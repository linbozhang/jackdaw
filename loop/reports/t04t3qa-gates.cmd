@echo off
cd /d E:\Project\rust\jackdaw
echo START %DATE% %TIME%

cargo fmt --all -- --check > loop\reports\gate-fmt-t04t3qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-fmt-t04t3qa.log

cargo clippy --workspace --all-targets --features dylib -- -D warnings > loop\reports\gate-clippy-t04t3qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-clippy-t04t3qa.log

cargo doc --locked --workspace --document-private-items --no-deps > loop\reports\gate-doc-t04t3qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-doc-t04t3qa.log

cargo xtask fast > loop\reports\gate-xtask-fast-t04t3qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-xtask-fast-t04t3qa.log

cargo xtask integration > loop\reports\gate-xtask-integration-t04t3qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-xtask-integration-t04t3qa.log

cargo test --locked --workspace --doc --features dylib --no-fail-fast > loop\reports\gate-doctests-t04t3qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-doctests-t04t3qa.log

cargo test --locked -p jackdaw_bind --doc --features dylib > loop\reports\gate-doctests-bind-t04t3qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-doctests-bind-t04t3qa.log

echo ALLDONE
