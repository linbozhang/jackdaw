#!/bin/bash
# T14-T3 final QA full gates (independent rerun), serial, no RUST_BACKTRACE
# (T11-T3 discipline). Logs land in loop/reports/t14t3_qa_*.log; the
# program's own t14t3_*.log archives are left untouched.
set -u
cd /Users/zhanglinbo/workspace/jackdaw
unset RUST_BACKTRACE
R=loop/reports
run() {
  local name="$1"; shift
  echo "== $name: $*  (start $(date +%H:%M:%S))"
  "$@" > "$R/$name.log" 2>&1
  echo "   exit=$?  (end $(date +%H:%M:%S))"
}
run t14t3_qa_fmt             cargo fmt --all -- --check
run t14t3_qa_clippy_ws       cargo clippy --workspace --all-targets --features dylib -- -D warnings
run t14t3_qa_clippy_physics  cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings
run t14t3_qa_libtests        cargo test --workspace --lib
run t14t3_qa_gate_fast       cargo xtask fast
run t14t3_qa_gate_integration cargo xtask integration
run t14t3_qa_doctests        cargo test --workspace --doc --features dylib
run t14t3_qa_docs            cargo doc --workspace --no-deps
run t14t3_qa_scaffold_e2e    cargo test -p jackdaw --test scaffold_e2e
echo "== ALL QA GATES DONE $(date +%H:%M:%S)"
