//! Edit-mode switch operators: Vertex / Edge / Face / Clip / Knife.
//! Each one either enters the named mode or, if already in it, toggles
//! back to Object. All `allows_undo = false` because edit-mode is UI
//! state, not a scene mutation.
//!
//! Also home to `brush.selection.set_faces`, the structured write that
//! lands a caller in Face mode on one brush with a given face selection —
//! the entry point for driving Face-mode edit chains where picking a face
//! in the viewport is not reachable (QA / automation). Same no-undo rule:
//! a selection is UI state, not a scene mutation.
//!
//! Default keybinds: `1` vertex, `2` edge, `3` face, `4` clip, `K` knife.

use bevy::{input_focus::InputFocus, prelude::*};
use jackdaw_api::prelude::*;
use jackdaw_api_internal::keymap::PresetInput;
use jackdaw_api_internal::operator::warn_caller;

use crate::brush::{
    BrushDragState, BrushEditMode, BrushSelection, ClipState, EdgeDragState, EditMode, KnifeMode,
    VertexDragState, shown_edit_brushes,
};
use crate::core_extension::CoreExtensionInputContext;
use crate::draw_brush::DrawBrushState;
use crate::selection::Selection;

/// Resets edit mode to Object, clears any brush sub-element selection,
/// and cancels an in-progress draw brush session. Called by `tool.select`
/// so that switching to the Select tool always lands in Object mode.
pub(crate) fn set_edit_mode_object(world: &mut World) {
    if let Some(mut edit_mode) = world.get_resource_mut::<EditMode>() {
        *edit_mode = EditMode::Object;
    }
    if let Some(mut brush_selection) = world.get_resource_mut::<BrushSelection>() {
        brush_selection.clear();
    }
    if let Some(mut draw_state) = world.get_resource_mut::<DrawBrushState>() {
        draw_state.active = None;
    }
}

pub(crate) fn add_to_extension(ctx: &mut ExtensionContext) {
    ctx.register_operator::<EditModeVertexOp>()
        .register_operator::<EditModeEdgeOp>()
        .register_operator::<EditModeFaceOp>()
        .register_operator::<EditModeClipOp>()
        .register_operator::<EditModeKnifeOp>()
        .register_operator::<BrushExitEditModeOp>()
        .register_operator::<BrushSelectionSetFacesOp>();

    ctx.bind_operator::<CoreExtensionInputContext, EditModeVertexOp>([PresetInput::key("Digit1")]);
    ctx.bind_operator::<CoreExtensionInputContext, EditModeEdgeOp>([PresetInput::key("Digit2")]);
    ctx.bind_operator::<CoreExtensionInputContext, EditModeFaceOp>([PresetInput::key("Digit3")]);
    ctx.bind_operator::<CoreExtensionInputContext, EditModeClipOp>([PresetInput::key("Digit4")]);
    ctx.bind_operator::<CoreExtensionInputContext, EditModeKnifeOp>([PresetInput::key("KeyK")]);
    ctx.bind_operator::<CoreExtensionInputContext, BrushExitEditModeOp>([PresetInput::key(
        "Escape",
    )]);
}

/// True only when the user is in `BrushEdit` and an Escape press
/// should drop them back to Object mode (no modal running, no drag
/// in flight, not in Clip mode with pending points, not in Knife
/// mode with a partial path). Clip-with-points is owned by
/// `brush.clip.clear`'s Escape binding instead; Knife-with-path is
/// owned by `handle_knife_mode`'s Escape handling.
fn can_exit_brush_edit(
    edit_mode: Res<EditMode>,
    active: ActiveModalQuery,
    face_drag: Res<BrushDragState>,
    vertex_drag: Res<VertexDragState>,
    edge_drag: Res<EdgeDragState>,
    clip_state: Res<ClipState>,
    knife: Res<KnifeMode>,
) -> bool {
    if active.is_modal_running() {
        return false;
    }
    if face_drag.active || vertex_drag.active || edge_drag.active {
        return false;
    }
    if face_drag.pending.is_some() || vertex_drag.pending.is_some() || edge_drag.pending.is_some() {
        return false;
    }
    match *edit_mode {
        EditMode::BrushEdit(BrushEditMode::Clip) if !clip_state.points.is_empty() => false,
        EditMode::BrushEdit(BrushEditMode::Knife) if !knife.path.is_empty() => false,
        EditMode::BrushEdit(_) => true,
        _ => false,
    }
}

/// Drop out of brush-edit mode back to Object.
#[operator(
    id = "brush.exit_edit_mode",
    label = "Exit Edit Mode",
    description = "Stop editing the brush and return to selecting whole entities.",
    is_available = can_exit_brush_edit,
    allows_undo = false,
)]
pub(crate) fn brush_exit_edit_mode(
    _: In<OperatorParameters>,
    mut edit_mode: ResMut<EditMode>,
    mut brush_selection: ResMut<BrushSelection>,
) -> OperatorResult {
    *edit_mode = EditMode::Object;
    brush_selection.clear();
    OperatorResult::Finished
}

/// What makes switching edit modes unsafe, keyboard focus aside: a running
/// modal, a brush sub-element drag in flight or pending (it would lose its
/// target), a 2D viewport in front, or a selected tilemap, which takes the
/// mode keys for tile edit mode.
#[derive(bevy::ecs::system::SystemParam)]
#[doc(hidden)]
pub struct EditModeGuards<'w, 's> {
    selection: Res<'w, Selection>,
    tilemaps: Query<'w, 's, (), With<jackdaw_scene_types::Tilemap>>,
    active: ActiveModalQuery<'w, 's>,
    face_drag: Res<'w, BrushDragState>,
    vertex_drag: Res<'w, VertexDragState>,
    edge_drag: Res<'w, EdgeDragState>,
    viewport: crate::viewport_2d::FrontedViewport<'w, 's>,
}

impl EditModeGuards<'_, '_> {
    /// Why the edit mode may not change now, if it may not.
    #[doc(hidden)]
    pub fn blocked(&self) -> Option<&'static str> {
        if self.active.is_modal_running() {
            return Some("a modal operation is running");
        }
        if !self.viewport.is_three_d() {
            return Some("the 2D viewport is in front");
        }
        if self
            .selection
            .primary()
            .is_some_and(|e| self.tilemaps.contains(e))
        {
            return Some("a tilemap is selected");
        }
        let (face, vertex, edge) = (&self.face_drag, &self.vertex_drag, &self.edge_drag);
        if face.active || vertex.active || edge.active {
            return Some("a drag is in progress");
        }
        if face.pending.is_some() || vertex.pending.is_some() || edge.pending.is_some() {
            return Some("a drag is about to start");
        }
        None
    }
}

/// True when switching edit modes is safe: no text field has focus and no
/// [`EditModeGuards`] objection.
fn can_change_edit_mode(input_focus: Res<InputFocus>, guards: EditModeGuards) -> bool {
    input_focus.get().is_none() && guards.blocked().is_none()
}

#[operator(
    id = "edit_mode.vertex",
    label = "Vertex Mode",
    is_available = can_change_edit_mode,
    allows_undo = false,
)]
pub(crate) fn edit_mode_vertex(
    _: In<OperatorParameters>,
    edit_mode: ResMut<EditMode>,
    brush_selection: ResMut<BrushSelection>,
    draw_state: ResMut<DrawBrushState>,
    selection: Res<Selection>,
    brushes: Query<(), With<jackdaw_scene_types::Brush>>,
    children: Query<&Children>,
) -> OperatorResult {
    switch_brush_edit_mode(
        BrushEditMode::Vertex,
        edit_mode,
        brush_selection,
        draw_state,
        selection,
        brushes,
        children,
    )
}

#[operator(
    id = "edit_mode.edge",
    label = "Edge Mode",
    is_available = can_change_edit_mode,
    allows_undo = false,
)]
pub(crate) fn edit_mode_edge(
    _: In<OperatorParameters>,
    edit_mode: ResMut<EditMode>,
    brush_selection: ResMut<BrushSelection>,
    draw_state: ResMut<DrawBrushState>,
    selection: Res<Selection>,
    brushes: Query<(), With<jackdaw_scene_types::Brush>>,
    children: Query<&Children>,
) -> OperatorResult {
    switch_brush_edit_mode(
        BrushEditMode::Edge,
        edit_mode,
        brush_selection,
        draw_state,
        selection,
        brushes,
        children,
    )
}

#[operator(
    id = "edit_mode.face",
    label = "Face Mode",
    is_available = can_change_edit_mode,
    allows_undo = false,
)]
pub(crate) fn edit_mode_face(
    _: In<OperatorParameters>,
    edit_mode: ResMut<EditMode>,
    brush_selection: ResMut<BrushSelection>,
    draw_state: ResMut<DrawBrushState>,
    selection: Res<Selection>,
    brushes: Query<(), With<jackdaw_scene_types::Brush>>,
    children: Query<&Children>,
) -> OperatorResult {
    switch_brush_edit_mode(
        BrushEditMode::Face,
        edit_mode,
        brush_selection,
        draw_state,
        selection,
        brushes,
        children,
    )
}

#[operator(
    id = "edit_mode.clip",
    label = "Clip Mode",
    is_available = can_change_edit_mode,
    allows_undo = false,
)]
pub(crate) fn edit_mode_clip(
    _: In<OperatorParameters>,
    edit_mode: ResMut<EditMode>,
    brush_selection: ResMut<BrushSelection>,
    draw_state: ResMut<DrawBrushState>,
    selection: Res<Selection>,
    brushes: Query<(), With<jackdaw_scene_types::Brush>>,
    children: Query<&Children>,
) -> OperatorResult {
    switch_brush_edit_mode(
        BrushEditMode::Clip,
        edit_mode,
        brush_selection,
        draw_state,
        selection,
        brushes,
        children,
    )
}

#[operator(
    id = "edit_mode.knife",
    label = "Knife Mode",
    description = "Toggle the brush knife edit mode. Click to place path \
                   points, Enter to apply, Esc to discard the in-progress \
                   path.",
    is_available = can_change_edit_mode,
    allows_undo = false,
)]
pub(crate) fn edit_mode_knife(
    _: In<OperatorParameters>,
    edit_mode: ResMut<EditMode>,
    brush_selection: ResMut<BrushSelection>,
    draw_state: ResMut<DrawBrushState>,
    selection: Res<Selection>,
    brushes: Query<(), With<jackdaw_scene_types::Brush>>,
    children: Query<&Children>,
) -> OperatorResult {
    switch_brush_edit_mode(
        BrushEditMode::Knife,
        edit_mode,
        brush_selection,
        draw_state,
        selection,
        brushes,
        children,
    )
}

fn switch_brush_edit_mode(
    target: BrushEditMode,
    mut edit_mode: ResMut<EditMode>,
    mut brush_selection: ResMut<BrushSelection>,
    mut draw_state: ResMut<DrawBrushState>,
    selection: Res<Selection>,
    brushes: Query<(), With<jackdaw_scene_types::Brush>>,
    children: Query<&Children>,
) -> OperatorResult {
    draw_state.active = None;

    match *edit_mode {
        EditMode::BrushEdit(current) if current == target => {
            // Same mode pressed twice: toggle back to Object.
            *edit_mode = EditMode::Object;
            brush_selection.clear();
        }
        EditMode::BrushEdit(_) => {
            // Switching between brush sub-modes: swap and clear all sub-element picks
            // (indices are per-mode and don't translate across).
            *edit_mode = EditMode::BrushEdit(target);
            brush_selection.clear_sub_selections();
        }
        _ => {
            // Entering from Object / Physics: populate from selection,
            // expanding any non-brush selected entities to their brush children.
            let shown = shown_edit_brushes(
                &selection.entities,
                |e| brushes.contains(e),
                |e| {
                    children
                        .get(e)
                        .map(|c| c.iter().collect())
                        .unwrap_or_default()
                },
            );

            // No edit brushes in the selection: no-op.
            if shown.is_empty() {
                return OperatorResult::Cancelled;
            }

            brush_selection.clear();
            for &e in &shown {
                brush_selection.sub_mut(e);
            }
            brush_selection.active_brush = selection
                .primary()
                .filter(|&e| brushes.contains(e))
                .or_else(|| shown.first().copied());

            *edit_mode = EditMode::BrushEdit(target);
        }
    }
    OperatorResult::Finished
}

// =====================================================================
// Structured face-selection write (QA / automation entry point)
// =====================================================================

/// The state a face click produces, written directly: Face edit mode, one
/// brush as the sole edit brush and the active one, and a given face
/// selection. Every refusal answers structurally through
/// [`warn_caller`], which a remote caller reads out of `OperatorWarnings`.
#[operator(
    id = "brush.selection.set_faces",
    label = "Set Brush Face Selection",
    description = "Write one brush's face sub-selection directly and enter Face \
                   edit mode on it. The edit-brush set is replaced by exactly \
                   this brush, it becomes the active brush, and its selected \
                   faces are set to `faces` (authored indices, each validated \
                   against the brush's face count; an empty list selects \
                   nothing). The same EditMode / BrushSelection state a face \
                   click lands, so Face-mode edit chains (nudge, drag, \
                   material apply) drive from here without a viewport pick. \
                   Refusals — no such brush entity, a malformed list, an \
                   out-of-range index — come back as `Cancelled` with the \
                   reason in `OperatorWarnings`, for a remote caller to read. \
                   Selection state is UI state, not a scene edit: like \
                   `edit_mode.face` this never creates a history entry.",
    is_available = can_change_edit_mode,
    allows_undo = false,
    params(
        entity(
            Entity,
            doc = "The brush to select faces on. Over BRP this is an entity \
                   id (the bits `jackdaw/scene_tree` reports) or a \
                   scene-unique name.",
        ),
        faces(
            String,
            doc = "Comma-separated authored face indices, e.g. \"0,2,5\"; a \
                   JSON array arrives stringified and is read the same way. \
                   Empty selects nothing.",
        ),
    ),
)]
pub(crate) fn brush_selection_set_faces(
    params: In<OperatorParameters>,
    mut edit_mode: ResMut<EditMode>,
    mut brush_selection: ResMut<BrushSelection>,
    brushes: Query<&jackdaw_scene_types::Brush>,
    mut commands: Commands,
) -> OperatorResult {
    let Some(entity) = entity_param(&params) else {
        return refuse(
            &mut commands,
            "brush.selection.set_faces: expected `entity` (a brush entity id \
             or name) and `faces` (e.g. \"0,2,5\")",
        );
    };
    let Some(text) = params.as_str("faces") else {
        return refuse(
            &mut commands,
            "brush.selection.set_faces: expected a `faces` list, e.g. \
             \"0,2,5\" (got none)",
        );
    };
    let Ok(brush) = brushes.get(entity) else {
        return refuse(
            &mut commands,
            format!(
                "brush.selection.set_faces: entity {entity:?} does not exist \
                 or carries no Brush component"
            ),
        );
    };
    let face_count = brush.faces.len();
    let faces = match parse_face_list(text) {
        Ok(faces) => faces,
        Err(reason) => {
            return refuse(
                &mut commands,
                format!("brush.selection.set_faces: {reason}"),
            );
        }
    };
    if let Some(&out_of_range) = faces.iter().find(|&&face| face >= face_count) {
        return refuse(
            &mut commands,
            format!(
                "brush.selection.set_faces: face index {out_of_range} is out \
                 of range; the brush has {face_count} faces"
            ),
        );
    }

    *edit_mode = EditMode::BrushEdit(BrushEditMode::Face);
    brush_selection.clear();
    brush_selection.sub_mut(entity).faces = faces;
    brush_selection.active_brush = Some(entity);
    OperatorResult::Finished
}

/// The entity the `entity` parameter names: the resolved
/// `PropertyValue::Entity` a BRP call arrives with, or raw bits a direct
/// in-process caller passed as an `Int`.
fn entity_param(params: &OperatorParameters) -> Option<Entity> {
    params.as_entity("entity").or_else(|| {
        params
            .as_int("entity")
            .and_then(|bits| Entity::try_from_bits(bits as u64))
    })
}

/// Parse a `faces` parameter: a comma-separated list of authored face
/// indices. One pair of surrounding brackets is tolerated, because a JSON
/// array parameter arrives here stringified as `[0, 2, 5]`. The written
/// list is exactly the given order, duplicates included.
fn parse_face_list(text: &str) -> Result<Vec<usize>, String> {
    let text = text.trim();
    let text = text
        .strip_prefix('[')
        .and_then(|rest| rest.strip_suffix(']'))
        .map_or(text, str::trim);
    if text.is_empty() {
        return Ok(Vec::new());
    }
    text.split(',')
        .map(|token| {
            token.trim().parse::<usize>().map_err(|_| {
                format!(
                    "`faces` holds a comma-separated list of face indices \
                     (e.g. \"0,2,5\"); \"{token}\" is not one"
                )
            })
        })
        .collect()
}

/// Refuse with a structured answer: log for the person at a terminal and
/// leave the message in `OperatorWarnings`, where a remote caller reads it.
/// `Cancelled` never reaches the history path on its own, and the
/// operator's `allows_undo = false` keeps a successful write out of it too.
fn refuse(commands: &mut Commands, refusal: impl Into<String>) -> OperatorResult {
    let refusal = refusal.into();
    commands.queue(move |world: &mut World| warn_caller(world, refusal));
    OperatorResult::Cancelled
}

#[cfg(test)]
mod brush_selection_set_faces_tests {
    use super::*;
    use bevy::ecs::system::RunSystemOnce;
    use jackdaw_api_internal::operator::OperatorWarnings;
    use jackdaw_scene_types::{Brush, PropertyValue};

    /// A cuboid wears six faces, indexed by the plane order
    /// (+X, -X, +Y, -Y, +Z, -Z), so index 5 is the last legal one.
    fn face_selection_world() -> (World, Entity) {
        let mut world = World::new();
        world.init_resource::<EditMode>();
        world.init_resource::<BrushSelection>();
        world.init_resource::<OperatorWarnings>();
        let entity = world.spawn(Brush::cuboid(1.0, 1.0, 1.0)).id();
        (world, entity)
    }

    fn call_set_faces(world: &mut World, entity: Entity, faces: &str) -> OperatorResult {
        let params = OperatorParameters(
            [
                ("entity".to_string(), PropertyValue::Entity(entity)),
                (
                    "faces".to_string(),
                    PropertyValue::String(faces.to_string().into()),
                ),
            ]
            .into_iter()
            .collect(),
        );
        world
            .run_system_once_with(brush_selection_set_faces, params)
            .expect("the operator system runs")
    }

    fn warnings(world: &World) -> Vec<String> {
        world.resource::<OperatorWarnings>().0.clone()
    }

    #[test]
    fn a_valid_write_lands_faces_and_enters_face_mode() {
        let (mut world, entity) = face_selection_world();

        let result = call_set_faces(&mut world, entity, "0,2,5");

        assert_eq!(result, OperatorResult::Finished);
        assert_eq!(
            *world.resource::<EditMode>(),
            EditMode::BrushEdit(BrushEditMode::Face),
            "the write lands in Face edit mode, the state a face click lands",
        );
        let selection = world.resource::<BrushSelection>();
        assert_eq!(selection.active_brush, Some(entity));
        assert_eq!(
            selection.brushes.keys().copied().collect::<Vec<_>>(),
            [entity]
        );
        let sub = selection.sub(entity).expect("the brush is an edit brush");
        assert_eq!(sub.faces, vec![0, 2, 5]);
        assert!(sub.vertices.is_empty() && sub.edges.is_empty());
        assert!(warnings(&world).is_empty(), "a clean call warns of nothing");
    }

    /// A bracketed spelling — what a JSON array parameter arrives as after
    /// the BRP layer stringifies it — reads the same as the plain form.
    #[test]
    fn a_bracketed_faces_list_reads_the_same() {
        let (mut world, entity) = face_selection_world();

        let result = call_set_faces(&mut world, entity, "[1, 4]");

        assert_eq!(result, OperatorResult::Finished);
        assert_eq!(
            world
                .resource::<BrushSelection>()
                .sub(entity)
                .expect("the brush is an edit brush")
                .faces,
            vec![1, 4],
        );
    }

    /// A direct in-process caller may pass the entity as raw bits, where a
    /// BRP call would have resolved them before the operator ever ran.
    #[test]
    fn raw_bits_entity_parameter_is_accepted_too() {
        let (mut world, entity) = face_selection_world();
        let params = OperatorParameters(
            [
                (
                    "entity".to_string(),
                    PropertyValue::Int(entity.to_bits() as i64),
                ),
                ("faces".to_string(), PropertyValue::String("3".into())),
            ]
            .into_iter()
            .collect(),
        );

        let result = world
            .run_system_once_with(brush_selection_set_faces, params)
            .expect("the operator system runs");

        assert_eq!(result, OperatorResult::Finished);
        assert_eq!(
            world.resource::<BrushSelection>().active_brush,
            Some(entity),
        );
    }

    /// An empty list is a legal write: Face mode on the brush with nothing
    /// selected — the state between entering the mode and the first click.
    #[test]
    fn empty_faces_enters_face_mode_with_nothing_selected() {
        let (mut world, entity) = face_selection_world();

        let result = call_set_faces(&mut world, entity, "");

        assert_eq!(result, OperatorResult::Finished);
        assert_eq!(
            *world.resource::<EditMode>(),
            EditMode::BrushEdit(BrushEditMode::Face),
        );
        let selection = world.resource::<BrushSelection>();
        assert_eq!(selection.active_brush, Some(entity));
        assert!(
            selection
                .sub(entity)
                .expect("the brush is an edit brush")
                .faces
                .is_empty(),
        );
    }

    #[test]
    fn an_out_of_range_index_is_refused_and_writes_nothing() {
        let (mut world, entity) = face_selection_world();

        let result = call_set_faces(&mut world, entity, "0,6");

        assert_eq!(result, OperatorResult::Cancelled);
        assert!(
            warnings(&world)
                .iter()
                .any(|warning| warning.contains("out of range")
                    && warning.contains("6")
                    && warning.contains("6 faces")),
            "the refusal names the index and the face count: {:?}",
            warnings(&world),
        );
        // Neither the mode nor any selection state moved.
        assert_eq!(*world.resource::<EditMode>(), EditMode::Object);
        assert!(world.resource::<BrushSelection>().brushes.is_empty());
        assert_eq!(world.resource::<BrushSelection>().active_brush, None);
    }

    #[test]
    fn a_malformed_token_is_refused_and_writes_nothing() {
        let (mut world, entity) = face_selection_world();

        let result = call_set_faces(&mut world, entity, "0,two");

        assert_eq!(result, OperatorResult::Cancelled);
        assert!(
            warnings(&world)
                .iter()
                .any(|warning| warning.contains("two")),
            "the refusal names the offending token: {:?}",
            warnings(&world),
        );
        assert_eq!(*world.resource::<EditMode>(), EditMode::Object);
        assert!(world.resource::<BrushSelection>().brushes.is_empty());
    }

    #[test]
    fn an_entity_without_a_brush_is_refused() {
        let (mut world, _) = face_selection_world();
        let plain = world.spawn_empty().id();

        let result = call_set_faces(&mut world, plain, "0");

        assert_eq!(result, OperatorResult::Cancelled);
        assert!(
            warnings(&world)
                .iter()
                .any(|warning| warning.contains("no Brush component")),
            "the refusal says the entity carries no Brush: {:?}",
            warnings(&world),
        );
        assert_eq!(*world.resource::<EditMode>(), EditMode::Object);
        assert!(world.resource::<BrushSelection>().brushes.is_empty());
    }

    #[test]
    fn a_missing_parameter_is_refused() {
        let (mut world, entity) = face_selection_world();
        let params = OperatorParameters(
            [("entity".to_string(), PropertyValue::Entity(entity))]
                .into_iter()
                .collect(),
        );

        let result = world
            .run_system_once_with(brush_selection_set_faces, params)
            .expect("the operator system runs");

        assert_eq!(result, OperatorResult::Cancelled);
        assert!(
            warnings(&world)
                .iter()
                .any(|warning| warning.contains("expected")),
        );
        assert_eq!(*world.resource::<EditMode>(), EditMode::Object);
    }

    /// Selection state is UI state, not a scene edit, so the write never
    /// arms undo. This is the same ruling `edit_mode.face` makes and the
    /// same shape the BRP `selection.set` handler keeps (it writes the
    /// resource directly and never pushes). The dispatcher reads this const
    /// to gate the whole history path (`creates_history_entry &&
    /// allows_undo`, `dispatch_operator`), so `false` here means no
    /// snapshot and no `CommandHistory` entry regardless of the caller's
    /// `history` flag.
    #[test]
    fn the_write_never_arms_undo() {
        assert!(!BrushSelectionSetFacesOp::ALLOWS_UNDO);
    }
}
