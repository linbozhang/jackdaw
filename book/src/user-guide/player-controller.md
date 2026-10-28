# The Player Controller

Where [Game Input](game-input.md) names the actions and
[Physics](physics.md) simulates bodies, this chapter covers the thing
that joins them: the **player controller** — a character that walks,
turns, jumps, collides with walls, and is followed by a camera. A new
game project ships one working; Play it and you are standing on the
stage in three seconds.

Three channels, one behavior: the editor's **Play**, a plain
`cargo run`, and an **exported build** all run the same binary over
the same scene, so what you tune in the editor is what ships.

## The five pieces

`move_player` in the template queries five components together. An
entity carrying all of them is a driven player; an entity missing any
one of them does not move at all — not even gravity reaches it:

| Component | What it is | Who writes it |
|---|---|---|
| `PlayerMarker` | "the actions drive me" tag | You (or the template's spawn) |
| `PlayerController` | The tuning: `move_speed`, `jump_speed` | You |
| `PlayerVelocity` | Per-frame velocity, starts all-zero | You when hand-placing; the system owns it after |
| `RigidBody` = `Kinematic` | Physics takes no liberty with the player | You |
| `AvianCollider` (capsule 0.35 × 1.0) | The shape that sweeps against walls | You |

The template's own player is spawned complete (with a visible capsule
mesh). Hand-placing one is the same list — see
[Placing your own player](#placing-your-own-player).

Movement is **camera-relative**: W walks away from wherever the camera
looks, and the body turns to face the way it moves. The one source of
truth for "which way is forward" is the camera's `CameraLook.yaw`;
the player transform never stores a look direction.

## The follow camera is a child

The template's camera is a `CameraRig` parented under the player —
parenting is the whole setup. The runtime plugin the template wires
activates a lone rig by itself and drives it around its parent every
frame; no camera code exists in the game.

The rig is a component, so its knobs are on the Components panel:

| Field | Default | What it does |
|---|---|---|
| `mode` | `ThirdPerson` | `ThirdPerson` orbits at `distance`; `FirstPerson` sits at `eye_height` |
| `distance` | 10.0 | Orbit radius (third person) |
| `pitch` | 0.4 | Orbit height angle, radians |
| `eye_height` | 1.2 | Eye offset above the parent (first person) |
| `sensitivity` | 0.005 | Radians of turn per pixel of look input |

**Two rigs, no camera.** The auto-activation is a lone-rig
convenience: author a second rig and *neither* self-activates — the
game must choose. Add an `ActiveCameraRig` component to the one you
want (a marker you can add in the Components panel and save with the
scene; at Play it activates that rig). This is the multiplayer-gate
design: with several rigs in the world, activation is a decision, not
a default.

**Look has two channels that agree.** The `Look` action writes the
rig's `CameraLook` every frame; while the right mouse button is held,
the rig's own mouse-look owns the turn instead and the action bridge
yields those frames — the two never double-write one turn.

## Jump and collision

Jumping is one line of tuning and a ground check: `Jump`
just-pressed plus a short downward cast that finds ground not too
steep launches at `jump_speed`; a press mid-air does nothing, and
landing is stable and re-jumpable.

Collision is avian's `move_and_slide`: each frame it sweeps the
capsule as far as the way is clear, **slides along** whatever is in
the way, and pushes back out of anything already penetrated. Walk
into the stage walls to see it — head-on you stop, diagonally you
slide. (The character-controller tools are documented in avian's own
character-controller chapter.)

Gravity comes from `GameConfig.gravity` — the same number
[Game Parameters](game-parameters.md) authors and the same one the
engine's own simulation got at startup. One value, both consumers.

## Placing your own player

The whole chain in the editor, each step on the panels — this is the
five-component list from above in order:

1. **Add Entity** a Cube or Capsule where the player should stand.
2. Add Component — five, by fully-qualified name (the picker offers
   your game's types after a Rebuild):
   - `my_game::PlayerMarker`
   - `my_game::PlayerController` (then set `move_speed`/`jump_speed`)
   - `my_game::PlayerVelocity` — leave the value at zero
   - `avian3d::dynamics::rigid_body::RigidBody` = `Kinematic`
   - `jackdaw_avian_integration::AvianCollider` — a Capsule of
     radius 0.35, height 1.0
3. **Add Entity > Camera Rig**, then drag it under the player in the
   Hierarchy (parenting is the follow).
4. Give the world a floor: a cube scaled flat, then
   [enable physics](physics.md) on it (a static body).
5. **Play** — the entity walks, jumps, stops at walls, and the rig
   follows.

Step 2 is where an omission bites silently: the entity needs **all
five** — one missing and nothing drives it (it will hang in the air,
not even falling). Without the physics module the set is two
(`PlayerMarker` + `PlayerController`): the walk still works,
camera-relative and frame-rate-correct, but there is no jump and
nothing stops the player.

## Tuning is on the entity

Player numbers live on the player, camera numbers on the rig — both
are components, edited in the Components panel, saved with the scene,
and read again identically on the next open. The template's split is
the rule: **per-entity numbers are components; game-wide numbers are
the config** — the player's speed is a component, the world's gravity
is `GameConfig`.

Editing is live: change `move_speed` while selected, Play, and the
walk is measurably faster; set `distance` to half and the camera
halves its orbit. Save, reopen, and both are where you left them.

## Adding a controller to an older project

A project built before the controller existed gets the **authoring
side for free** after a Rebuild: `CameraRig` and `ActiveCameraRig`
appear in the picker, can be placed and saved. The **running side**
is one line — in the game's plugin:

```rust
app.add_plugins(JackdawCameraRigPlugin);
```

Without that line the placed rig is a stored component that never
drives; with it, the same scene follows. The controller components
(`PlayerController`, `PlayerVelocity`) come from *your* game crate —
copy the template's player section, or scaffold a fresh game and
move your scenes over.

## The 30-second check

1. New project, **Play**: a capsule player — WASD walks, Space jumps
   (and jumps again after landing), walking into a wall stops you
   (diagonally, slides), the camera follows every turn.
2. Select the player, set `move_speed` 8.0; select the rig, set
   `distance` 4.0. Play again: visibly faster, visibly closer. Save,
   reopen — both numbers held.
3. Place your own: a Cube with the five components and a rig under
   it, on a physics-enabled floor — Play, and it plays.
