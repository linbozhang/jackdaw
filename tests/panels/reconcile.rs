//! How the maximize state follows the tree changing underneath it:
//! workspace switches clear it outright, a vanishing leaf self-heals on
//! the next reconcile, and opening a window into a hidden leaf restores
//! the layout first.

use bevy::prelude::*;
use jackdaw::prelude::*;
use jackdaw_panels::WorkspaceRegistry;
use jackdaw_panels::maximize::MaximizedLeaf;
use jackdaw_panels::tree::{DockTree, Edge};
use jackdaw_panels::workspace::WorkspaceChanged;

use crate::util::OperatorResultExt;
use crate::{INSPECTOR, editor_app, leaf_displays, settle, toggle};

/// Switching workspaces replaces the whole tree, so the maximized id
/// can't be trusted to mean the same node — it is cleared with the swap.
#[test]
fn switching_workspaces_clears_the_maximized_leaf() {
    let mut app = editor_app();
    toggle(&mut app, INSPECTOR);
    assert!(app.world().resource::<MaximizedLeaf>().0.is_some());

    let old = app
        .world()
        .resource::<WorkspaceRegistry>()
        .active
        .clone()
        .expect("an active workspace");
    app.world_mut().trigger(WorkspaceChanged {
        old: Some(old),
        new: "level_design".to_string(),
    });
    settle(&mut app);

    assert_eq!(
        app.world().resource::<MaximizedLeaf>().0,
        None,
        "the maximized id went with the outgoing tree"
    );
    let tree = app.world().resource::<DockTree>();
    assert!(
        tree.find_by_area_id("split.jackdaw.viewport.qv_top")
            .is_some(),
        "precondition check: the live tree is the level-design quad view"
    );
}

/// Closing the maximized leaf's last tab collapses the leaf, and the
/// next reconcile notices via validation: maximize ends and every
/// sibling comes back, with no operator involved.
#[test]
fn a_maximized_leaf_draining_ends_the_maximize() {
    let mut app = editor_app();

    // A runtime-split leaf (not persistent): draining it removes it
    // from the tree. Park the project window there alone so the
    // window id names exactly one leaf.
    let (new_leaf, tab) = {
        let mut tree = app.world_mut().resource_mut::<DockTree>();
        tree.remove_window_kind("jackdaw.project");
        let center = tree
            .find_by_area_id("center")
            .expect("the default tree has a center area");
        tree.split(center, Edge::Right, "jackdaw.project".to_string())
            .expect("splitting the center works")
    };
    settle(&mut app);

    toggle(&mut app, "jackdaw.project");
    assert_eq!(
        app.world().resource::<MaximizedLeaf>().0,
        Some(new_leaf),
        "precondition: the runtime leaf is maximized"
    );

    app.world_mut()
        .operator("dock.close_tab")
        .param("tab_id", tab.0 as i64)
        .call()
        .expect("dock.close_tab dispatch resolves")
        .assert_finished();
    settle(&mut app);

    assert_eq!(
        app.world().resource::<MaximizedLeaf>().0,
        None,
        "validation self-healed the maximize away with the leaf"
    );
    for (key, visible) in leaf_displays(app.world_mut()) {
        assert!(visible, "leaf {key} came back visible");
    }
}

/// A persistent leaf (a built-in dock region) stays in the tree when
/// its windows go, so the maximize holds: same behavior as an empty
/// persistent placeholder outside maximize mode.
#[test]
fn a_maximized_persistent_leaf_keeps_the_maximize_when_emptied() {
    let mut app = editor_app();
    toggle(&mut app, INSPECTOR);
    let leaf = app
        .world()
        .resource::<DockTree>()
        .find_leaf_with_window(INSPECTOR)
        .expect("the inspector's leaf");

    {
        let mut tree = app.world_mut().resource_mut::<DockTree>();
        let windows: Vec<String> = tree
            .get(leaf)
            .and_then(|n| n.as_leaf())
            .map(|l| l.windows.iter().map(|w| w.window_id.clone()).collect())
            .unwrap_or_default();
        assert!(!windows.is_empty(), "precondition: the leaf holds panels");
        for window in windows {
            tree.remove_window_kind(&window);
        }
    }
    settle(&mut app);

    assert_eq!(
        app.world().resource::<MaximizedLeaf>().0,
        Some(leaf),
        "the persistent leaf survives empty, so the maximize stands"
    );
    // And the placeholder itself is still on screen.
    for (key, visible) in leaf_displays(app.world_mut()) {
        let expected = key.starts_with("right_sidebar");
        assert_eq!(visible, expected, "leaf {key}");
    }
}

/// Focusing a window whose leaf is hidden as a maximize sibling (the
/// auto-open path PIE uses for the Game panel) restores the layout
/// first instead of activating a tab nobody can see.
#[test]
fn opening_a_window_into_a_hidden_leaf_restores_the_layout_first() {
    let mut app = editor_app();
    toggle(&mut app, INSPECTOR);
    assert!(app.world().resource::<MaximizedLeaf>().0.is_some());

    // The project window lives in the bottom dock, hidden right now.
    assert!(
        app.world()
            .resource::<DockTree>()
            .find_leaf_with_window("jackdaw.project")
            .is_some(),
        "precondition: the project window is docked"
    );
    jackdaw::open_window_in_default_area_if_absent(app.world_mut(), "jackdaw.project");
    settle(&mut app);

    assert_eq!(
        app.world().resource::<MaximizedLeaf>().0,
        None,
        "the open into a hidden leaf ended the maximize"
    );
    for (key, visible) in leaf_displays(app.world_mut()) {
        assert!(visible, "leaf {key}");
    }
}

/// A window id no leaf holds cancels the toggle and leaves the state
/// alone. Already maximized, the toggle half wins over the parameter:
/// whatever the id says, the operator restores.
#[test]
fn an_unknown_window_cancels_and_a_stale_id_still_restores() {
    let mut app = editor_app();

    app.world_mut()
        .operator("panel.toggle_maximize")
        .param("window_id", "jackdaw.no.such_window")
        .call()
        .expect("dispatch resolves")
        .assert_cancelled();
    assert_eq!(
        app.world().resource::<MaximizedLeaf>().0,
        None,
        "the failed toggle changed nothing"
    );

    toggle(&mut app, INSPECTOR);
    app.world_mut()
        .operator("panel.toggle_maximize")
        .param("window_id", "jackdaw.no.such_window")
        .call()
        .expect("dispatch resolves")
        .assert_finished();
    assert_eq!(
        app.world().resource::<MaximizedLeaf>().0,
        None,
        "maximized, the operator restores no matter the parameter"
    );
}
