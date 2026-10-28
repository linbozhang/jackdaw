# One N9 quit-dialog cell (7/8): fresh editor, one dirty named tab,
# WM_CLOSE, click the labelled button, assert exit or stay.
param([Parameter(Mandatory = $true)][ValidateSet('Discard All', 'Cancel')][string]$Label)
$ErrorActionPreference = 'Stop'
$Port = 15814
$Cfg = "$env:TEMP\t04-final-cfg"
Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force
if (Test-Path $Cfg) { Remove-Item $Cfg -Recurse -Force }
cmd /c "$env:TEMP\t04-final-launch.cmd" | Out-Null
$deadline = (Get-Date).AddSeconds(90)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    if (netstat -ano | Select-String ":$Port\s.*LISTENING") { break }
}
Start-Sleep 4
function Post([string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 15
}
Post 'jackdaw/call_operator' @{ id = 'entity.add.cube'; params = @{} } | Out-Null
Start-Sleep -Seconds 1
$h = (Get-Process jackdaw | Select-Object -First 1).MainWindowHandle
Add-Type -Namespace N4 -Name W -MemberDefinition '[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);' -ErrorAction SilentlyContinue
[N4.W]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
Start-Sleep -Seconds 3
$t = (Post 'jackdaw/ui_tree' @{ depth = 24 }).result.nodes
$ent = $null
function Walk($ns) {
    foreach ($n in @($ns)) {
        foreach ($c in @($n.children)) {
            if ($c.text -eq $Label -and $c.rect -and $c.rect[2] -gt 1) { $script:ent = $n.entity }
        }
        Walk @($n.children)
    }
}
Walk $t
if (-not $ent) { throw "no $Label button in the quit dialog" }
Post 'jackdaw/ui_click' @{ entity = [uint64]$ent } | Out-Null
Start-Sleep -Seconds 4
$alive = [bool](Get-Process jackdaw -ErrorAction SilentlyContinue)
Write-Output ("[$Label] editor-alive=$alive")
if ($Label -eq 'Cancel' -and -not $alive) { throw 'editor exited on Cancel' }
if ($Label -ne 'Cancel' -and $alive) { throw "editor did not exit on $Label" }
Write-Output "CELL $Label VERDICT: PASS"
