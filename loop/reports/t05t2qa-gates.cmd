@echo off
cd /d E:\Project\rust\jackdaw
echo START %DATE% %TIME%

cargo test --test guards reference_audit > loop\reports\gate-guards-refaudit-t05t2qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-guards-refaudit-t05t2qa.log
echo GUARDS-REFAUDIT DONE %DATE% %TIME%

cargo test --lib reference_audit > loop\reports\gate-lib-refaudit-t05t2qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-lib-refaudit-t05t2qa.log
echo LIB-REFAUDIT DONE %DATE% %TIME%

cargo test --test guards reference_rewrite > loop\reports\gate-guards-refrewrite-t05t2qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-guards-refrewrite-t05t2qa.log
echo GUARDS-REFREWRITE DONE %DATE% %TIME%

cargo clippy --workspace --all-targets -- -D warnings > loop\reports\gate-clippy-alltargets-t05t2qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-clippy-alltargets-t05t2qa.log
echo CLIPPY-ALLTARGETS DONE %DATE% %TIME%

echo ALLDONE %DATE% %TIME%
