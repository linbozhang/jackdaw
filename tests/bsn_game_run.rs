#![expect(
    clippy::print_stdout,
    reason = "e2e test prints the runtime proof line"
)]
//! A game built through `build_project_binary` and run as its own
//! executable loads and spawns an authored `.bsn` scene at runtime. The
//! game's stderr marker reports which authored entities reached the live
//! world.
//!
//! The second test is the run-targets heavy smoke: a `[[run]]` entry's
//! `target = { example = ... }` builds that example through the same
//! pipeline, adopts the example's own artifact, and runs it.
//!
//! ```text
//! cargo test --test bsn_game_run -- --nocapture
//! ```

use std::path::PathBuf;

use jackdaw::project_build::build_project_binary;
use jackdaw::project_build::build_project_binary_with_load;
use jackdaw::project_build::shim::ShimSpec;
use jackdaw::project_build::{BuildLoad, CargoTarget, prepare_game_command};

mod util;

fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

#[test]
fn built_game_loads_and_spawns_a_bsn_scene() {
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
    let binary = build.binary;
    assert!(
        binary.exists(),
        "game binary missing at {}",
        binary.display()
    );

    // Run from the game dir so `assets/scene.bsn` resolves. BEVY_ASSET_ROOT
    // overrides the inherited CARGO_MANIFEST_DIR that bevy would otherwise use.
    let (loaded, stderr) = util::run_windowless_game(
        &binary,
        &game_dir,
        &[("BEVY_ASSET_ROOT", game_dir.as_os_str())],
    );

    assert!(
        loaded,
        "the built game never loaded the .bsn scene \
         (no `BSN_SCENE_LOADED ... has_target=true`); game stderr:\n{stderr}"
    );
    // Scatter provenance is scene data, so the runtime has to know the type:
    // a game that cannot apply it loads a scattered scene with the groups
    // stripped back to bare models. The game reports the keys it found, so
    // this reads what arrived rather than what nothing complained about.
    assert!(
        stderr.contains("scatter_keys=[\"Props\"]"),
        "the runtime did not apply the scene's scatter provenance; game stderr:\n{stderr}"
    );
    println!("ok: {stderr}");
}

/// The run-targets heavy smoke: a `[[run]]` entry's
/// `target = { example = "schema_echo" }` builds that one example
/// through the editor's pipeline, the build adopts the example's own
/// artifact (cargo puts it in an `examples/` segment), and the artifact
/// runs as its own process. The heavy profile runs this one at a time,
/// and the test shares the default build's `jackdaw` dir so the
/// dependency closure is compiled once.
///
/// This is also the real-machine check of the cargo JSON `target.kind`
/// filter the unit tests pin with literal JSON: adopting the artifact
/// requires the record's `target.kind` to contain the exact string
/// `"example"`. If cargo spelled the kind any other way, the build would
/// return "produced no executable" here and this test would fail.
#[test]
fn a_run_target_builds_and_runs_its_example() {
    let game_dir = workspace_root().join("tests/fixtures/bsn_game");
    let jackdaw_dir = workspace_root().join("target/bsn_game_run");
    std::fs::create_dir_all(&jackdaw_dir).expect("create build dir");
    let spec = ShimSpec {
        package_name: "bsn_scene_game".into(),
        crate_name: "bsn_scene_game".into(),
        project_root: game_dir.clone(),
        extension_type: None,
    };
    let target = CargoTarget {
        example: Some("schema_echo".to_string()),
        ..CargoTarget::default()
    };
    let build = build_project_binary_with_load(
        &spec,
        &jackdaw_dir,
        Some(&target),
        BuildLoad::Foreground,
        &mut |_| {},
    )
    .expect("build the example target the editor way");

    // The path is cargo's own report, never assembled by jackdaw; the
    // examples/ segment is what `--example` artifacts are placed under.
    let binary = build.binary;
    assert!(
        binary.exists(),
        "example binary missing at {}",
        binary.display()
    );
    assert!(
        binary
            .components()
            .any(|component| component.as_os_str() == "examples"),
        "expected the example's own artifact under examples/, got {}",
        binary.display()
    );

    // The schema extractor runs the built example with its flag; a
    // target without the game's plugins cannot answer it, and the
    // documented degradation is a build with no schema, not a failure.
    assert!(
        build.schema.is_none(),
        "an example without the game plugin has no schema to extract"
    );

    // Play launches the artifact as a bare process; do the same and
    // require the marker line the example prints before exiting.
    let mut command = std::process::Command::new(&binary);
    prepare_game_command(&mut command, &binary);
    command.current_dir(&game_dir);
    let output = command.output().expect("run the built example");
    let text = format!(
        "{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.status.success(),
        "the example exited with {}: {text}",
        output.status
    );
    assert!(
        text.contains("SCHEMA_ECHO_MARKER"),
        "the example's marker line never printed: {text}"
    );
}
