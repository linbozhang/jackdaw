use bevy::prelude::*;

pub struct JackdawCameraPlugin;

impl Plugin for JackdawCameraPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<CameraNavInput>()
            .add_systems(Update, camera_system);
    }
}

/// Per-frame navigation input, populated by the host application.
///
/// The camera controller reads only this resource, so the editor can drive it
/// from rebindable input actions while other hosts feed it directly.
///
/// The editor populates this in `PreUpdate` (after `jackdaw_input::ActionSystems`)
/// via `populate_camera_nav_input` in `src/input_contexts.rs`. The camera
/// system runs in `Update`, so it always sees the freshly written frame value.
#[derive(Resource, Default, Clone)]
pub struct CameraNavInput {
    /// Fly mode engaged (the editor binds this to RMB hold via a code-level
    /// `Down` condition; see `src/input_contexts.rs`).
    pub fly_active: bool,
    /// Pointer delta this frame while navigating.
    pub look_delta: Vec2,
    /// Pan mode engaged (the editor binds this to MMB hold via a code-level
    /// `Down` condition; see `src/input_contexts.rs`).
    pub pan_active: bool,
    /// Pointer delta this frame while panning, in screen pixels with y
    /// growing downward.
    pub pan_delta: Vec2,
    /// Wheel movement this frame (positive = zoom in / forward).
    pub zoom_ticks: f32,
    /// Normalized movement intent in camera-local axes while flying
    /// (x = right, y = up, z = forward). The host resolves WASD/QE from raw
    /// keyboard because those keys are not actions.
    pub move_axes: Vec3,
}

/// Settings component placed on the camera entity to enable fly-camera controls.
///
/// Controls:
/// - Right-click + drag: look around (yaw/pitch)
/// - Middle-click + drag: pan across the view plane (scene follows cursor)
/// - Right-click + WASD: move forward/back/left/right (view-relative)
/// - Right-click + Q / E: move up / down (world-space Y)
/// - Scroll wheel: move forward/back along view direction
/// - Right-click + scroll: adjust camera speed
/// - Shift (held): run speed multiplier while flying
#[derive(Component)]
pub struct JackdawCameraSettings {
    /// Mouse look sensitivity (radians per pixel).
    pub sensitivity: f32,
    /// Base movement speed (units per second).
    pub speed: f32,
    /// Speed multiplier when Shift is held.
    pub run_multiplier: f32,
    /// Whether camera controls are enabled. Set to false during UI focus, etc.
    pub enabled: bool,
    /// Scroll movement speed (units per scroll line).
    pub scroll_speed: f32,
    /// Pitch the view down when the pointer moves away, rather than up.
    pub invert_y: bool,
}

impl Default for JackdawCameraSettings {
    fn default() -> Self {
        Self {
            sensitivity: 0.003,
            speed: 10.0,
            run_multiplier: 2.0,
            enabled: true,
            scroll_speed: 1.0,
            invert_y: false,
        }
    }
}

/// World units of pan per dragged pixel, per unit of [`JackdawCameraSettings::speed`].
///
/// A deliberate drag covers a few hundred pixels per second, so at the
/// default speed of 10 this pans roughly as fast as flying forward.
const PAN_UNITS_PER_SPEED_PER_PIXEL: f32 = 0.002;

fn camera_system(
    // Shift raw read is intentionally kept: it is a speed modifier that
    // compounds with `move_axes` but is not a navigation trigger, so it
    // does not need to be preset-bindable this pass.
    keyboard: Res<ButtonInput<KeyCode>>,
    nav: Res<CameraNavInput>,
    time: Res<Time>,
    mut camera_query: Query<(
        &mut JackdawCameraSettings,
        &mut Transform,
        Option<&mut Projection>,
    )>,
) {
    let shift = keyboard.any_pressed([KeyCode::ShiftLeft, KeyCode::ShiftRight]);
    let dt = time.delta_secs();

    for (mut settings, mut transform, projection) in &mut camera_query {
        if !settings.enabled {
            continue;
        }

        let ortho_scale = projection
            .as_ref()
            .and_then(|p| match p.as_ref() {
                Projection::Orthographic(ortho) => Some(ortho.scale),
                _ => None,
            })
            .unwrap_or(1.0);
        let is_ortho = projection
            .as_ref()
            .is_some_and(|p| matches!(p.as_ref(), Projection::Orthographic(_)));

        // Mouse look (only while fly mode is active; disabled in ortho
        // so axis-locked views stay aligned).
        if nav.fly_active && !is_ortho && nav.look_delta != Vec2::ZERO {
            let (mut yaw, mut pitch, _) = transform.rotation.to_euler(EulerRot::YXZ);
            yaw -= nav.look_delta.x * settings.sensitivity;
            pitch -= pitch_direction(settings.invert_y) * nav.look_delta.y * settings.sensitivity;
            pitch = pitch.clamp(
                -std::f32::consts::FRAC_PI_2 + 0.01,
                std::f32::consts::FRAC_PI_2 - 0.01,
            );
            transform.rotation = Quat::from_euler(EulerRot::YXZ, yaw, pitch, 0.0);
        }

        // Middle-drag pan: the scene follows the cursor across the view
        // plane (Unity Scene view). Pointer x grows rightward and y grows
        // downward, so the camera moves against the drag along `right` and
        // with it along `up`. Unlike look, pan works in ortho too — an
        // axis-locked view still pans — with the drag scaled by the ortho
        // scale so the same pixel travel moves the same share of the view
        // at any zoom (the same reasoning as the ortho zoom below).
        if nav.pan_active && nav.pan_delta != Vec2::ZERO {
            let pan = -transform.right().as_vec3() * nav.pan_delta.x
                + transform.up().as_vec3() * nav.pan_delta.y;
            transform.translation +=
                pan * settings.speed * PAN_UNITS_PER_SPEED_PER_PIXEL * ortho_scale;
        }

        // Scroll zoom. Ctrl+Alt (grid size shortcut) and Shift (brush/grid
        // resize) skip zoom so those chords are not stolen.
        let ctrl = keyboard.any_pressed([KeyCode::ControlLeft, KeyCode::ControlRight]);
        let alt = keyboard.any_pressed([KeyCode::AltLeft, KeyCode::AltRight]);
        if (!ctrl || !alt) && !shift && nav.zoom_ticks != 0.0 {
            let mut projection = projection;
            if nav.fly_active {
                // Right-click + scroll: adjust speed.
                settings.speed = (settings.speed * (1.0 + nav.zoom_ticks * 0.1)).clamp(0.5, 100.0);
            } else if let Some(proj) = projection.as_deref_mut()
                && let Projection::Orthographic(ortho) = proj
            {
                // Ortho zoom: smaller scale = closer view.
                ortho.scale = (ortho.scale * (1.0 - nav.zoom_ticks * 0.1)).clamp(0.05, 1000.0);
            } else {
                // Perspective: dolly along view direction.
                let forward = transform.forward().as_vec3();
                transform.translation += forward * nav.zoom_ticks * settings.scroll_speed;
            }
        }

        // Fly movement. `move_axes` is in camera-local space (x=right, y=up,
        // z=forward); the host resolves WASD/QE from raw keyboard this pass.
        if nav.move_axes != Vec3::ZERO {
            let movement = nav.move_axes.x * transform.right().as_vec3()
                + nav.move_axes.y * Vec3::Y
                + nav.move_axes.z * transform.forward().as_vec3();
            if movement != Vec3::ZERO {
                let speed_mult = if shift { settings.run_multiplier } else { 1.0 };
                transform.translation += movement.normalize() * settings.speed * speed_mult * dt;
            }
        }
    }
}

/// The sign a look delta's vertical component is applied with. Pointer
/// coordinates grow downward, so the uninverted camera pitches up when
/// the pointer moves away.
fn pitch_direction(invert_y: bool) -> f32 {
    if invert_y { -1.0 } else { 1.0 }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The pitch a look drag of `delta` leaves, from level.
    fn pitch_after_look(invert_y: bool, delta: Vec2) -> f32 {
        let mut app = App::new();
        app.add_plugins((MinimalPlugins, JackdawCameraPlugin))
            .init_resource::<ButtonInput<KeyCode>>();
        app.insert_resource(CameraNavInput {
            fly_active: true,
            look_delta: delta,
            ..Default::default()
        });
        let camera = app
            .world_mut()
            .spawn((
                JackdawCameraSettings {
                    invert_y,
                    ..Default::default()
                },
                Transform::IDENTITY,
            ))
            .id();
        app.update();
        let (_, pitch, _) = app
            .world()
            .get::<Transform>(camera)
            .expect("the camera kept its transform")
            .rotation
            .to_euler(EulerRot::YXZ);
        pitch
    }

    /// Where a middle-drag pan of `delta` leaves the camera, from identity,
    /// with the given speed and optional projection.
    fn position_after_pan(delta: Vec2, speed: f32, projection: Option<Projection>) -> Vec3 {
        let mut app = App::new();
        app.add_plugins((MinimalPlugins, JackdawCameraPlugin))
            .init_resource::<ButtonInput<KeyCode>>();
        app.insert_resource(CameraNavInput {
            pan_active: true,
            pan_delta: delta,
            ..Default::default()
        });
        let settings = JackdawCameraSettings {
            speed,
            ..Default::default()
        };
        let camera = match projection {
            Some(projection) => app
                .world_mut()
                .spawn((settings, Transform::IDENTITY, projection))
                .id(),
            None => app.world_mut().spawn((settings, Transform::IDENTITY)).id(),
        };
        app.update();
        app.world()
            .get::<Transform>(camera)
            .expect("the camera kept its transform")
            .translation
    }

    /// Pointer coordinates grow rightward and downward, and the scene
    /// follows the cursor: a rightward drag moves the camera left along
    /// `right`, a downward drag moves it up along `up`.
    #[test]
    fn pan_drag_moves_the_camera_against_the_drag() {
        let right = position_after_pan(Vec2::new(100.0, 0.0), 10.0, None);
        assert!(right.x < 0.0, "camera moved left: {right:?}");
        assert_eq!(right.y, 0.0);
        assert_eq!(right.z, 0.0, "pan stays in the view plane");

        let down = position_after_pan(Vec2::new(0.0, 100.0), 10.0, None);
        assert!(down.y > 0.0, "camera moved up: {down:?}");
        assert_eq!(down.x, 0.0);
        assert_eq!(down.z, 0.0);
    }

    /// Pan length scales with the speed setting, like every other motion.
    #[test]
    fn pan_scales_with_speed() {
        let slow = position_after_pan(Vec2::new(100.0, 0.0), 5.0, None);
        let fast = position_after_pan(Vec2::new(100.0, 0.0), 10.0, None);
        assert!((fast.x - 2.0 * slow.x).abs() < 1e-6, "{slow:?} vs {fast:?}");
    }

    /// An ortho view covers more world per pixel the larger its scale, so
    /// the pan is scaled with it: the same drag moves the same share of
    /// the view at any zoom (mirroring the ortho zoom handling).
    #[test]
    fn ortho_pan_scales_with_ortho_scale() {
        let mut base = OrthographicProjection::default_3d();
        base.scale = 1.0;
        let mut zoomed = OrthographicProjection::default_3d();
        zoomed.scale = 4.0;

        let at_one = position_after_pan(
            Vec2::new(100.0, 0.0),
            10.0,
            Some(Projection::Orthographic(base)),
        );
        let at_four = position_after_pan(
            Vec2::new(100.0, 0.0),
            10.0,
            Some(Projection::Orthographic(zoomed)),
        );
        assert!(
            (at_four.x - 4.0 * at_one.x).abs() < 1e-5,
            "{at_one:?} vs {at_four:?}"
        );
    }

    /// Pointer coordinates grow downward, so a drag away from the user
    /// pitches the view up unless the setting says otherwise.
    #[test]
    fn inverting_y_reverses_the_pitch_a_look_drag_produces() {
        let away = Vec2::new(0.0, -20.0);
        let upright = pitch_after_look(false, away);
        let inverted = pitch_after_look(true, away);
        assert!(upright > 0.0, "the view pitched up: {upright}");
        assert!(inverted < 0.0, "the view pitched down: {inverted}");
        assert!((upright + inverted).abs() < 1e-6, "by the same amount");
    }

    #[test]
    fn camera_nav_input_default_is_inactive() {
        let nav = CameraNavInput::default();
        assert!(!nav.fly_active);
        assert_eq!(nav.look_delta, Vec2::ZERO);
        assert!(!nav.pan_active);
        assert_eq!(nav.pan_delta, Vec2::ZERO);
        assert_eq!(nav.zoom_ticks, 0.0);
        assert_eq!(nav.move_axes, Vec3::ZERO);
    }
}
