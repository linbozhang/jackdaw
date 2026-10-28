# Probe: after clicking the bloom track, read the widget's own SliderValue.
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
function Rows {
    $j = Raw 'world.query' @{ data = @{ components = @('bevy_ui::widget::text::Text', 'bevy_ui::ui_node::ComputedNode', 'bevy_ui::ui_transform::UiGlobalTransform') } }
    $j.result | Where-Object { $_.components.'bevy_ui::ui_node::ComputedNode'.size[0] -gt 0 } | ForEach-Object {
        $a = $_.components.'bevy_ui::ui_transform::UiGlobalTransform'
        [pscustomobject]@{ text = [string]$_.components.'bevy_ui::widget::text::Text'; cx = [double]$a[4]; cy = [double]$a[5]; w = [double]$_.components.'bevy_ui::ui_node::ComputedNode'.size[0] }
    }
}
function NodesWith {
    param([string[]]$Comps)
    $j = Raw 'world.query' @{ data = @{ components = $Comps } }
    $j.result | ForEach-Object {
        $a = $_.components.'bevy_ui::ui_transform::UiGlobalTransform'
        [pscustomobject]@{ entity = [string]$_.entity; cx = [math]::Round([double]$a[4],1); cy = [math]::Round([double]$a[5],1); w = [math]::Round([double]$_.components.'bevy_ui::ui_node::ComputedNode'.size[0],1); sv = $_.components.'bevy_ui_widgets::SliderValue' }
    }
}
function Ptr([string]$Action, [double]$X, [double]$Y, $Extra = @{}) {
    $p = @{ x = $X; y = $Y; action = $Action }
    foreach ($k in $Extra.Keys) { $p[$k] = $Extra[$k] }
    Raw 'jackdaw/call_operator' @{ id = 'input.pointer'; params = $p } | Out-Null
}
function Frames([int]$n) { try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 } }
function Bloom {
    $r = Raw 'world.query' @{ data = @{ components = @('jackdaw_scene_types::environment::Environment') } }
    return [double](@($r.result)[0]).components.'jackdaw_scene_types::environment::Environment'.post.bloom_intensity
}
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath (Join-Path $Repo 'target\debug\jackdaw.exe') -WorkingDirectory (Join-Path $Repo 'target\debug') -PassThru -RedirectStandardOutput "$env:TEMP\jd-out.log" -RedirectStandardError "$env:TEMP\jd-err9.log"
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    Raw 'jackdaw/call_operator' @{ id = 'graphics.open'; params = @{} } | Out-Null
    Frames 12; Start-Sleep -Milliseconds 500
    $tree = (Brp-Result (Brp-Call 'jackdaw/scene_tree' @{})).tree
    Raw 'jackdaw/call_operator' @{ id = 'component.add'; params = @{ entity = @($tree)[0].entity; type_path = 'jackdaw_scene_types::environment::Environment' } } | Out-Null
    Frames 8
    Raw 'jackdaw/call_operator' @{ id = 'environment.set'; params = @{ 'post.enabled' = $true } } | Out-Null
    Frames 6

    $label = @(Rows | Where-Object { $_.text -eq 'Bloom Intensity' -and $_.cx -gt 1000 })[0]
    Write-Host '--- sliders before (SliderValue per node):'
    $before = NodesWith @('bevy_ui::ui_node::ComputedNode', 'bevy_ui::ui_transform::UiGlobalTransform', 'bevy_ui_widgets::SliderValue')
    $before | Where-Object { [math]::Abs($_.cy - $label.cy) -lt 30 } | ConvertTo-Json -Depth 4 | Write-Host
    $track = @($before | Where-Object { [math]::Abs($_.cy - $label.cy) -lt 26 -and $_.w -gt 60 })[0]
    Write-Host ("bloom slider node: entity={0} ({1:N0},{2:N0}) w={3:N0} value={4}" -f $track.entity, $track.cx, $track.cy, $track.w, $track.sv.0)

    Ptr 'click' ($track.cx) ($track.cy) @{ frames = 4 }
    Start-Sleep -Milliseconds 500; Frames 8
    $after = NodesWith @('bevy_ui::ui_node::ComputedNode', 'bevy_ui::ui_transform::UiGlobalTransform', 'bevy_ui_widgets::SliderValue')
    $t2 = @($after | Where-Object { $_.entity -eq $track.entity })[0]
    Write-Host ("after click at center: SliderValue={0} bloom_env={1}" -f $t2.sv.0, (Bloom))
    Write-Host '--- op tail:'
    Get-Content "$env:TEMP\jd-err9.log" -Tail 8 | Select-String -Pattern 'OPERATOR:' | ForEach-Object { ($_.Line -replace '.*[0-9]Z ', '') -replace '\x1b\[[0-9;]*m', '' }
} finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
