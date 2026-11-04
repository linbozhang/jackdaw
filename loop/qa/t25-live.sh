#!/bin/bash
# T25-T2 live matrix: the thirteen live-tuning acceptance cells (plan
# loop/plans/t25-live-tuning.md section 2) on the Mac template fixture. The
# two narrow passes landed in T1 (LT2's component.set live route is the
# injection surface: selection.set + component.set on a projected entity;
# LT1's structural entries cover runtime component add/remove), so every
# cell here drives the green side and the LT-R1 red evidence
# (t25t1_ltr1_red.log) gets its green contrast from A1's leg.
#
# Cell map (every anchor structured: jackdaw/pie counts + projection,
# jackdaw/scene_bsn document text, jackdaw/history undo depth, ui_tree
# text/kind/disabled/rect walks, game BRP 15702 values; nothing pixel-based):
#   A1  component.set on the authored Root streams (game BRP x changes),
#       counts (live_edits=1), and dots the field row (ui_tree 8x8 dot
#       appears). Green contrast: document SHA, disk SHA and undo depth all
#       unchanged by the routed edit (red log had doc changed + undo +1 +
#       count 0 + game static). Negative half: a game-driven change (the
#       hazard's real damage, the T20 walk form; gcomp_mut assist fallback)
#       does NOT increment the ledger.
#   A2  same-field re-edit updates the one entry (count stays 1, the tray
#       diff cell's live side moves 2.0 -> 3.5); a second entity's edit
#       makes the count 2.
#   A3  a field edit on a runtime-added (unauthored) component shows the
#       (not authored) baseline; its per-entry Save lands the WHOLE
#       component patch (sibling fields carried, the N14 calibre) with one
#       undo entry. The save runs inside the play window with the tray open
#       (the Review handoff keeps TrayOpen across a replay), because the
#       stop's revert_preview regenerates the authored preview from the AST
#       alone and would leave nothing to serialize.
#   A4  component.add / component.remove stream (game BRP shows the
#       component appear / disappear) and enter the ledger as structural
#       entries (count increments; tray rows show Save enabled and Revert
#       disabled:true in the walk); the removal row's Save drops the
#       authored patch with one undo entry.
#   B1  the tray preview surface: badge count text in the walk joined with
#       the jackdaw/pie count (the LT7/A14 calibre — badge visibility is a
#       Display flip ui_tree cannot see), row label + baseline -> live diff
#       cell, and a tooltip attempt recorded (the full-value tooltip is a
#       hover popover; the synthetic surface has no hover, so the leg tries
#       a click-then-walk and archives what the walk shows).
#   B2  per-entry Revert streams the baseline back INTO THE RUNNING GAME
#       (the T1 D3 lesson: streaming assertions live in the play window),
#       decrements the count, and the field-row dot disappears.
#   B3  per-entry Save authors the document field (scene_bsn), decrements
#       the count, and pushes exactly one undo entry.
#   C1  a stop with pending edits raises the prompt titled "N live edits
#       not saved to scene" with the ledger untouched behind it.
#   C2  the Apply All five-point iron chain: Apply (the prompt key,
#       candidate-index resolved against the open tray's own footer
#       button) -> document fields change + ONE undo group -> scene.save
#       -> scene.open reload -> replay -> the game-side values equal the
#       saved ones.
#   C3  the Discard half: document SHA, disk SHA and undo depth all
#       identical, count to 0, prompt closed.
#   C4  the Review handoff + triage self-healing: Review closes the prompt
#       and opens the tray; per-row Revert then Save empty the ledger; the
#       prompt does not reappear and the tray closes with the count at 0.
#   D1  the no-autosave legs: stop with a pending edit leaves document SHA,
#       disk SHA identical and ephemeral=0; a save issued in that state
#       writes no live value to disk.
#   D2  Save to Scene both paths: Path A (authored Sun selected) lands the
#       whole-component overlay (scale/rotation carried) as ONE undo group;
#       Path B (ephemeral player selected) registers a new document node with
#       authored pose/body/collider configuration, excludes Avian's
#       session-local relationship bits and per-frame physics state, leaves
#       undo depth UNCHANGED (the LT5 v1-not-undoable note), and survives
#       save -> reload -> replay with the player in the game.
#
# LT10 assertion evolution: T2's first six T2.5 logs retain the old positive
# D2_PROMOTE_INTERNALS_LAND label. In that script revision `ColliderOf` being
# present was called PASS; after the promote filter removed it, the old grep
# printed FAIL even though d2b-doc contained the authored components and no
# relationship bits. That label is stale, not a product red. The current
# D2_PROMOTE_INTERNALS_EXCLUDED leg passes only when forbidden relationship
# bits are absent; the paired per-frame and semantic-component legs prevent
# absence from being mistaken for an empty/broken promoted node.
#
# T1 handoff notes, executed: the ancestor-climbing button resolver (the
# tray row wraps the label in a flex holder); click_label's kind=button
# candidate fallback for the prompt's text/button ambiguity, plus a rect
# pick for the two live "Apply All" buttons when the tray and the prompt
# are up together; the boot dismisses the Recovered Work modal (its scrim
# swallowed badge/tray clicks in v1) and the guard loop tolerates a
# recovered session whose document already carries authored values (the v2
# reading: judge settled, do not mis-report); Revert streaming assertions
# only inside play windows; no t25-red.sh:355 helper-name-as-variable
# construction anywhere (a helper name is not a variable — QA-2).
#
# Disciplines: one trigger source per leg; settle >= 2s around every write;
# budget-judged waits, timeouts judge FAIL; the live window shares nothing
# with the cargo gates (the `gates` phase runs standalone after the live
# windows closed — A6); disk checked before the run (15Gi bar, A9 families);
# RUST_BACKTRACE never set (the T11-T3 wgpu calibre); the N13 panic census
# rides at the end, attributed, never a leg criterion; warn-shape scan
# (SetComponent|AddComponent|swap_remove|unknown field) in the census; live
# finds go to the LT ledger only (LT8 already recorded — badge click lands
# but does not spawn the tray; new finds continue at LT9).
#
# Usage: bash loop/qa/t25-live.sh [phase]   phase: prep|live|gates|all
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
FIXROOT=/Users/zhanglinbo/workspace/loop-mac/t25-live-tuning
PROJECT="$FIXROOT/t25-live"
PORT=15703
GAME_PORT=15702
OUTDIR="${T25_OUTDIR:-$REPO/loop/t25-live}"
REPORT_TAG="${T25_REPORT_TAG:-t25t2}"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
GAMEBIN="t25-live"
TRANSFORM='bevy_transform::components::transform::Transform'
DLIGHT='bevy_light::directional_light::DirectionalLight'
NAME='bevy_ecs::name::Name'
PHEALTH='t25_live::PlayerHealth'
PMARKER='t25_live::PlayerMarker'
KB_MSG='bevy_input::keyboard::KeyboardInput'
ROW_ROOT_X='Root / Transform.translation.x'
ROW_SUN_X='Sun / Transform.translation.x'
ROW_ROOT_Z='Root / Transform.translation.z'
ROW_ROOT_Y='Root / Transform.translation.y'
ROW_SUN_Z='Sun / Transform.translation.z'
ROW_SUN_Y='Sun / Transform.translation.y'
mkdir -p "$OUTDIR"
PHASE="${1:-all}"
EDITOR_LOG="$OUTDIR/editor-live.log"
CONSOLE_LOG="$OUTDIR/console-$PHASE.log"
echo "=== phase $PHASE run $(date '+%Y-%m-%d %H:%M:%S') build=$(git -C "$REPO" rev-parse --short HEAD) ===" >> "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t25-live.XXXXXX)"
touch "$RESULTS_FILE"
log() { echo "$@" | tee -a "$CONSOLE_LOG"; }
leg() {
  case "$2" in
    true|0) r=PASS ;;
    *) r=FAIL ;;
  esac
  echo "$1=$r" >> "$RESULTS_FILE"
  log "${1}_${r}"
}
results() { sort "$RESULTS_FILE" | tr '\n' ' '; }
cleanup() {
  pkill -x jackdaw 2>/dev/null
  pkill -x "$GAMEBIN" 2>/dev/null
  sleep 1
}
trap cleanup EXIT

brp_raw() {
  local method="$1" params="${2:-}" id=$RANDOM body
  if [ -n "$params" ]; then
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params")
  else
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s"}' "$id" "$method")
  fi
  curl -s -m 60 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' -d "$body"
}
brp() {
  local method="$1" params="${2:-}" attempt out
  for attempt in 1 2 3 4 5 6 7 8; do
    out=$(brp_raw "$method" "$params")
    if [ -n "$out" ] && ! echo "$out" | grep -q "expected value at line 1"; then
      echo "$out"; return 0
    fi
    sleep 3
  done
  echo "$out"; return 1
}
gbrp() {
  local method="$1" params="${2:-}" id=$RANDOM body out attempt
  if [ -n "$params" ]; then
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params")
  else
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s"}' "$id" "$method")
  fi
  for attempt in 1 2 3; do
    out=$(curl -s -m 30 -X POST "http://127.0.0.1:$GAME_PORT/" -H 'Content-Type: application/json' -d "$body")
    if [ -n "$out" ] && ! echo "$out" | grep -q "expected value at line 1"; then
      echo "$out"; return 0
    fi
    sleep 2
  done
  echo "$out"
}
op() {
  local id="$1" params="${2:-}"
  if [ -n "$params" ]; then brp_raw jackdaw/call_operator "{\"id\":\"$id\",\"params\":$params}"
  else brp_raw jackdaw/call_operator "{\"id\":\"$id\",\"params\":{}}"; fi
}
opres() { op "$1" "$2" 2>/dev/null | jq -r '.result.result // "error"' 2>/dev/null; }
wait_idle() {
  local deadline=$((SECONDS + ${1:-300}))
  while [ $SECONDS -lt $deadline ]; do
    if brp jackdaw/wait '{"until":"idle"}' | jq -e '.result.idle == true' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}
dismiss_dialog() {
  local st
  st=$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.dialog // empty' 2>/dev/null)
  if [ -n "$st" ] && [ "$st" != "null" ]; then
    op dialog.answer '{"choice":"0"}' >/dev/null 2>&1
    sleep 2
  fi
}
port_silent() {
  [ -z "$(curl -s -m 3 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"jackdaw/status","params":{}}' 2>/dev/null)" ]
}
budget() {
  local secs="$1"; shift
  local deadline=$((SECONDS + secs))
  while [ $SECONDS -lt $deadline ]; do
    if "$@"; then return 0; fi
    sleep 1
  done
  return 1
}
scene_bsn_text() { brp jackdaw/scene_bsn '{}' 2>/dev/null | jq -r '.result.bsn // empty' 2>/dev/null; }
sha_of() { printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1; }
disk_sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
history_depth() { brp jackdaw/history '{}' 2>/dev/null | jq -r '.result.undo_len // 0' 2>/dev/null; }
live_edits_count() { brp jackdaw/pie '{}' 2>/dev/null | jq -r '.result.live_edits // 0' 2>/dev/null; }
ephemeral_count() { brp jackdaw/pie '{}' 2>/dev/null | jq -r '.result.projection.ephemeral // 0' 2>/dev/null; }
tree_bits_of() {
  brp jackdaw/scene_tree '{"depth":8}' 2>/dev/null | jq -r --arg n "$1" '
    def walk: if (.name? == $n) then .entity
              elif (.children? | type) == "array" then (.children[]? | walk)
              else empty end;
    (.result.tree // .tree // [])[]? | walk' 2>/dev/null | head -1
}
# bits_of_component <needle> — the Live tree's node carrying a component
# whose name contains the needle (the code-spawned player carries no Name;
# its scene_tree row is an "Entity NN" one with a components list).
# find_player_bits — the ephemeral player carries no Name and the editor's
# registry lacks the project's components (the scene_tree component lists
# hold engine types only), so no row can be named by component: walk the
# unnamed game-entity rows and read each one's BSN, picking the body at the
# player spawn (translation x -2.0 — the only body parked there).
find_player_bits() {
  brp jackdaw/scene_tree '{"depth":8}' > "$OUTDIR/tree-now.json" 2>/dev/null
  python3 - "$OUTDIR/tree-now.json" << 'PYT' > "$OUTDIR/player-candidates.txt" 2>/dev/null
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    raise SystemExit
def walk(node):
    comps = node.get("components", []) or []
    if node.get("name") is None and len(comps) >= 6:
        print(node.get("entity"))
    for child in node.get("children", []) or []:
        walk(child)
for root in (data.get("result", data).get("tree") or []):
    walk(root)
PYT
  local bits bsn
  while read -r bits; do
    [ -n "$bits" ] || continue
    bsn=$(brp jackdaw/entity "{\"entity\":$bits}" 2>/dev/null | jq -r '.result.bsn // empty' 2>/dev/null)
    # the diagnostics ride stderr: the caller captures stdout as the bits
    echo "  candidate $bits: $(printf '%s' "$bsn" | grep -o 'translation[^,]*' | head -1)" >&2
    if printf '%s' "$bsn" | grep -q "x: -2.0"; then
      echo "$bits"
      return 0
    fi
  done < "$OUTDIR/player-candidates.txt"
  return 1
}
walk() { brp jackdaw/ui_tree '{"kind":"node","visible_only":true,"depth":80}' > "$1" 2>/dev/null; }
walk_all() { brp jackdaw/ui_tree '{"kind":"node","visible_only":false,"depth":80}' > "$1" 2>/dev/null; }
walk_has() { grep -qF "$1" "$2" 2>/dev/null; }
click_label() { # click_label <label> — ui_click by text; on ambiguity, retry
                # against the kind=button candidate (the prompt's row texts vs
                # keys; the T1 probe form)
  local label="$1" response cand
  response=$(brp jackdaw/ui_click "{\"text\":\"$label\"}" 2>/dev/null)
  if echo "$response" | jq -e '.result.clicked == true' >/dev/null 2>&1; then
    log "click '$label': $(echo "$response" | jq -c '.result.target // .' 2>/dev/null)"
    return 0
  fi
  cand=$(echo "$response" | jq -r '.error.data.candidates // [] | to_entries[] | select(.value.kind == "button") | .key' 2>/dev/null | head -1)
  if [ -n "$cand" ]; then
    response=$(brp jackdaw/ui_click "{\"text\":\"$label\",\"index\":$cand}" 2>/dev/null)
    log "click '$label' (button candidate $cand): $(echo "$response" | jq -c '.result.target // .' 2>/dev/null)"
    echo "$response" | jq -e '.result.clicked == true' >/dev/null 2>&1
  else
    log "click '$label' failed: $response"
    return 1
  fi
}
click_label_rect() { # click_label_rect <label> <top|bottom> — disambiguate
                     # two live buttons with the same text by rect: the stop
                     # prompt is a centered modal, the tray footer hugs the
                     # hierarchy badge at the top of the hierarchy column
  local label="$1" pick="$2" response count y ent best= -1 besty
  response=$(brp jackdaw/ui_click "{\"text\":\"$label\"}" 2>/dev/null)
  if echo "$response" | jq -e '.result.clicked == true' >/dev/null 2>&1; then
    log "click '$label': $(echo "$response" | jq -c '.result.target // .' 2>/dev/null)"
    return 0
  fi
  count=$(echo "$response" | jq -r '.error.data.candidates // [] | length' 2>/dev/null)
  if [ "${count:-0}" -lt 1 ]; then
    log "click '$label' failed: $response"
    return 1
  fi
  besty=""
  for i in $(seq 0 $((count - 1))); do
    y=$(echo "$response" | jq -r ".error.data.candidates[$i].rect[1] // 0" 2>/dev/null)
    ent=$(echo "$response" | jq -r ".error.data.candidates[$i].entity // empty" 2>/dev/null)
    case "$pick" in
      top)    if [ -z "$besty" ] || awk "BEGIN{exit !($y < $besty)}" 2>/dev/null; then besty=$y; best=$i; fi ;;
      bottom) if [ -z "$besty" ] || awk "BEGIN{exit !($y > $besty)}" 2>/dev/null; then besty=$y; best=$i; fi ;;
    esac
  done
  [ -n "$best" ] || return 1
  response=$(brp jackdaw/ui_click "{\"text\":\"$label\",\"index\":$best}" 2>/dev/null)
  log "click '$label' ($pick candidate $best, y=$besty): $(echo "$response" | jq -c '.result.target // .' 2>/dev/null)"
  echo "$response" | jq -e '.result.clicked == true' >/dev/null 2>&1
}
button_bits_in_row() { # button_bits_in_row <walk.json> <row-label> <button-label>
                       # [exact] — the T24-T2 C3 resolution generalized (the
                       # tray row wraps the label in a flex-grown holder, so
                       # the resolver climbs ancestors until one holds a
                       # sibling subtree carrying the button). `exact` pins
                       # the row text to equality instead of prefix, keeping
                       # "Root / DirectionalLight" apart from
                       # "Root / DirectionalLight.illuminance".
  python3 - "$1" "$2" "$3" "${4:-}" << 'PYT'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    raise SystemExit
data = data.get("result", data)
prefix, label, exact = sys.argv[2], sys.argv[3], len(sys.argv) > 4 and sys.argv[4] == "exact"
parent = {}
def walk(node):
    for child in node.get("children", []) or []:
        parent[child.get("entity")] = node
        walk(child)
for root in data.get("nodes", []):
    walk(root)
def subtree_texts(node, acc):
    t = node.get("text")
    if isinstance(t, str):
        acc.append(t)
    for child in node.get("children", []) or []:
        subtree_texts(child, acc)
    return acc
def nodes(node):
    yield node
    for child in node.get("children", []) or []:
        yield from nodes(child)
seen = set()
for root in data.get("nodes", []):
    for node in nodes(root):
        t = node.get("text")
        ent = node.get("entity")
        if not isinstance(t, str) or ent in seen:
            continue
        hit = (t == prefix) if exact else t.startswith(prefix)
        if not hit:
            continue
        seen.add(ent)
        holder = parent.get(ent, node)
        while True:
            for child in holder.get("children", []) or []:
                if child.get("entity") == ent:
                    continue
                if label in subtree_texts(child, []):
                    print(child.get("entity"))
                    raise SystemExit
            holder = parent.get(holder.get("entity"))
            if holder is None:
                break
PYT
}
row_button_disabled() { # row_button_disabled <walk.json> <row-label> <button-label> [exact]
                        # — the disabled flag the ui_tree walk carries on the
                        # button node (the LT1 structural row's greyed Revert)
  python3 - "$1" "$2" "$3" "${4:-}" << 'PYT'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    raise SystemExit
data = data.get("result", data)
prefix, label, exact = sys.argv[2], sys.argv[3], len(sys.argv) > 4 and sys.argv[4] == "exact"
parent = {}
def walk(node):
    for child in node.get("children", []) or []:
        parent[child.get("entity")] = node
        walk(child)
for root in data.get("nodes", []):
    walk(root)
def subtree_texts(node, acc):
    t = node.get("text")
    if isinstance(t, str):
        acc.append(t)
    for child in node.get("children", []) or []:
        subtree_texts(child, acc)
    return acc
def nodes(node):
    yield node
    for child in node.get("children", []) or []:
        yield from nodes(child)
seen = set()
for root in data.get("nodes", []):
    for node in nodes(root):
        t = node.get("text")
        ent = node.get("entity")
        if not isinstance(t, str) or ent in seen:
            continue
        hit = (t == prefix) if exact else t.startswith(prefix)
        if not hit:
            continue
        seen.add(ent)
        holder = parent.get(ent, node)
        while True:
            for child in holder.get("children", []) or []:
                if child.get("entity") == ent:
                    continue
                if label in subtree_texts(child, []):
                    print("1" if child.get("disabled") else "0")
                    raise SystemExit
            holder = parent.get(holder.get("entity"))
            if holder is None:
                break
PYT
}
dot_count() { # dot_count <walk.json> — the live-edit dot's structural
              # footprint: the textless node SIBLINGS hanging beside the
              # Inspector's composite field labels (the label's parent row
              # carries the chrome nodes plus, on a tracked row, the dot's
              # wrapper). The walk's rect data is degenerate on this build
              # (plain UI nodes read 0-size), so a rect shape never matches;
              # the sibling-count differential does (2 chrome nodes idle, +1
              # with the dot wrapper up — verified on the attempt-3 walks)
  python3 - "$1" << 'PYT' 2>/dev/null
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    raise SystemExit
data = data.get("result", data)
parent = {}
def build(node):
    for child in node.get("children", []) or []:
        parent[child.get("entity")] = node
        build(child)
for root in data.get("nodes", []):
    build(root)
total = 0
seen = set()
def walk(node):
    global total
    t = node.get("text")
    ent = node.get("entity")
    if isinstance(t, str) and t in ("translation", "rotation", "scale") and ent not in seen:
        seen.add(ent)
        p = parent.get(ent)
        if p is not None:
            extras = [k for k in (p.get("children") or [])
                      if k.get("text") is None and k.get("kind") == "node"]
            total += len(extras)
    for child in node.get("children", []) or []:
        walk(child)
for root in data.get("nodes", []):
    walk(root)
print(total)
PYT
}
refresh_bits() { # every session restart invalidates the preview ids and the
                 # game ids; read them fresh
  ROOT_BITS=$(tree_bits_of "Root")
  SUN_BITS=$(tree_bits_of "Sun")
  GAME_ROOT=$(gid "Root")
  GAME_SUN=$(gid "Sun")
}
switch_view() {
  local bits
  bits=$(brp jackdaw/ui_tree "{\"text\":\"$1\"}" 2>/dev/null | jq -r '.result.nodes[0].entity // empty' 2>/dev/null)
  if [ -n "$bits" ]; then
    brp jackdaw/ui_click "{\"entity\":$bits}" >/dev/null 2>&1
    sleep 2
    log "switched to $1 view"
  else
    log "SWITCH_VIEW_FAIL: no '$1' segment"
  fi
}
pie_running() { [ "$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.pie // empty' 2>/dev/null)" = "running" ]; }
pie_stopped() { [ "$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.pie // empty' 2>/dev/null)" = "stopped" ]; }
stage_live() { [ "$(brp jackdaw/pie '{}' 2>/dev/null | jq -r '.result.instances[0].stage // empty' 2>/dev/null)" = "live" ]; }
projection_up() { # the LT2 route needs the projection populated: the scene
                  # tree's Live rows re-map onto the streamed previews only
                  # once the state deltas landed (the first run's edit went
                  # through the authored path because it fired before this)
  [ "$(brp jackdaw/pie '{}' 2>/dev/null | jq -r '.result.projection.entities // 0' 2>/dev/null)" -ge 3 ]
}
authored_mapped() { # the LT2 route maps the AUTHORED editor entity; the
                    # attempt-3 run lost this mapping on later play sessions
                    # (authored=0 while entities streamed) and every edit
                    # fell through to the authored path — the gate judges it
                    # per session and one session restart re-establishes it
  [ "$(brp jackdaw/pie '{}' 2>/dev/null | jq -r '.result.projection.authored // 0' 2>/dev/null)" -ge 2 ]
}
view_live() { [ "$(brp jackdaw/pie '{}' 2>/dev/null | jq -r '.result.view_mode // empty' 2>/dev/null)" = "live" ]; }
play_and_wait() {
  op pie.play_current >/dev/null 2>&1
  budget 300 pie_running || log "note: the pie status never read running (the stage gate below judges)"
  budget 120 [ "$(gbrp jackdaw/app_info '{}' 2>/dev/null | jq -r '.result.app_name // empty' 2>/dev/null)" != "" ] \
    || log "note: the game BRP did not answer within budget"
  budget 120 stage_live || { log "the instance stage never read live"; return 1; }
  budget 120 projection_up || { log "the projection never populated"; return 1; }
  if ! budget 30 authored_mapped; then
    log "MAPPING_DOWN: the projection streamed without the authored mapping — one session restart is the recovery"
    op pie.stop >/dev/null 2>&1
    budget 120 pie_stopped || true
    sleep 2
    op pie.play_current >/dev/null 2>&1
    budget 120 stage_live || { log "the restarted session never reached live"; return 1; }
    budget 120 projection_up || { log "the restarted projection never populated"; return 1; }
    budget 60 authored_mapped || log "MAPPING_DOWN_PERSISTS (recorded for the LT ledger; the routed edits below will fall through)"
  fi
  log "session up: $(brp jackdaw/pie '{}' 2>/dev/null | jq -c '.result.projection // .' 2>/dev/null)"
  sleep 2
  return 0
}
stop_and_wait() {
  op pie.stop >/dev/null 2>&1
  budget 240 pie_stopped || log "note: the pie ran past its stop budget"
  sleep 2
}
settle_save() { # settle_save — an explicit save so the AST and the disk
                # agree before a SHA-identity cell takes its baselines
  op scene.save >/dev/null 2>&1
  sleep 1; wait_idle 120 >/dev/null
}
# ---- game-side helpers (the T20 forms; the fixture's game BRP 15702) ----
gid() {
  gbrp world.query "{\"data\":{\"components\":[\"$NAME\"]}}" 2>/dev/null \
    | jq -r --arg n "$1" '[.result[]? | select(.components["'"$NAME"'"] == $n) | .entity][0]' 2>/dev/null
}
gcomp() {
  local id="$1" out attempt
  [ -n "$id" ] || return 0
  for attempt in 1 2 3 4; do
    out=$(gbrp world.get_components "{\"entity\":\"$id\",\"components\":[\"$2\"]}" 2>/dev/null \
      | jq -c --arg c "$2" '.result.components[$c] // .result[$c] // empty' 2>/dev/null)
    [ -n "$out" ] && { echo "$out"; return 0; }
    sleep 2
  done
  echo "$out"
}
gcomp_mut() {
  gbrp world.mutate_components "{\"entity\":\"$1\",\"component\":\"$2\",\"path\":\"$3\",\"value\":$4}" >/dev/null 2>&1
}
game_has_component() {
  gbrp world.query "{\"data\":{\"components\":[\"$1\"]}}" 2>/dev/null | jq -e '(.result | length) >= 1' >/dev/null 2>&1
}
game_translation_axis() { # game_translation_axis <id> <0|x|1|y|2|z>
  local idx case
  case "$2" in x|0) idx=0 ;; y|1) idx=1 ;; z|2) idx=2 ;; esac
  gcomp "$1" "$TRANSFORM" 2>/dev/null \
    | jq -r ".translation | if type == \"array\" then .[$idx] else .\"$2\" end // empty" 2>/dev/null
}
health_of() { gcomp "$1" "$PHEALTH" 2>/dev/null | jq -r '.current // empty' 2>/dev/null; }
GAME_WIN=""
walk_begin() {
  [ -n "$GAME_WIN" ] && return 0
  GAME_WIN=$(gbrp world.query '{"data":{"components":["bevy_window::window::Window"]}}' 2>/dev/null \
    | jq -r '.result[0].entity // empty' 2>/dev/null)
  [ -n "$GAME_WIN" ] || GAME_WIN="0"   # the windowless PIE stream still
                                       # routes events through bevy_input
  return 0
}
kb_msg() {
  gbrp world.write_message "{\"message\":\"$KB_MSG\",\"value\":{\"key_code\":\"$2\",\"logical_key\":{\"Character\":\" \"},\"state\":\"$1\",\"text\":null,\"repeat\":false,\"window\":\"$GAME_WIN\"}}" >/dev/null 2>&1
}
walk_reset() {
  local k
  for k in KeyW KeyA KeyS KeyD; do kb_msg Released "$k"; done
}
walk_axis() { # walk_axis <pid> <x|z> <target> [tol] — the T20 poll-driven
              # walk (latency-immune: hold beats stretch with the channel,
              # the coordinate is read back every beat)
  local pid="$1" axis="$2" target="$3" tol="${4:-0.35}" key cur d tries=0 n=0
  while [ "$tries" -lt 6 ]; do
    if [ "$axis" = x ]; then
      cur=$(game_translation_axis "$pid" x); key=KeyA
      d=$(awk "BEGIN{printf \"%.3f\", $target - $cur}" 2>/dev/null)
      awk "BEGIN{exit !($d > 0)}" 2>/dev/null && key=KeyD
    else
      cur=$(game_translation_axis "$pid" z); key=KeyW
      d=$(awk "BEGIN{printf \"%.3f\", $target - $cur}" 2>/dev/null)
      awk "BEGIN{exit !($d > 0)}" 2>/dev/null && key=KeyS
    fi
    case "$d" in ''|*[!0-9.+-]*) tries=$((tries + 1)); continue ;; esac
    awk "BEGIN{exit !(($d < $tol) && ($d > -$tol))}" 2>/dev/null && return 0
    walk_begin || return 1
    n=0
    while [ "$n" -lt 40 ]; do
      kb_msg Pressed "$key"
      if [ "$axis" = x ]; then cur=$(game_translation_axis "$pid" x); else cur=$(game_translation_axis "$pid" z); fi
      d=$(awk "BEGIN{printf \"%.3f\", $target - $cur}" 2>/dev/null)
      case "$d" in
        ''|*[!0-9.+-]*) n=$((n + 1)); continue ;;
      esac
      if awk "BEGIN{exit !(($d < $tol) && ($d > -$tol))}" 2>/dev/null; then
        kb_msg Released "$key"
        walk_reset
        return 0
      fi
      n=$((n + 1))
    done
    kb_msg Released "$key"
    walk_reset
    tries=$((tries + 1))
  done
  return 1
}
projection_state() { brp jackdaw/pie '{}' 2>/dev/null | jq -c '.result.projection // .' 2>/dev/null; }
# routed_edit <name> <type_path> <field> <value> — the LT2 injection surface
# with a fall-through guard. The attempt-4 run exposed a stale-binding mode:
# after in-play tray-row saves and the reload/replay cycle, the projection's
# entity_for_stable_id answers with despawned entities, the scene_tree's live
# entity is no longer in by_bits, and component.set falls through to the
# authored path (the document moves, the ledger does not — the exact red
# signature). The guard detects that signature, UNDOES the authored write
# (no document pollution), restarts the PIE session (which re-links the AST),
# re-resolves the bits and retries once.
routed_edit() {
  local name="$1" tp="$2" field="$3" value="$4" bits
  bits=$(tree_bits_of "$name")
  [ -n "$bits" ] || { log "routed_edit: no tree row for $name"; return 1; }
  local e0 u0 e1 u1
  e0=$(live_edits_count); u0=$(history_depth)
  op component.set "{\"entity\":$bits,\"type_path\":\"$tp\",\"field\":\"$field\",\"value\":\"$value\"}" >/dev/null 2>&1
  sleep 2
  e1=$(live_edits_count); u1=$(history_depth)
  if [ "${e1:-0}" = "${e0:-0}" ] && [ "${u1:-0}" != "${u0:-0}" ]; then
    log "ROUTE_FALL_THROUGH on $name ($tp.$field): state=$(projection_state) bits=$bits — undoing the authored write and restarting the session"
    op history.undo >/dev/null 2>&1
    sleep 1
    stop_and_wait
    play_and_wait || { log "routed_edit: the restarted session never came up"; return 1; }
    switch_view "Live"
    budget 60 view_live || log "note: the view mode never read live after the restart"
    sleep 1
    bits=$(tree_bits_of "$name")
    [ -n "$bits" ] || { log "routed_edit: no tree row for $name after the restart"; return 1; }
    e0=$(live_edits_count); u0=$(history_depth)
    op component.set "{\"entity\":$bits,\"type_path\":\"$tp\",\"field\":\"$field\",\"value\":\"$value\"}" >/dev/null 2>&1
    sleep 2
    e1=$(live_edits_count); u1=$(history_depth)
    if [ "${e1:-0}" = "${e0:-0}" ] && [ "${u1:-0}" != "${u0:-0}" ]; then
      log "ROUTE_FALL_THROUGH_PERSISTS on $name — undoing; the cell judges on the faces below"
      op history.undo >/dev/null 2>&1
      sleep 1
      return 1
    fi
    log "routed_edit retry landed: edits=$e1 undo=$u1 bits=$bits state=$(projection_state)"
  fi
  return 0
}
routed_add() { # routed_add <name> <type_path> — component.add with the same
               # guard (the Scene-mode fall-through pushes an undo entry too)
  local name="$1" tp="$2" bits e0 u0 e1 u1
  bits=$(tree_bits_of "$name")
  [ -n "$bits" ] || { log "routed_add: no tree row for $name"; return 1; }
  e0=$(live_edits_count); u0=$(history_depth)
  op component.add "{\"entity\":$bits,\"type_path\":\"$tp\"}" >/dev/null 2>&1
  sleep 3
  e1=$(live_edits_count); u1=$(history_depth)
  if [ "${e1:-0}" = "${e0:-0}" ] && [ "${u1:-0}" != "${u0:-0}" ]; then
    log "ROUTE_FALL_THROUGH on add($name, $tp) — undoing and restarting the session"
    op history.undo >/dev/null 2>&1
    sleep 1
    stop_and_wait
    play_and_wait || return 1
    switch_view "Live"; sleep 1
    bits=$(tree_bits_of "$name")
    [ -n "$bits" ] || return 1
    op component.add "{\"entity\":$bits,\"type_path\":\"$tp\"}" >/dev/null 2>&1
    sleep 3
  fi
  return 0
}
routed_remove() { # routed_remove <name> <type_path> — component.remove with
                  # the guard (the removal streams and ledgeres in Live; the
                  # Scene-mode fall-through drops the authored patch + undo)
  local name="$1" tp="$2" bits e0 u0 e1 u1
  bits=$(tree_bits_of "$name")
  [ -n "$bits" ] || { log "routed_remove: no tree row for $name"; return 1; }
  e0=$(live_edits_count); u0=$(history_depth)
  op component.remove "{\"entity\":$bits,\"type_path\":\"$tp\"}" >/dev/null 2>&1
  sleep 3
  e1=$(live_edits_count); u1=$(history_depth)
  if [ "${e1:-0}" = "${e0:-0}" ] && [ "${u1:-0}" != "${u0:-0}" ]; then
    log "ROUTE_FALL_THROUGH on remove($name, $tp) — undoing and restarting the session"
    op history.undo >/dev/null 2>&1
    sleep 1
    stop_and_wait
    play_and_wait || return 1
    switch_view "Live"; sleep 1
    bits=$(tree_bits_of "$name")
    [ -n "$bits" ] || return 1
    op component.remove "{\"entity\":$bits,\"type_path\":\"$tp\"}" >/dev/null 2>&1
    sleep 3
  fi
  return 0
}
open_tray_via_review() { # the tray-opening route that works (the badge click
                         # does not spawn the tray — LT8; Review hands off)
  click_label "Review"
  sleep 2
}
recover_tray_in_play() { # if the tray did not survive a replay (the TrayOpen
                         # resource resetting on a view/mode flip is the one
                         # suspect), re-run the handoff: stop -> Review ->
                         # replay carries it into the next play window
  log "note: the tray is not up in the play window — the stop->Review->replay handoff re-runs"
  stop_and_wait
  open_tray_via_review || true
  play_and_wait || return 1
  switch_view "Live"
  sleep 1
  ROOT_BITS=$(tree_bits_of "Root")
  SUN_BITS=$(tree_bits_of "Sun")
  GAME_ROOT=$(gid "Root")
  GAME_SUN=$(gid "Sun")
  walk "$OUTDIR/walk-tray-recovered.json"
  walk_has "$ROW_ROOT_X" "$OUTDIR/walk-tray-recovered.json"
}

# ---- phase: prep --------------------------------------------------------------
prep() {
  pkill -x jackdaw 2>/dev/null; pkill -x "$GAMEBIN" 2>/dev/null; sleep 1
  local free
  free=$(df -g / | awk 'NR==2 {print $4}')
  [ "$free" -ge 15 ] || { log "PREP_FAIL only ${free}Gi free; clean the disk first"; exit 1; }
  log "disk: ${free}Gi free"
  [ -d "$PROJECT" ] || { log "PREP_FAIL no fixture project at $PROJECT (T1's prep built it)"; exit 1; }
  grep -q jackdaw_remote "$PROJECT/Cargo.toml" || { log "PREP_FAIL no remote dep"; exit 1; }
  # The pristine template level with the document's stable node ids written
  # (the T1/T06 fixture form): without SceneNodeId lines the game streams its
  # entities without a node id, the projection spawns every preview as
  # ephemeral (authored=0), and the LT2 live route — which maps the AUTHORED
  # editor entity — never fires (both failed attempts missed exactly here).
  # Written fresh so a re-run starts authored-clean regardless of what an
  # earlier window saved (the T1 probe v2 lesson). The warm cargo target is
  # kept — no rm -rf.
  cat > "$PROJECT/assets/scene.bsn" << 'EOF'
// Starter scene. Authored by the jackdaw editor; safe to edit by hand.
// The game's camera is the CameraRig its code parents under the player;
// to author a fixed camera instead, use Add Entity > Scene Camera.

#Root
jackdaw_scene_types::node_id::SceneNodeId(7001)
bevy_transform::components::transform::Transform
bevy_camera::visibility::Visibility::Visible
bevy_ecs::hierarchy::Children [
    #Sun
    jackdaw_scene_types::node_id::SceneNodeId(7002)
    bevy_light::directional_light::DirectionalLight
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: 0.0, y: 8.0, z: 0.0 },
        rotation: glam::Quat { x: -0.4226183, y: 0.0, z: 0.0, w: 0.9063078 },
    }
    bevy_camera::visibility::Visibility::Visible
    --
    #Ambient
    jackdaw_scene_types::node_id::SceneNodeId(7003)
    bevy_audio::audio::AudioPlayer<bevy_audio::audio_source::AudioSource>("sounds/ambient.wav")
    bevy_audio::audio::PlaybackSettings {
        mode: bevy_audio::audio::PlaybackMode::Loop,
        volume: bevy_audio::volume::Volume::Linear(0.8),
        spatial: true,
    }
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: 6.0, y: 2.0, z: -4.0 },
    }
    bevy_camera::visibility::Visibility::Visible
]
EOF
  cp "$PROJECT/assets/scene.bsn" "$PROJECT/assets/scene.bsn.pristine"
  python3 - "$PROJECT/.jackdaw/project.json" << 'PYT'
import json, sys
path = sys.argv[1]
try:
    cfg = json.load(open(path))
    cfg.pop("layout", None)
    cfg["last_open_tabs"] = ["assets/scene.bsn"]
    cfg["last_active_tab"] = 0
    json.dump(cfg, open(path, "w"), indent=2)
except FileNotFoundError:
    pass
PYT
  (cd "$PROJECT" && cargo metadata --format-version 1 >/dev/null 2>"$OUTDIR/lockfix.log") \
    || { log "PREP_FAIL lock refresh: $(tail -2 "$OUTDIR/lockfix.log")"; exit 1; }
  log "PREP_OK fixture=$PROJECT scene=scene.bsn (pristine copy kept)"
}

# ---- phase: live (the thirteen cells, one window) ------------------------------
live() {
  # T25_WINDOWS="A B C D E" (default all) — each window is a self-contained
  # editor life, so a subset re-run produces self-contained evidence
  WANTED="${T25_WINDOWS:-A B C D E}"
  wanted() { case " $WANTED " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
  WINDOW=0
  EDITOR_LOG="$OUTDIR/editor-live-w0.log"
  kill_editor() {
    pkill -x jackdaw 2>/dev/null
    sleep 2
    pkill -9 -x jackdaw 2>/dev/null
    pkill -x "$GAMEBIN" 2>/dev/null
    sleep 2
  }
  editor_boot() {
    WINDOW=$((WINDOW + 1))
    EDITOR_LOG="$OUTDIR/editor-live-w$WINDOW.log"
    local squatter
    for squatter in 1 2 3 4 5; do
      pkill -x jackdaw 2>/dev/null
      pkill -9 -x jackdaw 2>/dev/null
      sleep 2
      port_silent && break
    done
    if ! port_silent; then
      log "EDITOR_BOOT_FAIL: an editor still answers :$PORT after five kills"; exit 1
    fi
    : > "$EDITOR_LOG"
    export JACKDAW_OPEN_PROJECT="$PROJECT"
    export JACKDAW_PIE_PREBUILD=0
    export JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1600x1000
    cd "$REPO"
    nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$EDITOR_LOG" 2>&1 &
    BOOT_PID=$!
    echo "$BOOT_PID" > "$OUTDIR/boot-pid.txt"
    local ok=""
    for i in $(seq 1 150); do
      sleep 2
      if brp jackdaw/status '{}' >/dev/null 2>&1 && kill -0 "$BOOT_PID" 2>/dev/null; then ok=1; break; fi
      kill -0 "$BOOT_PID" 2>/dev/null || break
    done
    [ -n "$ok" ] || { log "EDITOR_BOOT_FAIL"; exit 1; }
    # the pid read rides a budget: a fresh boot's BRP can answer through a
    # busy window (attempt 8 died on a single empty read right here)
    budget 90 [ "$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.pid // empty' 2>/dev/null)" = "$BOOT_PID" ] \
      || { log "EDITOR_BOOT_FAIL: the port never answered with pid $BOOT_PID"; exit 1; }
    sleep 5
    wait_idle 900 >/dev/null; sleep 3; dismiss_dialog
    # The Recovered Work modal's scrim swallows badge/tray clicks (v1's
    # lesson); its Discard All is unique at boot. A recovered document may
    # already carry authored values — the v2 precedent judges settled, the
    # cells below always re-read the live faces before asserting.
    local guard
    for guard in 1 2 3; do
      walk "$OUTDIR/walk-boot-recovery.json"
      grep -qF "closed unexpectedly" "$OUTDIR/walk-boot-recovery.json" 2>/dev/null || break
      brp jackdaw/ui_click '{"text":"Discard All"}' >/dev/null 2>&1
      sleep 2; wait_idle 120 >/dev/null
    done
    walk "$OUTDIR/walk-boot-final.json"
    if grep -qF "closed unexpectedly" "$OUTDIR/walk-boot-final.json" 2>/dev/null; then
      log "EDITOR_BOOT_FAIL: the recovery modal survived three Discard All attempts"; exit 1
    fi
    log "EDITOR_READY project=$PROJECT pid=$BOOT_PID (recovery modal clear)"
  }

  editor_boot
  op scene.open '{"path":"assets/scene.bsn","reload":true}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
  settle_save
  log "--- warm build (the game binary the PIE legs reuse) ---"
  op project.build >/dev/null 2>&1
  local warm=""
  for i in $(seq 1 90); do
    sleep 5
    if brp jackdaw/wait '{"until":"idle"}' 2>/dev/null | jq -e '.result.idle == true' >/dev/null 2>&1; then warm=1; break; fi
  done
  [ -n "$warm" ] && log "WARM_BUILD_OK" || log "WARM_BUILD_UNVERIFIED (continuing)"
  sleep 2; wait_idle 120 >/dev/null

  window_A() {
  # ============================ CYCLE 1: A1 (+ the LT-R1 green contrast) ======
  log "=== CYCLE 1: A1 — the routed live edit, its dot, the ledger, and the game-driven negative half ==="
  play_and_wait || { log "LIVE_FAIL: no PIE session for cycle 1"; exit 1; }
  switch_view "Live"
  budget 60 view_live || log "note: the view mode never read live"
  # the bits read rides AFTER the gates: the Live tree's rows re-map onto
  # the streamed previews as the projection populates
  ROOT_BITS=$(tree_bits_of "Root")
  SUN_BITS=$(tree_bits_of "Sun")
  local proj_face
  proj_face=$(brp jackdaw/pie '{}' 2>/dev/null | jq -c '.result.projection // .' 2>/dev/null)
  log "ROOT_PREVIEW_BITS=$ROOT_BITS SUN_PREVIEW_BITS=$SUN_BITS projection=$proj_face"
  local authored_n
  authored_n=$(printf '%s' "$proj_face" | jq -r '.authored // 0' 2>/dev/null)
  [ "${authored_n:-0}" -ge 2 ] && leg A1_AUTHORED_MAPPED true || leg A1_AUTHORED_MAPPED false
  [ -n "$ROOT_BITS" ] && leg A1_PROJECTION_ROOT true || leg A1_PROJECTION_ROOT false
  brp jackdaw/selection.set "{\"entities\":[$ROOT_BITS]}" > "$OUTDIR/a1-selection.json" 2>/dev/null
  sleep 1
  GAME_ROOT=$(gid "Root")
  GAME_SUN=$(gid "Sun")
  log "GAME_ROOT_BITS=$GAME_ROOT GAME_SUN_BITS=$GAME_SUN"
  local gy0 gx0 edits0 doc0 disk0 undo0 dots0 dots1 gx1
  gx0=$(game_translation_axis "$GAME_ROOT" x)
  edits0=$(live_edits_count)
  doc0=$(sha_of "$(scene_bsn_text)")
  disk0=$(disk_sha "$PROJECT/assets/scene.bsn")
  undo0=$(history_depth)
  walk "$OUTDIR/walk-a1-before.json"
  dots0=$(dot_count "$OUTDIR/walk-a1-before.json")
  log "baselines: game_x=$gx0 edits=$edits0 doc=$doc0 disk=$disk0 undo=$undo0 dot-nodes=$dots0 (want 0 / 0 / stable / stable / stable / chrome-only)"
  [ "${edits0:-1}" = "0" ] && leg A1_LEDGER_CLEAN_BEFORE true || leg A1_LEDGER_CLEAN_BEFORE false

  log "--- A1: component.set Root translation.x=2.0 (the routed injection) ---"
  routed_edit "Root" "$TRANSFORM" "translation.x" "2.0" || leg A1_ROUTE_FALL_THROUGH_RECOVERED false
  refresh_bits
  # the selection rides again after any session restart (the dot needs the
  # Inspector card up on the edited entity)
  brp jackdaw/selection.set "{\"entities\":[$ROOT_BITS]}" > "$OUTDIR/a1-selection2.json" 2>/dev/null
  sleep 1
  gx1=$(game_translation_axis "$GAME_ROOT" x)
  edits1=$(live_edits_count)
  log "after the edit: game_x=$gx1 edits=$edits1"
  awk "BEGIN{exit !($gx1 > 1.9 && $gx1 < 2.1)}" 2>/dev/null && leg A1_GAME_STREAMED true || leg A1_GAME_STREAMED false
  [ "${edits1:-0}" = "1" ] && leg A1_LEDGER_ONE true || leg A1_LEDGER_ONE false
  sleep 1
  walk "$OUTDIR/walk-a1-after.json"
  dots1=$(dot_count "$OUTDIR/walk-a1-after.json")
  log "dot nodes beside the field labels: $dots0 -> $dots1 (want +1 with the wrapper up)"
  [ "${dots1:-0}" -gt "${dots0:-0}" ] && leg A1_DOT_ON_FIELD_ROW true || leg A1_DOT_ON_FIELD_ROW false
  # the LT-R1 green contrast: the routed edit leaves the document, the disk
  # and the undo stack alone (the red log's triple silence flipped)
  local doc1 disk1 undo1
  doc1=$(sha_of "$(scene_bsn_text)")
  disk1=$(disk_sha "$PROJECT/assets/scene.bsn")
  undo1=$(history_depth)
  [ "$doc1" = "$doc0" ] && leg LTR1_GREEN_DOCUMENT_UNCHANGED true || leg LTR1_GREEN_DOCUMENT_UNCHANGED false
  [ "$disk1" = "$disk0" ] && leg LTR1_GREEN_DISK_UNCHANGED true || leg LTR1_GREEN_DISK_UNCHANGED false
  [ "$undo1" = "$undo0" ] && leg LTR1_GREEN_NO_UNDO true || leg LTR1_GREEN_NO_UNDO false

  log "--- A1 negative half: the game-driven hazard damage must not enter the ledger ---"
  local pid h0 h1 n hurt_route="walk"
  pid=$(gbrp world.query "{\"data\":{\"components\":[\"$PMARKER\"]}}" 2>/dev/null \
    | jq -r '[.result[]?][0].entity // empty' 2>/dev/null)
  log "player entity: $pid"
  # the T20 walk-calibrate lesson: at full move_speed one poll beat overshoots
  # the release window, so the measurement legs pace at 0.5 and the template
  # default goes back afterwards
  gcomp_mut "$pid" "t25_live::PlayerController" move_speed 0.5
  sleep 1
  h0=$(health_of "$pid")
  log "health before the walk: $h0  pos: x=$(game_translation_axis "$pid" x) z=$(game_translation_axis "$pid" z)"
  walk_axis "$pid" z 1.6 || log "note: the z corridor walk lagged (continuing)"
  walk_axis "$pid" x 2.3 0.2 || log "note: the x leg lagged (continuing)"
  log "at the dive start: x=$(game_translation_axis "$pid" x) z=$(game_translation_axis "$pid" z)"
  gcomp_mut "$pid" "t25_live::PlayerController" move_speed 4.0
  walk_begin
  n=0; h1=""
  while [ "$n" -lt 90 ]; do
    kb_msg Pressed KeyW
    h1=$(health_of "$pid")
    [ -n "$h1" ] && awk "BEGIN{exit !($h1 < $h0 - 0.5)}" 2>/dev/null && break
    n=$((n + 1))
  done
  kb_msg Released KeyW
  walk_reset
  walk_axis "$pid" z 1.6 || true
  gcomp_mut "$pid" "t25_live::PlayerController" move_speed 4.0
  sleep 1
  h1=""
  for n in 1 2 3; do
    h1=$(health_of "$pid")
    [ -n "$h1" ] && break
    sleep 2
  done
  log "health after the dive: $h0 -> $h1"
  if [ -z "$h1" ] || ! awk "BEGIN{exit !($h1 < $h0 - 0.5)}" 2>/dev/null; then
    hurt_route="gcomp_mut assist (the t17 form; the walk found no contact)"
    log "note: the physical walk found no contact — the game-side assist takes over"
    gcomp_mut "$pid" "$PHEALTH" current "$(awk "BEGIN{printf \"%.1f\", $h0 - 15.0}" 2>/dev/null || echo 85.0)"
    sleep 2
    h1=""
    for n in 1 2 3; do
      h1=$(health_of "$pid")
      { [ -n "$h1" ] && awk "BEGIN{exit !($h1 < $h0 - 0.5)}" 2>/dev/null; } && break
      sleep 2
    done
    log "health after the assist: $h1"
    { [ -n "$h1" ] && awk "BEGIN{exit !($h1 < $h0 - 0.5)}" 2>/dev/null; } && hurt_route="gcomp_mut assist landed"
  fi
  { [ -n "$h1" ] && awk "BEGIN{exit !($h1 < $h0 - 0.5)}" 2>/dev/null; } \
    && leg A1_NEG_GAME_CHANGED true || leg A1_NEG_GAME_CHANGED false
  log "hurt route: $hurt_route"
  echo "$hurt_route" > "$OUTDIR/a1-negative-route.txt"
  local edits_neg
  edits_neg=$(live_edits_count)
  [ "${edits_neg:-0}" = "1" ] && leg A1_NEG_LEDGER_UNCHANGED true || leg A1_NEG_LEDGER_UNCHANGED false

  log "--- stop with 1 pending edit: the prompt rises (C1 evidence, cycle 1) ---"
  local doc_pre_stop edits_pre_stop
  doc_pre_stop=$(sha_of "$(scene_bsn_text)")
  edits_pre_stop=$(live_edits_count)
  stop_and_wait
  sleep 2
  walk "$OUTDIR/walk-prompt-c1.json"
  walk_has "1 live edit not saved to scene" "$OUTDIR/walk-prompt-c1.json" && leg C1_PROMPT_TITLE true || leg C1_PROMPT_TITLE false
  for b in Review Discard "Apply All"; do
    walk_has "\"$b\"" "$OUTDIR/walk-prompt-c1.json" || log "note: the $b key is not in the prompt walk"
  done
  local edits_behind
  edits_behind=$(live_edits_count)
  { [ "${edits_behind:-0}" = "1" ] && [ "$(sha_of "$(scene_bsn_text)")" = "$doc_pre_stop" ]; } \
    && leg C1_LEDGER_UNMOVED true || leg C1_LEDGER_UNMOVED false

  log "--- Review hands off to the tray; the tray rides the replay (the C4 opening route) ---"
  open_tray_via_review || log "note: the Review click did not land cleanly"
  sleep 1
  walk "$OUTDIR/walk-tray-cycle1.json"
  # the row names the tray, not the prompt: the prompt text must be gone
  # (the prompt also lists the entry row, so row-presence alone would lie)
  { walk_has "$ROW_ROOT_X" "$OUTDIR/walk-tray-cycle1.json" \
    && ! walk_has "not saved to scene" "$OUTDIR/walk-tray-cycle1.json"; } \
    && leg A2_TRAY_OPENED true || leg A2_TRAY_OPENED false
  # the Root node authors a BARE Transform line: no field-level translation
  # exists, so the honest baseline is the (not authored) form (the Sun row's
  # explicit Vec3 patch shows the numeric form — A2_SECOND_ROW_DIFF below)
  walk_has "(not authored) -> 2.0" "$OUTDIR/walk-tray-cycle1.json" && leg A2_TRAY_DIFF_INITIAL true || leg A2_TRAY_DIFF_INITIAL false
  play_and_wait || { log "LIVE_FAIL: replay for cycle 2"; exit 1; }
  switch_view "Live"
  budget 60 view_live || log "note: the view mode never read live after the replay"
  sleep 1
  # the stop's revert_preview despawned the previous previews and the game
  # world is new: every bits read refreshes here (stale bits are the
  # one failure mode the replay carries)
  ROOT_BITS=$(tree_bits_of "Root")
  SUN_BITS=$(tree_bits_of "Sun")
  GAME_ROOT=$(gid "Root")
  GAME_SUN=$(gid "Sun")
  log "cycle-2 bits: ROOT=$ROOT_BITS SUN=$SUN_BITS GAME_ROOT=$GAME_ROOT GAME_SUN=$GAME_SUN"
  walk "$OUTDIR/walk-tray-inplay.json"
  if walk_has "$ROW_ROOT_X" "$OUTDIR/walk-tray-inplay.json"; then
    leg A2_TRAY_SURVIVES_REPLAY true
  else
    leg A2_TRAY_SURVIVES_REPLAY false
    recover_tray_in_play || { log "LIVE_FAIL: the tray never came up in a play window"; exit 1; }
  fi

  # ============================ CYCLE 2 (still the same play): A2/A3/A4/B1/B2/B3 =
  log "=== CYCLE 2: A2 re-edits, A4 structural add/remove, A3 whole-component save, B1/B2/B3 ==="
  routed_edit "Root" "$TRANSFORM" "translation.x" "3.5"
  refresh_bits
  local edits_a2
  edits_a2=$(live_edits_count)
  [ "${edits_a2:-0}" = "1" ] && leg A2_REEDIT_COUNT_STILL_ONE true || leg A2_REEDIT_COUNT_STILL_ONE false
  walk "$OUTDIR/walk-tray-a2a.json"
  walk_has "(not authored) -> 3.5" "$OUTDIR/walk-tray-a2a.json" && leg A2_TRAY_LIVE_SIDE_UPDATED true || leg A2_TRAY_LIVE_SIDE_UPDATED false
  routed_edit "Sun" "$TRANSFORM" "translation.x" "5.0"
  refresh_bits
  local edits_a2b
  edits_a2b=$(live_edits_count)
  [ "${edits_a2b:-0}" = "2" ] && leg A2_SECOND_ENTITY_COUNT_TWO true || leg A2_SECOND_ENTITY_COUNT_TWO false
  walk "$OUTDIR/walk-tray-a2b.json"
  walk_has "$ROW_SUN_X" "$OUTDIR/walk-tray-a2b.json" && leg A2_SECOND_ROW true || leg A2_SECOND_ROW false
  walk_has "0.0 -> 5.0" "$OUTDIR/walk-tray-a2b.json" && leg A2_SECOND_ROW_DIFF true || leg A2_SECOND_ROW_DIFF false

  log "--- A4: component.add DirectionalLight on Root (structural entry) ---"
  routed_add "Root" "$DLIGHT"
  refresh_bits
  sleep 1
  local gadd edits_add
  gadd=$(gcomp "$GAME_ROOT" "$DLIGHT")
  edits_add=$(live_edits_count)
  log "after add: game Root DirectionalLight=${gadd:0:80} edits=$edits_add (want present / 3)"
  [ -n "$gadd" ] && [ "$gadd" != "null" ] && leg A4_ADD_STREAMED true || leg A4_ADD_STREAMED false
  [ "${edits_add:-0}" = "3" ] && leg A4_ADD_LEDGERED true || leg A4_ADD_LEDGERED false

  log "--- A3: a field edit on the runtime-added (unauthored) component ---"
  routed_edit "Root" "$DLIGHT" "illuminance" "8000.0"
  refresh_bits
  local edits_a3
  edits_a3=$(live_edits_count)
  [ "${edits_a3:-0}" = "4" ] && leg A3_FIELD_ENTRY true || leg A3_FIELD_ENTRY false
  local gill
  gill=$(gcomp "$GAME_ROOT" "$DLIGHT" 2>/dev/null | jq -r '.illuminance // empty' 2>/dev/null)
  awk "BEGIN{exit !($gill > 7999 && $gill < 8001)}" 2>/dev/null && leg A3_GAME_VALUE true || leg A3_GAME_VALUE false
  walk "$OUTDIR/walk-tray-a3.json"
  walk_has "(not authored)" "$OUTDIR/walk-tray-a3.json" && leg A3_BASELINE_NOT_AUTHORED true || leg A3_BASELINE_NOT_AUTHORED false
  walk_has "Root / DirectionalLight.illuminance" "$OUTDIR/walk-tray-a3.json" && leg A3_ROW_LABEL true || leg A3_ROW_LABEL false

  log "--- A4: component.remove DirectionalLight on Sun (authored patch baseline) ---"
  routed_remove "Sun" "$DLIGHT"
  refresh_bits
  sleep 1
  local edits_rem
  edits_rem=$(live_edits_count)
  local sun_has
  sun_has=$(gcomp "$GAME_SUN" "$DLIGHT")
  { [ -z "$sun_has" ] || [ "$sun_has" = "null" ]; } && leg A4_REMOVE_STREAMED true || leg A4_REMOVE_STREAMED false
  [ "${edits_rem:-0}" = "5" ] && leg A4_REMOVE_LEDGERED true || leg A4_REMOVE_LEDGERED false

  log "--- tray row states: the structural rows carry Save enabled and Revert disabled:true ---"
  walk "$OUTDIR/walk-tray-structural.json"
  walk_has "$ROW_SUN_X" "$OUTDIR/walk-tray-structural.json" && leg B1_TRAY_ROWS true || leg B1_TRAY_ROWS false
  walk_has "(not authored)" "$OUTDIR/walk-tray-structural.json" && leg B1_DIFF_CELLS true || leg B1_DIFF_CELLS false
  local badge_text
  badge_text="5 edits"
  walk_has "$badge_text" "$OUTDIR/walk-tray-structural.json" && leg B1_BADGE_TEXT true || leg B1_BADGE_TEXT false
  [ "$(live_edits_count)" = "5" ] && leg B1_BADGE_COUNT_FACE true || leg B1_BADGE_COUNT_FACE false
  local rev_add save_add rev_rem save_rem
  rev_add=$(row_button_disabled "$OUTDIR/walk-tray-structural.json" "Root / DirectionalLight" "Revert" exact)
  save_add=$(row_button_disabled "$OUTDIR/walk-tray-structural.json" "Root / DirectionalLight" "Save" exact)
  rev_rem=$(row_button_disabled "$OUTDIR/walk-tray-structural.json" "Sun / DirectionalLight" "Revert" exact)
  save_rem=$(row_button_disabled "$OUTDIR/walk-tray-structural.json" "Sun / DirectionalLight" "Save" exact)
  [ "$rev_add" = "1" ] && [ "$rev_rem" = "1" ] && leg A4_STRUCTURAL_REVERT_DISABLED true || leg A4_STRUCTURAL_REVERT_DISABLED false
  [ "$save_add" = "0" ] && [ "$save_rem" = "0" ] && leg A4_STRUCTURAL_SAVE_ENABLED true || leg A4_STRUCTURAL_SAVE_ENABLED false

  log "--- B1: the tooltip attempt (hover popover; the synthetic surface has no hover) ---"
  local diff_bits
  diff_bits=$(button_bits_in_row "$OUTDIR/walk-tray-structural.json" "$ROW_ROOT_X" "3.5" | head -1)
  [ -n "$diff_bits" ] && brp jackdaw/ui_click "{\"entity\":$diff_bits}" >/dev/null 2>&1
  sleep 2
  walk "$OUTDIR/walk-tray-tooltip.json"
  if walk_has "scene:" "$OUTDIR/walk-tray-tooltip.json"; then
    leg B1_TOOLTIP_WALKED true
  else
    walk_all "$OUTDIR/walk-tray-tooltip-all.json"
    walk_has "scene:" "$OUTDIR/walk-tray-tooltip-all.json" && leg B1_TOOLTIP_WALKED true || leg B1_TOOLTIP_WALKED false
    log "note: the tooltip popover is hover-spawned (A14 family); the diff cell carries the values this leg judges"
  fi

  log "--- A3: the per-entry Save lands the WHOLE component patch (in the play window) ---"
  local doc_a3 undo_a3 edits_a3_pre
  doc_a3=$(sha_of "$(scene_bsn_text)")
  undo_a3=$(history_depth)
  edits_a3_pre=$(live_edits_count)
  local save_a3_bits
  save_a3_bits=$(button_bits_in_row "$OUTDIR/walk-tray-structural.json" "Root / DirectionalLight.illuminance" "Save" | head -1)
  if [ -n "$save_a3_bits" ]; then
    brp jackdaw/ui_click "{\"entity\":$save_a3_bits}" > "$OUTDIR/a3-save-click.json" 2>/dev/null
    sleep 3
  else
    log "note: the A3 row's Save button was not resolved from the stale walk — re-walking"
    walk "$OUTDIR/walk-tray-a3-refresh.json"
    save_a3_bits=$(button_bits_in_row "$OUTDIR/walk-tray-a3-refresh.json" "Root / DirectionalLight.illuminance" "Save" | head -1)
    [ -n "$save_a3_bits" ] && brp jackdaw/ui_click "{\"entity\":$save_a3_bits}" > "$OUTDIR/a3-save-click.json" 2>/dev/null
    sleep 3
  fi
  scene_bsn_text > "$OUTDIR/a3-doc-after-save.txt"
  local edits_a3_post undo_a3_post patch_span
  edits_a3_post=$(live_edits_count)
  undo_a3_post=$(history_depth)
  patch_span=$(python3 - "$OUTDIR/a3-doc-after-save.txt" << 'PYT' 2>/dev/null
import re, sys
text = open(sys.argv[1]).read()
i = text.find("DirectionalLight {")
if i < 0:
    print("0")
    raise SystemExit
depth = 0
end = len(text)
start = i + len("DirectionalLight ")
for k in range(start, len(text)):
    c = text[k]
    if c == '{':
        depth += 1
    elif c == '}':
        depth -= 1
        if depth == 0:
            end = k
            break
body = text[start:end]
print(len(re.findall(r"[A-Za-z_]+\s*:", body)))
PYT
)
  log "after the A3 Save: edits $edits_a3_pre -> $edits_a3_post undo $undo_a3 -> $undo_a3_post patch_fields=$patch_span (want 4 / +1 / >1)"
  [ "${edits_a3_post:-0}" = "4" ] && leg A3_SAVE_SETTLED true || leg A3_SAVE_SETTLED false
  [ "$undo_a3_post" = "$((undo_a3 + 1))" ] && leg A3_SAVE_ONE_UNDO true || leg A3_SAVE_ONE_UNDO false
  awk "BEGIN{exit !($patch_span > 1)}" 2>/dev/null && leg A3_WHOLE_COMPONENT_PATCH true || leg A3_WHOLE_COMPONENT_PATCH false
  grep -q "8000" "$OUTDIR/a3-doc-after-save.txt" && leg A3_PATCH_CARRIES_LIVE true || leg A3_PATCH_CARRIES_LIVE false

  log "--- A4: the removal row's Save drops the authored patch ---"
  local doc_a4 doc_a4_post undo_a4 undo_a4_post edits_a4_post
  doc_a4=$(sha_of "$(scene_bsn_text)")
  undo_a4=$(history_depth)
  local save_rem_bits
  walk "$OUTDIR/walk-tray-a4-refresh.json"
  save_rem_bits=$(button_bits_in_row "$OUTDIR/walk-tray-a4-refresh.json" "Sun / DirectionalLight" "Save" exact | head -1)
  [ -n "$save_rem_bits" ] && brp jackdaw/ui_click "{\"entity\":$save_rem_bits}" > "$OUTDIR/a4-save-click.json" 2>/dev/null
  sleep 3
  scene_bsn_text > "$OUTDIR/a4-doc-after-save.txt"
  edits_a4_post=$(live_edits_count)
  undo_a4_post=$(history_depth)
  python3 - "$OUTDIR/a4-doc-after-save.txt" << 'PYT' > "$OUTDIR/a4-sun-section.txt" 2>/dev/null
import re, sys
text = open(sys.argv[1]).read()
i = text.find("#Sun")
j = text.find("--", i + 1)
print(text[i:j if j > 0 else len(text)])
PYT
  log "after the removal Save: edits -> $edits_a4_post undo $undo_a4 -> $undo_a4_post"
  [ "${edits_a4_post:-0}" = "3" ] && leg A4_REMOVE_SAVE_SETTLED true || leg A4_REMOVE_SAVE_SETTLED false
  [ "$undo_a4_post" = "$((undo_a4 + 1))" ] && leg A4_REMOVE_SAVE_ONE_UNDO true || leg A4_REMOVE_SAVE_ONE_UNDO false
  grep -qF "DirectionalLight" "$OUTDIR/a4-sun-section.txt" && leg A4_PATCH_DROPPED false || leg A4_PATCH_DROPPED true

  log "--- B2: per-entry Revert streams the baseline back into the RUNNING game ---"
  brp jackdaw/selection.set "{\"entities\":[$ROOT_BITS]}" >/dev/null 2>&1
  sleep 1
  walk "$OUTDIR/walk-b2-before.json"
  local dots_b2_0 dots_b2_1
  dots_b2_0=$(dot_count "$OUTDIR/walk-b2-before.json")
  local gx_b2
  gx_b2=$(game_translation_axis "$GAME_ROOT" x)
  local rev_x_bits
  rev_x_bits=$(button_bits_in_row "$OUTDIR/walk-b2-before.json" "$ROW_ROOT_X" "Revert" | head -1)
  log "Revert button bits: ${rev_x_bits:-none}; game_x before=$gx_b2 dots=$dots_b2_0"
  if [ -n "$rev_x_bits" ]; then
    brp jackdaw/ui_click "{\"entity\":$rev_x_bits}" > "$OUTDIR/b2-revert-click.json" 2>/dev/null
    sleep 3
    leg B2_REVERT_CLICKED true
  else
    leg B2_REVERT_CLICKED false
  fi
  local gx_b2_after edits_b2
  gx_b2_after=$(game_translation_axis "$GAME_ROOT" x)
  edits_b2=$(live_edits_count)
  sleep 1
  walk "$OUTDIR/walk-b2-after.json"
  dots_b2_1=$(dot_count "$OUTDIR/walk-b2-after.json")
  log "after the Revert: game_x $gx_b2 -> $gx_b2_after edits=$edits_b2 dot nodes $dots_b2_0 -> $dots_b2_1 (want 3.5 -> 0.0 / 2 / down 1)"
  awk "BEGIN{exit !($gx_b2_after < 0.1)}" 2>/dev/null && leg B2_GAME_BASELINE_STREAMED true || leg B2_GAME_BASELINE_STREAMED false
  [ "${edits_b2:-0}" = "2" ] && leg B2_COUNT_DECREMENTED true || leg B2_COUNT_DECREMENTED false
  [ "${dots_b2_1:-0}" -lt "${dots_b2_0:-1}" ] && leg B2_DOT_GONE true || leg B2_DOT_GONE false

  log "--- B3: per-entry Save authors the field with exactly one undo entry ---"
  # a fresh edit is the B3 subject (the Sun.x entry stays pending for C2's
  # Apply All two-entry group): Sun translation.z 0.0 -> 3.0, then its row
  # Save
  routed_edit "Sun" "$TRANSFORM" "translation.z" "3.0"
  refresh_bits
  local doc_b3 undo_b3 edits_b3_pre doc_b3_post undo_b3_post edits_b3_post
  doc_b3=$(sha_of "$(scene_bsn_text)")
  undo_b3=$(history_depth)
  edits_b3_pre=$(live_edits_count)
  walk "$OUTDIR/walk-tray-b3.json"
  local save_z_bits
  save_z_bits=$(button_bits_in_row "$OUTDIR/walk-tray-b3.json" "$ROW_SUN_Z" "Save" | head -1)
  if [ -n "$save_z_bits" ]; then
    brp jackdaw/ui_click "{\"entity\":$save_z_bits}" > "$OUTDIR/b3-save-click.json" 2>/dev/null
    sleep 3
    leg B3_SAVE_CLICKED true
  else
    leg B3_SAVE_CLICKED false
  fi
  scene_bsn_text > "$OUTDIR/b3-doc-after-save.txt"
  edits_b3_post=$(live_edits_count)
  undo_b3_post=$(history_depth)
  log "after the B3 Save: edits $edits_b3_pre -> $edits_b3_post undo $undo_b3 -> $undo_b3_post (want 2 / +1)"
  [ "${edits_b3_post:-0}" = "2" ] && leg B3_COUNT_DECREMENTED true || leg B3_COUNT_DECREMENTED false
  [ "$undo_b3_post" = "$((undo_b3 + 1))" ] && leg B3_ONE_UNDO_ENTRY true || leg B3_ONE_UNDO_ENTRY false
  { [ "$(sha_of "$(scene_bsn_text)")" != "$doc_b3" ] && grep -q "z: 3.0" "$OUTDIR/b3-doc-after-save.txt"; } \
    && leg B3_DOCUMENT_AUTHORED true || leg B3_DOCUMENT_AUTHORED false

  # ---- window A ends: the ledger's shape dies with the session; the C/D
  # cells run in fresh windows (a long session's projection accumulates
  # stale entity_for_stable_id bindings — attempts 3-5 all degraded from
  # the fourth play on; a fresh boot re-links deterministically)
  kill_editor
  log "WINDOW A done (A1/A2/A3/A4/B1/B2/B3 + C1-in-motion archived)"
  }
  wanted A && window_A

  window_B() {
  # ============================ WINDOW B: C2's five-point chain ================
  log "=== WINDOW B: C2 — the Apply All five-point iron chain in a fresh session ==="
  editor_boot
  op scene.open '{"path":"assets/scene.bsn","reload":true}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
  settle_save
  play_and_wait || { log "WINDOW_B_FAIL: no PIE session"; exit 1; }
  switch_view "Live"
  budget 60 view_live || log "note: the view mode never read live"
  sleep 1
  refresh_bits
  # two fresh entries for the two-entry prompt and the one-group apply
  routed_edit "Root" "$TRANSFORM" "translation.x" "4.5"
  routed_edit "Sun" "$TRANSFORM" "translation.z" "6.0"
  refresh_bits
  brp jackdaw/selection.set "{\"entities\":[$ROOT_BITS]}" >/dev/null 2>&1
  local doc_c2_pre edits_c2_pre
  doc_c2_pre=$(sha_of "$(scene_bsn_text)")
  edits_c2_pre=$(live_edits_count)
  stop_and_wait
  sleep 2
  walk "$OUTDIR/walk-prompt-c2.json"
  walk_has "2 live edits not saved to scene" "$OUTDIR/walk-prompt-c2.json" \
    && leg C1_PROMPT_TITLE_TWO true || leg C1_PROMPT_TITLE_TWO false
  [ "$(live_edits_count)" = "$edits_c2_pre" ] && [ "$(sha_of "$(scene_bsn_text)")" = "$doc_c2_pre" ] \
    && leg C1_LEDGER_UNMOVED_TWO true || leg C1_LEDGER_UNMOVED_TWO false
  log "--- C2 point 1: Apply All (the prompt key; the tray is not up in this window, so the label is unambiguous) ---"
  local undo_c2_pre undo_c2_post doc_c2_post edits_c2_post
  undo_c2_pre=$(history_depth)
  click_label "Apply All" && leg C2_APPLY_CLICKED true || leg C2_APPLY_CLICKED false
  sleep 3
  scene_bsn_text > "$OUTDIR/c2-doc-after-apply.txt"
  doc_c2_post=$(sha_of "$(scene_bsn_text)")
  undo_c2_post=$(history_depth)
  edits_c2_post=$(live_edits_count)
  log "after Apply All: edits -> $edits_c2_post undo $undo_c2_pre -> $undo_c2_post doc changed=$([ "$doc_c2_post" != "$doc_c2_pre" ] && echo yes || echo no)"
  [ "${edits_c2_post:-1}" = "0" ] && leg C2_APPLY_SETTLED true || leg C2_APPLY_SETTLED false
  [ "$doc_c2_post" != "$doc_c2_pre" ] && leg C2_DOCUMENT_CHANGED true || leg C2_DOCUMENT_CHANGED false
  [ "$undo_c2_post" = "$((undo_c2_pre + 1))" ] && leg C2_ONE_UNDO_GROUP true || leg C2_ONE_UNDO_GROUP false
  { grep -qF "x: 4.5" "$OUTDIR/c2-doc-after-apply.txt" && grep -qF "z: 6.0" "$OUTDIR/c2-doc-after-apply.txt"; } \
    && leg C2_FIELDS_AUTHORED true || leg C2_FIELDS_AUTHORED false
  log "--- C2 point 2-3: save -> reload ---"
  local disk_c2 disk_c2_post
  disk_c2=$(disk_sha "$PROJECT/assets/scene.bsn")
  op scene.save >/dev/null 2>&1
  sleep 1; wait_idle 120 >/dev/null
  disk_c2_post=$(disk_sha "$PROJECT/assets/scene.bsn")
  [ "$disk_c2_post" != "$disk_c2" ] && leg C2_SAVE_WROTE_DISK true || leg C2_SAVE_WROTE_DISK false
  op scene.open '{"path":"assets/scene.bsn","reload":true}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
  scene_bsn_text > "$OUTDIR/c2-doc-after-reload.txt"
  { grep -qF "x: 4.5" "$OUTDIR/c2-doc-after-reload.txt" && grep -qF "z: 6.0" "$OUTDIR/c2-doc-after-reload.txt"; } \
    && leg C2_RELOAD_KEEPS true || leg C2_RELOAD_KEEPS false
  log "--- C2 points 4-5: replay; the game-side values equal the saved ones ---"
  play_and_wait || log "note: the C2 replay lagged (the assertions below judge)"
  switch_view "Live"
  budget 60 view_live || log "note: the view mode never read live after the replay"
  sleep 1
  refresh_bits
  local gx_c2 gz_sun
  gx_c2=$(game_translation_axis "$GAME_ROOT" x)
  gz_sun=$(game_translation_axis "$GAME_SUN" z)
  log "after replay: game Root x=$gx_c2 (want 4.5) game Sun z=$gz_sun (want 6.0) — the applied pair read back through save+reload+replay"
  awk "BEGIN{exit !($gx_c2 > 4.4 && $gx_c2 < 4.6)}" 2>/dev/null && leg C2_GAME_ROOT_X true || leg C2_GAME_ROOT_X false
  awk "BEGIN{exit !($gz_sun > 5.9 && $gz_sun < 6.1)}" 2>/dev/null && leg C2_GAME_SUN_Z true || leg C2_GAME_SUN_Z false
  stop_and_wait
  kill_editor
  log "WINDOW B done"
  }
  wanted B && window_B

  window_C() {
  # ============================ WINDOW C: C3 + C4 ==============================
  log "=== WINDOW C: C3 — Discard preserves the document byte for byte ==="
  editor_boot
  op scene.open '{"path":"assets/scene.bsn","reload":true}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
  settle_save
  local doc_c3 disk_c3 undo_c3
  doc_c3=$(sha_of "$(scene_bsn_text)")
  disk_c3=$(disk_sha "$PROJECT/assets/scene.bsn")
  undo_c3=$(history_depth)
  play_and_wait || log "note: the C3 play lagged"
  switch_view "Live"
  budget 60 view_live || log "note: the view mode never read live"
  sleep 1
  routed_edit "Root" "$TRANSFORM" "translation.z" "7.0"
  refresh_bits
  log "C3 entry made: edits=$(live_edits_count) (want 1)"
  stop_and_wait
  sleep 2
  walk "$OUTDIR/walk-prompt-c3.json"
  walk_has "1 live edit not saved to scene" "$OUTDIR/walk-prompt-c3.json" \
    && leg C3_PROMPT_UP true || leg C3_PROMPT_UP false
  click_label "Discard" && leg C3_DISCARD_CLICKED true || leg C3_DISCARD_CLICKED false
  sleep 3
  local doc_c3_post disk_c3_post undo_c3_post edits_c3_post
  doc_c3_post=$(sha_of "$(scene_bsn_text)")
  disk_c3_post=$(disk_sha "$PROJECT/assets/scene.bsn")
  undo_c3_post=$(history_depth)
  edits_c3_post=$(live_edits_count)
  walk "$OUTDIR/walk-prompt-c3-closed.json"
  log "after Discard: doc same=$([ "$doc_c3_post" = "$doc_c3" ] && echo yes || echo no) disk same=$([ "$disk_c3_post" = "$disk_c3" ] && echo yes || echo no) undo $undo_c3 -> $undo_c3_post edits -> $edits_c3_post"
  [ "$doc_c3_post" = "$doc_c3" ] && leg C3_DOCUMENT_IDENTICAL true || leg C3_DOCUMENT_IDENTICAL false
  [ "$disk_c3_post" = "$disk_c3" ] && leg C3_DISK_IDENTICAL true || leg C3_DISK_IDENTICAL false
  [ "$undo_c3_post" = "$undo_c3" ] && leg C3_UNTOUCHED_UNDO true || leg C3_UNTOUCHED_UNDO false
  [ "${edits_c3_post:-1}" = "0" ] && leg C3_COUNT_ZERO true || leg C3_COUNT_ZERO false
  walk_has "not saved to scene" "$OUTDIR/walk-prompt-c3-closed.json" && leg C3_PROMPT_CLOSED false || leg C3_PROMPT_CLOSED true

  log "=== WINDOW C (cont): C4 — Review opens the tray; per-row triage empties the ledger ==="
  play_and_wait || log "note: the C4 play lagged"
  switch_view "Live"
  budget 60 view_live || log "note: the view mode never read live"
  sleep 1
  routed_edit "Root" "$TRANSFORM" "translation.x" "1.5"
  routed_edit "Sun" "$TRANSFORM" "translation.z" "2.5"
  refresh_bits
  log "C4 entries made: edits=$(live_edits_count) (want 2)"
  stop_and_wait
  sleep 2
  walk "$OUTDIR/walk-prompt-c4.json"
  walk_has "2 live edits not saved to scene" "$OUTDIR/walk-prompt-c4.json" \
    && leg C4_PROMPT_UP true || leg C4_PROMPT_UP false
  click_label "Review" && leg C4_REVIEW_CLICKED true || leg C4_REVIEW_CLICKED false
  sleep 2
  walk "$OUTDIR/walk-tray-c4.json"
  { walk_has "$ROW_ROOT_X" "$OUTDIR/walk-tray-c4.json" \
    && walk_has "1.5" "$OUTDIR/walk-tray-c4.json" \
    && ! walk_has "not saved to scene" "$OUTDIR/walk-tray-c4.json"; } \
    && leg C4_HANDOFF_TRAY true || leg C4_HANDOFF_TRAY false
  # the post-stop row Revert runs the DESIGNED keep+warn branch (revert_entry
  # needs the live projection to stream the baseline into; stopped, there is
  # none — "has no live counterpart right now, keeping the entry"), so the
  # triage empties the ledger through the per-row Saves and the Revert's
  # no-op is asserted as the honest semantics
  local rev_c4 save_c4 edits_c4_mid
  rev_c4=$(button_bits_in_row "$OUTDIR/walk-tray-c4.json" "$ROW_ROOT_X" "Revert" | head -1)
  [ -n "$rev_c4" ] && brp jackdaw/ui_click "{\"entity\":$rev_c4}" > "$OUTDIR/c4-revert-click.json" 2>/dev/null
  sleep 3
  edits_c4_mid=$(live_edits_count)
  grep -q "has no live counterpart right now" "$EDITOR_LOG" 2>/dev/null \
    && [ "${edits_c4_mid:-0}" = "2" ] \
    && leg C4_REVERT_KEEPS_ENTRY true || leg C4_REVERT_KEEPS_ENTRY false
  log "after the row Revert (post-stop): edits=$edits_c4_mid (the designed keep + warn)"
  walk "$OUTDIR/walk-tray-c4-mid.json"
  save_c4=$(button_bits_in_row "$OUTDIR/walk-tray-c4-mid.json" "$ROW_ROOT_X" "Save" | head -1)
  local undo_c4 undo_c4_post
  undo_c4=$(history_depth)
  [ -n "$save_c4" ] && brp jackdaw/ui_click "{\"entity\":$save_c4}" > "$OUTDIR/c4-save-click.json" 2>/dev/null
  sleep 3
  edits_c4_mid=$(live_edits_count)   # the count after the FIRST save
  walk "$OUTDIR/walk-tray-c4-mid2.json"
  save_c4=$(button_bits_in_row "$OUTDIR/walk-tray-c4-mid2.json" "$ROW_SUN_Z" "Save" | head -1)
  [ -n "$save_c4" ] && brp jackdaw/ui_click "{\"entity\":$save_c4}" > "$OUTDIR/c4-save-click2.json" 2>/dev/null
  sleep 3
  local edits_c4_post undo_c4_post2
  edits_c4_post=$(live_edits_count)
  undo_c4_post2=$(history_depth)
  walk "$OUTDIR/walk-after-c4.json"
  log "after the row Saves: edits=$edits_c4_post undo $undo_c4 -> $undo_c4_post2 (want 0 / +2 — one entry per Save)"
  [ "${edits_c4_post:-1}" = "0" ] && leg C4_TRIAGE_SAVES_EMPTY true || leg C4_TRIAGE_SAVES_EMPTY false
  [ "${edits_c4_mid:-0}" = "1" ] && leg C4_TRIAGE_SAVE true || leg C4_TRIAGE_SAVE false
  [ "$undo_c4_post2" = "$((undo_c4 + 2))" ] && leg C4_SAVE_TWO_UNDOS true || leg C4_SAVE_TWO_UNDOS false
  { ! walk_has "not saved to scene" "$OUTDIR/walk-after-c4.json" \
    && ! walk_has "$ROW_SUN_Z" "$OUTDIR/walk-after-c4.json" \
    && ! walk_has "1 edit" "$OUTDIR/walk-after-c4.json" \
    && ! walk_has "2 edits" "$OUTDIR/walk-after-c4.json"; } \
    && leg C4_SELF_HEALED true || leg C4_SELF_HEALED false
  settle_save
  kill_editor
  log "WINDOW C done"
  }
  wanted C && window_C

  window_D() {
  # ============================ WINDOW D: D1 the no-autosave legs ==============
  log "=== WINDOW D: D1 — a stop with a pending edit leaves document, disk and ephemerals alone ==="
  editor_boot
  op scene.open '{"path":"assets/scene.bsn","reload":true}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
  settle_save
  local doc_d1 disk_d1
  doc_d1=$(sha_of "$(scene_bsn_text)")
  disk_d1=$(disk_sha "$PROJECT/assets/scene.bsn")
  play_and_wait || log "note: the D1 play lagged"
  switch_view "Live"
  budget 60 view_live || log "note: the view mode never read live"
  sleep 1
  routed_edit "Root" "$TRANSFORM" "translation.y" "9.0"
  refresh_bits
  local edits_d1
  edits_d1=$(live_edits_count)
  log "D1 entry made: edits=$edits_d1 (want 1)"
  stop_and_wait
  sleep 2
  walk "$OUTDIR/walk-prompt-d1.json"
  walk_has "1 live edit not saved to scene" "$OUTDIR/walk-prompt-d1.json" \
    && leg D1_PROMPT_UP true || leg D1_PROMPT_UP false
  local doc_d1_post disk_d1_post eph_d1_post
  doc_d1_post=$(sha_of "$(scene_bsn_text)")
  disk_d1_post=$(disk_sha "$PROJECT/assets/scene.bsn")
  # the ephemeral despawn lags the stopped status by a few frames (the
  # attempt-6 read caught 28 mid-teardown); give it a budget
  budget 30 [ "$(ephemeral_count)" = "0" ] || log "note: ephemerals never drained to 0"
  eph_d1_post=$(ephemeral_count)
  log "after the stop: doc same=$([ "$doc_d1_post" = "$doc_d1" ] && echo yes || echo no) disk same=$([ "$disk_d1_post" = "$disk_d1" ] && echo yes || echo no) ephemeral=$eph_d1_post (want yes / yes / 0)"
  [ "$doc_d1_post" = "$doc_d1" ] && leg D1_DOCUMENT_IDENTICAL true || leg D1_DOCUMENT_IDENTICAL false
  [ "$disk_d1_post" = "$disk_d1" ] && leg D1_DISK_IDENTICAL true || leg D1_DISK_IDENTICAL false
  [ "${eph_d1_post:-1}" = "0" ] && leg D1_EPHEMERAL_ZERO true || leg D1_EPHEMERAL_ZERO false
  log "--- D1: a save issued with the prompt still up writes no live value ---"
  op scene.save >/dev/null 2>&1
  sleep 1; wait_idle 120 >/dev/null
  cp "$PROJECT/assets/scene.bsn" "$OUTDIR/d1-disk-after-save.bsn"
  local doc_d1_saved
  doc_d1_saved=$(sha_of "$(scene_bsn_text)")
  grep -qF "y: 9.0" "$OUTDIR/d1-disk-after-save.bsn" && leg D1_SAVE_NO_LIVE_VALUE false || leg D1_SAVE_NO_LIVE_VALUE true
  [ "$doc_d1_saved" = "$doc_d1" ] && leg D1_SAVE_DOC_UNCHANGED true || leg D1_SAVE_DOC_UNCHANGED false
  click_label "Discard" >/dev/null 2>&1
  sleep 2
  kill_editor
  log "WINDOW D done"
  }
  wanted D && window_D

  window_E() {
  # ============================ WINDOW E: D2 the Save to Scene paths ===========
  log "=== WINDOW E: D2 — Path A (authored overlay, one undo group) and Path B (ephemeral promote, no undo) ==="
  editor_boot
  op scene.open '{"path":"assets/scene.bsn","reload":true}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
  settle_save
  play_and_wait || log "note: the D2 play lagged"
  switch_view "Live"
  sleep 1
  SUN_BITS=$(tree_bits_of "Sun")
  brp jackdaw/selection.set "{\"entities\":[$SUN_BITS]}" > "$OUTDIR/d2-selection-sun.json" 2>/dev/null
  sleep 1
  routed_edit "Sun" "$TRANSFORM" "translation.y" "6.5"
  refresh_bits
  # the overlay path reads the primary selection: re-select with the fresh
  # bits after any session restart inside routed_edit
  brp jackdaw/selection.set "{\"entities\":[$SUN_BITS]}" > "$OUTDIR/d2-selection-sun2.json" 2>/dev/null
  sleep 1
  local undo_d2a undo_d2a_post doc_d2a
  undo_d2a=$(history_depth)
  local save_scene_bits
  walk "$OUTDIR/walk-d2a.json"
  save_scene_bits=$(brp jackdaw/ui_tree '{"text":"Save to Scene"}' 2>/dev/null | jq -r '.result.nodes[0].entity // empty' 2>/dev/null)
  log "Save to Scene button bits: ${save_scene_bits:-none}"
  if [ -n "$save_scene_bits" ]; then
    brp jackdaw/ui_click "{\"entity\":$save_scene_bits}" > "$OUTDIR/d2a-save-click.json" 2>/dev/null
    sleep 3
    leg D2_PATHA_CLICKED true
  else
    leg D2_PATHA_CLICKED false
  fi
  scene_bsn_text > "$OUTDIR/d2a-doc.txt"
  undo_d2a_post=$(history_depth)
  local d2a_span
  d2a_span=$(python3 - "$OUTDIR/d2a-doc.txt" << 'PYT' 2>/dev/null
import re, sys
text = open(sys.argv[1]).read()
i = text.find("#Sun")
j = text.find("--", i + 1)
body = text[i:j if j > 0 else len(text)]
fields = len(re.findall(r"(translation|rotation|scale)", body))
print(fields)
PYT
)
  log "Path A: undo $undo_d2a -> $undo_d2a_post transform_keywords=$d2a_span (want +1 exactly; >=3 = the whole component landed)"
  [ "$undo_d2a_post" = "$((undo_d2a + 1))" ] && leg D2_PATHA_ONE_UNDO true || leg D2_PATHA_ONE_UNDO false
  awk "BEGIN{exit !($d2a_span >= 3)}" 2>/dev/null && leg D2_PATHA_WHOLE_COMPONENT true || leg D2_PATHA_WHOLE_COMPONENT false
  grep -q "y: 6.5" "$OUTDIR/d2a-doc.txt" && leg D2_PATHA_LIVE_VALUE true || leg D2_PATHA_LIVE_VALUE false

  log "--- Path B: the ephemeral player promotes to a new document node ---"
  brp jackdaw/selection.set '{"clear":true}' >/dev/null 2>&1
  sleep 1
  PLAYER_BITS=$(find_player_bits)
  log "player preview bits: ${PLAYER_BITS:-none}"
  [ -n "$PLAYER_BITS" ] && leg D2_PLAYER_SELECTED_FACE true || leg D2_PLAYER_SELECTED_FACE false
  brp jackdaw/selection.set "{\"entities\":[$PLAYER_BITS]}" > "$OUTDIR/d2-selection-player.json" 2>/dev/null
  sleep 1
  local eph_b undo_b doc_len_b
  local d2_runtime_state_re='avian3d::(physics_transform::(transform::)?(Position|Rotation|PreSolveDeltaPosition|PreSolveDeltaRotation)|dynamics::(integrator::VelocityIntegrationData|rigid_body::(LinearVelocity|AngularVelocity|sleeping::(Sleeping|SleepTimer)|forces::AccumulatedLocalAcceleration|mass_properties::components::computed::Computed(Mass|AngularInertia|CenterOfMass)|mass_properties::components::collider::ColliderMassProperties))|collision::collider::(ColliderAabb|EnlargedAabb|collider_transform::ColliderTransform))([ (]|$)'
  eph_b=$(ephemeral_count)
  undo_b=$(history_depth)
  walk "$OUTDIR/walk-d2b.json"
  save_scene_bits=$(brp jackdaw/ui_tree '{"text":"Save to Scene"}' 2>/dev/null | jq -r '.result.nodes[0].entity // empty' 2>/dev/null)
  [ -n "$save_scene_bits" ] && brp jackdaw/ui_click "{\"entity\":$save_scene_bits}" > "$OUTDIR/d2b-save-click.json" 2>/dev/null
  sleep 3
  scene_bsn_text > "$OUTDIR/d2b-doc.txt"
  local eph_b_post undo_b_post
  eph_b_post=$(ephemeral_count)
  undo_b_post=$(history_depth)
  log "Path B: ephemeral $eph_b -> $eph_b_post undo $undo_b -> $undo_b_post (want -1 / unchanged — the LT5 v1 note)"
  { [ -n "$eph_b" ] && [ -n "$eph_b_post" ] && [ "$eph_b_post" = "$((eph_b - 1))" ]; } \
    && leg D2_PATHB_EPHEMERAL_DROPPED true || leg D2_PATHB_EPHEMERAL_DROPPED false
  [ "$undo_b_post" = "$undo_b" ] && leg D2_PATHB_NOT_UNDOABLE true || leg D2_PATHB_NOT_UNDOABLE false
  # The editor registry lacks project-specific game types, so the player
  # marker is its authored AvianCollider capsule rather than PlayerHealth.
  grep -qF "ColliderConstructor::Capsule" "$OUTDIR/d2b-doc.txt" && leg D2_PATHB_NODE_IN_DOC true || leg D2_PATHB_NODE_IN_DOC false
  if grep -qF "bevy_transform::components::transform::Transform" "$OUTDIR/d2b-doc.txt" \
    && grep -qF "avian3d::dynamics::rigid_body::RigidBody::Kinematic" "$OUTDIR/d2b-doc.txt" \
    && grep -qF "ColliderDensity" "$OUTDIR/d2b-doc.txt" \
    && grep -qF "ColliderAabbMargin" "$OUTDIR/d2b-doc.txt" \
    && grep -qF "CollisionLayers" "$OUTDIR/d2b-doc.txt" \
    && grep -qF "SleepThreshold" "$OUTDIR/d2b-doc.txt" \
    && grep -qF "jackdaw_avian_integration::AvianCollider" "$OUTDIR/d2b-doc.txt" \
    && grep -qF "ColliderConstructor::Capsule" "$OUTDIR/d2b-doc.txt"; then
    leg D2_PROMOTE_SEMANTIC_COMPONENTS true
  else
    leg D2_PROMOTE_SEMANTIC_COMPONENTS false
  fi
  if grep -Eq 'ColliderOf|RigidBodyColliders' "$OUTDIR/d2b-doc.txt"; then
    leg D2_PROMOTE_INTERNALS_EXCLUDED false
  else
    leg D2_PROMOTE_INTERNALS_EXCLUDED true
  fi
  if grep -Eq "$d2_runtime_state_re" "$OUTDIR/d2b-doc.txt"; then
    leg D2_PROMOTE_PER_FRAME_EXCLUDED false
  else
    leg D2_PROMOTE_PER_FRAME_EXCLUDED true
  fi
  stop_and_wait
  walk "$OUTDIR/walk-prompt-d2.json"
  walk_has "live edit not saved to scene" "$OUTDIR/walk-prompt-d2.json" && log "note: a leftover entry raised the prompt; Discard cleans it" || true
  click_label "Discard" >/dev/null 2>&1
  sleep 2
  log "--- D2 closing chain: save -> reload -> replay -> the player is in the game ---"
  op scene.save >/dev/null 2>&1
  sleep 1; wait_idle 120 >/dev/null
  if grep -qF "ColliderConstructor::Capsule" "$PROJECT/assets/scene.bsn" \
    && grep -qF "bevy_transform::components::transform::Transform" "$PROJECT/assets/scene.bsn" \
    && grep -qF "avian3d::dynamics::rigid_body::RigidBody::Kinematic" "$PROJECT/assets/scene.bsn" \
    && grep -qF "ColliderDensity" "$PROJECT/assets/scene.bsn" \
    && grep -qF "ColliderAabbMargin" "$PROJECT/assets/scene.bsn" \
    && grep -qF "CollisionLayers" "$PROJECT/assets/scene.bsn" \
    && grep -qF "SleepThreshold" "$PROJECT/assets/scene.bsn"; then
    leg D2_DISK_HAS_PLAYER true
  else
    leg D2_DISK_HAS_PLAYER false
  fi
  if grep -Eq 'ColliderOf|RigidBodyColliders' "$PROJECT/assets/scene.bsn"; then
    leg D2_DISK_PROMOTE_INTERNALS_EXCLUDED false
  else
    leg D2_DISK_PROMOTE_INTERNALS_EXCLUDED true
  fi
  if grep -Eq "$d2_runtime_state_re" "$PROJECT/assets/scene.bsn"; then
    leg D2_DISK_PER_FRAME_EXCLUDED false
  else
    leg D2_DISK_PER_FRAME_EXCLUDED true
  fi
  op scene.open '{"path":"assets/scene.bsn","reload":true}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
  play_and_wait || log "note: the D2 replay lagged"
  switch_view "Live"
  sleep 2
  local players_d2 phealth_d2 suny_d2
  players_d2=$(gbrp world.query "{\"data\":{\"components\":[\"$PMARKER\"]}}" 2>/dev/null | jq -r '.result | length' 2>/dev/null)
  phealth_d2=$(gbrp world.query "{\"data\":{\"components\":[\"$PHEALTH\"]}}" 2>/dev/null | jq -r '[.result[]?][0].components["'"$PHEALTH"'"].current // empty' 2>/dev/null)
  SUN_BITS=$(tree_bits_of "Sun")
  GAME_SUN=$(gid "Sun")
  suny_d2=$(game_translation_axis "$GAME_SUN" y)
  log "after the replay: players=$players_d2 health.current=$phealth_d2 game Sun y=$suny_d2 (want >=1 / coherent / 6.5)"
  [ "${players_d2:-0}" -ge 1 ] && leg D2_REPLAY_PLAYER_IN_GAME true || leg D2_REPLAY_PLAYER_IN_GAME false
  [ -n "$phealth_d2" ] && leg D2_REPLAY_HEALTH_PRESENT true || leg D2_REPLAY_HEALTH_PRESENT false
  awk "BEGIN{exit !($suny_d2 > 6.4 && $suny_d2 < 6.6)}" 2>/dev/null && leg D2_REPLAY_SUN_Y true || leg D2_REPLAY_SUN_Y false
  # LT10 is the failed relationship apply/construct panic. The generic
  # "Entity has no BSN representation" warning is not this panic (the
  # Path A overlay can emit it) and remains visible in the editor log.
  # N13 swap_remove panics are census noise and remain separately attributed.
  if grep -Eq "create an instance of .*ColliderOf|create an instance of .*RigidBodyColliders|does not fit bevy_ecs::entity::Entity" "$EDITOR_LOG"; then
    leg D2_NO_LT10_LOAD_PANIC false
  else
    leg D2_NO_LT10_LOAD_PANIC true
  fi
  stop_and_wait

  kill_editor
  log "WINDOW E done"
  }
  wanted E && window_E

  # ---- epilogue: restore the pristine level so the next window starts clean --
  log "--- epilogue: restore the pristine scene.bsn ---"
  if [ -f "$PROJECT/assets/scene.bsn.pristine" ]; then
    cp "$PROJECT/assets/scene.bsn.pristine" "$PROJECT/assets/scene.bsn"
    log "pristine scene restored on disk"
  fi

  # ---- census + teardown -------------------------------------------------------
  sleep 1; pkill -x "$GAMEBIN" 2>/dev/null; sleep 2
  local panic_n13 swap_n13 wlog
  panic_n13=0; swap_n13=0
  : > "$OUTDIR/census-live.txt"
  : > "$OUTDIR/warns-live.txt"
  for wlog in "$OUTDIR"/editor-live-w*.log; do
    [ -f "$wlog" ] || continue
    local p s
    p=$(grep -c "Encountered an error in system" "$wlog" 2>/dev/null)
    s=$(grep -c "swap_remove index" "$wlog" 2>/dev/null)
    case "$p" in ''|*[!0-9]*) p=0 ;; esac
    case "$s" in ''|*[!0-9]*) s=0 ;; esac
    panic_n13=$((panic_n13 + p))
    swap_n13=$((swap_n13 + s))
    echo "--- $wlog panics=$p swap_remove=$s ---" >> "$OUTDIR/census-live.txt"
    grep -E "Encountered an error in system|swap_remove index" "$wlog" >> "$OUTDIR/census-live.txt" 2>/dev/null
    grep -E "WARN|warn" "$wlog" >> "$OUTDIR/warns-live.txt" 2>/dev/null
  done
  log "CENSUS: error-handler panics=$panic_n13 swap_remove-signature=$swap_n13 across $WINDOW windows (N13 family, attributed; ~5-6/cycle is the baseline)"
  local setwarn addwarn unkfield skipwarn
  setwarn=$(grep -cE "SetComponent|AddComponent" "$OUTDIR/warns-live.txt" 2>/dev/null)
  unkfield=$(grep -c "unknown field" "$OUTDIR/warns-live.txt" 2>/dev/null)
  skipwarn=$(grep -c "field write skipped" "$OUTDIR/warns-live.txt" 2>/dev/null)
  case "$setwarn" in ''|*[!0-9]*) setwarn=0 ;; esac
  case "$unkfield" in ''|*[!0-9]*) unkfield=0 ;; esac
  case "$skipwarn" in ''|*[!0-9]*) skipwarn=0 ;; esac
  log "WARN-SHAPES: SetComponent|AddComponent=$setwarn unknown-field=$unkfield field-write-skipped=$skipwarn (the green run expects zeros — the game-side failure mouths never spoke)"
  log "LIVE done: $(results)"
}

# ---- phase: gates (A6: never shares a window with the live legs) ----------------
gates() {
  pkill -x jackdaw 2>/dev/null; pkill -x "$GAMEBIN" 2>/dev/null; sleep 2
  local free
  free=$(df -g / | awk 'NR==2 {print $4}')
  [ "$free" -ge 15 ] || { log "GATES_FAIL only ${free}Gi free"; exit 1; }
  log "gates: disk ${free}Gi; RUST_BACKTRACE=${RUST_BACKTRACE:-<unset>}"
  cd "$REPO"
  cargo fmt --all -- --check > "$OUTDIR/$REPORT_TAG-gates-fmt.log" 2>&1
  log "fmt EXIT=$? (zero output is the passing calibre; archived)"
  cargo clippy --workspace --all-targets --features dylib -- -D warnings > "$OUTDIR/$REPORT_TAG-gates-clippy-ws.log" 2>&1
  log "clippy ws EXIT=$? ($(wc -l < "$OUTDIR/$REPORT_TAG-gates-clippy-ws.log" | tr -d ' ') lines)"
  cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings > "$OUTDIR/$REPORT_TAG-gates-clippy-phys.log" 2>&1
  log "clippy physics EXIT=$? ($(wc -l < "$OUTDIR/$REPORT_TAG-gates-clippy-phys.log" | tr -d ' ') lines)"
  cargo test --workspace --lib > "$OUTDIR/$REPORT_TAG-gates-libtests.log" 2>&1
  log "libtests EXIT=$? ($(grep -hE '^test result:' "$OUTDIR/$REPORT_TAG-gates-libtests.log" | awk '{p+=$4} END {print p" passed"}'))"
  cargo test -p jackdaw --test guards > "$OUTDIR/$REPORT_TAG-guards.log" 2>&1
  log "guards EXIT=$? ($(grep -hE '^test result:' "$OUTDIR/$REPORT_TAG-guards.log" | awk '{p+=$4} END {print p" passed"}'))"
  log "GATES done"
}

case "$PHASE" in
  prep) prep ;;
  live) live ;;
  gates) gates ;;
  all)
    prep
    live
    log "ALL done"
    ;;
  *) log "unknown phase $PHASE"; exit 2 ;;
esac
log "PHASE_DONE $PHASE results: $(results)"
