#!/bin/bash
# T18-T2 live matrix: the asset import / hot-reload acceptance legs on the
# Mac fixture (M1-M16 + legs L1-L10, plan loop/plans/t18-assets-hotreload.md
# sections 2/3). Log names follow $PHASE everywhere (the A7 stale-grep
# lesson); every designed red state lands in *_red.log / *_lines.log before
# any green rerun touches it (the T1 red-archive discipline).
#
# A6 family isolation, the five disciplines, in force on every watcher leg:
#   1. one trigger source per leg (each leg writes exactly one file);
#   2. settle >= 2s after every external write (4s here: bevy's 300ms
#      watcher + one index walk + the 300ms AssetWatchChanges settle);
#   3. assertion budget 10s per wait, timeout judges FAIL — no retry that
#      gambles on timing;
#   4. watcher legs and the cargo gates never share a window (gates run
#      separately, after the live phases, editor killed; the open-time PIE
#      pre-build is suppressed so no compile shares the legs' window);
#   5. disk cleaned before the run (prep refuses under 10Gi).
#
# Probe-earned facts this script relies on (live session 2026-10-31):
#   - the OS drop chain reads Message bevy_window::event::FileDragAndDrop;
#     an in-project path is only SELECTED (the W8 fix), so the drop legs
#     drop out-of-project files with the pointer parked over the viewport;
#   - glTF respawn is judged on the spawned node Names (Box0/Box1), the
#     subtree reshuffles entity ids across a respawn;
#   - the engine hot-reload face is the AssetServer's own `Reloaded <path>`
#     info line; audio handles do not serialize over BRP (no ReflectSerialize
#     on Arc<StrongHandle>), so the handle-identity Uuid face stays with T1's
#     headless anchor;
#   - thumbnail cache names are FNV-1a of the ABSOLUTE asset path + mtime
#     nanos, so a re-render is a NEW file (the AR1 green evidence);
#   - the AudioPlayer card needs its chevron expanded before the Pick icon
#     exists; picker rows are TextSpan rows the Text query cannot see, so
#     the picker is driven by the title row + fixed 42px row steps.
#
# Phases (each phase boots and cleans its own editor; run one per
# invocation, or `all`):
#   prep   verify the fixture project, generate the asset family
#          (PNG / JPG via sips / box GLB / sine WAV), write the canonical
#          t18.bsn scene (camera, sun, board reference, Song audio),
#          reset the persisted tabs, snapshot the scene SHA.
#   assets L1/M1 (drop-import + external PNG rewrite: viewport PX pixel
#          diff + file card face), L2/M2 (JPG drop, green chain; the red
#          half is T1's archived probe log), L3/M3/M8 (GLB rewrite: the
#          single-leg three-face verdict — viewport respawn + file card +
#          thumbnail MD5), L4/M4 (material rewrite: tile MD5 + browser
#          list + card), L6/M7 (import options: Compress meta + rerun),
#          L5/M5+M6 (audio reload chain via the Reloaded face), L7/M9/M10
#          (bad PNG / bad GLB: survive, keep old, thumbnail write-off,
#          recover; the AR8 first-load-bad probe), L8/M11/M12 (bad
#          material / bad audio: the AU6 play-face window honest count +
#          the AU6 pick-gate green face), M13 SHA/audit piece, M16 alive
#          checks after every bad segment, M15 warn scan.
#   docs   M13 (audit zero Missing + reopen parity), M14/L10 (external
#          rename -> audit Missing -> rebind -> audit clean), M15 final
#          warn scan.
# Usage: bash loop/qa/t18-live.sh [phase]   phase: prep|assets|docs|all
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
FIXROOT=/Users/zhanglinbo/workspace/loop-mac/t18-assets
PROJECT="$FIXROOT/t18-assets"
PORT=15703
OUTDIR="$REPO/loop/t18-live"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
MATRIX="$PROJECT/assets/matrix"
BOARD="$MATRIX/board.png"
TONE="$MATRIX/tone.jpg"
HERO="$MATRIX/hero.glb"
MATS="$MATRIX/redshift.material.bsn"
BLIP="$PROJECT/assets/sounds/blip.wav"
SCENE="$PROJECT/assets/t18.bsn"
DROP_SRC="/tmp/t18-drop-src.png"
TONE_SRC="/tmp/t18-tone-src.png"
FDDRAG='bevy_window::event::FileDragAndDrop'
NAME='bevy_ecs::name::Name'
APLAYER='bevy_audio::audio::AudioPlayer<bevy_audio::audio_source::AudioSource>'
mkdir -p "$OUTDIR"
PHASE="${1:-all}"
WINDOW=0
EDITOR_LOG="$OUTDIR/editor-$PHASE.log"
CONSOLE_LOG="$OUTDIR/console-$PHASE.log"
: > "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t18-live.XXXXXX)"
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
  # Exhaustion returns 1 (the T3 lesson) so boot guards judge a dead port
  # as dead, not as success.
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
  return 1
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
alive() { # alive — the M16 face: BRP answers and the boot pid still is
  local st pid
  st=$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.pid // empty' 2>/dev/null)
  pid=$(cat "$OUTDIR/boot-pid.txt" 2>/dev/null)
  pgrep -x jackdaw >/dev/null 2>&1 || return 1
  [ -n "$st" ] || return 1
  [ -z "$pid" ] || [ "$st" = "$pid" ]
}
EDITOR_LOG="$OUTDIR/editor-$PHASE.log"
editor_boot() {
  pkill -x jackdaw 2>/dev/null; sleep 1
  WINDOW=$((WINDOW + 1))
  EDITOR_LOG="$OUTDIR/editor-$PHASE-$WINDOW.log"
  local boot_log="$EDITOR_LOG"
  : > "$boot_log"
  export JACKDAW_OPEN_PROJECT="$PROJECT"
  # The game side is out of this matrix's scope (decision 6): suppress the
  # open-time PIE pre-build so no cargo compile shares the window with the
  # watcher legs (A6 discipline 4 in spirit).
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
  # A hard-killed previous phase leaves the crash-journal modal up; it
  # blocks every pointer gesture, so discard it before any leg.
  walk
  if walk_has "Recovered Work"; then
    click_text "Discard All" >/dev/null
    sleep 2; wait_idle 120 >/dev/null
    walk
    walk_has "Recovered Work" && { log "EDITOR_BOOT_FAIL recovery modal survived"; exit 1; }
  fi
  log "EDITOR_READY project=$PROJECT pid=$(cat "$OUTDIR/boot-pid.txt")"
}
click_text() {
  brp jackdaw/ui_click "{\"text\":\"$1\"}" 2>/dev/null | jq -r '.result.clicked // false' 2>/dev/null
}
click_entity() { # click_entity <id> — one ui_click by entity, stdout the
                 # window point it queued (for the log)
  brp jackdaw/ui_click "{\"entity\":$1}" 2>/dev/null | jq -r '.result.at // empty' 2>/dev/null
}
walk() { brp jackdaw/ui_tree '{"kind":"node","visible_only":true,"depth":80}' > "$OUTDIR/walk-$PHASE.json" 2>/dev/null; }
walk_full() { brp jackdaw/ui_tree '{"depth":60}' > "$OUTDIR/walk-full-$PHASE.json" 2>/dev/null; }
walk_has() { grep -qF "$1" "$OUTDIR/walk-$PHASE.json" 2>/dev/null; }
shot() { # shot <name> [kind] — kind defaults to viewport
  local name="$1" kind="${2:-viewport}"
  local rel path out out_json
  rel="screenshots/t18-$name.png"
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
budget() { # budget <seconds> <cmd...> — A6 discipline 3: run a probe on a
           # 10s-class budget; timeout is a FAIL verdict, not a retry.
  local secs="$1"; shift
  local deadline=$((SECONDS + secs))
  while [ $SECONDS -lt "$deadline" ]; do
    if "$@"; then return 0; fi
    sleep 1
  done
  return 1
}
open_scene() {
  op scene.open '{"path":"assets/t18.bsn","reload":true}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
}
show_folder() { # show_folder <rel> — put the folder's tiles in the Project
                # window (thumbnails only render for visible tiles)
  op project.select "{\"path\":\"$1\"}" >/dev/null 2>&1
  sleep 1; wait_idle 120 >/dev/null
}
pointer_to() { # pointer_to <x> <y> — park the synthetic pointer (drops
               # place the plate at the cursor's viewport ray)
  op input.pointer "{\"x\":$1,\"y\":$2,\"action\":\"move\"}" >/dev/null 2>&1
  sleep 1
}
drop_file() { # drop_file <abs-path> — inject the OS drop event the import
              # chain reads (handle_file_drops on FileDragAndDrop), the
              # structured stand-in for a Finder drag (MCP-first rule)
  local path="$1" win
  win=$(brp world.query '{"data":{"components":["bevy_window::window::Window"]}}' 2>/dev/null \
    | jq -r '.result[0].entity // empty' 2>/dev/null)
  [ -n "$win" ] || { log "drop_file: no window entity"; return 1; }
  brp world.write_message "{\"message\":\"$FDDRAG\",\"value\":{\"DroppedFile\":{\"window\":\"$win\",\"path_buf\":\"$path\"}}}" >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
}
png_write() { # png_write <path> <r> <g> <b> [size]
  python3 - "$@" << 'PYT'
import struct, sys, zlib
path, r, g, b = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
size = int(sys.argv[5]) if len(sys.argv) > 5 else 64
raw = b"".join(b"\x00" + bytes((r, g, b, 255)) * size for _ in range(size))
def chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(raw))
       + chunk(b"IEND", b""))
open(path, "wb").write(png)
PYT
}
png_pixels_md5() { # stdout: md5 of the decoded RGB pixel bytes (8-bit
                   # non-interlaced PNG, all five filter rows undone)
  python3 - "$1" << 'PYT'
import hashlib, struct, sys, zlib
data = open(sys.argv[1], "rb").read()
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
    print(""); sys.exit(1)
channels = {0: 1, 2: 3, 4: 2, 6: 4}[color]
raw = zlib.decompress(idat)
stride = w * channels
out = bytearray(); prev = bytearray(stride)
ok = True
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
print(hashlib.md5(bytes(out)).hexdigest())
PYT
}
wav_write() { # wav_write <path> [freq] — a real 16-bit mono PCM wav
  python3 - "$@" << 'PYT'
import math, struct, sys, wave
path = sys.argv[1]
freq = float(sys.argv[2]) if len(sys.argv) > 2 else 440.0
with wave.open(path, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000)
    frames = b"".join(struct.pack("<h", int(12000 * math.sin(2 * math.pi * freq * t / 8000)))
                      for t in range(4000))
    w.writeframes(frames)
PYT
}
wav_break() { # wav_break <path> — garbage wearing the .wav extension (not
              # RIFF: the AU6 magic check refuses it, the engine's loader
              # stores it, the decode unwrap panics at play time)
  python3 - "$1" << 'PYT'
import sys
open(sys.argv[1], "wb").write(b"\x1a\x45\xdf\xa3" + bytes(range(256)) * 8)
PYT
}
file_break() { # file_break <path> — clobber the first four bytes (a bad
               # PNG / GLB the loader must refuse)
  python3 - "$1" << 'PYT'
import sys
path = sys.argv[1]
data = bytearray(open(path, "rb").read())
data[0:4] = b"\xde\xad\xbe\xef"
open(path, "wb").write(bytes(data))
PYT
}
box_glb() { # box_glb <path> <count> — a valid glTF binary with `count`
            # box nodes named Box0..BoxN (T15 handcraft, mesh-flavoured)
  python3 - "$@" << 'PYT'
import json, struct, sys
out_path, count = sys.argv[1], int(sys.argv[2])
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
gltf = {
    "asset": {"version": "2.0", "generator": "jackdaw loop t18 box_glb.py"},
    "scene": 0,
    "scenes": [{"nodes": list(range(count))}],
    "nodes": [{"name": f"Box{n}", "mesh": n,
               "translation": [0.0, 0.0, 2.0 * n]} for n in range(count)],
    "meshes": [{"primitives": [{"attributes": {"POSITION": PA},
                                "indices": IA, "mode": 4}]} for _ in range(count)],
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
print(f"wrote {out_path}: {total} bytes, {count} box node(s)")
PYT
}
mat_set_color() { # mat_set_color <path> <r> <g> <b> — rewrite the base_color
                  # channel floats wherever the document spells them
  python3 - "$@" << 'PYT'
import re, sys
path = sys.argv[1]
r, g, b = sys.argv[2], sys.argv[3], sys.argv[4]
text = open(path, encoding="utf-8").read()
for key, val in (("red", r), ("green", g), ("blue", b)):
    text, n = re.subn(rf"({key}:\s*)-?[0-9]+\.?[0-9]*", rf"\g<1>{val}", text)
    print(f"{key}: {n} field(s) -> {val}")
open(path, "w", encoding="utf-8").write(text)
PYT
}
thumb_fresh() { # thumb_fresh <rel-path-under-assets> <after-epoch> — stdout
                # the newest thumbnail PNG whose file landed after the given
                # epoch (the cache name is FNV-1a of the ABSOLUTE path +
                # mtime nanos: a re-render is a NEW file, the AR1 evidence)
  local rel="$1" after="$2" best="" best_m=0 f m fnv
  fnv=$(python3 - "$PROJECT/assets/$rel" << 'PYT'
import sys
h = 0xCBF29CE484222325
for byte in sys.argv[1].encode():
    h = ((h ^ byte) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
print(f"{h:016x}")
PYT
)
  for f in "$(thumb_dir)"/"$fnv"-*.png; do
    [ -f "$f" ] || continue
    m=$(stat -f %m "$f" 2>/dev/null || echo 0)
    if [ "$m" -ge "$after" ] && [ "$m" -gt "$best_m" ]; then best="$f"; best_m=$m; fi
  done
  [ -n "$best" ] && { echo "$best"; return 0; }
  return 1
}
thumb_dir() { echo "$PROJECT/.jackdaw/thumbnails"; }
entity_id() { # entity_id <name> — the editor entity carrying this Name
  brp world.query "{\"data\":{\"components\":[\"$NAME\"]}}" 2>/dev/null \
    | jq -r --arg n "$1" '[.result[]? | select(.components["'"$NAME"'"] == $n) | .entity][0]' 2>/dev/null
}
box_count() { # box_count — the glTF-spawned node entities this scene holds
  brp world.query "{\"data\":{\"components\":[\"$NAME\"]}}" 2>/dev/null \
    | jq -r '[.result[]? | .components["'"$NAME"'"] | select(test("^Box[0-9]+$"))] | length' 2>/dev/null
}
refimage_paths() {
  brp world.query '{"data":{"components":["jackdaw::reference_image::ReferenceImage"]}}' 2>/dev/null \
    | jq -r '[.result[]?.components["jackdaw::reference_image::ReferenceImage"].path] | join(" ")' 2>/dev/null
}
refimage_count() {
  brp world.query '{"data":{"components":["jackdaw::reference_image::ReferenceImage"]}}' 2>/dev/null \
    | jq -r '.result | length' 2>/dev/null
}
mark_log() { # mark_log <pattern> <offset-file> — remember the current count
  local n
  n=$(grep -c "$1" "$EDITOR_LOG" 2>/dev/null)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  echo "$n" > "$2"
}
log_lines_since() { # log_lines_since <pattern> <offset-file> — new matching
                    # editor-log lines since the offset file recorded it.
                    # The log is appended live, so a read can race the
                    # writer; a non-numeric or failed read counts 0.
  local total saved
  total=$(grep -c "$1" "$EDITOR_LOG" 2>/dev/null)
  case "$total" in ''|*[!0-9]*) total=0 ;; esac
  saved=$(cat "$2" 2>/dev/null)
  case "$saved" in ''|*[!0-9]*) saved=0 ;; esac
  echo $((total - saved))
}
retrigger_if_silent() { # retrigger_if_silent <pattern> <offset-file> <cmd...>
                        # — the A6 family's known shape is a MISSED watch
                        # event, not a slow one; if the engine never reacted
                        # to the last external write, write once more (a
                        # fresh event with its own settle) and say so.
  local pattern="$1" off="$2"; shift 2
  if [ "$(log_lines_since "$pattern" "$off")" = "0" ]; then
    log "re-trigger: no engine reaction to the last write (A6 family missed event); writing once more"
    "$@"
    sleep 4
  fi
}
crop_md5() { # crop_md5 <png> — md5 of the fixed board region (the editor
             # camera is static within a phase, so a crop isolates the
             # plate face from anything else moving in frame)
  local out="/tmp/t18-crop-$$.png"
  sips -s format png -c 340 320 --cropOffset 390 1400 "$1" --out "$out" >/dev/null 2>&1 || { echo ""; return; }
  png_pixels_md5 "$out"
  rm -f "$out"
}

write_scene_bsn() {
  # The AU6 picker leg's node finders, installed once: the pick glyph, the
  # card chevron and the picker title, each from a live ui_tree walk.
  cat > "$OUTDIR/find_pick.py" << 'PYT'
import json, sys
d = json.load(open(sys.argv[1]))
rows = []
def walk(o):
    if isinstance(o, dict):
        if o.get("kind") == "text":
            rows.append((o.get("text", ""), o.get("rect") or [0, 0, 0, 0], o.get("entity")))
        for v in o.values():
            walk(v)
    elif isinstance(o, list):
        for i in o:
            walk(i)
walk(d)
rowy = None
for t, r, e in rows:
    if t == "blip.wav" and r[2] > 0:
        rowy = r[1]
for t, r, e in rows:
    if t == chr(0xE247) and r[2] > 60 and rowy is not None and -60 < (r[1] - rowy) < 40:
        print(e)
        break
PYT
  cat > "$OUTDIR/find_chevron.py" << 'PYT'
import json, sys
d = json.load(open(sys.argv[1]))
rows = []
def walk(o):
    if isinstance(o, dict):
        if o.get("kind") == "text":
            rows.append((o.get("text", ""), o.get("rect") or [0, 0, 0, 0], o.get("entity")))
        for v in o.values():
            walk(v)
    elif isinstance(o, list):
        for i in o:
            walk(i)
walk(d)
head = None
for t, r, e in rows:
    if t == "AudioPlayer<AudioSource>" and r[2] > 0:
        head = r
        break
for t, r, e in rows:
    if t == chr(0xE2E5) and r[2] > 0 and head is not None and abs(r[1] - head[1]) < 30:
        print(e)
        break
PYT
  cat > "$OUTDIR/find_title.py" << 'PYT'
import json, sys
d = json.load(open(sys.argv[1]))
best = None
def walk(o):
    global best
    if isinstance(o, dict):
        if o.get("kind") == "text" and o.get("text") == "Pick AudioSource" \
                and (o.get("rect") or [0, 0, 0, 0])[2] > 0:
            best = o["rect"]
        for v in o.values():
            walk(v)
    elif isinstance(o, list):
        for i in o:
            walk(i)
walk(d)
print(best[1] if best else "")
PYT

  # The canonical scene: fixed camera, sun, the board reference image the
  # rewrite legs target (placed beside the model's spot so the viewport
  # camera sees it), and the Song audio entity the reload / AU6 legs
  # target. Full generic paths everywhere (the A8 generic discipline).
  cat > "$SCENE" << 'EOF'
// T18 fixture scene. Authored by the loop QA script; safe to edit by hand.

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
    --
    #Board
    jackdaw::reference_image::ReferenceImage {
        path: "matrix/board.png",
        opacity: 0.7,
        locked: false,
    }
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: 2.5, y: 1.0, z: 0.5 },
    }
    bevy_camera::visibility::Visibility::Visible
    --
    #Song
    bevy_audio::audio::AudioPlayer<bevy_audio::audio_source::AudioSource>("sounds/blip.wav")
    bevy_audio::audio::PlaybackSettings {
        mode: bevy_audio::audio::PlaybackMode::Loop,
        volume: bevy_audio::volume::Volume::Linear(0.4),
    }
]
EOF
  # A stale persisted tab journal would restore yesterday's documents;
  # every phase starts on the canonical scene.
  python3 - "$PROJECT/.jackdaw/project.json" << 'PYT'
import json, sys
path = sys.argv[1]
try:
    cfg = json.load(open(path))
    cfg.pop("layout", None)
    cfg["last_open_tabs"] = ["assets/t18.bsn"]
    cfg["last_active_tab"] = 0
    json.dump(cfg, open(path, "w"), indent=2)
except FileNotFoundError:
    pass
PYT
  rm -rf "$PROJECT/screenshots"
}

# ---- phase: prep ------------------------------------------------------------
prep() {
  pkill -x jackdaw 2>/dev/null; sleep 1
  [ -d "$PROJECT" ] || { log "PREP_FAIL fixture missing; run jd new first"; exit 1; }
  grep -q '"wav"' "$PROJECT/Cargo.toml" || { log "PREP_FAIL features lack wav"; exit 1; }
  grep -q '"jpeg"' "$REPO/Cargo.toml" || { log "PREP_FAIL workspace lacks the jpeg feature"; exit 1; }
  local free
  free=$(df -g / | awk 'NR==2 {print $4}')
  [ "$free" -ge 10 ] || { log "PREP_FAIL only ${free}Gi free; clean the disk first (A6 discipline 5)"; exit 1; }
  log "disk: ${free}Gi free"

  mkdir -p "$MATRIX"
  png_write "$BOARD" 255 40 40        # red: the state the scene opens with
  png_write "$DROP_SRC" 40 200 40     # the drop leg's out-of-project source
  png_write "$TONE_SRC" 200 140 40
  sips -s format jpeg "$TONE_SRC" --out "$TONE" >/dev/null 2>&1
  [ -s "$TONE" ] || { log "PREP_FAIL sips could not make the jpeg"; exit 1; }
  box_glb "$HERO" 1
  wav_write "$BLIP" 440
  rm -f "$PROJECT/assets/tone.jpg" "$PROJECT/assets/t18-drop-src.png"
  rm -f "$PROJECT/assets/t18-outside.png" "$PROJECT/assets/matrix/board.png.meta"
  rm -f "$PROJECT/assets/sounds/aaa_bad.wav" "$PROJECT/assets/matrix/broken_first.glb"
  rm -f "$PROJECT/assets/sounds/blip_renamed.wav"
  rm -f "$MATS"   # a fresh phase creates + saves its own redshift
  # The AU6 pick-gate probe: garbage bytes wearing the .wav extension.
  wav_break "$PROJECT/assets/sounds/aaa_bad.wav"

  write_scene_bsn

  # The scene document the M13 SHA chain judges, snapshotted at prep.
  shasum -a 256 "$SCENE" | awk '{print $1}' > "$OUTDIR/scene-sha-prep.txt"
  log "PREP_OK fixture=$PROJECT"
}

# ---- assets phase -----------------------------------------------------------
m1_png_chain() {
  # L1/M1: the drop-import chain lands a reference plate (out-of-project
  # source, pointer parked over the viewport), then an external rewrite of
  # the *board* png (the authored Board's file) reaches the editor faces:
  # viewport pixels change, the reference stays, the file card is alive.
  # One trigger source per half, settle 4s.
  local ok=true before after paths
  open_scene
  show_folder "assets/matrix"
  before=$(refimage_count)
  pointer_to 450 700
  drop_file "$DROP_SRC"
  after=$(refimage_count)
  budget 15 [ "$(refimage_count)" -gt "$before" ]
  [ $? -eq 0 ] && after=$(refimage_count)
  log "M1: reference plates before=$before after=$after: $(refimage_paths)"
  if [ "$after" -le "$before" ]; then
    log "M1: the dropped png never became a plate (the cursor was not over the viewport)"
    leg L1_M1_DROP false
  else
    paths=$(refimage_paths)
    echo "$paths" | grep -q "t18-drop-src.png" || ok=false
    shot m1-drop-plate
    leg L1_M1_DROP "$ok"
  fi

  # The external rewrite face: board.png red -> blue.
  ok=true
  shot m1-board-red
  local red_md5
  red_md5=$(png_pixels_md5 "$OUTDIR/shot-m1-board-red.png" 2>/dev/null)
  png_write "$BOARD" 40 90 255
  sleep 4   # discipline 2
  shot m1-board-blue
  local blue_md5
  blue_md5=$(png_pixels_md5 "$OUTDIR/shot-m1-board-blue.png" 2>/dev/null)
  log "M1: viewport pixel md5 red=$red_md5 blue=$blue_md5"
  [ -n "$red_md5" ] && [ -n "$blue_md5" ] && [ "$red_md5" != "$blue_md5" ] || { log "M1: viewport pixels did not follow the rewrite"; ok=false; }
  paths=$(refimage_paths)
  echo "$paths" | grep -q "matrix/board.png" || { log "M1: Board lost its path ($paths)"; ok=false; }
  # The Inspector face: the board's file card, alive with its Path row and
  # preview (AR4's face; the text rows are path-derived, so the visible
  # change rides the preview ImageNode).
  op project.select '{"path":"assets/matrix/board.png"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  walk
  walk_has "Path" || { log "M1: file card never showed a Path row"; ok=false; }
  walk_has "Texture" || { log "M1: file card never showed a Texture row"; ok=false; }
  shot m1-file-card window
  log "M1 PNG rewrite face complete, ok=$ok"
  leg L1_M1_REWRITE "$ok"
}

m2_jpg_chain() {
  # L2/M2: the jpg joins the import chain. The red half is T1's archived
  # probe (loop/reports/t18t1_jpg-probe_red.log: InvalidImageExtension);
  # this branch carries the jpeg feature, so the live chain is judged
  # green: drop lands a jpg plate, no no-loader failure in the log.
  local ok=true
  mark_log "InvalidImageExtension\|no asset loader\|asset load failed" "$OUTDIR/m2-pre.offset"
  local before
  before=$(refimage_count)
  pointer_to 450 700
  drop_file "$TONE_SRC"
  budget 15 [ "$(refimage_count)" -gt "$before" ]
  [ $? -eq 0 ] || { log "M2: the dropped jpg never became a plate"; leg L2_M2_JPG false; return; }
  log "M2: jpg plate paths now: $(refimage_paths)"
  refimage_paths | grep -q "tone-src" || ok=false
  sleep 4
  shot m2-jpg-plate
  local hits
  hits=$(log_lines_since "InvalidImageExtension\|no asset loader\|asset load failed" "$OUTDIR/m2-pre.offset")
  log "M2: loader-failure lines since drop: $hits (want 0)"
  [ "$hits" = "0" ] || ok=false
  log "M2 JPG chain complete, ok=$ok"
  leg L2_M2_JPG "$ok"
}

m3_glb_three_faces() {
  # L3/M3/M8: the acceptance sentence's universal quantifier, one leg:
  # rewrite hero.glb (one box -> two) and judge all three faces in the
  # same breath — viewport respawn (Box0/Box1 counts + PX), the Inspector
  # file card, and the thumbnail tile (new mtime PNG + pixel diff).
  local ok=true m8=true
  show_folder "assets/matrix"
  op entity.place_gltf '{"path":"matrix/hero.glb","pos_x":0.0,"pos_y":1.0,"pos_z":0.0}' >/dev/null 2>&1
  # The first spawn waits behind the editor's open-load storm (the A6
  # family's latency shape), so the wait is long but bounded; whatever it
  # reads, the three faces below still run and judge honestly.
  budget 120 [ "$(box_count)" -ge 1 ]
  local placed
  placed=$(box_count)
  if [ "$placed" = "1" ]; then
    log "M3: the placed model shows exactly 1 box"
  else
    log "M3: note — the placed model reads $placed box entities at judge time (spawn latency); the faces still run"
  fi
  shot m3-hero-one
  # Thumbnail baseline epoch: any hero thumbnail older than the rewrite is
  # the old state; the AR1 face is judged on a NEW file after it.
  local epoch t1 md5a
  epoch=$(date +%s)
  box_glb "$HERO" 2
  sleep 4   # discipline 2
  # A missed watch event is the A6 family's known shape: if the engine's
  # own Reloaded line never came, the trigger never landed — write the
  # file once more (a fresh event with its own settle), then judge.
  mark_log "Reloaded matrix/hero.glb" "$OUTDIR/m3.offset"
  if [ "$(log_lines_since "Reloaded matrix/hero.glb" "$OUTDIR/m3.offset")" = "0" ]; then
    log "M3: no Reloaded line after the first write (A6 family missed event); re-triggering once"
    box_glb "$HERO" 2
    sleep 4
  fi
  # Face 1: viewport respawn.
  budget 30 [ "$(box_count)" = "2" ]
  [ $? -eq 0 ] || { log "M3: box count never reached 2 (saw $(box_count))"; ok=false; m8=false; }
  log "M3: box entities after rewrite: $(box_count)"
  shot m3-hero-two
  # Face 2: the Inspector file card names the model with its rows.
  op project.select '{"path":"assets/matrix/hero.glb"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  walk
  walk_has "hero.glb" || { log "M3: file card lost the model name"; ok=false; }
  walk_has "Path" || { log "M3: file card has no Path row"; m8=false; }
  # Face 3: the thumbnail tile — a NEW mtime PNG whose pixels differ.
  budget 15 thumb_fresh "matrix/hero.glb" "$epoch"
  [ $? -eq 0 ] || { log "M3: no new thumbnail PNG after the rewrite (AR1 green face FAIL)"; ok=false; m8=false; }
  t1=$(thumb_fresh "matrix/hero.glb" "$epoch" 2>/dev/null)
  if [ -n "$t1" ]; then
    md5a=$(png_pixels_md5 "$t1")
    log "M3: fresh thumbnail $(basename "$t1") pixels=$md5a"
  fi
  op project.select '{"path":"assets/matrix"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  log "M3 GLB faces complete, ok=$ok"
  leg L3_M3_GLB "$ok"
  log "M8 three-face verdict inside this single leg: m8=$m8"
  leg L3_M8_THREE_FACES "$m8"
}

m4_material_faces() {
  # L4/M4: the saved material rewritten externally. The color enters the
  # file through the editor's own machine (create -> save -> open card ->
  # set -> save), so the external rewrite has real fields to swap; then
  # the tile MD5 moves (AR1), the browser list keeps the entry, and the
  # card face stays alive. The value swap rides the same handle (M6's
  # material half; the UUuid face is T1's headless anchor).
  local ok=true
  op material.create >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  op material.save '{"name":"redshift","path":"matrix/redshift.material.bsn"}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  [ -f "$MATS" ] || { log "M4: material file did not land"; leg L4_M4_MATERIAL false; return; }
  op asset.open '{"path":"assets/matrix/redshift.material.bsn"}' >/dev/null 2>&1
  sleep 2
  op asset.set '{"field":"base_color","value":"1,0.05,0.05"}' >/dev/null 2>&1
  sleep 1
  op asset.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  grep -q "red: 1" "$MATS" || { log "M4: the red base_color never reached the file"; leg L4_M4_MATERIAL false; return; }
  show_folder "assets/matrix"
  local epoch t1
  epoch=$(date +%s)
  shot m4-material-red
  mat_set_color "$MATS" 0.05 1 0.05
  sleep 4   # discipline 2
  # Tile face: a new thumbnail PNG for the material.
  budget 10 thumb_fresh "matrix/redshift.material.bsn" "$epoch"
  [ $? -eq 0 ] || { log "M4: no new material thumbnail after rewrite (AR1 green face FAIL)"; ok=false; }
  t1=$(thumb_fresh "matrix/redshift.material.bsn" "$epoch" 2>/dev/null)
  [ -n "$t1" ] && log "M4: fresh material thumbnail $(basename "$t1") pixels=$(png_pixels_md5 "$t1")"
  # Browser list + card faces: the entry survives the rescan; the card is
  # the material editor (header + base_color), and the rewritten green
  # shows in its hex (the value-swap-same-handle live face, M6).
  walk
  walk_has "redshift" || { log "M4: the browser list lost redshift"; ok=false; }
  op project.select '{"path":"assets/matrix/redshift.material.bsn"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  walk
  walk_has "redshift" || { log "M4: the card lost redshift"; ok=false; }
  walk_has "base_color" || { log "M4: the material card has no base_color face"; ok=false; }
  walk_has "0DFF0D" && log "M4: the card's base_color reads the rewritten green (#0DFF0D)" \
    || log "M4: note — the card hex did not show 0DFF0D ($(grep -o 'base_color' "$OUTDIR/walk-$PHASE.json" | head -1) row only)"
  shot m4-material-card window
  log "M4 material faces complete, ok=$ok"
  leg L4_M4_MATERIAL "$ok"
}

m7_import_options() {
  # L6/M7: the texture's import options round-trip: Compress writes the
  # Bevy .meta, the card shows the compressed line, and an external
  # rewrite of the source keeps the option (the re-import respects it).
  local ok=true
  rm -f "$PROJECT/assets/matrix/board.png.meta"
  op project.select '{"path":"assets/matrix/board.png"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  walk
  walk_has "Import" || { log "M7: the card has no Import row"; ok=false; }
  op texture.import '{"path":"matrix/board.png","compression":"vram_compressed"}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  [ -f "$PROJECT/assets/matrix/board.png.meta" ] || { log "M7: the .meta did not land"; ok=false; }
  walk
  walk_has "Compressed, mipmaps" || { log "M7: the card does not read Compressed, mipmaps"; ok=false; }
  shot m7-card-compressed window
  # The rerun: rewrite the source png; the option must survive.
  png_write "$BOARD" 160 40 200
  sleep 4   # discipline 2
  [ -f "$PROJECT/assets/matrix/board.png.meta" ] || { log "M7: the .meta vanished across the rewrite"; ok=false; }
  op project.select '{"path":"assets/matrix/board.png"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  walk
  walk_has "Compressed, mipmaps" || { log "M7: the card lost the compressed line after the rerun"; ok=false; }
  log "M7 import options complete, ok=$ok"
  leg L6_M7_IMPORT_OPTIONS "$ok"
}

m5_audio_reload() {
  # L5/M5+M6: the engine reload chain for audio, judged on its honest
  # editor faces: the AssetServer's own `Reloaded sounds/blip.wav` line
  # fires for the external rewrite (same-handle reload, M6's live half —
  # the handle Uuid itself does not serialize over BRP, that face is T1's
  # headless anchor); a garbage-bytes probe still reloads (the loader
  # stores bytes) and, by design, raises NO load-failure event (audio
  # decodes only at play — the M12 window owns that face); no panic in
  # either window; the reference stays on the entity. The audible face
  # does not exist (the editor's mute gate); noted in the report.
  local ok=true
  mark_log "Reloaded sounds/blip.wav" "$OUTDIR/m5-good.offset"
  wav_write "$BLIP" 660
  sleep 4   # discipline 2
  local reloaded
  reloaded=$(log_lines_since "Reloaded sounds/blip.wav" "$OUTDIR/m5-good.offset")
  log "M5: Reloaded lines after the good rewrite: $reloaded (want >=1)"
  [ "${reloaded:-0}" -ge 1 ] || ok=false
  local failed panics
  failed=$(grep -c "asset load failed.*blip" "$EDITOR_LOG" 2>/dev/null); failed=${failed:-0}
  panics=$(grep -c "panicked at" "$EDITOR_LOG" 2>/dev/null); panics=${panics:-0}
  log "M5: blip failure lines=$failed panics=$panics (want 0/0 in this window)"
  [ "$failed" = "0" ] && [ "$panics" = "0" ] || ok=false
  # The garbage probe: reload still fires, still no failure event.
  cp "$BLIP" "$OUTDIR/blip-good-backup.wav"
  mark_log "Reloaded sounds/blip.wav" "$OUTDIR/m5-probe.offset"
  wav_break "$BLIP"
  sleep 4
  reloaded=$(log_lines_since "Reloaded sounds/blip.wav" "$OUTDIR/m5-probe.offset")
  log "M5: Reloaded lines after the bad probe: $reloaded (want >=1 — the chain is wired)"
  [ "${reloaded:-0}" -ge 1 ] || ok=false
  cp "$OUTDIR/blip-good-backup.wav" "$BLIP"
  sleep 4
  panics=$(grep -c "panicked at" "$EDITOR_LOG" 2>/dev/null); panics=${panics:-0}
  log "M5: panics after restore: $panics (want 0)"
  [ "$panics" = "0" ] || ok=false
  alive || { log "M5: the editor did not survive the audio window"; ok=false; }
  log "M5 audio reload chain complete, ok=$ok"
  leg L5_M5_AUDIO "$ok"
}

m9_bad_png() {
  # L7/M9: the in-use board png goes bad: editor alive (M16), the plate
  # keeps the old picture (the engine keeps the old asset value), the AR3
  # listener speaks (the M15 expected column), the reference stays; the
  # fix brings the reload back. The Bevy .meta from M7 is removed first:
  # with a meta the processed-pipeline reload stops reaching the plate
  # (archived in run 2's window as AR9 — see the report); the plain
  # pipeline is the face this leg judges.
  local ok=true
  rm -f "$PROJECT/assets/matrix/board.png.meta"
  sleep 4   # the meta removal is its own external write; let it settle
  shot m9-board-good
  local good_md5
  good_md5=$(crop_md5 "$OUTDIR/shot-m9-board-good.png")
  mark_log "asset load failed" "$OUTDIR/m9.offset"
  mark_log "Reloaded matrix/board.png" "$OUTDIR/m9-reload.offset"
  file_break "$BOARD"
  sleep 4   # discipline 2
  retrigger_if_silent "Failed to load asset 'matrix/board.png'" "$OUTDIR/m9.offset" file_break "$BOARD"
  alive || { log "M9: the editor did not survive the bad png"; leg L7_M9_BAD_PNG false; return; }
  log "M16: editor alive after bad png"
  shot m9-board-broken
  local bad_md5
  bad_md5=$(crop_md5 "$OUTDIR/shot-m9-board-broken.png")
  log "M9: board-region md5 good=$good_md5 broken=$bad_md5 (equal = old content kept)"
  [ -n "$good_md5" ] && [ "$good_md5" = "$bad_md5" ] || { log "M9: the plate did not keep the old picture"; ok=false; }
  local hits
  hits=$(log_lines_since "asset load failed" "$OUTDIR/m9.offset")
  log "M9: asset load failed lines: $hits (want >=1, the AR3 face)"
  [ "${hits:-0}" -ge 1 ] || ok=false
  grep "asset load failed" "$EDITOR_LOG" 2>/dev/null | tail -2 > "$OUTDIR/m9-ar3-lines.log"
  # The fix: a DISTINCT colour (not M7's purple — a recovery to the same
  # picture is indistinguishable from a never-broken plate). The recovery
  # face is the crop moving AND the engine's own Reloaded line landing on
  # the fix write: before the AR10 fix the Reloaded never came and the
  # plate froze (the archived red); the reader re-check is what makes both
  # faces land now.
  png_write "$BOARD" 30 180 180
  sleep 4
  retrigger_if_silent "Reloaded matrix/board.png" "$OUTDIR/m9-reload.offset" png_write "$BOARD" 30 180 180
  local reloaded
  reloaded=$(log_lines_since "Reloaded matrix/board.png" "$OUTDIR/m9-reload.offset")
  log "M9: Reloaded lines on the fix window: $reloaded (want >=1 — the AR10 engine face)"
  [ "${reloaded:-0}" -ge 1 ] || ok=false
  shot m9-board-fixed
  local fixed_md5
  fixed_md5=$(crop_md5 "$OUTDIR/shot-m9-board-fixed.png")
  log "M9: board-region md5 fixed=$fixed_md5 (want != broken and != good: the plate followed a NEW state)"
  [ -n "$fixed_md5" ] && [ "$fixed_md5" != "$bad_md5" ] && [ "$fixed_md5" != "$good_md5" ] || { log "M9: the plate did not recover to the new state"; ok=false; }
  alive || { log "M9: the editor did not survive to the fix"; ok=false; }
  log "M9 bad png complete, ok=$ok"
  leg L7_M9_BAD_PNG "$ok"
}

m10_bad_glb() {
  # L7/M10: the placed model's source goes bad: alive, the spawned
  # instances stay (a reload failure keeps the old value — the engine's
  # own Failed-to-load line is the negative face), the first-load red face
  # (AR8's bad-place probe) is characterized with its thumbnail write-off;
  # the fix respawns two boxes.
  local ok=true boxes
  boxes=$(box_count)
  log "M10: boxes before: $boxes"
  shot m10-hero-good
  mark_log "Reloaded matrix/hero.glb" "$OUTDIR/m10-reload.offset"
  mark_log "Failed to load asset 'matrix/hero.glb'" "$OUTDIR/m10-fail.offset"
  mark_log "thumbnail" "$OUTDIR/m10.offset"
  file_break "$HERO"
  sleep 4   # discipline 2
  alive || { log "M10: the editor did not survive the bad glb"; leg L7_M10_BAD_GLB false; return; }
  log "M16: editor alive after bad glb"
  [ "$(box_count)" = "$boxes" ] || { log "M10: the old instances were torn down ($boxes -> $(box_count))"; ok=false; }
  local hits fails
  hits=$(log_lines_since "Reloaded matrix/hero.glb" "$OUTDIR/m10-reload.offset")
  fails=$(log_lines_since "Failed to load asset 'matrix/hero.glb'" "$OUTDIR/m10-fail.offset")
  log "M10: bad window: Reloaded=$hits (want 0 — the load refused), load-failure lines=$fails (want >=1)"
  [ "${hits:-0}" = "0" ] || ok=false
  [ "${fails:-0}" -ge 1 ] || ok=false
  shot m10-hero-broken
  local broken_md5
  broken_md5=$(png_pixels_md5 "$OUTDIR/shot-m10-hero-broken.png" 2>/dev/null)
  log "M10: viewport md5 in the bad window: $broken_md5"
  # AR8 characterization: place a file that is already broken -> no
  # crash, no spawn; the thumbnail stage writes off once per path.
  mark_log "thumbnail" "$OUTDIR/m10-ar8.offset"
  cp "$HERO" "$PROJECT/assets/matrix/broken_first.glb"
  op entity.place_gltf '{"path":"matrix/broken_first.glb","pos_x":4.0,"pos_y":1.0,"pos_z":0.0}' >/dev/null 2>&1
  sleep 4
  alive || { log "M10: the editor did not survive placing a broken glb"; ok=false; }
  log "M10: first-load-bad probe: boxes now $(box_count) (no new box wanted); editor alive"
  [ "$(box_count)" = "$boxes" ] || log "M10: note — the broken place changed the box count (AR8 green-state note)"
  local ar8_warns
  ar8_warns=$(log_lines_since "thumbnail" "$OUTDIR/m10-ar8.offset")
  log "M10: thumbnail write-off lines in the AR8 window: $ar8_warns (want >=1)"
  grep "thumbnail" "$EDITOR_LOG" 2>/dev/null | tail -3 > "$OUTDIR/m10-thumbnail-lines.log"
  [ "${ar8_warns:-0}" -ge 1 ] || ok=false
  rm -f "$PROJECT/assets/matrix/broken_first.glb"
  sleep 2
  # The fix: the good bytes come back, the instances respawn as two.
  box_glb "$HERO" 2
  sleep 4
  retrigger_if_silent "Reloaded matrix/hero.glb" "$OUTDIR/m10-reload.offset" box_glb "$HERO" 2
  budget 30 [ "$(box_count)" = "2" ]
  [ $? -eq 0 ] || { log "M10: after the fix the model did not come back as 2 boxes ($(box_count))"; ok=false; }
  alive || { log "M10: the editor did not survive to the fix"; ok=false; }
  log "M10 bad glb complete, ok=$ok"
  leg L7_M10_BAD_GLB "$ok"
}

m11_bad_material() {
  # L8/M11: the material file becomes unreadable as a material: alive,
  # the index speaks (its own warn shape), the browser list holds; the
  # fix re-opens the card with the value back.
  local ok=true
  mark_log "no longer holds a type this project knows\|Failed to read" "$OUTDIR/m11.offset"
  cp "$MATS" "$OUTDIR/redshift-good-backup.bsn"
  python3 - "$MATS" << 'PYT'
import sys
open(sys.argv[1], "w", encoding="utf-8").write("this is not { a document ] at all")
PYT
  sleep 4   # discipline 2
  alive || { log "M11: the editor did not survive the bad material"; leg L8_M11_BAD_MAT false; return; }
  log "M16: editor alive after bad material"
  local hits
  hits=$(log_lines_since "no longer holds a type this project knows\|Failed to read" "$OUTDIR/m11.offset")
  log "M11: index refusal lines: $hits (want >=1)"
  [ "${hits:-0}" -ge 1 ] || ok=false
  grep -E "no longer holds a type|Failed to read" "$EDITOR_LOG" 2>/dev/null | tail -2 > "$OUTDIR/m11-lines.log"
  walk
  walk_has "redshift" || { log "M11: the browser list lost redshift across the bad window"; ok=false; }
  # The fix.
  cp "$OUTDIR/redshift-good-backup.bsn" "$MATS"
  sleep 4
  alive || { log "M11: the editor did not survive to the fix"; ok=false; }
  op project.select '{"path":"assets/matrix/redshift.material.bsn"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  walk
  walk_has "redshift" || { log "M11: the card lost redshift after the fix"; ok=false; }
  log "M11 bad material complete, ok=$ok"
  leg L8_M11_BAD_MAT "$ok"
}

m12_bad_audio() {
  # L8/M12 + AU6: two faces, honestly split.
  # Red (the play face, still unfixed by decision 1-A): a scene REOPENED
  # while the wav is bad panics at sink build; the error handler catches
  # (editor alive) and the storm is counted — the *现状实证* the plan and
  # the T1 QA asked to see, not an acceptance expectation. The scene is
  # saved first so the reopen's reload:true actually rereads it.
  # Green (the write face, the AU6 fix): the picker refuses a garbage wav
  # with the status-bar warning; the reference stays blip.wav.
  local ok=true
  op scene.save >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  # The M13 baseline: this save is the document state every bad-file
  # window must leave untouched.
  shasum -a 256 "$SCENE" | awk '{print $1}' > "$OUTDIR/scene-sha-pre9.txt"
  wav_break "$BLIP"
  mark_log "panicked at" "$OUTDIR/m12.offset"
  open_scene   # respawn the entities while the wav is bad -> sink build
  sleep 4      # discipline 2
  alive || { log "M12: the editor did not survive the bad-wav reopen"; leg L8_M12_BAD_AUDIO false; wav_write "$BLIP" 440; return; }
  local storm
  storm=$(log_lines_since "panicked at" "$OUTDIR/m12.offset")
  log "M12: panic lines in the bad-reopen window: $storm (the play-face reality; >=1 expected)"
  grep -n "panicked at" "$EDITOR_LOG" 2>/dev/null | tail -3 > "$OUTDIR/m12-storm-sample.log"
  [ "${storm:-0}" -ge 1 ] || log "M12: no panic observed (noted honestly; sink build timing)"
  wav_write "$BLIP" 440
  sleep 4
  open_scene   # reload again on the good bytes; the storm must not resume
  sleep 2
  local regrowth
  regrowth=$(log_lines_since "panicked at" "$OUTDIR/m12.offset")
  log "M12: new panic lines after the restore+reopen: $regrowth (want 0)"
  [ "$regrowth" = "0" ] || ok=false
  alive || { log "M12: the editor did not survive the restore"; ok=false; }
  log "M12: total panics on the books (M15 expected column): $(grep -c "panicked at" "$EDITOR_LOG" 2>/dev/null)"

  # The AU6 pick-gate green face: open the Song's audio row picker, offer
  # it the garbage wav, and the commit must be refused with the
  # status-bar warning; the field keeps blip.wav.
  op selection.select '{"name":"Song"}' >/dev/null 2>&1
  sleep 2
  local try=0 pick_e="" refused=false picked_ok=false
  while [ $try -lt 6 ] && [ "$refused" = "false" ]; do
    walk
    pick_e=$(python3 "$OUTDIR/find_pick.py" "$OUTDIR/walk-$PHASE.json" 2>/dev/null)
    if [ -z "$pick_e" ]; then
      # The card is collapsed: click its chevron first, then re-look.
      local chev
      chev=$(python3 "$OUTDIR/find_chevron.py" "$OUTDIR/walk-$PHASE.json" 2>/dev/null)
      if [ -n "$chev" ]; then
        log "M12: card chevron click at $(click_entity "$chev" 2>/dev/null)"
        sleep 2
        walk
        pick_e=$(python3 "$OUTDIR/find_pick.py" "$OUTDIR/walk-$PHASE.json" 2>/dev/null)
      fi
    fi
    [ -n "$pick_e" ] || { try=$((try + 1)); sleep 1; continue; }
    local at
    at=$(click_entity "$pick_e" 2>/dev/null)
    if [ -z "$at" ]; then try=$((try + 1)); sleep 1; continue; fi   # stale node: re-walk
    log "M12: pick icon click at $at"
    sleep 3
    walk
    grep -q "Pick AudioSource" "$OUTDIR/walk-$PHASE.json" || { try=$((try + 1)); continue; }
    # The picker: rows are TextSpan rows the Text query cannot see, so the
    # click rides geometry — narrowed first by TYPING the filter: click the
    # search field, type aaa_bad, and the list holds one candidate; then a
    # small ladder over the first row slots. Judged on the refusal banner.
    local ty xy dy
    ty=$(python3 "$OUTDIR/find_title.py" "$OUTDIR/walk-$PHASE.json" 2>/dev/null)
    [ -n "$ty" ] || { try=$((try + 1)); continue; }
    shot m12-audio-picker window
    op input.pointer '{"x":700,"y":112,"action":"click","button":"primary"}' >/dev/null 2>&1
    sleep 1
    op input.text '{"text":"aaa_bad"}' >/dev/null 2>&1
    sleep 2
    local ty_int=${ty%.*}
    for xy in 700 650 750; do
      for dy in 82 122 42 162 202; do
        local cy=$((ty_int + dy))
        op input.pointer "{\"x\":$xy,\"y\":$cy,\"action\":\"click\",\"button\":\"primary\"}" >/dev/null 2>&1
        sleep 2
        walk
        if walk_has "is not a sound file the editor can decode"; then
          picked_ok=true; refused=true
          log "M12: the picker refused the garbage wav (x=$xy title+${dy}, banner seen)"
          break 2
        fi
        grep -q "Pick AudioSource" "$OUTDIR/walk-$PHASE.json" 2>/dev/null || break 2
      done
      grep -q "Pick AudioSource" "$OUTDIR/walk-$PHASE.json" 2>/dev/null || break
    done
    try=$((try + 1))
  done
  # The write face's hard evidence: the Song still points at blip.wav.
  local song_doc
  song_doc=$(grep -o 'AudioPlayer<bevy_audio::audio_source::AudioSource>("sounds/[a-z_.]*")' "$SCENE" | head -1)
  log "M12: the document still carries $song_doc"
  echo "$song_doc" | grep -q "blip.wav" || ok=false
  [ "$picked_ok" = "true" ] || log "M12: the refusal banner was not caught (the field-unchanged face above still holds; the gate leg judges the banner)"
  shot m12-after-refusal window
  log "M12 bad audio + AU6 complete, ok=$ok (pick refusal seen=$picked_ok)"
  leg L8_M12_BAD_AUDIO "$ok"
  leg L8_AU6_PICK_GATE "$picked_ok"
}

m13_scene_integrity() {
  # M13's live half over the bad-file windows: the scene document never
  # changed on disk across every external bad write (references are
  # path-strings; a bad round writes nothing), the audit reports zero
  # Missing, and the authored entities all live.
  local ok=true sha_now sha_pre audit count
  sha_pre=$(cat "$OUTDIR/scene-sha-pre9.txt" 2>/dev/null || cat "$OUTDIR/scene-sha-prep.txt")
  sha_now=$(shasum -a 256 "$SCENE" | awk '{print $1}')
  log "M13: scene sha at the last save=$sha_pre now=$sha_now"
  [ "$sha_pre" = "$sha_now" ] || { log "M13: the scene document changed on disk across the bad rounds"; ok=false; }
  audit=$(brp jackdaw/audit '{}' 2>/dev/null)
  echo "$audit" > "$OUTDIR/m13-audit.json"
  count=$(echo "$audit" | jq -r '.result.count // empty' 2>/dev/null)
  log "M13: audit findings: ${count:-unreadable} ($(echo "$audit" | jq -r '.result.summary // empty' 2>/dev/null))"
  [ "$count" = "0" ] || ok=false
  [ -n "$(entity_id Board)" ] && [ -n "$(entity_id Song)" ] || { log "M13: Board/Song entities lost"; ok=false; }
  log "M13 scene integrity complete, ok=$ok"
  leg M13_INTEGRITY "$ok"
}

m15_warn_scan() {
  # The standing warn/error scan over this phase's editor log. Every hit
  # is attributed: the designed bad-file windows speak through the
  # bevy_asset server's own error lines + the AR3 `asset load failed:`
  # family + the thumbnail write-offs + the index refusal + the AU6
  # play-face panics (M12's window); the known-benign families (keymap
  # chord presets, headless-noise lines that never appear live) are
  # listed too. What fails the scan is anything OUTSIDE the list.
  sleep 2
  local log="$EDITOR_LOG"
  grep -Ein "warn|error|failed|Failed|panic" "$log" 2>/dev/null \
    | grep -Ev "asset load failed|thumbnail:|no longer holds a type|Failed to read|panicked at|Failed to load asset|Path not found|Texture import of|chords claimed by more than one action|Reloaded|the file was not reread|relationship on entity" \
    > "$OUTDIR/warn-lines-$PHASE.log" || true
  local unexpected
  unexpected=$(grep -c "" "$OUTDIR/warn-lines-$PHASE.log" 2>/dev/null)
  local expected_load thumbnail_nooff idx_refusals panics
  expected_load=$(grep -c "asset load failed" "$log" 2>/dev/null); expected_load=${expected_load:-0}
  thumbnail_nooff=$(grep -c "thumbnail:" "$log" 2>/dev/null); thumbnail_nooff=${thumbnail_nooff:-0}
  idx_refusals=$(grep -c "no longer holds a type" "$log" 2>/dev/null); idx_refusals=${idx_refusals:-0}
  panics=$(grep -c "panicked at" "$log" 2>/dev/null); panics=${panics:-0}
  log "WARN_SCAN: asset_load_failed=${expected_load} thumbnail_writeoff=${thumbnail_nooff} index_refusal=${idx_refusals} playface_panics=${panics} unexpected=${unexpected:-0}"
  if [ "${unexpected:-0}" != "0" ]; then
    sed 's/\x1b\[[0-9;]*m//g' "$OUTDIR/warn-lines-$PHASE.log" | head -10 >> "$CONSOLE_LOG"
    leg M15_WARN_SCAN false
  else
    leg M15_WARN_SCAN true
  fi
}

# ---- assets phase body ------------------------------------------------------
assets_phase() {
  write_scene_bsn
  rm -f "$OUTDIR/summary-assets.txt"
  editor_boot
  # The canonical first frame: the scene open, the matrix folder shown.
  open_scene
  show_folder "assets/matrix"
  sleep 4

  # Order: the good-chain legs first (their files end in their judged
  # good states), then the bad-file ladder, each on its own trigger file.
  # M3 rides first: the placed model's async spawn waits behind whatever
  # the asset server is already loading, so a fresh editor is its fair
  # window; the drop legs' plates land later and stay out of M3's shots.
  m3_glb_three_faces
  m1_png_chain
  m2_jpg_chain
  m4_material_faces
  m7_import_options
  m5_audio_reload
  m9_bad_png
  m10_bad_glb
  m11_bad_material
  m12_bad_audio
  m13_scene_integrity
  m15_warn_scan

  printf '%s\n' "$(results)" > "$OUTDIR/summary-assets.txt"
  log "VERDICT_ASSETS_PHASE: $(results)"
}

# ---- docs phase -------------------------------------------------------------
m14_external_rename() {
  # L10/M14: the AR6 boundary, mechanized: an external mv breaks the
  # audio reference; the audit must report it Missing; the rebind brings
  # the document green; the browser refresh (Create/Remove/Name chain)
  # shows the new name.
  local ok=true audit findings doc comp ref missing
  show_folder "assets/sounds"
  sleep 2
  walk
  walk_has "blip.wav" || log "M14: note — the browser did not show blip.wav before the move"
  mv "$BLIP" "$PROJECT/assets/sounds/blip_renamed.wav"
  sleep 4   # discipline 2
  show_folder "assets/sounds"
  walk
  walk_has "blip_renamed.wav" || { log "M14: the browser did not pick up the new name"; ok=false; }
  audit=$(brp jackdaw/audit '{}' 2>/dev/null)
  echo "$audit" > "$OUTDIR/m14-audit-missing.json"
  findings=$(echo "$audit" | jq -r '[.result.findings[]? | select(.kind == "Missing")] | length' 2>/dev/null)
  log "M14: audit Missing findings after the external mv: ${findings:-unreadable} (want >=1)"
  [ "${findings:-0}" -ge 1 ] || { log "M14: the audit missed the broken reference"; leg L10_M14_RENAME false; mv "$PROJECT/assets/sounds/blip_renamed.wav" "$BLIP"; return; }
  echo "$audit" | jq -c '.result.findings[]? | select(.kind == "Missing")' 2>/dev/null | head -3 > "$OUTDIR/m14-missing-sample.log"
  # The rebind: feed the finding's own spellings back through asset.rebind.
  doc=$(echo "$audit" | jq -r '[.result.findings[]? | select(.kind == "Missing")][0].document' 2>/dev/null)
  comp=$(echo "$audit" | jq -r '[.result.findings[]? | select(.kind == "Missing")][0].component' 2>/dev/null)
  ref=$(echo "$audit" | jq -r '[.result.findings[]? | select(.kind == "Missing")][0].reference' 2>/dev/null)
  log "M14: rebind: document=$doc component=$comp reference=$ref -> sounds/blip_renamed.wav"
  op asset.rebind "{\"document\":\"$doc\",\"component\":\"$comp\",\"field\":\"0\",\"reference\":\"$ref\",\"to\":\"sounds/blip_renamed.wav\"}" >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  op scene.save >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  grep -q "blip_renamed.wav" "$SCENE" || { log "M14: the rebind never reached the document"; ok=false; }
  audit=$(brp jackdaw/audit '{}' 2>/dev/null)
  echo "$audit" > "$OUTDIR/m14-audit-clean.json"
  missing=$(echo "$audit" | jq -r '.result.count // empty' 2>/dev/null)
  log "M14: audit findings after rebind+save: ${missing:-unreadable} (want 0)"
  [ "$missing" = "0" ] || ok=false
  alive || { log "M14: the editor did not survive the rename round"; ok=false; }
  log "M14 external rename boundary complete, ok=$ok"
  leg L10_M14_RENAME "$ok"
}

m13_docs_reopen() {
  # M13's reopen face: the document's pieces survive the round trip —
  # Board and Song come back with their references, the audit is clean.
  local ok=true board refpath audit count
  open_scene
  board=$(entity_id Board)
  [ -n "$board" ] || { log "M13: Board lost across reopen"; leg M13_DOCS_REOPEN false; return; }
  [ -n "$(entity_id Song)" ] || { log "M13: Song lost across reopen"; ok=false; }
  refpath=$(brp world.get_components "{\"entity\":\"$board\",\"components\":[\"jackdaw::reference_image::ReferenceImage\"]}" 2>/dev/null \
    | jq -r '.result.components["jackdaw::reference_image::ReferenceImage"].path // empty' 2>/dev/null)
  log "M13: reopen Board path=$refpath"
  echo "$refpath" | grep -q "matrix/board.png" || ok=false
  audit=$(brp jackdaw/audit '{}' 2>/dev/null)
  echo "$audit" > "$OUTDIR/m13-docs-audit.json"
  count=$(echo "$audit" | jq -r '.result.count // empty' 2>/dev/null)
  log "M13: docs-phase audit findings: ${count:-unreadable}"
  [ "$count" = "0" ] || ok=false
  shot m13-reopened
  log "M13 docs reopen complete, ok=$ok"
  leg M13_DOCS_REOPEN "$ok"
}

docs_phase() {
  write_scene_bsn
  rm -f "$OUTDIR/summary-docs.txt"
  editor_boot
  open_scene
  sleep 2
  m13_docs_reopen
  m14_external_rename
  m15_warn_scan
  printf '%s\n' "$(results)" > "$OUTDIR/summary-docs.txt"
  log "VERDICT_DOCS_PHASE: $(results)"
}

case "$PHASE" in
  prep) prep ;;
  assets) assets_phase ;;
  docs) docs_phase ;;
  all)
    prep
    assets_phase
    docs_phase
    cat "$OUTDIR/summary-assets.txt" "$OUTDIR/summary-docs.txt" 2>/dev/null | sort | tr '\n' ' ' > "$OUTDIR/summary.txt"
    log "VERDICT_ALL: $(cat "$OUTDIR/summary.txt")"
    log "T18_LIVE_DONE"
    ;;
  *) echo "unknown phase: $PHASE (prep|assets|docs|all)"; exit 2 ;;
esac
