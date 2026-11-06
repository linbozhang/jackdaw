#!/bin/bash
# R7 live leg 2: build the L-shaped concave brush.
# Semantics discovered in leg1: csg_subtract cuts the NON-selected brushes
# with the selected ones (selected = cutters), and its availability gate
# requires >=2 selected brushes. Layout:
#   Cube  A (0,0,0)      — target, NOT selected
#   CubeB   (0.5,0.5,0.5) — cutter (cuts A's +X+Y+Z corner → concave L)
#   CubeC   (10,10,10)    — second selected brush, AABB-rejected as harmless
set -u
REPO=/Users/linbo.zhang/workspace/jackdaw
PORT=15703
OUTDIR="$REPO/loop/bug-r7-qa"
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$OUTDIR/r7-console.log"; }
brp() { # brp <method> <params> <outfile>
  curl -s --max-time 25 -X POST "http://127.0.0.1:$PORT/" \
    -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}" > "$3"
  head -c 220 "$3"; echo
}
wait_idle() {
  local deadline=$(( SECONDS + ${1:-120} ))
  while [ $SECONDS -lt $deadline ]; do
    if brp jackdaw/wait '{"until":"idle"}' /dev/null 2>/dev/null | jq -e '.result.idle == true' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}
tree_names() { # scene (entity,name) list → stdout
  curl -s --max-time 10 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"jackdaw/scene_tree","params":{}}' > "$1"
  python3 -c "
import json
d=json.load(open('$1'))
print([(n.get('entity'),n.get('name')) for n in d['result']['tree']])
"
}

log "=== R7 LEG2 (L-shaped brush, cutter/target semantics) BEGIN ==="

# 0) clean slate: undo everything left over (Cube spawn, CubeB apply, ...)
brp jackdaw/history '{}' "$OUTDIR/r7-history-pre.json"
for i in 1 2 3 4; do
  brp jackdaw/call_operator '{"id":"history.undo","params":{}}' "$OUTDIR/r7-undo-$i.json"
  sleep 1
done
wait_idle 60
log "scene after 4 undos: $(tree_names "$OUTDIR/r7-tree-clean2.json")"

# 1) spawn the three brushes
brp jackdaw/call_operator '{"id":"entity.add.cube","params":{}}' "$OUTDIR/r7-add-cubeA.json"
sleep 1; wait_idle 60
brp jackdaw/apply_bsn '{"source":"#CubeB\nbevy_transform::components::transform::Transform {\n    translation: glam::Vec3 { x: 0.5, y: 0.5, z: 0.5 },\n}\n"}' "$OUTDIR/r7-add-cubeB.json"
sleep 1; wait_idle 60
brp jackdaw/apply_bsn '{"source":"#CubeC\nbevy_transform::components::transform::Transform {\n    translation: glam::Vec3 { x: 10.0, y: 10.0, z: 10.0 },\n}\n"}' "$OUTDIR/r7-add-cubeC.json"
sleep 1; wait_idle 60
log "scene after spawns: $(tree_names "$OUTDIR/r7-tree-3cubes.json")"

# 2) select cutters (B and C)
B_BITS=$(python3 -c "
import json
d=json.load(open('$OUTDIR/r7-tree-3cubes.json'))
print({n.get('name'): n.get('entity') for n in d['result']['tree']}.get('CubeB',''))")
C_BITS=$(python3 -c "
import json
d=json.load(open('$OUTDIR/r7-tree-3cubes.json'))
print({n.get('name'): n.get('entity') for n in d['result']['tree']}.get('CubeC',''))")
[ -n "$B_BITS" ] && [ -n "$C_BITS" ] || { log "LEG2_FAIL: cutters missing"; exit 1; }
brp jackdaw/selection.set "{\"entities\":[$B_BITS,$C_BITS]}" "$OUTDIR/r7-select-cutters.json"
sleep 1

# 3) history snapshot right before the subtract (undo-count anchor)
brp jackdaw/history '{}' "$OUTDIR/r7-history-before-nudge-prep.json"
log "history before subtract: $(jq -c '.result | {undo_len, redo_len, top}' "$OUTDIR/r7-history-before-nudge-prep.json" 2>/dev/null)"

# 4) subtract
brp jackdaw/call_operator '{"id":"brush.csg_subtract","params":{}}' "$OUTDIR/r7-csg-subtract2.json"
sleep 2; wait_idle 180; sleep 2
log "subtract reply: $(head -c 220 "$OUTDIR/r7-csg-subtract2.json")"
log "scene after subtract: $(tree_names "$OUTDIR/r7-tree-after-subtract2.json")"

# 5) archive every brush entity's BSN as the topology snapshot
for nm in Cube CubeB CubeC; do
  curl -s --max-time 15 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"jackdaw/entity\",\"params\":{\"name\":\"$nm\"}}" \
    > "$OUTDIR/r7-brush-$nm.json" 2>/dev/null
done
brp jackdaw/history '{}' "$OUTDIR/r7-history-after-subtract.json"
log "history after subtract: $(jq -c '.result | {undo_len, redo_len, top}' "$OUTDIR/r7-history-after-subtract.json" 2>/dev/null)"
log "=== R7 LEG2 END ==="
