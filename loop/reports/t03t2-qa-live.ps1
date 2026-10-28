# T03-T2 QA live: record-count chains through the real UI, asserted with the
# new jackdaw/history BRP probe.
#   Chain 1 (scrub): drag the Inspector translation X row -> exactly ONE undo
#            entry -> one undo returns x -> dirty falls back.
#   Chain 2 (Y2): right-click the outliner Zone row -> Duplicate menu item ->
#            exactly ONE entry -> one undo removes the copy.
#   Chain 3 (Y4): place a rock instance, drag its inherited Pebble row onto
#            Zone -> exactly ONE entry -> one undo returns the document
#            byte-for-byte -> save -> undo leaves the tab dirty (N4 echo).
param(
    [string]$Exe = "E:\Project\rust\jackdaw\target\debug\jackdaw.exe",
    [int]$Port = 15812,
    [string]$OutDir = "E:\Project\rust\jackdaw\loop\reports\t03t2-qa"
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
function Key([string]$K) { Op 'input.key' @{ key = $K; action = 'tap' } | Out-Null; Wait-Idle }
function HistProbe {
    $r = Brp-Call 'jackdaw/history' @{ entries = 5 }
    if ($r.error) { Write-Host ("[history] ERROR: " + ($r.error | ConvertTo-Json -Depth 6 -Compress)) }
    $r.result
}
function Dirty { [bool](Brp-Call 'jackdaw/status' @{}).result.dirty }
function SceneBsn { [string]((Brp-Call 'jackdaw/scene_bsn' @{}).result.bsn) }
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

# --- full ui_tree walk; collects every node so callers can filter by hand ---
$script:AllNodes = @()
$script:TreeRefreshes = 0
function Walk($n) { $script:AllNodes += ,$n; foreach ($c in @($n.children)) { Walk $c } }
function Refresh-Tree {
    $script:AllNodes = @()
    $answer = Brp-Call 'jackdaw/ui_tree' @{ depth = 30 }
    if ($answer.error) { Write-Host ("[tree] ui_tree error: " + ($answer.error | ConvertTo-Json -Compress)); return }
    $full = $answer.result.nodes
    foreach ($n in $full) { Walk $n }
    $script:TreeRefreshes++
    if ($script:TreeRefreshes -le 3) { Write-Host ("[tree] walk collected " + $script:AllNodes.Count + " nodes") }
}
# The row whose direct child text is exactly `label` (per manual 7.5).
function Row-Of([string]$Label, [double]$MaxX = 600) {
    $rows = @($script:AllNodes | Where-Object {
        @($_.children | Where-Object { $_.text -eq $Label }).Count -gt 0 -and $_.rect -and $_.rect[0] -lt $MaxX -and $_.rect[1] -gt 100
    } | Sort-Object { $_.rect[1] })
    return $rows
}
# Rows can lag a scene load or an expansion by a few frames; poll for them.
function Row-Of-Or-Wait([string]$Label, [int]$Seconds = 15) {
    for ($i = 0; $i -lt ($Seconds * 2); $i++) {
        Refresh-Tree
        $rows = Row-Of $Label
        if ($i -eq 0) {
            $pre = @($script:AllNodes | Where-Object { @($_.children | Where-Object { $_.text -eq $Label }).Count -gt 0 })
            Write-Host ("[row] AllNodes=" + $script:AllNodes.Count + " pre-rect=" + $pre.Count + " post-rect=" + @($rows).Count)
            foreach ($n in @($pre | Select-Object -First 3)) { Write-Host ("[row]   pre e=" + $n.entity + " rect=[" + ($n.rect -join ',') + "]") }
        }
        if (@($rows).Count -gt 0) { return $rows[0] }
        Start-Sleep -Milliseconds 500
    }
    throw "no outliner row whose child text is $Label"
}

$Failures = 0

# --- boot on a throwaway project holding a saved zone scene + a rock prefab ---
$Project = Join-Path $env:TEMP "t03t2-qa-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $Project "assets/prefabs"), (Join-Path $Project ".jackdaw") | Out-Null
Set-Content (Join-Path $Project ".jackdaw/project.json") '{"name":"t03t2-qa","remote":{"enabled":true}}'
Set-Content (Join-Path $Project "Cargo.toml") "[package]`nname = `"qa`"`nversion = `"0.1.0`"`nedition = `"2021`"`n`n[dependencies]`n"
Set-Content (Join-Path $Project "assets/zone.bsn") "#Zone`nbevy_transform::components::transform::Transform`n"
Set-Content (Join-Path $Project "assets/prefabs/rock.bsn") @'
#Rock
jackdaw::prefab::components::Prefab
jackdaw::prefab::components::PrefabEntityId(0)
bevy_transform::components::transform::Transform
bevy_ecs::hierarchy::Children [
    #Pebble
    jackdaw::prefab::components::PrefabEntityId(7)
    bevy_transform::components::transform::Transform {
        translation: glam::Vec3 { x: 3.0, y: 0.0, z: 0.0 },
        rotation: glam::Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 },
        scale: glam::Vec3 { x: 1.0, y: 1.0, z: 1.0 },
    }
]
'@

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
    Key 'Escape'

    Op 'scene.open' @{ path = 'assets/zone.bsn' } | Out-Null
    $zoneThere = $false
    for ($i = 0; $i - 60; $i++) { if ($null -ne (EntityX 'Zone')) { $zoneThere = $true; break }; Start-Sleep -Milliseconds 500 }
    Check $zoneThere 'stage: zone.bsn loaded, Zone reachable'
    Wait-Idle; Wait-Idle

    # --- the scale factor, for input.pointer's logical coordinates ---
    $scale = 1.0
    try {
        $w = Brp-Call 'world.query' @{ data = @{ components = @('bevy_window::window::Window') }; filter = @{ with = @('bevy_window::window::PrimaryWindow') } } 10
        if ($w.result -and @($w.result).Count -gt 0) {
            $win = @($w.result)[0].components.'bevy_window::window::Window'
            if ($win.scale_factor) { $scale = [double]$win.scale_factor }
        }
    } catch { Write-Output '[stage] Window query failed; assuming scale 1.0' }
    Write-Output ("[stage] window scale factor = " + $scale)

    # --- select Zone through the outliner ---
    $zoneRow = Row-Of-Or-Wait 'Zone'
    Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$zoneRow.entity } | Out-Null
    Wait-Idle
    $sel = ((Brp-Call 'jackdaw/status' @{}).result.selection | ConvertTo-Json -Compress -Depth 6)
    Check ($sel -match 'Zone') 'stage: Zone selected through the outliner'

    # --- history probe answers on a clean scene ---
    $h0 = HistProbe
    Write-Output ("[stage] history probe: " + ($h0 | ConvertTo-Json -Compress))
    Check ($h0.undo_len -eq 0 -and $h0.redo_len -eq 0) 'stage: jackdaw/history reads empty stacks on a clean scene'
    Check (-not (Dirty)) 'stage: freshly loaded scene reads clean'

    # ================= chain 1: scrub the translation X row ==================
    # Expand the Transform card (manual 7.5: cards start collapsed, and a text
    # filter returns the subtree ROOT, so walk for the exact-text node).
    $expanded = $false
    for ($i = 0; $i -lt 10; $i++) {
        Refresh-Tree
        $subtreeRoots = @()
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
    Write-Output ("[chain1] Transform card clicked: " + $expanded)

    # The three same-y text inputs in the inspector are translation X/Y/Z
    # (manual 7.5: group by y; the name field above sits alone at its own y).
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
    Write-Output ("[chain1] translation trio: " + (@($trio | ForEach-Object { "e=$($_.entity) y=$([math]::Round($_.rect[1])) x=$([math]::Round($_.rect[0]))" }) -join ' | '))
    if ($trio.Count -lt 3) { throw "expected the three translation rows, got $($trio.Count)" }
    $xField = $trio[0]

    $h1 = HistProbe
    $xBefore = EntityX 'Zone'
    Brp-Call 'jackdaw/ui_drag' @{ entity = [uint64]$xField.entity; from = @(0.15, 0.5); to = @(0.85, 0.5); steps = 10 } | Out-Null
    Wait-Idle; Wait-Idle
    $xAfter = EntityX 'Zone'
    $h2 = HistProbe
    Write-Output ("[chain1] x: $xBefore -> $xAfter; undo_len: $($h1.undo_len) -> $($h2.undo_len) (top: $($h2.top))")
    Check ($xAfter -ne $xBefore) "chain1: the scrub moved Zone.x ($xBefore -> $xAfter)"
    Check ($h2.undo_len -eq ($h1.undo_len + 1)) "chain1: the scrub gesture is ONE entry (undo_len $($h1.undo_len) -> $($h2.undo_len))"
    Check (Dirty) 'chain1: the scrub dirties the tab'

    Op 'history.undo' @{} | Out-Null; Wait-Idle
    $xBack = EntityX 'Zone'
    Check ($xBack -eq $xBefore) "chain1: ONE undo returns x to $xBefore (got $xBack)"
    $h3 = HistProbe
    Check ($h3.undo_len -eq $h1.undo_len) "chain1: stack back at $($h3.undo_len); redo_len $($h3.redo_len)"
    Check (-not (Dirty)) 'chain1: undo back to the saved content reads clean'

    Brp-Call 'jackdaw/screenshot' @{ kind = 'window'; path = 'shots/chain1-window.png' } | Out-Null

    # ============ chain 2: right-click Zone -> context menu Duplicate =========
    Refresh-Tree
    $zoneRows = Row-Of 'Zone'
    if ($zoneRows.Count -lt 1) { $zoneRow = Row-Of-Or-Wait 'Zone' } else { $zoneRow = $zoneRows[0] }
    $zx = ($zoneRow.rect[0] + $zoneRow.rect[2] / 2) / $scale
    $zy = ($zoneRow.rect[1] + $zoneRow.rect[3] / 2) / $scale
    $h4 = HistProbe
    # The menu opens from the operator the (RMB, Press) binding fires; drive
    # the real right-click first, then fall back to the operator with the
    # cursor parked on the row.
    Op 'input.pointer' @{ x = $zx; y = $zy; action = 'press'; button = 'secondary' } | Out-Null
    Wait-Idle; Wait-Idle
    Op 'input.pointer' @{ x = $zx; y = $zy; action = 'release'; button = 'secondary' } | Out-Null
    Wait-Idle
    $dup = Brp-Call 'jackdaw/ui_tree' @{ text = 'Duplicate'; depth = 4 }
    if ($dup.error -or @($dup.result.nodes).Count -lt 1) {
        Write-Output '[chain2] synthetic RMB opened no menu; driving the operator with the cursor on the row'
        Op 'input.pointer' @{ x = $zx; y = $zy; action = 'move' } | Out-Null
        Wait-Idle
        Op 'hierarchy.open_context_menu' @{} | Out-Null
        Wait-Idle; Wait-Idle
        $dup = Brp-Call 'jackdaw/ui_tree' @{ text = 'Duplicate'; depth = 4 }
    }
    if ($dup.error -or @($dup.result.nodes).Count -lt 1) { throw 'no context menu opened with a Duplicate row' }
    $dupRow = @($dup.result.nodes | Where-Object { $_.text -eq 'Duplicate' })
    if ($dupRow.Count -lt 1) { $dupRow = @($dup.result.nodes) }
    Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$dupRow[0].entity } | Out-Null
    Wait-Idle; Wait-Idle
    Key 'Escape'

    $h5 = HistProbe
    $zones = ([regex]::Matches((SceneBsn), '(?m)^\s*#Zone')).Count
    Write-Output ("[chain2] undo_len: $($h4.undo_len) -> $($h5.undo_len) (top: $($h5.top)); #Zone in document: $zones")
    Check ($h5.undo_len -eq ($h4.undo_len + 1)) "chain2: the menu Duplicate is ONE entry (undo_len $($h4.undo_len) -> $($h5.undo_len))"
    Check ($zones -ge 2) "chain2: the copy reached the document (#Zone x$zones)"

    Op 'history.undo' @{} | Out-Null; Wait-Idle
    $zonesAfter = ([regex]::Matches((SceneBsn), '(?m)^\s*#Zone')).Count
    Check ($zonesAfter -eq ($zones - 1)) "chain2: ONE undo removes the copy (#Zone x$zones -> x$zonesAfter)"

    Brp-Call 'jackdaw/screenshot' @{ kind = 'window'; path = 'shots/chain2-window.png' } | Out-Null

    # ============ chain 3: drag Pebble out of the rock instance ==============
    $placed = Op 'prefab.spawn_instance' @{ path = 'prefabs/rock.bsn'; pos_x = 0.0; pos_y = 0.0; pos_z = 0.0 }
    Write-Output ("[chain3] spawn_instance result: " + ($placed | ConvertTo-Json -Depth 6 -Compress))
    Wait-Idle; Wait-Idle
    Start-Sleep -Seconds 2
    $ent = Brp-Call 'jackdaw/entity' @{ entity = $placed.result.entities[0] }
    Write-Output ("[chain3] spawned entity bsn: " + (($ent.result.bsn -split "`n") | Select-Object -First 6))
    $st = Brp-Call 'jackdaw/scene_tree' @{ depth = 3 }
    Write-Output ("[chain3] scene_tree: " + ($st.result | ConvertTo-Json -Depth 8 -Compress))
    Write-Output ("[chain3] scene_bsn head: " + ((SceneBsn -split "`n") | Select-Object -First 30))

    # Selecting Pebble makes the outliner reveal it: the reveal driver
    # expands Zone and Rock on its own, so the Pebble row exists to drag.
    Op 'selection.select' @{ name = 'Pebble' } | Out-Null
    Wait-Idle; Wait-Idle
    $pebbleRow = $null
    try { $pebbleRow = Row-Of-Or-Wait 'Pebble' 12 } catch { Write-Output '[chain3] selection reveal did not surface Pebble' }
    if (-not $pebbleRow) {
        # Fallback: click the disclosure checkboxes down the row chain.
        function Expand-Until([object]$Row, [string]$ChildLabel) {
            $checkboxes = @()
            $stack = New-Object System.Collections.Stack
            $stack.Push($Row)
            while ($stack.Count -gt 0 -and $checkboxes.Count -lt 4) {
                $n = $stack.Pop()
                foreach ($c in @($n.children)) {
                    if ($c.kind -eq 'checkbox') { $checkboxes += ,$c }
                    $stack.Push($c)
                }
            }
            foreach ($candidate in $checkboxes) {
                Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$candidate.entity } | Out-Null
                Wait-Idle
                Refresh-Tree
                $child = Row-Of $ChildLabel
                if (@($child).Count -gt 0) { return $child[0] }
            }
            return $null
        }
        $zoneRows2 = Row-Of 'Zone'
        if ($zoneRows2.Count -lt 1) { $zoneRowForExpand = Row-Of-Or-Wait 'Zone' } else { $zoneRowForExpand = $zoneRows2[0] }
        $rockRow = Expand-Until $zoneRowForExpand 'Rock'
        if ($rockRow) { $pebbleRow = Expand-Until $rockRow 'Pebble' }
    }
    if (-not $pebbleRow) { throw 'the Pebble row never became visible in the outliner' }
    Refresh-Tree
    $zoneRows = Row-Of 'Zone'
    if ($zoneRows.Count -lt 1) { $zoneRow = Row-Of-Or-Wait 'Zone' } else { $zoneRow = $zoneRows[0] }
    Write-Output ("[chain3] pebble row rect=[" + ($pebbleRow.rect -join ',') + "] zone row rect=[" + ($zoneRow.rect -join ',') + "]")

    $bsnBefore = SceneBsn
    $h6 = HistProbe
    # ui_drag fractions are relative to the Pebble row's box and may exceed
    # 0..1: aim the release at the Zone row's centre.
    $pcx = $pebbleRow.rect[0] + $pebbleRow.rect[2] / 2
    $pcy = $pebbleRow.rect[1] + $pebbleRow.rect[3] / 2
    $zcx = $zoneRow.rect[0] + $zoneRow.rect[2] / 2
    $zcy = $zoneRow.rect[1] + $zoneRow.rect[3] / 2
    $fx = 0.5 + ($zcx - $pcx) / $pebbleRow.rect[2]
    $fy = 0.5 + ($zcy - $pcy) / $pebbleRow.rect[3]
    Brp-Call 'jackdaw/ui_drag' @{ entity = [uint64]$pebbleRow.entity; from = @(0.5, 0.5); to = @($fx, $fy); steps = 24 } | Out-Null
    Wait-Idle; Wait-Idle; Wait-Idle

    $h7 = HistProbe
    $bsnAfter = SceneBsn
    $pebbles = ([regex]::Matches($bsnAfter, '#Pebble')).Count
    $pebblesBefore = ([regex]::Matches($bsnBefore, '#Pebble')).Count
    Write-Output ("[chain3] undo_len: $($h6.undo_len) -> $($h7.undo_len) (top: $($h7.top)); #Pebble: $pebblesBefore -> $pebbles")
    Check ($bsnAfter -ne $bsnBefore) 'chain3: the gesture changed the document'
    Check ($h7.undo_len -eq ($h6.undo_len + 1)) "chain3: the unpack gesture is ONE entry (undo_len $($h6.undo_len) -> $($h7.undo_len))"
    Check ($pebbles -eq ($pebblesBefore + 1)) "chain3: the unpacked child appears exactly once (#Pebble $pebblesBefore -> $pebbles)"

    Op 'history.undo' @{} | Out-Null; Wait-Idle
    $bsnBack = SceneBsn
    Check ($bsnBack -eq $bsnBefore) 'chain3: ONE undo returns the document byte-for-byte'
    Op 'history.redo' @{} | Out-Null; Wait-Idle
    Check ((SceneBsn) -eq $bsnAfter) 'chain3: redo restores the unpacked document'

    # save -> undo must leave the tab dirty (the N4 acceptance, T1 chain 2)
    Op 'scene.save' @{} | Out-Null; Wait-Idle
    Check (-not (Dirty)) 'chain3: saved reads clean'
    Op 'history.undo' @{} | Out-Null; Wait-Idle
    Check (Dirty) 'chain3: save then undo leaves the tab DIRTY (close must prompt)'

    Brp-Call 'jackdaw/screenshot' @{ kind = 'window'; path = 'shots/chain3-window.png' } | Out-Null

    # Copy the screenshots out of the throwaway project before the finally
    # removes it.
    try { Copy-Item (Join-Path $Project 'shots\*.png') $OutDir -Force -ErrorAction SilentlyContinue } catch {}

    Write-Output ("RESULT failures=" + $Failures)
    if ($Failures -gt 0) { exit 1 }
}
finally {
    try { Stop-Process -Id $editor.Id -Force -ErrorAction SilentlyContinue } catch {}
    Remove-Item -Recurse -Force $Project -ErrorAction SilentlyContinue
}
