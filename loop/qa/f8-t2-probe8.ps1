# Probe: after the first widget click kills later ones, try explicit release,
# rest, and re-hover to revive UI clicking; also test checkbox WITHOUT any
# prior segment click to confirm first-click-alive.
param([int]$Port = 15703, [string]$Order = 'smaa-first')
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
function Ptr([string]$Action, [double]$X, [double]$Y) {
    Raw 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = $X; y = $Y; action = $Action } } | Out-Null
}
function Frames([int]$n) { try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 } }
function CamState {
    $r = Raw 'world.get_components' @{ entity = $script:CamId; components = @('bevy_anti_alias::smaa::Smaa','bevy_anti_alias::fxaa::Fxaa','bevy_pbr::ssao::ScreenSpaceAmbientOcclusion') }
    $c = $r.result.components
    ("Smaa={0} Fxaa={1} Ssao={2}" -f ($null -ne $c.'bevy_anti_alias::smaa::Smaa'), ($null -ne $c.'bevy_anti_alias::fxaa::Fxaa'), ($null -ne $c.'bevy_pbr::ssao::ScreenSpaceAmbientOcclusion'))
}
function Try-Ao([string]$Tag) {
    $ao = @(Rows | Where-Object { $_.text -eq 'Ambient Occlusion' })[0]
    Ptr 'click' ($ao.cx - $ao.w/2 - 36) $ao.cy; Frames 8
    Write-Host ("[{0}] cam: {1}" -f $Tag, (CamState))
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru -RedirectStandardOutput "$env:TEMP\jd-out.log" -RedirectStandardError "$env:TEMP\jd-err5.log"
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    $script:CamId = [string](Get-FlyCamera).Entity
    Raw 'jackdaw/call_operator' @{ id = 'graphics.open'; params = @{} } | Out-Null
    Frames 12; Start-Sleep -Milliseconds 500

    if ($Order -eq 'smaa-first') {
        $smaa = @(Rows | Where-Object { $_.text -eq 'SMAA' })[0]
        Ptr 'click' $smaa.cx $smaa.cy; Frames 8
        Write-Host ("after SMAA: {0}" -f (CamState))
        Try-Ao 'AO after SMAA (expect dead?)'
        Ptr 'release' 900 400; Frames 4
        Try-Ao 'AO after explicit release'
        Ptr 'rest' 900 400; Frames 6
        Try-Ao 'AO after rest'
        # hover somewhere else first, then click
        $ao = @(Rows | Where-Object { $_.text -eq 'Ambient Occlusion' })[0]
        Ptr 'move' 800 400; Frames 4
        Ptr 'move' ($ao.cx - $ao.w/2 - 36) $ao.cy; Frames 6
        Ptr 'press' ($ao.cx - $ao.w/2 - 36) $ao.cy; Frames 4
        Ptr 'release' ($ao.cx - $ao.w/2 - 36) $ao.cy; Frames 8
        Write-Host ("[AO via move+press+release] cam: {0}" -f (CamState))
    } else {
        # checkbox first, no segment click
        Try-Ao 'AO first (expect alive)'
        $smaa = @(Rows | Where-Object { $_.text -eq 'SMAA' })[0]
        Ptr 'click' $smaa.cx $smaa.cy; Frames 8
        Write-Host ("after SMAA (2nd): {0}" -f (CamState))
        $fog = @(Rows | Where-Object { $_.text -eq 'Fog' })[0]
        Ptr 'click' ($fog.cx - $fog.w/2 - 36) $fog.cy; Frames 8
        $r = Raw 'world.get_resources' @{ resource = 'jackdaw::viewport_settings::ViewportSettings' }
        Write-Host ("fog click: ViewportSettings readable: {0}" -f ($null -ne $r.result))
    }
    Write-Host '--- op log:'
    Get-Content "$env:TEMP\jd-err5.log" -Tail 20 | Select-String -Pattern 'OPERATOR:' | ForEach-Object { ($_.Line -replace '.*[0-9]Z ', '') -replace '\x1b\[[0-9;]*m', '' }
} finally {
    try {
        Raw 'jackdaw/call_operator' @{ id = 'viewport.quality.set'; params = @{ anti_aliasing = 'fxaa' } } | Out-Null
        Raw 'jackdaw/call_operator' @{ id = 'viewport.ssao.set'; params = @{ on = $false } } | Out-Null
        Raw 'jackdaw/call_operator' @{ id = 'viewport.show.toggle'; params = @{ flag = 'fog'; on = $true } } | Out-Null
    } catch {}
    Start-Sleep -Milliseconds 500
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
