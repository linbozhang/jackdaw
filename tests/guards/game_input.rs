//! The editor↔game contract for the action table: a rebinding saved
//! by the editor's own asset writer (`write_asset_file`, the
//! `asset.save` path) loads back through the game's walk and drives
//! the actions it names, while the actions it omits keep the built-in
//! defaults (the union merge). This is the editable-bindings half of
//! T09's acceptance at the mechanism layer: rebinding is editing this
//! file, and bevy's own reflected input types carry the values.

use std::path::Path;

use bevy::asset::{AssetApp, ReflectAsset};
use bevy::input::keyboard::KeyCode;
use bevy::prelude::*;
use jackdaw::asset_index::AssetValue;
use jackdaw::definition_assets::write_asset_file;
use jackdaw_runtime::{
    ConfigPlugin, GameActionDef, GameActionKind, GameInputBinding, GameInputConfig,
    InputActionsPlugin, JackdawCatalog, merge_actions,
};

use crate::util;

/// A rebind worth round-tripping: Move moves from WASD to the arrow
/// keys with a left-stick axis at a distinctive deadzone, Jump keeps
/// its shape but lands on a mouse button. Saving goes through the
/// editor's real writer, so what this proves includes that bevy's own
/// input types survive the editor's value model.
fn rebinding() -> GameInputConfig {
    GameInputConfig {
        actions: vec![
            GameActionDef {
                name: "Move".into(),
                kind: GameActionKind::Axis2D,
                bindings: vec![
                    GameInputBinding::Key(KeyCode::ArrowUp),
                    GameInputBinding::Key(KeyCode::ArrowDown),
                    GameInputBinding::Key(KeyCode::ArrowLeft),
                    GameInputBinding::Key(KeyCode::ArrowRight),
                    GameInputBinding::GamepadAxis {
                        axis: bevy::input::gamepad::GamepadAxis::LeftStickX,
                        deadzone: 0.5,
                    },
                ],
            },
            GameActionDef {
                name: "Jump".into(),
                kind: GameActionKind::Button,
                bindings: vec![GameInputBinding::MouseButton(
                    bevy::input::mouse::MouseButton::Left,
                )],
            },
        ],
    }
}

/// The editor side: the rebinding value, written the way `asset.save`
/// writes it — the real writer, the real handle, the real file form.
fn editor_saves_rebinding(assets: &Path) {
    let mut app = util::editor_test_app();
    app.init_asset::<GameInputConfig>()
        .register_asset_reflect::<GameInputConfig>();
    let world = app.world_mut();
    let value = rebinding();
    let registry = world
        .resource::<bevy::ecs::reflect::AppTypeRegistry>()
        .clone();
    let handle = {
        let registry = registry.read();
        let registration = registry
            .get_with_type_path(std::any::type_name::<GameInputConfig>())
            .expect("the type registered");
        let reflect_asset = registration.data::<ReflectAsset>().expect("as an asset");
        reflect_asset.add(world, &value)
    };
    write_asset_file(
        world,
        "input-actions",
        &AssetValue::Handle(handle),
        &assets.join("input-actions.bsn"),
    )
    .expect("the editor saves the rebinding");
}

/// The game side of the round trip: an app with the actions plugin and
/// the config loader, the asset walked into the catalog (what
/// `JackdawPlugin`'s walk does for this file), then updates.
fn game_app(assets: &Path) -> App {
    let mut app = App::new();
    app.add_plugins((
        bevy::app::TaskPoolPlugin::default(),
        bevy::input::InputPlugin,
        bevy::asset::AssetPlugin::default(),
    ));
    app.init_asset::<GameInputConfig>()
        .register_asset_reflect::<GameInputConfig>();
    app.init_resource::<JackdawCatalog>();
    app.add_plugins(InputActionsPlugin);
    // The template's own line: the config plugin injects the file's
    // value into the resource after the walk.
    app.add_plugins(ConfigPlugin::<GameInputConfig>::new("input-actions.bsn"));
    app.update();
    {
        let world = app.world_mut();
        let text = std::fs::read_to_string(assets.join("input-actions.bsn")).expect("the file");
        let ast = jackdaw_bsn::parse_bsn_text(&text).expect("the editor's form parses");
        let root = ast.roots.first().copied().expect("a root");
        let handle = jackdaw_bsn::load_asset_root(world, &ast, root).expect("the asset loads");
        world
            .resource_mut::<JackdawCatalog>()
            .register_file("input-actions.bsn", handle);
        world.insert_resource(jackdaw_runtime::AssetsWalked);
    }
    app.update();
    app
}

fn press(app: &mut App, code: KeyCode) {
    app.world_mut()
        .write_message(bevy::input::keyboard::KeyboardInput {
            key_code: code,
            logical_key: bevy::input::keyboard::Key::Character("k".into()),
            state: bevy::input::ButtonState::Pressed,
            window: Entity::PLACEHOLDER,
            repeat: false,
            text: None,
        });
}

/// A rebinding the editor saved reaches the game: the file's Move
/// (arrow keys) drives Move, the file's W-less table no longer reads
/// W, and the omitted actions keep their built-in bindings. This is
/// the round-trip T09's acceptance rides on: edit the file, save,
/// play — the actions follow.
#[test]
fn a_rebinding_file_drives_the_actions_it_names() {
    let tmp = tempfile::tempdir().expect("tempdir");
    let assets = tmp.path().join("assets");
    std::fs::create_dir_all(&assets).expect("assets dir");
    editor_saves_rebinding(&assets);

    let mut app = game_app(&assets);

    // The file's binding drives the action.
    press(&mut app, KeyCode::ArrowUp);
    app.update();
    assert!(
        app.world()
            .resource::<jackdaw_runtime::GameActions>()
            .pressed("Move"),
        "the file's ArrowUp holds Move down"
    );
    // The built-in binding no longer does: the file replaced Move.
    let mut app2 = game_app(&assets);
    press(&mut app2, KeyCode::KeyW);
    app2.update();
    assert!(
        !app2
            .world()
            .resource::<jackdaw_runtime::GameActions>()
            .pressed("Move"),
        "W is no longer Move — the file's table won"
    );
    // The omitted actions keep the built-in bindings.
    press(&mut app2, KeyCode::Escape);
    app2.update();
    assert!(
        app2.world()
            .resource::<jackdaw_runtime::GameActions>()
            .pressed("Pause"),
        "Pause keeps its built-in Escape (union merge)"
    );
}

/// The reflection round trip alone, named: bevy's input types (key
/// codes, mouse buttons, gamepad buttons and axes) survive
/// `BsnValue::from_reflect` — the editor card's value model — and
/// rebuild into the same value through the loader's own reflect
/// constructor. Without this, the card could display a rebinding it
/// cannot save.
#[test]
fn bevy_input_types_survive_the_editors_value_model() {
    let mut registry = bevy::reflect::TypeRegistry::new();
    registry.register::<GameInputConfig>();
    let value = rebinding();
    let bsn = jackdaw_bsn::BsnValue::from_reflect(&value, &registry);
    let rebuilt = jackdaw_bsn::apply::bsn_value_to_reflect(
        &bsn,
        std::any::TypeId::of::<GameInputConfig>(),
        &registry,
        None,
    )
    .and_then(|reflected| GameInputConfig::from_reflect(&*reflected))
    .expect("the value model rebuilds the config");
    assert_eq!(rebuilt, value, "the round trip is lossless");
}

/// The union merge rules on the wire: a file naming Move and Jump
/// replaces both (kind and bindings from the file) and the other
/// three built-ins stand; the file's deadzone rides along in the
/// binding (the deadzone-to-settings leg has its own runtime test).
#[test]
fn a_partial_file_merges_and_carries_its_deadzone() {
    let file = rebinding();
    let merged = merge_actions(&GameInputConfig::defaults().actions, &file.actions);
    assert_eq!(
        merged.len(),
        5,
        "five actions: two from the file, three built-in"
    );
    let r#move = merged.iter().find(|d| d.name == "Move").unwrap();
    assert_eq!(
        r#move.bindings[0],
        GameInputBinding::Key(KeyCode::ArrowUp),
        "the file's binding won"
    );
    assert!(
        r#move
            .bindings
            .iter()
            .any(|b| matches!(b, GameInputBinding::GamepadAxis { deadzone: 0.5, .. })),
        "the file's deadzone traveled with the binding"
    );
    let jump = merged.iter().find(|d| d.name == "Jump").unwrap();
    assert_eq!(
        jump.bindings,
        vec![GameInputBinding::MouseButton(
            bevy::input::mouse::MouseButton::Left
        )],
        "Jump came wholly from the file"
    );
    let pause = merged.iter().find(|d| d.name == "Pause").unwrap();
    assert_eq!(
        pause,
        &GameInputConfig::defaults().actions[4],
        "Pause is untouched"
    );
}

/// The deadzone leg, file-driven: the editor saved a 0.5 deadzone on
/// Move's left-stick binding; once the game walks the file in, that
/// number sits in the engine's per-gamepad `GamepadSettings`, where
/// the engine itself filters the axis before any reader sees it. A
/// deadzone on the card is not decoration — it is the axis's filter,
/// and it beats the engine's built-in 0.15.
#[test]
fn the_files_deadzone_reaches_the_engine_gamepad_settings() {
    let tmp = tempfile::tempdir().expect("tempdir");
    let assets = tmp.path().join("assets");
    std::fs::create_dir_all(&assets).expect("assets dir");
    editor_saves_rebinding(&assets);

    let mut app = game_app(&assets);
    // The gamepad the engine would spawn on connection; the settings
    // are per-device components.
    app.world_mut()
        .spawn(bevy::input::gamepad::GamepadSettings::default());
    app.update();

    let mut query = app
        .world_mut()
        .query::<&bevy::input::gamepad::GamepadSettings>();
    let settings = query.single(app.world()).expect("the gamepad");
    let left_x = settings
        .axis_settings
        .get(&bevy::input::gamepad::GamepadAxis::LeftStickX)
        .cloned()
        .expect("the file's binding installed settings for its axis");
    assert_eq!(left_x.deadzone_lowerbound(), -0.5);
    assert_eq!(left_x.deadzone_upperbound(), 0.5);
    assert_eq!(
        settings.axis_settings.len(),
        1,
        "only the file's axis carries explicit settings; the rest ride the engine default"
    );
}

/// The runtime's config asset family must clear the schema's crate
/// filter: `GameInputConfig` lives in `jackdaw_runtime` — an
/// engine-prefixed crate the extractor used to skip wholesale — but it
/// is exactly the type the New Asset flow creates `input-actions.bsn`
/// from; the whole rebind path starts there. The resource mark is the
/// family's tell (the `ConfigPlugin` family is Asset + Resource), and
/// the binding enum the list holds is walked so the card can edit it.
#[test]
fn the_runtime_config_assets_reach_the_new_asset_list() {
    let mut registry = bevy::reflect::TypeRegistry::new();
    registry.register::<GameInputConfig>();
    registry.register_type_data::<GameInputConfig, bevy::asset::ReflectAsset>();
    let assets = jackdaw_schema::extract_asset_types(&registry);
    let paths: Vec<&str> = assets.iter().map(|s| s.type_path.as_str()).collect();
    assert!(
        paths.iter().any(|p| p.ends_with("GameInputConfig")),
        "the runtime's config asset clears the crate filter: {paths:?}"
    );
    assert!(
        paths.iter().any(|p| p.ends_with("GameInputBinding")),
        "the binding enum is described for the card: {paths:?}"
    );
}

/// The editor's writer lands the on-disk form the game reads: the
/// header names the runtime type, the rebinding body is in the text,
/// and that exact file drives the game when read back.
#[test]
fn the_editors_writer_lands_the_same_form_the_game_reads() {
    let tmp = tempfile::tempdir().expect("tempdir");
    let assets = tmp.path().join("assets");
    std::fs::create_dir_all(&assets).expect("assets dir");
    editor_saves_rebinding(&assets);

    let text = std::fs::read_to_string(assets.join("input-actions.bsn")).expect("the file");
    assert!(
        text.contains("jackdaw_runtime::game_input::GameInputConfig"),
        "the header names the type: {text}"
    );
    assert!(text.contains("Move"), "the rebinding body is there: {text}");
    assert!(
        text.contains("LeftStickX"),
        "the gamepad axis binding is in the file: {text}"
    );

    // And the game reads that exact file back.
    let mut game = game_app(&assets);
    press(&mut game, KeyCode::ArrowUp);
    game.update();
    assert!(
        game.world()
            .resource::<jackdaw_runtime::GameActions>()
            .pressed("Move"),
        "the editor-written file drives the game's Move"
    );
}
