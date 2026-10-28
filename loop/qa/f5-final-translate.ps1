# translate.x edit on the newest Cube: reset the strip to the Object tab first
# (a sticky Components tab from an earlier probe leaves the panel empty for a Cube),
# then click the numeric field, clear it with Backspace x4, type the value, Enter.
param([int]$Port = 15703, [string]$Value = '2', [string]$OutDir = 'E:\Project\rust\jackdaw\loop\reports\f5-final-qa')
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
function Click-At([double]$x, [double]$y) {
    Op @{ id = 'input.pointer'; params = @{ x = $x; y = $y; action = 'click' } }
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
function Get-LastCubeTranslation([string]$bsn) {
    $idx = $bsn.LastIndexOf('#Cube')
    if ($idx -lt 0) { return $null }
    $chunk = $bsn.Substring($idx, [Math]::Min(3000, $bsn.Length - $idx))
    if ($chunk -match 'translation:\s*glam::Vec3\s*\{\s*x:\s*([-\d.eE+]+),\s*y:\s*([-\d.eE+]+),\s*z:\s*([-\d.eE+]+)') {
        return @{ x = [double]$Matches[1]; y = [double]$Matches[2]; z = [double]$Matches[3] }
    }
    return $null
}

# 1) select the newest Cube row (the added one)
$rows = Get-UiRows
$cubes = @($rows | Where-Object { $_.text -eq 'Cube' -and $_.cx -lt 300 -and $_.cy -gt 190 } | Sort-Object cy)
if ($cubes.Count -lt 2) { throw ("expected 2 Cube rows, got {0}" -f $cubes.Count) }
$newest = $cubes[-1]
Click-At ([double]$newest.cx / 1.5) ([double]$newest.cy / 1.5)
Wait-Frames 8; Start-Sleep -Milliseconds 500
$status = Get-UiRows | Where-Object { $_.text -like 'Entity:*' }
Write-Host ("selection: {0}" -f ((@($status) | ForEach-Object { $_.text }) -join ' | '))

# 2) reset the strip: click the TOP strip icon (Object)
$rows = Get-UiRows
$strip = @($rows | Where-Object { [math]::Abs($_.cx - 1330) -le 12 -and $_.w -le 30 -and $_.cy -gt 100 -and $_.cy -lt 220 } | Sort-Object cy)
$strip | ForEach-Object { Write-Host ("strip icon [{0:N1},{1:N1}]" -f $_.cx, $_.cy) }
$obj = $strip[0]
Click-At ([double]$obj.cx / 1.5) ([double]$obj.cy / 1.5)
Wait-Frames 8; Start-Sleep -Milliseconds 500

# 3) find the Transform section and its translation.x field
$panel = Get-UiRows | Where-Object { $_.cx -gt 1300 -and $_.cy -gt 100 -and $_.cy -lt 620 } | Sort-Object cy, cx
$panel | ForEach-Object { $t = $_.text; if ($t.Length -gt 24) { $t = $t.Substring(0, 24) }; Write-Host ('   [{0,7:N1},{1,7:N1}] {2}' -f $_.cx, $_.cy, $t) }
$tHeader = $panel | Where-Object { $_.text -eq 'Transform' } | Select-Object -First 1
if (-not $tHeader) { throw 'no Transform card after Object tab reset' }
# the card body starts collapsed: click the header until the translation row shows
for ($try = 1; $try -le 2; $try++) {
    Click-At ([double]$tHeader.cx / 1.5) ([double]$tHeader.cy / 1.5)
    Wait-Frames 8; Start-Sleep -Milliseconds 500
    $panel = Get-UiRows | Where-Object { $_.cx -gt 1300 -and $_.cy -gt 100 -and $_.cy -lt 620 } | Sort-Object cy, cx
    if ($panel | Where-Object { $_.text -eq 'translation' }) { break }
    Write-Host "translation row not visible after click $try; retrying (toggle)"
}
$panel | ForEach-Object { $t = $_.text; if ($t.Length -gt 24) { $t = $t.Substring(0, 24) }; Write-Host ('   [{0,7:N1},{1,7:N1}] {2}' -f $_.cx, $_.cy, $t) }
$xLabel = $panel | Where-Object { $_.text -eq 'X' -and $_.cy -gt $tHeader.cy -and $_.cy -lt ($tHeader.cy + 120) } | Sort-Object cy | Select-Object -First 1
if (-not $xLabel) { throw 'no X label under translation' }
# the value input is a ScrubNumberInput (its text is not a Text widget): click
# just right of the X label to focus translation.x's numeric field.
$fieldX = [double]$xLabel.cx + 100.0
$fieldY = [double]$xLabel.cy
$t0 = Get-LastCubeTranslation (Get-SceneBsn)
Write-Host ("translation.x input at ~({0:N1},{1:N1}); bsn before: x={2}" -f $fieldX, $fieldY, $t0.x)

# 4) click, clear, type, commit
Click-At ($fieldX / 1.5) ($fieldY / 1.5)
Wait-Frames 5; Start-Sleep -Milliseconds 300
foreach ($i in 1..4) { Op @{ id = 'input.key'; params = @{ key = 'Backspace' } }; Wait-Frames 2 }
Start-Sleep -Milliseconds 150
Op @{ id = 'input.text'; params = @{ text = $Value } }
Wait-Frames 5; Start-Sleep -Milliseconds 200
Op @{ id = 'input.key'; params = @{ key = 'Enter' } }
Wait-Frames 10; Start-Sleep -Milliseconds 600

# 5) assert the document picked it up
$t1 = Get-LastCubeTranslation (Get-SceneBsn)
if (-not $t1) { throw 'no translation for last Cube after edit' }
Write-Host ("last Cube translation after: x={0} y={1} z={2}" -f $t1.x, $t1.y, $t1.z)
if ([math]::Abs($t1.x - [double]$Value) -gt 0.001) { throw ("translation.x is {0}, expected {1}" -f $t1.x, $Value) }

$r = Wait-BrpResult 'jackdaw/screenshot' @{ kind = 'viewport'; path = 'screenshots/f5-after-translate-v.png' } -TimeoutSec 20
Copy-Item 'C:\Users\linbo.zhang\Projects\my-game\screenshots\f5-after-translate-v.png' (Join-Path $OutDir 'f5-after-translate-viewport.png') -Force
Write-Host 'PASS f5-translate'
