#!/bin/bash
# T12-T2, QA-promoted leg: the hud.bsn editor round trip must be a zero diff.
# Open the warm project's hud.bsn in the editor (2D UI canvas), touch nothing,
# scene.save, and compare SHA256 before/after. A diff means either serializer
# normalization (acceptable if explainable, seed should be rewritten to the
# normalized shape) or semantic drift (the T1 seed bug family again).
# Usage: bash loop/qa/t12t2-roundtrip.sh [project] [port]
set -u
PROJECT="${1:-/Users/zhanglinbo/workspace/loop-mac/t12t1-game/t12t1-game}"
PORT="${2:-15901}"
REPO=/Users/zhanglinbo/workspace/jackdaw
OUTDIR="$REPO/loop/t12t2-live"
EDITOR_LOG="$OUTDIR/t12t2-roundtrip-editor.log"
CONSOLE_LOG="$OUTDIR/t12t2-roundtrip-console.log"
HUD="$PROJECT/assets/hud.bsn"
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
    log "dialog up: $st"
    op dialog.answer '{"choice":"0"}' >/dev/null 2>&1
    sleep 2
  fi
}

pkill -x jackdaw 2>/dev/null
sleep 1
SHA_BEFORE=$(shasum -a 256 "$HUD" | awk '{print $1}')
log "hud.bsn sha256 before: $SHA_BEFORE"

export JACKDAW_OPEN_PROJECT="$PROJECT"
export JACKDAW_REMOTE_PORT="$PORT"
export JACKDAW_WINDOW_SIZE=1600x900
cd "$REPO"
nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$EDITOR_LOG" 2>&1 &
ok=""
for i in $(seq 1 150); do
  sleep 2
  if brp jackdaw/status '{}' >/dev/null 2>&1; then ok=1; break; fi
  pgrep -x jackdaw >/dev/null || { log "EDITOR_BOOT_FAIL"; exit 1; }
done
[ -n "$ok" ] || { log "EDITOR_BOOT_FAIL (timeout)"; exit 1; }
wait_idle 600; sleep 3
dismiss_dialog
log "EDITOR_READY"

op scene.open "{\"path\":\"$HUD\"}" >/dev/null 2>&1
sleep 3
wait_idle 300; sleep 2
dismiss_dialog
# Save only once the hud document is actually in front (the active scene's
# bsn names the root); saving mid-open serializes a half-loaded world.
open_ok=false
for i in $(seq 1 30); do
  if brp jackdaw/scene_bsn '{}' 2>/dev/null | jq -re '.result // empty' 2>/dev/null | grep -q "HudRoot"; then
    open_ok=true
    break
  fi
  sleep 1
done
if [ "$open_ok" = true ]; then
  log "hud document confirmed open"
else
  log "WARN: HudRoot not seen in the active scene bsn; saving anyway"
fi
op scene.save '{}' >/dev/null 2>&1
sleep 3
wait_idle 300; sleep 2
dismiss_dialog

SHA_AFTER=$(shasum -a 256 "$HUD" | awk '{print $1}')
log "hud.bsn sha256 after:  $SHA_AFTER"
# Archive the saved shape for diagnosis before the cleanup restores the seed.
cp "$HUD" "$OUTDIR/t12t2-roundtrip-after.bsn"
if [ "$SHA_BEFORE" = "$SHA_AFTER" ]; then
  log "VERDICT_ROUNDTRIP: PASS (zero diff)"
else
  log "VERDICT_ROUNDTRIP: FAIL (diff archived in t12t2-roundtrip-after.bsn; header+40 lines follow)"
  sed -n '1,40p' "$HUD" >> "$CONSOLE_LOG" 2>/dev/null
fi
op pie.stop '{}' >/dev/null 2>&1
pkill -x jackdaw 2>/dev/null
log "T12T2_ROUNDTRIP_DONE"
