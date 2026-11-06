#!/usr/bin/env python3
"""R8b: the r8 legs with the FIXED vertex-position parser (the BSN spells
MeshVert positions across three lines; the old single-line regex matched
nothing, so every moved-vert comparison ran on empty lists). The editor
session is reused: the L product sits at its baseline with Face mode on."""
import json, math, re, subprocess, sys, time

PORT = 15703
OUT = "/Users/linbo.zhang/workspace/jackdaw/loop/bug-r7-qa"
SHOTDIR = "r7qa-shots"
GRID = 0.25
PRODUCT = 38654700367

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

def archive(name, obj):
    with open(f"{OUT}/{name}.json", "w") as f:
        json.dump(obj, f, indent=1)

def op(op_id, params=None):
    r = brp("jackdaw/call_operator", {"id": op_id, "params": params or {}})
    archive(f"r8b-op-{op_id.replace('.', '_')}", r)
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

POS_RE = re.compile(
    r"position: glam::Vec3 \{\s*x: ([0-9.eE+-]+),\s*y: ([0-9.eE+-]+),\s*z: ([0-9.eE+-]+)",
    re.S)

def vert_positions(bsn):
    parts = bsn.split("vertices: [")
    if len(parts) < 2:
        return []
    tail = parts[1].split("]", 1)[0]
    return [tuple(float(v) for v in m) for m in POS_RE.findall(tail)]

def brush_shape(bsn):
    return bsn.count("BrushFaceData"), len(POS_RE.findall(bsn))

def bsn_translation_rotation(bsn):
    m = re.findall(r"translation: glam::Vec3A? \{ x: ([0-9.eE+-]+), y: ([0-9.eE+-]+), z: ([0-9.eE+-]+)", bsn)
    t = [tuple(float(v) for v in x) for x in m[:1]]
    q = re.findall(r"rotation: glam::Quat \{\s*x: ([0-9.eE+-]+),\s*y: ([0-9.eE+-]+),\s*z: ([0-9.eE+-]+),\s*w: ([0-9.eE+-]+)", bsn, re.S)
    rot = tuple(float(v) for v in q[0]) if q else (0.0, 0.0, 0.0, 1.0)
    return (t[0] if t else (0.0, 0.0, 0.0)), rot

def quat_rotate(q, v):
    x, y, z, w = q
    ux, uy, uz = y * v[2] - z * v[1], z * v[0] - x * v[2], x * v[1] - y * v[0]
    return (v[0] + 2 * (w * ux + (uy * v[2] - uz * v[1])),
            v[1] + 2 * (w * uy + (uz * v[0] - ux * v[2])),
            v[2] + 2 * (w * uz + (ux * v[1] - uy * v[0])))

def screenshot(name):
    r = brp("jackdaw/screenshot", {"kind": "viewport", "path": f"{SHOTDIR}/{name}.png"})
    archive(f"r8b-shot-{name}", r)
    time.sleep(1.5)
    subprocess.run(["cp", f"/Users/linbo.zhang/workspace/jackdaw/tests/fixtures/bsn_game/{SHOTDIR}/{name}.png",
                    f"{OUT}/{name}.png"], capture_output=True)

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

log("=== R8B RE-RUN (fixed parser) BEGIN ===")

# sanity: the fixed parser now reads positions
probe = vert_positions(entity_bsn(PRODUCT))
log(f"parser probe on the L product: {len(probe)} verts read, sample={probe[:2]}")
if len(probe) != 14:
    log("R8B_FAIL: parser still wrong")
    sys.exit(1)

# ---- LEG A (redo, fixed parser): baseline -> set_faces -> PageUp ----
bsn0 = entity_bsn(PRODUCT)
faces0 = bsn0.count("BrushFaceData")
v_before = vert_positions(bsn0)
log(f"LEG-A baseline: faces={faces0} verts={len(v_before)}")

r = brp("jackdaw/call_operator", {"id": "brush.selection.set_faces",
                                  "params": {"entity": PRODUCT, "faces": "0"}})
archive("r8b-set-faces-A", r)
log(f"set_faces: {r.get('result', {}).get('result')} warnings={r.get('result', {}).get('warnings')}")
time.sleep(1)

h_pre = brp("jackdaw/history", {})
archive("r8b-history-pre", h_pre)
op("input.key", {"key": "PageUp", "action": "tap"})
time.sleep(2); wait_idle(60); time.sleep(2)
h_post = brp("jackdaw/history", {})
archive("r8b-history-post", h_post)
delta = h_post["result"]["undo_len"] - h_pre["result"]["undo_len"]

bsn1 = entity_bsn(PRODUCT)
faces1 = bsn1.count("BrushFaceData")
v_after = vert_positions(bsn1)
moved_idx = [i for i, (a, b) in enumerate(zip(v_before, v_after))
             if any(abs(x - y) > 1e-5 for x, y in zip(a, b))]
deltas = {tuple(round(b[k] - v_before[i][k], 4) for k in range(3)) for i in moved_idx
          for b in [v_after[i]]}
log(f"ASSERT-A1: faces {faces0}->{faces1} verts {len(v_before)}->{len(v_after)} "
    f"undo_delta={delta} moved_verts={len(moved_idx)} idx={moved_idx} deltas={deltas}")
screenshot("r8b-A-after-nudge")

op("history.undo")
time.sleep(2); wait_idle(60); time.sleep(2)
bsn_u = entity_bsn(PRODUCT)
v_undo = vert_positions(bsn_u)
faces_u = bsn_u.count("BrushFaceData")
ident = v_undo == v_before
h_u = brp("jackdaw/history", {})
log(f"ASSERT-A2: faces={faces_u} verts={len(v_undo)} bit_identical={ident} "
    f"undo_len={h_u['result']['undo_len']} (pre={h_pre['result']['undo_len']})")

# ---- LEG B: convex anchor ----
op("brush.exit_edit_mode")
time.sleep(1)
bits_d = add_cube("D")
r = brp("jackdaw/call_operator", {"id": "brush.selection.set_faces",
                                  "params": {"entity": bits_d, "faces": "0"}})
log(f"anchor set_faces: {r.get('result', {}).get('result')}")
time.sleep(1)
bsn_d0 = entity_bsn(bits_d)
df0 = bsn_d0.count("BrushFaceData")
dv_before = vert_positions(bsn_d0)
h_b = brp("jackdaw/history", {})
op("input.key", {"key": "PageUp", "action": "tap"})
time.sleep(2); wait_idle(60); time.sleep(2)
bsn_d1 = entity_bsn(bits_d)
df1 = bsn_d1.count("BrushFaceData")
dv_after = vert_positions(bsn_d1)
d_moved = [i for i, (a, b) in enumerate(zip(dv_before, dv_after))
           if any(abs(x - y) > 1e-5 for x, y in zip(a, b))]
d_deltas = {tuple(round(dv_after[i][k] - dv_before[i][k], 4) for k in range(3)) for i in d_moved}
h_bb = brp("jackdaw/history", {})
log(f"ASSERT-B: faces {df0}->{df1} verts {len(dv_before)}->{len(dv_after)} moved={len(d_moved)} "
    f"delta_set={d_deltas} undo_delta={h_bb['result']['undo_len'] - h_b['result']['undo_len']}")
screenshot("r8b-B-anchor")

# ---- LEG C: rotated brush -> world Y ----
op("brush.exit_edit_mode")
time.sleep(1)
# rotate via the transform op; verify the quaternion actually changed
r = op("transform.rotate_90_pitch_ccw")
time.sleep(1); wait_idle(60)
(t_d, q_d) = bsn_translation_rotation(entity_bsn(bits_d))
log(f"after rotate_90_pitch_ccw: quat={q_d} t={t_d}")
if q_d == (0.0, 0.0, 0.0, 1.0):
    log("rotate_90_pitch_ccw left the quat identity; trying rotate_90_yaw_cw")
    op("transform.rotate_90_yaw_cw")
    time.sleep(1); wait_idle(60)
    (t_d, q_d) = bsn_translation_rotation(entity_bsn(bits_d))
    log(f"after rotate_90_yaw_cw: quat={q_d} t={t_d}")
if q_d == (0.0, 0.0, 0.0, 1.0):
    log("R8B_FAIL: no rotation op took effect on the cube")
    sys.exit(1)

r = brp("jackdaw/call_operator", {"id": "brush.selection.set_faces",
                                  "params": {"entity": bits_d, "faces": "0"}})
log(f"rotated set_faces: {r.get('result', {}).get('result')}")
time.sleep(1)
bsn_r0 = entity_bsn(bits_d)
rf0 = bsn_r0.count("BrushFaceData")
rv_before = vert_positions(bsn_r0)
(t_r, q_r) = bsn_translation_rotation(bsn_r0)
log(f"rotated baseline: faces={rf0} verts={len(rv_before)} quat={q_r}")
op("input.key", {"key": "PageUp", "action": "tap"})
time.sleep(2); wait_idle(60); time.sleep(2)
bsn_r1 = entity_bsn(bits_d)
rf1 = bsn_r1.count("BrushFaceData")
rv_after = vert_positions(bsn_r1)
r_moved = [i for i, (a, b) in enumerate(zip(rv_before, rv_after))
           if any(abs(x - y) > 1e-5 for x, y in zip(a, b))]
world_deltas = set()
for i in r_moved:
    ld = tuple(rv_after[i][k] - rv_before[i][k] for k in range(3))
    wd = quat_rotate(q_r, ld)
    world_deltas.add(tuple(round(v, 4) for v in wd))
log(f"ASSERT-C: faces {rf0}->{rf1} verts {len(rv_before)}->{len(rv_after)} moved={len(r_moved)} "
    f"world_deltas={world_deltas} "
    f"all_world_y_plus_grid={bool(world_deltas) and all(abs(d[1] - GRID) < 1e-3 for d in world_deltas)}")
screenshot("r8b-C-rotated")
log("=== R8B RE-RUN END ===")
