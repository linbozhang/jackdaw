//! The export heavy smoke (roadmap T07's "moved directory, still runs"):
//! a fixture game built through the editor's pipeline, staged by
//! [`stage_export`], asserted for layout, filtering and manifest — then
//! **moved to a different directory** and launched there with the
//! schema flag, which prints and exits without opening a window. A game
//! that only runs where it was built is not an export; this test is the
//! automated form of the manual "copy to a USB stick, double-click"
//! acceptance.
//!
//! ```text
//! cargo test --test export -- --nocapture
//! ```
//! (or via `cargo xtask heavy`, which runs the SDK-gated binaries)

use std::path::{Path, PathBuf};

use jackdaw::project_build::prepare_game_command;
use jackdaw_project_build::build_project_binary;
use jackdaw_project_build::export::{ExportManifest, manifest_for, plan_export, stage_export};
use jackdaw_project_build::shim::ShimSpec;
use jackdaw_schema::{SCHEMA_FLAG, parse_from_stdout};

fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

/// The full export leg on the fixture game: build → stage → assert the
/// layout, the filter and the manifest → move the whole dist elsewhere
/// → run the staged executable from there with the schema flag and
/// parse what it prints. One build, many assertions (the D6 rule for
/// heavy tests).
#[test]
fn an_exported_game_runs_from_a_moved_directory() {
    let game_dir = workspace_root().join("tests/fixtures/bsn_game");
    let jackdaw_dir = workspace_root().join("target/bsn_game_run");
    std::fs::create_dir_all(&jackdaw_dir).expect("create build dir");
    let spec = ShimSpec {
        package_name: "bsn_scene_game".into(),
        crate_name: "bsn_scene_game".into(),
        project_root: game_dir.clone(),
        extension_type: None,
    };
    let build = build_project_binary(&spec, &jackdaw_dir, &mut |_| {})
        .expect("build the project binary the editor way");

    // The editor-private filter needs something to filter: a PIE temp
    // copy and a save rotation, planted in the fixture's assets.
    std::fs::create_dir_all(game_dir.join("assets/.jackdaw-pie")).expect("pie dir");
    std::fs::write(game_dir.join("assets/.jackdaw-pie/current.bsn"), b"unsaved").expect("pie copy");
    std::fs::write(game_dir.join("assets/scene.bsn.bak"), b"old scene").expect("bak");

    let plan = plan_export(&game_dir, "dev", &build.binary, None);
    let report = stage_export(&plan).expect("stage the export");

    // Layout: the executable beside the asset tree, the marker and the
    // manifest at the root.
    assert!(
        report.executable.is_file(),
        "{}",
        report.executable.display()
    );
    assert!(report.assets_dir.join("scene.bsn").is_file());
    assert!(report.dist_dir.join(".jackdaw-export").is_file());
    assert!(report.manifest.is_file(), "{}", report.manifest.display());

    // The filter: nothing editor-private shipped, and the report says
    // exactly what was kept out.
    assert!(!report.assets_dir.join(".jackdaw-pie").exists());
    assert!(!report.assets_dir.join("scene.bsn.bak").exists());
    assert_eq!(report.skipped, 2, "the pie directory and the .bak rotation");

    // The manifest: a receipt for exactly the shipped tree.
    let manifest: ExportManifest = serde_json::from_str(
        &std::fs::read_to_string(&report.manifest).expect("read the manifest"),
    )
    .expect("parse the manifest");
    let regenerated = manifest_for(&report.dist_dir, "dev").expect("re-hash the export");
    assert_eq!(manifest.files, regenerated.files);
    assert!(
        manifest
            .files
            .iter()
            .any(|file| file.path.ends_with("scene.bsn"))
    );

    // The move: the whole dist, copied to a directory nowhere near the
    // project — a different parent, deeper nesting, as a USB stick
    // would be.
    let moved = workspace_root().join("target/export_moved/deeply/nested/dist");
    std::fs::create_dir_all(moved.parent().unwrap()).expect("make the moved parent");
    let _ = std::fs::remove_dir_all(&moved);
    copy_tree(&report.dist_dir, &moved);
    assert!(moved.join(report.executable.file_name().unwrap()).is_file());

    // The launch from the moved home: the schema flag makes the game
    // print its type schema and exit 0 without opening a window, and it
    // must do that with its cwd set to the moved directory only — no
    // inherited project paths, no asset root fallbacks.
    let moved_exe = moved.join(report.executable.file_name().unwrap());
    let mut command = std::process::Command::new(&moved_exe);
    command
        .arg(SCHEMA_FLAG)
        .current_dir(&moved)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());
    prepare_game_command(&mut command, &moved_exe);
    let output = command.output().expect("run the moved game's extractor");
    assert!(
        output.status.success(),
        "the moved export's extractor failed: {}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr),
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    let parsed = parse_from_stdout(stdout.as_bytes()).expect("the moved game's schema parses");
    assert!(
        !parsed.components.is_empty(),
        "a game with no components printed no schema"
    );

    // The planted PIE copy and rotation leave with the test.
    let _ = std::fs::remove_dir_all(game_dir.join("assets/.jackdaw-pie"));
    let _ = std::fs::remove_file(game_dir.join("assets/scene.bsn.bak"));
}

/// `std::fs::copy` over a tree, since the export's own `copy_tree` is
/// private to the build crate.
fn copy_tree(from: &Path, to: &Path) {
    std::fs::create_dir_all(to).expect("make the copy target");
    for entry in std::fs::read_dir(from).expect("read the source") {
        let entry = entry.expect("entry");
        let target = to.join(entry.file_name());
        if entry.file_type().expect("type").is_dir() {
            copy_tree(&entry.path(), &target);
        } else {
            std::fs::copy(entry.path(), target).expect("copy the file");
        }
    }
}
