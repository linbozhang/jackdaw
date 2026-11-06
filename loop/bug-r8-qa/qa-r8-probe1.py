#!/usr/bin/env python3
"""R8 QA probe: after leg1, figure out (a) what PageUp actually moved
(translation vs vertices) on the L brush, (b) whether an EditorToast entity
exists in the ECS world (BRP world.query filter), (c)对照: set_faces then
PageUp WITHOUT the extend call — does the face lift (probe validity)."""
import json, re, subprocess, sys, time
from collections import Counter

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
    print(f"[{time.strftime('%H:%M:%S')}] {m}", flush=True)
    with open(f"{OUT}/r8qa-console.log", "a") as f:
        f.write(f"[{time.strftime('%H:%M:%S')}] {m}\n")

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

TRANS_RE = re.compile(r"translation: glam::Vec3A? \{ x: ([0-9.eE+-]+), y: ([0-9.eE+-]+), z: ([0-9.eE+-]+)")
POS_RE = re.compile(
    r"position: glam::Vec3 \{\s*x: ([0-9.eE+-]+),\s*y: ([0-9.eE+-]+),\s*z: ([0-9.eE+-]+)",
    re.S)

def verts(bsn):
    parts = bsn.split("vertices: [")
    if len(parts) < 2:
        return []
    tail = parts[1].split("]", 1)[0]
    return [tuple(round(float(v), 6) for v in m) for m in POS_RE.findall(tail)]

def trans(bsn):
    m = TRANS_RE.findall(bsn)
    return tuple(round(float(v), 6) for v in m[0]) if m else None

# (a) current state of the L brush: did PageUp/PageDown move translation?
ents = {n["entity"]: n.get("name") for n in brp("jackdaw/scene_tree", {})["result"]["tree"]}
log(f"probe: entities={ents}")
l_bits = None
for bits in ents:
    if ents[bits] != "Root" and len(verts(entity_bsn(bits))) == 14:
        l_bits = bits
        break
if l_bits is None:
    log("PROBE_FAIL: no 14-vert brush")
    sys.exit(1)
b = entity_bsn(l_bits)
log(f"probe (a): L bits={l_bits} translation={trans(b)} verts0={verts(b)[:2]}...")

# (b) EditorToast entities in the ECS world
q = brp("jackdaw/world.query", {"filter": {"with": ["jackdaw_feathers::toast::EditorToast"]}})
log(f"probe (b): EditorToast query -> {json.dumps(q)[:500]}")

# (c) control: set_faces on the L then PageUp WITHOUT extend — face should lift
r = brp("jackdaw/call_operator", {"id": "brush.selection.set_faces",
                                  "params": {"entity": l_bits, "faces": "0"}})
log(f"probe (c): set_faces -> {r.get('result', {}).get('result')}")
time.sleep(1)
b0 = entity_bsn(l_bits)
t0, v0 = trans(b0), verts(b0)
op("input.key", {"key": "PageUp", "action": "tap"})
time.sleep(2); wait_idle(60); time.sleep(2)
b1 = entity_bsn(l_bits)
t1, v1 = trans(b1), verts(b1)
c0, c1 = Counter(v0), Counter(v1)
added = c1 - c0
lifted = sum(n for p, n in added.items()
             if any(abs(p[1] - (q1[1] + 0.25)) < 1e-5 and p[0] == q1[0] and p[2] == q1[2]
                    for q1, m2 in (c0 - c1).items() if m2 >= n))
log(f"probe (c) NO-EXTEND control: translation {t0}->{t1} verts_moved={len(c0-c1)+len(added)} "
    f"lifted_by_grid={lifted}/{sum(added.values())} faces={b1.count('BrushFaceData')}")
# restore
op("input.key", {"key": "PageDown", "action": "tap"})
time.sleep(2); wait_idle(60); time.sleep(2)
b2 = entity_bsn(l_bits)
log(f"probe (c) restore: bsn_identical={b2 == b0}")
log("PROBE END")
