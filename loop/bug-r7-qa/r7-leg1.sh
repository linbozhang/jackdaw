#!/bin/bash
# R7 live leg, part 1: build the L-shaped concave brush (two overlapping
# cubes + brush.csg_subtract), record its Brush face/vert topology as the
# pre-nudge baseline. Structured (BRP/operator) steps only.
set -u
REPO=/Users/linbo.zhang/workspace/jackdaw
PORT=15703
OUTDIR="$REPO/loop/bug-r7-qa"
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$OUTDIR/r7-console.log"; }
brp() { # brp <method> <params> <outfile>
  curl -s --max-time 20 -X POST "http://127.0.0.1:$PORT/" \
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

log "=== R7 LEG1 (L-shaped brush construction) BEGIN ==="

# 0) clean slate: undo the probe's cube add (entity.add.cube from probe was
#    itself pushed as a SpawnEntity undo entry) — undo once to remove the
#    probe Cube, then undo the misplaced Cube2 spawn.
brp jackdaw/call_operator '{"id":"history.undo","params":{}}' "$OUTDIR/r7-undo-1.json"
sleep 1
brp jackdaw/call_operator '{"id":"history.undo","params":{}}' "$OUTDIR/r7-undo-2.json"
sleep 1; wait_idle 60
curl -s --max-time 10 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"jackdaw/scene_tree","params":{}}' > "$OUTDIR/r7-tree-clean.json"
log "scene after undos: $(python3 -c "
import json
d=json.load(open('$OUTDIR/r7-tree-clean.json'))
print([(n.get('entity'),n.get('name')) for n in d['result']['tree']])
")"

# 1) spawn cube A at origin and cube B overlapping at (0.5,0.5,0.5) —
#    B cuts A's +X+Y+Z corner → the subtract leaves the concave L.
brp jackdaw/call_operator '{"id":"entity.add.cube","params":{}}' "$OUTDIR/r7-add-cubeA.json"
sleep 1; wait_idle 60
brp jackdaw/apply_bsn '{"source":"#CubeB\nbevy_transform::components::transform::Transform {\n    translation: glam::Vec3 { x: 0.5, y: 0.5, z: 0.5 },\n}\n"}' "$OUTDIR/r7-add-cubeB.json"
sleep 1; wait_idle 60

# 2) read both brushes back
curl -s --max-time 10 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"jackdaw/scene_tree","params":{}}' > "$OUTDIR/r7-tree-2cubes.json"
CUBE_ENTS=$(python3 -c "
import json
d=json.load(open('$OUTDIR/r7-tree-2cubes.json'))
ents={n.get('name'): n.get('entity') for n in d['result']['tree'] if n.get('name') in ('Cube','CubeB')}
print(json.dumps(ents))
")
log "two brushes present: $CUBE_ENTS"
A_BITS=$(python3 -c "import json; print(json.loads('$CUBE_ENTS').get('Cube') or '')")
B_BITS=$(python3 -c "import json; print(json.loads('$CUBE_ENTS').get('CubeB') or '')")
[ -n "$A_BITS" ] && [ -n "$B_BITS" ] || { log "LEG1_FAIL: cubes missing"; exit 1; }

# 3) select both, then subtract (first selected = target, rest = cutters)
brp jackdaw/selection.set "{\"entities\":[$A_BITS,$B_BITS]}" "$OUTDIR/r7-select-both.json"
sleep 1
brp jackdaw/call_operator '{"id":"brush.csg_subtract","params":{}}' "$OUTDIR/r7-csg-subtract.json"
sleep 2; wait_idle 120; sleep 2

# 4) find the product brush
curl -s --max-time 10 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"jackdaw/scene_tree","params":{}}' > "$OUTDIR/r7-tree-after-subtract.json"
PRODUCT=$(python3 -c "
import json
d=json.load(open('$OUTDIR/r7-tree-after-subtract.json'))
print([(n.get('entity'),n.get('name')) for n in d['result']['tree']])
")
log "scene after subtract: $PRODUCT"

# 5) record the product brush topology (pre-nudge baseline)
curl -s --max-time 15 -X POST "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"jackdaw/entity","params":{"name":"Cube"}}' > "$OUTDIR/r7-brush-baseline.bsn.txt"
python3 - "$OUTDIR/r7-brush-baseline.bsn.txt" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
bsn = d.get('result', {}).get('bsn', '')
faces = bsn.count('BrushFaceData')
verts = len(re.findall(r'vertices:', bsn))
print(f"baseline brush bsn bytes={len(bsn)} faces~={faces}")
open(sys.argv[1] + '.head.txt', 'w').write(bsn[:2000])
PY
log "baseline brush archived: r7-brush-baseline.bsn.txt"
log "=== R7 LEG1 END ==="
