# R3 D10.5 retry: Add Entity picker with robust row discovery.
param(
    [int]$Port = 15703,
    [string]$OutDir = 'E:\Project\rust\jackdaw\loop\reports\r3-add-e2e'
)
$ErrorActionPreference = 'Stop'
. 'E:\Project\rust\jackdaw\loop\qa\brp.ps1' -Port $Port

function Invoke-BrpRaw([string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 12 -Compress
    $w = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing -TimeoutSec 30
    return [System.Text.Encoding]::UTF8.GetString($w.RawContentStream.ToArray()) | ConvertFrom-Json
}
function Op($p) { Brp-Result (Brp-Call 'jackdaw/call_operator' $p) | Out-Null }
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
    return [string]$r.bsn
}
function Shot([string]$kind, [string]$relName) {
    $r = Wait-BrpResult 'jackdaw/screenshot' @{ kind = $kind; path = "screenshots/$relName" } -TimeoutSec 20
    Copy-Item "C:\Users\linbo.zhang\Projects\my-game\screenshots\$relName" (Join-Path $OutDir $relName) -Force
    Write-Host ("shot {0}: {1}x{2}" -f $relName, $r.width, $r.height)
}

$before = ([regex]::Matches((Get-SceneBsn), '(?m)^\s*#Cube\r?\s*$')).Count
Write-Host "exact cubes before: $before"

# 1) open the picker
Op @{ id = 'input.pointer'; params = @{ x = 71.3; y = 111.3; action = 'click' } }
Wait-Frames 8
Start-Sleep -Milliseconds 500
$rows = Get-UiRows
$pickerRows = $rows | Where-Object { $_.cy -gt 130 -and $_.cy -lt 640 -and $_.cx -gt 300 -and $_.cx -lt 1300 }
if (@($pickerRows).Count -eq 0) { throw 'Add Entity picker did not open' }
Write-Host '--- picker rows (unfiltered) ---'
$pickerRows | Sort-Object cy | ForEach-Object { $t = $_.text; if ($t.Length -gt 40) { $t = $t.Substring(0, 40) + '..' }; Write-Host ('{0,7:N1} {1,7:N1}  {2}' -f $_.cx, $_.cy, $t) }
Shot 'window' 'r3-07b-picker-open-window.png'

# 2) type the filter (the picker's input is auto-focused)
Op @{ id = 'input.text'; params = @{ text = 'cube' } }
Wait-Frames 8
Start-Sleep -Milliseconds 500
$rows = Get-UiRows
$pickerRows = $rows | Where-Object { $_.cy -gt 130 -and $_.cy -lt 640 -and $_.cx -gt 300 -and $_.cx -lt 1300 }
Write-Host '--- picker rows (filtered "cube") ---'
$pickerRows | Sort-Object cy | ForEach-Object { $t = $_.text; if ($t.Length -gt 40) { $t = $t.Substring(0, 40) + '..' }; Write-Host ('{0,7:N1} {1,7:N1}  {2}' -f $_.cx, $_.cy, $t) }
Shot 'window' 'r3-07c-picker-filtered-window.png'

$row = $pickerRows | Where-Object { $_.text -eq 'Cube' } | Sort-Object cy | Select-Object -First 1
if (-not $row) { throw 'filtered picker shows no Cube row' }
Op @{ id = 'input.pointer'; params = @{ x = ([double]$row.cx / 1.5); y = ([double]$row.cy / 1.5); action = 'click' } }
Wait-Frames 10
Start-Sleep -Milliseconds 500

$after = ([regex]::Matches((Get-SceneBsn), '(?m)^\s*#Cube\r?\s*$')).Count
Write-Host "exact cubes after: $after"
if ($after -le $before) { throw 'picker Cube click created no entity' }
Shot 'window' 'r3-08-after-picker-cube-window.png'
Shot 'viewport' 'r3-08-after-picker-cube-viewport.png'
Write-Host 'PASS picker-add-entity'
