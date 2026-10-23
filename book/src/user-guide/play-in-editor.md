# Play-in-editor

Play-in-editor (PIE) runs your game as a real process and streams its
frames into the editor, so you can play, inspect, and live-edit a running
build without leaving jackdaw. The game runs in its own process, so a
crash takes down the game, not the editor.

PIE keeps two surfaces strictly separate:

- The **Game panel** is a pure monitor of the running game's frame.
- The **Viewport** is always an editing surface for the authored scene.
  It never composites the game frame over your scene.

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

The Game panel header has a **Play | Select** mode bar.

In **Play** mode, click inside the panel to engage input capture (or use
the **Play Input** header button). While captured:

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

## Selecting entities from the frame

Switch the mode bar to **Select**. Game input stops, and the cursor becomes
a picker over the streamed frame.

- Click an object in the frame to select it. The selection appears in the
  outliner's **Live** tab and the Components panel shows its live values.
- Picking reads the real frame through the game's own camera, so it needs
  no alignment and reaches runtime-only entities (the player character,
  spawned props) that have no authored counterpart.
- The game draws a bounding box around the picked entity, and the Live tree
  expands to reveal the selected row.
- Selecting a row in the Live tree moves the box to that entity.

Menu and UI elements are not pickable; they are not streamable scene
entities.

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

## Stopping and reloading

- **Stop** ends the game process. The Game panel returns to its idle state,
  the panel that was in front before Play comes back, and the **LIVE** badge
  clears.
- **Reload** relaunches with the current window-mode setting, which is how
  you apply a change to the **Embedded** / **Windowed** button.
