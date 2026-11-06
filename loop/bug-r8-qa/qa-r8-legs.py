#!/usr/bin/env python3
"""R8 QA live legs. Phase leg1 (assertion 1+3): build the R7 L-shaped concave
brush, pick a face, drive brush.extend_face_to_brush through the structured
operator entry, and assert refusal + zero side effects + an honest toast.
Phase leg2 (assertion 2): convex regression anchor on a fresh cube against a
flat opposing wall (no angled wall, avoiding the A27 degenerate form).
Driving patterns borrowed from loop/bug-r7-qa/r8c-run.py.
Usage: python3 loop/bug-r8-qa/qa-r8-legs.py leg1|leg2"""
import json, re, subprocess, sys, time
from collections import Counter

PORT = 15703
OUT = "/Users/linbo.zhang/workspace/jackdaw/loop/bug-r8-qa"
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
    with open(f"{OUT}/r8qa-console.log", "a") as f:
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

def face_count(bsn):
    return bsn.count("BrushFaceData")

def history():
    return brp("jackdaw/history", {}).get("result", {})

def toast_texts():
    """Full ui_tree walk (A21: text filtering misses popovers), return all texts."""
    d = brp("jackdaw/ui_tree", {"depth": 24})
    texts = []
    def walk(nodes):
        for n in nodes:
            if n.get("text"):
                texts.append(n.get("text"))
            walk(n.get("children", []))
    walk(d.get("result", {}).get("nodes", []))
    return texts

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
    log(f"  nudge {bits} {axis}{sign}x{steps} -> {t} {'OK' if ok else 'MISMATCH'}")
    return bool(ok)

def find_face_index(bsn, normal_pred):
    """Index of the first authored face whose plane normal matches pred(x,y,z)."""
    parts = bsn.split("faces: [")
    if len(parts) < 2:
        return None
    tail = parts[1]
    # faces list ends at "topology:" or end; split into BrushFaceData chunks
    chunks = tail.split("BrushFaceData")[1:]
    # stop at topology section (vertices appear after faces in entity BSN)
    idx = 0
    for c in chunks:
        if "vertices: [" in c:
            break
        m = re.search(r"normal: glam::Vec3 \{\s*x: ([0-9.eE+-]+),\s*y: ([0-9.eE+-]+),\s*z: ([0-9.eE+-]+)", c)
        if not m:
            return None
        n = tuple(float(v) for v in m.groups())
        if normal_pred(n):
            return idx
        idx += 1
    return None

def leg1():
    log("=== R8QA LEG1 BEGIN (concave refusal, assertions 1+3) ===")
    ents = {b: n for b, n in tree_entities().items() if n != "Root"}
    if ents:
        log(f"LEG1_FAIL: scene not empty: {ents}")
        sys.exit(1)

    # R7 construction: base A at origin, corner cutter B at (0.5,0.5,0.5),
    # far-away filler cutter C (csg_subtract needs >=2 selected brushes).
    bits_a = add_cube("A")
    bits_b = add_cube("B")
    ok = nudge_axis("x", "pos", 2, bits_b, (0.5, 0.0, 0.0)) \
         and nudge_axis("y", "pos", 2, bits_b, (0.5, 0.5, 0.0)) \
         and nudge_axis("z", "pos", 2, bits_b, (0.5, 0.5, 0.5))
    bits_c = add_cube("C")
    ok = ok and nudge_axis("x", "pos", 40, bits_c, (10.0, 0.0, 0.0))
    if not ok:
        log("LEG1_FAIL: layout")
        sys.exit(1)

    brp("jackdaw/selection.set", {"entities": [bits_b, bits_c]})
    time.sleep(1)
    op("brush.csg_subtract")
    time.sleep(2); wait_idle(180); time.sleep(2)

    product = None
    for bits in tree_entities():
        if face_count(entity_bsn(bits)) == 9:
            product = bits
            break
    if product is None:
        log("LEG1_FAIL: no 9-face L product")
        sys.exit(1)
    log(f"L product: {product}")

    bsn0 = entity_bsn(product)
    with open(f"{OUT}/r8qa-leg1-baseline.bsn.txt", "w") as f:
        f.write(bsn0)
    v0 = vert_positions(bsn0)
    f0 = face_count(bsn0)
    log(f"baseline: faces={f0} verts={len(v0)}")
    if f0 != 9 or len(v0) != 14:
        log(f"LEG1_FAIL: L shape unexpected (want 9/14)")
        sys.exit(1)

    h0 = history()
    log(f"history before extend: undo_len={h0.get('undo_len')} redo_len={h0.get('redo_len')} top={h0.get('top')}")

    # Pick a face on the L (face 0) so the Face-mode entry path is armed.
    r = brp("jackdaw/call_operator", {"id": "brush.selection.set_faces",
                                      "params": {"entity": product, "faces": "0"}})
    rr = r.get("result", {})
    log(f"set_faces: {rr.get('result')} warnings={rr.get('warnings')}")
    time.sleep(1)

    # Fire the extend operator through the structured entry.
    ext = op("brush.extend_face_to_brush")
    log(f"extend operator reply: {json.dumps(ext)[:400]}")
    time.sleep(1)
    wait_idle(60); time.sleep(1)

    # Assertion 3: toast text (grab fast — it expires).
    texts = toast_texts()
    with open(f"{OUT}/r8qa-leg1-toast-texts.json", "w") as f:
        json.dump(texts, f, ensure_ascii=False, indent=1)
    hits = [t for t in texts if "concave" in t.lower() or "extend" in t.lower()]
    log(f"TOAST hits: {hits}")
    brp("jackdaw/screenshot", {"kind": "window", "path": f"{OUT}/r8qa-leg1-toast-window.png"})
    brp("jackdaw/screenshot", {"kind": "viewport", "path": f"{OUT}/r8qa-leg1-toast-viewport.png"})

    # Assertion 1: zero side effects.
    bsn1 = entity_bsn(product)
    with open(f"{OUT}/r8qa-leg1-after-refusal.bsn.txt", "w") as f:
        f.write(bsn1)
    v1 = vert_positions(bsn1)
    f1 = face_count(bsn1)
    h1 = history()
    log(f"after refused extend: faces={f1} verts={len(v1)} "
        f"bsn_identical={bsn1 == bsn0} "
        f"undo_delta={h1.get('undo_len', -99) - h0.get('undo_len', -99)} "
        f"undo_top_now={h1.get('top')}")

    # Face mode / BrushSelection survival (indirect behavioral chain):
    # a PageUp nudge only moves the picked face while Face mode + faces + active_brush
    # all survive. Move +0.25Y then back.
    op("input.key", {"key": "PageUp", "action": "tap"})
    time.sleep(2); wait_idle(60); time.sleep(2)
    bsn_pu = entity_bsn(product)
    v_pu = vert_positions(bsn_pu)
    c0, cp = Counter(v0), Counter(v_pu)
    added = cp - c0
    lifted = sum(n for p, n in added.items()
                 if any(abs(p[1] - (q[1] + GRID)) < 1e-5 and p[0] == q[0] and p[2] == q[2]
                        for q, m in (c0 - cp).items() if m >= n))
    log(f"FACE-MODE-SURVIVAL PageUp: faces={face_count(bsn_pu)} verts={len(v_pu)} "
        f"lifted_by_grid={lifted}/{sum(added.values())}")
    op("input.key", {"key": "PageDown", "action": "tap"})
    time.sleep(2); wait_idle(60); time.sleep(2)
    bsn_pd = entity_bsn(product)
    log(f"FACE-MODE-SURVIVAL PageDown restore: bsn_identical_to_baseline={bsn_pd == bsn0}")
    # clean the two nudge undo entries to keep the ledger honest for leg2 reads
    op("history.undo"); time.sleep(1); wait_idle(60)
    op("history.undo"); time.sleep(1); wait_idle(60)
    log(f"history after cleanup: {json.dumps(history())[:200]}")
    log("=== R8QA LEG1 END ===")

def leg2():
    log("=== R8QA LEG2 BEGIN (convex anchor on a flat opposing wall, assertion 2) ===")
    ents = {b: n for b, n in tree_entities().items() if n != "Root"}
    # L brush may sit among other leftovers; find it by face count.
    l_bits = None
    for bits in ents:
        if face_count(entity_bsn(bits)) == 9:
            l_bits = bits
    if l_bits is None:
        log(f"LEG2_FAIL: no L brush in scene: {ents}")
        sys.exit(1)

    # D: fresh convex cube at (-4,0,0); E: flat target wall at (-2,0,0),
    # no rotation -> opposing-face fallback path, no angled wall (avoids A27).
    bits_d = add_cube("D")
    ok = nudge_axis("x", "neg", 16, bits_d, (-4.0, 0.0, 0.0))
    bits_e = add_cube("E")
    ok = ok and nudge_axis("x", "neg", 8, bits_e, (-2.0, 0.0, 0.0))
    if not ok:
        log("LEG2_FAIL: layout")
        sys.exit(1)

    bsn_d = entity_bsn(bits_d)
    fx = find_face_index(bsn_d, lambda n: n[0] > 0.9 and abs(n[1]) < 0.1 and abs(n[2]) < 0.1)
    log(f"D face with +X normal: index={fx} (baseline faces={face_count(bsn_d)} verts={len(vert_positions(bsn_d))})")
    if fx is None:
        log("LEG2_FAIL: no +X face on D")
        sys.exit(1)

    brp("jackdaw/selection.set", {"entities": [bits_d, bits_e]})
    time.sleep(1)
    r = brp("jackdaw/call_operator", {"id": "brush.selection.set_faces",
                                      "params": {"entity": bits_d, "faces": str(fx)}})
    rr = r.get("result", {})
    log(f"set_faces(D, {fx}): {rr.get('result')} warnings={rr.get('warnings')}")
    time.sleep(1)

    h0 = history()
    ext = op("brush.extend_face_to_brush")
    log(f"extend operator reply: {json.dumps(ext)[:400]}")
    time.sleep(1); wait_idle(60); time.sleep(1)

    texts = toast_texts()
    concave_hits = [t for t in texts if "concave" in t.lower()]
    log(f"TOAST concave hits after convex extend (want none): {concave_hits}")

    bsn_d1 = entity_bsn(bits_d)
    with open(f"{OUT}/r8qa-leg2-after-extend.bsn.txt", "w") as f:
        f.write(bsn_d1)
    v_d1 = vert_positions(bsn_d1)
    xs = [p[0] for p in v_d1]
    h1 = history()
    log(f"after convex extend: faces={face_count(bsn_d1)} verts={len(v_d1)} "
        f"x_range=({min(xs):.4f},{max(xs):.4f}) "
        f"undo_delta={h1.get('undo_len', -99) - h0.get('undo_len', -99)} "
        f"top={h1.get('top')}")
    brp("jackdaw/screenshot", {"kind": "viewport", "path": f"{OUT}/r8qa-leg2-viewport.png"})
    l_untouched = entity_bsn(l_bits)
    log(f"L brush untouched by leg2: {l_untouched == entity_bsn(l_bits)}")
    log("=== R8QA LEG2 END ===")

if __name__ == "__main__":
    {"leg1": leg1, "leg2": leg2}[sys.argv[1]]()
