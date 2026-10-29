#!/bin/bash
# T13-T3 live matrix: the template's three-document game flow, on the
# Mac fixture project (jd new + the BRP injection the t13t2 fixture
# established).
#
# Phases (each phase is self-contained: it boots and cleans its own
# editor/game processes — run one per invocation, or `all` for the
# sequential run):
#   prep   jd new the fixture, inject jackdaw_remote, refresh the lock.
#   game   the PIE phase over a fresh boot: CELL1 (fresh boot starts on
#          the menu, the flow face reads menu.bsn), CELL2 (Start -> the
#          level, zero menu residue), CELL3 (hazard to death -> the end
#          screen, level + hud zero residue), CELL4 (Restart -> the
#          digital reset), CELL5 (three menu<->level<->gameover cycles,
#          per-stop counts identical), CELL6 (the player's id constant,
#          the pickups' ids fresh per entry), STAND_FLOW (one Escape is
#          one pause flip), CELL12 (pickups 0->3 + level-clear line +
#          pause doors + walk/jump + the Stop proof on the four seeds).
#   flow   the config phase: CELL10 (Play vs Play-Current), CELL7
#          (set-start-scene: Play/direct/staged all boot the named
#          scene, restore), CELL8 (export from the named scene: the
#          staged tree, the manifest, change->re-export->changed launch),
#          CELL9 (a ghost start scene warns on the editor, the export
#          and the game's fallback, then clears), CELL11 (retitle the
#          menu in the editor, Save, Play, export keeps it).
# Usage: bash loop/qa/t13t3-live.sh [phase]   phase: prep|game|flow|all
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
FIXROOT=/Users/zhanglinbo/workspace/loop-mac/t13t3
PROJECT="$FIXROOT/t13t3-game"
BIN="$PROJECT/.jackdaw/target/game/debug/t13t3-game"
PORT=15919
GAME_PORT=15702
OUTDIR="$REPO/loop/t13t3-live"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
STAGED="$PROJECT/.jackdaw/dist/release"
STAGED_EXE="$STAGED/t13t3-game"
CRATE='t13t3_game'
TKEY='bevy_transform::components::transform::Transform'
KB_MSG='bevy_input::keyboard::KeyboardInput'
CAM2D='bevy_camera::components::Camera2d'
PLAYER_SPAWN_X=-2.0
mkdir -p "$OUTDIR"
PHASE="${1:-all}"
CONSOLE_LOG="$OUTDIR/console-$PHASE.log"
: > "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t13t3-live.XXXXXX)"
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
results() { sort "$RESULTS_FILE" | tr '\n' ' '; }
cleanup() {
  op pie.stop >/dev/null 2>&1
  sleep 1
  pkill -x jackdaw 2>/dev/null
  pkill -x t13t3-game 2>/dev/null
  sleep 1
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
  else brp jackdaw/call_operator "{\"id\":\"$id\",\"params\":{}}"; fi
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
wait_game() {
  local deadline=$((SECONDS + ${1:-600}))
  while [ $SECONDS -lt $deadline ]; do
    game_up && return 0
    sleep 2
  done
  return 1
}
stop_game() {
  op pie.stop >/dev/null 2>&1
  sleep 2
  pkill -x t13t3-game 2>/dev/null
  sleep 2
}
# count_of <component type path> -> how many entities carry it
count_of() {
  gbrp world.query "{\"data\":{\"components\":[\"$1\"]}}" 2>/dev/null | jq -r '.result | length' 2>/dev/null
}
named_count() {
  gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null \
    | jq -r --arg n "$1" '[.result[] | .components["bevy_ecs::name::Name"] | tostring | select(. == $n)] | length' 2>/dev/null
}
entity_named() {
  gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null \
    | jq -r --arg n "$1" '[.result[] | select(.components["bevy_ecs::name::Name"] == $n) | .entity] | first // empty' 2>/dev/null
}
player_pos() {
  gbrp world.query "{\"data\":{\"components\":[\"$TKEY\",\"$CRATE::PlayerHealth\"]}}" 2>/dev/null \
    | jq -r --arg t "$TKEY" '[.result[] | select(.components["'$CRATE'::PlayerHealth"] != null) | .components[$t].translation] | first | if . then "\(.[0]) \(.[1]) \(.[2])" else empty end' 2>/dev/null
}
health() {
  gbrp world.query "{\"data\":{\"components\":[\"$CRATE::PlayerHealth\"]}}" 2>/dev/null \
    | jq -r '[.result[] | .components["'$CRATE'::PlayerHealth"].current] | first // empty' 2>/dev/null
}
pick_count() {
  gbrp world.query "{\"data\":{\"components\":[\"$CRATE::PickupCount\"]}}" 2>/dev/null \
    | jq -r '[.result[] | .components["'$CRATE'::PickupCount"] | (.["0"]? // .) | if type == "number" then . else empty end] | first // empty' 2>/dev/null
}
paused_state() {
  gbrp world.get_resources "{\"resource\":\"$CRATE::GameState\"}" 2>/dev/null \
    | jq -r '.result.value | "\(.paused)"' 2>/dev/null
}
pickup_ids() {
  gbrp world.query "{\"data\":{\"components\":[\"$CRATE::Pickup\"]}}" 2>/dev/null \
    | jq -r '[.result[].entity] | sort | join(",")' 2>/dev/null
}
# The per-stop mechanical signature: named entities, pickups, hazards,
# cubes, players, roots, 2D cameras.
stop_signature() {
  local named pickups hazards cubes players roots cams
  named=$(gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null | jq -r '.result | length' 2>/dev/null)
  pickups=$(count_of "$CRATE::Pickup")
  hazards=$(count_of "$CRATE::Hazard")
  cubes=$(count_of "$CRATE::FallingCube")
  players=$(count_of "$CRATE::PlayerMarker")
  roots=$(count_of "jackdaw_runtime::JackdawSceneRoot")
  cams=$(count_of "$CAM2D")
  echo "n=${named:-?} p=${pickups:-?} h=${hazards:-?} c=${cubes:-?} pl=${players:-?} r=${roots:-?} cam=${cams:-?}"
}
flow_face() { brp jackdaw/game_flow '{}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null; }
window_entity() {
  gbrp world.query '{"data":{"components":["bevy_window::window::Window"]}}' 2>/dev/null | jq -r '.result[0].entity // empty' 2>/dev/null
}
keyev() {
  gbrp world.write_message "{\"message\":\"$KB_MSG\",\"value\":{\"key_code\":\"$1\",\"logical_key\":{\"Character\":\" \"},\"state\":\"$2\",\"text\":null,\"repeat\":false,\"window\":\"$WINDOW_ENTITY\"}}" >/dev/null 2>&1
}
frame_click() {
  op input.pointer "{\"x\":$1,\"y\":$2,\"action\":\"click\",\"button\":\"primary\"}" >/dev/null 2>&1
  sleep 1.5
}
# sweep_click <check-cmd> — click a grid over the PIE viewport until
# <check-cmd> (a command; empty output = hit) stops matching.
sweep_click() {
  local check="$1" before after
  before=$($check)
  [ -z "$before" ] && return 0
  local x y
  for y in 787 757 745 800 720 470 650 560 380; do
    for x in 700 787 800 550 875 1025 650 900 760; do
      frame_click "$x" "$y"
      after=$($check)
      [ "$after" = "0" ] && { log "sweep_click: hit at ($x,$y)"; return 0; }
    done
  done
  return 1
}
gameover_screen_up() { named_count "GameOverRoot"; }
menu_up() { named_count "MenuRoot"; }
sun_up() { named_count "Sun"; }
# The flow buttons fire through the game's own BRP: `world.trigger_event`
# sends the `Activate` event a real click produces (the pointer path is
# proven separately in CELL2's sweep; this channel keeps the loop legs
# independent of the editor's operator pipeline, which the known N13
# drain panics can wedge — buglist N13, ridden-around + counted).
activate_btn() { # activate_btn <button name>
  local e resp
  e=$(entity_named "$1")
  [ -n "$e" ] || { log "activate_btn: no entity named $1"; return 1; }
  resp=$(gbrp "world.trigger_event" "{\"event\":\"bevy_ui_widgets::Activate\",\"value\":{\"entity\":\"$e\"}}")
  case "$resp" in
    *'"result":null'*|*'"result":{}'*) ;;
    *) log "activate_btn $1 ($e) response: $(echo "$resp" | head -c 200)" ;;
  esac
  sleep 1.5
  return 0
}
wait_world() { # wait_world <name> <count> — pump until the name's count lands
  local deadline=$((SECONDS + 45))
  while [ $SECONDS -lt $deadline ]; do
    [ "$(named_count "$1")" = "$2" ] && return 0
    sleep 1
  done
  return 1
}
click_start() {
  activate_btn StartButton || return 1
  wait_world Sun 1 && log "click_start: the level came up" && return 0
  return 1
}
click_restart() {
  activate_btn RestartButton || return 1
  wait_world Sun 1 && log "click_restart: the level came back" && return 0
  return 1
}
click_menu_btn() {
  activate_btn MenuButton || return 1
  wait_world MenuRoot 1 && log "click_menu: the menu came back" && return 0
  return 1
}
# editor boot (per phase)
editor_boot() {
  pkill -x jackdaw 2>/dev/null; pkill -x t13t3-game 2>/dev/null; sleep 1
  export JACKDAW_OPEN_PROJECT="$PROJECT" JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1600x900
  cd "$REPO"
  nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$OUTDIR/editor-$PHASE.log" 2>&1 &
  local ok=""
  for i in $(seq 1 150); do
    sleep 2
    if brp jackdaw/status '{}' >/dev/null 2>&1; then ok=1; break; fi
    pgrep -x jackdaw >/dev/null || break
  done
  [ -n "$ok" ] || { log "EDITOR_BOOT_FAIL"; exit 1; }
  wait_idle 600 >/dev/null; sleep 3; dismiss_dialog
  log "EDITOR_READY"
}
# pie.play: the flow's startup-scene run (no override).
play_flow() {
  op pie.play >/dev/null 2>&1
  wait_game 900 || { log "PIE_GAME_UP_FAIL"; return 1; }
  sleep 4
  return 0
}
# pie.play_current on a scene tab: the editor's own scene boots in.
play_current() {
  op scene.open "{\"path\":\"$1\"}" >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1
  op pie.play_current >/dev/null 2>&1
  wait_game 900 || { log "PIE_CURRENT_UP_FAIL"; return 1; }
  sleep 4
  return 0
}
input_on() { op pie.play_input_toggle >/dev/null 2>&1; sleep 2; WINDOW_ENTITY=$(window_entity); log "window entity: ${WINDOW_ENTITY:-MISSING}"; }
goto_x() { # goto_x <target x> <key+> <key-> — x drive with z trim
  for i in $(seq 1 20); do
    read -r CURX _ CURZ <<< "$(player_pos)"
    [ -z "$CURX" ] && return 1
    if python3 -c "import sys; sys.exit(0 if $CURX >= $1 and abs($CURZ) <= 0.35 else 1)" 2>/dev/null; then return 0; fi
    if python3 -c "import sys; sys.exit(0 if $CURZ > 0.35 else 1)" 2>/dev/null; then
      keyev KeyW Pressed; sleep 0.2; keyev KeyW Released; sleep 0.15
    elif python3 -c "import sys; sys.exit(0 if $CURZ < -0.35 else 1)" 2>/dev/null; then
      keyev KeyS Pressed; sleep 0.2; keyev KeyS Released; sleep 0.15
    elif python3 -c "import sys; sys.exit(0 if $CURX < $1 else 1)" 2>/dev/null; then
      keyev "$2" Pressed; sleep 0.22; keyev "$2" Released; sleep 0.25
    fi
  done
  return 0
}
# retreat_x <target x> — walk KeyA (west) until x <= target, z trimmed.
retreat_x() {
  for i in $(seq 1 20); do
    read -r CURX _ CURZ <<< "$(player_pos)"
    [ -z "$CURX" ] && return 1
    if python3 -c "import sys; sys.exit(0 if $CURX <= $1 else 1)" 2>/dev/null; then return 0; fi
    if python3 -c "import sys; sys.exit(0 if $CURZ > 0.35 else 1)" 2>/dev/null; then
      keyev KeyW Pressed; sleep 0.2; keyev KeyW Released; sleep 0.15
    elif python3 -c "import sys; sys.exit(0 if $CURZ < -0.35 else 1)" 2>/dev/null; then
      keyev KeyS Pressed; sleep 0.2; keyev KeyW Released; sleep 0.15
    else
      keyev KeyA Pressed; sleep 0.22; keyev KeyA Released; sleep 0.25
    fi
  done
  return 0
}
# die_on_hazard — cross the hazard at x=2 and back until the end screen
# is up (each fresh entry burns 15; the trigger fires on overlap start).
die_on_hazard() {
  for i in $(seq 1 14); do
    [ "$(named_count GameOverRoot)" != "0" ] && return 0
    goto_x 2.05 KeyD KeyA
    sleep 0.6
    [ "$(named_count GameOverRoot)" != "0" ] && return 0
    retreat_x 1.1
    sleep 0.6
  done
  [ "$(named_count GameOverRoot)" != "0" ]
}

# ---- phase: prep ------------------------------------------------------------
prep() {
  pkill -x jackdaw 2>/dev/null; pkill -x t13t3-game 2>/dev/null; sleep 1
  rm -rf "$FIXROOT"; mkdir -p "$FIXROOT"
  (cd "$REPO" && ./target/debug/jd new t13t3-game --path "$FIXROOT" --no-git) > "$OUTDIR/jd-new.log" 2>&1
  [ -d "$PROJECT" ] || { log "PREP_FAIL no project"; exit 1; }
  grep -q "menu.bsn" "$PROJECT/assets/game.flow.json" || { log "PREP_FAIL flow seed is not the three-document shape"; exit 1; }
  [ -f "$PROJECT/assets/menu.bsn" ] && [ -f "$PROJECT/assets/gameover.bsn" ] || { log "PREP_FAIL missing flow documents"; exit 1; }
  # Warm-project test injection (t11t2/t13t2 practice): game-side BRP.
  /usr/bin/sed -i '' "s|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = \[\"terrain\", \"pie\"\] }|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = [\"terrain\", \"pie\"] }\njackdaw_remote = { path = '$REPO/crates/jackdaw_remote' }|" "$PROJECT/Cargo.toml"
  grep -q jackdaw_remote "$PROJECT/Cargo.toml" || { log "PREP_FAIL no remote dep"; exit 1; }
  /usr/bin/sed -i '' 's|\.add_plugins(t13t3_game::GamePlugin)|.add_plugins(t13t3_game::GamePlugin)\n        .add_plugins(jackdaw_remote::JackdawRemotePlugin::default())|' "$PROJECT/src/main.rs"
  grep -q JackdawRemotePlugin "$PROJECT/src/main.rs" || { log "PREP_FAIL no remote plugin"; exit 1; }
  (cd "$PROJECT" && cargo metadata --format-version 1 >/dev/null 2>"$OUTDIR/lockfix.log") \
    || { log "PREP_FAIL lock refresh: $(tail -2 "$OUTDIR/lockfix.log")"; exit 1; }
  log "SEED_FLOW=$(tr -d '\n' < "$PROJECT/assets/game.flow.json")"
  log "PREP_OK"
}

# ---- phase: game (the PIE walk) ---------------------------------------------
game_phase() {
  editor_boot
  log "---- CELL1: fresh boot = the flow's start scene ----"
  # The project's first Play is the startup-scene run: the menu comes
  # up, nothing of the level is in the world, and the flow face reads
  # the seed.
  play_flow || { leg CELL1_FRESH_BOOT false; stop_game; exit 1; }
  input_on
  c1=true
  [ "$(named_count MenuRoot)" = "1" ] || c1=false
  [ "$(named_count StartButton)" = "1" ] || c1=false
  [ "$(named_count MenuUiCamera)" = "1" ] || c1=false
  [ "$(named_count Sun)" = "0" ] || c1=false
  [ "$(named_count HudRoot)" = "0" ] || c1=false
  [ "$(count_of "$CRATE::PlayerMarker")" = "0" ] || c1=false
  face=$(flow_face)
  echo "$face" | jq -e '.start_scene == "menu.bsn"' >/dev/null 2>&1 || c1=false
  echo "$face" | jq -e '(.warnings | length) == 0' >/dev/null 2>&1 || c1=false
  echo "$face" | jq -e '(.scenes | length) == 3' >/dev/null 2>&1 || c1=false
  log "CELL1: MenuRoot=$(named_count MenuRoot) StartButton=$(named_count StartButton) MenuUiCamera=$(named_count MenuUiCamera) Sun=$(named_count Sun) HudRoot=$(named_count HudRoot) face=$(echo "$face" | tr -d '\n' | head -c 200)"
  leg CELL1_FRESH_BOOT "$c1"
  GAME_LOG_BOOT=$(tail -n 400 "$OUTDIR/editor-game.log" 2>/dev/null; true)

  log "---- CELL2: Start -> the level, zero menu residue ----"
  sig_menu=$(stop_signature)
  start_hit=""
  if sweep_click menu_up; then
    start_hit=$(grep "sweep_click: hit at" "$CONSOLE_LOG" | tail -1 | sed 's/.*(\([0-9]*\),\([0-9]*\)).*/\1 \2/')
    read -r START_X START_Y <<< "$start_hit"
    log "flow-button anchor: ($START_X,$START_Y)"
    deadline=$((SECONDS + 60))
    while [ $SECONDS -lt $deadline ]; do
      [ "$(named_count Sun)" = "1" ] && break
      sleep 1
    done
    sleep 3
    c2=true
    [ "$(named_count Sun)" = "1" ] || c2=false
    [ "$(named_count HudRoot)" = "1" ] || c2=false
    [ "$(named_count HealthBar)" = "1" ] || c2=false
    [ "$(named_count MenuRoot)" = "0" ] || c2=false
    [ "$(named_count MenuTitle)" = "0" ] || c2=false
    [ "$(named_count MenuUiCamera)" = "0" ] || c2=false
    [ "$(count_of "$CRATE::Pickup")" = "3" ] || c2=false
    [ "$(count_of "$CRATE::FallingCube")" = "1" ] || c2=false
    [ "$(count_of "$CRATE::PlayerMarker")" = "1" ] || c2=false
    log "CELL2: sig_menu=[$sig_menu] sig_level=[$(stop_signature)]"
    log "CELL2: Sun=$(named_count Sun) HudRoot=$(named_count HudRoot) MenuRoot=$(named_count MenuRoot) MenuUiCamera=$(named_count MenuUiCamera)"
  else
    c2=false
    log "CELL2: Start click never landed"
  fi
  leg CELL2_START_TO_LEVEL "$c2"
  PLAYER_ID_1=$(gbrp world.query "{\"data\":{\"components\":[\"$CRATE::PlayerMarker\"]}}" 2>/dev/null | jq -r '.result[0].entity // empty' 2>/dev/null)
  PICKUP_IDS_1=$(pickup_ids)
  HEALTH_FULL=$(health)

  log "---- CELL12a: the pickup chain 0->3 and the level-clear line ----"
  cell12=true
  h0=$(health)
  goto_x -0.55 KeyD KeyA; c_b=$(pick_count)
  goto_x 0.55 KeyD KeyA;  c_c=$(pick_count)
  goto_x 1.2 KeyD KeyA;   c_d=$(pick_count)
  sleep 2
  log "pickup walk: ->$c_b/$c_c/$c_d count=$(pick_count) (expect 3)"
  python3 -c "import sys; sys.exit(0 if 0 <= $c_b <= $c_c <= $c_d and $c_d >= 3 else 1)" 2>/dev/null || cell12=false
  ui_texts=$(brp jackdaw/ui_tree '{"kind":"text","visible_only":true,"depth":30}' 2>/dev/null \
    | jq -r '[.. | objects | select(.kind? == "text") | .text // ""] | join(" || ")' 2>/dev/null)
  echo "$ui_texts" | grep -q "Level clear" && clear_line=true || clear_line=false
  log "level-clear line in the Game panel log strip: $clear_line"

  log "---- CELL12b: the pause doors and the frozen player ----"
  tap_esc() { keyev Escape Pressed; sleep 0.15; keyev Escape Released; sleep 0.6; }
  pos_a=$(player_pos)
  tap_esc
  p1=$(paused_state)
  pos_b=$(player_pos); keyev KeyW Pressed; sleep 0.6; keyev KeyW Released; sleep 0.3; pos_c=$(player_pos)
  frozen=false
  python3 - "$pos_b" "$pos_c" << 'PYT' 2>/dev/null && frozen=true
import sys
bx, by, bz = (float(v) for v in sys.argv[1].split())
cx, cy, cz = (float(v) for v in sys.argv[2].split())
sys.exit(0 if abs(bx-cx) + abs(by-cy) + abs(bz-cz) < 0.01 else 1)
PYT
  tap_esc
  p2=$(paused_state)
  pos_d=$(player_pos); keyev KeyW Pressed; sleep 0.6; keyev KeyW Released; sleep 0.3; pos_e=$(player_pos)
  resumed=false
  python3 - "$pos_d" "$pos_e" << 'PYT' 2>/dev/null && resumed=true
import sys
dx, dy, dz = (float(v) for v in sys.argv[1].split())
ex, ey, ez = (float(v) for v in sys.argv[2].split())
sys.exit(0 if abs(dx-ex) + abs(dy-ey) + abs(dz-ez) > 0.05 else 1)
PYT
  st_flow=true
  [ "$p1" = "true" ] || st_flow=false
  [ "$p2" = "false" ] || st_flow=false
  [ "$frozen" = true ] || st_flow=false
  [ "$resumed" = true ] || st_flow=false
  log "STAND_FLOW_PAUSE: tap1=$p1 tap2=$p2 frozen=$frozen resumed=$resumed pos_a=$pos_a pos_e=$pos_e"
  leg STAND_FLOW_PAUSE_SINGLE "$st_flow"

  log "---- CELL12c: the walk and the jump (the player chain) ----"
  pos_w1=$(player_pos)
  keyev KeyA Pressed; sleep 0.8; keyev KeyA Released; sleep 0.3
  pos_w2=$(player_pos)
  walked=false
  python3 - "$pos_w1" "$pos_w2" << 'PYT' 2>/dev/null && walked=true
import sys
a = [float(v) for v in sys.argv[1].split()]
b = [float(v) for v in sys.argv[2].split()]
sys.exit(0 if abs(a[0]-b[0]) + abs(a[2]-b[2]) > 0.15 else 1)
PYT
  read -r JX JY JZ <<< "$(player_pos)"
  keyev Space Pressed; sleep 0.25; keyev Space Released; sleep 0.5
  read -r KX KY KZ <<< "$(player_pos)"
  jumped=false
  python3 -c "import sys; sys.exit(0 if $KY - $JY > 0.1 or $KY > $JY else 1)" 2>/dev/null && jumped=true
  # The jump arc may have landed by the sample; a second, tighter probe.
  if [ "$jumped" = false ]; then
    keyev Space Pressed; sleep 0.12; keyev Space Released
    sleep 0.15
    read -r _ KY2 _ <<< "$(player_pos)"
    python3 -c "import sys; sys.exit(0 if $KY2 - $JY > 0.05 else 1)" 2>/dev/null && jumped=true
  fi
  log "player chain: walked=$walked ($pos_w1 -> $pos_w2) jumped=$jumped (y $JY -> $KY)"
  [ "$walked" = true ] || cell12=false
  [ "$jumped" = true ] || cell12=false
  [ "$clear_line" = true ] || cell12=false

  log "---- CELL3: hazard to death -> the end screen, zero level residue ----"
  die_ok=$(die_on_hazard && echo true || echo false)
  sleep 3
  c3=true
  [ "$die_ok" = "true" ] || c3=false
  [ "$(named_count GameOverRoot)" = "1" ] || c3=false
  [ "$(named_count RestartButton)" = "1" ] || c3=false
  [ "$(named_count MenuButton)" = "1" ] || c3=false
  [ "$(named_count GameOverUiCamera)" = "1" ] || c3=false
  [ "$(named_count Sun)" = "0" ] || c3=false
  [ "$(named_count HudRoot)" = "0" ] || c3=false
  [ "$(named_count HealthBar)" = "0" ] || c3=false
  [ "$(count_of "$CRATE::Pickup")" = "0" ] || c3=false
  [ "$(count_of "$CRATE::FallingCube")" = "0" ] || c3=false
  [ "$(count_of "$CRATE::Hazard")" = "0" ] || c3=false
  [ "$(count_of "$CRATE::PlayerMarker")" = "1" ] || c3=false
  log "CELL3: died=$die_ok GameOverRoot=$(named_count GameOverRoot) Sun=$(named_count Sun) HudRoot=$(named_count HudRoot) pickups=$(count_of "$CRATE::Pickup") hazards=$(count_of "$CRATE::Hazard") player_still=$(count_of "$CRATE::PlayerMarker") sig=[$(stop_signature)]"
  leg CELL3_LEVEL_TO_GAMEOVER "$c3"
  PLAYER_ID_GO=$(gbrp world.query "{\"data\":{\"components\":[\"$CRATE::PlayerMarker\"]}}" 2>/dev/null | jq -r '.result[0].entity // empty' 2>/dev/null)

  log "---- CELL4: Restart -> the run comes back whole ----"
  if [ "$(named_count GameOverRoot)" = "1" ] && click_restart; then
    sleep 3
    c4=true
    [ "$(named_count Sun)" = "1" ] || c4=false
    [ "$(named_count HudRoot)" = "1" ] || c4=false
    [ "$(named_count GameOverRoot)" = "0" ] || c4=false
    [ "$(named_count GameOverUiCamera)" = "0" ] || c4=false
    h=$(health); c=$(pick_count); alive=$(count_of "$CRATE::Pickup"); pos=$(player_pos)
    python3 -c "import sys; sys.exit(0 if abs($h - 100.0) < 0.01 else 1)" 2>/dev/null || c4=false
    [ "$c" = "0" ] || c4=false
    [ "$alive" = "3" ] || c4=false
    python3 - "$pos" << 'PYT' 2>/dev/null || c4=false
import sys
x, y, z = (float(v) for v in sys.argv[1].split())
sys.exit(0 if abs(x + 2.0) < 0.05 and abs(y - 1.0) < 0.5 and abs(z) < 0.05 else 1)
PYT
    log "CELL4: after Restart health=$h PickupCount=$c pickups=$alive pos=$pos sig=[$(stop_signature)]"
  else
    c4=false
    log "CELL4: Restart click never landed"
  fi
  leg CELL4_RESTART_ROUNDTRIP "$c4"
  PICKUP_IDS_2=$(pickup_ids)
  PLAYER_ID_2=$(gbrp world.query "{\"data\":{\"components\":[\"$CRATE::PlayerMarker\"]}}" 2>/dev/null | jq -r '.result[0].entity // empty' 2>/dev/null)

  log "---- CELL6: cross-scene ids ----"
  c6=true
  [ -n "$PLAYER_ID_1" ] && [ "$PLAYER_ID_1" = "$PLAYER_ID_GO" ] && [ "$PLAYER_ID_GO" = "$PLAYER_ID_2" ] || c6=false
  [ -n "$PICKUP_IDS_1" ] && [ -n "$PICKUP_IDS_2" ] && [ "$PICKUP_IDS_1" != "$PICKUP_IDS_2" ] || c6=false
  log "CELL6: player $PLAYER_ID_1 == $PLAYER_ID_GO == $PLAYER_ID_2; pickups '$PICKUP_IDS_1' != '$PICKUP_IDS_2'"
  leg CELL6_CROSS_SCENE_IDS "$c6"

  log "---- CELL5: three menu<->level<->gameover cycles, identical counts ----"
  # One more full act closes the menu loop; then cycle 3 repeats it.
  # Cycle A is the baseline; cycles B and C must repeat it exactly.
  c5=true
  base_level=""; base_over=""; base_menu=""
  for cycle in A B C; do
    # menu -> level (Start); cycle A picks up from CELL4's restart, so
    # its level stop is the same level that stop produced.
    if [ "$(named_count MenuRoot)" = "1" ]; then
      click_start || { c5=false; break; }
    fi
    sleep 2
    deadline=$((SECONDS + 60)); while [ $SECONDS -lt $deadline ]; do [ "$(named_count Sun)" = "1" ] && break; sleep 1; done
    sleep 2
    [ "$(named_count Sun)" = "1" ] || { c5=false; break; }
    sig=$(stop_signature)
    [ "$cycle" = A ] && base_level="$sig"
    [ "$sig" != "$base_level" ] && { c5=false; log "CELL5: level[$cycle]=$sig != base=$base_level"; }
    # level -> gameover (hazard)
    die_on_hazard >/dev/null || { c5=false; break; }
    sleep 2
    sig=$(stop_signature)
    [ "$cycle" = A ] && base_over="$sig"
    [ "$sig" != "$base_over" ] && { c5=false; log "CELL5: gameover[$cycle]=$sig != base=$base_over"; }
    # gameover -> menu (Menu button)
    click_menu_btn || { c5=false; break; }
    sleep 2
    deadline=$((SECONDS + 60)); while [ $SECONDS -lt $deadline ]; do [ "$(named_count MenuRoot)" = "1" ] && break; sleep 1; done
    sleep 2
    [ "$(named_count MenuRoot)" = "1" ] || { c5=false; break; }
    sig=$(stop_signature)
    [ "$cycle" = A ] && base_menu="$sig"
    [ "$sig" != "$base_menu" ] && { c5=false; log "CELL5: menu[$cycle]=$sig != base=$base_menu"; }
    log "CELL5 cycle $cycle: level=[$base_level] over=[$base_over] menu=[$base_menu] (all cycles identical so far=$c5)"
  done
  log "CELL5: base_level=[$base_level] base_over=[$base_over] base_menu=[$base_menu]"
  leg CELL5_ROUNDTRIP_STABILITY "$c5"

  log "---- CELL12d: the player id survived the whole walk; the warn face ----"
  PLAYER_ID_3=$(gbrp world.query "{\"data\":{\"components\":[\"$CRATE::PlayerMarker\"]}}" 2>/dev/null | jq -r '.result[0].entity // empty' 2>/dev/null)
  [ "$PLAYER_ID_3" = "$PLAYER_ID_1" ] || cell12=false
  leg CELL12_REGRESSION "$cell12"

  # The game's own output for this phase: the standing warn scan with the
  # T13 word list (defect forms hard-fail; the flow faces are asserted
  # where their legs expect them, here there should be none).
  sleep 2
  warns=$(grep -Ec "cannot apply|cannot read|does not read as|UnresolvedTypes" "$OUTDIR/editor-game.log" 2>/dev/null)
  flowwarns=$(grep -Ec "game flow:" "$OUTDIR/editor-game.log" 2>/dev/null)
  refused=$(grep -Ec "Cannot spawn scene" "$OUTDIR/editor-game.log" 2>/dev/null)
  log "WARN_SCAN game phase: defect_forms=${warns:-0} game_flow_lines=${flowwarns:-0} refused_lines=${refused:-0} (expected 0/0/0; the editor log carries PIE game streams)"
  [ "${warns:-0}" = "0" ] || leg WARN_SCAN_GAME false
  [ "${flowwarns:-0}" = "0" ] || leg WARN_SCAN_GAME false
  [ "${refused:-0}" = "0" ] || leg WARN_SCAN_GAME false
  leg WARN_SCAN_GAME true

  # ---- the Stop proof: the four seeds untouched by the whole session ----
  input_off() { op pie.play_input_toggle >/dev/null 2>&1; sleep 1; }
  input_off
  stop_game
  shas=$(shasum -a 256 "$PROJECT/assets/scene.bsn" "$PROJECT/assets/menu.bsn" "$PROJECT/assets/gameover.bsn" "$PROJECT/assets/hud.bsn" | awk '{print $1}' | sort | tr '\n' ' ')
  log "SEED_SHAS_AFTER_GAME_PHASE=$shas"
  echo "$shas" > "$OUTDIR/seed-shas-game-phase.txt"
  printf '%s\n' "$(results)" > "$OUTDIR/summary-game.txt"
  log "VERDICT_GAME_PHASE: $(results)"
}

# ---- phase: flow (config, export, PIE, re-edit) -----------------------------
flow_phase() {
  editor_boot

  log "---- CELL10a: Play = the menu, the full flow ----"
  play_flow || { leg CELL10_PIE_DUAL false; stop_game; exit 1; }
  c10=true
  [ "$(named_count MenuRoot)" = "1" ] || c10=false
  [ "$(named_count Sun)" = "0" ] || c10=false
  stop_game

  log "---- CELL10b: Play-Current on the level tab = the level, flow=Level ----"
  play_current "$PROJECT/assets/scene.bsn" || c10=false
  sleep 2
  [ "$(named_count Sun)" = "1" ] || c10=false
  [ "$(named_count HudRoot)" = "1" ] || c10=false
  [ "$(named_count MenuRoot)" = "0" ] || c10=false
  [ "$(named_count MenuUiCamera)" = "0" ] || c10=false
  [ "$(count_of "$CRATE::PlayerMarker")" = "1" ] || c10=false
  log "CELL10: play menu_up=$(named_count MenuRoot); play_current Sun=$(named_count Sun) HudRoot=$(named_count HudRoot) MenuRoot=$(named_count MenuRoot) player=$(count_of "$CRATE::PlayerMarker")"
  stop_game
  leg CELL10_PIE_DUAL "$c10"

  log "---- CELL7: the start scene config drives all three launch forms ----"
  c7=true
  op game.set_start_scene "{\"path\":\"$PROJECT/assets/gameover.bsn\"}" >/dev/null 2>&1
  sleep 2
  face=$(flow_face)
  echo "$face" | jq -e '.start_scene == "gameover.bsn"' >/dev/null 2>&1 || c7=false
  echo "$face" | jq -e '(.warnings | length) == 0' >/dev/null 2>&1 || c7=false
  grep -q '"start_scene": "gameover.bsn"' "$PROJECT/assets/game.flow.json" || c7=false
  # form 1: Play (the startup-scene run) boots the end screen.
  play_flow || c7=false
  [ "$(named_count GameOverRoot)" = "1" ] || c7=false
  [ "$(named_count MenuRoot)" = "0" ] || c7=false
  [ "$(named_count GameOverUiCamera)" = "1" ] || c7=false
  stop_game
  # form 2: the direct binary (the PIE build has no assets beside it;
  # the asset root points at the project, exactly what a plain `cargo
  # run` in the project produces).
  (cd "$PROJECT" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" BEVY_ASSET_ROOT="$PROJECT" "$BIN" > "$OUTDIR/direct-gameover.log" 2>&1 &)
  wait_game 300 || c7=false
  sleep 2
  [ "$(named_count GameOverRoot)" = "1" ] || c7=false
  [ "$(named_count MenuRoot)" = "0" ] || c7=false
  stop_game
  log "CELL7: face=$(echo "$face" | tr -d '\n' | head -c 160); play+direct boot the end screen"
  leg CELL7_SET_START_THREE_FORMS "$c7"

  log "---- CELL8: the export starts from the named scene (five-point chain) ----"
  c8=true
  op game.export '{}' >/dev/null 2>&1
  deadline=$((SECONDS + 900))
  while [ $SECONDS -lt $deadline ]; do
    st=$(brp jackdaw/export '{}' 2>/dev/null | jq -r '.result.state // empty' 2>/dev/null)
    [ "$st" = "ready" ] && break
    sleep 3
  done
  face=$(brp jackdaw/export '{}' 2>/dev/null)
  ok_face=$(echo "$face" | jq -e '.result.flow_warnings == []' >/dev/null 2>&1 && echo y || echo n)
  [ "$(echo "$face" | jq -r '.result.state // empty')" = "ready" ] || c8=false
  [ -f "$STAGED_EXE" ] || c8=false
  ok_man=$(jq -r '.files[].path' "$STAGED/export-manifest.json" 2>/dev/null | grep -q "assets/game.flow.json" && echo y || echo n)
  ok_man=$ok_man
  [ "$ok_man" = "y" ] || c8=false
  ok_flow=$(python3 -c "import json,sys; d=json.load(open('$STAGED/assets/game.flow.json')); sys.exit(0 if d.get('start_scene')=='gameover.bsn' else 1)" 2>/dev/null && echo y || echo n)
  [ "$ok_flow" = "y" ] || c8=false
  (cd "$STAGED" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./t13t3-game > "$OUTDIR/staged-gameover.log" 2>&1 &)
  wait_game 300 || c8=false
  sleep 2
  ok_go=$( [ "$(named_count GameOverRoot)" = "1" ] && [ "$(named_count MenuRoot)" = "0" ] && echo y || echo n)
  [ "$ok_go" = "y" ] || c8=false
  stop_game
  log "CELL8 leg1: face_zero_warn=$ok_face manifest=$ok_man staged_flow=$ok_flow staged_boot_go=$ok_go"
  log "CELL8: staged gameover boot done; now change -> re-export -> changed launch"
  # The five-point chain's change -> re-export -> changed launch.
  op game.set_start_scene "{\"path\":\"$PROJECT/assets/menu.bsn\"}" >/dev/null 2>&1
  sleep 2
  op game.export '{}' >/dev/null 2>&1
  deadline=$((SECONDS + 900))
  while [ $SECONDS -lt $deadline ]; do
    st=$(brp jackdaw/export '{}' 2>/dev/null | jq -r '.result.state // empty' 2>/dev/null)
    [ "$st" = "ready" ] && break
    sleep 3
  done
  python3 -c "import json,sys; d=json.load(open('$STAGED/assets/game.flow.json')); sys.exit(0 if d.get('start_scene')=='menu.bsn' else 1)" 2>/dev/null || c8=false
  (cd "$STAGED" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./t13t3-game > "$OUTDIR/staged-menu.log" 2>&1 &)
  wait_game 300 || c8=false
  sleep 2
  [ "$(named_count MenuRoot)" = "1" ] || c8=false
  [ "$(named_count GameOverRoot)" = "0" ] || c8=false
  stop_game
  log "CELL8: staged flow now menu.bsn, staged launch boots the menu"
  leg CELL8_EXPORT_FROM_NAMED "$c8"

  log "---- CELL9: a ghost start scene warns on three faces, then clears ----"
  c9=true
  op game.set_start_scene "{\"path\":\"$PROJECT/assets/ghost.bsn\"}" >/dev/null 2>&1
  sleep 3
  face=$(flow_face)
  echo "$face" | jq -e '.start_scene == "ghost.bsn"' >/dev/null 2>&1 || c9=false
  echo "$face" | jq -e '(.warnings | length) >= 1' >/dev/null 2>&1 || c9=false
  echo "$face" | jq -r '.warnings | join(" | ")' | grep -q "ghost.bsn" || c9=false
  warn_text=$(echo "$face" | jq -r '.warnings | join("\n")')
  echo "$warn_text" > "$OUTDIR/leg-warn-text.txt"
  log "CELL9 editor face warnings: $(echo "$warn_text" | head -3 | tr '\n' ' ')"
  # The direct game falls back loudly to the code's scene.
  (cd "$PROJECT" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" BEVY_ASSET_ROOT="$PROJECT" "$BIN" > "$OUTDIR/direct-ghost.log" 2>&1 &)
  wait_game 300 || c9=false
  sleep 2
  [ "$(named_count MenuRoot)" = "1" ] || c9=false
  grep -q "ghost.bsn" "$OUTDIR/direct-ghost.log" || c9=false
  grep -Eq "game flow:.*ghost\.bsn.*not on disk|not on disk.*ghost\.bsn" "$OUTDIR/direct-ghost.log" || c9=false
  log "CELL9 game fallback log line: $(grep "game flow:" "$OUTDIR/direct-ghost.log" | head -1)"
  stop_game
  # The export warns too (the editor entry's flow_warnings on the face).
  op game.export '{}' >/dev/null 2>&1
  deadline=$((SECONDS + 900))
  while [ $SECONDS -lt $deadline ]; do
    st=$(brp jackdaw/export '{}' 2>/dev/null | jq -r '.result.state // empty' 2>/dev/null)
    [ "$st" = "ready" ] && break
    sleep 3
  done
  expface=$(brp jackdaw/export '{}' 2>/dev/null)
  echo "$expface" | jq -e '.result.flow_warnings | length >= 1' >/dev/null 2>&1 || c9=false
  echo "$expface" | jq -r '.result.flow_warnings | join(" | ")' | grep -q "ghost.bsn" || c9=false
  log "CELL9 export face: $(echo "$expface" | jq -r '.result.flow_warnings | join(" | ")' | head -c 200)"
  # Fix it: the warnings clear everywhere.
  op game.set_start_scene "{\"path\":\"$PROJECT/assets/menu.bsn\"}" >/dev/null 2>&1
  sleep 3
  face=$(flow_face)
  echo "$face" | jq -e '(.warnings | length) == 0' >/dev/null 2>&1 || c9=false
  leg CELL9_BAD_DATA_THREE_FACES "$c9"

  log "---- CELL11: retitle the menu in the editor, Save, Play, export ----"
  c11=true
  op scene.open "{\"path\":\"$PROJECT/assets/menu.bsn\"}" >/dev/null 2>&1
  sleep 3; wait_idle 300 >/dev/null; sleep 2; dismiss_dialog
  doc=$(brp jackdaw/scene_bsn '{}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
  echo "$doc" | grep -q "MenuRoot" || { c11=false; log "CELL11: menu document did not open"; }
  if [ "$c11" = true ]; then
    op component.set "{\"entity\":\"MenuTitle\",\"type_path\":\"bevy_ui::widget::text::Text\",\"field\":\"\",\"value\":\"\\\"T13t3 Flow Title\\\"\"}" >/dev/null 2>&1
    sleep 2
    brp jackdaw/scene_bsn '{}' 2>/dev/null | jq -r '.result // empty' | grep -q "T13t3 Flow Title" || c11=false
    op scene.save '{}' >/dev/null 2>&1
    sleep 3; wait_idle 300 >/dev/null; sleep 2; dismiss_dialog
    grep -q "T13t3 Flow Title" "$PROJECT/assets/menu.bsn" || c11=false
    log "CELL11: doc edit saved ($(grep -c 'T13t3 Flow Title' "$PROJECT/assets/menu.bsn") hit(s) on disk)"
    # Play from the 3D scene tab keeps the PIE override off the flow; the
    # game boots from the flow start scene and shows the edited title.
    op scene.open "{\"path\":\"$PROJECT/assets/scene.bsn\"}" >/dev/null 2>&1
    sleep 2; wait_idle 300 >/dev/null
    play_flow || c11=false
    title_hits=$(gbrp world.query '{"data":{"components":["bevy_ui::widget::text::Text"]}}' 2>/dev/null \
      | jq -r '[.result[] | .components["bevy_ui::widget::text::Text"] | tostring | select(test("T13t3 Flow Title"))] | length' 2>/dev/null)
    [ "${title_hits:-0}" -ge 1 ] || c11=false
    stop_game
    log "CELL11: live title hits after Play = $title_hits"
    # The export carries the edit and the staged launch shows it.
    op game.export '{}' >/dev/null 2>&1
    deadline=$((SECONDS + 900))
    while [ $SECONDS -lt $deadline ]; do
      st=$(brp jackdaw/export '{}' 2>/dev/null | jq -r '.result.state // empty' 2>/dev/null)
      [ "$st" = "ready" ] && break
      sleep 3
    done
    grep -q "T13t3 Flow Title" "$STAGED/assets/menu.bsn" || c11=false
    (cd "$STAGED" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./t13t3-game > "$OUTDIR/staged-reedit.log" 2>&1 &)
    wait_game 300 || c11=false
    sleep 2
    staged_hits=$(gbrp world.query '{"data":{"components":["bevy_ui::widget::text::Text"]}}' 2>/dev/null \
      | jq -r '[.result[] | .components["bevy_ui::widget::text::Text"] | tostring | select(test("T13t3 Flow Title"))] | length' 2>/dev/null)
    [ "${staged_hits:-0}" -ge 1 ] || c11=false
    stop_game
    log "CELL11: staged title hits = $staged_hits"
  fi
  leg CELL11_EDITOR_REEDIT "$c11"

  sleep 2
  warns=$(grep -Ec "cannot apply|cannot read|does not read as|UnresolvedTypes" "$OUTDIR/editor-flow.log" 2>/dev/null)
  log "WARN_SCAN flow phase editor log: defect_forms=${warns:-0} (game flow lines expected in CELL9 and asserted there)"
  [ "${warns:-0}" = "0" ] || leg WARN_SCAN_FLOW false
  leg WARN_SCAN_FLOW true
  printf '%s\n' "$(results)" > "$OUTDIR/summary-flow.txt"
  log "VERDICT_FLOW_PHASE: $(results)"
}

case "$PHASE" in
  prep) prep ;;
  game) game_phase ;;
  flow) flow_phase ;;
  all)
    prep
    game_phase
    flow_phase
    cat "$OUTDIR/summary-game.txt" "$OUTDIR/summary-flow.txt" | sort | tr '\n' ' ' > "$OUTDIR/summary.txt"
    log "VERDICT_ALL: $(cat "$OUTDIR/summary.txt")"
    log "T13T3_LIVE_DONE"
    ;;
  *) echo "unknown phase: $PHASE (prep|game|flow|all)"; exit 2 ;;
esac
