//! Resource operators: the Resources panel's add / remove / set-field
//! actions, each one undoable through the resource commands' own history
//! entries.

use bevy::prelude::*;
use jackdaw_api::prelude::*;

use super::resource_commands::{ResourceInsert, ResourceRemove, resource_field_commit};
use super::resource_panel::{ResourcePanelSelection, ResourcePanelVisibility, ResourceRowButton};
use crate::commands::{CommandHistory, EditorCommand};

pub(crate) fn add_to_extension(ctx: &mut ExtensionContext) {
    ctx.register_operator::<ResourceInsertOp>()
        .register_operator::<ResourceRemoveOp>()
        .register_operator::<ResourceSetFieldOp>();
}

/// The Resources panel names a resource it is listing, which is what the
/// panel's own buttons act on. A listed row is by construction
/// instantiated and visible.
fn has_visible_resource(
    selection: Res<ResourcePanelSelection>,
    rows: Query<&ResourceRowButton>,
) -> bool {
    selection
        .0
        .as_ref()
        .is_some_and(|type_path| rows.iter().any(|row| &row.type_path == type_path))
}

/// Read a parameter as the JSON a field edit commits. A string is parsed as
/// JSON first, so `{"Px": 120}` arrives as the enum variant it spells, and
/// falls back to being the string it is.
fn param_json(params: &OperatorParameters, key: &str) -> Option<serde_json::Value> {
    use jackdaw_scene_types::PropertyValue;
    match params.get(key)? {
        PropertyValue::Bool(value) => Some(serde_json::Value::Bool(*value)),
        PropertyValue::Int(value) => Some(serde_json::json!(value)),
        PropertyValue::Float(value) => Some(serde_json::json!(value)),
        PropertyValue::String(value) => Some(
            serde_json::from_str(value)
                .unwrap_or_else(|_| serde_json::Value::String(value.to_string())),
        ),
        _ => None,
    }
}

/// Add a resource of this type.
#[operator(
    id = "resource.insert",
    label = "Add Resource",
    description = "Add a resource of this type.",
    params(type_path(
        String,
        doc = "Fully-qualified reflect type path of the resource to add."
    ),)
)]
pub(crate) fn resource_insert(
    params: In<OperatorParameters>,
    mut commands: Commands,
) -> Option<OperatorResult> {
    let type_path = params.as_str("type_path").map(str::to_string)?;
    commands.queue(move |world: &mut World| {
        // The type must be a registered, default-constructible resource the
        // panel's filter admits; otherwise there is nothing to add and no
        // undo entry to hold.
        if super::resource_commands::ResourceInsert::buildable(world, &type_path).is_none() {
            return;
        }
        if !world
            .resource::<ResourcePanelVisibility>()
            .visible(&type_path)
        {
            return;
        }
        let mut command: Box<dyn EditorCommand> = Box::new(ResourceInsert::new(&type_path));
        command.execute(world);
        world
            .resource_mut::<CommandHistory>()
            .push_executed(command);
        // Show the fresh resource's card right away; the refresh pass
        // swaps the card on the next frame.
        world.resource_mut::<ResourcePanelSelection>().0 = Some(type_path);
    });
    Some(OperatorResult::Finished)
}

/// Remove this resource.
#[operator(
    id = "resource.remove",
    label = "Remove Resource",
    description = "Remove this resource.",
    is_available = has_visible_resource,
    params(
        type_path(String, default = "", doc = "Fully-qualified reflect type path of the resource to remove; empty removes the one selected in the Resources panel."),
    ),
)]
pub(crate) fn resource_remove(
    params: In<OperatorParameters>,
    mut commands: Commands,
) -> Option<OperatorResult> {
    let type_path = params.as_str("type_path").unwrap_or("").to_string();
    commands.queue(move |world: &mut World| {
        // With no explicit target, the panel's own selection is the
        // resource the Remove button sits on.
        let type_path = if type_path.is_empty() {
            match world.resource::<ResourcePanelSelection>().0.clone() {
                Some(type_path) => type_path,
                None => return,
            }
        } else {
            type_path
        };
        let Some(mut command) = ResourceRemove::from_world(world, &type_path) else {
            return;
        };
        command.execute(world);
        world
            .resource_mut::<CommandHistory>()
            .push_executed(Box::new(command));
    });
    Some(OperatorResult::Finished)
}

/// Set one field on a resource.
#[operator(
    id = "resource.set_field",
    label = "Set Resource Field",
    description = "Set one field on a resource.",
    is_available = has_visible_resource,
    params(
        type_path(String, doc = "Fully-qualified reflect type path of the resource that owns the field."),
        field(String, doc = "Dotted path to the field within the resource (e.g. \"points\")."),
        value(String, doc = "New value as JSON: 12, true, text, or {\"Px\": 12}."),
    ),
)]
pub(crate) fn resource_set_field(
    params: In<OperatorParameters>,
    mut commands: Commands,
) -> Option<OperatorResult> {
    let type_path = params.as_str("type_path").map(str::to_string)?;
    let field = params.as_str("field").map(str::to_string)?;
    let value = param_json(&params, "value")?;
    commands.queue(move |world: &mut World| {
        resource_field_commit(world, &type_path, &field, &value);
    });
    Some(OperatorResult::Finished)
}
