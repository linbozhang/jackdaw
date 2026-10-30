//! The save store: the runtime's thin persistence layer for player data
//! (T17 plan §四-T1). The matrix's headless half lives here — the three
//! probe pins the plan asked for first, then the fallback grid:
//!
//! * probes (kept as standing assertions, the T16-T1 way):
//!   serde round-trip of the input types a save profile embeds, the
//!   macOS form of `dirs::data_dir()`, and the explicit-reflect pin for
//!   a generic resource (`SaveStore<T>` is *not* auto-registered — the
//!   T16-T1 lesson, re-proven and pinned for this type);
//! * M1  restart recovery: two apps, one directory, every field;
//! * M9  missing file: quiet default, no directory made, game runs;
//! * M10 version guard: newer saves and unmigrated older ones are read
//!   as `VersionSkipped`, never overwritten (the invariant), a
//!   registered migration upgrades in place;
//! * M11 corrupt saves: backed up as `save.json.corrupt-<millis>`,
//!   default stands, game runs;
//! * M12 directory trouble: an unwritable directory warns and the game
//!   keeps running; an unresolvable directory is the `NoDir` status;
//! * M7  the input restore leg's merge semantics against real loaded
//!   data (`merge_actions` over what the file came back with);
//! * the env seam (`JACKDAW_SAVE_DIR`), lazy directory creation, and
//!   the atomic write's stray-temp immunity.
//!
//! Plugin-level legs go through the env seam the way `game_flow.rs`
//! holds its env lock; everything else reads the explicit seam
//! (`SaveStore::open_in`), this module's `flow::start_scene_in`.
//!
//! ```text
//! cargo test -p jackdaw_runtime --test save_store
//! ```

use std::any::TypeId;
use std::path::Path;

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

use bevy::ecs::reflect::AppTypeRegistry;
use bevy::prelude::*;
use bevy::reflect::serde::ReflectSerializer;
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;

use jackdaw_runtime::{
    GameActionDef, GameActionKind, GameInputBinding, GameInputConfig, SavePlugin, SaveStatus,
    SaveStore, merge_actions,
};

/// Serializes the tests that touch process-wide environment variables.
static ENV_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

fn env_lock() -> std::sync::MutexGuard<'static, ()> {
    ENV_LOCK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn set_env(key: &str, value: Option<&str>) {
    // SAFETY: the caller holds ENV_LOCK, so no other thread of this
    // process reads or writes the variable meanwhile.
    unsafe {
        match value {
            Some(value) => std::env::set_var(key, value),
            None => std::env::remove_var(key),
        }
    }
}

/// The profile a save carries in these tests, in the shape the template
/// will declare its `GameSave` (plain data: numbers, a flag, a string).
#[derive(Reflect, Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[reflect(Default)]
struct TestProfile {
    runs_played: u32,
    unlocked: bool,
    master_volume: f32,
    nickname: String,
}

fn played_profile() -> TestProfile {
    TestProfile {
        runs_played: 3,
        unlocked: true,
        master_volume: 0.4,
        nickname: "lin".into(),
    }
}

fn file_text(dir: &Path) -> String {
    std::fs::read_to_string(dir.join("save.json")).expect("save.json on disk")
}

fn write_envelope(dir: &Path, text: &str) {
    std::fs::create_dir_all(dir).expect("save dir");
    std::fs::write(dir.join("save.json"), text).expect("write the save");
}

fn backups(dir: &Path) -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(dir)
        .expect("save dir")
        .flatten()
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .filter(|name| name.starts_with("save.json.corrupt-"))
        .collect();
    names.sort();
    names
}

// ---- Probe 1: the input types a save embeds round-trip through JSON ----

/// `GameInputBinding`/`GameActionDef` carry serde derives for exactly
/// this purpose (T09); the save profile embeds them, so the JSON path
/// must be round-trip stable. The exact JSON spelling is pinned in
/// `the_on_disk_envelope_shape_is_pinned`.
#[test]
fn the_input_types_a_save_embeds_round_trip_through_json() {
    let def = GameActionDef {
        name: "Move".into(),
        kind: GameActionKind::Axis2D,
        bindings: vec![
            GameInputBinding::Key(bevy::input::keyboard::KeyCode::KeyW),
            GameInputBinding::MouseButton(MouseButton::Left),
            GameInputBinding::MouseMotion,
            GameInputBinding::GamepadButton(GamepadButton::South),
            GameInputBinding::GamepadAxis {
                axis: GamepadAxis::LeftStickX,
                deadzone: 0.15,
            },
        ],
    };
    let text = serde_json::to_string(&def).expect("serialize");
    let back: GameActionDef = serde_json::from_str(&text).expect("deserialize");
    assert_eq!(back, def, "the JSON path is lossless");
    // The exact spelling, pinned: bevy input enums are their own
    // serde shapes (KeyW a bare string, the wrapper a tagged variant),
    // so a save holds readable JSON a QA script can walk.
    assert_eq!(
        text,
        r#"{"name":"Move","kind":"Axis2D","bindings":[{"Key":"KeyW"},{"MouseButton":"Left"},"MouseMotion",{"GamepadButton":"South"},{"GamepadAxis":{"axis":"LeftStickX","deadzone":0.15}}]}"#,
        "the JSON form the profile embeds"
    );

    // And through an envelope, the way a save actually carries them.
    let dir = tempfile::tempdir().expect("tempdir");
    let target = dir.path().join("game");
    let mut store = SaveStore::<Vec<GameActionDef>>::open_in(Some(&target), &[]).0;
    *store.get_mut() = vec![def.clone()];
    store.write().expect("write");
    let (reloaded, warnings) = SaveStore::<Vec<GameActionDef>>::open_in(Some(&target), &[]);
    assert!(
        warnings.is_empty(),
        "a save the same build wrote must load without a warning: {warnings:?}"
    );
    assert_eq!(reloaded.profile, vec![def], "the table survives the file");
    assert_eq!(reloaded.status, SaveStatus::Loaded);
}

// ---- Probe 2: the macOS form of the save directory ----------------------

/// `dirs::data_dir()` on macOS is `~/Library/Application Support`, and
/// a game's save directory is its id under it — the player-data
/// convention, and the literal answer to "separate from the scene
/// files" (those live in the project's assets tree).
#[test]
#[cfg(target_os = "macos")]
fn the_save_directory_lives_in_application_support_on_macos() {
    let _guard = env_lock();
    set_env("JACKDAW_SAVE_DIR", None);
    let dir = jackdaw_runtime::save_dir("t17_probe_game").expect("a data dir on macOS");
    let data = dirs::data_dir().expect("a data dir on macOS");
    assert!(
        dir.starts_with(&data),
        "{} is the game id under {}",
        dir.display(),
        data.display()
    );
    assert!(
        dir.ends_with("Library/Application Support/t17_probe_game"),
        "the macOS player-data form, got {}",
        dir.display()
    );
}

/// The env seam replaces the whole directory (not a subdirectory of
/// it): tests and QA point every game at one scratch tree.
#[test]
fn the_environment_seam_moves_the_whole_save_directory() {
    let _guard = env_lock();
    let scratch = tempfile::tempdir().expect("tempdir");
    set_env("JACKDAW_SAVE_DIR", scratch.path().to_str());
    let dir = jackdaw_runtime::save_dir("whatever-game").expect("env wins");
    assert_eq!(
        dir,
        scratch.path(),
        "the seam replaces the directory whole: {}",
        dir.display()
    );
    set_env("JACKDAW_SAVE_DIR", None);
}

// ---- Probe 3: the BRP face — registration is explicit -------------------

/// The T16-T1 lesson, re-proven and pinned for the save family: a
/// generic resource is never in the reflect auto-inventory, so
/// `SavePlugin` registers `SaveStore<T>`, `SaveStatus` *and* the
/// profile type itself — without those, the BRP `world.get_resources`
/// face is silently absent and a partial `profile` would not even
/// serialize.
#[test]
fn a_generic_save_store_needs_explicit_registration_to_be_reflect_reachable() {
    // The control: the resource can sit in a world without any
    // registration — and the registry does not know it.
    let mut before = App::new();
    before.init_resource::<AppTypeRegistry>();
    before.insert_resource(SaveStore::<TestProfile>::default());
    assert!(
        !before
            .world()
            .resource::<AppTypeRegistry>()
            .read()
            .contains(TypeId::of::<SaveStore<TestProfile>>()),
        "an unregistered generic resource is invisible to reflection \
         (auto-registration skips generics — the T16-T1 finding)"
    );

    // The green half: one call each brings the whole face up, and the
    // resource then serializes the way BRP's `get_resources` does.
    let mut app = App::new();
    app.init_resource::<AppTypeRegistry>();
    app.register_type::<TestProfile>();
    app.register_type::<SaveStatus>();
    app.register_type::<SaveStore<TestProfile>>();
    let mut store = SaveStore::<TestProfile>::default();
    store.profile = played_profile();
    store.dirty = true;
    app.insert_resource(store);

    let registry = app.world().resource::<AppTypeRegistry>().clone();
    {
        let registry = registry.read();
        assert!(registry.contains(TypeId::of::<SaveStore<TestProfile>>()));
        assert!(registry.contains(TypeId::of::<SaveStatus>()));
        assert!(registry.contains(TypeId::of::<TestProfile>()));
        let serializer = ReflectSerializer::new(
            app.world()
                .resource::<SaveStore<TestProfile>>()
                .as_partial_reflect(),
            &registry,
        );
        let text = serde_json::to_string(&serializer).expect("the BRP face serializes");
        let value: JsonValue = serde_json::from_str(&text).expect("the BRP face reads as JSON");
        // ReflectSerializer wraps the fields under the resource's full
        // registered type name — exactly the key a BRP client walks.
        let object = value.as_object().expect("an object");
        let inner = object
            .values()
            .next()
            .expect("the resource sits under its type name");
        assert!(
            object.contains_key("jackdaw_runtime::save::SaveStore<save_store::TestProfile>"),
            "the resource answers under its full type path: {value}"
        );
        assert!(
            inner.get("profile").is_some()
                && inner.get("status").is_some()
                && inner.get("dirty").is_some(),
            "profile, status and dirty are the assertable face: {value}"
        );
        assert_eq!(
            inner
                .get("profile")
                .and_then(|profile| profile.get("runs_played"))
                .and_then(JsonValue::as_u64),
            Some(3),
            "the fields under the profile read through: {value}"
        );
        assert_eq!(
            inner.get("status").and_then(JsonValue::as_str),
            Some("NoDir"),
            "a nowhere-to-live store reads as NoDir through reflection"
        );
    }
}

// ---- M1: restart recovery across two apps -------------------------------

/// One process writes (through the plugin's own flush system, one
/// update), the process boundary is the drop, the second app reads
/// everything back: every profile field equal, status `Loaded`.
#[test]
fn a_save_survives_the_process_boundary_between_two_apps() {
    let _guard = env_lock();
    let scratch = tempfile::tempdir().expect("tempdir");
    set_env("JACKDAW_SAVE_DIR", scratch.path().to_str());

    let mut app1 = App::new();
    app1.add_plugins(SavePlugin::<TestProfile>::new("restart-game"));
    assert!(
        app1.world()
            .get_resource::<SaveStore<TestProfile>>()
            .is_some(),
        "the store is in before the first update"
    );
    {
        let mut store = app1.world_mut().resource_mut::<SaveStore<TestProfile>>();
        store.get_mut().runs_played = 3;
        store.get_mut().unlocked = true;
        store.get_mut().master_volume = 0.4;
        store.get_mut().nickname = "lin".into();
    }
    app1.update();
    assert!(
        scratch.path().join("save.json").is_file(),
        "one update after a mutation lands the file (the flush system)"
    );
    drop(app1);

    let mut app2 = App::new();
    app2.add_plugins(SavePlugin::<TestProfile>::new("restart-game"));
    let store = app2.world().resource::<SaveStore<TestProfile>>();
    assert_eq!(store.status, SaveStatus::Loaded);
    assert_eq!(store.profile, played_profile(), "every field came back");
    assert!(!store.dirty);
    set_env("JACKDAW_SAVE_DIR", None);
}

// ---- M9: a missing file is the quiet default ----------------------------

#[test]
fn a_missing_save_file_starts_fresh_quietly() {
    let scratch = tempfile::tempdir().expect("tempdir");
    let dir = scratch.path().join("fresh-game");
    let (store, warnings) = SaveStore::<TestProfile>::open_in(Some(&dir), &[]);
    assert_eq!(store.status, SaveStatus::Fresh);
    assert_eq!(store.profile, TestProfile::default());
    assert!(
        warnings.is_empty(),
        "no file is the default state, not a problem: {warnings:?}"
    );
    assert!(
        !dir.exists(),
        "the directory is made lazily, at the first write, never by a load"
    );
}

// ---- M10: the version guard ---------------------------------------------

/// A save from a newer build is a `VersionSkipped` load, and the
/// invariant holds: automatic writing is suppressed — the file this
/// build cannot read stays byte-for-byte on disk, through mutations and
/// flushes, until the game deliberately discards it with
/// `reset_to_default`.
#[test]
fn a_newer_save_is_never_overwritten_automatically() {
    let _guard = env_lock();
    let scratch = tempfile::tempdir().expect("tempdir");
    set_env("JACKDAW_SAVE_DIR", scratch.path().to_str());
    let dir = scratch.path().to_path_buf();
    let original = r#"{"save_version": 99, "saved_at": "2031-01-01T00:00:00Z", "profile": {"runs_played": 7}}"#;
    write_envelope(&dir, original);
    let before = file_text(&dir);

    let mut app = App::new();
    app.add_plugins(SavePlugin::<TestProfile>::new("newer-game"));
    let store = app.world().resource::<SaveStore<TestProfile>>();
    assert_eq!(store.status, SaveStatus::VersionSkipped { found: 99 });
    assert_eq!(
        store.profile,
        TestProfile::default(),
        "the default stands in"
    );

    // Mutate and let the flush system run — the disk still holds the
    // original bytes.
    app.world_mut()
        .resource_mut::<SaveStore<TestProfile>>()
        .get_mut()
        .runs_played = 1;
    for _ in 0..3 {
        app.update();
    }
    assert_eq!(
        file_text(&dir),
        before,
        "the invariant: an unreadable save is never overwritten by the default"
    );

    // The explicit API refuses too — the same guard, one error.
    let mut refused = app.world_mut().resource_mut::<SaveStore<TestProfile>>();
    let error = refused.write().expect_err("writing is refused");
    assert!(matches!(
        error,
        jackdaw_runtime::SaveError::VersionGuard { found: 99 }
    ));
    assert_eq!(file_text(&dir), before);

    // reset_to_default is the deliberate discard: the guard lifts and
    // the write goes through at the current version.
    let mut store = app.world_mut().resource_mut::<SaveStore<TestProfile>>();
    store.reset_to_default();
    store.write().expect("the deliberate overwrite");
    let value: JsonValue = serde_json::from_str(&file_text(&dir)).expect("valid json");
    assert_eq!(
        value.get("save_version").and_then(JsonValue::as_u64),
        Some(jackdaw_runtime::SAVE_VERSION as u64),
        "the discard writes the current envelope"
    );
    set_env("JACKDAW_SAVE_DIR", None);
}

/// An older version with no registered migration reads as
/// `VersionSkipped` too — same suppression.
#[test]
fn an_older_save_without_a_migration_is_suppressed_too() {
    let scratch = tempfile::tempdir().expect("tempdir");
    let dir = scratch.path().join("older-game");
    let original =
        r#"{"save_version": 0, "saved_at": "2020-01-01T00:00:00Z", "profile": {"runs_played": 2}}"#;
    write_envelope(&dir, original);
    let before = file_text(&dir);

    let (mut store, warnings) = SaveStore::<TestProfile>::open_in(Some(&dir), &[]);
    assert_eq!(store.status, SaveStatus::VersionSkipped { found: 0 });
    assert_eq!(store.profile, TestProfile::default());
    assert!(
        !warnings.is_empty(),
        "a save this build cannot read says so in the log"
    );
    assert!(store.write().is_err(), "the guard refuses the write");
    assert_eq!(file_text(&dir), before, "the file is untouched");
}

/// A registered migration upgrades in place: the chain walks the
/// profile to the current version and the save loads as `Loaded`. A
/// migration whose apply fails degrades to `VersionSkipped` (still no
/// overwrite).
#[test]
fn a_registered_migration_upgrades_an_older_save() {
    let scratch = tempfile::tempdir().expect("tempdir");
    let dir = scratch.path().join("migrated-game");
    write_envelope(
        &dir,
        r#"{"save_version": 0, "saved_at": "2020-01-01T00:00:00Z", "profile": {"runs_played": 5}}"#,
    );

    let mut store = SaveStore::<TestProfile>::open_in(
        Some(&dir),
        &[jackdaw_runtime::SaveMigration::new(0, 1, |mut value| {
            value["nickname"] = JsonValue::String("carried".into());
            value["unlocked"] = JsonValue::Bool(true);
            value["master_volume"] = JsonValue::from(1.0);
            Ok(value)
        })],
    )
    .0;
    assert_eq!(store.status, SaveStatus::Loaded, "the migration carried it");
    assert_eq!(store.profile.runs_played, 5, "old data survives");
    assert_eq!(store.profile.nickname, "carried", "migrated fields apply");
    // The next write stamps the current version.
    store.get_mut().runs_played = 6;
    store.write().expect("write the migrated save");
    let value: JsonValue = serde_json::from_str(&file_text(&dir)).expect("valid json");
    assert_eq!(
        value.get("save_version").and_then(JsonValue::as_u64),
        Some(1)
    );

    // A migration that cannot read the old shape fails the chain, not
    // the load: VersionSkipped, file untouched.
    write_envelope(
        &dir,
        r#"{"save_version": 0, "saved_at": "x", "profile": {}}"#,
    );
    let before = file_text(&dir);
    let (store, _warnings) = SaveStore::<TestProfile>::open_in(
        Some(&dir),
        &[jackdaw_runtime::SaveMigration::new(0, 1, |_value| {
            Err("too damaged to migrate".into())
        })],
    );
    assert_eq!(
        store.status,
        SaveStatus::VersionSkipped { found: 0 },
        "a failed migration is a skipped version, not a corrupt file"
    );
    assert_eq!(file_text(&dir), before);
}

/// The migration-boundary probes the T17-T1 QA ran as throwaways,
/// absorbed here so they stay true (QA reflow F):
///
/// * a *degenerate* step (`from == to`) walks backwards — refused, the
///   save is left untouched;
/// * a step that *overshoots* the current version is still a legal
///   walk: the loop stops at `SAVE_VERSION` and the profile's serde
///   final check is the true gate, so the save loads;
/// * a `save_version` too big for `u32` cannot be a version at all —
///   it takes the damaged path (backed up, defaults in), never a
///   `VersionSkipped` that would sit on the file forever.
#[test]
fn migration_chain_boundaries_stay_on_the_safe_side() {
    let scratch = tempfile::tempdir().expect("tempdir");
    let dir = scratch.path().join("boundary-game");

    // Degenerate 0→0: refused as backwards, the file stands.
    write_envelope(
        &dir,
        r#"{"save_version": 0, "saved_at": "2020-01-01T00:00:00Z", "profile": {"runs_played": 2}}"#,
    );
    let before = file_text(&dir);
    let (store, warnings) = SaveStore::<TestProfile>::open_in(
        Some(&dir),
        &[jackdaw_runtime::SaveMigration::new(0, 0, Ok)],
    );
    assert_eq!(store.status, SaveStatus::VersionSkipped { found: 0 });
    assert!(
        warnings
            .iter()
            .any(|warning| warning.contains("walks backwards")),
        "the degenerate step says why: {warnings:?}"
    );
    assert_eq!(file_text(&dir), before, "the file is untouched");

    // Overshoot 0→5 (past SAVE_VERSION 1): the walk ends at 5, serde
    // judges the profile, the save loads and the next write stamps the
    // current version.
    write_envelope(
        &dir,
        r#"{"save_version": 0, "saved_at": "2020-01-01T00:00:00Z", "profile": {"runs_played": 7}}"#,
    );
    let mut store = SaveStore::<TestProfile>::open_in(
        Some(&dir),
        &[jackdaw_runtime::SaveMigration::new(0, 5, |mut value| {
            value["nickname"] = JsonValue::String("overshot".into());
            value["unlocked"] = JsonValue::Bool(false);
            value["master_volume"] = JsonValue::from(1.0);
            Ok(value)
        })],
    )
    .0;
    assert_eq!(store.status, SaveStatus::Loaded, "serde is the true gate");
    assert_eq!(store.profile.runs_played, 7);
    store.get_mut().runs_played = 8;
    store.write().expect("the loaded save writes");
    let value: JsonValue = serde_json::from_str(&file_text(&dir)).expect("valid json");
    assert_eq!(
        value.get("save_version").and_then(JsonValue::as_u64),
        Some(1)
    );

    // A version beyond u32 is not a version: damaged path, backup on
    // disk, defaults in — and the file's bytes survive in the backup.
    write_envelope(
        &dir,
        r#"{"save_version": 5000000000, "saved_at": "2020-01-01T00:00:00Z", "profile": {"runs_played": 9}}"#,
    );
    let bytes = std::fs::read(dir.join("save.json")).expect("the file");
    let (store, _warnings) = SaveStore::<TestProfile>::open_in(Some(&dir), &[]);
    assert!(
        matches!(store.status, SaveStatus::Recovered { backup: Some(_) }),
        "the unreadable envelope takes the damaged path, backed up: {:?}",
        store.status
    );
    let names = backups(&dir);
    assert_eq!(
        names.len(),
        1,
        "the unreadable envelope is backed up like any damage: {names:?}"
    );
    assert_eq!(
        std::fs::read(dir.join(&names[0])).expect("the backup"),
        bytes,
        "the backup carries the original bytes"
    );
    assert_eq!(store.profile, TestProfile::default());
}

/// The read-side API surface the store exposes beside load/write:
/// `dir()`/`save_file()` name where the save lives, and `reload()`
/// re-reads the file over in-memory mutations.
#[test]
fn the_store_reports_its_slot_and_reloads_it() {
    let scratch = tempfile::tempdir().expect("tempdir");
    let dir = scratch.path().join("slot-game");
    write_envelope(
        &dir,
        r#"{"save_version": 1, "saved_at": "2020-01-01T00:00:00Z",
            "profile": {"runs_played": 4, "unlocked": true, "master_volume": 1.0, "nickname": "lin"}}"#,
    );
    let mut store = SaveStore::<TestProfile>::open_in(Some(&dir), &[]).0;
    assert_eq!(store.status, SaveStatus::Loaded);
    assert_eq!(store.dir(), Some(dir.as_path()));
    assert_eq!(store.save_file(), Some(dir.join("save.json")));

    // In-memory mutations are dropped by a reload, not merged.
    store.get_mut().runs_played = 99;
    assert_eq!(store.reload(), SaveStatus::Loaded);
    assert_eq!(store.profile.runs_played, 4, "reload re-reads the file");
    assert!(!store.dirty, "reload leaves nothing pending");
}

// ---- M11: corrupt saves are backed up, never fatal ----------------------

/// Every damaged shape — bad JSON, an empty file, binary garbage, a
/// half-written file, and a same-version envelope whose profile does
/// not fit the schema — lands as `Recovered` with the original renamed
/// to `save.json.corrupt-<millis>` beside where it was.
#[test]
fn a_corrupt_save_is_backed_up_and_the_game_runs_on() {
    let shapes: Vec<(&str, Vec<u8>)> = vec![
        ("not json", b"{ this is not json".to_vec()),
        ("empty file", Vec::new()),
        ("binary garbage", vec![0x00, 0x9F, 0x92, 0x96, 0xFF, 0xE2]),
        ("half a file", b"{ \"save_version\": 1, \"prof".to_vec()),
        (
            "wrong-schema profile",
            br#"{"save_version": 1, "saved_at": "2026-01-01T00:00:00Z", "profile": {"runs_played": "seven"}}"#
                .to_vec(),
        ),
    ];
    for (name, bytes) in &shapes {
        let scratch = tempfile::tempdir().expect("tempdir");
        let dir = scratch.path().join("damaged-game");
        write_envelope(&dir, "");
        std::fs::write(dir.join("save.json"), bytes).expect("the damaged bytes");

        let (store, warnings) = SaveStore::<TestProfile>::open_in(Some(&dir), &[]);
        let SaveStatus::Recovered { backup } = &store.status else {
            panic!(
                "{name}: a damaged save reads as Recovered, got {:?}",
                store.status
            );
        };
        assert_eq!(
            store.profile,
            TestProfile::default(),
            "{name}: the default stands"
        );
        assert!(
            !warnings.is_empty(),
            "{name}: the damage says so in the log"
        );
        let backup = backup.as_deref().expect("{name}: the backup path");
        let backup_path = dir.join(backup);
        assert!(
            backup_path.is_file(),
            "{name}: the original bytes survive as {backup}"
        );
        assert_eq!(
            std::fs::read(&backup_path).expect("the backup bytes"),
            *bytes,
            "{name}: the backup holds the original bytes verbatim"
        );
        assert!(
            !dir.join("save.json").is_file(),
            "{name}: the canonical slot is empty until the next write"
        );
        // And the next write repopulates it from the default.
        let mut store = store;
        store.get_mut().runs_played = 1;
        store.write().expect("{name}: the game writes on");
        assert!(dir.join("save.json").is_file());
        assert_eq!(backups(&dir).len(), 1, "{name}: exactly one backup");
    }
}

/// Two damaged loads in a row leave two backups: one per event, no
/// cleanup, no clobbering (SV7 records that nothing prunes them).
#[test]
fn every_corrupt_load_leaves_its_own_backup() {
    let scratch = tempfile::tempdir().expect("tempdir");
    let dir = scratch.path().join("twice-game");
    std::fs::create_dir_all(&dir).expect("save dir");
    std::fs::write(dir.join("save.json"), "junk one").expect("first junk");
    let (first, _) = SaveStore::<TestProfile>::open_in(Some(&dir), &[]);
    let SaveStatus::Recovered {
        backup: first_backup,
    } = &first.status
    else {
        panic!("the first damaged load is Recovered");
    };
    let first_backup = first_backup.clone().expect("the first backup path");

    std::thread::sleep(std::time::Duration::from_millis(2));
    std::fs::write(dir.join("save.json"), "junk two").expect("second junk");
    let (second, _) = SaveStore::<TestProfile>::open_in(Some(&dir), &[]);
    let SaveStatus::Recovered {
        backup: second_backup,
    } = &second.status
    else {
        panic!("the second damaged load is Recovered");
    };
    let second_backup = second_backup.clone().expect("the second backup path");

    assert_ne!(
        first_backup, second_backup,
        "distinct events, distinct backups"
    );
    assert_eq!(
        backups(&dir),
        vec![first_backup.clone(), second_backup.clone()],
        "both survive on disk"
    );
    assert_eq!(
        std::fs::read_to_string(dir.join(&first_backup)).expect("first backup"),
        "junk one",
        "each backup holds its own event's bytes"
    );
}

// ---- M12: directory trouble ---------------------------------------------

/// A directory the process cannot write into makes the write fail with
/// one error and the in-memory profile keeps running — the game never
/// crashes over a save.
#[test]
#[cfg(unix)]
fn an_unwritable_directory_warns_and_the_game_keeps_running() {
    let scratch = tempfile::tempdir().expect("tempdir");
    let dir = scratch.path().join("readonly-game");
    std::fs::create_dir_all(&dir).expect("save dir");
    let mut permissions = std::fs::metadata(&dir).expect("metadata").permissions();
    permissions.set_mode(0o500);
    std::fs::set_permissions(&dir, permissions.clone()).expect("chmod");

    let (mut store, warnings) = SaveStore::<TestProfile>::open_in(Some(&dir), &[]);
    assert!(
        warnings.is_empty(),
        "the load is clean; the trouble is at write"
    );
    store.get_mut().runs_played = 1;
    let error = store
        .write()
        .expect_err("a read-only directory refuses the write");
    assert!(
        matches!(error, jackdaw_runtime::SaveError::Io(_)),
        "the error is the io failure: {error}"
    );
    assert!(
        store.dirty,
        "the change is not dropped silently: it stays pending"
    );
    assert_eq!(store.profile.runs_played, 1, "memory keeps running");

    // Writable again, the pending change lands on the next attempt.
    permissions.set_mode(0o755);
    std::fs::set_permissions(&dir, permissions).expect("chmod back");
    store.write().expect("the retry succeeds");
    assert!(!store.dirty);
    assert!(dir.join("save.json").is_file());
}

// ---- M7: the input restore leg's merge semantics -------------------------

/// The input table a save came back with merges over the built-in
/// defaults as a union — same-name entries from the save win, actions
/// the save never knew keep their defaults — so an old save never
/// eats an action a newer game added.
#[test]
fn the_saved_input_table_merges_with_the_defaults_as_a_union() {
    let scratch = tempfile::tempdir().expect("tempdir");
    let dir = scratch.path().join("input-game");
    let mut store = SaveStore::<Vec<GameActionDef>>::open_in(Some(&dir), &[]).0;
    *store.get_mut() = vec![GameActionDef {
        name: "Move".into(),
        kind: GameActionKind::Button,
        bindings: vec![GameInputBinding::Key(
            bevy::input::keyboard::KeyCode::ArrowUp,
        )],
    }];
    store.write().expect("write");

    let (reloaded, _) = SaveStore::<Vec<GameActionDef>>::open_in(Some(&dir), &[]);
    assert_eq!(reloaded.status, SaveStatus::Loaded);
    let merged = merge_actions(&GameInputConfig::defaults().actions, &reloaded.profile);
    let r#move = merged.iter().find(|def| def.name == "Move").expect("Move");
    assert_eq!(
        r#move.kind,
        GameActionKind::Button,
        "the save's rebinding wins for the action it names"
    );
    let jump = merged.iter().find(|def| def.name == "Jump").expect("Jump");
    assert!(
        jump.bindings.iter().any(|binding| matches!(
            binding,
            GameInputBinding::Key(bevy::input::keyboard::KeyCode::Space)
        )),
        "an action the save omits keeps its default bindings"
    );
    assert_eq!(merged.len(), GameInputConfig::defaults().actions.len());
}

// ---- The write path: envelope shape, lazy directory, atomicity ----------

/// The envelope the file actually carries: the three top-level fields
/// in order, a current `save_version`, an RFC 3339 `saved_at`, and the
/// profile under `profile` — the shape QA's `jq` assertions walk.
#[test]
fn the_on_disk_envelope_shape_is_pinned() {
    let scratch = tempfile::tempdir().expect("tempdir");
    let dir = scratch.path().join("shape-game");
    let mut store = SaveStore::<TestProfile>::open_in(Some(&dir), &[]).0;
    store.profile = played_profile();
    store.write().expect("write");

    let text = file_text(&dir);
    assert!(
        text.starts_with("{\n  \"save_version\": 1,\n  \"saved_at\": \""),
        "the envelope's fields lead version, then saved_at, pretty-printed: {text}"
    );
    let value: JsonValue = serde_json::from_str(&text).expect("valid json");
    let object = value.as_object().expect("an object");
    // (serde_json's parsed map sorts keys; the file order itself is
    // pinned by the raw-text assert above.)
    let keys: Vec<&str> = object.keys().map(String::as_str).collect();
    assert_eq!(
        keys,
        vec!["profile", "save_version", "saved_at"],
        "exactly the three envelope fields"
    );
    let saved_at = object
        .get("saved_at")
        .and_then(JsonValue::as_str)
        .expect("saved_at");
    assert_eq!(
        saved_at.len(),
        20,
        "RFC 3339 UTC, second precision: {saved_at}"
    );
    assert!(
        saved_at.ends_with('Z') && saved_at.as_bytes()[4] == b'-' && saved_at.as_bytes()[7] == b'-',
        "the date form: {saved_at}"
    );
    assert_eq!(
        object.get("profile"),
        Some(&serde_json::json!({
            "runs_played": 3,
            "unlocked": true,
            "master_volume": 0.4,
            "nickname": "lin"
        })),
        "the profile rides under its own key, unchanged"
    );
}

/// A write from a load that never made a directory creates the whole
/// chain; a stray `.tmp` from an interrupted write is neither taken
/// for a save nor allowed to break the next one.
#[test]
fn a_stray_temp_file_is_never_taken_for_a_save() {
    let scratch = tempfile::tempdir().expect("tempdir");
    let dir = scratch.path().join("atomic-game");
    std::fs::create_dir_all(&dir).expect("the game made the dir once");
    std::fs::write(dir.join("save.json.tmp"), "half-written junk").expect("stray tmp");

    // The load reads only save.json: a stray tmp is a Fresh start.
    let (store, warnings) = SaveStore::<TestProfile>::open_in(Some(&dir), &[]);
    assert_eq!(store.status, SaveStatus::Fresh, "the tmp is not a save");
    assert!(warnings.is_empty());

    // The write replaces the tmp wholesale and lands the real file.
    let mut store = store;
    store.get_mut().nickname = "after".into();
    store.write().expect("write over the stray");
    assert!(
        std::fs::read_to_string(dir.join("save.json"))
            .expect("the real file")
            .contains("\"after\""),
        "the new save is complete"
    );
    assert!(
        !dir.join("save.json.tmp").exists(),
        "the tmp is consumed by the rename, not left behind"
    );
}

// ---- The plugin: flush wiring --------------------------------------------

/// The before/after pair for the auto-write system: a store mutated
/// without the plugin's flush system never reaches the disk (every
/// game before this module existed); with the plugin, one update after
/// the mutation lands the file.
#[test]
fn the_flush_system_is_what_carries_a_mutation_to_disk() {
    let scratch = tempfile::tempdir().expect("tempdir");
    let dir = scratch.path().join("flush-game");

    // The red half: a store nobody flushes.
    let mut app = App::new();
    app.insert_resource(SaveStore::<TestProfile>::open_in(Some(&dir), &[]).0);
    app.world_mut()
        .resource_mut::<SaveStore<TestProfile>>()
        .get_mut()
        .runs_played = 9;
    for _ in 0..5 {
        app.update();
    }
    assert!(
        !dir.join("save.json").is_file(),
        "without the flush system a mutation never reaches the disk"
    );

    // The green half: the plugin brings the system, the same mutation
    // persists on the first update (env seam held for the build, the
    // way every plugin-level leg here does).
    let _guard = env_lock();
    set_env("JACKDAW_SAVE_DIR", scratch.path().to_str());
    let mut app = App::new();
    app.add_plugins(SavePlugin::<TestProfile>::new("flush-game"));
    app.world_mut()
        .resource_mut::<SaveStore<TestProfile>>()
        .get_mut()
        .runs_played = 9;
    app.update();
    assert!(
        scratch.path().join("save.json").is_file(),
        "the flush system wrote"
    );
    let (reloaded, _) = SaveStore::<TestProfile>::open_in(Some(scratch.path()), &[]);
    assert_eq!(reloaded.profile.runs_played, 9);
    set_env("JACKDAW_SAVE_DIR", None);
}

/// An unresolvable directory (env unset, no data dir, no home) loads
/// as `NoDir` and refuses writes without ever panicking — the M12
/// bottom edge, tested at the resolution layer where `None` is
/// constructible (`save.rs`'s inline test covers the layering).
#[test]
fn a_missing_directory_is_a_quiet_nodir() {
    let (mut store, warnings) = SaveStore::<TestProfile>::open_in(None, &[]);
    assert_eq!(store.status, SaveStatus::NoDir);
    assert_eq!(store.profile, TestProfile::default());
    assert!(
        warnings.is_empty(),
        "nothing was on disk to be wrong about: {warnings:?}"
    );
    assert!(
        matches!(store.write(), Err(jackdaw_runtime::SaveError::NoSaveDir)),
        "nowhere to write, said plainly"
    );
}
