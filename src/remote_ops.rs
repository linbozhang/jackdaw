//! Operators a caller with no pointer needs: the parametric form of gestures
//! that otherwise only a mouse can perform. Each pushes the same command the
//! gesture pushes, so it undoes the same way.

use bevy::prelude::*;
use jackdaw_api::prelude::*;
use jackdaw_commands::{CommandGroup, EditorCommand};
use jackdaw_feathers::dialog::{DialogChoices, EditorDialog, answer_dialog, resolve_dialog_choice};

use crate::commands::{CommandHistory, ReparentEntity, SetBsnField, SetTransform, SpawnEntity};
use crate::entity_ops::EntityTemplate;

pub(crate) fn add_to_extension(ctx: &mut ExtensionContext) {
    ctx.register_operator::<EntityAddGroupOp>()
        .register_operator::<EntitySetTransformOp>()
        .register_operator::<ComponentSetOp>()
        .register_operator::<DialogAnswerOp>();
}

/// Press a button on the dialog that is up. `jackdaw/status` reports the
/// pending dialog and its choices.
#[operator(
    id = "dialog.answer",
    label = "Answer Dialog",
    description = "Press a button on the dialog that is up, by label or index.",
    allows_undo = false,
    is_available = a_dialog_is_up,
    params(choice(
        String,
        doc = "Button label, or its index counting from the primary action. \
               Matched exactly, then as an index, then as an unambiguous \
               case-insensitive prefix. Defaults to the primary action."
    ))
)]
pub(crate) fn dialog_answer(
    params: In<OperatorParameters>,
    dialogs: Query<(Entity, &DialogChoices), With<EditorDialog>>,
    mut commands: Commands,
) -> OperatorResult {
    // Entity ids rise with each spawn, so the greatest is the dialog on top.
    let Some((dialog, choices)) = dialogs.iter().max_by_key(|(entity, _)| *entity) else {
        commands.queue(|world: &mut World| warn_caller(world, "dialog.answer: no dialog is up"));
        return OperatorResult::Cancelled;
    };
    let wanted = params.as_str("choice").unwrap_or("0");
    let choice = match resolve_dialog_choice(choices, wanted) {
        Ok(choice) => choice,
        Err(err) => {
            let message = format!(
                "dialog.answer: {wanted:?} was not pressed: {err}; it offers {:?}",
                choices.labels()
            );
            commands.queue(move |world: &mut World| warn_caller(world, message));
            return OperatorResult::Cancelled;
        }
    };
    answer_dialog(&mut commands, dialog, choice);
    OperatorResult::Finished
}

fn a_dialog_is_up(dialogs: Query<(), With<EditorDialog>>) -> bool {
    !dialogs.is_empty()
}

/// Add an empty node, named, optionally under another node, as one undo entry.
#[operator(
    id = "entity.add.group",
    label = "Add Group",
    description = "Add an empty node, named, optionally under another node.",
    allows_undo = false,
    params(
        name(String, doc = "Name for the new node. Defaults to \"Group\"."),
        parent(
            Entity,
            doc = "Node that adopts it. Left out, top level, or in an open 2D world scene beside a selection inside the scene, else under the scene root."
        ),
    )
)]
pub(crate) fn entity_add_group(
    params: In<OperatorParameters>,
    mut commands: Commands,
) -> OperatorResult {
    let name = params
        .as_str("name")
        .filter(|name| !name.is_empty())
        .unwrap_or("Group")
        .to_string();
    let parent = params.as_entity("parent");
    commands.queue(move |world: &mut World| {
        // Spawn through the same command `entity.add.empty` pushes, so undo
        // despawns the node rather than only taking back its rename.
        let in_2d = crate::sprite_ops::scene_2d_parent(world, None);
        let mut spawn = SpawnEntity::new(
            move |world: &mut World| {
                crate::entity_ops::spawn_template_under(world, EntityTemplate::Empty, in_2d)
            },
            "Add Group".to_string(),
        );
        spawn.execute(world);
        let Some(entity) = spawn
            .spawned
            .filter(|entity| *entity != Entity::PLACEHOLDER)
        else {
            warn_caller(world, "entity.add.group: could not spawn the node");
            return;
        };

        let old_name = world
            .get::<Name>(entity)
            .map(|name| jackdaw_bsn::BsnValue::String(name.as_str().to_string()));
        let mut group: Vec<Box<dyn EditorCommand>> = vec![
            Box::new(spawn),
            Box::new(SetBsnField {
                entity,
                type_path: crate::commands::NAME_TYPE_PATH.to_string(),
                field_path: String::new(),
                old_value: old_name,
                new_value: jackdaw_bsn::BsnValue::String(name.clone()),
                was_derived: false,
            }),
        ];
        if let Some(parent) = parent
            && world.get_entity(parent).is_ok()
        {
            group.push(Box::new(ReparentEntity {
                entity,
                old_parent: world.get::<ChildOf>(entity).map(ChildOf::parent),
                new_parent: Some(parent),
                old_index: None,
            }));
        }

        // The spawn already ran; the rest runs here and the group goes on the
        // history as one already-executed entry.
        for command in group.iter_mut().skip(1) {
            command.execute(world);
        }
        world
            .resource_mut::<CommandHistory>()
            .push_executed(Box::new(CommandGroup {
                label: format!("Add Group {name}"),
                commands: group,
            }));
    });
    OperatorResult::Finished
}

/// Place an entity: position, rotation in degrees, scale. Every field is
/// optional and an omitted one is left alone.
#[operator(
    id = "entity.set_transform",
    label = "Set Transform",
    description = "Set an entity's position, rotation and scale.",
    allows_undo = false,
    params(
        entity(Entity, doc = "Entity to place. Defaults to the selection."),
        x(f64, doc = "Position X. Unchanged when omitted."),
        y(f64, doc = "Position Y. Unchanged when omitted."),
        z(f64, doc = "Position Z. Unchanged when omitted."),
        yaw(f64, doc = "Rotation about Y in degrees. Unchanged when omitted."),
        pitch(f64, doc = "Rotation about X in degrees. Unchanged when omitted."),
        roll(f64, doc = "Rotation about Z in degrees. Unchanged when omitted."),
        sx(f64, doc = "Scale X. Unchanged when omitted."),
        sy(f64, doc = "Scale Y. Unchanged when omitted."),
        sz(f64, doc = "Scale Z. Unchanged when omitted."),
        world(
            bool,
            doc = "Read the values as world space rather than as the entity's own \
                   local transform. Defaults to false."
        ),
    )
)]
pub(crate) fn entity_set_transform(
    params: In<OperatorParameters>,
    mut commands: Commands,
) -> Option<OperatorResult> {
    let entity = params.as_entity("entity")?;
    let params = params.0;
    commands.queue(move |world: &mut World| {
        let Some(old) = world.get::<Transform>(entity).copied() else {
            warn_caller(
                world,
                format!("entity.set_transform: {entity} has no Transform"),
            );
            return;
        };
        let in_world = params.as_bool("world").unwrap_or(false);

        // In world space the values are read from and written back through the
        // parent's frame.
        let parent = world
            .get::<ChildOf>(entity)
            .map(ChildOf::parent)
            .and_then(|parent| world.get::<GlobalTransform>(parent).copied())
            .unwrap_or_default();
        let basis = if in_world {
            world
                .get::<GlobalTransform>(entity)
                .copied()
                .unwrap_or_default()
                .compute_transform()
        } else {
            old
        };

        let mut wanted = basis;
        let axis = |key: &str, current: f32| params.as_float(key).map_or(current, |v| v as f32);
        wanted.translation = Vec3::new(
            axis("x", wanted.translation.x),
            axis("y", wanted.translation.y),
            axis("z", wanted.translation.z),
        );
        wanted.scale = Vec3::new(
            axis("sx", wanted.scale.x),
            axis("sy", wanted.scale.y),
            axis("sz", wanted.scale.z),
        );
        // Only recomposed when a rotation was asked for: several euler triples
        // name the same quaternion, so a needless round-trip rewrites it.
        let angles = ["yaw", "pitch", "roll"].map(|key| params.as_float(key));
        if angles.iter().any(Option::is_some) {
            let (current_yaw, current_pitch, current_roll) =
                wanted.rotation.to_euler(EulerRot::YXZ);
            let [yaw, pitch, roll] = angles;
            wanted.rotation = Quat::from_euler(
                EulerRot::YXZ,
                yaw.map_or(current_yaw, |v| (v as f32).to_radians()),
                pitch.map_or(current_pitch, |v| (v as f32).to_radians()),
                roll.map_or(current_roll, |v| (v as f32).to_radians()),
            );
        }

        let new_transform = if in_world {
            Transform::from_matrix(parent.to_matrix().inverse() * wanted.to_matrix())
        } else {
            wanted
        };

        if new_transform == old {
            return;
        }
        apply_computed_transform(world, entity, old, new_transform);
    });
    Some(OperatorResult::Finished)
}

/// Land one computed transform write: live routing first (the same dual
/// condition — Live view and a projected entity — as the Inspector's field
/// rows), else the authored [`SetTransform`] command. In the live case the
/// whole transform streams to the focused game and lands in the ledger
/// instead of silently authoring the document behind the game's back; the
/// next projection delta brings the preview entity back in step.
fn apply_computed_transform(
    world: &mut World,
    entity: Entity,
    old: Transform,
    new_transform: Transform,
) {
    const TRANSFORM_PATH: &str = "bevy_transform::components::transform::Transform";
    {
        let registry = world
            .resource::<bevy::ecs::reflect::AppTypeRegistry>()
            .clone();
        let value_json = {
            let registry = registry.read();
            use bevy::reflect::serde::TypedReflectSerializer;
            let serializer =
                TypedReflectSerializer::new(new_transform.as_partial_reflect(), &registry);
            serde_json::to_value(&serializer).unwrap_or(serde_json::Value::Null)
        };
        if crate::inspector::reflect_fields::try_route_pie_live_field_edit(
            world,
            entity,
            TRANSFORM_PATH,
            "",
            value_json,
        ) {
            return;
        }
    }
    let mut cmd: Box<dyn EditorCommand> = Box::new(SetTransform {
        entity,
        old_transform: old,
        new_transform,
    });
    cmd.execute(world);
    world.resource_mut::<CommandHistory>().push_executed(cmd);
}

/// Set one field on one entity's component, by reflection path. Unlike
/// `field.set`, this writes to the named entity and leaves the selection alone.
#[operator(
    id = "component.set",
    label = "Set Component Field",
    description = "Set one field on one entity's component by reflection path.",
    allows_undo = false,
    params(
        entity(Entity, doc = "Entity whose component is edited."),
        type_path(
            String,
            doc = "Fully-qualified Bevy reflected type path of the component."
        ),
        field(
            String,
            doc = "Dotted reflection path within the component (e.g. \"translation.x\"). \
                   Empty sets the whole component."
        ),
        value(
            String,
            doc = "New value as JSON: 12, true, \"text\", or {\"Px\": 12}. A field \
                   holding an asset takes its path, and a colour takes 'r,g,b', a \
                   hex code or a name."
        ),
    )
)]
pub(crate) fn component_set(
    params: In<OperatorParameters>,
    mut commands: Commands,
) -> Option<OperatorResult> {
    let entity = params.as_entity("entity")?;
    let type_path = params.as_str("type_path").map(str::to_string)?;
    let field_path = params.as_str("field").unwrap_or_default().to_string();
    let value = param_json(&params, "value")?;
    commands.queue(move |world: &mut World| {
        apply_component_set(world, entity, &type_path, &field_path, value);
    });
    Some(OperatorResult::Finished)
}

/// The body of `component.set`: live routing first (the same dual condition
/// — Live view and a projected entity — as the Inspector's field rows), else
/// the authored [`crate::commands::field_edit_commit_on`] path.
fn apply_component_set(
    world: &mut World,
    entity: Entity,
    type_path: &str,
    field_path: &str,
    value: serde_json::Value,
) {
    if crate::inspector::reflect_fields::try_route_pie_live_field_edit(
        world,
        entity,
        type_path,
        field_path,
        value.clone(),
    ) {
        return;
    }
    if !crate::commands::field_edit_commit_on(world, entity, type_path, field_path, &value) {
        warn_caller(
            world,
            format!("component.set: {value} is not a value for {type_path}.{field_path}"),
        );
    }
}

/// A parameter as JSON. A string parses as JSON when it can and stands for
/// itself when it cannot.
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::live_edits::LiveEditLog;
    use crate::pie_mirror::PieViewMode;
    use crate::pie_projection::PieProjection;
    use bevy::ecs::reflect::AppTypeRegistry;
    use jackdaw_bsn::SceneBsnAst;

    const TRANSFORM_PATH: &str = "bevy_transform::components::transform::Transform";

    fn build_world(view: PieViewMode) -> (World, Entity) {
        let mut world = World::new();
        world.init_resource::<AppTypeRegistry>();
        world.init_resource::<PieProjection>();
        world.init_resource::<LiveEditLog>();
        world.init_resource::<CommandHistory>();
        world.init_resource::<crate::commands::FieldEditSessions>();
        world.insert_resource(view);
        {
            let registry = world.resource::<AppTypeRegistry>().clone();
            let mut registry = registry.write();
            registry.register::<Transform>();
        }
        let preview = world
            .spawn((Name::new("player"), Transform::from_xyz(1.0, 2.0, 3.0)))
            .id();
        let mut ast = SceneBsnAst::default();
        let patches = {
            let registry = world.resource::<AppTypeRegistry>().clone();
            let registry = registry.read();
            let transform = Transform::from_xyz(1.0, 2.0, 3.0);
            vec![jackdaw_bsn::component_to_bsn_patch(&transform, &registry)]
        };
        let node = ast.create_entity_node(patches);
        ast.add_to_roots(node);
        ast.link(preview, node);
        world.insert_resource(ast);
        world
            .resource_mut::<PieProjection>()
            .by_bits
            .insert(7, preview);
        (world, preview)
    }

    /// The authored document field as a comparable debug string, so the tests
    /// can pin "the document did not move" without a JSON conversion.
    fn doc_field_debug(world: &World, entity: Entity, field_path: &str) -> Option<String> {
        let ast = world.resource::<SceneBsnAst>();
        let node = ast.ast_for(entity)?;
        Some(format!(
            "{:?}",
            jackdaw_bsn::get_bsn_field(ast, node, TRANSFORM_PATH, field_path)?
        ))
    }

    fn ledger_len(world: &World) -> usize {
        world.resource::<LiveEditLog>().entries.len()
    }

    fn undo_len(world: &World) -> usize {
        world.resource::<CommandHistory>().undo_stack.len()
    }

    #[test]
    fn live_component_set_tracks_the_edit_and_leaves_the_document() {
        let (mut world, preview) = build_world(PieViewMode::Live);
        let before = doc_field_debug(&world, preview, "translation");

        apply_component_set(
            &mut world,
            preview,
            TRANSFORM_PATH,
            "translation.y",
            serde_json::json!(2.5),
        );

        {
            let log = world.resource::<LiveEditLog>();
            assert_eq!(log.entries.len(), 1, "the edit lands in the ledger");
            let (key, entry) = &log.entries[0];
            assert_eq!(key.bits, 7);
            assert_eq!(key.type_path, TRANSFORM_PATH);
            assert_eq!(key.field_path, "translation.y");
            assert_eq!(entry.live_value, serde_json::json!(2.5));
            assert_eq!(
                entry.baseline,
                Some(serde_json::json!(2.0)),
                "the authored y is the baseline"
            );
            assert_eq!(entry.label, "player / Transform.translation.y");
        }
        assert_eq!(
            doc_field_debug(&world, preview, "translation"),
            before,
            "the document is untouched while live"
        );
        assert_eq!(undo_len(&world), 0, "no authored history entry while live");
    }

    #[test]
    fn scene_mode_component_set_authors_the_document_and_skips_the_ledger() {
        let (mut world, preview) = build_world(PieViewMode::Scene);

        apply_component_set(
            &mut world,
            preview,
            TRANSFORM_PATH,
            "translation.y",
            serde_json::json!(2.5),
        );

        assert_eq!(ledger_len(&world), 0, "no ledger entry in Scene view");
        assert_eq!(undo_len(&world), 1, "one authored undo entry, as before");
        assert_eq!(
            doc_field_debug(&world, preview, "translation.y"),
            Some("Float(2.5)".to_string()),
            "the authored path wrote the document"
        );
    }

    #[test]
    fn scene_mode_ephemeral_writes_stay_skipped_with_no_ledger() {
        let (mut world, _preview) = build_world(PieViewMode::Scene);
        // An ephemeral projected entity: in the projection, no AST node —
        // the SetBsnField no-node warn branch, unchanged by the routing.
        let ephemeral = world
            .spawn((Name::new("hazard"), Transform::from_xyz(0.0, 5.0, 0.0)))
            .id();
        world
            .resource_mut::<PieProjection>()
            .by_bits
            .insert(9, ephemeral);

        apply_component_set(
            &mut world,
            ephemeral,
            TRANSFORM_PATH,
            "translation.y",
            serde_json::json!(7.0),
        );

        assert_eq!(ledger_len(&world), 0, "no ledger entry for a skipped write");
        assert!(
            doc_field_debug(&world, ephemeral, "translation").is_none(),
            "no document node exists to author"
        );
        // The authored path warns and writes nothing, but the command it
        // pushed still rides the history — the pre-existing ephemeral warn
        // shape, unchanged by the routing.
        assert_eq!(undo_len(&world), 1, "the pushed no-op command, as before");
    }

    #[test]
    fn live_ephemeral_component_set_tracks_without_a_document() {
        let (mut world, _preview) = build_world(PieViewMode::Live);
        let ephemeral = world
            .spawn((Name::new("hazard"), Transform::from_xyz(0.0, 5.0, 0.0)))
            .id();
        world
            .resource_mut::<PieProjection>()
            .by_bits
            .insert(9, ephemeral);

        apply_component_set(
            &mut world,
            ephemeral,
            TRANSFORM_PATH,
            "translation.y",
            serde_json::json!(7.0),
        );

        let log = world.resource::<LiveEditLog>();
        assert_eq!(log.entries.len(), 1, "the runtime entity's edit is tracked");
        let (key, entry) = &log.entries[0];
        assert_eq!(key.bits, 9);
        assert_eq!(
            entry.node_id, None,
            "the runtime entity has no authored node"
        );
        assert_eq!(entry.live_value, serde_json::json!(7.0));
    }

    #[test]
    fn live_set_transform_routes_the_whole_component_into_the_ledger() {
        let (mut world, preview) = build_world(PieViewMode::Live);
        let before = doc_field_debug(&world, preview, "translation");

        apply_computed_transform(
            &mut world,
            preview,
            Transform::from_xyz(1.0, 2.0, 3.0),
            Transform::from_xyz(9.0, 2.0, 3.0),
        );

        {
            let log = world.resource::<LiveEditLog>();
            assert_eq!(log.entries.len(), 1);
            let (key, entry) = &log.entries[0];
            assert_eq!(key.bits, 7);
            assert_eq!(key.field_path, "", "a whole-component entry");
            assert_eq!(
                entry.live_value["translation"][0],
                serde_json::json!(9.0),
                "the streamed component carries the new x"
            );
        }
        assert_eq!(
            doc_field_debug(&world, preview, "translation"),
            before,
            "the document is untouched while live"
        );
        assert_eq!(undo_len(&world), 0, "no authored history entry while live");
    }

    #[test]
    fn scene_mode_set_transform_keeps_the_authored_command() {
        let (mut world, preview) = build_world(PieViewMode::Scene);

        apply_computed_transform(
            &mut world,
            preview,
            Transform::from_xyz(1.0, 2.0, 3.0),
            Transform::from_xyz(9.0, 2.0, 3.0),
        );

        assert_eq!(ledger_len(&world), 0, "no ledger entry in Scene view");
        assert_eq!(undo_len(&world), 1, "one authored undo entry, as before");
        assert_eq!(
            world.get::<Transform>(preview),
            Some(&Transform::from_xyz(9.0, 2.0, 3.0)),
            "the ECS transform moved, as before"
        );
    }
}
