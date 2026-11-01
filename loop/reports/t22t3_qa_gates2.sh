#!/bin/bash
# T22 final QA — clean rerun chain (run 2). NOTHING else may invoke cargo concurrently.
cd /Users/zhanglinbo/workspace/jackdaw || exit 1
R=loop/reports
echo "=== T22 final QA clean rerun start $(date -u +%FT%TZ) HEAD=$(git rev-parse --short HEAD) ==="
df -h / | tail -1

cargo xtask integration > $R/t22t3_qa_integration2.log 2>&1
echo "INTEGRATION2_EXIT=$?" >> $R/t22t3_qa_integration2.log

cargo nextest run --profile heavy -p jackdaw --test scaffold_e2e > $R/t22t3_qa_scaffold_e2e_heavy.log 2>&1
echo "E2E_HEAVY_EXIT=$?" >> $R/t22t3_qa_scaffold_e2e_heavy.log

cargo nextest run --profile ci -p jackdaw --test prefabs prefab_file_change_triggers_reload > $R/t22t3_qa_a6_isolated.log 2>&1
echo "A6_ISOLATED_EXIT=$?" >> $R/t22t3_qa_a6_isolated.log

echo "=== T22 final QA clean rerun done $(date -u +%FT%TZ) ==="
df -h / | tail -1
