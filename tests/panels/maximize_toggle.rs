//! Toggling maximize: the resource flips, every other leaf host hides,
//! the maximized leaf keeps its content visible, and a second toggle
//! brings the layout back with each split fraction bit-for-bit intact.

use bevy::prelude::*;
use jackdaw::prelude::*;
use jackdaw_panels::area::DockTabContent;
use jackdaw_panels::maximize::MaximizedLeaf;
use jackdaw_panels::tree::DockTree;

use crate::util::OperatorResultExt;
use crate::{INSPECTOR, editor_app, fractions, leaf_displays, settle, toggle};

#[test]
fn a_toggle_hides_the_siblings_and_a_second_restores_them() {
    let mut app = editor_app();
    let fractions_before = fractions(app.world());
    let displays_before = leaf_displays(app.world_mut());
    assert!(
        displays_before.iter().all(|(_, visible)| *visible),
        "precondition: the default layout is fully visible: {displays_before:?}"
    );
    let leaf = app
        .world()
        .resource::<DockTree>()
        .find_leaf_with_window(INSPECTOR)
        .expect("the inspector has a leaf");

    toggle(&mut app, INSPECTOR);

    assert_eq!(
        app.world().resource::<MaximizedLeaf>().0,
        Some(leaf),
        "the toggle records the inspector's leaf"
    );
    for (key, visible) in leaf_displays(app.world_mut()) {
        // All four canonical areas live in one tree, so the leaf keys
        // are stable; the inspector's key is the only visible one.
        let expected = key.starts_with("right_sidebar");
        assert_eq!(visible, expected, "leaf {key}");
    }
    assert_eq!(
        fractions(app.world()),
        fractions_before,
        "maximize is a view overlay: the tree's splits are untouched"
    );
    assert_active_content_visible(&mut app, leaf, INSPECTOR);

    toggle(&mut app, INSPECTOR);

    assert_eq!(app.world().resource::<MaximizedLeaf>().0, None);
    assert_eq!(
        leaf_displays(app.world_mut()),
        displays_before,
        "every leaf host comes back visible"
    );
    assert_eq!(
        fractions(app.world()),
        fractions_before,
        "each split fraction survived the round trip exactly"
    );
}

/// The tab the maximized leaf shows stays materialized and visible, so
/// the panel the user maximized is the one they see.
fn assert_active_content_visible(
    app: &mut App,
    leaf: jackdaw_panels::tree::NodeId,
    window_id: &str,
) {
    // The operator activates the named window's tab on maximize.
    let active = {
        let tree = app.world().resource::<DockTree>();
        let l = tree
            .get(leaf)
            .and_then(|n| n.as_leaf())
            .expect("the maximized leaf exists");
        let active_window = l
            .windows
            .iter()
            .find(|w| Some(w.id) == l.active)
            .map(|w| w.window_id.clone());
        assert_eq!(
            active_window.as_deref(),
            Some(window_id),
            "maximize brought the focused window's tab to the front"
        );
        l.active
    };

    let mut contents = app.world_mut().query::<(&DockTabContent, &Node)>();
    let (shown, total) = contents
        .iter(app.world())
        .fold((0, 0), |(shown, total), (c, n)| {
            if c.tab_id == active.unwrap() {
                (shown + usize::from(n.display == Display::Flex), total + 1)
            } else {
                (shown, total)
            }
        });
    assert_eq!(
        (shown, total),
        (1, 1),
        "the maximized tab's content is the one displayed"
    );
}

/// A layout already at a single leaf has nothing to maximize over, so
/// the operator cancels rather than recording a no-op state.
#[test]
fn a_root_leaf_layout_refuses_to_maximize() {
    let mut app = editor_app();
    // Drain the tree down to one leaf by hand (the default tree's
    // leaves are all persistent, so tabs move rather than collapse).
    {
        let mut tree = app.world_mut().resource_mut::<DockTree>();
        let root = tree.root.expect("the default tree has a root");
        let all_tabs: Vec<jackdaw_panels::tree::TabId> = tree.tabs().map(|(_, t)| t.id).collect();
        let survivor = tree
            .leaves_under(root)
            .into_iter()
            .next()
            .map(|(id, _)| id)
            .unwrap_or(root);
        for tab in all_tabs {
            tree.move_tab(tab, survivor);
        }
    }
    settle(&mut app);

    let window_id = {
        let tree = app.world().resource::<DockTree>();
        let root = tree.root.unwrap();
        let (_, leaf) = tree.leaves_under(root).into_iter().next().unwrap();
        // The move left several tabs on one leaf; any of them names it.
        leaf.windows[0].window_id.clone()
    };

    app.world_mut()
        .operator("panel.toggle_maximize")
        .param("window_id", window_id)
        .call()
        .expect("dispatch resolves")
        .assert_cancelled();
    assert_eq!(app.world().resource::<MaximizedLeaf>().0, None);
}
