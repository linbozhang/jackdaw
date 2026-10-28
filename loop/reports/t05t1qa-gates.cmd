@echo off
cd /d E:\Project\rust\jackdaw
echo START %DATE% %TIME%

cargo fmt --all -- --check > loop\reports\gate-fmt-t05t1qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-fmt-t05t1qa.log
echo FMT DONE %DATE% %TIME%

cargo clippy --workspace -- -D warnings > loop\reports\gate-clippy-t05t1qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-clippy-t05t1qa.log
echo CLIPPY DONE %DATE% %TIME%

cargo clippy --workspace --all-targets -- -D warnings > loop\reports\gate-clippy-alltargets-t05t1qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-clippy-alltargets-t05t1qa.log
echo CLIPPY-ALLTARGETS DONE %DATE% %TIME%

cargo test --workspace --lib > loop\reports\gate-lib-t05t1qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-lib-t05t1qa.log
echo LIB DONE %DATE% %TIME%

cargo test --test guards > loop\reports\gate-guards-full-t05t1qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-guards-full-t05t1qa.log
echo GUARDS-FULL DONE %DATE% %TIME%

cargo test --test guards reference_rewrite > loop\reports\gate-guards-refrewrite-t05t1qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-guards-refrewrite-t05t1qa.log
echo GUARDS-REFREWRITE DONE %DATE% %TIME%

cargo test --test guards the_journal_write_costs_no_more_than_five_milliseconds > loop\reports\gate-guards-journal-1-t05t1qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-guards-journal-1-t05t1qa.log
echo JOURNAL-1 DONE %DATE% %TIME%

cargo test --test guards the_journal_write_costs_no_more_than_five_milliseconds > loop\reports\gate-guards-journal-2-t05t1qa.log 2>&1
echo EXIT:%ERRORLEVEL% >> loop\reports\gate-guards-journal-2-t05t1qa.log
echo JOURNAL-2 DONE %DATE% %TIME%

echo ALLDONE %DATE% %TIME%
