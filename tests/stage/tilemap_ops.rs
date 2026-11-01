//! The tilemap authoring operators, end to end in a real editor (T22-T2's
//! H-side evidence for matrix cells M1-M8): a layer added on a 2D world
//! scene, cells painted / erased / filled / flooded through the operators
//! the palette panel and the canvas stroke dispatch, one stroke one undo
//! entry, and the whole structure through a save/reopen round trip.
//!
//! These are the same doors the mouse walks (`tilemap.stroke` only repacks
//! a drag into one of these calls), so an operator-level green here is the
//! authoring chain's green; the panel chrome and the pointer gesture are
//! the T3 live legs.

use crate::sprite_gizmo::settle;
use crate::util::{self, OperatorResultExt as _};

use bevy::prelude::*;
use jackdaw::active_tool::ActiveTool;
use jackdaw::commands::CommandHistory;
use jackdaw::tilemap::TilemapPalette;
use jackdaw_api::prelude::*;
use jackdaw_scene_types::{TileCollisionMode, TileGridCell, TilemapLayer};

/// A 2D starter scene in the shape a `scene.new kind=2d` save writes (the
/// T21 fixture form, the `tilemap_guard` shape).
const STARTER: &str = r#"// Starter scene. Authored by the jackdaw editor; safe to edit by hand.

#Root
jackdaw_scene_types::Scene2dRoot
bevy_transform::components::transform::Transform
bevy_camera::visibility::Visibility::Visible
"#;

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
    app.world_mut()
        .operator("scene.open")
        .param("path", scene_path.display().to_string())
        .call()
        .expect("scene.open dispatches")
        .assert_finished();
    util::settle_scene_load(&mut app);
    (app, tmp, scene_path)
}

/// One operator parameter: strings, entities and numbers as the ops read
/// them.
enum P {
    S(&'static str, String),
    E(&'static str, Entity),
    I(&'static str, i64),
}

fn call(app: &mut App, id: &'static str, params: &[P]) {
    let mut call = app.world_mut().operator(id);
    for param in params {
        call = match param {
            P::S(key, value) => call.param(*key, value.clone()),
            P::E(key, entity) => call.param(*key, *entity),
            P::I(key, value) => call.param(*key, *value),
        };
    }
    call.call()
        .expect("the operator dispatched")
        .assert_finished();
    for _ in 0..8 {
        app.update();
    }
}

/// A call that is expected to refuse: nothing happens, and the operator
/// says so with `Cancelled`.
fn call_refused(app: &mut App, id: &'static str, params: &[P]) {
    let mut call = app.world_mut().operator(id);
    for param in params {
        call = match param {
            P::S(key, value) => call.param(*key, value.clone()),
            P::E(key, entity) => call.param(*key, *entity),
            P::I(key, value) => call.param(*key, *value),
        };
    }
    call.call()
        .expect("the operator dispatched")
        .assert_cancelled();
    for _ in 0..8 {
        app.update();
    }
}

/// `call`, plus the stroke rule's check: one scene-writing undo entry.
fn call_ok(app: &mut App, id: &'static str, params: &[P]) {
    let before = app.world().resource::<CommandHistory>().scene_pushes();
    call(app, id, params);
    let after = app.world().resource::<CommandHistory>().scene_pushes();
    assert_eq!(
        after,
        before + 1,
        "{id} is one undo entry — the stroke rule (T03)"
    );
}

fn undo(app: &mut App) {
    call(app, "history.undo", &[]);
}

fn redo(app: &mut App) {
    call(app, "history.redo", &[]);
}

fn add_layer(app: &mut App, name: &str) -> Entity {
    call(
        app,
        "tilemap.layer.add",
        &[
            P::S("name", name.to_string()),
            P::I("columns", 4),
            P::I("rows", 2),
        ],
    );
    let mut layers = app
        .world_mut()
        .query_filtered::<Entity, With<TilemapLayer>>();
    layers
        .single(app.world())
        .expect("exactly one layer after the add")
}

/// The layer's tile children, as (cell, tile index).
fn cells_of(app: &mut App, layer: Entity) -> Vec<(IVec2, u32)> {
    let mut found = app
        .world_mut()
        .query::<(&TileGridCell, &ChildOf)>()
        .iter(app.world())
        .filter(|(_, parent)| parent.parent() == layer)
        .map(|(cell, _)| (cell.cell, cell.tile))
        .collect::<Vec<_>>();
    found.sort_by_key(|(cell, _)| (cell.y, cell.x));
    found
}

fn tile_count(app: &mut App, layer: Entity) -> usize {
    cells_of(app, layer).len()
}

fn mode_of(app: &mut App, layer: Entity) -> TileCollisionMode {
    *app.world()
        .get::<TileCollisionMode>(layer)
        .expect("the layer carries its collision mode")
}

#[test]
fn a_layer_paints_erases_and_undoes_one_stroke_per_call() {
    let (mut app, _tmp, _scene) = editor_with_scene();
    let layer = add_layer(&mut app, "Ground");

    // Adding the layer named it the palette's active layer.
    assert_eq!(
        app.world().resource::<TilemapPalette>().active_layer,
        Some(layer),
        "the new layer is the one strokes land on"
    );
    // The layer lives under the 2D scene root, in the document.
    assert!(
        app.world().get::<ChildOf>(layer).is_some_and(|parent| app
            .world()
            .get::<jackdaw_scene_types::Scene2dRoot>(parent.parent())
            .is_some()),
        "the layer parents to the 2D scene root"
    );

    // One paint call, three cells: one stroke, one undo entry.
    call_ok(
        &mut app,
        "tilemap.paint",
        &[P::S("cells", "0,0;1,0;2,0".to_string()), P::I("tile", 1)],
    );
    assert_eq!(
        cells_of(&mut app, layer),
        vec![
            (IVec2::new(0, 0), 1),
            (IVec2::new(1, 0), 1),
            (IVec2::new(2, 0), 1)
        ],
        "every cell of the stroke cuts the named tile"
    );
    // The route-C tile form: a sheet sprite cut by rect (the guard test
    // pins the disk face; this is the live-entity face).
    let mut tiles = app
        .world_mut()
        .query::<(&TileGridCell, &Sprite, &ChildOf)>();
    let (_, sprite, parent) = tiles
        .iter(app.world())
        .find(|(_, _, parent)| parent.parent() == layer)
        .expect("a tile child");
    assert_eq!(
        sprite.rect,
        Some(Rect::new(32.0, 0.0, 64.0, 32.0)),
        "tile 1 of a 4-column sheet cuts column 1"
    );
    assert_eq!(sprite.custom_size, Some(Vec2::splat(32.0)));
    assert_eq!(parent.parent(), layer);

    // Undo lifts the whole stroke; redo restores it.
    undo(&mut app);
    assert_eq!(tile_count(&mut app, layer), 0, "one undo lifts the stroke");
    redo(&mut app);
    assert_eq!(tile_count(&mut app, layer), 3, "redo re-lays it");

    // Erase is the same rule.
    call_ok(
        &mut app,
        "tilemap.erase",
        &[P::S("cells", "1,0".to_string())],
    );
    assert_eq!(tile_count(&mut app, layer), 2);
    undo(&mut app);
    assert_eq!(tile_count(&mut app, layer), 3, "erase undoes");

    // A second stroke over an occupied cell repaints it, and undo brings
    // the previous tile back.
    call_ok(
        &mut app,
        "tilemap.paint",
        &[P::S("cells", "1,0".to_string()), P::I("tile", 2)],
    );
    assert!(cells_of(&mut app, layer).contains(&(IVec2::new(1, 0), 2)));
    undo(&mut app);
    assert!(
        cells_of(&mut app, layer).contains(&(IVec2::new(1, 0), 1)),
        "undo restores the repainted cell's previous tile"
    );

    // Out-of-bounds cells are refused whole: the grid the game builds is
    // exactly the layer's sheet cut.
    let before = tile_count(&mut app, layer);
    call_refused(
        &mut app,
        "tilemap.paint",
        &[P::S("cells", "9,9".to_string())],
    );
    assert_eq!(
        tile_count(&mut app, layer),
        before,
        "out-of-bounds paints nothing"
    );
}

#[test]
fn fill_and_flood_cover_their_regions() {
    let (mut app, _tmp, _scene) = editor_with_scene();
    let layer = add_layer(&mut app, "Ground");

    // Rect fill: corners in either order, one undo entry.
    call_ok(
        &mut app,
        "tilemap.fill",
        &[
            P::S("from", "0,0".to_string()),
            P::S("to", "2,1".to_string()),
            P::I("tile", 1),
        ],
    );
    assert_eq!(tile_count(&mut app, layer), 6, "the 3x2 rect fills whole");
    undo(&mut app);
    assert_eq!(tile_count(&mut app, layer), 0);
    redo(&mut app);

    // Flood from an open cell: the connected empty region — (3,0) and
    // (3,1), the column the rect never reached — becomes tile 4, and the
    // tile-1 border stops it.
    call_ok(
        &mut app,
        "tilemap.fill.flood",
        &[P::S("at", "3,1".to_string()), P::I("tile", 4)],
    );
    let cells = cells_of(&mut app, layer);
    assert_eq!(cells.len(), 8, "six rect tiles plus the flood's two cells");
    assert!(
        cells.contains(&(IVec2::new(3, 1), 4)) && cells.contains(&(IVec2::new(3, 0), 4)),
        "the seed cell and its connected empty neighbor flipped"
    );
    let flooded: Vec<IVec2> = cells
        .iter()
        .filter(|(_, tile)| *tile == 4)
        .map(|(cell, _)| *cell)
        .collect();
    assert_eq!(
        flooded,
        vec![IVec2::new(3, 0), IVec2::new(3, 1)],
        "the flood painted exactly its region — never across the tile-1 border"
    );
    undo(&mut app);
    assert_eq!(tile_count(&mut app, layer), 6, "flood undoes whole");
}

#[test]
fn layers_switch_active_visibility_and_mode() {
    let (mut app, _tmp, _scene) = editor_with_scene();
    let ground = add_layer(&mut app, "Ground");
    call(
        &mut app,
        "tilemap.layer.add",
        &[P::S("name", "Triggers".to_string())],
    );
    let triggers = {
        let mut layers = app
            .world_mut()
            .query_filtered::<Entity, With<TilemapLayer>>();
        layers
            .iter(app.world())
            .find(|entity| *entity != ground)
            .expect("a second layer")
    };

    // The active layer is the newest add; paint without a layer param
    // lands there, and switching writes the palette.
    assert_eq!(
        app.world().resource::<TilemapPalette>().active_layer,
        Some(triggers)
    );
    call(&mut app, "tilemap.layer.active", &[P::E("entity", ground)]);
    assert_eq!(
        app.world().resource::<TilemapPalette>().active_layer,
        Some(ground)
    );
    call(
        &mut app,
        "tilemap.paint",
        &[P::S("cells", "0,0".to_string()), P::I("tile", 1)],
    );
    assert_eq!(
        cells_of(&mut app, ground).len(),
        1,
        "the stroke landed on the active layer"
    );
    assert_eq!(cells_of(&mut app, triggers).len(), 0);

    // Mode: set, read back, undo.
    call_ok(
        &mut app,
        "tilemap.layer.mode",
        &[
            P::E("entity", triggers),
            P::S("mode", "trigger".to_string()),
        ],
    );
    assert_eq!(mode_of(&mut app, triggers), TileCollisionMode::Trigger);
    undo(&mut app);
    assert_eq!(mode_of(&mut app, triggers), TileCollisionMode::Passable);
    redo(&mut app);
    assert_eq!(mode_of(&mut app, triggers), TileCollisionMode::Trigger);

    // Visibility: hide, read back, undo.
    call_ok(
        &mut app,
        "tilemap.layer.visible",
        &[
            P::E("entity", triggers),
            P::S("visible", "false".to_string()),
        ],
    );
    assert_eq!(
        app.world().get::<Visibility>(triggers),
        Some(&Visibility::Hidden),
        "the hidden layer reads Hidden"
    );
    undo(&mut app);
    assert_eq!(
        app.world().get::<Visibility>(triggers),
        Some(&Visibility::Inherited),
        "undo restores the layer's spawn default"
    );
}

#[test]
fn the_tilemap_scene_saves_and_reopens() {
    let (mut app, _tmp, scene_path) = editor_with_scene();
    let layer = add_layer(&mut app, "Ground");
    call(
        &mut app,
        "tilemap.layer.mode",
        &[P::E("entity", layer), P::S("mode", "solid".to_string())],
    );
    call(
        &mut app,
        "tilemap.paint",
        &[P::S("cells", "0,0;1,0;3,1".to_string()), P::I("tile", 2)],
    );
    // A stroke over an occupied cell repaints it; the document patch, not
    // just the live component, must learn the new index — the save below
    // writes the patch.
    call(
        &mut app,
        "tilemap.paint",
        &[P::S("cells", "0,0".to_string()), P::I("tile", 5)],
    );
    settle(&mut app);

    assert!(jackdaw::scene_io::save_scene(app.world_mut()));
    let text = std::fs::read_to_string(&scene_path).expect("read the save");
    assert!(
        text.contains("TilemapLayer"),
        "the layer is on disk: {text}"
    );
    assert!(text.contains("TileGridCell"), "the tiles are on disk");
    assert!(text.contains("TileCollisionMode"), "the mode is on disk");
    assert!(text.contains("rect:"), "tiles cut by rect, never an atlas");
    assert!(!text.contains("texture_atlas"));

    // A fresh editor reopens: layer fields, tiles and mode all come back.
    let mut reopened = util::editor_test_app();
    reopened
        .world_mut()
        .operator("scene.open")
        .param("path", scene_path.display().to_string())
        .call()
        .expect("scene.open dispatches")
        .assert_finished();
    util::settle_scene_load(&mut reopened);

    let mut layers = reopened
        .world_mut()
        .query::<(Entity, &TilemapLayer, &TileCollisionMode)>();
    let (_, form, mode) = layers
        .single(reopened.world())
        .expect("the reopened scene has its layer");
    assert_eq!(form.columns, 4);
    assert_eq!(form.rows, 2);
    assert_eq!(*mode, TileCollisionMode::Solid);

    let mut cells = reopened.world_mut().query::<&TileGridCell>();
    let mut found: Vec<(IVec2, u32)> = cells
        .iter(reopened.world())
        .map(|cell| (cell.cell, cell.tile))
        .collect();
    found.sort_by_key(|(cell, _)| (cell.y, cell.x));
    assert_eq!(
        found,
        vec![
            (IVec2::new(0, 0), 5),
            (IVec2::new(1, 0), 2),
            (IVec2::new(3, 1), 2)
        ],
        "the cells survive the reopen with their tile cuts — including the repaint"
    );
}

#[test]
fn the_palette_session_tracks_the_tile_and_brush() {
    let (mut app, _tmp, _scene) = editor_with_scene();
    add_layer(&mut app, "Ground");

    // The palette click dispatches tilemap.tile.select — session state,
    // never an undo entry.
    let before = app.world().resource::<CommandHistory>().scene_pushes();
    call(&mut app, "tilemap.tile.select", &[P::I("tile", 5)]);
    assert_eq!(app.world().resource::<TilemapPalette>().active_tile, 5);
    assert_eq!(
        app.world().resource::<CommandHistory>().scene_pushes(),
        before,
        "palette selections are not scene edits"
    );

    // The brush switch decides what a stroke does; a paint call without a
    // tile param cuts the palette's active tile.
    call(
        &mut app,
        "tilemap.brush",
        &[P::S("brush", "erase".to_string())],
    );
    assert_eq!(
        app.world().resource::<TilemapPalette>().brush,
        jackdaw::tilemap::TileBrush::Erase
    );
    call(
        &mut app,
        "tilemap.paint",
        &[P::S("cells", "0,0;1,0".to_string())],
    );
    let layer = {
        let mut layers = app
            .world_mut()
            .query_filtered::<Entity, With<TilemapLayer>>();
        layers.single(app.world()).expect("the layer")
    };
    assert_eq!(
        cells_of(&mut app, layer),
        vec![(IVec2::new(0, 0), 5), (IVec2::new(1, 0), 5)],
        "an unnamed tile reads the palette's active tile"
    );
}

#[test]
fn the_tilemap_tool_switches_and_the_palette_stays_out_of_history() {
    let (mut app, _tmp, _scene) = editor_with_scene();
    call(&mut app, "tool.tilemap", &[]);
    assert_eq!(
        *app.world().resource::<ActiveTool>(),
        ActiveTool::Tilemap,
        "T is the tilemap tool"
    );
    call(&mut app, "tool.select", &[]);
    assert_eq!(*app.world().resource::<ActiveTool>(), ActiveTool::Select);
}
