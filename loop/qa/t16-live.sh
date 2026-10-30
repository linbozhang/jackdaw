#!/bin/bash
# T16-T2 live matrix: the audio workflow's live legs on the Mac fixture
# (the green-state t16-audio fixture task 1 left, plus jackdaw_remote
# injected and two authored probe sounds in scene.bsn). Log names follow
# $PHASE everywhere (the A7 stale-grep lesson); every planned red state
# lands in *_red.log before the fix rerun (the T1 QA reflow discipline).
#
# Phases (each phase boots and cleans its own editor/game processes —
# run one per invocation, or `all`):
#   prep    verify the fixture's green state, write scene.bsn (the
#           starter scene plus the #MusicProbe/#SfxProbe authored loop
#           sounds), inject jackdaw_remote (two-line sed), refresh the
#           lock, warm-build the game, reset the flow start scene.
#   editor  L1/M1 (the authorization chain: add.audio_source -> asset-row
#           Pick -> PlaybackSettings Loop -> save -> reopen, four pieces
#           + marker), M7's auth face (asset.new GameAudioConfig, card
#           edit machine), M14's editor half (GlobalVolume 0.0 witness,
#           PlaybackSettings readable, screenshots), M13 warn scan.
#   game    L2 (afplay control), L3/M2 (BGM live numbers + master-mute
#           live), M3-direct (ScreenPressed chain: blip count + flow
#           move = stop word), L5/M4 (spatial scene + listener + walk),
#           L9/M9/M10 (bus routing live numbers), M7's play face (config
#           edit reaches the running mix), L7/M6 (bad reference red/
#           green), L4/M3 (PIE real click on Start, blip caught, flow
#           moves), L10/M11 (stop invariant), L6/M5 (staged export
#           carries and replays the three sounds), the warn scan and
#           the N13 count.
# Usage: bash loop/qa/t16-live.sh [phase]   phase: prep|editor|game|all
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
FIXROOT=/Users/zhanglinbo/workspace/loop-mac/t16-audio
PROJECT="$FIXROOT/t16-audio"
PORT=15703
GAME_PORT=15702
OUTDIR="$REPO/loop/t16-live"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
STAGED="$PROJECT/.jackdaw/dist/release"
STAGED_EXE="$STAGED/t16-audio"
APLAYER='bevy_audio::audio::AudioPlayer<bevy_audio::audio_source::AudioSource>'
PSET='bevy_audio::audio::PlaybackSettings'
SLIVE='t16_audio::SoundLive'
GACONFIG='t16_audio::GameAudioConfig'
SLISTEN='bevy_audio::audio::SpatialListener'
GTRANS='bevy_transform::components::global_transform::GlobalTransform'
GLOBALVOL='bevy_audio::volume::GlobalVolume'
NAME='bevy_ecs::name::Name'
KB_MSG='bevy_input::keyboard::KeyboardInput'
mkdir -p "$OUTDIR"
PHASE="${1:-all}"
CONSOLE_LOG="$OUTDIR/console-$PHASE.log"
: > "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t16-live.XXXXXX)"
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
  pkill -x t16-audio 2>/dev/null
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
  # Reads ride the flaky window (AN9): retry until a parseable body
  # comes back. Callers that mutate go through brp_raw/op — an op
  # executes even when its response comes back empty.
  local method="$1" params="${2:-}"
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
  local method="$1" params="${2:-}" id=$RANDOM body out attempt
  if [ -n "$params" ]; then
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params")
  else
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s"}' "$id" "$method")
  fi
  # The game BRP answers intermittently empty in busy windows (A9):
  # reads retry with a short settle; writes go through gbrp_write which
  # verifies through a read.
  for attempt in 1 2 3; do
    out=$(curl -s -m 30 -X POST "http://127.0.0.1:$GAME_PORT/" -H 'Content-Type: application/json' -d "$body")
    if [ -n "$out" ] && ! echo "$out" | grep -q "expected value at line 1"; then
      echo "$out"
      return 0
    fi
    sleep 2
  done
  echo "$out"
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
  pkill -x t16-audio 2>/dev/null
  sleep 2
}
editor_boot() { # editor_boot [project]
  pkill -x jackdaw 2>/dev/null; pkill -x t16-audio 2>/dev/null; sleep 1
  local boot_log="$OUTDIR/editor-$PHASE.log"
  if [ -n "${1:-}" ]; then
    export JACKDAW_OPEN_PROJECT="$1"
  else
    unset JACKDAW_OPEN_PROJECT
  fi
  export JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1600x1000
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
  wait_idle 900 >/dev/null; sleep 3; dismiss_dialog
  # A hard-killed previous phase leaves the crash-journal modal up; it
  # blocks every pointer gesture, so discard it before any leg.
  walk
  if walk_has "Recovered Work"; then
    click_text "Discard All" >/dev/null
    sleep 2; wait_idle 120 >/dev/null
    walk
    walk_has "Recovered Work" && { log "EDITOR_BOOT_FAIL recovery modal survived"; exit 1; }
  fi
  log "EDITOR_READY project=${1:-none}"
}
open_scene() {
  # reload: true — an already-open tab rereads the file, which the disk
  # edits in the bad-reference leg and the save/reopen legs rely on.
  op scene.open "{\"path\":\"$PROJECT/assets/$1\",\"reload\":true}" >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
}
walk() { brp jackdaw/ui_tree '{"depth":60}' > "$OUTDIR/walk-$PHASE.json" 2>/dev/null; }
walk_has() { grep -qF "$1" "$OUTDIR/walk-$PHASE.json" 2>/dev/null; }
click_text() {
  brp jackdaw/ui_click "{\"text\":\"$1\"}" 2>/dev/null | jq -r '.result.clicked // false' 2>/dev/null
}
shot() { # shot <name> [kind]
  local name="$1" kind="${2:-window}"
  local rel path out out_json
  rel="screenshots/t16-$name.png"
  path="$PROJECT/$rel"
  rm -f "$path"
  for i in $(seq 1 20); do
    out_json=$(curl -s -m 12 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
      -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"jackdaw/screenshot\",\"params\":{\"kind\":\"$kind\",\"path\":\"$rel\",\"request\":\"$name\"}}" 2>/dev/null)
    out=$(echo "$out_json" | jq -r '.result.path // empty' 2>/dev/null)
    if [ -n "$out" ] && [ -s "$path" ]; then
      # A later phase's canonical reset clears the project's screenshots
      # dir; the evidence copy here is what the archive keeps.
      cp "$path" "$OUTDIR/shot-$name.png" 2>/dev/null
      log "shot $name ok ($kind)"
      return 0
    fi
    sleep 1
  done
  screencapture -x "$path" 2>/dev/null && [ -s "$path" ] \
    && { cp "$path" "$OUTDIR/shot-$name.png" 2>/dev/null; log "shot $name ok (os screencapture fallback)"; return 0; }
  log "shot $name FAILED (capture never landed)"
  return 1
}
game_ready() { # game_ready [timeout] — wait until the game's world.* answers
  local deadline=$((SECONDS + ${1:-180}))
  while [ $SECONDS -lt $deadline ]; do
    if gbrp world.query "{\"data\":{\"components\":[\"$NAME\"]}}" 2>/dev/null \
       | jq -e '.result' >/dev/null 2>&1; then
      return 0
    fi
    sleep 3
  done
  log "GAME_READY timeout: the game BRP never answered world.query"
  return 1
}
editor_build_settled() { # editor_build_settled [timeout]
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
direct_run() { # direct_run <tag> — cargo run the fixture, log to direct-<tag>.log
  (cd "$PROJECT" && nohup cargo run > "$OUTDIR/direct-$1.log" 2>&1 &)
  wait_game 600 || { log "direct_run $1: game never came up"; return 1; }
  game_ready 240
  sleep 3
}
gid() { # gid <name> — the game entity id carrying this Name
  gbrp world.query "{\"data\":{\"components\":[\"$NAME\"]}}" 2>/dev/null \
    | jq -r --arg n "$1" '[.result[]? | select(.components["'"$NAME"'"] == $n) | .entity][0]' 2>/dev/null
}
gcomp() { # gcomp <name> <component> — the named game entity's component JSON
  local id="$1" out attempt
  [ -n "$id" ] || return 0
  for attempt in 1 2 3 4; do
    out=$(gbrp world.get_components "{\"entity\":\"$id\",\"components\":[\"$2\"]}" 2>/dev/null \
      | jq -c --arg c "$2" '.result.components[$c] // .result[$c] // empty' 2>/dev/null)
    [ -n "$out" ] && { echo "$out"; return 0; }
    sleep 2
  done
  echo "$out"
}
# The SoundLive mirror rides one frame behind the sink (T1 口径): wait
# until it appears, then return it. Empty after the budget = the honest
# "no sink" answer (the M6 red half reads exactly that).
gsound_wait() { # gsound_wait <name> [attempts]
  local n=0 out want="${2:-10}"
  while [ $n -lt "$want" ]; do
    out=$(gcomp "$(gid "$1")" "$SLIVE" 2>/dev/null)
    [ -n "$out" ] && [ "$out" != "null" ] && { echo "$out"; return 0; }
    sleep 1.5
    n=$((n + 1))
  done
  echo ""
  return 1
}
gsound() { gcomp "$(gid "$1")" "$SLIVE" 2>/dev/null; }
sfx_count() { # sfx_count — entities whose mirror says kind=sfx (small response: name+SoundLive)
  gbrp world.query "{\"data\":{\"components\":[\"$SLIVE\"]}}" 2>/dev/null \
    | jq -r '[.result[]? | select(.components["'"$SLIVE"'"].kind? == "sfx")] | length' 2>/dev/null
}
sound_kinds() { # sound_kinds — "name=kind:volume" list from one small query
  gbrp world.query "{\"data\":{\"components\":[\"$NAME\",\"$SLIVE\"]}}" 2>/dev/null \
    | jq -r '[.result[]? | .components | select(.["'"$SLIVE"'"] != null)
              | "\(.["'"$NAME"'"])=\(.["'"$SLIVE"'"].kind):\(.["'"$SLIVE"'"].volume)"] | join(" ")' 2>/dev/null
}
gconfig_get() { # gconfig_get — the game's GameAudioConfig resource JSON
  # This fork's world.get_resources takes one `resource` path and answers
  # {result:{value:{...}}} (builtin_methods.rs BrpGetResourcesParams).
  gbrp world.get_resources "{\"resource\":\"$GACONFIG\"}" 2>/dev/null \
    | jq -c '.result.value // empty' 2>/dev/null
}
gconfig_mutate() { # gconfig_mutate <field> <value> — mutate until a read-back agrees
  local field="$1" value="$2" attempt got
  for attempt in 1 2 3 4; do
    gbrp world.mutate_resources "{\"resource\":\"$GACONFIG\",\"path\":\"$field\",\"value\":$value}" >/dev/null 2>&1
    sleep 1.5
    got=$(gconfig_get | jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null)
    [ "$got" = "${value%.*}" ] || [ "$got" = "$value" ] && { echo "$got"; return 0; }
  done
  echo "$got"
  return 1
}
export_wait() { # export_wait — game.export, held until the staged tree carries the flow scene
  local want got st saw_state=""
  want=$(shasum -a 256 "$PROJECT/assets/scene.bsn" 2>/dev/null | awk '{print $1}')
  op game.export '{}' >/dev/null 2>&1
  local deadline=$((SECONDS + 1500))
  while [ $SECONDS -lt $deadline ]; do
    st=$(brp jackdaw/export '{}' 2>/dev/null | jq -r '.result.state // empty' 2>/dev/null)
    [ -n "$st" ] && saw_state=1
    got=$(shasum -a 256 "$STAGED/assets/scene.bsn" 2>/dev/null | awk '{print $1}')
    if [ -n "$got" ] && [ "$got" = "$want" ]; then return 0; fi
    if [ -z "$saw_state" ] && [ -x "$STAGED_EXE" ] && [ -f "$STAGED/export-manifest.json" ]; then
      return 0
    fi
    sleep 5
  done
  return 1
}
# The letterboxed streamed-frame rect from the editor's UI tree (the T12
# channel): the widest 16:9-ish plain node is the frame image.
frame_rect() {
  # The widest 16:9-ish node in window-logical coordinates: the PIE
  # streamed frame. Nodes measured in another unit (a scaled monitor's
  # backing store) carry origins outside the window — reject those, the
  # click coordinates are window-logical.
  brp jackdaw/ui_tree '{"kind":"node","visible_only":true,"depth":24}' 2>/dev/null \
    | jq -r '[.. | objects | select(.kind? == "node") | .rect
              | select(. != null and .[0] >= 0 and .[1] >= 0 and .[2] > 300 and .[2] < 2000 and (.[3] > 1) and ((.[2] / .[3]) > 1.6) and ((.[2] / .[3]) < 1.95))]
             | sort_by(-.[2]) | first | if . then "\(.[0]) \(.[1]) \(.[2]) \(.[3])" else empty end' 2>/dev/null
}

write_scene_bsn() {
  # The starter scene with the template's ambient drone plus two authored
  # probe sounds: a music-bus loop and an sfx-bus loop. With the flow in
  # Level the running game carries all three bus kinds at once, which is
  # what the routing legs sample. Full generic paths everywhere (the A8
  # generic discipline).
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
    --
    #Ambient
    bevy_audio::audio::AudioPlayer<bevy_audio::audio_source::AudioSource>("sounds/ambient.wav")
    bevy_audio::audio::PlaybackSettings {
        mode: bevy_audio::audio::PlaybackMode::Loop,
        volume: bevy_audio::volume::Volume::Linear(0.8),
        spatial: true,
    }
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: 6.0, y: 2.0, z: -4.0 },
    }
    bevy_camera::visibility::Visibility::Visible
    --
    #MusicProbe
    bevy_audio::audio::AudioPlayer<bevy_audio::audio_source::AudioSource>("sounds/bgm.wav")
    bevy_audio::audio::PlaybackSettings {
        mode: bevy_audio::audio::PlaybackMode::Loop,
        volume: bevy_audio::volume::Volume::Linear(0.5),
    }
    t16_audio::MusicBus
    --
    #SfxProbe
    bevy_audio::audio::AudioPlayer<bevy_audio::audio_source::AudioSource>("sounds/blip.wav")
    bevy_audio::audio::PlaybackSettings {
        mode: bevy_audio::audio::PlaybackMode::Loop,
        volume: bevy_audio::volume::Volume::Linear(0.4),
    }
    t16_audio::SfxBus
]
EOF
  python3 - "$PROJECT/assets/game.flow.json" << 'PYT'
import json, sys
path = sys.argv[1]
try:
    flow = json.load(open(path))
    flow["start_scene"] = "menu.bsn"
    json.dump(flow, open(path, "w"), indent=2)
except FileNotFoundError:
    pass
PYT
  # A stale persisted tab journal would restore yesterday's documents;
  # every phase starts on the canonical pair.
  python3 - "$PROJECT/.jackdaw/project.json" << 'PYT'
import json, sys
path = sys.argv[1]
try:
    cfg = json.load(open(path))
    cfg.pop("layout", None)
    cfg["last_open_tabs"] = ["assets/menu.bsn"]
    cfg["last_active_tab"] = 0
    json.dump(cfg, open(path, "w"), indent=2)
except FileNotFoundError:
    pass
PYT
  rm -rf "$PROJECT/screenshots"
}

# ---- phase: prep ------------------------------------------------------------
prep() {
  pkill -x jackdaw 2>/dev/null; pkill -x t16-audio 2>/dev/null; sleep 1
  [ -d "$PROJECT" ] || { log "PREP_FAIL fixture missing; run the T1 prep first"; exit 1; }
  grep -q '"wav"' "$PROJECT/Cargo.toml" || { log "PREP_FAIL features lack wav"; exit 1; }
  grep -q "GameAudioConfig" "$PROJECT/src/lib.rs" || { log "PREP_FAIL fixture lacks the audio template section"; exit 1; }
  for f in bgm blip ambient; do
    [ -f "$PROJECT/assets/sounds/$f.wav" ] || { log "PREP_FAIL sounds/$f.wav missing"; exit 1; }
  done
  grep -q "MenuBgm" "$PROJECT/assets/menu.bsn" || { log "PREP_FAIL menu.bsn lacks #MenuBgm"; exit 1; }

  write_scene_bsn

  # Warm-project test injection (t11t2/t13t2/t14/t15 practice): game-side BRP.
  if ! grep -q jackdaw_remote "$PROJECT/Cargo.toml"; then
    /usr/bin/sed -i '' "s|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = \[\"terrain\", \"pie\"\] }|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = [\"terrain\", \"pie\"] }\njackdaw_remote = { path = '$REPO/crates/jackdaw_remote' }|" "$PROJECT/Cargo.toml"
    grep -q jackdaw_remote "$PROJECT/Cargo.toml" || { log "PREP_FAIL no remote dep"; exit 1; }
    /usr/bin/sed -i '' 's|\.add_plugins(t16_audio::GamePlugin)|.add_plugins(t16_audio::GamePlugin)\n        .add_plugins(jackdaw_remote::JackdawRemotePlugin::default())|' "$PROJECT/src/main.rs"
    grep -q JackdawRemotePlugin "$PROJECT/src/main.rs" || { log "PREP_FAIL no remote plugin"; exit 1; }
    (cd "$PROJECT" && cargo metadata --format-version 1 >/dev/null 2>"$OUTDIR/lockfix.log") \
      || { log "PREP_FAIL lock refresh: $(tail -2 "$OUTDIR/lockfix.log")"; exit 1; }
  fi

  # Warm the game build so the legs are not cold compiles.
  (cd "$PROJECT" && cargo build > "$OUTDIR/game-warmbuild-prep.log" 2>&1) \
    || { log "PREP_FAIL game warm build: $(tail -3 "$OUTDIR/game-warmbuild-prep.log")"; exit 1; }
  log "PREP_OK fixture=$PROJECT"
}

# ---- editor phase -----------------------------------------------------------
pick_entity_for() { # pick_entity_for <none-x> <none-y> — the Pick icon nearest the None row
  # Anchored on the row's own rect: the editor UI's coordinate space
  # drifts between runs (display scale/placement), so absolute windows
  # miss by pixels. Relative + nearest wins.
  brp jackdaw/ui_tree '{"kind":"node","visible_only":true,"depth":80}' 2>/dev/null \
    | jq -r --argjson x "$1" --argjson y "$2" \
        '[.. | objects
           | select(.kind? == "text" and .text? == "\ue247"
                    and ((.rect[1] // -9999) > ($y - 45)) and ((.rect[1] // -9999) < ($y + 45))
                    and ((.rect[0] // -9999) > ($x + 40)))
           | [((.rect[1] - $y) | if . < 0 then -. else . end), .entity]]
         | sort_by(.[0]) | first | if . then .[1] else empty end' 2>/dev/null
}

l1_m1_chain() {
  # The authorization chain, the way an author drives it: Add Entity >
  # Audio Source, the inspector's Audio tab, the AudioPlayer card's Pick
  # (the AU3 picker face: it lists this project's wavs), the pick lands
  # in the handle, PlaybackSettings mode to Loop by the same edit machine
  # the card uses, save, reopen — four pieces back (AudioPlayer +
  # PlaybackSettings + derived marker + the document's full generic
  # paths). The operator `entity` clause spells targets by Name; the
  # world.query "idvGEN" strings only answer bevy-native methods (N12).
  open_scene scene.bsn
  local ok=true
  op entity.add.audio_source >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  op selection.select '{"name":"Audio Source"}' >/dev/null 2>&1
  sleep 2
  local id
  id=$(brp world.query "{\"data\":{\"components\":[\"$NAME\"]}}" 2>/dev/null \
    | jq -r '[.result[]? | select(.components["'"$NAME"'"] == "Audio Source") | .entity][0]' 2>/dev/null)
  [ -n "$id" ] || { log "L1: Audio Source entity not found after add"; leg L1_M1_CHAIN false; return; }
  # The Audio tab rides the strip's category rail; it appears when the
  # selected entity carries audio. Then expand the card by its header.
  # Both the tab click and the expand can race the inspector's layout —
  # retry the pair until the handle row's icons show up.
  local none_y pick_e try=0
  while [ $try -lt 5 ]; do
    click_text "\ue1ab" >/dev/null; sleep 1
    click_text "AudioPlayer<AudioSource>" >/dev/null; sleep 2
    # The Pick icon: the folder-open glyph on the handle's row (the row
    # whose value text reads None), found by geometry and clicked by id —
    # icon buttons carry no text label and the picker's own items are
    # TextSpan rows the Text query cannot see (A7-family tool debt).
    walk
    pick_e=""
    while read -r nx ny; do
      [ -n "$nx" ] || continue
      pick_e=$(pick_entity_for "$nx" "$ny")
      [ -n "$pick_e" ] && { none_y=$ny; break; }
    done <<EOF
$(jq -r '[.. | objects | select(.kind? == "text" and .text? == "None" and ((.rect[2] // 0) > 0))][].rect | "\(.[0] | floor) \(.[1] | floor)"' "$OUTDIR/walk-$PHASE.json" 2>/dev/null)
EOF
    [ -n "$pick_e" ] && break
    try=$((try + 1))
    sleep 1
  done
  if [ -n "$pick_e" ]; then
      brp jackdaw/ui_click "{\"entity\":$pick_e}" >/dev/null 2>&1
      sleep 1
      # The picker is a fixed-size modal; the items sit at fixed offsets
      # under its title. sounds/blip.wav is the fourth row (Browse,
      # ambient, bgm, blip). jq reports float rects; awk makes the click
      # point integers.
      local pxy
      pxy=$(brp jackdaw/ui_tree '{"kind":"node","visible_only":true,"depth":80}' 2>/dev/null \
        | jq -r '[.. | objects | select(.kind? == "text" and .text? == "Pick AudioSource")][0].rect | if . then "\(.[0]) \(.[1])" else empty end' 2>/dev/null \
        | awk '{printf "%d %d", $1, $2 + 162}')
      if [ -n "$pxy" ]; then
        shot l1-audio-picker
        op input.pointer "{\"x\":${pxy% *},\"y\":${pxy#* },\"action\":\"click\",\"button\":\"primary\"}" >/dev/null 2>&1
        sleep 2; wait_idle 60 >/dev/null
      else
        log "L1: picker title not found after Pick"
        ok=false
      fi
  else
    log "L1: the expanded card's Pick icon never showed (none_y=${none_y:-absent})"
    ok=false
  fi
  # The handle's live value only serializes as a Uuid; the path lives in
  # the document, so the data half is judged on the saved file below.
  op component.set '{"entity":"Audio Source","type_path":"'"$PSET"'","field":"mode","value":"\"Loop\""}' >/dev/null 2>&1
  sleep 1
  op component.set '{"entity":"Audio Source","type_path":"'"$PSET"'","field":"volume","value":"{\"Linear\":0.55}"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  local settings
  settings=$(brp world.get_components "{\"entity\":\"$id\",\"components\":[\"$PSET\"]}" 2>/dev/null \
    | jq -c --arg c "$PSET" '.result.components[$c] // empty' 2>/dev/null)
  echo "$settings" | grep -q '"mode":"Loop"' || { log "L1: mode reads $settings"; ok=false; }
  echo "$settings" | grep -q "0.55" || { log "L1: volume reads $settings"; ok=false; }
  # Save + reopen: the four pieces must come back (the generic
  # registration is what makes the AudioPlayer survive the round trip;
  # the document text is where the picked path is honestly readable).
  op scene.save >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  grep -q 'AudioPlayer<bevy_audio::audio_source::AudioSource>("sounds/blip.wav")' "$PROJECT/assets/scene.bsn" \
    || { log "L1: document lacks the picked handle"; ok=false; }
  open_scene scene.bsn
  sleep 2
  op selection.select '{"name":"Audio Source"}' >/dev/null 2>&1
  sleep 2
  local id2
  id2=$(brp world.query "{\"data\":{\"components\":[\"$NAME\"]}}" 2>/dev/null \
    | jq -r '[.result[]? | select(.components["'"$NAME"'"] == "Audio Source") | .entity][0]' 2>/dev/null)
  [ -n "$id2" ] || { log "L1: Audio Source lost across reopen"; ok=false; }
  local player2 settings2 marker
  # The handle's live serialization can come back empty across a reopen
  # (an unloaded dependency's ReflectHandle), so presence rides a query
  # filtered on the component itself; the value was already judged on the
  # saved document above.
  player2=$(brp world.query "{\"data\":{\"components\":[\"$APLAYER\"]}}" 2>/dev/null \
    | jq -r --arg id "$id2" '[.result[]? | select(.entity == $id)][0].entity // empty' 2>/dev/null)
  settings2=$(brp world.get_components "{\"entity\":\"$id2\",\"components\":[\"$PSET\"]}" 2>/dev/null \
    | jq -c --arg c "$PSET" '.result.components[$c] // empty' 2>/dev/null)
  marker=$(brp world.get_components "{\"entity\":\"$id2\",\"components\":[\"jackdaw::entity_ops::SceneAudioSource\"]}" 2>/dev/null \
    | jq -c '.result.components // empty' 2>/dev/null)
  [ -n "$player2" ] || { log "L1: reopen handle not on the entity ($player2)"; ok=false; }
  echo "$settings2" | grep -q '"mode":"Loop"' || { log "L1: reopen settings read $settings2"; ok=false; }
  echo "$settings2" | grep -q "0.55" || { log "L1: reopen volume reads $settings2"; ok=false; }
  echo "$marker" | grep -q "SceneAudioSource" || { log "L1: derived marker missing across reopen ($marker)"; ok=false; }
  walk
  shot l1-reopened-inspector
  log "L1 M1 chain: reopen handle ok, settings ok, marker ok, ok=$ok"
  leg L1_M1_CHAIN "$ok"
}

m7_auth_face() {
  # The config auth face: New Asset -> GameAudioConfig, the card opens,
  # the edit machine takes a value and the file carries it. The play face
  # (a running game reading the authored numbers) runs in the game phase.
  local ok=true
  rm -f "$PROJECT/assets/audio-config.bsn"
  rm -rf "$PROJECT/assets/assets"   # a stray tree an earlier red run's
                                    # "assets/audio-config.bsn" path created
  # The kind must be spelled as the editor knows it (the full type path —
  # the bare name is not an id/label), and the path is relative to the
  # assets dir (writing "assets/..." lands in assets/assets/).
  op asset.new '{"type":"t16_audio::GameAudioConfig","name":"audio-config","path":"audio-config.bsn"}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  [ -f "$PROJECT/assets/audio-config.bsn" ] || { log "M7: audio-config.bsn did not land"; leg M7_AUTH_FACE false; return; }
  # The fresh file is a stamp plus the type at its defaults (the writer
  # omits default-equal fields — no "master" line exists yet); the edit
  # half below is what proves the card machine writes.
  grep -q "GameAudioConfig" "$PROJECT/assets/audio-config.bsn" || ok=false
  op asset.set '{"field":"music","value":"0.5"}' >/dev/null 2>&1
  sleep 1
  op asset.save >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  grep -q "0.5" "$PROJECT/assets/audio-config.bsn" || { log "M7: card edit did not reach the file"; ok=false; }
  shot m7-config-card
  # Back to the canonical defaults the mix legs expect.
  op asset.set '{"field":"music","value":"1.0"}' >/dev/null 2>&1
  sleep 1
  op asset.save >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  grep -q "0.5" "$PROJECT/assets/audio-config.bsn" && { log "M7: revert did not land"; ok=false; }
  log "M7 auth face: asset.new + card edit + save + revert, ok=$ok"
  leg M7_AUTH_FACE "$ok"
}

m14_editor_mute_witness() {
  # The editor must not be a sounding body (AU7): the mute gate is the
  # AudioPlugin global volume at 0.0, the engine multiplies it into every
  # sink it builds. The editor world still shows the authored
  # PlaybackSettings (0.6) on the menu BGM — the authored numbers stay
  # untouched; the output base is what reads zero.
  local ok=true
  open_scene menu.bsn
  sleep 2
  local gv
  gv=$(brp world.get_resources "{\"resource\":\"$GLOBALVOL\"}" 2>/dev/null \
    | jq -c '.result.value // empty' 2>/dev/null)
  log "M14: editor GlobalVolume = $gv (want Linear 0.0)"
  echo "$gv" | jq -e '.volume.Linear == 0' >/dev/null 2>&1 || ok=false
  local id bgm
  id=$(brp world.query "{\"data\":{\"components\":[\"$NAME\"]}}" 2>/dev/null \
    | jq -r '[.result[]? | select(.components["'"$NAME"'"] == "MenuBgm") | .entity][0]' 2>/dev/null)
  [ -n "$id" ] || { log "M14: MenuBgm not in the editor world"; ok=false; }
  bgm=$(brp world.get_components "{\"entity\":\"$id\",\"components\":[\"$PSET\"]}" 2>/dev/null \
    | jq -c --arg c "$PSET" '.result.components[$c] // empty' 2>/dev/null)
  log "M14: editor MenuBgm PlaybackSettings = $bgm (authored base stays 0.6)"
  echo "$bgm" | grep -q "0.6" || ok=false
  shot m14-editor-muted-menu
  log "M14 editor half: GlobalVolume zeroed=$([ "$ok" = true ] && echo y || echo n)"
  leg M14_EDITOR_MUTED "$ok"
}

m12_reopen() {
  # The template-authored audio data survives the editor's own save and
  # a reopen: the menu BGM's AudioPlayer handle and PlaybackSettings read
  # the same on both sides of the round trip (live values — the handle
  # only serializes as a Uuid), and the document still carries the full
  # generic paths and the MusicBus line (the editor's registry does not
  # hold the template's own types, so the bus is judged at the document).
  local ok=true
  m12_read() { # m12_read — one combined read of the menu BGM's live pieces
    local id
    id=$(brp world.query "{\"data\":{\"components\":[\"$NAME\"]}}" 2>/dev/null \
      | jq -r '[.result[]? | select(.components["'"$NAME"'"] == "MenuBgm") | .entity][0]' 2>/dev/null)
    # The AudioPlayer's live value may serialize empty (unloaded
    # dependency); presence rides a component-filtered query.
    local player settings
    player=$(brp world.query "{\"data\":{\"components\":[\"$APLAYER\"]}}" 2>/dev/null \
      | jq -r --arg id "$id" 'any(.result[]?; .entity == $id) | if . then "present" else "absent" end' 2>/dev/null)
    settings=$(brp world.get_components "{\"entity\":\"$id\",\"components\":[\"$PSET\"]}" 2>/dev/null \
      | jq -c --arg c "$PSET" '.result.components[$c] // empty' 2>/dev/null)
    printf 'player=%s settings=%s\n' "$player" "$settings"
  }
  open_scene menu.bsn
  sleep 2
  local before after
  before=$(m12_read)
  op scene.save >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  open_scene menu.bsn
  sleep 2
  after=$(m12_read)
  log "M12: before=$before"
  log "M12: after =$after"
  [ -n "$before" ] && [ "$before" = "$after" ] || { log "M12: menu BGM pieces changed across save/reopen"; ok=false; }
  echo "$after" | grep -q "player=present" || { log "M12: reopen handle reads $after"; ok=false; }
  echo "$after" | grep -q '"mode":"Loop"' || ok=false
  echo "$after" | grep -q "0.6" || ok=false
  grep -q 'AudioPlayer<bevy_audio::audio_source::AudioSource>("sounds/bgm.wav")' "$PROJECT/assets/menu.bsn" \
    || { log "M12: document lacks the BGM handle"; ok=false; }
  grep -q "t16_audio::MusicBus" "$PROJECT/assets/menu.bsn" \
    || { log "M12: document lacks the MusicBus line"; ok=false; }
  log "M12 reopen: menu BGM handle/settings/bus all kept, ok=$ok"
  leg M12_REOPEN_CONSISTENT "$ok"
}

editor_phase() {
  write_scene_bsn   # canonical prep state for every editor segment
  rm -f "$OUTDIR/summary-editor.txt"
  editor_boot "$PROJECT"
  editor_build_settled 600
  l1_m1_chain
  m7_auth_face
  m14_editor_mute_witness
  m12_reopen

  # The standing warn scan over this phase's editor log. The audio
  # word-list forms: a `cannot apply ... AudioPlayer` line = the generic
  # registration regression; `No audio device` = a deviceless host.
  sleep 2
  local log="$OUTDIR/editor-$PHASE.log"
  local reg n13
  reg=$(grep -Ec "cannot apply.*AudioPlayer" "$log" 2>/dev/null)
  n13=$(grep -c "panicked at" "$log" 2>/dev/null)
  log "WARN_SCAN editor phase: generic_registration_lines=${reg:-0} (panics counted: ${n13:-0})"
  grep -Ein "audio|sound|Spatial|UnresolvedTypes|cannot-apply" "$log" 2>/dev/null \
    | grep -Ei "warn|error|fail|missing|not found|unresolved|cannot" \
    > "$OUTDIR/audio-warn-lines-editor.log" || true
  if [ "${reg:-0}" != "0" ]; then
    leg WARN_SCAN_EDITOR false
  else
    leg WARN_SCAN_EDITOR true
  fi
  printf '%s\n' "$(results)" > "$OUTDIR/summary-editor.txt"
  log "VERDICT_EDITOR_PHASE: $(results)"
}

# ---- game phase -------------------------------------------------------------
l2_afplay() {
  # The files are listenable at all, before any engine claim: afplay
  # decodes and plays them on the real output device.
  local ok=true
  for f in blip bgm ambient; do
    if afplay "$PROJECT/assets/sounds/$f.wav" >/dev/null 2>&1; then
      log "L2: afplay $f.wav exit 0"
    else
      log "L2: afplay $f.wav failed"; ok=false
    fi
  done
  leg L2_AFPLAY_CONTROL "$ok"
}

l3_m2_bgm() {
  # The menu BGM plays in the direct-run game; the mirror reads the mix
  # math (0.6 base x music 1 x master 1 = 0.6), the position advances
  # (loop live), and a master=0 mutate reaches the already-playing sink.
  local ok=true
  local vol1 pos1 vol2 pos2
  vol1=$(gsound_wait MenuBgm | jq -r '.volume // empty' 2>/dev/null)
  [ -n "$vol1" ] || { log "L3: MenuBgm mirror never appeared"; leg L3_M2_BGM false; return; }
  pos1=$(gsound MenuBgm | jq -r '.position_secs // empty' 2>/dev/null)
  sleep 2
  pos2=$(gsound MenuBgm | jq -r '.position_secs // empty' 2>/dev/null)
  gsound MenuBgm > "$OUTDIR/l3-menubgm-witness.json"
  log "L3: MenuBgm sample1 vol=$vol1 pos=$pos1, sample2 pos=$pos2 ($(cat "$OUTDIR/l3-menubgm-witness.json"))"
  awk "BEGIN{exit !($vol1 > 0.59 && $vol1 < 0.61)}" || { log "L3: volume $vol1 != 0.6"; ok=false; }
  awk "BEGIN{exit !($pos2 > $pos1)}" || { log "L3: position did not advance ($pos1 -> $pos2)"; ok=false; }
  gsound MenuBgm | jq -e '.kind == "music" and .paused == false and .finished == false' >/dev/null 2>&1 \
    || { log "L3: kind/paused/finished off: $(gsound MenuBgm)"; ok=false; }
  # Live master mute on an already-playing sink (the engine never does
  # this itself — the template's mix system is what reaches it).
  local got
  got=$(gconfig_mutate master 0.0)
  sleep 1.5
  local muted
  muted=$(gsound MenuBgm | jq -r '.volume // empty' 2>/dev/null)
  log "L3: master->0 readback=$got, MenuBgm volume now $muted"
  awk "BEGIN{exit !($muted < 0.001)}" || { log "L3: master mute did not reach the sink ($muted)"; ok=false; }
  gconfig_mutate master 1.0 >/dev/null
  sleep 1.5
  local restored
  restored=$(gsound MenuBgm | jq -r '.volume // empty' 2>/dev/null)
  awk "BEGIN{exit !($restored > 0.59 && $restored < 0.61)}" || { log "L3: restore gave $restored"; ok=false; }
  log "L3 M2 BGM: mute+restore cycle complete, ok=$ok"
  leg L3_M2_BGM "$ok"
}

m3_direct_chain() {
  # The ScreenPressed chain without a pointer: trigger the reflected
  # event the button binding would send, and the template's observer
  # does the rest — blip sink (count 0 -> 1 with volume 1.0), then the
  # flow moves to Level and the menu BGM stops (the "stop" word live:
  # the menu document's entity leaves with the state).
  local ok=true before after caught=0 blipvol="" flowmoved=false
  before=$(sfx_count)
  [ "${before:-0}" = "0" ] || { log "M3-direct: expected 0 sfx sinks in Menu, saw $before"; ok=false; }
  gbrp world.trigger_event "{\"event\":\"t16_audio::ScreenPressed\",\"value\":{\"button\":\"start\"}}" >/dev/null 2>&1
  # Sample hard for ~3s: the blip is 0.12s of sink.
  local n=0 sfx kind
  while [ $n -lt 40 ]; do
    sfx=$(sfx_count)
    if [ "${sfx:-0}" -ge 1 ]; then
      caught=$((caught + 1))
      blipvol=$(gbrp world.query "{\"data\":{\"components\":[\"$SLIVE\"]}}" 2>/dev/null \
        | jq -r --arg t "$SLIVE" '[.result[]? | select(.components[$t].kind? == "sfx") | .components[$t].volume] | first // empty' 2>/dev/null)
      [ -n "$blipvol" ] && break
    fi
    sleep 0.08
    n=$((n + 1))
  done
  log "M3-direct: sfx sinks before=$before, samples with a sfx sink=$caught, blip volume=$blipvol"
  [ "$caught" -ge 1 ] || ok=false
  # The flow moved: the MenuBgm entity leaves with Menu, the level's
  # Ambient appears (document switch = DespawnOnExit semantics).
  local deadline=$((SECONDS + 20)) bgm=""
  while [ $SECONDS -lt $deadline ]; do
    bgm=$(gsound MenuBgm | jq -r '.kind // empty' 2>/dev/null)
    [ -z "$bgm" ] && { flowmoved=true; break; }
    sleep 1
  done
  local amb
  amb=$(gsound_wait Ambient 8 | jq -r '.kind // empty' 2>/dev/null)
  log "M3-direct: flow moved=$flowmoved (MenuBgm gone), Ambient now=$([ -n "$amb" ] && echo present || echo missing)"
  [ "$flowmoved" = "true" ] || ok=false
  [ -n "$amb" ] || ok=false
  echo "M3_DIRECT blip_caught=$caught blip_volume=$blipvol flow_moved=$flowmoved" > "$OUTDIR/m3-direct-witness.txt"
  log "M3-direct chain complete, ok=$ok"
  leg M3_DIRECT_CHAIN "$ok"
}

l5_m4_spatial() {
  # The level scene: a spatial ambient drone with no bus (kind=plain,
  # master-only), the player camera's SpatialListener in the world, and
  # the update chain: drive the player with the Move action's key and
  # both the player and the listener rig move.
  local ok=true
  local amb
  amb=$(gsound_wait Ambient 10)
  [ -n "$amb" ] || { log "L5: Ambient mirror never appeared"; leg L5_M4_SPATIAL false; return; }
  echo "$amb" > "$OUTDIR/l5-ambient-witness.json"
  log "L5: Ambient sample=$amb"
  echo "$amb" | jq -e '.kind == "plain"' >/dev/null 2>&1 || { log "L5: Ambient kind not plain"; ok=false; }
  local ambvol
  ambvol=$(echo "$amb" | jq -r '.volume // 0' 2>/dev/null)
  awk "BEGIN{exit !($ambvol > 0.79 && $ambvol < 0.81)}" 2>/dev/null \
    || { log "L5: Ambient volume off: $ambvol"; ok=false; }
  local probes
  probes=$(sound_kinds)
  log "L5: routing baseline sample: $probes"
  echo "$probes" > "$OUTDIR/l5-routing-baseline.txt"
  echo "$probes" | grep -q "MusicProbe=music:0.5" || { log "L5: MusicProbe missing/off in '$probes'"; ok=false; }
  echo "$probes" | grep -q "SfxProbe=sfx:0.4" || { log "L5: SfxProbe missing/off in '$probes'"; ok=false; }
  # The listener: the camera rig the player carries.
  local listener_id
  listener_id=$(gbrp world.query "{\"data\":{\"components\":[\"$SLISTEN\"]}}" 2>/dev/null \
    | jq -r '[.result[]?][0].entity // empty' 2>/dev/null)
  [ -n "$listener_id" ] || { log "L5: no SpatialListener entity in the game world"; ok=false; }
  log "L5: SpatialListener entity=$listener_id"
  # The authored spatial flag on the ambient entity.
  local amb_settings
  amb_settings=$(gcomp "$(gid Ambient)" "$PSET" 2>/dev/null)
  echo "$amb_settings" | grep -q "spatial" && echo "$amb_settings" | grep -q "true" \
    || { log "L5: Ambient PlaybackSettings lacks spatial:true ($amb_settings)"; ok=false; }
  # The emitter sits where the scene put it. GlobalTransform serializes
  # as the 12 floats of an Affine3A; the translation is the last three.
  local emitter
  emitter=$(gcomp "$(gid Ambient)" "$GTRANS" 2>/dev/null | jq -c 'if type == "array" then .[-3:] else .translation // empty end' 2>/dev/null)
  log "L5: Ambient emitter GlobalTransform.translation=$emitter (authored 6,2,-4)"
  echo "$emitter" | grep -q "6" || ok=false
  echo "$emitter" | grep -q -- "-4" || ok=false
  # The update chain: walk the player forward, the player and the
  # listener rig both move (emitter stays put; bevy updates listener
  # positions from Transform changes every frame). The player carries no
  # Name — PlayerMarker is how the template answers "which one".
  local player_id t1 t2 l1 l2
  player_id=$(gbrp world.query '{"data":{"components":["t16_audio::PlayerMarker"]}}' 2>/dev/null \
    | jq -r '[.result[]?][0].entity // empty' 2>/dev/null)
  gt_translation() { # gt_translation <id> — translation out of a Transform or a GlobalTransform
    gcomp "$1" "$2" 2>/dev/null | jq -c 'if type == "array" then .[-3:] else .translation // empty end' 2>/dev/null
  }
  t1=$(gt_translation "$player_id" "bevy_transform::components::transform::Transform")
  l1=$(gt_translation "$listener_id" "$GTRANS")
  local window
  window=$(gbrp world.query '{"data":{"components":["bevy_window::window::Window"]}}' 2>/dev/null | jq -r '.result[0].entity // empty' 2>/dev/null)
  gbrp world.write_message "{\"message\":\"$KB_MSG\",\"value\":{\"key_code\":\"KeyW\",\"logical_key\":{\"Character\":\" \"},\"state\":\"Pressed\",\"text\":null,\"repeat\":false,\"window\":\"$window\"}}" >/dev/null 2>&1
  sleep 2
  gbrp world.write_message "{\"message\":\"$KB_MSG\",\"value\":{\"key_code\":\"KeyW\",\"logical_key\":{\"Character\":\" \"},\"state\":\"Released\",\"text\":null,\"repeat\":false,\"window\":\"$window\"}}" >/dev/null 2>&1
  sleep 1
  t2=$(gt_translation "$player_id" "bevy_transform::components::transform::Transform")
  l2=$(gt_translation "$listener_id" "$GTRANS")
  log "L5: walk player $t1 -> $t2; listener $l1 -> $l2"
  [ -n "$t1" ] && [ -n "$t2" ] && [ "$t1" != "$t2" ] || { log "L5: the player did not move"; ok=false; }
  [ -n "$l1" ] && [ -n "$l2" ] && [ "$l1" != "$l2" ] || { log "L5: the listener transform did not follow"; ok=false; }
  log "L5 M4 spatial complete, ok=$ok"
  leg L5_M4_SPATIAL "$ok"
}

l9_m10_routing() {
  # The three-bus routing, live: each bus knob moves only its own sinks,
  # and master moves all of them — on sinks that are already playing.
  local ok=true probes
  probes=$(sound_kinds)
  log "L9 baseline: $probes"
  echo "$probes" | grep -q "MusicProbe=music:0.5" || { log "L9: baseline lacks MusicProbe=music:0.5"; ok=false; }
  echo "$probes" | grep -q "SfxProbe=sfx:0.4" || { log "L9: baseline lacks SfxProbe=sfx:0.4"; ok=false; }
  echo "$probes" | grep -q "Ambient=plain:0.8" || { log "L9: baseline lacks Ambient=plain:0.8"; ok=false; }
  # music -> 0: only the music sink mutes.
  gconfig_mutate music 0.0 >/dev/null; sleep 1.5
  probes=$(sound_kinds)
  log "L9 music=0: $probes"
  echo "$probes" > "$OUTDIR/l9-music-zero.txt"
  echo "$probes" | grep -q "MusicProbe=music:0" || { log "L9: MusicProbe did not mute ($probes)"; ok=false; }
  echo "$probes" | grep -q "SfxProbe=sfx:0.4" || { log "L9: SfxProbe followed music ($probes)"; ok=false; }
  echo "$probes" | grep -q "Ambient=plain:0.8" || { log "L9: Ambient followed music ($probes)"; ok=false; }
  gconfig_mutate music 1.0 >/dev/null; sleep 1.5
  # sfx -> 0: only the sfx sink mutes.
  gconfig_mutate sfx 0.0 >/dev/null; sleep 1.5
  probes=$(sound_kinds)
  log "L9 sfx=0: $probes"
  echo "$probes" > "$OUTDIR/l9-sfx-zero.txt"
  echo "$probes" | grep -q "SfxProbe=sfx:0" || { log "L9: SfxProbe did not mute ($probes)"; ok=false; }
  echo "$probes" | grep -q "MusicProbe=music:0.5" || { log "L9: MusicProbe followed sfx ($probes)"; ok=false; }
  gconfig_mutate sfx 1.0 >/dev/null; sleep 1.5
  # master -> 0: everything mutes.
  gconfig_mutate master 0.0 >/dev/null; sleep 1.5
  probes=$(sound_kinds)
  log "L9 master=0: $probes"
  echo "$probes" > "$OUTDIR/l9-master-zero.txt"
  echo "$probes" | grep -q "MusicProbe=music:0" || { log "L9: MusicProbe survived master 0"; ok=false; }
  echo "$probes" | grep -q "SfxProbe=sfx:0" || { log "L9: SfxProbe survived master 0"; ok=false; }
  echo "$probes" | grep -q "Ambient=plain:0" || { log "L9: Ambient survived master 0"; ok=false; }
  gconfig_mutate master 1.0 >/dev/null; sleep 1.5
  probes=$(sound_kinds)
  log "L9 restored: $probes"
  echo "$probes" | grep -q "MusicProbe=music:0.5" && echo "$probes" | grep -q "SfxProbe=sfx:0.4" && echo "$probes" | grep -q "Ambient=plain:0.8" \
    || { log "L9: restore incomplete ($probes)"; ok=false; }
  # The bus markers the mirrors declare.
  local mb sb
  mb=$(gcomp "$(gid MusicProbe)" 't16_audio::MusicBus' 2>/dev/null)
  sb=$(gcomp "$(gid SfxProbe)" 't16_audio::SfxBus' 2>/dev/null)
  [ -n "$mb" ] && [ "$mb" != "null" ] || { log "L9: MusicBus marker unreadable ($mb)"; ok=false; }
  [ -n "$sb" ] && [ "$sb" != "null" ] || { log "L9: SfxBus marker unreadable ($sb)"; ok=false; }
  log "L9 M9/M10 routing complete, ok=$ok"
  leg L9_M10_ROUTING "$ok"
}

m7_play_face() {
  # The config's play face: an authored music=0.5 reaches the running
  # game — the resource reads it and the music-bus sinks play the mixed
  # number (MenuBgm 0.6x0.5=0.3, MusicProbe 0.5x0.5=0.25). Then back to
  # the defaults for the routing parity legs.
  local ok=true
  stop_game
  flow_start_scene "menu.bsn"
  op asset.open '{"path":"assets/audio-config.bsn"}' >/dev/null 2>&1
  sleep 2
  op asset.set '{"field":"music","value":"0.5"}' >/dev/null 2>&1
  sleep 1
  op asset.save >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  grep -q "0.5" "$PROJECT/assets/audio-config.bsn" || { log "M7-play: file edit did not land"; ok=false; }
  direct_run m7music || { stop_game; leg M7_PLAY_FACE false; return; }
  local cfg vol
  cfg=$(gconfig_get)
  log "M7-play: game resource = $cfg"
  echo "$cfg" > "$OUTDIR/m7-config-resource.json"
  echo "$cfg" | jq -e '.music == 0.5' >/dev/null 2>&1 || { log "M7-play: resource music != 0.5 ($cfg)"; ok=false; }
  vol=$(gsound_wait MenuBgm | jq -r '.volume // empty' 2>/dev/null)
  log "M7-play: MenuBgm volume=$vol (want 0.6x0.5=0.3)"
  awk "BEGIN{exit !($vol > 0.29 && $vol < 0.31)}" || { log "M7-play: MenuBgm $vol != 0.3"; ok=false; }
  # Revert through the same machine.
  stop_game
  op asset.set '{"field":"music","value":"1.0"}' >/dev/null 2>&1
  sleep 1
  op asset.save >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  grep -q "0.5" "$PROJECT/assets/audio-config.bsn" && { log "M7-play: revert did not land"; ok=false; }
  log "M7 play face complete, ok=$ok"
  leg M7_PLAY_FACE "$ok"
}

l7_m6_badref() {
  # The bad reference, red then green: a handle naming no file leaves the
  # entity with its authored settings but no sink (AU8's silence), and
  # the fix brings the sound back. The red run's log archives as *_red
  # before anything overwrites it.
  local ok=true
  stop_game
  flow_start_scene "menu.bsn"
  /usr/bin/sed -i '' 's|"sounds/bgm.wav"|"sounds/missing.wav"|' "$PROJECT/assets/menu.bsn"
  grep -q "missing.wav" "$PROJECT/assets/menu.bsn" || { log "L7: edit did not land"; leg L7_M6_BADREF false; return; }
  direct_run badref
  local id settings live=""
  id=$(gid MenuBgm)
  settings=$(gcomp "$id" "$PSET" 2>/dev/null)
  # The red half: no mirror after a real wait = no sink was ever built.
  if gsound_wait MenuBgm 8 >/dev/null 2>&1; then
    live=$(gsound MenuBgm)
  fi
  log "L7 red: MenuBgm settings=$settings; SoundLive after settle='${live:-ABSENT}'"
  [ -n "$id" ] && [ -n "$settings" ] || ok=false
  [ -z "$live" ] || { log "L7 red: a sink appeared for a missing file?"; ok=false; }
  # Archive the red state before the green rerun touches anything.
  cp "$OUTDIR/direct-badref.log" "$OUTDIR/direct-badref_red.log" 2>/dev/null
  gbrp world.query "{\"data\":{\"components\":[\"$SLIVE\"]}}" 2>/dev/null > "$OUTDIR/l7-red-world_red.json" 2>/dev/null
  log "L7: red state archived (direct-badref_red.log, l7-red-world_red.json)"
  # The green half: put the reference back, the sink appears.
  stop_game
  /usr/bin/sed -i '' 's|"sounds/missing.wav"|"sounds/bgm.wav"|' "$PROJECT/assets/menu.bsn"
  grep -q "missing.wav" "$PROJECT/assets/menu.bsn" && ok=false
  direct_run goodref
  local vol
  vol=$(gsound_wait MenuBgm | jq -r '.volume // empty' 2>/dev/null)
  log "L7 green: MenuBgm volume=$vol"
  awk "BEGIN{exit !($vol > 0.59 && $vol < 0.61)}" || { log "L7 green: $vol != 0.6"; ok=false; }
  log "L7 M6 bad reference red/green complete, ok=$ok"
  leg L7_M6_BADREF "$ok"
}

l4_m3_pie_click() {
  # The real-click leg: PIE on the menu, the editor forwards the pointer
  # click into the streamed frame (the T12 channel), the Start button's
  # Activate fires the binding, the blip sounds and the flow moves.
  local ok=true l10=true
  stop_game
  open_scene menu.bsn
  sleep 2
  local sha_before
  sha_before=$(shasum -a 256 "$PROJECT/assets/menu.bsn" | awk '{print $1}')
  op pie.play_current >/dev/null 2>&1
  wait_game 900 || { log "L4: PIE game never came up"; leg L4_M3_PIE_CLICK false; stop_game; return; }
  game_ready 240
  sleep 5
  local before
  before=$(sfx_count)
  local rect
  rect=$(frame_rect)
  [ -n "$rect" ] || { log "L4: no streamed frame rect found"; leg L4_M3_PIE_CLICK false; stop_game; return; }
  local fx fy fw fh cx cy
  # rects are floats; awk makes the click point integers (an arithmetic
  # syntax error is fatal in a non-interactive shell).
  read -r fx fy fw fh cx cy <<< "$(printf '%s\n' "$rect" | awk '{printf "%d %d %d %d %d %d", $1, $2, $3, $4, $1 + $3 / 2, $2 + $4 / 2}')"
  log "L4: frame rect ($fx,$fy ${fw}x${fh}), clicking ($cx,$cy); sfx sinks before=$before"
  # The pointer only forwards into the running game while input capture
  # is engaged (pie.play_input_toggle — the T12 capture-on line), and the
  # game panel docks as the bottom strip at this window size: its Start
  # sits just below the panel header's Play Input row, near the window
  # centre line. Sweep that band.
  op pie.play_input_toggle >/dev/null 2>&1
  sleep 1
  local dy dx caught_at="" caught=0 blipvol=""
  for dy in 871 851 891 831 911; do
    for dx in 0 -60 60 -120 120; do
      op input.pointer "{\"x\":$((800 + dx)),\"y\":$dy,\"action\":\"click\",\"button\":\"primary\"}" >/dev/null 2>&1
      local n=0 sfx
      while [ $n -lt 12 ]; do
        sfx=$(sfx_count)
        if [ "${sfx:-0}" -ge 1 ]; then
          caught=$((caught + 1))
          blipvol=$(gbrp world.query "{\"data\":{\"components\":[\"$SLIVE\"]}}" 2>/dev/null \
            | jq -r --arg t "$SLIVE" '[.result[]? | select(.components[$t].kind? == "sfx") | .components[$t].volume] | first // empty' 2>/dev/null)
          caught_at="(+$dx,+$dy)"
          break 2
        fi
        sleep 0.08
        n=$((n + 1))
      done
    done
  done
  log "L4: samples with an sfx sink=$caught (hit at$caught_at), blip volume=$blipvol"
  echo "M3_PIE caught=$caught blip_volume=$blipvol" > "$OUTDIR/m3-pie-witness.txt"
  [ "$caught" -ge 1 ] || ok=false
  # The flow moved to Level: the menu BGM leaves, the level sounds enter.
  local deadline=$((SECONDS + 25)) amb="" bgm_gone=false
  while [ $SECONDS -lt $deadline ]; do
    amb=$(gsound Ambient 2>/dev/null | jq -r '.kind // empty' 2>/dev/null)
    [ -n "$amb" ] && { bgm_gone=true; break; }
    sleep 1
  done
  log "L4: level sounds present=$([ -n "$amb" ] && echo y || echo n) (Ambient=$amb)"
  [ -n "$amb" ] || ok=false
  # The stop invariant: the scene document does not change across a PIE
  # run, and no sink type leaks into any document (unreflected, it
  # cannot — the check is the proof it stayed that way).
  op pie.play_input_toggle >/dev/null 2>&1   # capture off
  op pie.stop >/dev/null 2>&1
  sleep 3
  pkill -x t16-audio 2>/dev/null
  sleep 2
  local sha_after
  sha_after=$(shasum -a 256 "$PROJECT/assets/menu.bsn" | awk '{print $1}')
  [ "$sha_before" = "$sha_after" ] || { log "L10: menu.bsn sha changed across PIE"; l10=false; }
  grep -rl "AudioSink" "$PROJECT/assets/"*.bsn 2>/dev/null | grep -q . \
    && { log "L10: AudioSink leaked into a document"; l10=false; }
  log "L10 stop invariant: sha stable=$([ "$sha_before" = "$sha_after" ] && echo y || echo n), no AudioSink in documents"
  leg L4_M3_PIE_CLICK "$ok"
  leg L10_M11_STOP_INVARIANT "$l10"
}

l6_m5_export() {
  # The export: the packaged tree carries the sounds, and the staged
  # binary replays the level scene's three sounds at the same numbers the
  # direct run showed (the M5 numeric parity).
  local ok=true
  stop_game
  flow_start_scene "scene.bsn"
  export_wait || { log "L6: export never became ready"; leg L6_M5_EXPORT false; return; }
  [ -x "$STAGED_EXE" ] || { log "L6: staged exe missing"; ok=false; }
  for f in bgm blip ambient; do
    [ -f "$STAGED/assets/sounds/$f.wav" ] || { log "L6: staged sounds/$f.wav missing"; ok=false; }
  done
  jq -r '.files[].path' "$STAGED/export-manifest.json" 2>/dev/null | grep -q "sounds/bgm.wav" \
    || { log "L6: manifest lacks sounds/bgm.wav"; ok=false; }
  log "L6: staged tree carries sounds/ + manifest rows"
  if [ -x "$STAGED_EXE" ]; then
    (cd "$STAGED" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./t16-audio > "$OUTDIR/staged-run.log" 2>&1 &)
    wait_game 300 || { log "L6: staged game never came up"; ok=false; }
    # Two settles: the game BRP answers early (game_ready below) but the
    # level's load window ate every read in the first run (the A9 flake);
    # settle past it and re-check readiness before sampling.
    sleep 10
    game_ready 240
    if game_up; then
      sleep 5
      local amb probes
      amb=$(gsound_wait Ambient 15)
      [ -n "$amb" ] || { log "L6: staged Ambient never appeared"; ok=false; }
      probes=$(sound_kinds)
      log "L6 staged sample: Ambient=$amb"
      log "L6 staged routing: $probes"
      echo "$probes" > "$OUTDIR/l6-staged-routing.txt"
      echo "$amb" > "$OUTDIR/l6-staged-ambient.json"
      echo "$probes" | grep -q "MusicProbe=music:0.5" || { log "L6: staged MusicProbe off ('$probes')"; ok=false; }
      echo "$probes" | grep -q "SfxProbe=sfx:0.4" || { log "L6: staged SfxProbe off ('$probes')"; ok=false; }
      echo "$probes" | grep -q "Ambient=plain:0.8" || { log "L6: staged Ambient off ('$probes')"; ok=false; }
      # The authored spatial flag reads the same from the staged world.
      local staged_settings
      staged_settings=$(gcomp "$(gid Ambient)" "$PSET" 2>/dev/null)
      echo "$staged_settings" | grep -q "true" || { log "L6: staged spatial flag off ($staged_settings)"; ok=false; }
      local cfg
      cfg=$(gconfig_get)
      echo "$cfg" | jq -e '.master == 1.0 and .music == 1.0 and .sfx == 1.0' >/dev/null 2>&1 \
        || { log "L6: staged config resource off ($cfg)"; ok=false; }
    fi
    pkill -x t16-audio 2>/dev/null; sleep 2
  fi
  flow_start_scene "menu.bsn"   # restore the canonical start scene
  log "L6 M5 export parity complete, ok=$ok"
  leg L6_M5_EXPORT "$ok"
}

game_phase() {
  write_scene_bsn   # canonical scene for the game legs (drops the entity
                    # the editor phase's L1 chain saved into scene.bsn)
  rm -f "$OUTDIR/summary-game.txt"
  editor_boot "$PROJECT"
  editor_build_settled 600
  l2_afplay

  # --- menu world: the BGM leg, the direct ScreenPressed chain ---------
  stop_game
  flow_start_scene "menu.bsn"
  direct_run menu || { log "GAME_PHASE: direct menu run failed"; leg L3_M2_BGM false; }
  if game_up; then
    l3_m2_bgm
    m3_direct_chain
  fi

  # --- level world: spatial + routing ----------------------------------
  stop_game
  flow_start_scene "scene.bsn"
  direct_run level || { log "GAME_PHASE: direct level run failed"; leg L5_M4_SPATIAL false; }
  if game_up; then
    l5_m4_spatial
    l9_m10_routing
  fi

  # --- config play face + bad reference + PIE + export ------------------
  m7_play_face
  l7_m6_badref
  l4_m3_pie_click
  l6_m5_export

  # The game phase's own output: the standing warn scan + N13 count over
  # every channel's own stdout (the AN10 blind spot). The judged list is
  # audio-domain only — the template's own benign states are attributed,
  # not counted: a missing game-config.bsn starts GameConfig at its
  # default, and the level bindings' first frames read before their
  # context exists. `t16_audio::` in a bind line is a crate path, not an
  # audio event.
  sleep 2
  local log="$OUTDIR/editor-$PHASE.log"
  local reg n13
  reg=$(grep -Ec "cannot apply.*AudioPlayer" "$log" 2>/dev/null)
  n13=$(grep -c "panicked at" "$log" 2>/dev/null)
  : > "$OUTDIR/audio-warn-lines-game-channels.log"
  : > "$OUTDIR/audio-warn-attributed.log"
  local gl
  for gl in "$OUTDIR"/direct-*.log "$OUTDIR/staged-run.log"; do
    [ -f "$gl" ] || continue
    # The L7 red half's own log is the leg's designed evidence (the
    # missing.wav load error is what it exists to produce) — same skip
    # rule as the *_red.log archives.
    case "$gl" in *_red.log|*badref.log) continue ;; esac
    grep -Ein "audio|sound|Spatial|UnresolvedTypes|cannot|decoder|missing" "$gl" 2>/dev/null \
      | grep -Ei "warn|error|fail|missing|not found|unresolved" \
      | sed "s|^.|$(basename "$gl") &|" >> "$OUTDIR/audio-warn-attributed.raw" 2>/dev/null || true
  done
  # Audio-domain = a real sound event. Everything else in the raw sweep
  # is template-state, listed as attributed.
  grep -Ei "No audio device|Spatial|decoder|decode|AudioSource|AudioPlayer|missing\.wav|cannot apply" "$OUTDIR/audio-warn-attributed.raw" 2>/dev/null \
    >> "$OUTDIR/audio-warn-lines-game-channels.log" || true
  grep -Ev "No audio device|Spatial|decoder|decode|AudioSource|AudioPlayer|missing\.wav|cannot apply" "$OUTDIR/audio-warn-attributed.raw" 2>/dev/null \
    > "$OUTDIR/audio-warn-attributed.log" || true
  rm -f "$OUTDIR/audio-warn-attributed.raw"
  local game_channel_warns
  game_channel_warns=$(grep -c "" "$OUTDIR/audio-warn-lines-game-channels.log" 2>/dev/null)
  local attributed
  attributed=$(grep -c "" "$OUTDIR/audio-warn-attributed.log" 2>/dev/null)
  log "WARN_SCAN game phase: generic_registration_lines=${reg:-0} game_channel_audio_warns=${game_channel_warns:-0} attributed_template_states=${attributed:-0} (panics counted: ${n13:-0})"
  grep -n "panicked at" "$log" 2>/dev/null | head -5 > "$OUTDIR/n13-count.txt" || true
  grep -Ein "audio|sound|Spatial|UnresolvedTypes|cannot" "$log" 2>/dev/null \
    | grep -Ei "warn|error|fail|missing|not found|unresolved" \
    > "$OUTDIR/audio-warn-lines-game.log" || true
  if [ "${reg:-0}" != "0" ] || [ "${game_channel_warns:-0}" != "0" ]; then
    leg WARN_SCAN_GAME false
    log "game-channel warn lines (each must attribute):"
    cat "$OUTDIR/audio-warn-lines-game-channels.log"
  else
    leg WARN_SCAN_GAME true
  fi
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
    log "T16_LIVE_DONE"
    ;;
  *) echo "unknown phase: $PHASE (prep|editor|game|all)"; exit 2 ;;
esac
