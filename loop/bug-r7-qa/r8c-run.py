#!/usr/bin/env python3
"""R8c: clean-room leg A. Rebuild the L brush on a fresh boot, archive the
full BSN before/after the nudge, and judge the nudge by the ORDER-INDEPENDENT
vertex multiset difference:
  correct  = exactly {4 old positions removed, 4 positions shifted +0.25Y},
  plus a per-index comparison to record whether the authored vertex ORDER is
  preserved (a reorder alone would be a bookkeeping defect, not a geometry
  one). Then undo and multiset-compare against the baseline."""
import json, re, subprocess, sys, time
from collections import Counter

PORT = 15703
OUT = "/Users/linbo.zhang/workspace/jackdaw/loop/bug-r7-qa"
SHOTDIR = "r7qa-shots"
GRID = 0.25

def brp(method, params, timeout=30):
    payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
    r = subprocess.run(["curl", "-s", "--max-time", str(timeout), "-X", "POST",
                        f"http://127.0.0.1:{PORT}/", "-H", "Content-Type: application/json",
                        "-d", payload], capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"raw": r.stdout[:200]}

def log(msg):
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    with open(f"{OUT}/r8-console.log", "a") as f:
        f.write(line + "\n")

def op(op_id, params=None):
    return brp("jackdaw/call_operator", {"id": op_id, "params": params or {}})

def wait_idle(limit=120):
    deadline = time.time() + limit
    while time.time() < deadline:
        if brp("jackdaw/wait", {"until": "idle"}).get("result", {}).get("idle") is True:
            return True
        time.sleep(1)
    return False

def tree_entities():
    d = brp("jackdaw/scene_tree", {})
    return {n["entity"]: n.get("name") for n in d["result"]["tree"]}

def entity_bsn(bits):
    return brp("jackdaw/entity", {"entity": bits}).get("result", {}).get("bsn", "")

POS_RE = re.compile(
    r"position: glam::Vec3 \{\s*x: ([0-9.eE+-]+),\s*y: ([0-9.eE+-]+),\s*z: ([0-9.eE+-]+)",
    re.S)

def vert_positions(bsn):
    parts = bsn.split("vertices: [")
    if len(parts) < 2:
        return []
    tail = parts[1].split("]", 1)[0]
    return [tuple(round(float(v), 6) for v in m) for m in POS_RE.findall(tail)]

def add_cube(tag):
    before = tree_entities()
    op("entity.add.cube")
    time.sleep(1); wait_idle(60); time.sleep(1)
    new_bits = [b for b in tree_entities() if b not in before]
    if len(new_bits) != 1:
        log(f"ADD_CUBE_FAIL {tag}")
        sys.exit(1)
    log(f"add_cube {tag}: bits={new_bits[0]}")
    return new_bits[0]

def nudge_to(axis, steps, bits, expect):
    brp("jackdaw/selection.set", {"entities": [bits]})
    time.sleep(0.5)
    for _ in range(steps):
        op(f"transform.nudge_{axis}_pos")
    time.sleep(1); wait_idle(60)
    bsn = entity_bsn(bits)
    m = re.findall(r"translation: glam::Vec3A? \{ x: ([0-9.eE+-]+), y: ([0-9.eE+-]+), z: ([0-9.eE+-]+)", bsn)
    t = [tuple(round(float(v), 6) for v in x) for x in m[:1]]
    ok = t and all(abs(a - b) < 1e-4 for a, b in zip(t[0], expect))
    log(f"  {axis}x{steps} -> {t} {'OK' if ok else 'MISMATCH'}")
    return bool(ok)

log("=== R8C CLEAN-ROOM LEG A BEGIN ===")

ents = {b: n for b, n in tree_entities().items() if n != "Root"}
if ents:
    log(f"R8C_FAIL: scene not empty: {ents}")
    sys.exit(1)

bits_a = add_cube("A")
bits_b = add_cube("B")
ok = nudge_to("x", 2, bits_b, (0.5, 0.0, 0.0)) \
     and nudge_to("y", 2, bits_b, (0.5, 0.5, 0.0)) \
     and nudge_to("z", 2, bits_b, (0.5, 0.5, 0.5))
bits_c = add_cube("C")
ok = ok and nudge_to("x", 40, bits_c, (10.0, 0.0, 0.0))
if not ok:
    log("R8C_FAIL: layout")
    sys.exit(1)

brp("jackdaw/selection.set", {"entities": [bits_b, bits_c]})
time.sleep(1)
op("brush.csg_subtract")
time.sleep(2); wait_idle(180); time.sleep(2)

product = None
for bits in tree_entities():
    if entity_bsn(bits).count("BrushFaceData") == 9:
        product = bits
        break
if product is None:
    log("R8C_FAIL: no product")
    sys.exit(1)
log(f"product: {product}")

bsn0 = entity_bsn(product)
with open(f"{OUT}/r8c-baseline.bsn.txt", "w") as f:
    f.write(bsn0)
v0 = vert_positions(bsn0)
faces0 = bsn0.count("BrushFaceData")
log(f"baseline: faces={faces0} verts={len(v0)}")

r = brp("jackdaw/call_operator", {"id": "brush.selection.set_faces",
                                  "params": {"entity": product, "faces": "0"}})
log(f"set_faces: {r.get('result', {}).get('result')} warnings={r.get('result', {}).get('warnings')}")
time.sleep(1)

h0 = brp("jackdaw/history", {})
op("input.key", {"key": "PageUp", "action": "tap"})
time.sleep(2); wait_idle(60); time.sleep(2)
h1 = brp("jackdaw/history", {})

bsn1 = entity_bsn(product)
with open(f"{OUT}/r8c-after-nudge.bsn.txt", "w") as f:
    f.write(bsn1)
v1 = vert_positions(bsn1)
faces1 = bsn1.count("BrushFaceData")
log(f"after nudge: faces={faces1} verts={len(v1)} undo_delta={h1['result']['undo_len'] - h0['result']['undo_len']}")

# order-independent judgement
c0, c1 = Counter(v0), Counter(v1)
removed = c0 - c1
added = c1 - c0
lifted = Counter({p: n for p, n in added.items()
                  if any(abs(p[1] - (q[1] + GRID)) < 1e-5 and p[0] == q[0] and p[2] == q[2]
                         for q, m in removed.items() if m >= n)})
log(f"MULTISET removed={sorted(removed.elements())}")
log(f"MULTISET added={sorted(added.elements())}")
log(f"MULTISET added_are_lifted_by_grid={sum(lifted.values())}/{sum(added.values())}")

per_index_same = sum(1 for a, b in zip(v0, v1) if a == b)
moved_idx = [i for i, (a, b) in enumerate(zip(v0, v1)) if a != b]
log(f"PER-INDEX: same={per_index_same}/{len(v0)} moved_idx={moved_idx}")

op("history.undo")
time.sleep(2); wait_idle(60); time.sleep(2)
bsn_u = entity_bsn(product)
with open(f"{OUT}/r8c-after-undo.bsn.txt", "w") as f:
    f.write(bsn_u)
v_u = vert_positions(bsn_u)
cu = Counter(v_u)
log(f"ASSERT-A2 undo: faces={bsn_u.count('BrushFaceData')} verts={len(v_u)} "
    f"multiset_identical={cu == c0} per_index_identical={v_u == v0} "
    f"undo_len={brp('jackdaw/history', {})['result']['undo_len']}")
log("=== R8C CLEAN-ROOM LEG A END ===")
