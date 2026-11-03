//! Structured rows out of a failed build's rendered log (W2).
//!
//! A failing cargo writes rustc's rendered diagnostics into the build log,
//! and every rendered diagnostic carries a `--> path:line:col` line — the
//! position is already on screen, but as text nobody can act on: the whole
//! log rides one scrolling text node and finding the first error means
//! reading. This module is the parse half ([`parse_diagnostics`], decision
//! 2(a): a regex over the rendered text, the pipeline untouched) and the
//! landing ([`BuildDiagnostics`], the companion resource the Build panel's
//! error rows render from, with the first error pinned and an "N errors"
//! summary), plus the last meter of the code-position jump (decision 3(c)):
//! [`open_diagnostic`] hands the position to an external editor whose CLI
//! protocol supports line-accurate opens, falling back to revealing the
//! file's folder when no known editor answers.
//!
//! The parse is deliberately forgiving: rustc makes no format promise across
//! versions, so a rendered line that does not match passes quietly, a log
//! with no arrows at all parses to an empty row list, and the panel renders
//! exactly what it always did — the whole log — when nothing structured
//! came out.

use std::path::{Path, PathBuf};

use bevy::prelude::*;
use jackdaw_feathers::tokens;

use crate::build_status::BuildStatus;

/// How serious the diagnostic a row came from was.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Severity {
    Error,
    Warning,
}

/// One actionable position the failed build's log names: the `-->` line of a
/// rustc diagnostic, with the severity of the diagnostic it belongs to.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DiagnosticRow {
    pub file: String,
    pub line: u32,
    pub column: u32,
    pub severity: Severity,
}

impl DiagnosticRow {
    /// The position as the log spells it, for the row's face.
    pub fn position(&self) -> String {
        format!("{}:{}:{}", self.file, self.line, self.column)
    }
}

/// The structured face of the last failed build, kept beside
/// [`BuildStatus`] so the panel renders rows without re-reading the log
/// text every frame. Empty whenever the log holds no arrows — the parse
/// never invents a row it cannot pin.
#[derive(Resource, Default)]
pub struct BuildDiagnostics {
    pub rows: Vec<DiagnosticRow>,
    /// How many `error`-level lines the log holds, arrows or not: a
    /// linker failure carries no `-->` line and still deserves an honest
    /// count.
    pub errors: usize,
}

impl BuildDiagnostics {
    /// The error rows, first error first — the order the log spelled them.
    pub fn error_rows(&self) -> impl Iterator<Item = &DiagnosticRow> {
        self.rows
            .iter()
            .filter(|row| row.severity == Severity::Error)
    }

    /// The first error row, the one "first error" means.
    pub fn first_error(&self) -> Option<&DiagnosticRow> {
        self.error_rows().next()
    }
}

/// Pull every `--> path:line:col` row out of rendered rustc output, tagging
/// each with the severity of the diagnostic block it sits in (`error[E0308]:
/// ...` / `warning: ...` lines set it; notes and help keep the block's).
/// Lines that match nothing pass quietly.
pub fn parse_diagnostics(log: &str) -> Vec<DiagnosticRow> {
    let mut rows = Vec::new();
    let mut severity = Severity::Error;
    for line in log.lines() {
        let trimmed = line.trim_start();
        if trimmed.starts_with("error") && is_level_line(trimmed, "error") {
            severity = Severity::Error;
            continue;
        }
        if trimmed.starts_with("warning") && is_level_line(trimmed, "warning") {
            severity = Severity::Warning;
            continue;
        }
        let Some(rest) = trimmed.strip_prefix("-->") else {
            continue;
        };
        let Some(row) = parse_arrow(rest.trim()) else {
            continue;
        };
        rows.push(DiagnosticRow { severity, ..row });
    }
    rows
}

/// Count the `error`-level lines a log carries, whatever else is in it.
pub fn count_errors(log: &str) -> usize {
    log.lines()
        .filter(|line| {
            let trimmed = line.trim_start();
            trimmed.starts_with("error") && is_level_line(trimmed, "error")
        })
        .count()
}

/// Whether a trimmed line is a diagnostic level line of `level`: `error`,
/// `error[E0308]:` and `error: ...` are, `errors` in prose or an
/// `error_code` identifier is not.
fn is_level_line(trimmed: &str, level: &str) -> bool {
    let rest = trimmed
        .strip_prefix(level)
        .expect("the caller matched the prefix");
    rest.starts_with(':') || rest.starts_with('[') || rest.trim().is_empty()
}

/// Parse the tail of a `-->` line: everything before the last two
/// colon-separated numbers is the path, so a path that itself carries
/// colons still splits clean.
fn parse_arrow(tail: &str) -> Option<DiagnosticRow> {
    let mut parts = tail.rsplitn(3, ':');
    let column = parts.next()?.trim().parse::<u32>().ok()?;
    let line = parts.next()?.trim().parse::<u32>().ok()?;
    let file = parts.next()?.trim().to_string();
    if file.is_empty() || file.contains(' ') {
        return None;
    }
    Some(DiagnosticRow {
        file,
        line,
        column,
        severity: Severity::Error,
    })
}

/// Re-read the failed log into the structured face whenever the latch
/// changes. A cleared latch (the next build starting) re-parses to empty.
pub(crate) fn sync_build_diagnostics(
    status: Res<BuildStatus>,
    mut diagnostics: ResMut<BuildDiagnostics>,
) {
    if !status.is_changed() {
        return;
    }
    diagnostics.rows = status
        .failed_log
        .as_deref()
        .map(parse_diagnostics)
        .unwrap_or_default();
    diagnostics.errors = status
        .failed_log
        .as_deref()
        .map(count_errors)
        .unwrap_or_default();
}

/// Where a row's spelled path lands on disk. cargo ran in the game package,
/// so rendered paths are relative to it; the project root and the project's
/// package directory both get a try before the position is called unfindable.
fn resolve_source_file(world: &World, spelled: &str) -> Option<PathBuf> {
    let path = Path::new(spelled);
    if path.is_absolute() {
        return path.is_file().then(|| path.to_path_buf());
    }
    let root = world
        .get_resource::<crate::project::ProjectRoot>()
        .map(|project| project.root.clone())?;
    let mut candidates = vec![root.join(spelled)];
    // The nested-package shape (a game crate directory beside the project
    // files): any first-level directory holding a Cargo.toml gets a try for
    // a package-relative spelling. One or two stats, no cargo invocation.
    if let Ok(entries) = std::fs::read_dir(&root) {
        for entry in entries.flatten() {
            let dir = entry.path();
            if dir.is_dir() && dir.join("Cargo.toml").is_file() {
                candidates.push(dir.join(spelled));
            }
        }
    }
    candidates.into_iter().find(|candidate| candidate.is_file())
}

/// How an editor CLI takes a `file:line:col` position.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EditorProtocol {
    /// `--goto file:line:col`, the VS Code family flag.
    GotoFlag,
    /// `file:line:col` as a plain positional, the Zed form.
    Positional,
}

/// The probe table: every editor CLI this build knows to try, first match
/// on `PATH` wins. New editors join as one row (name + how they take a
/// position); nothing here is editor-version specific.
const EDITOR_PROBES: &[(&str, EditorProtocol)] = &[
    ("code", EditorProtocol::GotoFlag),
    ("code-insiders", EditorProtocol::GotoFlag),
    ("vscodium", EditorProtocol::GotoFlag),
    ("cursor", EditorProtocol::GotoFlag),
    ("windsurf", EditorProtocol::GotoFlag),
    ("zed", EditorProtocol::Positional),
];

/// The first probe table entry whose executable answers on `path_var`
/// (a `PATH`-shaped list).
fn find_external_editor_in(path_var: &str) -> Option<(&'static str, EditorProtocol)> {
    for (name, protocol) in EDITOR_PROBES {
        if executable_on_path(path_var, name) {
            return Some((name, *protocol));
        }
    }
    None
}

/// The probe at click time over the process's own `PATH`.
fn find_external_editor() -> Option<(&'static str, EditorProtocol)> {
    let path = std::env::var_os("PATH")?;
    find_external_editor_in(&path.to_string_lossy())
}

/// Whether an executable named `name` sits on a `PATH`-shaped list.
fn executable_on_path(path_var: &str, name: &str) -> bool {
    std::env::split_paths(&path_var).any(|dir| {
        let candidate = dir.join(name);
        candidate.is_file() && is_executable(&candidate)
    })
}

#[cfg(unix)]
fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt as _;
    std::fs::metadata(path)
        .map(|meta| meta.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn is_executable(path: &Path) -> bool {
    path.is_file()
}

/// The arguments that carry `file:line:column` to an editor of `protocol`.
fn editor_args(protocol: EditorProtocol, file: &Path, line: u32, column: u32) -> Vec<String> {
    let position = format!("{}:{line}:{column}", file.display());
    match protocol {
        EditorProtocol::GotoFlag => vec!["--goto".to_string(), position],
        EditorProtocol::Positional => vec![position],
    }
}

/// One error row, taken at its word: resolve the spelled path, hand the
/// position to the best external editor on `PATH` (decision 3(c)), and
/// reveal the file's folder when no editor answers (decision 3(a)). The
/// status bar says what became of the click either way.
pub fn open_diagnostic(world: &mut World, row: &DiagnosticRow) {
    let Some(file) = resolve_source_file(world, &row.file) else {
        crate::status_bar::notify_warn(
            world,
            format!("{} is not in this project; nothing to open", row.position()),
        );
        return;
    };
    if let Some((editor, protocol)) = find_external_editor() {
        let args = editor_args(protocol, &file, row.line, row.column);
        match std::process::Command::new(editor).args(&args).spawn() {
            Ok(_) => {
                crate::status_bar::notify_info(
                    world,
                    format!("opened {editor} at {}", row.position()),
                );
                return;
            }
            Err(err) => {
                warn!("build diagnostic: {editor} would not start: {err}");
            }
        }
    }
    // No editor on `PATH`, or the one found refused: reveal the folder, the
    // fallback every machine can answer.
    let folder = file
        .parent()
        .map(Path::to_path_buf)
        .unwrap_or_else(|| file.clone());
    if let Err(err) = crate::project_window::open_with_desktop(&folder) {
        crate::status_bar::notify_warn(
            world,
            format!("{} cannot be opened: {err}", folder.display()),
        );
        return;
    }
    crate::status_bar::notify_info(
        world,
        format!(
            "no external editor on PATH; revealed {} ({}:{})",
            folder.display(),
            row.line,
            row.column
        ),
    );
}

/// The severity a row renders in: errors in the error color, warnings in
/// the warning color, so the strip reads like the log does.
pub fn severity_color(severity: Severity) -> Color {
    match severity {
        Severity::Error => tokens::TEXT_ERROR,
        Severity::Warning => tokens::TEXT_WARNING,
    }
}

pub(crate) fn plugin(app: &mut App) {
    app.init_resource::<BuildDiagnostics>().add_systems(
        Update,
        sync_build_diagnostics.run_if(in_state(crate::AppState::Editor)),
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A rendered rustc error, as `--message-format=json` carries it in
    /// `message.rendered`: the level line, the arrow, the source. The parse
    /// pins the arrow's three numbers and the block's severity.
    #[test]
    fn an_arrow_line_is_parsed_into_a_row_with_its_block_severity() {
        let log = "error[E0308]: mismatched types\n  \
                   --> src/lib.rs:12:5\n   \
                   |\nhelp: consider `.parse()`ing it\n";
        let rows = parse_diagnostics(log);
        assert_eq!(
            rows,
            vec![DiagnosticRow {
                file: "src/lib.rs".to_string(),
                line: 12,
                column: 5,
                severity: Severity::Error,
            }],
            "the arrow's path, line and column land as fields"
        );
        assert_eq!(rows[0].position(), "src/lib.rs:12:5");
    }

    /// A warning block's arrows read as warnings, a secondary span's arrow
    /// (a `note:` line's) keeps the diagnostic's own severity, and lines
    /// that are no diagnostic at all — cargo's stderr, progress chatter —
    /// pass without a row and without an error.
    #[test]
    fn non_matching_lines_pass_quietly_and_severity_follows_the_block() {
        let log = "warning: unused variable `y`\n \
                   --> src/game.rs:40:9\n\
                   Compiling game v0.1.0\n\
                   error[E0369]: cannot add strings\n \
                   --> src/game.rs:7:21\n\
                   note: the second operand is `&str`\n \
                   --> src/game.rs:7:30\n\
                   note: some noise without an arrow\n\
                   5 | let x = thing\n  |             ^\n";
        let rows = parse_diagnostics(log);
        assert_eq!(rows.len(), 3, "only arrow lines become rows: {rows:?}");
        assert_eq!(rows[0].severity, Severity::Warning);
        assert_eq!(rows[0].file, "src/game.rs");
        assert_eq!(rows[1].severity, Severity::Error);
        assert_eq!(
            rows[2].severity,
            Severity::Error,
            "a note's arrow keeps the error block it annotates"
        );
        assert_eq!(rows[2].line, 7);
        assert_eq!(rows[2].column, 30);
    }

    /// A log with no arrows at all — a linker failure, cargo refusing to
    /// even start — parses to zero rows while the error count still says
    /// what happened.
    #[test]
    fn an_arrowless_failure_yields_no_rows_and_an_honest_count() {
        let log = "error: linking with `cc` failed: exit status 1\n\
                   error: could not compile `game` due to 1 previous error\n";
        assert!(parse_diagnostics(log).is_empty(), "nothing to pin");
        assert_eq!(count_errors(log), 2);
    }

    /// The level-line matcher does not mistake prose for diagnostics.
    #[test]
    fn error_shaped_prose_is_not_a_level_line() {
        assert!(is_level_line("error[E0308]: mismatched types", "error"));
        assert!(is_level_line("error: could not compile", "error"));
        assert!(is_level_line("error", "error"));
        assert!(!is_level_line("errors were found in the manifest", "error"));
        assert!(!is_level_line("error_code = 5", "error"));
    }

    /// A path that itself carries colons — an absolute mac or windows
    /// spelling — splits from the right and keeps the whole path.
    #[test]
    fn a_colonful_path_survives_the_split() {
        let row = parse_arrow("/Users/dev/Weird:Dir/lib.rs:3:7").expect("parses");
        assert_eq!(row.file, "/Users/dev/Weird:Dir/lib.rs");
        assert_eq!((row.line, row.column), (3, 7));
        assert!(parse_arrow("src/lib.rs:12").is_none(), "no column, no row");
        assert!(parse_arrow("src/lib.rs:x:1").is_none());
        assert!(parse_arrow("has space.rs:1:2").is_none());
    }

    /// The two protocol faces build the argument lists their editors
    /// document: the VS Code family behind `--goto`, Zed positional.
    #[test]
    fn editor_args_match_the_protocol_forms() {
        let file = Path::new("/proj/src/lib.rs");
        assert_eq!(
            editor_args(EditorProtocol::GotoFlag, file, 12, 5),
            vec!["--goto".to_string(), "/proj/src/lib.rs:12:5".to_string(),]
        );
        assert_eq!(
            editor_args(EditorProtocol::Positional, file, 12, 5),
            vec!["/proj/src/lib.rs:12:5".to_string()],
        );
    }

    /// The probe table answers with the first executable a `PATH` holds,
    /// whatever order the table lists the rest in.
    #[test]
    fn the_probe_takes_the_first_editor_the_path_holds() {
        let dir = tempfile::tempdir().expect("tempdir");
        std::fs::write(dir.path().join("zed"), "#!/bin/sh\n").expect("fake zed");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt as _;
            std::fs::set_permissions(
                dir.path().join("zed"),
                std::fs::Permissions::from_mode(0o755),
            )
            .expect("chmod");
        }
        let path_var = format!("/nonexistent:{}", dir.path().display());
        let (name, protocol) = find_external_editor_in(&path_var).expect("the fake editor answers");
        assert_eq!(name, "zed");
        assert_eq!(protocol, EditorProtocol::Positional);
        assert!(
            find_external_editor_in("/nonexistent").is_none(),
            "an empty PATH answers nothing"
        );
    }

    /// A rendered path resolves against the project root first, then any
    /// sibling package directory with a Cargo.toml of its own (the
    /// `jd new` shape: the game crate lives one level down).
    #[test]
    fn a_rendered_path_finds_the_package_file() {
        let tmp = tempfile::tempdir().expect("tempdir");
        let package = tmp.path().join("my-game");
        std::fs::create_dir_all(&package).expect("the package dir is made");
        std::fs::write(package.join("Cargo.toml"), "[package]\n").expect("the manifest");
        std::fs::create_dir_all(package.join("src")).expect("the src dir");
        std::fs::write(package.join("src/lib.rs"), "fn main() {}\n").expect("the source");
        let mut world = World::new();
        world.insert_resource(crate::project::ProjectRoot {
            root: tmp.path().to_path_buf(),
            config: crate::project::ProjectConfig::default(),
        });

        assert_eq!(
            resolve_source_file(&world, "src/lib.rs"),
            Some(package.join("src/lib.rs")),
            "the package-relative spelling lands on the real file"
        );
        assert_eq!(
            resolve_source_file(&world, "src/gone.rs"),
            None,
            "a path no candidate holds answers nothing"
        );
    }
}
