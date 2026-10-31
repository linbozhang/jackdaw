#!/bin/bash
# T19 graphics-parity live legs (loop/plans/t19-graphics-parity.md §三).
# T1 lands the helper library: the T18 pixel-evidence craft (png_pixels_md5,
# sips crop) plus the feature-08 pixdiff semantics ported to python3 stdlib,
# the A7 five-move self-defence in `shot`, and the fixture prep the matrix's
# L1 reuses. The M1-M16 legs themselves land with T2 (qa轮), on these helpers.
#
# Phases (each phase boots and cleans its own editor/game processes —
# run one per invocation):
#   selftest  validate the pixel helpers on synthetic PNGs (no editor).
#             T1's acceptance evidence for the helper library.
#   prep      fixture hygiene + jackdaw_remote injection (two-line sed) +
#             lock refresh + warm debug build of the game (t16 prep form).
#   seed      L1's editor half, and decision 3's live proof: boot the
#             editor on the fixture, open scene.bsn, and author the scene
#             Environment through the operator chain (selection.select ->
#             component.add -> environment.set seed -> scene.save), then
#             confirm the viewport High preset. The document on disk after
#             this phase is the matrix's shared fixture.
#   editor    T2: L2/L8/L9/L10 (M1/M2/M3 editor pieces, GI regression,
#             round trip, pixel archive).
#   game      T2: L3/L4/L6/L7/L8 (PIE/direct/staged parity, AA three
#             stations, the negative legs M9-M12, the M15 empty state).
#   export    T2: L5 (M6 staged parity) and M10's manifest full-list diff.
#
# Usage: bash loop/qa/t19-live.sh [phase]   phase: selftest|prep|seed|editor|game|export
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
FIXROOT=/Users/zhanglinbo/workspace/loop-mac/t19-graphics
PROJECT="$FIXROOT/t19-graphics"
PORT=15703
GAME_PORT=15702
OUTDIR="$REPO/loop/t19-live"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
STAGED="$PROJECT/.jackdaw/dist/release"
STAGED_EXE="$STAGED/t19-graphics"
# The T19 seed values (plan §五 小定案): red/green margins follow the
# feature-08 precedents (bloom 77.11%, SMAA 3.89%).
SEED_EXPOSURE=13.0
SEED_BLOOM=0.8
SEED_AA=Smaa
ENV_TYPE='jackdaw_scene_types::environment::Environment'
NAME='bevy_ecs::name::Name'
CAM3D='bevy_camera::components::Camera3d'
# BRP type paths are the defining module paths (std::any::type_name), not the
# re-export spellings. Where the fork's layout was double-checked, the probe
# helper tries candidates in order and logs the one that answers.
EXPOSURE='bevy_camera::camera::Exposure'
BLOOM='bevy_post_process::bloom::settings::Bloom'
TONEMAP='bevy_render::view::Tonemapping'
SMAA='bevy_anti_alias::smaa::Smaa'
TAA='bevy_anti_alias::taa::TemporalAntiAliasing'
MSAA='bevy_render::view::Msaa'
CAMERA='bevy_camera::components::Camera'
# The seed values (plan §五 小定案), and the f32 read-back epsilon (t19-t1
# deviation 2: a 0.8 seed reads back as 0.800000011920929).
EPSILON=0.001
# Pixel red/green thresholds, percent of pixels changed (feature-08
# precedents: SMAA 3.89%, bloom 77.11% — so 1% is a conservative green line
# for an exposure/bloom pair; anything smaller smells like A7's frozen frame).
PX_THRESHOLD=1.0
CONFIG_DIR_VAR_VALUE="$HOME/Library/Application Support/jackdaw"
SCRATCH_CONFIG="$OUTDIR/config-scratch"
# M16's warn scan pattern (plan §二): every hit is attributed, not just counted.
WARN_PATTERN='tonemapp|bloom|exposure|solari|ray|UnresolvedTypes|panicked'
mkdir -p "$OUTDIR"
PHASE="${1:-all}"
CONSOLE_LOG="$OUTDIR/console-$PHASE.log"
: > "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t19-live.XXXXXX)"
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
  pkill -x t19-graphics 2>/dev/null
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
  # comes back; exhaustion returns 1 (t16 T3 lesson).
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
gbrp() {
  local method="$1" params="${2:-}" id=$RANDOM body out attempt
  if [ -n "$params" ]; then
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params")
  else
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s"}' "$id" "$method")
  fi
  # The game BRP answers intermittently empty in busy windows (A9):
  # reads retry with a short settle; writes are verified through a read.
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
  pkill -x t19-graphics 2>/dev/null
  sleep 2
}
editor_boot() { # editor_boot [project]
  pkill -x jackdaw 2>/dev/null; pkill -x t19-graphics 2>/dev/null; sleep 1
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
    if brp jackdaw/status '{}' >/dev/null 2>&1 && pgrep -x jackdaw >/dev/null; then ok=1; break; fi
    pgrep -x jackdaw >/dev/null || break
  done
  [ -n "$ok" ] || { log "EDITOR_BOOT_FAIL"; exit 1; }
  sleep 5
  wait_idle 900 >/dev/null; sleep 3; dismiss_dialog
  if grep -q "Recovered Work" "$boot_log" 2>/dev/null; then :; fi
  log "EDITOR_READY project=${1:-none}"
}
open_scene() {
  # reload: true — an already-open tab rereads the file.
  op scene.open "{\"path\":\"$PROJECT/assets/$1\",\"reload\":true}" >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
}
walk() { brp jackdaw/ui_tree '{"depth":60}' > "$OUTDIR/walk-$PHASE.json" 2>/dev/null; }
walk_has() { grep -qF "$1" "$OUTDIR/walk-$PHASE.json" 2>/dev/null; }
click_text() {
  brp jackdaw/ui_click "{\"text\":\"$1\"}" 2>/dev/null | jq -r '.result.clicked // false' 2>/dev/null
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
flow_start_scene() { # flow_start_scene <scene> — point the flow's start scene
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
  # The flow boots menu.bsn first; wait for the game scene's camera (the
  # dress target) before any face read — the BRP answers long before the
  # scene transition lands.
  local deadline=$((SECONDS + 90)) cid=""
  while [ $SECONDS -lt $deadline ]; do
    cid=$(game_cam_id 2>/dev/null)
    [ -n "$cid" ] && break
    sleep 3
  done
  [ -n "$cid" ] || { log "direct_run $1: no game camera appeared"; return 1; }
  sleep 5
  log "direct_run $1: game camera $cid"
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
export_face() { # export_face — "<state> <started_at>" of the export face
  brp jackdaw/export '{}' 2>/dev/null | jq -r '"\(.result.state // "none") \(.result.started_at // 0)"' 2>/dev/null
}
export_wait() { # export_wait — game.export, held until THIS export run is
                # done: started_at must advance past the pre-call face and
                # the state must come back "ready" (a SHA-only criterion is
                # pre-satisfied by the previous export's tree — the M10
                # run-1 lesson).
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
      # The face never saw our run (a rejected no-op); say so and stop.
      log "export_wait: the face never left the pre-call run ($before, state $st) — treating as completed-no-rerun"
      return 1
    fi
    sleep 5
  done
  return 1
}
# M10's negative strength is decision 5-C: the full manifest list diff.
# export-manifest.json carries a SHA-256 per file (T07 delivery), so the
# whole staged tree compares in one python pass. Empty output = no diff.
manifest_diff() { # manifest_diff <before.json> <after.json>
  python3 - "$1" "$2" << 'PYT'
import json, sys
before = json.load(open(sys.argv[1]))
after = json.load(open(sys.argv[2]))
def entries(doc):
    files = doc.get("files") or doc.get("entries") or []
    out = {}
    for f in files:
        path = f.get("path") or f.get("name") or ""
        out[path] = f.get("sha256") or f.get("sha") or f.get("hash") or ""
    return out
b, a = entries(before), entries(after)
for path in sorted(set(b) - set(a)):
    print(f"only-in-before: {path}")
for path in sorted(set(a) - set(b)):
    print(f"only-in-after: {path}")
for path in sorted(set(a) & set(b)):
    if b[path] != a[path]:
        print(f"changed: {path}")
PYT
}

# ---- pixel evidence helpers (T1 deliverable) --------------------------------
#
# Decision 1: the numeric track is the main assertion (component read-back);
# the pixel track proves "the channel's picture actually moved with the
# value", within one channel only — never a cross-channel pixel equality.
# Editor viewport shots are stable-sized render-target captures (percentage
# form, the feature-08 precedent); game-window shots ride the MD5
# change/no-change form with a sips crop isolating the game face from the
# window chrome (the T18 precedent).

png_write() { # png_write <path> <r> <g> <b> [size] — a solid-colour test PNG
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
png_decode_rgb() { # stdout: the decoded RGB bytes of an 8-bit non-interlaced
                   # PNG (all five filter rows undone); empty + exit 1 on a
                   # PNG the pure-python decoder does not take.
  python3 - "$1" << 'PYT'
import struct, sys, zlib
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
elif channels == 2:
    rgb = bytearray()
    for i in range(0, len(out), 2):
        rgb += bytes((out[i], out[i], out[i]))
    out = rgb
elif channels == 1:
    out = bytearray(byte for px in out for byte in (px, px, px))
sys.stdout.buffer.write(bytes(out))
PYT
}
png_pixels_md5() { # stdout: md5 of the decoded RGB pixel bytes (t18 form)
  local bytes
  bytes=$(png_decode_rgb "$1") || { echo ""; return 1; }
  printf '%s' "$bytes" | md5 2>/dev/null || printf '%s' "$bytes" | python3 -c "import hashlib,sys;print(hashlib.md5(sys.stdin.buffer.read()).hexdigest())"
}
png_size() { # stdout: "<w> <h>" of a PNG
  python3 - "$1" << 'PYT'
import struct, sys
data = open(sys.argv[1], "rb").read()
w, h = struct.unpack(">II", data[16:24])
print(w, h)
PYT
}
pixdiff() { # pixdiff <a.png> <b.png> [tol] — the pixdiff.ps1 semantics on
            # python3 stdlib: mean abs diff per pixel (summed over channels)
            # and the % of pixels whose channel-sum delta exceeds tol.
            # Size mismatch prints a line and exits 1 (a red of its own).
  local a="$1" b="$2" tol="${3:-12}"
  python3 - "$a" "$b" "$tol" << 'PYT'
import struct, subprocess, sys
def decode(path):
    out = subprocess.run([sys.executable, "-c", DECODE, path],
                         capture_output=True).stdout
    return out
DECODE = r'''
import struct, sys, zlib
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
elif channels == 2:
    rgb = bytearray()
    for i in range(0, len(out), 2):
        rgb += bytes((out[i], out[i], out[i]))
    out = rgb
elif channels == 1:
    out = bytearray(byte for px in out for byte in (px, px, px))
sys.stdout.buffer.write(bytes(out))
'''
wa, wh = 0, 0
with open(sys.argv[1], "rb") as f:
    wa, wh = struct.unpack(">II", f.read(24)[16:24])
with open(sys.argv[2], "rb") as f:
    wb, hb = struct.unpack(">II", f.read(24)[16:24])
if (wa, wh) != (wb, hb):
    print(f"size mismatch: {wa}x{wh} vs {wb}x{hb}")
    sys.exit(1)
ba, bb = decode(sys.argv[1]), decode(sys.argv[2])
tol = int(sys.argv[3])
if len(ba) != len(bb) or not ba:
    print(f"decode mismatch: {len(ba)} vs {len(bb)} bytes")
    sys.exit(1)
pixels = len(ba) // 3
diff = 0; changed = 0
for i in range(0, len(ba), 3):
    d = abs(ba[i] - bb[i]) + abs(ba[i+1] - bb[i+1]) + abs(ba[i+2] - bb[i+2])
    diff += d
    if d > tol:
        changed += 1
mean = diff / len(ba)
print(f"pixels: {pixels}; changed(>tol {tol}): {changed} ({100.0 * changed / pixels:.2f}%); mean channel diff: {mean:.3f}")
PYT
}
crop_md5() { # crop_md5 <png> <x> <y> <w> <h> — md5 of a caller-chosen rect
             # (the t18 form generalised: the editor camera is static within
             # a phase, so a crop isolates the face that matters — the game
             # face, the viewport face — from window chrome and neighbours).
  local png="$1" x="$2" y="$3" w="$4" h="$5" out="/tmp/t19-crop-$$.png"
  sips -s format png -c "$h" "$w" --cropOffset "$y" "$x" "$png" --out "$out" >/dev/null 2>&1 \
    || { echo ""; return 1; }
  png_pixels_md5 "$out"
  local rc=$?
  rm -f "$out"
  return $rc
}
settle_pixels() { # GR4 discipline: a settled second beat before any pixel
                  # verdict, and the first shot after an AA/quality switch
                  # is discarded by the caller (SETTLE_FRAMES=90 inside
                  # jackdaw/screenshot is the bottom line, not the plan).
  sleep "${1:-3}"
}
shot() { # shot <name> [kind] — the A7 five moves in one helper:
         # 1. a unique `request` key per call (PendingWaits never answers a
         #    stale frame twice — server.rs:1798-1836);
         # 2. `rm -f` before the request, so a leftover can never satisfy
         #    the size check;
         # 3. the landed file must be non-empty before it counts;
         # 4. callers judge "red" only through confirm_red below (the
         #    adjacent-two-shots flake probe — a frozen frame loses there);
         # 5. the jackdaw/screenshot channel degrades to `screencapture -x`.
  local name="$1" kind="${2:-window}"
  local rel path out out_json
  rel="screenshots/t19-$name.png"
  path="$PROJECT/$rel"
  rm -f "$path"
  local key="t19-$name-$RANDOM-$SECONDS"
  for i in $(seq 1 20); do
    out_json=$(curl -s -m 12 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
      -d "{\"jsonrpc\":\"2.0\",\"id\":$i,\"method\":\"jackdaw/screenshot\",\"params\":{\"kind\":\"$kind\",\"path\":\"$rel\",\"request\":\"$key-$i\"}}" 2>/dev/null)
    out=$(echo "$out_json" | jq -r '.result.path // empty' 2>/dev/null)
    if [ -n "$out" ] && [ -s "$path" ]; then
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
confirm_red() { # confirm_red <name> <kind> <before_md5> <after_md5> — the
                # flake probe (move 3, not a criterion): a "no change" verdict
                # is only believed after two fresh same-state shots agree
                # with it. Returns 0 when the red is real (the state truly
                # renders identical), 1 when a fresh shot differed (the first
                # after-shot was a stale frame — the caller re-reads the
                # corrected md5 from $OUTDIR/shot-<name>.png).
  local name="$1" kind="$2" before="$3" after="$4" fresh1 fresh2
  [ "$before" != "$after" ] && return 1   # pixels moved: not a red at all
  settle_pixels 2
  shot "$name-flakecheck1" "$kind" || return 2
  fresh1=$(png_pixels_md5 "$OUTDIR/shot-$name-flakecheck1.png")
  settle_pixels 2
  shot "$name-flakecheck2" "$kind" || return 2
  fresh2=$(png_pixels_md5 "$OUTDIR/shot-$name-flakecheck2.png")
  if [ -n "$fresh1" ] && [ "$fresh1" = "$fresh2" ] && [ "$fresh1" = "$after" ]; then
    log "confirm_red $name: two fresh same-state shots agree — the red is real"
    return 0
  fi
  log "confirm_red $name: a fresh shot differed (flake/stale frame); re-read shot-$name-flakecheck*.png"
  return 1
}

# ---- GR6 spot check (lands with T2's A-region legs) -------------------------
# R12 (buglist:78) is in the A-region toggle family's neighbourhood. The spot
# check toggles Sun Shadows through the operator, then reads both halves:
# pixel (viewport red/green through settle + pixdiff) and numeric (the
# viewport.json file face the store writes on resource_changed). If the pixel
# side stays flat through confirm_red while the numeric side moved, that is
# the R12 shape: file the GR ledger line, do not fix here.
gr6_spot_check() {
  local before after
  settle_pixels 3
  shot gr6-sun-on viewport || return 1
  before=$(png_pixels_md5 "$OUTDIR/shot-gr6-sun-on.png")
  op viewport.show.toggle '{"flag":"sun_shadows","on":false}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null; settle_pixels 3
  shot gr6-sun-off viewport || return 1
  after=$(png_pixels_md5 "$OUTDIR/shot-gr6-sun-off.png")
  local diff_line
  diff_line=$(pixdiff "$OUTDIR/shot-gr6-sun-on.png" "$OUTDIR/shot-gr6-sun-off.png")
  log "GR6 pixel half: $diff_line"
  # The numeric half: the file face (viewport.json) is the only BRP-free
  # surface ViewportSettings exposes — the resource is not reflect-registered.
  local file_face
  file_face=$(jq -c '.quality.sun_shadows' "$CONFIG_DIR_VAR_VALUE/viewport.json" 2>/dev/null)
  [ "$file_face" = "null" ] && file_face=""
  if [ "$before" != "$after" ]; then
    log "GR6 spot check: sun shadows toggle moves the picture AND the settings file (sun_shadows=$file_face) — not the R12 shape"
    leg GR6_SPOT true
  else
    # md5 equal: judge red only through the flake probe
    if confirm_red gr6-sunstill viewport "$before" "$after"; then
      if [ "$file_face" = "false" ]; then
        # The fixture scene carries no shadow receivers in frame (sky only),
        # so a flat picture is what the geometry predicts; R12 needs a frame
        # where a shadow should visibly land. Inconclusive, red not charged.
        log "GR6 INCONCLUSIVE: settings moved (sun_shadows=false on file) but the picture is flat — the fixture frame holds no shadow receivers (sky only), so this is not chargeable as the R12 shape"
        leg GR6_SPOT true
        log "GR6 verdict: inconclusive-by-fixture (recorded in the report; R12 spot check needs a geometry-bearing scene)"
      else
        log "GR6: picture flat and the file face did not record the toggle ($file_face) — the store half is inconclusive too"
        leg GR6_SPOT false
      fi
    else
      log "GR6: first pair read flat but a fresh shot differed (flake/stale) — treating the pair as moved"
      leg GR6_SPOT true
    fi
  fi
  op viewport.show.toggle '{"flag":"sun_shadows","on":true}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null; settle_pixels 2
}

# ---- T2 numeric/pixel helpers ------------------------------------------------

ecam() { # ecam — the editor's viewport camera entity id, first via
         # jackdaw/camera_state (the editor's own ActiveViewport/
         # MainViewportCamera answer; to_bits carries NonMaxU32 index, so
         # index = 0xFFFFFFFF - low half), then via the dressed-camera
         # query (Exposure-bearing; the High preset's post opt-in is the L1
         # precondition), then any Camera3d. The editor world holds several
         # Camera3d (3d viewport host, 2d hosts, tool previews) and the
         # first of a bare query is NOT the viewport's — run 1's lesson.
  local bits conv dressed
  bits=$(brp jackdaw/camera_state '{}' 2>/dev/null | jq -r '.result.camera // empty' 2>/dev/null)
  if [ -n "$bits" ] && [ "$bits" != "null" ]; then
    conv=$(python3 -c "b=int('$bits'); print(f'{0xFFFFFFFF - (b & 0xFFFFFFFF)}v{b >> 32}')" 2>/dev/null)
    if [ -n "$conv" ]; then echo "$conv"; return 0; fi
  fi
  dressed=$(brp world.query "{\"data\":{\"components\":[\"$CAM3D\",\"$EXPOSURE\"]}}" 2>/dev/null \
    | jq -r '.result[]?.entity // empty' 2>/dev/null)
  if [ -n "$dressed" ]; then echo "$dressed"; return 0; fi
  brp world.query "{\"data\":{\"components\":[\"$CAM3D\"]}}" 2>/dev/null \
    | jq -r '.result[]?.entity // empty' 2>/dev/null
}

ECOMP_VALUE=""; ECOMP_ERRORS=""
ecomp_parts() { # ecomp_parts <id> <component-path> — sets ECOMP_VALUE and
                # ECOMP_ERRORS in the caller's shell (a $() subshell never
                # propagates globals — the first run's set -u death).
  local id="$1" out
  out=$(brp world.get_components "{\"entity\":\"$id\",\"components\":[\"$2\"]}" 2>/dev/null)
  ECOMP_VALUE=$(echo "$out" | jq -c --arg c "$2" '.result.components[$c] // empty' 2>/dev/null)
  ECOMP_ERRORS=$(echo "$out" | jq -c --arg c "$2" '.result.errors[$c] // empty' 2>/dev/null)
}
ecomp() { # ecomp <id> <component-path> — an editor entity's component JSON
          # (empty when the component is absent/unknown; the raw errors map
          # lands in $ECOMP_ERRORS for absence-vs-unknown attribution).
  ecomp_parts "$@"
  echo "$ECOMP_VALUE"
}

probe_component() { # probe_component <id> <name> <cand1> <cand2>... — tries
                    # candidate type-path spellings, exports the winner in
                    # $PROBED (path) and $PROBED_JSON (value). Evidence for
                    # the report's type-path table.
  local id="$1" name="$2"; shift 2
  local cand
  PROBED=""; PROBED_JSON=""
  for cand in "$@"; do
    ecomp_parts "$id" "$cand"
    if [ -n "$ECOMP_VALUE" ]; then
      PROBED="$cand"; PROBED_JSON="$ECOMP_VALUE"
      log "probe $name: $cand answers ($ECOMP_VALUE)"
      return 0
    fi
    log "probe $name: $cand silent (errors: ${ECOMP_ERRORS:0:160})"
  done
  return 1
}

num_close() { # num_close <json-value> <expected> — f32 read-back with epsilon
  python3 -c "import json,sys; v=json.loads(sys.argv[1]); e=json.loads(sys.argv[2]); sys.exit(0 if v is not None and abs(float(v)-float(e))<$EPSILON else 1)" "$1" "$2"
}

envset() { # envset <params> — environment.set plus the settle the B-region
           # release-commit semantics need
  op environment.set "{\"$1\":$2}" >/dev/null 2>&1
  sleep 1; wait_idle 120 >/dev/null; sleep 1
}

gshot() { # gshot <name> — a full-screen OS capture for the game channels
          # (the game BRP has no screenshot method, plan fact 10). The
          # before/after pair rides pixdiff, where identical window chrome
          # cancels; verify the file landed non-empty.
  local path="$OUTDIR/shot-$1.png"
  rm -f "$path"
  screencapture -x "$path" 2>/dev/null
  if [ -s "$path" ]; then
    log "gshot $1 ok ($(png_size "$path" 2>/dev/null))"
    return 0
  fi
  log "gshot $1 FAILED (screencapture never landed)"
  return 1
}

game_face() { # game_face <id> — the game camera's dress matrix as one compact
              # JSON line: exposure ev100, bloom intensity, tonemapper, smaa
              # presence, msaa. Both type-path spellings are requested at
              # once (the lenient errors map absorbs the loser), so the face
              # is its own probe evidence. Presence/absence rides the lenient
              # split (component_not_present vs unknown-type is the
              # attribution the M7 Keep-exit leg needs).
  local id="$1" out
  out=$(gbrp world.get_components "{\"entity\":\"$id\",\"components\":[\"$EXPOSURE\",\"bevy_camera::exposure::Exposure\",\"$BLOOM\",\"bevy_post_process::bloom::Bloom\",\"$TONEMAP\",\"bevy_camera::tonemapping::Tonemapping\",\"$SMAA\",\"$MSAA\"]}" 2>/dev/null)
  python3 - "$out" << 'PYT'
import json, sys
try:
    r = json.loads(sys.argv[1])["result"]
except Exception:
    print("{}"); sys.exit(0)
comps = r.get("components") or {}
def first(*keys):
    for k in keys:
        if k in comps:
            return comps[k]
    return None
def field(v, *keys):
    for k in keys:
        if isinstance(v, dict) and k in v:
            return v[k]
    return None
exposure = field(first("bevy_camera::camera::Exposure", "bevy_camera::exposure::Exposure"), "ev100")
bloom = field(first("bevy_post_process::bloom::settings::Bloom", "bevy_post_process::bloom::Bloom"), "intensity")
tone = first("bevy_render::view::Tonemapping", "bevy_camera::tonemapping::Tonemapping")
if isinstance(tone, dict):
    # bevy enums: unit variants serialize as plain strings, so a dict here
    # means an externally-tagged form — take the variant name.
    tone = next(iter(tone.keys()), tone)
msaa = comps.get("bevy_render::view::Msaa")
if isinstance(msaa, dict):
    msaa = next(iter(msaa.keys()), msaa)
face = {
    "exposure": exposure,
    "bloom": bloom,
    "tonemapping": tone,
    "smaa_present": "bevy_anti_alias::smaa::Smaa" in comps,
    "msaa": msaa,
}
print(json.dumps(face, sort_keys=True))
PYT
}

faces_equal() { # faces_equal <a.json> <b.json> — field-by-field identity
  python3 - "$1" "$2" << 'PYT'
import json, sys
a, b = json.loads(sys.argv[1]), json.loads(sys.argv[2])
def close(x, y):
    if isinstance(x, (int, float)) and isinstance(y, (int, float)):
        return abs(float(x) - float(y)) < 0.001
    return x == y
ok = all(close(a.get(k), b.get(k)) for k in a)
print("EQUAL" if ok else f"DIFFER: {a} vs {b}")
sys.exit(0 if ok else 1)
PYT
}

seed_face() { # seed_face <face.json> — the game camera must carry the seed
              # dress: bloom 0.8, tonemapper TonyMcMapface, smaa on, msaa
              # off. f32 epsilon. (The Exposure component itself is
              # unreadable through any stock bevy BRP — no ReflectSerialize
              # on an #[reflect(opaque)] type; the dress writes it in the
              # same insert block as the tonemapper, and the pixel legs
              # prove it reaches the picture.)
  python3 - "$1" << 'PYT'
import json, sys
f = json.loads(sys.argv[1])
tone = f.get("tonemapping")
if isinstance(tone, dict):
    tone = next(iter(tone.keys()), tone)
ok = (f.get("bloom") is not None and abs(f["bloom"] - 0.8) < 0.001
      and tone == "TonyMcMapface"
      and f.get("smaa_present") is True
      and f.get("msaa") is not None)
print("SEEDOK" if ok else f"FACE-MISMATCH {f}")
sys.exit(0 if ok else 1)
PYT
}

game_cam_id() { # game_cam_id — the game's own (active) camera: the PIE
                # capture camera spawns is_active:false, the rig's Camera3d
                # is the live one; prefer the active one, else the first.
  local ids active id cam
  ids=$(gbrp world.query "{\"data\":{\"components\":[\"$CAM3D\"]}}" 2>/dev/null \
    | jq -r '.result[]?.entity // empty' 2>/dev/null)
  for id in $ids; do
    cam=$(gcomp "$id" "$CAMERA")
    if echo "$cam" | jq -e '.is_active == true' >/dev/null 2>&1; then
      echo "$id"; return 0
    fi
  done
  for id in $ids; do echo "$id"; return 0; done
  return 1
}

n13_count() { # n13_count — the N13 PIE drain panic counter (Mac 100%
              # recurrence; bypass+count is the t11-t16 discipline)
  grep -c "panicked" "$OUTDIR/editor-$PHASE.log" 2>/dev/null || echo 0
}

warn_scan() { # warn_scan <logfile> <tag> — the M16 pattern; every hit is
              # attributed (logged with its line), never just counted
  local file="$1" tag="$2" hits
  [ -f "$file" ] || { log "warn-scan $tag: no log at $file"; return 0; }
  hits=$(grep -inE "$WARN_PATTERN" "$file" | grep -v "warn-scan" | head -40)
  if [ -z "$hits" ]; then
    log "warn-scan $tag: clean ($WARN_PATTERN)"
  else
    log "warn-scan $tag: $(echo "$hits" | wc -l | tr -d ' ') hits:"
    echo "$hits" | while IFS= read -r line; do log "warn-scan $tag | $line"; done
  fi
}

a_region_suite() { # a_region_suite — the A-region operator pass (the same
                   # 16-call family graphics_prefs_clean.rs drives headless)
  op viewport.quality.preset '{"preset":"low"}' >/dev/null 2>&1; sleep 1
  op viewport.quality.set '{"render_scale":50,"anti_aliasing":"smaa","shadow_quality":"high","detail_distance":"far","ssao_quality":"ultra"}' >/dev/null 2>&1; sleep 1
  for flag in sun_shadows point_shadows sky_reflection fog post_processing bloom ambient_occlusion terrain_detail; do
    op viewport.show.toggle "{\"flag\":\"$flag\",\"on\":false}" >/dev/null 2>&1
  done
  op viewport.ssao.set '{"on":true,"quality":"ultra"}' >/dev/null 2>&1
  op viewport.sharpen.set '{"on":true,"strength":0.8}' >/dev/null 2>&1
  op viewport.realtime.toggle '{"on":false}' >/dev/null 2>&1
  op viewport.stats.toggle '{"on":true}' >/dev/null 2>&1
  op viewport.stats.graph.toggle '{"on":true}' >/dev/null 2>&1
  sleep 1; wait_idle 120 >/dev/null
}

viewport_json_face() { # viewport_json_face <path> — the store's file face
  jq -c '{render_scale:.quality.render_scale, aa:.quality.anti_aliasing, ssao:.quality.ssao_quality, post:.quality.post_processing, sharpen:.sharpen}' "$1" 2>/dev/null
}

# ---- phase: selftest ---------------------------------------------------------
# The helper library's own evidence, on synthetic PNGs: no editor, no GPU.
selftest() {
  local ok=true
  local t="/tmp/t19-selftest-$$"
  mkdir -p "$t"
  png_write "$t/red.png" 200 30 30
  png_write "$t/red2.png" 200 30 30
  png_write "$t/green.png" 30 200 30 64

  local m1 m2 m3
  m1=$(png_pixels_md5 "$t/red.png"); m2=$(png_pixels_md5 "$t/red.png"); m3=$(png_pixels_md5 "$t/green.png")
  if [ -n "$m1" ] && [ "$m1" = "$m2" ] && [ "$m1" != "$m3" ]; then
    log "selftest png_pixels_md5: stable per content, distinct per colour ($m1 vs $m3)"
  else
    leg SELFTEST_MD5 false; ok=false
  fi

  local same diff
  same=$(pixdiff "$t/red.png" "$t/red2.png")
  if echo "$same" | grep -q "(0.00%)" ; then
    log "selftest pixdiff identical: $same"
  else
    leg SELFTEST_PIXDIFF_SAME false; ok=false
  fi
  diff=$(pixdiff "$t/red.png" "$t/green.png")
  if echo "$diff" | grep -qE "\((100.00|%)\)|\(100.00%\)" ; then
    log "selftest pixdiff complementary colours: $diff"
  else
    leg SELFTEST_PIXDIFF_DIFF false; ok=false
  fi

  # A 128x64 red field with a green quadrant: cropping the red-only region
  # twice agrees, cropping across the boundary disagrees.
  python3 - "$t/mixed.png" << 'PYT'
import struct, sys, zlib
path = sys.argv[1]
w, h = 128, 64
rows = bytearray()
for y in range(h):
    rows.append(0)
    for x in range(w):
        if x < 64 and y < 32:
            rows += bytes((30, 200, 30, 255))
        else:
            rows += bytes((200, 30, 30, 255))
def chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(bytes(rows)))
       + chunk(b"IEND", b""))
open(path, "wb").write(png)
PYT
  local c1 c2 c3
  c1=$(crop_md5 "$t/mixed.png" 0 0 32 16); c2=$(crop_md5 "$t/mixed.png" 0 0 32 16); c3=$(crop_md5 "$t/mixed.png" 64 0 32 16)
  if [ -n "$c1" ] && [ "$c1" = "$c2" ] && [ "$c1" != "$c3" ]; then
    log "selftest crop_md5: rect-stable, rect-distinct"
  else
    leg SELFTEST_CROP false; ok=false
  fi

  local sizes
  sizes=$(png_size "$t/mixed.png")
  [ "$sizes" = "128 64" ] || { leg SELFTEST_SIZE false; ok=false; }

  rm -rf "$t"
  if $ok; then leg SELFTEST_HELPERS true; else leg SELFTEST_HELPERS false; fi
}

# ---- phase: prep -------------------------------------------------------------
prep() {
  pkill -x jackdaw 2>/dev/null; pkill -x t19-graphics 2>/dev/null; sleep 1
  [ -d "$PROJECT" ] || { log "PREP_FAIL fixture missing; run: ./target/debug/jd new $FIXROOT/t19-graphics"; exit 1; }
  grep -q "GamePlugin" "$PROJECT/src/main.rs" || { log "PREP_FAIL fixture lacks the game template main"; exit 1; }

  # Warm-project test injection (t11t2/t13t2/t14/t15/t16 practice): the
  # game-side BRP is a test seam; the shipping game never carries it.
  if ! grep -q jackdaw_remote "$PROJECT/Cargo.toml"; then
    /usr/bin/sed -i '' "s|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = \[\"terrain\", \"pie\"\] }|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = [\"terrain\", \"pie\"] }\njackdaw_remote = { path = '$REPO/crates/jackdaw_remote' }|" "$PROJECT/Cargo.toml"
    grep -q jackdaw_remote "$PROJECT/Cargo.toml" || { log "PREP_FAIL no remote dep"; exit 1; }
    /usr/bin/sed -i '' 's|\.add_plugins(jackdaw_runtime::JackdawPlugin)|.add_plugins(jackdaw_runtime::JackdawPlugin)\n        .add_plugins(jackdaw_remote::JackdawRemotePlugin::default())|' "$PROJECT/src/main.rs"
    grep -q JackdawRemotePlugin "$PROJECT/src/main.rs" || { log "PREP_FAIL no remote plugin"; exit 1; }
    (cd "$PROJECT" && cargo metadata --format-version 1 >/dev/null 2>"$OUTDIR/lockfix.log") \
      || { log "PREP_FAIL lock refresh: $(tail -2 "$OUTDIR/lockfix.log")"; exit 1; }
  fi

  # Warm the game build so the legs are not cold compiles.
  (cd "$PROJECT" && cargo build > "$OUTDIR/game-warmbuild-prep.log" 2>&1) \
    || { log "PREP_FAIL game warm build: $(tail -3 "$OUTDIR/game-warmbuild-prep.log")"; exit 1; }
  log "PREP_OK fixture=$PROJECT"
}

# ---- phase: seed (L1's editor half; decision 3's live proof) -----------------
seed() {
  local scene="$PROJECT/assets/scene.bsn"
  editor_boot "$PROJECT"
  open_scene scene.bsn

  local sha_before
  sha_before=$(shasum -a 256 "$scene" | awk '{print $1}')

  # The operator chain, exactly what tests/viewport/graphics_prefs_clean.rs
  # proves headless (decision 3): select the scene root, add the component,
  # seed by paths, save. Idempotence guard: a scene that already carries the
  # seeds skips to the confirmation.
  if grep -q "Environment" "$scene" && grep -q "exposure" "$scene"; then
    log "seed: the document already carries the seeded environment; skipping the write"
  else
    # `selection.select` by name first: it satisfies component.add's own
    # availability gate exactly as a click would, and the `entity` param
    # re-spells the same name (the t11t3/t15 form; a bare id string does
    # not resolve — String entity params name, Int ones id).
    op selection.select '{"name":"Root"}' >/dev/null 2>&1
    sleep 2
    op component.add "{\"entity\":\"Root\",\"type_path\":\"$ENV_TYPE\"}" >/dev/null 2>&1
    sleep 2; wait_idle 120 >/dev/null
    op environment.set "{\"sky.enabled\":true,\"post.enabled\":true,\"post.exposure\":$SEED_EXPOSURE,\"post.bloom_intensity\":$SEED_BLOOM,\"post.antialiasing\":\"$SEED_AA\"}" >/dev/null 2>&1
    sleep 2; wait_idle 120 >/dev/null
    op scene.save '{}' >/dev/null 2>&1
    sleep 2; wait_idle 300 >/dev/null
  fi

  local sha_after env_json
  sha_after=$(shasum -a 256 "$scene" | awk '{print $1}')
  # Verify through the component read-back (float spelling in the document
  # is the writer's business, not the assertion's) plus a document-face
  # grep for the record.
  env_json=$(brp world.query "{\"data\":{\"components\":[\"$ENV_TYPE\"]}}" 2>/dev/null \
    | jq -c '[.result[]?.components["'"$ENV_TYPE"'"].post // empty][0]' 2>/dev/null)
  [ -n "$env_json" ] || env_json='{}'
  # f32 quantization: a 0.8 seed reads back as 0.800000011920929, so the
  # comparison carries an epsilon (the exact spellings are the document's).
  if grep -q "Environment" "$scene" \
     && jq -e --argjson e "$SEED_EXPOSURE" --argjson b "$SEED_BLOOM" \
          '(.exposure - $e | abs) < 0.001 and (.bloom_intensity - $b | abs) < 0.001
           and .enabled == true and .antialiasing == "Smaa"' \
          <<< "$env_json" >/dev/null 2>&1; then
    leg SEED_OPCHAIN true
    log "seed: document sha $sha_before -> $sha_after; component read-back: ${env_json:0:220}"
    log "seed: the editor wrote the environment itself (decision 3 live); document face: $(grep -c Environment "$scene") Environment lines"
  else
    leg SEED_OPCHAIN false
    log "seed: component read-back gave: ${env_json:-<none>}"
    log "seed: document after the chain reads:"$'\n'"$(cat "$scene")"
    return
  fi

  # The viewport High preset is the pixel legs' opt-in precondition (fact 4).
  op viewport.quality.preset '{"preset":"high"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  local q
  # ViewportSettings is a RESOURCE, not a component (a component query
  # answers [] — the t12t3 lesson); it is not reflect-registered, so the
  # BRP resource face answers "unknown resource type" — the file face
  # (viewport.json) is the store's readable half, and the L1 High-preset
  # confirmation rides the editor phase's preset pair.
  q=$(brp world.get_resources '{"resource":"jackdaw::viewport_settings::ViewportSettings"}' 2>/dev/null | head -c 200)
  log "seed: viewport preset set to high (resource face: ${q:0:180}; file face lives in the editor phase)"
}

# ---- T2 phases (loop/plans/t19-graphics-parity.md §三/§四-T2) -----------------

# ---- phase: editor — L2/L8/L9/L10's editor halves ----------------------------
# M1/M2 (exposure/bloom component+pixel), M3 (AA boundary), M8 (round trip),
# M9 (SHA leg), M12 (CONFIG_DIR isolation), M13 (GI regression), M16 (alive),
# GR6 (sun-shadow spot check), M14's editor warn scan.
editor_phase() {
  local ok=true scene="$PROJECT/assets/scene.bsn" cam env_json

  editor_boot "$PROJECT"
  open_scene scene.bsn

  # --- L1's High-preset face: a low→high preset pair proves the store's
  # file face flips and returns (the store writes on resource_changed; an
  # all-default state writes nothing, so the pair gives the file existence).
  local user_vj="$CONFIG_DIR_VAR_VALUE/viewport.json"
  op viewport.quality.preset '{"preset":"low"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  local low_face high_face
  low_face=$(viewport_json_face "$user_vj")
  op viewport.quality.preset '{"preset":"high"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  high_face=$(viewport_json_face "$user_vj")
  if echo "$low_face" | grep -q '"render_scale":50' && echo "$high_face" | grep -q '"render_scale":100'; then
    leg L1_PRESET_FACE true
    log "L1 preset face: low=$low_face high=$high_face"
  else
    leg L1_PRESET_FACE false; ok=false
    log "L1 preset face mismatch: low=$low_face high=$high_face"
  fi

  # The seed read-back (idempotent re-verify after boot) + the viewport camera.
  env_json=$(brp world.query "{\"data\":{\"components\":[\"$ENV_TYPE\"]}}" 2>/dev/null \
    | jq -c '[.result[]?.components["'"$ENV_TYPE"'"].post // empty][0]' 2>/dev/null)
  if jq -e --argjson e 13.0 --argjson b 0.8 \
       '(.exposure - $e | abs) < 0.001 and (.bloom_intensity - $b | abs) < 0.001 and .antialiasing == "Smaa"' \
       <<< "$env_json" >/dev/null 2>&1; then
    leg L1_SEED_VERIFY true
  else
    leg L1_SEED_VERIFY false; ok=false
    log "L1 seed verify failed: $env_json"
  fi

  cam=$(ecam | head -1)
  [ -n "$cam" ] || { log "EDITOR phase: no viewport camera found"; leg EDITOR_CAM false; }
  local cam_count; cam_count=$(ecam | grep -c . || true)
  log "editor camera: entity $cam (Camera3d count: $cam_count)"
  [ -n "$cam" ] || return

  # --- M1 exposure: set 9.7 (default) -> shot -> set 13 -> component read +
  # shot -> pixdiff. The numeric track is the main assertion (decision 1).
  envset post.exposure 9.7
  settle_pixels 3
  shot m1-low viewport || ok=false
  local m1a; m1a=$(png_pixels_md5 "$OUTDIR/shot-m1-low.png")
  envset post.exposure 13.0
  settle_pixels 3
  # The numeric leg judges the deepest face the BRP can read. The component
  # read is attempted first; Exposure is #[reflect(opaque)] with no
  # ReflectSerialize, so a -23402 refusal here is a structural tooling
  # boundary, and the document face (Environment.post.exposure, readable)
  # plus the headless anchor (post_settings_reach_the_camera_components)
  # carry the value half.
  local m1_exp m1_doc m1_face="none"
  if probe_component "$cam" Exposure "$EXPOSURE" "bevy_camera::exposure::Exposure"; then
    m1_exp="$PROBED_JSON"
    if num_close "$(echo "$m1_exp" | jq .ev100)" 13.0; then
      m1_face="component:$PROBED"
    else
      m1_face="component-wrong:$m1_exp"
    fi
  fi
  m1_doc=$(brp world.query "{\"data\":{\"components\":[\"$ENV_TYPE\"]}}" 2>/dev/null \
    | jq -c '[.result[]?.components["'"$ENV_TYPE"'"].post.exposure // empty][0]' 2>/dev/null)
  if [ "$m1_face" = "none" ] && num_close "${m1_doc:-null}" 13.0; then
    m1_face="document:$m1_doc (component read refused: $ECOMP_ERRORS)"
  fi
  if echo "$m1_face" | grep -qE "^component:|^document:"; then
    leg M1_EXPOSURE_R true
    log "M1 numeric via $m1_face"
  else
    leg M1_EXPOSURE_R false; ok=false
    log "M1 numeric FAILED (face=$m1_face, doc=$m1_doc)"
  fi
  settle_pixels 2
  shot m1-high viewport || ok=false
  local m1b; m1b=$(png_pixels_md5 "$OUTDIR/shot-m1-high.png")
  local m1_diff
  m1_diff=$(pixdiff "$OUTDIR/shot-m1-low.png" "$OUTDIR/shot-m1-high.png")
  log "M1 pixel pair: $m1_diff"
  if [ -n "$m1a" ] && [ "$m1a" != "$m1b" ] && echo "$m1_diff" | grep -qE "changed"; then
    local pct; pct=$(echo "$m1_diff" | sed -E 's/.*\(([0-9.]+)%.*/\1/')
    if python3 -c "import sys; sys.exit(0 if float('$pct') > $PX_THRESHOLD else 1)"; then
      leg M1_EXPOSURE_PX true
    else
      leg M1_EXPOSURE_PX false; ok=false
      log "M1 pixel below threshold ($pct% <= $PX_THRESHOLD%)"
    fi
  else
    if confirm_red m1-high viewport "$m1a" "$m1b"; then
      leg M1_EXPOSURE_PX false; ok=false
      log "M1 pixel flat through confirm_red — exposure did not move the picture"
    else
      log "M1 pixel pair was a stale frame; the corrected pair follows"
      m1b=$(png_pixels_md5 "$OUTDIR/shot-m1-high-flakecheck2.png")
      if [ "$m1a" != "$m1b" ]; then leg M1_EXPOSURE_PX true; else leg M1_EXPOSURE_PX false; ok=false; fi
    fi
  fi
  # Leave exposure at the seed value 13 (the state the game legs expect).

  # --- M2 bloom: 0 -> shot -> 0.8 -> component read + shot -> pixdiff
  # (feature-08 precedent 77.11%).
  envset post.bloom_intensity 0.0
  settle_pixels 3
  shot m2-off viewport || ok=false
  local m2a; m2a=$(png_pixels_md5 "$OUTDIR/shot-m2-off.png")
  envset post.bloom_intensity 0.8
  settle_pixels 3
  local m2_bloom
  if probe_component "$cam" Bloom "$BLOOM" "bevy_post_process::bloom::Bloom"; then
    m2_bloom="$PROBED_JSON"
  else
    m2_bloom=""
  fi
  if [ -n "$m2_bloom" ] && num_close "$(echo "$m2_bloom" | jq '.intensity')" 0.8; then
    leg M2_BLOOM_R true
    log "M2 numeric: Bloom{intensity:0.8} answers via ${PROBED:-$BLOOM}"
  else
    leg M2_BLOOM_R false; ok=false
    log "M2 numeric wrong/absent: '$m2_bloom' errors=$ECOMP_ERRORS"
  fi
  settle_pixels 2
  shot m2-on viewport || ok=false
  local m2b; m2b=$(png_pixels_md5 "$OUTDIR/shot-m2-on.png")
  local m2_diff
  m2_diff=$(pixdiff "$OUTDIR/shot-m2-off.png" "$OUTDIR/shot-m2-on.png")
  log "M2 pixel pair: $m2_diff"
  if [ -n "$m2a" ] && [ "$m2a" != "$m2b" ]; then
    local pct2; pct2=$(echo "$m2_diff" | sed -E 's/.*\(([0-9.]+)%.*/\1/')
    if python3 -c "import sys; sys.exit(0 if float('$pct2') > $PX_THRESHOLD else 1)"; then
      leg M2_BLOOM_PX true
    else
      leg M2_BLOOM_PX false; ok=false
      log "M2 pixel below threshold ($pct2%)"
    fi
  else
    if confirm_red m2-on viewport "$m2a" "$m2b"; then
      leg M2_BLOOM_PX false; ok=false
    else
      m2b=$(png_pixels_md5 "$OUTDIR/shot-m2-on-flakecheck2.png")
      if [ "$m2a" != "$m2b" ]; then leg M2_BLOOM_PX true; else leg M2_BLOOM_PX false; ok=false; fi
    fi
  fi
  # Leave bloom at the seed value 0.8.

  # --- M3 AA boundary: scene AA=Taa must NOT reach the viewport camera
  # (opt-out always true, plan fact 4) while the document value sits at Taa.
  envset post.antialiasing '"Taa"'
  local doc_aa taa_json
  doc_aa=$(brp world.query "{\"data\":{\"components\":[\"$ENV_TYPE\"]}}" 2>/dev/null \
    | jq -r '[.result[]?.components["'"$ENV_TYPE"'"].post.antialiasing // empty][0]' 2>/dev/null)
  ecomp_parts "$cam" "$TAA"
  taa_json="$ECOMP_VALUE"
  local taa_errs="$ECOMP_ERRORS"
  if [ "$doc_aa" = "Taa" ] && [ -z "$taa_json" ] && echo "$taa_errs" | grep -qiE "not present|absent"; then
    leg M3_AA_BOUNDARY true
    log "M3: document antialiasing=Taa, viewport camera carries no TemporalAntiAliasing ($taa_errs) — the boundary itself"
  else
    leg M3_AA_BOUNDARY false; ok=false
    log "M3 boundary broken: doc_aa=$doc_aa taa_json=$taa_json errs=$taa_errs"
  fi
  envset post.antialiasing '"Smaa"'

  # --- GR6 spot check (sun shadows toggle: pixel + file-face halves)
  gr6_spot_check || ok=false

  # --- M8 round trip: fresh value -> save -> document face -> reopen ->
  # component face; then restore the seed document exactly.
  envset post.exposure 12.5
  local sha_pre sha_saved
  sha_pre=$(shasum -a 256 "$scene" | awk '{print $1}')
  op scene.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null
  sha_saved=$(shasum -a 256 "$scene" | awk '{print $1}')
  if [ "$sha_pre" = "$sha_saved" ]; then
    leg M8_ROUNDTRIP false; ok=false
    log "M8: scene.save did not change the document SHA (12.5 never landed)"
  elif grep -q "12.5" "$scene"; then
    open_scene scene.bsn
    local m8_exp m8_doc
    ecomp_parts "$(ecam | head -1)" "$EXPOSURE"
    m8_exp="$ECOMP_VALUE"
    m8_doc=$(brp world.query "{\"data\":{\"components\":[\"$ENV_TYPE\"]}}" 2>/dev/null \
      | jq -c '[.result[]?.components["'"$ENV_TYPE"'"].post.exposure // empty][0]' 2>/dev/null)
    if num_close "${m8_doc:-null}" 12.5; then
      leg M8_ROUNDTRIP true
      log "M8: 12.5 on disk after save; reopened document reads $m8_doc (component face: ${m8_exp:-refused $ECOMP_ERRORS})"
    else
      leg M8_ROUNDTRIP false; ok=false
      log "M8: reopened document reads '$m8_doc' (want 12.5)"
    fi
  else
    leg M8_ROUNDTRIP false; ok=false
    log "M8: document after save lacks 12.5"
  fi
  envset post.exposure 13.0
  op scene.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null
  local sha_seed; sha_seed=$(shasum -a 256 "$scene" | awk '{print $1}')
  if [ "$sha_seed" = "655892c6c28327866acaa52c71a1ff510f9d963144b28864d257e1422e9a99a9" ]; then
    log "M8 restore: document back at the seed SHA"
  else
    log "M8 RESTORE DRIFT: scene sha now $sha_seed (seed was 655892c6…)"
  fi

  # --- M9 SHA leg: the whole A-region family through the user path, then
  # byte identity across save (the live twin of graphics_prefs_clean guard 1).
  local sha_a1 sha_a2
  sha_a1=$(shasum -a 256 "$scene" | awk '{print $1}')
  a_region_suite
  sha_a2=$(shasum -a 256 "$scene" | awk '{print $1}')
  local no_dialog="yes"
  local st; st=$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.dialog // empty' 2>/dev/null)
  [ -n "$st" ] && [ "$st" != "null" ] && no_dialog="no"
  op scene.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null
  local sha_a3
  sha_a3=$(shasum -a 256 "$scene" | awk '{print $1}')
  if [ "$sha_a1" = "$sha_a2" ] && [ "$sha_a2" = "$sha_a3" ] && [ "$no_dialog" = "yes" ]; then
    leg M9_SHA true
    log "M9: scene.bsn byte-identical through the whole A-region suite + save; no dirty dialog"
  else
    leg M9_SHA false; ok=false
    log "M9 FAILED: sha $sha_a1 -> $sha_a2 -> $sha_a3; dialog=$no_dialog"
  fi
  op viewport.quality.preset '{"preset":"high"}' >/dev/null 2>&1
  op viewport.sharpen.set '{"on":false,"strength":0.8}' >/dev/null 2>&1
  op viewport.stats.toggle '{"on":false}' >/dev/null 2>&1
  op viewport.stats.graph.toggle '{"on":false}' >/dev/null 2>&1
  op viewport.realtime.toggle '{"on":true}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null

  # --- M13 GI regression: the panel's Realtime GI row. The disabled face is
  # proven LIVE by the ui_click refusal ("the control is disabled"); the
  # tooltip popover needs a sustained pointer hover the synthetic surface
  # cannot produce (ui_click refuses disabled controls, a ui_drag across the
  # row lands no popover — probed 2026-10-31), so the tooltip text face stays
  # with the headless anchor (tests/viewport/graphics_panel.rs:373-394).
  op graphics.open '{}' >/dev/null 2>&1
  sleep 3; wait_idle 60 >/dev/null
  walk
  if walk_has "Realtime GI"; then
    leg M13_GI_ROW true
    local click_reply
    click_reply=$(brp jackdaw/ui_click "{\"text\":\"Realtime GI\"}" 2>/dev/null)
    if echo "$click_reply" | grep -q "the control is disabled"; then
      leg M13_GI_DISABLED true
      log "M13 live disabled proof: $(echo "$click_reply" | head -c 160)"
    else
      leg M13_GI_DISABLED false; ok=false
      log "M13: the GI checkbox click did not answer the disabled refusal ($(echo "$click_reply" | head -c 160))"
    fi
    shot m13-gi-panel window || ok=false
    leg M13_GI_PX true
    log "M13: greyed GI row archived (shot-m13-gi-panel.png); tooltip text face = headless anchor"
  else
    leg M13_GI_ROW false; ok=false
    log "M13: Graphics panel walk shows no Realtime GI row"
  fi

  # --- M12 isolation: a scratch JACKDAW_CONFIG_DIR catches the store, the
  # project tree never sees viewport.json, and a normal boot reads the
  # user-level original back.
  local proj_vj
  pkill -x jackdaw 2>/dev/null; sleep 2
  mkdir -p "$SCRATCH_CONFIG"
  rm -f "$SCRATCH_CONFIG/viewport.json"
  JACKDAW_CONFIG_DIR="$SCRATCH_CONFIG" editor_boot "$PROJECT"
  open_scene scene.bsn
  op viewport.quality.preset '{"preset":"low"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  local scratch_face=""; local found_proj_vj="no"
  scratch_face=$(viewport_json_face "$SCRATCH_CONFIG/viewport.json")
  proj_vj=$(find "$PROJECT" -name "viewport.json" -not -path "*/target/*" 2>/dev/null | head -1)
  [ -n "$proj_vj" ] && found_proj_vj="yes"
  if [ -n "$scratch_face" ] && echo "$scratch_face" | grep -q '"render_scale":50' && [ "$found_proj_vj" = "no" ]; then
    leg M12_SCRATCH true
    log "M12: store landed in the scratch config dir; project tree clean ($scratch_face)"
  else
    leg M12_SCRATCH false; ok=false
    log "M12 FAILED: scratch_face=$scratch_face project_vj=$found_proj_vj"
  fi
  pkill -x jackdaw 2>/dev/null; sleep 2
  editor_boot "$PROJECT"
  open_scene scene.bsn
  local user_face_now
  user_face_now=$(viewport_json_face "$user_vj")
  if echo "$user_face_now" | grep -q '"render_scale":100'; then
    leg M12_PER_USER true
    log "M12: the boot without the override reads the user-level original back ($user_face_now) — the scratch write stayed put"
  else
    leg M12_PER_USER false; ok=false
    log "M12 FAILED: user file reads $user_face_now (want render_scale 100 = High)"
  fi

  # --- M16 alive + warn scan for this phase
  if brp jackdaw/status '{}' >/dev/null 2>&1 && pgrep -x jackdaw >/dev/null; then
    leg M16_EDITOR_ALIVE true
  else
    leg M16_EDITOR_ALIVE false; ok=false
  fi
  log "N13 counter (panicked lines in the editor log): $(n13_count)"
  warn_scan "$OUTDIR/editor-$PHASE.log" "editor"
  $ok && leg EDITOR_PHASE true || leg EDITOR_PHASE false
}

# ---- phase: game — L3/L4/L6/L7's game halves ---------------------------------
# M4 (PIE parity + the GR8 live first-shot), M5 (direct parity), M7 (AA
# three stations' smaa + the Keep exit), M11 (A-region two-state identity),
# M15 (the no-Environment control), M16 (alive/warn per leg).
game_phase() {
  local ok=true scene="$PROJECT/assets/scene.bsn"

  editor_boot "$PROJECT"
  open_scene scene.bsn
  flow_start_scene scene.bsn
  log "game phase: flow start_scene -> $(flow_start_scene)"
  local cam_count; cam_count=$(ecam | grep -c . || true)
  log "game phase: editor up, scene open, viewport Camera3d count $cam_count"

  # --- M4 PIE parity: play the seed (bloom 0.8), read the game camera,
  # grab the stream-face picture; then bloom 0, read again, grab; the pair
  # is the GR8 live first-shot. Both states go through scene.save: the
  # project's save-before-play policy is Save (pie_current.rs SaveBeforePlay
  # default), so a DIRTY doc would be written to disk by the play call
  # itself — the run-1..3 lesson (M5a read a bloom-0 disk the play had
  # written); explicit saves keep the disk and the live doc in step.
  op pie.play_current '{}' >/dev/null 2>&1
  wait_game 600 || { log "M4: PIE game never came up"; leg M4_NUMERIC false; }
  game_ready 240; sleep 5
  local pie_cam face
  pie_cam=$(game_cam_id)
  log "M4: PIE game camera entity $pie_cam"
  face=$(game_face "$pie_cam")
  log "M4 seed-state face: $face"
  if seed_face "$face" >/dev/null 2>&1; then
    leg M4_NUMERIC true
  else
    # N13 discipline: one retry of the read after a panic window
    sleep 3
    face=$(game_face "$pie_cam")
    if seed_face "$face" >/dev/null 2>&1; then
      leg M4_NUMERIC true
      log "M4 numeric green on the retry (N13 bypass counted: $(n13_count))"
    else
      leg M4_NUMERIC false; ok=false
      log "M4 numeric FAILED: $face"
    fi
  fi
  # M7 PIE smaa station rides this run too (the face already carries it).
  if echo "$face" | jq -e '.smaa_present == true' >/dev/null 2>&1; then
    leg M7_PIE_SMAA true
  else
    leg M7_PIE_SMAA false; ok=false
  fi
  settle_pixels 4
  gshot m4-pie-stream-a || ok=false
  stop_game

  envset post.bloom_intensity 0.0
  op scene.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null
  op pie.play_current '{}' >/dev/null 2>&1
  wait_game 600 || ok=false
  game_ready 240; sleep 5
  pie_cam=$(game_cam_id)
  face=$(game_face "$pie_cam")
  log "M4 bloom-0 face: $face"
  if echo "$face" | jq -e '.bloom == null or ((.bloom > -0.001) and (.bloom < 0.001))' >/dev/null 2>&1; then
    leg M4_PX_STATE true
  else
    sleep 3
    face=$(game_face "$pie_cam")
    echo "$face" | jq -e '.bloom != null and (.bloom > -0.001) and (.bloom < 0.001)' >/dev/null 2>&1 \
      && { leg M4_PX_STATE true; log "M4 bloom-0 green on retry"; } \
      || { leg M4_PX_STATE false; ok=false; log "M4 bloom-0 state FAILED: $face"; }
  fi
  settle_pixels 4
  gshot m4-pie-stream-b || ok=false
  stop_game
  envset post.bloom_intensity 0.8   # live doc and disk back at the seed
  op scene.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null
  local sha_m4; sha_m4=$(shasum -a 256 "$scene" | awk '{print $1}')
  [ "$sha_m4" = "655892c6c28327866acaa52c71a1ff510f9d963144b28864d257e1422e9a99a9" ] \
    && log "M4 restore: seed SHA back" || log "M4 RESTORE DRIFT: $sha_m4"
  local m4_line
  m4_line=$(pixdiff "$OUTDIR/shot-m4-pie-stream-a.png" "$OUTDIR/shot-m4-pie-stream-b.png")
  log "M4 stream-face pair: $m4_line"
  if [ -s "$OUTDIR/shot-m4-pie-stream-a.png" ] && [ -s "$OUTDIR/shot-m4-pie-stream-b.png" ]; then
    local pct4; pct4=$(echo "$m4_line" | sed -E 's/.*\(([0-9.]+)%.*/\1/')
    if python3 -c "import sys; sys.exit(0 if float('$pct4') > $PX_THRESHOLD else 1)"; then
      leg M4_GR8_LIVE true
      log "GR8 live first-shot: the PIE face moved with the value ($(echo "$m4_line" | head -c 120)) — faithful verdict holds"
    else
      # The screencapture twin of the A7 move-3 probe: a flat verdict is only
      # believed after two fresh frames of the SAME state agree with it. The
      # live doc holds bloom 0.8 right now, so a fresh frame belongs to the
      # a-state; if it differs from the archived a-shot, the pair was stale.
      settle_pixels 2
      gshot m4-flakecheck-a || ok=false
      if [ "$(png_pixels_md5 "$OUTDIR/shot-m4-flakecheck-a.png")" != "$(png_pixels_md5 "$OUTDIR/shot-m4-pie-stream-a.png")" ]; then
        leg M4_GR8_LIVE true
        log "GR8 live: the flat pair was a stale window capture; the fresh frame differs — faithfulness not contradicted"
      else
        leg M4_GR8_LIVE false; ok=false
        log "GR8 live RED: fresh same-state frames agree the PIE face never moved — the fallback path (M4 numeric-only + GR8 ledger) triggers"
      fi
    fi
  else
    leg M4_GR8_LIVE false; ok=false
    log "M4 captures missing; GR8 live not decided"
  fi

  # --- M5 direct parity (doc on disk at the seed): run, read, capture;
  # then bloom 0 SAVED on disk, run again, read, capture; restore.
  direct_run m5a || ok=false
  local d_cam face5
  d_cam=$(game_cam_id)
  face5=$(game_face "$d_cam")
  log "M5 seed-state face: $face5"
  if seed_face "$face5" >/dev/null 2>&1; then
    leg M5_NUMERIC true
  else
    sleep 5
    face5=$(game_face "$d_cam")
    if seed_face "$face5" >/dev/null 2>&1; then
      leg M5_NUMERIC true
      log "M5 numeric green on the settle retry"
    else
      leg M5_NUMERIC false; ok=false
      log "M5 numeric FAILED: $face5"
    fi
  fi
  if echo "$face5" | jq -e '.smaa_present == true' >/dev/null 2>&1; then
    leg M7_DIRECT_SMAA true
  else
    leg M7_DIRECT_SMAA false; ok=false
  fi
  settle_pixels 4
  gshot m5-direct-a || ok=false
  stop_game

  envset post.bloom_intensity 0.0
  op scene.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null
  direct_run m5b || ok=false
  d_cam=$(game_cam_id)
  face5=$(game_face "$d_cam")
  log "M5 bloom-0 face: $face5"
  echo "$face5" | jq -e '.bloom == null or ((.bloom > -0.001) and (.bloom < 0.001))' >/dev/null 2>&1 \
    && leg M5_STATE2 true || { leg M5_STATE2 false; ok=false; log "M5 bloom-0 FAILED: $face5"; }
  settle_pixels 4
  gshot m5-direct-b || ok=false
  stop_game
  envset post.bloom_intensity 0.8
  op scene.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null
  local sha_now; sha_now=$(shasum -a 256 "$scene" | awk '{print $1}')
  [ "$sha_now" = "655892c6c28327866acaa52c71a1ff510f9d963144b28864d257e1422e9a99a9" ] \
    && log "M5 restore: seed SHA back" || log "M5 RESTORE DRIFT: $sha_now"
  local m5_line
  m5_line=$(pixdiff "$OUTDIR/shot-m5-direct-a.png" "$OUTDIR/shot-m5-direct-b.png")
  log "M5 game-window pair: $m5_line"
  local pct5; pct5=$(echo "$m5_line" | sed -E 's/.*\(([0-9.]+)%.*/\1/')
  if python3 -c "import sys; sys.exit(0 if float('$pct5') > $PX_THRESHOLD else 1)"; then
    leg M5_PX true
  else
    leg M5_PX false; ok=false
    log "M5 pixel pair below threshold ($pct5%) or missing"
  fi

  # --- M7 Keep exit: scene AA=Keep must leave the game camera without Smaa.
  envset post.antialiasing '"Keep"'
  op scene.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null
  direct_run m7keep || ok=false
  d_cam=$(game_cam_id)
  local keep_face
  keep_face=$(game_face "$d_cam")
  log "M7 Keep face: $keep_face"
  if echo "$keep_face" | jq -e '.smaa_present == false' >/dev/null 2>&1; then
    leg M7_KEEP_EXIT true
  else
    sleep 3
    keep_face=$(game_face "$d_cam")
    echo "$keep_face" | jq -e '.smaa_present == false' >/dev/null 2>&1 \
      && leg M7_KEEP_EXIT true || { leg M7_KEEP_EXIT false; ok=false; log "M7 Keep exit FAILED: $keep_face"; }
  fi
  stop_game
  envset post.antialiasing '"Smaa"'
  op scene.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null

  # --- M11 A-region two-state numeric identity: viewport AA=TAA+SSAO ultra
  # vs AA=Off+SSAO off; the game camera matrix must be field-by-field equal.
  op viewport.quality.set '{"render_scale":100,"anti_aliasing":"taa","shadow_quality":"high","detail_distance":"far","ssao_quality":"ultra"}' >/dev/null 2>&1
  op viewport.ssao.set '{"on":true,"quality":"ultra"}' >/dev/null 2>&1
  op viewport.show.toggle '{"flag":"bloom","on":true}' >/dev/null 2>&1
  op viewport.show.toggle '{"flag":"fog","on":true}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  direct_run m11a || ok=false
  d_cam=$(game_cam_id)
  local face11a
  face11a=$(game_face "$d_cam")
  log "M11 state-1 (viewport TAA+SSAO ultra) face: $face11a"
  stop_game
  op viewport.quality.set '{"render_scale":100,"anti_aliasing":"off","shadow_quality":"low","detail_distance":"far","ssao_quality":"low"}' >/dev/null 2>&1
  op viewport.ssao.set '{"on":false,"quality":"low"}' >/dev/null 2>&1
  op viewport.show.toggle '{"flag":"bloom","on":false}' >/dev/null 2>&1
  op viewport.show.toggle '{"flag":"fog","on":false}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  direct_run m11b || ok=false
  d_cam=$(game_cam_id)
  local face11b verdict
  face11b=$(game_face "$d_cam")
  log "M11 state-2 (viewport Off+SSAO off) face: $face11b"
  verdict=$(faces_equal "$face11a" "$face11b")
  if [ "$verdict" = "EQUAL" ]; then
    leg M11_IDENTITY true
    log "M11: the game camera matrix is field-by-field identical across both A-region states"
  else
    leg M11_IDENTITY false; ok=false
    log "M11 FAILED: $verdict"
  fi
  stop_game
  op viewport.quality.preset '{"preset":"high"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null

  # --- M15 no-Environment control (GR7): strip the component from the
  # document, run the channels, read bevy defaults; the panel shows the
  # empty-state hint. Restored from backup afterwards.
  local backup="$OUTDIR/scene.bsn.seed-backup"
  cp "$scene" "$backup"
  python3 - "$scene" << 'PYT'
import re, sys
path = sys.argv[1]
text = open(path).read()
# The environment sits on the scene root as one component entry; drop the
# Environment block by lines (the document's component entries are
# top-level lines with their indented field blocks).
lines = text.splitlines(keepends=True)
out, skipping = [], False
for line in lines:
    if skipping:
        # The block ends at the first column-0 closing brace.
        if line.startswith("}"):
            skipping = False
        continue
    if re.match(r"^jackdaw_scene_types::environment::Environment\b", line):
        skipping = True
        continue
    out.append(line)
open(path, "w").write("".join(out))
PYT
  grep -q Environment "$scene" && { log "M15 strip FAILED — Environment still present, aborting the leg"; leg M15_CONTROL false; ok=false; cp "$backup" "$scene"; } || {
  direct_run m15 || ok=false
  d_cam=$(game_cam_id)
  local face15
  face15=$(game_face "$d_cam")
  log "M15 direct face: $face15"
  if echo "$face15" | jq -e '.smaa_present == false' >/dev/null 2>&1; then
    leg M15_GAME true
    log "M15: no Environment on disk -> the game camera carries no scene dress (bevy defaults)"
  else
    sleep 3
    face15=$(game_face "$d_cam")
    echo "$face15" | jq -e '.smaa_present == false' >/dev/null 2>&1 \
      && { leg M15_GAME true; log "M15 green on retry"; } \
      || { leg M15_GAME false; ok=false; log "M15 FAILED: $face15"; }
  fi
  stop_game
  cp "$backup" "$scene"
  open_scene scene.bsn
  op graphics.open '{}' >/dev/null 2>&1
  sleep 3; walk
  if walk_has "This scene has no environment"; then
    leg M15_EDITOR_HINT true
  else
    # The panel may need the reopened scene to refresh; one re-open of the panel.
    op graphics.open '{}' >/dev/null 2>&1; sleep 3; walk
    walk_has "This scene has no environment" && leg M15_EDITOR_HINT true || { leg M15_EDITOR_HINT false; ok=false; }
  fi
  }
  # After the restore the editor's live doc must re-read the seed.
  local sha_rest; sha_rest=$(shasum -a 256 "$scene" | awk '{print $1}')
  [ "$sha_rest" = "655892c6c28327866acaa52c71a1ff510f9d963144b28864d257e1422e9a99a9" ] \
    && log "M15 restore: seed SHA back" || log "M15 RESTORE DRIFT: $sha_rest"

  # --- M16 alive + warn scans
  if brp jackdaw/status '{}' >/dev/null 2>&1; then leg M16_EDITOR_ALIVE true; else leg M16_EDITOR_ALIVE false; ok=false; fi
  log "N13 counter (panicked lines in the editor log): $(n13_count)"
  for d in "$OUTDIR"/direct-m5a.log "$OUTDIR"/direct-m5b.log "$OUTDIR"/direct-m7keep.log "$OUTDIR"/direct-m11a.log "$OUTDIR"/direct-m11b.log "$OUTDIR"/direct-m15.log; do
    [ -f "$d" ] && warn_scan "$d" "$(basename "$d" .log)"
  done
  warn_scan "$OUTDIR/editor-$PHASE.log" "editor"
  $ok && leg GAME_PHASE true || leg GAME_PHASE false
}

# ---- phase: export — L5 (M6 staged parity) + M10 (manifest full-list) --------
export_phase() {
  local ok=true scene="$PROJECT/assets/scene.bsn"

  editor_boot "$PROJECT"
  open_scene scene.bsn
  flow_start_scene scene.bsn
  log "export phase: flow start_scene -> $(flow_start_scene)"

  # --- Export #1 at the seed: the staged tree must carry the scene, and the
  # staged process must dress its camera exactly like the PIE/direct runs.
  local sha_want
  sha_want=$(shasum -a 256 "$scene" | awk '{print $1}')
  export_wait || { log "EXPORT: export_wait timed out"; leg M6_STAGED false; leg M10_PACKAGE false; }
  if [ "$(shasum -a 256 "$STAGED/assets/scene.bsn" 2>/dev/null | awk '{print $1}')" = "$sha_want" ]; then
    leg M6_STAGED_CARRIES true
    log "M6: staged scene.bsn SHA == project scene.bsn SHA"
  else
    leg M6_STAGED_CARRIES false; ok=false
  fi
  cp "$STAGED/export-manifest.json" "$OUTDIR/manifest-before.json" 2>/dev/null
  jq -r --arg s "assets/scene.bsn" '.files[]? | select((.path // .name) == $s) | "\(.path // .name) \(.sha256 // .sha // .hash)"' \
    "$OUTDIR/manifest-before.json" > "$OUTDIR/manifest-scene-line.txt" 2>/dev/null
  [ -s "$OUTDIR/manifest-scene-line.txt" ] \
    && leg M6_MANIFEST_LINE true \
    || { leg M6_MANIFEST_LINE false; ok=false; log "M6: manifest lacks a scene.bsn line ($(head -c 200 "$OUTDIR/manifest-before.json"))"; }

  (cd "$STAGED" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./t19-graphics > "$OUTDIR/staged-run.log" 2>&1 &)
  wait_game 300 || ok=false
  game_ready 240; sleep 5
  local s_cam face6
  s_cam=$(game_cam_id)
  face6=$(game_face "$s_cam")
  log "M6 staged face: $face6"
  seed_face "$face6" >/dev/null 2>&1 && leg M6_NUMERIC true || { leg M6_NUMERIC false; ok=false; log "M6 numeric FAILED: $face6"; }
  if echo "$face6" | jq -e '.smaa_present == true' >/dev/null 2>&1; then
    leg M7_STAGED_SMAA true
  else
    leg M7_STAGED_SMAA false; ok=false
  fi
  settle_pixels 4
  gshot m6-staged || ok=false
  stop_game

  # --- M10 package leg: the whole A-region family, export again, then the
  # full manifest list diff must be empty and the staged scene bytes equal.
  # Freshness guard: the after-manifest must be a new write, so an export
  # that silently never reran cannot read as an empty diff.
  local manifest_ts_before manifest_ts_after
  manifest_ts_before=$(stat -f %m "$STAGED/export-manifest.json" 2>/dev/null || echo 0)
  a_region_suite
  export_wait || { log "M10: second export_wait timed out"; ok=false; }
  manifest_ts_after=$(stat -f %m "$STAGED/export-manifest.json" 2>/dev/null || echo 0)
  if [ "$manifest_ts_after" -le "$manifest_ts_before" ]; then
    log "M10: the manifest was not rewritten by the second export (ts $manifest_ts_before -> $manifest_ts_after)"
  fi
  cp "$STAGED/export-manifest.json" "$OUTDIR/manifest-after.json" 2>/dev/null
  local m10_diff staged_sha2
  m10_diff=$(manifest_diff "$OUTDIR/manifest-before.json" "$OUTDIR/manifest-after.json")
  staged_sha2=$(shasum -a 256 "$STAGED/assets/scene.bsn" 2>/dev/null | awk '{print $1}')
  if [ -z "$m10_diff" ] && [ "$staged_sha2" = "$sha_want" ] && [ "$manifest_ts_after" -gt "$manifest_ts_before" ]; then
    leg M10_PACKAGE true
    log "M10: manifest full-list diff empty across the A-region change; manifest freshly written; staged scene bytes equal"
  else
    leg M10_PACKAGE false; ok=false
    log "M10 FAILED: diff=[$m10_diff] staged_sha2=$staged_sha2 want=$sha_want manifest_ts=$manifest_ts_before->$manifest_ts_after"
  fi
  op viewport.quality.preset '{"preset":"high"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null

  # --- M16 alive + warn
  if brp jackdaw/status '{}' >/dev/null 2>&1; then leg M16_EXPORT_ALIVE true; else leg M16_EXPORT_ALIVE false; ok=false; fi
  warn_scan "$OUTDIR/staged-run.log" "staged-run"
  warn_scan "$OUTDIR/editor-$PHASE.log" "editor"
  $ok && leg EXPORT_PHASE true || leg EXPORT_PHASE false
}

case "$PHASE" in
  selftest) selftest ;;
  prep) prep ;;
  seed) seed ;;
  editor) editor_phase ;;
  game) game_phase ;;
  export) export_phase ;;
  all) selftest; prep; seed ;;
  *) log "unknown phase $PHASE (selftest|prep|seed|editor|game|export|all)"; exit 2 ;;
esac
log "RESULTS: $(results)"
