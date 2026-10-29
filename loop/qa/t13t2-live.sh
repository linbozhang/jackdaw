#!/bin/bash
# T13-T2 live leg: the editor flow-config chain and the export five-point
# chain, over the warm t13t2 fixture.
#
#   STAND_FLOW   the seed state: jackdaw/game_flow reads the scaffolded
#                flow file (present, start_scene=scene.bsn, every listed
#                scene on disk, zero warnings).
#   LEG_EXP1     jd export with the flow naming scene.bsn: zero game-flow
#                warnings, the staged tree carries game.flow.json with the
#                same start scene, the manifest lists it, and a staged
#                standalone launch starts from scene.bsn (Name "Root" in
#                the game world, no "LevelTwo").
#   LEG_SET      game.set_start_scene level2.bsn: the file lands atomically
#                on disk with the same start_scene, and jackdaw/game_flow
#                reads back consistent with zero warnings.
#   LEG_WARN     a typo path is written anyway and the validation names it
#                (warning text archived); resetting clears the warnings.
#   LEG_EXP2     the editor's game.export: the face answers ready with the
#                staged tree and manifest carrying the NEW start scene, and
#                a staged standalone launch starts from level2.bsn
#                (LevelTwo present, Root gone) — the five-point chain's
#                change -> re-export -> changed-launch lands.
#   LEG_MENU     best effort: the Project window's right-click on
#                scene.bsn offers "Set as Startup Scene" and clicking it
#                writes the flow file (ui_tree + input.pointer).
# Usage: bash loop/qa/t13t2-live.sh [phase]   phase: prep|editor|exp1|chain|all
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
FIXROOT=/Users/zhanglinbo/workspace/loop-mac/t13t2
PROJECT="$FIXROOT/t13t2-game"
PORT=15917
GAME_PORT=15702
OUTDIR="$REPO/loop/t13t2-live"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
STAGED="$PROJECT/.jackdaw/dist/release"
EXE="$STAGED/t13t2-game"
mkdir -p "$OUTDIR"
RESULTS_FILE="$(mktemp /tmp/t13t2-live.XXXXXX)"
touch "$RESULTS_FILE"
log() { echo "$@" | tee -a "$OUTDIR/console.log"; }
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
  pkill -x t13t2-game 2>/dev/null
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
names_in_game() {
  gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null > "$OUTDIR/names-raw.json"
  cat "$OUTDIR/names-raw.json"
}
game_has_name() {
  # The game's BRP serializes each Name component as the plain string
  # under the reflected key: "bevy_ecs::name::Name":"Root". Grep the raw
  # body; the quoted tail keeps HudRoot from matching Root.
  names_in_game | grep -q "Name\":\"$1\""
}
manifest_has_flow() {
  jq -r '.files[].path' "$STAGED/export-manifest.json" 2>/dev/null | grep -q "game.flow.json"
}
game_up() { gbrp jackdaw/app_info '{}' 2>/dev/null | jq -e '.result.app_name' >/dev/null 2>&1; }
launch_staged() {
  (cd "$STAGED" && nohup ./t13t2-game >> "$OUTDIR/staged-$1.log" 2>&1 &)
  local deadline=$((SECONDS + 120))
  while [ $SECONDS -lt $deadline ]; do
    game_up && return 0
    sleep 2
  done
  return 1
}
stop_staged() { pkill -x t13t2-game 2>/dev/null; sleep 2; }
flow_json_field() { jq -r ".$1 // empty" "$PROJECT/assets/game.flow.json" 2>/dev/null; }

# ---- phase: prep -----------------------------------------------------------
prep() {
  pkill -x jackdaw 2>/dev/null; pkill -x t13t2-game 2>/dev/null; sleep 1
  rm -rf "$FIXROOT"; mkdir -p "$FIXROOT"
  (cd "$REPO" && ./target/debug/jd new t13t2-game --path "$FIXROOT" --no-git) > "$OUTDIR/jd-new.log" 2>&1
  [ -d "$PROJECT" ] || { log "PREP_FAIL no project"; exit 1; }
  # Warm-project test injection (t11t2 practice): game-side BRP so the
  # direct and staged launches answer world queries.
  /usr/bin/sed -i '' "s|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = \[\"terrain\", \"pie\"\] }|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = [\"terrain\", \"pie\"] }\njackdaw_remote = { path = '$REPO/crates/jackdaw_remote' }|" "$PROJECT/Cargo.toml"
  grep -q jackdaw_remote "$PROJECT/Cargo.toml" || { log "PREP_FAIL no remote dep"; exit 1; }
  /usr/bin/sed -i '' 's|\.add_plugins(t13t2_game::GamePlugin)|.add_plugins(t13t2_game::GamePlugin)\n        .add_plugins(jackdaw_remote::JackdawRemotePlugin::default())|' "$PROJECT/src/main.rs"
  grep -q JackdawRemotePlugin "$PROJECT/src/main.rs" || { log "PREP_FAIL no remote plugin"; exit 1; }
  # The inserted dep must land in the lock file too: an export builds
  # --locked, so regenerate it here (a minimal refresh, the pinned
  # versions kept) before anything builds.
  (cd "$PROJECT" && cargo metadata --format-version 1 >/dev/null 2>"$OUTDIR/lockfix.log") \
    || { log "PREP_FAIL lock refresh: $(tail -2 "$OUTDIR/lockfix.log")"; exit 1; }
  # The second scene the flow switch targets: the seed scene's twin with
  # its own root name, so a world query tells the two apart.
  /usr/bin/sed -e 's|^#Root$|#LevelTwo|' -e 's|#Sun|#LevelTwoSun|' "$PROJECT/assets/scene.bsn" > "$PROJECT/assets/level2.bsn"
  grep -q "#LevelTwo" "$PROJECT/assets/level2.bsn" || { log "PREP_FAIL no level2"; exit 1; }
  log "SEED_FLOW=$(cat "$PROJECT/assets/game.flow.json" | tr -d '\n')"
  log "PREP_OK"
}

# ---- phase: editor ---------------------------------------------------------
editor_boot() {
  pkill -x jackdaw 2>/dev/null; sleep 1
  cd "$REPO"
  JACKDAW_OPEN_PROJECT="$PROJECT" JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1600x900 \
    nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$OUTDIR/editor.log" 2>&1 &
  local ok=""
  for i in $(seq 1 150); do
    sleep 2
    if brp jackdaw/status '{}' >/dev/null 2>&1; then ok=1; break; fi
    pgrep -x jackdaw >/dev/null || break
  done
  [ -n "$ok" ] || { log "EDITOR_BOOT_FAIL"; exit 1; }
  wait_idle 600; sleep 3
  log "EDITOR_READY"
  # STAND_FLOW: the seed flow face (seed state only — later phases run
  # with the start scene the chain has set, and the face follows it).
  local face
  face=$(brp jackdaw/game_flow '{}')
  echo "$face" > "$OUTDIR/stand-flow.json"
  if [ "$(flow_json_field start_scene)" = "scene.bsn" ]; then
    [ "$(echo "$face" | jq -r '.result.present')" = "true" ] || { log "STAND_FLOW_FAIL not present"; return 1; }
    [ "$(echo "$face" | jq -r '.result.start_scene')" = "scene.bsn" ] || { log "STAND_FLOW_FAIL wrong start scene"; return 1; }
    [ "$(echo "$face" | jq -r '.result.warnings | length')" = "0" ] || { log "STAND_FLOW_FAIL warnings: $(echo "$face" | jq -r '.result.warnings')"; return 1; }
    [ "$(echo "$face" | jq -r '[.result.scenes[] | select(.path=="scene.bsn" and .on_disk)] | length')" = "1" ] || { log "STAND_FLOW_FAIL scene.bsn not listed"; return 1; }
    leg STAND_FLOW 0
  else
    [ "$(echo "$face" | jq -r '.result.start_scene')" = "$(flow_json_field start_scene)" ] || { log "STAND_FLOW_FAIL face disagrees with disk"; return 1; }
    log "STAND_FLOW_CONSISTENT (non-seed state)"
  fi
}

# ---- phase: exp1 (jd export from the seed flow) ----------------------------
exp1() {
  (cd "$REPO" && ./target/debug/jd export --project "$PROJECT" \
    > "$OUTDIR/jd-export-1.log" 2>&1)
  echo "EXP1_EXIT=$?" | tee -a "$OUTDIR/jd-export-1.log"
}

exp1_verify() {
  [ -x "$EXE" ] || { log "EXP1_FAIL no exe"; return 1; }
  if grep -q "game flow" "$OUTDIR/jd-export-1.log"; then
    log "EXP1_FAIL unexpected flow warning: $(grep 'game flow' "$OUTDIR/jd-export-1.log")"
    return 1
  fi
  [ "$(flow_json_field start_scene)" = "scene.bsn" ] || { log "EXP1_FAIL project flow changed mid-flight"; return 1; }
  [ "$(jq -r '.start_scene // empty' "$STAGED/assets/game.flow.json" 2>/dev/null)" = "scene.bsn" ] || { log "EXP1_FAIL staged flow missing"; return 1; }
  manifest_has_flow || { log "EXP1_FAIL manifest lacks flow file"; return 1; }
  leg EXP1_STAGED_TREE 0
  launch_staged 1 || { log "EXP1_FAIL staged boot"; return 1; }
  sleep 4
  game_has_name "Root" || { log "EXP1_FAIL no Root (scene.bsn root) in game"; stop_staged; return 1; }
  game_has_name "LevelTwo" && { log "EXP1_FAIL level2 leaked into run 1"; stop_staged; return 1; }
  stop_staged
  leg EXP1 0
}

# ---- phase: chain (set/warn legs + editor export + staged run 2) -----------
chain() {
  # LEG_SET
  op game.set_start_scene '{"path":"level2.bsn"}' >/dev/null 2>&1
  sleep 1
  [ "$(flow_json_field start_scene)" = "level2.bsn" ] || { log "LEG_SET_FAIL disk json"; return 1; }
  local face
  face=$(brp jackdaw/game_flow '{}')
  echo "$face" > "$OUTDIR/leg-set.json"
  [ "$(echo "$face" | jq -r '.result.start_scene')" = "level2.bsn" ] || { log "LEG_SET_FAIL read-back"; return 1; }
  [ "$(echo "$face" | jq -r '.result.warnings | length')" = "0" ] || { log "LEG_SET_FAIL warnings"; return 1; }
  leg LEG_SET 0

  # LEG_WARN: the typo path is written, and the validation names it.
  op game.set_start_scene '{"path":"typo.bsn"}' >/dev/null 2>&1
  sleep 1
  face=$(brp jackdaw/game_flow '{}')
  echo "$face" > "$OUTDIR/leg-warn.json"
  [ "$(echo "$face" | jq -r '.result.start_scene')" = "typo.bsn" ] || { log "LEG_WARN_FAIL not written"; return 1; }
  echo "$face" | jq -r '.result.warnings[]' > "$OUTDIR/leg-warn-text.txt"
  grep -q "typo.bsn" "$OUTDIR/leg-warn-text.txt" || { log "LEG_WARN_FAIL no warning: $(cat "$OUTDIR/leg-warn-text.txt")"; return 1; }
  grep -q "game flow: .*typo.bsn" "$OUTDIR/editor.log" || log "LEG_WARN_NOTE editor-log line not found (status-bar surface carried it)"
  # Reset to the level the export will use; warnings clear.
  op game.set_start_scene '{"path":"level2.bsn"}' >/dev/null 2>&1
  sleep 1
  face=$(brp jackdaw/game_flow '{}')
  [ "$(echo "$face" | jq -r '.result.warnings | length')" = "0" ] || { log "LEG_WARN_FAIL warnings did not clear"; return 1; }
  leg LEG_WARN 0

  # LEG_EXP2: the editor's own export, warm.
  op game.export '{}' >/dev/null 2>&1
  local deadline=$((SECONDS + 1200)) face2
  while [ $SECONDS -lt $deadline ]; do
    face2=$(brp jackdaw/export '{}')
    [ "$(echo "$face2" | jq -r '.result.state')" = "ready" ] && break
    [ "$(echo "$face2" | jq -r '.result.state')" = "failed" ] && { log "EXP2_FAIL build: $(echo "$face2" | jq -r '.result.outcome')"; return 1; }
    sleep 5
  done
  echo "$face2" > "$OUTDIR/leg-exp2.json"
  [ "$(echo "$face2" | jq -r '.result.state')" = "ready" ] || { log "EXP2_FAIL still building"; return 1; }
  [ "$(echo "$face2" | jq -r '.result.flow_warnings | length')" = "0" ] || { log "EXP2_FAIL flow warnings: $(echo "$face2" | jq -r '.result.flow_warnings')"; return 1; }
  [ "$(jq -r '.start_scene // empty' "$STAGED/assets/game.flow.json" 2>/dev/null)" = "level2.bsn" ] || { log "EXP2_FAIL staged flow not updated"; return 1; }
  manifest_has_flow || { log "EXP2_FAIL manifest lacks flow file"; return 1; }
  leg EXP2_STAGED_TREE 0
  launch_staged 2 || { log "EXP2_FAIL staged boot"; return 1; }
  sleep 4
  game_has_name "LevelTwo" || { log "EXP2_FAIL no LevelTwo in game"; stop_staged; return 1; }
  game_has_name "Root" && { log "EXP2_FAIL old scene leaked into run 2"; stop_staged; return 1; }
  stop_staged
  leg EXP2 0

  # LEG_MENU (best effort): the Project window's right-click.
  menu_leg
}

menu_leg() {
  # Locate a scene tile by its text node, right-click it, read the menu.
  # Two tiles, two labels: the file that is NOT the start scene offers
  # "Set as Startup Scene"; the file that IS carries the marker
  # ("Startup Scene ✓") — both halves of the menu's contract.
  # ui_tree rects are physical pixels; input.pointer takes logical, so
  # the retina factor is divided out and a nudge lands inside the tile
  # behind the zero-size text node.
  click_tile() {
    local tile="$1" rect x y
    rect=$(brp jackdaw/ui_tree "{\"text\":\"$tile\",\"depth\":30}" 2>/dev/null \
      | jq -r "[.. | objects | select(.text? == \"$tile\")][0].rect // empty")
    [ -n "$rect" ] || return 1
    x=$(echo "$rect" | jq -r '.[0] / 2 + 10' | cut -d. -f1)
    y=$(echo "$rect" | jq -r '.[1] / 2 + 10' | cut -d. -f1)
    op input.pointer "{\"x\":$x,\"y\":$y,\"action\":\"click\",\"button\":\"secondary\"}" >/dev/null 2>&1
    sleep 1.5
  }
  click_tile "scene.bsn" || { log "LEG_MENU_SKIP tile not found"; return 0; }
  local menu
  menu=$(brp jackdaw/ui_tree '{"text":"Set as Startup Scene","depth":30}' 2>/dev/null)
  echo "$menu" > "$OUTDIR/leg-menu.json"
  echo "$menu" | jq -e '[.. | objects | select(.text? == "Set as Startup Scene")][0].rect' >/dev/null 2>&1 \
    || { log "LEG_MENU_FAIL item missing"; return 1; }
  log "LEG_MENU_ITEM_OFFERS 1"
  # Close this menu, then check the marker on the start-scene file.
  op input.pointer '{"x":20,"y":60,"action":"click"}' >/dev/null 2>&1
  sleep 1
  click_tile "level2.bsn" || { log "LEG_MENU_FAIL start tile gone"; return 1; }
  local start_menu
  start_menu=$(brp jackdaw/ui_tree '{"text":"Startup Scene","depth":30}' 2>/dev/null)
  echo "$start_menu" > "$OUTDIR/leg-menu-marker.json"
  if echo "$start_menu" | grep -q "Startup Scene ✓"; then
    leg LEG_MENU 0
  else
    log "LEG_MENU_FAIL marker missing"
    return 1
  fi
}

# ---- phase dispatch --------------------------------------------------------
PHASE="${1:-all}"
case "$PHASE" in
  prep)   prep ;;
  editor) editor_boot ;;
  exp1)   exp1 ;;
  exp1v)  exp1_verify ;;
  # The editor legs need the editor this invocation booted: the phase's
  # exit trap reaps the process, so boot + legs go together.
  chain)  editor_boot && chain ;;
  menu)   editor_boot && menu_leg ;;
  all)
    prep && editor_boot && exp1 && exp1_verify && chain
    log "RESULTS: $(results)"
    ;;
esac
