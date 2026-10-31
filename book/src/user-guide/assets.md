# Assets

Everything the game loads that is not a scene you authored by hand —
pictures, models, materials, sounds — lives under the project's
`assets/` folder, and the editor treats it as one working set: you
drop files in, set import options on the ones that want them, and
the editor keeps every face of the open project in step when the
files change on disk — even when the change came from an external
tool. This chapter is the overview: what the import entrances are,
what each format family supports, how hot reload reaches the
viewport, the inspector and the thumbnails, and what happens when a
file is broken. The per-domain chapters go deeper:
[Materials & Textures](materials-textures.md),
[Audio](audio.md), [Prefabs](prefabs.md) and
[Asset References](asset-references.md).

## The five families

| Family | Extensions | Ways in |
|---|---|---|
| Images | `.png` `.jpg` `.jpeg` `.webp` `.bmp` `.tga` `.ktx2` | drag-and-drop or paste into the editor window, **Add > Reference Image** |
| Models | `.gltf` `.glb` | drag-and-drop (placed where it lands); `Place GLTF` behind it |
| Materials | `.material.bsn` | **New Material** (the material browser), the Project window's **New Asset** menu |
| Audio | `.ogg` `.oga` `.wav` | the audio row's **Pick**/**Browse**, drag onto the field |
| Definitions | texture sets, layered surfaces, foliage, water | created by naming convention and detected on the walk |

A dropped or pasted image is imported (copied into `assets/` if it
came from outside) *and* placed as a reference plate at the cursor,
ready to trace over. A dropped model is placed as a full instance.
Everything else lands as a file the Project window lists.

Two format boundaries are worth knowing as they are, honestly:

- **JPG works in the editor, not (yet) in template games.** The
  editor enables JPEG decode, so a `.jpg` imports, displays,
  thumbnails and hot-reloads like a PNG. The game template keeps
  its Bevy features to `wav` — it ships no jpg assets — so a game
  that should load `.jpg` at runtime adds `"jpeg"` to its own Bevy
  features.
- **MP3 and FLAC are not enabled** anywhere yet: the pickers don't
  offer them and the loaders won't decode them. Ogg Vorbis and WAV
  are the audio pair ([Audio](audio.md)).

## Import options

Two asset kinds carry import options today, both stored as a Bevy
`.meta` file beside the source:

- **Textures.** The file card's **Import** row offers *Compressed,
  mipmaps* (VRAM compressed, mipmaps generated — the right choice
  for anything that ends up on a model) and *Original file* (the
  bytes go to the GPU as they are — screenshots, reference
  plates). The choice is the `.meta`; the card shows which one is
  in force, and it survives an external rewrite of the source:
  re-import reads the option again. When no `.meta` exists, the
  color space is chosen by filename convention (`_albedo`,
  `_normal` and friends), so name textures the way the convention
  expects and sRGB lands correctly without touching anything.
- **Models.** A model's `.meta` holds its LOD import settings —
  which meshes count as which detail level. They are set once and
  respected across later re-imports, including changes made at
  the placement level for one placed instance.

There is no general import panel beyond these; explicit sRGB
switches and per-texture flips are open work.

## Hot reload: edit the file, watch the editor follow

The editor watches `assets/` while it is open. Save a file from an
external tool — an image editor, a mesh tool, a script — and within
about a second every face follows, with no manual refresh:

- **The engine reloads the asset in place.** The same handle an
  asset was loaded under is reused, so everything holding it sees
  the new content without any reference changing. The engine's own
  log line (`Reloaded matrix/hero.glb`) is the reload happening.
- **The viewport follows per asset kind.** Images swap pixels in
  place (reference plates and material slots). Models are
  re-instantiated whole: the placed instance's entities are
  rebuilt from the new file — authored transforms on the instance
  stay, the geometry under it is replaced.
- **Materials re-import through the asset index.** `.material.bsn`
  files do not go through Bevy's asset server; the index walk
  compares modification times and swaps the new value into the
  *old* handle, so previews, brushes and every scene using the
  material follow. A card with unsaved edits is left alone until
  you save or discard it. The same walk picks up new and deleted
  files everywhere.
- **The Project window and thumbnails refresh.** The changed paths
  drive the window's re-render and invalidate the thumbnails of
  the files that changed (below).
- **A prefab file changes → every instance reloads** after a short
  debounce, overrides preserved
  ([Prefabs](prefabs.md)). **A scene file changes outside the
  editor** → an open tab offers to reload instead of being
  silently clobbered.

One naming trap: the **File > Hot Reload** switch in the menu is a
different thing entirely — it watches *extension* builds (dylibs
compiled outside the editor). Asset hot reload has no switch; it
is always on in the editor.

**The game side is dormant by design.** A template game does not
watch files — a shipped game should not — so editing a scene while
the game runs does nothing there. The reload machinery exists for
development if you opt in (add Bevy's `file_watcher` feature to
the game and the scene-root respawn primitive is already wired).

## Thumbnails

Model, material and prefab tiles in the Project window are
rendered thumbnails, cached under `<project>/.jackdaw/thumbnails/`.
The cache key is the file's path plus its modification time, so:

- a stale thumbnail is never served for a changed file — the new
  mtime is a new key;
- when the watcher reports a file changed, its cached thumbnail is
  invalidated and re-rendered on the next sight of the tile — the
  same external rewrite that moves the viewport moves the tile;
- a file that fails to render gets one warning and is written off
  for that version; fixing the file earns a new attempt (the
  mtime changed);
- the folder is a cache: deleting `.jackdaw/thumbnails/` is safe
  and costs one re-render per tile.

## When a file is broken

A file that exists but does not load — truncated, clobbered by a
half-finished write, garbage wearing an honest extension — is the
case the editor is built to survive, and the behavior has two
halves worth separating:

**The engine keeps the old content.** A failed load — first load
or reload — never removes the previous value of an asset. The
viewport keeps the last good picture, placed model instances stay
standing, references in documents are untouched (they are path
strings, and a broken round writes nothing), and the scene saves
exactly as it was. Nothing cascades.

**The editor tells you, twice.** The failure reaches the author
instead of scrolling past in engine chatter:

- the log names the file and the reason once per version of the
  file: `asset load failed: …/board.png (…) -- showing the previous
  content`;
- the status bar carries the same news as a warning banner:
  `board.png failed to load; showing the previous content`.

Once per version means a file that fails repeatedly (a retrying
loader, ten systems asking) warns once; rewrite the file — fix it,
or break it a different way — and it speaks again if it still
fails. There is no lock to clear when a file recovers: a
recovered file raises no failure at all, and the next successful
load simply follows the fix. For images on the plain path, the
plate picks the restored picture up like any other rewrite.

Two edges to the picture, stated as they are:

- **Audio is guarded at the picker, not at play time.** The editor
  refuses to attach a file it cannot decode (garbage bytes under a
  `.wav` name): the pick is declined with a warning —
  `… is not a sound file the editor can decode; the reference was
  not written` — and the field keeps its old value. This matters
  because a broken audio file that *does* get attached (made bad
  after the fact) decodes only when a sink is built: in a game
  process that decode failure is a crash of that process. Keep
  real files under real names, and let the picker be the first
  gate ([Audio](audio.md)).
- **A texture with import options has a known corner.** After a
  texture has been re-imported through *Compressed* (the `.meta`
  path), later rewrites of the same file still reload — but the
  visible plate can stay on its first-loaded picture, because the
  GPU face does not follow the re-uploaded format yet. This is a
  known open defect on the render side, not the reload chain: the
  plain (no `.meta`) path — the common case — follows normally.
  If a compressed texture refuses to visibly update, toggling it
  back to *Original* (or removing the `.meta`) restores the
  following.

## Renaming and moving

Inside the editor — the Project window's rename/move, or the
operators — a rename brings every reference along: documents are
rewritten, tabs and cards follow, the index moves the entry, and
nothing re-loads ([Asset References](asset-references.md)).

Outside the editor (the OS file manager), the watcher sees a file
vanish and another appear; it does not guess they are the same
asset. Documents keep the old path, and the audit reports it
`Missing` — run **Missing References** and **Rebind** the entry to
the new file. That is the designed boundary, not a gap: the safe
path for renames is the editor.

## The 30-second check

1. Open a project with a model, a material and a reference image
   placed (the new-project template's assets work). Look at the
   Project window: tiles for all three.
2. From an external tool, edit the model's `.glb` (or swap it for
   a different export) and save. Within a beat: the viewport
   instance rebuilds, its file card follows, and the tile renders
   the new shape.
3. Same for the material: change `base_color` in the
   `.material.bsn` file. The tile, the browser and every face
   using it turn over.
4. Now break something: write garbage over the image's bytes. The
   editor stays alive, the plate keeps the previous picture, and
   the status bar names the file: `… failed to load; showing the
   previous content`.
5. Restore the good bytes. The reload follows the fix.
6. Try to attach a garbage file as a sound: the picker declines it
   with a warning and nothing is written.

*(Keep the demo on textures without import options: a compressed
(`.meta`) texture's visible face is the one known corner that
lags — see above.)*
