#!/bin/bash
# T25-T1 red window: the two pre-fix evidence legs, archived before any
# construction (the t23 QD1 / t24 DF-R discipline). The editor binary is the
# pre-fix build (main 050b4813, docs-only plan commit on top of b9bc6e4e).
#
#   LT-R1  the LT2 triple-silence proof: in Live view, `component.set` on a
#          projected authored entity silently authors the DOCUMENT — the
#          scene_bsn document SHA changes while (a) the game-side value the
#          BRP reads is unchanged, (b) `jackdaw/pie` live_edits stays 0, and
#          (c) the disk file is untouched until an explicit save. No stream,
#          no ledger, no game knowledge: document and viewport fork.
#   LT-R2  the N11 live refresh: `ui_input` typed into the Inspector's
#          numeric rows with an Enter commit — no commit happens (the typed
#          value never reaches the field commit path; live_edits stays 0,
#          game value unchanged, document byte-identical to post-R1). Pure
#          archive leg, zero fix expected (T06 cell 7's tooling-gap ruling,
#          now on this build).
#
# Disciplines (A6 family, the five), in force on every leg:
#   1. one trigger source per leg (R1: one operator call; R2: typed inputs);
#   2. settle >= 2s after every write;
#   3. assertion budget per wait, timeout judges FAIL;
#   4. this red window shares no window with the cargo gates (the only
#      cargo inside is the editor's own warm build of the fixture);
#   5. disk checked before the run (15Gi bar).
# A9: reads retry through the flaky window; no RUST_BACKTRACE anywhere (the
# T11-T3 wgpu SIGSEGV calibre). N13 rides every PIE leg: the census at the
# end attributes panics by signature; panic noise is NOT a red-leg criterion.
# QA-2 rework note: the R2 leg's document-before read once called its helper
# as a variable (`"$scene_bsn_text"` — unbound under bash 3.2's set -u, the
# expansion silently emptying) so the leg never actually read the document;
# the offline judgment on the archived SHA pair stood in. T2 scripts: always
# `$(scene_bsn_text)` — a helper name is not a variable.
#
# Usage: bash loop/qa/t25-red.sh [phase]   phase: prep|red|all
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
FIXROOT=/Users/zhanglinbo/workspace/loop-mac/t25-live-tuning
PROJECT="$FIXROOT/t25-live"
PORT=15703
GAME_PORT=15702
OUTDIR="${T25_OUTDIR:-$REPO/loop/t25-live}"
REPORT_TAG="${T25_REPORT_TAG:-t25t1}"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
GAMEBIN="t25-live"
TRANSFORM='bevy_transform::components::transform::Transform'
mkdir -p "$OUTDIR"
PHASE="${1:-all}"
EDITOR_LOG="$OUTDIR/editor-red.log"
CONSOLE_LOG="$OUTDIR/console-red.log"
echo "=== red run $(date '+%Y-%m-%d %H:%M:%S') build=$(git -C "$REPO" rev-parse --short HEAD) ===" >> "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t25-red.XXXXXX)"
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
  # True when :$PORT answers nothing (a dying window's listener can hold
  # connections open without answering, hence the 3s timeout).
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
  echo "$boot_pid" > "$OUTDIR/boot-pid.txt"
  local ok=""
  for i in $(seq 1 150); do
    sleep 2
    if brp jackdaw/status '{}' >/dev/null 2>&1 && kill -0 "$boot_pid" 2>/dev/null; then ok=1; break; fi
    kill -0 "$boot_pid" 2>/dev/null || break
  done
  [ -n "$ok" ] || { log "EDITOR_BOOT_FAIL"; exit 1; }
  local answer_pid
  answer_pid=$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.pid // empty' 2>/dev/null)
  [ "$answer_pid" = "$boot_pid" ] || { log "EDITOR_BOOT_FAIL: :$PORT answers pid=$answer_pid, wanted $boot_pid"; exit 1; }
  sleep 5
  wait_idle 900 >/dev/null; sleep 3; dismiss_dialog
  log "EDITOR_READY project=$PROJECT pid=$boot_pid"
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
pie_face() { brp jackdaw/pie '{}' 2>/dev/null | jq -c '.result // .' 2>/dev/null; }
live_edits_count() { pie_face | jq -r '.live_edits // 0' 2>/dev/null; }
tree_bits_of() { # tree_bits_of <name> — the entity bits `scene_tree` gives
                 # the entity this name (the Live tree's projected entity)
  brp jackdaw/scene_tree '{"depth":8}' 2>/dev/null | jq -r --arg n "$1" '
    def walk: if (.name? == $n) then .entity
              elif (.children? | type) == "array" then (.children[]? | walk)
              else empty end;
    (.result.tree // .tree // [])[]? | walk' 2>/dev/null | head -1
}
switch_view() { # switch_view <label> — click the view toggle by its text
  local bits
  bits=$(brp jackdaw/ui_tree "{\"text\":\"$1\"}" 2>/dev/null | jq -r '.result.nodes[0].entity // empty' 2>/dev/null)
  if [ -n "$bits" ]; then
    brp jackdaw/ui_click "{\"entity\":$bits}" >/dev/null 2>&1
    sleep 2
    log "switched to $1 view (entity $bits)"
  else
    log "SWITCH_VIEW_FAIL: no '$1' segment in the walk"
  fi
}
game_entity_bits() { # the GAME-side bits of the named entity
  gbrp world.query "{\"data\":{\"components\":[\"bevy_ecs::name::Name\"]}}" 2>/dev/null \
    | jq -r --arg n "$1" '[.result[]? | select(.components["bevy_ecs::name::Name"] == $n) | .entity][0]' 2>/dev/null
}
game_translation_y() { # the game's current Transform.translation.y for bits
  gbrp world.get_components "{\"entity\":\"$1\",\"components\":[\"$TRANSFORM\"]}" 2>/dev/null \
    | jq -r '.result.components["'"$TRANSFORM"'"].translation[1]
             // .result["'"$TRANSFORM"'"].translation[1] // empty' 2>/dev/null
}
game_translation_full() {
  gbrp world.get_components "{\"entity\":\"$1\",\"components\":[\"$TRANSFORM\"]}" 2>/dev/null \
    | jq -c '.result.components["'"$TRANSFORM"'"] // .result["'"$TRANSFORM"'"]' 2>/dev/null
}

# ---- phase: prep --------------------------------------------------------------
prep() {
  pkill -x jackdaw 2>/dev/null; pkill -x "$GAMEBIN" 2>/dev/null; sleep 1
  local free
  free=$(df -g / | awk 'NR==2 {print $4}')
  [ "$free" -ge 15 ] || { log "PREP_FAIL only ${free}Gi free; clean the disk first"; exit 1; }
  log "disk: ${free}Gi free"
  rm -rf "$PROJECT"; mkdir -p "$FIXROOT" "$OUTDIR"
  (cd "$REPO" && DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jd new t25-live --path "$FIXROOT" --no-git) > "$OUTDIR/jd-new.log" 2>&1
  [ -d "$PROJECT" ] || { log "PREP_FAIL no project ($(tail -2 "$OUTDIR/jd-new.log"))"; exit 1; }
  python3 - "$PROJECT" "$REPO" << 'PYT'
import sys
project, repo = sys.argv[1], sys.argv[2]
toml_path = f"{project}/Cargo.toml"
text = open(toml_path).read()
if "jackdaw_remote" not in text:
    needle = "jackdaw_runtime = { path = "
    line_start = text.index(needle)
    line_end = text.index("\n", line_start)
    remote = f"\njackdaw_remote = {{ path = '{repo}/crates/jackdaw_remote' }}"
    text = text[:line_end] + remote + text[line_end:]
    open(toml_path, "w").write(text)
main_path = f"{project}/src/main.rs"
main = open(main_path).read()
if "JackdawRemotePlugin" not in main:
    marker = "::GamePlugin)"
    at = main.index(marker) + len(marker)
    main = main[:at] + "\n        .add_plugins(jackdaw_remote::JackdawRemotePlugin::default())" + main[at:]
    open(main_path, "w").write(main)
print("injected")
PYT
  grep -q jackdaw_remote "$PROJECT/Cargo.toml" || { log "PREP_FAIL no remote dep"; exit 1; }
  cat > "$PROJECT/assets/t25-red.bsn" << 'EOF'
// T25 red-leg fixture: one authored entity with a readable Transform.
#Spinner
jackdaw_scene_types::node_id::SceneNodeId(7001)
bevy_transform::components::transform::Transform {
    translation: glam::Vec3 { x: 0.0, y: 1.0, z: 0.0 },
}
EOF
  python3 - "$PROJECT/.jackdaw/project.json" << 'PYT'
import json, sys
path = sys.argv[1]
try:
    cfg = json.load(open(path))
    cfg.pop("layout", None)
    cfg["last_open_tabs"] = ["assets/t25-red.bsn"]
    cfg["last_active_tab"] = 0
    json.dump(cfg, open(path, "w"), indent=2)
except FileNotFoundError:
    pass
PYT
  (cd "$PROJECT" && cargo metadata --format-version 1 >/dev/null 2>"$OUTDIR/lockfix.log") \
    || { log "PREP_FAIL lock refresh: $(tail -2 "$OUTDIR/lockfix.log")"; exit 1; }
  log "PREP_OK fixture=$PROJECT"
}

# ---- phase: red (LT-R1 + LT-R2) ------------------------------------------------
red() {
  editor_boot
  open_scene "assets/t25-red.bsn"
  op scene.save >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  log "--- warm build (fills .jackdaw/target so the play leg stays short) ---"
  op project.build >/dev/null 2>&1
  local warm=""
  for i in $(seq 1 120); do
    sleep 10
    if brp jackdaw/wait '{"until":"idle"}' 2>/dev/null | jq -e '.result.idle == true' >/dev/null 2>&1; then warm=1; break; fi
  done
  [ -n "$warm" ] && log "WARM_BUILD_OK" || log "WARM_BUILD_UNVERIFIED (continuing)"
  sleep 3; wait_idle 120 >/dev/null

  log "--- baselines before the play ---"
  local bsn_before disk_before hist_before
  bsn_before=$(scene_bsn_text)
  disk_before=$(shasum -a 256 "$PROJECT/assets/t25-red.bsn" | cut -d' ' -f1)
  hist_before=$(history_depth)
  log "BSN_SHA_BEFORE=$(sha_of "$bsn_before") DISK_SHA_BEFORE=$disk_before HISTORY_BEFORE=$hist_before"
  cp "$PROJECT/assets/t25-red.bsn" "$OUTDIR/t25-red.bsn.before"

  log "--- play, wait live, switch to Live view ---"
  op pie.play_current >/dev/null 2>&1
  budget 240 [ "$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.pie // empty' 2>/dev/null)" = "running" ] \
    || { log "R_LEG_FAIL: the pie never ran"; leg LTR1_GAME_UP false; leg LTR2_NO_COMMIT false; return; }
  leg LTR1_GAME_UP true
  budget 120 [ "$(pie_face | jq -r '.instances[0].stage // empty' 2>/dev/null)" = "live" ] \
    || log "note: the instance stage never read live (continuing on the BRP face)"
  budget 120 [ "$(gbrp jackdaw/app_info '{}' 2>/dev/null | jq -r '.result.app_name // empty' 2>/dev/null)" != "" ] \
    || log "note: the game BRP did not answer within budget"
  sleep 4
  switch_view "Live"
  sleep 2

  local spinner_bits game_bits
  spinner_bits=$(tree_bits_of "Spinner")
  log "SPINNER_PREVIEW_BITS=$spinner_bits"
  [ -n "$spinner_bits" ] && leg LTR1_PROJECTION_SELECTED true || leg LTR1_PROJECTION_SELECTED false
  game_bits=$(game_entity_bits "Spinner")
  log "SPINNER_GAME_BITS=$game_bits"
  local gy_before
  gy_before=$(game_translation_y "$game_bits")
  log "GAME_TRANSLATION_Y_BEFORE=$gy_before (want 1)"
  [ "${gy_before:-x}" = "1" ] || log "note: the game baseline y is '${gy_before:-none}' (assertion below judges)"

  local edits_before hist_after_play
  edits_before=$(live_edits_count)
  hist_after_play=$(history_depth)
  log "LIVE_EDITS_BEFORE=$edits_before HISTORY_AFTER_PLAY=$hist_after_play (want 0 / $hist_before)"
  [ "${edits_before:-1}" = "0" ] && leg LTR1_LEDGER_CLEAN_BEFORE true || leg LTR1_LEDGER_CLEAN_BEFORE false

  # ------------------------- LT-R1: the component.set triple silence --------
  log "--- LT-R1: component.set translation.y=2.5 on the projected entity ---"
  op component.set "{\"entity\":$spinner_bits,\"type_path\":\"$TRANSFORM\",\"field\":\"translation.y\",\"value\":\"2.5\"}" \
    > "$OUTDIR/ltr1-component-set-response.json" 2>/dev/null
  log "component.set response: $(cat "$OUTDIR/ltr1-component-set-response.json")"
  sleep 4   # settle: any game stream-back or ledger write would have landed

  local bsn_after edits_after gy_after disk_after hist_after
  bsn_after=$(scene_bsn_text)
  edits_after=$(live_edits_count)
  gy_after=$(game_translation_y "$game_bits")
  disk_after=$(shasum -a 256 "$PROJECT/assets/t25-red.bsn" | cut -d' ' -f1)
  hist_after=$(history_depth)
  local bsn_sha_before=$(sha_of "$bsn_before") bsn_sha_after=$(sha_of "$bsn_after")
  log "LT-R1 verdicts:"
  log "  document: $bsn_sha_before -> $bsn_sha_after (changed = the silent authoring)"
  log "  game y:   $gy_before -> $gy_after (unchanged = the game never heard)"
  log "  ledger:   $edits_before -> $edits_after (0 = the route bypassed it)"
  log "  disk:     $disk_before -> $disk_after"
  log "  history:  $hist_before -> $hist_after (+1 = an authored undo entry exists)"
  echo "$bsn_after" > "$OUTDIR/t25-red.bsn.after-document"
  [ "$bsn_sha_after" != "$bsn_sha_before" ] && leg LTR1_DOCUMENT_SILENTLY_AUTHORED true || leg LTR1_DOCUMENT_SILENTLY_AUTHORED false
  [ "${gy_after:-x}" = "${gy_before:-y}" ] && leg LTR1_GAME_VALUE_UNCHANGED true || leg LTR1_GAME_VALUE_UNCHANGED false
  [ "${edits_after:-1}" = "0" ] && leg LTR1_LEDGER_COUNT_ZERO true || leg LTR1_LEDGER_COUNT_ZERO false
  [ "$disk_after" = "$disk_before" ] && leg LTR1_DISK_UNTOUCHED true || leg LTR1_DISK_UNTOUCHED false
  [ "$hist_after" = "$((hist_before + 1))" ] && leg LTR1_HISTORY_ENTRY_PUSHED true || leg LTR1_HISTORY_ENTRY_PUSHED false
  game_translation_full "$game_bits" > "$OUTDIR/ltr1-game-transform.json"

  # ------------------------- LT-R2: the ui_input N11 refresh ----------------
  log "--- LT-R2: ui_input typed into the Inspector numeric rows ---"
  local bsn_r2_before=$(sha_of "$(scene_bsn_text)")
  local gy_r2_before=$(game_translation_y "$game_bits")
  local inputs_y
  brp jackdaw/ui_tree '{"kind":"text_input"}' > "$OUTDIR/ltr2-inputs.json" 2>/dev/null
  python3 - "$OUTDIR/ltr2-inputs.json" << 'PYT' > "$OUTDIR/ltr2-candidates.txt"
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    raise SystemExit
data = data.get("result", data)
rows = []
def walk(node):
    rect = node.get("rect")
    if isinstance(rect, list) and len(rect) >= 2:
        rows.append((float(rect[0]), float(rect[1]), node.get("entity")))
    for child in node.get("children", []) or []:
        walk(child)
for root in data.get("nodes", []):
    walk(root)
# The Inspector column: right-hand dock. 1600px window -> x past 1050; below
# the panel chrome (y > 150), reading top to bottom.
for x, y, entity in sorted((r for r in rows if r[0] > 1050 and r[1] > 150), key=lambda r: r[1]):
    print(int(entity))
PYT
  local tried=0 landed=0 row_entity
  while read -r row_entity; do
    [ -n "$row_entity" ] || continue
    [ "$tried" -ge 6 ] && break
    tried=$((tried + 1))
    brp jackdaw/ui_input "{\"entity\":$row_entity,\"text\":\"2.5\",\"commit\":\"enter\"}" \
      > "$OUTDIR/ltr2-input-response-$tried.json" 2>/dev/null
    sleep 2
    local edits_now gy_now
    edits_now=$(live_edits_count)
    gy_now=$(game_translation_y "$game_bits")
    log "R2 row $tried (entity $row_entity): live_edits=$edits_now game_y=$gy_now"
    if [ "${edits_now:-1}" != "0" ] || [ "${gy_now:-x}" != "${gy_r2_before:-y}" ]; then
      landed=1
      break
    fi
  done < "$OUTDIR/ltr2-candidates.txt"
  sleep 2
  local bsn_r2_after edits_r2_after gy_r2_after
  bsn_r2_after=$(sha_of "$(scene_bsn_text)")
  edits_r2_after=$(live_edits_count)
  gy_r2_after=$(game_translation_y "$game_bits")
  log "LT-R2 verdicts:"
  log "  rows tried: $tried; a commit anywhere: $landed (want 0)"
  log "  ledger: $edits_r2_after (want 0)  game y: $gy_r2_after (want $gy_r2_before)"
  log "  document: $bsn_r2_before -> $bsn_r2_after (want identical)"
  [ "$landed" = "0" ] && [ "${edits_r2_after:-1}" = "0" ] && leg LTR2_NO_COMMIT true || leg LTR2_NO_COMMIT false
  [ "${gy_r2_after:-x}" = "${gy_r2_before:-y}" ] && leg LTR2_GAME_VALUE_UNCHANGED true || leg LTR2_GAME_VALUE_UNCHANGED false
  [ "$bsn_r2_after" = "$bsn_r2_before" ] && leg LTR2_DOCUMENT_STABLE true || leg LTR2_DOCUMENT_STABLE false
  [ "$tried" -ge 1 ] && leg LTR2_ROWS_REACHED true || leg LTR2_ROWS_REACHED false

  # ------------------------- census + teardown ------------------------------
  log "--- stop and census ---"
  op pie.stop >/dev/null 2>&1
  budget 240 [ "$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.pie // empty' 2>/dev/null)" = "stopped" ] \
    || log "note: the pie session ran past its stop budget (the kill below closes it)"
  sleep 2; pkill -x "$GAMEBIN" 2>/dev/null; sleep 2
  local panic_n13
  panic_n13=$(grep -c "Encountered an error in system" "$EDITOR_LOG" 2>/dev/null)
  case "$panic_n13" in ''|*[!0-9]*) panic_n13=0 ;; esac
  local swap_n13
  swap_n13=$(grep -c "swap_remove index" "$EDITOR_LOG" 2>/dev/null)
  case "$swap_n13" in ''|*[!09]*) swap_n13=0 ;; esac
  log "CENSUS: error-handler panics=$panic_n13 swap_remove-signature=$swap_n13 (N13 family, attributed, not a leg criterion)"
  grep -E "Encountered an error in system|swap_remove index" "$EDITOR_LOG" > "$OUTDIR/census-red.txt" 2>/dev/null
  log "RED done: $(results)"
}

case "$PHASE" in
  prep) prep ;;
  red) red ;;
  all)
    prep
    red
    log "ALL done"
    ;;
  *) log "unknown phase $PHASE"; exit 2 ;;
esac
log "PHASE_DONE $PHASE results: $(results)"
