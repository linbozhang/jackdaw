#!/usr/bin/env python3
"""Generate the T15 mini rig hero.glb: two loop clips and a one-shot jump.

A minimal, valid glTF 2.0 binary: two nodes (Armature > Hips) and three
translation-only animations named Idle_Loop / Walk_Loop / Jump. The loop clips
end on their first keyframe so they cycle seamlessly; Jump is authored as a
one-shot hop the set's `then: idle` falls back from. Kept in loop/ (not
committed) as the fixture asset's generator; rerun to regenerate:

    python3 loop/t15-live/make_hero_glb.py OUT_PATH
"""

import json
import struct
import sys

CLIPS = [
    ("Idle_Loop", [0.0, 1.0, 2.0],
     [[0.0, 0.0, 0.0], [0.0, 0.02, 0.0], [0.0, 0.0, 0.0]]),
    ("Walk_Loop", [0.0, 0.5, 1.0],
     [[-0.1, 0.0, 0.0], [0.1, 0.0, 0.0], [-0.1, 0.0, 0.0]]),
    ("Jump", [0.0, 0.4, 0.8],
     [[0.0, 0.0, 0.0], [0.0, 0.6, 0.0], [0.0, 0.0, 0.0]]),
]


def main(out_path):
    # One bufferView + accessor per sampler endpoint, in order: clip k's
    # times land at accessor 2k, its translations at 2k+1.
    views = []
    accessors = []
    blob = b""
    for name, times, translations in CLIPS:
        for floats, is_times in ((times, True), (
                [c for vec in translations for c in vec], False)):
            while len(blob) % 4:
                blob += b"\x00"
            data = struct.pack("<%df" % len(floats), *floats)
            accessor = {
                "bufferView": len(views),
                "componentType": 5126,
                "count": len(floats) if is_times else len(translations),
                "type": "SCALAR" if is_times else "VEC3",
            }
            if is_times:
                accessor["min"] = [min(times)]
                accessor["max"] = [max(times)]
            views.append({
                "buffer": 0,
                "byteOffset": len(blob),
                "byteLength": len(data),
                "target": 34962,
            })
            accessors.append(accessor)
            blob += data

    animations = [
        {
            "name": name,
            "samplers": [{
                "input": 2 * k,
                "interpolation": "LINEAR",
                "output": 2 * k + 1,
            }],
            "channels": [{
                "sampler": 0,
                "target": {"node": 1, "path": "translation"},
            }],
        }
        for k, (name, _, _) in enumerate(CLIPS)
    ]

    gltf = {
        "asset": {"version": "2.0",
                  "generator": "jackdaw loop t15 make_hero_glb.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "Armature", "children": [1]}, {"name": "Hips"}],
        "animations": animations,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }

    json_chunk = json.dumps(gltf, separators=(",", ":")).encode()
    while len(json_chunk) % 4:
        json_chunk += b" "

    total = 12 + 8 + len(json_chunk) + 8 + len(blob)
    with open(out_path, "wb") as out:
        out.write(struct.pack("<III", 0x46546C67, 2, total))
        out.write(struct.pack("<II", len(json_chunk), 0x4E4F534A))
        out.write(json_chunk)
        out.write(struct.pack("<II", len(blob), 0x004E4942))
        out.write(blob)
    print(f"wrote {out_path}: {total} bytes, "
          f"clips {[name for name, _, _ in CLIPS]}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "hero.glb")
