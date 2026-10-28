# QA N9 matrix spot-check cells. Each cell is self-contained: fresh editor,
# one dirty arrangement, drive the dialog, assert exit/stay.
param([Parameter(Mandatory = $true)][ValidateSet('c1','c2','c4','c6','c6r','c8','c11')][string]$Cell)
$ErrorActionPreference = 'Stop'
$Port = 15815
function Post([string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $deadline = (Get-Date).AddSeconds(25)
    while ((Get-Date) -lt $deadline) {
        try { $raw = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 10 }
        catch { Start-Sleep -Milliseconds 250; continue }
        if ($null -ne $raw.error) { return @{ error = $raw.error } }
        if ($null -ne $raw.result) { return @{ result = $raw.result } }
        Start-Sleep -Milliseconds 120
    }
    throw "timeout $Method"
}
function Restart-Editor {
    Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 2
    cmd /c "$env:TEMP\t04-final-launch.cmd" | Out-Null
    $deadline = (Get-Date).AddSeconds(120); $ok = $false
    while ((Get-Date) -lt $deadline) { Start-Sleep 3; if (netstat -ano | Select-String ":$Port\s.*LISTENING") { $ok = $true; break } }
    if (-not $ok) { throw 'editor never listened' }
    Start-Sleep 6
}
function Get-Nodes { (Post 'jackdaw/ui_tree' @{ depth = 24 }).result.nodes }
function Find-Button([string]$Text) {
    $script:ent = $null
    function Walk($ns) {
        foreach ($n in @($ns)) {
            foreach ($c in @($n.children)) {
                if ($c.text -eq $Text -and $c.rect -and $c.rect[2] -gt 1) { $script:ent = [uint64]$n.entity }
            }
            Walk @($n.children)
        }
    }
    Walk (Get-Nodes)
    return $script:ent
}
function Click-Label([string]$Text) {
    $e = Find-Button $Text
    if (-not $e) { throw "no button labelled '$Text'" }
    Post 'jackdaw/ui_click' @{ entity = $e } | Out-Null
    Start-Sleep 3
}
function Send-WmClose {
    $h = (Get-Process jackdaw | Select-Object -First 1).MainWindowHandle
    Add-Type -Namespace N9 -Name W -MemberDefinition '[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);' -ErrorAction SilentlyContinue
    [N9.W]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    Start-Sleep 3
}
$Scene = 'C:\Users\linbo.zhang\Projects\my-game\assets\scene.bsn'

switch ($Cell) {
    'c1' {  # named dirty close -> Save: file written, tab closed
        $sha0 = (Get-FileHash $Scene -Algorithm SHA256).Hash
        Post 'jackdaw/call_operator' @{ id = 'entity.add.cube'; params = @{} } | Out-Null
        Start-Sleep 1
        Post 'jackdaw/call_operator' @{ id = 'scene.close'; params = @{} } | Out-Null
        Start-Sleep 2
        Click-Label 'Save'
        $sha1 = (Get-FileHash $Scene -Algorithm SHA256).Hash
        $st = (Post 'jackdaw/status' @{}).result
        Write-Output ("[c1] file-changed=" + ($sha1 -ne $sha0) + " scene-after=" + $st.scene)
        if ($sha1 -eq $sha0) { throw 'c1 FAIL: Save did not write the file' }
        if ($st.scene) { throw 'c1 FAIL: tab still open' }
        Write-Output 'CELL 1 PASS'
    }
    'c2' {  # named dirty close -> Discard: file untouched, tab closed
        Post 'jackdaw/call_operator' @{ id = 'entity.add.cube'; params = @{} } | Out-Null
        Start-Sleep 1
        $sha0 = (Get-FileHash $Scene -Algorithm SHA256).Hash
        Post 'jackdaw/call_operator' @{ id = 'scene.close'; params = @{} } | Out-Null
        Start-Sleep 2
        Click-Label 'Discard'
        $sha1 = (Get-FileHash $Scene -Algorithm SHA256).Hash
        $st = (Post 'jackdaw/status' @{}).result
        Write-Output ("[c2] file-unchanged=" + ($sha1 -eq $sha0) + " scene-after=" + $st.scene)
        if ($sha1 -ne $sha0) { throw 'c2 FAIL: Discard wrote the file' }
        if ($st.scene) { throw 'c2 FAIL: tab still open' }
        Write-Output 'CELL 2 PASS'
    }
    'c4' {  # untitled dirty close -> Save: Save As flow, tab stays open and dirty
        Post 'jackdaw/call_operator' @{ id = 'scene.new'; params = @{} } | Out-Null
        Start-Sleep 1
        Post 'jackdaw/call_operator' @{ id = 'entity.add.cube'; params = @{} } | Out-Null
        Start-Sleep 1
        $sha0 = (Get-FileHash $Scene -Algorithm SHA256).Hash
        Post 'jackdaw/call_operator' @{ id = 'scene.close'; params = @{} } | Out-Null
        Start-Sleep 2
        Click-Label 'Save'
        Start-Sleep 2
        $st = (Post 'jackdaw/status' @{}).result
        $sha1 = (Get-FileHash $Scene -Algorithm SHA256).Hash
        Write-Output ("[c4] dirty-after-save-click=" + $st.dirty + " file-untouched=" + ($sha1 -eq $sha0))
        if (-not $st.dirty) { throw 'c4 FAIL: the untitled tab was discarded or closed' }
        if ($sha1 -ne $sha0) { throw 'c4 FAIL: something wrote the scene file' }
        Write-Output 'CELL 4 PASS (Save opened Save As, tab kept; native dialog left up - killing)'
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force
    }
    'c6' {  # quit with named dirty -> Save All: saves and exits
        $sha0 = (Get-FileHash $Scene -Algorithm SHA256).Hash
        Post 'jackdaw/call_operator' @{ id = 'entity.add.cube'; params = @{} } | Out-Null
        Start-Sleep 1
        Send-WmClose
        Click-Label 'Save All'
        Start-Sleep 4
        $alive = [bool](Get-Process jackdaw -ErrorAction SilentlyContinue)
        $sha1 = (Get-FileHash $Scene -Algorithm SHA256).Hash
        Write-Output ("[c6] editor-exited=" + (-not $alive) + " file-saved=" + ($sha1 -ne $sha0))
        if ($alive) { throw 'c6 FAIL: editor still alive after Save All' }
        if ($sha1 -eq $sha0) { throw 'c6 FAIL: Save All exited without saving' }
        Write-Output 'CELL 6 PASS'
    }
    'c6r' {  # counter-proof: quit with dirty untitled -> Save All refuses to exit
        Post 'jackdaw/call_operator' @{ id = 'scene.new'; params = @{} } | Out-Null
        Start-Sleep 1
        Post 'jackdaw/call_operator' @{ id = 'entity.add.cube'; params = @{} } | Out-Null
        Start-Sleep 1
        Send-WmClose
        Click-Label 'Save All'
        Start-Sleep 4
        $alive = [bool](Get-Process jackdaw -ErrorAction SilentlyContinue)
        $st = (Post 'jackdaw/status' @{}).result
        Write-Output ("[c6r] editor-alive=" + $alive + " dirty=" + $st.dirty)
        if (-not $alive) { throw 'c6r FAIL: editor exited despite unsavable untitled tab' }
        Write-Output 'CELL 6-REFUSAL PASS (Save All correctly refuses with a dirty untitled tab)'
        Send-WmClose
        Click-Label 'Cancel'
    }
    'c8' {  # quit -> Cancel: editor stays
        Post 'jackdaw/call_operator' @{ id = 'entity.add.cube'; params = @{} } | Out-Null
        Start-Sleep 1
        Send-WmClose
        Click-Label 'Cancel'
        Start-Sleep 3
        $alive = [bool](Get-Process jackdaw -ErrorAction SilentlyContinue)
        $st = (Post 'jackdaw/status' @{}).result
        Write-Output ("[c8] editor-alive=" + $alive + " dirty-kept=" + $st.dirty)
        if (-not $alive) { throw 'c8 FAIL: editor exited on Cancel' }
        if (-not $st.dirty) { throw 'c8 FAIL: dirty lost on Cancel' }
        Write-Output 'CELL 8 PASS'
    }
    'c11' { # WM_CLOSE with dirty tab intercepted by the quit dialog
        Post 'jackdaw/call_operator' @{ id = 'entity.add.cube'; params = @{} } | Out-Null
        Start-Sleep 1
        Send-WmClose
        $e = Find-Button 'Save All'
        $alive = [bool](Get-Process jackdaw -ErrorAction SilentlyContinue)
        Write-Output ("[c11] dialog-up=" + ([bool]$e) + " editor-alive=" + $alive)
        if (-not $e) { throw 'c11 FAIL: quit dialog did not appear' }
        if (-not $alive) { throw 'c11 FAIL: editor exited without asking' }
        Write-Output 'CELL 11 PASS (WM_CLOSE intercepted)'
        Click-Label 'Cancel'
    }
}
