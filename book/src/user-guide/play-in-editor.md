# Play-in-editor

Play-in-editor (PIE) runs your game as a real process and streams its
frames into the editor, so you can play, inspect, and live-edit a running
build without leaving jackdaw. The game runs in its own process, so a
crash takes down the game, not the editor.

PIE keeps two surfaces strictly separate:

- The **Game panel** is a pure monitor of the running game's frame.
- The **Viewport** is always an editing surface for the authored scene.
  It never composites the game frame over your scene.

## Which scene Play runs

The **Play button (F5) plays the scene in front of the editor** — any
open scene, saved or not. The Play dropdown's first row, **Play Startup
Scene**, keeps the other meaning: launch the game and let it load
whatever its own code loads (`scene.bsn` in the template), and the run
rows below it stay that way too.

Playing the current scene hands the game the scene through the
`JACKDAW_PIE_SCENE` environment variable: the runtime swaps the first
scene root it finds for the named scene, so a game that loads its scene
through `jackdaw_runtime`'s scene root plays it without any code of its
own changing. Two limits worth knowing:

- Only the **first** scene root a game spawns is swapped — the game's
  "main scene" by convention. Roots the game's own systems add while
  running (a level loader, a second world) keep the scenes they name.
- A game that spawns its scene some other way than a
  `JackdawSceneRoot` does not follow the override; it plays its own
  scene.

## Unsaved changes: the three policies

What Play does with unsaved work before launching is a project setting
(`project.set_save_before_play`, or the toggle in the editor):

- **save** (default): every modified scene that has a file is saved
  first, so the game loads exactly what the editor shows.
- **ask**: a dialog before launching — **Save**, **Play Unsaved Copy**,
  or **Cancel**.
- **play_unsaved_copy**: the game runs against a temporary copy of the
  unsaved work; nothing reaches disk and the tab keeps its dirty flag.

A scene that has never been saved (an untitled tab) never blocks Play
and is never written: it always runs as a temporary copy, whatever the
policy. A settings file from before the three policies carried a bool;
it reads back as `true` = save and `false` = play a copy — the old
`false` ran the game against whatever was last on disk, a silent
wrong-scene the copy mode ends.

### The temporary copies

A play of unsaved work writes a copy under `assets/.jackdaw-pie/`
(`current-<scene>-<editor pid>.bsn`). The dot-prefixed directory is
skipped by every asset walk, so the copy never shows up in the asset
index, the reference audit, or a referrers search. It is deleted when
play stops and swept away the next time the project opens, so a killed
editor leaves nothing behind that matters; the copy itself is
regenerable — its source is the tab in the editor that wrote it.

## Stopping and reloading

- **Stop** asks the game to exit and gives it a two-second window to do
  so cleanly — flushing, saving what it means to save, running its exit
  hooks — before the editor kills it. The editor returns to authoring
  mode when the game is gone.
- **Stop restores the edit state**: the running game's state was only
  ever a projection over the preview world, and the authored scene
  comes back exactly as it was — same entities, same file on disk, same
  dirty flags, same undo stack. What the game did while running never
  reaches the document; the only way runtime changes come back is the
  explicit gates (Save to Scene, the Live Changes tray, the stop
  prompt's Apply).
- **Reload** rebuilds and relaunches. A current-scene session reloads
  onto a freshly resolved scene: edited since the launch, the relaunch
  writes a new temporary copy; still clean, the same file. A reload
  never writes disk on its own.

## What you need

Nothing compiles at play time once the project is built. The editor
builds your game as an ordinary cargo binary when the project opens;
Play launches that same executable and connects to it over IPC.

That build goes to `.jackdaw/target/game` inside your project, never to
the project's own `target/`. The editor builds the plain package, while
the build you run from your terminal usually carries features of your
own; keeping them apart means neither overwrites the other's binary, at
the cost of compiling the dependencies once more. `.jackdaw/` is
gitignored, so none of it is committed; a project that does not ignore it
should.

The editor compiles your dependencies optimised (`opt-level = 2`, line
tables only) and your own crate as your profile says, because a game
spends its load and its frames in Bevy and the runtime. A project that sets
a dev `opt-level` for itself or its dependencies keeps that setting, whether
in its manifest, a `.cargo/config.toml` in its folder or a parent, cargo's
home, or `CARGO_PROFILE_DEV_OPT_LEVEL`. So the first build compiles every
dependency once, which takes several minutes, and later builds only compile
your crate. A plain `cargo run` follows your manifest; new projects start
with the same profile in theirs.

To opt out, set `opt-level` under `[profile.dev.package."*"]`: `0` builds
dependencies as cargo would by default. While the override stands, stepping
into a dependency in a debugger is limited: the code is optimised and carries
line tables only, so it has no local variables to show. Setting `debug = true`
under `[profile.dev.package."*"]` keeps full debug info, on code still
optimised.

The Play dropdown is filled from the **run configurations** in your
project's `jackdaw.toml` (`[[run]]` entries carrying a name, environment
variables, arguments, an instance count, and a working directory). A
project with no `jackdaw.toml` still plays: the editor synthesizes a
single default run. See [Configuration](../reference/configuration.md)
for the fields.

How many configs you define is up to your game. Some games run a single
process; others split into several that you launch together. Configs
differ in launch environment, and — with a run target — in what gets
built; see [Run targets](#run-targets) below. PIE treats each launched
process as an instance and streams the focused one.

## Run targets

By default every run plays the package's own game binary. A run can
instead name a cargo target to build and play: one `[[bin]]` or
`[[example]]`, optionally of another workspace member, with cargo
features and a profile.

```toml
[[run]]
name = "Server"
target = { bin = "server", features = ["net", "dedicated"], profile = "release" }

[[run]]
name = "Split-screen"
target = { example = "split_screen", package = "game-client" }
```

The `target` table's fields (exactly one of `bin`/`example`):

- `bin` / `example`: the cargo target to build and launch. Its
  executable's path comes from cargo itself, so wherever cargo puts an
  example or a custom profile's artifacts is where the run finds it.
- `package`: another workspace member to build instead of the package
  `jackdaw.toml` resolves for the project.
- `features`: cargo features for the build.
- `profile`: the cargo profile to build with. `dev` and `release` are
  always available; any other name needs a `[profile.*]` table in the
  manifest.

Each run with a target is built and cached separately from the default
one, so playing `Play` and then `Server` launches each its own binary.
The Play row carries a dim badge — `bin:server`,
`example:split_screen` — so same-named rows of different targets stay
tellable apart.

You write targets by hand in this version: the editor does not discover
your workspace's bins and examples for you, and it does not manage
prebuilt binaries — a target is built from source through the same
pipeline as the default game. `jd doctor` checks every target before
anything builds: that the package exists, that the bin/example name is
one the package declares, and that the profile is one cargo will
accept. From the terminal, `jd run --config <label>` builds the named
run's target and launches it with that run's env/args/cwd, exactly as
the editor's Play of that row does; without `--config`, `jd run` keeps
its historical behaviour of a plain `cargo run` in the project root.

## Building a standalone executable

An export turns the project into a directory that runs on its own —
no editor, no cargo, no terminal: double-click the executable and the
game starts. **File > Build Game...** builds the game with the release
profile, stages the executable beside a copy of the whole asset tree
(the folder your `jackdaw.toml` names with `assets_dir`, `assets/` by
default), and opens the folder when it finishes. The footer shows the
same compiling progress a Play build does; a failure lands in the Build
panel with the compiler output — whose strip pins the first error's
file, line and column, with a row that opens your editor exactly there
([Debugging Errors](debugging-errors.md) is the thirty-second tour).

The same export is on the terminal, with a say in what and where:

    jd export                             # release, into .jackdaw/dist/release/
    jd export --profile dev               # another profile, staged side by side
    jd export --config Server             # a run's target dimensions (bin, features...)
    jd export --out D:\ Builds\game       # an absolute directory of your own
    jd export --out D:\ Builds\game --force  # ...that something else lives in

`--profile` defaults to `release` and overrides whatever the selected
run's target carried; `--config` reuses a `[[run]]` target exactly as
`jd run --config` does, then applies the profile on top. `--out` must
name an absolute path: the output directory is replaced wholesale on
every export, so a relative one — `--out .` is the extreme — is refused
rather than replacing whatever the current directory happens to be.

The staged layout is the one thing a standalone run needs:

```text
<project>/.jackdaw/dist/release/
    my-game.exe
    assets/...            <- your assets_dir, staged under its own name
    .jackdaw-export       <- "this directory is ours" marker
    export-manifest.json  <- every shipped file, hashed (see below)
```

A game resolves its asset root by `BEVY_ASSET_ROOT`, then
`CARGO_MANIFEST_DIR`, then its own executable's directory — and a
double-clicked executable has none of the first two, so the
executable with the asset folder beside it is the only supported
layout. A project whose `assets_dir` names another folder (`content/`,
say) stages it under that name, matching what the game's own
`AssetPlugin` resolves.

**A failed export keeps the old one.** The new export is assembled in
full beside the output and swapped in only when complete: if anything
fails — a full disk, a locked file, the game from the last export
still running — the previous export stays exactly as it was, byte for
byte. A re-export replaces rather than merges (assets the project
dropped do not survive beside the new executable), and moving or copying
the directory elsewhere works unchanged — the assets follow the
executable.

Three things an export refuses, rather than shipping a game that will
not start:

- A project built with bevy's `dynamic_linking` feature. Its
  executable needs dlls the staging directory would not have. Remove
  the feature (a statically linked game carries everything it needs)
  and export again. The `jd new` template never sets it.
- An editor extension project. An extension builds a library for the
  editor and has no game to export.
- An `--out` that holds something no jackdaw export wrote: a
  non-empty directory without the `.jackdaw-export` marker is not ours
  to delete, so the export refuses and says so. Write into an empty
  directory, or pass `--force` — explicit consent on the command line —
  to replace it. (The editor's Build Game entry has no force; its
  default directory is always one jackdaw created.)

### What ships, and what stays behind

The asset copy filters the editor's own private files out of the
package: scene save rotations (`*.bak`), atomic-write leftovers
(`*.tmp-*`, `*.corrupt-*`), and the play-in-editor temp directory
(`.jackdaw-pie/`, which holds unsaved scene content while a session
runs). Everything else — including any dotfile you own — ships, and
the export report counts what was kept out, so a package that filtered
something says so instead of being silently thinner. Exporting while a
play session runs is fine: its temp copies are filtered, not staged.

### The export manifest

Every export writes `export-manifest.json` at the root of its output:
each shipped file's path, SHA-256 and size, plus the profile, the
jackdaw version, and the Bevy commit the editor was built against.
Two exports of the same input produce the same manifest (the
generation time is the only field allowed to differ), which is what
"same input, same output" means in practice: re-export, compare, ship.
The manifest is also a verifier — a moved or copied package can be
checked file by file against it.

### Reproducible builds

Every build the editor runs — Play, `jd build`, `jd run`, export —
passes `--locked` to cargo: the lockfile is the contract, and a silent
dependency re-resolution is how an upstream crate update turns into a
wall of errors nobody asked for. A project without a `Cargo.lock`
gets one generated on the first build, with a note to commit it. When
the lockfile is out of date with `Cargo.toml` (a dependency added or
changed by hand), the build fails with the remedy in its log: run
`cargo update`, or delete `Cargo.lock` to regenerate it, and commit
the result. A project without `rust-toolchain.toml` is told so in the
same log — new jackdaw projects pin one, and `jd doctor` reports both
files' presence for the project in scope.

The staged game still carries the `pie` feature the template adds to
`jackdaw_runtime`. It is inert outside the editor (nothing connects to
it without the editor's environment variables), but a release can drop
it from `jackdaw_runtime`'s features in the game's `Cargo.toml` — a
one-line edit that is yours to make, not the tool's. (Before shipping,
running the asset audit once — the References panel's missing-reference
check — is cheap insurance: an export stages exactly what the project
holds, references that do not resolve included.)

Not to be confused with two other exports: `jd export-terrain` writes
a heightmap, and the `project.export_binary` operator converts scene
documents to their binary form. Neither builds the game.

## Your own launch environment

A run config is committed, so it can only say what is true for everyone
working on the game. The variables that point a launch at a particular
server, or carry a sign-in token, or ask for an offline mode, are yours
alone. Those go in **Play Settings**, which the `play.settings` operator
opens:

- **Environment** is a line of `NAME=value` words, added to every game
  the editor launches and overriding a run config's own.
- **Arguments** is a line of words, appended to the ones the run config
  names.

Both are kept with the project's other editor preferences, under
`.jackdaw/`, which a project does not commit, and the editor never writes
or logs their values anywhere else. To set them without the dialog:

    play.settings env="REALM=dev TOKEN=..." args="--offline"

Either parameter replaces what is held; naming neither opens the dialog.

The **Game** panel docks in the bottom dock area next to Assets. An embedded
Play brings it to the front, since the game only streams while the panel is
showing.

## Launching

The play controls header carries **Play**, **Pause**, **Stop**, and
**Reload**, plus a window-mode button that reads **Embedded** or
**Windowed**. The window-mode button sets the mode for the next launch.

- **Embedded** (default): no separate game window opens. The game renders
  off-screen and streams into the Game panel at full frame rate. This is
  the mode you want for input capture and picking.
- **Windowed**: the game opens its own OS window. The Game panel still
  mirrors the active in-game camera once one exists, but menus do not
  stream and input capture is not offered.

Hit **Play** to launch. The Game panel starts streaming immediately,
beginning with whatever the game shows first (often a menu or title
screen). The outliner shows a **LIVE** badge with the running instance's
name.

When more than one instance is running, the **instance picker** in the
outliner header switches which one the Game panel and Live tree follow.

## Playing the game

Click inside the Game panel to engage input capture (or use the **Play
Input** header button). While captured:

- Keyboard and mouse forward to the game. WASD, mouse-look, scroll, clicks,
  and typing all reach it.
- Editor keybinds are suppressed. Tool keys and `Ctrl+S` go to the game,
  not the editor.
- A **Playing, Shift+Esc to release** chip shows, and the panel border
  takes the capture accent.

Plain `Esc` forwards to the game (so the in-game menu still opens). Press
`Shift+Esc` to release capture and return control to the editor. Capture
also releases on its own if you stop the game, switch instances, click away
to another application, or close the panel, and any keys you were holding
are released so nothing stays stuck down.

## Selecting entities while playing

Select entities in the outliner's **Live** tab. The Components panel shows
the selected entity's live values, and the game draws a bounding box around
it in the frame.

## Scene and Live trees

The outliner header has a **Scene | Live** tab switch:

- **Scene** shows the authored tree of the open scene file. This is the
  same hierarchy you edit when the game is not running.
- **Live** shows the entities the focused game instance currently has,
  including runtime-only ones. Authored entities the game has not spawned
  do not appear here.

The two trees are independent. When the game shows a menu, the Live tab
shows the menu's entities while the Scene tab still shows your authored
scene, and the Viewport keeps showing that scene with gizmos, fully
editable. You can select and edit authored entities in the Viewport or
Scene tab at any time without disturbing the running game's frame.

## The stop prompt and live changes

An edit made to a projected entity in the **Live** tree goes to the
running game and is recorded in the **Live Changes** tray; it does not
change the authored scene document by itself. The tray is the review
surface: each row shows the recorded baseline and current live value as
`baseline -> live`, alongside per-edit **Save** and **Revert** actions.
For example, `0.0 -> 3.5` means the field was 0.0 when first edited and is
now 3.5 in the running game. The Inspector's live-edit marker identifies
tracked fields, and the hierarchy's Live Changes badge is a **count**, not
a tray button. Clicking the badge does not open the tray.

While the game is running, **Revert** sends the recorded baseline back to
the game and removes that field entry. **Save** writes the tracked value
to the authored scene document. **Apply All** writes the pending changes
together as one undoable batch; **Discard All** clears the pending-change
ledger without writing those values to the document or changing the
currently running game. The live value remains until it changes or the
session ends; stopping restores the authored preview. For a pending change
when Play stops, the prompt offers three choices:

- **Apply All** writes the pending changes to the scene document.
- **Discard** clears them without applying them to the document.
- **Review** closes the prompt and hands the changes to the Live Changes
  tray for individual triage. If Play is started again while the prompt is
  open, review is handed off to the tray as well.

To open the tray through the supported review flow, stop Play with pending
changes and choose **Review**. After stopping, there is no running entity
to receive a field-level Revert: that action can warn and leave its entry
pending. Save the entry, use Apply All, or discard it instead. This differs
from Revert during Play, when the baseline can still be streamed to the
game.

### What live editing includes

The runtime-edit surface has a **finite, built-in boundary**, not a
user-configurable component whitelist. Three existing filters determine
what can be reached and retained:

1. The game streams entities with a `Transform`, excluding selected
   derived-face and frame-capture camera entities. Entities outside that
   stream cannot be selected or edited through this live route.
2. The editor's projection omits selected camera and other skipped
   components when it mirrors the game into the editing world.
3. Scene saving applies its existing component skip rules, and resource
   entities are excluded from Inspector live-field routing.

These are implementation filters, not a project setting where you can
choose an arbitrary list of editable components. The exact components
available also depend on what the game exposes and the editor can reflect.

Runtime component **add** and **remove** operations are streamed and
tracked as structural rows. Their row **Save** action is available to
retain the structural change in the authored scene; **Revert** is disabled
for these rows. Use Save or Apply All to keep the change, or Discard to
leave it out of the scene. This is the current structural-edit boundary;
it is not a field-level baseline that can be reverted during Play.

### Saving runtime changes deliberately

A live edit is **not an automatic save**. It first changes the running
game and enters the review ledger. Tray **Save**, **Apply All**, and the
stop prompt's **Apply All** apply reviewed values to the authored scene
document; they do not by themselves write the scene file to disk. Save the
scene explicitly (for example, with **Ctrl+S**) after applying changes.
The Inspector's **Save to Scene** action is a separate explicit gate for
copying an entity's live component values into the scene:

- **Path A — authored projection:** saving an authored entity copies its
  live overlay onto the corresponding scene node as one undoable change.
- **Path B — runtime-only entity:** saving an ephemeral entity promotes
  it to a new scene node. In v1 this promotion is **not undoable**; use a
  disposable scene or save a backup before promoting an entity you may
  need to remove. Save the scene file explicitly afterward.

Path B stores authored, meaningful component values rather than a raw
snapshot of the running physics world. Avian relationship data tied to
one runtime session and per-frame or derived physics state are excluded;
authored values such as Transform, rigid-body type, collider shape, and
physics configuration remain eligible for saving. This filter is not a
user-editable whitelist.

A long editor session with repeated Play/stop cycles can encounter a
stale Live projection binding (LT9, still an open limitation). If a live
edit does not appear to reach the running game, stop and restart the
session or editor before continuing; this is a workaround, not a claim
that the limitation has been fixed. On macOS, a known PIE panic
signature may also appear in logs even when the editor remains available.
Treat it as diagnostic noise rather than a save signal: runtime changes
still require one of the explicit gates above.

### A 30-second check

Use a disposable scene for this quick check:

1. In Play, edit an authored field. Confirm its `baseline -> live` row in
   the tray, choose **Apply All**, save the scene file, reopen it, and Play
   again to verify the saved value reaches the game.
2. Repeat with a different field and choose **Discard** instead. Confirm
   the authored document remains unchanged for that edit.
3. Add and remove a runtime component. Confirm each appears as a
   structural row with **Save** available and **Revert** disabled.
4. Select a runtime-only entity and use **Save to Scene**. Confirm it is
   promoted, remember that Path B is not undoable in v1, and explicitly
   save the scene file if you want to keep the new node.
