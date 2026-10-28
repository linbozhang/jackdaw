# T10b QA round 2: re-run cell A (Start-Process+Redirect, Vulkan) twice-flag check,
# and cell E (Start-Process+Redirect+WGPU_BACKEND=dx12) with stderr capture.
$ErrorActionPreference = 'Continue'
$proj  = 'H:\workspace_AI\t10-phys\phys-game'
$exe   = 'H:\workspace_AI\t10-phys\phys-game\target\debug\phys-game.exe'
$qaDir = 'H:\workspace_AI\t10b-qa'

function NewCrashesSince([datetime]$t) {
  $e = @(Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000; StartTime=$t.AddSeconds(-1)} -ErrorAction SilentlyContinue)
  $colon = [char[]]@(0x3A, 0xFF1A); $comma = [char[]]@(0x2C, 0xFF0C)
  foreach ($x in $e) {
    $ln = $x.Message -split "`r?`n"
    $app='?';$mod='?';$code='?';$off='?'
    try {
      $app  = ((($ln[0].Split($colon,2))[1]).Split($comma,2))[0].Trim()
      $mod  = ((($ln[1].Split($colon,2))[1]).Split($comma,2))[0].Trim()
      $code = (($ln[2].Split($colon,2))[1]).Trim()
      $off  = (($ln[3].Split($colon,2))[1]).Trim()
    } catch {}
    "{0:yyyy-MM-dd HH:mm:ss} | app={1} | mod={2} | code={3} | off={4}" -f $x.TimeCreated,$app,$mod,$code,$off
  }
}

"START {0:yyyy-MM-dd HH:mm:ss}" -f (Get-Date)
$pre = @(Get-Process phys-game -ErrorAction SilentlyContinue)
"pre-existing phys-game: $($pre.Count)"; if ($pre.Count -gt 0) { "ABORT"; exit 1 }

# --- R2a: cell A replica, second run ---
"== R2a (A replica run 2: Start-Process + Redirect, Vulkan) =="
$t = Get-Date
$p = Start-Process -FilePath $exe -WorkingDirectory $proj -PassThru -RedirectStandardOutput "$qaDir\r2a-out.log" -RedirectStandardError "$qaDir\r2a-err.log"
$exited = $p.WaitForExit(45000)
if (-not $exited) { "R2a RESULT: ALIVE after 45s"; Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; "R2a killed pid=$($p.Id)" }
else { "R2a RESULT: EXITED ExitCode={0:X8}" -f ([uint32]($p.ExitCode)) }
Start-Sleep 3
"R2a event-log rows:"; NewCrashesSince $t | ForEach-Object { "  $_" }
"R2a adapter line:"; Select-String -Path "$qaDir\r2a-err.log","$qaDir\r2a-out.log" -Pattern 'AdapterInfo' -SimpleMatch | ForEach-Object { "  $($_.Line)" }

# --- R2b: cell E replica with stderr capture ---
""
"== R2b (E replica: Start-Process + Redirect + WGPU_BACKEND=dx12) =="
$t = Get-Date
$env:WGPU_BACKEND = 'dx12'
$p = Start-Process -FilePath $exe -WorkingDirectory $proj -PassThru -RedirectStandardOutput "$qaDir\r2b-out.log" -RedirectStandardError "$qaDir\r2b-err.log"
$exited = $p.WaitForExit(45000)
if (-not $exited) { "R2b RESULT: ALIVE after 45s"; Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; "R2b killed pid=$($p.Id)" }
else { "R2b RESULT: EXITED ExitCode={0:X8}" -f ([uint32]($p.ExitCode)) }
Remove-Item Env:\WGPU_BACKEND -ErrorAction SilentlyContinue
Start-Sleep 3
"R2b event-log rows:"; NewCrashesSince $t | ForEach-Object { "  $_" }
"R2b adapter line:"; Select-String -Path "$qaDir\r2b-err.log","$qaDir\r2b-out.log" -Pattern 'AdapterInfo' -SimpleMatch | ForEach-Object { "  $($_.Line)" }
"R2b stderr tail (10):"
if (Test-Path "$qaDir\r2b-err.log") { Get-Content "$qaDir\r2b-err.log" -Tail 10 | ForEach-Object { "  | $_" } }

$left = @(Get-Process phys-game -ErrorAction SilentlyContinue)
"final sweep phys-game remaining: $($left.Count)"
"END {0:yyyy-MM-dd HH:mm:ss}" -f (Get-Date)
