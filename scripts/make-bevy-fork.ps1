# Make the version-pinned bevy fork the physics integration patches to.
#
# The workspace tracks bevy's git main branch, whose crates carry
# pre-release versions (`0.20.0-dev`). avian (and anything else on
# registry bevy) requires `^0.20`, which a pre-release can never
# satisfy, so a plain git `[patch]` is silently ignored and the two
# bevy trees coexist with incompatible types. This script clones the
# pinned bevy commit into a directory beside the jackdaw checkout and
# rewrites every `0.20.0-dev` version string in its manifests to
# `0.20.0` — no source change, only version strings — so the fork
# satisfies registry version requirements and one `[patch.crates-io]
# bevy = { path = ... }` unifies every bevy type in the graph.
#
# When the workspace's bevy pin moves, re-run this script with the new
# rev and re-run `cargo update`: the git_deps guard keeps the fork and
# the workspace pin from drifting apart.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\make-bevy-fork.ps1
#   powershell ... -Rev <full-sha> -OutDir D:\somewhere\bevy-fork-pinned
param(
    # The bevy commit the workspace's Cargo.lock pins. Keep in step.
    [string]$Rev = 'c9c397ba1a73e6cfffe957318e0359330b701865',
    # Where the fork lives. The workspace's [patch.crates-io] names this
    # path; keep the default unless the checkout moved.
    [string]$OutDir = 'E:\Project\rust\bevy-fork-pinned'
)

$ErrorActionPreference = 'Stop'

# The cargo git cache for bevy, when this rev has been resolved before
# (jackdaw's own build populates it). A local clone from there avoids a
# full network fetch of bevy's history.
$cargoDb = Join-Path $env:USERPROFILE '.cargo\git\db'
$cargoCheckouts = Join-Path $env:USERPROFILE '.cargo\git\checkouts'
function Find-CargoCheckout([string]$rev) {
    Get-ChildItem $cargoCheckouts -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $candidate = Join-Path $_.FullName $rev.Substring(0, 7)
            if (Test-Path (Join-Path $candidate 'Cargo.toml')) { $candidate }
        } |
        Select-Object -First 1
}

if (Test-Path $OutDir) {
    throw "$OutDir already exists; remove it (or pick -OutDir) to remake the fork"
}

$source = Find-CargoCheckout $Rev
if ($source) {
    Write-Host "cloning the pinned rev from the cargo cache: $source"
    git clone $source $OutDir
    if ($LASTEXITCODE -ne 0) { throw 'git clone (local cache) failed' }
    git -C $OutDir checkout $Rev
    if ($LASTEXITCODE -ne 0) { throw "git checkout $Rev failed" }
} else {
    Write-Host 'no cached checkout; cloning bevy (blobless) from github'
    git clone --filter=blob:none --no-checkout https://github.com/bevyengine/bevy $OutDir
    if ($LASTEXITCODE -ne 0) { throw 'git clone failed' }
    git -C $OutDir checkout $Rev
    if ($LASTEXITCODE -ne 0) { throw "git checkout $Rev failed" }
}

# Rewrite the pre-release version strings in every manifest: version
# declarations and the version requirements the crates name each other
# with. `0.20.0-dev` appears only as these strings; nothing else in the
# tree carries them.
$manifests = Get-ChildItem $OutDir -Recurse -Filter Cargo.toml
$rewritten = 0
foreach ($manifest in $manifests) {
    $text = Get-Content $manifest.FullName -Raw
    if ($text -notmatch '0\.20\.0-dev') { continue }
    $text -replace '0\.20\.0-dev', '0.20.0' |
        Set-Content $manifest.FullName -NoNewline
    $rewritten++
}
Write-Host "rewrote the version strings in $rewritten manifests"

git -C $OutDir add -A
git -C $OutDir commit -m "Pin the workspace versions to 0.20.0 (version strings only, no source change)"
if ($LASTEXITCODE -ne 0) { throw 'git commit in the fork failed' }

# Record the upstream commit this fork stands on, so the build scripts can
# still name the bevy pin now that no lockfile carries a git bevy source.
$Rev | Set-Content (Join-Path $OutDir 'jackdaw-pinned-rev')
git -C $OutDir add jackdaw-pinned-rev
git -C $OutDir commit -m "Record the pinned upstream rev"
if ($LASTEXITCODE -ne 0) { throw 'git commit (pin record) failed' }

Write-Host "fork ready at $OutDir (bevy $Rev, versions 0.20.0)"
Write-Host 'patch line for the workspace manifest:'
Write-Host "[patch.crates-io]"
Write-Host "bevy = { path = '$OutDir' }"
