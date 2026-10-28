# Dump panel rows after layout reset.
param([int]$Port = 15703)
$ErrorActionPreference = 'Stop'
$Repo = 'E:\Project\rust\jackdaw'
. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
function Raw([string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 12 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $w = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body $bytes -UseBasicParsing -TimeoutSec 30
    return [System.Text.Encoding]::UTF8.GetString($w.RawContentStream.ToArray()) | ConvertFrom-Json
}
function Rows {
    $j = Raw 'world.query' @{ data = @{ components = @('bevy_ui::widget::text::Text', 'bevy_ui::ui_node::ComputedNode', 'bevy_ui::ui_transform::UiGlobalTransform') } }
    $j.result | Where-Object { $_.components.'bevy_ui::ui_node::ComputedNode'.size[0] -gt 0 } | ForEach-Object {
        $a = $_.components.'bevy_ui::ui_transform::UiGlobalTransform'
        [pscustomobject]@{ text = [string]$_.components.'bevy_ui::widget::text::Text'; cx = [math]::Round([double]$a[4],1); cy = [math]::Round([double]$a[5],1); w = [math]::Round([double]$_.components.'bevy_ui::ui_node::ComputedNode'.size[0],1) }
    }
}
function Ptr([string]$Action, [double]$X, [double]$Y) {
    Raw 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = $X; y = $Y; action = $Action } } | Out-Null
}
function Frames([int]$n) { try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 } }
Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = 'C:\Users\linbo.zhang\Projects\my-game'; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath (Join-Path $Repo 'target\debug\jackdaw.exe') -WorkingDirectory (Join-Path $Repo 'target\debug') -PassThru
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    $win = @(Rows | Where-Object { $_.text -eq 'Window' -and $_.cy -lt 40 })[0]
    Ptr 'click' $win.cx $win.cy; Frames 8; Start-Sleep -Milliseconds 500
    $reset = @(Rows | Where-Object { $_.text -like '*Reset Layout*' -and $_.cy -gt 20 })[0]
    Ptr 'click' $reset.cx $reset.cy; Frames 20; Start-Sleep -Milliseconds 800
    Raw 'jackdaw/call_operator' @{ id = 'graphics.open'; params = @{} } | Out-Null
    Frames 12; Start-Sleep -Milliseconds 500
    $want = 'Viewport','Quality Preset','Low','Medium','High','Full','Render Scale','Anti-Aliasing','Off','FXAA','SMAA','TAA','Ambient Occlusion','SSAO Quality','Low','Ultra','Sun Shadows','Fog','Sharpening','Scene','Post Processing','Tonemapper','Exposure (EV100)','Bloom Intensity','Realtime GI'
    Rows | Where-Object { $want -contains $_.text -and $_.cx -gt 800 } | Sort-Object cy, cx | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
    # also the viewport capture size now
    Wait-BrpResult 'jackdaw/screenshot' @{ kind = 'viewport'; path = 'screenshots/reset-vp.png' } -TimeoutSec 30 | Out-Null
    Add-Type -AssemblyName System.Drawing
    $b = [System.Drawing.Bitmap]::FromFile('C:\Users\linbo.zhang\Projects\my-game\screenshots\reset-vp.png')
    Write-Host ("viewport capture after reset: {0}x{1}" -f $b.Width, $b.Height)
    $b.Dispose()
} finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
