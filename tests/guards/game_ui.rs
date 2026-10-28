//! The game UI template pattern over the real engine (T12-T1).
//!
//! Six legs over `JackdawPlugin`, mirroring `templates/game/src/
//! lib.rs.template`'s "Game UI" section and `assets/hud.bsn` (the
//! seed is loaded from the scaffold's template directory rendered the
//! way `jd new` renders it — the systems below are faithful local
//! ports of the template's own code):
//!
//! * **Load (U1 red→green)**: a game without the hud spawn has no UI
//!   at all — the shape every pre-T12 project ran in; with it, the
//!   document spawns its four screens as an unparented UI root and
//!   every binding resolves with `BindFailures` empty.
//! * **Screens follow state**: flipping the `GameState` bools is the
//!   whole show/hide mechanism (the `Visibility` bindings move the
//!   screens; nothing positions anything in code).
//! * **The bar binds data (U3 red→green)**: without `PlayerHealth` on
//!   the context entity the bindings fail into `BindFailures` — the
//!   visible-failure shape U2's runtime half takes; with it,
//!   `Progress.value` follows `current / max` exactly and the texts
//!   format the same numbers.
//! * **Buttons are real behavior (U7-adjacent)**: an `Activate` on
//!   each authored button sends `ScreenPressed` with its literal and
//!   the observer flips the matching state — and without the observer
//!   a click changes nothing (the red state the template's log-line
//!   buttons used to live in).
//! * **Four resolutions, one layout**: at 800x600, 1280x720, 1920x1080
//!   and 2560x1440 the overlays fill the window, the bar sits in the
//!   top-left padding and the buttons stay inside their screens —
//!   percent-and-flex discipline, asserted numerically per size.
//! * **The pause gate**: with a screen up (menu, paused, game over)
//!   the player stands still; running, the same input walks, and the
//!   Interact key — the no-physics damage fallback — takes health.

use bevy::camera::{Camera2d, ComputedCameraValues, RenderTargetInfo};
use bevy::prelude::*;
use bevy::time::TimeUpdateStrategy;
use bevy::ui::{IsDefaultUiCamera, UiGlobalTransform};
use bevy::ui_widgets::Activate;
use jackdaw_bind::{BindContext, BindFailures};
use jackdaw_runtime::JackdawScene;
use jackdaw_runtime::prelude::*;
use std::time::Duration;

// ---- The game UI pattern, ported from the template ------------------

/// Which screen is up (template `GameState`).
#[derive(Resource, Reflect)]
#[reflect(Resource, Default)]
struct GameState {
    menu: bool,
    paused: bool,
    game_over: bool,
}

impl Default for GameState {
    fn default() -> Self {
        Self {
            menu: true,
            paused: false,
            game_over: false,
        }
    }
}

/// What a hud button says (template `ScreenPressed`). No `Entity`
/// field: the button's literal fills `button`, so this is a plain
/// `Event` — the `EntityEvent` derive would demand an entity target.
#[derive(Event, Reflect, Clone, Default)]
#[reflect(Event, Default)]
struct ScreenPressed {
    button: String,
}

/// The live health the hud reads (template `PlayerHealth`).
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct PlayerHealth {
    current: f32,
    max: f32,
}

/// The pickup counter the hud's second text reads.
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct PickupCount(u32);

/// The marker the hud document carries (template `HudRoot`). The
/// `Default` in `#[reflect(..)]` is load-bearing: the document's bare
/// marker line applies through `ReflectDefault`, and without it the
/// type resolves but silently does not apply.
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct HudRoot;

/// The template player marker, for the pause-gate leg.
#[derive(Component, Reflect, Default)]
#[reflect(Component)]
struct PlayerMarker;

/// The controller tuning the pause-gate leg walks with.
#[derive(Component, Reflect)]
#[reflect(Component, Default)]
struct PlayerController {
    move_speed: f32,
}

impl Default for PlayerController {
    fn default() -> Self {
        Self { move_speed: 4.0 }
    }
}

/// Template constants and via functions, ported verbatim.
const PLAYER_DAMAGE: f32 = 15.0;
const PLAYER_SPAWN: Vec3 = Vec3::new(-2.0, 1.0, 0.0);

fn ratio(current: f32, max: f32) -> f32 {
    (current / max).clamp(0.0, 1.0)
}

fn not(value: bool) -> bool {
    !value
}

fn is_zero(value: f32) -> bool {
    value == 0.0
}

fn take_damage(health: &mut PlayerHealth, amount: f32) {
    health.current = (health.current - amount).max(0.0);
}

/// Template `wire_hud`: the marker lookup plus the context insert.
fn wire_hud(
    mut commands: Commands,
    hud_roots: Query<Entity, Added<HudRoot>>,
    players: Query<Entity, With<PlayerMarker>>,
) {
    let (Ok(root), Ok(player)) = (hud_roots.single(), players.single()) else {
        return;
    };
    commands.entity(root).insert(BindContext(player));
}

/// Template `on_screen_pressed`: literals to state flips.
fn on_screen_pressed(
    press: On<ScreenPressed>,
    mut state: ResMut<GameState>,
    mut players: Query<(&mut PlayerHealth, &mut Transform), With<PlayerMarker>>,
) {
    match press.event().button.as_str() {
        "start" => state.menu = false,
        "resume" => state.paused = false,
        "restart" => {
            state.menu = false;
            state.paused = false;
            state.game_over = false;
            for (mut health, mut transform) in &mut players {
                health.current = health.max;
                *transform = Transform::from_translation(PLAYER_SPAWN);
            }
        }
        _ => {}
    }
}

/// Template `handle_pause_action`.
fn handle_pause_action(actions: Res<GameActions>, mut state: ResMut<GameState>) {
    if actions.just_pressed("Pause") && !state.menu && !state.game_over {
        state.paused = !state.paused;
    }
}

/// Template `update_game_over`.
fn update_game_over(
    mut state: ResMut<GameState>,
    mut players: Query<&mut PlayerHealth, With<PlayerMarker>>,
) {
    if state.game_over {
        return;
    }
    for health in &mut players {
        if health.current <= 0.0 {
            state.game_over = true;
            state.paused = false;
        }
    }
}

/// Template `move_direction` (shared by both movement forms).
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

/// Template `face_movement_direction` (body turn while walking).
fn face_movement_direction(direction: Vec3, dt: f32, transform: &mut Transform) {
    let horizontal = Vec3::new(direction.x, 0.0, direction.z);
    if horizontal.length_squared() < 1e-6 {
        return;
    }
    let facing = horizontal.normalize();
    let target = Quat::from_rotation_y((-facing.x).atan2(-facing.z));
    let turn = (12.0 * dt).clamp(0.0, 1.0);
    transform.rotation = transform.rotation.slerp(target, turn);
}

/// The template's no-physics `move_player`: the gate, the walk, the
/// Jump log line and the Interact damage fallback — the form every
/// module set ships (the physics form adds avian below it).
fn move_player(
    actions: Res<GameActions>,
    state: Res<GameState>,
    time: Res<Time>,
    mut players: Query<(&PlayerController, &mut Transform), With<PlayerMarker>>,
    mut healths: Query<&mut PlayerHealth, With<PlayerMarker>>,
    look: Query<&CameraLook>,
) {
    if state.menu || state.paused || state.game_over {
        return;
    }
    let dt = time.delta_secs();
    let camera_yaw = look.single().map(|camera| camera.yaw).unwrap_or(0.0);
    let direction = move_direction(actions.value("Move"), camera_yaw);
    for (controller, mut transform) in &mut players {
        transform.translation += direction * controller.move_speed * dt;
        face_movement_direction(direction, dt, &mut transform);
    }
    if actions.just_pressed("Jump") {
        info!("Jump! (needs the physics module to leave the ground)");
    }
    if actions.just_pressed("Interact") {
        for mut health in &mut healths {
            take_damage(&mut health, PLAYER_DAMAGE);
        }
    }
}

// ---- The app and the seed -------------------------------------------

/// The engine under a game: the pieces `main.rs.template`'s
/// `DefaultPlugins` provide headless, plus `JackdawPlugin` (the UI
/// loader, the binding evaluator and the widget runtime ride in it).
/// The input plugin is the piece a UI-plus-input test app cannot skip:
/// widgets' interaction systems read `ButtonInput<MouseButton>`.
fn game_app() -> App {
    let mut app = App::new();
    app.add_plugins((
        MinimalPlugins,
        bevy::transform::TransformPlugin,
        bevy::input::InputPlugin,
        bevy::asset::AssetPlugin::default(),
        bevy::text::TextPlugin,
        bevy::picking::PickingPlugin,
        bevy::picking::InteractionPlugin,
        bevy::ui::UiPlugin,
        bevy::world_serialization::WorldSerializationPlugin,
        JackdawPlugin,
    ));
    // The two asset stores bevy_ui's content-size systems read; the
    // real game gets them from DefaultPlugins, hud_scenario inits them
    // by hand for the same reason.
    app.init_asset::<Image>();
    app.init_asset::<TextureAtlasLayout>();
    app.register_type::<GameState>();
    app.register_type::<PlayerHealth>();
    app.register_type::<PickupCount>();
    app.register_type::<HudRoot>();
    app.register_type::<ScreenPressed>();
    app.register_function(ratio);
    app.register_function(not);
    app.register_function(is_zero);
    app.init_resource::<GameState>();
    app
}

/// The rendered hud seed, exactly as `jd new` renders it for a project
/// named `guards` (the crate name this test target registers its
/// ported types under — the bindings name the same paths).
fn hud_seed() -> String {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/crates/jackdaw_scaffold/templates/game/assets/hud.bsn.template"
    );
    std::fs::read_to_string(path)
        .unwrap_or_else(|error| panic!("the template ships the hud seed: {error}"))
        .replace("{{crate_name}}", "guards::game_ui")
        .replace("{{project-name | title_case}}", "Guards")
}

/// Spawn the hud document from the rendered seed.
fn spawn_hud_seed(app: &mut App) {
    let scene = app
        .world_mut()
        .resource_mut::<Assets<JackdawScene>>()
        .add(JackdawScene::new(hud_seed(), ".".into()));
    app.world_mut().spawn(JackdawSceneRoot(scene));
}

/// The context player the hud reads: health, pickups, the marker
/// `wire_hud` looks for.
fn spawn_player(app: &mut App, health: Option<PlayerHealth>) -> Entity {
    let mut entity = app.world_mut().spawn((
        PlayerMarker,
        PlayerController::default(),
        PickupCount(3),
        CameraLook::default(),
        Transform::from_translation(PLAYER_SPAWN),
    ));
    if let Some(health) = health {
        entity.insert(health);
    }
    entity.id()
}

fn named(world: &mut World, target: &str) -> Entity {
    let mut names = world.query::<(Entity, &Name)>();
    names
        .iter(world)
        .find_map(|(entity, name)| (name.as_str() == target).then_some(entity))
        .unwrap_or_else(|| panic!("expected entity named {target}"))
}

fn state_of(app: &mut App) -> (bool, bool, bool) {
    let state = app.world().resource::<GameState>();
    (state.menu, state.paused, state.game_over)
}

fn failure_count(app: &mut App) -> usize {
    app.world().resource::<BindFailures>().0.len()
}

// ---- 1. Load: red (no hud, no UI) then green ------------------------

#[test]
fn the_hud_is_the_only_ui_and_it_loads_with_its_bindings_resolved() {
    // Red (U1): the pre-template shape — a game running its scene with
    // no hud spawn has zero UI. Nothing below passes if the runtime
    // grows stray UI of its own.
    {
        let mut app = game_app();
        let player = spawn_player(
            &mut app,
            Some(PlayerHealth {
                current: 100.0,
                max: 100.0,
            }),
        );
        app.world_mut().entity_mut(player).remove::<PickupCount>();
        for _ in 0..3 {
            app.update();
        }
        let mut nodes = app.world_mut().query::<&Node>();
        assert_eq!(
            nodes.iter(app.world()).count(),
            0,
            "a game that never spawns the hud has no UI"
        );
        assert!(
            app.world()
                .get_resource::<BindFailures>()
                .is_none_or(|f| f.0.is_empty()),
            "no hud means no bindings to fail"
        );
    }

    // Green: the template's spawn plus wire — the document loads as an
    // unparented UI root carrying its marker, all four screens and
    // every part arrive, and every binding resolved.
    let mut app = game_app();
    let player = spawn_player(
        &mut app,
        Some(PlayerHealth {
            current: 87.0,
            max: 100.0,
        }),
    );
    app.add_systems(Update, wire_hud);
    spawn_hud_seed(&mut app);
    for _ in 0..3 {
        app.update();
    }
    let world = app.world_mut();
    let hud_root_probe = named(world, "HudRoot");
    let entity_ref = world.entity(hud_root_probe);
    let mut names = Vec::new();
    for component_id in entity_ref.archetype().components() {
        if let Some(info) = world.components().get_info(*component_id) {
            names.push(info.name().to_string());
        }
    }
    let hud_root = named(world, "HudRoot");
    assert!(
        world.get::<HudRoot>(hud_root).is_some(),
        "the authored marker loaded"
    );
    assert!(
        world.get::<bevy::ui::Node>(hud_root).is_some(),
        "the hud root is a UI node"
    );
    assert!(
        world.get::<ChildOf>(hud_root).is_none(),
        "a UI root stays unparented (bevy lays out parented UI not at all)"
    );
    assert_eq!(
        world.get::<BindContext>(hud_root).map(|c| c.0),
        Some(player),
        "wire_hud put the player's context on the root"
    );
    for screen in ["Hud", "StartScreen", "PauseScreen", "GameOverScreen"] {
        let e = named(world, screen);
        assert!(world.get::<Node>(e).is_some(), "{screen} is a UI node");
        assert!(
            world.get::<Visibility>(e).is_some(),
            "{screen} carries visibility"
        );
    }
    // The veils' authored colors land exactly: a wrong value TypePath
    // (the re-export spelling `bevy_color::Srgba` instead of the
    // canonical `bevy_color::srgba::Srgba`, QA t12-t1 §四) still inserts
    // the component but at the fallback default — fully transparent,
    // with no BindFailures and no UnresolvedTypes to catch it.
    for (screen, alpha) in [("PauseScreen", 0.6), ("GameOverScreen", 0.92)] {
        let e = named(world, screen);
        assert_eq!(
            world.get::<BackgroundColor>(e),
            Some(&BackgroundColor(Color::srgba(0.0, 0.0, 0.0, alpha))),
            "{screen}: the authored veil color must land exactly"
        );
    }
    for part in [
        "HealthBar",
        "HealthFill",
        "HealthText",
        "PickupsText",
        "StartButton",
        "ResumeButton",
        "RestartButton",
    ] {
        named(world, part);
    }
    assert_eq!(
        failure_count(&mut app),
        0,
        "every binding resolved, got: {:?}",
        app.world().resource::<BindFailures>().0
    );
}

// ---- 2. Screens follow state ----------------------------------------

#[test]
fn flipping_game_state_moves_the_screens() {
    let mut app = game_app();
    spawn_player(
        &mut app,
        Some(PlayerHealth {
            current: 87.0,
            max: 100.0,
        }),
    );
    spawn_hud_seed(&mut app);
    for _ in 0..3 {
        app.update();
    }
    let visibility = |app: &mut App, name: &str| {
        let e = named(app.world_mut(), name);
        *app.world().get::<Visibility>(e).unwrap()
    };
    // The default state: menu up, everything else down.
    assert_eq!(visibility(&mut app, "StartScreen"), Visibility::Inherited);
    assert_eq!(visibility(&mut app, "Hud"), Visibility::Hidden);
    assert_eq!(visibility(&mut app, "PauseScreen"), Visibility::Hidden);
    assert_eq!(visibility(&mut app, "GameOverScreen"), Visibility::Hidden);

    app.world_mut().resource_mut::<GameState>().menu = false;
    app.update();
    assert_eq!(visibility(&mut app, "StartScreen"), Visibility::Hidden);
    assert_eq!(visibility(&mut app, "Hud"), Visibility::Inherited);

    app.world_mut().resource_mut::<GameState>().paused = true;
    app.update();
    assert_eq!(visibility(&mut app, "PauseScreen"), Visibility::Inherited);
    // The hud stays up under the pause veil (its binding reads the
    // menu, not the pause): the veil is translucent over a live game.
    assert_eq!(visibility(&mut app, "Hud"), Visibility::Inherited);

    app.world_mut().resource_mut::<GameState>().paused = false;
    app.world_mut().resource_mut::<GameState>().game_over = true;
    app.update();
    assert_eq!(
        visibility(&mut app, "GameOverScreen"),
        Visibility::Inherited
    );
    assert_eq!(visibility(&mut app, "PauseScreen"), Visibility::Hidden);
}

// ---- 3. The bar binds data: red (no component) then green -----------

#[test]
fn the_bar_follows_player_health_and_misses_it_loudly() {
    // Red (U3, and U2's runtime shape): the hud loaded but the context
    // player carries no `PlayerHealth` — the health bindings fail into
    // `BindFailures` instead of silently showing something.
    {
        let mut app = game_app();
        spawn_player(&mut app, None);
        app.add_systems(Update, wire_hud);
        spawn_hud_seed(&mut app);
        for _ in 0..3 {
            app.update();
        }
        assert!(
            failure_count(&mut app) > 0,
            "a hud reading a component the context entity lacks fails loudly: {:?}",
            app.world().resource::<BindFailures>().0
        );
        let bar = named(app.world_mut(), "HealthBar");
        let progress = app
            .world()
            .get::<jackdaw_widgets_runtime::Progress>(bar)
            .unwrap();
        assert_eq!(
            progress.value, 1.0,
            "the bar keeps its authored value while the binding fails"
        );
    }

    // Green: with the component, the bar is `ratio` and the texts are
    // the same numbers — at two health values, and the same component
    // drives game over when it bottoms out.
    let mut app = game_app();
    let player = spawn_player(
        &mut app,
        Some(PlayerHealth {
            current: 87.0,
            max: 100.0,
        }),
    );
    app.add_systems(Update, (wire_hud, update_game_over));
    spawn_hud_seed(&mut app);
    for _ in 0..3 {
        app.update();
    }
    let bar = named(app.world_mut(), "HealthBar");
    let value = |app: &mut App| {
        app.world()
            .get::<jackdaw_widgets_runtime::Progress>(bar)
            .unwrap()
            .value
    };
    let text = |app: &mut App| {
        let e = named(app.world_mut(), "HealthText");
        app.world().get::<Text>(e).unwrap().0.clone()
    };
    assert_eq!(value(&mut app), 0.87);
    assert_eq!(text(&mut app), "87 / 100");
    let pickups = {
        let e = named(app.world_mut(), "PickupsText");
        app.world().get::<Text>(e).unwrap().0.clone()
    };
    assert_eq!(pickups, "Pickups: 3");

    app.world_mut()
        .get_mut::<PlayerHealth>(player)
        .unwrap()
        .current = 30.0;
    app.update();
    assert_eq!(value(&mut app), 0.3);
    assert_eq!(text(&mut app), "30 / 100");
    assert!(!app.world().resource::<GameState>().game_over);

    // Blood out: `take_damage` clamps at the component (the binding
    // mirrors whatever the component says, so the clamp lives at the
    // source), and the next frame is game over.
    {
        let mut health = app.world_mut().get_mut::<PlayerHealth>(player).unwrap();
        take_damage(&mut health, 200.0);
    }
    app.update();
    assert_eq!(value(&mut app), 0.0, "the ratio clamps at zero");
    assert_eq!(text(&mut app), "0 / 100");
    assert!(
        app.world().resource::<GameState>().game_over,
        "bottomed health is game over"
    );
    assert_eq!(failure_count(&mut app), 0, "no failures on the green leg");
}

// ---- 4. Buttons: red (no observer) then green ------------------------

#[test]
fn buttons_flip_state_only_through_the_observer() {
    // Red: the pre-template shape — a click dispatches the event and
    // nothing listens. The state does not move; nothing panics.
    {
        let mut app = game_app();
        spawn_player(
            &mut app,
            Some(PlayerHealth {
                current: 100.0,
                max: 100.0,
            }),
        );
        app.add_systems(Update, wire_hud);
        spawn_hud_seed(&mut app);
        for _ in 0..3 {
            app.update();
        }
        let start = named(app.world_mut(), "StartButton");
        app.world_mut().trigger(Activate { entity: start });
        app.update();
        assert_eq!(
            state_of(&mut app),
            (true, false, false),
            "a click with no observer changes nothing"
        );
    }

    // Green: each button's literal reaches the observer and flips its
    // own piece of state; Restart also resets health and position.
    let mut app = game_app();
    let player = spawn_player(
        &mut app,
        Some(PlayerHealth {
            current: 100.0,
            max: 100.0,
        }),
    );
    app.add_observer(on_screen_pressed);
    app.add_systems(Update, wire_hud);
    spawn_hud_seed(&mut app);
    for _ in 0..3 {
        app.update();
    }
    let press = |app: &mut App, name: &str| {
        let e = named(app.world_mut(), name);
        app.world_mut().trigger(Activate { entity: e });
        app.update();
    };

    press(&mut app, "StartButton");
    assert_eq!(
        state_of(&mut app),
        (false, false, false),
        "Start leaves the menu"
    );

    app.world_mut().resource_mut::<GameState>().paused = true;
    press(&mut app, "ResumeButton");
    assert_eq!(state_of(&mut app), (false, false, false), "Resume unpauses");

    app.world_mut().resource_mut::<GameState>().game_over = true;
    app.world_mut()
        .get_mut::<PlayerHealth>(player)
        .unwrap()
        .current = 0.0;
    {
        let mut transform = app.world_mut().get_mut::<Transform>(player).unwrap();
        transform.translation = Vec3::new(9.0, 9.0, 9.0);
    }
    press(&mut app, "RestartButton");
    assert_eq!(
        state_of(&mut app),
        (false, false, false),
        "Restart clears the screens"
    );
    assert_eq!(
        app.world().get::<PlayerHealth>(player).unwrap().current,
        100.0,
        "Restart restores the health"
    );
    assert_eq!(
        app.world().get::<Transform>(player).unwrap().translation,
        PLAYER_SPAWN,
        "Restart lands the player where the run began"
    );
}

// ---- 5. Four resolutions, one layout ---------------------------------

#[test]
fn one_layout_holds_across_the_four_common_resolutions() {
    for (width, height) in [(800u32, 600u32), (1280, 720), (1920, 1080), (2560, 1440)] {
        let mut app = game_app();
        // The render-less stand-in for a window: a camera whose
        // viewport is the resolution, marked as the default UI camera
        // (bevy_ui lays out against its target size; with no camera a
        // UI root lays out at zero).
        app.world_mut().spawn((
            Camera2d,
            IsDefaultUiCamera,
            Camera {
                viewport: Some(bevy::camera::Viewport {
                    physical_size: UVec2::new(width, height),
                    ..default()
                }),
                computed: ComputedCameraValues {
                    target_info: Some(RenderTargetInfo {
                        physical_size: UVec2::new(width, height),
                        scale_factor: 1.0,
                    }),
                    ..default()
                },
                ..default()
            },
        ));
        spawn_player(
            &mut app,
            Some(PlayerHealth {
                current: 87.0,
                max: 100.0,
            }),
        );
        spawn_hud_seed(&mut app);
        for _ in 0..3 {
            app.update();
        }
        let geometry = |app: &mut App, name: &str| {
            let e = named(app.world_mut(), name);
            let world = app.world();
            let at = world
                .get::<UiGlobalTransform>(e)
                .unwrap_or_else(|| panic!("{name}: no global transform"))
                .to_scale_angle_translation()
                .2;
            let size = world
                .get::<ComputedNode>(e)
                .unwrap_or_else(|| panic!("{name}: no computed node"))
                .size;
            (at, size)
        };
        let close = |a: f32, b: f32| (a - b).abs() <= 1.0;

        // The overlays stretch the full window from the corner,
        // whatever the size. The transform reads at the node's center,
        // so corner assertions subtract half the size.
        let (start_at, start_size) = geometry(&mut app, "StartScreen");
        let start_min = start_at - start_size / 2.0;
        assert!(
            close(start_min.x, 0.0) && close(start_min.y, 0.0),
            "{width}x{height}: the start screen starts at the corner, at {start_min}"
        );
        assert!(
            close(start_size.x, width as f32) && close(start_size.y, height as f32),
            "{width}x{height}: the start screen fills the window, sized {start_size}"
        );
        let (_, hud_size) = geometry(&mut app, "HudRoot");
        assert!(
            close(hud_size.x, width as f32) && close(hud_size.y, height as f32),
            "{width}x{height}: the hud root fills the window, sized {hud_size}"
        );

        // The bar sits in the top-left padding of the hud row, at its
        // authored pixel size, at every resolution.
        let (bar_at, bar_size) = geometry(&mut app, "HealthBar");
        let bar_min = bar_at - bar_size / 2.0;
        assert!(
            close(bar_min.x, 12.0) && bar_min.y >= 11.0 && bar_min.y < 40.0,
            "{width}x{height}: the bar hugs the top-left padding, at {bar_min}"
        );
        assert!(
            close(bar_size.x, 180.0) && close(bar_size.y, 10.0),
            "{width}x{height}: the bar keeps its pixel size, sized {bar_size}"
        );

        // The button stays inside its screen and centered: anchored by
        // the flex column, not by pixels.
        let (button_at, button_size) = geometry(&mut app, "StartButton");
        let button_min = button_at - button_size / 2.0;
        assert!(
            button_min.x >= 0.0
                && button_min.y >= 0.0
                && button_min.x + button_size.x <= width as f32 + 1.0
                && button_min.y + button_size.y <= height as f32 + 1.0,
            "{width}x{height}: the button stays inside the window, at {button_min} sized {button_size}"
        );
        assert!(
            (button_at.x - width as f32 / 2.0).abs() < 2.0,
            "{width}x{height}: the button is centered, at {button_at}"
        );
    }
}

// ---- 6. The pause gate ------------------------------------------------

#[test]
fn the_player_only_moves_while_no_screen_owns_the_moment() {
    let mut app = game_app();
    app.init_asset::<GameInputConfig>();
    app.register_asset_reflect::<GameInputConfig>();
    app.add_plugins(InputActionsPlugin);
    // The pause flip owns the frame (the template wires the same edge).
    app.add_systems(Update, (handle_pause_action, move_player).chain());
    app.insert_resource(TimeUpdateStrategy::ManualDuration(Duration::from_millis(
        100,
    )));
    let player = spawn_player(
        &mut app,
        Some(PlayerHealth {
            current: 100.0,
            max: 100.0,
        }),
    );
    app.update();

    let translation = |app: &mut App| app.world().get::<Transform>(player).unwrap().translation;
    let health = |app: &mut App| app.world().get::<PlayerHealth>(player).unwrap().current;
    // Keys enter through the message pipeline, exactly as a window
    // delivers them: a bare `press()` on the resource would be wiped by
    // the input system's per-frame clear. A press persists (until its
    // release event), so each walk leg sends its own release afterwards
    // and the legs stay independent.
    let key_event = |app: &mut App, code: KeyCode, state: bevy::input::ButtonState| {
        app.world_mut()
            .write_message(bevy::input::keyboard::KeyboardInput {
                key_code: code,
                logical_key: bevy::input::keyboard::Key::Character("k".into()),
                state,
                window: Entity::PLACEHOLDER,
                repeat: false,
                text: None,
            });
    };
    let walk = |app: &mut App, key_event: &dyn Fn(&mut App, KeyCode, bevy::input::ButtonState)| {
        key_event(app, KeyCode::KeyW, bevy::input::ButtonState::Pressed);
        app.update();
        key_event(app, KeyCode::KeyW, bevy::input::ButtonState::Released);
    };

    // On the menu (the default state) the walk input is dead.
    walk(&mut app, &key_event);
    assert_eq!(
        translation(&mut app).z,
        0.0,
        "the menu gate holds the player"
    );

    // Running: W walks away from the camera (yaw 0: -Z), 4 m/s * 0.1 s.
    app.world_mut().resource_mut::<GameState>().menu = false;
    walk(&mut app, &key_event);
    assert!(
        (translation(&mut app).z + 0.4).abs() < 1e-4,
        "running, W walks: at {:?}",
        translation(&mut app)
    );

    // Paused: the same held input moves nothing.
    app.world_mut().resource_mut::<GameState>().paused = true;
    walk(&mut app, &key_event);
    assert!(
        (translation(&mut app).z + 0.4).abs() < 1e-4,
        "paused, the player stands still"
    );

    // The Pause action is the other door into that bool. (The W release
    // queued by the last walk is consumed on this frame's update, so
    // the unpause itself moves nothing.)
    key_event(&mut app, KeyCode::Escape, bevy::input::ButtonState::Pressed);
    app.update();
    assert!(
        !app.world().resource::<GameState>().paused,
        "Escape unpauses"
    );
    walk(&mut app, &key_event);
    assert!(
        (translation(&mut app).z + 0.8).abs() < 1e-4,
        "unpaused, the walk resumes"
    );

    // The Interact key is the no-physics damage fallback.
    key_event(&mut app, KeyCode::KeyE, bevy::input::ButtonState::Pressed);
    app.update();
    key_event(&mut app, KeyCode::KeyE, bevy::input::ButtonState::Released);
    assert!(
        (health(&mut app) - 85.0).abs() < 1e-5,
        "Interact takes one hit of damage"
    );

    // Game over: the gate comes down again.
    app.world_mut().resource_mut::<GameState>().game_over = true;
    walk(&mut app, &key_event);
    assert!(
        (translation(&mut app).z + 0.8).abs() < 1e-4,
        "game over, the player stands still"
    );
}
