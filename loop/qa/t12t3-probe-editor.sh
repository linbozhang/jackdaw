#!/bin/bash
# T12-T3 probe: which editor-side channels the matrix legs can drive.
#  P1 editor world.query over the open document's entities
#  P2 component.set on a hud entity (the bindings-card commit chain)
#  P3 authoring badge: select the entity, read the bindings card text
#  P4 history.undo reverts the document edit (and scene_bsn agrees)
#  P5 scene_bsn shows the edit before undo (three-places face 1)
# Usage: bash loop/qa/t12t3-probe-editor.sh [project] [port]
set -u
PROJECT="${1:-/Users/zhanglinbo/workspace/loop-mac/t12t1-game/t12t1-game}"
PORT="${2:-15911}"
REPO=/Users/zhanglinbo/workspace/jackdaw
OUTDIR="$REPO/loop/t12t3-live"
EDITOR_LOG="$OUTDIR/t12t3-probe-editor.log"
CONSOLE_LOG="$OUTDIR/t12t3-probe-console.log"
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
    op dialog.answer '{"choice":"0"}' >/dev/null 2>&1
    sleep 2
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
log "EDITOR_READY"

op scene.open "{\"path\":\"$HUD\"}" >/dev/null 2>&1
sleep 3; wait_idle 300; sleep 2; dismiss_dialog
open_ok=false
for i in $(seq 1 30); do
  if brp jackdaw/scene_bsn '{}' 2>/dev/null | jq -re '.result // empty' 2>/dev/null | grep -q "HudRoot"; then open_ok=true; break; fi
  sleep 1
done
log "hud open: $open_ok"

log "--- P1: editor world.query over document entities (Bindings)"
log "P1: $(brp world.query '{"data":{"components":["jackdaw_bind::types::Bindings"]}}' | head -c 600)"

log "--- P2: component.set typo on the HealthBar Bindings (card commit chain)"
HEALTHBAR=$(brp world.query '{"data":{"components":["jackdaw_bind::types::Bindings","jackdaw_widgets_runtime::Progress"]}}' 2>/dev/null | jq -r '.result[0].entity // empty' 2>/dev/null)
log "HealthBar entity: $HEALTHBAR"
CUR=$(brp world.query "{\"data\":{\"components\":[\"jackdaw_bind::types::Bindings\"]}}" 2>/dev/null | jq -r --arg e "${HEALTHBAR%%v*}" '.result[] | select(.entity == $e) | .components["jackdaw_bind::types::Bindings"] | tostring' 2>/dev/null | head -c 400)
log "current Bindings: $CUR"
NEWBIND=$(echo "$CUR" | python3 -c 'import sys,json; s=json.load(sys.stdin); s[0]["fields"]["read"][0]["raw"]=s[0]["fields"]["read"][0]["raw"].replace(".current",".currrent"); print(json.dumps(s))' 2>/dev/null)
log "new Bindings json: ${NEWBIND:0:300}"
if [ -n "$NEWBIND" ]; then
  op component.set "{\"entity\":\"$HEALTHBAR\",\"type_path\":\"jackdaw_bind::types::Bindings\",\"field\":\"\",\"value\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$NEWBIND")}" >/dev/null 2>&1
  sleep 2
  log "P5 scene_bsn after edit: $(brp jackdaw/scene_bsn '{}' | jq -r '.result' | grep -o 'currrent' | head -1) (want currrent)"
fi

log "--- P3: select the entity, read the bindings card text"
insel=$(op component.set "{\"entity\":\"$HEALTHBAR\",\"type_path\":\"jackdaw_api_internal::selection::Selected\",\"field\":\"\",\"value\":\"{}\"}" 2>/dev/null)
log "select attempt: $(echo "$insel" | head -c 200)"
sleep 2
log "P3 card texts: $(brp jackdaw/ui_tree '{"kind":"text","visible_only":false,"depth":30}' | jq -r '[.. | objects | select(.kind? == "text") | .text // ""] | join(" || ")' | head -c 900)"

log "--- P4: history.undo reverts the document edit"
op history.undo '{}' >/dev/null 2>&1
sleep 2
UNDO_TXT=$(brp jackdaw/scene_bsn '{}' | jq -r '.result' | grep -c 'currrent')
log "P4 scene_bsn 'currrent' count after undo: $UNDO_TXT (want 0)"

pkill -x jackdaw 2>/dev/null
cp "$HUD.bak" "$HUD"
log "T12T3_PROBE_DONE"
