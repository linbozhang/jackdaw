//! The project's game flow file: `game.flow.json` inside the assets
//! tree — which scene a game starts from, and which scenes make up the
//! game.
//!
//! ```json
//! {
//!   "start_scene": "menu.bsn",
//!   "scenes": ["menu.bsn", "scene.bsn", "gameover.bsn"]
//! }
//! ```
//!
//! Paths are relative to the assets folder, with `/` separators. The
//! `scenes` list is optional and reads as "just the start scene" when
//! absent; the game itself only consumes `start_scene` — the list is
//! the editor's to validate and an export's to check, never a gate.
//!
//! The file lives in the assets tree so the same file the editor writes
//! is the one a game reads (`jackdaw_runtime::flow`) and the one an
//! export stages whole — one source for all three launch forms. This
//! module is the schema the editor's validation, `game.export` and
//! `jd export` share: [`inspect_flow`] reads and checks, and every
//! problem comes back as a warning that names what is wrong, because a
//! broken flow file must describe itself rather than block an export.

use std::path::{Path, PathBuf};

use path_slash::PathExt as _;

/// The file, inside the assets tree.
pub const FLOW_FILE: &str = "game.flow.json";

/// The field keys the schema knows; anything else warns.
const KNOWN_FIELDS: &[&str] = &["start_scene", "scenes"];

/// The assets subfolder play-in-editor stages unsaved scene copies into
/// while a session runs. A flow path under it is listed but never held
/// to disk: the copies live exactly as long as the session.
const PIE_TEMP_DIR: &str = ".jackdaw-pie";

/// What a flow file says.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct GameFlow {
    /// The scene a standalone game starts from.
    pub start_scene: Option<String>,
    /// The scenes that make up the game. Empty reads the same as
    /// absent: "just the start scene".
    pub scenes: Vec<String>,
}

/// One listed scene and whether the project holds it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SceneOnDisk {
    pub path: String,
    pub on_disk: bool,
}

/// The whole face of one flow file: what it says and what is wrong
/// with it, as the editor's validation, `game.export` and `jd export`
/// all surface it.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct FlowInspection {
    /// Whether the project has a flow file at all. `false` is the
    /// default state of every project, so it warns nothing.
    pub present: bool,
    pub start_scene: Option<String>,
    pub scenes: Vec<SceneOnDisk>,
    /// Every problem, each naming the path or field it concerns. A
    /// healthy (or absent) file leaves this empty.
    pub warnings: Vec<String>,
}

/// Where a project's flow file sits.
pub fn flow_path(assets: &Path) -> PathBuf {
    assets.join(FLOW_FILE)
}

/// Parse and schema-check the flow file's text. Never refuses: every
/// problem comes back as a warning, and what could be read comes back
/// in the [`GameFlow`].
pub fn parse_flow(text: &str) -> (GameFlow, Vec<String>) {
    let mut warnings = Vec::new();
    let value: serde_json::Value = match serde_json::from_str(text) {
        Ok(value) => value,
        Err(err) => {
            warnings.push(format!(
                "{FLOW_FILE} does not read as JSON ({err}); the game will start from the \
                 scene its code names"
            ));
            return (GameFlow::default(), warnings);
        }
    };
    let Some(fields) = value.as_object() else {
        warnings.push(format!(
            "{FLOW_FILE} holds a JSON {}, not an object; the game will start from the \
             scene its code names",
            json_kind(&value)
        ));
        return (GameFlow::default(), warnings);
    };

    let unknown: Vec<&str> = fields
        .keys()
        .map(String::as_str)
        .filter(|field| !KNOWN_FIELDS.contains(field))
        .collect();
    if !unknown.is_empty() {
        warnings.push(format!(
            "{FLOW_FILE} has field(s) the flow schema does not know: {}; they are ignored",
            unknown.join(", ")
        ));
    }

    let start_scene = match fields.get("start_scene") {
        None | Some(serde_json::Value::Null) => {
            warnings.push(format!(
                "{FLOW_FILE} names no start_scene; the game will start from the scene its \
                 code names"
            ));
            None
        }
        Some(serde_json::Value::String(path)) => {
            if path.is_empty() {
                warnings.push(format!(
                    "{FLOW_FILE} names an empty start_scene; the game will start from the \
                     scene its code names"
                ));
                None
            } else if let Some(problem) = path_form_problem(path) {
                warnings.push(format!(
                    "the start scene '{path}' {problem}; the game will start from the scene \
                     its code names"
                ));
                None
            } else {
                Some(path.clone())
            }
        }
        Some(other) => {
            warnings.push(format!(
                "{FLOW_FILE}'s start_scene is a JSON {}, not a string; the game will start \
                 from the scene its code names",
                json_kind(other)
            ));
            None
        }
    };

    let mut scenes = Vec::new();
    match fields.get("scenes") {
        None | Some(serde_json::Value::Null) => {}
        Some(serde_json::Value::Array(items)) => {
            for (index, item) in items.iter().enumerate() {
                match item.as_str() {
                    Some(path) if !path.is_empty() => match path_form_problem(path) {
                        Some(problem) => warnings.push(format!(
                            "scene list entry {} ('{path}') {problem}",
                            index + 1
                        )),
                        None => scenes.push(path.to_string()),
                    },
                    Some(_) => {
                        warnings.push(format!("scene list entry {} is an empty string", index + 1));
                    }
                    None => warnings.push(format!(
                        "scene list entry {} is a JSON {}, not a string",
                        index + 1,
                        json_kind(item)
                    )),
                }
            }
            let mut seen = Vec::new();
            for path in &scenes {
                if seen.contains(path) {
                    warnings.push(format!(
                        "scene '{path}' is listed more than once in the scene list"
                    ));
                }
                seen.push(path.clone());
            }
        }
        Some(other) => warnings.push(format!(
            "{FLOW_FILE}'s scenes is a JSON {}, not a list; the list is ignored",
            json_kind(other)
        )),
    }

    // A list that omits the start scene is legal to the game (it never
    // reads the list) but misdescribes the project; say so.
    if let Some(start) = &start_scene
        && !scenes.is_empty()
        && !scenes.contains(start)
    {
        warnings.push(format!(
            "the start scene '{start}' is not in the scene list"
        ));
    }

    (
        GameFlow {
            start_scene,
            scenes,
        },
        warnings,
    )
}

/// Serialize a flow file the way the editor writes it: pretty, two-space
/// indent, newline-terminated. An empty list serializes away — absent
/// and empty read the same, so a write never adds a key that was not
/// there to mean something.
pub fn flow_json(flow: &GameFlow) -> String {
    let mut object = serde_json::Map::new();
    if let Some(start) = &flow.start_scene {
        object.insert(
            "start_scene".to_string(),
            serde_json::Value::String(start.clone()),
        );
    }
    if !flow.scenes.is_empty() {
        object.insert(
            "scenes".to_string(),
            serde_json::Value::Array(
                flow.scenes
                    .iter()
                    .map(|scene| serde_json::Value::String(scene.clone()))
                    .collect(),
            ),
        );
    }
    let mut json = serde_json::to_string_pretty(&serde_json::Value::Object(object))
        .unwrap_or_else(|_| "{}".to_string());
    json.push('\n');
    json
}

/// Read and check the project's flow file: the parse plus an on-disk
/// check of every path it names. A project without the file inspects
/// clean — the default state, not a problem.
pub fn inspect_flow(assets: &Path) -> FlowInspection {
    let path = flow_path(assets);
    if !path.is_file() {
        return FlowInspection::default();
    }
    let text = match std::fs::read_to_string(&path) {
        Ok(text) => text,
        Err(err) => {
            return FlowInspection {
                present: true,
                warnings: vec![format!("{FLOW_FILE} could not be read ({err})")],
                ..FlowInspection::default()
            };
        }
    };
    let (parsed, mut warnings) = parse_flow(&text);

    let scenes = parsed
        .scenes
        .iter()
        .map(|path| {
            let on_disk = under_pie_temp(path) || scene_on_disk(assets, path);
            if !on_disk {
                warnings.push(format!("scene '{path}' is not on disk"));
            }
            SceneOnDisk {
                path: path.clone(),
                on_disk,
            }
        })
        .collect();

    if let Some(start) = &parsed.start_scene
        && !under_pie_temp(start)
        && !scene_on_disk(assets, start)
    {
        warnings.push(format!(
            "the start scene '{start}' is not on disk; the game will start from the scene \
             its code names"
        ));
    }

    FlowInspection {
        present: true,
        start_scene: parsed.start_scene,
        scenes,
        warnings,
    }
}

/// The warning list alone, for the entries that only need to know
/// whether something is wrong.
pub fn validate_flow(assets: &Path) -> Vec<String> {
    inspect_flow(assets).warnings
}

/// Whether the project holds the scene file a flow path names — the
/// text form, or its compiled `.bsb` twin when the project keeps the
/// binary form on disk.
pub fn scene_on_disk(assets: &Path, path: &str) -> bool {
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

/// Whether a flow path sits in the PIE temp-copy folder.
fn under_pie_temp(path: &str) -> bool {
    Path::new(path)
        .components()
        .next()
        .is_some_and(|first| first.as_os_str() == PIE_TEMP_DIR)
}

/// What disqualifies a flow path, if anything: the file spells paths
/// relative to the assets folder with `/` separators, so anything else
/// is a problem worth naming — never a panic.
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

/// The assets-relative form of a scene file path, as the flow file
/// spells it: `/` separators, no `..`. Accepts an assets-relative path
/// or an absolute path inside `assets`; `None` for anything else.
pub fn assets_relative_path(assets: &Path, raw: &str) -> Option<String> {
    let candidate = Path::new(raw);
    let relative: String = if candidate.is_absolute() {
        candidate
            .strip_prefix(assets)
            .ok()?
            .to_slash_lossy()
            .into_owned()
    } else {
        raw.replace('\\', "/")
    };
    let relative = relative.trim_start_matches("./");
    if relative.is_empty() || path_form_problem(relative).is_some() {
        return None;
    }
    Some(relative.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_absent_file_is_the_quiet_default() {
        let dir = tempfile::tempdir().expect("tempdir");
        let seen = inspect_flow(dir.path());
        assert!(!seen.present);
        assert!(seen.warnings.is_empty());
    }

    #[test]
    fn the_relative_form_accepts_both_spellings() {
        let assets = Path::new("/project/assets");
        assert_eq!(
            assets_relative_path(assets, "menu.bsn").as_deref(),
            Some("menu.bsn")
        );
        assert_eq!(
            assets_relative_path(assets, "/project/assets/menu.bsn").as_deref(),
            Some("menu.bsn")
        );
        assert_eq!(assets_relative_path(assets, "../menu.bsn"), None);
        assert_eq!(assets_relative_path(assets, "/elsewhere/menu.bsn"), None);
    }

    #[test]
    fn a_non_object_file_warns_instead_of_refusing() {
        let (parsed, warnings) = parse_flow("[\"menu.bsn\"]");
        assert_eq!(parsed, GameFlow::default());
        assert!(warnings.iter().any(|warning| warning.contains("list")));
    }

    /// A `start_scene` that is not a string (the hand-edited-JSON
    /// classic) warns and reads as absent, on the validator side — the
    /// runtime side's mirror is `an_unusable_start_scene` (T13-T2 QA
    /// ⚪-2: this branch existed on both sides but only the runtime's
    /// was directly tested).
    #[test]
    fn a_non_string_start_scene_warns_instead_of_refusing() {
        let (parsed, warnings) = parse_flow("{\"start_scene\": 42}");
        assert_eq!(parsed, GameFlow::default());
        assert!(
            warnings
                .iter()
                .any(|warning| warning.contains("start_scene") && warning.contains("number")),
            "{warnings:?}"
        );
    }
}
