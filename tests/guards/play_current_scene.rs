//! The current-scene play channel (`pie.play_current`): resolving the
//! scene tab in front, the three save policies, the temporary run copy
//! under `assets/.jackdaw-pie/`, and the prefab fallback. Headless half:
//! the resolution and its file effects, asserted through the operator
//! surface and `LastPlayCurrent`; the child process itself (the override
//! traveling through `JACKDAW_PIE_SCENE` into the game) is covered by the
//! runtime override tests and the live QA script.

use bevy::prelude::*;
use jackdaw::boot_ops::{run_op_clause, run_op_clause_as_user};
use jackdaw::pie_current::LastPlayCurrent;
use jackdaw::scenes::Scenes;

use crate::util::{self, OperatorResultExt as _};

/// Each test runs a full editor, a scene load, and a play resolution: heavy
/// enough that a parallel pile of them pushes the binary's timing-sensitive
/// tests (the journal write budget) over their limits. They share the
/// binary-wide heavy-editor lock and run one at a time.
use crate::HEAVY_EDITOR_LOCK as PLAY_CURRENT_LOCK;

fn play_lock() -> std::sync::MutexGuard<'static, ()> {
    PLAY_CURRENT_LOCK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

const ZONE_SCENE: &str = "#Zone\nbevy_transform::components::transform::Transform\n";

/// An editor on a scratch project holding a saved scene (open in front)
/// and a one-entry prefab the edits place instances of.
fn editor() -> (App, tempfile::TempDir) {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-play-current-")
        .tempdir()
        .expect("temp dir");
    std::fs::create_dir_all(tmp.path().join("assets/prefabs")).expect("asset folders");
    // A rock that is also a prefab document (the Prefab component on its
    // root), so opening it opens a prefab tab; scenes reference it for
    // placements through the same file.
    std::fs::write(
        tmp.path().join("assets/prefabs/rock.bsn"),
        "#Rock\njackdaw::prefab::components::Prefab\nbevy_transform::components::transform::Transform\n",
    )
    .expect("the prefab");
    std::fs::write(tmp.path().join("assets/zone.bsn"), ZONE_SCENE).expect("the scene");
    // An empty workspace manifest, so the launch's cargo probe fails fast
    // on this directory instead of crawling its parents for one 鈥?a crawl
    // that made the whole guards binary heavy enough to push the journal
    // write-timing test over its budget. The play resolution (save / temp
    // copy) completes before the probe either way.
    std::fs::write(tmp.path().join("Cargo.toml"), "[workspace]\n").expect("the manifest");

    let mut app = util::editor_test_app();
    app.world_mut()
        .insert_resource(jackdaw::project::ProjectRoot {
            root: tmp.path().to_path_buf(),
            config: default(),
        });
    // One run config so pie.play_current has something to launch; the
    // scratch project has no cargo crate, so the launch itself stops at
    // the build spec 鈥?after every save/copy effect this file asserts.
    app.world_mut()
        .insert_resource(jackdaw::run_config::RunConfigs {
            manifest: jackdaw_pie_protocol::manifest::Manifest {
                runs: vec![jackdaw_pie_protocol::manifest::RunConfig::default()],
                ..Default::default()
            },
        });
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    app.update();
    (app, tmp)
}

/// Open the zone scene in front and settle its load.
fn open_zone(app: &mut App) {
    run_op_clause(app.world_mut(), "scene.open path=assets/zone.bsn")
        .expect("the scene opens")
        .assert_finished();
    util::settle_scene_load(app);
}

/// One user edit: place a rock instance, a single history entry.
fn place_rock(app: &mut App) {
    run_op_clause_as_user(
        app.world_mut(),
        "prefab.spawn_instance path=prefabs/rock.bsn pos_x=1 pos_y=0 pos_z=0",
    )
    .expect("the placement dispatched")
    .assert_finished();
    app.update();
}

fn set_mode(app: &mut App, mode: &str) {
    run_op_clause(
        app.world_mut(),
        &format!("project.set_save_before_play mode={mode}"),
    )
    .expect("the mode operator runs")
    .assert_finished();
    app.update();
}

/// `pie.play_current` through the operator surface, then a frame for the
/// queued resolution.
fn play_current(app: &mut App) {
    run_op_clause(app.world_mut(), "pie.play_current")
        .expect("pie.play_current exists")
        .assert_finished();
    app.update();
}

fn active_dirty(app: &App) -> bool {
    let scenes = app.world().resource::<Scenes>();
    scenes.tabs[scenes.active].dirty
}

fn last_play(app: &App) -> LastPlayCurrent {
    app.world()
        .get_resource::<LastPlayCurrent>()
        .cloned()
        .unwrap_or_default()
}

/// The temporary run copies this editor process wrote, by display stem.
fn temp_copies(tmp: &tempfile::TempDir, stem: &str) -> Vec<std::path::PathBuf> {
    let pid = std::process::id();
    let dir = tmp.path().join("assets/.jackdaw-pie");
    std::fs::read_dir(&dir)
        .map(|entries| {
            entries
                .flatten()
                .map(|entry| entry.path())
                .filter(|path| {
                    let name = path.file_name().map(|n| n.to_string_lossy().into_owned());
                    matches!(name, Some(name) if name.starts_with(&format!("current-{stem}-"))
                        && name.ends_with(&format!("-{pid}.bsn")))
                })
                .collect()
        })
        .unwrap_or_default()
}

// ------------------------------------------------------------------ Save --

/// The Save policy: a dirty named scene is saved through the ordinary
/// launch-save chain, so the game plays the file with the edit in it and
/// the tab comes back clean.
#[test]
fn a_dirty_named_scene_saves_before_playing() {
    let _guard = play_lock();
    let (mut app, tmp) = editor();
    open_zone(&mut app);
    place_rock(&mut app);
    assert!(active_dirty(&app), "the premise: an unsaved edit");

    play_current(&mut app);

    let on_disk = std::fs::read_to_string(tmp.path().join("assets/zone.bsn")).unwrap();
    assert!(
        on_disk.contains("rock.bsn"),
        "the edit reached the file the game will read"
    );
    assert!(!active_dirty(&app), "the tab is clean after the save");
    let last = last_play(&app);
    assert_eq!(last.assets_relative.as_deref(), Some("zone.bsn"));
    assert!(!last.from_temp_copy, "a named scene plays its own file");
    assert!(
        temp_copies(&tmp, "zone").is_empty(),
        "the save policy writes no run copy for a named scene"
    );
}

// ------------------------------------------------------- PlayUnsavedCopy --

/// The copy policy: a dirty named scene plays from a temporary run copy 鈥?/// the disk file keeps its old content, the tab keeps its dirty flag, and
/// the copy carries the unsaved edit.
#[test]
fn the_copy_policy_plays_a_temporary_copy_and_leaves_disk_alone() {
    let _guard = play_lock();
    let (mut app, tmp) = editor();
    open_zone(&mut app);
    place_rock(&mut app);
    set_mode(&mut app, "play_unsaved_copy");

    play_current(&mut app);

    let on_disk = std::fs::read_to_string(tmp.path().join("assets/zone.bsn")).unwrap();
    assert_eq!(
        on_disk, ZONE_SCENE,
        "the disk file is untouched under the copy policy"
    );
    assert!(active_dirty(&app), "the tab keeps its unsaved state");

    let copies = temp_copies(&tmp, "zone");
    assert_eq!(copies.len(), 1, "one run copy for this editor pid");
    let copy = std::fs::read_to_string(&copies[0]).unwrap();
    assert!(
        copy.contains("rock.bsn"),
        "the copy is the unsaved work, not the file on disk"
    );
    let last = last_play(&app);
    let copy_name = copies[0]
        .file_name()
        .unwrap()
        .to_string_lossy()
        .into_owned();
    assert_eq!(
        last.assets_relative.as_deref(),
        Some(format!(".jackdaw-pie/{copy_name}").as_str()),
        "the override names the copy, assets-relative"
    );
    assert!(last.from_temp_copy, "the game reads the copy");
}

/// A clean named scene plays its own file even under the copy policy:
/// there is nothing unsaved to copy.
#[test]
fn a_clean_named_scene_plays_its_file_even_in_copy_mode() {
    let _guard = play_lock();
    let (mut app, tmp) = editor();
    open_zone(&mut app);
    set_mode(&mut app, "play_unsaved_copy");

    play_current(&mut app);

    let last = last_play(&app);
    assert_eq!(last.assets_relative.as_deref(), Some("zone.bsn"));
    assert!(!last.from_temp_copy);
    assert!(temp_copies(&tmp, "zone").is_empty());
}

// ---------------------------------------------------------------- untitled --

/// An untitled scene plays from a temporary copy under the Save policy 鈥?/// the old hard refusal ("save the scene before playing") is gone (N2).
#[test]
fn an_unsaved_untitled_scene_plays_in_save_mode_too() {
    let _guard = play_lock();
    let (mut app, tmp) = editor();
    run_op_clause(app.world_mut(), "scene.new")
        .expect("the untitled scene exists")
        .assert_finished();
    app.update();
    place_rock(&mut app);
    assert!(active_dirty(&app), "the premise: unsaved untitled work");

    play_current(&mut app);

    let copies = temp_copies(&tmp, "untitled");
    assert_eq!(copies.len(), 1, "the untitled scene runs from a copy");
    let copy = std::fs::read_to_string(&copies[0]).unwrap();
    assert!(
        copy.contains("rock.bsn"),
        "the copy carries the unsaved edit"
    );
    assert!(
        active_dirty(&app),
        "the tab stays unsaved: nothing was written"
    );
    assert!(last_play(&app).from_temp_copy);
}

/// 鈥nd under the copy policy, the same resolution with the same effects.
#[test]
fn an_unsaved_untitled_scene_plays_in_copy_mode() {
    let _guard = play_lock();
    let (mut app, tmp) = editor();
    run_op_clause(app.world_mut(), "scene.new")
        .expect("the untitled scene exists")
        .assert_finished();
    app.update();
    place_rock(&mut app);
    set_mode(&mut app, "play_unsaved_copy");

    play_current(&mut app);

    assert_eq!(temp_copies(&tmp, "untitled").len(), 1);
    assert!(active_dirty(&app));
}

// -------------------------------------------------------------------- Ask --

/// The Ask policy holds the play on a dialog for a dirty named scene:
/// nothing is written and nothing resolves until an answer comes.
#[test]
fn ask_holds_the_play_until_answered() {
    let _guard = play_lock();
    let (mut app, tmp) = editor();
    open_zone(&mut app);
    place_rock(&mut app);
    set_mode(&mut app, "ask");

    play_current(&mut app);

    let pending = app
        .world()
        .get_resource::<jackdaw::pie_current::PendingPlayAsk>();
    assert_eq!(
        pending.and_then(|ask| ask.tab_index),
        Some(0),
        "the play is held on the dialog"
    );
    assert!(
        temp_copies(&tmp, "zone").is_empty(),
        "no copy exists while the dialog is up"
    );
    assert_eq!(
        std::fs::read_to_string(tmp.path().join("assets/zone.bsn")).unwrap(),
        ZONE_SCENE,
        "nothing was saved while the dialog is up"
    );
    assert_eq!(
        last_play(&app),
        LastPlayCurrent::default(),
        "the play has not resolved yet"
    );

    // The Save answer takes the ordinary save path.
    jackdaw::pie_current::resolve_play_ask(
        app.world_mut(),
        jackdaw::pie_current::PlayAskChoice::Save,
    );
    app.update();
    assert!(
        std::fs::read_to_string(tmp.path().join("assets/zone.bsn"))
            .unwrap()
            .contains("rock.bsn"),
        "the Save answer saves before playing"
    );
    assert!(!active_dirty(&app));
    assert_eq!(last_play(&app).assets_relative.as_deref(), Some("zone.bsn"));
}

/// The Ask dialog's Play Copy answer leaves the disk file and the dirty
/// flag alone and runs the copy.
#[test]
fn ask_play_copy_leaves_disk_alone() {
    let _guard = play_lock();
    let (mut app, tmp) = editor();
    open_zone(&mut app);
    place_rock(&mut app);
    set_mode(&mut app, "ask");
    play_current(&mut app);

    jackdaw::pie_current::resolve_play_ask(
        app.world_mut(),
        jackdaw::pie_current::PlayAskChoice::PlayCopy,
    );
    app.update();

    assert_eq!(
        std::fs::read_to_string(tmp.path().join("assets/zone.bsn")).unwrap(),
        ZONE_SCENE,
        "the disk file keeps its old content"
    );
    assert!(active_dirty(&app));
    assert_eq!(temp_copies(&tmp, "zone").len(), 1);
    assert!(last_play(&app).from_temp_copy);
}

/// Cancel drops the play entirely: no save, no copy, nothing resolved.
#[test]
fn ask_cancel_drops_the_play() {
    let _guard = play_lock();
    let (mut app, tmp) = editor();
    open_zone(&mut app);
    place_rock(&mut app);
    set_mode(&mut app, "ask");
    play_current(&mut app);

    jackdaw::pie_current::cancel_play_ask(app.world_mut());
    app.update();

    assert!(
        app.world()
            .get_resource::<jackdaw::pie_current::PendingPlayAsk>()
            .is_none(),
        "the pending play is gone"
    );
    assert!(temp_copies(&tmp, "zone").is_empty());
    assert_eq!(last_play(&app), LastPlayCurrent::default());
    assert!(active_dirty(&app), "the unsaved work is untouched");
}

/// An untitled scene never asks: there is no file to save to, so it runs
/// as a copy straight away.
#[test]
fn ask_never_blocks_an_untitled_scene() {
    let _guard = play_lock();
    let (mut app, tmp) = editor();
    run_op_clause(app.world_mut(), "scene.new")
        .expect("the untitled scene exists")
        .assert_finished();
    app.update();
    place_rock(&mut app);
    set_mode(&mut app, "ask");

    play_current(&mut app);

    assert!(
        app.world()
            .get_resource::<jackdaw::pie_current::PendingPlayAsk>()
            .is_none(),
        "no dialog for a scene with no file"
    );
    assert_eq!(temp_copies(&tmp, "untitled").len(), 1, "it plays a copy");
}

// ---------------------------------------------------------- prefab fallback --

/// A prefab tab in front falls back to the nearest scene tab, which plays
/// as the named scene it is.
#[test]
fn a_prefab_in_front_falls_back_to_the_scene_tab() {
    let _guard = play_lock();
    let (mut app, _tmp) = editor();
    open_zone(&mut app);
    // The prefab opens in front of the scene.
    run_op_clause(app.world_mut(), "scene.open path=assets/prefabs/rock.bsn")
        .expect("the prefab opens")
        .assert_finished();
    util::settle_scene_load(&mut app);
    let kind = {
        let scenes = app.world().resource::<Scenes>();
        scenes.tabs[scenes.active].kind.clone()
    };
    assert_eq!(
        kind,
        jackdaw::scenes::TabKind::Prefab,
        "the premise: a prefab is in front"
    );

    play_current(&mut app);

    assert_eq!(
        last_play(&app).assets_relative.as_deref(),
        Some("zone.bsn"),
        "the scene tab behind the prefab is what plays"
    );
}

/// Every tab a prefab: the play refuses, resolving to nothing.
#[test]
fn all_prefab_tabs_refuse_the_play() {
    let _guard = play_lock();
    let (mut app, tmp) = editor();
    run_op_clause(app.world_mut(), "scene.open path=assets/prefabs/rock.bsn")
        .expect("the prefab opens")
        .assert_finished();
    util::settle_scene_load(&mut app);

    play_current(&mut app);

    assert_eq!(
        last_play(&app),
        LastPlayCurrent::default(),
        "nothing resolved: there is no scene to play"
    );
    assert!(
        temp_copies(&tmp, "rock").is_empty() && temp_copies(&tmp, "untitled").is_empty(),
        "and nothing was written"
    );
}

// ------------------------------------------------------- background tabs --

/// A dirty untitled tab in the background is reported, not silently
/// dropped: the named scene in front saves and plays, the background
/// unsaved scene keeps its state and does not reach the game.
#[test]
fn background_unsaved_tabs_keep_their_state() {
    let _guard = play_lock();
    let (mut app, tmp) = editor();
    open_zone(&mut app);
    place_rock(&mut app);
    // A second, unsaved scene in front of the dirty named one.
    run_op_clause(app.world_mut(), "scene.new")
        .expect("the untitled scene exists")
        .assert_finished();
    app.update();
    place_rock(&mut app);
    assert!(active_dirty(&app), "the premise: the front tab is unsaved");

    // Save policy: the front untitled runs as a copy; the background
    // dirty named tab is what gets saved.
    play_current(&mut app);

    assert_eq!(
        temp_copies(&tmp, "untitled").len(),
        1,
        "the untitled scene in front runs from a copy"
    );
    assert!(
        std::fs::read_to_string(tmp.path().join("assets/zone.bsn"))
            .unwrap()
            .contains("rock.bsn"),
        "the background named tab's edit was saved, not dropped"
    );
}

// ---------------------------------------------------------------- reload --

/// A reload resolves the override fresh (matrix #8): an edited scene
/// reloads onto a new temporary copy, a clean named scene onto its file,
/// and neither writes disk — the reload replays what is in front.
#[test]
fn reload_resolves_the_override_fresh_without_writing_disk() {
    let _guard = play_lock();
    let (mut app, tmp) = editor();

    // A clean named scene: the reload override is its file path.
    open_zone(&mut app);
    let override_clean = jackdaw::pie_current::override_for_reload(app.world_mut())
        .expect("a clean named scene resolves");
    assert_eq!(override_clean.assets_relative, "zone.bsn");
    assert!(!override_clean.from_temp_copy);
    assert!(
        temp_copies(&tmp, "zone").is_empty(),
        "a clean scene writes no copy"
    );

    // The same scene edited: the reload override is a fresh temp copy of
    // the unsaved work, and the disk file keeps its old content.
    place_rock(&mut app);
    let override_dirty = jackdaw::pie_current::override_for_reload(app.world_mut())
        .expect("an edited scene resolves");
    assert!(override_dirty.from_temp_copy);
    let copy = std::fs::read_to_string(
        override_dirty
            .temp_copy
            .as_ref()
            .expect("the override owns its copy"),
    )
    .unwrap();
    assert!(
        copy.contains("rock.bsn"),
        "the reload copy carries the unsaved edit"
    );
    assert!(
        !std::fs::read_to_string(tmp.path().join("assets/zone.bsn"))
            .unwrap()
            .contains("rock.bsn"),
        "the reload never writes disk"
    );
}
