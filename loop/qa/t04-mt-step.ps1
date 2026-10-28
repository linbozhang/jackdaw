# T04-T3 multitab / damage / matrix driver, one short step per
# invocation (the phase script's own long runs stall under this host's
# background shell; each step here is a single bounded action).
param(
    [Parameter(Mandatory = $true)][ValidateSet(
        'second', 'kill', 'relaunch', 'restore', 'check', 'damage-prep',
        'damage-check', 'm', 'wrap'
    )][string]$Step,
    [int]$Port = 15814,
    [string]$Cfg = "$env:TEMP\t04-final-cfg",
    [string]$Proj = 'C:\Users\linbo.zhang\Projects\my-game'
)
$ErrorActionPreference = 'Stop'
$OutDir = 'E:\Project\rust\jackdaw\loop\reports\t04t3-live'
$State = "$env:TEMP\t04-mt-state.txt"

function Brp-Call([string]$Method, $Params, [int]$TimeoutSec = 25) {
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
function Op([string]$Id, $Params) { Brp-Call 'jackdaw/call_operator' @{ id = $Id; params = $Params } }
function Get-Tree { (Brp-Call 'jackdaw/ui_tree' @{ depth = 24 }).result.nodes }
function Walk-Tree($Nodes, $Fn) {
    foreach ($n in @($Nodes)) {
        & $Fn $n
        if (@($n.children).Count) { Walk-Tree @($n.children) $Fn }
    }
}
function Has-Text([string]$Text) {
    $script:found = $false
    Walk-Tree (Get-Tree) { param($n) if ($n.text -eq $Text) { $script:found = $true } }
    return $script:found
}
function Click-Text([string]$Text) {
    $script:hit = $null
    Walk-Tree (Get-Tree) {
        param($n)
        if ($script:hit) { return }
        foreach ($c in @($n.children)) {
            if ($c.text -eq $Text -and $c.rect -and $c.rect[2] -gt 1) { $script:hit = $n; break }
        }
    }
    if (-not $script:hit) { throw "no clickable node labelled '$Text'" }
    Brp-Call 'jackdaw/ui_click' @{ entity = [uint64]$script:hit.entity }
}
function Find-Journal {
    Get-ChildItem -Path (Join-Path $Cfg 'state\sessions') -Recurse -Filter journal.json -File -ErrorAction SilentlyContinue
}
function Add-Close-Window {
    Add-Type -Namespace Native -Name Win32 -MemberDefinition '
        [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);' -ErrorAction SilentlyContinue
    $p = Get-Process jackdaw -ErrorAction Stop | Select-Object -First 1
    [Native.Win32]::PostMessage($p.MainWindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
}

switch ($Step) {
    'second' {
        Op 'scene.new' @{} | Out-Null
        Start-Sleep -Milliseconds 700
        $r = Op 'entity.add.cube' @{}
        if ($r.error) { throw $r.error.message }
        $deadline = (Get-Date).AddSeconds(30); $j = $null
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 500
            $j = Find-Journal | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($j) {
                $doc = Get-Content $j.FullName -Raw | ConvertFrom-Json
                if ($doc.tabs.Count -ge 2) { break }
            }
        }
        $doc = Get-Content $j.FullName -Raw | ConvertFrom-Json
        Write-Output ("SECOND tabs=" + $doc.tabs.Count + " names=" + (($doc.tabs | ForEach-Object { $_.display_name }) -join ','))
        $pidNow = (Brp-Call 'jackdaw/status' @{}).result.pid
        "$pidNow|$($j.DirectoryName)" | Set-Content -Encoding UTF8 $State
    }
    'kill' {
        $s = (Get-Content $State) -split '\|', 2
        taskkill /F /PID $s[0] | Out-Null
        Start-Sleep -Seconds 2
        Write-Output ("KILLED kept=" + (Test-Path (Join-Path $s[1] 'journal.json')))
    }
    'relaunch' {
        cmd /c "$env:TEMP\t04-final-launch.cmd" | Out-Null
        $deadline = (Get-Date).AddSeconds(150); $ok = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3
            if (netstat -ano | Select-String ":$Port\s.*LISTENING") { $ok = $true; break }
        }
        if (-not $ok) { throw 'editor never relistened' }
        Start-Sleep -Seconds 4
        $rec = (Brp-Call 'jackdaw/recovery' @{ }).result
        Write-Output ("RECOVERY available=" + $rec.available + " tabs=" + $rec.sessions[0].tabs.Count)
        $rec | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $OutDir 'mt-recovery.json')
        $rec.sessions[0].session | Set-Content -Encoding UTF8 "$env:TEMP\t04-mt-session.txt"
    }
    'restore' {
        # Pure-BRP assertions (the ui_tree walk stalls under this host's
        # background shell; tab identity is proven through status.scene).
        $session = Get-Content "$env:TEMP\t04-mt-session.txt"
        $r1 = Op 'recovery.restore' @{ session = $session; tab = 0 }
        if ($r1.error) { throw ("restore 0: " + $r1.error.message) }
        Start-Sleep -Seconds 2
        $left = (Brp-Call 'jackdaw/recovery' @{ }).result
        $still = @($left.sessions | Where-Object { $_.session -eq $session })
        $leftCount = if ($still) { $still[0].tabs.Count } else { 0 }
        Write-Output ("RESTORE-1 left=" + $leftCount)
        if ($leftCount -lt 1) { throw 'the first restore did not leave the second entry' }
        $r2 = Op 'recovery.restore' @{ session = $session; tab = 0 }
        if ($r2.error) { throw ("restore 2: " + $r2.error.message) }
        Start-Sleep -Seconds 3
        $after = (Brp-Call 'jackdaw/recovery' @{ }).result
        $gone = @($after.sessions | Where-Object { $_.session -eq $session }).Count -eq 0
        $st = (Brp-Call 'jackdaw/status' @{}).result
        Write-Output ("RESTORE-2 session-spent=$gone active-scene=" + $st.scene + " dirty=" + $st.dirty)
        # The second restore is the untitled tab: the active scene is not
        # a file. Switch to tab 0 and the named tab comes forward.
        $sw = Op 'scene.switch' @{ tab = 0 }
        Start-Sleep -Seconds 2
        $st0 = (Brp-Call 'jackdaw/status' @{}).result
        Write-Output ("TAB0 scene=" + $st0.scene + " dirty=" + $st0.dirty)
        if ($st0.scene -notlike '*scene.bsn') { throw 'the named tab did not survive beside the untitled one' }
        Write-Output 'MULTITAB VERDICT: PASS (two entries restored independently)'
    }
    'damage-prep' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force
        if (Test-Path $Cfg) { Remove-Item $Cfg -Recurse -Force }
        cmd /c "$env:TEMP\t04-final-launch.cmd" | Out-Null
        $deadline = (Get-Date).AddSeconds(150); $ok = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3
            if (netstat -ano | Select-String ":$Port\s.*LISTENING") { $ok = $true; break }
        }
        if (-not $ok) { throw 'editor never listened' }
        Start-Sleep -Seconds 3
        $r = Op 'entity.add.cube' @{}
        if ($r.error) { throw $r.error.message }
        $deadline = (Get-Date).AddSeconds(30); $j = $null
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 500
            $j = Find-Journal | Select-Object -First 1
            if ($j) { break }
        }
        if (-not $j) { throw 'journal never landed' }
        $pidNow = (Brp-Call 'jackdaw/status' @{}).result.pid
        taskkill /F /PID $pidNow | Out-Null
        Start-Sleep -Seconds 2
        $bytes = [System.IO.File]::ReadAllBytes($j.FullName)
        [System.IO.File]::WriteAllBytes($j.FullName, $bytes[0..([Math]::Max(1, [int]($bytes.Length / 2)) - 1)])
        Write-Output ("DAMAGE-PREP " + $j.FullName + " now " + (Get-Item $j.FullName).Length + " bytes")
        "$($j.DirectoryName)" | Set-Content -Encoding UTF8 "$env:TEMP\t04-damage-dir.txt"
    }
    'damage-check' {
        cmd /c "$env:TEMP\t04-final-launch.cmd" | Out-Null
        $deadline = (Get-Date).AddSeconds(150); $ok = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3
            if (netstat -ano | Select-String ":$Port\s.*LISTENING") { $ok = $true; break }
        }
        if (-not $ok) { throw 'editor never relistened after damage' }
        Start-Sleep -Seconds 4
        $rec = (Brp-Call 'jackdaw/recovery' @{ }).result
        $dir = Get-Content "$env:TEMP\t04-damage-dir.txt"
        $damaged = @($rec.sessions | Where-Object { $_.damaged })
        Write-Output ("DAMAGE available=" + $rec.available + " damaged-sessions=" + $damaged.Count + " file-kept=" + (Test-Path (Join-Path $dir 'journal.json')))
        if ($damaged.Count -lt 1) { throw 'the damaged session is not reported' }
        if (-not (Test-Path (Join-Path $dir 'journal.json'))) { throw 'damaged journal was deleted' }
        Write-Output 'DAMAGE VERDICT: PASS (skipped, kept, no crash)'
    }
    'm' {
        # One N9 cell per invocation, chosen by a -Cell value appended via
        # $env:T04_CELL (1..11).
        $cell = $env:T04_CELL
        switch ([int]$cell) {
            { $_ -in 1..3 } {
                $scene = "$Proj\assets\scene.bsn"
                $sha = (Get-FileHash $scene).Hash
                $label = @('Save', 'Discard', 'Cancel')[[int]$cell - 1]
                # The close needs a second tab to close into.
                Op 'scene.new' @{} | Out-Null; Start-Sleep -Milliseconds 700
                Op 'scene.switch' @{ tab = 0 } | Out-Null; Start-Sleep -Milliseconds 700
                Op 'entity.add.cube' @{} | Out-Null; Start-Sleep -Milliseconds 700
                Op 'scene.close' @{} | Out-Null; Start-Sleep -Milliseconds 700
                if (-not (Has-Text 'Unsaved Changes')) { throw "[$label] close dialog not up" }
                Click-Text $label | Out-Null
                Start-Sleep -Seconds 1
                $st = (Brp-Call 'jackdaw/status' @{}).result
                $shaNow = (Get-FileHash $scene).Hash
                Write-Output ("[$cell $label] dirty=" + $st.dirty + " file-changed=" + ($shaNow -ne $sha) + " scene-set=" + ($null -ne $st.scene))
                if ($label -eq 'Save' -and $shaNow -eq $sha) { throw 'save did not write' }
                if ($label -eq 'Discard' -and $shaNow -ne $sha) { throw 'discard wrote the file' }
                if ($label -eq 'Cancel' -and -not $st.dirty) { throw 'cancel lost the tab' }
            }
            4 {
                Op 'scene.new' @{} | Out-Null; Start-Sleep -Milliseconds 700
                Op 'entity.add.cube' @{} | Out-Null; Start-Sleep -Milliseconds 700
                Op 'scene.close' @{} | Out-Null; Start-Sleep -Milliseconds 700
                if (-not (Has-Text 'Unsaved Changes')) { throw '[4] close dialog not up' }
                Click-Text 'Save' | Out-Null
                Start-Sleep -Seconds 2
                $st = (Brp-Call 'jackdaw/status' @{}).result
                Write-Output ("[4 untitled Save] dirty=" + $st.dirty + ' (tab kept, not discarded)')
                if (-not $st.dirty) { throw 'untitled Save discarded the tab' }
                # Drop the native Save As so later steps start clean.
                Start-Sleep -Seconds 1
                Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { $_.CloseMainWindow() | Out-Null }
                Start-Sleep -Seconds 2
            }
            5 {
                Op 'entity.add.cube' @{} | Out-Null; Start-Sleep -Milliseconds 700
                Op 'scene.close' @{} | Out-Null; Start-Sleep -Milliseconds 700
                if (-not (Has-Text 'Unsaved Changes')) { throw '[5] close dialog not up' }
                Click-Text 'Cancel' | Out-Null
                Start-Sleep -Seconds 1
                $st = (Brp-Call 'jackdaw/status' @{}).result
                Write-Output ("[5 untitled Cancel] dirty=" + $st.dirty)
                if (-not $st.dirty) { throw 'cancel closed the untitled tab' }
            }
            { $_ -in 6..8 } {
                $label = @('Save All', 'Discard All', 'Cancel')[[int]$cell - 6]
                Op 'entity.add.cube' @{} | Out-Null; Start-Sleep -Milliseconds 700
                Op 'scene.new' @{} | Out-Null; Start-Sleep -Milliseconds 700
                Op 'entity.add.cube' @{} | Out-Null; Start-Sleep -Milliseconds 700
                Add-Close-Window
                Start-Sleep -Seconds 2
                if (-not (Has-Text 'Unsaved')) { throw "[$cell $label] quit dialog not up on window close" }
                Click-Text $label | Out-Null
                Start-Sleep -Seconds 4
                $alive = [bool](Get-Process jackdaw -ErrorAction SilentlyContinue)
                Write-Output ("[$cell $label] editor-alive=$alive")
                if ($label -eq 'Cancel' -and -not $alive) { throw 'editor exited on Cancel' }
                if ($label -ne 'Cancel' -and $alive) { throw "editor did not exit on $label" }
            }
            11 {
                Op 'entity.add.cube' @{} | Out-Null; Start-Sleep -Milliseconds 700
                Add-Close-Window
                Start-Sleep -Seconds 2
                $up = Has-Text 'Unsaved'
                $alive = [bool](Get-Process jackdaw -ErrorAction SilentlyContinue)
                Write-Output ("[11 X-click] dialog=$up alive=$alive")
                if (-not $up -or -not $alive) { throw 'X-click was not intercepted by the quit dialog' }
                Click-Text 'Discard All' | Out-Null
                Start-Sleep -Seconds 3
            }
            { $_ -in 9..10 } {
                $confirm = ([int]$cell -eq 9)
                Op 'entity.add.cube' @{} | Out-Null; Start-Sleep -Milliseconds 700
                Op 'app.go_home' @{} | Out-Null
                Start-Sleep -Seconds 2
                if (-not (Has-Text 'Unsaved')) { throw "[$cell] leave dialog not up" }
                $label = if ($confirm) { 'Discard All' } else { 'Cancel' }
                Click-Text $label | Out-Null
                Start-Sleep -Seconds 3
                $st = (Brp-Call 'jackdaw/status' @{}).result
                $left = ($null -eq $st.project)
                Write-Output ("[$cell leave $label] project-left=$left dirty=" + $st.dirty)
                if ($confirm -and -not $left) { throw 'confirm did not leave the project' }
                if (-not $confirm -and $left) { throw 'cancel left the project anyway' }
            }
        }
        Write-Output "CELL $cell VERDICT: PASS"
    }
    'wrap' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Output 'editor stopped'
    }
}
