# Feature #8 task 1 real-machine spot check (BRP only, no screenshots needed):
# boot the plain editor on my-game, flip the viewport AA via operators, and
# assert the viewport camera's components appear/disappear exactly as
# dress_viewport_cameras should. Ends by restoring FXAA/SSAO-off defaults.
# Usage: powershell -NoProfile -File loop\qa\f8-t1-brp.ps1
$ErrorActionPreference = 'Stop'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Port    = 15703
$OutDir  = Join-Path $Repo 'loop\f8-t1'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port

$Smaa  = 'bevy_anti_alias::smaa::Smaa'
$Fxaa  = 'bevy_anti_alias::fxaa::Fxaa'
$Taa   = 'bevy_anti_alias::taa::TemporalAntiAliasing'
$Jit   = 'bevy_render::camera::TemporalJitter'
$Bias  = 'bevy_render::camera::MipBias'
$Ssao  = 'bevy_pbr::ssao::ScreenSpaceAmbientOcclusion'
$Norm  = 'bevy_core_pipeline::prepass::NormalPrepass'

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
try {
    Wait-EditorReady -TimeoutSec 120
    Write-Host 'editor ready'
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    Write-Host 'editor idle'

    $cam = Get-FlyCamera
    $camId = $cam.Entity
    Write-Host "viewport camera entity=$camId"

    function Has-Comp([string]$Path) {
        $r = Brp-Result (Brp-Call 'world.get_components' @{ entity = $camId; components = @($Path) })
        return ($null -ne $r.components.$Path)
    }
    function Set-AA([string]$choice) {
        Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'viewport.quality.set'; params = @{ anti_aliasing = $choice } }) | Out-Null
        Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } -TimeoutSec 30 | Out-Null
    }

    # Stage 0: default should be FXAA (only FXAA on the camera).
    Set-AA 'fxaa'
    if (-not (Has-Comp $Fxaa)) { throw 'fxaa: Fxaa component missing' }
    if (Has-Comp $Smaa -or (Has-Comp $Taa)) { throw 'fxaa: another AA component leaked' }
    Write-Host 'fxaa OK: only Fxaa present'

    # Stage 1: SMAA on - Smaa present (High preset), FXAA gone.
    Set-AA 'smaa'
    $r = Brp-Result (Brp-Call 'world.get_components' @{ entity = $camId; components = @($Smaa, $Fxaa, $Taa, $Jit, $Bias) })
    $c = $r.components
    if ($null -eq $c.$Smaa) { throw 'smaa: Smaa component missing' }
    if ($c.$Smaa.preset -ne 'High') { throw "smaa: preset is $($c.$Smaa.preset), want High" }
    if ($null -ne $c.$Fxaa) { throw 'smaa: Fxaa left behind' }
    if ($null -ne $c.$Taa -or $null -ne $c.$Jit -or $null -ne $c.$Bias) { throw 'smaa: TAA parts left behind' }
    Write-Host 'smaa OK: Smaa preset=High, fxaa/taa/jitter/mipbias all gone'

    # Stage 2: TAA on - Smaa gone, TAA+jitter+mipbias present.
    Set-AA 'taa'
    $r = Brp-Result (Brp-Call 'world.get_components' @{ entity = $camId; components = @($Smaa, $Taa, $Jit, $Bias) })
    $c = $r.components
    if ($null -ne $c.$Smaa) { throw 'taa: Smaa left behind' }
    if ($null -eq $c.$Taa -or $null -eq $c.$Jit -or $null -eq $c.$Bias) { throw 'taa: TAA parts missing' }
    Write-Host 'taa OK: TAA+TemporalJitter+MipBias present, Smaa gone'

    # Stage 3: SSAO on=ultra then off - component + NormalPrepass appear then go.
    Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'viewport.ssao.set'; params = @{ on = $true; quality = 'ultra' } }) | Out-Null
    Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } -TimeoutSec 30 | Out-Null
    $r = Brp-Result (Brp-Call 'world.get_components' @{ entity = $camId; components = @($Ssao, $Norm) })
    $c = $r.components
    if ($null -eq $c.$Ssao) { throw 'ssao: component missing' }
    if ($c.$Ssao.quality_level -ne 'Ultra') { throw "ssao: quality_level is $($c.$Ssao.quality_level), want Ultra" }
    if ($null -eq $c.$Norm) { throw 'ssao: NormalPrepass missing' }
    Write-Host 'ssao OK: SSAO quality=Ultra + NormalPrepass present'
    Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'viewport.ssao.set'; params = @{ on = $false } }) | Out-Null
    Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } -TimeoutSec 30 | Out-Null
    $r = Brp-Result (Brp-Call 'world.get_components' @{ entity = $camId; components = @($Ssao, $Norm) })
    if ($null -ne $r.components.$Ssao -or $null -ne $r.components.$Norm) {
        throw 'ssao off: SSAO or NormalPrepass left behind'
    }
    Write-Host 'ssao off OK: SSAO + NormalPrepass both gone'

    Write-Output 'F8_T1_BRP_SPOT_CHECK_PASS'
} finally {
    # Restore the defaults (FXAA) so the user's viewport.json is unchanged.
    try {
        Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'viewport.quality.set'; params = @{ anti_aliasing = 'fxaa' } }) | Out-Null
    } catch { }
    Start-Sleep -Milliseconds 500
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Write-Host "editor killed pid=$($proc.Id)"
}
