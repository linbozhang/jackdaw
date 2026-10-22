# Keyboard shortcuts

## Navigation

| Key | Action |
|-----|--------|
| RMB + Drag | Look around |
| WASD | Move (forward / left / back / right) |
| Q / E | Move up / down |
| Shift | Double speed |
| Scroll | Dolly forward / back |
| RMB + Scroll | Adjust move speed |
| F | Focus selected |
| Ctrl+1-9 | Save camera bookmark |
| 1-9 | Restore camera bookmark |

## Selection

| Key | Action |
|-----|--------|
| LMB | Select entity |
| Ctrl+Click | Toggle multi-select |
| Shift+LMB Drag | Box select |

## Transform

| Key | Action |
|-----|--------|
| Esc | Translate mode |
| R | Rotate mode |
| T | Scale mode |
| X | Toggle local / world space |
| M | Toggle snapping (same as the toolbar magnet) |
| MMB | Toggle snap |
| Ctrl (during drag) | Toggle snap |
| Arrows | Nudge (grid-unit move) |
| Alt+Arrows | 90 deg rotate |
| PageUp / PageDown | Nudge vertical |

## Entity

| Key | Action |
|-----|--------|
| Delete / Backspace | Delete selected |
| Ctrl+D | Duplicate |
| Ctrl+C | Copy components |
| Ctrl+V | Paste components |
| H | Toggle visibility |
| Alt+G | Reset position |
| Alt+R | Reset rotation |
| Alt+S | Reset scale |

## Brush Editing

| Key | Action |
|-----|--------|
| 1 | Vertex mode |
| 2 | Edge mode |
| 3 | Face mode |
| 4 | Clip mode |
| X / Y / Z | Constrain axis |
| Shift+Click | Multi-select |
| Delete | Delete selected element |
| PageUp/PageDown | Nudge selected vertices/edges/faces up/down |
| Enter | Apply clip plane |
| Esc | Exit brush edit |

## Brush Draw

| Key | Action |
|-----|--------|
| B | Draw brush (add) |
| C | Draw brush (cut) |
| Tab | Toggle add / cut mode |
| Click | Place vertex / advance phase |
| Enter | Close polygon |
| Backspace | Remove last vertex |
| Esc / Right-click | Cancel drawing |

## View

| Key | Action |
|-----|--------|
| Numpad 1 | Front view (orthographic, looking down +Y) |
| Numpad 3 | Right view (orthographic, looking down +X) |
| Ctrl+Numpad 3 | Left view |
| Numpad 7 | Top view (orthographic, looking down +Z) |
| Numpad 5 | Toggle perspective / orthographic |
| Home | Frame all entities |
| Ctrl+Shift+W | Toggle wireframe |
| [ | Decrease grid size |
| ] | Increase grid size |
| Ctrl+Alt+Scroll | Change grid size |

## Panels

| Key | Action |
|-----|--------|
| Shift+Space | Maximize / restore the panel under the cursor |

### Panel Maximize

Press **Shift+Space**, or click the maximize icon at the right of a
panel's tab bar, to expand that panel's tab group to fill the whole
workspace. Nothing is closed and the layout is not modified — the
other panels are only hidden for the moment:

- Press **Shift+Space** again (or click the highlighted restore icon in
  the maximized tab bar) to bring the layout back exactly as it was,
  split positions included.
- Opening a panel that would land in a hidden area (the Window menu,
  the tab bar `+`, or starting Play) restores the layout first, so the
  result of the action is always visible.
- Maximize is a view state, not part of the layout: saving while
  maximized stores the normal arrangement, and a fresh session starts
  un-maximized.
- The command palette lists the action as "Toggle Panel Maximize", and
  the key is rebindable like any other shortcut.

## File

| Key | Action |
|-----|--------|
| Ctrl+S | Save scene |
| Ctrl+O | Open scene in a new tab |
| Ctrl+T | New scene tab |
| Ctrl+Z | Undo |
| Ctrl+Shift+Z | Redo |

## Play-in-editor

| Key | Action |
|-----|--------|
| Esc | Forward to the game (opens its in-game menu) while capturing |
| Shift+Esc | Release input capture, return control to the editor |

See [Play-in-editor](play-in-editor.md) for the full workflow.
