# T08 lock-fix QA: the must-blow path, independently re-run.
#   fresh `jd new` (rebuilt jd, lock snapshot embedded) -> verify the
#   seeded lock survived the resolve prune (new entry added, bevy stays
#   at the workspace rev) -> editor prebuild over JACKDAW_OPEN_PROJECT:
#   IDLE + schema.json (with GameConfig) + zero errors, first try.
$ErrorActionPreference = 'Stop'

$Repo  = 'E:\Project\rust\jackdaw'
$Jd    = Join-Path $Repo 'target\debug\jd.exe'
$Exe   = Join-Path $Repo 'target\debug\jackdaw.exe'
$FixDir = Join-Path $Repo 'loop\qa-fixture'
$Proj  = Join-Path $FixDir 't08lf-qa'
$Port  = 15703
$OutDir = Join-Path $Repo 'loop\t08-t2-qa-live'

function Brp-Try([string]$method, $params, [int]$retries = 6) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = (Get-Random); method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 8)
        } catch { Start-Sleep -Milliseconds (500 * ($i + 1)) }
    }
    return $null
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
if (Test-Path $Proj) { Remove-Item -Recurse -Force $Proj }
Start-Sleep -Milliseconds 500

# 1. Fresh scaffold with the rebuilt jd.
& $Jd new t08lf-qa --path $FixDir --no-git --no-modules 2>&1 | Write-Host
if (-not (Test-Path (Join-Path $Proj 'Cargo.toml'))) { throw 'scaffold produced nothing' }

# 2. The lock after jd new's own resolve step: seeded snapshot pruned,
#    not re-resolved.
$lock = Get-Content (Join-Path $Proj 'Cargo.lock') -Raw
$hasEntry = $lock -match 'name = "t08lf-qa"'
$hasBevyRev = $lock -match 'c9c397ba'
$hasBadRev = $lock -match 'fe544043'
Write-Host ("LOCK: own-entry=$hasEntry bevy-at-workspace-rev=$hasBevyRev drifted-rev-present=$hasBadRev")
if (-not $hasEntry -or -not $hasBevyRev -or $hasBadRev) { throw 'the seeded lock drifted or was replaced' }

# 3. Editor prebuild over the fresh project - the must-blow path.
$env:JACKDAW_OPEN_PROJECT = $Proj
$env:JACKDAW_REMOTE_PORT  = "$Port"
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
    -RedirectStandardOutput (Join-Path $OutDir 'lfqa-stdout.log') `
    -RedirectStandardError (Join-Path $OutDir 'lfqa-stderr.log') -PassThru
$proc.Id | Set-Content (Join-Path $OutDir 'lfqa.pid')
$ready = $false
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    if (Brp-Try 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw 'editor died while booting' }
}
if (-not $ready) { throw 'editor BRP never answered' }
Write-Host 'BRP up; waiting idle (first prebuild)...'
$idle = $false
$deadline = (Get-Date).AddSeconds(1800)
while ((Get-Date) -lt $deadline) {
    $r = Brp-Try 'jackdaw/wait' @{ until = 'idle' } 1
    if ($r -and $r.result -and $r.result.idle) { $idle = $true; break }
    Start-Sleep -Seconds 3
}
Write-Host ("IDLE reached: " + $idle)
if (-not $idle) { throw 'prebuild never went idle' }

$schema = Join-Path $Proj '.jackdaw\schema.json'
$schemaOk = $false
if (Test-Path $schema) {
    $s = Get-Content $schema -Raw
    $schemaOk = ($s -match 'GameConfig')
}
$alive = [bool](Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
$errLines = 0
$errLog = Join-Path $OutDir 'lfqa-stderr.log'
if (Test-Path $errLog) {
    $errLines = (Select-String -Path $errLog -Pattern '^ERROR' -ErrorAction SilentlyContinue | Measure-Object).Count
}
Write-Host ("PREBUILD-SCHEMA(GameConfig): $schemaOk  EDITOR-ALIVE: $alive  STDERR-ERROR-LINES: $errLines")

# 4. Game-config end probe: the schema bucket answers over BRP too.
$kinds = Brp-Try 'jackdaw/assets' @{} 2
$gc = if ($kinds) { "$($kinds.result)" -match 'GameConfig' } else { $false }
Write-Host ("assets-face has GameConfig: $gc")

Stop-Process -Id $proc.Id -Force
Write-Output 'T08_LF_QA_DONE'
