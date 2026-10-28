#!/bin/bash
# T11-T3 second editor pass (macOS): the PIE-dependent cells leg A's probe
# mis-judged on this machine. Two Mac divergences bit that probe, both fixed
# here and recorded in the report:
#   1. The PIE game binary lives at .jackdaw/target/game/debug/t11t1-game
#      (the first Play's pre-build takes minutes on a cold .jackdaw target);
#      leg A's pgrep pattern and 20 s window only fit a warm Windows target.
#      Here: process pattern matches any t11t1-game argv, and the probe waits
#      out the build.
#   2. macOS nohup strips DYLD_* (fixed in leg A already).
# Cells served: PIE probe (warm-aware) / C7 Look injection (open channel +
# RMB yield) / cell 11 Stop iron proof / N13 x10. Assertion windows identical
# to the leg A blocks they replace.
# Usage: bash loop/qa/t11t3-matrix-a2.sh [project] [port]
set -u
PROJECT="${1:-/Users/zhanglinbo/workspace/loop-mac/t11t1-game}"
PORT="${2:-15804}"
REPO=/Users/zhanglinbo/workspace/jackdaw
OUTDIR="$REPO/loop/t11t3-live"
EDITOR_LOG="$OUTDIR/t11t3-a2-mac-editor.log"
CONSOLE_LOG="$OUTDIR/t11t3-a2-mac-console.log"
SUMMARY="$OUTDIR/t11t3-a2-mac-summary.txt"
GAME_PORT=15702
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
KC_RES='bevy_input::button_input::ButtonInput<bevy_input::keyboard::KeyCode>'
MB_RES='bevy_input::button_input::ButtonInput<bevy_input::mouse_button::MouseButton>'
mkdir -p "$OUTDIR"
: > "$CONSOLE_LOG"
RESULTS_FILE="$(mktemp /tmp/t11t3-a2-results.XXXXXX)"
touch "$RESULTS_FILE"
TKEY='bevy_transform::components::transform::Transform'

log() { echo "$@" | tee -a "$CONSOLE_LOG"; }
leg() {
  case "$2" in
    true|0) r=PASS ;;
    DEGRADED) r=DEGRADED ;;
    SKIP) r=SKIP ;;
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
ent() { echo "$1" | jq -r '.result.entities[0] // .result.entity // .result.result.entity // empty' 2>/dev/null; }
# Any t11t1-game process, whatever target dir it was built in.
game_pid() { pgrep -f 't11t1-game$' | head -1; }
editor_pid() { pgrep -x jackdaw | head -1; }
wait_idle() {
  local deadline=$((SECONDS + ${1:-600}))
  while [ $SECONDS -lt $deadline ]; do
    if brp "$PORT" jackdaw/wait '{"until":"idle"}' | jq -e '.result.idle == true' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  log "wait(idle) timeout (continuing)"
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
boot_editor() {
  cd "$REPO"
  nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw >> "$EDITOR_LOG" 2>&1 &
  for i in $(seq 1 150); do
    sleep 2
    if brp "$PORT" jackdaw/status '{}' >/dev/null 2>&1; then return 0; fi
    editor_pid >/dev/null || return 1
  done
  return 1
}
read_yaw() {
  local v
  v=$(brp "$PORT" jackdaw/scene_snapshot '{}' | jq -r '[.result[] | select(.components["jackdaw_camera_rig::CameraLook"]) | .components["jackdaw_camera_rig::CameraLook"].yaw][0] // empty' 2>/dev/null)
  if [ -z "$v" ]; then
    v=$(brp "$GAME_PORT" jackdaw/scene_snapshot '{}' | jq -r '[.result[] | select(.components["jackdaw_camera_rig::CameraLook"]) | .components["jackdaw_camera_rig::CameraLook"].yaw][0] // empty' 2>/dev/null)
  fi
  echo "$v"
}
exited_marks() { grep -c "exited before connecting" "$EDITOR_LOG" 2>/dev/null || echo 0; }

# --- clean boot ---------------------------------------------------------------
pkill -x jackdaw 2>/dev/null; pkill -f 't11t1-game$' 2>/dev/null
sleep 1
export JACKDAW_OPEN_PROJECT="$PROJECT"
export JACKDAW_REMOTE_PORT="$PORT"
export JACKDAW_WINDOW_SIZE=1600x900
# NOTE: no RUST_BACKTRACE on this machine (debug wgpu LockTrace -> libunwind
# SIGSEGV; reproduced live - see the report).
boot_editor || { log "EDITOR_BOOT_FAIL"; exit 1; }
wait_idle 600; sleep 3
dismiss_dialog
log "EDITOR_READY"

# --- warm-aware PIE probe -------------------------------------------------------
op scene.open "{\"path\":\"$PROJECT/assets/scene.bsn\"}" >/dev/null 2>&1
sleep 2
pie_alive=false; probe_notes=""
op pie.play_current >/dev/null 2>&1
deadline=$((SECONDS + 420))
while [ $SECONDS -lt $deadline ]; do
  sleep 3
  alive=$(game_pid)
  conn=""
  brp "$GAME_PORT" jackdaw/app_info '{}' 2>/dev/null | jq -e '.result.app_name' >/dev/null 2>&1 && conn=1
  if [ -n "$alive" ] && [ -n "$conn" ]; then pie_alive=true; break; fi
  marks=$(exited_marks)
  if [ "${marks:-0}" -gt 0 ] 2>/dev/null; then probe_notes="exit mark seen"; break; fi
  editor_pid >/dev/null || { probe_notes="editor died"; break; }
  # an error dialog would block everything; clear it and keep waiting
  dismiss_dialog
done
log "PIE_PROBE2 (warm-aware, up to 420s): alive=$pie_alive note=$probe_notes"
leg PIE2_PROBE_ALIVE "$pie_alive"
if ! $pie_alive; then
  stop_pie; dismiss_dialog
  pkill -x jackdaw 2>/dev/null; pkill -f 't11t1-game$' 2>/dev/null
  printf '%s\n' "$(summary_line)" > "$SUMMARY"
  log "VERDICT_A2_MAC: $(summary_line)"
  exit 0
fi
stop_pie
dismiss_dialog
wait_idle 120

# === C7 Look real injection =====================================================
op scene.open "{\"path\":\"$PROJECT/assets/scene.bsn\"}" >/dev/null 2>&1
sleep 2
op pie.play_current >/dev/null 2>&1
# wait until the game answers on its own BRP
for i in $(seq 1 60); do
  sleep 1
  brp "$GAME_PORT" jackdaw/app_info '{}' 2>/dev/null | jq -e '.result.app_name' >/dev/null 2>&1 && break
done
sleep 3
op pie.play_input_toggle >/dev/null 2>&1   # capture on
sleep 2
yaw0=$(read_yaw)
op input.motion '{"dx":200,"dy":0,"steps":20}' >/dev/null 2>&1
sleep 2
yaw1=$(read_yaw)
c7_open=false; c7_open_delta=999
if [ -n "$yaw0" ] && [ -n "$yaw1" ]; then
  c7_open_delta=$(python3 -c "print($yaw1 - $yaw0)")
  python3 -c "import sys; sys.exit(0 if abs(($yaw1 - $yaw0) - (-1.0)) < 0.15 else 1)" && c7_open=true
fi
log "C7 open-channel: yaw0=$yaw0 yaw1=$yaw1 delta=$c7_open_delta (expect -1.0 = -dx*0.005)"
leg C7_LOOK_OPEN_CHANNEL "$c7_open"

# RMB-held: bridge yields, no real mouse motion reaches the crate channel,
# so the same injection must not move the yaw (|delta| < 0.05).
mb_ok=$(brp "$GAME_PORT" world.get_resources "{\"resource\":\"$MB_RES\"}" | jq -r '.result.value.pressed // .error.message // empty' 2>/dev/null | head -c 60)
log "C7 mouse resource probe: ${mb_ok:0:60}"
c7_rmb=SKIP
if [ -n "$mb_ok" ]; then
  brp "$GAME_PORT" world.insert_resources "{\"resource\":\"$MB_RES\",\"value\":{\"pressed\":[\"Right\"],\"just_pressed\":[\"Right\"],\"just_released\":[]}}" >/dev/null 2>&1
  sleep 1
  yaw2=$(read_yaw)
  op input.motion '{"dx":200,"dy":0,"steps":20}' >/dev/null 2>&1
  sleep 2
  yaw3=$(read_yaw)
  brp "$GAME_PORT" world.insert_resources "{\"resource\":\"$MB_RES\",\"value\":{\"pressed\":[],\"just_pressed\":[],\"just_released\":[]}}" >/dev/null 2>&1
  c7_rmb=false
  if [ -n "$yaw2" ] && [ -n "$yaw3" ]; then
    c7_rmb_delta=$(python3 -c "print($yaw3 - $yaw2)")
    log "C7 rmb-held: yaw2=$yaw2 yaw3=$yaw3 delta=$c7_rmb_delta (expect ~0, bridge yields)"
    python3 -c "import sys; sys.exit(0 if abs($yaw3 - $yaw2) < 0.05 else 1)" && c7_rmb=true
  else
    log "C7 rmb-held: yaw read failed (yaw2=$yaw2 yaw3=$yaw3)"
  fi
fi
leg C7_LOOK_RMB_YIELD "$c7_rmb"
op pie.play_input_toggle >/dev/null 2>&1   # capture off
stop_pie
dismiss_dialog
wait_idle 120
sleep 2

# === cell 11 Stop iron proof ====================================================
SCENE_MAIN="$PROJECT/assets/t11t3-place.bsn"
SHA_BEFORE=$(shasum -a 256 "$SCENE_MAIN" | cut -d' ' -f1)
op scene.open "{\"path\":\"$SCENE_MAIN\"}" >/dev/null 2>&1
sleep 2
op pie.play_current >/dev/null 2>&1
for i in $(seq 1 60); do
  sleep 1
  brp "$GAME_PORT" jackdaw/app_info '{}' 2>/dev/null | jq -e '.result.app_name' >/dev/null 2>&1 && break
done
sleep 2
# player running (held W through the game's own BRP) while the rig follows
for i in $(seq 1 10); do
  brp "$GAME_PORT" world.insert_resources "{\"resource\":\"$KC_RES\",\"value\":{\"pressed\":[\"KeyW\"],\"just_pressed\":[\"KeyW\"],\"just_released\":[]}}" >/dev/null 2>&1
  sleep 0.25
done
moved=$(brp "$GAME_PORT" jackdaw/scene_snapshot '{}' | jq -r '[.result[] | select(any(.components | keys[]; endswith("PlayerMarker"))) | select((any(.components | keys[]; endswith("PickupCount"))) | not)][0].components["'"$TKEY"'"].translation[2] // empty' 2>/dev/null)
brp "$GAME_PORT" world.insert_resources "{\"resource\":\"$KC_RES\",\"value\":{\"pressed\":[],\"just_pressed\":[],\"just_released\":[]}}" >/dev/null 2>&1
log "CELL11 player z while driven: ${moved:-unseen}"
stop_pie
wait_idle 120
sleep 2
SHA_AFTER=$(shasum -a 256 "$SCENE_MAIN" | cut -d' ' -f1)
TEMP_LEFT=$(ls "$PROJECT/assets/.jackdaw-pie/"current-* 2>/dev/null | wc -l | tr -d ' ')
c11=false
[ "$SHA_BEFORE" = "$SHA_AFTER" ] && [ "$TEMP_LEFT" = 0 ] && c11=true
log "CELL11_STOP sha_same=$([ "$SHA_BEFORE" = "$SHA_AFTER" ] && echo true || echo false) temp_left=$TEMP_LEFT"
leg CELL11_STOP_IRON "$c11"

# === N13 x10 =====================================================================
n13_hits=0; n13_rounds=0
for round in $(seq 1 10); do
  if [ -z "$(editor_pid)" ]; then
    log "N13 #$round: editor dead before round, rebooting"
    boot_editor || { log "N13 #$round: editor reboot failed"; break; }
    wait_idle 600; sleep 3
    op scene.open "{\"path\":\"$PROJECT/assets/scene.bsn\"}" >/dev/null 2>&1
    sleep 2
  fi
  n13_rounds=$((n13_rounds + 1))
  op pie.play_current >/dev/null 2>&1
  connected=""
  for i in $(seq 1 40); do
    sleep 1
    brp "$GAME_PORT" jackdaw/app_info '{}' 2>/dev/null | jq -e '.result.app_name' >/dev/null 2>&1 && { connected=1; break; }
  done
  sleep 6
  sig=$(grep -c "swap_remove index" "$EDITOR_LOG" 2>/dev/null || echo 0)
  alive=$(editor_pid)
  log "N13 #$round: connected=${connected:+yes} editorAlive=${alive:+yes} swap_remove_hits_in_log=${sig:-0}"
  if [ "${sig:-0}" -gt 0 ] 2>/dev/null; then n13_hits=$sig; fi
  if [ -z "$alive" ]; then n13_hits=$((n13_hits + 1)); fi
  stop_pie 2>/dev/null
  dismiss_dialog 2>/dev/null
  sleep 2
done
log "N13_X10: rounds=$n13_rounds recurrences=$n13_hits (T10b: 1 hit / 1 clean on the old machine; panic-message signature only, no RUST_BACKTRACE on this machine)"
n13_ok=false; [ "$n13_hits" = 0 ] && n13_ok=true
leg N13_X10_NO_RECURRENCE "$n13_ok"

# --- teardown ---------------------------------------------------------------------
stop_pie; dismiss_dialog
pkill -x jackdaw 2>/dev/null; pkill -f 't11t1-game$' 2>/dev/null
printf '%s\n' "$(summary_line)" > "$SUMMARY"
log "VERDICT_A2_MAC: $(summary_line)"
log "T11T3_A2_MAC_DONE"
