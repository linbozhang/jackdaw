#!/bin/bash
# T25-T1 probe v3: the two tray row buttons (per-entry Save / per-entry
# Revert) clicked in the Review-handoff-opened tray. v2 proved the prompt's
# three keys and the tray footer end to end, and found the badge click does
# not open the tray — so this window opens the tray the way that works
# (stop -> Review) and drives the row buttons the C4 triage cell needs.
#
# Usage: bash loop/qa/t25-probe3.sh
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
PROJECT=/Users/zhanglinbo/workspace/loop-mac/t25-live-tuning/t25-live
PORT=15703
GAME_PORT=15702
OUTDIR="${T25_OUTDIR:-$REPO/loop/t25-live}"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
GAMEBIN="t25-live"
TRANSFORM='bevy_transform::components::transform::Transform'
ROW='Spinner / Transform.translation.y'
EDITOR_LOG="$OUTDIR/editor-probe3.log"
CONSOLE_LOG="$OUTDIR/console-probe3.log"
echo "=== probe3 run $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t25-probe3.XXXXXX)"
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
cleanup() { pkill -x jackdaw 2>/dev/null; pkill -x "$GAMEBIN" 2>/dev/null; sleep 1; }
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
wait_idle() {
  local deadline=$((SECONDS + ${1:-300}))
  while [ $SECONDS -lt $deadline ]; do
    if brp jackdaw/wait '{"until":"idle"}' | jq -e '.result.idle == true' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
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
history_depth() { brp jackdaw/history '{}' 2>/dev/null | jq -r '.result.undo_len // 0' 2>/dev/null; }
live_edits_count() { brp jackdaw/pie '{}' 2>/dev/null | jq -r '.result.live_edits // 0' 2>/dev/null; }
tree_bits_of() {
  brp jackdaw/scene_tree '{"depth":8}' 2>/dev/null | jq -r --arg n "$1" '
    def walk: if (.name? == $n) then .entity
              elif (.children? | type) == "array" then (.children[]? | walk)
              else empty end;
    (.result.tree // .tree // [])[]? | walk' 2>/dev/null | head -1
}
walk() { brp jackdaw/ui_tree '{"kind":"node","visible_only":true,"depth":80}' > "$1" 2>/dev/null; }
walk_has() { grep -qF "$1" "$2" 2>/dev/null; }
button_bits_in_row() {
  # The T24-T2 C3 resolution, generalized: find the node whose text carries
  # the row prefix, then climb its ancestors until one holds a sibling whose
  # subtree carries the button label (the tray row wraps the label in a
  # flex-grown holder, so the buttons hang off the row, the label's
  # grandparent).
  python3 - "$1" "$2" "$3" << 'PYT'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    raise SystemExit
data = data.get("result", data)
prefix, label = sys.argv[2], sys.argv[3]
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
        if isinstance(t, str) and t.startswith(prefix) and ent not in seen:
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
game_entity_bits() {
  gbrp world.query "{\"data\":{\"components\":[\"bevy_ecs::name::Name\"]}}" 2>/dev/null \
    | jq -r --arg n "$1" '[.result[]? | select(.components["bevy_ecs::name::Name"] == $n) | .entity][0]' 2>/dev/null
}
game_translation_y() {
  gbrp world.get_components "{\"entity\":\"$1\",\"components\":[\"$TRANSFORM\"]}" 2>/dev/null \
    | jq -r '.result.components["'"$TRANSFORM"'"].translation[1]
             // .result["'"$TRANSFORM"'"].translation[1] // empty' 2>/dev/null
}
pie_running() { [ "$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.pie // empty' 2>/dev/null)" = "running" ]; }
pie_stopped() { [ "$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.pie // empty' 2>/dev/null)" = "stopped" ]; }

# ---- boot (with recovery-modal dismissal) -------------------------------------
for squatter in 1 2 3 4 5; do
  pkill -x jackdaw 2>/dev/null; pkill -9 -x jackdaw 2>/dev/null; sleep 2
  [ -z "$(curl -s -m 3 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"jackdaw/status","params":{}}' 2>/dev/null)" ] && break
done
: > "$EDITOR_LOG"
export JACKDAW_OPEN_PROJECT="$PROJECT" JACKDAW_PIE_PREBUILD=0
export JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1600x1000
cd "$REPO"
nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$EDITOR_LOG" 2>&1 &
BOOT_PID=$!
ok=""
for i in $(seq 1 150); do
  sleep 2
  brp jackdaw/status '{}' >/dev/null 2>&1 && kill -0 "$BOOT_PID" 2>/dev/null && { ok=1; break; }
  kill -0 "$BOOT_PID" 2>/dev/null || break
done
[ -n "$ok" ] || { log "EDITOR_BOOT_FAIL"; exit 1; }
sleep 5
wait_idle 900 >/dev/null; sleep 3
for guard in 1 2 3; do
  walk "$OUTDIR/walk-p3-boot-recovery.json"
  grep -qF "closed unexpectedly" "$OUTDIR/walk-p3-boot-recovery.json" 2>/dev/null || break
  brp jackdaw/ui_click '{"text":"Discard All"}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
done
log "EDITOR_READY pid=$BOOT_PID"
op scene.open '{"path":"assets/t25-red.bsn","reload":true}' >/dev/null 2>&1
sleep 2; wait_idle 300 >/dev/null; sleep 1
log "--- play (warm) ---"
op pie.play_current >/dev/null 2>&1
budget 240 pie_running || { log "PROBE3_FAIL: no PIE"; exit 1; }
budget 120 [ "$(gbrp jackdaw/app_info '{}' 2>/dev/null | jq -r '.result.app_name // empty' 2>/dev/null)" != "" ] || true
sleep 3
brp jackdaw/ui_tree '{"text":"Live"}' > "$OUTDIR/p3-view.json" 2>/dev/null
VIEW_BITS=$(jq -r '.result.nodes[0].entity // empty' "$OUTDIR/p3-view.json" 2>/dev/null)
[ -n "$VIEW_BITS" ] && brp jackdaw/ui_click "{\"entity\":$VIEW_BITS}" >/dev/null 2>&1
sleep 2
GAME_BITS=$(game_entity_bits "Spinner")
log "SPINNER_GAME_BITS=$GAME_BITS disk_y_baseline=$(game_translation_y "$GAME_BITS")"

# ---- cycle R3: row Revert in the handoff-opened tray --------------------------
log "--- cycle R3: entry -> stop -> Review -> row Revert ---"
SPIN_BITS=$(tree_bits_of "Spinner")
op component.set "{\"entity\":$SPIN_BITS,\"type_path\":\"$TRANSFORM\",\"field\":\"translation.y\",\"value\":\"2.5\"}" >/dev/null 2>&1
sleep 2
[ "$(live_edits_count)" -ge 1 ] || { log "PROBE3_FAIL: no entry"; leg P3_ROW_REVERT false; leg P3_ROW_SAVE false; exit 1; }
GY_BEFORE=$(game_translation_y "$GAME_BITS")
log "entry made: game_y=$GY_BEFORE (the route streamed 2.5)"
op pie.stop >/dev/null 2>&1
budget 240 pie_stopped || true
sleep 2
walk "$OUTDIR/walk-p3-prompt.json"
click_review() { brp jackdaw/ui_click '{"text":"Review"}' 2>/dev/null | jq -e '.result.clicked == true' >/dev/null 2>&1; }
click_review && log "Review clicked" || log "Review click failed"
sleep 2
walk "$OUTDIR/walk-p3-tray.json"
walk_has "$ROW" "$OUTDIR/walk-p3-tray.json" && leg P3_HANDOFF_TRAY true || leg P3_HANDOFF_TRAY false
rev_bits=$(button_bits_in_row "$OUTDIR/walk-p3-tray.json" "$ROW" "Revert" | head -1)
log "Revert button bits: ${rev_bits:-none}"
if [ -n "$rev_bits" ]; then
  brp jackdaw/ui_click "{\"entity\":$rev_bits}" > "$OUTDIR/p3-revert-click.json" 2>/dev/null
  sleep 3
  leg P3_ROW_REVERT true
else
  leg P3_ROW_REVERT false
fi
sleep 2
log "after row Revert: live_edits=$(live_edits_count) game_y=$(game_translation_y "$GAME_BITS") (want 0 / back to the authored baseline)"
[ "$(live_edits_count)" = "0" ] && leg P3_ROW_REVERT_SETTLED true || leg P3_ROW_REVERT_SETTLED false
GY_AFTER=$(game_translation_y "$GAME_BITS")
BSN_NOW=$(scene_bsn_text)
AUTHORED_Y=$(printf '%s' "$BSN_NOW" | grep -A 6 "translation" | grep "y:" | head -1 | grep -o '[0-9.]*')
log "game_y=$GY_AFTER vs authored doc y=$AUTHORED_Y (the Revert streamed the baseline back)"
[ "$GY_AFTER" = "$AUTHORED_Y" ] && leg P3_ROW_REVERT_STREAMED_BASELINE true || leg P3_ROW_REVERT_STREAMED_BASELINE false

# ---- cycle S3: row Save in the handoff-opened tray -----------------------------
log "--- cycle S3: entry -> stop -> Review -> row Save ---"
play_probe() {
  op pie.play_current >/dev/null 2>&1
  budget 240 pie_running
}
play_probe || { log "PROBE3_FAIL: replay"; exit 1; }
sleep 3
SPIN_BITS=$(tree_bits_of "Spinner")
op component.set "{\"entity\":$SPIN_BITS,\"type_path\":\"$TRANSFORM\",\"field\":\"translation.y\",\"value\":\"5.0\"}" >/dev/null 2>&1
sleep 2
[ "$(live_edits_count)" -ge 1 ] || log "note: cycle S3 entry lagged"
BSN_BEFORE=$(sha_of "$(scene_bsn_text)")
HIST_BEFORE=$(history_depth)
op pie.stop >/dev/null 2>&1
budget 240 pie_stopped || true
sleep 2
click_review && log "Review clicked" || log "Review click failed"
sleep 2
walk "$OUTDIR/walk-p3-tray2.json"
save_bits=$(button_bits_in_row "$OUTDIR/walk-p3-tray2.json" "$ROW" "Save" | head -1)
log "Save button bits: ${save_bits:-none}"
if [ -n "$save_bits" ]; then
  brp jackdaw/ui_click "{\"entity\":$save_bits}" > "$OUTDIR/p3-save-click.json" 2>/dev/null
  sleep 3
  leg P3_ROW_SAVE true
else
  leg P3_ROW_SAVE false
fi
sleep 2
BSN_AFTER=$(sha_of "$(scene_bsn_text)")
log "after row Save: live_edits=$(live_edits_count) doc $BSN_BEFORE -> $BSN_AFTER undo $(history_depth) (want 0 / changed / +1)"
[ "$(live_edits_count)" = "0" ] && leg P3_ROW_SAVE_SETTLED true || leg P3_ROW_SAVE_SETTLED false
[ "$BSN_AFTER" != "$BSN_BEFORE" ] && leg P3_ROW_SAVE_AUTHORED true || leg P3_ROW_SAVE_AUTHORED false
[ "$(history_depth)" = "$((HIST_BEFORE + 1))" ] && leg P3_ROW_SAVE_UNDO true || leg P3_ROW_SAVE_UNDO false
grep -A 6 "translation" "$OUTDIR/walk-p3-tray2.json" >/dev/null 2>&1
scene_bsn_text > "$OUTDIR/p3-doc-after-save.txt"

# ---- census + teardown ---------------------------------------------------------
panic_n13=$(grep -c "Encountered an error in system" "$EDITOR_LOG" 2>/dev/null)
case "$panic_n13" in ''|*[!0-9]*) panic_n13=0 ;; esac
swap_n13=$(grep -c "swap_remove index" "$EDITOR_LOG" 2>/dev/null)
case "$swap_n13" in ''|*[!0-9]*) swap_n13=0 ;; esac
log "CENSUS: error-handler panics=$panic_n13 swap_remove-signature=$swap_n13 (N13 family, attributed)"
log "PROBE3 done: $(results)"
