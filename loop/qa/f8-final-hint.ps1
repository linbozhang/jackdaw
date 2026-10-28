# Feature 8 final QA: the Scene section's empty-scene hint on a real editor.
# States: no Environment -> hint visible (+ PrintWindow shot); Environment added
# (+ environment.set post on) -> hint gone; Environment removed -> hint back.
param([int]$Port = 15703)
$ErrorActionPreference = 'Stop'
$Repo = 'E:\Project\rust\jackdaw'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$Out = Join-Path $Repo 'loop\f8-final-qa'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port
. (Join-Path $Repo 'loop\qa\screenshot.ps1')

function Raw([string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 12 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    try { $w = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body $bytes -UseBasicParsing -TimeoutSec 30 }
    catch { Start-Sleep -Seconds 2; $w = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body $bytes -UseBasicParsing -TimeoutSec 45 }
    return [System.Text.Encoding]::UTF8.GetString($w.RawContentStream.ToArray()) | ConvertFrom-Json
}
function Op([string]$Id, $Params = @{}) { Raw 'jackdaw/call_operator' @{ id = $Id; params = $Params } | Out-Null }
function Frames([int]$n) { try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 } }
function Shot([string]$Name) {
    $hwnd = (Get-Process jackdaw -ErrorAction Stop | Select-Object -First 1).MainWindowHandle
    Save-WindowScreenshot ([IntPtr]$hwnd) (Join-Path $Out $Name) | Out-Null
    Write-Host ("SHOT {0}" -f $Name)
}
# The empty hint row: its Text (rendered copy, not the ftl key), its layout size,
# and the style-level display of the node carrying GraphicsSceneEmptyHint's Text.
function HintRow {
    $rows = Raw 'world.query' @{
        data = @{ components = @('bevy_ui::widget::text::Text', 'bevy_ui::ui_node::ComputedNode', 'bevy_ui::ui_node::Node') }
    }
    foreach ($r in @($rows.result)) {
        $t = [string]$r.components.'bevy_ui::widget::text::Text'
        if ($t -like '*no environment*') {
            $cn = $r.components.'bevy_ui::ui_node::ComputedNode'
            $node = $r.components.'bevy_ui::ui_node::Node'
            return @{ entity = [string]$r.entity; text = $t; w = [double]$cn.size[0]; h = [double]$cn.size[1]; display = ($node | ConvertTo-Json -Depth 4 -Compress) }
        }
    }
    return $null
}
function Environments {
    $r = Raw 'world.query' @{ data = @{ components = @('jackdaw_scene_types::environment::Environment') } }
    return @($r.result) | ForEach-Object { [string]$_.entity }
}

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project; $env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath (Join-Path $Repo 'target\debug\jackdaw.exe') -WorkingDirectory (Join-Path $Repo 'target\debug') -PassThru -RedirectStandardOutput "$env:TEMP\jd-final-out.log" -RedirectStandardError "$env:TEMP\jd-final-err.log"
try {
    Wait-EditorReady -TimeoutSec 120
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    Op 'graphics.open'; Frames 12; Start-Sleep -Milliseconds 400

    # -- State 1: ensure the scene has NO environment, the hint must show -------
    $envs = Environments
    Write-Host ("environments at start: {0}" -f ($(if ($envs) { $envs -join ',' } else { 'none' })))
    foreach ($e in $envs) { Op 'component.remove' @{ entity = $e; type_path = 'jackdaw_scene_types::environment::Environment' } }
    Frames 8; Start-Sleep -Milliseconds 400

    $hint = HintRow
    if (-not $hint) { throw 'FAIL: no "no environment" text rendered in the panel' }
    Write-Host ("EMPTY state: text='{0}' size={1:N0}x{2:N0} display-json={3}" -f $hint.text, $hint.w, $hint.h, $hint.display)
    if ($hint.w -le 0) { throw 'FAIL: hint text renders but is laid out at zero size' }
    if ($hint.text -like '*graphics-scene-empty-hint*') { throw 'FAIL: the ftl key leaked into the UI instead of its copy' }
    Shot 'final-empty-hint.png'

    # -- State 2: add an Environment (component.add), open post, hint must go ---
    $tree = (Brp-Result (Brp-Call 'jackdaw/scene_tree' @{})).tree
    Op 'component.add' @{ entity = @($tree)[0].entity; type_path = 'jackdaw_scene_types::environment::Environment' }
    Frames 8
    Op 'environment.set' @{ 'post.enabled' = $true }
    Frames 6; Start-Sleep -Milliseconds 400
    $hint2 = HintRow
    $goneOk = ($null -eq $hint2) -or ($hint2.w -le 0) -or ($hint2.display -match 'None')
    Write-Host ("WITH-ENV state: row={0}" -f ($(if ($hint2) { "size={0:N0} display={1}" -f $hint2.w, $hint2.display } else { 'text no longer laid out' })))
    if (-not $goneOk) { throw 'FAIL: hint still visible with an environment present' }
    Shot 'final-with-environment.png'

    # -- State 3: remove the environment, the hint must come back --------------
    $envs2 = Environments
    if ($envs2.Count -ne 1) { throw ("unexpected environment count after add: {0}" -f $envs2.Count) }
    Op 'component.remove' @{ entity = $envs2[0]; type_path = 'jackdaw_scene_types::environment::Environment' }
    Frames 8; Start-Sleep -Milliseconds 400
    $hint3 = HintRow
    if (-not $hint3 -or $hint3.w -le 0) { throw 'FAIL: hint did not return after the environment left' }
    Write-Host ("BACK-EMPTY state: size={0:N0} — hint returned" -f $hint3.w)
    Write-Host 'F8_FINAL_HINT_QA_PASS'
} finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
