@echo off
cd /d E:\Project\rust\jackdaw
set PATH=%PATH%;C:\Users\linbo.zhang\.cargo\bin

echo === gate 1: cargo fmt --all -- --check ===
cargo fmt --all -- --check > loop\reports\gate-fmt-r1b-fix1.log 2>&1
echo FMT_EXITCODE=%ERRORLEVEL%

echo === gate 2: cargo clippy --workspace --all-targets --features dylib -- -D warnings ===
cargo clippy --workspace --all-targets --features dylib -- -D warnings > loop\reports\gate-clippy-r1b-fix1.log 2>&1
echo CLIPPY_EXITCODE=%ERRORLEVEL%

echo === gate 3: cargo xtask fast ===
cargo xtask fast > loop\reports\gate-xtask-fast-r1b-fix1.log 2>&1
echo FAST_EXITCODE=%ERRORLEVEL%

echo === gate 4: cargo xtask integration ===
cargo xtask integration > loop\reports\gate-xtask-integration-r1b-fix1.log 2>&1
echo INTEGRATION_EXITCODE=%ERRORLEVEL%

echo === all gates done ===
