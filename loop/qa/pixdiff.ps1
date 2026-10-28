# Pixel-diff two PNGs (mean abs diff per channel + % pixels changed beyond tolerance).
param([string]$A, [string]$B, [double]$Tol = 12)
Add-Type -AssemblyName System.Drawing
$ia = [System.Drawing.Bitmap]::FromFile($A)
$ib = [System.Drawing.Bitmap]::FromFile($B)
if ($ia.Width -ne $ib.Width -or $ia.Height -ne $ib.Height) {
    Write-Host ("size mismatch: {0}x{1} vs {2}x{3}" -f $ia.Width, $ia.Height, $ib.Width, $ib.Height)
    $ia.Dispose(); $ib.Dispose(); exit 1
}
$rect = New-Object System.Drawing.Rectangle(0, 0, $ia.Width, $ia.Height)
$fa = $ia.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$fb = $ib.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$bytes = [Math]::Abs($fa.Stride) * $fa.Height
$ba = New-Object byte[] $bytes
$bb = New-Object byte[] $bytes
[System.Runtime.InteropServices.Marshal]::Copy($fa.Scan0, $ba, 0, $bytes)
[System.Runtime.InteropServices.Marshal]::Copy($fb.Scan0, $bb, 0, $bytes)
$ia.UnlockBits($fa); $ib.UnlockBits($fb)
$diff = 0L; $changed = 0L; $pixels = $bytes / 3
for ($i = 0; $i -lt $bytes; $i += 3) {
    $d = [Math]::Abs($ba[$i] - $bb[$i]) + [Math]::Abs($ba[$i + 1] - $bb[$i + 1]) + [Math]::Abs($ba[$i + 2] - $bb[$i + 2])
    $diff += $d
    if ($d -gt $Tol) { $changed++ }
}
Write-Host ("pixels: {0}; changed(>tol {1}): {2} ({3:N2}%); mean channel diff: {4:N3}" -f $pixels, $Tol, $changed, (100.0 * $changed / $pixels), ($diff / $bytes))
$ia.Dispose(); $ib.Dispose()
