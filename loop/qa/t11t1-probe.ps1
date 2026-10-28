# Probe: dump the live game's snapshot, inspect wall/rig/player entities.
param(
    [string]$Project = 'H:\workspace_AI\t11-live\t11t1-game',
    [int]$GamePort = 15702
)
$OutDir = 'E:\Project\rust\jackdaw\loop\t11t1-live'
$Exe = Join-Path $Project 'target\debug\t11t1-game.exe'
function Brp([string]$method, $params, [int]$retries = 3) {
    for ($i = 0; $i -lt $retries; $i++) {
        try {
            $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
            if ($params) { $body.params = $params }
            return Invoke-RestMethod -Uri "http://127.0.0.1:$GamePort/" -Method Post `
                -ContentType 'application/json' -TimeoutSec 30 -Body ($body | ConvertTo-Json -Depth 10)
        } catch { Start-Sleep -Milliseconds (300 * ($i + 1)) }
    }
    return $null
}
Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$deps = Join-Path $Project 'target\debug\deps'
$env:PATH = "$deps;$env:PATH"
cmd /c "start /B /D `"$Project`" cmd /c `"`"$Exe`" > `"$OutDir\probe-stdout.log`" 2>`&1`""
$ready = $false
for ($i = 0; $i -lt 80; $i++) {
    Start-Sleep -Milliseconds 250
    if (Brp 'jackdaw/status' @{} 1) { $ready = $true; break }
    if (-not (Get-Process t11t1-game -ErrorAction SilentlyContinue)) { Write-Host 'BOOT_FAIL'; exit 1 }
}
if (-not $ready) { Write-Host 'BOOT_FAIL'; exit 1 }
Start-Sleep -Seconds 3

$snap = (Brp 'jackdaw/scene_snapshot' @{}).result
$snap | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $OutDir 'probe-snap.json')
Write-Host ("ENTITIES: {0}" -f @($snap).Count)
$i = 0
foreach ($e in @($snap)) {
    $names = ''
    $t = $null
    $props = if ($e.components -is [System.Management.Automation.PSObject]) { $e.components.PSObject.Properties } else { $e.components }
    $comps = @()
    foreach ($prop in $props) { $comps += $prop.Name }
    if ($e.PSObject.Properties['name']) { $names = $e.name }
    Write-Host ("[{0}] {1} :: {2}" -f $i, $names, ($comps -join ' | '))
    $i++
}
# Inspect specific entities through bevy_remote for the full component set.
$wall = Brp 'world.query' @{ data = @{}; filter = @{ with = 'avian3d::collision::collider::Collider' } }
Get-Process t11t1-game -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Write-Host 'PROBE_DONE'
