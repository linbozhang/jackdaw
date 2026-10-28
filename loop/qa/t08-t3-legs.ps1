# T08-T3 remaining matrix legs (C2 restart, C7 export, C8 moved),
# after the long-form run confirmed C1/C5a/C9 live and left the dev
# target warm. C6 rides along (scene SHA across sessions).
$ErrorActionPreference = 'Continue'
$Repo = 'E:\Project\rust\jackdaw'
$Exe  = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'H:\workspace_AI\t08t3\t3game'
$Port = 15703
$OutDir = Join-Path $Repo 'loop\t08-t3-live'
. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
function Brp-Try([string]$method, $params, [int]$retries = 4) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = (Get-Random); method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 8)
        } catch { Start-Sleep -Milliseconds (400 * ($i + 1)) }
    }
    return $null
}
function Op([string]$id, $params) {
    if ($params) { Brp-Try 'jackdaw/call_operator' @{ id = $id; params = $params } }
    else { Brp-Try 'jackdaw/call_operator' @{ id = $id } }
}

$sceneFile = Join-Path $Project 'assets\scene.bsn'
$shaBefore = (Get-FileHash $sceneFile -Algorithm SHA256).Hash

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 800
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru `
    -RedirectStandardOutput (Join-Path $OutDir 'leg-out.log') -RedirectStandardError (Join-Path $OutDir 'leg-err.log')
for ($i = 0; $i -lt 90; $i++) { Start-Sleep -Seconds 2; if (Brp-Try 'jackdaw/status' @{} 1) { break } }
$deadline = (Get-Date).AddSeconds(2400)
while ((Get-Date) -lt $deadline) {
    $r = Brp-Try 'jackdaw/wait' @{ until = 'idle' } 1
    if ($r -and $r.result -and $r.result.idle) { break }
    Start-Sleep -Seconds 5
}
Write-Host 'editor ready (restart)'

# C2: values survived the restart - on disk (the file) and re-openable
# (asset.get after opening the card).
$cfgPath = Join-Path $Project 'assets\game-config.bsn'
$disk = Get-Content $cfgPath -Raw
$c2disk = ($disk -match '3\.5') -or ($disk -match '2\.5')
Write-Host ("C2 disk value survived restart: " + $c2disk)
$r = Op 'asset.open' @{ path = 'assets/game-config.bsn' }
Start-Sleep -Seconds 2
$r = Op 'asset.get' @{ }
$txt = $r | ConvertTo-Json -Depth 8 -Compress
$c2card = ($txt -match 'move_speed')
Write-Host ("C2 card reopens with value: " + $c2card)

# C7: dirty card + export -> dist carries card value + manifest lists it
Op 'asset.set' @{ field = 'move_speed'; value = '7.5' } | Out-Null
Start-Sleep -Seconds 1
Op 'game.export' @{} | Out-Null
$deadline = (Get-Date).AddSeconds(2400)
$state = ''
while ((Get-Date) -lt $deadline) {
    $f = Brp-Try 'jackdaw/export' @{}
    $state = "$($f.result.state)"
    if ($state -eq 'ready' -or $state -eq 'failed') { break }
    Start-Sleep -Seconds 10
}
Write-Host ("C7 export state: " + $state)
$dist = "C:\Users\linbo.zhang\Projects".Replace('C:\Users\linbo.zhang\Projects', '')
$f = Brp-Try 'jackdaw/export' @{}
$dist = "$($f.result.dist_dir)"
$distCfg = Join-Path $dist 'assets\game-config.bsn'
$c7a = (Test-Path $distCfg) -and ((Get-Content $distCfg -Raw) -match '7\.5')
$manifest = if (Test-Path (Join-Path $dist 'export-manifest.json')) { Get-Content (Join-Path $dist 'export-manifest.json') -Raw } else { '' }
$c7b = $manifest -match 'game-config'
Write-Host ("C7 dist carries card value: " + $c7a + "; manifest lists config: " + $c7b + "; dist=" + $dist)

# C8: moved dist self-contained
$moved = Join-Path $OutDir 'moved8\dist'
New-Item -ItemType Directory -Force -Path (Split-Path $moved) | Out-Null
Remove-Item $moved -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item $dist $moved -Recurse
$exe = Get-ChildItem $moved -Filter *.exe | Select-Object -First 1
$p2 = Start-Process -FilePath $exe.FullName -WorkingDirectory $moved -ArgumentList '--jackdaw-extract-schema' -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutDir 'moved8-schema.txt') -RedirectStandardError (Join-Path $OutDir 'moved8-err.txt')
$p2 | Wait-Process -Timeout 120 -ErrorAction SilentlyContinue
$c8 = ($p2.ExitCode -eq 0)
Write-Host ("C8 moved dist schema flag exit: " + $c8)

# C6: scene SHA across the whole matrix
$shaAfter = (Get-FileHash $sceneFile -Algorithm SHA256).Hash
$c6 = ($shaBefore -eq $shaAfter)
Write-Host ("C6 scene SHA unchanged: " + $c6)

Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Write-Output 'T08_T3_LEGS_DONE'
