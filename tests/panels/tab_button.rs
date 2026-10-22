//! The tab-bar maximize entry: every tabbed leaf's bar grows the
//! button, clicking it reaches the `panel.toggle_maximize` operator
//! with the leaf's active window, and the glyph tracks whether its own
//! leaf is the maximized one.

use bevy::camera::{NormalizedRenderTarget, RenderTarget};
use bevy::picking::{
    backend::HitData,
    events::{Pointer, PointerClick},
    pointer::{Location, PointerButton, PointerId},
};
use bevy::prelude::*;
use jackdaw_feathers::icons::Icon;
use jackdaw_feathers::tokens;
use jackdaw_panels::area::DockAreaStyle;
use jackdaw_panels::maximize::MaximizedLeaf;
use jackdaw_panels::reconcile::NodeBinding;
use jackdaw_panels::tabs::{DockTabMaximizeButton, DockTabMaximizeIcon};
use jackdaw_panels::tree::{DockTree, NodeId};

use crate::{INSPECTOR, editor_app, settle, toggle};

/// Every maximize button paired with the tree leaf its bar belongs to.
fn buttons(world: &mut World) -> Vec<(Entity, NodeId)> {
    let mut q = world.query::<(Entity, &DockTabMaximizeButton)>();
    q.iter(world)
        .filter_map(|(entity, button)| {
            world
                .get::<NodeBinding>(button.area_entity)
                .map(|binding| (entity, binding.0))
        })
        .collect()
}

/// The button belonging to `leaf`, with the assertion message it
/// deserves when it is missing.
fn button_for(world: &mut World, leaf: NodeId) -> Entity {
    buttons(world)
        .into_iter()
        .find(|(_, node)| *node == leaf)
        .map(|(entity, _)| entity)
        .unwrap_or_else(|| panic!("no maximize button bound to leaf {leaf:?}"))
}

/// (leaf, glyph text, glyph color) for every tab bar's maximize icon.
fn glyph_states(world: &mut World) -> Vec<(NodeId, String, Color)> {
    buttons(world)
        .into_iter()
        .map(|(entity, leaf)| {
            let children: Vec<Entity> = world
                .get::<Children>(entity)
                .map(|c| c.iter().collect())
                .unwrap_or_default();
            let glyph = children
                .into_iter()
                .find(|child| world.get::<DockTabMaximizeIcon>(*child).is_some())
                .expect("the button carries a maximize glyph");
            (
                leaf,
                world.get::<Text>(glyph).expect("glyph has text").0.clone(),
                world.get::<TextColor>(glyph).expect("glyph has a color").0,
            )
        })
        .collect()
}

/// Click `entity` the way a user does: the `PointerClick` the tab bar
/// observers watch for.
fn click(world: &mut World, entity: Entity) {
    let window = world
        .query_filtered::<Entity, With<bevy::window::PrimaryWindow>>()
        .single(world)
        .expect("headless apps still have a primary window");
    let target: NormalizedRenderTarget = RenderTarget::Window(bevy::window::WindowRef::Primary)
        .normalize(Some(window))
        .expect("the primary window normalizes");
    world.trigger(PointerClick {
        entity,
        pointer: Pointer::new(
            PointerId::Mouse,
            Location {
                target,
                position: Vec2::ZERO,
            },
        ),
        button: PointerButton::Primary,
        hit: HitData::new(Entity::PLACEHOLDER, 0.0, None, None),
        duration: core::time::Duration::ZERO,
        count: 1,
    });
}

/// One button per tabbed leaf of the materialized tree — no more (the
/// icon sidebar carries its own affordances), no fewer.
#[test]
fn every_tabbed_leaf_bar_grows_a_maximize_button() {
    let mut app = editor_app();

    let mut expected: Vec<NodeId> = app
        .world()
        .resource::<DockTree>()
        .leaves()
        .filter(|(_, leaf)| leaf.style == DockAreaStyle::TabBar)
        .map(|(id, _)| id)
        .collect();
    expected.sort_unstable_by_key(|id| id.0);
    assert!(!expected.is_empty(), "the default tree has tabbed leaves");

    let mut found: Vec<NodeId> = buttons(app.world_mut())
        .into_iter()
        .map(|(_, leaf)| leaf)
        .collect();
    found.sort_unstable_by_key(|id| id.0);
    assert_eq!(
        found, expected,
        "exactly the tabbed leaves carry a maximize button"
    );
}

/// The maximized leaf's button offers restore (Minimize glyph, accent
/// tint); every other bar keeps the expand glyph. Restoring brings
/// every bar back to the expand glyph.
#[test]
fn the_maximized_leaf_s_button_swaps_to_the_restore_glyph() {
    let mut app = editor_app();
    let expand = String::from(Icon::Maximize.unicode());
    let restore = String::from(Icon::Minimize.unicode());

    let leaf = app
        .world()
        .resource::<DockTree>()
        .find_leaf_with_window(INSPECTOR)
        .expect("the inspector has a leaf");

    toggle(&mut app, INSPECTOR);

    let states = glyph_states(app.world_mut());
    assert!(
        states.iter().any(|(node, _, _)| *node == leaf),
        "the maximized leaf's bar is on the button list"
    );
    for (node, glyph, color) in &states {
        if *node == leaf {
            assert_eq!(glyph, &restore, "the maximized bar offers restore");
            assert_eq!(*color, tokens::ACCENT_BLUE, "restore is tinted");
        } else {
            assert_eq!(glyph, &expand, "other bars keep the expand glyph");
            assert_eq!(*color, tokens::TAB_INACTIVE_TEXT);
        }
    }

    toggle(&mut app, INSPECTOR);

    for (node, glyph, color) in glyph_states(app.world_mut()) {
        assert_eq!(glyph, expand, "bar of leaf {node:?} back to expand");
        assert_eq!(color, tokens::TAB_INACTIVE_TEXT);
    }
}

/// Clicking the button dispatches the operator for the bar's active
/// window: the leaf maximizes, and a second click restores it. This is
/// the whole observer path — marker lookup, binding, active-window
/// resolution — not a direct operator call. The press puts the cursor
/// on the panel, so the focus chain names it the way it would live.
#[test]
fn clicking_the_button_maximizes_and_restores_the_leaf() {
    let mut app = editor_app();
    let leaf = app
        .world()
        .resource::<DockTree>()
        .find_leaf_with_window(INSPECTOR)
        .expect("the inspector has a leaf");
    let button = button_for(app.world_mut(), leaf);
    app.world_mut()
        .insert_resource(jackdaw::panel_focus::LastPressedPanel(Some(
            INSPECTOR.to_string(),
        )));

    click(app.world_mut(), button);
    settle(&mut app);

    assert_eq!(
        app.world().resource::<MaximizedLeaf>().0,
        Some(leaf),
        "the click maximized the clicked bar's leaf"
    );
    // The maximized view shows the window the operator activated.
    let states = glyph_states(app.world_mut());
    let (_, glyph, _) = states
        .into_iter()
        .find(|(node, _, _)| *node == leaf)
        .expect("the maximized bar is on the button list");
    assert_eq!(glyph, String::from(Icon::Minimize.unicode()));

    click(app.world_mut(), button);
    settle(&mut app);

    assert_eq!(
        app.world().resource::<MaximizedLeaf>().0,
        None,
        "the second click restored the layout"
    );
}
