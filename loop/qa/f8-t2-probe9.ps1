# Discriminating probe: OS-level SendInput (real mouse) vs input.pointer.
# If real clicks keep working after the SMAA segment click, the multi-click
# death is a synthetic-input artifact, not a product bug.
param([int]$Port = 15703)
$ErrorActionPreference = 'Stop'
$Repo = 'E:\Project\rust\jackdaw'
$Exe = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
. (Join-Path $Repo 'loop\qa\input.ps1')
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
function Nodes {
    $j = Raw 'world.query' @{ data = @{ components = @('bevy_ui::ui_node::ComputedNode', 'bevy_ui::ui_transform::UiGlobalTransform') } }
    $j.result | Where-Object { $_.components.'bevy_ui::ui_node::ComputedNode'.size[0] -gt 100 } | ForEach-Object {
        $a = $_.components.'bevy_ui::ui_transform::UiGlobalTransform'
        $s = $_.components.'bevy_ui::ui_node::ComputedNode'.size
        [pscustomobject]@{ cx = [math]::Round([double]$a[4],1); cy = [math]::Round([double]$a[5],1); w = [math]::Round([double]$s[0],1); h = [math]::Round([double]$s[1],1) }
    }
}
function Frames([int]$n) { try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 } }
function CamState {
    $r = Raw 'world.get_components' @{ entity = $script:CamId; components = @('bevy_anti_alias::smaa::Smaa','bevy_anti_alias::fxaa::Fxaa','bevy_pbr::ssao::ScreenSpaceAmbientOcclusion') }
    $c = $r.result.components
    ("Smaa={0} Fxaa={1} Ssao={2}" -f ($null -ne $c.'bevy_anti_alias::smaa::Smaa'), ($null -ne $c.'bevy_anti_alias::fxaa::Fxaa'), ($null -ne $c.'bevy_pbr::ssao::ScreenSpaceAmbientOcclusion'))
}
# UiGlobalTransform maps 1:1 to window physical px on this machine (the panel
# container spans 943..1276 inside the 1280px window).
function Ui-ToScreen([double]$X, [double]$Y) {
    $r = $script:WinRect
    return @{ X = [int]($r.L + $X); Y = [int]($r.T + $Y) }
}
function Click-Real([double]$X, [double]$Y) {
    $p = Ui-ToScreen $X $Y
    [JdInput]::SetCursorPos($p.X, $p.Y) | Out-Null
    Start-Sleep -Milliseconds 150
    foreach ($try in 1..3) {
        try {
            [JdInput]::LmbDown(); Start-Sleep -Milliseconds 80; [JdInput]::LmbUp()
            break
        } catch {
            Write-Host "  SendInput retry $try after error"
            Focus-Jackdaw $script:Hwnd
            [JdInput]::SetCursorPos($p.X, $p.Y) | Out-Null
            Start-Sleep -Milliseconds 200
        }
    }
    Start-Sleep -Milliseconds 200
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru -RedirectStandardOutput "$env:TEMP\jd-out.log" -RedirectStandardError "$env:TEMP\jd-err6.log"
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    $script:CamId = [string](Get-FlyCamera).Entity
    Raw 'jackdaw/call_operator' @{ id = 'graphics.open'; params = @{} } | Out-Null
    Frames 12; Start-Sleep -Milliseconds 500

    $script:Hwnd = Get-JackdawHwnd
    Focus-Jackdaw $script:Hwnd
    $rect = New-Object JdInput+RECT
    [JdInput]::GetWindowRect($script:Hwnd, [ref]$rect) | Out-Null
    $script:WinRect = $rect
    Write-Host ("window phys {0}x{1} at ({2},{3}); UI coords map 1:1" -f ($rect.R - $rect.L), ($rect.B - $rect.T), $rect.L, $rect.T)

    $smaa = @(Rows | Where-Object { $_.text -eq 'SMAA' })[0]
    Click-Real $smaa.cx $smaa.cy; Frames 10
    Write-Host ("after REAL SMAA click: {0}" -f (CamState))

    $ao = @(Rows | Where-Object { $_.text -eq 'Ambient Occlusion' })[0]
    Click-Real ($ao.cx - $ao.w/2 - 36) $ao.cy; Frames 10
    Write-Host ("after REAL AO click: {0}" -f (CamState))

    $fog = @(Rows | Where-Object { $_.text -eq 'Fog' })[0]
    Click-Real ($fog.cx - $fog.w/2 - 36) $fog.cy; Frames 10
    # fog state not in camera comps; use operator-log count instead
    Write-Host '--- op log tail:'
    Get-Content "$env:TEMP\jd-err6.log" -Tail 20 | Select-String -Pattern 'OPERATOR:' | ForEach-Object { ($_.Line -replace '.*[0-9]Z ', '') -replace '\x1b\[[0-9;]*m', '' }
} finally {
    try {
        Raw 'jackdaw/call_operator' @{ id = 'viewport.quality.set'; params = @{ anti_aliasing = 'fxaa' } } | Out-Null
        Raw 'jackdaw/call_operator' @{ id = 'viewport.ssao.set'; params = @{ on = $false } } | Out-Null
        Raw 'jackdaw/call_operator' @{ id = 'viewport.show.toggle'; params = @{ flag = 'fog'; on = $true } } | Out-Null
    } catch {}
    Start-Sleep -Milliseconds 500
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
