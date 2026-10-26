//! The stop-restore guards: after PIE stops, the preview world is the
//! authored scene again (same entity names, no ephemerals, no projection
//! leftovers), the selection is rebuilt over the new entity ids instead of
//! holding dead handles, nothing reaches the disk or the document, and a
//! scene saved before play leaves no journal entry behind (a kill after
//! the save recovers from the file, not the journal).

use bevy::prelude::*;
use jackdaw::boot_ops::{run_op_clause, run_op_clause_as_user};
use jackdaw::scene_io::session_journal::{self, JOURNAL_DEBOUNCE};
use jackdaw::scenes::Scenes;
use jackdaw_scene_types::SceneNodeId;

use crate::util::{self, OperatorResultExt as _};

/// Each test runs a full editor and a scene load: heavy enough that a
/// parallel pile of them pushes the binary's timing-sensitive tests (the
/// journal write budget) over their limits. They share the binary-wide
/// heavy-editor lock with the other editor-booting module.
use crate::HEAVY_EDITOR_LOCK as STOP_RESTORE_LOCK;

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

fn place_rock(app: &mut App, x: f64) {
    run_op_clause_as_user(
        app.world_mut(),
        &format!("prefab.spawn_instance path=prefabs/rock.bsn pos_x={x} pos_y=0 pos_z=0"),
    )
    .expect("the placement dispatched")
    .assert_finished();
    app.update();
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

/// Every scene entity's name (the editor's own chrome — gizmo renderers,
/// input contexts — never carries a `SceneNodeId`), in a stable order.
fn scene_entity_names(app: &mut App) -> Vec<String> {
    let mut names = app.world_mut().query_filtered::<&Name, With<SceneNodeId>>();
    let mut found: Vec<String> = names
        .iter(app.world())
        .map(|n| n.as_str().to_string())
        .collect();
    found.sort();
    found
}

use jackdaw_api::pie::PlayState;

// --------------------------------------------------------------- stop (1) --

/// What a live session leaves behind: an ephemeral entity (a game-private
/// actor the user picked in Live view), the projection entry pointing at
/// it, an authored entity re-parented under it (the projection's own
/// parenting), and a selection holding both. This is the world the stop
/// chain has to clean up.
fn install_live_projection_state(app: &mut App) -> (Entity, Entity) {
    let zone = {
        let mut query = app
            .world_mut()
            .query_filtered::<Entity, With<SceneNodeId>>();
        query
            .iter(app.world())
            .next()
            .expect("the authored scene entity")
    };
    let ephemeral = app
        .world_mut()
        .spawn((
            jackdaw::pie_projection::PieEphemeral,
            Name::new("GameActor"),
            Transform::default(),
        ))
        .id();
    // The projection parents authored previews under game-spawned roots.
    if let Ok(mut authored) = app.world_mut().get_entity_mut(zone) {
        authored.insert(ChildOf(ephemeral));
    }
    // The user's selection covers the authored entity and the game actor.
    let selection = jackdaw::selection::Selection {
        entities: vec![zone, ephemeral],
    };
    app.world_mut().insert_resource(selection);
    if let Ok(mut e) = app.world_mut().get_entity_mut(zone) {
        e.insert(jackdaw::selection::Selected);
    }
    if let Ok(mut e) = app.world_mut().get_entity_mut(ephemeral) {
        e.insert(jackdaw::selection::Selected);
    }
    (zone, ephemeral)
}

/// After a stop, no ephemeral entity and no projection entry survives, and
/// the authored scene's entity names are exactly what they were before the
/// play: the AST is the baseline that comes back.
#[test]
fn stop_clears_the_projection_and_restores_the_authored_names() {
    let _guard = stop_lock();
    let (mut app, _tmp) = editor();
    let before = scene_entity_names(&mut app);
    assert!(
        before.iter().any(|n| n == "Zone"),
        "the premise: the authored scene is in front"
    );

    let (_zone, _ephemeral) = install_live_projection_state(&mut app);
    play_then_stop(&mut app);

    let after = scene_entity_names(&mut app);
    assert!(
        !after.iter().any(|n| n == "GameActor"),
        "the game-private entity is gone: {after:?}"
    );
    assert_eq!(
        before, after,
        "the authored scene's entities are exactly restored"
    );
    assert!(
        app.world()
            .resource::<jackdaw::pie_projection::PieProjection>()
            .by_bits
            .is_empty(),
        "no projection entries survive"
    );
    let mut ephemerals = app
        .world_mut()
        .query_filtered::<Entity, With<jackdaw::pie_projection::PieEphemeral>>();
    assert_eq!(
        ephemerals.iter(app.world()).count(),
        0,
        "no PieEphemeral entities survive"
    );
}

/// After a stop, the selection holds live entity handles only: the
/// respawned authored entity it names, never a despawned one, and never a
/// dangling id. Red on a revert that respawns ids without rebuilding the
/// selection (every handle would be dead).
#[test]
fn stop_rebuilds_the_selection_over_the_new_entity_ids() {
    let _guard = stop_lock();
    let (mut app, _tmp) = editor();
    let (zone, _ephemeral) = install_live_projection_state(&mut app);
    let zone_node = app
        .world()
        .get::<SceneNodeId>(zone)
        .copied()
        .expect("the authored entity carries its stable node id");

    play_then_stop(&mut app);

    let selection = app
        .world()
        .resource::<jackdaw::selection::Selection>()
        .entities
        .clone();
    assert!(!selection.is_empty(), "the selection survives the stop");
    for entity in &selection {
        assert!(
            app.world().get_entity(*entity).is_ok(),
            "no dangling selection handles: {entity:?}"
        );
        assert!(
            app.world()
                .get::<jackdaw::selection::Selected>(*entity)
                .is_some(),
            "a selected entity carries the Selected marker"
        );
    }
    // The authored entity is selected again, under its new id.
    let mut still_selected = app
        .world_mut()
        .query_filtered::<Entity, With<jackdaw::selection::Selected>>();
    let selected_ids: Vec<SceneNodeId> = still_selected
        .iter(app.world())
        .filter_map(|e| app.world().get::<SceneNodeId>(e).copied())
        .collect();
    assert!(
        selected_ids.contains(&zone_node),
        "the authored selection is restored over the respawned entity"
    );
    // No Selected marker lingers on a despawned entity — markers live on
    // entities, so this is implied by the survival check above plus the
    // count equality below.
    assert_eq!(
        selected_ids.len(),
        selection.len(),
        "the marker set and the selection resource agree"
    );
}

/// Stop writes nothing: the tab's dirty flag, the document emitter, and
/// the file on disk are all byte-identical before and after a play session
/// that only projected state (the authored side of acceptance ③, at the
/// headless layer the stop chain itself).
#[test]
fn stop_touches_neither_document_nor_disk() {
    let _guard = stop_lock();
    let (mut app, tmp) = editor();
    let disk_before = std::fs::read(tmp.path().join("assets/zone.bsn")).unwrap();
    let dirty_before = {
        let scenes = app.world().resource::<Scenes>();
        scenes.tabs[scenes.active].dirty
    };

    let (_zone, _ephemeral) = install_live_projection_state(&mut app);
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

// ------------------------------------------------------- journal (N-QA4) --

/// A scene saved before play leaves no journal entry: the kill-and-restart
/// recovery reads the file, not a journal the save already spent. The
/// dirty tab journals first (the premise), then the save spends it.
#[test]
fn a_save_before_play_spends_the_journal_entry() {
    let _guard = stop_lock();
    let (mut app, tmp) = editor();
    session_journal::begin_session(app.world_mut(), tmp.path());
    app.insert_resource(bevy::time::TimeUpdateStrategy::ManualDuration(
        JOURNAL_DEBOUNCE + std::time::Duration::from_millis(100),
    ));

    place_rock(&mut app, 1.0);
    util::update_until(
        &mut app,
        "the journal to land",
        std::time::Duration::from_secs(10),
        |app| {
            session_journal::session_dir(app.world())
                .map(|dir| dir.join("journal.json").is_file())
                .unwrap_or(false)
        },
    );
    let dir_premise = session_journal::session_dir(app.world()).expect("the session dir");
    assert!(
        dir_premise.join("journal.json").is_file(),
        "the premise: the dirty tab is journaled"
    );

    // The save a Play under the save policy performs.
    assert!(
        jackdaw::scene_io::save_scene(app.world_mut()),
        "the scene saves"
    );
    app.update();

    let dir = session_journal::session_dir(app.world()).expect("the session dir");
    let after = session_journal::read_session_journal(&dir);
    let entries = after.map(|journal| journal.tabs.len()).unwrap_or(0);
    assert_eq!(
        entries, 0,
        "a saved scene leaves no journal entry for its tab"
    );
}
