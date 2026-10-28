#!/bin/zsh
# T12-T3 full gates (sequential; NO RUST_BACKTRACE per T11-T3 §八-3)
cd /Users/zhanglinbo/workspace/jackdaw || exit 9
unset RUST_BACKTRACE
R=/Users/zhanglinbo/workspace/jackdaw/loop/reports

echo "=== GATE 1 fmt $(date '+%H:%M:%S') ==="
cargo fmt --all -- --check > "$R/t12t3_fmt.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_fmt.log"

echo "=== GATE 2 clippy ws $(date '+%H:%M:%S') ==="
cargo clippy --workspace --all-targets --features dylib -- -D warnings > "$R/t12t3_clippy_ws.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_clippy_ws.log"

echo "=== GATE 3 clippy physics $(date '+%H:%M:%S') ==="
cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings > "$R/t12t3_clippy_physics.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_clippy_physics.log"

echo "=== GATE 4 lib tests $(date '+%H:%M:%S') ==="
cargo test --workspace --lib > "$R/t12t3_libtests.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_libtests.log"

echo "=== GATE 5 xtask fast $(date '+%H:%M:%S') ==="
cargo xtask fast > "$R/t12t3_gate_fast.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_gate_fast.log"

echo "=== GATE 6 doctests $(date '+%H:%M:%S') ==="
cargo test --workspace --doc --features dylib > "$R/t12t3_doctests.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_doctests.log"

echo "=== GATE 7 docs $(date '+%H:%M:%S') ==="
cargo doc --workspace --no-deps > "$R/t12t3_docs.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_docs.log"

echo "=== GATE 8 integration $(date '+%H:%M:%S') ==="
cargo xtask integration > "$R/t12t3_gate_integration.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_gate_integration.log"

echo "=== ALL_GATES_DONE $(date '+%H:%M:%S') ==="
