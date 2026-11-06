//! The Game panel: a dockable surface showing the focused instance's
//! streamed frame. A click on the frame engages input capture. The panel is
//! a pure monitor: no editor camera, no overlay, no compositing.

use std::time::{Duration, Instant};

use bevy::{prelude::*, ui_widgets::observe};
use jackdaw_api::pie::PlayState;
use jackdaw_api::prelude::*;
use jackdaw_feathers::button::{ButtonProps, button};
use jackdaw_feathers::tokens;

use jackdaw_panels::tree::{DockTree, NodeId, TabId};

use crate::live_frame::LiveFrameStream;
use crate::pie::PieWindowMode;

/// Dock window id, used for registration and presence checks.
pub const GAME_WINDOW_ID: &str = "jackdaw.game";

/// Marker on the panel content root.
#[derive(Component)]
pub struct GamePanel;

/// Marker on the letterbox container the frame image centers inside. Its
/// computed size is the stream request size and the cursor remap space.
#[derive(Component)]
pub struct GamePanelSurface;

/// Marker on the frame `ImageNode`.
#[derive(Component)]
pub struct GamePanelImage;

/// Marker on the idle label shown while no frame is streaming.
#[derive(Component)]
pub struct GamePanelIdleLabel;

/// Marker on the "no signal" chip shown while the focused instance's stream
/// has gone quiet.
#[derive(Component)]
pub struct GameNoSignalChip;

/// Marker on the "Playing, Shift+Esc to release" chip shown while input
/// capture is forwarding to the game.
#[derive(Component)]
pub struct GamePlayingChip;

/// Marker on the header button that toggles forwarding editor input to the
/// running game.
#[derive(Component)]
pub struct GamePlayInputButton;

/// How many recent game log lines the strip under the frame shows.
const LOG_ROWS: usize = 4;

/// How tall the strip grows when it expands into the full list (W4: the
/// buffer keeps [`PIE_GAME_LOG_CAP`] lines and four of them were all a
/// person could see).
const EXPANDED_MAX_HEIGHT: Val = Val::Percent(45.0);

/// Marker on the recent-game-log strip at the bottom of the panel.
#[derive(Component)]
pub struct GamePanelLogStrip;

/// Marker on the strip while it is expanded into the full scrollable list.
#[derive(Component)]
struct GameLogExpanded;

/// Marker on one log row, numbered from the top of the strip.
#[derive(Component, Clone, Copy, Debug, PartialEq, Eq)]
pub struct GameLogRow(pub usize);

/// Whether Play brought the Game panel forward, and the tab its dock showed
/// before, so the end of the session can put that tab back.
#[derive(Resource, Default, Debug)]
struct GamePanelSurfaced {
    shown: bool,
    previous: Option<(NodeId, TabId)>,
}

/// Letterboxed (contain-fit) display size and top-left offset for a stream
/// inside a panel.
pub(crate) fn contain_fit(panel: Vec2, stream: Vec2) -> (Vec2, Vec2) {
    let scale = (panel.x / stream.x).min(panel.y / stream.y);
    let size = stream * scale;
    (size, (panel - size) * 0.5)
}

/// Map a panel-local position to stream pixels through the contain fit,
/// clamped to the stream bounds. `None` on degenerate sizes.
pub fn panel_to_stream(local: Vec2, panel: Vec2, stream: Vec2) -> Option<Vec2> {
    if panel.x < 1.0 || panel.y < 1.0 || stream.x < 1.0 || stream.y < 1.0 {
        return None;
    }
    let scale = (panel.x / stream.x).min(panel.y / stream.y);
    let size = stream * scale;
    let offset = (panel - size) * 0.5;
    Some(((local - offset) / scale).clamp(Vec2::ZERO, stream))
}

/// The surface's top-left corner and logical size in window-logical pixels,
/// from its `ComputedNode` and `UiGlobalTransform`. `UiGlobalTransform`'s
/// translation is the node center in physical pixels, so it is scaled to
/// logical and shifted by half the logical size. Window-logical positions
/// map to surface-local with `window_pos - top_left`.
pub(crate) fn surface_remap(
    computed: &ComputedNode,
    transform: &bevy::ui::UiGlobalTransform,
) -> (Vec2, Vec2) {
    let scale = computed.inverse_scale_factor();
    let panel = computed.size() * scale;
    let top_left = transform.translation * scale - panel * 0.5;
    (top_left, panel)
}

/// Engage input capture on a click on the frame surface. Clicks while the
/// stream is not fresh do nothing, though the last frame stays up.
fn surface_clicked(world: &mut World, surface: Entity) {
    let fresh = world
        .get_resource::<LiveFrameStream>()
        .is_some_and(LiveFrameStream::is_fresh);
    let embedded = crate::pie::effective_window_mode_in(world) == PieWindowMode::Embedded;
    if !fresh || !embedded {
        return;
    }
    if !world
        .resource::<crate::live_input::LiveInputCapture>()
        .active
    {
        crate::live_input::engage_capture(world, surface);
    }
}

/// Build the panel content: a header with the signal and playing chips and
/// a Play-input button; below it a letterbox surface
/// hosting the frame image and an idle label.
pub fn game_panel_content() -> impl Bundle {
    (
        GamePanel,
        Node {
            flex_direction: FlexDirection::Column,
            width: percent(100),
            height: percent(100),
            border: UiRect::all(px(1.0)),
            ..Default::default()
        },
        BorderColor::all(Color::NONE),
        children![
            (
                Node {
                    flex_direction: FlexDirection::Row,
                    align_items: AlignItems::Center,
                    column_gap: px(tokens::SPACING_SM),
                    padding: UiRect::axes(px(tokens::SPACING_SM), px(tokens::SPACING_XS)),
                    flex_shrink: 0.0,
                    ..Default::default()
                },
                children![
                    game_no_signal_chip(),
                    game_playing_chip(),
                    game_play_input_button(),
                ],
            ),
            (
                GamePanelSurface,
                Node {
                    flex_grow: 1.0,
                    overflow: Overflow::clip(),
                    justify_content: JustifyContent::Center,
                    align_items: AlignItems::Center,
                    position_type: PositionType::Relative,
                    ..Default::default()
                },
                observe(|click: On<PointerClick>, mut commands: Commands| {
                    let surface = click.event_target();
                    commands.queue(move |world: &mut World| {
                        surface_clicked(world, surface);
                    });
                }),
                children![
                    (
                        GamePanelImage,
                        ImageNode::new(Handle::default()),
                        Node {
                            display: Display::None,
                            ..Default::default()
                        },
                    ),
                    (
                        GamePanelIdleLabel,
                        Text::new(IDLE_STOPPED),
                        TextFont {
                            font_size: tokens::TEXT_SIZE_SM,
                            ..Default::default()
                        },
                        TextColor(tokens::TEXT_DISABLED),
                    ),
                ],
            ),
            game_log_strip(),
        ],
    )
}

/// The recent-game-log strip: the newest [`LOG_ROWS`] lines the focused game
/// logged, each in its notice tier's color (warn speaks in the warning color,
/// an error in the error color). Hidden until the game has said something.
/// A click expands it into the full scrollable list the buffer holds (W4)
/// and a second click folds it back.
fn game_log_strip() -> impl Bundle {
    (
        GamePanelLogStrip,
        Node {
            flex_direction: FlexDirection::Column,
            row_gap: px(2.0),
            padding: UiRect::axes(px(tokens::SPACING_SM), px(2.0)),
            flex_shrink: 0.0,
            overflow: Overflow::clip(),
            display: Display::None,
            ..Default::default()
        },
        jackdaw_feathers::tooltip::Tooltip::title(
            "The focused game's log. Click to expand the full list; click again to fold.",
        ),
        observe(|_: On<PointerClick>, mut commands: Commands| {
            commands.queue(|world: &mut World| toggle_game_log_expansion(world));
        }),
        children![log_row(0), log_row(1), log_row(2), log_row(3),],
    )
}

/// Fold or unfold the strip. Expanded, the strip becomes the scrollable list
/// the whole [`PIE_GAME_LOG_CAP`] buffer rides; folded, the newest four lines
/// again. Pure consumer: the T12 channel's two ends are untouched.
fn toggle_game_log_expansion(world: &mut World) {
    let mut strip = world.query_filtered::<Entity, With<GamePanelLogStrip>>();
    let Some(strip) = strip.iter(world).next() else {
        return;
    };
    let mut entity = world.entity_mut(strip);
    if entity.contains::<GameLogExpanded>() {
        entity.remove::<GameLogExpanded>();
    } else {
        entity.insert(GameLogExpanded);
    }
}

/// One row of the log strip: a clipped text line in the secondary color
/// until a log entry claims it.
fn log_row(row: usize) -> impl Bundle {
    (
        GameLogRow(row),
        Node {
            overflow: Overflow::clip(),
            ..Default::default()
        },
        Text::new(""),
        TextFont {
            font_size: tokens::TEXT_SIZE_SM,
            ..Default::default()
        },
        TextColor(tokens::TEXT_SECONDARY),
    )
}

/// Build the two-segment Play/Select mode bar.
fn game_mode_bar() -> impl Bundle {
    (
        segmented::segmented_bar(),
        observe(
            |change: On<ValueChange<Entity>>,
             segments: Query<&GameModeSegment>,
             mut commands: Commands| {
                let Ok(&segment) = segments.get(change.value) else {
                    return;
                };
                commands.queue(move |world: &mut World| {
                    let next = match segment {
                        GameModeSegment::Play => GamePanelMode::Play,
                        GameModeSegment::Select => GamePanelMode::Select,
                    };
                    if next == GamePanelMode::Select
                        && world
                            .resource::<crate::live_input::LiveInputCapture>()
                            .active
                    {
                        world
                            .resource_mut::<crate::live_input::LiveInputCapture>()
                            .release_requested = true;
                        crate::live_input::apply_release_requests(world);
                        crate::live_input::flush_forwards(world);
                    }
                    *world.resource_mut::<GamePanelMode>() = next;
                });
            },
        ),
        children![
            game_mode_segment(
                GameModeSegment::Play,
                "Play",
                "Play: clicks and keys go to the game (Shift+Esc releases)",
            ),
            game_mode_segment(
                GameModeSegment::Select,
                "Select",
                "Select: click the frame to inspect the entity under the cursor",
            ),
        ],
    )
}

/// One segment inside the Play/Select mode bar.
fn game_mode_segment(
    segment: GameModeSegment,
    label: &'static str,
    tooltip: &'static str,
) -> impl Bundle {
    (
        segment,
        jackdaw_feathers::tooltip::Tooltip::title(tooltip),
        segmented::segment(label),
    )
}

/// Build the "no signal" chip, shown while the focused instance's stream has
/// gone quiet.
fn game_no_signal_chip() -> impl Bundle {
    (
        GameNoSignalChip,
        Node {
            align_items: AlignItems::Center,
            padding: UiRect::axes(px(tokens::SPACING_SM), px(2.0)),
            border_radius: BorderRadius::all(px(tokens::BORDER_RADIUS_SM)),
            display: Display::None,
            flex_shrink: 0.0,
            ..Default::default()
        },
        BackgroundColor(tokens::ELEVATED_BG),
        children![(
            Text::new("no signal"),
            TextFont {
                font_size: tokens::TEXT_SIZE_SM,
                ..Default::default()
            },
            TextColor(tokens::TEXT_DISABLED),
        )],
    )
}

/// Build the "Playing, Shift+Esc to release" chip, shown while input capture
/// forwards editor input to the running game.
fn game_playing_chip() -> impl Bundle {
    (
        GamePlayingChip,
        Node {
            align_items: AlignItems::Center,
            padding: UiRect::axes(px(tokens::SPACING_SM), px(2.0)),
            border_radius: BorderRadius::all(px(tokens::BORDER_RADIUS_SM)),
            display: Display::None,
            flex_shrink: 0.0,
            ..Default::default()
        },
        BackgroundColor(tokens::ELEVATED_BG),
        children![(
            Text::new("Playing, Shift+Esc to release"),
            TextFont {
                font_size: tokens::TEXT_SIZE_SM,
                ..Default::default()
            },
            TextColor(crate::default_style::CAPTURE_ACCENT),
        )],
    )
}

/// Build the button that toggles forwarding editor input to the running game.
fn game_play_input_button() -> impl Bundle {
    (
        GamePlayInputButton,
        jackdaw_feathers::tooltip::Tooltip::title(
            "Forward keyboard and mouse to the running game (Shift+Esc releases)",
        ),
        button(ButtonProps::new("Play Input")),
        observe(|_: On<PointerClick>, mut commands: Commands| {
            commands
                .operator(crate::live_input::PiePlayInputToggleOp::ID)
                .settings(CallOperatorSettings {
                    execution_context: ExecutionContext::Invoke,
                    creates_history_entry: false,
                })
                .call();
        }),
    )
}

/// Point the frame image at the current stream and show it once a frame has
/// arrived, else show the idle label. A slow game's last frame stays up.
fn sync_game_panel_image(
    stream: Res<LiveFrameStream>,
    mut images: Query<(&mut ImageNode, &mut Node), With<GamePanelImage>>,
    mut idle: Query<&mut Node, (With<GamePanelIdleLabel>, Without<GamePanelImage>)>,
) {
    let handle = stream.image.clone();
    let show_image = handle.is_some();
    let image_display = if show_image {
        Display::Flex
    } else {
        Display::None
    };
    let idle_display = if show_image {
        Display::None
    } else {
        Display::Flex
    };
    for (mut image_node, mut node) in &mut images {
        if let Some(ref handle) = handle
            && image_node.image != *handle
        {
            image_node.image = handle.clone();
        }
        if node.display != image_display {
            node.display = image_display;
        }
    }
    for mut node in &mut idle {
        if node.display != idle_display {
            node.display = idle_display;
        }
    }
}

const IDLE_STOPPED: &str = "Press Play to run the game here";
const IDLE_BUILDING: &str = "Building the game...";
const IDLE_WINDOWED: &str = "Running in its own window";
const IDLE_LOADING: &str = "Loading the game...";
const IDLE_STARTING: &str = "Starting the game...";
const IDLE_OWN_WINDOW: &str = "This game opened its own window. To show it here, pass DefaultPlugins \
     through jackdaw_runtime::maybe_windowless in its main.rs.";

/// How long a launched game may stay unconnected before the panel says why it
/// might never connect. It is stopped soon after, at the session's own timeout.
const SLOW_CONNECT: Duration = Duration::from_secs(10);

/// How long a game may take to its first frame before the panel remarks on it.
const SLOW_FIRST_FRAME: Duration = Duration::from_secs(60);

/// What the game is doing, for the label shown while the panel has no frame.
#[derive(Clone, Copy, Debug, PartialEq)]
enum GameWait {
    Stopped,
    Building,
    Windowed,
    OwnWindow,
    /// Launched and not yet connected, for this long. A game connects when
    /// `JackdawPlugin` builds, so one without it never does.
    Connecting(Duration),
    /// Connected and not yet showing a frame, for this long.
    Loading(Duration),
}

fn idle_message(wait: GameWait) -> String {
    match wait {
        GameWait::Stopped => IDLE_STOPPED.to_string(),
        GameWait::Building => IDLE_BUILDING.to_string(),
        GameWait::Windowed => IDLE_WINDOWED.to_string(),
        GameWait::OwnWindow => IDLE_OWN_WINDOW.to_string(),
        GameWait::Connecting(waited) if waited >= SLOW_CONNECT => {
            "The game has not connected to the editor yet. It connects when its app adds \
             JackdawPlugin, and is stopped if it does not."
                .to_string()
        }
        GameWait::Connecting(_) => IDLE_STARTING.to_string(),
        GameWait::Loading(waited) if waited >= SLOW_FIRST_FRAME => format!(
            "Still loading the game ({} s). A large scene takes a while, and a game with its \
             own window on an older runtime will not show here.",
            waited.as_secs()
        ),
        GameWait::Loading(_) => IDLE_LOADING.to_string(),
    }
}

/// Say where the game is while the panel has no frame to show, and report a
/// first frame that took unusually long.
fn update_game_panel_idle_label(
    play_state: Option<Res<State<PlayState>>>,
    launched: crate::pie::LaunchedWindowMode,
    stream: Res<LiveFrameStream>,
    request: Option<Res<crate::live_frame_view::StreamRequest>>,
    session: Option<NonSend<crate::pie::PieSession>>,
    mut loading_since: Local<Option<Instant>>,
    mut labels: Query<&mut Text, With<GamePanelIdleLabel>>,
    mut commands: Commands,
) {
    let running = play_state.is_some_and(|state| *state.get() != PlayState::Stopped);
    let windowed = launched.get() == PieWindowMode::Windowed;
    if !running || windowed || stream.game_has_own_window {
        *loading_since = None;
    } else if stream.has_frame() {
        if let Some(waited) = loading_since.take().map(|since| since.elapsed())
            && waited >= SLOW_FIRST_FRAME
        {
            commands.queue(move |world: &mut World| {
                crate::status_bar::notify_info(
                    world,
                    format!(
                        "The game took {} s to show its first frame",
                        waited.as_secs()
                    ),
                );
            });
        }
    } else if request.is_some_and(|request| request.is_requested()) {
        loading_since.get_or_insert_with(Instant::now);
    }

    let wait = if running {
        if windowed {
            GameWait::Windowed
        } else if stream.game_has_own_window {
            GameWait::OwnWindow
        } else {
            GameWait::Loading(loading_since.map_or(Duration::ZERO, |since| since.elapsed()))
        }
    } else if let Some(session) = session {
        if session.is_launching() {
            GameWait::Building
        } else if let Some(waited) = session.connecting_for() {
            GameWait::Connecting(waited)
        } else {
            GameWait::Stopped
        }
    } else {
        GameWait::Stopped
    };
    let message = idle_message(wait);
    for mut text in &mut labels {
        if text.0 != message {
            text.0.clone_from(&message);
        }
    }
}

/// Bring the Game panel to the front when an embedded Play session starts,
/// and put back the tab its dock showed before once play stops, if the Game
/// panel is still the one in front. The game only streams frames while the
/// panel is laid out, so a hidden panel would leave the game unseen.
fn surface_game_panel_on_play(world: &mut World) {
    let running = world
        .get_resource::<State<PlayState>>()
        .is_some_and(|state| *state.get() != PlayState::Stopped);
    let embedded = crate::pie::effective_window_mode_in(world) == PieWindowMode::Embedded;
    let Some(shown) = world
        .get_resource::<GamePanelSurfaced>()
        .map(|surfaced| surfaced.shown)
    else {
        return;
    };
    if !world.contains_resource::<DockTree>() {
        return;
    }
    if running && embedded && !shown {
        let previous = front_tab_beside_game(world.resource::<DockTree>());
        crate::open_window_in_default_area_if_absent(world, GAME_WINDOW_ID);
        let mut surfaced = world.resource_mut::<GamePanelSurfaced>();
        surfaced.shown = true;
        surfaced.previous = previous;
    } else if !running && shown {
        let previous = std::mem::take(&mut *world.resource_mut::<GamePanelSurfaced>()).previous;
        let mut tree = world.resource_mut::<DockTree>();
        if let Some((leaf, tab)) = previous
            && front_window(&tree, leaf).as_deref() == Some(GAME_WINDOW_ID)
        {
            tree.set_active(leaf, tab);
        }
    }
}

/// The dock leaf holding the Game panel and the tab in front of it, when
/// that tab is another window's.
fn front_tab_beside_game(tree: &DockTree) -> Option<(NodeId, TabId)> {
    let leaf_id = tree.find_leaf_with_window(GAME_WINDOW_ID)?;
    let leaf = tree.get(leaf_id)?.as_leaf()?;
    let active = leaf.active?;
    leaf.tabs()
        .any(|(window, tab)| tab == active && window != GAME_WINDOW_ID)
        .then_some((leaf_id, active))
}

/// The window whose tab is in front of `leaf`.
fn front_window(tree: &DockTree, leaf: NodeId) -> Option<String> {
    let leaf = tree.get(leaf)?.as_leaf()?;
    let active = leaf.active?;
    leaf.tabs()
        .find_map(|(window, tab)| (tab == active).then(|| window.to_string()))
}

/// Letterbox the frame image inside the surface.
fn layout_game_panel_image(
    stream: Res<LiveFrameStream>,
    surfaces: Query<&ComputedNode, With<GamePanelSurface>>,
    mut images: Query<&mut Node, With<GamePanelImage>>,
) {
    let stream_size = stream.size.as_vec2();
    if stream_size.x < 1.0 || stream_size.y < 1.0 {
        return;
    }
    let Ok(computed) = surfaces.single() else {
        return;
    };
    let panel = computed.size() * computed.inverse_scale_factor();
    if panel.x < 1.0 || panel.y < 1.0 {
        return;
    }
    let (size, _offset) = contain_fit(panel, stream_size);
    let width = Val::Px(size.x);
    let height = Val::Px(size.y);
    for mut node in &mut images {
        if node.width != width {
            node.width = width;
        }
        if node.height != height {
            node.height = height;
        }
    }
}

/// A stream that showed frames and has stopped. A game still on its way to its
/// first frame is loading, which the idle label says.
fn went_quiet(stream: &LiveFrameStream) -> bool {
    stream.has_frame() && !stream.is_fresh()
}

/// Drive the no-signal chip, the playing chip, and the capture accent border.
fn update_game_panel_chips(
    capture: Res<crate::live_input::LiveInputCapture>,
    stream: Res<LiveFrameStream>,
    instances: Res<crate::pie_mirror::PieInstances>,
    mut no_signal: Query<&mut Node, With<GameNoSignalChip>>,
    mut playing: Query<&mut Node, (With<GamePlayingChip>, Without<GameNoSignalChip>)>,
    mut roots: Query<&mut BorderColor, With<GamePanel>>,
) {
    let no_signal_display = if instances.focused.is_some() && went_quiet(&stream) {
        Display::Flex
    } else {
        Display::None
    };
    for mut node in &mut no_signal {
        if node.display != no_signal_display {
            node.display = no_signal_display;
        }
    }
    let playing_display = if capture.active {
        Display::Flex
    } else {
        Display::None
    };
    for mut node in &mut playing {
        if node.display != playing_display {
            node.display = playing_display;
        }
    }
    let border = if capture.active {
        BorderColor::all(crate::default_style::CAPTURE_ACCENT)
    } else {
        BorderColor::all(Color::NONE)
    };
    for mut root in &mut roots {
        if *root != border {
            *root = border;
        }
    }
}

/// Write the log lines into the strip, folded or expanded. Folded, row `i`
/// shows entry `len - LOG_ROWS + i`, in the entry's notice-tier color, and
/// the strip stays the newest-four face. Expanded (the [`GameLogExpanded`]
/// marker the strip's click toggles), the strip grows a scroll cap and one
/// row per buffered line — the whole [`PIE_GAME_LOG_CAP`] window, oldest
/// first, pinned to the newest. The strip stays hidden until the game has
/// said something.
fn sync_game_panel_log(
    log: Option<Res<crate::pie_game_log::PieGameLog>>,
    mut strips: Query<(Entity, &mut Node, Has<GameLogExpanded>), With<GamePanelLogStrip>>,
    row_entities: Query<Entity, (With<GameLogRow>, Without<GamePanelLogStrip>)>,
    mut rows: Query<(&GameLogRow, &mut Text, &mut TextColor), Without<GamePanelLogStrip>>,
    mut commands: Commands,
) {
    let Some(log) = log else {
        return;
    };
    let entries: Vec<_> = log.entries().collect();
    let show = !entries.is_empty();
    let display = if show { Display::Flex } else { Display::None };
    let Ok((strip, mut node, expanded)) = strips.single_mut() else {
        return;
    };
    if node.display != display {
        node.display = display;
    }
    let grown = expanded && show;
    let desired_max = if grown {
        EXPANDED_MAX_HEIGHT
    } else {
        Val::Auto
    };
    if node.max_height != desired_max {
        node.max_height = desired_max;
    }
    let desired_rows = if grown { entries.len() } else { LOG_ROWS };
    if row_entities.iter().count() != desired_rows {
        for entity in &row_entities {
            commands.entity(entity).despawn();
        }
        for index in 0..desired_rows {
            commands.spawn((log_row(index), ChildOf(strip)));
        }
        if grown {
            // The list just rebuilt from the buffer's start; pin it to the
            // newest line the way a terminal does.
            commands
                .entity(strip)
                .insert(ScrollPosition(Vec2::new(0.0, f32::MAX)));
        } else {
            commands.entity(strip).remove::<ScrollPosition>();
        }
        // The rows the commands spawn fill in on the next pass.
        return;
    }
    if grown {
        for (row, mut text, mut color) in &mut rows {
            let entry = entries.get(row.0);
            match entry {
                Some(entry) => {
                    if text.0 != entry.message {
                        text.0 = entry.message.clone();
                    }
                    let tinted = entry.color();
                    if color.0 != tinted {
                        color.0 = tinted;
                    }
                }
                None => {
                    if !text.0.is_empty() {
                        text.0 = String::new();
                    }
                }
            }
        }
        return;
    }
    let first = entries.len().saturating_sub(LOG_ROWS);
    // Fewer entries than rows: the lines sit at the bottom of the strip
    // (terminal order), so the leading rows stay blank.
    let leading_blanks = LOG_ROWS.saturating_sub(entries.len());
    for (row, mut text, mut color) in &mut rows {
        let entry = if row.0 < leading_blanks {
            None
        } else {
            entries.get(first + row.0 - leading_blanks)
        };
        match entry {
            Some(entry) => {
                if text.0 != entry.message {
                    text.0 = entry.message.clone();
                }
                let tinted = entry.color();
                if color.0 != tinted {
                    color.0 = tinted;
                }
            }
            None => {
                if !text.0.is_empty() {
                    text.0 = String::new();
                }
            }
        }
    }
}

/// While Select mode is active, forward the cursor position over the surface
/// so the game's picking backend tracks hover before a pick click.
fn forward_select_hover(
    mode: Res<GamePanelMode>,
    stream: Option<Res<LiveFrameStream>>,
    mut cursor: MessageReader<bevy::window::CursorMoved>,
    surfaces: Query<(&ComputedNode, &bevy::ui::UiGlobalTransform), With<GamePanelSurface>>,
    mut pending: ResMut<crate::live_input::PendingForwards>,
) {
    if *mode != GamePanelMode::Select {
        cursor.clear();
        return;
    }
    let Some(stream) = stream.filter(|s| s.is_fresh()) else {
        cursor.clear();
        return;
    };
    let Ok((computed, transform)) = surfaces.single() else {
        cursor.clear();
        return;
    };
    let (top_left, panel) = surface_remap(computed, transform);
    for moved in cursor.read() {
        let local = moved.position - top_left;
        if local.x < 0.0 || local.y < 0.0 || local.x > panel.x || local.y > panel.y {
            continue;
        }
        if let Some(position) = panel_to_stream(local, panel, stream.size.as_vec2()) {
            pending
                .0
                .push(jackdaw_pie_protocol::PieInputEvent::CursorMoved { position });
        }
    }
}

pub struct GamePanelPlugin;

impl Plugin for GamePanelPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<GamePanelMode>()
            .init_resource::<GamePanelSurfaced>()
            .init_resource::<crate::pie_game_log::PieGameLog>()
            .add_systems(Update, surface_game_panel_on_play)
            .add_systems(
                Update,
                (
                    sync_game_panel_image,
                    update_game_panel_idle_label,
                    layout_game_panel_image,
                    update_game_panel_chips,
                    sync_game_panel_log,
                    forward_select_hover,
                ),
            );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn contain_fit_letterboxes_and_centers() {
        let (size, offset) = contain_fit(Vec2::new(800.0, 600.0), Vec2::new(1600.0, 1200.0));
        assert_eq!(size, Vec2::new(800.0, 600.0));
        assert_eq!(offset, Vec2::ZERO);
        let (size, offset) = contain_fit(Vec2::new(600.0, 600.0), Vec2::new(1200.0, 600.0));
        assert_eq!(size, Vec2::new(600.0, 300.0));
        assert_eq!(offset, Vec2::new(0.0, 150.0));
        let (size, offset) = contain_fit(Vec2::new(400.0, 800.0), Vec2::new(800.0, 800.0));
        assert_eq!(size, Vec2::new(400.0, 400.0));
        assert_eq!(offset, Vec2::new(0.0, 200.0));
    }

    #[test]
    fn surface_click_without_fresh_stream_is_a_noop() {
        let mut world = World::new();
        world.init_resource::<crate::live_input::LiveInputCapture>();
        world.init_resource::<crate::live_input::PendingForwards>();
        let surface = world.spawn_empty().id();
        // No LiveFrameStream resource: not fresh, so the click does nothing.
        surface_clicked(&mut world, surface);
        assert!(
            !world
                .resource::<crate::live_input::LiveInputCapture>()
                .active
        );
    }

    /// Only a game that said it has its own window is told to change main.rs.
    #[test]
    fn a_busy_game_reads_as_loading_and_is_not_blamed() {
        let loading = idle_message(GameWait::Loading(Duration::from_secs(5)));
        assert_eq!(loading, IDLE_LOADING);
        assert!(!loading.contains("maybe_windowless"));

        let long = idle_message(GameWait::Loading(Duration::from_secs(200)));
        assert!(long.contains("200 s"), "{long}");
        assert!(!long.contains("maybe_windowless"));

        assert!(idle_message(GameWait::OwnWindow).contains("maybe_windowless"));
        assert_eq!(
            idle_message(GameWait::Connecting(Duration::from_secs(1))),
            IDLE_STARTING
        );
        let unconnected = idle_message(GameWait::Connecting(SLOW_CONNECT));
        assert!(unconnected.contains("JackdawPlugin"), "{unconnected}");
        assert!(!unconnected.contains("oading"), "{unconnected}");
        assert_eq!(idle_message(GameWait::Stopped), IDLE_STOPPED);
        assert_eq!(idle_message(GameWait::Building), IDLE_BUILDING);
        assert_eq!(idle_message(GameWait::Windowed), IDLE_WINDOWED);
    }

    #[test]
    fn only_a_stream_that_showed_frames_can_go_quiet() {
        let mut stream = LiveFrameStream::default();
        assert!(!went_quiet(&stream), "still loading");

        let mut images = Assets::<Image>::default();
        stream.image = Some(images.add(Image::default()));
        assert!(went_quiet(&stream));

        stream.received_at = Some(Instant::now());
        assert!(!went_quiet(&stream));
    }

    #[test]
    fn panel_to_stream_inverts_the_fit() {
        let panel = Vec2::new(600.0, 600.0);
        let stream = Vec2::new(1200.0, 600.0);
        assert_eq!(
            panel_to_stream(Vec2::new(300.0, 300.0), panel, stream),
            Some(Vec2::new(600.0, 300.0))
        );
        assert_eq!(
            panel_to_stream(Vec2::new(300.0, 10.0), panel, stream),
            Some(Vec2::new(600.0, 0.0))
        );
        assert_eq!(panel_to_stream(Vec2::ZERO, Vec2::ZERO, stream), None);
    }

    /// The strip's click toggles the expansion marker on the strip itself,
    /// folding whatever it was (W4's pure consumer face).
    #[test]
    fn the_strip_click_toggles_the_expansion() {
        let mut world = World::new();
        let strip = world.spawn((GamePanelLogStrip, Node::default())).id();
        toggle_game_log_expansion(&mut world);
        assert!(
            world.get::<GameLogExpanded>(strip).is_some(),
            "one click expands the strip"
        );
        toggle_game_log_expansion(&mut world);
        assert!(
            world.get::<GameLogExpanded>(strip).is_none(),
            "a second click folds it"
        );
    }

    /// Expanded, the strip renders the whole buffer — a hundred lines, oldest
    /// first, in their tier colors — not the newest four (W4: ninety-six of
    /// the buffer's hundred lines were unreachable before).
    #[test]
    fn the_expanded_strip_reaches_every_buffered_line() {
        use crate::pie_game_log::{PIE_GAME_LOG_CAP, PieGameLog};

        let mut world = World::new();
        world.init_resource::<PieGameLog>();
        let strip = world
            .spawn((GamePanelLogStrip, Node::default()))
            .insert(GameLogExpanded)
            .id();
        {
            let mut log = world.resource_mut::<PieGameLog>();
            for n in 0..PIE_GAME_LOG_CAP + 20 {
                log.push("info", format!("line {n}"));
            }
        }
        world.run_system_cached(sync_game_panel_log).unwrap();
        world.run_system_cached(sync_game_panel_log).unwrap();
        let texts: Vec<(usize, String)> = world
            .query::<(&GameLogRow, &Text)>()
            .iter(&world)
            .map(|(row, text)| (row.0, text.0.clone()))
            .collect();
        assert_eq!(
            texts.len(),
            PIE_GAME_LOG_CAP,
            "one row per buffered line, not four: {}",
            texts.len()
        );
        let mut sorted = texts.clone();
        sorted.sort_by_key(|(index, _)| *index);
        assert_eq!(sorted[0].1, "line 20", "the buffer's oldest survivor leads");
        assert_eq!(
            sorted[PIE_GAME_LOG_CAP - 1].1,
            format!("line {}", PIE_GAME_LOG_CAP + 19),
            "the newest line is last"
        );
        // And the strip grew its scroll cap.
        let node = world.get::<Node>(strip).unwrap();
        assert_eq!(node.max_height, EXPANDED_MAX_HEIGHT);
        assert!(
            world.get::<ScrollPosition>(strip).is_some(),
            "the expanded strip carries a scroll position"
        );
    }

    #[test]
    fn the_log_strip_carries_the_newest_lines_in_tier_colors() {
        use crate::pie_game_log::{PIE_GAME_LOG_CAP, PieGameLog};

        let mut world = World::new();
        world.init_resource::<PieGameLog>();
        world.spawn((GamePanelLogStrip, Node::default()));
        for row in 0..LOG_ROWS {
            world.spawn((
                GameLogRow(row),
                Text::new(""),
                TextColor(tokens::TEXT_SECONDARY),
            ));
        }
        // Two lines: they fill the bottom rows, older rows stay empty, and the
        // strip is visible.
        world
            .resource_mut::<PieGameLog>()
            .push("warn", "binding 0 failed");
        world.resource_mut::<PieGameLog>().push("info", "started");
        world.run_system_cached(sync_game_panel_log).unwrap();
        let strip = world
            .query_filtered::<&Node, With<GamePanelLogStrip>>()
            .single(&world)
            .unwrap();
        assert_eq!(strip.display, Display::Flex, "a line makes the strip show");
        let rows = |world: &mut World| -> Vec<(usize, String, Color)> {
            let mut rows: Vec<_> = world
                .query::<(&GameLogRow, &Text, &TextColor)>()
                .iter(world)
                .map(|(row, text, color)| (row.0, text.0.clone(), color.0))
                .collect();
            rows.sort_by_key(|(row, _, _)| *row);
            rows
        };
        let texts: Vec<String> = rows(&mut world)
            .into_iter()
            .map(|(_, text, _)| text)
            .collect();
        assert_eq!(
            texts,
            vec![
                String::new(),
                String::new(),
                "binding 0 failed".to_owned(),
                "started".to_owned()
            ]
        );
        // Push past the cap: only the newest LOG_ROWS remain on the strip.
        for n in 0..PIE_GAME_LOG_CAP {
            world
                .resource_mut::<PieGameLog>()
                .push("error", format!("e{n}"));
        }
        world.run_system_cached(sync_game_panel_log).unwrap();
        let entries: Vec<_> = world.resource::<PieGameLog>().entries().cloned().collect();
        assert_eq!(entries.len(), PIE_GAME_LOG_CAP);
        let texts: Vec<String> = rows(&mut world)
            .into_iter()
            .map(|(_, text, _)| text)
            .collect();
        let want: Vec<_> = entries[entries.len() - LOG_ROWS..]
            .iter()
            .map(|e| e.message.clone())
            .collect();
        assert_eq!(texts, want, "the newest lines are what the strip shows");
        for (_, _, color) in rows(&mut world) {
            assert_eq!(color, jackdaw_feathers::tokens::TEXT_ERROR);
        }
        // A warn speaks in the warning color, not the error or secondary one.
        world.resource_mut::<PieGameLog>().push("warn", "last word");
        world.run_system_cached(sync_game_panel_log).unwrap();
        let last = rows(&mut world);
        assert_eq!(
            last[LOG_ROWS - 1],
            (
                LOG_ROWS - 1,
                "last word".to_owned(),
                jackdaw_feathers::tokens::TEXT_WARNING
            )
        );
    }
}
