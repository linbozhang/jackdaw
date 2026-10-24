# Graphics Panel

The Graphics panel is one window over the two layers that already decide
picture quality: how the **editor previews** the scene, and how the
**scene itself** is meant to look. Open it from the Window menu
(Graphics, docked in the right sidebar) or the command palette
(`graphics.open`).

The two halves of the panel write to different places, and that is the
one thing worth holding onto:

- **Viewport** is the editor's own preview. Every control is an
  editor-only preference: it applies at once, never enters the undo
  history, never enters the scene, and is kept per user in
  `viewport.json`. Drop the editor on a slower machine, dial the preview
  down, and the game is untouched.
- **Scene** is the scene's look. Every control writes one field of the
  scene's `Environment` (its `post` settings): one undo entry per
  gesture, saved with the scene, carried into play and export. A scene
  with no environment shows a note saying so — add an `Environment`
  component to start authoring the look.

## Viewport section

| Control | What it does |
|---|---|
| Quality Preset | One click for the whole row below (see the table). |
| Render Scale | Renders the viewport at 25–100% of its size and upscales. |
| Anti-Aliasing | Off, FXAA, TAA or SMAA on the viewport camera. |
| Ambient Occlusion | Screen-space ambient occlusion, with a quality row (Low–Ultra). |
| Sun / Point Shadows | Whether the preview draws shadow maps at all. |
| Fog | Distance fog in the preview. |
| Sharpening | Contrast-adaptive sharpening, off/on with a strength. |

The presets are the same four the viewport menu offers:

| Preset | Render scale | Anti-aliasing | Shadows | Point shadows | Fog | Post-processing | Bloom | SSAO |
|---|---|---|---|---|---|---|---|---|
| Low | 50% | Off | low maps | off | off | off | off | off |
| Medium | 75% | FXAA | medium maps | off | on | on | off | off |
| High | 100% | FXAA | high maps | on | on | on | on | off |
| Full | 100% | TAA | high maps | on | on | on | on | on (High) |

Picking a preset rewrites the whole row; anything you then change by
hand stays until the next preset pick. The presets also set the shadow
map sizes and detail distance, which have no separate rows here.

## Scene section

The controls are the scene's `Environment.post`, field for field — the
same thing the inspector edits, gathered in one place:

| Control | Field |
|---|---|
| Post Processing | The section's master switch (`post.enabled`). |
| Tonemapper | Nine tonemappers, `TonyMcMapface` by default. |
| Exposure (EV100) | Camera exposure, 9.7 by default (Blender's EV100). |
| Bloom Intensity / Threshold | The bloom prefilter; intensity 0 means no bloom. |

Sliders commit on release: one drag is one undo entry. When the scene
has no environment, the section shows a note and its controls write
nothing until one is added.

One honest caveat about **previews**: the Scene section reaches the
game's cameras, and the viewport only previews what it hasn't opted out
of. On the Low preset — or with the viewport's post-processing toggle
off — tonemapping and bloom stay authored but are not drawn in the
viewport, and the panel shows a note saying the viewport opted out. The
anti-aliasing row never applies to the game at all: the viewport's AA
is always the viewport's own.

## Realtime GI

The last row is named but greyed out, on purpose. Bevy's realtime global
illumination (Solari) is experimental, needs hardware ray tracing and
its own cargo feature, and jackdaw has not adopted it — a greyed row
with the reasons says more than an absent one. The tooltip also names
what stands in for it today: ambient occlusion, sky reflections
(Environment → Ambient → Reflections: Sky), baked reflection probes,
and volumetric light.
