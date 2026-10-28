# Tight probe: A1 SMAA click, then AO clicks with row-position dumps around each.
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
function CamState {
    $r = Raw 'world.get_components' @{ entity = $script:CamId; components = @('bevy_anti_alias::smaa::Smaa','bevy_anti_alias::fxaa::Fxaa','bevy_pbr::ssao::ScreenSpaceAmbientOcclusion') }
    $c = $r.result.components
    ("Smaa={0} Fxaa={1} Ssao={2}" -f ($null -ne $c.'bevy_anti_alias::smaa::Smaa'), ($null -ne $c.'bevy_anti_alias::fxaa::Fxaa'), ($null -ne $c.'bevy_pbr::ssao::ScreenSpaceAmbientOcclusion'))
}
function PanelRows {
    $want = 'Quality Preset','Render Scale','Anti-Aliasing','Ambient Occlusion','SSAO Quality','Sun Shadows','Fog','Sharpening'
    (Rows | Where-Object { $want -contains $_.text } | Sort-Object cy | ForEach-Object { "{0}@({1:N0},{2:N0})" -f $_.text, $_.cx, $_.cy }) -join '  '
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru -RedirectStandardOutput "$env:TEMP\jd-out.log" -RedirectStandardError "$env:TEMP\jd-err2.log"
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    $script:CamId = [string](Get-FlyCamera).Entity
    Raw 'jackdaw/call_operator' @{ id = 'graphics.open'; params = @{} } | Out-Null
    Frames 12; Start-Sleep -Milliseconds 500

    Write-Host ("start cam: {0}" -f (CamState))
    Write-Host ("rows: {0}" -f (PanelRows))
    $smaa = @(Rows | Where-Object { $_.text -eq 'SMAA' })[0]
    Click $smaa.cx $smaa.cy; Frames 10
    Write-Host ("after SMAA click cam: {0}" -f (CamState))

    foreach ($dx in -95, -91, -87, -83) {
        $ao = @(Rows | Where-Object { $_.text -eq 'Ambient Occlusion' })[0]
        $x = [math]::Round($ao.cx - $ao.w/2 + $dx + 59.5, 1)  # caption.left + (dx+59.5): -35.5..-23.5 from left edge
        $x = [math]::Round($ao.cx - $ao.w/2 - 36 + ($dx + 95), 1)
        Write-Host ("--- AO click at ({0:N1},{1:N1})  rows-now: {2}" -f $x, $ao.cy, (PanelRows))
        Click $x $ao.cy
        Frames 10
        Write-Host ("    cam after: {0}" -f (CamState))
    }
    Write-Host '--- operator log tail:'
    Get-Content "$env:TEMP\jd-err2.log" -Tail 40 | Select-String -Pattern 'OPERATOR' | ForEach-Object { $_.Line -replace '.*OPERATOR: ', 'OP: ' }
} finally {
    try {
        Raw 'jackdaw/call_operator' @{ id = 'viewport.quality.set'; params = @{ anti_aliasing = 'fxaa' } } | Out-Null
        Raw 'jackdaw/call_operator' @{ id = 'viewport.ssao.set'; params = @{ on = $false } } | Out-Null
    } catch {}
    Start-Sleep -Milliseconds 500
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
