# T08-T1 QA: the behavior leg the program could not run headless —
# scene_snapshot two-frame difference while PIE runs, on my-game (a
# healthy-lock project), with a visible editor window.
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$Exe  = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Port = 15741

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500

$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
$env:JACKDAW_WINDOW_SIZE  = '1600x900'
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$stamp = Get-Date -Format 'HHmmss'
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru `
    -RedirectStandardOutput "$env:TEMP\qa-t08-behavior-$stamp-out.log" `
    -RedirectStandardError "$env:TEMP\qa-t08-behavior-$stamp-err.log"

function Brp([string]$method, $params) {
    $body = @{ jsonrpc = '2.0'; id = (Get-Random); method = $method }
    if ($params) { $body.params = $params }
    Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' `
        -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 8)
}
function Op([string]$id, $params) { (Brp 'jackdaw/call_operator' @{ id = $id; params = $params }).result }
function Pie-Status { (Brp 'jackdaw/status' @{}).result.pie }

# ready + idle
$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline) {
    try { Brp 'jackdaw/status' @{} | Out-Null; break } catch { Start-Sleep -Milliseconds 500 }
}
$deadline = (Get-Date).AddSeconds(600)
while ((Get-Date) -lt $deadline) {
    $r = (Brp 'jackdaw/wait' @{ until = 'idle' }) | Out-Null
    break
}
Write-Host 'editor ready (visible window)'

# play the current scene
Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
Start-Sleep -Seconds 2
Op 'pie.play_current' | Out-Null
$deadline = (Get-Date).AddSeconds(300)
while ((Get-Date) -lt $deadline -and (Pie-Status) -ne 'running') { Start-Sleep -Milliseconds 300 }
Write-Host ("pie running: {0}" -f (Pie-Status))
Start-Sleep -Seconds 2

# the behavior leg: two scene_snapshot reads, a second apart, differ
function Snap-Text {
    $r = Brp 'jackdaw/scene_snapshot' @{}
    if ($null -eq $r.result) { return $null }
    ($r.result | ConvertTo-Json -Depth 14 -Compress)
}
$s1 = Snap-Text
Start-Sleep -Seconds 2
$s2 = Snap-Text
$s3 = $null
if ($s1 -eq $null -or $s2 -eq $null) {
    # watching-pending form: poll a few times for a non-null result
    foreach ($i in 1..10) {
        Start-Sleep -Seconds 2
        $s3 = Snap-Text
        if ($s3) { break }
    }
}
$len1 = if ($s1) { $s1.Length } else { -1 }
$len2 = if ($s2) { $s2.Length } else { -1 }
$len3 = if ($s3) { $s3.Length } else { -1 }
Write-Host ("snapshot lens: s1={0} s2={1} s3(polled)={2}" -f $len1, $len2, $len3)
if ($s1 -and $s2) {
    Write-Host ("two snapshots differ: {0}" -f ($s1 -cne $s2))
    # sample the first divergence region for the record
    if ($s1 -cne $s2) {
        $min = [Math]::Min($s1.Length, $s2.Length)
        for ($i = 0; $i -lt $min; $i++) {
            if ($s1[$i] -ne $s2[$i]) {
                $from = [Math]::Max(0, $i - 40)
                Write-Host ("first diff at char {0}: ...{1}... vs ...{2}..." -f $i, $s1.Substring($from, [Math]::Min(100, $s1.Length-$from)), $s2.Substring($from, [Math]::Min(100, $s2.Length-$from)))
                break
            }
        }
        Write-Host 'BEHAVIOR_LEG_DIFF_PASS'
    } else { Write-Host 'BEHAVIOR_LEG_SAME_FAIL (two frames identical)' }
} elseif ($s3) {
    Write-Host 'snapshot only answered after polling (watching-pending shape)'
} else {
    Write-Host 'BEHAVIOR_LEG_BLOCKED (snapshot never returned data even in a visible window)'
}

# stop and cleanup
Op 'pie.stop' | Out-Null
$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline -and (Pie-Status) -ne 'stopped') { Start-Sleep -Milliseconds 200 }
Write-Host ("pie stopped: {0}" -f (Pie-Status))
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Write-Host 'T08_QA_BEHAVIOR_DONE'
