# Sprites in 2D

A 2D world scene is the flat counterpart of the 3D viewport: sprites
instead of meshes, a 2D camera instead of orbit, and a canvas where one
world unit is one texture pixel. Everything you already know about
documents, saving and reopening applies unchanged — a sprite scene is a
scene like any other. This chapter covers the 2D half of authoring: making
a scene, getting images onto its canvas as sprites, the select-and-move
toolkit, the Inspector's sprite fields, cutting a sheet into an atlas,
draw order, and what Play and export do with all of it.

UI is a different scene kind with its own canvas and widget set —
[Game UI](game-ui.md) covers that world. The two coexist in one project:
a 2D world scene holds the game's spaces, a UI scene holds the interface
drawn over them.

## A 2D scene

Create one with **File > New Scene** and the 2D kind (the operator is
`scene.new kind=2d`; [Scene Management](scene-management.md) has the
document mechanics). The tab opens on the 2D canvas — pan with the usual
controls, zoom, and the view stays framed on your content
([Viewport Navigation](viewport-navigation.md) has the gestures). A new
2D scene is empty except for its root marker; the camera that draws the
canvas is the editor's, not yours.

The **2D game** template in the launcher starts a project whose starter
scene is exactly this: a `Camera2d` named `Main Camera` and one sprite,
ready to run. One honesty note about that template: its game code still
carries the 3D furniture (camera rig, physics) from the standard template,
so a 2D scene plays with the 2D camera drawing sprites while the 3D rig
draws an empty 3D view alongside. It runs fine; trimming that furniture is
your first edit, not the editor's.

## Making a sprite

Three entrances, one destination — all three make the same kind of
entity, and all three are one undo:

- **The Add menu.** With a 2D scene open the Add menu grows a **2D**
  group with **Sprite** and **Empty 2D** rows. The group only appears
  while a 2D world scene is in front. (The 3D groups still show in a 2D
  scene — adding a Cube does not error, but a 2D camera cannot draw it;
  use the 2D group.)
- **The operator.** `sprite.add` takes an optional `path` (an image under
  `assets/`), `x`/`y` (world coordinates; default is the centre of the
  view in front), `parent` and `name`.
- **Drag and drop.** Drop an image file onto the 2D canvas and it lands
  as a sprite at the drop point, named after the file — the same image
  dropped into a UI scene or a 3D scene becomes a UI node or a reference
  plate instead ([Assets](assets.md) has the import half).

A sprite with no image is a 32×32 placeholder block you can select and
move immediately; attach an image through the Inspector (below) or drop
one in. Each new sprite draws **on top**: its z lands one above the
scene's highest sprite, so what you add last is what you see first
([Draw order](#draw-order)).

The result is a normal entity: `Name`, `Sprite`, `Anchor`, `Transform`,
`Visibility` — everything the Inspector lists, everything that saves.

## Select, move, rotate, scale

Click a sprite on the canvas and it picks: a blue outline marks the
selection and the move gizmo draws over it — the same tools the 3D
viewport uses, so the toolbar's translate/rotate/scale rows behave as
they do there. Moving takes the whole selection; rotating and scaling
take the primary sprite alone, and rotation turns about the sprite's
**anchor** — move the pivot first if a rotation should swing from an
edge (below). The arrow keys nudge the selection; every step is an undo
entry, so `Ctrl+Z` walks a drag back piece by piece.

The 2D canvas also snaps and guides:

- **Guides** are lines you place for alignment: `canvas.guide.add`
  with `axis=vertical position=64` (or `axis=horizontal`), and
  `canvas.guide.remove` naming the line to take back — the same guides
  a UI canvas uses, stored on the scene root.
- **Snapping** has a master toggle (**Use Snap**) and a pixel toggle
  (**Use Pixel Snap**); each axis lands on the first line within reach —
  another sprite's edge or centre, or a guide — then the grid, then the
  whole pixel, and `Ctrl` inverts snapping for the length of one drag.

For driving the canvas from a script or remote client,
`input.pointer` accepts `space=world` — world coordinates, y up, framed
by the panel's pan/zoom ([Remote Control](../developer-guide/remote-control.md)).

## The Inspector: sprite fields

Select a sprite and the Inspector lists the works. The fields that
matter day to day:

| Field | What it does |
|---|---|
| `image` | The texture — pick, browse or drop a file onto the row |
| `color` | Tint multiplied over the texture |
| `flip_x` / `flip_y` | Mirror the sprite |
| `custom_size` | Draw size in world units, overriding the texture's pixel size |
| `rect` | Draw only a sub-rectangle of the image |
| `texture_atlas` | Atlas layout + which frame to draw ([Sprite atlases](#sprite-atlases)) |
| `image_mode` | `Auto`, `Scale`, `Sliced` (nine-slice borders) or `Tiled` |
| `alpha_mode` | `Opaque`, `Mask` or `Blend` |

Every change answers on the canvas at once — tint it red and it is red,
slice it and the borders hold while the middle stretches.

**Pivot.** The `Anchor` component is the sprite's pivot, and its card
leads with a 3×3 preset grid — nine cells from Top Left to Bottom Right —
plus the raw offset row underneath for anything off-grid. A preset pick
writes the same field the offset row edits, with the same undo. The pivot
is where the sprite sits, where it rotates about and where it scales
from, so moving the pivot visibly shifts the sprite.

## Sizes and pixels (the PPU question)

There is no pixels-per-unit setting anywhere in this editor or the
engine — by design, because the engine's answer is simpler: **one world
unit is one texture pixel**. A 64×64 image draws 64 units wide; end of
conversion. What Unity calls PPU-100 is expressed here as the result
rather than the setting:

| You want (Unity habit) | Here |
|---|---|
| 64×64 image at PPU 100 → 0.64 units | `custom_size` = 0.64 (or `Transform.scale` = 0.01) |
| 64×64 image drawn at half size | `custom_size` = 32×32, or `scale` = 0.5 |
| Pixel-perfect (1 texel = 1 unit) | leave both alone — that is the default |

`custom_size` changes what is drawn; `scale` changes the transform. Pick
one and stay with it — both at once is two answers to one question.

**Filtering** (nearest vs linear) is a per-texture sampler property the
editor does not expose per asset today, and a runtime change would not
survive a reload anyway. The editor's global default is linear with
repeat; if a project needs nearest (crisp pixel art at odd scales), the
honest paths today are the global default or a line of game code. A
per-asset, persistent switch is recorded as open work.

## Sprite atlases

A sheet — one image holding a grid of frames — is cut by a **Sprite
Atlas** definition asset, not by the sprite:

1. **New Asset** (Project window) → **Sprite Atlas**. The card lands
   under `assets/` as a `.bsn` file.
2. On the card, run the grid cut: `sprite.atlas.grid` with
   `tile_size=32,32 columns=8 rows=4` (plus optional `padding` and
   `offset`). The frames are numbered **left to right, top to bottom**,
   and the whole cut is one undo. The card's rows list every frame's
   rectangle; hand-editing them is the way to a non-grid layout.
3. On a sprite, set `texture_atlas.layout` to the atlas card (the row's
   picker lists the project's atlases) and `texture_atlas.index` to a
   frame number.

One limitation to know as it is: **the editor's canvas currently draws
the whole sheet** for a sprite wearing an atlas — the indexed frame is not
previewed on the canvas yet (and depending on when the atlas card first
landed on disk, the log may carry an asset-loader error for it besides).
The **game and exported builds load the atlas card through their own
walk** — but there too, a sprite wearing the card currently draws the
whole sheet rather than its indexed frame. The indexed-frame render path
is a recorded defect (A17), not a save or a data problem — everything
authored (the cut, the reference, the index) round-trips exactly.

## Draw order

A sprite's draw order is its `Transform.translation.z`: smaller z draws
first, larger z draws on top — the same z the move gizmo, the Inspector
and every transform tool already edit. Newly added sprites land one above
the scene's highest, so the newest thing is the visible thing until you
say otherwise.

What does not exist yet: a sorting panel that lists sprites by z with
drag-to-reorder, and a Y-sort mode (siblings ordered by their y so top-down
scenes need no z bookkeeping). Both are recorded as open work; today z is
the whole surface, and it satisfies the letter of authoring — it is just
hand-run.

The atlas is the one sheet-cutting surface — the Tilemap tool cuts the
same way and paints with the cells; [Tilemaps in 2D](tilemaps-2d.md) is
the whole 2D-level story.

## Playing and shipping

Play, direct run and export all speak 2D. The **embedded** Play mode
streams the game's own frames into the Game panel — sprites and all, the
panel is a faithful monitor for a 2D scene
([Play-in-editor](play-in-editor.md)). The **windowed** mode's stream is
captured by the template's 3D camera and shows no 2D pass, so judge a 2D
scene there by the game's own window (or by numbers over the live tree),
not by the Game panel — the game window is the truth either way. Exports
ship the whole `assets/` tree including atlas cards. (A staged build
runs the indexed tiles — but the editor canvas currently draws the
whole sheet for an authored-atlas sprite; see the atlas section above
for the standing note.)

Two wiring notes for the running side, stated as they are: the editor's
live tree reads the template game's screens through the scenes' document
root markers — `State<GameFlow>` itself is not remotely readable yet (a
recorded gap, A16, with a one-line fix waiting for the next template
touch) — see [Game Flow](game-flow.md) for what the template actually
does. And if you rename or move an image file outside the editor,
**Missing References** and **Rebind** rewrite the documents
([Asset References](asset-references.md)), but a scene that is open live
keeps the old handle until you reopen it (recorded gap, A11) — the safe
path for renames is the editor, as [Assets](assets.md) already advises.

## The 30-second check

1. New project with the **2D game** template, open the starter scene:
   a sprite on a 2D canvas. **Play**: the Game panel shows it.
2. Drag any PNG onto the canvas: a sprite lands at the drop point named
   after the file. Click it — outline and move gizmo; drag it, nudge it
   with the arrows, `Ctrl+Z` steps it back.
3. In the Inspector pick a **Pivot** preset (say Top Center): the sprite
   shifts about its position. Tint `color`: the canvas follows.
4. **New Asset → Sprite Atlas**, cut a grid over a sheet, point the
   sprite's `texture_atlas` at the card, set an index. **Save**,
   **Play**: the game runs wearing the card — today both the editor
   canvas and the game window draw the whole sheet rather than the one
   indexed frame (the recorded gap above); the cut, reference and index
   still save and reload exactly.
5. Reopen the scene: transforms, pivot, atlas reference and index all
   come back exactly.
