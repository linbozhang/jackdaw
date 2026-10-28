#!/bin/bash
# T11-T3 C7 retry (macOS): the a2 C7 legs read CameraLook directly, but that
# component is deliberately runtime-only (no Reflect derive) and never appears
# in any scene snapshot - on any machine. Observation channel here is the
# orbit rig's local Transform offset instead: the driver places the rig at
# (0, h, distance) rotated by yaw, so the local offset's XZ angle IS the yaw.
# Assert: |delta atan2(x, z) of the rig local offset| ~= |dx * sensitivity|
# (open channel: 200 * 0.005 = 1.0 rad, window +-0.15; RMB-held frames: the
# bridge yields and no real mouse motion reaches the crate channel, so the
# same injection must not rotate the rig, window 0.05).
# Requires the fixture's mouse ButtonInput registration (added after a2).
# Usage: bash loop/qa/t11t3-matrix-a3.sh [project] [port]
set -u
PROJECT="${1:-/Users/zhanglinbo/workspace/loop-mac/t11t1-game}"
PORT="${2:-15804}"
REPO=/Users/zhanglinbo/workspace/jackdaw
OUTDIR="$REPO/loop/t11t3-live"
EDITOR_LOG="$OUTDIR/t11t3-a3-mac-editor.log"
CONSOLE_LOG="$OUTDIR/t11t3-a3-mac-console.log"
SUMMARY="$OUTDIR/t11t3-a3-mac-summary.txt"
GAME_PORT=15702
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
MB_RES='bevy_input::button_input::ButtonInput<bevy_input::mouse::MouseButton>'
mkdir -p "$OUTDIR"
: > "$CONSOLE_LOG"
RESULTS_FILE="$(mktemp /tmp/t11t3-a3-results.XXXXXX)"
touch "$RESULTS_FILE"
TKEY='bevy_transform::components::transform::Transform'

log() { echo "$@" | tee -a "$CONSOLE_LOG"; }
leg() {
  case "$2" in
    true|0) r=PASS ;;
    *) r=FAIL ;;
  esac
  echo "$1=$r" >> "$RESULTS_FILE"
  log "${1}_${r}"
}
summary_line() { sort "$RESULTS_FILE" | tr '\n' ' '; }
brp() {
  local port="$1" method="$2" params="${3:-}" body id=$RANDOM
  if [ -n "$params" ]; then
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params")
  else
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s"}' "$id" "$method")
  fi
  curl -s -m 30 -X POST "http://127.0.0.1:$port/" -H 'Content-Type: application/json' -d "$body"
}
op() {
  local id="$1" params="${2:-}"
  if [ -n "$params" ]; then brp "$PORT" jackdaw/call_operator "{\"id\":\"$id\",\"params\":$params}"
  else brp "$PORT" jackdaw/call_operator "{\"id\":\"$id\"}"; fi
}
wait_idle() {
  local deadline=$((SECONDS + ${1:-600}))
  while [ $SECONDS -lt $deadline ]; do
    if brp "$PORT" jackdaw/wait '{"until":"idle"}' | jq -e '.result.idle == true' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}
stop_pie() {
  for _ in 1 2 3 4; do
    op pie.stop >/dev/null 2>&1
    sleep 2
    st=$(brp "$PORT" jackdaw/status '{}' | jq -r '.result.pie // empty' 2>/dev/null)
    [ "$st" = stopped ] && break
  done
}
dismiss_dialog() {
  local st
  st=$(brp "$PORT" jackdaw/status '{}' 2>/dev/null | jq -r '.result.dialog // empty' 2>/dev/null)
  if [ -n "$st" ] && [ "$st" != "null" ]; then
    log "dialog up: $st"
    op dialog.answer '{"choice":"0"}' >/dev/null 2>&1
    sleep 2
  fi
}
# The active rig's local offset angle in the XZ plane, in degrees.
# Editor projection snapshot first, the game's own world as fallback.
rig_angle() {
  local jq='[.result[]
    | select(any(.components | keys[]; endswith("ActiveCameraRig")))
    | .components[$t].translation] | first
    | if . then "\([.[0], .[2]] | @tsv)" else empty end'
  local v
  v=$(brp "$PORT" jackdaw/scene_snapshot '{}' | jq -r --arg t "$TKEY" "$jq" 2>/dev/null)
  if [ -z "$v" ]; then
    v=$(brp "$GAME_PORT" jackdaw/scene_snapshot '{}' | jq -r --arg t "$TKEY" "$jq" 2>/dev/null)
  fi
  [ -n "$v" ] && python3 -c "import math; x, z = map(float, '$v'.split()); print(math.degrees(math.atan2(x, z)))"
}

pkill -x jackdaw 2>/dev/null; pkill -f 't11t1-game$' 2>/dev/null
sleep 1
export JACKDAW_OPEN_PROJECT="$PROJECT"
export JACKDAW_REMOTE_PORT="$PORT"
export JACKDAW_WINDOW_SIZE=1600x900
cd "$REPO"
nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$EDITOR_LOG" 2>&1 &
ok=""
for i in $(seq 1 150); do
  sleep 2
  if brp "$PORT" jackdaw/status '{}' >/dev/null 2>&1; then ok=1; break; fi
  pgrep -x jackdaw >/dev/null || { log "EDITOR_BOOT_FAIL"; exit 1; }
done
[ -n "$ok" ] || { log "EDITOR_BOOT_FAIL (timeout)"; exit 1; }
wait_idle 600; sleep 3
dismiss_dialog
log "EDITOR_READY"

op scene.open "{\"path\":\"$PROJECT/assets/scene.bsn\"}" >/dev/null 2>&1
sleep 2
op pie.play_current >/dev/null 2>&1
for i in $(seq 1 90); do
  sleep 1
  brp "$GAME_PORT" jackdaw/app_info '{}' 2>/dev/null | jq -e '.result.app_name' >/dev/null 2>&1 && break
done
sleep 3
op pie.play_input_toggle >/dev/null 2>&1   # capture on
sleep 2
a0=$(rig_angle)
op input.motion '{"dx":200,"dy":0,"steps":20}' >/dev/null 2>&1
sleep 2
a1=$(rig_angle)
c7_open=false; c7_open_delta=999
if [ -n "$a0" ] && [ -n "$a1" ]; then
  c7_open_delta=$(python3 -c "print(abs($a1 - $a0))")
  log "C7 open-channel: rigXZangle $a0 -> $a1 deg, |delta|=$c7_open_delta (expect ~57.3 deg = 1.0 rad = dx*0.005)"
  python3 -c "import sys; sys.exit(0 if abs(abs($a1 - $a0) - 57.29578) < 8.5 else 1)" && c7_open=true
else
  log "C7 open-channel: rig angle read failed ($a0 -> $a1)"
fi
leg C7_LOOK_OPEN_CHANNEL "$c7_open"

# RMB-held: the bridge yields those frames (decision 3-3), and the crate's
# own RMB channel legitimately owns the turn - the editor's synthetic motion
# IS a real MouseMotion event to the game, so with RMB held the crate channel
# applies it. The yield therefore asserts "exactly one channel wrote": the
# same |delta| as the open leg (57.3 +- 8.5 deg). Had the bridge failed to
# yield, both channels would write and the rig would turn ~114.6 deg.
mb=$(brp "$GAME_PORT" world.get_resources "{\"resource\":\"$MB_RES\"}" | jq -r '.result.value.pressed // .error.message // empty' 2>/dev/null)
log "C7 mouse resource probe: ${mb:0:50}"
c7_rmb=false
if [ -n "$mb" ]; then
  brp "$GAME_PORT" world.insert_resources "{\"resource\":\"$MB_RES\",\"value\":{\"pressed\":[\"Right\"],\"just_pressed\":[\"Right\"],\"just_released\":[]}}" >/dev/null 2>&1
  sleep 1
  a2v=$(rig_angle)
  op input.motion '{"dx":200,"dy":0,"steps":20}' >/dev/null 2>&1
  sleep 2
  a3v=$(rig_angle)
  brp "$GAME_PORT" world.insert_resources "{\"resource\":\"$MB_RES\",\"value\":{\"pressed\":[],\"just_pressed\":[],\"just_released\":[]}}" >/dev/null 2>&1
  if [ -n "$a2v" ] && [ -n "$a3v" ]; then
    log "C7 rmb-held: rigXZangle $a2v -> $a3v deg (single write ~57.3 = crate channel only; double would be ~114.6)"
    python3 -c "import sys; sys.exit(0 if abs(abs($a3v - $a2v) - 57.29578) < 8.5 else 1)" && c7_rmb=true
  else
    log "C7 rmb-held: rig angle read failed ($a2v -> $a3v)"
  fi
fi
leg C7_LOOK_RMB_YIELD "$c7_rmb"

op pie.play_input_toggle >/dev/null 2>&1
stop_pie; dismiss_dialog
pkill -x jackdaw 2>/dev/null; pkill -f 't11t1-game$' 2>/dev/null
printf '%s\n' "$(summary_line)" > "$SUMMARY"
log "VERDICT_A3_MAC: $(summary_line)"
log "T11T3_A3_MAC_DONE"
