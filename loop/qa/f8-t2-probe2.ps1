# Probe: panel row positions vs the sidebar's visible band; try clicking SMAA
# with scroll-to-top first, then check the camera.
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
        $s = $_.components.'bevy_ui::ui_node::ComputedNode'.size
        [pscustomobject]@{ text = [string]$_.components.'bevy_ui::widget::text::Text'; cx = [math]::Round([double]$a[4],1); cy = [math]::Round([double]$a[5],1); w = [math]::Round([double]$s[0],1); h = [math]::Round([double]$s[1],1) }
    }
}
function Nodes {
    $j = Raw 'world.query' @{ data = @{ components = @('bevy_ui::ui_node::ComputedNode', 'bevy_ui::ui_transform::UiGlobalTransform') } }
    $j.result | Where-Object { $_.components.'bevy_ui::ui_node::ComputedNode'.size[0] -gt 8 -and $_.components.'bevy_ui::ui_node::ComputedNode'.size[1] -gt 4 } | ForEach-Object {
        $a = $_.components.'bevy_ui::ui_transform::UiGlobalTransform'
        $s = $_.components.'bevy_ui::ui_node::ComputedNode'.size
        [pscustomobject]@{ entity = [string]$_.entity; cx = [math]::Round([double]$a[4],1); cy = [math]::Round([double]$a[5],1); w = [math]::Round([double]$s[0],1); h = [math]::Round([double]$s[1],1) }
    }
}
function Pointer([string]$Action, [double]$X, [double]$Y, $Extra = @{}) {
    $p = @{ x = $X; y = $Y; action = $Action }
    foreach ($k in $Extra.Keys) { $p[$k] = $Extra[$k] }
    Raw 'jackdaw/call_operator' @{ id = 'input.pointer'; params = $p } | Out-Null
}
function Frames([int]$n) { try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 } }

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    $cam = Get-FlyCamera; $camId = [string]$cam.Entity
    Raw 'jackdaw/call_operator' @{ id = 'graphics.open'; params = @{} } | Out-Null
    Frames 12; Start-Sleep -Milliseconds 400

    Write-Host '--- panel rows sorted by cy:'
    $panelTexts = 'Viewport','Editor-only preview','Quality Preset','Render Scale','Anti-Aliasing','Off','FXAA','SMAA','TAA','Ambient Occlusion','SSAO Quality','Low','Medium','High','Ultra','Sun Shadows','Point Shadows','Fog','Sharpening','Strength','Scene','Saved with the scene','Post Processing','Tonemapper','Exposure (EV100)','Bloom Intensity','Bloom Threshold','Realtime GI'
    Rows | Where-Object { $panelTexts -contains $_.text } | Sort-Object cy, cx | Format-Table -AutoSize | Out-String -Width 120 | Write-Host

    Write-Host '--- biggest nodes on the right (possible panel/sidebar containers):'
    Nodes | Where-Object { $_.cx -gt 1100 -and $_.h -gt 200 } | Sort-Object h -Descending | Select-Object -First 6 | Format-Table -AutoSize | Out-String -Width 120 | Write-Host

    # scroll the panel up hard (negative lines), then click SMAA
    $smaa = @(Rows | Where-Object { $_.text -eq 'SMAA' })[0]
    Write-Host ("SMAA text at ({0},{1})" -f $smaa.cx, $smaa.cy)
    Pointer 'scroll' ($smaa.cx) 500 @{ lines = -20 }
    Frames 6; Start-Sleep -Milliseconds 200
    $smaa = @(Rows | Where-Object { $_.text -eq 'SMAA' })[0]
    Write-Host ("SMAA text after scroll at ({0},{1})" -f $smaa.cx, $smaa.cy)
    Pointer 'click' $smaa.cx $smaa.cy
    Frames 12
    $r = Raw 'world.get_components' @{ entity = $camId; components = @('bevy_anti_alias::smaa::Smaa', 'bevy_anti_alias::fxaa::Fxaa') }
    Write-Host ("after SMAA click: Smaa={0} Fxaa={1}" -f ($null -ne $r.result.components.'bevy_anti_alias::smaa::Smaa'), ($null -ne $r.result.components.'bevy_anti_alias::fxaa::Fxaa'))
    if ($r.error) { Write-Host "BRP error: $($r.error | ConvertTo-Json -Compress)" }
} finally {
    try { Raw 'jackdaw/call_operator' @{ id = 'viewport.quality.set'; params = @{ anti_aliasing = 'fxaa' } } | Out-Null } catch {}
    Start-Sleep -Milliseconds 300
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
