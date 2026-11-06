#!/usr/bin/env python3
"""R8 QA leg1c: the extend Face-mode branch needs targets = Selection.entities
minus primary to be non-empty. leg1b relied on whatever the csg_subtract left
in Selection; this leg sets it explicitly before the extend call.
  selection.set([L, C]) -> set_faces(L, "0") -> extend -> warn/toast checks.
The L built in leg1b is reused as-is (byte-identical baseline already on file).
"""
import json, re, subprocess, sys, time

PORT = 15703
OUT = "/Users/linbo.zhang/workspace/jackdaw/loop/bug-r8-qa"

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

def wait_idle(limit=90):
    d = time.time() + limit
    while time.time() < d:
        if brp("jackdaw/wait", {"until": "idle"}).get("result", {}).get("idle") is True:
            return True
        time.sleep(1)
    return False

def entity_bsn(bits):
    return brp("jackdaw/entity", {"entity": bits}).get("result", {}).get("bsn", "")

POS_RE = re.compile(
    r"position: glam::Vec3 \{\s*x: ([0-9.eE+-]+),\s*y: ([0-9.eE+-]+),\s*z: ([0-9.eE+-]+)", re.S)

def verts(bsn):
    parts = bsn.split("vertices: [")
    if len(parts) < 2:
        return []
    tail = parts[1].split("]", 1)[0]
    return [tuple(round(float(v), 6) for v in m) for m in POS_RE.findall(tail)]

def history():
    return brp("jackdaw/history", {}).get("result", {})

log("=== R8QA LEG1C BEGIN (explicit targets, reach the guard) ===")
ents = {n["entity"]: n.get("name") for n in brp("jackdaw/scene_tree", {})["result"]["tree"]}
log(f"scene: {ents}")
l_bits, c_bits = None, None
for bits, name in ents.items():
    if name == "Root":
        continue
    b = entity_bsn(bits)
    if b.count("BrushFaceData") == 9:
        l_bits = bits
    elif (10.0, 0.0, 0.0) in re.findall(r"translation: glam::Vec3A? \{ x: ([0-9.eE+-]+), y: ([0-9.eE+-]+), z: ([0-9.eE+-]+)", b) or "x: 10" in b:
        c_bits = bits
if l_bits is None or c_bits is None:
    log(f"LEG1C_FAIL: L={l_bits} C={c_bits}")
    sys.exit(1)
bsn0 = entity_bsn(l_bits)
log(f"L={l_bits} faces={bsn0.count('BrushFaceData')} verts={len(verts(bsn0))}; C={c_bits}")

brp("jackdaw/selection.set", {"entities": [l_bits, c_bits]})
time.sleep(1)
r = brp("jackdaw/call_operator", {"id": "brush.selection.set_faces",
                                  "params": {"entity": l_bits, "faces": "0"}})
log(f"set_faces: {r.get('result', {}).get('result')} warnings={r.get('result', {}).get('warnings')}")
time.sleep(1)

h0 = history()
ext = op("brush.extend_face_to_brush")
log(f"extend reply: {json.dumps(ext)[:300]}")
TOAST_Q = {"data": {"components": []}, "filter": {"with": ["jackdaw_feathers::toast::EditorToast"]}}
tq = brp("world.query", TOAST_Q)
log(f"TOAST instant: {json.dumps(tq)[:300]}")
time.sleep(0.3)
log(f"TOAST +0.3s: {json.dumps(brp('world.query', TOAST_Q))[:300]}")

bsn1 = entity_bsn(l_bits)
h1 = history()
log(f"after extend: bsn_identical={bsn1 == bsn0} faces={bsn1.count('BrushFaceData')} "
    f"verts={len(verts(bsn1))} undo_delta={h1.get('undo_len', -99) - h0.get('undo_len', -99)} "
    f"top={h1.get('top')}")

texts = []
def walk(nodes):
    for n in nodes:
        if n.get("text"):
            texts.append(n.get("text"))
        walk(n.get("children", []))
walk(brp("jackdaw/ui_tree", {"depth": 24}).get("result", {}).get("nodes", []))
hits = [t for t in texts if "concave" in t.lower() or "extend" in t.lower() or "refus" in t.lower()]
log(f"TOAST ui_tree hits: {hits}")
brp("jackdaw/screenshot", {"kind": "window", "path": f"{OUT}/r8qa-leg1c-toast-window.png"})
with open(f"{OUT}/r8qa-leg1c-toast-texts.json", "w") as f:
    json.dump(texts, f, ensure_ascii=False, indent=1)
log("=== R8QA LEG1C END ===")
