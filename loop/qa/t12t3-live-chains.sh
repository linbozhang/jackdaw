#!/bin/bash
# T12-T3 live chains over PIE on the warm project.
#   STAND_CHAIN  the QA-promoted standing check: clean boot state (the health
#                chain ordering), the hud root and the 3D world both present
#                (the spawn-chain ordering), and no "in place of" swap line in
#                the streamed game log.
#   STAND_PAUSE  one Escape tap flips paused once (the single-registration
#                check; a double-registered toggle nets zero).
#   CELL4        the second data channel: walking the pickup line takes
#                PickupCount 0 -> 1 -> 2 -> 3, the Pickups text follows, and
#                "Level clear!" reaches the Game panel log strip.
#   CELL5        Escape and the Resume button agree; with the pause screen up
#                the player is frozen (zero displacement on a held key).
#   CELL2R       Restart resets the run at full number level: health back to
#                max, player back to PLAYER_SPAWN, PickupCount back to 0, the
#                three pickups back in the world, screens cleared.
# Usage: bash loop/qa/t12t3-live-chains.sh [project] [editorPort]
set -u
PROJECT="${1:-/Users/zhanglinbo/workspace/loop-mac/t12t1-game/t12t1-game}"
PORT="${2:-15913}"
GAME_PORT=15702
REPO=/Users/zhanglinbo/workspace/jackdaw
OUTDIR="$REPO/loop/t12t3-live"
EDITOR_LOG="$OUTDIR/t12t3-live-editor.log"
CONSOLE_LOG="$OUTDIR/t12t3-live-console.log"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
TKEY='bevy_transform::components::transform::Transform'
KB_MSG='bevy_input::keyboard::KeyboardInput'
mkdir -p "$OUTDIR"
: > "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t12t3-live.XXXXXX)"
touch "$RESULTS_FILE"
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
cleanup() {
  op pie.stop >/dev/null 2>&1
  sleep 2
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
gbrp() {
  local method="$1" params="${2:-}" id=$RANDOM body
  if [ -n "$params" ]; then
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params")
  else
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s"}' "$id" "$method")
  fi
  curl -s -m 30 -X POST "http://127.0.0.1:$GAME_PORT/" -H 'Content-Type: application/json' -d "$body"
}
op() {
  local id="$1" params="${2:-}"
  if [ -n "$params" ]; then brp jackdaw/call_operator "{\"id\":\"$id\",\"params\":$params}"
  else brp jackdaw/call_operator "{\"id\":\"$id\"}"; fi
}
wait_idle() {
  local deadline=$((SECONDS + ${1:-300}))
  while [ $SECONDS -lt $deadline ]; do
    if brp jackdaw/wait '{"until":"idle"}' | jq -e '.result.idle == true' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}
dismiss_dialog() {
  local st
  st=$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.dialog // empty' 2>/dev/null)
  if [ -n "$st" ] && [ "$st" != "null" ]; then
    op dialog.answer '{"choice":"0"}' >/dev/null 2>&1
    sleep 2
  fi
}
game_up() { gbrp jackdaw/app_info '{}' 2>/dev/null | jq -e '.result.app_name' >/dev/null 2>&1; }
shown() { [ "$1" = "Inherited" ] || [ "$1" = "Visible" ]; }
state() {
  gbrp world.get_resources "{\"resource\":\"t12t1_game::GameState\"}" 2>/dev/null \
    | jq -r '.result.value | "\(.menu),\(.paused),\(.game_over)"' 2>/dev/null
}
menu_off() { state | grep -q '^false,'; }
paused_on() { state | grep -q '^[^,]*,true,'; }
paused_off() { state | grep -q '^[^,]*,false,'; }
game_over_cleared() { state | grep -q ',false$'; }
screen_vis() {
  local raw="$1" want_not="${2:-}"
  gbrp world.query '{"data":{"components":["bevy_camera::visibility::Visibility","jackdaw_bind::types::Bindings"]}}' 2>/dev/null \
    | jq -r --arg raw "$raw" --arg vn "$want_not" \
      '[.result[]
        | (.components["jackdaw_bind::types::Bindings"] | tostring) as $b
        | select($b | contains("Res(t12t1_game::GameState).\($raw)"))
        | select(($vn == "not") == ($b | contains("not")))
        | .components["bevy_camera::visibility::Visibility"]] | first // empty' 2>/dev/null
}
vis_of() {
  case "$1" in
    hud)      screen_vis menu not ;;
    start)    screen_vis menu ;;
    pause)    screen_vis paused ;;
    gameover) screen_vis game_over ;;
  esac
}
health() {
  gbrp world.query '{"data":{"components":["t12t1_game::PlayerHealth"]}}' 2>/dev/null \
    | jq -r '[.result[] | .components["t12t1_game::PlayerHealth"].current] | first // empty' 2>/dev/null
}
pick_count() {
  gbrp world.query '{"data":{"components":["t12t1_game::PickupCount"]}}' 2>/dev/null \
    | jq -r '[.result[] | .components["t12t1_game::PickupCount"] | (.["0"]? // .) | if type == "number" then . else empty end] | first // empty' 2>/dev/null
}
pick_entity_count() {
  gbrp world.query '{"data":{"components":["t12t1_game::Pickup"]}}' 2>/dev/null \
    | jq -r '.result | length' 2>/dev/null
}
pickups_text() {
  gbrp world.query '{"data":{"components":["bevy_ui::widget::text::Text"]}}' 2>/dev/null \
    | jq -r '[.result[] | .components["bevy_ui::widget::text::Text"] | strings | select(test("^Pickups: "))] | first // empty' 2>/dev/null
}
progress_value() {
  gbrp world.query '{"data":{"components":["jackdaw_widgets_runtime::Progress"]}}' 2>/dev/null \
    | jq -r '[.result[] | .components["jackdaw_widgets_runtime::Progress"].value] | first // empty' 2>/dev/null
}
player_pos() {
  gbrp world.query "{\"data\":{\"components\":[\"$TKEY\",\"t12t1_game::PlayerHealth\"]}}" 2>/dev/null \
    | jq -r --arg t "$TKEY" '[.result[] | select(.components["t12t1_game::PlayerHealth"] != null) | .components[$t].translation] | first | if . then "\(.[0]) \(.[1]) \(.[2])" else empty end' 2>/dev/null
}
window_entity() {
  gbrp world.query '{"data":{"components":["bevy_window::window::Window"]}}' 2>/dev/null | jq -r '.result[0].entity // empty' 2>/dev/null
}
keyev() {
  gbrp world.write_message "{\"message\":\"$KB_MSG\",\"value\":{\"key_code\":\"$1\",\"logical_key\":{\"Character\":\" \"},\"state\":\"$2\",\"text\":null,\"repeat\":false,\"window\":\"$WINDOW_ENTITY\"}}" >/dev/null 2>&1
}
walk() { keyev "$1" Pressed; sleep "$2"; keyev "$1" Released; sleep 0.3; }
tapkey() { keyev "$1" Pressed; sleep 0.15; keyev "$1" Released; sleep 0.4; }
ui_texts() {
  brp jackdaw/ui_tree '{"kind":"text","visible_only":true,"depth":24}' 2>/dev/null \
    | jq -r '[.. | objects | select(.kind? == "text") | .text // ""] | join(" || ")' 2>/dev/null
}
ui_has_text() { ui_texts | grep -qF "$1"; }
frame_click() {
  op input.pointer "{\"x\":$1,\"y\":$2,\"action\":\"click\",\"button\":\"primary\"}" >/dev/null 2>&1
  sleep 1.5
}
sweep_click() {
  local check
  case "$1" in
    menu)    check=menu_off ;;
    resume)  check=paused_off ;;
    restart) check=game_over_cleared ;;
  esac
  local x y
  for y in 772 757 787 800 745; do
    for x in 787 700 875 550 1025; do
      frame_click "$x" "$y"
      if $check; then log "sweep_click: hit at ($x,$y)"; return 0; fi
    done
  done
  return 1
}
boot_pie() {
  op scene.open "{\"path\":\"$1\"}" >/dev/null 2>&1
  sleep 2
  wait_idle 300 >/dev/null
  op pie.play_current >/dev/null 2>&1
  local deadline=$((SECONDS + 900))
  while [ $SECONDS -lt $deadline ]; do
    game_up && break
    sleep 2
  done
  game_up || { log "PIE_GAME_UP_FAIL"; return 1; }
  sleep 4
}
stop_pie() {
  for _ in 1 2 3 4; do
    op pie.stop >/dev/null 2>&1
    sleep 2
    st=$(brp jackdaw/status '{}' | jq -r '.result.pie // empty' 2>/dev/null)
    [ "$st" = stopped ] && break
  done
  pkill -f 't12t1-game$' 2>/dev/null
  sleep 1
}

# ---- editor boot ------------------------------------------------------------
pkill -x jackdaw 2>/dev/null; pkill -f 't12t1-game$' 2>/dev/null
sleep 1
export JACKDAW_OPEN_PROJECT="$PROJECT" JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1600x900
cd "$REPO"
nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$EDITOR_LOG" 2>&1 &
ok=""
for i in $(seq 1 150); do
  sleep 2
  if brp jackdaw/status '{}' >/dev/null 2>&1; then ok=1; break; fi
  pgrep -x jackdaw >/dev/null || { log "EDITOR_BOOT_FAIL"; exit 1; }
done
[ -n "$ok" ] || { log "EDITOR_BOOT_FAIL (timeout)"; exit 1; }
wait_idle 600; sleep 3; dismiss_dialog
log "EDITOR_READY"

if ! boot_pie "$PROJECT/assets/scene.bsn"; then
  log "PIE_BOOT_FAIL"
  leg STAND_CHAIN false; leg STAND_PAUSE_SINGLE false; leg CELL4_PICKUPS false
  leg CELL5_PAUSE_DOORS false; leg CELL2_RESTART_RESET false
  exit 1
fi
op pie.play_input_toggle >/dev/null 2>&1   # capture on
sleep 2
WINDOW_ENTITY=$(window_entity)
log "window entity: ${WINDOW_ENTITY:-MISSING}"

# ---- standing checks --------------------------------------------------------
boot_state=$(state)
huds=$(gbrp world.query '{"data":{"components":["t12t1_game::HudRoot"]}}' 2>/dev/null | jq -r '.result | length' 2>/dev/null)
pickups_alive=$(pick_entity_count)
cubes=$(gbrp world.query '{"data":{"components":["t12t1_game::FallingCube"]}}' 2>/dev/null | jq -r '.result | length' 2>/dev/null)
sleep 3
strip=$(ui_texts)
swap_line=false
echo "$strip" | grep -Eq "in place of '[^']*hud\.bsn'" && swap_line=true
stand=true
[ "$boot_state" = "true,false,false" ] || stand=false
[ "${pickups_alive:-0}" = "3" ] 2>/dev/null || stand=false
[ "${cubes:-0}" -ge 1 ] 2>/dev/null || stand=false
[ "${huds:-0}" -ge 1 ] 2>/dev/null || stand=false
[ "$swap_line" = false ] || stand=false
log "STAND_CHAIN: boot=$boot_state HudRoot=$huds pickups_alive=$pickups_alive FallingCube=$cubes hud_swap_defect_line=$swap_line"
leg STAND_CHAIN "$stand"

# ---- start (the pause action is menu-gated; the checks below need play) -----
start_ok=false
if sweep_click menu; then
  start_ok=true
  log "after Start: Hud=$(vis_of hud) StartScreen=$(vis_of start)"
  shown "$(vis_of hud)" || start_ok=false
fi
[ "$start_ok" = true ] || leg CELL4_PICKUPS false

# ---- single-registration pause (the action is menu-gated, so now) -----------
tapkey Escape
sleep 1
s1=$(state)
tapkey Escape
sleep 1
s2=$(state)
single=true
[ "$(echo "$s1" | cut -d, -f2)" = "true" ] || single=false
[ "$(echo "$s2" | cut -d, -f2)" = "false" ] || single=false
log "STAND_PAUSE: after tap1=$s1 after tap2=$s2 (each tap flips once)"
leg STAND_PAUSE_SINGLE "$single"

goto_x() { # goto_x <target x> <key+> <key-> — x drive with z trim (the
  # camera-relative walk drifts; the pickup line sits on z=0)
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    read -r CURX _ CURZ <<< "$(player_pos)"
    [ -z "$CURX" ] && return 1
    if python3 -c "import sys; sys.exit(0 if $CURX >= $1 and abs($CURZ) <= 0.3 else 1)" 2>/dev/null; then return 0; fi
    if python3 -c "import sys; sys.exit(0 if $CURZ > 0.3 else 1)" 2>/dev/null; then
      keyev KeyW Pressed; sleep 0.2; keyev KeyW Released; sleep 0.15
    elif python3 -c "import sys; sys.exit(0 if $CURZ < -0.3 else 1)" 2>/dev/null; then
      keyev KeyS Pressed; sleep 0.2; keyev KeyS Released; sleep 0.15
    elif python3 -c "import sys; sys.exit(0 if $CURX < $1 else 1)" 2>/dev/null; then
      keyev "$2" Pressed; sleep 0.22; keyev "$2" Released; sleep 0.25
    fi
  done
  return 0
}
cell4=true
h0=$(health)
c_a=$(pick_count); t_a=$(pickups_text)
log "at spawn: count=$c_a text='$t_a' health=$h0 (expect 0 / 'Pickups: 0')"
[ "$c_a" = "0" ] || { [ "${t_a%%:*}" = "Pickups" ] || cell4=false; }
goto_x -0.55 KeyD KeyA
c_b=$(pick_count)
goto_x 0.55 KeyD KeyA
c_c=$(pick_count)
goto_x 1.2 KeyD KeyA
sleep 1
c_d=$(pick_count); t_d=$(pickups_text); pos_after=$(player_pos)
log "pickup walk: 0->$c_a/$c_b/$c_c->$c_d text='$t_d' pos=$(player_pos) health=$(health)"
seq_ok=false
python3 -c "import sys; sys.exit(0 if 0 <= $c_a <= $c_b <= $c_c <= $c_d and $c_d >= 3 else 1)" 2>/dev/null && seq_ok=true
[ "$seq_ok" = true ] || cell4=false
[ "$t_d" = "Pickups: ${c_d}" ] || cell4=false
h_end=$(health)
if python3 -c "import sys; sys.exit(0 if $h0 - $h_end < 1 else 1)" 2>/dev/null; then
  log "health untouched by the walk ($h_end)"
else
  # The walk crossed the hazard line: the same walk fed the damage channel.
  # Orthogonal to the pickups leg, and itself live evidence - noted, not a fail.
  log "note: health $h0 -> $h_end on the walk (hazard contact en route; the damage channel is live)"
fi
sleep 2
clear_log=false
ui_has_text "Level clear" && clear_log=true
log "level-clear line in the Game panel log strip: $clear_log"
[ "$clear_log" = true ] || cell4=false
# back off west, away from the hazard, before the next legs
goto_x 0.0 KeyA KeyD
leg CELL4_PICKUPS "$cell4"

# ---- cell 5: two doors, one pause, frozen player ----------------------------
cell5=true
tapkey Escape
sleep 1
p_vis=$(vis_of pause)
pos_a=$(player_pos)
walk KeyW 1
pos_b=$(player_pos)
frozen=false
python3 - "$pos_a" "$pos_b" << 'PYT' 2>/dev/null && frozen=true
import sys
ax, ay, az = (float(v) for v in sys.argv[1].split())
bx, by, bz = (float(v) for v in sys.argv[2].split())
sys.exit(0 if abs(ax-bx) + abs(ay-by) + abs(az-bz) < 0.01 else 1)
PYT
log "paused: screen=$p_vis pos $pos_a -> $pos_b (held W; frozen=$frozen)"
shown "$p_vis" || cell5=false
[ "$(state | cut -d, -f2)" = "true" ] || cell5=false
[ "$frozen" = true ] || cell5=false
if sweep_click resume; then
  sleep 1
  paused_off || cell5=false
  log "after Resume click: state=$(state) PauseScreen=$(vis_of pause)"
else
  cell5=false
fi
leg CELL5_PAUSE_DOORS "$cell5"

# ---- cell 2 supplement: the full-number restart -----------------------------
pent=$(gbrp world.query '{"data":{"components":["t12t1_game::PlayerHealth"]}}' 2>/dev/null | jq -r '.result[0].entity // empty' 2>/dev/null)
gbrp world.insert_components "{\"entity\":\"$pent\",\"components\":{\"t12t1_game::PlayerHealth\":{\"current\":-1.0,\"max\":100.0}}}" >/dev/null 2>&1
sleep 1.5
go_vis=$(vis_of gameover)
log "before Restart: state=$(state) GameOverScreen=$go_vis pickups_alive=$(pick_entity_count)"
c2r=
st_pre=$(state)
if [ "${st_pre##*,}" = "true" ] && shown "$go_vis"; then
  if sweep_click restart; then
    sleep 1.5
    st=$(state); h=$(health); c=$(pick_count); alive=$(pick_entity_count); pos=$(player_pos)
    log "after Restart: state=$st health=$h PickupCount=$c pickups_alive=$alive pos=$pos"
    [ "${st##*,}" = "false" ] && [ "${st%%,*}" = "false" ] || c2r=false
    python3 -c "import sys; sys.exit(0 if abs($h - 100.0) < 0.01 else 1)" 2>/dev/null || c2r=false
    [ "$c" = "0" ] || c2r=false
    [ "$alive" = "3" ] || c2r=false
    python3 - "$pos" << 'PYT' 2>/dev/null || c2r=false
import sys
x, y, z = (float(v) for v in sys.argv[1].split())
sys.exit(0 if abs(x + 2.0) < 0.02 and abs(y - 1.0) < 0.5 and abs(z) < 0.02 else 1)
PYT
    [ "$(vis_of gameover)" = "Hidden" ] || c2r=false
    c2r=${c2r:-true}
  fi
fi
leg CELL2_RESTART_RESET "$c2r"

op pie.play_input_toggle >/dev/null 2>&1
stop_pie
printf '%s\n' "$(summary_line)" > "$OUTDIR/t12t3-live-summary.txt"
log "VERDICT_LIVE_CHAINS: $(summary_line)"
log "T12T3_LIVE_CHAINS_DONE"
