use crate::commands::CommandHistory;
use crate::draw_brush::{DrawBrushState, env_allows_brush_op};
use crate::keybind_focus::KeybindFocus;
use crate::prelude::*;
use crate::{
    brush::{BrushMeshCache, BrushMeshChunk},
    selection::Selection,
    viewport::ViewportCursor,
};
use bevy::{
    picking::mesh_picking::ray_cast::{MeshRayCast, MeshRayCastSettings, RayCastVisibility},
    prelude::*,
};
use jackdaw_geometry::{
    brush_planes_to_world, clean_degenerate_faces, compute_brush_geometry_from_planes,
    compute_brush_topology, point_inside_all_planes,
};
use jackdaw_scene_types::{Brush, BrushFaceData, BrushPlane};

/// `brush.extend_face_to_brush` needs either (a) Face edit mode with a
/// face picked and another brush selected, or (b) Object mode with >= 2
/// brushes selected and a remembered/hovered face on the primary.
fn can_run_extend_face(
    keybind_focus: KeybindFocus,
    modal: Res<crate::modal_transform::ModalTransformState>,
    draw_state: Res<DrawBrushState>,
    selection: Res<Selection>,
    brush_selection: Res<crate::brush::BrushSelection>,
    edit_mode: Res<crate::brush::EditMode>,
    brushes: Query<(), With<Brush>>,
) -> bool {
    if !env_allows_brush_op(&keybind_focus, &modal, &draw_state) {
        return false;
    }
    let brush_count = selection
        .entities
        .iter()
        .filter(|&&e| brushes.contains(e))
        .count();
    match *edit_mode {
        crate::brush::EditMode::BrushEdit(crate::brush::BrushEditMode::Face) => {
            brush_selection.active_brush.is_some()
                && brush_selection
                    .active_sub()
                    .is_some_and(|s| !s.faces.is_empty())
                && brush_count >= 1
        }
        crate::brush::EditMode::Object => {
            brush_count >= 2
                && brush_selection.last_face_entity.is_some_and(|e| {
                    brush_selection.last_face_index.is_some() && brushes.contains(e)
                })
        }
        _ => false,
    }
}

#[operator(
    id = "brush.extend_face_to_brush",
    label = "Extend to Brush",
    description = "Extend a face of the primary brush to conform to the shape of \
                   the other selected brushes. Two entry paths:\n\
                   - `EditMode::BrushEdit(Face)` with a face selected on \
                     `BrushSelection` and >= 1 other brush in `Selection::entities`.\n\
                   - `EditMode::Object` with >= 2 brushes in `Selection::entities` \
                     and a remembered face on the primary.\n\
                   Availability (`can_run_extend_face`) is false when neither \
                   entry path applies. The Object-mode path additionally \
                   tries to resolve a hovered face via raycast once invoked; \
                   if that also fails it returns `Cancelled`.\n\
                   Refuses with a toast when the primary brush is concave: \
                   the extension rebuild is the intersection of the face \
                   half-spaces, which would collapse the concave shape into \
                   its convex hull.",
    is_available = can_run_extend_face,
    allows_undo = false,
)]
pub(crate) fn brush_extend_face_to_brush(
    _: In<OperatorParameters>,
    mut edit_mode: ResMut<crate::brush::EditMode>,
    selection: Res<Selection>,
    mut brush_selection: ResMut<crate::brush::BrushSelection>,
    vp: ViewportCursor,
    mut ray_cast: MeshRayCast,
    brush_chunks: Query<&BrushMeshChunk>,
    brush_caches: Query<&BrushMeshCache>,
    brush_query: Query<&Brush>,
    mut commands: Commands,
) -> Option<OperatorResult> {
    // Resolve (primary, face_index, targets) depending on edit mode
    let (primary, face_index, targets) = if *edit_mode
        == crate::brush::EditMode::BrushEdit(crate::brush::BrushEditMode::Face)
    {
        // Face mode path: primary is the brush being edited, face is the selected face
        let primary = brush_selection
            .active_brush
            .filter(|&e| brush_query.contains(e))?;
        let face_index = brush_selection
            .sub(primary)
            .and_then(|s| s.faces.last().copied())?;
        let targets: Vec<Entity> = selection
            .entities
            .iter()
            .copied()
            .filter(|&e| e != primary && brush_query.contains(e))
            .collect();
        if targets.is_empty() {
            return None;
        }
        (primary, face_index, targets)
    } else if *edit_mode == crate::brush::EditMode::Object {
        // Object mode: need 2+ brushes selected
        let selected_brushes: Vec<Entity> = selection
            .entities
            .iter()
            .copied()
            .filter(|&e| brush_query.contains(e))
            .collect();
        if selected_brushes.len() < 2 {
            return None;
        }

        let primary = selection.primary().filter(|e| brush_query.contains(*e))?;
        let targets: Vec<Entity> = selected_brushes
            .into_iter()
            .filter(|&e| e != primary)
            .collect();

        // Try hover raycast first to find the face
        let face_index =
            find_hovered_face_on_brush(primary, &vp, &mut ray_cast, &brush_chunks, &brush_caches)
                .or_else(|| {
                    // Fall back to remembered face
                    if brush_selection.last_face_entity == Some(primary) {
                        brush_selection.last_face_index
                    } else {
                        None
                    }
                });

        let face_index = face_index?;
        (primary, face_index, targets)
    } else {
        return None;
    };

    // Refuse a concave primary before any state changes: the rebuild in the
    // impl recasts the brush as the intersection of its face half-spaces,
    // which would collapse a concave shape into its convex hull. This sits
    // before the face-mode exit, so a refusal leaves the editor state
    // exactly as it was.
    if let Ok(primary_brush) = brush_query.get(primary)
        && !brush_is_convex(primary_brush)
    {
        warn!("{CONCAVE_EXTEND_REFUSAL}");
        commands.queue(move |world: &mut World| toast_brush_notice(world, CONCAVE_EXTEND_REFUSAL));
        return None;
    }

    // If we were in face mode, exit it (geometry is about to change, indices become invalid)
    if *edit_mode == crate::brush::EditMode::BrushEdit(crate::brush::BrushEditMode::Face) {
        *edit_mode = crate::brush::EditMode::Object;
        brush_selection.clear();
    }

    let targets_clone = targets.clone();
    commands.queue(move |world: &mut World| {
        extend_face_to_brush_impl(world, primary, &targets_clone, face_index);
    });
    Some(OperatorResult::Finished)
}

/// Raycast from cursor to find a hovered brush face belonging to the given
/// brush. Returns the authored face index if found; a hit on a mirrored
/// copy resolves to its source face.
fn find_hovered_face_on_brush(
    brush_entity: Entity,
    vp: &ViewportCursor,
    ray_cast: &mut MeshRayCast,
    brush_chunks: &Query<&BrushMeshChunk>,
    brush_caches: &Query<&BrushMeshCache>,
) -> Option<usize> {
    let cursor_pos = vp.cursor()?;
    let camera_entity = vp.camera_entity()?;
    let viewport_entity = vp.viewport_entity()?;
    let (camera, cam_tf) = vp.camera_for(camera_entity)?;
    let viewport_cursor = vp.viewport_cursor_for(camera, viewport_entity, cursor_pos)?;
    let ray = camera.viewport_to_world(cam_tf, viewport_cursor).ok()?;

    let settings = MeshRayCastSettings::default().with_visibility(RayCastVisibility::Any);
    let hits = ray_cast.cast_ray(ray, &settings);

    for (hit_entity, hit_data) in hits {
        let Ok(chunk) = brush_chunks.get(*hit_entity) else {
            continue;
        };
        if chunk.brush_entity != brush_entity {
            continue;
        }
        let Some(tri_idx) = hit_data.triangle_index else {
            continue;
        };
        let Some(&face_idx) = chunk.face_of_tri.get(tri_idx) else {
            continue;
        };
        // A hit on a bisect cut cap has no authored face and is skipped.
        let face_idx = match brush_caches.get(brush_entity) {
            Ok(cache) => {
                let Some(authored) = cache.authored_face(face_idx as usize) else {
                    continue;
                };
                authored
            }
            Err(_) => face_idx as usize,
        };
        return Some(face_idx);
    }
    None
}

/// The refusal message when the primary brush is concave, carried to the
/// log by `warn!` and to the screen by [`toast_brush_notice`].
const CONCAVE_EXTEND_REFUSAL: &str = "Extend to Brush refused: the primary brush is concave, \
    and the extension rebuilds the brush as the intersection of its face planes, which \
    would collapse it into a convex hull.";

/// Whether the brush's authored vertices all sit on or inside every authored
/// face plane — the definition of a convex brush.
///
/// `Extend to Brush` rebuilds the primary as the intersection of its face
/// half-spaces, which only reproduces convex brushes: a concave brush has
/// hull corners poking past its re-entrant walls (a vertex strictly outside
/// some face plane), and the rebuild would silently recast it as its convex
/// hull. Checked in local space — convexity is rigid-transform invariant, so
/// a rotated brush needs no world conversion to judge.
///
/// Tolerance is [`jackdaw_geometry::EPSILON`] (1e-4), the same tolerance the
/// plane intersection itself and extend's no-op comparison use, so float
/// residue on a convex brush is not misread as concavity.
///
/// A legacy plane-only brush (empty topology) has no authored vertices; its
/// shape IS the half-space intersection, so it counts as convex.
fn brush_is_convex(brush: &Brush) -> bool {
    brush
        .topology
        .vertices
        .iter()
        .all(|vert| point_inside_all_planes(vert.position, &brush.faces))
}

/// Puts a brush notice on screen as well as in the log.
///
/// The brush-domain equivalent of `crate::terrain::toast_terrain_notice`,
/// which is the terrain channel's wrapper over the same feathers toast;
/// kept local to this file because the extend refusal is the one brush-domain
/// op that declines today. A no-op without the editor's fonts, which is the
/// headless case tests run in.
fn toast_brush_notice(world: &mut World, message: &str) {
    let (Some(editor_font), Some(icon_font)) = (
        world
            .get_resource::<jackdaw_feathers::icons::EditorFont>()
            .map(|f| f.0.clone()),
        world
            .get_resource::<jackdaw_feathers::icons::IconFont>()
            .map(|f| f.0.clone()),
    ) else {
        return;
    };
    world.spawn(jackdaw_feathers::toast::toast(
        jackdaw_feathers::toast::ToastVariant::Error,
        message,
        jackdaw_feathers::toast::DEFAULT_TOAST_DURATION,
        &editor_font,
        &icon_font,
    ));
}

/// Core logic for Extend Face to Brush.
///
/// Removes the specified face from the primary brush, adds all target brush faces,
/// then computes the intersection. The result is the primary brush reshaped to
/// conform to the target brushes in the direction of the removed face.
pub(crate) fn extend_face_to_brush_impl(
    world: &mut World,
    primary: Entity,
    targets: &[Entity],
    face_index: usize,
) {
    // Read primary brush
    let Some(primary_brush) = world.get::<Brush>(primary) else {
        return;
    };
    let old_brush = primary_brush.clone();
    // Defense in depth beside the operator's entry guard: a concave primary
    // cannot survive the rebuild below (it recasts the brush as the
    // intersection of its face half-spaces, collapsing a concave shape into
    // its convex hull), so refuse before any geometry, AST or undo state
    // changes.
    if !brush_is_convex(&old_brush) {
        warn!("{CONCAVE_EXTEND_REFUSAL}");
        toast_brush_notice(world, CONCAVE_EXTEND_REFUSAL);
        return;
    }
    if face_index >= old_brush.faces.len() {
        return;
    }

    let Some(primary_gtf) = world.get::<GlobalTransform>(primary) else {
        return;
    };
    let (_, rotation, translation) = primary_gtf.to_scale_rotation_translation();
    let inv_rotation = rotation.inverse();

    // Transform primary faces to world space, removing the target face
    let all_world_faces = brush_planes_to_world(&old_brush.faces, rotation, translation);
    let removed_normal = all_world_faces[face_index].plane.normal;
    let mut world_faces: Vec<BrushFaceData> = all_world_faces
        .into_iter()
        .enumerate()
        .filter(|(i, _)| *i != face_index)
        .map(|(_, f)| f)
        .collect();

    // Collect candidate target faces in world space
    let mut candidate_faces = Vec::new();
    for &target in targets {
        let Some(target_brush) = world.get::<Brush>(target) else {
            continue;
        };
        let Some(target_gtf) = world.get::<GlobalTransform>(target) else {
            continue;
        };
        let (_, t_rot, t_trans) = target_gtf.to_scale_rotation_translation();
        let target_world_faces = brush_planes_to_world(&target_brush.faces, t_rot, t_trans);
        // Flip target faces: negate normal and distance so the half-space constraint
        // means "on the outside of the target brush" rather than "inside it". This way
        // the wall extends UP TO the target surface instead of being clipped to the
        // target interior.
        candidate_faces.extend(target_world_faces.into_iter().map(|f| BrushFaceData {
            plane: BrushPlane {
                normal: -f.plane.normal,
                distance: -f.plane.distance,
            },
            ..f
        }));
    }

    // Filter target faces: prefer angled faces (not anti-parallel or perpendicular to the
    // removed face). Anti-parallel faces (dot approx -1) would just re-cap at the same level,
    // and perpendicular/same-direction faces (dot >= 0) don't constrain the extension.
    let angled: Vec<BrushFaceData> = candidate_faces
        .iter()
        .filter(|f| {
            let dot = f.plane.normal.dot(removed_normal);
            dot < -0.01 && dot > -0.99
        })
        .cloned()
        .collect();

    // If we found angled faces, use those. Otherwise fall back to all faces with a
    // negative dot (the simple flat-ceiling case where anti-parallel IS the constraint).
    if !angled.is_empty() {
        world_faces.extend(angled);
    } else {
        let opposing: Vec<BrushFaceData> = candidate_faces
            .into_iter()
            .filter(|f| f.plane.normal.dot(removed_normal) < -0.01)
            .collect();
        world_faces.extend(opposing);
    }

    // Compute geometry from combined face set
    let (verts, _) = compute_brush_geometry_from_planes(&world_faces);
    if verts.len() < 4 {
        return;
    }

    // No-op check: compare with original geometry
    let (old_verts, _) = compute_brush_geometry_from_planes(&brush_planes_to_world(
        &old_brush.faces,
        rotation,
        translation,
    ));
    if verts.len() == old_verts.len() {
        let mut changed = false;
        for (a, b) in verts.iter().zip(old_verts.iter()) {
            if a.distance(*b) > 1e-4 {
                changed = true;
                break;
            }
        }
        if !changed {
            return;
        }
    }

    // Convert ALL world faces back to local space (keeping constraint planes),
    // then clean degenerate faces once in local space.
    let local_faces: Vec<BrushFaceData> = world_faces
        .iter()
        .map(|f| BrushFaceData {
            plane: BrushPlane {
                normal: inv_rotation * f.plane.normal,
                distance: f.plane.distance - f.plane.normal.dot(translation),
            },
            ..f.clone()
        })
        .collect();
    let local_clean = clean_degenerate_faces(&local_faces);
    if local_clean.len() < 4 {
        return;
    }
    // Apply via undo-able SetBrush command (ECS + AST)
    let topology = compute_brush_topology(&local_clean);
    let new_brush = Brush {
        faces: local_clean,
        topology,
    };
    crate::brush::sync_brush_to_ast(world, primary, &new_brush);
    if let Some(mut brush) = world.get_mut::<Brush>(primary) {
        *brush = new_brush.clone();
    }

    let cmd = crate::brush::SetBrush {
        entity: primary,
        old: old_brush,
        new: new_brush,
        label: "Extend face to brush".to_string(),
    };
    let mut history = world.resource_mut::<CommandHistory>();
    history.push_executed(Box::new(cmd));
}

#[cfg(test)]
mod extend_face_tests {
    use super::*;
    use jackdaw_csg::{BooleanOp, CsgInput, brush_boolean};

    /// Cuboid of half extent `half` moved so it sits centred on `center`
    /// (the R7 test construction).
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

    /// L-shaped concave brush: unit cube minus an overlapping corner cube,
    /// the R7 red-evidence construction (subtract leaves a concave brush
    /// the convex plane rebuild recasts as its hull).
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

    /// Face index of the re-entrant +Y bite wall (normal +Y at the bite
    /// depth 0.25, not the original +Y face plane at 1.0): removing it opens
    /// the bite, and the half-space rebuild then recasts the brush as a box.
    fn reentrant_plus_y_face(brush: &Brush) -> usize {
        brush
            .faces
            .iter()
            .position(|f| f.plane.normal.dot(Vec3::Y) > 0.9 && f.plane.distance < 0.4)
            .expect("the L should keep a re-entrant +Y bite wall")
    }

    /// A wall squared to the extension direction: its oblique faces are the
    /// "angled" constraints the extend resolves against (the construction the
    /// extend undo guard drives through the full editor).
    fn rotated_wall_gt(translation: Vec3) -> GlobalTransform {
        GlobalTransform::from(
            Transform::from_translation(translation)
                .with_rotation(Quat::from_rotation_y(std::f32::consts::FRAC_PI_4)),
        )
    }

    /// A bare world holding the extend impl's collaborators: the undo
    /// history, the AST-sync type registry, and the editor fonts so the
    /// refusal toast is observable (the headless editor runs keep the fonts
    /// out, which is the toast's no-op guard).
    fn extend_world(
        primary: Brush,
        primary_tf: GlobalTransform,
        target: Brush,
        target_tf: GlobalTransform,
    ) -> (World, Entity, Entity) {
        let mut world = World::new();
        world.insert_resource(CommandHistory::default());
        world.insert_resource(AppTypeRegistry::default());
        world.insert_resource(jackdaw_feathers::icons::EditorFont(
            Handle::<Font>::default(),
        ));
        world.insert_resource(jackdaw_feathers::icons::IconFont(Handle::<Font>::default()));
        let primary = world.spawn((primary, primary_tf)).id();
        let target = world.spawn((target, target_tf)).id();
        (world, primary, target)
    }

    /// Exact shape snapshot: the authored face data (via Debug, covering
    /// plane + material + UV fields) and the authored vertex positions.
    fn shape_signature(brush: &Brush) -> (String, Vec<Vec3>) {
        (
            format!("{:?}", brush.faces),
            brush.topology.vertices.iter().map(|v| v.position).collect(),
        )
    }

    fn toast_count(world: &mut World) -> usize {
        world
            .query::<&jackdaw_feathers::toast::EditorToast>()
            .iter(world)
            .count()
    }

    /// The R8 bug: extending off a concave brush ran the rebuild and
    /// silently recast the shape. The fix refuses instead — geometry,
    /// history and everything else exactly as they were, plus a toast.
    #[test]
    fn extend_refuses_a_concave_primary_and_touches_nothing() {
        let l = concave_l_brush();
        let face = reentrant_plus_y_face(&l);
        let (mut world, primary, target) = extend_world(
            l,
            GlobalTransform::IDENTITY,
            Brush::cuboid(0.5, 0.5, 0.5),
            rotated_wall_gt(Vec3::new(3.0, 0.0, 0.0)),
        );
        let (before_faces, before_verts) = shape_signature(world.get::<Brush>(primary).unwrap());
        let before_undo = world.resource::<CommandHistory>().undo_stack.len();

        extend_face_to_brush_impl(&mut world, primary, &[target], face);

        let (after_faces, after_verts) = shape_signature(world.get::<Brush>(primary).unwrap());
        assert_eq!(
            after_faces, before_faces,
            "a refused extend must leave every face untouched"
        );
        assert_eq!(
            after_verts, before_verts,
            "a refused extend must leave every vertex untouched"
        );
        assert_eq!(
            world.resource::<CommandHistory>().undo_stack.len(),
            before_undo,
            "a refused extend must not push an undo entry"
        );
        assert_eq!(
            toast_count(&mut world),
            1,
            "the refusal is reported on the brush toast channel"
        );
    }

    /// The verdict must not care how the brush sits in the world: convexity
    /// is rigid-transform invariant and the check runs in the brush's local
    /// space, so a rotated concave brush is refused the same way.
    #[test]
    fn extend_refuses_a_rotated_concave_primary() {
        let l = concave_l_brush();
        let face = reentrant_plus_y_face(&l);
        let (mut world, primary, target) = extend_world(
            l,
            // 90° about Z: local +Y points along world -X.
            GlobalTransform::from_rotation(Quat::from_rotation_z(std::f32::consts::FRAC_PI_2)),
            Brush::cuboid(0.5, 0.5, 0.5),
            rotated_wall_gt(Vec3::new(3.0, 0.0, 0.0)),
        );
        let (before_faces, before_verts) = shape_signature(world.get::<Brush>(primary).unwrap());

        extend_face_to_brush_impl(&mut world, primary, &[target], face);

        let (after_faces, after_verts) = shape_signature(world.get::<Brush>(primary).unwrap());
        assert_eq!(
            after_faces, before_faces,
            "a rotated concave primary must be left untouched"
        );
        assert_eq!(
            after_verts, before_verts,
            "a rotated concave primary must keep its vertices"
        );
        assert_eq!(
            world.resource::<CommandHistory>().undo_stack.len(),
            0,
            "a refused extend must not push an undo entry"
        );
    }

    /// The D3 anchor: a convex primary extends exactly as before — the
    /// rebuild runs, pushes its one SetBrush entry, and reports no refusal.
    #[test]
    fn extend_still_rebuilds_a_convex_primary() {
        let (mut world, primary, target) = extend_world(
            Brush::cuboid(0.5, 0.5, 0.5),
            GlobalTransform::IDENTITY,
            Brush::cuboid(0.5, 0.5, 0.5),
            rotated_wall_gt(Vec3::new(3.0, 0.0, 0.0)),
        );
        let (before_faces, before_verts) = shape_signature(world.get::<Brush>(primary).unwrap());

        // Face 0 of `Brush::cuboid` is the +X face — the wall the extend
        // opens toward the target at +X (the pick the extend undo guard
        // drives through the full editor).
        extend_face_to_brush_impl(&mut world, primary, &[target], 0);

        assert_eq!(
            world.resource::<CommandHistory>().undo_stack.len(),
            1,
            "the convex extend still pushes exactly its own SetBrush entry"
        );
        let (after_faces, after_verts) = shape_signature(world.get::<Brush>(primary).unwrap());
        assert_ne!(
            (after_faces, after_verts),
            (before_faces, before_verts),
            "the convex extend still rebuilds the brush"
        );
        assert_eq!(
            toast_count(&mut world),
            0,
            "a successful extend reports no refusal"
        );
    }

    #[test]
    fn convexity_helper_tells_the_l_from_the_cuboid() {
        assert!(
            !brush_is_convex(&concave_l_brush()),
            "the corner-bitten L is concave: its hull corners poke past the bite walls"
        );
        assert!(
            brush_is_convex(&Brush::cuboid(1.0, 1.0, 1.0)),
            "the cuboid is convex: every vertex sits on every face plane"
        );
    }

    /// Below the epsilon a drifted vertex is float residue, not concavity;
    /// past it, a real poke-out.
    #[test]
    fn convexity_eps_ignores_subepsilon_poke_out() {
        let drifted = |past: f32| {
            let mut brush = Brush::cuboid(1.0, 1.0, 1.0);
            let xi = brush
                .topology
                .vertices
                .iter()
                .enumerate()
                .max_by(|(_, a), (_, b)| a.position.x.total_cmp(&b.position.x))
                .map(|(i, _)| i)
                .expect("the cuboid has vertices");
            brush.topology.vertices[xi].position.x += past;
            brush
        };
        assert!(
            brush_is_convex(&drifted(0.5 * jackdaw_geometry::EPSILON)),
            "a sub-epsilon poke-out stays inside the tolerance"
        );
        assert!(
            !brush_is_convex(&drifted(10.0 * jackdaw_geometry::EPSILON)),
            "a poke-out past the epsilon reads as concave"
        );
    }
}
