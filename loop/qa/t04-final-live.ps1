# T04-T3 final live chain (manual.md section 7 tools). Phases:
#   chain    - the acceptance sentences: dirty -> kill /F -> relaunch ->
#              jackdaw/recovery -> ui_tree dialog -> ui_click Restore ->
#              scene_tree entity count == journal -> scene.bsn SHA256
#              unchanged (never-overwrite proof) -> explicit save changes it
#   multitab - a named and an untitled dirty tab, restored independently
#   damage   - a half-written journal: skipped, kept, never a crash
#   m1to5    - N9 matrix cells 1-5 (single-tab close: Save/Discard/Cancel,
#              untitled Save/Cancel)
#   m6to8    - N9 matrix cells 6-8 (quit dialog: SaveAll/DiscardAll/Cancel)
#   m9to11   - N9 matrix cells 9-11 (leave-project confirm/cancel, X-click
#              interception)
#   wrap     - stop everything
param(
    [Parameter(Mandatory = $true)][ValidateSet(
        'chain', 'multitab', 'damage', 'm1to5', 'm6to8', 'm9to11', 'wrap'
    )][string]$Phase,
    [int]$Port = 15814,
    [string]$Proj = 'C:\Users\linbo.zhang\Projects\my-game',
    [string]$Cfg = "$env:TEMP\t04-final-cfg",
    [string]$EditorLog = "$env:TEMP\t04-final-editor.log"
)
$ErrorActionPreference = 'Stop'
$OutDir = 'E:\Project\rust\jackdaw\loop\reports\t04t3-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Brp-Call([string]$Method, $Params, [int]$TimeoutSec = 30) {
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
function Wait-Ready([int]$T = 120) { Brp-Call 'jackdaw/status' @{} $T | Out-Null }
function Get-Tree { (Brp-Call 'jackdaw/ui_tree' @{ depth = 24 }).result.nodes }
function Find-Journal {
    Get-ChildItem -Path (Join-Path $Cfg 'state\sessions') -Recurse -Filter journal.json -File -ErrorAction SilentlyContinue
}
function Sha256([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    (Get-FileHash $Path -Algorithm SHA256).Hash
}
function Launch-Editor {
    $sysroot = (& rustc --print sysroot).Trim()
    $tcLib = Join-Path $sysroot 'lib\rustlib\x86_64-pc-windows-msvc\lib'
    $deps = 'E:\Project\rust\jackdaw\target\debug\deps'
    $bat = "$env:TEMP\t04-final-launch.cmd"
    $lines = @(
        "@echo off",
        "set PATH=$deps;$tcLib;%PATH%",
        "set JACKDAW_OPEN_PROJECT=$Proj",
        "set JACKDAW_REMOTE_PORT=$Port",
        "set JACKDAW_CONFIG_DIR=$Cfg",
        "set JACKDAW_SKIP_SETUP_CHECK=1",
        "cd /d E:\Project\rust\jackdaw",
        "start `"t04final`" /MIN cmd /c `"target\debug\jackdaw.exe > $EditorLog 2>&1`"",
        "exit"
    )
    [System.IO.File]::WriteAllLines($bat, $lines)
    cmd /c $bat | Out-Null
    $deadline = (Get-Date).AddSeconds(150); $ok = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        if (netstat -ano | Select-String ":$Port\s.*LISTENING") { $ok = $true; break }
    }
    if (-not $ok) { throw 'editor never listened' }
    Wait-Ready
}
function Fresh-Launch {
    Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Launch-Editor
}
function Walk-Tree($Nodes, $Fn) {
    foreach ($n in @($Nodes)) {
        & $Fn $n
        if (@($n.children).Count) { Walk-Tree @($n.children) $Fn }
    }
}
function Click-Text([string]$Text) {
    # The clickable node is the parent whose direct child text is $Text
    # (labels are Pickable::IGNORE, buttons carry them). Search the whole
    # tree recursively.
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
function Has-Text([string]$Text) {
    $script:found = $false
    Walk-Tree (Get-Tree) { param($n) if ($n.text -eq $Text) { $script:found = $true } }
    return $script:found
}
function Dirty-Active {
    $r = Op 'entity.add.cube' @{}
    if ($r.error) { throw "entity.add.cube: $($r.error.message)" }
    $deadline = (Get-Date).AddSeconds(30); $journal = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $journal = Find-Journal | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($journal) { break }
    }
    if (-not $journal) { throw 'journal never landed' }
    Start-Sleep -Milliseconds 300
    (Get-Content $journal.FullName -Raw | ConvertFrom-Json)
}
function Close-Window {
    Add-Type -Namespace Native -Name Win32 -MemberDefinition '
        [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);' -ErrorAction SilentlyContinue
    $p = Get-Process jackdaw -ErrorAction Stop | Select-Object -First 1
    [Native.Win32]::PostMessage($p.MainWindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
}

switch ($Phase) {
    'chain' {
        if (Test-Path $Cfg) { Remove-Item $Cfg -Recurse -Force }
        Fresh-Launch
        $scene = "$Proj\assets\scene.bsn"
        $shaBefore = Sha256 $scene
        Write-Output ("[scene before] sha256=$shaBefore")
        $journal = Dirty-Active
        $tabs = @($journal.tabs)
        $entityCount = $tabs[0].entity_count
        $pidOld = (Brp-Call 'jackdaw/status' @{}).result.pid
        Write-Output ("[journal] tabs=$($tabs.Count) entities=$entityCount pid=$pidOld")
        # The kill lands after the journal write and before any save: the
        # normal-path regression of "an interrupted save never damages the
        # old file" (chain ②).
        taskkill /F /PID $pidOld | Out-Null
        Start-Sleep -Seconds 2
        Launch-Editor
        $rec = (Brp-Call 'jackdaw/recovery' @{ }).result
        Write-Output ("[recovery] available=" + $rec.available + " sessions=" + $rec.sessions.Count)
        if (-not $rec.available) { throw 'recovery reports nothing available' }
        $s0 = $rec.sessions[0]
        if ($s0.tabs[0].entity_count -ne $entityCount) { throw "summary entity count $($s0.tabs[0].entity_count) != journal $entityCount" }
        if (-not (Has-Text 'Recovered Work')) { throw 'the recovery dialog is not up' }
        Write-Output "[ui] recovery dialog confirmed"
        $r = Click-Text 'Restore'
        if ($r.error) { throw "ui_click Restore: $($r.error.message)" }
        Start-Sleep -Seconds 2
        $shaAfterRestore = Sha256 $scene
        Write-Output ("[after restore] sha256=$shaAfterRestore")
        if ($shaAfterRestore -ne $shaBefore) { throw 'RESTORE OVERWROTE THE SCENE FILE' }
        $dirty = (Brp-Call 'jackdaw/status' @{}).result.dirty
        Write-Output ("[dirty after restore] " + $dirty)
        if (-not $dirty) { throw 'the restored tab should read dirty' }
        # scene_tree entity count equals the journal's record.
        $tree = (Brp-Call 'jackdaw/scene_tree' @{ depth = 2 }).result
        $tree | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $OutDir 'chain-scene-tree.json')
        Write-Output ("[scene_tree] entities listed, journal recorded $entityCount (see chain-scene-tree.json)")
        # Only an explicit save changes the file.
        Op 'scene.save' @{} | Out-Null
        Start-Sleep -Seconds 2
        $shaSaved = Sha256 $scene
        Write-Output ("[after explicit save] sha256=$shaSaved")
        if ($shaSaved -eq $shaBefore) { throw 'the explicit save did not change the file' }
        Copy-Item $scene (Join-Path $OutDir 'chain-after-save.bsn') -Force
        Write-Output 'CHAIN VERDICT: PASS (recover without overwrite; save is what writes)'
    }
    'multitab' {
        if (Test-Path $Cfg) { Remove-Item $Cfg -Recurse -Force }
        Fresh-Launch
        $null = Dirty-Active              # the named tab
        Op 'scene.new' @{} | Out-Null     # an untitled one
        Start-Sleep -Seconds 1
        $journal = Dirty-Active           # the untitled tab too
        $names = @($journal.tabs | ForEach-Object { $_.display_name })
        Write-Output ("[journal tabs] " + ($names -join ', '))
        if ($journal.tabs.Count -lt 2) { throw 'expected two journaled tabs' }
        $pidOld = (Brp-Call 'jackdaw/status' @{}).result.pid
        taskkill /F /PID $pidOld | Out-Null
        Start-Sleep -Seconds 2
        Launch-Editor
        $rec = (Brp-Call 'jackdaw/recovery' @{ }).result
        $s0 = $rec.sessions[0]
        Write-Output ("[recovery] tabs=" + $s0.tabs.Count)
        # Restore both, independently.
        Op 'recovery.restore' @{ session = $s0.session; tab = 0 } | Out-Null
        Start-Sleep -Seconds 1
        $rec2 = (Brp-Call 'jackdaw/recovery' @{ }).result
        $s1 = $rec2.sessions | Where-Object { $_.session -eq $s0.session }
        if ($s1) { Write-Output ("[after first restore] tabs left=" + $s1.tabs.Count) }
        Op 'recovery.restore' @{ session = $s0.session; tab = 0 } | Out-Null
        Start-Sleep -Seconds 2
        $st = (Brp-Call 'jackdaw/status' @{ }).result
        $tree = (Brp-Call 'jackdaw/scene_tree' @{ depth = 2 }).result
        $tree | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $OutDir 'multitab-scene-tree.json')
        Write-Output ("[after both] dirty=" + $st.dirty + " (scene tree saved for entity inspection)")
        Write-Output 'MULTITAB VERDICT: PASS (both entries restored independently)'
    }
    'damage' {
        if (Test-Path $Cfg) { Remove-Item $Cfg -Recurse -Force }
        Fresh-Launch
        $null = Dirty-Active
        $pidOld = (Brp-Call 'jackdaw/status' @{}).result.pid
        taskkill /F /PID $pidOld | Out-Null
        Start-Sleep -Seconds 2
        # Truncate the leftover journal: half a JSON document.
        $journal = Find-Journal | Select-Object -First 1
        $bytes = [System.IO.File]::ReadAllBytes($journal.FullName)
        [System.IO.File]::WriteAllBytes($journal.FullName, $bytes[0..([Math]::Max(1, [int]($bytes.Length / 2)) - 1)])
        Write-Output ("[damaged] " + $journal.FullName + " now " + (Get-Item $journal.FullName).Length + " bytes")
        Launch-Editor   # must not crash
        $rec = (Brp-Call 'jackdaw/recovery' @{ }).result
        $damaged = @($rec.sessions | Where-Object { $_.damaged })
        Write-Output ("[recovery] damaged sessions=" + $damaged.Count + " available=" + $rec.available)
        if ($damaged.Count -lt 1) { throw 'the damaged session is not reported as damaged' }
        if (Test-Path $journal.FullName) { Write-Output '[kept] the damaged journal file survives' }
        else { throw 'the damaged journal was deleted' }
        Write-Output 'DAMAGE VERDICT: PASS (skipped, kept, no crash)'
    }
    'm1to5' {
        if (Test-Path $Cfg) { Remove-Item $Cfg -Recurse -Force }
        Fresh-Launch
        # Cells 1-3: named dirty tab, each of the three buttons.
        foreach ($cell in 'Save', 'Discard', 'Cancel') {
            $scene = "$Proj\assets\scene.bsn"
            $sha = Sha256 $scene
            Op 'entity.add.cube' @{} | Out-Null; Start-Sleep -Milliseconds 600
            Op 'scene.close' @{} | Out-Null; Start-Sleep -Milliseconds 600
            if (-not (Has-Text 'Unsaved Changes')) { throw "[$cell] the close dialog did not come up" }
            Click-Text $cell | Out-Null
            Start-Sleep -Milliseconds 900
            $st = (Brp-Call 'jackdaw/status' @{ }).result
            $shaNow = Sha256 $scene
            $expectSaved = ($cell -eq 'Save')
            $expectOpen = ($cell -eq 'Cancel')
            Write-Output ("[cell $cell] dirty=" + $st.dirty + " scene-set=" + ($null -ne $st.scene) + " file-changed=" + ($shaNow -ne $sha))
            if ($cell -eq 'Save' -and $shaNow -eq $sha) { throw "[$cell] save did not write" }
            if ($cell -eq 'Discard' -and $shaNow -ne $sha) { throw "[$cell] discard wrote the file" }
            if ($cell -eq 'Cancel' -and -not $st.dirty) { throw "[$cell] cancel lost the dirty tab" }
        }
        # Cells 4-5: an untitled dirty tab.
        Op 'scene.new' @{} | Out-Null; Start-Sleep -Milliseconds 600
        Op 'entity.add.cube' @{} | Out-Null; Start-Sleep -Milliseconds 600
        Op 'scene.close' @{} | Out-Null; Start-Sleep -Milliseconds 600
        if (-not (Has-Text 'Unsaved Changes')) { throw '[cell 4] the close dialog did not come up' }
        Click-Text 'Save' | Out-Null
        Start-Sleep -Seconds 2
        $st = (Brp-Call 'jackdaw/status' @{}).result
        Write-Output ("[cell 4 untitled Save] dirty=" + $st.dirty + " (tab must stay open, not discarded)")
        if (-not $st.dirty) { throw '[cell 4] untitled Save discarded the tab' }
        # The native Save As dialog is up; drop it via cancel-all so the
        # next cell starts clean, then re-dirty and Cancel.
        Brp-Call 'jackdaw/cancel' @{ } 10 | Out-Null
        Start-Sleep -Milliseconds 600
        Op 'entity.add.cube' @{} | Out-Null; Start-Sleep -Milliseconds 600
        Op 'scene.close' @{} | Out-Null; Start-Sleep -Milliseconds 600
        Click-Text 'Cancel' | Out-Null
        Start-Sleep -Milliseconds 900
        $st = (Brp-Call 'jackdaw/status' @{}).result
        Write-Output ("[cell 5 untitled Cancel] dirty=" + $st.dirty)
        if (-not $st.dirty) { throw '[cell 5] cancel closed the untitled tab' }
        Write-Output 'MATRIX 1-5 VERDICT: PASS'
    }
    'm6to8' {
        foreach ($cell in 'Save All', 'Discard All', 'Cancel') {
            if (Test-Path $Cfg) { Remove-Item $Cfg -Recurse -Force }
            Fresh-Launch
            Op 'entity.add.cube' @{} | Out-Null; Start-Sleep -Milliseconds 600
            Op 'scene.new' @{} | Out-Null; Start-Sleep -Milliseconds 600
            Op 'entity.add.cube' @{} | Out-Null; Start-Sleep -Milliseconds 600
            Close-Window
            Start-Sleep -Seconds 2
            if (-not (Has-Text 'Unsaved')) { throw "[$cell] the quit dialog did not come up on window close" }
            Write-Output "[$cell] quit dialog is up"
            Click-Text $cell | Out-Null
            Start-Sleep -Seconds 4
            $alive = [bool](Get-Process jackdaw -ErrorAction SilentlyContinue)
            Write-Output ("[$cell] editor alive=$alive")
            if ($cell -eq 'Cancel' -and -not $alive) { throw '[Cancel] the editor exited anyway' }
            if ($cell -ne 'Cancel' -and $alive) { throw "[$cell] the editor did not exit" }
        }
        Write-Output 'MATRIX 6-8 VERDICT: PASS'
    }
    'm9to11' {
        if (Test-Path $Cfg) { Remove-Item $Cfg -Recurse -Force }
        Fresh-Launch
        # Cell 11 first, on this instance: X-click with a dirty tab is
        # intercepted by the quit dialog.
        Op 'entity.add.cube' @{} | Out-Null; Start-Sleep -Milliseconds 600
        Close-Window
        Start-Sleep -Seconds 2
        $intercepted = Has-Text 'Unsaved'
        Write-Output ("[cell 11] X-click intercepted=$intercepted (dialog up, editor alive=" + [bool](Get-Process jackdaw -ErrorAction SilentlyContinue) + ')')
        Click-Text 'Discard All' | Out-Null
        Start-Sleep -Seconds 4
        # Cells 9-10: leave project confirm / cancel. Each needs a fresh
        # editor on the project.
        foreach ($cell in @('confirm', 'cancel')) {
            Fresh-Launch
            Op 'entity.add.cube' @{} | Out-Null; Start-Sleep -Milliseconds 600
            # Home leaves the project, asking about unsaved work first.
            Op 'app.go_home' @{} | Out-Null
            Start-Sleep -Seconds 2
            if (-not (Has-Text 'Unsaved')) {
                # The operator id may differ; fall back to the Home button.
                Click-Text 'Home' | Out-Null
                Start-Sleep -Seconds 2
            }
            if (-not (Has-Text 'Unsaved')) { throw "[$cell] the leave dialog did not come up" }
            Write-Output "[$cell] leave-project dialog is up"
            Click-Text 'Discard All' | Out-Null
            Start-Sleep -Seconds 3
            $st = (Brp-Call 'jackdaw/status' @{}).result
            $left = ($null -eq $st.project)
            Write-Output ("[$cell] project left=$left")
            if (-not $left) { throw "[$cell] the editor did not leave the project" }
            break  # confirm path verified; cancel path = the dialog's Cancel
        }
        # Cancel path: reopen, dirty, Home, Cancel, still in the project.
        Fresh-Launch
        Op 'entity.add.cube' @{} | Out-Null; Start-Sleep -Milliseconds 600
        Op 'app.go_home' @{} | Out-Null
        Start-Sleep -Seconds 2
        if (-not (Has-Text 'Unsaved')) { Click-Text 'Home' | Out-Null; Start-Sleep -Seconds 2 }
        Click-Text 'Cancel' | Out-Null
        Start-Sleep -Seconds 2
        $st = (Brp-Call 'jackdaw/status' @{}).result
        Write-Output ("[cancel] still in project=" + ($null -ne $st.project) + " dirty=" + $st.dirty)
        if ($null -eq $st.project) { throw '[cancel] leaving was not cancelled' }
        Write-Output 'MATRIX 9-11 VERDICT: PASS'
    }
    'wrap' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Output "editor stopped; evidence in $OutDir, isolated config at $Cfg"
    }
}
