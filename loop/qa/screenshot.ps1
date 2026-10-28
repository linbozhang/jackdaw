# PrintWindow 全窗口截图（R4 手册 §5.5 第二通道）
# 用法: . E:\Project\rust\jackdaw\loop\qa\screenshot.ps1
#   Save-WindowScreenshot $hwnd 'C:\temp\shot.png'
# PW_RENDERFULLCONTENT(2)：DirectComposition/分层内容也能截到；无标题栏窗口适用。
# 首选仍是 BRP jackdaw/screenshot kind=viewport（所见即所渲染，不受遮挡/最小化影响）；
# 本脚本用于比对整体 UI（工具栏高亮、modal 提示等）。

Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class JdShot {
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int L; public int T; public int R; public int B; }
}
"@

function Save-WindowScreenshot {
    param(
        [Parameter(Mandatory = $true)][IntPtr]$Hwnd,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $r = New-Object JdShot+RECT
    [JdShot]::GetWindowRect($Hwnd, [ref]$r) | Out-Null
    $w = $r.R - $r.L; $h = $r.B - $r.T
    if ($w -le 0 -or $h -le 0) { throw "bad window rect ${w}x${h}" }
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    $ok = [JdShot]::PrintWindow($Hwnd, $hdc, 2)
    $g.ReleaseHdc($hdc); $g.Dispose()
    if (-not $ok) { $bmp.Dispose(); throw "PrintWindow failed" }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return $Path
}
