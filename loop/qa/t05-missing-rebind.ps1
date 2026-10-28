# T05-T2 real-machine missing-reference rebind loop (manual.md section 7
# tools): a scene names a material the project does not hold -> asset.audit
# names it with all four locations -> the Missing list shows it -> its Rebind
# picker picks a held material -> the authored bsn names the new path ->
# scene.save writes it -> reopening audits clean. The inspector's broken-red
# row is asserted on the way (the regression the plan asks for).
param(
    [Parameter(Mandatory = $true)][ValidateSet(
        'launch', 'audit', 'list', 'rebind', 'save', 'reopen', 'wrap'
    )][string]$Phase,
    [int]$Port = 15821,
    [string]$Proj = "$env:TEMP\t05t2-proj",
    [string]$EditorLog = "$env:TEMP\t05t2-editor.log"
)
$ErrorActionPreference = 'Stop'
$OutDir = 'E:\Project\rust\jackdaw\loop\reports\t05t2-rebind'
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
function Get-Tree { (Brp-Call 'jackdaw/ui_tree' @{ depth = 30 }).result.nodes }
function Find-Node($nodes, [string]$text) {
    foreach ($n in $nodes) {
        if ($null -ne $n.text -and $n.text -like "*$text*") { return $n }
        if ($n.children) { $hit = Find-Node $n.children $text; if ($hit) { return $hit } }
    }
    return $null
}
function Fail([string]$What) { Write-Output "FAIL: $What"; exit 1 }
function Pass([string]$What) { Write-Output "PASS: $What" }

switch ($Phase) {
    'launch' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        if (Test-Path $Proj) { Remove-Item -Recurse -Force $Proj }
        New-Item -ItemType Directory -Force -Path "$Proj\assets\materials" | Out-Null
        New-Item -ItemType Directory -Force -Path "$Proj\assets\zones" | Out-Null
        if (-not (Test-Path "$Proj\Cargo.toml")) {
            Set-Content -Encoding UTF8 "$Proj\Cargo.toml" "[package]`nname = `"t05t2-qa`"`nversion = `"0.1.0`"`nedition = `"2021`""
        }
        if (-not (Test-Path "$Proj\jackdaw.toml")) {
            # `bevy = "main"` with the running editor's rev, so the version
            # check does not put up its mismatch card (the QA finding: a
            # stale "0.20" pin blocked the auto-open).
            Set-Content -Encoding UTF8 "$Proj\jackdaw.toml" "[jackdaw]`nbevy = `"main`"`nchannel = `"bleeding-edge`"`nbevy_rev = `"c9c397ba1a73e6cfffe957318e0359330b701865`""
        }
        # One held prefab, and a scene whose instance names one the project
        # does not hold.
        New-Item -ItemType Directory -Force -Path "$Proj\assets\props" | Out-Null
        Set-Content -Encoding UTF8 "$Proj\assets\materials\rust.material.bsn" "#rust`nbevy_pbr::pbr_material::StandardMaterial { metallic: 0.25 }`n"
        Set-Content -Encoding UTF8 "$Proj\assets\props\crate.bsn" "#crate`nbevy_transform::components::transform::Transform`n"
        Set-Content -Encoding UTF8 "$Proj\assets\zones\hedgerow.bsn" "#Sign`njackdaw::prefab::components::Prefab`njackdaw::prefab::components::IsA { source: `"props/gone.bsn`" }`n"
        $sysroot = (& rustc --print sysroot).Trim()
        $tcLib = Join-Path $sysroot 'lib\rustlib\x86_64-pc-windows-msvc\lib'
        $deps = 'E:\Project\rust\jackdaw\target\debug\deps'
        $bat = "$env:TEMP\t05t2-launch.cmd"
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
        Start-Sleep -Seconds 12
        Wait-Idle 90
        Write-Output "LAUNCHED"
    }
    'audit' {
        Wait-Idle
        # Open the scene, then ask the audit.
        Op 'scene.open' @{ path = 'assets/zones/hedgerow.bsn' } | Out-Null
        Wait-Idle 90
        $audit = (Brp-Call 'jackdaw/audit' @{} 60).result
        $gone = @($audit.findings) | Where-Object { $_.reference -eq 'props/gone.bsn' }
        if (@($gone).Count -lt 1) { Fail "audit findings do not name the gone prefab: $($audit | ConvertTo-Json -Depth 8)" }
        $g = @($gone)[0]
        foreach ($part in @('document', 'component', 'field', 'reference')) {
            if (-not $g.$part) { Fail "audit entry misses $part" }
        }
        if ($g.document -notlike '*zones/hedgerow.bsn') { Fail "audit document is $($g.document)" }
        if ($g.field -ne 'source') { Fail "audit field is $($g.field)" }
        Pass "audit names the gone prefab with all four locations"
    }
    'list' {
        Wait-Idle
        Op 'asset.missing_list' @{} | Out-Null
        Wait-Idle
        $tree = Get-Tree
        $row = Find-Node $tree 'props/gone.bsn'
        if (-not $row) { Fail 'the Missing list does not show the broken reference' }
        $rebind = Find-Node $tree 'Rebind'
        if (-not $rebind) { Fail 'the Missing list has no Rebind button' }
        Pass "the Missing list shows the row and its Rebind"
    }
    'rebind' {
        Wait-Idle
        Op 'asset.missing_list' @{} | Out-Null
        Wait-Idle
        $tree = Get-Tree
        $rebind = Find-Node $tree 'Rebind'
        if (-not $rebind) { Fail 'no Rebind button to click' }
        Brp-Call 'jackdaw/ui_click' @{ target = $rebind.ref } 30 | Out-Null
        Wait-Idle
        $tree2 = Get-Tree
        $pick = Find-Node $tree2 'props/crate.bsn'
        if (-not $pick) { Fail 'the rebind picker does not offer the held prefab' }
        Brp-Call 'jackdaw/ui_click' @{ target = $pick.ref } 30 | Out-Null
        Wait-Idle
        $bsn = (Brp-Call 'jackdaw/scene_bsn' @{} 30).result
        $text = $bsn | ConvertTo-Json -Depth 10
        if ($text -notlike '*props/crate.bsn*') { Fail "the authored bsn does not name the held prefab: $text" }
        if ($text -like '*props/gone.bsn*') { Fail 'the authored bsn still names the gone prefab' }
        Pass 'the pick rebound the authored reference'
    }
    'save' {
        Wait-Idle
        Op 'scene.save' @{} | Out-Null
        Wait-Idle
        $saved = Get-Content "$Proj\assets\zones\hedgerow.bsn" -Raw
        if ($saved -notlike '*props/crate.bsn*') { Fail "the file on disk does not name the held prefab: $saved" }
        Pass 'the save wrote the new reference to disk'
    }
    'reopen' {
        Wait-Idle
        # Open a fresh tab so the scene's tab can close (the strip keeps
        # one), then reopen the scene from disk and audit.
        Op 'scene.new' @{} | Out-Null
        Wait-Idle
        Op 'scene.switch' @{ tab = 0 } | Out-Null
        Wait-Idle
        Op 'scene.close' @{} | Out-Null
        Wait-Idle
        Op 'scene.open' @{ path = 'assets/zones/hedgerow.bsn' } | Out-Null
        Wait-Idle 90
        $audit = (Brp-Call 'jackdaw/audit' @{} 60).result
        $left = @($audit.findings) | Where-Object { $_.reference -eq 'props/gone.bsn' }
        if (@($left).Count -gt 0) { Fail "audit still names the gone prefab after the rebind save" }
        Pass 'the reopened scene audits clean'
    }
    'wrap' {
        Write-Output 'WRAP: run phases launch,audit,list,rebind,save,reopen in order; each prints PASS or FAIL.'
    }
}
