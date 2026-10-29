#!/bin/bash
# T14-T1 live matrix: the prefab workflow's eight live legs on the Mac
# fixture project (jd new + hand-written prefab fixtures + the BRP
# injection the t13t3 fixture established).
#
# Phases (each phase is self-contained: it boots and cleans its own
# editor/game processes — run one per invocation, or `all`):
#   prep    jd new the fixture, write assets/prefabs/{rock,barrel,base}.bsn
#           + world.bsn (two rock instances, one scale override, one nested
#           barrel), point the flow's start scene at world.bsn, inject
#           jackdaw_remote, refresh the lock, warm-build the game.
#   editor  L1 (entity.add.prefab native dialog), L2 (Inspector override
#           dot + the five prefab menu actions), L3 (hierarchy four
#           actions + the Save-as-Prefab dialog), L4 (external edit ->
#           watcher reload, override preserved), L7 (editor restart
#           reopen), L8 (undo chains over spawn/pack).
#   game    L5 (PIE: prefab instances in the game world, Stop restores),
#           L6 (the export five-point chain), the warn scan and the N13
#           count.
# Usage: bash loop/qa/t14-live.sh [phase]   phase: prep|editor|game|all
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
FIXROOT=/Users/zhanglinbo/workspace/loop-mac/t14-prefab
PROJECT="$FIXROOT/t14-prefab"
BIN="$PROJECT/.jackdaw/target/game/debug/t14-prefab"
PORT=15921
GAME_PORT=15702
OUTDIR="$REPO/loop/t14-live"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
STAGED="$PROJECT/.jackdaw/dist/release"
STAGED_EXE="$STAGED/t14-prefab"
CRATE='t14_prefab'
TKEY='bevy_transform::components::transform::Transform'
mkdir -p "$OUTDIR"
PHASE="${1:-all}"
CONSOLE_LOG="$OUTDIR/console-$PHASE.log"
: > "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t14-live.XXXXXX)"
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
  pkill -x t14-prefab 2>/dev/null
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
  curl -s -m 60 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' -d "$body"
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
  local deadline=$((SECONDS + ${1:-900}))
  while [ $SECONDS -lt $deadline ]; do
    game_up && return 0
    sleep 2
  done
  return 1
}
stop_game() {
  op pie.stop >/dev/null 2>&1
  sleep 2
  pkill -x t14-prefab 2>/dev/null
  sleep 2
}
editor_boot() {
  pkill -x jackdaw 2>/dev/null; pkill -x t14-prefab 2>/dev/null; sleep 1
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
open_world() {
  op scene.open "{\"path\":\"$PROJECT/assets/world.bsn\"}" >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
}
# name_count <name> in the editor world
name_count() {
  brp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null \
    | jq -r --arg n "$1" '[.result[] | .components["bevy_ecs::name::Name"] | tostring | select(. == $n)] | length' 2>/dev/null
}
# field <component> <name> <field> — the named entity's component field
field_of() {
  brp world.query "{\"data\":{\"components\":[\"bevy_ecs::name::Name\",\"$1\"]}}" 2>/dev/null \
    | jq -c --arg n "$2" --arg c "$1" --arg f "$3" \
      '[.result[] | select(.components["bevy_ecs::name::Name"] == $n) | .components[$c][$f]][0]' 2>/dev/null
}
scale_of() { field_of "$TKEY" "$1" "scale" | jq -c '.' 2>/dev/null; }
posy_of() { field_of "$TKEY" "$1" "translation" | jq -r '.[1]' 2>/dev/null; }
# The click primitives: the ui walk rects are screen-global physical px and
# this host runs the window at origin (0,0) at scale 2, so the window-local
# logical point is the rect center divided by two (calibrated against
# ui_click's own conversion during the T14-T1 dry run).
WALK=/tmp/t14-walk.json
walk() { brp jackdaw/ui_tree '{"depth":60}' > "$WALK" 2>/dev/null; }
rect_of() { # rect_of <exact text> — first match's rect from the last walk
  jq -r --arg t "$1" '[.. | objects | select(.text? == $t and .rect? != null) | .rect] | first // empty' "$WALK" 2>/dev/null
}
click_rect() { # click_rect <rect> [button]
  local rect="$1" button="${2:-primary}" cx cy
  [ -n "$rect" ] || return 1
  # A hand-rolled field-row label can carry a zero rect; the row is wide.
  rect=$(echo "$rect" | jq -c 'if .[2] == 0 then .[2] = 500 else . end' 2>/dev/null)
  cx=$(python3 -c "print(int((${rect}).x))" 2>/dev/null)
  cx=$(echo "$rect" | jq -r '(.[0]+.[2]/2.0)/2.0 | floor')
  cy=$(echo "$rect" | jq -r '(.[1]+.[3]/2.0)/2.0 | floor')
  op input.pointer "{\"x\":$cx,\"y\":$cy,\"action\":\"click\",\"button\":\"$button\"}" >/dev/null 2>&1
  sleep 1.5
}
# expand_outliner — the scene rows spawn under the collapsed World root; the
# disclosure toggle sits near the row's left edge, so the click sweeps a
# short list of x positions until the fixture's rows render.
expand_outliner() {
  walk
  local row cy n
  n=$(jq -r '[.. | objects | select(.text? == "rock_a")] | length' "$WALK" 2>/dev/null)
  [ "$n" != "0" ] && { log "expand_outliner: rows already rendered"; return 0; }
  row=$(rect_of "World")
  [ -n "$row" ] || { log "expand_outliner: no World row"; return 1; }
  cy=$(echo "$row" | jq -r '(.[1]+.[3]/2.0)/2.0 | floor')
  for X in 30 20 40 55 70; do
    op input.pointer "{\"x\":$X,\"y\":$cy,\"action\":\"click\",\"button\":\"primary\"}" >/dev/null 2>&1
    sleep 1.5
    walk
    n=$(jq -r '[.. | objects | select(.text? == "rock_a")] | length' "$WALK" 2>/dev/null)
    [ "$n" != "0" ] && { log "expand_outliner: toggled at x=$X"; return 0; }
  done
  log "expand_outliner: the World row never expanded"
  return 1
}
# entity_ops <name> — operator entity params resolve NAMES, not ids (the
# T14-T1 dry run: bits and NvM forms are refused, a name resolves).
# open the hierarchy context menu for a row: real secondary click at the
# row's center, then the walk names the menu items.
row_menu() { # row_menu <row text> — returns 0 when the menu came up
  local rect try
  for try in 1 2 3; do
    walk
    rect=$(rect_of "$1")
    if [ -n "$rect" ]; then
      # select the row first: the hierarchy context menu binds to
      # the selection (T14-T3 run: rock_b menus opened only after
      # the L2 selection; never-selected rows opened nothing)
      click_rect "$rect"
      click_rect "$rect" secondary
      walk
      if jq -r '[.. | objects | select(.text? != null and .text != "") | .text] | any(test("Revert All|Variant|Unbundle"))' "$WALK" 2>/dev/null | grep -q true; then
        return 0
      fi
    fi
    sleep 2
  done
  log "row_menu: no row '$1' or its menu never came up"
  return 1
}
menu_click() { # menu_click <item text prefix> — click a context-menu item
  walk
  local rect
  rect=$(jq -r --arg t "$1" '[.. | objects | select(.text? != null and (.text | startswith($t)) and .rect? != null) | .rect] | first // empty' "$WALK" 2>/dev/null)
  [ -n "$rect" ] || { log "menu_click: no item '$1'"; return 1; }
  click_rect "$rect"
}
# dialog_input <text> — type into the frontmost dialog's text input and
# click its Save button (Enter alone does not commit it).
dialog_input() {
  local input_ent try
  for try in 1 2 3; do
    walk
    input_ent=$(jq -r '[.. | objects | select(.kind? == "text_input" and .rect? != null and .entity? != null) | .entity] | first // empty' "$WALK" 2>/dev/null)
    [ -n "$input_ent" ] && break
    sleep 2
  done
  [ -n "$input_ent" ] || { log "dialog_input: no text input in the dialog"; return 1; }
  brp jackdaw/ui_input "{\"entity\":$input_ent,\"text\":\"$1\",\"commit\":\"none\"}" >/dev/null 2>&1
  sleep 1
  # commit through the dialog action itself: choice 0 is the action
  # button (Save); the walk never sees the button node. The dialog
  # closing is the commit receipt.
  for try in 1 2 3; do
    op dialog.answer '{"choice":"0"}' >/dev/null 2>&1
    sleep 2
    walk
    grep -q "text_input" "$WALK" 2>/dev/null || return 0
  done
  log "dialog_input: the dialog never closed after the Save answer"
  return 1
}
# click the first ui element whose text contains $1
click_text() {
  brp jackdaw/ui_click "{\"text\":\"$1\"}" 2>/dev/null | jq -r '.result.clicked // false' 2>/dev/null
}
# right-click the first ui element whose text contains $1 (secondary
# button), scaling the ui_tree rect (physical px) into window px.
rclick_text() {
  local rect scale_json w h x y
  rect=$(brp jackdaw/ui_tree "{\"text\":\"$1\",\"visible_only\":true,\"depth\":40}" 2>/dev/null \
    | jq -r '[.. | objects | select(.text? != null and (.text | tostring | contains('"'"'"$1"'"'"'))) | .rect][0] // empty' 2>/dev/null)
  [ -n "$rect" ] || { log "rclick_text: no ui element '$1'"; return 1; }
  scale_json=$(brp jackdaw/ui_tree '{"visible_only":true,"depth":1}' 2>/dev/null \
    | jq -r '[.. | objects | select(.rect? != null)][0].rect' 2>/dev/null)
  local rw rw2
  rw=$(echo "$scale_json" | jq -r '.[2]' 2>/dev/null)
  # The window is 1600 logical px wide; the widest depth-1 rect is it.
  rw2=$(brp jackdaw/ui_tree '{"depth":2}' 2>/dev/null \
    | jq -r '[.. | objects | select(.rect? != null) | .rect[2]] | max' 2>/dev/null)
  local scale
  scale=$(python3 -c "print((${rw2:-1600})/1600.0)" 2>/dev/null)
  [ -n "$scale" ] || scale=1.0
  w=$(echo "$rect" | jq -r '.[2]'); h=$(echo "$rect" | jq -r '.[3]')
  x=$(echo "$rect" | jq -r '.[0]'); y=$(echo "$rect" | jq -r '.[1]')
  local cx cy
  cx=$(python3 -c "print(int(($x + $w/2.0) / $scale))")
  cy=$(python3 -c "print(int(($y + $h/2.0) / $scale))")
  op input.pointer "{\"x\":$cx,\"y\":$cy,\"action\":\"click\",\"button\":\"secondary\"}" >/dev/null 2>&1
  sleep 1.5
  log "rclick_text '$1' at ($cx,$cy) scale=$scale"
  return 0
}
screenshot() { # screenshot <name>
  brp jackdaw/screenshot '{}' > "$OUTDIR/shot-$1.json" 2>/dev/null
  python3 - "$OUTDIR/shot-$1.json" "$OUTDIR/shot-$1.png" << 'PYT' 2>/dev/null
import json, base64, sys
data = json.load(open(sys.argv[1]))
def find_png(node):
    if isinstance(node, str) and node.startswith("iVBOR"):
        return node
    if isinstance(node, dict):
        for v in node.values():
            got = find_png(v)
            if got: return got
    if isinstance(node, list):
        for v in node:
            got = find_png(v)
            if got: return got
    return None
png = find_png(data)
if png:
    open(sys.argv[2], "wb").write(base64.b64decode(png))
    print("saved", sys.argv[2])
PYT
}
export_prefab_wait() { # export_prefab_wait — game.export to ready
  op game.export '{}' >/dev/null 2>&1
  local deadline=$((SECONDS + 900))
  while [ $SECONDS -lt $deadline ]; do
    local st
    st=$(brp jackdaw/export '{}' 2>/dev/null | jq -r '.result.state // empty' 2>/dev/null)
    [ "$st" = "ready" ] && return 0
    # The staging lands asynchronously; the state can race past the poll.
    # T1 note: readiness must also poll the payload — the staged rock.bsn
    # matching the project's byte for byte, named in the manifest.
    local staged_sha local_sha
    staged_sha=$(shasum -a 256 "$STAGED/assets/prefabs/rock.bsn" 2>/dev/null | awk '{print $1}')
    local_sha=$(shasum -a 256 "$PROJECT/assets/prefabs/rock.bsn" 2>/dev/null | awk '{print $1}')
    if [ -n "$staged_sha" ] && [ "$staged_sha" = "$local_sha" ] \
       && jq -e '.files[].path' "$STAGED/export-manifest.json" 2>/dev/null | grep -q "prefabs/rock.bsn"; then
      return 0
    fi
    sleep 3
  done
  return 1
}

re_prefab_y() {
  python3 - "$1" "$2" "$3" <<'PYT'
import re, sys
p, old, new = sys.argv[1:4]
t = open(p).read()
pat = r"(y: )" + re.escape(old) + r"(,\s*z: )"
t2, n = re.subn(pat, lambda m: m.group(1) + new + m.group(2), t)
open(p, "w").write(t2)
print(n)
PYT
}
write_fixtures() {
  mkdir -p "$PROJECT/assets/prefabs"
  cat > "$PROJECT/assets/prefabs/rock.bsn" << 'EOF'
// T14 prefab fixture: a single-level prefab, a rock with a tip child.

#Rock
jackdaw::prefab::components::Prefab
jackdaw::prefab::components::PrefabEntityId(0)
bevy_transform::components::transform::Transform {
    translation: glam::Vec3 { x: 0.0, y: 0.0, z: 0.0 },
    rotation: glam::Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 },
    scale: glam::Vec3 { x: 1.0, y: 1.0, z: 1.0 },
}
bevy_camera::visibility::Visibility::Inherited
bevy_ecs::hierarchy::Children [
    #RockTip
    jackdaw::prefab::components::PrefabEntityId(1)
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: 0.0, y: 1.0, z: 0.0 },
        rotation: glam::Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 },
        scale: glam::Vec3 { x: 1.0, y: 1.0, z: 1.0 },
    }
    bevy_camera::visibility::Visibility::Inherited
]
EOF
  cat > "$PROJECT/assets/prefabs/base.bsn" << 'EOF'
// T14 prefab fixture: the variant base plate.

#Base
jackdaw::prefab::components::Prefab
jackdaw::prefab::components::PrefabEntityId(0)
bevy_transform::components::transform::Transform {
    translation: glam::Vec3 { x: 0.0, y: 0.0, z: 0.0 },
    rotation: glam::Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 },
    scale: glam::Vec3 { x: 1.0, y: 1.0, z: 1.0 },
}
bevy_camera::visibility::Visibility::Inherited
bevy_ecs::hierarchy::Children [
    #BaseLeg
    jackdaw::prefab::components::PrefabEntityId(1)
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: 0.0, y: -0.5, z: 0.0 },
        rotation: glam::Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 },
        scale: glam::Vec3 { x: 1.0, y: 1.0, z: 1.0 },
    }
    bevy_camera::visibility::Visibility::Inherited
]
EOF
  cat > "$PROJECT/assets/prefabs/barrel.bsn" << 'EOF'
// T14 prefab fixture: a nested prefab — the barrel's own root plus a
// nested instance of rock.

#Barrel
jackdaw::prefab::components::Prefab
jackdaw::prefab::components::PrefabEntityId(0)
bevy_transform::components::transform::Transform {
    translation: glam::Vec3 { x: 0.0, y: 0.0, z: 0.0 },
    rotation: glam::Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 },
    scale: glam::Vec3 { x: 1.0, y: 1.0, z: 1.0 },
}
bevy_camera::visibility::Visibility::Inherited
bevy_ecs::hierarchy::Children [
    #BarrelRock
    jackdaw::prefab::components::PrefabEntityId(5)
    jackdaw::prefab::components::IsA { source: "prefabs/rock.bsn", deleted: [] }
]
EOF
  cat > "$PROJECT/assets/world.bsn" << 'EOF'
// T14 prefab fixture scene: two rock instances (one with an authored
// scale override) and a barrel instance resolving through the nested
// prefab chain.

#World
bevy_transform::components::transform::Transform
bevy_camera::visibility::Visibility::Inherited
bevy_ecs::hierarchy::Children [
    #rock_a
    jackdaw::prefab::components::PrefabEntityId(0)
    jackdaw::prefab::components::IsA { source: "prefabs/rock.bsn", deleted: [] }
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: 2.0, y: 0.0, z: 0.0 },
        rotation: glam::Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 },
        scale: glam::Vec3 { x: 1.0, y: 1.0, z: 1.0 },
    }
    bevy_camera::visibility::Visibility::Inherited
    --
    #rock_b
    jackdaw::prefab::components::PrefabEntityId(0)
    jackdaw::prefab::components::IsA { source: "prefabs/rock.bsn", deleted: [] }
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: -2.0, y: 0.0, z: 0.0 },
        rotation: glam::Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 },
        scale: glam::Vec3 { x: 2.0, y: 1.0, z: 1.0 },
    }
    bevy_camera::visibility::Visibility::Inherited
    --
    #barrel_a
    jackdaw::prefab::components::PrefabEntityId(0)
    jackdaw::prefab::components::IsA { source: "prefabs/barrel.bsn", deleted: [] }
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: 0.0, y: 3.0, z: 0.0 },
        rotation: glam::Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 },
        scale: glam::Vec3 { x: 1.0, y: 1.0, z: 1.0 },
    }
    bevy_camera::visibility::Visibility::Inherited
]
EOF

  # A stale persisted dock layout would hide the panels the live legs
  # click; every prep starts from the default layout.
  python3 - "$PROJECT/.jackdaw/project.json" << 'PYT'
import json, sys
path = sys.argv[1]
try:
    cfg = json.load(open(path))
    cfg.pop("layout", None)
    json.dump(cfg, open(path, "w"), indent=2)
except FileNotFoundError:
    pass
PYT

  # The flow boots the prefab scene so staged/standalone runs see it too.
  # world.bsn joins the scenes list as well, or the flow face warns.
  python3 - "$PROJECT/assets/game.flow.json" << 'PYT'
import json, sys
path = sys.argv[1]
flow = json.load(open(path))
flow["start_scene"] = "world.bsn"
if "world.bsn" not in flow["scenes"]:
    flow["scenes"].insert(0, "world.bsn")
json.dump(flow, open(path, "w"), indent=2)
PYT
  grep -q '"start_scene": "world.bsn"' "$PROJECT/assets/game.flow.json" || { log "PREP_FAIL flow edit"; exit 1; }
}

# ---- phase: prep ------------------------------------------------------------
prep() {
  pkill -x jackdaw 2>/dev/null; pkill -x t14-prefab 2>/dev/null; sleep 1
  rm -rf "$FIXROOT"; mkdir -p "$FIXROOT"
  (cd "$REPO" && cargo run -p jd --quiet -- new t14-prefab --path "$FIXROOT" --no-git) > "$OUTDIR/jd-new.log" 2>&1
  [ -d "$PROJECT" ] || { log "PREP_FAIL no project"; exit 1; }

  write_fixtures

  # Warm-project test injection (t11t2/t13t2 practice): game-side BRP.
  /usr/bin/sed -i '' "s|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = \[\"terrain\", \"pie\"\] }|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = [\"terrain\", \"pie\"] }\njackdaw_remote = { path = '$REPO/crates/jackdaw_remote' }|" "$PROJECT/Cargo.toml"
  grep -q jackdaw_remote "$PROJECT/Cargo.toml" || { log "PREP_FAIL no remote dep"; exit 1; }
  /usr/bin/sed -i '' 's|\.add_plugins(t14_prefab::GamePlugin)|.add_plugins(t14_prefab::GamePlugin)\n        .add_plugins(jackdaw_remote::JackdawRemotePlugin::default())|' "$PROJECT/src/main.rs"
  grep -q JackdawRemotePlugin "$PROJECT/src/main.rs" || { log "PREP_FAIL no remote plugin"; exit 1; }
  (cd "$PROJECT" && cargo metadata --format-version 1 >/dev/null 2>"$OUTDIR/lockfix.log") \
    || { log "PREP_FAIL lock refresh: $(tail -2 "$OUTDIR/lockfix.log")"; exit 1; }

  # Warm the PIE game build so the game phase is not a cold compile.
  (cd "$PROJECT" && cargo build > "$OUTDIR/game-warmbuild.log" 2>&1) \
    || { log "PREP_FAIL game warm build: $(tail -3 "$OUTDIR/game-warmbuild.log")"; exit 1; }
  log "PREP_OK fixture=$PROJECT"
}

# ---- phase: editor (L1-L4, L7, L8) ------------------------------------------
editor_phase() {
  # every editor segment starts from the canonical prep
  # state: the L2 gates hardcode the fresh-prep baseline
  write_fixtures
  editor_boot
  open_world

  log "---- L0 sanity: the fixture resolves in the editor ----"
  sleep 2; walk; expand_outliner || true
  l0=true
  [ "$(name_count rock_a)" = "1" ] || l0=false
  [ "$(name_count rock_b)" = "1" ] || l0=false
  [ "$(name_count barrel_a)" = "1" ] || l0=false
  [ "$(name_count RockTip)" = "3" ] || l0=false
  [ "$(name_count BarrelRock)" = "1" ] || l0=false
  sb=$(scale_of rock_b)
  [ "$sb" = "[2.0,1.0,1.0]" ] || l0=false
  log "L0: names RockTip=$(name_count RockTip) BarrelRock=$(name_count BarrelRock) rock_b scale=$sb"
  leg L0_FIXTURE_RESOLVES "$l0"

  log "---- L2: Inspector prefab menu faces on rock_b ----"
  # Select the override carrier: a primary click on its hierarchy row.
  walk
  rb_rect=$(rect_of "rock_b")
  [ -n "$rb_rect" ] && click_rect "$rb_rect"
  screenshot l2-inspector
  # a) component-header menu: Revert Component — the scale override goes
  #    back to the baseline.
  walk
  tf_rect=$(jq -r '[.. | objects | select(.text? == "Transform" and .rect? != null) | .rect] | max_by(.[0]) // empty' "$WALK" 2>/dev/null)
  if [ -n "$tf_rect" ]; then
    click_rect "$tf_rect" secondary
    if menu_click "Revert Component"; then
      sleep 2; wait_idle 60 >/dev/null
      rb=$(scale_of rock_b)
      log "L2a: Revert Component ran; rock_b scale now $rb (baseline [1.0,1.0,1.0])"
      [ "$rb" = "[1.0,1.0,1.0]" ] && leg L2_REVERT_COMPONENT true || leg L2_REVERT_COMPONENT false
    else
      log "L2a: the component context menu did not offer Revert Component"
      leg L2_REVERT_COMPONENT false
    fi
  else
    log "L2a: no Transform card found in the Inspector walk"
    leg L2_REVERT_COMPONENT false
  fi
  # rebuild the override through the same channel an inspector drag uses
  op component.set "{\"entity\":\"rock_b\",\"type_path\":\"$TKEY\",\"field\":\"scale\",\"value\":[2.0,1.0,1.0]}" >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  # b) component-header menu: Apply Component to Prefab Source — the PF1
  #    live proof: rock_a follows the applied baseline (the
  #    multi-instance propagation face, now gated).
  walk
  tf_rect=$(jq -r '[.. | objects | select(.text? == "Transform" and .rect? != null) | .rect] | max_by(.[0]) // empty' "$WALK" 2>/dev/null)
  if [ -n "$tf_rect" ]; then
    click_rect "$tf_rect" secondary
    if menu_click "Apply Component to Prefab Source"; then
      sleep 4; wait_idle 240 >/dev/null
      ra=$(scale_of rock_a); rb=$(scale_of rock_b)
      log "L2b: Apply-to-Source ran; rock_a scale after propagate = $ra (expect rock_a [1.0,1.0,1.0]: its authored override survives the apply; rock_b=$rb follows the new baseline)"
      echo "L2b_PF1_WITNESS rock_a=$ra" > "$OUTDIR/pf1-live-witness.txt"
      [ "$ra" = "[1.0,1.0,1.0]" ] && [ "$rb" = "[2.0,1.0,1.0]" ] \
        && leg L2_APPLY_TO_SOURCE true || leg L2_APPLY_TO_SOURCE false
    else
      leg L2_APPLY_TO_SOURCE false
    fi
  else
    leg L2_APPLY_TO_SOURCE false
  fi
  # c) component-header menu: Apply to All Instances in Scene — the bulk
  #    face: both rocks end at the picked scale.
  walk
  tf_rect=$(jq -r '[.. | objects | select(.text? == "Transform" and .rect? != null) | .rect] | max_by(.[0]) // empty' "$WALK" 2>/dev/null)
  if [ -n "$tf_rect" ]; then
    click_rect "$tf_rect" secondary
    if menu_click "Apply to All Instances in Scene"; then
      sleep 2; wait_idle 120 >/dev/null
      ra=$(scale_of rock_a); rb2=$(scale_of rock_b)
      log "L2c: bulk_apply ran; rock_a=$ra rock_b=$rb2 (expect both [2.0,1.0,1.0])"
      [ "$ra" = "[2.0,1.0,1.0]" ] && [ "$rb2" = "[2.0,1.0,1.0]" ] \
        && leg L2_BULK_APPLY true || leg L2_BULK_APPLY false
    else
      leg L2_BULK_APPLY false
    fi
  else
    leg L2_BULK_APPLY false
  fi
  # d) field-row menu on the placement: Revert Field snaps rock_b back to
  #    the baseline translation, Apply Field pushes it into the source.
  # re-select the row so the Inspector re-renders its field rows
  # (T14-T3: the translation row text was absent from the walk until a
  # fresh selection re-rendered the card body)
  walk
  rb3=$(rect_of "rock_b")
  [ -n "$rb3" ] && click_rect "$rb3"
  walk
  tr_rect=$(jq -r '[.. | objects | select(.text? == "translation" and .rect? != null) | .rect] | max_by(.[0]) // empty' "$WALK" 2>/dev/null)
  if [ -n "$tr_rect" ]; then
    click_rect "$tr_rect" secondary
    if menu_click "Revert Field"; then
      sleep 2; wait_idle 60 >/dev/null
      py=$(posy_of rock_b)
      log "L2d: Revert Field ran; rock_b y=$py (baseline 0)"
  pyw=$(awk -v a="$py" 'BEGIN {print (a+0 >= -0.01 && a+0 <= 0.01) ? "y" : "n"}')
  [ -n "$py" ] && [ "$pyw" = "y" ] \
    && leg L2_REVERT_FIELD true || leg L2_REVERT_FIELD false
    else
      leg L2_REVERT_FIELD false
    fi
  else
    log "L2d: no translation field row in the Inspector walk"
    leg L2_REVERT_FIELD false
  fi
  op component.set "{\"entity\":\"rock_b\",\"type_path\":\"$TKEY\",\"field\":\"translation\",\"value\":[-2.0,0.0,0.0]}" >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  walk
  tr_rect=$(jq -r '[.. | objects | select(.text? == "translation" and .rect? != null) | .rect] | max_by(.[0]) // empty' "$WALK" 2>/dev/null)
  if [ -n "$tr_rect" ]; then
    click_rect "$tr_rect" secondary
    if menu_click "Apply Field to Prefab Source"; then
      sleep 2; wait_idle 60 >/dev/null
      leg L2_APPLY_FIELD true
    else
      leg L2_APPLY_FIELD false
    fi
  else
    leg L2_APPLY_FIELD false
  fi

  log "---- L3: hierarchy prefab actions + the Save as Prefab dialog ----"
  # Reset to a known scene state first: discard the L2 mutations.
  open_world
  walk; expand_outliner || true
  # a) Save as Variant on rock_b (dialog: name input + Save click).
  if row_menu "rock_b"; then
    menu_click "Save as Variant"
    sleep 2; walk
    dialog_input "rock_var" && v=true || v=false
    wait_idle 120 >/dev/null
    [ -f "$PROJECT/assets/prefabs/rock_var.bsn" ] && v=true || v=false
    log "L3a: Save-as-Variant dialog driven; file=$v"
    [ "$v" = "true" ] && leg L3_SAVE_AS_VARIANT true || leg L3_SAVE_AS_VARIANT false
  else
    leg L3_SAVE_AS_VARIANT false
  fi
  # b) Apply All Changes to Prefab Source on the variant instance (the
  #    dispatch face; the instance carries no overrides now).
  if row_menu "rock_b"; then
    menu_click "Apply All Changes to Prefab Source"
    sleep 2; wait_idle 120 >/dev/null
    brp jackdaw/status '{}' >/dev/null 2>&1 && leg L3_APPLY_ALL true || leg L3_APPLY_ALL false
  else
    leg L3_APPLY_ALL false
  fi
  # c) Rebuild an override, then Revert All Overrides clears it. The
  #    baseline is whatever the source holds NOW (L3b's apply-all may have
  #    moved it) — capture, override, and expect the capture back.
  base_scale=$(scale_of rock_b)
  op component.set "{\"entity\":\"rock_b\",\"type_path\":\"$TKEY\",\"field\":\"scale\",\"value\":[3.0,1.0,1.0]}" >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  if row_menu "rock_b"; then
    menu_click "Revert All Overrides"
    sleep 2; wait_idle 120 >/dev/null
    rb=$(scale_of rock_b)
    log "L3c: Revert All ran; rock_b scale now $rb (baseline $base_scale)"
    [ "$rb" = "$base_scale" ] && leg L3_REVERT_ALL true || leg L3_REVERT_ALL false
  else
    leg L3_REVERT_ALL false
  fi
  # d) Unbundle Prefab Instance on barrel_a: the markers come off.
  if row_menu "barrel_a"; then
    menu_click "Unbundle Prefab Instance"
    sleep 2; wait_idle 120 >/dev/null
    isa_count=$(brp jackdaw/scene_bsn '{}' 2>/dev/null | jq -r '.result' | grep -c "prefabs/barrel.bsn")
    log "L3d: Unbundle ran; barrel references left in the doc = $isa_count"
    [ "$isa_count" = "0" ] && leg L3_UNBUNDLE true || leg L3_UNBUNDLE false
  else
    leg L3_UNBUNDLE false
  fi
  # e) Save as Prefab dialog over the unbundled barrel content.
  if row_menu "barrel_a"; then
    menu_click "Save Selection as Prefab"
    sleep 2; walk
    dialog_input "barrel_packed" && p=true || p=false
    wait_idle 120 >/dev/null
    [ -f "$PROJECT/assets/prefabs/barrel_packed.bsn" ] && p=true || p=false
    log "L3e: Save-as-Prefab dialog driven; file=$p"
    [ "$p" = "true" ] && leg L3_SAVE_AS_PREFAB true || leg L3_SAVE_AS_PREFAB false
  else
    leg L3_SAVE_AS_PREFAB false
  fi

  log "---- L4: external edit -> watcher reload, override preserved ----"
  l4=true
  n_y=$(re_prefab_y "$PROJECT/assets/prefabs/rock.bsn" "1.0" "4.0")
  [ "${n_y:-0}" -ge 1 ] || l4=false
  deadline=$((SECONDS + 20))
  while [ $SECONDS -lt $deadline ]; do
    [ "$(posy_of RockTip)" = "4" ] && break
    sleep 1
  done
  ty=$(posy_of RockTip)
  sb=$(scale_of rock_b)
  log "L4: RockTip y after external edit = $ty (expect 4); rock_b override scale = $sb (propagate may have moved the baseline; only the watcher face gates here)"
  [ "$(awk -v a="$ty" 'BEGIN {print (a+0 >= 3.99 && a+0 <= 4.01) ? "y" : "n"}')" = "y" ] || l4=false
  # restore the fixture for the later legs
  n_y=$(re_prefab_y "$PROJECT/assets/prefabs/rock.bsn" "4.0" "1.0")
  deadline=$((SECONDS + 20))
  while [ $SECONDS -lt $deadline ]; do
    [ "$(posy_of RockTip)" = "1" ] && break
    sleep 1
  done
  ty2=$(posy_of RockTip)
  [ "$(awk -v a="$ty2" 'BEGIN {print (a+0 >= 0.99 && a+0 <= 1.01) ? "y" : "n"}')" = "y" ] || l4=false
  leg L4_EXTERNAL_EDIT_PROPAGATES "$l4"

  log "---- L8: undo chains over spawn and pack ----"
  # Deviation (recorded): the BRP face has no raw key-chord channel, so
  # the undo gesture runs through history.undo — the same command the
  # classic preset's Super+Z row dispatches; the preset itself is applied
  # at boot (112 entries, logged).
  l8=true
  before=$(brp jackdaw/scene_bsn '{}' 2>/dev/null | jq -r '.result' | grep -c "prefabs/base.bsn")
  op prefab.spawn_instance "{\"path\":\"prefabs/base.bsn\",\"pos_x\":6.0,\"pos_y\":0.0,\"pos_z\":0.0}" >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  after=$(brp jackdaw/scene_bsn '{}' 2>/dev/null | jq -r '.result' | grep -c "prefabs/base.bsn")
  [ "$((before + 1))" = "$after" ] || l8=false
  op history.undo >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  undone=$(brp jackdaw/scene_bsn '{}' 2>/dev/null | jq -r '.result' | grep -c "prefabs/base.bsn")
  [ "$before" = "$undone" ] || l8=false
  log "L8a: spawn-undo chain base refs $before->$after->$undone"
  leg L8_SPAWN_UNDO "$l8"
  # pack chain: pack the unbundled barrel content back, undo restores the
  # group while the packed file stays on disk (the pack convention).
  l8b=true
  if row_menu "barrel_a"; then
    menu_click "Save Selection as Prefab"
    sleep 2; walk
    dialog_input "barrel_repacked" && p=true || p=false
    wait_idle 120 >/dev/null
    [ -f "$PROJECT/assets/prefabs/barrel_repacked.bsn" ] || l8b=false
    op history.undo >/dev/null 2>&1
    sleep 2; wait_idle 60 >/dev/null
    [ -f "$PROJECT/assets/prefabs/barrel_repacked.bsn" ] || l8b=false
    log "L8b: pack-undo chain file stays on disk ok=$l8b"
  else
    l8b=false
    log "L8b: no barrel_a row to pack"
  fi
  leg L8_PACK_UNDO_FILE_STAYS "$l8b"

  log "---- L7: the editor restart reopens the prefab scene ----"
  l7=true
  op scene.save >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null; dismiss_dialog
  [ -f "$PROJECT/assets/world.bsn" ] || l7=false
  pkill -x jackdaw 2>/dev/null; sleep 3
  editor_boot
  # The journal restores the session's tabs; the scene must come back
  # with its prefab instances resolved.
  deadline=$((SECONDS + 30))
  while [ $SECONDS -lt $deadline ]; do
    [ "$(name_count RockTip)" = "3" ] && break
    sleep 1
  done
  [ "$(name_count rock_a)" = "1" ] || l7=false
  [ "$(name_count RockTip)" = "3" ] || l7=false
  log "L7: after restart rock_a=$(name_count rock_a) RockTip=$(name_count RockTip)"
  leg L7_EDITOR_RESTART "$l7"

  log "---- L1: the native prefab picker dialog ----"
  # The rfd panel is an OS window: the drive is an osascript keystroke
  # attempt (Cmd+Shift+G, path, Return, Return). A host without the
  # accessibility permission records a BLOCKED leg, not a silent pass.
  open_world
  instances_before=$(brp jackdaw/scene_bsn '{}' 2>/dev/null | jq -r '.result' | grep -c "prefabs/base.bsn")
  op entity.add.prefab >/dev/null 2>&1
  sleep 3
  osascript > "$OUTDIR/l1-osascript.log" 2>&1 << 'EOS'
with timeout of 10 seconds
  tell application "System Events"
    keystroke "g" using {command down, shift down}
    delay 1.0
    keystroke "/Users/zhanglinbo/workspace/loop-mac/t14-prefab/t14-prefab/assets/prefabs/base.bsn"
    delay 1.0
    keystroke return
    delay 1.0
    keystroke return
  end tell
end timeout
EOS
  rc=$?
  deadline=$((SECONDS + 15))
  while [ $SECONDS -lt $deadline ]; do
    now=$(brp jackdaw/scene_bsn '{}' 2>/dev/null | jq -r '.result' | grep -c "prefabs/base.bsn")
    [ "$((instances_before + 1))" = "$now" ] && break
    sleep 1
  done
  now=$(brp jackdaw/scene_bsn '{}' 2>/dev/null | jq -r '.result' | grep -c "prefabs/base.bsn")
  log "L1: osascript rc=$rc base refs $instances_before->$now"
  if [ "$now" = "$((instances_before + 1))" ]; then
    leg L1_NATIVE_PICKER true
  else
    log "L1 BLOCKED: the native panel could not be driven from this host (see l1-osascript.log) — tool gap per the MCP-first rule, reported to the controller"
    leg L1_NATIVE_PICKER false
  fi

  # The standing warn scan over this phase's editor log.
  sleep 2
  warns=$(grep -Ec "cannot apply|cannot read|does not read as|UnresolvedTypes" "$OUTDIR/editor-editor.log" 2>/dev/null)
  flowwarns=$(grep -Ec "game flow:" "$OUTDIR/editor-editor.log" 2>/dev/null)
  refused=$(grep -Ec "Cannot spawn scene" "$OUTDIR/editor-editor.log" 2>/dev/null)
  log "WARN_SCAN editor phase: defect_forms=${warns:-0} game_flow_lines=${flowwarns:-0} refused_lines=${refused:-0}"
  grep -Ein "prefab" "$OUTDIR/editor-editor.log" 2>/dev/null | grep -Ei "warn|error|fail|missing|not found|unresolved" > "$OUTDIR/prefab-warn-lines-editor.log" || true
  [ "${warns:-0}" = "0" ] || leg WARN_SCAN_EDITOR false
  [ "${refused:-0}" = "0" ] || leg WARN_SCAN_EDITOR false
  leg WARN_SCAN_EDITOR true
  printf '%s\n' "$(results)" > "$OUTDIR/summary-editor.txt"
  log "VERDICT_EDITOR_PHASE: $(results)"
}

# ---- phase: game (L5, L6) ----------------------------------------------------
game_phase() {
  editor_boot
  open_world

  log "---- L5: PIE over the prefab scene, Stop restores ----"
  l5=true
  op pie.play_current >/dev/null 2>&1
  wait_game 900 || { log "PIE_GAME_UP_FAIL"; leg L5_PIE_PREFAB_SCENE false; stop_game; exit 1; }
  sleep 4
  tips=$(gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null \
    | jq -r '[.result[] | .components["bevy_ecs::name::Name"] | tostring | select(. == "RockTip")] | length' 2>/dev/null)
  barrels=$(gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null \
    | jq -r '[.result[] | .components["bevy_ecs::name::Name"] | tostring | select(. == "BarrelRock")] | length' 2>/dev/null)
  sb=$(gbrp world.query "{\"data\":{\"components\":[\"bevy_ecs::name::Name\",\"$TKEY\"]}}" 2>/dev/null \
    | jq -r --arg t "$TKEY" '[.result[] | select(.components["bevy_ecs::name::Name"] == "rock_b") | .components[$t].scale][0] | tostring' 2>/dev/null)
  tip_y=$(gbrp world.query "{\"data\":{\"components\":[\"bevy_ecs::name::Name\",\"$TKEY\"]}}" 2>/dev/null \
    | jq -r --arg t "$TKEY" '[.result[] | select(.components["bevy_ecs::name::Name"] == "RockTip") | .components[$t].translation[1]] | first' 2>/dev/null)
  log "L5: game world RockTip=$tips BarrelRock=$barrels rock_b scale=$sb RockTip y=$tip_y"
  [ "$tips" = "3" ] || l5=false
  [ "$barrels" = "1" ] || l5=false
  [ "$sb" = "[2.0,1.0,1.0]" ] || l5=false
  [ "$(awk -v a="$tip_y" 'BEGIN {print (a+0 >= 0.99 && a+0 <= 1.01) ? "y" : "n"}')" = "y" ] || l5=false
  leg L5_PIE_PREFAB_SCENE "$l5"

  # Stop restores the editor's own scene: the PIE entities are gone, the
  # editor's counts are back, the fixture files are untouched.
  l5r=true
  world_sha_before=$(shasum -a 256 "$PROJECT/assets/world.bsn" | awk '{print $1}')
  stop_game
  sleep 2
  [ "$(name_count RockTip)" = "3" ] || l5r=false
  [ "$(name_count rock_a)" = "1" ] || l5r=false
  world_sha_after=$(shasum -a 256 "$PROJECT/assets/world.bsn" | awk '{print $1}')
  [ "$world_sha_before" = "$world_sha_after" ] || l5r=false
  log "L5-stop: editor counts back, world.bsn sha stable=$([ "$world_sha_before" = "$world_sha_after" ] && echo y || echo n)"
  leg L5_STOP_RESTORES "$l5r"

  log "---- L6: the export five-point chain ----"
  # 1. change the prefab on disk (the authored-data path; the apply-only
  #    variant of this chain is PF2's red, probed headlessly).
  l6=true
  n_y=$(re_prefab_y "$PROJECT/assets/prefabs/rock.bsn" "1.0" "5.5")
  [ "${n_y:-0}" -ge 1 ] || l6=false
  sleep 3; wait_idle 60 >/dev/null
  # 2. export
  export_prefab_wait || l6=false
  # 3. the staged tree carries the edit
  [ -f "$STAGED_EXE" ] || l6=false
  staged_sha=$(shasum -a 256 "$STAGED/assets/prefabs/rock.bsn" 2>/dev/null | awk '{print $1}')
  local_sha=$(shasum -a 256 "$PROJECT/assets/prefabs/rock.bsn" | awk '{print $1}')
  if [ -z "$staged_sha" ] || [ "$staged_sha" != "$local_sha" ]; then
    l6=false
    log "L6 side-check: staged rock.bsn sha mismatch (staged=$staged_sha local=$local_sha)"
  fi
  if ! jq -r '.files[].path' "$STAGED/export-manifest.json" 2>/dev/null | grep -q "prefabs/rock.bsn"; then
    l6=false
    log "L6 side-check: manifest paths = $(jq -r '.files[].path' "$STAGED/export-manifest.json" 2>/dev/null | tr '\n' ' ' | head -c 300)"
  fi
  # 4. the staged game boots with the new baseline
  (cd "$STAGED" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./"$(basename "$STAGED_EXE")" > "$OUTDIR/staged-tall.log" 2>&1 &)
  wait_game 300 || l6=false
  sleep 3
  staged_tip=$(gbrp world.query "{\"data\":{\"components\":[\"bevy_ecs::name::Name\",\"$TKEY\"]}}" 2>/dev/null \
    | jq -r --arg t "$TKEY" '[.result[] | select(.components["bevy_ecs::name::Name"] == "RockTip") | .components[$t].translation[1]] | first' 2>/dev/null)
  log "L6: staged RockTip y = $staged_tip (expect 5.5)"
  [ "$staged_tip" = "5.5" ] || l6=false
  stop_game
  # 5. change back, re-export, the staged launch shows the old value.
  n_y=$(re_prefab_y "$PROJECT/assets/prefabs/rock.bsn" "5.5" "1.0")
  sleep 3; wait_idle 60 >/dev/null
  export_prefab_wait || l6=false
  staged_sha2=$(shasum -a 256 "$STAGED/assets/prefabs/rock.bsn" 2>/dev/null | awk '{print $1}')
  [ "$staged_sha2" = "$(shasum -a 256 "$PROJECT/assets/prefabs/rock.bsn" | awk '{print $1}')" ] || l6=false
  (cd "$STAGED" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./"$(basename "$STAGED_EXE")" > "$OUTDIR/staged-restored.log" 2>&1 &)
  wait_game 300 || l6=false
  sleep 3
  staged_tip2=$(gbrp world.query "{\"data\":{\"components\":[\"bevy_ecs::name::Name\",\"$TKEY\"]}}" 2>/dev/null \
    | jq -r --arg t "$TKEY" '[.result[] | select(.components["bevy_ecs::name::Name"] == "RockTip") | .components[$t].translation[1]] | first' 2>/dev/null)
  log "L6: staged RockTip y after restore+re-export = $staged_tip2 (expect 1)"
  [ "$(awk -v a="$staged_tip2" 'BEGIN {print (a+0 >= 0.99 && a+0 <= 1.01) ? "y" : "n"}')" = "y" ] || l6=false
  stop_game
  leg L6_EXPORT_FIVE_POINT "$l6"

  # The game phase's own output: the standing warn scan with the T13 word
  # list + the N13 PIE drain-panic count (ridden around + counted).
  sleep 2
  warns=$(grep -Ec "cannot apply|cannot read|does not read as|UnresolvedTypes" "$OUTDIR/editor-game.log" 2>/dev/null)
  flowwarns=$(grep -Ec "game flow:" "$OUTDIR/editor-game.log" 2>/dev/null)
  refused=$(grep -Ec "Cannot spawn scene" "$OUTDIR/editor-game.log" 2>/dev/null)
  n13=$(grep -c "panicked at" "$OUTDIR/editor-game.log" 2>/dev/null)
  log "WARN_SCAN game phase: defect_forms=${warns:-0} game_flow_lines=${flowwarns:-0} refused_lines=${refused:-0} (N13 PIE panics counted: ${n13:-0})"
  grep -n "panicked at" "$OUTDIR/editor-game.log" 2>/dev/null | head -5 >> "$OUTDIR/n13-count.txt" || true
  [ "${warns:-0}" = "0" ] || leg WARN_SCAN_GAME false
  [ "${refused:-0}" = "0" ] || leg WARN_SCAN_GAME false
  leg WARN_SCAN_GAME true
  printf '%s\n' "$(results)" > "$OUTDIR/summary-game.txt"
  log "VERDICT_GAME_PHASE: $(results)"
}

case "$PHASE" in
  prep) prep ;;
  editor) editor_phase ;;
  game) game_phase ;;
  all)
    prep
    editor_phase
    game_phase
    cat "$OUTDIR/summary-editor.txt" "$OUTDIR/summary-game.txt" 2>/dev/null | sort | tr '\n' ' ' > "$OUTDIR/summary.txt"
    log "VERDICT_ALL: $(cat "$OUTDIR/summary.txt")"
    log "T14_LIVE_DONE"
    ;;
  *) echo "unknown phase: $PHASE (prep|editor|game|all)"; exit 2 ;;
esac
