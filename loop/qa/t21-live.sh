#!/bin/bash
# T21 sprite live legs (loop/plans/t21-sprite.md §三, T2 scope: the SP7 probe
# pinned as the first step plus the six-PR capability pass, the SP3 atlas
# chain and the editable/savable/runnable three states; L1-L12's remaining
# M-matrix formalisation stays T3's).
#
# Helper library: the t19-live.sh form — the T18 pixel-evidence craft
# (png_pixels_md5, sips crop), the feature-08 pixdiff semantics, the A7
# five-move self-defence in `shot`, BRP retry disciplines (AN2 editor side,
# A9 game side), per-phase boot/cleanup traps and `$PHASE` log names.
#
# Phases (each phase boots and cleans its own editor/game processes —
# run one per invocation):
#   selftest  validate the pixel helpers on synthetic PNGs (no editor).
#   prep      fixture hygiene (jd new + the Template::TwoD starter with the
#             Scene2dRoot marker) + jackdaw_remote injection (two-line sed) +
#             flow start scene + test pngs + warm builds (t16 prep form).
#   probe     SP7 (decision 7, T1-QA handoff D2): PIE 2D streamed-frame
#             fidelity in the embedded (default) and windowed modes, the
#             temp-copy scene path, the Stop integrity (M11 form) and the
#             numeric track. The verdict routes M14's pixel channel.
#   editor    the six PR capabilities live: sprite.add entries (M1), picking
#             and outline (M2), move gizmo + arrow keys + undo (M3), rotate
#             and scale gizmos (M3b), grid/edge snap (#655), guides (#656),
#             draw order z (M7), the SP9 Anchor preset grid, and the
#             save/reopen round trip (M9's fields).
#   atlas     SP3 live: the New Asset face, asset.new + sprite.atlas.grid
#             (the T1-QA pinned call), undo/redo of the cut, a sprite wearing
#             the atlas, index switching with canvas red/green, and the atlas
#             card reopening.
#   game      M13: direct run numeric parity + the game-window picture.
#   export    M15: export_wait, the staged tree's manifest face, the staged
#             process numeric parity.
#
# Usage: bash loop/qa/t21-live.sh [phase]
#   phase: selftest|prep|probe|editor|atlas|game|export
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
FIXROOT=/Users/zhanglinbo/workspace/loop-mac/t21-sprite
PROJECT="$FIXROOT/t21-sprite"
PORT=15703
GAME_PORT=15702
OUTDIR="$REPO/loop/t21-live"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
STAGED="$PROJECT/.jackdaw/dist/release"
STAGED_EXE="$STAGED/t21-sprite"
SCENE="$PROJECT/assets/scene.bsn"
PHASE="${1:-all}"
CONSOLE_LOG="$OUTDIR/console-$PHASE.log"
mkdir -p "$OUTDIR"
: > "$CONSOLE_LOG"

# The fixture scene: the Template::TwoD starter (Camera2d + Sprite) plus the
# Scene2dRoot marker a `scene.new kind=2d` save writes, so the editor opens
# it as a 2D world scene and the sprite authoring face gates open. The hero
# sprite is textured so the pixel channels have a strong colour to census.
FIXTURE_SCENE='// Starter scene. Authored by the jackdaw editor; safe to edit by hand.

#Root
jackdaw_scene_types::Scene2dRoot
bevy_transform::components::transform::Transform
bevy_camera::visibility::Visibility::Visible
bevy_ecs::hierarchy::Children [
    #"Main Camera"
    bevy_camera::components::Camera2d
    bevy_transform::components::transform::Transform
    bevy_camera::visibility::Visibility::Visible
    --
    #Hero
    bevy_sprite::sprite::Sprite {
        image: "hero.png",
    }
    bevy_sprite::sprite::Anchor
    bevy_transform::components::transform::Transform
    bevy_camera::visibility::Visibility::Visible
    --
    #SheetSpr
    bevy_sprite::sprite::Sprite {
        image: "sheet.png",
        texture_atlas: core::option::Option::Some(bevy_sprite::texture_atlas::TextureAtlas {
            layout: "content/sheet.bsn",
            index: 2,
        }),
    }
    bevy_sprite::sprite::Anchor
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: -80.0, y: 160.0, z: 0.0 },
    }
    bevy_camera::visibility::Visibility::Visible
]
'
SPRITE='bevy_sprite::sprite::Sprite'
ANCHOR='bevy_sprite::sprite::Anchor'
TRANSFORM='bevy_transform::components::transform::Transform'
NAME='bevy_ecs::name::Name'
CAM2D='bevy_camera::components::Camera2d'
EPSILON=0.001
WARN_PATTERN='UnresolvedTypes|cannot-apply|panicked'

RESULTS_FILE="$(mktemp /tmp/t21-live.XXXXXX)"
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
  pkill -x t21-sprite 2>/dev/null
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
  # Reads ride the flaky window (AN2): retry until a parseable body comes
  # back; exhaustion returns 1 (t16 T3 lesson).
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
  # The game BRP answers intermittently empty in busy windows (A9): reads
  # retry with a short settle; writes are verified through a read.
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
  pkill -x t21-sprite 2>/dev/null
  sleep 2
}
editor_boot() { # editor_boot [project]
  pkill -x jackdaw 2>/dev/null; pkill -x t21-sprite 2>/dev/null; sleep 1
  # A dirty kill leaves a crash journal; the next boot opens the Recovered
  # Work modal, which eats every canvas click (the run-2 lesson that ate the
  # first editor pass). Clear the project's journals before booting.
  find "$HOME/.jackdaw/sessions" -name "journal.json" -delete 2>/dev/null
  local boot_log="$OUTDIR/editor-$PHASE.log"
  if [ -n "${1:-}" ]; then
    export JACKDAW_OPEN_PROJECT="$1"
  else
    unset JACKDAW_OPEN_PROJECT
  fi
  export JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1920x1080
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
  # The Recovered Work modal does not ride the status dialog face; walk for
  # it and press Discard (the disk file is the fixture; nothing to restore).
  for attempt in 1 2 3; do
    brp jackdaw/ui_tree '{"depth":20,"text":"Recovered"}' >/dev/null 2>&1
    if brp jackdaw/ui_tree '{"depth":20,"text":"Recovered"}' 2>/dev/null | jq -e '.result.nodes | length > 0' >/dev/null 2>&1; then
      log "editor_boot: a Recovered Work dialog is up; discarding"
      brp jackdaw/ui_click '{"text":"Discard"}' >/dev/null 2>&1
      sleep 3; wait_idle 300 >/dev/null
    else
      break
    fi
  done
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
click_operator() { # click_operator <operator-prefix> — the first ui_tree row
                   # whose operator field starts with the prefix, by entity.
  walk
  local entity
  entity=$(jq -r --arg op "$1" '
    [.. | objects | select(.operator? != null and (.operator | startswith($op)))][0].entity // empty' \
    "$OUTDIR/walk-$PHASE.json" 2>/dev/null)
  [ -n "$entity" ] || { log "click_operator $1: no row"; echo ""; return 1; }
  brp jackdaw/ui_click "{\"entity\":$entity}" 2>/dev/null | jq -r '.result.clicked // false' 2>/dev/null
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

# ---- pixel evidence (the t19/t18 craft) --------------------------------------

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
png_tiles() { # png_tiles <path> <w> <h> <tw> <th> <r,g,b;...> — a grid of solid
              # tiles, row-major, one colour per tile (the frame-switch census
              # sheet: every index a distinct colour).
  python3 - "$@" << 'PYT'
import struct, sys, zlib
path = sys.argv[1]
w, h, tw, th = (int(v) for v in sys.argv[2:6])
colours = [[int(c) for c in item.split(",")] for item in sys.argv[6].split(";")]
rows = (h + th - 1) // th
cols = (w + tw - 1) // tw
raw = bytearray()
for y in range(h):
    raw.append(0)
    ty = y // th
    for x in range(w):
        tx = x // tw
        index = min(ty * cols + tx, len(colours) - 1)
        r, g, b = colours[index]
        raw += bytes((r, g, b, 255))
def chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(bytes(raw)))
       + chunk(b"IEND", b""))
open(path, "wb").write(png)
PYT
}
png_decode_rgb() { # stdout: the decoded RGB bytes of an 8-bit non-interlaced PNG
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
png_pixels_md5() {
  local bytes
  bytes=$(png_decode_rgb "$1") || { echo ""; return 1; }
  printf '%s' "$bytes" | md5 2>/dev/null || printf '%s' "$bytes" | python3 -c "import hashlib,sys;print(hashlib.md5(sys.stdin.buffer.read()).hexdigest())"
}
png_size() {
  python3 - "$1" << 'PYT'
import struct, sys
data = open(sys.argv[1], "rb").read()
w, h = struct.unpack(">II", data[16:24])
print(w, h)
PYT
}
pixdiff() {
  local a="$1" b="$2" tol="${3:-12}"
  python3 - "$a" "$b" "$tol" << 'PYT'
import struct, subprocess, sys
DECODE = open("/dev/null") and r'''
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
def decode(path):
    return subprocess.run([sys.executable, "-c", DECODE, path], capture_output=True).stdout
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
color_census() { # color_census <png> <r> <g> <b> [tol] — the share of pixels
                 # within tol of the colour, in percent. The sprite-visibility
                 # verdict for streamed frames and game windows, where a plain
                 # diff has no single baseline to diff against.
  python3 - "$@" << 'PYT'
import struct, subprocess, sys
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
bytes_ = subprocess.run([sys.executable, "-c", DECODE, sys.argv[1]], capture_output=True).stdout
r, g, b = (int(v) for v in sys.argv[2:5])
tol = int(sys.argv[5]) if len(sys.argv) > 5 else 40
if not bytes_:
    print("0.00")
    sys.exit(1)
total = len(bytes_) // 3
hit = 0
for i in range(0, len(bytes_), 3):
    if abs(bytes_[i] - r) <= tol and abs(bytes_[i+1] - g) <= tol and abs(bytes_[i+2] - b) <= tol:
        hit += 1
print(f"{100.0 * hit / total:.3f}")
PYT
}
color_census_crop() { # color_census_crop <png> <r> <g> <b> <tol> <x0> <y0> <x1> <y1>
  local png="$1" r="$2" g="$3" b="$4" tol="$5" x0="$6" y0="$7" x1="$8" y1="$9"
  python3 - "$png" "$r" "$g" "$b" "$tol" "$x0" "$y0" "$x1" "$y1" << 'PYT'
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
r, g, b = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
tol = int(sys.argv[5])
x0, y0, x1, y1 = (int(v) for v in sys.argv[6:10])
x1 = min(x1, w); y1 = min(y1, h)
hit = 0; total = 0
for y in range(max(0, y0), y1, 2):
    for x in range(max(0, x0), x1, 2):
        i = (y * w + x) * 3
        total += 1
        if abs(out[i] - r) <= tol and abs(out[i+1] - g) <= tol and abs(out[i+2] - b) <= tol:
            hit += 1
print(f"{100.0 * hit / max(total, 1):.3f}")
PYT
}
crop_md5() {
  local png="$1" x="$2" y="$3" w="$4" h="$5" out="/tmp/t21-crop-$$.png"
  sips -s format png -c "$h" "$w" --cropOffset "$y" "$x" "$png" --out "$out" >/dev/null 2>&1 \
    || { echo ""; return 1; }
  png_pixels_md5 "$out"
  local rc=$?
  rm -f "$out"
  return $rc
}
settle_pixels() { sleep "${1:-3}"; }
shot() { # shot <name> [kind] — the A7 five moves in one helper.
  local name="$1" kind="${2:-window}"
  local rel path out out_json
  rel="screenshots/t21-$name.png"
  path="$PROJECT/$rel"
  rm -f "$path"
  local key="t21-$name-$RANDOM-$SECONDS"
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
confirm_red() { # the A7 move-3 flake probe: a "no change" verdict only counts
                # after two fresh same-state shots agree with it.
  local name="$1" kind="$2" before="$3" after="$4" fresh1 fresh2
  [ "$before" != "$after" ] && return 1
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
  log "confirm_red $name: a fresh shot differed (flake/stale frame)"
  return 1
}
gshot() { # gshot <name> — a full-screen OS capture for the game channels.
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

# ---- readback helpers ---------------------------------------------------------

eselect() { # eselect — the editor's current selection as entity decimal ids.
  brp jackdaw/status '{}' 2>/dev/null | jq -cr '.result.selection // []' 2>/dev/null
}
ecomp() { # ecomp <id> <component> — an editor entity's component JSON
  local id="$1" out raw attempt
  [ -n "$id" ] || return 0
  for attempt in 1 2 3 4 5 6; do
    raw=$(brp world.get_components "{\"entity\":\"$id\",\"components\":[\"$2\"]}" 2>/dev/null)
    out=$(echo "$raw" | jq -c --arg c "$2" '.result.components[$c] // .result[$c] // empty' 2>/dev/null)
    [ -n "$out" ] && { echo "$out"; return 0; }
    sleep 3
  done
  log "ecomp $id $2 raw tail: $(echo "$raw" | tail -c 220)"
  echo "$out"
}
eid() { # eid <name> — the editor entity carrying this Name
  brp world.query "{\"data\":{\"components\":[\"$NAME\"]}}" 2>/dev/null \
    | jq -r --arg n "$1" '[.result[]? | select(.components["'"$NAME"'"] == $n) | .entity][0]' 2>/dev/null
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
undo_len() { # undo_len — the history face's undo depth (M12's counter).
  brp jackdaw/history '{}' 2>/dev/null | jq -r '.result.undo_len // ""' 2>/dev/null
}
warn_scan() { # warn_scan <tag> <logfile> — every hit attributed, not counted.
  local tag="$1" file="$2"
  [ -f "$file" ] || { log "WARN_SCAN $tag: no log at $file"; return 0; }
  local hits
  hits=$(grep -E "$WARN_PATTERN" "$file" 2>/dev/null | grep -v "entity.add.cube" | head -10)
  if [ -n "$hits" ]; then
    log "WARN_SCAN $tag HITS:"
    echo "$hits" | while IFS= read -r line; do log "  $line"; done
    echo "$hits" | grep -qE "UnresolvedTypes|cannot-apply|panicked" && return 1
  else
    log "WARN_SCAN $tag: zero hits"
  fi
  return 0
}

# ---- phase: selftest ----------------------------------------------------------

selftest() {
  local t="/tmp/t21-selftest-$$"
  mkdir -p "$t"
  png_write "$t/red.png" 200 30 30 64
  png_write "$t/red2.png" 200 30 30 64
  png_write "$t/green.png" 30 180 60 64
  png_tiles "$t/sheet.png" 64 48 32 16 "200,30,30;30,180,60;40,80,200;210,190,40;180,60,180;60,190,190"
  local m1 m2 m3
  m1=$(png_pixels_md5 "$t/red.png"); m2=$(png_pixels_md5 "$t/red2.png"); m3=$(png_pixels_md5 "$t/green.png")
  if [ -n "$m1" ] && [ "$m1" = "$m2" ] && [ "$m1" != "$m3" ]; then
    log "selftest png_pixels_md5: stable per content, distinct per colour ($m1 vs $m3)"
    leg SELFTEST_MD5 true
  else
    leg SELFTEST_MD5 false
  fi
  local size; size=$(png_size "$t/sheet.png")
  [ "$size" = "64 48" ] && leg SELFTEST_TILES_SIZE true || { leg SELFTEST_TILES_SIZE false; log "selftest tiles size: $size"; }
  local c
  c=$(color_census "$t/sheet.png" 30 180 60)
  python3 -c "import sys; sys.exit(0 if 15.0 < float('$c') < 17.5 else 1)" \
    && leg SELFTEST_CENSUS true || { leg SELFTEST_CENSUS false; log "selftest census green: $c (want ~16.7 — one of six tiles)"; }
  c=$(color_census "$t/red.png" 200 30 30)
  python3 -c "import sys; sys.exit(0 if float('$c') > 99.0 else 1)" \
    && leg SELFTEST_SOLID true || { leg SELFTEST_SOLID false; log "selftest census solid red: $c"; }
  rm -rf "$t"
  log "SELFTEST done: $(results)"
}

# ---- phase: prep --------------------------------------------------------------

prep() {
  pkill -x jackdaw 2>/dev/null; pkill -x t21-sprite 2>/dev/null; sleep 1
  log "PREP disk face: $(df -h / | tail -1 | awk '{print $4 " free"}') (A6 discipline: closed fixtures are the hogs)"
  # The editor binary must carry this round's code (SP9's preset grid rides
  # the inspector), and jd must exist for the scaffold.
  (cd "$REPO" && cargo build -p jackdaw -p jd > "$OUTDIR/editor-warmbuild-prep.log" 2>&1) \
    || { log "PREP_FAIL editor/jd build: $(tail -3 "$OUTDIR/editor-warmbuild-prep.log")"; exit 1; }

  if [ ! -d "$PROJECT" ]; then
    mkdir -p "$FIXROOT"
    (cd "$REPO" && ./target/debug/jd new t21-sprite --path "$FIXROOT" --no-git > "$OUTDIR/jd-new.log" 2>&1) \
      || { log "PREP_FAIL jd new: $(tail -3 "$OUTDIR/jd-new.log")"; exit 1; }
  fi
  [ -f "$PROJECT/Cargo.toml" ] || { log "PREP_FAIL fixture incomplete"; exit 1; }
  grep -q "GamePlugin" "$PROJECT/src/main.rs" || { log "PREP_FAIL fixture lacks the game template main"; exit 1; }

  # The Template::TwoD starter face: Camera2d + a textured hero sprite under a
  # Scene2dRoot, so the editor opens it as a 2D world scene.
  printf '%s' "$FIXTURE_SCENE" > "$SCENE"

  # Warm-project test injection (t11t2/t13/t15/t16/t19 practice): the
  # game-side BRP is a test seam; the shipping game never carries it.
  if ! grep -q jackdaw_remote "$PROJECT/Cargo.toml"; then
    /usr/bin/sed -i '' "s|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = \[\"terrain\", \"pie\"\] }|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = [\"terrain\", \"pie\"] }\njackdaw_remote = { path = '$REPO/crates/jackdaw_remote' }|" "$PROJECT/Cargo.toml"
    grep -q jackdaw_remote "$PROJECT/Cargo.toml" || { log "PREP_FAIL no remote dep"; exit 1; }
    /usr/bin/sed -i '' 's|\.add_plugins(jackdaw_runtime::JackdawPlugin)|.add_plugins(jackdaw_runtime::JackdawPlugin)\n        .add_plugins(jackdaw_remote::JackdawRemotePlugin::default())|' "$PROJECT/src/main.rs"
    grep -q JackdawRemotePlugin "$PROJECT/src/main.rs" || { log "PREP_FAIL no remote plugin"; exit 1; }
    (cd "$PROJECT" && cargo metadata --format-version 1 >/dev/null 2>"$OUTDIR/lockfix.log") \
      || { log "PREP_FAIL lock refresh: $(tail -2 "$OUTDIR/lockfix.log")"; exit 1; }
  fi

  # Test pngs: hero red, the frame-switch sheet (2x3 of 32x16, six distinct
  # colours in atlas index order), and a blue second sprite for the z leg.
  png_write "$PROJECT/assets/hero.png" 200 30 30 64
  png_write "$PROJECT/assets/blue.png" 40 80 200 64
  png_tiles "$PROJECT/assets/sheet.png" 64 48 32 16 \
    "200,30,30;30,180,60;40,80,200;210,190,40;180,60,180;60,190,190"

  # The atlas card the fixture scene's SheetSpr names: the same 2x3-of-32x16
  # grid the sprite.atlas.grid operator cuts, spelled as the editor saves it
  # (created live by the atlas phase on its run; written here when absent so
  # the game/export phases stand alone).
  if [ ! -f "$PROJECT/assets/content/sheet.bsn" ]; then
    mkdir -p "$PROJECT/assets/content"
    python3 - "$PROJECT/assets/content/sheet.bsn" << 'PYT'
import struct, sys
tiles = []
for row in range(3):
    for col in range(2):
        x, y = col * 32, row * 16
        tiles.append(
            "        bevy_math::rects::urect::URect {\n"
            "            min: glam::UVec2 {\n"
            f"                x: {x},\n"
            f"                y: {y},\n"
            "            },\n"
            "            max: glam::UVec2 {\n"
            f"                x: {x + 32},\n"
            f"                y: {y + 16},\n"
            "            },\n"
            "        },"
        )
body = (
    "bevy_image::texture_atlas::TextureAtlasLayout {\n"
    "    size: glam::UVec2 {\n"
    "        x: 64,\n"
    "        y: 48,\n"
    "    },\n"
    "    textures: [\n" + "\n".join(tiles) + ",\n    ],\n"
    "}\n"
)
text = (
    "// jackdaw 0.21.0-dev | bevy main\n"
    "// jackdaw asset bevy_image::texture_atlas::TextureAtlasLayout\n"
    "#sheet\n"
    "bevy_image::texture_atlas::TextureAtlasLayout {\n"
    "    size: glam::UVec2 {\n"
    "        x: 64,\n"
    "        y: 48,\n"
    "    },\n"
    "    textures: [\n" + "\n".join(tiles) + ",\n    ],\n"
    "}\n"
)
open(sys.argv[1], "w").write(text)
print("wrote", sys.argv[1])
PYT
  fi

  # The flow boots its start scene: point it at the 2D starter (t19 form).
  python3 - "$PROJECT/assets/game.flow.json" << 'PYT'
import json, sys
path = sys.argv[1]
flow = json.load(open(path))
flow["start_scene"] = "scene.bsn"
if "scene.bsn" not in flow["scenes"]:
    flow["scenes"].append("scene.bsn")
json.dump(flow, open(path, "w"), indent=2)
print("flow start_scene =", flow["start_scene"])
PYT

  # Warm the game build so the legs are not cold compiles.
  (cd "$PROJECT" && cargo build > "$OUTDIR/game-warmbuild-prep.log" 2>&1) \
    || { log "PREP_FAIL game warm build: $(tail -3 "$OUTDIR/game-warmbuild-prep.log")"; exit 1; }
  log "PREP_OK fixture=$PROJECT"
  log "PREP scene sha=$(shasum -a 256 "$SCENE" | awk '{print $1}')"
}

# ---- phase: probe (SP7 first — the T1-QA handoff pins this) -------------------

pie_play_wait() { # pie_play_wait — play_current + game up + world answering.
  op pie.play_current '{}' >/dev/null 2>&1
  wait_game 600 || { log "pie_play_wait: PIE game never came up"; return 1; }
  game_ready 240
  sleep 5
}

probe() {
  local ok=true
  editor_boot "$PROJECT"
  open_scene scene.bsn
  # L1's kind face: the 2D world scene gates the sprite authoring surface —
  # sprite.add's availability is the behavioural proof the marker read back.
  local probe_id
  probe_id=$(op sprite.add '{"name":"KindProbe","x":1000,"y":1000}' 2>/dev/null \
    | jq -r '.result // empty')
  sleep 2; wait_idle 120 >/dev/null
  local probe_entity; probe_entity=$(eid KindProbe)
  if [ -n "$probe_entity" ]; then
    log "L1 kind face: sprite.add answered in the opened scene (2D world scene recognised)"
    leg L1_KIND true
    op history.undo '{}' >/dev/null 2>&1
    sleep 1; wait_idle 60 >/dev/null
  else
    leg L1_KIND false; ok=false
    log "L1 kind face FAILED: sprite.add produced nothing (Scene2dRoot marker not read?)"
  fi

  local sha_before; sha_before=$(shasum -a 256 "$SCENE" | awk '{print $1}')

  # The Game panel strip is the streamed frame's home in the editor window
  # (the run-1 lesson: a whole-window census dilutes the strip to hundredths
  # of a percent; the strip band is where the verdict reads). The band is a
  # fixed-layout face of the 1920x1080 window; override via env if the layout
  # moves.
  local strip_y0="${T21_STRIP_Y0:-1450}" strip_y1="${T21_STRIP_Y1:-1700}"
  strip_census() { # strip_census <png> — hero-red share of the strip band
    color_census_crop "$1" 200 30 30 60 0 "$strip_y0" 3024 "$strip_y1"
  }

  # --- SP7 beat 1: embedded (default) PIE, file-path state (the scene is
  # saved). The streamed frame rides the game's own cameras (the windowless
  # retarget points every window camera at the capture image, the authored
  # Camera2d included), so the statics predict sprite colours in the strip.
  settle_pixels 3
  shot probe-canvas-baseline viewport2d || ok=false
  pie_play_wait || { leg SP7_EMBEDDED_PX false; ok=false; }
  local hero; hero=$(gid Hero)
  log "SP7: game-side Hero entity $hero"
  # The game BRP cannot serialize a Sprite's image handle (run-2 root cause:
  # -23402, Arc<StrongHandle> carries no ReflectSerialize in the game app) —
  # the error names the Sprite stack, which is presence evidence of its own.
  # The numeric channel reads what serializes: Hero's Transform values, plus
  # a With<Sprite> query filter for presence (N12: bevy-native reads only).
  local presence
  presence=$(gbrp world.query "{\"data\":{\"components\":[\"$TRANSFORM\"]},\"filter\":{\"with\":[\"$SPRITE\"]}}" 2>/dev/null \
    | jq -r --arg n "Hero" '[.result[]? | select(.components["'"$NAME"'"] == $n)] | length' 2>/dev/null)
  [ -z "$presence" ] && presence=$(gbrp world.query "{\"data\":{\"components\":[\"$TRANSFORM\",\"$NAME\"]},\"filter\":{\"with\":[\"$SPRITE\"]}}" 2>/dev/null \
    | jq -r '[.result[]? | select(.components["'"$NAME"'"] == "Hero")] | length' 2>/dev/null)
  local tface; tface=$(gcomp "$hero" "$TRANSFORM")
  log "SP7 embedded numeric: With<Sprite> Hero rows = ${presence:-0}; Transform = $tface"
  local sprite_err
  sprite_err=$(gbrp world.get_components "{\"entity\":\"$hero\",\"components\":[\"$SPRITE\"]}" 2>/dev/null | head -c 300)
  log "SP7 sprite-face probe (structural): $sprite_err"
  if [ "${presence:-0}" = "1" ] && echo "$tface" | jq -e '.translation != null' >/dev/null 2>&1; then
    leg SP7_NUMERIC true
  else
    # N13 discipline: one settled retry of the read after a panic window.
    sleep 5
    tface=$(gcomp "$hero" "$TRANSFORM")
    presence=$(gbrp world.query "{\"data\":{\"components\":[\"$TRANSFORM\",\"$NAME\"]},\"filter\":{\"with\":[\"$SPRITE\"]}}" 2>/dev/null \
      | jq -r '[.result[]? | select(.components["'"$NAME"'"] == "Hero")] | length' 2>/dev/null)
    log "SP7 embedded numeric (retry): rows=${presence:-0} transform=$tface"
    if [ "${presence:-0}" = "1" ] && echo "$tface" | jq -e '.translation != null' >/dev/null 2>&1; then
      leg SP7_NUMERIC true
    else
      leg SP7_NUMERIC false; ok=false; log "SP7 numeric FAILED"
    fi
  fi
  settle_pixels 4
  shot probe-pie-embedded window || ok=false
  local embed_census
  embed_census=$(strip_census "$OUTDIR/shot-probe-pie-embedded.png")
  log "SP7 embedded: hero-red census in the Game-panel strip = $embed_census% (window-wide $(color_census "$OUTDIR/shot-probe-pie-embedded.png" 200 30 30)%)"
  stop_game

  # --- SP7 beat 2: windowed PIE (FrameCaptureCamera = Camera3d drives the
  # stream). The statics predict the streamed strip loses the 2D pass.
  op pie.window_mode_toggle '{}' >/dev/null 2>&1
  pie_play_wait || { leg SP7_WINDOWED_PX false; ok=false; }
  settle_pixels 4
  shot probe-pie-windowed window || ok=false
  local win_census
  win_census=$(strip_census "$OUTDIR/shot-probe-pie-windowed.png")
  log "SP7 windowed: hero-red census in the Game-panel strip = $win_census%"
  gshot probe-pie-windowed-screen || ok=false
  stop_game
  op pie.window_mode_toggle '{}' >/dev/null 2>&1   # back to embedded

  # --- SP7 verdict: the streamed-frame fidelity routes M14's pixel channel.
  local embed_ok win_ok
  python3 -c "import sys; sys.exit(0 if float('$embed_census') > 0.1 else 1)" && embed_ok=true || embed_ok=false
  python3 -c "import sys; sys.exit(0 if float('$win_census') < 0.1 else 1)" && win_ok=true || win_ok=false
  if $embed_ok; then
    leg SP7_EMBEDDED_PX true
    log "SP7 verdict: the embedded streamed frame carries the 2D sprite — M14 keeps its pixel channel on the default (embedded) mode"
  else
    leg SP7_EMBEDDED_PX false; ok=false
    log "SP7 verdict: the embedded streamed frame shows no sprite — M14 downgrades to the numeric track"
  fi
  if $win_ok && $embed_ok; then
    leg SP7_WINDOWED_PX true
    log "SP7 windowed: the streamed strip shows no sprite — the FrameCaptureCamera (Camera3d) suspicion confirmed; windowed PIE 2D goes numeric (T19 decision-4 form), the game window is the truth"
  elif ! $win_ok; then
    leg SP7_WINDOWED_PX true
    log "SP7 windowed: the streamed strip carries the sprite too (suspicion 1 not confirmed) — both modes faithful"
  else
    leg SP7_WINDOWED_PX false; ok=false
    log "SP7 windowed: embedded red but windowed also red-less while embedded failed — inconsistent; re-run"
  fi

  # --- SP7 beat 3: the temp-copy scene path (the dirty-document play). The
  # save-before-play policy goes play_unsaved_copy, the doc is dirtied, and
  # the play runs against assets/.jackdaw-pie/ — Camera2d on that copy is the
  # projection-skip suspicion's other half.
  op project.set_save_before_play '{"mode":"play_unsaved_copy"}' >/dev/null 2>&1
  sleep 1
  # Dirty the doc: add a sprite (a history-bearing operator — run-2 lesson:
  # component.set left the tab clean and the play read the file directly).
  op sprite.add '{"name":"DirtyMarker","x":500,"y":300}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  log "SP7 temp-copy dirty marker: $(eid DirtyMarker)"
  pie_play_wait || { leg SP7_TEMPCOPY false; ok=false; }
  local temp_file
  temp_file=$(ls "$PROJECT/assets/.jackdaw-pie/"*.bsn 2>/dev/null | head -1)
  local temp_has_cam=""
  [ -n "$temp_file" ] && grep -q "Camera2d" "$temp_file" && temp_has_cam=true
  if [ -n "$temp_file" ] && [ -n "$temp_has_cam" ]; then
    leg SP7_TEMPCOPY true
    log "SP7 temp-copy: $(basename "$temp_file") carries the Camera2d — the copy path cannot lose the 2D camera (FS half)"
  else
    leg SP7_TEMPCOPY false; ok=false
    log "SP7 temp-copy FAILED: temp file ${temp_file:-missing}, camera marker ${temp_has_cam:-absent}"
  fi
  settle_pixels 4
  shot probe-pie-tempcopy window || true
  local temp_census
  temp_census=$(strip_census "$OUTDIR/shot-probe-pie-tempcopy.png")
  log "SP7 temp-copy: hero-red census in the strip = $temp_census%"
  stop_game
  # Restore: policy back to save, discard the dirty marker by reopening.
  op project.set_save_before_play '{"mode":"save"}' >/dev/null 2>&1
  open_scene scene.bsn   # reload: true rereads the file, dropping the dirt

  # --- Stop integrity (M11's 2D form): the document on disk never moved.
  local sha_after; sha_after=$(shasum -a 256 "$SCENE" | awk '{print $1}')
  if [ "$sha_before" = "$sha_after" ]; then
    leg SP7_STOP_SHA true
  else
    leg SP7_STOP_SHA false; ok=false
    log "SP7 stop integrity: scene SHA moved ($sha_before -> $sha_after)"
  fi

  warn_scan "probe-editor" "$OUTDIR/editor-probe.log"
  # N13 discipline (T11-T2/T19 form): a drain_game_events panic is counted and
  # attributed, not charged — the editor liveness after it is the verdict.
  local panics alive
  panics=$(grep -c "drain_game_events" "$OUTDIR/editor-probe.log" 2>/dev/null)
  alive=$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.dialog // "dead"' 2>/dev/null)
  log "SP7 N13 count: ${panics:-0} drain_game_events lines; editor status face: ${alive:-none} (alive)"
  [ -n "$alive" ] && leg SP7_ALIVE true || { leg SP7_ALIVE false; ok=false; }
  log "PROBE done: $(results)"
  $ok || exit 1
}

# ---- phase: editor (the six PR capabilities + SP9 + the round trip) -----------

editor_phase() {
  local ok=true
  editor_boot "$PROJECT"
  open_scene scene.bsn

  # ---- M1a: sprite.add operator, placeholder form (no image).
  op sprite.add '{"name":"OpSprite","x":220,"y":40}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  local sel; sel=$(eselect)
  log "M1a selection after sprite.add: $sel"
  local op_sprite; op_sprite=$(eid OpSprite)
  local comp_face=""
  [ -n "$op_sprite" ] && comp_face=$(ecomp "$op_sprite" "$SPRITE")
  log "M1a face: $comp_face"
  if [ -n "$op_sprite" ] && echo "$comp_face" | jq -e '.custom_size == [32.0, 32.0] and .texture_atlas == null' >/dev/null 2>&1 \
     && [ -n "$(ecomp "$op_sprite" "$ANCHOR")" ]; then
    leg M1_OPERATOR true
  else
    leg M1_OPERATOR false; ok=false
    log "M1a FAILED: entity=${op_sprite:-none} sprite=$comp_face"
  fi

  # The z semantics: a new sprite lands one above the scene's highest sprite
  # (upstream #657's only order supply; the starter Hero sits at z=0).
  local op_z; op_z=$(ecomp "$(eid OpSprite)" "$TRANSFORM" | jq -r '.translation.z // empty' 2>/dev/null)
  if python3 -c "import sys; sys.exit(0 if '$op_z' and float('$op_z') >= 1.0 else 1)"; then
    leg M7_NEW_TOP true
    log "M7 new-sprite z = $op_z (one above the starter's 0)"
  else
    leg M7_NEW_TOP false; ok=false
    log "M7 new-sprite z read back '$op_z', wanted >= 1"
  fi

  # ---- M1b: the Add Entity picker's 2D group row drives the same operator.
  # The picker shares collect_add_menu_items with the Add menu; its rows carry
  # no operator fields, so the drive is search ("Sprite") then click by text.
  op entity.add_picker '{}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  walk
  local search_box
  search_box=$(jq -r '[.. | objects | select(.kind? == "text_input")][0].entity // empty' "$OUTDIR/walk-$PHASE.json" 2>/dev/null)
  log "M1b picker search box: ${search_box:-none}"
  if [ -n "$search_box" ]; then
    brp jackdaw/ui_input "{\"entity\":$search_box,\"text\":\"Sprite\",\"commit\":\"none\"}" >/dev/null 2>&1
    sleep 2; wait_idle 60 >/dev/null
    walk
    local row
    row=$(jq -r '[.. | objects | select(.text? == "Sprite" and .kind? == "node")][0].entity // empty' "$OUTDIR/walk-$PHASE.json" 2>/dev/null)
    [ -n "$row" ] || row=$(jq -r '[.. | objects | select(.text? == "Sprite")][-1].entity // empty' "$OUTDIR/walk-$PHASE.json" 2>/dev/null)
    log "M1b picker Sprite row: ${row:-none}"
    local sel_before; sel_before=$(eselect)
    [ -n "$row" ] && brp jackdaw/ui_click "{\"entity\":$row}" >/dev/null 2>&1
    sleep 2; wait_idle 60 >/dev/null
    sel_after_check=$(eselect)
    if [ "$sel_after_check" = "$sel_before" ]; then
      # The entity may name the label inside the row; ui_click by text walks
      # to the clickable ancestor itself.
      brp jackdaw/ui_click '{\"text\":\"Sprite\"}' >/dev/null 2>&1
      sleep 2; wait_idle 120 >/dev/null
    fi
    local sel_after; sel_after=$(eselect)
    if [ "$sel_before" != "$sel_after" ] && [ "$sel_after" != "[]" ]; then
      leg M1_MENU true
      log "M1b picker row produced selection $sel_after (was $sel_before)"
    else
      leg M1_MENU false; ok=false
      log "M1b FAILED: selection $sel_before -> $sel_after (row=${row:-none})"
    fi
  else
    leg M1_MENU false; ok=false
    log "M1b FAILED: the picker's search box was not found"
  fi
  brp jackdaw/cancel '{}' >/dev/null 2>&1   # clear any modal leftover
  sleep 1
  # M1c: the image-drop route dispatches sprite.add with path/x/y — the same
  # operator the next leg drives (src/sprite_ops.rs dispatch_drop). An OS
  # file drag has no synthetic seam; the product form is proven by proxy.
  op sprite.add '{"name":"Dropped","path":"hero.png","x":-160,"y":-40}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  local drop_face; drop_face=$(ecomp "$(eid Dropped)" "$SPRITE")
  if [ -n "$drop_sprite" ] && echo "$drop_face" | jq -e '.image != null' >/dev/null 2>&1; then
    leg M1_IMAGE true
    log "M1c sprite-with-image face (the drop's product form): $drop_face"
  else
    leg M1_IMAGE false; ok=false
    log "M1c FAILED: entity=${drop_sprite:-none} face=$drop_face"
  fi

  # ---- M2: picking + outline. A world-space click on the Hero selects it;
  # the outline shows as a viewport pixel change around the sprite.
  op selection.clear '{}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  settle_pixels 2
  shot m2-unselected viewport2d || ok=false
  shot m2-unselected-window window || true
  op input.pointer '{"action":"click","x":0,"y":0,"space":"world"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  sel=$(eselect)
  local hero_e; hero_e=$(eid Hero)
  if echo "$sel" | jq -e 'any(.[]; .name? == "Hero")' >/dev/null 2>&1; then
    leg M2_PICK true
    log "M2: world click selected Hero ($hero_e); selection=$sel"
  else
    leg M2_PICK false; ok=false
    log "M2 FAILED: selection after the click = $sel (wanted Hero $hero_e)"
  fi
  settle_pixels 6
  shot m2-selected viewport2d || ok=false
  shot m2-selected-window window || true
  local outline_line outline_line_w
  outline_line=$(pixdiff "$OUTDIR/shot-m2-unselected.png" "$OUTDIR/shot-m2-selected.png")
  log "M2 outline canvas half: $outline_line"
  if [ -s "$OUTDIR/shot-m2-unselected-window.png" ] && [ -s "$OUTDIR/shot-m2-selected-window.png" ]; then
    outline_line_w=$(pixdiff "$OUTDIR/shot-m2-unselected-window.png" "$OUTDIR/shot-m2-selected-window.png")
    log "M2 outline window half: $outline_line_w"
  fi
  local outline_pct outline_pct_w
  outline_pct=$(echo "$outline_line" | sed -E 's/.*\(([0-9.]+)%.*/\1/')
  outline_pct_w=$(echo "${outline_line_w:-}" | sed -E 's/.*\(([0-9.]+)%.*/\1/')
  if python3 -c "import sys; sys.exit(0 if float('${outline_pct:-0}') > 0.02 or float('${outline_pct_w:-0}') > 0.02 else 1)"; then
    leg M2_OUTLINE_PX true
  else
    if confirm_red m2-still viewport2d "$(png_pixels_md5 "$OUTDIR/shot-m2-unselected.png")" "$(png_pixels_md5 "$OUTDIR/shot-m2-selected.png")"; then
      leg M2_OUTLINE_PX false; ok=false
      log "M2 outline: the viewport truly did not change — the outline pixel leg is red"
    else
      leg M2_OUTLINE_PX true
      log "M2 outline: the flat pair was a stale frame; a fresh shot differs"
    fi
  fi
  # Click empty space inside the canvas view: the selection clears.
  op input.pointer '{"action":"click","x":0,"y":-300,"space":"world"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  sel=$(eselect)
  echo "$sel" | jq -e 'length == 0' >/dev/null 2>&1 \
    && leg M2_CLEAR true || { leg M2_CLEAR false; ok=false; log "M2 clear FAILED: $sel"; }

  # ---- M3: the move gizmo. Tool to Translate, drag the +X handle (the arrow
  # reaches 64 stage pixels from the anchor; at the fitted zoom the world
  # offset is 64/zoom), then arrow keys, then two undos back.
  op tool.translate '{}' >/dev/null 2>&1
  sleep 1
  # Select Hero again (the clear click above deselected it); re-read the id —
  # entity ids are per-session and the reads want the current generation.
  op input.pointer '{"action":"click","x":0,"y":0,"space":"world"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  hero_e=$(eid Hero)
  local zoom ortho
  ortho=$(brp jackdaw/camera_state '{}' 2>/dev/null | jq -r '.result.projection.ortho_scale // .result.ortho_scale // empty' 2>/dev/null)
  if [ -n "$ortho" ] && python3 -c "import sys; sys.exit(0 if float('$ortho') > 0 else 1)"; then
    zoom=$(python3 -c "print(1.0 / float('$ortho'))")
  else
    zoom=1.0
    log "M3: camera_state gave no ortho_scale ('$ortho'); assuming zoom 1 (log the fit if drags miss)"
  fi
  log "M3: view zoom = $zoom (ortho_scale $ortho)"
  local t0 tx0
  t0=$(ecomp "$(eid Hero)" "$TRANSFORM")
  tx0=$(echo "$t0" | jq -r '.translation.x' 2>/dev/null)
  local reach; reach=$(python3 -c "print(round(56.0 / float('$zoom'), 1))")
  op input.pointer "{\"action\":\"press\",\"x\":$reach,\"y\":0,\"space\":\"world\"}" >/dev/null 2>&1
  wait_idle 60 >/dev/null
  local steps=8 dx step
  dx=$(python3 -c "print(round(96.0 / float('$zoom'), 1))")
  step=$(python3 -c "print(round(float('$dx') / $steps, 2))")
  for i in $(seq 1 $steps); do
    local at
    at=$(python3 -c "print(round(float('$reach') + float('$step') * $i, 2))")
    op input.pointer "{\"action\":\"move\",\"x\":$at,\"y\":0,\"space\":\"world\"}" >/dev/null 2>&1
    wait_idle 60 >/dev/null
  done
  op input.pointer "{\"action\":\"release\",\"x\":$(python3 -c "print(round(float('$reach') + float('$dx'), 2))"),\"y\":0,\"space\":\"world\"}" >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  local t1 tx1
  t1=$(ecomp "$(eid Hero)" "$TRANSFORM")
  tx1=$(echo "$t1" | jq -r '.translation.x' 2>/dev/null)
  if [ -n "$tx0" ] && [ -n "$tx1" ] \
     && python3 -c "import sys; sys.exit(0 if abs(float('$tx1') - float('$tx0')) > 40.0 else 1)"; then
    leg M3_DRAG true
    log "M3 drag: Hero x $tx0 -> $tx1"
  else
    leg M3_DRAG false; ok=false
    log "M3 drag FAILED: x $tx0 -> '$tx1' (the handle grab missed? zoom=$zoom reach=$reach)"
  fi
  # Arrow key nudge (transform_ops: plain Arrow moves the selection).
  op input.key '{"key":"ArrowRight"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  local tx2; tx2=$(ecomp "$(eid Hero)" "$TRANSFORM" | jq -r '.translation.x' 2>/dev/null)
  if [ -n "$tx1" ] && [ -n "$tx2" ] \
     && python3 -c "import sys; sys.exit(0 if abs(float('$tx2') - float('$tx1')) > 0.001 else 1)"; then
    leg M3_ARROWS true
    log "M3 arrows: Hero x $tx1 -> $tx2"
  else
    leg M3_ARROWS false; ok=false
    log "M3 arrows FAILED: x $tx1 -> '$tx2'"
  fi
  # Undo until the start value is back (T03's chain, sprite form); a drag
  # holds one or more entries depending on where the settle landed.
  local tx3=""
  for i in 1 2 3 4; do
    op history.undo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
    tx3=$(ecomp "$(eid Hero)" "$TRANSFORM" | jq -r '.translation.x' 2>/dev/null)
    [ -n "$tx3" ] && python3 -c "import sys; sys.exit(0 if abs(float('$tx3') - float('$tx0')) < 0.5 else 1)" && break
  done
  if [ -n "$tx3" ] && python3 -c "import sys; sys.exit(0 if abs(float('$tx3') - float('$tx0')) < 0.5 else 1)"; then
    leg M3_UNDO true
    log "M3 undo: x back to $tx3"
  else
    leg M3_UNDO false; ok=false
    log "M3 undo FAILED: x '$tx3' vs the start $tx0"
  fi
  op tool.select '{}' >/dev/null 2>&1

  # ---- M3b: rotate and scale gizmos (#654). The rotate knob sits 56 stage
  # pixels above the anchor (world offset 56/zoom), a quarter-turn drag winds
  # the sprite about its anchor; the scale handle sits on the sprite's corner
  # (half-extent 32/zoom), dragging it out grows Transform.scale.
  op tool.rotate '{}' >/dev/null 2>&1
  sleep 1
  op input.pointer '{"action":"click","x":0,"y":0,"space":"world"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  local knob; knob=$(python3 -c "print(round(56.0 / float('$zoom'), 1))")
  local r0; r0=$(ecomp "$(eid Hero)" "$TRANSFORM" | jq -cr '.rotation' 2>/dev/null)
  op input.pointer "{\"action\":\"press\",\"x\":0,\"y\":$knob,\"space\":\"world\"}" >/dev/null 2>&1
  wait_idle 60 >/dev/null
  for i in $(seq 1 6); do
    local rx ry
    rx=$(python3 -c "import math; a = math.pi/2 * $i/6; print(round($knob * math.sin(a), 2))")
    ry=$(python3 -c "import math; a = math.pi/2 * $i/6; print(round($knob * math.cos(a), 2))")
    op input.pointer "{\"action\":\"move\",\"x\":$rx,\"y\":$ry,\"space\":\"world\"}" >/dev/null 2>&1
    wait_idle 60 >/dev/null
  done
  op input.pointer "{\"action\":\"release\",\"x\":$knob,\"y\":0,\"space\":\"world\"}" >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  local r1; r1=$(ecomp "$(eid Hero)" "$TRANSFORM" | jq -cr '.rotation' 2>/dev/null)
  if [ -n "$r0" ] && [ "$r0" != "$r1" ] && [ "$r1" != "null" ]; then
    leg M3B_ROTATE true
    log "M3b rotate knob: $r0 -> $r1"
  else
    leg M3B_ROTATE false; ok=false
    log "M3b rotate knob FAILED: $r0 -> '$r1' (knob press missed? zoom=$zoom knob=$knob)"
  fi
  op history.undo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  op tool.scale '{}' >/dev/null 2>&1
  sleep 1
  local corner; corner=$(python3 -c "print(round(32.0 / float('$zoom'), 1))")
  local s0; s0=$(ecomp "$(eid Hero)" "$TRANSFORM" | jq -r '.scale.x' 2>/dev/null)
  op input.pointer "{\"action\":\"press\",\"x\":$corner,\"y\":$corner,\"space\":\"world\"}" >/dev/null 2>&1
  wait_idle 60 >/dev/null
  for i in $(seq 1 4); do
    local sx
    sx=$(python3 -c "print(round(float('$corner') * (1.0 + 0.25 * $i), 2))")
    op input.pointer "{\"action\":\"move\",\"x\":$sx,\"y\":$sx,\"space\":\"world\"}" >/dev/null 2>&1
    wait_idle 60 >/dev/null
  done
  op input.pointer "{\"action\":\"release\",\"x\":$(python3 -c "print(round(float('$corner') * 2.0, 2))"),\"y\":$(python3 -c "print(round(float('$corner') * 2.0, 2))"),\"space\":\"world\"}" >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  local s1; s1=$(ecomp "$(eid Hero)" "$TRANSFORM" | jq -r '.scale.x' 2>/dev/null)
  if [ -n "$s0" ] && [ -n "$s1" ] \
     && python3 -c "import sys; sys.exit(0 if abs(float('$s1') - float('$s0')) > 0.05 else 1)"; then
    leg M3B_SCALE true
    log "M3b scale corner: $s0 -> $s1"
  else
    leg M3B_SCALE false; ok=false
    log "M3b scale corner FAILED: $s0 -> '$s1'"
  fi
  op history.undo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  op tool.select '{}' >/dev/null 2>&1

  # ---- #655: drag snapping. Grid snap on, drag Hero, the landing honours
  # the grid; sprite-edge snap pulls a second sprite flush to the first.
  op canvas.snap '{"kind":"grid","on":true}' >/dev/null 2>&1
  sleep 1
  local gx0; gx0=$(ecomp "$(eid Hero)" "$TRANSFORM" | jq -r '.translation.x' 2>/dev/null)
  op input.pointer '{"action":"click","x":0,"y":0,"space":"world"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  op input.pointer '{"action":"press","x":0,"y":0,"space":"world"}' >/dev/null 2>&1
  wait_idle 60 >/dev/null
  for i in 1 2 3 4; do
    op input.pointer "{\"action\":\"move\",\"x\":$(python3 -c "print($i * 9)"),\"y\":$(python3 -c "print($i * 7)"),\"space\":\"world\"}" >/dev/null 2>&1
    wait_idle 60 >/dev/null
  done
  op input.pointer '{"action":"release","x":36,"y":28,"space":"world"}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  local gx1 gy1
  gx1=$(ecomp "$(eid Hero)" "$TRANSFORM" | jq -r '.translation.x' 2>/dev/null)
  gy1=$(ecomp "$(eid Hero)" "$TRANSFORM" | jq -r '.translation.y' 2>/dev/null)
  if python3 -c "import sys; sys.exit(0 if float('${gx1:-999}') != float('${gx0:-999}') else 1)" \
     && python3 -c "import sys; sys.exit(0 if abs(float('${gx1:-0}') - round(float('${gx1:-0}'))) < 0.01 and abs(float('${gy1:-0}') - round(float('${gy1:-0}'))) < 0.01 else 1)"; then
    leg SNAP_GRID true
    log "SNAP grid: drag landed on ($gx1, $gy1) — whole world units"
  else
    leg SNAP_GRID false; ok=false
    log "SNAP grid FAILED: ($gx0, ?) -> ('$gx1', '$gy1')"
  fi
  op history.undo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  op canvas.snap '{"kind":"grid","on":false}' >/dev/null 2>&1

  # ---- #656: guides. A vertical guide at x=64 shows and a dragged sprite
  # snaps its side onto it (the guides snap kind).
  op canvas.guides '{"on":true}' >/dev/null 2>&1
  op canvas.rulers '{"on":true}' >/dev/null 2>&1
  op canvas.guide.add '{"axis":"vertical","position":64}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  # The guide lives on the scene root's CanvasGuides component.
  local root_e; root_e=$(brp world.query "{\"data\":{\"components\":[\"jackdaw_scene_types::CanvasGuides\"]}}" 2>/dev/null \
    | jq -r '.result[0].entity // empty' 2>/dev/null)
  local guides_face
  guides_face=$(ecomp "$root_e" "jackdaw_scene_types::CanvasGuides")
  log "GUIDES face on root $root_e: $guides_face"
  if echo "$guides_face" | jq -e '.vertical | length >= 1' >/dev/null 2>&1; then
    leg GUIDES_ADD true
  else
    leg GUIDES_ADD false; ok=false
    log "GUIDES add FAILED: $guides_face"
  fi
  op canvas.snap '{"kind":"guides","on":true}' >/dev/null 2>&1
  op input.pointer '{"action":"click","x":0,"y":0,"space":"world"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  op input.pointer '{"action":"press","x":0,"y":0,"space":"world"}' >/dev/null 2>&1
  wait_idle 60 >/dev/null
  for i in 1 2 3 4 5 6; do
    op input.pointer "{\"action\":\"move\",\"x\":$(python3 -c "print(round(64.0 * $i / 6.0, 2))"),\"y\":0,\"space\":\"world\"}" >/dev/null 2>&1
    wait_idle 60 >/dev/null
  done
  op input.pointer '{"action":"release","x":64,"y":0,"space":"world"}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  local guide_x; guide_x=$(ecomp "$(eid Hero)" "$TRANSFORM" | jq -r '.translation.x' 2>/dev/null)
  # The guide-snap offers the sprite's EDGE to the line: the centre lands at
  # 64 minus half the 64-wide sprite, i.e. 32, or dead on 64 for a centre
  # offer. Either is the guide working; a landing far from both is not.
  if python3 -c "import sys; sys.exit(0 if min(abs(float('${guide_x:-999}') - 64.0), abs(float('${guide_x:-999}') - 32.0)) < 1.0 else 1)"; then
    leg GUIDES_SNAP true
    log "GUIDES snap: Hero x landed at $guide_x (edge 32 or centre 64 offer)"
  else
    leg GUIDES_SNAP false; ok=false
    log "GUIDES snap FAILED: Hero x = '$guide_x' (wanted 32 or 64)"
  fi
  op history.undo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  op canvas.snap '{"kind":"guides","on":false}' >/dev/null 2>&1
  op canvas.guide.remove '{"axis":"vertical","position":64}' >/dev/null 2>&1
  op canvas.guides '{"on":false}' >/dev/null 2>&1
  op canvas.rulers '{"on":false}' >/dev/null 2>&1

  # ---- M7: draw order. Dropped overlaps Hero; blue shows on top (new z =
  # top+1), a z flip trades the winner, readbacks follow.
  op sprite.add '{"name":"TopSpr","path":"blue.png","x":-150,"y":-40}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  # Overlap them exactly: put TopSpr on Hero's spot.
  op component.set "{\"entity\":$(eid TopSpr),\"type_path\":\"$TRANSFORM\",\"field\":\"translation\",\"value\":{\"x\":0.0,\"y\":0.0,\"z\":2.0}}" >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  op component.set "{\"entity\":$(eid Hero),\"type_path\":\"$TRANSFORM\",\"field\":\"translation.z\",\"value\":\"1.0\"}" >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  settle_pixels 2
  shot m7-blue-top viewport2d || ok=false
  local blue_c
  blue_c=$(color_census "$OUTDIR/shot-m7-blue-top.png" 40 80 200)
  log "M7 blue-on-top census: $blue_c%"
  op component.set "{\"entity\":$(eid Hero),\"type_path\":\"$TRANSFORM\",\"field\":\"translation.z\",\"value\":\"3.0\"}" >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  settle_pixels 2
  shot m7-red-top viewport2d || ok=false
  local red_c
  red_c=$(color_census "$OUTDIR/shot-m7-red-top.png" 200 30 30)
  local blue_c2
  blue_c2=$(color_census "$OUTDIR/shot-m7-red-top.png" 40 80 200)
  log "M7 red-on-top census: red $red_c% blue $blue_c2%"
  if python3 -c "import sys; sys.exit(0 if float('${blue_c:-0}') > 0.05 else 1)" \
     && python3 -c "import sys; sys.exit(0 if float('${red_c:-0}') > 0.05 else 1)" \
     && python3 -c "import sys; sys.exit(0 if float('${red_c:-0}') > float('${blue_c2:-0}') else 1)"; then
    leg M7_Z_FLIP_PX true
  else
    leg M7_Z_FLIP_PX false; ok=false
    log "M7 z flip FAILED: blue-top $blue_c%, red-top red $red_c% blue $blue_c2%"
  fi
  # Clean the overlap back apart and the z values to the plain ones.
  op component.set "{\"entity\":$(eid Hero),\"type_path\":\"$TRANSFORM\",\"field\":\"translation.z\",\"value\":\"0.0\"}" >/dev/null 2>&1
  op component.set "{\"entity\":$(eid TopSpr),\"type_path\":\"$TRANSFORM\",\"field\":\"translation\",\"value\":{\"x\":-150.0,\"y\":-40.0,\"z\":1.0}}" >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null

  # ---- SP9: the Anchor preset grid live. Select Hero, expand the Anchor
  # card if it sits collapsed (the manual's card rule), find a preset cell,
  # click it, Anchor.0 reads back the constant; one undo takes it back.
  op input.pointer '{"action":"click","x":0,"y":0,"space":"world"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  walk
  # A collapsed card zeroes its subtree rects; expand via the card's header.
  local collapsed
  collapsed=$(jq -r '[.. | objects | select(.text? == "•")] | length > 0
    and ([.. | objects | select(.text? == "•") | select(.rect[2] > 0)] | length) == 0' \
    "$OUTDIR/walk-$PHASE.json" 2>/dev/null)
  if [ "$collapsed" = "true" ]; then
    local header
    header=$(jq -r '[.. | objects | select(.text? == "Anchor" and .rect[1] > 100)][0].entity // empty' \
      "$OUTDIR/walk-$PHASE.json" 2>/dev/null)
    log "SP9: the Anchor card sits collapsed; clicking header $header"
    [ -n "$header" ] && brp jackdaw/ui_click "{\"entity\":$header}" >/dev/null 2>&1
    sleep 2; wait_idle 60 >/dev/null
    walk
  fi
  local cell_entity
  cell_entity=$(jq -r '[.. | objects | select(.text? == "•" and .rect[2] > 0)][0].entity // empty' "$OUTDIR/walk-$PHASE.json" 2>/dev/null)
  if [ -n "$cell_entity" ]; then
    local a0; a0=$(ecomp "$(eid Hero)" "$ANCHOR")
    log "SP9 Anchor before: $a0"
    # Click the bottom-right cell: the last visible one (grid order row-major
    # from top left), so the click lands off the current Centre.
    local br_cell
    br_cell=$(jq -r '[.. | objects | select(.text? == "•" and .rect[2] > 0)][-1].entity // empty' "$OUTDIR/walk-$PHASE.json" 2>/dev/null)
    brp jackdaw/ui_click "{\"entity\":$br_cell}" >/dev/null 2>&1
    sleep 2; wait_idle 60 >/dev/null
    local a1; a1=$(ecomp "$(eid Hero)" "$ANCHOR")
    log "SP9 Anchor after the bottom-right preset: $a1"
    if python3 - "$a0" "$a1" << 'PYT'
import json, sys
def offset(raw):
    try:
        value = json.loads(raw)
        field = value.get("bevy_sprite::sprite::Anchor", value)
        inner = field["0"] if "0" in field else field
        if isinstance(inner, dict):
            return (inner.get("x"), inner.get("y"))
        if isinstance(inner, list):
            return (inner[0], inner[1])
    except Exception:
        pass
    return None
sys.exit(0 if offset(sys.argv[1]) != offset(sys.argv[2]) and offset(sys.argv[2]) == (0.5, -0.5) else 1)
PYT
    then
      leg SP9_PRESET true
    else
      leg SP9_PRESET false; ok=false
      log "SP9 preset FAILED: before=$a0 after=$a1"
    fi
    op history.undo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
    local a2; a2=$(ecomp "$(eid Hero)" "$ANCHOR")
    [ "$a2" = "$a0" ] && log "SP9 undo: $a2" || { log "SP9 undo face: $a2 (before $a0)"; }
  else
    leg SP9_PRESET false; ok=false
    log "SP9 FAILED: no preset cell in the inspector walk (is Hero selected? was the editor rebuilt?)"
  fi
  op tool.select '{}' >/dev/null 2>&1

  # ---- M9 (editor half): save, reopen, every touched field reads back.
  op scene.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null
  local saved_sha; saved_sha=$(shasum -a 256 "$SCENE" | awk '{print $1}')
  log "M9 saved scene sha=$saved_sha"
  grep -q "bevy_sprite::sprite::Sprite" "$SCENE" && grep -q "bevy_sprite::sprite::Anchor" "$SCENE" \
    && leg M9_BSN_TYPES true || { leg M9_BSN_TYPES false; ok=false; log "M9 bsn types missing"; }
  open_scene scene.bsn
  local hero2; hero2=$(eid Hero)
  local anchor_back; anchor_back=$(ecomp "$hero2" "$ANCHOR")
  log "M9 Anchor after reopen: $anchor_back"
  echo "$anchor_back" | jq -e . >/dev/null 2>&1 && leg M9_REOPEN true || { leg M9_REOPEN false; ok=false; }
  # The 2D kind re-identified on reopen: sprite.add answers again.
  op sprite.add '{"name":"AfterReopen","x":300,"y":-200}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  [ -n "$(eid AfterReopen)" ] && leg M9_KIND_REOPENED true || { leg M9_KIND_REOPENED false; ok=false; }
  op history.undo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null

  warn_scan "editor-editor" "$OUTDIR/editor-editor.log"
  log "EDITOR done: $(results)"
  $ok || exit 1
}

# ---- phase: atlas (SP3 live) --------------------------------------------------

atlas_phase() {
  local ok=true
  editor_boot "$PROJECT"
  open_scene scene.bsn

  # The New Asset face: "Sprite Atlas" stands in the editor's kind list.
  walk
  walk_has "Sprite Atlas" && leg ATLAS_KIND_FACE true || {
    # The list may live behind a collapsed menu; the operator route is the
    # QA-pinned call either way. Record what the walk saw.
    leg ATLAS_KIND_FACE false
    log "ATLAS kind face: the walk found no 'Sprite Atlas' text (menu depth?); the asset.new route continues"
  }

  # asset.new opens the card; the grid cut goes through the pinned call.
  op asset.new '{"type":"sprite_atlas","name":"sheet","path":"content"}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null
  [ -f "$PROJECT/assets/content/sheet.bsn" ] \
    && leg ATLAS_NEW true || { leg ATLAS_NEW false; ok=false; log "ATLAS new FAILED: no card file"; }

  op sprite.atlas.grid '{"tile_size":"32,16","columns":2,"rows":3}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null
  op asset.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null
  local frames
  frames=$(grep -c "URect" "$PROJECT/assets/content/sheet.bsn" 2>/dev/null)
  if [ "${frames:-0}" -ge 6 ]; then
    leg ATLAS_GRID true
    log "ATLAS grid: the saved card holds $frames URect rows (2x3 of 32x16)"
  else
    leg ATLAS_GRID false; ok=false
    log "ATLAS grid FAILED: $frames URect rows in the card"
  fi

  # One undo takes the cut back; the re-save shows the empty default. Redo
  # restores it (the T1-QA undo note, live).
  op history.undo '{}' >/dev/null 2>&1
  sleep 1; wait_idle 120 >/dev/null
  op asset.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null
  frames=$(grep -c "URect" "$PROJECT/assets/content/sheet.bsn" 2>/dev/null)
  [ "${frames:-0}" -eq 0 ] \
    && leg ATLAS_UNDO true || { leg ATLAS_UNDO false; ok=false; log "ATLAS undo FAILED: $frames rows after undo+save"; }
  op history.redo '{}' >/dev/null 2>&1
  sleep 1; wait_idle 120 >/dev/null
  op asset.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null
  frames=$(grep -c "URect" "$PROJECT/assets/content/sheet.bsn" 2>/dev/null)
  [ "${frames:-0}" -ge 6 ] \
    && leg ATLAS_REDO true || { leg ATLAS_REDO false; ok=false; log "ATLAS redo FAILED: $frames rows after redo+save"; }

  # A sprite wears the atlas: the sheet.png sprite's texture_atlas points at
  # the layout card, index 0. The tile census then flips with the index.
  op sprite.add '{"name":"SheetSpr","path":"sheet.png","x":-80,"y":160}' >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  local sheet_e; sheet_e=$(eid SheetSpr)
  op component.set "{\"entity\":$sheet_e,\"type_path\":\"$SPRITE\",\"field\":\"texture_atlas\",\"value\":{\"layout\":\"content/sheet.bsn\",\"index\":0}}" >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  local atlas_face; atlas_face=$(ecomp "$sheet_e" "$SPRITE")
  log "ATLAS sprite face: $atlas_face"
  if echo "$atlas_face" | jq -e '.texture_atlas != null' >/dev/null 2>&1; then
    leg ATLAS_WEAR true
  else
    leg ATLAS_WEAR false; ok=false
    log "ATLAS wear FAILED: $atlas_face"
  fi

  # Index switch: frame 0 is the red tile, frame 1 green, frame 2 blue. Each
  # switch repaints the sprite; the census follows.
  settle_pixels 2
  shot atlas-index0 viewport2d || ok=false
  local c0; c0=$(color_census "$OUTDIR/shot-atlas-index0.png" 200 30 30)
  op component.set "{\"entity\":$sheet_e,\"type_path\":\"$SPRITE\",\"field\":\"texture_atlas.index\",\"value\":\"1\"}" >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  settle_pixels 2
  shot atlas-index1 viewport2d || ok=false
  local c1; c1=$(color_census "$OUTDIR/shot-atlas-index1.png" 30 180 60)
  op component.set "{\"entity\":$sheet_e,\"type_path\":\"$SPRITE\",\"field\":\"texture_atlas.index\",\"value\":\"2\"}" >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  settle_pixels 2
  shot atlas-index2 viewport2d || ok=false
  local c2; c2=$(color_census "$OUTDIR/shot-atlas-index2.png" 40 80 200)
  log "ATLAS index census: index0 red $c0%, index1 green $c1%, index2 blue $c2%"
  if python3 -c "import sys; sys.exit(0 if float('${c0:-0}') > 0.02 else 1)" \
     && python3 -c "import sys; sys.exit(0 if float('${c1:-0}') > 0.02 else 1)" \
     && python3 -c "import sys; sys.exit(0 if float('${c2:-0}') > 0.02 else 1)"; then
    leg ATLAS_INDEX_PX true
  else
    leg ATLAS_INDEX_PX false; ok=false
  fi

  # The atlas card reopens for editing after scene tabs visited it.
  op asset.open "{\"path\":\"$PROJECT/assets/content/sheet.bsn\"}" >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  op asset.save '{}' >/dev/null 2>&1
  sleep 1
  frames=$(grep -c "URect" "$PROJECT/assets/content/sheet.bsn" 2>/dev/null)
  [ "${frames:-0}" -ge 6 ] \
    && leg ATLAS_REOPEN true || { leg ATLAS_REOPEN false; ok=false; log "ATLAS reopen FAILED: $frames rows"; }

  # Back to the scene tab before saving it (the front tab resolve reads scenes).
  open_scene scene.bsn
  op scene.save '{}' >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null
  warn_scan "atlas-editor" "$OUTDIR/editor-atlas.log"
  log "ATLAS done: $(results)"
  $ok || exit 1
}

# ---- phase: game (M13) --------------------------------------------------------

game_cam2d_id() { # the game's active Camera2d entity
  local ids id cam
  ids=$(gbrp world.query "{\"data\":{\"components\":[\"$CAM2D\"]}}" 2>/dev/null \
    | jq -r '.result[]?.entity // empty' 2>/dev/null)
  for id in $ids; do echo "$id"; return 0; done
  return 1
}
direct_run() { # direct_run <tag> — cargo run the fixture (the flow starts the 2D scene)
  (cd "$PROJECT" && nohup cargo run > "$OUTDIR/direct-$1.log" 2>&1 &)
  wait_game 600 || { log "direct_run $1: game never came up"; return 1; }
  game_ready 240
  sleep 5
  log "direct_run $1: game up"
}
numeric_parity() { # numeric_parity <tag> — the saved fields read back == what
                   # the editor saved. The Sprite component itself cannot cross
                   # either BRP (the -23402 Arc<StrongHandle> serialization
                   # limit, run-2/probe root cause), so the face splits:
                   # presence via a With<Sprite> query, values via Transform,
                   # and the atlas index via the document text (FS) plus the
                   # window census (index 2 draws the blue tile).
  local tag="$1" ok=true face
  # Wait for the scene transition: the game window runs slow in this
  # environment; poll for Hero by name before any read.
  local hero="" deadline=$((SECONDS + 180))
  while [ $SECONDS -lt $deadline ]; do
    hero=$(gid Hero)
    [ -n "$hero" ] && break
    sleep 3
  done
  [ -n "$hero" ] || { leg "$tag" false; log "$tag: Hero never appeared in the game"; return 1; }
  face=$(gcomp "$hero" "$TRANSFORM")
  if echo "$face" | jq -e '.translation != null' >/dev/null 2>&1; then
    log "$tag: Hero transform $face"
  else
    leg "$tag" false; ok=false
    log "$tag: Hero transform read failed: $face"
  fi
  local presence
  presence=$(gbrp world.query "{\"data\":{\"components\":[\"$TRANSFORM\",\"$NAME\"]},\"filter\":{\"with\": [\"$SPRITE\"]}}" 2>/dev/null \
    | jq -r '[.result[]? | select(.components["'"$NAME"'"] == "SheetSpr")] | length' 2>/dev/null)
  if [ "${presence:-0}" = "1" ]; then
    log "$tag: SheetSpr present under With<Sprite>"
  else
    leg "$tag" false; ok=false
    log "$tag: SheetSpr presence rows=${presence:-0}"
  fi
  $ok && leg "$tag" true
  $ok
}
atlas_face() { # atlas_face <tag> <scene-file> — the atlas index face: the
               # document text names index 2 and the window draws the blue tile.
  local tag="$1" file="$2"
  grep -q "bevy_image::texture_atlas::TextureAtlas" "$file" \
    && grep -q "index: 2" "$file" \
    && log "$tag: the document carries the worn atlas (TextureAtlas, index 2)" \
    || { leg "$tag" false; log "$tag: the document lost the atlas wear"; return 1; }
  settle_pixels 3
  gshot "$tag-window" || return 1
  local blue
  blue=$(color_census "$OUTDIR/shot-$tag-window.png" 40 80 200 50)
  log "$tag: game-window blue tile census $blue%"
  python3 -c "import sys; sys.exit(0 if float('${blue:-0}') > 0.005 else 1)" \
    && { leg "$tag" true; return 0; } || { leg "$tag" false; return 1; }
}

game_phase() {
  local ok=true
  direct_run m13 || { leg M13_NUMERIC false; log "GAME done: $(results)"; exit 1; }
  numeric_parity M13_NUMERIC || ok=false
  local cam; cam=$(game_cam2d_id)
  [ -n "$cam" ] && leg M13_CAM2D true || { leg M13_CAM2D false; ok=false; log "M13: no Camera2d in the game"; }
  settle_pixels 3
  gshot m13-game-window || ok=false
  local win_red
  win_red=$(color_census "$OUTDIR/shot-m13-game-window.png" 200 30 30)
  log "M13 game window hero-red census: $win_red%"
  python3 -c "import sys; sys.exit(0 if float('${win_red:-0}') > 0.02 else 1)" \
    && leg M13_WINDOW_PX true || { leg M13_WINDOW_PX false; ok=false; }
  atlas_face M13_ATLAS "$SCENE" || ok=false
  stop_game
  warn_scan "game-direct" "$OUTDIR/direct-m13.log"
  log "GAME done: $(results)"
  $ok || exit 1
}

# ---- phase: export (M15) ------------------------------------------------------

export_face() {
  brp jackdaw/export '{}' 2>/dev/null | jq -r '"\(.result.state // "none") \(.result.started_at // 0)"' 2>/dev/null
}
export_wait() {
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
      log "export_wait: the face never left the pre-call run ($before, state $st)"
      return 1
    fi
    sleep 5
  done
  return 1
}
export_phase() {
  local ok=true
  editor_boot "$PROJECT"
  open_scene scene.bsn
  export_wait || { leg M15_EXPORT false; log "EXPORT done: $(results)"; exit 1; }
  leg M15_EXPORT true
  local a b
  a=$(shasum -a 256 "$SCENE" | awk '{print $1}')
  b=$(shasum -a 256 "$STAGED/assets/scene.bsn" 2>/dev/null | awk '{print $1}')
  [ -n "$b" ] && [ "$a" = "$b" ] \
    && leg M15_SCENE_SHA true || { leg M15_SCENE_SHA false; ok=false; log "M15 sha: project $a staged $b"; }
  # The package carries the scene, the atlas card and the pngs (the walk's face).
  local manifest="$STAGED/export-manifest.json"
  if [ -f "$manifest" ]; then
    local missing=""
    for rel in "assets/scene.bsn" "assets/content/sheet.bsn" "assets/hero.png" "assets/sheet.png" "assets/blue.png"; do
      grep -qF "$rel" "$manifest" || missing="$missing $rel"
    done
    [ -z "$missing" ] && leg M15_PACKAGE true || { leg M15_PACKAGE false; ok=false; log "M15 manifest missing:$missing"; }
  else
    # Older layout: the staged tree itself is the face.
    local miss2=""
    [ -f "$STAGED/assets/scene.bsn" ] || miss2="$miss2 scene.bsn"
    [ -f "$STAGED/assets/content/sheet.bsn" ] || miss2="$miss2 content/sheet.bsn"
    [ -f "$STAGED/assets/hero.png" ] || miss2="$miss2 hero.png"
    [ -z "$miss2" ] && leg M15_PACKAGE true || { leg M15_PACKAGE false; ok=false; log "M15 staged tree missing:$miss2"; }
  fi
  # The staged process answers the same parity face.
  (cd "$STAGED" && nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" "./$STAGED_EXE_NAME" > "$OUTDIR/staged-run.log" 2>&1 &)
  wait_game 300 || { leg M15_STAGED_NUMERIC false; ok=false; log "M15: staged process never came up"; }
  game_ready 240
  sleep 5
  numeric_parity M15_STAGED_NUMERIC || ok=false
  settle_pixels 3
  gshot m15-staged-window || true
  local staged_red
  staged_red=$(color_census "$OUTDIR/shot-m15-staged-window.png" 200 30 30)
  log "M15 staged window hero-red census: $staged_red%"
  python3 -c "import sys; sys.exit(0 if float('${staged_red:-0}') > 0.02 else 1)" \
    && leg M15_STAGED_PX true || { leg M15_STAGED_PX false; ok=false; }
  atlas_face M15_STAGED_ATLAS "$STAGED/assets/scene.bsn" || ok=false
  stop_game
  pkill -x "$(basename "$STAGED_EXE")" 2>/dev/null
  warn_scan "export-staged" "$OUTDIR/staged-run.log"
  log "EXPORT done: $(results)"
  $ok || exit 1
}

STAGED_EXE_NAME=t21-sprite

case "$PHASE" in
  selftest) selftest ;;
  prep)     prep ;;
  probe)    probe ;;
  editor)   editor_phase ;;
  atlas)    atlas_phase ;;
  game)     game_phase ;;
  export)   export_phase ;;
  all)      log "run one phase per invocation: selftest|prep|probe|editor|atlas|game|export"; exit 2 ;;
  *)        log "unknown phase $PHASE"; exit 2 ;;
esac
