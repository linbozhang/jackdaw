#!/bin/bash
# T15-T3: quiet manual game-channel verification (the T2 QA method: no
# editor running, so the AN9 empty-read window stays closed). For each
# channel (staged, direct): boot on the purged graph.bsn, assert the
# channel's stdout carries zero leaked-node warns (AN10 green), and drive
# the parity sequence with the T2 driver.
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
PROJECT=/Users/zhanglinbo/workspace/loop-mac/t15-anim/t15-anim
STAGED="$PROJECT/.jackdaw/dist/release"
OUT="$REPO/loop/t15-live"
REPORTS="$REPO/loop/reports"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
CONSOLE="$REPORTS/t15t3_channels_console.log"
: > "$CONSOLE"
log() { echo "$@" | tee -a "$CONSOLE"; }
cleanup() { pkill -x t15-anim 2>/dev/null; sleep 1; }
trap cleanup EXIT
pkill -x jackdaw 2>/dev/null; pkill -x t15-anim 2>/dev/null; sleep 1

flow_start_scene() { # <dir> <scene>
  python3 - "$1/assets/game.flow.json" "$2" << 'PYT'
import json, sys
path, scene = sys.argv[1], sys.argv[2]
flow = json.load(open(path))
flow["start_scene"] = scene
if scene not in flow["scenes"]:
    flow["scenes"].append(scene)
json.dump(flow, open(path, "w"), indent=2)
PYT
}
wait_game() {
  local deadline=$((SECONDS + ${1:-300}))
  while [ $SECONDS -lt $deadline ]; do
    curl -s -m 5 -X POST "http://127.0.0.1:15702/" -H 'Content-Type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"jackdaw/app_info"}' | jq -e '.result.app_name' >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}
leak_warns() { grep -Ec "GraphNode|cannot apply" "$1" 2>/dev/null; }

# ---- staged channel ----
flow_start_scene "$STAGED" graph.bsn
(cd "$STAGED" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./t15-anim > "$OUT/t15t3-staged-run.log" 2>&1 &)
if wait_game 300; then
  sleep 4
  log "STAGED_UP leak_warns=$(leak_warns "$OUT/t15t3-staged-run.log")"
  python3 "$REPORTS/t15t2_parity_driver.py" t3-staged-manual 2>&1 | tail -3 | tee -a "$CONSOLE"
  cp "$OUT/parity-t3-staged-manual.json" "$REPORTS/t15t3_parity_staged_manual.json"
else
  log "STAGED_NEVER_UP"
fi
pkill -x t15-anim 2>/dev/null; sleep 2

# ---- direct channel ----
flow_start_scene "$PROJECT" graph.bsn
(cd "$PROJECT" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" cargo run > "$OUT/t15t3-direct-run.log" 2>&1 &)
if wait_game 600; then
  sleep 4
  log "DIRECT_UP leak_warns=$(leak_warns "$OUT/t15t3-direct-run.log")"
  python3 "$REPORTS/t15t2_parity_driver.py" t3-direct-manual 2>&1 | tail -3 | tee -a "$CONSOLE"
  cp "$OUT/parity-t3-direct-manual.json" "$REPORTS/t15t3_parity_direct_manual.json"
else
  log "DIRECT_NEVER_UP"
fi
pkill -x t15-anim 2>/dev/null; sleep 2
flow_start_scene "$PROJECT" anim.bsn   # restore the canonical start scene

log "STAGED_LEAK_WARNS=$(leak_warns "$OUT/t15t3-staged-run.log") DIRECT_LEAK_WARNS=$(leak_warns "$OUT/t15t3-direct-run.log")"
log "T15T3_CHANNELS_DONE"
