# Prepare QA chain assets: fresh isolated config + launch bat on port 15815.
$ErrorActionPreference = 'Stop'
$cfg = "$env:TEMP\t04-final-cfg-qa"
if (Test-Path $cfg) { Remove-Item -Recurse -Force $cfg }
New-Item -ItemType Directory -Force -Path $cfg | Out-Null
$sysroot = (& rustc --print sysroot).Trim()
$tcLib = Join-Path $sysroot 'lib\rustlib\x86_64-pc-windows-msvc\lib'
$deps = 'E:\Project\rust\jackdaw\target\debug\deps'
$bat = "$env:TEMP\t04-final-launch.cmd"
$editorLog = "$env:TEMP\t04-final-qa-editor.log"
$lines = @(
    "@echo off",
    "set PATH=$deps;$tcLib;%PATH%",
    "set JACKDAW_OPEN_PROJECT=C:\Users\linbo.zhang\Projects\my-game",
    "set JACKDAW_CONFIG_DIR=$cfg",
    "set JACKDAW_REMOTE_PORT=15815",
    "set JACKDAW_SKIP_SETUP_CHECK=1",
    "cd /d E:\Project\rust\jackdaw",
    "start `"t04t3qa`" /MIN cmd /c `"target\debug\jackdaw.exe > $editorLog 2>&1`"",
    "exit"
)
[System.IO.File]::WriteAllLines($bat, $lines)
Write-Output ("cfg: " + $cfg)
Write-Output ("bat: " + $bat + " (port 15815)")
