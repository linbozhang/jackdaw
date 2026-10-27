//! Trigger contacts as one readable resource, the same shape
//! [`GameActions`](crate::GameActions) gives input: the engine's
//! physics events are turned into a per-frame list a game reads
//! instead of polling the physics engine itself.
//!
//! The plugin side of this lives in the physics integration crate
//! (`jackdaw_avian_integration::TriggerPlugin`): it reads the
//! engine's collision start/end messages and rebuilds
//! [`TriggerEvents`] each frame before `Update` systems run. A
//! contact enters the list when a **sensor** collider starts or
//! stops touching another collider — the sensor side is reported
//! as `trigger`, the other side as `other` (when both are
//! sensors, both directions are listed).
//!
//! This module holds the data only, so every game can read
//! [`TriggerEvents`] without a physics dependency of its own.
//!
//! # Making a pickup
//!
//! Spawn a small collider with the engine's `Sensor` marker (the
//! editor shows sensors with a cyan outline), let the plugin add
//! the event prerequisite automatically, and read the list:
//!
//! ```ignore
//! fn collect_pickups(triggers: Res<TriggerEvents>, mut commands: Commands) {
//!     for contact in triggers.enters() {
//!         // `contact.trigger` is the sensor side; despawn it, count it…
//!     }
//! }
//! ```
//!
//! For "is it inside right now" rather than edges, query the
//! engine's `CollidingEntities` component on the sensor instead;
//! this list is the edge view (enter/exit).

use bevy::prelude::*;

/// Which edge of a contact a [`TriggerContact`] reports.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum TriggerPhase {
    /// The sensor started touching `other` this frame.
    Enter,
    /// The sensor stopped touching `other` this frame (it was
    /// despawned, moved away, or the other side was).
    Exit,
}

/// One sensor contact edge this frame: the sensor entity as
/// `trigger`, what it touched as `other`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TriggerContact {
    /// The sensor side of the contact.
    pub trigger: Entity,
    /// The collider the sensor touched.
    pub other: Entity,
    /// Whether the contact started or ended.
    pub phase: TriggerPhase,
}

/// Every sensor contact edge this frame, rebuilt each frame by
/// `jackdaw_avian_integration::TriggerPlugin` before `Update`
/// systems run. An empty list means no sensor changed contact
/// this frame — not that nothing is touching (see the module
/// docs for the "inside right now" query).
///
/// The list is in event order, unfiltered and unsorted; a pair
/// touching across several physics steps reports once per edge,
/// not once per step.
#[derive(Resource, Clone, Debug, Default)]
pub struct TriggerEvents {
    contacts: Vec<TriggerContact>,
}

impl TriggerEvents {
    /// All contact edges this frame, in event order.
    pub fn iter(&self) -> impl Iterator<Item = &TriggerContact> + '_ {
        self.contacts.iter()
    }

    /// The contacts that started this frame.
    pub fn enters(&self) -> impl Iterator<Item = &TriggerContact> + '_ {
        contacts_in_phase(self.contacts.iter(), TriggerPhase::Enter)
    }

    /// The contacts that ended this frame.
    pub fn exits(&self) -> impl Iterator<Item = &TriggerContact> + '_ {
        contacts_in_phase(self.contacts.iter(), TriggerPhase::Exit)
    }

    /// Whether no contact edge happened this frame.
    pub fn is_empty(&self) -> bool {
        self.contacts.is_empty()
    }

    /// Empty the list. The physics integration's plugin rebuilds
    /// it each frame; game code reads.
    pub fn clear(&mut self) {
        self.contacts.clear();
    }

    /// How many contact edges happened this frame.
    pub fn len(&self) -> usize {
        self.contacts.len()
    }

    /// Record a contact edge. The physics integration's plugin
    /// is the intended writer; game code reads.
    pub fn push(&mut self, contact: TriggerContact) {
        self.contacts.push(contact);
    }
}

fn contacts_in_phase<'a>(
    iter: impl Iterator<Item = &'a TriggerContact> + 'a,
    phase: TriggerPhase,
) -> impl Iterator<Item = &'a TriggerContact> + 'a {
    iter.filter(move |contact| contact.phase == phase)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enters_and_exits_filter_by_phase() {
        let mut events = TriggerEvents::default();
        let a = Entity::from_bits(1);
        let b = Entity::from_bits(2);
        events.push(TriggerContact {
            trigger: a,
            other: b,
            phase: TriggerPhase::Enter,
        });
        events.push(TriggerContact {
            trigger: a,
            other: b,
            phase: TriggerPhase::Exit,
        });

        assert_eq!(events.len(), 2);
        let enters: Vec<_> = events.enters().collect();
        let exits: Vec<_> = events.exits().collect();
        assert_eq!(enters.len(), 1, "one enter");
        assert_eq!(exits.len(), 1, "one exit");
        assert_eq!(enters[0].trigger, a);
        assert_eq!(exits[0].phase, TriggerPhase::Exit);
        assert!(!events.is_empty());
    }
}
