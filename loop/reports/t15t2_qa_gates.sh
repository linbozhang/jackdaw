#!/bin/bash
# T15-T2 QA gates — serial, RUST_BACKTRACE unset, logs to loop/reports/t15t2_qa_*
cd /Users/zhanglinbo/workspace/jackdaw
unset RUST_BACKTRACE
R=loop/reports
echo "== env ==" > $R/t15t2_qa_gates_progress.log
date >> $R/t15t2_qa_gates_progress.log
echo "RUST_BACKTRACE=[${RUST_BACKTRACE:-UNSET}]" >> $R/t15t2_qa_gates_progress.log
df -h / | tail -1 >> $R/t15t2_qa_gates_progress.log

echo "[$(date +%T)] fmt start" >> $R/t15t2_qa_gates_progress.log
cargo fmt --all -- --check > $R/t15t2_qa_fmt.log 2>&1
echo "[$(date +%T)] fmt exit=$?" >> $R/t15t2_qa_gates_progress.log

echo "[$(date +%T)] clippy ws start" >> $R/t15t2_qa_gates_progress.log
cargo clippy --workspace --all-targets --features dylib -- --deny warnings > $R/t15t2_qa_clippy_ws.log 2>&1
echo "[$(date +%T)] clippy ws exit=$?" >> $R/t15t2_qa_gates_progress.log

echo "[$(date +%T)] clippy physics start" >> $R/t15t2_qa_gates_progress.log
cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings > $R/t15t2_qa_clippy_physics.log 2>&1
echo "[$(date +%T)] clippy physics exit=$?" >> $R/t15t2_qa_gates_progress.log

echo "[$(date +%T)] libtests start" >> $R/t15t2_qa_gates_progress.log
cargo test --workspace --lib --features dylib > $R/t15t2_qa_libtests.log 2>&1
echo "[$(date +%T)] libtests exit=$?" >> $R/t15t2_qa_gates_progress.log

echo "[$(date +%T)] fast start" >> $R/t15t2_qa_gates_progress.log
cargo xtask fast > $R/t15t2_qa_fast.log 2>&1
echo "[$(date +%T)] fast exit=$?" >> $R/t15t2_qa_gates_progress.log

echo "[$(date +%T)] an2 leg start" >> $R/t15t2_qa_gates_progress.log
cargo nextest run --profile ci -p jackdaw_runtime --features animation --test animation_scene_load > $R/t15t2_qa_an2_scene_load.log 2>&1
echo "[$(date +%T)] an2 leg exit=$?" >> $R/t15t2_qa_gates_progress.log

echo "[$(date +%T)] stage animation filter start" >> $R/t15t2_qa_gates_progress.log
cargo nextest run --profile ci -p jackdaw --features dylib --test stage animation > $R/t15t2_qa_stage_animation.log 2>&1
echo "[$(date +%T)] stage animation filter exit=$?" >> $R/t15t2_qa_gates_progress.log

echo "[$(date +%T)] ALL GATES DONE" >> $R/t15t2_qa_gates_progress.log
df -h / | tail -1 >> $R/t15t2_qa_gates_progress.log
