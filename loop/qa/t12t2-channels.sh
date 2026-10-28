#!/bin/bash
# T12-T2 resolution + four-channel legs (macOS, bash+curl+jq).
#   RES_A / RES_B: two PIE sessions at different editor window sizes; the
#     game's virtual window reports the landed stream size, and the start
#     overlay fills it while the bar stays 180x10 at both — the live half of
#     the T1 headless four-resolution assertion. A window screenshot is
#     archived per size for the pixel record.
#   DIRECT: the warm game runs in its own window (BRP 15702); the four
#     screens and the bar are driven through their data face and assert the
#     same behavior PIE showed (the click channel is PIE's: a windowed direct
#     run on macOS has no input-injection equivalent — T11 precedent).
#   EXPORT: `game.export` stages a release build into .jackdaw/dist/release/;
#     the staged exe asserts the same parity set.
# Usage: bash loop/qa/t12t2-channels.sh [project] [editorPort]
set -u
PROJECT="${1:-/Users/zhanglinbo/workspace/loop-mac/t12t1-game/t12t1-game}"
PORT="${2:-15903}"
GAME_PORT=15702
REPO=/Users/zhanglinbo/workspace/jackdaw
OUTDIR="$REPO/loop/t12t2-live"
CONSOLE_LOG="$OUTDIR/t12t2-channels-console.log"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
NKEY='bevy_core::name::Name'
TKEY='bevy_transform::components::transform::Transform'
mkdir -p "$OUTDIR"
: > "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t12t2-ch-results.XXXXXX)"
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
  sleep 1
  pkill -x jackdaw 2>/dev/null
  pkill -f 't12t1-game$' 2>/dev/null
}
trap cleanup EXIT

brp() {
  local port="$1" method="$2" params="${3:-}" id=$RANDOM body
  if [ -n "$params" ]; then
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params")
  else
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s"}' "$id" "$method")
  fi
  curl -s -m 30 -X POST "http://127.0.0.1:$port/" -H 'Content-Type: application/json' -d "$body"
}
gbrp() { brp "$GAME_PORT" "$@"; }
op() {
  local id="$1" params="${2:-}"
  if [ -n "$params" ]; then brp "$PORT" jackdaw/call_operator "{\"id\":\"$id\",\"params\":$params}"
  else brp "$PORT" jackdaw/call_operator "{\"id\":\"$id\"}"; fi
}
wait_idle() {
  local deadline=$((SECONDS + ${1:-300}))
  while [ $SECONDS -lt $deadline ]; do
    if brp "$PORT" jackdaw/wait '{"until":"idle"}' | jq -e '.result.idle == true' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}
dismiss_dialog() {
  local st
  st=$(brp "$PORT" jackdaw/status '{}' 2>/dev/null | jq -r '.result.dialog // empty' 2>/dev/null)
  if [ -n "$st" ] && [ "$st" != "null" ]; then
    op dialog.answer '{"choice":"0"}' >/dev/null 2>&1
    sleep 2
  fi
}
game_up() { gbrp jackdaw/app_info '{}' 2>/dev/null | jq -e '.result.app_name' >/dev/null 2>&1; }
editor_boot() { # editor_boot <window size>
  pkill -x jackdaw 2>/dev/null; pkill -f 't12t1-game$' 2>/dev/null
  sleep 1
  JACKDAW_OPEN_PROJECT="$PROJECT" JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE="$1" \
    nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw \
    > "$OUTDIR/t12t2-channels-editor-$1.log" 2>&1 &
  local ok=""
  for i in $(seq 1 150); do
    sleep 2
    if brp "$PORT" jackdaw/status '{}' >/dev/null 2>&1; then ok=1; break; fi
    pgrep -x jackdaw >/dev/null || break
  done
  [ -n "$ok" ] || { log "EDITOR_BOOT_FAIL($1)"; return 1; }
  wait_idle 600 >/dev/null; sleep 3
  dismiss_dialog
  return 0
}
boot_pie() {
  op scene.open "{\"path\":\"$PROJECT/assets/scene.bsn\"}" >/dev/null 2>&1
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
  return 0
}
stop_pie() {
  for _ in 1 2 3; do
    op pie.stop >/dev/null 2>&1
    sleep 2
    local st
    st=$(brp "$PORT" jackdaw/status '{}' | jq -r '.result.pie // empty' 2>/dev/null)
    [ "$st" = stopped ] && break
  done
  pkill -f 't12t1-game$' 2>/dev/null
  sleep 1
}
# Resolution parity probe: the virtual window's size and three named nodes'
# computed boxes. A layout that holds prints the overlay at the window size
# and the bar at 180x10 in both.
resolution_probe() { # resolution_probe <label>
  local label="$1" win overlay bar button
  win=$(gbrp world.query '{"data":{"components":["bevy_window::window::Window"]}}' 2>/dev/null \
    | jq -r '.result[0].components["bevy_window::window::Window"].resolution
             | if type == "object" then "\(.physical_width // .width) x\(.physical_height // .height)" else tostring end' 2>/dev/null)
  read -r OWX OWY <<< "$(gbrp world.query "{\"data\":{\"components\":[\"$NKEY\",\"bevy_ui::ui_node::ComputedNode\"]}}" 2>/dev/null \
    | jq -r --arg t "bevy_ui::ui_node::ComputedNode" \
      '[.result[] | select(.components["bevy_core::name::Name"] == "StartScreen") | .components[$t].size] | first | if . then "\(.[0]) \(.[1])" else empty end' 2>/dev/null)"
  read -r BWX BWY <<< "$(gbrp world.query "{\"data\":{\"components\":[\"$NKEY\",\"bevy_ui::ui_node::ComputedNode\"]}}" 2>/dev/null \
    | jq -r --arg t "bevy_ui::ui_node::ComputedNode" \
      '[.result[] | select(.components["bevy_core::name::Name"] == "HealthBar") | .components[$t].size] | first | if . then "\(.[0]) \(.[1])" else empty end' 2>/dev/null)"
  read -r UBX UBY <<< "$(gbrp world.query "{\"data\":{\"components\":[\"$NKEY\",\"bevy_ui::ui_node::ComputedNode\"]}}" 2>/dev/null \
    | jq -r --arg t "bevy_ui::ui_node::ComputedNode" \
      '[.result[] | select(.components["bevy_core::name::Name"] == "StartButton") | .components[$t].size] | first | if . then "\(.[0]) \(.[1])" else empty end' 2>/dev/null)"
  log "$label: window=$win StartScreen=${OWX}x${OWY} HealthBar=${BWX}x${BWY} StartButton=${UBX}x${UBY}"
  echo "$win|$OWX|$OWY|$BWX|$BWY|$UBX|$UBY"
}

# ---- resolution leg A (1600x900 editor) --------------------------------------
if editor_boot 1600x900 && boot_pie; then
  read -r WIN OX OY BX BY UX UY <<< "$(resolution_probe A)"
  op pie.play_input_toggle >/dev/null 2>&1
  sleep 2
  brp "$PORT" jackdaw/screenshot '{"kind":"window","path":"t12t2-res-a.png"}' >/dev/null 2>&1
  sleep 2
  brp "$PORT" jackdaw/screenshot '{"kind":"window","path":"t12t2-res-a.png"}' >/dev/null 2>&1
  sleep 2
  res_a=false
  # The overlay fills the landed stream; the bar keeps its authored 180x10.
  if [ -n "$OX" ] && [ -n "$BX" ]; then
    wx="${WIN%% x*}"; wy="${WIN##*x}"
    res_a=$(python3 -c "
import sys
win = ('$WIN'.replace(' x','x').split('x'))
try:
    wx, wy = float(win[0]), float(win[1])
except Exception:
    sys.exit(1)
ox, oy, bx, by, ux, uy = $OX, $OY, $BX, $BY, float($UX or 0), float($UY or 0)
ok_overlay = abs(ox - wx) < 2 and abs(oy - wy) < 2
ok_bar = abs(bx - 180.0) < 1 and abs(by - 10.0) < 1
ok_button = ux > 40 and uy > 20
sys.exit(0 if ok_overlay and ok_bar and ok_button else 1)" 2>/dev/null && echo true || echo false)
  fi
  leg RES_A_1600x900 "$res_a"
  stop_pie
else
  leg RES_A_1600x900 false
fi

# ---- resolution leg B (1920x1080 editor) --------------------------------------
if editor_boot 1920x1080 && boot_pie; then
  read -r WIN OX OY BX BY UX UY <<< "$(resolution_probe B)"
  op pie.play_input_toggle >/dev/null 2>&1
  sleep 2
  brp "$PORT" jackdaw/screenshot '{"kind":"window","path":"t12t2-res-b.png"}' >/dev/null 2>&1
  sleep 2
  brp "$PORT" jackdaw/screenshot '{"kind":"window","path":"t12t2-res-b.png"}' >/dev/null 2>&1
  sleep 2
  res_b=false
  if [ -n "$OX" ] && [ -n "$BX" ]; then
    res_b=$(python3 -c "
import sys
win = ('$WIN'.replace(' x','x').split('x'))
try:
    wx, wy = float(win[0]), float(win[1])
except Exception:
    sys.exit(1)
ox, oy, bx, by, ux, uy = $OX, $OY, $BX, $BY, float($UX or 0), float($UY or 0)
ok_overlay = abs(ox - wx) < 2 and abs(oy - wy) < 2
ok_bar = abs(bx - 180.0) < 1 and abs(by - 10.0) < 1
ok_button = ux > 40 and uy > 20
sys.exit(0 if ok_overlay and ok_bar and ok_button else 1)" 2>/dev/null && echo true || echo false)
  fi
  leg RES_B_1920x1080 "$res_b"
  stop_pie
else
  leg RES_B_1920x1080 false
fi
pkill -x jackdaw 2>/dev/null
sleep 1

# ---- the parity set, run against whatever game owns 15702 ----------------------
parity() { # parity <label> — four screens + bar over the data face
  local label="$1"
  local pass=true
  local st vis_hud vis_start vis_pause vis_go pv
  # Boot state: the menu is up.
  st=$(gbrp world.get_resources '{"resource":"t12t1_game::GameState"}' 2>/dev/null | jq -r '.result.value | "\(.menu),\(.paused),\(.game_over)"' 2>/dev/null)
  [ "$st" = "true,false,false" ] || pass=false
  log "$label boot state=$st"
  # menu=false: the hud shows, the start screen hides.
  gbrp world.insert_resources '{"resource":"t12t1_game::GameState","value":{"menu":false,"paused":false,"game_over":false}}' >/dev/null 2>&1
  sleep 1.5
  vis_hud=$(gbrp world.query '{"data":{"components":["bevy_camera::visibility::Visibility","jackdaw_bind::types::Bindings"]}}' 2>/dev/null | jq -r '[.result[] | (.components["jackdaw_bind::types::Bindings"] | tostring) as $b | select(($b | contains("GameState).menu")) and ($b | contains("not")) and (($b | contains("PickupCount")) | not)) | .components["bevy_camera::visibility::Visibility"]] | first // empty' 2>/dev/null)
  vis_start=$(gbrp world.query '{"data":{"components":["bevy_camera::visibility::Visibility","jackdaw_bind::types::Bindings"]}}' 2>/dev/null | jq -r '[.result[] | (.components["jackdaw_bind::types::Bindings"] | tostring) as $b | select(($b | contains("GameState).menu")) and (($b | contains("not")) | not) and (($b | contains("PickupCount")) | not)) | .components["bevy_camera::visibility::Visibility"]] | first // empty' 2>/dev/null)
  [ "$vis_hud" = "Visible" ] && [ "$vis_start" = "Hidden" ] || pass=false
  log "$label menu=false: Hud=$vis_hud StartScreen=$vis_start"
  # Health 60: the bar binds it. (Name is not BRP-serializable in this
  # fork; the bar is the only Progress entity, so no name is needed.)
  gbrp world.insert_resources '{"resource":"t12t1_game::GameState","value":{"menu":false,"paused":false,"game_over":false}}' >/dev/null 2>&1
  local pent
  pent=$(gbrp world.query '{"data":{"components":["t12t1_game::PlayerHealth"]}}' 2>/dev/null | jq -r '.result[0].entity // empty' 2>/dev/null)
  gbrp world.insert_components "{\"entity\":\"$pent\",\"components\":{\"t12t1_game::PlayerHealth\":{\"current\":60.0,\"max\":100.0}}}" >/dev/null 2>&1
  sleep 1.5
  pv=$(gbrp world.query '{"data":{"components":["jackdaw_widgets_runtime::Progress"]}}' 2>/dev/null | jq -r '[.result[] | .components["jackdaw_widgets_runtime::Progress"].value] | first // empty' 2>/dev/null)
  python3 -c "import sys; sys.exit(0 if abs(${pv:-9} - 0.6) < 0.01 else 1)" 2>/dev/null || pass=false
  log "$label health 60 -> Progress.value=$pv (expect 0.6)"
  # paused: the pause screen.
  gbrp world.insert_resources '{"resource":"t12t1_game::GameState","value":{"menu":false,"paused":true,"game_over":false}}' >/dev/null 2>&1
  sleep 1.5
  vis_pause=$(gbrp world.query '{"data":{"components":["bevy_camera::visibility::Visibility","jackdaw_bind::types::Bindings"]}}' 2>/dev/null | jq -r '[.result[] | (.components["jackdaw_bind::types::Bindings"] | tostring) as $b | select($b | contains("GameState).paused")) | .components["bevy_camera::visibility::Visibility"]] | first // empty' 2>/dev/null)
  [ "$vis_pause" = "Visible" ] || pass=false
  log "$label paused: PauseScreen=$vis_pause"
  # game over: the end screen.
  gbrp world.insert_resources '{"resource":"t12t1_game::GameState","value":{"menu":false,"paused":false,"game_over":true}}' >/dev/null 2>&1
  sleep 1.5
  vis_go=$(gbrp world.query '{"data":{"components":["bevy_camera::visibility::Visibility","jackdaw_bind::types::Bindings"]}}' 2>/dev/null | jq -r '[.result[] | (.components["jackdaw_bind::types::Bindings"] | tostring) as $b | select($b | contains("GameState).game_over")) | .components["bevy_camera::visibility::Visibility"]] | first // empty' 2>/dev/null)
  [ "$vis_go" = "Visible" ] || pass=false
  log "$label game_over: GameOverScreen=$vis_go"
  leg "PARITY_$label" "$pass"
}

# ---- direct run (windowed, debug, BRP 15702) -----------------------------------
pkill -f 't12t1-game$' 2>/dev/null
sleep 1
(cd "$PROJECT" && nohup ./target/debug/t12t1-game >> "$OUTDIR/t12t2-direct-game.log" 2>&1 &)
deadline=$((SECONDS + 120))
while [ $SECONDS -lt $deadline ]; do
  game_up && break
  pgrep -f 't12t1-game$' >/dev/null || break
  sleep 1
done
if game_up; then
  sleep 3
  parity DIRECT
else
  log "DIRECT_BOOT_FAIL"
  leg PARITY_DIRECT false
fi
pkill -f 't12t1-game$' 2>/dev/null
sleep 2

# ---- export: release build staged into .jackdaw/dist/release --------------------
if editor_boot 1600x900; then
  log "export build starting (release; several minutes)"
  op game.export >/dev/null 2>&1
  deadline=$((SECONDS + 1800))
  while [ $SECONDS -lt $deadline ]; do
    [ -x "$PROJECT/.jackdaw/dist/release/t12t1-game" ] && break
    sleep 5
  done
  sleep 5
  pkill -x jackdaw 2>/dev/null
  sleep 2
  if [ -x "$PROJECT/.jackdaw/dist/release/t12t1-game" ]; then
    ls -la "$PROJECT/.jackdaw/dist/release/" | tee -a "$CONSOLE_LOG"
    (cd "$PROJECT/.jackdaw/dist/release" && nohup ./t12t1-game >> "$OUTDIR/t12t2-export-game.log" 2>&1 &)
    deadline=$((SECONDS + 120))
    while [ $SECONDS -lt $deadline ]; do
      game_up && break
      sleep 1
      pgrep -f 'dist/release/t12t1-game' >/dev/null || break
    done
    if game_up; then
      sleep 3
      parity EXPORT
    else
      log "EXPORT_BOOT_FAIL"
      leg PARITY_EXPORT false
    fi
  else
    log "EXPORT_STAGING_MISSING"
    leg PARITY_EXPORT false
  fi
else
  leg PARITY_EXPORT false
fi
pkill -f 't12t1-game$' 2>/dev/null
pkill -x jackdaw 2>/dev/null

printf '%s\n' "$(summary_line)" > "$OUTDIR/t12t2-channels-summary.txt"
log "VERDICT_CHANNELS: $(summary_line)"
log "T12T2_CHANNELS_DONE"
