# R3: one-shot Add-menu -> 3D Objects -> Cube click with in-process UI row lookup.
param(
    [int]$Port = 15703,
    [string]$OutDir = 'E:\Project\rust\jackdaw\loop\reports\r3-add-e2e',
    [string]$Label = 'menu-cube'
)
$ErrorActionPreference = 'Stop'
. 'E:\Project\rust\jackdaw\loop\qa\brp.ps1' -Port $Port

function Invoke-BrpRaw([string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 12 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $w = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body $bytes -UseBasicParsing -TimeoutSec 30
    return [System.Text.Encoding]::UTF8.GetString($w.RawContentStream.ToArray()) | ConvertFrom-Json
}
function Click-At([double]$x, [double]$y) {
    Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = $x; y = $y; action = 'click' } }) | Out-Null
}
function Hover-At([double]$x, [double]$y) {
    Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = $x; y = $y; action = 'move' } }) | Out-Null
}
function Wait-Frames([int]$n) {
    try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 }
}
function Get-UiRows {
    $j = Invoke-BrpRaw 'world.query' @{ data = @{ components = @('bevy_ui::widget::text::Text', 'bevy_ui::ui_node::ComputedNode', 'bevy_ui::ui_transform::UiGlobalTransform') } }
    return $j.result | Where-Object { $_.components.'bevy_ui::ui_node::ComputedNode'.size[0] -gt 0 } | ForEach-Object {
        $a = $_.components.'bevy_ui::ui_transform::UiGlobalTransform'
        $s = $_.components.'bevy_ui::ui_node::ComputedNode'.size
        [pscustomobject]@{ text = $_.components.'bevy_ui::widget::text::Text'; cx = [double]$a[4]; cy = [double]$a[5]; w = [double]$s[0]; h = [double]$s[1] }
    }
}
function Get-SceneBsn {
    $r = (Invoke-BrpRaw 'jackdaw/scene_bsn' @{}).result
    if ($r -is [string]) { return $r }
    if ($r.bsn) { return [string]$r.bsn }
    return [string]$r
}

$before = ([regex]::Matches((Get-SceneBsn), '(?m)^\s*#Cube\s*$')).Count
Write-Host "exact '#Cube' headers before: $before"

# 1) open the Add menu (menu bar Add at physical 199.5x26 -> logical /1.5)
Click-At 133.0 17.3
Wait-Frames 6
Start-Sleep -Milliseconds 300
$group = Get-UiRows | Where-Object { $_.text -eq '3D Objects' }
if (-not $group) { throw 'Add dropdown did not open: no "3D Objects" row' }
Write-Host ("dropdown open; 3D Objects at ({0:N1},{1:N1})" -f $group.cx, $group.cy)

# 2) hover the group to expand its submenu (dwell), then find the Cube row
Hover-At ([double]$group.cx / 1.5) ([double]$group.cy / 1.5)
Wait-Frames 6
Start-Sleep -Milliseconds 700
$sub = Get-UiRows | Where-Object { $_.text -eq 'Cube' -and $_.cx -gt ($group.cx + 150) -and [math]::Abs($_.cy - $group.cy) -lt 140 }
if (-not $sub) { throw 'submenu did not expand: no Cube row beside 3D Objects' }
Write-Host ("submenu Cube row at ({0:N1},{1:N1})" -f $sub.cx, $sub.cy)

# 3) click the Cube row
Click-At ([double]$sub.cx / 1.5) ([double]$sub.cy / 1.5)
Wait-Frames 8
Start-Sleep -Milliseconds 400

$after = ([regex]::Matches((Get-SceneBsn), '(?m)^\s*#Cube\s*$')).Count
Write-Host "exact '#Cube' headers after: $after"
if ($after -le $before) { throw 'clicking the Cube menu row created no entity' }

# 4) evidence: screenshots + the new Cube's bsn summary
$r = Wait-BrpResult 'jackdaw/screenshot' @{ kind = 'viewport'; path = "screenshots/r3-$Label-v.png" } -TimeoutSec 20
Copy-Item "C:\Users\linbo.zhang\Projects\my-game\screenshots\r3-$Label-v.png" (Join-Path $OutDir "$Label-viewport.png") -Force
$r2 = Wait-BrpResult 'jackdaw/screenshot' @{ kind = 'window'; path = "screenshots/r3-$Label-w.png" } -TimeoutSec 20
Copy-Item "C:\Users\linbo.zhang\Projects\my-game\screenshots\r3-$Label-w.png" (Join-Path $OutDir "$Label-window.png") -Force
Write-Host ("shots: viewport {0}x{1} window {2}x{3}" -f $r.width, $r.height, $r2.width, $r2.height)
Write-Host 'PASS menu-cube'
