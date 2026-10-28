# follow-up: (a) live SpotLight data via world.query (b) restore 3D mode (c) add a fresh
# Point Light, select it, open the Components tab, dump — does the new light get a card?
param([int]$Port = 15703, [string]$OutDir = 'E:\Project\rust\jackdaw\loop\reports\f5-final-qa')
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

# (a) live data leg: world.query for SpotLight holders
$q = Invoke-BrpRaw 'world.query' @{ data = @{ components = @('bevy_light::spot_light::SpotLight'); option = @('bevy_transform::components::transform::Transform') }; filter = @{ with = @('bevy_light::spot_light::SpotLight') } }
$q | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $OutDir 'spotlight-world-query.json') -Encoding UTF8
$n = @($q.result).Count
Write-Host ("world.query SpotLight holders: {0}" -f $n)
foreach ($r in @($q.result)) {
    $t = $r.components.'bevy_transform::components::transform::Transform'
    if ($t) { Write-Host ("  entity {0}: translation y={1}" -f $r.entity, $t.translation.y) }
}
if ($n -lt 1) { throw 'no live SpotLight component found' }

# (b) restore 3D viewport mode if the toolbar currently shows Fit/Edit/Interact (2D mode)
$rows = Get-UiRows
if ($rows | Where-Object { $_.text -eq 'Interact' }) {
    $b3d = $rows | Where-Object { $_.text -eq '3D' } | Select-Object -First 1
    Write-Host ("restoring 3D mode: clicking ({0:N1},{1:N1})" -f $b3d.cx, $b3d.cy)
    Click-At ([double]$b3d.cx / 1.5) ([double]$b3d.cy / 1.5)
    Wait-Frames 8; Start-Sleep -Milliseconds 400
}

# (c) fresh Point Light via BRP op, select via outliner, open Components tab
$before = ([regex]::Matches((Get-SceneBsn), '(?m)^#\"?Point Light\"?\r?$')).Count
Op @{ id = 'entity.add.point_light' }
Wait-Frames 10; Start-Sleep -Milliseconds 500
$after = ([regex]::Matches((Get-SceneBsn), '(?m)^#\"?Point Light\"?\r?$')).Count
Write-Host ("Point Light headers: {0} -> {1}" -f $before, $after)

$rows = Get-UiRows
$plRow = $rows | Where-Object { $_.text -eq 'Point Light' -and $_.cx -lt 300 -and $_.cy -gt 150 } | Sort-Object cy | Select-Object -Last 1
if (-not $plRow) { throw 'no Point Light row in outliner' }
Click-At ([double]$plRow.cx / 1.5) ([double]$plRow.cy / 1.5)
Wait-Frames 8; Start-Sleep -Milliseconds 500
$status = Get-UiRows | Where-Object { $_.text -like 'Entity:*' }
Write-Host ("selection: {0}" -f ((@($status) | ForEach-Object { $_.text }) -join ' | '))

# locate the two strip icons at cx~1330 (Object top, Components bottom)
$rows = Get-UiRows
$strip = $rows | Where-Object { [math]::Abs($_.cx - 1330) -le 12 -and $_.cy -gt 100 -and $_.cy -lt 260 -and $_.w -le 30 } | Sort-Object cy
$strip | ForEach-Object { Write-Host ("strip icon [{0:N1},{1:N1}]" -f $_.cx, $_.cy) }
if (@($strip).Count -lt 2) { throw 'could not locate the category strip icons' }
$comps = $strip[-1]
Click-At ([double]$comps.cx / 1.5) ([double]$comps.cy / 1.5)
Wait-Frames 8; Start-Sleep -Milliseconds 500

$panel = Get-UiRows | Where-Object { $_.cx -gt 1050 -and $_.cy -gt 95 -and $_.cy -lt 1060 } | Sort-Object cy, cx
$panel | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $OutDir 'newpointlight-components-tab.json') -Encoding UTF8
$panel | ForEach-Object { $t = $_.text; if ($t.Length -gt 28) { $t = $t.Substring(0, 28) + '..' }; Write-Host ('   [{0,7:N1},{1,7:N1}] {2}' -f $_.cx, $_.cy, $t) }
$hits = @($panel | Where-Object { $_.text -match 'PointLight|color|intensity|range|Components|SubEntity' })
Write-Host ("Components-tab light-related rows: {0}" -f $hits.Count)
$hits | ForEach-Object { Write-Host ("   HIT [{0:N1},{1:N1}] {2}" -f $_.cx, $_.cy, $_.text) }
Write-Host 'DONE lightprobe2'
