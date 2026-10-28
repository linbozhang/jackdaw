# DX12 backend switch - real-machine verification (loop contract: real machine)
# Rounds:
#  1 plain (no WGPU_BACKEND)        -> AdapterInfo backend: Dx12  + screenshot
#  2 WGPU_BACKEND=vulkan            -> AdapterInfo backend: Vulkan (override still honored)
#  3 WGPU_BACKEND=vukan (typo)      -> falls back to Dx12
param(
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15731
)
$ErrorActionPreference = 'Stop'
$OutDir = Join-Path $PSScriptRoot "reports\dx12-verify"
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

. (Join-Path $PSScriptRoot 'qa\brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'qa\screenshot.ps1')

if (Test-Path Env:WGPU_BACKEND) { throw "WGPU_BACKEND is set in this shell; unset it first" }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class JdFind {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
  public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
"@
function Get-JackdawHwnd {
    $found = [IntPtr]::Zero
    $cb = {
        param([IntPtr]$h, [IntPtr]$l)
        $pid2 = 0
        [JdFind]::GetWindowThreadProcessId($h, [ref]$pid2) | Out-Null
        if ($pid2 -eq $script:JdPid -and [JdFind]::IsWindowVisible($h)) {
            $script:Found = $h; return $false
        }
        return $true
    }
    $script:Found = [IntPtr]::Zero
    [JdFind]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
    if ($script:Found -eq [IntPtr]::Zero) { throw "no visible window for pid $script:JdPid" }
    return $script:Found
}

function Run-Round {
    param([string]$Label, [string]$BackendOverride)
    Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
    Start-Sleep -Milliseconds 800
    if ($BackendOverride) { $env:WGPU_BACKEND = $BackendOverride } else { Remove-Item Env:WGPU_BACKEND -ErrorAction SilentlyContinue }
    $err = Join-Path $OutDir "$Label.stderr.log"
    $out = Join-Path $OutDir "$Label.stdout.log"
    $env:JACKDAW_OPEN_PROJECT = $Project
    $env:JACKDAW_REMOTE_PORT = "$Port"
    $proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
        -RedirectStandardError $err -RedirectStandardOutput $out -PassThru
    $script:JdPid = $proc.Id
    try {
        Wait-EditorReady -TimeoutSec 240
        foreach ($try in 1..6) {
            try { Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 30 | Out-Null; break }
            catch { Start-Sleep -Seconds 2 }
        }
        Wait-BrpResult 'jackdaw/wait' @{ frames = 20 } | Out-Null
        Start-Sleep -Seconds 3
        $hwnd = Get-JackdawHwnd
        Save-WindowScreenshot $hwnd (Join-Path $OutDir "$Label.png") | Out-Null
        Write-Host "[$Label] screenshot saved; pid=$($proc.Id)"
    } finally {
        Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
        Remove-Item Env:WGPU_BACKEND -ErrorAction SilentlyContinue
    }
    # adapter line: emitted at renderer init, before BRP is even up
    $adapter = (Select-String -Path $err -Pattern 'AdapterInfo' | Select-Object -First 1).Line
    Write-Host "[$Label] $adapter"
    return $adapter
}

$a1 = Run-Round 'dx12-default' $null
$a2 = Run-Round 'vulkan-override' 'vulkan'
$a3 = Run-Round 'typo-fallback' 'vukan'

$ok1 = $a1 -match 'backend: Dx12'
$ok2 = $a2 -match 'backend: Vulkan'
$ok3 = $a3 -match 'backend: Dx12'
$all = ($ok1 -and $ok2 -and $ok3)
Write-Host "SUMMARY default-dx12=$ok1 vulkan-override=$ok2 typo-fallback-dx12=$ok3"
if ($all) { exit 0 } else { exit 1 }
