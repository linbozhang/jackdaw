import json, sys
d = json.load(open(sys.argv[1]))
best = None
def walk(o):
    global best
    if isinstance(o, dict):
        if o.get("kind") == "text" and o.get("text") == "Pick AudioSource" \
                and (o.get("rect") or [0, 0, 0, 0])[2] > 0:
            best = o["rect"]
        for v in o.values():
            walk(v)
    elif isinstance(o, list):
        for i in o:
            walk(i)
walk(d)
print(best[1] if best else "")
