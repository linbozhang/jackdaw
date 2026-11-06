#!/usr/bin/env python3
"""R7 run7a: rebuild the L brush on a fresh boot, frame it, enter face mode,
screenshot. Writes run7-state.json (product bits, baseline topology)."""
import json, re, subprocess, sys, time

PORT = 15703
OUT = "/Users/linbo.zhang/workspace/jackdaw/loop/bug-r7-qa"
SHOTDIR = "r7qa-shots"

def brp(method, params, timeout=30):
    payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
    r = subprocess.run(["curl", "-s", "--max-time", str(timeout), "-X", "POST",
                        f"http://127.0.0.1:{PORT}/", "-H", "Content-Type: application/json",
                        "-d", payload], capture_output=True, text=True)
    return json.loads(r.stdout)

def log(msg):
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    with open(f"{OUT}/r7-console.log", "a") as f:
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

def brush_shape(bsn):
    return bsn.count("BrushFaceData"), len(re.findall(r"position: glam::Vec3 \{", bsn))

def vert_positions(bsn):
    parts = bsn.split("vertices: [")
    if len(parts) < 2:
        return []
    tail = parts[1].split("]", 1)[0]
    return [tuple(float(v) for v in t) for t in
            re.findall(r"position: glam::Vec3 \{ x: ([0-9.eE+-]+), y: ([0-9.eE+-]+), z: ([0-9.eE+-]+)", tail)]

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
    m = re.findall(r"translation: glam::Vec3A? \{ x: ([0-9.eE+-]+), y: ([0-9.eE+-]+), z: ([0-9.eE+-]+)",
                   entity_bsn(bits))
    t = [tuple(float(v) for v in x) for x in m[:1]]
    ok = t and all(abs(a - b) < 1e-4 for a, b in zip(t[0], expect))
    log(f"  {axis}x{steps} -> {t} {'OK' if ok else 'MISMATCH'}")
    return ok

log("=== R7 RUN7A BEGIN ===")
ents = {b: n for b, n in tree_entities().items() if n != "Root"}
log(f"scene at start (Root excluded): {ents}")
if ents:
    log("RUN7A_FAIL: scene not empty on fresh boot")
    sys.exit(1)

bits_a = add_cube("A")
bits_b = add_cube("B")
ok = nudge_to("x", 2, bits_b, (0.5, 0.0, 0.0)) \
     and nudge_to("y", 2, bits_b, (0.5, 0.5, 0.0)) \
     and nudge_to("z", 2, bits_b, (0.5, 0.5, 0.5))
bits_c = add_cube("C")
ok = ok and nudge_to("x", 40, bits_c, (10.0, 0.0, 0.0))
if not ok:
    log("RUN7A_FAIL: layout mismatch")
    sys.exit(1)

brp("jackdaw/selection.set", {"entities": [bits_b, bits_c]})
time.sleep(1)
op("brush.csg_subtract")
time.sleep(2); wait_idle(180); time.sleep(2)

product_bits = None
for bits, name in tree_entities().items():
    faces, verts = brush_shape(entity_bsn(bits))
    if faces != 6:
        product_bits = bits
        log(f"product: {bits} faces={faces} verts={verts}")
if product_bits is None:
    log("RUN7A_FAIL: no concave product")
    sys.exit(1)

bsn0 = entity_bsn(product_bits)
faces0, verts0 = brush_shape(bsn0)
state = {"bits": product_bits, "faces": faces0, "verts": verts0,
         "positions": vert_positions(bsn0),
         "history_undo_len": brp("jackdaw/history", {})["result"]["undo_len"]}
with open(f"{OUT}/r7-run7-state.json", "w") as f:
    json.dump(state, f, indent=1)
log(f"baseline: faces={faces0} verts={verts0} undo_len={state['history_undo_len']}")

# frame the product and enter face mode
brp("jackdaw/selection.set", {"entities": [product_bits]})
time.sleep(1)
op("view.frame_selected")
time.sleep(2); wait_idle(60); time.sleep(2)
op("edit_mode.face")
time.sleep(2); wait_idle(60); time.sleep(2)

r = brp("jackdaw/screenshot", {"kind": "viewport", "path": f"{SHOTDIR}/r7-run7-before-click.png"})
time.sleep(1.5)
subprocess.run(["cp", f"/Users/linbo.zhang/workspace/jackdaw/tests/fixtures/bsn_game/{SHOTDIR}/r7-run7-before-click.png",
                f"{OUT}/r7-run7-before-click.png"], capture_output=True)
log(f"screenshot: {json.dumps(r)[:120]}")

# structured-path probe: does brush.nudge_up through call_operator see the
# populated BrushSelection? (Separates core-path health from key-dispatch.)
halfedge_q = brp("world.query", {"data": {"components": []},
                                 "filter": {"with": ["jackdaw::brush::BrushHalfedge"]}})
log(f"BrushHalfedge entities after face mode: {halfedge_q.get('result')}")
nr = op("brush.nudge_up")
log(f"structured brush.nudge_up probe: {json.dumps(nr)[:140]}")
time.sleep(2); wait_idle(60); time.sleep(2)
faces_p, verts_p = brush_shape(entity_bsn(product_bits))
moved = sum(1 for a, b in zip(state["positions"], vert_positions(entity_bsn(product_bits)))
            if any(abs(x - y) > 1e-5 for x, y in zip(a, b)))
log(f"after structured probe: faces={faces_p} verts={verts_p} moved_verts={moved}")
# undo the probe so run7b starts from the baseline
op("history.undo")
time.sleep(2); wait_idle(60); time.sleep(2)
faces_r, verts_r = brush_shape(entity_bsn(product_bits))
log(f"after probe-undo: faces={faces_r} verts={verts_r} (expect {faces0}/{verts0})")
log("=== R7 RUN7A END (awaiting manual click coordinates) ===")
