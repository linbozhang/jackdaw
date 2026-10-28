# adjudicate the 9 integration failures on clean main (worktree).
$wt = 'E:\Project\rust\jd-t3check'
Set-Location $wt
$log = 'E:\Project\rust\jackdaw\loop\reports\t10t3_main_baseline_9tests.log'
Remove-Item $log -ErrorAction SilentlyContinue
foreach ($suite in @('sdk_layout', 'operators', 'viewport', 'stage', 'sdk_feature_superset')) {
    cargo test --test $suite *>> $log
}
"FINAL_EXIT=$LASTEXITCODE" | Out-File $log -Append
Select-String -Path $log -Pattern 'running \d+ tests|test result:' | ForEach-Object Line
