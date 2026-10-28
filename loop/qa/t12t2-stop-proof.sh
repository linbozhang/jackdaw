#!/bin/bash
# T12-T2: the Stop iron proof, now over both documents. Play a PIE session
# with binding evaluation running, Stop, and both scene.bsn and hud.bsn must
# be byte-identical to before (a play session never writes the authored
# documents).
# Usage: bash loop/qa/t12t2-stop-proof.sh [project] [port]
set -u
PROJECT="${1:-/Users/zhanglinbo/workspace/loop-mac/t12t1-game/t12t1-game}"
PORT="${2:-15906}"
GAME_PORT=15702
REPO=/Users/zhanglinbo/workspace/jackdaw
OUTDIR="$REPO/loop/t12t2-live"
EDITOR_LOG="$OUTDIR/t12t2-stop-editor.log"
CONSOLE_LOG="$OUTDIR/t12t2-stop-console.log"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
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
game_up() { curl -s -m 5 -X POST "http://127.0.0.1:$GAME_PORT/" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"jackdaw/app_info"}' | jq -e '.result.app_name' >/dev/null 2>&1; }

pkill -x jackdaw 2>/dev/null; pkill -f 't12t1-game$' 2>/dev/null
sleep 1
SHA_SCENE_BEFORE=$(shasum -a 256 "$PROJECT/assets/scene.bsn" | awk '{print $1}')
SHA_HUD_BEFORE=$(shasum -a 256 "$PROJECT/assets/hud.bsn" | awk '{print $1}')
log "scene.bsn before: $SHA_SCENE_BEFORE"
log "hud.bsn before:   $SHA_HUD_BEFORE"

export JACKDAW_OPEN_PROJECT="$PROJECT" JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1600x900
cd "$REPO"
nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$EDITOR_LOG" 2>&1 &
for i in $(seq 1 150); do
  sleep 2
  brp jackdaw/status '{}' >/dev/null 2>&1 && break
done
sleep 3
brp jackdaw/wait '{"until":"idle"}' >/dev/null 2>&1
st=$(brp jackdaw/status '{}' | jq -r '.result.dialog // empty')
[ -n "$st" ] && [ "$st" != "null" ] && op dialog.answer '{"choice":"0"}' >/dev/null 2>&1
log "EDITOR_READY"

op scene.open "{\"path\":\"$PROJECT/assets/scene.bsn\"}" >/dev/null 2>&1
sleep 2
op pie.play_current >/dev/null 2>&1
for i in $(seq 1 300); do
  sleep 2
  game_up && break
done
sleep 6
log "game up: $(game_up && echo yes || echo no)"
op pie.stop >/dev/null 2>&1
sleep 4
pkill -f 't12t1-game$' 2>/dev/null
sleep 2

SHA_SCENE_AFTER=$(shasum -a 256 "$PROJECT/assets/scene.bsn" | awk '{print $1}')
SHA_HUD_AFTER=$(shasum -a 256 "$PROJECT/assets/hud.bsn" | awk '{print $1}')
log "scene.bsn after:  $SHA_SCENE_AFTER"
log "hud.bsn after:    $SHA_HUD_AFTER"
if [ "$SHA_SCENE_BEFORE" = "$SHA_SCENE_AFTER" ] && [ "$SHA_HUD_BEFORE" = "$SHA_HUD_AFTER" ]; then
  log "VERDICT_STOP_PROOF: PASS (both documents untouched)"
else
  log "VERDICT_STOP_PROOF: FAIL (a play session wrote an authored document)"
fi
pkill -x jackdaw 2>/dev/null
log "T12T2_STOP_DONE"
