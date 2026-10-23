//! Build a standalone release of the game: the `Build Game` entry.
//!
//! One operator, `game.export`, behind the File menu: save the modified
//! scenes (an export stages `assets/`, so what the editor shows must be
//! on disk), build with the release profile on the same pipeline and
//! progress the footer already renders for Play's builds, then stage the
//! executable with the whole `assets/` tree into
//! `<root>/.jackdaw/dist/release/` — a directory that runs when
//! double-clicked — and open it in the file manager.
//!
//! The staging itself is [`jackdaw_project_build::export`], shared with
//! `jd export`; this module is only the editor's wiring around it.

use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Instant;

use bevy::prelude::*;
use bevy::tasks::{AsyncComputeTaskPool, Task, futures_lite::future};
use jackdaw_api::prelude::*;
use jackdaw_project_build::export::{self, ExportReport};

use crate::build_status::BuildStatus;
use crate::ext_build::BuildProgress;
use crate::project_build::shim::ShimSpec;

/// The profile the menu entry exports with. An export is a release
/// artifact; other profiles stay reachable through `jd export
/// --profile`.
const EXPORT_PROFILE: &str = "release";

/// The one export the editor runs at a time: the build-and-stage task,
/// the progress sink the footer and Build panel read while it runs, and
/// the project it builds.
#[derive(Resource, Default)]
pub struct GameExports {
    /// The export task. `None` is no export in flight.
    task: Option<Task<Result<ExportReport, String>>>,
    /// The progress sink, kept beside the task and dropped with it.
    progress: Option<Arc<Mutex<BuildProgress>>>,
    /// The project the export builds, for the staging step's plan.
    root: PathBuf,
}

impl GameExports {
    /// The progress sink, while an export runs. What
    /// [`crate::pie::reconcile_build_status`] mirrors into the footer.
    pub(crate) fn progress(&self) -> Option<Arc<Mutex<BuildProgress>>> {
        self.progress.clone()
    }
}

/// Whether the Build Game entry can run: a project is open, and no
/// export is already in flight — the second is what makes the entry
/// grey out rather than silently no-op on a second click.
fn game_export_is_available(
    project: Option<Res<crate::project::ProjectRoot>>,
    exports: Option<Res<GameExports>>,
) -> bool {
    project.is_some() && exports.is_none_or(|exports| exports.task.is_none())
}

/// Build a standalone release of the game and stage it with its assets
/// into `.jackdaw/dist/release/`. Not `project.export_binary`, which
/// serializes a scene, and not terrain export; this builds the game
/// executable itself.
#[operator(
    id = "game.export",
    label = "Build Game Executable",
    description = "Build the game with the release profile and stage it with its assets into .jackdaw/dist/.",
    is_available = game_export_is_available,
    allows_undo = false
)]
pub(crate) fn game_export(_: In<OperatorParameters>, mut commands: Commands) -> OperatorResult {
    commands.queue(start_game_export);
    OperatorResult::Finished
}

/// Begin the export: refuse what cannot be exported up front, save the
/// modified scenes, then hand the rest to a background task and let
/// [`poll_game_export`] report the outcome.
fn start_game_export(world: &mut World) {
    if world.resource::<GameExports>().task.is_some() {
        return;
    }
    let Some(root) = crate::pie::project_root(world) else {
        return;
    };
    if crate::extension_build::is_extension_project(world, &root, true) {
        crate::status_bar::notify_error(
            world,
            "Cannot export: this project is an editor extension, not a game",
        );
        return;
    }
    if let Err(message) = crate::pie::save_scenes_before_launch(world, "exporting") {
        crate::status_bar::notify_error(world, message);
        return;
    }
    match crate::project_build::shim_spec_for_project(&root) {
        Ok(spec) => {
            let (task, progress) = spawn_export_task(root.clone(), spec);
            let mut exports = world.resource_mut::<GameExports>();
            exports.task = Some(task);
            exports.progress = Some(progress);
            exports.root = root;
        }
        Err(err) => crate::status_bar::notify_error(world, format!("Cannot export: {err}")),
    }
}

/// The export's build-and-stage task: Play's own build pipeline with the
/// release profile, then the staging and the dynamic-linking refusal
/// `jd export` applies, all off the render loop — an `assets/` tree can
/// be thousands of files.
fn spawn_export_task(
    root: PathBuf,
    spec: ShimSpec,
) -> (
    Task<Result<ExportReport, String>>,
    Arc<Mutex<BuildProgress>>,
) {
    // The editor stays responsive while a release build runs: the
    // background load keeps half the machine for the editor itself.
    let target = crate::project_build::CargoTarget {
        profile: Some(EXPORT_PROFILE.to_string()),
        ..Default::default()
    };
    let (build, progress) = crate::pie::spawn_game_build(
        &root,
        spec,
        Some(target),
        crate::project_build::BuildLoad::Background,
    );
    if let Ok(mut p) = progress.lock() {
        p.push_log(format!(
            "exporting: building the game with the {EXPORT_PROFILE} profile"
        ));
    }
    let task = AsyncComputeTaskPool::get().spawn(async move {
        // The build's own diagnostics already streamed into the progress
        // log this task shares; only the one-line summary travels on.
        let build = build.await.map_err(|err| err.to_string())?;
        if let Some(rejection) = export::dynamic_linking_rejection(&build.dylib_artifacts) {
            return Err(rejection);
        }
        let plan = export::plan_export(&root, EXPORT_PROFILE, &build.binary, None);
        export::stage_export(&plan).map_err(|err| err.to_string())
    });
    (task, progress)
}

/// Report a finished export: latch the outcome into the shared
/// `BuildStatus` the footer and Build panel render, notify, and open the
/// staging directory so the finished export is where the user looks.
fn poll_game_export(world: &mut World) {
    let (task, progress) = {
        let mut exports = world.resource_mut::<GameExports>();
        if !exports
            .task
            .as_ref()
            .is_some_and(bevy::tasks::Task::is_finished)
        {
            return;
        }
        (exports.task.take(), exports.progress.take())
    };
    let Some(task) = task else {
        return;
    };
    match future::block_on(task) {
        Ok(report) => {
            let outcome = export_outcome(&report);
            report_export_success(world, &outcome);
            // Failing to open the folder is not failing to export.
            if let Err(err) = export::reveal_in_file_manager(&report.dist_dir) {
                warn!("could not open the export folder: {err}");
            }
        }
        Err(message) => {
            let log = progress.and_then(|p| p.lock().ok().map(|g| g.full_log.clone()));
            report_export_failure(world, message, log);
        }
    }
}

/// What a finished export reports, and where: the directory and how much
/// of it there is, so the user knows what to look for.
fn export_outcome(report: &ExportReport) -> String {
    format!(
        "exported {} ({} files) to {}",
        report.executable.file_name().map_or_else(
            || report.executable.display().to_string(),
            |name| name.display().to_string()
        ),
        report.files,
        report.dist_dir.display()
    )
}

/// Tell the user the export landed: the footer's success state carries
/// the outcome, the panel shows "Build succeeded - <outcome>", and the
/// notification says it in words.
fn report_export_success(world: &mut World, outcome: &str) {
    {
        let mut status = world.resource_mut::<BuildStatus>();
        status.state = crate::build_status::BuildState::Ready {
            at: Instant::now(),
            components: 0,
        };
        status.outcome = Some(outcome.to_string());
    }
    crate::status_bar::notify_info(world, outcome.to_string());
}

/// Tell the user the export failed, with the whole build output kept for
/// the Build panel — the same failure surface a failed Play build uses.
fn report_export_failure(world: &mut World, message: String, log: Option<String>) {
    {
        let mut status = world.resource_mut::<BuildStatus>();
        status.state = crate::build_status::BuildState::Failed { at: Instant::now() };
        status.outcome = Some(message.clone());
        status.failed_log = log;
    }
    crate::status_bar::notify_error(world, message);
}

/// The export's editor wiring: the resource that carries the one export,
/// polled while a project is open. The operator itself registers through
/// [`add_to_extension`], like every operator.
pub struct GameExportPlugin;

impl Plugin for GameExportPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<GameExports>().add_systems(
            Update,
            poll_game_export.run_if(in_state(crate::AppState::Editor)),
        );
    }
}

pub(crate) fn add_to_extension(ctx: &mut ExtensionContext) {
    ctx.register_operator::<GameExportOp>();
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A finished task that already resolved to `result`.
    fn finished_task<T: Send + 'static>(result: T) -> Task<T> {
        let task = AsyncComputeTaskPool::get_or_init(bevy::tasks::TaskPool::default)
            .spawn(async move { result });
        while !task.is_finished() {
            std::thread::yield_now();
        }
        task
    }

    /// A world with everything the export's status surface reads: the
    /// exports resource, the shared build status, and the notification
    /// the outcome also writes.
    fn export_world() -> World {
        let mut world = World::new();
        world.init_resource::<GameExports>();
        world.init_resource::<BuildStatus>();
        world.init_resource::<crate::status_bar::StatusNotice>();
        world
    }

    #[test]
    fn the_entry_needs_a_project_and_a_free_export_slot() {
        use bevy::ecs::system::RunSystemOnce;
        let mut world = World::new();
        world.init_resource::<GameExports>();
        assert!(
            !world.run_system_once(game_export_is_available).unwrap(),
            "with no project open there is nothing to export"
        );

        world.insert_resource(crate::project::ProjectRoot {
            root: PathBuf::from("my-game"),
            config: default(),
        });
        assert!(
            world.run_system_once(game_export_is_available).unwrap(),
            "an open project and no export in flight is available"
        );

        {
            let mut exports = world.resource_mut::<GameExports>();
            exports.task = Some(finished_task(Ok(ExportReport {
                dist_dir: PathBuf::from("dist"),
                executable: PathBuf::from("dist/game.exe"),
                assets_dir: PathBuf::from("dist/assets"),
                files: 1,
            })));
        }
        assert!(
            !world.run_system_once(game_export_is_available).unwrap(),
            "a second export while one runs greys the entry out"
        );
    }

    /// The footer shows an export's build as a build: while the task
    /// runs, `reconcile_build_status` mirrors its progress sink into
    /// `Building`, exactly as it does for Play's builds.
    #[test]
    fn the_footer_shows_the_export_build_as_a_build() {
        let mut world = export_world();
        world.insert_non_send(crate::pie::PieSession::default());
        {
            let mut exports = world.resource_mut::<GameExports>();
            exports.task = Some(
                AsyncComputeTaskPool::get_or_init(bevy::tasks::TaskPool::default)
                    .spawn(std::future::pending()),
            );
            exports.progress = Some(Arc::new(Mutex::new(BuildProgress::default())));
        }
        crate::pie::reconcile_build_status(&mut world);
        assert!(
            matches!(
                world.resource::<BuildStatus>().state,
                crate::build_status::BuildState::Building { .. }
            ),
            "the export's build drives the footer"
        );

        // Once the export is gone the footer is free again: an export
        // ends by taking the task and its sink out together.
        *world.resource_mut::<GameExports>() = GameExports::default();
        crate::pie::reconcile_build_status(&mut world);
        assert!(
            matches!(
                world.resource::<BuildStatus>().state,
                crate::build_status::BuildState::Idle
            ),
            "no export means no build showing"
        );
    }

    /// A finished export latches the success the panel and notification
    /// show: the ready state carrying the outcome, which names where the
    /// export landed.
    #[test]
    fn a_finished_export_names_where_it_landed() {
        let mut world = export_world();
        report_export_success(
            &mut world,
            &export_outcome(&ExportReport {
                dist_dir: PathBuf::from("my-game/.jackdaw/dist/release"),
                executable: PathBuf::from("my-game/.jackdaw/dist/release/my-game.exe"),
                assets_dir: PathBuf::from("my-game/.jackdaw/dist/release/assets"),
                files: 12,
            }),
        );

        let status = world.resource::<BuildStatus>();
        assert!(matches!(
            status.state,
            crate::build_status::BuildState::Ready { .. }
        ));
        let outcome = status.outcome.as_deref().expect("an outcome");
        assert!(outcome.contains("my-game.exe"), "{outcome}");
        assert!(outcome.contains("12 files"), "{outcome}");
        assert!(
            outcome.contains(".jackdaw/dist/release"),
            "the outcome names the staging directory: {outcome}"
        );
        assert_eq!(
            world.resource::<crate::status_bar::StatusNotice>().text(),
            outcome,
            "the notification says it in words"
        );
    }

    /// A failed export uses the failed-build surface: sticky footer
    /// state, the outcome for the panel header, and the whole build log
    /// kept for the panel body.
    #[test]
    fn a_failed_export_keeps_the_build_log_for_the_panel() {
        let mut world = export_world();
        let mut output = BuildProgress::default();
        output.push_log("error[E0560]: no field (src/lib.rs:40:13)".to_string());
        report_export_failure(
            &mut world,
            "error[E0560]: no field (src/lib.rs:40:13)".to_string(),
            Some(output.full_log.clone()),
        );

        let status = world.resource::<BuildStatus>();
        assert!(matches!(
            status.state,
            crate::build_status::BuildState::Failed { .. }
        ));
        assert!(
            status
                .outcome
                .as_deref()
                .is_some_and(|outcome| outcome.contains("E0560")),
            "the outcome names the error"
        );
        assert!(
            status
                .failed_log
                .as_deref()
                .is_some_and(|log| log.contains("src/lib.rs:40:13")),
            "the compiler output stays for the Build panel"
        );
        assert!(
            world
                .resource::<crate::status_bar::StatusNotice>()
                .text()
                .contains("E0560"),
            "the notification carries the error"
        );
    }

    /// The poll drives a finished task to its report and frees the slot:
    /// the same finished-task mechanics the success helpers above cover
    /// for their half, exercised end to end on the failure path (the
    /// success path also opens the file manager, which a test must not).
    #[test]
    fn the_poll_reports_a_finished_failure_and_frees_the_slot() {
        let mut world = export_world();
        {
            let mut exports = world.resource_mut::<GameExports>();
            exports.task = Some(finished_task(Err(
                "no assets directory at my-game/assets".to_string()
            )));
            exports.root = PathBuf::from("my-game");
        }
        poll_game_export(&mut world);

        assert!(
            world.resource::<GameExports>().task.is_none(),
            "the finished export frees the slot for the next one"
        );
        let status = world.resource::<BuildStatus>();
        assert!(matches!(
            status.state,
            crate::build_status::BuildState::Failed { .. }
        ));
        assert!(
            status
                .outcome
                .as_deref()
                .is_some_and(|outcome| outcome.contains("no assets directory")),
            "the staging refusal reached the user: {:?}",
            status.outcome
        );
    }
}
