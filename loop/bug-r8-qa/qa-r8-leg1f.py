#!/usr/bin/env python3
"""R8 QA leg1f: full leg on the debug-log editor. Build the L, arm the
Face-mode state, call extend, then assert refusal + zero side effects +
toast; the debug editor log should name whichever stage turns the call down."""
import json, re, subprocess, sys, time
from collections import Counter

PORT = 15703
OUT = "/Users/linbo.zhang/workspace/jackdaw/loop/bug-r8-qa"
GRID = 0.25

def brp(m, p, t=30):
    r = subprocess.run(["curl", "-s", "--max-time", str(t), "-X", "POST",
                        f"http://127.0.0.1:{PORT}/", "-H", "Content-Type: application/json",
                        "-d", json.dumps({"jsonrpc": "2.0", "id": 1, "method": m, "params": p})],
                       capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"raw": r.stdout[:200]}

def log(m):
    line = f"[{time.strftime('%H:%M:%S')}] {m}"
    print(line, flush=True)
    with open(f"{OUT}/r8qa-console.log", "a") as f:
        f.write(line + "\n")

def op(op_id, params=None):
    return brp("jackdaw/call_operator", {"id": op_id, "params": params or {}})

def wait_idle(limit=120):
    d = time.time() + limit
    while time.time() < d:
        if brp("jackdaw/wait", {"until": "idle"}).get("result", {}).get("idle") is True:
            return True
        time.sleep(1)
    return False

def tree_entities():
    d = brp("jackdaw/scene_tree", {})
    return {n["entity"]: n.get("name") for n in d["result"]["tree"]}

def entity_bsn(bits):
    return brp("jackdaw/entity", {"entity": bits}).get("result", {}).get("bsn", "")

POS_RE = re.compile(r"x: ([0-9.eE+-]+),\s*y: ([0-9.eE+-]+),\s*z: ([0-9.eE+-]+)")

def verts(bsn):
    parts = bsn.split("vertices: [")
    if len(parts) < 2:
        return []
    tail = parts[1].split("]", 1)[0]
    return [tuple(round(float(v), 6) for v in m) for m in POS_RE.findall(tail)]

def history():
    return brp("jackdaw/history", {}).get("result", {})

def avail():
    d = brp("jackdaw/operators", {})
    r = d.get("result")
    ops = r if isinstance(r, list) else r.get("operators", r.get("list", []))
    for o in ops:
        if isinstance(o, dict) and o.get("id") == "brush.extend_face_to_brush":
            return o.get("available")

log("=== R8QA LEG1F BEGIN (debug-log editor, full chain) ===")
ents = {b: n for b, n in tree_entities().items() if n != "Root"}
if ents:
    log(f"LEG1F_FAIL: scene not empty: {ents}")
    sys.exit(1)

def add_cube(tag):
    before = tree_entities()
    op("entity.add.cube")
    time.sleep(1); wait_idle(60); time.sleep(1)
    new_bits = [b for b in tree_entities() if b not in before]
    if len(new_bits) != 1:
        log(f"LEG1F_FAIL: add_cube {tag}")
        sys.exit(1)
    return new_bits[0]

def nudge_axis(axis, sign, steps, bits, expect):
    brp("jackdaw/selection.set", {"entities": [bits]})
    time.sleep(0.5)
    for _ in range(steps):
        op(f"transform.nudge_{axis}_{sign}")
    time.sleep(1); wait_idle(60)
    bsn = entity_bsn(bits)
    m = re.findall(r"translation: glam::Vec3A? \{ x: ([0-9.eE+-]+), y: ([0-9.eE+-]+), z: ([0-9.eE+-]+)", bsn)
    t = [tuple(round(float(v), 6) for v in x) for x in m[:1]]
    ok = t and all(abs(a - b) < 1e-4 for a, b in zip(t[0], expect))
    log(f"  nudge {bits} -> {t} {'OK' if ok else 'MISMATCH'}")
    return bool(ok)

bits_a = add_cube("A")
bits_b = add_cube("B")
ok = nudge_axis("x", "pos", 2, bits_b, (0.5, 0.0, 0.0)) \
     and nudge_axis("y", "pos", 2, bits_b, (0.5, 0.5, 0.0)) \
     and nudge_axis("z", "pos", 2, bits_b, (0.5, 0.5, 0.5))
bits_c = add_cube("C")
ok = ok and nudge_axis("x", "pos", 40, bits_c, (10.0, 0.0, 0.0))
if not ok:
    log("LEG1F_FAIL: layout")
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
    log("LEG1F_FAIL: no 9-face L")
    sys.exit(1)
bsn0 = entity_bsn(product)
with open(f"{OUT}/r8qa-leg1f-baseline.bsn.txt", "w") as f:
    f.write(bsn0)
log(f"L product: {product} faces={bsn0.count('BrushFaceData')} verts={len(verts(bsn0))}")

brp("jackdaw/selection.set", {"entities": [product, bits_c]})
time.sleep(1.5)
r = brp("jackdaw/call_operator", {"id": "brush.selection.set_faces",
                                  "params": {"entity": product, "faces": "0"}})
log(f"set_faces: {r.get('result', {}).get('result')}")
time.sleep(1.5)
log(f"avail#1: {avail()}")

h0 = history()
ext = op("brush.extend_face_to_brush")
log(f"extend reply: {json.dumps(ext.get('result'))}")
time.sleep(1); wait_idle(60); time.sleep(1)
log(f"avail#2: {avail()}")

TOAST_Q = {"data": {"components": []}, "filter": {"with": ["jackdaw_feathers::toast::EditorToast"]}}
log(f"TOAST query: {json.dumps(brp('world.query', TOAST_Q))[:200]}")
texts = []
def walk(nodes):
    for n in nodes:
        if n.get("text"):
            texts.append(n.get("text"))
        walk(n.get("children", []))
walk(brp("jackdaw/ui_tree", {"depth": 24}).get("result", {}).get("nodes", []))
hits = [t for t in texts if "concave" in t.lower() or "refus" in t.lower()]
log(f"TOAST ui_tree hits: {hits}")
brp("jackdaw/screenshot", {"kind": "window", "path": f"{OUT}/r8qa-leg1f-toast-window.png"})

bsn1 = entity_bsn(product)
with open(f"{OUT}/r8qa-leg1f-after.bsn.txt", "w") as f:
    f.write(bsn1)
h1 = history()
log(f"AFTER: bsn_identical={bsn1 == bsn0} faces={bsn1.count('BrushFaceData')} "
    f"verts={len(verts(bsn1))} undo_delta={h1.get('undo_len', -99) - h0.get('undo_len', -99)} "
    f"top={h1.get('top')}")
log("=== R8QA LEG1F END ===")
