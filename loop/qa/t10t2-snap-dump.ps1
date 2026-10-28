# Dump the PIE snapshot entity list: what the editor world holds.
$ErrorActionPreference = 'Continue'
$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'H:\workspace_AI\t10-phys\phys-game'
$Port    = 15705
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
    -RedirectStandardError  (Join-Path $OutDir 'dump-editor-stderr.log') `
    -RedirectStandardOutput (Join-Path $OutDir 'dump-editor-stdout.log')
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    if (Brp-Try 'jackdaw/status' @{} 1) { break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw 'editor died' }
}

Op 'scene.open' @{ path = 'assets/scene.bsn' } | Out-Null
Start-Sleep -Seconds 2

# Snapshot before play: the authored scene.
$before = Brp-Try 'jackdaw/scene_snapshot' @{}
"before-play entities: $(@($before.result).Count)" | Write-Host
@($before.result) | ForEach-Object {
    $names = ($_.components.PSObject.Properties.Name | Select-Object -First 3) -join ','
    "  e=$($_.entity) comps=[$names]" | Write-Host
}

Op 'pie.play_current' | Out-Null
$deadline = (Get-Date).AddSeconds(600)
$last = ''
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $st = (Brp-Try 'jackdaw/status' @{}).result
    if ("$($st.pie)" -ne $last) { Write-Host ("pie: {0}" -f $st.pie); $last = "$($st.pie)" }
    if ("$($st.pie)" -eq 'running') { break }
}
Start-Sleep -Seconds 4

$after = Brp-Try 'jackdaw/scene_snapshot' @{}
"after-play entities: $(@($after.result).Count)" | Write-Host
$after.result | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $OutDir 'snapshot-pie.json') -Encoding UTF8
@($after.result) | ForEach-Object {
    $t = $_.components.'bevy_transform::components::transform::Transform'
    $pos = if ($t) { "{0},{1},{2}" -f $t.translation[0], $t.translation[1], $t.translation[2] } else { '-' }
    $names = ($_.components.PSObject.Properties.Name | Select-Object -First 4) -join ','
    "  e=$($_.entity) pos=($pos) comps=[$names]" | Write-Host
}

Op 'pie.stop' | Out-Null
Start-Sleep -Seconds 2
Write-Host 'DUMP_DONE'
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
