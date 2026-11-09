//! The stop guard: after a play session in which nobody edited anything,
//! nothing reaches the disk and the tab's dirty flag does not move. (The
//! projection-era restore guards went with the Scene/Live model: edits made
//! during Play now stay in the document, and a project setting can revert
//! them on Stop.)

use bevy::prelude::*;
use jackdaw::boot_ops::run_op_clause;
use jackdaw::scenes::Scenes;

use crate::util::{self, OperatorResultExt as _};

/// Each test runs a full editor and a scene load: heavy enough that a
/// parallel pile of them pushes the binary's timing-sensitive tests (the
/// journal write budget) over their limits. They share the binary-wide
/// heavy-editor lock with the other editor-booting module.
use super::HEAVY_EDITOR_LOCK as STOP_RESTORE_LOCK;

fn stop_lock() -> std::sync::MutexGuard<'static, ()> {
    STOP_RESTORE_LOCK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

const ZONE_SCENE: &str = "#Zone\njackdaw_scene_types::node_id::SceneNodeId(4242)\nbevy_transform::components::transform::Transform\n";

/// An editor on a project with a saved scene in front. The clock steps past
/// the journal debounce every frame when a journal session is begun later.
fn editor() -> (App, tempfile::TempDir) {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-stop-restore-")
        .tempdir()
        .expect("temp dir");
    std::fs::create_dir_all(tmp.path().join("assets/prefabs")).expect("asset folders");
    std::fs::write(
        tmp.path().join("assets/prefabs/rock.bsn"),
        "#Rock\njackdaw::prefab::components::Prefab\nbevy_transform::components::transform::Transform\n",
    )
    .expect("the prefab");
    std::fs::write(tmp.path().join("assets/zone.bsn"), ZONE_SCENE).expect("the scene");

    let mut app = util::editor_test_app();
    app.world_mut()
        .insert_resource(jackdaw::project::ProjectRoot {
            root: tmp.path().to_path_buf(),
            config: default(),
        });
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    app.update();
    run_op_clause(app.world_mut(), "scene.open path=assets/zone.bsn")
        .expect("the scene opens")
        .assert_finished();
    util::settle_scene_load(&mut app);
    (app, tmp)
}

/// Drive the editor through Playing -> Stopped so the `OnEnter(Stopped)`
/// chain (the same one a real stop runs) executes.
fn play_then_stop(app: &mut App) {
    app.world_mut()
        .resource_mut::<NextState<PlayState>>()
        .set(PlayState::Playing);
    app.update();
    app.world_mut()
        .resource_mut::<NextState<PlayState>>()
        .set(PlayState::Stopped);
    app.update();
}

use jackdaw_api::pie::PlayState;

/// Stop writes nothing: the tab's dirty flag and the file on disk are
/// byte-identical before and after a play session in which nobody edited
/// anything.
#[test]
fn stop_touches_neither_document_nor_disk() {
    let _guard = stop_lock();
    let (mut app, tmp) = editor();
    let disk_before = std::fs::read(tmp.path().join("assets/zone.bsn")).unwrap();
    let dirty_before = {
        let scenes = app.world().resource::<Scenes>();
        scenes.tabs[scenes.active].dirty
    };

    play_then_stop(&mut app);

    let disk_after = std::fs::read(tmp.path().join("assets/zone.bsn")).unwrap();
    assert_eq!(
        disk_before, disk_after,
        "the file on disk is byte-identical across the play session"
    );
    let scenes = app.world().resource::<Scenes>();
    assert_eq!(
        scenes.tabs[scenes.active].dirty, dirty_before,
        "the dirty flag does not move"
    );
}
