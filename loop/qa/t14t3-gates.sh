#!/bin/bash
# T14-T3 full gate chain (sequential; run only when no editor/game live
# legs are up -- T12-T3 §9-7 discipline). Records one log + exit code
# per gate under loop/reports/.
set -u
R=/Users/zhanglinbo/workspace/jackdaw/loop/reports
cd /Users/zhanglinbo/workspace/jackdaw
: > "$R/t14t3_gates_exitcodes.log"
run() {
  local name="$1"; shift
  echo "=== $name start $(date +%H:%M:%S): $*"
  "$@" > "$R/$name.log" 2>&1
  local rc=$?
  echo "$name EXIT=$rc" | tee -a "$R/t14t3_gates_exitcodes.log"
}
run t14t3_fmt cargo fmt --all -- --check
run t14t3_clippy_ws cargo clippy --workspace --all-targets --features dylib -- -D warnings
run t14t3_clippy_phy cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings
run t14t3_libtests cargo test --workspace --lib
run t14t3_fast cargo xtask fast
run t14t3_integration cargo xtask integration
run t14t3_doctests cargo test --doc --workspace
run t14t3_docs cargo doc --no-deps --workspace
run t14t3_scaffold_e2e cargo test -p jackdaw --test scaffold_e2e --features dylib -- --nocapture
echo "GATES_DONE $(date +%H:%M:%S)"
cat "$R/t14t3_gates_exitcodes.log"
