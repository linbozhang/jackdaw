$ErrorActionPreference = 'Stop'
$Repo    = 'E:\Project\rust\jackdaw'
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
function Get-UiRows {
    $j = Invoke-BrpRaw 'world.query' @{ data = @{ components = @('bevy_ui::widget::text::Text', 'bevy_ui::ui_node::ComputedNode', 'bevy_ui::ui_transform::UiGlobalTransform') } }
    return $j.result | Where-Object { $_.components.'bevy_ui::ui_node::ComputedNode'.size[0] -gt 0 } | ForEach-Object {
        $a = $_.components.'bevy_ui::ui_transform::UiGlobalTransform'
        [pscustomobject]@{ text = $_.components.'bevy_ui::widget::text::Text'; cx = [double]$a[4]; cy = [double]$a[5] }
    }
}

$proc = Get-Process jackdaw -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $proc) { throw 'editor not running' }
Write-Host ("editor pid=" + $proc.Id)

# The dropdown must still be open with the Build Game... row.
$row = Get-UiRows | Where-Object { $_.text -like 'Build Game*' } | Select-Object -First 1
if (-not $row) { throw 'dropdown closed; no Build Game... row' }
Write-Host ("row '" + $row.text + "' at ({0:N1},{1:N1})" -f $row.cx, $row.cy)

# Evidence: window screenshot with the menu open (BRP screenshot saves under the project).
$r = Wait-BrpResult 'jackdaw/screenshot' @{ kind = 'window'; path = 'screenshots/qa-final-menu-open.png' } -TimeoutSec 20
Copy-Item (Join-Path $Project 'screenshots\qa-final-menu-open.png') (Join-Path $OutDir 'qa-menu-open.png') -Force
Write-Host ("menu-open shot {0}x{1}" -f $r.width, $r.height)

$before = (Get-Item $Dist).LastWriteTime
Write-Host "dist mtime before: $before"

# Click the Build Game... row.
Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = $row.cx; y = $row.cy; action = 'click' } }) | Out-Null
Start-Sleep -Milliseconds 800
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
$alive2 = Get-Process -Id $proc.Id -ErrorAction Stop
$alive2.Refresh()
Save-WindowScreenshot $alive2.MainWindowHandle (Join-Path $OutDir 'qa-menu-exported.png') | Out-Null
Write-Host 'footer shot saved'

Write-Output 'QA_MENU_EXPORT_PASS'
Stop-Process -Id $proc.Id -Force
Write-Host ("editor killed pid=" + $proc.Id)
