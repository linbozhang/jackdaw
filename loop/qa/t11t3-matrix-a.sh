#!/bin/bash
# T11-T3 acceptance matrix, editor leg (macOS port of t11t3-matrix-a.ps1).
# Same cells and assertion windows as the Windows original, letter for
# letter where the cell existed there. Mac environment divergences,
# all recorded in the T11-T3 report:
#   - No RUST_BACKTRACE=1: debug wgpu-core's snatch-lock LockTrace calls
#     Backtrace::capture() on every lock enter, and unwinding this ~1 GB
#     debug binary stalls the loop and then segfaults in libunwind
#     (KERN_INVALID_ADDRESS at 0x0) - reproduced live on this machine.
#   - Editor boot: nohup + DYLD_LIBRARY_PATH to the rustup toolchain's
#     libstd dylib (the editor is a bevy dynamic_linking build).
#   - PIE probe first: if PIE is alive (Metal is expected to survive
#     where the old machine's NVIDIA driver died), the deferred real
#     cells run this round: C7 Look injection (input.motion -> CameraLook
#     yaw, bridge yields on RMB-held frames), cell 11 Stop iron proof,
#     N13 drain_game_events recurrence x10.
#   - M9 supplement (old leg had no evidence for eye_height): the
#     FirstPerson variant scene gets eye_height authored, and leg C's
#     round 4 asserts the rig offset follows it.
# Cells served: PROBE / C7 / CELL11_STOP / N13_X10 / M2 / N14 / M8+M9 /
# M7-pre / M6-pre.
# Usage: bash loop/qa/t11t3-matrix-a.sh [project] [port]
set -u
PROJECT="${1:-/Users/zhanglinbo/workspace/loop-mac/t11t1-game}"
PORT="${2:-15804}"
REPO=/Users/zhanglinbo/workspace/jackdaw
OUTDIR="$REPO/loop/t11t3-live"
EDITOR_LOG="$OUTDIR/t11t3-a-mac-editor.log"
CONSOLE_LOG="$OUTDIR/t11t3-a-mac-console.log"
SUMMARY="$OUTDIR/t11t3-a-mac-summary.txt"
GAME_PORT=15702
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
KC_RES='bevy_input::button_input::ButtonInput<bevy_input::keyboard::KeyCode>'
MB_RES='bevy_input::button_input::ButtonInput<bevy_input::mouse_button::MouseButton>'
mkdir -p "$OUTDIR"
: > "$CONSOLE_LOG"
RESULTS_FILE="$(mktemp /tmp/t11t3-results.XXXXXX)"
touch "$RESULTS_FILE"
TKEY='bevy_transform::components::transform::Transform'

log() { echo "$@" | tee -a "$CONSOLE_LOG"; }
leg() { # leg NAME OK|DEGRADED|SKIP
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

brp() { # brp PORT method json-params
  local port="$1" method="$2" params="${3:-}"
  local body id=$RANDOM
  if [ -n "$params" ]; then
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params")
  else
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s"}' "$id" "$method")
  fi
  curl -s -m 30 -X POST "http://127.0.0.1:$port/" -H 'Content-Type: application/json' -d "$body"
}
op() { # op opId json-params
  local id="$1" params="${2:-}"
  if [ -n "$params" ]; then brp "$PORT" jackdaw/call_operator "{\"id\":\"$id\",\"params\":$params}"
  else brp "$PORT" jackdaw/call_operator "{\"id\":\"$id\"}"; fi
}
wait_idle() { # wait_idle timeoutSec
  local deadline=$((SECONDS + ${1:-600}))
  while [ $SECONDS -lt $deadline ]; do
    if brp "$PORT" jackdaw/wait '{"until":"idle"}' | jq -e '.result.idle == true' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  log "wait(idle) timeout (continuing)"
  return 1
}
ent() { echo "$1" | jq -r '.result.entities[0] // .result.entity // .result.result.entity // empty' 2>/dev/null; }
game_pid() { pgrep -f 'target/debug/t11t1-game' | head -1; }
editor_pid() { pgrep -x jackdaw | head -1; }
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

# --- clean boot -------------------------------------------------------------
pkill -x jackdaw 2>/dev/null; pkill -f 't11t1-game' 2>/dev/null
sleep 1
export JACKDAW_OPEN_PROJECT="$PROJECT"
export JACKDAW_REMOTE_PORT="$PORT"
export JACKDAW_WINDOW_SIZE=1600x900
export DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB"
# NOTE: deliberately no RUST_BACKTRACE on this machine (see header).
cd "$REPO"
nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$EDITOR_LOG" 2>&1 &
ready=""
for i in $(seq 1 150); do
  sleep 2
  if brp "$PORT" jackdaw/status '{}' >/dev/null 2>&1; then ready=1; break; fi
  if ! editor_pid >/dev/null; then log "EDITOR_BOOT_FAIL"; exit 1; fi
done
[ -n "$ready" ] || { log "EDITOR_BOOT_FAIL (timeout)"; exit 1; }
wait_idle 600; sleep 5
dismiss_dialog
# ProjectTypes need the watcher to pick the schema up (T2 finding). The
# fixture's game run generated .jackdaw/components.json; stamp schema.json
# if present to trigger the load.
if [ -f "$PROJECT/.jackdaw/schema.json" ]; then
  touch "$PROJECT/.jackdaw/schema.json"
  sleep 6
fi
log "EDITOR_READY"

read_yaw() { # CameraLook yaw of the first rig: editor projection first, game world as fallback
  local v
  v=$(brp "$PORT" jackdaw/scene_snapshot '{}' | jq -r '[.result[] | select(.components["jackdaw_camera_rig::CameraLook"]) | .components["jackdaw_camera_rig::CameraLook"].yaw][0] // empty' 2>/dev/null)
  if [ -z "$v" ]; then
    v=$(brp "$GAME_PORT" jackdaw/scene_snapshot '{}' | jq -r '[.result[] | select(.components["jackdaw_camera_rig::CameraLook"]) | .components["jackdaw_camera_rig::CameraLook"].yaw][0] // empty' 2>/dev/null)
  fi
  echo "$v"
}

# --- PIE probe: the environment question every PIE cell asks first ----------
so=$(op scene.open "{\"path\":\"$PROJECT/assets/scene.bsn\"}")
sleep 2
log "PIE_PROBE scene.open: $(echo "$so" | jq -c . 2>/dev/null | head -c 200)"
pie_alive=false
probe_crashes=0
for attempt in 1 2 3; do
  op pie.play_current >/dev/null 2>&1
  sleep 20
  alive=$(game_pid)
  exited=$(grep -c "exited before connecting" "$EDITOR_LOG" 2>/dev/null || true)
  log "PIE_PROBE #$attempt: procAlive=${alive:+yes} exitedMark=$exited"
  [ "$exited" -gt 0 ] 2>/dev/null && probe_crashes=$((probe_crashes + 1))
  if [ -n "$alive" ]; then
    stp=$(brp "$PORT" jackdaw/status '{}' 2>/dev/null | jq -r '.result.pie // empty' 2>/dev/null)
    case "$stp" in *running*) pie_alive=true; break ;; esac
  fi
  dismiss_dialog
  stop_pie
  sleep 2
done
if $pie_alive; then
  log "PIE_PROBE: RECOVERED -- PIE cells run real this round"
else
  log "PIE_PROBE: DEAD ($probe_crashes/3 attempts exited before connecting) -- PIE cells degrade per T10 precedent"
fi
leg PIE_PROBE_ALIVE $pie_alive

# ---------------------------------------------------------------------------
# PIE-alive path: the deferred real-machine cells. Each block re-plays the
# scene it needs and stops afterwards.
# ---------------------------------------------------------------------------
if $pie_alive; then
  stop_pie
  dismiss_dialog
  wait_idle 120

  # === C7 Look real injection: input.motion -> CameraLook yaw ==========
  # Template scene (rig default sensitivity 0.005). Capture on, inject
  # dx=+200 over 20 steps -> yaw must fall by 200*0.005 = 1.0 rad
  # (T09 grid-4 re-pinned semantics; window +-0.15 rad).
  op scene.open "{\"path\":\"$PROJECT/assets/scene.bsn\"}" >/dev/null 2>&1
  sleep 2
  op pie.play_current >/dev/null 2>&1
  sleep 10
  op pie.play_input_toggle >/dev/null 2>&1   # capture on
  sleep 2
  yaw0=$(read_yaw)
  op input.motion '{"dx":200,"dy":0,"steps":20}' >/dev/null 2>&1
  sleep 2
  yaw1=$(read_yaw)
  c7_open=false; c7_open_delta=999
  if [ -n "$yaw0" ] && [ -n "$yaw1" ]; then
    c7_open_delta=$(python3 -c "print($yaw1 - $yaw0)")
    ok=$(python3 -c "print(1 if abs(($yaw1 - $yaw0) - (-1.0)) < 0.15 else 0)")
    [ "$ok" = 1 ] && c7_open=true
  fi
  log "C7 open-channel: yaw0=$yaw0 yaw1=$yaw1 delta=$c7_open_delta (expect -1.0 = -dx*0.005)"
  leg C7_LOOK_OPEN_CHANNEL "$c7_open"

  # RMB-held frames: the bridge yields (decision 3-3), and with no real
  # mouse motion reaching the game the crate channel writes nothing, so
  # the same injection must NOT move the yaw (|delta| < 0.05 rad).
  # RMB is held by writing the PIE game's own ButtonInput<MouseButton>
  # over its BRP port (fixture registers the keyboard resource; the mouse
  # one is registered stock - verified by world.get_resources).
  mb_ok=$(brp "$GAME_PORT" world.get_resources "{\"resource\":\"$MB_RES\"}" | jq -r '.result.value // .error // empty' 2>/dev/null | head -c 60)
  log "C7 mouse resource probe: ${mb_ok:0:60}"
  yaw2=""
  if echo "$mb_ok" | grep -q pressed; then
    brp "$GAME_PORT" world.insert_resources "{\"resource\":\"$MB_RES\",\"value\":{\"pressed\":[\"Right\"],\"just_pressed\":[\"Right\"],\"just_released\":[]}}" >/dev/null 2>&1
    sleep 1
    yaw2=$(read_yaw)
    op input.motion '{"dx":200,"dy":0,"steps":20}' >/dev/null 2>&1
    sleep 2
    yaw3=$(read_yaw)
    brp "$GAME_PORT" world.insert_resources "{\"resource\":\"$MB_RES\",\"value\":{\"pressed\":[],\"just_pressed\":[],\"just_released\":[]}}" >/dev/null 2>&1
  fi
  c7_rmb=SKIP; c7_rmb_delta=999
  if [ -n "$yaw2" ] && [ -n "$yaw3" ]; then
    c7_rmb_delta=$(python3 -c "print($yaw3 - $yaw2)")
    ok=$(python3 -c "print(1 if abs($yaw3 - $yaw2) < 0.05 else 0)")
    [ "$ok" = 1 ] && c7_rmb=true || c7_rmb=false
  fi
  log "C7 rmb-held: yaw2=$yaw2 yaw3=$yaw3 delta=$c7_rmb_delta (expect ~0, bridge yields)"
  leg C7_LOOK_RMB_YIELD "$c7_rmb"
  op pie.play_input_toggle >/dev/null 2>&1   # capture off
  stop_pie
  dismiss_dialog
  wait_idle 120
  sleep 2

  # === N13 x10: drain_game_events swap_remove recurrence ================
  # PIE connected ~6s each round (the T10b signature hit at ~1.9s after
  # connected). drain_game_events is an EDITOR-side system: a recurrence
  # kills the editor, so each round checks editor liveness + log tail.
  # No RUST_BACKTRACE on this machine (header): the panic message itself
  # carries the swap_remove signature.
  n13_hits=0; n13_rounds=0
  op scene.open "{\"path\":\"$PROJECT/assets/scene.bsn\"}" >/dev/null 2>&1
  sleep 2
  for round in $(seq 1 10); do
    if [ -z "$(editor_pid)" ]; then
      log "N13 #$round: editor dead before round, rebooting"
      cd "$REPO"; nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw >> "$EDITOR_LOG" 2>&1 &
      for i in $(seq 1 90); do sleep 2; brp "$PORT" jackdaw/status '{}' >/dev/null 2>&1 && break; done
      wait_idle 300; sleep 3
      so=$(op scene.open "{\"path\":\"$PROJECT/assets/scene.bsn\"}"); sleep 2
    fi
    n13_rounds=$((n13_rounds + 1))
    op pie.play_current >/dev/null 2>&1
    connected=""
    for i in $(seq 1 40); do
      sleep 1
      if brp "$GAME_PORT" jackdaw/app_info '{}' 2>/dev/null | jq -e '.result.app_name' >/dev/null 2>&1; then connected=1; break; fi
    done
    sleep 6
    sig=$(grep -c "swap_remove index" "$EDITOR_LOG" 2>/dev/null || true)
    alive=$(editor_pid)
    log "N13 #$round: connected=${connected:+yes} editorAlive=${alive:+yes} swap_remove_hits_in_log=$sig"
    if [ "${sig:-0}" -gt 0 ] 2>/dev/null; then n13_hits=$sig; fi
    if [ -z "$alive" ]; then n13_hits=$((n13_hits + 1)); fi
    stop_pie 2>/dev/null
    dismiss_dialog 2>/dev/null
    sleep 2
  done
  log "N13_X10: rounds=$n13_rounds recurrences=$n13_hits (T10b: 1 hit / 1 clean on the old machine)"
  leg N13_X10_RECURRENT "$( [ "$n13_hits" = 0 ] && echo true || echo false )"   # count recorded in log line; PASS when 0 recurrences
  stop_pie; dismiss_dialog; wait_idle 120
fi

# --- M2: the placement chain exactly as the fixed doc teaches it -------------
op scene.new >/dev/null 2>&1
sleep 2
r=$(op entity.add.cube '{}')
player=$(ent "$r")
if [ -z "$player" ]; then
  log "ENTITY_ADD_FAIL: $r"
  pkill -x jackdaw; exit 1
fi
op component.set "{\"entity\":\"$player\",\"type_path\":\"$TKEY\",\"field\":\"translation\",\"value\":\"[2.0, 1.0, 2.0]\"}" >/dev/null

# The five components, by fully-qualified name -- PlayerVelocity included
# (the C10 fix).
five_ok=true
for tp in 't11t1_game::PlayerMarker' 't11t1_game::PlayerController' 't11t1_game::PlayerVelocity'; do
  a=$(op component.add "{\"entity\":\"$player\",\"type_path\":\"$tp\"}")
  st=$(echo "$a" | jq -r '.result.result // empty' 2>/dev/null)
  [ "$st" = finished ] || { five_ok=false; log "  add $tp -> $st"; }
done
a=$(op component.add "{\"entity\":\"$player\",\"type_path\":\"avian3d::dynamics::rigid_body::RigidBody\"}")
st=$(echo "$a" | jq -r '.result.result // empty' 2>/dev/null); [ "$st" = finished ] || { five_ok=false; log "  add RigidBody -> $st"; }
op component.set "{\"entity\":\"$player\",\"type_path\":\"avian3d::dynamics::rigid_body::RigidBody\",\"field\":\"\",\"value\":\"\\\"Kinematic\\\"\"}" >/dev/null
a=$(op component.add "{\"entity\":\"$player\",\"type_path\":\"jackdaw_avian_integration::AvianCollider\"}")
st=$(echo "$a" | jq -r '.result.result // empty' 2>/dev/null); [ "$st" = finished ] || { five_ok=false; log "  add AvianCollider -> $st"; }
op component.set "{\"entity\":\"$player\",\"type_path\":\"jackdaw_avian_integration::AvianCollider\",\"field\":\"\",\"value\":\"{\\\"Capsule\\\":{\\\"radius\\\":0.35,\\\"height\\\":1.0}}\"}" >/dev/null
log "M2_ADD five components via operators: $five_ok"

# N14 live: the FIRST single-field set after add; the saved block must
# spell jump_speed too (merged from the schema default).
op component.set "{\"entity\":\"$player\",\"type_path\":\"t11t1_game::PlayerController\",\"field\":\"move_speed\",\"value\":\"2.0\"}" >/dev/null

rr=$(op entity.add.camera_rig '{}')
rig=$(ent "$rr")
[ -z "$rig" ] && log "RIG_ADD_FAIL: $rr"
op component.set "{\"entity\":\"$rig\",\"type_path\":\"jackdaw_camera_rig::CameraRig\",\"field\":\"distance\",\"value\":\"5.0\"}" >/dev/null
op entity.reparent "{\"child\":\"$rig\",\"parent\":\"$player\"}" >/dev/null
# The placed rig needs its own activation marker (two rigs in the world).
op component.add "{\"entity\":\"$rig\",\"type_path\":\"jackdaw_camera_rig::ActiveCameraRig\"}" >/dev/null

rf=$(op entity.add.cube '{}')
floor=$(ent "$rf")
[ -z "$floor" ] && log "FLOOR_ADD_FAIL: $rf"
op component.set "{\"entity\":\"$floor\",\"type_path\":\"$TKEY\",\"field\":\"scale\",\"value\":\"[12.0, 1.0, 12.0]\"}" >/dev/null
op component.set "{\"entity\":\"$floor\",\"type_path\":\"$TKEY\",\"field\":\"translation\",\"value\":\"[0.0, -0.5, 0.0]\"}" >/dev/null
op physics.enable "{\"entity\":\"$floor\"}" >/dev/null

rw=$(op entity.add.cube '{}')
wall=$(ent "$rw")
[ -z "$wall" ] && log "WALL_ADD_FAIL: $rw"
op component.set "{\"entity\":\"$wall\",\"type_path\":\"$TKEY\",\"field\":\"scale\",\"value\":\"[12.0, 1.5, 0.4]\"}" >/dev/null
op component.set "{\"entity\":\"$wall\",\"type_path\":\"$TKEY\",\"field\":\"translation\",\"value\":\"[0.0, 0.75, -3.0]\"}" >/dev/null
op physics.enable "{\"entity\":\"$wall\"}" >/dev/null

SCENE_MAIN="$PROJECT/assets/t11t3-place.bsn"
sv=$(op scene.save "{\"path\":\"$SCENE_MAIN\"}")
wait_idle 60
hasMs=false; hasJs=false; hasDist=false; hasVel=false; hasKin=false; hasAct=false
if [ -f "$SCENE_MAIN" ]; then
  grep -q 'move_speed: *2\.0' "$SCENE_MAIN" && hasMs=true
  grep -q 'jump_speed: *4\.5' "$SCENE_MAIN" && hasJs=true
  grep -q 'distance: *5\.0' "$SCENE_MAIN" && hasDist=true
  grep -q 'PlayerVelocity' "$SCENE_MAIN" && hasVel=true
  grep -q 'Kinematic' "$SCENE_MAIN" && hasKin=true
  grep -q 'ActiveCameraRig' "$SCENE_MAIN" && hasAct=true
fi
log "N14_LIVE first-set-after-add: move_speed 2.0 on disk=$hasMs; sibling jump_speed 4.5 on disk=$hasJs"
leg N14_LIVE_SIBLING_ON_DISK "$([ "$hasMs" = true ] && [ "$hasJs" = true ] && echo true || echo false)"
svok=$(echo "$sv" | jq -r '.result.result // empty' 2>/dev/null)
leg M2_BUILD "$([ "$five_ok" = true ] && [ "$hasVel" = true ] && [ "$hasKin" = true ] && [ "$hasAct" = true ] && [ "$hasDist" = true ] && [ "$svok" = finished ] && echo true || echo false)"

# M8 second-set control + M9 (sensitivity and eye_height authored legs).
op component.set "{\"entity\":\"$player\",\"type_path\":\"t11t1_game::PlayerController\",\"field\":\"jump_speed\",\"value\":\"6.0\"}" >/dev/null
op component.set "{\"entity\":\"$rig\",\"type_path\":\"jackdaw_camera_rig::CameraRig\",\"field\":\"sensitivity\",\"value\":\"0.008\"}" >/dev/null
op scene.save "{\"path\":\"$SCENE_MAIN\"}" >/dev/null
wait_idle 60
m8=false
if [ -f "$SCENE_MAIN" ]; then
  grep -q 'move_speed: *2\.0' "$SCENE_MAIN" && grep -q 'jump_speed: *6\.0' "$SCENE_MAIN" && grep -q 'sensitivity: *0\.008' "$SCENE_MAIN" && m8=true
fi
leg M8_SECOND_SET "$m8"

# --- M7-pre + M9: FirstPerson variant with authored eye_height ---------------
op component.set "{\"entity\":\"$rig\",\"type_path\":\"jackdaw_camera_rig::CameraRig\",\"field\":\"mode\",\"value\":\"\\\"FirstPerson\\\"\"}" >/dev/null
op component.set "{\"entity\":\"$rig\",\"type_path\":\"jackdaw_camera_rig::CameraRig\",\"field\":\"eye_height\",\"value\":\"1.3\"}" >/dev/null
SCENE_FP="$PROJECT/assets/t11t3-fp.bsn"
op scene.save "{\"path\":\"$SCENE_FP\"}" >/dev/null
wait_idle 60
fpok=false
if [ -f "$SCENE_FP" ]; then
  grep -q 'FirstPerson' "$SCENE_FP" && grep -q 'eye_height: *1\.2999' "$SCENE_FP" && fpok=true  # f32 serializes 1.3 as 1.2999999523162842
fi
log "M7PRE_FP(+M9 eye_height=1.3) saved: $fpok"
leg M7PRE_FP_EYEHEIGHT "$fpok"

# --- M6-pre: high-speed variant scene ----------------------------------------
op component.set "{\"entity\":\"$player\",\"type_path\":\"t11t1_game::PlayerController\",\"field\":\"move_speed\",\"value\":\"8.0\"}" >/dev/null
SCENE_FAST="$PROJECT/assets/t11t3-fast.bsn"
op scene.save "{\"path\":\"$SCENE_FAST\"}" >/dev/null
wait_idle 60
fastok=false
[ -f "$SCENE_FAST" ] && grep -q 'move_speed: *8\.0' "$SCENE_FAST" && fastok=true
log "M6PRE_FAST move_speed=8 saved: $fastok"
leg M6PRE_FAST "$fastok"

# --- cell 11 Stop iron proof (PIE alive path only) ---------------------------
if $pie_alive; then
  SHA_BEFORE=$(shasum -a 256 "$SCENE_MAIN" | cut -d' ' -f1)
  op scene.open "{\"path\":\"$SCENE_MAIN\"}" >/dev/null 2>&1
  sleep 2
  op pie.play_current >/dev/null 2>&1
  # player running (held W over the game's own BRP) while the camera drives
  for i in $(seq 1 10); do
    brp "$GAME_PORT" world.insert_resources "{\"resource\":\"$KC_RES\",\"value\":{\"pressed\":[\"KeyW\"],\"just_pressed\":[\"KeyW\"],\"just_released\":[]}}" >/dev/null 2>&1
    sleep 0.25
  done
  moved=$(brp "$GAME_PORT" jackdaw/scene_snapshot '{}' | jq -r '[.result[] | select(.components | tostring | contains("PickupCount") | not) | select(.components | tostring | contains("PlayerMarker"))][0].components["bevy_transform::components::transform::Transform"].translation[2] // empty' 2>/dev/null)
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
else
  leg CELL11_STOP_IRON DEGRADED
fi

# --- teardown -----------------------------------------------------------------
pkill -x jackdaw 2>/dev/null; pkill -f 't11t1-game' 2>/dev/null
printf '%s\n' "$(summary_line)" > "$SUMMARY"
log "VERDICT_A_MAC: $(summary_line)"
log "T11T3_A_MAC_DONE"
