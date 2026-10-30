#!/bin/bash
# T15-T3 full gate sequence, each archived to loop/reports/t15t3_*.log.
set -u
cd /Users/zhanglinbo/workspace/jackdaw
R=loop/reports
echo "=== GATES START $(date) ==="
unset RUST_BACKTRACE
cargo fmt --all -- --check > "$R/t15t3_fmt.log" 2>&1; echo "fmt exit=$?" | tee -a "$R/t15t3_gates_progress.log"
cargo clippy --workspace --all-targets --features dylib -- --deny warnings > "$R/t15t3_clippy_ws.log" 2>&1; echo "clippy_ws exit=$?" | tee -a "$R/t15t3_gates_progress.log"
cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings > "$R/t15t3_clippy_physics.log" 2>&1; echo "clippy_physics exit=$?" | tee -a "$R/t15t3_gates_progress.log"
cargo test --workspace --lib --features dylib > "$R/t15t3_libtests.log" 2>&1; echo "libtests exit=$?" | tee -a "$R/t15t3_gates_progress.log"
cargo xtask fast > "$R/t15t3_fast.log" 2>&1; echo "fast exit=$?" | tee -a "$R/t15t3_gates_progress.log"
cargo xtask integration > "$R/t15t3_integration.log" 2>&1; echo "integration exit=$?" | tee -a "$R/t15t3_gates_progress.log"
cargo test --doc --workspace > "$R/t15t3_doctests.log" 2>&1; echo "doctests exit=$?" | tee -a "$R/t15t3_gates_progress.log"
cargo doc --no-deps --workspace > "$R/t15t3_docs.log" 2>&1; echo "docs exit=$?" | tee -a "$R/t15t3_gates_progress.log"
cargo nextest run --profile ci -p jackdaw --features dylib --test scaffold_e2e > "$R/t15t3_scaffold_e2e.log" 2>&1; echo "scaffold_e2e exit=$?" | tee -a "$R/t15t3_gates_progress.log"
echo "=== GATES END $(date) ==="
