# T11-T2 QA acceptance: independent sampling of the claimed PIE death.
# The implementer claims >=10 play attempts all died 0xc0000005 before
# 'connected' (both windowless and windowed forms), attributing it to the
# T10b-pinned driver state (nvcuda64.dll @ 0x3ab984, driver 591.86). This
# script independently tries 3 plays (2 windowless + 1 windowed); if any
# connects, it holds the window open for the N13 observation (drain panic
# after ~2s) and records 'window recovered' honestly. Windows Error Report
# events (Id 1000) raised after the run start are dumped and matched
# against the nvcuda64/0x3ab984 signature.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t11t2-qa-pie.ps1
param(
    [string]$Project = 'H:\workspace_AI\t11-live\t11t1-game',
    [int]$Port = 15807,
    [int]$GamePort = 15702
)
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$QaDir = Join-Path $Repo 'loop\qa'
$Exe = Join-Path $Repo 'target\debug\jackdaw.exe'
if (-not (Test-Path $Exe)) { Write-Host 'EXE_MISSING'; exit 1 }
$editorLog = Join-Path $QaDir 't11t2-qa-pie-editor.log'
$runStart = Get-Date

function Brp([string]$method, $params, [int]$retries = 3) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 12)
        } catch { Start-Sleep -Milliseconds (300 * ($i + 1)) }
    }
    return $null
}
function Op([string]$id, $params) {
    if ($params) { Brp 'jackdaw/call_operator' @{ id = $id; params = $params } }
    else { Brp 'jackdaw/call_operator' @{ id = $id } }
}
function Wait-Idle([int]$TimeoutSec = 120) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Brp 'jackdaw/wait' @{ until = 'idle' } 1
        if ($r -and $r.result -and $r.result.idle) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}
function Log-Tail([long]$fromLen) {
    if (-not (Test-Path $editorLog)) { return '' }
    $txt = [IO.File]::ReadAllText($editorLog)
    if ($txt.Length -le $fromLen) { return '' }
    return $txt.Substring($fromLen)
}
function Log-Len {
    if (Test-Path $editorLog) { return (Get-Item $editorLog).Length }
    return 0
}

# --- boot ---------------------------------------------------------------------------
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 800
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_WINDOW_SIZE = '1920x1080'
$env:RUST_BACKTRACE = '1'
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
cmd /c "start /B /D `"$(Split-Path -Parent $Exe)`" cmd /c `"`"$Exe`" > `"$editorLog`" 2>`&1`""
$ready = $false
for ($i = 0; $i -lt 150; $i++) { Start-Sleep -Seconds 2; if (Brp 'jackdaw/status' @{} 1) { $ready = $true; break } }
if (-not $ready) { Write-Host 'EDITOR_BOOT_FAIL'; exit 1 }
Wait-Idle 1200; Start-Sleep -Seconds 3
$st0 = (Brp 'jackdaw/status' @{} 2).result
if ($st0 -and $st0.dialog) {
    Write-Host ("boot dialog up: {0}" -f ($st0.dialog | ConvertTo-Json -Depth 3 -Compress))
    Op 'dialog.answer' @{ choice = '0' } | Out-Null
    Start-Sleep -Seconds 2
}
$schemaJson = Join-Path $Project '.jackdaw\schema.json'
if (Test-Path $schemaJson) {
    (Get-Item $schemaJson).LastWriteTime = Get-Date
    Start-Sleep -Seconds 6
}
Op 'scene.open' @{ path = 'assets/t11t2-place.bsn' } | Out-Null
Wait-Idle 90; Start-Sleep -Seconds 2

# --- three play attempts ------------------------------------------------------------
$playResults = @()
$windowed = $false
for ($n = 1; $n -le 3; $n++) {
    if ($n -eq 3) {
        # last attempt in the windowed fallback form (probe2 form)
        $w = Op 'pie.window_mode_toggle' @{}
        $windowed = $true
        Write-Host ("play #3 windowed toggle: {0}" -f ($w | ConvertTo-Json -Depth 3 -Compress))
        Start-Sleep -Seconds 1
    }
    $len0 = Log-Len
    Op 'pie.play_current' @{} | Out-Null
    $outcome = 'timeout'; $exitCode = ''
    $deadline = (Get-Date).AddSeconds(150)
    while ((Get-Date) -lt $deadline) {
        $tail = Log-Tail $len0
        if ($tail -match 'exited before connecting with exit code:\s*(0x[0-9a-fA-F]+)') {
            $outcome = 'crashed'; $exitCode = $Matches[1]; break
        }
        if ($tail -match 'PIE:.*connected') { $outcome = 'connected'; break }
        Start-Sleep -Milliseconds 700
    }
    $n13 = 'n/a'
    if ($outcome -eq 'connected') {
        # N13 observation window: drain_game_events swap_remove panic ~2s after connect
        Start-Sleep -Seconds 12
        $tail = Log-Tail $len0
        if ($tail -match 'swap_remove|panicked|drain_game_events') { $n13 = ('signal: ' + $Matches[0]) }
        else { $n13 = 'no drain panic in 12s' }
        $g = $null
        try { $g = Invoke-RestMethod -Uri "http://127.0.0.1:$GamePort/" -Method Post -ContentType 'application/json' -TimeoutSec 10 -Body '{"jsonrpc":"2.0","id":1,"method":"jackdaw/status"}' } catch {}
        Write-Host ("  game 15702: {0}" -f $(if ($g) { 'ANSWERS' } else { 'silent' }))
    }
    Write-Host ("PLAY#{0} form={1} outcome={2} exit={3} n13={4}" -f $n, $(if ($windowed) { 'windowed' } else { 'windowless' }), $outcome, $exitCode, $n13)
    $playResults += @{ n = $n; form = $(if ($windowed) { 'windowed' } else { 'windowless' }); outcome = $outcome; exitCode = $exitCode; n13 = $n13 }
    # settle: stop PIE if anything is running, wait for stopped before next round
    foreach ($attempt in 1..4) {
        Op 'pie.stop' | Out-Null
        $st = (Brp 'jackdaw/status' @{} 1).result
        if ($st -and "$($st.pie)" -eq 'stopped') { break }
        Start-Sleep -Seconds 2
    }
    Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    Start-Sleep -Seconds 3
}
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }

# --- Windows Error Report cross-check (T10b signature: nvcuda64.dll @ 0x3ab984) -----
Write-Host '---- WER events since run start ----'
$wer = @()
try {
    $evts = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000; StartTime = $runStart } -ErrorAction SilentlyContinue
    foreach ($ev in @($evts)) {
        $msg = $ev.Message
        $app = ''; $mod = ''; $code = ''; $off = ''
        if ($msg -match '错误应用程序名称:\s*(\S+)') { $app = $Matches[1] }
        elseif ($msg -match 'Faulting application name:\s*(\S+)') { $app = $Matches[1] }
        if ($msg -match '错误模块名称:\s*(\S+)') { $mod = $Matches[1] }
        elseif ($msg -match 'Faulting module name:\s*(\S+)') { $mod = $Matches[1] }
        if ($msg -match '异常代码:\s*(\S+)') { $code = $Matches[1] }
        elseif ($msg -match 'Exception code:\s*(\S+)') { $code = $Matches[1] }
        if ($msg -match '故障偏移:\s*(\S+)') { $off = $Matches[1] }
        elseif ($msg -match 'Fault offset:\s*(\S+)') { $off = $Matches[1] }
        Write-Host ("WER {0:HH:mm:ss} app={1} module={2} code={3} offset={4}" -f $ev.TimeCreated, $app, $mod, $code, $off)
        $wer += @{ app = $app; module = $mod; code = $code; offset = $off }
    }
    if (-not $evts) { Write-Host 'WER: no Id=1000 events since run start' }
} catch { Write-Host ("WER query failed: {0}" -f $_.Exception.Message) }

# --- summary ------------------------------------------------------------------------
$crashes = @($playResults | Where-Object { $_.outcome -eq 'crashed' })
$connected = @($playResults | Where-Object { $_.outcome -eq 'connected' })
$sig = @($wer | Where-Object { "$($_.module)" -match 'nvcuda64' })
$summary = ("plays={0} crashed={1} connected={2} werNvcuda={3}" -f @($playResults).Count, @($crashes).Count, @($connected).Count, @($sig).Count)
[IO.File]::WriteAllText((Join-Path $QaDir 't11t2-qa-pie-summary.txt'), ($summary + "`r`n" + (($playResults | ForEach-Object { "play#{0} {1} {2} {3} n13={4}" -f $_.n, $_.form, $_.outcome, $_.exitCode, $_.n13 }) -join "`r`n") + "`r`n" + (($wer | ForEach-Object { "wer app={0} module={1} code={2} offset={3}" -f $_.app, $_.module, $_.code, $_.offset }) -join "`r`n") + "`r`n"))
Write-Host ("VERDICT_QA_PIE: {0}" -f $summary)
Write-Host 'T11T2_QA_PIE_DONE'
