#!/bin/bash
# T15-T1 AN1 red evidence prep: jd new a default-module fixture, author an
# animation scene, cold-build the game WITHOUT the animation feature.
set -ux
REPO=/Users/zhanglinbo/workspace/jackdaw
FIXROOT=/Users/zhanglinbo/workspace/loop-mac/t15-anim
PROJECT="$FIXROOT/t15-anim"
TOOLCHAIN_LIB=/Users/zhanglinbo/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib
mkdir -p "$FIXROOT"
cd "$REPO"
cargo run -p jd --quiet -- new t15-anim --path "$FIXROOT" --no-git || exit 1

# The animation scene: a rig whose set names hero.glb clips (jump one-shot
# falls back to idle via then). Serves red (type unresolved) and, after the
# module is enabled, green (set binds and plays).
cat > "$PROJECT/assets/anim.bsn" <<'SCENE'
// Animation parity scene (T15). A rig whose set names hero.glb clips; the
// game plays the default state as soon as the set binds.

#Rig
jackdaw_animation_runtime::AnimationSet {
    sources: ["models/hero.glb"],
    states: [
        jackdaw_animation_runtime::AnimationStateDef {
            name: "idle",
            source: 0,
            clip: "Idle_Loop",
            looped: true,
            transition_secs: 0.15,
            speed: 1.0,
            then: None,
        },
        jackdaw_animation_runtime::AnimationStateDef {
            name: "walk",
            source: 0,
            clip: "Walk_Loop",
            looped: true,
            transition_secs: 0.15,
            speed: 1.0,
            then: None,
        },
        jackdaw_animation_runtime::AnimationStateDef {
            name: "jump",
            source: 0,
            clip: "Jump",
            looped: false,
            transition_secs: 0.15,
            speed: 1.0,
            then: Some("idle"),
        },
    ],
    default_state: "idle",
    skeleton_root: "Armature",
}
bevy_ecs::hierarchy::Children [
    #Armature
    bevy_transform::components::transform::Transform
]
SCENE

python3 - "$PROJECT/assets/game.flow.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    flow = json.load(f)
flow["start_scene"] = "anim.bsn"
if "anim.bsn" not in flow.get("scenes", []):
    flow.setdefault("scenes", []).insert(0, "anim.bsn")
with open(path, "w") as f:
    json.dump(flow, f, indent=2)
PY

mkdir -p "$PROJECT/assets/models"
cp -R "$REPO/assets/jan" "$PROJECT/assets/models/jan"
echo "PREP_DONE"
