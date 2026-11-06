//! Multi-scene editor state. Owns the tab list; the active tab's
//! contents live in the live Bevy world, inactive tabs hold a
//! scene-document snapshot plus the per-tab view state and history.

pub mod confirm_dialog;
pub mod external_watch;
pub mod load_progress;
pub mod operators;
pub mod recovery_dialog;
pub mod swap;
pub mod ui;

use std::path::PathBuf;

use bevy::prelude::*;

use crate::commands::CommandHistory;
use crate::project::ProjectRoot;
use crate::terrain_mode::TerrainDataStore;
use jackdaw_api_internal::document::{SceneResource, SceneResourceValue};

pub struct ScenesPlugin;

impl Plugin for ScenesPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<Scenes>();
        load_progress::plugin(app);
        recovery_dialog::plugin(app);
        app.init_resource::<confirm_dialog::PendingTabClose>();
        app.init_resource::<confirm_dialog::PendingQuit>();
        app.add_systems(
            Update,
            (
                mark_active_dirty_on_history_growth,
                persist_tabs_to_project_config,
                ui::rebuild_scene_tab_strip,
                ui::update_scene_tab_visuals,
                ui::update_scene_tab_label_abbreviation,
                ui::show_scene_tab_close_on_hover,
                intercept_window_close,
            ),
        );
        app.add_observer(ui::on_scene_tab_context_action);
        app.add_plugins(external_watch::ExternalSceneWatchPlugin);
    }
}

/// Intercept `WindowCloseRequested`. If any tab is dirty — or a
/// definition-asset card holds unsaved edits — show the confirm-quit
/// dialog and consume the event. Otherwise emit `AppExit::Success`
/// so the normal X-click flow still works.
pub fn intercept_window_close(
    mut close_events: bevy::ecs::message::MessageReader<bevy::window::WindowCloseRequested>,
    mut exit: bevy::ecs::message::MessageWriter<bevy::app::AppExit>,
    scenes: Res<Scenes>,
    asset_edits: Query<&crate::definition_assets::DefinitionAssetEdit>,
    mut commands: Commands,
    mut pending: ResMut<confirm_dialog::PendingQuit>,
) {
    let mut close_requested = false;
    for _ in close_events.read() {
        close_requested = true;
    }
    if !close_requested {
        return;
    }

    let any_dirty =
        scenes.tabs.iter().any(|t| t.dirty) || asset_edits.iter().any(|edit| edit.dirty);
    if !any_dirty {
        exit.write(bevy::app::AppExit::Success);
        return;
    }

    // Dialog already open; ignore the repeated event.
    if pending.active {
        return;
    }
    pending.active = true;
    pending.leaving_project = false;

    commands.queue(|world: &mut World| {
        confirm_dialog::spawn_confirm_quit_dialog(world);
    });
}

#[derive(Resource, Default)]
pub struct Scenes {
    pub tabs: Vec<SceneTab>,
    pub active: usize,
}

impl Scenes {
    /// Append a tab and return its index. Does not activate it.
    pub fn push_tab(&mut self, tab: SceneTab) -> usize {
        let idx = self.tabs.len();
        self.tabs.push(tab);
        idx
    }
}

#[derive(Default, Clone, Debug, PartialEq, Eq)]
pub enum TabKind {
    #[default]
    Scene,
    Prefab,
}

/// What a tab holds when it isn't the active tab.
///
/// `Scene` owns its AST directly. `Prefab` keys into `PrefabAstCache`
/// instead, so the cache stays the single source of truth for prefab
/// content and a prefab tab can't drift from the cache entry.
pub enum TabContent {
    /// Scene document. `None` is the just-pushed / never-captured state
    /// for an untitled tab; `Some` is what `capture_active_tab` stores
    /// during a swap. Boxed: the document holds a whole ECS world, so the
    /// variant would otherwise dwarf `Prefab` (a path).
    Scene(Option<Box<jackdaw_bsn::SceneBsnAst>>),
    /// Prefab document. The AST lives in `PrefabAstCache`, keyed by
    /// this canonical path. Capturing flushes the live scene document
    /// into the cache entry; activating installs the cache entry back
    /// into the live world.
    Prefab(crate::prefab::CanonicalPrefabPath),
}

impl Default for TabContent {
    fn default() -> Self {
        Self::Scene(None)
    }
}

pub struct SceneTab {
    pub path: Option<PathBuf>,
    pub display_name: String,
    pub dirty: bool,
    pub kind: TabKind,
    pub content: TabContent,
    pub view_state: ViewState,
    pub history: CommandHistory,
    /// Decoded terrain sidecars owned by this tab while it is inactive.
    /// The active tab's store lives in the world as a resource instead.
    pub terrain_data_store: TerrainDataStore,
    /// Extensions' [`SceneResource`] values owned by this tab while it is
    /// inactive, like the terrain data.
    pub scene_resources: TabResources,
    /// Undo-stack state the dirty watcher last observed for this tab. Both
    /// are compared before anything else happens: when neither moved since
    /// the last look, the frame costs nothing, no matter what the stack's
    /// depth is relative to the save point.
    pub observed_undo_len: usize,
    /// [`Self::observed_undo_len`]'s companion: the history's monotonic
    /// **scene-document** push counter as the watcher last saw it. It
    /// moves on new scene edits even when budget trimming keeps the
    /// stack's length flat, so growth is never missed; entries that do
    /// not write the scene document (asset fields, session resources)
    /// do not move it, so sharing the history cannot mark the tab dirty.
    pub observed_pushes: u64,
    /// The undo stack's length at the last save or load: the depth the
    /// document on disk corresponds to.
    pub saved_undo_len: usize,
    /// [`Self::saved_undo_len`]'s companion: the scene-document push
    /// counter as it stood at the last save or load. A stack sitting
    /// above the saved depth because of non-scene pushes (asset
    /// fields, session resources) has not moved this — so the watcher
    /// reads "the document itself did not change" and leaves the tab
    /// clean.
    pub saved_scene_pushes: u64,
    /// Fingerprint of the document content as it was written at the last
    /// save (or read at load), hashed from the same emitter a save uses.
    /// When the stack returns to `saved_undo_len`, the current document is
    /// re-emitted and compared against this, so "undo back to the saved
    /// content" reads clean while "undo then a different edit at the same
    /// depth" reads dirty. `None` until the tab has a baseline (a fresh
    /// untitled tab), where growth alone decides.
    pub saved_doc_hash: Option<u64>,
    /// When this tab's document last reached disk, as a UTC RFC 3339
    /// string. `None` until a save does (the crash journal reports it, so
    /// a recovery preview can say how far back the journaled edit is).
    pub saved_at: Option<String>,
    /// Why the tab is in front without its contents in the world, if it is.
    /// Set, the world is not the file's contents and must not be written back.
    pub refusal: Option<TabRefusal>,
}

/// Why an activation refused to put a tab's document in the world. The next
/// successful activation clears it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TabRefusal {
    /// The document names vocabulary this build will not spawn.
    Rejected(String),
    /// The spawn was attempted and failed.
    SpawnFailed(String),
}

impl TabRefusal {
    /// The message shown for a save this refusal blocks.
    pub fn reason(&self) -> &str {
        match self {
            Self::Rejected(reason) | Self::SpawnFailed(reason) => reason,
        }
    }
}

impl SceneTab {
    /// Whether writing this tab's file would write a world that never held it.
    pub fn is_refused(&self) -> bool {
        self.refusal.is_some()
    }

    pub fn new_untitled(n: u32) -> Self {
        Self {
            path: None,
            display_name: format!("untitled-{n}"),
            dirty: false,
            kind: TabKind::Scene,
            content: TabContent::default(),
            view_state: ViewState::with_default_camera(),
            history: CommandHistory::default(),
            terrain_data_store: TerrainDataStore::default(),
            scene_resources: TabResources::default(),
            observed_undo_len: 0,
            observed_pushes: 0,
            saved_undo_len: 0,
            saved_scene_pushes: 0,
            saved_doc_hash: None,
            saved_at: None,
            refusal: None,
        }
    }

    /// Record `history`'s current state as what the watcher last observed,
    /// so the next frame's fast path skips. Call when a tab is activated or
    /// a baseline (save / load) is written. The push counter is the
    /// scene-document one: the watcher judges tab dirtiness against it.
    pub fn observe_history(&mut self, history: &CommandHistory) {
        self.observed_undo_len = history.undo_stack.len();
        self.observed_pushes = history.scene_pushes();
    }
}

/// Extensions' [`SceneResource`] values, keyed by resource type.
pub type TabResources = std::collections::HashMap<std::any::TypeId, SceneResourceValue>;

fn scene_resources(world: &mut World) -> Vec<SceneResource> {
    world
        .query::<&SceneResource>()
        .iter(world)
        .copied()
        .collect()
}

/// Take every extension's [`SceneResource`] out of the world, for the tab
/// going inactive.
pub(crate) fn take_scene_resources(world: &mut World) -> TabResources {
    scene_resources(world)
        .into_iter()
        .filter_map(|resource| Some((resource.type_id(), resource.take(world)?)))
        .collect()
}

/// Put back the values a tab took with it, and the default for any it has
/// none of.
pub(crate) fn restore_scene_resources(world: &mut World, mut values: TabResources) {
    for resource in scene_resources(world) {
        let value = values.remove(&resource.type_id());
        resource.restore(world, value);
    }
}

/// Reset every extension's [`SceneResource`], for a scene leaving the world
/// with nowhere to keep it.
pub(crate) fn reset_scene_resources(world: &mut World) {
    restore_scene_resources(world, TabResources::default());
}

/// When `Scenes` mutates, mirror the open-tab paths into the project
/// config so they survive across sessions. Skipped if no project root
/// is loaded (e.g. project-selector screen, headless tests).
pub fn persist_tabs_to_project_config(
    scenes: Res<Scenes>,
    project_root: Option<ResMut<ProjectRoot>>,
) {
    if !scenes.is_changed() {
        return;
    }
    let Some(mut project_root) = project_root else {
        return;
    };

    let last_open_tabs: Vec<String> = scenes
        .tabs
        .iter()
        .filter_map(|t| t.path.as_ref())
        .filter_map(|p| project_root.to_relative(p).to_str().map(str::to_owned))
        .collect();
    let last_active_tab = scenes.active;

    let cfg = &mut project_root.config;
    if cfg.last_open_tabs == last_open_tabs && cfg.last_active_tab == last_active_tab {
        return;
    }
    cfg.last_open_tabs = last_open_tabs;
    cfg.last_active_tab = last_active_tab;

    let root = project_root.root.clone();
    let project = project_root.config.clone();
    if let Err(e) = crate::project::save_project_config(&root, &project) {
        warn!("Failed to persist tab list to project.jsn: {e}");
    }
}

/// Per-frame system: keep the active tab's `dirty` flag in step with its
/// history.
///
/// The fast path compares the stack's length and the history's monotonic
/// push counter against what the tab last observed; when neither moved, the
/// frame costs nothing. When either moved, the flag is re-decided:
///
/// - With a save baseline (`saved_doc_hash`), the flag is `len !=
///   saved_undo_len`, or — when the stack sits exactly at the saved depth —
///   a content comparison: the document is emitted the way a save emits it
///   and hashed against the fingerprint the save left. Undoing back to the
///   saved content reads clean; undoing *past* a save, or landing on the
///   same depth with different content, reads dirty. The emit only happens
///   on the frame the stack arrived at the saved depth, so the steady state
///   stays O(1).
/// - Without a baseline (a fresh untitled tab), growth alone decides: new
///   pushes dirty the tab and nothing undirties it, the pre-existing
///   behaviour.
///
/// The push counter, not the length, is what growth is read from, so budget
/// trimming dropping the oldest entries can never hide a real edit. And the
/// baseline lives on the tab, so a tab switch can never judge one tab's
/// stack against another tab's save point.
///
/// The content comparison needs `&mut World` (the emit suspends preview
/// writes), so it runs in a queued command at the frame's sync point rather
/// than making this system exclusive; an exclusive system would reshape the
/// whole Update schedule for every unrelated system.
pub fn mark_active_dirty_on_history_growth(
    history: Res<CommandHistory>,
    mut scenes: ResMut<Scenes>,
    mut commands: Commands,
) {
    if scenes.tabs.is_empty() {
        return;
    }
    let active = scenes.active;
    let current_len = history.undo_stack.len();
    // The scene-document counter: an asset-field or session-resource
    // entry shares this history and moves the stack, but it is not a
    // scene edit and must not flip this tab's dirty flag.
    let current_pushes = history.scene_pushes();
    let tab = scenes.bypass_change_detection().tabs.get_mut(active);
    let Some(tab) = tab else { return };
    if current_len == tab.observed_undo_len && current_pushes == tab.observed_pushes {
        return;
    }
    let saved_undo_len = tab.saved_undo_len;
    let saved_scene_pushes = tab.saved_scene_pushes;
    let saved_doc_hash = tab.saved_doc_hash;
    let was_dirty = tab.dirty;
    let grew = current_pushes > tab.observed_pushes;

    if let Some(saved_hash) = saved_doc_hash
        && current_len == saved_undo_len
    {
        // Back at the saved depth: equal content means clean, anything else
        // (a different edit at the same depth) means dirty. Decided by a
        // queued emit, so this system stays out of the schedule's way. If
        // the emit is impossible the flag stays where it is.
        commands.queue(move |world: &mut World| {
            let Some(current) = crate::scene_io::document_fingerprint(world) else {
                return;
            };
            let Some(mut scenes) = world.get_resource_mut::<Scenes>() else {
                return;
            };
            if scenes.tabs.len() <= active {
                return;
            }
            scenes.set_changed();
            scenes.tabs[active].dirty = current != saved_hash;
        });
        scenes.bypass_change_detection().tabs[active].observed_undo_len = current_len;
        scenes.bypass_change_detection().tabs[active].observed_pushes = current_pushes;
        return;
    }

    // Away from the saved depth — unsaved edits above it, an undo past it,
    // or no baseline at all (where growth dirties and nothing cleans).
    // Above the saved depth, only scene-document pushes can have moved
    // the document: a stack that climbed on asset-field or
    // session-resource entries alone (scene_pushes still at its saved
    // baseline) leaves the tab clean. Below it, an undo withdrew a
    // scene command, which changed the document — dirty.
    let needs_dirty_flip = match saved_doc_hash {
        Some(_) => {
            let below = current_len < saved_undo_len;
            let scene_grew_since_save = current_pushes > saved_scene_pushes;
            (below || scene_grew_since_save) && !was_dirty
        }
        None => grew && !was_dirty,
    };
    if !needs_dirty_flip {
        scenes.bypass_change_detection().tabs[active].observed_undo_len = current_len;
        scenes.bypass_change_detection().tabs[active].observed_pushes = current_pushes;
        return;
    }
    scenes.set_changed();
    let tab = &mut scenes.tabs[active];
    tab.dirty = true;
    tab.observed_undo_len = current_len;
    tab.observed_pushes = current_pushes;
}

#[derive(Default, Clone)]
pub struct ViewState {
    pub camera_transform: Transform,
    /// Optional projection matrix. `None` means use the editor's default
    /// perspective on restore. Stored as a `Mat4` so we don't have to
    /// reflect the entire `Projection` enum across tab swaps.
    pub camera_projection: Option<bevy::math::Mat4>,
    pub edit_mode: crate::brush::EditMode,
    /// Object-level selection stored as scene node ids so it survives
    /// the despawn / respawn cycle of a tab swap.
    pub selection: Vec<jackdaw_scene_types::SceneNodeId>,
    /// Brush sub-element selection (verts, edges, faces) for whichever
    /// brush is active in `selection`.
    pub brush_sub_selection: crate::brush::BrushSelection,
    /// How the 2D viewport was framed while this tab was active. `None` means
    /// no framing was ever chosen, so the tab takes whatever its next
    /// activation gives it.
    pub ui_view: Option<crate::viewport_2d::Ui2dView>,
    /// The viewport mode the user picked for this tab, overriding the one its
    /// scene kind asks for. `None` falls back to the document's kind.
    pub viewport_mode: Option<crate::viewport_host::ViewportMode>,
}

impl ViewState {
    /// Default `ViewState` for a freshly-created tab. Uses the same
    /// initial camera framing as the viewport setup (looking at the
    /// origin from `(0, 4, 8)`), so a new untitled scene shows the
    /// grid + axes instead of the camera sitting on the origin and
    /// rendering the grid edge-on.
    pub fn with_default_camera() -> Self {
        Self {
            camera_transform: Transform::from_xyz(0.0, 4.0, 8.0)
                .looking_at(bevy::math::Vec3::ZERO, bevy::math::Vec3::Y),
            ..Self::default()
        }
    }
}
