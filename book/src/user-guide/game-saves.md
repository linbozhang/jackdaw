# Game Saves

A run ends, the player drags a volume slider, unlocks a mode — and
none of it is lost. The template persists a small player profile
through the runtime's save store: one human-readable JSON file under
the *user's* data directory, reloaded the next time the game starts.
This is the player's layer. It is deliberately separate from the
things you author: scenes and config assets live in the project's
`assets/` tree and ship with every build; the save belongs to whoever
is playing, and an exported build neither carries it nor overwrites
it.

The two layers compose, and the order is fixed:

```
config asset (authored default)  <  save (what the player changed)
```

[Game Parameters](game-parameters.md) covers the authored layer — a
`GameAudioConfig`, a `GameConfig`, files under `assets/` that Play,
`cargo run` and an exported build all read. This chapter covers the
layer above it: what the template saves, where the file lives, how a
 damaged or foreign-version save is handled without ever crashing the
game, and the one environment variable tests and scripts use to keep
their saves out of the real player tree.

## Where the save lives

One file per game, named `save.json`, under a directory named after
the game's crate (the string the game passes
`SavePlugin::new` — the template passes `env!("CARGO_PKG_NAME")`):

| OS | Directory |
|---|---|
| macOS | `~/Library/Application Support/<game-id>/` |
| Windows | `%APPDATA%\<game-id>\` |
| Linux | `~/.local/share/<game-id>/` |

Open it and it reads like data, because it is data — the whole file
for a fresh template game looks like this:

```json
{
  "save_version": 1,
  "saved_at": "2026-10-31T21:23:16Z",
  "profile": {
    "progress": { "runs_played": 3 },
    "unlocks": ["endless"],
    "audio": { "master": 0.35, "music": 0.6, "sfx": 0.5 },
    "input": null
  }
}
```

The runtime owns the envelope (`save_version`, `saved_at`); the game
owns `profile` — plain serde JSON of the game's own save type. Being
out of the project tree is the point, for three reasons:

* An **exported build is a read-only distribution** — it lands in
  `/Applications` or `Program Files`, where a game cannot write
  anyway. Progress lives with the player, not the install.
* The **project tree stays clean** — no player data mixed into the
  `assets/` the editor walks, versions, and ships.
* **Play's temp copies don't touch it** — a Play of unsaved work runs
  against a copy of the project under `assets/.jackdaw-pie/`
  ([Play-in-editor](play-in-editor.md)); a save living in the assets
  tree would land in that copy and never come back.

**Testing and QA seam:** the `JACKDAW_SAVE_DIR` environment variable
*replaces the save directory whole* (it is not a subdirectory of the
real one). Tests, scripts and CI point every game at one scratch tree
and the real player data is never touched. The seam moves the whole
directory, so a game run under it never even resolves the real path.

## One line to save: the plugin and the store

A game opts in with one line, the way it opts into a config:

```rust
app.add_plugins(SavePlugin::<GameSave>::new(env!("CARGO_PKG_NAME")));
```

The plugin loads the file synchronously in the build — the file is
small and local — so the store is in place before the first frame,
inserts it as a resource, and registers it for reflection. The
**`SaveStore<GameSave>`** resource has three reflected fields, which
makes it assertable from the [Resources panel](resources.md) and over
[BRP](remote-debugging.md) like any resource:

| Field | Meaning |
|---|---|
| `profile` | the game's data — the `profile` object in the file |
| `status` | how the last load went (the table below) |
| `dirty` | a change is waiting for the next write |

Mutations go through `get_mut()`, which hands out the profile mutably
and marks the store dirty in the same stroke (an edit made any other
way — including over BRP — must set `dirty` itself, or it never
reaches the disk); a flush system writes a dirty store on the next
update — there is no save call to forget. An explicit `write()` is
there for a game that wants the moment under its control, `reload()`
re-reads the file (dropping in-memory changes), and
`reset_to_default()` is the deliberate discard. The directory is
created lazily at the first write: a game that never saves never
leaves a directory behind.

## What the template saves

The template's `GameSave` covers the four classes a small game needs,
each through a real path rather than a demo:

| Class | In the profile | How it gets there |
|---|---|---|
| Progress | `progress.runs_played` | counted at every game-over (`OnEnter(GameFlow::GameOver)` — [Game Flow](game-flow.md)'s states are the hooks) — and both endings are game-overs, so a run won on the third pickup counts like a run lost |
| Unlocks | `unlocks` | the third finished run pushes `"endless"` |
| Audio | `audio` (`master`/`music`/`sfx`) | the pause screen's sliders and any other writer of `GameAudioConfig`; a watcher persists every change the same frame |
| Input | `input` (rebound actions) | the same watcher shape over `GameInputConfig` |

Two of these deserve a closer look, because they are bridges between
the two layers:

**The audio bridge.** The saved mix is `Option<AudioPrefs>` — the
same three knobs `GameAudioConfig` authors
([Audio](audio.md)'s three-way mix), minus the asset plumbing. At
startup a bridge system waits until the authored config has landed
(its loader despawns — that frame is the readiness gate), then puts
the saved values *over* it. `None` — the fresh first run — keeps the
authored values. From then on, every change to `GameAudioConfig` (a
slider drag, a BRP edit) lands in the save the same frame.

**The input bridge.** Saved rebinds restore through the same union
merge `input-actions.bsn` gets ([Game Input](game-input.md)):
same-named actions take the saved bindings, actions the save has
never heard of keep their authored ones — an old save is never
allowed to eat a new action a game update added.

The menu's `Runs:` line reads a mirror of the save in `GameState`
(bindings resolve resources — [Game UI](game-ui.md) has the binding
kinds), so after a restart the menu already shows the persisted
count.

## The three-state fallback

The store guards itself. Every problem warns with a `game save:` line
naming the path and the fallback, and **no problem ever keeps the
game from running**:

| What it reads | Status | What happens |
|---|---|---|
| nothing (first run) | `Fresh` | the default profile, *quietly* — no warning, no directory created |
| the current version | `Loaded` | the saved profile |
| a damaged file (bad JSON, empty, half-written, profile no longer fits the schema) | `Recovered` | the original bytes are renamed to `save.json.corrupt-<millis>` beside where they were, the default stands in, the next write repopulates the slot |
| an older version with a registered migration | `Loaded` | the migration chain walks the profile up to the current version, then it loads |
| an older version with no migration, or a *newer* version | `VersionSkipped { found }` | the default stands in and **the file is left untouched** |
| nowhere to put a save at all | `NoDir` | quiet defaults, writes refuse, the game runs |

Two behaviors in that table are worth stating as rules:

* **A damaged save is backed up, never destroyed.** The rename keeps
  the original bytes (one backup per event; the backups are not
  cleaned up — they are small, and each one is a player's data).
* **An unreadable save is never overwritten.** A `VersionSkipped`
  store — a future build's save, or an old one nobody registered a
  migration for — *suppresses automatic writing*, and an explicit
  `write()` refuses, until the game calls `reset_to_default()`: the
  one deliberate discard. Overwriting data this build cannot read
  with defaults would destroy it; corrupt files are different, because
  their bytes already sit in a backup.

Migrations are opt-in (`SavePlugin::with_migrations`) — a chain of
small steps, each turning a profile's raw JSON from one version to the
next. The template registers none: its first save format is version 1,
and the guard's fallback is the demonstration.

## The pause screen's sliders

The settings screen the template ships is the pause screen: three
sliders — Master, Music, Sfx — over the level's view
([Game UI](game-ui.md) has the overlay; the values you see on a
restart are the saved ones, restored by the audio bridge). A slider
does not write the save directly: dragging it fires a `ValueChange`
event, an observer writes the matching field of `GameAudioConfig`, and
the *watcher* — the same one that persists a BRP edit — carries the
change into the save that frame. On the next launch the saved mix is
bridged back over the authored config, and the sliders are pointed at
it: position and volume come back together.

One authoring boundary this screen teaches, worth knowing before you
add your own controls: **a `FeathersSlider` is a *scene component* —
a BSN component line only attaches its require chain and never spawns
the widget's scene.** The template authors the three label rows in
`hud.bsn` and attaches the actual sliders from Rust
(`commands.spawn_scene(bsn! { @FeathersSlider })` onto each row, with
the slider types registered for reflection). If a control you authored
as a plain component line shows up invisible and childless in the
game, this is why — attach scene components through `spawn_scene`, or
author only the layout slot in the document and let code hang the
widget on it.

## Play writes the real save

Play-in-editor runs the real game — real code, real logic — so Play
reads and writes the same `save.json` a standalone or exported build
does. What you reach in Play is what ships
([Play-in-editor](play-in-editor.md) covers the run itself). That is
the honest semantics, and it has one consequence to know: **a Play
session overwrites the standalone run's progress**, because they share
one slot per game.

One writer per slot: the store writes through a fixed temporary name
(`save.json.tmp`) that is renamed into place the instant it is
complete, so an interrupted write leaves the last good save — the
loader never mistakes a stray `.tmp` for one. But the fixed temp name
is also the reason **two live processes should not share one save
slot**: Play and a standalone run writing simultaneously is out of the
store's single-writer contract, and the three-state fallback is what
catches the worst case (the file is backed up, defaults stand in,
nothing unrecoverable is lost). Development loops that need both
processes alive point each at its own `JACKDAW_SAVE_DIR`.

## When a save goes wrong

The failure modes are all *loud in the log and quiet in the game* —
the opposite of the audio chapter's broken-file crash
([Audio](audio.md)); a broken save never takes the game down.

* **First run** — nothing on disk, no warning. `Fresh` is the normal
  state, not a problem.
* **Damaged file** — one `game save:` warning naming the path and the
  fallback, a `save.json.corrupt-<millis>` backup on disk, defaults
  in the store, and the next player change repopulates the slot.
* **Foreign version** — one warning naming the found version and this
  build's; the file is untouched and saving pauses (mutating values
  works in memory, but nothing lands on disk) until a migration is
  registered or the game deliberately discards. If values you change
  refuse to persist, read `status` first — this state is why.
* **Unwritable directory** — writes warn once and retry on the next
  attempt; the profile stays in memory and the game runs.

## The 30-second check

1. New project, **Play** (or `cargo run`): the menu shows `Runs: 0`,
   and `~/Library/Application Support/<game-id>/` does not exist yet —
   a first run leaves nothing behind.
2. Start a run, walk into the hazard, let the end screen count it.
   **Kill the process hard** (or quit) and relaunch: the menu shows
   `Runs: 1` — the restart recovery, no graceful-exit hook involved.
3. **Escape**, drag **Master** down, quit, relaunch: the slider sits
   where you left it and the mix matches — the saved layer over the
   authored one.
4. Delete `save.json`, relaunch: the game runs, silent — the quiet
   fresh default.
5. Fill `save.json` with garbage, relaunch: the game runs, the log has
   one `game save:` line naming the path, and a
   `save.json.corrupt-<timestamp>` sits beside the file. Change the
   volume once — the slot is a real save again.
6. Open `save.json` in a text editor: `save_version`, `saved_at`, and
   the `profile` you have been watching — the file is the truth.
