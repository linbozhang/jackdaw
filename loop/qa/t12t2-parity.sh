#!/bin/bash
# T12-T2 parity set: the four screens + the bar over the data face, against
# whatever game owns the BRP port (direct run or staged export).
# Usage: bash loop/qa/t12t2-parity.sh <label> [port]
set -u
LABEL="${1:-GAME}"
GAME_PORT="${2:-15702}"
REPO=/Users/zhanglinbo/workspace/jackdaw
OUTDIR="$REPO/loop/t12t2-live"
CONSOLE_LOG="$OUTDIR/t12t2-parity-$LABEL-console.log"
: > "$CONSOLE_LOG"
log() { echo "$@" | tee -a "$CONSOLE_LOG"; }
gbrp() {
  local method="$1" params="${2:-}" id=$RANDOM body
  if [ -n "$params" ]; then
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}' "$id" "$method" "$params")
  else
    body=$(printf '{"jsonrpc":"2.0","id":%s,"method":"%s"}' "$id" "$method")
  fi
  curl -s -m 30 -X POST "http://127.0.0.1:$GAME_PORT/" -H 'Content-Type: application/json' -d "$body"
}
st() { gbrp world.get_resources '{"resource":"t12t1_game::GameState"}' 2>/dev/null | jq -c '.result.value' 2>/dev/null; }
screen_vis() { # screen_vis <menu|paused|game_over> [not]
  local raw="$1" want_not="${2:-}"
  gbrp world.query '{"data":{"components":["bevy_camera::visibility::Visibility","jackdaw_bind::types::Bindings"]}}' 2>/dev/null \
    | jq -r --arg raw "$raw" --arg vn "$want_not" \
      '[.result[]
        | (.components["jackdaw_bind::types::Bindings"] | tostring) as $b
        | select($b | contains("Res(t12t1_game::GameState).\($raw)"))
        | select(($vn == "not") == ($b | contains("not")))
        | .components["bevy_camera::visibility::Visibility"]] | first // empty' 2>/dev/null
}
pass=true
log "$LABEL boot state=$(st)"
[ "$(st)" = '{"game_over":false,"menu":true,"paused":false}' ] || pass=false
gbrp world.insert_resources '{"resource":"t12t1_game::GameState","value":{"menu":false,"paused":false,"game_over":false}}' >/dev/null 2>&1
sleep 1.5
vis_hud=$(screen_vis menu not)
vis_start=$(screen_vis menu)
[ "$vis_hud" = "Inherited" ] && [ "$vis_start" = "Hidden" ] || pass=false
log "$LABEL menu=false: Hud=$vis_hud (shown=Inherited) StartScreen=$vis_start"
pent=$(gbrp world.query '{"data":{"components":["t12t1_game::PlayerHealth"]}}' 2>/dev/null | jq -r '.result[0].entity // empty' 2>/dev/null)
gbrp world.insert_components "{\"entity\":\"$pent\",\"components\":{\"t12t1_game::PlayerHealth\":{\"current\":60.0,\"max\":100.0}}}" >/dev/null 2>&1
sleep 1.5
pv=$(gbrp world.query '{"data":{"components":["jackdaw_widgets_runtime::Progress"]}}' 2>/dev/null | jq -r '[.result[] | .components["jackdaw_widgets_runtime::Progress"].value] | first // empty' 2>/dev/null)
ht=$(gbrp world.query '{"data":{"components":["bevy_ui::widget::text::Text"]}}' 2>/dev/null | jq -r '[.result[] | .components["bevy_ui::widget::text::Text"] | strings | select(test("^[0-9.-]+ / "))] | first // empty' 2>/dev/null)
python3 -c "import sys; sys.exit(0 if abs(${pv:-9} - 0.6) < 0.01 else 1)" 2>/dev/null || pass=false
[ "$ht" = "60 / 100" ] || pass=false
log "$LABEL health 60: Progress.value=$pv HealthText=$ht (expect 0.6 / 60 / 100)"
gbrp world.insert_resources '{"resource":"t12t1_game::GameState","value":{"menu":false,"paused":true,"game_over":false}}' >/dev/null 2>&1
sleep 1.5
vis_pause=$(screen_vis paused)
[ "$vis_pause" = "Inherited" ] || pass=false
log "$LABEL paused: PauseScreen=$vis_pause (shown=Inherited)"
gbrp world.insert_resources '{"resource":"t12t1_game::GameState","value":{"menu":false,"paused":false,"game_over":true}}' >/dev/null 2>&1
sleep 1.5
vis_go=$(screen_vis game_over)
[ "$vis_go" = "Inherited" ] || pass=false
log "$LABEL game_over: GameOverScreen=$vis_go (shown=Inherited)"
if [ "$pass" = true ]; then
  log "VERDICT_PARITY_$LABEL: PASS"
else
  log "VERDICT_PARITY_$LABEL: FAIL"
fi
