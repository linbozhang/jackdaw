//! Authored-asset lifecycle: dirty asset cards save on the same chain a
//! launch runs, and an asset-field edit sharing the scene tab's undo
//! history does not mark the tab dirty. The red halves of these ran red
//! on main (an asset push flipped the tab dirty through the total push
//! counter; no save leg existed for cards).

use std::path::PathBuf;

use bevy::prelude::*;
use jackdaw::asset_files::AssetFileKind;
use jackdaw::asset_index::{AssetEntry, AssetIndex, AssetValue};
use jackdaw::commands::CommandHistory;
use jackdaw::definition_assets::{DefinitionAssetEdit, SetDefinitionField, save_dirty_assets};
use jackdaw::scenes::operators::active_tab_modified;
use jackdaw_bsn::{BsnField, BsnStructData, BsnStructFields, BsnValue};

use crate::util;

/// One schema-backed asset value: a struct patch with one f32 field.
fn config_value(type_path: &str, speed: f32) -> AssetValue {
    AssetValue::Schema(Box::new(BsnStructData {
        type_path: type_path.to_string(),
        fields: BsnStructFields(vec![BsnField {
            name: "move_speed".to_string(),
            value: BsnValue::Float(speed.into()),
        }]),
    }))
}

fn asset_entry(path: &str, speed: f32) -> AssetEntry {
    AssetEntry {
        path: PathBuf::from(path),
        kind: "game_config".to_string(),
        type_path: "my_game::GameConfig".to_string(),
        file_kind: AssetFileKind::Asset {
            type_path: "my_game::GameConfig".to_string(),
        },
        value: config_value("my_game::GameConfig", speed),
        mtime: std::time::SystemTime::now(),
    }
}

/// A dirty card for `path` in a world whose project root is `assets`'s
/// parent.
fn dirty_card(world: &mut World, path: &str, speed: f32) {
    world
        .resource_mut::<AssetIndex>()
        .insert(asset_entry(path, speed));
    world.spawn(DefinitionAssetEdit {
        kind: "game_config".to_string(),
        name: "game-config".to_string(),
        type_path: "my_game::GameConfig".to_string(),
        path: PathBuf::from(path),
        dirty: true,
    });
}

/// An asset-field edit sharing the scene tab's history leaves the tab
/// clean, and still takes one undo slot: Ctrl+Z reaches it as before.
#[test]
fn an_asset_field_edit_does_not_dirty_the_scene_tab() {
    let mut app = util::editor_test_app();
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    // One scene tab to watch, opened the way the editor opens one.
    use crate::util::OperatorResultExt;
    jackdaw::boot_ops::run_op_clause(app.world_mut(), "scene.new")
        .expect("a new scene opens")
        .assert_finished();
    app.update();
    let world = app.world_mut();
    world
        .resource_mut::<CommandHistory>()
        .push_executed(Box::new(SetDefinitionField {
            path: PathBuf::from("game-config.bsn"),
            type_path: "my_game::GameConfig".to_string(),
            field_path: "move_speed".to_string(),
            old_json: serde_json::json!(1.0),
            new_json: serde_json::json!(2.5),
            rebuilds_rows: false,
        }));
    // The undo entry exists: undo still reaches the asset edit.
    assert_eq!(
        world.resource::<CommandHistory>().undo_stack.len(),
        1,
        "the asset edit is on the undo stack"
    );
    let before = world.resource::<CommandHistory>().scene_pushes();
    assert_eq!(
        before, 0,
        "an asset-field push is not a scene-document push"
    );
    assert!(
        !active_tab_modified(world),
        "the scene tab stays clean: the tab's dirty flag describes its document, not the shared history"
    );
    // And the watcher agrees over frames.
    for _ in 0..5 {
        app.update();
    }
    let scenes = app.world().resource::<jackdaw::scenes::Scenes>();
    let tab = &scenes.tabs[scenes.active];
    assert!(!tab.dirty, "the watcher leaves the tab clean too");
}

/// The same protection on the *saved-baseline* path (QA-1): a tab with
/// a save baseline — every opened or saved scene, the form the failure
/// actually took live — stays clean when an asset-field push climbs
/// the shared history above the baseline. The first version of the
/// protection only covered the baseline-less path; the watcher's
/// `Some(_)` arm used to flip dirty on any depth change regardless of
/// what pushed.
#[test]
fn a_saved_scene_stays_clean_when_an_asset_field_edits_the_shared_history() {
    let mut app = util::editor_test_app();
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    use crate::util::OperatorResultExt;
    jackdaw::boot_ops::run_op_clause(app.world_mut(), "scene.new")
        .expect("a new scene opens")
        .assert_finished();
    app.update();

    // Give the tab a save baseline by hand — what a save or load leaves
    // behind — pinned at the current depth and scene-push count.
    {
        let mut scenes = app
            .world_mut()
            .get_resource_mut::<jackdaw::scenes::Scenes>()
            .unwrap();
        let active = scenes.active;
        let tab = &mut scenes.tabs[active];
        tab.saved_doc_hash = Some(42);
        tab.saved_undo_len = 0;
        tab.saved_scene_pushes = 0;
        tab.observed_undo_len = 0;
        tab.observed_pushes = 0;
        tab.dirty = false;
    }

    // The asset-field push: depth above the baseline, scene_pushes
    // unchanged.
    app.world_mut()
        .resource_mut::<CommandHistory>()
        .push_executed(Box::new(SetDefinitionField {
            path: PathBuf::from("game-config.bsn"),
            type_path: "my_game::GameConfig".to_string(),
            field_path: "move_speed".to_string(),
            old_json: serde_json::json!(1.0),
            new_json: serde_json::json!(2.5),
            rebuilds_rows: false,
        }));
    for _ in 0..5 {
        app.update();
    }
    let scenes = app.world().resource::<jackdaw::scenes::Scenes>();
    let tab = &scenes.tabs[scenes.active];
    assert!(
        !tab.dirty,
        "a saved tab stays clean when only an asset field climbed the history (QA-1)"
    );
}

/// Undoing below the baseline still reads dirty — the protection is
/// about *what* pushed, not about depth being sacred: an undo withdrew
/// a scene command, which changed the document.
#[test]
fn undoing_below_the_saved_baseline_still_marks_the_tab_dirty() {
    let mut app = util::editor_test_app();
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    use crate::util::OperatorResultExt;
    jackdaw::boot_ops::run_op_clause(app.world_mut(), "scene.new")
        .expect("a new scene opens")
        .assert_finished();
    app.update();

    // A baseline above the current depth: the saved state held one more
    // scene command than the stack now does (the shape after an undo —
    // observed_undo_len still names the pre-undo depth the watcher last
    // saw).
    {
        let mut scenes = app
            .world_mut()
            .get_resource_mut::<jackdaw::scenes::Scenes>()
            .unwrap();
        let active = scenes.active;
        let tab = &mut scenes.tabs[active];
        tab.saved_doc_hash = Some(42);
        tab.saved_undo_len = 2;
        tab.saved_scene_pushes = 0;
        tab.observed_undo_len = 1;
        tab.observed_pushes = 0;
        tab.dirty = false;
    }
    for _ in 0..5 {
        app.update();
    }
    let scenes = app.world().resource::<jackdaw::scenes::Scenes>();
    let tab = &scenes.tabs[scenes.active];
    assert!(
        tab.dirty,
        "an undo past the saved depth changed the document and reads dirty"
    );
}

/// A dirty card saves through the launch chain's asset leg: the file on
/// disk carries the card's value, not the one the last save wrote.
#[test]
fn a_dirty_card_writes_its_value_to_disk() {
    let tmp = tempfile::tempdir().expect("tempdir");
    let assets = tmp.path().join("assets");
    std::fs::create_dir_all(&assets).expect("assets dir");
    // The stale file the last save left.
    std::fs::write(assets.join("game-config.bsn"), "stale").expect("stale file");

    let mut app = util::editor_test_app();
    jackdaw::project::set_open_project_assets_dir(Some(assets.clone()));
    {
        let world = app.world_mut();
        world.insert_resource(jackdaw::project::ProjectRoot {
            root: tmp.path().to_path_buf(),
            config: default(),
        });
        dirty_card(world, "game-config.bsn", 2.5);
    }
    let failures = save_dirty_assets(app.world_mut());
    jackdaw::project::set_open_project_assets_dir(None);
    assert!(failures.is_empty(), "the save succeeded: {failures:?}");
    let text = std::fs::read_to_string(assets.join("game-config.bsn")).expect("the file");
    assert!(
        text.contains("move_speed: 2.5"),
        "the card's value reached the file, got: {text}"
    );
    assert!(
        !jackdaw::definition_assets::open_card_has_unsaved_edits(app.world()),
        "a card that saved is no longer dirty"
    );
}

/// A save that cannot happen is reported and the card stays dirty, so
/// the next attempt retries. Injected as a dirty card whose file the
/// index does not know — the first step of the save refuses, the same
/// branch an unreadable file or a full disk takes.
#[test]
fn an_unwritable_card_reports_and_stays_dirty() {
    let mut app = util::editor_test_app();
    // A dirty card whose path the index does not carry: the save chain
    // has nothing to write from.
    app.world_mut().spawn(DefinitionAssetEdit {
        kind: "game_config".to_string(),
        name: "game-config".to_string(),
        type_path: "my_game::GameConfig".to_string(),
        path: PathBuf::from("game-config.bsn"),
        dirty: true,
    });

    let failures = save_dirty_assets(app.world_mut());
    assert!(
        !failures.is_empty(),
        "the failed save is reported, not swallowed"
    );
    assert!(
        failures.iter().any(|named| named.contains("game-config")),
        "the failure names the file: {failures:?}"
    );
    let mut edits = app.world_mut().query::<&DefinitionAssetEdit>();
    assert!(
        edits.iter(app.world()).any(|edit| edit.dirty),
        "the card stays dirty for the next attempt"
    );
}
