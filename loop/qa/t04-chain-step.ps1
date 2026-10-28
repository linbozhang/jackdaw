# T04-T3 chain driver, one step per invocation (each is short and prints
# immediately; the phase script's buffered output was unreadable when a
# step stalled).
param(
    [Parameter(Mandatory = $true)][ValidateSet('record', 'kill', 'relaunch', 'verify', 'save', 'wrap')][string]$Step,
    [int]$Port = 15814,
    [string]$Cfg = "$env:TEMP\t04-final-cfg",
    [string]$Proj = 'C:\Users\linbo.zhang\Projects\my-game'
)
$ErrorActionPreference = 'Stop'
$OutDir = 'E:\Project\rust\jackdaw\loop\reports\t04t3-live'
$State = "$env:TEMP\t04-chain-state.txt"
$Scene = "$Proj\assets\scene.bsn"

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
    # The clickable node is the parent whose direct child text is $Text
    # (labels are Pickable::IGNORE, buttons carry them). Search the whole
    # tree, both levels.
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

switch ($Step) {
    'record' {
        $j = Get-ChildItem (Join-Path $Cfg 'state\sessions') -Recurse -Filter journal.json | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $doc = Get-Content $j.FullName -Raw | ConvertFrom-Json
        $count = $doc.tabs[0].entity_count
        $sha = (Get-FileHash $Scene -Algorithm SHA256).Hash
        $pidNow = (Brp-Call 'jackdaw/status' @{}).result.pid
        "$pidNow|$count|$sha|$($j.DirectoryName)" | Set-Content -Encoding UTF8 $State
        Write-Output "RECORD pid=$pidNow journal-entities=$count sha=$sha"
        Copy-Item $j.FullName (Join-Path $OutDir 'chain-journal.json') -Force
    }
    'kill' {
        $s = (Get-Content $State) -split '\|', 4
        taskkill /F /PID $s[0] | Out-Null
        Start-Sleep -Seconds 2
        Write-Output ("KILLED pid=" + $s[0] + " journal-kept=" + (Test-Path (Join-Path $s[3] 'journal.json')))
    }
    'relaunch' {
        $bat = "$env:TEMP\t04-final-launch.cmd"
        cmd /c $bat | Out-Null
        $deadline = (Get-Date).AddSeconds(150); $ok = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3
            if (netstat -ano | Select-String ":$Port\s.*LISTENING") { $ok = $true; break }
        }
        if (-not $ok) { throw 'editor never relistened' }
        Start-Sleep -Seconds 4
        $rec = (Brp-Call 'jackdaw/recovery' @{ }).result
        Write-Output ("RECOVERY available=" + $rec.available + " sessions=" + $rec.sessions.Count)
        $rec | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $OutDir 'chain-recovery.json')
        $s = (Get-Content $State) -split '\|', 4
        $s0 = $rec.sessions[0]
        if ($s0.tabs[0].entity_count -ne [int]$s[1]) { throw ("summary entities " + $s0.tabs[0].entity_count + " != journal " + $s[1]) }
        Write-Output ("SUMMARY-ENTITIES MATCH " + $s0.tabs[0].entity_count)
        if (-not (Has-Text 'Recovered Work')) { throw 'recovery dialog not up' }
        Write-Output 'DIALOG-UP'
        $s0.session | Set-Content -Encoding UTF8 "$env:TEMP\t04-chain-session.txt"
    }
    'verify' {
        $s = (Get-Content $State) -split '\|', 4
        $r = Click-Text 'Restore'
        if ($r.error) { throw ("ui_click Restore: " + $r.error.message) }
        Start-Sleep -Seconds 3
        $shaNow = (Get-FileHash $Scene -Algorithm SHA256).Hash
        if ($shaNow -ne $s[2]) { throw "RESTORE OVERWROTE: $shaNow vs $($s[2])" }
        Write-Output "SHA-UNCHANGED $shaNow"
        $st = (Brp-Call 'jackdaw/status' @{}).result
        Write-Output ("DIRTY=" + $st.dirty)
        $tree = (Brp-Call 'jackdaw/scene_tree' @{ depth = 3 }).result
        $tree | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $OutDir 'chain-scene-tree.json')
        Write-Output ("SCENE-TREE saved; journal recorded " + $s[1] + " entities (inspect chain-scene-tree.json)")
    }
    'save' {
        $s = (Get-Content $State) -split '\|', 4
        Brp-Call 'jackdaw/call_operator' @{ id = 'scene.save'; params = @{} } 30 | Out-Null
        Start-Sleep -Seconds 3
        $shaNow = (Get-FileHash $Scene -Algorithm SHA256).Hash
        if ($shaNow -eq $s[2]) { throw 'the explicit save did not change the file' }
        Write-Output "SHA-CHANGED-ON-SAVE $shaNow"
        Copy-Item $Scene (Join-Path $OutDir 'chain-after-save.bsn') -Force
        Write-Output 'CHAIN VERDICT: PASS (recover without overwrite; save is what writes)'
    }
    'wrap' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Output 'editor stopped'
    }
}
