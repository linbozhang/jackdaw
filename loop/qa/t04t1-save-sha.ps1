# T04-T1 real-machine regression anchor (manual.md section 7 tools):
# open my-game -> call_operator scene.save -> assert the bytes on disk are
# exactly the document the editor emits: the file's first line is the
# version stamp, and the file minus that line hashes identically to the
# `jackdaw/scene_bsn` emit of the same frame.
param(
    [Parameter(Mandatory = $true)][ValidateSet('launch', 'save', 'wrap')][string]$Phase,
    [int]$Port = 15812,
    [string]$Proj = 'C:\Users\linbo.zhang\Projects\my-game',
    [string]$EditorLog = "$env:TEMP\t04t1-editor.log"
)
$ErrorActionPreference = 'Stop'
$OutDir = 'E:\Project\rust\jackdaw\loop\reports\t04t1-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Brp-Call([string]$Method, $Params, [int]$TimeoutSec = 30) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $raw = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 15
        } catch { Start-Sleep -Milliseconds 250; continue }
        if ($null -ne $raw.error) { return @{ error = $raw.error } }
        if ($null -ne $raw.result) { return @{ result = $raw.result } }
        Start-Sleep -Milliseconds 120
    }
    throw "timeout waiting for $Method $Params"
}
function Wait-Idle([int]$T = 60) { Brp-Call 'jackdaw/wait' @{ until = 'idle' } $T | Out-Null }
function Op([string]$Id, $Params) { Brp-Call 'jackdaw/call_operator' @{ id = $Id; params = $Params } }

switch ($Phase) {
    'launch' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path "$Proj\Cargo.toml")) { throw "no project at $Proj" }
        $sysroot = (& rustc --print sysroot).Trim()
        $tcLib = Join-Path $sysroot 'lib\rustlib\x86_64-pc-windows-msvc\lib'
        $deps = 'E:\Project\rust\jackdaw\target\debug\deps'
        $bat = "$env:TEMP\t04t1-launch.cmd"
        $lines = @(
            "@echo off",
            "set PATH=$deps;$tcLib;%PATH%",
            "set JACKDAW_OPEN_PROJECT=$Proj",
            "set JACKDAW_REMOTE_PORT=$Port",
            "set JACKDAW_SKIP_SETUP_CHECK=1",
            "cd /d E:\Project\rust\jackdaw",
            "start `"t04t1`" /MIN cmd /c `"target\debug\jackdaw.exe > $EditorLog 2>&1`"",
            "exit"
        )
        [System.IO.File]::WriteAllLines($bat, $lines)
        $shell = New-Object -ComObject Shell.Application
        $shell.ShellExecute('open', "`"$bat`"", '', 'open', 0) | Out-Null
        $deadline = (Get-Date).AddSeconds(180); $ok = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 4
            if (netstat -ano | Select-String ":$Port\s.*LISTENING") { $ok = $true; break }
        }
        Write-Output "LISTENING=$ok"
        if (-not $ok) { throw 'editor never listened' }
        Brp-Call 'jackdaw/status' @{} 90 | Out-Null
        Wait-Idle 120
        # Snapshot every .bsn under the project before the save, so the
        # modified one can be identified afterwards and its previous bytes
        # kept as evidence. Persisted to disk so the `save` phase can run
        # in its own process.
        $before = @{}
        Get-ChildItem -Path $Proj -Recurse -Filter *.bsn -File | ForEach-Object {
            $before[$_.FullName] = $_.LastWriteTimeUtc.Ticks
        }
        $before.GetEnumerator() | ForEach-Object { "$($_.Key)|$($_.Value)" } |
            Set-Content -Encoding UTF8 (Join-Path $OutDir 'before-bsn.txt')
        Write-Output ("[bsn files before] " + $before.Count)
        $tree = (Brp-Call 'jackdaw/scene_tree' @{ depth = 3 }).result
        $tree | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $OutDir '00-scene-tree.json')
    }
    'save' {
        # 1. Save the open scene through the operator chain.
        $r = Op 'scene.save' @{}
        Write-Output ("[save] " + ($r | ConvertTo-Json -Depth 8 -Compress))
        Wait-Idle
        Start-Sleep -Milliseconds 800

        # 2. Which .bsn changed (against the `launch` phase's snapshot)?
        $before = @{}
        Get-Content (Join-Path $OutDir 'before-bsn.txt') | ForEach-Object {
            $parts = $_ -split '\|', 2
            if ($parts.Count -eq 2) { $before[$parts[0]] = [long]$parts[1] }
        }
        $changed = @()
        Get-ChildItem -Path $Proj -Recurse -Filter *.bsn -File | ForEach-Object {
            if (-not $before.ContainsKey($_.FullName) -or
                $before[$_.FullName] -ne $_.LastWriteTimeUtc.Ticks) { $changed += $_ }
        }
        if ($changed.Count -lt 1) { throw 'no .bsn changed on disk after scene.save' }
        $file = $changed[0]
        Write-Output ("[saved file] " + $file.FullName + " (" + $file.Length + " bytes, " + $changed.Count + " changed)")
        Copy-Item $file.FullName (Join-Path $OutDir '10-saved-on-disk.bsn') -Force

        # 3. The editor's own emit of the same document.
        $bsn = (Brp-Call 'jackdaw/scene_bsn' @{}).result.bsn
        [System.IO.File]::WriteAllText((Join-Path $OutDir '11-editor-emit.bsn'), $bsn)

        # 4. Byte proof: disk file = stamp line + emit bytes.
        $disk = [System.IO.File]::ReadAllBytes($file.FullName)
        $nl = -1
        for ($i = 0; $i -lt $disk.Length; $i++) { if ($disk[$i] -eq 10) { $nl = $i; break } }
        if ($nl -lt 0) { throw 'saved file has no newline: no stamp line' }
        $stampLine = [System.Text.Encoding]::UTF8.GetString($disk[0..($nl - 1)])
        $stampOk = $stampLine -match '^// jackdaw .+ \| bevy .+$'
        Write-Output ("[stamp line] '$stampLine' ok=$stampOk")

        $bodyBytes = New-Object byte[] ($disk.Length - $nl - 1)
        [Array]::Copy($disk, $nl + 1, $bodyBytes, 0, $bodyBytes.Length)
        $emitBytes = [System.Text.Encoding]::UTF8.GetBytes($bsn)
        $sha1 = [System.Security.Cryptography.SHA256]::Create()
        $h1 = [BitConverter]::ToString($sha1.ComputeHash($bodyBytes)).Replace('-', '')
        $h2 = [BitConverter]::ToString($sha1.ComputeHash($emitBytes)).Replace('-', '')
        Write-Output ("[sha disk body]  $h1 ($($bodyBytes.Length) bytes)")
        Write-Output ("[sha editor emit] $h2 ($($emitBytes.Length) bytes)")
        $verdict = $(if ($stampOk -and $h1 -eq $h2) { 'PASS' } else { 'FAIL' })
        Write-Output "SAVE VERDICT: $verdict (stamp=$stampOk sha_match=$($h1 -eq $h2))"
    }
    'wrap' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Output 'editor stopped'
    }
}
