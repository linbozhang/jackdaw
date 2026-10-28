# Dump the game-port snapshot during PIE.
$ErrorActionPreference = 'Continue'
$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'H:\workspace_AI\t10-phys\phys-game'
$EditorPort = 15703
$GamePort   = 15702
$OutDir  = Join-Path $Repo 'loop\t10t2-live'

function Brp([int]$Port, [string]$method, $params, [int]$retries = 6) {
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
    if ($params) { Brp $EditorPort 'jackdaw/call_operator' @{ id = $id; params = $params } }
    else { Brp $EditorPort 'jackdaw/call_operator' @{ id = $id } }
}

Get-Process jackdaw, phys-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$EditorPort"
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru `
    -RedirectStandardError  (Join-Path $OutDir 'gdump-editor-stderr.log')
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    if (Brp $EditorPort 'jackdaw/status' @{} 1) { break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw 'editor died' }
}
Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
Start-Sleep -Seconds 2
Op 'pie.play_current' | Out-Null
$deadline = (Get-Date).AddSeconds(600)
while ((Get-Date) -lt $deadline) {
    $st = (Brp $EditorPort 'jackdaw/status' @{} 1).result
    if ("$($st.pie)" -eq 'running') { break }
    Start-Sleep -Seconds 3
}
Write-Host 'running; sampling game port'
Start-Sleep -Seconds 4

$s1 = Brp $GamePort 'jackdaw/scene_snapshot' @{}
$s1 | ConvertTo-Json -Depth 14 | Set-Content (Join-Path $OutDir 'game-snap-1.json') -Encoding UTF8
Write-Host ("snap1 raw type: {0}, count {1}" -f $s1.result.GetType().Name, @($s1.result).Count)
Start-Sleep -Seconds 2
$s2 = Brp $GamePort 'jackdaw/scene_snapshot' @{}
$s2 | ConvertTo-Json -Depth 14 | Set-Content (Join-Path $OutDir 'game-snap-2.json') -Encoding UTF8

# app_info as a sanity check on the game port.
$ai = Brp $GamePort 'jackdaw/app_info' @{}
Write-Host ("app_info: {0}" -f ($ai.result | ConvertTo-Json -Compress))

Op 'pie.stop' | Out-Null
Start-Sleep -Seconds 2
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Get-Process jackdaw, phys-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Write-Host 'GDUMP_DONE'
