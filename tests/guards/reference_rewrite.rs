//! Guards for T05 reference stability: a rename, a move or a delete of a
//! referenced file is followed through — the documents that spelled the old
//! path are rewritten at the AST level (a non-asset string reading the same
//! is left alone, W10), the tabs and cards standing on the file are
//! retargeted (Y8), a delete of an open scene is refused (N3), a
//! case-only rename lands (W11), a drop of a file already in the project
//! copies nothing (W8), and the crash journal names the new path.

use std::path::{Path, PathBuf};

use bevy::prelude::*;
use jackdaw::boot_ops::run_op_clause;
use jackdaw::scenes::Scenes;
use jackdaw_api_internal::operator::{OperatorReports, OperatorWarnings};

use crate::util::{self, OperatorResultExt as _};

const SIGNPOST: &str = "guards::reference_rewrite::Signpost";

/// A component naming a material, with a plain string beside it that is made
/// to spell the very same path: the rewrite must touch the one and not the
/// other (W10).
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct Signpost {
    #[reflect(default)]
    board: Handle<StandardMaterial>,
    #[reflect(default)]
    note: String,
}

/// A material file spelling the given fields, in the shape the editor reads.
fn material(metallic: f64) -> String {
    format!("#rust\nbevy_pbr::pbr_material::StandardMaterial {{ metallic: {metallic} }}\n")
}

/// A scene with one Signpost on it, referencing `reference` in its asset
/// field and in a plain string beside it.
fn scene_with(reference: &str) -> String {
    format!("#Sign\n{SIGNPOST} {{ board: \"{reference}\", note: \"{reference}\" }}\n")
}

/// Write a file under the project's assets, folders and all.
fn write(root: &Path, relative: &str, text: &str) {
    let path = root.join("assets").join(relative);
    std::fs::create_dir_all(path.parent().expect("a parent")).expect("the folder is made");
    std::fs::write(path, text).expect("the file is written");
}

/// Read a file under the project's assets.
fn read(root: &Path, relative: &str) -> String {
    std::fs::read_to_string(root.join("assets").join(relative)).expect("the file is read")
}

/// An editor on a project holding a material and a scene referencing it, the
/// scene open in front.
fn editor_with_scene() -> (App, tempfile::TempDir) {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-reference-rewrite-")
        .tempdir()
        .expect("temp dir");
    write(tmp.path(), "materials/rust.material.bsn", &material(0.25));
    write(
        tmp.path(),
        "zones/hedgerow.bsn",
        &scene_with("materials/rust.material.bsn"),
    );

    let mut app = util::editor_test_app();
    app.register_type::<Signpost>();
    app.register_asset_reflect::<StandardMaterial>();
    app.world_mut()
        .insert_resource(jackdaw::project::ProjectRoot {
            root: tmp.path().to_path_buf(),
            config: default(),
        });
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    app.update();
    // The index is built before the scene opens, so its references resolve
    // to loaded handles the way a project that has been open a while does.
    jackdaw::asset_index::rescan_asset_index(app.world_mut());
    open(&mut app, "zones/hedgerow.bsn");
    (app, tmp)
}

/// Open a scene by its project-relative path and settle the load.
fn open(app: &mut App, relative: &str) {
    run_op_clause(
        app.world_mut(),
        &format!("scene.open path=assets/{relative}"),
    )
    .expect("the scene opens")
    .assert_finished();
    util::settle_scene_load(app);
}

/// Rescan the project's assets synchronously, so the index and the
/// referrers table see what is on disk now.
fn rescan(app: &mut App) {
    jackdaw::asset_index::rescan_asset_index(app.world_mut());
}

/// The operator reports the run has gathered, cleared for a fresh read.
fn fresh_reports(app: &mut App) -> Vec<String> {
    app.world_mut()
        .get_resource_or_init::<OperatorReports>()
        .0
        .clear();
    Vec::new()
}

fn reports(app: &App) -> Vec<String> {
    app.world()
        .get_resource::<OperatorReports>()
        .map(|reports| reports.0.to_vec())
        .unwrap_or_default()
}

/// The active tab's path.
fn active_path(app: &App) -> Option<PathBuf> {
    let scenes = app.world().resource::<Scenes>();
    scenes.tabs[scenes.active].path.clone()
}

/// The one Signpost in the open scene.
fn signpost_board(app: &mut App) -> Handle<StandardMaterial> {
    let mut query = app.world_mut().query::<&Signpost>();
    let signpost = query
        .iter(app.world())
        .next()
        .expect("the scene holds a Signpost");
    signpost.board.clone()
}

// ------------------------------------------------------------------ N1/W10 --

/// Renaming a material every open document references rewrites the
/// references on disk — through the asset field only, leaving a plain string
/// that spells the very same path exactly as it was (W10) — and the reopened
/// scene resolves the same material under its new name.
#[test]
fn renaming_a_referenced_file_rewrites_its_referrers_and_nothing_else() {
    let (mut app, tmp) = editor_with_scene();
    rescan(&mut app);

    run_op_clause(
        app.world_mut(),
        "file.rename path=assets/materials/rust.material.bsn name=patinated.material.bsn",
    )
    .expect("the rename runs")
    .assert_finished();

    let rewritten = read(tmp.path(), "zones/hedgerow.bsn");
    assert!(
        rewritten.contains("materials/patinated.material.bsn"),
        "the reference follows the file: {rewritten}"
    );
    assert!(
        !rewritten.contains("board: \"materials/rust.material.bsn\""),
        "the asset field leaves the old path behind: {rewritten}"
    );
    assert!(
        rewritten.contains("note: \"materials/rust.material.bsn\""),
        "a plain string spelling the old path is left as it was: {rewritten}"
    );
    assert!(
        !tmp.path()
            .join("assets/materials/rust.material.bsn")
            .exists()
            && tmp
                .path()
                .join("assets/materials/patinated.material.bsn")
                .is_file(),
        "the file itself moved"
    );

    // Reopened, the scene resolves the same material value under the new
    // path, and the report says what the rewrite touched.
    let reports = reports(&app);
    assert!(
        reports
            .iter()
            .any(|line| line.contains("rewrote 1 references in 1 documents")),
        "the rename reports its rewrite: {reports:?}"
    );
    run_op_clause(app.world_mut(), "scene.close").expect("the tab closes");
    app.update();
    open(&mut app, "zones/hedgerow.bsn");
    let board = signpost_board(&mut app);
    let metallic = app
        .world()
        .resource::<Assets<StandardMaterial>>()
        .get(&board)
        .expect("the material loads")
        .metallic;
    assert_eq!(metallic, 0.25, "the material itself is unchanged");
    let path = jackdaw::asset_index::indexed_path(
        app.world(),
        &jackdaw::asset_index::absolute_path(
            app.world(),
            Path::new("materials/patinated.material.bsn"),
        ),
    );
    assert_eq!(
        path.as_deref(),
        Some(Path::new("materials/patinated.material.bsn")),
        "the index keys the material by its new path"
    );
}

// -------------------------------------------------------------- folder move --

/// Renaming a folder rewrites the prefixed references in every document that
/// holds one, on path components: `props` never reaches into `props2`.
#[test]
fn renaming_a_folder_rewrites_prefixed_references_on_component_boundaries() {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-reference-folders-")
        .tempdir()
        .expect("temp dir");
    write(
        tmp.path(),
        "props/a/crate.bsn",
        &material(0.25).replace("#rust", "#crate"),
    );
    write(
        tmp.path(),
        "props/b/box.bsn",
        &material(0.5).replace("#rust", "#box"),
    );
    write(
        tmp.path(),
        "props2/keep.bsn",
        &material(0.75).replace("#rust", "#keep"),
    );
    write(
        tmp.path(),
        "zones/one.bsn",
        &scene_with("props/a/crate.bsn"),
    );
    write(tmp.path(), "zones/two.bsn", &scene_with("props/b/box.bsn"));
    write(
        tmp.path(),
        "zones/three.bsn",
        &scene_with("props2/keep.bsn"),
    );

    let mut app = util::editor_test_app();
    app.register_type::<Signpost>();
    app.register_asset_reflect::<StandardMaterial>();
    app.world_mut()
        .insert_resource(jackdaw::project::ProjectRoot {
            root: tmp.path().to_path_buf(),
            config: default(),
        });
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    app.update();
    rescan(&mut app);

    run_op_clause(app.world_mut(), "file.rename path=assets/props name=prop")
        .expect("the folder renames")
        .assert_finished();

    let one = read(tmp.path(), "zones/one.bsn");
    assert_eq!(
        one.matches("prop/a/crate.bsn").count(),
        1,
        "the asset field under the renamed folder is rewritten exactly once: {one}"
    );
    assert!(
        one.contains("note: \"props/a/crate.bsn\""),
        "a plain string spelling the old prefix is left as it was (W10): {one}"
    );
    let two = read(tmp.path(), "zones/two.bsn");
    assert_eq!(
        two.matches("prop/b/box.bsn").count(),
        1,
        "and the second document likewise: {two}"
    );
    assert!(
        two.contains("note: \"props/b/box.bsn\""),
        "here too only the asset field moved: {two}"
    );
    let three = read(tmp.path(), "zones/three.bsn");
    assert_eq!(
        three.matches("props2/keep.bsn").count(),
        2,
        "a sibling folder the prefix also spells is untouched, both fields: {three}"
    );
    assert!(tmp.path().join("assets/prop").is_dir() && !tmp.path().join("assets/props").exists());
}

// ------------------------------------------------------------------- Y8 tab --

/// Renaming the scene an open, clean tab holds retargets the tab: its path
/// is the new one, a save lands there, and the old file stays gone.
#[test]
fn renaming_an_open_clean_scene_retargets_its_tab() {
    let (mut app, tmp) = editor_with_scene();
    rescan(&mut app);

    run_op_clause(
        app.world_mut(),
        "file.rename path=assets/zones/hedgerow.bsn name=thicket.bsn",
    )
    .expect("the rename runs")
    .assert_finished();

    let path = active_path(&app).expect("the tab keeps a path");
    assert!(
        path.ends_with(Path::new("assets").join("zones").join("thicket.bsn")),
        "the tab saves through the new path: {}",
        path.display()
    );
    assert!(
        !app.world().resource::<Scenes>().tabs[app.world().resource::<Scenes>().active].dirty,
        "a clean tab stays clean across the retarget"
    );
    assert!(
        jackdaw::scene_io::save_scene(app.world_mut()),
        "the scene saves"
    );
    app.update();
    assert!(
        tmp.path().join("assets/zones/thicket.bsn").is_file()
            && !tmp.path().join("assets/zones/hedgerow.bsn").exists(),
        "the save lands at the new path only"
    );
    let saved = read(tmp.path(), "zones/thicket.bsn");
    assert!(
        saved.contains("materials/patinated.material.bsn")
            || saved.contains("materials/rust.material.bsn"),
        "the saved document spells a material reference: {saved}"
    );
}

/// Renaming a material while a dirty tab references it keeps the tab dirty
/// and keeps its in-memory reference in step: the save writes the new path.
#[test]
fn renaming_a_referenced_material_under_a_dirty_tab_keeps_it_dirty_and_in_step() {
    let (mut app, tmp) = editor_with_scene();
    rescan(&mut app);
    {
        let mut scenes = app.world_mut().resource_mut::<Scenes>();
        let active = scenes.active;
        scenes.tabs[active].dirty = true;
        assert!(scenes.tabs[active].dirty, "the tab starts dirty");
    }

    run_op_clause(
        app.world_mut(),
        "file.rename path=assets/materials/rust.material.bsn name=patinated.material.bsn",
    )
    .expect("the rename runs")
    .assert_finished();

    {
        let scenes = app.world().resource::<Scenes>();
        assert!(scenes.tabs[scenes.active].dirty, "a dirty tab stays dirty");
    }
    assert!(
        jackdaw::scene_io::save_scene(app.world_mut()),
        "the dirty scene saves"
    );
    app.update();
    let saved = read(tmp.path(), "zones/hedgerow.bsn");
    assert!(
        saved.contains("materials/patinated.material.bsn"),
        "the save writes the reference the rewrite left: {saved}"
    );
    assert!(
        !saved.contains("board: \"materials/rust.material.bsn\""),
        "the old path is not written back: {saved}"
    );
}

// ------------------------------------------------------------------- N3 del --

/// Deleting a scene a tab holds is refused without force and says why; with
/// force the tab is closed and the file is gone, with nothing left to write
/// it back.
#[test]
fn deleting_an_open_scene_is_refused_and_forced_close_removes_it() {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-reference-delete-")
        .tempdir()
        .expect("temp dir");
    write(
        tmp.path(),
        "zones/one.bsn",
        "#One\nbevy_transform::components::transform::Transform\n",
    );
    write(
        tmp.path(),
        "zones/two.bsn",
        "#Two\nbevy_transform::components::transform::Transform\n",
    );
    let mut app = util::editor_test_app();
    app.register_type::<Signpost>();
    app.register_asset_reflect::<StandardMaterial>();
    app.world_mut()
        .insert_resource(jackdaw::project::ProjectRoot {
            root: tmp.path().to_path_buf(),
            config: default(),
        });
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    app.update();
    open(&mut app, "zones/one.bsn");
    open(&mut app, "zones/two.bsn");
    let one = tmp.path().join("assets/zones/one.bsn");

    fresh_reports(&mut app);
    run_op_clause(
        app.world_mut(),
        &format!("file.delete path={}", one.display()),
    )
    .expect("the delete is asked for")
    .assert_finished();
    app.update();
    assert!(
        one.is_file(),
        "without force the open scene is left on disk"
    );
    let refused = app
        .world()
        .get_resource::<OperatorWarnings>()
        .map(|warnings| warnings.0.to_vec())
        .unwrap_or_default();
    assert!(
        refused.iter().any(|line| line.contains("is open in a tab")),
        "the refusal says the file is open in a tab: {refused:?}"
    );
    assert!(
        app.world().resource::<Scenes>().tabs.len() == 2,
        "and no tab was closed behind the user's back"
    );

    run_op_clause(
        app.world_mut(),
        &format!("file.delete path={} force=true", one.display()),
    )
    .expect("the forced delete runs")
    .assert_finished();
    app.update();
    assert!(!one.exists(), "the file is gone");
    assert_eq!(
        app.world().resource::<Scenes>().tabs.len(),
        1,
        "the tab holding it is closed"
    );
    assert!(
        !app.world().resource::<Scenes>().tabs.iter().any(|tab| tab
            .path
            .as_deref()
            .is_some_and(|path| path.ends_with("one.bsn"))),
        "no tab is left standing on the deleted file, ready to write it back"
    );
}

// ------------------------------------------------------------------- W11 case --

/// A rename that differs only in case lands, leaving exactly one file with
/// the same contents.
#[test]
fn a_rename_that_differs_only_in_case_lands() {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-reference-case-")
        .tempdir()
        .expect("temp dir");
    write(
        tmp.path(),
        "zones/hedgerow.bsn",
        "#Zone\nbevy_transform::components::transform::Transform\n",
    );
    let file = tmp.path().join("assets/zones/hedgerow.bsn");
    let before = std::fs::read(&file).expect("the file is there");

    let mut app = util::editor_test_app();
    app.world_mut()
        .insert_resource(jackdaw::project::ProjectRoot {
            root: tmp.path().to_path_buf(),
            config: default(),
        });
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    app.update();
    run_op_clause(
        app.world_mut(),
        "file.rename path=assets/zones/hedgerow.bsn name=HEDGEROW.bsn",
    )
    .expect("the case rename runs")
    .assert_finished();

    let folder = tmp.path().join("assets/zones");
    let held: Vec<String> = std::fs::read_dir(&folder)
        .expect("the folder reads")
        .filter_map(|entry| {
            entry
                .ok()
                .map(|entry| entry.file_name().to_string_lossy().into_owned())
        })
        .collect();
    assert!(
        held.iter().any(|name| name == "HEDGEROW.bsn"),
        "the file holds the new casing: {held:?}"
    );
    assert_eq!(
        held.iter()
            .filter(|name| name.eq_ignore_ascii_case("hedgerow.bsn"))
            .count(),
        1,
        "exactly one file answers to the name: {held:?}"
    );
    let after = std::fs::read(folder.join("HEDGEROW.bsn")).expect("the renamed file reads");
    assert_eq!(before, after, "the contents are unchanged");
}

// ------------------------------------------------------------------ file.move --

/// Moving a referenced material into another folder follows with the whole
/// chain: the on-disk reference, the open card, and the report.
#[test]
fn moving_a_file_rewrites_references_and_retargets_the_card() {
    let (mut app, tmp) = editor_with_scene();
    std::fs::create_dir_all(tmp.path().join("assets/mats")).expect("the folder is made");
    rescan(&mut app);
    run_op_clause(
        app.world_mut(),
        "asset.open path=assets/materials/rust.material.bsn",
    )
    .expect("the card opens")
    .assert_finished();

    run_op_clause(
        app.world_mut(),
        "file.move path=assets/materials/rust.material.bsn folder=assets/mats",
    )
    .expect("the move runs")
    .assert_finished();

    assert!(
        tmp.path().join("assets/mats/rust.material.bsn").is_file()
            && !tmp
                .path()
                .join("assets/materials/rust.material.bsn")
                .exists(),
        "the file moved"
    );
    let rewritten = read(tmp.path(), "zones/hedgerow.bsn");
    assert!(
        rewritten.contains("mats/rust.material.bsn"),
        "the on-disk reference follows the move: {rewritten}"
    );
    let moved = reports(&app);
    assert!(
        moved
            .iter()
            .any(|line| line.contains("moved") && line.contains("rewrote")),
        "the move reports its rewrite: {moved:?}"
    );

    // The card that was editing the file saves through the new path.
    let card = app
        .world_mut()
        .query::<&jackdaw::definition_assets::DefinitionAssetEdit>()
        .iter(app.world())
        .next()
        .map(|edit| edit.path.clone())
        .expect("the card is open");
    assert_eq!(card, PathBuf::from("mats/rust.material.bsn"));
    run_op_clause(app.world_mut(), "asset.save").expect("the card saves");
    app.update();
    assert!(
        tmp.path().join("assets/mats/rust.material.bsn").is_file(),
        "the save lands at the new path"
    );
}

// ----------------------------------------------------- reimport / watcher --

/// The rewritten document is not read back as an outside edit: the open tab
/// is not prompted to reload, and a later overwrite of the material at the
/// same path reloads into the handle the scene already holds.
#[test]
fn a_rewritten_document_is_not_read_back_and_a_reimport_reloads_in_place() {
    let (mut app, tmp) = editor_with_scene();
    rescan(&mut app);
    let board = signpost_board(&mut app);

    // An overwrite at the same path reloads into the same handle (the
    // reimport behaviour this chain must not disturb).
    write(tmp.path(), "materials/rust.material.bsn", &material(0.9));
    rescan(&mut app);
    let metallic = app
        .world()
        .resource::<Assets<StandardMaterial>>()
        .get(&board)
        .expect("the material still loads")
        .metallic;
    assert_eq!(metallic, 0.9, "the handle took the new value");

    // The rewrite of the open tab's own document is not an outside edit.
    write(tmp.path(), "materials/rust.material.bsn", &material(0.25));
    rescan(&mut app);
    fresh_reports(&mut app);
    run_op_clause(
        app.world_mut(),
        "file.rename path=assets/materials/rust.material.bsn name=patina.material.bsn",
    )
    .expect("the rename runs")
    .assert_finished();
    for _ in 0..5 {
        app.update();
    }
    let prompts = app
        .world()
        .get_resource::<jackdaw::scenes::external_watch::ExternalSceneChanges>()
        .map(|changes| changes.prompts.len())
        .unwrap_or(0);
    assert_eq!(
        prompts, 0,
        "the open tab is not prompted to reload what the editor itself rewrote"
    );
}

// ------------------------------------------------------------------ W8 drop --

/// Dropping a file that already sits in the project's assets copies nothing.
#[test]
fn dropping_a_file_already_in_the_assets_copies_nothing() {
    let (mut app, tmp) = editor_with_scene();
    let inside = tmp.path().join("assets").join("moss.png");
    std::fs::write(&inside, b"a png").expect("the file is written");

    app.world_mut()
        .write_message(bevy::window::FileDragAndDrop::DroppedFile {
            window: Entity::PLACEHOLDER,
            path_buf: inside.clone(),
        });
    for _ in 0..3 {
        app.update();
    }

    let assets = tmp.path().join("assets");
    let pngs: Vec<String> = std::fs::read_dir(&assets)
        .expect("the assets read")
        .filter_map(|entry| {
            entry
                .ok()
                .map(|entry| entry.file_name().to_string_lossy().into_owned())
        })
        .filter(|name| name.ends_with(".png"))
        .collect();
    assert_eq!(
        pngs,
        vec!["moss.png".to_string()],
        "no copy of an in-project file appears"
    );
}

// ----------------------------------------------------------------- journal --

/// A dirty tab that survives a rename journals under the new path, so a
/// crash recovers onto the file that exists.
#[test]
fn a_dirty_tab_journals_under_the_renamed_path() {
    let (mut app, tmp) = editor_with_scene();
    rescan(&mut app);
    jackdaw::scene_io::session_journal::begin_session(app.world_mut(), tmp.path());
    {
        let mut scenes = app.world_mut().resource_mut::<Scenes>();
        let active = scenes.active;
        scenes.tabs[active].dirty = true;
    }

    run_op_clause(
        app.world_mut(),
        "file.rename path=assets/zones/hedgerow.bsn name=thicket.bsn",
    )
    .expect("the rename runs")
    .assert_finished();

    let journal = read_journal(&mut app).expect("the journal lands");
    assert_eq!(journal.tabs.len(), 1, "one entry for the one dirty tab");
    let entry_path = PathBuf::from(
        journal.tabs[0]
            .path
            .as_deref()
            .expect("the entry names a file"),
    );
    assert!(
        entry_path.ends_with(Path::new("assets").join("zones").join("thicket.bsn")),
        "the journaled path is the new one: {}",
        entry_path.display()
    );
}

/// The session's journal file, if the session has written one.
fn read_journal(app: &mut App) -> Option<jackdaw::scene_io::session_journal::JournalFile> {
    let dir = jackdaw::scene_io::session_journal::session_dir(app.world())?;
    jackdaw::scene_io::session_journal::read_session_journal(&dir)
}
