# T10b QA round 3: E-form (dx12) re-run with a clean settle window (30s idle, no prior game process)
$ErrorActionPreference = 'Continue'
$proj  = 'H:\workspace_AI\t10-phys\phys-game'
$exe   = 'H:\workspace_AI\t10-phys\phys-game\target\debug\phys-game.exe'
$qaDir = 'H:\workspace_AI\t10b-qa'
"START {0:yyyy-MM-dd HH:mm:ss}" -f (Get-Date)
$pre = @(Get-Process phys-game -ErrorAction SilentlyContinue)
"pre-existing phys-game: $($pre.Count)"
"settling 30s ..."; Start-Sleep -Seconds 30
$t = Get-Date
$env:WGPU_BACKEND = 'dx12'
$p = Start-Process -FilePath $exe -WorkingDirectory $proj -PassThru -RedirectStandardOutput "$qaDir\r3-out.log" -RedirectStandardError "$qaDir\r3-err.log"
$exited = $p.WaitForExit(45000)
if (-not $exited) { "R3 RESULT: ALIVE after 45s (dx12 form usable right now)"; Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; "R3 killed pid=$($p.Id)" }
else { "R3 RESULT: EXITED ExitCode={0:X8}" -f ([uint32]($p.ExitCode)) }
Remove-Item Env:\WGPU_BACKEND -ErrorAction SilentlyContinue
Start-Sleep 3
$e = @(Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000; StartTime=$t.AddSeconds(-1)} -ErrorAction SilentlyContinue)
"R3 new Id=1000 rows: $($e.Count)"
"R3 adapter line:"; Select-String -Path "$qaDir\r3-err.log","$qaDir\r3-out.log" -Pattern 'AdapterInfo','Queue creation failed','panicked' | ForEach-Object { "  $($_.Line)" }
$left = @(Get-Process phys-game -ErrorAction SilentlyContinue)
"final sweep phys-game remaining: $($left.Count)"
"END {0:yyyy-MM-dd HH:mm:ss}" -f (Get-Date)
