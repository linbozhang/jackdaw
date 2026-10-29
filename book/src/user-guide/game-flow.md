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

## Cross-scene objects: the rules

What survives a switch is decided on purpose. The table:

| Kind | Examples | Across a switch |
|---|---|---|
| Scene members | pickups, hazards, walls, the hud, everything authored in a `.bsn` the flow moves | **Die with their scene.** The switch despawns them; the next entry starts from a fresh set (fresh entity ids). |
| Code-spawned entities | the player, its rig, anything your systems spawn | **Survive.** They belong to no scene document, so no switch touches them — the player's entity id is one and the same from Start through game over to Restart. |
| Resources | `GameConfig`, `GameState.paused`, your run state | **Survive.** What crosses gets put back in shape by hand — see below. |

The third row is the one to think about: a surviving resource is
stale state the moment its world is gone. The template's answer is
`reset_run`, running on every entry into the level: health back to
the config's number, the player back to the spawn point, the pickup
counter (with the physics module) back to zero. Because it runs on
*every* entry, Restart is not special — the end screen's Restart
button just moves the flow to `Level`, and switching **is** the reset.

Prefab instances and nested scenes follow their host scene, like any
other scene member. A mechanism for marking individual entities to
outlive their scene has no current user and is not built; the
code-spawned-entity row covers every case the template knows.

## The 30-second check

1. New project, **Play**: the menu; click **Start** — the level with
   the HUD over it. Walk into the red hazard until the bar empties:
   the end screen. **Restart** → full health, spawn point, pickups
   back; **Menu** (end screen) → the start screen again. Loop it —
   nothing accumulates.
2. Project window, right-click `scene.bsn` → **Set as Startup Scene**
   → Play (or `cargo run`): the game now boots into the level. Set it
   back to `menu.bsn`.
3. Edit `game.flow.json` to name `ghost.bsn`, Save: the editor's
   status bar says `game flow: the start scene 'ghost.bsn' is not on
   disk...`, and the game still runs (from the code's scene). Fix the
   name and the warning clears.
