#!/bin/bash
# T15-T3: the AN10 fixture purge leg. Loads the fixture's leaked graph.bsn
# into the fixed editor, saves it, and asserts the document no longer
# carries the canvas nodes while the rig's AnimationGraphRef stays.
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
PROJECT=/Users/zhanglinbo/workspace/loop-mac/t15-anim/t15-anim
GRAPH="$PROJECT/assets/graph.bsn"
PORT=15930
OUT="$REPO/loop/reports"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
CONSOLE="$OUT/t15t3_an10_purge_console.log"
: > "$CONSOLE"
log() { echo "$@" | tee -a "$CONSOLE"; }

brp_raw() {
  local method="$1" params="${2:-}" id=$RANDOM body
  if [ -n "$params" ]; then
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params")
  else
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s"}' "$id" "$method")
  fi
  curl -s -m 60 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' -d "$body"
}
op() {
  local id="$1" params="${2:-}"
  if [ -n "$params" ]; then brp_raw jackdaw/call_operator "{\"id\":\"$id\",\"params\":$params}"
  else brp_raw jackdaw/call_operator "{\"id\":\"$id\",\"params\":{}}"; fi
}
wait_idle() {
  local deadline=$((SECONDS + ${1:-300}))
  while [ $SECONDS -lt $deadline ]; do
    if brp_raw jackdaw/wait '{"until":"idle"}' | jq -e '.result.idle == true' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}

cleanup() {
  op pie.stop >/dev/null 2>&1
  sleep 1
  pkill -x jackdaw 2>/dev/null
  pkill -x t15-anim 2>/dev/null
  sleep 1
}
trap cleanup EXIT

BEFORE_NODES=$(grep -c "jackdaw_node_graph::graph::GraphNode" "$GRAPH")
BEFORE_REF=$(grep -c "AnimationGraphRef" "$GRAPH")
BEFORE_SHA=$(shasum -a 256 "$GRAPH" | awk '{print $1}')
log "PURGE_BEFORE leaked_nodes=$BEFORE_NODES graphref=$BEFORE_REF sha=$BEFORE_SHA"

pkill -x jackdaw 2>/dev/null; sleep 1
export JACKDAW_OPEN_PROJECT="$PROJECT" JACKDAW_REMOTE_PORT="$PORT" JACKDAW_WINDOW_SIZE=1600x900
cd "$REPO"
nohup env DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB" ./target/debug/jackdaw > "$OUT/t15t3_an10_purge_editor.log" 2>&1 &
ok=""
for i in $(seq 1 150); do
  sleep 2
  if brp_raw jackdaw/status '{}' >/dev/null 2>&1; then ok=1; break; fi
  pgrep -x jackdaw >/dev/null || break
done
[ -n "$ok" ] || { log "EDITOR_BOOT_FAIL"; exit 1; }
sleep 5
wait_idle 600; sleep 3
log "EDITOR_READY"

# Open the leaked document (reload so a stale tab rereads the file).
op scene.open "{\"path\":\"$GRAPH\",\"reload\":true}" >/dev/null 2>&1
sleep 3
wait_idle 300; sleep 2
log "SCENE_OPENED"

# Save through the operator (the same path M13 used).
op scene.save >/dev/null 2>&1
sleep 3
wait_idle 120; sleep 1

AFTER_NODES=$(grep -c "jackdaw_node_graph::graph::GraphNode" "$GRAPH")
AFTER_REF=$(grep -c "AnimationGraphRef" "$GRAPH")
AFTER_SHA=$(shasum -a 256 "$GRAPH" | awk '{print $1}')
log "PURGE_AFTER leaked_nodes=$AFTER_NODES graphref=$AFTER_REF sha=$AFTER_SHA"

if [ "$AFTER_NODES" = "0" ] && [ "$AFTER_REF" != "0" ]; then
  log "AN10_PURGE_PASS"
else
  log "AN10_PURGE_FAIL"
fi
echo "$GRAPH" | xargs cat > "$OUT/t15t3_an10_purge_graph.bsn"
