#!/bin/bash
# T21-T3 program gate script — run from repo root, sequential, per-gate logs + exit codes.
# Full log capture per the evidence standard (exit code auxiliary only).
# RUST_BACKTRACE deliberately NOT set (T11-T3 discipline).
set -u
cd /Users/zhanglinbo/workspace/jackdaw
A=loop/reports
: > "$A/t21t3_gates_exit.txt"
echo "df before gates:" >> "$A/t21t3_gates_exit.txt"
df -h / | tail -1 >> "$A/t21t3_gates_exit.txt"

run_gate() {
  local name="$1"; shift
  echo "=== $name START $(date '+%F %T') ===" >> "$A/t21t3_gates_exit.txt"
  "$@" > "$A/t21t3_gates_${name}.log" 2>&1
  local rc=$?
  echo "$name EXIT=$rc $(date '+%F %T')" >> "$A/t21t3_gates_exit.txt"
  echo "=== $name END rc=$rc $(date '+%F %T') ===" >> "$A/t21t3_gates_exit.txt"
  df -h / | tail -1 >> "$A/t21t3_gates_exit.txt"
}

run_gate fmt            cargo fmt --all -- --check
run_gate clippy_ws      cargo clippy --workspace --all-targets --features dylib -- -D warnings
run_gate clippy_phys    cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings
run_gate libtests       cargo test --workspace --lib
run_gate fast           cargo xtask fast
run_gate integration    cargo xtask integration
run_gate doctests       cargo test --workspace --doc
run_gate docs           cargo doc --workspace --no-deps
run_gate scaffold_e2e   cargo nextest run --profile ci -E 'binary(scaffold_e2e)'
echo "ALL_GATES_DONE $(date '+%F %T')" >> "$A/t21t3_gates_exit.txt"
