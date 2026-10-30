#!/bin/bash
# T15 final QA gate chain (serial, no RUST_BACKTRACE, gates in a lone window).
set -u
cd /Users/zhanglinbo/workspace/jackdaw
R=loop/reports
echo "=== QA GATES START $(date) HEAD=$(git rev-parse --short HEAD) DIRTY=$(git status --porcelain | wc -l | tr -d ' ') df=$(df -g /Users/zhanglinbo/workspace | tail -1 | awk '{print $4}')Gi ==="
unset RUST_BACKTRACE
cargo fmt --all -- --check > "$R/t15t3qa_fmt.log" 2>&1; echo "fmt exit=$?" >> "$R/t15t3qa_gates_progress.log"
cargo test --workspace --lib --features dylib > "$R/t15t3qa_libtests.log" 2>&1; echo "libtests exit=$?" >> "$R/t15t3qa_gates_progress.log"
cargo xtask fast > "$R/t15t3qa_fast.log" 2>&1; echo "fast exit=$?" >> "$R/t15t3qa_gates_progress.log"
cargo xtask integration > "$R/t15t3qa_integration.log" 2>&1; echo "integration exit=$?" >> "$R/t15t3qa_gates_progress.log"
cargo doc --no-deps --workspace > "$R/t15t3qa_docs.log" 2>&1; echo "docs exit=$?" >> "$R/t15t3qa_gates_progress.log"
cargo nextest run --profile ci -p jackdaw --test scaffold_e2e > "$R/t15t3qa_scaffold_e2e.log" 2>&1; echo "scaffold_e2e exit=$?" >> "$R/t15t3qa_gates_progress.log"
echo "=== QA GATES END $(date) ==="
