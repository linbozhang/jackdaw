# Asset References

A reference from one document to another — a scene naming the material a
sign wears, an instance naming the prefab it was placed from — is **a path
relative to the project's `assets/` folder**, spelled as a string inside the
document (`materials/rust.material.bsn`). No GUIDs, no meta files: the path
is the identity, and everything the editor does around references follows
from that.

## Where references live

A field holds a reference when its type is a `Handle<T>` (or a list of
them), or when the component marks it with `@AssetRef`. A prefab instance's
`IsA.source` is a reference the same way. Older documents may spell a bare
name (`@rust`) — the editor resolves it to the one file whose stem carries
that name, and two files sharing a stem make it ambiguous, which is why
paths are preferred. The paths inside a `MaterialOverrides` or
`InstanceMaterialOverrides` map are references too, and the audit walks
them with everything else: a broken override shows up as a `Missing` row
naming the component's `materials` field
([Material Overrides](material-overrides.md)).

## Rename and move follow through

When a file is renamed or moved **inside the editor** (`file.rename`,
`file.move`, or the Project window), everything that named the old path is
brought along:

- every document on disk that spelled the reference is rewritten — the
  replacement happens on the document's own structure, so a plain string
  that merely reads like the old path is never touched;
- the tabs and the inspector card standing on the file follow it to the new
  path, so the next save writes where the file landed (a clean tab stays
  clean; a tab with unsaved edits stays dirty);
- the asset index moves its entry with the same handle, so already-loaded
  assets keep rendering without a reload;
- a rename that differs only in letter case (`Rat.bsn` → `rat.bsn`) goes
  through, on filesystems that ignore case.

The status bar reports what happened: `renamed; rewrote 3 references in 2
documents`.

## Deleting

`file.delete` asks first, and the confirmation names the documents that
reference the file — the first few by name plus a count of the rest. A file
a tab has open is refused unless forced; forcing closes the tab (or the
card) before deleting, so no later save can resurrect the file. References
the tabs were still editing but had not saved are part of the confirmation's
count.

## When a reference names nothing

Run `asset.audit` (or look at the file card's **Missing References…**
button, or the `audit` tool over MCP). The audit walks every document the
project holds — an open tab with unsaved edits stands in for its file — and
lists every reference that does not resolve, with the document, entity,
component and field holding it, and what is wrong: `Missing` (no such
file), `Ambiguous` (two files share the bare name) or `MachinePath` (an
absolute path on one machine).

The **Missing References** list puts those findings on screen. Each row can
**Rebind** through the picker — the reference in the open tab's document is
rewritten to the chosen file, and the tab turns dirty until its own save —
**Locate** (bring the document forward with the entity selected), **Show**
(open the folder in the file manager) or **Copy** the reference. A document
that is not open says so on its Rebind; open it first. The list is one
of the editor's five trouble mouths — [Debugging
Errors](debugging-errors.md) maps them all.

## Renaming outside the editor

The watcher reports files that appear and vanish, but it does not guess that
a gone file and a new one are the same asset renamed — nothing outside the
editor can make that call safely. If you rename or move files in the OS file
manager:

- references in documents stay as they were spelled and now name nothing;
- run `asset.audit` afterwards to see what broke, and rebind from the
  Missing References list.

The safe path is to rename and move inside the editor, where the follow-up
is automatic.
