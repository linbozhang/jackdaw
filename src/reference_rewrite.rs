//! Rewriting the references documents spell, when the file a reference names
//! moves.
//!
//! A reference is a path a document holds in a field whose type names an
//! asset (a `Handle<T>` and friends), a string under the `@` sigil, or a
//! `:`-base pointing at another document. When a file — or a folder of them —
//! arrives at a new path, [`follow_a_move`] rewrites every document that
//! spelled the old path, retargets the tabs and cards standing on the file,
//! and keeps the editor's own bookkeeping (the asset index, the crash
//! journal, the open-tab watcher) in step, so nothing reads the rewrite back
//! as a change made behind the editor's back.
//!
//! The rewrite itself is a value replacement on the document's AST, not a
//! text substitution: a string that merely reads like the old path in a
//! non-asset field is left exactly as it is.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use bevy::prelude::*;
use jackdaw_api_internal::operator::report_to_caller;
use jackdaw_bsn::{BsnPatch, BsnValue, SceneBsnAst};
use path_slash::PathExt as _;

use crate::asset_index::{AssetIndex, assets_dir, rescan_asset_index};

/// How a rewrite decides that a reference is one to replace.
#[derive(Clone, Debug)]
pub enum ReferenceMove {
    /// The reference spells `from` exactly: a path, a bare name, an `@name`.
    Spelled { from: String, to: String },
    /// The reference names the file at `path` — exactly, through its binary
    /// twin, or by a stem the project's documents hold uniquely — or, when
    /// `folder` is set, any file under the folder at `path`, matched on path
    /// components so `props` never reaches into `props2`.
    Names {
        path: String,
        to: String,
        folder: bool,
    },
}

/// What a run of rewrites changed.
#[derive(Default)]
pub struct RewriteOutcome {
    pub references: usize,
    pub documents: usize,
    pub failures: Vec<String>,
}

impl RewriteOutcome {
    fn note(&mut self, replaced: usize) {
        self.references += replaced;
        self.documents += 1;
    }

    fn said(&self, what: &str) -> String {
        match self.documents {
            0 => format!("{what}; rewrote 0 references"),
            _ => format!(
                "{what}; rewrote {} references in {} documents",
                self.references, self.documents
            ),
        }
    }
}

/// Every reference a document spells, as the strings it holds. Only a field
/// whose type names an asset by path counts, so a string that happens to
/// read like a name is left alone; a string under the `@` sigil counts
/// wherever it sits, since nothing else spells one; a `:`-base is a document
/// path wherever it sits. Nested values name their own type, so a reference
/// inside a brush face is found the same way as one on a component.
pub(crate) fn spelled_references(world: &World, ast: &SceneBsnAst) -> Vec<String> {
    let Some(registry) = world.get_resource::<AppTypeRegistry>() else {
        return Vec::new();
    };
    let registry = registry.read();
    let mut found: Vec<String> = Vec::new();
    let mut bases: Vec<String> = Vec::new();
    for entity in ast.world.iter_entities() {
        let Some(patch) = entity.get::<BsnPatch>() else {
            continue;
        };
        match patch {
            BsnPatch::Struct(data) => {
                scan_struct(&registry, data, &mut found);
            }
            BsnPatch::TupleStruct(data) => {
                for value in &data.values {
                    scan_value(&registry, None, value, &mut found);
                }
            }
            BsnPatch::Template(_, Some(fields)) => {
                for field in &fields.0 {
                    scan_value(&registry, None, &field.value, &mut found);
                }
            }
            BsnPatch::Base(base) => bases.push(base.clone()),
            _ => {}
        }
    }
    found.extend(bases);
    found.sort();
    found.dedup();
    found
}

/// Read the fields of one struct, by the type it names.
fn scan_struct(
    registry: &bevy::reflect::TypeRegistry,
    data: &jackdaw_bsn::BsnStructData,
    found: &mut Vec<String>,
) {
    let info = registry
        .get_with_type_path(&data.type_path)
        .map(bevy::reflect::TypeRegistration::type_info);
    for field in &data.fields.0 {
        let field_type = match info {
            Some(bevy::reflect::TypeInfo::Struct(info)) => info
                .field(&field.name)
                .map(bevy::reflect::NamedField::type_id),
            _ => None,
        };
        scan_value(registry, field_type, &field.value, found);
    }
}

/// The type the items of a list or an array hold.
fn item_type(
    registry: &bevy::reflect::TypeRegistry,
    type_id: std::any::TypeId,
) -> Option<std::any::TypeId> {
    match registry.get(type_id)?.type_info() {
        bevy::reflect::TypeInfo::List(info) => Some(info.item_ty().id()),
        bevy::reflect::TypeInfo::Array(info) => Some(info.item_ty().id()),
        _ => None,
    }
}

fn scan_value(
    registry: &bevy::reflect::TypeRegistry,
    field_type: Option<std::any::TypeId>,
    value: &BsnValue,
    found: &mut Vec<String>,
) {
    match value {
        BsnValue::String(reference) => {
            let takes_path = field_type
                .is_some_and(|type_id| crate::typed_values::takes_asset_path(registry, type_id));
            if (takes_path || reference.starts_with('@'))
                && !reference.is_empty()
                && !found.contains(reference)
            {
                found.push(reference.clone());
            }
        }
        BsnValue::Struct(data) => scan_struct(registry, data, found),
        BsnValue::TupleStruct(data) => {
            for value in &data.values {
                scan_value(registry, None, value, found);
            }
        }
        BsnValue::List(values) => {
            let item = field_type.and_then(|type_id| item_type(registry, type_id));
            for value in values {
                scan_value(registry, item, value, found);
            }
        }
        BsnValue::Map(pairs) => {
            for (_, value) in pairs {
                scan_value(registry, field_type, value, found);
            }
        }
        _ => {}
    }
}

/// What `reference` becomes under `moves`, if it is one to replace.
///
/// The `index` answers the stem question: a bare name counts only while it
/// uniquely names the very path being moved, so a name two documents share
/// never drags either along.
fn replacement(reference: &str, moves: &[ReferenceMove], index: &AssetIndex) -> Option<String> {
    for what in moves {
        match what {
            ReferenceMove::Spelled { from, to } => {
                if reference == from {
                    return Some(to.clone());
                }
            }
            ReferenceMove::Names { path, to, folder } => {
                if reference == path {
                    return Some(to.clone());
                }
                if is_twin_spelling(reference, path) {
                    let dot = reference.rfind('.').unwrap_or(reference.len());
                    return Some(format!("{to}{}", &reference[dot..]));
                }
                if *folder && let Some(rest) = folder_tail(reference, path) {
                    return Some(format!("{to}/{rest}"));
                }
                if !*folder && names_by_stem(reference, path, index) {
                    return Some(to.clone());
                }
            }
        }
    }
    None
}

/// Whether `reference` is the binary twin spelling of `path` (`a.bsb` for
/// `a.bsn`).
fn is_twin_spelling(reference: &str, path: &str) -> bool {
    let twin = jackdaw_bsn::binary_twin(Path::new(path));
    reference == twin.to_slash_lossy()
}

/// The part of `reference` after the `path/` folder prefix, when `reference`
/// sits under that folder and the prefix ends on a path-component boundary.
pub(crate) fn folder_tail(reference: &str, path: &str) -> Option<String> {
    reference
        .strip_prefix(&format!("{path}/"))
        .filter(|rest| !rest.is_empty())
        .map(str::to_string)
}

/// Whether `reference` is the bare or `@`-sigilled stem of `path`, naming it
/// uniquely among the project's documents.
fn names_by_stem(reference: &str, path: &str, index: &AssetIndex) -> bool {
    let spelled = reference.strip_prefix('@').unwrap_or(reference);
    if spelled.is_empty() || spelled.contains('/') {
        return false;
    }
    let stem = jackdaw_bsn::asset_stem(spelled);
    index
        .stems()
        .unique(stem)
        .is_some_and(|held| held.to_slash_lossy() == Path::new(path).to_slash_lossy())
}

/// Rewrite the references `ast` spells in place, answering how many values
/// were replaced.
pub(crate) fn rewrite_ast(world: &World, ast: &mut SceneBsnAst, moves: &[ReferenceMove]) -> usize {
    if moves.is_empty() {
        return 0;
    }
    let Some(index) = world.get_resource::<AssetIndex>() else {
        return 0;
    };
    let Some(registry) = world.get_resource::<AppTypeRegistry>().cloned() else {
        return 0;
    };
    let registry = registry.read();
    let mut replaced = 0usize;
    let mut patches = ast.world.query::<&mut BsnPatch>();
    for mut patch in patches.iter_mut(&mut ast.world) {
        match &mut *patch {
            BsnPatch::Struct(data) => {
                rewrite_struct(&registry, data, moves, index, &mut replaced);
            }
            BsnPatch::TupleStruct(data) => {
                for value in &mut data.values {
                    rewrite_value(&registry, None, value, moves, index, &mut replaced);
                }
            }
            BsnPatch::Template(_, Some(fields)) => {
                for field in &mut fields.0 {
                    rewrite_value(
                        &registry,
                        None,
                        &mut field.value,
                        moves,
                        index,
                        &mut replaced,
                    );
                }
            }
            BsnPatch::Base(base) => {
                if let Some(now) = replacement(base, moves, index) {
                    *base = now;
                    replaced += 1;
                }
            }
            _ => {}
        }
    }
    replaced
}

fn rewrite_struct(
    registry: &bevy::reflect::TypeRegistry,
    data: &mut jackdaw_bsn::BsnStructData,
    moves: &[ReferenceMove],
    index: &AssetIndex,
    replaced: &mut usize,
) {
    let info = registry
        .get_with_type_path(&data.type_path)
        .map(bevy::reflect::TypeRegistration::type_info);
    for field in &mut data.fields.0 {
        let field_type = match info {
            Some(bevy::reflect::TypeInfo::Struct(info)) => info
                .field(&field.name)
                .map(bevy::reflect::NamedField::type_id),
            _ => None,
        };
        rewrite_value(
            registry,
            field_type,
            &mut field.value,
            moves,
            index,
            replaced,
        );
    }
}

fn rewrite_value(
    registry: &bevy::reflect::TypeRegistry,
    field_type: Option<std::any::TypeId>,
    value: &mut BsnValue,
    moves: &[ReferenceMove],
    index: &AssetIndex,
    replaced: &mut usize,
) {
    match value {
        BsnValue::String(reference) => {
            let takes_path = field_type
                .is_some_and(|type_id| crate::typed_values::takes_asset_path(registry, type_id));
            if !takes_path && !reference.starts_with('@') {
                return;
            }
            if let Some(now) = replacement(reference, moves, index) {
                *reference = now;
                *replaced += 1;
            }
        }
        BsnValue::Struct(data) => rewrite_struct(registry, data, moves, index, replaced),
        BsnValue::TupleStruct(data) => {
            for value in &mut data.values {
                rewrite_value(registry, None, value, moves, index, replaced);
            }
        }
        BsnValue::List(values) => {
            let item = field_type.and_then(|type_id| item_type(registry, type_id));
            for value in values {
                rewrite_value(registry, item, value, moves, index, replaced);
            }
        }
        BsnValue::Map(pairs) => {
            for (_, value) in pairs.iter_mut() {
                rewrite_value(registry, field_type, value, moves, index, replaced);
            }
        }
        _ => {}
    }
}

/// Rewrite one document on disk. The document keeps the form it is held in
/// and the comment lines it opens with; the write lands atomically and is
/// noted, so neither the asset index nor the open-tab watcher reads it back.
/// Answers how many references were replaced, or `None` when the document
/// could not be read or written.
pub(crate) fn rewrite_document(
    world: &mut World,
    file: &Path,
    moves: &[ReferenceMove],
) -> Option<usize> {
    let document = jackdaw_bsn::read_document(file).ok()?;
    let mut ast = document.ast;
    let replaced = rewrite_ast(world, &mut ast, moves);
    if replaced == 0 {
        return Some(0);
    }
    let text = jackdaw_bsn::document_as_text(&ast, document.preamble.as_deref());
    let bytes = jackdaw_bsn::document_bytes(file, &text).ok()?;
    crate::scene_io::save::write_atomic(file, &bytes).ok()?;
    crate::asset_migration::note_written(world, file);
    Some(replaced)
}

/// Rewrite every document in `holders` (as the index keys them) that spells
/// one of `moves`. A document held in binary form is rewritten in that form.
pub(crate) fn rewrite_documents(
    world: &mut World,
    holders: &[PathBuf],
    moves: &[ReferenceMove],
) -> RewriteOutcome {
    let mut outcome = RewriteOutcome::default();
    let Some(assets) = assets_dir(world) else {
        return outcome;
    };
    for relative in holders {
        let file = jackdaw_bsn::existing_form(&assets.join(relative))
            .unwrap_or_else(|| assets.join(relative));
        if !file.is_file() {
            continue;
        }
        match rewrite_document(world, &file, moves) {
            Some(0) => continue,
            Some(replaced) => outcome.note(replaced),
            None => outcome
                .failures
                .push(relative.to_slash_lossy().into_owned()),
        }
    }
    outcome
}

/// The documents the index saw referring to the file at `relative` — or,
/// when `relative` is a folder, to anything it holds, from wherever the
/// referring document sits. The index is a snapshot from the last walk, so a
/// caller moves the file first and reads the table it left.
pub(crate) fn referrers_of_move(world: &World, relative: &Path, folder: bool) -> Vec<PathBuf> {
    let index = world.resource::<AssetIndex>();
    let mut holders: BTreeSet<PathBuf> = match folder {
        true => index
            .referrers_including_within(relative)
            .into_iter()
            .collect(),
        false => index.referrers(relative).iter().cloned().collect(),
    };
    holders.remove(relative);
    holders.into_iter().collect()
}

// -- The follow-through of one file arriving at a new path --------------------

/// Everything that follows a file or folder arriving at a new path on disk:
/// the documents that spelled the old path are rewritten, the tabs and cards
/// standing on the file are retargeted (their in-memory references rewritten
/// too, a clean tab kept clean by recomputing its baseline, a dirty one kept
/// dirty), the index and the crash journal are brought forward, and the
/// caller's report says how much was rewritten.
///
/// The caller has already moved the file and holds a fresh index (a rescan
/// before the move), which the stem matching reads.
pub(crate) fn follow_a_move(world: &mut World, old: &Path, new: &Path, what: &str) {
    let old_indexed =
        crate::asset_index::indexed_path(world, old).unwrap_or_else(|| old.to_path_buf());
    let new_indexed =
        crate::asset_index::indexed_path(world, new).unwrap_or_else(|| new.to_path_buf());
    let folder = new.is_dir();

    // The referrers table is the one from before the move; the stems it
    // counted still resolve the old spelling, which is exactly what the
    // rewrite matches against.
    let holders = referrers_of_move(world, &old_indexed, folder);
    let moves = vec![ReferenceMove::Names {
        path: old_indexed.to_slash_lossy().into_owned(),
        to: new_indexed.to_slash_lossy().into_owned(),
        folder,
    }];
    let mut outcome = rewrite_documents(world, &holders, &moves);
    for failed in std::mem::take(&mut outcome.failures) {
        report_to_caller(world, format!("{what}: {failed} could not be rewritten"));
    }

    // Retarget before the index moves on: the stems the rewrite matches bare
    // names against still resolve the old spelling.
    let holding = retarget_tabs(world, old, new, &moves);
    retarget_cards(world, &old_indexed, &new_indexed, folder);

    // The entries move with their files, keeping every loaded handle: a
    // rename must not orphan what already references the asset, or the next
    // save writes the old path back.
    migrate_index_entries(world, &old_indexed, &new_indexed, folder);

    // The rescan rebuilds the referrers table over the rewritten documents
    // and re-derives the name index; the moved entries hold the mtime the
    // files kept through the rename, so their handles and values are left
    // alone.
    rescan_asset_index(world);
    recompute_clean_baselines(world, &holding);

    // A dirty tab's journal entry still names the old path; the crash
    // journal is the one place that outlives this frame.
    crate::scene_io::session_journal::write_snapshot(world);

    report_to_caller(world, outcome.said(what));
    crate::status_bar::notify_info(world, outcome.said(what));
}

/// Put every open tab that stood on `old` — or under it, when a folder moved
/// — onto `new`: the path the tab saves through, the prefab cache entry a
/// prefab tab keys into, and the references its held document spells.
/// Answers the indices of the tabs that were retargeted, so the caller can
/// recompute their clean baselines once the index has moved on.
fn retarget_tabs(world: &mut World, old: &Path, new: &Path, moves: &[ReferenceMove]) -> Vec<usize> {
    let old_canonical = dunce::canonicalize(old).unwrap_or_else(|_| old.to_path_buf());
    let new_canonical = dunce::canonicalize(new).unwrap_or_else(|_| new.to_path_buf());
    let active = world.resource::<crate::scenes::Scenes>().active;
    let holding: Vec<usize> = {
        let scenes = world.resource::<crate::scenes::Scenes>();
        scenes
            .tabs
            .iter()
            .enumerate()
            .filter(|(_, tab)| stands_on(tab, &old_canonical))
            .map(|(index, _)| index)
            .collect()
    };
    for &index in &holding {
        {
            let mut scenes = world.resource_mut::<crate::scenes::Scenes>();
            scenes.set_changed();
            let Some(tab) = scenes.tabs.get_mut(index) else {
                continue;
            };
            tab.path = Some(new_canonical.clone());
            if let Some(stem) = new_canonical.file_stem() {
                tab.display_name = stem.to_string_lossy().into_owned();
            }
        }
        let held_prefab = {
            let scenes = world.resource::<crate::scenes::Scenes>();
            match &scenes.tabs[index].content {
                crate::scenes::TabContent::Prefab(path) => Some(path.clone()),
                _ => None,
            }
        };
        match held_prefab {
            // A scene tab: the active one's references in the live world are
            // handles, which the rescan follows by id — but the live
            // document AST is what the world is rebuilt from, so its spelled
            // values move too. An inactive one holds its own snapshot,
            // rewritten in place through a copy so the world is free for the
            // lookup.
            None => {
                if index == active {
                    let live = world.remove_resource::<jackdaw_bsn::SceneBsnAst>();
                    if let Some(mut ast) = live {
                        rewrite_ast(world, &mut ast, moves);
                        world.insert_resource(ast);
                    }
                }
                let stash = {
                    let scenes = world.resource::<crate::scenes::Scenes>();
                    match &scenes.tabs[index].content {
                        crate::scenes::TabContent::Scene(Some(ast)) => Some(ast.deep_clone()),
                        _ => None,
                    }
                };
                if let Some(mut ast) = stash {
                    rewrite_ast(world, &mut ast, moves);
                    let mut scenes = world.resource_mut::<crate::scenes::Scenes>();
                    scenes.tabs[index].content =
                        crate::scenes::TabContent::Scene(Some(Box::new(ast)));
                }
            }
            // A prefab tab keys into the cache, active or not: the entry
            // moves to the new key with its references rewritten, keeping
            // the saved fingerprint the watcher compares against.
            Some(held) => {
                let moved = crate::prefab::canonical_prefab_path(&new_canonical);
                let entry = world
                    .resource::<crate::prefab::PrefabAstCache>()
                    .get(held.as_path())
                    .map(crate::prefab::resolver_bsn::clone_scene);
                if let Some(mut ast) = entry {
                    rewrite_ast(world, &mut ast, moves);
                    let fingerprint = world
                        .resource::<crate::prefab::PrefabAstCache>()
                        .last_saved_fingerprint(held.as_path())
                        .cloned();
                    let mut cache = world.resource_mut::<crate::prefab::PrefabAstCache>();
                    cache.invalidate(held.as_path());
                    cache.insert(moved.as_path(), ast);
                    if let Some(fingerprint) = fingerprint {
                        cache.record_saved_fingerprint(moved.as_path(), fingerprint);
                    }
                }
                let mut scenes = world.resource_mut::<crate::scenes::Scenes>();
                scenes.tabs[index].content = crate::scenes::TabContent::Prefab(moved);
            }
        }
    }
    holding
}

/// A clean tab stays clean across a move: the baseline is recomputed over
/// the rewritten document, now that the index spells every reference the way
/// the rewrite left it. The active tab's document is the live world, so its
/// baseline is the live fingerprint; an inactive tab's is the document it
/// holds, emitted the way a save would. A dirty tab keeps its baseline: the
/// rewrite is not the user's edit, but the tab has edits of its own that the
/// baseline still guards.
fn recompute_clean_baselines(world: &mut World, holding: &[usize]) {
    let active = world.resource::<crate::scenes::Scenes>().active;
    for &index in holding {
        let (dirty, refused) = {
            let tab = &world.resource::<crate::scenes::Scenes>().tabs[index];
            (tab.dirty, tab.is_refused())
        };
        if dirty || refused {
            continue;
        }
        let fresh = if index == active {
            crate::scene_io::document_fingerprint(world)
        } else {
            crate::scene_io::session_journal::stashed_document(world, index)
                .as_deref()
                .map(crate::scene_io::save::document_hash)
        };
        if let Some(fresh) = fresh {
            let mut scenes = world.resource_mut::<crate::scenes::Scenes>();
            scenes.set_changed();
            if let Some(tab) = scenes.tabs.get_mut(index) {
                tab.saved_doc_hash = Some(fresh);
            }
        }
    }
}

/// Whether a tab's file is `moved` itself or sits under it.
fn stands_on(tab: &crate::scenes::SceneTab, moved: &Path) -> bool {
    tab.path.as_ref().is_some_and(|path| {
        let held = dunce::canonicalize(path).unwrap_or_else(|_| path.clone());
        held == moved || folder_tail(&held.to_slash_lossy(), &moved.to_slash_lossy()).is_some()
    })
}

/// Move the index entries under `old` onto the same files at `new`, keeping
/// every loaded handle and the mtime the files kept through the rename: what
/// already references the asset keeps resolving, by its new path, into the
/// same value.
fn migrate_index_entries(world: &mut World, old: &Path, new: &Path, folder: bool) {
    let held: Vec<crate::asset_index::AssetEntry> = {
        let index = world.resource::<AssetIndex>();
        match folder {
            true => index
                .iter()
                .filter(|entry| entry.path.starts_with(old))
                .cloned()
                .collect(),
            false => index.get(old).cloned().into_iter().collect(),
        }
    };
    for mut entry in held {
        let was = entry.path.clone();
        entry.path = match folder {
            true => new.join(was.strip_prefix(old).unwrap_or(&was)),
            false => new.to_path_buf(),
        };
        world.resource_mut::<AssetIndex>().remove(&was);
        world.resource_mut::<AssetIndex>().insert(entry);
    }
    crate::asset_index::publish_reference_map(world);
}

/// Put the card editing the moved file onto the file under its new path, so
/// a save through the card writes where the file landed. A card editing a
/// file under a moved folder follows it the same way.
fn retarget_cards(world: &mut World, old: &Path, new: &Path, folder: bool) {
    let entity = world
        .get_resource::<crate::definition_assets::OpenDefinition>()
        .and_then(|open| open.0);
    let Some(entity) = entity else {
        return;
    };
    let mut edits = world.query::<&mut crate::definition_assets::DefinitionAssetEdit>();
    let Ok(mut edit) = edits.get_mut(world, entity) else {
        return;
    };
    let hit = edit.path == *old
        || (folder && folder_tail(&edit.path.to_slash_lossy(), &old.to_slash_lossy()).is_some());
    if !hit {
        return;
    }
    let now = match folder {
        true => new.join(
            edit.path
                .strip_prefix(old)
                .map(Path::to_path_buf)
                .unwrap_or_default(),
        ),
        false => new.to_path_buf(),
    };
    edit.path = now;
    edit.name = jackdaw_bsn::path_stem(&edit.path);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_folder_prefix_ends_on_a_component_boundary() {
        assert_eq!(
            folder_tail("props/a/crate.bsn", "props").as_deref(),
            Some("a/crate.bsn")
        );
        assert_eq!(
            folder_tail("props2/box.bsn", "props"),
            None,
            "a sibling folder is not under it"
        );
        assert_eq!(
            folder_tail("props", "props"),
            None,
            "the folder itself is not under it"
        );
        assert_eq!(folder_tail("propsurement/box.bsn", "props"), None);
    }

    #[test]
    fn a_twin_spelling_is_the_binary_form_of_the_same_path() {
        assert!(is_twin_spelling(
            "a/rust.material.bsb",
            "a/rust.material.bsn"
        ));
        assert!(!is_twin_spelling(
            "a/rust.material.bsn",
            "a/rust.material.bsn"
        ));
    }
}
