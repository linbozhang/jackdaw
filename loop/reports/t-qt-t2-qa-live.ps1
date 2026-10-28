# T-QT-T2 dogfood live QA: T02-T1 acceptance on a real editor, driven by the
# new ui_* BRP tools (manual.md section 7). Retry-capable Brp-Call throughout
# (T-QT-T1 round-2 lesson: stale keep-alive stalls one call every few hundred).
param(
    [Parameter(Mandatory = $true)][ValidateSet(
        'launch', 'setup', 'probe', 'switch', 'light', 'logscan', 'wrap'
    )][string]$Phase,
    [int]$Port = 15807,
    [string]$Proj = "$env:TEMP\t-qt-t2-proj",
    [string]$EditorLog = "$env:TEMP\t-qt-t2-editor.log"
)
$ErrorActionPreference = 'Stop'
$OutDir = 'E:\Project\rust\jackdaw\loop\reports\t-qt-t2-live'
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
function Save-Json($Name, $Value) {
    $Value | ConvertTo-Json -Depth 24 | Set-Content -Encoding UTF8 (Join-Path $OutDir $Name)
}

switch ($Phase) {
    'launch' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $Proj | Out-Null
        # launch4.cmd mode: the debug exe is a dylib-host after the integration
        # gate, so deps + toolchain lib go first on PATH; explorer-launch so the
        # windowed child gets the interactive desktop; stdout+stderr captured.
        $sysroot = (& rustc --print sysroot).Trim()
        $tcLib = Join-Path $sysroot 'lib\rustlib\x86_64-pc-windows-msvc\lib'
        $deps = 'E:\Project\rust\jackdaw\target\debug\deps'
        $bat = "$env:TEMP\t-qt-t2-launch.cmd"
        $lines = @(
            "@echo off",
            "set PATH=$deps;$tcLib;%PATH%",
            "set JACKDAW_OPEN_PROJECT=$Proj",
            "set JACKDAW_REMOTE_PORT=$Port",
            "set JACKDAW_SKIP_SETUP_CHECK=1",
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
        $s = Brp-Call 'jackdaw/status' @{} 90
        Write-Output ("STATUS=" + ($s.result | ConvertTo-Json -Compress -Depth 3))
        Wait-Idle
        $cam = Brp-Call 'jackdaw/camera_state' @{}
        Write-Output ("[camera_state sanity] " + ($cam.result | ConvertTo-Json -Compress))
        $tree = Brp-Call 'jackdaw/scene_tree' @{}
        Write-Output ("[scene_tree] " + ($tree.result | ConvertTo-Json -Compress -Depth 6))
        Save-Json '00-scene-tree.json' $tree.result
    }
    'setup' {
        # Create the switch-test entities through operators (the Add-menu picker
        # flow was proven with these tools last round; T02-T1 is about the edit
        # chain, not the menu).
        foreach ($op in 'entity.add.cube', 'entity.add.point_light') {
            $r = Op $op @{}
            Write-Output ("[add] $op -> " + ($r.result | ConvertTo-Json -Compress))
        }
        Wait-Idle
        $tree = Brp-Call 'jackdaw/scene_tree' @{}
        Write-Output ("[scene_tree] " + ($tree.result | ConvertTo-Json -Compress -Depth 6))
        Save-Json '01-scene-tree.json' $tree.result
    }
    'probe' {
        # Dump the ui_tree around the inspector + outliner to find the widgets
        # the switch test needs (outliner rows, the transform Y scrub input).
        $t = Brp-Call 'jackdaw/ui_tree' @{ depth = 14 }
        Save-Json '02-ui-tree-full.json' $t.result
        Write-Output ("[ui_tree] nodes=" + @($t.result.nodes).Count)
        $labels = Brp-Call 'jackdaw/ui_tree' @{ text = 'Cube' }
        Write-Output ("[text=Cube] " + ($labels.result | ConvertTo-Json -Compress -Depth 8))
        $inputs = Brp-Call 'jackdaw/ui_tree' @{ kind = 'text_input' }
        Write-Output ("[kind=text_input] count=" + @($inputs.result.nodes).Count)
        $inputs.result.nodes | ForEach-Object {
            Write-Output ("  ti e=$($_.entity) text='$($_.text)' op='$($_.operator)' rect=[$($_.rect -join ',')]")
        }
        # numeric scrub inputs are not FeathersTextInput; find label texts X/Y/Z
        foreach ($lab in 'X', 'Y', 'Z') {
            $n = Brp-Call 'jackdaw/ui_tree' @{ text = $lab }
            Write-Output ("[text=$lab] " + ($n.result | ConvertTo-Json -Compress -Depth 8))
        }
    }
    'switch' { . "$PSScriptRoot\t-qt-t2-qa-switch.ps1" -Port $Port -OutDir $OutDir -EditorLog $EditorLog }
    'light'  { . "$PSScriptRoot\t-qt-t2-qa-light.ps1" -Port $Port -OutDir $OutDir -EditorLog $EditorLog }
    'logscan' {
        $hits = Select-String -Path $EditorLog -Pattern 'field edit dropped|STALE|did not convert|live write skipped|field write skipped' -SimpleMatch:$false
        Write-Output ("[logscan] matches=" + @($hits).Count)
        $hits | ForEach-Object { Write-Output ("  L" + $_.LineNumber + ": " + $_.Line.Trim()) }
    }
    'wrap' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Output 'editor stopped'
    }
}
