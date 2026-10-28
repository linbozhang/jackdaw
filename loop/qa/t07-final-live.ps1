# T07 final live matrix (10 cells) — the export safety closeout.
# Cells 1/2/3/8/9/10 drive the editor on my-game over BRP; cells
# 5/6 drive the CLI on my-game; cell 7 drives the CLI on a throwaway
# assets_dir project. Long: cell 1 pays the first release build.
# Usage: powershell -NoProfile -File loop\qa\t07-final-live.ps1 [-Cells "1,2,..."]
param([string]$Cells = "1,2,3,4,5,6,7,8,9,10")
$ErrorActionPreference = 'Stop'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Jd      = Join-Path $Repo 'target\debug\jd.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Port    = 15703
$OutDir  = Join-Path $Repo 'loop\t07-final-live'
$Dist    = Join-Path $Project '.jackdaw\dist\release'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
. (Join-Path $Repo 'loop\qa\screenshot.ps1')

function Brp-Try([string]$method, $params, [int]$retries = 6) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = (Get-Random); method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 8)
        } catch {
            Start-Sleep -Milliseconds (500 * ($i + 1))
        }
    }
    return $null
}

function Tree-Hash([string]$root) {
    if (-not (Test-Path $root)) { return @() }
    $rows = Get-ChildItem $root -Recurse -File | Sort-Object FullName | ForEach-Object {
        '{0}={1}' -f $_.FullName.Substring($root.Length + 1), (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    }
    return $rows
}

function Tree-Hash-NoMeta([string]$root) {
    # Exclude the marker and manifest: both carry the export time.
    return @(Tree-Hash $root | Where-Object { $_ -notmatch '^[^.\\]+=(.*)?$' -or $true } |
        Where-Object { $_ -notlike '.jackdaw-export=*' -and $_ -notlike 'export-manifest.json=*' })
}

function Manifest-Strip-Time([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    $json = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $json.PSObject.Properties.Remove('generated_unix')
    return ($json | ConvertTo-Json -Depth 8 -Compress)
}

$pass = @(); $fail = @()
function Pass([string]$cell, [string]$note) { $script:pass += $cell; Write-Host "CELL $cell PASS: $note" }
function Fail([string]$cell, [string]$note) { $script:fail += $cell; Write-Host "CELL $cell FAIL: $note" }

$wanted = $Cells.Split(',') | ForEach-Object { $_.Trim() }

# A leftover dist from before the marker gate existed (feature#7-era
# exports carry no .jackdaw-export) makes every re-export refuse — the
# protection working as designed. Clear the slate once, explicitly, so
# the matrix measures this build's behavior, not the residue.
if ((Test-Path $Dist) -and -not (Test-Path (Join-Path $Dist '.jackdaw-export'))) {
    Write-Host "pre-clearing markerless legacy dist at $Dist"
    Remove-Item $Dist -Recurse -Force
}

$proc = $null
if ($wanted -contains '1' -or $wanted -contains '2' -or $wanted -contains '3' -or
    $wanted -contains '8' -or $wanted -contains '9' -or $wanted -contains '10') {
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
    $proc.Id | Set-Content (Join-Path $OutDir 'editor.pid')
    Wait-EditorReady -TimeoutSec 180
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 900 | Out-Null
    Write-Host "editor ready pid=$($proc.Id)"
}

# --- Cell 1: full editor export chain; Cell 8 rides its build window ---
if ($wanted -contains '1' -or $wanted -contains '8') {
    try {
        Brp-Try 'jackdaw/call_operator' @{ id = 'game.export' } | Out-Null
        $sawPanel = $false
        $deadline = (Get-Date).AddSeconds(1200)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 5
            if ($wanted -contains '8' -and -not $sawPanel) {
                # Compiling lines need actual compilation; a fully Fresh
                # build logs only the "building..." header. Either is
                # the panel carrying live build output.
                foreach ($probe in 'Compiling', 'as a cargo binary') {
                    $t = Brp-Try 'jackdaw/ui_tree' @{ text = $probe }
                    if ($t -and $t.result.nodes -and @($t.result.nodes).Count -gt 0) { $sawPanel = $true; break }
                }
            }
            $busy = Brp-Try 'jackdaw/wait' @{ until = 'idle' }
            if ($busy -and $busy.result.idle) { break }
        }
        if ($wanted -contains '8') {
            if ($sawPanel) { Pass '8' 'Build panel showed compiling lines during the export build' }
            else { Fail '8' 'no compiling line reached the panel' }
        }
        $face = Brp-Try 'jackdaw/export' @{}
        $state = $face.result.state
        if ($state -eq 'ready' -and $face.result.dist_dir -and "$($face.result.dist_dir)".Contains('dist')) {
            Pass '1' "jackdaw/export=ready dist=$($face.result.dist_dir) files=$($face.result.files) started_at=$($face.result.started_at)"
        } else { Fail '1' "jackdaw/export=$state face=$(($face | ConvertTo-Json -Depth 6 -Compress))" }
        $alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
        if ($alive) {
            $alive.Refresh()
            Save-WindowScreenshot $alive.MainWindowHandle (Join-Path $OutDir 'cell1-exported.png') | Out-Null
        }
    } catch { Fail '1' $_.Exception.Message; Fail '8' $_.Exception.Message }
}

# --- Cell 2: a failed export keeps the old one (live leg) ---
if ($wanted -contains '2') {
    try {
        $before = Tree-Hash $Dist
        $startedBefore = (Brp-Try 'jackdaw/export' @{}).result.started_at
        # Pre-squat the staging name the editor's export will pick
        # (pid + counter 0): a file blocks directory creation.
        $parent = Split-Path -Parent $Dist
        $blocker = Join-Path $parent (".release.staging-{0}-0" -f $proc.Id)
        Set-Content -Path $blocker -Value 'file blocks directory creation' -Encoding ASCII
        Brp-Try 'jackdaw/call_operator' @{ id = 'game.export' } | Out-Null
        # Wait for the new run to actually start (started_at moves), so
        # the assertions below read this run's outcome, not the previous
        # run's — the whole failure completes in well under a second
        # when the build is Fresh.
        $deadline = (Get-Date).AddSeconds(900)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3
            $face = Brp-Try 'jackdaw/export' @{}
            if ($face -and $face.result.started_at -ne $startedBefore) { break }
        }
        Start-Sleep -Seconds 5
        $face = Brp-Try 'jackdaw/export' @{}
        $after = Tree-Hash $Dist
        Remove-Item $blocker -Force -ErrorAction SilentlyContinue
        if ($face.result.state -eq 'failed' -and ($before -join ';') -eq ($after -join ';')) {
            Pass '2' "failed state=$($face.result.state), old dist SHA unchanged ($($before.Count) files)"
        } else {
            Fail '2' "state=$($face.result.state) unchanged=$((($before -join ';') -eq ($after -join ';')))"
        }
    } catch { Fail '2' $_.Exception.Message }
}

# --- Cell 3: repeat export idempotence (SHAs + manifest minus time) ---
if ($wanted -contains '3') {
    try {
        $firstHash = Tree-Hash-NoMeta $Dist
        $firstManifest = Manifest-Strip-Time (Join-Path $Dist 'export-manifest.json')
        Brp-Try 'jackdaw/call_operator' @{ id = 'game.export' } | Out-Null
        $deadline = (Get-Date).AddSeconds(900)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 5
            $busy = Brp-Try 'jackdaw/wait' @{ until = 'idle' }
            if ($busy -and $busy.result.idle) { break }
        }
        $secondHash = Tree-Hash-NoMeta $Dist
        $secondManifest = Manifest-Strip-Time (Join-Path $Dist 'export-manifest.json')
        if ((($firstHash -join ';') -eq ($secondHash -join ';')) -and $firstManifest -eq $secondManifest) {
            Pass '3' "second export byte-identical ($($firstHash.Count) files) + manifest equal (time excluded)"
        } else {
            Fail '3' "hash-equal=$((($firstHash -join ';') -eq ($secondHash -join ';'))) manifest-equal=$($firstManifest -eq $secondManifest)"
        }
    } catch { Fail '3' $_.Exception.Message }
}

# --- Cell 4: moved dist runs (window mode, screenshot not black) ---
if ($wanted -contains '4') {
    try {
        $moved = Join-Path $OutDir 'moved\deep\nest\game'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $moved) | Out-Null
        Remove-Item $moved -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item $Dist $moved -Recurse
        # NB: lowercase `$exe` would collide with `$Exe` — PowerShell
        # variable names are case-insensitive.
        $gameExe = Get-ChildItem $moved -Filter *.exe | Select-Object -First 1
        $game = Start-Process -FilePath $gameExe.FullName -WorkingDirectory $moved -PassThru
        Start-Sleep -Seconds 12
        $alive = Get-Process -Id $game.Id -ErrorAction SilentlyContinue
        if (-not $alive) { Fail '4' 'moved game exited immediately'; }
        else {
            $alive.Refresh()
            Save-WindowScreenshot $alive.MainWindowHandle (Join-Path $OutDir 'cell4-moved-game.png') | Out-Null
            Stop-Process -Id $game.Id -Force
            $shot = [System.IO.File]::ReadAllBytes((Join-Path $OutDir 'cell4-moved-game.png'))
            Pass '4' "moved game ran ${shot.Length} screenshot bytes (see cell4-moved-game.png)"
        }
    } catch { Fail '4' $_.Exception.Message }
}

# --- Cell 9: exporting while PIE runs ships no .jackdaw-pie/.bak ---
if ($wanted -contains '9') {
    try {
        Brp-Try 'jackdaw/call_operator' @{ id = 'pie.play' } | Out-Null
        Wait-BrpResult 'jackdaw/wait' @{ until = 'pie_running' } -TimeoutSec 900 | Out-Null
        Brp-Try 'jackdaw/call_operator' @{ id = 'game.export' } | Out-Null
        $deadline = (Get-Date).AddSeconds(900)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 5
            $busy = Brp-Try 'jackdaw/wait' @{ until = 'idle' }
            if ($busy -and $busy.result.idle) { break }
        }
        Brp-Try 'jackdaw/call_operator' @{ id = 'pie.stop' } | Out-Null
        Start-Sleep -Seconds 3
        $pieInDist = Test-Path (Join-Path $Dist 'assets\.jackdaw-pie')
        $bakInDist = [bool](Get-ChildItem (Join-Path $Dist 'assets') -Filter '*.bak' -Recurse -ErrorAction SilentlyContinue)
        if (-not $pieInDist -and -not $bakInDist) { Pass '9' 'PIE-session export shipped no .jackdaw-pie and no .bak' }
        else { Fail '9' "pie=$pieInDist bak=$bakInDist" }
    } catch { Fail '9' $_.Exception.Message }
}

# --- Cell 10: the Play regression after --locked ---
if ($wanted -contains '10') {
    try {
        Brp-Try 'jackdaw/call_operator' @{ id = 'pie.play' } | Out-Null
        Wait-BrpResult 'jackdaw/wait' @{ until = 'pie_running' } -TimeoutSec 900 | Out-Null
        Start-Sleep -Seconds 3
        $alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
        Brp-Try 'jackdaw/call_operator' @{ id = 'pie.stop' } | Out-Null
        Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 120 | Out-Null
        $alive2 = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
        if ($alive -and $alive2) { Pass '10' 'dev Play built (--locked) and ran; Stop returned to authoring' }
        else { Fail '10' "play alive=$([bool]$alive) after-stop alive=$([bool]$alive2)" }
    } catch { Fail '10' $_.Exception.Message }
}

# --- Cells 5/6: CLI --out protection and case-variant refusal ---
# These run with the editor closed (the script closes it first): a CLI
# export builds the same dev cache the editor uses, and one writer at a
# time is the clean way to keep the run reproducible.
if ($wanted -contains '5' -or $wanted -contains '6') {
    if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; $proc = $null; Start-Sleep -Seconds 2 }
    $deps = Join-Path (Split-Path -Parent $Exe) 'deps'
    $env:PATH = "$deps;$env:PATH"
    if ($wanted -contains '5') {
        try {
            $foreign = Join-Path $OutDir 'cell5\foreign'
            New-Item -ItemType Directory -Force -Path $foreign | Out-Null
            Set-Content (Join-Path $foreign 'important.txt') 'keep me'
            $out = & $Jd export --project $Project --profile dev --out $foreign 2>&1
            $refused = ($out -join ' ') -match 'does not belong to a jackdaw export'
            $kept = (Get-Content (Join-Path $foreign 'important.txt') -Raw -Encoding UTF8) -match 'keep me'
            $out2 = & $Jd export --project $Project --profile dev --out $foreign --force 2>&1
            $exeLanded = [bool](Get-ChildItem $foreign -Filter *.exe -ErrorAction SilentlyContinue)
            if ($refused -and $kept -and $exeLanded) { Pass '5' "refused+kept, --force staged into it" }
            else { Fail '5' "refused=$refused kept=$kept force-staged=$exeLanded out=$(($out + $out2) -join ' | ')" }
        } catch { Fail '5' $_.Exception.Message }
    }
    if ($wanted -contains '6') {
        try {
            # A case variant of the project root itself: the guard must
            # refuse it rather than delete the real sources.
            $variant = $Project.Substring(0, $Project.LastIndexOf('\')) + '\' + `
                (Split-Path -Leaf $Project).ToUpper()
            $out = & $Jd export --project $Project --profile dev --out $variant 2>&1
            $refused = ($out -join ' ') -match 'refusing to stage'
            $sourcesAlive = Test-Path (Join-Path $Project 'assets')
            if ($refused -and $sourcesAlive) { Pass '6' "case-variant --out refused, sources intact" }
            else { Fail '6' "refused=$refused sourcesAlive=$sourcesAlive out=$(($out) -join ' | ')" }
        } catch { Fail '6' $_.Exception.Message }
    }
}

# --- Cell 7: an assets_dir project stages under its own name ---
# A copy of the bevy fixture (jd refuses a project without a bevy
# dependency), its jackdaw.toml pointed at `content/`, and the heavy
# tier's warm build cache junctioned in so the dev build is incremental.
if ($wanted -contains '7') {
    try {
        $proj = Join-Path $OutDir 'cell7\bsn_game'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $proj) | Out-Null
        Remove-Item $proj -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item (Join-Path $Repo 'tests\fixtures\bsn_game') $proj -Recurse
        # Move the staged assets aside under the configured name.
        Move-Item (Join-Path $proj 'assets') (Join-Path $proj 'content')
        Add-Content (Join-Path $proj 'jackdaw.toml') "`nassets_dir = `"content`"`n"
        New-Item -ItemType Junction -Path (Join-Path $proj '.jackdaw\target') `
            -Target (Join-Path $Repo 'target\bsn_game_run\target') | Out-Null
        $out = & $Jd export --project $proj --profile dev 2>&1
        $dist = Join-Path $proj '.jackdaw\dist\dev'
        $contentLayout = Test-Path (Join-Path $dist 'content\scene.bsn')
        $noAssets = -not (Test-Path (Join-Path $dist 'assets'))
        $schemaRun = & (Join-Path $dist 'bsn_scene_game.exe') '--jackdaw-extract-schema' 2>&1
        $schemaOk = $LASTEXITCODE -eq 0
        if ($contentLayout -and $noAssets -and $schemaOk) { Pass '7' "dist/content layout + schema flag exit 0" }
        else { Fail '7' "content=$contentLayout noAssets=$noAssets schema=$schemaOk out=$(($out + $schemaRun) -join ' | ')" }
        # The junction made the copy cheap; do not let the recursive
        # cleanup of $proj walk into the real cache.
        Remove-Item (Join-Path $proj '.jackdaw\target') -Force
    } catch { Fail '7' $_.Exception.Message }
}

if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
Write-Host ("MATRIX: {0} passed, {1} failed ({2})" -f $pass.Count, $fail.Count, (($pass + $fail) -join ','))
if ($fail.Count -gt 0) { exit 1 } else { Write-Output 'T07_FINAL_LIVE_MATRIX_ALL_PASS' }
