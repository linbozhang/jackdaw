# T04-T2 kill chain, step form: each step is one short BRP exchange with
# visible output, for driving the chain manually when the phase script's
# long `wait until idle` stalls on the project's background pre-build.
param(
    [Parameter(Mandatory = $true)][ValidateSet('dirty', 'check', 'kill', 'relaunch', 'wrap')][string]$Step,
    [int]$Port = 15813,
    [string]$Cfg = "$env:TEMP\t04-kill-cfg"
)
$ErrorActionPreference = 'Stop'
$OutDir = 'E:\Project\rust\jackdaw\loop\reports\t04t2-kill'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$State = "$env:TEMP\t04-kill-state.txt"

function Brp-Call([string]$Method, $Params, [int]$TimeoutSec = 20) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $raw = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 10
        } catch { Start-Sleep -Milliseconds 250; continue }
        if ($null -ne $raw.error) { return @{ error = $raw.error } }
        if ($null -ne $raw.result) { return @{ result = $raw.result } }
        Start-Sleep -Milliseconds 120
    }
    throw "timeout waiting for $Method $Params"
}
function Find-Journal {
    Get-ChildItem -Path (Join-Path $Cfg 'state\sessions') -Recurse -Filter journal.json -File -ErrorAction SilentlyContinue
}

switch ($Step) {
    'dirty' {
        $r = Brp-Call 'jackdaw/call_operator' @{ id = 'entity.add.cube'; params = @{} }
        Write-Output ("[add cube] " + ($r | ConvertTo-Json -Depth 6 -Compress))
        Start-Sleep -Milliseconds 500
        $s = (Brp-Call 'jackdaw/status' @{}).result
        Write-Output ("[dirty] " + $s.dirty + " [pid] " + $s.pid)
        if (-not $s.dirty) { throw 'the edit did not light the tab' }
        $deadline = (Get-Date).AddSeconds(30); $journal = $null
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 500
            $journal = Find-Journal | Select-Object -First 1
            if ($journal) { break }
        }
        if (-not $journal) { throw 'journal.json never landed' }
        $age = [math]::Round(((Get-Date) - $journal.LastWriteTime).TotalSeconds, 1)
        Write-Output ("[journal] " + $journal.FullName + " fresh=${age}s bytes=" + $journal.Length)
        Copy-Item $journal.FullName (Join-Path $OutDir '10-pre-kill-journal.json') -Force
        "$($s.pid)|$($journal.DirectoryName)" | Set-Content -Encoding UTF8 $State
        Write-Output 'DIRTY VERDICT: PASS'
    }
    'check' {
        $parts = (Get-Content $State) -split '\|', 2
        Write-Output ("[state] pid=" + $parts[0] + " dir=" + $parts[1])
        $j = Get-Content (Join-Path $parts[1] 'journal.json') -Raw
        $tabs = ($j | ConvertFrom-Json).tabs
        Write-Output ("[journal tabs] " + $tabs.Count + " -> " + (($tabs | ForEach-Object { "$($_.kind):$($_.display_name) entities=$($_.entity_count)" }) -join '; '))
    }
    'kill' {
        $parts = (Get-Content $State) -split '\|', 2
        taskkill /F /PID $parts[0] | Out-Null
        Start-Sleep -Seconds 2
        $journal = Join-Path $parts[1] 'journal.json'
        if (-not (Test-Path $journal)) { throw "kill left no journal behind: $journal" }
        Write-Output ("[after kill] $journal survived (" + (Get-Item $journal).Length + " bytes)")
        Copy-Item $journal (Join-Path $OutDir '11-post-kill-journal.json') -Force
        Write-Output 'KILL VERDICT: PASS (session directory survived the hard kill)'
    }
    'relaunch' {
        $parts = (Get-Content $State) -split '\|', 2
        $deadDir = $parts[1]
        $sysroot = (& rustc --print sysroot).Trim()
        $tcLib = Join-Path $sysroot 'lib\rustlib\x86_64-pc-windows-msvc\lib'
        $deps = 'E:\Project\rust\jackdaw\target\debug\deps'
        $bat = "$env:TEMP\t04-kill-launch.cmd"
        cmd /c $bat | Out-Null
        $deadline = (Get-Date).AddSeconds(120); $ok = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3
            if (netstat -ano | Select-String ":$Port\s.*LISTENING") { $ok = $true; break }
        }
        if (-not $ok) { throw 'editor never relistened' }
        Start-Sleep -Seconds 5
        $s = (Brp-Call 'jackdaw/status' @{}).result
        Write-Output ("[relaunched pid] " + $s.pid)
        if (-not (Test-Path (Join-Path $deadDir 'journal.json'))) { throw 'the dead session vanished on relaunch' }
        $root = Join-Path $Cfg 'state\sessions'
        $dirs = Get-ChildItem $root -Directory | ForEach-Object { $_.Parent.Parent.Name + '/' + $_.Parent.Name + '/' + $_.Name }
        Get-ChildItem $root -Directory | ForEach-Object {
            Write-Output ("[session] " + $_.Name + (($_ | Get-ChildItem) -replace '^', '  '))
        }
        $sessionDirs = Get-ChildItem $root -Directory
        $grandChild = $sessionDirs | ForEach-Object { Get-ChildItem $_ -Directory }
        Write-Output ("[session dirs] " + (($grandChild | ForEach-Object { $_.Name }) -join ', '))
        if ($grandChild.Count -lt 2) { throw 'expected the dead session and the new live session side by side' }
        Write-Output 'RELAUNCH VERDICT: PASS (dead session residue is the recovery signal)'
    }
    'wrap' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Output "editor stopped; isolated config kept at $Cfg as evidence"
    }
}
