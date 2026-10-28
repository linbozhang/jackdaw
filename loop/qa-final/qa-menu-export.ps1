# Final QA: File menu -> "Build Game..." row click (real UI click path via
# BRP input.pointer + world.query row lookup), verify footer + dist rebuild.
$ErrorActionPreference = 'Stop'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Dist    = Join-Path $Project '.jackdaw\dist\release'
$Port    = 15719
$OutDir  = Join-Path $Repo 'loop\qa-final'

. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
. (Join-Path $Repo 'loop\qa\screenshot.ps1')

function Invoke-BrpRaw([string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 12 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $w = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body $bytes -UseBasicParsing -TimeoutSec 30
    return [System.Text.Encoding]::UTF8.GetString($w.RawContentStream.ToArray()) | ConvertFrom-Json
}
function Click-At([double]$x, [double]$y) {
    Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = $x; y = $y; action = 'click' } }) | Out-Null
}
function Wait-Frames([int]$n) {
    try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 }
}
function Get-UiRows {
    $j = Invoke-BrpRaw 'world.query' @{ data = @{ components = @('bevy_ui::widget::text::Text', 'bevy_ui::ui_node::ComputedNode', 'bevy_ui::ui_transform::UiGlobalTransform') } }
    return $j.result | Where-Object { $_.components.'bevy_ui::ui_node::ComputedNode'.size[0] -gt 0 } | ForEach-Object {
        $a = $_.components.'bevy_ui::ui_transform::UiGlobalTransform'
        $s = $_.components.'bevy_ui::ui_node::ComputedNode'.size
        [pscustomobject]@{ text = $_.components.'bevy_ui::widget::text::Text'; cx = [double]$a[4]; cy = [double]$a[5]; w = [double]$s[0]; h = [double]$s[1] }
    }
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "killing stale jackdaw pid=$($_.Id)"; Stop-Process -Id $_.Id -Force
}
Start-Sleep -Milliseconds 500

$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT  = "$Port"
$deps = Join-Path (Split-Path -Parent $Exe) 'deps'
$env:PATH = "$deps;$env:PATH"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
    -RedirectStandardOutput (Join-Path $OutDir 'menu-editor-stdout.log') `
    -RedirectStandardError (Join-Path $OutDir 'menu-editor-stderr.log') -PassThru
Write-Host "editor pid=$($proc.Id)"

Wait-EditorReady -TimeoutSec 120
Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 120 | Out-Null
Write-Host 'editor ready/idle'

$before = (Get-Item $Dist).LastWriteTime
Write-Host "dist mtime before: $before"

# 1) open the File menu: click the menu-bar File row.
$file = Get-UiRows | Where-Object { $_.text -eq 'File' -and $_.cy -lt 60 } | Select-Object -First 1
if (-not $file) { throw 'File menu-bar row not found' }
Write-Host ("File bar row at ({0:N1},{1:N1})" -f $file.cx, $file.cy)
Click-At ([double]$file.cx / 1.5) ([double]$file.cy / 1.5)
Wait-Frames 6
Start-Sleep -Milliseconds 400

# 2) the dropdown must now show the Build Game... row.
$row = Get-UiRows | Where-Object { $_.text -like 'Build Game*' } | Select-Object -First 1
if (-not $row) { throw 'File dropdown did not open: no Build Game... row' }
Write-Host ("dropdown open; row '" + $row.text + "' at ({0:N1},{1:N1})" -f $row.cx, $row.cy)

# Evidence: window screenshot with the menu open.
$r = Wait-BrpResult 'jackdaw/screenshot' @{ kind = 'window'; path = 'screenshots/qa-final-menu-open.png' } -TimeoutSec 20
Copy-Item (Join-Path $Project 'screenshots\qa-final-menu-open.png') (Join-Path $OutDir 'qa-menu-open.png') -Force
Write-Host ("menu-open shot {0}x{1}" -f $r.width, $r.height)

# 3) click the Build Game... row.
Click-At ([double]$row.cx / 1.5) ([double]$row.cy / 1.5)
Wait-Frames 8
Start-Sleep -Milliseconds 500
Write-Host 'Build Game... clicked'

$deadline = (Get-Date).AddMinutes(12)
$now = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { throw 'editor died during export' }
    $now = (Get-Item $Dist -ErrorAction SilentlyContinue).LastWriteTime
    if ($now -and $now -gt $before) { Write-Host "dist rebuilt at $now"; break }
}
if (-not ($now -and $now -gt $before)) { throw 'dist was not rebuilt within 12min' }

Start-Sleep -Seconds 6
$alive2 = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if (-not $alive2) { throw 'editor died after export' }
$alive2.Refresh()
Save-WindowScreenshot $alive2.MainWindowHandle (Join-Path $OutDir 'qa-menu-exported.png') | Out-Null
Write-Host 'footer shot saved'

Write-Output 'QA_MENU_EXPORT_PASS'
Stop-Process -Id $proc.Id -Force
Write-Host "editor killed pid=$($proc.Id)"
