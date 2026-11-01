#!/bin/bash
# T22 tilemap live legs (loop/plans/t22-tilemap.md §三). T1 ships the
# skeleton plus the prep leg: the Template::TwoD fixture, the 2D scene
# fixture, the 4x2 tile sheet asset, and the template-integrity precheck.
# The L1-L12 matrix formalisation stays T3's — the later phases are stubs
# that name the legs they will carry so the skeleton's shape is reviewable.
#
# Helper library: the t21-live.sh form — the T18 pixel-evidence craft
# (png_pixels_md5, sips crop), the A7 five-move self-defence in `shot`,
# BRP retry disciplines (AN2 editor side, A9 game side), per-phase
# boot/cleanup traps and `$PHASE` log names.
#
# Phases (each phase boots and cleans its own editor/game processes —
# run one per invocation):
#   selftest  validate the pixel helpers on synthetic PNGs (no editor).
#   prep      fixture hygiene (jd new + the Template::TwoD starter with the
#             Scene2dRoot marker) + jackdaw_remote injection (two-line sed) +
#             the tiles.png 4x2 sheet + the 2D scene fixture + the template
#             integrity precheck + warm builds (t16 prep form).
#   T3 stubs: palette (L2/M1), draw (L2/M2), erase (L3/M3), fill (L3/M4),
#             layers (L4/M5), collision (L4/M6), undo (L5/M7), save (L6/M8),
#             stop (L7/M9), run (L8/M10), pie (L9/M11), export (L10/M12),
#             flow (L11/M13, optional), guards (L7/M14 with L2's pixel half).
#
# Usage: bash loop/qa/t22-live.sh [phase]
#   phase: selftest|prep   (T3 adds the L-leg phases)
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
FIXROOT=/Users/zhanglinbo/workspace/loop-mac/t22-tilemap
PROJECT="$FIXROOT/t22-tilemap"
PORT=15703
GAME_PORT=15702
OUTDIR="$REPO/loop/t22-live"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
SCENE="$PROJECT/assets/scene.bsn"
SHEET="$PROJECT/assets/tiles.png"
PHASE="${1:-all}"
CONSOLE_LOG="$OUTDIR/console-$PHASE.log"
mkdir -p "$OUTDIR"
: > "$CONSOLE_LOG"

# The fixture scene: the Template::TwoD starter (Camera2d + Sprite) plus the
# Scene2dRoot marker a `scene.new kind=2d` save writes, so the editor opens
# it as a 2D world scene. The hero sprite wears the tile sheet already cut
# to cell 0 by `rect` — the route-C tile form this round guards (T22 plan
# fact 5); the texture path is the sheet the prep leg generates.
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
        image: "tiles.png",
        rect: core::option::Option::Some(bevy_math::rects::rect::Rect {
            min: glam::Vec2 { x: 0.0, y: 0.0 },
            max: glam::Vec2 { x: 32.0, y: 32.0 },
        }),
        custom_size: core::option::Option::Some(glam::Vec2 { x: 32.0, y: 32.0 }),
    }
    bevy_sprite::sprite::Anchor
    bevy_transform::components::transform::Transform
    bevy_camera::visibility::Visibility::Visible
]
'
SPRITE='bevy_sprite::sprite::Sprite'
TRANSFORM='bevy_transform::components::transform::Transform'
NAME='bevy_ecs::name::Name'
CAM2D='bevy_camera::components::Camera2d'
EPSILON=0.001
WARN_PATTERN='tilemap|Tile|UnresolvedTypes|cannot-apply|panicked'

RESULTS_FILE="$(mktemp /tmp/t22-live.XXXXXX)"
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
  pkill -x t22-tilemap 2>/dev/null
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
  pkill -x t22-tilemap 2>/dev/null
  sleep 2
}
warn_scan() { # warn_scan <tag> <log> — the T22 warn face (plan §0 line 41-42)
  local tag="$1" file="$2" hits
  [ -f "$file" ] || { leg "WARN_${tag}" false; return 1; }
  hits=$(grep -E "$WARN_PATTERN" "$file" 2>/dev/null | grep -v "TileBrush\|tile_size\b" | wc -l | tr -d ' ')
  if [ "$hits" = "0" ]; then leg "WARN_${tag}" true; else
    log "WARN_${tag}: $hits hits"; grep -E "$WARN_PATTERN" "$file" | head -5 | tee -a "$CONSOLE_LOG"
    leg "WARN_${tag}" false
  fi
}
editor_boot() { # editor_boot [project]
  pkill -x jackdaw 2>/dev/null; pkill -x t22-tilemap 2>/dev/null; sleep 1
  # A dirty kill leaves a crash journal; the next boot opens the Recovered
  # Work modal, which eats every canvas click. Clear the journals first.
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
  op scene.open "{\"path\":\"$1\",\"reload\":true}" >/dev/null 2>&1
  sleep 2; wait_idle 300 >/dev/null; sleep 1; dismiss_dialog
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
              # tiles, row-major, one colour per tile. The T22 sheet: 4x2
              # eight cells, eight distinct colours, so every tile index has
              # a pixel-identifiable colour (the palette/draw red-green
              # census sheet; pure stdlib, plan §三 prep).
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
png_cells_md5() { # png_cells_md5 <png> <tw> <th> — one md5 per grid cell,
                  # row-major, whitespace separated. The tile-index census
                  # without sips: the --cropOffset anchor proved unreliable
                  # in a T1 probe (A7 family), so cell crops decode in
                  # python stdlib from the full image.
  python3 - "$1" "$2" "$3" << 'PYT'
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
assert depth == 8 and interlace == 0 and color in (0, 2, 4, 6), "unsupported PNG"
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
tw, th = int(sys.argv[2]), int(sys.argv[3])
cols = w // tw
md5s = []
for index in range((w // tw) * (h // th)):
    cy, cx = divmod(index, cols)
    cell = bytearray()
    for y in range(cy * th, (cy + 1) * th):
        start = (y * w + cx * tw) * 3
        cell += out[start:start + tw * 3]
    md5s.append(hashlib.md5(bytes(cell)).hexdigest())
print(" ".join(md5s))
PYT
}
png_size() {
  python3 - "$1" << 'PYT'
import struct, sys
data = open(sys.argv[1], "rb").read()
w, h = struct.unpack(">II", data[16:24])
print(w, h)
PYT
}
color_census() { # color_census <png> <r> <g> <b> [tol] — the share of pixels
                 # within tol of the colour, in percent. The tile-colour
                 # verdict for canvas/streamed frames, where there is no
                 # single baseline to diff against.
  python3 - "$@" << 'PYT'
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
if channels == 2:
    rgb = bytearray()
    for i in range(0, len(out), 2):
        rgb += bytes((out[i], out[i], out[i]))
    out = rgb
elif channels == 1:
    out = bytearray(byte for px in out for byte in (px, px, px))
elif channels == 4:
    rgb = bytearray()
    for i in range(0, len(out), 4):
        rgb += out[i:i+3]
    out = rgb
tr, tg, tb = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
tol = int(sys.argv[5]) if len(sys.argv) > 5 else 12
total = max(1, len(out) // 3)
hits = 0
for i in range(0, len(out), 3):
    if abs(out[i]-tr) <= tol and abs(out[i+1]-tg) <= tol and abs(out[i+2]-tb) <= tol:
        hits += 1
print(f"{100.0 * hits / total:.4f}")
PYT
}
shot() { # shot <name> — the A7 five-move self-defence: settle first, two
         # adjacent frames, the md5 census and a size echo, all under a
         # $PHASE-named file.
  local name="$1" frame
  sleep 1
  brp jackdaw/screenshot "{\"path\":\"$OUTDIR/shot-$name-frame0.png\"}" >/dev/null 2>&1
  sleep 1
  brp jackdaw/screenshot "{\"path\":\"$OUTDIR/shot-$name.png\"}" >/dev/null 2>&1
  for frame in frame0 ""; do
    local file="$OUTDIR/shot-$name${frame:+-$frame}.png"
    [ -f "$file" ] || continue
    log "shot-$name$frame: size=$(png_size "$file" 2>/dev/null) md5=$(png_pixels_md5 "$file" 2>/dev/null)"
  done
}

# ---- phases -------------------------------------------------------------------

selftest() {
  local ok=true tmp="$OUTDIR/selftest"
  mkdir -p "$tmp"
  png_write "$tmp/solid.png" 200 30 30 64
  png_tiles "$tmp/sheet.png" 128 64 32 32 "255,0,0;0,255,0;0,0,255;255,255,0;255,0,255;0,255,255;128,128,128;255,128,0"
  [ "$(png_size "$tmp/sheet.png")" = "128 64" ] && leg SELFTEST_SIZE true || { leg SELFTEST_SIZE false; ok=false; }
  # The sheet's eight cells decode to eight distinct pixel md5s (python
  # stdlib crop — the sips --cropOffset anchor is unreliable, T1 probe).
  local distinct
  distinct=$(png_cells_md5 "$tmp/sheet.png" 32 32 | tr ' ' '\n' | sort -u | wc -l | tr -d ' ')
  [ "$distinct" = "8" ] && leg SELFTEST_CELLS true || { leg SELFTEST_CELLS false; log "cells: $(png_cells_md5 "$tmp/sheet.png" 32 32)"; ok=false; }
  local red=$(color_census "$tmp/solid.png" 200 30 30)
  python3 -c "import sys; sys.exit(0 if float('${red:-0}') > 99.0 else 1)" \
    && leg SELFTEST_CENSUS true || { leg SELFTEST_CENSUS false; log "census: $red"; ok=false; }
  $ok || exit 1
  log "SELFTEST done: $(results)"
}

template_precheck() {
  # The template-integrity precheck: the scaffold's module placeholder
  # family must be intact (the T2 wiring hangs the tilemap collision module
  # on the same family), and the tilemap placeholder must be expected-absent
  # today — its appearance without this branch's work would mean drift.
  local tpl="$REPO/crates/jackdaw_scaffold/templates/game/src/lib.rs.template"
  local scf="$REPO/crates/jackdaw_scaffold/src/lib.rs"
  local ok=true
  for anchor in "{{module_physics_player_body}}" "{{module_physics_falling_body}}" \
                "{{module_physics_manual_gravity}}" "{{module_physics_demo}}"; do
    if grep -qF "$anchor" "$tpl"; then
      leg "TPL_$(printf '%s' "$anchor" | sed 's/[{}]//g')" true
    else
      leg "TPL_$(printf '%s' "$anchor" | sed 's/[{}]//g')" false
      ok=false
    fi
  done
  grep -qF "fn module_physics_player_body" "$scf" \
    && leg TPL_SCAFFOLD_FAMILY true || { leg TPL_SCAFFOLD_FAMILY false; ok=false; }
  if grep -qF "{{module_tilemap_collision}}" "$tpl"; then
    leg TPL_TILEMAP_ABSENT false; ok=false
    log "template_precheck: {{module_tilemap_collision}} appeared without this branch's T2 work"
  else
    leg TPL_TILEMAP_ABSENT true
  fi
  $ok
}

prep() {
  local ok=true
  pkill -x jackdaw 2>/dev/null; pkill -x t22-tilemap 2>/dev/null; sleep 1
  log "PREP disk face: $(df -h / | tail -1 | awk '{print $4 " free"}') (A6 discipline: closed fixtures are the hogs)"
  # The editor binary must carry this round's code, and jd must exist (and
  # match the current dylib — a stale jd aborts on a symbol mismatch after
  # any dependency-graph change, the T1 lesson) for the scaffold.
  (cd "$REPO" && cargo build -p jackdaw -p jd > "$OUTDIR/editor-warmbuild-prep.log" 2>&1) \
    || { log "PREP_FAIL editor/jd build: $(tail -3 "$OUTDIR/editor-warmbuild-prep.log")"; exit 1; }
  # Fixture hygiene: start the round from an empty root (t16 prep form),
  # then the proven `jd new` shape (t21 prep) — the 2D flavour arrives with
  # the fixture scene file below, as in T21.
  rm -rf "$FIXROOT"
  mkdir -p "$FIXROOT"
  cd "$REPO"
  if ! env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jd new t22-tilemap --path "$FIXROOT" --no-git > "$OUTDIR/jd-new.log" 2>&1; then
    log "jd new failed: $(tail -3 "$OUTDIR/jd-new.log")"; leg PREP_JD_NEW false; exit 1
  fi
  leg PREP_JD_NEW true
  [ -f "$PROJECT/Cargo.toml" ] || { log "PREP_FAIL fixture incomplete"; exit 1; }
  grep -q "GamePlugin" "$PROJECT/src/main.rs" || { log "PREP_FAIL fixture lacks the game template main"; leg PREP_JD_NEW false; exit 1; }
  # jackdaw_remote injection: the two-line sed (the proven T21 form) so the
  # game BRP 15702 answers the M10 legs.
  if grep -q "jackdaw_remote" "$PROJECT/Cargo.toml"; then
    leg PREP_REMOTE_ALREADY true
  else
    /usr/bin/sed -i '' "s|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = \[\"terrain\", \"pie\"\] }|jackdaw_runtime = { path = '$REPO/crates/jackdaw_runtime', features = [\"terrain\", \"pie\"] }\\njackdaw_remote = { path = '$REPO/crates/jackdaw_remote' }|" "$PROJECT/Cargo.toml"
    grep -q jackdaw_remote "$PROJECT/Cargo.toml" || { log "PREP_FAIL no remote dep"; leg PREP_REMOTE_INJECT false; exit 1; }
    /usr/bin/sed -i '' 's|\.add_plugins(jackdaw_runtime::JackdawPlugin)|.add_plugins(jackdaw_runtime::JackdawPlugin)\n        .add_plugins(jackdaw_remote::JackdawRemotePlugin::default())|' "$PROJECT/src/main.rs"
    grep -q JackdawRemotePlugin "$PROJECT/src/main.rs" || { log "PREP_FAIL no remote plugin"; leg PREP_REMOTE_INJECT false; exit 1; }
    leg PREP_REMOTE_INJECT true
  fi
  # The tile sheet: 4x2 eight cells, eight distinct colours (the palette/
  # draw red-green census sheet; 32 px cells).
  png_tiles "$SHEET" 128 64 32 32 "255,0,0;0,255,0;0,0,255;255,255,0;255,0,255;0,255,255;128,128,128;255,128,0"
  [ -f "$SHEET" ] && leg PREP_SHEET true || { leg PREP_SHEET false; ok=false; }
  # The 2D scene fixture: the Template::TwoD starter plus the route-C tile
  # form (sheet handle + rect cell 0), so the editor opens a 2D world scene
  # and the pixel channels have a tile colour to census.
  printf '%s\n' "$FIXTURE_SCENE" > "$SCENE"
  grep -q "Scene2dRoot" "$SCENE" && leg PREP_SCENE_2D true || { leg PREP_SCENE_2D false; ok=false; }
  # Template integrity (the placeholder family the T2 wiring extends).
  template_precheck || ok=false
  # Warm builds: the game compiles (the M10 legs' first run otherwise eats
  # a cold build inside a leg's timeout), and the editor binary is current.
  (cd "$PROJECT" && cargo build >> "$CONSOLE_LOG" 2>&1) \
    && leg PREP_GAME_WARM true || { leg PREP_GAME_WARM false; ok=false; }
  $ok || exit 1
  log "PREP done: $(results)"
  log "fixture: $PROJECT"
}

# ---- T3 stubs: the L-leg phases name the matrix cells they will carry ----

phase_stub() { # phase_stub <name> <legs...>
  log "$1 is a T3 stub; planned legs: $2"
  exit 2
}

palette()    { phase_stub palette "L2 (M1: sheet cells, palette pick, panel PX)"; }
draw()       { phase_stub draw "L2 (M2: canvas drag, cell sprites, one-stroke undo)"; }
erase()      { phase_stub erase "L3 (M3: erase stroke, empty-cell safety)"; }
fill()       { phase_stub fill "L3 (M4: rect fill + flood fill)"; }
layers()     { phase_stub layers "L4 (M5/M6: three layers, mode switch, tint PX)"; }
undo()       { phase_stub undo "L5 (M7: stroke-level undo chain, dirty flags)"; }
save()       { phase_stub save "L6 (M8: save/reopen field-by-field + bsn text)"; }
stop()       { phase_stub stop "L7 (M9 Stop SHA + M14 tile-pixel negative guard)"; }
run()        { phase_stub run "L8 (M10: ground holds / wall blocks / trigger fires)"; }
pie()        { phase_stub pie "L9 (M11: embedded streamed frames + numeric parity)"; }
export()     { phase_stub export "L10 (M12: staged export parity + package census)"; }
flow()       { phase_stub flow "L11 (M13: optional flow second scene)"; }

case "$PHASE" in
  selftest) selftest ;;
  prep)     prep ;;
  palette)  palette ;;
  draw)     draw ;;
  erase)    erase ;;
  fill)     fill ;;
  layers)   layers ;;
  undo)     undo ;;
  save)     save ;;
  stop)     stop ;;
  run)      run ;;
  pie)      pie ;;
  export)   export ;;
  flow)     flow ;;
  all)      log "run one phase per invocation: selftest|prep (T3 adds the L-leg phases)"; exit 2 ;;
  *)        log "unknown phase $PHASE"; exit 2 ;;
esac
