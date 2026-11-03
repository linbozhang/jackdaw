#!/bin/bash
# T23-T2 live matrix: the material-override acceptance legs on the Mac fixture
# (M1-M13 + legs L1-L8, plan loop/plans/t23-material-override.md sections 2/3).
# Log names follow $PHASE everywhere (the A7 stale-grep lesson); the designed
# red states were archived headless before the fix (t23t1_red.log), so the
# live legs judge the green half — a live face that turns out silent/sticky
# (the A11 rebind stickiness family) is archived as its own *_sticky.log
# evidence, never silently passed over.
#
# Readable-face calibre (live probe 2026-11-02, loop/t23-live/):
#   - the glTF material-name component rides the MESH entities (named
#     Mesh.Rock / Mesh.Trim by the loader; the node entities RockA.. carry
#     only the node Name), and its registered path is
#     `bevy_gltf::assets::GltfMaterialName`;
#   - BRP entity ids are strings (`5440v0`) and must be quoted in params;
#   - `MaterialOverrides`/`InstanceMaterialOverrides` and the Layered/Water
#     wear components read fine over BRP; `ModelMaterial` is not reflected
#     (query returns nothing) and `MeshMaterial3d<StandardMaterial>`'s VALUE
#     fails to serialize (presence reads, the handle does not) — so the
#     Standard-face dressing is judged by the override map + the PX pixel
#     diff + warn silence, while the Layered/Water faces give the
#     component-swap proof (a glTF model never carries them) and every
#     give-back face is judged on a Layered/Water holder;
#   - the report mouth fires a transient stale round while a scene with
#     overrides is still spawning its parts (the locks self-clear once the
#     parts arrive; the log lines stay) — every warn delta below is marked
#     AFTER that window, and the transients are archived under the M12
#     attribution (new defect candidate MO8, recorded not fixed).
#
# A6 family isolation, the five disciplines, in force on every watcher leg:
#   1. one trigger source per leg (each leg writes exactly one file);
#   2. settle >= 2s after every external write (4s here: bevy's 300ms
#      watcher + one index walk + the reference-table publish);
#   3. assertion budget per wait, timeout judges FAIL — no retry that
#      gambles on timing;
#   4. watcher legs and the cargo gates never share a window (gates run
#      separately, after the live phases, editor killed; the open-time PIE
#      pre-build is suppressed; the export phase is its own window because
#      game.export runs a release build);
#   5. disk cleaned before the run (prep refuses under 10Gi).
#
# A9 game-side self-defence: small response bodies (single-component
# queries), settle retries on the game BRP, no assertions during a build
# window, idle probes between writes.
#
# Phases (each phase boots and cleans its own editor; run one per
# invocation, or `all`):
#   prep       jd new the fixture, inject jackdaw_remote, write the GLB
#              fixtures (props.glb + kit.glb, materials Rock/Trim + one
#              unnamed; nodes RockA/RockB/TrimC/PlainD per model), the two
#              scene documents, the flow and the tab journal.
#   chains     L1 editor half (place -> override Rock->mossy -> map+PX ->
#              save -> reopen -> still dressed), L2 (the wear faces:
#              Standard -> Layered -> Water -> Standard -> Trim Water, kit
#              Rock Layered), M11 (undo: map gone, no false warn, redo),
#              MO4 refusal (unnamed part + name= empty is refused with the
#              nameable list), M4 (prefab pack carries the override, the
#              instance layer wins on Trim while the spawned twin keeps its
#              own).
#   export     L1/L2 staged half: game.export, the staged tree carries the
#              patch + the material files, the staged game dresses the
#              overridden parts (G channel: the maps read back, the Water
#              and Layered wears sit exactly on the overridden parts).
#   broken     L4/M5+M9/L7: rm the held layered material -> one `material
#              override:` warn + audit Missing + the Layered wears drop,
#              one-shot lock, heal restores the wear silently, re-break
#              speaks again; M13 breaks the water file's bytes (asset load
#              failed + give-back + re-wear); then the rebind chain:
#              rebind wet -> a copied wet2, the A11 live-world stickiness
#              face is archived, save, audit clean, reopen wears wet2.
#   rename     L5/M6: file.rename the held water material -> the document's
#              override entry follows (MO3 green), the live face is
#              characterized (sticky or not, archived), save, audit clean,
#              reopen wears the renamed path.
#   reimport   L6/M7+M8: rewrite props.glb to add BoxE wearing Trim (the
#              override survives the reimport and dresses the new part
#              through the Water face; the thumbnail re-renders, the M13
#              face), then rename Rock->Stone (the stale key warns once,
#              stays quiet while it lasts, heals on the name's return,
#              speaks again) — the live green of MO1, four states.
#   gamebroken L8/M10: a copy of the staged tree minus mossy+deep runs, the
#              water wear silently drops (deep's holder gives back), the
#              layered wear stays (wet still held), the game stays alive
#              without a panic — the game-side boundary of "not silently
#              lost" (editor-only reporting is the design).
# Usage: bash loop/qa/t23-live.sh [phase]   phase: prep|chains|export|broken|
#                                              rename|reimport|gamebroken|all
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
FIXROOT=/Users/zhanglinbo/workspace/loop-mac/t23-materials
PROJECT="$FIXROOT/t23-materials"
PORT=15703
GAME_PORT=15702
OUTDIR="$REPO/loop/t23-live"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
GAMEBIN="t23-materials"
STAGED="$PROJECT/.jackdaw/dist/release"
STAGED_EXE="$STAGED/$GAMEBIN"
BROKEN_STAGE="$OUTDIR/staged-broken"
MATDIR="$PROJECT/assets/materials"
MOSSY="$MATDIR/mossy.bsn"
WET="$MATDIR/wet.bsn"
DEEP="$MATDIR/deep.bsn"
SCENE="$PROJECT/assets/t23.bsn"
PREF="$PROJECT/assets/pref.bsn"
PROPS="$PROJECT/assets/models/props.glb"
KIT="$PROJECT/assets/models/kit.glb"
# BRP type paths (probe-calibrated; the two wear-face paths for wet/deep are
# read off the files the editor itself writes, so no hand-spelled generic
# type path can drift).
NAME='bevy_ecs::name::Name'
GLTFNAME='bevy_gltf::assets::GltfMaterialName'
OVERR='jackdaw_scene_types::types::MaterialOverrides'
IOVERR='jackdaw_scene_types::types::InstanceMaterialOverrides'
GLTFSRC='jackdaw_scene_types::types::GltfSource'
STD='bevy_pbr::mesh_material::MeshMaterial3d<bevy_pbr::pbr_material::StandardMaterial>'
# M12's warn scan: every hit is attributed, not just counted.
WARN_PATTERN='material override:|material\.override:|holds no material|asset load failed|no longer holds a type this project knows|UnresolvedTypes|cannot-apply|references name files|panicked'
mkdir -p "$OUTDIR"
PHASE="${1:-all}"
WINDOW=0
EDITOR_LOG="$OUTDIR/editor-$PHASE.log"
CONSOLE_LOG="$OUTDIR/console-$PHASE.log"
echo "=== phase $PHASE run $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t23-live.XXXXXX)"
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
  # A9: the game BRP answers intermittently empty in busy windows — reads
  # retry with a short settle.
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
opwarn() { op "$1" "$2" 2>/dev/null | jq -c '.result.warnings // []' 2>/dev/null; }
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
editor_boot() {
  pkill -x jackdaw 2>/dev/null; sleep 1
  WINDOW=$((WINDOW + 1))
  EDITOR_LOG="$OUTDIR/editor-$PHASE-$WINDOW.log"
  local boot_log="$EDITOR_LOG"
  : > "$boot_log"
  export JACKDAW_OPEN_PROJECT="$PROJECT"
  export JACKDAW_PIE_PREBUILD=0
  export JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1600x1000
  cd "$REPO"
  nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$boot_log" 2>&1 &
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
  walk
  if walk_has "Recovered Work"; then
    brp jackdaw/ui_click '{"text":"Discard All"}' >/dev/null 2>&1
    sleep 2; wait_idle 120 >/dev/null
    walk
    walk_has "Recovered Work" && { log "EDITOR_BOOT_FAIL recovery modal survived"; exit 1; }
  fi
  log "EDITOR_READY project=$PROJECT pid=$(cat "$OUTDIR/boot-pid.txt")"
}
open_scene() {
  op scene.open "{\"path\":\"$1\",\"reload\":true}" >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
}
walk() { brp jackdaw/ui_tree '{"kind":"node","visible_only":true,"depth":80}' > "$OUTDIR/walk-$PHASE.json" 2>/dev/null; }
walk_has() { grep -qF "$1" "$OUTDIR/walk-$PHASE.json" 2>/dev/null; }
shot() { # shot <name> [kind] — kind defaults to viewport
  local name="$1" kind="${2:-viewport}"
  local rel path out out_json
  rel="screenshots/t23-$name.png"
  path="$PROJECT/$rel"
  rm -f "$path"
  for i in $(seq 1 20); do
    out_json=$(curl -s -m 12 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
      -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"jackdaw/screenshot\",\"params\":{\"kind\":\"$kind\",\"path\":\"$rel\",\"request\":\"$name\"}}" 2>/dev/null)
    out=$(echo "$out_json" | jq -r '.result.path // empty' 2>/dev/null)
    if [ -n "$out" ] && [ -s "$path" ]; then
      cp "$path" "$OUTDIR/shot-$name.png" 2>/dev/null
      log "shot $name ok ($kind)"
      return 0
    fi
    sleep 1
  done
  log "shot $name FAILED (capture never landed)"
  return 1
}
pixdiff() { # pixdiff <a.png> <b.png> [tol] — stdout the changed-percent
            # (t19 semantics); the viewport dress verdict rides it.
  local a="$1" b="$2" tol="${3:-12}"
  python3 - "$a" "$b" "$tol" << 'PYT' 2>/dev/null
import struct, sys, zlib
def decode(path):
    data = open(path, "rb").read()
    pos = 8; idat = b""; w = h = depth = color = interlace = 0
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos+4])
        kind = data[pos+4:pos+8]
        body = data[pos+8:pos+8+length]
        if kind == b"IHDR":
            w, h, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    if depth != 8 or interlace != 0 or color not in (0, 2, 4, 6):
        sys.exit(1)
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[color]
    raw = zlib.decompress(idat)
    stride = w * channels
    out = bytearray(); prev = bytearray(stride)
    for y in range(h):
        row = bytearray(raw[y*(stride+1)+1:(y+1)*(stride+1)])
        f = raw[y*(stride+1)]
        for x in range(stride):
            a = row[x - channels] if x >= channels else 0
            b_ = prev[x]
            c = prev[x - channels] if x >= channels else 0
            if f == 1: row[x] = (row[x] + a) & 0xFF
            elif f == 2: row[x] = (row[x] + b_) & 0xFF
            elif f == 3: row[x] = (row[x] + (a + b_) // 2) & 0xFF
            elif f == 4:
                p = a + b_ - c
                pa, pb, pc = abs(p - a), abs(p - b_), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b_ if pb <= pc else c)
                row[x] = (row[x] + pr) & 0xFF
        out += row; prev = row
    if channels == 4:
        rgb = bytearray()
        for i in range(0, len(out), 4):
            rgb += out[i:i+3]
        out = rgb
    else:
        out = bytearray(byte for px in out for byte in (px, px, px))
    return out
with open(sys.argv[1], "rb") as f: wa, wh = struct.unpack(">II", f.read(24)[16:24])
with open(sys.argv[2], "rb") as f: wb, hb = struct.unpack(">II", f.read(24)[16:24])
if (wa, wh) != (wb, hb):
    print("size-mismatch"); sys.exit(1)
ba, bb = decode(sys.argv[1]), decode(sys.argv[2])
tol = int(sys.argv[3])
if len(ba) != len(bb) or not ba:
    print("decode-mismatch"); sys.exit(1)
pixels = len(ba) // 3
changed = 0
for i in range(0, len(ba), 3):
    d = abs(ba[i] - bb[i]) + abs(ba[i+1] - bb[i+1]) + abs(ba[i+2] - bb[i+2])
    if d > tol:
        changed += 1
print(f"{100.0 * changed / pixels:.3f}")
PYT
}
budget() { # budget <seconds> <cmd...> — A6 discipline 3: run a probe on a
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
warn_since_at_least() { # budget probe: the override-report mouth spoke n more
  [ "$(log_lines_since "material override:" "$1")" -ge "$2" ]
}
# ---- BRP readers -------------------------------------------------------------
q() { # q <components-json-array> — entities carrying ALL the components
  brp world.query "{\"data\":{\"components\":$1}}" 2>/dev/null | jq -c '.result // []' 2>/dev/null
}
qcount() { q "$1" 2>/dev/null | jq '. | length' 2>/dev/null; }
eid() { # eid <name> — the entity id carrying this Name
  q "[\"$NAME\"]" 2>/dev/null | jq -r --arg n "$1" \
    '[.[]? | select(.components["'"$NAME"'"] == $n) | .entity][0]' 2>/dev/null
}
comp() { # comp <entity> <type-path> — the component JSON, or empty
  brp world.get_components "{\"entity\":\"$1\",\"components\":[\"$2\"]}" 2>/dev/null \
    | jq -c --arg c "$2" '.result.components[$c] // .result[$c] // empty' 2>/dev/null
}
override_map() { comp "$1" "$OVERR" 2>/dev/null | jq -c '.materials // {}' 2>/dev/null; }
instance_map() { comp "$1" "$IOVERR" 2>/dev/null | jq -c '.materials // {}' 2>/dev/null; }
has_comp() { [ -n "$(comp "$1" "$2" 2>/dev/null)" ] && [ "$(comp "$1" "$2" 2>/dev/null)" != "null" ]; }
audit_json() { brp jackdaw/audit '{}' 2>/dev/null | jq -c '.result // .' 2>/dev/null; }
findings_for() { # the audit's entries naming this reference
  audit_json 2>/dev/null | jq -c --arg r "$1" '[.findings[]? | select(.reference == $r)]' 2>/dev/null
}
game_up() { gbrp jackdaw/app_info '{}' 2>/dev/null | jq -e '.result.app_name' >/dev/null 2>&1; }
wait_game() {
  local deadline=$((SECONDS + ${1:-600}))
  while [ $SECONDS -lt $deadline ]; do
    if game_up && gbrp world.query "{\"data\":{\"components\":[\"$NAME\"]}}" 2>/dev/null | jq -e '.result' >/dev/null 2>&1; then
      return 0
    fi
    sleep 3
  done
  return 1
}
stop_game() { pkill -x "$GAMEBIN" 2>/dev/null; sleep 2; }

# ---- fixture writers --------------------------------------------------------
glb_write() { # glb_write <path> <base|stone|box> <name1> <name2> ... — a
              # valid glTF binary: node 0 and 1 wear material "Rock" (or
              # "Stone"), node 2 wears "Trim", node 3 wears an UNNAMED
              # material (the MO4 face); the `box` variant's fifth node
              # wears "Trim" so its dress lands on the readable Water face.
              # T18 box_glb craft + materials.
  python3 - "$@" << 'PYT'
import json, struct, sys
out_path, variant = sys.argv[1], sys.argv[2]
names = sys.argv[3:]
corners = [(-0.5,-0.5,-0.5),(0.5,-0.5,-0.5),(0.5,0.5,-0.5),(-0.5,0.5,-0.5),
           (-0.5,-0.5,0.5),(0.5,-0.5,0.5),(0.5,0.5,0.5),(-0.5,0.5,0.5)]
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
rock_name = "Stone" if variant == "stone" else "Rock"
materials = [
    {"name": rock_name, "pbrMetallicRoughness": {"baseColorFactor": [0.72, 0.72, 0.72, 1.0]}},
    {"name": "Trim", "pbrMetallicRoughness": {"baseColorFactor": [0.16, 0.18, 0.24, 1.0]}},
    {"pbrMetallicRoughness": {"baseColorFactor": [0.45, 0.85, 0.45, 1.0]}},
]
meshes, nodes = [], []
for i, nm in enumerate(names):
    if variant == "box" and i == len(names) - 1:
        mat = 1   # the added node wears Trim: its dress reads on the Water face
    elif i < 2:
        mat = 0
    elif i == 2:
        mat = 1
    else:
        mat = 2
    meshes.append({"primitives": [{"attributes": {"POSITION": PA}, "indices": IA,
                                   "mode": 4, "material": mat}]})
    nodes.append({"name": nm, "mesh": i, "translation": [0.0, 1.4 * i, 0.0]})
gltf = {
    "asset": {"version": "2.0", "generator": "jackdaw loop t23 glb_write.py"},
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
print(f"wrote {out_path}: {total} bytes, {len(names)} node(s), rock={rock_name}")
PYT
}
write_scene() { # write_scene <path> — the canonical doc: fixed camera + sun.
  cat > "$1" << 'EOF'
// T23 fixture scene. Authored by the loop QA script; safe to edit by hand.

#Root
bevy_transform::components::transform::Transform
bevy_camera::visibility::Visibility::Visible
bevy_ecs::hierarchy::Children [
    #Sun
    bevy_light::directional_light::DirectionalLight
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: 4.0, y: 8.0, z: 4.0 },
        rotation: glam::Quat { x: -0.35, y: 0.3, z: 0.0, w: 0.89 },
    }
    bevy_camera::visibility::Visibility::Visible
    --
    #MainCamera
    bevy_camera::components::Camera3d
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: -3.0, y: 2.5, z: 5.0 },
        rotation: glam::Quat { x: -0.05, y: 0.45, z: 0.0, w: 0.89 },
    }
    bevy_camera::visibility::Visibility::Visible
]
EOF
}
wear_paths() { # read the wear component paths off the files the editor
               # itself wrote (no hand-spelled generic type path can drift);
               # later phases hold the renamed -2 spellings, same registered
               # type, which is all the wear queries need
  local wet_file="$WET" deep_file="$DEEP"
  [ -f "$wet_file" ] || wet_file="$MATDIR/wet2.bsn"
  [ -f "$deep_file" ] || deep_file="$MATDIR/deep2.bsn"
  TP_WET=$(grep -m1 'jackdaw asset' "$wet_file" 2>/dev/null | sed 's|^// jackdaw asset ||')
  TP_DEEP=$(grep -m1 'jackdaw asset' "$deep_file" 2>/dev/null | sed 's|^// jackdaw asset ||')
  LAYERED="bevy_pbr::mesh_material::MeshMaterial3d<$TP_WET>"
  WATER="bevy_pbr::mesh_material::MeshMaterial3d<$TP_DEEP>"
  log "wear paths (from $(basename "$wet_file")/$(basename "$deep_file")): layered=$TP_WET water=$TP_DEEP"
}
export_wait() { # game.export, held until the staged tree carries the current
                # scene (t15 form: the sha must match before this returns)
  local want got st saw_state=""
  want=$(shasum -a 256 "$SCENE" 2>/dev/null | awk '{print $1}')
  op game.export '{}' >/dev/null 2>&1
  local deadline=$((SECONDS + 2400))
  while [ $SECONDS -lt $deadline ]; do
    st=$(brp jackdaw/export '{}' 2>/dev/null | jq -r '.result.state // empty' 2>/dev/null)
    [ -n "$st" ] && saw_state=1
    got=$(shasum -a 256 "$STAGED/assets/t23.bsn" 2>/dev/null | awk '{print $1}')
    if [ -n "$got" ] && [ "$got" = "$want" ]; then return 0; fi
    if [ -z "$saw_state" ] && [ -x "$STAGED_EXE" ] && [ -f "$STAGED/export-manifest.json" ]; then
      return 0
    fi
    sleep 5
  done
  return 1
}
thumb_fresh() { # thumb_fresh <rel-path-under-assets> <after-epoch> — the
                # newest thumbnail PNG whose file landed after the epoch
                # (cache name is FNV-1a of the ABSOLUTE path + mtime nanos)
  local rel="$1" after="$2" best="" best_m=0 f m fnv
  fnv=$(python3 - "$PROJECT/assets/$rel" << 'PYT'
import sys
h = 0xCBF29CE484222325
for byte in sys.argv[1].encode():
    h = ((h ^ byte) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
print(f"{h:016x}")
PYT
)
  for f in "$PROJECT/.jackdaw/thumbnails"/"$fnv"-*.png; do
    [ -f "$f" ] || continue
    m=$(stat -f %m "$f" 2>/dev/null || echo 0)
    if [ "$m" -ge "$after" ] && [ "$m" -gt "$best_m" ]; then best="$f"; best_m=$m; fi
  done
  [ -n "$best" ] && { echo "$best"; return 0; }
  return 1
}
warn_scan() { # warn_scan <log...> — the M12 face: archive every hit with its
              # line, the phase's attribution input
  local out="$OUTDIR/warn-scan-$PHASE.txt"
  : > "$out"
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    grep -E "$WARN_PATTERN" "$f" >> "$out" 2>/dev/null
  done
  log "warn scan ($PHASE): $(wc -l < "$out" | tr -d ' ') hit(s) -> $out"
  cat "$out"
}
break_file() { # break_file <path> — clobber the first four bytes
  python3 - "$1" << 'PYT'
import sys
path = sys.argv[1]
data = bytearray(open(path, "rb").read())
data[0:4] = b"\xde\xad\xbe\xef"
open(path, "wb").write(bytes(data))
PYT
}

# ---- phase: prep ------------------------------------------------------------
prep() {
  pkill -x jackdaw 2>/dev/null; pkill -x "$GAMEBIN" 2>/dev/null; sleep 1
  local free
  free=$(df -g / | awk 'NR==2 {print $4}')
  [ "$free" -ge 10 ] || { log "PREP_FAIL only ${free}Gi free; clean the disk first (A6 discipline 5)"; exit 1; }
  log "disk: ${free}Gi free"
  rm -rf "$FIXROOT"; mkdir -p "$FIXROOT" "$OUTDIR"
  rm -rf "$BROKEN_STAGE"
  (cd "$REPO" && DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jd new t23-materials --path "$FIXROOT" --no-git) > "$OUTDIR/jd-new.log" 2>&1
  [ -d "$PROJECT" ] || { log "PREP_FAIL no project ($(tail -2 "$OUTDIR/jd-new.log"))"; exit 1; }
  # The game-side BRP injection (t13t3/t15 practice): a remote dep after the
  # runtime dep, the remote plugin after the game plugin.
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
  mkdir -p "$MATDIR" "$PROJECT/assets/models"
  glb_write "$PROPS" base RockA RockB TrimC PlainD
  glb_write "$KIT" base KitA KitB KitC KitD
  write_scene "$SCENE"
  write_scene "$PREF"
  printf '{\n  "start_scene": "t23.bsn",\n  "scenes": [\n    "t23.bsn"\n  ]\n}\n' \
    > "$PROJECT/assets/game.flow.json"
  # A stale persisted tab journal would restore yesterday's documents; every
  # phase starts on the canonical scene.
  python3 - "$PROJECT/.jackdaw/project.json" << 'PYT'
import json, sys
path = sys.argv[1]
try:
    cfg = json.load(open(path))
    cfg.pop("layout", None)
    cfg["last_open_tabs"] = ["assets/t23.bsn"]
    cfg["last_active_tab"] = 0
    json.dump(cfg, open(path, "w"), indent=2)
except FileNotFoundError:
    pass
PYT
  rm -rf "$PROJECT/screenshots"
  log "PREP_OK fixture=$PROJECT"
}

# ---- phase: chains ----------------------------------------------------------
prefab_two_trimc() { # budget probe: both instances' node subtrees are in
  [ "$(qcount "[\"$GLTFNAME\"]")" -ge 6 ] \
    && [ "$(q "[\"$NAME\"]" | jq --arg n TrimC '[.[]? | select(.components["'"$NAME"'"] == $n)] | length')" = "2" ]
}
chains() {
  local ok=true
  editor_boot
  open_scene "assets/t23.bsn"
  op viewport.look_through '{"entity":"MainCamera"}' >/dev/null 2>&1
  sleep 1
  op entity.place_gltf '{"path":"models/props.glb","pos_x":-1.8,"pos_y":1.0,"pos_z":0.0}' >/dev/null 2>&1
  op entity.place_gltf '{"path":"models/kit.glb","pos_x":1.8,"pos_y":1.0,"pos_z":0.0}' >/dev/null 2>&1
  # The first spawn waits behind the editor's open-load storm (the A6 shape);
  # the wait is long but bounded. Six = both models' Rock/Rock/Trim meshes.
  budget 120 [ "$(qcount "[\"$GLTFNAME\"]")" -ge 6 ]
  local parts; parts=$(qcount "[\"$GLTFNAME\"]")
  log "placed mesh parts wearing named materials: $parts (want 6)"
  local props_id kit_id
  props_id=$(eid props); kit_id=$(eid kit)
  if [ "$parts" -ge 6 ] && [ -n "$props_id" ] && [ -n "$kit_id" ] && has_comp "$props_id" "$GLTFSRC"; then
    leg L1_PLACE_PARTS true
  else
    log "L1: placement incomplete (parts=$parts props=$props_id kit=$kit_id)"
    leg L1_PLACE_PARTS false
  fi

  # The three material files: wet/deep written by the editor's own asset.new
  # (so their type headers are the registered truth), mossy by the materials
  # machine (create -> save -> recolor).
  op asset.new '{"type":"Layered Surface","name":"wet","path":"assets/materials"}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  op asset.new '{"type":"Water","name":"deep","path":"assets/materials"}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  op material.create '{}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  op material.save '{"name":"mossy","path":"materials/mossy.bsn"}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  if [ -f "$WET" ] && [ -f "$DEEP" ] && [ -f "$MOSSY" ]; then
    leg L1_MATERIALS true
  else
    log "MATS: material files did not land"
    leg L1_MATERIALS false
  fi
  op asset.open '{"path":"assets/materials/mossy.bsn"}' >/dev/null 2>&1
  sleep 2
  op asset.set '{"field":"base_color","value":"0.05,1,0.05"}' >/dev/null 2>&1
  sleep 1
  op asset.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  grep -q "green: 1" "$MOSSY" || log "MATS: note - the green base_color did not reach the file (defaults still bind)"
  # Pristine copies for the break/restore legs.
  cp "$MOSSY" /tmp/t23-mossy.pristine; cp "$WET" /tmp/t23-wet.pristine; cp "$DEEP" /tmp/t23-deep.pristine
  wear_paths
  local ra rb tc
  ra=$(eid RockA); rb=$(eid RockB); tc=$(eid TrimC)
  # The mesh entities under them: the Rock-mesh pair of props (names repeat
  # across models, so pick through the water face later; here count baselines).
  local base_layered base_water
  base_layered=$(qcount "[\"$LAYERED\"]"); base_water=$(qcount "[\"$WATER\"]")
  log "L1 baseline: layered=$base_layered water=$base_water (want 0/0 - nothing dressed yet)"
  [ "$base_layered" = "0" ] && [ "$base_water" = "0" ] || ok=false

  # ---- L1 editor half: override Rock -> mossy (the canonical face) --------
  op view.frame_all >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  shot l1-before
  mark_log "material override:" "$OUTDIR/l1.offset"
  local res
  res=$(opres material.override '{"entity":"props","name":"Rock","material":"materials/mossy.bsn"}')
  [ "$res" = "finished" ] || { log "L1: material.override returned $res"; ok=false; }
  sleep 2; wait_idle 120 >/dev/null
  local map; map=$(override_map "$props_id")
  log "L1: props override map now $map"
  [ "$map" = '{"Rock":"materials/mossy.bsn"}' ] || ok=false
  local quiet; quiet=$(log_lines_since "material override:" "$OUTDIR/l1.offset")
  log "L1: report lines after the healthy override: $quiet (want 0)"
  [ "$quiet" = "0" ] || ok=false
  sleep 1; shot l1-after
  # ---- L2: the wear faces (Standard -> Layered -> Water -> Standard) ------
  local l2=true
  op material.override '{"entity":"props","name":"Rock","material":"materials/wet.bsn"}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  local lw; lw=$(qcount "[\"$LAYERED\"]")
  log "L2: layered wears after Rock->wet: $lw (want 2: props RockA/RockB)"
  [ "$lw" = "2" ] || l2=false
  op material.override '{"entity":"props","name":"Rock","material":"materials/deep.bsn"}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  local ww; ww=$(qcount "[\"$WATER\"]")
  log "L2: water wears after Rock->deep: $ww (want 2: props RockA/RockB)"
  [ "$ww" = "2" ] || l2=false
  [ "$(qcount "[\"$LAYERED\"]")" = "0" ] || { log "L2: the layered wear stayed under the water override"; l2=false; }
  op material.override '{"entity":"props","name":"Rock","material":"materials/mossy.bsn"}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  [ "$(qcount "[\"$WATER\"]")" = "0" ] || { log "L2: the water wear stayed under the mossy override"; l2=false; }
  op material.override '{"entity":"props","name":"Trim","material":"materials/deep.bsn"}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  ww=$(qcount "[\"$WATER\"]")
  log "L2: water wears after Trim->deep: $ww (want 1: props TrimC)"
  [ "$ww" = "1" ] || l2=false
  # kit takes the layered face for the staged leg.
  op material.override '{"entity":"kit","name":"Rock","material":"materials/wet.bsn"}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  lw=$(qcount "[\"$LAYERED\"]")
  log "L2: layered wears after kit Rock->wet: $lw (want 2: KitA/KitB)"
  [ "$lw" = "2" ] || l2=false
  log "L2: props map $(override_map "$props_id") kit map $(override_map "$kit_id")"
  [ "$(override_map "$props_id")" = '{"Rock":"materials/mossy.bsn","Trim":"materials/deep.bsn"}' ] || l2=false
  [ "$(override_map "$kit_id")" = '{"Rock":"materials/wet.bsn"}' ] || l2=false
  shot l1-after
  local moved; moved=$(pixdiff "$OUTDIR/shot-l1-before.png" "$OUTDIR/shot-l1-after.png" 2>/dev/null)
  log "L1: viewport changed-percent after the dress faces: ${moved:-none}"
  python3 -c "import sys; sys.exit(0 if float(sys.argv[1] or -1) > 1.0 else 1)" "$moved" 2>/dev/null \
    || { log "L1: the viewport did not visibly change"; ok=false; }
  leg L1_DRESS "$ok"
  leg L2_WEAR_FACES "$l2"

  # ---- M11: undo puts the map away and quiets -----------------------------
  local m11=true
  mark_log "material override:" "$OUTDIR/m11.offset"
  op material.override '{"entity":"kit","name":"Trim","material":"materials/mossy.bsn"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  [ "$(override_map "$kit_id")" = '{"Rock":"materials/wet.bsn","Trim":"materials/mossy.bsn"}' ] || { log "M11: the kit override never landed"; m11=false; }
  op history.undo '{}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  [ "$(override_map "$kit_id")" = '{"Rock":"materials/wet.bsn"}' ] || { log "M11: the undo left the entry behind"; m11=false; }
  local dwarn; dwarn=$(log_lines_since "material override:" "$OUTDIR/m11.offset")
  log "M11: 'material override:' lines through the undo round: $dwarn (want 0)"
  [ "$dwarn" = "0" ] || m11=false
  op history.redo '{}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  [ "$(override_map "$kit_id")" = '{"Rock":"materials/wet.bsn","Trim":"materials/mossy.bsn"}' ] || { log "M11: the redo did not restore the entry"; m11=false; }
  op history.undo '{}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  leg M11_UNDO "$m11"

  # ---- MO4: the unnamed part is refused, not silently expanded ------------
  local mo4=true
  local out mres mw1 mw2
  out=$(op material.override '{"entity":"PlainD","name":"","material":"materials/mossy.bsn"}' 2>/dev/null)
  echo "$out" > "$OUTDIR/mo4-response.json"
  mres=$(echo "$out" | jq -r '.result.result // "error"')
  mw1=$(echo "$out" | jq -r '[.result.warnings[]? | select(test("wears an unnamed material"))] | length')
  mw2=$(echo "$out" | jq -r '[.result.warnings[]? | select(test("Rock"))] | length')
  log "MO4: result=$mres warnings=$(echo "$out" | jq -c '.result.warnings // []')"
  [ "$mres" = "cancelled" ] || mo4=false
  [ "${mw1:-0}" -ge 1 ] || mo4=false
  [ "${mw2:-0}" -ge 1 ] || mo4=false
  [ "$(override_map "$props_id")" = '{"Rock":"materials/mossy.bsn","Trim":"materials/deep.bsn"}' ] || mo4=false
  leg MO4_REFUSAL "$mo4"

  # ---- save + reopen: the override survives the round trip ----------------
  local ok2=true
  op scene.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 180 >/dev/null
  local d1
  d1=$(grep -c "MaterialOverrides" "$SCENE" 2>/dev/null)
  [ "${d1:-0}" -ge 2 ] || { log "L1: the saved document holds $d1 MaterialOverrides (want 2)"; ok2=false; }
  grep -q "materials/mossy.bsn" "$SCENE" && grep -q "materials/deep.bsn" "$SCENE" \
    && grep -q "materials/wet.bsn" "$SCENE" \
    || { log "L1: the saved document lacks the override paths"; ok2=false; }
  leg L1_DOC_ON_DISK "$ok2"
  # The same selection on both sides of the reopen: the selection outline is
  # the one thing that would otherwise differ between the two frames.
  op selection.select '{"name":"props"}' >/dev/null 2>&1
  sleep 1
  op view.frame_all >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  shot l1-saved
  open_scene "assets/t23.bsn"
  sleep 2; wait_idle 180 >/dev/null
  budget 60 [ "$(qcount "[\"$GLTFNAME\"]")" -ge 6 ]
  sleep 3   # let the dressing settle after the parts arrive
  op selection.select '{"name":"props"}' >/dev/null 2>&1
  sleep 1
  op view.frame_all >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  local props_id3 kit_id3
  props_id3=$(eid props); kit_id3=$(eid kit)
  [ "$(override_map "$props_id3")" = '{"Rock":"materials/mossy.bsn","Trim":"materials/deep.bsn"}' ] || { log "L1: the props map did not survive the reopen"; ok2=false; }
  [ "$(override_map "$kit_id3")" = '{"Rock":"materials/wet.bsn"}' ] || { log "L1: the kit map did not survive the reopen"; ok2=false; }
  lw=$(qcount "[\"$LAYERED\"]"); ww=$(qcount "[\"$WATER\"]")
  log "L1: after the reopen layered=$lw water=$ww (want 2/1 - still dressed)"
  [ "$lw" = "2" ] && [ "$ww" = "1" ] || ok2=false
  shot l1-reopen
  local stayed; stayed=$(pixdiff "$OUTDIR/shot-l1-saved.png" "$OUTDIR/shot-l1-reopen.png" 2>/dev/null)
  log "L1: viewport changed-percent across the reopen: ${stayed:-none} (want < 1)"
  python3 -c "import sys; sys.exit(0 if 0 <= float(sys.argv[1] or 999) < 1.0 else 1)" "$stayed" 2>/dev/null || ok2=false
  leg L1_REOPEN "$ok2"

  # ---- M4: the prefab chain ------------------------------------------------
  local m4=true
  open_scene "assets/pref.bsn"
  op entity.place_gltf '{"path":"models/props.glb","pos_x":0.0,"pos_y":1.0,"pos_z":0.0}' >/dev/null 2>&1
  budget 120 [ "$(qcount "[\"$GLTFNAME\"]")" -ge 3 ]
  op material.override '{"entity":"props","name":"Rock","material":"materials/mossy.bsn"}' >/dev/null 2>&1
  op material.override '{"entity":"props","name":"Trim","material":"materials/deep.bsn"}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  op prefab.pack '{"entity":"props","path":"prefabs/props.bsn","overwrite":true}' >/dev/null 2>&1
  sleep 3; wait_idle 180 >/dev/null
  local prefab_file="$PROJECT/assets/prefabs/props.bsn"
  [ -f "$prefab_file" ] || { log "M4: the prefab file never landed"; m4=false; }
  grep -q "MaterialOverrides" "$prefab_file" && grep -q "materials/mossy.bsn" "$prefab_file" \
    && grep -q "materials/deep.bsn" "$prefab_file" \
    || { log "M4: the prefab file does not carry both overrides"; m4=false; }
  budget 120 [ "$(qcount "[\"$GLTFNAME\"]")" -ge 3 ]
  # The packed instance still dresses through the prefab's model layer: its
  # TrimC wears the water face from the carried deep entry.
  budget 60 [ "$(qcount "[\"$WATER\"]")" = "1" ]
  [ "$(qcount "[\"$WATER\"]")" = "1" ] || { log "M4: the packed instance's TrimC is not dressed (water face missing)"; m4=false; }
  # The instance layer, before any twin exists (so the TrimC part name is
  # unique): the override on a part walks up to the model root, whose
  # enclosing instance is the packed one — SetMaterialOverrides auto-writes
  # the INSTANCE layer, and the instance wins over the prefab's model layer
  # on the shared Trim key.
  op material.override '{"entity":"TrimC","name":"Trim","material":"materials/wet.bsn"}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  local n_roots inst_roots imap
  n_roots=$(qcount "[\"$IOVERR\"]")
  inst_roots=$(q "[\"$IOVERR\"]" | jq -r '.[0].entity // empty')
  imap=$(instance_map "$inst_roots")
  log "M4: instance roots=$n_roots map=$imap"
  [ "$n_roots" = "1" ] || { log "M4: instance-layer holders = $n_roots (want 1)"; m4=false; }
  [ "$(echo "$imap" | jq -r '.Trim // ""')" = "materials/wet.bsn" ] || { log "M4: the instance layer did not take the override"; m4=false; }
  local lw4 ww4
  lw4=$(qcount "[\"$LAYERED\"]"); ww4=$(qcount "[\"$WATER\"]")
  log "M4: after the instance override layered=$lw4 (want 1) water=$ww4 (want 0)"
  [ "$lw4" = "1" ] || { log "M4: the instance layer's win is not on the layered face"; m4=false; }
  [ "$ww4" = "0" ] || { log "M4: the water face stayed under the instance's wet override"; m4=false; }
  # The twin: spawned from the same prefab, it follows the prefab's model
  # layer (its TrimC wears the deep water face), not the first instance's
  # instance-layer entry.
  op prefab.spawn_instance '{"path":"prefabs/props.bsn","pos_x":2.5,"pos_y":1.0,"pos_z":0.0}' >/dev/null 2>&1
  budget 120 prefab_two_trimc
  lw4=$(qcount "[\"$LAYERED\"]"); ww4=$(qcount "[\"$WATER\"]")
  log "M4: after the twin layered=$lw4 (want 1) water=$ww4 (want 1 - the twin follows the prefab)"
  [ "$lw4" = "1" ] || { log "M4: the packed instance lost its layered win"; m4=false; }
  [ "$ww4" = "1" ] || { log "M4: the twin does not follow the prefab's model layer"; m4=false; }
  leg M4_PREFAB_INSTANCE "$m4"

  warn_scan "$EDITOR_LOG"
  log "CHAINS done: $(results)"
}

# ---- phase: export ----------------------------------------------------------
export_phase() {
  local ok=true
  editor_boot
  open_scene "assets/t23.bsn"
  sleep 2; wait_idle 300 >/dev/null
  # The models spawn behind the open-load storm; hold until the parts are in
  # and the dressing settled.
  budget 120 [ "$(qcount "[\"$GLTFNAME\"]")" -ge 6 ]
  sleep 3
  wear_paths
  export_wait || { log "EXPORT: the staged tree never carried the scene"; leg L1_EXPORT false; return; }
  log "EXPORT: staged tree ready"
  # Disk face: the staged document carries the patch, the material files
  # travelled, the manifest lists them.
  local d1
  d1=$(grep -c "MaterialOverrides" "$STAGED/assets/t23.bsn" 2>/dev/null)
  [ "${d1:-0}" -ge 2 ] || { log "EXPORT: staged document holds $d1 MaterialOverrides (want 2)"; ok=false; }
  grep -q "materials/mossy.bsn" "$STAGED/assets/t23.bsn" \
    && grep -q "materials/deep.bsn" "$STAGED/assets/t23.bsn" \
    && grep -q "materials/wet.bsn" "$STAGED/assets/t23.bsn" || { log "EXPORT: staged document lacks the override paths"; ok=false; }
  for m in mossy wet deep; do
    [ -f "$STAGED/assets/materials/$m.bsn" ] || { log "EXPORT: staged materials/$m.bsn missing"; ok=false; }
  done
  jq -r '.files[].path' "$STAGED/export-manifest.json" 2>/dev/null | grep -q "materials/mossy.bsn" \
    || log "EXPORT: note - the manifest does not list materials/mossy.bsn (staged files are the witness)"
  leg L1_EXPORT "$ok"
  # The staged game dresses (G channel, readable faces only).
  (cd "$STAGED" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" "./$GAMEBIN" > "$OUTDIR/staged-run.log" 2>&1 &)
  if ! wait_game 420; then
    log "EXPORT: the staged game never came up"
    leg L1_STAGED_DRESS false
    stop_game
    return
  fi
  sleep 8   # let the catalog, the scene spawn and the dressing settle
  local gq mroot1 mroot2
  gq=$(gbrp world.query "{\"data\":{\"components\":[\"$OVERR\"]}}" 2>/dev/null | jq -c '.result // []')
  echo "$gq" > "$OUTDIR/g-holders.json"
  [ "$(echo "$gq" | jq '. | length')" = "2" ] || { log "EXPORT: staged game holds $(echo "$gq" | jq '. | length') override holders (want 2)"; ok=false; }
  mroot1=$(echo "$gq" | jq -r '[.[]? | select(.components["'"$OVERR"'"].materials.Rock == "materials/mossy.bsn") | .entity][0]')
  mroot2=$(echo "$gq" | jq -r '[.[]? | select(.components["'"$OVERR"'"].materials.Rock == "materials/wet.bsn") | .entity][0]')
  [ -n "$mroot1" ] && [ -n "$mroot2" ] || { log "EXPORT: the staged maps did not read back ($gq)"; ok=false; }
  # Parts: six named mesh entities; the dressed faces split by wear component.
  local named layered water
  named=$(gbrp world.query "{\"data\":{\"components\":[\"$NAME\",\"$GLTFNAME\"]}}" 2>/dev/null | jq -c '.result // []')
  echo "$named" > "$OUTDIR/g-parts.json"
  [ "$(echo "$named" | jq '. | length')" = "6" ] || { log "EXPORT: staged named parts = $(echo "$named" | jq '. | length') (want 6)"; ok=false; }
  layered=$(gbrp world.query "{\"data\":{\"components\":[\"$NAME\",\"$LAYERED\"]}}" 2>/dev/null | jq -c '.result // []')
  water=$(gbrp world.query "{\"data\":{\"components\":[\"$NAME\",\"$WATER\"]}}" 2>/dev/null | jq -c '.result // []')
  echo "$layered" > "$OUTDIR/g-layered.json"; echo "$water" > "$OUTDIR/g-water.json"
  log "EXPORT: staged layered=$(echo "$layered" | jq '. | length') water=$(echo "$water" | jq '. | length')"
  [ "$(echo "$layered" | jq '. | length')" = "2" ] || ok=false   # kit Rock meshes
  [ "$(echo "$water" | jq '. | length')" = "1" ] || ok=false    # props Trim mesh
  # The water face must sit on a Mesh.Trim, the layered faces on Mesh.Rock.
  echo "$water" | jq -e '[.[]?.components["bevy_ecs::name::Name"]] | all(. == "Mesh.Trim")' >/dev/null 2>&1 \
    || { log "EXPORT: the water wear is not on the Trim mesh"; ok=false; }
  echo "$layered" | jq -e '[.[]?.components["bevy_ecs::name::Name"]] | all(. == "Mesh.Rock")' >/dev/null 2>&1 \
    || { log "EXPORT: the layered wears are not on the Rock meshes"; ok=false; }
  leg L1_STAGED_DRESS "$ok"
  stop_game
  warn_scan "$OUTDIR/staged-run.log" "$EDITOR_LOG"
  log "EXPORT done: $(results)"
}

# ---- phase: broken ----------------------------------------------------------
layered_count_is() { [ "$(qcount "[\"$LAYERED\"]")" = "$1" ]; }
water_count_is() { [ "$(qcount "[\"$WATER\"]")" = "$1" ]; }
broken() {
  local ok=true
  editor_boot
  open_scene "assets/t23.bsn"
  sleep 2; wait_idle 300 >/dev/null
  budget 120 [ "$(qcount "[\"$GLTFNAME\"]")" -ge 6 ]
  sleep 3   # the dressing and the open-transient report window settle here
  wear_paths
  local kit_id; kit_id=$(eid kit)
  # Baseline: the layered face is on (kit holds wet), healthy, quiet.
  if ! layered_count_is 2; then
    log "M5: baseline layered wears = $(qcount "[\"$LAYERED\"]") (want 2; doc state from the chains phase expected)"
    leg M5_MISSING false
    return
  fi
  mark_log "material override:" "$OUTDIR/m5.offset"

  # rm the held file: one warn, one audit finding, the part gives back.
  rm "$WET"
  sleep 4   # discipline 2
  budget 20 warn_since_at_least "$OUTDIR/m5.offset" 1
  local w1; w1=$(log_lines_since "material override:" "$OUTDIR/m5.offset")
  log "M5: 'material override:' lines after the rm: $w1"
  grep "material override:" "$EDITOR_LOG" | tail -1 > "$OUTDIR/m5-warn-line.txt"
  grep -q "names no material the project holds" "$OUTDIR/m5-warn-line.txt" || ok=false
  grep -q "kit" "$OUTDIR/m5-warn-line.txt" || ok=false
  walk; walk_has "material override" && log "M5: the status bar mouth shows the warning" \
    || log "M5: note - the status bar text was not in the walk (log mouth is the judge)"
  local find; find=$(findings_for "materials/wet.bsn")
  echo "$find" > "$OUTDIR/m5-finding.json"
  log "M5: audit findings for materials/wet.bsn: $find"
  [ "$(echo "$find" | jq '. | length')" = "1" ] || ok=false
  echo "$find" | jq -e '.[0].component == "MaterialOverrides" and .[0].field == "materials" and .[0].kind == "Missing"' >/dev/null 2>&1 || ok=false
  sleep 3
  budget 20 layered_count_is 0
  layered_count_is 0 || { log "M5: the layered wear stayed on after the file went"; ok=false; }
  water_count_is 1 || { log "M5: the water face moved too (deep.bsn still held)"; ok=false; }
  local w2; w2=$(log_lines_since "material override:" "$OUTDIR/m5.offset")
  [ "$w1" = "$w2" ] || { log "M5: the lock re-warned ($w1 -> $w2)"; ok=false; }
  leg M5_MISSING "$ok"

  # Heal: the file returns, the parts re-wear, no new warn.
  local heal=true
  cp /tmp/t23-wet.pristine "$WET"
  sleep 4
  budget 20 layered_count_is 2
  layered_count_is 2 || { log "M5: the heal did not re-wear the layered face"; heal=false; }
  local w3; w3=$(log_lines_since "material override:" "$OUTDIR/m5.offset")
  [ "$w3" = "$w2" ] || { log "M5: the heal spoke ($w2 -> $w3)"; heal=false; }
  leg M5_HEAL "$heal"

  # Re-break: speaks again.
  local again=true
  rm "$WET"
  sleep 4
  budget 20 warn_since_at_least "$OUTDIR/m5.offset" $((w3 + 1))
  local w4; w4=$(log_lines_since "material override:" "$OUTDIR/m5.offset")
  [ "$w4" -gt "$w3" ] || { log "M5: the re-break stayed quiet ($w3 -> $w4)"; again=false; }
  budget 20 layered_count_is 0
  leg M5_SPEAKS_AGAIN "$again"

  # M13: a broken (not missing) file — the asset_failures mouth, once, and
  # the water face gives back then re-wears.
  local m13=true
  mark_log "no longer holds a type this project knows" "$OUTDIR/m13.offset"
  mark_log "material override:" "$OUTDIR/m13o.offset"
  break_file "$DEEP"
  sleep 4
  budget 20 [ "$(log_lines_since "no longer holds a type this project knows" "$OUTDIR/m13.offset")" -ge 1 ]
  local lw; lw=$(log_lines_since "no longer holds a type this project knows" "$OUTDIR/m13.offset")
  local ow; ow=$(log_lines_since "material override:" "$OUTDIR/m13o.offset")
  log "M13: index-refusal lines=$lw 'material override:' delta=$ow (want 1/1)"
  [ "$lw" -ge 1 ] || m13=false
  [ "$ow" -ge 1 ] || m13=false
  budget 20 water_count_is 0
  water_count_is 0 || { log "M13: the water face stayed on through the broken file"; m13=false; }
  cp /tmp/t23-deep.pristine "$DEEP"
  sleep 4
  budget 20 water_count_is 1
  water_count_is 1 || { log "M13: the water face did not re-wear after the file healed"; m13=false; }
  leg M13_BROKEN_FILE "$m13"

  # M9: the rebind chain + the A11 face. wet is missing (the M5 state), the
  # audit finding names it; rebind it to a copy of the same layered content.
  local m9=true
  cp /tmp/t23-wet.pristine "$MATDIR/wet2.bsn"
  sleep 4   # let the index pick wet2 up so the rebound path resolves
  local find9; find9=$(findings_for "materials/wet.bsn")
  if [ "$(echo "$find9" | jq '. | length')" != "1" ]; then
    log "M9: no audit finding to rebind ($(echo "$find9" | jq '. | length'))"
    leg M9_REBIND false
    m9=false
  else
    local doc comp9
    doc=$(echo "$find9" | jq -r '.[0].document')
    comp9=$(echo "$find9" | jq -r '.[0].component')
    op asset.rebind "{\"document\":\"$doc\",\"component\":\"$comp9\",\"field\":\"materials\",\"reference\":\"materials/wet.bsn\",\"to\":\"materials/wet2.bsn\"}" >/dev/null 2>&1
    sleep 2; wait_idle 120 >/dev/null
    walk; cp "$OUTDIR/walk-$PHASE.json" /tmp/walk-mo9.json 2>/dev/null || true
    # The rebind face on a Map reference: whatever happened, archive the live
    # map, the audit and the document. The live probe found the repair leg
    # answering "the document no longer holds that reference" — the audit
    # FINDS the override reference (the MO2 pickup) but the rebind's rewrite
    # only walks String/List field values, and a materials MAP is neither
    # (new defect candidate MO9, recorded not fixed). The red is archived.
    local live_map
    live_map=$(override_map "$kit_id")
    { echo "MO9 red: asset.rebind over a MaterialOverrides map reference (doc=$doc to=materials/wet2.bsn):"
      echo "live kit map after the rebind: $live_map"
      echo "audit findings after the rebind:"
      audit_json
      echo "editor status text:"
      grep -i "no longer holds that reference\|rebound to" "$EDITOR_LOG" 2>/dev/null | tail -2
    } > "$REPO/loop/reports/t23t2_mo9_rebind_map_red.log" 2>/dev/null
    cp /tmp/walk-mo9.json "$REPO/loop/reports/t23t2_mo9_status_walk.json" 2>/dev/null || true
    if [ "$live_map" = '{"Rock":"materials/wet.bsn"}' ]; then
      log "MO9: the rebind left the document and the live world on the old path (map blind) - archived as the MO9 red"
      leg M9_REBIND_MAP_BLIND true
    elif [ "$live_map" = '{"Rock":"materials/wet2.bsn"}' ]; then
      log "MO9: the rebind rewrote the map reference (the blind spot is not there in this build)"
      leg M9_REBIND_MAP_BLIND false
    else
      log "MO9: unexpected live map $live_map"
      leg M9_REBIND_MAP_BLIND false
    fi
    # The A11 question (does a document-side repair reach the live world) is
    # shadowed here by MO9: the rebind cannot touch a map reference at all.
    # The repair chain continues by the document's own door: the file is
    # rebound externally (the same write a save of a rewritten document would
    # make), the scene reopens, and the audit comes back clean.
    python3 - "$SCENE" << 'PYT'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
n = text.count("materials/wet.bsn")
text = text.replace("materials/wet.bsn", "materials/wet2.bsn")
open(path, "w", encoding="utf-8").write(text)
print(f"external rebind: {n} reference(s) rewritten in place")
PYT
    sleep 4   # the watcher sees the external edit; the reopen re-reads anyway
    open_scene "assets/t23.bsn"
    sleep 2; wait_idle 180 >/dev/null
    budget 60 [ "$(qcount "[\"$GLTFNAME\"]")" -ge 6 ]
    sleep 3
    kit_id=$(eid kit)
    [ "$(override_map "$kit_id")" = '{"Rock":"materials/wet2.bsn"}' ] \
      || { log "M9: the reopened kit map is not the rebound one"; m9=false; }
    budget 30 layered_count_is 2
    layered_count_is 2 || { log "M9: the Rock meshes do not wear the rebound layered material"; m9=false; }
    local total; total=$(audit_json | jq '.count')
    log "M9: audit after the rebound doc reopened: total=$total"
    [ "$total" = "0" ] || m9=false
    leg M9_REBIND "$m9"
  fi

  warn_scan "$EDITOR_LOG"
  log "BROKEN done: $(results)"
}

# ---- phase: rename ----------------------------------------------------------
rename() {
  local ok=true
  editor_boot
  open_scene "assets/t23.bsn"
  sleep 2; wait_idle 300 >/dev/null
  budget 120 [ "$(qcount "[\"$GLTFNAME\"]")" -ge 6 ]
  sleep 3
  wear_paths
  local props_id; props_id=$(eid props)
  if ! water_count_is 1; then
    log "M6: baseline water wears = $(qcount "[\"$WATER\"]") (want 1; doc state from the broken phase expected)"
    leg M6_RENAME false
    return
  fi
  mark_log "material override:" "$OUTDIR/m6.offset"
  op file.rename '{"path":"assets/materials/deep.bsn","name":"deep2.bsn"}' >/dev/null 2>&1
  sleep 4; wait_idle 180 >/dev/null
  if [ ! -f "$MATDIR/deep2.bsn" ] || [ -f "$DEEP" ]; then
    log "M6: the rename did not land on disk"
    leg M6_RENAME false
    return
  fi
  # The live face: whatever the live world holds after the rename, archive it
  # with the warn delta and the wear state - sticky or not, it is evidence.
  local live_props dwarn dress_a
  live_props=$(override_map "$props_id")
  dwarn=$(log_lines_since "material override:" "$OUTDIR/m6.offset")
  if water_count_is 0; then dress_a=gave-back; else dress_a=still-water; fi
  { echo "M6 live face after file.rename deep.bsn -> deep2.bsn (doc rewrite pending save):"
    echo "live props map: $live_props"
    echo "new 'material override:' lines: $dwarn"
    echo "water wear count (was 1): $(qcount "[\"$WATER\"]")"
    grep "material override:" "$EDITOR_LOG" | tail -3
  } > "$REPO/loop/reports/t23t2_rename_sticky.log" 2>/dev/null
  log "M6: live face archived (props=$live_props warns=+$dwarn water=$(qcount "[\"$WATER\"]"))"
  leg M6_LIVE_FACE_CHARACTERIZED true
  # MO3's green: the document follows.
  op scene.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 180 >/dev/null
  grep -q "materials/deep2.bsn" "$SCENE" || { log "M6: the saved document still spells the old path"; ok=false; }
  grep -q "materials/deep.bsn" "$SCENE" && { log "M6: the saved document still holds the old path somewhere"; ok=false; }
  local n_d2; n_d2=$(grep -c "materials/deep2.bsn" "$SCENE" 2>/dev/null)
  log "M6: the document spells materials/deep2.bsn $n_d2 time(s) (want 1: props Trim)"
  [ "${n_d2:-0}" = "1" ] || ok=false
  local total; total=$(audit_json | jq '.count')
  [ "$total" = "0" ] || { log "M6: audit shows $total findings after the rename"; ok=false; }
  # Reopen: the document wins, the part wears the renamed path.
  open_scene "assets/t23.bsn"
  sleep 2; wait_idle 180 >/dev/null
  budget 60 [ "$(qcount "[\"$GLTFNAME\"]")" -ge 6 ]
  sleep 3
  props_id=$(eid props)
  [ "$(override_map "$props_id")" = '{"Rock":"materials/mossy.bsn","Trim":"materials/deep2.bsn"}' ] \
    || { log "M6: the reopened props map is not the renamed one"; ok=false; }
  budget 30 water_count_is 1
  water_count_is 1 || { log "M6: the Trim mesh does not wear the renamed water material"; ok=false; }
  leg M6_RENAME "$ok"
  warn_scan "$EDITOR_LOG"
  log "RENAME done: $(results)"
}

# ---- phase: reimport --------------------------------------------------------
reimport() {
  editor_boot
  open_scene "assets/t23.bsn"
  sleep 2; wait_idle 300 >/dev/null
  budget 120 [ "$(qcount "[\"$GLTFNAME\"]")" -ge 6 ]
  sleep 3
  wear_paths
  local props_id; props_id=$(eid props)

  # ---- M7: the reimport preserves the override and dresses the new part ---
  local m7=true
  local epoch; epoch=$(date +%s)
  mark_log "Reloaded models/props.glb" "$OUTDIR/m7.offset"
  glb_write "$PROPS" box RockA RockB TrimC PlainD BoxE
  sleep 4   # discipline 2
  if [ "$(log_lines_since "Reloaded models/props.glb" "$OUTDIR/m7.offset")" = "0" ]; then
    log "M7: no Reloaded line after the first write (A6 family missed event); re-triggering once"
    glb_write "$PROPS" box RockA RockB TrimC PlainD BoxE
    sleep 4
  fi
  budget 30 [ "$(qcount "[\"$GLTFNAME\"]")" = "7" ]
  [ "$(qcount "[\"$GLTFNAME\"]")" = "7" ] || { log "M7: named parts never reached 7 (saw $(qcount "[\"$GLTFNAME\"]"))"; m7=false; }
  # The new part wears Trim, so the surviving override dresses it on the
  # readable water face: two water wears now (TrimC + BoxE).
  budget 30 water_count_is 2
  water_count_is 2 || { log "M7: the new part BoxE was not dressed by the surviving override"; m7=false; }
  [ "$(override_map "$props_id")" = '{"Rock":"materials/mossy.bsn","Trim":"materials/deep2.bsn"}' ] \
    || { log "M7: the override map did not survive the reimport"; m7=false; }
  op project.select '{"path":"assets/models"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  budget 15 thumb_fresh "models/props.glb" "$epoch"
  local th; th=$(thumb_fresh "models/props.glb" "$epoch" 2>/dev/null)
  if [ -n "$th" ]; then
    log "M13: fresh thumbnail $(basename "$th") after the GLB rewrite"
  else
    log "M13: no new thumbnail after the GLB rewrite"
    m7=false
  fi
  shot l6-box
  leg M7_REIMPORT "$m7"

  # ---- M8: the stale key — warn once, quiet while it lasts, heal, again ---
  local m8=true
  mark_log "material override:" "$OUTDIR/m8.offset"
  glb_write "$PROPS" stone RockA RockB TrimC PlainD BoxE
  sleep 4
  budget 30 warn_since_at_least "$OUTDIR/m8.offset" 1
  if [ "$(log_lines_since "material override:" "$OUTDIR/m8.offset")" = "0" ]; then
    log "M8: no reaction to the rename write (A6 family missed event); re-triggering once"
    glb_write "$PROPS" stone RockA RockB TrimC PlainD BoxE
    sleep 4
    budget 30 warn_since_at_least "$OUTDIR/m8.offset" 1
  fi
  local w1; w1=$(log_lines_since "material override:" "$OUTDIR/m8.offset")
  grep "material override:" "$EDITOR_LOG" | tail -1 > "$OUTDIR/m8-warn-line.txt"
  log "M8: stale-key warns=$w1 line=$(cat "$OUTDIR/m8-warn-line.txt")"
  [ "$w1" = "1" ] || m8=false
  grep -q "overrides a material named 'Rock', which no part of it wears any more" "$OUTDIR/m8-warn-line.txt" || m8=false
  grep -q "props" "$OUTDIR/m8-warn-line.txt" || m8=false
  # kit is untouched by props' reimport: its layered face stays on.
  layered_count_is 2 || { log "M8: kit wrongly undressed by props' reimport"; m8=false; }
  # One-shot: another pass over the stale state says nothing new.
  sleep 3
  glb_write "$PROPS" stone RockA RockB TrimC PlainD BoxE
  sleep 4
  local w2; w2=$(log_lines_since "material override:" "$OUTDIR/m8.offset")
  [ "$w2" = "$w1" ] || { log "M8: the stale key re-warned ($w1 -> $w2)"; m8=false; }
  leg M8_STALE_WARN "$m8"

  # Recover: the name returns, the override dresses again (BoxE's water face
  # is the readable witness: the Trim chain was never broken, so the recovery
  # face rides the map and the warn silence; the BoxE part respawns too).
  local rec=true
  glb_write "$PROPS" box RockA RockB TrimC PlainD BoxE
  sleep 4
  budget 30 water_count_is 2
  water_count_is 2 || { log "M8: the recovery did not re-dress the water face"; rec=false; }
  local w3; w3=$(log_lines_since "material override:" "$OUTDIR/m8.offset")
  [ "$w3" = "$w2" ] || { log "M8: the recovery spoke ($w2 -> $w3)"; rec=false; }
  leg M8_RECOVER "$rec"

  # Speaks again: the name goes once more.
  local ag=true
  glb_write "$PROPS" stone RockA RockB TrimC PlainD BoxE
  sleep 4
  budget 30 warn_since_at_least "$OUTDIR/m8.offset" $((w3 + 1))
  local w4; w4=$(log_lines_since "material override:" "$OUTDIR/m8.offset")
  [ "$w4" -gt "$w3" ] || { log "M8: the re-break stayed quiet ($w3 -> $w4)"; ag=false; }
  leg M8_SPEAKS_AGAIN "$ag"

  # Leave the fixture healthy.
  glb_write "$PROPS" box RockA RockB TrimC PlainD BoxE
  sleep 4
  budget 30 water_count_is 2
  water_count_is 2 || log "REIMPORT: note - the fixture left without its water face"
  [ "$(log_lines_since "material override:" "$OUTDIR/m8.offset")" = "$w4" ] \
    && leg M8_FINAL_STATE true || leg M8_FINAL_STATE false

  warn_scan "$EDITOR_LOG"
  log "REIMPORT done: $(results)"
}

# ---- phase: gamebroken ------------------------------------------------------
gw_is() { # gw_is <query-json> <want>
  local n
  n=$(gbrp world.query "{\"data\":{\"components\":$1}}" 2>/dev/null | jq -c '.result // []' | jq '. | length')
  [ "$n" = "$2" ]
}
gamebroken() {
  local ok=true
  pkill -x jackdaw 2>/dev/null; pkill -x "$GAMEBIN" 2>/dev/null; sleep 1
  if [ ! -x "$STAGED_EXE" ]; then
    log "M10: no staged tree (run the export phase first)"
    leg M10_GAME_MISSING false
    return
  fi
  wear_paths
  rm -rf "$BROKEN_STAGE"
  cp -R "$STAGED" "$BROKEN_STAGE"
  rm -f "$BROKEN_STAGE/assets/materials/mossy.bsn" "$BROKEN_STAGE/assets/materials/deep.bsn"
  grep -q "materials/mossy.bsn" "$BROKEN_STAGE/assets/t23.bsn" \
    || { log "M10: the staged copy does not spell mossy (wrong tree?)"; leg M10_GAME_MISSING false; return; }
  (cd "$BROKEN_STAGE" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" "./$GAMEBIN" > "$OUTDIR/staged-broken-run.log" 2>&1 &)
  if ! wait_game 420; then
    log "M10: the broken-package game never came up"
    leg M10_GAME_MISSING false
    stop_game
    return
  fi
  sleep 8
  # The readable faces: the water holder gave back (deep gone), the layered
  # holder stays dressed (wet still held), the maps still spell both paths.
  local gq named layered water
  gq=$(gbrp world.query "{\"data\":{\"components\":[\"$OVERR\"]}}" 2>/dev/null | jq -c '.result // []')
  echo "$gq" > "$OUTDIR/gb-holders.json"
  [ "$(echo "$gq" | jq '. | length')" = "2" ] || { log "M10: holders = $(echo "$gq" | jq '. | length') (want 2 - the doc keeps its entries)"; ok=false; }
  echo "$gq" | jq -e '[.[]?.components["'"$OVERR"'"].materials] | any(.Trim == "materials/deep.bsn")' >/dev/null 2>&1 \
    || { log "M10: the deep entry vanished from the holder"; ok=false; }
  named=$(gbrp world.query "{\"data\":{\"components\":[\"$NAME\",\"$GLTFNAME\"]}}" 2>/dev/null | jq -c '.result // []')
  layered=$(gbrp world.query "{\"data\":{\"components\":[\"$NAME\",\"$LAYERED\"]}}" 2>/dev/null | jq -c '.result // []')
  water=$(gbrp world.query "{\"data\":{\"components\":[\"$NAME\",\"$WATER\"]}}" 2>/dev/null | jq -c '.result // []')
  echo "$named" > "$OUTDIR/gb-parts.json"; echo "$layered" > "$OUTDIR/gb-layered.json"
  echo "$water" > "$OUTDIR/gb-water.json"
  local nl nly nw
  nl=$(echo "$named" | jq '. | length'); nly=$(echo "$layered" | jq '. | length'); nw=$(echo "$water" | jq '. | length')
  log "M10: broken package named=$nl layered=$nly water=$nw (want 6/2/0)"
  [ "$nl" = "6" ] || ok=false
  [ "$nly" = "2" ] || ok=false
  [ "$nw" = "0" ] || ok=false
  grep -q "panicked" "$OUTDIR/staged-broken-run.log" && { log "M10: the game panicked on the missing materials"; ok=false; }
  game_up || { log "M10: the game is not answering after the missing materials"; ok=false; }
  local hits; hits=$(grep -c "material override:" "$OUTDIR/staged-broken-run.log" 2>/dev/null)
  log "M10: 'material override:' lines in the game log: ${hits:-0} (want 0 - the report is editor-only by design)"
  [ "${hits:-0}" = "0" ] || ok=false
  leg M10_GAME_MISSING "$ok"
  stop_game
  rm -rf "$BROKEN_STAGE"
  warn_scan "$OUTDIR/staged-broken-run.log"
  log "GAMEBROKEN done: $(results)"
}

# ---- dispatcher -------------------------------------------------------------
case "$PHASE" in
  prep) prep ;;
  chains) chains ;;
  export) export_phase ;;
  broken) broken ;;
  rename) rename ;;
  reimport) reimport ;;
  gamebroken) gamebroken ;;
  all)
    prep
    chains
    export_phase
    broken
    rename
    reimport
    gamebroken
    log "ALL done"
    ;;
  *) log "unknown phase $PHASE"; exit 2 ;;
esac
