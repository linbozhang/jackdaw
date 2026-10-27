//! Sensor contacts into [`TriggerEvents`]: the physics side of the
//! trigger bridge whose readable half lives in `jackdaw_runtime`.
//!
//! The engine only sends collision events for entities carrying
//! `CollisionEventsEnabled`, an authoring detail no game should
//! have to remember: [`TriggerPlugin`] adds it to every entity
//! that becomes a [`Sensor`] and turns the engine's collision
//! start/end messages into [`TriggerEvents`] each frame.
//!
//! The list holds **sensor** contacts only — a contact between two
//! plain colliders never enters it (the engine message fires if
//! the event prerequisite is on either side; this bridge filters
//! to the sensor side, reporting it as `trigger`). Collision
//! layers filter earlier still: contacts the engine's
//! `CollisionLayers` masks out never become events at all.

use avian3d::prelude::*;
use bevy::prelude::*;
use jackdaw_runtime::{TriggerContact, TriggerEvents, TriggerPhase};

/// Turns the engine's collision events into
/// [`TriggerEvents`](jackdaw_runtime::TriggerEvents), and keeps
/// every [`Sensor`] able to send them.
///
/// Add beside the physics plugins (the physics module's template
/// wiring does). Games read the resource; nothing here needs
/// configuring.
pub struct TriggerPlugin;

impl Plugin for TriggerPlugin {
    fn build(&self, app: &mut App) {
        // The engine initializes the collision message buffers when
        // its schedule first runs; a reader in `PreUpdate` runs
        // before that, so both buffers exist from the first frame.
        app.init_resource::<bevy::ecs::message::Messages<CollisionStart>>()
            .init_resource::<bevy::ecs::message::Messages<CollisionEnd>>()
            .init_resource::<TriggerEvents>()
            .add_observer(enable_events_for_sensors)
            .add_systems(PreUpdate, collect_trigger_events);
    }
}

/// Give every new [`Sensor`] the component the engine needs before
/// it will report the sensor's contacts — the author adds `Sensor`,
/// the prerequisite is this plugin's business (the same shape
/// [`StaticCollidersPlugin`](crate::StaticCollidersPlugin) gives
/// colliders without a body a static one).
///
/// This runs as an observer, not a system, for an ordering reason:
/// the engine snapshots `Has<CollisionEventsEnabled>` into its
/// broad phase proxy when the collider enters the collider tree,
/// and never re-reads it afterwards. The sensor marker reaching
/// the entity — at spawn or through a later edit — is the last
/// moment the prerequisite is guaranteed to land before any
/// collider built from the entity's `AvianCollider` enters the
/// tree, so the prerequisite rides along with the marker itself.
fn enable_events_for_sensors(
    trigger: On<Add<Sensor>>,
    mut commands: Commands,
    armed: Query<(), Without<CollisionEventsEnabled>>,
) {
    let entity = trigger.event_target();
    if armed.contains(entity) {
        commands.entity(entity).insert(CollisionEventsEnabled);
    }
}

/// Rebuild [`TriggerEvents`] from this frame's collision messages.
///
/// The resource is cleared and refilled each frame; messages the
/// engine wrote over the last physics step(s) are all read, so a
/// frame that ran several fixed steps reports each contact edge
/// once per step it happened in, in event order.
fn collect_trigger_events(
    mut events: ResMut<TriggerEvents>,
    mut started: MessageReader<CollisionStart>,
    mut ended: MessageReader<CollisionEnd>,
    sensors: Query<Has<Sensor>>,
) {
    events.clear();
    for event in started.read() {
        push_sensor_sides(
            &mut events,
            &sensors,
            event.collider1,
            event.collider2,
            TriggerPhase::Enter,
        );
    }
    for event in ended.read() {
        push_sensor_sides(
            &mut events,
            &sensors,
            event.collider1,
            event.collider2,
            TriggerPhase::Exit,
        );
    }
}

/// Record the sensor sides of one contact pair. Both sides sensor
/// means both directions count as a trigger; no sensor means the
/// contact is not a trigger at all. A side that no longer exists —
/// the engine writes an end when a collider is despawned — reads
/// as not a sensor, so the surviving sensor still gets its exit.
fn push_sensor_sides(
    events: &mut TriggerEvents,
    sensors: &Query<Has<Sensor>>,
    first: Entity,
    second: Entity,
    phase: TriggerPhase,
) {
    let first_is = sensors.get(first).unwrap_or(false);
    let second_is = sensors.get(second).unwrap_or(false);
    if first_is {
        events.push(TriggerContact {
            trigger: first,
            other: second,
            phase,
        });
    }
    if second_is {
        events.push(TriggerContact {
            trigger: second,
            other: first,
            phase,
        });
    }
}
