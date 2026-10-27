//! The trigger bridge: collision messages become `TriggerEvents`
//! entries for the sensor side of each contact — and nothing else.
//!
//! The engine's simulation is driven in the guards test on the
//! editor app (`tests/guards/physics_triggers.rs`); here the
//! messages are written directly, which is what the bridge
//! consumes, so every rule of the bridge is pinned without the
//! physics step's timing.

use avian3d::prelude::*;
use bevy::prelude::*;
use jackdaw_avian_integration::{AvianCollider, AvianColliderBridgePlugin, TriggerPlugin};
use jackdaw_runtime::{TriggerContact, TriggerEvents, TriggerPhase};

/// Every `CollisionStart` the engine sent, collected by a probe
/// system reading the same message stream the bridge does.
#[derive(Resource, Default)]
struct Starts(usize);

fn probe_starts(mut reader: MessageReader<CollisionStart>, mut starts: ResMut<Starts>) {
    for _ in reader.read() {
        starts.0 += 1;
    }
}

fn app(with_trigger: bool) -> App {
    let mut app = App::new();
    app.add_plugins((MinimalPlugins, AvianColliderBridgePlugin));
    if with_trigger {
        app.add_plugins(TriggerPlugin);
    }
    // Only the trigger plugin initializes the collision buffers
    // itself; the probe reads them either way.
    app.init_resource::<bevy::ecs::message::Messages<CollisionStart>>();
    app.init_resource::<bevy::ecs::message::Messages<CollisionEnd>>();
    app.init_resource::<Starts>()
        .add_systems(PreUpdate, probe_starts);
    app
}

fn unit_cuboid() -> AvianCollider {
    AvianCollider(ColliderConstructor::Cuboid {
        x_length: 1.0,
        y_length: 1.0,
        z_length: 1.0,
    })
}

/// A sensor and a plain collider entity, both standing where they
/// were spawned (the positions matter only to the engine, not to
/// these message-driven tests).
fn pair(app: &mut App) -> (Entity, Entity) {
    let sensor = app
        .world_mut()
        .spawn((unit_cuboid(), Sensor, Transform::IDENTITY))
        .id();
    let player = app
        .world_mut()
        .spawn((unit_cuboid(), Transform::IDENTITY))
        .id();
    (sensor, player)
}

/// Write the message a physics step writes when the two colliders
/// start touching, then run one frame so the bridge collects it.
fn start_touching(app: &mut App, first: Entity, second: Entity) {
    app.world_mut().write_message(CollisionStart {
        collider1: first,
        collider2: second,
        body1: Some(first),
        body2: Some(second),
    });
    app.update();
}

fn stop_touching(app: &mut App, first: Entity, second: Entity) {
    app.world_mut().write_message(CollisionEnd {
        collider1: first,
        collider2: second,
        body1: Some(first),
        body2: Some(second),
    });
    app.update();
}

/// The bridge only exists with the plugin: without it there is no
/// `TriggerEvents` resource to read at all (the red half of "the
/// plugin wires the list"), and no prerequisite is added to a
/// sensor either.
#[test]
fn without_the_plugin_there_is_no_list_and_no_prerequisite() {
    let mut app = app(false);
    let (sensor, _) = pair(&mut app);
    app.update();

    assert!(
        !app.world().contains_resource::<TriggerEvents>(),
        "the list comes with the plugin"
    );
    assert!(
        app.world().get::<CollisionEventsEnabled>(sensor).is_none(),
        "and so does the event prerequisite"
    );
}

/// The plugin adds the engine's event prerequisite to every sensor,
/// the frame the sensor appears (an author adds `Sensor`, nothing
/// else — the same shape the static-colliders plugin gives a
/// bodyless collider).
#[test]
fn the_plugin_adds_the_event_prerequisite_to_sensors() {
    let mut app = app(true);
    let (sensor, player) = pair(&mut app);
    app.update();

    assert!(
        app.world().get::<CollisionEventsEnabled>(sensor).is_some(),
        "the sensor gets the prerequisite"
    );
    assert!(
        app.world().get::<CollisionEventsEnabled>(player).is_none(),
        "a plain collider does not"
    );
}

/// A contact the engine reports lands in the list with the sensor
/// as `trigger`; the same contact ending lands as an `Exit`.
#[test]
fn sensor_contacts_land_as_enter_and_exit() {
    let mut app = app(true);
    let (sensor, player) = pair(&mut app);
    app.update();

    start_touching(&mut app, sensor, player);
    let events = app.world().resource::<TriggerEvents>();
    assert_eq!(
        events.iter().collect::<Vec<_>>(),
        vec![&TriggerContact {
            trigger: sensor,
            other: player,
            phase: TriggerPhase::Enter,
        }],
        "the sensor side is the trigger"
    );

    stop_touching(&mut app, sensor, player);
    let events = app.world().resource::<TriggerEvents>();
    assert_eq!(
        events.exits().collect::<Vec<_>>(),
        vec![&TriggerContact {
            trigger: sensor,
            other: player,
            phase: TriggerPhase::Exit,
        }],
        "the end is an exit"
    );
}

/// Contacts between plain colliders never become triggers: a
/// start with no sensor on either side stays out of the list.
#[test]
fn plain_contacts_stay_out_of_the_list() {
    let mut app = app(true);
    let wall = app
        .world_mut()
        .spawn((unit_cuboid(), Transform::IDENTITY))
        .id();
    let player = app
        .world_mut()
        .spawn((unit_cuboid(), Transform::IDENTITY))
        .id();
    app.update();

    start_touching(&mut app, wall, player);
    assert!(
        app.world().resource::<TriggerEvents>().is_empty(),
        "no sensor, no trigger"
    );
    assert_eq!(
        app.world().resource::<Starts>().0,
        1,
        "the message itself was still read by the probe"
    );
}

/// Two sensors touching list both directions: each side is a
/// trigger of its own.
#[test]
fn two_sensors_list_both_directions() {
    let mut app = app(true);
    let first = app
        .world_mut()
        .spawn((unit_cuboid(), Sensor, Transform::IDENTITY))
        .id();
    let second = app
        .world_mut()
        .spawn((unit_cuboid(), Sensor, Transform::IDENTITY))
        .id();
    app.update();

    start_touching(&mut app, first, second);
    let events = app.world().resource::<TriggerEvents>();
    let triggers: Vec<_> = events.enters().map(|contact| contact.trigger).collect();
    assert_eq!(triggers.len(), 2, "both directions are triggers");
    assert!(triggers.contains(&first) && triggers.contains(&second));
}

/// The list is per-frame: contacts from the previous frame are
/// gone when nothing new happens, so a consumer reading every
/// frame sees each edge exactly once.
#[test]
fn the_list_resets_each_frame() {
    let mut app = app(true);
    let (sensor, player) = pair(&mut app);
    app.update();

    start_touching(&mut app, sensor, player);
    assert_eq!(app.world().resource::<TriggerEvents>().len(), 1);

    app.update();
    assert!(
        app.world().resource::<TriggerEvents>().is_empty(),
        "no new contact, no entries"
    );
}
