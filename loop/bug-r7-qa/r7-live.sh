#!/bin/bash
# R7 QA live leg: boot the editor on the bsn_game fixture (no jackdaw.toml,
# the machine-verified "Open without setup" path), build an L-shaped concave
# brush via two overlapping cubes + brush.csg_subtract, enter Face mode,
# click one face, press PageUp (the nudge), and assert the brush keeps its
# concave shape (face/vert counts unchanged), exactly one undo entry is
# recorded and undoing restores the geometry, a convex brush still nudges
# (regression anchor), and a rotated brush nudges along WORLD Y (D1 ruling).
# Usage: bash loop/bug-r7-qa/r7-live.sh <phase>
#   phase: boot | probe | live | all
set -u
REPO=/Users/linbo.zhang/workspace/jackdaw
PROJECT="$REPO/tests/fixtures/bsn_game"
PORT=15703
OUTDIR="$REPO/loop/bug-r7-qa"
TOOLCHAIN_LIB=/Users/linbo.zhang/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
EDITOR_LOG="$OUTDIR/r7-editor.log"
CONSOLE_LOG="$OUTDIR/r7-console.log"
SCENE="$PROJECT/assets/scene.bsn"
mkdir -p "$OUTDIR"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$CONSOLE_LOG"; }

brp() { # editor BRP: brp <method> <params-json> [outfile]
  local out="${4:-}"
  local reply
  reply=$(curl -s --max-time 20 -X POST "http://127.0.0.1:$PORT/" \
    -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}")
  if [ -n "$out" ]; then printf '%s' "$reply" > "$out"; fi
  printf '%s' "$reply"
}
budget() { # budget <seconds> <command...> — retry until it exits 0
  local deadline=$(( SECONDS + $1 )); shift
  while [ $SECONDS -lt $deadline ]; do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  return 1
}
wait_idle() {
  local deadline=$(( SECONDS + ${1:-300} ))
  while [ $SECONDS -lt $deadline ]; do
    if brp jackdaw/wait '{"until":"idle"}' 2>/dev/null | jq -e '.result.idle == true' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}
alive() { kill -0 "$(cat "$OUTDIR/r7-boot-pid.txt" 2>/dev/null)" 2>/dev/null; }
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
  # no-save policy: SHA the fixture scene before the run
  shasum -a 256 "$SCENE" | tee -a "$CONSOLE_LOG" > "$OUTDIR/r7-scene-sha-before.txt"
  export JACKDAW_OPEN_PROJECT="$PROJECT"
  export PATH="$HOME/.cargo/bin:$PATH"
  export JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1920x1080
  cd "$REPO"
  nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$EDITOR_LOG" 2>&1 &
  BOOT_PID=$!
  echo "$BOOT_PID" > "$OUTDIR/r7-boot-pid.txt"
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
  brp jackdaw/ui_tree '{"text":"closed unexpectedly","depth":3}' > "$OUTDIR/r7-walk-boot-recovery.json" 2>/dev/null
  if grep -qF "closed unexpectedly" "$OUTDIR/r7-walk-boot-recovery.json"; then
    log "recovery modal present, dismissing via Discard All"
    brp jackdaw/ui_click '{"text":"Discard All"}' > "$OUTDIR/r7-click-discard.json" 2>/dev/null
    sleep 2; wait_idle 120
  fi
  open_setup || true
  if ! brp jackdaw/status '{}' 2>/dev/null | jq -e '.result.project != null' >/dev/null 2>&1; then
    log "project face still null; trying a direct scene.open"
    brp jackdaw/call_operator "{\"id\":\"scene.open\",\"params\":{\"path\":\"$SCENE\",\"reload\":true}}" \
      > "$OUTDIR/r7-scene-open.json" 2>/dev/null
    sleep 3; wait_idle 120
  fi
  brp jackdaw/status '{}' | jq -c '{project: .result.project, scene: .result.scene, selection: .result.selection}' | tee -a "$CONSOLE_LOG" > "$OUTDIR/r7-status-boot.json"
  log "EDITOR_READY pid=$BOOT_PID"
  return 0
}

open_setup() {
  brp jackdaw/ui_tree '{"text":"Open without setup","depth":8}' > "$OUTDIR/r7-walk-setup-dialog.json" 2>/dev/null
  if grep -qF "Open without setup" "$OUTDIR/r7-walk-setup-dialog.json"; then
    log "setup dialog up; clicking Open without setup"
    brp jackdaw/ui_click '{"text":"Open without setup"}' > "$OUTDIR/r7-click-open-setup.json" 2>/dev/null
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

probe() {
  log "=== R7 PROBE BEGIN ==="
  # 1) operator registry on the running editor (must be the R7 binary)
  brp jackdaw/operators '{}' > "$OUTDIR/r7-operators.json" 2>/dev/null
  jq -r '.result[] | select(.id | test("nudge|csg|edit_mode|cube")) | .id' "$OUTDIR/r7-operators.json" 2>/dev/null | sort | tee "$OUTDIR/r7-ops-filtered.txt" | head -20
  log "operator ids: $(wc -l < "$OUTDIR/r7-ops-filtered.txt") matched (nudge/csg/edit_mode/cube)"
  # 2) history baseline
  brp jackdaw/history '{}' > "$OUTDIR/r7-history-baseline.json" 2>/dev/null
  log "history baseline: $(cat "$OUTDIR/r7-history-baseline.json" | jq -c '.result | {undo_len, redo_len, dirty}')"
  # 3) probe world.mutate_components on a throwaway basis: query cubes first
  brp jackdaw/world.query '{"data":{"components":["bevy_transform::components::transform::Transform","jackdaw_scene_types::Brush","bevy_core::name::Name"]},"filter":{"with":["jackdaw_scene_types::Brush"]}}' > "$OUTDIR/r7-query-brushes-0.json" 2>/dev/null
  log "initial brushes: $(cat "$OUTDIR/r7-query-brushes-0.json" | jq -c '.result' | head -c 400)"
  # 4) probe mutate availability (add one cube first)
  brp jackdaw/call_operator '{"id":"entity.add.cube","params":{}}' > "$OUTDIR/r7-add-cube-1.json" 2>/dev/null
  sleep 1; wait_idle 60; sleep 1
  brp jackdaw/world.query '{"data":{"components":["bevy_transform::components::transform::Transform","bevy_core::name::Name"]},"filter":{"with":["jackdaw_scene_types::Brush"]}}' > "$OUTDIR/r7-query-cubes-1.json" 2>/dev/null
  log "after add.cube: $(cat "$OUTDIR/r7-query-cubes-1.json" | jq -c '.result' | head -c 500)"
  log "=== R7 PROBE END ==="
}

case "${1:-all}" in
  boot) boot ;;
  probe) probe ;;
  all) boot && probe ;;
  *) echo "usage: $0 boot|probe|live|all"; exit 1 ;;
esac
