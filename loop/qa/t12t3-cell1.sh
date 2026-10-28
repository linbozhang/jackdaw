#!/bin/bash
# T12-T3 cell 1: a brand-new scaffolded project shows the four screens out of
# the box. The project (t12t3-ui, scaffolded this round, cold-built once via
# `jd build` into .jackdaw/target/game/debug) is opened in the editor and
# played; the start screen is up first, and the Start button's real forwarded
# click hands over to the 3D world + HUD with the T11 player chain in it.
# Usage: bash loop/qa/t12t3-cell1.sh [project] [editorPort]
set -u
PROJECT="${1:-/Users/zhanglinbo/workspace/loop-mac/t12t3/t12t3-ui}"
PORT="${2:-15914}"
GAME_PORT=15702
CRATE='t12t3_ui'
REPO=/Users/zhanglinbo/workspace/jackdaw
OUTDIR="$REPO/loop/t12t3-live"
EDITOR_LOG="$OUTDIR/t12t3-cell1-editor.log"
CONSOLE_LOG="$OUTDIR/t12t3-cell1-console.log"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
TKEY='bevy_transform::components::transform::Transform'
KB_MSG='bevy_input::keyboard::KeyboardInput'
mkdir -p "$OUTDIR"
: > "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t12t3-cell1.XXXXXX)"
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
  pkill -f 't12t3-ui$' 2>/dev/null
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
  gbrp world.get_resources "{\"resource\":\"${CRATE}::GameState\"}" 2>/dev/null \
    | jq -r '.result.value | "\(.menu),\(.paused),\(.game_over)"' 2>/dev/null
}
menu_off() { state | grep -q '^false,'; }
screen_vis() {
  local raw="$1" want_not="${2:-}"
  gbrp world.query '{"data":{"components":["bevy_camera::visibility::Visibility","jackdaw_bind::types::Bindings"]}}' 2>/dev/null \
    | jq -r --arg raw "$raw" --arg vn "$want_not" \
      '[.result[]
        | (.components["jackdaw_bind::types::Bindings"] | tostring) as $b
        | select($b | contains("Res('"$CRATE"'::GameState).\($raw)"))
        | select(($vn == "not") == ($b | contains("not")))
        | .components["bevy_camera::visibility::Visibility"]] | first // empty' 2>/dev/null
}
ui_texts() {
  brp jackdaw/ui_tree '{"kind":"text","visible_only":true,"depth":24}' 2>/dev/null \
    | jq -r '[.. | objects | select(.kind? == "text") | .text // ""] | join(" || ")' 2>/dev/null
}
frame_click() {
  op input.pointer "{\"x\":$1,\"y\":$2,\"action\":\"click\",\"button\":\"primary\"}" >/dev/null 2>&1
  sleep 1.5
}
sweep_click() {
  local x y
  for y in 772 757 787 800 745; do
    for x in 787 700 875 550 1025; do
      frame_click "$x" "$y"
      if menu_off; then log "sweep_click: hit at ($x,$y)"; return 0; fi
    done
  done
  return 1
}

pkill -x jackdaw 2>/dev/null; pkill -f 't12t3-ui$' 2>/dev/null
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
log "EDITOR_READY (fresh project $PROJECT)"

op scene.open "{\"path\":\"$PROJECT/assets/scene.bsn\"}" >/dev/null 2>&1
sleep 2; wait_idle 300 >/dev/null
op pie.play_current >/dev/null 2>&1
deadline=$((SECONDS + 900))
while [ $SECONDS -lt $deadline ]; do
  game_up && break
  sleep 2
done
sleep 4
if ! game_up; then log "PIE_BOOT_FAIL"; leg CELL1_STARTSCREEN_FIRST false; leg CELL1_START_TO_WORLD false; exit 1; fi
op pie.play_input_toggle >/dev/null 2>&1
sleep 2
WINDOW_ENTITY=$(gbrp world.query '{"data":{"components":["bevy_window::window::Window"]}}' 2>/dev/null | jq -r '.result[0].entity // empty' 2>/dev/null)

# The start screen is up first: clean boot state, StartScreen shown, the hud
# hidden behind its `not` binding, and the four screens' texts in the document.
boot=$(state)
start_vis=$(screen_vis menu)
hud_vis=$(screen_vis menu not)
log "boot: state=$boot StartScreen=$start_vis Hud=$hud_vis"
c1a=true
[ "$boot" = "true,false,false" ] || c1a=false
shown "$start_vis" || c1a=false
[ "$hud_vis" = "Hidden" ] || c1a=false
strip=$(ui_texts)
log "log strip texts: $(echo "$strip" | head -c 300)"
leg CELL1_STARTSCREEN_FIRST "$c1a"

# Start's real forwarded click hands over to the 3D world + HUD, and the T11
# player chain is on stage (player capsule with PlayerHealth, a CameraRig).
c1b=false
if sweep_click menu; then
  sleep 1
  hud_vis=$(screen_vis menu not)
  start_vis=$(screen_vis menu)
  pickups=$(gbrp world.query '{"data":{"components":["t12t3_ui::Pickup"]}}' 2>/dev/null | jq -r '.result | length' 2>/dev/null)
  cubes=$(gbrp world.query '{"data":{"components":["t12t3_ui::FallingCube"]}}' 2>/dev/null | jq -r '.result | length' 2>/dev/null)
  player=$(gbrp world.query "{\"data\":{\"components\":[\"${CRATE}::PlayerHealth\",\"$TKEY\"]}}" 2>/dev/null | jq -r '.result | length' 2>/dev/null)
  rig=$(gbrp world.query '{"data":{"components":["jackdaw_camera_rig::CameraRig"]}}' 2>/dev/null | jq -r '.result | length' 2>/dev/null)
  htext=$(gbrp world.query '{"data":{"components":["bevy_ui::widget::text::Text"]}}' 2>/dev/null | jq -r '[.result[] | .components["bevy_ui::widget::text::Text"] | strings | select(test("^[0-9.-]+ / "))] | first // empty' 2>/dev/null)
  log "after Start: state=$(state) Hud=$hud_vis Start=$start_vis pickups=$pickups FallingCube=$cubes player=$player rig=$rig health_text='$htext'"
  shown "$hud_vis" && [ "$start_vis" = "Hidden" ] && [ "${pickups:-0}" = "3" ] 2>/dev/null \
    && [ "${cubes:-0}" -ge 1 ] 2>/dev/null && [ "${player:-0}" -ge 1 ] 2>/dev/null \
    && [ "${rig:-0}" -ge 1 ] 2>/dev/null && [ -n "$htext" ] && c1b=true
fi
leg CELL1_START_TO_WORLD "$c1b"

op pie.play_input_toggle >/dev/null 2>&1
for _ in 1 2 3 4; do op pie.stop >/dev/null 2>&1; sleep 2; st=$(brp jackdaw/status '{}' | jq -r '.result.pie // empty' 2>/dev/null); [ "$st" = stopped ] && break; done
printf '%s\n' "$(summary_line)" > "$OUTDIR/t12t3-cell1-summary.txt"
log "VERDICT_CELL1: $(summary_line)"
log "T12T3_CELL1_DONE"
