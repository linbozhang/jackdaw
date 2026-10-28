//! The game flow config surface over the real validator and the real
//! runtime reader (T13-T2).
//!
//! `assets/game.flow.json` is the single source the three launch forms
//! read (Play's startup-scene run, `cargo run`, the staged export) and
//! the editor validates; these legs pin the schema both sides agree on:
//!
//! * a healthy file — start scene present on disk (a `.bsb` twin
//!   counts), every listed scene on disk — inspects clean;
//! * no flow file at all is the quiet default, not a problem;
//! * every broken shape the plan's matrix names — missing
//!   `start_scene`, a path off the manifest, duplicates, unreadable
//!   JSON, unknown fields, paths that leave the assets folder — warns
//!   with the path named and never refuses;
//! * the runtime reader (`start_scene_in`) reaches the same verdicts
//!   the validator does on the same fixtures, so the two parsers
//!   cannot drift apart silently;
//! * a `.jackdaw-pie/` temp-copy path is listed but not held to disk
//!   (`play_current`'s copies live exactly as long as the session).

use jackdaw_project_build::flow;
use jackdaw_runtime::flow as runtime_flow;

fn write(dir: &std::path::Path, name: &str, text: &str) {
    std::fs::write(dir.join(name), text).expect("write the file");
}

fn flow_text(start_scene: &str, scenes: &[&str]) -> String {
    let scenes = scenes
        .iter()
        .map(|scene| format!("    \"{scene}\""))
        .collect::<Vec<_>>()
        .join(",\n");
    if scenes.is_empty() {
        format!("{{\"start_scene\": \"{start_scene}\"}}\n")
    } else {
        format!(
            "{{\n    \"start_scene\": \"{start_scene}\",\n    \"scenes\": [\n{scenes}\n    ]\n}}\n"
        )
    }
}

fn inspect(dir: &std::path::Path) -> flow::FlowInspection {
    flow::inspect_flow(dir)
}

#[test]
fn a_healthy_flow_inspects_clean() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "menu.bsn", "#MenuRoot\n");
    write(dir.path(), "scene.bsn", "#Anchor\n");
    write(
        dir.path(),
        flow::FLOW_FILE,
        &flow_text("menu.bsn", &["menu.bsn", "scene.bsn"]),
    );

    let seen = inspect(dir.path());
    assert!(seen.present, "the flow file was found");
    assert_eq!(seen.start_scene.as_deref(), Some("menu.bsn"));
    assert_eq!(seen.scenes.len(), 2, "{:?}", seen.scenes);
    assert!(seen.scenes.iter().all(|scene| scene.on_disk));
    assert!(
        seen.warnings.is_empty(),
        "a healthy project warns nothing: {:?}",
        seen.warnings
    );
    assert!(flow::validate_flow(dir.path()).is_empty());
}

#[test]
fn a_bsb_twin_counts_as_on_disk() {
    let dir = tempfile::tempdir().expect("tempdir");
    // The project keeps the binary form; the flow file names the text
    // path every authoring surface spells.
    write(dir.path(), "menu.bsb", "binary");
    write(dir.path(), flow::FLOW_FILE, &flow_text("menu.bsn", &[]));

    let seen = inspect(dir.path());
    assert!(seen.warnings.is_empty(), "{:?}", seen.warnings);
}

#[test]
fn no_flow_file_is_the_quiet_default() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "scene.bsn", "#Anchor\n");

    let seen = inspect(dir.path());
    assert!(!seen.present);
    assert!(seen.start_scene.is_none());
    assert!(seen.scenes.is_empty());
    assert!(
        seen.warnings.is_empty(),
        "every pre-T13 project opens warning-free: {:?}",
        seen.warnings
    );
}

#[test]
fn the_matrix_of_broken_shapes_all_warn() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "scene.bsn", "#Anchor\n");
    write(dir.path(), "menu.bsn", "#MenuRoot\n");

    // Missing start_scene.
    write(
        dir.path(),
        flow::FLOW_FILE,
        "{\n    \"scenes\": [\"scene.bsn\"]\n}\n",
    );
    let seen = inspect(dir.path());
    assert!(
        seen.warnings
            .iter()
            .any(|warning| warning.contains("start_scene")),
        "{:?}",
        seen.warnings
    );

    // Start scene off the manifest: the start scene loads anyway but the
    // list is wrong twice — it does not name the start scene, and it
    // names a file that is not there.
    write(
        dir.path(),
        flow::FLOW_FILE,
        &flow_text("menu.bsn", &["scene.bsn", "ghost.bsn"]),
    );
    let seen = inspect(dir.path());
    assert!(
        seen.warnings
            .iter()
            .any(|warning| warning.contains("menu.bsn") && warning.contains("scene list")),
        "the list that omits the start scene is named: {:?}",
        seen.warnings
    );
    assert!(
        seen.warnings
            .iter()
            .any(|warning| warning.contains("ghost.bsn")),
        "the off-disk list entry is named: {:?}",
        seen.warnings
    );

    // Duplicates.
    write(
        dir.path(),
        flow::FLOW_FILE,
        &flow_text("menu.bsn", &["menu.bsn", "menu.bsn"]),
    );
    let seen = inspect(dir.path());
    assert!(
        seen.warnings
            .iter()
            .any(|warning| warning.contains("more than once")),
        "{:?}",
        seen.warnings
    );

    // Unreadable JSON: warned, never a refusal.
    write(dir.path(), flow::FLOW_FILE, "{ oops");
    let seen = inspect(dir.path());
    assert!(seen.present, "the file is there, it just does not read");
    assert!(
        seen.warnings.iter().any(|warning| warning.contains("JSON")),
        "{:?}",
        seen.warnings
    );

    // Unknown fields.
    write(
        dir.path(),
        flow::FLOW_FILE,
        "{\"start_scene\": \"menu.bsn\", \"legacy\": true}",
    );
    let seen = inspect(dir.path());
    assert!(
        seen.warnings
            .iter()
            .any(|warning| warning.contains("legacy")),
        "{:?}",
        seen.warnings
    );

    // Paths that leave the assets folder.
    write(
        dir.path(),
        flow::FLOW_FILE,
        &flow_text("../escape.bsn", &["/absolute.bsn"]),
    );
    let seen = inspect(dir.path());
    assert!(
        seen.warnings
            .iter()
            .any(|warning| warning.contains("relative")),
        "both path shapes are named: {:?}",
        seen.warnings
    );
    assert!(
        seen.warnings
            .iter()
            .any(|warning| warning.contains("absolute.bsn")),
        "{:?}",
        seen.warnings
    );

    // A start scene that is not on disk.
    write(dir.path(), flow::FLOW_FILE, &flow_text("ghost.bsn", &[]));
    let seen = inspect(dir.path());
    assert!(
        seen.warnings
            .iter()
            .any(|warning| warning.contains("ghost.bsn") && warning.contains("not on disk")),
        "{:?}",
        seen.warnings
    );
}

#[test]
fn pie_temp_copy_paths_are_not_held_to_disk() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "scene.bsn", "#Anchor\n");
    // The temp copy lives exactly as long as the play session; a flow
    // path under it is listed but never flagged for being gone.
    write(
        dir.path(),
        flow::FLOW_FILE,
        &flow_text(
            ".jackdaw-pie/session/scene.bsn",
            &[".jackdaw-pie/session/scene.bsn"],
        ),
    );

    let seen = inspect(dir.path());
    assert_eq!(seen.scenes.len(), 1);
    assert!(seen.scenes[0].on_disk, "the temp-copy entry is skipped");
    assert!(
        !seen
            .warnings
            .iter()
            .any(|warning| warning.contains("not on disk")),
        "{:?}",
        seen.warnings
    );
}

// ---- The two parsers agree ---------------------------------------------

#[test]
fn the_runtime_reader_reaches_the_same_verdicts() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "menu.bsn", "#MenuRoot\n");
    write(dir.path(), "scene.bsn", "#Anchor\n");

    // Healthy: both name the menu.
    write(
        dir.path(),
        flow::FLOW_FILE,
        &flow_text("menu.bsn", &["menu.bsn", "scene.bsn"]),
    );
    let (scene, warnings) = runtime_flow::start_scene_in(Some(dir.path()), "scene.bsn");
    assert_eq!(scene, "menu.bsn");
    assert!(warnings.is_empty(), "{warnings:?}");
    assert!(flow::validate_flow(dir.path()).is_empty());

    // Off-disk start scene: both fall back (the validator warns, the
    // runtime warns and hands back the caller's default).
    write(dir.path(), flow::FLOW_FILE, &flow_text("ghost.bsn", &[]));
    let (scene, warnings) = runtime_flow::start_scene_in(Some(dir.path()), "scene.bsn");
    assert_eq!(scene, "scene.bsn");
    assert!(warnings.iter().any(|warning| warning.contains("ghost.bsn")));
    assert!(
        flow::validate_flow(dir.path())
            .iter()
            .any(|warning| warning.contains("ghost.bsn"))
    );

    // Broken JSON: both say so.
    write(dir.path(), flow::FLOW_FILE, "{ oops");
    let (scene, warnings) = runtime_flow::start_scene_in(Some(dir.path()), "scene.bsn");
    assert_eq!(scene, "scene.bsn");
    assert!(warnings.iter().any(|warning| warning.contains("JSON")));
    assert!(
        flow::validate_flow(dir.path())
            .iter()
            .any(|warning| warning.contains("JSON"))
    );
}

#[test]
fn the_write_helper_round_trips() {
    let written = flow::flow_json(&flow::GameFlow {
        start_scene: Some("menu.bsn".to_string()),
        scenes: vec!["menu.bsn".to_string(), "scene.bsn".to_string()],
    });
    let (parsed, warnings) = flow::parse_flow(&written);
    assert!(warnings.is_empty(), "{warnings:?}");
    assert_eq!(parsed.start_scene.as_deref(), Some("menu.bsn"));
    assert_eq!(parsed.scenes, vec!["menu.bsn", "scene.bsn"]);

    // An empty list serializes away (absent and empty read the same:
    // the list defaults to "just the start scene").
    let minimal = flow::flow_json(&flow::GameFlow {
        start_scene: Some("scene.bsn".to_string()),
        scenes: Vec::new(),
    });
    assert!(!minimal.contains("scenes"), "{minimal}");
    let (parsed, warnings) = flow::parse_flow(&minimal);
    assert!(warnings.is_empty(), "{warnings:?}");
    assert_eq!(parsed.start_scene.as_deref(), Some("scene.bsn"));
    assert!(parsed.scenes.is_empty());
}
