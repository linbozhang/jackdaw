#!/usr/bin/env python3
"""R7 live leg 4: L-shaped concave brush with exact entity bookkeeping.
Every spawned brush is located by diffing the scene_tree snapshots taken
before/after each add, and every move is verified by reading the entity's
BSN translation back before proceeding."""
import json, re, subprocess, sys, time

PORT = 15703
OUT = "/Users/linbo.zhang/workspace/jackdaw/loop/bug-r7-qa"

def brp(method, params, timeout=25):
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

def archive(name, obj):
    with open(f"{OUT}/{name}.json", "w") as f:
        json.dump(obj, f, indent=1)

def tree_entities():
    d = brp("jackdaw/scene_tree", {})
    return {n["entity"]: n.get("name") for n in d["result"]["tree"]}

def wait_idle(limit=120):
    deadline = time.time() + limit
    while time.time() < deadline:
        r = brp("jackdaw/wait", {"until": "idle"})
        if r.get("result", {}).get("idle") is True:
            return True
        time.sleep(1)
    return False

def op(op_id, params=None):
    r = brp("jackdaw/call_operator", {"id": op_id, "params": params or {}})
    archive(f"r7-op-{op_id.replace('.', '_')}", r)
    return r

def entity_bsn(bits):
    r = brp("jackdaw/entity", {"entity": bits})
    return r.get("result", {}).get("bsn", "")

def bsn_translation(bsn):
    m = re.findall(r"translation: glam::Vec3A? \{ x: ([0-9.eE+-]+), y: ([0-9.eE+-]+), z: ([0-9.eE+-]+)", bsn)
    return [tuple(float(v) for v in t) for t in m[:1]]

def brush_shape(bsn):
    """Count BrushFaceData blocks and topology vertices in the entity BSN."""
    faces = bsn.count("BrushFaceData")
    vm = re.search(r"vertices: \[", bsn)
    verts = len(re.findall(r"position: glam::Vec3 \{", bsn))
    return faces, verts

log("=== R7 LEG4 BEGIN ===")

# 0) clean slate: undo until the scene is empty (or 12 attempts)
for i in range(12):
    ents = tree_entities()
    if not ents:
        break
    archive(f"r7-leg4-tree-pre-undo-{i}", ents)
    op("history.undo")
    time.sleep(1)
wait_idle(60)
ents = tree_entities()
log(f"scene after undos: {ents}")
if ents:
    log("LEG4_FAIL: scene not empty after 12 undos")
    sys.exit(1)

def add_cube(tag):
    before = tree_entities()
    r = op("entity.add.cube")
    time.sleep(1); wait_idle(60); time.sleep(1)
    after = tree_entities()
    new_bits = [b for b in after if b not in before]
    if len(new_bits) != 1:
        log(f"ADD_CUBE_FAIL {tag}: new entities {new_bits}")
        sys.exit(1)
    bits = new_bits[0]
    log(f"add_cube {tag}: bits={bits}")
    return bits

def nudge_selected(axis, steps, bits, expect_xyz):
    r = brp("jackdaw/selection.set", {"entities": [bits]})
    archive(f"r7-leg4-sel-{axis}-{bits}", r)
    time.sleep(0.5)
    for i in range(steps):
        op(f"transform.nudge_{axis}_pos")
    time.sleep(1); wait_idle(60)
    t = bsn_translation(entity_bsn(bits))
    ok = t and all(abs(a - b) < 1e-4 for a, b in zip(t[0], expect_xyz))
    log(f"nudge {axis}x{steps} on {bits}: translation now {t} (expect ~{expect_xyz}) {'OK' if ok else 'MISMATCH'}")
    return ok

# 1) target A at origin
bits_a = add_cube("A")
# 2) cutter B at (0.5,0.5,0.5)
bits_b = add_cube("B")
if not nudge_selected("x", 2, bits_b, (0.5, 0.0, 0.0)): sys.exit(1)
if not nudge_selected("y", 2, bits_b, (0.5, 0.5, 0.0)): sys.exit(1)
if not nudge_selected("z", 2, bits_b, (0.5, 0.5, 0.5)): sys.exit(1)
# 3) harmless cutter C at (10,0,0)
bits_c = add_cube("C")
if not nudge_selected("x", 40, bits_c, (10.0, 0.0, 0.0)): sys.exit(1)

ents = tree_entities()
log(f"scene after layout: {ents}")

# 4) history before the subtract
h = brp("jackdaw/history", {})
archive("r7-leg4-history-before-subtract", h)
log(f"history before subtract: undo_len={h['result']['undo_len']}")

# 5) select the two cutters and subtract
r = brp("jackdaw/selection.set", {"entities": [bits_b, bits_c]})
archive("r7-leg4-sel-cutters", r)
log(f"selection: {r['result']['selection']}")
sel_bits = [e["entity"] for e in r["result"]["selection"]]
if set(sel_bits) != {bits_b, bits_c}:
    log(f"LEG4_FAIL: selection mismatch {sel_bits} != {[bits_b, bits_c]}")
    sys.exit(1)

r = op("brush.csg_subtract")
log(f"subtract reply: {json.dumps(r)[:200]}")
time.sleep(2); wait_idle(180); time.sleep(2)

ents = tree_entities()
log(f"scene after subtract: {ents}")
h = brp("jackdaw/history", {})
archive("r7-leg4-history-after-subtract", h)

# 6) find the product: any entity whose brush is no longer a plain 6-face cube
for bits, name in ents.items():
    bsn = entity_bsn(bits)
    faces, verts = brush_shape(bsn)
    t = bsn_translation(bsn)
    log(f"entity {bits} ({name}): faces={faces} verts={verts} translation={t}")
    archive(f"r7-leg4-brush-{bits}", {"bsn": bsn, "faces": faces, "verts": verts})
    if faces != 6:
        log(f"PRODUCT FOUND: {bits} with {faces} faces — concave brush built")
log("=== R7 LEG4 END ===")
