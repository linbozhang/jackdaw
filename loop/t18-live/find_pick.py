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
rowy = None
for t, r, e in rows:
    if t == "blip.wav" and r[2] > 0:
        rowy = r[1]
for t, r, e in rows:
    if t == chr(0xE247) and r[2] > 60 and rowy is not None and -60 < (r[1] - rowy) < 40:
        print(e)
        break
