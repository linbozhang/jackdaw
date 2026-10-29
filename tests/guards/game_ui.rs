//! The game UI template pattern over the real engine (T12-T1, re-pinned
//! for the T13 flow: the hud is the level's own overlay now, two
//! screens).
//!
//! Six legs over `JackdawPlugin`, mirroring `templates/game/src/
//! lib.rs.template`'s "Game UI" section and `assets/hud.bsn` (the
//! seed is loaded from the scaffold's template directory rendered the
//! way `jd new` renders it — the systems below are faithful local
//! ports of the template's own code; the worlds themselves and their
//! buttons live in `game_flow_template.rs` next door):
//!
//! * **Load (U1 red→green)**: a game without the hud spawn has no UI
//!   at all — the shape every pre-T12 project ran in; with it, the
//!   document spawns as an unparented UI root carrying the HUD and the
//!   pause veil, and every binding resolves with `BindFailures` empty.
//! * **The veil follows its bool**: flipping `GameState.paused` is the
//!   whole show/hide mechanism, and the HUD stays up under the
//!   translucent veil (the world keeps running behind it).
//! * **The bar binds data (U3 red→green)**: without `PlayerHealth` on
//!   the context entity the bindings fail into `BindFailures` — the
//!   visible-failure shape U2's runtime half takes; with it,
//!   `Progress.value` follows `current / max` exactly and the texts
//!   format the same numbers.
//! * **Buttons are real behavior (U7-adjacent)**: an `Activate` on the
//!   pause screen's button sends `ScreenPressed` with its literal and
//!   the observer drops the veil — and without the observer a click
//!   changes nothing (the red state the template's log-line buttons
//!   used to live in).
//! * **Four resolutions, one layout**: at 800x600, 1280x720, 1920x1080
//!   and 2560x1440 the veil fills the window, the bar sits in the
//!   top-left padding and the button stays inside its screen —
//!   percent-and-flex discipline, asserted numerically per size.
//! * **The pause gate**: outside the level (menu, game over) or under
//!   the veil the player stands still; running, the same input walks,
//!   and the Interact key — the no-physics damage fallback — takes
//!   health.

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

/// Which world the game is in (template `GameFlow`).
#[derive(States, Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
enum GameFlow {
    #[default]
    Menu,
    Level,
    GameOver,
}

/// The one bool the hud's bindings read (template `GameState`): the
/// pause veil.
#[derive(Resource, Reflect, Default)]
#[reflect(Resource, Default)]
struct GameState {
    paused: bool,
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

// The author's starting number for the health lives in the template's
// `GameConfig`; the injection chain it rides is the config guards' own
// surface (`config_injection.rs`), so this file carries only the
// component side.

// Template constants and via functions, ported verbatim.
const PLAYER_DAMAGE: f32 = 15.0;
const PLAYER_SPAWN: Vec3 = Vec3::new(-2.0, 1.0, 0.0);

fn ratio(current: f32, max: f32) -> f32 {
    (current / max).clamp(0.0, 1.0)
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

/// Template `on_screen_pressed`, hud half: the veil's button.
fn on_screen_pressed(press: On<ScreenPressed>, mut state: ResMut<GameState>) {
    if press.event().button == "resume" {
        state.paused = false;
    }
}

/// Template `update_game_over`: blood out ends the run, and only a
/// current `Level` can end. (The template chains it after
/// `apply_health_from_config`; the injection leg is the config guards'
/// surface.)
fn update_game_over(
    flow: Res<State<GameFlow>>,
    mut next: ResMut<NextState<GameFlow>>,
    players: Query<&PlayerHealth, With<PlayerMarker>>,
) {
    if flow.get() != &GameFlow::Level {
        return;
    }
    for health in &players {
        if health.current <= 0.0 {
            next.set(GameFlow::GameOver);
            break;
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
    flow: Res<State<GameFlow>>,
    state: Res<GameState>,
    time: Res<Time>,
    mut players: Query<(&PlayerController, &mut Transform), With<PlayerMarker>>,
    mut healths: Query<&mut PlayerHealth, With<PlayerMarker>>,
    look: Query<&CameraLook>,
) {
    if flow.get() != &GameFlow::Level || state.paused {
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
/// loader, the binding evaluator and the widget runtime ride in it)
/// and `StatesPlugin` (the flow state machine; `DefaultPlugins` has
/// it, `MinimalPlugins` does not). The input plugin is the piece a
/// UI-plus-input test app cannot skip: widgets' interaction systems
/// read `ButtonInput<MouseButton>`.
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
        bevy::state::app::StatesPlugin,
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
    app.register_function(is_zero);
    app.init_resource::<GameState>();
    app.init_state::<GameFlow>();
    app
}

/// The current flow state, for the gate legs.
fn flow_of(app: &mut App) -> GameFlow {
    *app.world().resource::<State<GameFlow>>().get()
}

/// Put the flow in `state` as a transition would (the next update runs
/// the `OnEnter`/`OnExit` schedules around it).
fn set_flow(app: &mut App, state: GameFlow) {
    app.world_mut()
        .resource_mut::<NextState<GameFlow>>()
        .set(state);
    app.update();
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

fn paused(app: &mut App) -> bool {
    app.world().resource::<GameState>().paused
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
    // unparented UI root carrying its marker, both overlays and every
    // part arrive, and every binding resolved.
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
    for screen in ["Hud", "PauseScreen"] {
        let e = named(world, screen);
        assert!(world.get::<Node>(e).is_some(), "{screen} is a UI node");
        assert!(
            world.get::<Visibility>(e).is_some(),
            "{screen} carries visibility"
        );
    }
    // The veil's authored color lands exactly: a wrong value TypePath
    // (the re-export spelling `bevy_color::Srgba` instead of the
    // canonical `bevy_color::srgba::Srgba`, QA t12-t1 §四) still inserts
    // the component but at the fallback default — fully transparent,
    // with no BindFailures and no UnresolvedTypes to catch it.
    let pause = named(world, "PauseScreen");
    assert_eq!(
        world.get::<BackgroundColor>(pause),
        Some(&BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.6))),
        "the pause veil's authored color must land exactly"
    );
    for part in [
        "HealthBar",
        "HealthFill",
        "HealthText",
        "PickupsText",
        "ResumeButton",
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

// ---- 2. The veil follows its bool ------------------------------------

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
    // The hud is the level's own overlay: up the whole time its
    // document is in the world (its old `not(menu)` binding retired
    // with the menu screen — the menu is a world now, not a bool).
    assert_eq!(visibility(&mut app, "Hud"), Visibility::Inherited);
    assert_eq!(visibility(&mut app, "PauseScreen"), Visibility::Hidden);

    // Flipping the bool is the whole mechanism.
    app.world_mut().resource_mut::<GameState>().paused = true;
    app.update();
    assert_eq!(visibility(&mut app, "PauseScreen"), Visibility::Inherited);
    // The hud stays up under the pause veil: the veil is translucent
    // over a live game.
    assert_eq!(visibility(&mut app, "Hud"), Visibility::Inherited);

    app.world_mut().resource_mut::<GameState>().paused = false;
    app.update();
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
    // ends the run when it bottoms out.
    let mut app = game_app();
    set_flow(&mut app, GameFlow::Level);
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
    assert_eq!(flow_of(&mut app), GameFlow::Level);

    // Blood out: `take_damage` clamps at the component (the binding
    // mirrors whatever the component says, so the clamp lives at the
    // source), and the next frame ends the run.
    {
        let mut health = app.world_mut().get_mut::<PlayerHealth>(player).unwrap();
        take_damage(&mut health, 200.0);
    }
    app.update();
    app.update();
    assert_eq!(value(&mut app), 0.0, "the ratio clamps at zero");
    assert_eq!(text(&mut app), "0 / 100");
    assert_eq!(
        flow_of(&mut app),
        GameFlow::GameOver,
        "bottomed health ends the run (a `NextState` set lands the frame after)"
    );
    assert_eq!(failure_count(&mut app), 0, "no failures on the green leg");
    // The `is_zero` registered function is the other half of the pair
    // bar-style bindings reach for; the run itself ends through the
    // flow (asserted above).
    assert!(is_zero(0.0) && !is_zero(0.5));
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
        app.world_mut().resource_mut::<GameState>().paused = true;
        let resume = named(app.world_mut(), "ResumeButton");
        app.world_mut().trigger(Activate { entity: resume });
        app.update();
        assert!(paused(&mut app), "a click with no observer changes nothing");
    }

    // Green: the button's literal reaches the observer and drops the
    // veil. (The flow documents' buttons — start, restart, menu — are
    // the `game_flow_template.rs` file's legs.)
    let mut app = game_app();
    spawn_player(
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

    app.world_mut().resource_mut::<GameState>().paused = true;
    app.update();
    press(&mut app, "ResumeButton");
    assert!(!paused(&mut app), "Resume drops the veil");
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
        // Raise the veil so the overlay leg measures the pause screen
        // the way the old start screen was measured — full-bleed.
        app.world_mut().resource_mut::<GameState>().paused = true;
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

        // The veil stretches the full window from the corner, whatever
        // the size. The transform reads at the node's center, so corner
        // assertions subtract half the size.
        let (veil_at, veil_size) = geometry(&mut app, "PauseScreen");
        let veil_min = veil_at - veil_size / 2.0;
        assert!(
            close(veil_min.x, 0.0) && close(veil_min.y, 0.0),
            "{width}x{height}: the veil starts at the corner, at {veil_min}"
        );
        assert!(
            close(veil_size.x, width as f32) && close(veil_size.y, height as f32),
            "{width}x{height}: the veil fills the window, sized {veil_size}"
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
        let (button_at, button_size) = geometry(&mut app, "ResumeButton");
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
    app.add_systems(Update, (handle_pause_action_port, move_player).chain());
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

    // On the menu (the boot state) the walk input is dead: the flow
    // gate is the world-level half of the pause.
    walk(&mut app, &key_event);
    assert_eq!(
        translation(&mut app).z,
        0.0,
        "outside the level the gate holds the player"
    );

    // Running: W walks away from the camera (yaw 0: -Z), 4 m/s * 0.1 s.
    set_flow(&mut app, GameFlow::Level);
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

    // The end screen is the other world: the gate comes down again.
    set_flow(&mut app, GameFlow::GameOver);
    walk(&mut app, &key_event);
    assert!(
        (translation(&mut app).z + 0.8).abs() < 1e-4,
        "on the end screen, the player stands still"
    );
}

/// Template `handle_pause_action`: the flip, level-only.
fn handle_pause_action_port(
    actions: Res<GameActions>,
    flow: Res<State<GameFlow>>,
    mut state: ResMut<GameState>,
) {
    if actions.just_pressed("Pause") && flow.get() == &GameFlow::Level {
        state.paused = !state.paused;
    }
}

// ---- 7. A typoed binding fails loudly, and fixing it lands (T12-T2) ---

/// U2's headless half, at the classic field-typo shape (`Health.currrent`):
/// a binding naming a field the component does not have warns into
/// `BindFailures` and the widget keeps its authored value (the log face in
/// Play/PIE is what makes the warn visible; this pins the ledger mechanics
/// behind it). Correcting the path is enough — no re-spawn, no reset: the
/// same binding evaluates, the value lands, and the ledger clears.
#[test]
fn a_typoed_field_fails_loudly_and_a_fix_lands_quietly() {
    let mut app = game_app();
    let player = spawn_player(
        &mut app,
        Some(PlayerHealth {
            current: 87.0,
            max: 100.0,
        }),
    );
    let bar = app
        .world_mut()
        .spawn((
            Name::new("HealthBar"),
            Node::default(),
            jackdaw_widgets_runtime::Progress { value: 1.0 },
            BindContext(player),
            jackdaw_bind::Bindings(vec![jackdaw_bind::Binding::Field {
                read: vec![
                    jackdaw_bind::BindPath::new("guards::game_ui::PlayerHealth.currrent"),
                    jackdaw_bind::BindPath::new("guards::game_ui::PlayerHealth.max"),
                ],
                via: Some("ratio".to_owned()),
                write: jackdaw_bind::BindPath::new("jackdaw_widgets_runtime::Progress.value"),
                as_percent: false,
            }]),
        ))
        .id();
    for _ in 0..3 {
        app.update();
    }
    assert!(
        failure_count(&mut app) > 0,
        "a field the component does not have is a loud failure, not a silent one"
    );
    let value = |app: &mut App| {
        app.world()
            .get::<jackdaw_widgets_runtime::Progress>(bar)
            .unwrap()
            .value
    };
    assert_eq!(
        value(&mut app),
        1.0,
        "the bar keeps its authored value while the path is wrong"
    );

    // The fix: correct the field name on the same binding. The next frame
    // evaluates, the ratio lands, and the failure clears from the ledger.
    app.world_mut()
        .get_mut::<jackdaw_bind::Bindings>(bar)
        .unwrap()
        .0[0] = jackdaw_bind::Binding::Field {
        read: vec![
            jackdaw_bind::BindPath::new("guards::game_ui::PlayerHealth.current"),
            jackdaw_bind::BindPath::new("guards::game_ui::PlayerHealth.max"),
        ],
        via: Some("ratio".to_owned()),
        write: jackdaw_bind::BindPath::new("jackdaw_widgets_runtime::Progress.value"),
        as_percent: false,
    };
    app.update();
    app.update();
    assert!(
        (value(&mut app) - 0.87).abs() < 1e-5,
        "the corrected binding lands the ratio"
    );
    assert_eq!(
        failure_count(&mut app),
        0,
        "the fix clears the ledger without a restart"
    );
}
