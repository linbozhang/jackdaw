//! Filesystem operators for the Project window.
//!
//! `file.delete` confirms via a dialog before removing the path from disk,
//! naming what would be left pointing at nothing, `asset.duplicate` copies one
//! file beside itself, `asset.references` reports what points at a file,
//! `file.convert_to_binary` and `file.convert_to_text` rewrite one document in
//! the other form, and `project.export_binary` writes a whole tree out as
//! binary for a shipped game. The Project window reaches these from its
//! right-click menu.

use std::path::{Path, PathBuf};

use bevy::prelude::*;
use jackdaw_api::prelude::*;
use jackdaw_api_internal::operator::{report_to_caller, warn_caller};
use jackdaw_feathers::dialog::{
    DialogActionEvent, DialogDismissEvent, EditorDialog, OpenConfirmationDialogEvent,
};
use path_slash::PathExt as _;

use crate::asset_files::AssetFileKind;
use crate::asset_index::AssetIndex;

/// How many referrers a confirmation names before it counts the rest.
const REFERRERS_NAMED: usize = 3;

pub struct FileOpsPlugin;

impl Plugin for FileOpsPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<PendingFileDelete>()
            .add_observer(on_file_delete_confirmed)
            .add_observer(on_dialog_dismissed);
    }
}

/// Path queued for deletion. Set by `file.delete` when the operator
/// opens the confirmation dialog; consumed by the dialog action observer
/// when the user clicks Delete.
#[derive(Resource, Default)]
pub struct PendingFileDelete {
    pub path: Option<PathBuf>,
}

pub(crate) fn add_to_extension(ctx: &mut ExtensionContext) {
    ctx.register_operator::<FileDeleteOp>();
    ctx.register_operator::<AssetDuplicateOp>();
    ctx.register_operator::<AssetReferencesOp>();
    ctx.register_operator::<FileMoveOp>();
    ctx.register_operator::<FileConvertToBinaryOp>();
    ctx.register_operator::<FileConvertToTextOp>();
    ctx.register_operator::<ProjectExportBinaryOp>();
}

/// The folder an export writes into when none is named: a sibling of the tree.
fn default_export_dir(source: &Path) -> PathBuf {
    let name = source
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| "assets".to_string());
    source
        .parent()
        .unwrap_or(Path::new("."))
        .join(format!("{name}-binary"))
}

/// Confirm and delete a file or directory from disk. The path is taken either
/// from the `path` param (preferred) or, if absent, from the file the Project
/// window has selected.
#[operator(
    id = "file.delete",
    label = "Delete File",
    description = "Remove a file or directory from disk after user confirmation.",
    allows_undo = false,
    params(
        path(String, doc = "Absolute path to the file or directory."),
        force(
            bool,
            doc = "Delete a file other documents reference without asking first."
        )
    )
)]
pub fn file_delete(
    params: In<OperatorParameters>,
    mut commands: Commands,
    project: Option<Res<crate::project_window::ProjectWindowState>>,
) -> OperatorResult {
    let path: Option<PathBuf> = params.as_str("path").map(PathBuf::from).or_else(|| {
        project
            .as_ref()
            .and_then(|state| state.selected_file.as_ref())
            .map(PathBuf::from)
    });
    let Some(path) = path else {
        warn!("file.delete: no path provided and nothing selected in the Project window");
        return OperatorResult::Cancelled;
    };
    if !path.exists() {
        warn!("file.delete: {} does not exist", path.display());
        return OperatorResult::Cancelled;
    }
    let forced = params.as_bool("force").unwrap_or(false);
    commands.queue(move |world: &mut World| {
        ask_to_delete(world, path.clone(), forced);
    });
    OperatorResult::Finished
}

/// Put a file up for deletion: straight away when it was forced, and behind a
/// confirmation otherwise. A file other documents reference says so, and a
/// caller with no dialog to answer is told to force it. A file a tab or a
/// card is standing on is refused outright unless forced - deleting it would
/// leave the tab's next save writing the deleted file back (N3). A
/// confirmation already on screen is the one that stands, so nothing else is
/// queued behind it.
fn ask_to_delete(world: &mut World, path: PathBuf, forced: bool) {
    if let Some(holder) = open_holder(world, &path) {
        if !forced {
            warn_caller(
                world,
                format!(
                    "file.delete: {} is {}; close it first, or pass force to delete it anyway",
                    path.display(),
                    holder
                ),
            );
            return;
        }
        if !close_open_holders(world, &path) {
            warn_caller(
                world,
                format!(
                    "file.delete: {} is {} and closing it would close the last open tab, \
                     so nothing was deleted; close it first",
                    path.display(),
                    holder
                ),
            );
            return;
        }
    }
    if forced {
        delete_path(world, &path);
        return;
    }
    if world
        .query_filtered::<Entity, With<EditorDialog>>()
        .iter(world)
        .next()
        .is_some()
    {
        warn_caller(
            world,
            format!(
                "file.delete: a confirmation is already up, so {} was left alone",
                path.display()
            ),
        );
        return;
    }
    let referrers = referrers_of(world, &path);
    let display = path
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_string_lossy().into_owned());
    let description = if referrers.is_empty() {
        format!("Permanently delete {display}?")
    } else {
        let held = match path.is_dir() {
            true => format!("files in {display}"),
            false => display.clone(),
        };
        let points_at = what_points_at(&held, &referrers);
        warn_caller(
            world,
            format!("file.delete: {points_at}; pass force to delete it anyway"),
        );
        format!("{points_at}. Delete it anyway?")
    };
    world.resource_mut::<PendingFileDelete>().path = Some(path);
    world.trigger(
        OpenConfirmationDialogEvent::new("Delete file", "Delete").with_description(description),
    );
}

/// The documents referring to a file, as the index keys them. A directory
/// answers with what refers to anything it holds, from outside it.
///
/// Beyond the index - which reads the last walk of the files on disk - the
/// references held by the tabs that are open are scanned too, so a delete
/// names the document an unsaved edit is about to save as well (N4).
fn referrers_of(world: &mut World, path: &Path) -> Vec<PathBuf> {
    let Some(indexed) = crate::asset_index::indexed_path(world, path) else {
        return Vec::new();
    };
    if world.get_resource::<AssetIndex>().is_none() {
        return Vec::new();
    }
    let mut found = match path.is_dir() {
        true => world.resource::<AssetIndex>().referrers_under(&indexed),
        false => world.resource::<AssetIndex>().referrers(&indexed).to_vec(),
    };
    found.extend(open_tab_referrers(world, &indexed, path.is_dir()));
    found.sort();
    found.dedup();
    found
}

/// The open tabs whose document 鈥?held in a snapshot, in the prefab cache, or
/// live in the world 鈥?spells a reference to `target` (or, when `dir`, to
/// anything under it), as the paths the index keys them by.
fn open_tab_referrers(world: &mut World, target: &Path, dir: bool) -> Vec<PathBuf> {
    let Some(assets) = crate::asset_index::assets_dir(world) else {
        return Vec::new();
    };
    let tabs: Vec<(usize, Option<PathBuf>)> = {
        let scenes = world.resource::<crate::scenes::Scenes>();
        scenes
            .tabs
            .iter()
            .enumerate()
            .map(|(index, tab)| (index, tab.path.clone()))
            .collect()
    };
    let mut found = Vec::new();
    for (index, path) in tabs {
        let Some(references) = references_of_tab(world, index) else {
            continue;
        };
        let hit = references.iter().any(|reference| {
            let Some(named) = crate::asset_index::referenced_path(
                world.resource::<AssetIndex>(),
                &assets,
                reference,
            ) else {
                return false;
            };
            named == *target || (dir && named.starts_with(target))
        });
        if hit
            && let Some(keyed) = path
                .as_deref()
                .and_then(|path| crate::asset_index::indexed_path(world, path))
        {
            found.push(keyed);
        }
    }
    found
}

/// The references one open tab's document spells. An inactive scene tab
/// answers from the snapshot it holds, a prefab tab from the cache either
/// way, and the active scene tab from the live world, emitted the way a save
/// would write it; a tab that cannot be read costs nothing to ask.
fn references_of_tab(world: &mut World, index: usize) -> Option<Vec<String>> {
    let held = {
        let scenes = world.resource::<crate::scenes::Scenes>();
        match &scenes.tabs.get(index)?.content {
            crate::scenes::TabContent::Scene(Some(ast)) => Some(ast.deep_clone()),
            _ => None,
        }
    };
    if let Some(ast) = held {
        return Some(crate::reference_rewrite::spelled_references(world, &ast));
    }
    let (kind, path) = {
        let scenes = world.resource::<crate::scenes::Scenes>();
        let tab = scenes.tabs.get(index)?;
        (
            matches!(tab.kind, crate::scenes::TabKind::Prefab),
            tab.path.clone()?,
        )
    };
    if kind {
        let canonical = crate::prefab::canonical_prefab_path(&path);
        let ast = world
            .resource::<crate::prefab::PrefabAstCache>()
            .get_canonical(&canonical)
            .map(crate::prefab::resolver_bsn::clone_scene)?;
        return Some(crate::reference_rewrite::spelled_references(world, &ast));
    }
    // The active scene tab: its document is the live world.
    let parent = path.parent().map(Path::to_path_buf)?;
    let text = crate::scene_io::emit_bsn_scene_for_file(world, &parent).ok()?;
    let ast = jackdaw_bsn::parse_bsn_text(&text).ok()?;
    Some(crate::reference_rewrite::spelled_references(world, &ast))
}

/// Whether `path` names `held` itself or sits under it, compared
/// case-insensitively: the filesystem a delete lands on may not care about
/// case, and a tab on `Rat.bsn` stands on `rat.bsn` just the same.
fn stands_on(path: &Path, held: &Path, folder: bool) -> bool {
    let open = dunce::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let open = open.to_slash_lossy().to_lowercase();
    let held = held.to_slash_lossy().to_lowercase();
    open == held || (folder && crate::reference_rewrite::folder_tail(&open, &held).is_some())
}

/// What stands on `path`, if a tab or an editing card does: the tab or card
/// would write the deleted file back at its next save.
fn open_holder(world: &World, path: &Path) -> Option<&'static str> {
    let held = dunce::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let folder = path.is_dir();
    if world
        .get_resource::<crate::scenes::Scenes>()
        .is_some_and(|scenes| {
            scenes.tabs.iter().any(|tab| {
                tab.path
                    .as_deref()
                    .is_some_and(|open| stands_on(open, &held, folder))
            })
        })
    {
        return Some("open in a tab");
    }
    let card = world
        .get_resource::<crate::definition_assets::OpenDefinition>()
        .and_then(|open| open.0)
        .and_then(|entity| world.get::<crate::definition_assets::DefinitionAssetEdit>(entity));
    if let Some(card) = card {
        let editing = crate::asset_index::absolute_path(world, &card.path);
        if stands_on(&editing, &held, folder) {
            return Some("open on a card");
        }
    }
    None
}

/// Close every tab and card standing on `path`, for a forced delete.
/// Answers whether they are all closed: when every open tab stands on the
/// path, closing them would close the last open tab, which the tab strip
/// never does — and deleting under a tab that stayed would resurrect the
/// file at its next save, so the caller refuses the delete instead.
fn close_open_holders(world: &mut World, path: &Path) -> bool {
    let held = dunce::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let folder = path.is_dir();
    // The card first: closing it writes nothing.
    if let Some(entity) = world
        .get_resource::<crate::definition_assets::OpenDefinition>()
        .and_then(|open| open.0)
        && let Some(edit) = world.get::<crate::definition_assets::DefinitionAssetEdit>(entity)
        && stands_on(
            &crate::asset_index::absolute_path(world, &edit.path),
            &held,
            folder,
        )
    {
        crate::definition_assets::close_open_definition(world);
    }
    let holding: Vec<usize> = world
        .resource::<crate::scenes::Scenes>()
        .tabs
        .iter()
        .enumerate()
        .filter(|(_, tab)| {
            tab.path
                .as_deref()
                .is_some_and(|open| stands_on(open, &held, folder))
        })
        .map(|(index, _)| index)
        .collect();
    // No tab may survive the close: the last one the strip always keeps
    // would stay standing on the deleted path, whatever the tab count.
    if holding.len() == world.resource::<crate::scenes::Scenes>().tabs.len() {
        return false;
    }
    for index in holding.into_iter().rev() {
        crate::scenes::operators::scene_close_system_unprompted(world, index);
    }
    true
}

/// What a file's referrers read as: how many there are and the first few by
/// name.
fn what_points_at(display: &str, referrers: &[PathBuf]) -> String {
    let named: Vec<String> = referrers
        .iter()
        .take(REFERRERS_NAMED)
        .map(|path| path.to_slash_lossy().into_owned())
        .collect();
    let rest = referrers.len().saturating_sub(named.len());
    let listed = match rest {
        0 => named.join(", "),
        _ => format!("{} and {rest} more", named.join(", ")),
    };
    let count = referrers.len();
    match count {
        1 => format!("1 document references {display}: {listed}"),
        _ => format!("{count} documents reference {display}: {listed}"),
    }
}

/// A confirmation dismissed unanswered leaves nothing for the next one to take.
fn on_dialog_dismissed(_event: On<DialogDismissEvent>, mut pending: ResMut<PendingFileDelete>) {
    pending.path = None;
}

/// The path is taken here rather than in the queued delete, so a dismissal
/// reaching the queue behind the answer cannot clear it first.
fn on_file_delete_confirmed(
    _event: On<DialogActionEvent>,
    mut pending: ResMut<PendingFileDelete>,
    mut commands: Commands,
) {
    let Some(path) = pending.path.take() else {
        return;
    };
    commands.queue(move |world: &mut World| delete_path(world, &path));
}

/// Remove a path from disk and put the Project window back in step with it.
fn delete_path(world: &mut World, path: &Path) {
    world.resource_mut::<PendingFileDelete>().path = None;
    let result = if path.is_dir() {
        std::fs::remove_dir_all(path)
    } else {
        std::fs::remove_file(path)
    };
    match result {
        Ok(()) => info!("file.delete: removed {}", path.display()),
        Err(err) => {
            warn_caller(
                world,
                format!("file.delete: failed to remove {}: {err}", path.display()),
            );
            return;
        }
    }
    // Drop a selection that pointed at the deleted path so the path bar and
    // the highlight do not lag behind the filesystem.
    let Some(mut project) = world.get_resource_mut::<crate::project_window::ProjectWindowState>()
    else {
        return;
    };
    let deleted = path.to_string_lossy().to_string();
    if project.selected_file.as_deref() == Some(deleted.as_str()) {
        project.selected_file = None;
    }
    project.needs_refresh = true;
    project.needs_tree_refresh = true;
}

/// Copy one file beside itself, under the next free name or the one asked for.
#[operator(
    id = "asset.duplicate",
    label = "Duplicate",
    description = "Copy an asset, scene or prefab file beside itself under a name of its own.",
    allows_undo = false,
    params(
        path(String, doc = "The file to copy."),
        name(
            String,
            doc = "The name to give the copy. Defaults to the next free one."
        )
    )
)]
pub fn asset_duplicate(params: In<OperatorParameters>, mut commands: Commands) -> OperatorResult {
    let Some(path) = params.as_str("path").map(PathBuf::from) else {
        warn!("asset.duplicate: no path given");
        return OperatorResult::Cancelled;
    };
    let name = params.as_str("name").map(str::to_owned);
    commands.queue(move |world: &mut World| {
        duplicate_file(world, &path, name.as_deref());
    });
    OperatorResult::Finished
}

/// Everything after a file's bare name: the `.material.bsn` of
/// `slate.material.bsn`.
fn file_suffix(path: &Path) -> String {
    let name = path
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default();
    match name.find('.') {
        Some(dot) => name[dot..].to_string(),
        None => String::new(),
    }
}

/// The name a copy counts up from: `slate` for `slate` and for `slate_2`
/// alike, so a copy of a copy is `slate_3` rather than `slate_2_1`.
fn counting_base(stem: &str) -> &str {
    let Some((base, counter)) = stem.rsplit_once('_') else {
        return stem;
    };
    let counted = !base.is_empty()
        && !counter.is_empty()
        && counter.chars().all(|digit| digit.is_ascii_digit());
    match counted {
        true => base,
        false => stem,
    }
}

/// The first of `name_1`, `name_2` that no file in `parent` answers to.
fn next_free_stem(parent: &Path, stem: &str, suffix: &str) -> String {
    let base = counting_base(stem);
    for counter in 1..1000 {
        let candidate = format!("{base}_{counter}");
        let file = parent.join(format!("{candidate}{suffix}"));
        if !file.exists() && jackdaw_bsn::existing_form(&file).is_none() {
            return candidate;
        }
    }
    format!("{stem}_copy")
}

/// A name as a document spells it: bare where every character allows it, and
/// quoted otherwise.
fn name_line(name: &str) -> String {
    let bare = !name.is_empty()
        && name
            .chars()
            .all(|part| part.is_ascii_alphanumeric() || part == '_');
    match bare {
        true => format!("#{name}"),
        false => format!("#\"{name}\""),
    }
}

/// The document with its root renamed, so a duplicated asset is not a second
/// file answering to the same name. Only the name the root carries is touched,
/// and a root carrying none is given one. A scene or a prefab is used by the
/// file it sits in rather than by that name, so neither goes through here.
fn with_root_named(text: &str, name: &str) -> String {
    let named = name_line(name);
    let mut renamed = false;
    let mut lines: Vec<String> = Vec::new();
    for line in text.lines() {
        if !renamed && line.starts_with('#') {
            renamed = true;
            lines.push(format!("{named}{}", after_name(line)));
            continue;
        }
        lines.push(line.to_string());
    }
    if !renamed {
        lines.insert(body_starts_at(&lines), named);
    }
    let mut written = lines.join("\n");
    written.push('\n');
    written
}

/// Whatever a line carrying a name holds after it, for the documents that put
/// the root's first patch on the same line.
fn after_name(line: &str) -> &str {
    let mut rest = line[1..].chars();
    let mut taken = 1;
    match rest.next() {
        Some('"') => {
            taken += 1;
            let mut escaped = false;
            for character in rest {
                taken += character.len_utf8();
                match character {
                    _ if escaped => escaped = false,
                    '\\' => escaped = true,
                    '"' => break,
                    _ => {}
                }
            }
        }
        _ => {
            taken += line[1..]
                .chars()
                .take_while(|part| part.is_ascii_alphanumeric() || *part == '_')
                .map(char::len_utf8)
                .sum::<usize>();
        }
    }
    &line[taken.min(line.len())..]
}

/// The line the document proper starts on, after the comments that carry its
/// header and its version stamp.
fn body_starts_at(lines: &[String]) -> usize {
    lines
        .iter()
        .position(|line| {
            let trimmed = line.trim();
            !trimmed.is_empty() && !trimmed.starts_with("//")
        })
        .unwrap_or(lines.len())
}

/// Copy a file beside itself, index what the copy holds and put the inspector
/// on it. Reports the copy's path, so a caller with no viewport knows where it
/// landed.
fn duplicate_file(world: &mut World, path: &Path, name: Option<&str>) -> Option<PathBuf> {
    let path = crate::definition_assets::resolve_project_path(world, path);
    let path = jackdaw_bsn::existing_form(&path).unwrap_or(path);
    if !path.is_file() {
        warn_caller(
            world,
            format!("asset.duplicate: {} is not a file", path.display()),
        );
        return None;
    }
    let parent = path.parent()?.to_path_buf();
    let suffix = file_suffix(&path);
    let stem = match name {
        Some(name) => crate::definition_assets::sanitize_definition_name(&jackdaw_bsn::path_stem(
            Path::new(name),
        )),
        None => next_free_stem(&parent, &jackdaw_bsn::path_stem(&path), &suffix),
    };
    let target = parent.join(format!("{stem}{suffix}"));
    if target.exists() || jackdaw_bsn::existing_form(&target).is_some() {
        warn_caller(
            world,
            format!("asset.duplicate: {} is already there", target.display()),
        );
        return None;
    }
    let kind = {
        let kinds = world.resource::<AssetKinds>();
        crate::asset_files::read_asset_kind(&path, kinds)
    };
    if !jackdaw_bsn::is_document_path(&path) {
        if let Err(err) = std::fs::copy(&path, &target) {
            warn_caller(
                world,
                format!(
                    "asset.duplicate: {} could not be written: {err}",
                    target.display()
                ),
            );
            return None;
        }
    } else {
        let text = match jackdaw_bsn::read_document_text(&path) {
            Ok(text) => text,
            Err(err) => {
                warn_caller(world, format!("asset.duplicate: {err}"));
                return None;
            }
        };
        let text = match kind {
            AssetFileKind::Asset { .. } => with_root_named(&text, &stem),
            _ => text,
        };
        let written = jackdaw_bsn::document_bytes(&target, &text)
            .map_err(std::io::Error::other)
            .and_then(|bytes| crate::scene_io::save::write_atomic(&target, &bytes));
        if let Err(err) = written {
            warn_caller(
                world,
                format!(
                    "asset.duplicate: {} could not be written: {err}",
                    target.display()
                ),
            );
            return None;
        }
    }
    index_duplicate(world, &target);
    crate::project_window::select_path(world, &target);
    let shown = crate::asset_index::indexed_path(world, &target).unwrap_or_else(|| target.clone());
    report_to_caller(world, shown.to_slash_lossy().into_owned());
    Some(target)
}

/// Put a freshly written copy in the index, so it answers to its path without
/// waiting for the watcher.
fn index_duplicate(world: &mut World, target: &Path) {
    let Some(kind) = crate::definition_assets::kind_of_file(world, target) else {
        return;
    };
    let Some(value) = crate::asset_index::load_asset_value(world, &kind, target) else {
        return;
    };
    crate::asset_index::index_written(world, target, &kind, value);
}

/// Report every document whose patches reference a file.
#[operator(
    id = "asset.references",
    label = "List References",
    description = "Report every document whose patches reference a file.",
    allows_undo = false,
    params(path(String, doc = "The file to report on."))
)]
pub fn asset_references(params: In<OperatorParameters>, mut commands: Commands) -> OperatorResult {
    let Some(path) = params.as_str("path").map(PathBuf::from) else {
        warn!("asset.references: no path given");
        return OperatorResult::Cancelled;
    };
    commands.queue(move |world: &mut World| {
        let resolved = crate::definition_assets::resolve_project_path(world, &path);
        let shown = crate::asset_index::indexed_path(world, &resolved)
            .unwrap_or_else(|| path.clone())
            .to_slash_lossy()
            .into_owned();
        let referrers = referrers_of(world, &resolved);
        let message = match referrers.is_empty() {
            true => format!("nothing references {shown}"),
            false => format!(
                "{shown} is referenced by {}",
                referrers
                    .iter()
                    .map(|path| path.to_slash_lossy().into_owned())
                    .collect::<Vec<_>>()
                    .join(", ")
            ),
        };
        report_to_caller(world, message);
    });
    OperatorResult::Finished
}

/// Move a file into another folder in the project's assets, following it
/// with the whole chain a rename does: the documents that spelled the old
/// path are rewritten, the tabs and cards standing on the file are
/// retargeted, and the report says how much was rewritten (N2).
#[operator(
    id = "file.move",
    label = "Move",
    description = "Move a file or folder into another folder under the project's assets.",
    allows_undo = false,
    params(
        path(String, doc = "The file or folder to move."),
        folder(
            String,
            doc = "The folder to move it into, under the project's assets."
        )
    )
)]
pub fn file_move(params: In<OperatorParameters>, mut commands: Commands) -> OperatorResult {
    let Some(path) = params.as_str("path").map(PathBuf::from) else {
        warn!("file.move: no path given");
        return OperatorResult::Cancelled;
    };
    let Some(folder) = params.as_str("folder").map(PathBuf::from) else {
        warn!("file.move: no folder given");
        return OperatorResult::Cancelled;
    };
    commands.queue(move |world: &mut World| {
        move_file(world, &path, &folder);
    });
    OperatorResult::Finished
}

/// Move `path` under `folder`. Both are resolved against the project; the
/// destination must be a folder in the project's assets, and the move keeps
/// the file's own name.
fn move_file(world: &mut World, path: &Path, folder: &Path) {
    let path = crate::definition_assets::resolve_project_path(world, path);
    let folder = crate::definition_assets::resolve_project_path(world, folder);
    if !path.exists() {
        warn_caller(
            world,
            format!("file.move: {} does not exist", path.display()),
        );
        return;
    }
    if !folder.is_dir() {
        warn_caller(
            world,
            format!("file.move: {} is not a folder", folder.display()),
        );
        return;
    }
    if crate::asset_index::indexed_path(world, &folder).is_none() {
        warn_caller(
            world,
            format!(
                "file.move: {} is outside the project's assets",
                folder.display()
            ),
        );
        return;
    }
    let Some(name) = path.file_name() else {
        return;
    };
    let target = folder.join(name);
    if target.exists() {
        warn_caller(
            world,
            format!("file.move: {} is already there", target.display()),
        );
        return;
    }
    // The referrers table the rewrite matches against is the one from before
    // the move.
    crate::asset_index::rescan_asset_index(world);
    // A folder the open-tab watcher holds a handle inside cannot be moved on
    // Windows; the watches under it are let go first.
    if path.is_dir() {
        crate::scenes::external_watch::release_watch_under(world, &path);
    }
    if let Err(err) = std::fs::rename(&path, &target) {
        warn_caller(
            world,
            format!("file.move: {} could not be moved: {err}", path.display()),
        );
        return;
    }
    crate::reference_rewrite::follow_a_move(world, &path, &target, "moved");
    if let Some(mut state) = world.get_resource_mut::<crate::project_window::ProjectWindowState>() {
        state.needs_refresh = true;
        state.needs_tree_refresh = true;
    }
    crate::project_window::select_path(world, &target);
}

/// Rewrite one document as its binary twin, in place.
#[operator(
    id = "file.convert_to_binary",
    label = "Convert to Binary",
    description = "Rewrite one BSN document in the binary form, removing the text file.",
    allows_undo = false,
    params(path(String, doc = "The document to convert."))
)]
pub fn file_convert_to_binary(
    params: In<OperatorParameters>,
    scenes: Option<Res<crate::scenes::Scenes>>,
) -> OperatorResult {
    convert_document(
        params.as_str("path"),
        jackdaw_bsn::DocumentForm::Binary,
        scenes.as_deref(),
    )
}

/// Rewrite one document as `.bsn` text, in place.
#[operator(
    id = "file.convert_to_text",
    label = "Convert to Text",
    description = "Rewrite one BSN document in the text form, removing the binary file.",
    allows_undo = false,
    params(path(String, doc = "The document to convert."))
)]
pub fn file_convert_to_text(
    params: In<OperatorParameters>,
    scenes: Option<Res<crate::scenes::Scenes>>,
) -> OperatorResult {
    convert_document(
        params.as_str("path"),
        jackdaw_bsn::DocumentForm::Text,
        scenes.as_deref(),
    )
}

fn convert_document(
    path: Option<&str>,
    to: jackdaw_bsn::DocumentForm,
    scenes: Option<&crate::scenes::Scenes>,
) -> OperatorResult {
    let Some(path) = path.map(PathBuf::from) else {
        warn!("convert: no path provided");
        return OperatorResult::Cancelled;
    };
    if !jackdaw_bsn::is_document_path(&path) {
        warn!("convert: {} is not a BSN document", path.display());
        return OperatorResult::Cancelled;
    }
    if scenes.is_some_and(|scenes| is_open_in_a_tab(scenes, &path)) {
        warn!(
            "convert: {} is open; close its tab before changing the form it is held in",
            path.display()
        );
        return OperatorResult::Cancelled;
    }
    let converted = match to {
        jackdaw_bsn::DocumentForm::Binary => jackdaw_bsn::convert_to_binary(&path),
        jackdaw_bsn::DocumentForm::Text => jackdaw_bsn::convert_to_text(&path),
    };
    match converted {
        Ok(written) => {
            info!("{} is now {}", path.display(), written.display());
            OperatorResult::Finished
        }
        Err(err) => {
            warn!("convert: {err}");
            OperatorResult::Cancelled
        }
    }
}

/// Whether a tab holds the document at `path`, whose file a conversion moves.
fn is_open_in_a_tab(scenes: &crate::scenes::Scenes, path: &Path) -> bool {
    let held = dunce::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    scenes.tabs.iter().any(|tab| {
        tab.path
            .as_ref()
            .map(|open| dunce::canonicalize(open).unwrap_or_else(|_| open.clone()))
            .is_some_and(|open| open == held)
    })
}

/// Write a tree of documents out in the binary form, for a shipped game.
#[operator(
    id = "project.export_binary",
    label = "Export Binary Assets",
    description = "Write every BSN document under a folder out in the binary form, leaving the \
                   source files as they are and copying everything else through.",
    allows_undo = false,
    params(
        path(
            String,
            doc = "The folder to convert. Defaults to the project's assets folder."
        ),
        out(
            String,
            doc = "The folder to write into. Defaults to a sibling of the source."
        )
    )
)]
pub fn project_export_binary(
    params: In<OperatorParameters>,
    project: Option<Res<crate::project::ProjectRoot>>,
) -> OperatorResult {
    let source = params
        .as_str("path")
        .map(PathBuf::from)
        .or_else(|| project.as_ref().map(|project| project.assets_dir()));
    let Some(source) = source else {
        warn!("project.export_binary: no folder to convert");
        return OperatorResult::Cancelled;
    };
    if !source.is_dir() {
        warn!(
            "project.export_binary: {} is not a folder",
            source.display()
        );
        return OperatorResult::Cancelled;
    }
    let destination = params
        .as_str("out")
        .map(PathBuf::from)
        .unwrap_or_else(|| default_export_dir(&source));
    match jackdaw_bsn::export_binary(&source, &destination) {
        Ok(converted) => {
            info!(
                "exported {converted} documents from {} into {}",
                source.display(),
                destination.display()
            );
            OperatorResult::Finished
        }
        Err(err) => {
            warn!("project.export_binary: {err}");
            OperatorResult::Cancelled
        }
    }
}
