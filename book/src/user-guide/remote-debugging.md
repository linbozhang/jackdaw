# Remote Debugging

The Remote Debug workspace is the editor's window onto a **running game**:
read-only panels that poll a live Bevy process over the Bevy Remote Protocol
and show what the game's scheduler is doing. It is the mirror image of
[Remote Control and jd mcp](../developer-guide/remote-control.md), which
drives the editor from outside; this workspace looks the other way, at a
game you launched yourself.

## Connecting a game

The game opts in by hosting Jackdaw's BRP server:

```rust
app.add_plugins(jackdaw_remote::JackdawRemotePlugin::default());
```

That serves the protocol on loopback port 15702 (`.with_port()` moves it).
Launch the game however you like, then click the connection indicator in the
editor's status bar, check the endpoint (`http://127.0.0.1:15702` by
default) and press **Connect**. The status bar names the connected game;
every debug panel polls the connection on its own cadence and falls quiet
when it drops.

The Remote Debug workspace's center column tabs the panels: **Schedules**,
**System Graph**, **Live Queries**, **Archetypes** and **Relationships**,
with the streamed entity browser and remote inspector to the sides. The
rest of this page covers the two scheduler panels.

## Schedules: run order and access badges

The Schedules panel shows one card per schedule, each listing its systems
left to right in the order they execute, with the system sets they belong
to as chips. Every system also carries a small access badge — `R2 W1` means
two component reads and one write — the same badge the System Graph shows
under its node labels:

- `R2 W1` — counts of read and written components/resources.
- `ALL` — an unbounded access: the system may touch any component.
- `EXCL` — the system takes `&mut World` and runs exclusively.

## System Graph: filtering and reverse lookup

The System Graph panel draws one schedule's systems as a layered
dependency graph: ordering edges, and scheduler **ambiguities** — pairs of
unordered systems with conflicting data access — as red edges and red node
borders. A schedule with many edges truncates the drawing and says so in
the meta line.

With access data available, the filter row under the schedule buttons
answers "which systems touch what":

- **Add component** picks component type names from the schedules' access
  tables. Picked components become chips; a system matches only when it
  accesses **every** picked component (AND). Matches are highlighted, the
  rest dimmed — the layout never changes, so neighbors keep their context.
  `ALL`/`EXCL` systems match any filter. Names match by full type path,
  with a final-segment fallback for naming that differs between registries.
- **From selection** flips the question: it takes the currently selected
  entity — the remote entity under the BRP connection if one is selected,
  otherwise the editor's own selection — and highlights every system that
  accesses **any** of its components (OR): "what could be moving this
  entity?". The meta line reports how many components the selection
  contributed. The button is disabled when nothing is selected.
- **Clear** drops the filter; clicking a chip removes just that component.

## When access data is missing

The access tables came with a specific `jackdaw_remote` version, and the
panels say which problem they hit rather than guessing:

- **Not connected** — the filter row reads *connect to a game to filter by
  component access*, and the meta line shows no schedules.
- **Connected to an older game** — the reply carries no access data, the
  filter row reads *component access data requires a newer jackdaw_remote*,
  the badges disappear and the meta line notes access data is unavailable;
  the graph itself renders exactly as it always did.

Upgrading the game's `jackdaw_remote` dependency and rebuilding is all it
takes — the protocol grew the fields; no game code changes.
