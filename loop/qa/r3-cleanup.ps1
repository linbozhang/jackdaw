# Clean up QA entities: delete the two extra Cube rows (the user's Cube is the FIRST) and the
# Point Light row, bottom-up so row shifts don't matter, then save.
param([int]$Port = 15703, [string]$OutDir = 'E:\Project\rust\jackdaw\loop\reports\r3-add-e2e')
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
        [pscustomobject]@{ text = $_.components.'bevy_ui::widget::text::Text'; cx = [double]$a[4]; cy = [double]$a[5] }
    }
}
function Get-SceneBsn {
    $r = (Invoke-BrpRaw 'jackdaw/scene_bsn' @{}).result
    if ($r -is [string]) { return $r }
    return [string]$r.bsn
}
function Delete-Row($row) {
    Write-Host ("deleting '{0}' at ({1:N1},{2:N1})" -f $row.text, $row.cx, $row.cy)
    Op @{ id = 'input.pointer'; params = @{ x = ([double]$row.cx / 1.5); y = ([double]$row.cy / 1.5); action = 'click' } }
    Wait-Frames 6
    Start-Sleep -Milliseconds 400
    Op @{ id = 'entity.delete' }
    Wait-Frames 8
    Start-Sleep -Milliseconds 500
}

for ($round = 1; $round -le 4; $round++) {
    # Clear any text-input keyboard focus (a spoken-for keyboard refuses entity ops).
    Op @{ id = 'input.key'; params = @{ key = 'Escape' } }
    Wait-Frames 5
    Start-Sleep -Milliseconds 250
    $rows = Get-UiRows | Where-Object { $_.cx -lt 300 -and $_.cy -gt 150 } | Sort-Object cy
    Write-Host ("round {0}: {1}" -f $round, (($rows | ForEach-Object { $_.text }) -join ' | '))
    $cubes = @($rows | Where-Object { $_.text -eq 'Cube' })
    if ($cubes.Count -gt 1) { Delete-Row $cubes[-1]; continue }
    $pl = @($rows | Where-Object { $_.text -eq 'Point Light' })
    if ($pl.Count -gt 0) { Delete-Row $pl[-1]; continue }
    break
}
$rows = Get-UiRows | Where-Object { $_.cx -lt 300 -and $_.cy -gt 150 } | Sort-Object cy
Write-Host ("final rows: {0}" -f (($rows | ForEach-Object { $_.text }) -join ' | '))
$bsn = Get-SceneBsn
$cubes = ([regex]::Matches($bsn, '(?m)^\s*#Cube\r?\s*$')).Count
$pl = ([regex]::Matches($bsn, '(?m)^\s*#.?\"?Point Light\"?\r?\s*$')).Count
Write-Host "exact cubes: $cubes (expect 1); point lights: $pl (expect 0)"
if ($cubes -ne 1 -or $pl -ne 0) { throw 'cleanup left QA entities behind' }
Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'scene.save' }) | Out-Null
Start-Sleep -Milliseconds 800
Write-Host 'PASS cleanup-and-save'
