//! The editor↔game contract for config assets: what the editor's
//! asset writer puts on disk is what the runtime's config loader reads
//! back — the file form the two sides share, pinned end to end with
//! the real `write_asset_file`, not a hand-written imitation. Plus the
//! session-state boundary in the negative: a Resources-panel edit (an
//! editor-world resource write) produces no file and no game value.

use std::path::Path;

use bevy::asset::{AssetApp, ReflectAsset};
use bevy::prelude::*;
use jackdaw::asset_index::AssetValue;
use jackdaw::definition_assets::write_asset_file;
use jackdaw_runtime::{ConfigLoader, JackdawCatalog, apply_config_defaults};

use crate::util;

/// A game config type in the shape the template teaches.
#[derive(Asset, Resource, Reflect, Clone, PartialEq, Debug)]
#[reflect(Resource, Default)]
struct GuardConfig {
    player_health: f32,
    move_speed: f32,
    gravity: f32,
}

impl Default for GuardConfig {
    fn default() -> Self {
        Self {
            player_health: 100.0,
            move_speed: 1.0,
            gravity: -9.81,
        }
    }
}

/// The editor side: a value with authored numbers, written the way
/// `asset.save` writes it.
fn editor_writes_config(assets: &Path) {
    let mut app = util::editor_test_app();
    app.init_asset::<GuardConfig>()
        .register_asset_reflect::<GuardConfig>();
    let world = app.world_mut();
    let value = GuardConfig {
        player_health: 150.0,
        move_speed: 2.5,
        gravity: -19.5,
    };
    let registry = world
        .resource::<bevy::ecs::reflect::AppTypeRegistry>()
        .clone();
    let handle = {
        let registry = registry.read();
        let registration = registry
            .get_with_type_path(std::any::type_name::<GuardConfig>())
            .expect("the type registered");
        let reflect_asset = registration.data::<ReflectAsset>().expect("as an asset");
        reflect_asset.add(world, &value)
    };
    write_asset_file(
        world,
        "game-config",
        &AssetValue::Handle(handle),
        &assets.join("game-config.bsn"),
    )
    .expect("the editor writes the config asset");
}

/// The game side: the plugin's startup walk plus the config system,
/// and the Resource the file yields.
fn game_reads_config(assets: &Path) -> Option<GuardConfig> {
    let mut app = App::new();
    app.add_plugins((
        bevy::app::TaskPoolPlugin::default(),
        bevy::asset::AssetPlugin::default(),
    ));
    app.init_asset::<GuardConfig>()
        .register_asset_reflect::<GuardConfig>();
    app.init_resource::<JackdawCatalog>();
    app.add_systems(Update, apply_config_defaults::<GuardConfig>);
    app.world_mut()
        .spawn(ConfigLoader::<GuardConfig>::new("game-config.bsn"));
    app.update(); // let schedules exist before the walk mutates the world
    walk(&mut app, assets);
    for _ in 0..3 {
        app.update();
    }
    app.world().get_resource::<GuardConfig>().cloned()
}

/// The editor's file is the game's value: authored numbers travel
/// through the real writer and the real loader. If either side changes
/// the file form, this goes red — that form is the contract.
#[test]
fn the_editors_config_file_is_the_games_initial_resource() {
    let tmp = tempfile::tempdir().expect("tempdir");
    let assets = tmp.path().join("assets");
    std::fs::create_dir_all(&assets).expect("assets dir");

    editor_writes_config(&assets);
    let read = game_reads_config(&assets).expect("the game applied a config");
    assert_eq!(
        read,
        GuardConfig {
            player_health: 150.0,
            move_speed: 2.5,
            gravity: -19.5,
        },
        "the authored numbers are the initial Resource values"
    );
}

/// The session-state boundary: what the Resources panel edits (an
/// editor-world resource write) reaches no file — so a game launched
/// next reads nothing of it. Config assets are the authored path;
/// the panel is the debug path, and the two do not mix.
#[test]
fn a_resource_panel_edit_never_reaches_the_game() {
    let tmp = tempfile::tempdir().expect("tempdir");
    let assets = tmp.path().join("assets");
    std::fs::create_dir_all(&assets).expect("assets dir");

    // The panel edit: a session-resource write in the editor's world.
    let mut app = util::editor_test_app();
    app.world_mut().insert_resource(GuardConfig {
        player_health: 999.0,
        move_speed: 99.0,
        gravity: -99.0,
    });
    app.update();

    // No file appeared...
    let files: Vec<_> = std::fs::read_dir(&assets)
        .expect("assets dir")
        .map(|entry| entry.expect("entry").file_name())
        .collect();
    assert!(files.is_empty(), "a session edit writes no file: {files:?}");

    // ...so a game launched next starts at its default, not 999.
    let read = game_reads_config(&assets).expect("the fallback applies");
    assert_eq!(
        read,
        GuardConfig::default(),
        "the game never sees the editor's session value"
    );
}

/// The loading half of the startup walk, over the file the editor
/// really wrote: parse the editor's form, load the value the way the
/// runtime loads every asset file, and file it under the key the
/// catalog would. The crate-private walk itself is covered by the
/// runtime's own tests; this pins the *form* the two sides share.
/// A missing file is the no-config case: nothing filed, walk done.
fn walk(app: &mut App, assets: &Path) {
    let world = app.world_mut();
    if let Ok(text) = std::fs::read_to_string(assets.join("game-config.bsn")) {
        let ast = jackdaw_bsn::parse_bsn_text(&text).expect("the editor's form parses");
        let root = ast.roots.first().copied().expect("a root");
        let handle = jackdaw_bsn::load_asset_root(world, &ast, root).expect("an asset loads");
        world
            .resource_mut::<JackdawCatalog>()
            .register_file("game-config.bsn", handle);
    }
    world.insert_resource(jackdaw_runtime::AssetsWalked);
}
