//! Play the scene the editor has in front.
//!
//! `pie.play` keeps its startup-scene meaning: launch the game and let it
//! load whatever its own code loads. This module owns the other half,
//! `pie.play_current`: resolve the scene tab in front, apply the project's
//! unsaved-changes policy (save / ask / play an unsaved copy), and hand the
//! game the result through the `JACKDAW_PIE_SCENE` override, so any open
//! scene — named, dirty, or never saved — can run.
//!
//! An unsaved scene runs from a temporary copy under
//! `<assets>/.jackdaw-pie/`: a dot-prefixed directory the asset walks skip,
//! written through the same atomic write a save uses but deliberately kept
//! out of the save journal, since it is a run artifact, not editor state.
//! The copy is deleted when play stops and swept away at project open, so
//! nothing accumulates.

use std::path::{Path, PathBuf};

use bevy::picking::events::PointerClick;
use bevy::prelude::*;
use jackdaw_api::pie::PlayState;
use jackdaw_api::prelude::*;
use jackdaw_feathers::{icons::EditorFont, tokens};
use jackdaw_pie_protocol::manifest::RunConfig;

use crate::pie::{InstanceKey, launch_instance_with_override};
use crate::project_build::EditorBuildSettings;
use crate::scenes::{Scenes, TabKind};

/// The directory under the project's `assets/` that holds temporary run
/// copies of unsaved scenes. Dot-prefixed so every asset walk skips it.
pub const PIE_TEMP_DIR: &str = ".jackdaw-pie";

/// What Play does with unsaved scene changes before starting the game.
///
/// Serialized as `save`, `ask` or `play_unsaved_copy`. A settings file from
/// before the enum carries a bool, which reads back as `true` →
/// [`Save`](Self::Save) and `false` → [`PlayUnsavedCopy`](Self::PlayUnsavedCopy):
/// the old `false` ran the game against whatever was last on disk, a
/// silent wrong-scene that the copy mode ends.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SaveBeforePlay {
    /// Save every modified scene that has a file, then launch, so the game
    /// loads what the editor shows. The default.
    #[default]
    Save,
    /// Ask first, with a dialog: Save, Play Unsaved Copy, or Cancel.
    Ask,
    /// Launch against a temporary copy of the unsaved work; nothing
    /// reaches disk and the tab keeps its dirty flag.
    PlayUnsavedCopy,
}

impl SaveBeforePlay {
    /// The mode's name in logs.
    pub fn as_log(self) -> &'static str {
        match self {
            Self::Save => "save",
            Self::Ask => "ask",
            Self::PlayUnsavedCopy => "play_unsaved_copy",
        }
    }
}

impl<'de> serde::Deserialize<'de> for SaveBeforePlay {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct Visitor;
        impl serde::de::Visitor<'_> for Visitor {
            type Value = SaveBeforePlay;
            fn expecting(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str("`save`, `ask`, `play_unsaved_copy`, or a legacy bool")
            }
            fn visit_bool<E: serde::de::Error>(self, v: bool) -> Result<Self::Value, E> {
                Ok(if v {
                    SaveBeforePlay::Save
                } else {
                    SaveBeforePlay::PlayUnsavedCopy
                })
            }
            fn visit_str<E: serde::de::Error>(self, v: &str) -> Result<Self::Value, E> {
                match v {
                    "save" => Ok(SaveBeforePlay::Save),
                    "ask" => Ok(SaveBeforePlay::Ask),
                    "play_unsaved_copy" => Ok(SaveBeforePlay::PlayUnsavedCopy),
                    other => Err(E::unknown_variant(
                        other,
                        &["save", "ask", "play_unsaved_copy"],
                    )),
                }
            }
        }
        deserializer.deserialize_any(Visitor)
    }
}

/// The scene one `pie.play_current` launch carries, and what Stop owes it.
#[derive(Clone, Debug)]
pub struct SceneOverrideLaunch {
    /// The value handed to `JACKDAW_PIE_SCENE`: the scene's path relative
    /// to the asset root the run launches from, with `/` separators.
    pub assets_relative: String,
    /// The temporary copy this launch owns, deleted when play stops.
    /// `None` when the game reads the tab's own file.
    pub temp_copy: Option<PathBuf>,
    /// Whether the game reads the tab's own file or a temporary copy of it.
    pub from_temp_copy: bool,
}

/// What the last `pie.play_current` resolved to: which scene the game was
/// handed, and whether it read the tab's file or a temporary copy of it.
/// The status face and tests read this; it says what *was* played, never
/// what is playing (that is the PIE session's own state).
#[derive(Resource, Default, Debug, PartialEq, Eq, Clone)]
pub struct LastPlayCurrent {
    /// The override handed to the game, assets-relative; `None` until a
    /// current-scene play resolved one.
    pub assets_relative: Option<String>,
    /// Whether the game read a temporary copy of unsaved work.
    pub from_temp_copy: bool,
    /// The tab whose scene was played, as the tab strip spells it.
    pub tab_display: Option<String>,
}

/// Where the scene in front is, when it is anywhere: the active tab when it
/// holds a scene, otherwise the nearest scene tab (a prefab in front falls
/// back to the scene the user most plausibly means). `None` when every tab
/// is a prefab or none is open.
fn current_scene_tab(scenes: &Scenes) -> Option<usize> {
    if let Some(tab) = scenes.tabs.get(scenes.active)
        && tab.kind == TabKind::Scene
    {
        return Some(scenes.active);
    }
    // Nearest by distance, preferring the earlier tab on a tie so the
    // answer never depends on iteration order.
    (1..scenes.tabs.len()).find_map(|distance| {
        let left = scenes.active as isize - distance as isize;
        if left >= 0 && scenes.tabs[left as usize].kind == TabKind::Scene {
            return Some(left as usize);
        }
        let right = scenes.active + distance;
        (right < scenes.tabs.len() && scenes.tabs[right].kind == TabKind::Scene).then_some(right)
    })
}

/// Whether the tab at `index` has changes no save has written, counting an
/// edit made this frame on the active tab that the dirty watcher has not
/// seen yet.
fn tab_modified(world: &World, index: usize) -> bool {
    let Some(scenes) = world.get_resource::<Scenes>() else {
        return false;
    };
    let Some(tab) = scenes.tabs.get(index) else {
        return false;
    };
    if index == scenes.active {
        crate::scenes::operators::active_tab_modified(world)
    } else {
        // An inactive tab cannot be mid-edit; its own flag is the truth.
        tab.dirty
    }
}

/// Begin play on the scene in front. From Stopped, resolves the scene tab,
/// applies the unsaved-changes policy, and launches the first run config
/// with the resulting scene override; from Paused, resumes like `pie.play`.
pub fn handle_play_current(world: &mut World) {
    let state = world.resource::<State<PlayState>>().get().clone();
    match state {
        PlayState::Stopped => {
            let mode = world
                .get_resource::<EditorBuildSettings>()
                .map(|settings| settings.save_before_play)
                .unwrap_or_default();
            let tab_index = world.get_resource::<Scenes>().and_then(current_scene_tab);
            let Some(tab_index) = tab_index else {
                let reason = "No scene is open to play";
                warn!("PIE: not playing the current scene: {reason}");
                crate::status_bar::notify_error(world, reason.to_string());
                return;
            };
            let named = world
                .resource::<Scenes>()
                .tabs
                .get(tab_index)
                .is_some_and(|tab| tab.path.is_some());
            if mode == SaveBeforePlay::Ask && named && tab_modified(world, tab_index) {
                ask_play_current(world, tab_index);
                return;
            }
            launch_current_scene(world, tab_index, mode == SaveBeforePlay::Save);
        }
        // Paused and Playing behave exactly like the startup-scene button:
        // resume, or nothing to do.
        PlayState::Paused | PlayState::Playing => crate::pie::handle_play(world),
    }
}

/// Resolve the tab at `index` into a scene override and launch the first
/// run config with it. `save_first` is the Save policy (or the Ask dialog's
/// Save answer): modified named scenes are saved before anything launches.
fn launch_current_scene(world: &mut World, tab_index: usize, save_first: bool) {
    let Some(run) = first_run_config(world) else {
        return;
    };

    let scene_override = match resolve_override_for_launch(world, tab_index, save_first, "playing")
    {
        Ok(scene_override) => scene_override,
        Err(reason) => {
            warn!("PIE: not playing: {reason}");
            crate::status_bar::notify_error(world, reason);
            return;
        }
    };

    report_background_unsaved(world, tab_index);

    let display = world
        .resource::<Scenes>()
        .tabs
        .get(tab_index)
        .map(|tab| tab.display_name.clone())
        .unwrap_or_else(|| "the scene".to_string());
    world.insert_resource(LastPlayCurrent {
        assets_relative: Some(scene_override.assets_relative.clone()),
        from_temp_copy: scene_override.from_temp_copy,
        tab_display: Some(display.clone()),
    });
    if scene_override.from_temp_copy {
        crate::status_bar::notify_info(
            world,
            format!("Playing '{display}': an unsaved copy, nothing written to disk"),
        );
    } else {
        crate::status_bar::notify_info(world, format!("Playing '{display}'"));
    }

    let key = InstanceKey {
        config: run.label().to_string(),
        instance: 1,
    };
    launch_instance_with_override(world, key, run, Some(scene_override));
}

/// The override a current-scene launch runs with, for the tab at
/// `tab_index`. `save_first` applies the Save policy first (the caller's
/// answer to Ask included); `action` names what asked, for the refusal
/// messages. Nothing here notifies or launches — the caller owns the
/// user-facing outcome.
pub(crate) fn resolve_override_for_launch(
    world: &mut World,
    tab_index: usize,
    save_first: bool,
    action: &str,
) -> Result<SceneOverrideLaunch, String> {
    let Some(root) = crate::pie::project_root(world) else {
        return Err("no project is open".to_string());
    };
    let Some(run) = world
        .get_resource::<crate::run_config::RunConfigs>()
        .map(|configs| configs.manifest.runs.clone())
        .and_then(|runs| runs.into_iter().next())
    else {
        return Err("no run configurations".to_string());
    };

    let (named, was_modified) = {
        let scenes = world.resource::<Scenes>();
        let Some(tab) = scenes.tabs.get(tab_index) else {
            return Err("the scene tab is gone".to_string());
        };
        (tab.path.is_some(), tab_modified(world, tab_index))
    };

    // The Save policy: what the game may load must be on disk first. The
    // named-scene case runs the ordinary launch-save chain (its
    // modified-untitled refusal gate can never fire: the scene in front is
    // named here); an untitled scene in front saves the named background
    // tabs without that gate, since it itself is about to run as a copy.
    // Definition-asset cards save on both branches: the game reads their
    // files whatever scene it runs, so the editor's card values must be
    // on disk before the launch (QA T2 §七, ruling A).
    if save_first {
        if named {
            crate::pie::save_scenes_before_launch(world, action)?;
        } else {
            let mut failures: Vec<String> = crate::scenes::operators::save_modified_scenes(world)
                .into_iter()
                .map(|failure| failure.message)
                .collect();
            failures.extend(crate::definition_assets::save_dirty_assets(world));
            if !failures.is_empty() {
                return Err(format!(
                    "Not {action}: could not save {}",
                    failures.join("; ")
                ));
            }
        }
    }

    // The override: the tab's file when it is named and (under the Save
    // policy) freshly saved, a temporary copy when it is not — an untitled
    // scene, or unsaved work under the copy policy.
    let use_temp_copy = !named || (was_modified && !save_first);
    let launch_assets_root = run_launch_asset_root(&root, &run);
    if use_temp_copy {
        write_pie_temp_copy(world, tab_index, &launch_assets_root)
    } else {
        let path = {
            let scenes = world.resource::<Scenes>();
            scenes
                .tabs
                .get(tab_index)
                .and_then(|tab| tab.path.clone())
                .expect("the tab was checked named above")
        };
        assets_relative_scene_path(&launch_assets_root, &path).map(|assets_relative| {
            SceneOverrideLaunch {
                assets_relative,
                temp_copy: None,
                from_temp_copy: false,
            }
        })
    }
}

/// The override a Reload of a current-scene session relaunches with,
/// resolved fresh against the scene in front: edited since the launch, the
/// relaunch writes a new temporary copy; still clean, the same file. A
/// reload never writes disk on its own — it replays what is in front, not
/// what a save policy would do — and it never asks: the rebuild is already
/// the user's explicit answer. `None` when no scene tab is in front (the
/// relaunch falls back to the game's own startup scene) or the resolution
/// refused.
pub fn override_for_reload(world: &mut World) -> Option<SceneOverrideLaunch> {
    let tab_index = world.get_resource::<Scenes>().and_then(current_scene_tab)?;
    match resolve_override_for_launch(world, tab_index, false, "reloading") {
        Ok(scene_override) => {
            info!(
                "PIE: reload runs the current scene '{}'",
                scene_override.assets_relative
            );
            Some(scene_override)
        }
        Err(reason) => {
            warn!("PIE: reload falls back to the startup scene: {reason}");
            None
        }
    }
}

/// The first run config, refused the way `pie.play` refuses when there is
/// none.
fn first_run_config(world: &mut World) -> Option<RunConfig> {
    let runs = world
        .get_resource::<crate::run_config::RunConfigs>()
        .map(|configs| configs.manifest.runs.clone());
    match runs {
        None => {
            warn!("PIE: run configurations not loaded");
            crate::status_bar::notify_error(world, "Run configurations not loaded".to_string());
            None
        }
        Some(runs) => match runs.into_iter().next() {
            Some(first) => Some(first),
            None => {
                warn!("PIE: no run configurations");
                crate::status_bar::notify_error(world, "No run configurations to play".to_string());
                None
            }
        },
    }
}

/// The asset root a launch reads: the run's working directory with
/// `assets` under it, exactly as `spawn_instance` points `BEVY_ASSET_ROOT`
/// at the cwd and bevy joins `assets` to that.
fn run_launch_asset_root(project_root: &Path, run: &RunConfig) -> PathBuf {
    let cwd = match run.cwd.as_ref() {
        Some(dir) => project_root.join(dir),
        None => project_root.to_path_buf(),
    };
    cwd.join("assets")
}

/// The tab's file spelled the way the game's asset server sees it:
/// relative to the launch's asset root, `/`-separated. A scene outside
/// that root cannot be played by path — it would hand the game a path it
/// can never read.
fn assets_relative_scene_path(
    launch_assets_root: &Path,
    tab_path: &Path,
) -> Result<String, String> {
    let assets_root = dunce::canonicalize(launch_assets_root)
        .unwrap_or_else(|_| launch_assets_root.to_path_buf());
    let scene = dunce::canonicalize(tab_path).unwrap_or_else(|_| tab_path.to_path_buf());
    let relative = scene.strip_prefix(&assets_root).map_err(|_| {
        format!(
            "{} is outside the asset folder {} the run launches from",
            scene.display(),
            assets_root.display()
        )
    })?;
    let joined = relative
        .components()
        .map(|component| component.as_os_str().to_string_lossy())
        .collect::<Vec<_>>()
        .join("/");
    Ok(joined)
}

/// A file-stem-safe spelling of a tab's display name, so a temp copy's name
/// stays one component on every platform.
fn sanitize_stem(name: &str) -> String {
    let cleaned: String = name
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '-'
            }
        })
        .collect();
    let trimmed = cleaned.trim_matches('-');
    if trimmed.is_empty() {
        "scene".to_string()
    } else {
        trimmed.chars().take(48).collect()
    }
}

/// Write the tab's document to a fresh temporary run copy under
/// `<launch_assets_root>/.jackdaw-pie/` and hand back the override that
/// names it. The copy goes through the same emitter a save uses (asset
/// references spelled against the assets namespace) and the same atomic
/// write (fsync, rename), and deliberately not the save journal: it is a
/// run artifact, regenerated on every play, not editor state to recover.
fn write_pie_temp_copy(
    world: &mut World,
    tab_index: usize,
    launch_assets_root: &Path,
) -> Result<SceneOverrideLaunch, String> {
    let (original_active, display) = {
        let scenes = world.resource::<Scenes>();
        let Some(tab) = scenes.tabs.get(tab_index) else {
            return Err("the scene tab is gone".to_string());
        };
        (scenes.active, tab.display_name.clone())
    };
    let dir = launch_assets_root.join(PIE_TEMP_DIR);
    std::fs::create_dir_all(&dir)
        .map_err(|err| format!("cannot create {}: {err}", dir.display()))?;
    let file = dir.join(format!(
        "current-{}-{}.bsn",
        sanitize_stem(&display),
        std::process::id()
    ));

    // The emitter reads the live world, so a background tab comes to the
    // front for the emission and goes back after it.
    let was_active = original_active == tab_index;
    if !was_active {
        crate::scenes::swap::swap_active_tab(world, tab_index);
    }
    let emitted = crate::scene_io::emit_bsn_scene_for_file(world, &dir);
    if !was_active {
        crate::scenes::swap::swap_active_tab(world, original_active);
    }
    let text = emitted.map_err(|refusal| format!("cannot emit the scene: {refusal}"))?;
    jackdaw_api_internal::document::write_atomic(&file, text.as_bytes())
        .map_err(|err| format!("cannot write {}: {err}", file.display()))?;
    let assets_relative = format!(
        "{}/{}",
        PIE_TEMP_DIR,
        file.file_name().expect("named above").to_string_lossy()
    );
    info!("PIE: wrote the temporary run copy {}", file.display());
    Ok(SceneOverrideLaunch {
        assets_relative,
        temp_copy: Some(file),
        from_temp_copy: true,
    })
}

/// Name the background tabs whose unsaved work the game will not see, so a
/// multi-tab session is told what "play the current scene" skipped instead
/// of finding out by surprise: dirty untitled tabs, which no policy can
/// save and no launch reads.
fn report_background_unsaved(world: &mut World, playing_index: usize) {
    let skipped: Vec<String> = {
        let scenes = world.resource::<Scenes>();
        scenes
            .tabs
            .iter()
            .enumerate()
            .filter(|(index, tab)| *index != playing_index && tab.path.is_none() && tab.dirty)
            .map(|(_, tab)| tab.display_name.clone())
            .collect()
    };
    if skipped.is_empty() {
        return;
    }
    let list = skipped.join(", ");
    warn!("PIE: unsaved scene(s) not included in play: {list}");
    crate::status_bar::notify_warn(
        world,
        format!("Unsaved scene(s) not included in play: {list}"),
    );
}

/// Delete the leftover temporary run copies a killed editor never stopped
/// to remove. Called where a project opens, next to the orphan-temp sweep:
/// every copy is regenerable (its source is the tab in the editor that
/// wrote it) and its name carries the pid of the editor that wrote it, so
/// a fresh open never owes anything to the files it finds.
///
/// One case sweeps a file still in use: a second editor opened on the same
/// project while the first is playing. The running game has already loaded
/// its copy, so only a reload would miss it; the first editor's own stop
/// cleanup tolerates the file already being gone.
pub fn sweep_orphan_pie_copies(project_root: &Path) -> usize {
    let dir = project_root.join("assets").join(PIE_TEMP_DIR);
    let Ok(entries) = std::fs::read_dir(&dir) else {
        return 0;
    };
    let mut removed = 0;
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if name.starts_with("current-")
            && name.ends_with(".bsn")
            && std::fs::remove_file(entry.path()).is_ok()
        {
            removed += 1;
        }
    }
    if removed > 0 {
        info!(
            "PIE: removed {removed} leftover temporary run cop{} under {}",
            if removed == 1 { "y" } else { "ies" },
            dir.display()
        );
    }
    removed
}

// ---------------------------------------------------------------------------
// The Ask dialog
// ---------------------------------------------------------------------------

/// The play the Ask dialog is holding while the user decides.
#[derive(Resource, Default, Debug, PartialEq, Eq)]
pub struct PendingPlayAsk {
    /// The scene tab Play was asked to run; `None` when no dialog is up.
    pub tab_index: Option<usize>,
}

/// Marker on the Ask dialog's root (the scrim node), for one-step despawn.
#[derive(Component)]
pub struct PlayAskDialogRoot;

/// The dialog's three answers.
#[derive(Component, Clone, Copy, PartialEq, Eq)]
pub enum PlayAskButton {
    Cancel,
    PlayCopy,
    Save,
}

/// Which way the Ask dialog resolved an answer into a launch.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum PlayAskChoice {
    /// Save the unsaved work, then play the file.
    Save,
    /// Play a temporary copy; the disk file and dirty flag stay as they are.
    PlayCopy,
}

/// Hold the play and open the Ask dialog for the unsaved scene tab.
fn ask_play_current(world: &mut World, tab_index: usize) {
    world.insert_resource(PendingPlayAsk {
        tab_index: Some(tab_index),
    });
    spawn_play_ask_dialog(world);
}

/// Spawn the Ask dialog (scrim + card + three buttons), following the
/// scene-close confirm dialog's shape. Skips UI spawning without
/// `EditorFont` (headless tests); the `PendingPlayAsk` resource is still
/// set, so tests resolve the dialog by calling [`resolve_play_ask`].
fn spawn_play_ask_dialog(world: &mut World) {
    let Some(editor_font) = world.get_resource::<EditorFont>().map(|f| f.0.clone()) else {
        return;
    };
    let display = world
        .get_resource::<PendingPlayAsk>()
        .and_then(|ask| ask.tab_index)
        .and_then(|index| {
            world
                .get_resource::<Scenes>()
                .and_then(|scenes| scenes.tabs.get(index))
                .map(|tab| tab.display_name.clone())
        })
        .unwrap_or_else(|| "the scene".to_string());

    let scrim = world
        .spawn((
            PlayAskDialogRoot,
            Node {
                position_type: PositionType::Absolute,
                left: Val::Px(0.0),
                top: Val::Px(0.0),
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                ..Default::default()
            },
            BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.55)),
            GlobalZIndex(100),
        ))
        .id();

    let card = world
        .spawn((
            Node {
                flex_direction: FlexDirection::Column,
                row_gap: Val::Px(12.0),
                padding: UiRect::all(Val::Px(24.0)),
                min_width: Val::Px(380.0),
                max_width: Val::Px(480.0),
                border: UiRect::all(Val::Px(1.0)),
                border_radius: BorderRadius::all(Val::Px(tokens::BORDER_RADIUS_MD)),
                ..Default::default()
            },
            BackgroundColor(tokens::PANEL_BG),
            BorderColor::all(tokens::BORDER_SUBTLE),
            ChildOf(scrim),
        ))
        .id();

    world.spawn((
        Text::new("Unsaved Scene"),
        TextFont {
            font: editor_font.clone().into(),
            font_size: tokens::TEXT_SIZE_LG,
            ..Default::default()
        },
        TextColor(tokens::TEXT_PRIMARY),
        ChildOf(card),
    ));
    world.spawn((
        Text::new(format!(
            "\"{display}\" has unsaved changes. Save before playing?"
        )),
        TextFont {
            font: editor_font.clone().into(),
            font_size: tokens::TEXT_SIZE_SM,
            ..Default::default()
        },
        TextColor(tokens::TEXT_SECONDARY),
        ChildOf(card),
    ));

    let button_row = world
        .spawn((
            Node {
                flex_direction: FlexDirection::Row,
                justify_content: JustifyContent::FlexEnd,
                column_gap: Val::Px(8.0),
                margin: UiRect::top(Val::Px(8.0)),
                ..Default::default()
            },
            ChildOf(card),
        ))
        .id();

    for (label, kind, bg) in [
        ("Cancel", PlayAskButton::Cancel, tokens::TOOLBAR_BG),
        (
            "Play Unsaved Copy",
            PlayAskButton::PlayCopy,
            tokens::TOOLBAR_BG,
        ),
        ("Save", PlayAskButton::Save, tokens::SELECTED_BG),
    ] {
        let button = world
            .spawn((
                kind,
                Node {
                    padding: UiRect::axes(Val::Px(16.0), Val::Px(8.0)),
                    border_radius: BorderRadius::all(Val::Px(tokens::BORDER_RADIUS_MD)),
                    ..Default::default()
                },
                BackgroundColor(bg),
                ChildOf(button_row),
            ))
            .id();
        world.spawn((
            Text::new(label.to_string()),
            TextFont {
                font: editor_font.clone().into(),
                font_size: tokens::TEXT_SIZE,
                ..Default::default()
            },
            TextColor(tokens::TEXT_PRIMARY),
            Pickable::IGNORE,
            ChildOf(button),
        ));
        world.entity_mut(button).observe(on_play_ask_button_click);
    }
}

fn on_play_ask_button_click(
    mut click: On<PointerClick>,
    buttons: Query<&PlayAskButton>,
    mut commands: Commands,
) {
    let target = click.event_target();
    let Ok(kind) = buttons.get(target) else {
        return;
    };
    click.propagate(false);
    let choice = match *kind {
        PlayAskButton::Save => PlayAskChoice::Save,
        PlayAskButton::PlayCopy => PlayAskChoice::PlayCopy,
        PlayAskButton::Cancel => {
            commands.queue(|world: &mut World| cancel_play_ask(world));
            return;
        }
    };
    commands.queue(move |world: &mut World| resolve_play_ask(world, choice));
}

/// Apply the dialog's answer: clear the pending play, close the dialog,
/// and launch with the chosen policy.
pub fn resolve_play_ask(world: &mut World, choice: PlayAskChoice) {
    let Some(tab_index) = world
        .get_resource::<PendingPlayAsk>()
        .and_then(|ask| ask.tab_index)
    else {
        return;
    };
    world.remove_resource::<PendingPlayAsk>();
    despawn_play_ask_dialog(world);
    launch_current_scene(world, tab_index, choice == PlayAskChoice::Save);
}

/// Cancel the pending play and close the dialog.
pub fn cancel_play_ask(world: &mut World) {
    world.remove_resource::<PendingPlayAsk>();
    despawn_play_ask_dialog(world);
}

fn despawn_play_ask_dialog(world: &mut World) {
    let dialogs: Vec<Entity> = world
        .query_filtered::<Entity, With<PlayAskDialogRoot>>()
        .iter(world)
        .collect();
    for entity in dialogs {
        world.despawn(entity);
    }
}

// ---------------------------------------------------------------------------
// Operators
// ---------------------------------------------------------------------------

fn play_stopped_or_paused(state: Res<State<PlayState>>) -> bool {
    !matches!(state.get(), PlayState::Playing)
}

/// Start the game running on the scene in front. Unsaved work follows the
/// project's save-before-play setting: save, ask, or play a temporary
/// copy. The Play toolbar button and F5 dispatch this; the dropdown's
/// "Play Startup Scene" row and the run rows keep the game's own startup
/// scene.
#[operator(
    id = "pie.play_current",
    label = "Play Current Scene",
    description = "Start the game running on the scene in front of the editor.",
    is_available = play_stopped_or_paused
)]
pub(crate) fn pie_play_current(
    _: In<OperatorParameters>,
    mut commands: Commands,
) -> OperatorResult {
    commands.queue(handle_play_current);
    OperatorResult::Finished
}

/// Set how Play handles unsaved scene changes: `save`, `ask` (a dialog
/// before launching), or `play_unsaved_copy` (a temporary run copy,
/// nothing written). Settings files from before the enum carry a bool,
/// which reads back as `true` = save and `false` = play a copy.
#[operator(
    id = "project.set_save_before_play",
    label = "Set Save Before Play",
    description = "Set how Play handles unsaved scenes: save, ask, or play an unsaved copy.",
    // The `save` policy persists into project settings and fires scene
    // saves before launch; batches that must roll back refuse it.
    writes_disk = true,
    params(mode(
        String,
        doc = "The policy: \"save\" (save modified scenes, then launch), \"ask\" \
                   (a dialog before launching), or \"play_unsaved_copy\" (run a \
                   temporary copy; nothing written)."
    ),)
)]
pub(crate) fn project_set_save_before_play(
    In(params): In<OperatorParameters>,
    mut commands: Commands,
) -> OperatorResult {
    let Some(mode) = params.as_str("mode").map(str::to_string) else {
        warn!("project.set_save_before_play: a mode= is required (save, ask, play_unsaved_copy)");
        return OperatorResult::Cancelled;
    };
    let parsed = match mode.as_str() {
        "save" => Some(SaveBeforePlay::Save),
        "ask" => Some(SaveBeforePlay::Ask),
        "play_unsaved_copy" => Some(SaveBeforePlay::PlayUnsavedCopy),
        _ => None,
    };
    let Some(mode) = parsed else {
        warn!(
            "project.set_save_before_play: unknown mode '{mode}' \
             (save, ask, play_unsaved_copy)"
        );
        return OperatorResult::Cancelled;
    };
    commands.queue(move |world: &mut World| {
        world.resource_mut::<EditorBuildSettings>().save_before_play = mode;
        crate::project_build::persist_project_build_settings(world);
        info!("PIE: save before play set to {}", mode.as_log());
    });
    OperatorResult::Finished
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The pre-enum bool settings migrate onto the enum: `true` was
    /// "save before playing" and `false` was not (the game ran whatever
    /// was last on disk), which maps to the copy mode rather than a silent
    /// stale-scene play.
    #[test]
    fn legacy_bool_settings_read_as_enum_modes() {
        let save: SaveBeforePlay = serde_json::from_value(serde_json::json!(true)).unwrap();
        assert_eq!(save, SaveBeforePlay::Save);
        let copy: SaveBeforePlay = serde_json::from_value(serde_json::json!(false)).unwrap();
        assert_eq!(copy, SaveBeforePlay::PlayUnsavedCopy);
    }

    #[test]
    fn enum_settings_round_trip_snake_case() {
        for mode in [
            SaveBeforePlay::Save,
            SaveBeforePlay::Ask,
            SaveBeforePlay::PlayUnsavedCopy,
        ] {
            let text = serde_json::to_string(&mode).unwrap();
            let back: SaveBeforePlay = serde_json::from_str(&text).unwrap();
            assert_eq!(back, mode, "{text} round-trips");
        }
        assert_eq!(
            serde_json::to_string(&SaveBeforePlay::PlayUnsavedCopy).unwrap(),
            "\"play_unsaved_copy\""
        );
    }

    #[test]
    fn an_unknown_mode_is_rejected() {
        assert!(serde_json::from_value::<SaveBeforePlay>(serde_json::json!("always")).is_err());
    }

    /// The whole settings section, the way the project file holds it: the
    /// other fields alongside a legacy bool, read through the section
    /// loader the editor uses.
    #[test]
    fn the_settings_section_migrates_a_legacy_bool() {
        let tmp = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(tmp.path().join(".jackdaw")).unwrap();
        std::fs::write(
            tmp.path().join(".jackdaw/settings.json"),
            r#"{"auto_build": true, "prebuild": false, "save_before_play": false}"#,
        )
        .unwrap();
        let settings: EditorBuildSettings = crate::project_settings::load_section(
            tmp.path(),
            crate::project_settings::Section::TopLevel,
        );
        assert_eq!(settings.save_before_play, SaveBeforePlay::PlayUnsavedCopy);
        assert!(settings.auto_build, "the neighboring fields survive");
        assert!(!settings.prebuild);
    }

    #[test]
    fn tab_display_names_sanitize_to_single_components() {
        assert_eq!(sanitize_stem("untitled-0"), "untitled-0");
        assert_eq!(sanitize_stem("props/main zone"), "props-main-zone");
        assert_eq!(sanitize_stem("///"), "scene");
        assert_eq!(sanitize_stem(&"a".repeat(80)).chars().count(), 48);
    }

    #[test]
    fn the_nearest_scene_tab_wins_over_prefab_tabs() {
        let prefab = |n: u32| crate::scenes::SceneTab {
            kind: TabKind::Prefab,
            ..crate::scenes::SceneTab::new_untitled(n)
        };
        let scene = |n: u32| crate::scenes::SceneTab {
            kind: TabKind::Scene,
            ..crate::scenes::SceneTab::new_untitled(n)
        };
        let mut scenes = Scenes {
            tabs: vec![scene(1), prefab(2), prefab(3), scene(4)],
            active: 0,
        };
        scenes.active = 2;
        // The prefab in front falls back to the nearest scene tab, one
        // step to its right (the tab to its left is also a prefab).
        assert_eq!(current_scene_tab(&scenes), Some(3));
        scenes.active = 0;
        assert_eq!(
            current_scene_tab(&scenes),
            Some(0),
            "a scene in front is itself"
        );
        // A scene one tab away on each side: the earlier index wins the tie.
        scenes.tabs = vec![scene(1), prefab(2), scene(3)];
        scenes.active = 1;
        assert_eq!(current_scene_tab(&scenes), Some(0));
        // Nearest beats first: a scene one tab to the left wins over one
        // two to the right.
        scenes.tabs = vec![scene(1), prefab(2), prefab(3), scene(4)];
        scenes.active = 1;
        assert_eq!(current_scene_tab(&scenes), Some(0));
        scenes.tabs = vec![prefab(1), prefab(2)];
        scenes.active = 1;
        assert_eq!(
            current_scene_tab(&scenes),
            None,
            "all prefab: nothing to play"
        );
        scenes.tabs = Vec::new();
        scenes.active = 0;
        assert_eq!(current_scene_tab(&scenes), None, "no tabs: nothing to play");
    }

    /// The sweep removes stale `current-*` copies and nothing else in the
    /// directory, and a second sweep is a no-op.
    #[test]
    fn the_sweep_removes_only_stale_run_copies() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("assets").join(PIE_TEMP_DIR);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("current-untitled-99999.bsn"), "#Stale\n").unwrap();
        std::fs::write(dir.join("current-zone-12345.bsn"), "#Stale\n").unwrap();
        std::fs::write(dir.join("notes.txt"), "keep me").unwrap();
        let removed = sweep_orphan_pie_copies(tmp.path());
        assert_eq!(removed, 2);
        assert!(!dir.join("current-untitled-99999.bsn").exists());
        assert!(dir.join("notes.txt").exists());
        assert_eq!(sweep_orphan_pie_copies(tmp.path()), 0);
    }

    /// The game-side spelling of a tab's file: relative to the launch
    /// asset root, `/`-separated, refused when the scene is not under it.
    #[test]
    fn scene_paths_spell_assets_relative_or_refuse() {
        let root = Path::new("/proj");
        let assets = run_launch_asset_root(root, &RunConfig::default());
        assert_eq!(assets, PathBuf::from("/proj/assets"));
        let scene = Path::new("/proj/assets/props/other.bsn");
        assert_eq!(
            assets_relative_scene_path(&assets, scene).unwrap(),
            "props/other.bsn"
        );
        let outside = Path::new("/elsewhere/other.bsn");
        assert!(assets_relative_scene_path(&assets, outside).is_err());
    }
}
