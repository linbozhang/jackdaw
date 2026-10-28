# OS 级输入注入（SendInput）+ 窗口定位（R4 手册 §5.4）
# 用法: . E:\Project\rust\jackdaw\loop\qa\input.ps1
#   $hwnd = Get-JackdawHwnd; Focus-Jackdaw $hwnd
#   Set-CursorToWindowCenter $hwnd 0.5 0.5   # 返回屏幕物理像素坐标
#   Send-RmbDown; Start-Sleep -Milliseconds 500; 1..20 | % { Send-MoveRel 15 0; Start-Sleep -Milliseconds 16 }; Send-RmbUp
#   Send-Esc; Send-W -Ms 400   # W 按住 400ms（fly 位移回归用）
#
# 坐标系：SetCursorPos/GetWindowRect/SendInput 相对位移均为物理屏幕像素，绕开 DPI 缩放差异。
# 能力边界：SendInput 是 OS 级注入，产生真实 WM_INPUT raw delta（可驱动 NavLook）；
# 这正是 R1 真机验证必须走本脚本而非 BRP input.pointer 的原因（后者只有 CursorMoved）。

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class JdInput {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int L; public int T; public int R; public int B; }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT { public uint type; public MK u; }

    [StructLayout(LayoutKind.Explicit)]
    public struct MK {
        [FieldOffset(0)] public MOUSE mo;
        [FieldOffset(0)] public KEY k;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSE { public int dx; public int dy; public uint data; public uint flags; public uint time; public IntPtr extra; }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEY { public ushort vk; public ushort scan; public uint flags; public uint time; public IntPtr extra; }

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint n, INPUT[] i, int size);

    const uint MOUSEEVENTF_MOVE = 0x0001;
    const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    const uint MOUSEEVENTF_LEFTUP = 0x0004;
    const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    const uint MOUSEEVENTF_MIDDLEUP = 0x0040;
    const uint MOUSEEVENTF_WHEEL = 0x0800;
    const uint KEYEVENTF_KEYUP = 0x0002;

    static INPUT NewMouse(uint flags) {
        MOUSE m = new MOUSE(); m.flags = flags;
        INPUT i = new INPUT(); i.type = 0; i.u.mo = m; return i;
    }

    static INPUT NewKey(ushort vk, uint flags) {
        KEY k = new KEY(); k.vk = vk; k.flags = flags;
        INPUT i = new INPUT(); i.type = 1; i.u.k = k; return i;
    }

    static void Send(INPUT i) {
        uint sent = SendInput(1, new INPUT[] { i }, Marshal.SizeOf(typeof(INPUT)));
        if (sent != 1) throw new Exception("SendInput failed: " + Marshal.GetLastWin32Error());
    }

    public static void RmbDown() { Send(NewMouse(MOUSEEVENTF_RIGHTDOWN)); }
    public static void RmbUp() { Send(NewMouse(MOUSEEVENTF_RIGHTUP)); }
    public static void LmbDown() { Send(NewMouse(MOUSEEVENTF_LEFTDOWN)); }
    public static void LmbUp() { Send(NewMouse(MOUSEEVENTF_LEFTUP)); }
    public static void MmbDown() { Send(NewMouse(MOUSEEVENTF_MIDDLEDOWN)); }
    public static void MmbUp() { Send(NewMouse(MOUSEEVENTF_MIDDLEUP)); }
    public static void Wheel(int ticks) {
        INPUT i = NewMouse(MOUSEEVENTF_WHEEL); i.u.mo.data = unchecked((uint)ticks); Send(i);
    }
    public static void MoveRel(int dx, int dy) {
        INPUT i = NewMouse(MOUSEEVENTF_MOVE); i.u.mo.dx = dx; i.u.mo.dy = dy; Send(i);
    }
    public static void KeyDown(ushort vk) { Send(NewKey(vk, 0)); }
    public static void KeyUp(ushort vk) { Send(NewKey(vk, KEYEVENTF_KEYUP)); }
}
"@

# 常用虚拟键码
$script:Vk = @{
    Esc = 0x1B; W = 0x57; A = 0x41; S = 0x53; D = 0x44; Q = 0x51; E = 0x45
    Enter = 0x0D; Ctrl = 0x11; Shift = 0x10
}

# jackdaw 主窗口句柄（窗口无标题栏文本，按进程找）。
function Get-JackdawHwnd {
    param([int]$ProcId = 0)
    $p = if ($ProcId -gt 0) { Get-Process -Id $ProcId -ErrorAction SilentlyContinue }
         else { Get-Process jackdaw -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1 }
    if (-not $p -or $p.MainWindowHandle -eq 0) { throw 'jackdaw window not found' }
    return $p.MainWindowHandle
}

function Focus-Jackdaw {
    param([Parameter(Mandatory = $true)][IntPtr]$Hwnd)
    [JdInput]::SetForegroundWindow($Hwnd) | Out-Null
    Start-Sleep -Milliseconds 300
}

# 光标放到窗口内一点（默认中心）。$XFactor/$YFactor 为窗口宽高比例（0~1）。
# 返回放置后的屏幕物理坐标。
function Set-CursorToWindowPoint {
    param(
        [Parameter(Mandatory = $true)][IntPtr]$Hwnd,
        [double]$XFactor = 0.5,
        [double]$YFactor = 0.5
    )
    $r = New-Object JdInput+RECT
    [JdInput]::GetWindowRect($Hwnd, [ref]$r) | Out-Null
    $x = [int]($r.L + ($r.R - $r.L) * $XFactor)
    $y = [int]($r.T + ($r.B - $r.T) * $YFactor)
    [JdInput]::SetCursorPos($x, $y) | Out-Null
    return @{ X = $x; Y = $y; Rect = $r }
}

function Send-Esc { [JdInput]::KeyDown($script:Vk.Esc); Start-Sleep -Milliseconds 30; [JdInput]::KeyUp($script:Vk.Esc) }

# 按住某键一段时间（默认 400ms）后松开。用于 fly 位移（WASD/QE）注入。
function Send-KeyHold {
    param([Parameter(Mandatory = $true)][string]$Key, [int]$Ms = 400)
    $vk = $script:Vk[$Key]
    if (-not $vk) { throw "unknown key '$Key' (add it to `$script:Vk)" }
    [JdInput]::KeyDown([uint16]$vk)
    Start-Sleep -Milliseconds $Ms
    [JdInput]::KeyUp([uint16]$vk)
}

function Send-RmbDown { [JdInput]::RmbDown() }
function Send-RmbUp { [JdInput]::RmbUp() }
function Send-MmbDown { [JdInput]::MmbDown() }
function Send-MmbUp { [JdInput]::MmbUp() }
# 滚轮注入：$Ticks 为滚轮格数，正=向前滚（zoom in）。
function Send-Wheel {
    param([Parameter(Mandatory = $true)][int]$Ticks)
    [JdInput]::Wheel($Ticks)
}
function Send-MoveRel {
    param([Parameter(Mandatory = $true)][int]$Dx, [Parameter(Mandatory = $true)][int]$Dy)
    [JdInput]::MoveRel($Dx, $Dy)
}
