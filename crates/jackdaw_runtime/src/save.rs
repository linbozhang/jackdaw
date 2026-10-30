//! The save store: the player's data, in a file that survives the
//! process, separate from the scene files.
//!
//! A game's progress, unlocks and settings live in one small JSON file
//! under the user's own data directory — `~/Library/Application
//! Support/<game-id>/save.json` on macOS — reached by one line in the
//! game's plugin,
//!
//! ```ignore
//! app.add_plugins(SavePlugin::<GameSave>::new(env!("CARGO_PKG_NAME")));
//! ```
//!
//! The file is the *player's* layer: a config asset ([`ConfigPlugin`])
//! is the authored default a game ships with, the save is what the
//! player changed. They compose — authored default first, saved values
//! over it — and they live in different places: scenes and configs in
//! the project's assets tree, the save in the user directory, so an
//! exported build (a read-only distribution) neither carries nor
//! overwrites anyone's progress.
//!
//! ## The envelope and the version guard
//!
//! The file holds three fields: `save_version` (an integer this
//! runtime stamps and guards), `saved_at` (RFC 3339, UTC) and
//! `profile` (the game's own type, plain serde JSON —
//! [`SaveEnvelope`] is the on-disk contract). On load the guard reads
//! the version and picks a [`SaveStatus`]:
//!
//! * no file — [`SaveStatus::Fresh`], the default profile, *quietly*
//!   (a first run is the normal state, not a problem);
//! * the current version — [`SaveStatus::Loaded`], the saved profile;
//! * an older version with a registered [`SaveMigration`] for its
//!   step — the migration chain walks the profile up to the current
//!   version, then `Loaded`;
//! * an older version with no migration, or a *newer* version (a
//!   downgrade guard) — [`SaveStatus::VersionSkipped`], the default
//!   profile stands in, and **the file is left untouched**;
//! * anything that does not read — bad JSON, an empty or half-written
//!   file, a profile that no longer fits the schema — is
//!   [`SaveStatus::Recovered`]: the original bytes are renamed to
//!   `save.json.corrupt-<millis>` beside where they were (one backup
//!   per event, never cleaned up) and the default stands in.
//!
//! Every problem warns with a `game save:` line naming the path and
//! the fallback, the way a flow file describes itself; no problem
//! ever keeps the game from running.
//!
//! ## The invariant: an unreadable save is never overwritten
//!
//! [`SaveStatus::VersionSkipped`] suppresses automatic writing. The
//! file on disk is a save this build cannot read — a future build's
//! save, or an old one nobody registered a migration for — and
//! overwriting it with the default profile would destroy it: corrupt
//! files already sit in a backup, but this data would be gone. So the
//! flush system stays quiet and [`SaveStore::write`] refuses with
//! [`SaveError::VersionGuard`] until the game calls
//! [`SaveStore::reset_to_default`] — the one deliberate discard. A
//! `Recovered` save needs no such guard: its original bytes are
//! already in the backup, so the next write repopulates the slot.
//!
//! ## Writing
//!
//! Mutations go through [`SaveStore::get_mut`] (or any `ResMut`), which
//! marks the store dirty; [`flush_saves`] writes a dirty store on the
//! next update — tmp file, `sync_all`, rename, the atomic-write
//! discipline, so a crash mid-write leaves the last good save or a
//! stray `.tmp` the loader never mistakes for a save. Explicit
//! [`SaveStore::write`] is there for a game that wants the moment
//! under its control. The directory is created lazily, at the first
//! write: a game that never saves never leaves a directory behind.
//!
//! The directory is resolved once at plugin build: `JACKDAW_SAVE_DIR`
//! (set, it *replaces* the directory whole — the seam tests and QA
//! scripts point every game at one scratch tree), then
//! `dirs::data_dir()/<game-id>`, then the home-directory form of the
//! Linux default. Nowhere to resolve is [`SaveStatus::NoDir`]: loads
//! are quiet defaults, writes refuse, the game runs.
//!
//! [`ConfigPlugin`]: crate::ConfigPlugin

use std::marker::PhantomData;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use bevy::prelude::*;
use bevy::reflect::{GetTypeRegistration, Typed};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;

/// The file a game's save lives at, under the save directory.
pub const SAVE_FILE: &str = "save.json";

/// Environment variable naming the save directory; set, it replaces
/// the whole directory (not a subdirectory of it) — the seam tests and
/// QA scripts use to keep their saves out of the real player tree.
pub const SAVE_DIR_VAR: &str = "JACKDAW_SAVE_DIR";

/// The envelope version this build writes and reads. A save at any
/// other version needs a [`SaveMigration`] (older) or a newer build
/// (newer) — either way the guard skips it rather than overwrite.
pub const SAVE_VERSION: u32 = 1;

/// Where the save is: the part of the store a QA script (or any
/// reader over BRP) asserts first. `Fresh` is a first run; `Loaded` a
/// save that read clean; `Recovered` a damaged one (its original
/// bytes renamed into the backup named here); `VersionSkipped` a save
/// at a version this build cannot read (automatic writing is
/// suppressed); `NoDir` nowhere to keep one at all.
#[derive(Reflect, Clone, Debug, Default, PartialEq, Eq)]
#[reflect(Default)]
pub enum SaveStatus {
    /// No save file yet: the default profile, nothing warned.
    #[default]
    Fresh,
    /// The save read clean: its profile is in the store.
    Loaded,
    /// The save was damaged; the original bytes were renamed into the
    /// backup (named here) and the default profile stands in.
    Recovered {
        /// The backup file's name under the save directory; `None`
        /// when even the rename failed (warned separately).
        backup: Option<String>,
    },
    /// The save is at a version this build cannot read. The file on
    /// disk is left untouched and automatic writing is suppressed —
    /// see the module docs. `found` is the version the file carries.
    VersionSkipped {
        /// The version the unreadable save carries.
        found: u32,
    },
    /// No save directory could be resolved: loads are quiet defaults
    /// and writes refuse.
    NoDir,
}

/// One step of a migration chain: how to turn a save at version
/// `from` into one at version `to`. The `apply` walks the profile's
/// raw JSON (an object, usually) to the new shape; returning `Err`
/// fails the chain — which degrades the load to
/// [`SaveStatus::VersionSkipped`] (never a data-destroying overwrite).
#[derive(Clone)]
pub struct SaveMigration {
    /// The envelope version this step reads.
    pub from: u32,
    /// The envelope version this step writes.
    pub to: u32,
    /// The profile's old shape into the new one.
    pub apply: Arc<dyn Fn(JsonValue) -> Result<JsonValue, String> + Send + Sync>,
}

impl SaveMigration {
    /// A step from `from` to `to` with `apply` as its walker.
    pub fn new(
        from: u32,
        to: u32,
        apply: impl Fn(JsonValue) -> Result<JsonValue, String> + Send + Sync + 'static,
    ) -> Self {
        Self {
            from,
            to,
            apply: Arc::new(apply),
        }
    }
}

/// The on-disk contract: what every save file holds, at the top
/// level, in this order. The runtime owns `save_version` and
/// `saved_at`; the game owns `profile`.
#[derive(Serialize, Deserialize)]
pub struct SaveEnvelope<T> {
    /// The envelope version the file was written at ([`SAVE_VERSION`]
    /// for anything this runtime wrote).
    pub save_version: u32,
    /// When the save was written, RFC 3339, UTC, second precision.
    pub saved_at: String,
    /// The game's own data, plain serde JSON.
    pub profile: T,
}

/// Why a write did not happen. The game logs or ignores these; nothing
/// panics over a save.
#[derive(Debug, thiserror::Error)]
pub enum SaveError {
    /// No save directory could be resolved ([`SaveStatus::NoDir`]).
    #[error("no save directory could be resolved for this game")]
    NoSaveDir,
    /// The save on disk is at a version this build cannot read; the
    /// guard refused to overwrite it. [`SaveStore::reset_to_default`]
    /// is the deliberate discard.
    #[error(
        "the save on disk is at version {found}, which this build cannot read; \
         reset_to_default discards it deliberately"
    )]
    VersionGuard {
        /// The version the unreadable save carries.
        found: u32,
    },
    /// The envelope did not serialize.
    #[error("the envelope does not serialize: {0}")]
    Serialize(#[from] serde_json::Error),
    /// The directory could not be made or the file not written.
    #[error("the save file could not be written: {0}")]
    Io(#[from] std::io::Error),
}

/// A game's save: the profile, where it stands, and whether it owes
/// the disk a write. The resource [`SavePlugin`] inserts; a game (or a
/// BRP client) reads and mutates it like any resource — `profile`,
/// `status` and `dirty` are the reflected, assertable face, and the
/// plugin registers them (and the profile type) for reflection.
#[derive(Resource, Reflect, Clone)]
#[reflect(Resource)]
pub struct SaveStore<T: Send + Sync> {
    /// The game's data. The default until a save loads or the game
    /// changes it.
    pub profile: T,
    /// How the last load went (see [`SaveStatus`]).
    pub status: SaveStatus,
    /// A mutation is waiting for the next [`flush_saves`].
    pub dirty: bool,
    #[reflect(ignore)]
    dir: Option<PathBuf>,
    #[reflect(ignore)]
    migrations: Vec<SaveMigration>,
    #[reflect(ignore)]
    warned_write_failure: bool,
}

impl<T: Send + Sync + Default + DeserializeOwned> SaveStore<T> {
    /// Load the save at `dir` (an explicit directory — the seam a
    /// caller that resolves the location itself reads through, and the
    /// one tests read through to stay out of the process-wide
    /// environment). Returns the store and the warnings that explain
    /// it, in the `flow::start_scene_in` form: the caller logs them,
    /// so a test can assert a quiet default. `None` is a store with
    /// nowhere to live: [`SaveStatus::NoDir`], no warnings.
    pub fn open_in(dir: Option<&Path>, migrations: &[SaveMigration]) -> (Self, Vec<String>) {
        let mut warnings = Vec::new();
        let (profile, status) = match dir {
            None => (T::default(), SaveStatus::NoDir),
            Some(dir) => load(&dir.join(SAVE_FILE), migrations, &mut warnings),
        };
        (
            Self {
                profile,
                status,
                dirty: false,
                dir: dir.map(Path::to_path_buf),
                migrations: migrations.to_vec(),
                warned_write_failure: false,
            },
            warnings,
        )
    }
}

impl<T: Send + Sync + Default + DeserializeOwned> Default for SaveStore<T> {
    /// The nowhere-to-live store: [`SaveStatus::NoDir`], at the
    /// profile's default.
    fn default() -> Self {
        Self::open_in(None, &[]).0
    }
}

impl<T: Send + Sync + Serialize + DeserializeOwned + Default + Clone> SaveStore<T> {
    /// Mark a mutation: the profile hands itself out mutably and the
    /// store owes the disk a write the next update delivers.
    pub fn get_mut(&mut self) -> &mut T {
        self.dirty = true;
        &mut self.profile
    }

    /// Write the save now (the flush system does this on its own for a
    /// dirty store). Refused on a
    /// [`SaveStatus::VersionSkipped`] store — the guard, see the
    /// module docs. A failed write leaves the mutation pending
    /// (`dirty` stays) and the next attempt retries it.
    pub fn write(&mut self) -> Result<(), SaveError> {
        let Some(dir) = self.dir.clone() else {
            return Err(SaveError::NoSaveDir);
        };
        if let SaveStatus::VersionSkipped { found } = self.status {
            warn!(
                "game save: the write to '{}' is refused: the save on disk is at version \
                 {found}, which this build cannot read; reset_to_default discards it \
                 deliberately",
                dir.join(SAVE_FILE).display()
            );
            return Err(SaveError::VersionGuard { found });
        }
        let envelope = SaveEnvelope {
            save_version: SAVE_VERSION,
            saved_at: rfc3339_now(),
            profile: &self.profile,
        };
        let text = serde_json::to_string_pretty(&envelope)?;
        match atomic_write(&dir.join(SAVE_FILE), text.as_bytes()) {
            Ok(()) => {
                self.dirty = false;
                self.warned_write_failure = false;
                Ok(())
            }
            Err(error) => {
                if !self.warned_write_failure {
                    warn!(
                        "game save: '{}' could not be written ({error}); the profile stays \
                         in memory and the next attempt retries it",
                        dir.join(SAVE_FILE).display()
                    );
                    self.warned_write_failure = true;
                }
                Err(SaveError::Io(error))
            }
        }
    }

    /// Read the save again from disk, replacing the profile and the
    /// status with what the file says now. In-memory mutations are
    /// dropped — reload is a re-read, not a merge.
    pub fn reload(&mut self) -> SaveStatus {
        let mut warnings = Vec::new();
        let (profile, status) = match self.dir.as_deref() {
            None => (T::default(), SaveStatus::NoDir),
            Some(dir) => load(&dir.join(SAVE_FILE), &self.migrations, &mut warnings),
        };
        for warning in &warnings {
            warn!("game save: {warning}");
        }
        self.profile = profile;
        self.status = status;
        self.dirty = false;
        self.warned_write_failure = false;
        self.status.clone()
    }

    /// The deliberate discard: the profile goes back to its default,
    /// the status to `Fresh`, and the next write repopulates the file.
    /// This is also the one way out of a
    /// [`SaveStatus::VersionSkipped`] guard — the save this build
    /// cannot read is overwritten *because the game said so*.
    pub fn reset_to_default(&mut self) {
        self.profile = T::default();
        self.status = SaveStatus::Fresh;
        self.dirty = true;
        self.warned_write_failure = false;
    }

    /// The directory the save lives in, when one could be resolved.
    pub fn dir(&self) -> Option<&Path> {
        self.dir.as_deref()
    }

    /// The file the save lives at, when a directory could be resolved.
    pub fn save_file(&self) -> Option<PathBuf> {
        self.dir.as_ref().map(|dir| dir.join(SAVE_FILE))
    }
}

/// The save directory: `JACKDAW_SAVE_DIR` when set (the directory,
/// whole), else the game id under the user's data directory
/// (`dirs::data_dir()` — `~/Library/Application Support/<game-id>` on
/// macOS), else the home-directory form of the Linux default. `None`
/// is nowhere: the store loads quietly and refuses writes.
pub fn save_dir(game_id: &str) -> Option<PathBuf> {
    if let Some(overridden) = std::env::var_os(SAVE_DIR_VAR).filter(|v| !v.is_empty()) {
        return Some(PathBuf::from(overridden));
    }
    resolve_save_dir(dirs::data_dir(), std::env::home_dir(), game_id)
}

/// The layers under the env seam, one argument each so the `None`
/// bottom edge is constructible: the user data directory first, then
/// `~/.local/share/<game-id>` (the form `dirs::data_dir()` itself has
/// on Linux), then `None`.
fn resolve_save_dir(
    data_dir: Option<PathBuf>,
    home_dir: Option<PathBuf>,
    game_id: &str,
) -> Option<PathBuf> {
    data_dir
        .map(|dir| dir.join(game_id))
        .or_else(|| home_dir.map(|home| home.join(".local/share").join(game_id)))
}

/// The plugin: one line per game,
/// `SavePlugin::<GameSave>::new(env!("CARGO_PKG_NAME"))`. The save
/// loads in the build (the file is small and local — no async), so the
/// store is in before the first update, the way [`ConfigPlugin`]
/// inserts its default before anything can read it. The flush system
/// rides on `Update`, and the reflection registrations happen here —
/// [`SaveStore<T>`], [`SaveStatus`] and the profile type itself,
/// because a generic type is never in the reflect auto-inventory and
/// an unregistered one is invisible to BRP.
///
/// [`ConfigPlugin`]: crate::ConfigPlugin
pub struct SavePlugin<T> {
    /// The directory name under the user data directory. A crate name
    /// (`env!("CARGO_PKG_NAME")`) is the conventional choice.
    pub game_id: String,
    /// The migration chain the version guard walks (see
    /// [`SaveMigration`]). Empty is the common case: older saves then
    /// read as [`SaveStatus::VersionSkipped`].
    pub migrations: Vec<SaveMigration>,
    marker: PhantomData<fn() -> T>,
}

impl<T> SavePlugin<T> {
    /// Save `T` for the game named `game_id`.
    pub fn new(game_id: impl Into<String>) -> Self {
        Self {
            game_id: game_id.into(),
            migrations: Vec::new(),
            marker: PhantomData,
        }
    }

    /// Register the migration chain the version guard walks.
    pub fn with_migrations(mut self, migrations: Vec<SaveMigration>) -> Self {
        self.migrations = migrations;
        self
    }
}

impl<T> Plugin for SavePlugin<T>
where
    T: Reflect
        + FromReflect
        + Typed
        + GetTypeRegistration
        + Clone
        + Default
        + Serialize
        + DeserializeOwned
        + Send
        + Sync
        + 'static,
{
    fn build(&self, app: &mut App) {
        let dir = save_dir(&self.game_id);
        let (store, warnings) = SaveStore::<T>::open_in(dir.as_deref(), &self.migrations);
        for warning in &warnings {
            warn!("game save: {warning}");
        }
        app.insert_resource(store);
        app.add_systems(Update, flush_saves::<T>);
        app.register_type::<T>();
        app.register_type::<SaveStatus>();
        app.register_type::<SaveStore<T>>();
    }
}

/// The auto-write system: a dirty store whose status allows it is
/// written on the next update. A [`SaveStatus::VersionSkipped`] store
/// is *never* flushed — the invariant; `write` would refuse anyway,
/// but the flush stays quiet because the load already said why.
pub fn flush_saves<T>(mut store: ResMut<SaveStore<T>>)
where
    T: Serialize + DeserializeOwned + Default + Clone + Send + Sync + 'static,
{
    if !store.dirty || matches!(store.status, SaveStatus::VersionSkipped { .. }) {
        return;
    }
    let _ = store.write();
}

/// Read one save file, through the guard. The `flow.rs` parse shape:
/// a warning per problem, a default plus a status per outcome, never a
/// refusal to run.
fn load<T: DeserializeOwned + Default>(
    file: &Path,
    migrations: &[SaveMigration],
    warnings: &mut Vec<String>,
) -> (T, SaveStatus) {
    let bytes = match std::fs::read(file) {
        Ok(bytes) => bytes,
        // No file is the normal first run: the quiet default.
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return (T::default(), SaveStatus::Fresh);
        }
        Err(error) => return damaged(file, warnings, format!("could not be read ({error})")),
    };
    let Ok(text) = String::from_utf8(bytes) else {
        return damaged(file, warnings, "is not text".to_string());
    };
    let value: JsonValue = match serde_json::from_str(&text) {
        Ok(value) => value,
        Err(error) => return damaged(file, warnings, format!("does not read as JSON ({error})")),
    };
    let Some(fields) = value.as_object() else {
        return damaged(
            file,
            warnings,
            format!("holds a JSON {}, not an object", json_kind(&value)),
        );
    };
    for field in fields.keys() {
        if field != "save_version" && field != "saved_at" && field != "profile" {
            warnings.push(format!(
                "'{}' has a field the envelope does not know: '{field}'; it is ignored",
                file.display()
            ));
        }
    }
    let Some(found) = fields
        .get("save_version")
        .and_then(JsonValue::as_u64)
        .and_then(|found| u32::try_from(found).ok())
    else {
        return damaged(file, warnings, "names no save_version".to_string());
    };
    if found > SAVE_VERSION {
        warnings.push(format!(
            "'{}' was written by a newer build (version {found}, this build writes \
             {SAVE_VERSION}); it is left untouched and automatic saving is suppressed \
             until reset_to_default",
            file.display()
        ));
        return (T::default(), SaveStatus::VersionSkipped { found });
    }
    if found < SAVE_VERSION {
        let profile = fields.get("profile").cloned().unwrap_or(JsonValue::Null);
        return match migrate(profile, found, migrations, file, warnings) {
            Some(profile) => (profile, SaveStatus::Loaded),
            None => (T::default(), SaveStatus::VersionSkipped { found }),
        };
    }
    let Some(profile) = fields.get("profile") else {
        return damaged(file, warnings, "names no profile".to_string());
    };
    match serde_json::from_value::<T>(profile.clone()) {
        Ok(profile) => (profile, SaveStatus::Loaded),
        Err(error) => damaged(
            file,
            warnings,
            format!("profile does not fit this game's schema ({error})"),
        ),
    }
}

/// A damaged save: warn with the problem, rename the original bytes
/// into a `save.json.corrupt-<millis>` backup, default profile. The
/// backup having happened is why a `Recovered` save needs no write
/// guard: the next write cannot destroy anything.
fn damaged<T: DeserializeOwned + Default>(
    file: &Path,
    warnings: &mut Vec<String>,
    problem: String,
) -> (T, SaveStatus) {
    let backup = back_up_corrupt(file, warnings);
    warnings.push(format!(
        "'{}' {problem}; starting from the default{}",
        file.display(),
        match &backup {
            Some(backup) => format!(" (the original is kept as '{backup}')"),
            None => String::new(),
        }
    ));
    (T::default(), SaveStatus::Recovered { backup })
}

/// Rename the damaged file out of its slot, the
/// `project.json.corrupt-<millis>` form: one backup per event, never
/// cleaned up, never overwriting an earlier one unless two land in the
/// same millisecond.
fn back_up_corrupt(file: &Path, warnings: &mut Vec<String>) -> Option<String> {
    let name = file.file_name()?.to_string_lossy().into_owned();
    let millis = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|since| since.as_millis())
        .unwrap_or_default();
    let backup = file.with_file_name(format!("{name}.corrupt-{millis}"));
    match std::fs::rename(file, &backup) {
        Ok(()) => Some(format!("{name}.corrupt-{millis}")),
        Err(error) => {
            warnings.push(format!(
                "the damaged save '{}' could not be backed up ({error}); it will be \
                 overwritten at the next write",
                file.display()
            ));
            None
        }
    }
}

/// Walk a save's profile up the migration chain to the current
/// version. `Some` is a profile this build reads; `None` is a skipped
/// version (warned here) — the caller leaves the file untouched.
fn migrate<T: DeserializeOwned>(
    mut profile: JsonValue,
    mut version: u32,
    migrations: &[SaveMigration],
    file: &Path,
    warnings: &mut Vec<String>,
) -> Option<T> {
    let mut hops = 0;
    while version < SAVE_VERSION {
        let Some(step) = migrations.iter().find(|step| step.from == version) else {
            warnings.push(format!(
                "'{}' is at version {version}, this build reads {SAVE_VERSION}, and no \
                 migration is registered for that step; it is left untouched and \
                 automatic saving is suppressed",
                file.display()
            ));
            return None;
        };
        if step.to <= step.from {
            warnings.push(format!(
                "the migration {from}\u{2192}{to} walks backwards; '{file}' is left \
                 untouched",
                from = step.from,
                to = step.to,
                file = file.display()
            ));
            return None;
        }
        profile = match (step.apply)(profile) {
            Ok(profile) => profile,
            Err(error) => {
                warnings.push(format!(
                    "the migration {from}\u{2192}{to} failed ({error}); '{file}' is left \
                     untouched and automatic saving is suppressed",
                    from = step.from,
                    to = step.to,
                    file = file.display()
                ));
                return None;
            }
        };
        version = step.to;
        hops += 1;
        if hops > migrations.len() {
            warnings.push(format!(
                "the migration chain cannot reach version {SAVE_VERSION}; '{file}' is \
                 left untouched",
                file = file.display()
            ));
            return None;
        }
    }
    match serde_json::from_value(profile) {
        Ok(profile) => Some(profile),
        Err(error) => {
            warnings.push(format!(
                "the migrated profile does not fit this game's schema ({error}); '{file}' \
                 is left untouched and automatic saving is suppressed",
                file = file.display()
            ));
            None
        }
    }
}

/// Write bytes into place through a tmp file: write, `sync_all`,
/// rename — a crash mid-write leaves the last good save, or a stray
/// `.tmp` the loader never mistakes for one.
fn atomic_write(file: &Path, bytes: &[u8]) -> std::io::Result<()> {
    if let Some(folder) = file.parent() {
        std::fs::create_dir_all(folder)?;
    }
    let name = file
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default();
    let tmp = file.with_file_name(format!("{name}.tmp"));
    let mut handle = std::fs::File::create(&tmp)?;
    use std::io::Write as _;
    handle.write_all(bytes)?;
    handle.sync_all()?;
    drop(handle);
    std::fs::rename(&tmp, file)?;
    Ok(())
}

/// Now, RFC 3339, UTC, at second precision.
fn rfc3339_now() -> String {
    rfc3339(
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|since| since.as_secs())
            .unwrap_or_default(),
    )
}

/// RFC 3339, UTC, at second precision, from the Unix second count
/// (`1769635396` is `2026-01-28T21:23:16Z`). No timestamp crate rides
/// along for one field: the civil-from-days conversion below is the
/// whole of it, pinned by the tests.
fn rfc3339(unix_secs: u64) -> String {
    let (year, month, day) = civil_from_days((unix_secs / 86_400) as i64);
    let rem = unix_secs % 86_400;
    format!(
        "{year:04}-{month:02}-{day:02}T{h:02}:{m:02}:{s:02}Z",
        h = rem / 3_600,
        m = rem % 3_600 / 60,
        s = rem % 60
    )
}

/// The proleptic Gregorian date a Unix day count names (Howard
/// Hinnant's civil-from-days).
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let month = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (year + i64::from(month <= 2), month, day)
}

fn json_kind(value: &JsonValue) -> &'static str {
    match value {
        JsonValue::Null => "null",
        JsonValue::Bool(_) => "boolean",
        JsonValue::Number(_) => "number",
        JsonValue::String(_) => "string",
        JsonValue::Array(_) => "list",
        JsonValue::Object(_) => "object",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The layering, with every input explicit so the `None` bottom
    /// edge is constructible: env already handled above this,
    /// data dir over home over nothing.
    #[test]
    fn the_save_directory_layers_data_dir_over_home_over_none() {
        let data = PathBuf::from("/data");
        let home = PathBuf::from("/home/player");
        assert_eq!(
            resolve_save_dir(Some(data.clone()), Some(home.clone()), "my-game"),
            Some(data.join("my-game"))
        );
        assert_eq!(
            resolve_save_dir(None, Some(home.clone()), "my-game"),
            Some(home.join(".local/share/my-game")),
            "the home fallback is the form data_dir has on Linux"
        );
        assert_eq!(
            resolve_save_dir(None, None, "my-game"),
            None,
            "nowhere to resolve: NoDir, quietly"
        );
    }

    /// The timestamp the envelope carries, pinned: the epoch, a leap
    /// day, and a present-day second (`date -u -r` agrees with each).
    #[test]
    fn the_saved_at_stamp_is_rfc3339_utc() {
        assert_eq!(rfc3339(0), "1970-01-01T00:00:00Z");
        assert_eq!(rfc3339(951_782_400), "2000-02-29T00:00:00Z");
        assert_eq!(rfc3339(1_769_635_396), "2026-01-28T21:23:16Z");
    }
}
