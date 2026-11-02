//! Guards for the T05 missing-reference audit: the operator reports what the
//! audit found, the list operator fills the findings a caller asserts
//! against, and the load-time summary leaves one line in the warnings rather
//! than a line per field.

use bevy::prelude::*;
use jackdaw::boot_ops::run_op_clause;
use jackdaw::scenes::Scenes;
use jackdaw_api_internal::operator::{OperatorReports, OperatorWarnings};

use crate::util::{self, OperatorResultExt as _};

/// A component naming a material — the shape the audit's four-location
/// findings travel in.
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct Signboard {
    #[reflect(default)]
    board: Handle<StandardMaterial>,
}

const SIGNBOARD: &str = "guards::reference_audit::Signboard";

fn write(root: &std::path::Path, relative: &str, text: &str) {
    let path = root.join("assets").join(relative);
    std::fs::create_dir_all(path.parent().expect("a parent")).expect("the folder is made");
    std::fs::write(path, text).expect("the file is written");
}

/// An editor on a project holding one material a scene references and two it
/// does not, the scene open in front.
fn editor() -> (App, tempfile::TempDir) {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-reference-audit-")
        .tempdir()
        .expect("temp dir");
    write(
        tmp.path(),
        "materials/rust.material.bsn",
        "#rust\nbevy_pbr::pbr_material::StandardMaterial { metallic: 0.25 }\n",
    );
    write(
        tmp.path(),
        "zones/hedgerow.bsn",
        &format!(
            "bevy_ecs::hierarchy::Children [\n\
             \x20\x20\x20\x20#Sign\n\
             \x20\x20\x20\x20{SIGNBOARD} {{ board: \"materials/gone.material.bsn\" }}\n\
             \n\
             \x20\x20\x20\x20#Post\n\
             \x20\x20\x20\x20{SIGNBOARD} {{ board: \"materials/also-gone.material.bsn\" }}\n\
             ]\n"
        ),
    );

    let mut app = util::editor_test_app();
    app.register_type::<Signboard>();
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
    jackdaw::asset_index::rescan_asset_index(app.world_mut());
    run_op_clause(app.world_mut(), "scene.open path=assets/zones/hedgerow.bsn")
        .expect("the scene opens")
        .assert_finished();
    util::settle_scene_load(&mut app);
    (app, tmp)
}

/// `asset.audit` reports the summary a person reads and fills the findings
/// resource a tool asserts against: one entry per broken reference, with the
/// document, the entity, the component and the field.
#[test]
fn asset_audit_reports_and_fills_the_findings() {
    let (mut app, _tmp) = editor();

    run_op_clause(app.world_mut(), "asset.audit")
        .expect("the audit runs")
        .assert_finished();

    let reports = app
        .world()
        .get_resource::<OperatorReports>()
        .map(|reports| reports.0.to_vec())
        .unwrap_or_default();
    assert!(
        reports
            .iter()
            .any(|line| line.contains("2 broken references in 1 documents")),
        "the summary counts what it found: {reports:?}"
    );
    let findings = app
        .world()
        .get_resource::<jackdaw::reference_audit::AuditFindings>()
        .map(|findings| findings.0.clone())
        .expect("the findings are kept for the caller");
    assert_eq!(findings.len(), 2, "one entry per broken reference");
    let mut references: Vec<&str> = findings
        .iter()
        .map(|finding| finding.reference.as_str())
        .collect();
    references.sort();
    assert_eq!(
        references,
        vec![
            "materials/also-gone.material.bsn",
            "materials/gone.material.bsn"
        ],
        "each broken reference is named as it is spelled"
    );
    for finding in &findings {
        assert_eq!(
            finding.document,
            std::path::PathBuf::from("zones/hedgerow.bsn")
        );
        assert_eq!(finding.component, "Signboard");
        assert_eq!(finding.field, "board");
        assert_eq!(finding.kind, jackdaw::reference_audit::FindingKind::Missing);
        assert!(
            finding.entity_name.is_some(),
            "each finding names the entity it sits on: {:?}",
            finding.line()
        );
    }
}

/// `asset.missing_list` gathers the findings the list shows, and in a
/// headless editor — where the dialog never spawns — the run is still the
/// gather.
#[test]
fn asset_missing_list_gathers_the_findings_headless() {
    let (mut app, _tmp) = editor();

    run_op_clause(app.world_mut(), "asset.missing_list")
        .expect("the list runs")
        .assert_finished();

    let findings = app
        .world()
        .get_resource::<jackdaw::reference_audit::AuditFindings>()
        .map(|findings| findings.0.clone())
        .expect("the findings are kept");
    assert_eq!(findings.len(), 2, "the list has both broken references");
    assert!(
        findings.iter().all(|finding| !finding.line().is_empty()),
        "each finding renders a line for the list"
    );
}

/// The scene load leaves one summary warning about its missing references,
/// not a warning per field (N5), on the chain a real load takes.
#[test]
fn a_loaded_scene_leaves_one_summary_warning() {
    let (app, _tmp) = editor();
    let warnings = app
        .world()
        .get_resource::<OperatorWarnings>()
        .map(|warnings| warnings.0.to_vec())
        .unwrap_or_default();
    let about_scene = warnings
        .iter()
        .filter(|line| line.contains("zones/hedgerow.bsn"))
        .count();
    assert_eq!(
        about_scene, 1,
        "one line for the loaded scene's broken references: {warnings:?}"
    );
    assert!(
        warnings
            .iter()
            .any(|line| line.contains("2 references name files")),
        "the line counts what it found: {warnings:?}"
    );
    // And the scene is open in front with its tabs intact.
    assert_eq!(
        app.world().resource::<Scenes>().tabs.len(),
        1,
        "the load itself was untouched"
    );
}

/// An open tab's `IsA.source` is spelled absolutely in memory (the load
/// absolutizes; the save folds back), so the audit judges it the way a save
/// would spell it: a missing prefab reads as Missing, and a held one reads
/// as no finding at all — never as a machine path (the QA 🟡).
#[test]
fn an_open_tabs_isa_source_is_judged_by_its_relative_spelling() {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-audit-isa-")
        .tempdir()
        .expect("temp dir");
    write(
        tmp.path(),
        "props/keeper.bsn",
        "#keeper\nbevy_transform::components::transform::Transform\n",
    );
    write(
        tmp.path(),
        "zones/one.bsn",
        "#A\njackdaw::prefab::components::Prefab\n\
         jackdaw::prefab::components::IsA { source: \"props/gone.bsn\" }\n",
    );
    write(
        tmp.path(),
        "zones/two.bsn",
        "#B\njackdaw::prefab::components::Prefab\n\
         jackdaw::prefab::components::IsA { source: \"props/keeper.bsn\" }\n",
    );
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
    jackdaw::asset_index::rescan_asset_index(app.world_mut());
    for scene in ["zones/one.bsn", "zones/two.bsn"] {
        run_op_clause(app.world_mut(), &format!("scene.open path=assets/{scene}"))
            .expect("the scene opens")
            .assert_finished();
        util::settle_scene_load(&mut app);
    }

    let findings = jackdaw::reference_audit::audit_references(app.world_mut());
    let isa: Vec<_> = findings
        .iter()
        .filter(|finding| finding.component == "IsA")
        .collect();
    assert_eq!(
        isa.len(),
        1,
        "the missing prefab is a finding and the held one is not: {findings:?}"
    );
    assert_eq!(
        isa[0].kind,
        jackdaw::reference_audit::FindingKind::Missing,
        "judged by its relative spelling, not as a machine path: {:?}",
        isa[0].line()
    );
    assert_eq!(isa[0].document, std::path::PathBuf::from("zones/one.bsn"));
}

/// T23 MO2: the paths a `MaterialOverrides` entry spells are references the
/// same way a typed handle field is, so an entry naming no file the project
/// holds is a Missing finding a caller can find and rebind — not a silent
/// fall-back to the model's own material. A placed model's own `GltfSource`
/// path is one too (the model file gone is discoverable, not silent).
#[test]
fn an_override_path_that_names_no_file_is_a_missing_finding() {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-audit-overrides-")
        .tempdir()
        .expect("temp dir");
    write(
        tmp.path(),
        "materials/rust.material.bsn",
        "#rust\nbevy_pbr::pbr_material::StandardMaterial { metallic: 0.25 }\n",
    );
    write(
        tmp.path(),
        "zones/hedgerow.bsn",
        "#Cliff\n\
         jackdaw_scene_types::types::GltfSource { path: \"models/gone.glb\", scene_index: 0 }\n\
         jackdaw_scene_types::types::MaterialOverrides {\n\
         \x20\x20\x20\x20materials: map[\n\
         \x20\x20\x20\x20\x20\x20\x20\x20(\"Rock\", \"materials/gone.material.bsn\"),\n\
         \x20\x20\x20\x20\x20\x20\x20\x20(\"Moss\", \"materials/rust.material.bsn\")\n\
         \x20\x20\x20\x20]\n\
         }\n",
    );
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
    jackdaw::asset_index::rescan_asset_index(app.world_mut());

    let findings = jackdaw::reference_audit::audit_references(app.world_mut());

    let overrides: Vec<_> = findings
        .iter()
        .filter(|finding| finding.component == "MaterialOverrides")
        .collect();
    assert_eq!(
        overrides.len(),
        1,
        "the override entry naming no file is one finding: {findings:?}"
    );
    assert_eq!(overrides[0].field, "materials");
    assert_eq!(overrides[0].reference, "materials/gone.material.bsn");
    assert_eq!(
        overrides[0].kind,
        jackdaw::reference_audit::FindingKind::Missing
    );
    assert_eq!(overrides[0].entity_name.as_deref(), Some("Cliff"));
    assert_eq!(
        overrides[0].document,
        std::path::PathBuf::from("zones/hedgerow.bsn")
    );

    let model: Vec<_> = findings
        .iter()
        .filter(|finding| finding.component == "GltfSource")
        .collect();
    assert_eq!(
        model.len(),
        1,
        "a placed model naming no model file is a finding too: {findings:?}"
    );
    assert_eq!(model[0].field, "path");
    assert_eq!(model[0].reference, "models/gone.glb");
    assert_eq!(
        model[0].kind,
        jackdaw::reference_audit::FindingKind::Missing
    );

    // The reference that resolves costs nothing.
    assert!(
        findings
            .iter()
            .all(|finding| finding.reference != "materials/rust.material.bsn"),
        "a held material is no finding: {findings:?}"
    );
}

/// The startup walk fills the index on its own — no test rescan asked for
/// it. This is the guard that keeps the real-machine path (`OnEnter` the
/// editor state, the async walk, the apply) from silently going dark while
/// the tests keep it alive by hand (the QA finding).
#[test]
fn the_startup_walk_fills_the_index_without_a_manual_rescan() {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-audit-startup-")
        .tempdir()
        .expect("temp dir");
    write(
        tmp.path(),
        "materials/rust.material.bsn",
        "#rust\nbevy_pbr::pbr_material::StandardMaterial { metallic: 0.25 }\n",
    );

    let mut app = util::editor_test_app();
    app.register_asset_reflect::<StandardMaterial>();
    app.world_mut()
        .insert_resource(jackdaw::project::ProjectRoot {
            root: tmp.path().to_path_buf(),
            config: default(),
        });
    // Entering the editor state is what a real launch does; no rescan is
    // called by hand anywhere in this test.
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    // The walk sets out on enter, lands a frame later, applies the frame
    // after that; a few frames is what the real machine pays.
    for _ in 0..30 {
        app.update();
    }

    let index = app.world().resource::<jackdaw::asset_index::AssetIndex>();
    assert!(
        index
            .get(std::path::Path::new("materials/rust.material.bsn"))
            .is_some(),
        "the startup walk indexed the material on its own"
    );
}
