//! Guards for the T04 crash-recovery entry point: a leftover journal
//! queues a recovery, the tab restore waits for the user's answer,
//! restoring opens an in-memory dirty tab that never writes the file
//! until an explicit save, untitled entries come back untitled, entries
//! are spent independently, a damaged journal is skipped and kept, the
//! dismiss operators clean up, and the `jackdaw/recovery` BRP summarizes
//! it all.

use std::path::Path;

use bevy::prelude::*;
use jackdaw::boot_ops::run_op_clause;
use jackdaw::remote::server::recovery_handler;
use jackdaw::scene_io::session_journal::{self, JournalFile, JournalTab};
use jackdaw::scenes::Scenes;
use jackdaw::scenes::recovery_dialog::PendingRecovery;
use serde_json::json;

use crate::util::{self, OperatorResultExt as _};

const ZONE_SCENE: &str = "#Zone\nbevy_transform::components::transform::Transform\n";
/// The name the seeded leftover session directory carries.
const LEFTOVER: &str = "111111-1000";

/// One journaled entry, written by hand: the tests control the document
/// text exactly, so the restore path is exercised against known bytes
/// rather than against whatever a debounce produced.
fn entry(path: Option<&Path>, document: &str, name: &str) -> JournalTab {
    JournalTab {
        path: path.map(|path| path.to_string_lossy().into_owned()),
        kind: "scene".to_string(),
        display_name: name.to_string(),
        captured_at: "2026-10-25T00:00:00Z".to_string(),
        saved_at: None,
        entity_count: 2,
        document: document.to_string(),
    }
}

/// An editor opened on `tmp` with one leftover session holding `tabs`.
/// The open itself (`transition_to_editor`) detects the leftover and
/// queues the recovery; one update brings the dialog's session forward.
fn editor_with_leftover(
    tmp: &tempfile::TempDir,
    tabs: Vec<JournalTab>,
) -> (App, std::path::PathBuf) {
    std::fs::create_dir_all(tmp.path().join("assets")).expect("assets");
    std::fs::write(tmp.path().join("assets/zone.bsn"), ZONE_SCENE).expect("the scene");

    let mut app = util::editor_test_app();
    let sessions = session_journal::sessions_root(tmp.path()).expect("sessions root");
    let dir = sessions.join(LEFTOVER);
    std::fs::create_dir_all(&dir).expect("leftover dir");
    let journal = JournalFile {
        schema: 1,
        editor_version: "test".to_string(),
        pid: 111111,
        started: "2026-10-25T00:00:00Z".to_string(),
        terrain_note: "test".to_string(),
        tabs,
    };
    std::fs::write(
        dir.join("journal.json"),
        serde_json::to_vec(&journal).expect("encode"),
    )
    .expect("seed the leftover");

    jackdaw::project_select::transition_to_editor(app.world_mut(), tmp.path().to_path_buf());
    app.update();
    (app, dir)
}

// ------------------------------------------------------- detection gate --

/// Opening a project with a leftover session queues the recovery and holds
/// the tab restore until the user answers.
#[test]
fn a_leftover_session_holds_the_tab_restore() {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-recovery-")
        .tempdir()
        .expect("temp dir");
    let (app, _dir) = editor_with_leftover(
        &tmp,
        vec![entry(
            Some(&tmp.path().join("assets/zone.bsn")),
            "#Zone\nbevy_transform::components::transform::Transform {}\n#Extra\n",
            "zone",
        )],
    );

    let pending = app.world().resource::<PendingRecovery>();
    assert_eq!(pending.queue.len(), 0, "the dialog took the session");
    assert!(pending.current.is_some(), "a dialog session is up");
    assert!(
        app.world().resource::<Scenes>().tabs.is_empty(),
        "the tab restore waits for the recovery answer"
    );
}

// ------------------------------------------------------ restore (N11) --

/// Restoring opens a dirty in-memory tab and writes nothing: the file on
/// disk keeps its exact bytes until an explicit save.
#[test]
fn restore_opens_a_dirty_tab_and_writes_nothing() {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-recovery-")
        .tempdir()
        .expect("temp dir");
    let scene = tmp.path().join("assets/zone.bsn");
    let before = ZONE_SCENE.as_bytes().to_vec();
    let (mut app, dir) = editor_with_leftover(
        &tmp,
        vec![entry(
            Some(&scene),
            "#Zone\nbevy_transform::components::transform::Transform {}\n#Extra\n",
            "zone",
        )],
    );

    run_op_clause(
        app.world_mut(),
        "recovery.restore session=111111-1000 tab=0",
    )
    .expect("the restore dispatches")
    .assert_finished();
    app.update();

    {
        let scenes = app.world().resource::<Scenes>();
        let restored = scenes.tabs.last().expect("the restored tab");
        assert!(restored.dirty, "a restored tab is dirty from the start");
        assert_eq!(
            restored.path.as_deref(),
            Some(scene.as_path()),
            "the restored tab carries the journal's path"
        );
        assert!(
            restored.saved_doc_hash.is_some(),
            "the disk file is its baseline"
        );
    }
    assert_eq!(
        std::fs::read(&scene).unwrap(),
        before,
        "restore never writes the file"
    );
    assert!(!dir.exists(), "the spent session directory is gone");
    // One more frame: the dialog system notices the session it was
    // holding is gone and drops the pending state.
    app.update();
    assert!(
        !app.world().contains_resource::<PendingRecovery>(),
        "nothing left to ask about"
    );

    // The explicit save is what writes the file, through the standard
    // boundary (stamp, watcher echo suppression).
    assert!(jackdaw::scene_io::save_scene(app.world_mut()));
    app.update();
    let saved = std::fs::read_to_string(&scene).expect("the save wrote it");
    assert!(
        saved.contains("#Extra"),
        "the recovered edit landed: {saved}"
    );
    assert!(saved.starts_with("// jackdaw "), "the save stamped it");
    assert!(
        !app.world().resource::<Scenes>().tabs.last().unwrap().dirty,
        "the save cleared the restored tab's dirty flag"
    );
}

/// An entry with no path restores as an untitled tab, dirty, keeping the
/// display name the journal recorded.
#[test]
fn an_untitled_entry_restores_as_an_untitled_dirty_tab() {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-recovery-")
        .tempdir()
        .expect("temp dir");
    let (mut app, _dir) = editor_with_leftover(
        &tmp,
        vec![entry(
            None,
            "#Draft\nbevy_transform::components::transform::Transform {}\n",
            "untitled-1",
        )],
    );

    run_op_clause(
        app.world_mut(),
        "recovery.restore session=111111-1000 tab=0",
    )
    .expect("the restore dispatches")
    .assert_finished();
    app.update();

    let scenes = app.world().resource::<Scenes>();
    let restored = scenes.tabs.last().expect("the restored tab");
    assert!(restored.path.is_none(), "an untitled entry stays untitled");
    assert_eq!(restored.display_name, "untitled-1");
    assert!(restored.dirty);
    assert!(restored.saved_doc_hash.is_none(), "no file, no baseline");
}

/// Two entries in one session restore and dismiss independently.
#[test]
fn two_entries_are_spent_independently() {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-recovery-")
        .tempdir()
        .expect("temp dir");
    let (mut app, dir) = editor_with_leftover(
        &tmp,
        vec![
            entry(
                Some(&tmp.path().join("assets/zone.bsn")),
                "#Zone\nbevy_transform::components::transform::Transform {}\n",
                "zone",
            ),
            entry(
                None,
                "#Draft\nbevy_transform::components::transform::Transform {}\n",
                "untitled-1",
            ),
        ],
    );

    // Restore the first; the journal keeps the second.
    run_op_clause(
        app.world_mut(),
        "recovery.restore session=111111-1000 tab=0",
    )
    .expect("the first restore dispatches")
    .assert_finished();
    app.update();
    let journal = session_journal::read_session_journal(&dir).expect("one entry left");
    assert_eq!(journal.tabs.len(), 1);
    assert_eq!(journal.tabs[0].display_name, "untitled-1");

    // Dismiss the second by operator; the session directory goes.
    run_op_clause(app.world_mut(), "recovery.dismiss session=111111-1000")
        .expect("the dismiss dispatches")
        .assert_finished();
    app.update();
    assert!(!dir.exists(), "the dismissed session directory is gone");
    let scenes = app.world().resource::<Scenes>();
    assert_eq!(scenes.tabs.len(), 1, "exactly the one restored tab");
    assert!(scenes.tabs[0].dirty);
}

/// `recovery.dismiss all=true` clears every leftover in one call.
#[test]
fn dismiss_all_clears_every_session() {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-recovery-")
        .tempdir()
        .expect("temp dir");
    let (mut app, dir) = editor_with_leftover(
        &tmp,
        vec![entry(
            None,
            "#Draft\nbevy_transform::components::transform::Transform {}\n",
            "untitled-1",
        )],
    );
    // A second, older leftover.
    let sessions = session_journal::sessions_root(tmp.path()).expect("root");
    let older = sessions.join("111111-500");
    std::fs::create_dir_all(&older).expect("older dir");
    std::fs::write(older.join("journal.json"), "{}").expect("older journal");

    run_op_clause(app.world_mut(), "recovery.dismiss all=true")
        .expect("the dismiss dispatches")
        .assert_finished();
    app.update();

    assert!(!dir.exists() && !older.exists(), "every leftover is gone");
    assert!(
        !app.world().contains_resource::<PendingRecovery>(),
        "and the pending state with them"
    );
}

/// A journal that does not parse is skipped, kept on disk, and never
/// crashes the open (the Y28 line).
#[test]
fn a_damaged_journal_is_skipped_and_kept() {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-recovery-")
        .tempdir()
        .expect("temp dir");
    std::fs::create_dir_all(tmp.path().join("assets")).expect("assets");
    let mut app = util::editor_test_app();
    let sessions = session_journal::sessions_root(tmp.path()).expect("root");
    let dir = sessions.join(LEFTOVER);
    std::fs::create_dir_all(&dir).expect("dir");
    // Half of a JSON document: exactly what a crash mid-write leaves.
    std::fs::write(dir.join("journal.json"), "{ \"schema\": 1, \"tabs\": [ tru").expect("damaged");

    jackdaw::project_select::transition_to_editor(app.world_mut(), tmp.path().to_path_buf());
    for _ in 0..5 {
        app.update(); // must not panic
    }
    assert!(
        dir.join("journal.json").is_file(),
        "the damaged journal is kept as evidence"
    );
    assert!(
        !app.world().contains_resource::<PendingRecovery>(),
        "a damaged session is skipped, not offered"
    );
}

// ------------------------------------------------------------- the BRP --

/// The `jackdaw/recovery` BRP names every leftover with its tabs
/// summarized, including the line diff against the file on disk.
#[test]
fn the_recovery_brp_summarizes_the_leftovers() {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-recovery-")
        .tempdir()
        .expect("temp dir");
    let (mut app, _dir) = editor_with_leftover(
        &tmp,
        vec![entry(
            Some(&tmp.path().join("assets/zone.bsn")),
            "#Zone\nbevy_transform::components::transform::Transform {}\n#Extra\n#More\n",
            "zone",
        )],
    );

    let answer = app
        .world_mut()
        .run_system_cached_with(recovery_handler, Some(json!({})))
        .expect("the handler ran")
        .expect("the handler answered");
    assert_eq!(answer["available"], json!(true));
    let sessions = answer["sessions"].as_array().expect("sessions");
    assert_eq!(sessions.len(), 1);
    assert_eq!(sessions[0]["session"], json!(LEFTOVER));
    assert_eq!(sessions[0]["damaged"], json!(false));
    let tabs = sessions[0]["tabs"].as_array().expect("tabs");
    assert_eq!(tabs.len(), 1);
    assert_eq!(tabs[0]["display_name"], json!("zone"));
    assert_eq!(tabs[0]["entity_count"], json!(2));
    // zone.bsn holds one line; the journal's document holds three.
    assert_eq!(tabs[0]["diff"], json!("+2 lines vs the file on disk"));
}
