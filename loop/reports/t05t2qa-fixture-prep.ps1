$ErrorActionPreference = 'Stop'
# Fixture-block reproduction: the T2 program's fixture shape (Cargo.toml [package] with no
# deps + jackdaw.toml bevy="0.20", no .jackdaw), launched the same way my-game was.
Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$proj = "$env:TEMP\t05t2-fixture-repro"
if (Test-Path $proj) { Remove-Item -Recurse -Force $proj }
New-Item -ItemType Directory -Force -Path "$proj\assets\materials", "$proj\assets\props", "$proj\assets\zones" | Out-Null
Set-Content -Encoding UTF8 "$proj\Cargo.toml" "[package]`nname = `"t05t2-qa`"`nversion = `"0.1.0`"`nedition = `"2021`""
Set-Content -Encoding UTF8 "$proj\jackdaw.toml" "[jackdaw]`nbevy = `"0.20`""
Set-Content -Encoding UTF8 "$proj\assets\materials\rust.material.bsn" "#rust`nbevy_pbr::pbr_material::StandardMaterial { metallic: 0.25 }`n"
Set-Content -Encoding UTF8 "$proj\assets\props\crate.bsn" "#crate`nbevy_transform::components::transform::Transform`n"
Set-Content -Encoding UTF8 "$proj\assets\zones\hedgerow.bsn" "#Sign`njackdaw::prefab::components::Prefab`njackdaw::prefab::components::IsA { source: `"props/gone.bsn`" }`n"
Write-Output ('fixture at: ' + $proj)
Get-ChildItem $proj -Recurse -File | ForEach-Object { Write-Output ('  ' + $_.FullName.Substring($proj.Length + 1)) }
# the launch bat (same env as my-game run)
$cfg = "$env:TEMP\t05t2-fixture-cfg"
if (Test-Path $cfg) { Remove-Item -Recurse -Force $cfg }
New-Item -ItemType Directory -Force -Path $cfg | Out-Null
$bat = "$env:TEMP\t05t2-fixture-launch.cmd"
$lines = @(
    "@echo off",
    "set PATH=E:\Project\rust\jackdaw\target\debug\deps;C:\Users\linbo.zhang\.rustup\toolchains\1.99.0-x86_64-pc-windows-msvc\lib\rustlib\x86_64-pc-windows-msvc\lib;%PATH%",
    "set JACKDAW_OPEN_PROJECT=$proj",
    "set JACKDAW_CONFIG_DIR=$cfg",
    "set JACKDAW_REMOTE_PORT=15831",
    "set JACKDAW_SKIP_SETUP_CHECK=1",
    "set JACKDAW_WINDOW_SIZE=1920x1080",
    "cd /d E:\Project\rust\jackdaw",
    "target\debug\jackdaw.exe > $env:TEMP\t05t2-fixture-editor.log 2>&1"
)
[System.IO.File]::WriteAllLines($bat, $lines)
Write-Output ('bat at: ' + $bat)
