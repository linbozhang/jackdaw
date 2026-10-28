# T-QT-T2 dogfood: T02 plan section 7-3 quick-switch rounds, new ui_* tools.
# Round shape: click outliner row A -> ui_input into A's Transform Y scrub
# input with commit=none (typed, uncommitted) -> immediately ui_click outliner
# row B: the click steals focus, so the number widget blur-commits its final
# ValueChange in the same frame the selection moves to B -- the D1 race live.
# Assert: B's translation.y never takes the typed value.
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

$TRANSFORM = 'bevy_transform::components::transform::Transform'
$script:Ids = @{}

# The bevy BRP world methods take entities as "NvM" strings and their rows
# carry names and translations; one query builds the whole name -> y map.
function Update-TransYs {
    $script:Ys = @{}
    $q = Brp-Call 'world.query' @{ data = @{ components = @('bevy_ecs::name::Name', $TRANSFORM) } } 60
    foreach ($row in @($q.result)) {
        $script:Ys[$row.components.'bevy_ecs::name::Name'] = [double]$row.components.$TRANSFORM.translation[1]
    }
}
function Get-TransY([string]$Name) {
    if (-not $script:Ys -or -not $script:Ys.ContainsKey($Name)) { Update-TransYs }
    return [double]$script:Ys[$Name]
}
function Stale-Log-Count {
    if (-not (Test-Path $EditorLog)) { return 0 }
    return @(Select-String -Path $EditorLog -Pattern 'field edit dropped: its entity left the selection').Count
}

# Full ui_tree flattened with parent links kept via recursion.
function Get-Tree { (Brp-Call 'jackdaw/ui_tree' @{ depth = 24 }).result.nodes }

# The outliner row for `Name`: the node whose direct child text equals Name.
function Find-Row([string]$Name) {
    $script:rows = @()
    function Walk($n) {
        if (@($n.children | Where-Object { $_.text -eq $Name }).Count -gt 0) { $script:rows += $n }
        foreach ($c in @($n.children)) { Walk $c }
    }
    foreach ($n in (Get-Tree)) { Walk $n }
    $rows = @($script:rows | Where-Object { $_.rect[0] -lt 300 -and $_.rect[2] -gt 0 })
    if ($rows.Count -lt 1) { throw "no outliner row for '$Name'" }
    return $rows[0]
}

# The Transform card starts collapsed (its field nodes measure zero); its
# header row carries the direct text child 'Transform'. One click expands it
# and the collapse state is sticky per component name, so once per entity
# kind is enough -- but calling it again is harmless (toggles it back! so
# only click when the Y input has no box yet).
function Ensure-TransformExpanded {
    $expanded = $true
    try { Find-YInput | Out-Null } catch { $expanded = $false }
    if ($expanded) { return }
    $script:cards = @()
    function CardWalk($n) {
        if ($n.rect -and $n.rect[1] -gt 100 -and @($n.children | Where-Object { $_.text -eq 'Transform' }).Count -gt 0) { $script:cards += $n }
        foreach ($c in @($n.children)) { CardWalk $c }
    }
    foreach ($n in (Get-Tree)) { CardWalk $n }
    if ($script:cards.Count -lt 1) { throw 'no Transform card header' }
    $card = $script:cards[0]
    $r = Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$card.entity }
    if ($r.error) { throw "expand Transform: $($r.error.message)" }
    Wait-Idle
    Start-Sleep -Milliseconds 400
}

# The translation.y input: the FeathersTextInput embedded in the Transform
# card's first (topmost) vector row. Inspector text inputs sit at x 1230-1315;
# group by y, first group = translation (X/Y/Z), middle = Y. The X/Y/Z label
# glyphs are siblings OUTSIDE the input -- clicking them focuses nothing
# (lesson from round 1-5 of the first run).
function Find-YInput {
    $t = Brp-Call 'jackdaw/ui_tree' @{ kind = 'text_input'; depth = 10 }
    $tis = @($t.result.nodes | Where-Object { $_.rect[3] -gt 20 })
    if ($tis.Count -lt 3) { throw "expected 3+ inspector text inputs, got $($tis.Count)" }
    $groups = @()
    foreach ($ti in ($tis | Sort-Object { $_.rect[1] })) {
        $placed = $false
        foreach ($g in $groups) {
            if ([math]::Abs($g.y - $ti.rect[1]) -lt 4) { $g.items += $ti; $placed = $true; break }
        }
        if (-not $placed) { $groups += , ([pscustomobject]@{ y = $ti.rect[1]; items = @($ti) }) }
    }
    $rows = @($groups | Where-Object { $_.items.Count -ge 3 } | Sort-Object { $_.y })
    if ($rows.Count -lt 1) { throw 'no 3-wide input row found' }
    $row1 = @($rows[0].items | Sort-Object { $_.rect[0] })
    if ($row1.Count -lt 3) { throw "translation row has $($row1.Count) inputs" }
    return $row1[1]
}

function Switch-Round([int]$N, [string]$From, [string]$To, [string]$Typed) {
    $rowA = Find-Row $From
    $r = Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$rowA.entity }
    if ($r.error) { throw "round ${N}: select $From`: $($r.error.message)" }
    Wait-Idle
    Ensure-TransformExpanded
    $y = Find-YInput
    Write-Output ("round ${N}: $From Y input e=" + $y.entity + " rect=[" + ($y.rect -join ',') + "]")
    Update-TransYs
    $beforeTo = Get-TransY $To
    $beforeFrom = Get-TransY $From
    $staleBefore = Stale-Log-Count

    # typed but not committed; the very next gesture is the switch click, so
    # the blur commit and the selection change share one frame.
    $in = Brp-Call 'jackdaw/ui_input' @{ entity = [uint64]$y.entity; text = $Typed; commit = 'none' }
    if ($in.error) { throw "round ${N}: ui_input: $($in.error.message)" }
    $rowB = Find-Row $To
    $clk = Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$rowB.entity }
    if ($clk.error) { throw "round ${N}: ui_click $To`: $($clk.error.message)" }
    Wait-Idle
    Start-Sleep -Milliseconds 300

    Update-TransYs
    $afterTo = Get-TransY $To
    $afterFrom = Get-TransY $From
    $staleAfter = Stale-Log-Count
    $verdict = if ([math]::Abs($afterTo - $beforeTo) -lt 1e-6) { 'PASS' } else { 'FAIL' }
    Write-Output ("round {0}: edit {1}.y='{2}' +switch->{3}: {3}.y {4}->{5} [{6}]; {1}.y {7}->{8}; stale-warn +{9}" -f `
        $N, $From, $Typed, $To, $beforeTo, $afterTo, $verdict, $beforeFrom, $afterFrom, ($staleAfter - $staleBefore))
    if ($verdict -eq 'FAIL') { $script:Failed = $true }
}

$script:Failed = $false
# five rounds across entity combinations (plan 7-3)
Switch-Round 1 'Sun' 'Cube' '7.5'
Switch-Round 2 'Cube' 'Sun' '3.25'
Switch-Round 3 'Sun' 'Point Light' '9.5'
Switch-Round 4 'Cube' 'Point Light' '-4.75'
Switch-Round 5 'Point Light' 'Cube' '6.125'

Write-Output ("SWITCH VERDICT: " + $(if ($script:Failed) { 'FAIL' } else { 'PASS' }) + "; total stale-drop warns: " + (Stale-Log-Count))
