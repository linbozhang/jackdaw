# Physics and prop placement

Jackdaw uses [avian3d](https://github.com/Jondolf/avian) for
physics, through the Physics module — **on by default** for new
projects (File > Modules can turn it off). The module's editor
extension (`jackdaw.physics`, from the `jackdaw_physics` crate) brings the tools on this page; the
game adds `avian3d` and `jackdaw_avian_integration`. Without the
extension, scenes keep their physics components and the
inspector shows them as components from a module that is not
loaded.

There's no global "enable physics" toggle: you opt an entity in
by adding the components it needs, and the Physics Tool lets you
drop dynamic bodies into the scene and let them settle.

## Adding physics to a brush or entity

A physics-enabled entity needs two things:

- `AvianCollider`: jackdaw's wrapper around avian's
  `ColliderConstructor`. Picks the collider shape (cuboid,
  sphere, trimesh-from-mesh, etc.) and rebuilds the actual
  `Collider` whenever you change it.
- `RigidBody`: dynamic / static / kinematic. Dynamic bodies
  fall under gravity; static bodies are immovable collision
  surfaces.

Workflow:

1. Select the brush (or any entity with a mesh).
2. Components panel: click **Add Component**.
3. Search "AvianCollider" and pick it (it lives under the
   **Avian3d** category).
4. A collider with no `RigidBody` on its entity or above it
   stands as a static body, in the editor and in the game. Add a
   `RigidBody` and pick `Dynamic` or `Kinematic` for a body that
   moves. **Enable Physics** adds both, with a `Static` body.

The collider builds from the entity's geometry on the next
tick. For brushes, jackdaw triangulates the brush faces and
hands them to avian. For mesh entities (`Mesh3d`), avian
reads the loaded mesh asset.

You'll see the green wireframe overlay on the brush once the
collider is up. If you don't, the collider build failed
silently; check the brush has finite volume.

### Switching collider shape

`AvianCollider` is a single-field tuple struct holding a
`ColliderConstructor`. The Components panel renders it as an enum
dropdown. Common picks:

- `Cuboid` / `Sphere` / `Capsule` / `Cylinder` / `Cone`:
  primitive shapes, parameters are the half-extents / radii.
- `TrimeshFromMesh`: builds a triangle mesh collider from
  the entity's mesh. Best for brushes and detailed props
  where shape fidelity matters; expensive for rigid bodies.
- `ConvexDecompositionFromMesh`: V-HACD decomposes the mesh
  into convex hulls. Use for dynamic props where trimesh
  isn't valid.

Trimesh colliders are static-only in practice (avian rejects
trimesh colliders on dynamic bodies). For dynamic props, use
a primitive or convex decomposition.

### Static level geometry

Platforms, walls, and floors need only a collider: without a
`RigidBody` they stand as static bodies. Static bodies don't
fall, can't be moved by forces, and serve as the collision
surface other bodies land on. New brushes and **Enable Physics**
author `RigidBody::Static` explicitly.

## Sensors and triggers

A **sensor** is a collider that detects overlaps without blocking
anything: nothing lands on it, nothing is pushed by it. Add
`Sensor` (Components panel, **Avian3d** category) to an entity
that already has an `AvianCollider` — the editor draws a sensor's
outline in cyan, so a trigger is recognizable at a glance.

The game reads triggers from the `TriggerEvents` resource. Each
frame it lists every contact that just started or stopped:

```rust
use jackdaw_runtime::prelude::TriggerEvents;

fn my_trigger_system(triggers: Res<TriggerEvents>) {
    for contact in triggers.enters() {
        // `contact.trigger` is the sensor entity, `contact.other`
        // is what touched it, `contact.phase` says Enter or Exit.
    }
}
```

The template wires this up with one plugin line
(`jackdaw_avian_integration::TriggerPlugin`) and one working
example: three glowing sensor cubes, a counter component on the
player, and a system that despawns a pickup and counts it when
**the player** walks into it — collect all three and the level
clears. The event prerequisite avian asks for
(`CollisionEventsEnabled`) is added automatically with the
`Sensor`; author the sensor, nothing else.

The pickup pattern in one paragraph: spawn a small collider with
`Sensor` and a marker of your own, read `triggers.enters()`, match
on your marker, despawn, count. `exits()` is the same list for
contacts that just ended — the "left the area" half of triggers.

## Collision layers

Who interacts with whom is a `CollisionLayers` component: two
bitmask fields, `memberships` (the layers this body belongs to)
and `filters` (the layers it interacts with). A contact only
exists when each side's memberships meet a layer the other side
filters in — both directions must agree.

Bits are yours to assign. A common table:

| Layer | Bit | Typical residents |
|---|---|---|
| 1 | `0b001` | the player, the world |
| 2 | `0b010` | pickups |
| 3 | `0b100` | hazards |

Give hazards `memberships 0b100, filters 0b001` (a hazard touches
the player only) and the player `0b001, 0b111` (touches
everything): pickups and hazards never interact, so a drifting
hazard cannot collect the pickups for the player. Layer masks
edit as numbers in the Components panel and round-trip through
save and reload unchanged.

The template's hazards do real work through exactly that row:
`hazard_damage` burns 15 health per touch, and the HUD's health
bar and text are bound to the same `PlayerHealth` the sensor
writes — [Game UI](game-ui.md) covers the screen side.

One engine boundary worth knowing: the broad phase pairs bodies
when they enter the simulation. Re-layering a body that then
stays perfectly still may not re-pair it until something moves —
when a layer change must take effect on a still scene, nudge the
body or re-enter Play.

## Physics Tool: dropping props into place

Once entities have colliders, you'd usually want to author
their resting positions by simulating instead of guessing
poses. That's what the Physics Tool is for.

### Workflow

1. Select the props you want to place (one or many).
2. Press `Shift+P` to enter the Physics Tool.
3. The status bar reads `Physics Tool | drag selected to
   release | Space commit | Esc cancel`.
4. Click and drag a selected entity. Release. Gravity takes
   over and the body falls / settles.
5. Drag again to nudge.
6. Press `Space` (or `Enter`) to commit and exit. Settled
   positions are pushed onto the undo stack as a single entry,
   so `Ctrl+Z` puts the bodies back where the tool found them.
7. `Esc` instead of `Space` cancels and reverts to the
   pre-tool poses.

### Selected vs non-selected

The tool only simulates the **selected** entities. Every
other dynamic / kinematic body in the scene gets paused
(`RigidBodyDisabled`) so it acts as a static obstacle while
the selection settles. Static bodies are always solid; the
tool never disables them.

This is the key UX: select what you want to place, ignore
the rest, drop them in. Re-select a different group to
place that one without disturbing the first.

### Visual cues

- Green wireframe: collider visible while a body is around.
- Orange: collider visible on a selected body.
- Cyan / blue: a sensor.
- Hierarchy arrows (toggle in `View` menu): show the body
  to collider parent / child links.

These are the **editor's** overlays, and they are the debugging
surface while you compose. The game itself runs without them: the
physics the template adds has no debug renderer by default, so a
Play window or an exported build shows only the game's own
visuals. If you ever want collider wireframes in the game's
picture, add avian's `debug-plugin` feature to your game's avian
dependency and rebuild.

## Two gravities, one number

Two things called gravity exist and they are different things:

| What | Where it lives | An edit takes effect |
|---|---|---|
| `GameConfig.gravity` (the [config asset](game-parameters.md)) | `assets/game-config.bsn` | next launch — Play, `cargo run`, and exports all read the file |
| the engine's `Gravity` resource | the running simulation | immediately, for the running session only (Resources panel) |

The template connects them in one direction: at startup (and
whenever the config reloads) `apply_gravity_from_config` copies
the config's number into the engine's resource. The file is the
author's truth; the resource is what the simulation reads. Editing
the file changes the next launch; tweaking the resource in the
Resources panel is a live experiment that evaporates when the
game stops.

## The template's physics demo

A new game starts with the whole pattern working (the physics
module is on by default; turn it off in **File > Modules** and
the template falls back to a physics-free shape):

- A **falling cube** — a dynamic body that drops onto the stage
  and settles. It is the "does physics work" canary: press Play
  on a fresh project and it lands, it doesn't sink.
- **Three pickups** — small glowing sensor cubes in a line. Walk
  the player into one and it despawns, the player's `PickupCount`
  goes up, and the third one logs "Level clear!". A cube merely
  landing on a pickup does not collect it — only the player's
  touch counts.
- A **player with a body** — a kinematic capsule collider whose
  movement the [player controller](player-controller.md) sweeps
  through the world (`move_and_slide`: walls stop it, diagonals slide
  along), that detects sensors, and is not pushed around by falling
  props.

The template's doc comment at the top of `src/lib.rs` walks the
same pattern in code: colliders, triggers, layers, and the two
gravities, each with the one line that makes it work.

## The 30-second check

1. New project, press Play: the cube drops, bounces once, rests
   on the ground — through the floor is a bug, not a feature.
2. Walk the player over a glowing pickup: it vanishes, the count
   goes up (cyan outline = trigger).
3. **Build Game...** and double-click the export in `dist/`:
   the same pickups, the same physics, the same fun.

## Common gotchas

- **Dynamic body falls through the floor.** The floor
  entity has no collider, or its `RigidBody` is not `Static`.
  Add `AvianCollider` to the floor, and remove its `RigidBody`
  or set it to `Static`.
- **Collider wireframe is the wrong shape after rescaling.**
  The wireframe tracks scale gizmo edits. If you still see drift, file an issue
  with the collider type and the resize gesture.
- **`ColliderConstructor` panic when added directly.**
  Picking the raw `ColliderConstructor` (not `AvianCollider`)
  on an entity without a `Mesh3d` panics avian's auto-init.
  The picker hides standalone `ColliderConstructor` for this
  reason; pick `AvianCollider` instead.
- **Body can't be selected in physics mode.** Selection
  works the same as Object mode (LMB-click). If clicks land
  on the wrong body, check the cursor is over the body's
  collider, not just its visual mesh.
- **Body doesn't move when I drag.** The first drag in a
  physics session unpauses `Time<Physics>`; if your drag is
  too short to clear the threshold, the sim never starts.
  Drag a few pixels.
