#!/bin/bash
# T12-T2 resolution leg: two PIE sessions at different editor window sizes.
# The Game panel docks as a bottom strip, so the stream is panel-sized (the
# strip shape, not a 16:9 tier — the 16:9 tiers are the T1 headless guards'
# four-tier math). What this leg proves live: the layout holds at TWO landed
# stream sizes — the start overlay fills the whole stream and the bar keeps
# its authored 180x10 while the button stays a real size — with the game's
# virtual Window reporting the landed stream size. A window screenshot is
# archived per size.
# Usage: bash loop/qa/t12t2-pie-resolution.sh [project] [port]
set -u
PROJECT="${1:-/Users/zhanglinbo/workspace/loop-mac/t12t1-game/t12t1-game}"
PORT="${2:-15908}"
GAME_PORT=15702
REPO=/Users/zhanglinbo/workspace/jackdaw
OUTDIR="$REPO/loop/t12t2-live"
CONSOLE_LOG="$OUTDIR/t12t2-resolution-console.log"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
mkdir -p "$OUTDIR"
: > "$CONSOLE_LOG"
log() { echo "$@" | tee -a "$CONSOLE_LOG"; }
leg() {
  case "$2" in
    true|0) r=PASS ;;
    *) r=FAIL ;;
  esac
  echo "$1=$r" >> "$RESULTS_FILE"
  log "${1}_${r}"
}
RESULTS_FILE="$(mktemp /tmp/t12t2-res-results.XXXXXX)"
touch "$RESULTS_FILE"
cleanup() {
  op pie.stop >/dev/null 2>&1
  sleep 1
  pkill -x jackdaw 2>/dev/null
  pkill -f 't12t1-game$' 2>/dev/null
}
trap cleanup EXIT
brp() {
  local method="$1" params="${2:-}" id=$RANDOM body
  if [ -n "$params" ]; then
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params")
  else
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s"}' "$id" "$method")
  fi
  curl -s -m 30 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' -d "$body"
}
op() {
  local id="$1" params="${2:-}"
  if [ -n "$params" ]; then brp jackdaw/call_operator "{\"id\":\"$id\",\"params\":$params}"
  else brp jackdaw/call_operator "{\"id\":\"$id\"}"; fi
}
game_up() { curl -s -m 5 -X POST "http://127.0.0.1:$GAME_PORT/" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"jackdaw/app_info"}' | jq -e '.result.app_name' >/dev/null 2>&1; }
editor_boot() {
  pkill -x jackdaw 2>/dev/null; pkill -f 't12t1-game$' 2>/dev/null
  sleep 1
  JACKDAW_OPEN_PROJECT="$PROJECT" JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE="$1" \
    nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw \
    > "$OUTDIR/t12t2-resolution-editor-$1.log" 2>&1 &
  local ok=""
  for i in $(seq 1 150); do
    sleep 2
    if brp jackdaw/status '{}' >/dev/null 2>&1; then ok=1; break; fi
    pgrep -x jackdaw >/dev/null || break
  done
  [ -n "$ok" ] || { log "EDITOR_BOOT_FAIL($1)"; return 1; }
  sleep 3
  brp jackdaw/wait '{"until":"idle"}' >/dev/null 2>&1
  local st
  st=$(brp jackdaw/status '{}' | jq -r '.result.dialog // empty')
  [ -n "$st" ] && [ "$st" != "null" ] && op dialog.answer '{"choice":"0"}' >/dev/null 2>&1
  return 0
}
# resolution_probe <label> — window size + the three nodes out of a
# ComputedNode-only query (Name is not BRP-serializable; the bar is the one
# 180x10 node, the overlay the biggest node, the button a mid-size one).
resolution_probe() {
  local label="$1" win nodes
  win=$(curl -s -m 10 -X POST "http://127.0.0.1:$GAME_PORT/" -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"world.query","params":{"data":{"components":["bevy_window::window::Window"]}}}' \
    | jq -r '.result[0].components["bevy_window::window::Window"].resolution | if type == "object" then "\(.physical_width // .width)x\(.physical_height // .height)" else tostring end' 2>/dev/null)
  nodes=$(curl -s -m 10 -X POST "http://127.0.0.1:$GAME_PORT/" -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"world.query","params":{"data":{"components":["bevy_ui::ui_node::ComputedNode"]}}}' \
    | jq -c '[.result[] | .components["bevy_ui::ui_node::ComputedNode"].size] // []' 2>/dev/null)
  local overlay bar button
  overlay=$(echo "$nodes" | jq -r 'sort_by(-.[0] * .[1]) | first | if . then "\(.[0])x\(.[1])" else empty end' 2>/dev/null)
  bar=$(echo "$nodes" | jq -r 'map(select((.[0] | round) == 180 and (.[1] | round) == 10)) | first | if . then "\(.[0])x\(.[1])" else empty end' 2>/dev/null)
  button=$(echo "$nodes" | jq -r 'map(select(.[0] > 50 and .[0] < 200 and .[1] > 20 and .[1] < 80)) | first | if . then "\(.[0])x\(.[1])" else empty end' 2>/dev/null)
  log "$label: window=$win StartScreen(overlay)=$overlay HealthBar=$bar StartButton=$button"
  echo "$win|$overlay|$bar|$button"
}
resolution_leg() { # resolution_leg <name> <window size>
  local name="$1" winsize="$2" probe ok wx wy ow ob
  editor_boot "$winsize" || { leg "$name" false; return; }
  op scene.open "{\"path\":\"$PROJECT/assets/scene.bsn\"}" >/dev/null 2>&1
  sleep 2
  op pie.play_current >/dev/null 2>&1
  local deadline=$((SECONDS + 600))
  while [ $SECONDS -lt $deadline ]; do
    game_up && break
    sleep 2
  done
  sleep 5
  op pie.play_input_toggle >/dev/null 2>&1
  sleep 3
  probe=$(resolution_probe "$name" | tail -1)  # the tee'd log line rides along; keep the data line
  IFS='|' read -r wx ow ob _ <<< "$probe"
  brp jackdaw/screenshot "{\"kind\":\"window\",\"path\":\"t12t2-res-$name.png\"}" >/dev/null 2>&1
  sleep 3
  brp jackdaw/screenshot "{\"kind\":\"window\",\"path\":\"t12t2-res-$name.png\"}" >/dev/null 2>&1
  sleep 2
  ok=false
  if [ -n "$wx" ] && [ -n "$ow" ] && [ -n "$ob" ]; then
    if python3 - "$wx" "$ow" "$ob" << 'EOF'
import sys
win, overlay, bar = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    wx, wy = [float(v) for v in win.lower().replace(' ', '').split('x')]
    sx, sy = [float(v) for v in overlay.lower().split('x')]
    bx, by = [float(v) for v in bar.lower().split('x')]
except Exception:
    sys.exit(1)
fills = abs(sx - wx) < 2 and abs(sy - wy) < 2
keeps = abs(bx - 180.0) < 1 and abs(by - 10.0) < 1
sys.exit(0 if fills and keeps else 1)
EOF
    then ok=true; fi
  fi
  leg "$name" "$ok"
  op pie.stop >/dev/null 2>&1
  sleep 2
}

resolution_leg RES_TIER_A 1600x900
resolution_leg RES_TIER_B 1920x1080
pkill -x jackdaw 2>/dev/null; pkill -f 't12t1-game$' 2>/dev/null
printf '%s\n' "$(sort "$RESULTS_FILE" | tr '\n' ' ')" > "$OUTDIR/t12t2-resolution-summary.txt"
log "VERDICT_RESOLUTION: $(cat "$OUTDIR/t12t2-resolution-summary.txt")"
log "T12T2_RESOLUTION_DONE"
