#!/usr/bin/env python3
"""R7 run7b: click the framed product's face, PageUp, assert.
Usage: r7-run7b.py <x> <y>   (window-logical click coordinates)"""
import json, re, subprocess, sys, time

PORT = 15703
OUT = "/Users/linbo.zhang/workspace/jackdaw/loop/bug-r7-qa"
SHOTDIR = "r7qa-shots"
CX, CY = float(sys.argv[1]), float(sys.argv[2])

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
    archive(f"r7-run7b-op-{op_id.replace('.', '_')}", r)
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
    parts = bsn.split("vertices: [")
    if len(parts) < 2:
        return []
    tail = parts[1].split("]", 1)[0]
    return [tuple(float(v) for v in t) for t in
            re.findall(r"position: glam::Vec3 \{ x: ([0-9.eE+-]+), y: ([0-9.eE+-]+), z: ([0-9.eE+-]+)", tail)]

def screenshot(name, kind="viewport"):
    r = brp("jackdaw/screenshot", {"kind": kind, "path": f"{SHOTDIR}/{name}.png"})
    archive(f"r7-run7b-shot-{name}", r)
    time.sleep(1.5)
    subprocess.run(["cp", f"/Users/linbo.zhang/workspace/jackdaw/tests/fixtures/bsn_game/{SHOTDIR}/{name}.png",
                    f"{OUT}/{name}.png"], capture_output=True)

state = json.load(open(f"{OUT}/r7-run7-state.json"))
product_bits = state["bits"]
faces0, verts0 = state["faces"], state["verts"]
verts_before = [tuple(v) for v in state["positions"]]

log(f"=== R7 RUN7B BEGIN (product {product_bits}, click {CX},{CY}) ===")

# probes before the click
edit_mode = brp("world.get_resources", {"resource": "jackdaw::brush::EditMode"})
halfedge_q = brp("world.query", {"data": {"components": []},
                                 "filter": {"with": ["jackdaw::brush::BrushHalfedge"]}})
log(f"probes pre-click: EditMode={edit_mode['result']['value']} "
    f"BrushHalfedge entities={halfedge_q.get('result')}")

# 1) click the face
r = op("input.pointer", {"x": CX, "y": CY, "action": "click", "button": "primary"})
log(f"click reply: {json.dumps(r)[:120]}")
time.sleep(2); wait_idle(60); time.sleep(2)
edit_mode = brp("world.get_resources", {"resource": "jackdaw::brush::EditMode"})
log(f"EditMode after click: {edit_mode['result']['value']}")
screenshot("r7-run7-after-click")

# 2) PageUp
h_pre = brp("jackdaw/history", {})
archive("r7-run7-history-pre", h_pre)
log(f"history pre-nudge: undo_len={h_pre['result']['undo_len']} top={h_pre['result']['top']}")
op("input.key", {"key": "PageUp", "action": "tap"})
time.sleep(2); wait_idle(60); time.sleep(2)
h_post = brp("jackdaw/history", {})
archive("r7-run7-history-post", h_post)
delta = h_post["result"]["undo_len"] - h_pre["result"]["undo_len"]
log(f"history post-nudge: undo_len={h_post['result']['undo_len']} top={h_post['result']['top']} delta={delta}")

# 3) assertions
bsn1 = entity_bsn(product_bits)
faces1, verts1 = brush_shape(bsn1)
verts_after = vert_positions(bsn1)
same_count = len(verts_after) == len(verts_before)
moved = sum(1 for a, b in zip(verts_before, verts_after) if any(abs(x - y) > 1e-5 for x, y in zip(a, b)))
lifted = sum(1 for a, b in zip(verts_before, verts_after) if abs((b[1] - a[1]) - 0.25) < 1e-4)
log(f"ASSERT1 shape-preserved: faces {faces0}->{faces1} verts {verts0}->{verts1} "
    f"moved_verts={moved} lifted_by_grid={lifted} (counts equal: {same_count and faces1 == faces0})")
screenshot("r7-run7-after-nudge")

# 4) undo restores exactly
op("history.undo")
time.sleep(2); wait_idle(60); time.sleep(2)
bsn_u = entity_bsn(product_bits)
faces_u, verts_u = brush_shape(bsn_u)
verts_undo = vert_positions(bsn_u)
ident = verts_undo == verts_before and faces_u == faces0
h_u = brp("jackdaw/history", {})
log(f"ASSERT2 undo-restores: faces={faces_u} verts={verts_u} identical_to_baseline={ident} "
    f"undo_len={h_u['result']['undo_len']} (pre={h_pre['result']['undo_len']})")
screenshot("r7-run7-after-undo")
op("brush.exit_edit_mode")
log("=== R7 RUN7B END ===")
