//! Run-configuration manifest (`jackdaw.toml`) types.
//!
//! The editor reads these from the project root to build the Play
//! dropdown. The game never parses them; it only learns its ipc
//! rendezvous name from the bootstrap env var.

use std::collections::BTreeMap;

use serde::Deserialize;

use crate::event::PieMode;

/// One launchable run configuration. A run without a `target` launches
/// the project's default game binary and differs from its siblings only
/// in launch environment; one with a `target` builds and launches that
/// specific cargo target instead.
#[derive(Deserialize, Clone, Debug, Default)]
pub struct RunConfig {
    /// Dropdown label; defaults to `Play`.
    #[serde(default)]
    pub name: Option<String>,
    /// Number of individually launchable copies (`Label #1..#N`).
    #[serde(default = "one")]
    pub instances: u32,
    /// Process env vars set on the child; the game's own input surface.
    #[serde(default)]
    pub env: BTreeMap<String, String>,
    /// Extra argv appended after the game's own.
    #[serde(default)]
    pub args: Vec<String>,
    /// Working directory; defaults to the project root.
    #[serde(default)]
    pub cwd: Option<String>,
    /// Engine-execution axis; `editor-preview` reserved.
    #[serde(default)]
    pub mode: PieMode,
    /// What to build and launch instead of the default game binary.
    /// Absent keeps the historical behavior: the plain package build.
    #[serde(default)]
    pub target: Option<RunTarget>,
}

/// The cargo target a run builds and launches: one `[[bin]]` or one
/// `[[example]]` of the project (or of `package`, when it names another
/// workspace member), with optional cargo features and profile.
///
/// `bin` and `example` are two optional fields rather than one untagged
/// enum because serde's untagged errors are unreadable; exactly-one-of
/// is checked by [`RunTarget::validate`], which can say what to fix.
#[derive(Deserialize, Clone, Debug, Default, PartialEq, Eq)]
pub struct RunTarget {
    /// Build this workspace member instead of the project's resolved
    /// package.
    #[serde(default)]
    pub package: Option<String>,
    /// The `[[bin]]` target to build and launch.
    #[serde(default)]
    pub bin: Option<String>,
    /// The `[[example]]` target to build and launch.
    #[serde(default)]
    pub example: Option<String>,
    /// Cargo features enabled for the build.
    #[serde(default)]
    pub features: Vec<String>,
    /// The cargo profile to build with: `dev`, `release`, or a custom
    /// one the project defines.
    #[serde(default)]
    pub profile: Option<String>,
}

impl RunTarget {
    /// Whether the target can become a cargo command: exactly one of
    /// `bin`/`example`, and a non-empty name. Everything else (features,
    /// profile) cargo itself rejects before compiling.
    pub fn validate(&self) -> Result<(), String> {
        let empty = |kind: &str| format!("target's {kind} name is empty");
        match (&self.bin, &self.example) {
            (Some(_), Some(_)) => Err(format!(
                "target cannot set both bin ({:?}) and example ({:?}); keep one",
                self.bin, self.example
            )),
            (None, None) => Err("target needs a bin or an example".to_string()),
            (Some(bin), None) if bin.trim().is_empty() => Err(empty("bin")),
            (None, Some(example)) if example.trim().is_empty() => Err(empty("example")),
            _ => Ok(()),
        }
    }
}

fn one() -> u32 {
    1
}

impl RunConfig {
    /// The label shown in the dropdown.
    pub fn label(&self) -> &str {
        self.name.as_deref().unwrap_or("Play")
    }
}

/// The parsed `jackdaw.toml`.
#[derive(Deserialize, Clone, Debug, Default)]
pub struct Manifest {
    /// Optional name of the project's root Bevy `Plugin`. Recorded by
    /// import/setup and checked by doctor; Play launches the cargo
    /// binary, which adds the plugin itself.
    #[serde(default)]
    pub plugin: Option<String>,
    #[serde(default, rename = "run")]
    pub runs: Vec<RunConfig>,
}

impl Manifest {
    /// Find a run config by its dropdown label.
    pub fn run_by_name(&self, label: &str) -> Option<&RunConfig> {
        self.runs.iter().find(|r| r.label() == label)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn label_and_defaults() {
        let m: Manifest = toml::from_str(
            r#"[[run]]
name = "My Game""#,
        )
        .unwrap();
        assert_eq!(m.runs[0].label(), "My Game");
        assert_eq!(m.runs[0].instances, 1);
        assert!(m.plugin.is_none());
    }

    #[test]
    fn full_entry_parses() {
        let m: Manifest = toml::from_str(
            r#"
plugin = "MyGamePlugin"

[[run]]
name = "Client"
instances = 4
env = { ADDR = "127.0.0.1:5000" }
"#,
        )
        .unwrap();
        assert_eq!(m.plugin.as_deref(), Some("MyGamePlugin"));
        assert_eq!(m.runs[0].label(), "Client");
        assert_eq!(m.runs[0].instances, 4);
        assert_eq!(m.runs[0].env.get("ADDR").unwrap(), "127.0.0.1:5000");
        assert_eq!(m.run_by_name("Client").unwrap().instances, 4);
    }

    #[test]
    fn legacy_mode_key_is_ignored() {
        let m: Manifest = toml::from_str(
            r#"[[run]]
mode = "editor-preview""#,
        )
        .unwrap();
        assert_eq!(m.runs[0].instances, 1);
    }

    #[test]
    fn a_target_subtable_parses_field_by_field() {
        let m: Manifest = toml::from_str(
            r#"
[[run]]
name = "Server"
target = { bin = "server", features = ["net", "dedicated"], profile = "release" }

[[run]]
name = "Split-screen"
target = { example = "split_screen", package = "game-client" }
"#,
        )
        .unwrap();
        let server = &m.runs[0].target.as_ref().unwrap();
        assert_eq!(server.bin.as_deref(), Some("server"));
        assert_eq!(server.example, None);
        assert_eq!(server.package, None);
        assert_eq!(server.features, ["net", "dedicated"]);
        assert_eq!(server.profile.as_deref(), Some("release"));
        let split = &m.runs[1].target.as_ref().unwrap();
        assert_eq!(split.example.as_deref(), Some("split_screen"));
        assert_eq!(split.bin, None);
        assert_eq!(split.package.as_deref(), Some("game-client"));
        assert_eq!(split.features, Vec::<String>::new());
        assert_eq!(split.profile, None);
        // Everything outside `target` still parses as before.
        assert_eq!(m.runs[0].instances, 1);
    }

    #[test]
    fn a_target_missing_fields_default() {
        let m: Manifest = toml::from_str("[[run]]\ntarget = { bin = \"tool\" }").unwrap();
        let target = m.runs[0].target.as_ref().unwrap();
        assert_eq!(target.bin.as_deref(), Some("tool"));
        assert_eq!(target.package, None);
        assert_eq!(target.features, Vec::<String>::new());
        assert_eq!(target.profile, None);
    }

    #[test]
    fn a_target_naming_both_bin_and_example_is_rejected() {
        let m: Manifest = toml::from_str(
            r#"[[run]]
target = { bin = "a", example = "b" }"#,
        )
        .unwrap();
        let reason = m.runs[0].target.as_ref().unwrap().validate().unwrap_err();
        assert!(reason.contains("both"), "{reason}");
    }

    #[test]
    fn a_target_naming_neither_bin_nor_example_is_rejected() {
        let m: Manifest = toml::from_str(
            r#"[[run]]
target = { profile = "release" }"#,
        )
        .unwrap();
        let reason = m.runs[0].target.as_ref().unwrap().validate().unwrap_err();
        assert!(reason.contains("bin or an example"), "{reason}");
    }

    #[test]
    fn a_target_with_an_empty_name_is_rejected() {
        let m: Manifest = toml::from_str(
            r#"[[run]]
target = { bin = "  " }"#,
        )
        .unwrap();
        let reason = m.runs[0].target.as_ref().unwrap().validate().unwrap_err();
        assert!(reason.contains("empty"), "{reason}");
        let m: Manifest = toml::from_str("[[run]]\ntarget = { example = \"\" }").unwrap();
        let reason = m.runs[0].target.as_ref().unwrap().validate().unwrap_err();
        assert!(reason.contains("empty"), "{reason}");
    }

    #[test]
    fn a_target_naming_exactly_one_is_valid() {
        let bin: Manifest = toml::from_str("[[run]]\ntarget = { bin = \"server\" }").unwrap();
        assert!(bin.runs[0].target.as_ref().unwrap().validate().is_ok());
        let example: Manifest =
            toml::from_str("[[run]]\ntarget = { example = \"split\" }").unwrap();
        assert!(example.runs[0].target.as_ref().unwrap().validate().is_ok());
    }

    /// The lockstep fixture, shared verbatim with the CLI-side reader's
    /// twin test in `jackdaw_project_build::run_manifest`: both readers
    /// parse this same file and both tests assert the same name/target
    /// values, so a field rename on either side goes red here. This half
    /// also pins the non-target fields: a manifest written before targets
    /// existed parses exactly as it did then.
    const LOCKSTEP_FIXTURE: &str = r#"
plugin = "MyGamePlugin"
package = "game-client"

[jackdaw]
version = "0.19.0"
bevy = "0.19"
channel = "stable"

[[run]]
name = "Play"

[[run]]
name = "Server"
instances = 2
env = { SEED = "42" }
args = ["--listen", "0.0.0.0"]
cwd = "server"
target = { bin = "server", features = ["net", "dedicated"], profile = "release" }

[[run]]
name = "Split-screen"
mode = "editor-preview"
target = { example = "split_screen", package = "other-client" }
"#;

    #[test]
    fn a_manifest_from_before_targets_parses_field_by_field() {
        let m: Manifest = toml::from_str(LOCKSTEP_FIXTURE).unwrap();
        assert_eq!(m.plugin.as_deref(), Some("MyGamePlugin"));
        assert_eq!(m.runs.len(), 3);

        let play = &m.runs[0];
        assert_eq!(play.label(), "Play");
        assert_eq!(play.instances, 1);
        assert!(play.env.is_empty());
        assert!(play.args.is_empty());
        assert_eq!(play.cwd, None);
        assert_eq!(play.mode, PieMode::Play);
        assert!(play.target.is_none());

        let server = &m.runs[1];
        assert_eq!(server.label(), "Server");
        assert_eq!(server.instances, 2);
        assert_eq!(server.env.get("SEED").unwrap(), "42");
        assert_eq!(server.args, ["--listen", "0.0.0.0"]);
        assert_eq!(server.cwd.as_deref(), Some("server"));
        assert_eq!(server.mode, PieMode::Play);
        let target = server.target.as_ref().unwrap();
        assert_eq!(target.bin.as_deref(), Some("server"));
        assert_eq!(target.example, None);
        assert_eq!(target.package, None);
        assert_eq!(target.features, ["net", "dedicated"]);
        assert_eq!(target.profile.as_deref(), Some("release"));

        let split = &m.runs[2];
        assert_eq!(split.label(), "Split-screen");
        assert_eq!(split.mode, PieMode::EditorPreview);
        let target = split.target.as_ref().unwrap();
        assert_eq!(target.example.as_deref(), Some("split_screen"));
        assert_eq!(target.bin, None);
        assert_eq!(target.package.as_deref(), Some("other-client"));
        assert_eq!(target.features, Vec::<String>::new());
        assert_eq!(target.profile, None);
    }
}
