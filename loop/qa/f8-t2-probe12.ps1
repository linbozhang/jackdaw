# Compare BRP window capture vs PrintWindow capture in the 3D-viewport region.
param([int]$Port = 15703)
$ErrorActionPreference = 'Stop'
$Repo = 'E:\Project\rust\jackdaw'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
. (Join-Path $Repo 'loop\qa\input.ps1')
. (Join-Path $Repo 'loop\qa\screenshot.ps1')
Add-Type -AssemblyName System.Drawing
function Region-Stats([string]$Path, [int]$X, [int]$Y, [int]$W, [int]$H) {
    $b = [System.Drawing.Bitmap]::FromFile($Path)
    $w = [Math]::Min($W, $b.Width - $X); $h = [Math]::Min($H, $b.Height - $Y)
    $sum = 0.0; $sum2 = 0.0; $n = 0
    for ($yy = $Y; $yy -lt $Y + $h; $yy += 7) {
        for ($xx = $X; $xx -lt $X + $w; $xx += 7) {
            $c = $b.GetPixel($xx, $yy)
            $v = ($c.R + $c.G + $c.B) / 3.0
            $sum += $v; $sum2 += $v * $v; $n++
        }
    }
    $b.Dispose()
    $mean = $sum / $n
    return ("mean={0:N1} std={1:N1} n={2}" -f $mean, [Math]::Sqrt([Math]::Max(0, $sum2 / $n - $mean * $mean)), $n)
}
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath (Join-Path $Repo 'target\debug\jackdaw.exe') -WorkingDirectory (Join-Path $Repo 'target\debug') -PassThru
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    Start-Sleep -Seconds 2
    $brpShot = 'C:\Users\linbo.zhang\Projects\my-game\screenshots\captest-brp.png'
    Wait-BrpResult 'jackdaw/screenshot' @{ kind = 'window'; path = 'screenshots/captest-brp.png' } -TimeoutSec 30 | Out-Null
    $vpShot = 'C:\Users\linbo.zhang\Projects\my-game\screenshots\captest-vp.png'
    Wait-BrpResult 'jackdaw/screenshot' @{ kind = 'viewport'; path = 'screenshots/captest-vp.png' } -TimeoutSec 30 | Out-Null
    $hwnd = Get-JackdawHwnd
    $pwShot = 'E:\Project\rust\jackdaw\loop\f8-t2\captest-printwindow.png'
    Save-WindowScreenshot $hwnd $pwShot | Out-Null
    foreach ($f in @($brpShot, $vpShot, $pwShot)) {
        $b = [System.Drawing.Bitmap]::FromFile($f)
        Write-Host ("{0}: {1}x{2}" -f (Split-Path -Leaf $f), $b.Width, $b.Height)
        $b.Dispose()
    }
    Write-Host ("BRP window 3D region: {0}" -f (Region-Stats $brpShot 250 100 630 590))
    Write-Host ("PrintWindow 3D region: {0}" -f (Region-Stats $pwShot 250 100 630 590))
} finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
