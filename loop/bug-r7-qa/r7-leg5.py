#!/usr/bin/env python3
"""R7 live leg 5: the actual nudge (PageUp) on the concave L brush.
Preconditions: leg4 built the L brush (9 faces / 14 verts) at the origin,
entity bits are passed on the command line.
Steps:
  1 select the product, enter Face mode
  2 screenshot the viewport, click the brush's face in the 3D viewport centre
  3 history snapshot, PageUp via input.key, history snapshot again
  4 assert: faces/verts unchanged (9/14), undo_len +1, undo restores the BSN
"""
import json, re, subprocess, sys, time

PORT = 15703
OUT = "/Users/linbo.zhang/workspace/jackdaw/loop/bug-r7-qa"
PRODUCT_BITS = int(sys.argv[1]) if len(sys.argv) > 1 else 34359733269
CLICK_XY = (float(sys.argv[2]), float(sys.argv[3])) if len(sys.argv) > 3 else (480.0, 270.0)

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

def op(op_id, params=None):
    r = brp("jackdaw/call_operator", {"id": op_id, "params": params or {}})
    archive(f"r7-leg5-op-{op_id.replace('.', '_')}", r)
    return r

def wait_idle(limit=120):
    deadline = time.time() + limit
    while time.time() < deadline:
        if brp("jackdaw/wait", {"until": "idle"}).get("result", {}).get("idle") is True:
            return True
        time.sleep(1)
    return False

def entity_bsn(bits):
    return brp("jackdaw/entity", {"entity": bits}).get("result", {}).get("bsn", "")

def brush_shape(bsn):
    return bsn.count("BrushFaceData"), len(re.findall(r"position: glam::Vec3 \{", bsn))

def vert_positions(bsn):
    """All topology vertex positions, in stored order."""
    block = bsn.split("vertices: [", 1)
    if len(block) < 2:
        return []
    tail = block[1].split("]", 1)[0]
    return [tuple(float(v) for v in t) for t in
            re.findall(r"position: glam::Vec3 \{ x: ([0-9.eE+-]+), y: ([0-9.eE+-]+), z: ([0-9.eE+-]+)", tail)]

log(f"=== R7 LEG5 BEGIN (product {PRODUCT_BITS}, click {CLICK_XY}) ===")

# 1) select the product, enter Face mode
r = brp("jackdaw/selection.set", {"entities": [PRODUCT_BITS]})
archive("r7-leg5-sel-product", r)
log(f"selection: {r['result']['selection']}")
time.sleep(1)
r = op("edit_mode.face")
time.sleep(2); wait_idle(60); time.sleep(2)
bsn = entity_bsn(PRODUCT_BITS)
faces0, verts0 = brush_shape(bsn)
verts_before = vert_positions(bsn)
log(f"face mode entered; product shape: faces={faces0} verts={verts0}")

# 2) screenshot the viewport for the click-coordinate evidence
r = brp("jackdaw/screenshot", {"kind": "viewport", "path": f"{OUT}/r7-leg5-viewport-before.png"})
archive("r7-leg5-screenshot-before", r)
time.sleep(2)

# 3) click the face (window-logical coordinates)
r = op("input.pointer", {"x": CLICK_XY[0], "y": CLICK_XY[1], "action": "click", "button": "primary"})
log(f"click reply: {json.dumps(r)[:150]}")
time.sleep(2); wait_idle(60); time.sleep(2)

# 4) history before, PageUp, history after
h0 = brp("jackdaw/history", {})
archive("r7-leg5-history-before", h0)
log(f"history before PageUp: undo_len={h0['result']['undo_len']} top={h0['result']['top']}")

r = op("input.key", {"key": "PageUp", "action": "tap"})
log(f"PageUp reply: {json.dumps(r)[:150]}")
time.sleep(2); wait_idle(60); time.sleep(2)

h1 = brp("jackdaw/history", {})
archive("r7-leg5-history-after", h1)
log(f"history after PageUp: undo_len={h1['result']['undo_len']} top={h1['result']['top']} redo_len={h1['result']['redo_len']}")

# 5) assertion 1: the brush kept its shape
bsn_after = entity_bsn(PRODUCT_BITS)
faces1, verts1 = brush_shape(bsn_after)
verts_after = vert_positions(bsn_after)
log(f"ASSERT1 shape: faces {faces0}->{faces1} verts {verts0}->{verts1}")
moved = sum(1 for a, b in zip(verts_before, verts_after) if any(abs(x - y) > 1e-5 for x, y in zip(a, b)))
log(f"ASSERT1 moved verts: {moved} (expect the selected face's ring)")

r = brp("jackdaw/screenshot", {"kind": "viewport", "path": f"{OUT}/r7-leg5-viewport-after.png"})
archive("r7-leg5-screenshot-after", r)
time.sleep(2)

# 6) assertion 2: exactly one undo entry and undo restores the geometry
delta = h1["result"]["undo_len"] - h0["result"]["undo_len"]
log(f"ASSERT2 undo entries added by the nudge: {delta} (expect 1)")
op("history.undo")
time.sleep(2); wait_idle(60); time.sleep(2)
bsn_undo = entity_bsn(PRODUCT_BITS)
faces_u, verts_u = brush_shape(bsn_undo)
verts_undo = vert_positions(bsn_undo)
same = verts_undo == verts_before
log(f"ASSERT2 after undo: faces={faces_u} verts={verts_u} verts_identical={same}")
h2 = brp("jackdaw/history", {})
archive("r7-leg5-history-after-undo", h2)

# 7) leave edit mode
op("brush.exit_edit_mode")
log("=== R7 LEG5 END ===")
