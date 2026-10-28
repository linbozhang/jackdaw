# R3: Add menu evidence shots + Lights group -> Point Light creation, one shot.
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
function Click-At([double]$x, [double]$y) {
    Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = $x; y = $y; action = 'click' } }) | Out-Null
}
function Hover-At([double]$x, [double]$y) {
    Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = $x; y = $y; action = 'move' } }) | Out-Null
}
function Wait-Frames([int]$n) {
    try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 }
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

$before = ([regex]::Matches((Get-SceneBsn), '(?m)^\s*#Point_Light\r?\s*$|^\s*#"Point Light"\r?\s*$')).Count
Write-Host "point light headers before: $before"

# --- Phase A: evidence shot of the 3D Objects submenu (with the Cube row) ---
Click-At 133.0 17.3
Wait-Frames 6
Start-Sleep -Milliseconds 300
$g3d = Get-UiRows | Where-Object { $_.text -eq '3D Objects' }
if (-not $g3d) { throw 'Add dropdown did not open (phase A)' }
Hover-At ([double]$g3d.cx / 1.5) ([double]$g3d.cy / 1.5)
Wait-Frames 6
Start-Sleep -Milliseconds 700
$cubeRow = Get-UiRows | Where-Object { $_.text -eq 'Cube' -and $_.cx -gt ($g3d.cx + 150) }
if (-not $cubeRow) { throw '3D Objects submenu not visible for the evidence shot' }
Shot 'window' 'r3-02-addmenu-3dobjects-window.png'
Key 'Escape'
Wait-Frames 5
Start-Sleep -Milliseconds 300

# --- Phase B: Lights -> Point Light ---
Click-At 133.0 17.3
Wait-Frames 6
Start-Sleep -Milliseconds 300
$lights = Get-UiRows | Where-Object { $_.text -eq 'Lights' }
if (-not $lights) { throw 'Add dropdown did not open (phase B): no Lights group' }
Hover-At ([double]$lights.cx / 1.5) ([double]$lights.cy / 1.5)
Wait-Frames 6
Start-Sleep -Milliseconds 700
$pl = Get-UiRows | Where-Object { $_.text -eq 'Point Light' -and $_.cx -gt ($lights.cx + 150) -and [math]::Abs($_.cy - $lights.cy) -lt 150 }
if (-not $pl) { throw 'Lights submenu did not expand: no Point Light row' }
Write-Host ("Point Light row at ({0:N1},{1:N1})" -f $pl.cx, $pl.cy)
Shot 'window' 'r3-03-addmenu-lights-window.png'
Click-At ([double]$pl.cx / 1.5) ([double]$pl.cy / 1.5)
Wait-Frames 8
Start-Sleep -Milliseconds 400

$after = ([regex]::Matches((Get-SceneBsn), '(?m)^\s*#Point_Light\r?\s*$|^\s*#"Point Light"\r?\s*$')).Count
Write-Host "point light headers after: $after"
if ($after -le $before) {
    # name may differ; dump fresh headers for the report before failing
    [regex]::Matches((Get-SceneBsn), '(?m)^\s*#[A-Za-z][^\r\n]*') | ForEach-Object { $_.Value.Trim() } | Set-Content -Encoding UTF8 (Join-Path $OutDir 'bsn-names-after-light.txt')
    throw 'clicking the Point Light menu row created no entity'
}
Shot 'viewport' 'r3-04-after-pointlight-viewport.png'
Shot 'window' 'r3-04-after-pointlight-window.png'
Write-Host 'PASS menu-pointlight'
