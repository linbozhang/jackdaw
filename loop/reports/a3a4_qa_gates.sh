#!/bin/zsh
# A3+A4 QA gate runner (serial, no RUST_BACKTRACE). Logs to loop/reports/a3a4_qa_*.
set -u
cd /Users/zhanglinbo/workspace/jackdaw
unset RUST_BACKTRACE
R=loop/reports
run() {
  name=$1; shift
  echo "=== GATE $name START $(date '+%F %T') ==="
  ( "$@" ) > $R/a3a4_qa_${name}.log 2>&1
  echo "EXIT_$name=$?" | tee -a $R/a3a4_qa_exitcodes.log
  echo "=== GATE $name END $(date '+%F %T') ==="
}
rm -f $R/a3a4_qa_exitcodes.log
run fmt        cargo fmt --all -- --check
run clippy_ws  cargo clippy --workspace --all-targets --features dylib -- -D warnings
run clippy_phy cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings
run libtests   cargo test --workspace --lib
run fast       cargo xtask fast
run integration cargo xtask integration
echo "ALL_GATES_DONE $(date '+%F %T')"
