# T07-T3 QA: independent rerun of matrix cell 2 (failure keeps the old
# export) and cell 5 (--out guard three states), CLI-driven on my-game.
# Cell 2 injection: hold an open handle on the previous dist's exe (no
# FILE_SHARE_DELETE) - the swap's first rename of the dist directory is
# refused on Windows, so the export fails and the old dist must stay
# byte-identical. (The program's probe used a pid-derived staging squat,
# which needs the child's pid up front; the locked-handle injection tests
# the same cell semantics and is deterministic.)
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$Jd   = Join-Path $Repo 'target\debug\jd.exe'
$Proj = 'C:\Users\linbo.zhang\Projects\my-game'
$Out  = Join-Path $Repo 'loop\t07t3-qa-live'
New-Item -ItemType Directory -Force -Path $Out | Out-Null

function Jd-Export([string[]]$Extra) {
    $args = @('export', '--project', $Proj) + $Extra
    & $Jd @args 2>&1 | Out-String
}

function Tree-Sha([string]$Dir) {
    Get-ChildItem $Dir -Recurse -File | Sort-Object FullName |
        ForEach-Object { '{0}={1}' -f $_.FullName.Substring($Dir.Length), (Get-FileHash $_.FullName -Algorithm SHA256).Hash } |
        Get-Unique
}

# ---------- cell 5: --out guard three states ----------
Write-Host '== cell 5: --out guard =='
$dist5 = Join-Path $Out 'cell5-dist'
Remove-Item $dist5 -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $dist5 | Out-Null
Set-Content (Join-Path $dist5 'important.txt') 'precious'

$leg1 = Jd-Export @('--out', $dist5)
$refused = ($LASTEXITCODE -ne 0) -and ($leg1 -match 'not ours|--force|refus')
$kept = (Get-Content (Join-Path $dist5 'important.txt') -Raw) -eq "precious`n"
Write-Host ("  leg1 refused={0} exit={1} important-kept={2}" -f $refused, $LASTEXITCODE, $kept)
if ($leg1.Length -lt 400) { Write-Host ('  leg1 output: ' + $leg1.Trim().Substring(0, [Math]::Min(360, $leg1.Trim().Length))) }

$leg2 = Jd-Export @('--out', $dist5, '--force')
$forced = ($LASTEXITCODE -eq 0)
$replaced = -not (Test-Path (Join-Path $dist5 'important.txt'))
$marker = Test-Path (Join-Path $dist5 '.jackdaw-export')
$manifest = Test-Path (Join-Path $dist5 'export-manifest.json')
$exe = @(Get-ChildItem $dist5 -Filter *.exe).Count -gt 0
$assets = Test-Path (Join-Path $dist5 'assets')
Write-Host ("  leg2 force-ok={0} important-gone={1} marker={2} manifest={3} exe={4} assets={5}" -f $forced, $replaced, $marker, $manifest, $exe, $assets)
Write-Host '== cell 5 done =='

# ---------- cell 2: failure keeps the old export ----------
Write-Host '== cell 2: locked old dist -> export fails, old dist intact =='
$dist2 = Join-Path $Out 'cell2-dist'
Remove-Item $dist2 -Recurse -Force -ErrorAction SilentlyContinue
$r0 = Jd-Export @('--out', $dist2)
Write-Host ("  baseline export exit={0}" -f $LASTEXITCODE)
if (-not (Test-Path $dist2)) { Write-Host 'BASELINE EXPORT FAILED - aborting cell 2'; exit 1 }
$before = Tree-Sha $dist2

# Hold the old dist's exe open without FILE_SHARE_DELETE: the swap's first
# step (renaming the dist directory aside) must be refused on Windows.
$exe2 = @(Get-ChildItem $dist2 -Filter *.exe)[0].FullName
$handle = [System.IO.File]::Open($exe2, 'Open', 'Read', 'ReadWrite')
try {
    $r2 = Jd-Export @('--out', $dist2)
    $failed = $LASTEXITCODE -ne 0
    Write-Host ("  locked export failed={0} exit={1}" -f $failed, $LASTEXITCODE)
    if ($r2.Length -lt 400) { Write-Host ('  output: ' + $r2.Trim().Substring(0, [Math]::Min(360, $r2.Trim().Length))) }
} finally {
    $handle.Close()
}
$after = Tree-Sha $dist2
$identical = ($before -join '|') -eq ($after -join '|')
Write-Host ("  old dist byte-identical across the failed export: {0} ({1} files)" -f $identical, @($before).Count)
Write-Host '== cell 2 done =='

# cleanup the dist dirs (leave nothing under loop/t07t3-qa-live)
Remove-Item $dist5 -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $dist2 -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem $Proj -Filter '*.staging-*' -Force -ErrorAction SilentlyContinue | Out-Null
Write-Host 'T07T3_QA_CELLS_DONE'
