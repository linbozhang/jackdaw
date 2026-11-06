use bevy::{
    input::mouse::MouseMotion,
    picking::mesh_picking::ray_cast::{MeshRayCast, MeshRayCastSettings, RayCastVisibility},
    prelude::*,
    ui::UiGlobalTransform,
    window::{CursorGrabMode, CursorOptions},
};

use crate::{
    active_tool::ActiveTool,
    commands::SetTransform,
    gizmos::{GizmoAxis, GizmoDragState, GizmoHoverState},
    selection::Selection,
    snapping::SnapSettings,
    viewport::{MainViewportCamera, SceneViewport},
};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ModalOp {
    Grab,
    Rotate,
    Scale,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum ModalConstraint {
    #[default]
    Free,
    Axis(GizmoAxis),
    /// Constrains to a plane by excluding this axis.
    Plane(GizmoAxis),
}

#[derive(Resource, Debug, Default)]
pub struct ModalTransformState {
    pub active: Option<ActiveModal>,
}

#[derive(Debug)]
pub struct ActiveModal {
    pub op: ModalOp,
    pub entity: Entity,
    pub start_transform: Transform,
    pub constraint: ModalConstraint,
    pub start_cursor: Vec2,
}

#[derive(Resource, Default)]
pub struct ViewportDragState {
    pub pending: Option<PendingDrag>,
    pub active: Option<ActiveDrag>,
}

pub struct PendingDrag {
    pub entity: Entity,
    pub start_transform: Transform,
    pub click_pos: Vec2,
    /// Viewport-local cursor position at drag start.
    pub start_viewport_cursor: Vec2,
    /// Camera entity of the viewport this drag was started in.
    pub camera: Entity,
    /// `SceneViewport` UI-node entity of the same viewport.
    pub viewport: Entity,
}

pub struct ActiveDrag {
    pub entity: Entity,
    pub start_transform: Transform,
    /// Viewport-local cursor position at drag start.
    pub start_viewport_cursor: Vec2,
    /// Camera entity of the viewport this drag was started in.
    pub camera: Entity,
    /// `SceneViewport` UI-node entity of the same viewport.
    pub viewport: Entity,
}

pub struct ModalTransformPlugin;

impl Plugin for ModalTransformPlugin {
    fn build(&self, app: &mut App) {
        // ModalTransformState is kept so other systems can check `modal.active.is_some()`.
        // Modal activate/constrain/update/confirm/cancel/draw systems are disabled
        // (G/R/S bind to TrenchBroom-style keybinds rather than modal transforms.)
        // The code is preserved in this file for a future alternate keymap option.
        app.init_resource::<ModalTransformState>()
            .init_resource::<ViewportDragState>()
            .add_systems(
                Update,
                (
                    snap_toggle,
                    viewport_drag_detect.after(crate::viewport_select::handle_viewport_click),
                    viewport_drag_update,
                    viewport_drag_finish,
                )
                    .chain()
                    .in_set(crate::EditorInteractionSystems),
            );
    }
}

/// Pointer travel (px) below which a middle press-and-release still counts
/// as a click that toggles snapping. Beyond it the gesture was a middle
/// drag — the viewport pan (Unity Scene view alignment) — and the release
/// that ends the pan must not also flip the snap setting.
const SNAP_CLICK_MAX_TRAVEL: f32 = 4.0;

fn snap_toggle(
    mouse: Res<ButtonInput<MouseButton>>,
    mode: Res<ActiveTool>,
    modal: Res<ModalTransformState>,
    mut snap_settings: ResMut<SnapSettings>,
    mut motion: MessageReader<MouseMotion>,
    mut travel: Local<f32>,
    mut commands: Commands,
) {
    // Reset the click tracker on the press itself, before any early return:
    // a modal (or leaving one) must not score the next click against a
    // previous press's travel. The clear also drops motion that piled up
    // unread while no button was held — it belongs to no click, and reading
    // it on the press frame would inflate the travel and swallow the click.
    if mouse.just_pressed(MouseButton::Middle) {
        motion.clear();
        *travel = 0.0;
    }

    if modal.active.is_some() {
        return;
    }

    if mouse.pressed(MouseButton::Middle) {
        *travel += motion.read().map(|ev| ev.delta.length()).sum::<f32>();
    }
    if mouse.just_released(MouseButton::Middle) && *travel <= SNAP_CLICK_MAX_TRAVEL {
        let toggled = match *mode {
            ActiveTool::Select | ActiveTool::Tilemap => false,
            ActiveTool::Translate => {
                snap_settings.translate_snap = !snap_settings.translate_snap;
                true
            }
            ActiveTool::Rotate => {
                snap_settings.rotate_snap = !snap_settings.rotate_snap;
                true
            }
            ActiveTool::Scale => {
                snap_settings.scale_snap = !snap_settings.scale_snap;
                true
            }
        };
        // Middle-mouse toggles snap outside the operator path, so the
        // toolbar's GridToggleSnap highlight observer won't see the change
        // unless we announce it.
        if toggled {
            commands.trigger(jackdaw_api::op::RefreshOperatorButtons);
        }
    }
}

fn viewport_drag_detect(
    mouse: Res<ButtonInput<MouseButton>>,
    keyboard: Res<ButtonInput<KeyCode>>,
    cursor: crate::viewport::UiCursorPos,
    camera_query: Query<(&Camera, &GlobalTransform), With<MainViewportCamera>>,
    viewport_query: Query<(&ComputedNode, &UiGlobalTransform), With<SceneViewport>>,
    active_viewport: Res<crate::viewport::ActiveViewport>,
    selection: Res<Selection>,
    transforms: Query<(&GlobalTransform, &Transform)>,
    gizmo_drag: Res<GizmoDragState>,
    modal: Res<ModalTransformState>,
    gizmo_hover: Res<GizmoHoverState>,
    mirror_plane_hover: Res<crate::brush::mirror_plane_overlay::MirrorPlaneHover>,
    mut drag_state: ResMut<ViewportDragState>,
    (edit_mode, draw_state, terrain_edit_mode, active_modal): (
        Res<crate::brush::EditMode>,
        Res<crate::draw_brush::DrawBrushState>,
        Res<crate::terrain_mode::TerrainEditMode>,
        jackdaw_api::prelude::ActiveModalQuery,
    ),
    (mut ray_cast, parents, brushes, editor_entities): (
        MeshRayCast,
        Query<&ChildOf>,
        Query<(), With<jackdaw_scene_types::Brush>>,
        Query<(), With<crate::EditorEntity>>,
    ),
) {
    // A hovered mirror-plane handle wins the press, so the viewport object drag
    // must not also start and move the whole brush.
    if modal.active.is_some()
        || active_modal.is_modal_running()
        || gizmo_drag.active
        || gizmo_hover.hovered_axis.is_some()
        || mirror_plane_hover.target.is_some()
    {
        return;
    }

    // Skip detect if there's already an active drag
    if drag_state.active.is_some() {
        return;
    }

    // Block viewport drag during brush edit mode or draw mode
    if *edit_mode != crate::brush::EditMode::Object || draw_state.active.is_some() {
        return;
    }

    // Block viewport drag during terrain sculpt or paint mode
    if terrain_edit_mode.brush_active() {
        return;
    }

    // Shift+click on a brush is always face interaction, not viewport drag
    // (follows TrenchBroom pattern: modifier keys define non-overlapping input contexts)
    let shift = keyboard.any_pressed([KeyCode::ShiftLeft, KeyCode::ShiftRight]);
    if shift
        && let Some(primary) = selection.primary()
        && brushes.contains(primary)
    {
        return;
    }

    if !mouse.just_pressed(MouseButton::Left) {
        return;
    }

    let Some(primary) = selection.primary() else {
        return;
    };
    let Ok((_, local_tf)) = transforms.get(primary) else {
        return;
    };

    let Some(cursor_pos) = cursor.get() else {
        return;
    };
    // Drag-start is hover-routed: the click happens in whichever
    // viewport the cursor is currently over.
    let Some(camera_entity) = active_viewport.camera else {
        return;
    };
    let Some(viewport_entity) = active_viewport.ui_node else {
        return;
    };
    let Ok((camera, cam_tf)) = camera_query.get(camera_entity) else {
        return;
    };

    let Some(viewport_cursor) = crate::viewport_util::window_to_viewport_cursor_for(
        cursor_pos,
        camera,
        viewport_entity,
        &viewport_query,
    ) else {
        return;
    };

    // Raycast to check if click hits the primary selection's mesh
    let Ok(ray) = camera.viewport_to_world(cam_tf, viewport_cursor) else {
        return;
    };
    // Filter out editor-internal mesh entities (material preview spheres,
    // gizmo meshes, draw previews) so they don't occlude clicks against
    // the actual scene geometry. Same fix as in `viewport_select::handle_viewport_click`.
    let editor_filter = |entity: Entity| !editor_entities.contains(entity);
    let settings = MeshRayCastSettings::default()
        .with_visibility(RayCastVisibility::Any)
        .with_filter(&editor_filter);
    let hits = ray_cast.cast_ray(ray, &settings);

    let mut hit_primary = false;
    for (hit_entity, _) in hits {
        let mut entity = *hit_entity;
        loop {
            if entity == primary {
                hit_primary = true;
                break;
            }
            if let Ok(child_of) = parents.get(entity) {
                entity = child_of.0;
            } else {
                break;
            }
        }
        if hit_primary {
            break;
        }
    }

    if hit_primary {
        drag_state.pending = Some(PendingDrag {
            entity: primary,
            start_transform: *local_tf,
            click_pos: cursor_pos,
            start_viewport_cursor: viewport_cursor,
            camera: camera_entity,
            viewport: viewport_entity,
        });
    }
}

fn viewport_drag_update(
    mouse: Res<ButtonInput<MouseButton>>,
    cursor: crate::viewport::UiCursorPos,
    camera_query: Query<(&Camera, &GlobalTransform), With<MainViewportCamera>>,
    viewport_query: Query<(&ComputedNode, &UiGlobalTransform), With<SceneViewport>>,
    keyboard: Res<ButtonInput<KeyCode>>,
    snap_settings: Res<SnapSettings>,
    numeric: Res<crate::numeric_transform::NumericTransformState>,
    mut drag_state: ResMut<ViewportDragState>,
    mut transforms: Query<&mut Transform>,
    mut cursor_query: Query<&mut CursorOptions, With<Window>>,
    edit_mode: Res<crate::brush::EditMode>,
    terrain_edit_mode: Res<crate::terrain_mode::TerrainEditMode>,
) {
    if !mouse.pressed(MouseButton::Left) {
        drag_state.pending = None;
        return;
    }

    // Cancel pending drag if terrain sculpt or paint mode became active
    if terrain_edit_mode.brush_active() {
        drag_state.pending = None;
        return;
    }

    let Some(cursor_pos) = cursor.get() else {
        return;
    };

    // Check pending -> active promotion
    if let Some(ref pending) = drag_state.pending {
        // Cancel pending drag if we're no longer in Object mode
        // (e.g. brush_face_interact entered Face mode on the same click)
        if *edit_mode != crate::brush::EditMode::Object {
            drag_state.pending = None;
            return;
        }
        let dist = (cursor_pos - pending.click_pos).length();
        if dist > 5.0 {
            let active = ActiveDrag {
                entity: pending.entity,
                start_transform: pending.start_transform,
                start_viewport_cursor: pending.start_viewport_cursor,
                camera: pending.camera,
                viewport: pending.viewport,
            };
            drag_state.active = Some(active);
            drag_state.pending = None;
            // Confine cursor during viewport drag
            if let Ok(mut cursor_opts) = cursor_query.single_mut() {
                cursor_opts.grab_mode = CursorGrabMode::Confined;
            }
        } else {
            return;
        }
    }

    // Update active drag
    let Some(ref active) = drag_state.active else {
        return;
    };
    // Use the captured viewport so the drag stays attached to its
    // origin viewport across frames, not whichever one the cursor
    // happens to be over now (multi-viewport).
    let Ok((camera, cam_tf)) = camera_query.get(active.camera) else {
        return;
    };
    let ctrl = keyboard.any_pressed([KeyCode::ControlLeft, KeyCode::ControlRight]);
    let alt = keyboard.any_pressed([KeyCode::AltLeft, KeyCode::AltRight]);
    let shift = keyboard.any_pressed([KeyCode::ShiftLeft, KeyCode::ShiftRight]);

    let Some(viewport_cursor) = crate::viewport_util::window_to_viewport_cursor_for(
        cursor_pos,
        camera,
        active.viewport,
        &viewport_query,
    ) else {
        return;
    };

    let start_pos = active.start_transform.translation;

    let offset = if let Some(axis) = numeric.axis {
        // Armed numeric axis: constrain the drag to that world axis the same
        // way the gizmo handle does, so body and handle feel identical.
        let axis_dir = crate::numeric_transform::axis_direction(axis);
        let amount = crate::viewport_util::drag_along_axis(
            camera,
            cam_tf,
            active.start_viewport_cursor,
            viewport_cursor,
            start_pos,
            axis_dir,
        )
        .unwrap_or(0.0);
        axis_dir * amount
    } else if alt {
        crate::viewport_util::drag_along_axis(
            camera,
            cam_tf,
            active.start_viewport_cursor,
            viewport_cursor,
            start_pos,
            Vec3::Y,
        )
        .map(|amount| Vec3::Y * amount)
        .unwrap_or(Vec3::ZERO)
    } else {
        // Move on the ground plane through the grab point. If the ray is
        // parallel to the ground (looking horizontally), fall back to a
        // camera-facing plane flattened onto XZ.
        let raw = crate::viewport_util::drag_on_plane(
            camera,
            cam_tf,
            active.start_viewport_cursor,
            viewport_cursor,
            start_pos,
            Vec3::Y,
        )
        .or_else(|| {
            crate::viewport_util::drag_on_plane(
                camera,
                cam_tf,
                active.start_viewport_cursor,
                viewport_cursor,
                start_pos,
                cam_tf.forward().as_vec3(),
            )
            .map(|d| Vec3::new(d.x, 0.0, d.z))
        })
        .unwrap_or(Vec3::ZERO);

        if shift {
            // Shift+drag: restrict to dominant axis
            if raw.x.abs() > raw.z.abs() {
                Vec3::new(raw.x, 0.0, 0.0)
            } else {
                Vec3::new(0.0, 0.0, raw.z)
            }
        } else {
            raw
        }
    };

    let snapped_offset = snap_settings.snap_translate_vec3_if(offset, ctrl);

    if let Ok(mut transform) = transforms.get_mut(active.entity) {
        transform.translation = start_pos + snapped_offset;
    }
}

fn viewport_drag_finish(
    mouse: Res<ButtonInput<MouseButton>>,
    cursor: crate::viewport::UiCursorPos,
    mut drag_state: ResMut<ViewportDragState>,
    transforms: Query<&Transform>,
    mut cursor_query: Query<&mut CursorOptions, With<Window>>,
    mut numeric: ResMut<crate::numeric_transform::NumericTransformState>,
    mut commands: Commands,
) {
    if !mouse.just_released(MouseButton::Left) && cursor.get().is_some() {
        return;
    }

    drag_state.pending = None;

    let Some(active) = drag_state.active.take() else {
        return;
    };

    // The drag consumed the armed axis; disarm so the next operation starts
    // free unless the user re-arms with X / Y / Z.
    numeric.clear();

    if let Ok(transform) = transforms.get(active.entity) {
        // Modal mutated ECS directly during the drag; the synced push
        // runs the AST-sync hook so reloads see the new Transform.
        jackdaw_commands::push_executed_synced(
            Box::new(SetTransform {
                entity: active.entity,
                old_transform: active.start_transform,
                new_transform: *transform,
            }),
            &mut commands,
        );
    }

    // Release cursor confinement
    if let Ok(mut cursor_opts) = cursor_query.single_mut() {
        cursor_opts.grab_mode = CursorGrabMode::None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::active_tool::ActiveTool;
    use crate::snapping::SnapSettings;
    use bevy::input::mouse::MouseMotion;

    /// Minimal app running `snap_toggle` each Update, with the inputs the
    /// system reads driven directly: `ButtonInput` for the button edges,
    /// `Messages<MouseMotion>` for the drag travel.
    fn make_snap_app() -> App {
        let mut app = App::new();
        app.init_resource::<ButtonInput<MouseButton>>()
            .init_resource::<ModalTransformState>()
            .init_resource::<SnapSettings>()
            .insert_resource(ActiveTool::Translate)
            .add_message::<MouseMotion>()
            .add_systems(Update, snap_toggle);
        app
    }

    fn translate_snap(app: &App) -> bool {
        app.world().resource::<SnapSettings>().translate_snap
    }

    fn press_middle(app: &mut App) {
        app.world_mut()
            .resource_mut::<ButtonInput<MouseButton>>()
            .press(MouseButton::Middle);
    }

    fn release_middle(app: &mut App) {
        app.world_mut()
            .resource_mut::<ButtonInput<MouseButton>>()
            .release(MouseButton::Middle);
    }

    fn travel(app: &mut App, delta: Vec2) {
        app.world_mut().write_message(MouseMotion { delta });
    }

    /// One frame: run the schedule, then stand in for `InputSystems` by
    /// ending the just-press/just-release edges (the bare test app has no
    /// input plugin doing it). The held state survives the edge reset.
    fn frame(app: &mut App) {
        app.update();
        app.world_mut()
            .resource_mut::<ButtonInput<MouseButton>>()
            .clear();
    }

    /// Motion that piled up unread while no button was held belongs to no
    /// click: the press frame clears the backlog, so a still click right
    /// after a moving cursor still toggles.
    #[test]
    fn stale_motion_backlog_does_not_swallow_a_middle_click() {
        let mut app = make_snap_app();
        let initial = translate_snap(&app);

        // Motion with no button held: nobody reads it this frame.
        travel(&mut app, Vec2::new(80.0, 0.0));
        frame(&mut app);

        // Press on the next frame: the backlog is dropped, not scored.
        press_middle(&mut app);
        frame(&mut app);

        release_middle(&mut app);
        frame(&mut app);
        assert_ne!(
            translate_snap(&app),
            initial,
            "the click toggled despite the stale backlog"
        );
    }

    /// A middle drag past the click travel is a viewport pan; the release
    /// that ends it must not toggle the snap setting.
    #[test]
    fn a_middle_drag_beyond_the_click_travel_does_not_toggle() {
        let mut app = make_snap_app();
        let initial = translate_snap(&app);

        press_middle(&mut app);
        frame(&mut app);
        travel(&mut app, Vec2::new(30.0, 0.0));
        frame(&mut app);
        release_middle(&mut app);
        frame(&mut app);

        assert_eq!(
            translate_snap(&app),
            initial,
            "a drag's release does not toggle"
        );
    }

    /// A plain middle click toggles, and a second plain click toggles back.
    #[test]
    fn a_plain_middle_click_toggles_and_toggles_back() {
        let mut app = make_snap_app();
        let initial = translate_snap(&app);

        press_middle(&mut app);
        frame(&mut app);
        release_middle(&mut app);
        frame(&mut app);
        assert_ne!(translate_snap(&app), initial, "the first click toggles");

        press_middle(&mut app);
        frame(&mut app);
        release_middle(&mut app);
        frame(&mut app);
        assert_eq!(
            translate_snap(&app),
            initial,
            "the second click toggles back"
        );
    }
}
