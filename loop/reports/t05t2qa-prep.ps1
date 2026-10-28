$ErrorActionPreference = 'Stop'
$mg = 'C:\Users\linbo.zhang\Projects\my-game'
$bak = Join-Path $env:TEMP 't05t2qa-scenebak.bsn'
Copy-Item (Join-Path $mg 'assets\scene.bsn') $bak -Force
New-Item -ItemType Directory -Force -Path (Join-Path $mg 'assets\props') | Out-Null
$keeper = "#keeper`nbevy_transform::components::transform::Transform`n"
$victim = "#victim`nbevy_transform::components::transform::Transform`n"
[System.IO.File]::WriteAllText((Join-Path $mg 'assets\props\keeper.bsn'), $keeper)
[System.IO.File]::WriteAllText((Join-Path $mg 'assets\props\victim.bsn'), $victim)
$scenePath = Join-Path $mg 'assets\scene.bsn'
$scene = [System.IO.File]::ReadAllText($scenePath)
$probe = "`n#Probe`njackdaw::prefab::components::Prefab`njackdaw::prefab::components::IsA { source: `"props/victim.bsn`" }`n"
[System.IO.File]::WriteAllText($scenePath, $scene + $probe)
Write-Output '--- tail of scene.bsn:'
Get-Content $scenePath -Tail 4 -Encoding UTF8
Write-Output ('backup SHA: ' + (Get-FileHash $bak -Algorithm SHA256).Hash)
Write-Output ('backup at:  ' + $bak)
