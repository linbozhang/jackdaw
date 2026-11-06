#!/usr/bin/env python3
"""R8 QA leg1b — clean-room rerun with a same-session control/experiment pair.

Sequence on a fresh editor: build the R7 L-shaped concave brush, pick a face,
  CONTROL : set_faces -> PageUp (no extend) -> BSN full before/after archived
  RESTORE : PageDown
  EXPERIMENT: set_faces -> brush.extend_face_to_brush (must refuse)
              -> instant EditorToast world.query + ui_tree + screenshots
              -> zero-side-effect assertions -> PageUp -> BSN archived -> PageDown
The only difference between the two PageUp reads is the refused extend call in
between, so any difference in what PageUp moves (face vertices vs entity
translation vs nothing) pins down whether the refusal cleared the Face mode.
"""
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

POS_RE = re.compile(
    r"position: glam::Vec3 \{\s*x: ([0-9.eE+-]+),\s*y: ([0-9.eE+-]+),\s*z: ([0-9.eE+-]+)", re.S)
TRANS_RE = re.compile(r"translation: glam::Vec3A? \{ x: ([0-9.eE+-]+), y: ([0-9.eE+-]+), z: ([0-9.eE+-]+)")

def verts(bsn):
    parts = bsn.split("vertices: [")
    if len(parts) < 2:
        return []
    tail = parts[1].split("]", 1)[0]
    return [tuple(round(float(v), 6) for v in m) for m in POS_RE.findall(tail)]

def trans(bsn):
    m = TRANS_RE.findall(bsn)
    return tuple(round(float(v), 6) for v in m[0]) if m else None

def history():
    return brp("jackdaw/history", {}).get("result", {})

def pageup_report(tag, before, after):
    t0, t1 = trans(before), trans(after)
    v0, v1 = Counter(verts(before)), Counter(verts(after))
    added, removed = v1 - v0, v0 - v1
    lifted = sum(n for p, n in added.items()
                 if any(abs(p[1] - (q[1] + GRID)) < 1e-5 and p[0] == q[0] and p[2] == q[2]
                        for q, m2 in removed.items() if m2 >= n))
    log(f"{tag}: translation {t0}->{t1} verts_removed={sum(removed.values())} "
        f"verts_added={sum(added.values())} lifted_by_grid={lifted}/{sum(added.values())} "
        f"faces={after.count('BrushFaceData')}")
    return {"translation_before": t0, "translation_after": t1,
            "verts_removed": sum(removed.values()), "verts_added": sum(added.values()),
            "lifted_by_grid": lifted}

def add_cube(tag):
    before = tree_entities()
    op("entity.add.cube")
    time.sleep(1); wait_idle(60); time.sleep(1)
    new_bits = [b for b in tree_entities() if b not in before]
    if len(new_bits) != 1:
        log(f"LEG1B_FAIL: add_cube {tag}")
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

log("=== R8QA LEG1B BEGIN (control/experiment same session) ===")

ents = {b: n for b, n in tree_entities().items() if n != "Root"}
if ents:
    log(f"LEG1B_FAIL: scene not empty: {ents}")
    sys.exit(1)

bits_a = add_cube("A")
bits_b = add_cube("B")
ok = nudge_axis("x", "pos", 2, bits_b, (0.5, 0.0, 0.0)) \
     and nudge_axis("y", "pos", 2, bits_b, (0.5, 0.5, 0.0)) \
     and nudge_axis("z", "pos", 2, bits_b, (0.5, 0.5, 0.5))
bits_c = add_cube("C")
ok = ok and nudge_axis("x", "pos", 40, bits_c, (10.0, 0.0, 0.0))
if not ok:
    log("LEG1B_FAIL: layout")
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
    log("LEG1B_FAIL: no 9-face L product")
    sys.exit(1)
log(f"L product: {product}")

bsn0 = entity_bsn(product)
with open(f"{OUT}/r8qa-leg1b-baseline.bsn.txt", "w") as f:
    f.write(bsn0)
v0 = verts(bsn0)
log(f"baseline: faces={bsn0.count('BrushFaceData')} verts={len(v0)} translation={trans(bsn0)}")
if bsn0.count("BrushFaceData") != 9 or len(v0) != 14:
    log("LEG1B_FAIL: L shape unexpected")
    sys.exit(1)

# ---- CONTROL: PageUp with no extend in between ----
r = brp("jackdaw/call_operator", {"id": "brush.selection.set_faces",
                                  "params": {"entity": product, "faces": "0"}})
log(f"CONTROL set_faces: {r.get('result', {}).get('result')} warnings={r.get('result', {}).get('warnings')}")
time.sleep(1)
h0 = history()
op("input.key", {"key": "PageUp", "action": "tap"})
time.sleep(2); wait_idle(60); time.sleep(2)
h1 = history()
bsn_ctrl = entity_bsn(product)
with open(f"{OUT}/r8qa-leg1b-control-after-pageup.bsn.txt", "w") as f:
    f.write(bsn_ctrl)
ctrl = pageup_report("CONTROL PageUp", bsn0, bsn_ctrl)
log(f"CONTROL undo entries pushed: {h1.get('undo_len', -99) - h0.get('undo_len', -99)} top={h1.get('top')}")
# restore via PageDown and verify byte-identity
op("input.key", {"key": "PageDown", "action": "tap"})
time.sleep(2); wait_idle(60); time.sleep(2)
bsn_ctrl_back = entity_bsn(product)
log(f"CONTROL PageDown restore: bsn_identical={bsn_ctrl_back == bsn0}")

# ---- EXPERIMENT: set_faces -> refused extend -> the same PageUp read ----
r = brp("jackdaw/call_operator", {"id": "brush.selection.set_faces",
                                  "params": {"entity": product, "faces": "0"}})
log(f"EXPERIMENT set_faces: {r.get('result', {}).get('result')}")
time.sleep(1)
h2 = history()
ext = op("brush.extend_face_to_brush")
log(f"extend operator reply: {json.dumps(ext)[:400]}")

# toast, grabbed instantly: BRP component query first, then ui_tree walk
TOAST_Q = {"data": {"components": []}, "filter": {"with": ["jackdaw_feathers::toast::EditorToast"]}}
toast_q = brp("world.query", TOAST_Q)
log(f"TOAST world.query instant: {json.dumps(toast_q)[:400]}")
time.sleep(0.3)
toast_q2 = brp("world.query", TOAST_Q)
log(f"TOAST world.query +0.3s: {json.dumps(toast_q2)[:400]}")
texts = []
def walk(nodes):
    for n in nodes:
        if n.get("text"):
            texts.append(n.get("text"))
        walk(n.get("children", []))
walk(brp("jackdaw/ui_tree", {"depth": 24}).get("result", {}).get("nodes", []))
with open(f"{OUT}/r8qa-leg1b-toast-texts.json", "w") as f:
    json.dump(texts, f, ensure_ascii=False, indent=1)
hits = [t for t in texts if "concave" in t.lower() or "extend" in t.lower() or "refus" in t.lower()]
log(f"TOAST ui_tree hits: {hits}")
brp("jackdaw/screenshot", {"kind": "window", "path": f"{OUT}/r8qa-leg1b-toast-window.png"})
brp("jackdaw/screenshot", {"kind": "viewport", "path": f"{OUT}/r8qa-leg1b-toast-viewport.png"})

bsn_exp = entity_bsn(product)
with open(f"{OUT}/r8qa-leg1b-after-refusal.bsn.txt", "w") as f:
    f.write(bsn_exp)
h3 = history()
log(f"after refused extend: bsn_identical={bsn_exp == bsn0} "
    f"faces={bsn_exp.count('BrushFaceData')} verts={len(verts(bsn_exp))} "
    f"undo_delta={h3.get('undo_len', -99) - h2.get('undo_len', -99)} top={h3.get('top')}")

op("input.key", {"key": "PageUp", "action": "tap"})
time.sleep(2); wait_idle(60); time.sleep(2)
bsn_exp_pu = entity_bsn(product)
with open(f"{OUT}/r8qa-leg1b-experiment-after-pageup.bsn.txt", "w") as f:
    f.write(bsn_exp_pu)
exp = pageup_report("EXPERIMENT PageUp", bsn0, bsn_exp_pu)
log(f"SURVIVAL VERDICT: control={json.dumps(ctrl)}")
log(f"SURVIVAL VERDICT: experiment={json.dumps(exp)}")
op("input.key", {"key": "PageDown", "action": "tap"})
time.sleep(2); wait_idle(60); time.sleep(2)
log(f"EXPERIMENT PageDown restore: bsn_identical={entity_bsn(product) == bsn0}")
log("=== R8QA LEG1B END ===")
