#!/bin/bash
# T23-T2 gate chain, run after the live phases with the editor killed (the A6
# window discipline). T2 made no product-code changes (the live script and the
# reports are the deliverables), so the gates re-prove the T1 green state on
# the branch tip. Logs land in loop/reports/ with the t23t2_gates_ prefix;
# evidence standard = the log's full text (the exit code is a helper, the
# 2026-10-25 lesson), so each gate's FAIL lines are grepped and echoed.
set -u
REPO=/Users/zhanglinbo/workspace/jackdaw
R="$REPO/loop/reports"
mkdir -p "$R"
cd "$REPO"
FAIL=0

run() { # run <log> <cmd...>
  local log="$1"; shift
  echo "== $* -> $log"
  "$@" > "$R/$log" 2>&1
  local code=$?
  local bad
  bad=$(grep -cE "^error|FAILED|Diff after reformat|warning:" "$R/$log")
  echo "   exit=$code suspicious-lines=$bad"
  [ "$code" = "0" ] || FAIL=1
}

run t23t2_gates_fmt.log        cargo fmt --all -- --check
run t23t2_gates_clippy_ws.log  cargo clippy --workspace --all-targets --features dylib -- -D warnings
run t23t2_gates_clippy_phys.log cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings
run t23t2_gates_libtests.log   cargo nextest run --profile ci --workspace --lib
run t23t2_guards.log           cargo nextest run --profile ci -p jackdaw --test guards
run t23t2_stage.log            cargo nextest run --profile ci -p jackdaw --test stage
# The AN2 leg (T15's integration-tier feature leg) stays green.
run t23t2_an2_scene_load.log   cargo nextest run --profile ci -p jackdaw_runtime --features animation --test animation_scene_load

echo "GATES_FAIL=$FAIL"
