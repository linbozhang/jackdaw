//! The Resources panel's write path: three [`EditorCommand`]s plus the
//! preview/commit pair the panel's field widgets drive.
//!
//! Resource edits are editor-session state. The scene document holds no
//! patch for a resource entity (a write through `SetBsnField` would be
//! silently dropped), so these commands touch the world's ECS only and
//! take their undo from the shared [`CommandHistory`] directly. Scene-side
//! undo reloads scene entities and never touches resource entities, so
//! the two state domains coexist on one stack without interfering.

use bevy::ecs::component::ComponentId;
use bevy::ecs::reflect::{AppTypeRegistry, ReflectComponent, ReflectResource};
use bevy::ecs::resource::IsResource;
use bevy::prelude::*;
use jackdaw_commands::{CommandHistory, EditorCommand};

/// True when `entity` is one of the world's resource entities: on bevy
/// main every resource lives as a component on an entity the `IsResource`
/// marker identifies. Every write for such an entity belongs on the
/// resource path below, never the scene-document pipeline and never the
/// PIE live stream.
pub(crate) fn is_resource_entity(world: &World, entity: Entity) -> bool {
    world.get::<IsResource>(entity).is_some()
}

/// Clone a reflected value for later re-insertion: a direct clone when the
/// type supports one, else its dynamic stand-in.
fn cloned_value(value: &dyn PartialReflect) -> Option<Box<dyn PartialReflect>> {
    match value.reflect_clone() {
        Ok(cloned) => Some(cloned.into_partial_reflect()),
        Err(_) => value.to_dynamic().ok(),
    }
}

/// Resolve the `ComponentId` for a resource type path, registering the
/// component (and its `IsResource` requirement) with the world first when
/// it has only ever been `register_type`'d. Registering spawns nothing.
fn resource_component_id(world: &mut World, type_path: &str) -> Option<ComponentId> {
    let registry = world.resource::<AppTypeRegistry>().clone();
    let (type_id, reflect_component) = {
        let registry = registry.read();
        let registration = registry.get_with_type_path(type_path)?;
        (
            registration.type_id(),
            registration.data::<ReflectComponent>()?.clone(),
        )
    };
    Some(match world.components().get_id(type_id) {
        Some(component_id) => component_id,
        None => reflect_component.register_component(world),
    })
}

/// The entity the world holds the resource of `type_path` on, with its
/// `ComponentId`, or `None` when the resource is not instantiated.
fn live_resource_entity(world: &mut World, type_path: &str) -> Option<(ComponentId, Entity)> {
    let component_id = resource_component_id(world, type_path)?;
    let entity = world.resource_entities().get(component_id)?;
    let entity = world.get_entity(entity).ok()?.id();
    Some((component_id, entity))
}

/// Write `value` as the resource of `type_path`: onto the entity the world
/// already holds it on, or a fresh one when it holds none.
///
/// The typed insert pulls `IsResource` in as a required component of every
/// `#[derive(Resource)]` type, and the marker's insert hook is what keeps
/// the world's `ResourceEntities` cache in step -- all-safe APIs, no
/// `insert_resource_by_id` pointer dance needed.
fn insert_resource_value(
    world: &mut World,
    type_path: &str,
    value: &dyn PartialReflect,
) -> Option<Entity> {
    let component_id = resource_component_id(world, type_path)?;
    let registry = world.resource::<AppTypeRegistry>().clone();
    let reflect_component = {
        let registry = registry.read();
        registry
            .get_with_type_path(type_path)?
            .data::<ReflectComponent>()?
            .clone()
    };
    let entity = match world.resource_entities().get(component_id) {
        Some(entity) if world.get_entity(entity).is_ok() => entity,
        _ => world.spawn_empty().id(),
    };
    {
        let registry = registry.read();
        reflect_component.insert(&mut world.entity_mut(entity), value, &registry);
    }
    Some(entity)
}

/// Read one field of a live resource as canonical reflect JSON, reading a
/// `[key]` step into a map entry the way the inspector spells one.
fn live_resource_field_json(
    world: &mut World,
    entity: Entity,
    type_path: &str,
    field_path: &str,
) -> Option<serde_json::Value> {
    let registry = world.resource::<AppTypeRegistry>().clone();
    let registry = registry.read();
    let registration = registry.get_with_type_path(type_path)?;
    let reflected = registration
        .data::<ReflectComponent>()?
        .reflect(world.get_entity(entity).ok()?)?;
    let field = crate::commands::read_field_path(reflected.as_partial_reflect(), field_path)?;
    super::reflect_fields::reflect_to_json(field, &registry)
}

/// Write JSON into one field of a live resource (map-entry aware), or
/// replace the whole resource when the path is empty.
fn write_resource_field(
    world: &mut World,
    entity: Entity,
    type_path: &str,
    field_path: &str,
    value: &serde_json::Value,
) {
    if crate::commands::apply_json_map_entry_to_ecs(world, entity, type_path, field_path, value) {
        return;
    }
    crate::commands::apply_json_field_to_ecs(world, entity, type_path, field_path, value);
}

/// Flag the panel to rebuild the open card: a committed write can change a
/// list's length or an enum's variant shape, which value sync alone cannot
/// reflow.
fn mark_resource_card_dirty(world: &mut World) {
    world.insert_resource(super::resource_panel::ResourceCardDirty);
}

/// Set one field of one resource. Holds JSON rather than a document value:
/// there is no document to round-trip through, and the live-apply helpers
/// already speak JSON.
pub struct ResourceSetField {
    pub type_path: String,
    pub field_path: String,
    /// Pre-edit value for undo, captured at the first execute when the
    /// caller (a commit that never previewed) did not supply one.
    pub old_value: Option<serde_json::Value>,
    pub new_value: serde_json::Value,
}

impl EditorCommand for ResourceSetField {
    fn execute(&mut self, world: &mut World) {
        let Some((_, entity)) = live_resource_entity(world, &self.type_path) else {
            return;
        };
        if self.old_value.is_none() && !self.field_path.is_empty() {
            self.old_value =
                live_resource_field_json(world, entity, &self.type_path, &self.field_path);
        }
        write_resource_field(
            world,
            entity,
            &self.type_path,
            &self.field_path,
            &self.new_value,
        );
        mark_resource_card_dirty(world);
    }

    fn undo(&mut self, world: &mut World) {
        let Some((_, entity)) = live_resource_entity(world, &self.type_path) else {
            return;
        };
        match &self.old_value {
            Some(old) => {
                write_resource_field(world, entity, &self.type_path, &self.field_path, old);
            }
            // The field had no readable value before the edit; the closest
            // restoration is the type's own default for it.
            None => crate::commands::reset_ecs_field_to_default(
                world,
                entity,
                &self.type_path,
                &self.field_path,
            ),
        }
        mark_resource_card_dirty(world);
    }

    fn description(&self) -> &str {
        "Set resource field"
    }
}

/// Insert a default-constructed resource, or replace the value of one that
/// already exists (undo then restores what was there rather than removing).
pub struct ResourceInsert {
    pub type_path: String,
    /// The value a replace displaced, captured at execute.
    replaced: Option<Box<dyn PartialReflect>>,
}

impl ResourceInsert {
    /// A command that inserts a default-constructed resource of `type_path`.
    pub(crate) fn new(type_path: impl Into<String>) -> Self {
        Self {
            type_path: type_path.into(),
            replaced: None,
        }
    }

    /// Validate that `type_path` names a reflected, default-constructible
    /// resource the editor could insert. `None` cancels the operation
    /// before any command is built, so a dead type never lands on the
    /// undo stack.
    pub(crate) fn buildable(world: &World, type_path: &str) -> Option<()> {
        let registry = world.resource::<AppTypeRegistry>().clone();
        let registry = registry.read();
        let registration = registry.get_with_type_path(type_path)?;
        registration.data::<ReflectResource>()?;
        crate::reflect_default::build_reflective_default(registration.type_id(), &registry)?;
        Some(())
    }

    fn default_value(world: &World, type_path: &str) -> Option<Box<dyn Reflect>> {
        let registry = world.resource::<AppTypeRegistry>().clone();
        let registry = registry.read();
        let registration = registry.get_with_type_path(type_path)?;
        crate::reflect_default::build_reflective_default(registration.type_id(), &registry)
    }

    /// The live value of the resource, cloned, when it is instantiated.
    fn current_value(world: &World, type_path: &str) -> Option<Box<dyn PartialReflect>> {
        let registry = world.resource::<AppTypeRegistry>().clone();
        let registry = registry.read();
        let registration = registry.get_with_type_path(type_path)?;
        let component_id = world.components().get_id(registration.type_id())?;
        let entity = world.resource_entities().get(component_id)?;
        let reflected = registration
            .data::<ReflectComponent>()?
            .reflect(world.get_entity(entity).ok()?)?;
        cloned_value(reflected.as_partial_reflect())
    }
}

impl EditorCommand for ResourceInsert {
    fn execute(&mut self, world: &mut World) {
        let Some(default) = Self::default_value(world, &self.type_path) else {
            return;
        };
        self.replaced = Self::current_value(world, &self.type_path);
        insert_resource_value(world, &self.type_path, default.as_partial_reflect());
        mark_resource_card_dirty(world);
    }

    fn undo(&mut self, world: &mut World) {
        match &self.replaced {
            Some(prev) => {
                insert_resource_value(world, &self.type_path, prev.as_partial_reflect());
            }
            None => remove_resource_by_type_path(world, &self.type_path),
        }
        mark_resource_card_dirty(world);
    }

    fn description(&self) -> &str {
        "Insert resource"
    }
}

/// Remove an instantiated resource; undo re-inserts the captured value.
pub struct ResourceRemove {
    pub type_path: String,
    /// The value at removal time, so undo restores it exactly.
    pub prev: Option<Box<dyn PartialReflect>>,
}

impl ResourceRemove {
    /// Capture the live value, or `None` when the resource is not
    /// instantiated (nothing to remove, nothing to push).
    pub(crate) fn from_world(world: &World, type_path: &str) -> Option<Self> {
        Some(Self {
            type_path: type_path.to_string(),
            prev: ResourceInsert::current_value(world, type_path),
        })
    }
}

impl EditorCommand for ResourceRemove {
    fn execute(&mut self, world: &mut World) {
        if self.prev.is_none() {
            self.prev = ResourceInsert::current_value(world, &self.type_path);
        }
        remove_resource_by_type_path(world, &self.type_path);
        mark_resource_card_dirty(world);
    }

    fn undo(&mut self, world: &mut World) {
        if let Some(prev) = &self.prev {
            insert_resource_value(world, &self.type_path, prev.as_partial_reflect());
        }
        mark_resource_card_dirty(world);
    }

    fn description(&self) -> &str {
        "Remove resource"
    }
}

/// Remove the resource of `type_path` through the safe by-id API, then
/// make sure the world's cache names no phantom: whether the by-id removal
/// also drops the cache entry is a bevy implementation detail, so when any
/// entry survives, the marker comes off through commands (its discard
/// hook clears the entry and any value left with it).
fn remove_resource_by_type_path(world: &mut World, type_path: &str) {
    let Some(component_id) = resource_component_id(world, type_path) else {
        return;
    };
    world.remove_resource_by_id(component_id);
    if let Some(entity) = world.resource_entities().get(component_id)
        && world.get_entity(entity).is_ok()
    {
        world.commands().entity(entity).remove::<IsResource>();
        world.flush();
    }
}

/// Live field values at preview start, for the same reason
/// [`crate::commands::FieldEditSessions`] exists: a drag previews onto the
/// ECS every tick, so the commit's undo baseline must come from before the
/// gesture, not from the already-mutated present.
#[derive(Resource, Default)]
pub(crate) struct ResourceFieldEditSessions {
    live_at_begin: std::collections::HashMap<(String, String), serde_json::Value>,
}

impl ResourceFieldEditSessions {
    fn key(type_path: &str, field_path: &str) -> (String, String) {
        (type_path.to_string(), field_path.to_string())
    }
}

/// One drag-tick preview of a resource field: writes the live ECS only, no
/// undo, no document. Captures the pre-gesture value on the first tick.
pub(crate) fn resource_field_preview(
    world: &mut World,
    type_path: &str,
    field_path: &str,
    value: &serde_json::Value,
) {
    let Some((_, entity)) = live_resource_entity(world, type_path) else {
        return;
    };
    let key = ResourceFieldEditSessions::key(type_path, field_path);
    if !world
        .resource::<ResourceFieldEditSessions>()
        .live_at_begin
        .contains_key(&key)
    {
        let old = live_resource_field_json(world, entity, type_path, field_path);
        if let Some(old) = old {
            world
                .resource_mut::<ResourceFieldEditSessions>()
                .live_at_begin
                .insert(key, old);
        }
    }
    write_resource_field(world, entity, type_path, field_path, value);
}

/// Commit a resource field edit as one undo entry: old value from the
/// gesture session (or read live), then a [`ResourceSetField`] executed
/// and pushed. An edit that leaves the value as it was pushes nothing.
pub(crate) fn resource_field_commit(
    world: &mut World,
    type_path: &str,
    field_path: &str,
    value: &serde_json::Value,
) {
    let Some((_, entity)) = live_resource_entity(world, type_path) else {
        return;
    };
    let key = ResourceFieldEditSessions::key(type_path, field_path);
    let old = world
        .resource_mut::<ResourceFieldEditSessions>()
        .live_at_begin
        .remove(&key)
        .or_else(|| live_resource_field_json(world, entity, type_path, field_path));
    // A commit that leaves the field as it was must not bury the edit
    // before it under an entry that undoes to the same value.
    if old.as_ref() == Some(value) {
        return;
    }
    let mut command: Box<dyn EditorCommand> = Box::new(ResourceSetField {
        type_path: type_path.to_string(),
        field_path: field_path.to_string(),
        old_value: old,
        new_value: value.clone(),
    });
    command.execute(world);
    world
        .resource_mut::<CommandHistory>()
        .push_executed(command);
}
