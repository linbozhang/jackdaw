//! Atomic-write guards for the T04 save hardening: every authoritative
//! write path (prefab files, `project.json`, the JSN->BSN conversion) goes
//! through temp-file-plus-rename, a damaged `project.json` is backed up
//! before a default replaces it, an untitled tab's Save opens Save As
//! instead of discarding the tab, and orphan temp files are swept at
//! startup.
//!
//! The failure injection occupies the `.<name>.tmp-<pid>` slot that
//! `write_atomic` writes through: a save that goes through the atomic path
//! fails and leaves the old file byte-for-byte intact, while a bare
//! `fs::write` ploughs over the target and lets the test catch it.

use std::path::Path;
use std::time::{Duration, SystemTime};

use bevy::prelude::*;
use jackdaw::boot_ops::{run_op_clause, run_op_clause_as_user};
use jackdaw::scenes::{Scenes, confirm_dialog::PendingSaveAsClose};

use crate::util::{self, OperatorResultExt as _};

/// Where `write_atomic` stages this process's writes for `file`, every
/// slot of it occupied with a directory so the staged write fails without
/// any filesystem trickery that depends on the platform. The base name
/// plus all eight collision-suffix retries are held: a write that cannot
/// stage must fail, not write around the staging step.
fn occupy_temp_slot(parent: &Path, file: &str) -> std::path::PathBuf {
    let mut first = None;
    for suffix in std::iter::once(String::new()).chain((1..=8).map(|n| format!("-{n}"))) {
        let slot = parent.join(format!(".{file}.tmp-{}{suffix}", std::process::id()));
        std::fs::create_dir(&slot).expect("occupy the temp slot");
        first.get_or_insert(slot);
    }
    first.expect("at least the base slot")
}

/// An editor on a project holding a saved scene (open in front) and a
/// one-entry prefab the edits place instances of -- the same arrangement
/// the dirty matrix runs on.
fn editor() -> (App, tempfile::TempDir) {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-atomic-writes-")
        .tempdir()
        .expect("temp dir");
    std::fs::create_dir_all(tmp.path().join("assets/prefabs")).expect("asset folders");
    std::fs::write(
        tmp.path().join("assets/prefabs/rock.bsn"),
        "#Rock\nbevy_transform::components::transform::Transform\n",
    )
    .expect("the prefab");
    std::fs::write(
        tmp.path().join("assets/zone.bsn"),
        "#Zone\nbevy_transform::components::transform::Transform\n",
    )
    .expect("the scene");

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

/// One user edit: place a rock instance, a single snapshot entry.
fn place_rock(app: &mut App, x: f64) {
    run_op_clause_as_user(
        app.world_mut(),
        &format!("prefab.spawn_instance path=prefabs/rock.bsn pos_x={x} pos_y=0 pos_z=0"),
    )
    .expect("the placement dispatched")
    .assert_finished();
    app.update();
}

// --------------------------------------------------------------- N4 prefab --

/// A prefab save whose staged write fails must leave the old prefab file
/// byte-for-byte untouched (N4: the prefab path is inside the atomic
/// umbrella, not a bare `fs::write` over the live file).
#[test]
fn a_failed_prefab_save_keeps_the_old_file_byte_for_byte() {
    let dir = tempfile::tempdir().expect("temp dir");
    let prefab = dir.path().join("rock.bsn");
    const OLD: &[u8] = b"#Rock\nold prefab bytes\n";
    std::fs::write(&prefab, OLD).expect("seed the old prefab");
    occupy_temp_slot(dir.path(), "rock.bsn");

    let mut world = World::new();
    let mut cache = jackdaw::prefab::PrefabAstCache::default();
    cache.insert(
        &prefab,
        jackdaw_bsn::parse_bsn_text("#Rock\nbevy_transform::components::transform::Transform {}\n")
            .expect("prefab document parses"),
    );
    world.insert_resource(cache);

    let result = jackdaw::prefab::operators::save_prefab_to_disk(&mut world, &prefab);
    assert!(
        result.is_err(),
        "an occupied temp slot must fail the save rather than write around it"
    );
    assert_eq!(
        std::fs::read(&prefab).expect("the old file is still readable"),
        OLD,
        "the old prefab must survive the failed save byte for byte"
    );
}

// ------------------------------------------------------ project.json (Y9) --

/// A `project.json` save whose staged write fails must leave the previous
/// config byte-for-byte untouched (Y9: the config write is atomic).
#[test]
fn a_failed_project_config_save_keeps_the_old_file_byte_for_byte() {
    let dir = tempfile::tempdir().expect("temp dir");
    let config_dir = dir.path().join(".jackdaw");
    std::fs::create_dir_all(&config_dir).expect("config dir");
    let config_path = config_dir.join("project.json");
    const OLD: &str = "{\n  \"name\": \"kept\"\n}";
    std::fs::write(&config_path, OLD).expect("seed the old config");
    occupy_temp_slot(&config_dir, "project.json");

    let result = jackdaw::project::save_project_config(
        dir.path(),
        &jackdaw::project::ProjectConfig::default(),
    );
    assert!(
        result.is_err(),
        "an occupied temp slot must fail the config save rather than write around it"
    );
    assert_eq!(
        std::fs::read_to_string(&config_path).expect("the old config is still readable"),
        OLD,
        "the old project.json must survive the failed save byte for byte"
    );
}

// ----------------------------------------------------- jsn -> bsn (Y9/W9) --

/// A minimal legacy v2 scene, the layout every pre-conversion project has.
const LEGACY_V2_SCENE: &str = r#"{
    "jsn": {"format_version": [2, 0, 0], "editor_version": "0.4.0", "bevy_version": "0.18"},
    "metadata": {"name": "old"},
    "assets": {},
    "editor": null,
    "scene": [{
        "name": "Old",
        "transform": {
            "translation": [1.0, 2.0, 3.0],
            "rotation": [0.0, 0.0, 0.0, 1.0],
            "scale": [1.0, 1.0, 1.0]
        },
        "components": {}
    }]
}"#;

/// The conversion headless app of `tests/scenes/jsn_to_bsn.rs`, which is
/// all the reflection the converter needs.
fn convert_app() -> App {
    let mut app = App::new();
    app.add_plugins((MinimalPlugins, bevy::asset::AssetPlugin::default()));
    app.add_plugins(jackdaw_scene_types::SceneTypesPlugin {
        runtime_mesh_rebuild: false,
    });
    app.add_plugins(jackdaw_bsn::JackdawBsnPlugin);
    app
}

/// A conversion whose staged write fails must leave the old `.bsn` and the
/// legacy `.jsn` source exactly where they were (W9: the one scene write
/// path that did not go through `write_atomic`).
#[test]
fn a_failed_conversion_keeps_the_old_bsn_and_the_source_in_place() {
    let dir = tempfile::tempdir().expect("temp dir");
    let source = dir.path().join("level.jsn");
    let bsn = dir.path().join("level.bsn");
    std::fs::write(&source, LEGACY_V2_SCENE).expect("seed the legacy scene");
    const OLD: &[u8] = b"#Old\nprevious conversion\n";
    std::fs::write(&bsn, OLD).expect("seed the old bsn");
    occupy_temp_slot(dir.path(), "level.bsn");

    let mut app = convert_app();
    let result = jackdaw::jsn_to_bsn::convert_scene_file(app.world_mut(), &source);
    assert!(
        result.is_err(),
        "an occupied temp slot must fail the conversion rather than write around it"
    );
    assert_eq!(
        std::fs::read(&bsn).expect("the old bsn is still readable"),
        OLD,
        "the old .bsn must survive the failed conversion byte for byte"
    );
    assert!(
        source.is_file(),
        "the .jsn source must not be renamed to .bak when its .bsn never landed"
    );
    assert!(
        !dir.path().join("level.jsn.bak").exists(),
        "no backup must appear for a conversion that did not commit"
    );
}

/// A committed conversion writes the version stamp at the disk boundary,
/// the same provenance line a native scene save carries (W9).
#[test]
fn a_committed_conversion_carries_the_version_stamp() {
    let dir = tempfile::tempdir().expect("temp dir");
    let source = dir.path().join("level.jsn");
    std::fs::write(&source, LEGACY_V2_SCENE).expect("seed the legacy scene");

    let mut app = convert_app();
    let (bsn_path, report) = jackdaw::jsn_to_bsn::convert_scene_file(app.world_mut(), &source)
        .expect("the conversion commits");
    assert_eq!(report.entity_count, 1);

    let text = std::fs::read_to_string(&bsn_path).expect("the bsn landed");
    assert!(
        text.starts_with("// jackdaw "),
        "the converted .bsn must open with the version stamp:\n{text}"
    );
    let body = text
        .lines()
        .skip_while(|line| line.starts_with("// jackdaw"))
        .collect::<Vec<_>>()
        .join("\n");
    jackdaw_bsn::parse_bsn_text(&body).expect("the stamped document still parses");
}

// -------------------------------------------- damaged config recovery (Y9) --

/// Opening a project whose `project.json` is damaged (a crash left half a
/// JSON) must keep the damaged bytes under a `.corrupt-<ts>` name before
/// the default config replaces them, and say so on the status bar --
/// not silently overwrite the user's layout (Y9).
#[test]
fn a_damaged_project_json_is_backed_up_before_the_default_replaces_it() {
    let mut app = util::editor_test_app();
    let dir = tempfile::tempdir().expect("temp dir");
    let root = dir.path().to_path_buf();
    let config_dir = root.join(".jackdaw");
    std::fs::create_dir_all(&config_dir).expect("config dir");
    const DAMAGED: &str = "{\n  \"name\": \"half a write"; // truncated JSON
    let config_path = config_dir.join("project.json");
    std::fs::write(&config_path, DAMAGED).expect("seed the damaged config");

    jackdaw::project_select::transition_to_editor(app.world_mut(), root.clone());
    app.update();

    let mut backups: Vec<std::path::PathBuf> = std::fs::read_dir(&config_dir)
        .expect("config dir readable")
        .filter_map(|entry| entry.ok().map(|e| e.path()))
        .filter(|path| {
            path.file_name()
                .is_some_and(|name| name.to_string_lossy().starts_with("project.json.corrupt-"))
        })
        .collect();
    backups.sort();
    let backup = backups
        .pop()
        .expect("the damaged config was backed up, not overwritten");
    assert_eq!(
        std::fs::read_to_string(&backup).expect("the backup is readable"),
        DAMAGED,
        "the backup must hold exactly the damaged bytes"
    );

    let fresh = std::fs::read_to_string(&config_path).expect("a fresh config was written");
    serde_json::from_str::<serde_json::Value>(&fresh).expect("the fresh config parses");
    assert_ne!(
        fresh, DAMAGED,
        "the live config is no longer the damaged one"
    );

    let notice = app.world().resource::<jackdaw::status_bar::StatusNotice>();
    assert!(
        notice.text().contains("damaged"),
        "the status bar must tell the user what happened to their config: {}",
        notice.text()
    );
}

// ------------------------------------------------ untitled Save As (N8) --

/// Two tabs: the saved `zone.bsn` in front plus a fresh untitled one,
/// which is the arrangement a close with Save As has to survive. The
/// caller keeps the temp dir: the project's assets live in it.
fn editor_with_untitled_tab() -> (App, tempfile::TempDir) {
    let (mut app, tmp) = editor();
    run_op_clause(app.world_mut(), "scene.new")
        .expect("the untitled tab opens")
        .assert_finished();
    app.update();
    (app, tmp)
}

/// Saving an untitled tab from the close-confirmation dialog must open the
/// Save As flow and keep the tab open, not close it as if the user had
/// picked Discard (N8).
#[test]
fn an_untitled_tabs_save_opens_save_as_instead_of_discarding() {
    let (mut app, _tmp) = editor_with_untitled_tab();

    let untitled = app.world().resource::<Scenes>().active;
    assert!(
        app.world().resource::<Scenes>().tabs[untitled]
            .path
            .is_none(),
        "the new tab is untitled"
    );

    place_rock(&mut app, 1.0);
    assert!(
        app.world().resource::<Scenes>().tabs[untitled].dirty,
        "the edit lights the tab"
    );

    run_op_clause(app.world_mut(), "scene.close")
        .expect("the close is asked for")
        .assert_finished();
    app.update();
    assert_eq!(
        app.world()
            .resource::<jackdaw::scenes::confirm_dialog::PendingTabClose>()
            .tab_index,
        Some(untitled),
        "the close is pending on the confirm dialog"
    );

    jackdaw::scenes::confirm_dialog::apply_confirm_dialog_action(
        app.world_mut(),
        jackdaw::scenes::confirm_dialog::ConfirmDialogButton::Save,
        untitled,
    );

    assert_eq!(
        app.world().resource::<Scenes>().tabs.len(),
        2,
        "the tab must stay open while its Save As dialog is up"
    );
    assert!(
        app.world()
            .contains_resource::<jackdaw::scene_io::SceneDialogTask>(),
        "Save on an untitled tab must queue the Save As dialog"
    );
    // Drop the queued dialog task before it can open a real file dialog in
    // this process; the test only asserts it was queued.
    let task = app
        .world_mut()
        .remove_resource::<jackdaw::scene_io::SceneDialogTask>();
    drop(task);

    assert!(
        app.world().resource::<Scenes>().tabs[untitled].dirty,
        "the tab stays dirty until the dialog actually saves it"
    );
}

/// Once the deferred Save As resolves with a path and the save lands, the
/// close the user confirmed happens (N8: the deferred half of the flow).
#[test]
fn a_resolved_save_as_closes_the_confirmed_tab() {
    let (mut app, _tmp) = editor_with_untitled_tab();
    let untitled = app.world().resource::<Scenes>().active;
    assert_eq!(app.world().resource::<Scenes>().tabs.len(), 2);

    app.world_mut().insert_resource(PendingSaveAsClose {
        tab_index: untitled,
    });
    jackdaw::scenes::confirm_dialog::finish_pending_save_as_close(app.world_mut());
    app.update();

    assert_eq!(
        app.world().resource::<Scenes>().tabs.len(),
        1,
        "the saved tab closes after the deferred Save As resolves"
    );
    assert!(
        !app.world().contains_resource::<PendingSaveAsClose>(),
        "the deferred close is spent"
    );
}

/// A dismissed Save As dialog puts the tab back exactly where it was:
/// open, dirty, and closable again through the normal confirm flow (N8).
#[test]
fn a_dismissed_save_as_leaves_the_tab_open_and_dirty() {
    let (mut app, _tmp) = editor_with_untitled_tab();
    let untitled = app.world().resource::<Scenes>().active;
    place_rock(&mut app, 1.0);

    app.world_mut().insert_resource(PendingSaveAsClose {
        tab_index: untitled,
    });
    jackdaw::scenes::confirm_dialog::cancel_pending_save_as_close(app.world_mut());
    app.update();

    assert_eq!(
        app.world().resource::<Scenes>().tabs.len(),
        2,
        "the tab survives a cancelled Save As"
    );
    assert!(
        app.world().resource::<Scenes>().tabs[untitled].dirty,
        "the tab is still dirty"
    );
    assert!(
        !app.world().contains_resource::<PendingSaveAsClose>(),
        "the deferred close is gone, so a new close can ask again"
    );
}

// -------------------------------------------------- orphan tmp sweep (N6) --

/// Startup must remove orphan `.<name>.tmp-<pid>` files a killed save left
/// behind, without touching lookalikes the editor did not name (N6).
#[test]
fn startup_sweeps_orphan_temp_files() {
    let mut app = util::editor_test_app();
    let dir = tempfile::tempdir().expect("temp dir");
    let root = dir.path().to_path_buf();
    let assets = root.join("assets");
    std::fs::create_dir_all(&assets).expect("assets dir");

    let orphan = assets.join(".zone.bsn.tmp-999999");
    std::fs::write(&orphan, b"half a save from a dead process").expect("seed the orphan");
    let stale = std::fs::OpenOptions::new()
        .write(true)
        .open(&orphan)
        .expect("open for mtime");
    stale
        .set_modified(SystemTime::now() - Duration::from_secs(120))
        .expect("backdate past the fresh window");
    drop(stale);

    // Lookalikes the sweep must leave alone.
    let no_leading_dot = assets.join("zone.bsn.tmp-1");
    std::fs::write(&no_leading_dot, b"user file").expect("seed lookalike 1");
    let not_a_pid = assets.join(".zone.bsn.tmp-not-a-pid");
    std::fs::write(&not_a_pid, b"user file").expect("seed lookalike 2");

    jackdaw::project_select::transition_to_editor(app.world_mut(), root);
    app.update();

    assert!(
        !orphan.exists(),
        "the orphan temp file a dead save left behind is removed at startup"
    );
    assert!(no_leading_dot.exists(), "files without the dot prefix stay");
    assert!(not_a_pid.exists(), "files whose suffix is not a pid stay");
}
