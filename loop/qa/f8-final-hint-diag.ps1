# Diagnose: after component.remove of the Environment, does the hint return?
param([int]$Port = 15703)
$ErrorActionPreference = 'Stop'
$Repo = 'E:\Project\rust\jackdaw'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
function Raw([string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 12 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    try { $w = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body $bytes -UseBasicParsing -TimeoutSec 30 }
    catch { Start-Sleep -Seconds 2; $w = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body $bytes -UseBasicParsing -TimeoutSec 45 }
    return [System.Text.Encoding]::UTF8.GetString($w.RawContentStream.ToArray()) | ConvertFrom-Json
}
function Frames([int]$n) { try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 } }
function Environments {
    $r = Raw 'world.query' @{ data = @{ components = @('jackdaw_scene_types::environment::Environment') } }
    return @($r.result) | ForEach-Object { [string]$_.entity }
}
function HintDisplay {
    $rows = Raw 'world.query' @{ data = @{ components = @('bevy_ui::widget::text::Text', 'bevy_ui::ui_node::Node') } }
    foreach ($r in @($rows.result)) {
        if (([string]$r.components.'bevy_ui::widget::text::Text') -like '*no environment*') {
            return [string]$r.components.'bevy_ui::ui_node::Node'.display
        }
    }
    return 'ABSENT'
}
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath (Join-Path $Repo 'target\debug\jackdaw.exe') -WorkingDirectory (Join-Path $Repo 'target\debug') -PassThru -RedirectStandardOutput "$env:TEMP\jd-diag-out.log" -RedirectStandardError "$env:TEMP\jd-diag-err.log"
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    Raw 'jackdaw/call_operator' @{ id = 'graphics.open' } | Out-Null
    Frames 12; Start-Sleep -Milliseconds 400
    Write-Host ("start: envs=[{0}] hint={1}" -f ((Environments) -join ','), (HintDisplay))

    $tree = (Brp-Result (Brp-Call 'jackdaw/scene_tree' @{})).tree
    $target = @($tree)[0].entity
    $add = Raw 'jackdaw/call_operator' @{ id = 'component.add'; params = @{ entity = $target; type_path = 'jackdaw_scene_types::environment::Environment' } }
    Frames 8; Start-Sleep -Milliseconds 400
    Write-Host ("after add: envs=[{0}] hint={1}  add-result={2}" -f ((Environments) -join ','), (HintDisplay), ($add | ConvertTo-Json -Depth 4 -Compress))

    $set = Raw 'jackdaw/call_operator' @{ id = 'environment.set'; params = @{ 'post.enabled' = $true } }
    Frames 6; Start-Sleep -Milliseconds 400
    Write-Host ("after env.set: envs=[{0}] hint={1}" -f ((Environments) -join ','), (HintDisplay))

    $rm = Raw 'jackdaw/call_operator' @{ id = 'component.remove'; params = @{ entity = $target; type_path = 'jackdaw_scene_types::environment::Environment' } }
    Frames 8; Start-Sleep -Milliseconds 400
    Write-Host ("after remove: envs=[{0}] hint={1}" -f ((Environments) -join ','), (HintDisplay))
    Write-Host ("remove-response: {0}" -f ($rm | ConvertTo-Json -Depth 6 -Compress))
    Frames 30; Start-Sleep -Milliseconds 800
    Write-Host ("after 30 more frames: envs=[{0}] hint={1}" -f ((Environments) -join ','), (HintDisplay))
    Get-Content "$env:TEMP\jd-diag-err.log" -Tail 15 | ForEach-Object { $_ -replace '\x1b\[[0-9;]*m', '' } | Select-String -Pattern 'OPERATOR|warn|error' | ForEach-Object { $_.Line }
} finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
