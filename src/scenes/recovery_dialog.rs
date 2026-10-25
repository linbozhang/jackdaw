//! The crash-recovery dialog: what a killed editor's journal offers the
//! next session, one session at a time.
//!
//! Opening a project queues every leftover session (a directory holding a
//! `journal.json` that is not this session's own) into [`PendingRecovery`].
//! While a recovery is pending, the tab restore that opens the project's
//! last scenes waits: the user decides what to do with the recovered work
//! first. Each row names one journaled tab with its capture time, entity
//! count and a line-diff summary against the file on disk; restoring opens
//! the document as an in-memory tab that is dirty from the start (the
//! journal never writes a file -- only an explicit save does), and the
//! baseline it carries is the file on disk, so the tab reads dirty until
//! the user saves over it. A damaged journal is skipped with a warning and
//! kept on disk; it must never crash the editor (the Y28 line).

use std::collections::VecDeque;
use std::path::{Path, PathBuf};

use bevy::picking::events::PointerClick;
use bevy::prelude::*;
use jackdaw_api::prelude::*;
use jackdaw_feathers::{icons::EditorFont, tokens};

use crate::scene_io::session_journal::{self, JournalFile, JournalTab, read_session_journal};
use crate::scenes::{SceneTab, Scenes, TabContent, TabKind};

/// The recovery sessions still to ask about. Present while any leftover
/// session waits or a dialog is up; absent otherwise, which is what lets
/// the tab restore proceed.
#[derive(Resource, Default)]
pub struct PendingRecovery {
    /// Session directories (each holding a `journal.json`), oldest first.
    pub queue: VecDeque<PathBuf>,
    /// The session whose dialog is up.
    pub current: Option<PathBuf>,
}

/// Marker on the recovery dialog's scrim node.
#[derive(Component)]
pub struct RecoveryDialogRoot;

/// The preview text block below a row.
#[derive(Component)]
pub struct RecoveryPreviewText {
    pub session: PathBuf,
    pub index: usize,
}

/// What one dialog button does. The button carries its row's identity
/// itself, so the observer never walks the node tree.
#[derive(Component, Clone)]
pub struct RecoveryButton {
    pub action: RecoveryAction,
    /// The session the row belongs to; `None` for the dialog-wide
    /// Discard All.
    pub session: Option<PathBuf>,
    pub index: usize,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum RecoveryAction {
    Restore,
    Discard,
    DiscardAll,
    Preview,
}

pub(crate) fn plugin(app: &mut App) {
    app.init_resource::<PendingRecovery>()
        .add_systems(
            Update,
            recovery_dialog_system.run_if(in_state(crate::AppState::Editor)),
        )
        .add_observer(on_recovery_button_click);
}

/// Keep the dialog in step with the queue: finish a session whose journal
/// has no rows left, bring the next one up, and take the resource away
/// once nothing is left to ask about.
pub fn recovery_dialog_system(world: &mut World) {
    let has_dialog = world
        .query_filtered::<Entity, With<RecoveryDialogRoot>>()
        .iter(world)
        .next()
        .is_some();
    // Read (and hand back) what the queue holds; the resource borrow ends
    // with the block, so the world is free for the spawning below.
    let (current, next) = {
        let Some(mut pending) = world.get_resource_mut::<PendingRecovery>() else {
            return;
        };
        let current = pending.current.clone();
        let next = if current.is_none() {
            pending.queue.pop_front()
        } else {
            None
        };
        (current, next)
    };
    if let Some(dir) = current {
        if has_dialog {
            return;
        }
        // The dialog was despawned by an action; re-read the session's
        // journal, which that action rewrote.
        match read_session_journal(&dir) {
            Some(journal) if !journal.tabs.is_empty() => {
                spawn_recovery_dialog(world, &journal, &dir);
            }
            _ => {
                // Restored or dismissed down to nothing, or the rewrite
                // left it unreadable: either way this session is done.
                world.resource_mut::<PendingRecovery>().current = None;
            }
        }
        return;
    }
    let Some(next) = next else {
        world.remove_resource::<PendingRecovery>();
        return;
    };
    match read_session_journal(&next) {
        Some(journal) if !journal.tabs.is_empty() => {
            world.resource_mut::<PendingRecovery>().current = Some(next.clone());
            spawn_recovery_dialog(world, &journal, &next);
        }
        // An empty journal is nothing to ask about, and a damaged one is
        // skipped with the warning `read_session_journal` logged, the
        // file kept where it is as evidence.
        _ => {}
    }
}

/// One line summarizing the diff between the journaled document and the
/// file on disk, for the row and the recovery BRP.
pub fn diff_summary(entry: &JournalTab) -> Option<String> {
    let path = entry.path.as_deref().map(Path::new)?;
    let on_disk = std::fs::read_to_string(path).ok()?;
    let disk_lines = on_disk.lines().count();
    let journal_lines = entry.document.lines().count();
    Some(format!(
        "{:+} lines vs the file on disk",
        journal_lines as i64 - disk_lines as i64
    ))
}

fn spawn_recovery_dialog(world: &mut World, journal: &JournalFile, dir: &Path) {
    let Some(editor_font) = world.get_resource::<EditorFont>().map(|f| f.0.clone()) else {
        // Headless: the pending state is what tests and tooling assert
        // against, the UI never spawns.
        return;
    };

    let scrim = world
        .spawn((
            RecoveryDialogRoot,
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
                min_width: Val::Px(440.0),
                max_width: Val::Px(640.0),
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
        Text::new("Recovered Work"),
        TextFont {
            font: editor_font.clone().into(),
            font_size: tokens::TEXT_SIZE_LG,
            ..Default::default()
        },
        TextColor(tokens::TEXT_PRIMARY),
        ChildOf(card),
    ));
    let captured_when = journal
        .tabs
        .first()
        .map(|tab| tab.captured_at.as_str())
        .unwrap_or("an earlier session");
    world.spawn((
        Text::new(format!(
            "The editor closed unexpectedly ({captured_when}). These scenes had \
             unsaved changes. Restoring opens them as dirty tabs; nothing is \
             written until you save. Terrain bulk data is not journaled and \
             recovers to its last save."
        )),
        TextFont {
            font: editor_font.clone().into(),
            font_size: tokens::TEXT_SIZE_SM,
            ..Default::default()
        },
        TextColor(tokens::TEXT_SECONDARY),
        ChildOf(card),
    ));

    for (index, tab) in journal.tabs.iter().enumerate() {
        let row = world
            .spawn((
                Node {
                    flex_direction: FlexDirection::Column,
                    row_gap: Val::Px(6.0),
                    ..Default::default()
                },
                ChildOf(card),
            ))
            .id();

        let summary = format!(
            "{} -- {} · {} entities · saved {} · captured {}{}",
            tab.display_name,
            tab.path.as_deref().unwrap_or("untitled"),
            tab.entity_count,
            tab.saved_at.as_deref().unwrap_or("never"),
            tab.captured_at,
            diff_summary(tab)
                .map(|diff| format!(" · {diff}"))
                .unwrap_or_default(),
        );
        world.spawn((
            Text::new(summary),
            TextFont {
                font: editor_font.clone().into(),
                font_size: tokens::TEXT_SIZE_SM,
                ..Default::default()
            },
            TextColor(tokens::TEXT_PRIMARY),
            ChildOf(row),
        ));

        let buttons = world
            .spawn((
                Node {
                    flex_direction: FlexDirection::Row,
                    column_gap: Val::Px(8.0),
                    ..Default::default()
                },
                ChildOf(row),
            ))
            .id();
        for (label, action, bg) in [
            ("Preview", RecoveryAction::Preview, tokens::TOOLBAR_BG),
            ("Discard", RecoveryAction::Discard, tokens::TOOLBAR_BG),
            ("Restore", RecoveryAction::Restore, tokens::SELECTED_BG),
        ] {
            spawn_button(
                world,
                buttons,
                editor_font.clone(),
                label,
                RecoveryButton {
                    action,
                    session: Some(dir.to_path_buf()),
                    index,
                },
                bg,
            );
        }
    }

    let footer = world
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
    spawn_button(
        world,
        footer,
        editor_font,
        "Discard All",
        RecoveryButton {
            action: RecoveryAction::DiscardAll,
            session: None,
            index: 0,
        },
        tokens::TOOLBAR_BG,
    );
}

fn spawn_button(
    world: &mut World,
    parent: Entity,
    font: Handle<Font>,
    label: &str,
    button: RecoveryButton,
    bg: Color,
) {
    let node = world
        .spawn((
            button,
            Node {
                padding: UiRect::axes(Val::Px(14.0), Val::Px(6.0)),
                border_radius: BorderRadius::all(Val::Px(tokens::BORDER_RADIUS_MD)),
                ..Default::default()
            },
            BackgroundColor(bg),
            ChildOf(parent),
        ))
        .id();
    world.spawn((
        Text::new(label.to_string()),
        TextFont {
            font: font.into(),
            font_size: tokens::TEXT_SIZE,
            ..Default::default()
        },
        TextColor(tokens::TEXT_PRIMARY),
        Pickable::IGNORE,
        ChildOf(node),
    ));
    world.entity_mut(node).observe(on_recovery_button_click);
}

/// Despawn the dialog tree. The system brings it back (or moves on) from
/// whatever the action left in the journal.
fn despawn_dialog(world: &mut World) {
    let roots: Vec<Entity> = world
        .query_filtered::<Entity, With<RecoveryDialogRoot>>()
        .iter(world)
        .collect();
    for root in roots {
        if let Ok(ec) = world.get_entity_mut(root) {
            ec.despawn();
        }
    }
}

/// Every button rewrites the journal (or removes the session) and drops
/// the dialog; the system re-reads what is left.
pub fn on_recovery_button_click(
    trigger: On<PointerClick>,
    buttons: Query<&RecoveryButton>,
    mut commands: Commands,
) {
    let Ok(button) = buttons.get(trigger.event_target()) else {
        return;
    };
    let button = button.clone();
    commands.queue(move |world: &mut World| match button.action {
        RecoveryAction::Preview => {
            if let Some(session) = &button.session {
                toggle_preview(world, session, button.index);
            }
        }
        RecoveryAction::Restore => {
            if let Some(session) = &button.session {
                match restore_tab(world, session, button.index) {
                    Ok(()) => despawn_dialog(world),
                    Err(err) => {
                        warn!("recovery: restore failed: {err}");
                        crate::status_bar::notify_error(world, format!("Could not restore: {err}"));
                    }
                }
            }
        }
        RecoveryAction::Discard => {
            if let Some(session) = &button.session {
                if let Err(err) = dismiss_tab(session, button.index) {
                    warn!("recovery: dismiss failed: {err}");
                }
                despawn_dialog(world);
            }
        }
        RecoveryAction::DiscardAll => {
            if let Some(dir) = world
                .get_resource::<PendingRecovery>()
                .and_then(|pending| pending.current.clone())
            {
                remove_session(&dir);
                world.resource_mut::<PendingRecovery>().current = None;
                despawn_dialog(world);
            }
        }
    });
}

/// How many lines of the journaled document the preview shows.
const PREVIEW_LINES: usize = 40;

/// Expand or collapse one row's preview of its journaled document.
fn toggle_preview(world: &mut World, session: &Path, index: usize) {
    let Some(journal) = read_session_journal(session) else {
        return;
    };
    let Some(entry) = journal.tabs.get(index) else {
        return;
    };
    // Collapse: drop this row's preview blocks.
    let previews: Vec<Entity> = world
        .query_filtered::<Entity, With<RecoveryPreviewText>>()
        .iter(world)
        .filter(|entity| {
            world
                .get::<RecoveryPreviewText>(*entity)
                .is_some_and(|preview| preview.session == session && preview.index == index)
        })
        .collect();
    if !previews.is_empty() {
        for preview in previews {
            if let Ok(ec) = world.get_entity_mut(preview) {
                ec.despawn();
            }
        }
        return;
    }
    let Some(font) = world.get_resource::<EditorFont>().map(|f| f.0.clone()) else {
        return;
    };
    let shown: String = entry
        .document
        .lines()
        .take(PREVIEW_LINES)
        .collect::<Vec<_>>()
        .join("\n");
    let Some(card) = world
        .query_filtered::<Entity, With<RecoveryDialogRoot>>()
        .iter(world)
        .next()
        .and_then(|root| world.get::<ChildOf>(root).map(ChildOf::parent))
    else {
        return;
    };
    world.spawn((
        RecoveryPreviewText {
            session: session.to_path_buf(),
            index,
        },
        Text::new(shown),
        TextFont {
            font: font.into(),
            font_size: tokens::TEXT_SIZE_SM,
            ..Default::default()
        },
        TextColor(tokens::TEXT_SECONDARY),
        ChildOf(card),
    ));
}

// ---------------------------------------------------------- the actions --

/// Rewrite `dir`'s journal without entry `index`, removing the session
/// directory when nothing is left in it.
fn journal_without(dir: &Path, index: usize) -> Result<(), String> {
    let Some(mut journal) = read_session_journal(dir) else {
        return Err(format!(
            "the journal in {} cannot be read (kept as-is)",
            dir.display()
        ));
    };
    if index >= journal.tabs.len() {
        return Err(format!("entry {index} is not in the journal"));
    }
    journal.tabs.remove(index);
    if journal.tabs.is_empty() {
        remove_session(dir);
    } else {
        let bytes = serde_json::to_vec(&journal)
            .map_err(|err| format!("cannot encode the journal: {err}"))?;
        jackdaw_api_internal::document::write_atomic(&dir.join("journal.json"), &bytes)
            .map_err(|err| format!("cannot rewrite the journal: {err}"))?;
    }
    Ok(())
}

/// Drop a whole leftover session directory.
fn remove_session(dir: &Path) {
    if let Err(err) = std::fs::remove_dir_all(dir) {
        warn!("recovery: cannot remove {}: {err}", dir.display());
    }
}

/// Drop every leftover session of the open project.
pub fn dismiss_all(world: &mut World) {
    let Some(own) = session_journal::session_dir(world) else {
        return;
    };
    let Some(root) = leftover_root(world) else {
        return;
    };
    for dir in session_journal::list_sessions(&root) {
        if dir != own && dir.join("journal.json").is_file() {
            remove_session(&dir);
        }
    }
    world.remove_resource::<PendingRecovery>();
}

/// Where the open project's recovery sessions live, if a project is open.
pub(crate) fn leftover_root(world: &World) -> Option<PathBuf> {
    world
        .get_resource::<crate::project::ProjectRoot>()
        .map(|project| project.root.clone())
        .and_then(|root| session_journal::sessions_root(&root))
}

/// Restore one journaled tab as an in-memory tab: nothing is written, the
/// tab is dirty from the start, and its clean baseline is the file on
/// disk -- so an explicit save is what overwrites that file, and nothing
/// else ever does. The journal entry is spent (the document is in the
/// editor now, not only in the journal).
pub fn restore_tab(world: &mut World, dir: &Path, index: usize) -> Result<(), String> {
    let Some(journal) = read_session_journal(dir) else {
        return Err(format!(
            "the journal in {} cannot be read (kept as-is)",
            dir.display()
        ));
    };
    let Some(entry) = journal.tabs.get(index) else {
        return Err(format!("entry {index} is not in the journal"));
    };
    // Y28: journal text is untrusted input. A parse failure names the
    // entry and leaves everything (file included) alone.
    let mut doc = jackdaw_bsn::parse_bsn_text(&entry.document)
        .map_err(|err| format!("entry {index} does not parse: {err}"))?;

    let path = entry.path.as_ref().map(PathBuf::from);
    let kind = if entry.kind == "prefab" {
        TabKind::Prefab
    } else {
        TabKind::Scene
    };

    // The journal's prefab sources are spelled for the file they save to;
    // in memory they are absolute against the assets root, exactly as an
    // open rewrites them.
    let parent = path
        .as_deref()
        .and_then(Path::parent)
        .map(Path::to_path_buf)
        .or_else(|| {
            world
                .get_resource::<crate::project::ProjectRoot>()
                .map(crate::project::ProjectRoot::assets_dir)
        })
        .unwrap_or_else(|| PathBuf::from("."));
    let assets_root = crate::prefab::save_load::source_root(world, &parent);
    jackdaw_prefab::absolutize_isa_sources(&mut doc, &assets_root, &parent);
    crate::prefab::save_load::retarget_isa_sources(&mut doc, &assets_root, &parent);
    if kind == TabKind::Scene {
        crate::scene_nodes::name_instance_roots(&mut doc);
    }

    // The clean baseline is the file on disk: hash what a save of that
    // file would emit, so the restored tab reads dirty against it until
    // an explicit save replaces the file. A tab with no file (untitled)
    // has no baseline; growth keeps it dirty the way a fresh tab stays
    // dirty once edited.
    let baseline = path.as_deref().and_then(disk_baseline);

    let n = {
        let mut counter = world.resource_mut::<crate::scenes::operators::UntitledCounter>();
        counter.0 += 1;
        counter.0
    };
    let mut tab = SceneTab::new_untitled(n);
    tab.kind = kind.clone();
    tab.dirty = true;
    tab.saved_at = entry.saved_at.clone();
    match (&path, kind) {
        (Some(path), TabKind::Prefab) => {
            let canonical = crate::prefab::canonical_prefab_path(path);
            world
                .resource_mut::<crate::prefab::PrefabAstCache>()
                .insert(canonical.as_path(), doc);
            tab.path = Some(path.clone());
            tab.display_name = path
                .file_stem()
                .and_then(|stem| stem.to_str())
                .unwrap_or("prefab")
                .to_string();
            tab.content = TabContent::Prefab(canonical);
        }
        (Some(path), TabKind::Scene) => {
            tab.path = Some(path.clone());
            tab.display_name = path
                .file_stem()
                .and_then(|stem| stem.to_str())
                .unwrap_or("scene")
                .to_string();
            tab.content = TabContent::Scene(Some(Box::new(doc)));
        }
        (None, _) => {
            tab.display_name = entry.display_name.clone();
            tab.content = TabContent::Scene(Some(Box::new(doc)));
        }
    }

    // The file the tab points at is its known content from the watcher's
    // point of view, exactly as an open would register it, so the
    // restored tab's own save is never misread as an outside edit.
    if let Some(path) = &path {
        let known = std::fs::read(path).unwrap_or_default();
        crate::scenes::external_watch::note_known_content(world, path, &known);
    }

    let target = world.resource_mut::<Scenes>().push_tab(tab);
    crate::scenes::operators::activate_pushed_tab(world, target);
    let (history_len, history_pushes) = {
        let history = world.resource::<jackdaw_commands::CommandHistory>();
        (history.undo_stack.len(), history.total_pushes())
    };
    if let Some(mut scenes) = world.get_resource_mut::<Scenes>()
        && let Some(tab) = scenes.tabs.get_mut(target)
    {
        tab.dirty = true;
        tab.saved_undo_len = history_len;
        tab.saved_doc_hash = baseline;
        tab.observed_undo_len = history_len;
        tab.observed_pushes = history_pushes;
    }
    let destination = path
        .as_ref()
        .map(|path| path.display().to_string())
        .unwrap_or_else(|| "a file you pick when saving".to_string());
    crate::status_bar::notify_info(
        world,
        format!(
            "Recovered '{}' as an unsaved tab; saving writes it to {destination}",
            entry.display_name
        ),
    );
    info!(
        "recovery: restored '{}' from {} (captured {})",
        entry.display_name,
        dir.display(),
        entry.captured_at
    );
    journal_without(dir, index)
}

/// Discard one journaled tab: its entry leaves the journal (the session
/// directory goes when the last entry does).
pub fn dismiss_tab(dir: &Path, index: usize) -> Result<(), String> {
    journal_without(dir, index)
}

/// The fingerprint a save of the file at `path` would carry, so a
/// restored tab is dirty against exactly what is on disk. `None` when the
/// file is not there (nothing to be dirty against but history).
fn disk_baseline(path: &Path) -> Option<u64> {
    let text = std::fs::read_to_string(path).ok()?;
    // Strip the provenance stamp and asset header the way an in-memory
    // emit has neither.
    let body = text
        .lines()
        .skip_while(|line| line.starts_with("//"))
        .collect::<Vec<_>>()
        .join("\n");
    Some(crate::scene_io::save::document_hash(&body))
}

// -------------------------------------------------------- the operators --

/// Restore one journaled tab as an unsaved, dirty tab.
#[operator(
    id = "recovery.restore",
    label = "Restore Recovered Scene",
    allows_undo = false,
    params(
        session(String, doc = "Name of the recovery session directory."),
        tab(i64, doc = "Index of the entry in that session's journal."),
    )
)]
pub fn recovery_restore(
    In(params): In<OperatorParameters>,
    mut commands: Commands,
) -> OperatorResult {
    let (Some(session), Some(tab)) = (params.as_str("session"), params.as_int("tab")) else {
        warn!("recovery.restore: needs 'session' and 'tab'");
        return OperatorResult::Cancelled;
    };
    let session = session.to_string();
    let index = tab.max(0) as usize;
    commands.queue(move |world: &mut World| {
        let Some(dir) = session_dir_by_name(world, &session) else {
            warn!("recovery.restore: no recovery session named {session}");
            return;
        };
        match restore_tab(world, &dir, index) {
            Ok(()) => despawn_dialog(world),
            Err(err) => {
                warn!("recovery.restore: {err}");
                crate::status_bar::notify_error(world, format!("Could not restore: {err}"));
            }
        }
    });
    OperatorResult::Finished
}

/// Drop one recovery session (`session`), or all of them (`all=true`).
#[operator(
    id = "recovery.dismiss",
    label = "Dismiss Recovery",
    allows_undo = false,
    params(
        session(String, default = "", doc = "Name of the recovery session directory."),
        all(bool, default = false, doc = "Dismiss every leftover session."),
    )
)]
pub fn recovery_dismiss(
    In(params): In<OperatorParameters>,
    mut commands: Commands,
) -> OperatorResult {
    let all = params.as_bool("all").unwrap_or(false);
    let session = params.as_str("session").unwrap_or_default().to_string();
    commands.queue(move |world: &mut World| {
        if all {
            dismiss_all(world);
            despawn_dialog(world);
            return;
        }
        let Some(dir) = session_dir_by_name(world, &session) else {
            warn!("recovery.dismiss: no recovery session named {session}");
            return;
        };
        remove_session(&dir);
        if let Some(mut pending) = world.get_resource_mut::<PendingRecovery>()
            && pending.current.as_deref() == Some(dir.as_path())
        {
            pending.current = None;
        }
        despawn_dialog(world);
    });
    OperatorResult::Finished
}

/// A leftover session directory by the last component of its path.
pub(crate) fn session_dir_by_name(world: &World, name: &str) -> Option<PathBuf> {
    let own = session_journal::session_dir(world);
    let root = leftover_root(world)?;
    session_journal::list_sessions(&root)
        .into_iter()
        .find(|dir| {
            Some(dir) != own.as_ref()
                && dir.join("journal.json").is_file()
                && dir.file_name().is_some_and(|n| n == name)
        })
}
