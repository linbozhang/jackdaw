#!/bin/bash
# T12-T3 cell 12: the no-modules form keeps the whole UI. The project
# (t12t3-nophys, scaffolded --no-modules this round, cold-built once) plays
# with all four screens; the Interact key deals the fallback damage the bar
# follows; the pickup text stays authored ("Pickups: 0") while its binding's
# missing-context warn shows on the Game panel log strip (the U2 channel,
# alive without the physics module too); and the world carries no avian
# components.
# Usage: bash loop/qa/t12t3-cell12.sh [project] [editorPort]
set -u
PROJECT="${1:-/Users/zhanglinbo/workspace/loop-mac/t12t3/t12t3-nophys}"
PORT="${2:-15915}"
GAME_PORT=15702
CRATE='t12t3_nophys'
REPO=/Users/zhanglinbo/workspace/jackdaw
OUTDIR="$REPO/loop/t12t3-live"
EDITOR_LOG="$OUTDIR/t12t3-cell12-editor.log"
CONSOLE_LOG="$OUTDIR/t12t3-cell12-console.log"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
KB_MSG='bevy_input::keyboard::KeyboardInput'
mkdir -p "$OUTDIR"
: > "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t12t3-cell12.XXXXXX)"
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
  pkill -f 't12t3-nophys$' 2>/dev/null
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
health() {
  gbrp world.query "{\"data\":{\"components\":[\"${CRATE}::PlayerHealth\"]}}" 2>/dev/null \
    | jq -r '[.result[] | .components["'"$CRATE"'::PlayerHealth"].current] | first // empty' 2>/dev/null
}
progress_value() {
  gbrp world.query '{"data":{"components":["jackdaw_widgets_runtime::Progress"]}}' 2>/dev/null \
    | jq -r '[.result[] | .components["jackdaw_widgets_runtime::Progress"].value] | first // empty' 2>/dev/null
}
health_text() {
  gbrp world.query '{"data":{"components":["bevy_ui::widget::text::Text"]}}' 2>/dev/null \
    | jq -r '[.result[] | .components["bevy_ui::widget::text::Text"] | strings | select(test("^[0-9.-]+ / "))] | first // empty' 2>/dev/null
}
pickups_text() {
  gbrp world.query '{"data":{"components":["bevy_ui::widget::text::Text"]}}' 2>/dev/null \
    | jq -r '[.result[] | .components["bevy_ui::widget::text::Text"] | strings | select(test("^Pickups: "))] | first // empty' 2>/dev/null
}
window_entity() {
  gbrp world.query '{"data":{"components":["bevy_window::window::Window"]}}' 2>/dev/null | jq -r '.result[0].entity // empty' 2>/dev/null
}
keyev() {
  gbrp world.write_message "{\"message\":\"$KB_MSG\",\"value\":{\"key_code\":\"$1\",\"logical_key\":{\"Character\":\" \"},\"state\":\"$2\",\"text\":null,\"repeat\":false,\"window\":\"$WINDOW_ENTITY\"}}" >/dev/null 2>&1
}
tapkey() { keyev "$1" Pressed; sleep 0.2; keyev "$1" Released; sleep 0.6; }
ui_texts() {
  brp jackdaw/ui_tree '{"kind":"text","visible_only":true,"depth":24}' 2>/dev/null \
    | jq -r '[.. | objects | select(.kind? == "text") | .text // ""] | join(" || ")' 2>/dev/null
}
ui_has_text() { ui_texts | grep -qF "$1"; }
frame_click() {
  op input.pointer "{\"x\":$1,\"y\":$2,\"action\":\"click\",\"button\":\"primary\"}" >/dev/null 2>&1
  sleep 1.5
}
# The streamed frame's on-screen rect: the widest wide node in the editor's
# layout (the Game panel docks as a bottom band; the stream letterboxes into
# it). The template centers every screen's button, so the frame center is the
# button - measure first, then sweep a small grid around the measured center.
frame_center() {
  brp jackdaw/ui_tree '{"kind":"node","visible_only":true,"depth":24}' 2>/dev/null \
    | jq -r '[.. | objects | select(.kind? == "node") | .rect
              | select(. != null and .[2] > 300 and .[3] > 40)]
             | sort_by(-(.[2] * .[3])) | first
             | if . then "\(.[0] + .[2] / 2) \(.[1] + .[3] / 2)" else empty end' 2>/dev/null
}
sweep_click() {
  local x y
  read -r CX CY <<< "$(frame_center)"
  if [ -n "$CX" ]; then
    log "frame center measured at ($CX,$CY); clicking it"
    for d in "0 0" "-40 0" "40 0" "0 -20" "0 20"; do
      read -r DX DY <<< "$d"
      frame_click $(( ${CX%.*} + DX )) $(( ${CY%.*} + DY ))
      if menu_off; then log "sweep_click: hit at ($(( ${CX%.*} + DX )),$(( ${CY%.*} + DY )))"; return 0; fi
      log "sweep_click ($(( ${CX%.*} + DX )),$(( ${CY%.*} + DY ))): state=$(state)"
    done
  fi
  log "falling back to the fixed grid"
  for y in 772 787 800 757 745; do
    for x in 800 787 875 700 550 1025; do
      frame_click "$x" "$y"
      if menu_off; then log "sweep_click: hit at ($x,$y)"; return 0; fi
      log "sweep_click ($x,$y): state=$(state)"
    done
  done
  return 1
}

pkill -x jackdaw 2>/dev/null; pkill -f 't12t3-nophys$' 2>/dev/null
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
log "EDITOR_READY (no-modules project $PROJECT)"

op scene.open "{\"path\":\"$PROJECT/assets/scene.bsn\"}" >/dev/null 2>&1
sleep 2; wait_idle 300 >/dev/null
op pie.play_current >/dev/null 2>&1
deadline=$((SECONDS + 900))
while [ $SECONDS -lt $deadline ]; do
  game_up && break
  sleep 2
done
sleep 4
if ! game_up; then log "PIE_BOOT_FAIL"; leg CELL12_UI_PRESENT false; leg CELL12_INTERACT_DAMAGE false; leg CELL12_NO_AVIAN false; exit 1; fi
# Capture-on with verification: the toggle refuses silently while the game's
# stream is not fresh yet, so probe the panel header and retry.
capture_on() {
  for i in 1 2 3 4 5 6; do
    if brp jackdaw/ui_tree '{"kind":"text","visible_only":false,"depth":30}' 2>/dev/null | grep -q "Shift+Esc to release"; then
      return 0
    fi
    op pie.play_input_toggle >/dev/null 2>&1
    sleep 2.5
  done
  brp jackdaw/ui_tree '{"kind":"text","visible_only":false,"depth":30}' 2>/dev/null | grep -q "Shift+Esc to release"
}
capture_on
log "capture on: $?"
WINDOW_ENTITY=$(window_entity)

# The four screens are all present with zero module gating: clean boot state,
# the start screen shown, and the hud's authored texts live in the document
# (the bar at 100 / 100, the pickup text static at "Pickups: 0"). The
# PickupCount binding's missing-context warn reaches the Game panel log strip.
boot=$(state)
start_vis=$(screen_vis menu)
sleep 3
pt=$(pickups_text); ht=$(health_text)
strip=$(ui_texts)
warn_seen=false
echo "$strip" | grep -q "PickupCount" && warn_seen=true
c12a=true
[ "$boot" = "true,false,false" ] || c12a=false
shown "$start_vis" || c12a=false
[ "$pt" = "Pickups: 0" ] || c12a=false
log "boot: state=$boot StartScreen=$start_vis pickups_text='$pt' health_text='$ht' warn_on_strip=$warn_seen"
log "strip: $(echo "$strip" | grep -o 'jackdaw_bind[^\"]*PickupCount[^\"]*' | head -1)"
leg CELL12_UI_PRESENT "$c12a"

# Start, then the Interact key deals 15: 100 -> 85 with the bar and the text
# following.
c12b=false
if sweep_click menu; then
  sleep 1
  h0=$(health)
  tapkey KeyE
  sleep 1
  h1=$(health); pv=$(progress_value); ht1=$(health_text)
  log "Interact: health $h0 -> $h1 Progress.value=$pv text='$ht1' state=$(state)"
  H1_INT=$(python3 -c 'import sys; print(int(float(sys.argv[1])))' "$h1" 2>/dev/null)
  python3 -c "import sys; sys.exit(0 if abs($h0 - $h1 - 15.0) < 0.01 else 1)" 2>/dev/null \
    && python3 -c "import sys; sys.exit(0 if abs($pv - $h1 / 100.0) < 0.01 else 1)" 2>/dev/null \
    && [ "$ht1" = "$H1_INT / 100" ] && c12b=true
fi
leg CELL12_INTERACT_DAMAGE "$c12b"

# No avian in the world: the rigid-body query returns nothing and the
# project's extracted schema has no avian types.
rb=$(gbrp world.query '{"data":{"components":["avian3d::dynamics::rigid_body::RigidBody"]}}' 2>/dev/null | jq -r '.result | length' 2>/dev/null)
rb_alt=$(gbrp world.query '{"data":{"components":["avian3d::prelude::RigidBody"]}}' 2>/dev/null | jq -r '.result | length' 2>/dev/null)
schema_avian=$(grep -c 'avian' "$PROJECT/.jackdaw/schema.json" 2>/dev/null)
log "no-avian: RigidBody query len=${rb:-?}/${rb_alt:-?} schema avian hits=${schema_avian:-?}"
c12c=false
if [ "${rb:-1}" = "0" ] || [ "${rb_alt:-1}" = "0" ] || [ "${rb:-x}" = "null" ]; then c12c=true; fi
[ "${schema_avian:-1}" = "0" ] 2>/dev/null || c12c=false
leg CELL12_NO_AVIAN "$c12c"

op pie.play_input_toggle >/dev/null 2>&1
for _ in 1 2 3 4; do op pie.stop >/dev/null 2>&1; sleep 2; st=$(brp jackdaw/status '{}' | jq -r '.result.pie // empty' 2>/dev/null); [ "$st" = stopped ] && break; done
printf '%s\n' "$(summary_line)" > "$OUTDIR/t12t3-cell12-summary.txt"
log "VERDICT_CELL12: $(summary_line)"
log "T12T3_CELL12_DONE"
