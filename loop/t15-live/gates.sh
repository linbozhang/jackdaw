#!/bin/bash
# T15-T2 gate chain: fmt, clippy (workspace + physics dual), lib tests,
# then the xtask fast tier. Logs land beside this script.
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
OUT=/Users/zhanglinbo/workspace/jackdaw/loop/t15-live
cd "$REPO"
echo "== fmt ==" 
cargo fmt --all -- --check > "$OUT/fmt.log" 2>&1 && echo FMT_OK || echo FMT_FAIL
echo "== clippy ws =="
cargo clippy --workspace --all-targets --features dylib -- --deny warnings > "$OUT/clippy-ws.log" 2>&1 && echo CLIPPY_WS_OK || echo CLIPPY_WS_FAIL
echo "== clippy physics =="
cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings > "$OUT/clippy-physics.log" 2>&1 && echo CLIPPY_PHY_OK || echo CLIPPY_PHY_FAIL
echo "== lib tests =="
cargo test --workspace --lib --features dylib > "$OUT/libtests.log" 2>&1 && echo LIBTESTS_OK || echo LIBTESTS_FAIL
echo "== fast =="
cargo xtask fast > "$OUT/fast.log" 2>&1 && echo FAST_OK || echo FAST_FAIL
echo "== an2 leg =="
cargo nextest run --profile ci -p jackdaw_runtime --features animation --test animation_scene_load > "$OUT/an2-scene-load.log" 2>&1 && echo AN2_OK || echo AN2_FAIL
echo "== stage animation =="
cargo nextest run --profile ci -p jackdaw --features dylib --test stage -E 'test(/animation/)' > "$OUT/stage-animation.log" 2>&1 && echo STAGE_ANIM_OK || echo STAGE_ANIM_FAIL
echo "== gates done =="
