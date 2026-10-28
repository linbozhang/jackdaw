# probe 3: grid 8 now (Sensor is on), and a PrintWindow shot to read the
# viewport area for pointer aiming.
$Port = 15703
$OutDir = 'E:\Project\rust\jackdaw\loop\t10t3-live'
function Brp([string]$method, $params) {
    $body = @{ jsonrpc = '2.0'; id = Get-Random; method = $method }
    if ($params) { $body.params = $params }
    Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -TimeoutSec 20 -Body ($body | ConvertTo-Json -Depth 12)
}
function Op([string]$id, $params) { Brp 'jackdaw/call_operator' @{ id = $id; params = $params } }
. 'E:\Project\rust\jackdaw\loop\qa\screenshot.ps1'

$ed = Get-Process jackdaw -ErrorAction SilentlyContinue | Select-Object -First 1
Save-WindowScreenshot $ed.MainWindowHandle (Join-Path $OutDir 't10t3-probe3-window.png') | Out-Null
Write-Host 'window shot saved'

# grid 8: gizmo on -> cyan pixels in the viewport render
Op 'view.toggle_collider_gizmos' @{} | Out-Null
Start-Sleep -Seconds 2
$r = Brp 'jackdaw/screenshot' @{ kind = 'viewport'; path = 't10t3-grid8-sensor-on.png' }
Write-Host ("screenshot resp: {0}" -f ($r | ConvertTo-Json -Depth 4 -Compress))
Start-Sleep -Seconds 2
Add-Type -AssemblyName System.Drawing
$png = Join-Path $OutDir 't10t3-grid8-sensor-on.png'
Write-Host ("file exists: {0}" -f (Test-Path $png))
if (Test-Path $png) {
    $bmp = New-Object System.Drawing.Bitmap $png
    Write-Host ("size: {0}x{1}" -f $bmp.Width, $bmp.Height)
    $cyan = 0; $green = 0
    for ($px = 0; $px -lt $bmp.Width; $px += 2) {
        for ($py = 0; $py -lt $bmp.Height; $py += 2) {
            $c = $bmp.GetPixel($px, $py)
            if ($c.B -gt 200 -and $c.G -gt 150 -and $c.R -lt 90 -and ($c.B - $c.R) -gt 90) { $cyan++ }
            if ($c.G -gt 180 -and $c.R -lt 90 -and $c.B -lt 160) { $green++ }
        }
    }
    $bmp.Dispose()
    Write-Host ("cyan={0} green={1}" -f $cyan, $green)
}
Op 'view.toggle_collider_gizmos' @{} | Out-Null
Start-Sleep -Seconds 2
$r2 = Brp 'jackdaw/screenshot' @{ kind = 'viewport'; path = 't10t3-grid8-sensor-off.png' }
Start-Sleep -Seconds 2
$png2 = Join-Path $OutDir 't10t3-grid8-sensor-off.png'
if (Test-Path $png2) {
    $bmp2 = New-Object System.Drawing.Bitmap $png2
    $cyan2 = 0
    for ($px = 0; $px -lt $bmp2.Width; $px += 2) {
        for ($py = 0; $py -lt $bmp2.Height; $py += 2) {
            $c = $bmp2.GetPixel($px, $py)
            if ($c.B -gt 200 -and $c.G -gt 150 -and $c.R -lt 90 -and ($c.B - $c.R) -gt 90) { $cyan2++ }
        }
    }
    $bmp2.Dispose()
    Write-Host ("cyan(off)={0}" -f $cyan2)
}
