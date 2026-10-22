# Resources

The Resources panel is the editor's window onto the world's `Resource`
values: the singletons that hold global state, from ambient light to a
game's own score. It sits in the right sidebar of the default Level
Design workspace, tabbed beside Components, Materials and Systems.

The notice pinned to the top of the panel is the one thing to hold onto
before anything else: **resource changes apply to this editor session
only and are not saved with the scene.** A scene file holds entities and
their components; resources are runtime state, so an edit here is a
tweak to how the editor is running right now, not an authored change.
Close the editor, or open another scene, and it's gone. That is what
the panel is for: turning knobs while a scene is open — slow the clocks,
dim the ambient light, drop a test resource in — without pretending
those knobs ship.

## Listing

The panel lists every resource the editor's world has instantiated,
grouped with your game's own types in a Game section first and engine
types after, each row showing the type's short name and carrying its
full reflect path as a tooltip. The filter box at the top narrows rows
by name.

Not everything in the world shows up. A resource is listed when:

- It is one of **your game's types** — anything whose type path is not
  a `bevy` or `jackdaw` prefix. A resource your game registers shows up
  with zero configuration.
- It is on the panel's **engine allowlist**: `GlobalAmbientLight`,
  `ClearColor`, `GizmoConfigStore`, the `Time<Virtual>` and `Time<Fixed>`
  clocks, and `Gravity` when a physics module has registered it.
- An **extension** admitted it, through the `ResourcePanelVisibility`
  resource's `allow_path` / `allow_prefix` builders. A deny always wins
  over an allow, which is how asset storages, schedule internals and the
  editor's own bookkeeping stay out of the list.

## Viewing and editing

Click a row and the panel shows a card for that resource: its reflected
fields, read live, the same rows the inspector gives a component.
Nested structs expand, enums are menus of their variants, colors open
the color picker, lists grow and shrink from their own controls.

Edit a field and the write goes to the resource itself — the world's
ECS, never the scene document. Every gesture (a scrub, a typed value, a
picked variant) is one undo entry, interleaved with entity edits on the
same undo stack: Ctrl+Z after a resource edit undoes the resource edit,
and an entity edit before it is untouched.

## Adding and removing

**Add Resource** opens a picker of resource types that are registered,
default-constructible, and admitted by the same visibility rules — a
type with no `Default` can't be conjured from nothing, so it is not
offered. The card of a selected resource carries its own **Remove
Resource** button. Both are undoable: remove, undo, and the resource is
back with the values it had.

## Limits

- **Session-only, as the notice says.** Nothing here persists, by
  design; there is no place in a scene file for a resource.
- **Schema-only types aren't editable.** When a game's schema reports a
  resource type but no extension has loaded the real type into the
  editor — no dylib registered it — the panel has no `Reflect`
  registration to render or construct, so the type stays off the list.
  Load the real type through an extension and it appears, editable.
- **The panel reads the editor's world.** A game running under
  play-in-editor keeps its own resources in its own process; this panel
  is not that window.
