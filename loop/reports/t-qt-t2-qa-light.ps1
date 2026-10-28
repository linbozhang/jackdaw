# T-QT-T2 dogfood: T02 plan section 7-2 spot check -- PointLight intensity
# numeric chain on the real editor, driven with ui_click + ui_input (enter
# commit), asserted through BRP (ECS + authored bsn).
param([int]$Port, [string]$OutDir, [string]$EditorLog)
$ErrorActionPreference = 'Stop'

function Brp-Call([string]$Method, $Params, [int]$TimeoutSec = 30) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $raw = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 15
        } catch { Start-Sleep -Milliseconds 250; continue }
        if ($null -ne $raw.error) { return @{ error = $raw.error } }
        if ($null -ne $raw.result) { return @{ result = $raw.result } }
        Start-Sleep -Milliseconds 120
    }
    throw "timeout waiting for $Method $Params"
}
function Wait-Idle([int]$T = 60) { Brp-Call 'jackdaw/wait' @{ until = 'idle' } $T | Out-Null }

$POINT = 'bevy_light::point_light::PointLight'
function Get-Lights {
    $q = Brp-Call 'world.query' @{ data = @{ components = @('bevy_ecs::name::Name', $POINT) } } 60
    $map = @{}
    foreach ($row in @($q.result)) { $map[$row.components.'bevy_ecs::name::Name'] = $row.components.$POINT }
    return $map
}

# select Point Light through the outliner row (node whose direct child text
# is 'Point Light')
function Get-Tree { (Brp-Call 'jackdaw/ui_tree' @{ depth = 24 }).result.nodes }
$script:rows = @()
function Walk($n) {
    if (@($n.children | Where-Object { $_.text -eq 'Point Light' }).Count -gt 0) { $script:rows += $n }
    foreach ($c in @($n.children)) { Walk $c }
}
foreach ($n in (Get-Tree)) { Walk $n }
$rows = @($script:rows | Where-Object { $_.rect[0] -lt 300 -and $_.rect[2] -gt 0 })
if ($rows.Count -lt 1) { throw 'no outliner row for Point Light' }
$r = Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$rows[0].entity }
if ($r.error) { throw "ui_click: $($r.error.message)" }
Write-Output ("[light] selected: " + ($r.result | ConvertTo-Json -Compress))
Wait-Idle

$before = (Get-Lights)['Point Light']
Write-Output ("[light] intensity before: " + $before.intensity)

# Locate the intensity input: label 'intensity' in the inspector column;
# the first (translation is X/Y/Z, intensity is a named row) such label's
# nearest sized ancestor is the ScrubNumberInput box.
$script:chain = @(); $script:hit = $false
function Collect($n, $acc) {
    if ($script:hit) { return }
    if ($n.text -and $n.text -match 'intensity' -and $n.rect[0] -gt 1150) { $script:chain = $acc + @($n); $script:hit = $true; return }
    $newAcc = $acc + @($n)
    foreach ($c in @($n.children)) { Collect $c $newAcc }
}
foreach ($n in (Get-Tree)) { Collect $n @() }
if (-not $script:hit) { throw 'no intensity label in inspector column' }
$chain = $script:chain
$target = $null
for ($i = $chain.Count - 1; $i -ge 0; $i--) {
    if ($chain[$i].rect[2] -gt 1) { $target = $chain[$i]; break }
}
if (-not $target) { throw 'no sized ancestor for intensity input' }
Write-Output ("[light] intensity input e=" + $target.entity + " rect=[" + ($target.rect -join ',') + "]")

$in = Brp-Call 'jackdaw/ui_input' @{ entity = [uint64]$target.entity; text = '5'; commit = 'enter' }
if ($in.error) { throw "ui_input: $($in.error.message)" }
Write-Output ("[light] typed: " + ($in.result | ConvertTo-Json -Compress))
Wait-Idle
Start-Sleep -Milliseconds 300

$after = (Get-Lights)['Point Light']
$ent = (Brp-Call 'jackdaw/entity' @{ name = 'Point Light' }).result
$bsnIntensity = $null
if ($ent.bsn -and $ent.bsn -match '(?m)^bevy_light::point_light::PointLight') {
    $lines = $ent.bsn -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'PointLight') {
            # numeric fields appear as `intensity: 5,` style rows below it
            for ($j = $i + 1; $j -lt [Math]::Min($i + 14, $lines.Count); $j++) {
                if ($lines[$j] -match 'intensity:\s*([-\d.e]+)') { $bsnIntensity = $Matches[1]; break }
            }
            break
        }
    }
}
Write-Output ("[light] intensity after (ECS): " + $after.intensity + "; authored bsn intensity: " + $bsnIntensity)
$ok = ([double]$after.intensity - 5.0) -lt 1e-6 -and ([double]$after.intensity - 5.0) -gt -1e-6
if ($null -ne $bsnIntensity) { $ok = $ok -and ([double]$bsnIntensity -eq 5.0) } else { $ok = $false }
Write-Output ("LIGHT VERDICT: " + $(if ($ok) { 'PASS' } else { 'FAIL' }))
