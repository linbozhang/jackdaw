# Animation

Where [The Player Controller](player-controller.md) moves a body and
[Game UI](game-ui.md) wires an interface, this chapter covers the
third half of a living game: **animation** — the clips a model plays,
the states that pick between them, and the parameters that steer the
picks. Idle, walk, jump: you author the set in the editor, preview it
on the rig in the viewport, and the game plays exactly what you saw.

That last claim is the design, not a coincidence: the state-switch
operator exists "so an authored set previews in the viewport the way
it plays in the game", and the game reads the same components you
configure — there is no export step between the two.

## First, the module

The Animation module ships **off by default** — a game with no rigs
should not pay for one. Turn it on once per project with
**File > Modules** (or `jd new --modules animation`): the editor side
(the three panels, the preview transport, the Graph window) is built
into every editor, and the module's real job is the game side — it
adds the `animation` feature to the game's `jackdaw_runtime`, which
brings the plugin that binds sets and plays states.

A scene with an `AnimationSet` opened in a project without the module
tells you so: the components show up flagged as coming from a module
that is not loaded, and a game built that way names the unregistered
types in its log instead of playing quietly. Enable the module, let it
rewrite the game's `Cargo.toml`, and the same scene plays.
([Configuration](../reference/configuration.md) has the module table.)

## The three panels

The dock's **Animation** panel (and the **Animation** workspace
preset) has three tabs:

- **Library** — every animation clip the project's glTF files hold
  (`.gltf` and `.glb`), indexed with durations and a loop hint for
  clips whose names end in `Loop`. This is the pick-a-clip surface:
  select a rig, pick a clip, **Add as state** appends it to that
  entity's animation set (creating the set if it has none).
- **Timeline** — the keyframe editor for hand-authored clips: record
  keys on a tracked field, scrub, edit times. Keys undo like any edit.
- **Graph** — the state-machine canvas. The tab opens the **Graph
  window**, a dockable window of its own; a section below.

Everything on these panels has an operator
(`animation.library.select`, `animation.panel.tab`,
`animation.graph.*`, ...), so scripts and [jd
mcp](remote-debugging.md) drive the same surfaces your clicks do.

## Two ways to author states

An entity can carry its animation either way; both play through the
same bind-and-play path in the game.

**An `AnimationSet` on the entity** — the embedded form. One component
names the glTF sources, the states (each: a clip, a source index,
`looped`, `speed`, `transition_secs`, and an optional `then`), and the
`default_state`. Pick this for a small cast: the whole performance is
one component on the rig, visible and editable in the Inspector, saved
with the scene. Switching states at runtime means writing the entity's
`AnimationState` component — the game, the editor preview, and
[BRP](remote-debugging.md) all write the same field.

**An animgraph file** — the state-machine form. The panel's Graph tab
opens a canvas: states as nodes, transitions as wires, parameters in
the strip beside. The file lands
in `assets/animation/<name>.animgraph.bsn` — the canvas draws it and
**Animation Graph Save** writes it; the scene itself only carries an
`AnimationGraphRef` pointing at the file. Pick this when behavior
belongs to the graph rather than the entity: conditions, blends, an
any-state escape hatch. `animation.graph.assign` (or the Convert-to-
graph button on a set) hands a rig to a graph file.

## Preview: the editor viewport is the game

Three ways to see motion without leaving the editor:

1. **The viewport itself.** An entity whose set is bound plays its
   current state right in the editor — change `default_state` or write
   a state and the rig moves as you edit.
2. **Clip preview.** `animation.preview` with a `file#clip` plays one
   clip on the selected rig. A rig already playing a set **lends** its
   player to the preview and takes it back when you stop, resuming its
   own state; a rig that cannot play anything gets a temporary
   mannequin so the clip still shows.
3. **The Graph window lights up.** With a rig previewing a graph, the
   canvas tints the state actually running and greens the wire of any
   crossfade in progress — you watch the machine think.

Scrubbing the timeline and seeking a preview drive the same transport.

## Loop, transition, then

- **Loop** (`looped`, or the `Loop` name hint): a looping state keeps
  playing its clip; watch it by sampling the state name across a
  longer window than the clip — it holds. A non-looping state plays
  once.
- **Transition** (`transition_secs` on a set state, `crossfade_secs`
  on a graph wire): the outgoing pose fades over the incoming one. A
  graph wire can wait for `exit_time` (a fraction of the source clip)
  and gate on conditions.
- **`then`**: the state a finished one-shot falls back to. Jump with
  `then: idle` lands and settles into the idle clip without a frame
  of scripting.

## Parameters steer graphs

A graph's parameters come in three kinds — `Float`, `Bool`,
`Trigger`. Transitions gate on them with six comparisons
(`>` `>=` `<` `<=` `==` `!=`), combined as all-or-any
(`require_all`); a 1D blend state can slide between clips along one.

Game code writes parameters, never states — which clip a parameter
reaches stays the animator's business:

```rust
use jackdaw_animation_runtime::AnimationParams;

fn on_input(mut params: Query<&mut AnimationParams>, input: Res<ButtonInput<KeyCode>>) {
    let Ok(mut params) = params.single_mut() else { return };
    params.set_float("speed", if input.pressed(KeyCode::ShiftLeft) { 1.0 } else { 0.0 });
    if input.just_pressed(KeyCode::Space) {
        params.trigger("jump");
    }
}
```

The same component is readable over BRP, as is
`AnimationGraphPlayback` — the state name, seconds since entry, and
any crossfade still running. That is the handle the four-channel
promise hangs on: what the Graph window lights in the editor is the
same `state` string a running game reports.

## When a reference is wrong

Two faces, both named:

- **Author time** — the Inspector's animation card checks every state
  and the graph reference against the Library's index, and puts a
  plain-language badge on the offending line: `animation state
  'ghost_clip' wants clip 'No_Such_Clip', and 'models/hero.glb' holds
  'Idle_Loop', 'Walk_Loop', 'Jump'` — the fix is spelled into the
  message. A graph reference naming no project file gets the same
  treatment (`no graph file named 'animation/nope.bsn' in this
  project`). Fix the row and the badge goes.
- **Run time** — the same mistakes warn in the game's log, and
  Play-in-editor pipes them into the **Game panel**: `animation state
  'ghost_clip' wants clip 'No_Such_Clip', and its source holds
  ["Idle_Loop", "Walk_Loop", "Jump"]`. The set beside a broken graph
  reference keeps playing what it can.

## Hand-editing scene text

Documents spell animation types by their definition paths. The graph
family lives in the `graph` module — `AnimationGraphRef`,
`AnimationParams`, `AnimationGraphPlayback` are
`jackdaw_animation_runtime::graph::...` in scene text — while
`AnimationSet` and `AnimationStateDef` sit at the crate root
(`jackdaw_animation_runtime::AnimationSet`). A re-export short form
fails to load: the loader matches the registered path exactly.

## Where the model comes from

A placed glTF brings its clips
([Scene Management](scene-management.md) covers placement); the
Library indexes them and a clip name is `file#ClipName`. The editor's
own test rig, `hero.glb` — three translation clips named `Idle_Loop`,
`Walk_Loop`, `Jump` in a two-node skeleton — is deliberately the
smallest legal glTF, handy as a template for a hand-made rig.

Two corners worth knowing:

- **Play-in-editor keeps the editor viewport alive**: your scene's
  sets keep playing while the game runs, and Stop hands the stage
  back. The borrowed preview player is returned either way.
- **Graph edits are undoable**, one step per edit, on the graph's own
  history — a canvas drag does not mark the scene tab dirty.

## The 30-second check

1. **File > Modules**, tick Animation, let it rewrite the game.
2. Place a rigged glTF, select it, Library: pick a clip, **Add as
   state** — the viewport plays the default state.
3. `animation.set_state` to another state: the viewport switches with
   the crossfade you configured. **Play**: the game plays the same
   states, switches the same way.
4. Rename the clip a state wants: the Inspector card badges the row
   before you ever press Play.
