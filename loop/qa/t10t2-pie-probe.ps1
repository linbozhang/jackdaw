# Minimal PIE probe: does the game connect under windowless PIE?
$ErrorActionPreference = 'Continue'
$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'H:\workspace_AI\t10-phys\phys-game'
$Port    = 15704
$OutDir  = Join-Path $Repo 'loop\t10t2-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Brp-Try([string]$method, $params, [int]$retries = 6) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = (Get-Random); method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 10)
        } catch { Start-Sleep -Milliseconds (500 * ($i + 1)) }
    }
    return $null
}
function Op([string]$id, $params) {
    if ($params) { Brp-Try 'jackdaw/call_operator' @{ id = $id; params = $params } }
    else { Brp-Try 'jackdaw/call_operator' @{ id = $id } }
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru `
    -RedirectStandardError  (Join-Path $OutDir 'probe-editor-stderr.log') `
    -RedirectStandardOutput (Join-Path $OutDir 'probe-editor-stdout.log')
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    if (Brp-Try 'jackdaw/status' @{} 1) { break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw 'editor died' }
}

Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
Start-Sleep -Seconds 2
$r = Op 'pie.play_current' @{}
Write-Host ("play_current: {0}" -f ($r.result | ConvertTo-Json -Compress))
$deadline = (Get-Date).AddSeconds(600)
$last = ''
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $st = (Brp-Try 'jackdaw/status' @{}).result
    $pie = "$($st.pie)"
    if ($pie -ne $last) {
        Write-Host ("pie state: {0} (at {1})" -f $pie, (Get-Date -Format HH:mm:ss))
        $last = $pie
    }
    if ($pie -in @('running', 'stopped')) { break }
}
Write-Host ("final pie state: {0}" -f $last)
if ($last -eq 'running') { Write-Host 'PIE_CONNECT_PASS' } else { Write-Host 'PIE_CONNECT_FAIL' }
Op 'pie.stop' @{} | Out-Null
Start-Sleep -Seconds 3
Write-Host 'PROBE_DONE'
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
