//! One-shot brush-element operators: delete the active sub-element
//! and nudge selected vertices/edges/faces along Y by one grid step.
//! Dispatch by current `BrushEditMode`.
//!
//! Replace the keybind branches in `interaction::handle_brush_delete`,
//! `brush_face_interact`, `brush_vertex_interact`, and
//! `brush_edge_interact`.

use std::collections::HashSet;

use bevy::math::Affine3A;
use bevy::prelude::*;
use jackdaw_api::prelude::*;
use jackdaw_api_internal::keymap::PresetInput;
use jackdaw_geometry::halfedge::ops::delete_elements::{
    DeleteResult, delete_edges, delete_faces, delete_verts,
};
use jackdaw_geometry::halfedge::{EdgeKey, FaceKey, HalfedgeMesh, VertKey, apply_topology_edit};
use jackdaw_scene_types::Brush;

use jackdaw_editor_core::brush::{
    BrushDragState, BrushEditMode, BrushHalfedge, BrushMeshCache, BrushSelection, EdgeDragState,
    EditMode, VertexDragState,
};
use jackdaw_editor_core::brush_drag_ops::apply_vertex_deltas;
use jackdaw_editor_core::keybind_focus::KeybindFocus;

pub(crate) fn add_to_extension(ctx: &mut ExtensionContext) {
    ctx.register_operator::<BrushDeleteElementOp>()
        .register_operator::<BrushNudgeUpOp>()
        .register_operator::<BrushNudgeDownOp>();

    ctx.bind_operator_host::<BrushDeleteElementOp>([
        PresetInput::key("Delete"),
        PresetInput::key("Backspace"),
    ]);
    ctx.bind_operator_host::<BrushNudgeUpOp>([PresetInput::key("PageUp")]);
    ctx.bind_operator_host::<BrushNudgeDownOp>([PresetInput::key("PageDown")]);
}

/// True when the operator is allowed to mutate brush elements: brush-edit
/// mode active, no text field focused, no drag in flight.
fn can_run_element_op(
    edit_mode: Res<EditMode>,
    keybind_focus: KeybindFocus,
    face_drag: Res<BrushDragState>,
    vertex_drag: Res<VertexDragState>,
    edge_drag: Res<EdgeDragState>,
) -> bool {
    matches!(*edit_mode, EditMode::BrushEdit(_))
        && !keybind_focus.keyboard_is_spoken_for()
        && !face_drag.active
        && !vertex_drag.active
        && !edge_drag.active
        && face_drag.pending.is_none()
        && vertex_drag.pending.is_none()
        && edge_drag.pending.is_none()
}

#[operator(
    id = "brush.delete_element",
    label = "Delete Element",
    description = "Delete the selected vertex / edge / face from the active brush, \
                   destroying the incident geometry and leaving a hole (no merge or \
                   heal, unlike dissolve). Dispatch follows the current \
                   `BrushEditMode`. Available whenever the brush-edit gate \
                   (`can_run_element_op`) passes; the per-mode guard keeps at least \
                   one polygon after a vertex / edge delete so the brush is never \
                   left a loose vertex cloud, and allows a face delete down to the \
                   last face.",
    is_available = can_run_element_op,
)]
pub(crate) fn brush_delete_element(
    _: In<OperatorParameters>,
    edit_mode: Res<EditMode>,
    mut brush_selection: ResMut<BrushSelection>,
    mut brushes: Query<&mut Brush>,
    mut halfedge_q: Query<&mut BrushHalfedge>,
) -> OperatorResult {
    let EditMode::BrushEdit(mode) = *edit_mode else {
        return OperatorResult::Cancelled;
    };
    if matches!(mode, BrushEditMode::Clip | BrushEditMode::Knife) {
        return OperatorResult::Cancelled;
    }

    let edit_entities: Vec<Entity> = brush_selection.edit_brushes().collect();
    let mut any_modified = false;
    for entity in edit_entities {
        let Some(sub) = brush_selection.sub(entity) else {
            continue;
        };
        let sub_verts = sub.vertices.clone();
        let sub_edges = sub.edges.clone();
        let sub_faces = sub.faces.clone();
        let has_selection = match mode {
            BrushEditMode::Vertex => !sub_verts.is_empty(),
            BrushEditMode::Edge => !sub_edges.is_empty(),
            BrushEditMode::Face => !sub_faces.is_empty(),
            BrushEditMode::Clip | BrushEditMode::Knife => false,
        };
        if !has_selection {
            continue;
        }

        let Ok(mut halfedge) = halfedge_q.get_mut(entity) else {
            continue;
        };
        let Ok(mut brush) = brushes.get_mut(entity) else {
            continue;
        };

        // Guard: a vertex / edge delete must leave at least one polygon so the
        // brush is never reduced to a loose vertex cloud. A face delete may go
        // down to the last face. The gate runs the delete on a clone; the live
        // delete runs inside the reconcile closure below.
        let edit: Box<dyn FnOnce(&mut HalfedgeMesh) -> DeleteResult> = match mode {
            BrushEditMode::Vertex => {
                let keys: Vec<VertKey> = sub_verts
                    .iter()
                    .filter_map(|&v| halfedge.vert_keys.get(v).copied())
                    .collect();
                if keys.is_empty() {
                    continue;
                }
                let preview = preview_face_count(&halfedge.mesh, |mesh| delete_verts(mesh, &keys));
                if preview == 0 {
                    continue;
                }
                Box::new(move |mesh| delete_verts(mesh, &keys))
            }
            BrushEditMode::Edge => {
                let keys: Vec<EdgeKey> = sub_edges
                    .iter()
                    .filter_map(|&(a, b)| edge_key_between(&halfedge, a, b))
                    .collect();
                if keys.is_empty() {
                    continue;
                }
                let preview = preview_face_count(&halfedge.mesh, |mesh| delete_edges(mesh, &keys));
                if preview == 0 {
                    continue;
                }
                Box::new(move |mesh| delete_edges(mesh, &keys))
            }
            BrushEditMode::Face => {
                let keys: Vec<FaceKey> = sub_faces
                    .iter()
                    .filter_map(|&f| halfedge.face_keys.get(f).copied())
                    .collect();
                if keys.is_empty() {
                    continue;
                }
                Box::new(move |mesh| delete_faces(mesh, &keys))
            }
            BrushEditMode::Clip | BrushEditMode::Knife => continue,
        };

        apply_delete_to_brush(&mut brush, &mut halfedge, edit);

        if let Some(sub) = brush_selection.brushes.get_mut(&entity) {
            sub.vertices.clear();
            sub.edges.clear();
            sub.faces.clear();
        }
        any_modified = true;
    }

    if any_modified {
        OperatorResult::Finished
    } else {
        OperatorResult::Cancelled
    }
}

/// Run a delete on a clone of the mesh and report the surviving face count,
/// used to gate a destructive vertex / edge delete without mutating the live
/// mesh.
fn preview_face_count(
    mesh: &HalfedgeMesh,
    run: impl FnOnce(&mut HalfedgeMesh) -> DeleteResult,
) -> usize {
    let mut probe = mesh.clone();
    run(&mut probe);
    probe.face_count()
}

/// Map a selected cache-edge `(a, b)` to its live `EdgeKey` via the parallel
/// `vert_keys` table.
fn edge_key_between(halfedge: &BrushHalfedge, a: usize, b: usize) -> Option<EdgeKey> {
    let &va = halfedge.vert_keys.get(a)?;
    let &vb = halfedge.vert_keys.get(b)?;
    halfedge
        .mesh
        .edges
        .iter()
        .find(|(_, e)| (e.v[0] == va && e.v[1] == vb) || (e.v[0] == vb && e.v[1] == va))
        .map(|(k, _)| k)
}

/// Run a destructive delete and reconcile the brush. Applies `edit` through the
/// topology seam (recache normals, flatten, recompute planes, re-lift binding),
/// then rebuilds `brush.faces` parallel to the surviving polygons by re-indexing
/// the old per-face data through `surviving_faces` so each face keeps its
/// material + uv source rather than being default-filled.
fn apply_delete_to_brush(
    brush: &mut Brush,
    halfedge: &mut BrushHalfedge,
    edit: impl FnOnce(&mut HalfedgeMesh) -> DeleteResult,
) {
    let old_faces = brush.faces.clone();
    let result = apply_topology_edit(&mut brush.faces, &mut brush.topology, &mut halfedge.0, edit);

    let mut new_faces: Vec<jackdaw_scene_types::BrushFaceData> =
        Vec::with_capacity(result.surviving_faces.len());
    for &old_idx in &result.surviving_faces {
        let old = old_faces
            .get(old_idx)
            .cloned()
            .unwrap_or_else(|| old_faces.last().cloned().unwrap_or_default());
        new_faces.push(old);
    }
    brush.faces = new_faces;
    brush.topology.recompute_face_planes(&mut brush.faces);
}

#[operator(
    id = "brush.nudge_up",
    label = "Nudge Up",
    description = "Nudge the selected sub-element +Y by one grid step. \
                   Dispatch follows `BrushEditMode`; availability \
                   (`can_run_element_op`) gates on the brush-edit gate.",
    is_available = can_run_element_op,
)]
pub(crate) fn brush_nudge_up(
    _: In<OperatorParameters>,
    edit_mode: Res<EditMode>,
    mut brush_selection: ResMut<BrushSelection>,
    brushes: Query<&mut Brush>,
    brush_caches: Query<&BrushMeshCache>,
    halfedges: Query<&mut BrushHalfedge>,
    transforms: Query<&GlobalTransform>,
    snap: Res<jackdaw_editor_core::snapping::SnapSettings>,
) -> OperatorResult {
    nudge_brush_element(
        1.0,
        edit_mode,
        &mut brush_selection,
        brushes,
        brush_caches,
        halfedges,
        transforms,
        snap,
    )
}

#[operator(
    id = "brush.nudge_down",
    label = "Nudge Down",
    description = "Nudge the selected sub-element -Y by one grid step. \
                   Dispatch follows `BrushEditMode`; availability \
                   (`can_run_element_op`) gates on the brush-edit gate.",
    is_available = can_run_element_op,
)]
pub(crate) fn brush_nudge_down(
    _: In<OperatorParameters>,
    edit_mode: Res<EditMode>,
    mut brush_selection: ResMut<BrushSelection>,
    brushes: Query<&mut Brush>,
    brush_caches: Query<&BrushMeshCache>,
    halfedges: Query<&mut BrushHalfedge>,
    transforms: Query<&GlobalTransform>,
    snap: Res<jackdaw_editor_core::snapping::SnapSettings>,
) -> OperatorResult {
    nudge_brush_element(
        -1.0,
        edit_mode,
        &mut brush_selection,
        brushes,
        brush_caches,
        halfedges,
        transforms,
        snap,
    )
}

fn nudge_brush_element(
    direction: f32,
    edit_mode: Res<EditMode>,
    brush_selection: &mut BrushSelection,
    mut brushes: Query<&mut Brush>,
    brush_caches: Query<&BrushMeshCache>,
    mut halfedges: Query<&mut BrushHalfedge>,
    transforms: Query<&GlobalTransform>,
    snap: Res<jackdaw_editor_core::snapping::SnapSettings>,
) -> OperatorResult {
    let EditMode::BrushEdit(mode) = *edit_mode else {
        return OperatorResult::Cancelled;
    };

    // Gather per-brush affected vertex sets from immutable reads before mutation.
    struct NudgePlan {
        entity: Entity,
        affected_verts: HashSet<usize>,
    }

    let offset = Vec3::new(0.0, direction * snap.grid_size(), 0.0);
    let edit_entities: Vec<Entity> = brush_selection.edit_brushes().collect();
    let mut plans: Vec<NudgePlan> = Vec::new();
    for e in &edit_entities {
        let e = *e;
        let Some(sub) = brush_selection.sub(e) else {
            continue;
        };
        let Ok(cache) = brush_caches.get(e) else {
            continue;
        };
        let affected: HashSet<usize> = match mode {
            BrushEditMode::Vertex if !sub.vertices.is_empty() => {
                sub.vertices.iter().copied().collect()
            }
            BrushEditMode::Edge if !sub.edges.is_empty() => {
                sub.edges.iter().flat_map(|&(a, b)| [a, b]).collect()
            }
            BrushEditMode::Face if !sub.faces.is_empty() => sub
                .faces
                .iter()
                .filter_map(|&fi| cache.authored_face_polygons().get(fi))
                .flat_map(|poly| poly.iter().copied())
                .collect(),
            _ => continue,
        };
        if affected.is_empty() {
            continue;
        }
        plans.push(NudgePlan {
            entity: e,
            affected_verts: affected,
        });
    }

    if plans.is_empty() {
        return OperatorResult::Cancelled;
    }

    let mut any_modified = false;
    for plan in plans {
        let Ok(cache) = brush_caches.get(plan.entity) else {
            continue;
        };
        let Ok(mut brush) = brushes.get_mut(plan.entity) else {
            continue;
        };
        let mut halfedge = halfedges.get_mut(plan.entity).ok();
        let world_from_local = match transforms.get(plan.entity) {
            Ok(global) => global.affine(),
            Err(_) => continue,
        };
        let affected: Vec<usize> = plan.affected_verts.into_iter().collect();
        if !apply_nudge_to_brush(
            &mut brush,
            halfedge.as_deref_mut(),
            offset,
            &world_from_local,
            &affected,
            cache.authored_vertices(),
            cache.authored_face_polygons(),
        ) {
            continue;
        }
        any_modified = true;
    }

    if any_modified {
        OperatorResult::Finished
    } else {
        OperatorResult::Cancelled
    }
}

/// Apply one nudge step to a single brush: move `affected_verts` (authored
/// vertex indices) by the world-space `offset`, re-expressed in the brush's
/// own local space through `world_from_local`. Returns true when the brush
/// changed.
///
/// A missing `halfedge` (a legacy plane-only brush with no lifted edit mesh)
/// falls back to the convex-hull rebuild through `apply_vertex_deltas`'s
/// legacy path, matching the pre-topology behaviour.
fn apply_nudge_to_brush(
    brush: &mut Brush,
    halfedge: Option<&mut BrushHalfedge>,
    offset: Vec3,
    world_from_local: &Affine3A,
    affected_verts: &[usize],
    all_vertices: &[Vec3],
    face_polygons: &[Vec<usize>],
) -> bool {
    // Mirror the drag-tail conversion (`broadcast_drag_to_captures`): lift
    // the authored start positions to world space, add the world offset, and
    // re-express each destination in the brush's own local space, so a nudge
    // of one grid step travels along the world axis regardless of the
    // brush's rotation, exactly like a vertex drag.
    let world_to_local = world_from_local.inverse();
    let new_positions: Vec<Vec3> = affected_verts
        .iter()
        .map(|&vi| {
            let local_start = all_vertices.get(vi).copied().unwrap_or(Vec3::ZERO);
            let start_world = world_from_local.transform_point3(local_start);
            world_to_local.transform_point3(start_world + offset)
        })
        .collect();
    // Report a modification only when at least one vertex actually moves, so
    // a zero-step or out-of-range selection keeps the operator's undo state
    // untouched.
    let moved = affected_verts
        .iter()
        .zip(&new_positions)
        .any(|(&vi, next)| {
            all_vertices
                .get(vi)
                .is_some_and(|start| (*start - *next).length_squared() > 1e-12)
        });
    if !moved {
        return false;
    }
    let start_brush = brush.clone();
    // The halfedge path mutates the lifted edit mesh in place and keeps the
    // face list index-stable, preserving concave topology. With `halfedge`
    // None (legacy plane-only brush, no lifted mesh) `apply_vertex_deltas`
    // falls back to its convex-hull rebuild, matching the pre-topology
    // behaviour. Mirror clipping stays out of the nudge path: the rebuild it
    // replaces had no mirror semantics either.
    apply_vertex_deltas(
        brush,
        halfedge,
        None,
        &start_brush,
        all_vertices,
        face_polygons,
        affected_verts,
        &new_positions,
    );
    true
}

#[cfg(test)]
mod nudge_tests {
    use super::*;
    use jackdaw_csg::{BooleanOp, CsgInput, brush_boolean};

    const STEP: f32 = 0.25;
    const OFFSET: Vec3 = Vec3::new(0.0, STEP, 0.0);

    /// Unit cuboid moved so it sits centred on `center`.
    fn translated_cuboid(half: f32, center: Vec3) -> Brush {
        let mut brush = Brush::cuboid(half, half, half);
        for v in &mut brush.topology.vertices {
            v.position += center;
        }
        for f in &mut brush.faces {
            f.plane.distance += f.plane.normal.dot(center);
        }
        brush
    }

    /// L-shaped concave brush: unit cube minus an overlapping corner cube —
    /// the same CSG shape the bug report describes (subtract leaves a
    /// concave brush that the convex-hull rebuild then destroys).
    fn concave_l_brush() -> Brush {
        let base = Brush::cuboid(1.0, 1.0, 1.0);
        let corner = translated_cuboid(0.5, Vec3::new(0.75, 0.75, 0.75));
        let result = brush_boolean(
            &CsgInput::new(&base.faces, &base.topology),
            &CsgInput::new(&corner.faces, &corner.topology),
            BooleanOp::Difference,
        )
        .expect("corner subtract should produce the concave L");
        Brush {
            faces: result.faces,
            topology: result.topology,
        }
    }

    /// Vertex indices of the first face whose ring has more than four verts
    /// (the L-shaped end cap of the subtracted brush): the vertex set a
    /// face-mode nudge of that face would move.
    fn concave_face_verts(brush: &Brush) -> Vec<usize> {
        brush
            .topology
            .polygons
            .iter()
            .find(|p| p.loop_total > 4)
            .map(|p| {
                let start = p.loop_start as usize;
                let count = p.loop_total as usize;
                (0..count)
                    .map(|i| brush.topology.loops[start + i].vert as usize)
                    .collect()
            })
            .expect("concave L should have a >4-vert ring")
    }

    /// Authored vertex positions read the same way the nudge plan reads
    /// `BrushMeshCache::authored_vertices` (identity for an unmodified brush).
    fn authored_vertices(brush: &Brush) -> Vec<Vec3> {
        brush.topology.vertices.iter().map(|v| v.position).collect()
    }

    /// Authored face polygons read the same way the nudge plan reads
    /// `BrushMeshCache::authored_face_polygons`.
    fn authored_face_polygons(brush: &Brush) -> Vec<Vec<usize>> {
        brush
            .topology
            .polygons
            .iter()
            .map(|p| {
                let start = p.loop_start as usize;
                let count = p.loop_total as usize;
                (0..count)
                    .map(|i| brush.topology.loops[start + i].vert as usize)
                    .collect()
            })
            .collect()
    }

    /// Run one nudge step through the same core the operator uses, with a
    /// freshly lifted edit mesh (the live halfedge component).
    fn nudge_once(brush: &Brush, affected: &[usize]) -> Brush {
        let mut nudged = brush.clone();
        let mut halfedge =
            jackdaw_editor_core::brush::BrushHalfedge::from_topology(&brush.topology);
        let ok = super::apply_nudge_to_brush(
            &mut nudged,
            Some(&mut halfedge),
            OFFSET,
            &Affine3A::IDENTITY,
            affected,
            &authored_vertices(brush),
            &authored_face_polygons(brush),
        );
        assert!(ok, "nudge should report a modification");
        nudged
    }

    /// Per-index shape assertion: face / polygon / vertex counts unchanged,
    /// affected verts moved by exactly the world offset, every other vert
    /// bit-identical.
    fn assert_shape_preserved(before: &Brush, after: &Brush, affected: &[usize]) {
        assert_eq!(
            after.faces.len(),
            before.faces.len(),
            "face count must not change"
        );
        assert_eq!(
            after.topology.polygons.len(),
            before.topology.polygons.len(),
            "polygon count must not change"
        );
        let before_verts: Vec<Vec3> = before
            .topology
            .vertices
            .iter()
            .map(|v| v.position)
            .collect();
        let after_verts: Vec<Vec3> = after.topology.vertices.iter().map(|v| v.position).collect();
        assert_eq!(
            after_verts.len(),
            before_verts.len(),
            "vertex count must not change"
        );
        for (i, before) in before_verts.iter().enumerate() {
            let after = after_verts[i];
            if affected.contains(&i) {
                assert_eq!(
                    after,
                    *before + OFFSET,
                    "vert {i} should move by exactly the offset"
                );
            } else {
                assert_eq!(
                    (after - *before).length_squared(),
                    0.0,
                    "vert {i} must not move"
                );
            }
        }
    }

    #[test]
    fn face_nudge_on_concave_brush_preserves_the_shape() {
        let brush = concave_l_brush();
        let affected = concave_face_verts(&brush);
        assert!(
            affected.len() > 4,
            "the selected face ring should be concave (>4 verts), got {}",
            affected.len()
        );

        let nudged = nudge_once(&brush, &affected);
        assert_shape_preserved(&brush, &nudged, &affected);
    }

    #[test]
    fn vertex_nudge_on_concave_brush_preserves_the_shape() {
        let brush = concave_l_brush();
        // Nudge a single vert of the concave ring, the vertex-mode selection.
        let affected = vec![concave_face_verts(&brush)[0]];

        let nudged = nudge_once(&brush, &affected);
        assert_shape_preserved(&brush, &nudged, &affected);
    }

    #[test]
    fn nudge_offset_follows_world_y_through_brush_rotation() {
        let brush = Brush::cuboid(1.0, 1.0, 1.0);
        // Rotate the brush frame 90 degrees about Z: local +Y points along
        // world -X, so a world-Y step arrives as a local-X step.
        let world_from_local = Affine3A::from_rotation_translation(
            Quat::from_rotation_z(core::f32::consts::FRAC_PI_2),
            Vec3::ZERO,
        );
        let affected = vec![0usize];

        let mut nudged = brush.clone();
        let mut halfedge =
            jackdaw_editor_core::brush::BrushHalfedge::from_topology(&brush.topology);
        let ok = super::apply_nudge_to_brush(
            &mut nudged,
            Some(&mut halfedge),
            OFFSET,
            &world_from_local,
            &affected,
            &authored_vertices(&brush),
            &authored_face_polygons(&brush),
        );
        assert!(ok, "nudge should report a modification");

        let before_world = world_from_local.transform_point(authored_vertices(&brush)[0]);
        let after_world = world_from_local.transform_point(nudged.topology.vertices[0].position);
        assert_eq!(
            nudged.faces.len(),
            brush.faces.len(),
            "face count must not change"
        );
        assert!(
            (after_world.y - (before_world.y + STEP)).abs() < 1e-4,
            "the nudged vert should rise one grid step in WORLD Y, got {} -> {}",
            before_world.y,
            after_world.y
        );
    }

    #[test]
    fn face_nudge_on_a_convex_brush_keeps_cuboid_shape() {
        let brush = Brush::cuboid(1.0, 1.0, 1.0);
        // +Y face ring: verts 2, 3, 6, 7 in the canonical cuboid layout.
        let affected = vec![2usize, 3, 6, 7];
        let before_faces = brush.faces.len();

        let nudged = nudge_once(&brush, &affected);

        assert_eq!(
            nudged.faces.len(),
            before_faces,
            "a convex brush must keep every face"
        );
        assert_eq!(nudged.topology.vertices.len(), 8, "cuboid keeps 8 verts");
        // Position multiset: the four bottom verts are untouched, the top
        // ring is lifted. Compare as sorted multisets with an epsilon so the
        // assertion stays order-independent.
        let mut before: Vec<Vec3> = authored_vertices(&brush);
        let mut after: Vec<Vec3> = authored_vertices(&nudged);
        let lift = |v: &mut Vec3| {
            if v.y > 0.0 {
                *v += OFFSET;
            }
        };
        before.iter_mut().for_each(lift);
        let near = |a: &Vec3, b: &Vec3| (*a - *b).length_squared() < 1e-8;
        for vb in &before {
            match after.iter_mut().find(|va| near(va, vb)) {
                Some(va) => {
                    *va = Vec3::NAN; // consume the match
                }
                None => panic!("nudged cuboid lost a vertex near {vb:?}; got {after:?}"),
            }
        }
    }
}
