//! The `[[run]]` entries of `jackdaw.toml`, as the CLI needs them.
//!
//! Only names and cargo targets. The editor's own reader lives in
//! `jackdaw_pie_protocol::manifest` and parses the launch environment
//! too, but that crate carries bevy and so must stay out of `jd`. Two
//! readers of one file is this crate's established pattern (see
//! [`crate::project_manifest`]): unknown keys are ignored on both
//! sides, and the lockstep tests below pin the two schemas' field names
//! to the same TOML so neither drifts.

use serde::Deserialize;

/// One `[[run]]` entry: its label and, optionally, the cargo target it
/// builds. Field-for-field the mirror of the protocol crate's
/// `RunConfig`/`RunTarget`; see the module docs for why it exists twice.
#[derive(Deserialize, Clone, Debug, Default, PartialEq, Eq)]
pub struct RunEntry {
    /// Dropdown label; defaults to `Play`, as the editor's reader
    /// defaults it.
    #[serde(default)]
    pub name: Option<String>,
    /// What to build and launch instead of the default game binary.
    #[serde(default)]
    pub target: Option<RunTargetSpec>,
}

impl RunEntry {
    /// The label `--config <label>` selects (and Play shows).
    pub fn label(&self) -> &str {
        self.name.as_deref().unwrap_or("Play")
    }
}

/// The `target` subtable of a `[[run]]` entry, mirroring the protocol
/// crate's `RunTarget` field for field.
#[derive(Deserialize, Clone, Debug, Default, PartialEq, Eq)]
pub struct RunTargetSpec {
    /// Build this workspace member instead of the resolved package.
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
    /// The cargo profile to build with.
    #[serde(default)]
    pub profile: Option<String>,
}

impl RunTargetSpec {
    /// Exactly one non-empty `bin`/`example`, as the protocol side's
    /// `RunTarget::validate` demands; the wording is shared so one file
    /// validates the same whichever reader saw it.
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

/// The `[[run]]` entries of a parsed `jackdaw.toml`. Everything else in
/// the file — the editor side's env/args/mode, the build side's package
/// and pins — is unknown here and ignored, as it always has been.
#[derive(Deserialize, Clone, Debug, Default)]
pub struct RunManifest {
    #[serde(default, rename = "run")]
    pub runs: Vec<RunEntry>,
}

impl RunManifest {
    /// Parse the `[[run]]` entries from a `jackdaw.toml` body.
    pub fn parse(text: &str) -> Result<Self, String> {
        toml::from_str(text).map_err(|error| error.to_string())
    }

    /// Find a run entry by its label, as `--config <label>` does.
    pub fn by_name(&self, label: &str) -> Option<&RunEntry> {
        self.runs.iter().find(|run| run.label() == label)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The lockstep fixture, shared verbatim with the editor-side
    /// reader's twin test in `jackdaw_pie_protocol::manifest`: both
    /// readers parse this same file and both tests assert the same
    /// name/target values, so a field rename on either side goes red
    /// here. This half also pins that a manifest with the other readers'
    /// keys (plugin, package, pins, env/args/mode) parses cleanly.
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
    fn lockstep_names_and_targets_match_the_editor_reader() {
        let manifest = RunManifest::parse(LOCKSTEP_FIXTURE).unwrap();
        assert_eq!(manifest.runs.len(), 3);

        assert_eq!(manifest.runs[0].label(), "Play");
        assert_eq!(manifest.runs[0].target, None);

        let server = &manifest.runs[1];
        assert_eq!(server.label(), "Server");
        assert_eq!(
            server.target,
            Some(RunTargetSpec {
                package: None,
                bin: Some("server".to_string()),
                example: None,
                features: vec!["net".to_string(), "dedicated".to_string()],
                profile: Some("release".to_string()),
            })
        );

        let split = &manifest.runs[2];
        assert_eq!(split.label(), "Split-screen");
        assert_eq!(
            split.target,
            Some(RunTargetSpec {
                package: Some("other-client".to_string()),
                bin: None,
                example: Some("split_screen".to_string()),
                features: Vec::new(),
                profile: None,
            })
        );
    }

    #[test]
    fn entries_are_found_by_label_with_the_default_play() {
        let manifest = RunManifest::parse("[[run]]\ntarget = { bin = \"tool\" }").unwrap();
        // A run with no name defaults to the label Play, as the editor
        // shows it.
        assert_eq!(manifest.runs[0].label(), "Play");
        assert!(manifest.by_name("Play").is_some());
        assert!(manifest.by_name("Nope").is_none());
    }

    #[test]
    fn a_manifest_without_runs_is_empty_not_an_error() {
        let manifest = RunManifest::parse("plugin = \"MyGamePlugin\"\n").unwrap();
        assert!(manifest.runs.is_empty());
        assert!(RunManifest::parse("").unwrap().runs.is_empty());
    }

    #[test]
    fn broken_toml_is_an_error() {
        assert!(RunManifest::parse("this is not = valid = toml [[").is_err());
    }

    #[test]
    fn validation_rejects_the_same_shapes_as_the_editor_reader() {
        let target = |text: &str| {
            RunManifest::parse(text)
                .unwrap()
                .runs
                .into_iter()
                .next()
                .unwrap()
                .target
                .unwrap()
        };
        let both = target("[[run]]\ntarget = { bin = \"a\", example = \"b\" }");
        assert!(both.validate().unwrap_err().contains("both"));
        let neither = target("[[run]]\ntarget = { profile = \"release\" }");
        assert!(
            neither
                .validate()
                .unwrap_err()
                .contains("bin or an example")
        );
        let one = target("[[run]]\ntarget = { example = \"split\" }");
        assert!(one.validate().is_ok());
    }
}
