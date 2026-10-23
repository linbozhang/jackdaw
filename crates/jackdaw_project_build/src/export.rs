//! Staging a built game into a directory that runs on its own.
//!
//! A `cargo build` artifact in `.jackdaw/target/game/<profile>/` has no
//! assets beside it: double-clicked from Explorer it resolves its asset
//! root to its own directory (the runtime falls back
//! `BEVY_ASSET_ROOT` > `CARGO_MANIFEST_DIR` > the executable's
//! directory), finds no `assets/` there, and loads an empty world. An
//! export therefore copies the executable and the project's whole
//! `assets/` tree into one staging directory — the only layout a
//! standalone run supports:
//!
//! ```text
//! <root>/.jackdaw/dist/<profile>/
//!     my-game.exe
//!     assets/...
//! ```
//!
//! Everything here is bevy-light and editor-independent: `jd export`
//! and the editor's export entry stage through the same functions.

use std::path::{Path, PathBuf};

/// What an export stages and where from. Built by [`plan_export`],
/// executed by [`stage_export`]; splitting the two keeps the layout
/// pure (and testable) while the build pipeline owns where the
/// executable actually lands.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ExportPlan {
    /// The cargo profile the build used. A display name only — and the
    /// staging directory's name, so profiles stage side by side rather
    /// than overwriting each other.
    pub profile: String,
    /// Where the export lands: `<root>/.jackdaw/dist/<profile>`, or
    /// whatever `--out` named. `.jackdaw/` is git-ignored by every
    /// scaffolded project, so the default adds nothing to a commit.
    pub dist_dir: PathBuf,
    /// The executable cargo reported for the build. Copied verbatim;
    /// the export renames nothing.
    pub exe_source: PathBuf,
    /// The project's `assets/` tree, staged whole: a game loads its
    /// scene and every sidecar from there, so a partial copy is a
    /// broken export.
    pub assets_source: PathBuf,
}

/// Where an export stages by default: `<root>/.jackdaw/dist/<profile>`,
/// or `out` when the caller named a directory (the layout inside it is
/// still exe-plus-assets; only the directory's location changes). An
/// `out` must be absolute — [`stage_export`] refuses a relative one,
/// because it clears the staging directory on every run.
pub fn plan_export(root: &Path, profile: &str, binary: &Path, out: Option<&Path>) -> ExportPlan {
    let dist_dir = out.map_or_else(
        || root.join(".jackdaw").join("dist").join(profile),
        Path::to_path_buf,
    );
    ExportPlan {
        profile: profile.to_string(),
        dist_dir,
        exe_source: binary.to_path_buf(),
        assets_source: root.join("assets"),
    }
}

/// A finished export: where everything landed, and how much of it there
/// was, so the caller can report both without re-walking the tree.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ExportReport {
    /// The staging directory that was (re)built.
    pub dist_dir: PathBuf,
    /// The staged executable, `<dist_dir>/<name>.exe`.
    pub executable: PathBuf,
    /// The staged `assets/` directory.
    pub assets_dir: PathBuf,
    /// Files copied: every asset, plus the executable.
    pub files: usize,
}

/// Why an export could not stage. Both ends of a failed copy are always
/// in the message: a locked executable — the common failure, the game
/// from the last export is still running — is only actionable when the
/// user can see which file in which directory.
#[derive(Debug)]
pub enum ExportError {
    /// The build's executable vanished between build and staging.
    MissingExecutable { source: PathBuf },
    /// The project has no `assets/` directory. The staged layout is the
    /// only supported one and its whole point is the asset tree, so an
    /// assetless export is refused rather than shipped broken.
    MissingAssets { source: PathBuf },
    /// The staging path is relative. It would be cleared wherever the
    /// current directory happens to be, which is exactly the accident
    /// the guard exists to prevent.
    RelativeStagingDir { raw: PathBuf },
    /// The staging path did not normalize to a plain absolute path —
    /// empty, or carrying `..` components a verbatim prefix hid.
    InvalidStagingPath { raw: PathBuf },
    /// The staging directory contains a source the export copies from,
    /// or is a filesystem root, so the clearing step would delete the
    /// build, the assets, or a volume.
    UnsafeStagingDir { dir: PathBuf },
    /// The staging directory sits inside a source tree, so the copy
    /// would recurse into its own output.
    StagingInsideSource { dir: PathBuf },
    /// A filesystem action failed; `action` names it with both paths.
    Io {
        action: String,
        error: std::io::Error,
    },
}

impl std::fmt::Display for ExportError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::MissingExecutable { source } => {
                write!(f, "built executable not found at {}", source.display())
            }
            Self::MissingAssets { source } => write!(
                f,
                "no assets directory at {} to stage; a standalone game loads its assets from \
                 beside its executable, so an export without them cannot run",
                source.display()
            ),
            Self::RelativeStagingDir { raw } => write!(
                f,
                "refusing to stage into {}: the output directory must be an absolute path; a \
                 relative one would be cleared wherever the current directory happens to be",
                raw.display()
            ),
            Self::InvalidStagingPath { raw } => write!(
                f,
                "refusing to stage into {}: it does not normalize to a plain absolute path \
                 (empty, or with `..` components)",
                raw.display()
            ),
            Self::UnsafeStagingDir { dir } => write!(
                f,
                "refusing to stage into {}: it holds the build's own sources — or is a \
                 filesystem root — and staging clears the directory first",
                dir.display()
            ),
            Self::StagingInsideSource { dir } => write!(
                f,
                "refusing to stage into {}: it sits inside the build's own sources, and the \
                 copy would recurse into its own output",
                dir.display()
            ),
            Self::Io { action, error } => write!(f, "could not {action}: {error}"),
        }
    }
}

impl std::error::Error for ExportError {}

fn io_error(action: String) -> impl FnOnce(std::io::Error) -> ExportError {
    move |error| ExportError::Io { action, error }
}

/// Copy a built game and its assets into [`ExportPlan::dist_dir`],
/// producing a directory that runs when double-clicked.
///
/// Assets copy first, the executable last: an executable whose copy
/// failed or was interrupted is never mistaken for a complete export,
/// which matters because the copy target of a failed exe copy is often
/// a still-running previous export's exe. A staging directory that
/// already exists is cleared wholesale first — a re-export replaces,
/// it does not merge, so assets the project dropped since the last one
/// do not survive beside the new executable.
pub fn stage_export(plan: &ExportPlan) -> Result<ExportReport, ExportError> {
    if !plan.exe_source.is_file() {
        return Err(ExportError::MissingExecutable {
            source: plan.exe_source.clone(),
        });
    }
    if !plan.assets_source.is_dir() {
        return Err(ExportError::MissingAssets {
            source: plan.assets_source.clone(),
        });
    }
    // The guard compares normalized spellings, and everything after it
    // (the clearing, the copy, the report) uses the normalized staging
    // directory too, so what was judged is what is written.
    let dist = normalize_staging_dir(&plan.dist_dir)?;
    let sources = [
        dunce::simplified(&plan.exe_source),
        dunce::simplified(&plan.assets_source),
    ];
    if let Some(hazard) = staging_hazard(&dist, &sources) {
        return Err(match hazard {
            StagingHazard::InsideSource => ExportError::StagingInsideSource {
                dir: plan.dist_dir.clone(),
            },
            StagingHazard::Root | StagingHazard::ContainsSource => ExportError::UnsafeStagingDir {
                dir: plan.dist_dir.clone(),
            },
        });
    }
    if dist.exists() {
        std::fs::remove_dir_all(&dist).map_err(io_error(format!(
            "clear the existing staging directory {}",
            dist.display()
        )))?;
    }
    std::fs::create_dir_all(&dist).map_err(io_error(format!(
        "create the staging directory {}",
        dist.display()
    )))?;

    let assets_dir = dist.join("assets");
    let files = copy_tree(&plan.assets_source, &assets_dir)?;

    let name = plan.exe_source.file_name().unwrap_or_default();
    let executable = dist.join(name);
    std::fs::copy(&plan.exe_source, &executable).map_err(io_error(format!(
        "copy {} to {}",
        plan.exe_source.display(),
        executable.display()
    )))?;

    Ok(ExportReport {
        dist_dir: dist,
        executable,
        assets_dir,
        files: files + 1,
    })
}

/// Why a staging directory cannot be cleared and rebuilt safely.
enum StagingHazard {
    /// A filesystem root: clearing it deletes a volume, which no
    /// source containment catches across drives.
    Root,
    /// It contains a source: clearing it would delete the build or the
    /// assets themselves.
    ContainsSource,
    /// It sits inside the assets tree: the copy would walk the tree it
    /// is writing and recurse into its own output.
    InsideSource,
}

/// The hazard of clearing and rebuilding `dir`, against `sources` and
/// `dir` already in normalized form. `None` is safe to stage into.
fn staging_hazard(dir: &Path, sources: &[&Path]) -> Option<StagingHazard> {
    if dir.parent().is_none() {
        return Some(StagingHazard::Root);
    }
    if sources.iter().any(|source| source.starts_with(dir)) {
        return Some(StagingHazard::ContainsSource);
    }
    if sources.iter().any(|source| dir.starts_with(source)) {
        return Some(StagingHazard::InsideSource);
    }
    None
}

/// The staging directory in the form the guard compares and the copy
/// uses: absolute, and without a verbatim (`\\?\`) prefix, whose
/// component-wise spelling never compares equal to the same path
/// without it.
///
/// Relative paths are refused outright rather than absolute-ized
/// against the current directory: the clearing step would then delete
/// whatever `cwd` happens to be (`--out .` is exactly this accident).
/// A `..` that survives normalization — only possible behind a
/// verbatim prefix, where the OS resolves nothing — is refused with
/// it.
fn normalize_staging_dir(dir: &Path) -> Result<PathBuf, ExportError> {
    if !dir.is_absolute() {
        return Err(ExportError::RelativeStagingDir {
            raw: dir.to_path_buf(),
        });
    }
    let absolute = std::path::absolute(dir).map_err(|error| ExportError::Io {
        action: format!("normalize the staging directory {}", dir.display()),
        error,
    })?;
    let simplified = dunce::simplified(&absolute);
    if carries_dot_components(simplified) {
        return Err(ExportError::InvalidStagingPath {
            raw: dir.to_path_buf(),
        });
    }
    Ok(simplified.to_path_buf())
}

/// Whether `path` still carries a `.` or `..` component. A normalized
/// absolute path never does; one that does was not really normalized
/// and must not be handed to a directory-clearing step.
fn carries_dot_components(path: &Path) -> bool {
    path.components().any(|component| {
        matches!(
            component,
            std::path::Component::ParentDir | std::path::Component::CurDir
        )
    })
}

/// Copy a directory tree, preserving the relative layout. Returns the
/// number of files copied. A symlink copies as its target's contents,
/// which is what a game expects: the editor never authors links, and a
/// standalone directory cannot carry them meaningfully anyway.
fn copy_tree(source: &Path, target: &Path) -> Result<usize, ExportError> {
    let entries =
        std::fs::read_dir(source).map_err(io_error(format!("read {}", source.display())))?;
    std::fs::create_dir_all(target).map_err(io_error(format!("create {}", target.display())))?;
    let mut files = 0;
    for entry in entries {
        let entry = entry.map_err(io_error(format!("list {}", source.display())))?;
        let to = target.join(entry.file_name());
        if entry
            .file_type()
            .map_err(io_error(format!("stat {}", to.display())))?
            .is_dir()
        {
            files += copy_tree(&entry.path(), &to)?;
        } else {
            let from = entry.path();
            std::fs::copy(&from, &to).map_err(io_error(format!(
                "copy {} to {}",
                from.display(),
                to.display()
            )))?;
            files += 1;
        }
    }
    Ok(files)
}

/// The refusal for a build that linked dynamically, naming the crates
/// whose dlls the staging directory would be missing. `dylibs` is the
/// dylib artifacts the build reported; empty is a statically linked
/// build, which exports fine.
pub fn dynamic_linking_rejection(dylibs: &[String]) -> Option<String> {
    if dylibs.is_empty() {
        return None;
    }
    let crates = dylibs.join(", ");
    Some(format!(
        "this build links dynamically ({crates}), and a staged executable would not start \
         without the dlls it needs\n\
         note: remove `dynamic_linking` from your bevy features (a statically linked game \
         carries everything it needs) and export again"
    ))
}

/// Open `dir` in the platform file manager, so a finished export is
/// where the user is looking. Shared by `jd export` and the editor's
/// export entry for that reason. Failure to open is never an export
/// failure; callers report it and move on.
pub fn reveal_in_file_manager(dir: &Path) -> std::io::Result<()> {
    let program = if cfg!(target_os = "macos") {
        "open"
    } else if cfg!(target_os = "windows") {
        "explorer"
    } else {
        "xdg-open"
    };
    std::process::Command::new(program).arg(dir).spawn()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A fixture project root with a built executable and an assets
    /// tree, in a unique temp directory.
    fn staged_fixture(name: &str) -> (std::path::PathBuf, std::path::PathBuf) {
        let root =
            std::env::temp_dir().join(format!("jackdaw_export_{name}_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let build = root.join(".jackdaw/target/game/release");
        std::fs::create_dir_all(build.join("examples")).unwrap();
        std::fs::create_dir_all(root.join("assets/textures/tile")).unwrap();
        std::fs::write(build.join("my-game.exe"), b"exe bytes").unwrap();
        std::fs::write(root.join("assets/scene.bsn"), b"scene").unwrap();
        std::fs::write(root.join("assets/textures/tile/diffuse.png"), b"png").unwrap();
        (root, build.join("my-game.exe"))
    }

    #[test]
    fn the_default_staging_directory_is_jackdaw_dist_under_the_profile() {
        let root = Path::new("/game");
        let binary = root.join(".jackdaw/target/game/release/my-game.exe");
        let plan = plan_export(root, "release", &binary, None);
        assert_eq!(
            plan.dist_dir,
            Path::new("/game/.jackdaw/dist/release"),
            "the default is <root>/.jackdaw/dist/<profile>"
        );
        assert_eq!(plan.assets_source, Path::new("/game/assets"));
        assert_eq!(plan.exe_source, binary);

        let custom = plan_export(root, "release", &binary, Some(Path::new("/dist")));
        assert_eq!(custom.dist_dir, Path::new("/dist"));

        // Profiles stage side by side rather than overwriting each other.
        let bench = plan_export(root, "bench", &binary, None);
        assert_eq!(bench.dist_dir, Path::new("/game/.jackdaw/dist/bench"));
    }

    #[test]
    fn staging_copies_the_executable_and_the_whole_assets_tree() {
        let (root, binary) = staged_fixture("layout");
        let plan = plan_export(&root, "release", &binary, None);
        let report = stage_export(&plan).expect("the fixture stages");

        assert_eq!(report.executable, plan.dist_dir.join("my-game.exe"));
        assert_eq!(report.assets_dir, plan.dist_dir.join("assets"));
        assert_eq!(report.files, 3, "two assets and the executable");
        assert_eq!(
            std::fs::read(report.executable).unwrap(),
            b"exe bytes",
            "the executable is copied verbatim"
        );
        // The tree's relative layout survives: the game loads
        // `assets/<path>` the same way it did in the project.
        assert_eq!(
            std::fs::read(report.assets_dir.join("scene.bsn")).unwrap(),
            b"scene"
        );
        assert_eq!(
            std::fs::read(report.assets_dir.join("textures/tile/diffuse.png")).unwrap(),
            b"png"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    /// A re-export replaces, it does not merge: an asset the project
    /// dropped since the last export must not survive beside the new
    /// executable, or the game keeps loading a file nothing produces.
    #[test]
    fn a_re_export_clears_the_staging_directory_first() {
        let (root, binary) = staged_fixture("idempotent");
        let plan = plan_export(&root, "release", &binary, None);
        stage_export(&plan).expect("first export");
        std::fs::write(plan.dist_dir.join("assets/stale.bsn"), b"stale").unwrap();
        // A build artifact that happened to sit in the staging dir.
        std::fs::write(plan.dist_dir.join("game.pdb"), b"pdb").unwrap();

        stage_export(&plan).expect("second export");

        assert!(!plan.dist_dir.join("assets/stale.bsn").exists());
        assert!(!plan.dist_dir.join("game.pdb").exists());
        assert!(plan.dist_dir.join("assets/scene.bsn").exists());
        assert!(plan.dist_dir.join("my-game.exe").exists());
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_project_without_assets_is_refused_not_exported_broken() {
        let (root, binary) = staged_fixture("no-assets");
        std::fs::remove_dir_all(root.join("assets")).unwrap();
        let plan = plan_export(&root, "release", &binary, None);
        let error = stage_export(&plan).unwrap_err();
        assert!(
            error.to_string().contains("no assets directory"),
            "got {error}"
        );
        assert!(
            error
                .to_string()
                .contains(&root.join("assets").display().to_string()),
            "the message names the path it looked for: {error}"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_missing_executable_is_refused() {
        let (root, binary) = staged_fixture("no-exe");
        std::fs::remove_file(&binary).unwrap();
        let plan = plan_export(&root, "release", &binary, None);
        let error = stage_export(&plan).unwrap_err();
        assert!(
            error.to_string().contains("executable not found"),
            "got {error}"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    /// `--out` accepts any directory; one containing the export's own
    /// sources would be cleared, deleting the build or the assets:
    /// the project root and the build's target directory are this
    /// test's shapes. The staged directories never touch a real
    /// filesystem root; that shape is covered below, purely.
    #[test]
    fn a_staging_directory_that_contains_the_sources_is_refused() {
        let (root, binary) = staged_fixture("unsafe");
        let plan = plan_export(&root, "release", &binary, None);
        for dir in [
            root.clone(),                           // the project root
            binary.parent().unwrap().to_path_buf(), // the build directory
            root.join("assets"),                    // the assets themselves
        ] {
            let unsafe_plan = ExportPlan {
                dist_dir: dir.clone(),
                ..plan.clone()
            };
            let error = stage_export(&unsafe_plan).unwrap_err();
            assert!(
                error.to_string().contains("refusing to stage"),
                "{} was accepted: {error}",
                dir.display()
            );
        }
        // The untouched sources prove the refusal came first.
        assert!(binary.is_file());
        assert!(root.join("assets/scene.bsn").is_file());
        let _ = std::fs::remove_dir_all(&root);
    }

    /// A filesystem root is a hazard however it is spelled — checked
    /// purely, a real `stage_export` against a root must never run to
    /// find out — and even when no source leads there, which is the
    /// cross-drive shape.
    #[test]
    fn a_filesystem_root_is_always_a_staging_hazard() {
        let sources = [
            Path::new("/elsewhere/game.exe"),
            Path::new("/elsewhere/assets"),
        ];
        assert!(staging_hazard(Path::new("/"), &sources).is_some());
        // A source's own ancestor directories, caught by containment.
        assert!(staging_hazard(Path::new("/elsewhere"), &sources).is_some());
        // A directory beside the sources is fine.
        assert!(staging_hazard(Path::new("/elsewhere/dist"), &sources).is_none());
    }

    /// A Windows drive root is refused even with every source on
    /// another drive: `H:\` contains nothing of `C:\game`, yet clearing
    /// it would delete a volume.
    #[cfg(windows)]
    #[test]
    fn a_drive_root_is_a_hazard_across_drives() {
        let sources = [Path::new(r"C:\game\game.exe"), Path::new(r"C:\game\assets")];
        assert!(staging_hazard(Path::new(r"H:\"), &sources).is_some());
        assert!(staging_hazard(Path::new(r"C:\"), &sources).is_some());
    }

    /// The staging directory must be absolute: a relative one would be
    /// cleared wherever the current directory happens to be, and
    /// `--out .` is exactly that accident. Refused before anything on
    /// disk is touched.
    #[test]
    fn a_relative_staging_directory_is_refused_before_anything_is_touched() {
        let (root, binary) = staged_fixture("relative-out");
        let plan = plan_export(&root, "release", &binary, None);
        for dir in [".", "..", "dist", "assets"] {
            let relative = ExportPlan {
                dist_dir: PathBuf::from(dir),
                ..plan.clone()
            };
            let error = stage_export(&relative).unwrap_err();
            assert!(
                error.to_string().contains("must be an absolute path"),
                "`{dir}` gave: {error}"
            );
        }
        // The fixture is whole: the refusal came before any clearing.
        assert!(binary.is_file());
        assert!(root.join("assets/scene.bsn").is_file());
        let _ = std::fs::remove_dir_all(&root);
    }

    /// A verbatim (`\\?\`) prefix spells the same path differently
    /// enough that a literal comparison misses it: `C:\game\assets`
    /// does not start with `\\?\C:\game` component-wise, so the
    /// prefix alone would smuggle the project root past the guard.
    /// Normalized first, it cannot.
    #[cfg(windows)]
    #[test]
    fn a_verbatim_prefix_cannot_smuggle_a_directory_past_the_guard() {
        let (root, binary) = staged_fixture("verbatim");
        let plan = plan_export(&root, "release", &binary, None);

        let verbatim_project = PathBuf::from(format!(r"\\?\{}", root.display()));
        let smuggled = ExportPlan {
            dist_dir: verbatim_project.clone(),
            ..plan.clone()
        };
        let error = stage_export(&smuggled).unwrap_err();
        assert!(
            error.to_string().contains("refusing to stage"),
            "{} was accepted: {error}",
            verbatim_project.display()
        );

        // The prefix on a drive root is the same hazard as the bare
        // drive root.
        let drive = root.ancestors().last().expect("a drive root");
        let verbatim_drive = PathBuf::from(format!(r"\\?\{}", drive.display()));
        let smuggled_root = ExportPlan {
            dist_dir: verbatim_drive,
            ..plan.clone()
        };
        let error = stage_export(&smuggled_root).unwrap_err();
        assert!(
            error.to_string().contains("refusing to stage"),
            "the verbatim drive root was accepted: {error}"
        );

        // Nothing was cleared.
        assert!(binary.is_file());
        assert!(root.join("assets/scene.bsn").is_file());
        let _ = std::fs::remove_dir_all(&root);
    }

    /// The comparison form of the staging directory: a verbatim prefix
    /// is stripped, and a `..` the prefix might hide is still detected
    /// after the strip — the OS resolves nothing behind `\\?\`, so
    /// neither may the guard.
    #[cfg(windows)]
    #[test]
    fn verbatim_prefixes_are_stripped_and_hidden_dots_are_still_detected() {
        assert_eq!(
            normalize_staging_dir(Path::new(r"\\?\C:\elsewhere\dist")).unwrap(),
            Path::new(r"C:\elsewhere\dist"),
            "a verbatim prefix strips to the plain path"
        );
        let smuggled = PathBuf::from(r"\\?\C:\game\..\other\dist");
        assert!(
            carries_dot_components(dunce::simplified(&smuggled)),
            "a `..` behind a verbatim prefix survives the strip and must be caught"
        );
        // And a plain absolute path with no dots is detected as clean.
        assert!(!carries_dot_components(Path::new(r"C:\elsewhere\dist")));
    }

    /// Staging inside the assets tree would copy the tree into itself:
    /// the walk reaches the directory it is writing. Refused before
    /// the walk, and the source tree shows no pollution.
    #[test]
    fn a_staging_directory_inside_the_assets_tree_is_refused() {
        let (root, binary) = staged_fixture("inside-assets");
        let plan = plan_export(&root, "release", &binary, None);
        let nested = ExportPlan {
            dist_dir: root.join("assets/dist"),
            ..plan.clone()
        };
        let error = stage_export(&nested).unwrap_err();
        assert!(error.to_string().contains("sits inside"), "got {error}");
        assert!(!root.join("assets/dist").exists(), "the copy never started");
        assert!(root.join("assets/scene.bsn").is_file());
        assert!(
            root.join("assets/textures/tile/diffuse.png").is_file(),
            "the source tree is unpolluted"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    /// A dylib in the build report refuses the export with the feature
    /// that caused it named; a static build (the template's shape) is
    /// no refusal at all.
    #[test]
    fn a_dynamic_linking_build_is_refused_with_guidance() {
        let rejection =
            dynamic_linking_rejection(&["bevy_dylib".to_string()]).expect("a dylib refuses");
        assert!(rejection.contains("bevy_dylib"), "{rejection}");
        assert!(rejection.contains("dynamic_linking"), "{rejection}");
        assert!(rejection.contains("statically"), "{rejection}");

        assert_eq!(dynamic_linking_rejection(&[]), None);
    }
}
