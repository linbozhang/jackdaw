//! Rebinding a spawned root's [`JackdawSceneRoot`] to another scene is the
//! runtime scene switch (T13-T1): the old scene's members despawn and the
//! newly bound one instantiates, with the root entity — and everything the
//! game put on it — staying put. The mechanic is the hot-reload chain's, so
//! the tests only use the public runtime API and fail on a runtime without
//! the rebind: that failure is the red side of the S2 red-green pair.

use bevy::prelude::*;
use jackdaw_runtime::{JackdawPlugin, JackdawScene, JackdawSceneRoot, SceneRefused};

/// A scene whose one root is named `Anchor`.
const SCENE_A: &str = r#"
#Anchor
bevy_transform::components::transform::Transform
"#;

/// A scene whose one root is named `Other`.
const SCENE_B: &str = r#"
#Other
bevy_transform::components::transform::Transform
"#;

/// A third scene, named `Third`.
const SCENE_C: &str = r#"
#Third
bevy_transform::components::transform::Transform
"#;

/// Not a document: an entity patch that opens and never closes, so the
/// loader refuses it, and the switch must say so on the root instead of
/// leaving it silently empty.
const BROKEN: &str = "#Anchor\nbevy_transform::components::transform::Transform {\n";

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

/// Pump updates until `handle` has finished loading. The tests rebind to
/// already-loaded scenes on purpose: a target that loads *after* the rebind
/// happens to reload through the asset event path on any runtime, so the
/// no-op defect this file exists to pin only shows on a loaded target.
fn wait_loaded(app: &mut App, handle: &Handle<JackdawScene>) {
    for _ in 0..300 {
        app.update();
        if matches!(
            app.world().resource::<AssetServer>().get_load_state(handle),
            Some(bevy::asset::LoadState::Loaded)
        ) {
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    panic!("the target scene never finished loading");
}

/// The scene's members currently owned by `root`.
fn member_count(app: &mut App, root: Entity) -> usize {
    let mut members = app
        .world_mut()
        .query::<&jackdaw_runtime::JackdawSceneMember>();
    members
        .iter(app.world())
        .filter(|member| member.root == root)
        .count()
}

/// A game-authored marker, to prove the root keeps what the game put on it
/// across a switch.
#[derive(Component, Default)]
struct GameMarker;

/// A rebind of a spawned root swaps the scene: the old scene's entities
/// despawn, the new scene's spawn, and the root entity survives with its own
/// components untouched. Red on a runtime without the rebind: `Other` never
/// spawns because nothing consumes the new handle (S2).
#[test]
fn rebinding_a_spawned_root_swaps_the_scene_under_it() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "scene.bsn", SCENE_A);
    write(dir.path(), "other.bsn", SCENE_B);

    let mut app = app_reading(dir.path());
    let server = app.world().resource::<AssetServer>().clone();
    let root = app
        .world_mut()
        .spawn((
            JackdawSceneRoot(server.load::<JackdawScene>("scene.bsn")),
            GameMarker,
        ))
        .id();

    let names = pump_until(&mut app, |names| names.iter().any(|n| n == "Anchor"));
    assert!(
        names.iter().any(|n| n == "Anchor"),
        "the first scene spawns: {names:?}"
    );
    assert_eq!(member_count(&mut app, root), 1);

    // The switch: one line on the game's side. The target is already
    // loaded — the case a runtime without the rebind leaves as a no-op.
    let replacement = server.load::<JackdawScene>("other.bsn");
    wait_loaded(&mut app, &replacement);
    app.world_mut()
        .entity_mut(root)
        .insert(JackdawSceneRoot(replacement));

    let names = pump_until(&mut app, |names| names.iter().any(|n| n == "Other"));
    assert!(
        names.iter().any(|n| n == "Other"),
        "the rebound scene spawns: {names:?}"
    );
    assert!(
        !names.iter().any(|n| n == "Anchor"),
        "the previous scene must leave zero residue: {names:?}"
    );
    assert_eq!(
        member_count(&mut app, root),
        1,
        "the root owns exactly the new scene's members"
    );
    assert!(
        app.world().get_entity(root).is_ok(),
        "the root entity survives the switch"
    );
    assert!(
        app.world().get::<GameMarker>(root).is_some(),
        "what the game put on the root stays across the switch"
    );
}

/// Re-writing the handle that is already live is not a switch: the scene
/// stays instantiated, member for member. A reload here would tear down and
/// rebuild a running scene for no reason — the dedup half of the primitive.
#[test]
fn rewriting_the_live_handle_is_not_a_switch() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "scene.bsn", SCENE_A);

    let mut app = app_reading(dir.path());
    let server = app.world().resource::<AssetServer>().clone();
    let handle = server.load::<JackdawScene>("scene.bsn");
    let root = app.world_mut().spawn(JackdawSceneRoot(handle.clone())).id();

    pump_until(&mut app, |names| names.iter().any(|n| n == "Anchor"));
    let member = {
        let mut members = app
            .world_mut()
            .query::<(Entity, &jackdaw_runtime::JackdawSceneMember)>();
        members
            .iter(app.world())
            .find(|(_, member)| member.root == root)
            .map(|(entity, _)| entity)
            .expect("the scene spawned one member")
    };

    app.world_mut()
        .entity_mut(root)
        .insert(JackdawSceneRoot(handle));
    for _ in 0..5 {
        app.update();
    }

    assert!(
        app.world().get_entity(member).is_ok(),
        "the live member was not torn down: a same-handle rewrite is not a switch"
    );
    assert_eq!(member_count(&mut app, root), 1);
    assert!(
        spawned_names(&mut app).iter().any(|n| n == "Anchor"),
        "the scene is still the one that spawned"
    );
}

/// Two switches issued in one frame collapse into one reload that lands on
/// the last target: the change merges per frame, so no intermediate scene
/// ever instantiates.
#[test]
fn switching_twice_in_one_frame_lands_on_the_last_target() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "scene.bsn", SCENE_A);
    write(dir.path(), "other.bsn", SCENE_B);
    write(dir.path(), "third.bsn", SCENE_C);

    let mut app = app_reading(dir.path());
    let server = app.world().resource::<AssetServer>().clone();
    let root = app
        .world_mut()
        .spawn(JackdawSceneRoot(server.load::<JackdawScene>("scene.bsn")))
        .id();
    pump_until(&mut app, |names| names.iter().any(|n| n == "Anchor"));

    let to_other = server.load::<JackdawScene>("other.bsn");
    let to_third = server.load::<JackdawScene>("third.bsn");
    wait_loaded(&mut app, &to_other);
    wait_loaded(&mut app, &to_third);
    app.world_mut()
        .entity_mut(root)
        .insert(JackdawSceneRoot(to_other));
    app.world_mut()
        .entity_mut(root)
        .insert(JackdawSceneRoot(to_third));

    let names = pump_until(&mut app, |names| names.iter().any(|n| n == "Third"));
    assert!(
        names.iter().any(|n| n == "Third"),
        "the last target of the frame wins: {names:?}"
    );
    assert!(
        !names.iter().any(|n| n == "Other"),
        "the intermediate target must never spawn: {names:?}"
    );
    assert!(
        !names.iter().any(|n| n == "Anchor"),
        "the scene switched away from must leave zero residue: {names:?}"
    );
}

/// A rebind to a document the loader refuses leaves `SceneRefused` on the
/// root (the previous scene still leaves), and a later rebind to a good
/// scene recovers: the refusal describes one load attempt, not the root's
/// fate.
#[test]
fn rebinding_to_a_broken_scene_refuses_and_a_later_rebind_recovers() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "scene.bsn", SCENE_A);
    write(dir.path(), "broken.bsn", BROKEN);
    write(dir.path(), "other.bsn", SCENE_B);

    let mut app = app_reading(dir.path());
    let server = app.world().resource::<AssetServer>().clone();
    let root = app
        .world_mut()
        .spawn(JackdawSceneRoot(server.load::<JackdawScene>("scene.bsn")))
        .id();
    pump_until(&mut app, |names| names.iter().any(|n| n == "Anchor"));

    app.world_mut()
        .entity_mut(root)
        .insert(JackdawSceneRoot(server.load::<JackdawScene>("broken.bsn")));
    let refused = pump_until(&mut app, |_| false);
    assert!(
        !refused.iter().any(|n| n == "Anchor"),
        "the refused switch still unloads the previous scene: {refused:?}"
    );
    assert!(
        app.world().get::<SceneRefused>(root).is_some(),
        "the root says the load was refused"
    );
    assert_eq!(
        member_count(&mut app, root),
        0,
        "a refused scene spawns no members"
    );

    app.world_mut()
        .entity_mut(root)
        .insert(JackdawSceneRoot(server.load::<JackdawScene>("other.bsn")));
    let names = pump_until(&mut app, |names| names.iter().any(|n| n == "Other"));
    assert!(
        names.iter().any(|n| n == "Other"),
        "the recovery rebind spawns: {names:?}"
    );
    assert!(
        app.world().get::<SceneRefused>(root).is_none(),
        "the refusal describes one attempt; the next load removes it"
    );
}
