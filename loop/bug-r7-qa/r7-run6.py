#!/usr/bin/env python3
"""R7 run6: rebuild the L brush, frame it in the 3D viewport, click its face
at the viewport-panel centre (window-logical coords derived from the ui_tree
physical rect / 2 for the retina scale), PageUp, assert shape/undo."""
import json, re, subprocess, sys, time

PORT = 15703
OUT = "/Users/linbo.zhang/workspace/jackdaw/loop/bug-r7-qa"
SHOTDIR = "r7qa-shots"
VIEWPORT_PHYS = [293.0, 95.0, 1377.0, 753.0]  # ui_tree rect (physical px)
SCALE = 2.0  # retina

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

def archive(name, obj):
    with open(f"{OUT}/{name}.json", "w") as f:
        json.dump(obj, f, indent=1)

def op(op_id, params=None):
    r = brp("jackdaw/call_operator", {"id": op_id, "params": params or {}})
    archive(f"r7-run6-op-{op_id.replace('.', '_')}", r)
    return r

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

def bsn_translation(bsn):
    m = re.findall(r"translation: glam::Vec3A? \{ x: ([0-9.eE+-]+), y: ([0-9.eE+-]+), z: ([0-9.eE+-]+)", bsn)
    return [tuple(float(v) for v in t) for t in m[:1]]

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
        log(f"ADD_CUBE_FAIL {tag}: {new_bits}")
        sys.exit(1)
    log(f"add_cube {tag}: bits={new_bits[0]}")
    return new_bits[0]

def nudge_to(axis, steps, bits, expect):
    brp("jackdaw/selection.set", {"entities": [bits]})
    time.sleep(0.5)
    for _ in range(steps):
        op(f"transform.nudge_{axis}_pos")
    time.sleep(1); wait_idle(60)
    t = bsn_translation(entity_bsn(bits))
    ok = t and all(abs(a - b) < 1e-4 for a, b in zip(t[0], expect))
    log(f"  {axis}x{steps} -> {t} {'OK' if ok else 'MISMATCH'}")
    return ok

def screenshot(name, kind="viewport"):
    r = brp("jackdaw/screenshot", {"kind": kind, "path": f"{SHOTDIR}/{name}.png"})
    archive(f"r7-run6-shot-{name}", r)
    time.sleep(1.5)
    subprocess.run(["cp", f"/Users/linbo.zhang/workspace/jackdaw/tests/fixtures/bsn_game/{SHOTDIR}/{name}.png",
                    f"{OUT}/{name}.png"], capture_output=True)

log("=== R7 RUN6 BEGIN ===")

# 0) clean slate (the previous run's undo already reverted the subtract;
#    the add-cube entries are still on the stack)
op("brush.exit_edit_mode")
for i in range(10):
    if not tree_entities():
        break
    op("history.undo")
    time.sleep(1)
ents = tree_entities()
log(f"scene after clean: {ents}")
if ents:
    log("RUN6_FAIL: scene not empty; reboot needed")
    sys.exit(1)

# 1) rebuild the L brush
bits_a = add_cube("A")
bits_b = add_cube("B")
ok = nudge_to("x", 2, bits_b, (0.5, 0.0, 0.0)) \
     and nudge_to("y", 2, bits_b, (0.5, 0.5, 0.0)) \
     and nudge_to("z", 2, bits_b, (0.5, 0.5, 0.5))
bits_c = add_cube("C")
ok = ok and nudge_to("x", 40, bits_c, (10.0, 0.0, 0.0))
if not ok:
    log("RUN6_FAIL: layout mismatch")
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
    log("RUN6_FAIL: no concave product")
    sys.exit(1)

bsn0 = entity_bsn(product_bits)
faces0, verts0 = brush_shape(bsn0)
verts_before = vert_positions(bsn0)
archive("r7-run6-baseline", {"bits": product_bits, "faces": faces0, "verts": verts0,
                             "positions": verts_before})

# 2) frame the product in the viewport, then click its face
brp("jackdaw/selection.set", {"entities": [product_bits]})
time.sleep(1)
op("view.frame_selected")
time.sleep(2); wait_idle(60); time.sleep(2)
op("edit_mode.face")
time.sleep(2); wait_idle(60); time.sleep(2)
screenshot("r7-run6-before-click")

cx = (VIEWPORT_PHYS[0] + VIEWPORT_PHYS[2] / 2) / SCALE
cy = (VIEWPORT_PHYS[1] + VIEWPORT_PHYS[3] / 2) / SCALE
log(f"clicking viewport-panel centre, window-logical ({cx}, {cy})")
op("input.pointer", {"x": cx, "y": cy, "action": "click", "button": "primary"})
time.sleep(2); wait_idle(60); time.sleep(2)
screenshot("r7-run6-after-click")

# 3) PageUp through the real keybind
h_pre = brp("jackdaw/history", {})
archive("r7-run6-history-pre", h_pre)
log(f"history pre-nudge: undo_len={h_pre['result']['undo_len']} top={h_pre['result']['top']}")
op("input.key", {"key": "PageUp", "action": "tap"})
time.sleep(2); wait_idle(60); time.sleep(2)
h_post = brp("jackdaw/history", {})
archive("r7-run6-history-post", h_post)
delta = h_post["result"]["undo_len"] - h_pre["result"]["undo_len"]
log(f"history post-nudge: undo_len={h_post['result']['undo_len']} top={h_post['result']['top']} delta={delta}")

# 4) assertions
bsn1 = entity_bsn(product_bits)
faces1, verts1 = brush_shape(bsn1)
verts_after = vert_positions(bsn1)
moved = sum(1 for a, b in zip(verts_before, verts_after) if any(abs(x - y) > 1e-5 for x, y in zip(a, b)))
lifted = sum(1 for a, b in zip(verts_before, verts_after) if abs((b[1] - a[1]) - 0.25) < 1e-4)
log(f"ASSERT1: faces {faces0}->{faces1} verts {verts0}->{verts1} moved={moved} lifted_by_one_grid={lifted}")
screenshot("r7-run6-after-nudge")

op("history.undo")
time.sleep(2); wait_idle(60); time.sleep(2)
bsn_u = entity_bsn(product_bits)
faces_u, verts_u = brush_shape(bsn_u)
verts_undo = vert_positions(bsn_u)
ident = verts_undo == verts_before
log(f"ASSERT2: after undo faces={faces_u} verts={verts_u} verts_identical={ident}")
h_u = brp("jackdaw/history", {})
log(f"ASSERT2: undo_len now {h_u['result']['undo_len']} (pre-nudge {h_pre['result']['undo_len']})")
screenshot("r7-run6-after-undo")
log("=== R7 RUN6 END ===")
