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
    let (mut app, _tmp) = editor();
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
