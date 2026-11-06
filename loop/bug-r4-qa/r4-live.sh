#!/bin/bash
# R4 QA live leg: boot the editor on the bsn_game fixture (its scene.bsn
# authors #Root with a Children list of Main Camera / Sun / Marker Probe /
# Bgm Probe / Scatter Group, so the running game has a real parent-child
# hierarchy), start PIE, connect the editor's remote session to the game
# BRP, open/inspect the Remote Entities panel and assert the remote
# hierarchy tree is NESTED (child rows live under the parent row), not the
# R4-flat list of roots.
#
# Evidence discipline (loop/qa/manual.md): ui_tree JSON walks archived as
# files, screenshots via jackdaw/screenshot, the N13 swap_remove panic
# census rides at the end and is never a leg criterion.
#
# Usage: bash loop/bug-r4-qa/r4-live.sh <phase>
#   phase: boot | pie | connect | walk | all
set -u
REPO=/Users/linbo.zhang/workspace/jackdaw
PROJECT="$REPO/tests/fixtures/bsn_game"
PORT=15703
GAME_PORT=15702
OUTDIR="$REPO/loop/bug-r4-qa"
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
gbrp() { # game BRP
  curl -s --max-time 20 -X POST "http://127.0.0.1:$GAME_PORT/" \
    -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}"
}
budget() { # budget <seconds> <command...> — retry until it exits 0
  local limit="$1" deadline=$(( SECONDS + $1 )); shift
  while [ $SECONDS -lt $deadline ]; do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  return 1
}
# NOTE: no `bash -c` wrappers here — a child shell cannot see the brp/gbrp
# functions, so every retry body runs as a plain pipeline in THIS shell.
wait_idle() {
  local deadline=$(( SECONDS + ${1:-300} ))
  while [ $SECONDS -lt $deadline ]; do
    if brp jackdaw/wait '{"until":"idle"}' 2>/dev/null | jq -e '.result.idle == true' >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  return 1
}
pie_running() { [ "$(brp jackdaw/status '{}' | jq -r '.result.pie // empty' 2>/dev/null)" = "running" ]; }
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
  log "boot: editor pid=$BOOT_PID project=$PROJECT"
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
  # the recovered-work modal guard (the T25 form): dismiss if present
  brp jackdaw/ui_tree '{"text":"closed unexpectedly","depth":3}' > "$OUTDIR/live-walk-boot-recovery.json" 2>/dev/null
  if grep -qF "closed unexpectedly" "$OUTDIR/live-walk-boot-recovery.json"; then
    log "recovery modal present, dismissing via Discard All"
    brp jackdaw/ui_click '{"text":"Discard All"}' > "$OUTDIR/live-click-discard.json" 2>/dev/null
    sleep 2; wait_idle 120
    brp jackdaw/ui_tree '{"text":"closed unexpectedly","depth":3}' > "$OUTDIR/live-walk-boot-recovery2.json" 2>/dev/null
    grep -qF "closed unexpectedly" "$OUTDIR/live-walk-boot-recovery2.json" && { log "BOOT_FAIL: recovery modal survived"; return 1; }
  fi
  # Fallback: if the open-time project flow stalls (observed twice on this
  # machine), open the scene document directly — the chrome (Remote Entities
  # panel + connection indicator) does not depend on the project face.
  if ! brp jackdaw/status '{}' 2>/dev/null | jq -e '.result.project != null' >/dev/null 2>&1; then
    log "project face null after boot; trying a direct scene.open"
    brp jackdaw/call_operator '{"id":"scene.open","params":{"path":"assets/scene.bsn","reload":true}}' \
      > "$OUTDIR/live-scene-open.json" 2>/dev/null
    sleep 3; wait_idle 120
    brp jackdaw/status '{}' | jq -c '{project: .result.project, scene: .result.scene}' | tee -a "$CONSOLE_LOG"
  fi
  log "EDITOR_READY pid=$BOOT_PID"
  return 0
}

game_up() { gbrp jackdaw/app_info '{}' 2>/dev/null | jq -e '.result.app_name' >/dev/null 2>&1; }
pie() {
  # PIE via the editor is one route; the T25-precedent standalone game
  # process is the other (the editor only needs its chrome for the Remote
  # Entities panel, so a stuck project-open does not block this leg).
  if [ "${R4_STANDALONE_GAME:-1}" = "1" ]; then
    ( cd "$PROJECT" && nohup env \
        DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" \
        BEVY_ASSET_ROOT="$PROJECT" \
        ./target/debug/bsn_scene_game > "$OUTDIR/live-game.log" 2>&1 & echo $! > "$OUTDIR/live-game-pid.txt" )
    log "game launched pid=$(cat "$OUTDIR/live-game-pid.txt") (standalone, T25 form)"
    budget 120 game_up || { log "GAME_FAIL: the game BRP never answered"; return 1; }
    log "GAME_BRP_UP: $(gbrp jackdaw/app_info '{}')"
    sleep 3
    return 0
  fi
  brp jackdaw/call_operator '{"id":"pie.play_current","params":{}}' > "$OUTDIR/live-pie-play.json" 2>/dev/null
  budget 600 pie_running || { log "PIE_FAIL: status never read running"; return 1; }
  log "PIE running"
  budget 120 game_up || { log "PIE_FAIL: the game BRP never answered"; return 1; }
  log "GAME_BRP_UP: $(gbrp jackdaw/app_info '{}')"
  sleep 3
  return 0
}

game_snapshot() {
  # the producer face: what ChildOf looks like on the wire
  gbrp jackdaw/scene_snapshot '{}' > "$OUTDIR/live-game-scene_snapshot.json" 2>/dev/null
  local n
  n=$(jq -r '.result | length' "$OUTDIR/live-game-scene_snapshot.json" 2>/dev/null)
  log "GAME_SCENE_SNAPSHOT entities=$n"
  jq -c '.result[]? | select(.components["bevy_ecs::hierarchy::ChildOf"] != null) | {entity, childof: .components["bevy_ecs::hierarchy::ChildOf"]}' "$OUTDIR/live-game-scene_snapshot.json" > "$OUTDIR/live-game-childof-forms.json" 2>/dev/null
  head -c 2000 "$OUTDIR/live-game-childof-forms.json" | tee -a "$CONSOLE_LOG"
  echo | tee -a "$CONSOLE_LOG"
}

connect() {
  # find the status-bar indicator and open the popover
  brp jackdaw/ui_tree '{"text":"Disconnected","depth":3}' > "$OUTDIR/live-walk-indicator.json" 2>/dev/null
  if ! grep -qF "Disconnected" "$OUTDIR/live-walk-indicator.json"; then
    log "CONNECT: no Disconnected indicator found (maybe already connected?)"
  else
    brp jackdaw/ui_click '{"text":"Disconnected"}' > "$OUTDIR/live-click-indicator.json" 2>/dev/null
    sleep 1
    wait_idle 60
    brp jackdaw/ui_tree '{"text":"Connect","depth":5}' > "$OUTDIR/live-walk-popover.json" 2>/dev/null
    brp jackdaw/ui_click '{"text":"Connect","kind":"button"}' > "$OUTDIR/live-click-connect.json" 2>/dev/null
    sleep 2
    wait_idle 120
  fi
  budget 60 connected_label \
    && log "REMOTE_CONNECTED" || { log "CONNECT_FAIL: the indicator never read Connected"; return 1; }
  return 0
}

connected_label() {
  brp jackdaw/ui_tree '{"text":"Connected","depth":3}' 2>/dev/null | grep -qF 'Connected:'
}

walk() {
  # the panel face: dump the editor tree around the Remote Entities window
  brp jackdaw/ui_tree '{"text":"Remote Entities","depth":16}' > "$OUTDIR/live-walk-panel.json" 2>/dev/null
  brp jackdaw/ui_tree '{"depth":16}' > "$OUTDIR/live-walk-full.json" 2>/dev/null
  log "walk: panel walk $(wc -c < "$OUTDIR/live-walk-panel.json") bytes, full walk $(wc -c < "$OUTDIR/live-walk-full.json") bytes"
  return 0
}

case "${1:-all}" in
  boot) boot ;;
  pie) pie ;;
  snapshot) game_snapshot ;;
  connect) connect ;;
  walk) walk ;;
  all) boot && pie && game_snapshot && connect && walk ;;
  *) echo "usage: $0 boot|pie|snapshot|connect|walk|all"; exit 2 ;;
esac
