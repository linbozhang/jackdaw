# grid 1: the fresh scaffolded mygame exe runs standalone (detached).
$exe = 'C:\Users\linbo.zhang\AppData\Local\Temp\jackdaw_scaffold_e2e_69b367145f9ac515\75b430dc9c11d9ee\mygame\.jackdaw\target\game\debug\mygame.exe'
Write-Host ("exe: {0}" -f $exe)
$dir = Split-Path $exe
$deps = Join-Path $dir 'deps'
if (Test-Path $deps) { $env:PATH = "$deps;$env:PATH" }
$log = 'E:\Project\rust\jackdaw\loop\t10t3-live\grid1-mygame-run.log'
cmd /c "start /B /D `"$dir`" cmd /c `"`"$exe`" > `"$log`" 2>&1`""
Start-Sleep -Seconds 10
$p = Get-Process mygame -ErrorAction SilentlyContinue
if ($p) {
    Write-Host ("GRID1_EXE_ALIVE_PASS: pid={0} window={1}" -f $p.Id, ($p.MainWindowTitle))
    Stop-Process -Id $p.Id -Force
} else {
    Write-Host 'GRID1_EXE_DEAD (see log)'
    if (Test-Path $log) { Get-Content $log -Tail 6 | ForEach-Object { $_ } }
}
Start-Sleep -Milliseconds 500
Get-Process mygame -ErrorAction SilentlyContinue | Stop-Process -Force
