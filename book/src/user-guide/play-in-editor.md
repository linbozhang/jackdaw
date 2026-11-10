# Play-in-editor

Play-in-editor (PIE) runs your game as a real process and streams its
frames into the editor, so you can play a running build and edit its scene
without leaving jackdaw. The game runs in its own process, so a crash takes
down the game, not the editor.

PIE keeps two surfaces separate:

- The **Game panel** is a monitor of the running game's frame.
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

The editor compiles your dependencies optimized (`opt-level = 2`, line
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
into a dependency in a debugger is limited: the code is optimized and carries
line tables only, so it has no local variables to show. Setting `debug = true`
under `[profile.dev.package."*"]` keeps full debug info, on code still
optimized.

The Play menu lists the **run configurations** in your
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

## Launching

The play controls in the title bar are **Play**, **Pause**, **Step** and
**Stop**, with the Play menu on the arrow beside Play.

| Key | Action |
| --- | --- |
| `F5` | Play, or resume a paused game |
| `Ctrl+F5` (`Cmd+F5` on macOS) | Restart |
| `F7` | Pause or resume |
| `F8` | Stop |
| `F10` | Step one tick while paused |

Every key can be changed in the keymap. `F5` does nothing while a game is
running, so a second press never restarts it by accident.

Hit **Play** to launch, from the toolbar or from the Play button in the Game
panel. The Game panel comes to the front as the build starts. While the game
builds, Play reads **Building...** and **Stop** cancels the launch, stopping
the build. Once the game runs, Play fills with the accent color, the
viewport's edge takes the accent too, and the status bar reads **Playing**,
followed by the run configuration's name when it has one. The Game panel
starts streaming immediately, beginning with whatever the game shows first
(often a menu or title screen).

The game spawns the scene the editor has open, not the file on disk, so
there is no need to save first. Prefabs and sidecars with unsaved changes
reach it too. Model settings must be saved first; Play says so in the status
bar when some are not.

**Pause** freezes the game's clock and shows as pressed; Play then reads
**Resume**. While paused, **Step** advances the game by one fixed tick. The
game keeps rendering and keeps taking your edits while paused, so you can
change a value and step to see it act.

The Play menu holds:

- one row per run configuration instance, ticked while it runs; click a row
  to launch or stop that instance on its own
- the scene Play will run: the scene in front, unless a run configuration
  names one
- **Rebuild**, which rebuilds the project so new components appear in the
  editor
- **Restart**, which rebuilds and relaunches the running game with the
  current window setting
- **Play in separate window**, ticked when the next launch opens the game in
  its own OS window instead of the Game panel. See
  [The Game panel](#the-game-panel).
- **Revert edits when Play stops**, ticked when edits made during Play are
  undone on Stop. See [Stopping and reverting](#stopping-and-reverting).

## The Game panel

The **Game** panel docks in the bottom dock area next to Assets. An embedded
Play brings it to the front, since the game only streams while the panel is
showing.

By default the game renders off-screen and streams into the panel at full
frame rate, which is the mode you want for input capture and picking. With
**Play in separate window** the game opens its own OS window. The panel still
mirrors the active in-game camera once one exists, but menus do not stream
and input capture is not offered. The setting is kept per developer with the
Play settings, and **Restart** applies a change to it.

While there is no frame, the panel says what the game is doing:

- **Building the game...**, **Starting the game...** and **Loading the
  game...** while a launch progresses. A game that has not connected after ten
  seconds is called out, and a first frame that takes a minute is too.
- An idle panel with a **Play** button when no game runs.
- **Running in its own window** when the game was launched in a separate
  window. A game that opened its own window although the panel was meant to
  show it needs its `DefaultPlugins` passed through
  `jackdaw_runtime::maybe_windowless` in `main.rs`.

The header holds:

- The **view menu** sets the size the game renders at. **Free** fills the
  panel. **16:9**, **4:3** and **1:1** keep that aspect and letterbox it
  inside the panel. **1280 x 720** and **1920 x 1080** render at that size and
  scale it to fit. The menu also holds **Mute**, which silences the running
  game and the games Play launches until you unmute, and a way to open the
  Game Output window. A **muted** chip shows while mute is on.
- The **instance picker** shows when more than one instance is running. It
  names the instance on show, such as **Server** or **Client 2**, and lists the
  others to switch to.
- The **pop-out** button at the right moves the game to its own window, or
  back into the panel. It shares the **Play in separate window** setting, and
  a running game restarts in the new place. Play in a separate window when you
  want real performance numbers; the panel is not a performance view.

The view size and mute are kept per developer with the Play settings.

## Playing the game

When the game shows its first frame, the Game panel takes input on its own,
unless you clicked or pressed a key in the editor while it was starting, so a
long build never takes input from you once you have gone back to editing.
Otherwise click inside the Game panel to engage input capture. While captured:

- Keyboard and mouse forward to the game. WASD, mouse-look, scroll, clicks,
  and typing all reach it.
- Editor keybinds are suppressed. Tool keys and `Ctrl+S` go to the game,
  not the editor.
- **Shift+Esc to release** shows over the game for a moment, and the panel
  border takes the capture accent.

Plain `Esc` forwards to the game, so the in-game menu still opens. Press
`Shift+Esc` to release capture and return control to the editor. The Stop
key (`F8`) also works while captured: it releases capture and stops the game,
so a game that binds `F8` itself does not get it while playing in the editor.
Capture also releases on its own if you stop the game, switch instances, click
away to another application, or close the panel, and any keys you were holding
are released so nothing stays stuck down.

## Editing while playing

The editor works as it does when stopped. The outliner, Components panel and
viewport all work on the scene document, so anything you do during Play is an
ordinary edit: it undoes, marks the tab as modified, and saves with the scene.
Each edit also reaches every running instance straight away, including adds,
deletes and reparents.

Dragging a field in the Components panel moves the game on every tick. The edit
joins the document when you let go, and a cancelled drag puts the game back. A
transform gizmo drag reaches the game when you let go.

Selecting an entity draws a bounding box in the game's frame around every entity
spawned from that node by the scene in front. A child inside a prefab instance
boxes that instance's child, and a node in an open prefab tab boxes it in every
instance.

### Runtime entities and live values

The editor also reads from the running game, without changing it:

- The Outliner's **Runtime** group lists the entities the game spawned that no
  scene node did, under the authored entities they sit below. It is read-only,
  shows while a game runs, and asks the game for its entities about once a
  second while it is open.
- Selecting a Runtime row shows that entity in the Inspector as a read-only
  card, and clears the selection. Selecting anything else in the editor ends
  it.
- When the running game holds a different value for a number, bool, text or
  vector field of the selected entity, and its node spawned one entity in the
  game, the field carries a **Live** chip with that value. A collapsed
  component card carries a **Live** badge. The chip is not saved, and the
  document keeps the authored value.

## Stopping and reverting

**Stop** ends the game process. The Game panel returns to its idle state, the
panel that was in front before Play comes back, and the viewport's edge
clears. Stopping never asks about edits. A game that exits or crashes on its
own puts the controls back to stopped too.

Edits made during Play stay in the document by default. **Revert edits when
Play stops**, in the Play menu and kept per developer with the Play settings,
undoes them instead. Once the last game stops, each document edited during Play
goes back to where it stood when Play started, and no redo brings the edits
back. A document opened during Play goes back to how it opened. A save made
during Play stays on disk, so the reverted document then reads modified against
its file. The `play.edits` operator takes `keep` or `revert`, and switches
between them when left out.

## Several instances

A run configuration can launch more than one instance, and a project can hold
several configurations, such as a server and clients. The Play menu launches or
stops each instance on its own. The Game panel shows one instance at a time,
chosen with the instance picker in its header. The Runtime group, live values
and the Game Output window follow the instance on show. Edits reach every
running instance.

## Game output

The **Game Output** window, in the bottom dock and the Window menu, lists what
the game printed to stdout and stderr, with error and warning log lines in
their colors. It keeps the last 5000 lines of each instance, has a picker when
several instances ran, a filter box and **Clear**, and keeps a game's output
after it exits until Play launches it again. While you are scrolled up it holds
still and says when new lines wait below. The view menu in the Game panel
header opens it too. A client can read the same lines with `jackdaw/game_output`;
see [Remote control](../developer-guide/remote-control.md).

## When a launch goes wrong

The Game panel stays in front and says why:

- **Game exited**, with the exit code, when the game crashed. The panel shows
  the last lines the game printed. **Game exited before connecting** names the
  exit code of a game that quit while starting.
- **The game did not connect to the editor** when the game's app never added
  `JackdawPlugin`. Add it, with the `pie` feature of `jackdaw_runtime`
  enabled.
- **The build failed**, with a **Show build errors** button.

**Restart** in the panel launches the game that went away again, and **Show
output** opens the Game Output window. See also
[Troubleshooting](../getting-started/troubleshooting.md).
