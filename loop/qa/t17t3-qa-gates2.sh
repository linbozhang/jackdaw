#!/bin/bash
# T17-T3 QA gates, part 2 (the part-1 chain was SIGKILLed by the harness at
# the 1h wall cap mid-integration). Same evidence standard: serial, no
# RUST_BACKTRACE, whole logs archived. Adds the two QA-directed legs the
# integration gate excludes (heavy binaries): bsn_game_run (M2's H2 channel
# on the final tree) and the A6 isolated rerun.
set -u
unset RUST_BACKTRACE
unset RUST_LIB_BACKTRACE
cd /Users/zhanglinbo/workspace/jackdaw
R=loop/reports
echo "== QA gates p2 start $(date) df: $(df -g / | tail -1 | awk '{print $4}')Gi free ==" | tee -a "$R/t17t3_qa_gates_progress.log"
run_gate() {
  local name="$1" cmd="$2"
  echo "-- $name start $(date +%H:%M:%S)" | tee -a "$R/t17t3_qa_gates_progress.log"
  eval "$cmd" > "$R/t17t3_qa_${name}.log" 2>&1
  local ec=$?
  echo "-- $name end $(date +%H:%M:%S) EXIT=$ec" | tee -a "$R/t17t3_qa_gates_progress.log"
}
run_gate integration 'cargo xtask integration'
run_gate docs 'cargo doc --workspace --no-deps'
run_gate scaffold_e2e 'cargo nextest run --profile ci -p jackdaw --test scaffold_e2e'
run_gate bsn_game 'cargo nextest run --profile ci --test bsn_game_run'
run_gate a6_isolated 'cargo nextest run --profile ci -p jackdaw --test prefabs prefab_lifecycle::prefab_file_change_triggers_reload'
echo "== QA gates p2 done $(date) df after: $(df -g / | tail -1 | awk '{print $4}')Gi free ==" | tee -a "$R/t17t3_qa_gates_progress.log"
grep -h "EXIT=" "$R/t17t3_qa_gates_progress.log" | tail -10
