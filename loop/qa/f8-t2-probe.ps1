# Probe: dump top-strip UI rows, click Window menu candidates, dump again.
param([int]$Port = 15703, [string]$Label = 'probe')
$ErrorActionPreference = 'Stop'
$Repo = 'E:\Project\rust\jackdaw'
$Exe = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
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
        $s = $_.components.'bevy_ui::ui_node::ComputedNode'.size
        [pscustomobject]@{ text = [string]$_.components.'bevy_ui::widget::text::Text'; cx = [math]::Round([double]$a[4],1); cy = [math]::Round([double]$a[5],1); w = [math]::Round([double]$s[0],1) }
    }
}
function Click([double]$x, [double]$y) {
    Raw 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = $x; y = $y; action = 'click' } } | Out-Null
}
function Frames([int]$n) { try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 } }

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    Write-Host '--- top rows (cy < 80):'
    Rows | Where-Object { $_.cy -lt 80 } | Sort-Object cy, cx | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
    $win = @(Rows | Where-Object { $_.text -eq 'Window' } | Sort-Object cy)[0]
    Write-Host ("clicking Window at logical ({0:N1},{1:N1})" -f ($win.cx/1.5), ($win.cy/1.5))
    Click ($win.cx/1.5) ($win.cy/1.5)
    Frames 10; Start-Sleep -Milliseconds 600
    Write-Host '--- rows after Window click (cy < 400, texts):'
    Rows | Where-Object { $_.cy -lt 400 } | Sort-Object cy, cx | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
} finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
