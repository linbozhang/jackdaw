# dump the rig entity's raw JSON from the game snapshot
$proj = 'H:\workspace_AI\t11-live\t11t1-game'
$exe = Join-Path $proj 'target\debug\t11t1-game.exe'
$gameAssets = Join-Path $proj 'target\debug\assets'
Copy-Item (Join-Path $proj 'assets\t11t2-place.bsn') (Join-Path $gameAssets 'scene.bsn') -Force
Get-Process t11t1-game -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
function GBrp([string]$m, $p) {
    try {
        $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $m }
        if ($p) { $body.params = $p }
        return Invoke-RestMethod -Uri 'http://127.0.0.1:15702/' -Method Post -ContentType 'application/json' -TimeoutSec 20 -Body ($body | ConvertTo-Json -Depth 10)
    } catch { return $null }
}
$env:PATH = "$proj\target\debug\deps;$env:PATH"
cmd /c "start /B /D `"$proj`" cmd /c `"`"$exe`" > H:\workspace_AI\t11-live\diag2.log 2>&1`""
for ($i = 0; $i -lt 80; $i++) { Start-Sleep -Milliseconds 250; if (GBrp 'jackdaw/scene_snapshot' @{}) { break } }
Start-Sleep -Seconds 4
$s = (GBrp 'jackdaw/scene_snapshot' @{}).result
foreach ($e in @($s)) {
    $comps = @()
    $props = if ($e.components -is [System.Management.Automation.PSObject]) { $e.components.PSObject.Properties } else { $e.components }
    foreach ($p in $props) { $comps += ("$($p.Name)" -replace '^.*::', '') }
    if ($comps -contains 'CameraRig') {
        Write-Host ("RIG ENTITY {0}" -f $e.entity)
        foreach ($p in $props) {
            if ("$($p.Name)" -like '*Transform') {
                Write-Host ("  {0} = {1}" -f ($p.Name -replace '^.*::', ''), ($p.Value | ConvertTo-Json -Depth 6 -Compress))
            }
        }
    }
}
Get-Process t11t1-game -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host 'DUMP_DONE'
