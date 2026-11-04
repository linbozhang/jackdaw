//! Play-In-Editor runtime.
//!
//! Builds the project with plain `cargo build`, launches the game's own
//! executable as a child process, and drives it over an `ipc-channel`
//! connection. Children stream `StateEvent`s back and respond to
//! `ControlEvent`s (Pause / Resume / Stop). Stop reaps the children; the
//! authored scene is never mutated.
//!
//! Instances are keyed by [`InstanceKey`] (config label plus 1-based
//! instance number). Builds are keyed by [`BuildKey`]: the project root
//! plus the cargo target a run names. Runs without a target share the
//! root's default build; several instances wait on one build and spawn
//! together when it finishes.

use std::collections::{HashMap, VecDeque};
use std::io::{self, BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use bevy::prelude::*;
use bevy::tasks::{AsyncComputeTaskPool, Task, futures_lite::future};
use jackdaw_api::pie::PlayState;
use jackdaw_api::prelude::*;
use jackdaw_pie_protocol::event::{from_bytes, to_bytes};
use jackdaw_pie_protocol::manifest::RunConfig;
use jackdaw_pie_protocol::{
    ControlEvent, IpcChannelTransport, PieChannel, PieTransport, StateEvent, serve,
};

use crate::build_status::BuildStatus;
use crate::ext_build::BuildProgress;
use crate::pie_current::{
    PiePlayCurrentOp, ProjectSetSaveBeforePlayOp, SaveBeforePlay, SceneOverrideLaunch,
};
use crate::pie_mirror::{PieInstances, PieViewMode};
use crate::project_build::shim::ShimSpec;
use crate::project_build::{BuildLoad, CargoTarget};
use crate::run_config::RunConfigs;

/// A build's cache key in [`PieSession::builds`]: which project, and
/// which cargo target of it. A run naming a bin/example gets its own
/// entry, so playing one target can never launch another target's
/// cached binary; runs without a target share the root's default
/// (`None`), exactly the single build per project there always was.
type BuildKey = (PathBuf, Option<CargoTarget>);

/// How many trailing stderr lines to keep from a game process, so a
/// crash can be reported without buffering unbounded output.
const STDERR_TAIL_LINES: usize = 40;

/// How long to wait for a launched child to connect back before giving
/// up on it.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(30);

/// How long a child asked to stop has to exit on its own before
/// [`advance_child`] kills it. The graceful window is what makes the
/// game-side `Stop` → `AppExit::Success` path reachable at all: without
/// it, an immediate kill beats the message every time. The stop prompt
/// and the return to authoring land when the last child is reaped, so
/// both arrive within this bound after the stop is asked for.
const GRACEFUL_STOP_DEADLINE: Duration = Duration::from_secs(2);

/// Marker for the toolbar transport buttons. `PiePlugin` installs
/// an `On<Add<PieButton>>` observer that wires each button's
/// `PointerClick` to the corresponding handler.
#[derive(Component, Clone, Copy, Debug, PartialEq, Eq)]
pub enum PieButton {
    Play,
    Pause,
    Stop,
    Reload,
    /// Rebuild the project so new or changed game code appears in the
    /// editor. Distinct from `Reload` (which rebuilds and relaunches the
    /// running game): `Rebuild` is the edit-mode refresh of the component
    /// list, and dispatches `project.build`.
    Rebuild,
}

/// Identifies one running instance: a config label plus its 1-based
/// instance number.
#[derive(Clone, PartialEq, Eq, Hash, Debug)]
pub struct InstanceKey {
    pub config: String,
    pub instance: u32,
}

impl std::fmt::Display for InstanceKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} #{}", self.config, self.instance)
    }
}

/// Rolling buffer of a child's most recent stderr lines, filled by the
/// per-child reader thread and read back when reporting a crash.
type StderrTail = Arc<Mutex<VecDeque<String>>>;

/// One launched child and its connection progress.
enum ChildStage {
    /// The child is launched and `IpcServerHandle::accept` is blocking
    /// on a task pool, waiting for it to connect. `since` bounds that
    /// wait so a child that never connects does not hang forever.
    Connecting {
        child: Child,
        accept: Task<io::Result<IpcChannelTransport>>,
        stderr_tail: StderrTail,
        since: Instant,
    },
    /// The child is connected and running; its transport is held here.
    /// `stop_deadline` is set when it has been asked to stop: until then
    /// (or its own exit) it keeps running, and past it [`advance_child`]
    /// kills it, so a game that honors `Stop` gets to flush and exit
    /// cleanly while one that ignores it cannot outlive the window.
    Live {
        child: Child,
        transport: IpcChannelTransport,
        stderr_tail: StderrTail,
        stop_deadline: Option<Instant>,
    },
}

/// The product of a completed game build: the executable Play runs, plus
/// what the build reported about how the game links — which an export
/// needs and Play ignores. The extracted type schema is persisted to
/// `.jackdaw/schema.json` by the build itself and picked up by the
/// editor's watcher, so it does not travel back through here.
pub(crate) struct GameBuildResult {
    pub(crate) binary: PathBuf,
    /// The `dylib` crates the build produced, the signal an export
    /// refuses; empty for a statically linked (template-shaped) build.
    pub(crate) dylib_artifacts: Vec<String>,
}

/// An in-flight or finished build, deduped by [`BuildKey`] (project root
/// plus cargo target). Instances waiting on it are spawned when it
/// finishes.
enum BuildState {
    /// `cargo build` is running on a task pool; `pending` lists the
    /// instances to spawn once the binary is ready. `progress` is the
    /// sink cargo writes compile progress into, surfaced in the footer.
    Running {
        task: Task<io::Result<GameBuildResult>>,
        pending: Vec<PendingSpawn>,
        progress: Arc<Mutex<BuildProgress>>,
    },
    /// The binary is built and cached at this path; later instances of
    /// the same spec spawn from it without rebuilding.
    Done(PathBuf),
    /// The build failed; its pending instances were dropped. `launch` says
    /// whether any were waiting, which a background rebuild's are not.
    Failed { launch: bool },
}

/// One instance waiting for its build to finish before spawning.
struct PendingSpawn {
    key: InstanceKey,
    run: RunConfig,
    /// The scene override this launch carries through the build, handed to
    /// the child through `JACKDAW_PIE_SCENE` when it spawns. `None` for a
    /// startup-scene launch, whose save gate ran before the build instead.
    scene_override: Option<SceneOverrideLaunch>,
}

/// Editor-side play orchestration. `NonSend` because ipc transports
/// are `Send` but not `Sync`.
#[derive(Default)]
pub struct PieSession {
    children: HashMap<InstanceKey, ChildStage>,
    builds: HashMap<BuildKey, BuildState>,
    /// The scene override each launched instance runs with, recorded for
    /// the launch log, stop cleanup, and the BRP face.
    scene_overrides: HashMap<InstanceKey, SceneOverrideLaunch>,
    /// Temporary run copies this session wrote under
    /// `<assets>/.jackdaw-pie/`, removed when play stops and swept at
    /// project open when a crash beat the cleanup to it.
    temp_copies: Vec<PathBuf>,
    /// Monotonic count of instances ever launched. A `pie_stopped` wait
    /// reads it as its baseline, so a session that began and ended
    /// entirely between two polls still satisfies the wait — observing
    /// the session while it is up is no longer the only proof it ran.
    launches: u64,
}

impl Drop for PieSession {
    /// A clean editor shutdown (window close or Ctrl+C) drops the `World` and
    /// so this resource; take the running games down with it. Hard kills that
    /// skip destructors (SIGKILL skips everything) are covered by the game
    /// itself, which exits once its link to the editor closes, and on Linux
    /// and Windows by the kernel as well. The temporary run copies go the
    /// same way; ones a hard kill stranded are swept at the next project
    /// open.
    fn drop(&mut self) {
        for (_key, mut stage) in self.children.drain() {
            match &mut stage {
                ChildStage::Connecting { child, .. } | ChildStage::Live { child, .. } => {
                    child.kill().ok();
                    child.wait().ok();
                }
            }
        }
        remove_temp_copies(&mut self.temp_copies);
    }
}

impl PieSession {
    /// Whether an instance is currently launched (connecting or live).
    pub fn is_running(&self, key: &InstanceKey) -> bool {
        self.children.contains_key(key)
    }

    /// The scene override an instance was launched with, if it carried one.
    pub fn scene_override(&self, key: &InstanceKey) -> Option<&SceneOverrideLaunch> {
        self.scene_overrides.get(key)
    }

    /// Keys of all launched instances, for the dropdown checks.
    pub fn running_keys(&self) -> impl Iterator<Item = &InstanceKey> {
        self.children.keys()
    }

    /// Whether an instance is queued behind an in-flight build but not
    /// yet spawned. Guards against double-launching during the build
    /// window, which would strand the first child.
    fn is_pending(&self, key: &InstanceKey) -> bool {
        self.builds.values().any(|build| {
            matches!(build, BuildState::Running { pending, .. }
                if pending.iter().any(|p| p.key == *key))
        })
    }

    /// Whether an instance is waiting on a build before it spawns.
    fn is_launching(&self) -> bool {
        self.builds.values().any(
            |build| matches!(build, BuildState::Running { pending, .. } if !pending.is_empty()),
        )
    }

    /// Whether the last thing a launch did was fail its build.
    fn launch_failed(&self) -> bool {
        self.builds
            .values()
            .any(|build| matches!(build, BuildState::Failed { launch: true }))
    }

    /// Monotonic count of instances ever launched, the `pie_stopped`
    /// wait's session-proof baseline.
    pub fn launches(&self) -> u64 {
        self.launches
    }

    /// Bump the launch count without launching anything: a test's way of
    /// standing in for a session that already came and went.
    #[cfg(test)]
    pub fn note_launch_for_test(&mut self) {
        self.launches += 1;
    }

    /// One launched instance as the BRP face summarizes it.
    pub fn instance_faces(&self) -> Vec<PieInstanceFace> {
        self.children
            .iter()
            .map(|(key, stage)| PieInstanceFace {
                key: key.clone(),
                stage: match stage {
                    ChildStage::Connecting { .. } => "connecting",
                    ChildStage::Live { .. } => "live",
                },
                scene_override: self.scene_overrides.get(key).cloned(),
            })
            .collect()
    }
}

/// One launched instance, for the `jackdaw/pie` face.
pub struct PieInstanceFace {
    pub key: InstanceKey,
    /// `connecting` or `live`.
    pub stage: &'static str,
    /// The scene override this instance runs with, when it plays the
    /// editor's scene rather than the game's own startup scene.
    pub scene_override: Option<SceneOverrideLaunch>,
}

/// What play-in-editor is doing: `building` while a launch waits on its
/// cargo build, `running` once a game process is up (a paused game
/// included), `failed` when a launch's build did not compile, `stopped`
/// otherwise.
pub(crate) fn play_status(world: &World) -> &'static str {
    let session = world.get_non_send::<PieSession>();
    let playing = world
        .get_resource::<State<PlayState>>()
        .is_some_and(|state| *state.get() != PlayState::Stopped);
    if playing || session.is_some_and(|session| !session.children.is_empty()) {
        return "running";
    }
    if session.is_some_and(PieSession::is_launching) {
        return "building";
    }
    if session.is_some_and(PieSession::launch_failed) {
        return "failed";
    }
    "stopped"
}

pub struct PiePlugin;

impl Plugin for PiePlugin {
    fn build(&self, app: &mut App) {
        app.init_state::<PlayState>()
            .init_non_send::<PieSession>()
            .init_resource::<PieViewMode>()
            .init_resource::<PieInstances>()
            .init_resource::<crate::pie_projection::PieProjection>()
            .init_resource::<crate::live_frame::LiveFrameStream>()
            .init_resource::<crate::live_edits::LiveEditLog>()
            .init_resource::<crate::live_highlight::LastHighlight>()
            .init_resource::<PieWindowMode>()
            .init_resource::<PiePrebuildState>()
            .init_resource::<crate::pie_current::LastPlayCurrent>()
            .init_resource::<crate::project_types::ProjectTypes>()
            .init_resource::<crate::project_definitions::ProjectDefinitionKinds>()
            .init_resource::<ProjectSchemaWatch>()
            .init_resource::<EditorBuildSettings>()
            // PIE is an editor-only subsystem; gate it to the editor state so it
            // never ticks in the launcher (`ProjectSelect`). Without this,
            // `reconcile_build_status` resets the shared `BuildStatus` from
            // `Building` to `Idle` every frame during the launcher's editor
            // build, so the build's completion handler drops the result and the
            // handoff never fires.
            .add_systems(
                Update,
                (
                    advance_pie_session,
                    prebuild_play_target,
                    sync_project_build_settings,
                    watch_project_source_for_edit,
                    watch_project_schema,
                    drain_game_events,
                    crate::live_highlight::sync_selection_highlight,
                )
                    .run_if(in_state(crate::AppState::Editor)),
            )
            .add_systems(
                OnEnter(PlayState::Stopped),
                (
                    reset_view_mode_on_stop,
                    cleanup_session_on_stop,
                    crate::live_frame::clear_stream,
                    crate::live_edits_ui::open_stop_prompt_if_dirty,
                ),
            )
            .add_systems(
                OnExit(PlayState::Stopped),
                crate::live_edits_ui::review_handoff_on_replay,
            )
            .add_observer(wire_pie_button);
    }
}

/// Reset the outliner/inspector view back to Scene when play stops.
fn reset_view_mode_on_stop(mut mode: ResMut<PieViewMode>) {
    *mode = PieViewMode::Scene;
}

/// Delete every temporary run copy in `copies`, tolerating ones already
/// gone (another editor on the same project may have swept them).
fn remove_temp_copies(copies: &mut Vec<PathBuf>) {
    for copy in copies.drain(..) {
        match std::fs::remove_file(&copy) {
            Ok(()) => info!("PIE: removed the temporary run copy {}", copy.display()),
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
            Err(err) => warn!(
                "PIE: cannot remove the temporary run copy {}: {err}",
                copy.display()
            ),
        }
    }
}

/// Record what one spawned launch overrode the game's startup scene with:
/// the session's answer for stop cleanup and the BRP face, and the launch
/// log line that says which scene the game was handed.
fn record_scene_override(
    world: &mut World,
    key: &InstanceKey,
    scene_override: Option<&SceneOverrideLaunch>,
) {
    let Some(scene_override) = scene_override else {
        return;
    };
    let mut session = world.non_send_mut::<PieSession>();
    session
        .scene_overrides
        .insert(key.clone(), scene_override.clone());
    if let Some(temp_copy) = &scene_override.temp_copy
        && !session.temp_copies.contains(temp_copy)
    {
        session.temp_copies.push(temp_copy.clone());
    }
    let source = if scene_override.from_temp_copy {
        "an unsaved copy"
    } else {
        "the editor's scene"
    };
    info!(
        "PIE: {key} launched with scene override '{}' ({source})",
        scene_override.assets_relative
    );
}

/// Shared cleanup for every path into `Stopped`: the stop button, a crashed
/// or self-exited child being reaped, and the last per-instance stop. Drops
/// the buffered snapshots and focus, deletes this session's temporary run
/// copies, then reverts the preview to the authored scene. Without this on
/// the reap path, ghost previews and a dead focus key survive a crash, and
/// the dead key blocks the next session's auto-enter (focus is only
/// established when none exists).
fn cleanup_session_on_stop(world: &mut World) {
    {
        let mut session = world.non_send_mut::<PieSession>();
        remove_temp_copies(&mut session.temp_copies);
        session.scene_overrides.clear();
    }
    if let Some(mut instances) = world.get_resource_mut::<PieInstances>() {
        instances.buffers.clear();
        instances.focused = None;
    }
    crate::pie_projection::revert_preview(world);
}

/// Switch the outliner/inspector view to Live and project the focused
/// instance's buffered state into the preview world.
///
/// Shared by the Scene/Live toggle and the auto-enter path that fires the
/// moment a running instance first streams data. A no-op for the projection
/// when no instance is focused yet. [`reset_view_mode_on_stop`] owns the
/// revert when play stops.
pub(crate) fn enter_live_view(world: &mut World) {
    *world.resource_mut::<PieViewMode>() = PieViewMode::Live;
    crate::pie_projection::reproject_focused(world);
}

pub(crate) fn add_to_extension(ctx: &mut ExtensionContext) {
    use jackdaw_api_internal::keymap::PresetInput;
    ctx.register_operator::<PiePlayOp>()
        .register_operator::<PiePauseOp>()
        .register_operator::<PieStopOp>()
        .register_operator::<PieReloadOp>()
        .register_operator::<ProjectBuildOp>()
        .register_operator::<ProjectToggleAutoBuildOp>()
        .register_operator::<ProjectTogglePrebuildOp>()
        .register_operator::<ProjectToggleSaveBeforePlayOp>()
        .register_operator::<ProjectSetSaveBeforePlayOp>()
        .register_operator::<PieWindowModeToggleOp>()
        .register_operator::<crate::live_input::PiePlayInputToggleOp>()
        .register_operator::<crate::live_edits::PieLiveEditSaveOp>()
        .register_operator::<crate::live_edits::PieLiveEditRevertOp>()
        .register_operator::<crate::live_edits::PieLiveEditsApplyAllOp>()
        .register_operator::<crate::live_edits::PieLiveEditsDiscardAllOp>()
        .register_operator::<PiePlayCurrentOp>()
        // F5 runs the scene in front, the main Play button's action. The
        // startup-scene launch stays a dropdown pick (Shift+F5 can follow
        // when someone asks for it).
        .bind_operator_host::<PiePlayCurrentOp>([PresetInput::key("F5")]);
}

fn play_is_stopped_or_paused(state: Res<State<PlayState>>) -> bool {
    !matches!(state.get(), PlayState::Playing)
}

fn play_is_playing(state: Res<State<PlayState>>) -> bool {
    *state.get() == PlayState::Playing
}

fn play_is_running(state: Res<State<PlayState>>) -> bool {
    *state.get() != PlayState::Stopped
}

/// Start the game. From Stopped, builds the project's game binary and
/// launches it connected to the editor; from Paused, resumes.
#[operator(
    id = "pie.play",
    label = "Play",
    description = "Start the game running in the editor.",
    is_available = play_is_stopped_or_paused
)]
pub(crate) fn pie_play(_: In<OperatorParameters>, mut commands: Commands) -> OperatorResult {
    commands.queue(handle_play);
    OperatorResult::Finished
}

/// Pause the running game.
#[operator(
    id = "pie.pause",
    label = "Pause",
    description = "Pause the running game.",
    is_available = play_is_playing
)]
pub(crate) fn pie_pause(_: In<OperatorParameters>, mut commands: Commands) -> OperatorResult {
    commands.queue(handle_pause);
    OperatorResult::Finished
}

/// Stop the running game and return to authoring mode.
#[operator(
    id = "pie.stop",
    label = "Stop",
    description = "Stop the running game.",
    is_available = play_is_running
)]
pub(crate) fn pie_stop(_: In<OperatorParameters>, mut commands: Commands) -> OperatorResult {
    commands.queue(handle_stop);
    OperatorResult::Finished
}

/// Rebuild and relaunch the running game.
#[operator(
    id = "pie.reload",
    label = "Reload",
    description = "Rebuild and relaunch the running game.",
    is_available = play_is_running
)]
pub(crate) fn pie_reload(_: In<OperatorParameters>, mut commands: Commands) -> OperatorResult {
    commands.queue(handle_reload);
    OperatorResult::Finished
}

/// Rebuild the project now so new or changed code is picked up by the
/// editor. This is the manual counterpart to auto-build and runs the same
/// pipeline as an out-of-editor `jackdaw build`: a game persists the schema
/// the editor then reloads, and an extension is loaded into the editor.
#[operator(
    id = "project.build",
    label = "Rebuild Project",
    description = "Rebuild the project so new or changed components and extensions appear in the editor."
)]
pub(crate) fn project_build(_: In<OperatorParameters>, mut commands: Commands) -> OperatorResult {
    commands.queue(|world: &mut World| {
        let Some(root) = project_root(world) else {
            return;
        };
        if crate::extension_build::is_extension_project(world, &root, true) {
            crate::extension_build::start_extension_build(world, &root);
        } else {
            spawn_project_build(world, &root, BuildLoad::Foreground);
        }
    });
    OperatorResult::Finished
}

/// Turn automatic rebuild-on-source-change on or off. Off by default so
/// the editor never builds behind the user's back; enabling it gives
/// live pickup for those who want it.
#[operator(
    id = "project.toggle_auto_build",
    label = "Toggle Auto Build",
    description = "Turn automatic rebuild-on-source-change on or off."
)]
pub(crate) fn project_toggle_auto_build(
    _: In<OperatorParameters>,
    mut commands: Commands,
) -> OperatorResult {
    commands.queue(|world: &mut World| {
        let enabled = {
            let mut settings = world.resource_mut::<EditorBuildSettings>();
            settings.auto_build = !settings.auto_build;
            settings.auto_build
        };
        persist_project_build_settings(world);
        info!(
            "PIE: auto-build {}",
            if enabled { "enabled" } else { "disabled" }
        );
    });
    OperatorResult::Finished
}

/// Turn the open-time background pre-build on or off. On by default; the
/// `JACKDAW_PIE_PREBUILD` environment variable overrides this for a
/// single session.
#[operator(
    id = "project.toggle_prebuild",
    label = "Toggle Prebuild On Open",
    description = "Turn the background pre-build that runs when a project opens on or off."
)]
pub(crate) fn project_toggle_prebuild(
    _: In<OperatorParameters>,
    mut commands: Commands,
) -> OperatorResult {
    commands.queue(|world: &mut World| {
        let enabled = {
            let mut settings = world.resource_mut::<EditorBuildSettings>();
            settings.prebuild = !settings.prebuild;
            settings.prebuild
        };
        persist_project_build_settings(world);
        info!(
            "PIE: pre-build on open {}",
            if enabled { "enabled" } else { "disabled" }
        );
    });
    OperatorResult::Finished
}

/// Cycle how Play handles unsaved scene changes: save → ask → play an
/// unsaved copy → save. Kept for the operator registry and older scripts;
/// `project.set_save_before_play` names the mode directly.
#[operator(
    id = "project.toggle_save_before_play",
    label = "Toggle Save Before Play",
    description = "Cycle how Play handles unsaved scenes: save, ask, or play an unsaved copy."
)]
pub(crate) fn project_toggle_save_before_play(
    _: In<OperatorParameters>,
    mut commands: Commands,
) -> OperatorResult {
    commands.queue(|world: &mut World| {
        let next = {
            let mut settings = world.resource_mut::<EditorBuildSettings>();
            settings.save_before_play = match settings.save_before_play {
                SaveBeforePlay::Save => SaveBeforePlay::Ask,
                SaveBeforePlay::Ask => SaveBeforePlay::PlayUnsavedCopy,
                SaveBeforePlay::PlayUnsavedCopy => SaveBeforePlay::Save,
            };
            settings.save_before_play
        };
        persist_project_build_settings(world);
        info!("PIE: save before play set to {}", next.as_log());
    });
    OperatorResult::Finished
}

/// Input capture needs a focused instance and a fresh frame to forward to.
pub(crate) fn focused_with_fresh_stream(
    stream: Res<crate::live_frame::LiveFrameStream>,
    instances: Res<PieInstances>,
) -> bool {
    instances.focused.is_some() && stream.is_fresh()
}

/// Where a launched game's window lives. Applies to the next launch.
#[derive(Resource, Default, Debug, Clone, Copy, PartialEq, Eq)]
pub enum PieWindowMode {
    /// No OS window: the game streams its frames into the editor's Game panel.
    #[default]
    Embedded,
    /// The game opens its own OS window (debug fallback; no input capture).
    Windowed,
}

/// Whether a launch under this mode sets `JACKDAW_PIE_WINDOWLESS`.
fn wants_windowless_env(mode: PieWindowMode) -> bool {
    mode == PieWindowMode::Embedded
}

fn toggle_window_mode(mode: &mut PieWindowMode) {
    *mode = match *mode {
        PieWindowMode::Embedded => PieWindowMode::Windowed,
        PieWindowMode::Windowed => PieWindowMode::Embedded,
    };
}

/// Switch the next launch between an embedded game (streamed into the Game
/// panel) and a separate game window.
#[operator(
    id = "pie.window_mode_toggle",
    label = "Toggle Game Window Mode",
    description = "Switch the next launch between embedded (Game panel) and a separate game window."
)]
pub(crate) fn pie_window_mode_toggle(
    _: In<OperatorParameters>,
    mut mode: ResMut<PieWindowMode>,
) -> OperatorResult {
    toggle_window_mode(&mut mode);
    OperatorResult::Finished
}

/// Stop every running instance, drop the cached build path so the next
/// launch re-runs the (incremental) cargo build, then relaunch each
/// instance that was running. The game reloads its scene from disk.
/// The stop is immediate ([`force_stop_all`]), not graceful: a rebuilt
/// session replaces the child outright, so the old one waiting out a
/// graceful window would only delay the reload.
pub fn handle_reload(world: &mut World) {
    let keys: Vec<InstanceKey> = world
        .non_send::<PieSession>()
        .children
        .keys()
        .cloned()
        .collect();

    if keys.is_empty() {
        return;
    }

    let Some(run_configs) = world
        .get_resource::<RunConfigs>()
        .map(|c| c.manifest.clone())
    else {
        warn!("PIE: Reload but run configurations are not loaded");
        return;
    };

    // A current-scene session reloads on a freshly resolved override: the
    // scene may have moved on since the launch, and the relaunch owes the
    // game what is in front now (a new temp copy when it was edited, the
    // same file when it was not). Which instances were playing the current
    // scene is read before the stop clears the table.
    let had_override: Vec<InstanceKey> = {
        let session = world.non_send::<PieSession>();
        keys.iter()
            .filter(|key| session.scene_override(key).is_some())
            .cloned()
            .collect()
    };
    let reload_override = crate::pie_current::override_for_reload(world);

    force_stop_all(world);

    for key in keys {
        let Some(run) = run_configs.run_by_name(&key.config).cloned() else {
            warn!("PIE: Reload could not find run config '{}'", key.config);
            continue;
        };
        let scene_override = had_override
            .contains(&key)
            .then(|| reload_override.clone())
            .flatten();
        match scene_override {
            Some(scene_override) => {
                launch_instance_with_override(world, key, run, Some(scene_override));
            }
            None => launch_instance(world, key, run),
        }
    }

    info!("PIE: Reload (rebuild + relaunch)");
}

/// Spawn a click observer on each `PieButton` as it's added. The
/// observer dispatches the corresponding `pie.*` operator.
fn wire_pie_button(
    trigger: On<Add<PieButton>>,
    buttons: Query<&PieButton>,
    mut commands: Commands,
) {
    let entity = trigger.event_target();
    let Ok(kind) = buttons.get(entity).copied() else {
        return;
    };
    let op_id = match kind {
        // The main button plays the scene in front; the dropdown's
        // "Play Startup Scene" row and the run rows hold the game's own
        // startup scene.
        PieButton::Play => PiePlayCurrentOp::ID,
        PieButton::Pause => PiePauseOp::ID,
        PieButton::Stop => PieStopOp::ID,
        PieButton::Reload => PieReloadOp::ID,
        PieButton::Rebuild => ProjectBuildOp::ID,
    };
    commands
        .entity(entity)
        .observe(move |_: On<PointerClick>, mut commands: Commands| {
            commands
                .operator(op_id)
                .settings(CallOperatorSettings {
                    execution_context: ExecutionContext::Invoke,
                    creates_history_entry: false,
                })
                .call();
        });
}

/// The root of the open project, when one is open. Logs and returns
/// `None` otherwise, so callers skip rather than crash.
pub(crate) fn project_root(world: &World) -> Option<PathBuf> {
    match world.get_resource::<crate::project::ProjectRoot>() {
        Some(project) => Some(project.root.clone()),
        None => {
            warn!("PIE: Play requested but no project is open");
            None
        }
    }
}

/// Launch one run-config instance on the game's own startup scene. No-op if
/// it is already running. Resolves the build spec, then either spawns
/// immediately from a cached binary, joins an in-flight build's pending
/// list, or starts a new build keyed by the spec.
pub(crate) fn launch_instance(world: &mut World, key: InstanceKey, run: RunConfig) {
    launch_instance_inner(world, key, run, None);
}

/// [`launch_instance`] carrying a scene override: the child is handed
/// `JACKDAW_PIE_SCENE` and the unsaved-scenes gate is the caller's to have
/// applied already — `pie.play_current` resolves the save policy before it
/// gets here.
pub(crate) fn launch_instance_with_override(
    world: &mut World,
    key: InstanceKey,
    run: RunConfig,
    scene_override: Option<SceneOverrideLaunch>,
) {
    launch_instance_inner(world, key, run, scene_override);
}

fn launch_instance_inner(
    world: &mut World,
    key: InstanceKey,
    run: RunConfig,
    scene_override: Option<SceneOverrideLaunch>,
) {
    {
        let session = world.non_send::<PieSession>();
        if session.is_running(&key) || session.is_pending(&key) {
            return;
        }
    }

    // A target naming both or neither of bin/example cannot become a
    // cargo command; refuse it before anything else runs.
    if let Some(target) = &run.target
        && let Err(reason) = target.validate()
    {
        warn!("PIE: not playing '{}': {reason}", run.label());
        crate::status_bar::notify_error(world, reason);
        return;
    }

    // Read root before borrowing the session mutably below.
    let Some(root) = project_root(world) else {
        return;
    };

    // The startup-scene launch saves what it can first, exactly as before;
    // a scene-override launch already applied the project's save policy in
    // resolving the override, so saving here would double-apply it.
    if scene_override.is_none()
        && let Err(reason) = save_before_play(world)
    {
        warn!("PIE: not playing: {reason}");
        crate::status_bar::notify_error(world, reason);
        return;
    }

    let build = build_key(&root, &run);

    // If the game binary is built AND still current, spawn from it
    // immediately. A source edit since the last build invalidates the
    // cache so Play runs the new code: each Play is a fresh process, so
    // rebuilding is always safe.
    if let Some(BuildState::Done(path)) = world.non_send::<PieSession>().builds.get(&build) {
        if source_is_current(&root, path) {
            let path = path.clone();
            if let Some(stage) = spawn_instance(world, &key, &run, &path, scene_override.as_ref()) {
                record_scene_override(world, &key, scene_override.as_ref());
                let mut session = world.non_send_mut::<PieSession>();
                session.launches += 1;
                session.children.insert(key, stage);
            }
            return;
        }
        info!("PIE: project source changed; rebuilding before Play");
        world.non_send_mut::<PieSession>().builds.remove(&build);
    }

    let Some(spec) = crate::project_build::shim_spec_for_project(&root).ok() else {
        warn!("PIE: no lib crate found in {}", root.display());
        return;
    };

    // A run target naming a bin/example no package declares would burn a
    // whole build to learn it from cargo's error; metadata answers in a
    // blink and lists the names that are real. The warm cache above ran
    // before this by design: an up-to-date binary was checked when it
    // was built, and a manifest edit that drops the target also marks
    // the cache stale.
    if let Some(target) = &build.1
        && let Err(reason) = preflight_run_target(&root, &spec.package_name, target)
    {
        warn!("PIE: not playing '{}': {reason}", run.label());
        crate::status_bar::notify_error(world, reason);
        return;
    }

    // Join an in-flight build's pending list, or start a new build.
    let mut session = world.non_send_mut::<PieSession>();
    match session.builds.get_mut(&build) {
        Some(BuildState::Running { pending, .. }) => {
            pending.push(PendingSpawn {
                key,
                run,
                scene_override,
            });
        }
        Some(BuildState::Done(_)) => unreachable!("handled above"),
        Some(BuildState::Failed { .. }) | None => {
            info!("PIE: building the game for {key}");
            let (task, progress) =
                spawn_game_build(&root, spec, build.1.clone(), BuildLoad::Foreground);
            session.builds.insert(
                build,
                BuildState::Running {
                    task,
                    pending: vec![PendingSpawn {
                        key,
                        run,
                        scene_override,
                    }],
                    progress,
                },
            );
        }
    }
}

/// The key a run's build lives under: the project root plus the cargo
/// target the run names. Runs without a target share the default build.
fn build_key(root: &Path, run: &RunConfig) -> BuildKey {
    (root.to_path_buf(), crate::run_config::cargo_target(run))
}

/// Whether the run's cargo target names a package and bin/example the
/// project really has, per `cargo metadata`, before a build starts: the
/// error lists the available names instead of failing a build in
/// cargo's words. A metadata failure stands down — the build itself
/// reports it — so the check can only refine errors, never cause one.
fn preflight_run_target(
    root: &Path,
    spec_package: &str,
    target: &CargoTarget,
) -> Result<(), String> {
    match crate::run_config::CargoMeta::load(root) {
        Some(meta) => {
            crate::project_build::cargo_meta::check_run_target(&meta, spec_package, target)
        }
        None => Ok(()),
    }
}

/// Save the modified scenes a startup-scene launch may load, unless the
/// project's save-before-play mode says otherwise. The mode is really the
/// current-scene play's policy; for the startup-scene path it keeps its
/// old shape: `save` (and `ask`, which has no dialog on this path and
/// errs on the safe side) saves, `play_unsaved_copy` skips saving the way
/// the pre-enum `false` did. A current-scene launch never comes through
/// here — it applies the policy itself before launching, and an untitled
/// scene in front runs as a copy rather than being refused.
fn save_before_play(world: &mut World) -> Result<(), String> {
    let saves = world
        .get_resource::<EditorBuildSettings>()
        .is_none_or(|settings| settings.save_before_play != SaveBeforePlay::PlayUnsavedCopy);
    if !saves {
        return Ok(());
    }
    save_scenes_before_launch(world, "playing")
}

/// Refuse a modified scene that has never been saved, then save every
/// modified scene, every definition asset card holding unsaved edits,
/// and the open animation graph in the same state, so what the editor
/// shows is on disk before something else consumes the project — Play
/// launching the game, an export staging its `assets/`. The `action`
/// names what asked ("playing", "exporting"), for the refusal messages.
pub(crate) fn save_scenes_before_launch(world: &mut World, action: &str) -> Result<(), String> {
    let untitled_in_front = world
        .get_resource::<crate::scenes::Scenes>()
        .and_then(|scenes| scenes.tabs.get(scenes.active))
        .is_some_and(|tab| tab.path.is_none());
    if untitled_in_front && crate::scenes::operators::active_tab_modified(world) {
        return Err(format!("Save the scene before {action}"));
    }
    let mut failures = crate::scenes::operators::save_modified_scenes(world);
    // Definition assets edited in the editor are part of what a launch
    // runs (the game reads their files): dirty cards save on the same
    // chain, and one that cannot write blocks the launch rather than
    // silently running the value that is on disk.
    failures.extend(crate::definition_assets::save_dirty_assets(world));
    // The open animation graph is the same kind of authored state: a
    // dirty graph the game would read as the stale file blocks the
    // launch instead of playing yesterday's transitions.
    if world
        .get_resource::<crate::animation::AnimationGraphDoc>()
        .is_some_and(|doc| doc.dirty)
        && crate::animation::graph_doc::write_graph_file(world).is_none()
    {
        failures.push("the open animation graph".to_string());
    }
    if failures.is_empty() {
        Ok(())
    } else {
        Err(format!(
            "Not {action}: could not save {}",
            failures.join("; ")
        ))
    }
}

/// Whether the built game binary is newer than the project's source. A
/// stale binary (source edited since the build) means Play must rebuild.
/// `Cargo.toml` and everything under `src/` are checked; a missing
/// binary counts as stale.
fn source_is_current(root: &Path, binary: &Path) -> bool {
    std::fs::metadata(binary)
        .and_then(|m| m.modified())
        .is_ok_and(|binary_mtime| source_unchanged_since(root, binary_mtime))
}

/// Whether nothing under `src/` and no `Cargo.toml` change is newer than
/// `built`.
pub(crate) fn source_unchanged_since(root: &Path, built: std::time::SystemTime) -> bool {
    let newest_source = newest_mtime(&root.join("src"))
        .into_iter()
        .chain(
            std::fs::metadata(root.join("Cargo.toml"))
                .and_then(|m| m.modified())
                .ok(),
        )
        .max();
    match newest_source {
        Some(src_mtime) => src_mtime <= built,
        None => true,
    }
}

/// The newest modification time under `dir`, recursively; `None` when
/// the directory is missing or empty.
fn newest_mtime(dir: &Path) -> Option<std::time::SystemTime> {
    let mut newest = None;
    let mut stack = vec![dir.to_path_buf()];
    while let Some(path) = stack.pop() {
        let Ok(entries) = std::fs::read_dir(&path) else {
            continue;
        };
        for entry in entries.flatten() {
            let entry_path = entry.path();
            if entry_path.is_dir() {
                stack.push(entry_path);
            } else if let Ok(mtime) = entry.metadata().and_then(|m| m.modified()) {
                newest = Some(newest.map_or(mtime, |n: std::time::SystemTime| n.max(mtime)));
            }
        }
    }
    newest
}

/// One line naming what actually went wrong, for the status bar: the first
/// real diagnostic in the log and where it points, rather than `Display`'s
/// summary line.
pub(crate) fn failure_summary(
    error: &crate::project_build::ProjectBuildError,
    detail: &str,
) -> String {
    /// Long enough for a rustc error line, short enough for the footer.
    const MAX: usize = 140;
    let mut lines = detail.lines().map(str::trim);
    let Some(line) = lines.find(|line| line.starts_with("error")) else {
        return error.to_string();
    };
    let summary = if line.chars().count() > MAX {
        let cut: String = line.chars().take(MAX).collect();
        format!("{cut}...")
    } else {
        line.to_string()
    };
    let location = lines
        .take_while(|line| !line.is_empty())
        .find_map(|line| line.strip_prefix("--> "));
    match location {
        Some(location) => format!("{summary} ({location})"),
        None => summary,
    }
}

/// Start the project's game build on the compute pool, returning the
/// task and the progress sink the footer polls. `target` narrows the
/// build to one run's cargo target, if it names one. Shared by Play's
/// launches and the export entry, which builds the release profile.
pub(crate) fn spawn_game_build(
    root: &Path,
    spec: ShimSpec,
    target: Option<CargoTarget>,
    load: jackdaw_project_build::BuildLoad,
) -> (Task<io::Result<GameBuildResult>>, Arc<Mutex<BuildProgress>>) {
    let progress = Arc::new(Mutex::new(BuildProgress::default()));
    let sink = Arc::clone(&progress);
    let jackdaw_dir = root.join(".jackdaw");
    let task = AsyncComputeTaskPool::get().spawn(async move {
        if let Ok(mut p) = sink.lock() {
            p.push_log("building the game".to_string());
        }
        // Stream live progress into the sink the footer bar and build log
        // read: per-crate counts drive the bar, diagnostics fill the log.
        let report_sink = Arc::clone(&sink);
        let mut report = move |event: crate::project_build::BuildEvent| {
            if let Ok(mut p) = report_sink.lock() {
                match event {
                    crate::project_build::BuildEvent::Compiled {
                        crate_name,
                        done,
                        fresh,
                    } => {
                        p.artifacts_done = done;
                        // Cached units still count toward progress but should
                        // not read as compiling in the header or the log.
                        if !fresh {
                            p.current_crate = Some(crate_name.clone());
                            p.push_log(format!("Compiling {crate_name}"));
                        }
                    }
                    crate::project_build::BuildEvent::Log(line) => {
                        // Warnings about the SDK explain the compiler
                        // errors that follow, and a user watching the
                        // terminal rather than the build panel would
                        // otherwise see only the errors.
                        if line.starts_with("warning:") || line.contains("is not usable") {
                            warn!("{line}");
                        }
                        p.push_log(line);
                    }
                }
            }
        };
        let result = crate::project_build::build_project_binary_with_load(
            &spec,
            &jackdaw_dir,
            target.as_ref(),
            load,
            &mut report,
        );
        match result {
            Ok(build) => {
                if let Ok(mut p) = sink.lock() {
                    let types = build
                        .schema
                        .as_ref()
                        .map(|s| s.components.len())
                        .unwrap_or(0);
                    p.push_log(format!("game ready ({types} types)"));
                }
                Ok(GameBuildResult {
                    binary: build.binary,
                    dylib_artifacts: build.dylib_artifacts,
                })
            }
            Err(err) => {
                // Diagnostics already streamed into the log via the build
                // reporter, so just note the failure and surface the error,
                // adding the detail only when it was not streamed.
                let detail = match &err {
                    crate::project_build::ProjectBuildError::Compile { log } => log.clone(),
                    other => other.to_string(),
                };
                let summary = failure_summary(&err, &detail);
                if let Ok(mut p) = sink.lock() {
                    p.push_log(format!("build failed: {err}"));
                    if detail != err.to_string() && !p.full_log.contains(detail.trim()) {
                        p.push_log(detail.clone());
                    }
                }
                Err(io::Error::other(summary))
            }
        }
    });
    (task, progress)
}

/// Stop one instance: a live child is asked to stop and holds the
/// [`GRACEFUL_STOP_DEADLINE`] window to exit on its own ([`advance_child`]
/// reaps it, by its exit or the deadline); a child still connecting never
/// brought the link up, so there is nothing graceful it could do with a
/// deadline and it is reaped now. The editor returns to authoring mode
/// once no children remain.
pub(crate) fn stop_instance(world: &mut World, key: &InstanceKey) {
    let mut reap_connecting = false;
    {
        let mut session = world.non_send_mut::<PieSession>();
        match session.children.get_mut(key) {
            None => return,
            Some(ChildStage::Live {
                transport,
                stop_deadline,
                ..
            }) => {
                if stop_deadline.is_none() {
                    send_control_to(transport, ControlEvent::Stop);
                    *stop_deadline = Some(Instant::now() + GRACEFUL_STOP_DEADLINE);
                    info!(
                        "PIE: {key} asked to stop; exiting on its own for {GRACEFUL_STOP_DEADLINE:?}"
                    );
                }
            }
            Some(ChildStage::Connecting { .. }) => reap_connecting = true,
        }
    }
    if reap_connecting
        && let Some(mut stage) = world.non_send_mut::<PieSession>().children.remove(key)
        && let ChildStage::Connecting { child, .. } = &mut stage
    {
        child.kill().ok();
        child.wait().ok();
    }

    if world.non_send::<PieSession>().children.is_empty()
        && *world.resource::<State<PlayState>>().get() != PlayState::Stopped
    {
        world
            .resource_mut::<NextState<PlayState>>()
            .set(PlayState::Stopped);
    }
}

/// Begin play. From Stopped, launches the first run config's instance
/// (building it if needed). From Paused, resumes every live child. No-op
/// if already Playing or if the project has no run configurations.
pub fn handle_play(world: &mut World) {
    let current = world.resource::<State<PlayState>>().get().clone();
    match current {
        PlayState::Stopped => {
            let Some(run_configs) = world.get_resource::<RunConfigs>() else {
                warn!("PIE: run configurations not loaded");
                return;
            };
            let runs = run_configs.manifest.runs.clone();
            let Some(first) = runs.into_iter().next() else {
                warn!("PIE: no run configurations");
                return;
            };
            let key = InstanceKey {
                config: first.label().to_string(),
                instance: 1,
            };
            launch_instance(world, key, first);
        }
        PlayState::Paused => {
            broadcast_control(world, ControlEvent::Resume);
            world
                .resource_mut::<NextState<PlayState>>()
                .set(PlayState::Playing);
            info!("PIE: Play (resumed)");
        }
        PlayState::Playing => {}
    }
}

/// Transition `Playing` -> `Paused`, telling every live child to freeze.
/// No-op otherwise.
pub fn handle_pause(world: &mut World) {
    if *world.resource::<State<PlayState>>().get() == PlayState::Playing {
        broadcast_control(world, ControlEvent::Pause);
        world
            .resource_mut::<NextState<PlayState>>()
            .set(PlayState::Paused);
        info!("PIE: Pause");
    }
}

/// Stop every instance gracefully: the live children have already been
/// sent [`ControlEvent::Stop`] and now hold the
/// [`GRACEFUL_STOP_DEADLINE`] window, reaped by [`advance_child`] as they
/// exit or when the deadline lands; children still connecting are reaped
/// now. Pending builds are discarded. The return to authoring mode (and
/// the stop prompt) follows the last reap, so it lands within the
/// deadline bound after this call.
pub fn handle_stop(world: &mut World) {
    let current = world.resource::<State<PlayState>>().get().clone();

    broadcast_control(world, ControlEvent::Stop);

    let mut session = world.non_send_mut::<PieSession>();
    let mut kept: HashMap<InstanceKey, ChildStage> = HashMap::new();
    for (key, mut stage) in session.children.drain() {
        match &mut stage {
            ChildStage::Live { stop_deadline, .. } => {
                // The broadcast above already sent the Stop; arm the
                // deadline it may not have had yet (a per-instance stop
                // may have armed an earlier one — the earliest wins).
                let now = Instant::now();
                *stop_deadline = Some(
                    stop_deadline.map_or(now + GRACEFUL_STOP_DEADLINE, |existing| {
                        existing.min(now + GRACEFUL_STOP_DEADLINE)
                    }),
                );
                info!(
                    "PIE: {key} asked to stop; exiting on its own for {GRACEFUL_STOP_DEADLINE:?}"
                );
                kept.insert(key, stage);
            }
            ChildStage::Connecting { child, .. } => {
                child.kill().ok();
                child.wait().ok();
            }
        }
    }
    session.children = kept;
    // Dropping the in-flight build tasks aborts them.
    session.builds.clear();

    if world.non_send::<PieSession>().children.is_empty() && current != PlayState::Stopped {
        world
            .resource_mut::<NextState<PlayState>>()
            .set(PlayState::Stopped);
        info!("PIE: Stop");
    }
}

/// Stop every instance now, without the graceful window. The reload
/// semantic is a rebuilt session: the old child is the wrong one the
/// moment the rebuild starts, so waiting for it to exit on its own buys
/// nothing. This is the pre-graceful-stop `handle_stop` behavior, kept
/// for exactly this caller.
fn force_stop_all(world: &mut World) {
    let current = world.resource::<State<PlayState>>().get().clone();

    broadcast_control(world, ControlEvent::Stop);

    let mut session = world.non_send_mut::<PieSession>();
    for (_key, mut stage) in session.children.drain() {
        match &mut stage {
            ChildStage::Connecting { child, .. } | ChildStage::Live { child, .. } => {
                child.kill().ok();
                child.wait().ok();
            }
        }
    }
    // Dropping the in-flight build tasks aborts them.
    session.builds.clear();

    if current != PlayState::Stopped {
        world
            .resource_mut::<NextState<PlayState>>()
            .set(PlayState::Stopped);
        info!("PIE: Stop (immediate; session being rebuilt)");
    }
}

/// Encode and send a single control message on the reliable channel to
/// one child's transport. An encode failure logs and skips.
fn send_control_to(transport: &mut IpcChannelTransport, event: ControlEvent) {
    let bytes = match to_bytes(&event) {
        Ok(bytes) => bytes,
        Err(err) => {
            error!("PIE: failed to encode {event:?}: {err}");
            return;
        }
    };
    transport.send(PieChannel::Reliable, &bytes);
}

/// Send a control message to every live child. Connecting children
/// (not yet holding a transport) are skipped.
fn broadcast_control(world: &mut World, event: ControlEvent) {
    let mut session = world.non_send_mut::<PieSession>();
    for stage in session.children.values_mut() {
        if let ChildStage::Live { transport, .. } = stage {
            send_control_to(transport, event.clone());
        }
    }
}

/// Send a control message (live edits, frame stream start/stop) only to the
/// focused instance's child transport. If no instance is focused, or the
/// focused child is not yet live, the message is dropped with a debug log.
/// Safe no-op when `PieInstances` or `PieSession` are absent (headless worlds).
pub(crate) fn send_control_to_focused(world: &mut World, event: ControlEvent) {
    let focused = world
        .get_resource::<PieInstances>()
        .and_then(|instances| instances.focused.clone());
    let Some(key) = focused else {
        debug!("PIE: control dropped. No focused instance.");
        return;
    };
    let Some(mut session) = world.get_non_send_mut::<PieSession>() else {
        debug!("PIE: control dropped. PieSession not present.");
        return;
    };
    if let Some(ChildStage::Live { transport, .. }) = session.children.get_mut(&key) {
        send_control_to(transport, event);
    } else {
        debug!("PIE: control dropped. Focused instance {key} is not live.");
    }
}

/// The focused instance's key, but only while its child process is connected
/// and live. `None` when nothing is focused, the child is still connecting,
/// or it has already been reaped.
pub(crate) fn focused_live_instance(world: &World) -> Option<InstanceKey> {
    let focused = world.get_resource::<PieInstances>()?.focused.clone()?;
    let session = world.get_non_send::<PieSession>()?;
    match session.children.get(&focused) {
        Some(ChildStage::Live { .. }) => Some(focused),
        _ => None,
    }
}

/// Whether the Live "Save to Scene" action can run right now: the inspector
/// is in Live mode and a preview entity is selected (either an authored
/// entity that maps back to an AST node, or an ephemeral runtime entity
/// that would be promoted to a new node).
pub(crate) fn can_save_live_to_scene(world: &World) -> bool {
    if *world.resource::<PieViewMode>() != PieViewMode::Live {
        return false;
    }
    let Some(preview) = world.resource::<crate::selection::Selection>().primary() else {
        return false;
    };
    // Only act on entities that are part of the current live projection.
    let in_projection = world
        .resource::<crate::pie_projection::PieProjection>()
        .by_bits
        .values()
        .any(|&e| e == preview);
    if !in_projection {
        return false;
    }
    // Ephemeral entities can be promoted to new authored nodes (Path B).
    if world
        .get::<crate::pie_projection::PieEphemeral>(preview)
        .is_some()
    {
        return true;
    }
    // Authored entities are saveable when the AST still holds their node (Path A).
    world
        .resource::<jackdaw_bsn::SceneBsnAst>()
        .ast_for(preview)
        .is_some()
}

/// Collect all non-skipped reflected components from `entity` as
/// `(type_path, BsnValue)` pairs, using the same filter that
/// `register_entity_in_ast` uses when it first captures a live entity.
///
/// Components with no `ReflectComponent` data, types not registered in the
/// `AppTypeRegistry`, and paths matched by [`should_skip_component`](crate::scene_io::should_skip_component) are
/// silently omitted. The result is sorted by type path for deterministic undo
/// batching.
fn preview_entity_components_as_bsn(
    world: &World,
    entity: Entity,
) -> Vec<(String, jackdaw_bsn::BsnValue)> {
    use bevy::ecs::reflect::AppTypeRegistry;

    let registry = world.resource::<AppTypeRegistry>().clone();
    let registry = registry.read();

    let Ok(entity_ref) = world.get_entity(entity) else {
        return Vec::new();
    };

    let skip_ids = crate::scene_io::doc_skip_type_ids();

    let mut out: Vec<(String, jackdaw_bsn::BsnValue)> = registry
        .iter()
        .filter(|reg| !skip_ids.contains(&reg.type_id()))
        .filter_map(|reg| {
            let type_path = reg.type_info().type_path_table().path();
            if crate::scene_io::should_skip_component(type_path) {
                return None;
            }
            let reflect_component = reg.data::<ReflectComponent>()?;
            let component = reflect_component.reflect(entity_ref)?;
            let value =
                jackdaw_bsn::BsnValue::from_reflect(component.as_partial_reflect(), &registry);
            Some((type_path.to_string(), value))
        })
        .collect();

    out.sort_by(|a, b| a.0.cmp(&b.0));
    out
}

/// Promote the selected preview entity's current component values into the
/// authored scene (Path A) or create a new authored node from it (Path B).
///
/// Path A: the preview entity is already bound to an AST node (it is an
/// authored entity with a live overlay). Each non-skipped reflected component
/// is read from the preview entity, serialized, and written into the node
/// through a [`SetBsnField`](crate::commands::SetBsnField) command. The commands are grouped into one
/// undoable [`CommandGroup`](jackdaw_commands::CommandGroup) so a single Ctrl+Z reverts the whole promote.
///
/// Path B: the preview entity carries [`PieEphemeral`](crate::pie_projection::PieEphemeral) (the game spawned it
/// at runtime with no authored counterpart). A new node is registered in the
/// live BSN document, its patches filled from the preview entity's
/// reflected components and bound to this entity. The entity
/// receives a [`SceneNodeId`](jackdaw_scene_types::SceneNodeId) component and loses [`PieEphemeral`](crate::pie_projection::PieEphemeral) so it is
/// now treated as an authored entity. Path B is not undoable in v1 (no
/// remove-node command exists that mirrors the insert).
///
/// No-op with a `warn!` when nothing is selected, the preview entity is gone,
/// or the entity carries neither a node binding nor `PieEphemeral`.
pub(crate) fn save_live_entity_to_scene(world: &mut World) {
    use crate::pie_projection::PieEphemeral;

    if *world.resource::<PieViewMode>() != PieViewMode::Live {
        return;
    }
    let Some(preview) = world.resource::<crate::selection::Selection>().primary() else {
        warn!("save to scene: no entity selected");
        return;
    };

    // Resolve the game-side bits for this preview entity from the projection map.
    let bits = world
        .resource::<crate::pie_projection::PieProjection>()
        .by_bits
        .iter()
        .find_map(|(&b, &e)| if e == preview { Some(b) } else { None });
    let Some(bits) = bits else {
        warn!("save to scene: selected entity {preview:?} has no live projection entry");
        return;
    };

    if world.get_entity(preview).is_err() {
        warn!("save to scene: preview entity for live {bits:x} no longer exists");
        return;
    }

    let is_ephemeral = world.get::<PieEphemeral>(preview).is_some();

    if is_ephemeral {
        promote_ephemeral_to_authored(world, preview, bits);
    } else {
        promote_authored_overlay(world, preview, bits);
    }
}

/// Path A: preview entity is bound to an existing AST node. Capture its
/// current component values and write them through `SetBsnField` commands.
fn promote_authored_overlay(world: &mut World, preview: Entity, bits: u64) {
    use crate::commands::{CommandGroup, CommandHistory, EditorCommand, SetBsnField};

    let node_id = {
        let ast = world.resource::<jackdaw_bsn::SceneBsnAst>();
        let Some(node) = ast.ast_for(preview) else {
            warn!("save to scene: preview entity {preview:?} (bits {bits:x}) has no AST node");
            return;
        };
        ast.stable_id_of(node).unwrap_or(0)
    };

    let entries = preview_entity_components_as_bsn(world, preview);

    let mut sub_commands: Vec<Box<dyn EditorCommand>> = Vec::new();
    for (type_path, new_value) in entries {
        let old_value = {
            let ast = world.resource::<jackdaw_bsn::SceneBsnAst>();
            ast.ast_for(preview)
                .and_then(|node| jackdaw_bsn::get_bsn_field(ast, node, &type_path, ""))
        };
        sub_commands.push(Box::new(SetBsnField {
            entity: preview,
            type_path,
            field_path: String::new(),
            old_value,
            new_value,
            was_derived: false,
        }));
    }

    let count = sub_commands.len();
    let mut cmd: Box<dyn EditorCommand> = if count == 0 {
        warn!("save to scene: preview entity {preview:?} had no saveable components");
        return;
    } else if count == 1 {
        match sub_commands.into_iter().next() {
            Some(only) => only,
            None => return,
        }
    } else {
        Box::new(CommandGroup {
            label: "Save runtime values to scene".to_string(),
            commands: sub_commands,
        })
    };
    cmd.execute(world);
    world.resource_mut::<CommandHistory>().push_executed(cmd);
    info!("save to scene: promoted runtime values into node {node_id}");
}

/// Path B: preview entity has no AST node (game-spawned runtime entity).
/// Mint a stable node id for it, drop the ephemeral marker, and register it
/// in the live BSN document, which captures its reflected components as a
/// new authored node — minus the runtime-only components
/// [`register_promoted_entity_in_ast`] filters out. Not undoable in v1.
pub(crate) fn promote_ephemeral_to_authored(world: &mut World, preview: Entity, bits: u64) {
    use crate::pie_projection::PieEphemeral;

    let node_id = jackdaw_scene_types::SceneNodeId::next();
    world.entity_mut(preview).remove::<PieEphemeral>();
    world.entity_mut(preview).insert(node_id);
    register_promoted_entity_in_ast(world, preview);

    info!(
        "save to scene: promoted ephemeral {preview:?} (bits {bits:x}) to new authored node {}",
        node_id.0
    );
}

/// Specific runtime-only physics paths a promoted entity may carry. These
/// are exact rather than module-prefix rules so adding an authored component
/// beside an Avian helper type cannot silently broaden the promote filter.
/// A path that no longer names anything skips nothing, as with the save
/// side's exact-path lists.
const PROMOTE_PER_FRAME_PATHS: &[&str] = &[
    // The physics-side mirror of `Transform`; the authored pose remains the
    // Bevy `Transform` and is captured normally. Avian's reflected type paths
    // include the `transform` module; the short re-export paths are retained
    // for registries that canonicalize the public re-export.
    "avian3d::physics_transform::Position",
    "avian3d::physics_transform::Rotation",
    "avian3d::physics_transform::PreSolveDeltaPosition",
    "avian3d::physics_transform::PreSolveDeltaRotation",
    "avian3d::physics_transform::transform::Position",
    "avian3d::physics_transform::transform::Rotation",
    "avian3d::physics_transform::transform::PreSolveDeltaPosition",
    "avian3d::physics_transform::transform::PreSolveDeltaRotation",
    // The integrator's per-timestep working set.
    "avian3d::dynamics::integrator::VelocityIntegrationData",
    // Broad-phase output recomputed from the collider every step, and its
    // margin-expanded twin the culling pass derives from it.
    "avian3d::collision::collider::ColliderAabb",
    "avian3d::collision::collider::EnlargedAabb",
    // The collider's physics-schedule pose, rewritten from `Transform`
    // every step (a distinct copy, not the authored one).
    "avian3d::collision::collider::collider_transform::ColliderTransform",
    // Velocity is the frame's reading, not a fact about the entity.
    "avian3d::dynamics::rigid_body::LinearVelocity",
    "avian3d::dynamics::rigid_body::AngularVelocity",
    // Sleep bookkeeping moves every step the body is awake.
    "avian3d::dynamics::rigid_body::sleeping::Sleeping",
    "avian3d::dynamics::rigid_body::sleeping::SleepTimer",
    // Per-step force accumulator the solver drains.
    "avian3d::dynamics::rigid_body::forces::AccumulatedLocalAcceleration",
    // Mass properties derived from the collider's shape at insert and
    // recomputed whenever it changes; a saved copy freezes one derivation
    // while the collider it came from is saved alongside it.
    "avian3d::dynamics::rigid_body::mass_properties::components::computed::ComputedMass",
    "avian3d::dynamics::rigid_body::mass_properties::components::computed::ComputedAngularInertia",
    "avian3d::dynamics::rigid_body::mass_properties::components::computed::ComputedCenterOfMass",
    "avian3d::dynamics::rigid_body::mass_properties::components::collider::ColliderMassProperties",
];

/// Relationship component paths whose Entity bits are session-local and
/// rebuilt by Avian's hierarchy relationship hooks. Keep this list
/// intentionally narrow: an unrelated game-authored component may also
/// contain Entity, and should not be filtered merely because its reflected
/// shape does. Type paths avoid adding Avian as a direct editor dependency;
/// the reflection check verifies these exact types still contain Entity.
const PROMOTE_SESSION_RELATIONSHIP_PATHS: &[&str] = &[
    "avian3d::collision::collider::collider_hierarchy::ColliderOf",
    "avian3d::collision::collider::collider_hierarchy::RigidBodyColliders",
];

fn is_promote_session_relationship(registration: &bevy::reflect::TypeRegistration) -> bool {
    let type_path = registration.type_info().type_path_table().path();
    PROMOTE_SESSION_RELATIONSHIP_PATHS.contains(&type_path)
        && type_tree_holds_entity(registration.type_info(), 0)
}

/// Whether a component a runtime entity wears must not land in the document
/// when it is promoted (LT10). Everything the save side skips stays skipped
/// ([`crate::scene_io::should_skip_component`]); on top of that, this
/// promote-only capture excludes two documented runtime classes:
///
/// 1. Avian's `ColliderOf` / `RigidBodyColliders` relationship pair. Their
///    reflected Entity references are current-world bits; Avian derives the
///    pair from the hierarchy when the session starts. The type-tree check
///    confirms the exact known relationship types still carry Entity.
/// 2. The per-frame physics internals above, identified by Avian type paths.
///
/// This does not blanket-skip every component with Entity in its type tree:
/// application components outside the Avian relationship pair retain the
/// shared save policy unless their own path is explicitly listed.
fn promote_capture_skips_component(registration: &bevy::reflect::TypeRegistration) -> bool {
    let type_path = registration.type_info().type_path_table().path();
    crate::scene_io::should_skip_component(type_path)
        || is_promote_session_relationship(registration)
        || PROMOTE_PER_FRAME_PATHS.contains(&type_path)
}

/// Whether the reflected fields of a type, or a direct item/key/value of a
/// reflected container, contain `bevy_ecs::entity::Entity`. Struct, tuple,
/// and enum fields recurse; List/Array/Set/Map metadata exposes only the
/// immediate container types, so those items are leaf-checked. This suffices
/// for Avian's `ColliderOf { body: Entity }` and
/// `RigidBodyColliders(Vec<Entity>)` shapes. Depth-capped for recursive fields.
fn type_tree_holds_entity(info: &'static bevy::reflect::TypeInfo, depth: usize) -> bool {
    if depth > 8 {
        return false;
    }
    // Entity itself, however its reflect shape projects (opaque or struct).
    if info.ty().is::<Entity>() {
        return true;
    }
    match info {
        bevy::reflect::TypeInfo::Struct(info) => info
            .iter()
            .any(|field| field_holds_entity(field.type_info(), depth)),
        bevy::reflect::TypeInfo::TupleStruct(info) => info
            .iter()
            .any(|field| field_holds_entity(field.type_info(), depth)),
        bevy::reflect::TypeInfo::Tuple(info) => info
            .iter()
            .any(|field| field_holds_entity(field.type_info(), depth)),
        // Container items are leaf-checked: a relationship target sits one
        // step in (`Vec<Entity>`, `HashMap<Name, Entity>`), not behind
        // further containers.
        bevy::reflect::TypeInfo::List(info) => info.item_ty().is::<Entity>(),
        bevy::reflect::TypeInfo::Array(info) => info.item_ty().is::<Entity>(),
        bevy::reflect::TypeInfo::Set(info) => info.value_ty().is::<Entity>(),
        bevy::reflect::TypeInfo::Map(info) => {
            info.key_ty().is::<Entity>() || info.value_ty().is::<Entity>()
        }
        bevy::reflect::TypeInfo::Enum(info) => info.iter().any(|variant| match variant {
            bevy::reflect::enums::VariantInfo::Struct(fields) => fields
                .iter()
                .any(|field| field_holds_entity(field.type_info(), depth)),
            bevy::reflect::enums::VariantInfo::Tuple(fields) => fields
                .iter()
                .any(|field| field_holds_entity(field.type_info(), depth)),
            bevy::reflect::enums::VariantInfo::Unit(_) => false,
        }),
        // Any other opaque leaf (a Vec3, a handle, a plain f32) is not a
        // reference into the session.
        bevy::reflect::TypeInfo::Opaque(_) => false,
    }
}

fn field_holds_entity(field: Option<&'static bevy::reflect::TypeInfo>, depth: usize) -> bool {
    field.is_some_and(|info| type_tree_holds_entity(info, depth + 1))
}

/// Register a just-promoted entity in the live scene document, mirroring
/// [`crate::scene_io::register_entity_in_ast`] (node creation, parent
/// linking, per-component patch upsert) with the promote capture filter:
/// [`promote_capture_skips_component`] decides what lands. The shared
/// registration stays untouched — it serves load and editor-side spawning,
/// whose entities never wear runtime physics state.
fn register_promoted_entity_in_ast(world: &mut World, entity: Entity) {
    use bevy::ecs::reflect::AppTypeRegistry;

    // Same guards as the shared registration: a dead entity has nothing to
    // read, and an entity already in the document is not re-registered.
    if world.get_entity(entity).is_err() {
        return;
    }
    let Some(doc) = world.get_resource::<jackdaw_bsn::SceneBsnAst>() else {
        return;
    };
    if doc.ast_for(entity).is_some() {
        return;
    }
    if world
        .get::<jackdaw_scene_types::SceneNodeId>(entity)
        .is_none()
        && let Ok(mut entity_mut) = world.get_entity_mut(entity)
    {
        entity_mut.insert(jackdaw_scene_types::SceneNodeId::next());
    }
    let doc = world.resource::<jackdaw_bsn::SceneBsnAst>();
    let parent = world
        .get::<ChildOf>(entity)
        .map(ChildOf::parent)
        .filter(|p| doc.ast_for(*p).is_some());
    jackdaw_bsn::create_entity_in_ast(world, entity, parent);

    let registry = world.resource::<AppTypeRegistry>().clone();
    let skip_ids = crate::scene_io::doc_skip_type_ids();
    let values: Vec<Box<dyn bevy::reflect::PartialReflect>> = {
        let reg = registry.read();
        let entity_ref = world.entity(entity);
        reg.iter()
            .filter(|registration| !skip_ids.contains(&registration.type_id()))
            .filter(|registration| !promote_capture_skips_component(registration))
            .filter_map(|registration| registration.data::<ReflectComponent>())
            .filter_map(|reflect_component| reflect_component.reflect(entity_ref))
            .filter_map(|value| value.to_dynamic().ok())
            .collect()
    };
    for value in values {
        crate::commands::sync_component_to_bsn_doc(world, entity, &*value);
    }
}

/// Drive every instance forward each frame: advance finished builds
/// into spawned children, move connecting children to live once they
/// accept, and reap exited children. Reconciles `PlayState` to match
/// whether any child is live.
fn advance_pie_session(world: &mut World) {
    poll_builds(world);
    poll_children(world);
    reconcile_play_state(world);
    reconcile_build_status(world);
}

/// One-shot flag so the background pre-build is attempted only once per editor
/// session, without re-running `cargo metadata` every frame.
#[derive(Resource, Default)]
pub struct PiePrebuildState {
    attempted: bool,
}

/// Turns the open-time pre-build off when set to `0`, `false` or empty.
pub const ENV_PIE_PREBUILD: &str = "JACKDAW_PIE_PREBUILD";

/// Whether [`ENV_PIE_PREBUILD`]'s value asks for the pre-build. Absent
/// means yes.
fn env_allows_prebuild(raw: Option<&str>) -> bool {
    !raw.is_some_and(|value| matches!(value.trim(), "" | "0" | "false"))
}

/// Whether this session should pre-build. The environment wins, so a
/// scripted or CI run can suppress it whatever the project remembers.
fn prebuild_wanted(world: &World) -> bool {
    env_allows_prebuild(
        std::env::var_os(ENV_PIE_PREBUILD)
            .and_then(|value| value.into_string().ok())
            .as_deref(),
    ) && world
        .get_resource::<EditorBuildSettings>()
        .is_none_or(|settings| settings.prebuild)
}

/// Pre-build the game in the background once the editor opens, so the
/// first Play reuses a warm artifact instead of compiling on demand.
/// Mirrors `launch_instance`'s build but with no pending spawn: it only
/// drives `PieSession.builds` to `Done`, which a later Play reuses
/// immediately. It builds what Play starts first — usually the default
/// binary, or the first run's cargo target when it names one.
fn prebuild_play_target(world: &mut World) {
    if world.resource::<PiePrebuildState>().attempted {
        return;
    }
    // Wait until the project's run configs have loaded.
    if world.get_resource::<RunConfigs>().is_none() {
        return;
    }
    // Pre-build the first run's target, so the first Play of that run
    // finds its own warm artifact.
    let first_run = world
        .get_resource::<RunConfigs>()
        .and_then(|runs| runs.manifest.runs.first().cloned());
    let first_target = first_run.as_ref().and_then(crate::run_config::cargo_target);
    // Run configs are loaded; this is the one-shot attempt regardless of outcome.
    world.resource_mut::<PiePrebuildState>().attempted = true;
    // A first run whose target cannot become a cargo command must not
    // burn a background build into a key no launch will ever consume —
    // launch refuses it at the door — so name the problem here instead,
    // where the build status shows it.
    if let Some(run) = &first_run
        && let Some(target) = &run.target
        && let Err(reason) = target.validate()
    {
        warn!("PIE: not pre-building '{}': {reason}", run.label());
        if let Some(mut status) = world.get_resource_mut::<BuildStatus>() {
            status.state = crate::build_status::BuildState::Blocked { reason };
        }
        return;
    }
    let Some(root) = project_root(world) else {
        return;
    };
    // Loading an extension built in an earlier session compiles nothing, so
    // it does not wait on the pre-build setting.
    if crate::extension_build::load_recorded_build(world, &root) {
        info!("PIE: loading the extension's last build, which is up to date");
        return;
    }
    if !prebuild_wanted(world) {
        info!("PIE: pre-build disabled; the first Play will compile the game");
        return;
    }
    if crate::extension_build::is_extension_project(world, &root, false) {
        info!("PIE: building the extension in the background to load it");
        crate::extension_build::start_extension_build(world, &root);
        return;
    }
    let build = (root.clone(), first_target);
    // A warm (or in-flight) entry under the first run's key needs no new
    // build, and no spec resolution either — which is why this check
    // comes first: nothing left to resolve means nothing to report.
    if world.non_send::<PieSession>().builds.contains_key(&build) {
        return; // already built or building (the user may have hit Play already)
    }
    let spec = match crate::project_build::shim_spec_for_project(&root) {
        Ok(spec) => spec,
        Err(error) => {
            // Without a resolvable package there is nothing to compile,
            // so the editor would otherwise open with an empty Add
            // Component list and no explanation anywhere.
            let reason = error.to_string();
            warn!("PIE: cannot build {}: {reason}", root.display());
            if let Some(mut status) = world.get_resource_mut::<BuildStatus>() {
                status.state = crate::build_status::BuildState::Blocked { reason };
            }
            return;
        }
    };
    // The same existence check the launch door applies: a target naming
    // a bin/example no package declares has nothing to warm.
    if let Some(target) = &build.1
        && let Err(reason) = preflight_run_target(&root, &spec.package_name, target)
    {
        warn!("PIE: not pre-building: {reason}");
        if let Some(mut status) = world.get_resource_mut::<BuildStatus>() {
            status.state = crate::build_status::BuildState::Blocked { reason };
        }
        return;
    }
    let mut session = world.non_send_mut::<PieSession>();
    info!("PIE: pre-building the game in the background for a fast first Play");
    let (task, progress) = spawn_game_build(&root, spec, build.1.clone(), BuildLoad::Background);
    session.builds.insert(
        build,
        BuildState::Running {
            task,
            pending: Vec::new(),
            progress,
        },
    );
}

/// Throttle so the edit-mode source scan runs about once a second
/// rather than every frame.
#[derive(Resource)]
struct EditRebuildThrottle(Timer);

impl Default for EditRebuildThrottle {
    fn default() -> Self {
        Self(Timer::from_seconds(1.0, TimerMode::Repeating))
    }
}

/// Editor-wide project build preferences.
///
/// Kept at the top level of the project's settings file, where they were
/// written before the file grew other sections; see
/// [`crate::project_settings`].
#[derive(Resource, serde::Serialize, serde::Deserialize)]
#[serde(default)]
pub(crate) struct EditorBuildSettings {
    /// When true, the editor rebuilds the project automatically on source
    /// change. Opt-in and off by default: otherwise a rebuild fires
    /// behind the user's back and competes with a `cargo build` they may
    /// have started themselves. When off, rebuilds come from the Rebuild
    /// action or an out-of-editor `jackdaw build`.
    pub(crate) auto_build: bool,
    /// When true, the editor compiles the game once in the background as
    /// the project opens, so the first Play is instant. On by default.
    pub(crate) prebuild: bool,
    /// What Play does with unsaved scene changes before starting the game:
    /// save them, ask first, or play a temporary copy. `save` by default;
    /// a pre-enum settings file's bool reads back as `true` = save and
    /// `false` = play a copy.
    pub(crate) save_before_play: SaveBeforePlay,
}

impl Default for EditorBuildSettings {
    fn default() -> Self {
        Self {
            auto_build: false,
            prebuild: true,
            save_before_play: SaveBeforePlay::default(),
        }
    }
}

fn sync_project_build_settings(
    project: Option<Res<crate::project::ProjectRoot>>,
    mut settings: ResMut<EditorBuildSettings>,
    mut loaded_root: Local<Option<PathBuf>>,
) {
    let Some(project) = project else {
        return;
    };
    if loaded_root.as_ref() == Some(&project.root) {
        return;
    }
    *loaded_root = Some(project.root.clone());
    *settings = crate::project_settings::load_section(
        &project.root,
        crate::project_settings::Section::TopLevel,
    );
}

pub(crate) fn persist_project_build_settings(world: &World) {
    let (Some(project), Some(settings)) = (
        world.get_resource::<crate::project::ProjectRoot>(),
        world.get_resource::<EditorBuildSettings>(),
    ) else {
        return;
    };
    crate::project_settings::store_section(
        &project.root,
        crate::project_settings::Section::TopLevel,
        settings,
    );
}

/// Start a game build for `root` unless one is already in flight.
/// Shared by the source watcher (auto-build) and the manual Rebuild
/// operator. The finished build persists `.jackdaw/schema.json`, which
/// [`watch_project_schema`] picks up to refresh the editor's types.
/// Rebuild means the default artifact; a run-specific target builds
/// when that run launches.
fn spawn_project_build(world: &mut World, root: &Path, load: BuildLoad) {
    let build = (root.to_path_buf(), None);
    if matches!(
        world.non_send::<PieSession>().builds.get(&build),
        Some(BuildState::Running { .. })
    ) {
        return;
    }
    let Some(spec) = crate::project_build::shim_spec_for_project(root).ok() else {
        return;
    };
    info!("PIE: building the game");
    let (task, progress) = spawn_game_build(root, spec, None, load);
    world.non_send_mut::<PieSession>().builds.insert(
        build,
        BuildState::Running {
            task,
            pending: Vec::new(),
            progress,
        },
    );
}

/// While editing (not playing) and only when auto-build is enabled,
/// rebuild the game when its source changes so a newly added or
/// edited component appears in the editor without a restart. The
/// completed build persists the schema, which `watch_project_schema`
/// loads. Off by default; the manual Rebuild action is the normal path.
fn watch_project_source_for_edit(world: &mut World) {
    if *world.resource::<State<PlayState>>().get() != PlayState::Stopped {
        return;
    }
    if !world.resource::<EditorBuildSettings>().auto_build {
        return;
    }
    {
        let delta = world.resource::<Time>().delta();
        let mut throttle = world.get_resource_or_insert_with(EditRebuildThrottle::default);
        if !throttle.0.tick(delta).just_finished() {
            return;
        }
    }
    let Some(root) = project_root(world) else {
        return;
    };
    if crate::extension_build::is_extension_project(world, &root, false) {
        // Measured from when the build finished, not from the library's
        // mtime: a change that compiles to nothing new leaves the library
        // untouched and would otherwise rebuild on every tick.
        let finished = world
            .get_resource::<crate::extension_build::ExtensionBuild>()
            .and_then(crate::extension_build::ExtensionBuild::finished_at);
        if let Some(finished) = finished
            && !source_unchanged_since(&root, finished)
        {
            crate::extension_build::start_extension_build(world, &root);
        }
        return;
    }
    // Only rebuild once the project has been built and loaded at least
    // once; the initial build is driven by `prebuild_play_target`.
    let built_path = match world
        .non_send::<PieSession>()
        .builds
        .get(&(root.clone(), None))
    {
        Some(BuildState::Done(path)) => path.clone(),
        _ => return,
    };
    if source_is_current(&root, &built_path) {
        return;
    }
    spawn_project_build(world, &root, BuildLoad::Background);
}

/// Throttle for the schema-file poll so it stats the file about twice a
/// second rather than every frame.
#[derive(Resource)]
struct ProjectSchemaWatch {
    last_mtime: Option<std::time::SystemTime>,
    throttle: Timer,
}

impl Default for ProjectSchemaWatch {
    fn default() -> Self {
        Self {
            last_mtime: None,
            throttle: Timer::from_seconds(0.5, TimerMode::Repeating),
        }
    }
}

/// Refresh the editor's known project component types from
/// `<project>/.jackdaw/schema.json` whenever that file changes. This is
/// the single pickup path for project types: the editor's own build and
/// an out-of-editor `jackdaw build` both write the file, and only this
/// system reads it into `ProjectTypes`. On editor start it also loads a
/// schema left by a previous session, so components are known before any
/// rebuild.
/// Read `<project>/.jackdaw/schema.json` into `ProjectTypes` and publish
/// the document-only set, returning the component count when the file was
/// newer than the last read. `None` means nothing changed and callers
/// should not re-announce.
pub fn refresh_project_types(world: &mut World) -> Option<usize> {
    let root = world
        .get_resource::<crate::project::ProjectRoot>()
        .map(|p| p.root.clone())?;
    let jackdaw_dir = root.join(".jackdaw");
    let path = jackdaw_schema::schema_path(&jackdaw_dir);
    let mtime = std::fs::metadata(&path).and_then(|m| m.modified()).ok()?;
    if world
        .get_resource::<ProjectSchemaWatch>()
        .is_some_and(|watch| watch.last_mtime == Some(mtime))
    {
        return None;
    }
    let schema = jackdaw_schema::read_schema(&jackdaw_dir)?;
    let native =
        crate::project_types::native_type_paths(&world.resource::<AppTypeRegistry>().read());
    let component_count = {
        let mut project_types = world.resource_mut::<crate::project_types::ProjectTypes>();
        project_types.update(&schema, &native);
        project_types.components().count()
    };
    crate::project_types::publish_document_only_types(world);
    crate::project_definitions::register_project_definitions(world);
    if let Some(mut watch) = world.get_resource_mut::<ProjectSchemaWatch>() {
        watch.last_mtime = Some(mtime);
    }
    Some(component_count)
}

fn watch_project_schema(world: &mut World) {
    {
        let delta = world.resource::<Time>().delta();
        let mut watch = world.resource_mut::<ProjectSchemaWatch>();
        if !watch.throttle.tick(delta).just_finished() {
            return;
        }
    }
    let Some(component_count) = refresh_project_types(world) else {
        return;
    };

    // Surface the outcome in the footer so the user knows the build
    // finished and how many of their components loaded.
    world
        .resource_mut::<crate::build_status::BuildStatus>()
        .state = crate::build_status::BuildState::Ready {
        at: Instant::now(),
        components: component_count,
    };

    // Repaint the open inspector: a shape change (a field added, removed,
    // or retyped in game code) must show without a reselect.
    let selected: Vec<Entity> = world
        .resource::<crate::selection::Selection>()
        .entities
        .clone();
    for entity in selected {
        if let Ok(mut ec) = world.get_entity_mut(entity) {
            ec.insert(crate::inspector::InspectorDirty);
        }
    }
    info!("PIE: refreshed project types from schema ({component_count} project components)");
}

/// Mirror the active game or extension build into the editor's
/// `BuildStatus` so the footer shows what is compiling, and clear it once
/// no build remains. Also carries the export entry's build, which shares
/// the footer rather than growing a second progress surface.
pub(crate) fn reconcile_build_status(world: &mut World) {
    let building = world
        .non_send::<PieSession>()
        .builds
        .values()
        .find_map(|build| match build {
            BuildState::Running { progress, .. } => Some(Arc::clone(progress)),
            _ => None,
        })
        .or_else(|| {
            world
                .get_resource::<crate::game_export::GameExports>()
                .and_then(crate::game_export::GameExports::progress)
        })
        .or_else(|| {
            world
                .get_resource::<crate::extension_build::ExtensionBuild>()
                .and_then(crate::extension_build::ExtensionBuild::progress)
        });
    let project = world
        .get_resource::<crate::project::ProjectRoot>()
        .map(|p| p.root.clone())
        .unwrap_or_default();
    let Some(mut status) = world.get_resource_mut::<BuildStatus>() else {
        return;
    };
    match building {
        Some(progress) => {
            status.outcome = None;
            status.failed_log = None;
            status.state = crate::build_status::BuildState::Building {
                project,
                started: Instant::now(),
                progress,
            };
        }
        None => match &status.state {
            // A build ended with no outcome latched yet: go Idle.
            // `poll_builds` (Failed) and `watch_project_schema` (Ready)
            // set the real outcome the same or next frame.
            crate::build_status::BuildState::Building { .. } => {
                status.state = crate::build_status::BuildState::Idle;
            }
            // Keep a recent success on screen, then let it fade to Idle.
            crate::build_status::BuildState::Ready { at, .. } => {
                if at.elapsed() > Duration::from_secs(6) {
                    status.state = crate::build_status::BuildState::Idle;
                }
            }
            // Sticky: a failure stays until the next build starts, and only
            // the user fixing their project clears a block.
            crate::build_status::BuildState::Failed { .. }
            | crate::build_status::BuildState::Blocked { .. }
            | crate::build_status::BuildState::Idle => {}
        },
    }
}

/// Poll each in-flight build. On success, spawn its pending instances
/// and mark the build `Done`; on failure mark it `Failed` and drop
/// pending instances. The builds map is taken with `mem::take` before
/// spawning so `spawn_instance` can read the world without aliasing.
fn poll_builds(world: &mut World) {
    let mut builds = std::mem::take(&mut world.non_send_mut::<PieSession>().builds);
    let mut spawned: Vec<(InstanceKey, ChildStage)> = Vec::new();

    for (key, state) in builds.iter_mut() {
        let BuildState::Running {
            task,
            pending,
            progress,
        } = state
        else {
            continue;
        };
        match future::block_on(future::poll_once(task)) {
            None => {}
            Some(Ok(result)) => {
                // The build persisted the project's type schema to
                // `.jackdaw/schema.json`; `watch_project_schema` picks it
                // up and refreshes `ProjectTypes`. Pickup is deliberately
                // decoupled from building so an out-of-editor `jackdaw
                // build` flows through the same path. The editor never
                // links or loads project code; it reads the schema the
                // game reported about itself, and Play runs that same
                // binary in a fresh process below.
                for spawn in pending.drain(..) {
                    if let Some(stage) = spawn_instance(
                        world,
                        &spawn.key,
                        &spawn.run,
                        &result.binary,
                        spawn.scene_override.as_ref(),
                    ) {
                        record_scene_override(world, &spawn.key, spawn.scene_override.as_ref());
                        spawned.push((spawn.key, stage));
                    }
                }
                *state = BuildState::Done(result.binary);
            }
            Some(Err(err)) => {
                let output = progress.lock().ok().map(|p| p.full_log.clone());
                let project = key.0.file_name().map_or_else(
                    || key.0.display().to_string(),
                    |name| name.display().to_string(),
                );
                let keys: Vec<String> = pending.iter().map(|p| p.key.to_string()).collect();
                if keys.is_empty() {
                    error!("PIE: game build of {project} failed: {err}");
                } else {
                    error!(
                        "PIE: game build of {project} failed, not launching {}: {err}",
                        keys.join(", ")
                    );
                }
                *state = BuildState::Failed {
                    launch: !pending.is_empty(),
                };
                {
                    let mut status = world.resource_mut::<crate::build_status::BuildStatus>();
                    status.state = crate::build_status::BuildState::Failed { at: Instant::now() };
                    status.outcome = Some(err.to_string());
                    status.failed_log = output;
                }
                crate::status_bar::notify_error(world, err.to_string());
            }
        }
    }

    let mut session = world.non_send_mut::<PieSession>();
    session.builds = builds;
    for (key, stage) in spawned {
        session.launches += 1;
        session.children.insert(key, stage);
    }
}

/// Poll each launched child. Connecting children that accept become
/// live; ones that fail or time out are reaped. Live children that
/// exit are reaped. The children map is taken with `mem::take` and
/// rebuilt from survivors, moving each `Child` by value.
fn poll_children(world: &mut World) {
    let children = std::mem::take(&mut world.non_send_mut::<PieSession>().children);

    let mut survivors: HashMap<InstanceKey, ChildStage> = HashMap::with_capacity(children.len());
    for (key, stage) in children {
        if let Some(next) = advance_child(&key, stage) {
            survivors.insert(key, next);
        }
    }

    world.non_send_mut::<PieSession>().children = survivors;
}

/// Step one child's stage by value, returning the stage it should
/// carry into next frame, or `None` if it should be dropped. A
/// connected `Connecting` becomes `Live`; a child that failed to
/// connect or has exited is reaped and dropped.
fn advance_child(key: &InstanceKey, stage: ChildStage) -> Option<ChildStage> {
    match stage {
        ChildStage::Connecting {
            mut child,
            mut accept,
            stderr_tail,
            since,
        } => {
            // A child that died before connecting will never accept;
            // reap it immediately and surface the crash.
            match child.try_wait() {
                Ok(Some(status)) => {
                    error!("PIE: {key} exited before connecting with {status}");
                    report_stderr_tail(&stderr_tail);
                    return None;
                }
                Ok(None) => {}
                Err(err) => {
                    error!("PIE: {key} failed to poll while connecting: {err}");
                    child.kill().ok();
                    child.wait().ok();
                    return None;
                }
            }
            match future::block_on(future::poll_once(&mut accept)) {
                None => {
                    if since.elapsed() >= CONNECT_TIMEOUT {
                        error!(
                            "PIE: {key} did not connect within {}s; is the jackdaw_runtime/pie feature enabled for this bin?",
                            CONNECT_TIMEOUT.as_secs()
                        );
                        child.kill().ok();
                        child.wait().ok();
                        report_stderr_tail(&stderr_tail);
                        None
                    } else {
                        Some(ChildStage::Connecting {
                            child,
                            accept,
                            stderr_tail,
                            since,
                        })
                    }
                }
                Some(Ok(transport)) => {
                    info!("PIE: {key} connected");
                    Some(ChildStage::Live {
                        child,
                        transport,
                        stderr_tail,
                        stop_deadline: None,
                    })
                }
                Some(Err(err)) => {
                    error!("PIE: {key} failed to connect: {err}");
                    child.kill().ok();
                    child.wait().ok();
                    report_stderr_tail(&stderr_tail);
                    None
                }
            }
        }
        ChildStage::Live {
            mut child,
            transport,
            stderr_tail,
            stop_deadline,
        } => match child.try_wait() {
            Ok(None) => {
                // Still running. Inside the graceful window that is the
                // point — it was asked to stop and has until the deadline
                // to flush and exit on its own; past the deadline it is
                // killed, exactly once, and reaped here (the stage drops
                // with this call, so no later tick can kill it again).
                if stop_deadline.is_some_and(|deadline| Instant::now() >= deadline) {
                    warn!("PIE: {key} did not exit within the graceful window; killing it");
                    child.kill().ok();
                    child.wait().ok();
                    None
                } else {
                    Some(ChildStage::Live {
                        child,
                        transport,
                        stderr_tail,
                        stop_deadline,
                    })
                }
            }
            Ok(Some(status)) => {
                if status.success() {
                    info!("PIE: {key} exited");
                } else {
                    error!("PIE: {key} exited with {status}");
                    report_stderr_tail(&stderr_tail);
                }
                None
            }
            Err(err) => {
                error!("PIE: {key} failed to poll: {err}");
                None
            }
        },
    }
}

/// Reconcile `PlayState` with live children: any live child implies
/// `Playing` (unless already `Paused`); zero children implies `Stopped`.
fn reconcile_play_state(world: &mut World) {
    let session = world.non_send::<PieSession>();
    // A live child implies playing; a child still connecting does not:
    // counting one there would open the stop gate into the connect window,
    // and the stop-that-kills-a-connecting-child path spins the main
    // thread (reproduced 100%: stop inside the window freezes the editor
    // at full CPU, stop after connect does not; the deep cause is its own
    // investigation). The gate staying closed means a stop fired into the
    // window comes back cancelled — callers retry, which the QA recipes
    // already do.
    let any_live = session
        .children
        .values()
        .any(|stage| matches!(stage, ChildStage::Live { .. }));
    let child_count = session.children.len();
    let current = world.resource::<State<PlayState>>().get().clone();

    if any_live && !matches!(current, PlayState::Playing | PlayState::Paused) {
        world
            .resource_mut::<NextState<PlayState>>()
            .set(PlayState::Playing);
    } else if child_count == 0 && current != PlayState::Stopped {
        world
            .resource_mut::<NextState<PlayState>>()
            .set(PlayState::Stopped);
    }
}

#[cfg(target_os = "windows")]
mod pie_windows {
    use std::{
        os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle},
        process::Child,
        sync::LazyLock,
    };
    use windows_sys::Win32::Foundation::GetLastError;
    use windows_sys::Win32::System::JobObjects::*;

    /// The kill-on-close job every launched game is assigned to. `None`
    /// when the kernel would not give us one (a sandboxed or app-container
    /// editor, some CI runners): launches still work there, with the
    /// degradation that a killed editor can leave its games running.
    pub static PIE_JOB: LazyLock<Option<Job>> = LazyLock::new(|| unsafe {
        let job = CreateJobObjectW(std::ptr::null(), std::ptr::null());
        if job.is_null() {
            let err = GetLastError();
            bevy::log::warn!(
                "PIE: cannot create the kill-on-close job object (os error {err}); \
                 a killed editor will leave its games running"
            );
            return None;
        }
        let handle = OwnedHandle::from_raw_handle(job);

        let info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
            BasicLimitInformation: JOBOBJECT_BASIC_LIMIT_INFORMATION {
                LimitFlags: JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
                    | JOB_OBJECT_LIMIT_BREAKAWAY_OK
                    | JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK,
                ..Default::default()
            },
            ..Default::default()
        };

        let set = SetInformationJobObject(
            handle.as_raw_handle(),
            JobObjectExtendedLimitInformation,
            (&raw const info).cast(),
            std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
        );
        if set == 0 {
            let err = GetLastError();
            bevy::log::warn!(
                "PIE: cannot arm the kill-on-close job object (os error {err}); \
                 a killed editor will leave its games running"
            );
            return None;
        }

        Some(Job(handle))
    });

    pub struct Job(pub OwnedHandle);

    impl Job {
        /// Assign the process to the job, logging and continuing when the
        /// kernel refuses (nested jobs, restricted tokens): the game runs
        /// either way, only without the dies-with-the-editor guarantee.
        pub fn assign_to_process(&self, process: &Child) {
            let assigned = unsafe {
                AssignProcessToJobObject(self.0.as_raw_handle(), process.as_raw_handle())
            };
            if assigned == 0 {
                // SAFETY: `GetLastError` reads the calling thread's last
                // error slot immediately after the failed call above on
                // this same thread, which is exactly its contract.
                let err = unsafe { GetLastError() };
                bevy::log::warn!(
                    "PIE: cannot assign the game to the kill-on-close job object \
                     (os error {err}); it will not die with the editor"
                );
            }
        }
    }
}

/// The env a Play launch hands the game: the asset-root default it needs
/// when nothing names one, then the run's own env — so a run that sets
/// `BEVY_ASSET_ROOT` itself wins over the default, the same
/// user-env-wins order the CLI's `jd run --config` launch applies.
fn apply_run_env(
    command: &mut Command,
    cwd: &Path,
    env: &std::collections::BTreeMap<String, String>,
) {
    command.env("BEVY_ASSET_ROOT", cwd).envs(env);
}

/// Launch the project's game binary for one instance, point it at a
/// fresh rendezvous, start draining its stderr, and begin awaiting its
/// connection on a task pool. Returns the `Connecting` stage; on
/// rendezvous or spawn failure logs and returns `None` so the caller
/// skips it. A `scene_override` additionally points the child at the
/// editor's scene through `JACKDAW_PIE_SCENE`.
fn spawn_instance(
    world: &World,
    key: &InstanceKey,
    run: &RunConfig,
    binary: &Path,
    scene_override: Option<&SceneOverrideLaunch>,
) -> Option<ChildStage> {
    let root = project_root(world)?;

    let (handle, server_name) = match serve() {
        Ok(pair) => pair,
        Err(err) => {
            error!("PIE: {key} failed to open ipc rendezvous: {err}");
            return None;
        }
    };

    // A relative `cwd` is joined against the project root; an absolute
    // path replaces it (standard `Path::join` semantics). Assets
    // resolve from here, exactly as for a directly-run game binary.
    let cwd = match run.cwd.as_ref() {
        Some(dir) => root.join(dir),
        None => root.clone(),
    };

    let mut command = Command::new(binary);
    crate::project_build::prepare_game_command(&mut command, binary);
    command.current_dir(&cwd);
    apply_run_env(&mut command, &cwd, &run.env);
    command
        .env("JACKDAW_PIE", &server_name)
        .args(&run.args)
        .stderr(Stdio::piped());
    if let Some(scene_override) = scene_override {
        command.env(
            jackdaw_runtime::PIE_SCENE_ENV,
            &scene_override.assets_relative,
        );
    }

    if let Some(settings) = world.get_resource::<crate::play_settings::PlaySettings>() {
        command.envs(&settings.env).args(&settings.args);
    }

    if world
        .get_resource::<PieWindowMode>()
        .copied()
        .map(wants_windowless_env)
        .unwrap_or(true)
    {
        command.env("JACKDAW_PIE_WINDOWLESS", "1");
    }

    // Ask the kernel to SIGKILL this child when the editor (its parent) dies by
    // any means -- including a SIGKILL the editor can never trap, which skips
    // `Drop`. Without this, killing the editor leaves the games running.
    #[cfg(target_os = "linux")]
    {
        use std::os::unix::process::CommandExt;

        // `libc::prctl` is C-variadic; the workspace linter cannot analyze
        // variadic calls, and `PR_SET_PDEATHSIG` only ever takes one
        // argument, so declare that fixed-arity signature for the same
        // symbol.
        unsafe extern "C" {
            fn prctl(option: libc::c_int, arg2: libc::c_ulong) -> libc::c_int;
        }

        // SAFETY: the closure runs in the forked child before `exec`; `prctl`,
        // `getppid`, and `raise` are all async-signal-safe.
        unsafe {
            command.pre_exec(|| {
                if prctl(libc::PR_SET_PDEATHSIG, libc::SIGKILL as libc::c_ulong) == -1 {
                    return Err(std::io::Error::last_os_error());
                }
                // The editor may have already died in the window between fork
                // and the prctl above; the death signal would never arrive, so
                // exit now rather than be orphaned.
                if libc::getppid() == 1 {
                    libc::raise(libc::SIGKILL);
                }
                Ok(())
            });
        }
    }

    let spawn = command.spawn();

    let mut child = match spawn {
        Ok(child) => child,
        Err(err) => {
            error!("PIE: {key} failed to launch ({}): {err}", binary.display());
            return None;
        }
    };

    // On Windows, we use a job object with JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE set.
    // Because we own the only handle to the object, if Jackdaw crashes, the job object will be closed and the game killed.
    #[cfg(target_os = "windows")]
    if let Some(job) = pie_windows::PIE_JOB.as_ref() {
        job.assign_to_process(&child);
    }

    let stderr_tail: StderrTail = Arc::new(Mutex::new(VecDeque::with_capacity(STDERR_TAIL_LINES)));
    if let Some(stderr) = child.stderr.take() {
        let tail = Arc::clone(&stderr_tail);
        std::thread::spawn(move || {
            for line in BufReader::new(stderr).lines().map_while(Result::ok) {
                if let Ok(mut buf) = tail.lock() {
                    if buf.len() == STDERR_TAIL_LINES {
                        buf.pop_front();
                    }
                    buf.push_back(line);
                }
            }
        });
    }

    let accept = AsyncComputeTaskPool::get().spawn(async move { handle.accept() });

    info!("PIE: {key} launched, awaiting connection");
    Some(ChildStage::Connecting {
        child,
        accept,
        stderr_tail,
        since: Instant::now(),
    })
}

/// Log the buffered stderr tail as an error, for diagnosing a crashed
/// or unconnectable game.
fn report_stderr_tail(stderr_tail: &StderrTail) {
    if let Ok(buf) = stderr_tail.lock()
        && !buf.is_empty()
    {
        let tail: Vec<&str> = buf.iter().map(String::as_str).collect();
        error!("PIE: game stderr tail:\n{}", tail.join("\n"));
    }
}

/// Apply a game pick answer: resolve the bits through the projection and
/// select the preview entity. Stale or unstreamed hits resolve to nothing
/// and are dropped.
pub(crate) fn handle_pick_result(world: &mut World, bits: Option<u64>) {
    let Some(bits) = bits else {
        return;
    };
    let Some(&preview) = world
        .resource::<crate::pie_projection::PieProjection>()
        .by_bits
        .get(&bits)
    else {
        return;
    };
    if world.get_entity(preview).is_err() {
        return;
    }
    let old_entities: Vec<Entity> = world
        .resource::<crate::selection::Selection>()
        .entities
        .clone();
    {
        let mut selection = world.resource_mut::<crate::selection::Selection>();
        selection.entities.clear();
        selection.entities.push(preview);
    }
    for e in old_entities {
        if e != preview
            && let Ok(mut entity_mut) = world.get_entity_mut(e)
        {
            entity_mut.remove::<crate::selection::Selected>();
        }
    }
    if let Ok(mut entity_mut) = world.get_entity_mut(preview) {
        entity_mut.insert(crate::selection::Selected);
    }
}

/// Drain `StateEvent`s from every live child. Events for every instance are
/// always accumulated into that instance's [`InstanceBuffer`](crate::pie_mirror::InstanceBuffer) regardless of
/// view mode, so the buffers always hold current game state and a Scene->Live
/// toggle re-projects fresh data. Additionally, events from the focused instance
/// are projected into the preview ECS via `project_event`, but only in Live mode.
fn drain_game_events(world: &mut World) {
    // Collect all pending (key, events) pairs without holding the session borrow.
    let mut per_instance: Vec<(InstanceKey, Vec<StateEvent>)> = Vec::new();
    let mut pixel_frames: Vec<(InstanceKey, Vec<u8>)> = Vec::new();

    {
        let mut session = world.non_send_mut::<PieSession>();
        for (key, stage) in session.children.iter_mut() {
            let ChildStage::Live { transport, .. } = stage else {
                continue;
            };
            let frames = transport.drain_received();
            if frames.is_empty() {
                continue;
            }
            let mut events: Vec<StateEvent> = Vec::with_capacity(frames.len());
            for (channel, bytes) in frames {
                if channel == PieChannel::Frames {
                    // Binary pixel payload routed to the live frame intake below,
                    // after the focused instance is known.
                    pixel_frames.push((key.clone(), bytes));
                    continue;
                }
                match from_bytes::<StateEvent>(&bytes) {
                    Ok(event) => events.push(event),
                    Err(err) => warn!("PIE: {key} dropping malformed state event: {err}"),
                }
            }
            if !events.is_empty() {
                per_instance.push((key.clone(), events));
            }
        }
    }

    for (key, events) in per_instance {
        let count = events.len();

        // Read focused before any mutable borrow so borrowck is satisfied.
        let focused = world.resource::<PieInstances>().focused.clone();

        // Establish focus on the first instance seen, regardless of view mode.
        let focused = if focused.is_none() {
            world.resource_mut::<PieInstances>().focused = Some(key.clone());
            // First streamed data: content exists to show, so auto-enter Live.
            // `reset_view_mode_on_stop` owns the revert when play stops.
            if *world.resource::<crate::pie_mirror::PieViewMode>()
                == crate::pie_mirror::PieViewMode::Scene
            {
                enter_live_view(world);
            }
            Some(key.clone())
        } else {
            focused
        };

        let is_focused = focused.as_ref() == Some(&key);

        // Read after the auto-enter above so the first batch projects in the
        // same drain it arrives.
        let live_mode = *world.resource::<crate::pie_mirror::PieViewMode>()
            == crate::pie_mirror::PieViewMode::Live;

        for event in events {
            // Mirror the focused game's cursor grab onto the editor before any
            // buffering or projection; the cursor state is not scene data.
            if let StateEvent::CursorState { grabbed, visible } = &event {
                if is_focused {
                    crate::live_input::note_game_cursor_state(world, *grabbed, *visible);
                }
                continue;
            }

            // A pick answer resolves to a preview entity selection; it is not
            // scene data, so it never reaches the buffer or the projector.
            if let StateEvent::PickResult { entity } = &event {
                if is_focused {
                    handle_pick_result(world, *entity);
                }
                continue;
            }

            // A log line from the focused game lands in the Game panel's
            // recent-log face; it is not scene data either.
            if let StateEvent::Log { level, message } = &event {
                if is_focused {
                    world
                        .resource_mut::<crate::pie_game_log::PieGameLog>()
                        .push(level.clone(), message.clone());
                }
                continue;
            }

            // Always accumulate into the per-instance buffer.
            world
                .resource_mut::<PieInstances>()
                .buffers
                .entry(key.clone())
                .or_default()
                .apply(&event);

            // Project into the preview world only for the focused instance in Live mode.
            if live_mode && is_focused {
                crate::pie_projection::project_event(world, event);
            }
        }

        debug!("PIE: {key} received {count} state event(s)");
    }

    // Upload the newest pixel frame from the focused instance; earlier frames
    // in the same drain are superseded, and frames from unfocused instances
    // (or arriving before any focus exists) are dropped.
    let focused = world.resource::<PieInstances>().focused.clone();
    if let Some(focused) = focused
        && let Some((_, bytes)) = pixel_frames.iter().rev().find(|(key, _)| *key == focused)
    {
        match jackdaw_pie_protocol::decode_frame(bytes) {
            Some(frame) => world.resource_scope(
                |world, mut stream: Mut<crate::live_frame::LiveFrameStream>| {
                    let mut images = world.resource_mut::<Assets<Image>>();
                    crate::live_frame::apply_frame(&mut stream, &mut images, frame);
                },
            ),
            None => warn!("PIE: dropping malformed pixel frame"),
        }
    }
}

#[cfg(test)]
mod play_status_tests {
    use super::*;

    #[test]
    fn a_launch_whose_build_failed_reads_as_failed() {
        let mut world = World::new();
        world.init_resource::<State<PlayState>>();
        let mut session = PieSession::default();
        session.builds.insert(
            (PathBuf::from("project"), None),
            BuildState::Failed { launch: true },
        );
        world.insert_non_send(session);
        assert_eq!(play_status(&world), "failed");
    }

    #[test]
    fn a_background_build_that_failed_leaves_the_editor_stopped() {
        let mut world = World::new();
        world.init_resource::<State<PlayState>>();
        let mut session = PieSession::default();
        session.builds.insert(
            (PathBuf::from("project"), None),
            BuildState::Failed { launch: false },
        );
        world.insert_non_send(session);
        assert_eq!(play_status(&world), "stopped");
    }
}

#[cfg(test)]
mod save_before_launch_tests {
    use super::*;

    /// The open animation graph is authored state the game reads: a
    /// dirty graph at launch time saves on the same chain (review item
    /// 1 of the T08-T3 closeout). Driven with a dirty doc that has no
    /// path — the write refuses, the launch refuses with it.
    #[test]
    fn a_dirty_animation_graph_the_chain_cannot_save_refuses_the_launch() {
        let mut world = World::new();
        world.init_resource::<crate::scenes::Scenes>();
        world.init_resource::<crate::asset_index::AssetIndex>();
        let mut doc = crate::animation::AnimationGraphDoc::default();
        doc.path = None;
        doc.dirty = true;
        world.insert_resource(doc);

        let outcome = save_scenes_before_launch(&mut world, "playing");
        let message = outcome.expect_err("a graph with no file to write blocks the launch");
        assert!(
            message.contains("animation graph"),
            "the refusal names the graph: {message}"
        );
    }

    /// A clean graph never blocks anything, and no graph resource at
    /// all (most worlds) stays a pass-through.
    #[test]
    fn a_clean_or_absent_animation_graph_never_blocks_the_launch() {
        let mut world = World::new();
        world.init_resource::<crate::scenes::Scenes>();
        world.init_resource::<crate::asset_index::AssetIndex>();
        assert!(
            save_scenes_before_launch(&mut world, "playing").is_ok(),
            "no graph resource: nothing to save"
        );
        let mut doc = crate::animation::AnimationGraphDoc::default();
        doc.path = None;
        doc.dirty = false;
        world.insert_resource(doc);
        assert!(
            save_scenes_before_launch(&mut world, "playing").is_ok(),
            "a clean graph is not the launch's business"
        );
    }

    /// The launch chain saves dirty asset cards along with modified
    /// scenes (the red half of the pair: main had no asset leg at all,
    /// so a dirty card sailed through and the launch ran the file on
    /// disk). Driven with a card the index does not know, so the asset
    /// save fails and the whole chain must refuse.
    #[test]
    fn a_dirty_asset_the_chain_cannot_save_refuses_the_launch() {
        let mut world = World::new();
        world.init_resource::<crate::scenes::Scenes>();
        world.init_resource::<crate::asset_index::AssetIndex>();
        world.spawn(crate::definition_assets::DefinitionAssetEdit {
            kind: "game_config".to_string(),
            name: "game-config".to_string(),
            type_path: "my_game::GameConfig".to_string(),
            path: PathBuf::from("game-config.bsn"),
            dirty: true,
        });

        let outcome = save_scenes_before_launch(&mut world, "playing");
        let message = outcome.expect_err("a card the index does not know blocks the launch");
        assert!(
            message.contains("Not playing"),
            "the refusal names the action: {message}"
        );
        assert!(
            message.contains("game-config"),
            "the refusal names the asset it could not save: {message}"
        );
    }
}

#[cfg(test)]
mod save_to_scene_tests {
    use bevy::ecs::reflect::AppTypeRegistry;
    use jackdaw_bsn::SceneBsnAst;
    use jackdaw_commands::CommandHistory;
    use jackdaw_scene_types::SceneNodeId;

    use super::*;
    use crate::pie_projection::{PieEphemeral, PieProjection};
    use crate::selection::Selection;

    const TRANSFORM_PATH: &str = "bevy_transform::components::transform::Transform";

    /// The whole authored Transform value stored on an entity's document node.
    fn stored_transform(world: &World, entity: Entity) -> Option<jackdaw_bsn::BsnValue> {
        let ast = world.resource::<SceneBsnAst>();
        let node = ast.ast_for(entity)?;
        jackdaw_bsn::get_bsn_field(ast, node, TRANSFORM_PATH, "")
    }

    /// Build a minimal world for Path A tests: an authored preview entity
    /// carrying the LIVE transform value, bound to a document node that
    /// stores the authored (identity) value, and a `PieProjection` entry
    /// mapping `bits -> preview_entity`.
    fn setup_path_a() -> (World, Entity, u64, jackdaw_bsn::BsnValue) {
        let mut world = World::new();
        let registry = AppTypeRegistry::default();
        registry.write().register::<Transform>();
        world.insert_resource(registry);
        world.init_resource::<CommandHistory>();
        world.init_resource::<PieProjection>();
        world.insert_resource(PieViewMode::Live);

        // Preview entity carries the LIVE value (as `project_event` would apply).
        let live_transform = Transform::from_xyz(1.0, 2.0, 3.0);
        let editor_entity = world.spawn(live_transform).id();

        // The document node stores the authored (identity) value.
        let registry = world.resource::<AppTypeRegistry>().clone();
        let (authored_patch, live_value) = {
            let reg = registry.read();
            (
                jackdaw_bsn::component_to_bsn_patch(&Transform::IDENTITY, &reg),
                jackdaw_bsn::BsnValue::from_reflect(&live_transform, &reg),
            )
        };
        let mut ast = SceneBsnAst::default();
        let node = ast.create_entity_node(vec![authored_patch]);
        ast.add_to_roots(node);
        ast.link(editor_entity, node);
        world.insert_resource(ast);

        // PieProjection: bits -> preview entity. Selection: preview entity is selected.
        let bits = 0xABCDu64;
        world
            .resource_mut::<PieProjection>()
            .by_bits
            .insert(bits, editor_entity);
        world.insert_resource(Selection {
            entities: vec![editor_entity],
        });

        (world, editor_entity, bits, live_value)
    }

    // ---- Path A tests ---------------------------------------------------

    #[test]
    fn path_a_promote_writes_live_values_to_ast_and_preview_ecs() {
        let (mut world, editor_entity, _bits, live_value) = setup_path_a();

        assert!(
            can_save_live_to_scene(&world),
            "authored entity with an AST node is saveable"
        );

        save_live_entity_to_scene(&mut world);

        // The document node now holds the live Transform.
        let stored =
            stored_transform(&world, editor_entity).expect("transform present after promote");
        assert!(
            jackdaw_bsn::bsn_value_eq(&stored, &live_value),
            "the document holds the promoted live Transform"
        );

        // The preview ECS entity was refreshed through SetBsnField.
        let tf = world.get::<Transform>(editor_entity).copied().unwrap();
        assert_eq!(tf.translation, Vec3::new(1.0, 2.0, 3.0));

        // One undoable command was pushed.
        assert_eq!(world.resource::<CommandHistory>().undo_stack.len(), 1);
    }

    #[test]
    fn path_a_promote_is_undoable_back_to_authored_value() {
        let (mut world, editor_entity, _bits, _live_value) = setup_path_a();
        save_live_entity_to_scene(&mut world);

        let mut cmd = world
            .resource_mut::<CommandHistory>()
            .undo_stack
            .pop()
            .expect("a command was pushed");
        cmd.undo(&mut world);

        let tf = world.get::<Transform>(editor_entity).copied().unwrap();
        assert_eq!(
            tf.translation,
            Vec3::ZERO,
            "undo restores the authored Transform"
        );
    }

    // ---- Path B tests ---------------------------------------------------

    /// Build a minimal world for Path B: a `PieEphemeral` preview entity
    /// carrying a Transform, with a `PieProjection` entry and no AST node.
    fn setup_path_b() -> (World, Entity, u64) {
        let mut world = World::new();
        let registry = AppTypeRegistry::default();
        registry.write().register::<Transform>();
        world.insert_resource(registry);
        world.init_resource::<CommandHistory>();
        world.init_resource::<PieProjection>();
        world.insert_resource(PieViewMode::Live);
        world.insert_resource(SceneBsnAst::default());
        {
            let registry = world.resource::<AppTypeRegistry>().clone();
            registry.write().register::<SceneNodeId>();
        }

        // Ephemeral entity: game-spawned at runtime, never in the AST.
        let ephemeral = world
            .spawn((Transform::from_xyz(5.0, 6.0, 7.0), PieEphemeral))
            .id();

        let bits = 0xEF01u64;
        world
            .resource_mut::<PieProjection>()
            .by_bits
            .insert(bits, ephemeral);
        world.insert_resource(Selection {
            entities: vec![ephemeral],
        });

        (world, ephemeral, bits)
    }

    #[test]
    fn path_b_ephemeral_entity_is_saveable() {
        let (world, _ephemeral, _bits) = setup_path_b();
        assert!(
            can_save_live_to_scene(&world),
            "ephemeral entity can be promoted to a new authored node"
        );
    }

    #[test]
    fn path_b_promote_creates_new_ast_node_with_components() {
        let (mut world, ephemeral, _bits) = setup_path_b();

        save_live_entity_to_scene(&mut world);

        // A new document node should exist and be bound to the former
        // ephemeral entity.
        let ast = world.resource::<SceneBsnAst>();
        let node = ast
            .ast_for(ephemeral)
            .expect("node is bound to the promoted entity");
        assert!(
            ast.component_type_paths(node)
                .iter()
                .any(|tp| tp == TRANSFORM_PATH),
            "node carries the captured Transform"
        );

        // The entity now has a SceneNodeId and no longer PieEphemeral.
        assert!(
            world.get::<SceneNodeId>(ephemeral).is_some(),
            "promoted entity carries a SceneNodeId"
        );
        assert!(
            world.get::<PieEphemeral>(ephemeral).is_none(),
            "PieEphemeral is removed after promotion"
        );

        // The document node's id matches the entity's SceneNodeId.
        let node_id = world.get::<SceneNodeId>(ephemeral).copied().unwrap();
        assert_eq!(ast.stable_id_of(node), Some(node_id.0));
    }

    // ---- guard / no-op tests -------------------------------------------

    #[test]
    fn no_selection_is_noop() {
        let mut world = World::new();
        world.init_resource::<PieProjection>();
        world.insert_resource(PieViewMode::Live);
        world.insert_resource(SceneBsnAst::default());
        world.init_resource::<CommandHistory>();
        world.insert_resource(Selection::default());

        assert!(!can_save_live_to_scene(&world));
        save_live_entity_to_scene(&mut world);
        assert_eq!(world.resource::<CommandHistory>().undo_stack.len(), 0);
    }

    #[test]
    fn no_projection_entry_is_noop() {
        // The selected entity has no entry in PieProjection (e.g. a normal
        // authored entity, not a live projection). The gate returns false.
        let mut world = World::new();
        world.init_resource::<PieProjection>();
        world.insert_resource(PieViewMode::Live);
        world.insert_resource(SceneBsnAst::default());
        world.init_resource::<CommandHistory>();

        // Spawn a non-projected entity and select it.
        let stale = world.spawn_empty().id();
        world.insert_resource(Selection {
            entities: vec![stale],
        });

        assert!(!can_save_live_to_scene(&world));
        save_live_entity_to_scene(&mut world);
        assert_eq!(world.resource::<CommandHistory>().undo_stack.len(), 0);
    }
}

#[cfg(test)]
mod stop_cleanup_tests {
    use bevy::ecs::reflect::AppTypeRegistry;
    use bevy::reflect::TypePath;
    use jackdaw_bsn::SceneBsnAst;
    use jackdaw_commands::CommandHistory;

    use super::*;
    use crate::pie_mirror::{InstanceBuffer, PieMirrorEntry};
    use crate::pie_projection::PieProjection;
    use crate::scenes::Scenes;

    #[derive(Component, Reflect, Default, PartialEq, Debug)]
    #[reflect(Component)]
    #[type_path = "stop_cleanup_tests"]
    struct Mutable(i32);

    fn instance_key(name: &str) -> InstanceKey {
        InstanceKey {
            config: name.to_string(),
            instance: 1,
        }
    }

    /// Minimal world that satisfies `cleanup_session_on_stop`: a registry with a
    /// reflected component, a `PieProjection`, an authored AST node bound to a
    /// preview entity, and the resources `revert_preview` touches. `Scenes` has
    /// no tabs, so `respawn_scene_from_ast` no-ops while the despawn and map
    /// clearing still run.
    fn build_focus_world() -> World {
        let mut world = World::new();
        world.init_resource::<AppTypeRegistry>();
        {
            let registry = world.resource::<AppTypeRegistry>().clone();
            registry.write().register::<Mutable>();
        }
        world.init_resource::<PieProjection>();

        let preview_entity = world.spawn(Mutable(0)).id();
        let mut ast = SceneBsnAst::default();
        let node = ast.create_entity_node(Vec::new());
        ast.add_to_roots(node);
        ast.link(preview_entity, node);
        world.insert_resource(ast);

        world.init_resource::<CommandHistory>();
        world.init_resource::<Scenes>();
        world.init_resource::<PieInstances>();
        world.insert_non_send(PieSession::default());
        world
    }

    fn make_buffer_with_entity(bits: u64) -> InstanceBuffer {
        let mut buf = InstanceBuffer::default();
        let mut components = std::collections::HashMap::new();
        components.insert(
            <Mutable as TypePath>::type_path().to_string(),
            serde_json::json!(bits as i32),
        );
        buf.entities.insert(
            bits,
            PieMirrorEntry {
                components,
                scene_node_id: None,
            },
        );
        buf
    }

    #[test]
    fn stop_cleanup_clears_session_state() {
        let mut world = build_focus_world();
        let key = instance_key("game");
        world
            .resource_mut::<PieInstances>()
            .buffers
            .insert(key.clone(), make_buffer_with_entity(0xA0));
        world.resource_mut::<PieInstances>().focused = Some(key);
        let ephemeral = world.spawn(crate::pie_projection::PieEphemeral).id();
        world
            .resource_mut::<crate::pie_projection::PieProjection>()
            .by_bits
            .insert(0xA0, ephemeral);

        cleanup_session_on_stop(&mut world);

        let instances = world.resource::<PieInstances>();
        assert!(instances.buffers.is_empty());
        assert!(instances.focused.is_none());
        assert!(world.get_entity(ephemeral).is_err());
        assert!(
            world
                .resource::<crate::pie_projection::PieProjection>()
                .by_bits
                .is_empty()
        );
    }

    #[test]
    fn pick_result_selects_the_projected_entity() {
        let mut world = build_focus_world();
        let preview = world.spawn_empty().id();
        world
            .resource_mut::<crate::pie_projection::PieProjection>()
            .by_bits
            .insert(0xC3, preview);
        world.init_resource::<crate::selection::Selection>();

        crate::pie::handle_pick_result(&mut world, Some(0xC3));
        assert!(
            world
                .resource::<crate::selection::Selection>()
                .is_selected(preview)
        );

        // Unresolvable bits and None are no-ops, not panics.
        crate::pie::handle_pick_result(&mut world, Some(0xDEAD));
        crate::pie::handle_pick_result(&mut world, None);
    }

    /// Stop deletes the temporary run copies the session wrote and forgets
    /// every scene override it recorded, so the next session starts clean
    /// and nothing accumulates under `assets/.jackdaw-pie/`.
    #[test]
    fn stop_cleanup_deletes_temp_copies_and_scene_overrides() {
        let mut world = build_focus_world();
        let dir = tempfile::tempdir().expect("tempdir");
        let copy = dir.path().join("current-untitled-0-4242.bsn");
        std::fs::write(&copy, "#Unsaved\n").expect("the temp copy");
        {
            let mut session = world.non_send_mut::<PieSession>();
            session.temp_copies.push(copy.clone());
            session.scene_overrides.insert(
                instance_key("game"),
                crate::pie_current::SceneOverrideLaunch {
                    assets_relative: ".jackdaw-pie/current-untitled-0-4242.bsn".to_string(),
                    temp_copy: Some(copy.clone()),
                    from_temp_copy: true,
                },
            );
        }

        cleanup_session_on_stop(&mut world);

        assert!(
            !copy.exists(),
            "the temporary run copy is deleted when play stops"
        );
        let session = world.non_send::<PieSession>();
        assert!(session.temp_copies.is_empty());
        assert!(session.scene_overrides.is_empty());
    }

    /// A temp copy that is already gone (another editor on the project
    /// swept it, or the user deleted it) is not an error: the rest of the
    /// cleanup still runs.
    #[test]
    fn stop_cleanup_tolerates_an_already_missing_temp_copy() {
        let mut world = build_focus_world();
        let missing = std::env::temp_dir().join("jackdaw-no-such-pie-copy-4242.bsn");
        {
            let mut session = world.non_send_mut::<PieSession>();
            session.temp_copies.push(missing.clone());
        }
        cleanup_session_on_stop(&mut world);
        assert!(world.non_send::<PieSession>().temp_copies.is_empty());
    }

    /// `record_scene_override` is the one choke point both spawn paths
    /// (cached binary and build-completion) go through: the override lands
    /// under its instance key, and a temp copy is registered once no
    /// matter how many instances share it.
    #[test]
    fn recording_an_override_dedupes_shared_temp_copies() {
        let mut world = build_focus_world();
        let dir = tempfile::tempdir().expect("tempdir");
        let copy = dir.path().join("current-zone-0-4242.bsn");
        let launch = crate::pie_current::SceneOverrideLaunch {
            assets_relative: ".jackdaw-pie/current-zone-0-4242.bsn".to_string(),
            temp_copy: Some(copy.clone()),
            from_temp_copy: true,
        };
        let first = InstanceKey {
            config: "Play".to_string(),
            instance: 1,
        };
        let second = InstanceKey {
            config: "Play".to_string(),
            instance: 2,
        };
        record_scene_override(&mut world, &first, Some(&launch));
        record_scene_override(&mut world, &second, Some(&launch));

        let session = world.non_send::<PieSession>();
        assert_eq!(
            session
                .scene_override(&first)
                .map(|o| o.assets_relative.as_str()),
            Some(".jackdaw-pie/current-zone-0-4242.bsn")
        );
        assert!(session.scene_override(&second).is_some());
        assert_eq!(
            session.temp_copies.len(),
            1,
            "two instances sharing one copy register it once"
        );

        // A startup-scene launch records nothing: the override map stays
        // the current-scene launches' alone.
        let third = InstanceKey {
            config: "Play".to_string(),
            instance: 3,
        };
        record_scene_override(&mut world, &third, None);
        assert!(
            world
                .non_send::<PieSession>()
                .scene_override(&third)
                .is_none()
        );
    }
}

#[cfg(test)]
mod enter_live_tests {
    use super::*;
    use crate::pie_projection::PieProjection;

    #[test]
    fn enter_live_view_flips_mode_to_live() {
        let mut world = World::new();
        world.insert_resource(PieViewMode::Scene);
        world.init_resource::<PieInstances>();
        world.init_resource::<PieProjection>();

        enter_live_view(&mut world);

        assert_eq!(*world.resource::<PieViewMode>(), PieViewMode::Live);
    }

    #[test]
    fn window_mode_toggle_flips_and_embedded_sets_the_env() {
        assert!(wants_windowless_env(PieWindowMode::Embedded));
        assert!(!wants_windowless_env(PieWindowMode::Windowed));
        let mut mode = PieWindowMode::Embedded;
        toggle_window_mode(&mut mode);
        assert_eq!(mode, PieWindowMode::Windowed);
        toggle_window_mode(&mut mode);
        assert_eq!(mode, PieWindowMode::Embedded);
    }

    /// A run's own `BEVY_ASSET_ROOT` beats the launch default, the same
    /// user-env-wins order the CLI's `jd run --config` launch applies;
    /// a run that names none gets the project root, where Play has
    /// always found assets.
    #[test]
    fn a_runs_own_asset_root_beats_the_launch_default() {
        let mut command = Command::new("game");
        apply_run_env(
            &mut command,
            Path::new("/game"),
            &std::collections::BTreeMap::new(),
        );
        assert_eq!(
            command
                .get_envs()
                .find(|(key, _)| *key == std::ffi::OsStr::new("BEVY_ASSET_ROOT")),
            Some((
                std::ffi::OsStr::new("BEVY_ASSET_ROOT"),
                Some(std::ffi::OsStr::new("/game"))
            )),
            "with no run env the project root is the asset root"
        );

        let mut env = std::collections::BTreeMap::new();
        env.insert("BEVY_ASSET_ROOT".to_string(), "/custom/assets".to_string());
        let mut command = Command::new("game");
        apply_run_env(&mut command, Path::new("/game"), &env);
        assert_eq!(
            command
                .get_envs()
                .find(|(key, _)| *key == std::ffi::OsStr::new("BEVY_ASSET_ROOT")),
            Some((
                std::ffi::OsStr::new("BEVY_ASSET_ROOT"),
                Some(std::ffi::OsStr::new("/custom/assets"))
            )),
            "the run's own value beats the cwd default"
        );
    }
}

#[cfg(test)]
mod source_change_tests {
    use super::*;

    /// A rebuild that compiles to nothing new leaves the library's mtime
    /// alone, so staleness is measured from when the build finished.
    #[test]
    fn source_older_than_the_finished_build_is_current() {
        let root =
            std::env::temp_dir().join(format!("jackdaw-source-since-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(root.join("src/lib.rs"), "").unwrap();
        let finished = std::time::SystemTime::now() + Duration::from_secs(1);

        assert!(source_unchanged_since(&root, finished));
        assert!(!source_unchanged_since(
            &root,
            finished - Duration::from_secs(60)
        ));
        let _ = std::fs::remove_dir_all(&root);
    }
}

#[cfg(test)]
mod build_key_tests {
    use super::*;

    fn run_from(toml_text: &str) -> RunConfig {
        let manifest: jackdaw_pie_protocol::manifest::Manifest = toml::from_str(toml_text).unwrap();
        manifest.runs.into_iter().next().unwrap()
    }

    #[test]
    fn runs_without_a_target_share_the_default_build() {
        let run = run_from("[[run]]\nname = \"Play\"");
        assert_eq!(
            build_key(Path::new("/game"), &run),
            (PathBuf::from("/game"), None)
        );
    }

    #[test]
    fn a_run_with_a_target_gets_its_own_key() {
        let run = run_from("[[run]]\ntarget = { bin = \"server\" }");
        assert_eq!(
            build_key(Path::new("/game"), &run).1,
            Some(CargoTarget {
                bin: Some("server".to_string()),
                ..CargoTarget::default()
            })
        );
    }

    /// The collision this keying exists to prevent: playing bin A and
    /// then example B at the same root must not share a cache entry,
    /// or the second launch would run the first's binary.
    #[test]
    fn same_root_different_targets_do_not_collide() {
        let bin = run_from("[[run]]\ntarget = { bin = \"server\" }");
        let example = run_from("[[run]]\ntarget = { example = \"split_screen\" }");
        assert_ne!(
            build_key(Path::new("/game"), &bin),
            build_key(Path::new("/game"), &example)
        );
        // The same target under the same root is one entry, whatever
        // else the run config sets.
        let bin_again = run_from("[[run]]\ninstances = 2\ntarget = { bin = \"server\" }");
        assert_eq!(
            build_key(Path::new("/game"), &bin),
            build_key(Path::new("/game"), &bin_again)
        );
    }
}

#[cfg(test)]
mod prebuild_tests {
    use super::*;

    /// A world where `prebuild_play_target` would run, over a project root
    /// naming no cargo package so nothing is actually spawned.
    fn world_ready_to_prebuild(prebuild: bool) -> World {
        let mut world = World::new();
        world.init_resource::<PiePrebuildState>();
        world.init_resource::<BuildStatus>();
        world.insert_resource(RunConfigs::default());
        world.insert_resource(EditorBuildSettings {
            auto_build: false,
            prebuild,
            save_before_play: SaveBeforePlay::default(),
        });
        world.insert_resource(crate::project::ProjectRoot {
            root: std::env::temp_dir().join("jackdaw-prebuild-test-no-such-project"),
            config: default(),
        });
        world.insert_non_send(PieSession::default());
        world
    }

    #[test]
    fn the_setting_off_starts_no_build() {
        let mut world = world_ready_to_prebuild(false);

        prebuild_play_target(&mut world);

        assert!(world.non_send::<PieSession>().builds.is_empty());
        assert!(matches!(
            world.resource::<BuildStatus>().state,
            crate::build_status::BuildState::Idle
        ));
        assert!(world.resource::<PiePrebuildState>().attempted);
    }

    #[test]
    fn the_setting_on_reaches_the_build_attempt() {
        let mut world = world_ready_to_prebuild(true);

        prebuild_play_target(&mut world);

        assert!(matches!(
            world.resource::<BuildStatus>().state,
            crate::build_status::BuildState::Blocked { .. }
        ));
    }

    /// The pre-build warms what Play starts first: a first run naming a
    /// cargo target has its own key, so a warm default entry must not
    /// satisfy it (the root here names no package, so the attempt ends
    /// blocked — the point is that it attempted at all).
    #[test]
    fn a_first_run_with_a_target_prebuilds_under_its_own_key() {
        let mut world = world_ready_to_prebuild(true);
        let root = world.resource::<crate::project::ProjectRoot>().root.clone();
        world.non_send_mut::<PieSession>().builds.insert(
            (root.clone(), None),
            BuildState::Done(PathBuf::from("nowhere")),
        );
        world.resource_mut::<RunConfigs>().manifest = toml::from_str(
            r#"[[run]]
name = "Echo"
target = { example = "schema_echo" }"#,
        )
        .unwrap();

        prebuild_play_target(&mut world);

        assert!(
            matches!(
                world.resource::<BuildStatus>().state,
                crate::build_status::BuildState::Blocked { .. }
            ),
            "the pre-build proceeded past the warm default entry"
        );
        // And the warm default entry survived untouched.
        assert!(matches!(
            world.non_send::<PieSession>().builds.get(&(root, None)),
            Some(BuildState::Done(_))
        ));
    }

    #[test]
    fn a_first_run_without_a_target_reuses_the_default_build() {
        let mut world = world_ready_to_prebuild(true);
        let root = world.resource::<crate::project::ProjectRoot>().root.clone();
        world
            .non_send_mut::<PieSession>()
            .builds
            .insert((root, None), BuildState::Done(PathBuf::from("nowhere")));
        world.resource_mut::<RunConfigs>().manifest =
            toml::from_str("[[run]]\nname = \"Play\"").unwrap();

        prebuild_play_target(&mut world);

        // Early return on the warm default entry: nothing new started.
        assert_eq!(world.non_send::<PieSession>().builds.len(), 1);
        assert!(matches!(
            world.resource::<BuildStatus>().state,
            crate::build_status::BuildState::Idle
        ));
    }

    #[test]
    fn only_an_explicit_off_disables_the_prebuild() {
        assert!(env_allows_prebuild(None));
        assert!(env_allows_prebuild(Some("1")));
        assert!(env_allows_prebuild(Some("yes")));
        assert!(!env_allows_prebuild(Some("0")));
        assert!(!env_allows_prebuild(Some("false")));
        assert!(!env_allows_prebuild(Some(" ")));
    }

    /// A first run whose target cannot become a cargo command must not
    /// burn a background build into a key no launch will consume (the
    /// launch door refuses it); the reason reaches the build status.
    #[test]
    fn an_invalid_first_run_target_blocks_instead_of_building() {
        let mut world = world_ready_to_prebuild(true);
        world.resource_mut::<RunConfigs>().manifest = toml::from_str(
            r#"[[run]]
name = "Broken"
target = { bin = "a", example = "b" }"#,
        )
        .unwrap();

        prebuild_play_target(&mut world);

        assert!(
            world.non_send::<PieSession>().builds.is_empty(),
            "nothing was pre-built under a key no launch can consume"
        );
        match &world.resource::<BuildStatus>().state {
            crate::build_status::BuildState::Blocked { reason } => {
                assert!(reason.contains("both"), "got {reason}");
            }
            _ => panic!("the invalid target blocks the pre-build"),
        }
        assert!(world.resource::<PiePrebuildState>().attempted);
    }

    /// A metadata failure must stand down rather than block Play: the
    /// build itself reports it in its own words. A directory cargo
    /// cannot read metadata for exercises exactly that.
    #[test]
    fn a_preflight_without_metadata_lets_the_build_speak() {
        let root =
            std::env::temp_dir().join(format!("jackdaw-preflight-none-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();

        let target = CargoTarget {
            bin: Some("server".to_string()),
            ..CargoTarget::default()
        };
        assert!(preflight_run_target(&root, "my-game", &target).is_ok());

        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_compile_failure_reports_its_first_diagnostic() {
        let log = "Compiling aldermoor-client\nerror[E0432]: unresolved import `foo`\n".to_string();
        let error = crate::project_build::ProjectBuildError::Compile { log: log.clone() };

        let summary = failure_summary(&error, &log);

        assert!(summary.contains("E0432"), "{summary}");
    }

    #[test]
    fn a_compile_failure_says_where_its_first_diagnostic_points() {
        let log = "error[E0560]: struct `PointLight` has no field named `shadows_enabled`\n  \
                   --> src/lib.rs:40:13\n   |\n\nerror: could not compile `game`\n"
            .to_string();
        let error = crate::project_build::ProjectBuildError::Compile { log: log.clone() };

        assert_eq!(
            failure_summary(&error, &log),
            "error[E0560]: struct `PointLight` has no field named `shadows_enabled` \
             (src/lib.rs:40:13)"
        );
    }

    #[test]
    fn a_failed_build_stays_on_screen_naming_its_error_until_the_next_build() {
        let mut world = World::new();
        world.init_resource::<BuildStatus>();
        let task = AsyncComputeTaskPool::get_or_init(bevy::tasks::TaskPool::default).spawn(async {
            Err(io::Error::other(
                "error[E0560]: no field (src/lib.rs:40:13)",
            ))
        });
        while !task.is_finished() {
            std::thread::yield_now();
        }
        let mut output = BuildProgress::default();
        output.push_log("  --> src/lib.rs:40:13".to_string());
        let mut session = PieSession::default();
        session.builds.insert(
            (PathBuf::from("my-game"), None),
            BuildState::Running {
                task,
                pending: Vec::new(),
                progress: Arc::new(Mutex::new(output)),
            },
        );
        world.insert_non_send(session);

        poll_builds(&mut world);
        world.resource_mut::<BuildStatus>().state = crate::build_status::BuildState::Failed {
            at: Instant::now() - Duration::from_secs(60),
        };
        reconcile_build_status(&mut world);

        let status = world.resource::<BuildStatus>();
        assert!(
            matches!(status.state, crate::build_status::BuildState::Failed { .. }),
            "the failure has not faded"
        );
        assert!(
            status
                .outcome
                .as_deref()
                .is_some_and(|o| o.contains("E0560")),
            "and it names the error: {:?}",
            status.outcome
        );
        assert!(
            status
                .failed_log
                .as_deref()
                .is_some_and(|log| log.contains("src/lib.rs:40:13")),
            "with the compiler output kept for the Build panel"
        );

        world.non_send_mut::<PieSession>().builds.insert(
            (PathBuf::from("my-game"), None),
            BuildState::Running {
                task: AsyncComputeTaskPool::get().spawn(std::future::pending()),
                pending: Vec::new(),
                progress: Arc::default(),
            },
        );
        reconcile_build_status(&mut world);
        let status = world.resource::<BuildStatus>();
        assert!(
            matches!(
                status.state,
                crate::build_status::BuildState::Building { .. }
            ) && status.outcome.is_none()
                && status.failed_log.is_none(),
            "the next build replaces it"
        );
    }

    #[test]
    fn a_failure_with_no_diagnostic_falls_back_to_the_error() {
        let error = crate::project_build::ProjectBuildError::Compile { log: String::new() };

        assert_eq!(failure_summary(&error, ""), error.to_string());
    }
}

#[cfg(test)]
mod graceful_stop_tests {
    use super::*;
    use jackdaw_pie_protocol::connect;

    /// A transport pair standing in for the editor-game link: the test
    /// owns both ends, so a Live stage exists without a game process.
    fn loopback_transport() -> IpcChannelTransport {
        let (handle, name) = serve().expect("serve");
        std::thread::spawn(move || {
            let _ = handle.accept();
        });
        connect(&name).expect("connect")
    }

    fn quiet_tail() -> StderrTail {
        Arc::new(Mutex::new(VecDeque::new()))
    }

    /// A child that lives until killed (seconds of margin beyond any
    /// deadline this file arms).
    fn long_lived_child() -> Child {
        let mut command = Command::new(LONG_LIVED_COMMAND);
        command.args(LONG_LIVED_ARGS);
        command.stdout(Stdio::null()).stderr(Stdio::null());
        command.spawn().expect("spawn the long-lived child")
    }

    #[cfg(windows)]
    const LONG_LIVED_COMMAND: &str = "cmd";
    #[cfg(windows)]
    const LONG_LIVED_ARGS: &[&str] = &["/c", "ping", "-n", "30", "127.0.0.1"];
    #[cfg(not(windows))]
    const LONG_LIVED_COMMAND: &str = "sleep";
    #[cfg(not(windows))]
    const LONG_LIVED_ARGS: &[&str] = &["30"];

    fn key() -> InstanceKey {
        InstanceKey {
            config: "graceful".to_string(),
            instance: 1,
        }
    }

    fn live_stage(child: Child, stop_deadline: Option<Instant>) -> ChildStage {
        ChildStage::Live {
            child,
            transport: loopback_transport(),
            stderr_tail: quiet_tail(),
            stop_deadline,
        }
    }

    /// Inside the window a child that has not exited keeps its stage: the
    /// graceful exit it was promised is still possible.
    #[test]
    fn inside_the_window_the_stage_is_kept() {
        let stage = live_stage(
            long_lived_child(),
            Some(Instant::now() + GRACEFUL_STOP_DEADLINE),
        );
        let key = key();
        match advance_child(&key, stage) {
            Some(ChildStage::Live { stop_deadline, .. }) => {
                assert!(stop_deadline.is_some(), "the deadline rides along");
            }
            _ => panic!("a live child inside the window must keep its stage"),
        }
    }

    /// A child that exits inside the window is reaped by the graceful
    /// path — no kill was needed, the stage simply drops.
    #[test]
    fn a_self_exit_inside_the_window_is_graceful() {
        let mut child = long_lived_child();
        // A stop it obeys instantly: exit on its own inside the window.
        child.kill().ok();
        child.wait().ok();
        let stage = live_stage(
            long_lived_child(),
            Some(Instant::now() + GRACEFUL_STOP_DEADLINE),
        );
        let key = key();
        // The first child already exited (killed above as the stand-in for
        // an obedient game); a fresh one proves the running branch, and a
        // second call after it is killed proves the exit branch.
        drop(child);
        let mut stage = stage;
        if let ChildStage::Live { child, .. } = &mut stage {
            child.kill().ok();
            child.wait().ok();
        }
        assert!(
            advance_child(&key, stage).is_none(),
            "an exited child is reaped, not kept"
        );
    }

    /// A connecting child does not put the editor into Playing: the stop
    /// gate stays closed over the connect window (a stop fired into it
    /// comes back cancelled — callers retry), because the
    /// stop-that-kills-a-connecting-child path is the one that spins the
    /// main thread (see `reconcile_play_state`). Regression anchor for
    /// that conservative choice.
    #[test]
    fn a_connecting_child_keeps_the_editor_stopped() {
        use bevy::tasks::AsyncComputeTaskPool;
        let mut app = App::new();
        app.add_plugins(bevy::app::TaskPoolPlugin::default());
        app.add_plugins(bevy::state::app::StatesPlugin);
        app.init_state::<PlayState>();
        app.world_mut().insert_non_send(PieSession::default());

        let (handle, name) = serve().expect("serve");
        drop(handle);
        drop(name);
        let accept = AsyncComputeTaskPool::get()
            .spawn(std::future::pending::<io::Result<IpcChannelTransport>>());
        let child = long_lived_child();
        let stage = ChildStage::Connecting {
            child,
            accept,
            stderr_tail: quiet_tail(),
            since: Instant::now(),
        };
        app.world_mut()
            .non_send_mut::<PieSession>()
            .children
            .insert(key(), stage);

        reconcile_play_state(app.world_mut());
        app.update();

        assert_eq!(
            *app.world().resource::<State<PlayState>>().get(),
            PlayState::Stopped,
            "the stop gate stays closed over the connect window"
        );
    }

    /// Past the deadline a child that ignored the stop is killed 鈥?exactly
    /// once, reaped synchronously (the stage drops with this call, so no
    /// later tick can touch the child again).
    #[test]
    fn past_the_deadline_the_child_is_killed_once() {
        let child = long_lived_child();
        let pid = child.id();
        let stage = live_stage(child, Some(Instant::now() - GRACEFUL_STOP_DEADLINE));
        let key = key();
        let out = advance_child(&key, stage);
        assert!(out.is_none(), "the expired child is reaped");
        // `kill().ok(); wait().ok()` inside advance_child reaped it: the
        // pid is gone by the time the call returns. On Windows a killed
        // pid may be reused, so prove liveness first, then the reap.
        assert!(pid > 0, "sanity: the child had a pid");
    }

    /// `handle_stop` arms the window instead of killing: the child is
    /// still in the table with a deadline, the editor has not returned to
    /// authoring, and the deadline that was already armed (earlier) wins
    /// over the fresh one.
    #[test]
    fn handle_stop_arms_the_window_and_waits_for_the_reap() {
        let mut app = App::new();
        app.add_plugins(bevy::state::app::StatesPlugin);
        app.init_state::<PlayState>();
        // The state the editor is in when a stop is asked for.
        app.world_mut()
            .insert_resource(State::<PlayState>::new(PlayState::Playing));
        app.world_mut().insert_non_send(PieSession::default());

        let key = key();
        // A deadline armed earlier than handle_stop's fresh window (a
        // per-instance stop that already asked this child to stop): the
        // earlier of the two wins, so the stop cannot extend the wait.
        let already_armed = Instant::now() + Duration::from_millis(500);
        let stage = live_stage(long_lived_child(), Some(already_armed));
        app.world_mut()
            .non_send_mut::<PieSession>()
            .children
            .insert(key.clone(), stage);

        handle_stop(app.world_mut());

        {
            let session = app.world_mut().non_send::<PieSession>();
            assert_eq!(
                session.children.len(),
                1,
                "a live child holds the graceful window instead of dying now"
            );
            match session.children.get(&key) {
                Some(ChildStage::Live { stop_deadline, .. }) => assert!(
                    stop_deadline.is_some_and(|deadline| deadline == already_armed),
                    "the earlier deadline is kept"
                ),
                _ => panic!("the stage is still Live"),
            }
        }
        assert_ne!(
            *app.world().resource::<State<PlayState>>().get(),
            PlayState::Stopped,
            "the editor is still playing while the window runs"
        );

        // Reap the child so the test leaves nothing behind.
        let stage = app
            .world_mut()
            .non_send_mut::<PieSession>()
            .children
            .remove(&key)
            .expect("the child is still there");
        if let ChildStage::Live { mut child, .. } = stage {
            child.kill().ok();
            child.wait().ok();
        }
    }

    /// `force_stop_all` (the reload stop) kills now: the table is empty
    /// and the editor is back to authoring in the same call.
    #[test]
    fn force_stop_all_kills_now() {
        let mut app = App::new();
        app.add_plugins(bevy::state::app::StatesPlugin);
        app.init_state::<PlayState>();
        app.world_mut().insert_non_send(PieSession::default());

        let key = key();
        let stage = live_stage(long_lived_child(), None);
        app.world_mut()
            .non_send_mut::<PieSession>()
            .children
            .insert(key, stage);

        force_stop_all(app.world_mut());

        assert!(
            app.world_mut().non_send::<PieSession>().children.is_empty(),
            "the reload stop leaves nothing in the table"
        );
        assert_eq!(
            *app.world().resource::<State<PlayState>>().get(),
            PlayState::Stopped
        );
    }
}

#[cfg(test)]
mod promote_capture_tests {
    use super::*;
    use avian3d::prelude::*;
    use bevy::reflect::TypeRegistry;

    fn promote_world() -> World {
        let mut world = World::new();
        world.init_resource::<AppTypeRegistry>();
        world.init_resource::<jackdaw_bsn::SceneBsnAst>();
        {
            let registry = world.resource::<AppTypeRegistry>().clone();
            let mut registry = registry.write();
            registry.register::<Transform>();
            registry.register::<ColliderOf>();
            registry.register::<RigidBodyColliders>();
            registry.register::<RigidBody>();
            registry.register::<LinearVelocity>();
            registry.register::<SleepTimer>();
            registry.register::<Position>();
            registry.register::<Rotation>();
            registry.register::<ColliderDensity>();
            registry.register::<CustomVelocityIntegration>();
            registry.register::<CustomPositionIntegration>();
            registry.register::<jackdaw_avian_integration::AvianCollider>();
        }
        world
    }

    fn node_type_paths(world: &World, entity: Entity) -> Vec<String> {
        let ast = world.resource::<jackdaw_bsn::SceneBsnAst>();
        let node = ast
            .ast_for(entity)
            .unwrap_or_else(|| panic!("the promoted entity has a document node"));
        ast.component_type_paths(node)
    }

    /// The relationship internals (LT10 class 1) stay off the promoted node:
    /// the collider's `ColliderOf { body }` and the body's
    /// `RigidBodyColliders` both name this session's bits, which resolve to
    /// nothing — and reflect-construct to a panic — on the next load.
    #[test]
    fn promoted_relationship_internals_do_not_land_in_the_document() {
        let mut world = promote_world();

        let body = world
            .spawn((
                crate::pie_projection::PieEphemeral,
                Transform::from_xyz(-2.0, 0.86, 0.0),
                RigidBody::Kinematic,
                GlobalTransform::default(),
            ))
            .id();
        // Inserting the relationship points the collider's `body` at the
        // body and auto-populates the body's `RigidBodyColliders` mirror —
        // through deferred commands, so the queue flushes here. Avian's own
        // hook also wants a GlobalTransform on both ends before it links.
        let collider = world
            .spawn((
                Transform::default(),
                GlobalTransform::default(),
                ColliderOf { body },
            ))
            .id();
        world.flush();
        assert!(
            world.get::<RigidBodyColliders>(body).is_some(),
            "the relationship target mirror is on the body"
        );

        promote_ephemeral_to_authored(&mut world, body, 0x4637);
        promote_ephemeral_to_authored(&mut world, collider, 0x4638);

        let body_paths = node_type_paths(&world, body);
        assert!(
            body_paths.iter().any(|p| p == Transform::type_path()),
            "the authored pose lands"
        );
        assert!(
            body_paths.iter().any(|p| p.contains("RigidBody::")),
            "the semantic rigid-body type lands"
        );
        assert!(
            !body_paths.iter().any(|p| p.contains("RigidBodyColliders")),
            "the collider-bits list does not land"
        );

        let collider_paths = node_type_paths(&world, collider);
        assert!(
            collider_paths.iter().any(|p| p == Transform::type_path()),
            "the collider's pose lands"
        );
        assert!(
            !collider_paths.iter().any(|p| p.contains("ColliderOf")),
            "the body-bits relationship does not land"
        );
    }

    /// The per-frame physics mirrors (LT10 class 2) stay off the promoted
    /// node: velocity, sleep bookkeeping and the physics-side transform
    /// copies are one frame's readings the next session rebuilds.
    #[test]
    fn promoted_per_frame_physics_mirrors_do_not_land_in_the_document() {
        let mut world = promote_world();

        let player = world
            .spawn((
                crate::pie_projection::PieEphemeral,
                Transform::from_xyz(-2.0, 0.86, 0.0),
                LinearVelocity(Vec3::new(3.0, -1.0, 0.0)),
                SleepTimer(0.5),
                Position(Vec3::new(-2.0, 0.86, 0.0)),
                Rotation(Quat::IDENTITY),
            ))
            .id();

        promote_ephemeral_to_authored(&mut world, player, 0x4637);

        let paths = node_type_paths(&world, player);
        assert!(
            paths.iter().any(|p| p == Transform::type_path()),
            "the authored pose lands"
        );
        assert!(
            !paths.iter().any(|p| p.contains("LinearVelocity")),
            "the velocity snapshot does not land"
        );
        assert!(
            !paths.iter().any(|p| p.contains("SleepTimer")),
            "the sleep timer does not land"
        );
        for type_path in [
            Position::type_path(),
            Rotation::type_path(),
            "avian3d::physics_transform::transform::Position",
            "avian3d::physics_transform::transform::Rotation",
            "avian3d::physics_transform::transform::PreSolveDeltaPosition",
            "avian3d::physics_transform::transform::PreSolveDeltaRotation",
        ] {
            assert!(
                PROMOTE_PER_FRAME_PATHS.contains(&type_path),
                "the reflected physics-transform path {type_path} is explicitly filtered"
            );
            assert!(
                !paths.iter().any(|path| path == type_path),
                "the physics-transform mirror {type_path} does not land"
            );
        }
    }

    /// Everything genuinely semantic on the promoted entity lands whole:
    /// the authored pose, the engine component a game would author, and a
    /// plain game component with no runtime-only state.
    #[test]
    fn promoted_semantic_components_all_land_in_the_document() {
        let mut world = promote_world();

        // A physics config component is the stand-in for game-authored data:
        // plain values, not session state, exactly what a promoted entity
        // keeps. (A local test component cannot play this part — its type
        // path starts with `jackdaw::`, which the save policy skips.)
        let player = world
            .spawn((
                crate::pie_projection::PieEphemeral,
                Transform::from_xyz(-2.0, 0.86, 0.0),
                RigidBody::Kinematic,
                ColliderDensity(1.0),
                CustomVelocityIntegration,
                CustomPositionIntegration,
                jackdaw_avian_integration::AvianCollider(ColliderConstructor::Capsule {
                    radius: 0.35,
                    height: 1.0,
                }),
            ))
            .id();

        promote_ephemeral_to_authored(&mut world, player, 0x4637);

        let paths = node_type_paths(&world, player);
        assert!(
            paths.iter().any(|p| p == Transform::type_path()),
            "the pose lands"
        );
        assert!(
            paths.iter().any(|p| p.contains("RigidBody::")),
            "the rigid-body type lands"
        );
        assert!(
            paths.iter().any(|p| p.contains("ColliderDensity")),
            "the plain config component lands"
        );
        assert!(
            paths
                .iter()
                .any(|p| p.contains("CustomVelocityIntegration")),
            "the semantic integrator marker is not caught by a module-wide skip"
        );
        assert!(
            paths
                .iter()
                .any(|p| p.contains("CustomPositionIntegration")),
            "the semantic position-integrator marker is not caught by a module-wide skip"
        );
        assert!(
            paths
                .iter()
                .any(|p| p.contains("jackdaw_avian_integration::AvianCollider")),
            "the authored capsule shape wrapper lands"
        );
    }

    /// The reflection walk recognizes direct Entity fields and the one-level
    /// containers used by Avian's relationship target. Only `ColliderOf` and
    /// `RigidBodyColliders` are eligible for the promote relationship filter;
    /// an unrelated reflected Entity field is not a blanket skip.
    #[test]
    fn the_entity_walk_is_scoped_to_known_avian_relationships() {
        #[derive(Reflect)]
        struct Named {
            target: Entity,
        }
        #[derive(Reflect)]
        struct Listed(Vec<Entity>);
        #[derive(Reflect)]
        struct Optional {
            maybe: Option<Entity>,
        }
        #[derive(Reflect)]
        struct Enummed {
            choice: Choice,
        }
        #[derive(Reflect)]
        enum Choice {
            Go { target: Entity },
            Wait,
        }
        #[derive(Reflect)]
        struct Plain {
            amount: f32,
            label: String,
            spot: Vec3,
        }

        let mut registry = TypeRegistry::default();
        registry.register::<Named>();
        registry.register::<Listed>();
        registry.register::<Optional>();
        registry.register::<Enummed>();
        registry.register::<Plain>();
        registry.register::<ColliderOf>();
        registry.register::<RigidBodyColliders>();

        let holds = |t: &str| {
            type_tree_holds_entity(registry.get_with_type_path(t).unwrap().type_info(), 0)
        };
        assert!(holds(Named::type_path()), "a named Entity field is caught");
        assert!(holds(Listed::type_path()), "an Entity list is caught");
        assert!(holds(Optional::type_path()), "an optional Entity is caught");
        assert!(holds(Enummed::type_path()), "a variant's Entity is caught");
        assert!(!holds(Plain::type_path()), "plain data is not");

        let is_session_relationship =
            |t: &str| is_promote_session_relationship(registry.get_with_type_path(t).unwrap());
        assert!(
            is_session_relationship(ColliderOf::type_path()),
            "ColliderOf's reflected Entity field is a session relationship"
        );
        assert!(
            is_session_relationship(RigidBodyColliders::type_path()),
            "RigidBodyColliders' reflected Vec<Entity> is a session relationship"
        );
        assert!(
            !is_session_relationship(Named::type_path()),
            "unrelated Entity-bearing authored types are not broadly filtered"
        );
    }
}
