# T11-T2 N13 recurrence measurement: PIE connected x10 back-to-back runs
# with RUST_BACKTRACE=1, per the buglist N13 fix direction ("PIE connected
# x10 to pin the recurrence rate + a real backtrace"). No fix here -- data
# only. Each round: play -> wait connected -> hold >=25s (the original hit
# came 1.9s after connect) -> stop -> settle -> scan the editor log for the
# swap_remove panic. A driver-state (0x8007000E / DX12 OOM) round is logged
# and skipped, not counted as code. All rounds run the default backend
# (Vulkan); WGPU_BACKEND is never set (dx12 OOM is the known driver state).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t11t2-n13.ps1
param(
    [string]$Project = 'H:\workspace_AI\t11-live\t11t1-game',
    [int]$Port = 15804
)
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$OutDir = Join-Path $Repo 'loop\t11t2-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$Exe = Join-Path $Repo 'target\debug\jackdaw.exe'
if (-not (Test-Path $Exe)) { Write-Host 'EXE_MISSING'; exit 1 }

function Brp([string]$method, $params, [int]$retries = 3) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 10)
        } catch { Start-Sleep -Milliseconds (300 * ($i + 1)) }
    }
    return $null
}
function Op([string]$id, $params) {
    if ($params) { Brp 'jackdaw/call_operator' @{ id = $id; params = $params } }
    else { Brp 'jackdaw/call_operator' @{ id = $id } }
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 800
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_WINDOW_SIZE = '1920x1080'
$env:RUST_BACKTRACE = '1'
$editorLog = Join-Path $OutDir 't11t2-n13-editor.log'
if (Test-Path $editorLog) { Remove-Item $editorLog -Force }
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
cmd /c "start /B /D `"$(Split-Path -Parent $Exe)`" cmd /c `"`"$Exe`" > `"$editorLog`" 2>`&1`""
$ready = $false
for ($i = 0; $i -lt 150; $i++) {
    Start-Sleep -Seconds 2
    if (Brp 'jackdaw/status' @{} 1) { $ready = $true; break }
}
if (-not $ready) { Write-Host 'EDITOR_BOOT_FAIL'; exit 1 }
# settle: let the background prebuild finish so round timings are clean
$deadline = (Get-Date).AddSeconds(900)
while ((Get-Date) -lt $deadline) {
    $r = Brp 'jackdaw/wait' @{ until = 'idle' } 1
    if ($r -and $r.result -and $r.result.idle) { break }
    Start-Sleep -Seconds 2
}
Start-Sleep -Seconds 5
Write-Host ("N13 editor ready {0:HH:mm:ss}" -f (Get-Date))

$hits = 0; $clean = 0; $skipped = 0
$logBase = [IO.File]::ReadAllText($editorLog).Length
for ($round = 1; $round -le 10; $round++) {
    $t0 = Get-Date
    Op 'pie.play' @{} | Out-Null
    # connected: the editor log records "PIE: Play #N connected"; running
    # status is the BRP face of the same thing. Wait for either.
    $connectedAt = $null
    $deadline = (Get-Date).AddSeconds(180)
    while ((Get-Date) -lt $deadline) {
        $txt = ''
        if (Test-Path $editorLog) { $txt = [IO.File]::ReadAllText($editorLog) }
        if ($txt -match "Play #$round connected") { $connectedAt = Get-Date; break }
        $st = (Brp 'jackdaw/status' @{} 1).result
        if ($st -and "$($st.pie)" -eq 'running') { $connectedAt = Get-Date; break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $connectedAt) {
        $txt = ''
        if (Test-Path $editorLog) { $txt = [IO.File]::ReadAllText($editorLog) }
        if ($txt -match '0x8007000E|Queue creation failed') {
            Write-Host ("N13 round {0}: DRIVER_STATE (OOM signature), skipped" -f $round)
            $skipped++
        } else {
            Write-Host ("N13 round {0}: NEVER_CONNECTED, skipped" -f $round)
            $skipped++
        }
        Op 'pie.stop' | Out-Null
        Start-Sleep -Seconds 3
        continue
    }
    # hold the connection window open (>=25s past connect)
    Start-Sleep -Seconds 25
    $txt = ''
    if (Test-Path $editorLog) { $txt = [IO.File]::ReadAllText($editorLog) }
    $seg = $txt.Substring([Math]::Min($logBase, $txt.Length))
    $hit = ($seg -match 'swap_remove') -or ($seg -match 'panicked at') -or ($seg -match 'drain_game_events')
    # stop and settle
    $stopped = $false
    foreach ($attempt in 1..4) {
        Op 'pie.stop' | Out-Null
        $dl = (Get-Date).AddSeconds(20)
        while ((Get-Date) -lt $dl) {
            $st = (Brp 'jackdaw/status' @{} 1).result
            if ($st -and "$($st.pie)" -eq 'stopped') { $stopped = $true; break }
            Start-Sleep -Milliseconds 300
        }
        if ($stopped) { break }
    }
    if ($hit) {
        $hits++
        $arc = Join-Path $Repo ("loop\reports\t11t2_n13_hit_round{0}.log" -f $round)
        [IO.File]::WriteAllText($arc, $txt)
        Write-Host ("N13 round {0}: PANIC HIT (archived {1})" -f $round, (Split-Path -Leaf $arc))
    } else {
        $clean++
        Write-Host ("N13 round {0}: clean (connected {1:HH:mm:ss}, held 25s, stopped={2})" -f $round, $connectedAt, $stopped)
    }
    # the editor keeps running; the panic (if any) does not kill it (bevy's
    # handler catches), so the next round starts from the same process.
    $logBase = $txt.Length
    Start-Sleep -Seconds 2
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
$rate = if (($hits + $clean) -gt 0) { [Math]::Round(100.0 * $hits / ($hits + $clean), 1) } else { 'n/a' }
$line = "N13_RECURRENCE: hits=$hits clean=$clean skipped=$skipped rate=$rate% (10 attempted, RUST_BACKTRACE=1, default Vulkan backend)"
Write-Host $line
[IO.File]::WriteAllText((Join-Path $OutDir 't11t2-n13-summary.txt'), "$line`r`n")
# archive the full editor log either way (the recurrence data's provenance)
Copy-Item $editorLog (Join-Path $Repo 'loop\reports\t11t2_n13_editor_full.log') -Force
Write-Host 'T11T2_N13_DONE'
