//! The project's game flow: which scene a game starts from, as
//! `assets/game.flow.json` spells it (T13).
//!
//! One file, four faces:
//!
//! * **The file** — `{"start_scene": "menu.bsn", "scenes": [...]}` — is
//!   the single source the three launch forms read (`jackdaw_runtime::
//!   flow` on the game side) and the export stages whole.
//! * **The operator**, `game.set_start_scene`, writes `start_scene`:
//!   read-modify-write, created when the file is absent, atomically.
//! * **The validation** follows the file: a stat fingerprint per frame,
//!   re-read only when the file changes, every problem a `game flow:`
//!   warning on the status bar and in the log — never a popup, never a
//!   block. A project without the file is the default state and warns
//!   nothing.
//! * **The structured face**, [`GameFlowState`], is what the BRP
//!   `jackdaw/game_flow` method answers and what the Project window's
//!   right-click menu reads for its startup-scene marker.

use std::path::{Path, PathBuf};
use std::time::SystemTime;

use bevy::prelude::*;
use jackdaw_api::prelude::*;
use jackdaw_project_build::flow::{self, FlowInspection};

use crate::project::ProjectRoot;

pub struct GameFlowPlugin;

impl Plugin for GameFlowPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<GameFlowState>().add_systems(
            Update,
            poll_game_flow.run_if(in_state(crate::AppState::Editor)),
        );
    }
}

pub(crate) fn add_to_extension(ctx: &mut ExtensionContext) {
    ctx.register_operator::<GameSetStartSceneOp>();
}

/// The open project's flow file, as of the last time it changed: the
/// stat fingerprint it was read at, the inspection the validators and
/// the menu read, and where the file sits.
#[derive(Resource, Default)]
pub struct GameFlowState {
    /// Mtime + length of the file the inspection was read from, or
    /// `None` when the project has no flow file.
    fingerprint: Option<(SystemTime, u64)>,
    /// The absolute path of the flow file, when a project is open.
    pub flow_file: Option<PathBuf>,
    pub inspection: FlowInspection,
}

/// Follow the flow file while a project is open. A stat a frame is the
/// whole cost until the file changes; a change (a hand edit, another
/// tool's write, the operator below) re-reads and re-warns once.
fn poll_game_flow(world: &mut World) {
    let Some(assets) = world
        .get_resource::<ProjectRoot>()
        .map(super::project::ProjectRoot::assets_dir)
    else {
        if world
            .get_resource::<GameFlowState>()
            .is_some_and(|state| state.flow_file.is_some() || state.inspection.present)
        {
            world.insert_resource(GameFlowState::default());
        }
        return;
    };
    refresh_game_flow(world, &assets);
}

/// Re-read the flow file unless the last read is still current, and
/// surface what changed: every warning a `game flow:` line in the log
/// and on the status bar, once per change.
fn refresh_game_flow(world: &mut World, assets: &Path) {
    let file = flow::flow_path(assets);
    let fingerprint = file
        .is_file()
        .then(|| -> Option<(SystemTime, u64)> {
            let metadata = std::fs::metadata(&file).ok()?;
            Some((metadata.modified().ok()?, metadata.len()))
        })
        .flatten();
    if world
        .get_resource::<GameFlowState>()
        .is_some_and(|state| state.fingerprint == fingerprint)
    {
        return;
    }
    let inspection = flow::inspect_flow(assets);
    for warning in &inspection.warnings {
        warn!("game flow: {warning}");
        crate::status_bar::notify_warn(world, format!("game flow: {warning}"));
    }
    world.insert_resource(GameFlowState {
        fingerprint,
        flow_file: Some(file),
        inspection,
    });
}

/// The open project's flow inspection, freshly read — for a caller that
/// holds a project root but no world (the export, before its build).
pub fn inspect_project_flow(root: &Path) -> FlowInspection {
    let assets = jackdaw_project_build::project_manifest::ProjectManifest::read(root)
        .assets_dir()
        .to_path_buf();
    flow::inspect_flow(&root.join(assets))
}

// -- The operator --------------------------------------------------------

fn game_flow_op_available(project: Option<Res<ProjectRoot>>) -> bool {
    project.is_some()
}

/// Name the scene a standalone game starts from: `game.set_start_scene
/// path=<assets-relative>` writes the flow file's `start_scene`,
/// read-modify-write, creating the file when absent. The Project
/// window's right-click menu raises it; QA raises it through the BRP
/// operator call. A path that does not exist is still written — the
/// validation above is what says so, not a refusal here.
#[operator(
    id = "game.set_start_scene",
    label = "Set as Startup Scene",
    description = "Name the scene a standalone game starts from in assets/game.flow.json.",
    is_available = game_flow_op_available,
    allows_undo = false,
    params(path(String, doc = "The scene file: relative to the assets folder, or absolute inside the project.")),
)]
pub fn game_set_start_scene(
    In(params): In<OperatorParameters>,
    mut commands: Commands,
) -> OperatorResult {
    let Some(path) = params.as_str("path").map(str::to_string) else {
        warn!("game.set_start_scene: no path given");
        return OperatorResult::Cancelled;
    };
    commands.queue(move |world: &mut World| set_start_scene(world, &path));
    OperatorResult::Finished
}

/// The operator's body, public so tests run it against a plain world.
pub fn set_start_scene(world: &mut World, raw: &str) {
    let Some(assets) = world
        .get_resource::<ProjectRoot>()
        .map(super::project::ProjectRoot::assets_dir)
    else {
        crate::status_bar::notify_error(world, "Cannot set the start scene: no project is open");
        return;
    };
    let Some(relative) = flow::assets_relative_path(&assets, raw) else {
        crate::status_bar::notify_error(
            world,
            format!(
                "Cannot set the start scene: '{raw}' is not a path inside the project's \
                 assets folder"
            ),
        );
        return;
    };

    let file = flow::flow_path(&assets);
    let mut next = std::fs::read_to_string(&file)
        .map(|text| flow::parse_flow(&text).0)
        .unwrap_or_default();
    next.start_scene = Some(relative.clone());
    // The scene list reads as "the scenes that make up the game", and
    // the validator warns about a start scene it does not list. The
    // operator keeps the two consistent for a scene the project really
    // holds — it joins the list (never reordered, never pruned). A
    // path that names nothing joins nothing: the start_scene is
    // written so the author sees what was asked for, and the
    // validation is what says it is not there.
    if !next.scenes.contains(&relative) && flow::scene_on_disk(&assets, &relative) {
        next.scenes.push(relative.clone());
    }
    match crate::scene_io::save::write_atomic(&file, flow::flow_json(&next).as_bytes()) {
        Ok(()) => {
            info!("game flow: start scene set to '{relative}'");
            crate::status_bar::notify_info(world, format!("start scene set to '{relative}'"));
            // Re-read now rather than next frame, so the warning face
            // (and the Project window's marker) answers in the same
            // breath as the write.
            refresh_game_flow(world, &assets);
        }
        Err(err) => {
            crate::status_bar::notify_error(world, format!("Cannot set the start scene: {}", err));
        }
    }
}
