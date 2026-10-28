# Probe the shadow-map resource read shape.
param([int]$Port = 15703)
$ErrorActionPreference = 'Stop'
$Repo = 'E:\Project\rust\jackdaw'
. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
function Raw([string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 12 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $w = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body $bytes -UseBasicParsing -TimeoutSec 30
    return [System.Text.Encoding]::UTF8.GetString($w.RawContentStream.ToArray()) | ConvertFrom-Json
}
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = 'C:\Users\linbo.zhang\Projects\my-game'; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath (Join-Path $Repo 'target\debug\jackdaw.exe') -WorkingDirectory (Join-Path $Repo 'target\debug') -PassThru
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    foreach ($p in 'bevy_light::directional_light::DirectionalLightShadowMap',
                   'bevy_light::point_light::PointLightShadowMap') {
        Write-Host "--- $p"
        $r = Raw 'world.get_resources' @{ resource = $p }
        $r | ConvertTo-Json -Depth 8 | Write-Host
    }
    # registry.schema search for shadow map type paths
    $schema = Raw 'registry.schema' @{ }
    $json = $schema | ConvertTo-Json -Depth 6 -Compress
    $m = [regex]::Matches($json, '[a-z_:]*ShadowMap[a-zA-Z_:]*')
    Write-Host ("schema hits: " + (($m | ForEach-Object { $_.Value } | Sort-Object -Unique) -join ' | '))
} finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
