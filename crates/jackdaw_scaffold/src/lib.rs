//! Project scaffolding and side-effect-free import planning.
//!
//! Both flows produce the same contract: a normal Bevy crate with a
//! `[lib]` target, a `jackdaw.toml`, and a gitignored `.jackdaw/`
//! directory the editor owns. New projects come from templates
//! embedded in this binary (instantiated by string substitution,
//! offline). Imports are always planned before they are applied; the
//! plan is the single interface shared by `jd import` and the launcher.

use std::path::{Path, PathBuf};
use std::process::ExitCode;

use include_dir::{Dir, include_dir};
use jackdaw_project_build::modules::{GameDependencies, ModuleCatalog, ModuleSet};
use jackdaw_project_build::runtime_wiring::{
    PIE_FEATURE, RUNTIME_CRATE, RuntimeDependency, RuntimeWiring,
};
use path_slash::PathExt as _;
use toml_edit::DocumentMut;

pub mod dev_checkout;
pub mod migrate;

/// The one Bevy minor this editor release supports.
const SUPPORTED_BEVY_MINOR: &str = jackdaw_project_build::BEVY_VERSION;

static GAME_TEMPLATE: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/templates/game");
static EXTENSION_TEMPLATE: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/templates/extension");

/// Which embedded template a new project starts from.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum TemplateKind {
    Game,
    Extension,
}

impl TemplateKind {
    fn dir(self) -> &'static Dir<'static> {
        match self {
            Self::Game => &GAME_TEMPLATE,
            Self::Extension => &EXTENSION_TEMPLATE,
        }
    }
}

/// What scaffolding or import changed (or left in place).
pub struct ScaffoldReport {
    pub actions: Vec<String>,
    /// A `src/lib.rs` stub was created because the project had no
    /// library target; the user must move their game code into its
    /// `GamePlugin` for their systems to run.
    pub created_lib_stub: bool,
}

/// One exact filesystem effect in an [`ImportPlan`].
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ImportChange {
    CreateDirectory {
        path: PathBuf,
    },
    WriteFile {
        path: PathBuf,
        contents: String,
        replace: bool,
    },
}

impl ImportChange {
    pub fn summary(&self) -> String {
        match self {
            Self::CreateDirectory { path } => format!("create directory {}", path.display()),
            // `replace` is the plan's intent; check the disk so the
            // preview never promises to modify a file that is not
            // there, or to create one that is.
            Self::WriteFile { path, .. } if path.is_file() => {
                format!("modify {}", path.display())
            }
            Self::WriteFile { path, .. } => format!("create {}", path.display()),
        }
    }
}

/// A complete import proposal. Constructing it never changes the project.
#[derive(Clone, Debug)]
pub struct ImportPlan {
    /// The directory the user opened, and where `jackdaw.toml` lands.
    pub root: PathBuf,
    /// The package the editor will build. Differs from `root` when the
    /// opened directory is a workspace.
    pub package_dir: PathBuf,
    pub package_name: String,
    pub changes: Vec<ImportChange>,
    pub notes: Vec<String>,
    pub migrated_bin_target: bool,
    /// The modules the game's dependencies already show it using.
    pub detected_modules: ModuleSet,
    /// The modules the project uses once the plan is applied.
    pub modules: ModuleSet,
}

impl ImportPlan {
    pub fn is_empty(&self) -> bool {
        self.changes.is_empty()
    }
}

/// Why scaffolding could not complete.
#[derive(Debug)]
pub enum ScaffoldError {
    NoManifest(PathBuf),
    ManifestParse(String),
    /// No package could be resolved from the opened directory.
    Package(jackdaw_project_build::cargo_meta::ResolveError),
    /// An operation that assumes an integrated project ran on one that
    /// has not been set up yet.
    NotSetUp(PathBuf),
    /// `jackdaw.toml` exists but does not parse, so the project's
    /// plugin, package, and pins are all unreadable.
    SettingsParse {
        path: PathBuf,
        detail: String,
    },
    /// The project's Bevy dependency does not match the supported minor.
    BevyVersion {
        found: String,
    },
    /// The requested name does not produce a usable Rust crate name.
    ProjectName {
        raw: String,
        reason: &'static str,
    },
    Io(String),
}

impl std::fmt::Display for ScaffoldError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ScaffoldError::NoManifest(p) => {
                write!(
                    f,
                    "no Cargo.toml at {} (open the folder that holds your project's Cargo.toml)",
                    p.display()
                )
            }
            ScaffoldError::ManifestParse(e) => write!(f, "could not parse Cargo.toml: {e}"),
            ScaffoldError::Package(e) => write!(f, "{e}"),
            ScaffoldError::NotSetUp(path) => write!(
                f,
                "{} is not set up for jackdaw yet (no jackdaw.toml); run `jd import --apply {}` \
                 first",
                path.display(),
                path.display()
            ),
            ScaffoldError::SettingsParse { path, detail } => write!(
                f,
                "{} does not parse: {detail}. Fix it (or delete it and re-import) so jackdaw can \
                 read this project's plugin, package, and versions.",
                path.display()
            ),
            // Jackdaw's version is anchored to the Bevy minor it
            // targets, so the release a mismatched project needs is
            // mechanical: say which one instead of leaving the user to
            // work out the mapping.
            ScaffoldError::BevyVersion { found } => {
                writeln!(
                    f,
                    "this jackdaw targets Bevy {SUPPORTED_BEVY_MINOR}, and the project depends \
                     on bevy {found}. The editor and your game code have to share one Bevy."
                )?;
                // Only suggest a release that could exist: a bogus
                // requirement like `0.190` has no jackdaw to install.
                match bevy_minor_of(found) {
                    Some(minor) => writeln!(
                        f,
                        "Either install jackdaw {minor}.x (releases track the Bevy minor: \
                         https://github.com/jbuehler23/jackdaw/releases), or update the project \
                         to Bevy {SUPPORTED_BEVY_MINOR} and import again."
                    )?,
                    None => writeln!(
                        f,
                        "Update the project to Bevy {SUPPORTED_BEVY_MINOR} and import again."
                    )?,
                }
                write!(
                    f,
                    "To set up anyway and deal with it later, pass --allow-bevy-mismatch."
                )
            }
            ScaffoldError::ProjectName { raw, reason } => {
                write!(f, "`{raw}` is not a usable project name: {reason}")
            }
            ScaffoldError::Io(e) => write!(f, "{e}"),
        }
    }
}

/// CLI entry point for `jd new <name> [--extension]`.
#[expect(
    clippy::print_stdout,
    clippy::print_stderr,
    reason = "CLI subcommand writes its results and errors to the terminal"
)]
pub fn run_new_cli(args: &[String]) -> ExitCode {
    let kind = if args.iter().any(|a| a == "--extension") {
        TemplateKind::Extension
    } else {
        TemplateKind::Game
    };
    let Some(raw_name) = first_positional(args, &["--path", "--modules"]) else {
        eprintln!(
            "jd new: usage: jd new <name> [--extension] [--path <dir>] [--no-git] \
             [--modules <list> | --no-modules]"
        );
        return ExitCode::FAILURE;
    };
    let modules = match modules_arg(args) {
        Ok(None) => ModuleCatalog::builtin().defaults(),
        Ok(Some(_)) if kind == TemplateKind::Extension => {
            eprintln!("jd new: modules apply to games; an extension project has none");
            return ExitCode::FAILURE;
        }
        Ok(Some(modules)) => modules,
        Err(error) => {
            eprintln!("jd new: {error}");
            return ExitCode::FAILURE;
        }
    };
    let project_name = match validated_project_name(raw_name) {
        Ok(name) => name,
        Err(e) => {
            eprintln!("jd new: {e}");
            return ExitCode::FAILURE;
        }
    };
    let location = match flag_value(args, "--path") {
        Some(path) => PathBuf::from(path),
        None => match std::env::current_dir() {
            Ok(d) => d,
            Err(e) => {
                eprintln!("jd new: {e}");
                return ExitCode::FAILURE;
            }
        },
    };
    if !location.is_dir() {
        eprintln!("jd new: {} is not a directory", location.display());
        return ExitCode::FAILURE;
    }
    let dest = location.join(&project_name);
    match scaffold_new_project_with(&dest, &project_name, kind, &modules) {
        Ok(report) => {
            println!("jd new: created {}", dest.display());
            if kind == TemplateKind::Game {
                println!("  modules: {}", describe_modules(&modules));
            }
            for a in &report.actions {
                println!("  {a}");
            }
            if !args.iter().any(|a| a == "--no-git") {
                init_git_repository(&dest);
            }
            // Announce it: on a cold registry the resolve updates the
            // index, which is slow enough to look like a hang.
            println!("  checking dependencies resolve...");
            let warnings = check_new_project(&dest);
            // The dev-checkout rewrite logs through `warn!`, which the
            // CLI has no subscriber for, so without this the user ships
            // a manifest full of absolute local paths and only finds
            // out from a collaborator's failing build.
            if let Some(checkout) = crate::dev_checkout::jackdaw_dev_checkout() {
                println!(
                    "\nnote: this jackdaw runs from the checkout at {}, so the new project \
                     depends on its crates by path. That Cargo.toml is local to this machine; \
                     switch those back to versions before sharing it.",
                    checkout.display()
                );
            }
            for warning in &warnings {
                eprintln!("\nwarning: {warning}");
            }
            match kind {
                // An extension is a library: there is nothing to run.
                // It loads into the editor when its project is open.
                TemplateKind::Extension => println!(
                    "\nNext:\n  jd open {}\nThe extension loads into the editor when that \
                     project is open; `jd build` recompiles it.",
                    dest.display()
                ),
                TemplateKind::Game => println!(
                    "\nNext:\n  jd open {}\nor `cargo run` in that directory to play standalone.",
                    dest.display()
                ),
            }
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("jd new: {e}");
            ExitCode::FAILURE
        }
    }
}

/// A problem with a freshly created project that its first build would
/// otherwise be the first to report.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NewProjectWarning {
    /// The project sits inside a cargo workspace that no longer resolves.
    EnclosingWorkspaceBroken {
        /// The new project's directory.
        project: PathBuf,
        /// The root of the enclosing workspace.
        workspace: PathBuf,
        /// Cargo's first error line for the workspace.
        detail: String,
    },
    /// The project's own dependencies do not resolve.
    DependenciesUnresolved {
        /// The new project's directory.
        project: PathBuf,
        /// Where this editor's jackdaw crates come from, as a phrase.
        source: String,
        /// Cargo's first error line for the project.
        detail: String,
    },
}

impl NewProjectWarning {
    /// One line naming the problem.
    pub fn summary(&self) -> String {
        match self {
            Self::EnclosingWorkspaceBroken { workspace, .. } => format!(
                "This folder is inside another cargo workspace ({})",
                workspace.display()
            ),
            Self::DependenciesUnresolved { source, .. } => {
                format!("The jackdaw crates could not be resolved from {source}")
            }
        }
    }

    /// One line saying what to do about it.
    pub fn fix(&self) -> String {
        match self {
            Self::EnclosingWorkspaceBroken {
                project, workspace, ..
            } => format!(
                "Add exclude = [\"{}\"] to {}, or remove [workspace] from the new project's \
                 Cargo.toml to make it a member",
                exclude_entry(project, workspace),
                workspace.join("Cargo.toml").display()
            ),
            Self::DependenciesUnresolved { project, .. } => format!(
                "Once that source is reachable, run jd doctor --project {} to check again",
                project.display()
            ),
        }
    }

    /// Cargo's own error line.
    pub fn cargo_error(&self) -> &str {
        match self {
            Self::EnclosingWorkspaceBroken { detail, .. }
            | Self::DependenciesUnresolved { detail, .. } => detail,
        }
    }
}

/// Where a project scaffolded by this editor fetches the jackdaw crates
/// from: the checkout it runs from when the scaffold was rewritten to path
/// dependencies on it, otherwise the source this build was made from.
fn jackdaw_source_description() -> String {
    match crate::dev_checkout::jackdaw_dev_checkout() {
        Some(checkout) => format!("the checkout at {}", checkout.display()),
        None => jackdaw_project_build::build_source::build_source().describe(),
    }
}

/// The project's path relative to the workspace root, as written in that
/// workspace's `exclude` list.
fn exclude_entry(project: &Path, workspace: &Path) -> String {
    project
        .strip_prefix(workspace)
        .unwrap_or(project)
        .to_slash_lossy()
        .into_owned()
}

impl std::fmt::Display for NewProjectWarning {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::EnclosingWorkspaceBroken {
                project,
                workspace,
                detail,
            } => write!(
                f,
                "`{}` is inside the cargo workspace at {}, which now reports:\n  {detail}\n\
                 The new project declares its own `[workspace]` so it builds standalone. To \
                 keep the outer workspace working too, either add this line to {}:\n  \
                 exclude = [\"{}\"]\n\
                 or delete the `[workspace]` table from the new project's Cargo.toml to make \
                 it a member.",
                project
                    .file_name()
                    .unwrap_or(project.as_os_str())
                    .to_string_lossy(),
                workspace.display(),
                workspace.join("Cargo.toml").display(),
                exclude_entry(project, workspace),
            ),
            Self::DependenciesUnresolved {
                project,
                source,
                detail,
            } => write!(
                f,
                "this project's dependencies do not resolve yet:\n  {detail}\n\
                 The jackdaw crates could not be resolved from {source}. Run \
                 `jd doctor --project {}` once that source is reachable.",
                project.display()
            ),
        }
    }
}

/// Check a freshly scaffolded project at `dest` for problems its first
/// build would hit. Runs cargo's resolver, which updates the registry
/// index first on a cold cache, so call it off the UI thread.
pub fn check_new_project(dest: &Path) -> Vec<NewProjectWarning> {
    check_new_project_with(
        dest,
        jackdaw_project_build::cargo_meta::resolve_dependencies,
    )
}

/// [`check_new_project`] with the resolver supplied by the caller.
fn check_new_project_with(
    dest: &Path,
    resolves: impl Fn(&Path) -> Result<(), String>,
) -> Vec<NewProjectWarning> {
    let mut warnings = Vec::new();
    // Creating a project inside an existing repo is normal, and a
    // workspace whose `members` is a glob will adopt it. The scaffold's
    // own `[workspace]` then makes two roots, which breaks every cargo
    // command in the PARENT: a directory the user did not ask us to touch.
    if let Some(workspace) = enclosing_workspace(dest)
        && let Err(detail) = resolves(&workspace)
    {
        warnings.push(NewProjectWarning::EnclosingWorkspaceBroken {
            project: dest.to_path_buf(),
            workspace,
            detail,
        });
    }
    // A version that is not on the index yet would otherwise surface as
    // a baffling failure at the first build, with nothing connecting it
    // to the tool that wrote the file.
    if let Err(detail) = resolves(dest) {
        warnings.push(NewProjectWarning::DependenciesUnresolved {
            project: dest.to_path_buf(),
            source: jackdaw_source_description(),
            detail,
        });
    }
    warnings
}

/// The nearest ancestor directory whose `Cargo.toml` declares a
/// `[workspace]`, if any.
fn enclosing_workspace(dest: &Path) -> Option<PathBuf> {
    let mut candidate = dest.parent()?;
    loop {
        let manifest = candidate.join("Cargo.toml");
        if std::fs::read_to_string(&manifest).is_ok_and(|text| {
            text.parse::<DocumentMut>()
                .is_ok_and(|doc| doc.contains_key("workspace"))
        }) {
            return Some(candidate.to_path_buf());
        }
        candidate = candidate.parent()?;
    }
}

/// The first bare argument, skipping flags and the values belonging to
/// the `value_flags` that take one.
fn first_positional<'a>(args: &'a [String], value_flags: &[&str]) -> Option<&'a String> {
    let mut skip_next = false;
    for arg in args {
        if skip_next {
            skip_next = false;
            continue;
        }
        if value_flags.contains(&arg.as_str()) {
            skip_next = true;
            continue;
        }
        if !arg.starts_with('-') {
            return Some(arg);
        }
    }
    None
}

/// The modules `--modules <list>` or `--no-modules` ask for, or `None`
/// when neither is given.
fn modules_arg(args: &[String]) -> Result<Option<ModuleSet>, String> {
    let none = args.iter().any(|arg| arg == "--no-modules");
    match (flag_value(args, "--modules"), none) {
        (Some(_), true) => Err("pass --modules or --no-modules, not both".to_string()),
        (Some(list), false) => {
            let catalog = ModuleCatalog::builtin();
            catalog
                .parse_list(&list)
                .and_then(|set| catalog.available(set))
                .map(Some)
        }
        (None, true) => Ok(Some(ModuleSet::new())),
        (None, false) => Ok(None),
    }
}

/// The names of `modules` for a summary line, or `none`.
fn describe_modules(modules: &ModuleSet) -> String {
    if modules.is_empty() {
        return "none".to_string();
    }
    ModuleCatalog::builtin().names(&modules.iter().cloned().collect::<Vec<_>>())
}

/// The value following `flag` in `args`, or the `--flag=value` form.
fn flag_value(args: &[String], flag: &str) -> Option<String> {
    let mut it = args.iter();
    while let Some(arg) = it.next() {
        if arg == flag {
            return it.next().cloned();
        }
        if let Some(value) = arg.strip_prefix(&format!("{flag}=")) {
            return Some(value.to_string());
        }
    }
    None
}

/// `git init` a freshly scaffolded project, matching what `cargo new`
/// does. Skipped when the destination already sits inside a repository
/// (so scaffolding into an existing checkout does not nest one) and
/// when git is unavailable. Best effort: a failure is not worth
/// aborting a successful scaffold over.
pub fn init_git_repository(dest: &Path) {
    let inside_repo = jackdaw_env::without_console_window(&mut std::process::Command::new("git"))
        .args(["rev-parse", "--is-inside-work-tree"])
        .current_dir(dest)
        .output()
        .is_ok_and(|out| out.status.success() && out.stdout.starts_with(b"true"));
    if inside_repo {
        return;
    }
    let _ = jackdaw_env::without_console_window(&mut std::process::Command::new("git"))
        .arg("init")
        .arg("--quiet")
        .current_dir(dest)
        .status();
}

/// CLI entry point for `jd import [path] [--plugin <Type>] [--apply]`.
#[expect(
    clippy::print_stdout,
    clippy::print_stderr,
    reason = "CLI subcommand writes its results and errors to the terminal"
)]
pub fn run_import_cli(args: &[String]) -> ExitCode {
    let plugin = parse_plugin_arg(args);
    let package = flag_value(args, "--package");
    let requested_root =
        first_positional(args, &["--plugin", "--package", "--modules"]).map(PathBuf::from);
    let modules = match modules_arg(args) {
        Ok(modules) => modules,
        Err(error) => {
            eprintln!("jd import: {error}");
            return ExitCode::FAILURE;
        }
    };
    let root = match requested_root
        .map(Ok)
        .unwrap_or_else(std::env::current_dir)
        .and_then(dunce::canonicalize)
    {
        Ok(d) => d,
        Err(e) => {
            eprintln!("jd import: {e}");
            return ExitCode::FAILURE;
        }
    };
    let allow_mismatch = args.iter().any(|arg| arg == "--allow-bevy-mismatch");
    match plan_import_with_modules(
        &root,
        plugin,
        package.as_deref(),
        allow_mismatch,
        modules.as_ref(),
    ) {
        Ok(plan) if plan.is_empty() => {
            println!("jd import: {} is already set up", root.display());
            if !RuntimeWiring::inspect(&plan.package_dir).complete() {
                for note in &plan.notes {
                    println!("  note: {note}");
                }
            }
            println!("\nNext: `jd open {}`", root.display());
            ExitCode::SUCCESS
        }
        Ok(plan) => {
            println!("jd import preview: {}", root.display());
            if plan.package_dir != plan.root {
                println!("  package: {}", plan.package_name);
            }
            println!("  modules: {}", describe_modules(&plan.modules));
            for change in &plan.changes {
                println!("  {}", change.summary());
            }
            for note in &plan.notes {
                println!("  note: {note}");
            }
            if !args.iter().any(|arg| arg == "--apply") {
                println!(
                    "\nNo files changed. Run `jd import --apply {}` to apply.",
                    root.display()
                );
                return ExitCode::SUCCESS;
            }
            match apply_import_plan(&plan) {
                Ok(report) => {
                    println!("\nApplied {} change(s).", report.actions.len());
                    if report.created_lib_stub {
                        println!(
                            "\nYour project had no library target, so a `GamePlugin` stub was \
                             created in src/lib.rs. Move your game setup there from main.rs; the \
                             editor only sees components that live in the library."
                        );
                    }
                    println!("\nNext: `jd open {}`", root.display());
                    ExitCode::SUCCESS
                }
                Err(e) => {
                    eprintln!("jd import: {e}");
                    ExitCode::FAILURE
                }
            }
        }
        Err(e) => {
            eprintln!("jd import: {e}");
            ExitCode::FAILURE
        }
    }
}

/// Plan the edits that bring a project up to this jackdaw: refresh the
/// `[jackdaw]` pins, and bump any `jackdaw_*` requirement to the
/// anchored minor.
///
/// Side-effect free, like the import plan: the changes are previewed,
/// then applied on a second explicit action.
pub fn plan_upgrade_project(root: &Path) -> Result<ImportPlan, ScaffoldError> {
    let manifest_path = root.join("Cargo.toml");
    if !manifest_path.is_file() {
        return Err(ScaffoldError::NoManifest(manifest_path));
    }
    // Upgrading is for projects that are already set up. Writing a
    // pins-only `jackdaw.toml` here would leave a project with no
    // plugin, no run config, and no `.jackdaw/`, while making it look
    // set up to every later check, which permanently skips the import
    // flow that would have completed it.
    if !jackdaw_project_build::project_manifest::ProjectManifest::exists(root) {
        return Err(ScaffoldError::NotSetUp(root.to_path_buf()));
    }
    let settings = jackdaw_project_build::project_manifest::ProjectManifest::read_checked(root)
        .map_err(|detail| ScaffoldError::SettingsParse {
            path: jackdaw_project_build::project_manifest::path(root),
            detail,
        })?;
    let package = jackdaw_project_build::cargo_meta::resolve_project_package(
        root,
        settings.package.as_deref(),
    )
    .map_err(ScaffoldError::Package)?;

    let mut changes = Vec::new();
    let mut notes = Vec::new();

    // What the project's own manifest says it targets, which is what
    // the pins have to describe. An upgrade moves the jackdaw version;
    // it does not migrate anyone's Bevy for them.
    let project_bevy = jackdaw_project_build::project_manifest::targeted_bevy_from_manifest(root);
    if project_bevy
        .as_deref()
        .is_some_and(|minor| minor != jackdaw_project_build::BEVY_VERSION)
    {
        notes.push(format!(
            "this project targets bevy {}, not {}; upgrading records the jackdaw version but \
             leaves that mismatch in place",
            project_bevy.as_deref().unwrap_or_default(),
            jackdaw_project_build::BEVY_VERSION
        ));
    }

    // The bevy pin as recorded before the rewrite, so the preview can
    // name that change too. A note saying only "records jackdaw 0.19.0"
    // while silently moving the bevy pin describes half of what it does.
    let recorded_bevy = settings.jackdaw.bevy.clone();

    let modules = settings.modules(root);
    let settings_path = jackdaw_project_build::project_manifest::path(root);
    let settings = std::fs::read_to_string(&settings_path).unwrap_or_default();
    let mut new_settings = settings.clone();
    if let Some(updated) = rewrite_pins(&settings, project_bevy.as_deref()) {
        new_settings = updated;
        let recorded_bevy = recorded_bevy.as_deref().unwrap_or("none");
        let new_bevy = project_bevy
            .as_deref()
            .unwrap_or(jackdaw_project_build::BEVY_VERSION);
        if recorded_bevy == new_bevy {
            notes.push(format!(
                "records jackdaw {}",
                jackdaw_project_build::VERSION
            ));
        } else {
            notes.push(format!(
                "records jackdaw {}, and corrects the bevy pin {recorded_bevy} -> {new_bevy} to \
                 match this project's Cargo.toml",
                jackdaw_project_build::VERSION
            ));
        }
    }

    // Both manifests can carry jackdaw requirements: the member's own,
    // and the workspace root's `[workspace.dependencies]` that members
    // inherit with `{ workspace = true }`. Missing the root misses the
    // more common workspace idiom entirely.
    // Only when the project is on this editor's Bevy. Moving
    // `jackdaw_runtime` to a version that requires Bevy 0.19 inside a
    // project pinned to an older Bevy produces a manifest that cannot
    // resolve, which is worse than leaving it alone.
    let bump = project_bevy
        .as_deref()
        .is_none_or(|minor| minor == jackdaw_project_build::BEVY_VERSION);
    if !bump {
        notes.push(
            "leaving the jackdaw dependencies alone: moving them forward would require a bevy \
             this project does not use"
                .to_string(),
        );
    }
    let mut manifests = vec![package.dir.join("Cargo.toml")];
    if package.dir != root {
        manifests.push(root.join("Cargo.toml"));
    }
    let requirement = jackdaw_project_build::jackdaw_requirement();
    let mut bumped_any = false;
    let mut dropped = Vec::new();
    for manifest_path in manifests {
        let cargo = std::fs::read_to_string(&manifest_path)
            .map_err(|e| ScaffoldError::Io(format!("{}: {e}", manifest_path.display())))?;
        let mut updated = cargo.clone();
        if bump && let Some(bumped) = bump_jackdaw_requirements(&updated, &requirement) {
            updated = bumped;
            bumped_any = true;
        }
        if let Ok(mut doc) = updated.parse::<DocumentMut>() {
            let removed = drop_removed_runtime_features(&mut doc);
            if !removed.is_empty() {
                updated = doc.to_string();
                dropped.extend(removed);
            }
        }
        if updated != cargo {
            changes.push(ImportChange::WriteFile {
                path: manifest_path,
                contents: updated,
                replace: true,
            });
        }
    }
    if bumped_any {
        notes.push(format!("requests the jackdaw crates at {requirement}"));
    }
    dropped.sort();
    dropped.dedup();
    if !dropped.is_empty() {
        let catalog = ModuleCatalog::builtin();
        let mut target = modules;
        target.extend(
            dropped
                .iter()
                .filter_map(|feature| catalog.replacing_feature(feature))
                .map(|module| module.id.clone()),
        );
        let target = catalog.complete(target);
        new_settings = jackdaw_project_build::modules::with_modules(&new_settings, &target)
            .map_err(|detail| ScaffoldError::SettingsParse {
                path: settings_path.clone(),
                detail,
            })?;
        notes.extend(removed_feature_notes(&dropped));
    }
    if new_settings != settings {
        changes.push(ImportChange::WriteFile {
            path: settings_path,
            contents: new_settings,
            replace: true,
        });
    }

    Ok(ImportPlan {
        root: root.to_path_buf(),
        package_dir: package.dir,
        package_name: package.name,
        changes,
        notes,
        migrated_bin_target: false,
        detected_modules: ModuleSet::new(),
        modules: ModuleSet::new(),
    })
}

/// Bring the `[jackdaw]` pins up to this build. `None` when they are
/// already current.
///
/// `bevy` is only advanced when the project's own manifest actually
/// targets this Bevy minor. Writing it unconditionally would mark a
/// mismatched project healthy without changing anything about it,
/// undoing the very flag `--allow-bevy-mismatch` records so the user
/// can deal with it later.
fn rewrite_pins(settings: &str, project_bevy: Option<&str>) -> Option<String> {
    let mut doc: DocumentMut = settings.parse().ok()?;
    let get = |key: &str| {
        doc.get("jackdaw")
            .and_then(|table| table.get(key))
            .and_then(|value| value.as_str())
            .map(str::to_string)
    };
    let bevy = match project_bevy {
        Some(minor) => minor.to_string(),
        // Nothing conclusive in the manifest: keep whatever the project
        // already recorded rather than asserting this editor's.
        None => get("bevy").unwrap_or_else(|| jackdaw_project_build::BEVY_VERSION.to_string()),
    };
    // Edit the existing table in place where there is one, so its
    // position in the file, and any other keys or comments inside it,
    // survive. Replacing the item wholesale moves it to the end and
    // drops anything the user put there.
    let pins: DocumentMut = jackdaw_project_build::project_manifest::pins_toml_for_bevy(&bevy)
        .parse()
        .ok()?;
    let current = pins["jackdaw"]
        .as_table()?
        .iter()
        .filter(|(key, _)| *key != "channel")
        .all(|(key, value)| get(key).as_deref() == value.as_str());
    if current {
        return None;
    }
    match doc
        .get_mut("jackdaw")
        .and_then(|item| item.as_table_like_mut())
    {
        Some(existing) => {
            // Assign through the existing item rather than `insert`:
            // `insert` replaces the whole key-value entry, taking any
            // comment the user wrote above the key with it.
            let mut set = |key: &str, text: &str| match existing.get_mut(key) {
                Some(item) => *item = toml_edit::value(text),
                None => {
                    existing.insert(key, toml_edit::value(text));
                }
            };
            for (key, value) in pins["jackdaw"]
                .as_table()
                .into_iter()
                .flat_map(|table| table.iter())
            {
                if let Some(text) = value.as_str() {
                    set(key, text);
                }
            }
        }
        None => doc["jackdaw"] = pins["jackdaw"].clone(),
    }
    Some(doc.to_string())
}

/// Point every `jackdaw_*` dependency at `requirement`. `None` when
/// nothing needed changing (already current, or path/git deps, which
/// state no version to bump).
fn bump_jackdaw_requirements(cargo: &str, requirement: &str) -> Option<String> {
    const TABLES: [&str; 3] = ["dependencies", "dev-dependencies", "build-dependencies"];
    let mut doc: DocumentMut = cargo.parse().ok()?;
    let mut changed = false;

    for table in TABLES {
        if let Some(deps) = doc.get_mut(table).and_then(|item| item.as_table_like_mut()) {
            changed |= bump_jackdaw_deps(deps, requirement);
        }
    }
    // A platform-gated jackdaw dependency is still a jackdaw
    // dependency; leaving it behind contradicts what the upgrade says
    // it did.
    if let Some(targets) = doc
        .get_mut("target")
        .and_then(|item| item.as_table_like_mut())
    {
        for (_, cfg) in targets.iter_mut() {
            let Some(cfg) = cfg.as_table_like_mut() else {
                continue;
            };
            for table in TABLES {
                if let Some(deps) = cfg.get_mut(table).and_then(|item| item.as_table_like_mut()) {
                    changed |= bump_jackdaw_deps(deps, requirement);
                }
            }
        }
    }
    // `[workspace.dependencies]`, which members inherit with
    // `{ workspace = true }`. In a workspace this is usually the only
    // place a version is written down at all.
    if let Some(workspace) = doc
        .get_mut("workspace")
        .and_then(|item| item.as_table_like_mut())
        && let Some(deps) = workspace
            .get_mut("dependencies")
            .and_then(|item| item.as_table_like_mut())
    {
        changed |= bump_jackdaw_deps(deps, requirement);
    }
    changed.then(|| doc.to_string())
}

/// Move every `jackdaw_*` entry in one dependency table to
/// `requirement`. Returns whether anything changed.
fn bump_jackdaw_deps(deps: &mut dyn toml_edit::TableLike, requirement: &str) -> bool {
    let mut changed = false;
    let names: Vec<String> = deps
        .iter()
        .map(|(name, _)| name.to_string())
        .filter(|name| name.starts_with("jackdaw_"))
        .collect();
    for name in names {
        let Some(entry) = deps.get_mut(&name) else {
            continue;
        };
        if let Some(existing) = entry.as_str() {
            if existing != requirement {
                *entry = toml_edit::value(requirement);
                changed = true;
            }
        } else if let Some(table) = entry.as_table_like_mut() {
            // A path or git dependency resolves elsewhere; there is no
            // version requirement to bring forward. A git dependency on this
            // build's own repository moves to the revision it was built at.
            if table.get("git").is_some()
                && let jackdaw_project_build::build_source::BuildSource::Git { repository, rev } =
                    jackdaw_project_build::build_source::build_source()
                && table.get("git").and_then(|git| git.as_str()) == Some(repository.as_str())
                && table
                    .get("rev")
                    .and_then(|pinned| pinned.as_str())
                    .is_some_and(|pinned| pinned != rev)
            {
                table.insert("rev", toml_edit::value(rev));
                changed = true;
                continue;
            }
            if table.get("path").is_some() || table.get("git").is_some() {
                continue;
            }
            let current = table.get("version").and_then(|v| v.as_str());
            if current.is_some() && current != Some(requirement) {
                table.insert("version", toml_edit::value(requirement));
                changed = true;
            }
        }
    }
    changed
}

/// CLI entry point for `jd upgrade [path] [--apply]`.
#[expect(
    clippy::print_stdout,
    clippy::print_stderr,
    reason = "CLI subcommand writes its results and errors to the terminal"
)]
pub fn run_upgrade_cli(args: &[String]) -> ExitCode {
    let requested = first_positional(args, &[]).map(PathBuf::from);
    let root = match requested
        .clone()
        .map(Ok)
        .unwrap_or_else(std::env::current_dir)
        .and_then(dunce::canonicalize)
    {
        Ok(root) => root,
        Err(error) => {
            match requested {
                Some(path) => eprintln!("jd upgrade: {}: {error}", path.display()),
                None => eprintln!("jd upgrade: {error}"),
            }
            return ExitCode::FAILURE;
        }
    };
    match plan_upgrade_project(&root) {
        Ok(plan) if plan.is_empty() => {
            println!(
                "jd upgrade: {} is already on jackdaw {}",
                root.display(),
                jackdaw_project_build::VERSION
            );
            // Notes survive an empty plan, and the one that matters is
            // the bevy mismatch: `jd doctor` sends people to upgrade for
            // exactly that, and reporting only "already on jackdaw
            // 0.19.0" reads as if there were nothing to fix.
            for note in &plan.notes {
                println!("  note: {note}");
            }
            ExitCode::SUCCESS
        }
        Ok(plan) => {
            println!("jd upgrade preview: {}", root.display());
            for change in &plan.changes {
                println!("  {}", change.summary());
            }
            for note in &plan.notes {
                println!("  note: {note}");
            }
            if !args.iter().any(|arg| arg == "--apply") {
                println!(
                    "\nNo files changed. Run `jd upgrade --apply {}` to apply.",
                    root.display()
                );
                return ExitCode::SUCCESS;
            }
            match apply_import_plan(&plan) {
                Ok(report) => {
                    println!("\nApplied {} change(s).", report.actions.len());
                    println!("\nNext: `jd build {}`", root.display());
                    ExitCode::SUCCESS
                }
                Err(error) => {
                    eprintln!("jd upgrade: {error}");
                    ExitCode::FAILURE
                }
            }
        }
        Err(error) => {
            eprintln!("jd upgrade: {error}");
            ExitCode::FAILURE
        }
    }
}

/// The editor binary installed beside the running executable, or
/// `jackdaw` from `PATH` when the location is unknown.
pub fn editor_executable() -> PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|path| {
            path.parent()
                .map(|parent| parent.join(editor_executable_name()))
        })
        .unwrap_or_else(|| PathBuf::from(editor_executable_name()))
}

fn editor_executable_name() -> &'static str {
    if cfg!(windows) {
        "jackdaw.exe"
    } else {
        "jackdaw"
    }
}

fn parse_plugin_arg(args: &[String]) -> Option<String> {
    flag_value(args, "--plugin")
}

/// What a new game's starter scene holds. The game template ships the 3D
/// one; the others replace it after scaffolding.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum StarterScene {
    /// A camera, a sun and the game plugin that loads them.
    #[default]
    ThreeD,
    /// A 2D camera and a sprite.
    TwoD,
    /// An empty root, for a game that builds its world in code.
    Empty,
}

const STARTER_SCENE_2D: &str = "\
// Starter scene. Authored by the jackdaw editor; safe to edit by hand.

#Root
jackdaw_scene_types::Scene2dRoot
bevy_transform::components::transform::Transform
bevy_camera::visibility::Visibility::Visible
bevy_ecs::hierarchy::Children [
    #\"Main Camera\"
    bevy_camera::components::Camera2d
    bevy_transform::components::transform::Transform
    bevy_camera::visibility::Visibility::Visible
    --
    #Sprite
    bevy_sprite::sprite::Sprite
    bevy_transform::components::transform::Transform {
        scale: glam::Vec3 { x: 64.0, y: 64.0, z: 1.0 },
    }
    bevy_camera::visibility::Visibility::Visible
]
";

const STARTER_SCENE_EMPTY: &str = "\
// Starter scene. Authored by the jackdaw editor; safe to edit by hand.

#Root
bevy_transform::components::transform::Transform
bevy_camera::visibility::Visibility::Visible
";

/// Replace the starter scene of the game scaffolded at `dest` with
/// `starter`'s.
pub fn write_starter_scene(dest: &Path, starter: StarterScene) -> Result<(), ScaffoldError> {
    let text = match starter {
        StarterScene::ThreeD => return Ok(()),
        StarterScene::TwoD => STARTER_SCENE_2D,
        StarterScene::Empty => STARTER_SCENE_EMPTY,
    };
    let scene = dest.join("assets").join("scene.bsn");
    std::fs::write(&scene, text)
        .map_err(|error| ScaffoldError::Io(format!("{}: {error}", scene.display())))
}

/// Scaffold a new project at `dest` from an embedded template,
/// substituting the project name, crate name, authors, and title
/// placeholders. A game starts with the default modules.
pub fn scaffold_new_project(
    dest: &Path,
    project_name: &str,
    kind: TemplateKind,
) -> Result<ScaffoldReport, ScaffoldError> {
    scaffold_new_project_with(
        dest,
        project_name,
        kind,
        &ModuleCatalog::builtin().defaults(),
    )
}

/// As [`scaffold_new_project`], with the game using `modules`: they are
/// recorded in `jackdaw.toml`, and their runtime features, crates and
/// plugins are written into the game. Requirements are added. Reusable by
/// the launcher's New Project action.
pub fn scaffold_new_project_with(
    dest: &Path,
    project_name: &str,
    kind: TemplateKind,
    modules: &ModuleSet,
) -> Result<ScaffoldReport, ScaffoldError> {
    let modules = ModuleCatalog::builtin().complete(modules.clone());
    if dest.exists()
        && dest
            .read_dir()
            .map(|mut d| d.next().is_some())
            .unwrap_or(false)
    {
        return Err(ScaffoldError::Io(format!(
            "{} already exists and is not empty",
            dest.display()
        )));
    }

    let crate_name = project_name.replace('-', "_");
    let title = title_case(project_name);
    let authors = git_authors();

    let mut files = Vec::new();
    collect_template_files(kind.dir(), &mut files);

    let mut written = 0usize;
    for file in files {
        let rel = file.path().to_slash_lossy().into_owned();
        let (dest_rel, contents): (PathBuf, Vec<u8>) = match rel.strip_suffix(".template") {
            Some(stripped) => {
                let text = std::str::from_utf8(file.contents()).map_err(|_| {
                    ScaffoldError::Io(format!("template file {rel} is not valid UTF-8"))
                })?;
                let rendered = substitute_placeholders(
                    text,
                    project_name,
                    &crate_name,
                    &authors,
                    &title,
                    &modules,
                );
                // Dotfiles are stored undotted so they do not act on
                // the jackdaw repository itself.
                let stripped = if stripped == "gitignore" {
                    ".gitignore"
                } else {
                    stripped
                };
                (PathBuf::from(stripped), rendered.into_bytes())
            }
            None => (PathBuf::from(&rel), file.contents().to_vec()),
        };

        let out_path = dest.join(&dest_rel);
        if let Some(parent) = out_path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| ScaffoldError::Io(format!("{e}")))?;
        }
        std::fs::write(&out_path, contents).map_err(|e| ScaffoldError::Io(format!("{e}")))?;
        written += 1;
    }

    // In a jackdaw source checkout, repoint the new project's jackdaw
    // deps at the local workspace so it builds against the code being
    // worked on rather than the last release.
    crate::dev_checkout::rewrite_jackdaw_dep_for_dev_checkout(dest);

    // A game builds the same bevy/wgpu/windows tree this jackdaw was
    // built and tested with; a lock resolved fresh from the registry
    // picks whatever the index serves today, which in a bad upstream
    // window does not even compile (the wgpu-hal 30.0.1 dx12 /
    // windows-core macro clash, T08-T1 QA §六-②). Seed the project
    // with this workspace's own lock as the starting point: the
    // resolve step that follows (`check_new_project`'s `cargo
    // metadata`, which writes the lock when it is absent) then only
    // adds this project's own entry and prunes unused ones — cargo
    // keeps already-locked versions — instead of resolving 800 crates
    // at their newest.
    if kind == TemplateKind::Game {
        std::fs::write(dest.join("Cargo.lock"), workspace_lock_snapshot())
            .map_err(|e| ScaffoldError::Io(format!("{e}")))?;
    }

    Ok(ScaffoldReport {
        actions: vec![format!("scaffolded {written} files")],
        created_lib_stub: false,
    })
}

/// The workspace's own `Cargo.lock`, embedded at compile time: the
/// dependency tree this build was verified against. Embedded rather
/// than read from disk because a shipped `jd` runs far from this
/// checkout; a checkout build re-embeds on every compile, the same
/// freshness rule the template directory has.
fn workspace_lock_snapshot() -> &'static str {
    include_str!("../../../Cargo.lock")
}

/// Plan integration of an existing Bevy project without changing it.
pub fn plan_import_project(
    root: &Path,
    plugin_override: Option<String>,
) -> Result<ImportPlan, ScaffoldError> {
    plan_import_package(root, plugin_override, None)
}

/// As [`plan_import_project`], targeting a named workspace member.
///
/// `jackdaw.toml` and `.jackdaw/` always land at `root` (the directory
/// the user opened), while the source changes land in the resolved
/// package. For a single-package project the two are the same
/// directory.
pub fn plan_import_package(
    root: &Path,
    plugin_override: Option<String>,
    package_override: Option<&str>,
) -> Result<ImportPlan, ScaffoldError> {
    plan_import_with(root, plugin_override, package_override, false)
}

/// As [`plan_import_package`], optionally proceeding despite a Bevy
/// minor mismatch.
///
/// The mismatch is a real blocker for building project code, but
/// setting a project up is additive and reversible, and a user
/// mid-upgrade has a legitimate reason to do it before their code
/// compiles. Refusing with no override turns a warning into a dead end.
pub fn plan_import_with(
    root: &Path,
    plugin_override: Option<String>,
    package_override: Option<&str>,
    allow_bevy_mismatch: bool,
) -> Result<ImportPlan, ScaffoldError> {
    plan_import_with_modules(
        root,
        plugin_override,
        package_override,
        allow_bevy_mismatch,
        None,
    )
}

/// As [`plan_import_with`], choosing the modules the project uses.
///
/// Modules the game's dependencies already show are always kept: import
/// only adds. `None` adds nothing beyond those, except that a game without
/// `jackdaw_runtime` yet gets the default modules with it.
pub fn plan_import_with_modules(
    root: &Path,
    plugin_override: Option<String>,
    package_override: Option<&str>,
    allow_bevy_mismatch: bool,
    modules: Option<&ModuleSet>,
) -> Result<ImportPlan, ScaffoldError> {
    let manifest_path = root.join("Cargo.toml");
    if !manifest_path.is_file() {
        return Err(ScaffoldError::NoManifest(manifest_path));
    }
    // A `jackdaw.toml` that does not parse is worse than none: every
    // later check treats its existence as proof the project is set up,
    // so import found nothing to do and reported success, which is the
    // fix `jd doctor` sends people here to apply.
    if jackdaw_project_build::project_manifest::ProjectManifest::exists(root)
        && let Err(detail) =
            jackdaw_project_build::project_manifest::ProjectManifest::read_checked(root)
    {
        return Err(ScaffoldError::SettingsParse {
            path: jackdaw_project_build::project_manifest::path(root),
            detail,
        });
    }

    let package =
        jackdaw_project_build::cargo_meta::resolve_project_package(root, package_override)
            .map_err(ScaffoldError::Package)?;
    let package_dir = package.dir.clone();
    let package_manifest = package_dir.join("Cargo.toml");
    let manifest_text = std::fs::read_to_string(&package_manifest)
        .map_err(|e| ScaffoldError::Io(format!("{}: {e}", package_manifest.display())))?;
    let doc: DocumentMut = manifest_text
        .parse()
        .map_err(|e| ScaffoldError::ManifestParse(format!("{e}")))?;

    // A workspace member can inherit `bevy = { workspace = true }`, so
    // the root manifest is the second place to look.
    let workspace_doc = (package_dir != root)
        .then(|| std::fs::read_to_string(&manifest_path).ok())
        .flatten()
        .and_then(|text| text.parse::<DocumentMut>().ok());
    let mut changes = Vec::new();
    let mut notes = Vec::new();
    let mut migrated_bin_target = false;

    // On a mismatch the pins must record what the PROJECT targets, not
    // what this editor does. Writing the editor's version would make
    // every later check report health and silently disable the warning
    // the user chose to defer, which is the opposite of deferring it.
    let mut pinned_bevy = None;
    let mut bevy_mismatch = false;
    match check_bevy_version(&doc, workspace_doc.as_ref()) {
        Ok(()) => {}
        Err(error) if allow_bevy_mismatch => {
            bevy_mismatch = true;
            if let ScaffoldError::BevyVersion { found } = &error {
                pinned_bevy = bevy_minor_of(found);
            }
            notes.push(format!("proceeding despite a Bevy mismatch: {error}"));
            notes.push(
                "jackdaw.toml will record the Bevy this project targets, so the mismatch keeps \
                 being reported until you resolve it"
                    .to_string(),
            );
        }
        Err(error) => return Err(error),
    }

    if package_dir != root {
        notes.push(format!(
            "workspace detected; `{}` is the game package (override with the `package` key in \
             jackdaw.toml)",
            package.name
        ));
    }

    // A runtime built for this editor's Bevy cannot join a project on
    // another one, so a mismatched import only reports what is missing. A
    // declaration import cannot safely extend is left to the user, and no
    // source may name the crate until it is a plain dependency.
    let wiring = RuntimeWiring::inspect(&package_dir);
    let catalog = ModuleCatalog::builtin();
    let game = GameDependencies::read(&package_dir, root);
    let detected_modules = catalog.detect(&game);
    let chosen_modules = match modules {
        Some(chosen) => chosen.clone(),
        None if wiring.dependency == RuntimeDependency::Missing => catalog.defaults(),
        None => ModuleSet::new(),
    };
    let selected_modules =
        catalog.complete(chosen_modules.union(&detected_modules).cloned().collect());
    let declared_plain = wiring.dependency == RuntimeDependency::Plain;
    let wire_runtime = !bevy_mismatch
        && matches!(
            wiring.dependency,
            RuntimeDependency::Missing | RuntimeDependency::Plain
        );
    let plugin_ready = wire_runtime || declared_plain;
    let pie_always = wiring.pie_feature || (wire_runtime && !wiring.pie_via_feature);
    let windowless_ready = plugin_ready && pie_always;
    if let RuntimeDependency::Unsupported(form) = wiring.dependency {
        notes.push(format!(
            "Cargo.toml declares jackdaw_runtime as {form}, so import leaves it and your \
             sources alone; make it a plain [dependencies] entry with the `pie` feature and \
             re-run `jd import`"
        ));
    }
    if wire_runtime
        && let Some(edit) =
            runtime_dependency_edit(&manifest_text, &wiring, &selected_modules, &game)
    {
        changes.push(ImportChange::WriteFile {
            path: package_manifest.clone(),
            contents: edit.contents,
            replace: true,
        });
        notes.extend(edit.notes);
    }
    let added_modules: Vec<String> = selected_modules
        .difference(&detected_modules)
        .cloned()
        .collect();
    if wire_runtime {
        notes.extend(plugin_notes(
            &package_dir,
            &added_modules.iter().cloned().collect(),
        ));
    }
    if !wire_runtime && !added_modules.is_empty() {
        notes.push(format!(
            "jackdaw.toml records {} as used, but Cargo.toml is left for you to update",
            catalog.names(&added_modules)
        ));
    }

    // Lib target: an explicit [lib] or the conventional src/lib.rs.
    let has_lib = doc.get("lib").is_some() || package_dir.join("src/lib.rs").is_file();
    // The plugin the migration will declare. Not always `GamePlugin`: a
    // crate that already defines that name gets a differently-named
    // wrapper, and recording the wrong one points the shim at a type
    // that will not exist.
    let mut migrated_plugin: Option<String> = None;
    if !has_lib {
        match crate::migrate::plan_migration(&package_dir, &package.crate_name, windowless_ready) {
            Ok(migration) => {
                let main_path = package_dir.join("src/main.rs");
                let original_main = std::fs::read_to_string(&main_path)
                    .map_err(|e| ScaffoldError::Io(format!("{e}")))?;
                changes.push(ImportChange::WriteFile {
                    path: package_dir.join("src/main.rs.bak"),
                    contents: original_main,
                    replace: package_dir.join("src/main.rs.bak").exists(),
                });
                changes.push(ImportChange::WriteFile {
                    path: main_path,
                    contents: migration.main_rs,
                    replace: true,
                });
                changes.push(ImportChange::WriteFile {
                    path: package_dir.join("src/lib.rs"),
                    contents: migration.lib_rs,
                    replace: false,
                });
                migrated_plugin = Some(migration.plugin.clone());
                notes.extend(migration.notes);
                migrated_bin_target = true;
            }
            Err(error) => {
                changes.push(ImportChange::WriteFile {
                    path: package_dir.join("src/lib.rs"),
                    contents: lib_stub_source(plugin_ready),
                    replace: false,
                });
                notes.push(format!(
                    "automatic bin-to-library conversion was unavailable: {error}; \
                     move game setup into GamePlugin before Play"
                ));
            }
        }
    }

    // Plugin type: explicit override, then source detection, then the
    // GamePlugin convention (which is what the stub provides). Recorded
    // in jackdaw.toml for setup notes and `jd doctor`.
    let candidates = jackdaw_project_build::detect::plugin_candidates(&package_dir);
    let detected = detect_plugin(&package_dir, &package.crate_name)
        .and_then(|p| p.split_once("::").map(|(_, name)| name.to_string()));
    // A migration or a stub creates a plugin, so it can be recorded even
    // though the scan above ran before those files existed. The
    // migration reports the name it chose; the stub always uses
    // `GamePlugin`.
    let will_create_plugin = (!has_lib).then(|| {
        migrated_plugin
            .clone()
            .unwrap_or_else(|| "GamePlugin".to_string())
    });
    let plugin = plugin_override
        .clone()
        .or_else(|| detected.clone())
        .or(will_create_plugin);
    // An override is the user's call; warn when the crate does not
    // declare that name so doctor does not later fail on it.
    if let Some(name) = &plugin_override
        && !candidates.iter().any(|candidate| candidate == name)
    {
        notes.push(format!(
            "`{name}` was requested but {} declares no such plugin{}",
            package.crate_name,
            if candidates.is_empty() {
                String::new()
            } else {
                format!(" (found: {})", candidates.join(", "))
            }
        ));
    }
    if plugin_override.is_none() {
        // Distinguish "none exists" from "one exists but is not
        // reachable from outside the crate": telling a user with a
        // perfectly good plugin that none was found sends them looking
        // for the wrong problem.
        let unreachable: Vec<String> = jackdaw_project_build::detect::plugin_paths(&package_dir)
            .into_iter()
            .filter(|found| found.crate_path.is_none())
            .map(|found| found.type_name)
            .collect();
        match &plugin {
            Some(name) if detected.is_some() => notes.push(format!("game plugin: {name}")),
            Some(name) => notes.push(format!("game plugin: {name} (created by this setup)")),
            // Recording a name the crate does not define would leave
            // doctor failing on a key that does not match source, so
            // leave it unset and say what to do when there is one.
            None if candidates.len() >= 2 => notes.push(format!(
                "several plugins found ({}) and none is named GamePlugin; set `plugin` in \
                 jackdaw.toml to name the root one, and add it from `main.rs` for Play",
                candidates.join(", ")
            )),
            None if !unreachable.is_empty() => notes.push(format!(
                "found {}, but it is not reachable from outside the crate; make its module \
                 `pub mod` or re-export it from lib.rs, then set `plugin` in jackdaw.toml",
                unreachable.join(", ")
            )),
            // "Your source does not parse" is a different problem from
            // "you have no plugin", with a different next action.
            None => match jackdaw_project_build::detect::lib_parse_error(&package_dir) {
                Some(error) => notes.push(format!(
                    "could not read {}: {error}. Fix it and re-run, or set `plugin` in \
                     jackdaw.toml by hand.",
                    package_dir.join("src/lib.rs").display()
                )),
                None => notes.push(
                    "no `impl Plugin for ...` found; the editor will still read this crate's \
                     components. Add a Bevy Plugin in the library and wire it from `main.rs` \
                     for Play."
                        .to_string(),
                ),
            },
        }
    }

    // A migration and the library stub wire the runtime themselves.
    if !migrated_bin_target {
        if bevy_mismatch && wiring.dependency == RuntimeDependency::Missing {
            let mut features = module_runtime_features(&selected_modules);
            features.push(PIE_FEATURE.to_string());
            notes.push(format!(
                "add the runtime once the project is on bevy {}: cargo add {} --features {}",
                jackdaw_project_build::BEVY_VERSION,
                jackdaw_project_build::build_source::build_source().cargo_add("jackdaw_runtime"),
                features.join(",")
            ));
        }
        if !wiring.plugin && (has_lib || !plugin_ready) {
            let edit = plugin_ready
                .then_some(plugin.as_deref())
                .flatten()
                .and_then(|name| runtime_plugin_edit(&package_dir, name));
            match edit {
                Some((path, contents)) => {
                    changes.push(ImportChange::WriteFile {
                        path,
                        contents,
                        replace: true,
                    });
                    if let Some(name) = plugin.as_deref().and_then(|p| p.rsplit("::").next())
                        && let Ok(main) = std::fs::read_to_string(package_dir.join("src/main.rs"))
                        && !jackdaw_project_build::runtime_wiring::mentions_ident(&main, name)
                    {
                        notes.push(format!(
                            "src/main.rs does not add `{name}`; add it to your App so Play and \
                             component discovery reach the runtime plugin"
                        ));
                    }
                }
                None => notes.push(crate::migrate::runtime_wiring_note()),
            }
        }
        if !wiring.windowless {
            let main_path = package_dir.join("src/main.rs");
            let wrapped = windowless_ready
                .then(|| std::fs::read_to_string(&main_path).ok())
                .flatten()
                .and_then(|source| crate::migrate::wrap_default_plugins(&source));
            match wrapped {
                Some(contents) => changes.push(ImportChange::WriteFile {
                    path: main_path,
                    contents,
                    replace: true,
                }),
                None => notes.push(crate::migrate::windowless_note()),
            }
        }
    }

    let jackdaw_toml = root.join("jackdaw.toml");
    if !jackdaw_toml.exists() {
        let workspace_package =
            (package_override.is_some() || package_dir != root).then_some(package.name.as_str());
        changes.push(ImportChange::WriteFile {
            path: jackdaw_toml,
            contents: jackdaw_toml_source(
                plugin.as_deref(),
                workspace_package,
                pinned_bevy.as_deref(),
                &selected_modules,
            ),
            replace: false,
        });
    }

    let jackdaw_dir = root.join(".jackdaw");
    if !jackdaw_dir.is_dir() {
        changes.push(ImportChange::CreateDirectory { path: jackdaw_dir });
    }

    let gitignore = root.join(".gitignore");
    let existing_gitignore = std::fs::read_to_string(&gitignore).unwrap_or_default();
    if !has_jackdaw_gitignore(&existing_gitignore) {
        let mut contents = existing_gitignore;
        if !contents.is_empty() && !contents.ends_with('\n') {
            contents.push('\n');
        }
        contents.push_str("/.jackdaw\n");
        changes.push(ImportChange::WriteFile {
            path: gitignore.clone(),
            contents,
            replace: gitignore.exists(),
        });
    }

    Ok(ImportPlan {
        root: root.to_path_buf(),
        package_dir,
        package_name: package.name,
        changes,
        notes,
        migrated_bin_target,
        detected_modules,
        modules: selected_modules,
    })
}

/// Apply a previously reviewed import plan.
pub fn apply_import_plan(plan: &ImportPlan) -> Result<ScaffoldReport, ScaffoldError> {
    let mut actions = Vec::with_capacity(plan.changes.len());
    for change in &plan.changes {
        match change {
            ImportChange::CreateDirectory { path } => {
                std::fs::create_dir_all(path)
                    .map_err(|e| ScaffoldError::Io(format!("{}: {e}", path.display())))?;
            }
            ImportChange::WriteFile { path, contents, .. } => {
                if let Some(parent) = path.parent() {
                    std::fs::create_dir_all(parent)
                        .map_err(|e| ScaffoldError::Io(format!("{}: {e}", parent.display())))?;
                }
                std::fs::write(path, contents)
                    .map_err(|e| ScaffoldError::Io(format!("{}: {e}", path.display())))?;
            }
        }
        actions.push(change.summary());
    }
    Ok(ScaffoldReport {
        actions,
        created_lib_stub: plan.changes.iter().any(|change| {
            matches!(
                change,
                ImportChange::WriteFile {
                    path,
                    replace: false,
                    ..
                } if path.ends_with("src/lib.rs")
            )
        }) && !plan.migrated_bin_target,
    })
}

/// Compatibility helper for callers that have already presented their own
/// confirmation UI.
pub fn import_project(
    root: &Path,
    plugin_override: Option<String>,
) -> Result<ScaffoldReport, ScaffoldError> {
    let plan = plan_import_project(root, plugin_override)?;
    apply_import_plan(&plan)
}

/// The project's declared bevy dependency must be semver-compatible
/// with the supported minor. Projects without a direct bevy dependency
/// pass (an extension crate may express it indirectly); the build
/// surfaces any real mismatch later.
///
/// A workspace member inheriting `bevy = { workspace = true }` is
/// checked against `workspace`'s `[workspace.dependencies]`.
fn check_bevy_version(
    doc: &DocumentMut,
    workspace: Option<&DocumentMut>,
) -> Result<(), ScaffoldError> {
    let Some(req) = declared_bevy_req(doc, workspace) else {
        return Ok(());
    };
    if requirement_admits_supported_bevy(&req) {
        Ok(())
    } else {
        Err(ScaffoldError::BevyVersion { found: req })
    }
}

/// Whether a cargo version requirement can resolve to the Bevy minor
/// this editor supports.
///
/// A textual prefix test gets this wrong in both directions: it accepts
/// `0.190` (which starts with `0.19` but is a different minor) and
/// rejects a perfectly compatible range like `>=0.19, <0.21`. Parsing
/// the requirement and asking whether it matches a version in the
/// supported minor answers the question actually being asked.
fn requirement_admits_supported_bevy(req: &str) -> bool {
    let Ok(parsed) = req.parse::<semver::VersionReq>() else {
        // An unparseable requirement is cargo's problem to report, not
        // a reason to block an import.
        return true;
    };
    // A build on Bevy's main branch takes it from git; no registry release
    // is that Bevy.
    if jackdaw_project_build::BEVY_REV.is_some() {
        return false;
    }
    let Some((major, minor)) = SUPPORTED_BEVY_MINOR.split_once('.') else {
        return true;
    };
    let (Ok(major), Ok(minor)) = (major.parse::<u64>(), minor.parse::<u64>()) else {
        return true;
    };
    // Probe the ends of the supported minor: a requirement admits it if
    // it matches any patch in the range, and cargo requirements are
    // contiguous over patch.
    [0, u64::MAX]
        .iter()
        .any(|patch| parsed.matches(&semver::Version::new(major, minor, *patch)))
}

/// The bevy version requirement a manifest declares, if it states one
/// at all. `None` covers no bevy dependency and path/git dependencies,
/// which express no version for us to compare.
fn declared_bevy_req(doc: &DocumentMut, workspace: Option<&DocumentMut>) -> Option<String> {
    let bevy = doc.get("dependencies")?.get("bevy")?;
    if bevy
        .get("workspace")
        .and_then(toml_edit::Item::as_bool)
        .unwrap_or(false)
    {
        let inherited = workspace?
            .get("workspace")?
            .get("dependencies")?
            .get("bevy")?;
        return version_req_of(inherited);
    }
    version_req_of(bevy)
}

/// The `version` a dependency entry states, in either the plain-string
/// or table form.
fn version_req_of(item: &toml_edit::Item) -> Option<String> {
    item.as_str()
        .map(str::to_string)
        .or_else(|| {
            item.get("version")
                .and_then(|v| v.as_str())
                .map(str::to_string)
        })
        .filter(|req| !req.is_empty())
}

/// An edit to a game's Cargo manifest, with what it does in words.
struct ManifestEdit {
    contents: String,
    notes: Vec<String>,
}

/// `manifest` with `jackdaw_runtime` declared, or with `pie` and the
/// features of `modules` added to an existing plain declaration, plus the
/// crates `modules` add. `None` when nothing is missing or the declaration
/// is one this edit does not touch. A member of a workspace that declares
/// the runtime inherits it from there.
///
/// Edited in place so the user's formatting, comments and key order
/// survive. A `{ workspace = true }` entry gets the features on the
/// member's side, which cargo unions with whatever the workspace declares.
fn runtime_dependency_edit(
    manifest: &str,
    wiring: &RuntimeWiring,
    modules: &ModuleSet,
    game: &GameDependencies,
) -> Option<ManifestEdit> {
    let mut doc: DocumentMut = manifest.parse().ok()?;
    let mut notes = Vec::new();
    let module_features = module_runtime_features(modules);
    match wiring.dependency {
        RuntimeDependency::Missing => {
            let mut features = module_features;
            features.push(PIE_FEATURE.to_string());
            let source = if wiring.workspace_declares {
                "workspace = true".to_string()
            } else {
                jackdaw_dep_requirement(RUNTIME_CRATE)
            };
            let quoted = features
                .iter()
                .map(|feature| format!("\"{feature}\""))
                .collect::<Vec<_>>()
                .join(", ");
            insert_dependency(
                &mut doc,
                RUNTIME_CRATE,
                &format!("{{ {source}, features = [{quoted}] }}"),
            )?;
            notes.push(format!(
                "Cargo.toml: adds jackdaw_runtime (features {}), which component discovery \
                 and Play need",
                features.join(", ")
            ));
        }
        RuntimeDependency::Plain => {
            let mut wanted = Vec::new();
            if !wiring.pie_available() {
                wanted.push(PIE_FEATURE.to_string());
            }
            wanted.extend(
                module_features
                    .into_iter()
                    .filter(|feature| !game.runtime_features.contains(feature)),
            );
            if !wanted.is_empty() {
                add_runtime_features(&mut doc, &wanted)?;
                notes.push(match wanted.as_slice() {
                    [only] if only == PIE_FEATURE => {
                        "Cargo.toml: enables the `pie` feature of jackdaw_runtime, which Play needs"
                            .to_string()
                    }
                    _ => format!(
                        "Cargo.toml: enables jackdaw_runtime features {}",
                        wanted.join(", ")
                    ),
                });
            }
        }
        RuntimeDependency::Unsupported(_) => return None,
    }
    notes.extend(removed_feature_notes(&drop_removed_runtime_features(
        &mut doc,
    )));
    notes.extend(add_module_crates(&mut doc, game, modules)?);
    (doc.to_string() != manifest).then(|| ManifestEdit {
        contents: doc.to_string(),
        notes,
    })
}

/// The runtime features and crate names `doc` declares itself, without
/// anything a workspace adds.
fn declared_dependencies(doc: &DocumentMut) -> GameDependencies {
    let mut game = GameDependencies::default();
    let Some(deps) = doc
        .get("dependencies")
        .and_then(toml_edit::Item::as_table_like)
    else {
        return game;
    };
    for (key, entry) in deps.iter() {
        let name = entry
            .get("package")
            .and_then(toml_edit::Item::as_str)
            .unwrap_or(key);
        game.crates.insert(name.to_string());
        if name == RUNTIME_CRATE {
            let features = entry.get("features").and_then(toml_edit::Item::as_array);
            for feature in features.into_iter().flatten().filter_map(|f| f.as_str()) {
                game.runtime_features.insert(feature.to_string());
            }
        }
    }
    game
}

/// Insert `name = <value>` into `[dependencies]`, `value` being TOML.
fn insert_dependency(doc: &mut DocumentMut, name: &str, value: &str) -> Option<()> {
    let parsed: DocumentMut = format!("entry = {value}").parse().ok()?;
    let mut value = parsed.get("entry")?.as_value()?.clone();
    value.decor_mut().clear();
    doc.entry("dependencies")
        .or_insert_with(toml_edit::table)
        .as_table_like_mut()?
        .insert(name, toml_edit::Item::Value(value));
    Some(())
}

/// The `jackdaw_runtime` entry of `doc` as a table, turning a bare version
/// string into `{ version = ... }` first.
fn runtime_entry_table(doc: &mut DocumentMut) -> Option<&mut toml_edit::Item> {
    let entry = doc
        .get_mut("dependencies")?
        .as_table_like_mut()?
        .get_mut(RUNTIME_CRATE)?;
    if let Some(value) = entry.as_value()
        && let Some(version) = value.as_str()
    {
        let decor = value.decor().clone();
        let mut table = toml_edit::InlineTable::new();
        table.insert("version", version.into());
        let mut replacement = toml_edit::Value::from(table);
        *replacement.decor_mut() = decor;
        *entry = toml_edit::Item::Value(replacement);
    }
    Some(entry)
}

/// Add `features` to the `jackdaw_runtime` entry of `doc`.
fn add_runtime_features(doc: &mut DocumentMut, features: &[String]) -> Option<()> {
    let entry = runtime_entry_table(doc)?;
    let table = entry.as_table_like_mut()?;
    match table
        .get_mut("features")
        .and_then(toml_edit::Item::as_array_mut)
    {
        Some(array) => {
            for feature in features {
                array.push(feature.as_str());
            }
        }
        None => {
            let mut array = toml_edit::Array::new();
            for feature in features {
                array.push(feature.as_str());
            }
            table.insert("features", toml_edit::value(array));
        }
    }
    if let Some(inline) = entry.as_inline_table_mut() {
        inline.fmt();
    }
    Some(())
}

/// Take `features` off the `jackdaw_runtime` entry of `doc`.
fn remove_runtime_features(doc: &mut DocumentMut, features: &[String]) -> Option<()> {
    let entry = runtime_entry_table(doc)?;
    if let Some(array) = entry
        .as_table_like_mut()?
        .get_mut("features")
        .and_then(toml_edit::Item::as_array_mut)
    {
        array.retain(|value| {
            value
                .as_str()
                .is_none_or(|f| !features.iter().any(|x| x == f))
        });
        array.fmt();
    }
    Some(())
}

/// Take the `jackdaw_runtime` features that no longer exist off the entries
/// in `doc`'s `[dependencies]` and `[workspace.dependencies]`. Returns the
/// features taken off.
fn drop_removed_runtime_features(doc: &mut DocumentMut) -> Vec<String> {
    let catalog = ModuleCatalog::builtin();
    let mut dropped = Vec::new();
    let mut drop_from = |deps: Option<&mut toml_edit::Item>| {
        let Some(array) = deps
            .and_then(toml_edit::Item::as_table_like_mut)
            .and_then(|deps| deps.get_mut(RUNTIME_CRATE))
            .and_then(toml_edit::Item::as_table_like_mut)
            .and_then(|entry| entry.get_mut("features"))
            .and_then(toml_edit::Item::as_array_mut)
        else {
            return;
        };
        array.retain(|value| match value.as_str() {
            Some(feature) if catalog.replacing_feature(feature).is_some() => {
                dropped.push(feature.to_string());
                false
            }
            _ => true,
        });
        array.fmt();
    };
    drop_from(doc.get_mut("dependencies"));
    drop_from(
        doc.get_mut("workspace")
            .and_then(|workspace| workspace.get_mut("dependencies")),
    );
    dropped.sort();
    dropped.dedup();
    dropped
}

/// A note per removed `jackdaw_runtime` feature in `features`, naming the
/// module recorded in its place.
fn removed_feature_notes(features: &[String]) -> Vec<String> {
    let catalog = ModuleCatalog::builtin();
    features
        .iter()
        .filter_map(|feature| {
            let module = catalog.replacing_feature(feature)?;
            let mut note = format!(
                "Cargo.toml: drops the `{feature}` feature of jackdaw_runtime, which no longer \
                 exists; jackdaw.toml records the {} module in its place",
                module.name
            );
            if let Some(reason) = &module.unavailable {
                note.push_str(&format!(
                    ". {} is not compatible with this editor line yet: {reason}",
                    module.name
                ));
            }
            Some(note)
        })
        .collect()
}

/// Add the crates of `modules` that `game` does not declare yet, returning
/// a note per crate. Modules whose crates ride a foreign bevy (the physics
/// module's avian tracks registry bevy) also carry the version-pinned fork
/// patch, so the game resolves the one bevy this editor was built against.
fn add_module_crates(
    doc: &mut DocumentMut,
    game: &GameDependencies,
    modules: &ModuleSet,
) -> Option<Vec<String>> {
    let mut notes = Vec::new();
    for module in enabled_modules(modules) {
        if let Some(reason) = &module.unavailable {
            notes.push(format!(
                "{} is not compatible with this editor line, so none of its crates were added: {reason}.",
                module.name
            ));
            continue;
        }
        for krate in &module.crates {
            if game.crates.contains(&krate.name) {
                continue;
            }
            let requirement = match krate.requirement() {
                Some(requirement) => requirement,
                None => jackdaw_crate_like_runtime(doc, &krate.name)
                    .unwrap_or_else(|| module_crate_requirement(krate)),
            };
            insert_dependency(doc, &krate.name, &requirement)?;
            notes.push(format!(
                "Cargo.toml: adds {} for the {} module",
                krate.name, module.name
            ));
        }
    }
    if modules.contains("physics") {
        match jackdaw_project_build::BEVY_FORK {
            // The fork lives on the machine this editor was built on; a
            // project it is written into is not portable, so only a dev
            // checkout — running out of the tree the fork sits beside —
            // patches the game to it. Everyone else gets the note below.
            Some(fork) if crate::dev_checkout::jackdaw_dev_checkout().is_some() => {
                add_bevy_fork_patch(doc, fork);
                notes.push(String::from(
                    "Cargo.toml: patches bevy to the version-pinned fork, the one bevy \
                     this editor was built against",
                ));
            }
            _ => notes.push(String::from(
                "physics: this build cannot share its bevy fork patch with the game; \
                 if the build fails to resolve two bevies, remake the fork with this \
                 jackdaw's scripts/make-bevy-fork.ps1 and add the [patch] sections \
                 it writes",
            )),
        }
    }
    Some(notes)
}

/// Point both of the game's bevy sources — the registry one avian names and
/// the git one the template names — at the version-pinned fork, so every
/// bevy type in the game is the type this editor was built with.
fn add_bevy_fork_patch(doc: &mut DocumentMut, fork: &str) {
    let fork = fork.replace('\\', "/");
    for name in BEVY_FORK_CRATES {
        let path = fork_crate_path(&fork, name);
        path_patch_section(doc, "crates-io")
            .insert(name, toml_edit::Item::Table(path_table(&path)));
    }
    let git = jackdaw_project_build::bevy_source::BEVY_GIT;
    for name in BEVY_FORK_CRATES {
        let path = fork_crate_path(&fork, name);
        path_patch_section(doc, git).insert(name, toml_edit::Item::Table(path_table(&path)));
    }
}

/// The packages the bevy fork patches, in every `[patch]` section a
/// game carries: the umbrella `bevy` and the crates that ride the
/// same fork. Both the registry source (avian's bevy) and the git
/// source (the template's own bevy declaration) must be covered —
/// a git-source subcrate left unpatched floats to the remote branch
/// head on every resolve, past the commit the lockfile holds.
const BEVY_FORK_CRATES: [&str; 5] = [
    "bevy",
    "bevy_curve",
    "bevy_math",
    "bevy_reflect",
    "bevy_shape",
];

/// Where crate `name` lives inside the bevy fork at `fork`.
fn fork_crate_path(fork: &str, name: &str) -> String {
    if name == "bevy" {
        fork.to_string()
    } else {
        format!("{fork}/crates/{name}")
    }
}

/// The `[patch.<section>]` table of `doc`, appended as a standard table
/// (an implicit index would write an inline table in place, mangling the
/// manifest's order and form).
fn path_patch_section<'a>(doc: &'a mut DocumentMut, section: &str) -> &'a mut toml_edit::Table {
    let patch = doc
        .entry("patch")
        .or_insert(toml_edit::Item::Table({
            let mut table = toml_edit::Table::new();
            table.set_implicit(true);
            table
        }))
        .as_table_mut()
        .expect("patch is a table");
    let entry = patch
        .entry(section)
        .or_insert(toml_edit::Item::Table(toml_edit::Table::new()));
    entry.as_table_mut().expect("the patch section is a table")
}

/// A `{ path = "..." }` table in standard form.
fn path_table(path: &str) -> toml_edit::Table {
    let mut table = toml_edit::Table::new();
    table["path"] = toml_edit::value(path);
    table
}

/// What the game's code still has to do for `added` modules: add each
/// module plugin whose crate no source file names yet.
fn plugin_notes(package_dir: &Path, added: &ModuleSet) -> Vec<String> {
    let sources: Vec<String> =
        jackdaw_project_build::runtime_wiring::source_files(&package_dir.join("src"))
            .iter()
            .filter_map(|path| std::fs::read_to_string(path).ok())
            .collect();
    enabled_modules(added)
        .flat_map(|module| &module.crates)
        .filter_map(|krate| {
            let plugin = krate.plugin.as_ref()?;
            let ident = krate.name.replace('-', "_");
            let named = sources
                .iter()
                .any(|text| jackdaw_project_build::runtime_wiring::mentions_ident(text, &ident));
            (!named).then(|| format!("add `{plugin}` to the game's App"))
        })
        .collect()
}

/// How `doc` should ask for the jackdaw crate `name`: from the same place
/// its `jackdaw_runtime` comes from, so the two stay one build. `None` when
/// the runtime entry gives nothing to copy.
fn jackdaw_crate_like_runtime(doc: &DocumentMut, name: &str) -> Option<String> {
    let entry = doc.get("dependencies")?.get(RUNTIME_CRATE)?;
    if let Some(version) = entry.as_str() {
        return Some(format!("{{ version = \"{version}\" }}"));
    }
    let table = entry.as_table_like()?;
    let text = |key: &str| table.get(key).and_then(toml_edit::Item::as_str);
    if let Some(path) = text("path") {
        let parent = path
            .trim_end_matches(['/', '\\'])
            .strip_suffix(RUNTIME_CRATE)?;
        let checkout = Path::new(parent.trim_end_matches(['/', '\\']));
        let sibling = match checkout.parent() {
            Some(root) if checkout.file_name() == Some("crates".as_ref()) => {
                jackdaw_project_build::build_source::crate_path(root, name)
                    .to_slash_lossy()
                    .into_owned()
            }
            _ => format!("{parent}{name}"),
        };
        return Some(format!("{{ path = '{sibling}' }}"));
    }
    if let Some(git) = text("git") {
        let pin = ["rev", "tag", "branch"]
            .into_iter()
            .find_map(|key| text(key).map(|value| format!(", {key} = \"{value}\"")))
            .unwrap_or_default();
        return Some(format!("{{ git = \"{git}\"{pin} }}"));
    }
    text("version").map(|version| format!("{{ version = \"{version}\" }}"))
}

/// A set-up project's game package and the modules it uses.
struct SetUpGame {
    settings_path: PathBuf,
    package: jackdaw_project_build::cargo_meta::PackageInfo,
    game: GameDependencies,
    modules: ModuleSet,
}

fn set_up_game(root: &Path) -> Result<SetUpGame, ScaffoldError> {
    use jackdaw_project_build::project_manifest::{self, ProjectManifest};

    if !ProjectManifest::exists(root) {
        return Err(ScaffoldError::NotSetUp(root.to_path_buf()));
    }
    let settings_path = project_manifest::path(root);
    let manifest =
        ProjectManifest::read_checked(root).map_err(|detail| ScaffoldError::SettingsParse {
            path: settings_path.clone(),
            detail,
        })?;
    let package = jackdaw_project_build::cargo_meta::resolve_project_package(
        root,
        manifest.package.as_deref(),
    )
    .map_err(ScaffoldError::Package)?;
    let game = GameDependencies::read(&package.dir, root);
    let modules = match &manifest.modules {
        Some(_) => manifest.modules(root),
        None => ModuleCatalog::builtin().detect(&game),
    };
    Ok(SetUpGame {
        settings_path,
        package,
        game,
        modules,
    })
}

/// The modules the set-up project at `root` uses: its `[modules]` table,
/// or what its game package already declares when there is none.
pub fn project_modules(root: &Path) -> Result<ModuleSet, ScaffoldError> {
    set_up_game(root).map(|game| game.modules)
}

/// Plan switching the set-up project at `root` to `modules`: the
/// `[modules]` table in `jackdaw.toml`, and the runtime features and crates
/// in the game's Cargo.toml. Requirements are added. Side-effect free, like
/// the import plan; apply it with [`apply_import_plan`].
///
/// Turning a module off takes its runtime features away but leaves its
/// crates, which the game's own code may still use.
pub fn plan_module_change(root: &Path, modules: &ModuleSet) -> Result<ImportPlan, ScaffoldError> {
    let target = ModuleCatalog::builtin().complete(modules.clone());
    let SetUpGame {
        settings_path,
        package,
        game,
        modules: current,
    } = set_up_game(root)?;
    let mut changes = Vec::new();
    let mut notes = Vec::new();

    let cargo_path = package.dir.join("Cargo.toml");
    let cargo_text = std::fs::read_to_string(&cargo_path)
        .map_err(|e| ScaffoldError::Io(format!("{}: {e}", cargo_path.display())))?;
    let mut doc: DocumentMut = cargo_text
        .parse()
        .map_err(|e| ScaffoldError::ManifestParse(format!("{e}")))?;
    let declared = declared_dependencies(&doc);
    let wanted = module_runtime_features(&target);
    let dropped: ModuleSet = current.difference(&target).cloned().collect();
    let unwanted: Vec<String> = module_runtime_features(&dropped)
        .into_iter()
        .filter(|feature| !wanted.contains(feature))
        .collect();
    let wiring = RuntimeWiring::inspect(&package.dir);
    if wiring.dependency == RuntimeDependency::Plain {
        let add: Vec<String> = wanted
            .iter()
            .filter(|feature| !game.runtime_features.contains(*feature))
            .cloned()
            .collect();
        if !add.is_empty() {
            add_runtime_features(&mut doc, &add)
                .ok_or_else(|| ScaffoldError::ManifestParse("jackdaw_runtime".to_string()))?;
            notes.push(format!(
                "Cargo.toml: enables jackdaw_runtime features {}",
                add.join(", ")
            ));
        }
        let remove: Vec<String> = unwanted
            .iter()
            .filter(|feature| declared.runtime_features.contains(*feature))
            .cloned()
            .collect();
        if !remove.is_empty() {
            remove_runtime_features(&mut doc, &remove)
                .ok_or_else(|| ScaffoldError::ManifestParse("jackdaw_runtime".to_string()))?;
            notes.push(format!(
                "Cargo.toml: turns off jackdaw_runtime features {}",
                remove.join(", ")
            ));
        }
        let inherited: Vec<&String> = unwanted
            .iter()
            .filter(|feature| {
                game.runtime_features.contains(*feature)
                    && !declared.runtime_features.contains(*feature)
            })
            .collect();
        if !inherited.is_empty() {
            notes.push(format!(
                "the workspace's jackdaw_runtime entry still enables {}; take it off there",
                inherited
                    .iter()
                    .map(|feature| feature.as_str())
                    .collect::<Vec<_>>()
                    .join(", ")
            ));
        }
    } else if !wanted.is_empty() || !unwanted.is_empty() {
        notes.push(
            "Cargo.toml does not declare jackdaw_runtime as a plain dependency, so its features \
             are left for you to change"
                .to_string(),
        );
    }
    notes.extend(
        add_module_crates(&mut doc, &game, &target)
            .ok_or_else(|| ScaffoldError::ManifestParse("[dependencies]".to_string()))?,
    );
    let added: ModuleSet = target.difference(&current).cloned().collect();
    notes.extend(plugin_notes(&package.dir, &added));
    for module in enabled_modules(&dropped) {
        for krate in &module.crates {
            if declared.crates.contains(&krate.name) {
                notes.push(format!(
                    "{} stays in Cargo.toml; remove it and its plugin if the game no longer uses it",
                    krate.name
                ));
            }
        }
    }
    let cargo_changed = doc.to_string() != cargo_text;
    if cargo_changed {
        changes.push(ImportChange::WriteFile {
            path: cargo_path,
            contents: doc.to_string(),
            replace: true,
        });
        notes.push("the game rebuilds with these changes the next time it is built".to_string());
    }

    let settings_text = std::fs::read_to_string(&settings_path)
        .map_err(|e| ScaffoldError::Io(format!("{}: {e}", settings_path.display())))?;
    let settings = jackdaw_project_build::modules::with_modules(&settings_text, &target).map_err(
        |detail| ScaffoldError::SettingsParse {
            path: settings_path.clone(),
            detail,
        },
    )?;
    if settings != settings_text {
        changes.push(ImportChange::WriteFile {
            path: settings_path,
            contents: settings,
            replace: true,
        });
    }

    Ok(ImportPlan {
        root: root.to_path_buf(),
        package_dir: package.dir,
        package_name: package.name,
        changes,
        notes,
        migrated_bin_target: false,
        detected_modules: current,
        modules: target,
    })
}

/// The library file declaring `impl Plugin for <plugin>`, rewritten so its
/// `build` adds `JackdawPlugin`. `None` unless exactly one library file
/// declares exactly one such impl with a `build` that can be edited.
fn runtime_plugin_edit(package_dir: &Path, plugin: &str) -> Option<(PathBuf, String)> {
    let name = plugin.rsplit("::").next()?;
    let src = package_dir.join("src");
    let mut declaring = jackdaw_project_build::runtime_wiring::source_files(&src)
        .into_iter()
        .filter(|path| path != &src.join("main.rs") && !path.starts_with(src.join("bin")))
        .filter_map(|path| {
            let text = std::fs::read_to_string(&path).ok()?;
            let count = crate::migrate::plugin_impl_count(&text, name);
            (count > 0).then_some((path, text, count))
        });
    let (path, text, count) = declaring.next()?;
    if count != 1 || declaring.next().is_some() {
        return None;
    }
    let contents = crate::migrate::add_runtime_plugin(&text, name)?;
    Some((path, contents))
}

fn has_jackdaw_gitignore(contents: &str) -> bool {
    contents
        .lines()
        .any(|l| l.trim() == "/.jackdaw" || l.trim() == ".jackdaw" || l.trim() == ".jackdaw/")
}

/// The library stub for a bin-only project. `with_runtime` adds
/// `JackdawPlugin` from the plugin, for a project that depends on the
/// runtime.
fn lib_stub_source(with_runtime: bool) -> String {
    let build = if with_runtime {
        "fn build(&self, app: &mut App) {\n        app.add_plugins(jackdaw_runtime::JackdawPlugin);\n    }"
    } else {
        "fn build(&self, _app: &mut App) {}"
    };
    LIB_STUB.replace("{build}", build)
}

const LIB_STUB: &str = r#"//! Game library: put gameplay here and add [`GamePlugin`] from
//! `main.rs` so `cargo run` and the editor's Play button share it.
//! Move your game setup (systems, resources, observers) in here
//! from main.rs.
//!
//! # Adding components the editor can see
//!
//! Write components anywhere in this library (any module, not
//! `main.rs`), deriving `Component, Reflect, Default` with
//! `#[reflect(Component, Default)]`. After you save, click Rebuild in
//! jackdaw (or run `jd build`) and they appear in
//! `Add Component`. No registration code is needed; Bevy's
//! `reflect_auto_register` picks up the `Reflect` derive.

use bevy::prelude::*;

#[derive(Default)]
pub struct GamePlugin;

impl Plugin for GamePlugin {
    {build}
}

// Example: an editable component. Uncomment, save, and Rebuild to see
// `Health` in the Components panel's Add Component list.
//
// #[derive(Component, Reflect, Default)]
// #[reflect(Component, Default)]
// pub struct Health {
//     pub max: f32,
//     pub current: f32,
// }
"#;

/// The `major.minor` a version requirement names, for reporting and for
/// recording what a project targets. `None` when the requirement states
/// no usable pair.
fn bevy_minor_of(req: &str) -> Option<String> {
    let head = req
        .trim_start_matches(['^', '=', '~', '>', '<'])
        .split(',')
        .next()?
        .trim();
    let mut parts = head.split('.');
    let major = parts.next()?;
    let minor = parts.next()?;
    let usable = !major.is_empty()
        && !minor.is_empty()
        && major.chars().all(|c| c.is_ascii_digit())
        && minor.chars().all(|c| c.is_ascii_digit());
    usable.then(|| format!("{major}.{minor}"))
}

fn jackdaw_toml_source(
    plugin: Option<&str>,
    workspace_package: Option<&str>,
    pinned_bevy: Option<&str>,
    modules: &ModuleSet,
) -> String {
    let package = match workspace_package {
        Some(name) => {
            format!("\n# The workspace member jackdaw builds as the game.\npackage = \"{name}\"\n")
        }
        None => String::new(),
    };
    // With no plugin to name, the key stays commented so doctor does
    // not fail on a type the crate does not declare.
    let plugin = match plugin {
        Some(name) => {
            format!(
                "# Optional name of your game's root Bevy Plugin (for setup / `jd doctor`).\n\
                 plugin = \"{name}\"\n"
            )
        }
        None => "# Optional name of your game's root Bevy Plugin (for setup / `jd doctor`).\n\
                 # Play runs your cargo binary; add the plugin from `main.rs`.\n\
                 # plugin = \"GamePlugin\"\n"
            .to_string(),
    };
    format!(
        "# jackdaw project settings.\n\
         \n\
         {plugin}\
         {package}\n\
         {pins}\n\
         {modules}\n\
         [[run]]\n\
         name = \"Play\"\n",
        pins = match pinned_bevy {
            Some(bevy) => jackdaw_project_build::project_manifest::pins_toml_for_bevy(bevy),
            None => jackdaw_project_build::project_manifest::pins_toml(),
        },
        modules = jackdaw_project_build::modules::modules_toml(modules),
    )
}

/// Recursively gather every embedded file under `dir`.
fn collect_template_files<'a>(dir: &'a Dir<'a>, out: &mut Vec<&'a include_dir::File<'a>>) {
    for entry in dir.entries() {
        match entry {
            include_dir::DirEntry::File(f) => out.push(f),
            include_dir::DirEntry::Dir(d) => collect_template_files(d, out),
        }
    }
}

/// Replace the template's placeholders. Matches the exact forms the
/// templates use; the longer `title_case` form is replaced before the
/// bare one.
fn substitute_placeholders(
    text: &str,
    project_name: &str,
    crate_name: &str,
    authors: &str,
    title: &str,
    modules: &ModuleSet,
) -> String {
    let text = replace_line(text, "{{module_crates}}", &module_crate_lines(modules));
    let text = replace_line(&text, "{{module_patches}}", &module_patch_lines(modules));
    let text = replace_line(&text, "{{bevy_pin_note}}", &bevy_pin_note());
    let text = replace_line(&text, "{{module_plugins}}", &module_plugin_lines(modules));
    let text = replace_line(
        &text,
        "{{module_physics_statements}}",
        &module_physics_statements(modules),
    );
    let text = replace_line(
        &text,
        "{{module_physics_falling_body}}",
        &module_physics_falling_body(modules),
    );
    let text = replace_line(
        &text,
        "{{module_physics_manual_gravity}}",
        &module_physics_manual_gravity(modules),
    );
    let text = replace_line(
        &text,
        "{{module_physics_player_body}}",
        &module_physics_player_body(modules),
    );
    let text = replace_line(
        &text,
        "{{module_physics_player_doc}}",
        &module_physics_player_doc(modules),
    );
    let text = replace_line(
        &text,
        "{{module_physics_player_move}}",
        &module_physics_player_move(modules),
    );
    let text = replace_line(
        &text,
        "{{module_physics_demo}}",
        &module_physics_demo(modules),
    );
    let text = replace_line(
        &text,
        "{{module_tilemap_doc}}",
        &module_tilemap_doc(modules),
    );
    let text = replace_line(
        &text,
        "{{module_tilemap_collision}}",
        &module_tilemap_collision(modules),
    );
    let text = replace_line(
        &text,
        "{{module_tilemap_player}}",
        &module_tilemap_player(modules),
    );
    text.replace("{{project-name | title_case}}", title)
        .replace(
            "{{jackdaw_modules}}",
            jackdaw_project_build::modules::modules_toml(modules).trim_end(),
        )
        .replace(
            "{{jackdaw_runtime_features}}",
            &template_runtime_features(modules),
        )
        .replace("{{crate_name}}", crate_name)
        .replace("{{authors}}", authors)
        .replace("{{project-name}}", project_name)
        .replace(
            "{{jackdaw_pins}}",
            jackdaw_project_build::project_manifest::pins_toml().trim_end(),
        )
        .replace(
            "{{bevy_dependency}}",
            // Every template game names `wav`: the shipped sounds are wav
            // files, and a generated fixture speaks the same format. The
            // dependency must spell the inline table for the features to be
            // legal TOML in both the release and the git-branch shape.
            &jackdaw_project_build::bevy_source::dependency_with_features(&["wav"]),
        )
        // The toolchain file pins the project's own builds (Play included)
        // to the rustc this editor was built with: a Bevy newer than the
        // default toolchain's MSRV support fails far from the cause.
        .replace("{{rust_toolchain}}", jackdaw_env::RUSTUP_TOOLCHAIN)
        .replace(
            "{{jackdaw_version}}",
            &jackdaw_project_build::jackdaw_requirement(),
        )
        .replace(
            "{{jackdaw_runtime_dep}}",
            &jackdaw_dep_requirement("jackdaw_runtime"),
        )
        .replace(
            "{{jackdaw_extension_dep}}",
            &jackdaw_dep_requirement("jackdaw_extension"),
        )
}

/// The comment above a scaffolded `bevy` dependency that tracks Bevy's main
/// branch, naming the commit the lockfile is held at. Nothing for a release.
fn bevy_pin_note() -> String {
    match jackdaw_project_build::BEVY_REV {
        Some(rev) => format!(
            "# Bevy's main branch. Cargo.lock holds it at the commit this jackdaw is\n\
             # built against, recorded as `bevy_rev` in jackdaw.toml:\n\
             # {rev}\n\
             # The editor moves the lockfile back to it before each build.\n"
        ),
        None => String::new(),
    }
}

/// Replace each line holding only `placeholder` with `lines`, whichever
/// line ending the template was checked out with.
fn replace_line(text: &str, placeholder: &str, lines: &str) -> String {
    text.replace(&format!("{placeholder}\r\n"), lines)
        .replace(&format!("{placeholder}\n"), lines)
}

/// The runtime features a new game enables: its modules' features, then
/// terrain and tilemap drawing and the editor link.
fn template_runtime_features(modules: &ModuleSet) -> String {
    let mut features = module_runtime_features(modules);
    for always in ["terrain", "tilemap", PIE_FEATURE] {
        if !features.iter().any(|feature| feature == always) {
            features.push(always.to_string());
        }
    }
    features
        .iter()
        .map(|feature| format!("\"{feature}\""))
        .collect::<Vec<_>>()
        .join(", ")
}

/// The `jackdaw_runtime` features `modules` enable, in catalog order.
fn module_runtime_features(modules: &ModuleSet) -> Vec<String> {
    let mut features: Vec<String> = Vec::new();
    for module in enabled_modules(modules) {
        for feature in &module.runtime_features {
            if !features.contains(feature) {
                features.push(feature.clone());
            }
        }
    }
    features
}

/// The catalog entries of `modules`, in catalog order.
fn enabled_modules(
    modules: &ModuleSet,
) -> impl Iterator<Item = &'static jackdaw_project_build::modules::ModuleInfo> {
    ModuleCatalog::builtin()
        .modules()
        .iter()
        .filter(|module| modules.contains(&module.id))
}

/// How a game asks for a module's crate: its registry or git source, or for a jackdaw
/// crate the source the runtime comes from.
fn module_crate_requirement(krate: &jackdaw_project_build::modules::ModuleCrate) -> String {
    krate
        .requirement()
        .unwrap_or_else(|| format!("{{ {} }}", jackdaw_dep_requirement(&krate.name)))
}

/// The `[dependencies]` lines for the crates `modules` add.
fn module_crate_lines(modules: &ModuleSet) -> String {
    enabled_modules(modules)
        .flat_map(|module| &module.crates)
        .map(|krate| format!("{} = {}\n", krate.name, module_crate_requirement(krate)))
        .collect()
}

/// The `[patch]` sections a game with `modules` carries, as manifest text
/// (empty when none apply). The physics module rides avian, whose registry
/// bevy must be redirected to the version-pinned fork this editor was
/// built against — the same patch this editor's own workspace carries.
/// Only a dev checkout writes them: the fork is a directory on the machine
/// this editor was built on, so a shipped binary naming it hands every new
/// project a `[patch]` that resolves nowhere on the user's machine.
fn module_patch_lines(modules: &ModuleSet) -> String {
    if !modules.contains("physics") || !crate::dev_checkout::jackdaw_dev_checkout().is_some() {
        return String::new();
    }
    let Some(fork) = jackdaw_project_build::BEVY_FORK else {
        return String::new();
    };
    let fork = fork.replace('\\', "/");
    let mut out = String::from(
        "# One bevy for everything: avian tracks the registry's bevy, this\n\
         # game's own bevy comes from git, and only the fork below satisfies\n\
         # both. Remade by this jackdaw's scripts/make-bevy-fork.ps1.\n",
    );
    out.push_str("[patch.crates-io]\n");
    for name in BEVY_FORK_CRATES {
        let path = fork_crate_path(&fork, name);
        out.push_str(&format!("{name} = {{ path = \"{path}\" }}\n"));
    }
    let git = jackdaw_project_build::bevy_source::BEVY_GIT;
    out.push_str(&format!("[patch.\"{git}\"]\n"));
    for name in BEVY_FORK_CRATES {
        let path = fork_crate_path(&fork, name);
        out.push_str(&format!("{name} = {{ path = \"{path}\" }}\n"));
    }
    out
}

/// The `.add_plugins(...)` lines a new game's `main` adds for `modules`.
fn module_plugin_lines(modules: &ModuleSet) -> String {
    enabled_modules(modules)
        .flat_map(|module| &module.crates)
        .filter_map(|krate| krate.plugin.as_ref())
        .map(|plugin| format!("        .add_plugins({plugin})\n"))
        .collect()
}

/// The extra statements the template's `GamePlugin::build` gains with
/// the physics module: the trigger bridge (sensors report into
/// `TriggerEvents`), the stage/pickup spawns — level scenery, spawned
/// with the level and despawned with it — and the systems that consume
/// the triggers and the run's counters. Empty without the module — the
/// template's manual-fall fallback stands in instead.
fn module_physics_statements(modules: &ModuleSet) -> String {
    if !modules.contains("physics") {
        return String::new();
    }
    [
        "        // Physics & triggers (the docs at the top walk the pattern):\n",
        "        // the bridge turns sensor contacts into `TriggerEvents` —\n",
        "        // `collect_pickups` and `hazard_damage` read it — and\n",
        "        // `apply_gravity_from_config` hands the config's gravity\n",
        "        // number to the engine. The props are level scenery:\n",
        "        // spawned on entry, gone on exit, back fresh on the next\n",
        "        // one.\n",
        "        app.add_plugins(jackdaw_avian_integration::TriggerPlugin)\n",
        "            .add_systems(OnEnter(GameFlow::Level), reset_run_counters)\n",
        "            .add_systems(\n",
        "                OnEnter(GameFlow::Level),\n",
        "                (spawn_stage, spawn_pickups, spawn_walls, spawn_hazards),\n",
        "            )\n",
        "            .add_systems(Update, (collect_pickups, hazard_damage, apply_gravity_from_config));\n",
    ]
    .concat()
}

/// The rigid body and collider the template's falling cube carries
/// with the physics module: a dynamic body with its own cuboid, so
/// it falls, lands and stays on the stage.
fn module_physics_falling_body(modules: &ModuleSet) -> String {
    if !modules.contains("physics") {
        return String::new();
    }
    [
        "        avian3d::prelude::RigidBody::Dynamic,\n",
        "        jackdaw_avian_integration::AvianCollider(\n",
        "            avian3d::prelude::ColliderConstructor::Cuboid {\n",
        "                x_length: 0.6,\n",
        "                y_length: 0.6,\n",
        "                z_length: 0.6,\n",
        "            },\n",
        "        ),\n",
    ]
    .concat()
}

/// The manual fall line the template's `falling_cubes` uses *without*
/// the physics module: gravity as a translation step, the way the
/// template worked before physics arrived. With the module the line
/// is empty — the engine owns the fall, and `GameConfig::gravity`
/// reaches it through `apply_gravity_from_config` instead.
fn module_physics_manual_gravity(modules: &ModuleSet) -> String {
    if modules.contains("physics") {
        String::new()
    } else {
        "        transform.translation.y += config.gravity * dt;\n".to_string()
    }
}

/// The physical body the template's player carries with the physics
/// module: a kinematic capsule. Kinematic means the game keeps writing
/// the transform — `move_player` sweeps it with avian's move-and-slide,
/// so the player slides along walls instead of through them and walks
/// into sensors without being pushed around by them.
/// The header doc's "place your own player" bullet. With physics it
/// names the five components `move_player` queries together — a
/// hand-authored entity missing any of them does not move at all
/// (C10: the doc used to name two and an editor-placed player stood
/// frozen mid-air). Without the module the walk system's query is the
/// two-component set, and that is what the doc teaches.
fn module_physics_player_doc(modules: &ModuleSet) -> String {
    if !modules.contains("physics") {
        return r#"//! * **A hand-placed player needs two components:**
//!   `PlayerMarker` and `PlayerController` — the walk system below
//!   drives any entity carrying them (no jump and nothing stops it;
//!   that half is what the physics module adds). Parent a `CameraRig`
//!   under it for the follow camera.
"#
        .to_string();
    }
    r#"//! * **A hand-placed player needs the full set.** `move_player`
//!   queries five components together, so an entity authored in the
//!   editor only moves when it carries `PlayerMarker`,
//!   `PlayerController`, a zero `PlayerVelocity`, a Kinematic
//!   `RigidBody`, and an `AvianCollider` (a capsule of radius 0.35
//!   and height 1.0 matches the template's). Parent a `CameraRig`
//!   under it and the game plays your level.
"#
    .to_string()
}

fn module_physics_player_body(modules: &ModuleSet) -> String {
    if !modules.contains("physics") {
        return String::new();
    }
    [
        "        avian3d::prelude::RigidBody::Kinematic,\n",
        "        jackdaw_avian_integration::AvianCollider(\n",
        "            avian3d::prelude::ColliderConstructor::Capsule {\n",
        "                radius: 0.35,\n",
        "                height: 1.0,\n",
        "            },\n",
        "        ),\n",
        "        PlayerVelocity(Vec3::ZERO),\n",
        "        PickupCount(0),\n",
    ]
    .concat()
}

/// The player's movement system. With the physics module it is the
/// full character controller — gravity, a ground check, a jump, and
/// avian's move-and-slide so walls stop the player — in the shape of
/// avian's own controller example: a velocity component the system
/// integrates and a sweep that resolves the movement against the
/// world. Without the module the same actions drive a plain transform
/// step (camera-relative, scaled by delta time — frame-rate
/// independent, but nothing stops the player and there is no jump:
/// collision and falling are what the module adds).
fn module_physics_player_move(modules: &ModuleSet) -> String {
    if !modules.contains("physics") {
        return r#"/// The movement system a game without physics gets: the same
/// camera-relative, frame-rate-correct input handling, applied as a
/// plain transform step. Nothing stops the player and there is no
/// jump — collision and falling are what the physics module adds.
/// The Interact key stands in for the hazard sensors a physical game
/// has: no module means no sensors to walk into, so pressing it takes
/// the damage directly and the health bar has a live number in every
/// project.
fn move_player(
    actions: Res<GameActions>,
    flow: Res<State<GameFlow>>,
    state: Res<GameState>,
    time: Res<Time>,
    mut players: Query<(&PlayerController, &mut Transform), With<PlayerMarker>>,
    mut healths: Query<&mut PlayerHealth, With<PlayerMarker>>,
    look: Query<&CameraLook>,
) {
    // The player only exists inside a run: the flow's `Level` state is
    // the world gate, `paused` the freeze inside it.
    if flow.get() != &GameFlow::Level || state.paused {
        return;
    }
    let dt = time.delta_secs();
    let camera_yaw = look.single().map(|camera| camera.yaw).unwrap_or(0.0);
    let direction = move_direction(actions.value("Move"), camera_yaw);
    for (controller, mut transform) in &mut players {
        transform.translation += direction * controller.move_speed * dt;
        face_movement_direction(direction, dt, &mut transform);
    }
    if actions.just_pressed("Jump") {
        info!("Jump! (needs the physics module to leave the ground)");
    }
    if actions.just_pressed("Interact") {
        for mut health in &mut healths {
            take_damage(&mut health, PLAYER_DAMAGE);
        }
    }
}
"#
        .to_string();
    }
    r#"/// The player's velocity, in metres per second. `move_player` owns it
/// entirely — gravity adds to it, the ground and walls take from it,
/// a jump sets it — so it is runtime state, not an author knob (edit
/// `PlayerController` above to tune how the player moves).
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default, @EditorCategory::new("Actor"))]
pub struct PlayerVelocity(pub Vec3);

/// Everything the five actions do to the player, in one system:
///
/// * `Move` becomes a target horizontal velocity relative to the
///   camera (see `move_direction`);
/// * gravity — the same `GameConfig.gravity` the engine itself got
///   from `apply_gravity_from_config` — integrates onto the vertical
///   axis every frame, grounded or not;
/// * `Jump`, just-pressed and only when a short downward cast finds
///   ground that is not too steep, launches at `jump_speed`;
/// * `move_and_slide` then sweeps the capsule for the frame's
///   distance: as far as the way is clear, sliding along whatever is
///   in the way, and back out of anything already penetrated — that
///   sweep is the "collides with walls" half of a controller, and it
///   hands back the position and the leftover (slid) velocity.
///
/// None of it runs outside a run: the flow's `Level` state is the
/// world gate and `paused` the freeze inside it — the same two checks
/// the no-physics form makes, against the same state the hud reads.
fn move_player(
    actions: Res<GameActions>,
    flow: Res<State<GameFlow>>,
    state: Res<GameState>,
    config: Res<GameConfig>,
    time: Res<Time>,
    move_and_slide: avian3d::prelude::MoveAndSlide,
    mut players: Query<
        (
            Entity,
            &PlayerController,
            &avian3d::prelude::Collider,
            &mut PlayerVelocity,
            &mut Transform,
        ),
        With<PlayerMarker>,
    >,
    look: Query<&CameraLook>,
) {
    if flow.get() != &GameFlow::Level || state.paused {
        return;
    }
    use avian3d::math::{ToF32Precision, ToRealPrecision};
    let dt = time.delta_secs();
    let camera_yaw = look.single().map(|camera| camera.yaw).unwrap_or(0.0);
    let direction = move_direction(actions.value("Move"), camera_yaw);
    for (entity, controller, collider, mut velocity, mut transform) in &mut players {
        velocity.0.x = direction.x * controller.move_speed;
        velocity.0.z = direction.z * controller.move_speed;
        velocity.0.y += config.gravity * dt;
        // Exclude the player's own collider from its queries, or the
        // first sweep hits the player.
        let filter =
            avian3d::prelude::SpatialQueryFilter::from_excluded_entities([entity]);
        // A short cast straight down from the resting capsule finds the
        // ground (a hit whose surface is not too steep); skin width
        // keeps the resting capsule a hair above it, so the 0.1 m cast
        // is enough.
        let grounded = move_and_slide
            .spatial_query
            .cast_shape(
                collider,
                transform.translation.real(),
                transform.rotation,
                Dir3::NEG_Y,
                &avian3d::prelude::ShapeCastConfig::from_max_distance(0.1),
                &filter,
            )
            .is_some_and(|hit| hit.normal1.y > 0.7);
        if grounded && actions.just_pressed("Jump") {
            velocity.0.y = controller.jump_speed;
        }
        let output = move_and_slide.move_and_slide(
            collider,
            transform.translation.real(),
            transform.rotation,
            velocity.0.real(),
            time.delta(),
            &avian3d::prelude::MoveAndSlideConfig::default(),
            &filter,
            // Per-hit handling (footsteps, events) would go here; the
            // default accepts every hit and slides.
            |_| avian3d::prelude::MoveAndSlideHitResponse::Accept,
        );
        transform.translation = output.position.f32();
        velocity.0 = output.projected_velocity;
        face_movement_direction(direction, dt, &mut transform);
    }
    if actions.just_pressed("Interact") {
        info!("Interact!");
    }
}
"#
    .to_string()
}

/// The physics demo section the template's library gains: a stage to
/// land on, three pickups to walk into, the pickup counter, and the
/// gravity handoff. The whole trigger pattern in one place — a game
/// copies `collect_pickups` and swaps `Pickup` for its own marker.
fn module_physics_demo(modules: &ModuleSet) -> String {
    if !modules.contains("physics") {
        return String::new();
    }
    r#"// ---- Physics & triggers: the pickup demo -------------------------
// The stage, the pickups and the systems above them. Everything a
// game needs to copy: spawn a `Sensor` collider, read `TriggerEvents`.
// Every prop below is level scenery — spawned on entering the level,
// `DespawnOnExit` takes it when the level ends, and the next entry
// starts from a fresh set.

/// A thing to walk over and collect: a small glowing sensor cube.
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default, @EditorCategory::new("Actor"))]
pub struct Pickup;

/// How many pickups the player holds, carried by the player entity
/// (a component, so the editor's Play view and an exported build can
/// both see the count move).
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default, @EditorCategory::new("Actor"))]
pub struct PickupCount(pub u32);

/// The floor everything stands on: one big static collider.
fn spawn_stage(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    commands.spawn((
        Mesh3d(meshes.add(Cuboid::new(20.0, 1.0, 20.0))),
        MeshMaterial3d(materials.add(StandardMaterial {
            base_color: Color::srgb(0.15, 0.15, 0.18),
            ..default()
        })),
        Transform::from_xyz(0.0, -0.5, 0.0),
        DespawnOnExit(GameFlow::Level),
        jackdaw_avian_integration::AvianCollider(
            avian3d::prelude::ColliderConstructor::Cuboid {
                x_length: 20.0,
                y_length: 1.0,
                z_length: 20.0,
            },
        ),
    ));
}

/// Three pickups in a line between the player and the falling cube.
/// (`reset_run_counters` puts the count back when the level starts
/// over; the props themselves come back through `DespawnOnExit` and
/// the level-entry spawns.)
fn spawn_pickups(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    spawn_pickup_line(&mut commands, &mut meshes, &mut materials);
}

/// The pickup cubes themselves, one line of three. Its own function so
/// a restart lays the line down again after the run despawned it.
fn spawn_pickup_line(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
) {
    for i in 0..3 {
        commands.spawn((
            Pickup,
            Mesh3d(meshes.add(Cuboid::new(0.3, 0.3, 0.3))),
            MeshMaterial3d(materials.add(StandardMaterial {
                base_color: Color::srgb(0.1, 0.7, 0.2),
                emissive: LinearRgba::rgb(0.1, 1.6, 0.3),
                ..default()
            })),
            Transform::from_xyz(-1.0 + i as f32, 0.5, 0.0),
            DespawnOnExit(GameFlow::Level),
            jackdaw_avian_integration::AvianCollider(
                avian3d::prelude::ColliderConstructor::Sphere {
                    radius: 0.35,
                },
            ),
            // The trigger: detects, does not block. The bridge adds
            // the event prerequisite avian asks for.
            avian3d::prelude::Sensor,
        ));
    }
}

/// Two walls at right angles on the stage: something solid to walk
/// into. `move_player`'s sweep does the rest — walk at the north wall
/// (ahead of the spawn) head-on and stop; walk at it diagonally and
/// slide along it. Static, like the stage: a collider with no rigid
/// body stands still.
fn spawn_walls(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let wall = materials.add(StandardMaterial {
        base_color: Color::srgb(0.45, 0.4, 0.35),
        ..default()
    });
    for (x, z, x_length, z_length) in [(0.0, -3.0, 12.0, 0.4), (-4.0, 0.0, 0.4, 8.0)] {
        commands.spawn((
            Mesh3d(meshes.add(Cuboid::new(x_length, 1.5, z_length))),
            MeshMaterial3d(wall.clone()),
            Transform::from_xyz(x, 0.75, z),
            DespawnOnExit(GameFlow::Level),
            jackdaw_avian_integration::AvianCollider(
                avian3d::prelude::ColliderConstructor::Cuboid {
                    x_length,
                    y_length: 1.5,
                    z_length,
                },
            ),
        ));
    }
}

/// The pickup pattern itself: when the *player* starts touching a
/// `Pickup`, the pickup goes away and the count goes up; the third
/// one wins the run — the flow moves to the game-over screen, the
/// very move blood-out makes, so the end screen and its Restart are
/// the win's way out too. The other side of the contact is checked
/// on purpose — a prop merely settling onto a pickup (the falling
/// cube landing on one) must not collect it. Swap `Pickup` for your
/// own marker and this is a coin, a key, a landmine — whatever a
/// walk-over should do.
fn collect_pickups(
    triggers: Res<TriggerEvents>,
    pickups: Query<(), With<Pickup>>,
    mut players: Query<&mut PickupCount, With<PlayerMarker>>,
    mut flow: ResMut<NextState<GameFlow>>,
    mut commands: Commands,
    server: Res<AssetServer>,
) {
    let mut collected = 0u32;
    for contact in triggers.enters() {
        if pickups.contains(contact.trigger) && players.contains(contact.other) {
            commands.entity(contact.trigger).despawn();
            collected += 1;
        }
    }
    if collected == 0 {
        return;
    }
    let Ok(mut count) = players.single_mut() else {
        return;
    };
    count.0 += collected;
    if count.0 >= 3 {
        info!("Level clear! All {} pickups collected.", count.0);
        // The win acknowledges itself with the button blip: the same
        // one-shot `press_sound` sends, riding the sfx bus and taking
        // itself down when it ends.
        commands.spawn((
            AudioPlayer::<AudioSource>(server.load(BLIP_SOUND)),
            PlaybackSettings::DESPAWN,
            SfxBus,
        ));
        flow.set(GameFlow::GameOver);
    }
}

/// Hand the config's gravity number to the engine: `GameConfig` is
/// the saved author's truth, the engine's `Gravity` resource is what
/// the simulation reads. Runs whenever the config changes, so a
/// re-load mid-run (the editor's config panel) carries over too.
fn apply_gravity_from_config(
    config: Res<GameConfig>,
    mut gravity: ResMut<avian3d::prelude::Gravity>,
) {
    if config.is_changed() {
        gravity.0 = Vec3::new(0.0, config.gravity, 0.0);
    }
}

/// A thing that hurts to touch: a glowing red sensor on the walk
/// line. Carries the collision-layer row the docs' table gives
/// hazards (member of layer 3, filtered against layer 1), so its
/// contacts exist with the player and nothing else — the pickups and
/// walls it passes never feel it.
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default, @EditorCategory::new("Actor"))]
pub struct Hazard;

fn spawn_hazards(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    commands.spawn((
        Hazard,
        Mesh3d(meshes.add(Cuboid::new(0.4, 0.4, 0.4))),
        MeshMaterial3d(materials.add(StandardMaterial {
            base_color: Color::srgb(0.8, 0.1, 0.1),
            emissive: LinearRgba::rgb(1.2, 0.1, 0.1),
            ..default()
        })),
        Transform::from_xyz(2.0, 0.5, 0.0),
        DespawnOnExit(GameFlow::Level),
        jackdaw_avian_integration::AvianCollider(
            avian3d::prelude::ColliderConstructor::Sphere {
                radius: 0.35,
            },
        ),
        avian3d::prelude::Sensor,
        // The docs' hazard row, live: `memberships 0b100, filters
        // 0b001` — hazard hits the player only.
        avian3d::prelude::CollisionLayers::new(
            avian3d::prelude::LayerMask(0b100),
            avian3d::prelude::LayerMask(0b001),
        ),
    ));
}

/// The hazard pattern, the other half of `collect_pickups`: when the
/// *player* starts touching a `Hazard`, health drops (`take_damage`,
/// in the game-flow section above) and the hud's bar follows the
/// component. `enters()` fires when the overlap starts, not every
/// frame — walk out and back in to take it again. Nothing fires outside
/// a run: the same `GameFlow`/`paused` gate as the movement system.
fn hazard_damage(
    triggers: Res<TriggerEvents>,
    flow: Res<State<GameFlow>>,
    state: Res<GameState>,
    hazards: Query<(), With<Hazard>>,
    mut players: Query<&mut PlayerHealth, With<PlayerMarker>>,
) {
    if flow.get() != &GameFlow::Level || state.paused {
        return;
    }
    for contact in triggers.enters() {
        if hazards.contains(contact.trigger) && players.contains(contact.other) {
            if let Ok(mut health) = players.single_mut() {
                take_damage(&mut health, PLAYER_DAMAGE);
            }
        }
    }
}

/// The counter half of a restart: the level entry despawned nothing of
/// the player's — the player crossed the switch — so the run's numbers
/// are put back here instead. (The health and the spawn point are the
/// game-flow section's `reset_run`; this is the pickup-and-velocity
/// half, which only exists with the physics module.) Runs on every
/// entry into the level, so Restart is just a switch to `Level`.
fn reset_run_counters(
    mut players: Query<(&mut PickupCount, &mut PlayerVelocity), With<PlayerMarker>>,
) {
    for (mut count, mut velocity) in &mut players {
        count.0 = 0;
        velocity.0 = Vec3::ZERO;
    }
}
"#
    .to_string()
}

/// The template header's tilemap section: the module teaches a 2D half —
/// tile-grid levels authored in the editor, resolved here with the
/// collision kernel. Emitted only with the module: a game without it
/// should not carry prose about tooling it did not ask for.
fn module_tilemap_doc(modules: &ModuleSet) -> String {
    if !modules.contains("tilemap") {
        return String::new();
    }
    r#"//!
//! # Tilemap & 2D collision
//!
//! The tilemap module adds a 2D half to this 3D template: tile-grid
//! levels authored in jackdaw (the Tilemap tool — T on the keyboard —
//! with a palette that paints, erases and fills cells into layers),
//! and here in the template, the running half. Every tilemap layer of
//! the loaded scene becomes a collision grid, and a red probe body
//! walks it: gravity pulls, floors hold, walls stop, trigger cells
//! report. `collect_level_grid`, `apply_walk_input`, `resolve_probe`
//! and `census_triggers` below are the whole pattern — swap the probe
//! for your own player and keep the loop: read input, resolve with
//! `move_probe`, census the triggers.
"#
    .to_string()
}

/// The tilemap module's line in `GamePlugin::build`: the plugin the
/// player section below defines. Empty without the module.
fn module_tilemap_collision(modules: &ModuleSet) -> String {
    if !modules.contains("tilemap") {
        return String::new();
    }
    [
        "        // Tilemap & the 2D probe (the docs at the top walk the
",
        "        // pattern): the scene's tile layers become a collision grid
",
        "        // and the probe body below walks it with the kernel's sweep.
",
        "        app.add_plugins(TilemapProbePlugin);
",
    ]
    .concat()
}

/// The tilemap module's teaching section, the player-probe pattern: the
/// scene's tilemap layers become one collision grid, the probe walks it
/// with `move_probe`, and the trigger census reports crossings. Empty
/// without the module.
fn module_tilemap_player(modules: &ModuleSet) -> String {
    if !modules.contains("tilemap") {
        return String::new();
    }
    r#"// ---- Tilemap & 2D collision: the probe body ----------------------
// The scene's tilemap layers (edited in jackdaw with the Tilemap
// tool) become one collision grid; a 2D probe body walks it. The
// three-step loop a tilemap game lives on: read the input, resolve
// the move with `move_probe`, census the trigger cells.

use jackdaw_runtime::{TileCollisionMode, TileGridCell, TilemapLayer};
use jackdaw_tilemap_collision::{CollisionMode, Probe, TileGrid, move_probe};

/// The layer-to-grid teaching numbers. A fixed step keeps the walk
/// deterministic — swap in `Res<Time>` if you prefer wall-clock pace.
const PROBE_DT: f32 = 1.0 / 60.0;
const PROBE_GRAVITY: f32 = 900.0;
const PROBE_WALK: f32 = 120.0;
/// The probe draws in front of the tiles (tile z comes from the layer).
const PROBE_Z: f32 = 100.0;

/// Everything the tilemap module adds to the game: the grid and the
/// probe body. The 2D camera (order 1) draws the tilemap world over
/// the 3D view, so the level is visible whatever the flow shows.
struct TilemapProbePlugin;

impl Plugin for TilemapProbePlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<LevelGrid>()
            .init_resource::<TriggerCensus>()
            .register_type::<TriggerCensus>()
            .add_systems(Startup, spawn_tilemap_probe)
            .add_systems(
                Update,
                (
                    collect_level_grid,
                    // Chained: input integrates forces onto the probe, the
                    // kernel resolves them, the census reads the result.
                    (apply_walk_input, resolve_probe, census_triggers).chain(),
                    sync_probe_sprite,
                ),
            );
    }
}

/// The collision grid the scene's tilemap layers become. `None` until a
/// layer with tiles has loaded — the scene loads async after boot.
#[derive(Resource, Default)]
struct LevelGrid(Option<TileGrid>);

/// The 2D probe body: a kernel `Probe` (centre, half extents, velocity,
/// grounded latch) wearing a colored square. The prototype of a player —
/// swap it for yours and keep the loop below.
#[derive(Component)]
struct PlayerProbe {
    body: Probe,
}

/// The trigger cells under the probe this frame, plus whether any
/// crossing happened at all — the prototype of the flip a real game
/// turns into an event or a counter. Registered for reflection, so
/// tooling can read it while the game runs.
#[derive(Resource, Default, Reflect)]
#[reflect(Resource)]
struct TriggerCensus {
    inside: usize,
    crossed: bool,
}

/// Spawn the probe and its orthographic camera, once at boot.
fn spawn_tilemap_probe(mut commands: Commands) {
    commands.spawn((Name::new("Tilemap Camera"), Camera2d, Camera {
        order: 1,
        ..default()
    }));
    commands.spawn((
        Name::new("Player Probe"),
        PlayerProbe {
            body: Probe {
                center: Vec2::new(96.0, 160.0),
                half_size: Vec2::splat(12.0),
                velocity: Vec2::ZERO,
                grounded: false,
            },
        },
        Sprite::from_color(Color::srgb(0.9, 0.3, 0.3), Vec2::splat(24.0)),
        Transform::from_xyz(96.0, 160.0, PROBE_Z),
    ));
}

/// Rebuild the grid when the scene's tilemap faces change: layers or
/// tiles arriving (the scene loads async), leaving or being edited. One
/// kernel grid spans every layer; a cell goes to the layer with the
/// highest draw order that authors it. The lowest layer anchors the
/// grid's origin, so keep layers aligned (a layer moved off-grid in the
/// editor snaps its tiles to the nearest grid cell here).
fn collect_level_grid(
    layers_changed: Query<
        (),
        (
            With<TilemapLayer>,
            Or<(Added<TilemapLayer>, Changed<TilemapLayer>)>,
        ),
    >,
    cells_changed: Query<
        (),
        (
            With<TileGridCell>,
            Or<(Added<TileGridCell>, Changed<TileGridCell>)>,
        ),
    >,
    layers: Query<(&TilemapLayer, &TileCollisionMode, &GlobalTransform, Entity)>,
    tiles: Query<(&TileGridCell, &ChildOf)>,
    mut level: ResMut<LevelGrid>,
) {
    if layers_changed.is_empty() && cells_changed.is_empty() {
        return;
    }
    let mut forms: Vec<_> = layers.iter().collect();
    if forms.is_empty() {
        level.0 = None;
        return;
    }
    // Draw order low to high: a higher layer's cell wins.
    forms.sort_by_key(|(layer, _, _, entity)| (layer.order, *entity));
    let width = forms.iter().map(|(layer, ..)| layer.columns).max().unwrap_or(1);
    let height = forms.iter().map(|(layer, ..)| layer.rows).max().unwrap_or(1);
    let (_, _, base_global, _) = forms[0];
    let origin = base_global.translation().truncate();
    let cell = forms[0].0.cell_size.x.max(1.0);
    let mut grid = TileGrid::new(origin, cell, width, height);
    for (layer, mode, global, entity) in forms {
        let cell_mode = match mode {
            TileCollisionMode::Passable => CollisionMode::Passable,
            TileCollisionMode::Solid => CollisionMode::Solid,
            TileCollisionMode::Trigger => CollisionMode::Trigger,
        };
        let layer_origin = global.translation().truncate();
        let offset_x = ((layer_origin.x - origin.x) / cell).round() as i32;
        let offset_y = ((layer_origin.y - origin.y) / cell).round() as i32;
        for (tile, parent) in tiles
            .iter()
            .filter(|(_, parent)| parent.parent() == entity)
        {
            if tile.cell.x < 0
                || tile.cell.y < 0
                || tile.cell.x >= layer.columns as i32
                || tile.cell.y >= layer.rows as i32
            {
                continue;
            }
            let gx = tile.cell.x + offset_x;
            let gy = tile.cell.y + offset_y;
            if gx < 0 || gy < 0 || gx >= width as i32 || gy >= height as i32 {
                continue;
            }
            grid.set(IVec2::new(gx, gy), cell_mode);
        }
    }
    level.0 = Some(grid);
}

/// Step one: gravity onto the probe, the Move action's x onto the walk.
/// Runs inside a level only — the same gate `move_player` keeps.
fn apply_walk_input(
    actions: Res<GameActions>,
    flow: Res<State<GameFlow>>,
    state: Res<GameState>,
    mut probes: Query<&mut PlayerProbe>,
) {
    if flow.get() != &GameFlow::Level || state.paused {
        return;
    }
    let walk = actions.value("Move").x * PROBE_WALK;
    for mut probe in &mut probes {
        probe.body.velocity.x = walk;
        probe.body.velocity.y -= PROBE_GRAVITY * PROBE_DT;
    }
}

/// Step two: the kernel resolves the move against the grid's solid
/// cells — floors hold, walls clamp with a separation gap, triggers
/// pass. A missing grid (no tilemap in the scene yet) lets the probe
/// idle.
fn resolve_probe(
    level: Res<LevelGrid>,
    flow: Res<State<GameFlow>>,
    state: Res<GameState>,
    mut probes: Query<&mut PlayerProbe>,
) {
    if flow.get() != &GameFlow::Level || state.paused {
        return;
    }
    let Some(grid) = level.0.as_ref() else {
        return;
    };
    for mut probe in &mut probes {
        let outcome = move_probe(grid, &probe.body, PROBE_DT);
        probe.body.center = outcome.center;
        probe.body.velocity = outcome.velocity;
        probe.body.grounded = outcome.grounded;
    }
}

/// Step three: which trigger cells the probe overlaps, and whether the
/// run has crossed one at all. Log the first crossing so a fresh game
/// says so out loud.
fn census_triggers(
    level: Res<LevelGrid>,
    flow: Res<State<GameFlow>>,
    state: Res<GameState>,
    probes: Query<&PlayerProbe>,
    mut census: ResMut<TriggerCensus>,
) {
    if flow.get() != &GameFlow::Level || state.paused {
        return;
    }
    let Some(grid) = level.0.as_ref() else {
        return;
    };
    let Ok(probe) = probes.single() else {
        return;
    };
    let bounds = jackdaw_tilemap_collision::Aabb::from_center_half(
        probe.body.center,
        probe.body.half_size,
    );
    census.inside = grid.trigger_cells_overlapping(&bounds).count();
    if census.inside > 0 && !census.crossed {
        info!("Tilemap: the probe walked into a trigger cell!");
    }
    census.crossed |= census.inside > 0;
}

/// Put the probe's sprite where the kernel left the body: what you see
/// is what collides.
fn sync_probe_sprite(
    mut sprites: Query<(&mut Transform, &PlayerProbe), Without<TilemapLayer>>,
) {
    for (mut transform, probe) in &mut sprites {
        transform.translation = probe.body.center.extend(PROBE_Z);
    }
}
"#
    .to_string()
}

/// How a scaffolded project asks for one of the public jackdaw crates: the
/// registry line for a released editor, the exact revision for one built from
/// git, the workspace crate for one built from a checkout. A version
/// requirement alone would not resolve for a git-installed editor.
fn jackdaw_dep_requirement(crate_name: &str) -> String {
    jackdaw_project_build::build_source::build_source().dep_requirement(crate_name)
}

/// Title-case a kebab/snake name: `my-cool-game` becomes `My Cool Game`.
fn title_case(name: &str) -> String {
    name.split(['-', '_'])
        .filter(|w| !w.is_empty())
        .map(|w| {
            let mut chars = w.chars();
            match chars.next() {
                Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// `name <email>` from git config, or an empty string when unavailable.
fn git_authors() -> String {
    let field = |key: &str| {
        jackdaw_env::without_console_window(&mut std::process::Command::new("git"))
            .args(["config", key])
            .output()
            .ok()
            .filter(|o| o.status.success())
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .filter(|s| !s.is_empty())
    };
    match (field("user.name"), field("user.email")) {
        (Some(name), Some(email)) => format!("{name} <{email}>"),
        (Some(name), None) => name,
        _ => String::new(),
    }
}

/// A usable crate/dir name from arbitrary input: lowercased, spaces
/// and underscores to dashes, everything else alphanumeric. Runs of
/// separators collapse, so `My  Cool_Game!` becomes `my-cool-game`.
pub fn sanitize_project_name(raw: &str) -> String {
    let mut out = String::new();
    for c in raw.trim().chars() {
        match c {
            ' ' | '_' | '-' if !out.ends_with('-') => out.push('-'),
            ' ' | '_' | '-' => {}
            c if c.is_ascii_alphanumeric() => out.push(c.to_ascii_lowercase()),
            _ => {}
        }
    }
    out.trim_matches('-').to_string()
}

/// Rust keywords a crate name cannot be: the templates paste the crate
/// name straight into `use`/path position, so one of these would not
/// compile.
const RESERVED_CRATE_NAMES: [&str; 55] = [
    "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern",
    "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub",
    "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type",
    "unsafe", "use", "where", "while", "abstract", "become", "box", "do", "final", "macro",
    "override", "priv", "try", "typeof", "unsized", "virtual", "yield", "gen", "test", "main",
    "std",
];

/// Sanitize `raw` and confirm the result is usable as both a directory
/// and a Rust crate name. The two scaffolding entry points (the CLI and
/// the launcher modal) share this so they reject the same inputs with
/// the same message.
pub fn validated_project_name(raw: &str) -> Result<String, ScaffoldError> {
    // A path is not a name: `jd new E:\games\my-game` would otherwise
    // sanitize to a mangled directory name created wherever the shell
    // happens to be, and the user finds out from a wrong path, not a
    // message. Say where the path belongs instead.
    if raw.contains(['/', '\\']) || Path::new(raw).file_name().is_some_and(|name| name != raw) {
        return Err(ScaffoldError::ProjectName {
            raw: raw.to_string(),
            reason: "a name cannot be a path; pass the directory with --path and only the \
                     name here",
        });
    }
    let name = sanitize_project_name(raw);
    let reject = |reason| {
        Err(ScaffoldError::ProjectName {
            raw: raw.to_string(),
            reason,
        })
    };
    if name.is_empty() {
        // A name of entirely non-ASCII characters sanitizes to nothing.
        // Cargo package names are ASCII, so say that rather than
        // implying the input was empty.
        return if raw.trim().is_empty() {
            reject("enter a name")
        } else {
            reject("cargo package names use ASCII letters, digits, and dashes")
        };
    }
    if name.starts_with(|c: char| c.is_ascii_digit()) {
        return reject("a crate name cannot start with a digit");
    }
    let crate_name = name.replace('-', "_");
    if RESERVED_CRATE_NAMES.contains(&crate_name.as_str()) {
        return reject("that is a reserved Rust name");
    }
    Ok(name)
}

// `detect_extension` / `detect_plugin` moved to the bevy-light build
// pipeline crate (they are pure source scanning the shim builder needs);
// re-exported here at their historical path.
pub(crate) use jackdaw_project_build::detect::detect_plugin;

#[cfg(test)]
mod tests {
    /// A fixture manifest on the Bevy this build supports: its `bevy = "0.20"`
    /// lines ask for whatever this build would scaffold.
    fn with_bevy(text: &str) -> String {
        text.replace(
            "bevy = \"0.20\"",
            &format!(
                "bevy = {}",
                jackdaw_project_build::bevy_source::dependency()
            ),
        )
    }

    use super::*;

    fn temp_dir(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("jackdaw_scaffold_{name}_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn the_2d_starter_scene_is_a_2d_scene_that_keeps_its_camera() {
        let dest = temp_dir("starter_2d");
        std::fs::create_dir_all(dest.join("assets")).unwrap();

        write_starter_scene(&dest, StarterScene::TwoD).unwrap();

        let scene = std::fs::read_to_string(dest.join("assets/scene.bsn")).unwrap();
        let root = scene.split("bevy_ecs::hierarchy::Children").next().unwrap();
        assert!(
            root.contains("jackdaw_scene_types::Scene2dRoot"),
            "the root says the scene is 2D:\n{scene}"
        );
        assert!(
            scene.contains("bevy_camera::components::Camera2d"),
            "{scene}"
        );
        let _ = std::fs::remove_dir_all(&dest);
    }

    #[test]
    fn a_project_inside_a_workspace_that_stops_resolving_is_warned_about() {
        let outer = temp_dir("broken_workspace");
        std::fs::write(outer.join("Cargo.toml"), "[workspace]\nmembers = [\"*\"]\n").unwrap();
        let dest = outer.join("games").join("my-game");
        std::fs::create_dir_all(&dest).unwrap();

        let warnings = check_new_project_with(&dest, |root| {
            if root == outer {
                Err("error: multiple workspace roots found".to_string())
            } else {
                Ok(())
            }
        });

        assert_eq!(
            warnings,
            vec![NewProjectWarning::EnclosingWorkspaceBroken {
                project: dest.clone(),
                workspace: outer.clone(),
                detail: "error: multiple workspace roots found".to_string(),
            }]
        );
        let fix = warnings[0].fix();
        assert!(fix.contains("exclude = [\"games/my-game\"]"), "got:\n{fix}");
        assert!(!warnings[0].summary().contains('`'));
        let _ = std::fs::remove_dir_all(&outer);
    }

    #[test]
    fn a_project_in_a_clean_location_has_no_warnings() {
        let location = temp_dir("clean_location");
        let dest = location.join("my-game");
        std::fs::create_dir_all(&dest).unwrap();

        assert!(enclosing_workspace(&dest).is_none());
        assert!(check_new_project_with(&dest, |_| Ok(())).is_empty());
        let _ = std::fs::remove_dir_all(&location);
    }

    #[test]
    fn a_project_whose_dependencies_do_not_resolve_is_warned_about() {
        let location = temp_dir("unresolved");
        let dest = location.join("my-game");
        std::fs::create_dir_all(&dest).unwrap();

        let warnings = check_new_project_with(&dest, |_| {
            Err("error: failed to select a version for `jackdaw_runtime`".to_string())
        });

        assert!(
            matches!(
                warnings.as_slice(),
                [NewProjectWarning::DependenciesUnresolved { project, .. }] if *project == dest
            ),
            "got: {warnings:?}"
        );
        assert!(
            warnings[0]
                .summary()
                .contains(&jackdaw_source_description()),
            "the summary names where the crates were looked for: {}",
            warnings[0].summary()
        );
        assert_eq!(
            warnings[0].cargo_error(),
            "error: failed to select a version for `jackdaw_runtime`"
        );
        let _ = std::fs::remove_dir_all(&location);
    }

    #[test]
    fn upgrade_pins_a_prerelease_editor_to_its_exact_version() {
        let requirement = jackdaw_project_build::jackdaw_requirement_for("0.19.0-rc.1");
        let cargo = "[dependencies]\njackdaw_runtime = \"0.19\"\n\
                     jackdaw_extension = { version = \"0.19\", features = [\"physics\"] }\n";
        let out = bump_jackdaw_requirements(cargo, &requirement).expect("changed");
        assert!(
            out.contains("jackdaw_runtime = \"=0.19.0-rc.1\""),
            "got:\n{out}"
        );
        assert!(out.contains("version = \"=0.19.0-rc.1\""), "got:\n{out}");

        let stable = jackdaw_project_build::jackdaw_requirement_for("0.19.0");
        let back = bump_jackdaw_requirements(&out, &stable).expect("changed");
        assert_eq!(back.matches("\"0.19\"").count(), 2, "got:\n{back}");
    }

    #[test]
    fn new_game_project_has_the_contract_files() {
        let dest = temp_dir("newgame").join("my-game");
        scaffold_new_project(&dest, "my-game", TemplateKind::Game).unwrap();
        assert!(dest.join("Cargo.toml").is_file());
        assert!(dest.join("src/lib.rs").is_file());
        assert!(dest.join("src/main.rs").is_file());
        assert!(dest.join("assets/scene.bsn").is_file());
        assert!(dest.join("assets/menu.bsn").is_file());
        assert!(dest.join("assets/gameover.bsn").is_file());
        assert!(dest.join("assets/hud.bsn").is_file());
        assert!(dest.join("assets/game.flow.json").is_file());
        assert!(dest.join("jackdaw.toml").is_file());
        assert!(dest.join(".gitignore").is_file());
        let manifest = std::fs::read_to_string(dest.join("Cargo.toml")).unwrap();
        assert!(manifest.contains("name = \"my-game\""));
        assert!(!manifest.contains("crate-type"));
        assert!(!manifest.contains("[features]"));
        let lib = std::fs::read_to_string(dest.join("src/lib.rs")).unwrap();
        assert!(lib.contains("pub struct GamePlugin"));
        assert!(!lib.contains("{{"));
        let main = std::fs::read_to_string(dest.join("src/main.rs")).unwrap();
        assert!(
            main.contains("DefaultPlugins.set(jackdaw_runtime::image_plugin())"),
            "the game reads the project's 2D sampling: {main}"
        );
    }

    /// The templates state the whole jackdaw requirement rather than a
    /// version, because a version is only resolvable for a build that was
    /// released. Whichever form this build calls for is what a scaffolded
    /// manifest must end up carrying, and nothing may be left unfilled.
    #[test]
    fn the_templates_state_the_requirement_this_build_can_resolve() {
        for (path, dep) in [
            ("templates/game/Cargo.toml.template", "jackdaw_runtime"),
            (
                "templates/extension/Cargo.toml.template",
                "jackdaw_extension",
            ),
        ] {
            let template =
                std::fs::read_to_string(format!("{}/{path}", env!("CARGO_MANIFEST_DIR")))
                    .unwrap_or_else(|e| panic!("read {path}: {e}"));
            let filled = substitute_placeholders(
                &template,
                "my-game",
                "my_game",
                "",
                "My Game",
                &ModuleCatalog::builtin().defaults(),
            );
            assert!(
                !filled.contains("{{"),
                "{path}: every placeholder is filled, got: {filled}"
            );
            let line = filled
                .lines()
                .find(|line| line.trim_start().starts_with(dep))
                .unwrap_or_else(|| panic!("{path}: no {dep} dependency"));
            assert!(
                line.contains(&jackdaw_dep_requirement(dep)),
                "{path}: {dep} must state what this build can resolve, got: {line}"
            );
        }
    }

    #[test]
    fn new_extension_project_uses_the_api() {
        let dest = temp_dir("newext").join("my-ext");
        scaffold_new_project(&dest, "my-ext", TemplateKind::Extension).unwrap();
        let manifest = std::fs::read_to_string(dest.join("Cargo.toml")).unwrap();
        assert!(manifest.contains("jackdaw_extension"));
        let lib = std::fs::read_to_string(dest.join("src/lib.rs")).unwrap();
        assert!(lib.contains("JackdawExtension"));
    }

    /// A new game starts from this workspace's own lock, so its first
    /// resolve inherits the bevy/wgpu/windows tree this jackdaw was
    /// verified against instead of whatever the registry serves today
    /// (the fresh-lock drift that broke every new project's editor
    /// prebuild in a bad upstream window).
    #[test]
    fn a_new_game_carries_the_workspace_lock_snapshot() {
        let dest = temp_dir("newgame-lock").join("my-game");
        scaffold_new_project(&dest, "my-game", TemplateKind::Game).unwrap();
        let lock = std::fs::read_to_string(dest.join("Cargo.lock"))
            .expect("a new game project carries a Cargo.lock");
        assert_eq!(
            lock,
            workspace_lock_snapshot(),
            "the file is this workspace's lock verbatim, not a fresh resolve"
        );
        // The resolve step after scaffolding must be a prune-and-add on
        // this snapshot, not a re-resolve: cargo keeps already-locked
        // versions when the manifest admits them. That property is what
        // makes the seeded lock worth carrying; the editor's first
        // `--locked` build then passes on the first try. (Live behavior
        // is pinned by the real-machine leg, `loop/qa`.)
    }

    /// A path is not a project name: `jd new E:\games\my-game` used to
    /// sanitize into a mangled directory created in whatever directory
    /// the shell was in — silent, wrong, and nowhere near the message
    /// that would have helped.
    #[test]
    fn a_project_name_that_is_really_a_path_is_refused_with_guidance() {
        for raw in ["E:\\games\\my-game", "/home/me/my-game", "games/my-game"] {
            let error = validated_project_name(raw).expect_err("a path is not a name");
            assert!(
                error.to_string().contains("--path"),
                "{raw}: the refusal points at --path: {error}"
            );
        }
    }

    /// The game template teaches the config-asset pattern: a type that
    /// is both Asset and Resource, the registration lines that make the
    /// editor offer it, the one-line loader plugin, and a consumer —
    /// so every new project ships with the tuning-parameters path in
    /// place.
    #[test]
    fn new_game_project_teaches_the_config_pattern() {
        let dest = temp_dir("newgame-config").join("my-game");
        scaffold_new_project(&dest, "my-game", TemplateKind::Game).unwrap();
        let lib = std::fs::read_to_string(dest.join("src/lib.rs")).unwrap();
        for needle in [
            "struct GameConfig",
            "Asset, Resource, Reflect",
            "player_health",
            "move_speed",
            "gravity",
            "init_asset::<GameConfig>()",
            "register_asset_reflect::<GameConfig>()",
            "ConfigPlugin::<GameConfig>::default()",
            "falling_cubes",
            "Tuning parameters",
        ] {
            assert!(
                lib.contains(needle),
                "the template must teach `{needle}`; the config pattern drifted"
            );
        }
    }

    /// The game template teaches the input-action pattern the same way:
    /// the action table asset, the evaluation plugin, and a consumer
    /// reading named actions — plus the capture model note, without
    /// which a game binding Escape reads as eaten by the editor.
    #[test]
    fn new_game_project_teaches_the_input_action_pattern() {
        let dest = temp_dir("newgame-input").join("my-game");
        scaffold_new_project(&dest, "my-game", TemplateKind::Game).unwrap();
        let lib = std::fs::read_to_string(dest.join("src/lib.rs")).unwrap();
        for needle in [
            "init_asset::<GameInputConfig>()",
            "register_asset_reflect::<GameInputConfig>()",
            "InputActionsPlugin",
            "input-actions.bsn",
            "GameActions",
            "struct PlayerMarker",
            "actions.value(\"Move\")",
            "just_pressed(\"Jump\")",
            "Shift+Esc",
            "Input actions",
        ] {
            assert!(
                lib.contains(needle),
                "the template must teach `{needle}`; the input pattern drifted"
            );
        }
    }

    /// The game template teaches the audio pattern (T16): the three-way
    /// mix config authored as an asset, the bus markers, the mix systems
    /// that build and refresh each sink's real volume, the `SoundLive`
    /// mirror that makes playing sounds inspectable, the one-shot button
    /// blip — and the shipped wav files plus a bevy dependency that can
    /// decode them, so the menu has its BGM before the author adds
    /// anything.
    #[test]
    fn new_game_project_teaches_the_audio_pattern() {
        let dest = temp_dir("newgame-audio").join("my-game");
        scaffold_new_project(&dest, "my-game", TemplateKind::Game).unwrap();
        let lib = std::fs::read_to_string(dest.join("src/lib.rs")).unwrap();
        for needle in [
            "struct GameAudioConfig",
            "init_asset::<GameAudioConfig>()",
            "register_asset_reflect::<GameAudioConfig>()",
            "ConfigPlugin::<GameAudioConfig>::new(\"audio-config.bsn\")",
            "struct MusicBus",
            "struct SfxBus",
            "struct SoundLive",
            "fn mix_volume",
            "fn apply_audio_mix",
            "fn apply_audio_mix_to_new_sinks",
            "fn mirror_sound_live",
            "fn press_sound",
            "sounds/blip.wav",
            "SpatialListener::default()",
            "Game audio",
        ] {
            assert!(
                lib.contains(needle),
                "the template must teach `{needle}`; the audio pattern drifted"
            );
        }
        // The scenes ship playing entities, spelled with the full generic
        // type path bsn requires, and the sounds they name are real files.
        let menu = std::fs::read_to_string(dest.join("assets/menu.bsn")).unwrap();
        for needle in [
            "bevy_audio::audio::AudioPlayer<bevy_audio::audio_source::AudioSource>(\"sounds/bgm.wav\")",
            "bevy_audio::audio::PlaybackMode::Loop",
            "MusicBus",
        ] {
            assert!(
                menu.contains(needle),
                "the menu scene must teach `{needle}`; the BGM drifted"
            );
        }
        let scene = std::fs::read_to_string(dest.join("assets/scene.bsn")).unwrap();
        assert!(
            scene.contains("bevy_audio::audio::PlaybackSettings")
                && scene.contains("spatial: true"),
            "the level scene must teach the spatial ambient; the scene drifted"
        );
        for sound in ["bgm.wav", "blip.wav", "ambient.wav"] {
            let path = dest.join("assets/sounds").join(sound);
            assert!(
                path.is_file(),
                "the template ships `{sound}` so audio works with zero user assets"
            );
        }
        let cargo = std::fs::read_to_string(dest.join("Cargo.toml")).unwrap();
        assert!(
            cargo.contains("features = [\"wav\"]"),
            "the game decodes the shipped wav files; the bevy dependency drifted:\n{cargo}"
        );
    }

    /// The game template teaches the save pattern (T17): a player
    /// profile (`GameSave`: progress, unlocks, audio, input) wired
    /// through the runtime's `SavePlugin`, two bridges that restore
    /// the saved settings over the authored config defaults, two
    /// watchers that persist the player's changes, the run counter at
    /// game over — and the settings face: the pause screen's three
    /// volume sliders writing `GameAudioConfig` through a
    /// `ValueChange` observer, and the menu reading the run counter.
    #[test]
    fn new_game_project_teaches_the_save_pattern() {
        let dest = temp_dir("newgame-save").join("my-game");
        scaffold_new_project(&dest, "my-game", TemplateKind::Game).unwrap();
        let lib = std::fs::read_to_string(dest.join("src/lib.rs")).unwrap();
        for needle in [
            "struct GameSave",
            "struct GameProgress",
            "struct AudioPrefs",
            "SavePlugin::<GameSave>::new(env!(\"CARGO_PKG_NAME\"))",
            "register_type::<ValueChange<f32>>()",
            "register_type::<FeathersSlider>()",
            "fn apply_saved_audio",
            "fn save_audio_changes",
            "fn apply_saved_input",
            "fn save_input_changes",
            "fn count_run_over",
            "fn mirror_save_display",
            "fn attach_volume_sliders",
            "fn on_volume_changed",
            "fn sync_volume_sliders",
            "spawn_scene(bsn! { @FeathersSlider })",
            "struct MasterVolumeSlider",
            "ConfigLoader<GameAudioConfig>",
            "merge_actions(&config.actions, saved)",
            "Saving progress and settings",
        ] {
            assert!(
                lib.contains(needle),
                "the template must teach `{needle}`; the save pattern drifted"
            );
        }
        // The save profile carries serde derives, so the manifest must
        // name serde itself (the runtime's copy does not leak through).
        let cargo = std::fs::read_to_string(dest.join("Cargo.toml")).unwrap();
        assert!(
            cargo.contains("serde = { version = \"1\", features = [\"derive\"] }"),
            "the game's manifest must carry serde's derive for the save profile:\n{cargo}"
        );
        // The settings face is authored: the pause screen carries the
        // three themed sliders, and the menu and game-over documents
        // read the run counter from the GameState mirror.
        let hud = std::fs::read_to_string(dest.join("assets/hud.bsn")).unwrap();
        for needle in ["MasterVolumeSlider", "MusicVolumeSlider", "SfxVolumeSlider"] {
            assert!(
                hud.contains(needle),
                "the hud document must teach `{needle}`; the pause screen drifted"
            );
        }
        let menu = std::fs::read_to_string(dest.join("assets/menu.bsn")).unwrap();
        assert!(
            menu.contains("Res(my_game::GameState).runs_played"),
            "the menu must read the run counter from the mirror; the menu drifted:\n{menu}"
        );
        let gameover = std::fs::read_to_string(dest.join("assets/gameover.bsn")).unwrap();
        assert!(
            gameover.contains("Res(my_game::GameState).runs_played"),
            "the game-over document must read the run counter; the document drifted"
        );
    }

    /// The physics module (on by default) shapes the template around
    /// its own teaching: the trigger bridge, the pickup demo, the
    /// collision-layer table, the gravity handoff, and a physical
    /// falling cube and player. Without the module all of that
    /// withdraws and the manual fall the template predates physics
    /// with stands back in.
    #[test]
    fn new_game_project_teaches_the_physics_and_trigger_pattern() {
        let dest = temp_dir("newgame-triggers").join("my-game");
        scaffold_new_project(&dest, "my-game", TemplateKind::Game).unwrap();
        let lib = std::fs::read_to_string(dest.join("src/lib.rs")).unwrap();
        for needle in [
            "jackdaw_avian_integration::TriggerPlugin",
            "triggers.enters()",
            "struct Pickup",
            "PickupCount",
            "players.contains(contact.other)",
            "Level clear",
            // The win is a flow move, not just a log line (T20/EG1):
            // `flow.set` spells it here because `update_game_over`
            // transitions through `next.set` — this anchor pins the
            // pickup arm's own move to the game-over screen.
            "flow.set(GameFlow::GameOver)",
            "CollisionLayers",
            "memberships 0b100",
            "apply_gravity_from_config",
            "RigidBody::Dynamic",
            "RigidBody::Kinematic",
            "ColliderConstructor::Capsule",
            "Two gravities exist",
        ] {
            assert!(
                lib.contains(needle),
                "the template must teach `{needle}`; the trigger pattern drifted"
            );
        }
        assert!(
            !lib.contains("{{"),
            "every placeholder is substituted, got:\n{}",
            lib.lines().find(|line| line.contains("{{")).unwrap_or("…")
        );

        // Without the physics module the same template falls back:
        // no avian code, no bridge, no demo, and the manual gravity
        // line returns. (The docs at the top still mention physics —
        // they teach the default shape; only the code withdraws.)
        let plain = temp_dir("newgame-triggers-plain").join("my-game");
        scaffold_new_project_with(
            &plain,
            "my-game",
            TemplateKind::Game,
            &modules(&["navmesh"]),
        )
        .unwrap();
        let plain_lib = std::fs::read_to_string(plain.join("src/lib.rs")).unwrap();
        for gone in [
            "jackdaw_avian_integration",
            "avian3d",
            "TriggerPlugin",
            "struct Pickup",
            "PickupCount",
        ] {
            assert!(
                !plain_lib.contains(gone),
                "without the physics module `{gone}` must not appear"
            );
        }
        assert!(
            plain_lib.contains("transform.translation.y += config.gravity * dt;"),
            "the manual fall stands in without physics"
        );
    }

    /// The tilemap module (T22, opt-in) teaches the 2D half: the manifest
    /// carries the collision kernel, the template builds a grid from the
    /// scene's tilemap layers, and a probe body walks it with the
    /// kernel's sweep and a trigger census — the shape the kernel
    /// prototype (`player_probe_app`) pinned. Without the module none of
    /// it exists: the placeholders withdraw to empty lines, the header
    /// prose included.
    #[test]
    fn new_game_project_teaches_the_tilemap_collision_pattern() {
        let dest = temp_dir("newgame-tilemap").join("my-game");
        scaffold_new_project_with(&dest, "my-game", TemplateKind::Game, &modules(&["tilemap"]))
            .unwrap();
        let manifest = std::fs::read_to_string(dest.join("Cargo.toml")).unwrap();
        assert!(
            manifest.contains("jackdaw_tilemap_collision = {"),
            "the tilemap module's kernel crate rides the manifest: {manifest}"
        );
        let lib = std::fs::read_to_string(dest.join("src/lib.rs")).unwrap();
        for needle in [
            "TilemapProbePlugin",
            "struct LevelGrid",
            "struct PlayerProbe",
            "struct TriggerCensus",
            "TileCollisionMode::Solid => CollisionMode::Solid",
            "TileGrid::new",
            "move_probe(",
            "trigger_cells_overlapping",
            "spawn_tilemap_probe",
            "collect_level_grid",
            "apply_walk_input",
            "resolve_probe",
            "census_triggers",
            // The header teaches the editor half the module pairs with.
            "Tilemap & 2D collision",
        ] {
            assert!(
                lib.contains(needle),
                "the template must teach `{needle}`; the tilemap pattern drifted"
            );
        }
        assert!(
            !lib.contains("{{"),
            "every placeholder is substituted, got:\n{}",
            lib.lines().find(|line| line.contains("{{")).unwrap_or("…")
        );

        // Without the module the same template carries no tilemap: no
        // kernel crate, no probe code, no header section — the 3D
        // template stands alone.
        let plain = temp_dir("newgame-tilemap-plain").join("my-game");
        scaffold_new_project_with(
            &plain,
            "my-game",
            TemplateKind::Game,
            &modules(&["physics"]),
        )
        .unwrap();
        let plain_manifest = std::fs::read_to_string(plain.join("Cargo.toml")).unwrap();
        let plain_lib = std::fs::read_to_string(plain.join("src/lib.rs")).unwrap();
        for gone in [
            "jackdaw_tilemap_collision",
            "TilemapProbePlugin",
            "struct PlayerProbe",
            "Tilemap & 2D collision",
        ] {
            assert!(
                !plain_manifest.contains(gone) && !plain_lib.contains(gone),
                "without the tilemap module `{gone}` must not appear"
            );
        }
    }

    /// The win the pickup demo teaches (T20/EG1, decision 1-A): the
    /// third pickup moves the flow to the game-over screen — the very
    /// move blood-out takes, so the end screen's Restart covers both —
    /// and acknowledges itself with the button blip on the sfx bus. A
    /// fresh project can be won, not only lost.
    #[test]
    fn new_game_project_teaches_the_win_transition() {
        let dest = temp_dir("newgame-win").join("my-game");
        scaffold_new_project(&dest, "my-game", TemplateKind::Game).unwrap();
        let lib = std::fs::read_to_string(dest.join("src/lib.rs")).unwrap();
        for needle in [
            // The log line stays; the win moves the flow on top of it.
            "Level clear!",
            // The pickup arm's own move: spelled `flow.set` here, where
            // `update_game_over` transitions through `next.set`.
            "flow.set(GameFlow::GameOver)",
            // The header prose names the win and the end screen it lands on.
            "the run is won",
        ] {
            assert!(
                lib.contains(needle),
                "the template must teach `{needle}`; the win transition drifted"
            );
        }
        // The blip sounds exactly twice in the template — `press_sound`'s
        // acknowledgment and the win's: a third (or a vanished one) means
        // the pair drifted.
        assert_eq!(
            lib.matches("server.load(BLIP_SOUND)").count(),
            2,
            "the template teaches exactly two blip spawns (press + win)"
        );
        // The win does not resurrect the pickups or re-enter the level
        // by itself: the game-over screen's Restart is the way back, and
        // that door is the template's existing `"restart"` arm.
        assert!(
            lib.contains("\"start\" | \"restart\" =>"),
            "the win's way back is the shared restart arm; the flow pattern drifted"
        );
    }

    /// The animation module is the only road a game's manifest has to the
    /// `animation` feature: with the module the feature rides along, so the
    /// game links the runtime plugin and plays what a scene authored;
    /// without it nothing animation reaches the manifest and the scene's
    /// sets load as unresolved types.
    #[test]
    fn new_game_project_enables_animation_only_through_its_module() {
        let dest = temp_dir("newgame-animation").join("my-game");
        scaffold_new_project_with(
            &dest,
            "my-game",
            TemplateKind::Game,
            &modules(&["animation"]),
        )
        .unwrap();
        let manifest = std::fs::read_to_string(dest.join("Cargo.toml")).unwrap();
        assert!(
            manifest.contains("features = [\"animation\","),
            "the module's runtime feature must reach the game's manifest:\n{manifest}"
        );
        let toml = std::fs::read_to_string(dest.join("jackdaw.toml")).unwrap();
        assert!(toml.contains("animation = true"), "got:\n{toml}");

        let plain = temp_dir("newgame-animation-plain").join("my-game");
        scaffold_new_project_with(&plain, "my-game", TemplateKind::Game, &ModuleSet::new())
            .unwrap();
        let manifest = std::fs::read_to_string(plain.join("Cargo.toml")).unwrap();
        assert!(
            !manifest.contains("animation"),
            "without the module no animation may reach the manifest"
        );
    }

    /// The player controller pattern the template teaches: tuning on a
    /// component, camera-relative movement against the rig's look state,
    /// the rig parented under the player with the runtime plugin wired,
    /// and (with physics) avian's move-and-slide for walls, gravity and
    /// a jump. Without the module the same controller degrades to a
    /// frame-rate-correct transform walk with no jump and no collision,
    /// while the camera half stays.
    #[test]
    fn new_game_project_teaches_the_player_controller_pattern() {
        let dest = temp_dir("newgame-player").join("my-game");
        scaffold_new_project(&dest, "my-game", TemplateKind::Game).unwrap();
        let lib = std::fs::read_to_string(dest.join("src/lib.rs")).unwrap();
        for needle in [
            "struct PlayerController",
            "move_speed: 4.0",
            "jump_speed: 4.5",
            "PlayerController::default()",
            "fn move_direction(",
            "move_direction(actions.value(\"Move\"), camera_yaw)",
            "fn look_into_camera",
            "CameraRig::default()",
            "JackdawCameraRigPlugin",
            "face_movement_direction",
            "struct PlayerVelocity",
            "PlayerVelocity(Vec3::ZERO)",
            "MoveAndSlide",
            "move_and_slide(",
            "MoveAndSlideHitResponse::Accept",
            "SpatialQueryFilter::from_excluded_entities",
            "just_pressed(\"Jump\")",
            "spawn_walls",
            // C10: the header doc must spell the full five-component
            // set a hand-placed player needs — two names left an
            // editor-placed player frozen (QA t11-t2).
            "queries five components together",
            "zero `PlayerVelocity`",
            "`AvianCollider` (a capsule of radius 0.35",
        ] {
            assert!(
                lib.contains(needle),
                "the template must teach `{needle}`; the player pattern drifted"
            );
        }
        assert!(
            !lib.contains("{{"),
            "every placeholder is substituted, got:\n{}",
            lib.lines().find(|line| line.contains("{{")).unwrap_or("…")
        );

        // Without the physics module the controller degrades, it does
        // not vanish: no avian, no velocity, no walls — but the walk
        // (camera-relative, dt-corrected), the look bridge and the rig
        // wiring all stay, because none of them needs physics.
        let plain = temp_dir("newgame-player-plain").join("my-game");
        scaffold_new_project_with(
            &plain,
            "my-game",
            TemplateKind::Game,
            &modules(&["navmesh"]),
        )
        .unwrap();
        let plain_lib = std::fs::read_to_string(plain.join("src/lib.rs")).unwrap();
        for gone in [
            "avian3d",
            "PlayerVelocity",
            // Doc prose may still name the pattern (the header teaches
            // the default shape, T10 precedent); the call form is code.
            "move_and_slide(",
            "spawn_walls",
            "PickupCount",
        ] {
            assert!(
                !plain_lib.contains(gone),
                "without the physics module `{gone}` must not appear"
            );
        }
        for stays in [
            "fn move_player",
            "controller.move_speed * dt",
            "fn look_into_camera",
            "CameraRig::default()",
            "JackdawCameraRigPlugin",
            "just_pressed(\"Jump\")",
            // The no-physics doc teaches the two-component set the
            // walk query actually is.
            "needs two components",
        ] {
            assert!(
                plain_lib.contains(stays),
                "without the physics module `{stays}` must stay"
            );
        }
        assert!(
            !plain_lib.contains("{{"),
            "the plain template substitutes everything too, got:\n{}",
            plain_lib
                .lines()
                .find(|line| line.contains("{{"))
                .unwrap_or("…")
        );
    }

    /// The game UI pattern the template teaches (T13 form): one hud
    /// document scoped to the level with the two overlays (HUD, pause),
    /// a state resource the pause veil's `Visibility` binds to, an
    /// event the buttons send with their own literal, the via functions
    /// a binding may call registered by hand, and the one-line
    /// `BindContext` wire from the document's root marker to the
    /// player. The UI is not module-gated: the same document and the
    /// same code ship with and without physics.
    #[test]
    fn new_game_project_teaches_the_ui_pattern() {
        let dest = temp_dir("newgame-ui").join("my-game");
        scaffold_new_project(&dest, "my-game", TemplateKind::Game).unwrap();
        let lib = std::fs::read_to_string(dest.join("src/lib.rs")).unwrap();
        for needle in [
            "struct GameState",
            "pub paused: bool",
            "struct ScreenPressed",
            "register_function(ratio)",
            "register_function(is_zero)",
            "register_function(not)",
            "fn spawn_hud_while_level",
            "fn spawn_scene",
            "fn wire_hud",
            "BindContext(player)",
            "struct HudRoot",
            "Added<HudRoot>",
            "fn on_screen_pressed",
            // The resume arm also sounds the press (T16's press_sound), so
            // the needle anchors the two statements it now carries.
            "\"resume\" => {",
            "state.paused = false;",
            "fn handle_pause_action",
            "just_pressed(\"Pause\")",
            "add_systems(Update, handle_pause_action.before(move_player))",
            "(apply_health_from_config, update_game_over).chain()",
        ] {
            assert!(
                lib.contains(needle),
                "the template must teach `{needle}`; the game UI pattern drifted"
            );
        }
        // The hud document itself: the two overlays, the state the
        // pause veil's visibility follows, the bindings that carry the
        // pattern, and the bar half that turns two fields into a fill.
        // The start and game-over screens live in their own documents
        // now (the flow's, see the scene flow test below).
        let hud = std::fs::read_to_string(dest.join("assets/hud.bsn")).unwrap();
        for needle in [
            "UiSceneRoot",
            "#Hud",
            "#PauseScreen",
            "my_game::GameState",
            "my_game::PlayerHealth",
            "Binding::Visible",
            "Binding::Action",
            "[[\"button\", \"resume\"]]",
            "Binding::Field",
            "Binding::Text",
            "via: core::option::Option::Some(\"ratio\")",
            "ProgressFill",
        ] {
            assert!(
                hud.contains(needle),
                "the hud seed must carry `{needle}`; the game UI document drifted"
            );
        }
        for gone in [
            "#StartScreen",
            "#GameOverScreen",
            "my_game::GameState).menu",
        ] {
            assert!(
                !hud.contains(gone),
                "the hud seed's `{gone}` moved to the flow documents"
            );
        }
        assert!(
            !lib.contains("{{"),
            "every placeholder is substituted, got:\n{}",
            lib.lines().find(|line| line.contains("{{")).unwrap_or("…")
        );

        // The UI is not module-gated: a no-physics project ships the
        // same overlays, the same state machine and the same wiring,
        // with only the damage source traded for the Interact key.
        let plain = temp_dir("newgame-ui-plain").join("my-game");
        scaffold_new_project_with(
            &plain,
            "my-game",
            TemplateKind::Game,
            &modules(&["navmesh"]),
        )
        .unwrap();
        let plain_lib = std::fs::read_to_string(plain.join("src/lib.rs")).unwrap();
        for stays in [
            "struct GameState",
            "fn spawn_hud_while_level",
            "register_function(ratio)",
            "fn wire_hud",
            "BindContext(player)",
            "fn on_screen_pressed",
        ] {
            assert!(
                plain_lib.contains(stays),
                "without the physics module `{stays}` must stay"
            );
        }
        let plain_hud = std::fs::read_to_string(plain.join("assets/hud.bsn")).unwrap();
        assert!(
            plain_hud.contains("UiSceneRoot") && plain_hud.contains("#PauseScreen"),
            "the hud document ships without the physics module too"
        );
    }

    /// The health pattern the template teaches: a live component on the
    /// player, the config's number handed over on load, damage clamped
    /// at zero, the flow state reading the same component for the end
    /// of a run. With physics the damage source is a hazard sensor
    /// carrying the docs' collision-layer row and the level's props are
    /// state-scoped; without it the Interact key stands in — component,
    /// bar and gate are the same.
    #[test]
    fn new_game_project_teaches_the_health_pattern() {
        let dest = temp_dir("newgame-health").join("my-game");
        scaffold_new_project(&dest, "my-game", TemplateKind::Game).unwrap();
        let lib = std::fs::read_to_string(dest.join("src/lib.rs")).unwrap();
        for needle in [
            "struct PlayerHealth",
            "PlayerHealth::default()",
            "pub current: f32",
            "pub max: f32",
            "fn apply_health_from_config",
            "config.player_health",
            "fn take_damage",
            "const PLAYER_DAMAGE: f32 = 15.0",
            "fn update_game_over",
            "health.current = config.player_health",
            "const PLAYER_SPAWN: Vec3",
            "fn ratio(",
        ] {
            assert!(
                lib.contains(needle),
                "the template must teach `{needle}`; the health pattern drifted"
            );
        }
        // The physics damage source: a hazard sensor on the docs' row.
        // The restart's reset is the flow's (every level entry), split
        // across `reset_run` (health, spawn point) and the physics
        // module's counters.
        for needle in [
            "struct Hazard",
            "fn spawn_hazards",
            "fn hazard_damage",
            "fn reset_run_counters",
            "DespawnOnExit(GameFlow::Level)",
            "CollisionLayers::new",
            "LayerMask(0b100)",
            "LayerMask(0b001)",
        ] {
            assert!(
                lib.contains(needle),
                "the template must teach `{needle}`; the hazard pattern drifted"
            );
        }

        // Without the physics module the same health degrades, it does
        // not vanish: the Interact key takes the damage instead of a
        // sensor, and no avian anything remains.
        let plain = temp_dir("newgame-health-plain").join("my-game");
        scaffold_new_project_with(
            &plain,
            "my-game",
            TemplateKind::Game,
            &modules(&["navmesh"]),
        )
        .unwrap();
        let plain_lib = std::fs::read_to_string(plain.join("src/lib.rs")).unwrap();
        for gone in ["struct Hazard", "fn hazard_damage", "avian3d"] {
            assert!(
                !plain_lib.contains(gone),
                "without the physics module `{gone}` must not appear"
            );
        }
        for stays in [
            "struct PlayerHealth",
            "fn apply_health_from_config",
            "fn take_damage",
            "take_damage(&mut health, PLAYER_DAMAGE)",
            "fn update_game_over",
        ] {
            assert!(
                plain_lib.contains(stays),
                "without the physics module `{stays}` must stay"
            );
        }
    }

    /// The scene flow pattern the template teaches (T13): the project's
    /// `game.flow.json` names the scene a standalone run starts from,
    /// the boot line composes the editor's Play override around that
    /// read, the initial `GameFlow` state maps from the same scene, and
    /// the three flow documents ship as real scene files so a new
    /// project plays menu → level → game over from its first `cargo
    /// run`.
    #[test]
    fn new_game_project_teaches_the_scene_flow_pattern() {
        let dest = temp_dir("newgame-flow").join("my-game");
        scaffold_new_project(&dest, "my-game", TemplateKind::Game).unwrap();
        let lib = std::fs::read_to_string(dest.join("src/lib.rs")).unwrap();
        for needle in [
            // The doc names the file and its two readers.
            "game.flow.json",
            // The flow read and the Play override composed around it.
            "flow::start_scene_or",
            "pie_scene_or(",
            // The state machine the flow moves, and the boot mapping
            // from the start scene to the initial state.
            "enum GameFlow",
            "fn boot_state",
            "insert_state(boot_state(&start))",
            // The switch itself: one handle re-bind per state.
            "fn enter_level",
            "struct GameRoot",
        ] {
            assert!(
                lib.contains(needle),
                "the template must teach `{needle}`; the scene flow pattern drifted"
            );
        }
        // The seed file ships the whole game: the menu starts, and the
        // list names every document the flow moves between.
        let flow_seed = std::fs::read_to_string(dest.join("assets/game.flow.json")).unwrap();
        for needle in ["start_scene", "menu.bsn", "scene.bsn", "gameover.bsn"] {
            assert!(
                flow_seed.contains(needle),
                "the flow seed must carry `{needle}`; the scene flow seed drifted"
            );
        }
        // The flow documents themselves ship as real scene files: the
        // menu with its Start button, the end screen with Restart and
        // Menu, each carrying its flow marker and the ScreenPressed
        // action binding the observer reads.
        let menu = std::fs::read_to_string(dest.join("assets/menu.bsn")).unwrap();
        for needle in [
            "UiSceneRoot",
            "my_game::MenuRoot",
            "my_game::ScreenPressed",
            "[[\"button\", \"start\"]]",
        ] {
            assert!(
                menu.contains(needle),
                "the menu seed must carry `{needle}`; the menu document drifted"
            );
        }
        let gameover = std::fs::read_to_string(dest.join("assets/gameover.bsn")).unwrap();
        for needle in [
            "UiSceneRoot",
            "my_game::GameOverRoot",
            "[[\"button\", \"restart\"]]",
            "[[\"button\", \"menu\"]]",
        ] {
            assert!(
                gameover.contains(needle),
                "the game-over seed must carry `{needle}`; the game-over document drifted"
            );
        }
    }

    /// Both `[patch]` sections a physics game carries must cover every
    /// fork crate: a git-source subcrate left unpatched floats to the
    /// remote branch head at resolve time — past the commit the lockfile
    /// holds — and the project's first `--locked` build refuses (T10-T3:
    /// the scaffolded game's build failed on exactly that).
    #[test]
    fn a_physics_game_patches_every_fork_crate_on_both_sources() {
        let dest = temp_dir("newgame-patches").join("my-game");
        scaffold_new_project(&dest, "my-game", TemplateKind::Game).unwrap();
        let manifest = std::fs::read_to_string(dest.join("Cargo.toml")).unwrap();
        for section in [
            "[patch.crates-io]",
            "[patch.\"https://github.com/bevyengine/bevy\"]",
        ] {
            let body = manifest
                .split_once(section)
                // The section runs to the next `[` header, or to the end of
                // the file for its last section.
                .map(|(_, rest)| rest.split_once('[').map_or(rest, |(body, _)| body))
                .unwrap_or_else(|| panic!("`{section}` is missing from:\n{manifest}"));
            for name in [
                "bevy",
                "bevy_curve",
                "bevy_math",
                "bevy_reflect",
                "bevy_shape",
            ] {
                assert!(
                    body.contains(&format!("{name} = {{ path =")),
                    "`{section}` must patch `{name}`; got:{body}"
                );
            }
        }
    }

    #[test]
    fn import_adds_the_runtime_alongside_its_own_files() {
        let root = temp_dir("import");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            with_bevy("[package]\nname = \"their-game\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n[dependencies]\nbevy = \"0.20\"\n"),
        )
        .unwrap();
        std::fs::write(
            root.join("src/lib.rs"),
            "pub struct TheirPlugin;\nimpl Plugin for TheirPlugin {}\n",
        )
        .unwrap();
        let report = import_project(&root, None).unwrap();
        assert!(!report.created_lib_stub);
        let cargo = std::fs::read_to_string(root.join("Cargo.toml")).unwrap();
        assert!(cargo.contains(&with_bevy("bevy = \"0.20\"")));
        assert!(cargo.contains("jackdaw_runtime"));
        let toml = std::fs::read_to_string(root.join("jackdaw.toml")).unwrap();
        assert!(toml.contains("plugin = \"TheirPlugin\""));
        assert!(root.join(".jackdaw").is_dir());
        let gitignore = std::fs::read_to_string(root.join(".gitignore")).unwrap();
        assert!(gitignore.contains("/.jackdaw"));
    }

    #[test]
    fn import_offers_a_stub_for_bin_only_projects() {
        let root = temp_dir("stub");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            with_bevy("[package]\nname = \"bin-only\"\nversion = \"0.1.0\"\n\n[dependencies]\nbevy = \"0.20\"\n"),
        )
        .unwrap();
        std::fs::write(root.join("src/main.rs"), "fn main() {}\n").unwrap();

        let report = import_project(&root, None).unwrap();
        assert!(report.created_lib_stub);
        let lib = std::fs::read_to_string(root.join("src/lib.rs")).unwrap();
        assert!(lib.contains("pub struct GamePlugin"));
    }

    #[test]
    fn version_requirements_are_compared_not_prefix_matched() {
        // A build on Bevy's main branch matches no registry requirement.
        if jackdaw_project_build::BEVY_REV.is_some() {
            assert!(!requirement_admits_supported_bevy("0.20"));
            assert!(!requirement_admits_supported_bevy("*"));
            assert!(requirement_admits_supported_bevy("not a version"));
            return;
        }
        // Compatible with 0.20 one way or another.
        for req in [
            "0.20",
            "0.20.2",
            "^0.20",
            "=0.20.0",
            "~0.20",
            ">=0.20, <0.22",
        ] {
            assert!(
                requirement_admits_supported_bevy(req),
                "`{req}` should be accepted"
            );
        }
        // `0.200` is a different minor that merely shares a prefix.
        for req in ["0.16", "0.200", "0.19", "0.21.0-rc.1", "1.0"] {
            assert!(
                !requirement_admits_supported_bevy(req),
                "`{req}` should be rejected"
            );
        }
        // Cargo owns reporting a malformed requirement; import does not
        // block on one.
        assert!(requirement_admits_supported_bevy("not a version"));
    }

    #[test]
    fn import_rejects_a_bevy_minor_mismatch() {
        let root = temp_dir("mismatch");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            "[package]\nname = \"old\"\nversion = \"0.1.0\"\n\n[dependencies]\nbevy = \"0.16\"\n",
        )
        .unwrap();
        std::fs::write(root.join("src/lib.rs"), "pub struct GamePlugin;\n").unwrap();
        assert!(matches!(
            import_project(&root, None),
            Err(ScaffoldError::BevyVersion { .. })
        ));
    }

    /// A virtual workspace with `members`, one of which is the game.
    fn workspace_fixture(name: &str, members: &[(&str, &str)]) -> PathBuf {
        let root = temp_dir(name);
        let list = members
            .iter()
            .map(|(member, _)| format!("\"{member}\""))
            .collect::<Vec<_>>()
            .join(", ");
        std::fs::write(
            root.join("Cargo.toml"),
            format!("[workspace]\nresolver = \"3\"\nmembers = [{list}]\n"),
        )
        .unwrap();
        for (member, deps) in members {
            let dir = root.join(member);
            std::fs::create_dir_all(dir.join("src")).unwrap();
            std::fs::write(
                dir.join("Cargo.toml"),
                format!(
                    "[package]\nname = \"{member}\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
                     [dependencies]\n{deps}\n"
                ),
            )
            .unwrap();
            std::fs::write(dir.join("src/lib.rs"), "pub struct GamePlugin;\n").unwrap();
        }
        root
    }

    /// The recorded plugin is the value most likely to be wrong and the
    /// one the user is uniquely able to check, so it must never be a
    /// silent guess.
    #[test]
    fn the_plan_states_which_plugin_it_recorded() {
        let root = temp_dir("plugin-note");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            with_bevy(
                "[package]\nname = \"g\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
             [dependencies]\nbevy = \"0.20\"\n",
            ),
        )
        .unwrap();
        // A type merely named `*Plugin` above the real one, which a
        // first-name-wins scan would record instead of `MyGamePlugin`.
        std::fs::write(
            root.join("src/lib.rs"),
            "pub struct AudioPlugin;\nimpl Plugin for MyGamePlugin {}\n",
        )
        .unwrap();

        let plan = plan_import_project(&root, None).unwrap();
        assert!(
            plan.notes.iter().any(|n| n.contains("MyGamePlugin")),
            "the plan must state the plugin it recorded: {:?}",
            plan.notes
        );
        assert!(plan.changes.iter().any(|change| matches!(
            change,
            ImportChange::WriteFile { contents, path, .. }
                if path.ends_with("jackdaw.toml") && contents.contains("plugin = \"MyGamePlugin\"")
        )));
    }

    /// With no plugin to find, the key stays commented. Recording a
    /// plugin the crate does not define would leave doctor failing on
    /// a name that does not match source.
    #[test]
    fn no_plugin_means_no_plugin_key() {
        let root = temp_dir("no-plugin-key");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            with_bevy(
                "[package]\nname = \"g\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
             [dependencies]\nbevy = \"0.20\"\n",
            ),
        )
        .unwrap();
        std::fs::write(root.join("src/lib.rs"), "pub struct Health(f32);\n").unwrap();

        let plan = plan_import_project(&root, None).unwrap();
        apply_import_plan(&plan).unwrap();
        let manifest = jackdaw_project_build::project_manifest::ProjectManifest::read(&root);
        assert_eq!(
            manifest.plugin, None,
            "must not name a plugin that is absent"
        );
        let text = std::fs::read_to_string(root.join("jackdaw.toml")).unwrap();
        assert!(text.contains("# plugin = "), "got:\n{text}");
    }

    #[test]
    fn an_undetectable_plugin_is_flagged_not_asserted() {
        let root = temp_dir("plugin-guess");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            with_bevy(
                "[package]\nname = \"g\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
             [dependencies]\nbevy = \"0.20\"\n",
            ),
        )
        .unwrap();
        std::fs::write(root.join("src/lib.rs"), "pub fn helper() {}\n").unwrap();

        let plan = plan_import_project(&root, None).unwrap();
        assert!(
            plan.notes
                .iter()
                .any(|n| n.contains("no `impl Plugin for ...` found")),
            "got: {:?}",
            plan.notes
        );
    }

    /// A bin-only project gets `GamePlugin` created for it, so recording
    /// it is correct even though the pre-setup scan found nothing.
    #[test]
    fn a_created_game_plugin_is_recorded() {
        let root = temp_dir("created-plugin");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            with_bevy(
                "[package]\nname = \"g\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
             [dependencies]\nbevy = \"0.20\"\n",
            ),
        )
        .unwrap();
        std::fs::write(
            root.join("src/main.rs"),
            "use bevy::prelude::*;\nfn main() { App::new().add_plugins(DefaultPlugins).run(); }\n",
        )
        .unwrap();

        let plan = plan_import_project(&root, None).unwrap();
        apply_import_plan(&plan).unwrap();
        let manifest = jackdaw_project_build::project_manifest::ProjectManifest::read(&root);
        assert_eq!(manifest.plugin.as_deref(), Some("GamePlugin"));
        // And the type it names really exists afterwards.
        let lib = std::fs::read_to_string(root.join("src/lib.rs")).unwrap();
        assert!(lib.contains("impl Plugin for GamePlugin"), "got:\n{lib}");
    }

    /// A project set up by an older jackdaw pins that version and its
    /// crate line, so upgrading has to move both.
    #[test]
    fn upgrade_refreshes_the_pins_and_the_crate_requirements() {
        let root = temp_dir("upgrade");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            with_bevy(
                "[package]\nname = \"g\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
             [dependencies]\nbevy = \"0.20\"\n\
             jackdaw_runtime = { version = \"0.14\", features = [\"navmesh\"] }\n",
            ),
        )
        .unwrap();
        std::fs::write(root.join("src/lib.rs"), "impl Plugin for GamePlugin {}\n").unwrap();
        std::fs::write(
            root.join("jackdaw.toml"),
            "plugin = \"GamePlugin\"\n\n[jackdaw]\nversion = \"0.14.0\"\nbevy = \"0.14\"\n\n\
             [[run]]\nname = \"Play\"\n",
        )
        .unwrap();

        let plan = plan_upgrade_project(&root).unwrap();
        assert!(!plan.is_empty());
        apply_import_plan(&plan).unwrap();

        let settings = jackdaw_project_build::project_manifest::ProjectManifest::read(&root);
        assert_eq!(
            jackdaw_project_build::project_manifest::compare_pins(&settings.jackdaw),
            jackdaw_project_build::project_manifest::PinStatus::Match
        );
        // Everything else in the settings file survives the edit.
        assert_eq!(settings.plugin.as_deref(), Some("GamePlugin"));
        let settings_text = std::fs::read_to_string(root.join("jackdaw.toml")).unwrap();
        assert!(settings_text.contains("[[run]]"), "got:\n{settings_text}");

        let cargo = std::fs::read_to_string(root.join("Cargo.toml")).unwrap();
        assert!(
            cargo.contains(&format!(
                "version = \"{}\"",
                jackdaw_project_build::jackdaw_requirement()
            )),
            "got:\n{cargo}"
        );
        // The bump must not drop the features the project asked for.
        assert!(cargo.contains("navmesh"), "got:\n{cargo}");
        // Nor touch anything that is not a jackdaw crate.
        assert!(
            cargo.contains(&with_bevy("bevy = \"0.20\"")),
            "got:\n{cargo}"
        );
    }

    fn set_up_project(name: &str, runtime: &str) -> PathBuf {
        let root = temp_dir(name);
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            with_bevy(&format!(
                "[package]\nname = \"g\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
                 [dependencies]\nbevy = \"0.20\"\njackdaw_runtime = {runtime}\n"
            )),
        )
        .unwrap();
        std::fs::write(root.join("src/lib.rs"), "impl Plugin for GamePlugin {}\n").unwrap();
        std::fs::write(
            root.join("jackdaw.toml"),
            format!(
                "plugin = \"GamePlugin\"\n\n{}",
                jackdaw_project_build::project_manifest::pins_toml_for_bevy(
                    jackdaw_project_build::BEVY_VERSION
                )
            ),
        )
        .unwrap();
        root
    }

    #[test]
    fn upgrade_drops_a_removed_runtime_feature_and_records_its_module() {
        let root = set_up_project(
            "upgrade-removed-feature",
            &format!(
                "{{ version = \"{}\", features = [\"physics\", \"pie\"] }}",
                jackdaw_project_build::jackdaw_requirement()
            ),
        );

        let plan = plan_upgrade_project(&root).unwrap();
        assert!(
            plan.notes
                .iter()
                .any(|note| note.contains("`physics`") && note.contains("Physics module")),
            "got: {:?}",
            plan.notes
        );
        apply_import_plan(&plan).unwrap();

        let cargo = std::fs::read_to_string(root.join("Cargo.toml")).unwrap();
        assert!(cargo.contains("features = [\"pie\"]"), "got:\n{cargo}");
        assert_eq!(modules_table(&root).get("physics"), Some(&true));
        assert!(plan_upgrade_project(&root).unwrap().is_empty());
    }

    #[test]
    fn upgrade_drops_a_removed_runtime_feature_from_the_workspace_entry() {
        let root = set_up_project("upgrade-removed-workspace-feature", "{ workspace = true }");
        let cargo = std::fs::read_to_string(root.join("Cargo.toml")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            format!(
                "{cargo}\n[workspace.dependencies]\n\
                 jackdaw_runtime = {{ version = \"{}\", features = [\"pie\", \"physics\"] }}\n",
                jackdaw_project_build::jackdaw_requirement()
            ),
        )
        .unwrap();

        apply_import_plan(&plan_upgrade_project(&root).unwrap()).unwrap();

        let cargo = std::fs::read_to_string(root.join("Cargo.toml")).unwrap();
        assert!(!cargo.contains("physics"), "got:\n{cargo}");
        assert_eq!(modules_table(&root).get("physics"), Some(&true));
    }

    #[test]
    fn import_drops_a_removed_runtime_feature() {
        let root = bevy_game(
            "import-removed-feature",
            &with_bevy(
                "bevy = \"0.20\"\njackdaw_runtime = { version = \"0.19\", features = [\"physics\"] }\n",
            ),
        );
        let plan = plan_import_project(&root, None).unwrap();
        assert_eq!(plan.modules, modules(&["physics"]));
        let cargo = planned_contents(&plan, &root.join("Cargo.toml")).unwrap();
        assert!(cargo.contains("features = [\"pie\"]"), "got:\n{cargo}");
    }

    /// Deferring a mismatch must not silence it. Recording this
    /// editor's pins would make every later check report health, which
    /// is the opposite of deferring.
    #[test]
    fn setting_up_past_a_mismatch_records_the_projects_bevy() {
        let root = temp_dir("mismatch-pins");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            "[package]\nname = \"g\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
             [dependencies]\nbevy = \"0.16\"\n",
        )
        .unwrap();
        std::fs::write(root.join("src/lib.rs"), "impl Plugin for GamePlugin {}\n").unwrap();

        let plan = plan_import_with(&root, None, None, true).unwrap();
        assert!(
            !plan.changes.iter().any(|change| matches!(
                change,
                ImportChange::WriteFile { path, .. } if path.ends_with("Cargo.toml")
            )),
            "a runtime for another bevy must not be added"
        );
        apply_import_plan(&plan).unwrap();

        let manifest = jackdaw_project_build::project_manifest::ProjectManifest::read(&root);
        assert_eq!(manifest.jackdaw.bevy.as_deref(), Some("0.16"));
        assert!(
            jackdaw_project_build::project_manifest::compare_project(&root, &manifest)
                .is_blocking(),
            "the mismatch must keep being reported"
        );
    }

    /// Upgrading a project that was never set up must refuse: writing a
    /// pins-only jackdaw.toml would make it look integrated and skip the
    /// import flow that completes it.
    #[test]
    fn upgrade_refuses_a_project_that_was_never_set_up() {
        let root = temp_dir("upgrade-unset");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            with_bevy(
                "[package]\nname = \"g\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
             [dependencies]\nbevy = \"0.20\"\n",
            ),
        )
        .unwrap();
        std::fs::write(root.join("src/lib.rs"), "impl Plugin for GamePlugin {}\n").unwrap();

        let error = plan_upgrade_project(&root).unwrap_err();
        assert!(matches!(error, ScaffoldError::NotSetUp(_)), "got {error:?}");
        assert!(error.to_string().contains("jd import --apply"));
        assert!(!root.join("jackdaw.toml").exists());
    }

    #[test]
    fn a_malformed_settings_file_is_reported_not_ignored() {
        let root = temp_dir("bad-settings");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            with_bevy(
                "[package]\nname = \"g\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
             [dependencies]\nbevy = \"0.20\"\n",
            ),
        )
        .unwrap();
        std::fs::write(root.join("src/lib.rs"), "impl Plugin for GamePlugin {}\n").unwrap();
        std::fs::write(
            root.join("jackdaw.toml"),
            "plugin = \nthis is not toml [[\n",
        )
        .unwrap();

        let error = plan_upgrade_project(&root).unwrap_err();
        assert!(
            matches!(error, ScaffoldError::SettingsParse { .. }),
            "got {error:?}"
        );
    }

    /// A platform-gated jackdaw dependency is still a jackdaw
    /// dependency; leaving it behind contradicts what upgrade claims.
    #[test]
    fn upgrade_reaches_target_specific_dependencies() {
        let cargo = "[dependencies]\njackdaw_runtime = \"0.14\"\n\n\
                     [target.'cfg(target_arch = \"wasm32\")'.dependencies]\n\
                     jackdaw_web = \"0.14\"\n";
        let out = bump_jackdaw_requirements(cargo, &jackdaw_project_build::jackdaw_requirement())
            .expect("changed");
        assert_eq!(
            out.matches(&format!(
                "\"{}\"",
                jackdaw_project_build::jackdaw_requirement()
            ))
            .count(),
            2,
            "both entries should move:\n{out}"
        );
    }

    /// Upgrading moves the jackdaw version; it does not migrate the
    /// user's Bevy. Recording this editor's minor would mark a
    /// mismatched project healthy without changing anything, undoing
    /// the flag `--allow-bevy-mismatch` deliberately left behind.
    #[test]
    fn upgrade_does_not_launder_away_a_bevy_mismatch() {
        let root = temp_dir("upgrade-mismatch");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            "[package]\nname = \"g\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
             [dependencies]\nbevy = \"0.16\"\n",
        )
        .unwrap();
        std::fs::write(root.join("src/lib.rs"), "impl Plugin for GamePlugin {}\n").unwrap();
        std::fs::write(
            root.join("jackdaw.toml"),
            "plugin = \"GamePlugin\"\n\n[jackdaw]\nversion = \"0.14.0\"\nbevy = \"0.16\"\n\n\
             [[run]]\nname = \"Play\"\n",
        )
        .unwrap();

        let plan = plan_upgrade_project(&root).unwrap();
        apply_import_plan(&plan).unwrap();

        let manifest = jackdaw_project_build::project_manifest::ProjectManifest::read(&root);
        assert_eq!(manifest.jackdaw.bevy.as_deref(), Some("0.16"));
        assert_eq!(
            manifest.jackdaw.version.as_deref(),
            Some(jackdaw_project_build::VERSION)
        );
        assert!(
            jackdaw_project_build::project_manifest::compare_project(&root, &manifest)
                .is_blocking(),
            "the mismatch must survive the upgrade"
        );
        // And the user is told, rather than left to notice.
        assert!(
            plan.notes.iter().any(|note| note.contains("bevy 0.16")),
            "got: {:?}",
            plan.notes
        );
    }

    /// `[workspace.dependencies]` is where a workspace writes versions
    /// down; members inherit with `{ workspace = true }`.
    #[test]
    fn upgrade_reaches_workspace_dependencies() {
        let cargo = "[workspace]\nmembers = [\"game\"]\n\n\
                     [workspace.dependencies]\njackdaw_runtime = \"0.14\"\n";
        let out = bump_jackdaw_requirements(cargo, &jackdaw_project_build::jackdaw_requirement())
            .expect("changed");
        assert!(
            out.contains(&format!(
                "jackdaw_runtime = \"{}\"",
                jackdaw_project_build::jackdaw_requirement()
            )),
            "got:\n{out}"
        );
    }

    /// The pins table must stay where the user put it, keeping any
    /// other keys and comments inside it.
    #[test]
    fn refreshing_pins_keeps_the_table_in_place() {
        let settings = &with_bevy(
            "plugin = \"GamePlugin\"\n\n\
                        [jackdaw]\n# why this is here\nversion = \"0.14.0\"\nbevy = \"0.20\"\n\
                        note = \"keep me\"\n\n\
                        [[run]]\nname = \"Play\"\n",
        );
        let out = rewrite_pins(settings, Some("0.20")).expect("changed");
        assert!(out.contains("note = \"keep me\""), "got:\n{out}");
        assert!(out.contains("# why this is here"), "got:\n{out}");
        assert!(
            out.find("[jackdaw]") < out.find("[[run]]"),
            "the table must not be relocated past the run configs:\n{out}"
        );
    }

    #[test]
    fn upgrade_is_a_no_op_on_a_current_project() {
        let root = temp_dir("upgrade-current");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            with_bevy(
                "[package]\nname = \"g\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
             [dependencies]\nbevy = \"0.20\"\n",
            ),
        )
        .unwrap();
        std::fs::write(root.join("src/lib.rs"), "impl Plugin for GamePlugin {}\n").unwrap();
        std::fs::write(
            root.join("jackdaw.toml"),
            format!(
                "plugin = \"GamePlugin\"\n\n{}\n[[run]]\nname = \"Play\"\n",
                jackdaw_project_build::project_manifest::pins_toml()
            ),
        )
        .unwrap();

        assert!(plan_upgrade_project(&root).unwrap().is_empty());
    }

    /// A path or git dependency resolves outside the registry, so there
    /// is no version requirement to move and rewriting one would break
    /// a working local setup.
    #[test]
    fn upgrade_leaves_path_dependencies_alone() {
        let cargo =
            "[dependencies]\njackdaw_runtime = { path = '/checkout/crates/jackdaw_runtime' }\n";
        assert!(
            bump_jackdaw_requirements(cargo, &jackdaw_project_build::jackdaw_requirement())
                .is_none()
        );
    }

    #[test]
    fn import_resolves_the_game_member_of_a_workspace() {
        let root = workspace_fixture(
            "ws",
            &[
                ("tools", "clap = \"4\""),
                ("game", &with_bevy("bevy = \"0.20\"")),
            ],
        );

        let plan = plan_import_project(&root, None).unwrap();
        assert_eq!(plan.package_name, "game");
        assert_eq!(
            dunce::canonicalize(&plan.package_dir).unwrap(),
            dunce::canonicalize(root.join("game")).unwrap()
        );
        // The settings file belongs to the folder the user opened, not
        // to the member; the member is recorded inside it instead.
        assert!(plan.changes.iter().any(|change| matches!(
            change,
            ImportChange::WriteFile { path, contents, .. }
                if path == &root.join("jackdaw.toml") && contents.contains("package = \"game\"")
        )));
        assert!(plan.notes.iter().any(|note| note.contains("workspace")));
    }

    #[test]
    fn import_asks_which_member_when_several_use_bevy() {
        let root = workspace_fixture(
            "wsambig",
            &[
                ("client", &with_bevy("bevy = \"0.20\"")),
                ("server", &with_bevy("bevy = \"0.20\"")),
            ],
        );

        let err = plan_import_project(&root, None).unwrap_err();
        let message = err.to_string();
        assert!(message.contains("--package"), "got: {message}");
        assert!(message.contains("client") && message.contains("server"));

        let plan = plan_import_package(&root, None, Some("server")).unwrap();
        assert_eq!(plan.package_name, "server");
    }

    #[test]
    fn import_records_package_when_the_game_is_the_workspace_root() {
        let root = temp_dir("wsroot");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::create_dir_all(root.join("helper/src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            with_bevy(
                "[workspace]\nmembers = [\".\", \"helper\"]\nresolver = \"2\"\n\n\
             [package]\nname = \"the-game\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
             [dependencies]\nbevy = \"0.20\"\nhelper = { path = \"helper\" }\n",
            ),
        )
        .unwrap();
        std::fs::write(root.join("src/lib.rs"), "pub struct GamePlugin;\n").unwrap();
        std::fs::write(
            root.join("helper/Cargo.toml"),
            with_bevy(
                "[package]\nname = \"helper\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
             [dependencies]\nbevy = \"0.20\"\n",
            ),
        )
        .unwrap();
        std::fs::write(root.join("helper/src/lib.rs"), "pub struct HelperPlugin;\n").unwrap();

        let plan = plan_import_package(&root, None, Some("the-game")).unwrap();
        assert!(plan.changes.iter().any(|change| matches!(
            change,
            ImportChange::WriteFile { path, contents, .. }
                if path == &root.join("jackdaw.toml")
                    && contents.contains("package = \"the-game\"")
        )));
    }

    #[test]
    fn import_checks_a_workspace_inherited_bevy_version() {
        let root = temp_dir("wsinherit");
        std::fs::write(
            root.join("Cargo.toml"),
            "[workspace]\nresolver = \"3\"\nmembers = [\"game\"]\n\n\
             [workspace.dependencies]\nbevy = \"0.16\"\n",
        )
        .unwrap();
        let member = root.join("game");
        std::fs::create_dir_all(member.join("src")).unwrap();
        std::fs::write(
            member.join("Cargo.toml"),
            "[package]\nname = \"game\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
             [dependencies]\nbevy = { workspace = true }\n",
        )
        .unwrap();
        std::fs::write(member.join("src/lib.rs"), "pub struct GamePlugin;\n").unwrap();

        assert!(matches!(
            plan_import_project(&root, None),
            Err(ScaffoldError::BevyVersion { found }) if found == "0.16"
        ));
    }

    #[test]
    fn a_broken_manifest_reports_what_cargo_said() {
        let root = temp_dir("broken");
        std::fs::write(root.join("Cargo.toml"), "[package\nname = oops\n").unwrap();
        let err = plan_import_project(&root, None).unwrap_err();
        assert!(matches!(err, ScaffoldError::Package(_)), "got {err:?}");
        assert!(err.to_string().to_lowercase().contains("error"));
    }

    #[test]
    fn setup_records_the_versions_it_was_created_with() {
        let root = temp_dir("pins");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            with_bevy(
                "[package]\nname = \"pinned\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
             [dependencies]\nbevy = \"0.20\"\n",
            ),
        )
        .unwrap();
        std::fs::write(root.join("src/lib.rs"), "pub struct GamePlugin;\n").unwrap();
        import_project(&root, None).unwrap();

        let manifest = jackdaw_project_build::project_manifest::ProjectManifest::read(&root);
        assert_eq!(
            jackdaw_project_build::project_manifest::compare_pins(&manifest.jackdaw),
            jackdaw_project_build::project_manifest::PinStatus::Match
        );
    }

    #[test]
    fn scaffolded_projects_record_their_versions() {
        let dest = temp_dir("newpins").join("pinned-game");
        scaffold_new_project(&dest, "pinned-game", TemplateKind::Game).unwrap();
        let toml = std::fs::read_to_string(dest.join("jackdaw.toml")).unwrap();
        assert!(
            !toml.contains("{{"),
            "placeholders must be substituted:\n{toml}"
        );
        let manifest = jackdaw_project_build::project_manifest::ProjectManifest::read(&dest);
        assert_eq!(
            jackdaw_project_build::project_manifest::compare_pins(&manifest.jackdaw),
            jackdaw_project_build::project_manifest::PinStatus::Match
        );
        let cargo = std::fs::read_to_string(dest.join("Cargo.toml")).unwrap();
        assert!(cargo.contains(&format!(
            "bevy = {}",
            jackdaw_project_build::bevy_source::dependency_with_features(&["wav"])
        )));
        assert!(!cargo.contains("{{"));
    }

    #[test]
    fn project_names_that_cannot_be_crate_names_are_rejected() {
        assert_eq!(
            validated_project_name("My Cool Game!").unwrap(),
            "my-cool-game"
        );
        assert_eq!(
            validated_project_name("  spaced  out ").unwrap(),
            "spaced-out"
        );
        for bad in ["", "***", "2d-shooter", "crate", "impl", "type"] {
            assert!(
                validated_project_name(bad).is_err(),
                "`{bad}` should be rejected"
            );
        }
    }

    fn bevy_game(name: &str, deps: &str) -> PathBuf {
        let root = temp_dir(name);
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            format!(
                "[package]\nname = \"my-game\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
                 [dependencies]\n{deps}"
            ),
        )
        .unwrap();
        std::fs::write(
            root.join("src/lib.rs"),
            "use bevy::prelude::*;\n\npub struct GamePlugin;\n\n\
             impl Plugin for GamePlugin {\n    fn build(&self, _app: &mut App) {}\n}\n",
        )
        .unwrap();
        std::fs::write(
            root.join("src/main.rs"),
            "use bevy::prelude::*;\n\nfn main() {\n    App::new()\n        \
             .add_plugins(DefaultPlugins)\n        .add_plugins(my_game::GamePlugin)\n        \
             .run();\n}\n",
        )
        .unwrap();
        root
    }

    fn planned_contents(plan: &ImportPlan, path: &Path) -> Option<String> {
        plan.changes.iter().find_map(|change| match change {
            ImportChange::WriteFile {
                path: written,
                contents,
                ..
            } if written == path => Some(contents.clone()),
            _ => None,
        })
    }

    #[test]
    fn import_wraps_default_plugins_in_the_common_main_shapes() {
        let shapes = [
            "fn main() {\n    App::new()\n        .add_plugins(DefaultPlugins)\n        \
             .add_plugins(my_game::GamePlugin)\n        .run();\n}\n",
            "fn main() { App::new().add_plugins(DefaultPlugins)\
             .add_plugins(my_game::GamePlugin).run(); }\n",
            "fn main() {\n    App::new()\n        .add_plugins((DefaultPlugins, my_game::GamePlugin))\n        \
             .run();\n}\n",
            "fn main() {\n    App::new()\n        .add_plugins(bevy::DefaultPlugins)\n        \
             .add_plugins(my_game::GamePlugin)\n        .run();\n}\n",
            "fn main() {\n    App::new()\n        .add_plugins((\n            \
             DefaultPlugins.set(WindowPlugin::default()),\n            my_game::GamePlugin,\n        \
             ))\n        .run();\n}\n",
            "fn main() -> ExitCode {\n    App::new()\n        .add_plugins(DefaultPlugins)\n        \
             .add_plugins(my_game::GamePlugin)\n        .run()\n}\n",
            "fn main() {\n    let mut app = App::new();\n    app.add_plugins(DefaultPlugins);\n    \
             app.add_plugins(my_game::GamePlugin);\n    app.run();\n}\n",
        ];
        for (index, shape) in shapes.iter().enumerate() {
            let root = bevy_game(
                &format!("wrap-shape-{index}"),
                &with_bevy("bevy = \"0.20\"\n"),
            );
            std::fs::write(
                root.join("src/main.rs"),
                format!("use bevy::prelude::*;\n\n{shape}"),
            )
            .unwrap();

            let plan = plan_import_project(&root, None).unwrap();
            let main = planned_contents(&plan, &root.join("src/main.rs"))
                .unwrap_or_else(|| panic!("main.rs is not wrapped for:\n{shape}"));
            assert!(
                main.contains("jackdaw_runtime::maybe_windowless(default_plugins)"),
                "got:\n{main}"
            );
            assert!(syn::parse_file(&main).is_ok(), "still parses:\n{main}");
            assert!(
                !plan
                    .notes
                    .iter()
                    .any(|note| note.contains("pass DefaultPlugins through")),
                "no manual step is left for:\n{shape}\n{:?}",
                plan.notes
            );
        }
    }

    #[test]
    fn import_wires_the_runtime_into_a_plain_bevy_game() {
        let root = bevy_game("wire-runtime", &with_bevy("bevy = \"0.20\"\n"));

        let plan = plan_import_project(&root, None).unwrap();
        let cargo = planned_contents(&plan, &root.join("Cargo.toml")).expect("Cargo.toml edit");
        assert!(
            cargo.contains(&format!(
                "jackdaw_runtime = {{ {}, features = [\"pie\"] }}",
                jackdaw_dep_requirement("jackdaw_runtime")
            )),
            "got:\n{cargo}"
        );
        let lib = planned_contents(&plan, &root.join("src/lib.rs")).expect("lib.rs edit");
        assert!(
            lib.contains(
                "fn build(&self, app: &mut App) {\n        \
                 app.add_plugins(jackdaw_runtime::JackdawPlugin);\n    }"
            ),
            "got:\n{lib}"
        );
        let main = planned_contents(&plan, &root.join("src/main.rs")).expect("main.rs edit");
        assert!(
            main.contains(
                "let default_plugins = jackdaw_runtime::maybe_windowless(default_plugins);"
            ),
            "got:\n{main}"
        );
        assert!(main.contains(".add_plugins(default_plugins)"));
        assert!(
            plan.changes
                .iter()
                .any(|change| change.summary().starts_with("modify ")
                    && change.summary().ends_with("Cargo.toml")),
            "the preview lists the manifest edit"
        );
        assert!(
            !plan
                .notes
                .iter()
                .any(|note| note.contains("add_plugins(jackdaw_runtime")),
            "no manual step is left once the edit is made: {:?}",
            plan.notes
        );
    }

    #[test]
    fn a_second_import_has_nothing_to_do() {
        let root = bevy_game("reimport", &with_bevy("bevy = \"0.20\"\n"));
        apply_import_plan(&plan_import_project(&root, None).unwrap()).unwrap();

        let again = plan_import_project(&root, None).unwrap();
        assert!(again.is_empty(), "second run planned {:?}", again.changes);
    }

    fn modules(ids: &[&str]) -> ModuleSet {
        ids.iter().map(|id| (*id).to_string()).collect()
    }

    fn modules_table(root: &Path) -> std::collections::BTreeMap<String, bool> {
        jackdaw_project_build::project_manifest::ProjectManifest::read(root)
            .modules
            .expect("a [modules] table")
    }

    #[test]
    fn the_modules_flags_choose_the_modules_and_refuse_nonsense() {
        let args = |list: &[&str]| list.iter().map(|a| (*a).to_string()).collect::<Vec<_>>();
        assert_eq!(
            modules_arg(&args(&["game", "--modules", "navmesh"])).unwrap(),
            Some(modules(&["navmesh"]))
        );
        assert_eq!(
            modules_arg(&args(&["game", "--modules=multiplayer"])).unwrap(),
            Some(modules(&["multiplayer"]))
        );
        assert_eq!(
            modules_arg(&args(&["game", "--no-modules"])).unwrap(),
            Some(ModuleSet::new())
        );
        assert_eq!(modules_arg(&args(&["game"])).unwrap(), None);
        assert!(modules_arg(&args(&["game", "--modules", "rendering"])).is_err());
        assert_eq!(
            modules_arg(&args(&["game", "--modules", "physics"])).unwrap(),
            Some(modules(&["physics"]))
        );
        assert!(modules_arg(&args(&["game", "--modules", "physics", "--no-modules"])).is_err());
    }

    /// Windows checkouts can carry the templates with CRLF line endings.
    #[test]
    fn crlf_templates_still_get_their_module_lines() {
        for path in [
            "templates/game/Cargo.toml.template",
            "templates/game/src/main.rs.template",
        ] {
            let template =
                std::fs::read_to_string(format!("{}/{path}", env!("CARGO_MANIFEST_DIR")))
                    .unwrap()
                    .replace("\r\n", "\n")
                    .replace('\n', "\r\n");
            let filled = substitute_placeholders(
                &template,
                "my-game",
                "my_game",
                "",
                "My Game",
                &modules(&["multiplayer"]),
            );
            assert!(!filled.contains("{{"), "{path}: got:\n{filled}");
            assert!(
                filled.contains("jackdaw_multiplayer"),
                "{path}: got:\n{filled}"
            );
        }
    }

    #[test]
    fn a_new_game_writes_its_modules_into_cargo_toml_main_and_jackdaw_toml() {
        let dest = temp_dir("new-navmesh").join("nav-game");
        scaffold_new_project_with(
            &dest,
            "nav-game",
            TemplateKind::Game,
            &modules(&["navmesh"]),
        )
        .unwrap();
        let cargo = std::fs::read_to_string(dest.join("Cargo.toml")).unwrap();
        assert!(
            cargo.contains("features = [\"navmesh\", \"terrain\", \"tilemap\", \"pie\"] }"),
            "got:\n{cargo}"
        );
        assert!(!cargo.contains("avian3d"), "got:\n{cargo}");
        assert!(!cargo.contains("jackdaw_multiplayer"), "got:\n{cargo}");
        let table = modules_table(&dest);
        assert_eq!(table.get("physics"), Some(&false));
        assert_eq!(table.get("navmesh"), Some(&true));
        assert_eq!(table.get("multiplayer"), Some(&false));

        let bare = temp_dir("new-bare").join("bare-game");
        scaffold_new_project_with(&bare, "bare-game", TemplateKind::Game, &ModuleSet::new())
            .unwrap();
        let cargo = std::fs::read_to_string(bare.join("Cargo.toml")).unwrap();
        assert!(
            cargo.contains("features = [\"terrain\", \"tilemap\", \"pie\"] }"),
            "got:\n{cargo}"
        );
        assert!(!cargo.contains("avian3d"), "got:\n{cargo}");
        let main = std::fs::read_to_string(bare.join("src/main.rs")).unwrap();
        assert!(!main.contains("avian3d"), "got:\n{main}");
        assert!(!main.contains("{{"), "got:\n{main}");
        assert!(modules_table(&bare).values().all(|on| !on));

        let net = temp_dir("new-net").join("net-game");
        scaffold_new_project_with(
            &net,
            "net-game",
            TemplateKind::Game,
            &modules(&["multiplayer"]),
        )
        .unwrap();
        let cargo = std::fs::read_to_string(net.join("Cargo.toml")).unwrap();
        assert!(
            cargo.contains("\njackdaw_multiplayer = { "),
            "got:\n{cargo}"
        );
        let main = std::fs::read_to_string(net.join("src/main.rs")).unwrap();
        assert!(main.contains(".add_plugins(jackdaw_multiplayer::JackdawMultiplayerTypesPlugin)"));
    }

    #[test]
    fn import_detects_the_modules_a_game_already_uses_and_adds_the_chosen_ones_once() {
        let root = bevy_game(
            "import-modules",
            &with_bevy(
                "bevy = \"0.20\"\n\
             jackdaw_runtime = { version = \"0.19\", features = [\"physics\", \"pie\"] }\n\
             avian3d = \"0.7\"\n",
            ),
        );
        std::fs::write(
            root.join("src/main.rs"),
            "use bevy::prelude::*;\n\nfn main() {\n    let default_plugins = \
             jackdaw_runtime::maybe_windowless(DefaultPlugins);\n    App::new()\n        \
             .add_plugins(default_plugins)\n        .add_plugins(my_game::GamePlugin)\n        \
             .run();\n}\n",
        )
        .unwrap();
        std::fs::write(
            root.join("src/lib.rs"),
            "use bevy::prelude::*;\n\npub struct GamePlugin;\n\n\
             impl Plugin for GamePlugin {\n    fn build(&self, app: &mut App) {\n        \
             app.add_plugins(jackdaw_runtime::JackdawPlugin);\n    }\n}\n",
        )
        .unwrap();

        let plain = plan_import_project(&root, None).unwrap();
        assert_eq!(plain.detected_modules, modules(&["physics"]));
        assert_eq!(plain.modules, modules(&["physics"]));
        let cargo = planned_contents(&plain, &root.join("Cargo.toml")).expect("Cargo.toml edit");
        assert!(
            cargo.contains("features = [\"pie\"]"),
            "only the removed feature goes when no module is chosen, got:\n{cargo}"
        );

        let chosen = modules(&["navmesh", "multiplayer"]);
        let plan = plan_import_with_modules(&root, None, None, false, Some(&chosen)).unwrap();
        assert_eq!(
            plan.modules,
            modules(&["multiplayer", "navmesh", "physics"])
        );
        let cargo = planned_contents(&plan, &root.join("Cargo.toml")).expect("Cargo.toml edit");
        assert!(
            cargo.contains("features = [\"pie\", \"navmesh\"]"),
            "got:\n{cargo}"
        );
        assert!(cargo.contains("jackdaw_multiplayer = {"), "got:\n{cargo}");
        assert!(
            plan.notes
                .iter()
                .any(|note| note.contains("JackdawMultiplayerTypesPlugin")),
            "the plugin left to add is named: {:?}",
            plan.notes
        );
        apply_import_plan(&plan).unwrap();
        let table = modules_table(&root);
        assert_eq!(table.get("navmesh"), Some(&true));
        assert_eq!(table.get("multiplayer"), Some(&true));

        let again = plan_import_with_modules(&root, None, None, false, Some(&chosen)).unwrap();
        assert!(again.is_empty(), "second run planned {:?}", again.changes);
        assert_eq!(
            again.detected_modules,
            modules(&["multiplayer", "navmesh", "physics"])
        );
    }

    #[test]
    #[ignore = "merge TBD: the physics detection flow assumes the upstream environment (physics rides a foreign bevy and is removable); on the fork-pinned line physics is always available and `plan_module_change` detects no physics delta here. Ruling pending on which detection table the fork line keeps"]
    fn changing_modules_later_edits_both_manifests_and_keeps_the_games_crates() {
        let root = temp_dir("change-modules").join("change-game");
        scaffold_new_project_with(&root, "change-game", TemplateKind::Game, &ModuleSet::new())
            .unwrap();
        let cargo_path = root.join("Cargo.toml");

        let chosen = modules(&["multiplayer", "navmesh"]);
        let plan = plan_module_change(&root, &chosen).unwrap();
        assert_eq!(plan.detected_modules, modules(&["physics"]));
        apply_import_plan(&plan).unwrap();
        let cargo = std::fs::read_to_string(&cargo_path).unwrap();
        assert!(
            cargo.contains("features = [\"terrain\", \"tilemap\", \"pie\", \"navmesh\"]"),
            "got:\n{cargo}"
        );
        assert!(cargo.contains("jackdaw_multiplayer = {"), "got:\n{cargo}");
        assert_eq!(modules_table(&root).get("navmesh"), Some(&true));
        assert!(
            plan_module_change(&root, &chosen).unwrap().is_empty(),
            "asking again changes nothing"
        );

        let plan = plan_module_change(&root, &ModuleSet::new()).unwrap();
        assert!(
            plan.notes
                .iter()
                .any(|note| note.starts_with("jackdaw_multiplayer stays")),
            "{:?}",
            plan.notes
        );
        apply_import_plan(&plan).unwrap();
        let cargo = std::fs::read_to_string(&cargo_path).unwrap();
        assert!(
            cargo.contains("features = [\"terrain\", \"tilemap\", \"pie\"]"),
            "got:\n{cargo}"
        );
        assert!(cargo.contains("jackdaw_multiplayer = {"), "got:\n{cargo}");
        assert!(modules_table(&root).values().all(|on| !on));
        let settings = std::fs::read_to_string(root.join("jackdaw.toml")).unwrap();
        assert!(settings.contains("[[run]]"), "got:\n{settings}");
    }

    #[test]
    fn a_jackdaw_crate_a_module_adds_comes_from_where_the_runtime_does() {
        let doc = |entry: &str| -> DocumentMut {
            format!("[dependencies]\njackdaw_runtime = {entry}\n")
                .parse()
                .unwrap()
        };
        let like = |entry: &str| jackdaw_crate_like_runtime(&doc(entry), "jackdaw_multiplayer");
        assert_eq!(
            like("{ path = '/src/jackdaw/crates/jackdaw_runtime', features = [\"pie\"] }")
                .as_deref(),
            Some("{ path = '/src/jackdaw/crates/jackdaw_multiplayer' }")
        );
        assert_eq!(
            like("{ git = \"https://example.com/jackdaw\", rev = \"abc\" }").as_deref(),
            Some("{ git = \"https://example.com/jackdaw\", rev = \"abc\" }")
        );
        assert_eq!(like("\"0.19\"").as_deref(), Some("{ version = \"0.19\" }"));
        assert_eq!(
            like("{ version = \"=0.19.0-rc.10\", features = [] }").as_deref(),
            Some("{ version = \"=0.19.0-rc.10\" }")
        );
    }

    #[test]
    fn import_enables_pie_on_an_existing_runtime_dependency() {
        let root = bevy_game(
            "add-pie",
            &with_bevy("bevy = \"0.20\"\njackdaw_runtime = \"0.19\"\n"),
        );
        let plan = plan_import_project(&root, None).unwrap();
        let cargo = planned_contents(&plan, &root.join("Cargo.toml")).unwrap();
        assert!(
            cargo.contains("jackdaw_runtime = { version = \"0.19\", features = [\"pie\"] }"),
            "got:\n{cargo}"
        );

        let root = bevy_game(
            "extend-features",
            &with_bevy(
                "bevy = \"0.20\"\njackdaw_runtime = { version = \"0.19\", features = [\"navmesh\"] }\n",
            ),
        );
        let plan = plan_import_project(&root, None).unwrap();
        let cargo = planned_contents(&plan, &root.join("Cargo.toml")).unwrap();
        assert!(
            cargo.contains("features = [\"navmesh\", \"pie\"]"),
            "got:\n{cargo}"
        );
    }

    #[test]
    fn import_adds_pie_to_a_workspace_inherited_runtime() {
        let root = temp_dir("ws-runtime");
        let workspace = "[workspace]\nresolver = \"3\"\nmembers = [\"game\"]\n\n\
                         [workspace.dependencies]\njackdaw_runtime = \"0.19\"\n";
        std::fs::write(root.join("Cargo.toml"), workspace).unwrap();
        let member = root.join("game");
        std::fs::create_dir_all(member.join("src")).unwrap();
        std::fs::write(
            member.join("Cargo.toml"),
            with_bevy(
                "[package]\nname = \"game\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
             [dependencies]\nbevy = \"0.20\"\njackdaw_runtime = { workspace = true }\n",
            ),
        )
        .unwrap();
        std::fs::write(member.join("src/lib.rs"), "pub struct GamePlugin;\n").unwrap();

        let plan = plan_import_project(&root, None).unwrap();
        let cargo = planned_contents(&plan, &member.join("Cargo.toml")).unwrap();
        assert!(
            cargo.contains("jackdaw_runtime = { workspace = true, features = [\"pie\"] }"),
            "got:\n{cargo}"
        );
        assert!(planned_contents(&plan, &root.join("Cargo.toml")).is_none());

        std::fs::write(
            root.join("Cargo.toml"),
            workspace.replace(
                "jackdaw_runtime = \"0.19\"",
                "jackdaw_runtime = { version = \"0.19\", features = [\"pie\"] }",
            ),
        )
        .unwrap();
        let plan = plan_import_project(&root, None).unwrap();
        assert!(
            planned_contents(&plan, &member.join("Cargo.toml")).is_none(),
            "pie already comes from the workspace"
        );
    }

    #[test]
    fn the_runtime_edit_keeps_manifest_comments_and_order() {
        let root = bevy_game(
            "keep-comments",
            &with_bevy(
                "# Engine.\nbevy = \"0.20\" # pinned to the minor\n\n# Utilities.\nrand = \"0.9\"\n",
            ),
        );
        let before = std::fs::read_to_string(root.join("Cargo.toml")).unwrap();
        let plan = plan_import_project(&root, None).unwrap();
        let cargo = planned_contents(&plan, &root.join("Cargo.toml")).unwrap();
        assert!(cargo.starts_with(&before), "got:\n{cargo}");
        assert!(cargo[before.len()..].starts_with("jackdaw_runtime = {"));
    }

    #[test]
    fn enabling_pie_keeps_a_trailing_comment() {
        let root = bevy_game(
            "pie-comment",
            &with_bevy(
                "bevy = \"0.20\"\njackdaw_runtime = \"0.19\" # scene loading\nrand = \"0.9\"\n",
            ),
        );
        let plan = plan_import_project(&root, None).unwrap();
        let cargo = planned_contents(&plan, &root.join("Cargo.toml")).unwrap();
        assert!(
            cargo.contains(
                "jackdaw_runtime = { version = \"0.19\", features = [\"pie\"] } # scene loading\n"
            ),
            "got:\n{cargo}"
        );
    }

    fn assert_leaves_sources_alone(plan: &ImportPlan, root: &Path) {
        for file in ["Cargo.toml", "src/lib.rs", "src/main.rs"] {
            assert!(
                planned_contents(plan, &root.join(file)).is_none(),
                "{file} must not be edited: {:?}",
                plan.notes
            );
        }
        assert!(
            plan.notes
                .iter()
                .any(|note| note.contains("declares jackdaw_runtime as")),
            "the plan says why: {:?}",
            plan.notes
        );
    }

    #[test]
    fn an_optional_runtime_gets_notes_not_edits() {
        let root = bevy_game(
            "optional-runtime",
            &with_bevy(
                "bevy = \"0.20\"\njackdaw_runtime = { version = \"0.19\", optional = true }\n",
            ),
        );
        assert_leaves_sources_alone(&plan_import_project(&root, None).unwrap(), &root);
    }

    #[test]
    fn a_renamed_runtime_is_not_declared_twice() {
        let root = bevy_game(
            "renamed-runtime",
            &with_bevy(
                "bevy = \"0.20\"\nruntime = { package = \"jackdaw_runtime\", version = \"0.19\" }\n",
            ),
        );
        assert_leaves_sources_alone(&plan_import_project(&root, None).unwrap(), &root);
    }

    #[test]
    fn a_target_specific_runtime_is_not_declared_again() {
        let root = bevy_game("target-runtime", &with_bevy("bevy = \"0.20\"\n"));
        let cargo = std::fs::read_to_string(root.join("Cargo.toml")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            format!("{cargo}\n[target.'cfg(unix)'.dependencies]\njackdaw_runtime = \"0.19\"\n"),
        )
        .unwrap();
        assert_leaves_sources_alone(&plan_import_project(&root, None).unwrap(), &root);
    }

    #[test]
    fn pie_from_a_package_feature_is_not_forced_on() {
        let root = bevy_game(
            "feature-pie",
            &with_bevy("bevy = \"0.20\"\njackdaw_runtime = \"0.19\"\n"),
        );
        let cargo = std::fs::read_to_string(root.join("Cargo.toml")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            format!("{cargo}\n[features]\neditor = [\"jackdaw_runtime/pie\"]\n"),
        )
        .unwrap();
        let plan = plan_import_project(&root, None).unwrap();
        assert!(planned_contents(&plan, &root.join("Cargo.toml")).is_none());
        assert!(
            planned_contents(&plan, &root.join("src/lib.rs"))
                .is_some_and(|lib| lib.contains("jackdaw_runtime::JackdawPlugin")),
            "the plugin needs no feature"
        );
        assert!(
            planned_contents(&plan, &root.join("src/main.rs")).is_none(),
            "maybe_windowless only exists with pie, which a default build may lack"
        );
        assert!(
            plan.notes
                .iter()
                .any(|note| note.contains("maybe_windowless"))
        );
    }

    #[test]
    fn a_member_inherits_the_runtime_its_workspace_declares() {
        let root = temp_dir("ws-declares-runtime");
        std::fs::write(
            root.join("Cargo.toml"),
            "[workspace]\nresolver = \"3\"\nmembers = [\"game\"]\n\n\
             [workspace.dependencies]\njackdaw_runtime = \"0.19\"\n",
        )
        .unwrap();
        let member = root.join("game");
        std::fs::create_dir_all(member.join("src")).unwrap();
        std::fs::write(
            member.join("Cargo.toml"),
            with_bevy(
                "[package]\nname = \"game\"\nversion = \"0.1.0\"\nedition = \"2024\"\n\n\
             [dependencies]\nbevy = \"0.20\"\n",
            ),
        )
        .unwrap();
        std::fs::write(member.join("src/lib.rs"), "pub struct GamePlugin;\n").unwrap();

        let plan = plan_import_project(&root, None).unwrap();
        let cargo = planned_contents(&plan, &member.join("Cargo.toml")).unwrap();
        assert!(
            cargo.contains("jackdaw_runtime = { workspace = true, features = [\"pie\"] }"),
            "got:\n{cargo}"
        );
    }

    #[test]
    fn an_uneditable_plugin_keeps_the_manual_note() {
        let root = bevy_game("manual-plugin", &with_bevy("bevy = \"0.20\"\n"));
        std::fs::write(
            root.join("src/lib.rs"),
            "pub struct GamePlugin;\nimpl Plugin for GamePlugin {}\n",
        )
        .unwrap();
        let plan = plan_import_project(&root, None).unwrap();
        assert!(planned_contents(&plan, &root.join("src/lib.rs")).is_none());
        assert!(
            plan.notes
                .iter()
                .any(|note| note.contains("app.add_plugins(jackdaw_runtime::JackdawPlugin)")),
            "got: {:?}",
            plan.notes
        );
    }

    #[test]
    fn import_plan_is_side_effect_free_until_applied() {
        let root = temp_dir("preview");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            with_bevy("[package]\nname = \"preview\"\nversion = \"0.1.0\"\n\n[dependencies]\nbevy = \"0.20\"\n"),
        )
        .unwrap();
        std::fs::write(
            root.join("src/main.rs"),
            "use bevy::prelude::*;\nfn main() { App::new().add_plugins(DefaultPlugins).run(); }\n",
        )
        .unwrap();

        let main_before = std::fs::read_to_string(root.join("src/main.rs")).unwrap();
        let plan = plan_import_project(&root, None).unwrap();
        assert!(!plan.is_empty());
        assert!(!root.join("jackdaw.toml").exists());
        assert!(!root.join("src/lib.rs").exists());
        assert_eq!(
            std::fs::read_to_string(root.join("src/main.rs")).unwrap(),
            main_before
        );

        apply_import_plan(&plan).unwrap();
        assert!(root.join("jackdaw.toml").exists());
        assert!(root.join("src/lib.rs").exists());
        assert!(root.join(".jackdaw").is_dir());
    }
}
