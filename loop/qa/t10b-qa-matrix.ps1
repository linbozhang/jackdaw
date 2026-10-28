# T10b QA: live spot-check of 3 matrix cells (pure ASCII to avoid PS5.1 encoding issues)
#   CELL 1 = A  : PS Start-Process + Redirect, default Vulkan -> expect CRASH
#   CELL 2 = C  : cmd start /B + file redirect, default Vulkan -> expect ALIVE
#   CELL 3 = E  : PS Start-Process + WGPU_BACKEND=dx12 -> expect ALIVE
$ErrorActionPreference = 'Continue'
$proj  = 'H:\workspace_AI\t10-phys\phys-game'
$exe   = 'H:\workspace_AI\t10-phys\phys-game\target\debug\phys-game.exe'
$qaDir = 'H:\workspace_AI\t10b-qa'
$colon = [char[]]@(0x3A, 0xFF1A)
$comma = [char[]]@(0x2C, 0xFF0C)
New-Item -ItemType Directory -Force -Path $qaDir | Out-Null

function NewCrashesSince([datetime]$t) {
  $e = @(Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000; StartTime=$t.AddSeconds(-1)} -ErrorAction SilentlyContinue)
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
function ProbeBrp([int]$port) {
  try {
    $r = Invoke-WebRequest -Uri ("http://127.0.0.1:{0}/" -f $port) -Method GET -TimeoutSec 3 -UseBasicParsing
    return "HTTP {0}" -f $r.StatusCode
  } catch {
    if ($_.Exception.Response) { return "HTTP {0} (server responding)" -f [int]$_.Exception.Response.StatusCode }
    return "no response"
  }
}

"START {0:yyyy-MM-dd HH:mm:ss}" -f (Get-Date)
"exe = $exe"
"exe exists: $(Test-Path $exe)"

$pre = @(Get-Process phys-game -ErrorAction SilentlyContinue)
"pre-existing phys-game processes: $($pre.Count)"
if ($pre.Count -gt 0) { $pre | ForEach-Object { "  pid=$($_.Id) path=$($_.Path)" } ; "ABORT: clean env required"; exit 1 }

# ---------------- CELL 1 ----------------
"== CELL 1 (A: PS Start-Process + Redirect, Vulkan default) =="
$t0 = Get-Date
$p1 = Start-Process -FilePath $exe -WorkingDirectory $proj -PassThru -RedirectStandardOutput "$qaDir\c1-out.log" -RedirectStandardError "$qaDir\c1-err.log"
$exited = $p1.WaitForExit(90000)
if (-not $exited) {
  "CELL1 RESULT: STILL ALIVE after 90s (UNEXPECTED)"
  Stop-Process -Id $p1.Id -Force -ErrorAction SilentlyContinue
} else {
  "CELL1 RESULT: EXITED. ExitCode={0:X8} (int {1})" -f ([uint32]($p1.ExitCode)), $p1.ExitCode
}
Start-Sleep -Seconds 4
"CELL1 event-log rows since launch:"
NewCrashesSince $t0 | ForEach-Object { "  $_" }
if (Test-Path "$qaDir\c1-err.log") {
  "CELL1 stderr tail (last 5 lines):"
  Get-Content "$qaDir\c1-err.log" -Tail 5 | ForEach-Object { "  | $_" }
} else { "CELL1 stderr file missing" }

# ---------------- CELL 2 ----------------
""
"== CELL 2 (C: cmd start /B + file redirect, Vulkan default) =="
$t2 = Get-Date
$bat = "$qaDir\grid2.cmd"
Set-Content -Path $bat -Value ('start /B /D {0} cmd /c "{1} > {2}\c2-out.log 2>&1"' -f $proj, $exe, $qaDir) -Encoding ASCII
cmd /c $bat
Start-Sleep -Seconds 60
$procs2 = @(Get-Process phys-game -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe })
"CELL2 RESULT: alive processes for this exe: $($procs2.Count)"
$procs2 | ForEach-Object { "  pid=$($_.Id) start=$($_.StartTime.ToString('HH:mm:ss'))" }
if (Test-Path "$qaDir\c2-out.log") {
  $marker = Select-String -Path "$qaDir\c2-out.log" -Pattern 'Creating new window' -SimpleMatch
  "CELL2 out.log: lines=$((Get-Content "$qaDir\c2-out.log").Count) 'Creating new window' present=$([bool]$marker)"
  "CELL2 out.log tail:"
  Get-Content "$qaDir\c2-out.log" -Tail 4 | ForEach-Object { "  | $_" }
} else { "CELL2 out.log MISSING" }
"CELL2 BRP probe (127.0.0.1:15702): $(ProbeBrp 15702)"
"CELL2 event-log rows since launch (expect none):"
NewCrashesSince $t2 | ForEach-Object { "  $_" }
foreach ($pr in $procs2) { Stop-Process -Id $pr.Id -Force -ErrorAction SilentlyContinue }
"CELL2 cleanup: killed $($procs2.Count) process(es)"

# ---------------- CELL 3 ----------------
""
"== CELL 3 (E: PS Start-Process + WGPU_BACKEND=dx12) =="
$t3 = Get-Date
$env:WGPU_BACKEND = 'dx12'
$p3 = Start-Process -FilePath $exe -WorkingDirectory $proj -PassThru
Start-Sleep -Seconds 60
$p3.Refresh()
$alive3 = -not $p3.HasExited
"CELL3 RESULT: alive after 60s: $alive3 (pid=$($p3.Id))"
if ($alive3) {
  "CELL3 BRP probe (127.0.0.1:15702): $(ProbeBrp 15702)"
  Stop-Process -Id $p3.Id -Force -ErrorAction SilentlyContinue
  "CELL3 cleanup: killed pid=$($p3.Id)"
} else {
  "CELL3 ExitCode={0:X8}" -f ([uint32]($p3.ExitCode))
}
Remove-Item Env:\WGPU_BACKEND -ErrorAction SilentlyContinue
"CELL3 event-log rows since launch (expect none):"
NewCrashesSince $t3 | ForEach-Object { "  $_" }

# ---------------- FINAL SWEEP ----------------
""
"== FINAL PROCESS SWEEP =="
Start-Sleep -Seconds 2
$left = @(Get-Process phys-game -ErrorAction SilentlyContinue)
"phys-game processes remaining: $($left.Count)"
$left | ForEach-Object { "  pid=$($_.Id) path=$($_.Path)" }
"END {0:yyyy-MM-dd HH:mm:ss}" -f (Get-Date)
