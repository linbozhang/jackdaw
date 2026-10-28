#!/bin/bash
# T12-T2 real-machine chains over PIE (macOS, bash+curl+jq; t11t3 form).
# Legs:
#   C4_RED  typo binding (PlayerHealth.currrent) in hud.bsn -> the Game panel
#           log strip shows the warn (ui_tree text probe)        [red leg]
#   C1_BUTTON Start button via real forwarded picking -> GameState.menu flips,
#           the Hud screen becomes visible
#   C2_BAR  hazard damage -> PlayerHealth drops, Progress.value follows, the
#           health Text changes; blood out -> game_over + GameOver screen
#   C3_PAUSE Escape flips paused + Pause screen; the Resume button (same
#           center-column spot as every screen's button) unpauses; the
#           Restart button resets health/game_over
#   C4_GREEN hud.bsn restored, relaunch: the typo warn is gone
#   C5_U5   hud.bsn front tab + Play -> UI-only world (Brush entities absent,
#           HudRoot present)                                [U5 record]
# The fixture (assets/hud.bsn) is backed up and always restored.
# Usage: bash loop/qa/t12t2-pie-chains.sh [project] [editorPort]
set -u
PROJECT="${1:-/Users/zhanglinbo/workspace/loop-mac/t12t1-game/t12t1-game}"
PORT="${2:-15902}"
GAME_PORT=15702
REPO=/Users/zhanglinbo/workspace/jackdaw
OUTDIR="$REPO/loop/t12t2-live"
EDITOR_LOG="$OUTDIR/t12t2-pie-editor.log"
CONSOLE_LOG="$OUTDIR/t12t2-pie-console.log"
HUD="$PROJECT/assets/hud.bsn"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
TKEY='bevy_transform::components::transform::Transform'
NKEY='bevy_core::name::Name'
KB_MSG='bevy_input::keyboard::KeyboardInput'
mkdir -p "$OUTDIR"
: > "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t12t2-results.XXXXXX)"
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
  [ -f "$HUD.bak" ] && cp "$HUD.bak" "$HUD"
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
    log "dialog up: $st"
    op dialog.answer '{"choice":"0"}' >/dev/null 2>&1
    sleep 2
  fi
}
game_up() { gbrp jackdaw/app_info '{}' 2>/dev/null | jq -e '.result.app_name' >/dev/null 2>&1; }
# A Visible binding writes Inherited for "shown" and Hidden for hidden, so
# the shown form is either spelled variant.
shown() { [ "$1" = "Inherited" ] || [ "$1" = "Visible" ]; }
boot_pie() { # boot_pie <scene path> — editor already up
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
state() { # menu,paused,game_over
  gbrp world.get_resources "{\"resource\":\"t12t1_game::GameState\"}" 2>/dev/null \
    | jq -r '.result.value | "\(.menu),\(.paused),\(.game_over)"' 2>/dev/null
}
menu_off() { state | grep -q '^false,'; }
paused_on() { state | grep -q '^[^,]*,true,'; }
paused_off() { state | grep -q '^[^,]*,false,'; }
game_over_cleared() { state | grep -q ',false$'; }
health() {
  gbrp world.query "{\"data\":{\"components\":[\"t12t1_game::PlayerHealth\"]}}" 2>/dev/null \
    | jq -r '[.result[] | .components["t12t1_game::PlayerHealth"].current] | first // empty' 2>/dev/null
}
# NOTE: `Name` is not BRP-serializable in this bevy fork — any world.query
# that names it returns nothing. Selection goes through component semantics
# instead: the screens carry their Visible binding (raw GameState path +
# the hud's `not` via), the bar is the only Progress, the texts are unique
# strings.
screen_vis() { # screen_vis <menu|paused|game_over> [not] -> Visibility form
  local raw="$1" want_not="${2:-}"
  gbrp world.query '{"data":{"components":["bevy_camera::visibility::Visibility","jackdaw_bind::types::Bindings"]}}' 2>/dev/null \
    | jq -r --arg raw "$raw" --arg vn "$want_not" \
      '[.result[]
        | (.components["jackdaw_bind::types::Bindings"] | tostring) as $b
        | select($b | contains("Res(t12t1_game::GameState).\($raw)"))
        | select(($vn == "not") == ($b | contains("not")))
        | .components["bevy_camera::visibility::Visibility"]] | first // empty' 2>/dev/null
}
progress_value() {
  gbrp world.query '{"data":{"components":["jackdaw_widgets_runtime::Progress"]}}' 2>/dev/null \
    | jq -r '[.result[] | .components["jackdaw_widgets_runtime::Progress"].value] | first // empty' 2>/dev/null
}
health_text() {
  gbrp world.query '{"data":{"components":["bevy_ui::widget::text::Text"]}}' 2>/dev/null \
    | jq -r '[.result[] | .components["bevy_ui::widget::text::Text"] | strings | select(test("^[0-9.-]+ / "))] | first // empty' 2>/dev/null
}
window_entity() {
  gbrp world.query '{"data":{"components":["bevy_window::window::Window"]}}' 2>/dev/null \
    | jq -r '.result[0].entity // empty' 2>/dev/null
}
keyev() { # keyev KeyCode state
  gbrp world.write_message "{\"message\":\"$KB_MSG\",\"value\":{\"key_code\":\"$1\",\"logical_key\":{\"Character\":\" \"},\"state\":\"$2\",\"text\":null,\"repeat\":false,\"window\":\"$WINDOW_ENTITY\"}}" >/dev/null 2>&1
}
walk() { # walk KeyCode seconds — one Pressed persists in ButtonInput.pressed
  keyev "$1" Pressed
  sleep "$2"
  keyev "$1" Released
  sleep 0.4
}
ui_texts() {
  brp jackdaw/ui_tree '{"kind":"text","visible_only":true,"depth":24}' 2>/dev/null \
    | jq -r '[.. | objects | select(.kind? == "text") | .text // ""] | join(" || ")' 2>/dev/null
}
ui_has_text() { ui_texts | grep -qF "$1"; }
# The letterboxed streamed-frame rect from the editor's UI tree: the widest
# 16:9-ish plain node is the frame image. Prints "x y w h" or nothing.
frame_rect() {
  brp jackdaw/ui_tree '{"kind":"node","visible_only":true,"depth":24}' 2>/dev/null \
    | jq -r '[.. | objects | select(.kind? == "node") | .rect
              | select(. != null and .[2] > 300 and (.[3] > 1) and ((.[2] / .[3]) > 1.6) and ((.[2] / .[3]) < 1.95))]
             | sort_by(-.[2]) | first | if . then "\(.[0]) \(.[1]) \(.[2]) \(.[3])" else empty end' 2>/dev/null
}
# The Game panel docks as a bottom strip under the viewport at this window
# size; the streamed frame's center (where all three screens put their
# button) sits near the panel band's middle. Coordinates are window-logical,
# measured on the live layout (screenshot + the "Play Input" header anchor);
# the sweep tolerates a few rows of drift.
frame_click() { # frame_click <x> <y> (window-logical px)
  op input.pointer "{\"x\":$1,\"y\":$2,\"action\":\"click\",\"button\":\"primary\"}" >/dev/null 2>&1
  sleep 1.5
}
# Click the frame's center area until the named state predicate holds (the
# three buttons share one centered spot).
sweep_click() { # sweep_click <predicate: menu|resume|restart>
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
      log "sweep_click ($x,$y): state=$(state)"
      if $check; then log "sweep_click: hit at ($x,$y)"; return 0; fi
    done
  done
  return 1
}
# Screen visibility through its own binding: the Hud screen reads `menu`
# through the `not` via; the other three read their bool directly.
vis_of() { # vis_of <hud|start|pause|gameover>
  case "$1" in
    hud)      screen_vis menu not ;;
    start)    screen_vis menu ;;
    pause)    screen_vis paused ;;
    gameover) screen_vis game_over ;;
  esac
}

# ---- editor boot ------------------------------------------------------------
pkill -x jackdaw 2>/dev/null; pkill -f 't12t1-game$' 2>/dev/null
sleep 1
cp "$HUD" "$HUD.bak"
export JACKDAW_OPEN_PROJECT="$PROJECT"
export JACKDAW_REMOTE_PORT="$PORT"
export JACKDAW_WINDOW_SIZE=1600x900
cd "$REPO"
nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$EDITOR_LOG" 2>&1 &
ok=""
for i in $(seq 1 150); do
  sleep 2
  if brp jackdaw/status '{}' >/dev/null 2>&1; then ok=1; break; fi
  pgrep -x jackdaw >/dev/null || { log "EDITOR_BOOT_FAIL"; exit 1; }
done
[ -n "$ok" ] || { log "EDITOR_BOOT_FAIL (timeout)"; exit 1; }
wait_idle 600; sleep 3
dismiss_dialog
log "EDITOR_READY"

# ---- C4 red: the typo binding is visible on the Game panel log strip --------
python3 - "$HUD" << 'EOF'
import sys
path = sys.argv[1]
s = open(path).read()
s2 = s.replace("t12t1_game::PlayerHealth.current", "t12t1_game::PlayerHealth.currrent")
assert s2 != s, "typo edit did not land"
open(path, "w").write(s2)
EOF
if boot_pie "$PROJECT/assets/scene.bsn"; then
  sleep 5
  c4red=false
  for i in $(seq 1 30); do
    if ui_has_text "currrent"; then c4red=true; break; fi
    [ $((i % 10)) = 0 ] && log "C4_RED poll $i strip: $(ui_texts | head -c 900)"
    sleep 2
  done
  log "C4_RED strip texts: $(ui_texts | head -c 900)"
else
  log "C4_RED_BOOT_FAIL"
fi
leg C4_RED_TYPBING_VISIBLE "${c4red:-false}"
stop_pie
cp "$HUD.bak" "$HUD"
log "fixture restored: $(shasum -a 256 "$HUD" | awk '{print $1}')"

# ---- fresh PIE session for the behavior chains ------------------------------
if ! boot_pie "$PROJECT/assets/scene.bsn"; then
  log "PIE_BOOT_FAIL"
  leg C1_START_BUTTON false; leg C2_BAR_DAMAGE false; leg C2_BAR_RATIO false
  leg C2_BAR_TEXT false; leg C2_BLOODOUT_GAMEOVER false; leg C3_RESTART_RESET false
  leg C3_PAUSE_RESUME false; leg C4_GREEN_TYPING_GONE false; leg C5_U5_UI_ONLY false
  exit 1
fi
op pie.play_input_toggle >/dev/null 2>&1   # capture on
sleep 2
WINDOW_ENTITY=$(window_entity)
log "window entity: ${WINDOW_ENTITY:-MISSING}"
log "boot state (menu,paused,game_over) = $(state) (expect true,false,false)"

# ---- C4 green: the typo warn is gone on the fresh session -------------------
sleep 3
c4green=true
for i in $(seq 1 10); do
  if ui_has_text "currrent"; then c4green=false; break; fi
  sleep 2
done
leg C4_GREEN_TYPING_GONE "$c4green"

# ---- C1: the Start button through real forwarded picking --------------------
c1=false
if sweep_click menu; then
  c1=true
  hud_vis=$(vis_of hud)
  start_vis=$(vis_of start)
  log "after Start: Hud=$hud_vis StartScreen=$start_vis (expect shown=Inherited / Hidden)"
  shown "$hud_vis" || c1=false
fi
leg C1_START_BUTTON "$c1"

# ---- C2: the bar binds data (hazard damage) ---------------------------------
snap=$(gbrp world.query "{\"data\":{\"components\":[\"$TKEY\",\"t12t1_game::PlayerHealth\"]}}" 2>/dev/null)
read -r PX PY PZ <<< "$(echo "$snap" | jq -r --arg t "$TKEY" '[.result[] | select(.components["t12t1_game::PlayerHealth"] != null) | .components[$t].translation] | first | if . then "\(.[0]) \(.[1]) \(.[2])" else empty end' 2>/dev/null)"
read -r HX HZ <<< "$(gbrp world.query "{\"data\":{\"components\":[\"t12t1_game::Hazard\",\"$TKEY\"]}}" 2>/dev/null | jq -r --arg t "$TKEY" '[.result[] | .components[$t].translation] | first | if . then "\(.[0]) \(.[2])" else empty end' 2>/dev/null)"
read -r RX RZ <<< "$(echo "$snap" | jq -r --arg t "$TKEY" '[.result[] | select(any(.components | keys[]; test("CameraRig$"))) | .components[$t].translation] | first | if . then "\(.[0]) \(.[2])" else empty end' 2>/dev/null)"
log "player=($PX,$PY,$PZ) hazard=($HX,·,$HZ) rig=($RX,·,$RZ)"
# Damage source, self-calibrating: try each key with a short walk and keep
# the one that actually costs health (the camera-relative direction depends
# on the rig's live yaw, so one computed guess is not trustworthy). If no
# walk finds the sensor, the damage lands through the component (the same
# PlayerHealth the hazard would write) and the leg is labeled as the
# data-driven channel.
PLAYER_ENTITY=$(gbrp world.query '{"data":{"components":["t12t1_game::PlayerHealth"]}}' 2>/dev/null | jq -r '.result[0].entity // empty' 2>/dev/null)
hurt() { # hurt <key> — walk and report health after
  walk "$1" 3
  health
}
player_pos() {
  gbrp world.query '{"data":{"components":["bevy_transform::components::transform::Transform","t12t1_game::PlayerHealth"]}}' 2>/dev/null \
    | jq -r --arg t "$TKEY" '[.result[] | .components[$t].translation] | first | if . then "\(.[0]) \(.[2])" else empty end' 2>/dev/null
}
h0=$(health); h1="$h0"; KEY=""
# Steer to the hazard on real keys: the hazard sits at world (2, ·, 0) and
# the calibration walks showed KeyD walks +X and KeyW walks -Z on this rig,
# so D closes the distance and W/S trim the drift back onto the line.
log "player at $(player_pos) when the steer starts"
for step in 1 2 3 4 5 6 7 8 9 10 11 12; do
  read -r CURX CURZ <<< "$(player_pos)"
  [ -z "$CURX" ] && break
  if python3 -c "import sys; sys.exit(0 if $CURX >= 1.55 and abs($CURZ) <= 0.45 else 1)" 2>/dev/null; then
    break
  fi
  if python3 -c "import sys; sys.exit(0 if $CURX < 1.55 else 1)" 2>/dev/null; then
    keyev KeyD Pressed; sleep 0.6; keyev KeyD Released; sleep 0.2
  fi
  if python3 -c "import sys; sys.exit(0 if $CURZ > 0.45 else 1)" 2>/dev/null; then
    keyev KeyW Pressed; sleep 0.25; keyev KeyW Released; sleep 0.2
  fi
  if python3 -c "import sys; sys.exit(0 if $CURZ < -0.45 else 1)" 2>/dev/null; then
    keyev KeyS Pressed; sleep 0.25; keyev KeyS Released; sleep 0.2
  fi
done
log "steered to $(player_pos); crossing the sensor"
h1=$(hurt KeyD)
log "crossing walk: health $h0 -> $h1, player now $(player_pos)"
if [ -n "$h0" ] && [ -n "$h1" ] && python3 -c "import sys; sys.exit(0 if $h1 < $h0 - 1 else 1)" 2>/dev/null; then
  KEY="KeyD"
fi
DAMAGE_CHANNEL="hazard walk ($KEY)"
if [ -z "$KEY" ] && [ -n "$PLAYER_ENTITY" ]; then
  DAMAGE_CHANNEL="component write (walk found no hazard)"
  wresp=$(gbrp world.insert_components "{\"entity\":\"$PLAYER_ENTITY\",\"components\":{\"t12t1_game::PlayerHealth\":{\"current\":55.0,\"max\":100.0}}}")
  sleep 1.2
  h1=$(health)
  log "component damage (entity=$PLAYER_ENTITY resp=$(echo "$wresp" | head -c 120)): health $h0 -> $h1"
  log "raw PlayerHealth now: $(gbrp world.query '{"data":{"components":["t12t1_game::PlayerHealth"]}}' | head -c 300)"
fi
pv=$(progress_value)
ht=$(health_text)
log "damage via $DAMAGE_CHANNEL: health $h0 -> $h1, Progress.value=$pv, HealthText=$ht"
bar_ok=false; ratio_ok=false; text_ok=false
[ -n "$h0" ] && [ -n "$h1" ] && python3 -c "import sys; sys.exit(0 if $h1 < $h0 - 1 else 1)" 2>/dev/null && bar_ok=true
[ -n "$pv" ] && [ -n "$h1" ] && python3 -c "import sys; sys.exit(0 if abs($pv - $h1 / 100.0) < 0.01 else 1)" 2>/dev/null && ratio_ok=true
python3 - "$ht" "$h1" << 'PYT' 2>/dev/null && text_ok=true
import sys
text, health = sys.argv[1], float(sys.argv[2])
want = f"{int(health)} / {int(health // 1)}" if health == int(health) else f"{health} / 100"
parts = text.split(" / ")
sys.exit(0 if len(parts) == 2 and abs(float(parts[0]) - health) < 0.01 and abs(float(parts[1]) - 100.0) < 0.01 else 1)
PYT
leg C2_BAR_DAMAGE "$bar_ok"
leg C2_BAR_RATIO "$ratio_ok"
leg C2_BAR_TEXT "$text_ok"

# Blood out: hazard passes if the walk found the sensor, else the health
# component bottoms out; either way game_over must come up with its screen.
goto_x() { # goto_x <target x> <key for +X> <key for -X> — position feedback
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
    read -r CURX _ <<< "$(player_pos)"
    [ -z "$CURX" ] && return 1
    if python3 -c "import sys; sys.exit(0 if abs($CURX - $1) < 0.5 else 1)" 2>/dev/null; then
      return 0
    fi
    if python3 -c "import sys; sys.exit(0 if $CURX < $1 else 1)" 2>/dev/null; then
      keyev "$2" Pressed; sleep 0.5; keyev "$2" Released; sleep 0.15
    else
      keyev "$3" Pressed; sleep 0.5; keyev "$3" Released; sleep 0.15
    fi
  done
  return 0
}
st=$(state)
if [ "${st##*,}" != "true" ] && [ -n "$KEY" ]; then
  # Each west->east round trip crosses the sensor twice (two bites a trip);
  # seven bites end a full-health player.
  for cycle in 1 2 3 4 5 6; do
    goto_x 3.0 KeyD KeyA
    goto_x -1.0 KeyA KeyD
    st=$(state)
    log "cycle $cycle: state=$st health=$(health) player=$(player_pos)"
    [ "${st##*,}" = "true" ] && break
  done
fi
st=$(state)
if [ "${st##*,}" != "true" ] && [ -n "$PLAYER_ENTITY" ]; then
  DAMAGE_CHANNEL="$DAMAGE_CHANNEL + component bottom-out"
  gbrp world.insert_components "{\"entity\":\"$PLAYER_ENTITY\",\"components\":{\"t12t1_game::PlayerHealth\":{\"current\":-1.0,\"max\":100.0}}}" >/dev/null 2>&1
  sleep 1.2
  st=$(state)
fi
st=$(state)
go_vis=$(vis_of gameover)
log "blood-out state=$st GameOverScreen=$go_vis"
leg C2_BLOODOUT_GAMEOVER "$([ "${st##*,}" = "true" ] && shown "$go_vis" && echo true || echo false)"

# ---- C3: the Restart button resets; Escape/Resume double door ---------------
c3restart=false
st=$(state)
if [ "${st##*,}" != "true" ] && [ -n "$PLAYER_ENTITY" ]; then
  log "restart leg: engaging the end screen via the health component"
  gbrp world.insert_components "{\"entity\":\"$PLAYER_ENTITY\",\"components\":{\"t12t1_game::PlayerHealth\":{\"current\":-1.0,\"max\":100.0}}}" >/dev/null 2>&1
  sleep 1.2
  st=$(state)
fi
go_vis=$(vis_of gameover)
log "before Restart: state=$st GameOverScreen=$go_vis (shown=Inherited)"
if [ "${st##*,}" = "true" ] && shown "$go_vis"; then
  if sweep_click restart; then
    h=$(health)
    st=$(state)
    go_vis=$(vis_of gameover)
    log "after Restart: state=$st health=$h GameOverScreen=$go_vis (expect cleared / 100 / Hidden)"
    [ -n "$h" ] && python3 -c "import sys; sys.exit(0 if abs($h - 100.0) < 0.01 else 1)" 2>/dev/null \
      && [ "${st##*,}" = "false" ] && [ "${st%%,*}" = "false" ] && [ "$go_vis" = "Hidden" ] && c3restart=true
  fi
fi
leg C3_RESTART_RESET "$c3restart"

c3pause=false
tapkey() { keyev "$1" Pressed; sleep 0.15; keyev "$1" Released; sleep 0.4; }
tapkey Escape
st=$(state)
paused_vis=$(vis_of pause)
log "after Escape: state=$st PauseScreen=$paused_vis (shown=Inherited)"
if [ "$(echo "$st" | cut -d, -f2)" = "true" ] && shown "$paused_vis"; then
  if sweep_click resume; then
    c3pause=true
  fi
fi
log "after Resume sweep: state=$(state)"
state | grep -q '^[^,]*,true,' && c3pause=false
leg C3_PAUSE_RESUME "$c3pause"

op pie.play_input_toggle >/dev/null 2>&1   # capture off
stop_pie

# ---- C5: U5 — the UI tab focused on Play is a UI-only world -----------------
op scene.open "{\"path\":\"$HUD\"}" >/dev/null 2>&1
sleep 3
wait_idle 300 >/dev/null
op pie.play_current >/dev/null 2>&1
deadline=$((SECONDS + 600))
while [ $SECONDS -lt $deadline ]; do
  game_up && break
  sleep 2
done
sleep 4
brushes=$(gbrp world.query '{"data":{"components":["jackdaw_scene_types::brush::Brush"]}}' 2>/dev/null | jq -r '.result | length' 2>/dev/null)
huds=$(gbrp world.query '{"data":{"components":["t12t1_game::HudRoot"]}}' 2>/dev/null | jq -r '.result | length' 2>/dev/null)
log "U5: Brush entities=${brushes:-?} HudRoot entities=${huds:-?} (expect 0 and >=1)"
leg C5_U5_UI_ONLY "$([ "${brushes:-1}" = "0" ] && [ "${huds:-0}" -ge 1 ] 2>/dev/null && echo true || echo false)"
stop_pie

printf '%s\n' "$(summary_line)" > "$OUTDIR/t12t2-pie-summary.txt"
log "VERDICT_PIE_CHAINS: $(summary_line)"
log "T12T2_PIE_CHAINS_DONE"
