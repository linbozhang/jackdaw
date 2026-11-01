# Open challenges

Work that is unfinished, partly done, or hard. Nothing here is
shipped. If you want to take a swing at any of it, please file
an issue first so the approach can be talked through.

## Windows dylib hardening

The editor loads extension code as dylibs built against its SDK
proxy. On Windows, a PE export table addresses its entries with a
16-bit ordinal, so 65,535 is the ceiling and no linker escapes it.
Builds split the runtime into `bevy_dylib` and `jackdaw_dylib`
beside the SDK facade, so each library has its own table. Measured
on the current split, the hottest table is `bevy_dylib` (~46k
exports in the workspace debug profile, ~41k in release); the
Jackdaw runtime and the facade are a few thousand and a handful
respectively. The release job measures every table and fails above
60,000. Two gotchas the split codified: LTO stays off for Windows
binaries, because a PE file cannot import data across a DLL
boundary once inlining creates direct references to another
library's statics, and the SDK build disables incremental codegen,
which otherwise leaves undefined hidden symbols across the dylib
boundary.

What remains is headroom and those link-model gotchas: Bevy's
export surface grows with the engine, and a regression that merges
the runtimes again (or drops the split on one profile) would put
Windows back against the ceiling.

Where to dig in: keep the release export check green, and watch
`bevy_dylib`'s count when bumping Bevy or widening what extensions
share.

## Play-In-Editor (PIE) depth

PIE is the "click play to run your game" flow. The process model
is settled: the game always runs out of process as its own cargo
binary over IPC, with zero play-time compilation once built. Frame
streaming into the Game panel, input capture, click-to-select
picking, and the Live entity tree all shipped; see
[Play-in-editor](../user-guide/play-in-editor.md).

What's not done: deeper live editing (a broader set of
component edits riding back into the running game and into the
authored scene), richer widget metadata for live values, and
protocol maturity across more component types. Five smaller
ledgers from the input-actions and physics work (2026-10): the
schema watcher only fires on `schema.json` changes, so a restart
into an unchanged schema can serve New Asset before its kinds
land (an initial read on project open would close it); the game's
own log lines have no editor-visible surface (its stderr feeds a
crash tail buffer only — a log pane would make a teaching
template's `Jump!`/`Pause!` lines observable in PIE); stop still
closes open asset cards on some paths (the post-stop re-open
works, the close calls are the residue); the physical-gamepad
end-to-end leg has never run on hardware (the mechanism is
pinned — the game's own GilrsPlugin reads pads directly, and the
synthetic event chain is red-green tested — but no pad was ever
attached to this machine); and the version-pinned bevy fork the
physics integration patches to is a path on the machine that
built it — CI (and any collaborator) breaks until the fork is
hosted or upstream resolves the source split, which is where the
fix belongs.

Where to dig in: pick one component family that doesn't
round-trip yet and follow it through the IPC lanes.

## Upstream BSN alignment

Jackdaw's scene document is BSN: `.bsn` files are the authored
format, the live in-editor document is the BSN AST, and `.jsn`
survives only as a read-only importer. What remains is staying
aligned with the upstream Bevy scene work as its APIs settle,
and upstreaming the pieces of jackdaw's writer that make sense
there.

Where to dig in: track the upstream scene-notation APIs and
diff them against `crates/jackdaw_bsn` as they move.

## Engine-feature gaps

Compared to other game engines, jackdaw is missing a bunch.
None of these are blockers; they're places where someone with
taste in the area could lead. One line each:

- Animation graph editor. The authoring-and-game loop is closed:
  clips, states, transitions, and parameters round-trip from the
  editor's panels into a running game
  ([Animation](../user-guide/animation.md)). The open depth is
  retargeting between rigs and richer blend shapes beyond the 1D
  blend.
- Particle / VFX editor. Not started.
- Material graph editor (shader-graph style). Not started.
- Light baking and lightmap pipeline. Not started.
- Cinematics / cutscene editor. Not started.
- Audio mixer. Not started.
- Localization (i18n). Not started.
- In-editor profiler / frame-time inspector. Not started.
- Named collision layers (layer names over the `CollisionLayers`
  bitmask, so authors pick "hazard" instead of counting bits).
  The bitmask and its editing work; the naming is the gap. Not
  started.
- Asset import beyond GLTF (FBX, USD, batch texture
  compression). The common families are in — images (PNG/JPG),
  GLTF/GLB, materials, audio — with import options, hot reload
  and failure feedback ([Assets](../user-guide/assets.md)); the
  open tails are FBX/USD, explicit sRGB overrides and
  per-texture flips beyond the filename heuristics, decode for
  mp3/flac, a game-side dev hot-reload module (the template
  ships without the file watcher), and the compressed-texture
  face that stops following reloads. Not started.
- Level streaming for large open worlds. Not started.

If you care about any of these, opening a small "here's what
I'd do" issue is the best starting point.

## Asset processing pipeline

Asset processing happens only at editor runtime. To pre-process
textures or bake meshes for a CI build, you have to start the
editor headlessly.

The second shape below is half built: `jd` drives the editor's
build machinery from a terminal with `build` and `run`. What is
missing is a `process` step and the asset-processing pipeline
behind it. The remaining shapes:

- Split the user's game into a library plus multiple binaries
  (run, process), with processing driven from the project's own
  binaries. Invasive for the project template.
- Extend `jd` with a `process` subcommand alongside
  `build`. Less invasive but more code in jackdaw.

Where to dig in: pick one shape and prototype it against a
small game. We'd like to see the workflow before locking in
the design.

## Single-entity editor-only ergonomics

`EditorOnly` skips the whole entity from save, so to have a
`PlayerSpawn` marker that ships and a visual indicator that
doesn't, you author a parent (with `PlayerSpawn`) and a child
(with `EditorOnly` + a mesh).

A single entity cannot carry both, because the save filter is at
entity granularity. An `EditorOnlyVisuals` marker that strips
visual components (`Mesh3d`, `MeshMaterial3d`, etc) at save time
but keeps the entity and its non-visual components would enable
single-entity authoring. The cost is a small allowlist of
"visual" component types that grows as bevy adds new ones.

Where to dig in: design the allowlist, file an issue, then
implement. The semantics are harder than the code.

## Brush face children as a custom relationship

Each brush spawns N face child entities for rendering. They
carry `EditorHidden` (so they're not in the outliner) and
`NonSerializable` (so they're not in the save). But
`Children` queries on the brush still enumerate them, which
means user code that walks brush children sees jackdaw's
implementation detail.

A custom Bevy relationship (not `ChildOf`) for face entities
would solve this. The face entities would be reachable
through the relationship but invisible to standard `Children`
queries. The cost is a small per-frame propagation system that
reads the brush's `GlobalTransform` and writes the face's.

Where to dig in: the relationship API in Bevy 0.19, and
whether this can be done without breaking `BrushFaceEntity`
queries that already work.

## A material override on a part of a model

The Material row on the inspector writes a handle onto the
entity it is showing. When that entity is a part of a loaded
glTF, the scene document has no node for it: the model file is
the whole of what the document says about the instance, and the
parts under it are spawned by the loader. So the row falls back
to `wear_until_reloaded`, which swaps the handle on the live
entity, mints an undo entry, and warns that the pick is kept
only until the model is loaded again. Reopening the scene brings
back the material the glTF names.

What the document is missing is a way to address a part. The
shape that fits the rest of the format is a path of node names
from the model root -- the `Name` each glTF node is spawned
with, joined by `/` -- carried by a component on the entity that
holds `GltfSource`, so one entity's overrides sit in one patch
under the node the document already has:

```text
jackdaw_scene_types::types::GltfSource { path: "models/town.glb", scene_index: 0 }
jackdaw_scene_types::types::ModelPartMaterials {
    parts: map[("Roof/Tiles", "materials/slate.bsn")],
}
```

Four pieces make it work. A component of that shape, registered
and reflected like the rest of `jackdaw_scene_types`. A walk
that turns an entity under a model instance into its path of
names, and the reverse walk that finds the entity a path names.
An observer on the spawned instance that re-applies every
override once the model's entities are there, which is the same
moment `WorldAssetRoot` is derived, and again whenever the file
changes on disk. And a writer on the Material row that, for an
entity with no node of its own, walks up to the model root and
writes the entry rather than wearing the handle.

The parts that need care are the ones that decide whether it is
worth having. A name is not unique in a glTF, so two nodes
called `Tiles` under different parents are told apart only by
the path above them, and a model with two identical siblings is
not addressable at all -- the override has to refuse that case
rather than pick one. A model that is re-exported with renamed
nodes leaves entries naming nothing, which wants the same
"names nothing the project holds" reporting a missing asset
path gets rather than a silent drop. Undo has to take the
document entry and the live handle together. And the row has to
read the override back, so what it shows after a reload is the
path the document holds rather than the material the glTF
names.

Where to dig in: the name-path walk and its refusal on
ambiguous siblings, which is where the design either holds or
needs a stable per-node id from the loader instead.

## Pointer-delta gate headroom

Every frame's accumulated pointer motion passes a gate
(`drop_synthetic_pointer_jump` in `src/input_contexts.rs`) that
drops the whole frame's delta when it exceeds
`MAX_PLAUSIBLE_POINTER_DELTA`, 1000 px per frame. It exists
because the pointer stack itself lies: RDP sessions and some
vendor drivers re-anchor the cursor around a grab transition and
report 37k-850k px in a single frame, which fed straight into the
camera is the "the view snaps when I right-click" report. The
gate is measured against that observed population (remote-desktop
and vendor-driver sessions, measured 2026-10-23 on real hardware).

The gate judges the frame-accumulated sum, after the per-event
deltas are folded, and it drops rather than clamps -- a clamp
would still turn the view by the clamp bound. That choice has two
known corners where a real gesture can be dropped whole:

- High-DPI fast swipes. At 800 DPI a 1 m/s swipe is ~525 px/frame
  at 60 fps (safe); at 1600 DPI and 2 m/s it is ~2100 px/frame,
  past the gate. Hardware that fast is unusual for editor work,
  but not impossible.
- Hitch-frame backlog. Because the sum grows with frame time, a
  200 ms hitch that batches a merely moderate swipe accumulates
  on the order of 1300 px into one frame, past the gate -- and
  the drop is not recovered afterwards.

For calibration, the safe side of the line: a normal editor swipe
(0.25 s across a 2560 px screen at 150% DPI) is ~171 px/frame,
5.8x under the gate; an aggressive full-screen flick (0.1 s) is
~427 px/frame, 2.3x under. A measured 600 px/frame drag releases
cleanly, and a single 50000 px synthetic jump is dropped whole --
both ends verified live against the editor build. Any threshold
change should keep both of those pinned.

If the corners above start mattering, the candidate shapes are:
gate each event before the fold (a backlog of small real deltas
then sums through), or scale the threshold by the frame duration
so a hitch frame does not shrink it. Clamping is not on the table
-- it reintroduces the press-snap this gate fixed.

Where to dig in: `src/input_contexts.rs`
(`MAX_PLAUSIBLE_POINTER_DELTA`, `drop_synthetic_pointer_jump`)
and the constant's doc comment, which records the measured
background.

## Example-game orchestration edges (T20)

The template ships a complete example game (menu → level → two
endings → restart, with audio and saves), and T20 verified the whole
chain live including a pure-package export that runs with an empty
environment. Two edges are recorded as designed boundaries rather
than defects:

- Level props are code-generated and the editor can only add to
  them, not replace them (`collect_pickups` guards the player but
  props have no such guard). Moving a level to fully authored props
  is a template-extension exercise, not an editor gap.
- The Gatekeeper right-click opening on first launch of an exported
  pure package (EG6) is macOS policy, not an editor defect; the
  in-app right-click path is the supported route.

Where to dig in: `loop/plans/t20-example-game.md` (the degree table
and the M12/M13 isolation evidence).

## Sprite draw-order surface (T21)

A sprite's draw order is its `Transform.translation.z` (small z
draws first); the editor exposes it through the Inspector's bare z
field, the move gizmo, and the one rule that a newly added sprite
lands one above the scene's highest sprite. What a 2D-heavy project
will eventually want is thicker: a sorting panel that lists sprites
by z with drag-to-reorder, and a Y-sort mode (siblings drawn by
their y position, the standard for top-down character layers) --
neither exists upstream either; the upstream sprite suite deferred
ordering to its own issue. The z field satisfies the "editable"
letter of the current acceptance; the panel and Y-sort are recorded
here so they are not mistaken for defects.

Where to dig in: `bevy_sprite_render`'s extraction (the sort key)
and the editor's Add/transform surfaces (`src/sprite_ops.rs`,
`src/sprite_gizmo.rs`).

## The Add menu's 3D groups in a 2D scene (T21)

The Add menu shows its 3D-furniture groups (3D Objects, Lights,
Cameras, ...) in every scene, 2D world scenes included. Adding a
Cube to a 2D scene does not error; the entity is real and the
Inspector edits it, but the scene's Camera2d cannot draw it, so the
canvas shows nothing and the confusion is the bug-shaped part. The
upstream sprite work that added the 2D group deliberately left the
3D groups alone. Hiding (or moving the 3D groups behind an
"advanced" affordance) when a `Scene2dRoot` is open is the candidate
shape, and belongs with whatever round next touches the Add menu.

Where to dig in: `src/creation_taxonomy.rs` (the group collection
and the `two_d()` group that already gates on the open scene).
