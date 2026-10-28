# T11-T2 legacy-project leg: what does an OLD project (my-game, scaffolded
# before T11, whose Cargo.toml only knows jackdaw_runtime) gain from T1's
# unconditional camera_rig dependency with ZERO project changes?
#   1. The build compiles jackdaw_camera_rig into the game (cargo log).
#   2. The game's own schema extractor (the same run the editor's prebuild
#      does) reports the camera_rig types -- the type registry the scene
#      loader resolves CameraRig components against, i.e. components now
#      load resolved instead of the UnresolvedTypes fallback (the T05
#      safety net) without the project opting in.
#   3. Behavior (the driving plugin) still needs the one-line
#      add_plugins in the project's lib.rs -- recorded as the documented
#      upgrade boundary, not a regression.
# The project tree itself is untouched (zero-change claim checked: the
# game binary already exists from the prewarm build; nothing writes here).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File loop\qa\t11t2-mygame.ps1
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$OutDir = Join-Path $Repo 'loop\t11t2-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$Exe = Join-Path $Project 'target\debug\my-game.exe'
if (-not (Test-Path $Exe)) { Write-Host 'EXE_MISSING (prewarm build not found)'; exit 1 }

# zero-change check: the game's manifest has no camera_rig line of its own
$cargo = Get-Content (Join-Path $Project 'Cargo.toml') -Raw
$directDep = ($cargo -match 'jackdaw_camera_rig')
Write-Host ("MYGAME_1 direct camera_rig dep in project Cargo.toml: {0} (expect False -- the re-export path, not a project edit)" -f $directDep)

# the schema extractor: the game's own registry dump
$out = Join-Path $OutDir 't11t2-mygame-schema.json'
$err = Join-Path $OutDir 't11t2-mygame-extractor-stderr.log'
$p = Start-Process -FilePath $Exe -ArgumentList '--jackdaw-extract-schema' -WorkingDirectory $Project -PassThru `
    -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
$done = $p.WaitForExit(120000)
if (-not $done) { Stop-Process -Id $p.Id -Force; Write-Host 'MYGAME extractor timeout'; exit 1 }
Write-Host ("MYGAME_2 extractor exit: {0}" -f $p.ExitCode)

$schema = ''
if (Test-Path $out) { $schema = [IO.File]::ReadAllText($out) }
$hasRig = ($schema -match 'jackdaw_camera_rig::CameraRig')
$hasLook = ($schema -match 'jackdaw_camera_rig::CameraLook')
$hasActive = ($schema -match 'jackdaw_camera_rig::ActiveCameraRig')
$hasPlayerMarker = ($schema -match 'my_game::PlayerMarker')
# CameraLook is the runtime-half type registered by the DRIVING plugin
# (JackdawCameraRigPlugin), which a zero-change project has not wired --
# its absence is the honest boundary of the free upgrade, not a failure.
Write-Host ("MYGAME_3 schema: CameraRig={0} CameraLook={1} ActiveCameraRig={2} (author-face types arrive free; CameraLook belongs to the driving plugin an unwired project does not have)" -f $hasRig, $hasLook, $hasActive)
Write-Host ("MYGAME_4 project's own types: PlayerMarker={0} (this project predates the marker -- its absence is the project's age, not the upgrade)" -f $hasPlayerMarker)

# verdict: the re-export's claim is the author-face types with zero change
$ok = (-not $directDep) -and $hasRig -and $hasActive
Write-Host ("MYGAME_VERDICT: {0}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }))
Copy-Item $err (Join-Path $Repo 'loop\reports\t11t2_mygame_extractor_stderr.log') -Force
[IO.File]::WriteAllText((Join-Path $OutDir 't11t2-mygame-summary.txt'), `
        "directDep=$directDep exit=$($p.ExitCode) CameraRig=$hasRig CameraLook=$hasLook ActiveCameraRig=$hasActive PlayerMarker=$hasPlayerMarker`r`n")
Write-Host 'T11T2_MYGAME_DONE'
