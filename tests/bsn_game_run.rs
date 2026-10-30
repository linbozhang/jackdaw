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

    // The fixture now wires the save layer; its demo runs only under the
    // `JACKDAW_SAVE_DIR` seam, and this test points it at a scratch of its
    // own so the world is always fresh — the volume assertions below read
    // the hardcoded config (0.4 × 0.8 × 0.5 = 0.16), never a saved mix,
    // and nothing lands in the real player tree (T17 seam discipline).
    let scratch = tempfile::tempdir().expect("scratch save dir");

    // Run from the game dir so `assets/scene.bsn` resolves. BEVY_ASSET_ROOT
    // overrides the inherited CARGO_MANIFEST_DIR that bevy would otherwise use.
    // The wait also covers the game's `AUDIO_SINK_LIVE` line, which the audio
    // entity's mirror can only print a few frames after the scene lands.
    let (loaded, stderr) = util::run_windowless_game_until(
        &binary,
        &game_dir,
        &[
            ("BEVY_ASSET_ROOT", game_dir.as_os_str()),
            ("JACKDAW_SAVE_DIR", scratch.path().as_os_str()),
        ],
        &["AUDIO_SINK_LIVE"],
    );

    assert!(
        loaded,
        "the built game never loaded the .bsn scene \
         (no `BSN_SCENE_LOADED ... has_target=true`, or the scene's audio entity \
         never reached a playing sink); game stderr:\n{stderr}"
    );
    // Scatter provenance is scene data, so the runtime has to know the type:
    // a game that cannot apply it loads a scattered scene with the groups
    // stripped back to bare models. The game reports the keys it found, so
    // this reads what arrived rather than what nothing complained about.
    assert!(
        stderr.contains("scatter_keys=[\"Props\"]"),
        "the runtime did not apply the scene's scatter provenance; game stderr:\n{stderr}"
    );

    // The audio entity reached a real sink at the mixed volume: the scene
    // authors base 0.4 on the music bus, the game's config holds master 0.5
    // and music 0.8, and 0.4 × 0.8 × 0.5 = 0.16. A machine without an audio
    // output device produces no stream and no sink — the game then never
    // prints the line and the wait above fails with its stderr, which is the
    // declared environment dependency of this leg.
    let live = stderr
        .lines()
        .find(|line| line.contains("AUDIO_SINK_LIVE"))
        .expect("the wait above guarantees the line");
    assert!(
        live.contains("kind=music"),
        "the probe entity reports its bus: {live}"
    );
    assert!(
        live.contains("volume=0.160"),
        "the sink plays at base 0.4 × music 0.8 × master 0.5: {live}"
    );
    assert!(
        live.contains("paused=false") && live.contains("finished=false"),
        "the sink is actively playing: {live}"
    );
    assert!(
        !stderr.contains("No audio device found"),
        "the audio stack should find this machine's output device; stderr:\n{stderr}"
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

/// The restart-recovery proof at engine level (T17 M2/M8, the H2
/// channel): the same built fixture binary run twice against one
/// scratch save tree. Run one is a fresh world — it reports
/// `SAVE_FRESH`, the hardcoded config stands (`SAVE_CONFIG master=0.50`),
/// it counts its run and the plugin's flush lands `save.json`
/// (`SAVE_WRITTEN runs=1`). Run two loads that file — `SAVE_LOADED
/// runs=1` — the saved mix stands over the authored one
/// (`SAVE_CONFIG master=0.90`, the bridge order), and the file on disk
/// carries the bumped profile under the versioned envelope. kill -9 is
/// unnecessary here: each run is its own process, the boundary is real.
#[test]
fn a_save_survives_the_fixture_restart() {
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

    // One scratch tree, two runs: the whole point. The seam discipline
    // keeps the proof out of the real player tree.
    let scratch = tempfile::tempdir().expect("scratch save dir");
    let env = [
        ("BEVY_ASSET_ROOT", game_dir.as_os_str()),
        ("JACKDAW_SAVE_DIR", scratch.path().as_os_str()),
    ];

    let (loaded1, stderr1) =
        util::run_windowless_game_until(&binary, &game_dir, &env, &["SAVE_WRITTEN"]);
    assert!(
        loaded1,
        "run one never wrote its save; game stderr:\n{stderr1}"
    );
    assert!(
        stderr1.contains("SAVE_FRESH"),
        "run one is a fresh world: {stderr1}"
    );
    assert!(
        stderr1.contains("SAVE_CONFIG master=0.50"),
        "no save yet, the hardcoded config stands: {stderr1}"
    );
    assert!(
        stderr1.contains("SAVE_WRITTEN runs=1"),
        "run one counted and wrote: {stderr1}"
    );

    let (loaded2, stderr2) =
        util::run_windowless_game_until(&binary, &game_dir, &env, &["SAVE_WRITTEN"]);
    assert!(
        loaded2,
        "run two never wrote its save; game stderr:\n{stderr2}"
    );
    assert!(
        stderr2.contains("SAVE_LOADED runs=1"),
        "run two loaded run one's save across the process boundary: {stderr2}"
    );
    assert!(
        stderr2.contains("SAVE_CONFIG master=0.90"),
        "the saved mix stands over the authored config: {stderr2}"
    );
    assert!(
        stderr2.contains("SAVE_WRITTEN runs=2"),
        "run two counted and wrote: {stderr2}"
    );

    // The envelope on disk: the runtime's versioned shape, the game's
    // profile nested under `profile` — human-readable JSON by contract.
    let text = std::fs::read_to_string(scratch.path().join("save.json"))
        .expect("the save landed in the scratch tree");
    let value: serde_json::Value = serde_json::from_str(&text).expect("valid json");
    assert_eq!(
        value
            .get("save_version")
            .and_then(serde_json::Value::as_u64),
        Some(1),
        "the envelope names its version: {text}"
    );
    assert_eq!(
        value
            .pointer("/profile/runs_played")
            .and_then(serde_json::Value::as_u64),
        Some(2),
        "both runs counted: {text}"
    );
    assert_eq!(
        value
            .pointer("/profile/audio/master")
            .and_then(serde_json::Value::as_f64),
        Some(0.9),
        "the player's mix is what the file holds: {text}"
    );
}
