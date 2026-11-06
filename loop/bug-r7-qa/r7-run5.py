#!/usr/bin/env python3
"""R7 master: rebuild the L brush (leg4 logic) then run the nudge leg (leg5).
Keeps the product bits in-process, so a stale entity id cannot leak between
runs. Screenshots go to the fixture-relative r7qa-shots/ dir (the BRP
screenshot method refuses absolute paths) and are copied back to loop/."""
import json, re, subprocess, sys, time

PORT = 15703
OUT = "/Users/linbo.zhang/workspace/jackdaw/loop/bug-r7-qa"
SHOTDIR = "r7qa-shots"  # fixture-relative

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
    after = tree_entities()
    new_bits = [b for b in after if b not in before]
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
    log(f"  moved {axis}x{steps} -> {t} {'OK' if ok else 'MISMATCH expect ' + str(expect)}")
    return ok

def screenshot(name, kind="viewport"):
    r = brp("jackdaw/screenshot", {"kind": kind, "path": f"{SHOTDIR}/{name}.png"})
    archive(f"r7-shot-{name}", r)
    time.sleep(1.5)
    src = f"/Users/linbo.zhang/workspace/jackdaw/tests/fixtures/bsn_game/{SHOTDIR}/{name}.png"
    subprocess.run(["cp", src, f"{OUT}/{name}.png"], capture_output=True)
    return r

log("=== R7 MASTER (rebuild + nudge leg) BEGIN ===")

# 0) clean slate
op("brush.exit_edit_mode")
for i in range(14):
    if not tree_entities():
        break
    op("history.undo")
    time.sleep(1)
# any despawned-but-alive leftovers cannot be undone (subtract's spawn/despawn
# is not an undo entry) — respawn is on a fresh boot instead if this fails
ents = tree_entities()
log(f"scene after clean: {ents}")
if ents:
    log("MASTER_FAIL: scene not empty; a reboot is required")
    sys.exit(1)

# 1) build the L brush
bits_a = add_cube("A")
bits_b = add_cube("B")
ok = nudge_to("x", 2, bits_b, (0.5, 0.0, 0.0)) \
     and nudge_to("y", 2, bits_b, (0.5, 0.5, 0.0)) \
     and nudge_to("z", 2, bits_b, (0.5, 0.5, 0.5))
bits_c = add_cube("C")
ok = ok and nudge_to("x", 40, bits_c, (10.0, 0.0, 0.0))
if not ok:
    log("MASTER_FAIL: layout nudges mismatched")
    sys.exit(1)

h0 = brp("jackdaw/history", {})
archive("r7-master-history-pre-subtract", h0)
brp("jackdaw/selection.set", {"entities": [bits_b, bits_c]})
time.sleep(1)
r = op("brush.csg_subtract")
log(f"subtract: {json.dumps(r)[:120]}")
time.sleep(2); wait_idle(180); time.sleep(2)

ents = tree_entities()
product_bits = None
for bits, name in ents.items():
    bsn = entity_bsn(bits)
    faces, verts = brush_shape(bsn)
    if faces != 6:
        product_bits = bits
        log(f"product: {bits} faces={faces} verts={verts} t={bsn_translation(bsn)}")
if product_bits is None:
    log("MASTER_FAIL: no concave product found")
    sys.exit(1)

bsn0 = entity_bsn(product_bits)
faces0, verts0 = brush_shape(bsn0)
verts_before = vert_positions(bsn0)
archive("r7-master-brush-baseline", {"bits": product_bits, "faces": faces0, "verts": verts0,
                                     "verts_pos": verts_before})

# 2) select the product, face mode, click its face at the window centre
brp("jackdaw/selection.set", {"entities": [product_bits]})
time.sleep(1)
r = op("edit_mode.face")
time.sleep(2); wait_idle(60); time.sleep(2)
screenshot("r7-master-before-click")

for attempt, xy in enumerate([(480.0, 270.0), (480.0, 300.0), (500.0, 250.0)], 1):
    op("input.pointer", {"x": xy[0], "y": xy[1], "action": "click", "button": "primary"})
    time.sleep(2); wait_idle(60); time.sleep(2)
    # how do we know a face got selected? The nudge below is the probe; but a
    # quicker check: undo_len should NOT change on the click itself. Instead,
    # just take the screenshot and go on — the PageUp result is the assertion.
    log(f"click attempt {attempt} at {xy} done")
    break  # first attempt; coordinates refined after seeing the screenshot

h_pre = brp("jackdaw/history", {})
archive("r7-master-history-pre-nudge", h_pre)
log(f"history pre-nudge: undo_len={h_pre['result']['undo_len']} top={h_pre['result']['top']}")

# 3) PageUp through the real keybind
r = op("input.key", {"key": "PageUp", "action": "tap"})
time.sleep(2); wait_idle(60); time.sleep(2)

h_post = brp("jackdaw/history", {})
archive("r7-master-history-post-nudge", h_post)
log(f"history post-nudge: undo_len={h_post['result']['undo_len']} top={h_post['result']['top']} "
    f"delta={h_post['result']['undo_len'] - h_pre['result']['undo_len']}")

bsn1 = entity_bsn(product_bits)
faces1, verts1 = brush_shape(bsn1)
verts_after = vert_positions(bsn1)
moved = sum(1 for a, b in zip(verts_before, verts_after) if any(abs(x - y) > 1e-5 for x, y in zip(a, b)))
lifted = [b for a, b in zip(verts_before, verts_after)
          if abs((b[1] - a[1]) - 0.25) < 1e-4]
log(f"ASSERT1 shape: faces {faces0}->{faces1} verts {verts0}->{verts1} moved_verts={moved} lifted_by_grid={len(lifted)}")
screenshot("r7-master-after-nudge")

# 4) undo restores exactly
op("history.undo")
time.sleep(2); wait_idle(60); time.sleep(2)
bsn_u = entity_bsn(product_bits)
faces_u, verts_u = brush_shape(bsn_u)
verts_undo = vert_positions(bsn_u)
log(f"ASSERT2 after undo: faces={faces_u} verts={verts_u} verts_identical={verts_undo == verts_before} "
    f"undo_len={brp('jackdaw/history', {})['result']['undo_len']}")
op("brush.exit_edit_mode")
log("=== R7 MASTER END ===")
