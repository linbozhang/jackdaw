//! The TM5 guard (T22 plan §一/TM5, matrix cell M14): route C builds tiles as
//! `Sprite { image, rect, custom_size }` — the fork's documented "easy
//! one-off alternative to using a `TextureAtlas`"
//! (`bevy_sprite/src/sprite.rs:32-37`). A17's failure mode is the atlas
//! handle space: a sprite wearing `texture_atlas` renders the whole sheet on
//! both the canvas and the game window. These guards pin the form the T22
//! tilemap authoring must produce, through the editor's own save/reopen
//! loop:
//!
//! - a tile-form sprite saves `rect` and no `texture_atlas` anywhere, and
//!   the rect round-trips a reopen;
//! - the discriminating control: a sprite that does wear an atlas (a real
//!   `sprite_atlas` asset, the T21 SP3 flow) serializes the `texture_atlas`
//!   field — so the absence above is a meaningful pass, not a vacuous one.
//!
//! The pixel half of M14 (canvas tile pixels ≠ the whole sheet) is the
//! real-machine L7 leg in T3; this is its headless half (H+FS).

use crate::sprite_gizmo::{settle, sprite};
use crate::util::{self, OperatorResultExt as _};

use bevy::{image::TextureAtlas, prelude::*, sprite::Anchor};
use jackdaw_api::prelude::*;

/// A 2D starter scene in the shape a `scene.new kind=2d` save writes (the
/// T21 fixture form), pointing at a repo texture so the image handle has a
/// path on both sides of the save.
const STARTER: &str = r#"// Starter scene. Authored by the jackdaw editor; safe to edit by hand.

#Root
jackdaw_scene_types::Scene2dRoot
bevy_transform::components::transform::Transform
bevy_camera::visibility::Visibility::Visible
bevy_ecs::hierarchy::Children [
    #"Main Camera"
    bevy_camera::components::Camera2d
    bevy_transform::components::transform::Transform
    bevy_camera::visibility::Visibility::Visible
    --
    #Hero
    bevy_sprite::sprite::Sprite {
        image: "textures/hero.png",
    }
    bevy_sprite::sprite::Anchor
    bevy_transform::components::transform::Transform
    bevy_camera::visibility::Visibility::Visible
]
"#;

/// An editor with a project of its own (the `sprite_atlas` test's shape) and
/// the starter 2D scene opened from the project root.
fn editor_with_scene() -> (App, tempfile::TempDir, std::path::PathBuf) {
    let tmp = tempfile::tempdir().expect("tempdir");
    std::fs::create_dir_all(tmp.path().join("assets/content")).expect("a content folder");
    let scene_path = tmp.path().join("stage.bsn");
    std::fs::write(&scene_path, STARTER).expect("write the starter scene");
    let mut app = util::editor_test_app();
    app.world_mut()
        .insert_resource(jackdaw::project::ProjectRoot {
            root: tmp.path().to_path_buf(),
            config: default(),
        });
    open(&mut app, &scene_path);
    (app, tmp, scene_path)
}

fn open(app: &mut App, scene: &std::path::Path) {
    app.world_mut()
        .operator("scene.open")
        .param("path", scene.display().to_string())
        .call()
        .expect("scene.open dispatches")
        .assert_finished();
    util::settle_scene_load(app);
}

fn call(app: &mut App, id: &'static str, params: &[(&'static str, String)]) {
    let mut call = app.world_mut().operator(id);
    for (key, value) in params {
        call = call.param(*key, value.clone());
    }
    call.call()
        .expect("the operator dispatched")
        .assert_finished();
    for _ in 0..8 {
        app.update();
    }
}

fn scene_2d_root(app: &mut App) -> Entity {
    app.world_mut()
        .query_filtered::<Entity, With<jackdaw_scene_types::Scene2dRoot>>()
        .single(app.world())
        .expect("the opened scene has a 2D root")
}

fn named(app: &mut App, wanted: &str) -> Entity {
    let mut query = app.world_mut().query::<(Entity, &Name)>();
    query
        .iter(app.world())
        .find(|(_, name)| name.as_str() == wanted)
        .map(|(entity, _)| entity)
        .unwrap_or_else(|| panic!("an entity named {wanted} exists after the reopen"))
}

#[test]
fn the_tile_form_saves_a_rect_and_never_an_atlas() {
    let (mut app, _tmp, scene_path) = editor_with_scene();
    let root = scene_2d_root(&mut app);
    let image = app
        .world()
        .resource::<AssetServer>()
        .load("textures/hero.png");
    // The exact form the T2 tile authoring must produce (route C): the
    // sheet handle, one cell's rect, one cell's drawn size.
    sprite(
        &mut app,
        root,
        "GroundTile",
        Sprite {
            image,
            rect: Some(Rect::new(0.0, 0.0, 32.0, 32.0)),
            custom_size: Some(Vec2::splat(32.0)),
            ..default()
        },
        Anchor::CENTER,
        Vec3::ZERO,
    );
    settle(&mut app);

    assert!(jackdaw::scene_io::save_scene(app.world_mut()));
    let text = std::fs::read_to_string(&scene_path).expect("read the save");
    assert!(text.contains("GroundTile"), "the tile made it to disk");
    assert!(text.contains("rect:"), "the cell rect is on disk: {text}");
    assert!(
        !text.contains("texture_atlas"),
        "a tilemap scene names no atlas handle (the A17 handle space): {text}"
    );

    // The round-trip half: a fresh editor reopens the file and the tile
    // form is intact.
    let mut reopened = util::editor_test_app();
    open(&mut reopened, &scene_path);
    let tile = named(&mut reopened, "GroundTile");
    let saved = reopened
        .world()
        .get::<Sprite>(tile)
        .expect("the tile carries its Sprite");
    assert_eq!(
        saved.rect,
        Some(Rect::new(0.0, 0.0, 32.0, 32.0)),
        "the cell rect survives the reopen"
    );
    assert_eq!(
        saved.custom_size,
        Some(Vec2::splat(32.0)),
        "the drawn cell size survives the reopen"
    );
    assert!(
        saved.texture_atlas.is_none(),
        "the reopened tile carries no atlas"
    );
}

#[test]
fn an_atlas_sprite_is_the_discriminating_control() {
    let (mut app, _tmp, scene_path) = editor_with_scene();
    // A real atlas asset, written the way the T21 SP3 flow does, so the
    // control's layout handle has the same standing a route slip would.
    call(
        &mut app,
        "asset.new",
        &[
            ("type", "sprite_atlas".to_string()),
            ("name", "sheet".to_string()),
            ("path", "content".to_string()),
        ],
    );
    let layout = app
        .world()
        .resource::<AssetServer>()
        .load::<TextureAtlasLayout>("content/sheet.bsn");
    let image = app
        .world()
        .resource::<AssetServer>()
        .load("textures/hero.png");
    let root = scene_2d_root(&mut app);
    sprite(
        &mut app,
        root,
        "AtlasSprite",
        Sprite {
            image,
            texture_atlas: Some(TextureAtlas { index: 2, layout }),
            ..default()
        },
        Anchor::CENTER,
        Vec3::ZERO,
    );
    settle(&mut app);

    assert!(jackdaw::scene_io::save_scene(app.world_mut()));
    let text = std::fs::read_to_string(&scene_path).expect("read the save");
    assert!(
        text.contains("texture_atlas"),
        "a sprite wearing an atlas serializes it — the guard above is \
         discriminating, not vacuous: {text}"
    );
}
