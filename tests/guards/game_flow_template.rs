//! The template's game flow over the real engine (T13-T3).
//!
//! Three legs over `JackdawPlugin`, mirroring `templates/game/src/
//! lib.rs.template`'s "Game flow" section and the three seed documents
//! it ships (`menu.bsn`, `scene.bsn`, `gameover.bsn`, plus the hud the
//! level carries — all rendered the way `jd new` renders them; the
//! systems below are faithful local ports of the template's own code,
//! and the runtime primitive they drive is `game_flow.rs`'s subject):
//!
//! * **The flow walks the worlds**: boot on the menu → Start → the
//!   level (world + hud + player, menu gone to the last entity, menu
//!   camera despawned) → blood out → the end screen → its Menu button
//!   back to the menu → Start again. Two full cycles land on per-stop
//!   counts identical to the first visit, each camera and the hud
//!   exist in exactly their own states, and one click is one flow
//!   move.
//! * **Restart is a switch**: from the end screen, Restart re-enters
//!   the level and `reset_run` puts the run back — full health, the
//!   spawn point — while the player entity itself is the same one that
//!   crossed every switch (its id never changes).
//! * **The boot state follows the start scene**: the mapping the
//!   template's build spells (`boot_state` over the composed boot
//!   scene) puts a menu start on the menu, a game-over start on the
//!   end screen, and any other scene — the level, a Play-Current
//!   override — in a playable level, and an app built that way boots
//!   into the right world before its first frame is done.

use bevy::prelude::*;
use bevy::ui::IsDefaultUiCamera;
use bevy::ui_widgets::Activate;
use jackdaw_bind::BindFailures;
use jackdaw_runtime::prelude::*;

// ---- The template's flow section, ported -----------------------------

const MENU_SCENE: &str = "menu.bsn";
const LEVEL_SCENE: &str = "scene.bsn";
const GAME_OVER_SCENE: &str = "gameover.bsn";
const HUD_SCENE: &str = "hud.bsn";

/// Template `GameFlow`.
#[derive(States, Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
enum GameFlow {
    #[default]
    Menu,
    Level,
    GameOver,
}

/// Template `BootScene`.
#[derive(Resource)]
struct BootScene(String);

/// Template `boot_state`.
fn boot_state(start: &str) -> GameFlow {
    match start {
        MENU_SCENE => GameFlow::Menu,
        GAME_OVER_SCENE => GameFlow::GameOver,
        _ => GameFlow::Level,
    }
}

/// Template `GameRoot`, `MenuRoot`, `GameOverRoot`, `HudRoot`.
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct GameRoot;

#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct MenuRoot;

#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct GameOverRoot;

#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct HudRoot;

/// Template `GameState`. The T17 save section added the save-display
/// mirror fields (`runs_played`, `unlock_note`) that the menu and
/// game-over documents bind through `Res(GameState)`; the copy keeps
/// them so those bindings resolve the way the real game's do.
#[derive(Resource, Reflect, Default)]
#[reflect(Resource, Default)]
struct GameState {
    paused: bool,
    runs_played: u32,
    unlock_note: String,
}

/// Template `ScreenPressed`.
#[derive(Event, Reflect, Clone, Default)]
#[reflect(Event, Default)]
struct ScreenPressed {
    button: String,
}

/// Template `PlayerHealth` and friends.
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct PlayerHealth {
    current: f32,
    max: f32,
}

#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct PlayerMarker;

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

/// Template `GameConfig` (the number the run starts at).
#[derive(Resource)]
struct GameConfig {
    player_health: f32,
}

impl Default for GameConfig {
    fn default() -> Self {
        Self {
            player_health: 100.0,
        }
    }
}

const PLAYER_SPAWN: Vec3 = Vec3::new(-2.0, 1.0, 0.0);

fn ratio(current: f32, max: f32) -> f32 {
    (current / max).clamp(0.0, 1.0)
}

/// Template `spawn_scene`.
fn spawn_scene(mut commands: Commands, boot: Res<BootScene>, asset_server: Res<AssetServer>) {
    commands.spawn((
        Name::new("GameRoot"),
        GameRoot,
        JackdawSceneRoot(asset_server.load(boot.0.clone())),
    ));
}

/// Template `enter_menu`.
fn enter_menu(
    mut commands: Commands,
    roots: Query<Entity, With<GameRoot>>,
    server: Res<AssetServer>,
) {
    if let Ok(root) = roots.single() {
        commands
            .entity(root)
            .insert(JackdawSceneRoot(server.load(MENU_SCENE)));
    }
    commands.spawn((
        Name::new("MenuUiCamera"),
        Camera2d,
        IsDefaultUiCamera,
        Camera {
            order: 1,
            ..default()
        },
        DespawnOnExit(GameFlow::Menu),
    ));
}

/// Template `enter_level`.
fn enter_level(
    mut commands: Commands,
    roots: Query<Entity, With<GameRoot>>,
    server: Res<AssetServer>,
) {
    if let Ok(root) = roots.single() {
        commands
            .entity(root)
            .insert(JackdawSceneRoot(server.load(LEVEL_SCENE)));
    }
}

/// Template `enter_game_over`.
fn enter_game_over(
    mut commands: Commands,
    roots: Query<Entity, With<GameRoot>>,
    server: Res<AssetServer>,
) {
    if let Ok(root) = roots.single() {
        commands
            .entity(root)
            .insert(JackdawSceneRoot(server.load(GAME_OVER_SCENE)));
    }
    commands.spawn((
        Name::new("GameOverUiCamera"),
        Camera2d,
        IsDefaultUiCamera,
        Camera {
            order: 1,
            ..default()
        },
        DespawnOnExit(GameFlow::GameOver),
    ));
}

/// Template `spawn_hud_while_level`.
fn spawn_hud_while_level(
    mut commands: Commands,
    server: Res<AssetServer>,
    flow: Res<State<GameFlow>>,
    mut live: Local<bool>,
) {
    let live_now = flow.get() == &GameFlow::Level;
    if live_now && !*live {
        commands.spawn((
            JackdawSceneRoot(server.load(HUD_SCENE)),
            DespawnOnExit(GameFlow::Level),
        ));
    }
    *live = live_now;
}

/// Template `spawn_player` (spawn once, cross every switch).
fn spawn_player(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    existing: Query<(), With<PlayerMarker>>,
) {
    if !existing.is_empty() {
        return;
    }
    let player = commands
        .spawn((
            PlayerMarker,
            PlayerController::default(),
            PlayerHealth::default(),
            Mesh3d(meshes.add(Capsule3d::new(0.35, 1.0))),
            MeshMaterial3d(materials.add(StandardMaterial {
                base_color: Color::srgb(0.25, 0.55, 0.9),
                ..default()
            })),
            Transform::from_translation(PLAYER_SPAWN),
        ))
        .id();
    commands.spawn((CameraRig::default(), ChildOf(player)));
}

/// Template `reset_run` — full health straight from the config, chained
/// right after `spawn_player` so a freshly spawned player is filled in
/// before any game-over check can read its zeroed health.
fn reset_run(
    config: Res<GameConfig>,
    mut players: Query<(&mut PlayerHealth, &mut Transform), With<PlayerMarker>>,
) {
    for (mut health, mut transform) in &mut players {
        health.max = config.player_health;
        health.current = config.player_health;
        *transform = Transform::from_translation(PLAYER_SPAWN);
    }
}

/// Template `on_screen_pressed`.
fn on_screen_pressed(
    press: On<ScreenPressed>,
    mut flow: ResMut<NextState<GameFlow>>,
    mut state: ResMut<GameState>,
) {
    match press.event().button.as_str() {
        // Start and Restart both enter the level: the run's numbers
        // come back through `reset_run` on the entry, so Restart needs
        // nothing of its own.
        "start" | "restart" => flow.set(GameFlow::Level),
        "menu" => flow.set(GameFlow::Menu),
        "resume" => state.paused = false,
        _ => {}
    }
}

/// Template `wire_hud`.
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

/// Template `apply_health_from_config`.
fn apply_health_from_config(
    config: Res<GameConfig>,
    mut players: Query<&mut PlayerHealth, With<PlayerMarker>>,
) {
    if !config.is_changed() {
        return;
    }
    for mut health in &mut players {
        health.max = config.player_health;
        health.current = config.player_health;
    }
}

/// Template `update_game_over`.
fn update_game_over(
    flow: Res<State<GameFlow>>,
    mut next: ResMut<NextState<GameFlow>>,
    mut state: ResMut<GameState>,
    players: Query<&PlayerHealth, With<PlayerMarker>>,
) {
    if flow.get() != &GameFlow::Level {
        return;
    }
    for health in &players {
        if health.current <= 0.0 {
            state.paused = false;
            next.set(GameFlow::GameOver);
            break;
        }
    }
}

// ---- The app and the seeds -------------------------------------------

/// The engine under a game, wired the way `GamePlugin::build` wires the
/// flow: the boot scene read once, the state initialized and the boot
/// state inserted (whose `OnEnter` runs before `Startup`), then the
/// same system registrations.
fn template_app(start: &str, dir: &std::path::Path) -> App {
    let mut app = App::new();
    app.add_plugins((
        MinimalPlugins,
        bevy::transform::TransformPlugin,
        bevy::input::InputPlugin,
        bevy::asset::AssetPlugin {
            file_path: dir.to_string_lossy().into_owned(),
            ..Default::default()
        },
        bevy::text::TextPlugin,
        bevy::picking::PickingPlugin,
        bevy::picking::InteractionPlugin,
        bevy::ui::UiPlugin,
        bevy::world_serialization::WorldSerializationPlugin,
        bevy::state::app::StatesPlugin,
        JackdawPlugin,
    ));
    app.init_asset::<Image>();
    app.init_asset::<TextureAtlasLayout>();
    app.init_asset::<Mesh>();
    app.init_asset::<StandardMaterial>();
    app.register_type::<GameRoot>();
    app.register_type::<MenuRoot>();
    app.register_type::<GameOverRoot>();
    app.register_type::<HudRoot>();
    app.register_type::<GameState>();
    app.register_type::<PlayerHealth>();
    app.register_type::<ScreenPressed>();
    app.register_function(ratio);
    app.insert_resource(BootScene(start.to_string()))
        .init_state::<GameFlow>()
        .insert_state(boot_state(start))
        .add_systems(Startup, spawn_scene)
        .init_resource::<GameConfig>()
        .init_resource::<GameState>()
        .add_observer(on_screen_pressed)
        .add_systems(OnEnter(GameFlow::Menu), enter_menu)
        .add_systems(OnEnter(GameFlow::Level), enter_level)
        .add_systems(OnEnter(GameFlow::Level), (spawn_player, reset_run).chain())
        .add_systems(OnEnter(GameFlow::GameOver), enter_game_over)
        .add_systems(Update, spawn_hud_while_level)
        .add_systems(
            Update,
            (
                wire_hud,
                (apply_health_from_config, update_game_over).chain(),
            ),
        );
    app
}

fn rendered(name: &str) -> String {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/crates/jackdaw_scaffold/templates/game/assets/"
    );
    let raw = std::fs::read_to_string(format!("{path}{name}.template"))
        .or_else(|_| std::fs::read_to_string(format!("{path}{name}")))
        .unwrap_or_else(|error| panic!("the template ships {name}: {error}"));
    raw.replace("{{crate_name}}", "editor::guards::game_flow_template")
        .replace("{{project-name | title_case}}", "Guards")
}

fn write_seeds(dir: &std::path::Path) {
    for name in ["menu.bsn", "scene.bsn", "gameover.bsn", "hud.bsn"] {
        std::fs::write(dir.join(name), rendered(name))
            .unwrap_or_else(|error| panic!("write {name}: {error}"));
    }
}

// ---- Driving helpers ---------------------------------------------------

fn flow_of(app: &mut App) -> GameFlow {
    *app.world().resource::<State<GameFlow>>().get()
}

fn spawned_names(app: &mut App) -> Vec<String> {
    let mut names = app.world_mut().query::<&Name>();
    names
        .iter(app.world())
        .map(|n| n.as_str().to_string())
        .collect()
}

/// Pump updates until `predicate` holds over the spawned names; gives up
/// after ~5 seconds and returns whatever spawned.
fn pump_until(app: &mut App, mut predicate: impl FnMut(&[String]) -> bool) -> Vec<String> {
    for _ in 0..300 {
        app.update();
        let names = spawned_names(app);
        if predicate(&names) {
            return names;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    spawned_names(app)
}

/// Let cleanup, binding evaluation and the state-scoped despawns land.
fn settle(app: &mut App) {
    for _ in 0..3 {
        app.update();
    }
}

fn count_named(app: &mut App, target: &str) -> usize {
    spawned_names(app)
        .into_iter()
        .filter(|name| name == target)
        .count()
}

fn count_cameras(app: &mut App) -> usize {
    let mut cameras = app.world_mut().query::<&Camera2d>();
    cameras.iter(app.world()).count()
}

fn player_entity(app: &mut App) -> Entity {
    let mut players = app.world_mut().query::<(Entity, &PlayerMarker)>();
    players
        .single(app.world())
        .map(|(entity, _)| entity)
        .expect("one template player")
}

fn click(app: &mut App, button: &str) {
    let mut buttons = app.world_mut().query::<(Entity, &Name)>();
    let entity = buttons
        .iter(app.world())
        .find_map(|(entity, name)| (name.as_str() == button).then_some(entity))
        .unwrap_or_else(|| panic!("expected a button named {button}"));
    app.world_mut().trigger(Activate { entity });
    app.update();
}

fn failure_count(app: &mut App) -> usize {
    app.world().resource::<BindFailures>().0.len()
}

/// Failures whose entity is still alive: the ledger keeps the departed
/// hud's counter entry (the no-physics app has no `PickupCount`, and a
/// fresh hud's binding fails again per spawn), so the precise shape is
/// "exactly one live failure while the hud is up, none anywhere else".
fn live_failure_count(app: &mut App) -> usize {
    let mut all = app.world_mut().query::<Entity>();
    let alive: Vec<Entity> = all.iter(app.world()).collect();
    app.world()
        .resource::<BindFailures>()
        .0
        .iter()
        .filter(|(entity, _)| alive.contains(entity))
        .count()
}

/// What one stop in the flow carries: the world's whole entity set, the
/// scene members, the roots and the cameras. `PartialEq` makes the
/// constancy asserts read as one line.
#[derive(Clone, Copy, PartialEq, Debug)]
struct Counts {
    entities: usize,
    members: usize,
    roots: usize,
    cameras: usize,
}

fn counts(app: &mut App) -> Counts {
    let mut all = app.world_mut().query::<Entity>();
    let entities = all.iter(app.world()).count();
    let mut members = app.world_mut().query::<&JackdawSceneMember>();
    let members = members.iter(app.world()).count();
    let mut roots = app.world_mut().query::<&JackdawSceneRoot>();
    let roots = roots.iter(app.world()).count();
    Counts {
        entities,
        members,
        roots,
        cameras: count_cameras(app),
    }
}

// ---- 1. The flow walks the worlds --------------------------------------

#[test]
fn the_flow_walks_the_three_documents_and_back_with_zero_residue() {
    let dir = tempfile::tempdir().expect("tempdir");
    write_seeds(dir.path());

    let mut app = template_app(MENU_SCENE, dir.path());

    // Cycle 1 — shape over counts: the walk's stops each hold exactly
    // their own world, and the survivors are named. (The first cycle
    // also warms the state machine's one-time internals; the count
    // identity below starts from the second.)
    pump_until(&mut app, |names| names.iter().any(|n| n == "MenuRoot"));
    settle(&mut app);
    assert_eq!(
        flow_of(&mut app),
        GameFlow::Menu,
        "a menu start boots as menu"
    );
    assert_eq!(
        count_cameras(&mut app),
        1,
        "the menu world has its UI camera"
    );
    assert_eq!(count_named(&mut app, "HudRoot"), 0, "no hud on the menu");
    assert_eq!(count_named(&mut app, "Sun"), 0, "no level on the menu");
    assert_eq!(
        count_named(&mut app, "GameRoot"),
        1,
        "one root for every world"
    );

    click(&mut app, "StartButton");
    pump_until(&mut app, |names| names.iter().any(|n| n == "Sun"));
    settle(&mut app);
    assert_eq!(
        flow_of(&mut app),
        GameFlow::Level,
        "Start moves to the level"
    );
    assert_eq!(count_named(&mut app, "MenuRoot"), 0, "menu: zero residue");
    assert_eq!(count_named(&mut app, "MenuTitle"), 0, "menu: zero residue");
    assert_eq!(
        count_cameras(&mut app),
        0,
        "the menu camera left with the state"
    );
    assert_eq!(
        count_named(&mut app, "HudRoot"),
        1,
        "the hud rode in with the level"
    );
    assert_eq!(
        count_named(&mut app, "HealthBar"),
        1,
        "the hud's parts arrived"
    );
    assert_eq!(
        failure_count(&mut app),
        1,
        "the one expected failure is the hud's"
    );
    let player = player_entity(&mut app);

    app.world_mut()
        .get_mut::<PlayerHealth>(player)
        .unwrap()
        .current = 0.0;
    pump_until(&mut app, |names| names.iter().any(|n| n == "GameOverRoot"));
    settle(&mut app);
    assert_eq!(
        flow_of(&mut app),
        GameFlow::GameOver,
        "blood out ends the run"
    );
    assert_eq!(count_named(&mut app, "Sun"), 0, "the level world left");
    assert_eq!(
        count_named(&mut app, "HudRoot"),
        0,
        "the hud left with the level"
    );
    assert_eq!(
        count_named(&mut app, "HealthBar"),
        0,
        "the hud's parts left"
    );
    assert_eq!(
        count_cameras(&mut app),
        1,
        "the end screen has its UI camera"
    );

    click(&mut app, "MenuButton");
    pump_until(&mut app, |names| names.iter().any(|n| n == "MenuRoot"));
    settle(&mut app);
    assert_eq!(
        flow_of(&mut app),
        GameFlow::Menu,
        "Menu goes back to the start"
    );
    assert_eq!(
        count_named(&mut app, "GameOverRoot"),
        0,
        "end screen: zero residue"
    );

    // Cycles 2 and 3 — counts: every revisit of every stop lands on
    // exactly the counts of the visit before it, entities, members,
    // roots and cameras alike. A flow that reloads without cleaning up
    // cannot produce this line.
    let mut baselines = [None::<Counts>; 3];
    for cycle in 1..3u8 {
        click(&mut app, "StartButton");
        pump_until(&mut app, |names| names.iter().any(|n| n == "Sun"));
        settle(&mut app);
        assert_eq!(
            count_named(&mut app, "MenuRoot"),
            0,
            "cycle {cycle}: no menu residue"
        );
        assert_eq!(
            live_failure_count(&mut app),
            1,
            "cycle {cycle}: exactly one live failure, the fresh hud's counter"
        );
        let now = counts(&mut app);
        if cycle == 1 {
            baselines[0] = Some(now);
        } else {
            assert_eq!(
                now,
                baselines[0].unwrap(),
                "cycle {cycle} level is cycle 1's level"
            );
        }

        let player_now = player_entity(&mut app);
        assert_eq!(player_now, player, "cycle {cycle}: the same player");
        app.world_mut()
            .get_mut::<PlayerHealth>(player_now)
            .unwrap()
            .current = 0.0;
        pump_until(&mut app, |names| names.iter().any(|n| n == "GameOverRoot"));
        settle(&mut app);
        assert_eq!(
            count_named(&mut app, "Sun"),
            0,
            "cycle {cycle}: no level residue"
        );
        assert_eq!(
            live_failure_count(&mut app),
            0,
            "cycle {cycle}: no live failure off the level"
        );
        let now = counts(&mut app);
        if cycle == 1 {
            baselines[1] = Some(now);
        } else {
            assert_eq!(
                now,
                baselines[1].unwrap(),
                "cycle {cycle} end screen is cycle 1's end screen"
            );
        }

        click(&mut app, "MenuButton");
        pump_until(&mut app, |names| names.iter().any(|n| n == "MenuRoot"));
        settle(&mut app);
        assert_eq!(
            count_named(&mut app, "GameOverRoot"),
            0,
            "cycle {cycle}: no end-screen residue"
        );
        assert_eq!(
            live_failure_count(&mut app),
            0,
            "cycle {cycle}: no live failure on the menu"
        );
        let now = counts(&mut app);
        if cycle == 1 {
            baselines[2] = Some(now);
        } else {
            assert_eq!(
                now,
                baselines[2].unwrap(),
                "cycle {cycle} menu is cycle 1's menu"
            );
        }
    }
    assert_eq!(
        player_entity(&mut app),
        player,
        "one player across the whole walk"
    );
}

// ---- 2. Restart is a switch ---------------------------------------------

#[test]
fn a_restart_lands_the_run_back_where_it_began() {
    let dir = tempfile::tempdir().expect("tempdir");
    write_seeds(dir.path());

    let mut app = template_app(MENU_SCENE, dir.path());
    pump_until(&mut app, |names| names.iter().any(|n| n == "MenuRoot"));
    settle(&mut app);
    click(&mut app, "StartButton");
    pump_until(&mut app, |names| names.iter().any(|n| n == "Sun"));
    settle(&mut app);

    // One player for the whole process: remembered now, checked after
    // every switch below.
    let player = player_entity(&mut app);
    let level_counts = counts(&mut app);

    // Blood out (paused state included — the run ends and clears it).
    app.world_mut().resource_mut::<GameState>().paused = true;
    app.world_mut()
        .get_mut::<PlayerHealth>(player)
        .unwrap()
        .current = 0.0;
    pump_until(&mut app, |names| names.iter().any(|n| n == "GameOverRoot"));
    settle(&mut app);
    assert_eq!(flow_of(&mut app), GameFlow::GameOver);
    assert!(
        !app.world().resource::<GameState>().paused,
        "ending the run drops the pause veil"
    );

    // Drag the player somewhere else and hurt it: restart must undo
    // exactly that, by reset_run, with no new player.
    app.world_mut()
        .get_mut::<PlayerHealth>(player)
        .unwrap()
        .current = 5.0;
    app.world_mut()
        .get_mut::<Transform>(player)
        .unwrap()
        .translation = Vec3::new(9.0, 9.0, 9.0);

    click(&mut app, "RestartButton");
    pump_until(&mut app, |names| names.iter().any(|n| n == "Sun"));
    settle(&mut app);
    assert_eq!(
        flow_of(&mut app),
        GameFlow::Level,
        "Restart re-enters the level"
    );
    assert_eq!(
        player_entity(&mut app),
        player,
        "the player crossed the switch: same entity"
    );
    let health = app.world().get::<PlayerHealth>(player).unwrap();
    assert_eq!(
        health.current, 100.0,
        "reset_run restores the config's health"
    );
    assert_eq!(
        app.world().get::<Transform>(player).unwrap().translation,
        PLAYER_SPAWN,
        "reset_run lands the player where the run began"
    );
    assert_eq!(
        counts(&mut app),
        level_counts,
        "the restarted level is the first level, count for count"
    );
    let mut bars = app
        .world_mut()
        .query::<&jackdaw_widgets_runtime::Progress>();
    let value = bars
        .iter(app.world())
        .map(|bar| bar.value)
        .collect::<Vec<_>>();
    assert_eq!(value, vec![1.0], "the restarted bar reads full health");
}

// ---- 3. The boot state follows the start scene ---------------------------

#[test]
fn the_boot_state_follows_the_start_scene() {
    // The pure mapping the template's build spells.
    assert_eq!(boot_state("menu.bsn"), GameFlow::Menu);
    assert_eq!(boot_state("gameover.bsn"), GameFlow::GameOver);
    assert_eq!(boot_state("scene.bsn"), GameFlow::Level);
    assert_eq!(boot_state("levels/level-2.bsn"), GameFlow::Level);

    let dir = tempfile::tempdir().expect("tempdir");
    write_seeds(dir.path());

    // A game-over start boots onto the end screen: the document the
    // flow file named is the world, the camera is up, nothing else.
    {
        let mut app = template_app(GAME_OVER_SCENE, dir.path());
        pump_until(&mut app, |names| names.iter().any(|n| n == "GameOverRoot"));
        settle(&mut app);
        assert_eq!(flow_of(&mut app), GameFlow::GameOver);
        assert_eq!(count_named(&mut app, "MenuRoot"), 0);
        assert_eq!(count_named(&mut app, "HudRoot"), 0);
        assert_eq!(count_cameras(&mut app), 1);
    }

    // A level start (a Play-Current override lands here too) boots
    // straight into a playable level: the world, the hud, the player —
    // and the level entry ran before Startup had spawned the root,
    // which must be survived without a double spawn or a crash.
    {
        let mut app = template_app(LEVEL_SCENE, dir.path());
        pump_until(&mut app, |names| names.iter().any(|n| n == "Sun"));
        settle(&mut app);
        assert_eq!(flow_of(&mut app), GameFlow::Level);
        assert_eq!(count_named(&mut app, "MenuRoot"), 0);
        assert_eq!(count_named(&mut app, "HudRoot"), 1);
        assert_eq!(count_cameras(&mut app), 0);
        let player = player_entity(&mut app);
        let health = app.world().get::<PlayerHealth>(player).unwrap();
        assert_eq!(
            health.current, 100.0,
            "the frame-one health handoff ran before the game-over check"
        );
        // And the flow keeps working from there: blood out ends this
        // boot too.
        app.world_mut()
            .get_mut::<PlayerHealth>(player)
            .unwrap()
            .current = 0.0;
        pump_until(&mut app, |names| names.iter().any(|n| n == "GameOverRoot"));
        settle(&mut app);
        assert_eq!(flow_of(&mut app), GameFlow::GameOver);
    }
}
