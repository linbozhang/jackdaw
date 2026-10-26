//! The editor's scene override: `JACKDAW_PIE_SCENE` swaps the first scene
//! root's handle for the override scene before the spawn loop runs, so a
//! game launched from the editor loads the scene the editor has in front
//! rather than the one its own code named (T06 N1).
//!
//! The tests only use the public runtime API plus the raw environment
//! variable, so they compile against a runtime without the override and
//! fail there: that failure is the red side of the N1 red-green pair.

use bevy::prelude::*;
use jackdaw_runtime::{JackdawPlugin, JackdawScene, JackdawSceneRoot};

/// The tests set and clear a process-wide environment variable, so they
/// must never run at the same time. A panic while held must not take the
/// whole file down with it, so a poisoned lock is recovered rather than
/// propagated: the variable is cleared at the start of every test anyway.
static ENV_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

fn env_lock() -> std::sync::MutexGuard<'static, ()> {
    ENV_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
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
