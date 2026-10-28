# R3 D10.3: select the newest Cube in the outliner, edit Transform.translation.x to 2 via
# the Inspector's numeric field, assert the scene bsn picked it up, screenshot the move.
param(
    [int]$Port = 15703,
    [string]$OutDir = 'E:\Project\rust\jackdaw\loop\reports\r3-add-e2e',
    [string]$Value = '2'
)
$ErrorActionPreference = 'Stop'
. 'E:\Project\rust\jackdaw\loop\qa\brp.ps1' -Port $Port

function Invoke-BrpRaw([string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 12 -Compress
    $w = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing -TimeoutSec 30
    return [System.Text.Encoding]::UTF8.GetString($w.RawContentStream.ToArray()) | ConvertFrom-Json
}
function Click-At([double]$x, [double]$y) {
    Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = $x; y = $y; action = 'click' } }) | Out-Null
}
function Wait-Frames([int]$n) {
    try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 }
}
function Type-Text([string]$t) {
    Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.text'; params = @{ text = $t } }) | Out-Null
}
function Key([string]$k) {
    Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.key'; params = @{ key = $k } }) | Out-Null
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
# The LAST '#Cube' entity block in the bsn: return its translation lines.
function Get-LastCubeTranslation([string]$bsn) {
    $idx = $bsn.LastIndexOf('#Cube')
    if ($idx -lt 0) { return $null }
    $chunk = $bsn.Substring($idx, [Math]::Min(3000, $bsn.Length - $idx))
    if ($chunk -match 'translation:\s*glam::Vec3\s*\{\s*x:\s*([-\d.eE+]+),\s*y:\s*([-\d.eE+]+),\s*z:\s*([-\d.eE+]+)') {
        return @{ x = [double]$Matches[1]; y = [double]$Matches[2]; z = [double]$Matches[3] }
    }
    return $null
}

# 1) select the newest Cube row in the outliner (last row named exactly Cube)
$rows = Get-UiRows
$cubes = $rows | Where-Object { $_.text -eq 'Cube' -and $_.cx -lt 300 -and $_.cy -gt 190 } | Sort-Object cy
if (@($cubes).Count -lt 1) { throw 'no Cube row in the outliner' }
$newest = $cubes[-1]
Write-Host ("outliner Cube rows: {0}; clicking the newest at ({1:N1},{2:N1})" -f @($cubes).Count, $newest.cx, $newest.cy)
Click-At ([double]$newest.cx / 1.5) ([double]$newest.cy / 1.5)
Wait-Frames 8
Start-Sleep -Milliseconds 500

# 2) dump the right panel around the Transform section; candidate numeric fields
Shot 'window' 'r3-05-selected-cube-window.png'
$panel = Get-UiRows | Where-Object { $_.cx -gt 1300 -and $_.cy -gt 100 -and $_.cy -lt 560 } | Sort-Object cy
$panel | ForEach-Object { $t = $_.text; if ($t.Length -gt 22) { $t = $t.Substring(0, 22) + '..' }; Write-Host ('{0,7:N1} {1,7:N1}  {2}' -f $_.cx, $_.cy, $t) }
$t = Get-LastCubeTranslation (Get-SceneBsn)
if ($t) { Write-Host ("last Cube translation now: x={0} y={1} z={2}" -f $t.x, $t.y, $t.z) }

# candidate value fields: pure numeric texts under the Transform header (first three = x, y, z of translation)
$transformHeader = $panel | Where-Object { $_.text -eq 'Transform' } | Select-Object -First 1
if (-not $transformHeader) { throw 'Inspector shows no Transform section' }
$fields = $panel | Where-Object {
    $_.cy -gt $transformHeader.cy -and $_.cy -lt ($transformHeader.cy + 130) -and
    $_.text -match '^[+-]?[\d.]+$'
} | Sort-Object cy, cx
Write-Host ("candidate numeric fields: {0}" -f (@($fields) | ForEach-Object { ('({0:N0},{1:N0})={2}' -f $_.cx, $_.cy, $_.text) }) -join ' ')

if (@($fields).Count -lt 3) { throw 'expected the three translation fields under Transform' }
$target = $fields[0]   # smallest y then smallest x = x field
Write-Host ("clicking translation.x field at ({0:N1},{1:N1}) and typing {2}" -f $target.cx, $target.cy, $Value)
Click-At ([double]$target.cx / 1.5) ([double]$target.cy / 1.5)
Wait-Frames 5
Start-Sleep -Milliseconds 300
Type-Text $Value
Wait-Frames 5
Start-Sleep -Milliseconds 200
Key 'Enter'
Wait-Frames 8
Start-Sleep -Milliseconds 500

$t2 = Get-LastCubeTranslation (Get-SceneBsn)
if (-not $t2) { throw 'no translation found for the last Cube after the edit' }
Write-Host ("last Cube translation after: x={0} y={1} z={2}" -f $t2.x, $t2.y, $t2.z)
if ([math]::Abs($t2.x - [double]$Value) -gt 0.001) { throw "translation.x is $($t2.x), expected $Value" }
Shot 'viewport' 'r3-06-after-translate-viewport.png'
Shot 'window' 'r3-06-after-translate-window.png'
Write-Host 'PASS inspector-translate'
