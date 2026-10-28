# Game Input

Where [Game Parameters](game-parameters.md) covers a game's tuning
numbers, this chapter covers its **input actions**: named things a
game does on input — Move, Look, Jump — with bindings a project can
rebind without touching code. Systems read named actions; nobody polls
raw keys.

The template ships the whole pattern working. With no configuration at
all a game starts with five built-in actions:

| Action | Kind | Default bindings |
|---|---|---|
| `Move` | Axis2D (a held direction) | WASD, left stick |
| `Look` | Delta2D (per-frame motion) | mouse motion, right stick |
| `Jump` | Button | Space, pad South |
| `Interact` | Button | E, pad East |
| `Pause` | Button | Escape, pad Start |

A system consumes them from the `GameActions` resource, by name:

```rust
fn move_player(
    actions: Res<GameActions>,
    time: Res<Time>,
    mut players: Query<&mut Transform, With<PlayerMarker>>,
) {
    let r#move = actions.value("Move");   // Vec2, keys and stick composed
    let dt = time.delta_secs();
    for mut transform in &mut players {
        transform.translation.x += r#move.x * dt;
    }
    if actions.just_pressed("Jump") { /* ... */ }
}
```

Scale every held input by delta time, so the same input covers the same
ground at any frame rate. The template's own `move_player` is the full
controller this grows into — camera-relative movement, a jump, and
(with the physics module) a swept capsule that slides along walls;
[The Player Controller](player-controller.md) covers it chapter-length.
The sample above is the minimal shape, and `Look` is the one action the
controller consumes indirectly: it writes the camera rig's look state
(`CameraLook.yaw`), which movement is measured against — the player
body itself never turns on look.

The template's Pause consumer is the [game
UI](game-ui.md): `handle_pause_action` flips `GameState.paused`, the
movement system stands down while it holds, and the pause screen's
`Visibility` is bound to the same bool — one press pauses the game and
raises the screen, and the Resume button lands on the same state.

## Rebinding is editing one file

Bindings live in an asset, `assets/input-actions.bsn`, authored the
same way as any [config asset](game-parameters.md): the type is
registered in the game's plugin, and after a Rebuild **Project
window > New Asset...** offers **Game Input Config**. Edit the bindings
on the card — each binding is a variant (key, mouse button, mouse
motion, gamepad button, gamepad axis with its deadzone) — then
**Save**. The next Play, `cargo run`, and an exported build all read
the same file; until it exists, the built-in table stands.

An action the file names is replaced wholesale — its kind and its
whole binding list come from the file. An action the file **omits**
keeps its built-in default, so a file written against an older game
still receives actions the game adds later, and a new game with an old
rebinding file needs no migration. (The reverse trap — a file that
freezes every action forever — is why the merge is a union, not a
replacement.)

## Deadzones ride the engine

A gamepad-axis binding carries its own deadzone. The plugin copies it
into the engine's per-axis `GamepadSettings` before events are
filtered, so the value a game reads is already deadzone-filtered —
your code, the action system, and any other axis reader all see the
same number. The default table's sticks use 0.15, which matches the
engine's own default: an axis you have not configured behaves the same
as one you have.

Gamepads are read directly by the **game's own process** — the editor
neither sees nor forwards them, so a pad works identically in Play, in
`cargo run`, and in an export. Any connected pad drives the actions
(buttons union across pads; an axis reads the pad with the largest
deflection).

## Keyboard focus and the editor's own keys

While the Game panel has [input
capture](play-in-editor.md#playing-the-game), keyboard and mouse
forward to the game and the editor's own bindings are suppressed —
WASD moves the player, not the viewport camera, and a plain `Esc`
reaches the game (that is why `Pause` can be Escape). `Shift+Esc`
gives control back.

The two key maps never meet: the editor's shortcuts live in your user
keymap (outside the project), the game's actions in
`input-actions.bsn` inside it (and in every export). Giving the game
the editor's key, or vice versa, cannot collide — they are different
streams with different storage, and what ships with the game is only
ever the action table.

## What a rebind does not do

A rebind takes effect on the **next Play** — the file is read at
startup, not hot-swapped in a running game. Stop, Play, and the new
table is in force; that is the whole workflow, and the 30-second
version is:

1. Play, click the game image, and drive the defaults — WASD, mouse,
   Space, E, Esc (and a pad, if you have one).
2. Rebind Move to the arrow keys on the card, Save, Play again: the
   arrows walk, W does not.
3. Push the pad stick a little: nothing (deadzone). Push it more: it
   walks.
