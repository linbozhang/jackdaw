# clean-run probe on the fresh Point Light added via BRP, selected via outliner UI,
# Components tab opened via the strip icon. No viewport-mode icons touched.
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

# 1) add a fresh Point Light
$before = ([regex]::Matches((Get-SceneBsn), '(?m)^\s*#\s*\"?Point Light\"?\s*$')).Count
Op @{ id = 'entity.add.point_light' }
Wait-Frames 10; Start-Sleep -Milliseconds 600
$after = ([regex]::Matches((Get-SceneBsn), '(?m)^\s*#\s*\"?Point Light\"?\s*$')).Count
Write-Host ("Point Light entity headers: {0} -> {1}" -f $before, $after)
if ($after -le $before) { throw 'entity.add.point_light created nothing' }

# 2) select it via the outliner row
$rows = Get-UiRows
$plRow = $rows | Where-Object { $_.text -eq 'Point Light' -and $_.cx -lt 300 -and $_.cy -gt 150 } | Sort-Object cy | Select-Object -Last 1
if (-not $plRow) { throw 'no Point Light outliner row' }
Click-At ([double]$plRow.cx / 1.5) ([double]$plRow.cy / 1.5)
Wait-Frames 8; Start-Sleep -Milliseconds 600
$status = Get-UiRows | Where-Object { $_.text -like 'Entity:*' }
Write-Host ("selection: {0}" -f ((@($status) | ForEach-Object { $_.text }) -join ' | '))

# 3) dump the inspector header band to locate the two category strip icons
$band = Get-UiRows | Where-Object { $_.cx -gt 1250 -and $_.cx -lt 1470 -and $_.cy -gt 100 -and $_.cy -lt 210 } | Sort-Object cy, cx
Write-Host 'inspector header band rows:'
$band | ForEach-Object { $t = $_.text; if ($t.Length -gt 22) { $t = $t.Substring(0, 22) }; Write-Host ('   [{0,7:N1},{1,7:N1}] w={2:N0} "{3}"' -f $_.cx, $_.cy, $_.w, $t) }

# strip icons: small glyph rows; the Object icon sits ~y124, Components ~y172
$strip = @($band | Where-Object { $_.w -le 30 -and $_.text.Length -le 3 } | Sort-Object cy)
if ($strip.Count -lt 2) { throw ("strip icons not found (got {0})" -f $strip.Count) }
Write-Host ("strip icons found: {0}" -f (($strip | ForEach-Object { ('({0:N0},{1:N0})' -f $_.cx, $_.cy) }) -join ' '))

# 4) click the LOWER icon (Components) and dump the panel
$comps = $strip[-1]
Click-At ([double]$comps.cx / 1.5) ([double]$comps.cy / 1.5)
Wait-Frames 8; Start-Sleep -Milliseconds 600
$panel = Get-UiRows | Where-Object { $_.cx -gt 1250 -and $_.cy -gt 130 -and $_.cy -lt 1060 } | Sort-Object cy, cx
$panel | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $OutDir 'newpointlight-components-tab.json') -Encoding UTF8
Write-Host 'Components tab panel rows:'
$panel | ForEach-Object { $t = $_.text; if ($t.Length -gt 30) { $t = $t.Substring(0, 30) + '..' }; Write-Host ('   [{0,7:N1},{1,7:N1}] {2}' -f $_.cx, $_.cy, $t) }
$hits = @($panel | Where-Object { $_.text -match 'PointLight|Point Light|Components|color|intensity|range|SubEntity|SyncToSub' })
Write-Host ("light-related rows: {0}" -f $hits.Count)
$hits | ForEach-Object { Write-Host ("   HIT [{0:N1},{1:N1}] {2}" -f $_.cx, $_.cy, $_.text) }

# 5) screenshot for the archive
$r = Wait-BrpResult 'jackdaw/screenshot' @{ kind = 'window'; path = 'screenshots/f5-newpl-comps.png' } -TimeoutSec 20
Copy-Item 'C:\Users\linbo.zhang\Projects\my-game\screenshots\f5-newpl-comps.png' (Join-Path $OutDir 'f5-newpl-comps-window.png') -Force
Write-Host ("shot: {0}x{1}" -f $r.width, $r.height)
Write-Host 'DONE lightprobe3'
