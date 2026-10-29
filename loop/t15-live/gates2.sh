#!/bin/bash
# Rerun of the two gates the unused-mut broke, plus the AN7 unit test row.
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
OUT=/Users/zhanglinbo/workspace/jackdaw/loop/t15-live
cd "$REPO"
echo "== fmt =="
cargo fmt --all -- --check > "$OUT/fmt.log" 2>&1 && echo FMT_OK || echo FMT_FAIL
echo "== clippy ws =="
cargo clippy --workspace --all-targets --features dylib -- --deny warnings > "$OUT/clippy-ws.log" 2>&1 && echo CLIPPY_WS_OK || echo CLIPPY_WS_FAIL
echo "== lib tests =="
cargo test --workspace --lib --features dylib > "$OUT/libtests.log" 2>&1 && echo LIBTESTS_OK || echo LIBTESTS_FAIL
echo "== fast =="
cargo xtask fast > "$OUT/fast.log" 2>&1 && echo FAST_OK || echo FAST_FAIL
echo "== gates2 done =="
