//! What a save taken while maximized stores, and what a reload brings
//! back: the tree never knew about the maximize, so the saved layout is
//! the full un-maximized one, and a reload starts un-maximized.

use bevy::prelude::*;
use jackdaw::project::ProjectRoot;
use jackdaw_panels::WorkspacesPersist;
use jackdaw_panels::maximize::MaximizedLeaf;
use jackdaw_panels::tree::DockTree;

use crate::util;
use crate::{INSPECTOR, fractions, toggle};

/// The editor with a project root pointing at a scratch directory, so
/// the layout auto-save has somewhere to write that isn't the machine
/// of whoever runs the tests.
fn app_with_project() -> App {
    let mut app = util::editor_test_app();
    let root = std::env::temp_dir().join(format!("jackdaw_panels_persist_{}", std::process::id()));
    app.world_mut().insert_resource(ProjectRoot {
        root,
        config: default(),
    });
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    for _ in 0..4 {
        app.update();
    }
    util::fixed_frame_clock(&mut app);
    app
}

/// The saved layout after the 0.5s auto-save debounce, once it fires.
fn autosaved_layout(app: &mut App) -> WorkspacesPersist {
    util::update_until(
        app,
        "the layout auto-save to fire",
        std::time::Duration::from_secs(10),
        |app| {
            app.world()
                .resource::<ProjectRoot>()
                .config
                .layout
                .is_some()
        },
    );
    let layout = app
        .world()
        .resource::<ProjectRoot>()
        .config
        .layout
        .clone()
        .expect("the auto-save wrote a layout");
    serde_json::from_value(layout).expect("the layout parses as workspaces")
}

#[test]
fn saving_while_maximized_writes_the_unmaximized_tree() {
    let mut app = app_with_project();
    let fractions_before = fractions(app.world());

    toggle(&mut app, INSPECTOR);
    assert!(app.world().resource::<MaximizedLeaf>().0.is_some());

    let persist = autosaved_layout(&mut app);
    let active = persist.active.expect("an active workspace");
    let workspace = persist
        .workspaces
        .iter()
        .find(|w| w.id == active)
        .expect("the active workspace was saved");

    let mut saved: Vec<(u64, f32)> = workspace
        .tree
        .nodes
        .iter()
        .filter_map(|(id, n)| n.as_split().map(|s| (id.0, s.fraction)))
        .collect();
    saved.sort_by_key(|(id, _)| *id);
    assert_eq!(
        saved, fractions_before,
        "the saved layout is the full un-maximized arrangement"
    );
    assert!(
        workspace.tree.find_leaf_with_window(INSPECTOR).is_some(),
        "the maximized panel's own leaf was saved too"
    );
    assert_eq!(
        workspace.tree.leaves().count(),
        app.world().resource::<DockTree>().leaves().count(),
        "no leaf was dropped from the saved layout"
    );
}

#[test]
fn reloading_a_layout_starts_unmaximized() {
    let mut app = app_with_project();
    toggle(&mut app, INSPECTOR);
    autosaved_layout(&mut app);

    jackdaw::init_layout(app.world_mut());

    assert_eq!(
        app.world().resource::<MaximizedLeaf>().0,
        None,
        "maximize is session view state; a reload doesn't carry it"
    );
    for _ in 0..4 {
        app.update();
    }
    for (key, visible) in crate::leaf_displays(app.world_mut()) {
        assert!(visible, "leaf {key} is visible after reload");
    }
}
