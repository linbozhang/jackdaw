//! The crash journal: periodic snapshots of every dirty tab, kept under the
//! editor's state directory so a killed or crashed editor leaves something
//! to recover from.
//!
//! A session owns one directory, `<config>/state/sessions/<project
//! hash>/<pid>-<started>/`, holding a single `journal.json` with one entry
//! per dirty tab. An update system watches the same dirty signal the tab
//! strip reads (`SceneTab::dirty` with the observed undo counters -- no
//! second track) and, once edits have been quiet for
//! [`JOURNAL_DEBOUNCE`], writes a fresh snapshot of **every** dirty tab:
//! the active one emits from the live world through the very emitter its
//! save branch uses, inactive ones from the snapshot their tab already
//! holds (an inactive tab cannot have been edited). A clean exit removes
//! the whole session directory; a crash cannot, which is exactly what
//! makes a leftover directory the "something happened" signal.
//!
//! Terrain sidecar bulk data is deliberately not journaled (a sidecar runs
//! to megabytes): a recovered terrain falls back to its last saved file,
//! and [`JournalFile::terrain_note`] says so where a recovery UI will read
//! it. Journal writes go through `write_atomic`, so an interrupted write
//! leaves the previous snapshot rather than half of the new one.

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash as _, Hasher as _};
use std::path::{Path, PathBuf};

use bevy::prelude::*;
use serde::{Deserialize, Serialize};

use crate::scenes::{Scenes, TabContent, TabKind};
use jackdaw_api_internal::document::write_atomic;

/// How long the dirty state must stay unchanged before a snapshot is
/// written. Killed between edits, at most this much work is unrecoverable.
pub const JOURNAL_DEBOUNCE: std::time::Duration = std::time::Duration::from_secs(2);

/// How many session directories (crash leftovers, normally) to keep under
/// one project before the oldest are swept.
const KEPT_SESSIONS: usize = 5;

const JOURNAL_FILE: &str = "journal.json";

/// The running session's journal state. Absent while no project is open
/// (launcher, headless harnesses), which is what keeps the update system
/// free there.
#[derive(Resource)]
pub struct SessionJournal {
    /// `<state>/sessions/<project hash>/<pid>-<started>`; the directory a
    /// clean exit removes.
    dir: PathBuf,
    /// Dirty-state signature the watcher last saw. A change re-arms the
    /// debounce; no change costs one hash comparison.
    signature: u64,
    /// When the signature last changed, on the app clock. `None` while no
    /// rewrite is pending.
    last_edit: Option<std::time::Duration>,
    /// How many `AppExit` messages had been written when the session
    /// began. Watching the count is how the exit cleaner notices an exit
    /// on the very frame it is written, without an ordering dependency.
    exit_count: usize,
}

/// One journaled tab. `document` is BSN text from the same emitter family
/// the tab's save uses; recovery reads it through the ordinary open chain.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct JournalTab {
    /// The tab's file, as it spells it; `null` for an untitled tab.
    pub path: Option<String>,
    /// `"scene"` or `"prefab"`.
    pub kind: String,
    /// What the tab strip showed for the tab.
    pub display_name: String,
    /// UTC RFC 3339, when this entry was captured.
    pub captured_at: String,
    /// UTC RFC 3339, when the tab last reached disk; `null` if never.
    pub saved_at: Option<String>,
    /// Roots in the journaled document.
    pub entity_count: usize,
    /// The document text itself.
    pub document: String,
}

/// The on-disk journal document.
#[derive(Serialize, Deserialize, Debug)]
pub struct JournalFile {
    /// Bumps when the layout changes incompatibly.
    pub schema: u32,
    /// The jackdaw version that wrote this journal.
    pub editor_version: String,
    /// The process id of the session, also the first half of the directory
    /// name.
    pub pid: u32,
    /// UTC RFC 3339, when the session directory was created.
    pub started: String,
    /// The standing limitation a recovery UI must show: terrain bulk data
    /// is not journaled and recovers to its last save.
    pub terrain_note: String,
    /// One entry per dirty tab, in tab order.
    pub tabs: Vec<JournalTab>,
}

/// Where the sessions of the project at `project_root` live, under the
/// (test-overridable) state directory.
pub fn sessions_root(project_root: &Path) -> Option<PathBuf> {
    let mut hasher = DefaultHasher::new();
    project_root.to_string_lossy().hash(&mut hasher);
    let project = format!("{:016x}", hasher.finish());
    Some(
        jackdaw_env::paths::state_dir()?
            .join("sessions")
            .join(project),
    )
}

/// Start the session for the project at `root`: create its directory under
/// the state tree, sweep crash leftovers beyond [`KEPT_SESSIONS`], and
/// install the resource the update system reads. Call where a project
/// opens; a project that never gets a dirty tab never writes a journal
/// file, only the empty directory.
pub fn begin_session(world: &mut World, root: &Path) {
    let Some(sessions) = sessions_root(root) else {
        return;
    };
    let started_secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|since| since.as_secs())
        .unwrap_or_default();
    let dir = sessions.join(format!("{}-{}", std::process::id(), started_secs));
    if let Err(err) = std::fs::create_dir_all(&dir) {
        warn!("session journal: cannot create {}: {err}", dir.display());
        return;
    }
    rotate_sessions(&sessions);
    let exit_count = world
        .get_resource::<bevy::ecs::message::Messages<bevy::app::AppExit>>()
        .map_or(0, bevy::ecs::message::Messages::len);
    world.insert_resource(SessionJournal {
        dir,
        signature: 0,
        last_edit: None,
        exit_count,
    });
}

/// Every session directory under `sessions`, newest first. A live
/// session's journal rewrites keep its directory fresh (each write is a
/// rename into it), so another instance's directory sorts ahead of dead
/// leftovers; the directory name breaks ties, since a clock that has not
/// ticked between two directories cannot order them.
pub fn list_sessions(sessions: &Path) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(sessions) else {
        return Vec::new();
    };
    let mut listed: Vec<(std::time::SystemTime, String, PathBuf)> = entries
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| path.is_dir())
        .map(|path| {
            let modified = std::fs::metadata(&path)
                .and_then(|meta| meta.modified())
                .unwrap_or(std::time::UNIX_EPOCH);
            let name = path
                .file_name()
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or_default();
            (modified, name, path)
        })
        .collect();
    listed.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| b.1.cmp(&a.1)));
    listed.into_iter().map(|(_, _, path)| path).collect()
}

/// Keep only the newest [`KEPT_SESSIONS`] session directories: older crash
/// leftovers go. Modification time orders them, so a journal another
/// running instance is still writing sorts as alive.
fn rotate_sessions(sessions: &Path) {
    for old in list_sessions(sessions).into_iter().skip(KEPT_SESSIONS) {
        if let Err(err) = std::fs::remove_dir_all(&old) {
            warn!(
                "session journal: cannot sweep old session {}: {err}",
                old.display()
            );
        }
    }
}

/// End the session: drop the resource and remove the directory, journal
/// and all. A clean exit calls this, which is what makes anything left
/// over a crash's residue.
pub fn end_session(world: &mut World) {
    if let Some(journal) = world.remove_resource::<SessionJournal>()
        && let Err(err) = std::fs::remove_dir_all(&journal.dir)
    {
        warn!(
            "session journal: cannot remove {}: {err}",
            journal.dir.display()
        );
    }
}

/// Read a session's journal. A file that does not parse is skipped with a
/// warning and **left on disk** -- a damaged journal is evidence, not
/// garbage, and a recovery entry point must never crash on one.
pub fn read_session_journal(dir: &Path) -> Option<JournalFile> {
    let file = dir.join(JOURNAL_FILE);
    let bytes = std::fs::read(&file).ok()?;
    match serde_json::from_slice::<JournalFile>(&bytes) {
        Ok(journal) => Some(journal),
        Err(err) => {
            warn!(
                "session journal: {} does not parse ({err}); skipping the session, file kept",
                file.display()
            );
            None
        }
    }
}

/// The session directory the running editor owns, if a session is active.
pub fn session_dir(world: &World) -> Option<PathBuf> {
    world
        .get_resource::<SessionJournal>()
        .map(|journal| journal.dir.clone())
}

/// A save landed for the tab at `path`: rewrite the journal so the tab's
/// entry is gone (it is persisted -- there is nothing to recover) and the
/// entries that remain reflect right now. Called from the save boundary,
/// where the tab's clean baseline is written.
pub fn on_tab_saved(world: &mut World, path: &Path) {
    if world.get_resource::<SessionJournal>().is_none() {
        return;
    }
    info!(
        "session journal: {} reached disk; dropping its entry",
        path.display()
    );
    write_snapshot(world);
}

/// Watch for the app exiting and remove the session directory on the very
/// frame the exit is written -- before the runner stops and no system runs
/// again. Lives in `Last` so it sees exits queued through deferred
/// commands earlier in the frame too.
pub fn end_session_on_app_exit(world: &mut World) {
    let Some(journal) = world.get_resource::<SessionJournal>() else {
        return;
    };
    let exit_count = journal.exit_count;
    let exited = world
        .get_resource::<bevy::ecs::message::Messages<bevy::app::AppExit>>()
        .map(|messages| messages.len() > exit_count)
        .unwrap_or(false);
    if exited {
        end_session(world);
    }
}

/// The per-frame watcher. Exclusive because a snapshot emits the live
/// document, which takes the world.
pub fn session_journal_system(world: &mut World) {
    if world.get_resource::<SessionJournal>().is_none() {
        return;
    }

    let signature = dirty_signature(world);
    let now = world.resource::<Time>().elapsed();
    let any_dirty = world.resource::<Scenes>().tabs.iter().any(|tab| tab.dirty);
    let Some(mut journal) = world.get_resource_mut::<SessionJournal>() else {
        return;
    };
    if journal.signature != signature {
        journal.signature = signature;
        journal.last_edit = Some(now);
        return;
    }
    if !any_dirty {
        // Nothing recoverable: drop the journal file rather than wait out
        // the debounce with stale entries on disk. The session directory
        // stays as the marker of a live editor.
        if journal.last_edit.is_some() {
            journal.last_edit = None;
            let _ = std::fs::remove_file(journal.dir.join(JOURNAL_FILE));
        }
        return;
    }
    let Some(last_edit) = journal.last_edit else {
        return; // quiet, and already written
    };
    if now.saturating_sub(last_edit) < JOURNAL_DEBOUNCE {
        return;
    }
    journal.last_edit = None;
    write_snapshot_deferred(world);
}

/// Hash of everything about the tab strip the journal reacts to: which
/// tabs are dirty and how far each one's editing history has moved. This
/// is the T03 dirty signal verbatim, not a parallel track.
fn dirty_signature(world: &World) -> u64 {
    let mut hasher = DefaultHasher::new();
    let scenes = world.resource::<Scenes>();
    scenes.tabs.len().hash(&mut hasher);
    for tab in &scenes.tabs {
        tab.dirty.hash(&mut hasher);
        tab.observed_pushes.hash(&mut hasher);
        tab.observed_undo_len.hash(&mut hasher);
    }
    hasher.finish()
}

/// Collect and write the snapshot for every dirty tab, synchronously, and
/// reset the watcher so the next edit re-arms the debounce. Used where a
/// save just landed (the entry must be spent on the same boundary) and by
/// tests; the debounce path goes through [`write_snapshot_deferred`]
/// instead, which keeps the write off the interactive frame.
pub fn write_snapshot(world: &mut World) {
    let Some(journal_dir) = world
        .get_resource::<SessionJournal>()
        .map(|journal| journal.dir.clone())
    else {
        return;
    };
    let Some(document) = collect_entries(world) else {
        return;
    };
    persist(&journal_dir, &document);
    note_written(world);
}

/// The debounce path: collect on the main thread (the emit needs the
/// world) and hand serialization and the disk write to the IO pool, so an
/// editing frame pays the emit and nothing else. The write is a
/// whole-file overwrite, so an in-flight write at most delivers one
/// slightly stale snapshot; the next quiet period replaces it.
pub fn write_snapshot_deferred(world: &mut World) {
    let Some(journal_dir) = world
        .get_resource::<SessionJournal>()
        .map(|journal| journal.dir.clone())
    else {
        return;
    };
    let Some(document) = collect_entries(world) else {
        return;
    };
    bevy::tasks::IoTaskPool::get()
        .spawn(async move {
            persist(&journal_dir, &document);
        })
        .detach();
    note_written(world);
}

/// Record that the watcher is quiet again.
fn note_written(world: &mut World) {
    let signature = dirty_signature(world);
    if let Some(mut journal_state) = world.get_resource_mut::<SessionJournal>() {
        journal_state.signature = signature;
        journal_state.last_edit = None;
    }
}

/// Gather one journal document from every dirty tab, or `None` when no
/// session is active. An empty `tabs` list is a valid document: it says
/// there is nothing to recover.
fn collect_entries(world: &mut World) -> Option<JournalFile> {
    let captured_at = crate::timestamps::utc_rfc3339_now();
    let mut tabs = Vec::new();
    let (active, infos): (usize, Vec<TabInfo>) = {
        let scenes = world.resource::<Scenes>();
        (
            scenes.active,
            scenes
                .tabs
                .iter()
                .map(|tab| TabInfo {
                    path: tab.path.clone(),
                    display_name: tab.display_name.clone(),
                    kind: matches!(tab.kind, TabKind::Prefab),
                    dirty: tab.dirty,
                    refused: tab.is_refused(),
                    saved_at: tab.saved_at.clone(),
                })
                .collect(),
        )
    };
    for (index, info) in infos.iter().enumerate() {
        if !info.dirty || info.refused {
            continue;
        }
        if let Some(entry) = journal_entry(world, index, active, info, &captured_at) {
            tabs.push(entry);
        }
    }
    Some(JournalFile {
        schema: 1,
        editor_version: jackdaw_project_build::VERSION.to_string(),
        pid: std::process::id(),
        started: captured_at,
        terrain_note: "Terrain bulk data is not journaled; a recovered terrain \
                       falls back to its last saved file."
            .to_string(),
        tabs,
    })
}

/// Put `document` under `journal_dir`: an empty tab list removes the
/// journal file, anything else writes it atomically (compact: the `.bak`
/// next to it is the readable copy of the previous snapshot).
fn persist(journal_dir: &Path, document: &JournalFile) {
    if document.tabs.is_empty() {
        let _ = std::fs::remove_file(journal_dir.join(JOURNAL_FILE));
        return;
    }
    let Ok(bytes) = serde_json::to_vec(document) else {
        warn!("session journal: cannot serialize the snapshot");
        return;
    };
    if let Err(err) = write_atomic(&journal_dir.join(JOURNAL_FILE), &bytes) {
        warn!("session journal: cannot write the snapshot: {err}");
    }
}

/// What the snapshot collector needs to know about a tab, copied out so
/// the world can be borrowed for the emit.
struct TabInfo {
    path: Option<PathBuf>,
    display_name: String,
    kind: bool,
    dirty: bool,
    refused: bool,
    saved_at: Option<String>,
}

/// One tab's journal entry. The active tab emits from the live world
/// through its save branch's emitter; an inactive tab emits the snapshot
/// its tab holds (nothing can have edited it while inactive).
fn journal_entry(
    world: &mut World,
    index: usize,
    active: usize,
    info: &TabInfo,
    captured_at: &str,
) -> Option<JournalTab> {
    let parent = info
        .path
        .as_ref()
        .and_then(|path| path.parent().map(Path::to_path_buf))
        .unwrap_or_else(|| PathBuf::from("."));
    let (document, entity_count) = if index == active {
        live_emit(world, info, &parent)
    } else {
        stashed_emit(world, index, info, &parent)
    }?;
    Some(JournalTab {
        path: info
            .path
            .as_ref()
            .map(|path| path.to_string_lossy().into_owned()),
        kind: (if info.kind { "prefab" } else { "scene" }).to_string(),
        display_name: info.display_name.clone(),
        captured_at: captured_at.to_string(),
        saved_at: info.saved_at.clone(),
        entity_count,
        document,
    })
}

/// The active tab, from the live world, through the same emitter its save
/// branch uses: `emit_bsn_scene_for_file` for a scene,
/// `emit_bsn_scene_with_inline_assets` plus the prefab file pipeline for a
/// prefab.
fn live_emit(world: &mut World, info: &TabInfo, parent: &Path) -> Option<(String, usize)> {
    if !info.kind {
        let text = match crate::scene_io::save::emit_bsn_scene_for_file(world, parent) {
            Ok(text) => text,
            Err(reason) => {
                // A document the file pipeline would refuse still deserves
                // a recovery snapshot; fall back to the capture emitter.
                warn!("session journal: scene emit refused ({reason}); snapshotting as held");
                crate::scene_io::save::emit_bsn_scene_with_inline_assets(world, parent)
            }
        };
        let count = world
            .get_resource::<jackdaw_bsn::SceneBsnAst>()
            .map(|ast| ast.roots.len())
            .unwrap_or(0);
        return Some((text, count));
    }
    // The same pipeline save_prefab_to_disk runs: inline-asset emit,
    // relativize against the file, wrap as an asset document.
    let text = crate::scene_io::save::emit_bsn_scene_with_inline_assets(world, parent);
    let mut ast = match jackdaw_bsn::parse_bsn_text(&text) {
        Ok(ast) => ast,
        Err(err) => {
            warn!("session journal: prefab snapshot parse failed: {err}");
            return None;
        }
    };
    let count = ast.roots.len();
    crate::prefab::save_load::relativize_for_file(world, &mut ast, parent);
    let wrapped = crate::asset_files::asset_file_text(
        crate::prefab::resolver_bsn::PREFAB_TYPE,
        &jackdaw_bsn::emit_scene(&ast),
    );
    Some((wrapped, count))
}

/// An inactive tab, from the snapshot it holds: the captured AST for a
/// scene tab, the cache entry for a prefab one. An inactive tab cannot
/// have been edited, so this is its latest state.
fn stashed_emit(
    world: &mut World,
    index: usize,
    info: &TabInfo,
    parent: &Path,
) -> Option<(String, usize)> {
    // Copy the handle out first (a path for prefabs, a deep clone of the
    // document for scenes), so the world borrow ends before the emit.
    enum Stash {
        Scene(Box<jackdaw_bsn::SceneBsnAst>),
        Prefab(crate::prefab::CanonicalPrefabPath),
    }
    let stash = {
        let scenes = world.resource::<Scenes>();
        match &scenes.tabs[index].content {
            TabContent::Scene(Some(ast)) => Stash::Scene(Box::new(ast.deep_clone())),
            TabContent::Scene(None) => {
                warn!(
                    "session journal: tab {} ('{}') holds no snapshot to journal",
                    index, info.display_name
                );
                return None;
            }
            TabContent::Prefab(path) => Stash::Prefab(path.clone()),
        }
    };
    match stash {
        Stash::Scene(ast) => {
            let count = ast.roots.len();
            Some((jackdaw_bsn::emit_scene(&ast), count))
        }
        Stash::Prefab(canonical) => {
            let mut ast = {
                let cache = world.resource::<crate::prefab::PrefabAstCache>();
                cache
                    .get_canonical(&canonical)
                    .map(crate::prefab::resolver_bsn::clone_scene)
            }?;
            let count = ast.roots.len();
            crate::prefab::save_load::relativize_for_file(world, &mut ast, parent);
            let wrapped = crate::asset_files::asset_file_text(
                crate::prefab::resolver_bsn::PREFAB_TYPE,
                &jackdaw_bsn::emit_scene(&ast),
            );
            Some((wrapped, count))
        }
    }
}
