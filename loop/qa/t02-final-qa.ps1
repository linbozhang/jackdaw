# T02 final QA real-machine driver (manual.md section 7 tools):
#   header  : category header follows tab clicks + sticky resolution (D4.2 live)
#   light   : light color edit loop, red then green, ECS + authored bsn (7-1)
#   save    : scene.save with path -> green on disk
#   switch  : quick-switch pollution regression rounds (7-3, T1 core semantics)
#   reopen  : relaunch editor -> light still green (7-1 leg 3)
#   wrap    : stop the editor
param(
    [Parameter(Mandatory = $true)][ValidateSet(
        'launch', 'header', 'light', 'save', 'switch', 'reopen', 'wrap'
    )][string]$Phase,
    [int]$Port = 15815,
    [string]$Proj = "$env:TEMP\t02final-qa",
    [string]$EditorLog = "$env:TEMP\t02final-editor.log"
)
$ErrorActionPreference = 'Stop'
$OutDir = 'E:\Project\rust\jackdaw\loop\reports\t02final-qa'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

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
function Op([string]$Id, $Params) { Brp-Call 'jackdaw/call_operator' @{ id = $Id; params = $Params } }
function Get-Tree { (Brp-Call 'jackdaw/ui_tree' @{ depth = 24 }).result.nodes }

$TRANSFORM = 'bevy_transform::components::transform::Transform'
$LIGHT = 'bevy_light::directional_light::DirectionalLight'

function Update-TransYs {
    $script:Ys = @{}
    $q = Brp-Call 'world.query' @{ data = @{ components = @('bevy_ecs::name::Name', $TRANSFORM) } } 60
    foreach ($row in @($q.result)) {
        $script:Ys[$row.components.'bevy_ecs::name::Name'] = [double]$row.components.$TRANSFORM.translation[1]
    }
}
function Get-LightColor {
    $q = Brp-Call 'world.query' @{ data = @{ components = @('bevy_ecs::name::Name', $LIGHT) } } 60
    foreach ($row in @($q.result)) {
        if ($row.components.'bevy_ecs::name::Name' -match 'Directional') {
            $c = $row.components.$LIGHT.color
            if ($null -ne $c.Srgba) { $c = $c.Srgba }
            if ($null -ne $c.LinearRgba) { $c = $c.LinearRgba }
            return @{ r = [double]$c.red; g = [double]$c.green; b = [double]$c.blue }
        }
    }
    return $null
}
function Stale-Log-Count {
    if (-not (Test-Path $EditorLog)) { return 0 }
    return @(Select-String -Path $EditorLog -Pattern 'field edit dropped: its entity left the selection').Count
}
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
function Select-Entity([string]$Name) {
    $r = Brp-Call 'jackdaw/ui_click' @{ entity = [uint64](Find-Row $Name).entity }
    if ($r.error) { throw "select ${Name}: $($r.error.message)" }
    Wait-Idle
}
# The always-on category header: the text node that reads the active label in
# the content column (x ~1703, y ~65 in a 1920 window, measured live). ui_tree
# text filters return subtree roots, so walk descendants for the text itself.
function Get-HeaderText {
    foreach ($needle in @('Object', 'Components')) {
        $t = Brp-Call 'jackdaw/ui_tree' @{ text = $needle; depth = 30 }
        $script:found = $null
        function TextWalk($n) {
            if ($script:found) { return }
            if ($n.text -eq $needle -and $n.rect -and $n.rect[0] -gt 1650 -and $n.rect[1] -gt 40 -and $n.rect[1] -lt 120) { $script:found = $n }
            foreach ($c in @($n.children)) { TextWalk $c }
        }
        foreach ($n in @($t.result.nodes)) { TextWalk $n }
        if ($script:found) { return $script:found.text }
    }
    return $null
}
# Strip tab cells: square (30px) pickable nodes in the strip rail at x ~1673,
# below the panel title. Returns them top-to-bottom.
function Get-StripTabs {
    $script:tabs = @()
    function TabWalk($n) {
        if ($n.rect -and $n.rect[0] -gt 1650 -and $n.rect[0] -lt 1710 -and $n.rect[1] -gt 40 `
                -and [math]::Abs($n.rect[2] - $n.rect[3]) -le 2 -and $n.rect[2] -gt 20 -and $n.rect[2] -lt 45) {
            $script:tabs += $n
        }
        foreach ($c in @($n.children)) { TabWalk $c }
    }
    foreach ($n in (Get-Tree)) { TabWalk $n }
    return @($script:tabs | Sort-Object { $_.rect[1] })
}
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
    $r = Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$script:cards[0].entity }
    if ($r.error) { throw "expand Transform: $($r.error.message)" }
    Wait-Idle
    Start-Sleep -Milliseconds 400
}
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
function Find-HexInput {
    $script:tree = Get-Tree
    $script:hexNode = $null
    function FindHex($n, $parent) {
        if ($script:hexNode) { return }
        if ($n.text -eq 'color:' -and $n.rect[0] -gt 1150) {
            foreach ($c in @($parent.children)) {
                if ($c.kind -eq 'text_input' -and $c.rect[2] -gt 1) { $script:hexNode = $c }
                foreach ($g in @($c.children)) {
                    if ($g.kind -eq 'text_input' -and $g.rect[2] -gt 1) { $script:hexNode = $g }
                }
            }
            return
        }
        foreach ($c in @($n.children)) { FindHex $c $n }
    }
    foreach ($n in @($script:tree)) { FindHex $n $null }
    if (-not $script:hexNode) { throw 'no hex color input found beside the color: label' }
    return $script:hexNode
}
function Type-Hex([string]$Value) {
    $hex = Find-HexInput
    $in = Brp-Call 'jackdaw/ui_input' @{ entity = [uint64]$hex.entity; text = $Value; commit = 'enter' }
    if ($in.error) { throw "ui_input ${Value}: $($in.error.message)" }
    Wait-Idle
    Start-Sleep -Milliseconds 300
}
function Assert-Color([string]$Tag, [double]$R, [double]$G, [double]$B) {
    $c = Get-LightColor
    Write-Output ("[color $Tag] " + ($c | ConvertTo-Json -Compress))
    $ok = ($c -and [math]::Abs($c.r - $R) -lt 0.01 -and [math]::Abs($c.g - $G) -lt 0.01 -and [math]::Abs($c.b - $B) -lt 0.01)
    if (-not $ok) { throw "color $Tag mismatch" }
    return $c
}
function Assert-BsnColor([string]$Tag, [string]$Channel) {
    $ent = $null
    foreach ($nm in @('Directional Light', 'Sun', 'DirectionalLight')) {
        $r = Brp-Call 'jackdaw/entity' @{ name = $nm }
        if ($r.result -and $r.result.bsn) { $ent = $r.result; break }
    }
    if (-not $ent) { throw "no authored entity for bsn $Tag check" }
    $ent.bsn | Set-Content -Encoding UTF8 (Join-Path $OutDir "bsn-$Tag.txt")
    $lines = $ent.bsn -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'DirectionalLight') {
            for ($j = $i + 1; $j -lt [Math]::Min($i + 22, $lines.Count); $j++) {
                if ($lines[$j] -match ($Channel + ':\s*([-\d.e]+)')) {
                    $v = [double]$Matches[1]
                    if ($v -gt 0.99) { Write-Output "[bsn $Tag] $Channel = $v"; return }
                }
            }
            throw "bsn ${Tag}: channel $Channel not >0.99 near DirectionalLight"
        }
    }
    throw "bsn ${Tag}: no DirectionalLight block"
}

function Write-LaunchCmd {
    $sysroot = (& rustc --print sysroot).Trim()
    $tcLib = Join-Path $sysroot 'lib\rustlib\x86_64-pc-windows-msvc\lib'
    $deps = 'E:\Project\rust\jackdaw\target\debug\deps'
    $bat = "$env:TEMP\t02final-launch.cmd"
    $lines = @(
        "@echo off",
        "set PATH=$deps;$tcLib;%PATH%",
        "set JACKDAW_OPEN_PROJECT=$Proj",
        "set JACKDAW_REMOTE_PORT=$Port",
        "set JACKDAW_SKIP_SETUP_CHECK=1",
        "set JACKDAW_WINDOW_SIZE=1920x1080",
        "cd /d E:\Project\rust\jackdaw",
        "start `"jdqa`" /MIN cmd /c `"target\debug\jackdaw.exe > $EditorLog 2>&1`"",
        "exit"
    )
    [System.IO.File]::WriteAllLines($bat, $lines)
    return $bat
}

switch ($Phase) {
    'launch' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path "$Proj\assets" | Out-Null
        if (-not (Test-Path "$Proj\Cargo.toml")) {
            Set-Content -Encoding UTF8 "$Proj\Cargo.toml" "[package]`nname = `"t02final-qa`"`nversion = `"0.1.0`"`nedition = `"2021`""
        }
        if (-not (Test-Path "$Proj\jackdaw.toml")) {
            Set-Content -Encoding UTF8 "$Proj\jackdaw.toml" "[jackdaw]`nbevy = `"0.20`""
        }
        $bat = Write-LaunchCmd
        $shell = New-Object -ComObject Shell.Application
        $shell.ShellExecute('open', "`"$bat`"", '', 'open', 0) | Out-Null
        $deadline = (Get-Date).AddSeconds(180); $ok = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 4
            if (netstat -ano | Select-String ":$Port\s.*LISTENING") { $ok = $true; break }
        }
        Write-Output "LISTENING=$ok"
        if (-not $ok) { throw 'editor never listened' }
        Brp-Call 'jackdaw/status' @{} 90 | Out-Null
        Wait-Idle
        foreach ($op in @('entity.add.directional_light', 'entity.add.cube', 'entity.add.point_light')) {
            $r = Op $op @{}
            Write-Output ("[add] $op -> " + ($r.result | ConvertTo-Json -Compress))
        }
        Wait-Idle
    }
    'header' {
        Select-Entity 'Directional Light'
        $h0 = Get-HeaderText
        Write-Output ("[header on light, default] " + $h0)
        if ($h0 -ne 'Object') { throw "header should start at Object, got $h0" }
        $tabs = Get-StripTabs
        Write-Output ("[strip tabs] " + (@($tabs | ForEach-Object { "$($_.entity)@[$($_.rect -join ',')]" }) -join ' '))
        if ($tabs.Count -lt 2) { throw "expected 2+ strip tabs on a light entity, got $($tabs.Count)" }
        $bottom = $tabs[-1]
        $r = Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$bottom.entity }
        if ($r.error) { throw "click bottom tab: $($r.error.message)" }
        Write-Output ("[clicked bottom tab] " + ($r.result | ConvertTo-Json -Compress))
        Wait-Idle; Start-Sleep -Milliseconds 300
        $h1 = Get-HeaderText
        Write-Output ("[header after tab click] " + $h1)
        if ($h1 -ne 'Components') { throw "header should read Components after the bottom tab click, got $h1" }
        # Sticky resolution, live: Cube has no generic component card, so
        # reselecting it rebuilds and resolves Components -> Object.
        Select-Entity 'Cube'
        Start-Sleep -Milliseconds 300
        $h2 = Get-HeaderText
        Write-Output ("[header on cube after sticky resolve] " + $h2)
        if ($h2 -ne 'Object') { throw "header should resolve back to Object on the cube, got $h2" }
        Write-Output 'HEADER VERDICT: PASS'
    }
    'light' {
        Select-Entity 'Directional Light'
        # expand the DirectionalLight card if the color row is hidden (sticky
        # per component name, idempotent check like t02t2 script)
        $script:tree = Get-Tree
        $script:hasColor = $false
        function HasColor($n) {
            if ($n.text -eq 'color:' -and $n.rect[0] -gt 1150 -and $n.rect[2] -gt 0) { $script:hasColor = $true; return }
            foreach ($c in @($n.children)) { HasColor $c }
        }
        foreach ($n in @($script:tree)) { HasColor $n }
        if (-not $script:hasColor) {
            $script:card = $null
            function FindCard($n) {
                if ($script:card) { return }
                if ($n.text -match 'Directional' -and $n.rect[0] -gt 1150 -and $n.rect[2] -gt 1) { $script:card = $n; return }
                foreach ($c in @($n.children)) { FindCard $c }
            }
            foreach ($n in @($script:tree)) { FindCard $n }
            if ($script:card) {
                $r = Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$script:card.entity }
                Write-Output ("[expand card] " + ($r.result | ConvertTo-Json -Compress))
                Wait-Idle; Start-Sleep -Milliseconds 300
            }
        } else { Write-Output '[expand card] color row already visible' }
        $b = Brp-Call 'jackdaw/screenshot' @{ kind = 'viewport'; path = 'fqa-before.png' } 60
        Start-Sleep -Milliseconds 400
        if (Test-Path "$Proj\fqa-before.png") { Copy-Item "$Proj\fqa-before.png" "$OutDir\20-before.png" -Force }
        Type-Hex 'ff0000'
        Assert-Color 'red' 1.0 0.0 0.0
        Assert-BsnColor 'red' 'red'
        Type-Hex '00ff00'
        Assert-Color 'green' 0.0 1.0 0.0
        Assert-BsnColor 'green' 'green'
        $a = Brp-Call 'jackdaw/screenshot' @{ kind = 'viewport'; path = 'fqa-after.png' } 60
        Start-Sleep -Milliseconds 400
        if (Test-Path "$Proj\fqa-after.png") { Copy-Item "$Proj\fqa-after.png" "$OutDir\21-after-green.png" -Force }
        Write-Output '[pixdiff before/after]'
        & powershell -ExecutionPolicy Bypass -File E:\Project\rust\jackdaw\loop\qa\pixdiff.ps1 -A "$OutDir\20-before.png" -B "$OutDir\21-after-green.png"
        Write-Output 'LIGHT VERDICT: PASS'
    }
    'save' {
        $target = "$Proj\assets\qa-scene.bsn"
        $r = Op 'scene.save' @{ path = $target }
        Write-Output ("[save] " + ($r.result | ConvertTo-Json -Compress))
        Wait-Idle; Start-Sleep -Milliseconds 800
        if (-not (Test-Path $target)) { throw 'scene.bsn not on disk' }
        $f = Get-Item $target
        Write-Output ("[on disk] " + $f.FullName + " (" + $f.Length + " bytes)")
        $txt = [System.IO.File]::ReadAllText($target)
        Copy-Item $target "$OutDir\22-scene-on-disk.bsn" -Force
        if (-not ($txt -match 'green:\s*1\.0' -and $txt -match 'DirectionalLight')) { throw 'disk scene does not carry the green light' }
        Write-Output 'SAVE VERDICT: PASS'
    }
    'switch' {
        function Switch-Round([int]$N, [string]$From, [string]$To, [string]$Typed) {
            Select-Entity $From
            Ensure-TransformExpanded
            $y = Find-YInput
            Write-Output ("round ${N}: $From Y input e=" + $y.entity)
            Update-TransYs
            $beforeTo = $script:Ys[$To]
            $beforeFrom = $script:Ys[$From]
            $staleBefore = Stale-Log-Count
            $in = Brp-Call 'jackdaw/ui_input' @{ entity = [uint64]$y.entity; text = $Typed; commit = 'none' }
            if ($in.error) { throw "round ${N}: ui_input: $($in.error.message)" }
            $rowB = Find-Row $To
            $clk = Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$rowB.entity }
            if ($clk.error) { throw "round ${N}: ui_click $To`: $($clk.error.message)" }
            Wait-Idle; Start-Sleep -Milliseconds 300
            Update-TransYs
            $afterTo = $script:Ys[$To]
            $afterFrom = $script:Ys[$From]
            $staleAfter = Stale-Log-Count
            $verdict = if ([math]::Abs($afterTo - $beforeTo) -lt 1e-6) { 'PASS' } else { 'FAIL' }
            Write-Output ("round {0}: edit {1}.y='{2}' +switch->{3}: {3}.y {4}->{5} [{6}]; {1}.y {7}->{8}; stale-warn +{9}" -f `
                $N, $From, $Typed, $To, $beforeTo, $afterTo, $verdict, $beforeFrom, $afterFrom, ($staleAfter - $staleBefore))
            if ($verdict -eq 'FAIL') { $script:Failed = $true }
        }
        $script:Failed = $false
        Switch-Round 1 'Directional Light' 'Cube' '7.5'
        Switch-Round 2 'Cube' 'Point Light' '-3.5'
        Write-Output ("SWITCH VERDICT: " + $(if ($script:Failed) { 'FAIL' } else { 'PASS' }) + "; total stale-drop warns: " + (Stale-Log-Count))
    }
    'reopen' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $bat = Write-LaunchCmd
        $shell = New-Object -ComObject Shell.Application
        $shell.ShellExecute('open', "`"$bat`"", '', 'open', 0) | Out-Null
        $deadline = (Get-Date).AddSeconds(180); $ok = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 4
            if (netstat -ano | Select-String ":$Port\s.*LISTENING") { $ok = $true; break }
        }
        if (-not $ok) { throw 'editor never listened on reopen' }
        Brp-Call 'jackdaw/status' @{} 90 | Out-Null
        Wait-Idle
        $c = Get-LightColor
        Write-Output ("[color after reopen] " + ($c | ConvertTo-Json -Compress))
        $ok = ($c -and $c.g -gt 0.99 -and $c.r -lt 0.01 -and $c.b -lt 0.01)
        Write-Output ("REOPEN VERDICT: " + $(if ($ok) { 'PASS' } else { 'FAIL' }))
    }
    'wrap' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Output 'editor stopped'
    }
}
