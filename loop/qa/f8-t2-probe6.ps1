# Scan probe: after SMAA on, sweep clicks across the AO row and other controls,
# map exactly which widgets still respond (operator log + camera state).
param([int]$Port = 15703, [switch]$NoSmaa)
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
function Click([double]$x, [double]$y, [int]$FramesBetween = 1) {
    Raw 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = $x; y = $y; action = 'click'; frames = $FramesBetween } } | Out-Null
}
function Frames([int]$n) { try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 } }
function CamState {
    $r = Raw 'world.get_components' @{ entity = $script:CamId; components = @('bevy_anti_alias::smaa::Smaa','bevy_anti_alias::fxaa::Fxaa','bevy_pbr::ssao::ScreenSpaceAmbientOcclusion') }
    $c = $r.result.components
    ("Smaa={0} Fxaa={1} Ssao={2}" -f ($null -ne $c.'bevy_anti_alias::smaa::Smaa'), ($null -ne $c.'bevy_anti_alias::fxaa::Fxaa'), ($null -ne $c.'bevy_pbr::ssao::ScreenSpaceAmbientOcclusion'))
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru -RedirectStandardOutput "$env:TEMP\jd-out.log" -RedirectStandardError "$env:TEMP\jd-err3.log"
$opCount0 = 0
function OpCount {
    (Select-String -Path "$env:TEMP\jd-err3.log" -Pattern 'OPERATOR:').Count
}
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    $script:CamId = [string](Get-FlyCamera).Entity
    Raw 'jackdaw/call_operator' @{ id = 'graphics.open'; params = @{} } | Out-Null
    Frames 12; Start-Sleep -Milliseconds 500

    if (-not $NoSmaa) {
        $smaa = @(Rows | Where-Object { $_.text -eq 'SMAA' })[0]
        Click $smaa.cx $smaa.cy; Frames 10
        Write-Host ("after SMAA click cam: {0}" -f (CamState))
    } else {
        Write-Host 'SMAA switch skipped (-NoSmaa)'
    }

    # sweep the AO row from x=920 to 1000
    $ao = @(Rows | Where-Object { $_.text -eq 'Ambient Occlusion' })[0]
    $y = $ao.cy
    foreach ($x in 920, 930, 940, 950, 960, 970, 990) {
        $before = OpCount
        Click ([double]$x) ([double]$y); Frames 8
        Write-Host ("AO x={0}: new-ops={1}  cam: {2}" -f $x, ((OpCount) - $before - 1), (CamState))
        if ((CamState -like '*Ssao=True*')) { break }
    }
    # controls deep inside the panel: Fog checkbox + Ultra segment
    $fog = @(Rows | Where-Object { $_.text -eq 'Fog' })[0]
    $before = OpCount
    Click ($fog.cx - $fog.w/2 - 36) ($fog.cy); Frames 8
    Write-Host ("Fog box click: new-ops={0}" -f ((OpCount) - $before - 1))
    $ultra = @(Rows | Where-Object { $_.text -eq 'Ultra' })[0]
    $before = OpCount
    Click $ultra.cx $ultra.cy; Frames 8
    Write-Host ("Ultra seg click: new-ops={0}  cam: {1}" -f ((OpCount) - $before - 1), (CamState))
} finally {
    try {
        Raw 'jackdaw/call_operator' @{ id = 'viewport.quality.set'; params = @{ anti_aliasing = 'fxaa' } } | Out-Null
        Raw 'jackdaw/call_operator' @{ id = 'viewport.ssao.set'; params = @{ on = $false } } | Out-Null
        Raw 'jackdaw/call_operator' @{ id = 'viewport.show.toggle'; params = @{ flag = 'fog'; on = $true } } | Out-Null
    } catch {}
    Start-Sleep -Milliseconds 500
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
