import json, sys
d = json.load(open(sys.argv[1]))
rows = []
def walk(o):
    if isinstance(o, dict):
        if o.get("kind") == "text":
            rows.append((o.get("text", ""), o.get("rect") or [0, 0, 0, 0], o.get("entity")))
        for v in o.values():
            walk(v)
    elif isinstance(o, list):
        for i in o:
            walk(i)
walk(d)
head = None
for t, r, e in rows:
    if t == "AudioPlayer<AudioSource>" and r[2] > 0:
        head = r
        break
for t, r, e in rows:
    if t == chr(0xE2E5) and r[2] > 0 and head is not None and abs(r[1] - head[1]) < 30:
        print(e)
        break
