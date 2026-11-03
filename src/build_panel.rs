//! Build Window: a bottom-dock panel that forwards project-build status
//! and logs, so the background pre-build and any rebuild are visible with
//! progress instead of only a footer line. It focuses itself on the first
//! build after opening a project and whenever a build fails, but stays out
//! of the way on routine successful rebuilds.

use bevy::prelude::*;
use jackdaw_api::{
    DefaultArea,
    prelude::{ExtensionContext, ExtensionKind, JackdawExtension, WindowDescriptor},
};
use jackdaw_feathers::icons::{EditorFont, Icon};
use jackdaw_feathers::tokens;
use jackdaw_panels::tree::DockTree;

use crate::build_diagnostics::{self, BuildDiagnostics, DiagnosticRow};
use crate::build_status::{BuildState, BuildStatus};
use crate::scrolling_log::{self, ScrollingLog, ScrollingLogProps};

/// Dock-window id for the Build panel.
pub const BUILD_WINDOW_ID: &str = "jackdaw.build";

/// Seconds for one back-and-forth of the indeterminate progress segment.
const BAR_CYCLE: f32 = 1.4;
/// Width of the sliding segment, in percent.
const BAR_SEGMENT: f32 = 22.0;
/// How many error rows the strip renders before "... and N more". The whole
/// log is right below; the strip is the way in, not the archive.
const MAX_DIAGNOSTIC_ROWS: usize = 6;

pub struct BuildPanelPlugin;

impl Plugin for BuildPanelPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<BuildPanelFocus>()
            .add_observer(on_diagnostic_open_click)
            .add_systems(OnEnter(crate::AppState::Editor), reset_build_focus)
            .add_systems(
                Update,
                (
                    sync_build_panel,
                    sync_build_diagnostic_rows,
                    animate_build_bar,
                    auto_focus_build_panel,
                )
                    .run_if(in_state(crate::AppState::Editor)),
            );
    }
}

/// Tracks whether the panel has already surfaced itself for the current
/// project's first build, so it does that once per open, not every build.
#[derive(Resource, Default)]
struct BuildPanelFocus {
    first_build_shown: bool,
}

#[derive(Component)]
struct BuildPanelStatusText;
#[derive(Component)]
struct BuildPanelLog;
#[derive(Component)]
struct BuildPanelBarTrack;
#[derive(Component)]
struct BuildPanelBarFill;
/// The error-row strip between the header and the log: the structured face
/// of the failed build, one clickable row per `--> path:line:col` position.
#[derive(Component)]
struct BuildPanelRows;
/// The font the strip's rows render in, stashed at build time so the sync
/// system can respawn rows without hunting for the editor font.
#[derive(Component)]
struct BuildPanelRowsFont(Handle<Font>);
/// One rendered line of the strip (summary, position row, overflow note).
#[derive(Component)]
struct BuildPanelRow;
/// The "Open" button of one diagnostic row.
#[derive(Component)]
struct DiagnosticOpenButton(DiagnosticRow);

/// The panel content: a status header with a thin progress bar, and a
/// scrolling log filling the rest.
fn build_build_panel(world: &mut World, parent: Entity, font: Handle<Font>) {
    let root = world
        .spawn((
            Node {
                flex_direction: FlexDirection::Column,
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                min_height: Val::Px(0.0),
                ..default()
            },
            ChildOf(parent),
        ))
        .id();

    let header = world
        .spawn((
            Node {
                flex_direction: FlexDirection::Column,
                row_gap: Val::Px(5.0),
                padding: UiRect::all(Val::Px(8.0)),
                width: Val::Percent(100.0),
                ..default()
            },
            ChildOf(root),
        ))
        .id();
    world.spawn((
        BuildPanelStatusText,
        Text::new("No build running"),
        TextFont {
            font: font.clone().into(),
            font_size: tokens::TEXT_SIZE_SM,
            ..default()
        },
        TextColor(tokens::TEXT_SECONDARY),
        ChildOf(header),
    ));
    let track = world
        .spawn((
            BuildPanelBarTrack,
            Node {
                width: Val::Percent(100.0),
                height: Val::Px(3.0),
                overflow: Overflow::clip(),
                ..default()
            },
            BackgroundColor(tokens::PANEL_HEADER_BG),
            Visibility::Hidden,
            ChildOf(header),
        ))
        .id();
    world.spawn((
        BuildPanelBarFill,
        Node {
            position_type: PositionType::Absolute,
            left: Val::Percent(0.0),
            width: Val::Percent(0.0),
            height: Val::Percent(100.0),
            ..default()
        },
        BackgroundColor(tokens::TEXT_ACCENT),
        ChildOf(track),
    ));

    world.spawn((
        BuildPanelRows,
        BuildPanelRowsFont(font.clone()),
        Node {
            flex_direction: FlexDirection::Column,
            row_gap: Val::Px(2.0),
            padding: UiRect::horizontal(Val::Px(8.0)),
            width: Val::Percent(100.0),
            display: Display::None,
            ..default()
        },
    ));

    let log = scrolling_log::spawn(
        world,
        root,
        ScrollingLogProps {
            max_height: Val::Auto,
            margin: UiRect::all(Val::Px(0.0)),
            font,
            font_size: tokens::TEXT_SIZE_XS,
            text_color: tokens::TEXT_SECONDARY,
            background: Color::NONE,
            auto_hide_when_empty: false,
        },
    );
    world.entity_mut(log).insert(BuildPanelLog);
    // Let the log take the remaining height and scroll within it.
    if let Some(mut node) = world.entity_mut(log).get_mut::<Node>() {
        node.flex_grow = 1.0;
        node.min_height = Val::Px(0.0);
    }
}

/// Mirror the build state into the panel: header text/color, progress-bar
/// visibility, and the scrolling log. The build log lives in the
/// `BuildProgress` sink only while a build runs; once it finishes the last
/// captured output stays on screen.
fn sync_build_panel(
    build_status: Res<BuildStatus>,
    mut status: Query<(&mut Text, &mut TextColor), With<BuildPanelStatusText>>,
    mut logs: Query<&mut ScrollingLog, With<BuildPanelLog>>,
    mut track: Query<&mut Visibility, With<BuildPanelBarTrack>>,
) {
    let (label, color, log_content, building) = match &build_status.state {
        BuildState::Building { progress, .. } => {
            let (current, done, log) = progress
                .lock()
                .map(|g| {
                    (
                        g.current_crate.clone(),
                        g.artifacts_done,
                        g.full_log.clone(),
                    )
                })
                .unwrap_or((None, 0, String::new()));
            let label = match current {
                Some(name) => format!("Compiling {name} ({done})"),
                None => "Building project...".to_string(),
            };
            (label, tokens::TEXT_SECONDARY, Some(log), true)
        }
        BuildState::Ready { components, .. } => (
            match &build_status.outcome {
                Some(outcome) => format!("Build succeeded - {outcome}"),
                None => format!("Build succeeded - {components} components"),
            },
            tokens::TEXT_SUCCESS,
            None,
            false,
        ),
        BuildState::Failed { .. } => (
            match &build_status.outcome {
                Some(outcome) => format!("Build failed - {outcome}"),
                None => "Build failed - see the log below".to_string(),
            },
            tokens::TEXT_ERROR,
            // The build can end between two frames, so the panel may never
            // have seen its last lines; show the whole output it kept.
            build_status
                .failed_log
                .as_ref()
                .map(|log| match &build_status.outcome {
                    Some(outcome) => format!("{log}\n{outcome}"),
                    None => log.clone(),
                }),
            false,
        ),
        BuildState::Blocked { reason } => (
            "Cannot build this project".to_string(),
            tokens::TEXT_ERROR,
            Some(reason.clone()),
            false,
        ),
        BuildState::Idle => (
            build_status
                .outcome
                .clone()
                .unwrap_or_else(|| "No build running".to_string()),
            tokens::TEXT_SECONDARY,
            None,
            false,
        ),
    };

    if let Ok((mut text, mut text_color)) = status.single_mut() {
        if text.0 != label {
            text.0 = label;
        }
        if text_color.0 != color {
            text_color.0 = color;
        }
    }
    if let Some(content) = log_content
        && let Ok(mut log) = logs.single_mut()
        && log.content != content
    {
        log.content = content;
    }
    // The compiler output ends before the library is loaded; finish the log
    // with what came of it.
    if !building
        && let Some(outcome) = &build_status.outcome
        && let Ok(mut log) = logs.single_mut()
        && !log.content.ends_with(outcome.as_str())
    {
        if !log.content.is_empty() && !log.content.ends_with('\n') {
            log.content.push('\n');
        }
        log.content.push_str(outcome);
    }
    if let Ok(mut visibility) = track.single_mut() {
        let desired = if building {
            Visibility::Visible
        } else {
            Visibility::Hidden
        };
        if *visibility != desired {
            *visibility = desired;
        }
    }
}

/// Mirror the structured face of the failed build into the strip between the
/// header and the log: an "N errors" summary with the first error pinned,
/// then one row per actionable `--> path:line:col` position, each with an
/// Open button (decision 3(c): the best external editor on `PATH`, falling
/// back to a folder reveal). The strip hides while there is nothing to act
/// on — the log below stays the whole story.
fn sync_build_diagnostic_rows(
    diagnostics: Res<BuildDiagnostics>,
    fonts: Query<&BuildPanelRowsFont>,
    strips: Query<Entity, With<BuildPanelRows>>,
    mut strip_nodes: Query<&mut Node, With<BuildPanelRows>>,
    rows: Query<Entity, With<BuildPanelRow>>,
    mut commands: Commands,
) {
    if !diagnostics.is_changed() {
        return;
    }
    for entity in &rows {
        commands.entity(entity).despawn();
    }
    let Some(strip) = strips.iter().next() else {
        return;
    };
    let Ok(mut node) = strip_nodes.get_mut(strip) else {
        return;
    };
    let empty = diagnostics.rows.is_empty() && diagnostics.errors == 0;
    let desired = if empty { Display::None } else { Display::Flex };
    if node.display != desired {
        node.display = desired;
    }
    if empty {
        return;
    }
    let Some(font) = fonts.iter().next().map(|f| f.0.clone()) else {
        return;
    };
    let summary = match diagnostics.first_error() {
        Some(first) => format!(
            "{} errors · first: {}",
            diagnostics.errors,
            first.position()
        ),
        None => format!(
            "{} errors · the log names no source position (a linker or cargo failure)",
            diagnostics.errors,
        ),
    };
    spawn_summary_row(&mut commands, strip, &font, &summary);
    let shown = diagnostics.rows.len().min(MAX_DIAGNOSTIC_ROWS);
    for row in &diagnostics.rows[..shown] {
        spawn_diagnostic_row(&mut commands, strip, &font, row);
    }
    let hidden = diagnostics.rows.len() - shown;
    if hidden > 0 {
        spawn_text_row(
            &mut commands,
            strip,
            &font,
            format!("... and {hidden} more (see the log below)"),
            tokens::TEXT_SECONDARY,
        );
    }
}

/// The strip's summary line: the count and where the first error sits.
fn spawn_summary_row(commands: &mut Commands, strip: Entity, font: &Handle<Font>, text: &str) {
    spawn_text_row(commands, strip, font, text.to_string(), tokens::TEXT_ERROR);
}

/// One plain line in the strip, colored.
fn spawn_text_row(
    commands: &mut Commands,
    strip: Entity,
    font: &Handle<Font>,
    text: String,
    color: Color,
) {
    commands.spawn((
        BuildPanelRow,
        Node {
            width: Val::Percent(100.0),
            ..default()
        },
        ChildOf(strip),
        Text::new(text),
        TextFont {
            font: font.clone().into(),
            font_size: tokens::TEXT_SIZE_XS,
            ..default()
        },
        TextColor(color),
    ));
}

/// One actionable position: the arrow the log spells, in its severity's
/// color, with an Open button beside it.
fn spawn_diagnostic_row(
    commands: &mut Commands,
    strip: Entity,
    font: &Handle<Font>,
    row: &DiagnosticRow,
) {
    commands.spawn((
        BuildPanelRow,
        Node {
            flex_direction: FlexDirection::Row,
            align_items: AlignItems::Center,
            column_gap: Val::Px(8.0),
            width: Val::Percent(100.0),
            ..default()
        },
        ChildOf(strip),
        children![
            (
                Text::new(format!("--> {}", row.position())),
                TextFont {
                    font: font.clone().into(),
                    font_size: tokens::TEXT_SIZE_XS,
                    ..default()
                },
                TextColor(build_diagnostics::severity_color(row.severity)),
                Node {
                    flex_grow: 1.0,
                    min_width: Val::Px(0.0),
                    overflow: Overflow::clip(),
                    ..default()
                },
            ),
            (
                DiagnosticOpenButton(row.clone()),
                Node {
                    padding: UiRect::axes(Val::Px(10.0), Val::Px(4.0)),
                    border_radius: BorderRadius::all(Val::Px(tokens::BORDER_RADIUS_MD)),
                    ..default()
                },
                BackgroundColor(tokens::TOOLBAR_BG),
                children![(
                    Text::new("Open"),
                    TextFont {
                        font: font.clone().into(),
                        font_size: tokens::TEXT_SIZE_XS,
                        ..default()
                    },
                    TextColor(tokens::TEXT_PRIMARY),
                    Pickable::IGNORE,
                )],
            ),
        ],
    ));
}

/// The Open button of one diagnostic row, taken at its word.
fn on_diagnostic_open_click(
    trigger: On<PointerClick>,
    buttons: Query<&DiagnosticOpenButton>,
    mut commands: Commands,
) {
    let Ok(button) = buttons.get(trigger.event_target()) else {
        return;
    };
    let row = button.0.clone();
    commands.queue(move |world: &mut World| build_diagnostics::open_diagnostic(world, &row));
}

/// Slide the indeterminate progress segment while a build runs (the
/// redirected project build has no reliable unit total to fill against).
fn animate_build_bar(
    time: Res<Time>,
    build_status: Res<BuildStatus>,
    mut fill: Query<&mut Node, With<BuildPanelBarFill>>,
) {
    let Ok(mut node) = fill.single_mut() else {
        return;
    };
    if matches!(build_status.state, BuildState::Building { .. }) {
        let phase = (time.elapsed_secs() % BAR_CYCLE) / BAR_CYCLE;
        let sweep = 1.0 - (2.0 * phase - 1.0).abs();
        node.left = Val::Percent(sweep * (100.0 - BAR_SEGMENT));
        node.width = Val::Percent(BAR_SEGMENT);
    } else if node.width != Val::Percent(0.0) {
        node.width = Val::Percent(0.0);
    }
}

/// Reset the once-per-open focus flag and the last project's build outcome
/// and failure when a project opens.
fn reset_build_focus(mut focus: ResMut<BuildPanelFocus>, status: Option<ResMut<BuildStatus>>) {
    focus.first_build_shown = false;
    if let Some(mut status) = status {
        status.outcome = None;
        if matches!(status.state, BuildState::Failed { .. }) {
            status.state = BuildState::Idle;
        }
    }
}

/// Bring the Build panel to the front on the first build after opening a
/// project and whenever a build fails; leave routine successful rebuilds
/// alone so the panel does not steal focus.
fn auto_focus_build_panel(
    build_status: Res<BuildStatus>,
    mut tree: ResMut<DockTree>,
    mut focus: ResMut<BuildPanelFocus>,
) {
    if !build_status.is_changed() {
        return;
    }
    let surface = match &build_status.state {
        BuildState::Failed { .. } | BuildState::Blocked { .. } => true,
        BuildState::Building { .. } if !focus.first_build_shown => {
            focus.first_build_shown = true;
            true
        }
        _ => false,
    };
    if surface {
        activate_build_tab(&mut tree);
    }
}

/// Make the Build panel the active tab in whichever dock leaf holds it.
fn activate_build_tab(tree: &mut DockTree) {
    let Some(leaf_id) = tree.find_leaf_with_window(BUILD_WINDOW_ID) else {
        return;
    };
    let tab = tree
        .get(leaf_id)
        .and_then(|node| node.as_leaf())
        .and_then(|leaf| {
            leaf.tabs()
                .find(|(id, _)| *id == BUILD_WINDOW_ID)
                .map(|(_, tab)| tab)
        });
    if let Some(tab) = tab {
        tree.set_active(leaf_id, tab);
    }
}

/// Registers the Build panel as a bottom-dock window, like the other
/// built-in panels.
#[derive(Default)]
pub struct BuildPanelExtension;

impl JackdawExtension for BuildPanelExtension {
    fn id(&self) -> String {
        "jackdaw.build_panel".to_string()
    }

    fn label(&self) -> String {
        "Build".to_string()
    }

    fn kind(&self) -> ExtensionKind {
        ExtensionKind::Builtin
    }

    fn register(&self, ctx: &mut ExtensionContext) {
        ctx.register_window(
            WindowDescriptor::new(BUILD_WINDOW_ID)
                .with_name("Build")
                .with_icon(Icon::Hammer.unicode())
                .with_default_area(DefaultArea::BottomDock)
                .with_priority(3)
                .with_build(|window| {
                    let font = window
                        .world()
                        .get_resource::<EditorFont>()
                        .map(|f| f.0.clone())
                        .unwrap_or_default();
                    let parent = window.target_entity();
                    build_build_panel(window.world_mut(), parent, font);
                }),
        );
    }
}

#[cfg(test)]
mod diagnostic_rows_tests {
    use super::*;
    use crate::build_diagnostics::{parse_diagnostics, sync_build_diagnostics};
    use bevy::ecs::system::RunSystemOnce as _;

    const FAILED_LOG: &str = "error[E0308]: mismatched types\n \
         --> src/lib.rs:12:5\n\
         error[E0369]: cannot add `String` to `{integer}`\n \
         --> src/lib.rs:30:9\n\
         warning: unused variable `y`\n \
         --> src/game.rs:3:7\n\
         error[E0599]: no method named `spin`\n \
         --> src/game.rs:77:14\n\
         error[E0425]: cannot find value `w`\n \
         --> src/game.rs:81:5\n\
         error[E0308]: mismatched types\n \
         --> src/game.rs:90:20\n\
         error[E0382]: borrow of moved value\n \
         --> src/game.rs:95:9\n\
         error[E0597]: borrowed value does not live long enough\n \
         --> src/game.rs:99:5\n\
         error[E0308]: mismatched types\n \
         --> src/game.rs:104:6\n";

    /// A failed build renders a structured strip: the "N errors" summary
    /// pinning the first error, one row per actionable position (capped),
    /// and an Open button carrying the row's fields. A cleared latch hides
    /// the strip and takes the rows with it.
    #[test]
    fn the_failed_log_renders_summary_rows_and_clears_with_the_latch() {
        let mut world = World::new();
        world.init_resource::<BuildStatus>();
        world.init_resource::<BuildDiagnostics>();
        world.spawn((
            BuildPanelRows,
            BuildPanelRowsFont(Handle::default()),
            Node::default(),
        ));

        {
            let mut status = world.resource_mut::<BuildStatus>();
            status.failed_log = Some(FAILED_LOG.to_string());
        }
        world.run_system_once(sync_build_diagnostics).unwrap();
        world.run_system_once(sync_build_diagnostic_rows).unwrap();

        // The strip's face: the summary and overflow rows carry their text on
        // the marked row; a position row's arrow rides its text child.
        let rows: Vec<String> = world
            .query::<&Text>()
            .iter(&world)
            .map(|text| text.0.clone())
            .collect();
        assert!(
            rows.iter()
                .any(|text| text == "8 errors · first: src/lib.rs:12:5"),
            "the summary counts the level lines and pins the first error: {rows:?}"
        );
        let positioned: Vec<_> = rows
            .iter()
            .filter(|text| text.starts_with("--> "))
            .collect();
        assert_eq!(
            positioned.len(),
            MAX_DIAGNOSTIC_ROWS,
            "only the cap renders; the rest reads in the log below"
        );
        assert!(
            positioned.iter().any(|text| *text == "--> src/lib.rs:12:5"),
            "the first error is rendered as the log spelled it"
        );
        assert!(
            rows.iter().any(|text| text.contains("and 3 more")),
            "the overflow row names the count the strip left out"
        );
        // Every rendered row carries its Open button with the position.
        let buttons: Vec<&DiagnosticOpenButton> = world
            .query::<&DiagnosticOpenButton>()
            .iter(&world)
            .collect();
        assert_eq!(buttons.len(), MAX_DIAGNOSTIC_ROWS);
        assert_eq!(buttons[0].0.position(), "src/lib.rs:12:5");

        // The next build starts: the latch clears, the strip goes empty.
        {
            let mut status = world.resource_mut::<BuildStatus>();
            status.failed_log = None;
        }
        world.run_system_once(sync_build_diagnostics).unwrap();
        world.run_system_once(sync_build_diagnostic_rows).unwrap();
        let remaining = world
            .query::<(&BuildPanelRow, &Node)>()
            .iter(&world)
            .count();
        assert_eq!(remaining, 0, "the cleared latch takes the rows with it");
    }

    /// An arrowless failure (a linker refusal, cargo not even starting) has
    /// no rows to click but still counts its errors, so the summary never
    /// undercounts what went wrong.
    #[test]
    fn an_arrowless_failure_shows_a_summary_without_rows() {
        let mut world = World::new();
        world.init_resource::<BuildStatus>();
        world.init_resource::<BuildDiagnostics>();
        world.spawn((
            BuildPanelRows,
            BuildPanelRowsFont(Handle::default()),
            Node::default(),
        ));
        {
            let mut status = world.resource_mut::<BuildStatus>();
            status.failed_log =
                Some("error: linking with `cc` failed: exit status 1\n".to_string());
        }
        world.run_system_once(sync_build_diagnostics).unwrap();
        assert_eq!(
            world.resource::<BuildDiagnostics>().errors,
            1,
            "the count reads the level lines, arrows or not"
        );
        world.run_system_once(sync_build_diagnostic_rows).unwrap();
        let summary: Vec<String> = world
            .query::<(&BuildPanelRow, &Text)>()
            .iter(&world)
            .map(|(_, text)| text.0.clone())
            .collect();
        assert_eq!(summary.len(), 1, "only the summary line: {summary:?}");
        assert!(
            summary[0].contains("1 errors") && summary[0].contains("no source position"),
            "the summary says the log names no position: {}",
            summary[0]
        );
    }

    /// The parse itself, feeding the strip, keeps warnings distinct from
    /// errors so a row renders in its severity's color.
    #[test]
    fn rows_keep_their_severity_through_the_panel() {
        let rows = parse_diagnostics(
            "warning: unused\n --> src/a.rs:1:2\nerror: bad\n --> src/b.rs:3:4\n",
        );
        assert_eq!(rows.len(), 2);
        assert_eq!(
            rows[0].severity,
            crate::build_diagnostics::Severity::Warning
        );
        assert_eq!(
            build_diagnostics::severity_color(rows[0].severity),
            tokens::TEXT_WARNING
        );
        assert_eq!(
            build_diagnostics::severity_color(rows[1].severity),
            tokens::TEXT_ERROR
        );
    }
}
