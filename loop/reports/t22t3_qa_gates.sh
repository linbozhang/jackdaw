#!/bin/bash
# T22-T3 final QA gate chain — serialized to avoid cargo target-dir lock contention.
# No RUST_BACKTRACE (T11-T3 discipline). Gate chain runs alone (no editor/game same-window).
cd /Users/zhanglinbo/workspace/jackdaw || exit 1
R=loop/reports
echo "=== T22 final QA gates start $(date -u +%FT%TZ) HEAD=$(git rev-parse --short HEAD) ==="
df -h / | tail -1

cargo fmt --all -- --check > $R/t22t3_qa_fmt.log 2>&1
echo "FMT_EXIT=$?" >> $R/t22t3_qa_fmt.log

cargo test --workspace --lib > $R/t22t3_qa_libtests.log 2>&1
echo "LIBTESTS_EXIT=$?" >> $R/t22t3_qa_libtests.log

cargo xtask fast > $R/t22t3_qa_fast.log 2>&1
echo "FAST_EXIT=$?" >> $R/t22t3_qa_fast.log

cargo nextest run --profile ci --test audio_gate > $R/t22t3_qa_audio_gate.log 2>&1
echo "AUDIO_EXIT=$?" >> $R/t22t3_qa_audio_gate.log

cargo nextest run --profile ci -p jackdaw_runtime --test save_store > $R/t22t3_qa_save_store.log 2>&1
echo "SAVE_EXIT=$?" >> $R/t22t3_qa_save_store.log

cargo doc --workspace --no-deps > $R/t22t3_qa_doc.log 2>&1
echo "DOCS_EXIT=$?" >> $R/t22t3_qa_doc.log

cargo nextest run --profile ci -p jackdaw --test scaffold_e2e > $R/t22t3_qa_scaffold_e2e.log 2>&1
echo "E2E_EXIT=$?" >> $R/t22t3_qa_scaffold_e2e.log

cargo xtask integration > $R/t22t3_qa_integration.log 2>&1
echo "INTEGRATION_EXIT=$?" >> $R/t22t3_qa_integration.log

echo "=== T22 final QA gates done $(date -u +%FT%TZ) ==="
df -h / | tail -1
