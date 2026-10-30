#!/bin/bash
# T17-T3 full gates, sequential, each log archived into loop/reports/t17t3_*.
# Evidence standard (loop/README): exit code is auxiliary; the QA reads the
# whole logs. df is taken before the long gates (A6 family pressure).
set -u
cd /Users/zhanglinbo/workspace/jackdaw
R=loop/reports
mkdir -p "$R"
echo "== gates start $(date) df: $(df -g / | tail -1 | awk '{print $4}')Gi free ==" | tee "$R/t17t3_gates_progress.log"

run_gate() {
  local name="$1" cmd="$2"
  echo "-- $name start $(date +%H:%M:%S)" | tee -a "$R/t17t3_gates_progress.log"
  eval "$cmd" > "$R/t17t3_${name}.log" 2>&1
  local ec=$?
  echo "-- $name end $(date +%H:%M:%S) EXIT=$ec" | tee -a "$R/t17t3_gates_progress.log"
}

run_gate fmt 'cargo fmt --all -- --check'
run_gate clippy_ws 'cargo clippy --workspace --all-targets --features dylib -- --deny warnings'
run_gate clippy_physics 'cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings'
run_gate libtests 'cargo test --workspace --lib'
run_gate save_store 'cargo nextest run --profile ci -p jackdaw_runtime --test save_store'
run_gate fast 'cargo xtask fast'
echo "== df before integration: $(df -g / | tail -1 | awk '{print $4}')Gi free ==" | tee -a "$R/t17t3_gates_progress.log"
run_gate integration 'cargo xtask integration'
run_gate doctests 'cargo test --workspace --doc'
run_gate doc 'cargo doc --workspace --no-deps'
run_gate scaffold_e2e 'cargo nextest run --profile ci -p jackdaw --test scaffold_e2e'
echo "== gates done $(date) df after: $(df -g / | tail -1 | awk '{print $4}')Gi free ==" | tee -a "$R/t17t3_gates_progress.log"
grep -h "EXIT=" "$R/t17t3_gates_progress.log"
