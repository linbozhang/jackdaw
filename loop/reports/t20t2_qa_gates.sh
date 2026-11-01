#!/bin/bash
# T20-T2 QA gate script — run from repo root, sequential, per-gate logs + exit codes.
# RUST_BACKTRACE deliberately NOT set (T11-T3 discipline).
set -u
cd /Users/zhanglinbo/workspace/jackdaw
A=loop/reports
: > "$A/t20t2_qa_gates_exit.txt"

run_gate() {
  local name="$1"; shift
  echo "=== $name START $(date '+%F %T') ===" >> "$A/t20t2_qa_gates_exit.txt"
  "$@" > "$A/t20t2_qa_${name}.log" 2>&1
  local rc=$?
  echo "$name EXIT=$rc $(date '+%F %T')" >> "$A/t20t2_qa_gates_exit.txt"
  echo "=== $name END rc=$rc $(date '+%F %T') ===" >> "$A/t20t2_qa_gates_exit.txt"
}

run_gate fmt          cargo fmt --all -- --check
run_gate clippy_ws    cargo clippy --workspace --all-targets --features dylib -- -D warnings
run_gate clippy_phys  cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings
run_gate libtests     cargo test --workspace --lib
run_gate audio_gate   cargo nextest run --profile ci --test audio_gate
run_gate save_store   cargo nextest run --profile ci -p jackdaw_runtime --test save_store
run_gate an2_scene    cargo nextest run --profile ci -p jackdaw_runtime --features animation --test animation_scene_load
echo "ALL_GATES_DONE $(date '+%F %T')" >> "$A/t20t2_qa_gates_exit.txt"
