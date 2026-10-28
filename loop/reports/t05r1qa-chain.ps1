# QA independent chain re-run: the six closeout points, strengthened with
# four-part audit printing, full audit2 assertions (healthy keeper must NOT
# be a finding), and the raw walk-diagnosis lines.
$ErrorActionPreference = 'Stop'
$Port = 15841
$Proj = "$env:TEMP\t05r1-proj"
function Brp-Call([string]$Method, $Params, [int]$TimeoutSec = 30) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try { $raw = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 15 }
        catch { Start-Sleep -Milliseconds 250; continue }
        if ($null -ne $raw.error) { return @{ error = $raw.error } }
        if ($null -ne $raw.result) { return @{ result = $raw.result } }
        Start-Sleep -Milliseconds 120
    }
    throw "timeout $Method"
}
function Wait-Idle([int]$T = 90) { Brp-Call 'jackdaw/wait' @{ until = 'idle' } $T | Out-Null }
function Op([string]$Id, $Params) { Brp-Call 'jackdaw/call_operator' @{ id = $Id; params = $Params } }
function Get-Tree { (Brp-Call 'jackdaw/ui_tree' @{ depth = 30 } 30).result.nodes }
function Find-Node($nodes, [string]$text) {
    foreach ($n in $nodes) {
        if ($null -ne $n.text -and $n.text -like "*$text*") { return $n }
        if ($n.children) { $hit = Find-Node $n.children $text; if ($hit) { return $hit } }
    }
    return $null
}
function Fail([string]$What) { Write-Output "FAIL: $What"; exit 1 }
function Pass([string]$What) { Write-Output "PASS: $What" }

Wait-Idle
# --- point 1: the walk diagnosis lines, raw ---
$log = Get-Content "$env:TEMP\t05r1-editor.log" -Raw
$walkLines = ($log -split "`n") | Where-Object { $_ -match 'asset index:|Indexed' }
Write-Output '--- walk diagnosis lines:'
$walkLines | ForEach-Object { Write-Output ('  ' + $_.Trim()) }
if ($log -like '*Indexed 1 asset files*') { Pass 'point1: "Indexed 1 asset files" present' }
else { Fail 'point1: no Indexed line' }

# --- point 2: audit four parts, kind=Missing ---
Op 'scene.open' @{ path = 'assets/zones/scene.bsn' } | Out-Null
Wait-Idle 90
$audit = (Brp-Call 'jackdaw/audit' @{} 60).result
$audit | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 'E:\Project\rust\jackdaw\loop\reports\t05r1-live\qa-audit1.json'
$victim = @($audit.findings) | Where-Object { $_.reference -like '*victim.bsn' }
if (@($victim).Count -ne 1) { Fail "point2: victim findings = @($victim).Count : $($audit | ConvertTo-Json -Depth 8 -Compress)" }
$v = $victim[0]
Write-Output ("point2 finding: document=$($v.document) entity=$($v.entity) component=$($v.component) field=$($v.field) ref=$($v.reference) kind=$($v.kind)")
foreach ($part in @('document', 'entity', 'component', 'field', 'reference', 'kind')) { if (-not $v.$part) { Fail "point2: audit misses $part" } }
if ($v.kind -ne 'Missing') { Fail "point2: kind is $($v.kind), not Missing" }
if ($v.reference -ne 'props/victim.bsn') { Fail "point2: reference spelled $($v.reference), not the relative 'props/victim.bsn'" }
if ($v.document -ne 'zones/scene.bsn') { Fail "point2: document is $($v.document)" }
Pass 'point2: audit names the gone prefab Missing, four parts, relative spelling'

# --- point 3: list row + Rebind ---
Op 'asset.missing_list' @{} | Out-Null
Wait-Idle
$tree = Get-Tree
$row = Find-Node $tree 'victim.bsn'
if (-not $row) { Fail 'point3: no row for the gone prefab' }
$rebind = Find-Node $tree 'Rebind'
if (-not $rebind) { Fail 'point3: no Rebind button' }
Pass 'point3: the Missing list shows the row and its Rebind'

# --- point 4: rebind via the operator, authored bsn follows ---
Op 'asset.rebind' @{ document = 'zones/scene.bsn'; component = 'IsA'; field = 'source'; reference = 'props/victim.bsn'; to = 'props/keeper.bsn' } | Out-Null
Wait-Idle
$bsn = (Brp-Call 'jackdaw/scene_bsn' @{} 30).result | ConvertTo-Json -Depth 10
$bsn | Set-Content -Encoding UTF8 'E:\Project\rust\jackdaw\loop\reports\t05r1-live\qa-scene-bsn.json'
if ($bsn -notlike '*props/keeper.bsn*') { Fail "point4: authored bsn lacks keeper: $($bsn.Substring(0,300))" }
if ($bsn -like '*victim*') { Fail 'point4: authored bsn still names victim' }
Pass 'point4: asset.rebind wrote the tab document (victim -> keeper)'

# --- point 5: save to disk ---
Op 'scene.save' @{} | Out-Null
Wait-Idle
$saved = Get-Content "$Proj\assets\zones\scene.bsn" -Raw
if ($saved -notlike '*props/keeper.bsn*') { Fail "point5: disk lacks keeper: $saved" }
if ($saved -like '*victim*') { Fail 'point5: disk still names victim' }
Pass 'point5: scene.save wrote the new reference to disk'

# --- point 6: reopen, full audit (victim gone AND healthy keeper not a finding) ---
Op 'scene.new' @{} | Out-Null; Wait-Idle
Op 'scene.switch' @{ tab = 0 } | Out-Null; Wait-Idle
Op 'scene.close' @{} | Out-Null; Wait-Idle
Op 'scene.open' @{ path = 'assets/zones/scene.bsn' } | Out-Null
Wait-Idle 120
$audit2 = (Brp-Call 'jackdaw/audit' @{} 60).result
$audit2 | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 'E:\Project\rust\jackdaw\loop\reports\t05r1-live\qa-audit2.json'
Write-Output ("point6 audit2: count=$($audit2.count) summary=$($audit2.summary)")
if (@($audit2.findings).Count -ne 0) {
    Write-Output 'point6 findings after reopen:'
    $audit2.findings | ForEach-Object { Write-Output ("  " + ($_ | ConvertTo-Json -Compress)) }
    Fail 'point6: the reopened scene does not audit fully clean'
}
Pass 'point6: reopened scene audits fully clean (no victim, healthy keeper not reported)'
Write-Output 'QA CHAIN ALL PASS'
