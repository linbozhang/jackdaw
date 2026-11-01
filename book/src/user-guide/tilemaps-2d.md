# Tilemaps in 2D

A tilemap is a grid of cells painted from one sheet image: the shape a
platformer's ground, walls and trip zones want to take. The Tilemap tool
gives you a palette, a canvas that paints and erases whole cells, fills,
layers, and a per-layer collision setting — and what you author runs as a
real level: a floor holds the player, a wall stops them, a trigger cell
fires. This chapter walks the whole path: make a level, run it in Play
and as an exported build.

Everything here happens in a 2D world scene —
[Sprites in 2D](sprites-2d.md) covers the scene kind, the canvas and the
sprite toolkit that the tilemap rides on.

## A level, a layer, a sheet

Open (or make) a 2D scene and press **T** — the Tilemap tool. The palette
panel appears over the canvas:

- The **sheet display**: the layer's whole sheet image with a grid over
  it. Click a cell to pick the tile your strokes cut — the readout under
  the grid names the active tile (`Tile 12`), and a highlight box marks it
  on the sheet.
- The **brush row**: `Paint`, `Erase`, `Fill`, `Flood`.
- One **row per layer**: an eye toggles the layer's visibility, the badge
  cycles its collision mode (P for Passable, S for Solid, T for Trigger),
  and clicking the name makes it the active layer. **+ Add Layer** makes a
  new one.

A layer asks for the sheet and its cut: the image file, the cell size in
pixels, and how many columns and rows the sheet has. One consequence is
worth knowing up front: the layer's cut *is* the level grid. A 16×8 sheet
of 32-px cells is a level of 16×8 cells, 512×256 world units — pick (or
generate) a sheet with the room your level needs. Cells outside the cut
do not exist; a stroke that names one is refused whole, nothing partial.

## Painting, erasing, filling

With the Paint brush, drag across the canvas: every cell the cursor
touches lights up, and releasing the button stamps the whole drag at once.
One drag is one undo — a stroke, not a hundred single cells. **Esc** or a
right click cancels a drag mid-stroke.

The other brushes change what a drag does:

- **Erase** removes the cells you drag over. Erasing empty cells does
  nothing, on purpose and without complaint.
- **Fill** stretches a rectangle from where you pressed to where you
  released, and fills it.
- **Flood** fills a connected region from the cell you click — the same
  region a paint program would fill, bounded by differently-set cells and
  by the grid's edge.

Painting a cell that already holds a tile repaints it with the active
tile; painting over the same tile changes nothing.

## Layers: ground, wall, trigger

A level is usually three layers. The layer rows at the bottom of the
palette are the control surface: the **active layer** (its name lit)
receives every stroke, so painting the wall is "add a Wall layer, paint
the wall" without ever touching the ground beneath.

The badge on each row sets that layer's collision mode, and this is the
part that makes a level out of tiles:

- **P — Passable**: decoration. Runs render it; nothing stops on it.
- **S — Solid**: the ground and the walls. Bodies stand on a solid row
  and are stopped by a solid column.
- **T — Trigger**: the trip zones. A body entering a trigger cell fires
  it — the hook a door, a coin or a hazard hangs on.

The modes are per layer, not per cell: paint your floor on a Solid layer
and every cell of it is floor. Hide a layer with its eye to see (and
author) what is under it; hidden layers keep their collision — the eye is
an authoring aid, not a gameplay switch.

## Undo, save, reopen

Every stroke — a drag, a fill, a flood, an erase — is one undo entry, so
`Ctrl+Z` walks your level back a gesture at a time and redo walks it
forward again. Saving and reopening round-trips everything in the
chapter: every cell's position and tile, every layer's cut, visibility
and collision mode. Tiles are plain sprite entities cut by the sheet
rectangle — no sidecar format, no asset to lose.

## Running the level

Authoring runs on the editor; collision runs on the game. To give your
game the tile side, turn on the **tilemap** module for the project —
**File > Modules** (or `jd new --modules tilemap`): the module adds the
collision-kernel crate to the game's manifest and, into the game
template, a small teaching block: the scene's layers become one collision
grid, a square probe body walks it, and a census resource counts trigger
crossings — the census is reflection-registered on purpose, so remote
tooling can read it while the game runs (the flow's `States` resource is
not, which is why [Game Flow](game-flow.md) reads flow position from the
scene markers instead). Ground row holds the probe at its top edge, a
solid column stops its walk, a trigger cell flips the census — the three
behaviors a real player controller replaces with its own body.

That block is a prototype to build on, deliberately: per the example-game
boundaries, level *props* and their behavior are code the game owns — the
editor authors the grid and its modes, the game decides what walking into
a trigger means. Swap the probe for your player and keep the three-step
loop it teaches: read the input, resolve against the grid, census the
triggers.

**Play** in the editor and `cargo run` run the same executable; `jd
export` stages a build that runs on a machine with no toolchain at all —
the grid, its collision and the flow all ship inside the package.

## Two boundaries, stated plainly

- **Scale.** The tile-per-sprite form keeps every cell a real entity:
  right for the small levels this tool is for, not for a thousand-screen
  mega-world. The sheet is the level, so the level is as big as the sheet
  you bring.
- **Handles.** Tile sprites cut their sheet by rectangle (`Sprite.rect`),
  never by atlas handle — the editor and the game both render the one
  cell, where the atlas path can end up showing the whole sheet on one
  side ([Sprites in 2D](sprites-2d.md) has the atlas context). If a tile
  ever renders as the entire sheet, that is a bug, not a setting.

Collision here is the tile-grid kernel the module ships. For bodies,
joints and full physical simulation there is the 3D physics stack —
[Physics](physics.md) — a separate world with its own colliders; a 2D
tile level does not need it, and mostly does not want it.

## The 30-second check

Make a 2D scene, press **T**, add a layer, paint a row of floor, make the
layer Solid. Add a Trigger layer, paint two cells on the walk line. Save.
Press **T** again to stand down, Play — the probe drops onto your floor,
holds steady, and when you walk it through the trigger cells the game
says so out loud. Save, reopen: the level is exactly as you left it.
