#!/bin/bash
# T24-T2 live matrix: the thirteen debug-feedback acceptance cells on the Mac
# fixture (C1-C4 compile chain, A1-A4 asset chain, B1-B5 binding chain; plan
# loop/plans/t24-debug-feedback.md section 2, live-leg list section 3). The
# designed red states were archived pre-fix by loop/qa/t24-red.sh
# (loop/reports/t24t1_dfr{1,2,3}_red.log), so the live legs judge the green
# half and every red leg's cell carries the red-vs-green contrast in its
# evidence names.
#
# Cell map (each cell = trigger -> panel face -> locating action -> landing
# assertion, every anchor structured: jackdaw/audit, jackdaw/status, ui_tree
# text, selection):
#   C1  break one template line -> pie.play_current -> three failure mouths:
#       footer Failed (walk), jackdaw/status pie=failed, the notify_error
#       branch's error! line in the editor log.
#   C2  the Build panel surfaced with the whole rendered log: `-->
#       src/lib.rs:L:C` arrow lines and the "Build failed - " face in the
#       visible walk (visible_only=true: arrows in the walk mean the Build
#       tab is the active one, the auto-focus's own face).
#   C3  the structured strip: "N errors · first: src/lib.rs:L:C" summary,
#       one row per position with an Open button; click Open -> cursor
#       --goto file:line:col (the T1 probe table's first hit) -> landing
#       judged on the status-bar report ("opened cursor at ...") plus the
#       process on foot; Cursor is killed after the leg so windows do not
#       pile up (the T1 QA handoff note).
#   C4  a warning-only build: the footer reads Project built (never
#       Failed) and the warning arrow stays readable in the panel log.
#   A1  external mv of a referenced material -> reload -> the audit's four
#       mouths: the warn_on_load summary line, the jackdaw/audit finding
#       (four-tuple field by field), the asset.audit operator summary, and
#       the board (A2's face).
#   A2  asset.missing_list -> the Scene Problems board walks with the
#       finding's line() text and its Rebind/Locate/Show/Copy actions; the
#       three-color grading rides the remote kind=Missing (ui_tree carries
#       no color, the A14 calibre).
#   A3  Locate -> the tab already in front + select_only: jackdaw/status
#       answers scene=the document and selection[0].name=the entity.
#   A4  break the referenced GLB's bytes -> reload -> the Asset load
#       failures section with exactly one row (the (path,mtime) one-shot
#       lock); a second break (new mtime key) speaks again and lands a
#       second row.
#   B1  a scene spelling an unknown component -> the UnresolvedTypes
#       remedy line (type list + the two honest moves); reloading the same
#       document says nothing new (the unchanged-remedy lock).
#   B2  an unknown field -> the structured warn ("... on entity #RedField;
#       the scene-problems list carries the row") and the Binding problems
#       row naming entity/component/field — DF-R3's red face flipped.
#   B3  one document carrying BOTH a broken reference and an unknown
#       field -> the board shows the Broken references and Binding
#       problems sections side by side, neither swallowing the other.
#   B4  a game-side bad binding -> the focused game's log strip (newest
#       four face, the older lines provably held back) -> click expands to
#       the full buffered list (every line reachable); then the direct-run
#       face: the standalone game loads the bad-binding scene from its
#       flow and its own log carries the warn (PIE-free calibre per the
#       plan's A10/N13 bypass; the PIE half never forwards pointers).
#   B5  the crate-root re-export scene (DF-R2's exact fixture): the warn
#       now names the registered definition spelling, the remedy names
#       both honest moves (the misleading single-cause rebuild line is
#       gone), the Binding problems row renders, and the component stays
#       unapplied — said plainly, not normalized.
#
# A6 family isolation, the five disciplines, in force on every leg:
#   1. one trigger source per leg (each leg writes exactly one file);
#   2. settle >= 2s after every external write (4s here);
#   3. assertion budget per wait, timeout judges FAIL — no retry that
#      gambles on timing;
#   4. live legs and cargo gates never share a window (the gates are not
#      this script's business; the only cargo inside is the editor's own
#      build/play machinery, and the direct-run leg finds the binary the
#      PIE build already made — no fresh cargo in any live window);
#   5. disk checked before the run (prep refuses under 15Gi — the T2
#      build-heavy round raises t23's 10Gi bar).
#
# A9 self-defence: reads ride the flaky window with retries; build/play
# legs wait on jackdaw/wait or bounded budgets; no assertions inside a
# build window. A7 stays out: every panel assertion is a ui_tree text
# anchor or a structured remote read, never a hand-placed click on an
# unaddressable node. RUST_BACKTRACE is never set. The warn census rides
# mark_log/log_lines_since offset diffs (the MO8 calibre) and every hit
# is attributed phase by phase — zero unexpected warns is the target.
#
# Phases (each boots and cleans its own editor; run one per invocation,
# or `all`):
#   prep     jd new the fixture, inject jackdaw_remote (the game's BRP
#            face for B4), write the flow and the tab journal.
#   build    C1-C4 (one editor window; warm build first, then the
#            breakage, the failure cells, the Open click with its cursor
#            cleanup, the restore, the warning build).
#   assets   A1-A4 (material + reference scene, the mv, the board legs,
#            the GLB breakage and its one-shot lock).
#   bindings B1, B2, B3, B5 (the unknown-component, unknown-field,
#            both-sections and re-export legs; B4 lives in its own phase).
#   runtime  B4 (the PIE editor face + the direct-run game log face).
# Usage: bash loop/qa/t24-live.sh [phase]   phase: prep|build|assets|
#                                              bindings|runtime|all
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
FIXROOT=/Users/zhanglinbo/workspace/loop-mac/t24-debug
PROJECT="$FIXROOT/t24-live"
PORT=15703
GAME_PORT=15702
OUTDIR="${T24_OUTDIR:-$REPO/loop/t24-live}"
REPORT_TAG="${T24_REPORT_TAG:-t24t2}"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
GAME_LIB="$PROJECT/src/lib.rs"
GAMEBIN="t24-live"
MATDIR="$PROJECT/assets/materials"
T24MAT="$MATDIR/t24mat.bsn"
T24MAT_MOVED="$MATDIR/t24mat-moved.bsn"
MODELDIR="$PROJECT/assets/models"
GLB="$MODELDIR/t24model.glb"
NAME='bevy_ecs::name::Name'
TRANSFORM='bevy_transform::components::transform::Transform'
GRAPHREF_DEF='jackdaw_animation_runtime::graph::AnimationGraphRef'
mkdir -p "$OUTDIR"
PHASE="${1:-all}"
WINDOW=0
EDITOR_LOG="$OUTDIR/editor-$PHASE.log"
CONSOLE_LOG="$OUTDIR/console-$PHASE.log"
echo "=== phase $PHASE run $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t24-live.XXXXXX)"
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
  pkill -x jackdaw 2>/dev/null
  pkill -x "$GAMEBIN" 2>/dev/null
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
  # Reads ride the flaky window: retry until a parseable body comes back.
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
gbrp() {
  # A9: the game BRP answers intermittently empty in busy windows.
  local method="$1" params="${2:-}" id=$RANDOM body out attempt
  if [ -n "$params" ]; then
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params")
  else
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s"}' "$id" "$method")
  fi
  for attempt in 1 2 3; do
    out=$(curl -s -m 30 -X POST "http://127.0.0.1:$GAME_PORT/" -H 'Content-Type: application/json' -d "$body")
    if [ -n "$out" ] && ! echo "$out" | grep -q "expected value at line 1"; then
      echo "$out"; return 0
    fi
    sleep 2
  done
  echo "$out"
}
op() { # op <id> <params> — stdout the JSON-RPC response
  local id="$1" params="${2:-}"
  if [ -n "$params" ]; then brp_raw jackdaw/call_operator "{\"id\":\"$id\",\"params\":$params}"
  else brp_raw jackdaw/call_operator "{\"id\":\"$id\",\"params\":{}}"; fi
}
opres() { op "$1" "$2" 2>/dev/null | jq -r '.result.result // "error"' 2>/dev/null; }
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
port_silent() { # port_silent — whether :$PORT answers anything at all; the
                # probe is short-timeout (a dying window's listener can hold
                # connections open without ever answering, and the 60s
                # default timeout turned the guard into a seven-minute wait)
  [ -n "$(curl -s -m 3 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"jackdaw/status","params":{}}' 2>/dev/null)" ]
}
editor_boot() {
  # The port-squatter guard: two live windows on 15703 would answer each
  # other's BRP calls (the run-collision this script's own second build
  # run hit — the play rode another window's stale in-flight build). Kill
  # until the port is silent, boot, and only accept the boot when the
  # answering pid is the pid this boot spawned.
  local squatter
  for squatter in 1 2 3 4 5; do
    pkill -x jackdaw 2>/dev/null
    pkill -9 -x jackdaw 2>/dev/null
    sleep 2
    port_silent || continue
    break
  done
  if port_silent; then
    log "EDITOR_BOOT_FAIL: an editor still answers :$PORT after five kills"; exit 1
  fi
  WINDOW=$((WINDOW + 1))
  EDITOR_LOG="$OUTDIR/editor-$PHASE-w$WINDOW-$$-.log"
  : > "$EDITOR_LOG"
  export JACKDAW_OPEN_PROJECT="$PROJECT"
  export JACKDAW_PIE_PREBUILD=0
  export JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1600x1000
  cd "$REPO"
  nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$EDITOR_LOG" 2>&1 &
  local boot_pid=$!
  echo "$boot_pid" > "$OUTDIR/boot-pid.txt"
  local ok=""
  for i in $(seq 1 150); do
    sleep 2
    if brp jackdaw/status '{}' >/dev/null 2>&1 && kill -0 "$boot_pid" 2>/dev/null; then ok=1; break; fi
    kill -0 "$boot_pid" 2>/dev/null || break
  done
  [ -n "$ok" ] || { log "EDITOR_BOOT_FAIL"; exit 1; }
  # The answering pid must be this boot's own editor, not a squatter.
  local answer_pid
  answer_pid=$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.pid // empty' 2>/dev/null)
  [ "$answer_pid" = "$boot_pid" ] || { log "EDITOR_BOOT_FAIL: :$PORT answers pid=$answer_pid, wanted $boot_pid"; exit 1; }
  sleep 5
  wait_idle 900 >/dev/null; sleep 3; dismiss_dialog
  walk "$OUTDIR/walk-boot-$PHASE-w$WINDOW-$$-.json"
  if grep -qF "Recovered Work" "$OUTDIR/walk-boot-$PHASE-w$WINDOW-$$-.json" 2>/dev/null; then
    brp jackdaw/ui_click '{"text":"Discard All"}' >/dev/null 2>&1
    sleep 2; wait_idle 120 >/dev/null
  fi
  log "EDITOR_READY project=$PROJECT pid=$boot_pid"
}
open_scene() {
  op scene.open "{\"path\":\"$1\",\"reload\":true}" >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
}
walk() { brp jackdaw/ui_tree '{"kind":"node","visible_only":true,"depth":80}' > "$1" 2>/dev/null; }
walk_has() { grep -qF "$1" "$2" 2>/dev/null; } # walk_has <needle> <file>
budget() { # budget <seconds> <cmd...> — discipline 3: run a probe on a
           # budget; timeout is a FAIL verdict, not a retry.
  local secs="$1"; shift
  local deadline=$((SECONDS + secs))
  while [ $SECONDS -lt $deadline ]; do
    if "$@"; then return 0; fi
    sleep 1
  done
  return 1
}
mark_log() { # mark_log <pattern> <offset-file> — remember the current count
  local n
  n=$(grep -c "$1" "$EDITOR_LOG" 2>/dev/null)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  echo "$n" > "$2"
}
log_lines_since() { # new matching editor-log lines since the offset file
  local total saved
  total=$(grep -c "$1" "$EDITOR_LOG" 2>/dev/null)
  case "$total" in ''|*[!0-9]*) total=0 ;; esac
  saved=$(cat "$2" 2>/dev/null)
  case "$saved" in ''|*[!0-9]*) saved=0 ;; esac
  echo $((total - saved))
}
warn_scan() { # warn_scan <pattern> <log...> — the census face: archive
              # every hit with its line, the phase's attribution input
  local pattern="$1" out="$OUTDIR/warn-scan-$PHASE.txt"
  shift
  : > "$out"
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    grep -E "$pattern" "$f" >> "$out" 2>/dev/null
  done
  log "warn scan ($PHASE): $(wc -l < "$out" | tr -d ' ') hit(s) -> $out"
  cat "$out"
}
close_board() { # the Scene Problems board is up from the list legs; close it
                # and hold until the walk proves the scrim is gone
  local attempt
  for attempt in 1 2 3; do
    walk "$OUTDIR/walk-closecheck-$PHASE.json"
    grep -qF "Scene Problems" "$OUTDIR/walk-closecheck-$PHASE.json" 2>/dev/null || return 0
    brp jackdaw/ui_click '{"text":"Close","index":0}' >/dev/null 2>&1
    sleep 2
  done
  log "note: the board may still be up after three Close attempts (walk-closecheck archived)"
}
qcount() { # qcount <editor-brp> <component-path> — entities carrying the
           # component (the t23/t24-red reader forms, shape-tolerant)
  local port="$1" comp="$2"
  curl -s -m 60 -X POST "http://127.0.0.1:$port/" -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"world.query","params":{"data":{"components":["'"$comp"'"]}}}' 2>/dev/null \
    | jq -r 'if (.result|type) == "object" then ([.result|to_entries[]|select(.key != "error")]|length)
             elif (.result|type) == "array" then (.result|length)
             else 0 end' 2>/dev/null
}
audit_json() { brp jackdaw/audit '{}' 2>/dev/null | jq -c '.result // .' 2>/dev/null; }
findings_for() { # the audit's entries naming this reference
  audit_json 2>/dev/null | jq -c --arg r "$1" '[.findings[]? | select(.reference == $r)]' 2>/dev/null
}
glb_write() { # glb_write <path> <name1> <name2> ... — a valid glTF binary,
              # the T18 box craft (one material, every node wearing it)
  python3 - "$@" << 'PYT'
import json, struct, sys
out_path = sys.argv[1]
names = sys.argv[2:]
corners = [(-0.5,-0.5,-0.5),(0.5,-0.5,-0.5),(0.5,0.5,-0.5),(-0.5,0.5,0.5),
           (-0.5,-0.5,0.5),(0.5,-0.5,0.5),(0.5,0.5,0.5),(-0.5,0.5,-0.5)]
faces = [(0,1,2,3),(4,5,6,7),(0,1,5,4),(2,3,7,6),(1,2,6,5),(0,3,7,4)]
pos = [c for corner in corners for c in corner]
idx = []
for f in faces:
    a, b, c, d = f
    idx.extend((a, b, c)); idx.extend((a, c, d))
views, accessors, blob = [], [], b""
def add_view(vals, comp, vtype, count, mins=None, maxs=None):
    global blob
    while len(blob) % 4: blob += b"\x00"
    fmt = {5126: "<%df", 5123: "<%dH"}[comp]
    data = struct.pack(fmt % len(vals), *vals)
    acc = {"bufferView": len(views), "componentType": comp, "count": count, "type": vtype}
    if mins is not None: acc["min"] = mins
    if maxs is not None: acc["max"] = maxs
    views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)})
    accessors.append(acc)
    blob += data
pmin = [min(c[0] for c in corners), min(c[1] for c in corners), min(c[2] for c in corners)]
pmax = [max(c[0] for c in corners), max(c[1] for c in corners), max(c[2] for c in corners)]
PA = len(accessors); add_view(pos, 5126, "VEC3", 8, pmin, pmax)
IA = len(accessors); add_view(idx, 5123, "SCALAR", len(idx))
materials = [{"name": "Rock", "pbrMetallicRoughness": {"baseColorFactor": [0.72, 0.72, 0.72, 1.0]}}]
meshes, nodes = [], []
for i, nm in enumerate(names):
    meshes.append({"primitives": [{"attributes": {"POSITION": PA}, "indices": IA,
                                   "mode": 4, "material": 0}]})
    nodes.append({"name": nm, "mesh": i, "translation": [0.0, 1.4 * i, 0.0]})
gltf = {
    "asset": {"version": "2.0", "generator": "jackdaw loop t24 glb_write.py"},
    "scene": 0,
    "scenes": [{"nodes": list(range(len(names)))}],
    "nodes": nodes,
    "meshes": meshes,
    "materials": materials,
    "accessors": accessors,
    "bufferViews": views,
    "buffers": [{"byteLength": len(blob)}],
}
json_chunk = json.dumps(gltf, separators=(",", ":")).encode()
while len(json_chunk) % 4: json_chunk += b" "
total = 12 + 8 + len(json_chunk) + 8 + len(blob)
with open(out_path, "wb") as out:
    out.write(struct.pack("<III", 0x46546C67, 2, total))
    out.write(struct.pack("<II", len(json_chunk), 0x4E4F534A))
    out.write(json_chunk)
    out.write(struct.pack("<II", len(blob), 0x004E4942))
    out.write(blob)
print(f"wrote {out_path}: {total} bytes, {len(names)} node(s)")
PYT
}
break_file() { # break_file <path> — clobber the first four bytes,
               # written as an atomic replace so the watcher only ever
               # reads whole states (a mid-write read would take a
               # second (path,mtime) key and double the row)
  python3 - "$1" << 'PYT'
import os, sys
path = sys.argv[1]
data = bytearray(open(path, "rb").read())
data[0:4] = b"\xde\xad\xbe\xef"
tmp = path + ".breaking"
open(tmp, "wb").write(bytes(data))
os.replace(tmp, path)
print(f"broke {path} (atomic replace)")
PYT
}
first_arrow() { # first_arrow <walk-json> — the first `--> path:line:col`
                # the walk carries, empty when none
  python3 - "$1" << 'PYT'
import re, sys
try:
    text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
except OSError:
    print(""); raise SystemExit
hits = re.findall(r"-->\s*(\S+:\d+:\d+)", text)
print(hits[0] if hits else "")
PYT
}
walk_text_nodes() { # walk_text_nodes <walk-json> — every Text a node
                    # carries, one per line (the panel-face counter)
  python3 - "$1" << 'PYT'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    raise SystemExit
data = data.get("result", data)
def walk(node, out):
    label = node.get("text")
    if isinstance(label, str) and label:
        out.append(label)
    for child in node.get("children", []) or []:
        walk(child, out)
texts = []
for root in data.get("nodes", []):
    walk(root, texts)
for t in texts:
    print(t)
PYT
}
button_bits_in_row() { # button_bits_in_row <walk-json> <row-text-prefix>
                       # <button-label> — the entity the QA handoff said to
                       # hit: the row text's parent node, then the child
                       # whose subtree carries the label. Log lines that
                       # merely start with the prefix have no buttoned
                       # sibling and pass by.
  python3 - "$1" "$2" "$3" << 'PYT'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    raise SystemExit
data = data.get("result", data)
prefix, label = sys.argv[2], sys.argv[3]
parent = {}
def walk(node):
    for child in node.get("children", []) or []:
        parent[child.get("entity")] = node
        walk(child)
for root in data.get("nodes", []):
    walk(root)
def subtree_texts(node, acc):
    t = node.get("text")
    if isinstance(t, str):
        acc.append(t)
    for child in node.get("children", []) or []:
        subtree_texts(child, acc)
    return acc
def nodes(node):
    yield node
    for child in node.get("children", []) or []:
        yield from nodes(child)
hits = []
for root in data.get("nodes", []):
    for node in nodes(root):
        t = node.get("text")
        if isinstance(t, str) and t.startswith(prefix):
            hits.append(node)
for node in hits:
    holder = parent.get(node.get("entity"), node)
    for child in holder.get("children", []) or []:
        if label in subtree_texts(child, []):
            print(child.get("entity"))
            raise SystemExit
PYT
}
parent_bits_of_text() { # parent_bits_of_text <walk-json> <text-prefix> —
                        # the parent of the first node whose text starts
                        # with the prefix (the strip behind a log row)
  python3 - "$1" "$2" << 'PYT'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    raise SystemExit
data = data.get("result", data)
prefix = sys.argv[2]
parent = {}
def walk(node):
    for child in node.get("children", []) or []:
        parent[child.get("entity")] = node
        walk(child)
for root in data.get("nodes", []):
    walk(root)
def find(node):
    t = node.get("text")
    if isinstance(t, str) and t.startswith(prefix):
        return node
    for child in node.get("children", []) or []:
        hit = find(child)
        if hit is not None:
            return hit
    return None
for root in data.get("nodes", []):
    hit = find(root)
    if hit is not None:
        holder = parent.get(hit.get("entity"), hit)
        print(holder.get("entity"))
        raise SystemExit
PYT
}

pin_tabs() { # pin_tabs — the boot-time tab restore loads whatever the last
             # exit left open, and those loads fire their own warns before
             # the phase's baseline; pin the journal to the starter scene
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
print("journal pinned to assets/scene.bsn")
PYT
}

# ---- phase: prep -------------------------------------------------------------
prep() {
  pkill -x jackdaw 2>/dev/null; pkill -x "$GAMEBIN" 2>/dev/null; sleep 1
  local free
  free=$(df -g / | awk 'NR==2 {print $4}')
  [ "$free" -ge 15 ] || { log "PREP_FAIL only ${free}Gi free; clean the disk first (the T2 bar is 15Gi)"; exit 1; }
  log "disk: ${free}Gi free"
  rm -rf "$PROJECT"; mkdir -p "$FIXROOT" "$OUTDIR"
  (cd "$REPO" && DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jd new t24-live --path "$FIXROOT" --no-git) > "$OUTDIR/jd-new.log" 2>&1
  [ -d "$PROJECT" ] || { log "PREP_FAIL no project ($(tail -2 "$OUTDIR/jd-new.log"))"; exit 1; }
  # The game-side BRP injection (t13t3/t15 practice): the remote dep after
  # the runtime dep, the remote plugin after the game plugin. The PIE game
  # then answers BRP on 15702 and B4's runtime apply_bsn has a mouth.
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
  mkdir -p "$MATDIR" "$MODELDIR"
  # A stale persisted tab journal would restore yesterday's documents; every
  # phase starts on the canonical starter scene.
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

# ---- phase: build (C1-C4) ----------------------------------------------------
build() {
  local arrow
  # Self-heal: an earlier run that died before its own restore leaves the
  # template broken, and the warm build would fail on a leftover E0308
  # (this phase's third run opened on exactly such a leftover).
  if [ -f "$OUTDIR/lib.rs.pristine" ]; then
    cp "$OUTDIR/lib.rs.pristine" "$GAME_LIB"
    log "restored the template from the previous run's pristine copy before the warm build"
  fi
  editor_boot
  log "--- warm build (fills .jackdaw/target so the play legs stay short) ---"
  op project.build >/dev/null 2>&1
  # The editor's own busy face is the finish line (the schema.json file
  # check races — a leftover schema from an earlier window answers before
  # cargo is done, and the play then rides the in-flight build's stale
  # binary, the exact failure this phase's second run hit).
  local warm=""
  for i in $(seq 1 120); do
    sleep 10
    if brp jackdaw/wait '{"until":"idle"}' 2>/dev/null | jq -e '.result.idle == true' >/dev/null 2>&1; then warm=1; break; fi
  done
  [ -n "$warm" ] && log "WARM_BUILD_OK" || log "WARM_BUILD_UNVERIFIED (continuing; the failure legs judge the latch)"
  sleep 3; wait_idle 120 >/dev/null
  walk "$OUTDIR/warm-walk.json"
  log "--- C1/C2/C3: break one template line, fail the Play build ---"
  cp "$GAME_LIB" "$OUTDIR/lib.rs.pristine"
  wait_idle 300 >/dev/null
  printf '\nfn t24_live_breakage() {\n    let x: i32 = "five";\n}\n' >> "$GAME_LIB"
  sleep 2; wait_idle 60 >/dev/null
  mark_log "PIE: game build of" "$OUTDIR/c1.offset"
  op pie.play_current >/dev/null 2>&1
  local failed=""
  for i in $(seq 1 90); do
    sleep 5
    if grep -q "PIE: game build of .* failed" "$EDITOR_LOG" 2>/dev/null; then failed=1; break; fi
  done
  [ -n "$failed" ] || { log "C1: the play build never failed (budget out)"; leg C1_BUILD_FAILED false; return; }
  sleep 4; dismiss_dialog; sleep 2
  walk "$OUTDIR/walk-c1.json"
  # C1's three mouths: the footer, the remote pie face, the log's error line.
  walk_has "Build failed - " "$OUTDIR/walk-c1.json" \
    && leg C1_FOOTER_FAILED true || leg C1_FOOTER_FAILED false
  local pie_state
  pie_state=$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.pie // empty' 2>/dev/null)
  log "C1: jackdaw/status pie=$pie_state (want failed)"
  [ "$pie_state" = "failed" ] && leg C1_PIE_STATUS_FAILED true || leg C1_PIE_STATUS_FAILED false
  local err_mouth; err_mouth=$(log_lines_since "PIE: game build of" "$OUTDIR/c1.offset")
  log "C1: 'PIE: game build of' error lines in the log: $err_mouth (want >=1)"
  [ "${err_mouth:-0}" -ge 1 ] && leg C1_ERROR_MOUTH_LOG true || leg C1_ERROR_MOUTH_LOG false
  # C2: the whole rendered log on the surfaced panel.
  arrow=$(first_arrow "$OUTDIR/walk-c1.json")
  log "C2: first arrow in the visible walk: ${arrow:-none}"
  [ -n "$arrow" ] && leg C2_PANEL_ARROWS true || leg C2_PANEL_ARROWS false
  walk_has "Build failed - " "$OUTDIR/walk-c1.json" \
    && leg C2_PANEL_FAILED_FACE true || leg C2_PANEL_FAILED_FACE false
  # visible_only=true: arrows riding the walk mean the Build tab is the
  # active tab in its dock leaf — the auto-focus's own face.
  [ -n "$arrow" ] && leg C2_PANEL_AUTOFOCUSED true || leg C2_PANEL_AUTOFOCUSED false
  # C3: the structured strip, then the click.
  walk_has "errors · first: $arrow" "$OUTDIR/walk-c1.json" \
    && leg C3_SUMMARY_PINNED true || leg C3_SUMMARY_PINNED false
  local open_bits
  open_bits=$(button_bits_in_row "$OUTDIR/walk-c1.json" "--> $arrow" "Open" | head -1)
  log "C3: Open button entity bits: ${open_bits:-none}"
  [ -n "$open_bits" ] && leg C3_ROWS_WITH_OPEN true || leg C3_ROWS_WITH_OPEN false
  local cursor_before
  cursor_before=$(pgrep -x Cursor | wc -l | tr -d ' ')
  if [ -n "$open_bits" ]; then
    brp jackdaw/ui_click "{\"entity\":$open_bits}" > "$OUTDIR/c3-click-response.json" 2>/dev/null
    if jq -e '.result.clicked == true' "$OUTDIR/c3-click-response.json" >/dev/null 2>&1; then
      leg C3_OPEN_CLICK_LANDED true
    else
      log "C3: the click response: $(cat "$OUTDIR/c3-click-response.json")"
      leg C3_OPEN_CLICK_LANDED false
    fi
    # The landing: the status bar says what became of the click, and the
    # probe table's first editor is on foot (cursor --goto per the T1 probe).
    landing_probe() {
      walk "$OUTDIR/walk-c3-landing.json"
      grep -qF "opened cursor at $arrow" "$OUTDIR/walk-c3-landing.json" 2>/dev/null
    }
    budget 15 landing_probe && leg C3_LANDING_STATUS_TEXT true || leg C3_LANDING_STATUS_TEXT false
    budget 20 [ "$(pgrep -x Cursor | wc -l | tr -d ' ')" -gt "$cursor_before" ] && leg C3_CURSOR_LAUNCHED true || leg C3_CURSOR_LAUNCHED false
    log "C3: cursor processes before=${cursor_before} after=$(pgrep -x Cursor | wc -l | tr -d ' '); landing walk archived"
  else
    log "C3: no Open button to click; the click legs judge false"
    leg C3_OPEN_CLICK_LANDED false
    leg C3_LANDING_STATUS_TEXT false
    leg C3_CURSOR_LAUNCHED false
  fi
  # The QA handoff: the leg's own cursor windows are cleaned so nothing
  # piles up across legs.
  pkill -x Cursor 2>/dev/null; sleep 2
  cursor_after=$(pgrep -x Cursor | wc -l | tr -d ' ')
  [ "$cursor_after" = "0" ] && leg C3_CURSOR_CLEANED true || leg C3_CURSOR_CLEANED false
  log "--- C4: a warning-only build stays Ready and readable ---"
  if [ -f "$OUTDIR/lib.rs.pristine" ]; then cp "$OUTDIR/lib.rs.pristine" "$GAME_LIB"; fi
  wait_idle 300 >/dev/null
  printf '\nfn t24_live_warning() {\n    let unused_variable: i32 = 5;\n}\n' >> "$GAME_LIB"
  sleep 2; wait_idle 60 >/dev/null
  op project.build >/dev/null 2>&1
  local built=""
  for i in $(seq 1 60); do
    sleep 5
    if brp jackdaw/wait '{"until":"idle"}' 2>/dev/null | jq -e '.result.idle == true' >/dev/null 2>&1; then built=1; break; fi
  done
  [ -n "$built" ] || log "C4: the warning build ran past its budget (the walk judges what rendered)"
  sleep 3
  walk "$OUTDIR/walk-c4.json"
  if grep -qF "Build failed" "$OUTDIR/walk-c4.json" 2>/dev/null; then
    leg C4_STATE_NOT_FAILED false
  else
    walk_has "Project built" "$OUTDIR/walk-c4.json" \
      && leg C4_STATE_NOT_FAILED true || leg C4_STATE_NOT_FAILED false
  fi
  walk_has "warning: unused variable" "$OUTDIR/walk-c4.json" \
    && leg C4_WARNING_IN_PANEL true || leg C4_WARNING_IN_PANEL false
  local warn_arrow; warn_arrow=$(first_arrow "$OUTDIR/walk-c4.json")
  log "C4: warning arrow in the panel log: ${warn_arrow:-none}"
  [ -n "$warn_arrow" ] || leg C4_WARNING_IN_PANEL false
  if [ -f "$OUTDIR/lib.rs.pristine" ]; then cp "$OUTDIR/lib.rs.pristine" "$GAME_LIB"; fi
  warn_scan 'build failed|PIE: game build|error\[|warning:|Build failed' "$EDITOR_LOG"
  log "BUILD done: $(results)"
}

# ---- phase: assets (A1-A4) ---------------------------------------------------
assets() {
  pin_tabs
  editor_boot
  log "--- fixture: the referenced material and the reference scene ---"
  op asset.new '{"type":"Layered Surface","name":"t24mat","path":"assets/materials"}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  [ -f "$T24MAT" ] || { log "A1: the material file never landed"; leg A1_WARN_ON_LOAD false; leg A1_AUDIT_FOUR_TUPLE false; leg A1_OPERATOR_MOUTH false; leg A2_BOARD_ROWS false; leg A2_ROW_TEXT_MATCHES false; leg A2_ROW_ACTIONS false; leg A3_LOCATE_SELECTS false; leg A3_TAB_FORWARD false; return; }
  cat > "$PROJECT/assets/t24a.bsn" << 'EOF'
// T24 A-chain fixture: an override layer referencing a real material.
#AuditEntity
bevy_transform::components::transform::Transform
jackdaw_scene_types::types::MaterialOverrides {
    materials: map[
        ("Rock", "materials/t24mat.bsn"),
    ],
}
EOF
  # The baseline rides the audit alone: opening the scene here would make
  # the later reload an in-place reread, and the reread path never walks
  # the load-time summary warn (the fresh-open path does).
  local base_count; base_count=$(findings_for "materials/t24mat.bsn" | jq '. | length' 2>/dev/null)
  log "A1: baseline audit findings for the reference: ${base_count:-ERR} (want 0)"
  log "--- A1: external mv, first open, the audit's mouths ---"
  mark_log "references name files" "$OUTDIR/a1.offset"
  mark_log "asset load failed" "$OUTDIR/a1-load.offset"
  mv "$T24MAT" "$T24MAT_MOVED"
  sleep 4   # discipline 2
  # The load-time audit reads the index; hold the open until the index
  # has processed the mv (the audit mouth is the witness).
  budget 60 [ "$(findings_for "materials/t24mat.bsn" | jq '. | length' 2>/dev/null)" = "1" ] \
    || log "A1: note - the audit still answers nothing for the moved reference (index lag)"
  open_scene "assets/t24a.bsn"
  sleep 3
  local w1; w1=$(log_lines_since "references name files" "$OUTDIR/a1.offset")
  log "A1: 'references name files' lines after the mv+reload: $w1 (want >=1)"
  grep "references name files" "$EDITOR_LOG" | tail -1 > "$OUTDIR/a1-warn-line.txt"
  grep -q "t24a.bsn" "$OUTDIR/a1-warn-line.txt" || log "A1: note - the summary line did not name the document"
  [ "${w1:-0}" -ge 1 ] && leg A1_WARN_ON_LOAD true || leg A1_WARN_ON_LOAD false
  local find; find=$(findings_for "materials/t24mat.bsn")
  echo "$find" > "$OUTDIR/a1-finding.json"
  log "A1: audit findings for materials/t24mat.bsn: $find"
  echo "$find" | jq -e '. | length == 1' >/dev/null 2>&1 \
    && echo "$find" | jq -e '.[0].document | endswith("t24a.bsn")' >/dev/null 2>&1 \
    && echo "$find" | jq -e '.[0].entity == "AuditEntity" and .[0].component == "MaterialOverrides" and .[0].field == "materials" and .[0].kind == "Missing"' >/dev/null 2>&1 \
    && leg A1_AUDIT_FOUR_TUPLE true || leg A1_AUDIT_FOUR_TUPLE false
  op asset.audit > "$OUTDIR/a1-audit-operator.json" 2>/dev/null
  if grep -qF "1 broken references" "$OUTDIR/a1-audit-operator.json" 2>/dev/null; then
    leg A1_OPERATOR_MOUTH true
  else
    log "A1: the operator response: $(cat "$OUTDIR/a1-audit-operator.json")"
    leg A1_OPERATOR_MOUTH false
  fi
  log "--- A2: the board walks with the finding's line and actions ---"
  op asset.missing_list >/dev/null 2>&1
  sleep 2
  walk "$OUTDIR/walk-a2.json"
  walk_has "Scene Problems" "$OUTDIR/walk-a2.json" && leg A2_BOARD_ROWS true || leg A2_BOARD_ROWS false
  local want_line
  want_line=$(echo "$find" | jq -r '"\(.[0].document) · \(.[0].entity) · \(.[0].component).\(.[0].field) → \(.[0].reference) (\(.[0].kind))"' 2>/dev/null)
  log "A2: expected row text: $want_line"
  walk_has "$want_line" "$OUTDIR/walk-a2.json" \
    && leg A2_ROW_TEXT_MATCHES true || leg A2_ROW_TEXT_MATCHES false
  local buttons_ok=true
  for b in Rebind Locate Show Copy; do
    walk_has "\"$b\"" "$OUTDIR/walk-a2.json" || { log "A2: the $b action is not in the walk"; buttons_ok=false; }
  done
  leg A2_ROW_ACTIONS "$buttons_ok"
  close_board
  log "--- A3: Locate brings the tab forward and selects the entity ---"
  op asset.missing_list >/dev/null 2>&1
  sleep 2
  walk "$OUTDIR/walk-a3.json"
  local locate_bits
  locate_bits=$(button_bits_in_row "$OUTDIR/walk-a3.json" "$want_line" "Locate" | head -1)
  log "A3: Locate button entity bits: ${locate_bits:-none}"
  if [ -n "$locate_bits" ]; then
    brp jackdaw/selection.set '{"clear":true}' >/dev/null 2>&1
    sleep 1
    local sel_before
    sel_before=$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.selection | length' 2>/dev/null)
    log "A3: selection cleared before the click (length now ${sel_before:-ERR})"
    [ "${sel_before:-1}" = "0" ] || leg A3_LOCATE_SELECTS false
    brp jackdaw/ui_click "{\"entity\":$locate_bits}" > "$OUTDIR/a3-click-response.json" 2>/dev/null
    sleep 2; wait_idle 120 >/dev/null
  else
    log "A3: no Locate button found; the cell judges false"
  fi
  local sel_name scene_path
  sel_name=$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.selection[0].name // empty' 2>/dev/null)
  scene_path=$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.scene // empty' 2>/dev/null)
  log "A3: after Locate selection=$sel_name scene=$scene_path"
  [ "$sel_name" = "AuditEntity" ] && leg A3_LOCATE_SELECTS true || leg A3_LOCATE_SELECTS false
  case "$scene_path" in
    *t24a.bsn) leg A3_TAB_FORWARD true ;;
    *) leg A3_TAB_FORWARD false ;;
  esac
  close_board
  log "--- A4: the load-failure section, one row per (path,mtime) key ---"
  glb_write "$GLB" ModelA ModelB
  cp "$GLB" "$OUTDIR/t24model.glb.pristine"
  cat > "$PROJECT/assets/t24b.bsn" << 'EOF'
// T24 A4 fixture: a document whose model reference loads for real.
#ModelEntity
bevy_transform::components::transform::Transform
jackdaw_scene_types::types::GltfSource {
    path: "models/t24model.glb",
    scene_index: 0,
}
EOF
  open_scene "assets/t24b.bsn"
  sleep 4   # the model spawns behind the open-load storm
  mark_log "asset load failed" "$OUTDIR/a4.offset"
  break_file "$GLB"
  sleep 4
  open_scene "assets/t24b.bsn"
  sleep 3
  local f1; f1=$(log_lines_since "asset load failed" "$OUTDIR/a4.offset")
  log "A4: 'asset load failed' lines after the break+reload: $f1 (want >=1)"
  grep "asset load failed" "$EDITOR_LOG" | tail -1 > "$OUTDIR/a4-warn-line.txt"
  [ "${f1:-0}" -ge 1 ] && leg A4_FAILURE_ROW_ONE_MOUTH true || leg A4_FAILURE_ROW_ONE_MOUTH false
  sleep 5   # the watcher's own reload attempt lands beside the open's
  op asset.missing_list >/dev/null 2>&1
  sleep 3
  walk "$OUTDIR/walk-a4.json"
  local rows1
  rows1=$(grep -o '[0-9][0-9]* load failure' "$OUTDIR/walk-a4.json" 2>/dev/null | tail -1 | cut -d' ' -f1)
  log "A4: the board's summary counts $rows1 load failure(s) (want 1)"
  walk_has "Asset load failures" "$OUTDIR/walk-a4.json" || leg A4_FAILURE_ROW_ONE_MOUTH false
  [ "${rows1:-0}" = "1" ] && leg A4_FAILURE_ROW_ONE true || leg A4_FAILURE_ROW_ONE false
  close_board
  # One-shot lock: the same broken file at the same mtime fails again
  # (the reload asks for it) and says nothing new.
  open_scene "assets/scene.bsn"
  sleep 2
  mark_log "asset load failed" "$OUTDIR/a4b.offset"
  open_scene "assets/t24b.bsn"
  sleep 3
  local f2; f2=$(log_lines_since "asset load failed" "$OUTDIR/a4b.offset")
  log "A4: new 'asset load failed' lines on the same-key reload: $f2 (want 0)"
  [ "${f2:-0}" = "0" ] && leg A4_LOCK_QUIET true || leg A4_LOCK_QUIET false
  # A new key (the file rewritten again) speaks again and lands a row.
  break_file "$GLB"
  sleep 4
  open_scene "assets/t24b.bsn"
  sleep 3
  local f3; f3=$(log_lines_since "asset load failed" "$OUTDIR/a4b.offset")
  log "A4: new lines after the re-break (new mtime key): $f3 (want >=1)"
  [ "${f3:-0}" -ge 1 ] && leg A4_NEW_KEY_SPEAKS true || leg A4_NEW_KEY_SPEAKS false
  sleep 5   # the watcher's own reload attempt lands beside the open's
  op asset.missing_list >/dev/null 2>&1
  sleep 3
  walk "$OUTDIR/walk-a4-again.json"
  local rows2
  rows2=$(grep -o '[0-9][0-9]* load failure' "$OUTDIR/walk-a4-again.json" 2>/dev/null | tail -1 | cut -d' ' -f1)
  log "A4: the board's summary counts $rows2 load failure(s) after the re-break (want 2)"
  [ "${rows2:-0}" = "2" ] && leg A4_NEW_KEY_ROW_LANDED true || leg A4_NEW_KEY_ROW_LANDED false
  close_board
  # The heal lands as an atomic replace so the watcher never reads a
  # partial file (the race that fired a third failure in this phase's
  # first run).
  cp "$GLB" "$OUTDIR/t24model.glb.heal-tmp" 2>/dev/null || cp "$OUTDIR/t24model.glb.pristine" "$OUTDIR/t24model.glb.heal-tmp"
  cp "$OUTDIR/t24model.glb.pristine" "$OUTDIR/t24model.glb.heal-tmp"
  mv -f "$OUTDIR/t24model.glb.heal-tmp" "$GLB" 2>/dev/null
  warn_scan 'asset load failed|references name files|cannot apply|unknown field|UnresolvedTypes|in neither|no longer holds|failed to load' "$EDITOR_LOG"
  log "ASSETS done: $(results)"
}

# ---- phase: bindings (B1, B2, B3, B5) ----------------------------------------
bindings() {
  pin_tabs
  editor_boot
  log "--- B1: an unknown component, the remedy line once ---"
  cat > "$PROJECT/assets/t24b1.bsn" << 'EOF'
// T24 B1 fixture: a type path no registration and no schema answer.
#Ghost
some_game::GhostComponent
bevy_transform::components::transform::Transform
EOF
  mark_log "in neither" "$OUTDIR/b1.offset"
  open_scene "assets/t24b1.bsn"
  sleep 3
  local r1; r1=$(log_lines_since "in neither" "$OUTDIR/b1.offset")
  log "B1: remedy lines after the first load: $r1 (want >=1)"
  grep "in neither" "$EDITOR_LOG" | tail -1 > "$OUTDIR/b1-remedy-line.txt"
  grep -q "some_game::GhostComponent" "$OUTDIR/b1-remedy-line.txt" || log "B1: note - the remedy line does not list the type"
  grep -q "Rebuild the project if the type is new to it" "$OUTDIR/b1-remedy-line.txt" || log "B1: note - the remedy's rebuild move is missing"
  [ "${r1:-0}" -ge 1 ] && leg B1_REMEDY_ONCE true || leg B1_REMEDY_ONCE false
  mark_log "in neither" "$OUTDIR/b1b.offset"
  open_scene "assets/t24b1.bsn"
  sleep 3
  local r2; r2=$(log_lines_since "in neither" "$OUTDIR/b1b.offset")
  log "B1: remedy lines after the same-document reload: $r2 (want 0)"
  [ "${r2:-0}" = "0" ] && leg B1_RELOAD_QUIET true || leg B1_RELOAD_QUIET false
  log "--- B2: an unknown field, the structured row (DF-R3 flipped) ---"
  cat > "$PROJECT/assets/t24b2.bsn" << 'EOF'
// T24 B2 fixture: a registered component carrying a field it does not declare.
#RedField
bevy_transform::components::transform::Transform {
    translation: glam::Vec3 { x: 1.0, y: 2.0, z: 3.0 },
    nonexistent_field: 5.0,
}
EOF
  mark_log "unknown field" "$OUTDIR/b2.offset"
  open_scene "assets/t24b2.bsn"
  sleep 3
  local u1; u1=$(log_lines_since "unknown field" "$OUTDIR/b2.offset")
  grep "unknown field" "$EDITOR_LOG" | tail -1 > "$OUTDIR/b2-warn-line.txt"
  log "B2: 'unknown field' lines after the load: $u1; line: $(cat "$OUTDIR/b2-warn-line.txt")"
  grep -q "on entity #RedField" "$OUTDIR/b2-warn-line.txt" || leg B2_STRUCTURED_ROW false
  grep -q "the scene-problems list carries the row" "$OUTDIR/b2-warn-line.txt" || leg B2_STRUCTURED_ROW false
  [ "${u1:-0}" -ge 1 ] && leg B2_STRUCTURED_ROW true || leg B2_STRUCTURED_ROW false
  op asset.missing_list >/dev/null 2>&1
  sleep 2
  walk "$OUTDIR/walk-b2.json"
  walk_has "Binding problems" "$OUTDIR/walk-b2.json" && leg B2_PANEL_ROW_GREEN true || leg B2_PANEL_ROW_GREEN false
  walk_has "RedField · $TRANSFORM.nonexistent_field (unknown field)" "$OUTDIR/walk-b2.json" \
    && leg B2_PANEL_ROW_GREEN true || leg B2_PANEL_ROW_GREEN false
  log "B2: green side vs DF-R3 (loop/reports/t24t1_dfr3_red.log: the field name was absent from the panel) archived in walk-b2.json"
  close_board
  log "--- B3: both sections on one board ---"
  cat > "$PROJECT/assets/t24b3.bsn" << 'EOF'
// T24 B3 fixture: one entity carrying a broken reference AND an unknown field.
#DualEntity
bevy_transform::components::transform::Transform {
    nonexistent_field: 5.0,
}
jackdaw_scene_types::types::MaterialOverrides {
    materials: map[
        ("Rock", "materials/gone-b3.bsn"),
    ],
}
EOF
  open_scene "assets/t24b3.bsn"
  sleep 3
  op asset.missing_list >/dev/null 2>&1
  sleep 2
  walk "$OUTDIR/walk-b3.json"
  local b3=true
  walk_has "Broken references" "$OUTDIR/walk-b3.json" || { log "B3: the Broken references header is missing"; b3=false; }
  walk_has "Binding problems" "$OUTDIR/walk-b3.json" || { log "B3: the Binding problems header is missing"; b3=false; }
  walk_has "t24b3.bsn · DualEntity · MaterialOverrides.materials → materials/gone-b3.bsn (Missing)" "$OUTDIR/walk-b3.json" \
    || { log "B3: the reference row is missing"; b3=false; }
  walk_has "DualEntity · $TRANSFORM.nonexistent_field (unknown field)" "$OUTDIR/walk-b3.json" \
    || { log "B3: the binding row is missing"; b3=false; }
  # Scoped to this cell's document: earlier fixtures' findings (t24a's
  # moved material, an earlier phase's leftovers) legitimately persist —
  # the audit walks every document the project holds.
  local b3audit; b3audit=$(audit_json 2>/dev/null | jq '[.findings[]? | select(.document | endswith("t24b3.bsn"))] | length' 2>/dev/null)
  log "B3: audit findings scoped to t24b3.bsn: ${b3audit:-ERR} (want 1)"
  [ "${b3audit:-0}" = "1" ] || b3=false
  leg B3_BOTH_SECTIONS "$b3"
  close_board
  log "--- B5: the re-export spelling (DF-R2 flipped) ---"
  cat > "$PROJECT/assets/t24b5.bsn" << 'EOF'
// T24 B5 fixture: the graph-family component spelled by its crate-root
// re-export instead of its definition module path (the DF-R2 shape).
#RedEntity
bevy_transform::components::transform::Transform
jackdaw_animation_runtime::AnimationGraphRef {
    path: "graphs/move.animgraph",
    skeleton_root: "Root",
}
EOF
  mark_log "that spelling is not registered" "$OUTDIR/b5.offset"
  mark_log "rebuild the project so the editor picks up its types" "$OUTDIR/b5-old.offset"
  open_scene "assets/t24b5.bsn"
  sleep 3
  local g1 old1
  g1=$(log_lines_since "that spelling is not registered" "$OUTDIR/b5.offset")
  old1=$(log_lines_since "rebuild the project so the editor picks up its types" "$OUTDIR/b5-old.offset")
  grep "that spelling is not registered" "$EDITOR_LOG" | tail -1 > "$OUTDIR/b5-warn-line.txt"
  log "B5: guided warns=$g1 misleading-remedy lines=$old1; line: $(cat "$OUTDIR/b5-warn-line.txt")"
  grep -q "the project registers '$GRAPHREF_DEF'" "$OUTDIR/b5-warn-line.txt" || leg B5_GUIDED_WARN false
  grep -q "A crate-root re-export is not a registered spelling; write the definition module path" "$OUTDIR/b5-warn-line.txt" || leg B5_GUIDED_WARN false
  [ "${g1:-0}" -ge 1 ] && leg B5_GUIDED_WARN true || leg B5_GUIDED_WARN false
  [ "${old1:-0}" = "0" ] && leg B5_REMEDY_HONEST true || leg B5_REMEDY_HONEST false
  grep -q "rewrite it to the definition module path the editor registers" "$EDITOR_LOG" \
    && leg B5_REMEDY_HONEST true || { log "B5: the honest rewrite move is not in the log"; leg B5_REMEDY_HONEST false; }
  op asset.missing_list >/dev/null 2>&1
  sleep 2
  walk "$OUTDIR/walk-b5.json"
  walk_has "RedEntity · jackdaw_animation_runtime::AnimationGraphRef (unknown type)" "$OUTDIR/walk-b5.json" \
    && leg B5_PANEL_ROW true || leg B5_PANEL_ROW false
  close_board
  local graphs transforms
  graphs=$(qcount "$PORT" "$GRAPHREF_DEF")
  transforms=$(qcount "$PORT" "$TRANSFORM")
  log "B5: world after the load: entities_with_GraphRef(def path)=$graphs entities_with_Transform=$transforms"
  [ "${graphs:-1}" = "0" ] && [ "${transforms:-0}" -ge 1 ] \
    && leg B5_COMPONENT_UNAPPLIED true || leg B5_COMPONENT_UNAPPLIED false
  warn_scan 'cannot apply|unknown field|in neither|that spelling is not registered|rebuild the project|scene-problems' "$EDITOR_LOG"
  log "BINDINGS done: $(results)"
}

# ---- phase: runtime (B4) -----------------------------------------------------
bad_bsn_text() { # the game-side bad binding, one call per field name
  printf '#B4Entity\n%s {\n    %s: 5.0,\n}\n' "$TRANSFORM" "$1"
}
runtime() {
  pin_tabs
  editor_boot
  open_scene "assets/scene.bsn"
  op scene.save >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  log "--- B4 PIE half: the focused game's log strip ---"
  op pie.play_current >/dev/null 2>&1
  local running=""
  for i in $(seq 1 90); do
    sleep 5
    local st
    st=$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.pie // empty' 2>/dev/null)
    if [ "$st" = "running" ]; then running=1; break; fi
    if [ "$st" = "failed" ]; then log "B4: the play build failed"; break; fi
  done
  [ -n "$running" ] || { log "B4: the game never came up"; leg B4_STRIP_FOUR_FACE false; leg B4_EXPAND_FULL_LIST false; pkill -x "$GAMEBIN" 2>/dev/null; op pie.stop >/dev/null 2>&1; return; }
  log "B4: game running; waiting for the game BRP on 15702"
  budget 120 [ "$(gbrp jackdaw/app_info '{}' 2>/dev/null | jq -r '.result.app_name // empty' 2>/dev/null)" != "" ] \
    || log "B4: note - the game BRP did not answer (the strip leg continues without it)"
  sleep 6   # the instance streams, auto-focuses, the channel settles
  local i
  for i in a b c d e f; do
    gbrp jackdaw/apply_bsn "{\"source\":$(printf '%s' "$(bad_bsn_text "nonexistent_field_$i")" | jq -Rs .)}" >/dev/null 2>&1
    sleep 1.5
  done
  sleep 4   # the throttle's one-second windows drain the six lines over
  walk "$OUTDIR/walk-b4-folded.json"
  local folded_newest=true
  for i in c d e f; do
    walk_has "nonexistent_field_$i" "$OUTDIR/walk-b4-folded.json" || { log "B4: newest line $i missing from the folded strip"; folded_newest=false; }
  done
  for i in a b; do
    walk_has "nonexistent_field_$i" "$OUTDIR/walk-b4-folded.json" && { log "B4: the folded strip shows more than the newest four ($i leaked)"; folded_newest=false; }
  done
  leg B4_STRIP_FOUR_FACE "$folded_newest"
  # Expand: the strip's own click (the log row's parent node, the strip).
  local strip_bits
  strip_bits=$(parent_bits_of_text "$OUTDIR/walk-b4-folded.json" "log: unknown field 'nonexistent_field_f" | head -1)
  log "B4: strip entity bits: ${strip_bits:-none}"
  if [ -n "$strip_bits" ]; then
    brp jackdaw/ui_click "{\"entity\":$strip_bits}" > "$OUTDIR/b4-click-response.json" 2>/dev/null
    sleep 3
    walk "$OUTDIR/walk-b4-expanded.json"
    local expanded=true
    for i in a b c d e f; do
      walk_has "nonexistent_field_$i" "$OUTDIR/walk-b4-expanded.json" || { log "B4: line $i not reachable in the expanded list"; expanded=false; }
    done
    leg B4_EXPAND_FULL_LIST "$expanded"
    brp jackdaw/ui_click "{\"entity\":$strip_bits}" >/dev/null 2>&1
    sleep 2
  else
    log "B4: the strip node was not addressable; the expand leg judges false"
    leg B4_EXPAND_FULL_LIST false
  fi
  op pie.stop >/dev/null 2>&1
  pie_stopped_probe() {
    [ "$(brp jackdaw/wait '{"until":"pie_stopped"}' 2>/dev/null | jq -r '.result.pie // empty' 2>/dev/null)" = "stopped" ]
  }
  budget 240 pie_stopped_probe || log "B4: the pie session ran past its stop budget (the kill below closes it)"
  sleep 2; pkill -x "$GAMEBIN" 2>/dev/null; sleep 2
  log "--- B4 direct-run half: the standalone game's own log face ---"
  pkill -x jackdaw 2>/dev/null; sleep 2
  # The runtime's own flow-scene load drops a BSN unknown field in silence
  # (the t24bad flow leg, recorded as a DF candidate) — the standalone
  # trigger is therefore the game BRP's own apply_bsn, the same bad binding
  # the PIE half pushed, read back through the game's own log.
  cat > "$PROJECT/assets/t24bad.bsn" << 'EOF'
// T24 B4 fixture: a scene document carrying a field the component does not
// declare. Held for the record; the direct-run trigger rides apply_bsn.
#B4Direct
bevy_transform::components::transform::Transform {
    translation: glam::Vec3 { x: 0.0, y: 0.0, z: 0.0 },
    nonexistent_field: 5.0,
}
EOF
  # The PIE half's game held 15702 until moments ago; a fresh bind onto a
  # just-closed listener port fails outright (no SO_REUSEADDR on the BRP's
  # listener), and the game then runs without its remote face. Hold until
  # the port genuinely refuses connections before the launch.
  local port_wait=""
  for port_wait in $(seq 1 30); do
    nc -z -G 2 127.0.0.1 $GAME_PORT 2>/dev/null || break
    sleep 2
  done
  nc -z -G 2 127.0.0.1 $GAME_PORT 2>/dev/null && { log "B4: :$GAME_PORT still held; the direct-run leg judges false"; leg B4_DIRECT_LOG_FACE false; return; }
  sleep 3
  local bin
  bin=$(ls -t "$PROJECT/.jackdaw/target/"*/"$GAMEBIN" 2>/dev/null | head -1)
  [ -n "$bin" ] || { log "B4: no PIE-built binary found; cargo build as its own window (the editor is already down)"; (cd "$PROJECT" && cargo build > "$OUTDIR/b4-cargo.log" 2>&1) || true; bin=$(ls "$PROJECT/target/debug/$GAMEBIN" 2>/dev/null | head -1); }
  [ -n "$bin" ] || { log "B4: no game binary anywhere; the direct-run leg judges false"; leg B4_DIRECT_LOG_FACE false; return; }
  # The runtime locates the project beside the binary (the staged
  # convention), so the copy runs at the project root, next to assets/.
  cp "$bin" "$PROJECT/$GAMEBIN"
  log "B4: direct run of $PROJECT/$GAMEBIN (copied beside assets/)"
  (cd "$PROJECT" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" "./$GAMEBIN" > "$OUTDIR/b4-game-direct.log" 2>&1 &)
  game_up_probe() { [ "$(gbrp jackdaw/app_info '{}' 2>/dev/null | jq -r '.result.app_name // empty' 2>/dev/null)" != "" ]; }
  if ! budget 90 game_up_probe; then
    # One relaunch on a fully settled port: the first window after a PIE
    # teardown has twice come up without its remote face, and the same
    # binary answers instantly on a clean launch.
    log "B4: no BRP answer in 90s; relaunching once on the settled port"
    pkill -x "$GAMEBIN" 2>/dev/null; sleep 3; pkill -9 -x "$GAMEBIN" 2>/dev/null; sleep 2
    local pw
    for pw in $(seq 1 15); do nc -z -G 2 127.0.0.1 $GAME_PORT 2>/dev/null || break; sleep 2; done
    (cd "$PROJECT" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" "./$GAMEBIN" >> "$OUTDIR/b4-game-direct.log" 2>&1 &)
    budget 180 game_up_probe || { log "B4: the standalone game never answered its BRP"; leg B4_DIRECT_LOG_FACE false; pkill -x "$GAMEBIN" 2>/dev/null; return; }
  fi
  log "B4: the standalone game answers its BRP"
  sleep 4
  # The trigger: the same game-side bad binding the PIE half pushed, now
  # through the standalone game's own BRP, with the warn read off the
  # game's own log (the direct-run log face).
  gbrp jackdaw/apply_bsn "{\"source\":$(printf '%s' "$(bad_bsn_text "nonexistent_field_direct")" | jq -Rs .)}" \
    > "$OUTDIR/b4-apply-response.json" 2>/dev/null
  sleep 4   # the apply warns, the log flushes
  local hits
  hits=$(grep -c "unknown field 'nonexistent_field_direct'" "$OUTDIR/b4-game-direct.log" 2>/dev/null)
  log "B4: 'unknown field' lines in the standalone game's log: ${hits:-0} (want >=1)"
  grep "unknown field" "$OUTDIR/b4-game-direct.log" | tail -1 > "$OUTDIR/b4-direct-line.txt" 2>/dev/null
  [ "${hits:-0}" -ge 1 ] && leg B4_DIRECT_LOG_FACE true || leg B4_DIRECT_LOG_FACE false
  local gtransforms
  gtransforms=$(qcount "$GAME_PORT" "$TRANSFORM")
  log "B4: standalone world: entities_with_Transform=$gtransforms (archived; the component lands minus the field)"
  # Leave the fixture on the template's flow (the t24bad flow was this
  # leg's probe, kept on disk for the record).
  printf '{\n  "start_scene": "menu.bsn",\n  "scenes": [\n    "menu.bsn",\n    "scene.bsn",\n    "gameover.bsn"\n  ]\n}\n' \
    > "$PROJECT/assets/game.flow.json"
  pkill -x "$GAMEBIN" 2>/dev/null; sleep 2
  warn_scan "unknown field|nonexistent_field" "$EDITOR_LOG" "$OUTDIR/b4-game-direct.log"
  log "RUNTIME done: $(results)"
}

# ---- dispatcher ---------------------------------------------------------------
case "$PHASE" in
  prep) prep ;;
  build) build ;;
  assets) assets ;;
  bindings) bindings ;;
  runtime) runtime ;;
  all)
    prep
    build
    assets
    bindings
    runtime
    log "ALL done"
    ;;
  *) log "unknown phase $PHASE"; exit 2 ;;
esac
log "PHASE_DONE $PHASE results: $(results)"
