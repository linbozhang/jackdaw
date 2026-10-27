//! The player controller template pattern over the real engine.
//!
//! Four legs, mirroring `templates/game/src/lib.rs.template`'s player
//! section (the controller itself lives in the scaffolded game, so the
//! systems below are a faithful local port of that code — same numbers,
//! same order of operations; the teaches tests pin the template's shape
//! and the live legs re-run the built game):
//!
//! * **Camera wiring (C1)**: a scene-authored `CameraRig` only
//!   materializes and follows through `JackdawCameraRigPlugin` — the
//!   game-side half the runtime re-exports.
//! * **Collision (C3)**: the same input that walks a plainly-written
//!   transform straight through a wall stops at it, and slides along it
//!   when approached diagonally, with zero penetration.
//! * **Jump (C2)**: a just-pressed Jump launches at `jump_speed`, the
//!   flight matches the discrete parabola, a mid-air press does nothing,
//!   and the landing is stable and re-jumpable.
//! * **Frame-rate independence (C2)**: the same held input covers the
//!   same ground at two very different frame rates.

use avian3d::prelude::*;
use bevy::prelude::*;
use bevy::time::TimeUpdateStrategy;
// The prelude path is the point: a game wires the rig through the
// runtime's re-export, and so does this test.
use jackdaw_runtime::prelude::*;
use std::time::Duration;

// ---- The controller pattern, ported from the template ----------------------

/// The tuning the Components panel would edit.
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct PlayerController {
    move_speed: f32,
    jump_speed: f32,
}

/// The runtime velocity `move_player` integrates.
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct PlayerVelocity(pub Vec3);

/// The game-wide config the gravity number comes from.
#[derive(Resource, Default)]
struct TestConfig {
    gravity: f32,
}

/// The template's `move_player`, physics shape: camera-relative input,
/// gravity, a ground-checked jump, and the move-and-slide sweep.
fn move_player(
    actions: Res<GameActions>,
    config: Res<TestConfig>,
    time: Res<Time>,
    move_and_slide: MoveAndSlide,
    mut players: Query<(
        Entity,
        &PlayerController,
        &Collider,
        &mut PlayerVelocity,
        &mut Transform,
    )>,
    look: Query<&CameraLook>,
) {
    use avian3d::math::{ToF32Precision, ToRealPrecision};
    let dt = time.delta_secs();
    let camera_yaw = look.single().map(|camera| camera.yaw).unwrap_or(0.0);
    let direction = move_direction(actions.value("Move"), camera_yaw);
    for (entity, controller, collider, mut velocity, mut transform) in &mut players {
        velocity.0.x = direction.x * controller.move_speed;
        velocity.0.z = direction.z * controller.move_speed;
        velocity.0.y += config.gravity * dt;
        let filter = SpatialQueryFilter::from_excluded_entities([entity]);
        let grounded = move_and_slide
            .spatial_query
            .cast_shape(
                collider,
                transform.translation.real(),
                transform.rotation,
                Dir3::NEG_Y,
                &ShapeCastConfig::from_max_distance(0.1),
                &filter,
            )
            .is_some_and(|hit| hit.normal1.y > 0.7);
        if grounded && actions.just_pressed("Jump") {
            velocity.0.y = controller.jump_speed;
        }
        let output = move_and_slide.move_and_slide(
            collider,
            transform.translation.real(),
            transform.rotation,
            velocity.0.real(),
            time.delta(),
            &MoveAndSlideConfig::default(),
            &filter,
            |_| MoveAndSlideHitResponse::Accept,
        );
        transform.translation = output.position.f32();
        velocity.0 = output.projected_velocity;
    }
}

/// The template's `move_direction`: the input rotated by the camera's
/// yaw, clamped to unit length.
fn move_direction(move_input: Vec2, camera_yaw: f32) -> Vec3 {
    let forward = Quat::from_rotation_y(camera_yaw) * -Vec3::Z;
    let right = Quat::from_rotation_y(camera_yaw) * Vec3::X;
    let mut direction = right * move_input.x + forward * move_input.y;
    direction.y = 0.0;
    if direction.length_squared() > 1.0 {
        direction = direction.normalize();
    }
    direction
}

// ---- Shared fixtures --------------------------------------------------------

/// The editor app with physics unpaused (the editor pauses the
/// simulation until its physics tool runs) and manual time, plus the
/// actions plugin and the controller, so the chain under test is the
/// real one: keyboard events → `GameActions` → the controller systems.
fn controller_app(dt: Duration) -> App {
    let mut app = crate::util::headless_app();
    app.insert_resource(TestConfig { gravity: -9.81 });
    app.add_plugins(InputActionsPlugin);
    app.add_systems(Update, move_player);
    app.finish();
    // First tick runs Startup and extension auto-enable, the same start
    // `editor_test_app` gives.
    app.update();
    app.insert_resource(TimeUpdateStrategy::ManualDuration(dt));
    app.world_mut().resource_mut::<Time<Physics>>().unpause();
    app
}

fn frames(app: &mut App, count: usize) {
    for _ in 0..count {
        app.update();
    }
}

/// A key event into the engine's own input stream, the way T09's guards
/// drive the actions (a PIE-forwarded event lands here too).
fn key(app: &mut App, code: KeyCode, state: bevy::input::ButtonState) {
    app.world_mut()
        .write_message(bevy::input::keyboard::KeyboardInput {
            key_code: code,
            logical_key: bevy::input::keyboard::Key::Character("k".into()),
            state,
            window: Entity::PLACEHOLDER,
            repeat: false,
            text: None,
        });
}

fn press(app: &mut App, code: KeyCode) {
    key(app, code, bevy::input::ButtonState::Pressed);
}

fn release(app: &mut App, code: KeyCode) {
    key(app, code, bevy::input::ButtonState::Released);
}

/// The template's stage geometry: one big static ground, plus (when
/// `walled`) the north wall the slide runs against. The bodies are
/// explicit `RigidBody::Static`s — what a game's bridge turns its
/// authored `AvianCollider`s into, and what move-and-slide's sweep
/// requires (a bodyless collider never pairs with one).
fn spawn_stage(app: &mut App, walled: bool) {
    app.world_mut().spawn((
        RigidBody::Static,
        Collider::cuboid(20.0, 1.0, 20.0),
        Transform::from_xyz(0.0, -0.5, 0.0),
    ));
    if walled {
        app.world_mut().spawn((
            RigidBody::Static,
            Collider::cuboid(12.0, 1.5, 0.4),
            Transform::from_xyz(0.0, 0.75, -3.0),
        ));
    }
    // Let the static bodies enter the collider tree before anything
    // queries them.
    frames(app, 5);
}

/// The template's player: a kinematic capsule with the controller
/// components, dropped slightly above its resting height.
fn spawn_player(app: &mut App, x: f32, z: f32) -> Entity {
    app.world_mut()
        .spawn((
            PlayerController {
                move_speed: 4.0,
                jump_speed: 4.5,
            },
            PlayerVelocity(Vec3::ZERO),
            RigidBody::Kinematic,
            Collider::capsule(0.35, 1.0),
            Transform::from_xyz(x, 1.0, z),
        ))
        .id()
}

fn player_y(app: &App, player: Entity) -> f32 {
    app.world().get::<Transform>(player).unwrap().translation.y
}

fn player_z(app: &App, player: Entity) -> f32 {
    app.world().get::<Transform>(player).unwrap().translation.z
}

fn player_x(app: &App, player: Entity) -> f32 {
    app.world().get::<Transform>(player).unwrap().translation.x
}

/// The template's `look_into_camera`: the Look action writes the rig's
/// look state, mirroring the crate's own RMB channel signs and clamps.
fn look_into_camera(
    actions: Res<GameActions>,
    mouse: Option<Res<ButtonInput<MouseButton>>>,
    mut rigs: Query<(&CameraRig, &mut CameraLook)>,
) {
    if mouse
        .as_deref()
        .is_some_and(|buttons| buttons.pressed(MouseButton::Right))
    {
        return;
    }
    let look = actions.value("Look");
    if look == Vec2::ZERO {
        return;
    }
    for (rig, mut camera) in &mut rigs {
        camera.yaw -= look.x * rig.sensitivity;
        camera.pitch = match rig.mode {
            CameraMode::ThirdPerson => (camera.pitch + look.y * rig.sensitivity).clamp(0.05, 1.4),
            CameraMode::FirstPerson => (camera.pitch - look.y * rig.sensitivity).clamp(-1.4, 1.4),
        };
    }
}

// ---- Camera wiring (C1) -----------------------------------------------------

/// A scene the way the editor would author it: an anchor entity with a
/// `CameraRig` child — the "place a rig under the player" chain.
const RIG_SCENE: &str = "#Root\n\
bevy_transform::components::transform::Transform\n\
bevy_camera::visibility::Visibility::Visible\n\
bevy_ecs::hierarchy::Children [\n    \
#Anchor\n    \
bevy_transform::components::transform::Transform\n    \
bevy_ecs::hierarchy::Children [\n        \
#Rig\n        \
jackdaw_camera_rig::CameraRig\n        \
bevy_transform::components::transform::Transform\n    \
]\n\
]\n";

/// A game-shaped app: the runtime's scene loader over minimal plugins,
/// with or without the camera rig driver a game adds.
fn game_app(with_rig_driver: bool) -> App {
    let mut app = App::new();
    app.add_plugins((
        bevy::app::TaskPoolPlugin::default(),
        bevy::asset::AssetPlugin::default(),
        bevy::time::TimePlugin,
        bevy::transform::TransformPlugin,
        jackdaw_runtime::JackdawPlugin,
    ));
    if with_rig_driver {
        app.add_plugins(JackdawCameraRigPlugin);
    }
    app
}

/// Load `RIG_SCENE` through the runtime's own spawn loop and return the
/// anchor and rig entities.
fn spawn_rig_scene(app: &mut App) -> (Entity, Entity) {
    let handle = app
        .world_mut()
        .resource_mut::<Assets<jackdaw_runtime::JackdawScene>>()
        .add(jackdaw_runtime::JackdawScene::new(
            RIG_SCENE.to_string(),
            std::path::PathBuf::from("."),
        ));
    app.world_mut()
        .spawn(jackdaw_runtime::JackdawSceneRoot(handle));
    // One tick spawns the scene; the driver's Update systems run from
    // the next tick on.
    app.update();
    app.update();
    let named = |app: &mut App, name: &str| {
        app.world_mut()
            .query_filtered::<Entity, With<Name>>()
            .iter(app.world())
            .find(|&e| app.world().get::<Name>(e).unwrap().as_str() == name)
            .expect("the scene entity spawned")
    };
    (named(app, "Anchor"), named(app, "Rig"))
}

/// A scene-authored rig without the game-side driver is a dead camera:
/// nothing activates it, nothing materializes. With the one-line plugin
/// the rig activates, gains its camera, and follows its parent through
/// the world — the "reuse `CameraRig`" acceptance at the mechanism layer.
#[test]
fn a_scene_rig_follows_only_through_the_runtime_plugin() {
    // Red: no `JackdawCameraRigPlugin`, no camera. The rig entity (and
    // even its component, when reflection knows the type) sits inert —
    // the pre-wiring game played exactly this scene with no follow.
    let mut bare = game_app(false);
    let (_, dormant_rig) = spawn_rig_scene(&mut bare);
    frames(&mut bare, 5);
    assert!(
        !bare
            .world()
            .entity(dormant_rig)
            .contains::<ActiveCameraRig>(),
        "nothing activates a rig the game never wired"
    );
    assert!(
        !bare.world().entity(dormant_rig).contains::<Camera3d>(),
        "no driver, no camera: the follow leg is dead"
    );

    // Green: the same scene, the one plugin line added.
    let mut game = game_app(true);
    let (anchor, rig) = spawn_rig_scene(&mut game);
    frames(&mut game, 5);
    let (before, anchor_before) = {
        let world = game.world();
        assert!(
            world.entity(rig).contains::<CameraRig>(),
            "the authored component resolved (not an unresolved leftover)"
        );
        assert!(world.entity(rig).contains::<ActiveCameraRig>());
        assert!(world.entity(rig).contains::<Camera3d>());
        assert!(world.entity(rig).contains::<CameraLook>());

        // The follow: move the anchor, the rig's world placement moves
        // with it, keeping its offset from the anchor.
        (
            world.get::<GlobalTransform>(rig).unwrap().translation(),
            world.get::<GlobalTransform>(anchor).unwrap().translation(),
        )
    };
    let offset = before - anchor_before;
    game.world_mut()
        .entity_mut(anchor)
        .insert(Transform::from_xyz(3.0, 0.0, 0.0));
    frames(&mut game, 3);
    let after = game
        .world()
        .get::<GlobalTransform>(rig)
        .unwrap()
        .translation();
    let anchor_after = game
        .world()
        .get::<GlobalTransform>(anchor)
        .unwrap()
        .translation();
    assert!(
        (after - anchor_after - offset).length() < 1e-3,
        "the rig kept its offset from the anchor: {after:?} vs {anchor_after:?} + {offset:?}"
    );
    assert!(
        (after.x - before.x - 3.0).abs() < 1e-3,
        "the rig followed the anchor's move: {before:?} -> {after:?}"
    );
}

// ---- Collision (C3) ---------------------------------------------------------

/// The same held input that walks a plainly-written transform straight
/// through the wall stops at it under the sweep, and slides along it
/// when approached diagonally: normal movement gone, tangential kept,
/// no penetration.
#[test]
fn the_sweep_stops_the_player_at_walls_and_slides_along_them() {
    let dt = Duration::from_secs_f64(1.0 / 60.0);
    let mut app = controller_app(dt);
    spawn_stage(&mut app, true);
    let player = spawn_player(&mut app, 0.0, 0.0);
    // Settle onto the ground first.
    frames(&mut app, 10);

    // Red, numerically: the pre-controller shape — a plain transform
    // step each frame — covers the same ground straight through the
    // wall (10 s of held input would put it far past the far side).
    let hold_seconds = 1.5_f32;
    let plain_z = -(4.0 * hold_seconds);
    assert!(
        plain_z < -3.0 - 0.4,
        "a plain step reaches {plain_z}, straight through the wall at z=-3"
    );

    // Green, head on: hold W (forward is -Z) into the wall.
    press(&mut app, KeyCode::KeyW);
    frames(&mut app, 90);
    release(&mut app, KeyCode::KeyW);
    let z = player_z(&app, player);
    // Wall face at z=-2.8; the capsule's surface stops a radius plus
    // skin width short of it.
    assert!(
        (-2.50..=-2.40).contains(&z),
        "the sweep stopped the capsule at the wall, got z={z}"
    );
    assert!(z >= -2.8 + 0.35, "no penetration: z={z}");

    // Green, diagonally: the tangential half survives the contact. A
    // fresh player walks W+D at the wall from the side.
    let slider = spawn_player(&mut app, -3.0, 0.0);
    frames(&mut app, 10);
    let start_x = player_x(&app, slider);
    press(&mut app, KeyCode::KeyW);
    press(&mut app, KeyCode::KeyD);
    frames(&mut app, 90);
    release(&mut app, KeyCode::KeyW);
    release(&mut app, KeyCode::KeyD);
    let slid_x = player_x(&app, slider) - start_x;
    let slid_z = player_z(&app, slider);
    assert!(
        (-2.50..=-2.40).contains(&slid_z),
        "the normal half stopped at the wall, got z={slid_z}"
    );
    // Held input at 45° covers 4.0 m/s * 1.5 s * cos(45°) along the
    // wall once sliding; demand most of it.
    assert!(
        slid_x > 3.0,
        "the tangential half kept moving: {slid_x} m along the wall"
    );
}

// ---- Jump (C2) --------------------------------------------------------------

/// A just-pressed Jump leaves the ground at `jump_speed`, the flight is
/// the discrete parabola of that launch under the config's gravity, a
/// mid-air press adds nothing, and the landing is stable and ready to
/// jump again.
#[test]
fn a_jump_flies_the_parabola_and_lands_ready_again() {
    let dt_secs = 1.0_f32 / 60.0;
    let mut app = controller_app(Duration::from_secs_f64(dt_secs as f64));
    spawn_stage(&mut app, false);
    let player = spawn_player(&mut app, 0.0, 0.0);
    frames(&mut app, 10);
    let ground_y = player_y(&app, player);
    assert!(
        (ground_y - 0.86).abs() < 0.05,
        "the capsule rests on the ground (half height 0.85 + skin), got {ground_y}"
    );

    // Launch.
    press(&mut app, KeyCode::Space);
    frames(&mut app, 1);
    release(&mut app, KeyCode::Space);
    let vy_launch = app.world().get::<PlayerVelocity>(player).unwrap().0.y;
    assert!(
        (vy_launch - 4.5).abs() < 0.2,
        "Jump launched at jump_speed, got {vy_launch}"
    );

    // The flight: sample every frame from launch, so the apex (frame
    // ~27 of the 55-frame flight) is inside the window; at frame 18,
    // mid-air, press Jump again and demand gravity-only evolution.
    let mut apex = ground_y;
    let mut midair_checked = false;
    for i in 1..=90 {
        if i == 18 {
            let before_press = app.world().get::<PlayerVelocity>(player).unwrap().0.y;
            assert!(before_press > 0.0, "still ascending at frame {i}");
            press(&mut app, KeyCode::Space);
            frames(&mut app, 2);
            release(&mut app, KeyCode::Space);
            let after_press = app.world().get::<PlayerVelocity>(player).unwrap().0.y;
            let gravity_only = before_press - 9.81 * dt_secs * 2.0;
            assert!(
                (after_press - gravity_only).abs() < 0.05,
                "a mid-air press changed nothing: {after_press} vs gravity-only {gravity_only}"
            );
            midair_checked = true;
        }
        apex = apex.max(player_y(&app, player));
        frames(&mut app, 1);
    }
    assert!(midair_checked, "the mid-air leg ran");

    // Apex: v^2 / (2g) above the resting height.
    let expected_apex = ground_y + 4.5 * 4.5 / (2.0 * 9.81);
    assert!(
        (apex - expected_apex).abs() < 0.15,
        "the apex matches the parabola: {apex} vs {expected_apex}"
    );

    // Landing: two frames agree, at the resting height.
    frames(&mut app, 40);
    let y1 = player_y(&app, player);
    frames(&mut app, 2);
    let y2 = player_y(&app, player);
    assert!(
        (y1 - y2).abs() < 1e-3 && (y2 - ground_y).abs() < 0.02,
        "landed stable at rest height: {y1} then {y2} (rest {ground_y})"
    );

    // And can jump again.
    press(&mut app, KeyCode::Space);
    frames(&mut app, 5);
    release(&mut app, KeyCode::Space);
    assert!(
        player_y(&app, player) > ground_y + 0.1,
        "the landed player jumps again"
    );
}

/// The Look dimension through the real event stream: a mouse motion of
/// dx pixels turns the rig's `CameraLook.yaw` by −dx × sensitivity (the
/// template bridge), the pitch follows dy, and while the right mouse
/// button is held the bridge yields — the rig's own mouse-look owns
/// those frames, so the two channels never double-write. (This is the
/// T09 Look cell re-pinned to the controller's new semantics: the old
/// template rotated the player transform by −dx × 0.01; the yaw now
/// lives on the camera, at the rig's own sensitivity.)
#[test]
fn look_motion_turns_the_camera_not_the_player() {
    let mut app = controller_app(Duration::from_secs_f64(1.0 / 60.0));
    let parent = app.world_mut().spawn(Transform::default()).id();
    let rig = app
        .world_mut()
        .spawn((
            CameraRig::default(),
            ActiveCameraRig,
            CameraLook::default(),
            ChildOf(parent),
        ))
        .id();
    app.add_systems(Update, look_into_camera);
    frames(&mut app, 3);

    let yaw = |app: &App| app.world().get::<CameraLook>(rig).unwrap().yaw;
    let pitch = |app: &App| app.world().get::<CameraLook>(rig).unwrap().pitch;
    let yaw_before = yaw(&app);
    let pitch_before = pitch(&app);

    // 200 px of mouse motion in one frame.
    app.world_mut()
        .write_message(bevy::input::mouse::MouseMotion {
            delta: Vec2::new(200.0, 100.0),
        });
    app.update();
    assert!(
        (yaw(&app) - (yaw_before - 200.0 * 0.005)).abs() < 1e-4,
        "yaw turned by -dx * sensitivity: {} -> {}",
        yaw_before,
        yaw(&app)
    );
    assert!(
        (pitch(&app) - (pitch_before + 100.0 * 0.005)).abs() < 1e-4,
        "third-person pitch followed dy: {} -> {}",
        pitch_before,
        pitch(&app)
    );

    // The same motion with the right button held: the bridge yields,
    // the rig's own channel owns the turn, the bridge writes nothing.
    let held_out = yaw(&app);
    app.world_mut()
        .write_message(bevy::input::mouse::MouseButtonInput {
            button: MouseButton::Right,
            state: bevy::input::ButtonState::Pressed,
            window: Entity::PLACEHOLDER,
        });
    app.update();
    app.world_mut()
        .write_message(bevy::input::mouse::MouseMotion {
            delta: Vec2::new(200.0, 0.0),
        });
    app.update();
    assert!(
        (yaw(&app) - held_out).abs() < 1e-4,
        "RMB held: the bridge yields those frames, yaw stayed {held_out}"
    );

    // And the player body itself never turned — facing belongs to the
    // movement direction, not the look.
    let player_facing = app.world().get::<Transform>(parent).unwrap().rotation;
    assert!(
        player_facing.x.abs() < 1e-6
            && player_facing.y.abs() < 1e-6
            && player_facing.z.abs() < 1e-6,
        "look turned the camera, not the player: {player_facing:?}"
    );
}

// ---- Frame-rate independence (C2) -------------------------------------------

/// The same held input covers the same ground at 60 Hz and 30 Hz —
/// displacement is speed x time, not speed x frames. (The template's
/// pre-controller step was `x += move * 0.1` per frame: half the frame
/// rate, half the distance.)
#[test]
fn movement_covers_the_same_ground_at_two_frame_rates() {
    let run = |dt: Duration, tick: usize| {
        let mut app = controller_app(dt);
        spawn_stage(&mut app, false);
        let player = spawn_player(&mut app, 0.0, 0.0);
        frames(&mut app, 10);
        press(&mut app, KeyCode::KeyW);
        frames(&mut app, tick);
        release(&mut app, KeyCode::KeyW);
        player_z(&app, player)
    };
    // Two seconds of held W both ways.
    let at_60hz = run(Duration::from_secs_f64(1.0 / 60.0), 120);
    let at_30hz = run(Duration::from_secs_f64(1.0 / 30.0), 60);
    assert!(
        (at_60hz - at_30hz).abs() < 0.01,
        "the same distance at any frame rate: 60 Hz {at_60hz} vs 30 Hz {at_30hz}"
    );
    // And that distance is the tuned speed times the held time.
    assert!(
        ((-8.0) - at_60hz).abs() < 0.02,
        "4 m/s held for 2 s covers 8 m, got {at_60hz}"
    );
}
