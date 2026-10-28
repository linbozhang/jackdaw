# Probe: does an SMAA (or FXAA) click leave a modal holding the editor?
param([int]$Port = 15703)
$ErrorActionPreference = 'Stop'
$Repo = 'E:\Project\rust\jackdaw'
$Exe = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
function Raw([string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 12 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $w = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body $bytes -UseBasicParsing -TimeoutSec 30
    return [System.Text.Encoding]::UTF8.GetString($w.RawContentStream.ToArray()) | ConvertFrom-Json
}
function Rows {
    $j = Raw 'world.query' @{ data = @{ components = @('bevy_ui::widget::text::Text', 'bevy_ui::ui_node::ComputedNode', 'bevy_ui::ui_transform::UiGlobalTransform') } }
    $j.result | Where-Object { $_.components.'bevy_ui::ui_node::ComputedNode'.size[0] -gt 0 } | ForEach-Object {
        $a = $_.components.'bevy_ui::ui_transform::UiGlobalTransform'
        [pscustomobject]@{ text = [string]$_.components.'bevy_ui::widget::text::Text'; cx = [math]::Round([double]$a[4],1); cy = [math]::Round([double]$a[5],1); w = [math]::Round([double]$_.components.'bevy_ui::ui_node::ComputedNode'.size[0],1) }
    }
}
function Click([double]$x, [double]$y) {
    Raw 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = $x; y = $y; action = 'click' } } | Out-Null
}
function Frames([int]$n) { try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 } }
function Status {
    $s = (Raw 'jackdaw/status' @{}).result
    return ($s | ConvertTo-Json -Compress -Depth 5)
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru -RedirectStandardOutput "$env:TEMP\jd-out.log" -RedirectStandardError "$env:TEMP\jd-err4.log"
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    Raw 'jackdaw/call_operator' @{ id = 'graphics.open'; params = @{} } | Out-Null
    Frames 12; Start-Sleep -Milliseconds 500
    Write-Host ("status before: {0}" -f (Status))

    $fxaa = @(Rows | Where-Object { $_.text -eq 'FXAA' })[0]
    Click $fxaa.cx $fxaa.cy; Frames 8
    Write-Host ("status after FXAA click: {0}" -f (Status))

    $smaa = @(Rows | Where-Object { $_.text -eq 'SMAA' })[0]
    Click $smaa.cx $smaa.cy; Frames 8
    Write-Host ("status after SMAA click: {0}" -f (Status))

    $ao = @(Rows | Where-Object { $_.text -eq 'Ambient Occlusion' })[0]
    Click ($ao.cx - $ao.w/2 - 36) $ao.cy; Frames 8
    Write-Host ("status after AO click: {0}" -f (Status))

    # cancel any modal, then try AO again
    Raw 'jackdaw/cancel' @{} | Out-Null
    Frames 6
    Write-Host ("status after cancel: {0}" -f (Status))
    $ao = @(Rows | Where-Object { $_.text -eq 'Ambient Occlusion' })[0]
    Click ($ao.cx - $ao.w/2 - 36) $ao.cy; Frames 8
    $r = Raw 'world.get_components' @{ entity = $script:CamId; components = @('bevy_pbr::ssao::ScreenSpaceAmbientOcclusion') }
    Write-Host ("AO after cancel: Ssao present = {0}" -f ($null -ne $r.result.components.'bevy_pbr::ssao::ScreenSpaceAmbientOcclusion'))
    Write-Host '--- op log:'
    Get-Content "$env:TEMP\jd-err4.log" -Tail 25 | Select-String -Pattern 'OPERATOR|modal' | ForEach-Object { ($_.Line -replace '.*[0-9]Z ', '') -replace '\x1b\[[0-9;]*m', '' }
} finally {
    try {
        Raw 'jackdaw/call_operator' @{ id = 'viewport.quality.set'; params = @{ anti_aliasing = 'fxaa' } } | Out-Null
        Raw 'jackdaw/call_operator' @{ id = 'viewport.ssao.set'; params = @{ on = $false } } | Out-Null
    } catch {}
    Start-Sleep -Milliseconds 500
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
