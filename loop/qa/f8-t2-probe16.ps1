# Replicate run20's path then inspect the Bloom label object in detail.
param([int]$Port = 15703)
$ErrorActionPreference = 'Stop'
$Repo = 'E:\Project\rust\jackdaw'
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
        [pscustomobject]@{ text = [string]$_.components.'bevy_ui::widget::text::Text'; cx = [double]$a[4]; cy = [double]$a[5]; w = [double]$s[0] }
    }
}
function Find-Row([string]$Text) {
    $hits = Rows | Where-Object { $_.text -eq $Text -and $_.cx -ge 1000 -and $_.cy -ge 40 }
    if (-not $hits) { $hits = Rows | Where-Object { $_.text -eq $Text } }
    if (-not $hits) { throw "UI row '$Text' not found" }
    return @($hits)[0]
}
function Click([double]$x, [double]$y) { Raw 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = $x; y = $y; action = 'click' } } | Out-Null }
function Frames([int]$n) { try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 } }
function Get-Env {
    $r = Raw 'world.query' @{ data = @{ components = @('jackdaw_scene_types::environment::Environment') } }
    return (@($r.result)[0]).components.'jackdaw_scene_types::environment::Environment'
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath (Join-Path $Repo 'target\debug\jackdaw.exe') -WorkingDirectory (Join-Path $Repo 'target\debug') -PassThru
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    Raw 'jackdaw/call_operator' @{ id = 'graphics.open'; params = @{} } | Out-Null
    Frames 12; Start-Sleep -Milliseconds 500
    $tree = (Brp-Result (Brp-Call 'jackdaw/scene_tree' @{})).tree
    $target = @($tree)[0].entity
    Raw 'jackdaw/call_operator' @{ id = 'component.add'; params = @{ entity = $target; type_path = 'jackdaw_scene_types::environment::Environment' } } | Out-Null
    Frames 10
    $post = Find-Row 'Post Processing'
    Click ($post.cx - $post.w/2 - 12) $post.cy
    Frames 10
    Write-Host ("post.enabled now: {0}" -f [bool](Get-Env).post.enabled)

    Write-Host '--- all rows like *Bloom*:'
    (Rows | Where-Object { $_.text -like '*Bloom*' }) | ConvertTo-Json -Depth 3 | Write-Host
    $label = Find-Row 'Bloom Intensity'
    Write-Host '--- Find-Row result:'
    $label | ConvertTo-Json -Depth 3 | Write-Host
    Write-Host ("props: " -f (($label.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' '))
} finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
