#!/bin/zsh
# T12 FINAL QA full gates (sequential; NO RUST_BACKTRACE per T11-T3 §八-3 / T12 discipline)
cd /Users/zhanglinbo/workspace/jackdaw || exit 9
unset RUST_BACKTRACE
R=/Users/zhanglinbo/workspace/jackdaw/loop/reports

echo "=== GATE 1 fmt $(date '+%H:%M:%S') ==="
cargo fmt --all -- --check > "$R/t12t3_qa_fmt.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_qa_fmt.log"

echo "=== GATE 2 clippy ws $(date '+%H:%M:%S') ==="
cargo clippy --workspace --all-targets --features dylib -- -D warnings > "$R/t12t3_qa_clippy_ws.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_qa_clippy_ws.log"

echo "=== GATE 3 clippy physics $(date '+%H:%M:%S') ==="
cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings > "$R/t12t3_qa_clippy_physics.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_qa_clippy_physics.log"

echo "=== GATE 4 lib tests $(date '+%H:%M:%S') ==="
cargo test --workspace --lib > "$R/t12t3_qa_libtests.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_qa_libtests.log"

echo "=== GATE 5 xtask fast $(date '+%H:%M:%S') ==="
cargo xtask fast > "$R/t12t3_qa_gate_fast.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_qa_gate_fast.log"

echo "=== GATE 6 guards $(date '+%H:%M:%S') ==="
cargo test -p jackdaw --test guards > "$R/t12t3_qa_guards.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_qa_guards.log"

echo "=== GATE 7 scaffold_e2e $(date '+%H:%M:%S') ==="
cargo test -p jackdaw --test scaffold_e2e > "$R/t12t3_qa_scaffold_e2e.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_qa_scaffold_e2e.log"

echo "=== GATE 8 doctests $(date '+%H:%M:%S') ==="
cargo test --workspace --doc --features dylib > "$R/t12t3_qa_doctests.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_qa_doctests.log"

echo "=== GATE 9 docs $(date '+%H:%M:%S') ==="
cargo doc --workspace --no-deps > "$R/t12t3_qa_docs.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_qa_docs.log"

echo "=== GATE 10 integration $(date '+%H:%M:%S') ==="
cargo xtask integration > "$R/t12t3_qa_gate_integration.log" 2>&1
echo "EXIT=$?" >> "$R/t12t3_qa_gate_integration.log"

echo "=== ALL_GATES_DONE $(date '+%H:%M:%S') ==="
