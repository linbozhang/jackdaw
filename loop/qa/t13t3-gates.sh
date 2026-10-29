#!/bin/bash
# T13-T3 QA full gates, serial, no RUST_BACKTRACE (T11-T3 §八-3).
# Logs land in loop/reports/t13t3_*.log.
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
run t13t3_clippy_phy   cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings
run t13t3_libtests     cargo test --workspace --lib
run t13t3_guards       cargo test -p jackdaw --test guards
run t13t3_gate_fast    cargo xtask fast
run t13t3_gate_integration cargo xtask integration
run t13t3_doctests     cargo test --workspace --doc --features dylib
run t13t3_docs         cargo doc --workspace --no-deps
echo "== ALL GATES DONE"
