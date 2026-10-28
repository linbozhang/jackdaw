@echo off
cd /d E:\Project\rust\jackdaw
echo START %DATE% %TIME%

cargo fmt --all -- --check > loop\reports\gate-fmt-t04t2qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-fmt-t04t2qa.log

cargo clippy --workspace --all-targets --features dylib -- -D warnings > loop\reports\gate-clippy-t04t2qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-clippy-t04t2qa.log

cargo xtask fast > loop\reports\gate-xtask-fast-t04t2qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-xtask-fast-t04t2qa.log

cargo xtask integration > loop\reports\gate-xtask-integration-t04t2qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-xtask-integration-t04t2qa.log

echo ALLDONE
