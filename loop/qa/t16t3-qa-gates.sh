#!/bin/bash
# T16 final QA gate chain (serial, no RUST_BACKTRACE, gates in a lone window).
set -u
cd /Users/zhanglinbo/workspace/jackdaw
R=loop/reports
echo "=== QA GATES START $(date) HEAD=$(git rev-parse --short HEAD) DIRTY=$(git status --porcelain | wc -l | tr -d ' ') df=$(df -g /Users/zhanglinbo/workspace | tail -1 | awk '{print $4}')Gi ===" >> "$R/t16t3_qa_gates_progress.log"
unset RUST_BACKTRACE
cargo fmt --all -- --check > "$R/t16t3_qa_fmt.log" 2>&1; echo "fmt exit=$?" >> "$R/t16t3_qa_gates_progress.log"
cargo test --workspace --lib --features dylib > "$R/t16t3_qa_libtests.log" 2>&1; echo "libtests exit=$?" >> "$R/t16t3_qa_gates_progress.log"
cargo xtask fast > "$R/t16t3_qa_fast.log" 2>&1; echo "fast exit=$?" >> "$R/t16t3_qa_gates_progress.log"
cargo test --test audio_gate > "$R/t16t3_qa_audio_gate.log" 2>&1; echo "audio_gate exit=$?" >> "$R/t16t3_qa_gates_progress.log"
cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings > "$R/t16t3_qa_clippy_physics.log" 2>&1; echo "clippy_physics exit=$?" >> "$R/t16t3_qa_gates_progress.log"
cargo xtask integration > "$R/t16t3_qa_integration.log" 2>&1; echo "integration exit=$?" >> "$R/t16t3_qa_gates_progress.log"
cargo doc --no-deps --workspace > "$R/t16t3_qa_docs.log" 2>&1; echo "docs exit=$?" >> "$R/t16t3_qa_gates_progress.log"
cargo nextest run --profile ci -p jackdaw --test scaffold_e2e > "$R/t16t3_qa_scaffold_e2e.log" 2>&1; echo "scaffold_e2e exit=$?" >> "$R/t16t3_qa_gates_progress.log"
echo "=== QA GATES END $(date) df=$(df -g /Users/zhanglinbo/workspace | tail -1 | awk '{print $4}')Gi ===" >> "$R/t16t3_qa_gates_progress.log"
