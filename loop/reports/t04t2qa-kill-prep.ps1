# Prepare QA kill-chain assets: fresh isolated config dir + launch bat.
$ErrorActionPreference = 'Stop'
$cfg = "$env:TEMP\t04-kill-cfg-qa"
if (Test-Path $cfg) { Remove-Item -Recurse -Force $cfg }
New-Item -ItemType Directory -Force -Path $cfg | Out-Null
$sysroot = (& rustc --print sysroot).Trim()
$tcLib = Join-Path $sysroot 'lib\rustlib\x86_64-pc-windows-msvc\lib'
$deps = 'E:\Project\rust\jackdaw\target\debug\deps'
$bat = "$env:TEMP\t04-kill-launch.cmd"
$editorLog = "$env:TEMP\t04-kill-qa-editor.log"
$lines = @(
    "@echo off",
    "set PATH=$deps;$tcLib;%PATH%",
    "set JACKDAW_OPEN_PROJECT=C:\Users\linbo.zhang\Projects\my-game",
    "set JACKDAW_CONFIG_DIR=$cfg",
    "set JACKDAW_REMOTE_PORT=15814",
    "set JACKDAW_SKIP_SETUP_CHECK=1",
    "cd /d E:\Project\rust\jackdaw",
    "start `"t04qa`" /MIN cmd /c `"target\debug\jackdaw.exe > $editorLog 2>&1`"",
    "exit"
)
[System.IO.File]::WriteAllLines($bat, $lines)
Write-Output ("cfg: " + $cfg)
Write-Output ("bat: " + $bat)
Get-Content $bat | ForEach-Object { Write-Output ("  " + $_) }
