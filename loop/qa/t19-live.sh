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
EXPOSURE='bevy_camera::exposure::Exposure'
BLOOM='bevy_post_process::bloom::Bloom'
TONEMAP='bevy_camera::tonemapping::Tonemapping'
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
  sleep 3
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
export_wait() { # export_wait — game.export, held until the staged tree carries the scene
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

# ---- GR6 spot-check slot (reserved; the leg lands with T2) ------------------
# R12 (buglist:78) is in the A-region toggle family's neighbourhood. When T2
# runs the A-region legs, this slot抽查 the Sun/Point Shadows toggles: pixel
# red/green per toggle (settle_pixels first, shot before/after, pixdiff or
# crop_md5) plus the numeric half (the shadow resource the viewport quality
# drives, viewport_quality.rs:244-266,370-418). If the pixel side stays flat
# through confirm_red while the numeric side moved, that is the R12 shape:
# file the GR ledger line, do not fix here.
gr6_spot_check() {
  log "GR6 spot-check slot reserved (lands with T2's A-region legs)"
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
  # answers [] — the t12t3 lesson); world.get_resources reads it.
  q=$(brp world.get_resources '{"resource":"jackdaw::viewport_settings::ViewportSettings"}' 2>/dev/null | head -c 300)
  log "seed: viewport preset set to high (resource face: ${q:0:280})"
  gr6_spot_check
}

# ---- T2 phases (skeletons; the legs land with the matrix轮) ------------------
editor_phase() {
  log "EDITOR phase: T2 lands L2/L8/L9/L10 here (M1/M2/M3, GI regression, round trip, pixel archive) — loop/plans/t19-graphics-parity.md §三"
}
game_phase() {
  log "GAME phase: T2 lands L3/L4/L6/L7/L8 here (PIE/direct/staged parity, AA three stations, M9-M12 negatives, M15 empty state)"
}
export_phase() {
  log "EXPORT phase: T2 lands L5 here (M6 staged parity + M10 manifest_diff full-list leg)"
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
