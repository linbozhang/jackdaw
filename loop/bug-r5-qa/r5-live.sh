#!/bin/bash
# R5 QA live leg: boot the editor on the bsn_game fixture (no jackdaw.toml,
# the machine-verified "Open without setup" path), add a Terrain entity via
# the Add-menu operator (entity.add.terrain — spawns an unsculpted terrain,
# grid_resolution 0, and selects it), then trigger Erode WITHOUT generating:
#   Form A (primary): ui_click the panel "Erode" button — the exact user
#     path from the ticket (only gated by has_selected_terrain).
#   Form B (fallback, plan-sanctioned equivalent): jackdaw/call_operator
#     {"id":"terrain.erode"}.
# Assertions:
#   1 the editor does not panic and does not exit (process alive, no
#     "panicked" line in the editor log — before the fix this panicked at
#     erosion.rs:75 cannot sample empty range),
#   2 a toast appears carrying "erosion needs at least 4" (ui_tree walk
#     within the 3s DEFAULT_TOAST_DURATION window),
#   3 no side effects: the undo stack gains no entry and its top label is
#     unchanged (jackdaw/history), plus the warn refusal line in the log.
# Evidence discipline: every BRP reply archived as a file under
# loop/bug-r5-qa/, screenshots via jackdaw/screenshot.
#
# Usage: bash loop/bug-r5-qa/r5-live.sh <phase>
#   phase: boot | terrain | all
set -u
REPO=/Users/linbo.zhang/workspace/jackdaw
PROJECT="$REPO/tests/fixtures/bsn_game"
PORT=15703
OUTDIR="$REPO/loop/bug-r5-qa"
TOOLCHAIN_LIB=/Users/linbo.zhang/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
EDITOR_LOG="$OUTDIR/live-editor.log"
CONSOLE_LOG="$OUTDIR/live-console.log"
mkdir -p "$OUTDIR"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$CONSOLE_LOG"; }

brp() { # editor BRP: brp <method> <params-json>
  curl -s --max-time 20 -X POST "http://127.0.0.1:$PORT/" \
    -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}"
}
budget() { # budget <seconds> <command...> — retry until it exits 0
  local deadline=$(( SECONDS + $1 )); shift
  while [ $SECONDS -lt $deadline ]; do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  return 1
}
# NOTE (r4-live.sh lesson): no `bash -c` wrappers — a child shell cannot see
# these functions, so every retry body runs as a plain pipeline in THIS shell.
wait_idle() {
  local deadline=$(( SECONDS + ${1:-300} ))
  while [ $SECONDS -lt $deadline ]; do
    if brp jackdaw/wait '{"until":"idle"}' 2>/dev/null | jq -e '.result.idle == true' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}
alive() { kill -0 "$(cat "$OUTDIR/live-boot-pid.txt" 2>/dev/null)" 2>/dev/null; }
cleanup() {
  pkill -x jackdaw 2>/dev/null; sleep 2; pkill -9 -x jackdaw 2>/dev/null
  sleep 1
}
port_silent() { [ -z "$(curl -s --max-time 2 "http://127.0.0.1:$PORT/" 2>/dev/null)" ]; }

boot() {
  for squatter in 1 2 3 4 5; do
    cleanup
    port_silent && break
  done
  port_silent || { log "BOOT_FAIL: port $PORT still answered after five kills"; return 1; }
  : > "$EDITOR_LOG"
  export JACKDAW_OPEN_PROJECT="$PROJECT"
  export PATH="$HOME/.cargo/bin:$PATH"
  export JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1920x1080
  cd "$REPO"
  nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$EDITOR_LOG" 2>&1 &
  BOOT_PID=$!
  echo "$BOOT_PID" > "$OUTDIR/live-boot-pid.txt"
  log "boot: editor pid=$BOOT_PID project=$PROJECT binary=$(ls -la target/debug/jackdaw | awk '{print $6, $7, $8}')"
  local ok=""
  for i in $(seq 1 150); do
    sleep 2
    if brp jackdaw/status '{}' 2>/dev/null | jq -e '.result.pid' >/dev/null 2>&1 && kill -0 "$BOOT_PID" 2>/dev/null; then ok=1; break; fi
    kill -0 "$BOOT_PID" 2>/dev/null || break
  done
  [ -n "$ok" ] || { log "BOOT_FAIL: the BRP never answered"; return 1; }
  sleep 5
  wait_idle 900 || { log "BOOT_FAIL: the asset pipeline never went idle"; return 1; }
  sleep 3
  # the recovered-work modal guard: dismiss if present
  brp jackdaw/ui_tree '{"text":"closed unexpectedly","depth":3}' > "$OUTDIR/live-walk-boot-recovery.json" 2>/dev/null
  if grep -qF "closed unexpectedly" "$OUTDIR/live-walk-boot-recovery.json"; then
    log "recovery modal present, dismissing via Discard All"
    brp jackdaw/ui_click '{"text":"Discard All"}' > "$OUTDIR/live-click-discard.json" 2>/dev/null
    sleep 2; wait_idle 120
  fi
  # The setup dialog (a project with a Cargo.toml but no jackdaw.toml gets
  # "offering setup"): the machine-verified good path is clicking
  # "Open without setup" (project_select.rs:858). Without this click the
  # workspace never gains its docks and every later UI face is degraded
  # (first round: no visible leaf, empty selection, no Erode button).
  open_setup || true
  if ! brp jackdaw/status '{}' 2>/dev/null | jq -e '.result.project != null' >/dev/null 2>&1; then
    log "project face still null; trying a direct scene.open (absolute path)"
    brp jackdaw/call_operator "{\"id\":\"scene.open\",\"params\":{\"path\":\"$PROJECT/assets/scene.bsn\",\"reload\":true}}" \
      > "$OUTDIR/live-scene-open.json" 2>/dev/null
    sleep 3; wait_idle 120
  fi
  brp jackdaw/status '{}' | jq -c '{project: .result.project, scene: .result.scene, selection: .result.selection}' | tee -a "$CONSOLE_LOG"
  log "EDITOR_READY pid=$BOOT_PID"
  return 0
}

open_setup() {
  # Click "Open without setup" if the setup card is up; idempotent.
  # NOTE: the label glyph classifies as kind:"text" (its parent node is the
  # clickable button), so NO kind filter here — text targeting alone, the
  # ui_probe's text→clickable-ancestor walk does the rest.
  brp jackdaw/ui_tree '{"text":"Open without setup","depth":8}' > "$OUTDIR/live-walk-setup-dialog.json" 2>/dev/null
  if grep -qF "Open without setup" "$OUTDIR/live-walk-setup-dialog.json"; then
    log "setup dialog up; clicking Open without setup"
    brp jackdaw/ui_click '{"text":"Open without setup"}' > "$OUTDIR/live-click-open-setup.json" 2>/dev/null
    sleep 3
    wait_idle 300
    sleep 3
  else
    log "no setup dialog present (project may already be open)"
  fi
  if brp jackdaw/status '{}' 2>/dev/null | jq -e '.result.project != null' >/dev/null 2>&1; then
    log "PROJECT_OPEN"
    return 0
  fi
  return 1
}

terrain_leg() {
  log "=== R5 TERRAIN LEG BEGIN ==="
  brp jackdaw/status '{}' > "$OUTDIR/live-status-boot.json" 2>/dev/null
  log "status: $(jq -c '{project: .result.project, scene: .result.scene, pie: .result.pie}' "$OUTDIR/live-status-boot.json" 2>/dev/null)"

  # 0) operator registry evidence: the two operators this leg rides on
  brp jackdaw/operators '{}' > "$OUTDIR/live-operators.json" 2>/dev/null
  jq -r '.result[]? | select(.id=="terrain.erode" or .id=="entity.add.terrain") | .id' \
    "$OUTDIR/live-operators.json" > "$OUTDIR/live-operators-r5.txt" 2>/dev/null
  log "operators present: $(tr '\n' ' ' < "$OUTDIR/live-operators-r5.txt")"

  # 1) history baseline BEFORE the add
  brp jackdaw/history '{"entries":8}' > "$OUTDIR/live-history-baseline.json" 2>/dev/null
  log "history baseline: $(jq -c '{undo_len: .result.undo_len, redo_len: .result.redo_len, top: .result.top}' "$OUTDIR/live-history-baseline.json" 2>/dev/null)"

  # 2) add a Terrain entity (Add-menu operator): unsculpted, resolution 0,
  #    and it selects the new entity
  brp jackdaw/call_operator '{"id":"entity.add.terrain","params":{}}' > "$OUTDIR/live-add-terrain.json" 2>/dev/null
  sleep 1
  wait_idle 60
  sleep 2
  brp jackdaw/history '{"entries":8}' > "$OUTDIR/live-history-after-add.json" 2>/dev/null
  log "history after add: $(jq -c '{undo_len: .result.undo_len, redo_len: .result.redo_len, top: .result.top}' "$OUTDIR/live-history-after-add.json" 2>/dev/null)"
  brp jackdaw/entity '{"name":"Terrain"}' > "$OUTDIR/live-entity-terrain.json" 2>/dev/null
  log "terrain entity lookup: $(head -c 300 "$OUTDIR/live-entity-terrain.json" 2>/dev/null)"
  # gate: the erode operator must read available (has_selected_terrain true)
  # before it is called — round 1 raced the add's deferred commands.
  erode_ready() {
    brp jackdaw/operators '{}' 2>/dev/null | jq -e '.result.operators[] | select(.id=="terrain.erode") | .available == true' >/dev/null 2>&1
  }
  if budget 30 erode_ready; then
    log "ERODE_READY terrain.erode available:true"
  else
    log "ERODE_NOT_AVAILABLE after 30s — proceeding anyway (will read the reply)"
  fi
  curl -s --max-time 10 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"jackdaw/status","params":{}}' | jq -c '.result.selection' | tee -a "$CONSOLE_LOG"

  # 3) locate the panel Erode button; its disabled:false also proves
  #    has_selected_terrain passed (the ticket's only gate).
  #    No kind filter: the button's label glyph may classify as text.
  brp jackdaw/ui_tree '{"text":"Erode","depth":16}' > "$OUTDIR/live-walk-erode-button.json" 2>/dev/null
  if ! grep -qF '"Erode"' "$OUTDIR/live-walk-erode-button.json"; then
    log "filtered walk missed the Erode button; full walk fallback"
    brp jackdaw/ui_tree '{"depth":24}' > "$OUTDIR/live-walk-full-pre.json" 2>/dev/null
  fi
  log "erode button node: $(jq -c '.. | objects | select(.text? == "Erode") | {entity,kind,text,operator,disabled,rect}' "$OUTDIR/live-walk-erode-button.json" "$OUTDIR/live-walk-full-pre.json" 2>/dev/null | head -2)"

  # 4) trigger Erode — Form A: click the button, then walk FAST (toast lives 3s)
  brp jackdaw/ui_click '{"text":"Erode"}' > "$OUTDIR/live-click-erode.json" 2>/dev/null
  log "click form A: $(head -c 300 "$OUTDIR/live-click-erode.json" 2>/dev/null)"
  wait_idle 20
  brp jackdaw/ui_tree '{"depth":24}' > "$OUTDIR/live-walk-after-erode.json" 2>/dev/null
  if grep -qF "erosion needs at least 4" "$OUTDIR/live-walk-after-erode.json"; then
    log "ASSERT2_TOAST_FOUND (form A click)"
  else
    # Form B: the plan-sanctioned equivalent — call the operator directly
    log "toast not caught after click; retrying with operator form B"
    brp jackdaw/call_operator '{"id":"terrain.erode","params":{}}' > "$OUTDIR/live-erode-op.json" 2>/dev/null
    brp jackdaw/ui_tree '{"depth":24}' > "$OUTDIR/live-walk-after-erode2.json" 2>/dev/null
    if grep -qF "erosion needs at least 4" "$OUTDIR/live-walk-after-erode2.json"; then
      log "ASSERT2_TOAST_FOUND (form B operator)"
    else
      log "ASSERT2_TOAST_MISSING both forms (headless-font deviation candidate)"
    fi
  fi

  # 5) screenshot right after (toast may still be up)
  local shot=""
  for i in 1 2 3 4 5 6 7 8; do
    shot=$(brp jackdaw/screenshot "{\"kind\":\"window\",\"path\":\"$OUTDIR/live-erode-window.png\"}" 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
    [ -n "$shot" ] && break
    sleep 1
  done
  log "screenshot: ${shot:-NONE} file=$(ls -la "$OUTDIR/live-erode-window.png" 2>/dev/null | awk '{print $5}')"

  # 6) assertions
  if alive; then log "ASSERT1_ALIVE editor process alive"; else log "ASSERT1_FAIL editor process DEAD"; fi
  if grep -q "panicked" "$EDITOR_LOG"; then
    log "ASSERT1_FAIL panic line(s) in editor log:"; grep -n "panicked" "$EDITOR_LOG" | tee -a "$CONSOLE_LOG"
  else
    log "ASSERT1_NO_PANIC no 'panicked' line in editor log"
  fi
  if grep -q "vertices a side and erosion needs at least 4" "$EDITOR_LOG"; then
    log "REFUSAL_WARN_IN_LOG the refusal warn line reached the editor log"
    grep -n "vertices a side" "$EDITOR_LOG" | head -3 | tee -a "$CONSOLE_LOG"
  else
    log "REFUSAL_WARN_MISSING refusal warn line NOT in editor log"
  fi
  brp jackdaw/history '{"entries":8}' > "$OUTDIR/live-history-after-erode.json" 2>/dev/null
  log "history after erode: $(jq -c '{undo_len: .result.undo_len, redo_len: .result.redo_len, top: .result.top}' "$OUTDIR/live-history-after-erode.json" 2>/dev/null)"
  log "=== R5 TERRAIN LEG END ==="
  return 0
}

case "${1:-all}" in
  boot) boot ;;
  open-setup) open_setup ;;
  terrain) terrain_leg ;;
  all) boot && terrain_leg ;;
  *) echo "usage: $0 boot|open-setup|terrain|all"; exit 2 ;;
esac
