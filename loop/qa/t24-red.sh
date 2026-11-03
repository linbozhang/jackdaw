#!/bin/bash
# T24-T1 red evidence: DF-R1/R2/R3 archived on the PRE-FIX build (main
# a63fcb84, loop/t24-debug base). The plan's red-state discipline: archive
# before the construction edits exist, in windows of their own.
#
#   DF-R1 (W2)  break one line of the game template -> Play build fails ->
#               the Build panel holds the whole rendered log (the `-->
#               file:line:col` text is on screen) and nothing about it is
#               actionable: the walk of the Build window shows no per-row
#               nodes and no button labels, and the failure latch carries no
#               structured row list anywhere.
#   DF-R2 (A8)  a scene document spelling a crate-root re-export component
#               path loads with the patch dropped: the console's only mouth
#               is the bare "type not in the registry" line plus the
#               misleading "rebuild the project" remedy; the component does
#               not land (BRP absence), and neither the audit nor the
#               Missing References list carries a row for it.
#   DF-R3 (W1)  a scene document with an unknown field warns into the log
#               only: the panel face answers "no broken references" — zero
#               structured rows for a problem the console did name.
#
# Readable-face calibre (carried from t23-live.sh): BRP entity ids are
# strings and must be quoted; reads ride the flaky window with retries; one
# trigger source per leg; RUST_BACKTRACE is never set; the red windows and
# the construction work never share a window.
#
# Phases: prep | dfr1 | dfr23 | all
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
FIXROOT=/Users/zhanglinbo/workspace/loop-mac/t24-debug
PROJECT="$FIXROOT/t24-red"
PORT=15703
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
OUTDIR="$REPO/loop/t24-red"
PHASE="${1:-all}"
WINDOW=0
EDITOR_LOG="$OUTDIR/editor-$PHASE.log"
CONSOLE_LOG="$OUTDIR/console-$PHASE.log"
GAME_LIB="$PROJECT/src/lib.rs"
mkdir -p "$OUTDIR"

RESULTS_FILE="$(mktemp /tmp/t24-red.XXXXXX)"
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
cleanup() { pkill -x jackdaw 2>/dev/null; sleep 1; }
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
  local method="$1" params="${2:-}" attempt out
  for attempt in 1 2 3 4 5 6 7 8; do
    out=$(brp_raw "$method" "$params")
    if [ -n "$out" ] && ! echo "$out" | grep -q "expected value at line 1"; then
      echo "$out"; return 0
    fi
    sleep 3
  done
  echo "$out"; return 1
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
walk() { brp jackdaw/ui_tree '{"kind":"node","visible_only":true,"depth":80}' > "$1" 2>/dev/null; }
has_in() { grep -qFe "$2" "$1" 2>/dev/null; } # has_in <file> <needle> (-e: a needle may start with `-->`)

editor_boot() { # editor_boot <suppress_prebuild: 0|1>
  pkill -x jackdaw 2>/dev/null; sleep 1
  WINDOW=$((WINDOW + 1))
  EDITOR_LOG="$OUTDIR/editor-$PHASE-$WINDOW.log"
  : > "$EDITOR_LOG"
  export JACKDAW_OPEN_PROJECT="$PROJECT"
  export JACKDAW_PIE_PREBUILD="$1"
  export JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1600x1000
  cd "$REPO"
  nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$EDITOR_LOG" 2>&1 &
  echo $! > "$OUTDIR/boot-pid.txt"
  local ok=""
  for i in $(seq 1 150); do
    sleep 2
    if brp jackdaw/status '{}' >/dev/null 2>&1 && pgrep -x jackdaw >/dev/null; then ok=1; break; fi
    pgrep -x jackdaw >/dev/null || break
  done
  [ -n "$ok" ] || { log "EDITOR_BOOT_FAIL"; exit 1; }
  sleep 5
  wait_idle 900 >/dev/null; sleep 3; dismiss_dialog
  walk "$OUTDIR/walk-boot-$PHASE-$WINDOW.json"
  if has_in "$OUTDIR/walk-boot-$PHASE-$WINDOW.json" "Recovered Work"; then
    op dialog.answer '{"id":"recovery.dismiss","params":{}}' >/dev/null 2>&1
    brp jackdaw/ui_click '{"text":"Discard All"}' >/dev/null 2>&1
    sleep 2; wait_idle 120 >/dev/null
  fi
  log "EDITOR_READY window=$WINDOW prebuild=$1"
}

open_scene() {
  op scene.open "{\"path\":\"$1\",\"reload\":true}" >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
}

# ---- phase: prep -------------------------------------------------------------
prep() {
  local free
  free=$(df -g / | awk 'NR==2 {print $4}')
  [ "$free" -ge 10 ] || { log "PREP_FAIL only ${free}Gi free"; exit 1; }
  log "disk: ${free}Gi free"
  rm -rf "$FIXROOT"; mkdir -p "$FIXROOT" "$OUTDIR"
  (cd "$REPO" && DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jd new t24-red --path "$FIXROOT" --no-git) > "$OUTDIR/jd-new.log" 2>&1
  [ -d "$PROJECT" ] || { log "PREP_FAIL no project ($(tail -2 "$OUTDIR/jd-new.log"))"; exit 1; }
  python3 - "$PROJECT" "$REPO" << 'PYT'
import sys
project, repo = sys.argv[1], sys.argv[2]
toml_path = f"{project}/Cargo.toml"
text = open(toml_path).read()
if "jackdaw_remote" not in text:
    needle = "jackdaw_runtime = { path = "
    line_start = text.index(needle)
    line_end = text.index("\n", line_start)
    remote = f"\njackdaw_remote = {{ path = '{repo}/crates/jackdaw_remote' }}"
    text = text[:line_end] + remote + text[line_end:]
    open(toml_path, "w").write(text)
main_path = f"{project}/src/main.rs"
main = open(main_path).read()
if "JackdawRemotePlugin" not in main:
    marker = "::GamePlugin)"
    at = main.index(marker) + len(marker)
    main = main[:at] + "\n        .add_plugins(jackdaw_remote::JackdawRemotePlugin::default())" + main[at:]
    open(main_path, "w").write(main)
print("injected")
PYT
  grep -q jackdaw_remote "$PROJECT/Cargo.toml" || { log "PREP_FAIL no remote dep"; exit 1; }
  grep -q JackdawRemotePlugin "$PROJECT/src/main.rs" || { log "PREP_FAIL no remote plugin"; exit 1; }
  (cd "$PROJECT" && cargo metadata --format-version 1 >/dev/null 2>"$OUTDIR/lockfix.log") \
    || { log "PREP_FAIL lock refresh: $(tail -2 "$OUTDIR/lockfix.log")"; exit 1; }
  # The persisted tab journal would restore whatever the last window held;
  # every red window starts on the canonical starter scene.
  python3 - "$PROJECT/.jackdaw/project.json" << 'PYT'
import json, sys
path = sys.argv[1]
try:
    cfg = json.load(open(path))
    cfg.pop("layout", None)
    cfg["last_open_tabs"] = ["assets/scene.bsn"]
    cfg["last_active_tab"] = 0
    json.dump(cfg, open(path, "w"), indent=2)
except FileNotFoundError:
    pass
PYT
  log "PREP_OK fixture=$PROJECT"
}

# ---- phase: dfr1 (W2) --------------------------------------------------------
dfr1() {
  editor_boot 0
  log "--- DF-R1 warm build (first build fills .jackdaw/target) ---"
  op project.build >/dev/null 2>&1
  local warm=""
  for i in $(seq 1 240); do
    sleep 10
    if [ -f "$PROJECT/.jackdaw/schema.json" ] && grep -q "project build" "$EDITOR_LOG" 2>/dev/null; then :; fi
    # The build's end is the schema landing plus a quiet log; poll both.
    if [ -f "$PROJECT/.jackdaw/schema.json" ]; then
      if ! pgrep -f "cargo.*--target-dir" >/dev/null 2>&1; then warm=1; break; fi
    fi
  done
  [ -n "$warm" ] || log "DFR1_WARM_UNVERIFIED (continuing; assertions judge the failure leg)"
  log "--- DF-R1 break the template and fail the Play build ---"
  cp "$GAME_LIB" "$OUTDIR/lib.rs.pristine"
  printf '\nfn t24_red_breakage() {\n    let x: i32 = "five";\n}\n' >> "$GAME_LIB"
  op pie.play_current >/dev/null 2>&1
  local failed=""
  for i in $(seq 1 60); do
    sleep 5
    if grep -q "PIE: game build of .* failed" "$EDITOR_LOG" 2>/dev/null; then failed=1; break; fi
  done
  [ -n "$failed" ] && leg DFR1_BUILD_FAILED_LATCH true || leg DFR1_BUILD_FAILED_LATCH false
  sleep 3
  dismiss_dialog
  walk "$OUTDIR/walk-dfr1.json"
  # The whole rendered log is on screen: the rustc arrow line rides the text.
  has_in "$OUTDIR/walk-dfr1.json" "--> src/lib.rs" && leg DFR1_LOG_FULL_TEXT_ON_PANEL true || leg DFR1_LOG_FULL_TEXT_ON_PANEL false
  has_in "$OUTDIR/walk-dfr1.json" "Build failed" && leg DFR1_FAILED_STATUS_RENDERED true || leg DFR1_FAILED_STATUS_RENDERED false
  # The red half of W2: nothing about those rows is actionable. The Build
  # window's subtree holds no button labels and no per-row action face —
  # the walk is archived in full for the cell-by-cell read.
  python3 - "$OUTDIR/walk-dfr1.json" << 'PYT' >> "$CONSOLE_LOG" 2>&1
import json, re, sys
text = open(sys.argv[1]).read()
# The Build panel's subtree: from the "Build failed" text to the end of its
# window scope is not directly addressable in the flat walk, so the count is
# over the whole walk minus every label the status bar legitimately owns.
action_labels = ["Rebind", "Locate", "Copy", "Show in Finder", "Reveal"]
hits = [label for label in action_labels if label in text]
print("DFR1_ACTION_LABELS_IN_WALK", hits if hits else "none")
arrows = re.findall(r"-->\s*\S+:\d+:\d+", text)
print("DFR1_ARROW_LINES_PRESENT", len(arrows))
PYT
  cp "$EDITOR_LOG" "$OUTDIR/editor-dfr1-final.log"
  log "DFR1 evidence: walk-dfr1.json + editor-dfr1-final.log"
}

# ---- phase: dfr23 (A8 + W1) ---------------------------------------------------
dfr23() {
  # The template line window 1 broke must not leak into this window.
  if [ -f "$OUTDIR/lib.rs.pristine" ]; then cp "$OUTDIR/lib.rs.pristine" "$GAME_LIB"; fi
  editor_boot 0
  cat > "$PROJECT/assets/t24r2.bsn" << 'EOF'
// DF-R2 (A8): the graph-family component spelled by its crate-root
// re-export instead of its definition module path.
#RedEntity
bevy_transform::components::transform::Transform
jackdaw_animation_runtime::AnimationGraphRef {
    path: "graphs/move.animgraph",
    skeleton_root: "Root",
}
EOF
  log "--- DF-R2 open the re-export-path scene ---"
  open_scene "assets/t24r2.bsn"
  sleep 3
  # The console mouth: the bare not-in-registry line, repeated, plus the
  # misleading rebuild remedy.
  local cryptic remedy
  cryptic=$(grep -c "cannot apply 'jackdaw_animation_runtime::AnimationGraphRef': type not in the registry" "$EDITOR_LOG" 2>/dev/null || echo 0)
  remedy=$(grep -c "rebuild the project so the editor picks up its types" "$EDITOR_LOG" 2>/dev/null || echo 0)
  [ "${cryptic:-0}" -ge 1 ] && leg DFR2_CRYPTIC_WARN_IN_CONSOLE true || leg DFR2_CRYPTIC_WARN_IN_CONSOLE false
  [ "${remedy:-0}" -ge 1 ] && leg DFR2_MISLEADING_REMEDY_IN_CONSOLE true || leg DFR2_MISLEADING_REMEDY_IN_CONSOLE false
  log "DFR2 console: cryptic_warns=$cryptic remedy_lines=$remedy"
  # The component does not land: the registered (definition) path answers
  # nothing for RedEntity while Transform proves the entity is real.
  local transforms graphs
  transforms=$(brp world.query '{"data":{"components":["bevy_transform::components::transform::Transform"]}}' 2>/dev/null | jq '[.result | keys[] | select(. != "error")] | length' 2>/dev/null)
  graphs=$(brp world.query '{"data":{"components":["jackdaw_animation_runtime::graph::AnimationGraphRef"]}}' 2>/dev/null | jq '[.result | keys[] | select(. != "error")] | length' 2>/dev/null)
  log "DFR2 world: entities_with_transform=$transforms entities_with_graphref=$graphs (RedEntity must hold Transform and no GraphRef)"
  [ "${graphs:-0}" = "0" ] && leg DFR2_COMPONENT_ABSENT true || leg DFR2_COMPONENT_ABSENT false
  # No structured face anywhere: the audit's findings and the Missing
  # References list both stay empty for this binding problem.
  local audit_findings
  audit_findings=$(brp jackdaw/audit '{}' 2>/dev/null | jq '.result.findings | length' 2>/dev/null)
  log "DFR2 audit findings for the re-export scene: ${audit_findings:-ERR}"
  [ "${audit_findings:-1}" = "0" ] && leg DFR2_AUDIT_ZERO_ROWS true || leg DFR2_AUDIT_ZERO_ROWS false
  op asset.missing_list >/dev/null 2>&1
  sleep 2
  walk "$OUTDIR/walk-dfr2.json"
  has_in "$OUTDIR/walk-dfr2.json" "no broken references" && leg DFR2_LIST_SAYS_NOTHING true || leg DFR2_LIST_SAYS_NOTHING false

  log "--- DF-R3 open the unknown-field scene ---"
  cat > "$PROJECT/assets/t24r3.bsn" << 'EOF'
// DF-R3 (W1): a registered component carrying a field it does not declare.
#RedField
bevy_transform::components::transform::Transform {
    translation: glam::Vec3 { x: 1.0, y: 2.0, z: 3.0 },
    nonexistent_field: 5.0,
}
EOF
  open_scene "assets/t24r3.bsn"
  sleep 3
  local unknowns
  unknowns=$(grep -c "unknown field 'nonexistent_field' on 'bevy_transform::components::transform::Transform'" "$EDITOR_LOG" 2>/dev/null || echo 0)
  [ "${unknowns:-0}" -ge 1 ] && leg DFR3_LOG_ONLY_WARN true || leg DFR3_LOG_ONLY_WARN false
  log "DFR3 console: unknown_field_warns=$unknowns"
  # The panel face knows nothing of it: the list answers no problems.
  op asset.missing_list >/dev/null 2>&1
  sleep 2
  walk "$OUTDIR/walk-dfr3.json"
  has_in "$OUTDIR/walk-dfr3.json" "no broken references" && leg DFR3_PANEL_ZERO_ROWS true || leg DFR3_PANEL_ZERO_ROWS false
  # The red half of W1: the console names the field, the panel does not.
  # (Post-fix the binding rows render the field and this flips green.)
  has_in "$OUTDIR/walk-dfr3.json" "nonexistent_field" && leg DFR3_FIELD_NAME_ABSENT_FROM_PANEL false || leg DFR3_FIELD_NAME_ABSENT_FROM_PANEL true
  cp "$EDITOR_LOG" "$OUTDIR/editor-dfr23-final.log"
  log "DFR23 evidence: walk-dfr2.json walk-dfr3.json editor-dfr23-final.log"
}

case "$PHASE" in
  prep) prep ;;
  dfr1) dfr1 ;;
  dfr23) dfr23 ;;
  all) prep; dfr1; dfr23 ;;
  *) log "unknown phase $PHASE"; exit 1 ;;
esac
log "PHASE_DONE $PHASE results: $(results)"
