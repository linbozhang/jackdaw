//! The project's game flow file: which scene a game starts from.
//!
//! A game's own code names a default scene; the project's
//! `assets/game.flow.json` overrides that with the project's own start
//! scene (`start_scene`), and the editor's Play override composes
//! around both. The priority, outermost first:
//!
//! 1. `JACKDAW_PIE_SCENE` — the scene in front of the editor on a
//!    `play_current` launch (read through
//!    [`crate::pie_scene_or`], which composes around this module);
//! 2. `game.flow.json`'s `start_scene` — this module;
//! 3. the scene the game's code names — the caller's fallback.
//!
//! The template's startup line spells the whole chain in one
//! expression: `pie_scene_or(&flow::start_scene_or("scene.bsn"))`.
//!
//! Every problem with the flow file warns and falls back, never
//! refuses: a broken, missing or mis-pointed flow file must describe
//! itself in the log and still hand the game a scene to start from.
//! The file's `scenes` list is the editor's and an export's to check —
//! the game reads only `start_scene` and polices nothing else.

use std::path::{Path, PathBuf};

use bevy::log::warn;

/// The file the flow is read from, under the asset root.
pub const FLOW_FILE: &str = "game.flow.json";

/// The scene a standalone game starts from: the project flow file's
/// `start_scene` when the project has one that names a scene on disk,
/// and the caller's fallback otherwise.
///
/// Every problem warns with a `game flow:` line naming the path and
/// the fallback, so a mis-pointed project says so on every launch:
/// no flow file is the quiet default (every pre-flow project lives
/// there), while an unreadable file, a missing or mis-typed
/// `start_scene`, or a scene that is not on disk warn and fall back.
///
/// The asset root is resolved the way the asset server resolves its
/// default source: `BEVY_ASSET_ROOT`, then `CARGO_MANIFEST_DIR`, then
/// the executable's directory, each with the `assets` folder joined —
/// the layout `cargo run`, a Play launch and a staged export all
/// produce. A game that reads its assets from a folder renamed through
/// a custom `AssetPlugin::file_path` resolves flow the same way the
/// catalog's direct reads do, against the default name.
pub fn start_scene_or(fallback: &str) -> String {
    let (scene, warnings) = start_scene_in(standalone_asset_root().as_deref(), fallback);
    for warning in warnings {
        warn!("game flow: {warning}");
    }
    scene
}

/// [`start_scene_or`] against an explicit asset root: the seam a caller
/// that resolves the root itself reads through, and the one tests read
/// through to stay out of the process-wide environment. Returns the
/// scene and the warnings that explain it (empty for the quiet
/// default of a project with no flow file).
pub fn start_scene_in(assets: Option<&Path>, fallback: &str) -> (String, Vec<String>) {
    let Some(assets) = assets else {
        return (fallback.to_string(), Vec::new());
    };
    let Ok(text) = std::fs::read_to_string(assets.join(FLOW_FILE)) else {
        return (fallback.to_string(), Vec::new());
    };
    let mut warnings = Vec::new();
    let Some(start_scene) = parse_start_scene(&text, &mut warnings) else {
        return (fallback.to_string(), warnings);
    };
    if let Some(problem) = path_form_problem(&start_scene) {
        warnings.push(format!(
            "the start scene '{start_scene}' {problem}; starting from '{fallback}'"
        ));
        return (fallback.to_string(), warnings);
    }
    if !scene_on_disk(assets, &start_scene) {
        warnings.push(format!(
            "the start scene '{start_scene}' is not on disk; starting from '{fallback}'"
        ));
        return (fallback.to_string(), warnings);
    }
    (start_scene, warnings)
}

/// The one field the game consumes, with the schema's side conditions
/// checked along the way: unknown fields are named and ignored, a
/// missing, mis-typed or empty `start_scene` (or a file that does not
/// read at all) lands as `None` with the warning written through.
fn parse_start_scene(text: &str, warnings: &mut Vec<String>) -> Option<String> {
    let value: serde_json::Value = match serde_json::from_str(text) {
        Ok(value) => value,
        Err(err) => {
            warnings.push(format!(
                "{FLOW_FILE} does not read as JSON ({err}); starting from the scene the \
                 game's code names"
            ));
            return None;
        }
    };
    let Some(fields) = value.as_object() else {
        warnings.push(format!(
            "{FLOW_FILE} holds a JSON {}, not an object; starting from the scene the \
             game's code names",
            json_kind(&value)
        ));
        return None;
    };
    for field in fields.keys() {
        if field != "start_scene" && field != "scenes" {
            warnings.push(format!(
                "{FLOW_FILE} has a field the flow schema does not know: '{field}'; it is \
                 ignored"
            ));
        }
    }
    match fields.get("start_scene") {
        None | Some(serde_json::Value::Null) => {
            warnings.push(format!(
                "{FLOW_FILE} names no start_scene; starting from the scene the game's code \
                 names"
            ));
            None
        }
        Some(serde_json::Value::String(path)) if path.is_empty() => {
            warnings.push(format!(
                "{FLOW_FILE} names an empty start_scene; starting from the scene the \
                 game's code names"
            ));
            None
        }
        Some(serde_json::Value::String(path)) => Some(path.clone()),
        Some(other) => {
            warnings.push(format!(
                "{FLOW_FILE}'s start_scene is a JSON {}, not a string; starting from the \
                 scene the game's code names",
                json_kind(other)
            ));
            None
        }
    }
}

/// The asset root a standalone process reads: the way bevy's
/// `FileAssetReader` resolves its base, with the default `assets`
/// folder joined. The [`crate::JackdawPlugin`] records the app's own
/// resolution at build time for its systems; this free function
/// serves the startup line that runs before any system could.
fn standalone_asset_root() -> Option<PathBuf> {
    let base = if let Ok(root) = std::env::var("BEVY_ASSET_ROOT") {
        PathBuf::from(root)
    } else if let Ok(manifest) = std::env::var("CARGO_MANIFEST_DIR") {
        PathBuf::from(manifest)
    } else {
        std::env::current_exe()
            .ok()
            .and_then(|exe| exe.parent().map(ToOwned::to_owned))?
    };
    Some(base.join("assets"))
}

/// What disqualifies a flow path: the file spells paths relative to
/// the assets folder with `/` separators.
fn path_form_problem(path: &str) -> Option<&'static str> {
    if Path::new(path).is_absolute() {
        return Some("must be a path relative to the assets folder, not an absolute path");
    }
    if path.contains('\\') {
        return Some("must use / separators, not backslashes");
    }
    if Path::new(path)
        .components()
        .any(|component| !matches!(component, std::path::Component::Normal(_)))
    {
        return Some("must be a path relative to the assets folder");
    }
    None
}

/// Whether the scene file a flow path names is on disk — the text
/// form, or its compiled `.bsb` twin.
fn scene_on_disk(assets: &Path, path: &str) -> bool {
    let direct = assets.join(path);
    if direct.is_file() {
        return true;
    }
    let candidate = Path::new(path);
    if candidate.extension().is_some_and(|ext| ext == "bsn") {
        return direct.with_extension("bsb").is_file();
    }
    if candidate.extension().is_some_and(|ext| ext == "bsb") {
        return direct.with_extension("bsn").is_file();
    }
    false
}

fn json_kind(value: &serde_json::Value) -> &'static str {
    match value {
        serde_json::Value::Null => "null",
        serde_json::Value::Bool(_) => "boolean",
        serde_json::Value::Number(_) => "number",
        serde_json::Value::String(_) => "string",
        serde_json::Value::Array(_) => "list",
        serde_json::Value::Object(_) => "object",
    }
}
