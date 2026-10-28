# T03-T1 QA live spot checks (QA-driven, BRP only, no bevy/get -- jackdaw/entity instead):
#   Chain 1 (R2): select Zone -> X+1+Enter -> undo lands exactly one entry -> x back to 0,
#            dirty follows the fingerprint semantics (clean at saved depth+content, dirty on redo).
#   Chain 2 (N4): save -> undo -> tab dirty MUST be on.
param(
    [string]$Exe = "E:\Project\rust\jackdaw\target\debug\jackdaw.exe",
    [int]$Port = 15811
)
$ErrorActionPreference = 'Stop'

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
    throw "timeout waiting for $Method $Params"
}
function Wait-Idle([int]$T = 90) { Brp-Call 'jackdaw/wait' @{ until = 'idle' } $T | Out-Null; Start-Sleep -Milliseconds 400 }
function Op([string]$Id, $Params) { Brp-Call 'jackdaw/call_operator' @{ id = $Id; params = $Params } }
function Key([string]$K) { Op 'input.key' @{ key = $K; action = 'tap' } | Out-Null; Wait-Idle }
function Dirty { [bool](Brp-Call 'jackdaw/status' @{}).result.dirty }
function ZoneX {
    $r = Brp-Call 'jackdaw/entity' @{ name = 'Zone' }
    if ($r.error) { return $null }
    if ($r.result.bsn -match 'translation: glam::Vec3A \{ x: ([\d.eE+-]+)') { return [double]$Matches[1] }
    return $null
}
function Check([bool]$Ok, [string]$What) {
    if ($Ok) { Write-Output ("PASS  " + $What) }
    else { Write-Output ("FAIL  " + $What); $script:Failures++ }
}
$Failures = 0

# --- boot on a throwaway project holding a saved zone scene ---
$Project = Join-Path $env:TEMP "t03t1-qa-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $Project "assets"), (Join-Path $Project ".jackdaw") | Out-Null
Set-Content (Join-Path $Project ".jackdaw/project.json") '{"name":"t03t1-qa","remote":{"enabled":true}}'
Set-Content (Join-Path $Project "Cargo.toml") "[package]`nname = `"qa`"`nversion = `"0.1.0`"`nedition = `"2021`"`n`n[dependencies]`n"
Set-Content (Join-Path $Project "assets/zone.bsn") "#Zone`nbevy_transform::components::transform::Transform`n"

$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_SKIP_SETUP_CHECK = "1"
$editor = Start-Process -FilePath $Exe -PassThru
try {
    $ready = $false
    for ($i = 0; $i -lt 240; $i++) {
        try { $s = Brp-Call 'jackdaw/status' @{} 5; if ($s.result) { $ready = $true; break } } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $ready) { throw "editor never answered on $Port" }
    Write-Output ("READY pid=" + $editor.Id)
    Wait-Idle
    $setup = Brp-Call 'jackdaw/ui_tree' @{ text = 'Open without setup'; depth = 0 }
    if (@($setup.result.nodes).Count -gt 0) {
        Brp-Call 'jackdaw/ui_click' @{ text = 'Open without setup' } | Out-Null
        Wait-Idle; Wait-Idle
    }
    Key 'Escape'

    # --- open the saved zone scene (has a path, so scene.save never opens a dialog) ---
    Op 'scene.open' @{ path = 'assets/zone.bsn' } | Out-Null
    $zoneThere = $false
    for ($i = 0; $i -lt 60; $i++) { if ($null -ne (ZoneX)) { $zoneThere = $true; break }; Start-Sleep -Milliseconds 500 }
    Check $zoneThere 'stage: zone.bsn loaded, Zone entity reachable'
    Wait-Idle; Wait-Idle

    # --- select Zone through the real outliner click chain ---
    # Walk the full tree for a row node whose CHILD text is exactly 'Zone'
    # (ui_tree's text filter matches whole subtrees, which points at panels).
    $script:zoneRows = @()
    function Walk($n) {
        if (@($n.children | Where-Object { $_.text -eq 'Zone' }).Count -gt 0) { $script:zoneRows += $n }
        foreach ($c in @($n.children)) { Walk $c }
    }
    $full = (Brp-Call 'jackdaw/ui_tree' @{ depth = 24 }).result.nodes
    foreach ($n in $full) { Walk $n }
    $zoneRows = @($zoneRows | Where-Object { $_.rect -and $_.rect[0] -lt 300 -and $_.rect[1] -gt 100 } | Sort-Object { $_.rect[1] })
    foreach ($c in $zoneRows) { Write-Output ("[stage] zone row e=" + $c.entity + " rect=[" + ($c.rect -join ',') + "]") }
    if ($zoneRows.Count -lt 1) { throw 'no outliner row whose child text is Zone' }
    $r = Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$zoneRows[0].entity }
    Write-Output ('[stage] outliner click: ' + ($r | ConvertTo-Json -Depth 6 -Compress))
    Wait-Idle
    $selJson = ((Brp-Call 'jackdaw/status' @{}).result.selection | ConvertTo-Json -Compress -Depth 6)
    Write-Output ("[stage] selection: " + $selJson)
    Check ([bool]($selJson -match 'Zone')) 'stage: Zone selected through the outliner'

    Check ((ZoneX) -eq 0.0) ("stage: Zone starts at x=0 (got $(ZoneX))")
    Check (-not (Dirty)) 'stage: freshly loaded scene reads clean'

    # ================= chain 1 (R2): X + 1 + Enter, one undo entry ================
    Key 'KeyX'; Key 'Digit1'; Key 'Enter'
    $x1 = ZoneX
    Check ($x1 -eq 1.0) ("chain1: X+1+Enter moved Zone to x=1 (got $x1)")
    Check (Dirty) 'chain1: the move dirties the tab'

    Op 'history.undo' @{} | Out-Null; Wait-Idle
    $x0 = ZoneX
    Check ($x0 -eq 0.0) ("chain1: ONE undo returns x to 0 (got $x0): the move was exactly one entry")
    Check (-not (Dirty)) 'chain1: undo back to saved depth+content reads clean (fingerprint semantics)'

    # a second undo has nothing left to undo: x must stay 0 (proves the move was not two entries)
    Op 'history.undo' @{} | Out-Null; Wait-Idle
    Check ((ZoneX) -eq 0.0) 'chain1: second undo is a no-op (stack held only the move)'

    Op 'history.redo' @{} | Out-Null; Wait-Idle
    $xr = ZoneX
    Check ($xr -eq 1.0) ("chain1: redo returns x to 1 (got $xr)")
    Check (Dirty) 'chain1: redo re-dirties the tab (content differs from the file)'

    # ================= chain 2 (N4): save -> undo -> dirty MUST stay on ============
    Op 'scene.save' @{} | Out-Null; Wait-Idle
    Check (-not (Dirty)) 'chain2: saved at x=1, tab reads clean'
    $fileX = (Get-Content (Join-Path $Project 'assets/zone.bsn') -Raw)
    Check ($fileX -match 'x: 1(\.0)?') 'chain2: the saved file holds the move (R2 save-loss symptom gone)'

    Op 'history.undo' @{} | Out-Null; Wait-Idle
    $xBack = ZoneX
    Check ($xBack -eq 0.0) ("chain2: undo returned x to 0 (got $xBack)")
    Check (Dirty) 'chain2 (N4 CORE): save then undo leaves the tab DIRTY -- closing must prompt'

    Write-Output ("RESULT failures=" + $Failures)
    if ($Failures -gt 0) { exit 1 }
}
finally {
    try { Stop-Process -Id $editor.Id -Force -ErrorAction SilentlyContinue } catch {}
    Remove-Item -Recurse -Force $Project -ErrorAction SilentlyContinue
}
