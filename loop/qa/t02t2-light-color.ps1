# T02-T2 real-machine light color loop (manual.md section 7 tools):
# select Directional Light -> edit color through the ui chain (hex input via
# ui_input) -> assert ECS + authored bsn -> viewport screenshot diff ->
# scene.save -> scene.bsn on disk -> relaunch editor -> value persists.
param(
    [Parameter(Mandatory = $true)][ValidateSet(
        'launch', 'edit', 'save', 'reopen', 'wrap'
    )][string]$Phase,
    [int]$Port = 15809,
    [string]$Proj = "$env:TEMP\t02t2-proj",
    [string]$EditorLog = "$env:TEMP\t02t2-editor.log"
)
$ErrorActionPreference = 'Stop'
$OutDir = 'E:\Project\rust\jackdaw\loop\reports\t02t2-light'
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
function Get-Light {
    $q = Brp-Call 'world.query' @{ data = @{ components = @('bevy_ecs::name::Name', 'bevy_light::directional_light::DirectionalLight') } } 60
    foreach ($row in @($q.result)) {
        if ($row.components.'bevy_ecs::name::Name' -match 'Directional') { return $row.components.'bevy_light::directional_light::DirectionalLight' }
    }
    return $null
}
function Get-LightColor {
    $l = Get-Light
    if ($null -eq $l) { return $null }
    $c = $l.color
    if ($null -ne $c.Srgba) { $c = $c.Srgba }
    if ($null -ne $c.LinearRgba) { $c = $c.LinearRgba }
    return @{ r = [double]$c.red; g = [double]$c.green; b = [double]$c.blue }
}

switch ($Phase) {
    'launch' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $Proj | Out-Null
        # A temp project needs Cargo.toml + jackdaw.toml or the startup dialog
        # blocks headless driving (dogfood lesson, manual.md 7.5).
        if (-not (Test-Path "$Proj\Cargo.toml")) {
            Set-Content -Encoding UTF8 "$Proj\Cargo.toml" "[package]`nname = `"t02t2-qa`"`nversion = `"0.1.0`"`nedition = `"2021`""
        }
        if (-not (Test-Path "$Proj\jackdaw.toml")) {
            Set-Content -Encoding UTF8 "$Proj\jackdaw.toml" "[jackdaw]`nbevy = `"0.20`""
        }
        # launch4.cmd mode (integration gate leaves a dylib-host exe) + 1920x1080
        # so the inspector column is fully pickable.
        $sysroot = (& rustc --print sysroot).Trim()
        $tcLib = Join-Path $sysroot 'lib\rustlib\x86_64-pc-windows-msvc\lib'
        $deps = 'E:\Project\rust\jackdaw\target\debug\deps'
        $bat = "$env:TEMP\t02t2-launch.cmd"
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
        $r = Op 'entity.add.directional_light' @{}
        Write-Output ("[add] directional_light -> " + ($r.result | ConvertTo-Json -Compress))
        Wait-Idle
        $before = Get-LightColor
        Write-Output ("[color before] " + ($before | ConvertTo-Json -Compress))
        (Brp-Call 'jackdaw/scene_tree' @{}).result | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $OutDir '00-scene-tree.json')
    }
    'edit' {
        # 1. Select the light through its outliner row (node whose direct child
        #    text names it, left column).
        $script:rows = @()
        function Walk($n) {
            if (@($n.children | Where-Object { $_.text -match '^Directional Light$' -or $_.text -match '^Sun$' }).Count -gt 0) { $script:rows += $n }
            foreach ($c in @($n.children)) { Walk $c }
        }
        foreach ($n in (Get-Tree)) { Walk $n }
        $rows = @($script:rows | Where-Object { $_.rect[0] -lt 300 -and $_.rect[2] -gt 0 })
        if ($rows.Count -lt 1) { throw 'no outliner row for the directional light' }
        $r = Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$rows[0].entity }
        if ($r.error) { throw "ui_click select: $($r.error.message)" }
        Write-Output ("[select] " + ($r.result | ConvertTo-Json -Compress))
        Wait-Idle

        # 2. Viewport screenshot BEFORE the edit (screenshot paths are relative
        #    to the project dir; copy into the evidence dir).
        $b = Brp-Call 'jackdaw/screenshot' @{ kind = 'viewport'; path = 't02t2-before.png' } 60
        Write-Output ("[shot before] " + ($b.result | ConvertTo-Json -Compress))
        Start-Sleep -Milliseconds 500
        if (Test-Path "$Proj\t02t2-before.png") { Copy-Item "$Proj\t02t2-before.png" "$OutDir\10-before.png" -Force }

        # 3. Expand the DirectionalLight card (cards default to collapsed) --
        #    skipped when the color row is already in view, so reruns stay
        #    idempotent (clicking an expanded card title would collapse it).
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
                Wait-Idle
            } else { Write-Output '[expand card] no collapsed Directional card text found' }
        } else { Write-Output '[expand card] color row already visible (expanded)' }

        # 4. Locate the color hex input through the 'color:' label: the label,
        #    the hex box and the swatch share one row, so the hex input is a
        #    text_input inside the label's parent subtree with a real rect.
        #    (The probe reports every text_input's text as empty, so matching
        #    on a hex-looking value is not possible.)
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
        foreach ($n in @($script:tree)) { FindHex $n $n }
        if (-not $script:hexNode) { throw 'no hex color input found beside the color: label' }
        $hexNode = $script:hexNode
        Write-Output ("[hex input] e=$($hexNode.entity) rect=[$($hexNode.rect -join ',')]")

        # 5. Type the new color through the ui chain (focus -> select -> type ->
        #    enter commit -> hex_input_on_enter_key -> apply_color_with_undo).
        $in = Brp-Call 'jackdaw/ui_input' @{ entity = [uint64]$hexNode.entity; text = 'ff0000'; commit = 'enter' }
        if ($in.error) { throw "ui_input: $($in.error.message)" }
        Write-Output ("[typed] " + ($in.result | ConvertTo-Json -Compress))
        Wait-Idle
        Start-Sleep -Milliseconds 300

        # 6. Assert the ECS mirror turned red.
        $after = Get-LightColor
        Write-Output ("[color after] " + ($after | ConvertTo-Json -Compress))
        $ecsOk = ($after -and $after.r -gt 0.99 -and $after.g -lt 0.01 -and $after.b -lt 0.01)

        # 7. Assert the authored bsn carries the same value (try both common
        #    template names; entity.add.directional_light names it one way,
        #    fixture scenes the other).
        $ent = $null
        foreach ($nm in @('Directional Light', 'Sun', 'DirectionalLight')) {
            $r = Brp-Call 'jackdaw/entity' @{ name = $nm }
            if ($r.result -and $r.result.bsn) { $ent = $r.result; break }
        }
        if (-not $ent) {
            (Brp-Call 'jackdaw/scene_tree' @{}).result | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $OutDir '11-scene-tree-for-name.txt')
        }
        $bsnRed = $false
        if ($ent -and $ent.bsn) {
            $lines = $ent.bsn -split "`n"
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match 'DirectionalLight') {
                    for ($j = $i + 1; $j -lt [Math]::Min($i + 22, $lines.Count); $j++) {
                        if ($lines[$j] -match 'red:\s*([-\d.e]+)' -and [double]$Matches[1] -gt 0.99) { $bsnRed = $true; break }
                    }
                    break
                }
            }
            $ent.bsn | Set-Content -Encoding UTF8 (Join-Path $OutDir '11-authored-bsn.txt')
        }
        Write-Output ("[bsn red] " + $bsnRed)

        # 8. Viewport screenshot AFTER + pixel diff.
        $a = Brp-Call 'jackdaw/screenshot' @{ kind = 'viewport'; path = 't02t2-after.png' } 60
        Write-Output ("[shot after] " + ($a.result | ConvertTo-Json -Compress))
        Start-Sleep -Milliseconds 500
        if (Test-Path "$Proj\t02t2-after.png") { Copy-Item "$Proj\t02t2-after.png" "$OutDir\12-after.png" -Force }
        Write-Output '[pixdiff before/after]'
        & powershell -ExecutionPolicy Bypass -File E:\Project\rust\jackdaw\loop\qa\pixdiff.ps1 -A "$OutDir\10-before.png" -B "$OutDir\12-after.png"

        $verdict = $(if ($ecsOk -and $bsnRed) { 'PASS' } else { 'FAIL' })
        Write-Output "EDIT VERDICT: $verdict (ecs=$ecsOk bsn=$bsnRed)"
    }
    'save' {
        # Untitled scene: scene.save with no path only asks (no dialog over
        # BRP), so the scene is retargeted at an explicit file first.
        $target = "$Proj\assets\qa-scene.bsn"
        $r = Op 'scene.save' @{ path = $target }
        Write-Output ("[save] " + ($r.result | ConvertTo-Json -Compress))
        Wait-Idle
        Start-Sleep -Milliseconds 800
        $bsn = @()
        if (Test-Path $target) { $bsn = @((Get-Item $target)) } else { $bsn = Get-ChildItem -Path $Proj -Recurse -Filter *.bsn | Select-Object -First 3 }
        foreach ($f in $bsn) { Write-Output ("[on disk] " + $f.FullName + " (" + $f.Length + " bytes)") }
        $diskOk = $false
        if ($bsn) {
            $txt = [System.IO.File]::ReadAllText($bsn[0].FullName)
            $diskOk = ($txt -match 'green:\s*1\.0' -and $txt -match 'DirectionalLight')
            Copy-Item $bsn[0].FullName "$OutDir\13-scene-on-disk.bsn" -Force
        }
        Write-Output ("SAVE VERDICT: " + $(if ($diskOk) { 'PASS' } else { 'FAIL' }))
    }
    'reopen' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        # Relaunch on the same project (same launch4 PATH mode).
        $bat = "$env:TEMP\t02t2-launch.cmd"
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
