@echo off
cd /d E:\Project\rust\jackdaw
echo START %DATE% %TIME%

cargo fmt --all -- --check > loop\reports\gate-fmt-t03r1qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-fmt-t03r1qa.log

cargo clippy --workspace --all-targets --features dylib -- -D warnings > loop\reports\gate-clippy-t03r1qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-clippy-t03r1qa.log

cargo xtask fast > loop\reports\gate-xtask-fast-t03r1qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-xtask-fast-t03r1qa.log

cargo xtask integration > loop\reports\gate-xtask-integration-t03r1qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-xtask-integration-t03r1qa.log

echo ALLDONE
