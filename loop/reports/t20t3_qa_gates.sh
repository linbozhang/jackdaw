#!/bin/bash
# T20 final QA gate script — QA independent re-run, sequential, per-gate logs + exit codes.
# Full log capture per the evidence standard (exit code auxiliary only).
# RUST_BACKTRACE deliberately NOT set (T11-T3 discipline); gate chain runs in its own
# window, no editor/game processes launched from this session.
set -u
cd /Users/zhanglinbo/workspace/jackdaw
A=loop/reports
: > "$A/t20t3_qa_gates_exit.txt"
echo "df before gates:" >> "$A/t20t3_qa_gates_exit.txt"
df -h / | tail -1 >> "$A/t20t3_qa_gates_exit.txt"

run_gate() {
  local name="$1"; shift
  echo "=== $name START $(date '+%F %T') ===" >> "$A/t20t3_qa_gates_exit.txt"
  "$@" > "$A/t20t3_qa_${name}.log" 2>&1
  local rc=$?
  echo "$name EXIT=$rc $(date '+%F %T')" >> "$A/t20t3_qa_gates_exit.txt"
  echo "=== $name END rc=$rc $(date '+%F %T') ===" >> "$A/t20t3_qa_gates_exit.txt"
  df -h / | tail -1 >> "$A/t20t3_qa_gates_exit.txt"
}

run_gate fmt            cargo fmt --all -- --check
run_gate libtests       cargo test --workspace --lib
run_gate fast           cargo xtask fast
run_gate audio_gate     cargo nextest run --profile ci --test audio_gate
run_gate save_store     cargo nextest run --profile ci -p jackdaw_runtime --test save_store
run_gate integration    cargo xtask integration
run_gate docs           cargo doc --workspace --no-deps
run_gate scaffold_e2e   cargo nextest run --profile ci -E 'binary(scaffold_e2e)'
echo "ALL_GATES_DONE $(date '+%F %T')" >> "$A/t20t3_qa_gates_exit.txt"
