#!/bin/bash
# T25-T1 reachability probe (decision 6(a) premise): the Live Changes tray
# rows and the stop prompt's three keys, driven by jackdaw/ui_click with the
# T24-T2 C3 row-text-parent resolution. Zero product change — the probe
# rides the LT2 fix's injection surface (selection.set + component.set on a
# projected entity) to produce real ledger entries, which the pre-fix build
# could not (N11; see t25t1_ltr2_red.log — the D1 sequencing note).
#
# Button kinds covered:
#   badge chip ("1 edit")             -> toggles the tray open
#   tray row per-entry Revert         -> baseline streams back, count 0
#   tray row per-entry Save           -> document authored, count 0
#   stop prompt "Apply All"           -> document authored, count 0, prompt closed
#   stop prompt "Discard"             -> count 0, prompt closed, document identical
#   stop prompt "Review"              -> prompt closed, tray opened (handoff)
#   tray footer "Apply All"           -> document authored, count 0
#
# First-run lesson (v1 walked with the Recovered Work modal still up, whose
# scrim swallowed every badge/tray click while the prompt's GlobalZ-210
# buttons still landed): the boot now dismisses the recovery modal before
# any leg, and the row label needle is the projected entity's real name
# (Spinner, not the authored editor name).
#
# Disciplines: settle >= 2s around every click; budget-judged waits; this
# probe shares no window with the cargo gates; RUST_BACKTRACE never set;
# N13 census attribution at the end (not a leg criterion).
#
# Usage: bash loop/qa/t25-probe.sh
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
mkdir -p "$OUTDIR"
EDITOR_LOG="$OUTDIR/editor-probe.log"
CONSOLE_LOG="$OUTDIR/console-probe.log"
echo "=== probe run $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t25-probe.XXXXXX)"
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
editor_boot() {
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
  local boot_pid=$!
  echo "$boot_pid" > "$OUTDIR/probe-boot-pid.txt"
  local ok=""
  for i in $(seq 1 150); do
    sleep 2
    if brp jackdaw/status '{}' >/dev/null 2>&1 && kill -0 "$boot_pid" 2>/dev/null; then ok=1; break; fi
    kill -0 "$boot_pid" 2>/dev/null || break
  done
  [ -n "$ok" ] || { log "EDITOR_BOOT_FAIL"; exit 1; }
  local answer_pid
  answer_pid=$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.pid // empty' 2>/dev/null)
  [ "$answer_pid" = "$boot_pid" ] || { log "EDITOR_BOOT_FAIL: pid mismatch ($answer_pid vs $boot_pid)"; exit 1; }
  sleep 5
  wait_idle 900 >/dev/null; sleep 3; dismiss_dialog
  # The recovery modal (the red window's editor died holding the authored
  # document) puts a scrim over every tray/badge click; dismiss it before any
  # leg. Its Discard All is unique at boot (no tray or prompt is up).
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
  log "EDITOR_READY project=$PROJECT pid=$boot_pid (recovery modal clear)"
}
open_scene() {
  op scene.open "{\"path\":\"$1\",\"reload\":true}" >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
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
# click_label <json-locator-name> <label> — ui_click by text; on the "2
# candidates" ambiguity error, retry against the kind=button candidate.
click_label() {
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
button_bits_in_row() { # the T24-T2 C3 resolution, generalized: the row
                       # text's ancestors, climbed until one holds a sibling
                       # whose subtree carries the label (the tray row wraps
                       # the label in a flex-grown holder)
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
make_entry() { # make_entry <y> — one routed live edit on the projected Spinner
  local bits
  bits=$(tree_bits_of "Spinner")
  [ -n "$bits" ] || { log "make_entry: no projected Spinner"; return 1; }
  op component.set "{\"entity\":$bits,\"type_path\":\"$TRANSFORM\",\"field\":\"translation.y\",\"value\":\"$1\"}" >/dev/null 2>&1
  sleep 2
  [ "$(live_edits_count)" -ge 1 ]
}
play_and_wait() {
  op pie.play_current >/dev/null 2>&1
  budget 240 pie_running || { log "the pie never ran"; return 1; }
  budget 120 [ "$(gbrp jackdaw/app_info '{}' 2>/dev/null | jq -r '.result.app_name // empty' 2>/dev/null)" != "" ] \
    || log "note: the game BRP did not answer within budget"
  sleep 3
  return 0
}
stop_and_wait() {
  op pie.stop >/dev/null 2>&1
  budget 240 pie_stopped || log "note: the pie ran past its stop budget (the kill below closes it)"
  sleep 2
}
fail_all_legs() {
  for l in PROBE_INJECTION PROBE_BADGE PROBE_BADGE_OPENS_TRAY PROBE_TRAY_ROW PROBE_TRAY_DIFF_TEXT \
           PROBE_ROW_REVERT PROBE_ROW_REVERT_STREAMED PROBE_ROW_SAVE PROBE_ROW_SAVE_AUTHORED \
           PROBE_PROMPT_TITLE PROBE_PROMPT_APPLY_ALL PROBE_PROMPT_APPLY_ALL_AUTHORED PROBE_PROMPT_CLOSED \
           PROBE_PROMPT_DISCARD PROBE_PROMPT_DISCARD_PRESERVES_DOC PROBE_PROMPT_REVIEW PROBE_REVIEW_HANDOFF_TRAY \
           PROBE_FOOTER_APPLY_ALL PROBE_FOOTER_APPLY_ALL_AUTHORED; do
    leg "$l" false
  done
}

# ---- probe --------------------------------------------------------------------
editor_boot
open_scene "assets/t25-red.bsn"
op scene.save >/dev/null 2>&1
sleep 1
log "--- warm build + play ---"
op project.build >/dev/null 2>&1
for i in $(seq 1 60); do
  sleep 5
  brp jackdaw/wait '{"until":"idle"}' 2>/dev/null | jq -e '.result.idle == true' >/dev/null 2>&1 && break
done
sleep 2
play_and_wait || { log "PROBE_FAIL: no PIE session"; fail_all_legs; stop_and_wait; exit 1; }
switch_view "Live"
sleep 1
GAME_BITS=$(game_entity_bits "Spinner")
log "SPINNER_GAME_BITS=$GAME_BITS"

# ---- badge + tray row buttons (Revert, Save) --------------------------------
log "--- cycle R: badge opens the tray; per-entry Revert streams the baseline back ---"
budget 15 make_entry 2.5 || { log "PROBE_FAIL: component.set produced no entry (the LT2 route did not fire)"; fail_all_legs; stop_and_wait; exit 1; }
leg PROBE_INJECTION true
walk "$OUTDIR/walk-probe-badge.json"
walk_has "1 edit" "$OUTDIR/walk-probe-badge.json" && leg PROBE_BADGE true || leg PROBE_BADGE false
click_label "1 edit" && leg PROBE_BADGE_CLICK true || leg PROBE_BADGE_CLICK false
sleep 2
walk "$OUTDIR/walk-probe-tray.json"
walk_has "$ROW" "$OUTDIR/walk-probe-tray.json" && leg PROBE_BADGE_OPENS_TRAY true || leg PROBE_BADGE_OPENS_TRAY false
walk_has "$ROW" "$OUTDIR/walk-probe-tray.json" && leg PROBE_TRAY_ROW true || leg PROBE_TRAY_ROW false
walk_has "1.0 -> 2.5" "$OUTDIR/walk-probe-tray.json" && leg PROBE_TRAY_DIFF_TEXT true || leg PROBE_TRAY_DIFF_TEXT false
local_row_bits=$(button_bits_in_row "$OUTDIR/walk-probe-tray.json" "$ROW" "Revert" | head -1)
log "Revert button bits: ${local_row_bits:-none}"
if [ -n "$local_row_bits" ]; then
  brp jackdaw/ui_click "{\"entity\":$local_row_bits}" > "$OUTDIR/probe-revert-click.json" 2>/dev/null
  sleep 3
  leg PROBE_ROW_REVERT true
else
  leg PROBE_ROW_REVERT false
fi
sleep 2
log "after Revert: live_edits=$(live_edits_count) game_y=$(game_translation_y "$GAME_BITS") (want 0 / 1)"
[ "$(live_edits_count)" = "0" ] && leg PROBE_ROW_REVERT_SETTLED true || leg PROBE_ROW_REVERT_SETTLED false
[ "$(game_translation_y "$GAME_BITS")" = "1" ] && leg PROBE_ROW_REVERT_STREAMED true || leg PROBE_ROW_REVERT_STREAMED false

log "--- cycle S: per-entry Save authors the document ---"
budget 15 make_entry 2.5 || log "note: cycle S injection lagged"
click_label "1 edit" >/dev/null 2>&1   # the Revert emptied the ledger, which force-closed the tray
sleep 2
walk "$OUTDIR/walk-probe-tray2.json"
save_bits=$(button_bits_in_row "$OUTDIR/walk-probe-tray2.json" "$ROW" "Save" | head -1)
log "Save button bits: ${save_bits:-none}"
bsn_before_save=$(sha_of "$(scene_bsn_text)")
hist_before_save=$(history_depth)
if [ -n "$save_bits" ]; then
  brp jackdaw/ui_click "{\"entity\":$save_bits}" > "$OUTDIR/probe-save-click.json" 2>/dev/null
  sleep 3
  leg PROBE_ROW_SAVE true
else
  leg PROBE_ROW_SAVE false
fi
sleep 2
bsn_after_save=$(sha_of "$(scene_bsn_text)")
log "after Save: live_edits=$(live_edits_count) doc $bsn_before_save -> $bsn_after_save undo $(history_depth) (want 0 / changed / +1)"
[ "$(live_edits_count)" = "0" ] && leg PROBE_ROW_SAVE_SETTLED true || leg PROBE_ROW_SAVE_SETTLED false
[ "$bsn_after_save" != "$bsn_before_save" ] && leg PROBE_ROW_SAVE_AUTHORED true || leg PROBE_ROW_SAVE_AUTHORED false
[ "$(history_depth)" = "$((hist_before_save + 1))" ] && leg PROBE_ROW_SAVE_UNDO true || leg PROBE_ROW_SAVE_UNDO false

# ---- stop prompt three keys ---------------------------------------------------
log "--- cycle A: stop prompt Apply All ---"
budget 15 make_entry 3.0 || log "note: cycle A injection lagged"
stop_and_wait
sleep 2
walk "$OUTDIR/walk-probe-prompt.json"
walk_has "1 live edit not saved to scene" "$OUTDIR/walk-probe-prompt.json" && leg PROBE_PROMPT_TITLE true || leg PROBE_PROMPT_TITLE false
for b in Review Discard "Apply All"; do
  walk_has "\"$b\"" "$OUTDIR/walk-probe-prompt.json" || log "note: the $b key is not in the prompt walk"
done
bsn_before_apply=$(sha_of "$(scene_bsn_text)")
click_label "Apply All" && leg PROBE_PROMPT_APPLY_ALL true || leg PROBE_PROMPT_APPLY_ALL false
sleep 3
bsn_after_apply=$(sha_of "$(scene_bsn_text)")
log "after Apply All: live_edits=$(live_edits_count) doc $bsn_before_apply -> $bsn_after_apply (want 0 / changed)"
[ "$(live_edits_count)" = "0" ] && leg PROBE_PROMPT_APPLY_ALL_SETTLED true || leg PROBE_PROMPT_APPLY_ALL_SETTLED false
[ "$bsn_after_apply" != "$bsn_before_apply" ] && leg PROBE_PROMPT_APPLY_ALL_AUTHORED true || leg PROBE_PROMPT_APPLY_ALL_AUTHORED false
walk "$OUTDIR/walk-probe-prompt-closed.json"
walk_has "not saved to scene" "$OUTDIR/walk-probe-prompt-closed.json" && leg PROBE_PROMPT_CLOSED false || leg PROBE_PROMPT_CLOSED true
play_and_wait || { log "PROBE_FAIL: replay after Apply All"; exit 1; }

log "--- cycle D: stop prompt Discard ---"
budget 15 make_entry 3.5 || log "note: cycle D injection lagged"
stop_and_wait
sleep 2
walk "$OUTDIR/walk-probe-prompt2.json"
walk_has "1 live edit not saved to scene" "$OUTDIR/walk-probe-prompt2.json" || log "note: the prompt did not show for cycle D"
bsn_before_discard=$(sha_of "$(scene_bsn_text)")
hist_before_discard=$(history_depth)
click_label "Discard" && leg PROBE_PROMPT_DISCARD true || leg PROBE_PROMPT_DISCARD false
sleep 3
bsn_after_discard=$(sha_of "$(scene_bsn_text)")
log "after Discard: live_edits=$(live_edits_count) doc $bsn_before_discard -> $bsn_after_discard undo $(history_depth) (want 0 / identical / same)"
[ "$(live_edits_count)" = "0" ] && leg PROBE_PROMPT_DISCARD_SETTLED true || leg PROBE_PROMPT_DISCARD_SETTLED false
[ "$bsn_after_discard" = "$bsn_before_discard" ] && leg PROBE_PROMPT_DISCARD_PRESERVES_DOC true || leg PROBE_PROMPT_DISCARD_PRESERVES_DOC false
[ "$(history_depth)" = "$hist_before_discard" ] && leg PROBE_PROMPT_DISCARD_NO_UNDO true || leg PROBE_PROMPT_DISCARD_NO_UNDO false

log "--- cycle V: stop prompt Review hands off; tray footer Apply All ---"
play_and_wait || { log "PROBE_FAIL: replay for cycle V"; exit 1; }
budget 15 make_entry 4.0 || log "note: cycle V injection lagged"
stop_and_wait
sleep 2
walk "$OUTDIR/walk-probe-prompt3.json"
walk_has "1 live edit not saved to scene" "$OUTDIR/walk-probe-prompt3.json" || log "note: the prompt did not show for cycle V"
click_label "Review" && leg PROBE_PROMPT_REVIEW true || leg PROBE_PROMPT_REVIEW false
sleep 2
walk "$OUTDIR/walk-probe-review.json"
walk_has "$ROW" "$OUTDIR/walk-probe-review.json" && leg PROBE_REVIEW_HANDOFF_TRAY true || leg PROBE_REVIEW_HANDOFF_TRAY false
walk_has '"Apply All"' "$OUTDIR/walk-probe-review.json" && leg PROBE_FOOTER_BUTTONS_PRESENT true || leg PROBE_FOOTER_BUTTONS_PRESENT false
bsn_before_footer=$(sha_of "$(scene_bsn_text)")
click_label "Apply All" && leg PROBE_FOOTER_APPLY_ALL true || leg PROBE_FOOTER_APPLY_ALL false
sleep 3
bsn_after_footer=$(sha_of "$(scene_bsn_text)")
log "after footer Apply All: live_edits=$(live_edits_count) doc $bsn_before_footer -> $bsn_after_footer (want 0 / changed)"
[ "$(live_edits_count)" = "0" ] && leg PROBE_FOOTER_APPLY_ALL_SETTLED true || leg PROBE_FOOTER_APPLY_ALL_SETTLED false
[ "$bsn_after_footer" != "$bsn_before_footer" ] && leg PROBE_FOOTER_APPLY_ALL_AUTHORED true || leg PROBE_FOOTER_APPLY_ALL_AUTHORED false

# ---- census + teardown --------------------------------------------------------
op pie.stop >/dev/null 2>&1
budget 120 pie_stopped || log "note: the final stop ran past its budget"
sleep 2; pkill -x "$GAMEBIN" 2>/dev/null; sleep 2
panic_n13=$(grep -c "Encountered an error in system" "$EDITOR_LOG" 2>/dev/null)
case "$panic_n13" in ''|*[!0-9]*) panic_n13=0 ;; esac
swap_n13=$(grep -c "swap_remove index" "$EDITOR_LOG" 2>/dev/null)
case "$swap_n13" in ''|*[!0-9]*) swap_n13=0 ;; esac
log "CENSUS: error-handler panics=$panic_n13 swap_remove-signature=$swap_n13 (N13 family, attributed)"
grep -E "Encountered an error in system|swap_remove index" "$EDITOR_LOG" > "$OUTDIR/census-probe.txt" 2>/dev/null
log "PROBE done: $(results)"
