//! The physics trigger chain over the real engine: the event
//! prerequisite (red without, green with), the layer mask, the
//! bridge end to end, and a falling body settling on the ground
//! without tunneling through it.

use avian3d::prelude::*;
use bevy::prelude::*;
use bevy::time::TimeUpdateStrategy;
use jackdaw_avian_integration::{AvianCollider, TriggerPlugin};
use jackdaw_runtime::TriggerEvents;
use std::time::Duration;

/// Every `CollisionStart` the engine sent, collected the way the
/// bridge collects them.
#[derive(Resource, Default)]
struct Starts(usize);

fn probe_starts(mut reader: MessageReader<CollisionStart>, mut starts: ResMut<Starts>) {
    for _ in reader.read() {
        starts.0 += 1;
    }
}

/// The editor app with physics unpaused (the editor pauses the
/// simulation until its physics tool runs) and manual time, so the
/// engine steps deterministically. `with_bridge` also adds the
/// game-side trigger bridge. Built from `headless_app` (not
/// `editor_test_app`) because plugins cannot join an app that has
/// already finished.
fn physics_app(with_bridge: bool) -> App {
    let mut app = crate::util::headless_app();
    if with_bridge {
        app.add_plugins(TriggerPlugin);
    }
    app.init_resource::<Starts>()
        .add_systems(PreUpdate, probe_starts);
    app.finish();
    // First tick runs Startup and extension auto-enable, the same
    // start `editor_test_app` gives.
    app.update();
    app.insert_resource(TimeUpdateStrategy::ManualDuration(Duration::from_secs_f64(
        1.0 / 60.0,
    )));
    app.world_mut().resource_mut::<Time<Physics>>().unpause();
    app
}

fn frames(app: &mut App, count: usize) {
    for _ in 0..count {
        app.update();
    }
}

fn cuboid(x: f32, y: f32, z: f32) -> AvianCollider {
    AvianCollider(ColliderConstructor::Cuboid {
        x_length: x,
        y_length: y,
        z_length: z,
    })
}

/// A sensor and a plain collider overlapping at the origin.
fn overlapping_pair(app: &mut App) -> (Entity, Entity) {
    let sensor = app
        .world_mut()
        .spawn((cuboid(1.0, 1.0, 1.0), Sensor, Transform::IDENTITY))
        .id();
    let player = app
        .world_mut()
        .spawn((cuboid(1.0, 1.0, 1.0), Transform::IDENTITY))
        .id();
    (sensor, player)
}

/// The engine's own gate, red and green in one scene: a sensor
/// without `CollisionEventsEnabled` never sends its contacts,
/// while the same-shaped pair carrying the component does. (The
/// component is read into the engine's broad phase when a collider
/// enters the tree, so the green pair carries it from the start.)
#[test]
fn the_engine_sends_sensor_contacts_only_with_the_prerequisite() {
    let mut app = physics_app(false);
    let (silent_sensor, _) = overlapping_pair(&mut app);
    // The same shape three units over, but armed with the component.
    let _armed = app
        .world_mut()
        .spawn((
            cuboid(1.0, 1.0, 1.0),
            Sensor,
            CollisionEventsEnabled,
            Transform::from_xyz(3.0, 0.0, 0.0),
        ))
        .id();
    let _ = app
        .world_mut()
        .spawn((cuboid(1.0, 1.0, 1.0), Transform::from_xyz(3.0, 0.0, 0.0)))
        .id();
    let _ = silent_sensor;

    frames(&mut app, 5);
    assert_eq!(
        app.world().resource::<Starts>().0,
        1,
        "exactly the armed pair sent a start — no prerequisite, no event"
    );
}

/// The full game-side chain over the real engine: the bridge adds
/// the prerequisite itself, the enter lands in `TriggerEvents`, and
/// despawning the other side lands the exit.
#[test]
fn the_bridge_runs_the_full_chain_over_the_engine() {
    let mut app = physics_app(true);
    let (sensor, player) = overlapping_pair(&mut app);

    // A frame for the plugin to add the prerequisite and the bridge
    // to build the colliders, then the steps for the engine. The
    // list is per-frame, so each frame is checked while it is fresh.
    let mut saw_enter = false;
    for _ in 0..6 {
        app.update();
        if app
            .world()
            .resource::<TriggerEvents>()
            .enters()
            .any(|contact| contact.trigger == sensor && contact.other == player)
        {
            saw_enter = true;
        }
    }

    assert!(
        app.world().get::<CollisionEventsEnabled>(sensor).is_some(),
        "the bridge added the prerequisite the engine needs"
    );
    assert!(saw_enter, "the engine's start surfaced as a bridge enter");

    app.world_mut().despawn(player);
    let mut saw_exit = false;
    for _ in 0..6 {
        app.update();
        if app
            .world()
            .resource::<TriggerEvents>()
            .exits()
            .any(|contact| contact.trigger == sensor && contact.other == player)
        {
            saw_exit = true;
        }
    }
    assert!(
        saw_exit,
        "despawning the player ends the contact as an exit"
    );
}

/// Collision layers gate the contact inside the engine: two
/// overlapping colliders on layers that do not interact never touch
/// (no engine event, no trigger — red), while the same shapes on
/// interacting layers do (green). The layers each pair carries from
/// the start decide this: avian's incremental broad phase pairs
/// proxies as they enter the tree, and a still collider whose
/// layers are edited later is not re-paired until it moves — an
/// engine boundary the live editor legs (move after re-layering)
/// cover, not this headless pair.
#[test]
fn non_interacting_layers_keep_contacts_away() {
    let mut app = physics_app(true);
    let sensor = app
        .world_mut()
        .spawn((
            cuboid(1.0, 1.0, 1.0),
            Sensor,
            CollisionLayers::new(0b0010, 0b0100),
            Transform::IDENTITY,
        ))
        .id();
    let player = app
        .world_mut()
        .spawn((
            cuboid(1.0, 1.0, 1.0),
            CollisionLayers::new(0b0001, 0b0001),
            Transform::IDENTITY,
        ))
        .id();
    // The same shapes over on the right, on layers that interact.
    let open_sensor = app
        .world_mut()
        .spawn((
            cuboid(1.0, 1.0, 1.0),
            Sensor,
            CollisionLayers::new(0b0001, 0b0001),
            Transform::from_xyz(3.0, 0.0, 0.0),
        ))
        .id();
    let _ = app
        .world_mut()
        .spawn((
            cuboid(1.0, 1.0, 1.0),
            CollisionLayers::new(0b0001, 0b0001),
            Transform::from_xyz(3.0, 0.0, 0.0),
        ))
        .id();
    let _ = (sensor, player);

    let mut saw_open_enter = false;
    for _ in 0..6 {
        app.update();
        if app
            .world()
            .resource::<TriggerEvents>()
            .enters()
            .any(|contact| contact.trigger == open_sensor)
        {
            saw_open_enter = true;
        }
    }

    assert_eq!(
        app.world().resource::<Starts>().0,
        1,
        "exactly the interacting pair met; masked layers never did"
    );
    assert!(
        saw_open_enter,
        "the interacting pair surfaced through the bridge"
    );
}

/// The ground leg of "a dynamic body does not fall through": a
/// cube dropped from height settles on a static ground, stops
/// (two frames agree), and rests on the surface rather than below
/// it. Headless numbers; the live legs run on the real editor.
#[test]
fn a_falling_cube_settles_on_the_ground_without_tunneling() {
    let mut app = physics_app(false);
    app.world_mut()
        .spawn((cuboid(10.0, 1.0, 10.0), Transform::from_xyz(0.0, -0.5, 0.0)));
    let cube = app
        .world_mut()
        .spawn((
            cuboid(0.5, 0.5, 0.5),
            RigidBody::Dynamic,
            Transform::from_xyz(0.0, 5.0, 0.0),
        ))
        .id();

    // Two seconds of simulation.
    frames(&mut app, 120);

    let settle = |app: &App| {
        app.world()
            .get::<Transform>(cube)
            .expect("the cube")
            .translation
            .y
    };
    let first = settle(&app);
    frames(&mut app, 2);
    let second = settle(&app);
    assert!(
        (first - second).abs() < 0.001,
        "the cube stopped: {first} then {second}"
    );
    assert!(
        (0.24..=0.26).contains(&second),
        "it rests on the surface (top at 0.0, half side 0.25), not in it: {second}"
    );
}
