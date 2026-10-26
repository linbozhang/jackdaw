//! Guards for the T04 crash journal: a dirty tab produces a journal entry
//! whose text comes from the same emitter a save uses, a clean tab
//! produces none, a clean exit removes the session directory while a crash
//! leaves it, rotation keeps the newest sessions, a damaged journal reads
//! safely, the journal lives under the test-overridable config directory,
//! and a successful save spends the tab's entry and rotates the previous
//! file to `.bak`.

use std::path::Path;
use std::time::{Duration, Instant};

use bevy::prelude::*;
use jackdaw::boot_ops::{run_op_clause, run_op_clause_as_user};
use jackdaw::scene_io::session_journal::{
    self, JOURNAL_DEBOUNCE, JournalFile, read_session_journal,
};
use jackdaw::scenes::Scenes;

use crate::util::{self, OperatorResultExt as _};

const ZONE_SCENE: &str = "#Zone\nbevy_transform::components::transform::Transform\n";

/// An editor on a project with a saved scene in front, its journal session
/// begun, and its clock stepped past the debounce every frame so one
/// `update()` is enough to let a snapshot land.
fn editor() -> (App, tempfile::TempDir) {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-session-journal-")
        .tempdir()
        .expect("temp dir");
    std::fs::create_dir_all(tmp.path().join("assets/prefabs")).expect("asset folders");
    std::fs::write(
        tmp.path().join("assets/prefabs/rock.bsn"),
        "#Rock\nbevy_transform::components::transform::Transform\n",
    )
    .expect("the prefab");
    std::fs::write(tmp.path().join("assets/zone.bsn"), ZONE_SCENE).expect("the scene");

    let mut app = util::editor_test_app();
    // Isolated config directory (per test process), so the journal lands
    // under it and never touches whoever runs the tests.
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

    session_journal::begin_session(app.world_mut(), tmp.path());
    // One frame steps the clock past the debounce, so a dirty change is
    // one `update()` away from its snapshot.
    app.insert_resource(bevy::time::TimeUpdateStrategy::ManualDuration(
        JOURNAL_DEBOUNCE + Duration::from_millis(100),
    ));
    app.update();
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

/// The session's journal file, if the session has written one.
fn journal_path(app: &App) -> Option<std::path::PathBuf> {
    let dir = session_journal::session_dir(app.world())?;
    let file = dir.join("journal.json");
    file.is_file().then_some(file)
}

/// Run frames until the journal file exists (or not), then parse it.
fn read_journal(app: &mut App) -> Option<JournalFile> {
    util::update_until(app, "the journal to land", Duration::from_secs(10), |app| {
        journal_path(app).is_some()
    });
    let dir = session_journal::session_dir(app.world())?;
    read_session_journal(&dir)
}

fn save(app: &mut App) {
    assert!(
        jackdaw::scene_io::save_scene(app.world_mut()),
        "the scene saves"
    );
    app.update();
}

// ---------------------------------------------------- acceptance 1 (a) --

/// An edit lights the tab, the debounce passes, and the journal holds one
/// entry whose document is byte-for-byte what the save emitter produces
/// from the same live world.
#[test]
fn a_dirty_tab_journals_the_save_emitters_own_text() {
    let (mut app, tmp) = editor();
    place_rock(&mut app, 1.0);

    let journal = read_journal(&mut app).expect("the journal lands");
    assert_eq!(journal.tabs.len(), 1, "one entry for the one dirty tab");
    let entry = &journal.tabs[0];
    let entry_path = Path::new(entry.path.as_deref().expect("the entry names a file"));
    assert!(
        entry_path.starts_with(tmp.path())
            && entry_path.ends_with(Path::new("assets").join("zone.bsn")),
        "the entry names the tab's file: {}",
        entry_path.display()
    );
    assert_eq!(entry.kind, "scene");
    assert_eq!(entry.display_name, "zone");
    assert!(!entry.document.is_empty());
    assert!(
        !entry.document.starts_with("// jackdaw "),
        "journal text is the in-memory emit; the stamp is a disk-save-only line"
    );

    let same_source =
        jackdaw::scene_io::emit_bsn_scene_for_file(app.world_mut(), &tmp.path().join("assets"))
            .expect("the manual emit works");
    assert_eq!(
        entry.document, same_source,
        "the journal text and a save's emit come from the same emitter"
    );
    let live_roots = app
        .world()
        .resource::<jackdaw_bsn::SceneBsnAst>()
        .roots
        .len();
    assert_eq!(
        entry.entity_count, live_roots,
        "the entry counts the live document's roots"
    );
}

/// A clean tab produces no journal at all.
#[test]
fn a_clean_tab_journals_nothing() {
    let (mut app, _tmp) = editor();
    for _ in 0..5 {
        app.update();
    }
    assert!(
        journal_path(&app).is_none(),
        "a clean strip writes no journal file"
    );
}

// ---------------------------------------------------- acceptance 2 (b) --

/// Dropping the app without an exit (a crash, from the journal's point of
/// view) leaves the session directory and its journal behind.
#[test]
fn a_crashed_session_leaves_its_journal_behind() {
    let (mut app, tmp) = editor();
    place_rock(&mut app, 1.0);
    let journal = read_journal(&mut app).expect("the journal lands");
    assert_eq!(journal.tabs.len(), 1);

    drop(app); // no AppExit, no state leave: the process just dies

    let sessions = session_journal::sessions_root(tmp.path()).expect("sessions root");
    let leftover = session_journal::list_sessions(&sessions);
    assert_eq!(leftover.len(), 1, "the killed session's directory remains");
    assert!(
        read_session_journal(&leftover[0]).is_some(),
        "its journal is intact and readable"
    );
}

/// A clean exit removes the session directory: anything left over means a
/// crash.
#[test]
fn a_clean_exit_removes_the_session_directory() {
    let (mut app, tmp) = editor();
    place_rock(&mut app, 1.0);
    read_journal(&mut app).expect("the journal lands");

    app.world_mut().write_message(bevy::app::AppExit::Success);
    app.update(); // Last runs the exit cleaner

    let sessions = session_journal::sessions_root(tmp.path()).expect("sessions root");
    assert!(
        session_journal::list_sessions(&sessions).is_empty(),
        "a clean exit leaves no session behind"
    );
    assert!(
        session_journal::session_dir(app.world()).is_none(),
        "the resource is spent with the session"
    );
}

/// Starting a session keeps only the newest few leftovers.
#[test]
fn beginning_a_session_rotates_old_ones_beyond_five() {
    // Build the app first: that is what isolates the config directory,
    // and every path below must land inside it, never in the real one.
    let mut app = util::editor_test_app();
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-journal-rotate-")
        .tempdir()
        .expect("temp dir");
    let sessions = session_journal::sessions_root(tmp.path()).expect("sessions root");
    std::fs::create_dir_all(&sessions).expect("sessions dir");
    // Seven leftovers, aged apart by name (the tie-break list_sessions
    // falls back to) so the ordering is unambiguous even on a clock that
    // has not ticked between them.
    for n in 1..=7 {
        let dir = sessions.join(format!("111111-{n}000"));
        std::fs::create_dir_all(&dir).expect("leftover dir");
        std::fs::write(dir.join("journal.json"), "{}").expect("leftover journal");
    }

    session_journal::begin_session(app.world_mut(), tmp.path());

    let kept = session_journal::list_sessions(&sessions);
    assert!(
        kept.iter().all(|path| path.starts_with(&sessions)),
        "every session lives under the isolated state dir"
    );
    assert_eq!(
        kept.len(),
        5,
        "seven leftovers plus this session keep only the newest five"
    );
    assert!(
        !sessions.join("111111-1000").exists(),
        "the oldest-named leftover is swept"
    );
    assert!(
        sessions.join("111111-7000").exists(),
        "the newest-named leftover is kept"
    );
}

/// A journal that does not parse reads as absent, warns, and stays on
/// disk: the recovery entry point must never crash on one, and damaged
/// bytes are evidence, not garbage.
#[test]
fn a_damaged_journal_reads_as_none_and_stays_on_disk() {
    let tmp = tempfile::tempdir().expect("temp dir");
    let dir = tmp.path().join("999999-1");
    std::fs::create_dir_all(&dir).expect("session dir");
    std::fs::write(dir.join("journal.json"), "{ \"schema\": 1, \"tabs\": [ tru").expect("damaged");

    let read = read_session_journal(&dir);
    assert!(read.is_none(), "a damaged journal does not parse");
    assert!(
        dir.join("journal.json").is_file(),
        "the damaged file is kept"
    );
}

// ---------------------------------------------------- acceptance 3 (c) --

/// The journal lives under the config directory the test overrode, which
/// is what keeps every journal test off the real user state.
#[test]
fn the_journal_lives_under_the_overridden_config_dir() {
    let (mut app, _tmp) = editor();
    place_rock(&mut app, 1.0);
    read_journal(&mut app).expect("the journal lands");

    let overridden = std::env::var_os(jackdaw_env::paths::CONFIG_DIR_VAR)
        .expect("the test harness overrides the config dir");
    let journal = journal_path(&app).expect("the journal file");
    assert!(
        journal.starts_with(Path::new(&overridden)),
        "journal at {} must live under {}",
        journal.display(),
        Path::new(&overridden).display()
    );
}

// ---------------------------------------------------- acceptance 4 (d) --

/// A successful save spends the tab's journal entry and rotates the
/// previous file to a single `.bak` holding the pre-save bytes.
#[test]
fn a_successful_save_spends_the_entry_and_backups_the_old_file() {
    let (mut app, tmp) = editor();
    let scene = tmp.path().join("assets/zone.bsn");
    let before = std::fs::read(&scene).expect("the pre-save file");
    place_rock(&mut app, 1.0);
    read_journal(&mut app).expect("the journal lands");

    save(&mut app);

    let after_save = journal_path(&app);
    let tabs = after_save
        .and_then(|path| read_session_journal(path.parent().unwrap()))
        .map(|journal| journal.tabs)
        .unwrap_or_default();
    assert!(
        tabs.is_empty(),
        "a saved tab has nothing left to recover: {:?}",
        tabs
    );

    let backup = scene.with_file_name("zone.bsn.bak");
    assert_eq!(
        std::fs::read(&backup).expect("the backup exists"),
        before,
        "the .bak holds exactly the pre-save bytes"
    );
}

// ------------------------------------------------- the frame-cost gate --

/// A generated scene: `count` transform-only entities, the shape a big
/// level has on the text side.
fn generated_scene(count: usize) -> String {
    let mut text = String::from("#Zone\nbevy_transform::components::transform::Transform\n");
    for i in 0..count {
        text.push_str(&format!(
            "#Entity{i}\nbevy_transform::components::transform::Transform\n"
        ));
    }
    text
}

/// Terrain bulk data is not journaled (the standing design limitation),
/// so the journal's frame cost is emit-and-write of document text. The
/// gate measures that on a large generated scene and on the fixture scene
/// whose document carries a Terrain patch, and holds each under 5 ms.
#[test]
fn the_journal_write_costs_no_more_than_five_milliseconds() {
    // A timing gate this tight needs the machine to itself: this module was
    // its own test binary once (one process, no neighbors) and the merged
    // binary's other editor-booting tests, running in parallel, can push
    // the write over the budget all by themselves. Take the heavy-editor
    // lock so the measurement runs the way the budget was set: alone.
    let _heavy = crate::HEAVY_EDITOR_LOCK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    for (name, scene_text) in [
        ("400-entity generated", generated_scene(400)),
        (
            "terrain-patch fixture",
            include_str!("../fixtures/jsn_to_bsn/real_scene.bsn")
                .lines()
                .filter(|line| !line.starts_with("//"))
                .collect::<Vec<_>>()
                .join("\n")
                + "\n",
        ),
    ] {
        let tmp = tempfile::Builder::new()
            .prefix("jackdaw-journal-perf-")
            .tempdir()
            .expect("temp dir");
        std::fs::create_dir_all(tmp.path().join("assets/prefabs")).expect("folders");
        std::fs::write(
            tmp.path().join("assets/prefabs/rock.bsn"),
            "#Rock\nbevy_transform::components::transform::Transform\n",
        )
        .expect("the prefab");
        std::fs::write(tmp.path().join("assets/zone.bsn"), scene_text).expect("the scene");

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
        session_journal::begin_session(app.world_mut(), tmp.path());

        place_rock(&mut app, 1.0);
        let active = app.world().resource::<Scenes>().active;
        let dirty = app
            .world()
            .resource::<Scenes>()
            .tabs
            .get(active)
            .is_some_and(|tab| tab.dirty);
        assert!(dirty, "{name}: the edit lights the tab");

        // What the emit alone costs, to attribute the budget.
        let emit_started = Instant::now();
        let _ =
            jackdaw::scene_io::emit_bsn_scene_for_file(app.world_mut(), &tmp.path().join("assets"));
        bevy::log::info!("journal emit only ({name}): {:?}", emit_started.elapsed());

        // The gate: what the editing frame itself pays. The debounce path
        // collects on the main thread (the emit) and hands the write to
        // the IO pool, so this is the interactive cost.
        let started = Instant::now();
        session_journal::write_snapshot_deferred(app.world_mut());
        let cost = started.elapsed();

        bevy::log::info!("journal main-thread cost ({name}): {cost:?}");
        assert!(
            cost < Duration::from_millis(5),
            "{name}: journal write took {cost:?}, over the 5 ms frame budget"
        );
        // The deferred write lands on the IO pool; wait for the file.
        util::update_until(
            &mut app,
            "the journal to land",
            Duration::from_secs(10),
            |app| journal_path(app).is_some(),
        );
        assert!(
            journal_path(&app).is_some(),
            "{name}: the measured write actually produced a journal"
        );
    }
}
