#!/bin/bash
# T17-T2 live matrix: the save/settings workflow's live legs on the Mac
# fixture (the green state the template ships, plus jackdaw_remote
# injected and an authored audio-config.bsn). Log names follow $PHASE
# everywhere (the A7 stale-grep lesson); every planned red state lands
# in *_red.log before the rerun (the T1 red-first discipline).
#
# The one environmental discipline this task runs on: JACKDAW_SAVE_DIR
# is exported HERE, at the top, and points at the script's own scratch
# tree — every direct run, the editor (so PIE inherits it), and every
# staged export run share that one slot, and nothing this script does
# ever touches the real player tree (decision 6-A: same slot for PIE
# and direct, isolated from it through the seam).
#
# Phases (each phase boots and cleans its own processes — run one per
# invocation, or `all`):
#   prep    verify/create the fixture (`jd new` + the two-line remote
#           sed), author audio-config.bsn at a distinct master (0.42 —
#           the authored layer M6 judges against), point the flow at
#           the menu, wipe the scratch, warm-build the game.
#   game    L1 (first run: Fresh + defaults + no directory; one mutate
#           lands save.json), L2 (all four classes reach the file:
#           audio via the GameAudioConfig watcher, input via the
#           GameInputConfig watcher, progress+unlock through the real
#           game-over path — health to zero three times), L3 (kill -9,
#           restart, all four classes read back, status Loaded), L7
#           (the pause screen's master slider: ValueChange fired at the
#           real widget or the config mutated — either way the watcher
#           persists, and a restart restores both the mix and the
#           slider position), M6 (authored edit does not wash the save;
#           without a save the authored values stand), L4/M13 (corrupt
#           leg: empty save.json -> Recovered + .corrupt backup + warn
#           + defaults + the slot repopulates), L8/M14 (warn scan over
#           every channel log) and the N13 count.
#   editor  L5 (game.export -> staged tree carries no save -> the
#           staged binary reads the same scratch slot), L6 (PIE single
#           leg: Play writes the same slot a direct run reads back —
#           the same-slot decision live; N13 counted).
# Usage: bash loop/qa/t17-live.sh [phase]   phase: prep|game|editor|all
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
FIXROOT=/Users/zhanglinbo/workspace/loop-mac/t17-save
PROJECT="$FIXROOT/t17-save"
PORT=15703
GAME_PORT=15702
OUTDIR="$REPO/loop/t17-live"
SCRATCH="$FIXROOT/scratch"
STAGED="$PROJECT/.jackdaw/dist/release"
STAGED_EXE="$STAGED/t17-save"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
# The seam: the whole save directory, replaced (not a subdirectory of
# one) — every leg of this script lives and dies by it.
export JACKDAW_SAVE_DIR="$SCRATCH"

SSTORE='jackdaw_runtime::save::SaveStore<t17_save::GameSave>'
GACONFIG='t17_save::GameAudioConfig'
GINPUT='jackdaw_runtime::game_input::GameInputConfig'
PHEALTH='t17_save::PlayerHealth'
PMARKER='t17_save::PlayerMarker'
GSTATE='t17_save::GameState'
MASTERMARK='t17_save::MasterVolumeSlider'
FEATHERSSLIDER='bevy_feathers::controls::slider::FeathersSlider'
UINODE='bevy_ui::ui_node::Node'
CHILDREN='bevy_ecs::hierarchy::Children'
SLIDERVAL='bevy_ui_widgets::slider::SliderValue'
VC='bevy_ui_widgets::ValueChange<f32>'
NAME='bevy_ecs::name::Name'
mkdir -p "$OUTDIR"
PHASE="${1:-all}"
CONSOLE_LOG="$OUTDIR/console-$PHASE.log"
: > "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t17-live.XXXXXX)"
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
  pkill -x t17-save 2>/dev/null
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
  # Reads ride the flaky window; exhaustion returns 1 (the T3 lesson —
  # a bare echo fallback returns 0 and pass-dead-port guards).
  local method="$1" params="${2:-}" attempt out
  for attempt in 1 2 3 4 5 6 7 8; do
    out=$(brp_raw "$method" "$params")
    if [ -n "$out" ] && ! echo "$out" | grep -q "expected value at line 1"; then
      echo "$out"
      return 0
    fi
    sleep 3
  done
  echo "$out"
  return 1
}
gbrp() {
  local method="$1" params="${2:-}" id=$RANDOM body out attempt
  if [ -n "$params" ]; then
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params")
  else
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s"}' "$id" "$method")
  fi
  # The game BRP answers intermittently empty in busy windows (A9):
  # reads retry with a short settle; small responses only here.
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
  pkill -x t17-save 2>/dev/null
  sleep 2
}
editor_boot() {
  pkill -x jackdaw 2>/dev/null; pkill -x t17-save 2>/dev/null; sleep 1
  local boot_log="$OUTDIR/editor-$PHASE.log"
  export JACKDAW_OPEN_PROJECT="$PROJECT" JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1600x1000
  cd "$REPO"
  nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$boot_log" 2>&1 &
  local ok=""
  for i in $(seq 1 150); do
    sleep 2
    # The process check is load-bearing (the T3 lesson): a binary that
    # dies before binding the port must fail the boot at the process
    # level, not as a port timeout.
    if brp jackdaw/status '{}' >/dev/null 2>&1 && pgrep -x jackdaw >/dev/null; then ok=1; break; fi
    pgrep -x jackdaw >/dev/null || break
  done
  [ -n "$ok" ] || { log "EDITOR_BOOT_FAIL"; exit 1; }
  sleep 5
  wait_idle 900 >/dev/null; sleep 3; dismiss_dialog
  # A hard-killed previous phase leaves the crash-journal modal up; it
  # blocks every later gesture, so discard it before any leg.
  walk
  if walk_has "Recovered Work"; then
    click_text "Discard All" >/dev/null
    sleep 2; wait_idle 120 >/dev/null
    walk
    walk_has "Recovered Work" && { log "EDITOR_BOOT_FAIL recovery modal survived"; exit 1; }
  fi
  log "EDITOR_READY project=$PROJECT seam=$SCRATCH"
}
walk() { brp jackdaw/ui_tree '{"depth":60}' > "$OUTDIR/walk-$PHASE.json" 2>/dev/null; }
walk_has() { grep -qF "$1" "$OUTDIR/walk-$PHASE.json" 2>/dev/null; }
click_text() {
  brp jackdaw/ui_click "{\"text\":\"$1\"}" 2>/dev/null | jq -r '.result.clicked // false' 2>/dev/null
}
dismiss_dialog() {
  local st
  st=$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.dialog // empty' 2>/dev/null)
  if [ -n "$st" ] && [ "$st" != "null" ]; then
    op dialog.answer '{"choice":"0"}' >/dev/null 2>&1
    sleep 2
  fi
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
flow_start_scene() { # flow_start_scene <scene>
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
direct_run() { # direct_run <tag> — cargo run the fixture; the seam env is
               # already exported at the top of the script
  (cd "$PROJECT" && nohup cargo run > "$OUTDIR/direct-$1.log" 2>&1 &)
  wait_game 600 || { log "direct_run $1: game never came up"; return 1; }
  game_ready 240
  sleep 3
}
gid() { # gid <name> — the game entity id carrying this Name
  gbrp world.query "{\"data\":{\"components\":[\"$NAME\"]}}" 2>/dev/null \
    | jq -r --arg n "$1" '[.result[]? | select(.components["'"$NAME"'"] == $n) | .entity][0]' 2>/dev/null
}
gres() { # gres <resource> — a game resource's JSON (small responses only)
  gbrp world.get_resources "{\"resource\":\"$1\"}" 2>/dev/null \
    | jq -c '.result.value // empty' 2>/dev/null
}
gmut() { # gmut <resource> <path> <value> — mutate until a read-back agrees
  local resource="$1" path="$2" value="$3" attempt got want
  want=$(echo "$value" | jq -c . 2>/dev/null)
  for attempt in 1 2 3 4; do
    gbrp world.mutate_resources "{\"resource\":\"$resource\",\"path\":\"$path\",\"value\":$value}" >/dev/null 2>&1
    sleep 1.5
    got=$(gres "$resource" | jq -c --arg p "$path" 'getpath($p | split(".")) // empty' 2>/dev/null)
    if [ -n "$got" ]; then
      # Numbers read back f32-rounded; compare them loosely, the rest
      # exactly.
      if [ "$got" = "$want" ] || awk "BEGIN{exit !($got == $want)}" 2>/dev/null; then
        echo "$got"; return 0
      fi
    fi
  done
  echo "$got"
  return 1
}
gcomp_mut() { # gcomp_mut <entity> <component> <path> <value>
  gbrp world.mutate_components "{\"entity\":\"$1\",\"component\":\"$2\",\"path\":\"$3\",\"value\":$4}" >/dev/null 2>&1
}
# The player the template spawns on entering the level; None while the
# flow is on the menu (the player belongs to no scene document, but it
# only spawns on a level entry).
player_id() {
  local deadline=$((SECONDS + 20)) id
  while [ $SECONDS -lt $deadline ]; do
    id=$(gbrp world.query "{\"data\":{\"components\":[\"$PMARKER\"]}}" 2>/dev/null \
      | jq -r '[.result[]?][0].entity // empty' 2>/dev/null)
    [ -n "$id" ] && { echo "$id"; return 0; }
    sleep 1
  done
  echo ""
  return 1
}
press() { # press <button> — the flow screens' buttons over BRP
  gbrp world.trigger_event "{\"event\":\"t17_save::ScreenPressed\",\"value\":{\"button\":\"$1\"}}" >/dev/null 2>&1
  sleep 2
}
save_file() { echo "$SCRATCH/save.json"; }
save_field() { # save_field <jq-filter> — reads the scratch save's JSON
  jq -r "$1" "$(save_file)" 2>/dev/null
}
feq() { # feq <got> <want> — f32-tolerant number compare (BRP reads answer
        # full f64 spellings of f32 values: 0.42 arrives 0.41999998...)
  awk "BEGIN{exit !($1 - $2 < 0.001 && $2 - $1 < 0.001)}" 2>/dev/null
}
res_num() { # res_num <resource-json> <field> — a resource field as a number
  echo "$1" | jq -r --arg f "$2" '.[$f] // empty' 2>/dev/null
}

poll_save() { # poll_save <jq-filter> <want> [timeout] — the file is the truth
  local filter="$1" want="$2" deadline=$((SECONDS + ${3:-15})) got
  while [ $SECONDS -lt $deadline ]; do
    got=$(save_field "$filter")
    [ "$got" = "$want" ] && return 0
    sleep 1
  done
  echo "$got"
  return 1
}
export_wait() { # export_wait — game.export, held until this run's staged tree is ready
  rm -rf "$STAGED"   # no stale tree: the export must produce this run's tree
  op game.export '{}' >/dev/null 2>&1
  local deadline=$((SECONDS + 1500))
  while [ $SECONDS -lt $deadline ]; do
    if [ -x "$STAGED_EXE" ] && [ -f "$STAGED/export-manifest.json" ]; then
      return 0
    fi
    sleep 5
  done
  return 1
}

write_authored_audio() {
  # The authored audio layer, with a master distinct from every number
  # the legs mutate (0.7/0.35/0.6/0.75/0.9): M6 judges "authored vs
  # saved" against it. The form the editor's own New Asset writer
  # produces (default-equal fields omitted; a partial patch seeds from
  # the ReflectDefault).
  cat > "$PROJECT/assets/audio-config.bsn" << 'EOF'
// jackdaw 0.21.0-dev | bevy main
// jackdaw asset t17_save::GameAudioConfig
#"audio-config"
t17_save::GameAudioConfig {
    master: 0.42,
}
EOF
}

# ---- phase: prep ------------------------------------------------------------
prep() {
  pkill -x jackdaw 2>/dev/null; pkill -x t17-save 2>/dev/null; sleep 1
  mkdir -p "$FIXROOT"
  if [ ! -d "$PROJECT" ]; then
    TOOLCHAIN_LIB="$TOOLCHAIN_LIB" DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" \
      "$REPO/target/debug/jd" new t17-save --path "$FIXROOT" --no-git > "$OUTDIR/jd-new.log" 2>&1 \
      || { log "PREP_FAIL jd new: $(tail -3 "$OUTDIR/jd-new.log")"; exit 1; }
  fi
  grep -q "GameSave" "$PROJECT/src/lib.rs" \
    || { log "PREP_FAIL fixture lacks the save template section"; exit 1; }
  grep -q "FeathersSlider" "$PROJECT/assets/hud.bsn" \
    || { log "PREP_FAIL hud lacks the volume sliders"; exit 1; }

  write_authored_audio

  # Warm-project test injection (t11t2/t13t2/t14/t15/t16 practice): game-side BRP.
  if ! grep -q jackdaw_remote "$PROJECT/Cargo.toml"; then
    /usr/bin/sed -i '' "s|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = \[\"terrain\", \"pie\"\] }|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = [\"terrain\", \"pie\"] }\njackdaw_remote = { path = '$REPO/crates/jackdaw_remote' }|" "$PROJECT/Cargo.toml"
    grep -q jackdaw_remote "$PROJECT/Cargo.toml" || { log "PREP_FAIL no remote dep"; exit 1; }
    /usr/bin/sed -i '' 's|\.add_plugins(t17_save::GamePlugin)|.add_plugins(t17_save::GamePlugin)\n        .add_plugins(jackdaw_remote::JackdawRemotePlugin::default())|' "$PROJECT/src/main.rs"
    grep -q JackdawRemotePlugin "$PROJECT/src/main.rs" || { log "PREP_FAIL no remote plugin"; exit 1; }
    (cd "$PROJECT" && cargo metadata --format-version 1 >/dev/null 2>"$OUTDIR/lockfix.log") \
      || { log "PREP_FAIL lock refresh: $(tail -2 "$OUTDIR/lockfix.log")"; exit 1; }
  fi

  # Canonical flow + tab state; every phase starts clean.
  flow_start_scene "menu.bsn"
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

  # The scratch starts empty: L1's "no directory before the first write"
  # assert depends on it, and no leg ever inherits another's state.
  rm -rf "$SCRATCH"

  # Warm the game build so the legs are not cold compiles.
  (cd "$PROJECT" && cargo build > "$OUTDIR/game-warmbuild-prep.log" 2>&1) \
    || { log "PREP_FAIL game warm build: $(tail -3 "$OUTDIR/game-warmbuild-prep.log")"; exit 1; }
  log "PREP_OK fixture=$PROJECT seam=$SCRATCH"
}

# ---- game phase -------------------------------------------------------------
l1_first_run() {
  # First run against an empty scratch: the store answers Fresh with the
  # four classes at their defaults, the authored audio stands in the
  # mix (0.42 — no save, no override), the disk has NO save and not even
  # a directory (lazy creation is the contract), and not one `game save:`
  # warn fired. Then one mutate (the player layer's own watcher path)
  # lands the file.
  local ok=true store
  [ ! -e "$SCRATCH" ] || { log "L1: scratch not empty at boot"; ok=false; }
  store=$(gres "$SSTORE")
  echo "$store" > "$OUTDIR/l1-store-witness.json"
  echo "$store" | jq -e '.status == "Fresh"' >/dev/null 2>&1 \
    || { log "L1: status not Fresh ($store)"; ok=false; }
  echo "$store" | jq -e '.profile.progress.runs_played == 0 and .profile.unlocks == [] and .profile.audio == null and .profile.input == null' >/dev/null 2>&1 \
    || { log "L1: profile not at defaults ($store)"; ok=false; }
  local cfg
  cfg=$(gres "$GACONFIG")
  feq "$(res_num "$cfg" master)" 0.42 \
    || { log "L1: authored audio did not stand ($cfg)"; ok=false; }
  local warns
  warns=$(grep -ac "game save:" "$OUTDIR/direct-l1.log")
  [ "${warns:-0}" = "0" ] || { log "L1: $warns game save warn lines on a fresh run"; ok=false; }
  # One player-side change (through the config resource, the watcher's
  # own path — BRP never writes the store's dirty bit, QA reflow D):
  # the same-frame watcher persists it and the file appears.
  gmut "$GACONFIG" master 0.7 >/dev/null 2>&1
  if poll_save '.profile.audio.master' '0.7' 15; then
    log "L1: mutate landed save.json with audio.master=0.7"
  else
    log "L1: save.json never carried the mutation"; ok=false
  fi
  log "L1 first run complete, ok=$ok"
  leg L1_FIRST_RUN "$ok"
}

l2_four_classes() {
  # All four classes reach the file through the product paths: audio and
  # input through the template's change watchers, progress and the
  # unlock through the real game-over counter (health to zero — three
  # finished runs, three counts, one unlock).
  local ok=true got
  # audio: music and sfx ride the watcher like master did in L1.
  gmut "$GACONFIG" music 0.6 >/dev/null 2>&1
  poll_save '.profile.audio.music' '0.6' 15 || { log "L2: music never reached the file"; ok=false; }
  gmut "$GACONFIG" sfx 0.5 >/dev/null 2>&1
  poll_save '.profile.audio.sfx' '0.5' 15 || { log "L2: sfx never reached the file"; ok=false; }
  # input: read the table the BRP reflects, rebind Move's first key in
  # place (same shape in, same shape out), mutate, and the watcher
  # carries the whole table into the save.
  local table
  table=$(gres "$GINPUT" | jq -c '(.actions[0].bindings = [{"Key":"KeyE"}]) | .actions' 2>/dev/null)
  [ -n "$table" ] || { log "L2: could not read the input table"; leg L2_FOUR_CLASSES false; return; }
  gmut "$GINPUT" actions "$table" >/dev/null 2>&1
  poll_save '.profile.input[0].name' 'Move' 15 || { log "L2: saved input lost Move"; ok=false; }
  [ "$(save_field '.profile.input[0].bindings[0].Key')" = "KeyE" ] \
    || { log "L2: saved rebind reads $(save_field '.profile.input[0].bindings[0]')"; ok=false; }
  # progress + unlock: the honest path. start -> level (the player
  # spawns), health to zero -> game over -> count + write; three times.
  local cycle player
  for cycle in 1 2 3; do
    press start
    player=$(player_id) || { log "L2: cycle $cycle never spawned a player"; ok=false; break; }
    gcomp_mut "$player" "$PHEALTH" current 0.0
    poll_save '.profile.progress.runs_played' "$cycle" 20 \
      || { log "L2: cycle $cycle never counted (file says $(save_field '.profile.progress.runs_played'))"; ok=false; break; }
    [ "$cycle" = "3" ] || press restart   # gameover -> level, next run
  done
  save_field '.profile.unlocks' | grep -q "endless" \
    || { log "L2: three runs did not unlock endless ($(save_field '.profile.unlocks'))"; ok=false; }
  log "L2 four classes complete, ok=$ok (file: $(cat "$(save_file)" 2>/dev/null | jq -c .))"
  leg L2_FOUR_CLASSES "$ok"
}

l3_kill9_restart() {
  # The acceptance word's literal form: kill -9 (no graceful-exit hook
  # can pretend), restart, everything reads back. Both faces: the store
  # over BRP and the file on disk.
  local ok=true store
  pkill -9 -x t17-save 2>/dev/null; sleep 2
  pgrep -x t17-save >/dev/null && { log "L3: kill -9 left a process"; leg L3_KILL9_RESTART false; return; }
  direct_run l3 || { leg L3_KILL9_RESTART false; return; }
  store=$(gres "$SSTORE")
  echo "$store" > "$OUTDIR/l3-store-witness.json"
  echo "$store" | jq -e '.status == "Loaded"' >/dev/null 2>&1 \
    || { log "L3: status not Loaded ($store)"; ok=false; }
  echo "$store" | jq -e '.profile.progress.runs_played == 3' >/dev/null 2>&1 \
    || { log "L3: runs did not survive ($store)"; ok=false; }
  echo "$store" | jq -e '.profile.unlocks | index("endless")' >/dev/null 2>&1 \
    || { log "L3: unlock did not survive ($store)"; ok=false; }
  echo "$store" | jq -e '.profile.audio.master and .profile.audio.music and .profile.audio.sfx' >/dev/null 2>&1 \
    || { log "L3: audio did not survive ($store)"; ok=false; }
  feq "$(echo "$store" | jq -r '.profile.audio.master')" 0.7 \
    || { log "L3: audio master drifted ($(echo "$store" | jq -r '.profile.audio.master'))"; ok=false; }
  feq "$(echo "$store" | jq -r '.profile.audio.music')" 0.6 \
    || { log "L3: audio music drifted"; ok=false; }
  feq "$(echo "$store" | jq -r '.profile.audio.sfx')" 0.5 \
    || { log "L3: audio sfx drifted"; ok=false; }
  echo "$store" | jq -e '.profile.input[0].bindings[0].Key == "KeyE"' >/dev/null 2>&1 \
    || { log "L3: the rebind did not survive ($store)"; ok=false; }
  # The bridge order, live: the saved mix stands over the authored 0.42
  # (M6's "has a save" half), and the merged table keeps Move rebound.
  local cfg input
  cfg=$(gres "$GACONFIG")
  feq "$(res_num "$cfg" master)" 0.7 && feq "$(res_num "$cfg" music)" 0.6 \
    && feq "$(res_num "$cfg" sfx)" 0.5 \
    || { log "L3: the bridge did not restore the mix ($cfg)"; ok=false; }
  input=$(gres "$GINPUT")
  echo "$input" | jq -e '.actions[0].bindings[0].Key == "KeyE"' >/dev/null 2>&1 \
    || { log "L3: the merge did not restore the rebind ($input)"; ok=false; }
  echo "$input" | jq -e '.actions | length >= 5' >/dev/null 2>&1 \
    || { log "L3: the merge dropped default actions ($input)"; ok=false; }
  # The menu's display mirror reads the save through GameState (the
  # M8 menu face: what the Runs: line binds to).
  local state
  state=$(gres "$GSTATE")
  echo "$state" | jq -e '.runs_played == 3' >/dev/null 2>&1 \
    || { log "L3: the GameState mirror does not read the save ($state)"; ok=false; }
  echo "$state" | jq -e '.unlock_note | length > 0' >/dev/null 2>&1 \
    || { log "L3: the unlock note did not follow ($state)"; ok=false; }
  log "L3 kill -9 restart complete, ok=$ok"
  leg L3_KILL9_RESTART "$ok"
}

l7_slider() {
  # The settings screen, live: the pause screen's master slider exists
  # in the level's hud; fire the real widget event at it (decision 7-A:
  # the trigger chain, no pointer), the observer moves the config, the
  # watcher persists, and a restart restores both the mix and the
  # slider's position. If the reflected event cannot be fired over BRP
  # (entity serialization shape), the documented fallback is mutating
  # the slider's own field — the same resource the observer writes —
  # and the leg records which path landed.
  local ok=true slider sliderev="" wv
  press start
  # The marker rides two entities (the authored row and the attached
  # widget); only the widget carries the SliderValue, and it is the one
  # the event must target.
  local deadline=$((SECONDS + 15)) n=0
  while [ $SECONDS -lt $deadline ]; do
    slider=$(gbrp world.query "{\"data\":{\"components\":[\"$MASTERMARK\",\"$SLIDERVAL\"]}}" 2>/dev/null \
      | jq -r '[.result[]?][0].entity // empty' 2>/dev/null)
    [ -n "$slider" ] && break
    sleep 1
  done
  [ -n "$slider" ] || { log "L7: the master slider never spawned"; leg L7_SLIDER false; return; }
  # The entity payload must be JSON-shaped the way BRP spells entities
  # (a bare number or an id string, the query's own answer passed back).
  local srcjson="$slider"
  case "$slider" in *[!0-9]*) srcjson="\"$slider\"" ;; esac
  if gbrp world.trigger_event "{\"event\":\"$VC\",\"value\":{\"source\":$srcjson,\"value\":0.35,\"is_final\":true}}" >/dev/null 2>&1; then
    sleep 2
    wv=$(gres "$GACONFIG" | jq -r '.master // empty')
    if feq "$wv" 0.35; then sliderev="trigger"; fi
  fi
  if [ -z "$sliderev" ]; then
    log "L7: ValueChange trigger did not land; documented fallback (config mutate)"
    gmut "$GACONFIG" master 0.35 >/dev/null 2>&1
    sliderev="mutate-fallback"
  fi
  poll_save '.profile.audio.master' '0.35' 15 \
    || { log "L7: the slider change never persisted"; ok=false; }
  # The restart: both faces of "restored" — the mix, and the slider's
  # own position (the sync points the sliders back at the mix).
  pkill -9 -x t17-save 2>/dev/null; sleep 2
  direct_run l7 || { leg L7_SLIDER false; return; }
  press start
  deadline=$((SECONDS + 15)); slider=""
  while [ $SECONDS -lt $deadline ]; do
    slider=$(gbrp world.query "{\"data\":{\"components\":[\"$MASTERMARK\",\"$SLIDERVAL\"]}}" 2>/dev/null \
      | jq -r '[.result[]?][0].entity // empty' 2>/dev/null)
    [ -n "$slider" ] && break
    sleep 1
  done
  [ -n "$slider" ] || { log "L7: the slider did not spawn after restart"; ok=false; }
  if [ -n "$slider" ]; then
    # The sync points the slider at the restored mix within a frame of
    # its spawn; sample for a moment rather than race it.
    local pos num="" try=0
    while [ $try -lt 8 ]; do
      pos=$(gbrp world.get_components "{\"entity\":\"$slider\",\"components\":[\"$SLIDERVAL\"]}" 2>/dev/null \
        | jq -c --arg c "$SLIDERVAL" '.result.components[$c] // .result[$c] // empty' 2>/dev/null)
      num=$(echo "$pos" | jq -r '[.. | numbers] | first // empty' 2>/dev/null)
      feq "$num" 0.35 && break
      sleep 1
      try=$((try + 1))
    done
    log "L7: slider position after restart = $pos (want 0.35)"
    feq "$num" 0.35 || { log "L7: the slider did not follow the restored mix ($pos)"; ok=false; }
  fi
  # The SV9 face, green half: the attached slider is a real scene widget —
  # its entity carries the layout Node and the scene's children (track and
  # thumb), and the log carries zero scene-component rejections. The red
  # half (authored as a bare component line) is in the QA findings and the
  # *_red archives: no Node, no Children, three rejections per run.
  deadline=$((SECONDS + 15)); slider=""
  while [ $SECONDS -lt $deadline ]; do
    slider=$(gbrp world.query "{\"data\":{\"components\":[\"$FEATHERSSLIDER\"]}}" 2>/dev/null \
      | jq -r '[.result[]?][0].entity // empty' 2>/dev/null)
    [ -n "$slider" ] && break
    sleep 1
  done
  [ -n "$slider" ] || { log "L7: no attached slider entity found"; ok=false; }
  if [ -n "$slider" ]; then
    local sv9json
    sv9json=$(gbrp world.get_components "{\"entity\":\"$slider\",\"components\":[\"$UINODE\",\"$CHILDREN\"]}" 2>/dev/null \
      | jq -c '.result.components // empty' 2>/dev/null)
    log "L7: slider entity $slider = $sv9json"
    echo "$sv9json" | grep -q "bevy_ui::ui_node::Node" || { log "L7: slider has no Node (SV9 red form)"; ok=false; }
    echo "$sv9json" | grep -q "bevy_ecs::hierarchy::Children" || { log "L7: slider has no Children (SV9 red form)"; ok=false; }
  fi
  local sc_err
  sc_err=$(grep -ac "scene component" "$OUTDIR/direct-l7.log" 2>/dev/null)
  [ "${sc_err:-0}" = "0" ] || { log "L7: $sc_err scene-component rejections in this run"; ok=false; }
  # The PX half the plan always named: pause the game over BRP (the hud's
  # visibility binding shows the pause screen with the three sliders), and
  # capture the screen. The shot is evidence, not a pixel assert — the
  # mechanical truth is the Node/Children readback above.
  gbrp world.mutate_resources "{\"resource\":\"$GSTATE\",\"path\":\"paused\",\"value\":true}" >/dev/null 2>&1
  sleep 2
  if screencapture -x "$OUTDIR/shot-l7-pause-sliders.png" 2>/dev/null && [ -s "$OUTDIR/shot-l7-pause-sliders.png" ]; then
    log "L7: pause-screen shot captured (shot-l7-pause-sliders.png)"
  else
    log "L7: the pause-screen shot never landed"; ok=false
  fi
  gbrp world.mutate_resources "{\"resource\":\"$GSTATE\",\"path\":\"paused\",\"value\":false}" >/dev/null 2>&1
  echo "$sliderev" > "$OUTDIR/l7-path-witness.txt"
  log "L7 slider complete ($sliderev path), ok=$ok"
  leg L7_SLIDER "$ok"
}

m6_authored_vs_saved() {
  # The two layers, live: edit the authored asset to a new master (0.9);
  # with a save present the player's values still stand (0.35 — authored
  # default < player saved, and the file itself is untouched); delete
  # the save and the authored values stand in the fresh store; restore
  # the authored 0.42 canon.
  local ok=true cfg
  /usr/bin/sed -i '' 's|master: 0.42,|master: 0.9,|' "$PROJECT/assets/audio-config.bsn"
  grep -q "master: 0.9," "$PROJECT/assets/audio-config.bsn" \
    || { log "M6: the authored edit did not land"; leg M6_AUTHORED_VS_SAVED false; return; }
  stop_game
  direct_run m6 || { leg M6_AUTHORED_VS_SAVED false; return; }
  cfg=$(gres "$GACONFIG")
  feq "$(res_num "$cfg" master)" 0.35 \
    || { log "M6: the authored edit washed the saved mix ($cfg)"; ok=false; }
  [ "$(save_field '.profile.audio.master')" = "0.35" ] \
    || { log "M6: the save file itself changed ($(save_field '.profile.audio.master'))"; ok=false; }
  # No save, no override: the authored layer stands alone.
  stop_game
  rm -f "$(save_file)"
  direct_run m6fresh || { leg M6_AUTHORED_VS_SAVED false; return; }
  cfg=$(gres "$GACONFIG")
  feq "$(res_num "$cfg" master)" 0.9 \
    || { log "M6: the authored values did not stand with no save ($cfg)"; ok=false; }
  [ ! -f "$(save_file)" ] || { log "M6: a fresh run wrote a file"; ok=false; }
  stop_game
  write_authored_audio
  log "M6 authored-vs-saved complete, ok=$ok"
  leg M6_AUTHORED_VS_SAVED "$ok"
}

l4_corrupt() {
  # The live half of the three-state matrix: an empty save.json. The
  # store recovers (original bytes renamed into the backup), warns with
  # the path, hands the game defaults, and the next player change
  # repopulates the slot. The red log here is the leg's designed
  # evidence, not a failure — the warn scan attributes it.
  local ok=true store
  stop_game
  printf '' > "$(save_file)"
  direct_run l4 || { leg L4_M13_CORRUPT false; return; }
  store=$(gres "$SSTORE")
  echo "$store" > "$OUTDIR/l4-store-witness.json"
  # Recovered carries its backup name (an object form over BRP), so the
  # shape is judged by presence, not string equality.
  echo "$store" | grep -q "Recovered" \
    || { log "L4: status not Recovered ($store)"; ok=false; }
  local backups
  backups=$(ls "$SCRATCH"/save.json.corrupt-* 2>/dev/null | wc -l | tr -d ' ')
  [ "${backups:-0}" -ge 1 ] || { log "L4: no .corrupt backup on disk"; ok=false; }
  local warns
  warns=$(grep -ac "game save:" "$OUTDIR/direct-l4.log")
  [ "${warns:-0}" -ge 1 ] || { log "L4: no game save warn in the log"; ok=false; }
  grep -a "game save:" "$OUTDIR/direct-l4.log" | head -2 | sed 's/\x1b\[[0-9;]*m//g' >> "$OUTDIR/l4-warn-lines.txt"
  echo "$store" | jq -e '.profile.progress.runs_played == 0' >/dev/null 2>&1 \
    || { log "L4: defaults did not stand in ($store)"; ok=false; }
  # The slot repopulates on the next player change.
  gmut "$GACONFIG" master 0.6 >/dev/null 2>&1
  poll_save '.profile.audio.master' '0.6' 15 \
    || { log "L4: the slot never repopulated"; ok=false; }
  log "L4 corrupt complete, ok=$ok (backups=$backups, warns=$warns)"
  leg L4_M13_CORRUPT "$ok"
}

game_phase() {
  rm -f "$OUTDIR/summary-game.txt"
  rm -f "$OUTDIR/direct-"*.log

  stop_game
  flow_start_scene "menu.bsn"
  direct_run l1 || { log "GAME_PHASE: L1 run failed"; leg L1_FIRST_RUN false; }
  if game_up; then
    l1_first_run
    l2_four_classes
    l3_kill9_restart
    if game_up; then
      l7_slider
      m6_authored_vs_saved
    fi
    l4_corrupt
  fi

  # L8/M14: the standing warn scan over every channel's own stderr.
  # Zero tolerance: UnresolvedTypes / cannot-apply. The `game save:`
  # word appears ONLY in the corrupt leg's log, where it is the leg's
  # designed evidence (each line names the path and the fallback). The
  # template's benign states (a missing game-config.bsn / input-actions.bsn
  # starting at defaults) are attributed, not counted.
  sleep 2
  : > "$OUTDIR/warn-unattributed.log"
  : > "$OUTDIR/warn-attributed.log"
  local gl
  for gl in "$OUTDIR"/direct-*.log "$OUTDIR"/staged-run.log; do
    [ -f "$gl" ] || continue
    # The corrupt leg's warns are the leg's product; skip it here.
    case "$gl" in *l4.log) continue ;; esac
    grep -a "UnresolvedTypes\|cannot.apply\|cannot-apply\|scene component\|without its scene" "$gl" >> "$OUTDIR/warn-unattributed.log" 2>/dev/null || true
    grep -a "game save:" "$gl" | sed "s|^|$(basename "$gl"): |" >> "$OUTDIR/warn-unattributed.log" 2>/dev/null || true
    grep -a "no config asset" "$gl" | sed "s|^|attributed-template-state $(basename "$gl"): |" >> "$OUTDIR/warn-attributed.log" 2>/dev/null || true
  done
  local n13
  n13=$(grep -ac "panicked at" "$OUTDIR"/direct-*.log 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
  local unattr
  unattr=$(grep -c "" "$OUTDIR/warn-unattributed.log" 2>/dev/null)
  log "WARN_SCAN game phase: unattributed=${unattr:-0} (panics counted: ${n13:-0})"
  grep -an "panicked at" "$OUTDIR"/direct-*.log 2>/dev/null | head -5 > "$OUTDIR/n13-count.txt" || true
  if [ "${unattr:-0}" != "0" ]; then
    leg WARN_SCAN_GAME false
    log "unattributed warn lines (each must attribute):"
    cat "$OUTDIR/warn-unattributed.log"
  else
    leg WARN_SCAN_GAME true
  fi
  printf '%s\n' "$(results)" > "$OUTDIR/summary-game.txt"
  log "VERDICT_GAME_PHASE: $(results)"
}

# ---- editor phase -----------------------------------------------------------
l5_export() {
  # Export parity: a known save in the scratch, the staged tree ships
  # none, and the staged binary — pointed at the same slot — reads the
  # same numbers back. The export is editor-driven; the staged run is
  # the game's own.
  local ok=true
  stop_game
  flow_start_scene "menu.bsn"
  # Re-establish a known state in the slot (the game phase ended it at
  # the corrupt leg's fresh 0.6): fresh file, one known audio value.
  rm -f "$(save_file)"
  direct_run l5setup || { leg L5_EXPORT false; return; }
  gmut "$GACONFIG" master 0.75 >/dev/null 2>&1
  poll_save '.profile.audio.master' '0.75' 15 \
    || { log "L5: the setup mutate never landed"; leg L5_EXPORT false; return; }
  stop_game

  editor_boot "$PROJECT"
  wait_idle 600 >/dev/null
  export_wait || { log "L5: export never became ready"; leg L5_EXPORT false; return; }
  # The staged tree carries no player data (separate-from-scenes, the
  # M5 disk face), and the project's assets tree grew no save either.
  if find "$STAGED" -name "save.json" | grep -q .; then
    log "L5: the staged tree carries a save.json"; ok=false
  fi
  if find "$PROJECT/assets" -name "save.json" | grep -q .; then
    log "L5: the assets tree carries a save.json"; ok=false
  fi
  log "L5: staged tree clean of player data"
  if [ -x "$STAGED_EXE" ]; then
    (cd "$STAGED" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" \
      JACKDAW_SAVE_DIR="$SCRATCH" ./t17-save > "$OUTDIR/staged-run.log" 2>&1 &)
    wait_game 300 || { log "L5: staged game never came up"; ok=false; }
    sleep 10
    game_ready 240
    if game_up; then
      sleep 5
      local store cfg
      store=$(gres "$SSTORE")
      echo "$store" > "$OUTDIR/l5-store-witness.json"
      echo "$store" | jq -e '.status == "Loaded"' >/dev/null 2>&1 \
        || { log "L5: staged store not Loaded ($store)"; ok=false; }
      echo "$store" | jq -e '.profile.audio.master == 0.75' >/dev/null 2>&1 \
        || { log "L5: staged run did not read the same slot ($store)"; ok=false; }
      cfg=$(gres "$GACONFIG")
      echo "$cfg" | jq -e '.master == 0.75' >/dev/null 2>&1 \
        || { log "L5: staged bridge did not apply the saved mix ($cfg)"; ok=false; }
    fi
    pkill -x t17-save 2>/dev/null; sleep 2
  else
    log "L5: staged exe missing"
    ok=false
  fi
  log "L5 export parity complete, ok=$ok"
  leg L5_EXPORT "$ok"
}

l6_pie() {
  # The PIE single leg (N13 counted, no pointer work): Play runs the
  # real game with the editor's environment — the seam the editor boot
  # exported — so PIE writes the same slot a direct run reads back.
  # That is decision 6-A's same-slot semantics, live.
  local ok=true
  stop_game
  flow_start_scene "menu.bsn"
  # The stop invariant: the scene document does not change across a PIE
  # run, and no player data leaks into the assets tree.
  local sha_before sha_after
  sha_before=$(shasum -a 256 "$PROJECT/assets/menu.bsn" | awk '{print $1}')
  op pie.play_current >/dev/null 2>&1
  wait_game 900 || { log "L6: PIE game never came up"; leg L6_PIE_SLOT false; return; }
  game_ready 240
  sleep 5
  press start
  local player
  player=$(player_id) || { log "L6: PIE never spawned a player"; ok=false; }
  if [ -n "$player" ]; then
    gcomp_mut "$player" "$PHEALTH" current 0.0
    poll_save '.profile.progress.runs_played' '1' 25 \
      || { log "L6: PIE never counted a run (file says $(save_field '.profile.progress.runs_played'))"; ok=false; }
  fi
  op pie.play_input_toggle >/dev/null 2>&1
  op pie.stop >/dev/null 2>&1
  sleep 3
  pkill -x t17-save 2>/dev/null
  sleep 2
  sha_after=$(shasum -a 256 "$PROJECT/assets/menu.bsn" | awk '{print $1}')
  [ "$sha_before" = "$sha_after" ] \
    || { log "L6: menu.bsn sha changed across PIE"; ok=false; }
  find "$PROJECT/assets" -name "save.json" | grep -q . \
    && { log "L6: player data leaked into the assets tree"; ok=false; }
  # The same slot, read back by a plain direct run.
  direct_run l6check || { leg L6_PIE_SLOT false; return; }
  local store
  store=$(gres "$SSTORE")
  echo "$store" > "$OUTDIR/l6-store-witness.json"
  echo "$store" | jq -e '.status == "Loaded" and .profile.progress.runs_played == 1' >/dev/null 2>&1 \
    || { log "L6: the direct run did not read PIE's write ($store)"; ok=false; }
  local n13
  n13=$(grep -ac "panicked at" "$OUTDIR/editor-$PHASE.log" 2>/dev/null)
  log "L6 PIE complete, ok=$ok (editor panics counted: ${n13:-0})"
  grep -an "panicked at" "$OUTDIR/editor-$PHASE.log" 2>/dev/null | head -5 > "$OUTDIR/n13-editor-count.txt" || true
  stop_game
  leg L6_PIE_SLOT "$ok"
}

editor_phase() {
  rm -f "$OUTDIR/summary-editor.txt"
  l5_export
  l6_pie
  # The editor's own log: the standing scan (same word list, same
  # zero-tolerance), plus the N13 count.
  sleep 2
  local log="$OUTDIR/editor-$PHASE.log"
  local unattr n13
  unattr=$(grep -ac "UnresolvedTypes\|cannot.apply\|cannot-apply\|scene component\|without its scene" "$log" 2>/dev/null)
  n13=$(grep -ac "panicked at" "$log" 2>/dev/null)
  grep -an "panicked at" "$log" 2>/dev/null | head -5 > "$OUTDIR/n13-editor-count.txt" || true
  log "WARN_SCAN editor phase: zero_tolerance=${unattr:-0} (panics counted: ${n13:-0})"
  if [ "${unattr:-0}" != "0" ]; then
    leg WARN_SCAN_EDITOR false
  else
    leg WARN_SCAN_EDITOR true
  fi
  printf '%s\n' "$(results)" > "$OUTDIR/summary-editor.txt"
  log "VERDICT_EDITOR_PHASE: $(results)"
}

case "$PHASE" in
  prep) prep ;;
  game) game_phase ;;
  editor) editor_phase ;;
  all)
    prep
    game_phase
    editor_phase
    cat "$OUTDIR/summary-game.txt" "$OUTDIR/summary-editor.txt" 2>/dev/null | sort | tr '\n' ' ' > "$OUTDIR/summary.txt"
    log "VERDICT_ALL: $(cat "$OUTDIR/summary.txt")"
    log "T17_LIVE_DONE"
    ;;
  *) echo "unknown phase: $PHASE (prep|game|editor|all)"; exit 2 ;;
esac
