#!/bin/zsh
# T11-T3 final QA Mac full gates (sequential; NO RUST_BACKTRACE per report §八-3)
cd /Users/zhanglinbo/workspace/jackdaw || exit 9
unset RUST_BACKTRACE
export RUST_BACKTRACE=0 2>/dev/null
unset RUST_BACKTRACE  # ensure unset
R=/Users/zhanglinbo/workspace/jackdaw/loop/reports

echo "=== GATE 1 fmt $(date '+%H:%M:%S') ==="
cargo fmt --all -- --check > "$R/t11t3_qa_mac_fmt.log" 2>&1
echo "EXIT=$?" >> "$R/t11t3_qa_mac_fmt.log"

echo "=== GATE 2 clippy ws $(date '+%H:%M:%S') ==="
cargo clippy --workspace --all-targets --features dylib -- -D warnings > "$R/t11t3_qa_mac_clippy_ws.log" 2>&1
echo "EXIT=$?" >> "$R/t11t3_qa_mac_clippy_ws.log"

echo "=== GATE 3 clippy physics $(date '+%H:%M:%S') ==="
cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings > "$R/t11t3_qa_mac_clippy_physics.log" 2>&1
echo "EXIT=$?" >> "$R/t11t3_qa_mac_clippy_physics.log"

echo "=== GATE 4 lib tests $(date '+%H:%M:%S') ==="
cargo test --workspace --lib > "$R/t11t3_qa_mac_libtests.log" 2>&1
echo "EXIT=$?" >> "$R/t11t3_qa_mac_libtests.log"

echo "=== GATE 5 xtask fast $(date '+%H:%M:%S') ==="
cargo xtask fast > "$R/t11t3_qa_mac_gate_fast.log" 2>&1
echo "EXIT=$?" >> "$R/t11t3_qa_mac_gate_fast.log"

echo "=== GATE 6 xtask integration $(date '+%H:%M:%S') ==="
cargo xtask integration > "$R/t11t3_qa_mac_gate_integration.log" 2>&1
echo "EXIT=$?" >> "$R/t11t3_qa_mac_gate_integration.log"

echo "=== GATE 7 doctests $(date '+%H:%M:%S') ==="
cargo test --workspace --doc --features dylib > "$R/t11t3_qa_mac_doctests.log" 2>&1
echo "EXIT=$?" >> "$R/t11t3_qa_mac_doctests.log"

echo "=== GATE 8 docs $(date '+%H:%M:%S') ==="
cargo doc --locked --workspace --document-private-items --no-deps > "$R/t11t3_qa_mac_doc.log" 2>&1
echo "EXIT=$?" >> "$R/t11t3_qa_mac_doc.log"

echo "=== ALL_GATES_DONE $(date '+%H:%M:%S') ==="
