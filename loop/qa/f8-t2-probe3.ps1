# Probe: click the Ambient Occlusion row at several x offsets; check SSAO.
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

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru -RedirectStandardOutput "$env:TEMP\jd-out.log" -RedirectStandardError "$env:TEMP\jd-err.log"
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    $cam = Get-FlyCamera; $camId = [string]$cam.Entity
    Raw 'jackdaw/call_operator' @{ id = 'graphics.open'; params = @{} } | Out-Null
    Frames 12; Start-Sleep -Milliseconds 500

    function Has-Ssao {
        $r = Raw 'world.get_components' @{ entity = $camId; components = @('bevy_pbr::ssao::ScreenSpaceAmbientOcclusion') }
        return ($null -ne $r.result.components.'bevy_pbr::ssao::ScreenSpaceAmbientOcclusion')
    }
    $ao = @(Rows | Where-Object { $_.text -eq 'Ambient Occlusion' })[0]
    Write-Host ("AO caption at ({0},{1}) w={2} -> span [{3:N0}..{4:N0}]" -f $ao.cx, $ao.cy, $ao.w, ($ao.cx - $ao.w/2), ($ao.cx + $ao.w/2))
    foreach ($dx in -95, -80, -60, -45, -30, -15, 0) {
        $x = $ao.cx + $dx; $y = $ao.cy
        Click $x $y; Frames 10
        Write-Host ("click at x={0:N1} (dx={1}): SSAO present = {2}" -f $x, $dx, (Has-Ssao))
        if (Has-Ssao) { break }
    }
    Write-Host '--- stderr tail:'
    Get-Content "$env:TEMP\jd-err.log" -Tail 30
} finally {
    try { Raw 'jackdaw/call_operator' @{ id = 'viewport.ssao.set'; params = @{ on = $false } } | Out-Null } catch {}
    Start-Sleep -Milliseconds 300
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
