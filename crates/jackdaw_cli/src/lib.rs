//! Headless command implementations used by the public `jd` executable.
//!
//! This remains an internal library so the public executable and release
//! tooling share the bevy-light
//! [`jackdaw_project_build`] pipeline, so it stays small.
//!
//! Commands:
//!
//! ```text
//! build [--project <path>] [--config <label>]
//!                            Build the project so a running editor
//!                            picks up new or changed components; with
//!                            --config, one jackdaw.toml run's target.
//! run   [--project <path>] [--config <label>]
//!                            Build, then launch the game standalone;
//!                            --config launches one jackdaw.toml run
//!                            with its target and launch environment.
//! setup                      Build the SDK into the cache (one-time).
//! doctor                     Report SDK build prerequisites.
//! ```

#![expect(
    clippy::print_stdout,
    clippy::print_stderr,
    reason = "jd is a user-facing terminal tool; stdout/stderr is its output channel"
)]

use std::path::{Path, PathBuf};
use std::process::ExitCode;

use jackdaw_env::rust_env_command;
use jackdaw_project_build::bootstrap::{self, SetupProgress};
use jackdaw_project_build::build_tools::CheckStatus;
use jackdaw_project_build::cargo_meta::{self, CargoMeta};
use jackdaw_project_build::run_manifest::{self, RunEntry, RunManifest, RunTargetSpec};
use jackdaw_project_build::{
    BuildEvent, BuildLoad, CargoTarget, build_project_binary_with_load, build_project_dylib,
    prepare_game_command, sdk_paths,
};
use jackdaw_schema::{read_schema, schema_path};

pub mod package;

/// Dispatch the bevy-light subset of a `jd` invocation.
pub fn run_args(args: &[String]) -> ExitCode {
    match args.first().map(String::as_str) {
        Some("build") => cmd_build(&args[1..]),
        Some("run") => cmd_run(&args[1..]),
        Some("setup") => cmd_setup(),
        Some("doctor") => cmd_doctor(&args[1..]),
        Some("--version" | "-V" | "version") => {
            println!(
                "jd {} (targets bevy {})",
                jackdaw_project_build::build_name(),
                jackdaw_project_build::bevy_description()
            );
            ExitCode::SUCCESS
        }
        // Help and unknown commands belong to the `jd` executable,
        // which owns the real command list. A second usage string here
        // listed neither `new` nor `import`, and the fallthrough made it
        // the one users saw after a typo.
        other => {
            eprintln!(
                "jd: `{}` is not one of this library's commands; run `jd --help`",
                other.unwrap_or_default()
            );
            ExitCode::FAILURE
        }
    }
}

/// `jd setup`: build the SDK into `~/.jackdaw/sdk/...` so builds
/// work without a jackdaw source checkout. Requires a binary built with
/// the `embed-recipe` feature (packaged releases).
fn cmd_setup() -> ExitCode {
    if bootstrap::needs_setup() {
        println!(
            "jd setup: building the extension SDK once; this usually takes {}",
            bootstrap::SDK_BUILD_ESTIMATE
        );
    }
    // Print phase headers; cargo's own progress reaches the terminal on
    // inherited stderr, so per-crate events are left for the editor's bar.
    let report = |event: SetupProgress| {
        if let SetupProgress::Phase(phase) = event {
            println!("jd setup: {phase}");
        }
    };
    match bootstrap::ensure_sdk(report) {
        Ok(cache) => {
            println!("jd setup: SDK ready at {}", cache.display());
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprintln!("jd setup: {err}");
            ExitCode::FAILURE
        }
    }
}

/// How `jd doctor` grades the SDK.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SdkGrade {
    Ok,
    /// Missing or unusable, which matters only to an extension.
    Info,
    Fail,
}

fn grade_sdk(usable: bool, project_is_extension: bool) -> SdkGrade {
    match (usable, project_is_extension) {
        (true, _) => SdkGrade::Ok,
        (false, false) => SdkGrade::Info,
        (false, true) => SdkGrade::Fail,
    }
}

/// Report which of the three install paths supplied the SDK, and
/// whether it is usable. Only editor extensions build against it, so a
/// missing or broken one fails the report only for an extension project.
fn report_sdk(project_is_extension: bool) -> bool {
    let sdk = resolve_sdk(dev_workspace().as_deref());
    let problems = sdk.problems();
    let usable = problems.is_empty() && sdk.manifest.is_file();
    let grade = grade_sdk(usable, project_is_extension);
    let tag = match grade {
        SdkGrade::Ok => "[ ok ]",
        SdkGrade::Info => "[info]",
        SdkGrade::Fail => "[fail]",
    };
    if usable {
        println!(
            "  {tag} SDK: {} ({})",
            sdk.origin.describe(),
            sdk.dylib.display()
        );
    } else if problems.is_empty() {
        let scope = if project_is_extension {
            "this extension builds against it"
        } else {
            "only editor extensions need it"
        };
        println!("  {tag} SDK: not built; {scope}");
        println!(
            "         build it with: jd setup (usually {})",
            bootstrap::SDK_BUILD_ESTIMATE
        );
    } else {
        println!(
            "  {tag} SDK: {} at {} is not usable",
            sdk.origin.describe(),
            sdk.dylib.display()
        );
        for problem in problems {
            println!("         {problem}");
        }
        println!("         fix: {}", jackdaw_project_build::sdk_remedy(&sdk));
    }
    grade != SdkGrade::Fail
}

/// `jd doctor [--project <path>]`: report the tools an SDK build needs,
/// so a prerequisite gap is visible before a long compile rather than
/// after, followed by the state of a project when one is in scope. The
/// single "why is my project not working" command.
fn cmd_doctor(args: &[String]) -> ExitCode {
    let mut ok = true;

    println!("environment");
    for check in &bootstrap::check_prerequisites() {
        let tag = match check.status {
            CheckStatus::Ok => "[ ok ]",
            CheckStatus::Warn => "[warn]",
            CheckStatus::Fail => "[fail]",
        };
        ok &= check.status != CheckStatus::Fail;
        println!("  {tag} {}: {}", check.name, check.detail);
        if let Some(fix) = &check.fix {
            println!("         fix: {fix}");
        }
    }

    // A project is in scope when asked for explicitly, or when the
    // working directory is one. Running `jd doctor` anywhere else stays
    // a pure environment report.
    let requested = parse_project_arg(args);
    let explicit = requested.is_some();
    let root = requested
        .or_else(|| std::env::current_dir().ok())
        .and_then(|dir| dunce::canonicalize(dir).ok())
        .filter(|dir| explicit || dir.join("Cargo.toml").is_file());
    // The SDK belongs in the environment section, not the project one:
    // it is a property of the install and the same for every project.
    // Whether its absence is a failure depends on the project in scope.
    ok &= report_sdk(root.as_deref().is_some_and(bootstrap::project_needs_sdk));
    match root {
        Some(root) => {
            println!("\nproject: {}", root.display());
            ok &= report_project(&root);
        }
        // Say so, rather than leaving "all checks passed" to imply the
        // project was inspected and found healthy.
        None => println!(
            "\nproject: none here. Run this inside a project, or pass --project <path>, to \
             check one."
        ),
    }

    if ok {
        println!("\njd doctor: all checks passed");
        ExitCode::SUCCESS
    } else {
        eprintln!("\njd doctor: some checks failed (see above)");
        ExitCode::FAILURE
    }
}

/// Report whether a project is set up, what jackdaw resolved from it,
/// and whether its extracted type schema is current. Returns whether
/// everything that would block a build is in place.
fn report_project(root: &Path) -> bool {
    use jackdaw_project_build::project_manifest::{self, PinStatus};

    let mut ok = true;
    let pass = |detail: String| println!("  [ ok ] {detail}");

    if !root.join("Cargo.toml").is_file() {
        println!("  [fail] no Cargo.toml here");
        println!("         fix: run `jd new <name>` to create a project");
        return false;
    }

    let manifest = match project_manifest::ProjectManifest::read_checked(root) {
        Ok(manifest) if !project_manifest::ProjectManifest::exists(root) => {
            ok = false;
            println!("  [fail] jackdaw.toml: missing, this project is not set up yet");
            println!("         fix: jd import --apply {}", root.display());
            manifest
        }
        Ok(manifest) => {
            pass("jackdaw.toml: present".to_string());
            manifest
        }
        Err(detail) => {
            // A file that does not parse reads downstream as "no
            // overrides set", so without this the user gets a healthy
            // report while their plugin and package keys are ignored.
            ok = false;
            println!("  [fail] jackdaw.toml: does not parse: {detail}");
            println!("         fix: correct the file, or delete it and run `jd import --apply`");
            project_manifest::ProjectManifest::default()
        }
    };

    let package = jackdaw_project_build::cargo_meta::resolve_project_package(
        root,
        manifest.package.as_deref(),
    );
    match &package {
        Ok(package) => {
            pass(format!(
                "package: {} (crate `{}`)",
                package.name, package.crate_name
            ));
            if package.has_lib {
                pass("library target: present".to_string());
            } else {
                ok = false;
                println!("  [fail] library target: missing");
                println!(
                    "         fix: the editor only sees components in a library; \
                     run `jd import --apply` to add one"
                );
            }
            let extension = jackdaw_project_build::detect::detect_extension(&package.dir);
            // Check any configured plugin against what the crate really
            // declares. Echoing the key back would certify a name that
            // only fails later in doctor re-runs or setup notes.
            let found = jackdaw_project_build::detect::plugin_paths(&package.dir);
            let configured = manifest.plugin.as_deref();
            // A candidate not reachable from the crate root is not a
            // usable plugin name, so requiring a `crate_path` here keeps
            // doctor from blessing a key that cannot be referenced.
            let resolved = configured.and_then(|name| {
                found.iter().find(|candidate| {
                    candidate.crate_path.is_some()
                        && (candidate.type_name == name
                            || candidate.crate_path.as_deref() == Some(name))
                })
            });
            let detected =
                jackdaw_project_build::detect::detect_plugin(&package.dir, &package.crate_name)
                    .and_then(|path| path.split_once("::").map(|(_, name)| name.to_string()));
            if extension.is_none() {
                ok &= report_runtime_wiring(root, &package.dir);
            }
            match (&extension, configured, &resolved) {
                (Some((_, name)), ..) => pass(format!("editor extension: {name}")),
                (None, Some(name), None) => {
                    ok = false;
                    let unreachable = found.iter().any(|candidate| {
                        candidate.type_name == name && candidate.crate_path.is_none()
                    });
                    if unreachable {
                        println!(
                            "  [fail] game plugin: `{name}` is declared but not reachable from \
                             outside the crate"
                        );
                        println!(
                            "         fix: make its module `pub mod`, or re-export it from \
                             lib.rs with `pub use`"
                        );
                    } else {
                        println!(
                            "  [fail] game plugin: jackdaw.toml names `{name}`, which {} does \
                             not declare",
                            package.crate_name
                        );
                        let usable: Vec<&str> = found
                            .iter()
                            .filter(|candidate| candidate.crate_path.is_some())
                            .map(|candidate| candidate.type_name.as_str())
                            .collect();
                        if usable.is_empty() {
                            println!(
                                "         fix: this crate declares no reachable \
                                 `impl Plugin for ...`; add one, or remove the `plugin` key"
                            );
                        } else {
                            println!(
                                "         fix: set `plugin` to one of {}, or remove the key",
                                usable.join(", ")
                            );
                        }
                    }
                }
                (None, Some(_), Some(candidate)) => {
                    pass(format!("game plugin: {}", candidate.type_name));
                }
                (None, None, _) => match detected {
                    Some(name) => pass(format!("game plugin: {name}")),
                    None => println!(
                        "  [warn] game plugin: none declared; the editor still reads this \
                         crate's components. Play launches your cargo binary, so add a Bevy \
                         Plugin in the library and wire it from `main.rs` when you want \
                         gameplay under Play"
                    ),
                },
            }
            ok &= report_run_targets(root, &package.name);
        }
        Err(error) => {
            ok = false;
            println!("  [fail] package: {error}");
        }
    }

    match project_manifest::compare_project(root, &manifest) {
        PinStatus::Match => pass(format!(
            "versions: jackdaw {} / bevy {}",
            jackdaw_project_build::VERSION,
            jackdaw_project_build::BEVY_VERSION
        )),
        PinStatus::Unpinned => println!(
            "  [warn] versions: this project records none; it will be pinned on the next setup"
        ),
        PinStatus::JackdawDiffers { pinned, running } => println!(
            "  [warn] versions: set up with jackdaw {pinned}, running {running} (same bevy, so \
             builds still work)"
        ),
        PinStatus::BevyDiffers { pinned, running } => {
            ok = false;
            println!("  [fail] versions: set up for bevy {pinned}, this jackdaw targets {running}");
            println!(
                "         fix: install the jackdaw release for bevy {pinned}, or migrate the \
                 project to bevy {running}"
            );
        }
    }

    let jackdaw_dir = root.join(".jackdaw");
    match read_schema(&jackdaw_dir) {
        Some(schema) => pass(format!(
            "project types: {} components known ({})",
            schema.components.len(),
            schema_path(&jackdaw_dir).display()
        )),
        None => println!(
            "  [warn] project types: not built yet; run `jd build` so the editor sees your \
             components"
        ),
    }

    // A project whose requirements cannot resolve never reaches a
    // compiler, so every other check above can pass while nothing
    // builds. This is the one check that exercises the manifest a
    // scaffold or import actually produced.
    match resolve_dependencies(root) {
        Ok(()) => pass("dependencies: resolve".to_string()),
        Err(detail) => {
            ok = false;
            println!("  [fail] dependencies: {detail}");
            // Which jackdaw wrote the manifest decides what its jackdaw
            // dependency can be reached through at all, and a project set
            // up by an unreleased build names something no registry has.
            // Nothing in the manifest says so, so say it here.
            if let Some(note) =
                jackdaw_project_build::build_source::build_source().resolution_note()
            {
                println!("         note: {note}");
            }
            println!(
                "         fix: check the versions in Cargo.toml; `cargo update` refreshes the \
                 index if a release is newer than your cached copy"
            );
        }
    }

    ok
}

/// Report every `[[run]]` that names a cargo target: its bin/example
/// exists in the project's metadata, and the profile it asks for is one
/// cargo will accept. Returns whether nothing launch-blocking is wrong;
/// an unavailable profile is only a warning, since cargo itself refuses
/// it in a blink rather than mid-compile.
fn report_run_targets(root: &Path, package_name: &str) -> bool {
    // A missing or broken jackdaw.toml is already reported above; there
    // are no runs in it worth checking here.
    let Ok(manifest) = read_run_manifest(root) else {
        return true;
    };
    let mut ok = true;
    let meta = CargoMeta::load(root);
    let declared = std::fs::read_to_string(root.join("Cargo.toml"))
        .map(|text| run_manifest::declared_profiles(&text))
        .unwrap_or_default();
    for run in &manifest.runs {
        let Some(target) = run.target.as_ref() else {
            continue;
        };
        let label = run.label();
        // Shape first: a target that cannot become a cargo command is
        // wrong whatever the metadata says.
        if let Err(reason) = target.validate() {
            ok = false;
            println!("  [fail] run `{label}`: {reason}");
            continue;
        }
        // Metadata failing to run is already reported above (the
        // `package:` line); every run of it would only repeat that.
        if let Some(meta) = &meta {
            match cargo_meta::check_run_target(meta, package_name, &target.cargo_target()) {
                Ok(()) => {
                    if let Some((kind, name)) = target.cargo_target().named() {
                        let detail = match &target.profile {
                            Some(profile) => {
                                format!("{kind} `{name}` present, profile `{profile}`")
                            }
                            None => format!("{kind} `{name}` present"),
                        };
                        println!("  [ ok ] run `{label}`: {detail}");
                    } else {
                        // A validated target always names one; this is
                        // the shape the package default would take.
                        println!("  [ ok ] run `{label}`: the package's default binary");
                    }
                }
                Err(reason) => {
                    ok = false;
                    println!("  [fail] run `{label}`: {reason}");
                    println!(
                        "         fix: name one of the targets the package declares, or add it \
                         in Cargo.toml"
                    );
                }
            }
        }
        if let Some(profile) = target
            .profile
            .as_deref()
            .filter(|name| !name.trim().is_empty())
            && !run_manifest::profile_is_available(profile, &declared)
        {
            println!(
                "  [warn] run `{label}`: profile `{profile}` is neither dev, release, nor a \
                 [profile.{profile}] Cargo.toml declares; cargo will refuse the build"
            );
        }
    }
    ok
}

/// Report the four pieces of runtime wiring component discovery and Play
/// depend on. Returns whether nothing that blocks them is missing.
fn report_runtime_wiring(root: &Path, package_dir: &Path) -> bool {
    use jackdaw_project_build::runtime_wiring::{RuntimeDependency, RuntimeWiring};

    let wiring = RuntimeWiring::inspect(package_dir);
    let import_fix = format!("jd import --apply {}", root.display());
    let fail = |problem: &str, fix: &str| {
        println!("  [fail] {problem}");
        println!("         fix: {fix}");
    };
    let mut ok = true;
    match wiring.dependency {
        RuntimeDependency::Plain => println!("  [ ok ] runtime dependency: jackdaw_runtime"),
        RuntimeDependency::Missing => {
            ok = false;
            fail(
                "runtime dependency: Cargo.toml does not depend on jackdaw_runtime, so the \
                 editor cannot read this game's components",
                &import_fix,
            );
        }
        RuntimeDependency::Unsupported(form) => {
            ok = false;
            fail(
                &format!(
                    "runtime dependency: jackdaw_runtime is declared as {form}, so a default \
                     build may not link it"
                ),
                "make it a plain [dependencies] entry, then run `jd import --apply`",
            );
        }
    }
    if wiring.pie_available() {
        println!("  [ ok ] runtime feature: pie enabled");
    } else {
        ok = false;
        fail(
            "runtime feature: jackdaw_runtime is missing the `pie` feature, so Play cannot \
             reach the game",
            &import_fix,
        );
    }
    for removed in removed_feature_problems(root, package_dir) {
        ok = false;
        fail(&removed.problem, &removed.fix);
        if let Some(note) = removed.note {
            println!("         note: {note}");
        }
    }
    if wiring.plugin {
        println!("  [ ok ] runtime plugin: JackdawPlugin added");
    } else {
        ok = false;
        fail(
            "runtime plugin: nothing adds JackdawPlugin, so component discovery and Play time out",
            &import_fix,
        );
    }
    if wiring.windowless {
        println!("  [ ok ] embedded Play: DefaultPlugins pass through maybe_windowless");
    } else if !wiring.has_main {
        println!(
            "  [warn] embedded Play: not checked, no src/main.rs in this package; pass \
             DefaultPlugins through jackdaw_runtime::maybe_windowless where the game builds its App"
        );
    } else {
        ok = false;
        fail(
            "embedded Play: main.rs does not pass DefaultPlugins through maybe_windowless, so \
             Play cannot show the game in the editor",
            &import_fix,
        );
    }
    ok
}

/// A failed project check, with the command that fixes it.
struct Problem {
    problem: String,
    fix: String,
    note: Option<String>,
}

/// The `jackdaw_runtime` features the game asks for that no longer exist.
/// Upgrading drops them and records the module that replaced each.
fn removed_feature_problems(root: &Path, package_dir: &Path) -> Vec<Problem> {
    use jackdaw_project_build::modules::{GameDependencies, ModuleCatalog};
    use jackdaw_project_build::project_manifest::ProjectManifest;

    let game = GameDependencies::read(package_dir, root);
    let command = if ProjectManifest::exists(root) {
        "upgrade"
    } else {
        "import"
    };
    ModuleCatalog::builtin()
        .removed_runtime_features(&game)
        .into_iter()
        .map(|(feature, module)| Problem {
            problem: format!(
                "runtime feature: jackdaw_runtime no longer has `{feature}`, so the game does not \
                 build; the {} module replaces it",
                module.name
            ),
            fix: format!("jd {command} --apply {}", root.display()),
            note: module.unavailable.as_ref().map(|reason| {
                format!(
                    "{} is not compatible with this editor line yet: {reason}",
                    module.name
                )
            }),
        })
        .collect()
}

/// Ask cargo to resolve the project's full dependency graph, reporting
/// its first error line. Unlike the `--no-deps` metadata call used to
/// find the package, this one does the version solving, which is where
/// an unpublished or mistyped requirement surfaces.
fn resolve_dependencies(root: &Path) -> Result<(), String> {
    let output = rust_env_command("cargo")
        .current_dir(root)
        .args(["metadata", "--format-version", "1"])
        .output()
        .map_err(|error| format!("could not run cargo: {error}"))?;
    if output.status.success() {
        return Ok(());
    }
    let stderr = String::from_utf8_lossy(&output.stderr);
    Err(stderr
        .lines()
        .map(str::trim)
        .find(|line| line.starts_with("error"))
        .unwrap_or("cargo could not resolve this project's dependencies")
        .to_string())
}

/// `jd build [--project <path>] [--config <label>]`: run the same
/// pipeline the editor runs. A game persists `.jackdaw/schema.json`,
/// which a running editor watches and reloads; a project that is only
/// an extension builds its library against the SDK for `jd extension
/// pack`. `--config` selects one `[[run]]` of `jackdaw.toml` and builds
/// its cargo target. Defaults to the current directory.
fn cmd_build(args: &[String]) -> ExitCode {
    let root = match resolve_root(args) {
        Ok(root) => root,
        Err(code) => return code,
    };
    let Some(label) = parse_config_arg(args) else {
        return match build_project(&root, None) {
            Ok(_) => ExitCode::SUCCESS,
            Err(code) => code,
        };
    };
    let entry = match resolve_run_config(&root, &label) {
        Ok(entry) => entry,
        Err(message) => {
            eprintln!("jd build: {message}");
            return ExitCode::FAILURE;
        }
    };
    let target = entry.target.as_ref().map(RunTargetSpec::cargo_target);
    match build_project(&root, target.as_ref()) {
        Ok(_) => ExitCode::SUCCESS,
        Err(code) => code,
    }
}

/// `jd run [--project <path>] [--config <label>]`: build the game
/// (refreshing the schema a running editor reloads), then launch it. A
/// build failure aborts before running, since the game would fail to
/// compile anyway. With `--config`, the selected `[[run]]` decides the
/// whole launch — its target is what gets built, its env/args/cwd are
/// what the built binary launches with — mirroring the editor's Play of
/// that run (a bare process, not a `cargo run`). Without it, this is
/// the historical behaviour: a bare `cargo run` in the project root.
fn cmd_run(args: &[String]) -> ExitCode {
    let root = match resolve_root(args) {
        Ok(root) => root,
        Err(code) => return code,
    };
    let Some(label) = parse_config_arg(args) else {
        if let Err(code) = build_project(&root, None) {
            return code;
        }
        println!("jackdaw run: launching {}", root.display());
        return match rust_env_command("cargo")
            .arg("run")
            .current_dir(&root)
            .status()
        {
            Ok(status) if status.success() => ExitCode::SUCCESS,
            Ok(status) => ExitCode::from(u8::try_from(status.code().unwrap_or(1)).unwrap_or(1)),
            Err(err) => {
                eprintln!("jackdaw run: failed to launch the game: {err}");
                ExitCode::FAILURE
            }
        };
    };
    let entry = match resolve_run_config(&root, &label) {
        Ok(entry) => entry,
        Err(message) => {
            eprintln!("jd run: {message}");
            return ExitCode::FAILURE;
        }
    };
    let target = entry.target.as_ref().map(RunTargetSpec::cargo_target);
    let binary = match build_project(&root, target.as_ref()) {
        Ok(binary) => binary,
        Err(code) => return code,
    };
    println!("jackdaw run: launching {label} ({})", binary.display());
    // The bare-process semantics the editor's Play gives this run: the
    // built binary with the run's cwd, env and argv, nothing else.
    let cwd = match entry.cwd.as_ref() {
        Some(dir) => root.join(dir),
        None => root.clone(),
    };
    let mut command = std::process::Command::new(&binary);
    prepare_game_command(&mut command, &binary);
    command.current_dir(&cwd).envs(&entry.env).args(&entry.args);
    match command.status() {
        Ok(status) if status.success() => ExitCode::SUCCESS,
        Ok(status) => ExitCode::from(u8::try_from(status.code().unwrap_or(1)).unwrap_or(1)),
        Err(err) => {
            eprintln!("jackdaw run: failed to launch the game: {err}");
            ExitCode::FAILURE
        }
    }
}

/// Resolve and canonicalize the target project directory from
/// `--project`/`-p` or a bare path, defaulting to the current directory.
fn resolve_root(args: &[String]) -> Result<PathBuf, ExitCode> {
    let root =
        parse_project_arg(args).unwrap_or_else(|| std::env::current_dir().unwrap_or_default());
    dunce::canonicalize(&root).map_err(|err| {
        eprintln!("jd: cannot resolve project path {}: {err}", root.display());
        ExitCode::FAILURE
    })
}

/// Build the project at `root`: a game as its own binary with its
/// schema persisted, a project that is only an extension against the
/// SDK. `target` narrows a game build to one run's cargo target.
/// Returns the built artifact's path, so `jd run --config` can launch
/// what was built.
fn build_project(root: &Path, target: Option<&CargoTarget>) -> Result<PathBuf, ExitCode> {
    let spec = match jackdaw_project_build::shim_spec_for_project(root) {
        Ok(spec) => spec,
        Err(error) => {
            eprintln!("jackdaw build: {error}");
            return Err(ExitCode::FAILURE);
        }
    };

    let jackdaw_dir = root.join(".jackdaw");
    if bootstrap::project_needs_sdk(root) {
        // A run target selects a game binary; an extension builds its
        // library and has none to select.
        if target.is_some() {
            eprintln!(
                "jackdaw build: --config selects a game run target, but this project is an editor \
                 extension"
            );
            return Err(ExitCode::FAILURE);
        }
        return build_extension(root, &spec, &jackdaw_dir);
    }

    println!("jackdaw build: building {}", root.display());
    // Both accounts of the build reach the reporter: rustc's diagnostics
    // parsed out of the JSON stream, and cargo's own stderr on a failure.
    let mut report = |event: BuildEvent| {
        if let BuildEvent::Log(line) = event {
            eprintln!("{line}");
        }
    };
    match build_project_binary_with_load(
        &spec,
        &jackdaw_dir,
        target,
        BuildLoad::Foreground,
        &mut report,
    ) {
        Ok(build) => {
            let components = build
                .schema
                .as_ref()
                .map(|s| s.components.len())
                .unwrap_or(0);
            println!(
                "jackdaw build: ok ({components} components); binary at {}, schema at {}",
                build.binary.display(),
                schema_path(&jackdaw_dir).display()
            );
            Ok(build.binary)
        }
        Err(err) => {
            eprintln!("jackdaw build: failed: {err}");
            Err(ExitCode::FAILURE)
        }
    }
}

/// Build an extension's library against the SDK, building the SDK first
/// when this install has not yet.
fn build_extension(
    root: &Path,
    spec: &jackdaw_project_build::shim::ShimSpec,
    jackdaw_dir: &Path,
) -> Result<PathBuf, ExitCode> {
    if bootstrap::needs_setup() {
        println!(
            "jackdaw build: building the extension SDK first; this usually takes {}",
            bootstrap::SDK_BUILD_ESTIMATE
        );
        let report = |event: SetupProgress| {
            if let SetupProgress::Phase(phase) = event {
                println!("jackdaw build: {phase}");
            }
        };
        if let Err(err) = bootstrap::ensure_sdk(report) {
            eprintln!("jackdaw build: SDK setup failed: {err}");
            return Err(ExitCode::FAILURE);
        }
    }
    let dev_workspace = dev_workspace();
    let sdk = resolve_sdk(dev_workspace.as_deref());

    println!("jackdaw build: building extension {}", root.display());
    let mut report = |event: BuildEvent| {
        if let BuildEvent::Log(line) = event {
            eprintln!("{line}");
        }
    };
    match build_project_dylib(
        spec,
        jackdaw_dir,
        &sdk,
        dev_workspace.as_deref(),
        &mut report,
    ) {
        Ok(build) => {
            println!(
                "jackdaw build: ok; extension library at {}",
                build.dylib.display()
            );
            Ok(build.dylib)
        }
        Err(err) => {
            eprintln!("jackdaw build: failed: {err}");
            Err(ExitCode::FAILURE)
        }
    }
}

/// The jackdaw workspace this CLI was built from, two levels up from
/// the crate. Present in a dev checkout (even after `cargo install`,
/// the baked path still points at the real source tree); absent on a
/// machine that only has a packaged install.
fn dev_workspace() -> Option<PathBuf> {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|p| p.parent())
        .map(PathBuf::from)
        .filter(|p| p.exists())
}

/// Resolve the SDK the build pipeline needs.
///
/// The ordinary resolution runs first, so `jd doctor` reports the SDK
/// the editor would actually use. Taking the workspace scan first
/// instead made the two disagree: the scan has no view of whether a
/// checkout's SDK is current, so `doctor` would report one SDK as fine
/// while the editor built against another.
///
/// The scan remains as a fallback, for an installed `jd` on `PATH`
/// whose own directory holds nothing: the exe-relative default cannot
/// find a checkout it does not live in.
fn resolve_sdk(dev_workspace: Option<&Path>) -> sdk_paths::SdkPaths {
    let computed = sdk_paths::SdkPaths::compute();
    if computed.dylib_exists() {
        return computed;
    }
    if let Some(workspace) = dev_workspace
        && let Some(sdk) = sdk_paths::SdkPaths::for_workspace_detect(workspace)
    {
        return sdk;
    }
    computed
}

fn parse_project_arg(args: &[String]) -> Option<PathBuf> {
    let mut it = args.iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--project" | "-p" => return it.next().map(PathBuf::from),
            // Its value is a run label, not a project path, and must not
            // read as a bare positional below.
            "--config" => {
                it.next();
            }
            other if !other.starts_with('-') => return Some(PathBuf::from(other)),
            _ => {}
        }
    }
    None
}

/// The `--config <label>` value of a `run`/`build` invocation: the run
/// of `jackdaw.toml` it selects, target and launch environment together.
fn parse_config_arg(args: &[String]) -> Option<String> {
    let mut it = args.iter();
    while let Some(arg) = it.next() {
        if arg == "--config" {
            return it.next().cloned();
        }
    }
    None
}

/// The `[[run]]` entries of `jackdaw.toml`, read the way the CLI needs
/// them: names, targets, and the launch environment `jd run --config`
/// applies. A missing or broken file is an error naming the file, since
/// a `--config` selects a run and without the file there is nothing to
/// select from.
fn read_run_manifest(root: &Path) -> Result<RunManifest, String> {
    let path = root.join("jackdaw.toml");
    let text = std::fs::read_to_string(&path)
        .map_err(|_| format!("no jackdaw.toml at {} to pick a run from", path.display()))?;
    RunManifest::parse(&text).map_err(|error| format!("jackdaw.toml does not parse: {error}"))
}

/// The run `--config <label>` names, checked to the point a build can
/// start: present in `jackdaw.toml`, its target schema-valid, and its
/// package and bin/example real per `cargo metadata` — so a typo fails
/// here, with the names that are available, rather than inside a build.
fn resolve_run_config(root: &Path, label: &str) -> Result<RunEntry, String> {
    let manifest = read_run_manifest(root)?;
    let Some(entry) = manifest.by_name(label) else {
        let found = if manifest.runs.is_empty() {
            "jackdaw.toml lists no runs".to_string()
        } else {
            let labels: Vec<&str> = manifest.runs.iter().map(RunEntry::label).collect();
            format!("found: {}", labels.join(", "))
        };
        return Err(format!("`{label}` is not a run in jackdaw.toml ({found})"));
    };
    let entry = entry.clone();
    if let Some(target) = &entry.target {
        target.validate()?;
        let spec = jackdaw_project_build::shim_spec_for_project(root)
            .map_err(|error| error.to_string())?;
        // Metadata the build would run anyway; if it cannot run, the
        // build reports that in its own words, so the check stands down
        // rather than failing the run for cargo's sake.
        if let Some(meta) = CargoMeta::load(root) {
            cargo_meta::check_run_target(&meta, &spec.package_name, &target.cargo_target())?;
        }
    }
    Ok(entry)
}

#[cfg(test)]
mod tests {
    use super::{
        SdkGrade, grade_sdk, parse_config_arg, parse_project_arg, read_run_manifest,
        removed_feature_problems, resolve_run_config,
    };

    fn args(list: &[&str]) -> Vec<String> {
        list.iter().map(std::string::ToString::to_string).collect()
    }

    #[test]
    fn the_config_flag_reads_its_label() {
        assert_eq!(
            parse_config_arg(&args(&["--project", "x", "--config", "Server"])),
            Some("Server".to_string())
        );
        assert_eq!(
            parse_config_arg(&args(&["--config", "Play"])),
            Some("Play".to_string())
        );
        assert_eq!(parse_config_arg(&args(&["--project", "x"])), None);
        assert_eq!(parse_config_arg(&args(&[])), None);
    }

    /// The label is a label, not a project path: `--config Server` must
    /// not make the project resolve to a directory named Server.
    #[test]
    fn a_config_label_is_not_read_as_a_project_path() {
        assert_eq!(
            parse_project_arg(&args(&["--config", "Server"])),
            None,
            "the label is consumed by --config"
        );
        assert_eq!(
            parse_project_arg(&args(&["--project", "x", "--config", "Server"])),
            Some("x".into())
        );
    }

    fn project_with(name: &str, jackdaw_toml: &str) -> std::path::PathBuf {
        let root = std::env::temp_dir().join(format!("jackdaw_cli_{name}_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("jackdaw.toml"), jackdaw_toml).unwrap();
        root
    }

    const RUNS: &str = r#"
[[run]]
name = "Play"

[[run]]
name = "Server"
target = { bin = "server" }
"#;

    #[test]
    fn an_unknown_label_lists_the_runs_the_manifest_has() {
        let root = project_with("cfg-labels", RUNS);
        let message = resolve_run_config(&root, "Nope").unwrap_err();
        assert!(message.contains("`Nope` is not a run"), "{message}");
        assert!(message.contains("Play, Server"), "{message}");
        let _ = std::fs::remove_dir_all(&root);
    }

    /// Validation runs before any package resolution, so an invalid
    /// target reports its shape without invoking cargo.
    #[test]
    fn an_invalid_target_reports_its_shape_before_resolving_anything() {
        let root = project_with(
            "cfg-invalid",
            "[[run]]\ntarget = { bin = \"a\", example = \"b\" }",
        );
        let message = resolve_run_config(&root, "Play").unwrap_err();
        assert!(message.contains("both"), "{message}");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_missing_manifest_names_the_file() {
        let root =
            std::env::temp_dir().join(format!("jackdaw_cli_cfg_missing_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let message = read_run_manifest(&root).unwrap_err();
        assert!(message.contains("jackdaw.toml"), "{message}");
        let _ = std::fs::remove_dir_all(&root);
    }

    fn game_with_runtime(name: &str, features: &str) -> std::path::PathBuf {
        let root = std::env::temp_dir().join(format!("jackdaw_cli_{name}_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(
            root.join("Cargo.toml"),
            format!(
                "[package]\nname = \"g\"\nversion = \"0.1.0\"\n\n[dependencies]\n\
                 jackdaw_runtime = {{ version = \"0.19\", features = [{features}] }}\n"
            ),
        )
        .unwrap();
        root
    }

    #[test]
    fn a_removed_runtime_feature_fails_with_the_upgrade_that_drops_it() {
        let root = game_with_runtime("removed-feature", "\"physics\", \"pie\"");
        std::fs::write(root.join("jackdaw.toml"), "").unwrap();
        let problems = removed_feature_problems(&root, &root);
        assert_eq!(problems.len(), 1);
        assert!(problems[0].problem.contains("`physics`"));
        assert!(problems[0].problem.contains("Physics module"));
        assert_eq!(
            problems[0].fix,
            format!("jd upgrade --apply {}", root.display())
        );
        assert!(problems[0].note.is_some());
    }

    #[test]
    fn a_removed_runtime_feature_in_a_project_not_set_up_is_fixed_by_import() {
        let root = game_with_runtime("removed-feature-unset", "\"physics\"");
        let problems = removed_feature_problems(&root, &root);
        assert_eq!(
            problems[0].fix,
            format!("jd import --apply {}", root.display())
        );
    }

    #[test]
    fn current_runtime_features_are_no_problem() {
        let root = game_with_runtime("current-features", "\"navmesh\", \"pie\"");
        assert!(removed_feature_problems(&root, &root).is_empty());
    }

    #[test]
    fn a_missing_sdk_is_information_for_a_game_and_a_failure_for_an_extension() {
        assert_eq!(grade_sdk(false, false), SdkGrade::Info);
        assert_eq!(grade_sdk(false, true), SdkGrade::Fail);
    }

    #[test]
    fn a_usable_sdk_passes_for_every_project() {
        assert_eq!(grade_sdk(true, false), SdkGrade::Ok);
        assert_eq!(grade_sdk(true, true), SdkGrade::Ok);
    }
}
