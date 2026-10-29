# Prefabs

A prefab is an authored `.bsn` file under `assets/prefabs/`
that any number of scene entities can *instance*. An instance
does not copy the prefab's content: it stores a reference (an
`IsA { source: "prefabs/rock.bsn" }` component) plus its own
sparse overrides, and the editor and the game both resolve the
reference to the same content. Edit the source and every
instance follows; override a field on one instance and only
that instance keeps it.

The workflow has seven moves: pack, instantiate, override,
apply, revert, nest, and variant. This chapter walks each one,
then the undo/reopen/export behavior that cuts across them.

## Packing: creating a prefab

Four entry points, one file format:

- Select entities in the hierarchy, right-click, **Save
  Selection as Prefab...** -- prompts for a name under
  `assets/prefabs/`, writes the file, and turns the selection
  into an instance of it.
- Right-click an empty spot, **Save Scene as Prefab** to turn
  the whole scene's roots into one prefab (multiple roots get a
  synthesized root).
- `prefab.pack` / `prefab.pack_matching` operators for bulk
  conversions: every group of entities with the same structure
  (or matching a name prefix) becomes an instance of one shared
  file.
- `jd`/scripts can write `.bsn` prefab files directly; see
  [BSN Format](../developer-guide/bsn-format.md).

Packing keeps each instance's own placement: the transform
becomes the instance's first override.

One known edge: packing (or scene-to-prefab) *over* a path
that already holds instances of the same file replaces the
cache entry wholesale, without a staged reload of the old
instances -- harmless for fresh packs, worth a reopen if you
overwrite a prefab that older instances in the same scene
still reference. Undoing a pack puts the
entities back and leaves the file on disk.

## Instantiating

Right-click in the hierarchy, or use the `entity.add.prefab`
operator, to pick a prefab file and drop an instance at a
position. Spawning never copies content: the new entity is one
`IsA` marker plus a `PrefabEntityId` anchor, and the resolved
children appear around it. Instances are independent from birth
-- moving, overriding, or deleting one never touches another.

## Overriding

Edit any part of an instance and the edit lands as a *sparse
override* on that instance's node: only the changed leaf (down
to single fields like `translation.x`) is stored, everything
else keeps inheriting. The Inspector shows the state per field
-- a filled dot means overridden, a hollow dot means inherited;
clicking the dot reverts that field. Deleting an inherited
entity inside one instance is also an override (a tombstone in
the `IsA.deleted` list), so other instances keep the entity.

Overrides are what make instances safe to specialize. Save and
reopen, or export, and they are still there -- sparse deltas
survive round trips and the game resolves them the same way the
editor does.

## Applying: promoting overrides into the source

When an override deserves to become the new baseline, three
menus push it up:

- Inspector field-row menu: **Apply Field to Prefab Source**.
- Inspector component-header menu: **Apply Component to Prefab
  Source**, and **Apply to All Instances in Scene** (bulk).
- Hierarchy context menu: **Apply All Changes to Prefab
  Source**.

**Apply writes the prefab file immediately.** The applied value
becomes the file's baseline, the applied overrides come off the
instance (its other overrides stay), and every other instance
of that prefab follows the new baseline on the next reload --
in the same scene, in other open scenes, and after a restart.
This matches the "apply means write" behavior most engines
have. Consequences worth knowing:

- Apply is **not undoable**. It is a file-level write; no
  scene snapshot can roll it back. The `.bak` file beside the
  prefab (see [Scene Management](scene-management.md)) holds
  the previous content, and re-applying an older value is the
  manual way back.
- The hierarchy's **Apply All** writes the file once for the
  whole batch. The Inspector's component menu dispatches
  per-field applies, so a five-field component writes five
  times -- small files, atomic writes, same end state.
- **Apply to All Instances in Scene** is deliberately
  different: it writes each instance's own override to *its*
  node and never touches the source file.

## Reverting

The inverse move, three granularities plus two escape hatches:

- **Revert Field** (field-row menu) drops one override leaf.
- **Revert Component** (component-header menu) drops one
  component's overrides; a component with no baseline refuses
  to be "reverted" into deletion, so data cannot silently
  vanish.
- **Revert All Overrides** (hierarchy menu) clears every
  override on the instance; anything the source cannot resolve
  is reported instead of guessed away.
- **Unpack Child** pulls one subtree out of instance land: it
  stops inheriting and becomes plain scene content.
- **Unbundle Prefab Instance** flattens the whole instance
  into authored entities (placement folded in, markers
  stripped). Undo puts the instance back; the unpack itself is
  part of the same undo step.

## Nesting

An instance node inside a prefab makes the prefab nested: the
outer file references the inner one, resolution follows the
chain (with a depth cap of 8 and cycle detection that refuses
to hang the editor), and each level keeps its own id space, so
ids never collide across levels. Overrides reach through
nesting -- reverting a field that was inherited through two
levels lands back on the deepest source value. Editing a nested
prefab's file reloads everything downstream of it, including
instances of the outer prefab.

## Variants

**Save as Variant** on an instance creates a new prefab whose
baseline is the instance's current resolved shape, wired back
to the original through an `IsA { source, deleted }` link: the
variant inherits from its base, so later base edits still reach
through. The variant keeps the subtree shape the instance was
cut from -- nested levels stay nested at their own depth, and
nested instances inside the cut keep their own references, so
un-packing or editing them later behaves like the original did.
Variants are files under `assets/prefabs/` like any other;
undo rewires the instance back to the original and the variant
file stays on disk.

Renaming a prefab rewrites the references: open scene tabs get
their in-memory documents retargeted right away, so the next
save writes the new spelling. Two narrow gaps remain by
design: references spelled through a moved folder's tail,
and canonical-path disagreements (macOS `/var` symlink
families) can need a manual re-spell.

## External edits and the watcher

Prefabs are plain files: edit one outside the editor (or with
another tool) and the watcher reloads every instance of it
after a short debounce. Authored overrides are preserved across
the reload -- the reload compares against the *old* baseline,
so a value that merely matched the old baseline does not get
mistaken for an authored override and frozen. A file that
arrives broken keeps the last good copy until it parses again.

## Reopen, restart, and export

Everything above survives the three hard boundaries:

- **Reopen**: save the scene, close the tab, open it again --
  instances, overrides, tombstones and applied baselines all
  come back from the two files (scene + prefab).
- **Restart**: the crash journal restores the tabs; prefab
  tabs rebuild their cache from disk, scene tabs re-resolve
  their instances.
- **Export**: the export stages the whole `assets/` tree, so
  prefabs ride along, and the standalone game resolves
  references through the same code the editor uses. References
  outside `assets/` are refused; a file that fails to parse
  spawns as authored content with a warning naming it. The
  baseline on disk is what a fresh export ships --
  apply before exporting, or the staged game sees the old
  baseline.

## Common gotchas

- **An edit on an instance "moved" another instance.** It did
  not: you edited the source (apply) or the file (external
  edit), and the other instance followed. Revert the field to
  detach that one instance again.
- **Revert did nothing visible.** The field was already at the
  baseline; or the value you see comes from a *nested* level,
  and the revert landed one level down. Check the field dot's
  tooltip.
- **The override dot is hollow but the value looks custom.**
  The value matches the current baseline. After someone
  applies a new baseline, matching values stop counting as
  overrides -- that is the freeze-proofing working, not a
  bug.
- **`prefabs/` path not found in a scene file.** Prefab
  sources are stored relative to `assets/`; moving files
  outside the editor does not rewrite references. Move them
  back, or fix the path in the file.
- **Applied and then regretted it.** No undo for apply. Grab
  the previous values from the prefab's `.bak` (or `git`)
  before re-applying something else.
