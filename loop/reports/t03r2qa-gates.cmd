@echo off
cd /d E:\Project\rust\jackdaw
cargo fmt --all -- --check > loop\reports\gate-fmt-t03r2qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-fmt-t03r2qa.log
cargo clippy --workspace --all-targets --features dylib -- -D warnings > loop\reports\gate-clippy-t03r2qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-clippy-t03r2qa.log
echo ALLDONE
