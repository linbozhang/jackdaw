#!/bin/bash
# T15-T2 live matrix: the animation workflow's live legs on the Mac
# fixture project (the green-state t15-anim fixture task 1 left, plus a
# hand-written graph rig scene and a bad-reference scene for the badge
# faces). Log names follow $PHASE everywhere (the A7 stale-grep lesson).
#
# Phases (each phase boots and cleans its own editor/game processes —
# run one per invocation, or `all`):
#   prep    verify the fixture's green state, write assets/graph.bsn (a
#           rig whose AnimationGraphRef names the graph the editor phase
#           authors) and assets/bad.bsn (a set with a missing clip, an
#           out-of-range source and a graphref naming no file), add both
#           to the flow's scene list, reset the persisted layout/tab
#           journal, inject jackdaw_remote, refresh the lock, warm-build
#           the game.
#   editor  the AN7 close faces (launcher Extensions + New Project, the
#           Modules picker, the project-open warn), L1 (module switch
#           chain), L2 (the M1 set authoring chain), L4 (preview
#           borrow/return), M9 (preview bad references), L3 (the M2
#           graph authoring chain + param-driven preview), L8 (the M8
#           badge three forms), L9 (the M12 Stop invariant + AN5 note),
#           M13 (save/reopen consistency).
#   game    L5 (PIE: the set state follows writes; the graph entry state,
#           params, trigger and the one-shot fall-back), M7 (loop and
#           transition live proof), L6 (the four-channel parity), L7
#           (bad clip -> the Game panel warn entry, red/green), L10
#           (the export carries the graph and the model), the warn scan
#           and the N13 count.
# Usage: bash loop/qa/t15-live.sh [phase]   phase: prep|editor|game|all
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
FIXROOT=/Users/zhanglinbo/workspace/loop-mac/t15-anim
PROJECT="$FIXROOT/t15-anim"
BIN="$PROJECT/.jackdaw/target/game/debug/t15-anim"
PORT=15930
GAME_PORT=15702
OUTDIR="$REPO/loop/t15-live"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
STAGED="$PROJECT/.jackdaw/dist/release"
STAGED_EXE="$STAGED/t15-anim"
ASET='jackdaw_animation_runtime::AnimationSet'
ASTATE='jackdaw_animation_runtime::AnimationState'
APARAMS='jackdaw_animation_runtime::graph::AnimationParams'
APLAYBACK='jackdaw_animation_runtime::graph::AnimationGraphPlayback'
AGRAPHREF='jackdaw_animation_runtime::graph::AnimationGraphRef'
mkdir -p "$OUTDIR"
PHASE="${1:-all}"
CONSOLE_LOG="$OUTDIR/console-$PHASE.log"
: > "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t15-live.XXXXXX)"
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
  pkill -x t15-anim 2>/dev/null
  sleep 1
}
trap cleanup EXIT

brp_raw() {
  local method="$1" params="${2:-}" id=$RANDOM body
  if [ -n "$params" ]; then
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params")
  else
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s"}' "$id" "$method")
  fi
  curl -s -m 60 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' -d "$body"
}
brp() {
  local method="$1" params="${2:-}"
  # Reads ride the flaky window: the editor's BRP endpoint intermittently
  # serves an empty-body 200 or a transient method-not-found while heavy
  # scene work runs (AN9's evidence). Callers that mutate go through
  # brp_raw instead — an op executes even when its response comes back
  # empty, so a blind retry would apply it twice.
  local attempt out
  for attempt in 1 2 3 4 5 6 7 8; do
    out=$(brp_raw "$method" "$params")
    if [ -n "$out" ] && ! echo "$out" | grep -q "expected value at line 1"; then
      echo "$out"
      return 0
    fi
    sleep 3
  done
  echo "$out"
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
  if [ -n "$params" ]; then brp_raw jackdaw/call_operator "{\"id\":\"$id\",\"params\":$params}"
  else brp_raw jackdaw/call_operator "{\"id\":\"$id\",\"params\":{}}"; fi
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
  pkill -x t15-anim 2>/dev/null
  sleep 2
}
editor_boot() { # editor_boot [project] — no arg boots into the launcher
  pkill -x jackdaw 2>/dev/null; pkill -x t15-anim 2>/dev/null; sleep 1
  local boot_log="$OUTDIR/editor-$PHASE.log"
  if [ -n "${1:-}" ]; then
    export JACKDAW_OPEN_PROJECT="$1"
  else
    unset JACKDAW_OPEN_PROJECT
  fi
  export JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1600x900
  cd "$REPO"
  nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$boot_log" 2>&1 &
  local ok=""
  for i in $(seq 1 150); do
    sleep 2
    if brp jackdaw/status '{}' >/dev/null 2>&1; then ok=1; break; fi
    pgrep -x jackdaw >/dev/null || break
  done
  [ -n "$ok" ] || { log "EDITOR_BOOT_FAIL"; exit 1; }
  sleep 5
  wait_idle 600 >/dev/null; sleep 3; dismiss_dialog
  log "EDITOR_READY project=${1:-none}"
}
open_scene() {
  # reload: true — an already-open tab rereads the file, which the disk
  # edits in L7 and the save/reopen in M13 rely on.
  op scene.open "{\"path\":\"$PROJECT/assets/$1\",\"reload\":true}" >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
}
query_json() { # query_json <components-json-array> — one world.query (editor or game port by caller)
  brp world.query "{\"data\":{\"components\":$1}}" 2>/dev/null
}
name_id() { # name_id <name> — the entity id carrying this Name
  query_json '["bevy_ecs::name::Name"]' | jq -r --arg n "$1" \
    '[.result[] | select(.components["bevy_ecs::name::Name"] == $n) | .entity][0]' 2>/dev/null
}
comp_of() { # comp_of <name> <component> — the named entity's component as JSON
  # The read goes through a targeted world.get_components: a whole-world
  # query over a placed skeleton is the response size the empty-body
  # window eats most reliably, and the lookup retried here is the one
  # the legs assert on.
  local id attempt out
  for attempt in 1 2 3; do
    id=$(query_json '["bevy_ecs::name::Name"]' 2>/dev/null | jq -r --arg n "$1" \
      '[.result[] | select(.components["bevy_ecs::name::Name"] == $n) | .entity][0]' 2>/dev/null)
    [ -n "$id" ] && break
    sleep 3
  done
  [ -n "$id" ] || return 0
  for attempt in 1 2 3 4; do
    out=$(brp world.get_components "{\"entity\":\"$id\",\"components\":[\"$2\"]}" 2>/dev/null \
      | jq -c --arg c "$2" '.result.components[$c] // .result[$c] // empty' 2>/dev/null)
    [ -n "$out" ] && { echo "$out"; return 0; }
    sleep 3
  done
  echo "$out"
}
# jackdaw/screenshot is a watching method: the HTTP call blocks until the
# capture lands, so each poll runs on a short timeout and retries. The
# capture path must stay inside the project.
shot() { # shot <name> [kind]
  local name="$1" kind="${2:-window}"
  local rel path out out_json
  rel="screenshots/t15-$name.png"
  path="$PROJECT/$rel"
  rm -f "$path"
  for i in $(seq 1 20); do
    out_json=$(curl -s -m 12 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
      -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"jackdaw/screenshot\",\"params\":{\"kind\":\"$kind\",\"path\":\"$rel\",\"request\":\"$name\"}}" 2>/dev/null)
    out=$(echo "$out_json" | jq -r '.result.path // empty' 2>/dev/null)
    if [ -n "$out" ] && [ -s "$path" ]; then
      log "shot $name ok ($kind)"
      return 0
    fi
    sleep 1
  done
  # Last resort: the OS screen capture (the editor window sits at the
  # front on this host).
  screencapture -x "$path" 2>/dev/null && [ -s "$path" ] \
    && { log "shot $name ok (os screencapture fallback)"; return 0; }
  log "shot $name FAILED (capture never landed)"
  return 1
}
walk() { brp jackdaw/ui_tree '{"depth":60}' > "$OUTDIR/walk-$PHASE.json" 2>/dev/null; }
walk_has() { grep -qF "$1" "$OUTDIR/walk-$PHASE.json" 2>/dev/null; }
click_text() {
  brp jackdaw/ui_click "{\"text\":\"$1\"}" 2>/dev/null | jq -r '.result.clicked // false' 2>/dev/null
}
game_log_lines() { # game_log_lines — the Game panel's log rows, via the UI walk
  walk
  jq -r '[.. | objects | select(.text? != null) | .text] | .[]' "$OUTDIR/walk-$PHASE.json" 2>/dev/null \
    | grep -E "WARN|ERROR|wants clip|no state named|could not" | tail -20
}
ginsert() { # ginsert <entity-id> <type-path> <json-value> — bevy native insert, game world
  gbrp world.insert_components "{\"entity\":$1,\"components\":{\"$2\":$3}}" >/dev/null 2>&1
}
# The insert request itself can land in the empty-body window (a null
# response means it never executed), so writes confirm through a targeted
# read and re-send until the value sticks.
ginsert_verify() { # ginsert_verify <id> <type-path> <json-value>
  local id="$1" tp="$2" val="$3" attempt got
  for attempt in 1 2 3 4; do
    ginsert "$id" "$tp" "$val"
    sleep 2
    got=$(gbrp world.get_components "{\"entity\":$id,\"components\":[\"$tp\"]}" 2>/dev/null \
      | jq -c --arg t "$tp" '.result.components[$t] // empty' 2>/dev/null)
    echo "$got" | grep -qF "$val" && { echo "$got"; return 0; }
  done
  echo "$got"
  return 1
}
graph_state() { # the rig's AnimationGraphPlayback.state (editor or game world by caller)
  comp_of Rig "$APLAYBACK" | jq -r '.state // empty' 2>/dev/null
}
graph_transition_game() { # the rig's crossfade field in the GAME world
  local id
  id=$(gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null \
    | jq -r '[.result[]? | select(.components["bevy_ecs::name::Name"] == "Rig") | .entity][0]' 2>/dev/null)
  [ -n "$id" ] || return 0
  gbrp world.get_components "{\"entity\":$id,\"components\":[\"$APLAYBACK\"]}" 2>/dev/null \
    | jq -c --arg t "$APLAYBACK" '.result.components[$t].transition // empty' 2>/dev/null
}
graph_state_game() { # the rig's playback state in the GAME world
  local id
  id=$(gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null \
    | jq -r '[.result[]? | select(.components["bevy_ecs::name::Name"] == "Rig") | .entity][0]' 2>/dev/null)
  [ -n "$id" ] || return 0
  gbrp world.get_components "{\"entity\":$id,\"components\":[\"$APLAYBACK\"]}" 2>/dev/null \
    | jq -r --arg t "$APLAYBACK" '.result.components[$t].state // empty' 2>/dev/null
}
graph_transition() {
  comp_of Rig "$APLAYBACK" | jq -c '.transition // empty' 2>/dev/null
}
graph_since() {
  comp_of Rig "$APLAYBACK" | jq -r '.since_secs // empty' 2>/dev/null
}
sample_graph() { # sample_graph <label> — one labelled playback sample
  local st since tr
  st=$(graph_state); since=$(graph_since); tr=$(graph_transition)
  echo "{\"label\":\"$1\",\"state\":\"$st\",\"since\":${since:-0},\"transition\":${tr:-null}}"
}
flow_start_scene() { # flow_start_scene <scene> — point the flow's start scene; no arg prints it
  python3 - "$PROJECT/assets/game.flow.json" "${1:-}" << 'PYT'
import json, sys
path, scene = sys.argv[1], sys.argv[2]
flow = json.load(open(path))
if scene:
    flow["start_scene"] = scene
    if scene not in flow["scenes"]:
        flow["scenes"].append(scene)
    json.dump(flow, open(path, "w"), indent=2)
else:
    print(flow.get("start_scene", ""))
PYT
}
game_ready() { # game_ready [timeout] — wait until the game's world.* answers
  # The editor builds the game on project open; a core-saturating build
  # starves the game's main thread and its BRP method surface goes quiet
  # (the AN9 family). The legs start once it answers.
  local deadline=$((SECONDS + ${1:-180}))
  while [ $SECONDS -lt $deadline ]; do
    if gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null \
       | jq -e '.result' >/dev/null 2>&1; then
      return 0
    fi
    sleep 3
  done
  log "GAME_READY timeout: the game BRP never answered world.query"
  return 1
}
editor_build_settled() { # editor_build_settled [timeout] — wait out the editor's build
  local deadline=$((SECONDS + ${1:-300})) quiet=0
  while [ $SECONDS -lt $deadline ]; do
    local progress
    progress=$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.progress // empty' 2>/dev/null)
    if [ -z "$progress" ]; then
      quiet=$((quiet + 1))
      [ "$quiet" -ge 3 ] && return 0
    else
      quiet=0
      log "editor build in flight: $progress"
    fi
    sleep 3
  done
  log "editor_build_settled timeout"
  return 1
}

export_wait() { # export_wait — game.export to a ready staged tree
  op game.export '{}' >/dev/null 2>&1
  local deadline=$((SECONDS + 900))
  while [ $SECONDS -lt $deadline ]; do
    local st
    st=$(brp jackdaw/export '{}' 2>/dev/null | jq -r '.result.state // empty' 2>/dev/null)
    [ "$st" = "ready" ] && return 0
    [ -x "$STAGED_EXE" ] && [ -f "$STAGED/export-manifest.json" ] && return 0
    sleep 3
  done
  return 1
}

write_scenes() {
  # The L2 canvas in its canonical form (no placed model): L2's
  # place_gltf names its spawn after the file stem, and any hero left in
  # the document would make the name ambiguous for every later op.
  cat > "$PROJECT/assets/scene.bsn" << 'EOF'
// Starter scene. Authored by the jackdaw editor; safe to edit by hand.
// The game's camera is the CameraRig its code parents under the player;
// to author a fixed camera instead, use Add Entity > Scene Camera.

#Root
bevy_transform::components::transform::Transform
bevy_camera::visibility::Visibility::Visible
bevy_ecs::hierarchy::Children [
    #Sun
    bevy_light::directional_light::DirectionalLight
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: 0.0, y: 8.0, z: 0.0 },
        rotation: glam::Quat { x: -0.4226183, y: 0.0, z: 0.0, w: 0.9063078 },
    }
    bevy_camera::visibility::Visibility::Visible
]
EOF
  # The graph rig: the reference names the graph file the editor phase
  # authors (L3). The graph family carries its defining module path
  # (jackdaw_animation_runtime::graph::) in scene documents — the crate
  # root re-export path does not resolve (AN8 candidate, see the report).
  # Until the file exists this scene is the live red half of the graphref
  # badge; afterwards it binds and plays the entry state.
  cat > "$PROJECT/assets/graph.bsn" << 'EOF'
// T15 parity scene (graph model). A rig pointing at the animation graph
// the editor authors; the game plays the entry state as soon as it binds.

#Rig
jackdaw_animation_runtime::graph::AnimationGraphRef {
    path: "animation/hero_graph.animgraph.bsn",
    skeleton_root: "Armature",
}
bevy_ecs::hierarchy::Children [
    #Armature
    bevy_transform::components::transform::Transform
]
EOF
  # The badge red scene: a set whose second state names a clip hero.glb
  # does not carry, whose third state's source index is out of range,
  # plus a graphref naming no file at all.
  cat > "$PROJECT/assets/bad.bsn" << 'EOF'
// T15 badge-fixture scene: every author-side reference problem at once.

#BadSet
jackdaw_animation_runtime::AnimationSet {
    sources: ["models/hero.glb", "models/missing.glb"],
    states: [
        jackdaw_animation_runtime::AnimationStateDef {
            name: "good_one",
            source: 0,
            clip: "Idle_Loop",
            looped: true,
            transition_secs: 0.15,
            speed: 1.0,
            then: None,
        },
        jackdaw_animation_runtime::AnimationStateDef {
            name: "ghost_clip",
            source: 0,
            clip: "No_Such_Clip",
            looped: true,
            transition_secs: 0.15,
            speed: 1.0,
            then: None,
        },
        jackdaw_animation_runtime::AnimationStateDef {
            name: "off_range",
            source: 2,
            clip: "Walk_Loop",
            looped: true,
            transition_secs: 0.15,
            speed: 1.0,
            then: None,
        },
    ],
    default_state: "",
    skeleton_root: "Armature",
}
--
#BadGraph
jackdaw_animation_runtime::graph::AnimationGraphRef {
    path: "animation/nope.bsn",
    skeleton_root: "Armature",
}
EOF
  python3 - "$PROJECT/assets/game.flow.json" << 'PYT'
import json, sys
path = sys.argv[1]
flow = json.load(open(path))
for scene in ["graph.bsn", "bad.bsn"]:
    if scene not in flow["scenes"]:
        flow["scenes"].append(scene)
json.dump(flow, open(path, "w"), indent=2)
PYT
  grep -q '"start_scene"' "$PROJECT/assets/game.flow.json" || { log "PREP_FAIL flow"; exit 1; }

  # A stale persisted dock layout would hide the panels the legs walk,
  # and a stale tab journal would restore the bad-reference scenes (the
  # AN9 churn source) from boot; every prep starts clean on anim.bsn.
  python3 - "$PROJECT/.jackdaw/project.json" << 'PYT'
import json, sys
path = sys.argv[1]
try:
    cfg = json.load(open(path))
    cfg.pop("layout", None)
    cfg["last_open_tabs"] = ["assets/anim.bsn"]
    cfg["last_active_tab"] = 0
    json.dump(cfg, open(path, "w"), indent=2)
except FileNotFoundError:
    pass
PYT
  # The authored graph file must not survive between runs: the L3 red
  # half needs the reference genuinely unread (badge red, load failure,
  # runtime warn), and a stale file would turn all of it green.
  rm -f "$PROJECT/assets/animation/hero_graph.animgraph.bsn"
  rm -f "$PROJECT/assets/animation/hero_graph.animgraph.bsn.bak"
  rm -rf "$PROJECT/screenshots"
}

# ---- phase: prep ------------------------------------------------------------
prep() {
  pkill -x jackdaw 2>/dev/null; pkill -x t15-anim 2>/dev/null; sleep 1
  [ -d "$PROJECT" ] || { log "PREP_FAIL fixture missing; run the T1 prep first"; exit 1; }
  grep -q '^animation = true' "$PROJECT/jackdaw.toml" || { log "PREP_FAIL fixture not green"; exit 1; }
  grep -q '"animation"' "$PROJECT/Cargo.toml" || { log "PREP_FAIL features lack animation"; exit 1; }
  [ -f "$PROJECT/assets/models/hero.glb" ] || { log "PREP_FAIL hero.glb missing"; exit 1; }
  [ -d "$PROJECT/assets/models/jan" ] || { log "PREP_FAIL jan missing"; exit 1; }

  write_scenes

  # Warm-project test injection (t11t2/t13t2/t14 practice): game-side BRP.
  if ! grep -q jackdaw_remote "$PROJECT/Cargo.toml"; then
    /usr/bin/sed -i '' "s|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = \[\"animation\", \"terrain\", \"pie\"\] }|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = [\"animation\", \"terrain\", \"pie\"] }\njackdaw_remote = { path = '$REPO/crates/jackdaw_remote' }|" "$PROJECT/Cargo.toml"
    grep -q jackdaw_remote "$PROJECT/Cargo.toml" || { log "PREP_FAIL no remote dep"; exit 1; }
    /usr/bin/sed -i '' 's|\.add_plugins(t15_anim::GamePlugin)|.add_plugins(t15_anim::GamePlugin)\n        .add_plugins(jackdaw_remote::JackdawRemotePlugin::default())|' "$PROJECT/src/main.rs"
    grep -q JackdawRemotePlugin "$PROJECT/src/main.rs" || { log "PREP_FAIL no remote plugin"; exit 1; }
    (cd "$PROJECT" && cargo metadata --format-version 1 >/dev/null 2>"$OUTDIR/lockfix.log") \
      || { log "PREP_FAIL lock refresh: $(tail -2 "$OUTDIR/lockfix.log")"; exit 1; }
  fi

  # Warm the game build so the game phase is not a cold compile.
  (cd "$PROJECT" && cargo build > "$OUTDIR/game-warmbuild-prep.log" 2>&1) \
    || { log "PREP_FAIL game warm build: $(tail -3 "$OUTDIR/game-warmbuild-prep.log")"; exit 1; }
  log "PREP_OK fixture=$PROJECT"
}

# ---- phase: editor ------------------------------------------------------------
an7_launcher_faces() {
  editor_boot   # no project: the launcher comes up
  sleep 4; walk
  # The Extensions page: Animation must not read "not in this editor".
  click_text "Extensions"; sleep 2; walk
  local a7=true
  if walk_has "not in this editor"; then
    jq -r '[.. | objects | select(.text? != null) | .text] | .[]' "$OUTDIR/walk-$PHASE.json" 2>/dev/null \
      | grep -B4 "not in this editor" | grep -qi animation && a7=false
  fi
  walk_has "Animation" || a7=false
  shot an7-extensions-page
  log "AN7 extensions page: Animation row present, phrase check -> $a7"
  leg AN7_EXTENSIONS_PAGE_CLEAN "$a7"
  # The New Project dialog: same claim for its Animation chip.
  click_text "New Project"; sleep 2; walk
  local a7np=true
  if walk_has "not in this editor"; then
    jq -r '[.. | objects | select(.text? != null) | .text] | .[]' "$OUTDIR/walk-$PHASE.json" 2>/dev/null \
      | grep -B4 "not in this editor" | grep -qi animation && a7np=false
  fi
  shot an7-new-project-chip
  leg AN7_NEW_PROJECT_CHIP_CLEAN "$a7np"
}

an7_and_l1() {
  local log="$OUTDIR/editor-$PHASE.log"
  # 1. the project-open warn is gone from the status bar/log channel.
  if grep -q "which this editor does not include" "$log"; then
    leg AN7_PROJECT_OPEN_QUIET false
  else
    leg AN7_PROJECT_OPEN_QUIET true
  fi
  # 2. the File>Modules picker: the Animation row carries no warning line.
  #    (Navmesh legitimately shows "does not include" — its tooling rides
  #    an extension this editor does not ship — so the claim is checked
  #    positionally: nothing between the Animation row and the dialog's
  #    tail may carry the warning.)
  op project.modules >/dev/null 2>&1
  sleep 3; walk
  local after_animation
  after_animation=$(jq -r '[.. | objects | select(.text? != null) | .text] | .[]' "$OUTDIR/walk-$PHASE.json" 2>/dev/null \
    | awk '/^Animation$/{seen=1} seen && /does not include this module/{print; exit}')
  local picker=true
  [ -n "$after_animation" ] && picker=false
  walk_has "Animation" || picker=false
  shot modules-picker-green
  log "AN7 picker: Animation row present, no warning at/after it -> $picker"
  leg AN7_MODULES_PICKER_CLEAN "$picker"
  op dialog.answer '{"choice":"0"}' >/dev/null 2>&1
  sleep 2
  # 3. L1: the module switch chain's disk artifacts (the picker face above
  #    is the editor side; T1's jd smoke proved the generation chain).
  local l1=true
  grep -q '^animation = true' "$PROJECT/jackdaw.toml" || l1=false
  grep -q '"animation"' "$PROJECT/Cargo.toml" || l1=false
  [ -f "$PROJECT/Cargo.lock" ] || l1=false
  log "L1 disk chain: jackdaw.toml animation=true + Cargo.toml features animation + lock ok=$l1"
  leg L1_MODULE_CHAIN "$l1"
}

l2_m1_chain() {
  # The set authoring chain, all through the operators the panel itself
  # dispatches: place the model, add the set, choose clips in the library
  # (the preview op is what a clip row click dispatches and it is what
  # marks the chosen clip), add as state, then switch states.
  open_scene scene.bsn
  local ok=true
  op entity.place_gltf '{"path":"models/hero.glb","pos_x":0.0,"pos_y":0.0,"pos_z":0.0}' >/dev/null 2>&1
  sleep 3; wait_idle 120 >/dev/null
  local rig
  rig=$(query_json '["bevy_ecs::name::Name"]' | jq -r '[.result[] | .components["bevy_ecs::name::Name"] | tostring | select(test("hero"; "i"))][0]' 2>/dev/null)
  [ -n "$rig" ] || { log "L2: placed model not found"; leg L2_M1_CHAIN false; return; }
  op selection.select "{\"name\":\"$rig\"}" >/dev/null 2>&1
  sleep 1
  op component.add "{\"entity\":\"$rig\",\"type_path\":\"$ASET\"}" >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  # choose each clip (the preview op marks it chosen), append as a state.
  for clip in Idle_Loop Walk_Loop Jump; do
    op animation.library.select '{"file":"models/hero.glb"}' >/dev/null 2>&1
    op animation.preview "{\"clip\":\"models/hero.glb#$clip\",\"entity\":\"$rig\"}" >/dev/null 2>&1
    sleep 1
    op animation.library.add_state >/dev/null 2>&1
    sleep 1; wait_idle 60 >/dev/null
  done
  local set states
  set=$(comp_of "$rig" "$ASET")
  states=$(echo "$set" | jq -r '[.states[].name] | join(",")' 2>/dev/null)
  log "L2: authored set states = [$states] (expect Idle_Loop,Walk_Loop,Jump)"
  [ "$states" = "Idle_Loop,Walk_Loop,Jump" ] || ok=false
  # state switching: write each state and read the wanted-state back.
  for st in Idle_Loop Walk_Loop Jump Idle_Loop; do
    op animation.set_state "{\"entity\":\"$rig\",\"state\":\"$st\"}" >/dev/null 2>&1
    sleep 1
    local got
    got=$(comp_of "$rig" "$ASTATE")
    [ "$got" = "\"$st\"" ] || { log "L2: set_state $st read back $got"; ok=false; }
  done
  op animation.set_state "{\"entity\":\"$rig\",\"state\":\"Idle_Loop\"}" >/dev/null 2>&1
  sleep 1
  shot l2-viewport-idle viewport
  op animation.set_state "{\"entity\":\"$rig\",\"state\":\"Jump\"}" >/dev/null 2>&1
  sleep 1
  shot l2-viewport-jump viewport
  op animation.set_state "{\"entity\":\"$rig\",\"state\":\"Idle_Loop\"}" >/dev/null 2>&1
  log "L2 M1 chain complete, ok=$ok"
  leg L2_M1_CHAIN "$ok"
}

l4_preview_borrow() {
  # Preview borrows the bound set's player; stop returns it and the set
  # plays its own state again (the borrow/return protocol live).
  local ok=true
  op animation.set_state '{"entity":"hero","state":"Idle_Loop"}' >/dev/null 2>&1
  sleep 1
  op animation.preview '{"clip":"models/hero.glb#Walk_Loop","entity":"hero"}' >/dev/null 2>&1
  sleep 2
  shot l4-preview-walking viewport
  op animation.preview.pause >/dev/null 2>&1
  sleep 1
  op animation.preview.stop >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  # the set still answers: switch it and read the write back.
  op animation.set_state '{"entity":"hero","state":"Jump"}' >/dev/null 2>&1
  sleep 1
  local got
  got=$(comp_of "hero" "$ASTATE")
  [ "$got" = "\"Jump\"" ] || { log "L4: set did not resume after the borrow ($got)"; ok=false; }
  op animation.set_state '{"entity":"hero","state":"Idle_Loop"}' >/dev/null 2>&1
  shot l4-set-resumed viewport
  log "L4 borrow/return complete, ok=$ok"
  leg L4_PREVIEW_BORROW_RETURN "$ok"
}

m9_preview_bad_refs() {
  # Bad file and bad clip named to the preview op: the editor warns and
  # the panel does not move (the red half lives in the log lines).
  local before after ok=false
  before=$(grep -c "animation.preview:" "$OUTDIR/editor-$PHASE.log" 2>/dev/null || true)
  op animation.preview '{"clip":"models/missing.glb#Walk_Loop","entity":"hero"}' >/dev/null 2>&1
  sleep 3
  op animation.preview '{"clip":"models/hero.glb#No_Such_Clip","entity":"hero"}' >/dev/null 2>&1
  sleep 3
  after=$(grep -c "animation.preview:" "$OUTDIR/editor-$PHASE.log" 2>/dev/null || true)
  grep "animation.preview:" "$OUTDIR/editor-$PHASE.log" 2>/dev/null | tail -4 > "$OUTDIR/m9-preview-warns.log"
  [ "${after:-0}" -ge "$(( ${before:-0} + 2 ))" ] && grep -q "could not be read" "$OUTDIR/m9-preview-warns.log" \
    && grep -q "holds no clip named" "$OUTDIR/m9-preview-warns.log" && ok=true
  log "M9 preview bad refs: warn lines $before->$after (need both forms; see m9-preview-warns.log)"
  leg M9_PREVIEW_BAD_REFS "$ok"
}

l3_m2_graph_chain() {
  # The graph authoring chain: new -> three states -> two params -> four
  # transitions -> entry -> save; then assign to the rig and drive the
  # preview by parameters.
  local ok=true
  open_scene graph.bsn
  sleep 2
  # Red half first: the rig's graphref names a file that is not there yet
  # (the badge and the runtime warn both speak).
  op selection.select '{"name":"Rig"}' >/dev/null 2>&1
  sleep 2; walk
  # the unread warn fires once the asset load fails, a few frames after
  # the scene lands; poll rather than read once.
  local redwait=0
  while [ $redwait -lt 20 ]; do
    grep "animation graph .* could not be read" "$OUTDIR/editor-$PHASE.log" 2>/dev/null \
      | tail -2 > "$OUTDIR/l3-graphref-red-warn.log"
    [ -s "$OUTDIR/l3-graphref-red-warn.log" ] && break
    sleep 1; redwait=$((redwait + 1))
  done
  [ -s "$OUTDIR/l3-graphref-red-warn.log" ] || ok=false
  shot badge-graphref-red
  # Author the graph.
  op animation.graph.new '{"name":"hero_graph"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  op animation.graph.add_state '{"name":"idle","clip":"models/hero.glb#Idle_Loop","loop":true}' >/dev/null 2>&1
  op animation.graph.add_state '{"name":"walk","clip":"models/hero.glb#Walk_Loop","loop":true}' >/dev/null 2>&1
  op animation.graph.add_state '{"name":"jump","clip":"models/hero.glb#Jump","loop":false}' >/dev/null 2>&1
  op animation.graph.add_param '{"name":"Speed","kind":"float","default":0}' >/dev/null 2>&1
  op animation.graph.add_param '{"name":"Jump","kind":"trigger"}' >/dev/null 2>&1
  op animation.graph.add_transition '{"from":"idle","to":"walk","when":"Speed > 0.5"}' >/dev/null 2>&1
  op animation.graph.add_transition '{"from":"walk","to":"idle","when":"Speed < 0.5"}' >/dev/null 2>&1
  op animation.graph.add_transition '{"from":"idle","to":"jump","when":"Jump"}' >/dev/null 2>&1
  op animation.graph.add_transition '{"from":"jump","to":"idle","exit_time":1.0}' >/dev/null 2>&1
  op animation.graph.set_entry '{"name":"idle"}' >/dev/null 2>&1
  op animation.graph.save >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  local graph_file="$PROJECT/assets/animation/hero_graph.animgraph.bsn"
  [ -f "$graph_file" ] || { log "L3: graph file did not land"; leg L3_M2_GRAPH_CHAIN false; return; }
  grep -q "Speed" "$graph_file" && grep -q "jump" "$graph_file" || ok=false
  grep -q 'entry: "idle"' "$graph_file" || ok=false
  # Assign it to the selected rig; the badge turns green.
  op animation.graph.assign '{"path":"animation/hero_graph.animgraph.bsn"}' >/dev/null 2>&1
  sleep 3; wait_idle 120 >/dev/null
  # If the edited-graph rebind did not reach it, a reopen does.
  if [ -z "$(graph_state)" ]; then
    log "L3: playback not live yet; reopening the scene"
    open_scene graph.bsn
    sleep 2
  fi
  local ref
  ref=$(comp_of Rig "$AGRAPHREF")
  echo "$ref" | grep -q "hero_graph.animgraph.bsn" || { log "L3: ref reads $ref"; ok=false; }
  walk
  local badge_gone=true
  walk_has "no graph file named" && badge_gone=false
  shot badge-graphref-green
  log "L3: graph assigned, badge cleared=$badge_gone, ref=$ref"
  leg L3_M2_GRAPH_CHAIN "$ok"
}

l3_param_drives_preview() {
  # The editor-side parity leg: parameters steer the graph playing in the
  # viewport, and the one-shot jump falls back to idle on its own.
  local seq="$OUTDIR/parity-editor.json"
  : > "$seq"
  local ok=true deadline walk_state fell
  # entry state
  deadline=$((SECONDS + 20))
  until [ "$(graph_state)" = "idle" ]; do
    if [ $SECONDS -ge $deadline ]; then break; fi
    sleep 1
  done
  [ "$(graph_state)" = "idle" ] || { log "L3 parity: entry state never became idle ($(graph_state))"; ok=false; }
  echo "$(sample_graph_game entry)" >> "$seq"
  # Speed -> walk
  op animation.graph.set_param '{"name":"Speed","value":1}' >/dev/null 2>&1
  sleep 3
  [ "$(graph_state)" = "walk" ] || { log "L3 parity: Speed=1 gave $(graph_state) (want walk)"; ok=false; }
  echo "$(sample_graph_game speed1)" >> "$seq"
  # Speed -> idle
  op animation.graph.set_param '{"name":"Speed","value":0}' >/dev/null 2>&1
  sleep 3
  [ "$(graph_state)" = "idle" ] || { log "L3 parity: Speed=0 gave $(graph_state) (want idle)"; ok=false; }
  echo "$(sample_graph_game speed0)" >> "$seq"
  # trigger -> jump, then the one-shot falls back to idle by itself
  op animation.graph.set_param '{"name":"Jump","value":1}' >/dev/null 2>&1
  # the one-shot jump holds only ~0.95s (0.8s clip + fade); sample inside
  # the window, not after it.
  sleep 0.4
  walk_state="$(graph_state)"
  [ "$walk_state" = "jump" ] || { log "L3 parity: trigger gave $walk_state (want jump)"; ok=false; }
  echo "$(sample_graph jump)" >> "$seq"
  fell=idle
  deadline=$((SECONDS + 10))
  until [ "$(graph_state)" = "idle" ]; do
    if [ $SECONDS -ge $deadline ]; then fell=never; break; fi
    sleep 1
  done
  [ "$fell" = "idle" ] || { log "L3 parity: one-shot never fell back ($fell)"; ok=false; }
  echo "$(sample_graph_game fallback)" >> "$seq"
  # park on walk for the screenshot only — the parity record above stays
  # the canonical five-sample sequence every channel replays.
  op animation.graph.set_param '{"name":"Speed","value":1}' >/dev/null 2>&1
  sleep 2
  op animation.graph.set_param '{"name":"Speed","value":0}' >/dev/null 2>&1
  shot l3-graph-window
  log "L3 param-driven preview sequence: $(tr '\n' ' ' < "$seq")"
  leg L3_PARAM_DRIVES_PREVIEW "$ok"
}

l8_badge_forms() {
  # The author-side badge three forms plus the all-good zero-noise form.
  # The badge texts (set_reference_problems / the graphref card):
  #   form 1  "animation state `ghost_clip` wants clip `No_Such_Clip`, ..."
  #   form 2  "animation state `off_range` names source 2, and the set
  #            lists 2 sources"
  #   form 3  "no graph file named `animation/nope.bsn` in this project"
  open_scene bad.bsn
  sleep 3
  local ok=true
  op selection.select '{"name":"BadSet"}' >/dev/null 2>&1
  sleep 2; walk
  walk_has "wants clip" || ok=false
  walk_has "No_Such_Clip" || ok=false
  shot badge-set-ghost-clip
  walk_has "names source 2" || ok=false
  shot badge-set-source-bad
  op selection.select '{"name":"BadGraph"}' >/dev/null 2>&1
  sleep 2; walk
  walk_has "no graph file named" || ok=false
  shot badge-graphref-form3
  # The bad scene's permanently-unresolvable references keep the bind
  # systems retrying every frame (the AN9 churn); close its tab (it is
  # the active one) before the remaining legs run on the editor.
  op scene.close >/dev/null 2>&1
  sleep 2; dismiss_dialog
  # the all-good form: the same cards on a clean rig carry no error rows.
  open_scene graph.bsn
  sleep 2
  op selection.select '{"name":"Rig"}' >/dev/null 2>&1
  sleep 2; walk
  local clean=true
  walk_has "wants clip" && clean=false
  walk_has "no graph file named" && clean=false
  walk_has "names source" && clean=false
  shot badge-good-clean
  log "L8 badge forms: three red forms=$ok, clean rig zero rows=$clean; bad.bsn tab closed"
  leg L8_BADGE_THREE_FORMS "$ok"
  leg L8_GOOD_CARD_CLEAN "$clean"
}

l9_stop_invariant() {
  # Stop restores: the scene document does not change across a PIE run,
  # the editor's own set keeps playing (AN5, recorded), and after Stop
  # the set still answers. State names are anim.bsn's own (lowercase).
  open_scene anim.bsn
  sleep 2
  local ok=true
  local sha_before
  sha_before=$(shasum -a 256 "$PROJECT/assets/anim.bsn" | awk '{print $1}')
  op animation.set_state '{"entity":"Rig","state":"walk"}' >/dev/null 2>&1
  sleep 1
  op pie.play_current >/dev/null 2>&1
  wait_game 900 || { log "L9: PIE game never came up"; leg L9_STOP_INVARIANT false; stop_game; return; }
  sleep 3
  # AN5: the editor's own rig is still bound and answering mid-PIE.
  local mid
  op animation.set_state '{"entity":"Rig","state":"idle"}' >/dev/null 2>&1
  sleep 1
  mid=$(comp_of Rig "$ASTATE")
  [ "$mid" = "\"idle\"" ] || { log "L9/AN5: editor set refused writes mid-PIE ($mid)"; ok=false; }
  log "AN5 witness: the editor world's own set answered set_state mid-PIE (read back $mid)"
  stop_game
  sleep 2
  local sha_after
  sha_after=$(shasum -a 256 "$PROJECT/assets/anim.bsn" | awk '{print $1}')
  [ "$sha_before" = "$sha_after" ] || { log "L9: anim.bsn sha changed across PIE"; ok=false; }
  op animation.set_state '{"entity":"Rig","state":"walk"}' >/dev/null 2>&1
  sleep 1
  local resumed
  resumed=$(comp_of Rig "$ASTATE")
  [ "$resumed" = "\"walk\"" ] || { log "L9: set did not resume after stop ($resumed)"; ok=false; }
  log "L9 stop invariant: sha stable=$([ "$sha_before" = "$sha_after" ] && echo y || echo n), set resumes=$resumed"
  leg L9_STOP_INVARIANT "$ok"
}

m13_reopen() {
  # Save, reopen, the authored configuration survives (set states, graph
  # reference) while the runtime writes (AnimationState) stay out.
  local ok=true
  open_scene scene.bsn
  sleep 2
  local set_before
  set_before=$(comp_of "hero" "$ASET")
  op scene.save >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  open_scene scene.bsn
  sleep 2
  local set_after
  set_after=$(comp_of "hero" "$ASET")
  [ "$set_before" = "$set_after" ] || { log "M13: scene.bsn set changed across save/reopen"; ok=false; }
  echo "$set_after" | grep -q "Jump" || ok=false
  open_scene graph.bsn
  sleep 2
  local ref_before ref_after
  ref_before=$(comp_of Rig "$AGRAPHREF")
  op scene.save >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  open_scene graph.bsn
  sleep 2
  ref_after=$(comp_of Rig "$AGRAPHREF")
  [ "$ref_before" = "$ref_after" ] || { log "M13: graph ref changed across save/reopen"; ok=false; }
  echo "$ref_after" | grep -q "hero_graph" || ok=false
  log "M13 reopen: set states kept, graph ref kept ($ref_after), ok=$ok"
  leg M13_REOPEN_CONSISTENT "$ok"
}

editor_phase() {
  write_scenes   # canonical prep state for every editor segment
  an7_launcher_faces
  editor_boot "$PROJECT"
  an7_and_l1
  l2_m1_chain
  l4_preview_borrow
  m9_preview_bad_refs
  l3_m2_graph_chain
  l3_param_drives_preview
  l8_badge_forms
  l9_stop_invariant
  m13_reopen

  # The standing warn scan over this phase's editor log. The known AN7
  # line must NOT appear (the fix landed); animation-domain warn forms
  # are attributed in the archived per-leg logs.
  sleep 2
  local log="$OUTDIR/editor-$PHASE.log"
  local an7_warns refused n13
  an7_warns=$(grep -Ec "which this editor does not include" "$log" 2>/dev/null)
  refused=$(grep -Ec "Cannot spawn scene" "$log" 2>/dev/null)
  n13=$(grep -c "panicked at" "$log" 2>/dev/null)
  log "WARN_SCAN editor phase: an7_lines=${an7_warns:-0} refused_lines=${refused:-0} (N13 PIE panics counted: ${n13:-0})"
  grep -Ein "animation|clip|graph" "$log" 2>/dev/null | grep -Ei "warn|error|fail|missing|not found|unresolved" \
    > "$OUTDIR/animation-warn-lines-editor.log" || true
  [ "${an7_warns:-0}" = "0" ] || leg WARN_SCAN_EDITOR false
  [ "${refused:-0}" = "0" ] || leg WARN_SCAN_EDITOR false
  leg WARN_SCAN_EDITOR true
  printf '%s\n' "$(results)" > "$OUTDIR/summary-editor.txt"
  log "VERDICT_EDITOR_PHASE: $(results)"
}

# ---- phase: game ------------------------------------------------------------
l5_set_leg() {
  local ok=true
  open_scene anim.bsn
  sleep 2
  op pie.play_current >/dev/null 2>&1
  wait_game 900 || { log "L5: PIE game never came up"; leg L5_SET_STATE_FOLLOWS false; stop_game; return 1; }
  game_ready 180
  sleep 4
  local rig id set
  rig=$(gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null \
    | jq -r '[.result[] | .components["bevy_ecs::name::Name"] | tostring | select(. == "Rig")][0]')
  id=$(gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null \
    | jq -r '[.result[] | select(.components["bevy_ecs::name::Name"] == "Rig") | .entity][0]')
  set=$(gbrp world.query "{\"data\":{\"components\":[\"bevy_ecs::name::Name\",\"$ASET\"]}}" 2>/dev/null \
    | jq -c --arg t "$ASET" '[.result[] | select(.components["bevy_ecs::name::Name"] == "Rig") | .components[$t]][0]' 2>/dev/null)
  log "L5 set: game rig=$rig id=$id states=$(echo "$set" | jq -r '[.states[].name] | join(",")' 2>/dev/null)"
  echo "$set" | jq -e '.default_state == "idle"' >/dev/null 2>&1 || ok=false
  # M3 numeric half: the bind writes the default state into the component,
  # so the wanted-state read IS the playing-state read.
  local default_read
  default_read=$(gbrp world.get_components "{\"entity\":$id,\"components\":[\"$ASTATE\"]}" 2>/dev/null \
    | jq -c --arg t "$ASTATE" '.result.components[$t] // empty' 2>/dev/null)
  log "L5 set: bind-written default read = $default_read"
  echo "$default_read" | grep -qF '"idle"' || ok=false
  # the write channel: the game's AnimationState follows the BRP write.
  local got
  got=$(ginsert_verify "$id" "$ASTATE" '"walk"')
  [ "$got" = "\"walk\"" ] || { log "L5 set: written walk read back $got"; ok=false; }
  echo "L5_SET_WALK_READBACK $got" >> "$OUTDIR/l5-set-witness.txt"
  leg L5_SET_STATE_FOLLOWS "$ok"
}

l7_bad_clip() {
  # M10: a state naming a clip the file does not carry warns in the
  # running game and the Game panel shows the entry; the fix clears it.
  local ok=true
  python3 - "$PROJECT/assets/anim.bsn" << 'PYT'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace('clip: "Walk_Loop"', 'clip: "No_Such_Clip"')
open(path, "w").write(text)
PYT
  grep -q "No_Such_Clip" "$PROJECT/assets/anim.bsn" || ok=false
  stop_game
  open_scene anim.bsn   # reread the edited scene
  sleep 2
  op pie.play_current >/dev/null 2>&1
  wait_game 900 || { log "L7: PIE never came up"; leg L7_BAD_CLIP_PIE_LOG false; stop_game; return 1; }
  game_ready 180
  sleep 4
  local id
  id=$(gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null \
    | jq -r '[.result[] | select(.components["bevy_ecs::name::Name"] == "Rig") | .entity][0]')
  ginsert "$id" "$ASTATE" '"walk"'
  sleep 3
  local panel_ok=false
  game_log_lines | grep -q "wants clip" && panel_ok=true
  shot l7-game-panel-warn
  log "L7 red: Game panel carries the wants-clip warn=$panel_ok ($(game_log_lines | grep 'wants clip' | head -1))"
  # green half: fix the clip, the warn does not reappear.
  python3 - "$PROJECT/assets/anim.bsn" << 'PYT'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace('clip: "No_Such_Clip"', 'clip: "Walk_Loop"')
open(path, "w").write(text)
PYT
  stop_game
  open_scene anim.bsn
  sleep 2
  op pie.play_current >/dev/null 2>&1
  wait_game 300 || { log "L7: PIE never came up (green)"; leg L7_BAD_CLIP_PIE_LOG false; stop_game; return 1; }
  game_ready 180
  sleep 4
  id=$(gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null \
    | jq -r '[.result[] | select(.components["bevy_ecs::name::Name"] == "Rig") | .entity][0]')
  ginsert "$id" "$ASTATE" '"walk"'
  sleep 3
  local green_lines
  green_lines=$(game_log_lines | grep -c "wants clip")
  shot l7-game-panel-clean
  [ "${green_lines:-0}" = "0" ] || { log "L7 green: $green_lines wants-clip lines still up"; ok=false; }
  [ "$panel_ok" = "true" ] || ok=false
  log "L7: red panel warn seen=$panel_ok, green panel lines=$green_lines"
  leg L7_BAD_CLIP_PIE_LOG "$ok"
}

graph_drive_sequence() { # graph_drive_sequence <tag> — drive+sample the graph in the running game
  local tag="$1"
  local seq="$OUTDIR/parity-$tag.json"
  : > "$seq"
  local ok=true id deadline
  id=$(gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null \
    | jq -r '[.result[] | select(.components["bevy_ecs::name::Name"] == "Rig") | .entity][0]')
  [ -n "$id" ] || { log "graph seq $tag: no Rig in the game world"; echo FAIL > "$seq"; return 1; }
  deadline=$((SECONDS + 20))
  until [ "$(graph_state_game)" = "idle" ]; do
    if [ $SECONDS -ge $deadline ]; then break; fi
    sleep 1
  done
  [ "$(graph_state_game)" = "idle" ] || { log "graph seq $tag: entry $(graph_state_game) != idle"; ok=false; }
  echo "$(sample_graph_game entry)" >> "$seq"
  # Speed=1 -> walk (insert the whole params component, bevy native)
  gdrive "$id" '{"values":{"Speed":1.0},"pending":[]}' walk \
    || { log "graph seq $tag: Speed=1 never reached walk ($(graph_state_game))"; ok=false; }
  echo "$(sample_graph_game speed1)" >> "$seq"
  # M7 loop: two samples more than a clip duration apart, state constant
  echo "$(sample_graph_game walk-loop-a)" >> "$seq"
  sleep 2
  echo "$(sample_graph_game walk-loop-b)" >> "$seq"
  local w1 w2
  w1=$(sed -n '3p' "$seq" | jq -r .state); w2=$(sed -n '4p' "$seq" | jq -r .state)
  [ "$w1" = "walk" ] && [ "$w2" = "walk" ] \
    || { log "graph seq $tag: walk did not hold across the loop window ($w1/$w2)"; ok=false; }
  # Speed=0 -> idle
  gdrive "$id" '{"values":{"Speed":0.0},"pending":[]}' idle \
    || { log "graph seq $tag: Speed=0 never reached idle ($(graph_state_game))"; ok=false; }
  echo "$(sample_graph_game speed0)" >> "$seq"
  # trigger Jump -> jump, then the fall-back
  ginsert "$id" "$APARAMS" '{"values":{},"pending":["Jump"]}'
  sleep 0.5
  echo "$(sample_graph_game jump-early)" >> "$seq"
  sleep 0.5
  echo "$(sample_graph_game jump-held)" >> "$seq"
  local fell=idle
  deadline=$((SECONDS + 10))
  until [ "$(graph_state_game)" = "idle" ]; do
    if [ $SECONDS -ge $deadline ]; then fell=never; break; fi
    sleep 1
  done
  [ "$fell" = "idle" ] || { log "graph seq $tag: no fall-back ($fell)"; ok=false; }
  echo "$(sample_graph_game fallback)" >> "$seq"
  echo "$ok" > "$OUTDIR/parity-$tag.ok"
  log "graph seq $tag: $(tr '\n' ' ' < "$seq")"
  [ "$ok" = "true" ] && return 0 || return 1
}


sample_graph_game() { # sample_graph_game <label> — one playback sample from the game world
  local id json
  id=$(gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null \
    | jq -r '[.result[]? | select(.components["bevy_ecs::name::Name"] == "Rig") | .entity][0]' 2>/dev/null)
  [ -n "$id" ] || { echo "{\"label\":\"$1\",\"state\":\"MISSING\",\"since\":0,\"transition\":null}"; return; }
  json=$(gbrp world.get_components "{\"entity\":$id,\"components\":[\"$APLAYBACK\"]}" 2>/dev/null \
    | jq -c --arg t "$APLAYBACK" '.result.components[$t] // {}' 2>/dev/null)
  echo "$json" | jq -c --arg l "$1" '{label:$l, state:(.state // ""), since:(.since_secs // 0), transition:(.transition // null)}' 2>/dev/null
}

gdrive() { # gdrive <id> <params-json> <expected-state> — insert until the graph moves
  local id="$1" json="$2" want="$3" n got
  for n in 1 2 3; do
    ginsert "$id" "$APARAMS" "$json"
    local waited=0
    while [ $waited -lt 6 ]; do
      got=$(graph_state_game)
      [ "$got" = "$want" ] && return 0
      sleep 1; waited=$((waited + 1))
    done
  done
  return 1
}

sequence_states() { # sequence_states <parity-file> — consecutive-duplicate states collapsed
  jq -r '.state' "$1" 2>/dev/null | awk 'NR == 1 || $0 != prev { print } { prev = $0 }' | tr '\n' ','
}

l5_graph_and_m7() {
  local ok=true
  open_scene graph.bsn
  sleep 2
  op pie.play_current >/dev/null 2>&1
  wait_game 900 || { log "L5 graph: PIE never came up"; leg L5_GRAPH_PARAMS false; stop_game; return 1; }
  game_ready 180
  sleep 4
  graph_drive_sequence pie || ok=false
  # M7 transition face: trigger again and catch the crossfade field.
  local id caught=none n=0 tr
  id=$(gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null \
    | jq -r '[.result[] | select(.components["bevy_ecs::name::Name"] == "Rig") | .entity][0]')
  ginsert "$id" "$APARAMS" '{"values":{},"pending":["Jump"]}'
  sleep 1
  # a trigger eaten by the empty-body window never moves the graph; the
  # state then still reads walk/idle and the insert goes out again.
  local st
  st=$(graph_state_game)
  if [ "$st" != "jump" ] && [ "$st" != "idle" ]; then
    ginsert "$id" "$APARAMS" '{"values":{},"pending":["Jump"]}'
    sleep 1
  fi
  while [ $n -lt 12 ]; do
    tr=$(graph_transition_game)
    if [ -n "$tr" ] && [ "$tr" != "null" ] && [ "$tr" != "empty" ]; then caught="$tr"; break; fi
    sleep 0.5; n=$((n + 1))
  done
  log "M7 transition witness: crossfade field caught = $caught"
  echo "M7_TRANSITION_WITNESS $caught" > "$OUTDIR/m7-transition-witness.txt"
  echo "$caught" | grep -q "jump\|idle" || ok=false
  leg L5_GRAPH_PARAMS "$ok"
}

l6_parity() {
  # The editor sequence (recorded in the editor phase) replayed through
  # PIE, the direct run and the staged export.
  local ok=true
  local ed="$OUTDIR/parity-editor.json"
  [ -s "$ed" ] || { log "L6: the editor sequence is missing"; leg L6_PARITY_FOUR_CHANNELS false; return; }
  local want pie_states direct_states staged_states
  want=$(sequence_states "$ed")
  log "L6 editor sequence: $want"
  pie_states=$(sequence_states "$OUTDIR/parity-pie.json")
  [ "$pie_states" = "$want" ] || { log "L6: PIE states $pie_states != editor $want"; ok=false; }
  stop_game
  # direct run: the flow's start scene plays the graph rig.
  flow_start_scene "graph.bsn"
  (cd "$PROJECT" && nohup cargo run > "$OUTDIR/direct-run.log" 2>&1 &)
  wait_game 900 || { log "L6: direct run never came up"; ok=false; }
  game_ready 180
  if game_up; then
    sleep 4
    graph_drive_sequence direct || ok=false
    direct_states=$(sequence_states "$OUTDIR/parity-direct.json")
    [ "$direct_states" = "$want" ] || { log "L6: direct states $direct_states != editor $want"; ok=false; }
  fi
  pkill -x t15-anim 2>/dev/null; sleep 2
  # staged export replays the same scene from the packaged tree.
  export_wait || { log "L6: export never became ready"; ok=false; }
  [ -x "$STAGED_EXE" ] || ok=false
  if [ -x "$STAGED_EXE" ]; then
    (cd "$STAGED" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./t15-anim > "$OUTDIR/staged-run.log" 2>&1 &)
    wait_game 300 || { log "L6: staged game never came up"; ok=false; }
  game_ready 180
    if game_up; then
      sleep 4
      graph_drive_sequence staged || ok=false
      staged_states=$(sequence_states "$OUTDIR/parity-staged.json")
      [ "$staged_states" = "$want" ] || { log "L6: staged states $staged_states != editor $want"; ok=false; }
    fi
    pkill -x t15-anim 2>/dev/null; sleep 2
  fi
  flow_start_scene "anim.bsn"   # restore the canonical start scene
  log "L6 parity: editor=$want pie=$pie_states direct=$direct_states staged=$staged_states"
  leg L6_PARITY_FOUR_CHANNELS "$ok"
}

l10_export() {
  # The export carries the graph file and the model; the manifest lists both.
  local ok=true a b
  [ -f "$STAGED/assets/animation/hero_graph.animgraph.bsn" ] || { log "L10: staged graph file missing"; ok=false; }
  [ -f "$STAGED/assets/models/hero.glb" ] || { log "L10: staged model missing"; ok=false; }
  jq -r '.files[].path' "$STAGED/export-manifest.json" 2>/dev/null | grep -q "hero_graph.animgraph.bsn" \
    || { log "L10: manifest lacks the graph"; ok=false; }
  jq -r '.files[].path' "$STAGED/export-manifest.json" 2>/dev/null | grep -q "models/hero.glb" \
    || { log "L10: manifest lacks the model"; ok=false; }
  a=$(shasum -a 256 "$PROJECT/assets/animation/hero_graph.animgraph.bsn" 2>/dev/null | awk '{print $1}')
  b=$(shasum -a 256 "$STAGED/assets/animation/hero_graph.animgraph.bsn" 2>/dev/null | awk '{print $1}')
  [ -n "$a" ] && [ "$a" = "$b" ] || { log "L10: staged graph sha mismatch"; ok=false; }
  log "L10 export: graph+model staged, manifest lists them, sha equal=$([ "$a" = "$b" ] && echo y || echo n)"
  leg L10_EXPORT_CONSISTENT "$ok"
}

game_phase() {
  editor_boot "$PROJECT"
  editor_build_settled 300
  l5_set_leg
  l7_bad_clip
  l5_graph_and_m7
  l6_parity
  l10_export

  # The game phase's own output: the standing warn scan + N13 count.
  sleep 2
  local log="$OUTDIR/editor-$PHASE.log"
  local an7_warns refused n13
  an7_warns=$(grep -Ec "which this editor does not include" "$log" 2>/dev/null)
  refused=$(grep -Ec "Cannot spawn scene" "$log" 2>/dev/null)
  n13=$(grep -c "panicked at" "$log" 2>/dev/null)
  log "WARN_SCAN game phase: an7_lines=${an7_warns:-0} refused_lines=${refused:-0} (N13 PIE panics counted: ${n13:-0})"
  grep -n "panicked at" "$log" 2>/dev/null | head -5 >> "$OUTDIR/n13-count.txt" || true
  grep -Ein "animation|clip|graph" "$log" 2>/dev/null | grep -Ei "warn|error|fail|missing|not found|unresolved" \
    > "$OUTDIR/animation-warn-lines-game.log" || true
  [ "${an7_warns:-0}" = "0" ] || leg WARN_SCAN_GAME false
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
    log "T15_LIVE_DONE"
    ;;
  *) echo "unknown phase: $PHASE (prep|editor|game|all)"; exit 2 ;;
esac
