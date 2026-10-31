#!/bin/bash
# T20 example-game live legs (loop/plans/t20-example-game.md §三).
# T1 lands the helper library, the L1 prep legs and the three probes;
# the M1-M16 legs themselves land with T2 (the t19-live.sh precedent:
# T1 helpers + prep, T2 the matrix).
#
# Phases (each phase boots and cleans its own editor/game processes —
# run one per invocation):
#   prep    L1's clean half: jd new the fixture + the guards-style
#           template integrity precheck + scratch save dir + warm debug
#           build. NO remote injection — decision 3's pure package must
#           be exported from an un-injected project, so the injection
#           is its own phase and runs only after the pure legs.
#   inject  L1's test-seam half: the two-line sed (Cargo.toml dep +
#           main.rs plugin, t16-live.sh:458-469 form) + lock refresh +
#           warm rebuild. Idempotent.
#   probe   T1's probe 3 (plan §四-T1.3③): one beat of the PIE real
#           pointer in the fixed 1600x1000 window (A10 exposure
#           pre-judgment) — pie.play_current, frame_rect, the Start
#           band sweep, flow-move read on 15702.
#   pure    T2: M12/M13 — the pure-package isolation legs. MUST run
#           before `inject` (see the export order below).
#   box     T2: M1-M4 open-box chain + M3 win leg.
#   config  T2: M7-M10 the editor-configuration domains.
#   pie     T2: M6 the PIE full loop.
#   export  T2: M11/M14 the injected package.
#
# Decision 3 (probe 1, adjudicated A — double export), encoded here so
# T2 cannot mis-order it:
#   1. FIRST export = the pure package: on the `prep` fixture, BEFORE
#      `inject` ever ran. Serves M12 (env -i isolation) + M13 (otool /
#      manifest audit). Shipping-face and test-seam stay separate.
#   2. THEN `inject`, then the box/config/pie legs, then the SECOND
#      export = the injected package for M11 (staged full loop) + M14
#      (manifest reproducibility diff against a saved copy of #1).
#   Export criteria (both): export_wait holds until the export face's
#   started_at advances past the pre-call face AND the state returns
#   "ready" (the t19 lesson — a SHA-only criterion is pre-satisfied by
#   the previous export's tree); then staged assets/scene.bsn SHA must
#   equal the project's. The pure package is additionally MOVED OUT of
#   the project tree (cp -R to $PURE_DIST) before env -i runs — the
#   isolation assertion reads a tree that cargo/editor cannot reach.
#
# M2's seven-tuple (probe 2, plan §四-T1.3② — the restart-reset list,
# each field with its game-BRP channel; "stop/start" reads through
# SoundLive entity presence, document switch = DespawnOnExit):
#   1. health       PlayerHealth.current == .max == config 100.0 (default)
#   2. pickups      PickupCount.0 == 0
#   3. position     Transform.translation == PLAYER_SPAWN (-2, 1, 0)
#   4. props        With<Pickup> entity count == 3 (respawned)
#   5. MenuBgm      SoundLive present in Menu, GONE in Level ("stop")
#   6. Ambient      SoundLive present in Level, spatial ("start")
#   7. runs         GameState.runs_played: accumulates per run-over,
#                   survives kill -9 + restart (save.json mirror)
# The tuple is asserted before/after every Restart in M2 (x3 loops) and
# after the kill -9 in M5; field helpers live below (seven_tuple).
#
# Usage: bash loop/qa/t20-live.sh [phase]
#   phase: prep|inject|probe|pure|box|config|pie|export|all-prep
#   (all-prep = prep + inject, the pre-T2 fast path once the pure legs
#   are done.)
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
FIXROOT=/Users/zhanglinbo/workspace/loop-mac
PROJECT="$FIXROOT/t20-game"
PORT=15703
GAME_PORT=15702
OUTDIR="$REPO/loop/t20-live"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
STAGED="$PROJECT/.jackdaw/dist/release"
STAGED_EXE="$STAGED/t20-game"
PURE_DIST="$OUTDIR/t20-game-pure"
SAVE_SCRATCH="$OUTDIR/save-scratch"
CONFIG_SCRATCH="$OUTDIR/config-scratch"
# Game-side BRP type paths (defining module paths; the fixture's crate
# is t20_game — jd new t20-game).
NAME='bevy_ecs::name::Name'
PHEALTH='t20_game::PlayerHealth'
PCOUNT='t20_game::PickupCount'
PICKUP='t20_game::Pickup'
TRANSFORM='bevy_transform::components::transform::Transform'
SLIVE='t20_game::SoundLive'
GSTATE='t20_game::GameState'
# M15's warn scan pattern (plan §二): every hit is attributed, not just
# counted.
WARN_PATTERN='UnresolvedTypes|panicked|SceneRefused|BindContext|failed|refused'
mkdir -p "$OUTDIR"
PHASE="${1:-all-prep}"
CONSOLE_LOG="$OUTDIR/console-$PHASE.log"
: > "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t20-live.XXXXXX)"
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
  pkill -x t20-game 2>/dev/null
  sleep 1
}
trap cleanup EXIT

# ---- transport (t16/t19 form: brp retry, gbrp settle, op, idle) -------------
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
  # A9: the game BRP answers intermittently empty in busy windows —
  # reads retry with a short settle; writes verify through a read.
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
  pkill -x t20-game 2>/dev/null
  sleep 2
}
editor_boot() { # editor_boot [project] — the DYLD prefix is the editor's own
                # requirement; the staged PURE package must never get it (the
                # M12 asymmetry IS the isolation assertion's body).
  pkill -x jackdaw 2>/dev/null; pkill -x t20-game 2>/dev/null; sleep 1
  local boot_log="$OUTDIR/editor-$PHASE.log"
  if [ -n "${1:-}" ]; then
    export JACKDAW_OPEN_PROJECT="$1"
  else
    unset JACKDAW_OPEN_PROJECT
  fi
  # The fixed 1600x1000 window is the A10 containment (plan §0 fact
  # 15; T16 L4's working geometry) — do not boot without it.
  export JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1600x1000
  cd "$REPO"
  nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$boot_log" 2>&1 &
  local ok=""
  for i in $(seq 1 150); do
    sleep 2
    if brp jackdaw/status '{}' >/dev/null 2>&1 && pgrep -x jackdaw >/dev/null; then ok=1; break; fi
    pgrep -x jackdaw >/dev/null || break
  done
  [ -n "$ok" ] || { log "EDITOR_BOOT_FAIL"; exit 1; }
  sleep 5
  wait_idle 900 >/dev/null; sleep 3; dismiss_dialog
  log "EDITOR_READY project=${1:-none}"
}
open_scene() {
  op scene.open "{\"path\":\"$PROJECT/assets/$1\",\"reload\":true}" >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
}
game_ready() { # game_ready [timeout] — world.* answers on 15702
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
gid() { # gid <name> — the game entity id carrying this Name
  gbrp world.query "{\"data\":{\"components\":[\"$NAME\"]}}" 2>/dev/null \
    | jq -r --arg n "$1" '[.result[]? | select(.components["'"$NAME"'"] == $n) | .entity][0]' 2>/dev/null
}
gcomp() { # gcomp <id> <component> — a game entity's component JSON
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
gsound() { gcomp "$(gid "$1")" "$SLIVE" 2>/dev/null; }
gsound_wait() { # gsound_wait <name> [attempts] — the mirror rides one
                # frame behind the sink (T16 口径)
  local name="$1" attempts="${2:-10}" n=0 out=""
  while [ $n -lt "$attempts" ]; do
    out=$(gsound "$name")
    [ -n "$out" ] && { echo "$out"; return 0; }
    sleep 1
    n=$((n + 1))
  done
  echo ""
}
pickup_count() { # pickup_count — With<Pickup> entity count (M2 field 4)
  gbrp world.query "{\"data\":{\"components\":[\"$PICKUP\"]}}" 2>/dev/null \
    | jq '.result | length' 2>/dev/null
}
flow_state() { # flow_state — the State<GameFlow> resource read (win-leg judge)
  gbrp world.get_resources "{\"resource\":\"bevy_ecs::state::state_res::State<t20_game::GameFlow>\"}" 2>/dev/null \
    | head -c 300
}
n13_count() { # n13_count — the N13 PIE drain panic counter (Mac 100%
              # recurrence; bypass+count is the T13 discipline)
  grep -c "panicked" "$OUTDIR/editor-$PHASE.log" 2>/dev/null || echo 0
}
warn_scan() { # warn_scan <logfile> <tag> — every hit attributed
  local file="$1" tag="$2" hits
  [ -f "$file" ] || { log "warn-scan $tag: no log at $file"; return 0; }
  hits=$(grep -inE "$WARN_PATTERN" "$file" | grep -v "warn-scan" | head -40)
  if [ -z "$hits" ]; then
    log "warn-scan $tag: clean"
  else
    log "warn-scan $tag: $(echo "$hits" | wc -l | tr -d ' ') hits:"
    echo "$hits" | while IFS= read -r line; do log "warn-scan $tag | $line"; done
  fi
}
direct_run() { # direct_run <tag> — cargo run the fixture with the scratch
               # save dir (decision 7), log to direct-<tag>.log
  (cd "$PROJECT" && JACKDAW_SAVE_DIR="$SAVE_SCRATCH" nohup cargo run > "$OUTDIR/direct-$1.log" 2>&1 &)
  wait_game 600 || { log "direct_run $1: game never came up"; return 1; }
  game_ready 240
  sleep 5
}
export_face() { # export_face — "<state> <started_at>" of the export face
  brp jackdaw/export '{}' 2>/dev/null | jq -r '"\(.result.state // "none") \(.result.started_at // 0)"' 2>/dev/null
}
export_wait() { # export_wait — the decision-3 criteria in one helper:
                # started_at must advance past the pre-call face AND the
                # state must return "ready"; then the staged scene.bsn SHA
                # must equal the project's (the caller judges that part).
  local before st started
  read -r before _ <<< "$(export_face)"
  op game.export '{}' >/dev/null 2>&1
  local deadline=$((SECONDS + 1500))
  while [ $SECONDS -lt $deadline ]; do
    read -r st started <<< "$(export_face)"
    if [ "$started" != "$before" ] && [ "$st" = "ready" ]; then
      log "export_wait: run advanced ($before -> $started) and is ready"
      return 0
    fi
    if [ "$started" = "$before" ] && [ "$st" = "ready" ] && [ $SECONDS -gt 30 ]; then
      log "export_wait: the face never left the pre-call run ($before, state $st) — treating as completed-no-rerun"
      return 1
    fi
    sleep 5
  done
  return 1
}
seven_tuple() { # seven_tuple <tag> — the M2 restart-reset list, one JSON
                # line per field probe (probe 2's finalized list; the M2
                # legs compare before/after Restart)
  local tag="$1" pid
  pid=$(gid Player)
  {
    printf '%s health %s\n' "$tag" "$(gcomp "$pid" "$PHEALTH")"
    printf '%s pickups %s\n' "$tag" "$(gcomp "$pid" "$PCOUNT")"
    printf '%s position %s\n' "$tag" "$(gcomp "$pid" "$TRANSFORM")"
    printf '%s props %s\n' "$tag" "$(pickup_count)"
    printf '%s menubgm %s\n' "$tag" "$(gsound MenuBgm)"
    printf '%s ambient %s\n' "$tag" "$(gsound_wait Ambient 4)"
    printf '%s runs %s\n' "$tag" "$(gbrp world.get_resources "{\"resource\":\"$GSTATE\"}" 2>/dev/null | head -c 200)"
  } >> "$OUTDIR/seven-tuple-$tag.txt"
  log "seven_tuple $tag: archived to seven-tuple-$tag.txt"
}

# ---- phase: prep (L1 clean half — decision 3 keeps it injection-free) --------
prep() {
  pkill -x jackdaw 2>/dev/null; pkill -x t20-game 2>/dev/null; sleep 1

  # Tooling sanity: the jd binary must EXECUTE. A gate run with
  # --features dylib relinks target/debug/jd into its dynamic flavor
  # (the editor's: it then needs DYLD_LIBRARY_PATH=toolchain lib) —
  # say so instead of dying in dyld.
  if ! ./target/debug/jd --version >/dev/null 2>&1; then
    log "PREP_FAIL target/debug/jd does not execute (dylib-flavored after a --features dylib gate?); rebuild the static flavor first: cargo build -p jd"
    exit 1
  fi

  # The fixture: a fresh jd new every time (the matrix's premise is a
  # cold project; the t17-live.sh:344 form).
  if [ -d "$PROJECT" ]; then
    log "prep: removing the stale fixture $PROJECT"
    rm -rf "$PROJECT"
  fi
  (cd "$REPO" && ./target/debug/jd new t20-game --path "$FIXROOT" --no-git > "$OUTDIR/jd-new.log" 2>&1) \
    || { log "PREP_FAIL jd new: $(tail -3 "$OUTDIR/jd-new.log")"; exit 1; }
  grep -q "GamePlugin" "$PROJECT/src/main.rs" || { log "PREP_FAIL fixture lacks the game template main"; exit 1; }

  # Template integrity precheck (L1; the guards' grep set on the
  # materialized fixture — the same needles the teaches tests pin).
  local lib="$PROJECT/src/lib.rs"
  for needle in \
    "enum GameFlow" "fn collect_pickups" "fn update_game_over" \
    "flow.set(GameFlow::GameOver)" "Level clear" \
    "struct GameSave" "runs_played" "struct SoundLive" \
    "struct GameAudioConfig" "MasterVolumeSlider" "MusicVolumeSlider" "SfxVolumeSlider" \
    "struct Pickup" "struct Hazard" "const PLAYER_SPAWN" \
    "jackdaw_avian_integration::TriggerPlugin" "jackdaw_remote NOT EXPECTED"; do
    if [ "$needle" = "jackdaw_remote NOT EXPECTED" ]; then
      # The shipping face is seam-free until `inject` runs (T18 dormant
      # discipline): prep's fixture must NOT carry the remote dep.
      grep -q jackdaw_remote "$PROJECT/Cargo.toml" \
        && { log "PREP_FAIL fixture already injected — decision 3 needs a clean prep first"; exit 1; }
    elif ! grep -qF "$needle" "$lib" && ! grep -qF "$needle" "$PROJECT/assets/hud.bsn" 2>/dev/null; then
      log "PREP_FAIL template integrity: needle missing: $needle"
      exit 1
    fi
  done
  for f in bgm blip ambient; do
    [ -f "$PROJECT/assets/sounds/$f.wav" ] || { log "PREP_FAIL sounds/$f.wav missing"; exit 1; }
  done
  grep -q "MenuBgm" "$PROJECT/assets/menu.bsn" || { log "PREP_FAIL menu.bsn lacks MenuBgm"; exit 1; }
  [ -f "$PROJECT/assets/game.flow.json" ] || { log "PREP_FAIL flow seed missing"; exit 1; }
  [ "$(jq -r '.start_scene // empty' "$PROJECT/assets/game.flow.json" 2>/dev/null)" = "menu.bsn" ] \
    || { log "PREP_FAIL flow start_scene is not menu.bsn (the matrix's premise)"; exit 1; }
  [ "$(jq -r '[.scenes[]] | length' "$PROJECT/assets/game.flow.json" 2>/dev/null)" = "3" ] \
    || { log "PREP_FAIL flow does not list the three documents"; exit 1; }

  # Decision 7: the scratch save dir — runs_played assertions stay
  # deterministic and the real user save is never touched.
  rm -rf "$SAVE_SCRATCH"; mkdir -p "$SAVE_SCRATCH"
  log "prep: save scratch = $SAVE_SCRATCH (JACKDAW_SAVE_DIR on every game run)"

  # Warm the game build so the legs are not cold compiles.
  (cd "$PROJECT" && cargo build > "$OUTDIR/game-warmbuild-prep.log" 2>&1) \
    || { log "PREP_FAIL game warm build: $(tail -3 "$OUTDIR/game-warmbuild-prep.log")"; exit 1; }
  log "PREP_OK fixture=$PROJECT (clean — run the inject phase only after the pure legs)"
}

# ---- phase: inject (L1 test-seam half; idempotent) ---------------------------
inject() {
  [ -d "$PROJECT" ] || { log "INJECT_FAIL fixture missing; run prep first"; exit 1; }
  if grep -q jackdaw_remote "$PROJECT/Cargo.toml"; then
    log "inject: already present, skipping the sed (idempotent)"
  else
    /usr/bin/sed -i '' "s|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = \[\"terrain\", \"pie\"\] }|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = [\"terrain\", \"pie\"] }\njackdaw_remote = { path = '$REPO/crates/jackdaw_remote' }|" "$PROJECT/Cargo.toml"
    grep -q jackdaw_remote "$PROJECT/Cargo.toml" || { log "INJECT_FAIL no remote dep"; exit 1; }
    /usr/bin/sed -i '' 's|\.add_plugins(jackdaw_runtime::JackdawPlugin)|.add_plugins(jackdaw_runtime::JackdawPlugin)\n        .add_plugins(jackdaw_remote::JackdawRemotePlugin::default())|' "$PROJECT/src/main.rs"
    grep -q JackdawRemotePlugin "$PROJECT/src/main.rs" || { log "INJECT_FAIL no remote plugin"; exit 1; }
    (cd "$PROJECT" && cargo metadata --format-version 1 >/dev/null 2>"$OUTDIR/lockfix.log") \
      || { log "INJECT_FAIL lock refresh: $(tail -2 "$OUTDIR/lockfix.log")"; exit 1; }
  fi
  # Warm rebuild so the box legs are not cold compiles.
  (cd "$PROJECT" && cargo build > "$OUTDIR/game-warmbuild-inject.log" 2>&1) \
    || { log "INJECT_FAIL warm rebuild: $(tail -3 "$OUTDIR/game-warmbuild-inject.log")"; exit 1; }
  log "INJECT_OK remote seam in place (shipping-face purity was the pre-inject exports')"
}

# ---- phase: probe (T1 probe 3 — the PIE real pointer beat) -------------------
probe() {
  # A10 exposure pre-judgment in the fixed 1600x1000 window, the T16
  # L4 form: pie.play_current, the streamed frame rect, capture on,
  # the Start-band sweep, then the flow move read on 15702. One beat —
  # the verdict (usable / needs the trigger_event fallback) goes in the
  # T1 report and sets M6's primary channel.
  local ok=true
  editor_boot "$PROJECT"
  open_scene menu.bsn
  op pie.play_current '{}' >/dev/null 2>&1
  wait_game 900 || { log "probe: PIE game never came up"; leg PROBE_PIE_UP false; return; }
  game_ready 240; sleep 5
  leg PROBE_PIE_UP true

  frame_rect() {
    brp jackdaw/ui_tree '{"kind":"node","visible_only":true,"depth":80}' 2>/dev/null \
      | jq -r '[.. | objects | select(.name? // "" | test("Game|Play|Stream"; "i")) | .rect? // empty] | .[0] // empty' 2>/dev/null
  }
  local rect
  rect=$(frame_rect)
  log "probe: frame rect probe gave: ${rect:-<none>}"
  # The t16 L4 geometry: at 1600x1000 the game panel docks as the
  # bottom strip and the menu's Start sits near the panel's centre
  # line. Sweep that band regardless of what the rect read gave.
  op pie.play_input_toggle '{}' >/dev/null 2>&1
  sleep 1
  local dy dx hit=""
  for dy in 871 851 891 831 911; do
    for dx in 0 -60 60 -120 120; do
      op input.pointer "{\"x\":$((800 + dx)),\"y\":$dy,\"action\":\"click\",\"button\":\"primary\"}" >/dev/null 2>&1
      # The flow moved if the level's Ambient sound appears (document
      # switch = DespawnOnExit semantics, the t16 stop word).
      local n=0 amb
      while [ $n -lt 12 ]; do
        amb=$(gsound_wait Ambient 1)
        if [ -n "$amb" ]; then hit="($((800 + dx)),$dy)"; break 2; fi
        sleep 0.25
        n=$((n + 1))
      done
    done
  done
  if [ -n "$hit" ]; then
    leg PROBE_PIE_POINTER true
    log "probe: REAL POINTER reached the game UI at $hit — M6's primary channel is usable in the fixed window"
  else
    leg PROBE_PIE_POINTER false
    log "probe: the band sweep never moved the flow — M6 defaults to the trigger_event fallback (decision 4's recorded downgrade), and the A10 exposure note grows one line"
  fi
  op pie.play_input_toggle '{}' >/dev/null 2>&1
  op pie.stop '{}' >/dev/null 2>&1
  sleep 2
  log "N13 counter (panicked lines in the editor log): $(n13_count)"
  warn_scan "$OUTDIR/editor-$PHASE.log" "probe"
}

# ---- T2 phase stubs (the legs land with T2; the ordering contract is
# already binding — see the header) --------------------------------------------
pure() { log "pure: T2 lands M12/M13 here (MUST run before inject)"; }
box() { log "box: T2 lands M1-M4 (+M3 win) here"; }
config_phase() { log "config: T2 lands M7-M10 here"; }
pie_phase() { log "pie: T2 lands M6 here"; }
export_phase() { log "export: T2 lands M11/M14 here (after box/config/pie)"; }

case "$PHASE" in
  prep) prep ;;
  inject) inject ;;
  probe) probe ;;
  pure) pure ;;
  box) box ;;
  config) config_phase ;;
  pie) pie_phase ;;
  export) export_phase ;;
  all-prep) prep; inject ;;
  *) log "unknown phase $PHASE (prep|inject|probe|pure|box|config|pie|export|all-prep)"; exit 2 ;;
esac
log "RESULTS: $(results)"
