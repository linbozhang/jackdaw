//! Tile-grid authoring (T22, route C): the session state, the operators and
//! the undo commands behind the Tilemap tool.
//!
//! A [`TilemapLayer`] parent carries the sheet cut and the per-layer
//! [`TileCollisionMode`]; its tiles are `Sprite` children cut by `rect` (the
//! fork's documented one-off atlas alternative — never `texture_atlas`, the
//! A17 handle space the `tilemap_guard` stage tests pin). The operators are
//! the tool's whole face — the palette panel and the canvas stroke dispatch
//! them — so a remote caller and a mouse gesture make the same edit through
//! the same door, and every stroke lands as one [`EditorCommand`]: a drag is
//! one undo, the T03 rule.

use bevy::prelude::*;
use jackdaw_api::prelude::*;
use jackdaw_api_internal::operator::{report_to_caller, warn_caller};

use jackdaw_scene_types::{EditorHidden, Locked, TileCollisionMode, TileGridCell, TilemapLayer};

use crate::{
    commands::{CommandHistory, EditorCommand},
    entity_ops::{claim_free_name, scene_entity_names},
    sprite_ops::SpriteAddGate,
};

/// The tile authoring session: which layer receives strokes, which sheet
/// tile the strokes cut, and what a stroke does. An editor-session resource
/// — it names no scene document state, so switching it is never an undo
/// entry.
#[derive(Resource, Default, Debug, Clone, Copy, PartialEq)]
pub struct TilemapPalette {
    /// The layer strokes land on.
    pub active_layer: Option<Entity>,
    /// The sheet tile index strokes cut.
    pub active_tile: u32,
    /// What a stroke does.
    pub brush: TileBrush,
}

/// What a canvas stroke with the Tilemap tool does. Erase is a mode of the
/// same tool (plan decision 7): switch brushes, keep drawing.
#[derive(Default, Debug, Clone, Copy, PartialEq, Eq)]
pub enum TileBrush {
    /// Drag paints cells.
    #[default]
    Paint,
    /// Drag erases cells.
    Erase,
    /// Drag stretches a rectangle; release fills it.
    FillRect,
    /// Click floods the connected region of one tile.
    Flood,
}

pub(crate) fn plugin(app: &mut App) {
    app.init_resource::<TilemapPalette>();
}

pub(crate) fn add_to_extension(ctx: &mut ExtensionContext) {
    ctx.register_operator::<TilemapLayerAddOp>()
        .register_operator::<TilemapLayerActiveOp>()
        .register_operator::<TilemapLayerModeOp>()
        .register_operator::<TilemapLayerVisibleOp>()
        .register_operator::<TilemapTileSelectOp>()
        .register_operator::<TilemapBrushOp>()
        .register_operator::<TilemapPaintOp>()
        .register_operator::<TilemapEraseOp>()
        .register_operator::<TilemapFillOp>()
        .register_operator::<TilemapFloodOp>();
}

// ---------------------------------------------------------------------------
// cell math (shared with the palette's stroke)
// ---------------------------------------------------------------------------

/// Parse `"x,y"` into a cell. Negatives welcome: the floor-division grid
/// answers them, and the bounds check is the caller's.
pub(crate) fn parse_cell(text: &str) -> Option<IVec2> {
    let (x, y) = text.split_once(',')?;
    let x = x.trim().parse::<i32>().ok()?;
    let y = y.trim().parse::<i32>().ok()?;
    Some(IVec2::new(x, y))
}

/// Parse a stroke's cell list: `"0,0;1,0;2,0"`. Duplicate cells collapse —
/// a drag revisits cells, and one cell is one tile.
pub(crate) fn parse_cells(text: &str) -> Vec<IVec2> {
    let mut seen = std::collections::HashSet::new();
    text.split(';')
        .filter_map(parse_cell)
        .filter(|cell| seen.insert(*cell))
        .collect()
}

/// Every cell in the rectangle from `from` to `to`, corners included —
/// the fill operator's region. Order is row-major so tests read stably.
pub(crate) fn cells_in_rect(from: IVec2, to: IVec2) -> Vec<IVec2> {
    let min = from.min(to);
    let max = from.max(to);
    let mut cells = Vec::with_capacity(((max.x - min.x + 1) * (max.y - min.y + 1)) as usize);
    for y in min.y..=max.y {
        for x in min.x..=max.x {
            cells.push(IVec2::new(x, y));
        }
    }
    cells
}

/// The connected region of cells sharing `start`'s tile, bounded by `size`.
/// `same_tile` answers the current tile of a cell (`None` for the empty
/// grid); the flood spreads through cells equal to `start`'s and stops at
/// the border of differing tiles. Returns the cells to write (excluding
/// none — `start`'s own rewrite is the operator's to skip), row-major.
pub(crate) fn flood_cells(
    start: IVec2,
    size: UVec2,
    same_tile: impl Fn(IVec2) -> Option<u32>,
) -> Vec<IVec2> {
    let Some(seed) = same_tile(start) else {
        return Vec::new();
    };
    let max = IVec2::new(size.x as i32 - 1, size.y as i32 - 1);
    let mut region = std::collections::HashSet::new();
    region.insert(start);
    let mut frontier = vec![start];
    while let Some(cell) = frontier.pop() {
        for offset in [IVec2::X, IVec2::NEG_X, IVec2::Y, IVec2::NEG_Y] {
            let next = cell + offset;
            if next.x < 0 || next.y < 0 || next.x > max.x || next.y > max.y {
                continue;
            }
            // A differing tile is the flood's border; a repeat is done.
            if same_tile(next) != Some(seed) || !region.insert(next) {
                continue;
            }
            frontier.push(next);
        }
    }
    let mut cells: Vec<IVec2> = region.into_iter().collect();
    cells.sort_by_key(|cell| (cell.y, cell.x));
    cells
}

// ---------------------------------------------------------------------------
// reading the layer
// ---------------------------------------------------------------------------

/// The layer's live form, or `None` when `layer` is gone.
pub(crate) fn layer_form(world: &World, layer: Entity) -> Option<(TilemapLayer, GlobalTransform)> {
    Some((
        world.get::<TilemapLayer>(layer)?.clone(),
        *world.get::<GlobalTransform>(layer)?,
    ))
}

/// The tile child of `layer` sitting at `cell`, with its tile index.
pub(crate) fn tile_at_cell(world: &World, layer: Entity, cell: IVec2) -> Option<(Entity, u32)> {
    let children = world.get::<bevy::ecs::hierarchy::Children>(layer)?;
    children
        .iter()
        .filter_map(|child| world.get::<TileGridCell>(child).map(|c| (child, *c)))
        .find(|(_, grid_cell)| grid_cell.cell == cell)
        .map(|(child, grid_cell)| (child, grid_cell.tile))
}

/// A tile's outliner name (a hidden row, but the document still reads it).
fn tile_name(cell: IVec2) -> String {
    format!("Tile {},{}", cell.x, cell.y)
}

/// The spawn form of one tile (route C, the `tilemap_guard` shape): a sheet
/// sprite cut by `rect`, hidden from the outliner and locked from the canvas
/// — a tile is redrawn from the palette, never picked (plan decision 5-A).
fn spawn_tile(
    world: &mut World,
    layer: Entity,
    form: &TilemapLayer,
    cell: IVec2,
    tile: u32,
) -> Entity {
    let rect = form.tile_rect(tile);
    let center = form.cell_center(cell);
    let entity = world
        .spawn((
            Name::new(tile_name(cell)),
            Sprite {
                image: form.image.clone(),
                rect: Some(rect),
                custom_size: Some(form.cell_size),
                ..default()
            },
            bevy::sprite::Anchor::CENTER,
            Transform::from_translation(center.extend(form.order as f32)),
            Visibility::default(),
            TileGridCell { cell, tile },
            EditorHidden,
            Locked,
            ChildOf(layer),
        ))
        .id();
    crate::scene_io::register_entity_in_ast(world, entity);
    entity
}

/// Restate one existing tile's sheet cut in place (a stroke over an
/// occupied cell repaints it). The document learns both faces — the
/// sprite's rect and the grid cell's index — the same way the live ECS
/// does: a save writes the AST patches, not the live components.
fn repaint_tile(world: &mut World, tile_entity: Entity, tile: u32) {
    let layer = world
        .get::<ChildOf>(tile_entity)
        .map(ChildOf::parent)
        .expect("a tile child has a layer parent");
    let rect = world
        .get::<TilemapLayer>(layer)
        .expect("layer just read")
        .tile_rect(tile);
    if let Ok(mut grid_cell) = world.get_entity_mut(tile_entity) {
        if let Some(mut sprite) = grid_cell.get_mut::<Sprite>() {
            sprite.rect = Some(rect);
        }
        if let Some(mut cell) = grid_cell.get_mut::<TileGridCell>() {
            cell.tile = tile;
        }
    }
    if let Some(sprite) = world.get::<Sprite>(tile_entity).cloned() {
        crate::commands::sync_component_to_ast(world, tile_entity, Sprite::type_path(), &sprite);
    }
    if let Some(cell) = world.get::<TileGridCell>(tile_entity).copied() {
        crate::commands::sync_component_to_ast(
            world,
            tile_entity,
            TileGridCell::type_path(),
            &cell,
        );
    }
}

// ---------------------------------------------------------------------------
// undo commands — one stroke is one entry
// ---------------------------------------------------------------------------

/// One stroke of paints (or a fill): ensure every cell of `strokes` cuts
/// `tile` when executed, despawn the created and restore the repainted on
/// undo. `execute` rebuilds its recording from scratch, so a redo after an
/// intervening undo re-derives what it touched instead of replaying stale
/// entity ids.
pub(crate) struct PaintTiles {
    pub strokes: Vec<(IVec2, u32)>,
    pub label: String,
    created: Vec<Entity>,
    repainted: Vec<(Entity, u32)>,
    layer: Option<Entity>,
}

impl PaintTiles {
    pub(crate) fn new(layer: Entity, strokes: Vec<(IVec2, u32)>, label: String) -> Self {
        Self {
            strokes,
            label,
            created: Vec::new(),
            repainted: Vec::new(),
            layer: Some(layer),
        }
    }
}

impl EditorCommand for PaintTiles {
    fn execute(&mut self, world: &mut World) {
        self.created.clear();
        self.repainted.clear();
        let Some(layer) = self
            .layer
            .filter(|&layer| world.get::<TilemapLayer>(layer).is_some())
        else {
            return;
        };
        let Some((form, _)) = layer_form(world, layer) else {
            return;
        };
        for (cell, tile) in std::mem::take(&mut self.strokes) {
            match tile_at_cell(world, layer, cell) {
                Some((tile_entity, previous)) => {
                    if previous != tile {
                        repaint_tile(world, tile_entity, tile);
                        self.repainted.push((tile_entity, previous));
                    }
                }
                None => {
                    let entity = spawn_tile(world, layer, &form, cell, tile);
                    self.created.push(entity);
                }
            }
            self.strokes.push((cell, tile));
        }
    }

    fn undo(&mut self, world: &mut World) {
        for (entity, previous) in std::mem::take(&mut self.repainted) {
            repaint_tile(world, entity, previous);
        }
        for &entity in &self.created {
            let entity = crate::scene_nodes::live_entity(world, entity);
            crate::commands::deselect_entities(world, &[entity]);
            crate::commands::despawn_scene_entity(world, entity);
        }
        self.created.clear();
    }

    fn description(&self) -> &str {
        &self.label
    }
}

/// One stroke of erases: despawn every named cell's tile when executed,
/// re-spawn them (deterministically, from cell + tile) on undo.
pub(crate) struct EraseTiles {
    pub layer: Entity,
    pub cells: Vec<IVec2>,
    pub label: String,
    erased: Vec<(IVec2, u32)>,
}

impl EraseTiles {
    pub(crate) fn new(layer: Entity, cells: Vec<IVec2>, label: String) -> Self {
        Self {
            layer,
            cells,
            label,
            erased: Vec::new(),
        }
    }
}

impl EditorCommand for EraseTiles {
    fn execute(&mut self, world: &mut World) {
        self.erased.clear();
        for cell in std::mem::take(&mut self.cells) {
            if let Some((tile_entity, tile)) = tile_at_cell(world, self.layer, cell) {
                self.erased.push((cell, tile));
                crate::commands::deselect_entities(world, &[tile_entity]);
                crate::commands::despawn_scene_entity(world, tile_entity);
            }
            self.cells.push(cell);
        }
    }

    fn undo(&mut self, world: &mut World) {
        let Some((form, _)) = layer_form(world, self.layer) else {
            return;
        };
        for (cell, tile) in std::mem::take(&mut self.erased) {
            spawn_tile(world, self.layer, &form, cell, tile);
        }
    }

    fn description(&self) -> &str {
        &self.label
    }
}

/// A layer's collision tri-state, one undo entry per switch.
pub(crate) struct SetTileCollisionMode {
    pub layer: Entity,
    pub to: TileCollisionMode,
    from: Option<TileCollisionMode>,
}

impl SetTileCollisionMode {
    pub(crate) fn new(layer: Entity, to: TileCollisionMode) -> Self {
        Self {
            layer,
            to,
            from: None,
        }
    }
}

impl EditorCommand for SetTileCollisionMode {
    fn execute(&mut self, world: &mut World) {
        self.from = world.get::<TileCollisionMode>(self.layer).copied();
        if let Ok(mut entity) = world.get_entity_mut(self.layer) {
            entity.insert(self.to);
        }
        sync_mode_doc(world, self.layer, self.to);
    }

    fn undo(&mut self, world: &mut World) {
        if let Some(from) = self.from {
            if let Ok(mut entity) = world.get_entity_mut(self.layer) {
                entity.insert(from);
            }
            sync_mode_doc(world, self.layer, from);
        }
    }

    fn description(&self) -> &str {
        "Set Tilemap Collision Mode"
    }
}

/// The document learns the mode the live layer now carries: the AST patch
/// is what a save writes, and `register_entity_in_ast` only seeded it.
fn sync_mode_doc(world: &mut World, entity: Entity, mode: TileCollisionMode) {
    crate::commands::sync_component_to_ast(world, entity, TileCollisionMode::type_path(), &mode);
}

/// Same for the layer's visibility.
fn sync_visibility_doc(world: &mut World, entity: Entity, to: Visibility) {
    crate::commands::sync_component_to_ast(world, entity, Visibility::type_path(), &to);
}

/// A layer's visibility toggle, one undo entry per flip.
pub(crate) struct SetLayerVisible {
    pub layer: Entity,
    pub to: Visibility,
    from: Option<Visibility>,
}

impl SetLayerVisible {
    pub(crate) fn new(layer: Entity, to: Visibility) -> Self {
        Self {
            layer,
            to,
            from: None,
        }
    }
}

impl EditorCommand for SetLayerVisible {
    fn execute(&mut self, world: &mut World) {
        self.from = world.get::<Visibility>(self.layer).copied();
        if let Ok(mut entity) = world.get_entity_mut(self.layer) {
            entity.insert(self.to);
        }
        sync_visibility_doc(world, self.layer, self.to);
    }

    fn undo(&mut self, world: &mut World) {
        if let Some(from) = self.from {
            if let Ok(mut entity) = world.get_entity_mut(self.layer) {
                entity.insert(from);
            }
            sync_visibility_doc(world, self.layer, from);
        }
    }

    fn description(&self) -> &str {
        "Toggle Tilemap Layer Visibility"
    }
}

// ---------------------------------------------------------------------------
// availability
// ---------------------------------------------------------------------------

/// The tilemap operators' gate: a 2D world scene is open and the editor is
/// in a state that acts on it. The same question `sprite.add` asks.
pub(crate) fn can_author_tiles(gate: SpriteAddGate) -> bool {
    gate.allows()
}

// ---------------------------------------------------------------------------
// operators
// ---------------------------------------------------------------------------

/// Add a tilemap layer to the open 2D world scene: the parent entity the
/// tool's strokes fill, with its sheet cut and collision tri-state. Becomes
/// the palette's active layer.
#[operator(
    id = "tilemap.layer.add",
    label = "Tilemap Layer",
    description = "Add a tilemap layer to the open 2D world scene.",
    is_available = can_author_tiles,
    params(
        name(String, doc = "Name for the layer. Defaults to \"Tilemap Layer\"."),
        cell_size(String, doc = "Cell edge in world units, as '32' or '32,24'. Defaults to 32."),
        columns(i64, doc = "Sheet columns. Defaults to 8."),
        rows(i64, doc = "Sheet rows. Defaults to 4."),
        path(String, doc = "Sheet image file, absolute or relative to the assets folder. A blank layer when omitted."),
    )
)]
pub(crate) fn tilemap_layer_add(
    params: In<OperatorParameters>,
    mut commands: Commands,
) -> OperatorResult {
    let name = params
        .as_str("name")
        .filter(|name| !name.is_empty())
        .map(str::to_owned)
        .unwrap_or_else(|| "Tilemap Layer".to_owned());
    let cell_size = params
        .as_str("cell_size")
        .and_then(parse_uvec2)
        .map(UVec2::as_vec2)
        .unwrap_or(Vec2::splat(32.0));
    let columns = params.as_int("columns").map_or(8, |n| n.max(1) as u32);
    let rows = params.as_int("rows").map_or(4, |n| n.max(1) as u32);
    let path = params
        .as_str("path")
        .filter(|path| !path.is_empty())
        .map(crate::entity_ops::to_asset_path);
    let name_for_closure = name.clone();
    commands.queue(move |world: &mut World| {
        add_layer(world, name_for_closure, cell_size, columns, rows, path);
    });
    OperatorResult::Finished
}

fn parse_uvec2(text: &str) -> Option<UVec2> {
    let (x, y) = match text.split_once(',') {
        Some((x, y)) => (x.trim().parse::<u32>().ok()?, y.trim().parse::<u32>().ok()?),
        None => {
            let both = text.trim().parse::<u32>().ok()?;
            (both, both)
        }
    };
    Some(UVec2::new(x, y))
}

fn add_layer(
    world: &mut World,
    name: String,
    cell_size: Vec2,
    columns: u32,
    rows: u32,
    path: Option<String>,
) {
    let Some(parent) = crate::sprite_ops::scene_2d_parent(world, None) else {
        warn_caller(world, "tilemap.layer.add: no 2D world scene is open");
        return;
    };
    let image = path.map(|path| world.resource::<AssetServer>().load(path));
    let name = claim_free_name(&mut scene_entity_names(world), &name).unwrap_or(name);
    let layer = TilemapLayer {
        cell_size,
        columns,
        rows,
        image: image.unwrap_or_default(),
        order: 0,
    };
    let label = format!("Add Tilemap Layer {name}");
    let mut spawn = crate::commands::SpawnEntity::new(
        move |world: &mut World| {
            let parent = crate::scene_nodes::live_entity(world, parent);
            let entity = world
                .spawn((
                    Name::new(name.clone()),
                    layer.clone(),
                    TileCollisionMode::default(),
                    Transform::default(),
                    Visibility::default(),
                    ChildOf(parent),
                ))
                .id();
            crate::scene_io::register_entity_in_ast(world, entity);
            crate::selection::select_only(world, entity);
            entity
        },
        label,
    );
    spawn.execute(world);
    let spawned = spawn.spawned;
    world
        .resource_mut::<CommandHistory>()
        .push_executed(Box::new(spawn));
    if let Some(spawned) = spawned {
        world.resource_mut::<TilemapPalette>().active_layer = Some(spawned);
    }
}

/// Point the palette's strokes at a layer.
#[operator(
    id = "tilemap.layer.active",
    label = "Active Tilemap Layer",
    description = "Make a tilemap layer the one strokes land on.",
    allows_undo = false,
    remote_hidden = "session state, not a scene edit",
    params(entity(Entity, doc = "The tilemap layer."))
)]
pub(crate) fn tilemap_layer_active(
    params: In<OperatorParameters>,
    layers: Query<(), With<TilemapLayer>>,
    mut palette: ResMut<TilemapPalette>,
    mut commands: Commands,
) -> OperatorResult {
    let Some(entity) = params
        .as_entity("entity")
        .filter(|&entity| layers.get(entity).is_ok())
    else {
        commands.queue(|world: &mut World| {
            warn_caller(world, "tilemap.layer.active: entity is not a tilemap layer");
        });
        return OperatorResult::Cancelled;
    };
    palette.active_layer = Some(entity);
    OperatorResult::Finished
}

/// Switch a layer's collision tri-state. One undo entry.
#[operator(
    id = "tilemap.layer.mode",
    label = "Tilemap Collision Mode",
    description = "Set a tilemap layer's collision mode: passable, solid or trigger.",
    is_available = can_author_tiles,
    params(
        entity(Entity, doc = "The tilemap layer."),
        mode(String, doc = "'passable', 'solid' or 'trigger'."),
    )
)]
pub(crate) fn tilemap_layer_mode(
    params: In<OperatorParameters>,
    mut commands: Commands,
) -> OperatorResult {
    let Some(entity) = params.as_entity("entity") else {
        commands.queue(|world: &mut World| {
            warn_caller(world, "tilemap.layer.mode: entity is required");
        });
        return OperatorResult::Cancelled;
    };
    let Some(mode) = params.as_str("mode").and_then(parse_collision_mode) else {
        commands.queue(|world: &mut World| {
            warn_caller(
                world,
                "tilemap.layer.mode: mode is 'passable', 'solid' or 'trigger'",
            );
        });
        return OperatorResult::Cancelled;
    };
    commands.queue(move |world: &mut World| {
        if world.get::<TilemapLayer>(entity).is_none() {
            warn_caller(world, "tilemap.layer.mode: entity is not a tilemap layer");
            return;
        }
        let mut command = SetTileCollisionMode::new(entity, mode);
        command.execute(world);
        world
            .resource_mut::<CommandHistory>()
            .push_executed(Box::new(command));
    });
    OperatorResult::Finished
}

pub(crate) fn parse_collision_mode(text: &str) -> Option<TileCollisionMode> {
    match text.trim().to_ascii_lowercase().as_str() {
        "passable" => Some(TileCollisionMode::Passable),
        "solid" => Some(TileCollisionMode::Solid),
        "trigger" => Some(TileCollisionMode::Trigger),
        _ => None,
    }
}

/// Show or hide a whole layer. One undo entry.
#[operator(
    id = "tilemap.layer.visible",
    label = "Tilemap Layer Visibility",
    description = "Show or hide a tilemap layer.",
    is_available = can_author_tiles,
    params(
        entity(Entity, doc = "The tilemap layer."),
        visible(bool, doc = "True to show, false to hide."),
    )
)]
pub(crate) fn tilemap_layer_visible(
    params: In<OperatorParameters>,
    mut commands: Commands,
) -> OperatorResult {
    let Some(entity) = params.as_entity("entity") else {
        commands.queue(|world: &mut World| {
            warn_caller(world, "tilemap.layer.visible: entity is required");
        });
        return OperatorResult::Cancelled;
    };
    let visible = params.as_bool("visible").unwrap_or(true);
    commands.queue(move |world: &mut World| {
        if world.get::<TilemapLayer>(entity).is_none() {
            warn_caller(
                world,
                "tilemap.layer.visible: entity is not a tilemap layer",
            );
            return;
        }
        let mut command = SetLayerVisible::new(
            entity,
            if visible {
                Visibility::Visible
            } else {
                Visibility::Hidden
            },
        );
        command.execute(world);
        world
            .resource_mut::<CommandHistory>()
            .push_executed(Box::new(command));
    });
    OperatorResult::Finished
}

/// Select the sheet tile strokes cut (the palette's click writes this).
#[operator(
    id = "tilemap.tile.select",
    label = "Select Tile",
    description = "Pick the sheet tile the tilemap strokes cut.",
    allows_undo = false,
    remote_hidden = "session state, not a scene edit",
    params(tile(i64, doc = "Index into the sheet cut: row * columns + column."))
)]
pub(crate) fn tilemap_tile_select(
    params: In<OperatorParameters>,
    mut palette: ResMut<TilemapPalette>,
    mut commands: Commands,
) -> OperatorResult {
    let Some(tile) = params.as_int("tile").map(|tile| tile.max(0) as u32) else {
        commands.queue(|world: &mut World| {
            warn_caller(world, "tilemap.tile.select: tile is required");
        });
        return OperatorResult::Cancelled;
    };
    palette.active_tile = tile;
    OperatorResult::Finished
}

/// Switch what a canvas stroke does.
#[operator(
    id = "tilemap.brush",
    label = "Tilemap Brush",
    description = "Set the tilemap stroke: paint, erase, fill or flood.",
    allows_undo = false,
    remote_hidden = "session state, not a scene edit",
    params(brush(String, doc = "'paint', 'erase', 'fill' or 'flood'."))
)]
pub(crate) fn tilemap_brush(
    params: In<OperatorParameters>,
    mut palette: ResMut<TilemapPalette>,
    mut commands: Commands,
) -> OperatorResult {
    let Some(brush) = params.as_str("brush").and_then(|text| match text.trim() {
        "paint" => Some(TileBrush::Paint),
        "erase" => Some(TileBrush::Erase),
        "fill" => Some(TileBrush::FillRect),
        "flood" => Some(TileBrush::Flood),
        _ => None,
    }) else {
        commands.queue(|world: &mut World| {
            warn_caller(
                world,
                "tilemap.brush: brush is 'paint', 'erase', 'fill' or 'flood'",
            );
        });
        return OperatorResult::Cancelled;
    };
    palette.brush = brush;
    OperatorResult::Finished
}

/// The resolved layer for a stroke operator: the named one, else the
/// palette's active layer.
fn stroke_layer(params: &OperatorParameters, world: &World) -> Result<Entity, String> {
    if let Some(entity) = params.as_entity("layer") {
        return if world.get::<TilemapLayer>(entity).is_some() {
            Ok(entity)
        } else {
            Err("layer is not a tilemap layer".to_owned())
        };
    }
    let palette = world.resource::<TilemapPalette>();
    match palette
        .active_layer
        .filter(|&layer| world.get::<TilemapLayer>(layer).is_some())
    {
        Some(layer) => Ok(layer),
        None => Err("no active tilemap layer: add one with tilemap.layer.add".to_owned()),
    }
}

/// The tile a stroke cuts: the named index, else the palette's.
fn stroke_tile(params: &OperatorParameters, world: &World) -> u32 {
    params
        .as_int("tile")
        .map(|tile| tile.max(0) as u32)
        .unwrap_or(world.resource::<TilemapPalette>().active_tile)
}

/// Clip a stroke to the layer's grid: cells outside `columns`/`rows` do not
/// exist — the collision grid the game builds is exactly this size.
fn clip_cells(cells: Vec<IVec2>, world: &World, layer: Entity) -> Vec<IVec2> {
    let Some(form) = layer_form(world, layer) else {
        return Vec::new();
    };
    cells
        .into_iter()
        .filter(|cell| grid_bounds(&form.0, *cell))
        .collect()
}

/// Whether `cell` sits inside `form`'s sheet cut.
fn grid_bounds(form: &TilemapLayer, cell: IVec2) -> bool {
    cell.x >= 0 && cell.y >= 0 && cell.x < form.columns as i32 && cell.y < form.rows as i32
}

/// Paint cells of a layer: every named cell ends up cutting `tile`. One
/// undo entry per call — a whole drag is one stroke.
#[operator(
    id = "tilemap.paint",
    label = "Paint Tiles",
    description = "Paint tile cells of a tilemap layer: each named cell cuts the tile.",
    is_available = can_author_tiles,
    params(
        layer(Entity, doc = "The tilemap layer. Defaults to the palette's active layer."),
        cells(String, doc = "Cells to paint, as 'x,y;x,y;...'."),
        tile(i64, doc = "Sheet tile index. Defaults to the palette's active tile."),
    )
)]
pub(crate) fn tilemap_paint(params: In<OperatorParameters>, world: &mut World) -> OperatorResult {
    match paint_impl(&params.0, world) {
        Ok(count) => {
            report_to_caller(world, format!("Painted {count} tiles"));
            OperatorResult::Finished
        }
        Err(message) => {
            warn_caller(world, format!("tilemap.paint: {message}"));
            OperatorResult::Cancelled
        }
    }
}

fn paint_impl(params: &OperatorParameters, world: &mut World) -> Result<usize, String> {
    let layer = stroke_layer(params, world)?;
    let cells = clip_cells(
        parse_cells(params.as_str("cells").unwrap_or_default()),
        world,
        layer,
    );
    if cells.is_empty() {
        return Err("no in-bounds cells to paint".to_owned());
    }
    let tile = stroke_tile(params, world);
    let strokes: Vec<(IVec2, u32)> = cells.into_iter().map(|cell| (cell, tile)).collect();
    let count = strokes.len();
    let mut command = PaintTiles::new(layer, strokes, format!("Paint Tiles ({count})"));
    command.execute(world);
    world
        .resource_mut::<CommandHistory>()
        .push_executed(Box::new(command));
    Ok(count)
}

/// Erase cells of a layer. One undo entry per call.
#[operator(
    id = "tilemap.erase",
    label = "Erase Tiles",
    description = "Erase tile cells of a tilemap layer.",
    is_available = can_author_tiles,
    params(
        layer(Entity, doc = "The tilemap layer. Defaults to the palette's active layer."),
        cells(String, doc = "Cells to erase, as 'x,y;x,y;...'."),
    )
)]
pub(crate) fn tilemap_erase(params: In<OperatorParameters>, world: &mut World) -> OperatorResult {
    match erase_impl(&params.0, world) {
        Ok(count) => {
            report_to_caller(world, format!("Erased {count} tiles"));
            OperatorResult::Finished
        }
        Err(message) => {
            warn_caller(world, format!("tilemap.erase: {message}"));
            OperatorResult::Cancelled
        }
    }
}

fn erase_impl(params: &OperatorParameters, world: &mut World) -> Result<usize, String> {
    let layer = stroke_layer(params, world)?;
    let cells = clip_cells(
        parse_cells(params.as_str("cells").unwrap_or_default()),
        world,
        layer,
    );
    if cells.is_empty() {
        return Err("no in-bounds cells to erase".to_owned());
    }
    let count = cells.len();
    let mut command = EraseTiles::new(layer, cells, format!("Erase Tiles ({count})"));
    command.execute(world);
    world
        .resource_mut::<CommandHistory>()
        .push_executed(Box::new(command));
    Ok(count)
}

/// Fill the rectangle from `from` to `to` (corners included) with `tile`.
/// One undo entry.
#[operator(
    id = "tilemap.fill",
    label = "Fill Tile Rect",
    description = "Fill a rectangle of tile cells with one tile.",
    is_available = can_author_tiles,
    params(
        layer(Entity, doc = "The tilemap layer. Defaults to the palette's active layer."),
        from(String, doc = "One corner, as 'x,y'."),
        to(String, doc = "The opposite corner, as 'x,y'."),
        tile(i64, doc = "Sheet tile index. Defaults to the palette's active tile."),
    )
)]
pub(crate) fn tilemap_fill(params: In<OperatorParameters>, world: &mut World) -> OperatorResult {
    match fill_impl(&params.0, world) {
        Ok(count) => {
            report_to_caller(world, format!("Filled {count} tiles"));
            OperatorResult::Finished
        }
        Err(message) => {
            warn_caller(world, format!("tilemap.fill: {message}"));
            OperatorResult::Cancelled
        }
    }
}

fn fill_impl(params: &OperatorParameters, world: &mut World) -> Result<usize, String> {
    let layer = stroke_layer(params, world)?;
    let Some(from) = params.as_str("from").and_then(parse_cell) else {
        return Err("from is required, as 'x,y'".to_owned());
    };
    let Some(to) = params.as_str("to").and_then(parse_cell) else {
        return Err("to is required, as 'x,y'".to_owned());
    };
    let tile = stroke_tile(params, world);
    let cells = clip_cells(cells_in_rect(from, to), world, layer);
    if cells.is_empty() {
        return Err("the rectangle holds no in-bounds cells".to_owned());
    }
    let strokes: Vec<(IVec2, u32)> = cells.into_iter().map(|cell| (cell, tile)).collect();
    let count = strokes.len();
    let mut command = PaintTiles::new(layer, strokes, format!("Fill Rect ({count})"));
    command.execute(world);
    world
        .resource_mut::<CommandHistory>()
        .push_executed(Box::new(command));
    Ok(count)
}

/// Flood fill: the connected region of cells sharing `at`'s tile becomes
/// `tile`. The differing-tile border stops the flood. One undo entry.
#[operator(
    id = "tilemap.fill.flood",
    label = "Flood Fill Tiles",
    description = "Flood fill the connected region of one tile with another.",
    is_available = can_author_tiles,
    params(
        layer(Entity, doc = "The tilemap layer. Defaults to the palette's active layer."),
        at(String, doc = "The seed cell, as 'x,y'."),
        tile(i64, doc = "Sheet tile index. Defaults to the palette's active tile."),
    )
)]
pub(crate) fn tilemap_flood(params: In<OperatorParameters>, world: &mut World) -> OperatorResult {
    match flood_impl(&params.0, world) {
        Ok(count) => {
            report_to_caller(world, format!("Flooded {count} tiles"));
            OperatorResult::Finished
        }
        Err(message) => {
            warn_caller(world, format!("tilemap.fill.flood: {message}"));
            OperatorResult::Cancelled
        }
    }
}

fn flood_impl(params: &OperatorParameters, world: &mut World) -> Result<usize, String> {
    let layer = stroke_layer(params, world)?;
    let Some(at) = params.as_str("at").and_then(parse_cell) else {
        return Err("at is required, as 'x,y'".to_owned());
    };
    let Some((form, _)) = layer_form(world, layer) else {
        return Err("the layer is gone".to_owned());
    };
    let tile = stroke_tile(params, world);
    // Empty cells are a floodable region too: the flood's "tile" is a
    // sentinel for none, so an empty seed fills the connected empties
    // while the grid border (out of bounds) still stops it.
    const EMPTY: u32 = u32::MAX;
    let region = flood_cells(at, UVec2::new(form.columns, form.rows), |cell| {
        if !grid_bounds(&form, cell) {
            return None;
        }
        Some(
            tile_at_cell(world, layer, cell)
                .map(|(_, tile)| tile)
                .unwrap_or(EMPTY),
        )
    });
    let strokes: Vec<(IVec2, u32)> = region
        .into_iter()
        .filter(|&cell| {
            tile_at_cell(world, layer, cell).map(|(_, existing)| existing) != Some(tile)
        })
        .map(|cell| (cell, tile))
        .collect();
    if strokes.is_empty() {
        return Err("the region already cuts that tile".to_owned());
    }
    let count = strokes.len();
    let mut command = PaintTiles::new(layer, strokes, format!("Flood Fill ({count})"));
    command.execute(world);
    world
        .resource_mut::<CommandHistory>()
        .push_executed(Box::new(command));
    Ok(count)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_cell_reads_negatives() {
        assert_eq!(parse_cell("3,1"), Some(IVec2::new(3, 1)));
        assert_eq!(parse_cell("-1,-2"), Some(IVec2::new(-1, -2)));
        assert_eq!(parse_cell(" 4 , 5 "), Some(IVec2::new(4, 5)));
        assert_eq!(parse_cell("3"), None);
        assert_eq!(parse_cell("a,b"), None);
    }

    #[test]
    fn parse_cells_collapses_drag_revisits() {
        assert_eq!(
            parse_cells("0,0;1,0;1,0;2,0"),
            vec![IVec2::new(0, 0), IVec2::new(1, 0), IVec2::new(2, 0)]
        );
        assert!(parse_cells("").is_empty());
        assert!(parse_cells("garbage").is_empty());
    }

    #[test]
    fn cells_in_rect_covers_both_orders_row_major() {
        let a = cells_in_rect(IVec2::new(1, 0), IVec2::new(2, 1));
        let b = cells_in_rect(IVec2::new(2, 1), IVec2::new(1, 0));
        assert_eq!(a, b, "corner order does not matter");
        assert_eq!(
            a,
            vec![
                IVec2::new(1, 0),
                IVec2::new(2, 0),
                IVec2::new(1, 1),
                IVec2::new(2, 1),
            ]
        );
        assert_eq!(
            cells_in_rect(IVec2::new(3, 3), IVec2::new(3, 3)),
            vec![IVec2::new(3, 3)]
        );
    }

    /// A 4x2 testbed: tile 1 in (0,0)-(1,0), tile 2 in (2,0) and (3,0),
    /// open tile 0 across the top row, `None` outside.
    fn same_tile() -> impl Fn(IVec2) -> Option<u32> {
        |cell: IVec2| match (cell.x, cell.y) {
            (0, 0) | (1, 0) => Some(1),
            (2, 0) | (3, 0) => Some(2),
            _ if cell.x < 0 || cell.x > 3 || cell.y < 0 || cell.y > 1 => None,
            _ => Some(0),
        }
    }

    #[test]
    fn flood_spreads_through_equal_tiles_and_stops_at_the_border() {
        let region = flood_cells(IVec2::ZERO, UVec2::new(4, 2), same_tile());
        assert_eq!(
            region,
            vec![IVec2::new(0, 0), IVec2::new(1, 0)],
            "tile 1's region grows through (1,0) and stops at tile 2 and tile 0"
        );
        let empty = flood_cells(IVec2::new(0, 1), UVec2::new(4, 2), same_tile());
        assert_eq!(
            empty,
            vec![
                IVec2::new(0, 1),
                IVec2::new(1, 1),
                IVec2::new(2, 1),
                IVec2::new(3, 1),
            ],
            "the open tile 0 spans the top row up to the border tiles below"
        );
    }

    #[test]
    fn flood_of_a_single_tile_region_is_that_cell_alone() {
        let region = flood_cells(IVec2::new(2, 0), UVec2::new(4, 2), same_tile());
        assert_eq!(
            region,
            vec![IVec2::new(2, 0), IVec2::new(3, 0)],
            "tile 2 spans (2,0)-(3,0); the flood covers both"
        );
    }

    #[test]
    fn flood_of_an_out_of_bounds_seed_is_empty() {
        assert!(flood_cells(IVec2::new(-1, 0), UVec2::new(4, 2), same_tile()).is_empty());
        assert!(flood_cells(IVec2::new(9, 0), UVec2::new(4, 2), same_tile()).is_empty());
    }

    #[test]
    fn tile_rect_cuts_the_sheet_by_index() {
        let layer = TilemapLayer {
            cell_size: Vec2::splat(32.0),
            columns: 4,
            rows: 2,
            ..default()
        };
        assert_eq!(layer.tile_rect(0), Rect::new(0.0, 0.0, 32.0, 32.0));
        assert_eq!(layer.tile_rect(3), Rect::new(96.0, 0.0, 128.0, 32.0));
        assert_eq!(
            layer.tile_rect(4),
            Rect::new(0.0, 32.0, 32.0, 64.0),
            "row 1"
        );
        assert_eq!(layer.cell_center(IVec2::new(0, 0)), Vec2::new(16.0, 16.0));
        assert_eq!(layer.world_to_cell(Vec2::new(33.0, 16.0)), IVec2::new(1, 0));
        assert_eq!(
            layer.world_to_cell(Vec2::new(-1.0, 16.0)),
            IVec2::new(-1, 0),
            "floor division"
        );
    }
}
