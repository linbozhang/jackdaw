# Probe 10: checkbox clickability with generous settle + hover-first, plus a
# control checkbox elsewhere in the editor (BRP-readable Checked component).
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
function Ptr([string]$Action, [double]$X, [double]$Y) {
    Raw 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = $X; y = $Y; action = $Action } } | Out-Null
}
function Frames([int]$n) { try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 } }
function Has-Ssao {
    $r = Raw 'world.get_components' @{ entity = $script:CamId; components = @('bevy_pbr::ssao::ScreenSpaceAmbientOcclusion') }
    return ($null -ne $r.result.components.'bevy_pbr::ssao::ScreenSpaceAmbientOcclusion')
}
# count Checked components (BRP-readable via bevy_ui::Checked reflect)
function Checked-Count {
    $j = Raw 'world.query' @{ data = @{ components = @('bevy_ui::Checked') } }
    return @($j.result).Count
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru -RedirectStandardOutput "$env:TEMP\jd-out.log" -RedirectStandardError "$env:TEMP\jd-err7.log"
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    $script:CamId = [string](Get-FlyCamera).Entity
    Raw 'jackdaw/call_operator' @{ id = 'graphics.open'; params = @{} } | Out-Null
    Frames 30; Start-Sleep -Seconds 5

    $ao = @(Rows | Where-Object { $_.text -eq 'Ambient Occlusion' })[0]
    $boxY = $ao.cy
    foreach ($x in 925, 931, 937, 943, 949, 955, 961) {
        Ptr 'move' $x $boxY; Frames 8; Start-Sleep -Milliseconds 300
        Ptr 'click' $x $boxY; Frames 10
        Write-Host ("AO box x={0}: Ssao={1}" -f $x, (Has-Ssao))
        if (Has-Ssao) {
            Write-Host '  SSAO ON achieved; now clicking again for OFF:'
            Ptr 'move' $x $boxY; Frames 8; Start-Sleep -Milliseconds 300
            Ptr 'click' $x $boxY; Frames 10
            Write-Host ("  after 2nd click: Ssao={0}" -f (Has-Ssao))
            break
        }
    }
    # control: any other checkbox outside the Graphics panel? dump candidates
    Write-Host '--- texts that look like toggles outside the panel:'
    Rows | Where-Object { $_.cx -lt 900 -and $_.cy -gt 60 -and $_.cy -lt 120 } | Format-Table -AutoSize | Out-String -Width 100 | Write-Host
    Write-Host ("Checked-component entities: {0}" -f (Checked-Count))
    Write-Host '--- op log tail:'
    Get-Content "$env:TEMP\jd-err7.log" -Tail 30 | Select-String -Pattern 'OPERATOR:' | ForEach-Object { ($_.Line -replace '.*[0-9]Z ', '') -replace '\x1b\[[0-9;]*m', '' }
} finally {
    try {
        Raw 'jackdaw/call_operator' @{ id = 'viewport.ssao.set'; params = @{ on = $false } } | Out-Null
    } catch {}
    Start-Sleep -Milliseconds 500
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
