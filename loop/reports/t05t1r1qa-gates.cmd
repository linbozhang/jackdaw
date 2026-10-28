@echo off
cd /d E:\Project\rust\jackdaw
echo START %DATE% %TIME%

cargo test --test guards reference_rewrite > loop\reports\gate-guards-refrewrite-t05t1r1qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-guards-refrewrite-t05t1r1qa.log
echo REFREWRITE DONE %DATE% %TIME%

cargo clippy --workspace --all-targets -- -D warnings > loop\reports\gate-clippy-alltargets-t05t1r1qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-clippy-alltargets-t05t1r1qa.log
echo CLIPPY-ALLTARGETS DONE %DATE% %TIME%

echo ALLDONE %DATE% %TIME%
