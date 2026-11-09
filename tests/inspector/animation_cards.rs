//! The animation cards in the inspector: what an `AnimationSet` and an
//! `AnimationGraphRef` say about the project around them.
//!
//! A state naming a clip its source does not hold, and a graph reference
//! naming no file, badge the card in place — the way the bindings card
//! badges a row — instead of waiting for a Play to say it at run time.

use crate::util;

use bevy::picking::hover::Hovered;
use bevy::prelude::*;
use jackdaw::project_types::ProjectTypes;
use jackdaw::selection::Selection;
use jackdaw_animation_runtime::{AnimationGraphRef, AnimationSet, AnimationStateDef};
use jackdaw_feathers::tokens;
use jackdaw_feathers::tooltip::Tooltip;
use jackdaw_schema::ProjectSchema;

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// A selected, document-tracked entity carrying `components`, with an
/// inspector mounted, so the real dispatch builds its cards. Returns the app,
/// the selection, and the inspector's content root every card hangs under.
fn app_with(components: impl Bundle) -> (App, Entity, Entity) {
    let mut app = util::editor_test_app();
    {
        let native = jackdaw::project_types::native_type_paths(
            &app.world().resource::<AppTypeRegistry>().read(),
        );
        app.world_mut()
            .resource_mut::<ProjectTypes>()
            .update(&ProjectSchema::default(), &native);
    }
    let root = app
        .world_mut()
        .spawn(jackdaw::layout::inspector_components_content())
        .id();
    let entity = app
        .world_mut()
        .spawn((Name::new("rig"), Node::default(), components))
        .id();
    // An authored entity is what puts the animation types in the inspector's
    // authored-type filter.
    jackdaw::scene_io::register_entity_in_ast(app.world_mut(), entity);
    let world = app.world_mut();
    world.resource_scope(|world, mut selection: Mut<Selection>| {
        let mut commands = world.commands();
        selection.select_single(&mut commands, entity);
    });
    world.flush();
    app.update();
    app.update();
    (app, entity, root)
}

fn descendants(world: &mut World, root: Entity) -> Vec<Entity> {
    let mut out = Vec::new();
    let mut stack = vec![root];
    let mut query = world.query::<&Children>();
    while let Some(entity) = stack.pop() {
        if entity != root {
            out.push(entity);
        }
        if let Ok(children) = query.get(world, entity) {
            let kids: Vec<Entity> = children.iter().collect();
            stack.extend(kids.into_iter().rev());
        }
    }
    out
}

/// The one entity under `root` whose `Text` is exactly `needle`.
fn with_text(world: &mut World, root: Entity, needle: &str) -> Option<Entity> {
    descendants(world, root).into_iter().find(|entity| {
        world
            .get::<Text>(*entity)
            .is_some_and(|text| text.0 == needle)
    })
}

/// The texts under `root` painted in the error color.
fn error_texts(world: &mut World, root: Entity) -> Vec<String> {
    descendants(world, root)
        .into_iter()
        .filter(|entity| {
            world
                .get::<TextColor>(*entity)
                .is_some_and(|color| color.0 == tokens::TEXT_ERROR)
        })
        .filter_map(|entity| world.get::<Text>(entity).map(|text| text.0.clone()))
        .collect()
}

/// The badge on the one row whose `Text` is `text`, read the way the renderer
/// reads it. `Hovered` is opt-in and the tooltip system queries
/// `(Entity, &Tooltip, &Hovered)`, so a `Tooltip` sitting on its own is a
/// badge nobody can see.
fn row_badge(world: &mut World, root: Entity, text: &str) -> Option<String> {
    let mut query = world.query::<(&Tooltip, &Hovered)>();
    let row = descendants(world, root).into_iter().find(|entity| {
        world
            .get::<Text>(*entity)
            .is_some_and(|carry| carry.0 == text)
    });
    row.and_then(|entity| {
        query
            .get(world, entity)
            .ok()
            .map(|(tooltip, _)| tooltip.title.clone())
    })
}

// ---------------------------------------------------------------------------
// The badges: broken references that say so
// ---------------------------------------------------------------------------

const MISSING: &str = "models/missing.glb";

fn set_naming_nothing() -> AnimationSet {
    AnimationSet {
        sources: vec![MISSING.to_string()],
        states: vec![AnimationStateDef {
            name: "walk".to_string(),
            source: 0,
            clip: "Walk_Loop".to_string(),
            ..Default::default()
        }],
        default_state: "walk".to_string(),
        ..Default::default()
    }
}

#[test]
fn a_set_naming_a_source_file_the_project_does_not_hold_badges_the_row() {
    let (mut app, _, root) = app_with(set_naming_nothing());

    // The card itself is on screen: its Convert action built.
    assert!(with_text(app.world_mut(), root, "Convert to graph").is_some());

    let expected =
        format!("animation state `walk` names source `{MISSING}`, which is not in the project");
    assert_eq!(
        error_texts(app.world_mut(), root),
        vec![expected.clone()],
        "the state naming a file the project does not hold says so on the card"
    );
    assert_eq!(
        row_badge(app.world_mut(), root, &expected).as_deref(),
        Some(expected.as_str()),
        "the badge is the row, read the way the tooltip renderer reads it"
    );
}

#[test]
fn a_graph_reference_naming_no_file_badges_the_card() {
    let (mut app, _, root) = app_with(AnimationGraphRef {
        path: "rigs/nope.bsn".to_string(),
        ..Default::default()
    });

    // The picker built: the project holds no graph files, and the held path
    // is not among anything, so nothing highlights.
    assert!(with_text(app.world_mut(), root, "rigs/nope.bsn").is_none());
    assert!(with_text(app.world_mut(), root, "No graph file in this project yet.").is_some());

    let expected = "no graph file named `rigs/nope.bsn` in this project";
    assert_eq!(
        error_texts(app.world_mut(), root),
        vec![expected.to_string()],
        "the reference naming no graph file says so on the card"
    );
    assert_eq!(
        row_badge(app.world_mut(), root, expected).as_deref(),
        Some(expected),
        "the badge is the row, read the way the tooltip renderer reads it"
    );
}

#[test]
fn a_set_whose_references_resolve_draws_nothing() {
    let (mut app, _, root) = app_with(AnimationSet::default());

    assert!(with_text(app.world_mut(), root, "Convert to graph").is_some());
    assert!(error_texts(app.world_mut(), root).is_empty());
}
