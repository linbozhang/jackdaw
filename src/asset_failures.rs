//! What the editor tells the author when an asset fails to load (AR3).
//!
//! The engine reports failures two ways: the load state of the handle turns
//! `Failed`, and [`UntypedAssetLoadFailedEvent`] carries the path and the
//! error to anyone listening. Nobody was listening. A file an external tool
//! rewrote into something unloadable then failed its reload silently -- the
//! viewport, the inspector and the thumbnails all kept showing the previous
//! content (that is the engine's own rule: a failed reload never removes the
//! old value), so the author had no way to tell the write had not landed.
//! This module is the listener: one warning per failed path on the status bar
//! and in the log, naming the file, the reason, and what the editor is doing
//! about it — and, since the scene-problems list grew a load-failure section
//! (W3), a row that stays on the board instead of burning with the notice.
//!
//! The rule is once per *(path, mtime)*, the same key the thumbnail failures
//! use: the same broken file warns once no matter how many load attempts
//! fail against it, and a file rewritten since -- fixed, or broken in a new
//! way -- speaks again. The lock clears itself by changing keys; there is no
//! bookkeeping to run when a file recovers, because a recovered file raises
//! no failure at all.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use bevy::asset::UntypedAssetLoadFailedEvent;
use bevy::prelude::*;

use crate::project::ProjectRoot;

/// One load failure the session has spoken of: the file on disk, the asset
/// path it loaded under, and the engine's reason. The row is the panel face
/// of the once-per-*(path, mtime)* lock (W3: the status-bar notice was the
/// only face, and it burned after one line).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LoadFailureRow {
    pub file: PathBuf,
    pub named: String,
    pub error: String,
}

/// The (path, mtime) pairs a failure was reported for during this session,
/// with the rows those reports left behind for the scene-problems list.
#[derive(Resource, Default)]
pub struct WarnedFailures {
    reported: HashSet<(PathBuf, Option<SystemTime>)>,
    rows: Vec<LoadFailureRow>,
}

impl WarnedFailures {
    /// Whether a failure of the file at `path`, as it stands on disk now
    /// (`mtime`), has been reported already.
    pub fn is_reported(&self, path: &Path, mtime: Option<SystemTime>) -> bool {
        self.reported.contains(&(path.to_path_buf(), mtime))
    }

    /// The failure rows, oldest first — the list the panel renders.
    pub fn rows(&self) -> &[LoadFailureRow] {
        &self.rows
    }

    /// Lock one failure in and keep its row. Answers whether this key is
    /// new (the caller speaks).
    fn insert(&mut self, file: PathBuf, mtime: Option<SystemTime>, row: LoadFailureRow) -> bool {
        if !self.reported.insert((file, mtime)) {
            return false;
        }
        self.rows.push(row);
        true
    }

    /// How many distinct failures are on record. The tests count them, since
    /// a quiet second report looks exactly like a loud one.
    #[cfg(test)]
    fn len(&self) -> usize {
        self.reported.len()
    }
}

/// The file a failure's asset path names on disk: under the open project's
/// assets when there is one, spelled as the path says otherwise.
fn on_disk(project: Option<&ProjectRoot>, asset_path: &Path) -> PathBuf {
    match project {
        Some(project) => project.assets_dir().join(asset_path),
        None => asset_path.to_path_buf(),
    }
}

pub(crate) fn plugin(app: &mut App) {
    app.init_resource::<WarnedFailures>().add_systems(
        Update,
        report_failed_loads.run_if(in_state(crate::AppState::Editor)),
    );
}

fn report_failed_loads(
    mut failures: MessageReader<UntypedAssetLoadFailedEvent>,
    mut warned: ResMut<WarnedFailures>,
    project: Option<Res<ProjectRoot>>,
    mut commands: Commands,
) {
    for failure in failures.read() {
        let file = on_disk(project.as_deref(), failure.path.path());
        let mtime = std::fs::metadata(&file)
            .and_then(|meta| meta.modified())
            .ok();
        let named = failure.path.path().to_string_lossy().into_owned();
        let error = failure.error.to_string();
        if !warned.insert(
            file.clone(),
            mtime,
            LoadFailureRow {
                file: file.clone(),
                named: named.clone(),
                error: error.clone(),
            },
        ) {
            continue;
        }
        warn!(
            "asset load failed: {} ({}) -- showing the previous content",
            file.display(),
            failure.error
        );
        commands.queue(move |world: &mut World| {
            crate::status_bar::notify_warn(
                world,
                format!("{named} failed to load; showing the previous content"),
            );
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use bevy::asset::AssetLoadError;
    use bevy::ecs::system::RunSystemOnce as _;

    /// A failure message the engine would send for `path`.
    fn failure(named: &str) -> UntypedAssetLoadFailedEvent {
        UntypedAssetLoadFailedEvent {
            id: Handle::<Image>::default().id().untyped(),
            path: bevy::asset::AssetPath::from_path_buf(PathBuf::from(named)),
            error: AssetLoadError::MissingAssetLoader {
                asset_type_id: None,
                asset_path: named.to_string(),
            },
        }
    }

    fn with_file(dir: &Path, named: &str, contents: &[u8]) -> PathBuf {
        let file = dir.join(named);
        std::fs::write(&file, contents).expect("the file is written");
        file
    }

    fn report(world: &mut World, named: &str) {
        world
            .resource_mut::<Messages<UntypedAssetLoadFailedEvent>>()
            .write(failure(named));
        world
            .run_system_once(report_failed_loads)
            .expect("the listener ran");
    }

    /// One failed path is named once on the status bar and in the warned set;
    /// the same failure again stays quiet; a rewritten file speaks again.
    #[test]
    fn a_failure_warns_once_per_path_and_again_after_the_file_changes() {
        let tmp = tempfile::tempdir().expect("tempdir");
        let assets = tmp.path().join("assets");
        std::fs::create_dir_all(&assets).expect("the assets tree is made");
        let file = with_file(&assets, "broken.png", b"not a png");
        let mut world = World::new();
        world.init_resource::<WarnedFailures>();
        world.init_resource::<Messages<UntypedAssetLoadFailedEvent>>();
        world.init_resource::<crate::status_bar::StatusNotice>();
        world.insert_resource(crate::project::ProjectRoot {
            root: tmp.path().to_path_buf(),
            config: crate::project::ProjectConfig::default(),
        });

        report(&mut world, "broken.png");

        let warned = world.resource::<WarnedFailures>();
        let mtime = std::fs::metadata(&file)
            .and_then(|meta| meta.modified())
            .ok();
        assert!(
            warned.is_reported(file.as_path(), mtime),
            "the failure is on record"
        );
        assert_eq!(
            world.resource::<crate::status_bar::StatusNotice>().text(),
            "broken.png failed to load; showing the previous content",
            "the status bar names the file and what the editor does"
        );
        assert_eq!(warned.len(), 1);
        // The row the panel renders: the file, the asset path, the reason.
        let rows = world.resource::<WarnedFailures>().rows();
        assert_eq!(rows.len(), 1, "one failure, one row: {rows:?}");
        assert_eq!(rows[0].file, file);
        assert_eq!(rows[0].named, "broken.png");
        assert!(!rows[0].error.is_empty());

        // The same broken file, failing again (a retried load, another
        // dependent asking for it): already reported, stays quiet.
        report(&mut world, "broken.png");
        assert_eq!(
            world.resource::<WarnedFailures>().len(),
            1,
            "the same file at the same mtime is not reported twice"
        );
        assert_eq!(
            world.resource::<WarnedFailures>().rows().len(),
            1,
            "the quiet repeat adds no row either"
        );

        // The file is rewritten -- fixed or broken differently, the editor
        // cannot tell; either way it speaks again rather than staying quiet
        // for the rest of the session.
        std::thread::sleep(std::time::Duration::from_millis(20));
        with_file(&assets, "broken.png", b"still not a png");
        report(&mut world, "broken.png");
        assert_eq!(
            world.resource::<WarnedFailures>().len(),
            2,
            "a file rewritten since its failure is a new subject"
        );
    }
}
