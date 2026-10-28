# Game UI

A new game project ships with a working game interface: four screens
(start, HUD, pause, game over) that show and hide themselves, a health
bar bound to live player data, and buttons that do real things. The
screens live in `assets/hud.bsn`, a document like any other — open it
in the editor, move and restyle and rewire it, and the running game
picks your version up. This chapter covers both halves: authoring UI
on the 2D canvas, and the wiring that makes it a game's UI.

Where [Game Input](game-input.md) names the actions and
[The Player Controller](player-controller.md) drives the body the HUD
watches, this chapter covers the interface itself.

## The 2D canvas

UI is its own scene kind: **File > New Scene** and pick **UI Scene**.
The document opens on the 2D canvas — pixel coordinates from the
canvas's top-left corner, rulers and guides included — and the Add
menu grows a **UI** group: panels, rows, columns, grids, labels,
buttons, checkboxes, sliders, progress bars, tabs and the rest of the
widget set. Placement helpers cover the common cases: the layout
preset operator anchors a widget to a corner or stretches it, and
alignment snapping keeps edges tidy while you drag.

Each widget is a normal entity with normal components (`Node` for
layout, `Button`, `Text`, `Progress`, ...) plus the one that makes it
game-aware: a **`Bindings`** component. The whole deal is editable in
the Inspector — the bindings card there edits each binding with
dropdowns for the type, the fields and the event, and flags anything
that names nothing (see [When a binding is wrong](#when-a-binding-is-
wrong)).

`UiSceneRoot.reference_size` (1280×720 on a fresh canvas) is the
canvas's design basis — the size you lay out against in the editor.
Nothing scales by it at runtime; see
[Resolution discipline](#resolution-discipline) for what actually
keeps a screen correct at other sizes.

## The template's four screens

Open `assets/hud.bsn` (double-click it in the Project window) and the
structure is four overlays under one root:

| Screen | Shows when | Contents |
|---|---|---|
| `#StartScreen` | `GameState.menu` | Title + Start button |
| `#Hud` | not `menu` | Health bar, health text, pickups text |
| `#PauseScreen` | `GameState.paused` | Title + Resume button |
| `#GameOverScreen` | `GameState.game_over` | Title + Restart button |

The game side is deliberately small. `GameState { menu, paused,
game_over }` is a `Resource` of three bools, and **each screen's
`Visibility` is bound to one of them** — flipping a bool is the whole
show/hide mechanism, and the Hud screen is bound through the
registered `not` function so it is up whenever the menu is not.

Buttons say which one they are: each button's `Action` binding sends
`ScreenPressed { button: "start" }` (or `"resume"`, `"restart"`) from
its literal, and one observer turns those into behavior — leave the
menu, unpause, restart the run. The Pause *action* (Escape, see
[Game Input](game-input.md)) lands on the same `paused` bool through
`handle_pause_action`, so the key and the button agree: both doors,
one piece of state, and while `paused` the movement system stands down
(freeze the game to see it).

The health bar is the data-binding showcase. `#HealthBar` carries the
`Progress` widget and a `Field` binding reading
`PlayerHealth.current` and `.max` through the registered `ratio`
function, writing `Progress.value`; the fill's width follows that
value every frame. The two texts are `Text` bindings —
`"{} / {}"` over the same two fields, and `"Pickups: {}"` over
`PickupCount.0`. Damage comes from the world: with the physics module
the template's hazard sensors burn 15 a touch
([Physics](physics.md) has the collision-layer row that makes hazards
touch the player only), without it the Interact key does. Hit zero and
`game_over` flips, the end screen rises, and Restart — button, after
blood-out — puts the run back.

One restart semantic worth knowing exactly: Restart resets the player
(health to max, back to the spawn point, screens cleared) through the
UI observer, and with the physics module **the level comes back with
you** — surviving pickups despawn, a fresh line spawns, and the pickup
counter and any leftover velocity zero out (`respawn_pickups_on_restart`).
Without the physics module there are no pickups to reset. In both
forms a restart lands exactly where the game began.

## Wiring a binding: the five kinds

A `Bindings` component holds a list of bindings, one per behavior:

| Kind | Reads | Writes | Template example |
|---|---|---|---|
| `Field` | component fields (+ optional `via`) | a component field | bar: `PlayerHealth.{current,max}` → `ratio` → `Progress.value` |
| `Text` | fields or resource paths | the node's text, `{}` placeholders | `"{} / {}"` health text |
| `Visible` | a bool (path or `via`) | the entity's `Visibility` | each screen on a `GameState` bool |
| `Value` | a value path | a widget value | (the bar's job, done with `Field`+`as_percent`) |
| `Action` | — | fires an event on click | `ScreenPressed { button }` |

Paths read top-down: a bare `Res(my_game::GameState).paused` is a
resource; a plain `my_game::PlayerHealth.current` resolves against the
**`BindContext`** — the entity the document is pointed at. That
pointer is the one wiring line the template adds:
`wire_hud` waits for the hud document to spawn (it carries a `HudRoot`
marker) and inserts `BindContext(player)` on its root, which is what
lets every binding inside resolve the player's components.

`via` names a function **your game registers** — there is no built-in
library of them, by design. The template registers three and they are
the common shapes: `ratio` (current/max → 0..1 for a bar), `not`
(bool → inverse, the Hud screen's hide-me-while-the-menu-is-up), and
`is_zero` (the other half of the pair bar-style bindings reach for).
A `via` you forgot to register fails the binding (loudly — see below),
and the bindings card's dropdown only offers registered names.

## Resolution discipline

The four screens are correct from 800×600 to 2560×1440 (a headless
guard plays the layout at all four and asserts the geometry), and the
discipline that buys it is plain CSS-flavored restraint:

* **Percent and flex for anything position-like.** The overlays
  stretch to 100% of the window; the HUD hugs the top-left corner with
  flex and padding. Nothing is pinned to a pixel coordinate of a
  particular window size.
* **Pixels only for sizes and padding.** The bar is 180×10, buttons
  96×32, gaps 12–16 — constants that read the same at every
  resolution.
* `reference_size` is the canvas's design basis (what your pixel
  numbers were chosen against in the editor), **not** a scale factor:
  the game lays out against the real window, so a px element keeps its
  px size on a 4K screen. If you want the whole screen to grow with
  the window, express it in percent; if you want it pixel-locked, px
  is already that.

## When a binding is wrong

You get **two faces**, whichever way you break it:

* **Authoring.** The bindings card flags a binding that names nothing
  — a typoed field, an unregistered `via` — in the inspector, at the
  row, with the reason on the tooltip. The edit still commits; the
  badge is a warning, not a gate.
* **Running.** At Play a failed binding logs a warning **in the
  editor's Game panel** (the log strip at its bottom edge; failures
  also print to the game's own output in `cargo run` and exports). A
  failing binding leaves its widget at its authored value — a typoed
  health path leaves the bar full, visible and wrong, which is exactly
  why the log line names the entity and the path.

The 30-second version: open hud.bsn, change one `PlayerHealth.current`
in a binding to `currrent`, Save, Play — an orange warning appears in
the Game panel naming the path; fix it, Play again, gone.

## One editor edge

Play runs **the scene tab in front**. With a UI scene focused, the
editor's Play swaps that UI in for the 3D scene — a canvas preview
(the world's meshes are not loaded, but your UI runs its bindings
against the real game). To run the game, focus the 3D scene tab first;
the template already spawns the hud as a second root, so the normal
path needs nothing special.

## Adding UI to an older project

A project built before game UI existed needs two lines and one file.
Scaffold a fresh game and copy `assets/hud.bsn` over (renaming the
game's types inside), or author your own canvas document; in the game
plugin:

```rust
.init_resource::<GameState>()
.register_function(ratio)
.add_observer(on_screen_pressed)
// ... and at startup, after the main scene:
commands.spawn(JackdawSceneRoot(asset_server.load("hud.bsn")));
```

The runtime side — document loading, binding evaluation, widget
behavior, the dark theme — is the engine's and needs no feature flags
in any game.

## The 30-second check

1. New project, **Play**: the start screen; click **Start** — the HUD
   slides in over the 3D world. Walk into the red hazard twice (or tap
   **E** without the physics module): the bar drops, `70 / 100`,
   `Pickups: 3` when you collect the line. Blood out → the end screen;
   **Restart** → full health, spawn point, pickups back.
2. **Escape** → the pause screen and a frozen player; **Resume** →
   back. In the editor open hud.bsn, change the title and the fill's
   color, **Save**, Play: both edits are on screen, and an exported
   build ships them.
3. Break one binding path, Play: the Game panel names it in orange.
