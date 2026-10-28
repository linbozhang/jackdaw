#!/bin/bash
# T11-T3 acceptance matrix, direct-run leg (macOS port of t11t3-matrix-c.ps1).
# Same four rounds and the same assertion windows as the Windows original.
# Mac divergences (recorded in the T11-T3 report):
#   - No PostMessage on macOS: keys are injected by writing the game's own
#     ButtonInput<KeyCode> resource over its BRP port (world.insert_resources;
#     the fixture registers that resource - warm-project instrumentation,
#     same status as JackdawRemotePlugin). Held keys persist in `pressed`
#     across frames; just_pressed decays each frame, so taps repeat the
#     write a few times to cross the input-clear window.
#   - No RUST_BACKTRACE=1 (debug wgpu LockTrace -> libunwind SIGSEGV).
#   - Game boot: nohup, no focus chase needed at all.
# Rounds:
#   1 t11t3-place.bsn (operator-placed player, authored 2.0/6.0/5.0/0.008):
#     C1 settle, C2 wall stop, C5 follow, C3 jump apex, C4 slide, C6 half-speed.
#   2 template scene.bsn (out-of-box, cell 1) + FallingCube push (cell 6).
#   3 t11t3-fast.bsn (move_speed 8): no-penetration wall stop.
#   4 t11t3-fp.bsn (FirstPerson + authored eye_height 1.3): M9 behavior leg.
# Usage: bash loop/qa/t11t3-matrix-c.sh [project] [gamePort]
set -u
PROJECT="${1:-/Users/zhanglinbo/workspace/loop-mac/t11t1-game}"
GAME_PORT="${2:-15702}"
REPO=/Users/zhanglinbo/workspace/jackdaw
OUTDIR="$REPO/loop/t11t3-live"
PROGRESS_LOG="$OUTDIR/t11t3-c-mac-progress.log"
SUMMARY="$OUTDIR/t11t3-c-mac-summary.txt"
GAME_LOG="$OUTDIR/t11t3-c-mac-game.log"
mkdir -p "$OUTDIR"
: > "$PROGRESS_LOG"
EXE="$PROJECT/target/debug/t11t1-game"
[ -x "$EXE" ] || { echo "EXE_MISSING: $EXE"; exit 1; }
GAME_ASSETS="$PROJECT/target/debug/assets"
mkdir -p "$GAME_ASSETS"
SCENE="$GAME_ASSETS/scene.bsn"
KC_RES='bevy_input::button_input::ButtonInput<bevy_input::keyboard::KeyCode>'
TKEY='bevy_transform::components::transform::Transform'

RESULTS_FILE="$(mktemp /tmp/t11t3-results.XXXXXX)"
touch "$RESULTS_FILE"
log() { echo "$@" | tee -a "$PROGRESS_LOG"; }
leg() {
  case "$2" in
    true|0) r=PASS ;;
    *) r=FAIL ;;
  esac
  echo "$1=$r" >> "$RESULTS_FILE"
  log "${1}_${r}"
}
summary_line() { sort "$RESULTS_FILE" | tr '\n' ' '; }
gbrp() { # gbrp method json-params
  local method="$1" params="${2:-}" id=$RANDOM body
  if [ -n "$params" ]; then body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params")
  else body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s"}' "$id" "$method"); fi
  curl -s -m 30 -X POST "http://127.0.0.1:$GAME_PORT/" -H 'Content-Type: application/json' -d "$body"
}
snap_raw() { gbrp jackdaw/scene_snapshot '{}'; }
get_t() { echo "$1" | jq -r --arg t "$TKEY" '.components[$t].translation // empty' 2>/dev/null; }
has_comp() { echo "$1" | jq -e --arg t "$2" '.components | keys[] | endswith($t)' >/dev/null 2>&1; }

# --- key injection: native KeyboardInput events via world.write_message ------
# Resource writes (ButtonInput) work for HELD keys, but just_pressed never
# survives to the evaluator: BRP writes land in RemoteLast, and the next
# frame's button-input clear wipes just_pressed before GameActions reads it
# (probed live). Real messages go through the game's own keyboard system,
# exactly like a native key - so taps and holds both use events.
KB_MSG='bevy_input::keyboard::KeyboardInput'
WINDOW_ENTITY=""
keyev() { # keyev KeyCode state
  gbrp world.write_message "{\"message\":\"$KB_MSG\",\"value\":{\"key_code\":\"$1\",\"logical_key\":{\"Character\":\" \"},\"state\":\"$2\",\"text\":null,\"repeat\":false,\"window\":\"$WINDOW_ENTITY\"}}" >/dev/null 2>&1
}
down() { keyev "$1" Pressed; }
up() { keyev "$1" Released; }
tap() { # tap KeyCode -- press message, cross a few frames, release message
  down "$1"
  sleep 0.12
  up "$1"
}

find_player() { # find_player placed(0|1) -> prints "x y z"
  local placed="$1" want_x want_z
  [ "$placed" = 1 ] && { want_x=2.0; want_z=2.0; } || { want_x=-2.0; want_z=0.0; }
  snap_raw | jq -r --arg t "$TKEY" --argjson px "$want_x" --argjson pz "$want_z" --argjson placed "$placed" '
    [.result[]
     | select(any(.components | keys[]; endswith("PlayerMarker")))
     | select((if $placed == 1 then (any(.components | keys[]; endswith("PickupCount")) | not) else (any(.components | keys[]; endswith("PickupCount"))) end))
     | (.components[$t].translation) as $tr
     | select($tr != null)
     | {d: (($tr[0] - $px | if . < 0 then -. else . end) + ($tr[2] - $pz | if . < 0 then -. else . end)), tr: $tr}]
    | sort_by(.d) | .[0]
    | if . and (.d < 14.0) then "\(.tr[0]) \(.tr[1]) \(.tr[2])" else empty end' 2>/dev/null
}
py() { python3 "$@"; }
rig_local() { # rig_local placed(0|1) -> "x y z" of the rig nearest that player
  local placed="$1" p r
  p=$(find_player "$placed")
  [ -z "$p" ] && return 1
  r=$(snap_raw | jq -r --arg t "$TKEY" '
    .result[]
    | select(any(.components | keys[]; endswith("CameraRig")))
    | .components[$t].translation
    | select(. != null)
    | "\(.[0]) \(.[1]) \(.[2])"' 2>/dev/null)
  [ -z "$r" ] && return 1
  python3 -c "
px, py_, pz = map(float, '''$p'''.split())
best = None; bestd = 1e30
for line in '''$r'''.strip().splitlines():
    x, y, z = map(float, line.split())
    d = abs(x - px) + abs(z - pz)
    if d < bestd: bestd = d; best = (x, y, z)
if best and bestd < 22.0:
    print(best[0], best[1], best[2])"
}
game_alive() { pgrep -f 't11t1-game$' >/dev/null; }
stop_game() { pkill -f 't11t1-game$' 2>/dev/null; sleep 2.5; }
boot_game() { # boot_game <scene-file or "">
  stop_game
  [ -n "${1:-}" ] && [ -f "$1" ] && cp "$1" "$SCENE"
  (cd "$PROJECT" && nohup "$EXE" >> "$GAME_LOG" 2>&1 &)
  for i in $(seq 1 120); do
    sleep 0.25
    if snap_raw | jq -e '.result' >/dev/null 2>&1; then break; fi
    game_alive || { log "GAME_BOOT_FAIL"; return 1; }
  done
  sleep 3
  game_alive || { log "GAME_GONE_EARLY"; return 1; }
  # The window entity KeyboardInput messages must name.
  WINDOW_ENTITY=$(gbrp world.query '{"data":{"components":["bevy_window::window::Window"]}}' | jq -r '.result[0].entity // empty' 2>/dev/null)
  log "boot: window entity = ${WINDOW_ENTITY:-MISSING}"
  [ -n "$WINDOW_ENTITY" ] || return 1
  return 0
}

# =============== Round 1: the placed scene, authored tuning =====================
if ! boot_game "$PROJECT/assets/t11t3-place.bsn"; then exit 1; fi
sleep 2
R1P=$(find_player 1); R1T=$(find_player 0)
placed_ok=false; tpl_ok=false; rig_mat=false; rig_act=false
[ -n "$R1P" ] && placed_ok=true
[ -n "$R1T" ] && tpl_ok=true
snap_raw | jq -e '[.result[] | select(any(.components | keys[]; endswith("CameraRig"))) | select(any(.components | keys[]; endswith("Projection")))] | length > 0' >/dev/null 2>&1 && rig_mat=true
snap_raw | jq -e '[.result[] | select(any(.components | keys[]; endswith("CameraRig"))) | select(any(.components | keys[]; endswith("ActiveCameraRig")))] | length > 0' >/dev/null 2>&1 && rig_act=true
pyBase=$(echo "$R1P" | awk '{print $2}')
log "R1C1 placed y=$pyBase tplPlayer=$tpl_ok placedRig materialized=$rig_mat active=$rig_act"
r1c1=false
[ "$placed_ok" = true ] && [ "$tpl_ok" = true ] && [ "$rig_mat" = true ] && [ "$rig_act" = true ] \
  && py -c "import sys; sys.exit(0 if $pyBase > 0.7 and $pyBase < 1.05 else 1)" && r1c1=true
leg R1_C1_SETTLE "$r1c1"

# walk to the wall
sleep 1
down KeyW
zEnd=""; n=0
for i in $(seq 1 30); do
  sleep 0.12
  z=$(find_player 1 | awk '{print $3}')
  if [ -n "$z" ]; then zEnd="$z"; n=$((n + 1)); fi
  if [ "$i" -gt 10 ] && [ -n "$zEnd" ]; then
    zPrev=$(find_player 1 | awk '{print $3}')
    if py -c "import sys; sys.exit(0 if abs($zEnd - $zPrev) < 0.005 and $zEnd < -2.2 else 1)" 2>/dev/null; then break; fi
  fi
done
up KeyW
log "R1C2 walk zEnd=$zEnd (samples $n)"
r1c2=false
[ "${n:-0}" -ge 4 ] && py -c "import sys; sys.exit(0 if -2.60 < $zEnd < -2.0 else 1)" && r1c2=true
leg R1_C2_WALLSTOP "$r1c2"

# follow at the authored distance 5 across a turn
oa=$(rig_local 1)
down KeyD; sleep 1.5; up KeyD; sleep 0.4
ob=$(rig_local 1)
drift=9.9
if [ -n "$oa" ] && [ -n "$ob" ]; then
  read_line=$(py -c "
a=[$(echo $oa | tr ' ' ',')]; b=[$(echo $ob | tr ' ' ',')]
na=sum(x*x for x in a)**0.5; nb=sum(x*x for x in b)**0.5
print(f'{a[0]:.2f},{a[1]:.2f},{a[2]:.2f} {na:.3f} {b[0]:.2f},{b[1]:.2f},{b[2]:.2f} {nb:.3f} {abs(na-nb):.3f}')")
  drift=$(echo "$read_line" | awk '{print $NF}')
  log "R1C5 local=$read_line (distance-5 expectation (0,3.15,4.61), |.|~5.578)"
fi
r1c5=false
[ -n "$oa" ] && py -c "
import sys
d=float('$drift'); y=float('$(echo $oa | awk '{print $2}')'); z=float('$(echo $oa | awk '{print $3}')')
sys.exit(0 if d < 0.15 and abs(y - 3.147) < 0.3 and abs(z - 4.605) < 0.4 else 1)" && r1c5=true
leg R1_C5_FOLLOW "$r1c5"

# jump at the authored jump_speed 6.0: apex = rest + 36/19.62
yBase=$(find_player 1 | awk '{print $2}')
tap Space
apex=$yBase
for i in $(seq 1 40); do
  sleep 0.06
  y=$(find_player 1 | awk '{print $2}')
  [ -n "$y" ] && py -c "import sys; sys.exit(0 if $y > $apex else 1)" 2>/dev/null && apex=$y
done
log "R1C3 jump apex=$apex expected~$(py -c 'print(0.86 + 36.0/19.62)') (jump_speed 6.0 authored)"
r1c3=false
py -c "import sys; sys.exit(0 if abs($apex - (0.86 + 36.0/19.62)) < 0.35 else 1)" && r1c3=true
leg R1_C3_JUMP "$r1c3"

# slide: back west, then W+D along the wall
down KeyA; sleep 1.3; up KeyA; sleep 0.3
x0=$(find_player 1 | awk '{print $1}')
down KeyW; down KeyD
for i in $(seq 1 8); do sleep 0.12; snap_raw >/dev/null 2>&1; done
up KeyW; up KeyD
sleep 0.3
x1=$(find_player 1 | awk '{print $1}'); zSlide=$(find_player 1 | awk '{print $3}')
log "R1C4 slide x $x0 -> $x1, z=$zSlide"
r1c4=false
py -c "import sys; sys.exit(0 if ($x1 - $x0) > 0.8 and -2.70 < $zSlide < -2.15 else 1)" && r1c4=true
leg R1_C4_SLIDE "$r1c4"

# half-speed: placed 2.0 vs template 4.0 in one window
down KeyA; sleep 1.6; up KeyA; sleep 0.4
aP=$(find_player 1); aT=$(find_player 0)
t0=$(python3 -c 'import time; print(time.time())')
down KeyD; sleep 1.4; up KeyD; sleep 0.25
bP=$(find_player 1); bT=$(find_player 0)
dt=$(python3 -c "import time; print(time.time() - $t0)")
vPl=NA; vTp=NA
if [ -n "$aP" ] && [ -n "$bP" ]; then
  vPl=$(py -c "
a=[$(echo $aP | tr ' ' ',')]; b=[$(echo $bP | tr ' ' ',')]
print((((a[0]-b[0])**2 + (a[2]-b[2])**2)**0.5)/$dt)")
fi
if [ -n "$aT" ] && [ -n "$bT" ]; then
  vTp=$(py -c "
a=[$(echo $aT | tr ' ' ',')]; b=[$(echo $bT | tr ' ' ',')]
print((((a[0]-b[0])**2 + (a[2]-b[2])**2)**0.5)/$dt)")
fi
log "R1C6 placed=$vPl m/s (authored 2.0) template=$vTp m/s (4.0)"
r1c6=false
py -c "import sys; sys.exit(0 if $vPl > 1.2 and $vPl < 2.8 and $vTp > 2.8 else 1)" && r1c6=true
leg R1_C6_HALFSPEED "$r1c6"
stop_game

# =============== Round 2: template scene, out-of-box chain (cell 1) ============
if ! boot_game "$PROJECT/assets/scene.bsn"; then exit 1; fi
sleep 3
s2=$(snap_raw)
tplVis=$(echo "$s2" | jq -r '[.result[] | select(any(.components | keys[]; endswith("PlayerMarker"))) | select(any(.components | keys[]; endswith("Mesh3d")))] | length > 0' 2>/dev/null)
z0=$(find_player 0 | awk '{print $3}')
down KeyW; sleep 0.9; up KeyW; sleep 0.3
z1=$(find_player 0 | awk '{print $3}')
y0=$(find_player 0 | awk '{print $2}')
tap Space
apex2=$y0
for i in $(seq 1 30); do
  sleep 0.06
  y=$(find_player 0 | awk '{print $2}')
  [ -n "$y" ] && py -c "import sys; sys.exit(0 if $y > $apex2 else 1)" 2>/dev/null && apex2=$y
done
fa=$(rig_local 0)
down KeyD; sleep 0.7; up KeyD; sleep 0.3
fb=$(rig_local 0)
fDrift=9.9
if [ -n "$fa" ] && [ -n "$fb" ]; then
  fDrift=$(py -c "
a=[$(echo $fa | tr ' ' ',')]; b=[$(echo $fb | tr ' ' ',')]
print(abs(sum(x*x for x in a)**0.5 - sum(x*x for x in b)**0.5))")
fi
# FallingCube push (cell 6 kinematic->dynamic): settle point near (0, ., 0);
# walk the template player east into it and see whether the cube moves.
cube0=$(echo "$s2" | jq -r --arg t "$TKEY" '[.result[] | select(any(.components | keys[]; endswith("FallingCube"))) | .components[$t].translation] | first | if . then "\(.[0]) \(.[1]) \(.[2])" else empty end')
cubeDx=0.0; pushed=false
if [ -n "$cube0" ]; then
  cx0=$(echo "$cube0" | awk '{print $1}')
  down KeyD; sleep 2.6; up KeyD; sleep 0.4
  cube1=$(snap_raw | jq -r --arg t "$TKEY" '[.result[] | select(any(.components | keys[]; endswith("FallingCube"))) | .components[$t].translation] | first | if . then "\(.[0]) \(.[1]) \(.[2])" else empty end')
  if [ -n "$cube1" ]; then
    cx1=$(echo "$cube1" | awk '{print $1}')
    cubeDx=$(py -c "print(abs($cx1 - $cx0))")
    py -c "import sys; sys.exit(0 if $cubeDx > 0.3 else 1)" 2>/dev/null && pushed=true
  fi
fi
log "R2 tpl visible=$tplVis walk dz=$(py -c "print($z0 - $z1)") jumpApex=$apex2 followDrift=$fDrift cubePushed=$pushed (dx=$cubeDx)"
r2c1=false
[ "$tplVis" = true ] && py -c "import sys; sys.exit(0 if ($z0 - $z1) > 0.8 and ($apex2 - $y0) > 0.6 and $fDrift < 0.2 else 1)" && r2c1=true
leg R2_CELL1_OUTOFBOX "$r2c1"
leg R2_CELL6_PUSHCUBE "$pushed"
stop_game

# =============== Round 3: high speed into the wall (cell 6) ====================
if ! boot_game "$PROJECT/assets/t11t3-fast.bsn"; then exit 1; fi
sleep 3
down KeyW; sleep 2.5; up KeyW; sleep 0.3
zFast=$(find_player 1 | awk '{print $3}'); zFast=${zFast:-99.0}
log "R3 high-speed wall stop z=$zFast (no-penetration bound: >= -2.45)"
r3=false
py -c "import sys; sys.exit(0 if -2.50 < $zFast < -2.0 else 1)" && r3=true
leg R3_CELL6_NOPENETRATION "$r3"
stop_game

# =============== Round 4: FirstPerson mode + authored eye_height ===============
if ! boot_game "$PROJECT/assets/t11t3-fp.bsn"; then exit 1; fi
sleep 3
fp=$(rig_local 1)
fpLen=-1.0
if [ -n "$fp" ]; then
  fpLen=$(py -c "print(sum(x*x for x in [$(echo $fp | tr ' ' ',')])**0.5)")
fi
log "R4 FP rig local=($fp) |.|=$fpLen (authored eye_height 1.3; Windows default-eye run measured 1.600, TP form is 5.578)"
r4=false
py -c "import sys; sys.exit(0 if 0.9 < $fpLen < 1.75 and abs($fpLen - 1.3) < 0.3 else 1)" && r4=true
leg R4_CELL7_FIRSTPERSON "$r4"
stop_game

rm -f "$SCENE"
printf '%s\n' "$(summary_line)" > "$SUMMARY"
log "VERDICT_C_MAC: $(summary_line)"
log "T11T3_C_MAC_DONE"
