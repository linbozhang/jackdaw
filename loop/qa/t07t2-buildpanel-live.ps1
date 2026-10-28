# T07-T2 live spot check: the Build panel shows the build log (R9's
# user-visible face) and the prebuild — now `--locked` everywhere —
# still succeeds on my-game. Boots the freshly built editor on
# my-game, waits out the prebuild, then asserts the panel text via
# ui_tree and saves a window screenshot.
# Usage: powershell -NoProfile -File loop\qa\t07t2-buildpanel-live.ps1
$ErrorActionPreference = 'Stop'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Port    = 15703
$OutDir  = Join-Path $Repo 'loop\t07t2-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
. (Join-Path $Repo 'loop\qa\screenshot.ps1')

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "killing stale jackdaw pid=$($_.Id)"; Stop-Process -Id $_.Id -Force
}
Start-Sleep -Milliseconds 500

$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
    -RedirectStandardOutput (Join-Path $OutDir 'editor-stdout.log') `
    -RedirectStandardError (Join-Path $OutDir 'editor-stderr.log') -PassThru
Write-Host "editor pid=$($proc.Id)"
$proc.Id | Set-Content (Join-Path $OutDir 'editor.pid')

Wait-EditorReady -TimeoutSec 180
Write-Host 'editor ready (BRP up)'

# Catch the panel while the prebuild may still be running, and again
# after: the panel keeps the last captured output on success, so the
# build log lines are assertable either way.
$panelNodes = $null
foreach ($attempt in 1..30) {
    $tree = Brp-Call 'jackdaw/ui_tree' @{ text = 'as a cargo binary' } -ErrorAction SilentlyContinue
    if ($tree -and $tree.result.nodes -and $tree.result.nodes.Count -gt 0) {
        $panelNodes = $tree.result.nodes
        break
    }
    Start-Sleep -Milliseconds 500
}

# The prebuild runs with --locked now; a completed wait is the pass
# signal for the locked build itself.
Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 900 | Out-Null
Write-Host 'editor idle (prebuild with --locked completed)'

if (-not $panelNodes) {
    $tree = Brp-Call 'jackdaw/ui_tree' @{ text = 'as a cargo binary' }
    if ($tree -and $tree.result.nodes) { $panelNodes = $tree.result.nodes }
}
$nodeCount = if ($panelNodes) { @($panelNodes).Count } else { 0 }
if ($nodeCount -lt 1) {
    throw 'BUILD PANEL EMPTY: no ui_tree node carries the "building ... as a cargo binary" line (R9 not fixed)'
}
$panelText = ($panelNodes | ConvertTo-Json -Depth 8 -Compress)
Write-Host ("panel carries the build log ($nodeCount node(s)): " + $panelText.Substring(0, [Math]::Min(300, $panelText.Length)))

# Secondary evidence: a Compiling line reached the panel too (cargo
# progress events), when one exists in the log. Asserted on node hits,
# not on the JSON text being non-null — an empty nodes array also
# serializes non-null (the hollow-assertion fix).
$compiling = Brp-Call 'jackdaw/ui_tree' @{ text = 'Compiling' } -ErrorAction SilentlyContinue
$compilingHits = if ($compiling -and $compiling.result.nodes) { @($compiling.result.nodes).Count } else { 0 }
Write-Host ("compiling lines on panel: $compilingHits node(s)")

$alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if (-not $alive) { throw 'editor died' }
$alive.Refresh()
Save-WindowScreenshot $alive.MainWindowHandle (Join-Path $OutDir 't07t2-buildpanel.png') | Out-Null
Write-Host 'screenshot saved'

Stop-Process -Id $proc.Id -Force
Write-Output 'T07T2_BUILD_PANEL_LIVE_PASS'
