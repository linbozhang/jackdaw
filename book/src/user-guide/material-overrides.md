# Material Overrides

A placed glTF model wears the materials its file ships with. A
**material override** swaps one of those materials for one of your own —
by name, on the model as placed — without touching the file. The swap
travels with the model through saves, reopens, prefab packing, exports
and reimports, and a part whose override breaks says so instead of
quietly falling back.

## The three layers

Overriding is two components on entities, and one engine habit that
makes them show:

- **The model layer** — `MaterialOverrides`, on a placed model's root: a
  map from the model's *material names* to material files
  (`"Rock" → materials/mossy.bsn`).
- **The instance layer** — `InstanceMaterialOverrides`, on a prefab
  instance's root. It lays over the model layers of the models the
  instance holds, and wins on keys both layers name. An instance only
  records the keys it overrides; the rest keep following the prefab
  file, so a prefab edit re-dresses every instance that did not
  override that key.
- **The dressing itself** is not stored anywhere — the runtime dresses
  the parts: whenever a model spawns, a part arrives, or the project's
  material tables move, every part wearing an overridden material name
  is swapped to the override's file (and the part it replaced is kept
  so it can be given back). This is the same plugin in the editor
  viewport and in a built game, so what you see while authoring is
  what the game wears.

## One name, every part wearing it

The key is the glTF material's name, not a node's. Two parts of the
model that wear the same material swap together with one entry — a
`"Rock"` entry dresses every Rock mesh in the model at once. A part
whose glTF material has **no name** cannot be addressed by any
override; name your materials in the DCC before export if you mean to
re-dress them.

## The three ways to put an override on

- **The inspector's material row.** Select a part of a placed model and
  pick a material from the row: the editor finds the model the part
  belongs to and writes the override where it belongs (the instance
  layer if the model sits inside a prefab instance, the model layer
  otherwise). The picker only offers materials the project holds.
- **The operator.** `material.override` takes an entity, a material
  name and a material path — the scriptable door. Overriding the root
  with an empty name re-dresses every named material the model has;
  `material=""` clears an entry.
- **The material browser's Apply.** With a model part selected,
  applying a material from the browser writes the override for the
  part's material name.

All three land as one undo-able edit on the model's document patch —
the same command underneath, whichever door it came through. Packing
the model into a prefab carries its model-layer entries into the
prefab file; terrain scatter entries carry their models' overrides
into the scatter storage and back out again.

## Saving, reopening, exporting, undoing

The override map is part of the model's document patch, so it saves
with the scene and comes back on reopen; the parts dress again as they
spawn. An override is one undo-able edit like any other — undo takes
the entry off the map and the parts dress back, with no warning along
the way. A `game.export` copies the scene and the material files into
the staged package, and the staged game resolves the same relative
paths through its catalog — the parts wear the same overrides with no
editor present. The reporting, though, stays in the editor: a broken
override in a running game gives back quietly by design, so the game
log carries no `material override:` lines. Reimporting the GLB (an
external edit of the file) rebuilds the parts in place: the override
survives on the model root, and a part added by the new version of the
file dresses through the override it already covers.

## When an override breaks

Two things can break an override, and both are reported — never
silent:

- **A path breaks** (the material file is deleted, or renamed outside
  the editor): the parts wearing it give back to their own material,
  and the editor says so once — a `material override:` warning in the
  log and on the status bar. The finding also shows up in
  [the audit](asset-references.md) as a `Missing` row naming the
  document, entity, component and field (`MaterialOverrides ·
  materials`). Put the file back and the parts dress again, with no
  new warning; break it again and it speaks again.
- **A name breaks** (a reimported GLB renames or drops a material the
  override names): the entry stays (it may match again on a later
  reimport), the parts that no longer match wear their own material,
  and one warning names the model and the key — "overrides a material
  named 'Rock', which no part of it wears any more". Restore the name
  in the file and the override dresses again.

One transient to know about: **the warnings you see in the first
moments after opening a scene are spawn-timing, and clear
themselves** — the report can look before all the model's parts have
arrived, and once they do, the locks clear and nothing repeats. A
warning that stays is a real one.

An entry that is broken on purpose (you no longer want it) is yours to
remove: `material.override` with `material=""` clears the named entry.

## Rebinding a broken path

The audit's **Missing References** list (see
[Asset References](asset-references.md)) offers **Rebind** on an
override path exactly as on any other reference: the map entry is
rewritten to the file you pick, the tab turns dirty, and the parts
follow on the next save (or at once, on the tab the scene is open in).
Rebind covers the override maps on both layers.

## The 30-second tour

1. Select a model part, pick a material on the inspector's material
   row, save, reopen — the part still wears it.
2. `game.export`, run the staged game — it wears the same override.
3. Delete a material file an override names — one
   `material override:` warning, and a `Missing` row in the audit.
4. Put the file back — the part dresses again, the warning is gone.
5. Rename a material inside the GLB — one warning names the orphaned
   key ("no part of it wears any more").

## Where this sits

Overridden parts still carry standard material components under the
hood; the [Materials & Textures](materials-textures.md) panel is where
the material *files* come from, [Prefabs](prefabs.md) explains the
instance layer the overrides lay over, [Sprites in 2D](sprites-2d.md)
covers the 2D side of material use, and [Assets](assets.md) is the
index/watcher machinery the healing rides on.
