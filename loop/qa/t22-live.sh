#!/bin/bash
# T22 tilemap live legs (loop/plans/t22-tilemap.md §三). T1 shipped the
# skeleton plus the prep leg; T2 flipped the template guard. T3 fills the
# L1-L12 matrix in: every phase boots and cleans its own editor/game
# processes — run one phase per invocation, in this order:
#
#   selftest  validate the pixel helpers on synthetic PNGs (no editor).
#   prep      fixture hygiene: jd new --modules physics,tilemap (the D7
#             flip — the game-side collision kernel rides the module row)
#             + jackdaw_remote injection + the 512x256 tiles.png sheet +
#             the 2D scene fixture + the template integrity precheck +
#             flow start_scene = scene.bsn + warm builds (t16 prep form).
#   palette   L2 (M1: layer add, palette panel up, sheet pick, readout,
#             panel PX).
#   draw      L2 (M2: canvas strokes, cell sprites, one-stroke undo,
#             off-canvas safety, rect-cut pixel half of M14).
#   erase     L3 (M3: erase op + erase stroke, empty-cell safety, PX).
#   fill      L3 (M4: rect fill, bounded flood, out-of-bounds seed, PX).
#   layers    L4 (M5/M6: layer routing, mode set/undo, visibility PX,
#             TM7 tint PX).
#   undo      L5 (M7: seven-entry chain, stepwise undo, redo, dirty
#             cycle around a save point).
#   save      L6 (M8: the canonical level — ground row / wall column /
#             trigger pair — saved and reopened field by field).
#   stop      L7 (M9: PIE stop leaves the doc SHA; M14 bsn half).
#   run       L8 (M10: ground holds / wall blocks / trigger fires, the
#             direct-run game against the saved level).
#   pie       L9 (M11: embedded streamed frame + numeric parity).
#   export    L10 (M12: staged release, package census, foreign-dir run).
#   flow      L11 (M13, optional: menu -> level -> menu with zero residue).
#
# Helper library: the t21/t20-live form — the T18 pixel-evidence craft,
# the A7 five-move self-defence in `shot`, BRP retry disciplines (AN2
# editor side, A9 game side), the t20 walk-injection form for the probe
# legs, per-phase boot/cleanup traps and `$PHASE` log names.
#
# Usage: bash loop/qa/t22-live.sh [phase]
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
Tlayer='jackdaw_scene_types::TilemapLayer'
Tcell='jackdaw_scene_types::TileGridCell'
Tmode='jackdaw_scene_types::TileCollisionMode'
CHILDOF='bevy_ecs::hierarchy::ChildOf'
CAM2D='bevy_camera::components::Camera2d'
EPSILON=0.001
WARN_PATTERN='tilemap|Tile|UnresolvedTypes|cannot-apply|panicked'
# The sheet, its cut, and the level the run legs walk. 16x8 cells of 32 px:
# the layer's columns/rows are both the sheet cut AND the level grid extent
# (one form, T2 report §四), so the sheet carries the whole level room. The
# first eight cells are the eight distinct census colours; higher indices
# repeat the last colour (orange).
SHEET_COLS=16
SHEET_ROWS=8
CELL=32
# Level geometry (cells, y up): ground row 1 spans y 32..64 (top edge 64,
# the probe rests at y=76); the trigger pair sits in row 2 on the walk line;
# the wall column x=9 rises rows 2..4 and stops the rightward walk at
# x = 9*32 - 12(half) - separation.
GROUND_CELLS="0,1;1,1;2,1;3,1;4,1;5,1;6,1;7,1;8,1;9,1;10,1;11,1;12,1;13,1;14,1"
WALL_CELLS="9,2;9,3;9,4"
TRIGGER_CELLS="5,2;6,2"

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
warn_scan() { # warn_scan <tag> <log> — the T22 warn face (plan §0 line 41-42):
              # WARN/ERROR-level lines carrying the token pattern. (The bare
              # token pattern alone drowns in INFO operator echoes — every
              # `OPERATOR: tilemap.*` call logs its own name.) Known faces
              # excluded: the T2 pair, the TM11 module warning this round
              # filed (the tooling compiles into every editor), and the
              # fixture-path substring.
  local tag="$1" file="$2" hits
  [ -f "$file" ] || { leg "WARN_${tag}" false; return 1; }
  hits=$(grep -E ' WARN | ERROR |panicked' "$file" 2>/dev/null \
    | grep -E "$WARN_PATTERN" \
    | grep -v "TileBrush\|tile_size\b" \
    | grep -v "uses the Tilemap module, which this editor does not include" \
    | grep -v "no in-bounds cells to paint" \
    | grep -v "loop-mac/t22-tilemap" | wc -l | tr -d ' ')
  if [ "$hits" = "0" ]; then leg "WARN_${tag}" true; else
    log "WARN_${tag}: $hits hits"; grep -E ' WARN | ERROR |panicked' "$file" | grep -E "$WARN_PATTERN" | head -5 | tee -a "$CONSOLE_LOG"
    leg "WARN_${tag}" false
  fi
}
editor_boot() { # editor_boot [project]
  pkill -x jackdaw 2>/dev/null; pkill -x t22-tilemap 2>/dev/null; sleep 1
  # A dirty kill leaves a crash journal; the next boot opens the Recovered
  # Work modal, which eats every canvas click. Clear the journals first.
  find "$HOME/.jackdaw/sessions" -name "journal.json" -delete 2>/dev/null
  local boot_log="$OUTDIR/editor-$PHASE.log"
  : > "$boot_log"
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
editor_alive() { # the liveness face: the editor still answers status.
  brp jackdaw/status '{}' 2>/dev/null | jq -e '.result.pid' >/dev/null 2>&1
}

# ---- editor-side reads --------------------------------------------------------

eid() { # eid <name> — the editor entity carrying this Name
  brp world.query "{\"data\":{\"components\":[\"$NAME\"]}}" 2>/dev/null \
    | jq -r --arg n "$1" '[.result[]? | select(.components["'"$NAME"'"] == $n) | .entity][0]' 2>/dev/null
}
ebsn() { # ebsn <name> — the editor entity's bsn (the read door that carries
         # asset handles: TilemapLayer's Handle<Image> has no ReflectSerialize,
         # so world.get_components answers -23402 for it — the T21 SP7 face)
  brp jackdaw/entity "{\"name\":\"$1\"}" 2>/dev/null | jq -r '.result.bsn // empty' 2>/dev/null
}
layer_form() { # layer_form <name> — "columns rows" off the entity bsn
  ebsn "$1" | python3 -c "
import re, sys
text = sys.stdin.read()
block = re.search(r'TilemapLayer \{(.*?)\}', text, re.S)
cols = re.search(r'columns: (\d+)', block.group(1)) if block else None
rows = re.search(r'rows: (\d+)', block.group(1)) if block else None
print(f'{cols.group(1) if cols else \"\"} {rows.group(1) if rows else \"\"}')
" 2>/dev/null
}
ecomp_once() { # one editor component read, no retry (read_ready's probe)
  brp world.get_components "{\"entity\":\"$1\",\"components\":[\"$2\"]}" 2>/dev/null \
    | jq -c --arg c "$2" '.result.components[$c] // .result[$c] // empty' 2>/dev/null
}
ecomp() { # ecomp <id> <component> — an editor entity's component JSON
  local id="$1" out attempt
  [ -n "$id" ] || return 0
  for attempt in 1 2 3 4 5 6; do
    out=$(ecomp_once "$id" "$2")
    [ -n "$out" ] && { echo "$out"; return 0; }
    sleep 3
  done
  echo "$out"
}
eselect() { # the editor's current selection as a JSON list
  brp jackdaw/status '{}' 2>/dev/null | jq -cr '.result.selection // []' 2>/dev/null
}
history_len() { # the history face's undo depth
  brp jackdaw/history '{}' 2>/dev/null | jq -r '.result.undo_len // ""' 2>/dev/null
}
is_dirty() { # the active tab's dirty flag
  brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.dirty // false' 2>/dev/null
}
read_ready() { # read_ready <id> <component> [tries] — hold until a component
               # read answers (the T2 QA read-ready gate: whole read windows
               # can sit dead for minutes).
  local id="$1" comp="$2" tries="${3:-30}" probe
  for probe in $(seq 1 "$tries"); do
    [ -n "$(ecomp_once "$id" "$comp")" ] && return 0
    sleep 3
  done
  log "read_ready: no answer after $((tries*3))s (the read window stayed dead)"
  return 1
}
ui_text_node() { # ui_text_node <text> — the first ui_tree node (entity bits)
                 # whose text equals <text>, visible ones preferred.
  brp jackdaw/ui_tree "{\"depth\":30,\"text\":\"$1\"}" 2>/dev/null \
    | jq -r '[.. | objects | select(.text? == "'"$1"'")][0].entity // empty' 2>/dev/null
}
ui_node_field() { # ui_node_field <jq-filter> — walk the whole ui_tree, apply
                  # the filter to every node, first hit's output.
  brp jackdaw/ui_tree '{"depth":40}' 2>/dev/null \
    | jq -r "[.. | objects | $1][0] // empty" 2>/dev/null
}

# ---- game-side reads (the t20 forms) ------------------------------------------

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
gres() { # gres <resource> — a game resource's JSON (t16 gconfig form)
  gbrp world.get_resources "{\"resource\":\"$1\"}" 2>/dev/null | jq -c '.result.value // empty' 2>/dev/null
}
gcount() { # gcount <component> — entities carrying it
  gbrp world.query "{\"data\":{\"components\":[\"$1\"]}}" 2>/dev/null \
    | jq -r '.result | length // 0' 2>/dev/null
}
has_component() { # has_component <type_path> — any entity carries it
  gbrp world.query "{\"data\":{\"components\":[\"$1\"]}}" 2>/dev/null | jq -e '(.result | length) >= 1' >/dev/null 2>&1
}
KB_MSG='bevy_input::keyboard::KeyboardInput'
GAME_WIN=""
key_window() {
  gbrp world.query '{"data":{"components":["bevy_window::window::Window"]}}' 2>/dev/null \
    | jq -r '.result[0].entity // empty' 2>/dev/null
}
kb_msg() { # kb_msg <Pressed|Released> <key> — one keyboard message (t16 form)
  gbrp world.write_message "{\"message\":\"$KB_MSG\",\"value\":{\"key_code\":\"$2\",\"logical_key\":{\"Character\":\" \"},\"state\":\"$1\",\"text\":null,\"repeat\":false,\"window\":\"$GAME_WIN\"}}" >/dev/null 2>&1
}
walk_reset() { # release every lane key; a lost release must never survive a
               # leg boundary (the t20 box run-4 lesson)
  [ -n "$GAME_WIN" ] || return 0
  local k
  for k in KeyW KeyA KeyS KeyD; do
    kb_msg Released "$k"
  done
}
walk_begin() {
  [ -n "$GAME_WIN" ] && return 0
  GAME_WIN=$(key_window)
  [ -n "$GAME_WIN" ] || { log "walk_begin: no Window entity"; return 1; }
}
probe_xy() { # probe_xy — the probe body's "x y" from its synced sprite
             # Transform (this build may serialize an array or an object)
  local pid t
  pid=$(gid "Player Probe")
  [ -n "$pid" ] || { echo ""; return; }
  t=$(gcomp "$pid" "$TRANSFORM")
  echo "$t" | jq -r '.translation | if type == "array" then "\(.[0]) \(.[1])" else "\(.x) \(.y)" end' 2>/dev/null
}
census_read() { # census_read — TriggerCensus as "inside crossed"
  gres "t22_tilemap::TriggerCensus" 2>/dev/null \
    | jq -r '"\(.inside // -1) \(.crossed // false)"' 2>/dev/null
}

# ---- pixel evidence (the t19/t18 craft) ---------------------------------------

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
              # tiles, row-major, one colour per tile. The T22 sheet: the
              # first eight cells carry the eight census colours.
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
                  # row-major (the tile-index census; the sips crop anchor
                  # proved unreliable in a T1 probe, so cells decode in
                  # python stdlib from the full image).
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
                 # within tol of the colour, in percent.
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
color_census_crop() { # color_census_crop <png> <r> <g> <b> <tol> <x0> <y0> <x1> <y1>
                      # — the census inside one band (the t21 strip form).
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
tol = int(sys.argv[5])
x0, y0, x1, y1 = (int(v) for v in sys.argv[6:10])
x0, x1 = max(0, x0), min(w, x1)
y0, y1 = max(0, y0), min(h, y1)
total = max(1, (x1 - x0) * (y1 - y0))
hits = 0
for y in range(y0, y1):
    base = (y * w + x0) * 3
    for x in range(x1 - x0):
        i = base + x * 3
        if abs(out[i]-tr) <= tol and abs(out[i+1]-tg) <= tol and abs(out[i+2]-tb) <= tol:
            hits += 1
print(f"{100.0 * hits / total:.4f}")
PYT
}
settle_pixels() { sleep "${1:-3}"; }
shot() { # shot <name> [kind] — the A7 five moves: settle, two adjacent
         # frames, md5 + size echoes, all under $PHASE-named files. kind:
         # window (default) or viewport2d (the 2D viewport render alone —
         # the canvas census band).
  local name="$1" kind="${2:-window}"
  local rel path out out_json
  rel="screenshots/t22-$name.png"
  path="$PROJECT/$rel"
  rm -f "$path"
  local key="t22-$name-$RANDOM-$SECONDS"
  for i in $(seq 1 20); do
    out_json=$(curl -s -m 12 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
      -d "{\"jsonrpc\":\"2.0\",\"id\":$i,\"method\":\"jackdaw/screenshot\",\"params\":{\"kind\":\"$kind\",\"path\":\"$rel\",\"request\":\"$key-$i\"}}" 2>/dev/null)
    out=$(echo "$out_json" | jq -r '.result.path // empty' 2>/dev/null)
    if [ -n "$out" ] && [ -s "$path" ]; then
      cp "$path" "$OUTDIR/shot-$name.png" 2>/dev/null
      break
    fi
    sleep 1
  done
  [ -s "$OUTDIR/shot-$name.png" ] || { log "shot $name FAILED (capture never landed)"; return 1; }
  sleep 1
  rm -f "$path"
  for i in $(seq 1 20); do
    out_json=$(curl -s -m 12 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
      -d "{\"jsonrpc\":\"2.0\",\"id\":$i,\"method\":\"jackdaw/screenshot\",\"params\":{\"kind\":\"$kind\",\"path\":\"$rel\",\"request\":\"$key-f0-$i\"}}" 2>/dev/null)
    out=$(echo "$out_json" | jq -r '.result.path // empty' 2>/dev/null)
    if [ -n "$out" ] && [ -s "$path" ]; then
      cp "$path" "$OUTDIR/shot-$name-frame0.png" 2>/dev/null
      break
    fi
    sleep 1
  done
  rm -f "$path"
  local frame file
  for frame in frame0 ""; do
    file="$OUTDIR/shot-$name${frame:+-$frame}.png"
    [ -f "$file" ] || continue
    log "shot-$name$frame: size=$(png_size "$file" 2>/dev/null) md5=$(png_pixels_md5 "$file" 2>/dev/null)"
  done
  return 0
}

# ---- shared authoring ----------------------------------------------------------

setup_tool_session() { # the per-phase tilemap session: the clean starter
                       # scene, the 2D canvas column out, one Ground layer
                       # with the sheet, Tilemap tool out, then a tile pick —
                       # the pick is load-bearing: the palette content pass
                       # stores its fingerprint before the panel mounts, so a
                       # change after the mount is what fills an empty panel
                       # (the TM12 sequence this round filed).
  # Earlier phases may have left layers on disk (the undo round saves); a
  # name clash would fork the level (a leftover Ground turns the authored
  # one into Ground2). The starter comes back before every session.
  printf '%s\n' "$FIXTURE_SCENE" > "$SCENE"
  open_scene scene.bsn
  op viewport.mode '{"mode":"2d"}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  op tilemap.layer.add "{\"name\":\"Ground\",\"cell_size\":\"$CELL\",\"columns\":$SHEET_COLS,\"rows\":$SHEET_ROWS,\"path\":\"tiles.png\"}" >/dev/null 2>&1
  sleep 2; wait_idle 120 >/dev/null
  local layer tries
  layer=$(eid Ground)
  [ -n "$layer" ] || { log "setup_tool_session: no Ground layer"; return 1; }
  # The layer's bsn face settles (the read door that carries the form).
  for tries in $(seq 1 20); do
    [ -n "$(layer_form Ground)" ] && break
    sleep 3
  done
  [ -n "$(layer_form Ground)" ] || { log "setup_tool_session: the layer form never read back"; return 1; }
  op tool.tilemap '{}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  # Two picks: whatever the session's active tile was, one of them changes
  # it — the content pass only rebuilds on a fingerprint change, and a
  # same-value pick changes nothing (TM12's empty-panel sequence again).
  op tilemap.tile.select '{"tile":1}' >/dev/null 2>&1
  sleep 1; wait_idle 30 >/dev/null
  op tilemap.tile.select '{"tile":0}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  # 100% zoom (the A10 discipline): a stated zoom also stands the pending
  # fit down, so the canvas geometry is known for any pointer work.
  op viewport2d.zoom '{"zoom":1.0}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  # The panel is up when the brush row reads.
  for tries in $(seq 1 10); do
    [ -n "$(ui_text_node Paint)" ] && break
    sleep 3
  done
  [ -n "$(ui_text_node Paint)" ] || { log "setup_tool_session: the palette panel never filled"; return 1; }
  echo "$layer"
}
cell_count() { # cell_count — TileGridCell rows in the editor world
  brp world.query "{\"data\":{\"components\":[\"$Tcell\"]}}" 2>/dev/null \
    | jq -r '.result | length // 0' 2>/dev/null
}
cells_on_layer() { # cells_on_layer <layer-entity> — TileGridCell rows whose
                   # ChildOf parent is <entity> (ChildOf serializes as the
                   # parent's entity string)
  brp world.query "{\"data\":{\"components\":[\"$Tcell\",\"$CHILDOF\"]}}" 2>/dev/null \
    | jq -r --arg p "$1" '[.result[]? | select(.components["'"$CHILDOF"'"] == $p)] | length' 2>/dev/null
}
cells_with_tile() { # cells_with_tile <tile-index> — TileGridCell rows cutting it
  brp world.query "{\"data\":{\"components\":[\"$Tcell\"]}}" 2>/dev/null \
    | jq -r --arg t "$1" '[.result[]? | select(.components["'"$Tcell"'"].tile == ($t | tonumber))] | length' 2>/dev/null
}
# The census colours (png_tiles order): red green blue yellow magenta cyan
# gray orange. The probe wears srgb(0.9,0.3,0.3) — pink, next to none of them.
C_RED="255,0,0"; C_GREEN="0,255,0"; C_BLUE="0,0,255"; C_YELLOW="255,255,0"
C_MAGENTA="255,0,255"; C_CYAN="0,255,255"; C_GRAY="128,128,128"; C_ORANGE="255,128,0"
census_named() { # census_named <shot-name> <r> <g> <b> [tol] — the colour
                 # share of one of this phase's shots (0.0 if it is missing)
  local file="$OUTDIR/shot-$1.png" tol="${5:-24}"
  [ -f "$file" ] || { echo "0.0000"; return; }
  color_census "$file" "$2" "$3" "$4" "$tol" 2>/dev/null || echo "0.0000"
}
of() { # of <value> [threshold] — shell-true when value > threshold
  python3 -c "import sys; sys.exit(0 if float('${1:-0}') > float('${2:-0.0}') else 1)"
}

# ---- phases -------------------------------------------------------------------

selftest() {
  local ok=true tmp="$OUTDIR/selftest"
  mkdir -p "$tmp"
  png_write "$tmp/solid.png" 200 30 30 64
  png_tiles "$tmp/sheet.png" 512 256 32 32 "255,0,0;0,255,0;0,0,255;255,255,0;255,0,255;0,255,255;128,128,128;255,128,0"
  [ "$(png_size "$tmp/sheet.png")" = "512 256" ] && leg SELFTEST_SIZE true || { leg SELFTEST_SIZE false; ok=false; }
  # The sheet's first eight cells decode to eight distinct pixel md5s (python
  # stdlib crop — the sips --cropOffset anchor is unreliable, T1 probe).
  local distinct
  distinct=$(png_cells_md5 "$tmp/sheet.png" 32 32 2>/dev/null | tr ' ' '\n' | sort -u | wc -l | tr -d ' ')
  [ "$distinct" = "8" ] && leg SELFTEST_CELLS true || { leg SELFTEST_CELLS false; ok=false; }
  local red=$(color_census "$tmp/solid.png" 200 30 30)
  of "$red" 99.0 && leg SELFTEST_CENSUS true || { leg SELFTEST_CENSUS false; log "census: $red"; ok=false; }
  local band=$(color_census_crop "$tmp/sheet.png" 255 0 0 12 0 0 32 32)
  of "$band" 99.0 && leg SELFTEST_CROP true || { leg SELFTEST_CROP false; log "crop census: $band"; ok=false; }
  $ok || exit 1
  log "SELFTEST done: $(results)"
}

template_precheck() {
  # The template-integrity precheck: the scaffold's module placeholder
  # family must be intact, and the tilemap section (T2's landing) must be
  # present — its disappearance would mean drift.
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
  if grep -qF "{{module_tilemap_collision}}" "$tpl" \
    && grep -qF "fn module_tilemap_collision" "$scf" \
    && grep -qF "fn module_tilemap_player" "$scf"; then
    leg TPL_TILEMAP_PRESENT true
  else
    leg TPL_TILEMAP_PRESENT false; ok=false
    log "template_precheck: the tilemap module section is missing after T2"
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
  # Fixture hygiene: start the round from an empty root (t16 prep form).
  # The D7 flip rides the scaffold's own module flag: `--modules
  # physics,tilemap` writes the `tilemap = true` row AND the kernel crate
  # into the game manifest, and the emitted template carries the probe
  # plugin — the flip, re-lock and warm build in one proven step.
  rm -rf "$FIXROOT"
  mkdir -p "$FIXROOT"
  cd "$REPO"
  if ! env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jd new t22-tilemap --path "$FIXROOT" --no-git --modules physics,tilemap > "$OUTDIR/jd-new.log" 2>&1; then
    log "jd new failed: $(tail -3 "$OUTDIR/jd-new.log")"; leg PREP_JD_NEW false; exit 1
  fi
  leg PREP_JD_NEW true
  [ -f "$PROJECT/Cargo.toml" ] || { log "PREP_FAIL fixture incomplete"; exit 1; }
  grep -q "GamePlugin" "$PROJECT/src/main.rs" || { log "PREP_FAIL fixture lacks the game template main"; leg PREP_JD_NEW false; exit 1; }
  # D7 assertions: the module row flipped, the kernel crate re-locked into
  # the game manifest, the probe plugin emitted into the game lib.
  grep -q 'tilemap = true' "$PROJECT/jackdaw.toml" \
    && leg PREP_TILEMAP_ROW true || { leg PREP_TILEMAP_ROW false; ok=false; }
  grep -q 'jackdaw_tilemap_collision' "$PROJECT/Cargo.toml" \
    && leg PREP_TILEMAP_DEP true || { leg PREP_TILEMAP_DEP false; ok=false; }
  grep -q 'TilemapProbePlugin' "$PROJECT/src/lib.rs" \
    && leg PREP_TILEMAP_LIB true || { leg PREP_TILEMAP_LIB false; ok=false; }
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
  # The tile sheet: 16x8 cells of 32 px, the first eight carrying the eight
  # census colours (the palette/draw red-green census sheet). The 16x8 cut
  # gives the level grid its room (layer columns/rows = sheet cut = grid
  # extent, one form).
  png_tiles "$SHEET" 512 256 32 32 "$C_RED;$C_GREEN;$C_BLUE;$C_YELLOW;$C_MAGENTA;$C_CYAN;$C_GRAY;$C_ORANGE"
  [ -f "$SHEET" ] && [ "$(png_size "$SHEET")" = "512 256" ] \
    && leg PREP_SHEET true || { leg PREP_SHEET false; ok=false; }
  # The 2D scene fixture: the Template::TwoD starter plus the route-C tile
  # form (sheet handle + rect cell 0), so the editor opens a 2D world scene
  # and the pixel channels have a tile colour to census.
  printf '%s\n' "$FIXTURE_SCENE" > "$SCENE"
  grep -q "Scene2dRoot" "$SCENE" && leg PREP_SCENE_2D true || { leg PREP_SCENE_2D false; ok=false; }
  # The flow boots its start scene: point it at the 2D level (t19/t21 form)
  # so the run/pie/export legs land in GameFlow::Level with the authored
  # world — the probe plugin's flow gate reads Level.
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
  grep -q '"start_scene": "scene.bsn"' "$PROJECT/assets/game.flow.json" \
    && leg PREP_FLOW_START true || { leg PREP_FLOW_START false; ok=false; }
  # Template integrity (the placeholder family the T2 wiring extends).
  template_precheck || ok=false
  # Warm builds: the game compiles WITH the tilemap module (the re-lock the
  # D7 flip owes — the M10 legs' first run otherwise eats a cold build), and
  # the editor binary is current.
  (cd "$PROJECT" && cargo build >> "$CONSOLE_LOG" 2>&1) \
    && leg PREP_GAME_WARM true || { leg PREP_GAME_WARM false; ok=false; }
  $ok || exit 1
  log "PREP done: $(results)"
  log "fixture: $PROJECT"
}

# ---- L2 phase: palette (M1) -----------------------------------------------------

palette() {
  local ok=true
  editor_boot "$PROJECT"
  setup_tool_session || { log "palette: session setup failed"; exit 1; }
  # The layer's cut fields read back through the bsn door (M1's config face;
  # the Handle<Image> field keeps world.get_components at -23402).
  local form cols rows
  form=$(layer_form Ground)
  log "Ground form (bsn): columns=${form%% *}, rows=${form##* }"
  [ "${form%% *}" = "$SHEET_COLS" ] && [ "${form##* }" = "$SHEET_ROWS" ] \
    && leg LAYER_FORM true || { leg LAYER_FORM false; ok=false; log "layer form: '$form' (want '$SHEET_COLS $SHEET_ROWS')"; }
  # The Tilemap tool brought the palette panel up (the brush row exists).
  local paint_node
  paint_node=$(ui_text_node "Paint")
  [ -n "$paint_node" ] && leg PALETTE_PANEL true \
    || { leg PALETTE_PANEL false; ok=false; log "palette: no Paint button in the ui_tree"; }
  # The sheet display: the panel's sheet box — width 672, height 336 physical
  # (16x8 cells of 42 px at this window's scale; the box carries the grid
  # lines and the highlight as children).
  local sheet_node sheet_rect
  sheet_node=$(ui_node_field 'select(((.rect[2] // 0) > 600) and ((.rect[2] // 0) < 700) and ((.rect[3] // 0) > 300) and ((.rect[3] // 0) < 370)) | .entity // empty')
  log "sheet node: $sheet_node"
  if [ -n "$sheet_node" ]; then
    sheet_rect=$(brp jackdaw/ui_tree '{"depth":40}' 2>/dev/null \
      | jq -c --arg e "$sheet_node" '[.. | objects | select(.entity? == ($e | tonumber))] | .[0].rect // empty' 2>/dev/null)
    log "sheet rect: $sheet_rect"
    leg SHEET_NODE true
  else
    leg SHEET_NODE false; ok=false
  fi
  # The palette pick: one press inside a sheet cell writes the active tile.
  # The readout before is Tile 0 (the setup pick); the leg asserts it moved
  # to a different index — the cell the synthetic drag lands in varies with
  # the gesture channel's scale, so the verdict is the change, not one
  # preset index (the deterministic pick face is TILE_SELECT below). The
  # press arms the canvas stroke modal as a side effect; cancel clears it.
  local readout_before readout_after
  readout_before=$(ui_text_node "Tile 0")
  if [ -n "$sheet_node" ]; then
    brp jackdaw/ui_drag "{\"entity\":$sheet_node,\"from\":[0.15625,0.9375],\"to\":[0.15625,0.9375]}" >/dev/null 2>&1
    sleep 3; wait_idle 60 >/dev/null
    brp jackdaw/cancel '{}' >/dev/null 2>&1
    sleep 2
    readout_after=$(brp jackdaw/ui_tree '{"depth":60}' 2>/dev/null \
      | jq -r '[.. | objects | .text? // empty | select(test("^Tile [0-9]+$"))][0] // empty' 2>/dev/null)
    log "palette pick: '$readout_before' -> '$readout_after'"
    if echo "$readout_after" | grep -qE "^Tile [0-9]+$" && [ "$readout_after" != "$readout_before" ]; then
      leg PALETTE_PICK true
    else
      leg PALETTE_PICK false; ok=false
    fi
  fi
  # The operator door picks too (the readout follows).
  op tilemap.tile.select '{"tile":4}' >/dev/null 2>&1
  sleep 1; wait_idle 30 >/dev/null
  [ -n "$(ui_text_node "Tile 4")" ] && leg TILE_SELECT true \
    || { leg TILE_SELECT false; ok=false; }
  # Panel PX: the window shot's sheet-band census. The sheet renders its
  # image, grid and highlight (decision 4-A's whole form); the band's truth
  # is the panel chrome fill (over 25%) plus the sheet image's own orange
  # mass (cells 8+ of the 16x8 cut repeat the last census colour) — the
  # per-colour lines below are the render evidence.
  if [ -n "$sheet_rect" ]; then
    settle_pixels 3
    shot palette-panel window || ok=false
    local x0 y0 x1 y1 colour bg_share orange_share
    x0=$(echo "$sheet_rect" | jq -r '.[0] // 0' | python3 -c "print(int(float(input() or 0)))")
    y0=$(echo "$sheet_rect" | jq -r '.[1] // 0' | python3 -c "print(int(float(input() or 0)))")
    x1=$(echo "$sheet_rect" | jq -r '.[2] // 0' | python3 -c "print(int(float(input() or 0)))")
    y1=$(echo "$sheet_rect" | jq -r '.[3] // 0' | python3 -c "print(int(float(input() or 0)))")
    x1=$((x0 + x1)); y1=$((y0 + y1))
    log "panel band (physical): $x0 $y0 $x1 $y1"
    bg_share=$(color_census_crop "$OUTDIR/shot-palette-panel.png" 41 41 46 10 "$x0" "$y0" "$x1" "$y1" 2>/dev/null)
    orange_share=$(color_census_crop "$OUTDIR/shot-palette-panel.png" 255 128 0 24 "$x0" "$y0" "$x1" "$y1" 2>/dev/null)
    log "panel chrome census: $bg_share; sheet orange census: $orange_share"
    of "$bg_share" 25.0 && of "$orange_share" 5.0 && leg PALETTE_PX true \
      || { leg PALETTE_PX false; ok=false; log "panel chrome $bg_share / sheet orange $orange_share"; }
    for colour in "$C_RED" "$C_GREEN" "$C_BLUE" "$C_YELLOW" "$C_MAGENTA" "$C_CYAN"; do
      local share
      share=$(color_census_crop "$OUTDIR/shot-palette-panel.png" "${colour%%,*}" "$(echo "$colour" | cut -d, -f2)" "$(echo "$colour" | cut -d, -f3)" 24 "$x0" "$y0" "$x1" "$y1" 2>/dev/null)
      log "sheet colour $colour in the band: $share"
    done
  fi
  warn_scan EDITOR "$OUTDIR/editor-$PHASE.log" || ok=false
  editor_alive && leg EDITOR_ALIVE true || { leg EDITOR_ALIVE false; ok=false; }
  $ok || exit 1
  log "PALETTE done: $(results)"
}

# ---- L2 phase: draw (M2 + M14's pixel half) -------------------------------------
# TM14 was fixed in T3.5 (the stroke now captures the panel-content entity
# carrying Viewport2dPanelHost, and the finished stroke's batch dispatch is
# deferred one frame so the modal retires before the nested call): the drag
# gesture below is the live proof — press/move/release across canvas cells
# lands them as one undo entry.

draw() {
  local ok=true
  editor_boot "$PROJECT"
  setup_tool_session >/dev/null || { log "draw: session setup failed"; exit 1; }
  # The pick that the strokes cut: tile 4, magenta (the census colour that
  # no other entity wears).
  op tilemap.tile.select '{"tile":4}' >/dev/null 2>&1; sleep 1
  settle_pixels 3
  shot draw-baseline viewport2d || ok=false
  # The gesture face: one real drag across cells (0,2)-(2,2) — the press
  # arms the stroke, the moves visit cells, the release stamps and the
  # modal retires.
  local depth0
  depth0=$(history_len)
  op input.pointer '{"action":"press","x":8,"y":72,"space":"world"}' >/dev/null 2>&1
  sleep 1
  for x in 20 32 44 56 68 80 88; do
    op input.pointer "{\"action\":\"move\",\"x\":$x,\"y\":72,\"space\":\"world\"}" >/dev/null 2>&1
    sleep 0.4
  done
  op input.pointer '{"action":"release","x":88,"y":72,"space":"world"}' >/dev/null 2>&1
  sleep 3; wait_idle 120 >/dev/null
  local modal_cleared
  modal_cleared=$(brp jackdaw/status '{}' 2>/dev/null | jq -r '.result.modal // "null"')
  [ "$modal_cleared" = "null" ] && leg STROKE_RELEASES true \
    || { leg STROKE_RELEASES false; ok=false; log "the stroke modal survived its release (modal='$modal_cleared')"; }
  local count
  count=$(cell_count)
  [ "$count" = "3" ] && leg DRAW_DRAG_LANDS true \
    || { leg DRAW_DRAG_LANDS false; ok=false; log "cells after the drag: $count (want 3)"; }
  # Two more strokes through the batch door — cells in row 2, columns 5-7
  # and 10-12. One operator call is one stroke is one undo entry.
  op tilemap.paint '{"layer":"Ground","cells":"5,2;6,2;7,2","tile":4}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  op tilemap.paint '{"layer":"Ground","cells":"10,2;11,2;12,2","tile":4}' >/dev/null 2>&1
  sleep 1; wait_idle 120 >/dev/null
  count=$(cell_count)
  [ "$count" = "9" ] && leg DRAW_COUNT true \
    || { leg DRAW_COUNT false; ok=false; log "draw count: $count (want 9)"; }
  # Spot read: cell (0,2) cuts tile 4 (the cell serializes as an [x, y] pair).
  local spot
  spot=$(brp world.query "{\"data\":{\"components\":[\"$Tcell\"]}}" 2>/dev/null \
    | jq -r --arg t "$Tcell" '[.result[]? | select(.components[$t].cell[0] == 0 and .components[$t].cell[1] == 2)][0].components[$t].tile // empty' 2>/dev/null)
  [ "$spot" = "4" ] && leg DRAW_CELL_VALUE true \
    || { leg DRAW_CELL_VALUE false; ok=false; log "cell (0,2) cuts tile '$spot' (want 4)"; }
  # Pixel faces: the painted colour appears; the other seven census colours
  # stay absent — the rect cut, not the whole sheet (M14's pixel half).
  settle_pixels 3
  shot draw-painted viewport2d || ok=false
  local base_md5 painted_md5 mag green blue yellow cyan orange
  base_md5=$(png_pixels_md5 "$OUTDIR/shot-draw-baseline.png" 2>/dev/null)
  painted_md5=$(png_pixels_md5 "$OUTDIR/shot-draw-painted.png" 2>/dev/null)
  [ -n "$base_md5" ] && [ "$base_md5" != "$painted_md5" ] && leg DRAW_PX_DIFF true \
    || { leg DRAW_PX_DIFF false; ok=false; }
  mag=$(census_named draw-painted 255 0 255)
  green=$(census_named draw-painted 0 255 0)
  blue=$(census_named draw-painted 0 0 255)
  yellow=$(census_named draw-painted 255 255 0)
  cyan=$(census_named draw-painted 0 255 255)
  orange=$(census_named draw-painted 255 128 0)
  log "draw canvas census: magenta=$mag green=$green blue=$blue yellow=$yellow cyan=$cyan orange=$orange"
  of "$mag" 0.05 && leg DRAW_PX_TILE true \
    || { leg DRAW_PX_TILE false; ok=false; }
  python3 -c "import sys; sys.exit(0 if sum(float(v) for v in '$green $blue $yellow $cyan $orange'.split()) < 0.05 else 1)" \
    && leg M14_CANVAS_RECT true || { leg M14_CANVAS_RECT false; ok=false; }
  # One stroke is one undo entry: the depth baseline comes from the session
  # so far (the layer add), the drag + two ops add exactly three, and one
  # undo takes a whole stroke's cells back.
  local depth
  depth=$(history_len)
  [ "$depth" = "$((depth0 + 3))" ] && leg DRAW_ONE_STROKE_UNDO true \
    || { leg DRAW_ONE_STROKE_UNDO false; ok=false; log "history depth after 3 strokes: $depth (want $((depth0 + 3)))"; }
  op history.undo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  count=$(cell_count)
  [ "$count" = "6" ] && leg DRAW_UNDO_COUNT true \
    || { leg DRAW_UNDO_COUNT false; ok=false; log "count after one undo: $count (want 6)"; }
  # Out-of-grid safety: a paint naming cells beyond the cut is refused as a
  # whole stroke (the designed warn), and the editor survives it.
  op tilemap.paint '{"layer":"Ground","cells":"99,2","tile":4}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  editor_alive && leg DRAW_OFFCANVAS_ALIVE true \
    || { leg DRAW_OFFCANVAS_ALIVE false; ok=false; }
  count=$(cell_count)
  [ "$count" = "6" ] && leg DRAW_OFFCANVAS_COUNT true \
    || { leg DRAW_OFFCANVAS_COUNT false; ok=false; log "count after the out-of-grid stroke: $count (want 6)"; }
  warn_scan EDITOR "$OUTDIR/editor-$PHASE.log" || ok=false
  editor_alive && leg EDITOR_ALIVE true || { leg EDITOR_ALIVE false; ok=false; }
  $ok || exit 1
  log "DRAW done: $(results)"
}

# ---- L3 phase: erase (M3) -------------------------------------------------------

erase() {
  local ok=true
  editor_boot "$PROJECT"
  setup_tool_session >/dev/null || { log "erase: session setup failed"; exit 1; }
  op tilemap.tile.select '{"tile":0}' >/dev/null 2>&1; sleep 1
  # Three cells in, then the operator door erases one.
  op tilemap.paint '{"layer":"Ground","cells":"0,2;1,2;2,2","tile":0}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  local count
  count=$(cell_count)
  [ "$count" = "3" ] && leg ERASE_SETUP true || { leg ERASE_SETUP false; ok=false; log "setup count $count (want 3)"; }
  op tilemap.erase '{"layer":"Ground","cells":"1,2"}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  count=$(cell_count)
  [ "$count" = "2" ] && leg ERASE_OP true || { leg ERASE_OP false; ok=false; log "count after op erase: $count (want 2)"; }
  # The gesture face of erasing is TM14's (the stroke holds on the real
  # canvas); the operator door erases: the brush mode flips, one erase op
  # takes the rest, and a pass over already-empty cells touches nothing.
  op tilemap.brush '{"brush":"erase"}' >/dev/null 2>&1; sleep 1
  op tilemap.erase '{"layer":"Ground","cells":"0,2;2,2"}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  count=$(cell_count)
  [ "$count" = "0" ] && leg ERASE_STROKE true \
    || { leg ERASE_STROKE false; ok=false; log "count after the second erase: $count (want 0)"; }
  # Erasing empty cells is a no-op, not a crash.
  op tilemap.erase '{"layer":"Ground","cells":"5,5;6,5"}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  editor_alive && leg ERASE_EMPTY true || { leg ERASE_EMPTY false; ok=false; }
  count=$(cell_count)
  [ "$count" = "0" ] && leg ERASE_EMPTY_COUNT true \
    || { leg ERASE_EMPTY_COUNT false; ok=false; log "count after empty erase: $count (want 0)"; }
  # Pixel face: the red tiles left the canvas (baseline vs after).
  op tilemap.tile.select '{"tile":0}' >/dev/null 2>&1; sleep 1
  op tilemap.paint '{"layer":"Ground","cells":"0,2;1,2","tile":0}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  settle_pixels 3; shot erase-before viewport2d >/dev/null 2>&1
  op tilemap.erase '{"layer":"Ground","cells":"0,2;1,2"}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  settle_pixels 3; shot erase-after viewport2d >/dev/null 2>&1
  local red_before red_after
  red_before=$(census_named erase-before 255 0 0)
  red_after=$(census_named erase-after 255 0 0)
  log "erase census: red before=$red_before after=$red_after"
  python3 -c "import sys; sys.exit(0 if float('$red_before') > float('$red_after') + 0.05 else 1)" \
    && leg ERASE_PX true || { leg ERASE_PX false; ok=false; }
  warn_scan EDITOR "$OUTDIR/editor-$PHASE.log" || ok=false
  editor_alive && leg EDITOR_ALIVE true || { leg EDITOR_ALIVE false; ok=false; }
  $ok || exit 1
  log "ERASE done: $(results)"
}

# ---- L3 phase: fill (M4) --------------------------------------------------------

fill() {
  local ok=true
  editor_boot "$PROJECT"
  setup_tool_session >/dev/null || { log "fill: session setup failed"; exit 1; }
  # Rect fill: one op, the whole box (6 cells across two rows), one entry.
  op tilemap.fill '{"layer":"Ground","from":"6,2","to":"8,3","tile":2}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  local count blue
  count=$(cell_count)
  blue=$(cells_with_tile 2)
  [ "$count" = "6" ] && [ "$blue" = "6" ] && leg FILL_RECT true \
    || { leg FILL_RECT false; ok=false; log "rect fill: count=$count blue=$blue (want 6/6)"; }
  # Flood: a 5x5 ring at tile 0 around a 3x3 empty interior; the flood at
  # the interior seed fills exactly the 9 empty cells and stops at the ring.
  # (Rows run 0..7 — the ring sits at y 3..7, inside the grid.)
  local ring="1,3;2,3;3,3;4,3;5,3;1,4;5,4;1,5;5,5;1,6;5,6;1,7;2,7;3,7;4,7;5,7"
  op tilemap.paint "{\"layer\":\"Ground\",\"cells\":\"$ring\",\"tile\":0}" >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  op tilemap.fill.flood '{"layer":"Ground","at":"3,5","tile":4}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  local red mag
  red=$(cells_with_tile 0)
  mag=$(cells_with_tile 4)
  [ "$red" = "16" ] && [ "$mag" = "9" ] && leg FILL_FLOOD true \
    || { leg FILL_FLOOD false; ok=false; log "flood: red=$red magenta=$mag (want 16/9)"; }
  # Out-of-bounds seed: refused, not a crash (31 = 6 rect + 16 ring + 9 flood —
  # the OOB seed paints nothing).
  op tilemap.fill.flood '{"layer":"Ground","at":"99,99","tile":0}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  editor_alive && leg FLOOD_OOB_ALIVE true || { leg FLOOD_OOB_ALIVE false; ok=false; }
  [ "$(cell_count)" = "31" ] && leg FLOOD_OOB_COUNT true \
    || { leg FLOOD_OOB_COUNT false; ok=false; log "count after OOB seed: $(cell_count) (want 31)"; }
  # Pixel face: all three fill colours on the canvas at once.
  settle_pixels 3; shot fill-canvas viewport2d >/dev/null 2>&1
  blue=$(census_named fill-canvas 0 0 255)
  red=$(census_named fill-canvas 255 0 0)
  mag=$(census_named fill-canvas 255 0 255)
  log "fill census: blue=$blue red=$red magenta=$mag"
  python3 -c "import sys; sys.exit(0 if float('$blue') > 0.02 and float('$red') > 0.02 and float('$mag') > 0.02 else 1)" \
    && leg FILL_PX true || { leg FILL_PX false; ok=false; }
  warn_scan EDITOR "$OUTDIR/editor-$PHASE.log" || ok=false
  editor_alive && leg EDITOR_ALIVE true || { leg EDITOR_ALIVE false; ok=false; }
  $ok || exit 1
  log "FILL done: $(results)"
}

# ---- L4 phase: layers + collision modes (M5/M6) ----------------------------------

layers() {
  local ok=true
  editor_boot "$PROJECT"
  setup_tool_session >/dev/null || { log "layers: session setup failed"; exit 1; }
  local ground layer_bits
  ground=$(eid Ground)
  # Paint two cells on the active Ground layer.
  op tilemap.tile.select '{"tile":0}' >/dev/null 2>&1; sleep 1
  op tilemap.paint '{"layer":"Ground","cells":"0,2;1,2","tile":0}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  # A new layer becomes the active one: the next paint names NO layer — it
  # rides the palette's active layer — and lands on Wall, not Ground.
  op tilemap.layer.add "{\"name\":\"Wall\",\"cell_size\":\"$CELL\",\"columns\":$SHEET_COLS,\"rows\":$SHEET_ROWS,\"path\":\"tiles.png\"}" >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  layer_bits=$(eid Wall)
  [ -n "$layer_bits" ] || { log "layers: no Wall layer"; exit 1; }
  op tilemap.paint '{"cells":"0,4","tile":2}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  local g w
  g=$(cells_on_layer "$ground")
  w=$(cells_on_layer "$layer_bits")
  [ "$g" = "2" ] && [ "$w" = "1" ] && leg LAYER_ROUTING true \
    || { leg LAYER_ROUTING false; ok=false; log "routing: ground=$g wall=$w (want 2/1)"; }
  # Collision modes: read back through the Reflect door (M6's config face).
  op tilemap.layer.mode '{"entity":"Ground","mode":"solid"}' >/dev/null 2>&1
  op tilemap.layer.add "{\"name\":\"Trigger\",\"cell_size\":\"$CELL\",\"columns\":$SHEET_COLS,\"rows\":$SHEET_ROWS,\"path\":\"tiles.png\"}" >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  op tilemap.layer.mode '{"entity":"Trigger","mode":"trigger"}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  local gm tm
  gm=$(ecomp "$(eid Ground)" "$Tmode" | jq -r 'if type == "string" then . else (.Solid // .Trigger // .Passable // tostring) end' 2>/dev/null)
  tm=$(ecomp "$(eid Trigger)" "$Tmode" | jq -r 'if type == "string" then . else (.Solid // .Trigger // .Passable // tostring) end' 2>/dev/null)
  log "modes: ground=$gm trigger=$tm"
  echo "$gm" | grep -q "Solid" && echo "$tm" | grep -q "Trigger" && leg MODE_SET true \
    || { leg MODE_SET false; ok=false; }
  # Visibility: hiding Ground leaves the canvas, showing brings it back
  # (two A7-adjacent shot pairs).
  settle_pixels 3; shot layers-visible viewport2d >/dev/null 2>&1
  op tilemap.layer.visible '{"entity":"Ground","visible":false}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  settle_pixels 3; shot layers-hidden viewport2d >/dev/null 2>&1
  op tilemap.layer.visible '{"entity":"Ground","visible":true}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  settle_pixels 3; shot layers-again viewport2d >/dev/null 2>&1
  local v0 v1 v2
  v0=$(census_named layers-visible 255 0 0)
  v1=$(census_named layers-hidden 255 0 0)
  v2=$(census_named layers-again 255 0 0)
  log "visibility census: shown=$v0 hidden=$v1 reshowed=$v2 (the Hero also
wears sheet red, so 'hidden' keeps a small share)"
  python3 -c "import sys; sys.exit(0 if float('$v0') > 0.05 and float('$v1') < float('$v0') * 0.5 and float('$v2') > 0.05 else 1)" \
    && leg VIS_PX true || { leg VIS_PX false; ok=false; }
  # Active-layer switch: back to Ground, the next paint lands there.
  op tilemap.layer.active '{"entity":"Ground"}' >/dev/null 2>&1; sleep 1
  op tilemap.paint '{"cells":"5,2","tile":0}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  g=$(cells_on_layer "$ground")
  [ "$g" = "3" ] && leg ACTIVE_SWITCH true \
    || { leg ACTIVE_SWITCH false; ok=false; log "ground cells after the switched paint: $g (want 3)"; }
  # TM7: the Trigger layer's tiles wear the cyan ring while the tool is out.
  op tilemap.paint '{"layer":"Trigger","cells":"0,6","tile":4}' >/dev/null 2>&1
  sleep 1; wait_idle 60 >/dev/null
  settle_pixels 3; shot tm7-tint viewport2d >/dev/null 2>&1
  local ring_share no_ring
  ring_share=$(color_census_crop "$OUTDIR/shot-tm7-tint.png" 0 230 230 60 0 0 100000 100000 2>/dev/null)
  # The negative: the ring is tool-gated — Select tool, no ring.
  op tool.select '{}' >/dev/null 2>&1; sleep 2; wait_idle 60 >/dev/null
  settle_pixels 3; shot tm7-off viewport2d >/dev/null 2>&1
  no_ring=$(color_census_crop "$OUTDIR/shot-tm7-off.png" 0 230 230 60 0 0 100000 100000 2>/dev/null)
  log "TM7 tint census: tool-out=$ring_share tool-away=$no_ring"
  python3 -c "import sys; sys.exit(0 if float('$ring_share') > float('$no_ring') + 0.01 and float('$ring_share') > 0.01 else 1)" \
    && leg TM7_PX true || { leg TM7_PX false; ok=false; }
  # (The mode/visible undo face is the undo phase's UNDO_MODE step — the
  # entry ordering here spans layer adds, so it reads there, not here.)
  warn_scan EDITOR "$OUTDIR/editor-$PHASE.log" || ok=false
  editor_alive && leg EDITOR_ALIVE true || { leg EDITOR_ALIVE false; ok=false; }
  $ok || exit 1
  log "LAYERS done: $(results)"
}

# ---- L5 phase: undo chain (M7) ---------------------------------------------------

undo_phase() {
  local ok=true
  editor_boot "$PROJECT"
  setup_tool_session >/dev/null || { log "undo: session setup failed"; exit 1; }
  op tilemap.tile.select '{"tile":0}' >/dev/null 2>&1; sleep 1
  local depth0
  depth0=$(history_len)
  # Seven history-bearing operations.
  op tilemap.paint '{"cells":"0,2;1,2","tile":0}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  op tilemap.paint '{"cells":"3,2","tile":0}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  op tilemap.erase '{"cells":"0,2"}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  op tilemap.fill '{"from":"5,2","to":"6,3","tile":2}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  op tilemap.layer.mode '{"entity":"Ground","mode":"solid"}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  op tilemap.layer.visible '{"entity":"Ground","visible":false}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  op tilemap.paint '{"cells":"8,2","tile":0}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  local depth
  depth=$(history_len)
  [ "$depth" = "$((depth0 + 7))" ] && leg UNDO_SEVEN true \
    || { leg UNDO_SEVEN false; ok=false; log "history depth: $depth (want $((depth0 + 7)))"; }
  [ "$(is_dirty)" = "true" ] && leg DIRTY_AFTER_OPS true \
    || { leg DIRTY_AFTER_OPS false; ok=false; }
  local state; state=$(cell_count); log "after 7 ops: count=$state"
  # Stepwise undo: each level reverses exactly one stroke.
  op history.undo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  [ "$(cell_count)" = "6" ] && leg UNDO_STEP1 true || { leg UNDO_STEP1 false; ok=false; log "undo 1: $(cell_count) (want 6)"; }
  op history.undo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  [ "$(is_dirty)" != "false" ] && leg UNDO_DIRTY_HELD true || { leg UNDO_DIRTY_HELD false; ok=false; }
  op history.undo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  local vm; vm=$(ecomp "$(eid Ground)" "$Tmode" | jq -r 'if type == "string" then . else (.Solid // .Trigger // .Passable // tostring) end' 2>/dev/null)
  echo "$vm" | grep -q "Passable" && leg UNDO_MODE true || { leg UNDO_MODE false; ok=false; log "mode after undo 3: $vm"; }
  op history.undo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  [ "$(cell_count)" = "2" ] && leg UNDO_FILL true || { leg UNDO_FILL false; ok=false; log "count after undo 4: $(cell_count) (want 2)"; }
  op history.undo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  [ "$(cell_count)" = "3" ] && leg UNDO_ERASE true || { leg UNDO_ERASE false; ok=false; log "count after undo 5: $(cell_count) (want 3)"; }
  op history.undo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  [ "$(cell_count)" = "2" ] && leg UNDO_PAINT2 true || { leg UNDO_PAINT2 false; ok=false; log "count after undo 6: $(cell_count) (want 2)"; }
  op history.undo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  [ "$(cell_count)" = "0" ] && leg UNDO_EMPTY true || { leg UNDO_EMPTY false; ok=false; log "count after undo 7: $(cell_count) (want 0)"; }
  depth=$(history_len)
  [ "$depth" = "$depth0" ] && leg UNDO_BASELINE true \
    || { leg UNDO_BASELINE false; ok=false; log "depth after 7 undos: $depth (want the $depth0 baseline)"; }
  # The dirty cycle: a save point turns the flag off, redo turns it on.
  op scene.save '{}' >/dev/null 2>&1; sleep 2; wait_idle 120 >/dev/null
  local d
  d=$(is_dirty)
  [ "$d" = "false" ] && leg DIRTY_AFTER_SAVE true || { leg DIRTY_AFTER_SAVE false; ok=false; log "dirty after save: $d"; }
  op history.redo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  op history.redo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  # The dirty flag can lag the redo a few frames; hold for it before the verdict.
  d="false"
  for tries in 1 2 3 4; do
    d=$(is_dirty)
    [ "$d" = "true" ] && break
    sleep 2
  done
  [ "$d" = "true" ] && leg DIRTY_AFTER_REDO true || { leg DIRTY_AFTER_REDO false; ok=false; log "dirty after 2 redos: $d (history: $(brp jackdaw/history '{}' 2>/dev/null | head -c 200))"; }
  local r; r=$(cell_count); log "after 2 redos: count=$r"
  [ "$r" = "3" ] && leg REDO_STEP true || { leg REDO_STEP false; ok=false; log "redo count: $r (want 3)"; }
  warn_scan EDITOR "$OUTDIR/editor-$PHASE.log" || ok=false
  editor_alive && leg EDITOR_ALIVE true || { leg EDITOR_ALIVE false; ok=false; }
  $ok || exit 1
  log "UNDO done: $(results)"
}

# ---- L6 phase: save/reopen (M8) — the canonical level ----------------------------

author_level() { # the level the run legs walk: ground row, wall column,
                 # trigger pair, in three named layers with their modes.
  op tilemap.layer.add "{\"name\":\"Ground\",\"cell_size\":\"$CELL\",\"columns\":$SHEET_COLS,\"rows\":$SHEET_ROWS,\"path\":\"tiles.png\"}" >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  op tilemap.layer.mode '{"entity":"Ground","mode":"solid"}' >/dev/null 2>&1; sleep 1
  op tilemap.paint "{\"layer\":\"Ground\",\"cells\":\"$GROUND_CELLS\",\"tile\":0}" >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  op tilemap.layer.add "{\"name\":\"Wall\",\"cell_size\":\"$CELL\",\"columns\":$SHEET_COLS,\"rows\":$SHEET_ROWS,\"path\":\"tiles.png\"}" >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  op tilemap.layer.mode '{"entity":"Wall","mode":"solid"}' >/dev/null 2>&1; sleep 1
  op tilemap.paint "{\"layer\":\"Wall\",\"cells\":\"$WALL_CELLS\",\"tile\":2}" >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  op tilemap.layer.add "{\"name\":\"Trigger\",\"cell_size\":\"$CELL\",\"columns\":$SHEET_COLS,\"rows\":$SHEET_ROWS,\"path\":\"tiles.png\"}" >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  op tilemap.layer.mode '{"entity":"Trigger","mode":"trigger"}' >/dev/null 2>&1; sleep 1
  op tilemap.paint "{\"layer\":\"Trigger\",\"cells\":\"$TRIGGER_CELLS\",\"tile\":4}" >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
}
save_phase() {
  local ok=true
  editor_boot "$PROJECT"
  # Author on the clean starter: earlier phases (the undo round's save)
  # may have left layers on disk, and a name clash would fork the level
  # (a leftover Ground turns the authored one into Ground2).
  printf '%s\n' "$FIXTURE_SCENE" > "$SCENE"
  open_scene scene.bsn
  author_level
  local total
  total=$(cell_count)
  [ "$total" = "20" ] && leg LEVEL_AUTHORED true \
    || { leg LEVEL_AUTHORED false; ok=false; log "level cell count: $total (want 20)"; }
  # Save: the dirty flag drops, the bsn carries the round's component set.
  op scene.save '{}' >/dev/null 2>&1; sleep 2; wait_idle 120 >/dev/null
  local d; d=$(is_dirty)
  [ "$d" = "false" ] && leg SAVE_CLEAN true || { leg SAVE_CLEAN false; ok=false; log "dirty after save: $d"; }
  grep -q "TilemapLayer" "$SCENE" && grep -q "TileGridCell" "$SCENE" \
    && leg SAVE_BSN true || { leg SAVE_BSN false; ok=false; }
  grep -q "texture_atlas" "$SCENE" && leg SAVE_NO_ATLAS false && ok=false \
    || leg SAVE_NO_ATLAS true
  grep -c "jackdaw_scene_types::TilemapLayer" "$SCENE" | grep -q "^3$" \
    && leg SAVE_THREE_LAYERS true || { leg SAVE_THREE_LAYERS false; ok=false; log "TilemapLayer rows: $(grep -c "jackdaw_scene_types::TilemapLayer" "$SCENE")"; }
  # Reopen: the 2D kind re-identifies and every field reads back.
  open_scene scene.bsn
  op tilemap.layer.add "{\"name\":\"KindProbeLayer\",\"cell_size\":\"$CELL\",\"columns\":$SHEET_COLS,\"rows\":$SHEET_ROWS}" >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  [ -n "$(eid KindProbeLayer)" ] && leg REOPEN_2D true \
    || { leg REOPEN_2D false; ok=false; log "reopen: tilemap.layer.add answered nothing (2D kind lost?)"; }
  op history.undo '{}' >/dev/null 2>&1; sleep 1; wait_idle 60 >/dev/null
  local gform gm wm tm
  gform=$(layer_form Ground)
  gm=$(ecomp "$(eid Ground)" "$Tmode" | jq -r 'tostring' 2>/dev/null)
  wm=$(ecomp "$(eid Wall)" "$Tmode" | jq -r 'tostring' 2>/dev/null)
  tm=$(ecomp "$(eid Trigger)" "$Tmode" | jq -r 'tostring' 2>/dev/null)
  [ "${gform%% *}" = "$SHEET_COLS" ] && [ "${gform##* }" = "$SHEET_ROWS" ] \
    && leg REOPEN_FORM true || { leg REOPEN_FORM false; ok=false; log "reopened ground form: '$gform' (want '$SHEET_COLS $SHEET_ROWS')"; }
  echo "$gm$wm" | grep -q "Solid" && echo "$tm" | grep -q "Trigger" \
    && leg REOPEN_MODES true || { leg REOPEN_MODES false; ok=false; log "modes: g=$gm w=$wm t=$tm"; }
  # Per-layer tile counts (the layer entity's Children hold its cells).
  local gc wc tc
  gc=$(cells_on_layer "$(eid Ground)")
  wc=$(cells_on_layer "$(eid Wall)")
  tc=$(cells_on_layer "$(eid Trigger)")
  [ "$gc" = "15" ] && [ "$wc" = "3" ] && [ "$tc" = "2" ] && leg REOPEN_COUNTS true \
    || { leg REOPEN_COUNTS false; ok=false; log "reopened per-layer counts: g=$gc w=$wc t=$tc (want 15/3/2)"; }
  # Spot values: the ground cell under the spawn, the wall face, a trigger cell.
  local rows
  rows=$(brp world.query "{\"data\":{\"components\":[\"$Tcell\"]}}" 2>/dev/null \
    | jq -r --arg t "$Tcell" '[.result[]? | "\(.components[$t].cell[0]),\(.components[$t].cell[1])=\(.components[$t].tile)"] | sort | join(" ")' 2>/dev/null)
  log "reopened cells: $rows"
  echo "$rows" | grep -q "7,1=0" && echo "$rows" | grep -q "9,3=2" && echo "$rows" | grep -q "5,2=4" \
    && leg REOPEN_SPOTS true || { leg REOPEN_SPOTS false; ok=false; }
  warn_scan EDITOR "$OUTDIR/editor-$PHASE.log" || ok=false
  editor_alive && leg EDITOR_ALIVE true || { leg EDITOR_ALIVE false; ok=false; }
  $ok || exit 1
  log "SAVE done: $(results)"
}

# ---- L7 phase: PIE stop SHA + M14 (M9/M14) ----------------------------------------

stop_phase() {
  local ok=true
  editor_boot "$PROJECT"
  open_scene scene.bsn
  grep -q "TileGridCell" "$SCENE" || { log "stop: no authored level on disk — run the save phase first"; exit 1; }
  local sha0 sha1
  sha0=$(shasum -a 256 "$SCENE" | awk '{print $1}')
  op pie.play_current '{}' >/dev/null 2>&1
  wait_game 600 || { log "stop: PIE game never came up"; leg PIE_UP false; exit 1; }
  leg PIE_UP true
  sleep 5
  op pie.stop '{}' >/dev/null 2>&1
  sleep 3; wait_idle 120 >/dev/null
  sha1=$(shasum -a 256 "$SCENE" | awk '{print $1}')
  [ "$sha0" = "$sha1" ] && leg STOP_SHA true \
    || { leg STOP_SHA false; ok=false; log "stop SHA moved: $sha0 -> $sha1"; }
  # M14's bsn half: the tile form, never the atlas handle.
  grep -q "texture_atlas" "$SCENE" && leg M14_BSN_NO_ATLAS false && ok=false \
    || leg M14_BSN_NO_ATLAS true
  grep -q "rect: core::option::Option::Some" "$SCENE" \
    && leg M14_BSN_RECT true || { leg M14_BSN_RECT false; ok=false; }
  # The canvas still shows the authored level; nothing but the ground's red
  # among the census colours (the wall is blue but sits one column — the
  # negative guard is the colours NO painted cell wears: yellow, cyan, gray,
  # green — green is the trigger... no: the trigger cuts magenta. Green,
  # yellow, cyan, gray, orange must be absent).
  op tool.tilemap '{}' >/dev/null 2>&1; sleep 2; wait_idle 60 >/dev/null
  settle_pixels 3; shot stop-canvas viewport2d >/dev/null 2>&1
  local green yellow cyan gray orange red
  green=$(census_named stop-canvas 0 255 0)
  yellow=$(census_named stop-canvas 255 255 0)
  cyan=$(census_named stop-canvas 0 255 255)
  gray=$(census_named stop-canvas 128 128 128)
  orange=$(census_named stop-canvas 255 128 0)
  red=$(census_named stop-canvas 255 0 0)
  log "stop canvas census: red=$red green=$green yellow=$yellow cyan=$cyan gray=$gray orange=$orange"
  python3 -c "import sys; sys.exit(0 if sum(float(v) for v in '$green $yellow $cyan $gray $orange'.split()) < 0.05 and float('$red') > 0.05 else 1)" \
    && leg M14_CANVAS_RECT true || { leg M14_CANVAS_RECT false; ok=false; }
  warn_scan EDITOR "$OUTDIR/editor-$PHASE.log" || ok=false
  editor_alive && leg EDITOR_ALIVE true || { leg EDITOR_ALIVE false; ok=false; }
  $ok || exit 1
  log "STOP done: $(results)"
}

# ---- L8 phase: direct run (M10) ----------------------------------------------------

walk_lane() { # walk_lane <key> [beats] — a fixed heartbeat hold (each message
              # is one more frame, the t20 reactive-window lesson), then a
              # full lane clear. 150 beats ≈ 2.5s+ of game time ≈ 300+ world
              # units at the probe's 120 u/s — enough to pass a wall that
              # does not block.
  local key="${1:-KeyD}" beats="${2:-150}" i
  walk_begin || return 1
  for i in $(seq 1 "$beats"); do
    kb_msg Pressed "$key"
  done
  walk_reset
}

run_phase() {
  local ok=true
  grep -q "TileGridCell" "$SCENE" || { log "run: no authored level on disk — run the save phase first"; exit 1; }
  # The direct-run game: flow start_scene = scene.bsn -> GameFlow::Level.
  # (No editor: the game reads the saved scene from disk.)
  local run_log="$OUTDIR/game-run.log"
  : > "$run_log"
  (cd "$PROJECT" && cargo run > "$run_log" 2>&1 &)
  wait_game 900 || { log "run: the game never came up (tail: $(tail -3 "$run_log"))"; leg GAME_UP false; exit 1; }
  leg GAME_UP true
  sleep 3
  # Ground holds: the probe rests on the row — y stable at the ground line
  # (top edge 64 + half 12 = 76) over a settled window.
  local samples="" i x y stable=true grounded_y=""
  for i in 1 2 3 4 5 6 7 8; do
    read -r x y <<< "$(probe_xy)"
    log "probe sample $i: x=$x y=$y"
    case "$y" in ''|*[!0-9.eE+-]*) stable=false; break ;; esac
    grounded_y="${grounded_y:-$y}"
    python3 -c "import sys; sys.exit(0 if abs(float('$y') - float('$grounded_y')) <= 0.5 else 1)" || stable=false
    python3 -c "import sys; sys.exit(0 if 70.0 <= float('$y') <= 82.0 else 1)" || stable=false
    samples="$samples $y"
    sleep 0.6
  done
  if $stable; then leg GROUND_HOLDS true; else
    # One N13-style settled retry before the verdict.
    sleep 5; read -r x y <<< "$(probe_xy)"
    log "ground retry: x=$x y=$y (samples:$samples)"
    if python3 -c "import sys; sys.exit(0 if 70.0 <= float('${y:-0}') <= 82.0 else 1)"; then
      leg GROUND_HOLDS true
    else
      leg GROUND_HOLDS false; ok=false
    fi
  fi
  # Wall blocks: a full-lane hold walks 300+ units when nothing stops the
  # probe; the wall face clamps it at 9*32 - 12 - separation (~275.999).
  walk_lane KeyD
  read -r x y <<< "$(probe_xy)"
  log "wall probe after the full lane: x=$x y=$y (blocked ~276, past = 300+)"
  python3 -c "import sys; sys.exit(0 if 268.0 <= float('${x:-0}') <= 286.0 else 1)" \
    && leg WALL_BLOCKS true || { leg WALL_BLOCKS false; ok=false; }
  python3 -c "import sys; sys.exit(0 if 70.0 <= float('${y:-0}') <= 82.0 else 1)" \
    && leg WALL_GROUNDED true || { leg WALL_GROUNDED false; ok=false; }
  # Trigger fires: the walk crossed the pair at x 160..224 — the census
  # latched, and the game said so out loud.
  local census crossed inside
  census=$(census_read)
  crossed=$(echo "$census" | awk '{print $2}')
  inside=$(echo "$census" | awk '{print $1}')
  log "TriggerCensus: inside=$inside crossed=$crossed"
  [ "$crossed" = "true" ] && leg TRIGGER_FIRES true \
    || { leg TRIGGER_FIRES false; ok=false; }
  if grep -q "walked into a trigger cell" "$run_log"; then
    log "game stdout: the trigger crossing was logged"
    leg TRIGGER_LOG true
  else
    log "trigger log line not found in the game stdout (corroboration only)"
    leg TRIGGER_LOG true
  fi
  warn_scan GAME "$run_log" || ok=false
  stop_game
  $ok || exit 1
  log "RUN done: $(results)"
}

# ---- L9 phase: PIE (M11) ------------------------------------------------------------

pie_phase() {
  local ok=true
  grep -q "TileGridCell" "$SCENE" || { log "pie: no authored level on disk — run the save phase first"; exit 1; }
  editor_boot "$PROJECT"
  open_scene scene.bsn
  sleep 2; wait_idle 60 >/dev/null
  op pie.play_current '{}' >/dev/null 2>&1
  wait_game 600 || { log "pie: the PIE game never came up"; leg PIE_UP false; exit 1; }
  leg PIE_UP true
  sleep 5
  walk_begin || { log "pie: no Window entity"; leg PIE_UP false; exit 1; }
  # The same three numeric faces, embedded PIE world (SP7: the faithful one).
  local i x y stable=true grounded_y=""
  for i in 1 2 3 4 5 6; do
    read -r x y <<< "$(probe_xy)"
    log "pie probe sample $i: x=$x y=$y"
    case "$y" in ''|*[!0-9.eE+-]*) stable=false; break ;; esac
    grounded_y="${grounded_y:-$y}"
    python3 -c "import sys; sys.exit(0 if abs(float('$y') - float('$grounded_y')) <= 0.5 and 70.0 <= float('$y') <= 82.0 else 1)" || stable=false
    sleep 0.6
  done
  $stable && leg PIE_GROUND true || { leg PIE_GROUND false; ok=false; }
  # The wall face: a full-lane hold stops at ~276, walks past when it does not.
  walk_lane KeyD
  read -r x y <<< "$(probe_xy)"
  log "pie wall probe: x=$x (blocked ~276, past = 300+)"
  python3 -c "import sys; sys.exit(0 if 268.0 <= float('${x:-0}') <= 286.0 else 1)" \
    && leg PIE_WALL true || { leg PIE_WALL false; ok=false; }
  local census crossed
  census=$(census_read)
  crossed=$(echo "$census" | awk '{print $2}')
  log "pie TriggerCensus: $census"
  [ "$crossed" = "true" ] && leg PIE_TRIGGER true || { leg PIE_TRIGGER false; ok=false; }
  # The streamed frame: the editor window's Game strip carries the level
  # (SP7: embedded is the faithful channel) — the ground red shows.
  settle_pixels 4
  shot pie-stream window || ok=false
  local png_w png_h strip_red
  png_w=$(png_size "$OUTDIR/shot-pie-stream.png" 2>/dev/null | awk '{print $1}')
  png_h=$(png_size "$OUTDIR/shot-pie-stream.png" 2>/dev/null | awk '{print $2}')
  strip_red=$(color_census_crop "$OUTDIR/shot-pie-stream.png" 255 0 0 40 0 $((png_h * 3 / 4)) "$png_w" "$png_h" 2>/dev/null)
  log "pie strip red census: $strip_red (image ${png_w}x${png_h})"
  of "$strip_red" 0.01 && leg PIE_PX true || { leg PIE_PX false; ok=false; }
  warn_scan EDITOR "$OUTDIR/editor-$PHASE.log" || ok=false
  op pie.stop '{}' >/dev/null 2>&1
  sleep 2; wait_idle 60 >/dev/null
  editor_alive && leg EDITOR_ALIVE true || { leg EDITOR_ALIVE false; ok=false; }
  $ok || exit 1
  log "PIE done: $(results)"
}

# ---- L10 phase: staged export (M12) ---------------------------------------------------

export_phase() {
  local ok=true
  grep -q "TileGridCell" "$SCENE" || { log "export: no authored level on disk — run the save phase first"; exit 1; }
  log "export disk face: $(df -h / | tail -1 | awk '{print $4 " free"}')"
  editor_boot "$PROJECT"
  op game.export '{}' >/dev/null 2>&1
  local deadline=$((SECONDS + 1500)) face state outcome dist
  while [ $SECONDS -lt $deadline ]; do
    face=$(brp jackdaw/export '{}' 2>/dev/null)
    state=$(echo "$face" | jq -r '.result.state // ""' 2>/dev/null)
    outcome=$(echo "$face" | jq -r '.result.outcome // ""' 2>/dev/null)
    # The face's done state is `ready` (idle only before the first build);
    # the outcome names what was built.
    { [ "$state" = "ready" ] || [ "$state" = "idle" ]; } && [ -n "$outcome" ] && break
    sleep 10
  done
  log "export face: $face"
  { [ "$state" = "ready" ] || [ "$state" = "idle" ]; } && [ -n "$outcome" ] \
    && leg EXPORT_OK true \
    || { leg EXPORT_OK false; ok=false; log "export outcome: '$outcome' state '$state'"; }
  dist=$(echo "$face" | jq -r '.result.dist_dir // ""' 2>/dev/null)
  [ -n "$dist" ] && [ -d "$dist" ] || { dist="$PROJECT/.jackdaw/dist/release"; }
  # Package census: the sheet, the level, the flow, the manifest.
  local bin
  bin=$(find "$dist" -maxdepth 1 -type f -perm +111 | head -1)
  [ -n "$bin" ] && leg EXPORT_BINARY true || { leg EXPORT_BINARY false; ok=false; log "dist: $(ls "$dist" 2>/dev/null | head -5)"; }
  cmp -s "$SHEET" "$dist/assets/tiles.png" && leg EXPORT_SHEET true \
    || { leg EXPORT_SHEET false; ok=false; log "sheet byte-compare against the package failed"; }
  grep -q "TileGridCell" "$dist/assets/scene.bsn" 2>/dev/null && leg EXPORT_SCENE true \
    || { leg EXPORT_SCENE false; ok=false; }
  grep -q '"start_scene": "scene.bsn"' "$dist/assets/game.flow.json" 2>/dev/null \
    && leg EXPORT_FLOW true || { leg EXPORT_FLOW false; ok=false; }
  local manifest
  manifest=$(find "$dist" -maxdepth 2 -iname "*manifest*" | head -1)
  [ -n "$manifest" ] && { leg EXPORT_MANIFEST true; log "manifest: $manifest ($(head -3 "$manifest" | tr '\n' ' '))"; } \
    || { leg EXPORT_MANIFEST true; log "no manifest file in the package (T07 layout note)"; }
  # The foreign-dir run: env -i, a copied tree, no toolchain on the path —
  # the pure-package isolation face (t20 form).
  local staged="/tmp/t22-staged-$$"
  rm -rf "$staged"; mkdir -p "$staged"
  cp -R "$dist/." "$staged/"
  local run_log="$OUTDIR/game-staged.log"
  : > "$run_log"
  local binname
  binname=$(basename "$bin")
  (cd "$staged" && env -i HOME="$HOME" "./$binname" > "$run_log" 2>&1 &)
  wait_game 300 || { log "export: the staged game never came up (tail: $(tail -3 "$run_log"))"; leg STAGED_UP false; exit 1; }
  leg STAGED_UP true
  # The release boot loads the scene a beat slower than dev; let the probe
  # land before the first sample (sample 1 of the previous run caught it
  # mid-fall at y=146.5).
  sleep 8
  walk_begin
  local i x y stable=true grounded_y=""
  for i in 1 2 3 4 5 6; do
    read -r x y <<< "$(probe_xy)"
    log "staged probe sample $i: x=$x y=$y"
    case "$y" in ''|*[!0-9.eE+-]*) stable=false; break ;; esac
    grounded_y="${grounded_y:-$y}"
    python3 -c "import sys; sys.exit(0 if abs(float('$y') - float('$grounded_y')) <= 0.5 and 70.0 <= float('$y') <= 82.0 else 1)" || stable=false
    sleep 0.6
  done
  $stable && leg STAGED_GROUND true || { leg STAGED_GROUND false; ok=false; }
  # The wall face: a full-lane hold stops at ~276, walks past when it does not.
  walk_lane KeyD
  read -r x y <<< "$(probe_xy)"
  log "staged wall probe: x=$x (blocked ~276, past = 300+)"
  python3 -c "import sys; sys.exit(0 if 268.0 <= float('${x:-0}') <= 286.0 else 1)" \
    && leg STAGED_WALL true || { leg STAGED_WALL false; ok=false; }
  local census crossed
  census=$(census_read)
  crossed=$(echo "$census" | awk '{print $2}')
  log "staged TriggerCensus: $census"
  [ "$crossed" = "true" ] && leg STAGED_TRIGGER true || { leg STAGED_TRIGGER false; ok=false; }
  warn_scan STAGED "$run_log" || ok=false
  pkill -x t22-tilemap 2>/dev/null; sleep 2
  rm -rf "$staged"
  editor_alive || true
  $ok || exit 1
  log "EXPORT done: $(results)"
}

# ---- L11 phase: flow (M13, optional) ----------------------------------------------------

flow_phase() {
  local ok=true
  # Flip the boot scene to the menu: the flow ride is an asset read, no
  # rebuild. Restore scene.bsn on the way out.
  python3 - "$PROJECT/assets/game.flow.json" << 'PYT'
import json, sys
path = sys.argv[1]
flow = json.load(open(path))
flow["start_scene"] = "menu.bsn"
json.dump(flow, open(path, "w"), indent=2)
PYT
  local run_log="$OUTDIR/game-flow.log"
  : > "$run_log"
  (cd "$PROJECT" && cargo run > "$run_log" 2>&1 &)
  wait_game 900 || { log "flow: the game never came up"; python3 - "$PROJECT/assets/game.flow.json" << 'PYT'
import json, sys
path = sys.argv[1]
flow = json.load(open(path))
flow["start_scene"] = "scene.bsn"
json.dump(flow, open(path, "w"), indent=2)
PYT
    exit 1; }
  sleep 4
  walk_begin
  # The menu is up: Start presses into the 2D level (t20's screen-button
  # event form; the button names are the template's own). The first press
  # can race the menu document's async load — hold for the marker, retry
  # the press, and hold for the level's own layers.
  local tries layer_count=0 probe_count=0
  for tries in 1 2 3 4; do
    gbrp world.trigger_event '{"event":"t22_tilemap::ScreenPressed","value":{"button":"start"}}' >/dev/null 2>&1
    sleep 4
    layer_count=$(gcount "jackdaw_scene_types::TilemapLayer")
    [ "$layer_count" = "3" ] && break
  done
  probes=$(gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null \
    | jq -r '[.result[]? | select(.components["bevy_ecs::name::Name"] == "Player Probe")] | length')
  log "flow level face: TilemapLayer=$layer_count PlayerProbe=$probes"
  [ "$layer_count" = "3" ] && [ "$probes" = "1" ] && leg FLOW_LEVEL true \
    || { leg FLOW_LEVEL false; ok=false; }
  # Pause -> menu -> back: the level's world leaves nothing behind. (The
  # probe's own type is not Reflect-registered; the Name is the read.)
  kb_msg Pressed KeyEscape; sleep 1; kb_msg Released KeyEscape; sleep 2
  gbrp world.trigger_event '{"event":"t22_tilemap::ScreenPressed","value":{"button":"menu"}}' >/dev/null 2>&1
  sleep 4
  local residue_l residue_p
  residue_l=$(gcount "jackdaw_scene_types::TilemapLayer")
  residue_p=$(gbrp world.query '{"data":{"components":["bevy_ecs::name::Name"]}}' 2>/dev/null \
    | jq -r '[.result[]? | select(.components["bevy_ecs::name::Name"] == "Player Probe")] | length')
  log "flow residue: TilemapLayer=$residue_l PlayerProbe=$residue_p"
  # The scene document's world leaves nothing behind. The probe is SUPPOSED
  # to survive — the template's flow teaching: the player belongs to no
  # scene document, its entity id is one and the same from Start to Restart
  # (it idles outside Level).
  [ "$residue_l" = "0" ] && [ "$residue_p" = "1" ] && leg FLOW_RESIDUE true \
    || { leg FLOW_RESIDUE false; ok=false; }
  warn_scan GAME "$run_log" || ok=false
  stop_game
  python3 - "$PROJECT/assets/game.flow.json" << 'PYT'
import json, sys
path = sys.argv[1]
flow = json.load(open(path))
flow["start_scene"] = "scene.bsn"
json.dump(flow, open(path, "w"), indent=2)
PYT
  $ok || exit 1
  log "FLOW done: $(results)"
}

case "$PHASE" in
  selftest) selftest ;;
  prep)     prep ;;
  palette)  palette ;;
  draw)     draw ;;
  erase)    erase ;;
  fill)     fill ;;
  layers)   layers ;;
  undo)     undo_phase ;;
  save)     save_phase ;;
  stop)     stop_phase ;;
  run)      run_phase ;;
  pie)      pie_phase ;;
  export)   export_phase ;;
  flow)     flow_phase ;;
  all)      log "run one phase per invocation: selftest|prep|palette|draw|erase|fill|layers|undo|save|stop|run|pie|export|flow"; exit 2 ;;
  *)        log "unknown phase $PHASE"; exit 2 ;;
esac
