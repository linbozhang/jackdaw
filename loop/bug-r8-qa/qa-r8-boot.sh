#!/bin/bash
# R8 QA live leg, boot phase (mirrors loop/bug-r7-qa/r7-live.sh boot):
# bsn_game fixture (no jackdaw.toml -> "Open without setup"), port 15703,
# no-save policy with scene SHA before the run.
# Usage: bash loop/bug-r8-qa/qa-r8-boot.sh
set -u
REPO=/Users/linbo.zhang/workspace/jackdaw
PROJECT="$REPO/tests/fixtures/bsn_game"
PORT=15703
OUTDIR="$REPO/loop/bug-r8-qa"
TOOLCHAIN_LIB=/Users/linbo.zhang/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
EDITOR_LOG="$OUTDIR/r8qa-editor.log"
CONSOLE_LOG="$OUTDIR/r8qa-console.log"
SCENE="$PROJECT/assets/scene.bsn"
mkdir -p "$OUTDIR"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$CONSOLE_LOG"; }

brp() {
  local reply
  reply=$(curl -s --max-time 20 -X POST "http://127.0.0.1:$PORT/" \
    -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}")
  printf '%s' "$reply"
}
wait_idle() {
  local deadline=$(( SECONDS + ${1:-300} ))
  while [ $SECONDS -lt $deadline ]; do
    if brp jackdaw/wait '{"until":"idle"}' 2>/dev/null | jq -e '.result.idle == true' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}
cleanup() {
  pkill -x jackdaw 2>/dev/null; sleep 2; pkill -9 -x jackdaw 2>/dev/null
  sleep 1
}
port_silent() { [ -z "$(curl -s --max-time 2 "http://127.0.0.1:$PORT/" 2>/dev/null)" ]; }

for squatter in 1 2 3 4 5; do
  cleanup
  port_silent && break
done
port_silent || { log "BOOT_FAIL: port $PORT still answered after five kills"; exit 1; }
: > "$EDITOR_LOG"
shasum -a 256 "$SCENE" | tee -a "$CONSOLE_LOG" > "$OUTDIR/r8qa-scene-sha-before.txt"
export JACKDAW_OPEN_PROJECT="$PROJECT"
export PATH="$HOME/.cargo/bin:$PATH"
export JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1920x1080
cd "$REPO"
nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$EDITOR_LOG" 2>&1 &
BOOT_PID=$!
echo "$BOOT_PID" > "$OUTDIR/r8qa-boot-pid.txt"
log "boot: editor pid=$BOOT_PID binary=$(ls -la target/debug/jackdaw | awk '{print $6, $7, $8}')"
ok=""
for i in $(seq 1 150); do
  sleep 2
  if brp jackdaw/status '{}' 2>/dev/null | jq -e '.result.pid' >/dev/null 2>&1 && kill -0 "$BOOT_PID" 2>/dev/null; then ok=1; break; fi
  kill -0 "$BOOT_PID" 2>/dev/null || break
done
[ -n "$ok" ] || { log "BOOT_FAIL: the BRP never answered"; exit 1; }
sleep 5
wait_idle 900 || { log "BOOT_FAIL: the asset pipeline never went idle"; exit 1; }
sleep 3
brp jackdaw/ui_tree '{"text":"closed unexpectedly","depth":3}' > "$OUTDIR/r8qa-walk-boot-recovery.json" 2>/dev/null
if grep -qF "closed unexpectedly" "$OUTDIR/r8qa-walk-boot-recovery.json"; then
  log "recovery modal present, dismissing via Discard All"
  brp jackdaw/ui_click '{"text":"Discard All"}' > "$OUTDIR/r8qa-click-discard.json" 2>/dev/null
  sleep 2; wait_idle 120
fi
# "Open without setup" path (fixture has no jackdaw.toml)
brp jackdaw/ui_tree '{"text":"Open without setup","depth":8}' > "$OUTDIR/r8qa-walk-setup-dialog.json" 2>/dev/null
if grep -qF "Open without setup" "$OUTDIR/r8qa-walk-setup-dialog.json"; then
  log "setup dialog up; clicking Open without setup"
  brp jackdaw/ui_click '{"text":"Open without setup"}' > "$OUTDIR/r8qa-click-open-setup.json" 2>/dev/null
  sleep 3; wait_idle 300; sleep 3
else
  log "no setup dialog present (project may already be open)"
fi
if ! brp jackdaw/status '{}' 2>/dev/null | jq -e '.result.project != null' >/dev/null 2>&1; then
  log "project face still null; trying a direct scene.open"
  brp jackdaw/call_operator "{\"id\":\"scene.open\",\"params\":{\"path\":\"$SCENE\",\"reload\":true}}" \
    > "$OUTDIR/r8qa-scene-open.json" 2>/dev/null
  sleep 3; wait_idle 120
fi
brp jackdaw/status '{}' | jq -c '{project: .result.project, scene: .result.scene, selection: .result.selection}' | tee -a "$CONSOLE_LOG" > "$OUTDIR/r8qa-status-boot.json"
brp jackdaw/version '{}' > "$OUTDIR/r8qa-version.json" 2>/dev/null || true
log "EDITOR_READY pid=$BOOT_PID"
