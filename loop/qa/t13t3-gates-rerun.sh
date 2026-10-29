#!/bin/bash
# T13-T3 QA gates, rerun after the fmt/lint fixes: the failed gates plus
# the known-flaky re-verification legs. Serial, no RUST_BACKTRACE.
set -u
cd /Users/zhanglinbo/workspace/jackdaw
unset RUST_BACKTRACE
R=loop/reports
run() {
  local name="$1"; shift
  echo "== $name: $*"
  "$@" > "$R/$name.log" 2>&1
  echo "   exit=$?"
}
run t13t3_fmt          cargo fmt --all -- --check
run t13t3_clippy_ws    cargo clippy --workspace --all-targets --features dylib -- -D warnings
run t13t3_libtests     cargo test --workspace --lib
run t13t3_guards       cargo test -p jackdaw --test guards
run t13t3_gate_fast    cargo xtask fast
run t13t3_gate_integration cargo xtask integration
echo "== RERUN DONE"
