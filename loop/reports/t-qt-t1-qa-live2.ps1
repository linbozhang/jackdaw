# T-QT-T1 QA live verification, phase 2: drive the ALREADY-RUNNING editor
# (launched via Task Scheduler because this harness cannot spawn windowed
# children directly). Everything below runs through the NEW tools only.
param([int]$Port = 15807)
$ErrorActionPreference = "Stop"

function Brp-Call([string]$Method, $Params, [int]$TimeoutSec = 30) {
    $body = @{ jsonrpc = "2.0"; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $raw = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 20
        if ($null -ne $raw.error) { return @{ error = $raw.error } }
        if ($null -ne $raw.result) { return @{ result = $raw.result } }
        Start-Sleep -Milliseconds 120
    }
    throw "timeout waiting for $Method $Params"
}
function Wait-Idle() { Brp-Call "jackdaw/wait" @{ until = "idle" } 60 | Out-Null }
function Op([string]$Id, $Params) { Brp-Call "jackdaw/call_operator" @{ id = $Id; params = $Params } }

Wait-Idle

# --- [1] ui_tree: filtered queries, zero coordinate math on the caller side ---
$tree = Brp-Call "jackdaw/ui_tree" @{ text = "Open without setup"; depth = 0 }
$n1 = @($tree.result.nodes).Count
Write-Output ("[1] UI_TREE text=Open-without-setup -> $n1 node(s): " + ($tree.result | ConvertTo-Json -Compress -Depth 6))

# --- [2] ui_click through the real picking chain: the setup card, then Add Entity ---
$open = Brp-Call "jackdaw/ui_click" @{ text = "Open without setup" }
Write-Output ("[2] UI_CLICK setup card: " + ($open.result | ConvertTo-Json -Compress -Depth 10))
if ($open.error) { throw "setup card click refused" }
Wait-Idle; Wait-Idle

$buttons = Brp-Call "jackdaw/ui_tree" @{ kind = "button"; depth = 0 }
$nb = @($buttons.result.nodes).Count
$sample = @($buttons.result.nodes | Select-Object -First 4 | ForEach-Object { $_.text })
Write-Output ("[1] UI_TREE kind=button -> $nb buttons; sample: " + ($sample -join " | "))

$t0 = Get-Date
$add = Brp-Call "jackdaw/ui_click" @{ text = "Add Entity" }
$clickMs = [int]((Get-Date) - $t0).TotalMilliseconds
Write-Output ("[2] UI_CLICK Add Entity (${clickMs}ms): " + ($add.result | ConvertTo-Json -Compress -Depth 10))
Wait-Idle
$menu = Brp-Call "jackdaw/ui_tree" @{ text = "3D Objects"; depth = 0 }
if (@($menu.result.nodes).Count -lt 1) { throw "Add Entity opened no picker with a 3D Objects row" }
Write-Output ("[2] picker opened; 3D Objects rect=" + (@($menu.result.nodes)[0].rect -join ","))
Op "input.key" @{ key = "Escape"; action = "tap" } | Out-Null
Wait-Idle

# --- [3] ui_input: type into the picker search and submit ---
$add2 = Brp-Call "jackdaw/ui_click" @{ text = "Add Entity" }
Wait-Idle
$inputs = Brp-Call "jackdaw/ui_tree" @{ kind = "text_input"; depth = 0 }
$search = $null
foreach ($n in $inputs.result.nodes) {
    if ($n.rect -and [double]$n.rect[2] -gt 400.0) { $search = $n; break }
}
if (-not $search) { throw "no wide text_input among " + @($inputs.result.nodes).Count }
$typed = Brp-Call "jackdaw/ui_input" @{ entity = [UInt64]$search.entity; text = "Sphere"; commit = "enter" }
Write-Output ("[3] UI_INPUT search=Sphere: " + ($typed.result | ConvertTo-Json -Compress -Depth 10))
Wait-Idle
Start-Sleep -Milliseconds 400
$row = Brp-Call "jackdaw/ui_tree" @{ text = "Sphere"; depth = 0 }
if (@($row.result.nodes).Count -lt 1) { throw "typing Sphere surfaced no row" }
$sphere = Brp-Call "jackdaw/ui_click" @{ text = "Sphere" }
Write-Output ("[3] UI_CLICK Sphere row: " + ($sphere.result | ConvertTo-Json -Compress -Depth 10))
Wait-Idle
$scene = Brp-Call "jackdaw/scene_tree" @{ depth = 0 }
$names = @($scene.result.tree | ForEach-Object { $_.name })
Write-Output ("[3] scene roots: " + ($names -join ", "))
if ($names -notcontains "Sphere") { throw "picker flow added no Sphere" }

# --- [4] camera: input.motion under fly, negative then positive ---
$before = Brp-Call "jackdaw/camera_state" @{}
$before = $before.result
Write-Output ("[4] camera before: " + ($before | ConvertTo-Json -Compress))

$fly = $false; $hitX = 0
foreach ($x in 900, 800, 700, 1000, 600) {
    Op "input.pointer" @{ x = $x; y = 500; action = "move" } | Out-Null
    Wait-Idle
    Op "input.pointer" @{ x = $x; y = 500; action = "press"; button = "secondary" } | Out-Null
    Wait-Idle
    $state = Brp-Call "jackdaw/camera_state" @{}
    if ($state.result.fly -eq $true) { $fly = $true; $hitX = $x; break }
    Op "input.pointer" @{ x = $x; y = 500; action = "release"; button = "secondary" } | Out-Null
    Wait-Idle
}
if (-not $fly) { throw "no viewport under probed x positions" }
Write-Output ("[4] fly engaged at x=$hitX")

# [4a] NEGATIVE: one 3000px beat -> warning + gate drops it (yaw unchanged)
Op "input.pointer" @{ action = "rest"; steps = 5 } | Out-Null
Wait-Idle
$neg = Op "input.motion" @{ dx = 3000; dy = 0; steps = 1 }
$negWarn = @($neg.result.warnings)
Write-Output ("[4a] input.motion dx=3000 steps=1 warnings: " + ($negWarn -join " // "))
if (-not ($negWarn | Where-Object { $_ -match "plausible" })) { throw "no >1000px warning" }
Wait-Idle
$afterNeg = Brp-Call "jackdaw/camera_state" @{}
$dyawNeg = [double]$afterNeg.result.yaw - [double]$before.yaw
Write-Output ("[4a] yaw after dropped beat: " + [math]::Round($dyawNeg, 3) + " deg (expect ~0)")

# [4b] NEGATIVE: motion queued behind a still-playing gesture -> warning
Op "input.pointer" @{ action = "rest"; steps = 8 } | Out-Null
$q = Op "input.motion" @{ dx = 40; dy = 0; steps = 4 }
$qWarn = @($q.result.warnings)
Write-Output ("[4b] motion behind a playing rest warnings: " + ($qWarn -join " // "))
Wait-Idle

# [4c] POSITIVE: rest past the 3-frame suppression, then -160px over 16 beats
Op "input.pointer" @{ action = "rest"; steps = 5 } | Out-Null
Wait-Idle
$pos = Op "input.motion" @{ dx = -160; dy = 0; steps = 16 }
Write-Output ("[4c] input.motion dx=-160 steps=16 warnings: " + (@($pos.result.warnings) -join " // "))
Wait-Idle
Op "input.pointer" @{ x = $hitX; y = 500; action = "release"; button = "secondary" } | Out-Null
Wait-Idle
$after = Brp-Call "jackdaw/camera_state" @{}
$dyaw = [double]$after.result.yaw - [double]$before.yaw
$dpitch = [double]$after.result.pitch - [double]$before.pitch
Write-Output ("[4c] yaw " + [math]::Round($before.yaw, 3) + " -> " + [math]::Round($after.result.yaw, 3) + " (delta " + [math]::Round($dyaw, 3) + " deg); pitch delta " + [math]::Round($dpitch, 3))
if ([math]::Abs($dyaw) -lt 1.0) { throw "input.motion did not turn the camera (delta $dyaw)" }

# --- [5] ambiguity refusal ---
$amb = Brp-Call "jackdaw/ui_click" @{ text = "Add" }
if (-not $amb.error) { throw "ambiguous 'Add' did not refuse" }
Write-Output ("[5] ambiguous text=Add error: " + $amb.error.message)

Write-Output "QA-LIVE PASS"
