#!/bin/bash
# T12-T3 probe 2: nail the Entity parameter form for document entities.
#  A: world.query id + world.get_component on that id (same world?)
#  B: component.set by NAME ("HealthBar") — the document carries Name
#  C: component.set by Int bits
#  D: read the op outcome JSON warnings
# Usage: bash loop/qa/t12t3-probe2.sh [project] [port]
set -u
PROJECT="${1:-/Users/zhanglinbo/workspace/loop-mac/t12t1-game/t12t1-game}"
PORT="${2:-15916}"
REPO=/Users/zhanglinbo/workspace/jackdaw
OUTDIR="$REPO/loop/t12t3-live"
EDITOR_LOG="$OUTDIR/t12t3-probe2-editor.log"
CONSOLE_LOG="$OUTDIR/t12t3-probe2-console.log"
HUD="$PROJECT/assets/hud.bsn"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
BIND_TP='jackdaw_bind::types::Bindings'
mkdir -p "$OUTDIR"
: > "$CONSOLE_LOG"
log() { echo "$@" | tee -a "$CONSOLE_LOG"; }
brp() {
  local method="$1" params="${2:-}" id=$RANDOM body
  if [ -n "$params" ]; then
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params")
  else
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s"}' "$id" "$method")
  fi
  curl -s -m 30 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' -d "$body"
}
op() {
  local id="$1" params="${2:-}"
  if [ -n "$params" ]; then brp jackdaw/call_operator "{\"id\":\"$id\",\"params\":$params}"
  else brp jackdaw/call_operator "{\"id\":\"$id\"}"; fi
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
    op dialog.answer '{"choice":"0"}' >/dev/null 2>&1; sleep 2
  fi
}

pkill -x jackdaw 2>/dev/null; sleep 1
cp "$HUD" "$HUD.bak"
export JACKDAW_OPEN_PROJECT="$PROJECT" JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1600x900
cd "$REPO"
nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$EDITOR_LOG" 2>&1 &
ok=""
for i in $(seq 1 150); do
  sleep 2
  if brp jackdaw/status '{}' >/dev/null 2>&1; then ok=1; break; fi
  pgrep -x jackdaw >/dev/null || { log "EDITOR_BOOT_FAIL"; exit 1; }
done
[ -n "$ok" ] || { log "EDITOR_BOOT_FAIL (timeout)"; exit 1; }
wait_idle 600; sleep 3; dismiss_dialog

op scene.open "{\"path\":\"$HUD\"}" >/dev/null 2>&1
sleep 3; wait_idle 300; sleep 2; dismiss_dialog
log "hud open: $(brp jackdaw/scene_bsn '{}' | jq -r '.result' | grep -c HudRoot)"

Q=$(brp world.query "{\"data\":{\"components\":[\"$BIND_TP\",\"jackdaw_widgets_runtime::Progress\"]}}" 2>/dev/null)
log "A query raw: $(echo "$Q" | head -c 300)"
EID=$(echo "$Q" | jq -r '.result[0].entity // empty')
INT=$(python3 -c 'import sys; i,g=sys.argv[1].split("v"); print(int(i)+int(g)*(2**32))' "$EID" 2>/dev/null)
log "A entity=$EID int_bits=$INT"
log "A get_component by id string: $(brp world.get_component "{\"entity\":\"$EID\",\"component_type\":\"$BIND_TP\"}" | head -c 220)"

log "B by name: $(op component.set "{\"entity\":\"HealthBar\",\"type_path\":\"$BIND_TP\",\"field\":\"\",\"value\":\"[]\"}" | head -c 300)"
sleep 1
log "B after: scene_bsn Bindings lines with [] = $(brp jackdaw/scene_bsn '{}' | jq -r '.result' | grep -c 'Bindings(\[\]')"

log "C by int: $(op component.set "{\"entity\":$INT,\"type_path\":\"$BIND_TP\",\"field\":\"\",\"value\":\"[]\"}" | head -c 300)"

pkill -x jackdaw 2>/dev/null
cp "$HUD.bak" "$HUD"
log "T12T3_PROBE2_DONE"
