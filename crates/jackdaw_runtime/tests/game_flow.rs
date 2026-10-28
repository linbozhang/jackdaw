//! The project's game flow file: `game.flow.json` names the scene a
//! standalone game starts from (T13-T2).
//!
//! The runtime reads one field of it — `start_scene` — and every problem
//! warns and falls back to the scene the game's code names, because a
//! broken or missing flow file must never keep a game from starting:
//!
//! * no flow file: the quiet default (the state every pre-T13 project is
//!   in) — the fallback, no warnings;
//! * unreadable JSON, a missing or mis-typed `start_scene`, a path that
//!   leaves the assets folder or names nothing on disk: the fallback and
//!   a warning that names what was wrong;
//! * fields the schema does not know: warned, the rest still reads;
//! * the editor's Play override composes **around** the flow read —
//!   `pie_scene_or(&flow::start_scene_or(fallback))` — so a `play_current`
//!   launch plays the scene in front of the editor even when the project
//!   has a flow file (the priority the T06 semantics stand on).
//!
//! The parse-level legs go through the explicit-root seam
//! ([`jackdaw_runtime::flow::start_scene_in`]) so they need no
//! environment; the public-surface and priority legs hold an env lock
//! the way `pie_scene_override.rs` does, with the asset root laid out
//! the way the reader resolves it: `BEVY_ASSET_ROOT` + the `assets`
//! folder.

use bevy::prelude::*;
use jackdaw_runtime::flow;
use jackdaw_runtime::{JackdawPlugin, JackdawScene, JackdawSceneRoot};

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

fn write(dir: &std::path::Path, name: &str, text: &str) {
    std::fs::write(dir.join(name), text).expect("write the file");
}

/// A project laid out as a standalone run finds it: an `assets` folder
/// beside (or below) the asset-root base, holding the scenes and the
/// flow file.
fn project_dir() -> (tempfile::TempDir, std::path::PathBuf) {
    let base = tempfile::tempdir().expect("tempdir");
    let assets = base.path().join("assets");
    std::fs::create_dir_all(&assets).expect("assets folder");
    (base, assets)
}

fn flow_json(start_scene: &str) -> String {
    format!(r#"{{"start_scene": "{start_scene}"}}"#)
}

// ---- The parse legs, through the explicit-root seam --------------------

#[test]
fn the_flow_file_names_the_start_scene() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "menu.bsn", "#MenuRoot\n");
    write(dir.path(), flow::FLOW_FILE, &flow_json("menu.bsn"));

    let (scene, warnings) = flow::start_scene_in(Some(dir.path()), "scene.bsn");
    assert_eq!(scene, "menu.bsn", "the flow file's start scene wins");
    assert!(warnings.is_empty(), "a healthy flow file warns nothing");
}

#[test]
fn no_flow_file_falls_back_quietly() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "scene.bsn", "#Anchor\n");

    let (scene, warnings) = flow::start_scene_in(Some(dir.path()), "scene.bsn");
    assert_eq!(scene, "scene.bsn");
    assert!(
        warnings.is_empty(),
        "a project without a flow file is the default state, not a problem"
    );

    // No assets folder at all reads the same.
    let (scene, warnings) = flow::start_scene_in(None, "scene.bsn");
    assert_eq!(scene, "scene.bsn");
    assert!(warnings.is_empty());
}

#[test]
fn a_broken_flow_file_falls_back_loudly() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "scene.bsn", "#Anchor\n");
    write(dir.path(), flow::FLOW_FILE, "{ this is not json");

    let (scene, warnings) = flow::start_scene_in(Some(dir.path()), "scene.bsn");
    assert_eq!(
        scene, "scene.bsn",
        "a broken flow file never keeps the game down"
    );
    assert_eq!(warnings.len(), 1, "one problem, one warning: {warnings:?}");
    assert!(
        warnings[0].contains("JSON"),
        "the warning says what failed to read: {}",
        warnings[0]
    );
}

#[test]
fn an_unusable_start_scene_falls_back_loudly() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "scene.bsn", "#Anchor\n");

    // No start_scene key at all.
    write(dir.path(), flow::FLOW_FILE, r#"{"scenes": ["scene.bsn"]}"#);
    let (scene, warnings) = flow::start_scene_in(Some(dir.path()), "scene.bsn");
    assert_eq!(scene, "scene.bsn");
    assert!(
        warnings
            .iter()
            .any(|warning| warning.contains("start_scene")),
        "the warning names the missing key: {warnings:?}"
    );

    // A start_scene that is not a string.
    write(dir.path(), flow::FLOW_FILE, r#"{"start_scene": 42}"#);
    let (scene, warnings) = flow::start_scene_in(Some(dir.path()), "scene.bsn");
    assert_eq!(scene, "scene.bsn");
    assert!(!warnings.is_empty(), "{warnings:?}");

    // A path that leaves the assets folder.
    write(
        dir.path(),
        flow::FLOW_FILE,
        r#"{"start_scene": "../escape.bsn"}"#,
    );
    let (scene, warnings) = flow::start_scene_in(Some(dir.path()), "scene.bsn");
    assert_eq!(scene, "scene.bsn");
    assert!(!warnings.is_empty(), "{warnings:?}");
}

#[test]
fn a_start_scene_off_disk_falls_back_naming_it() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "scene.bsn", "#Anchor\n");
    write(dir.path(), flow::FLOW_FILE, &flow_json("ghost.bsn"));

    let (scene, warnings) = flow::start_scene_in(Some(dir.path()), "scene.bsn");
    assert_eq!(
        scene, "scene.bsn",
        "a start scene that is not on disk falls back to the code's default"
    );
    assert_eq!(warnings.len(), 1, "{warnings:?}");
    assert!(
        warnings[0].contains("ghost.bsn"),
        "the warning names the scene it could not find: {}",
        warnings[0]
    );
    assert!(
        warnings[0].contains("scene.bsn"),
        "the warning names what it falls back to: {}",
        warnings[0]
    );
}

#[test]
fn unknown_fields_are_warned_not_fatal() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "menu.bsn", "#MenuRoot\n");
    write(
        dir.path(),
        flow::FLOW_FILE,
        r#"{"start_scene": "menu.bsn", "legacy_start": "scene.bsn"}"#,
    );

    let (scene, warnings) = flow::start_scene_in(Some(dir.path()), "scene.bsn");
    assert_eq!(
        scene, "menu.bsn",
        "an unknown field does not sink the start scene"
    );
    assert_eq!(warnings.len(), 1, "{warnings:?}");
    assert!(
        warnings[0].contains("legacy_start"),
        "the warning names the field it does not know: {}",
        warnings[0]
    );
}

#[test]
fn a_scene_list_is_read_but_not_enforced() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "menu.bsn", "#MenuRoot\n");
    // A list the start scene is not in, with a duplicate and a missing
    // entry: the game's business is start_scene alone (the list is the
    // editor's and the export's to check), so none of it stops the read.
    write(
        dir.path(),
        flow::FLOW_FILE,
        r#"{"start_scene": "menu.bsn", "scenes": ["menu.bsn", "menu.bsn", "ghost.bsn"]}"#,
    );

    let (scene, warnings) = flow::start_scene_in(Some(dir.path()), "scene.bsn");
    assert_eq!(scene, "menu.bsn");
    assert!(
        warnings.is_empty(),
        "the runtime does not police the list the editor validates: {warnings:?}"
    );
}

// ---- The public surface and the PIE priority ---------------------------

#[test]
fn the_public_reader_resolves_the_asset_root() {
    let _guard = env_lock();
    let (base, assets) = project_dir();
    write(&assets, "menu.bsn", "#MenuRoot\n");
    write(&assets, flow::FLOW_FILE, &flow_json("menu.bsn"));

    set_env("BEVY_ASSET_ROOT", base.path().to_str());
    let scene = flow::start_scene_or("scene.bsn");
    set_env("BEVY_ASSET_ROOT", None);
    assert_eq!(scene, "menu.bsn", "the public reader finds the flow file");
}

/// The engine under a game: the pieces `main.rs.template`'s
/// `DefaultPlugins` provide headless, with assets read from the
/// project's `assets` folder.
fn app_reading(assets: &std::path::Path) -> App {
    let mut app = App::new();
    app.add_plugins(MinimalPlugins);
    app.add_plugins(bevy::transform::TransformPlugin);
    app.add_plugins(bevy::asset::AssetPlugin {
        file_path: assets.to_string_lossy().into_owned(),
        ..Default::default()
    });
    app.add_plugins(bevy::world_serialization::WorldSerializationPlugin);
    app.add_plugins(JackdawPlugin);
    app
}

/// The template's one startup line: the editor's override composes
/// around the flow read, the code's scene is the innermost fallback.
fn spawn_the_template_root(app: &mut App) {
    let handle =
        app.world()
            .resource::<AssetServer>()
            .load::<JackdawScene>(jackdaw_runtime::pie_scene_or(&flow::start_scene_or(
                "scene.bsn",
            )));
    app.world_mut().spawn(JackdawSceneRoot(handle));
}

/// The names the loaded scene's entities carry — what a content
/// assertion reads, not which handle the root holds.
fn spawned_names(app: &mut App) -> Vec<String> {
    let mut names = app.world_mut().query::<&Name>();
    names
        .iter(app.world())
        .map(|name| name.as_str().to_string())
        .collect()
}

fn pump_until(app: &mut App, needle: &str) -> Vec<String> {
    for _ in 0..300 {
        app.update();
        let names = spawned_names(app);
        if names.iter().any(|name| name == needle) {
            return names;
        }
    }
    spawned_names(app)
}

#[test]
fn a_standalone_run_starts_from_the_flow_file() {
    let _guard = env_lock();
    set_env("JACKDAW_PIE_SCENE", None);
    let (base, assets) = project_dir();
    write(&assets, "scene.bsn", "#Anchor\n");
    write(&assets, "menu.bsn", "#MenuRoot\n");
    write(&assets, flow::FLOW_FILE, &flow_json("menu.bsn"));

    set_env("BEVY_ASSET_ROOT", base.path().to_str());
    let mut app = app_reading(&assets);
    spawn_the_template_root(&mut app);
    let names = pump_until(&mut app, "MenuRoot");
    set_env("BEVY_ASSET_ROOT", None);
    assert!(
        names.contains(&"MenuRoot".to_string()),
        "the flow file's start scene loaded: {names:?}"
    );
    assert!(
        !names.contains(&"Anchor".to_string()),
        "the code's fallback scene did not: {names:?}"
    );
}

#[test]
fn the_pie_override_wins_over_the_flow_file() {
    let _guard = env_lock();
    let (base, assets) = project_dir();
    write(&assets, "scene.bsn", "#Anchor\n");
    write(&assets, "menu.bsn", "#MenuRoot\n");
    write(&assets, "override.bsn", "#Overridee\n");
    write(&assets, flow::FLOW_FILE, &flow_json("menu.bsn"));

    set_env("JACKDAW_PIE_SCENE", Some("override.bsn"));
    set_env("BEVY_ASSET_ROOT", base.path().to_str());
    let mut app = app_reading(&assets);
    spawn_the_template_root(&mut app);
    let names = pump_until(&mut app, "Overridee");
    set_env("JACKDAW_PIE_SCENE", None);
    set_env("BEVY_ASSET_ROOT", None);
    assert!(
        names.contains(&"Overridee".to_string()),
        "Play's override scene loaded: {names:?}"
    );
    assert!(
        !names.contains(&"MenuRoot".to_string()),
        "the flow file's start scene stood down: {names:?}"
    );
}
