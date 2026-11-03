# Debugging Errors

When something is wrong, the editor says so out loud — one mouth per
kind of trouble, five mouths in all — and every mouth lands somewhere
you can act: a panel row, a clickable position, a selected entity, a
cursor sitting on the exact line. This chapter is the map: which mouth
speaks for which trouble, where its words show up, and the thirty-second
path from a strange line to the thing that caused it.

## The five mouths

| The trouble | What says so | Where it lands |
|---|---|---|
| A file fails to load | `asset load failed: … -- showing the previous content` in the log, and the same news as a warning banner on the status bar — once per version of the file | The **Asset load failures** section of the Scene Problems board |
| A reference names nothing | the audit's summary when a scene loads (`N references name files the project does not hold`), the `asset.audit` operator, and the file card's **Missing References…** button | The **Broken references** section of the board |
| A material override breaks | a `material override:` warning in the log and on the status bar, once per break — and the audit picks it up as a `Missing` row naming the document, entity, component and field | The same **Broken references** section |
| A build fails | the status bar reads `Build failed - click for log`, and the Build panel steps forward on its own with the whole log | The Build panel's strip: `N errors · first: src/main.rs:12:5`, one row per position with an **Open** button |
| The running game logs something | the game's own log; while it plays in the editor, the lines stream into the Game panel's strip under the frame | The strip: the newest four lines; click it to open the full scrollable list |

Three of the five land on one board. The other two land where the trouble
lives: build trouble on the Build panel, game trouble on the Game panel.

## The Scene Problems board

Open it from a scene file card's **Missing References…** button, or run
`asset.audit` (also reachable as the `audit` tool over remote control).
The board walks every document the project holds and sorts what it finds
into three sections:

- **Broken references** — one row per reference that does not resolve,
  naming the document, the entity, the component and field holding it,
  and the reference as spelled. A row's buttons: **Rebind** (pick a file
  through the picker; the open tab's document is rewritten and turns
  dirty like any edit), **Locate** (bring the document forward with the
  entity selected), **Show** (open the document's folder in the file
  manager) and **Copy** (the reference onto the clipboard). A document
  with no tab of its own is never rewritten from here — its Rebind says
  so and asks you to open it first.
- **Binding problems** — one row per wrong field or type spelling the
  last load recorded, naming the entity, the component and the field
  when there is one. Its buttons: **Locate** (select the entity) and
  **Copy** (lift the spelling). No Rebind — a type or field spelling is
  not something a file picker can rewrite; [rewrite the spelling
  itself](#what-an-unknown-type-or-field-spelling-means).
- **Asset load failures** — one row per file version that failed to
  load, with **Show** (the folder) and **Copy** (the path). The rows are
  the panel face of the log's once-per-version mouth: the same lock that
  keeps the log quiet keeps the board at one row per version, and a file
  that breaks a second way (a new version) lands a second row.

The sections stand side by side and never swallow each other: a document
that carries both a broken reference and a bad binding shows a row in
each section.

## The thirty-second checklists

**The build broke.** The Build panel is already in front of you (it
focuses itself whenever a build fails, and the status bar's `Build
failed - click for log` is a click away from it). The strip at the top
counts the errors and pins the first one — `4 errors · first:
src/lib.rs:2077:18`. Below it, one row per position; click a row's
**Open** and your code editor opens at that file, line and column — the
probe tries `code`, `code-insiders`, `vscodium`, `cursor`, `windsurf`
and `zed` in that order and uses the first one on your `PATH`; with none
of them it reveals the file's folder in the file manager instead. A warning-only build never
turns the panel red: the footer stays `Project built` and the warnings
sit readable in the log.

**A reference went dead** (a file was renamed or moved outside the
editor). Open the Scene Problems board. The **Broken references** row
names the holder; click **Locate** to jump to the entity — the document
comes forward with it selected — or **Rebind** to point the reference at
the right file through the picker. What each fix touches and when it
reaches the file is [Asset References](asset-references.md)' subject;
the thirty-second version is: Locate to see, Rebind to fix, save to keep.

**A binding is wrong** (a field the component does not have, a type
spelled somewhere the project does not register). The load's warning
already names the entity and says the scene-problems list carries the
row — so open the board and read the **Binding problems** row: entity,
component, field. **Locate** selects the entity; **Copy** lifts the
spelling so you can search for it; then fix the document by hand —
[the next section](#what-an-unknown-type-or-field-spelling-means) tells
you what the two honest fixes are.

## The game's log

A built game logs to its own console. A game playing in the editor
streams its log lines into the Game panel's strip under the frame: the
newest four lines by default, three-level colored (error red, warn
yellow, the rest calm), and a click on the strip expands it into the
full scrollable list — the editor keeps the last hundred lines — and
clicks again fold it back to four.

The stream is throttled on purpose: a game stuck in a warn-per-frame
loop must not flood the editor. Lines repeat-deduplicate over a
one-second window, at most thirty-two pass per window, and the per-frame
drain tops out at five hundred twelve. Both ceilings say so when they
bite: a line names the count (`the one-second window overflowed; N lines
were dropped until it rolls`, once per window) and the drain's overflow
replaces the tail with its own note. If your game's log reads thinner
than it should, look for those two lines first.

## What an unknown type or field spelling means

A scene document names components by their Rust path, and the path must
be one the project registers — **the definition module's path**, spelled
in full. The classic mistakes, both warned, neither silent:

- **An unknown field** — the component exists but the document names a
  field it does not have. The warning names the entity, the component
  and the field (`unknown field 'nonexistent_field' on
  '…Transform' on entity #RedField; the scene-problems list carries the
  row`), and the row lands on the board's Binding problems section. The
  rest of the component loads; the field is dropped.
- **An unknown type spelling** — often a crate-root re-export
  (`my_game::AnimationGraphRef`) where the project registers the
  definition path (`my_game::graph::AnimationGraphRef`). The warning
  says exactly that: it names the registered spelling your document's
  tail matches and tells you the move. The remedy names the two honest
  fixes — rebuild the project **only if the type is genuinely new to
  it** (a type added after the editor last built); otherwise rewrite the
  spelling to the definition path. Until one of those happens, the
  component does **not** load: the entity stands without it, and the
  board row stays until the document is fixed. The editor does not
  normalize re-exports into definition paths on its own — said plainly,
  so the absence is never a mystery.

The load's summary line (one per load, quiet on an unchanged reload)
counts the types it could not resolve and points at the board.

## Transient warnings at open time

A boundary worth knowing before you chase a ghost: **the warnings you
see in the first moments after opening a scene can be spawn-timing, and
they clear themselves**. The clearest case is material overrides — the
override report can look before all the model's parts have arrived, and
once they do, the locks clear and nothing repeats
([Material Overrides](material-overrides.md) has the detail). The same
reader's rule holds across the board: every mouth in this chapter
speaks **once per failure identity** — once per version of a file, once
per break, once per unchanged reload — so a warning that repeats is a
new failure, and one that stays after the scene settles is a real one.

## Known edges, stated as they are

- Reopening an **already-open** tab from disk does not re-speak the
  audit's load summary — that mouth rides a fresh open. The
  file-version mouth (log + Asset load failures) is not affected.
- A game that loads a scene **from its own flow** (not through the
  editor) currently drops an unknown field in silence — the editor
  warns, the game does not yet.
- A file broken **in the middle of its write** can be read twice on the
  way down and land as two rows for one logical break. Writes that
  replace the file atomically (the usual case for generated files) do
  not do this.
- The editor's own log streamer (the remote `ui_tree` walk) re-emits
  subtrees, so raw line counts over that channel can read high — count
  distinct rows, not raw lines.
- A game **connected to a PIE session** that pushes log events can trip
  a panic in the editor's event drain (a known stability ticket, shared
  with the PIE channel family).
- The end of a PIE session can leave one dangling-relationship warning
  in the editor log — leftover bookkeeping from the session's entity
  churn, harmless to the scene on disk.
- A standalone game launched **right after a PIE session closed** can
  fail to bind its remote port (the PIE game held it moments before) and
  run without its remote face. Wait a breath between closing Play and
  starting a standalone game.

## Where this sits

The board's reference half is [Asset References](asset-references.md)'s
audit; the override rows are [Material
Overrides](material-overrides.md)' broken-override story; the
load-failure mouth and what the engine keeps while a file is broken is
[Assets](assets.md)' "when a file is broken" section; the build itself —
run targets, the standalone export and what a failed export keeps — is
[Play-in-editor](play-in-editor.md)'s territory.
