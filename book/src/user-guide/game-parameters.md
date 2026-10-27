# Game Parameters

A game's tuning numbers live in three places, each with its own
lifetime and its own way in:

| What | Where it lives | Lifetime | Edited by |
|---|---|---|---|
| A per-entity number (one cube's spin speed) | a component on the entity | saved with the scene | Components panel |
| A game-wide number (gravity, move speed, player health) | a **config asset** — a small file under `assets/` | saved as its own file; Play, `cargo run` and an exported build all read the same one | New Asset / the asset's card |
| A knob for right now (dim the ambient light while composing) | the editor's session resources | this editor session only; gone on close | Resources panel |

The Resources panel is the debug surface and says so on its face:
**its edits are not saved**. When a value should ship with the game,
it belongs in a config asset.

## Creating a config asset

A game declares the type once — both an `Asset` (so the editor can
author files of it) and a `Resource` (so systems can read it):

```rust
#[derive(Asset, Resource, Reflect, Clone)]
#[reflect(Resource, Default)]
pub struct GameConfig {
    pub player_health: f32,
    pub move_speed: f32,
    pub gravity: f32,
}
```

registered in the game's plugin, with the one line that turns the
file into the resource's starting value:

```rust
app.init_asset::<GameConfig>()
    .register_asset_reflect::<GameConfig>()
    .add_plugins(ConfigPlugin::<GameConfig>::default());
```

After a Rebuild, the type appears in **Project window > New Asset...**
— create it, edit the fields on the card, **Save**. The file (the
template names its `game-config.bsn`) lands under `assets/`, and the
next Play — or `cargo run`, or a double-clicked export — starts from
what it holds. Until the file exists the game runs on the type's
`Default`; a missing config is not an error.

That is the three-state consistency the export chain guarantees:
**restart the editor, press Play, ship the export — the same file, the
same values.** A dirty card is saved automatically before a Play or an
export (and before the editor quits, behind the save-all dialog), so
what the editor shows is always what the game runs.

## What the editor keeps out of the package

The asset copy filters the editor's own private files: scene save
rotations (`*.bak`), atomic-write leftovers (`*.tmp-*`,
`*.corrupt-*`), and the play-in-editor temp directory
(`.jackdaw-pie/`). Everything else — including any dotfile you own —
ships, and the export report counts what was kept out.

## Exports carry a receipt

Every export writes `export-manifest.json` at the root of its output:
each shipped file's path, SHA-256 and size, plus the profile and the
jackdaw build. Two exports of the same project agree on every line but
the timestamp — that is "same input, same output" made checkable — and
a moved or copied package can be verified against it file by file.

## Reproducible builds

Every build the editor runs — Play, `jd build`, `jd run`, an export —
passes `--locked` to cargo: the lockfile is the contract. New projects
start from the lock this jackdaw was built and tested with, so a fresh
scaffold compiles on the first try even when the registry has moved
on. When you change `Cargo.toml` and the lock is out of date, the
build fails with the remedy in its log: run `cargo update`, commit the
result.
