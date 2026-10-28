#!/bin/bash
# T12-T3 editor chains over the warm project's hud document.
#   T02_BIND  the bindings-card commit chain on a Bindings component: a typoed
#             field lands through component.set (the same field_edit_commit the
#             card drives) and reads back consistently in the editor ECS, the
#             document bsn, and the bindings card UI (selected row label).
#   T03_UNDO  the same edit is undoable: history.undo reverts the document and
#             the editor ECS agrees.
#   CELL9     the re-edit loop: retitle the start screen + recolor the health
#             fill in the editor, Save, Play picks both up, and a staged export
#             keeps them.
# The fixture hud.bsn is backed up and always restored.
# Usage: bash loop/qa/t12t3-editor-chains.sh [project] [port]
set -u
PROJECT="${1:-/Users/zhanglinbo/workspace/loop-mac/t12t1-game/t12t1-game}"
PORT="${2:-15912}"
GAME_PORT=15702
REPO=/Users/zhanglinbo/workspace/jackdaw
OUTDIR="$REPO/loop/t12t3-live"
EDITOR_LOG="$OUTDIR/t12t3-editor-chains-editor.log"
CONSOLE_LOG="$OUTDIR/t12t3-editor-chains-console.log"
HUD="$PROJECT/assets/hud.bsn"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
BIND_TP='jackdaw_bind::types::Bindings'
TEXT_TP='bevy_ui::widget::text::Text'
mkdir -p "$OUTDIR"
: > "$CONSOLE_LOG"

RESULTS_FILE="$(mktemp /tmp/t12t3-echains.XXXXXX)"
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
summary_line() { sort "$RESULTS_FILE" | tr '\n' ' '; }
cleanup() {
  [ -f "$HUD.bak" ] && cp "$HUD.bak" "$HUD"
  op pie.stop >/dev/null 2>&1
  sleep 2
  pkill -x jackdaw 2>/dev/null
  pkill -f 't12t1-game$' 2>/dev/null
}
trap cleanup EXIT

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
game_up() { curl -s -m 5 -X POST "http://127.0.0.1:$GAME_PORT/" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"jackdaw/app_info"}' | jq -e '.result.app_name' >/dev/null 2>&1; }
gbrp() {
  local method="$1" params="${2:-}" id=$RANDOM body
  if [ -n "$params" ]; then
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params")
  else
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s"}' "$id" "$method")
  fi
  curl -s -m 30 -X POST "http://127.0.0.1:$GAME_PORT/" -H 'Content-Type: application/json' -d "$body"
}
# "4671v0" -> the entity-bits int the operator layer's Int form parses.
eid() { python3 -c 'import sys; i,g=sys.argv[1].split("v"); print(int(i)+int(g)*(2**32))' "$1" 2>/dev/null; }
scene_bsn() { brp jackdaw/scene_bsn '{}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null; }
ui_texts() {
  brp jackdaw/ui_tree '{"kind":"text","visible_only":true,"depth":30}' 2>/dev/null \
    | jq -r '[.. | objects | select(.kind? == "text") | .text // ""] | join(" || ")' 2>/dev/null
}

# ---- editor boot ------------------------------------------------------------
pkill -x jackdaw 2>/dev/null; pkill -f 't12t1-game$' 2>/dev/null
sleep 1
cp "$HUD" "$HUD.bak"
SEED_SHA=$(shasum -a 256 "$HUD" | awk '{print $1}')
log "hud.bsn seed sha256: $SEED_SHA"
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
  if scene_bsn | grep -q "HudRoot"; then open_ok=true; break; fi
  sleep 1
done
[ "$open_ok" = true ] || { log "HUD_OPEN_FAIL"; leg T02_BIND_CARD false; leg T03_UNDO false; leg CELL9_REEDIT false; leg CELL9_EXPORT false; exit 1; }
log "hud document confirmed open"

# ---- T02: the bindings-card commit chain ------------------------------------
# The HealthBar carries the bar's Field binding. Edit its read path
# .current -> .currrent through component.set (the field_edit_commit the
# inspector card drives), then read the same typo back from the editor ECS
# (world.query), the document bsn, and the card row label (the set selects
# the entity, so the inspector shows the bindings card).
HEALTHBAR=$(brp world.query "{\"data\":{\"components\":[\"$BIND_TP\",\"jackdaw_widgets_runtime::Progress\"]}}" 2>/dev/null | jq -r '.result[0].entity // empty' 2>/dev/null)
log "HealthBar entity: $HEALTHBAR"
CUR_BIND=$(brp world.query "{\"data\":{\"components\":[\"$BIND_TP\"]}}" 2>/dev/null | jq -r --arg e "$HEALTHBAR" '.result[] | select(.entity == $e) | .components["jackdaw_bind::types::Bindings"] | tostring' 2>/dev/null)
log "current Bindings: ${CUR_BIND:0:220}"
TYPO_BIND=$(echo "$CUR_BIND" | python3 -c 'import sys,json; v=json.load(sys.stdin); print(json.dumps(v))' 2>/dev/null | sed 's/PlayerHealth\.current/PlayerHealth.currrent/g')
if [ -n "$CUR_BIND" ] && [ "$TYPO_BIND" != "$CUR_BIND" ] && [ -n "$(eid "$HEALTHBAR")" ]; then
  SETRESP=$(op component.set "{\"entity\":\"HealthBar\",\"type_path\":\"$BIND_TP\",\"field\":\"\",\"value\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$TYPO_BIND")}" 2>/dev/null)
  log "component.set outcome: $(echo "$SETRESP" | head -c 300)"
  # The card face: make sure the inspector shows the HealthBar, then read the
  # bindings card's row labels (the typo has to be visible where the author
  # edits).
  brp jackdaw/selection.set '{"names":["HealthBar"]}' >/dev/null 2>&1
  sleep 3
  sleep 2
  ECS_AFTER=$(brp world.query "{\"data\":{\"components\":[\"$BIND_TP\"]}}" 2>/dev/null | jq -r --arg e "$HEALTHBAR" '.result[] | select(.entity == $e) | .components["jackdaw_bind::types::Bindings"] | tostring' 2>/dev/null)
  DOC_AFTER=$(scene_bsn | grep -c 'currrent')
  sleep 1
  CARD_TXT=$(brp jackdaw/ui_tree '{"kind":"text","visible_only":false,"depth":30}' 2>/dev/null \
    | jq -r '[.. | objects | select(.kind? == "text") | .text // ""] | join(" || ")' 2>/dev/null)
  t02=true
  echo "$ECS_AFTER" | grep -q 'currrent' || t02=false
  [ "${DOC_AFTER:-0}" -ge 1 ] 2>/dev/null || t02=false
  echo "$CARD_TXT" | grep -q 'currrent' || t02=false
  log "T02 three faces after the edit: ecs=$(echo "$ECS_AFTER" | grep -o 'currrent' | head -1) doc_hits=$DOC_AFTER card=$(echo "$CARD_TXT" | grep -o 'currrent[a-z.]*' | head -1)"
else
  t02=false
  log "T02_SETUP_FAIL: cur='${CUR_BIND:0:120}' eid='$(eid "$HEALTHBAR")'"
fi
leg T02_BIND_CARD "$t02"

# ---- T03: the edit is undoable ----------------------------------------------
op history.undo '{}' >/dev/null 2>&1
sleep 2
ECS_UNDO=$(brp world.query "{\"data\":{\"components\":[\"$BIND_TP\"]}}" 2>/dev/null | jq -r --arg e "$HEALTHBAR" '.result[] | select(.entity == $e) | .components["jackdaw_bind::types::Bindings"] | tostring' 2>/dev/null)
DOC_UNDO=$(scene_bsn | grep -c 'currrent')
t03=true
echo "$ECS_UNDO" | grep -q 'currrent' && t03=false
[ "${DOC_UNDO:-0}" -eq 0 ] 2>/dev/null || t03=false
log "T03 after undo: ecs_typo=$(echo "$ECS_UNDO" | grep -c currrent) doc_hits=$DOC_UNDO"
leg T03_UNDO "$t03"

# ---- CELL 9: re-edit, save, play, export ------------------------------------
# Retitle the start screen and recolor the fill: the fill's theme token is
# removed and a plain authored BackgroundColor lands (the theme only rewrites
# nodes that carry both components, so the authored color is the final one).
TITLE_E=$(brp world.query "{\"data\":{\"components\":[\"$TEXT_TP\"]}}" 2>/dev/null | jq -r '.result[] | select(.components["bevy_ui::widget::text::Text"] | tostring | test("T12t1 Game")) | .entity' 2>/dev/null | head -1)
FILL_E=$(brp world.query '{"data":{"components":["jackdaw_widgets_runtime::ProgressFill"]}}' 2>/dev/null | jq -r '.result[0].entity // empty' 2>/dev/null)
log "StartTitle entity: $TITLE_E  HealthFill entity: $FILL_E"
cell9=true
if [ -n "$TITLE_E" ] && [ -n "$FILL_E" ]; then
  op component.set "{\"entity\":\"StartTitle\",\"type_path\":\"$TEXT_TP\",\"field\":\"\",\"value\":\"\\\"T12t3 Edited Title\\\"\"}" >/dev/null 2>&1
  R1=$(op component.remove "{\"entity\":\"HealthFill\",\"type_path\":\"bevy_feathers::theme::ThemeBackgroundColor\"}" 2>/dev/null)
  log "remove token outcome: $(echo "$R1" | head -c 200)"
  R2=$(op component.add "{\"entity\":\"HealthFill\",\"type_path\":\"bevy_ui::ui_node::BackgroundColor\"}" 2>/dev/null)
  log "add color outcome: $(echo "$R2" | head -c 200)"
  # The reflect JSON form for the Color enum; the 'r,g,b' spelling is the
  # fallback the card's own parser accepts.
  R3=$(op component.set "{\"entity\":\"HealthFill\",\"type_path\":\"bevy_ui::ui_node::BackgroundColor\",\"field\":\"\",\"value\":\"{\\\"Srgba\\\":{\\\"red\\\":0.85,\\\"green\\\":0.15,\\\"blue\\\":0.15,\\\"alpha\\\":1.0}}\"}" 2>/dev/null)
  log "set color json outcome: $(echo "$R3" | head -c 200)"
  echo "$R3" | grep -q '"result":"finished"' || {
    op component.set "{\"entity\":\"HealthFill\",\"type_path\":\"bevy_ui::ui_node::BackgroundColor\",\"field\":\"\",\"value\":\"0.85,0.15,0.15\"}" >/dev/null 2>&1
  }
  sleep 2
  FILLDOC=$(scene_bsn | grep -A2 '#HealthFill')
  log "fill doc region: $(echo "$FILLDOC" | head -4 | tr '\n' ' ')"
  scene_bsn | grep -q "T12t3 Edited Title" || cell9=false
  scene_bsn | grep -Eq 'red: 0.85|"red":0.85' || cell9=false
  log "doc before save: title=$(scene_bsn | grep -c 'T12t3 Edited Title') fill_red85=$(scene_bsn | grep -Ec 'red: 0.85')"
  SHA_BEFORE=$(shasum -a 256 "$HUD" | awk '{print $1}')
  op scene.save '{}' >/dev/null 2>&1
  sleep 3; wait_idle 300; sleep 2; dismiss_dialog
  SHA_AFTER=$(shasum -a 256 "$HUD" | awk '{print $1}')
  log "hud.bsn sha before=$SHA_BEFORE after=$SHA_AFTER"
  [ "$SHA_BEFORE" != "$SHA_AFTER" ] || cell9=false
  grep -q "T12t3 Edited Title" "$HUD" || cell9=false
  grep -q "red: 0.85" "$HUD" || cell9=false
else
  cell9=false
  log "CELL9_SETUP_FAIL"
fi

# Play from the 3D scene so the PIE override does not replace the main scene:
# the game loads the edited hud.bsn from disk through spawn_hud.
op scene.open "{\"path\":\"$PROJECT/assets/scene.bsn\"}" >/dev/null 2>&1
sleep 2; wait_idle 300 >/dev/null
op pie.play_current >/dev/null 2>&1
deadline=$((SECONDS + 600))
while [ $SECONDS -lt $deadline ]; do
  game_up && break
  sleep 2
done
sleep 4
if game_up; then
  TITLE_LIVE=$(gbrp world.query "{\"data\":{\"components\":[\"$TEXT_TP\"]}}" 2>/dev/null | jq -r '[.result[] | .components["bevy_ui::widget::text::Text"] | tostring] | join("||")' 2>/dev/null | grep -c 'T12t3 Edited Title')
  FILL_LIVE=$(gbrp world.query '{"data":{"components":["bevy_ui::ui_node::BackgroundColor","jackdaw_widgets_runtime::ProgressFill"]}}' 2>/dev/null | jq -r '[.result[] | .components["bevy_ui::ui_node::BackgroundColor"] | tostring] | first // empty' 2>/dev/null)
  log "live after Play: title_hits=$TITLE_LIVE fill_color=$FILL_LIVE"
  [ "${TITLE_LIVE:-0}" -ge 1 ] 2>/dev/null || cell9=false
  # The BRP serializes Color in its own variant (LinearRgba), so the authored
  # 0.85/0.15/0.15 srgb lands as a red-dominant color; assert that shape.
  echo "$FILL_LIVE" | python3 -c '
import sys, json
text = sys.stdin.read()
try:
    data = json.loads(text)
    rgb = [0, 0, 0]
    def walk(v):
        global rgb
        if isinstance(v, dict):
            if "red" in v: rgb = [v["red"], v.get("green", 0), v.get("blue", 0)]
            for value in v.values(): walk(value)
        elif isinstance(v, list):
            for value in v: walk(value)
    walk(data)
    sys.exit(0 if rgb[0] > 0.4 and rgb[1] < 0.3 and rgb[2] < 0.3 else 1)
except Exception:
    sys.exit(1)' || cell9=false
else
  cell9=false
  log "CELL9_PLAY_BOOT_FAIL"
fi
op pie.stop >/dev/null 2>&1; sleep 3; pkill -f 't12t1-game$' 2>/dev/null; sleep 1
leg CELL9_REEDIT "$cell9"

# The staged export keeps the edits: export, then the staged hud.bsn carries
# both edits, and the staged binary boots with the edited title live.
exp_ok=false
if [ "$cell9" = true ]; then
  log "exporting (release staging)..."
  rm -rf "$PROJECT/.jackdaw/dist/release"
  op game.export '{}' >/dev/null 2>&1
  deadline=$((SECONDS + 1800))
  while [ $SECONDS -lt $deadline ]; do
    [ -f "$PROJECT/.jackdaw/dist/release/export-manifest.json" ] && [ -x "$PROJECT/.jackdaw/dist/release/t12t1-game" ] && break
    sleep 5
  done
  sleep 8
  STAGED_HUD="$PROJECT/.jackdaw/dist/release/assets/hud.bsn"
  if [ -f "$STAGED_HUD" ] && grep -q "T12t3 Edited Title" "$STAGED_HUD" && grep -q "red: 0.85" "$STAGED_HUD"; then
    exp_ok=true
    log "staged hud.bsn carries both edits"
    # The staged binary boots with the edited title live.
    (cd "$PROJECT/.jackdaw/dist/release" && nohup ./t12t1-game > "$OUTDIR/t12t3-cell9-staged-boot.log" 2>&1 &)
    deadline=$((SECONDS + 120))
    while [ $SECONDS -lt $deadline ]; do game_up && break; sleep 2; done
    sleep 6
    if game_up; then
      STAGED_TITLE=$(gbrp world.query "{\"data\":{\"components\":[\"$TEXT_TP\"]}}" 2>/dev/null | jq -r '[.result[] | .components["bevy_ui::widget::text::Text"] | tostring] | join("||")' 2>/dev/null | grep -c 'T12t3 Edited Title')
      log "staged boot title_hits=$STAGED_TITLE"
      [ "${STAGED_TITLE:-0}" -ge 1 ] 2>/dev/null || exp_ok=false
    else
      exp_ok=false
      log "STAGED_BOOT_FAIL"
    fi
    pkill -f 't12t1-game$' 2>/dev/null
  else
    log "staged hud.bsn missing edits: $(ls "$PROJECT/.jackdaw/dist/release/assets/" 2>/dev/null | head -5)"
  fi
fi
leg CELL9_EXPORT "$exp_ok"

printf '%s\n' "$(summary_line)" > "$OUTDIR/t12t3-editor-chains-summary.txt"
log "VERDICT_EDITOR_CHAINS: $(summary_line)"
log "T12T3_EDITOR_CHAINS_DONE"
