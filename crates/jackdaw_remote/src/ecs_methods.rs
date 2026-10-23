//! ECS introspection over BRP: `jackdaw/archetypes` and `jackdaw/schedules`
//! feed the explorer's ECS internals page.

use bevy::ecs::component::ComponentId;
use bevy::ecs::query::ComponentAccessKind;
use bevy::ecs::schedule::graph::Direction;
use bevy::ecs::schedule::{NodeId, ScheduleGraph, Schedules, SystemKey};
use bevy::ecs::system::SystemAccess;
use bevy::prelude::*;
use bevy::remote::BrpResult;
use serde_json::{Value, json};
use std::collections::HashMap;

/// Resolves a dependency-graph node to the single system it represents, for
/// the purpose of reporting run-order edges between systems.
///
/// System nodes resolve directly. Set nodes only resolve when the set is an
/// implicit per-function `SystemTypeSet` (created automatically for calls
/// like `.after(some_system)`), which always contains exactly the one system
/// it was minted for; its sole hierarchy child is that system. Explicit,
/// possibly multi-member sets are left unresolved (`None`) and their edges
/// are skipped, since expanding them to every member system is out of scope
/// for this first pass.
fn resolve_edge_endpoint_to_system(graph: &ScheduleGraph, node: NodeId) -> Option<SystemKey> {
    match node {
        NodeId::System(key) => Some(key),
        NodeId::Set(key) => {
            let set = graph.system_sets.get(key)?;
            set.system_type()?;
            graph
                .hierarchy()
                .edges_directed(NodeId::Set(key), Direction::Outgoing)
                .find_map(|(_, child)| child.as_system())
        }
    }
}

/// One scheduler-detected ambiguity: two systems the scheduler found no
/// ordering between despite conflicting data access. `a`/`b` index into the
/// same schedule's `systems` array as `edges`. An empty `components` list
/// means the conflict is on `World` access in general (e.g. an exclusive
/// system) rather than a specific component.
struct Ambiguity {
    a: usize,
    b: usize,
    components: Vec<String>,
}

/// Resolve a `ComponentId` to its type name via the world's component
/// registry, falling back to the numeric id when the component isn't
/// registered (e.g. ids minted outside any registry).
fn component_name(id: ComponentId, world: &World) -> String {
    match world.components().get_info(id) {
        Some(info) => info.name().to_string(),
        None => id.index().to_string(),
    }
}

/// Extract `graph.conflicting_systems()` into the reply's index space.
///
/// Maps each `SystemKey` through `key_to_index` (built the same way as for
/// `edges`); pairs where either system does not resolve to an index in this
/// schedule are skipped. Resolves each conflicting `ComponentId` to a name
/// via `world`, falling back to the numeric id when the component isn't
/// registered, the same fallback pattern used elsewhere in this file.
fn ambiguities_for(
    graph: &ScheduleGraph,
    key_to_index: &HashMap<SystemKey, usize>,
    world: &World,
) -> Vec<Ambiguity> {
    graph
        .conflicting_systems()
        .iter()
        .filter_map(|(a, b, components)| {
            let a_index = *key_to_index.get(a)?;
            let b_index = *key_to_index.get(b)?;
            let components = components
                .iter()
                .map(|&id| component_name(id, world))
                .collect();
            Some(Ambiguity {
                a: a_index,
                b: b_index,
                components,
            })
        })
        .collect()
}

/// Names of the non-anonymous sets a system directly belongs to, using each
/// set's `Debug` name. Excludes the implicit per-function `SystemTypeSet`
/// that every function system is automatically placed in.
fn system_set_names(graph: &ScheduleGraph, key: SystemKey) -> Vec<String> {
    graph
        .hierarchy()
        .edges_directed(NodeId::System(key), Direction::Incoming)
        .filter_map(|(parent, _)| {
            let NodeId::Set(set_key) = parent else {
                return None;
            };
            let set = graph.system_sets.get(set_key)?;
            if set.system_type().is_some() || set.is_anonymous() {
                return None;
            }
            Some(format!("{set:?}"))
        })
        .collect()
}

/// The kind of access a system has to a component, as reported in the
/// per-system `accesses` table of a `jackdaw/schedules` reply. Serialized as
/// lowercase strings; the editor mirrors them as plain strings so replies
/// from newer servers with unknown kinds still deserialize.
#[derive(serde::Serialize, Clone, Copy, PartialEq, Eq, Debug)]
#[serde(rename_all = "lowercase")]
pub enum AccessKind {
    /// Shared access (`&T`, `Res<T>`).
    Read,
    /// Exclusive access (`&mut T`, `ResMut<T>`).
    Write,
    /// Presence-only access (`Has<T>`, `Allow<T>`).
    Archetypal,
    /// The system's access set is unbounded (e.g. `Query<EntityMut>`): it may
    /// touch any component. Carried as a single marker entry with an empty
    /// `component`, so consumers treat it as "matches any component filter".
    Unbounded,
}

/// One entry in a system's data-access table: a component or resource type
/// name plus the kind of access.
#[derive(serde::Serialize, Clone, PartialEq, Eq, Debug)]
pub struct AccessEntry {
    pub component: String,
    pub kind: AccessKind,
}

/// Export a system's [`SystemAccess`] as reply entries.
///
/// `Shared` accesses are iterated through
/// `combined_access().try_iter_access()`, yielding one entry per component
/// with its read/write/archetypal kind; an unbounded access (writes to all
/// components, e.g. `Query<EntityMut>`) collapses to a single `unbounded`
/// marker entry. `Exclusive` systems (`&mut World`) and `None` accesses
/// produce no entries — exclusive systems are flagged separately via the
/// reply's per-system `exclusive` field. Component names come from
/// `world.components().get_info()`, falling back to the numeric id when
/// unregistered (the same fallback as [`ambiguities_for`]).
pub fn system_access_entries(access: &SystemAccess, world: &World) -> Vec<AccessEntry> {
    let SystemAccess::Shared(set) = access else {
        return Vec::new();
    };
    let combined = set.combined_access();
    match combined.try_iter_access() {
        Ok(kinds) => kinds
            .map(|kind| AccessEntry {
                component: component_name(*kind.index(), world),
                kind: match kind {
                    ComponentAccessKind::Shared(_) => AccessKind::Read,
                    ComponentAccessKind::Exclusive(_) => AccessKind::Write,
                    ComponentAccessKind::Archetypal(_) => AccessKind::Archetypal,
                },
            })
            .collect(),
        Err(_) => vec![AccessEntry {
            component: String::new(),
            kind: AccessKind::Unbounded,
        }],
    }
}

pub fn jackdaw_archetypes_handler(In(_params): In<Option<Value>>, world: &mut World) -> BrpResult {
    let mut archetypes: Vec<(u32, Value)> = Vec::new();
    for archetype in world.archetypes().iter() {
        if archetype.is_empty() {
            continue;
        }
        let components: Vec<String> = archetype
            .components()
            .iter()
            .filter_map(|&id| world.components().get_info(id))
            .map(|info| info.name().to_string())
            .collect();
        let bytes_per_entity: usize = archetype
            .components()
            .iter()
            .filter_map(|&id| world.components().get_info(id))
            .map(|info| info.layout().size())
            .sum();
        archetypes.push((
            archetype.len(),
            json!({
                "components": components,
                "entity_count": archetype.len(),
                "bytes_per_entity": bytes_per_entity,
            }),
        ));
    }
    archetypes.sort_by_key(|entry| std::cmp::Reverse(entry.0));

    Ok(json!({
        "archetypes": archetypes.into_iter().map(|(_, v)| v).collect::<Vec<_>>(),
    }))
}

pub fn jackdaw_schedules_handler(In(_params): In<Option<Value>>, world: &mut World) -> BrpResult {
    let Some(schedules) = world.get_resource::<Schedules>() else {
        return Ok(json!({ "schedules": [], "access_reported": true }));
    };

    let mut out = Vec::new();
    for (label, schedule) in schedules.iter() {
        // systems_with_access() yields the executable in run order (the same
        // order as systems()); that order is preserved as the index space for
        // `edges`. Each system also carries the access captured at
        // initialization, exported per system as the `accesses` table.
        match schedule.systems_with_access() {
            Ok(iter) => {
                let ordered: Vec<(SystemKey, String, &SystemAccess)> = iter
                    .map(|(key, system)| (key, system.system().name().to_string(), system.access()))
                    .collect();
                let key_to_index: HashMap<SystemKey, usize> = ordered
                    .iter()
                    .enumerate()
                    .map(|(index, (key, _, _))| (*key, index))
                    .collect();

                let graph = schedule.graph();

                let systems: Vec<Value> = ordered
                    .iter()
                    .map(|(key, name, access)| {
                        json!({
                            "name": name,
                            "sets": system_set_names(graph, *key),
                            "accesses": system_access_entries(access, world),
                            "exclusive": access.is_exclusive(),
                        })
                    })
                    .collect();

                let edges: Vec<Value> = graph
                    .dependency()
                    .all_edges()
                    .filter_map(|(before, after)| {
                        let before = resolve_edge_endpoint_to_system(graph, before)?;
                        let after = resolve_edge_endpoint_to_system(graph, after)?;
                        let before_index = *key_to_index.get(&before)?;
                        let after_index = *key_to_index.get(&after)?;
                        Some(json!([before_index, after_index]))
                    })
                    .collect();

                let ambiguities: Vec<Value> = ambiguities_for(graph, &key_to_index, world)
                    .into_iter()
                    .map(|a| {
                        json!({
                            "a": a.a,
                            "b": a.b,
                            "components": a.components,
                        })
                    })
                    .collect();

                out.push(json!({
                    "schedule": format!("{label:?}"),
                    "initialized": true,
                    "systems": systems,
                    "edges": edges,
                    "ambiguities": ambiguities,
                }));
            }
            Err(_) => {
                out.push(json!({
                    "schedule": format!("{label:?}"),
                    "initialized": false,
                    "systems": [],
                    "edges": [],
                    "ambiguities": [],
                }));
            }
        }
    }

    // `access_reported` is the capability flag the editor checks: replies
    // from older jackdaw_remote versions lack it (and the per-system
    // `accesses`), letting the editor degrade gracefully.
    Ok(json!({ "schedules": out, "access_reported": true }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use bevy::ecs::query::FilteredAccessSet;
    use bevy::ecs::schedule::{Schedule, ScheduleLabel};

    #[derive(Resource, Default)]
    struct Counter(i32);

    #[derive(Component)]
    struct Marker;

    fn write_a(mut counter: ResMut<Counter>) {
        counter.0 += 1;
    }

    fn write_b(mut counter: ResMut<Counter>) {
        counter.0 += 1;
    }

    fn reads_counter(counter: Res<Counter>) {
        let _ = counter.0;
    }

    fn reads_transforms(query: Query<&Transform>) {
        let _ = query;
    }

    fn checks_marker(query: Query<Has<Marker>>) {
        let _ = query;
    }

    fn touches_world(world: &mut World) {
        let _ = world.entities().len();
    }

    fn mutates_all(query: Query<EntityMut>) {
        let _ = query;
    }

    #[derive(ScheduleLabel, Debug, Clone, Copy, Hash, PartialEq, Eq)]
    struct TestSchedule;

    /// The `SystemAccess` captured for the system whose name contains
    /// `name_fragment`, extracted from an initialized schedule.
    fn access_of(schedule: &Schedule, name_fragment: &str) -> SystemAccess {
        schedule
            .systems_with_access()
            .unwrap()
            .find(|(_, system)| system.system().name().to_string().contains(name_fragment))
            .map(|(_, system)| system.access().clone())
            .unwrap_or_else(|| panic!("no system named containing {name_fragment:?}"))
    }

    /// Build a world with an initialized `TestSchedule` running `systems`.
    fn world_with_schedule<M>(
        systems: impl bevy::ecs::schedule::IntoScheduleConfigs<bevy::ecs::system::ScheduleSystem, M>,
    ) -> (World, Schedule) {
        let mut world = World::new();
        world.insert_resource(Counter::default());
        let mut schedule = Schedule::new(TestSchedule);
        schedule.add_systems(systems);
        schedule.initialize(&mut world).unwrap();
        (world, schedule)
    }

    #[test]
    fn ambiguities_for_reports_unordered_conflicting_systems() {
        let mut world = World::new();
        world.insert_resource(Counter::default());

        let mut schedule = Schedule::new(TestSchedule);
        schedule.add_systems((write_a, write_b));
        schedule.initialize(&mut world).unwrap();

        let ordered: Vec<(SystemKey, String)> = schedule
            .systems()
            .unwrap()
            .map(|(key, system)| (key, system.name().to_string()))
            .collect();
        let key_to_index: HashMap<SystemKey, usize> = ordered
            .iter()
            .enumerate()
            .map(|(index, (key, _))| (*key, index))
            .collect();

        let ambiguities = ambiguities_for(schedule.graph(), &key_to_index, &world);

        assert_eq!(ambiguities.len(), 1);
        let ambiguity = &ambiguities[0];
        let pair: std::collections::HashSet<usize> =
            [ambiguity.a, ambiguity.b].into_iter().collect();
        assert_eq!(pair, std::collections::HashSet::from([0, 1]));
        assert!(
            ambiguity.components.iter().any(|c| c.ends_with("Counter")),
            "expected a component name ending in Counter, got {:?}",
            ambiguity.components
        );
    }

    #[test]
    fn ambiguities_for_skips_pairs_missing_from_the_index() {
        let mut world = World::new();
        world.insert_resource(Counter::default());

        let mut schedule = Schedule::new(TestSchedule);
        schedule.add_systems((write_a, write_b));
        schedule.initialize(&mut world).unwrap();

        let ambiguities = ambiguities_for(schedule.graph(), &HashMap::new(), &world);
        assert!(ambiguities.is_empty());
    }

    #[test]
    fn system_access_entries_reports_resource_reads_and_writes() {
        let (world, schedule) = world_with_schedule((reads_counter, write_a));

        let read = system_access_entries(&access_of(&schedule, "reads_counter"), &world);
        assert_eq!(read.len(), 1, "got {read:?}");
        assert!(read[0].component.ends_with("Counter"), "got {read:?}");
        assert_eq!(read[0].kind, AccessKind::Read);

        let write = system_access_entries(&access_of(&schedule, "write_a"), &world);
        assert_eq!(write.len(), 1, "got {write:?}");
        assert!(write[0].component.ends_with("Counter"), "got {write:?}");
        assert_eq!(write[0].kind, AccessKind::Write);
    }

    #[test]
    fn system_access_entries_reports_component_reads() {
        let (world, schedule) = world_with_schedule(reads_transforms);

        let entries = system_access_entries(&access_of(&schedule, "reads_transforms"), &world);
        assert_eq!(entries.len(), 1, "got {entries:?}");
        assert!(
            entries[0].component.ends_with("Transform"),
            "got {entries:?}"
        );
        assert_eq!(entries[0].kind, AccessKind::Read);
    }

    #[test]
    fn system_access_entries_reports_archetypal_access() {
        let (world, schedule) = world_with_schedule(checks_marker);

        let entries = system_access_entries(&access_of(&schedule, "checks_marker"), &world);
        assert_eq!(entries.len(), 1, "got {entries:?}");
        assert!(entries[0].component.ends_with("Marker"), "got {entries:?}");
        assert_eq!(entries[0].kind, AccessKind::Archetypal);
    }

    #[test]
    fn system_access_entries_reports_exclusive_and_none_as_empty() {
        let (world, schedule) = world_with_schedule(touches_world);

        let access = access_of(&schedule, "touches_world");
        assert!(access.is_exclusive());
        assert!(system_access_entries(&access, &world).is_empty());

        // A `None` access (system that doesn't touch the world) also
        // exports no entries.
        assert!(system_access_entries(&SystemAccess::None, &world).is_empty());
    }

    #[test]
    fn system_access_entries_reports_unbounded_access_as_marker() {
        let (world, schedule) = world_with_schedule(mutates_all);

        let entries = system_access_entries(&access_of(&schedule, "mutates_all"), &world);
        assert_eq!(
            entries,
            vec![AccessEntry {
                component: String::new(),
                kind: AccessKind::Unbounded,
            }],
            "got {entries:?}"
        );
    }

    #[test]
    fn system_access_entries_falls_back_to_numeric_id_for_unregistered_components() {
        let world = World::new();
        let mut set = FilteredAccessSet::new();
        set.add_unfiltered_component_read(ComponentId::new(999_999));

        let entries = system_access_entries(&SystemAccess::Shared(set), &world);
        assert_eq!(
            entries,
            vec![AccessEntry {
                component: "999999".to_string(),
                kind: AccessKind::Read,
            }],
            "got {entries:?}"
        );
    }

    #[test]
    fn schedules_handler_reports_accesses_and_capability_flag() {
        let (mut world, schedule) = world_with_schedule((reads_counter, write_a));
        let mut schedules = Schedules::default();
        schedules.insert(schedule);
        world.insert_resource(schedules);

        let reply = jackdaw_schedules_handler(In(None), &mut world).unwrap();

        assert_eq!(reply["access_reported"], json!(true));
        let systems = reply["schedules"][0]["systems"].as_array().unwrap();
        assert_eq!(systems.len(), 2);
        for system in systems {
            let accesses = system["accesses"].as_array().unwrap();
            assert_eq!(accesses.len(), 1, "got {accesses:?}");
            assert!(
                accesses[0]["component"]
                    .as_str()
                    .unwrap()
                    .ends_with("Counter"),
                "got {accesses:?}"
            );
            assert_eq!(system["exclusive"], json!(false));
        }
        let kinds: Vec<&str> = systems
            .iter()
            .map(|system| system["accesses"][0]["kind"].as_str().unwrap())
            .collect();
        assert!(kinds.contains(&"read"), "got {kinds:?}");
        assert!(kinds.contains(&"write"), "got {kinds:?}");
    }
}
