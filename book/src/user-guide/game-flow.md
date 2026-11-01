# Game Flow

A game is more than one world: a menu to start from, the level to
play, an end screen when the run is over. A new game project ships
all three as real scene documents — `assets/menu.bsn`,
`assets/scene.bsn`, `assets/gameover.bsn` — and only one of them is
in the world at a time. Switching between them is a scene lifecycle,
not a screen toggle: the old world's entities are gone before the new
one's arrive, nothing accumulates across a menu → level → game over →
menu loop, and where the whole thing begins is a file, not a line of
code.

The overlays *inside* one world — the HUD, the pause veil — are not
this. They live in `assets/hud.bsn` and show and hide through data
bindings; [Game UI](game-ui.md) covers them. This chapter is about the
worlds.

## Where a run begins: game.flow.json

`assets/game.flow.json` is the project's game flow file:

```json
{
  "start_scene": "menu.bsn",
  "scenes": ["menu.bsn", "scene.bsn", "gameover.bsn"]
}
```

* **`start_scene`** — the scene a standalone game starts from:
  `cargo run`, an exported build double-clicked, and the editor's
  Play button (the startup-scene run) all read it. Paths are relative
  to the `assets` folder with `/` separators.
* **`scenes`** — the scene list: the scenes that make up the game,
  the editor's equivalent of a build settings scene list. It is
  optional — a file with only `start_scene` reads as a one-scene game
  — and the game itself does not enforce it (a game runs with whatever
  scenes it names in code); the list is for the editor's validation,
  the export's checks, and the human.

Every launch form reads the same file, in the same priority order:
the editor's Play-Current override (the scene in front of the editor —
see [Play-in-editor](play-in-editor.md)), then `start_scene`, then the
scene the game's code names as its own default. A game is never left
without a scene: a **missing** flow file is the quiet default (every
pre-flow project lives there, no warning), and a **broken** one — bad
JSON, a missing field, a path that is not on disk — warns on the way
down and falls back. Warnings say `game flow:` and name the path, in
the editor's status bar, in the game's own output, and in an export's
log; they never block a launch or an export.

## Setting the start scene

The Project window's right-click on a scene document offers **Set as
Startup Scene**; the current start scene's file shows a **Startup
Scene ✓** marker. The operator behind it (`game.set_start_scene`) is
the same write the QA and tooling surfaces use, and the structured
read face is the `jackdaw/game_flow` remote method (start scene, scene
list with on-disk state, current warnings). Hand-editing the JSON is
equally legitimate — the file is a content file, not editor state.

## The scene list and its validation

The editor validates the flow file when the project opens and whenever
the file changes on disk, and the two export entries (`game.export`
and `jd export`) check it before paying for a build. The checks:

* `start_scene` present, a string, a well-formed relative path;
* every listed scene on disk (a `.bsb` compiled twin counts);
* the list naming the start scene, no duplicates, no unknown fields.

Each problem is one `game flow:` warning naming the path — never a
refusal. The export goes out anyway (a warn and a shipped build beat a
blocked author), and the game falls back to the scene its code names.

## Runtime switching: states and one handle

The template's flow is a `GameFlow` state machine — a bevy `States`
enum with `Menu`, `Level` and `GameOver` — and each state's `OnEnter`
shows its document by **re-binding one scene root's handle**:

```rust
commands.entity(root).insert(JackdawSceneRoot(server.load("menu.bsn")));
```

That insert is the runtime's whole switch primitive. The runtime
despawns the old document's entities (UI roots included — a UI
document has no parent to hang cleanup on, so the runtime tracks it by
its root), keeps the root entity itself (its `Name` and markers stay —
one root serves every world), and spawns the new document when its
load finishes. Switching to a scene that is not on disk leaves
`SceneRefused` on the root and a `Cannot spawn scene '<path>'` warning
in the log; the previous scene still left, and a later switch to a
good scene recovers. Loading is per-path deduplicated by the asset
server, so a round trip re-uses the loaded document — a cycle's entity
counts land exactly where the first visit did.

The boots agree with the states: the game reads its composed start
scene once (override, then flow file, then code) and inserts the
matching state before the first frame — the menu document boots as
`Menu`, the game-over document as `GameOver`, any other scene as a
playable `Level`. A Play-Current launch swaps the editor's own scene
in as that boot scene, so a level tab focused on Play boots straight
into a playable level with the flow state agreeing with what is on
screen.

## Cameras: each world brings its own

A UI document shown alone has no camera to render it — the level's
camera is the rig under the player ([The Player
Controller](player-controller.md)), and it does not exist on the menu.
So each UI world brings its own state-scoped camera:

```rust
commands.spawn((
    Camera2d,
    IsDefaultUiCamera,
    DespawnOnExit(GameFlow::Menu),
));
```

`DespawnOnExit` is bevy_state's marker component: the entity is
removed when the named state ends. The same discipline scopes the
level's props — pickups, hazards, the falling cube — so the menu is
genuinely an empty stage and a re-entered level starts from a fresh
set. Author your own menu the same way: if a screen shows black, the
first suspect is a missing UI camera.

What the level's camera draws is the scene's own business, too: the
look the Graphics panel's Scene section authors reaches that camera
the same way it reaches Play and the exported build
([Graphics Panel](graphics-panel.md)).

## Cross-scene objects: the rules

What survives a switch is decided on purpose. The table:

| Kind | Examples | Across a switch |
|---|---|---|
| Scene members | pickups, hazards, walls, the hud, the menu's theme music, everything authored in a `.bsn` the flow moves | **Die with their scene.** The switch despawns them; the next entry starts from a fresh set (fresh entity ids). |
| Code-spawned entities | the player, its rig, anything your systems spawn | **Survive.** They belong to no scene document, so no switch touches them — the player's entity id is one and the same from Start through game over to Restart. |
| Resources | `GameConfig`, `GameState.paused`, your run state | **Survive.** What crosses gets put back in shape by hand — see below. |

The first row is why sounds start and stop without any code: a
looping theme authored in the menu document is a scene member, so the
switch to the level is its stop button ([Audio](audio.md) has the
three sounds the template ships).

The third row is the one to think about: a surviving resource is
stale state the moment its world is gone. The template's answer is
`reset_run`, running on every entry into the level: health back to
the config's number, the player back to the spawn point, the pickup
counter (with the physics module) back to zero. Because it runs on
*every* entry, Restart is not special — the end screen's Restart
button just moves the flow to `Level`, and switching **is** the reset.
Restart resets the *player*, not the *player's record*: each finished
run lands in the save file, which outlives the process entirely
([Game Saves](game-saves.md)).

Prefab instances and nested scenes follow their host scene, like any
other scene member. A mechanism for marking individual entities to
outlive their scene has no current user and is not built; the
code-spawned-entity row covers every case the template knows.

## The example game, end to end

Put the chapters together and a new project *is* a small, complete
game — and it plays as one: the whole loop has been walked on a real
machine, on a project fresh from `jd new`, from the first Play through
an exported build, without writing a line of code. The inventory, and
what each piece is for:

- **The loop.** Play: the menu — theme music, `Runs: 0`, **Start** —
  then the level: a player, a ground, two walls, three pickups, a red
  hazard, the falling cube, the HUD over it all. Every run ends on
  the same screen, by one of two doors. Walk into the hazard until
  the bar empties — that is blood-out. Or collect **all three
  pickups**: a blip sounds, the flow makes the very move blood-out
  makes, and the run is *won* on the same end screen. (A run that
  dies has at most two pickups collected — the third one ends the run
  by winning it.) **Restart** re-enters the level fresh;
  **Menu** walks back to the start screen; loop it and nothing
  accumulates.
- **The volumes.** The pause screen's three sliders — master, music,
  sfx — write `GameAudioConfig`, the save brings them back on the
  next launch, and the mix reaches sounds that are already playing
  ([Audio](audio.md)'s three-way mix).
- **The record.** Every finished run — won or lost — counts one into
  the menu's `Runs:`; the third finished run unlocks endless mode;
  and the count survives killing the process and relaunching
  ([Game Saves](game-saves.md)).
- **The package.** **Build Game...** before *and* after editing —
  retitle the menu, rewrite the HUD copy, author a config, place a
  fourth pickup, point the start scene elsewhere — and every edit
  ships: the staged game plays the loop, shows your titles and copy,
  reads your configs, and collects your placed pickup alongside the
  template's three.

### What the editor configures, and what stays code

Out of the box the game plays with zero authoring. The template's
code is not a cost — it is the shipped behavior (a new project's
`src/lib.rs` teaches every pattern it uses). What you can then change
from the editor, and where the boundary honestly sits:

| Layer | What it is | Reachable from the editor? |
|---|---|---|
| Behavior | movement, collision, pickup counting, the flow's switches, the sounds | No — template code, and yours to copy and edit |
| Scene documents | `menu.bsn`, `hud.bsn`, `gameover.bsn`, `scene.bsn` | Yes — real documents; restyle, retext, save, and the game picks it up |
| Config assets | `GameConfig`, `GameAudioConfig`, `GameInputConfig` | Yes — **New Asset** cards ([Game Parameters](game-parameters.md)) |
| Where it starts | `game.flow.json` | Yes — **Set as Startup Scene**, or edit the file |
| Placing things | extra pickups, sound sources, your own player | Yes — a supported path ([Physics](physics.md), [Audio](audio.md)) |
| The level's own props | ground, the three pickups, the walls, the hazard | No — they spawn on every level entry, unconditionally |
| Flow conditions | blood-out, the buttons, three pickups → game over | No — a binding reads a resource but cannot write one, so "when to switch worlds" is not a config |

Two boundaries worth knowing exactly:

- **Placed props add; they do not replace.** A fourth pickup placed
  in `scene.bsn` collects alongside the template's three (the count
  reads 4), and the code-spawned line spawns anyway. The player is
  the exception in the other direction — the template's spawn keeps
  an existing player rather than doubling it. The only off-switch for
  the code-spawned props is the physics module's, which takes
  collision and pickups down with it.
- **Winning is template behavior.** Both endings are systems in the
  game crate your project carries — the win arm of `collect_pickups`
  and the blood-out arm of the hazard damage. Copy and edit them to
  change what winning means in your game.

One tooling note while we are being exact: the flow state itself
(`State<GameFlow>`) is not reflect-registered, so the game-side
[remote](remote-debugging.md) channel can neither read nor write it —
which world is up is observed through the document roots (`MenuRoot`,
`HudRoot`, `GameOverRoot`), and tools watch those markers. Opening
the flow channel to BRP is filed as ticket A16.

### Running without the toolchain

The exported package needs nothing from the machine that built it:
the executable is statically linked (an export refuses a
`dynamic_linking` build rather than ship one), the whole asset tree
stands beside the executable, and the asset root resolves to that
directory when nothing else names one ([Play-in-editor](play-in-editor.md)
has the staged layout). The audit face, if you want to check rather
than trust: `otool -L` on a staged executable lists only system
libraries — no rustup, no Homebrew, no `/Users/` paths — and no
`LC_RPATH` entries; the manifest's per-file hashes re-verify a moved
or copied package file by file. The machine test behind this chapter:
copy the dist folder somewhere foreign, strip the environment down to
`HOME` and `/usr/bin:/bin`, launch from another working directory —
the menu comes up, the loop plays, and the log is clean.

Two honest edges. The shipped package has **no remote-debugging
channel**: game-side BRP is a test seam that an injection adds, so
tool-driven assertions run against the editor and injected builds,
not the shipping face ([Remote Debugging](remote-debugging.md)). And
the executable is unsigned ad-hoc, so on a Mac that did not build it
the first open is a **right-click → Open** past Gatekeeper.

## The 30-second check

1. New project, **Play**: the menu; click **Start** — the level with
   the HUD over it. Walk into the red hazard until the bar empties:
   the end screen. Or collect all three pickups: the same end screen,
   by winning. **Restart** → full health, spawn point, pickups
   back; **Menu** (end screen) → the start screen again. Loop it —
   nothing accumulates.
2. Project window, right-click `scene.bsn` → **Set as Startup Scene**
   → Play (or `cargo run`): the game now boots into the level. Set it
   back to `menu.bsn`.
3. Edit `game.flow.json` to name `ghost.bsn`, Save: the editor's
   status bar says `game flow: the start scene 'ghost.bsn' is not on
   disk...`, and the game still runs (from the code's scene). Fix the
   name and the warning clears.
