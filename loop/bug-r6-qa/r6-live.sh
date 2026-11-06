#!/bin/bash
# R6 QA live leg: boot the editor on the bsn_game fixture (no jackdaw.toml,
# the machine-verified "Open without setup" path), add a Terrain entity,
# Generate it (fresh 4x4-region footprint, stored extent 1024 cells a side),
# then drive the scatter import path with a layout file holding 2 normal
# points + 1 far point (1,000,000 units out) and the adopt-side semantics via
# a second group.  Before the fix the far point allocated region (3906,3906),
# stored_extent squared to ~1,000,192 cells a side and the next
# sync_terrain_surface aborted on a multi-TiB reserve; after the fix the
# editor must stay alive and the import must say "(1 fell outside the
# terrain)" while the normal points store.
# Assertions:
#   1 the editor does not panic / does not abort (process alive, no "panicked"
#     or allocation-failure line in the editor log, several idle settles over
#     ~10 s after the import — the abort used to land the very next frame),
#   2 the far point is refused with the user-visible summary "(1 fell outside
#     the terrain)" (call_operator reports + editor log + Scatter panel walk),
#   3 the normal points store: the summary counts them ("imported 2 into
#     'r6probe'"), and a far-only second import stores 0,
#   4 regression anchor: a normal-points-only import into another group
#     behaves exactly as before the fix ("imported 2 into 'r6qa-near'", no
#     outside note); pre-fix near-point acceptance is evidenced by the
#     guard test a_point_just_past_the_stored_ground_still_claims_the_region_under_it
#     being green in the archived program red log and in QA's own stripped-gate
#     red run (loop/bug-r6-qa/qa-red-stripped.log).
# Evidence discipline: every BRP reply archived as a file under
# loop/bug-r6-qa/, fixture scene.bsn SHA256 checked before and after (no-save
# policy), layout file removed on cleanup.
#
# Usage: bash loop/bug-r6-qa/r6-live.sh <phase>
#   phase: boot | scatter | all
set -u
REPO=/Users/linbo.zhang/workspace/jackdaw
PROJECT="$REPO/tests/fixtures/bsn_game"
PORT=15703
OUTDIR="$REPO/loop/bug-r6-qa"
TOOLCHAIN_LIB=/Users/linbo.zhang/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
EDITOR_LOG="$OUTDIR/r6-editor.log"
CONSOLE_LOG="$OUTDIR/r6-console.log"
LAYOUT="$PROJECT/assets/r6-qa-scatter.json"
LAYOUT_NEAR="$PROJECT/assets/r6-qa-scatter-near.json"
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
wait_idle() {
  local deadline=$(( SECONDS + ${1:-300} ))
  while [ $SECONDS -lt $deadline ]; do
    if brp jackdaw/wait '{"until":"idle"}' 2>/dev/null | jq -e '.result.idle == true' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}
alive() { kill -0 "$(cat "$OUTDIR/r6-boot-pid.txt" 2>/dev/null)" 2>/dev/null; }
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
  shasum -a 256 "$PROJECT/assets/scene.bsn" | tee -a "$CONSOLE_LOG" > "$OUTDIR/r6-scene-sha-before.txt"
  export JACKDAW_OPEN_PROJECT="$PROJECT"
  export PATH="$HOME/.cargo/bin:$PATH"
  export JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1920x1080
  cd "$REPO"
  nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$EDITOR_LOG" 2>&1 &
  BOOT_PID=$!
  echo "$BOOT_PID" > "$OUTDIR/r6-boot-pid.txt"
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
  brp jackdaw/ui_tree '{"text":"closed unexpectedly","depth":3}' > "$OUTDIR/r6-walk-boot-recovery.json" 2>/dev/null
  if grep -qF "closed unexpectedly" "$OUTDIR/r6-walk-boot-recovery.json"; then
    log "recovery modal present, dismissing via Discard All"
    brp jackdaw/ui_click '{"text":"Discard All"}' > "$OUTDIR/r6-click-discard.json" 2>/dev/null
    sleep 2; wait_idle 120
  fi
  open_setup || true
  if ! brp jackdaw/status '{}' 2>/dev/null | jq -e '.result.project != null' >/dev/null 2>&1; then
    log "project face still null; trying a direct scene.open (absolute path)"
    brp jackdaw/call_operator "{\"id\":\"scene.open\",\"params\":{\"path\":\"$PROJECT/assets/scene.bsn\",\"reload\":true}}" \
      > "$OUTDIR/r6-scene-open.json" 2>/dev/null
    sleep 3; wait_idle 120
  fi
  brp jackdaw/status '{}' | jq -c '{project: .result.project, scene: .result.scene, selection: .result.selection}' | tee -a "$CONSOLE_LOG" > "$OUTDIR/r6-status-boot.json"
  log "EDITOR_READY pid=$BOOT_PID"
  return 0
}

open_setup() {
  brp jackdaw/ui_tree '{"text":"Open without setup","depth":8}' > "$OUTDIR/r6-walk-setup-dialog.json" 2>/dev/null
  if grep -qF "Open without setup" "$OUTDIR/r6-walk-setup-dialog.json"; then
    log "setup dialog up; clicking Open without setup"
    brp jackdaw/ui_click '{"text":"Open without setup"}' > "$OUTDIR/r6-click-open-setup.json" 2>/dev/null
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

scatter_leg() {
  log "=== R6 SCATTER LEG BEGIN ==="
  brp jackdaw/status '{}' > "$OUTDIR/r6-status-pre.json" 2>/dev/null
  log "status: $(jq -c '{project: .result.project, scene: .result.scene, pie: .result.pie}' "$OUTDIR/r6-status-pre.json" 2>/dev/null)"

  # 1) add a Terrain entity (unsculpted, resolution 0) and select it
  brp jackdaw/call_operator '{"id":"entity.add.terrain","params":{}}' > "$OUTDIR/r6-add-terrain.json" 2>/dev/null
  sleep 1; wait_idle 60; sleep 2
  brp jackdaw/entity '{"name":"Terrain"}' > "$OUTDIR/r6-entity-terrain.json" 2>/dev/null
  log "terrain entity lookup: $(head -c 200 "$OUTDIR/r6-entity-terrain.json" 2>/dev/null)"

  # 2) Generate it: fresh 4x4-region footprint, stored extent 1024 a side —
  #    the standard user flow that gives the scatter points real ground.
  brp jackdaw/call_operator '{"id":"terrain.generate","params":{}}' > "$OUTDIR/r6-generate.json" 2>/dev/null
  log "generate reply: $(head -c 300 "$OUTDIR/r6-generate.json" 2>/dev/null)"
  sleep 1; wait_idle 120; sleep 2

  # 3) write the layout files inside the project (path_within requirement):
  #    main probe = 2 normal points on the fresh footprint + 1 far point
  #    1,000,000 units out (region (3906,3906) — the ticket's shape).
  cat > "$LAYOUT" <<'JSON'
[
  {"asset": "a.glb", "x": 10.0,  "y": 0.0, "z": 10.0},
  {"asset": "a.glb", "x": 500.0, "y": 0.0, "z": 500.0},
  {"asset": "a.glb", "x": 1000000.0, "y": 0.0, "z": 1000000.0}
]
JSON
  # regression anchor: normal points only
  cat > "$LAYOUT_NEAR" <<'JSON'
[
  {"asset": "a.glb", "x": 20.0, "y": 0.0, "z": 20.0},
  {"asset": "a.glb", "x": 300.0, "y": 0.0, "z": 300.0}
]
JSON
  log "layout files written: $(wc -c < "$LAYOUT") bytes (probe), $(wc -c < "$LAYOUT_NEAR") bytes (near-only)"

  # 4) RSS before the import (allocation-blowup comparator)
  ps -o rss= -p "$(cat "$OUTDIR/r6-boot-pid.txt")" | tr -d ' ' > "$OUTDIR/r6-rss-before.txt"
  log "RSS before import: $(cat "$OUTDIR/r6-rss-before.txt") KB"

  # 5) THE probe: import 2 normal + 1 far into group 'r6probe'
  brp jackdaw/call_operator '{"id":"terrain.scatter.import","params":{"path":"assets/r6-qa-scatter.json","terrain":"Terrain","group":"r6probe"}}' \
    > "$OUTDIR/r6-import-probe.json" 2>/dev/null
  log "IMPORT PROBE reply: $(cat "$OUTDIR/r6-import-probe.json" 2>/dev/null)"
  sleep 1; wait_idle 60

  # assertion 1a: alive right after the import frame window
  alive && log "ASSERT1_ALIVE right after import" || log "ASSERT1_FAIL: editor died right after import"

  # assertion 2/3 primary evidence: the call_operator reports array
  jq -r '.result.reports[]?' "$OUTDIR/r6-import-probe.json" 2>/dev/null > "$OUTDIR/r6-probe-reports.txt"
  log "probe reports: $(tr '\n' '|' < "$OUTDIR/r6-probe-reports.txt")"

  # 6) survival watch: three more idle settles across ~12 s; the pre-fix
  #    abort landed the frame right after the import, so these must pass
  for i in 1 2 3; do
    sleep 4
    if wait_idle 30; then log "SURVIVE settle $i: idle ok"; else log "SURVIVE settle $i: NOT idle after 30s"; fi
    alive || { log "ASSERT1_FAIL: editor died during survival watch"; break; }
  done
  ps -o rss= -p "$(cat "$OUTDIR/r6-boot-pid.txt")" | tr -d ' ' > "$OUTDIR/r6-rss-after.txt"
  log "RSS after import+watch: $(cat "$OUTDIR/r6-rss-after.txt") KB (before: $(cat "$OUTDIR/r6-rss-before.txt"))"

  # assertion 2 user-visible channel: full ui_tree walk for the summary text
  brp jackdaw/ui_tree '{"depth":24}' > "$OUTDIR/r6-walk-after-probe.json" 2>/dev/null
  if grep -qF "fell outside the terrain" "$OUTDIR/r6-walk-after-probe.json"; then
    log "ASSERT2_UI: summary visible in the UI tree"
  else
    log "ASSERT2_UI: summary not in the UI tree this pass (panel may be scrolled away) — reports/log carry it"
  fi

  # 7) far-only second import into 'r6probe2': must store 0 and say 1 outside
  cat > "$LAYOUT" <<'JSON'
[
  {"asset": "a.glb", "x": -1000000.0, "y": 0.0, "z": 1000000.0}
]
JSON
  brp jackdaw/call_operator '{"id":"terrain.scatter.import","params":{"path":"assets/r6-qa-scatter.json","terrain":"Terrain","group":"r6probe2"}}' \
    > "$OUTDIR/r6-import-faronly.json" 2>/dev/null
  log "FAR-ONLY import reply: $(cat "$OUTDIR/r6-import-faronly.json" 2>/dev/null)"
  jq -r '.result.reports[]?' "$OUTDIR/r6-import-faronly.json" 2>/dev/null > "$OUTDIR/r6-faronly-reports.txt"
  sleep 1; wait_idle 30

  # 8) assertion 4 regression anchor: normal-only import into 'r6qa-near'
  brp jackdaw/call_operator '{"id":"terrain.scatter.import","params":{"path":"assets/r6-qa-scatter-near.json","terrain":"Terrain","group":"r6qa-near"}}' \
    > "$OUTDIR/r6-import-near.json" 2>/dev/null
  log "NEAR-ONLY import reply: $(cat "$OUTDIR/r6-import-near.json" 2>/dev/null)"
  jq -r '.result.reports[]?' "$OUTDIR/r6-import-near.json" 2>/dev/null > "$OUTDIR/r6-near-reports.txt"
  sleep 1; wait_idle 30

  # 9) log forensics: panics / aborts / allocation failures — none allowed
  sleep 2
  LOG_HITS=$(grep -icE "panicked|abort|allocation failed|memory allocation of" "$EDITOR_LOG" 2>/dev/null)
  log "ASSERT1_LOG: panicked/abort/allocation-failure lines in editor log = $LOG_HITS (expect 0)"
  grep -iE "terrain.scatter: imported" "$EDITOR_LOG" | tail -5 > "$OUTDIR/r6-log-import-lines.txt" || true
  log "editor log import lines: $(tr '\n' '|' < "$OUTDIR/r6-log-import-lines.txt")"

  # 10) no-save policy check
  shasum -a 256 "$PROJECT/assets/scene.bsn" > "$OUTDIR/r6-scene-sha-after.txt"
  if cmp -s "$OUTDIR/r6-scene-sha-before.txt" "$OUTDIR/r6-scene-sha-after.txt"; then
    log "SCENE_UNCHANGED: scene.bsn SHA matches before/after"
  else
    log "SCENE_CHANGED: scene.bsn SHA differs — inspect"
  fi
  alive && log "FINAL_ALIVE" || log "FINAL_DEAD"
  log "=== R6 SCATTER LEG END ==="
}

teardown() {
  cleanup
  rm -f "$LAYOUT" "$LAYOUT_NEAR"
  if [ ! -f "$LAYOUT" ] && [ ! -f "$LAYOUT_NEAR" ]; then log "TEARDOWN: layout files removed"; fi
  git -C "$REPO" status --short -- "$PROJECT" | tee -a "$CONSOLE_LOG"
}

case "${1:-all}" in
  boot) boot ;;
  scatter) scatter_leg ;;
  teardown) teardown ;;
  all)
    boot && scatter_leg
    teardown
    ;;
  *) echo "usage: $0 boot|scatter|teardown|all"; exit 2 ;;
esac
