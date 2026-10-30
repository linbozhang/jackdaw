#!/bin/bash
# T17-T2 QA gates: run in order, archive each log to loop/reports/t17t2_qa_*.log
# Note: RUST_BACKTRACE deliberately NOT set (T11-T3: Mac debug + RUST_BACKTRACE -> SIGSEGV).
set -u
cd /Users/zhanglinbo/workspace/jackdaw
R=loop/reports
: > $R/t17t2_qa_exitcodes.log

run_gate() {
  local name="$1"; shift
  echo "=== GATE $name START $(date '+%H:%M:%S') ===" >> $R/t17t2_qa_exitcodes.log
  "$@" > "$R/t17t2_qa_${name}.log" 2>&1
  local rc=$?
  echo "$name EXIT=$rc $(date '+%H:%M:%S')" >> $R/t17t2_qa_exitcodes.log
  echo "GATE $name rc=$rc"
}

df -h / | tail -1 > $R/t17t2_qa_df.txt
echo "--- df before gates ---"; cat $R/t17t2_qa_df.txt

run_gate fmt        cargo fmt --all -- --check
run_gate clippy_ws  cargo clippy --workspace --all-targets --features dylib -- --deny warnings
run_gate clippy_phy cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings
run_gate libtests   cargo test --workspace --lib
run_gate save_store cargo nextest run --profile ci -p jackdaw_runtime --test save_store
run_gate audio_gate cargo nextest run --profile ci --test audio_gate
run_gate an2        cargo nextest run --profile ci -p jackdaw_runtime --features animation --test animation_scene_load
run_gate bsngame    cargo nextest run --profile ci --test bsn_game_run
run_gate fast       cargo xtask fast

df -h / | tail -1 >> $R/t17t2_qa_df.txt
echo "--- df after gates ---"; cat $R/t17t2_qa_df.txt
echo "ALL GATES DONE $(date '+%H:%M:%S')" >> $R/t17t2_qa_exitcodes.log
cat $R/t17t2_qa_exitcodes.log
