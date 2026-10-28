# feature-05 final QA: concerns-1 probe — is a light's component card reachable in ANY
# inspector category tab? Select the ORIGINAL "Spot Light", click every strip icon,
# dump the panel after each, and BRP-query the live component as the "data is there" leg.
param(
    [int]$Port = 15703,
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [string]$OutDir = 'E:\Project\rust\jackdaw\loop\reports\f5-final-qa'
)
$ErrorActionPreference = 'Stop'
. 'E:\Project\rust\jackdaw\loop\qa\brp.ps1' -Port $Port
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

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
function Dump-Panel([string]$Tag) {
    $rows = Get-UiRows | Where-Object { $_.cx -gt 1050 -and $_.cy -gt 95 -and $_.cy -lt 1060 } | Sort-Object cy, cx
    $rows | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $OutDir "$Tag.json") -Encoding UTF8
    Write-Host ("-- {0}: {1} panel rows" -f $Tag, @($rows).Count)
    $rows | ForEach-Object { $t = $_.text; if ($t.Length -gt 26) { $t = $t.Substring(0, 26) + '..' }; Write-Host ('   [{0,7:N1},{1,7:N1}] {2}' -f $_.cx, $_.cy, $t) }
    return $rows
}

# 0) BRP leg: live SpotLight component data on the entity named Spot Light (data-present proof)
$ent = Brp-Result (Brp-Call 'jackdaw/entity' @{ name = 'Spot Light' })
$ent | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $OutDir 'spotlight-entity.json') -Encoding UTF8
Write-Host ("jackdaw/entity Spot Light -> entity bits: {0}" -f $ent.entity)
$gc = Invoke-BrpRaw 'world.get_components' @{ components = @('bevy_light::spot_light::SpotLight', 'bevy_transform::components::transform::Transform'); entity = $ent.entity }
$gc | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $OutDir 'spotlight-live-components.json') -Encoding UTF8
$hasSpot = $false
if ($gc.result.components) { $hasSpot = $null -ne $gc.result.components.'bevy_light::spot_light::SpotLight' }
Write-Host ("world.get_components live SpotLight present: {0}" -f $hasSpot)

# 1) select the original Spot Light row in the outliner
$rows = Get-UiRows
$spotRow = $rows | Where-Object { $_.text -eq 'Spot Light' -and $_.cx -lt 300 -and $_.cy -gt 150 } | Select-Object -First 1
if (-not $spotRow) { throw 'no Spot Light row in the outliner' }
Write-Host ("clicking Spot Light row at ({0:N1},{1:N1})" -f $spotRow.cx, $spotRow.cy)
Click-At ([double]$spotRow.cx / 1.5) ([double]$spotRow.cy / 1.5)
Wait-Frames 8; Start-Sleep -Milliseconds 500
$panel = Dump-Panel 'l0-object-default'
$status = Get-UiRows | Where-Object { $_.text -like 'Entity:*' }
Write-Host ("selection status text: {0}" -f (@($status) | ForEach-Object { $_.text }) -join ' | ')

# 2) find the category strip icons: small square icon nodes in the inspector header band,
#    left of the Add Component button, y between 100 and 200.
$all = Get-UiRows | Where-Object { $_.cy -gt 95 -and $_.cy -lt 210 }
$addComp = $all | Where-Object { $_.text -eq 'Add Component' } | Select-Object -First 1
Write-Host ("Add Component at ({0:N1},{1:N1})" -f $addComp.cx, $addComp.cy)
# icons: rows whose text is a short glyph (len <= 3) and non-ascii, in the band left of Add Component
$icons = $all | Where-Object { $_.text.Length -le 3 -and $_.cx -lt $addComp.cx -and $_.cx -gt 1000 -and $_.w -le 30 } | Sort-Object cx
$icons | ForEach-Object { Write-Host ("icon candidate [{0,7:N1},{1,7:N1}] w={2:N0} len={3}" -f $_.cx, $_.cy, $_.w, $_.text.Length) }

# Also dump the full-window rows near the inspector's left edge (vertical strip case).
$vs = Get-UiRows | Where-Object { $_.cx -gt 1000 -and $_.cx -le 1105 -and $_.cy -gt 100 -and $_.cy -lt 700 }
$vs | ForEach-Object { $t = $_.text; if ($t.Length -gt 20) { $t = $t.Substring(0, 20) }; Write-Host ("left-edge [{0,7:N1},{1,7:N1}] {2}" -f $_.cx, $_.cy, $t) }

# 3) click each icon candidate, dump, look for light fields
$fieldRx = 'color|Color|intensity|Intensity|range|Range|shadow|Shadow|SpotLight|PointLight|DirectionalLight|spot|Spot'
$idx = 0
foreach ($ic in $icons) {
    $idx++
    Click-At ([double]$ic.cx / 1.5) ([double]$ic.cy / 1.5)
    Wait-Frames 8; Start-Sleep -Milliseconds 450
    $p = Dump-Panel ("l$idx-icon-{0:N0}-{1:N0}" -f $ic.cx, $ic.cy)
    $hits = @($p | Where-Object { $_.text -match $fieldRx })
    Write-Host ("   >>> icon {0}: light-field hits = {1}" -f $idx, $hits.Count)
}
Write-Host 'DONE lightprobe'
