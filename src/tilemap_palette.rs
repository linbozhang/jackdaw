//! The Tilemap tool's faces on the 2D canvas: the palette panel, the paint
//! stroke, and the trigger overlay.
//!
//! The panel (plan decision 4-A): the active layer's whole sheet displayed
//! with the grid over it — clicking a cell selects the sheet tile the strokes
//! cut — above the brush row (paint / erase / fill / flood), the tile readout
//! and one row per [`TilemapLayer`] (active, collision mode, visibility). It
//! rides on the fronted 2D panel's clipping area while the Tilemap tool is
//! active, the way the terrain palette rides on the 3D one.
//!
//! The stroke is a modal operator on the left button: a drag visits cells,
//! and the release dispatches one batch operator (`tilemap.paint` /
//! `tilemap.erase` / `tilemap.fill`) — so the whole drag is one undo entry,
//! and a remote caller reading only the operators walks the exact path the
//! mouse does. Flood is a click: it dispatches on the press.
//!
//! The trigger overlay (plan TM7) draws each `Trigger` layer's tiles with a
//! translucent cyan ring while the tool is out, the T10 sensor pattern.

use bevy::{
    input::{ButtonInput, mouse::MouseButton},
    math::Isometry2d,
    picking::{events::PointerPress, pointer::PointerButton as PickButton},
    prelude::*,
    text::FontSize,
    ui::UiScale,
};
use jackdaw_api::prelude::*;
use jackdaw_api_internal::{
    lifecycle::{ActiveModalQuery, OperatorAction},
    tools::ToolStatus,
};
use jackdaw_feathers::{icons::Icon, tokens};
use jackdaw_input::{ActionOf, Condition, bindings};
use jackdaw_scene_types::{TileCollisionMode, TileGridCell, TilemapLayer};

use crate::{
    active_tool::ActiveTool,
    sprite_stage::stage_world_point,
    tilemap::{
        TileBrush, TilemapBrushOp, TilemapEraseOp, TilemapFillOp, TilemapFloodOp,
        TilemapLayerActiveOp, TilemapLayerAddOp, TilemapLayerModeOp, TilemapLayerVisibleOp,
        TilemapPaintOp, TilemapPalette, TilemapTileSelectOp,
    },
    viewport_2d::{FrontedViewport, Scene2dViewport, Viewport2dMode, Viewport2dPanelHost},
};

/// How wide the sheet display renders, whatever the sheet's pixel size.
const SHEET_DISPLAY_WIDTH: f32 = 168.0;

/// The trigger overlay tint: the T10 sensor cyan, translucent.
const TRIGGER_TINT: Color = Color::srgba(0.0, 0.9, 0.9, 0.55);

pub(crate) fn plugin(app: &mut App) {
    app.init_resource::<TileStrokeState>()
        .init_resource::<PendingStrokeDispatch>()
        .add_systems(
            Update,
            (
                sync_palette_panel,
                sync_palette_content,
                sync_tile_highlight,
                sync_brush_button_look,
            )
                .chain()
                .run_if(in_state(crate::AppState::Editor)),
        )
        // The finished stroke's batch dispatch: runs after the stroke modal
        // retired (see `PendingStrokeDispatch` for the ordering story).
        .add_systems(Update, apply_pending_stroke)
        .add_systems(
            PostUpdate,
            draw_trigger_overlays.in_set(crate::JackdawDrawSystems),
        )
        .add_observer(on_sheet_press)
        .add_observer(on_layer_row_press)
        .add_observer(on_mode_badge_press)
        .add_observer(on_eye_press)
        .add_observer(on_add_layer_press)
        .add_observer(on_brush_button_press);
}

pub(crate) fn add_to_extension(ctx: &mut ExtensionContext) {
    ctx.register_operator::<TilemapStrokeOp>();
    // Deferred binding: a mouse button arms with an explicit Press clause,
    // the measure tool's shape. The stroke arms on the Tilemap tool being
    // out, so a left press on the canvas is a stroke there and stays a
    // selection everywhere else.
    ctx.entity_mut().with_related::<ActionOf>((
        OperatorAction(TilemapStrokeOp::ID),
        bindings![(MouseButton::Left, Condition::Press)],
    ));
}

// ---------------------------------------------------------------------------
// panel
// ---------------------------------------------------------------------------

/// The palette panel's root, a child of the fronted 2D panel's clipping area.
#[derive(Component)]
struct TilemapPalettePanel;

/// The sheet display node — the whole sheet with the grid over it.
#[derive(Component)]
struct TilemapSheet;

/// The highlight over the active tile's cell.
#[derive(Component)]
struct TilemapHighlight;

/// The tile-index readout under the sheet.
#[derive(Component)]
struct TilemapTileLabel;

/// One layer row; carries the layer it names.
#[derive(Component)]
struct TilemapLayerRow(Entity);

/// The row's collision-mode badge; clicking cycles the mode.
#[derive(Component)]
struct TilemapModeBadge(Entity);

/// The row's visibility toggle.
#[derive(Component)]
struct TilemapEye(Entity);

/// A brush switch; carries what it switches to.
#[derive(Component)]
struct TilemapBrushButton(TileBrush);

/// The add-layer button.
#[derive(Component)]
struct AddLayerButton;

/// What the panel last rendered, so content rebuilds only on a real
/// change. A resource, not a `Local`: the rebuild is an exclusive system
/// (it reads the world's layers and spawns its nodes directly), and
/// exclusive systems take no `Local`.
#[derive(Resource, Default)]
struct PanelFingerprint(PaneState);

#[derive(Default, PartialEq, Clone)]
struct PaneState {
    layers: Vec<(Entity, String, TileCollisionMode, bool)>,
    active_layer: Option<Entity>,
    active_tile: u32,
    brush: TileBrush,
    sheet: Option<(Entity, u32, u32, Vec2)>,
}

impl PanelFingerprint {
    fn read(world: &mut World) -> Self {
        let (active_layer, active_tile, brush) = {
            let palette = world.resource::<TilemapPalette>();
            (palette.active_layer, palette.active_tile, palette.brush)
        };
        let state = PaneState {
            layers: Self::layers(world),
            active_layer,
            active_tile,
            brush,
            sheet: Self::sheet(world),
        };
        Self(state)
    }

    fn layers(world: &mut World) -> Vec<(Entity, String, TileCollisionMode, bool)> {
        let mut layers: Vec<(Entity, String, TileCollisionMode, bool)> = world
            .query::<(
                Entity,
                &Name,
                &TileCollisionMode,
                &Visibility,
                &TilemapLayer,
            )>()
            .iter(world)
            .map(|(entity, name, mode, visible, _)| {
                (
                    entity,
                    name.as_str().to_owned(),
                    *mode,
                    *visible == Visibility::Visible,
                )
            })
            .collect();
        layers.sort_by_key(|(entity, ..)| *entity);
        layers
    }

    fn sheet(world: &mut World) -> Option<(Entity, u32, u32, Vec2)> {
        let layer = world.resource::<TilemapPalette>().active_layer?;
        world
            .get::<TilemapLayer>(layer)
            .map(|form| (layer, form.columns, form.rows, form.cell_size))
    }
}

/// Spawn the panel on the fronted 2D panel while the Tilemap tool is out,
/// and take it away otherwise.
fn sync_palette_panel(
    mode: Res<ActiveTool>,
    fronted: FrontedViewport,
    mut commands: Commands,
    panels: Query<Entity, With<TilemapPalettePanel>>,
) {
    let tool_is_out = *mode == ActiveTool::Tilemap;
    let area = tool_is_out
        .then(|| fronted.two_d_host())
        .flatten()
        .map(|host| host.area);
    match (area, panels.iter().next()) {
        (Some(area), Some(panel)) => {
            // Re-parent when another 2D panel came to the front.
            commands.entity(panel).insert(ChildOf(area));
        }
        (Some(area), None) => {
            commands.spawn((
                TilemapPalettePanel,
                Name::new("Tilemap Palette"),
                Node {
                    position_type: PositionType::Absolute,
                    right: px(tokens::SPACING_MD),
                    top: px(tokens::TOOLBAR_HEIGHT + tokens::SPACING_MD),
                    width: px(SHEET_DISPLAY_WIDTH + 2.0 * tokens::SPACING_MD),
                    flex_direction: FlexDirection::Column,
                    align_items: AlignItems::Center,
                    padding: UiRect::all(px(tokens::SPACING_MD)),
                    row_gap: px(tokens::SPACING_SM),
                    border_radius: BorderRadius::all(px(tokens::BORDER_RADIUS_LG)),
                    ..default()
                },
                BackgroundColor(tokens::TOOLBAR_BG.with_alpha(0.92)),
                ChildOf(area),
            ));
            // `sync_palette_content` fills the panel on its next pass: the
            // local fingerprint still reads the empty default.
        }
        (None, Some(panel)) => {
            commands.entity(panel).despawn();
        }
        (None, None) => {}
    }
}

/// Rebuild the panel's content when anything it names changed. Exclusive:
/// the fingerprint read walks the layers, and the nodes spawn straight
/// into the world.
fn sync_palette_content(world: &mut World) {
    let current = PanelFingerprint::read(world);
    if world
        .get_resource::<PanelFingerprint>()
        .is_some_and(|fingerprint| fingerprint.0 == current.0)
    {
        return;
    }
    if let Some(mut stored) = world.get_resource_mut::<PanelFingerprint>() {
        stored.0 = current.0.clone();
    } else {
        world.insert_resource(PanelFingerprint(current.0.clone()));
    }
    let Some(panel) = world
        .query_filtered::<Entity, With<TilemapPalettePanel>>()
        .iter(world)
        .next()
    else {
        return;
    };
    if let Some(children) = world
        .get::<Children>(panel)
        .map(|children| children.iter().collect::<Vec<_>>())
    {
        for child in children {
            world.entity_mut(child).despawn();
        }
    }

    world.spawn((caption("Tilemap"), ChildOf(panel)));

    // The brush row.
    let brush_row = world
        .spawn((
            Node {
                flex_direction: FlexDirection::Row,
                column_gap: px(tokens::SPACING_SM),
                ..default()
            },
            ChildOf(panel),
        ))
        .id();
    for (brush, label) in [
        (TileBrush::Paint, "Paint"),
        (TileBrush::Erase, "Erase"),
        (TileBrush::FillRect, "Fill"),
        (TileBrush::Flood, "Flood"),
    ] {
        world.spawn((
            TilemapBrushButton(brush),
            text_button(label),
            ChildOf(brush_row),
        ));
    }

    // The sheet display, sized to `SHEET_DISPLAY_WIDTH` across.
    if let Some((layer, columns, rows, cell_size)) = current.0.sheet {
        let sheet = spawn_sheet(world, panel, layer, columns, rows, cell_size).unwrap_or(panel);
        // The active tile's highlight, repositioned by `sync_tile_highlight`.
        let cell_px = cell_display_px(cell_size, columns);
        world.spawn((
            TilemapHighlight,
            Node {
                position_type: PositionType::Absolute,
                width: px(cell_px),
                height: px(cell_px),
                border: UiRect::all(px(1.5)),
                ..default()
            },
            BorderColor::all(tokens::TEXT_PRIMARY),
            ChildOf(sheet),
        ));
    }

    // The tile readout.
    world.spawn((
        TilemapTileLabel,
        Text::new(format!("Tile {}", current.0.active_tile)),
        TextFont {
            font_size: tokens::TEXT_SIZE_SM,
            ..default()
        },
        TextColor(tokens::TEXT_SECONDARY),
        ChildOf(panel),
    ));

    // One row per layer: eye (click = toggle), mode badge (click = cycle),
    // name (click = active).
    for (entity, name, mode, visible) in &current.0.layers {
        let row = world
            .spawn((
                TilemapLayerRow(*entity),
                Node {
                    flex_direction: FlexDirection::Row,
                    align_items: AlignItems::Center,
                    column_gap: px(tokens::SPACING_SM),
                    width: percent(100),
                    ..default()
                },
                Pickable::default(),
                ChildOf(panel),
            ))
            .id();
        let glyph = String::from(if *visible { Icon::Eye } else { Icon::EyeOff }.unicode());
        world.spawn((
            TilemapEye(*entity),
            Text::new(glyph),
            icon_text_font(world),
            Pickable::default(),
            ChildOf(row),
        ));
        world.spawn((
            TilemapModeBadge(*entity),
            Text::new(mode_letter(mode)),
            TextFont {
                font_size: tokens::TEXT_SIZE_SM,
                ..default()
            },
            TextColor(mode_color(mode)),
            Pickable::default(),
            ChildOf(row),
        ));
        world.spawn((
            Text::new(name.clone()),
            TextFont {
                font_size: tokens::TEXT_SIZE_SM,
                ..default()
            },
            Pickable::default(),
            ChildOf(row),
        ));
    }

    // The layer-adding affordance.
    world.spawn((AddLayerButton, text_button("+ Add Layer"), ChildOf(panel)));
}

fn mode_letter(mode: &TileCollisionMode) -> &'static str {
    match mode {
        TileCollisionMode::Passable => "P",
        TileCollisionMode::Solid => "S",
        TileCollisionMode::Trigger => "T",
    }
}

fn mode_color(mode: &TileCollisionMode) -> Color {
    match mode {
        TileCollisionMode::Passable => tokens::TEXT_SECONDARY,
        TileCollisionMode::Solid => tokens::AXIS_X_COLOR,
        TileCollisionMode::Trigger => tokens::AXIS_Z_COLOR,
    }
}

fn caption(text: &str) -> Text {
    Text::new(text.to_owned())
}

/// The eye glyph's font: the editor's lucide icon font, so `Icon::Eye`
/// renders as a glyph rather than a box. Without the resource the editor
/// never finished starting; a family fallback keeps the row readable.
fn icon_text_font(world: &World) -> TextFont {
    TextFont {
        font: world
            .get_resource::<jackdaw_feathers::icons::IconFont>()
            .map(|icons| FontSource::Handle(icons.0.clone()))
            .unwrap_or(FontSource::Family("lucide".into())),
        font_size: FontSize::Px(12.0),
        ..default()
    }
}

/// A small clickable text button: node look, text, and pickability in one.
fn text_button(label: &str) -> impl Bundle {
    (
        Node {
            padding: UiRect::all(px(2.0)),
            border_radius: BorderRadius::all(px(tokens::BORDER_RADIUS_SM)),
            ..default()
        },
        BackgroundColor(tokens::CHIP_BG),
        Text::new(label.to_owned()),
        TextFont {
            font_size: tokens::TEXT_SIZE_SM,
            ..default()
        },
        TextColor(tokens::TEXT_PRIMARY),
        Pickable::default(),
    )
}

/// The display size, in panel pixels, of one sheet cell at
/// [`SHEET_DISPLAY_WIDTH`] across.
fn cell_display_px(cell_size: Vec2, columns: u32) -> f32 {
    let sheet_px = columns.max(1) as f32 * cell_size.x.max(1.0);
    (cell_size.x.max(1.0)) * SHEET_DISPLAY_WIDTH / sheet_px
}

/// Spawn the sheet display: the layer's whole sheet with the grid lines over
/// it. `None` (nothing spawned) when the layer is gone.
fn spawn_sheet(
    world: &mut World,
    panel: Entity,
    layer: Entity,
    columns: u32,
    rows: u32,
    cell_size: Vec2,
) -> Option<Entity> {
    let form = world.get::<TilemapLayer>(layer)?.clone();
    let cell_px = cell_display_px(cell_size, columns);
    let sheet = world
        .spawn((
            TilemapSheet,
            Node {
                width: px(SHEET_DISPLAY_WIDTH),
                height: px(rows.max(1) as f32 * cell_px),
                ..default()
            },
            BackgroundColor(Color::srgb(0.16, 0.16, 0.18)),
            Pickable::default(),
            ChildOf(panel),
        ))
        .id();
    let has_image = form
        .image
        .path()
        .is_some_and(|path| !path.path().as_os_str().is_empty());
    if has_image {
        world
            .entity_mut(sheet)
            .insert(ImageNode::new(form.image.clone()));
    }
    // Grid lines: one per interior column and row, over the sheet.
    for column in 1..columns {
        world.spawn((
            Node {
                position_type: PositionType::Absolute,
                left: px(column as f32 * cell_px),
                top: px(0.0),
                width: px(1.0),
                height: percent(100),
                ..default()
            },
            BackgroundColor(Color::srgba(1.0, 1.0, 1.0, 0.15)),
            ChildOf(sheet),
        ));
    }
    for row in 1..rows {
        world.spawn((
            Node {
                position_type: PositionType::Absolute,
                left: px(0.0),
                top: px(row as f32 * cell_px),
                width: percent(100),
                height: px(1.0),
                ..default()
            },
            BackgroundColor(Color::srgba(1.0, 1.0, 1.0, 0.15)),
            ChildOf(sheet),
        ));
    }
    Some(sheet)
}

/// Put the highlight over the active tile's cell.
fn sync_tile_highlight(
    palette: Res<TilemapPalette>,
    layers: Query<&TilemapLayer>,
    mut highlights: Query<&mut Node, With<TilemapHighlight>>,
) {
    let Ok(mut node) = highlights.single_mut() else {
        return;
    };
    let Some(layer) = palette
        .active_layer
        .and_then(|layer| layers.get(layer).ok())
    else {
        return;
    };
    let cell_px = cell_display_px(layer.cell_size, layer.columns);
    let column = palette.active_tile % layer.columns;
    let row = palette.active_tile / layer.columns;
    let left = Val::Px(column as f32 * cell_px);
    // The grid is y up (row 0 at the bottom), the display is y down.
    let top_row = layer.rows.saturating_sub(1).min(row);
    let top = Val::Px((layer.rows.saturating_sub(1) - top_row) as f32 * cell_px);
    if node.left != left {
        node.left = left;
    }
    if node.top != top {
        node.top = top;
    }
}

/// Recolor the active brush button's label.
fn sync_brush_button_look(
    palette: Res<TilemapPalette>,
    mut buttons: Query<(&TilemapBrushButton, &mut TextColor)>,
) {
    for (button, mut color) in &mut buttons {
        let target = if button.0 == palette.brush {
            tokens::TEXT_PRIMARY
        } else {
            tokens::TEXT_SECONDARY
        };
        if color.0 != target {
            color.0 = target;
        }
    }
}

// ---------------------------------------------------------------------------
// panel observers — every one dispatches the same operators a remote caller
// does
// ---------------------------------------------------------------------------

/// Click the sheet: the cell under the press becomes the active tile.
fn on_sheet_press(
    event: On<PointerPress>,
    sheets: Query<(&ComputedNode, &UiGlobalTransform), With<TilemapSheet>>,
    layers: Query<&TilemapLayer>,
    palette: Res<TilemapPalette>,
    ui_scale: Res<UiScale>,
    mut commands: Commands,
) {
    if event.button != PickButton::Primary {
        return;
    }
    let Some(layer) = palette
        .active_layer
        .and_then(|layer| layers.get(layer).ok())
    else {
        return;
    };
    let Ok((computed, transform)) = sheets.get(event.entity) else {
        return;
    };
    let cell_px = cell_display_px(layer.cell_size, layer.columns);
    // The node-centre offset in display pixels: the same mapping
    // `stage_offset_clamped` uses, without its clamp.
    let cursor = event.pointer.position / ui_scale.0;
    let offset = cursor / computed.inverse_scale_factor() - transform.translation;
    let column = ((offset.x + computed.size.x * 0.5) / cell_px)
        .floor()
        .clamp(0.0, layer.columns as f32 - 1.0);
    let row = ((-offset.y + computed.size.y * 0.5) / cell_px)
        .floor()
        .clamp(0.0, layer.rows as f32 - 1.0);
    // The display is y down; the grid is y up, so the display's top row is
    // the grid's last row.
    let index = (layer.rows - 1 - row as u32) * layer.columns + column as u32;
    let tile = i64::from(index);
    commands.queue(move |world: &mut World| {
        let _ = world
            .operator(TilemapTileSelectOp::ID)
            .param("tile", tile)
            .call();
    });
}

fn dispatch_layer_op(
    commands: &mut Commands,
    op: &'static str,
    layer: Entity,
    params: &[(&'static str, String)],
) {
    let params: Vec<(&'static str, String)> = params.to_vec();
    commands.queue(move |world: &mut World| {
        let mut call = world.operator(op).param("entity", layer);
        for (key, value) in params {
            call = call.param(key, value);
        }
        let _ = call.call();
    });
}

fn on_layer_row_press(
    event: On<PointerPress>,
    rows: Query<&TilemapLayerRow>,
    mut commands: Commands,
) {
    let Some(layer) = rows.get(event.entity).ok().map(|row| row.0) else {
        return;
    };
    dispatch_layer_op(&mut commands, TilemapLayerActiveOp::ID, layer, &[]);
}

fn on_mode_badge_press(
    event: On<PointerPress>,
    badges: Query<&TilemapModeBadge>,
    modes: Query<&TileCollisionMode>,
    mut commands: Commands,
) {
    let Some(layer) = badges.get(event.entity).ok().map(|badge| badge.0) else {
        return;
    };
    let next = match modes.get(layer) {
        Ok(TileCollisionMode::Passable) => TileCollisionMode::Solid,
        Ok(TileCollisionMode::Solid) => TileCollisionMode::Trigger,
        _ => TileCollisionMode::Passable,
    };
    let name = match next {
        TileCollisionMode::Passable => "passable".to_owned(),
        TileCollisionMode::Solid => "solid".to_owned(),
        TileCollisionMode::Trigger => "trigger".to_owned(),
    };
    dispatch_layer_op(
        &mut commands,
        TilemapLayerModeOp::ID,
        layer,
        &[("mode", name)],
    );
}

fn on_eye_press(
    event: On<PointerPress>,
    eyes: Query<&TilemapEye>,
    visibilities: Query<&Visibility>,
    mut commands: Commands,
) {
    let Some(layer) = eyes.get(event.entity).ok().map(|eye| eye.0) else {
        return;
    };
    let shown = visibilities
        .get(layer)
        .is_ok_and(|visible| *visible == Visibility::Visible);
    let visible = (!shown).to_string();
    dispatch_layer_op(
        &mut commands,
        TilemapLayerVisibleOp::ID,
        layer,
        &[("visible", visible)],
    );
}

fn on_add_layer_press(
    event: On<PointerPress>,
    buttons: Query<(), With<AddLayerButton>>,
    mut commands: Commands,
) {
    // The press bubbles up from whatever node was hit; this handler only
    // answers for the button itself.
    if buttons.get(event.entity).is_err() {
        return;
    }
    commands.queue(|world: &mut World| {
        let _ = world.operator(TilemapLayerAddOp::ID).call();
    });
}

fn on_brush_button_press(
    event: On<PointerPress>,
    buttons: Query<&TilemapBrushButton>,
    mut commands: Commands,
) {
    let Some(brush) = buttons.get(event.entity).ok().map(|button| button.0) else {
        return;
    };
    let name = match brush {
        TileBrush::Paint => "paint",
        TileBrush::Erase => "erase",
        TileBrush::FillRect => "fill",
        TileBrush::Flood => "flood",
    }
    .to_owned();
    commands.queue(move |world: &mut World| {
        let _ = world
            .operator(TilemapBrushOp::ID)
            .param("brush", name)
            .call();
    });
}

// ---------------------------------------------------------------------------
// the stroke
// ---------------------------------------------------------------------------

/// A finished stroke waiting to land: which batch operator applies it, for
/// which layer, cutting which tile, over which cells.
struct PendingStroke {
    op: &'static str,
    layer: Entity,
    tile: u32,
    cells: String,
}

/// A finished rect fill waiting to land.
struct PendingFill {
    layer: Entity,
    tile: u32,
    from: IVec2,
    to: IVec2,
}

/// One stroke's batch dispatch, deferred by a frame. The modal's own last
/// frame cannot call the batch operator: the frame the stroke returns
/// `Finished`, the modal's `ActiveModalOperator` marker is only torn down
/// moments later by the same tick, and a call made inside that window is
/// refused as nested (`can_act_on_entities` sees the modal and stands the
/// operator down — the whole stroke then lands nothing). The applier runs
/// the next frame, once the modal has retired.
#[derive(Resource, Default)]
struct PendingStrokeDispatch(Option<StrokeDispatch>);

/// Which batch operator a finished stroke lands, and with what.
enum StrokeDispatch {
    Cells(PendingStroke),
    Fill(PendingFill),
}

/// Apply a finished stroke's batch dispatch, one frame after the modal
/// retired.
fn apply_pending_stroke(
    mut pending: ResMut<PendingStrokeDispatch>,
    active: ActiveModalQuery,
    mut commands: Commands,
) {
    let Some(stroke) = pending.0.take() else {
        return;
    };
    if active.is_modal_running() {
        // Still retiring this frame; the next one lands it.
        pending.0 = Some(stroke);
        return;
    }
    match stroke {
        StrokeDispatch::Cells(stroke) => {
            commands.queue(move |world: &mut World| {
                let _ = world
                    .operator(stroke.op)
                    .param("layer", stroke.layer)
                    .param("tile", i64::from(stroke.tile))
                    .param("cells", stroke.cells)
                    .call();
            });
        }
        StrokeDispatch::Fill(fill) => {
            commands.queue(move |world: &mut World| {
                let _ = world
                    .operator(TilemapFillOp::ID)
                    .param("layer", fill.layer)
                    .param("tile", i64::from(fill.tile))
                    .param("from", format!("{},{}", fill.from.x, fill.from.y))
                    .param("to", format!("{},{}", fill.to.x, fill.to.y))
                    .call();
            });
        }
    }
}

/// The stroke's state across frames: which layer and panel host it captured,
/// and which cells it visited.
#[derive(Resource, Default)]
struct TileStrokeState {
    initialized: bool,
    layer: Option<Entity>,
    /// The panel content entity carrying the [`Viewport2dPanelHost`] — NOT
    /// the stage node it points at; the host component lives on the panel,
    /// and querying it on the stage answered nothing every frame (the
    /// stroke held until cancel).
    host: Option<Entity>,
    start: Option<IVec2>,
    visited: std::collections::HashSet<IVec2>,
}

/// The stroke's cell under the cursor, or `None` when the cursor is off the
/// captured stage or the layer is gone.
fn stroke_cell(
    state: &TileStrokeState,
    cursor: Vec2,
    hosts: &Query<(Entity, &Viewport2dPanelHost)>,
    stages: &Query<(&ComputedNode, &UiGlobalTransform), With<Scene2dViewport>>,
    layers: &Query<(&TilemapLayer, &GlobalTransform)>,
) -> Option<IVec2> {
    let layer = state.layer?;
    let (_, host) = hosts.get(state.host?).ok()?;
    let (computed, transform) = stages.get(host.stage).ok()?;
    let (point, inside) = stage_world_point(cursor, host, computed, transform);
    if !inside {
        return None;
    }
    let (form, global) = layers.get(layer).ok()?;
    let local = global
        .affine()
        .inverse()
        .transform_point3(point.extend(0.0));
    Some(form.world_to_cell(local.truncate()))
}

fn stroke_available(
    mode: Res<ActiveTool>,
    fronted: FrontedViewport,
    palette: Res<TilemapPalette>,
    layers: Query<(), With<TilemapLayer>>,
) -> bool {
    *mode == ActiveTool::Tilemap
        && fronted
            .two_d_host()
            .is_some_and(|host| host.mode == Viewport2dMode::Edit)
        && palette
            .active_layer
            .is_some_and(|layer| layers.contains(layer))
}

/// The Tilemap tool's stroke: a left-button drag on the 2D canvas. The
/// release dispatches one batch operator — one stroke, one undo entry — so
/// this modal itself never touches the history.
#[operator(
    id = "tilemap.stroke",
    label = "Tilemap Stroke",
    description = "Paint, erase or fill tile cells by dragging on the canvas.",
    modal = true,
    allows_undo = false,
    cancel = cancel_stroke,
    is_available = stroke_available,
    remote_hidden = "a pointer gesture; call the batch operators instead",
)]
pub(crate) fn tilemap_stroke(
    _: In<OperatorParameters>,
    mut state: ResMut<TileStrokeState>,
    palette: ResMut<TilemapPalette>,
    vp: crate::viewport::ViewportCursor,
    mouse: Res<ButtonInput<MouseButton>>,
    modal_inputs: crate::modal_inputs::ModalInputs,
    hosts: Query<(Entity, &Viewport2dPanelHost)>,
    stages: Query<(&ComputedNode, &UiGlobalTransform), With<Scene2dViewport>>,
    layers: Query<(&TilemapLayer, &GlobalTransform)>,
    mut pending: ResMut<PendingStrokeDispatch>,
    mut tool_status: ResMut<ToolStatus>,
) -> Option<OperatorResult> {
    if !state.initialized {
        // Viewport capture is deferred so the modal can start from the
        // toolbar or the palette button, where the cursor is over neither.
        state.initialized = true;
        state.layer = palette.active_layer;
        state.host = fronted_host_entity(&hosts, &stages);
        state.visited.clear();
        state.start = None;
        tool_status.0 = Some(stroke_hint(palette.brush).to_owned());
        if palette.brush == TileBrush::Flood {
            // A flood is a click, not a drag: seed at the press and finish.
            if let Some(cell) = vp
                .cursor()
                .and_then(|cursor| stroke_cell(&state, cursor, &hosts, &stages, &layers))
                && let Some(layer) = state.layer
            {
                pending.0 = Some(StrokeDispatch::Cells(PendingStroke {
                    op: TilemapFloodOp::ID,
                    layer,
                    tile: palette.active_tile,
                    cells: format!("{},{}", cell.x, cell.y),
                }));
            }
            reset_stroke(&mut state, &mut tool_status);
            return Some(OperatorResult::Finished);
        }
        if palette.brush == TileBrush::FillRect {
            state.start = vp
                .cursor()
                .and_then(|cursor| stroke_cell(&state, cursor, &hosts, &stages, &layers));
        }
        return Some(OperatorResult::Running);
    }

    if modal_inputs.cancel() || mouse.just_pressed(MouseButton::Right) {
        reset_stroke(&mut state, &mut tool_status);
        return None;
    }

    let Some(layer) = state.layer.filter(|&layer| layers.contains(layer)) else {
        reset_stroke(&mut state, &mut tool_status);
        return Some(OperatorResult::Finished);
    };
    let Some(cursor) = vp.cursor() else {
        return Some(OperatorResult::Running);
    };
    let Some(cell) = stroke_cell(&state, cursor, &hosts, &stages, &layers) else {
        return Some(OperatorResult::Running);
    };

    if palette.brush == TileBrush::FillRect {
        state.start = state.start.or(Some(cell));
    } else {
        state.visited.insert(cell);
    }

    if !mouse.just_released(MouseButton::Left) {
        return Some(OperatorResult::Running);
    }

    let tile = palette.active_tile;
    match palette.brush {
        TileBrush::Paint | TileBrush::Erase => {
            let op = if palette.brush == TileBrush::Paint {
                TilemapPaintOp::ID
            } else {
                TilemapEraseOp::ID
            };
            let cells = state
                .visited
                .iter()
                .map(|cell| format!("{},{}", cell.x, cell.y))
                .collect::<Vec<_>>()
                .join(";");
            pending.0 = Some(StrokeDispatch::Cells(PendingStroke {
                op,
                layer,
                tile,
                cells,
            }));
        }
        TileBrush::FillRect => {
            let start = state.start.unwrap_or(cell);
            pending.0 = Some(StrokeDispatch::Fill(PendingFill {
                layer,
                tile,
                from: start,
                to: cell,
            }));
        }
        TileBrush::Flood => unreachable!("flood finishes on the press"),
    }
    reset_stroke(&mut state, &mut tool_status);
    Some(OperatorResult::Finished)
}

fn stroke_hint(brush: TileBrush) -> String {
    match brush {
        TileBrush::Paint => "Tilemap: drag paints cells · release stamps · Esc cancels",
        TileBrush::Erase => "Tilemap: drag erases cells · release stamps · Esc cancels",
        TileBrush::FillRect => "Tilemap: drag stretches a fill rect · release fills · Esc cancels",
        TileBrush::Flood => "Tilemap: click floods a region",
    }
    .to_owned()
}

/// The panel content entity (the one carrying the
/// [`Viewport2dPanelHost`]) of whichever 2D panel the cursor is on,
/// captured at stroke start.
fn fronted_host_entity(
    hosts: &Query<(Entity, &Viewport2dPanelHost)>,
    stages: &Query<(&ComputedNode, &UiGlobalTransform), With<Scene2dViewport>>,
) -> Option<Entity> {
    hosts
        .iter()
        .find(|(_, host)| stages.contains(host.stage))
        .map(|(entity, _)| entity)
}

fn reset_stroke(state: &mut TileStrokeState, tool_status: &mut ToolStatus) {
    state.initialized = false;
    state.layer = None;
    state.host = None;
    state.start = None;
    state.visited.clear();
    tool_status.0 = None;
}

fn cancel_stroke(mut state: ResMut<TileStrokeState>, mut tool_status: ResMut<ToolStatus>) {
    reset_stroke(&mut state, &mut tool_status);
}

// ---------------------------------------------------------------------------
// the trigger overlay (TM7)
// ---------------------------------------------------------------------------

/// Draw each `Trigger` layer's tiles with the translucent cyan ring while the
/// Tilemap tool is out: the author's only "this cell trips things" sign.
fn draw_trigger_overlays(
    mode: Res<ActiveTool>,
    mut gizmos: Gizmos,
    layers: Query<(&TilemapLayer, &TileCollisionMode, &GlobalTransform)>,
    tiles: Query<(&TileGridCell, &ChildOf)>,
) {
    if *mode != ActiveTool::Tilemap {
        return;
    }
    for (cell, parent) in &tiles {
        let Ok((form, layer_mode, global)) = layers.get(parent.parent()) else {
            continue;
        };
        if *layer_mode != TileCollisionMode::Trigger {
            continue;
        }
        let center = global.transform_point(form.cell_center(cell.cell).extend(form.order as f32));
        gizmos.rect_2d(
            Isometry2d::from_translation(center.truncate()),
            form.cell_size,
            TRIGGER_TINT,
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The sheet-display math the highlight and the sheet clicks share:
    /// tile 0 sits at the display's bottom-left, the top row at the top.
    #[test]
    fn the_display_lays_the_grid_out_y_up_over_a_y_down_node() {
        let layer = TilemapLayer {
            cell_size: Vec2::splat(32.0),
            columns: 4,
            rows: 2,
            ..default()
        };
        let cell_px = cell_display_px(layer.cell_size, layer.columns);
        assert_eq!(cell_px, 42.0, "168 px across 4 columns");

        let tile = 5; // column 1, row 1 — the sheet's top row
        let column = tile % layer.columns;
        let row = tile / layer.columns;
        assert_eq!(column as f32 * cell_px, 42.0, "second display column");
        let top_row = layer.rows.saturating_sub(1).min(row);
        let top = (layer.rows.saturating_sub(1) - top_row) as f32 * cell_px;
        assert_eq!(top, 0.0, "the top grid row sits at the display's top");

        let top = (layer.rows.saturating_sub(1)) as f32 * cell_px;
        assert_eq!(top, 42.0, "row 0 sits at the display's bottom");
    }

    #[test]
    fn one_cell_sheet_does_not_divide_by_zero() {
        let cell_px = cell_display_px(Vec2::splat(0.0), 0);
        assert!(
            cell_px.is_finite(),
            "degenerate sheets still render: {cell_px}"
        );
    }
}
