#!/usr/bin/env python3
"""T15-T2 L5/M7 game-side driver: drives the graph rig in a running game
(BRP 15702) and records the state sequence. Run per channel with the game
already up:

    python3 parity_driver.py pie
Writes loop/t15-live/parity-<tag>.json (one JSON sample per line).
"""
import json
import sys
import time
import urllib.request

PORT = 15702
APLAYBACK = "jackdaw_animation_runtime::graph::AnimationGraphPlayback"
APARAMS = "jackdaw_animation_runtime::graph::AnimationParams"
OUT = "/Users/zhanglinbo/workspace/jackdaw/loop/t15-live"


def brp(method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(
        "http://127.0.0.1:%d/" % PORT, data=body, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def with_retry(method, params, tries=8):
    last = {}
    for _ in range(tries):
        try:
            last = brp(method, params)
        except Exception as exc:  # the flap surface is broad
            last = {"error": str(exc)}
        if "result" in last:
            return last["result"]
        time.sleep(2)
    return None


def rig_id():
    result = with_retry("world.query", {"data": {"components": ["bevy_ecs::name::Name"]}})
    for row in result or []:
        if row["components"]["bevy_ecs::name::Name"] == "Rig":
            return row["entity"]
    return None


def playback(eid):
    result = with_retry("world.get_components", {"entity": eid, "components": [APLAYBACK]})
    held = (result or {}).get("components", {}).get(APLAYBACK, {})
    return {
        "state": held.get("state", ""),
        "since": held.get("since_secs", 0),
        "transition": held.get("transition"),
    }


def sample(eid, label, seq):
    row = dict(label=label, **playback(eid))
    seq.append(row)
    print(json.dumps(row), flush=True)


def drive(eid, params_json, want, seq):
    for _ in range(3):
        brp("world.insert_components", {"entity": eid, "components": {APARAMS: params_json}})
        for _ in range(8):
            if playback(eid)["state"] == want:
                return True
            time.sleep(1)
    return False


def main():
    tag = sys.argv[1] if len(sys.argv) > 1 else "manual"
    eid = rig_id()
    assert eid, "no Rig entity answered world.query"
    seq = []
    deadline = time.time() + 20
    while playback(eid)["state"] != "idle" and time.time() < deadline:
        time.sleep(1)
    sample(eid, "entry", seq)
    assert drive(eid, {"values": {"Speed": 1.0}, "pending": []}, "walk", seq), "Speed=1 never reached walk"
    sample(eid, "speed1", seq)
    seq.append(dict(label="walk-loop-a", **playback(eid)))
    time.sleep(2)
    seq.append(dict(label="walk-loop-b", **playback(eid)))
    assert drive(eid, {"values": {"Speed": 0.0}, "pending": []}, "idle", seq), "Speed=0 never reached idle"
    sample(eid, "speed0", seq)
    brp("world.insert_components", {"entity": eid, "components": {APARAMS: {"values": {}, "pending": ["Jump"]}}})
    time.sleep(0.4)
    sample(eid, "jump-early", seq)
    time.sleep(0.5)
    sample(eid, "jump-held", seq)
    deadline = time.time() + 10
    fell = "never"
    while time.time() < deadline:
        if playback(eid)["state"] == "idle":
            fell = "idle"
            break
        time.sleep(1)
    sample(eid, "fallback", seq)
    path = OUT + "/parity-" + tag + ".json"
    with open(path, "w") as handle:
        handle.write("\n".join(json.dumps(row) for row in seq) + "\n")
    print("wrote", path, "fell:", fell)


if __name__ == "__main__":
    main()
