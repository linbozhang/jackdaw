//! The editor's scene override: `JACKDAW_PIE_SCENE` swaps the first scene
//! root's handle for the override scene before the spawn loop runs, so a
//! game launched from the editor loads the scene the editor has in front
//! rather than the one its own code named (T06 N1).
//!
//! The tests only use the public runtime API plus the raw environment
//! variable, so they compile against a runtime without the override and
//! fail there: that failure is the red side of the N1 red-green pair.

use bevy::asset::AssetPath;
use bevy::prelude::*;
use jackdaw_runtime::{JackdawPlugin, JackdawScene, JackdawSceneRoot, PieSceneOverride};
use std::path::{Path, PathBuf};
use std::time::Duration;

/// The tests set and clear a process-wide environment variable, so they
/// must never run at the same time. A panic while held must not take the
/// whole file down with it, so a poisoned lock is recovered rather than
/// propagated: the variable is cleared at the start of every test anyway.
static ENV_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

fn env_lock() -> std::sync::MutexGuard<'static, ()> {
    ENV_LOCK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// A scene whose one root is named `Anchor`.
const SCENE_A: &str = r#"
#Anchor
bevy_transform::components::transform::Transform {
    translation: glam::Vec3 { x: 4.0, y: 5.0, z: 6.0 },
}
"#;

/// A scene whose one root is named `Overridee`.
const SCENE_B: &str = r#"
#Overridee
bevy_transform::components::transform::Transform {
    translation: glam::Vec3 { x: 99.0, y: 0.0, z: 0.0 },
}
"#;

/// A second game-authored scene, named `Second`.
const SCENE_C: &str = r#"
#Second
bevy_transform::components::transform::Transform {
    translation: glam::Vec3 { x: 0.0, y: 7.0, z: 0.0 },
}
"#;

fn set_scene_env(value: Option<&str>) {
    // SAFETY: every test in this file holds `ENV_LOCK` for its whole body,
    // so no other thread of this process reads or writes the variable while
    // it is being set or removed.
    match value {
        Some(value) => unsafe { std::env::set_var("JACKDAW_PIE_SCENE", value) },
        None => unsafe { std::env::remove_var("JACKDAW_PIE_SCENE") },
    }
}

/// A headless app whose assets read from `dir`, with the override system
/// in its normal schedule slot (whatever the runtime installs).
fn app_reading(dir: &std::path::Path) -> App {
    let mut app = App::new();
    app.add_plugins(MinimalPlugins);
    app.add_plugins(bevy::transform::TransformPlugin);
    app.add_plugins(bevy::asset::AssetPlugin {
        file_path: dir.to_string_lossy().into_owned(),
        ..Default::default()
    });
    app.add_plugins(bevy::world_serialization::WorldSerializationPlugin);
    app.add_plugins(JackdawPlugin);
    app
}

fn write(dir: &std::path::Path, name: &str, text: &str) {
    std::fs::write(dir.join(name), text).expect("write the scene file");
}

/// The names of every spawned scene entity, which is what a content
/// assertion reads: not which handle the root holds, but whose entities
/// actually spawned.
fn spawned_names(app: &mut App) -> Vec<String> {
    let mut names = app.world_mut().query::<&Name>();
    names
        .iter(app.world())
        .map(|n| n.as_str().to_string())
        .collect()
}

/// Pump updates until `predicate` holds over the spawned names, and return
/// them; gives up after ~5 seconds and returns whatever spawned.
fn pump_until(app: &mut App, mut predicate: impl FnMut(&[String]) -> bool) -> Vec<String> {
    for _ in 0..300 {
        app.update();
        let names = spawned_names(app);
        if predicate(&names) {
            return names;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    spawned_names(app)
}

/// `pie_scene_or` is the template's spelling: the editor's override when
/// the game was launched from one, the game's own default otherwise. The
/// returned `String` feeds `AssetServer::load` directly.
#[test]
fn pie_scene_or_picks_the_override_or_the_default() {
    let _guard = env_lock();
    set_scene_env(None);
    assert_eq!(
        jackdaw_runtime::pie_scene_or("scene.bsn"),
        "scene.bsn",
        "standalone: the game's own default"
    );
    set_scene_env(Some("props/other.bsn"));
    assert_eq!(
        jackdaw_runtime::pie_scene_or("scene.bsn"),
        "props/other.bsn",
        "launched from the editor: the override wins"
    );
    set_scene_env(None);
}

/// Without the variable, the scene the game's own code named loads, byte
/// for byte the behavior of a runtime without the override system: the
/// regression anchor.
#[test]
fn without_the_env_the_named_scene_loads() {
    let _guard = env_lock();
    set_scene_env(None);

    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "scene.bsn", SCENE_A);
    write(dir.path(), "other.bsn", SCENE_B);

    let mut app = app_reading(dir.path());
    let handle = app
        .world()
        .resource::<AssetServer>()
        .load::<JackdawScene>("scene.bsn");
    app.world_mut().spawn(JackdawSceneRoot(handle));

    let names = pump_until(&mut app, |names| names.iter().any(|n| n == "Anchor"));
    assert!(
        names.iter().any(|n| n == "Anchor"),
        "the named scene's entities spawn: {names:?}"
    );
}

/// With the variable, the override scene's entities spawn and the named
/// scene's do not. Red on a runtime without the override: `Anchor` spawns
/// instead of `Overridee` (N1).
#[test]
fn the_override_scene_loads_in_place_of_the_named_one() {
    let _guard = env_lock();
    set_scene_env(None);

    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "scene.bsn", SCENE_A);
    write(dir.path(), "other.bsn", SCENE_B);

    let mut app = app_reading(dir.path());
    let handle = app
        .world()
        .resource::<AssetServer>()
        .load::<JackdawScene>("scene.bsn");
    app.world_mut().spawn(JackdawSceneRoot(handle));

    // Point the override at the other scene only after the app is built, so
    // the test exercises the running schedule, not a construction-time flag.
    set_scene_env(Some("other.bsn"));

    let names = pump_until(&mut app, |names| names.iter().any(|n| n == "Overridee"));
    assert!(
        names.iter().any(|n| n == "Overridee"),
        "the override scene's entities spawn: {names:?}"
    );
    assert!(
        !names.iter().any(|n| n == "Anchor"),
        "the named scene's entities must not also spawn: {names:?}"
    );
}

/// Several roots: the override replaces only the first one; the rest load
/// the scenes the game's own code named. Red on a runtime without the
/// override (`Anchor` spawns) and red on a runtime that overrides every
/// root (`Second` would be gone).
#[test]
fn only_the_first_scene_root_is_overridden() {
    let _guard = env_lock();
    set_scene_env(None);

    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "scene.bsn", SCENE_A);
    write(dir.path(), "other.bsn", SCENE_B);
    write(dir.path(), "second.bsn", SCENE_C);

    let mut app = app_reading(dir.path());
    let server = app.world().resource::<AssetServer>().clone();
    app.world_mut()
        .spawn(JackdawSceneRoot(server.load::<JackdawScene>("scene.bsn")));
    app.world_mut()
        .spawn(JackdawSceneRoot(server.load::<JackdawScene>("second.bsn")));

    set_scene_env(Some("other.bsn"));

    let names = pump_until(&mut app, |names| {
        names.iter().any(|n| n == "Overridee") && names.iter().any(|n| n == "Second")
    });
    assert!(
        names.iter().any(|n| n == "Overridee"),
        "the first root plays the override: {names:?}"
    );
    assert!(
        names.iter().any(|n| n == "Second"),
        "the second root still plays its own scene: {names:?}"
    );
    assert!(
        !names.iter().any(|n| n == "Anchor"),
        "the first root must not also spawn the named scene: {names:?}"
    );
}

/// The swap is once per process, not once per frame: a root the game's own
/// systems add while running — levels loading, streaming, a second scene
/// the gameplay spawns — keeps the scene it names. Red on a swap that keys
/// on whichever roots are `Added` this frame (the later root would be
/// swapped too, `Second` never spawning, N-QA1).
#[test]
fn a_root_added_while_running_keeps_its_own_scene() {
    let _guard = env_lock();
    set_scene_env(None);

    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "scene.bsn", SCENE_A);
    write(dir.path(), "other.bsn", SCENE_B);
    write(dir.path(), "second.bsn", SCENE_C);

    let mut app = app_reading(dir.path());
    let server = app.world().resource::<AssetServer>().clone();
    app.world_mut()
        .spawn(JackdawSceneRoot(server.load::<JackdawScene>("scene.bsn")));

    set_scene_env(Some("other.bsn"));

    // Let the first root be swapped and the override scene spawn.
    let names = pump_until(&mut app, |names| names.iter().any(|n| n == "Overridee"));
    assert!(
        names.iter().any(|n| n == "Overridee"),
        "the first root plays the override: {names:?}"
    );

    // A later frame's gameplay spawn: its root must not be swapped.
    app.world_mut()
        .spawn(JackdawSceneRoot(server.load::<JackdawScene>("second.bsn")));
    let names = pump_until(&mut app, |names| names.iter().any(|n| n == "Second"));
    assert!(
        names.iter().any(|n| n == "Second"),
        "a root added while running keeps its own scene: {names:?}"
    );
    assert!(
        !names.iter().any(|n| n == "Anchor"),
        "the later root must not fall back to the first root's named scene: {names:?}"
    );
}

// --- The play-scene face (upstream), on top of the scene-override face (local) ---

fn named_scene(name: &str) -> String {
    format!("#{name}\nbevy_transform::components::transform::Transform\n")
}

fn app_over(dir: &Path, play_scene: Option<PieSceneOverride>) -> App {
    let files = [
        ("scene.bsn", "Default"),
        ("hud.bsn", "Hud"),
        ("levels/meadow.bsn", "Meadow"),
        ("levels/boss#2.bsn", "Boss"),
    ];
    for (file, name) in files {
        let path = dir.join(file);
        std::fs::create_dir_all(path.parent().expect("a folder")).expect("folder");
        std::fs::write(path, named_scene(name)).expect("scene written");
    }

    let mut app = App::new();
    app.add_plugins(MinimalPlugins);
    app.add_plugins(bevy::transform::TransformPlugin);
    app.add_plugins(bevy::asset::AssetPlugin {
        file_path: dir.to_string_lossy().into_owned(),
        ..Default::default()
    });
    app.add_plugins(bevy::world_serialization::WorldSerializationPlugin);
    if let Some(play_scene) = play_scene {
        app.insert_resource(play_scene);
    }
    app.add_plugins(JackdawPlugin);
    app
}

fn meadow_over_main() -> Option<PieSceneOverride> {
    Some(PieSceneOverride::new("levels/meadow.bsn", "scene.bsn"))
}

fn upstream_spawned_names(app: &mut App, root: Entity) -> Vec<String> {
    let deadline = std::time::Instant::now() + Duration::from_secs(10);
    loop {
        app.update();
        let names: Vec<String> = app
            .world_mut()
            .query::<(&Name, &ChildOf)>()
            .iter(app.world())
            .filter(|(_, parent)| parent.parent() == root)
            .map(|(name, _)| name.to_string())
            .collect();
        if !names.is_empty() || std::time::Instant::now() > deadline {
            return names;
        }
        std::thread::sleep(Duration::from_millis(5));
    }
}

fn spawn_root(app: &mut App, path: &'static str) -> Entity {
    let handle: Handle<JackdawScene> = app.world().resource::<AssetServer>().load(path);
    app.world_mut().spawn(JackdawSceneRoot(handle)).id()
}

fn asked_path(app: &App, root: Entity) -> Option<AssetPath<'static>> {
    app.world()
        .get::<JackdawSceneRoot>(root)
        .and_then(|root| root.0.path().cloned())
}

#[test]
fn under_play_the_main_scene_root_loads_the_open_scene() {
    let dir = tempfile::tempdir().expect("tempdir");
    let mut app = app_over(dir.path(), meadow_over_main());

    let root = spawn_root(&mut app, "scene.bsn");

    assert_eq!(
        upstream_spawned_names(&mut app, root),
        vec!["Meadow".to_string()]
    );
}

#[test]
fn a_hud_spawned_first_is_left_alone_and_the_level_spawns_once() {
    let dir = tempfile::tempdir().expect("tempdir");
    let mut app = app_over(dir.path(), meadow_over_main());

    let hud = spawn_root(&mut app, "hud.bsn");
    let level = spawn_root(&mut app, "scene.bsn");

    assert_eq!(
        upstream_spawned_names(&mut app, hud),
        vec!["Hud".to_string()]
    );
    assert_eq!(
        upstream_spawned_names(&mut app, level),
        vec!["Meadow".to_string()]
    );
    let meadows = app
        .world_mut()
        .query::<&Name>()
        .iter(app.world())
        .filter(|name| name.as_str() == "Meadow")
        .count();
    assert_eq!(meadows, 1);
}

#[test]
fn an_in_memory_root_is_left_alone() {
    let dir = tempfile::tempdir().expect("tempdir");
    let mut app = app_over(dir.path(), meadow_over_main());
    let handle = app
        .world_mut()
        .resource_mut::<Assets<JackdawScene>>()
        .add(JackdawScene::new(named_scene("Built"), PathBuf::new()));

    let root = app.world_mut().spawn(JackdawSceneRoot(handle)).id();

    assert_eq!(
        upstream_spawned_names(&mut app, root),
        vec!["Built".to_string()]
    );
}

#[test]
fn a_root_inserted_again_to_restart_is_redirected_again() {
    let dir = tempfile::tempdir().expect("tempdir");
    let mut app = app_over(dir.path(), meadow_over_main());
    let root = spawn_root(&mut app, "scene.bsn");
    upstream_spawned_names(&mut app, root);

    let handle: Handle<JackdawScene> = app.world().resource::<AssetServer>().load("scene.bsn");
    app.world_mut()
        .entity_mut(root)
        .insert(JackdawSceneRoot(handle));

    assert_eq!(
        asked_path(&app, root),
        Some(AssetPath::from("levels/meadow.bsn"))
    );
}

#[test]
fn an_open_scene_whose_name_holds_a_hash_loads_as_a_file() {
    let dir = tempfile::tempdir().expect("tempdir");
    let mut app = app_over(
        dir.path(),
        Some(PieSceneOverride::new("levels/boss#2.bsn", "scene.bsn")),
    );

    let root = spawn_root(&mut app, "scene.bsn");

    assert_eq!(
        upstream_spawned_names(&mut app, root),
        vec!["Boss".to_string()]
    );
}

#[test]
fn without_an_override_the_game_loads_its_own_scene() {
    let dir = tempfile::tempdir().expect("tempdir");
    let mut app = app_over(dir.path(), None);

    let root = spawn_root(&mut app, "scene.bsn");

    assert_eq!(
        upstream_spawned_names(&mut app, root),
        vec!["Default".to_string()]
    );
}
