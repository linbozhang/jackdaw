//! Staging a built game into a directory that runs on its own.
//!
//! A `cargo build` artifact in `.jackdaw/target/game/<profile>/` has no
//! assets beside it: double-clicked from Explorer it resolves its asset
//! root to its own directory (the runtime falls back
//! `BEVY_ASSET_ROOT` > `CARGO_MANIFEST_DIR` > the executable's
//! directory), finds no assets there, and loads an empty world. An
//! export therefore copies the executable and the project's whole
//! asset tree (the folder `jackdaw.toml`'s `assets_dir` names, `assets`
//! by default) into one staging directory — the only layout a
//! standalone run supports:
//!
//! ```text
//! <root>/.jackdaw/dist/<profile>/
//!     my-game.exe
//!     assets/...
//!     .jackdaw-export      <- marker naming this directory as ours
//! ```
//!
//! The replacement is atomic at the directory level: the export is
//! assembled in full beside the output (a `.<profile>.staging-*`
//! sibling), and only a complete one is swapped in — the previous
//! export is moved aside, the staging directory takes its place, and
//! the moved-aside copy is deleted after. A failure at any point
//! leaves the previous export exactly as it was.
//!
//! Everything here is bevy-light and editor-independent: `jd export`
//! and the editor's export entry stage through the same functions.

use std::path::{Path, PathBuf};

/// The marker file an export leaves at the root of its output: proof
/// the directory belongs to a jackdaw export. [`stage_export`] refuses
/// to replace a non-empty directory without one (see
/// [`ExportError::ForeignOutputDir`]), so a mistyped `--out` into a
/// user directory is stopped by a second gate beyond the path guards.
const EXPORT_MARKER: &str = ".jackdaw-export";

/// Directory names the asset copy refuses to descend into: the PIE
/// temp copies live in `assets/.jackdaw-pie/` while a play session
/// runs, and hold unsaved scene content a release must not ship.
const SKIPPED_ASSET_DIRS: &[&str] = &[".jackdaw-pie"];

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
    /// The project's asset tree, staged whole: a game loads its
    /// scene and every sidecar from there, so a partial copy is a
    /// broken export. Follows the `assets_dir` of the project's
    /// `jackdaw.toml` rather than assuming `assets`.
    pub assets_source: PathBuf,
    /// Where the assets land inside [`ExportPlan::dist_dir`]: the
    /// manifest's `assets_dir` verbatim, so a project whose game reads
    /// `content/` stages into `<dist>/content/` exactly as the game
    /// resolves it beside its executable.
    pub assets_staged_subdir: PathBuf,
    /// Whether [`stage_export`] may replace a non-empty output
    /// directory without the jackdaw export marker. The CLI's
    /// `--force`; the editor entry leaves it off — its default
    /// directory is always one jackdaw created.
    pub force: bool,
}

/// Where an export stages by default: `<root>/.jackdaw/dist/<profile>`,
/// or `out` when the caller named a directory (the layout inside it is
/// still exe-plus-assets; only the directory's location changes). An
/// `out` must be absolute — [`stage_export`] refuses a relative one,
/// because the staging swap replaces the directory on every run.
pub fn plan_export(root: &Path, profile: &str, binary: &Path, out: Option<&Path>) -> ExportPlan {
    let dist_dir = out.map_or_else(
        || root.join(".jackdaw").join("dist").join(profile),
        Path::to_path_buf,
    );
    // The manifest's own reader is authoritative here: whatever folder
    // it names (falling back to `assets`) is the folder the game reads
    // and the one the editor indexes, so the export must stage the
    // same tree under the same name.
    let manifest = crate::project_manifest::ProjectManifest::read(root);
    let assets_dir = manifest.assets_dir();
    ExportPlan {
        profile: profile.to_string(),
        dist_dir,
        exe_source: binary.to_path_buf(),
        assets_source: root.join(assets_dir),
        assets_staged_subdir: assets_dir.to_path_buf(),
        force: false,
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
    /// The staged asset directory.
    pub assets_dir: PathBuf,
    /// Files copied: every asset, plus the executable. The export
    /// marker is not counted.
    pub files: usize,
    /// Files and directories the editor-private filter kept out of
    /// the package (scene `.bak` rotations, atomic-write temp and
    /// corrupt leftovers, PIE copies), so what did not ship is
    /// auditable rather than silent.
    pub skipped: usize,
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
    /// The staging path is relative. It would be replaced wherever the
    /// current directory happens to be, which is exactly the accident
    /// the guard exists to prevent.
    RelativeStagingDir { raw: PathBuf },
    /// The staging path did not normalize to a plain absolute path —
    /// empty, or carrying `..` components a verbatim prefix hid.
    InvalidStagingPath { raw: PathBuf },
    /// The staging directory contains a source the export copies from,
    /// or is a filesystem root, so the swap would discard the build,
    /// the assets, or a volume.
    UnsafeStagingDir { dir: PathBuf },
    /// The staging directory sits inside a source tree, so the copy
    /// would recurse into its own output.
    StagingInsideSource { dir: PathBuf },
    /// The staging directory exists, holds something, and carries no
    /// jackdaw export marker — it is not ours to replace. The second
    /// gate for a mistyped `--out` into a user directory.
    ForeignOutputDir { dir: PathBuf },
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
                 relative one would be replaced wherever the current directory happens to be",
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
                 filesystem root — and staging replaces the directory wholesale",
                dir.display()
            ),
            Self::StagingInsideSource { dir } => write!(
                f,
                "refusing to stage into {}: it sits inside the build's own sources, and the \
                 copy would recurse into its own output",
                dir.display()
            ),
            Self::ForeignOutputDir { dir } => write!(
                f,
                "refusing to stage into {}: it is not empty and has no {} marker, so it does \
                 not belong to a jackdaw export; pass --force to replace it, or choose \
                 another --out",
                dir.display(),
                EXPORT_MARKER
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
/// The replacement is atomic: everything is assembled in a staging
/// sibling beside the output, and only a complete assembly is swapped
/// in (previous export moved aside, staging moved into its place,
/// moved-aside copy deleted after). A failure — or an interruption —
/// at any step leaves the previous export byte for byte intact, which
/// is the property a failed export must have. Within the staging
/// directory assets copy first and the executable last, so an
/// executable whose copy failed is never mistaken for a complete
/// export inside the staging directory either.
///
/// A re-export replaces, it does not merge, so assets the project
/// dropped since the last one do not survive beside the new executable
/// (the swap swaps whole directories).
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
    // (the staging, the copy, the swap, the report) uses the normalized
    // output directory too, so what was judged is what is written.
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
    // The second gate for a mistyped `--out`: a directory that holds
    // something and was never written by an export is not ours to
    // replace. `--force` (the CLI's explicit intent) walks past it.
    if !plan.force && output_dir_is_foreign(&dist) {
        return Err(ExportError::ForeignOutputDir {
            dir: plan.dist_dir.clone(),
        });
    }

    // The staging sibling lives in the output's parent directory: the
    // same volume, so the final swap is a directory rename — atomic —
    // rather than a cross-volume copy.
    let Some(parent) = dist.parent().map(Path::to_path_buf) else {
        return Err(ExportError::UnsafeStagingDir {
            dir: plan.dist_dir.clone(),
        });
    };
    std::fs::create_dir_all(&parent).map_err(io_error(format!(
        "create the output's parent directory {}",
        parent.display()
    )))?;
    // Leftovers of earlier interrupted exports (a staging directory
    // half-built, a trash directory that could not be deleted) are
    // this export's to clean: they are the orphans of this very
    // mechanism.
    cleanup_orphan_exports(&parent, &plan.profile);
    let staging = unique_dir(
        &parent,
        &format!(".{}.staging-{}-", plan.profile, std::process::id()),
    );

    // Assemble the whole export inside the staging sibling. Any failure
    // here — a blocked directory, a locked source, a full disk —
    // removes the staging sibling and leaves the previous export
    // untouched.
    let copied = match stage_into(plan, &staging) {
        Ok(copied) => copied,
        Err(error) => {
            let _ = std::fs::remove_dir_all(&staging);
            return Err(error);
        }
    };
    if let Err(error) = swap_into_place(&dist, &staging, &parent, &plan.profile) {
        // The swap restores what it moved; the staging sibling is this
        // branch's to remove either way.
        let _ = std::fs::remove_dir_all(&staging);
        return Err(error);
    }

    let executable = dist.join(plan.exe_source.file_name().unwrap_or_default());
    Ok(ExportReport {
        assets_dir: dist.join(&plan.assets_staged_subdir),
        dist_dir: dist,
        executable,
        files: copied.files + 1,
        skipped: copied.skipped,
    })
}

/// Whether the output directory holds content that is not ours: it
/// exists, something is in it, and no export marker vouches for it. An
/// empty directory (a first export into a new place) and a marked one
/// (every re-export) are both fine; anything else gets to keep its
/// contents.
fn output_dir_is_foreign(dist: &Path) -> bool {
    if !dist.exists() || dist.join(EXPORT_MARKER).exists() {
        return false;
    }
    match std::fs::read_dir(dist) {
        Ok(mut entries) => entries.next().is_some(),
        // Not a directory (a file sits at the output path), or not
        // listable: either way it is not an empty export directory.
        Err(_) => true,
    }
}

/// Assemble the complete export inside `staging`: the asset tree, the
/// executable, the export marker. Nothing here touches the output
/// directory, which is what makes every failure in it recoverable.
fn stage_into(plan: &ExportPlan, staging: &Path) -> Result<Copied, ExportError> {
    std::fs::create_dir_all(staging).map_err(io_error(format!(
        "create the staging directory {}",
        staging.display()
    )))?;
    let copied = copy_tree(
        &plan.assets_source,
        &staging.join(&plan.assets_staged_subdir),
    )?;
    let staged_exe = staging.join(plan.exe_source.file_name().unwrap_or_default());
    std::fs::copy(&plan.exe_source, &staged_exe).map_err(io_error(format!(
        "copy {} to {}",
        plan.exe_source.display(),
        staged_exe.display()
    )))?;
    std::fs::write(
        staging.join(EXPORT_MARKER),
        export_marker_contents(&plan.profile),
    )
    .map_err(io_error(format!(
        "write the export marker {}",
        staging.join(EXPORT_MARKER).display()
    )))?;
    Ok(copied)
}

/// Replace `dist` with `staging` in one directory-level move: the
/// previous export (if any) is renamed aside to a trash sibling, the
/// staging directory is renamed into its place, and only then is the
/// trash deleted — a deletion failure leaves an orphan the next export
/// cleans, never a broken output. If the staging rename fails after
/// the previous export was moved, it is moved right back.
fn swap_into_place(
    dist: &Path,
    staging: &Path,
    parent: &Path,
    profile: &str,
) -> Result<(), ExportError> {
    let trash = if dist.exists() {
        let trash = unique_dir(parent, &format!(".{profile}.trash-{}-", unix_time_secs()));
        std::fs::rename(dist, &trash).map_err(io_error(format!(
            "move the previous export {} aside for the new one",
            dist.display()
        )))?;
        Some(trash)
    } else {
        None
    };
    match std::fs::rename(staging, dist) {
        Ok(()) => {
            if let Some(trash) = trash
                && let Err(error) = std::fs::remove_dir_all(&trash)
            {
                // The new export is in place; an undeletable trash is a
                // leftover for the next export's orphan cleanup, not a
                // failure to report as one.
                tracing::warn!(
                    "could not delete the previous export {}: {error}; it stays until the \
                     next export cleans it up",
                    trash.display()
                );
            }
            Ok(())
        }
        Err(error) => {
            if let Some(trash) = trash {
                let _ = std::fs::rename(&trash, dist);
            }
            Err(ExportError::Io {
                action: format!("move the staged export into place at {}", dist.display()),
                error,
            })
        }
    }
}

/// The marker's contents: which jackdaw, which profile, when. Readable
/// in any editor, and the marker's mere presence — not its contents —
/// is what the output gate checks.
fn export_marker_contents(profile: &str) -> String {
    format!(
        "jackdaw export\nversion {}\nprofile {}\nat {}\n",
        crate::VERSION,
        profile,
        unix_time_secs()
    )
}

/// Whole seconds since the Unix epoch, 0 if the clock is behind it —
/// a timestamp for names and markers, not a measurement.
fn unix_time_secs() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs())
        .unwrap_or(0)
}

/// A directory name under `parent` to stage into: `prefix` plus a
/// counter. An existing *directory* with the name — a leftover of a
/// crashed attempt in this same process — moves the counter on;
/// anything else squatting on the name is deliberately returned, so
/// the staging step fails on it loudly instead of silently growing a
/// suffix nobody asked for.
fn unique_dir(parent: &Path, prefix: &str) -> PathBuf {
    let mut counter = 0;
    loop {
        let candidate = parent.join(format!("{prefix}{counter}"));
        if !candidate.is_dir() {
            return candidate;
        }
        counter += 1;
    }
}

/// Remove the staging and trash siblings earlier interrupted exports
/// of this profile left beside the output. Directories only, and this
/// profile's only: a same-named file is not ours to delete, and other
/// profiles' siblings may belong to a live export of theirs.
fn cleanup_orphan_exports(parent: &Path, profile: &str) {
    let prefixes = [format!(".{profile}.staging-"), format!(".{profile}.trash-")];
    let Ok(entries) = std::fs::read_dir(parent) else {
        return;
    };
    for entry in entries.flatten() {
        let is_ours = entry.file_type().is_ok_and(|kind| kind.is_dir())
            && prefixes.iter().any(|prefix| {
                entry
                    .file_name()
                    .to_string_lossy()
                    .starts_with(prefix.as_str())
            });
        if is_ours {
            let _ = std::fs::remove_dir_all(entry.path());
        }
    }
}

/// Why a staging directory cannot be replaced safely.
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
    if sources.iter().any(|source| path_contains(dir, source)) {
        return Some(StagingHazard::ContainsSource);
    }
    if sources.iter().any(|source| path_contains(source, dir)) {
        return Some(StagingHazard::InsideSource);
    }
    None
}

/// Whether `descendant` names the same path as `ancestor` or one inside
/// it. On Windows the comparison matches the filesystem: NTFS resolves
/// names case-insensitively, so `C:\Game\Assets` does contain `c:\game`
/// there, and a `Path::starts_with` byte comparison would let a
/// case-variant spelling of the sources smuggle a directory past the
/// guard. Everywhere else the filesystems are case-sensitive and the
/// comparison stays byte-exact.
fn path_contains(ancestor: &Path, descendant: &Path) -> bool {
    #[cfg(windows)]
    {
        let mut ancestor = ancestor.components();
        let mut descendant = descendant.components();
        loop {
            match (ancestor.next(), descendant.next()) {
                (None, _) => return true,
                (Some(_), None) => return false,
                (Some(a), Some(d)) => {
                    let (a, d) = (
                        a.as_os_str().to_string_lossy(),
                        d.as_os_str().to_string_lossy(),
                    );
                    if !a.eq_ignore_ascii_case(&d) {
                        return false;
                    }
                }
            }
        }
    }
    #[cfg(not(windows))]
    {
        descendant.starts_with(ancestor)
    }
}

/// The staging directory in the form the guard compares and the copy
/// uses: absolute, and without a verbatim (`\\?\`) prefix, whose
/// component-wise spelling never compares equal to the same path
/// without it.
///
/// Relative paths are refused outright rather than absolute-ized
/// against the current directory: the swap would then replace
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

/// What a tree copy moved: the files that shipped, and the entries the
/// editor-private filter kept out, so a report can say both.
#[derive(Default)]
struct Copied {
    files: usize,
    skipped: usize,
}

/// Copy a directory tree, preserving the relative layout. Returns the
/// number of files copied and the editor-private entries filtered out.
/// A symlink copies as its target's contents, which is what a game
/// expects: the editor never authors links, and a standalone directory
/// cannot carry them meaningfully anyway.
///
/// The filter is a name list, deliberately narrow: the editor's own
/// artifacts inside the asset tree — the PIE temp directory, scene
/// save rotations and atomic-write leftovers — and nothing else. See
/// [`SKIPPED_ASSET_DIRS`] and [`is_editor_private_file`].
fn copy_tree(source: &Path, target: &Path) -> Result<Copied, ExportError> {
    let entries =
        std::fs::read_dir(source).map_err(io_error(format!("read {}", source.display())))?;
    std::fs::create_dir_all(target).map_err(io_error(format!("create {}", target.display())))?;
    let mut copied = Copied::default();
    for entry in entries {
        let entry = entry.map_err(io_error(format!("list {}", source.display())))?;
        let name = entry.file_name();
        let to = target.join(&name);
        if entry
            .file_type()
            .map_err(io_error(format!("stat {}", to.display())))?
            .is_dir()
        {
            if SKIPPED_ASSET_DIRS.contains(&name.to_string_lossy().as_ref()) {
                copied.skipped += 1;
                continue;
            }
            let inner = copy_tree(&entry.path(), &to)?;
            copied.files += inner.files;
            copied.skipped += inner.skipped;
        } else {
            if is_editor_private_file(&name) {
                copied.skipped += 1;
                continue;
            }
            let from = entry.path();
            std::fs::copy(&from, &to).map_err(io_error(format!(
                "copy {} to {}",
                from.display(),
                to.display()
            )))?;
            copied.files += 1;
        }
    }
    Ok(copied)
}

/// Whether `name` is an editor-private file the asset copy must not
/// ship: the `.bak` single-generation rotation and the `*.tmp-` /
/// `*.corrupt-` atomic-write leftovers all land inside the asset tree
/// when scenes save, and a PIE session's unsaved scene content lives
/// under `.jackdaw-pie/`. Everything else — including any dotfile a
/// user legitimately owns — copies.
fn is_editor_private_file(name: &std::ffi::OsStr) -> bool {
    let name = name.to_string_lossy();
    name.ends_with(".bak") || name.contains(".tmp-") || name.contains(".corrupt-")
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

    /// A byte-for-byte digest of a directory tree: every file's relative
    /// path and contents, sorted, so two trees compare equal exactly
    /// when their contents match. The export marker is excluded — it
    /// carries the export time, which no content comparison should.
    fn tree_digest(dir: &Path) -> Vec<(String, Vec<u8>)> {
        fn walk(dir: &Path, prefix: &Path, files: &mut Vec<(String, Vec<u8>)>) {
            for entry in std::fs::read_dir(dir).unwrap() {
                let entry = entry.unwrap();
                let path = entry.path();
                let rel = prefix.join(entry.file_name());
                if entry.file_type().unwrap().is_dir() {
                    walk(&path, &rel, files);
                } else {
                    files.push((rel.display().to_string(), std::fs::read(&path).unwrap()));
                }
            }
        }
        let mut files = Vec::new();
        walk(dir, Path::new(""), &mut files);
        files.retain(|(path, _)| path != ".jackdaw-export");
        files.sort();
        files
    }

    /// A failed export must keep the previous one byte for byte. The
    /// staged directory is assembled beside the output and swapped in
    /// only when complete, so a failure anywhere before the swap never
    /// touches what the previous export left. Injected here: a file
    /// squatting on the staging directory's name blocks its creation —
    /// the same blocked-parent fault injection the scene save tests use.
    #[test]
    fn a_failure_while_staging_keeps_the_previous_export_intact() {
        let (root, binary) = staged_fixture("keep-old");
        let plan = plan_export(&root, "release", &binary, None);
        stage_export(&plan).expect("the first export stages");
        std::fs::write(root.join("assets/second.bsn"), b"only in the second export").unwrap();
        let before = tree_digest(&plan.dist_dir);

        let parent = plan.dist_dir.parent().unwrap().to_path_buf();
        std::fs::create_dir_all(&parent).unwrap();
        let blocker = parent.join(format!(".release.staging-{}-0", std::process::id()));
        std::fs::write(&blocker, b"file blocks directory creation").unwrap();

        let error = stage_export(&plan).unwrap_err();
        assert!(
            error.to_string().contains(&blocker.display().to_string()),
            "the failure names the staging directory it could not build: {error}"
        );
        assert_eq!(
            tree_digest(&plan.dist_dir),
            before,
            "a failed staging must leave the previous export byte for byte intact"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    /// The executable copy can fail while its source is locked (a
    /// build still running, an antivirus scan). The previous export
    /// must survive that failure intact too: the copy happens inside
    /// the staging directory, and only a complete one is swapped in.
    #[cfg(windows)]
    #[test]
    fn a_locked_executable_source_keeps_the_previous_export_intact() {
        use std::os::windows::fs::OpenOptionsExt;
        let (root, binary) = staged_fixture("locked-exe");
        let plan = plan_export(&root, "release", &binary, None);
        stage_export(&plan).expect("the first export stages");
        let before = tree_digest(&plan.dist_dir);

        // share_mode(0): no other handle may even read the source, so
        // the executable copy fails.
        let held = std::fs::File::options()
            .read(true)
            .share_mode(0)
            .open(&binary)
            .unwrap();
        let error = stage_export(&plan).unwrap_err();
        drop(held);
        assert!(
            error.to_string().contains("copy"),
            "the failure is the copy: {error}"
        );
        assert_eq!(
            tree_digest(&plan.dist_dir),
            before,
            "the previous export is untouched when the executable copy fails"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    /// The swap itself can fail: the previous export's game can still
    /// be running, and a handle without FILE_SHARE_DELETE makes the OS
    /// refuse to move its directory aside. The refusal must bubble up
    /// as an error — never fall back to deleting — and the locked
    /// export stays where it was, byte for byte.
    #[cfg(windows)]
    #[test]
    fn a_locked_previous_export_refuses_the_swap_and_stays_intact() {
        use std::os::windows::fs::OpenOptionsExt;
        let (root, binary) = staged_fixture("locked-swap");
        let plan = plan_export(&root, "release", &binary, None);
        stage_export(&plan).expect("the first export stages");
        let before = tree_digest(&plan.dist_dir);

        // FILE_SHARE_READ | FILE_SHARE_WRITE, no DELETE: the directory
        // holding this file cannot be renamed.
        let held = std::fs::File::options()
            .read(true)
            .share_mode(1 | 2)
            .open(plan.dist_dir.join("my-game.exe"))
            .unwrap();
        let error = stage_export(&plan).unwrap_err();
        drop(held);
        assert!(
            error.to_string().contains("move the previous export"),
            "the failure names the swap it could not do: {error}"
        );
        assert_eq!(
            tree_digest(&plan.dist_dir),
            before,
            "the locked previous export stays in place, byte for byte"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    /// `Path::starts_with` compares bytes, but NTFS matches
    /// case-insensitively: an `--out` spelled `C:\GAME` where the
    /// project lives in `c:\game` is the same directory to the OS and a
    /// different one to a byte-comparing guard — which would then
    /// clear the real project directory as its "staging" one. The guard
    /// must compare the way the filesystem does.
    #[cfg(windows)]
    #[test]
    fn a_case_variant_of_the_output_directory_cannot_bypass_the_guard() {
        let (root, binary) = staged_fixture("case-guard");
        let plan = plan_export(&root, "release", &binary, None);

        let variant = {
            let text = root.display().to_string();
            let (head, tail) = text.rsplit_once(['\\', '/']).expect("a parent directory");
            PathBuf::from(format!("{head}\\{}", tail.to_uppercase()))
        };
        let smuggled = ExportPlan {
            dist_dir: variant.clone(),
            ..plan.clone()
        };
        let error = stage_export(&smuggled).unwrap_err();
        assert!(
            error.to_string().contains("refusing to stage"),
            "{} was accepted: {error}",
            variant.display()
        );
        // The sources are untouched: the refusal came before anything else.
        assert!(
            root.join("assets/scene.bsn").is_file(),
            "the real assets survive"
        );
        assert!(binary.is_file(), "the build survives");
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

    /// A project whose `jackdaw.toml` names another asset folder — the
    /// one its own `AssetPlugin` reads — stages that tree, under that
    /// name: a hardcoded `assets` would export the wrong tree (or none)
    /// and stage it under a name the game never looks for.
    #[test]
    fn an_assets_dir_override_is_staged_under_its_own_name() {
        let (root, binary) = staged_fixture("assets-dir");
        std::fs::write(root.join("jackdaw.toml"), "assets_dir = \"content\"\n").unwrap();
        std::fs::create_dir_all(root.join("content")).unwrap();
        std::fs::write(root.join("content/scene.bsn"), b"scene").unwrap();
        std::fs::remove_dir_all(root.join("assets")).unwrap();

        let plan = plan_export(&root, "release", &binary, None);
        assert_eq!(plan.assets_source, root.join("content"));
        assert_eq!(plan.assets_staged_subdir, Path::new("content"));

        let report = stage_export(&plan).expect("the overridden folder stages");
        assert_eq!(report.assets_dir, plan.dist_dir.join("content"));
        assert!(plan.dist_dir.join("content/scene.bsn").is_file());
        assert!(
            !plan.dist_dir.join("assets").exists(),
            "no phantom assets copy"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    /// The editor's private artifacts never ship: scene save rotations
    /// (`*.bak`), atomic-write temp and corrupt leftovers, and the PIE
    /// temp directory with its unsaved scene content. The acceptance
    /// trio — `.bak`, `.jackdaw-pie/`, `*.tmp-` — counts one skipped
    /// entry each; the corrupt leftover is the fourth of the same list.
    #[test]
    fn editor_private_files_stay_out_of_the_export() {
        let (root, binary) = staged_fixture("filtered");
        std::fs::write(root.join("assets/scene.bsn.bak"), b"old scene").unwrap();
        std::fs::create_dir_all(root.join("assets/.jackdaw-pie")).unwrap();
        std::fs::write(root.join("assets/.jackdaw-pie/current.bsn"), b"unsaved").unwrap();
        std::fs::write(root.join("assets/scene.bsn.tmp-123"), b"temp").unwrap();
        std::fs::write(root.join("assets/scene.bsn.corrupt-7"), b"corrupt").unwrap();

        let plan = plan_export(&root, "release", &binary, None);
        let report = stage_export(&plan).expect("the export stages");

        assert_eq!(report.skipped, 4, ".bak + .jackdaw-pie + .tmp- + .corrupt-");
        assert!(!report.assets_dir.join("scene.bsn.bak").exists());
        assert!(!report.assets_dir.join(".jackdaw-pie").exists());
        assert!(!report.assets_dir.join("scene.bsn.tmp-123").exists());
        assert!(!report.assets_dir.join("scene.bsn.corrupt-7").exists());
        // The real assets are all there.
        assert!(report.assets_dir.join("scene.bsn").is_file());
        assert!(
            report
                .assets_dir
                .join("textures/tile/diffuse.png")
                .is_file()
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    /// The second gate on `--out`: a directory that holds something and
    /// carries no export marker is not ours to replace — a mistyped
    /// `--out` into a user directory must be refused, not deleted.
    /// Marked (a re-export elsewhere), empty (a first export into a new
    /// place), and forced are the three ways through.
    #[test]
    fn an_output_directory_that_is_not_ours_is_refused_until_forced() {
        let (root, binary) = staged_fixture("foreign-out");
        let plan = plan_export(&root, "release", &binary, None);

        // Refused: a non-empty directory with no marker.
        let out = root.join("elsewhere/dist");
        std::fs::create_dir_all(&out).unwrap();
        std::fs::write(out.join("important.txt"), b"do not delete").unwrap();
        let refused = ExportPlan {
            dist_dir: out.clone(),
            ..plan.clone()
        };
        let error = stage_export(&refused).unwrap_err();
        assert!(
            error
                .to_string()
                .contains("does not belong to a jackdaw export"),
            "got {error}"
        );
        assert!(
            error.to_string().contains("--force"),
            "the remedy is named: {error}"
        );
        assert_eq!(
            std::fs::read(out.join("important.txt")).unwrap(),
            b"do not delete",
            "the refused directory is untouched"
        );

        // Marked: a re-export into a place a previous export wrote.
        std::fs::write(out.join(EXPORT_MARKER), b"jackdaw export\n").unwrap();
        stage_export(&refused).expect("a marked directory is a previous export");
        assert!(out.join("my-game.exe").is_file());
        assert!(!out.join("important.txt").exists(), "a re-export replaces");

        // Empty: a first export into a new place.
        let fresh = root.join("elsewhere/fresh");
        std::fs::create_dir_all(&fresh).unwrap();
        stage_export(&ExportPlan {
            dist_dir: fresh.clone(),
            ..plan.clone()
        })
        .expect("an empty directory is fine to fill");
        assert!(fresh.join("my-game.exe").is_file());

        // Forced: explicit consent on the command line.
        let stubborn = root.join("elsewhere/stubborn");
        std::fs::create_dir_all(&stubborn).unwrap();
        std::fs::write(stubborn.join("anything.txt"), b"x").unwrap();
        stage_export(&ExportPlan {
            dist_dir: stubborn.clone(),
            force: true,
            ..plan.clone()
        })
        .expect("--force replaces a foreign directory");
        assert!(stubborn.join("my-game.exe").is_file());
        let _ = std::fs::remove_dir_all(&root);
    }

    /// Leftovers of interrupted exports — a staging directory that was
    /// never swapped in, a trash directory that could not be deleted —
    /// are cleaned by the next export of the same profile. Another
    /// profile's siblings are not this export's to remove.
    ///
    /// The trash deletion failure itself can no longer be injected on
    /// Windows: any open handle in the previous export also blocks the
    /// rename that moves it aside (probed both with and without
    /// FILE_SHARE_DELETE), and a read-only file no longer stops
    /// `remove_dir_all`. The warn-and-leave-it branch in the swap is
    /// defensive; this test pins its user-visible half — a leftover
    /// trash directory never outlives the next export.
    #[test]
    fn staging_and_trash_leftovers_are_cleaned_on_the_next_export() {
        let (root, binary) = staged_fixture("orphans");
        let plan = plan_export(&root, "release", &binary, None);
        let parent = plan.dist_dir.parent().unwrap();
        std::fs::create_dir_all(parent).unwrap();
        std::fs::create_dir_all(parent.join(".release.staging-999")).unwrap();
        std::fs::write(parent.join(".release.staging-999/junk"), b"junk").unwrap();
        std::fs::create_dir_all(parent.join(".release.trash-old")).unwrap();
        std::fs::create_dir_all(parent.join(".dev.staging-1")).unwrap();

        stage_export(&plan).expect("the export stages");

        assert!(
            !parent.join(".release.staging-999").exists(),
            "the staging orphan goes"
        );
        assert!(
            !parent.join(".release.trash-old").exists(),
            "the trash orphan goes"
        );
        assert!(
            parent.join(".dev.staging-1").exists(),
            "another profile's leftovers stay"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    /// A successful export leaves nothing behind: no staging sibling
    /// (it became the output), no trash sibling (it was deleted after
    /// the swap).
    #[test]
    fn a_successful_export_leaves_no_staging_or_trash_behind() {
        let (root, binary) = staged_fixture("clean-swap");
        let plan = plan_export(&root, "release", &binary, None);
        stage_export(&plan).expect("first export");
        stage_export(&plan).expect("second export replaces the first");
        let parent = plan.dist_dir.parent().unwrap();
        for entry in std::fs::read_dir(parent).unwrap() {
            let name = entry.unwrap().file_name().to_string_lossy().to_string();
            assert!(
                !name.starts_with(".release.staging-") && !name.starts_with(".release.trash-"),
                "the export left {name} behind"
            );
        }
        let _ = std::fs::remove_dir_all(&root);
    }

    /// The same input exports to the same output: two consecutive
    /// exports stage byte-identical trees (the marker, which carries
    /// the export time, is the one thing allowed to differ).
    #[test]
    fn repeated_exports_stage_identical_content() {
        let (root, binary) = staged_fixture("idempotent-content");
        let plan = plan_export(&root, "release", &binary, None);
        stage_export(&plan).expect("first export");
        let first = tree_digest(&plan.dist_dir);
        stage_export(&plan).expect("second export");
        assert_eq!(
            tree_digest(&plan.dist_dir),
            first,
            "a re-export with the same input stages the same content"
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    /// The marker names what wrote the directory: the jackdaw version,
    /// the profile, and when. Its presence — checked before any of its
    /// content — is what the output gate trusts.
    #[test]
    fn the_export_marker_names_the_version_and_profile() {
        let (root, binary) = staged_fixture("marker");
        let plan = plan_export(&root, "release", &binary, None);
        let report = stage_export(&plan).expect("the export stages");
        let marker = std::fs::read_to_string(report.dist_dir.join(EXPORT_MARKER)).unwrap();
        assert!(marker.contains(crate::VERSION), "{marker}");
        assert!(marker.contains("release"), "{marker}");
        assert!(marker.contains("at "), "{marker}");
        let _ = std::fs::remove_dir_all(&root);
    }

    /// The Windows containment comparison in isolation: same path in a
    /// different case, a path and itself, a genuinely different path,
    /// the reverse direction, and a cross-drive near-miss.
    #[cfg(windows)]
    #[test]
    fn path_containment_matches_the_filesystems_case_rules() {
        assert!(path_contains(
            Path::new(r"C:\Game"),
            Path::new(r"c:\GAME\assets")
        ));
        assert!(path_contains(Path::new(r"c:\game"), Path::new(r"C:\Game")));
        assert!(!path_contains(
            Path::new(r"C:\Other"),
            Path::new(r"c:\game\assets")
        ));
        assert!(!path_contains(
            Path::new(r"C:\Game\assets"),
            Path::new(r"C:\Game")
        ));
        assert!(!path_contains(
            Path::new(r"H:\Game"),
            Path::new(r"C:\Game\assets")
        ));
    }
}
