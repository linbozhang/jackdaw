//! The runtime scene switch over the real engine (T13-T1).
//!
//! Five legs over `JackdawPlugin`, mirroring the switch a game makes with
//! one line — `commands.entity(root).insert(JackdawSceneRoot(handle)))` —
//! against three seed documents the way T3's template ships them:
//! `menu.bsn` (UI root, marker, bound bar, Start button), `level.bsn` (a
//! plain world) and `gameover.bsn` (UI root, Restart button). The documents
//! load through the real `AssetServer` from a temp folder, and tests 1-4
//! hold their handles loaded for the whole test on purpose: a switch to an
//! already-loaded scene is the case that separates the primitive from a
//! no-op (a fresh `server.load` right before the insert happens to reload
//! through the asset event path on any runtime, which is the accident this
//! file exists to replace with semantics):
//!
//! * **Zero residue (S2 red→green)**: menu→level and back — the previous
//!   scene's entities (UI roots included) are all gone, the new scene
//!   matches its single-load baseline exactly, the root survives, and
//!   nothing fails to bind.
//! * **Round-trip constancy**: five menu↔level↔gameover cycles land on
//!   per-stop counts identical to the first visit — the signature a
//!   reload-without-cleanup bug cannot produce.
//! * **One click is one event**: an `Activate` sends exactly one
//!   `ScreenPressed` per press, across freshly respawned buttons too (the
//!   `STAND_PAUSE_SINGLE` net-zero signature, carried across scene switches).
//! * **Bindings rewire**: the wire-context pattern re-lands on the newly
//!   spawned scene, the bar follows a changed value, and no stale context
//!   survives.
//! * **A broken target refuses loudly**: a missing or unparseable target
//!   leaves `SceneRefused` on the root, the log names the target, the
//!   previous scene still left, and a later rebind to a good scene
//!   recovers; a still-loading target neither panics nor wedges.

use std::sync::{Arc, Mutex};

use bevy::asset::LoadState;
use bevy::prelude::*;
use bevy::ui_widgets::Activate;
use jackdaw_bind::BindFailures;
use jackdaw_runtime::JackdawScene;
use jackdaw_runtime::prelude::*;
use tracing::Subscriber;
use tracing::field::Visit;
use tracing_subscriber::layer::Layer;
use tracing_subscriber::prelude::*;

// ---- The flow-facing types a template game registers ------------------

/// The menu document's marker (`MenuRoot` in the T13 seeds).
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct MenuRoot;

/// The game-over document's marker.
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct GameOverRoot;

/// The level document's marker (a plain world, no UI).
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct LevelMarker;

/// The player the menu's bar reads, spawned in code and therefore
/// cross-scene by construction.
#[derive(Component, Reflect, Default)]
#[reflect(Component)]
struct PlayerMarker;

/// The live health the menu's bar binds (`PlayerHealth` in the template).
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct PlayerHealth {
    current: f32,
    max: f32,
}

/// What a flow button says (template `ScreenPressed`).
#[derive(Event, Reflect, Clone, Default)]
#[reflect(Event, Default)]
struct ScreenPressed {
    button: String,
}

/// Every `ScreenPressed` the app has seen, in order.
#[derive(Resource, Default)]
struct Presses(Vec<String>);

fn ratio(current: f32, max: f32) -> f32 {
    (current / max).clamp(0.0, 1.0)
}

/// Template `wire_hud`, spelled for the menu document: the marker lookup
/// plus the context insert, re-firing for every freshly spawned menu.
fn wire_menu(
    mut commands: Commands,
    menus: Query<Entity, Added<MenuRoot>>,
    players: Query<Entity, With<PlayerMarker>>,
) {
    let (Ok(root), Ok(player)) = (menus.single(), players.single()) else {
        return;
    };
    commands.entity(root).insert(BindContext(player));
}

fn on_screen_pressed(press: On<ScreenPressed>, mut presses: ResMut<Presses>) {
    presses.0.push(press.event().button.clone());
}

// ---- The app and the seeds -------------------------------------------

/// The engine under a game: the pieces `main.rs.template`'s `DefaultPlugins`
/// provide headless, plus `JackdawPlugin`, with assets read from `dir` so
/// every test owns its scene files.
fn flow_app(dir: &std::path::Path) -> App {
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
        JackdawPlugin,
    ));
    app.init_asset::<Image>();
    app.init_asset::<TextureAtlasLayout>();
    app.register_type::<MenuRoot>();
    app.register_type::<GameOverRoot>();
    app.register_type::<LevelMarker>();
    app.register_type::<PlayerHealth>();
    app.register_type::<ScreenPressed>();
    app.register_function(ratio);
    app.init_resource::<Presses>();
    app
}

const MENU_BSN: &str = r#"
#MenuRoot
jackdaw_scene_types::UiSceneRoot
guards::game_flow::MenuRoot
bevy_ui::ui_node::Node {
    width: bevy_ui::geometry::Val::Percent(100.0),
    height: bevy_ui::geometry::Val::Percent(100.0),
}
bevy_ecs::hierarchy::Children [
    #MenuTitle
    bevy_ui::widget::text::Text("Menu")
    bevy_feathers::theme::ThemedText
    --
    #HealthBar
    bevy_ui::ui_node::Node {
        width: bevy_ui::geometry::Val::Px(180.0),
        height: bevy_ui::geometry::Val::Px(10.0),
    }
    jackdaw_widgets_runtime::Progress {
        value: 1.0,
    }
    jackdaw_bind::types::Bindings([jackdaw_bind::types::Binding::Field { read: [jackdaw_bind::types::BindPath { raw: "guards::game_flow::PlayerHealth.current" }, jackdaw_bind::types::BindPath { raw: "guards::game_flow::PlayerHealth.max" }], via: core::option::Option::Some("ratio"), write: jackdaw_bind::types::BindPath { raw: "jackdaw_widgets_runtime::Progress.value" }, as_percent: false }])
    --
    #HealthText
    bevy_ui::widget::text::Text("100 / 100")
    bevy_feathers::theme::ThemedText
    jackdaw_bind::types::Bindings([jackdaw_bind::types::Binding::Text { format: "{} / {}", args: [jackdaw_bind::types::BindPath { raw: "guards::game_flow::PlayerHealth.current" }, jackdaw_bind::types::BindPath { raw: "guards::game_flow::PlayerHealth.max" }] }])
    --
    #StartButton
    bevy_ui::ui_node::Node {
        min_width: bevy_ui::geometry::Val::Px(96.0),
        min_height: bevy_ui::geometry::Val::Px(32.0),
    }
    bevy_ui_widgets::button::Button
    jackdaw_bind::types::Bindings([jackdaw_bind::types::Binding::Action { event: "guards::game_flow::ScreenPressed", fields: [], literals: [["button", "start"]] }])
    bevy_ecs::hierarchy::Children [
        #StartCaption
        bevy_ui::widget::text::Text("Start")
        bevy_feathers::theme::ThemedText
    ]
]
"#;

const LEVEL_BSN: &str = r#"
#LevelRoot
guards::game_flow::LevelMarker
bevy_ecs::hierarchy::Children [
    #LevelPickup
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: 1.0, y: 0.0, z: 0.0 },
    }
    --
    #LevelHazard
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: -3.0, y: 0.0, z: 0.0 },
    }
]
"#;

const GAMEOVER_BSN: &str = r#"
#GameOverRoot
jackdaw_scene_types::UiSceneRoot
guards::game_flow::GameOverRoot
bevy_ui::ui_node::Node {
    width: bevy_ui::geometry::Val::Percent(100.0),
    height: bevy_ui::geometry::Val::Percent(100.0),
}
bevy_ecs::hierarchy::Children [
    #GameOverTitle
    bevy_ui::widget::text::Text("Game Over")
    bevy_feathers::theme::ThemedText
    --
    #RestartButton
    bevy_ui::ui_node::Node {
        min_width: bevy_ui::geometry::Val::Px(96.0),
        min_height: bevy_ui::geometry::Val::Px(32.0),
    }
    bevy_ui_widgets::button::Button
    jackdaw_bind::types::Bindings([jackdaw_bind::types::Binding::Action { event: "guards::game_flow::ScreenPressed", fields: [], literals: [["button", "restart"]] }])
]
"#;

/// The fourth leg-5 document: never loaded until its switch, so the switch
/// lands while the target is still loading.
const LATE_BSN: &str = r#"
#LateRoot
bevy_transform::components::transform::Transform
"#;

fn write_seeds(dir: &std::path::Path) {
    for (name, text) in [
        ("menu.bsn", MENU_BSN),
        ("level.bsn", LEVEL_BSN),
        ("gameover.bsn", GAMEOVER_BSN),
        ("late.bsn", LATE_BSN),
    ] {
        std::fs::write(dir.join(name), text)
            .unwrap_or_else(|error| panic!("write {name}: {error}"));
    }
}

// ---- Driving helpers ---------------------------------------------------

/// Spawn the scene root the way a game's one startup line does.
fn spawn_root(app: &mut App, path: &str) -> Entity {
    let handle = app
        .world()
        .resource::<AssetServer>()
        .load::<JackdawScene>(path.to_string());
    app.world_mut().spawn(JackdawSceneRoot(handle)).id()
}

/// The game's own scene handles, loaded once and held for the whole test:
/// a switch to any of them targets an already-loaded scene, which is the
/// primitive's whole job. Order: menu, level, gameover.
fn flow_handles(app: &mut App) -> [Handle<JackdawScene>; 3] {
    let handles: Vec<Handle<JackdawScene>> = ["menu.bsn", "level.bsn", "gameover.bsn"]
        .iter()
        .map(|path| {
            app.world()
                .resource::<AssetServer>()
                .load::<JackdawScene>(path.to_string())
        })
        .collect();
    let handles: [Handle<JackdawScene>; 3] = handles.try_into().expect("three scenes");
    for _ in 0..300 {
        app.update();
        let server = app.world().resource::<AssetServer>();
        if handles
            .iter()
            .all(|handle| matches!(server.get_load_state(handle), Some(LoadState::Loaded)))
        {
            return handles;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    panic!("the flow scenes never finished loading");
}

/// The switch itself: rebind the root's handle — the whole game-side API.
fn rebind(app: &mut App, root: Entity, handle: &Handle<JackdawScene>) {
    app.world_mut()
        .entity_mut(root)
        .insert(JackdawSceneRoot(handle.clone()));
}

/// The switch by path, for targets a game loads on demand (the broken and
/// in-flight legs): a fresh load call, then the same one-line rebind.
fn rebind_path(app: &mut App, root: Entity, path: &str) {
    let handle = app
        .world()
        .resource::<AssetServer>()
        .load::<JackdawScene>(path.to_string());
    app.world_mut()
        .entity_mut(root)
        .insert(JackdawSceneRoot(handle));
}

fn spawn_player(app: &mut App, health: PlayerHealth) -> Entity {
    app.world_mut()
        .spawn((PlayerMarker, health, Transform::default()))
        .id()
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

/// Pump until some scene root carries `SceneRefused`.
fn pump_until_refused(app: &mut App) -> bool {
    for _ in 0..300 {
        app.update();
        let mut refused = app.world_mut().query::<&SceneRefused>();
        if refused.iter(app.world()).next().is_some() {
            return true;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    false
}

/// Let cleanup, binding evaluation and the widget pass land.
fn settle(app: &mut App) {
    for _ in 0..3 {
        app.update();
    }
}

/// How many spawned entities carry this authored name.
fn count_named(app: &mut App, target: &str) -> usize {
    spawned_names(app)
        .into_iter()
        .filter(|name| name == target)
        .count()
}

fn named(app: &mut World, target: &str) -> Entity {
    let mut names = app.query::<(Entity, &Name)>();
    names
        .iter(app)
        .find_map(|(entity, name)| (name.as_str() == target).then_some(entity))
        .unwrap_or_else(|| panic!("expected entity named {target}"))
}

fn failure_count(app: &mut App) -> usize {
    app.world().resource::<BindFailures>().0.len()
}

/// What a full world carries that a scene switch can disturb: the entity
/// total, the scene members, the roots, the loaded scene assets and the
/// catalog. `PartialEq` makes the constancy asserts read as one line.
#[derive(Clone, Copy, PartialEq, Debug)]
struct Counts {
    entities: usize,
    members: usize,
    roots: usize,
    scenes: usize,
    catalog: usize,
}

/// The scene-borne slice of [`Counts`]: what a switch must land on exactly
/// when compared against a fresh app's single load. The asset and catalog
/// store sizes are not scene-borne — a game that holds handles for scenes
/// it has not switched to yet simply has more of them.
fn scene_counts(counts: Counts) -> (usize, usize, usize) {
    (counts.entities, counts.members, counts.roots)
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
        scenes: app.world().resource::<Assets<JackdawScene>>().len(),
        catalog: app.world().resource::<JackdawCatalog>().len(),
    }
}

/// What `path` loads to in a fresh app with nothing but it: the single-load
/// baseline a switch must land on exactly.
fn single_load_counts(dir: &std::path::Path, path: &str, root_name: &str) -> Counts {
    let mut app = flow_app(dir);
    spawn_player(
        &mut app,
        PlayerHealth {
            current: 70.0,
            max: 100.0,
        },
    );
    app.add_systems(Update, wire_menu);
    spawn_root(&mut app, path);
    pump_until(&mut app, |names| names.iter().any(|n| n == root_name));
    settle(&mut app);
    counts(&mut app)
}

fn click(app: &mut App, button: &str) {
    let world = app.world_mut();
    let entity = named(world, button);
    app.world_mut().trigger(Activate { entity });
    app.update();
}

// ---- 1. Zero residue, both directions ---------------------------------

#[test]
fn a_switch_leaves_zero_residue_in_both_directions() {
    let dir = tempfile::tempdir().expect("tempdir");
    write_seeds(dir.path());
    let menu_baseline = single_load_counts(dir.path(), "menu.bsn", "MenuRoot");
    let level_baseline = single_load_counts(dir.path(), "level.bsn", "LevelRoot");

    let mut app = flow_app(dir.path());
    spawn_player(
        &mut app,
        PlayerHealth {
            current: 70.0,
            max: 100.0,
        },
    );
    app.add_systems(Update, wire_menu);
    let handles = flow_handles(&mut app);
    let root = spawn_root(&mut app, "menu.bsn");
    pump_until(&mut app, |names| names.iter().any(|n| n == "MenuRoot"));
    settle(&mut app);
    assert_eq!(
        scene_counts(counts(&mut app)),
        scene_counts(menu_baseline),
        "the first load is the single-load baseline"
    );
    assert_eq!(failure_count(&mut app), 0, "the menu's bindings resolved");

    // menu → level: every menu entity is gone, including the unparented UI
    // root, and the level lands exactly on its own baseline.
    rebind(&mut app, root, &handles[1]);
    pump_until(&mut app, |names| names.iter().any(|n| n == "LevelRoot"));
    settle(&mut app);
    for name in [
        "MenuRoot",
        "MenuTitle",
        "HealthBar",
        "HealthText",
        "StartButton",
        "StartCaption",
    ] {
        assert_eq!(
            count_named(&mut app, name),
            0,
            "{name} must leave zero residue behind the switch"
        );
    }
    for name in ["LevelRoot", "LevelPickup", "LevelHazard"] {
        assert_eq!(count_named(&mut app, name), 1, "{name} is present once");
    }
    assert_eq!(
        scene_counts(counts(&mut app)),
        scene_counts(level_baseline),
        "the level matches its single-load baseline"
    );
    assert_eq!(
        failure_count(&mut app),
        0,
        "no binding of the departed menu is left failing"
    );
    assert!(
        app.world().get_entity(root).is_ok(),
        "the root entity survives the switch"
    );

    // level → menu, the same assertions in reverse: no level residue, the
    // menu back at its baseline, no growth from the reload.
    rebind(&mut app, root, &handles[0]);
    pump_until(&mut app, |names| names.iter().any(|n| n == "MenuRoot"));
    settle(&mut app);
    for name in ["LevelRoot", "LevelPickup", "LevelHazard"] {
        assert_eq!(
            count_named(&mut app, name),
            0,
            "{name} must leave zero residue behind the switch back"
        );
    }
    for name in ["MenuRoot", "MenuTitle", "StartButton"] {
        assert_eq!(count_named(&mut app, name), 1, "{name} is present once");
    }
    assert_eq!(
        scene_counts(counts(&mut app)),
        scene_counts(menu_baseline),
        "the reloaded menu matches its baseline (no growth)"
    );
    assert_eq!(failure_count(&mut app), 0);
}

// ---- 2. Five round trips, identical counts ----------------------------

#[test]
fn five_round_trips_land_on_identical_counts() {
    let dir = tempfile::tempdir().expect("tempdir");
    write_seeds(dir.path());

    let mut app = flow_app(dir.path());
    spawn_player(
        &mut app,
        PlayerHealth {
            current: 70.0,
            max: 100.0,
        },
    );
    let handles = flow_handles(&mut app);
    let root = spawn_root(&mut app, "menu.bsn");

    let root_names = ["MenuRoot", "LevelRoot", "GameOverRoot"];
    let mut first_stop = [None::<Counts>, None, None];

    for round in 0..5u8 {
        for (stop, root_name) in root_names.iter().enumerate() {
            if !(round == 0 && stop == 0) {
                rebind(&mut app, root, &handles[stop]);
            }
            pump_until(&mut app, |names| names.iter().any(|n| n == root_name));
            settle(&mut app);
            for (other, other_root) in root_names.iter().enumerate() {
                let hits = count_named(&mut app, other_root);
                if other == stop {
                    assert_eq!(hits, 1, "{other_root} is up once at {root_name}");
                } else {
                    assert_eq!(
                        hits, 0,
                        "{other_root} must not outlive its scene at {root_name}"
                    );
                }
            }
            let now = counts(&mut app);
            match first_stop[stop] {
                Some(first) => {
                    assert_eq!(
                        now, first,
                        "round {round} revisit of {root_name} must count identically to the first visit"
                    );
                }
                None => first_stop[stop] = Some(now),
            }
        }
    }
}

// ---- 3. One click is one event ----------------------------------------

#[test]
fn one_click_is_one_event_across_scene_reloads() {
    let dir = tempfile::tempdir().expect("tempdir");
    write_seeds(dir.path());

    let mut app = flow_app(dir.path());
    spawn_player(&mut app, PlayerHealth::default());
    app.add_observer(on_screen_pressed);
    let handles = flow_handles(&mut app);
    let root = spawn_root(&mut app, "menu.bsn");
    pump_until(&mut app, |names| names.iter().any(|n| n == "MenuRoot"));
    settle(&mut app);

    let presses = |app: &mut App| app.world().resource::<Presses>().0.clone();
    click(&mut app, "StartButton");
    assert_eq!(presses(&mut app), vec!["start".to_string()]);

    // The menu reloads twice; every freshly spawned button still forwards
    // exactly one event per click — never two (the double-registration
    // signature) and never zero.
    for round in 0..2 {
        rebind(&mut app, root, &handles[1]);
        pump_until(&mut app, |names| names.iter().any(|n| n == "LevelRoot"));
        settle(&mut app);
        rebind(&mut app, root, &handles[0]);
        pump_until(&mut app, |names| names.iter().any(|n| n == "MenuRoot"));
        settle(&mut app);
        click(&mut app, "StartButton");
        assert_eq!(
            presses(&mut app),
            vec!["start".to_string(); round + 2],
            "one click after reload {round} is exactly one event"
        );
    }
}

// ---- 4. Bindings rewire onto the fresh scene ---------------------------

#[test]
fn bindings_rewire_onto_the_freshly_spawned_scene() {
    let dir = tempfile::tempdir().expect("tempdir");
    write_seeds(dir.path());

    let mut app = flow_app(dir.path());
    let player = spawn_player(
        &mut app,
        PlayerHealth {
            current: 70.0,
            max: 100.0,
        },
    );
    app.add_systems(Update, wire_menu);
    let handles = flow_handles(&mut app);
    let root = spawn_root(&mut app, "menu.bsn");
    pump_until(&mut app, |names| names.iter().any(|n| n == "MenuRoot"));
    settle(&mut app);

    let first_menu = named(app.world_mut(), "MenuRoot");
    assert_eq!(
        app.world().get::<BindContext>(first_menu).map(|c| c.0),
        Some(player),
        "wire_menu put the player's context on the menu"
    );
    let bar = named(app.world_mut(), "HealthBar");
    assert_eq!(
        app.world()
            .get::<jackdaw_widgets_runtime::Progress>(bar)
            .unwrap()
            .value,
        0.7,
        "the bar follows the player's health"
    );

    // Away and back: the context re-lands on the new menu, the bar reads a
    // value that changed while the menu was away (fresh evaluation, not a
    // stale one), and no stale root or context survives.
    rebind(&mut app, root, &handles[1]);
    pump_until(&mut app, |names| names.iter().any(|n| n == "LevelRoot"));
    settle(&mut app);
    assert!(
        app.world().get_entity(first_menu).is_err(),
        "the first menu (and its context with it) is gone"
    );
    app.world_mut()
        .get_mut::<PlayerHealth>(player)
        .unwrap()
        .current = 40.0;

    rebind(&mut app, root, &handles[0]);
    pump_until(&mut app, |names| names.iter().any(|n| n == "MenuRoot"));
    settle(&mut app);

    let fresh_menu = named(app.world_mut(), "MenuRoot");
    assert_ne!(
        fresh_menu, first_menu,
        "the menu that came back is a freshly spawned scene"
    );
    assert_eq!(
        app.world().get::<BindContext>(fresh_menu).map(|c| c.0),
        Some(player),
        "wire_menu rewired the fresh menu to the same cross-scene player"
    );
    let fresh_bar = named(app.world_mut(), "HealthBar");
    assert_eq!(
        app.world()
            .get::<jackdaw_widgets_runtime::Progress>(fresh_bar)
            .unwrap()
            .value,
        0.4,
        "the fresh bar evaluates the health that changed while the menu was away"
    );
    let text = named(app.world_mut(), "HealthText");
    assert_eq!(
        app.world().get::<Text>(text).unwrap().0.clone(),
        "40 / 100",
        "the fresh text formats the same numbers"
    );
    assert_eq!(
        failure_count(&mut app),
        0,
        "every binding resolved on the fresh instance"
    );
}

// ---- 5. A broken target refuses loudly --------------------------------

/// A thread-local tracing layer that keeps every event's message (the
/// `field_targeting` shape): the refusal warn is part of the deliverable.
struct Messages(Arc<Mutex<Vec<String>>>);

impl<S: Subscriber> Layer<S> for Messages {
    fn on_event(
        &self,
        event: &tracing::Event<'_>,
        _ctx: tracing_subscriber::layer::Context<'_, S>,
    ) {
        let mut message = String::new();
        event.record(&mut Collector(&mut message));
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .push(message);
    }
}

/// Collects the formatted `message` field of one event.
struct Collector<'a>(&'a mut String);

impl Visit for Collector<'_> {
    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
        if field.name() == "message" {
            self.0.push_str(&format!("{value:?}"));
        }
    }
}

/// An entity patch that opens and never closes: the loader refuses it.
const BROKEN_BSN: &str = "#Anchor\nbevy_transform::components::transform::Transform {\n";

#[test]
fn a_broken_target_refuses_loudly_and_recovers() {
    let dir = tempfile::tempdir().expect("tempdir");
    write_seeds(dir.path());
    std::fs::write(dir.path().join("broken.bsn"), BROKEN_BSN).expect("write broken.bsn");

    let mut app = flow_app(dir.path());
    spawn_player(&mut app, PlayerHealth::default());
    let root = spawn_root(&mut app, "level.bsn");
    pump_until(&mut app, |names| names.iter().any(|n| n == "LevelRoot"));
    settle(&mut app);

    let sink = Arc::new(Mutex::new(Vec::new()));
    let subscriber = tracing_subscriber::registry().with(Messages(Arc::clone(&sink)));

    tracing::subscriber::with_default(subscriber, || {
        // A target that is not on disk at all: the previous scene still
        // leaves, the root says it was refused, and the log names the
        // target — S8's runtime half.
        rebind_path(&mut app, root, "missing.bsn");
        assert!(
            pump_until_refused(&mut app),
            "the refused switch says so on the root"
        );
        // A target that exists but does not parse: refused the same way.
        rebind_path(&mut app, root, "broken.bsn");
        settle(&mut app);
        assert!(
            pump_until_refused(&mut app),
            "the unparseable target refuses too"
        );

        let messages = sink
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .join("\n");
        assert!(
            messages.contains("missing.bsn"),
            "the refusal warns with the target's name, but the log said:\n{messages}"
        );
    });
    for name in ["LevelRoot", "LevelPickup", "LevelHazard"] {
        assert_eq!(
            count_named(&mut app, name),
            0,
            "{name}: the refused switch still unloads the previous scene"
        );
    }
    assert_eq!(failure_count(&mut app), 0, "no bindings live to fail");
    assert!(
        app.world().get_entity(root).is_ok(),
        "the root survives a refused switch"
    );

    // Recovery: a rebind to a good scene clears the refusal and spawns.
    rebind_path(&mut app, root, "level.bsn");
    pump_until(&mut app, |names| names.iter().any(|n| n == "LevelRoot"));
    settle(&mut app);
    assert!(
        app.world().get::<SceneRefused>(root).is_none(),
        "the refusal describes one load attempt; the next load removes it"
    );

    // A target that is still loading when the switch lands: no panic, and
    // the scene spawns once it is ready.
    rebind_path(&mut app, root, "late.bsn");
    app.update();
    app.update();
    pump_until(&mut app, |names| names.iter().any(|n| n == "LateRoot"));
    settle(&mut app);
    assert_eq!(
        count_named(&mut app, "LateRoot"),
        1,
        "the late target lands"
    );
}
