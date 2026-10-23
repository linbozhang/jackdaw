//! Builds a project as its own cargo binary. The project is a normal Bevy
//! app, so `cargo build` in the project root is the whole build.

use std::io::{BufRead, BufReader, Read};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Output, Stdio};
use std::time::{Duration, Instant};

use jackdaw_env::rust_env_command;
use jackdaw_schema::{ProjectSchema, SCHEMA_FLAG, parse_from_stdout, write_schema};

use crate::build::{BuildEvent, ProjectBuildError, parse_build_line};
use crate::shim::ShimSpec;

/// A completed binary build.
pub struct ProjectBinaryBuild {
    /// The game executable cargo produced. This is the same artifact a
    /// plain `cargo run` in the project would produce.
    pub binary: PathBuf,
    /// The project's type schema, extracted by running the binary in
    /// schema mode. `None` when extraction could not run; the editor
    /// keeps its previous schema in that case.
    pub schema: Option<ProjectSchema>,
}

/// How much of the machine a build may take. A build the user asked for gets
/// everything; one the editor started on its own competes with the editor's own
/// frame and with the user's terminal.
#[derive(Clone, Copy, Default, PartialEq, Eq, Debug)]
pub enum BuildLoad {
    /// All cores at normal priority.
    #[default]
    Foreground,
    /// Half the cores, de-prioritized.
    Background,
}

/// Cores a [`BuildLoad::Background`] build may use on a machine with
/// `total_threads` of them: half, and never fewer than one. Split out from the
/// command builder because the process-wide core count is not testable.
pub fn background_jobs(total_threads: usize) -> usize {
    (total_threads / 2).max(1)
}

/// The `CARGO_BUILD_JOBS` value for a background build, honouring a cap
/// this process already carries: an ambient one lower than half the cores
/// was chosen deliberately and must not be raised.
fn background_jobs_env() -> usize {
    let cores = std::thread::available_parallelism()
        .map(std::num::NonZero::get)
        .unwrap_or(1);
    let ours = background_jobs(cores);
    match std::env::var("CARGO_BUILD_JOBS")
        .ok()
        .and_then(|value| value.trim().parse::<usize>().ok())
    {
        Some(ambient) if ambient > 0 => ours.min(ambient),
        _ => ours,
    }
}

/// Apply `load` to a cargo invocation. Call after
/// [`detach_from_host_build`], which clears inherited cargo variables.
fn apply_load(command: &mut Command, load: BuildLoad) {
    if load == BuildLoad::Foreground {
        return;
    }
    command.env("CARGO_BUILD_JOBS", background_jobs_env().to_string());
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        // The whole cargo process group, since `setpriority` is inherited
        // by the rustc children cargo spawns.
        unsafe {
            command.pre_exec(|| {
                libc::setpriority(libc::PRIO_PROCESS, 0, 10);
                Ok(())
            });
        }
    }
}

/// Where the editor builds a project's game binary, which is never the
/// project's own `target/`.
pub fn game_target_dir(jackdaw_dir: &Path) -> PathBuf {
    jackdaw_dir.join("target/game")
}

/// The cargo target a run configuration builds: one `[[bin]]` or
/// `[[example]]`, optionally of another workspace `package`, with
/// optional cargo features and profile. `None` is the historical build:
/// the plain `-p <package>` with every binary it contains.
///
/// This is the build-pipeline's bevy-light twin of the serde type in
/// `jackdaw_pie_protocol::manifest`: the CLI must not depend on that
/// crate (it would drag bevy into `jd`), so the editor converts between
/// the two and lockstep tests pin their field names together. It hashes
/// and compares whole so an editor can key its build cache by it.
#[derive(Clone, Debug, Default, PartialEq, Eq, Hash)]
pub struct CargoTarget {
    /// Build this workspace member instead of the resolved package.
    pub package: Option<String>,
    /// The `[[bin]]` target to build.
    pub bin: Option<String>,
    /// The `[[example]]` target to build.
    pub example: Option<String>,
    /// Cargo features enabled for the build.
    pub features: Vec<String>,
    /// The cargo profile to build with.
    pub profile: Option<String>,
}

impl CargoTarget {
    /// The `-p` package a build with this target selects: its own
    /// override, or the spec's package when it names none.
    pub fn package_or<'a>(&'a self, spec_package: &'a str) -> &'a str {
        match self.package.as_deref() {
            Some(package) if !blank(package) => package,
            _ => spec_package,
        }
    }
}

/// Whether a name is blank. The config-side validation rejects blank
/// bin/example names; every passthrough here treats one the same way,
/// as no name at all.
fn blank(name: &str) -> bool {
    name.trim().is_empty()
}

/// The argv a run target adds to a `cargo build` invocation: `--bin` or
/// `--example`, `--features` (comma-joined, as cargo takes them), and
/// `--profile`. `None` adds nothing, so a no-target build's command is
/// byte-for-byte what it always was. The `-p` package override is not
/// here: it replaces the package the base command already selects
/// (see [`CargoTarget::package_or`]) rather than adding a flag.
pub fn cargo_target_args(target: Option<&CargoTarget>) -> Vec<String> {
    let Some(target) = target else {
        return Vec::new();
    };
    let mut args = Vec::new();
    // Both set is rejected by validation before a build starts; if it
    // ever slips through, the bin wins deterministically rather than
    // handing cargo two contradictory flags. Blank names degrade the
    // same way, to the package default.
    if let Some(bin) = target.bin.as_deref().filter(|bin| !blank(bin)) {
        args.extend(["--bin".to_string(), bin.to_string()]);
    } else if let Some(example) = target.example.as_deref().filter(|name| !blank(name)) {
        args.extend(["--example".to_string(), example.to_string()]);
    }
    let features: Vec<&str> = target
        .features
        .iter()
        .map(String::as_str)
        .filter(|feature| !blank(feature))
        .collect();
    if !features.is_empty() {
        args.push("--features".to_string());
        args.push(features.join(","));
    }
    if let Some(profile) = target.profile.as_deref().filter(|name| !blank(name)) {
        args.extend(["--profile".to_string(), profile.to_string()]);
    }
    args
}

/// Build a project's game binary and extract its type schema.
///
/// `jackdaw_dir` is the project's `.jackdaw/`, where the schema is persisted for
/// the editor's watcher and where the build's own artifacts land. It builds
/// against the user's own manifest, lockfile and toolchain, but into
/// [`game_target_dir`] rather than the project's `target/`: the editor builds
/// the plain package while a developer's own build carries the features their
/// game needs, and the two must not overwrite each other's binary. It travels
/// as a flag rather than as `CARGO_TARGET_DIR`, which `detach_from_host_build`
/// strips along with the rest of the editor's own build environment.
pub fn build_project_binary(
    spec: &ShimSpec,
    jackdaw_dir: &Path,
    report: &mut dyn FnMut(BuildEvent),
) -> Result<ProjectBinaryBuild, ProjectBuildError> {
    build_project_binary_with_load(spec, jackdaw_dir, None, BuildLoad::Foreground, report)
}

/// [`build_project_binary`], with a say in how much of the machine the
/// cargo run may take.
///
/// `target` narrows the build to one run target (`--bin`/`--example`,
/// features, profile, and an optional `-p` package override). The
/// executable comes from cargo's own JSON report whatever the target is,
/// so the per-profile and `examples/` directory rules stay cargo's.
pub fn build_project_binary_with_load(
    spec: &ShimSpec,
    jackdaw_dir: &Path,
    target: Option<&CargoTarget>,
    load: BuildLoad,
    report: &mut dyn FnMut(BuildEvent),
) -> Result<ProjectBinaryBuild, ProjectBuildError> {
    let target_dir = game_target_dir(jackdaw_dir);
    // A run target may name another workspace member than the resolved
    // package; the rest of the spec (root, crate name) is per-project.
    let package = target.map_or(spec.package_name.as_str(), |t| {
        t.package_or(spec.package_name.as_str())
    });
    let wanted = WantedArtifact::from(target);
    report(BuildEvent::Log(format!(
        "building {} as a cargo binary in {}, into {}",
        package,
        spec.project_root.display(),
        target_dir.display()
    )));

    // A build on Bevy's main branch hands the game its own Bevy commit; a
    // lockfile at another commit would build a game whose types are not
    // the editor's.
    match crate::bevy_source::pin_project(&spec.project_root) {
        Ok(Some(pinned)) => report(BuildEvent::Log(pinned)),
        Ok(None) => {}
        Err(error) => report(BuildEvent::Log(format!("warning: {error}"))),
    }

    let mut command = rust_env_command("cargo");
    command
        .arg("build")
        .args(["-p", package])
        .args(cargo_target_args(target))
        .arg("--target-dir")
        .arg(&target_dir)
        // Plain `json`, not `json-render-diagnostics`: that variant renders
        // diagnostics to cargo's own stderr and emits no `compiler-message`
        // records, leaving the parser below with nothing to report.
        .arg("--message-format=json")
        .current_dir(&spec.project_root)
        .stdout(Stdio::piped())
        // Captured rather than inherited: cargo's own failures, such as an
        // unresolvable dependency, are never in the JSON stream, and inherited
        // they reach only the terminal the editor was launched from.
        .stderr(Stdio::piped());
    detach_from_host_build(&mut command);
    apply_load(&mut command, load);
    let mut child = command.spawn()?;

    let stdout = child.stdout.take().expect("piped stdout");
    let stderr = child.stderr.take().map(drain_on_a_thread);
    let mut done = 0u32;
    let mut log = String::new();
    let mut executables: Vec<PathBuf> = Vec::new();
    for line in BufReader::new(stdout).lines().map_while(Result::ok) {
        if let Some(path) = executable_for_package(&line, package, wanted) {
            executables.push(path);
        }
        parse_build_line(&line, &mut done, &mut log, report);
    }
    let status = child.wait()?;
    if !status.success() {
        let stderr = stderr
            .and_then(|handle| handle.join().ok())
            .unwrap_or_default();
        let stderr = failure_stderr(&String::from_utf8_lossy(&stderr));
        // Cargo's own account of the failure never goes through the JSON stream.
        // `Display` for `Compile` is one line, so the detail has to reach the
        // panel line by line the way rustc's diagnostics do.
        for line in stderr.lines() {
            report(BuildEvent::Log(line.to_string()));
        }
        return Err(ProjectBuildError::Compile {
            log: compile_failure_log(log, &stderr),
        });
    }

    let binary = executables
        .pop()
        .ok_or_else(|| ProjectBuildError::Compile {
            log: no_binary_message(package),
        })?;

    // Ask the freshly built game for its types: a throwaway run that prints and
    // exits. A failure here is not fatal, and the editor keeps its prior schema.
    let schema = match run_binary_extractor(&binary, &spec.project_root) {
        Ok(schema) => Some(schema),
        Err(err) => {
            tracing::warn!("project schema extraction skipped: {err}");
            report(BuildEvent::Log(format!(
                "project schema extraction skipped: {err}"
            )));
            None
        }
    };

    if let Some(schema) = &schema
        && let Err(err) = write_schema(jackdaw_dir, schema)
    {
        tracing::warn!("failed to persist project schema: {err}");
    }

    Ok(ProjectBinaryBuild { binary, schema })
}

/// Cargo's stderr without its per-crate progress notes, which say nothing
/// about why a build failed and would bury the lines that do.
fn failure_stderr(stderr: &str) -> String {
    const PROGRESS: [&str; 5] = [
        "Compiling ",
        "Checking ",
        "Downloading ",
        "Downloaded ",
        "Fresh ",
    ];
    stderr
        .lines()
        .filter(|line| {
            let line = line.trim_start();
            !PROGRESS.iter().any(|verb| line.starts_with(verb))
        })
        .collect::<Vec<_>>()
        .join("\n")
}

/// What a failed build reports: rustc's diagnostics, then cargo's own stderr.
///
/// rustc's arrive as `compiler-message` records on stdout; cargo's are on stderr
/// and are the only account of a failure before any code was compiled. Either
/// can be empty, so both are carried.
fn compile_failure_log(diagnostics: String, stderr: &str) -> String {
    let mut log = diagnostics;
    let stderr = stderr.trim();
    if !stderr.is_empty() {
        if !log.trim().is_empty() {
            log.push('\n');
        }
        log.push_str(stderr);
        log.push('\n');
    }
    if log.trim().is_empty() {
        log.push_str("project failed to compile, and cargo reported no diagnostics");
    }
    log
}

/// How long the extractor may run before it is killed. This path compiles
/// nothing, so only a stuck process reaches the deadline.
const EXTRACTOR_TIMEOUT: Duration = Duration::from_secs(120);

/// Overrides [`EXTRACTOR_TIMEOUT`], in whole seconds.
const EXTRACTOR_TIMEOUT_VAR: &str = "JACKDAW_SCHEMA_EXTRACT_TIMEOUT_SECS";

/// The deadline to run the extractor under, from `value` (the raw environment
/// override). Anything unparseable or zero falls back to the default rather than
/// disabling the deadline.
fn extractor_timeout_from(value: Option<&str>) -> Duration {
    value
        .and_then(|raw| raw.trim().parse::<u64>().ok())
        .filter(|seconds| *seconds > 0)
        .map_or(EXTRACTOR_TIMEOUT, Duration::from_secs)
}

fn extractor_timeout() -> Duration {
    extractor_timeout_from(std::env::var(EXTRACTOR_TIMEOUT_VAR).ok().as_deref())
}

/// Ask a built project binary for its schema.
///
/// The binary is the same artifact Play runs; the flag makes it report and exit
/// before it opens a window. `cwd` is the project root so the game resolves
/// assets as it would when played.
///
/// The run is under a deadline, because the extractor answers from inside the
/// game's own `App` build and a project whose plugins block would otherwise hang
/// the editor's build. A kill becomes an ordinary extractor failure.
fn run_binary_extractor(binary: &Path, cwd: &Path) -> Result<ProjectSchema, String> {
    if !binary.is_file() {
        return Err(format!("game binary not found at {}", binary.display()));
    }
    let mut command = Command::new(binary);
    command
        .arg(SCHEMA_FLAG)
        .current_dir(cwd)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    prepare_game_command(&mut command, binary);
    let child = command
        .spawn()
        .map_err(|e| format!("spawn extractor: {e}"))?;
    let output = wait_with_deadline(child, extractor_timeout())?;
    if !output.status.success() {
        return Err(format!(
            "extractor failed: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    parse_from_stdout(&output.stdout)
}

/// Collect a child's output, killing it if it outlives `timeout`.
///
/// `Child::wait_with_output` has no deadline and `Child::wait` alone
/// would deadlock against a full pipe, so the pipes are drained on their
/// own threads while the main one polls for exit.
fn wait_with_deadline(mut child: Child, timeout: Duration) -> Result<Output, String> {
    let stdout = child.stdout.take().map(drain_on_a_thread);
    let stderr = child.stderr.take().map(drain_on_a_thread);
    let deadline = Instant::now() + timeout;

    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) => {}
            Err(e) => return Err(format!("wait for extractor: {e}")),
        }
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            return Err(format!(
                "extractor did not finish within {}s (set {EXTRACTOR_TIMEOUT_VAR} to allow longer)",
                timeout.as_secs()
            ));
        }
        std::thread::sleep(Duration::from_millis(25));
    };

    let collect = |handle: Option<std::thread::JoinHandle<Vec<u8>>>| {
        handle.and_then(|h| h.join().ok()).unwrap_or_default()
    };
    Ok(Output {
        status,
        stdout: collect(stdout),
        stderr: collect(stderr),
    })
}

fn drain_on_a_thread(mut pipe: impl Read + Send + 'static) -> std::thread::JoinHandle<Vec<u8>> {
    std::thread::spawn(move || {
        let mut buffer = Vec::new();
        let _ = pipe.read_to_end(&mut buffer);
        buffer
    })
}

/// Variables that describe *this* process's build rather than the project's,
/// removed before invoking cargo on the project.
const HOST_BUILD_VARS: &[&str] = &[
    // The one that matters most: the editor runs under a pinned toolchain, and
    // an inherited `RUSTUP_TOOLCHAIN` overrides the project's own
    // `rust-toolchain.toml`.
    "RUSTUP_TOOLCHAIN",
    "RUSTC",
    "RUSTDOC",
    "RUSTC_WRAPPER",
    "RUSTC_WORKSPACE_WRAPPER",
    "RUSTFLAGS",
    "CARGO_ENCODED_RUSTFLAGS",
    "CARGO",
    "CARGO_TARGET_DIR",
    "CARGO_BUILD_TARGET",
    "CARGO_BUILD_TARGET_DIR",
    "CARGO_MANIFEST_DIR",
    "CARGO_MANIFEST_PATH",
    "CARGO_CRATE_NAME",
    "CARGO_BIN_NAME",
    "CARGO_PRIMARY_PACKAGE",
    "CARGO_TARGET_TMPDIR",
    // Set by `cargo run` for the process it launches; inheriting them would put
    // the editor's dependency libraries on the project's search path.
    "LD_LIBRARY_PATH",
    "DYLD_LIBRARY_PATH",
    "DYLD_FALLBACK_LIBRARY_PATH",
];

/// Prefixes of the per-crate variables cargo exports to a build.
const HOST_BUILD_PREFIXES: &[&str] = &["CARGO_PKG_", "CARGO_CFG_", "CARGO_FEATURE_"];

/// Detach `command` from the build environment the editor is running under.
///
/// The editor is usually itself launched by cargo, which fills the environment
/// with variables describing the editor's build. `RUSTUP_TOOLCHAIN` outranks a
/// project's `rust-toolchain.toml`, so inheriting it compiles the project with
/// the editor's compiler, which shares no fingerprints with the user's own
/// builds.
///
/// `CARGO_HOME`, `RUSTUP_HOME` and `PATH` are deliberately kept: they locate the
/// toolchain and the shared package cache.
pub fn detach_from_host_build(command: &mut Command) {
    for variable in HOST_BUILD_VARS {
        command.env_remove(variable);
    }
    // The prefixed ones are per-crate and unbounded, so they have to be
    // discovered from this process's environment rather than listed.
    for (key, _) in std::env::vars_os() {
        if is_host_build_var(&key.to_string_lossy()) {
            command.env_remove(&key);
        }
    }
}

/// Whether a variable describes this process's build rather than the
/// project's, and so must not be inherited by a build or a game.
fn is_host_build_var(name: &str) -> bool {
    HOST_BUILD_VARS.contains(&name)
        || HOST_BUILD_PREFIXES
            .iter()
            .any(|prefix| name.starts_with(prefix))
}

/// Prepare a command that runs a built game: Play, and the schema extractor.
///
/// Keeps it from opening a console window of its own, detaches it from the
/// editor's build environment, then puts the build's `deps/`
/// on the dynamic library search path. One function rather than two calls at
/// each site, because the detach clears the library-path variables.
pub fn prepare_game_command(command: &mut Command, binary: &Path) {
    jackdaw_env::without_console_window(command);
    detach_from_host_build(command);
    apply_dynamic_library_path(command, binary);
}

/// The environment variable holding the dynamic library search path.
fn dynamic_library_path_var() -> &'static str {
    if cfg!(windows) {
        "PATH"
    } else if cfg!(target_os = "macos") {
        "DYLD_FALLBACK_LIBRARY_PATH"
    } else {
        "LD_LIBRARY_PATH"
    }
}

/// Put the build's `deps/` directory on the dynamic library search path for
/// `command`.
///
/// `cargo run` does this before launching a binary, and a game built with
/// `bevy/dynamic_linking` does not start without it: the bevy dll it needs sits
/// in `deps/`, not beside the executable.
fn apply_dynamic_library_path(command: &mut Command, binary: &Path) {
    let Some(deps) = binary.parent().map(|dir| dir.join("deps")) else {
        return;
    };
    if !deps.is_dir() {
        return;
    }
    let variable = dynamic_library_path_var();
    let mut paths = vec![deps];
    if let Some(existing) = std::env::var_os(variable) {
        paths.extend(std::env::split_paths(&existing));
    }
    if let Ok(joined) = std::env::join_paths(paths) {
        command.env(variable, joined);
    }
}

/// The cargo target an artifact must be for the build to adopt it as its
/// executable.
#[derive(Clone, Copy)]
enum WantedArtifact<'a> {
    /// Any binary artifact of the package: the no-target build, which
    /// adopts the last one cargo reported, as it always has.
    AnyBinary,
    /// Exactly this `--bin`/`--example` target of the package, matched
    /// against the record's `target.name` and `target.kind`, so a
    /// targeted build cannot adopt a sibling artifact of a multi-binary
    /// package.
    CargoTarget { name: &'a str, example: bool },
}

impl WantedArtifact<'_> {
    /// What `target` asks the build to produce. A target naming neither
    /// bin nor example, or both (validation rejects both upstream), falls
    /// back to the package default.
    fn from<'a>(target: Option<&'a CargoTarget>) -> WantedArtifact<'a> {
        let Some(target) = target else {
            return WantedArtifact::AnyBinary;
        };
        // The same precedence as `cargo_target_args`: a blank name or a
        // both-set target degrades to the package default rather than
        // handing cargo contradictory flags.
        if let Some(name) = target.bin.as_deref().filter(|name| !blank(name)) {
            WantedArtifact::CargoTarget {
                name,
                example: false,
            }
        } else if let Some(name) = target.example.as_deref().filter(|name| !blank(name)) {
            WantedArtifact::CargoTarget {
                name,
                example: true,
            }
        } else {
            WantedArtifact::AnyBinary
        }
    }

    /// Whether the JSON record's `target` table describes this cargo
    /// target. Cargo spells the kind `"bin"` or `"example"`.
    fn matches(&self, record: &serde_json::Value) -> bool {
        let Self::CargoTarget { name, example } = *self else {
            return true;
        };
        let kind = if example { "example" } else { "bin" };
        record.get("name").and_then(serde_json::Value::as_str) == Some(name)
            && record
                .get("kind")
                .and_then(serde_json::Value::as_array)
                .is_some_and(|kinds| kinds.iter().any(|k| k.as_str() == Some(kind)))
    }
}

/// The executable path from one `compiler-artifact` line, when that artifact is
/// a binary belonging to `package_name` and is the cargo target `wanted`.
///
/// cargo emits `executable` as null for every non-binary unit, and the graph
/// contains binaries from dependencies too, so both filters are needed.
fn executable_for_package(
    line: &str,
    package_name: &str,
    wanted: WantedArtifact<'_>,
) -> Option<PathBuf> {
    let value = serde_json::from_str::<serde_json::Value>(line).ok()?;
    if value.get("reason").and_then(serde_json::Value::as_str)? != "compiler-artifact" {
        return None;
    }
    let executable = value.get("executable")?.as_str()?;
    let package_id = value
        .get("package_id")
        .and_then(serde_json::Value::as_str)?;
    if !package_id_names(package_id, package_name) {
        return None;
    }
    // A record without a `target` table (older cargo) still serves the
    // package-default build, which never narrowed by target anyway.
    if !value
        .get("target")
        .is_none_or(|record| wanted.matches(record))
    {
        return None;
    }
    Some(PathBuf::from(executable))
}

/// Whether a cargo package id refers to `package_name`. Ids spell the
/// name either in the fragment (`...#my-game@0.1.0`) or, for path
/// packages that carry only a version there, as the last path segment
/// (`path+file:///home/u/my-game#0.1.0`).
fn package_id_names(package_id: &str, package_name: &str) -> bool {
    let normalize = |s: &str| s.replace('-', "_");
    let Some((base, fragment)) = package_id.rsplit_once('#') else {
        return false;
    };
    let name = match fragment.rsplit_once('@') {
        Some((name, _)) => name.to_string(),
        None => base.rsplit(['/', '\\']).next().unwrap_or("").to_string(),
    };
    normalize(&name) == normalize(package_name)
}

/// The error text when the build succeeded but produced no executable.
/// Almost always means the crate is a library with no `src/main.rs`.
fn no_binary_message(package: &str) -> String {
    format!(
        "`{}` built, but produced no executable.\n\
         note: jackdaw runs your game as an ordinary cargo binary, so the package needs a \
         binary target.\n\
         note: add a `src/main.rs` that builds a bevy `App` and adds your game plugin, or run \
         `jd migrate` to have one written for you.",
        package,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_editor_builds_the_game_away_from_the_one_a_developer_builds() {
        let project = Path::new("/game");

        let editor = game_target_dir(&project.join(".jackdaw"));

        assert!(
            !editor.starts_with(project.join("target")),
            "an editor build must not land where a developer's own build does, got {}",
            editor.display()
        );
    }

    /// A background build leaves the user half the machine, and never
    /// asks for zero jobs on a single-core box.
    #[test]
    fn a_background_build_takes_half_the_cores() {
        assert_eq!(background_jobs(1), 1);
        assert_eq!(background_jobs(2), 1);
        assert_eq!(background_jobs(12), 6);
        assert_eq!(background_jobs(64), 32);
    }

    /// The editor pins its own toolchain; leaking that into the
    /// project's build compiles it with the wrong compiler, which shares
    /// no fingerprints with the user's own builds.
    #[test]
    fn the_editors_toolchain_and_crate_vars_do_not_reach_the_project() {
        assert!(is_host_build_var("RUSTUP_TOOLCHAIN"));
        assert!(is_host_build_var("CARGO_MANIFEST_DIR"));
        assert!(is_host_build_var("CARGO_TARGET_DIR"));
        assert!(is_host_build_var("CARGO_PKG_VERSION"));
        assert!(is_host_build_var("CARGO_FEATURE_DEFAULT"));
        assert!(is_host_build_var("LD_LIBRARY_PATH"));
    }

    /// Locating the toolchain and the shared package cache is exactly
    /// what should carry over, so a project build reuses what is
    /// already downloaded.
    #[test]
    fn the_shared_toolchain_and_cache_locations_are_kept() {
        assert!(!is_host_build_var("PATH"));
        assert!(!is_host_build_var("CARGO_HOME"));
        assert!(!is_host_build_var("RUSTUP_HOME"));
    }

    #[test]
    fn registry_and_path_package_ids_are_recognised() {
        assert!(package_id_names(
            "registry+https://github.com/rust-lang/crates.io-index#my-game@0.1.0",
            "my-game"
        ));
        assert!(package_id_names(
            "path+file:///home/u/my-game#0.1.0",
            "my-game"
        ));
        assert!(package_id_names(
            "path+file:///home/u/my-game#0.1.0",
            "my_game"
        ));
        assert!(!package_id_names(
            "path+file:///home/u/other#0.1.0",
            "my-game"
        ));
    }

    #[test]
    fn a_broken_timeout_override_cannot_reintroduce_a_hang() {
        assert_eq!(extractor_timeout_from(None), EXTRACTOR_TIMEOUT);
        assert_eq!(
            extractor_timeout_from(Some("300")),
            Duration::from_secs(300)
        );
        assert_eq!(
            extractor_timeout_from(Some(" 45 ")),
            Duration::from_secs(45)
        );
        assert_eq!(extractor_timeout_from(Some("0")), EXTRACTOR_TIMEOUT);
        assert_eq!(extractor_timeout_from(Some("forever")), EXTRACTOR_TIMEOUT);
        assert_eq!(extractor_timeout_from(Some("-1")), EXTRACTOR_TIMEOUT);
    }

    /// A game that never exits must not hold the editor's build open.
    #[cfg(unix)]
    #[test]
    fn an_extractor_that_never_exits_is_killed_at_the_deadline() {
        let child = Command::new("sleep")
            .arg("120")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .expect("spawn sleep");

        let started = Instant::now();
        let result = wait_with_deadline(child, Duration::from_millis(200));

        let message = result.expect_err("a hung extractor must not succeed");
        assert!(message.contains("did not finish"), "got {message}");
        assert!(
            started.elapsed() < Duration::from_secs(10),
            "the deadline must fire, not the process"
        );
    }

    #[cfg(unix)]
    #[test]
    fn output_still_reaches_the_caller_when_the_extractor_exits_in_time() {
        let child = Command::new("echo")
            .arg("hello")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .expect("spawn echo");

        let output = wait_with_deadline(child, Duration::from_secs(30)).expect("echo finishes");
        assert!(output.status.success());
        assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "hello");
    }

    /// A project that does not compile fails with the compiler's own errors
    /// in it. The editor shows this text and nothing else, so a build that
    /// drops them leaves only "project failed to compile".
    #[test]
    fn a_project_that_does_not_compile_reports_the_compilers_own_errors() {
        let root = std::env::temp_dir().join(format!("jackdaw-broken-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(root.join("src")).expect("fixture dirs");
        std::fs::write(
            root.join("Cargo.toml"),
            "[package]\nname = \"broken-game\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n\
             [workspace]\n\n[dependencies]\n",
        )
        .expect("fixture manifest");
        // No dependencies, so this compiles (and fails) in about a second.
        std::fs::write(
            root.join("src/main.rs"),
            "fn main() { let _: u32 = \"not a number\"; }\n",
        )
        .expect("fixture source");

        let spec = ShimSpec {
            package_name: "broken-game".to_string(),
            crate_name: "broken_game".to_string(),
            project_root: root.clone(),
            extension_type: None,
        };
        let jackdaw_dir = root.join(".jackdaw");
        std::fs::create_dir_all(&jackdaw_dir).expect("jackdaw dir");

        let mut reported: Vec<String> = Vec::new();
        let result = build_project_binary(&spec, &jackdaw_dir, &mut |event| {
            if let BuildEvent::Log(line) = event {
                reported.push(line);
            }
        });
        let Err(ProjectBuildError::Compile { log }) = result else {
            panic!("a project that does not compile must fail as a compile error");
        };
        assert!(
            log.contains("E0308") && log.contains("mismatched types"),
            "the compiler's own diagnostic has to survive the trip:\n{log}"
        );
        assert!(
            !log.contains("no diagnostics"),
            "and it must not be reported as having said nothing:\n{log}"
        );
        // The panel shows what the reporter is handed, and `Display` for a
        // compile failure is one line, so cargo's own account has to arrive
        // here rather than only inside the error.
        let reported = reported.join("\n");
        assert!(
            reported.contains("E0308"),
            "the diagnostic reaches the build panel:\n{reported}"
        );
        assert!(
            reported.contains("could not compile"),
            "and so does cargo's own account of the failure:\n{reported}"
        );

        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_failure_leaves_out_cargos_progress_notes() {
        let stderr = "   Compiling bevy v0.19.1\n   Compiling my-game v0.1.0 (/p)\n\
                      error: could not compile `my-game` (lib) due to 1 previous error\n";

        assert_eq!(
            failure_stderr(stderr),
            "error: could not compile `my-game` (lib) due to 1 previous error"
        );
    }

    #[test]
    fn a_build_that_says_nothing_at_all_still_says_so() {
        assert_eq!(
            compile_failure_log(String::new(), "   \n"),
            "project failed to compile, and cargo reported no diagnostics"
        );
    }

    /// A failure before compilation starts is cargo's alone: nothing reaches
    /// the JSON stream, so the stderr is the whole account of it.
    #[test]
    fn cargos_own_failure_is_carried_when_no_diagnostic_is() {
        let log = compile_failure_log(
            String::new(),
            "error: failed to select a version for `serde`\n",
        );
        assert!(log.contains("failed to select a version"), "got {log}");
        assert!(!log.contains("no diagnostics"), "got {log}");
    }

    #[test]
    fn both_accounts_are_kept_when_both_have_something_to_say() {
        let log = compile_failure_log(
            "error[E0308]: mismatched types\n".to_string(),
            "error: could not compile `broken-game` due to 1 previous error",
        );
        assert!(log.contains("E0308"), "got {log}");
        assert!(log.contains("could not compile"), "got {log}");
    }

    #[test]
    fn only_binary_artifacts_of_the_game_package_are_taken() {
        let bin = r#"{"reason":"compiler-artifact","package_id":"path+file:///w/my-game#0.1.0","executable":"/w/target/debug/my-game"}"#;
        assert_eq!(
            executable_for_package(bin, "my-game", WantedArtifact::AnyBinary),
            Some(PathBuf::from("/w/target/debug/my-game"))
        );

        let lib = r#"{"reason":"compiler-artifact","package_id":"path+file:///w/my-game#0.1.0","executable":null}"#;
        assert_eq!(
            executable_for_package(lib, "my-game", WantedArtifact::AnyBinary),
            None
        );

        let other = r#"{"reason":"compiler-artifact","package_id":"path+file:///w/tool#0.1.0","executable":"/w/target/debug/tool"}"#;
        assert_eq!(
            executable_for_package(other, "my-game", WantedArtifact::AnyBinary),
            None
        );
    }

    /// A run target naming one example of a multi-target package must
    /// adopt that example's artifact and only it: without the name/kind
    /// filter, a sibling bin reported later in the stream would win.
    #[test]
    fn a_targeted_build_adopts_only_its_own_artifact() {
        let example = r#"{"reason":"compiler-artifact","package_id":"path+file:///w/my-game#0.1.0",
            "target":{"name":"split_screen","kind":["example"]},
            "executable":"/w/target/game/debug/examples/split_screen"}"#;
        assert_eq!(
            executable_for_package(
                example,
                "my-game",
                WantedArtifact::CargoTarget {
                    name: "split_screen",
                    example: true
                }
            ),
            Some(PathBuf::from("/w/target/game/debug/examples/split_screen"))
        );

        let sibling_bin = r#"{"reason":"compiler-artifact","package_id":"path+file:///w/my-game#0.1.0",
            "target":{"name":"my-game","kind":["bin"]},
            "executable":"/w/target/game/debug/my-game"}"#;
        assert_eq!(
            executable_for_package(
                sibling_bin,
                "my-game",
                WantedArtifact::CargoTarget {
                    name: "split_screen",
                    example: true
                }
            ),
            None
        );

        let wrong_kind = r#"{"reason":"compiler-artifact","package_id":"path+file:///w/my-game#0.1.0",
            "target":{"name":"split_screen","kind":["bin"]},
            "executable":"/w/target/game/debug/split_screen"}"#;
        assert_eq!(
            executable_for_package(
                wrong_kind,
                "my-game",
                WantedArtifact::CargoTarget {
                    name: "split_screen",
                    example: true
                }
            ),
            None
        );

        // The package-default build keeps adopting whatever the package
        // reports, target table or not.
        assert_eq!(
            executable_for_package(sibling_bin, "my-game", WantedArtifact::AnyBinary),
            Some(PathBuf::from("/w/target/game/debug/my-game"))
        );
        assert_eq!(
            executable_for_package(example, "my-game", WantedArtifact::AnyBinary),
            Some(PathBuf::from("/w/target/game/debug/examples/split_screen"))
        );
    }

    #[test]
    fn a_wanted_bin_matches_only_its_own_artifact() {
        let server = r#"{"reason":"compiler-artifact","package_id":"path+file:///w/my-game#0.1.0",
            "target":{"name":"server","kind":["bin"]},
            "executable":"/w/target/game/debug/server"}"#;
        assert_eq!(
            executable_for_package(
                server,
                "my-game",
                WantedArtifact::CargoTarget {
                    name: "server",
                    example: false
                }
            ),
            Some(PathBuf::from("/w/target/game/debug/server"))
        );
        assert_eq!(
            executable_for_package(
                server,
                "my-game",
                WantedArtifact::CargoTarget {
                    name: "client",
                    example: false
                }
            ),
            None
        );
    }

    /// A no-target run adds no argv, so the cargo command a project has
    /// always built with is byte-for-byte unchanged.
    #[test]
    fn no_target_adds_nothing_to_the_cargo_command() {
        assert_eq!(cargo_target_args(None), Vec::<String>::new());
        assert_eq!(
            cargo_target_args(Some(&CargoTarget::default())),
            Vec::<String>::new()
        );
    }

    #[test]
    fn a_bin_target_passes_through_bin_features_and_profile() {
        let target = CargoTarget {
            package: None,
            bin: Some("server".to_string()),
            example: None,
            features: vec!["net".to_string(), "dedicated".to_string()],
            profile: Some("release".to_string()),
        };
        assert_eq!(
            cargo_target_args(Some(&target)),
            [
                "--bin",
                "server",
                "--features",
                "net,dedicated",
                "--profile",
                "release"
            ]
        );
    }

    #[test]
    fn an_example_target_passes_example_through() {
        let target = CargoTarget {
            example: Some("split_screen".to_string()),
            ..CargoTarget::default()
        };
        assert_eq!(
            cargo_target_args(Some(&target)),
            ["--example", "split_screen"]
        );
    }

    /// Both bin and example is a validation error upstream; the command
    /// builder must never hand cargo both flags, and an empty name must
    /// not produce an empty flag value.
    #[test]
    fn contradictory_or_empty_targets_add_no_flags() {
        let both = CargoTarget {
            bin: Some("server".to_string()),
            example: Some("split_screen".to_string()),
            ..CargoTarget::default()
        };
        assert_eq!(cargo_target_args(Some(&both)), ["--bin", "server"]);

        let empty = CargoTarget {
            bin: Some("   ".to_string()),
            features: vec![String::new()],
            profile: Some(String::new()),
            ..CargoTarget::default()
        };
        assert_eq!(cargo_target_args(Some(&empty)), Vec::<String>::new());
    }

    #[test]
    fn a_package_override_replaces_the_specs_package() {
        let target = CargoTarget {
            package: Some("game-client".to_string()),
            ..CargoTarget::default()
        };
        assert_eq!(target.package_or("my-game"), "game-client");
        assert_eq!(CargoTarget::default().package_or("my-game"), "my-game");
        // An empty override selects nothing in cargo; fall back instead.
        let empty = CargoTarget {
            package: Some(String::new()),
            ..CargoTarget::default()
        };
        assert_eq!(empty.package_or("my-game"), "my-game");
    }

    /// The editor keys its build cache by `CargoTarget`; equal targets
    /// must hit one entry and different ones must not.
    #[test]
    fn cargo_targets_key_a_build_cache_by_value() {
        let mut cache = std::collections::HashMap::new();
        let bin = CargoTarget {
            bin: Some("server".to_string()),
            ..CargoTarget::default()
        };
        let example = CargoTarget {
            example: Some("server".to_string()),
            ..CargoTarget::default()
        };
        cache.insert(bin.clone(), 1);
        // Same target hits; a same-named example, or a feature change,
        // is a different build and must not.
        assert_eq!(cache.get(&bin), Some(&1));
        assert_eq!(cache.get(&example), None);
        let featured = CargoTarget {
            features: vec!["net".to_string()],
            ..bin.clone()
        };
        assert_eq!(cache.get(&featured), None);
    }
}
