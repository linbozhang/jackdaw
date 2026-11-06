#!/usr/bin/env python3
"""R8 live re-run: the R7 live leg, unblocked by the brush.selection.set_faces
QA tool (main eaaa952b). Legs:
  A) rebuild the L brush (subtract), set_faces pick one face, PageUp via the
     real keybind, assert shape preserved (9 faces / 14 verts), moved ring,
     exactly one undo entry, undo restores the BSN bit-exactly;
  B) convex regression anchor: fresh cube, set_faces, PageUp, face/vert counts
     unchanged, the four moved verts share one 0.25-length delta;
  C) rotated-brush world-Y leg: rotate the anchor cube 90 degrees, set_faces,
     PageUp, the moved verts' world-space delta is (0, +0.25, 0)."""
import json, math, re, subprocess, sys, time

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

def archive(name, obj):
    with open(f"{OUT}/{name}.json", "w") as f:
        json.dump(obj, f, indent=1)

def op(op_id, params=None):
    r = brp("jackdaw/call_operator", {"id": op_id, "params": params or {}})
    archive(f"r8-op-{op_id.replace('.', '_')}", r)
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

def vert_positions(bsn):
    parts = bsn.split("vertices: [")
    if len(parts) < 2:
        return []
    tail = parts[1].split("]", 1)[0]
    return [tuple(float(v) for v in t) for t in
            re.findall(r"position: glam::Vec3 \{ x: ([0-9.eE+-]+), y: ([0-9.eE+-]+), z: ([0-9.eE+-]+)", tail)]

def brush_shape(bsn):
    return bsn.count("BrushFaceData"), len(re.findall(r"position: glam::Vec3 \{", bsn))

def bsn_translation_rotation(bsn):
    m = re.findall(r"translation: glam::Vec3A? \{ x: ([0-9.eE+-]+), y: ([0-9.eE+-]+), z: ([0-9.eE+-]+)", bsn)
    t = [tuple(float(v) for v in x) for x in m[:1]]
    q = re.findall(r"rotation: glam::Quat \{ x: ([0-9.eE+-]+), y: ([0-9.eE+-]+), z: ([0-9.eE+-]+), w: ([0-9.eE+-]+)", bsn)
    rot = tuple(float(v) for v in q[0]) if q else (0.0, 0.0, 0.0, 1.0)
    return (t[0] if t else (0.0, 0.0, 0.0)), rot

def quat_rotate(q, v):
    x, y, z, w = q
    uv = (y * v[2] - z * v[1], z * v[0] - x * v[2], x * v[1] - y * v[0])
    uuv = (y * uuv_z(uv) - z * uuv_y(uv), z * uuv_x(uv) - x * uuv_z(uv), x * uuv_y(uv) - y * uuv_x(uv))
    return (v[0] + 2 * (w * uv[0] + uuv[0]),
            v[1] + 2 * (w * uv[1] + uuv[1]),
            v[2] + 2 * (w * uv[2] + uuv[2]))

def uuv_x(u): return u[0]
def uuv_y(u): return u[1]
def uuv_z(u): return u[2]

def screenshot(name, kind="viewport"):
    r = brp("jackdaw/screenshot", {"kind": kind, "path": f"{SHOTDIR}/{name}.png"})
    archive(f"r8-shot-{name}", r)
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

def nudge_to(axis, steps, bits, expect):
    brp("jackdaw/selection.set", {"entities": [bits]})
    time.sleep(0.5)
    for _ in range(steps):
        op(f"transform.nudge_{axis}_pos")
    time.sleep(1); wait_idle(60)
    (t, _) = bsn_translation_rotation(entity_bsn(bits))
    ok = all(abs(a - b) < 1e-4 for a, b in zip(t, expect))
    log(f"  {axis}x{steps} -> {t} {'OK' if ok else 'MISMATCH'}")
    return ok

log("=== R8 LIVE RE-RUN BEGIN ===")

# ---- leg A: the L brush, structured face pick, PageUp ----
ents = {b: n for b, n in tree_entities().items() if n != "Root"}
if ents:
    log(f"RUN8_FAIL: scene not empty at start: {ents}")
    sys.exit(1)

bits_a = add_cube("A")
bits_b = add_cube("B")
ok = nudge_to("x", 2, bits_b, (0.5, 0.0, 0.0)) \
     and nudge_to("y", 2, bits_b, (0.5, 0.5, 0.0)) \
     and nudge_to("z", 2, bits_b, (0.5, 0.5, 0.5))
bits_c = add_cube("C")
ok = ok and nudge_to("x", 40, bits_c, (10.0, 0.0, 0.0))
if not ok:
    log("RUN8_FAIL: layout mismatch")
    sys.exit(1)

brp("jackdaw/selection.set", {"entities": [bits_b, bits_c]})
time.sleep(1)
r = op("brush.csg_subtract")
log(f"subtract: {r['result']['result']}")
time.sleep(2); wait_idle(180); time.sleep(2)

product = None
for bits in tree_entities():
    f, v = brush_shape(entity_bsn(bits))
    if f == 9:
        product = bits
        break
if product is None:
    log("RUN8_FAIL: no concave product")
    sys.exit(1)

bsn0 = entity_bsn(product)
faces0, verts0 = brush_shape(bsn0)
v_before = vert_positions(bsn0)
log(f"LEG-A baseline: entity={product} faces={faces0} verts={verts0}")

# the structured face pick: face 0 of the L brush
r = brp("jackdaw/call_operator", {"id": "brush.selection.set_faces",
                                  "params": {"entity": product, "faces": "0"}})
archive("r8-set-faces", r)
picked = r.get("result", {}).get("result")
warn = r.get("result", {}).get("warnings")
log(f"set_faces reply: result={picked} warnings={warn}")
em = brp("world.get_resources", {"resource": "jackdaw::brush::EditMode"})["result"]["value"]
log(f"EditMode after set_faces: {em}")
if picked != "finished":
    log("RUN8_FAIL: set_faces refused")
    sys.exit(1)

h_pre = brp("jackdaw/history", {})
archive("r8-history-pre", h_pre)
log(f"history pre-nudge: undo_len={h_pre['result']['undo_len']} top={h_pre['result']['top']}")

r = op("input.key", {"key": "PageUp", "action": "tap"})
log(f"PageUp reply: {r['result']['result']}")
time.sleep(2); wait_idle(60); time.sleep(2)

h_post = brp("jackdaw/history", {})
archive("r8-history-post", h_post)
delta = h_post["result"]["undo_len"] - h_pre["result"]["undo_len"]
log(f"history post-nudge: undo_len={h_post['result']['undo_len']} top={h_post['result']['top']} delta={delta}")

bsn1 = entity_bsn(product)
faces1, verts1 = brush_shape(bsn1)
v_after = vert_positions(bsn1)
moved_idx = [i for i, (a, b) in enumerate(zip(v_before, v_after))
             if any(abs(x - y) > 1e-5 for x, y in zip(a, b))]
deltas = [tuple(b[i] - a[i] for i in range(3)) for a, b in
          zip((v_before[i] for i in moved_idx), (v_after[i] for i in moved_idx))]
same_delta = len({tuple(round(d, 4) for d in dl) for dl in deltas}) <= 1
log(f"ASSERT-A1 shape: faces {faces0}->{faces1} verts {verts0}->{verts1} "
    f"moved_verts={len(moved_idx)} deltas={deltas[:2]} uniform={same_delta}")
screenshot("r8-A-after-nudge")

# undo restores exactly
op("history.undo")
time.sleep(2); wait_idle(60); time.sleep(2)
bsn_u = entity_bsn(product)
faces_u, verts_u = brush_shape(bsn_u)
v_undo = vert_positions(bsn_u)
ident = v_undo == v_before
h_u = brp("jackdaw/history", {})
log(f"ASSERT-A2 undo-restore: faces={faces_u} verts={verts_u} verts_bit_identical={ident} "
    f"undo_len={h_u['result']['undo_len']} (pre={h_pre['result']['undo_len']})")
screenshot("r8-A-after-undo")

# ---- leg B: convex regression anchor ----
op("brush.exit_edit_mode")
time.sleep(1)
bits_d = add_cube("D")
r = brp("jackdaw/call_operator", {"id": "brush.selection.set_faces",
                                  "params": {"entity": bits_d, "faces": "0"}})
log(f"anchor set_faces: {r.get('result', {}).get('result')} warnings={r.get('result', {}).get('warnings')}")
time.sleep(1)
bsn_d0 = entity_bsn(bits_d)
df0, dv0 = brush_shape(bsn_d0)
dv_before = vert_positions(bsn_d0)
h_b = brp("jackdaw/history", {})
op("input.key", {"key": "PageUp", "action": "tap"})
time.sleep(2); wait_idle(60); time.sleep(2)
bsn_d1 = entity_bsn(bits_d)
df1, dv1 = brush_shape(bsn_d1)
dv_after = vert_positions(bsn_d1)
d_moved = [i for i, (a, b) in enumerate(zip(dv_before, dv_after))
           if any(abs(x - y) > 1e-5 for x, y in zip(a, b))]
d_deltas = {tuple(round(b[i] - a[i], 4) for i in range(3)) for a, b in
            zip((dv_before[i] for i in d_moved), (dv_after[i] for i in d_moved))}
log(f"ASSERT-B anchor: faces {df0}->{df1} verts {dv0}->{dv1} moved={len(d_moved)} "
    f"delta_set={d_deltas} undo_len={brp('jackdaw/history', {})['result']['undo_len'] - h_b['result']['undo_len']}")
screenshot("r8-B-anchor-nudged")

# ---- leg C: rotated brush nudges along WORLD Y ----
op("brush.exit_edit_mode")
time.sleep(1)
r = op("transform.rotate_90_pitch_ccw")
time.sleep(1); wait_idle(60)
(t_d, q_d) = bsn_translation_rotation(entity_bsn(bits_d))
log(f"anchor rotation after rotate_90_pitch_ccw: quat={q_d} translation={t_d}")
r = brp("jackdaw/call_operator", {"id": "brush.selection.set_faces",
                                  "params": {"entity": bits_d, "faces": "0"}})
log(f"rotated set_faces: {r.get('result', {}).get('result')}")
time.sleep(1)
bsn_r0 = entity_bsn(bits_d)
rf0, rv0 = brush_shape(bsn_r0)
rv_before = vert_positions(bsn_r0)
(t_r, q_r) = bsn_translation_rotation(bsn_r0)
log(f"rotated baseline: faces={rf0} verts={rv0} quat={q_r}")
op("input.key", {"key": "PageUp", "action": "tap"})
time.sleep(2); wait_idle(60); time.sleep(2)
bsn_r1 = entity_bsn(bits_d)
rf1, rv1 = brush_shape(bsn_r1)
rv_after = vert_positions(bsn_r1)
r_moved = [i for i, (a, b) in enumerate(zip(rv_before, rv_after))
           if any(abs(x - y) > 1e-5 for x, y in zip(a, b))]
world_deltas = []
for i in r_moved:
    ld = tuple(rv_after[i][k] - rv_before[i][k] for k in range(3))
    wd = quat_rotate(q_r, ld)
    world_deltas.append(tuple(round(v, 4) for v in wd))
world_set = set(world_deltas)
log(f"ASSERT-C rotated: faces {rf0}->{rf1} verts {rv0}->{rv1} moved={len(r_moved)} "
    f"world_deltas={world_deltas} all_world_y_grid={all(abs(d[1] - GRID) < 1e-3 for d in world_set)} "
    f"uniform={len(world_set) <= 1}")
screenshot("r8-C-rotated-nudged")

log("=== R8 LIVE RE-RUN END ===")
