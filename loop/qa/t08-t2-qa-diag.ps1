# T08-T2 QA diag: raw scene_snapshot shape during play (behavior leg).
$ErrorActionPreference = 'Stop'
$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'E:\Project\rust\jackdaw\loop\qa-fixture\t08t2qa-fixture'
$Port    = 15703

function Brp-Try([string]$method, $params, [int]$retries = 6) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = (Get-Random); method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 8)
        } catch { Start-Sleep -Milliseconds (500 * ($i + 1)) }
    }
    return $null
}
function Op([string]$id, $params) {
    if ($params) { Brp-Try 'jackdaw/call_operator' @{ id = $id; params = $params } }
    else { Brp-Try 'jackdaw/call_operator' @{ id = $id } }
}
function Wait-Until([string]$until, [int]$TimeoutSec) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Brp-Try 'jackdaw/wait' @{ until = $until } 1
        if ($r -and $r.result) {
            if ($until -eq 'idle' -and $r.result.idle) { return $true }
            if ($until -eq 'pie_running' -and "$($r.result.pie)" -eq 'running') { return $true }
        }
        Start-Sleep -Seconds 2
    }
    throw "wait($until) timed out"
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru
$ready = $false
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    if (Brp-Try 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw 'editor died' }
}
if (-not $ready) { throw 'BRP never answered' }
Wait-Until 'idle' 600
Start-Sleep -Seconds 10

Op 'scene.new' | Out-Null
Op 'scene.save' | Out-Null
Start-Sleep -Seconds 1
Op 'pie.play_current' | Out-Null
Wait-Until 'pie_running' 900
Start-Sleep -Seconds 3

$a = (Brp-Try 'jackdaw/scene_snapshot' @{}).result
Write-Host ("snapshot A count=" + @($a).Count)
foreach ($e in @($a)) {
    $t = $e.components.'bevy_transform::components::transform::Transform'
    $pos = ''
    if ($t) { $pos = " y=" + $t.translation.y }
    Write-Host ("  A entity=" + $e.entity + $pos)
}
Start-Sleep -Seconds 3
$b = (Brp-Try 'jackdaw/scene_snapshot' @{}).result
foreach ($eb in @($b)) {
    $tb = $eb.components.'bevy_transform::components::transform::Transform'
    $pos = ''
    if ($tb) { $pos = " y=" + $tb.translation.y }
    Write-Host ("  B entity=" + $eb.entity + $pos)
    if ($tb) {
        foreach ($ea in @($a)) {
            if ($ea.entity -eq $eb.entity) {
                $ta = $ea.components.'bevy_transform::components::transform::Transform'
                if ($ta -and ([double]$tb.translation.y -ne [double]$ta.translation.y)) {
                    Write-Host ("MOVED entity=" + $eb.entity + " y " + $ta.translation.y + " -> " + $tb.translation.y)
                }
            }
        }
    }
}
Op 'pie.stop' | Out-Null
Wait-Until 'idle' 120
Stop-Process -Id $proc.Id -Force
Write-Output 'DIAG_DONE'
