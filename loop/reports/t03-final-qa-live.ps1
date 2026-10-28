# T03 FINAL QA live spot checks (independent QA run):
#   (1) jackdaw/history one full round: an operation through the USER path
#       (BRP call_operator defaults history:true) -> stack/top/dirty move;
#       one undo -> stacks swap, dirty falls back to clean.
#   (2) scrub drag chain: one full drag gesture on the Inspector translation
#       X row -> exactly ONE undo entry; one undo returns x and reads clean.
param(
    [string]$Exe = "E:\Project\rust\jackdaw\target\debug\jackdaw.exe",
    [int]$Port = 15813,
    [string]$OutDir = "E:\Project\rust\jackdaw\loop\reports\t03final-qa"
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

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
function HistProbe {
    $r = Brp-Call 'jackdaw/history' @{ entries = 5 }
    if ($r.error) { Write-Host ("[history] ERROR: " + ($r.error | ConvertTo-Json -Depth 6 -Compress)) }
    $r.result
}
function Dirty { [bool](Brp-Call 'jackdaw/status' @{}).result.dirty }
function EntityX([string]$Name) {
    $r = Brp-Call 'jackdaw/entity' @{ name = $Name }
    if ($r.error) { return $null }
    if ($r.result.bsn -match 'translation: glam::Vec3A? \{ x: ([\d.eE+-]+)') { return [double]$Matches[1] }
    return $null
}
function Check([bool]$Ok, [string]$What) {
    if ($Ok) { Write-Output ("PASS  " + $What) }
    else { Write-Output ("FAIL  " + $What); $script:Failures++ }
}

$script:AllNodes = @()
function Walk($n) { $script:AllNodes += ,$n; foreach ($c in @($n.children)) { Walk $c } }
function Refresh-Tree {
    $script:AllNodes = @()
    $answer = Brp-Call 'jackdaw/ui_tree' @{ depth = 30 }
    if ($answer.error) { Write-Host ("[tree] ui_tree error"); return }
    foreach ($n in @($answer.result.nodes)) { Walk $n }
}
function Row-Of([string]$Label, [double]$MaxX = 600) {
    @($script:AllNodes | Where-Object {
        @($_.children | Where-Object { $_.text -eq $Label }).Count -gt 0 -and $_.rect -and $_.rect[0] -lt $MaxX -and $_.rect[1] -gt 100
    } | Sort-Object { $_.rect[1] })
}
function Row-Of-Or-Wait([string]$Label, [int]$Seconds = 15) {
    for ($i = 0; $i -lt ($Seconds * 2); $i++) {
        Refresh-Tree
        $rows = Row-Of $Label
        if (@($rows).Count -gt 0) { return $rows[0] }
        Start-Sleep -Milliseconds 500
    }
    throw "no outliner row whose child text is $Label"
}

$Failures = 0

$Project = Join-Path $env:TEMP "t03final-qa-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $Project "assets/prefabs"), (Join-Path $Project ".jackdaw") | Out-Null
Set-Content (Join-Path $Project ".jackdaw/project.json") '{"name":"t03final-qa","remote":{"enabled":true}}'
Set-Content (Join-Path $Project "Cargo.toml") "[package]`nname = `"qa`"`nversion = `"0.1.0`"`nedition = `"2021`"`n`n[dependencies]`n"
Set-Content (Join-Path $Project "assets/zone.bsn") "#Zone`nbevy_transform::components::transform::Transform`n"

$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_WINDOW_SIZE = "1920x1080"
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
    Brp-Call 'jackdaw/input' @{ } | Out-Null 2>$null

    Op 'scene.open' @{ path = 'assets/zone.bsn' } | Out-Null
    $zoneThere = $false
    for ($i = 0; $i -gt -60; $i--) { if ($null -ne (EntityX 'Zone')) { $zoneThere = $true; break }; Start-Sleep -Milliseconds 500 }
    Check $zoneThere 'stage: zone.bsn loaded, Zone reachable'
    Wait-Idle; Wait-Idle

    $scale = 1.0
    try {
        $w = Brp-Call 'world.query' @{ data = @{ components = @('bevy_window::window::Window') }; filter = @{ with = @('bevy_window::window::PrimaryWindow') } } 10
        if ($w.result -and @($w.result).Count -gt 0) {
            $win = @($w.result)[0].components.'bevy_window::window::Window'
            if ($win.scale_factor) { $scale = [double]$win.scale_factor }
        }
    } catch { Write-Output '[stage] Window query failed; assuming scale 1.0' }

    # ============ item 1: jackdaw/history round on a real operation ============
    $zoneRow = Row-Of-Or-Wait 'Zone'
    Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$zoneRow.entity } | Out-Null
    Wait-Idle

    $h0 = HistProbe
    Write-Output ("[h1] clean: " + ($h0 | ConvertTo-Json -Compress))
    Check ($h0.undo_len -eq 0 -and $h0.redo_len -eq 0) 'h1: history reads empty stacks on a clean scene'
    Check (-not (Dirty)) 'h1: freshly loaded scene reads clean'
    Check ($h0.saved_len -eq 0 -and $h0.has_save_baseline) 'h1: save baseline present at depth 0'

    # one operation through the USER path: BRP call_operator, history defaults true
    Op 'entity.add.cube' @{} | Out-Null
    Wait-Idle; Wait-Idle
    $h1 = HistProbe
    Write-Output ("[h1] after add.cube: " + ($h1 | ConvertTo-Json -Compress))
    Check ($h1.undo_len -eq 1) "h1: one operation leaves exactly ONE undo entry (undo_len=$($h1.undo_len))"
    Check ($h1.undo.Count -eq 1 -and $h1.top -eq $h1.undo[0].label) 'h1: top agrees with the newest undo label'
    Check ($h1.top -match 'Cube') "h1: top names the add (top=$($h1.top))"
    Check (Dirty) 'h1: the operation lights the dirty flag'

    # take the cube back out (keep the scrub chain below on a clean baseline)
    Op 'history.undo' @{} | Out-Null; Wait-Idle
    $h2 = HistProbe
    Write-Output ("[h1] after undo: " + ($h2 | ConvertTo-Json -Compress))
    Check ($h2.undo_len -eq 0 -and $h2.redo_len -eq 1) "h1: undo swaps the stacks (undo=$($h2.undo_len) redo=$($h2.redo_len))"
    Check ($h2.redo[0].label -eq $h1.top) 'h1: the redo stack carries the same label'
    Check (-not (Dirty)) 'h1: undo back to the saved document reads clean'
    Op 'history.redo' @{} | Out-Null; Wait-Idle   # redo the cube, then remove it for good via delete op (one entry)
    Op 'entity.delete' @{} | Out-Null; Wait-Idle; Wait-Idle
    $h3 = HistProbe
    Check ($h3.undo_len -eq 1) "h1: redo+delete leaves one entry (undo_len=$($h3.undo_len))"
    Op 'history.undo' @{} | Out-Null; Wait-Idle
    Check (-not (Dirty)) 'h1: back to clean before the scrub chain'
    while ((HistProbe).undo_len -gt 0) { Op 'history.undo' @{} | Out-Null; Wait-Idle }

    # ============ item 2: scrub drag -> exactly one entry, one undo returns ============
    $zoneRow = Row-Of-Or-Wait 'Zone'
    Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$zoneRow.entity } | Out-Null
    Wait-Idle

    $expanded = $false
    for ($i = 0; $i -lt 10; $i++) {
        Refresh-Tree
        $script:AllNodes = @()
        $t = Brp-Call 'jackdaw/ui_tree' @{ text = 'Transform'; depth = 8 }
        foreach ($n in @($t.result.nodes)) { Walk $n }
        $exact = @($script:AllNodes | Where-Object { $_.text -eq 'Transform' -and $_.rect -and $_.rect[0] -gt 1100 -and $_.rect[1] -gt 100 })
        if ($exact.Count -ge 1) {
            Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$exact[0].entity } | Out-Null
            Wait-Idle
            $expanded = $true
            break
        }
        Start-Sleep -Milliseconds 400
    }
    Write-Output ("[h2] Transform card clicked: " + $expanded)

    $trio = @()
    for ($i = 0; $i -lt 20; $i++) {
        Refresh-Tree
        $fields = @($script:AllNodes | Where-Object {
            $_.kind -eq 'text_input' -and $_.rect -and $_.rect[0] -gt 1100 -and $_.rect[1] -gt 100 -and $_.rect[3] -gt 14 -and $_.rect[3] -lt 40
        } | Sort-Object { $_.rect[1] }, { $_.rect[0] })
        $groups = $fields | Group-Object { [math]::Round($_.rect[1] / 6) }
        $trioGroup = @($groups | Where-Object { $_.Count -ge 3 } | Sort-Object { $_.Name } | Select-Object -First 1)
        if ($trioGroup.Count -gt 0) { $trio = @($trioGroup[0].Group | Sort-Object { $_.rect[0] }); break }
        Start-Sleep -Milliseconds 500
    }
    if ($trio.Count -lt 3) { throw "expected the three translation rows, got $($trio.Count)" }
    $xField = $trio[0]

    $ha = HistProbe
    $xBefore = EntityX 'Zone'
    Brp-Call 'jackdaw/ui_drag' @{ entity = [uint64]$xField.entity; from = @(0.15, 0.5); to = @(0.85, 0.5); steps = 10 } | Out-Null
    Wait-Idle; Wait-Idle
    $xAfter = EntityX 'Zone'
    $hb = HistProbe
    Write-Output ("[h2] x: $xBefore -> $xAfter; undo_len: $($ha.undo_len) -> $($hb.undo_len) (top: $($hb.top))")
    Check ($xAfter -ne $xBefore) "h2: the scrub moved Zone.x ($xBefore -> $xAfter)"
    Check ($hb.undo_len -eq ($ha.undo_len + 1)) "h2: one drag gesture is exactly ONE entry ($($ha.undo_len) -> $($hb.undo_len))"
    Check (Dirty) 'h2: the gesture dirties the tab'

    Op 'history.undo' @{} | Out-Null; Wait-Idle
    $xBack = EntityX 'Zone'
    $hc = HistProbe
    Check ($xBack -eq $xBefore) "h2: ONE undo returns x to $xBefore (got $xBack)"
    Check ($hc.undo_len -eq $ha.undo_len) "h2: stack back at $($hc.undo_len) after the single undo"
    Check (-not (Dirty)) 'h2: undo back to the saved content reads clean'

    Brp-Call 'jackdaw/screenshot' @{ kind = 'window'; path = 'shots/final-qa-window.png' } | Out-Null
    try { Copy-Item (Join-Path $Project 'shots\*.png') $OutDir -Force -ErrorAction SilentlyContinue } catch {}

    Write-Output ("RESULT failures=" + $Failures)
    if ($Failures -gt 0) { exit 1 }
}
finally {
    try { Stop-Process -Id $editor.Id -Force -ErrorAction SilentlyContinue } catch {}
    Remove-Item -Recurse -Force $Project -ErrorAction SilentlyContinue
}
