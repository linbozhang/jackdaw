param(
    [int]$Port = 15713,
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [string]$OutDir = 'E:\Project\rust\jackdaw\loop\reports\t02t1-race'
)
$ErrorActionPreference = 'Stop'
. 'E:\Project\rust\jackdaw\loop\qa\brp.ps1' -Port $Port
function Invoke-BrpRaw([string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 12 -Compress
    $w = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing -TimeoutSec 30
    return [System.Text.Encoding]::UTF8.GetString($w.RawContentStream.ToArray()) | ConvertFrom-Json
}
function Op([string]$Id, $Params) { Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = $Id; params = $Params }) | Out-Null }
function Click-At([double]$x, [double]$y) { Op 'input.pointer' @{ x = $x; y = $y; action = 'click' } }
function Wait-Frames([int]$n) { try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 } }
function Get-UiRows {
    $j = Invoke-BrpRaw 'world.query' @{ data = @{ components = @('bevy_ui::widget::text::Text', 'bevy_ui::ui_node::ComputedNode', 'bevy_ui::ui_transform::UiGlobalTransform') } }
    return $j.result | Where-Object { $_.components.'bevy_ui::ui_node::ComputedNode'.size[0] -gt 0 } | ForEach-Object {
        $a = $_.components.'bevy_ui::ui_transform::UiGlobalTransform'
        $s = $_.components.'bevy_ui::ui_node::ComputedNode'.size
        [pscustomobject]@{ text = $_.components.'bevy_ui::widget::text::Text'; cx = [double]$a[4]; cy = [double]$a[5]; w = [double]$s[0]; h = [double]$s[1] }
    }
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$p = Start-Process -FilePath $Exe -WorkingDirectory $Project -RedirectStandardError "$OutDir\probe.err" -RedirectStandardOutput "$OutDir\probe.out" -PassThru
try {
    Wait-EditorReady
    try { Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 60 | Out-Null } catch { Start-Sleep -Seconds 2 }
    $rows = Get-UiRows
    $xs = @($rows | ForEach-Object { $_.cx })
    $ys = @($rows | ForEach-Object { $_.cy })
    Write-Host ("total rows: {0}; x {1:N0}..{2:N0}; y {3:N0}..{4:N0}" -f @($rows).Count, ($xs | Measure-Object -Minimum).Minimum, ($xs | Measure-Object -Maximum).Maximum, ($ys | Measure-Object -Minimum).Minimum, ($ys | Measure-Object -Maximum).Maximum)
    $cube = $rows | Where-Object { $_.text -eq 'Cube' -and $_.cx -lt 400 -and $_.cy -gt 150 } | Sort-Object cy | Select-Object -First 1
    if (-not $cube) { throw 'no Cube outliner row' }
    Write-Host ("Cube row at ({0:N0},{1:N1})" -f $cube.cx, $cube.cy)
    Click-At ([double]$cube.cx) ([double]$cube.cy)
    Wait-Frames 8; Start-Sleep -Milliseconds 600
    $rows = Get-UiRows
    $rows | Sort-Object cx, cy | ForEach-Object {
        $t = $_.text; if ($t.Length -gt 40) { $t = $t.Substring(0, 40) + '..' }
        Write-Host ('{0,7:N0} {1,7:N0} w={2,5:N0}  {3}' -f $_.cx, $_.cy, $_.w, $t)
    } | Out-File "$OutDir\panel-dump.txt" -Encoding utf8
    Get-Content "$OutDir\panel-dump.txt" | Select-Object -First 120
    try {
        $r = Wait-BrpResult 'jackdaw/screenshot' @{ kind = 'window'; path = 'screenshots/t02t1-probe.png' } -TimeoutSec 20
        Copy-Item "$Project\screenshots\t02t1-probe.png" "$OutDir\t02t1-probe.png" -Force
        Write-Host 'probe shot saved'
    } catch { Write-Host "shot failed: $_" }
}
finally { Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force }

