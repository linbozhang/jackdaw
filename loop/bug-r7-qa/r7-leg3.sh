#!/bin/bash
# R7 live leg 3: build the L-shaped concave brush with REAL Brush entities.
# leg2 root cause: apply_bsn spawns transform-only entities, which fail the
# `brushes.contains` gate of brush.csg_subtract (needs >=2 selected Brushes).
# All three brushes now come from entity.add.cube; the cutter is moved onto
# the target's +X+Y+Z corner with the entity-level nudge operators
# (grid default 0.25 → two steps per axis = 0.5), the陪选 second cutter is
# pushed 40 steps +X (10.0) so its AABB misses the target.
set -u
REPO=/Users/linbo.zhang/workspace/jackdaw
PORT=15703
OUTDIR="$REPO/loop/bug-r7-qa"
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$OUTDIR/r7-console.log"; }
brp() { # brp <method> <params> <outfile>
  curl -s --max-time 25 -X POST "http://127.0.0.1:$PORT/" \
    -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}" > "$3"
  head -c 200 "$3"; echo
}
wait_idle() {
  local deadline=$(( SECONDS + ${1:-120} ))
  while [ $SECONDS -lt $deadline ]; do
    if brp jackdaw/wait '{"until":"idle"}' /dev/null 2>/dev/null | jq -e '.result.idle == true' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}
tree_names() {
  curl -s --max-time 10 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"jackdaw/scene_tree","params":{}}' > "$1"
  python3 -c "
import json
d=json.load(open('$1'))
print([(n.get('entity'),n.get('name')) for n in d['result']['tree']])
"
}
last_entity_bits() { # parse the last call_operator/apply_bsn reply for entities[]
  python3 -c "
import json
d=json.load(open('$1'))
e=d.get('result',{}).get('entities',[])
print(e[-1] if e else '')
"
}
op() { # op <operator-id> <outfile>
  brp jackdaw/call_operator "{\"id\":\"$1\",\"params\":{}}" "$2"
}

log "=== R7 LEG3 (real Brush cutters) BEGIN ==="

# 0) clean slate: undo the three leftover entries (Cube spawn, 2x Apply BSN)
brp jackdaw/history '{}' "$OUTDIR/r7-history-pre3.json"
for i in 1 2 3 4 5; do
  op history.undo "$OUTDIR/r7-undo3-$i.json"
  sleep 1
done
wait_idle 60
log "scene after undos: $(tree_names "$OUTDIR/r7-tree-clean3.json")"

# 1) target A at origin
op entity.add.cube "$OUTDIR/r7-add3-A.json"; sleep 1; wait_idle 60
# 2) cutter B, moved to (0.5,0.5,0.5) = 2 grid steps per axis
op entity.add.cube "$OUTDIR/r7-add3-B.json"; sleep 1; wait_idle 60
curl -s --max-time 10 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"jackdaw/scene_tree","params":{}}' > "$OUTDIR/r7-tree3-ab.json"
B_BITS=$(python3 -c "
import json
d=json.load(open('$OUTDIR/r7-tree3-ab.json'))
ents=[n.get('entity') for n in d['result']['tree'] if n.get('name')=='Cube']
print(ents[-1] if ents else '')")
brp jackdaw/selection.set "{\"entities\":[$B_BITS]}" "$OUTDIR/r7-sel3-B.json"; sleep 1
for ax in x y z; do
  op "transform.nudge_${ax}_pos" "$OUTDIR/r7-nudge3-B-$ax.json"
  op "transform.nudge_${ax}_pos" "$OUTDIR/r7-nudge3-B-$ax.json"
done
sleep 1; wait_idle 60
# 3) harmless second cutter C, pushed 40 steps +X (10.0)
op entity.add.cube "$OUTDIR/r7-add3-C.json"; sleep 1; wait_idle 60
curl -s --max-time 10 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"jackdaw/scene_tree","params":{}}' > "$OUTDIR/r7-tree3-abc.json"
C_BITS=$(python3 -c "
import json
d=json.load(open('$OUTDIR/r7-tree3-abc.json'))
ents=[n.get('entity') for n in d['result']['tree'] if n.get('name')=='Cube']
print(ents[-1] if ents else '')")
brp jackdaw/selection.set "{\"entities\":[$C_BITS]}" "$OUTDIR/r7-sel3-C.json"; sleep 1
for i in $(seq 1 40); do
  op transform.nudge_x_pos "$OUTDIR/r7-nudge3-C-x.json"
done
sleep 1; wait_idle 120
log "scene after layout: $(tree_names "$OUTDIR/r7-tree3-layout.json")"

# 4) select cutters, subtract
brp jackdaw/selection.set "{\"entities\":[$B_BITS,$C_BITS]}" "$OUTDIR/r7-sel3-cutters.json"
sleep 1
brp jackdaw/history '{}' "$OUTDIR/r7-history3-before-subtract.json"
op brush.csg_subtract "$OUTDIR/r7-subtract3.json"
sleep 2; wait_idle 180; sleep 2
log "subtract reply: $(head -c 200 "$OUTDIR/r7-subtract3.json")"
log "scene after subtract: $(tree_names "$OUTDIR/r7-tree3-after-subtract.json")"
brp jackdaw/history '{}' "$OUTDIR/r7-history3-after-subtract.json"
log "history: before=$(jq -c '.result|{undo_len}' "$OUTDIR/r7-history3-before-subtract.json" 2>/dev/null) after=$(jq -c '.result|{undo_len,top}' "$OUTDIR/r7-history3-after-subtract.json" 2>/dev/null)"

# 5) archive the product brush BSN (name "Cube" — cloned from target A)
curl -s --max-time 15 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"jackdaw/entity","params":{"name":"Cube"}}' \
  > "$OUTDIR/r7-product-brush.json" 2>/dev/null
log "product brush bsn bytes: $(wc -c < "$OUTDIR/r7-product-brush.json")"
log "=== R7 LEG3 END ==="
