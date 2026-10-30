#!/bin/bash
# T17-T1 QA gates (acceptance re-run by QA), sequential, on loop/t17-save @ e589257f.
# Discipline: no RUST_BACKTRACE; gates run one at a time (T12-T3 §九-7); logs overwrite-archive into loop/reports/t17t1_qa_*.
set -u
cd /Users/zhanglinbo/workspace/jackdaw || exit 9
unset RUST_BACKTRACE
R=/Users/zhanglinbo/workspace/jackdaw/loop/reports
: > "$R/t17t1_qa_exitcodes.log"

run() {
  local name="$1"; shift
  { echo "== $name START $(date '+%F %T')"; echo "cwd=$(pwd)"; echo "cmd=$*"; } > "$R/t17t1_qa_${name}.log"
  "$@" >> "$R/t17t1_qa_${name}.log" 2>&1
  local ec=$?
  echo "== $name EXIT=$ec $(date '+%F %T')" >> "$R/t17t1_qa_${name}.log"
  echo "$name EXIT=$ec" >> "$R/t17t1_qa_exitcodes.log"
}

echo "df before gates:" >> "$R/t17t1_qa_exitcodes.log"
df -h / | tail -1 >> "$R/t17t1_qa_exitcodes.log"

run fmt        cargo fmt --all -- --check
run clippy_ws  cargo clippy --workspace --all-targets --features dylib -- --deny warnings
run clippy_phy cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings
run libtests   cargo test --workspace --lib
run fast       cargo xtask fast
run an2        cargo nextest run --profile ci -p jackdaw_runtime --features animation --test animation_scene_load
run save_store cargo nextest run --profile ci -p jackdaw_runtime --test save_store
run rt_suite   cargo test -p jackdaw_runtime

echo "ALL GATES DONE $(date '+%F %T')" >> "$R/t17t1_qa_exitcodes.log"
cat "$R/t17t1_qa_exitcodes.log"
