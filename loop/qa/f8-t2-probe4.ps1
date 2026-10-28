# Bisect probe: which open-phase step breaks the SMAA click afterwards?
param([int]$Port = 15703, [string]$Steps = 'menu,shots,clicks')
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
function Has([string]$Path) {
    $r = Raw 'world.get_components' @{ entity = $script:CamId; components = @($Path) }
    return ($null -ne $r.result.components.$Path)
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru -RedirectStandardOutput "$env:TEMP\jd-out.log" -RedirectStandardError "$env:TEMP\jd-err.log"
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    $script:CamId = [string](Get-FlyCamera).Entity

    if ($Steps -like '*menu*') {
        $win = @(Rows | Where-Object { $_.text -eq 'Window' } | Sort-Object cy)[0]
        Click $win.cx $win.cy
        Frames 8; Start-Sleep -Milliseconds 400
        $gfx = Rows | Where-Object { $_.text -eq 'Graphics' }
        Write-Host ("menu step: Graphics candidates = " -f ($gfx | ConvertTo-Json -Compress))
        if ($gfx) {
            $g = @($gfx | Where-Object { $_.cx -gt 100 })[0]
            if ($g) { Click $g.cx $g.cy; Frames 10; Start-Sleep -Milliseconds 400; Write-Host "clicked Graphics menu entry" }
            else { Write-Host 'no valid-position Graphics entry; menu did not open?' }
        }
    }
    if ($Steps -like '*shots*') {
        Wait-BrpResult 'jackdaw/screenshot' @{ kind = 'window'; path = 'screenshots/bisect-w.png' } -TimeoutSec 30 | Out-Null
        Write-Host 'window shot taken'
        Frames 6
    }

    # A1 clicks regardless
    $fxaa = @(Rows | Where-Object { $_.text -eq 'FXAA' })[0]
    Click $fxaa.cx $fxaa.cy; Frames 8
    Write-Host ("FXAA present after FXAA click: {0}" -f (Has 'bevy_anti_alias::fxaa::Fxaa'))
    $smaa = @(Rows | Where-Object { $_.text -eq 'SMAA' })[0]
    Click $smaa.cx $smaa.cy; Frames 12
    Write-Host ("SMAA present after SMAA click: {0}  FXAA present: {1}" -f (Has 'bevy_anti_alias::smaa::Smaa'), (Has 'bevy_anti_alias::fxaa::Fxaa'))
    Write-Host '--- stderr tail (warnings):'
    Get-Content "$env:TEMP\jd-err.log" -Tail 15 | Select-String -Pattern 'WARN|ERROR|OPERATOR' | ForEach-Object { $_.Line }
} finally {
    try { Raw 'jackdaw/call_operator' @{ id = 'viewport.quality.set'; params = @{ anti_aliasing = 'fxaa' } } | Out-Null } catch {}
    Start-Sleep -Milliseconds 300
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
