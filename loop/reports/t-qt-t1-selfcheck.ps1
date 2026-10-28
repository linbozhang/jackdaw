# T-QT-T1 lightweight live self-check: ui_click on a real menu, input.motion look.
# Not a gate; the dogfood suite is T-QT-T2. Prints numbers for the report.
param(
    [string]$Exe = "E:\Project\rust\jackdaw\target\debug\jackdaw.exe",
    [int]$Port = 15794
)
$ErrorActionPreference = "Stop"

# --- BRP helpers (watching semantics: null result -> resend same params) ---
function Brp-Call([string]$Method, $Params, [int]$TimeoutSec = 30) {
    $body = @{ jsonrpc = "2.0"; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $raw = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 20
        if ($null -ne $raw.error) { throw "$Method refused: $($raw.error | ConvertTo-Json -Compress)" }
        if ($null -ne $raw.result) { return $raw.result }
        Start-Sleep -Milliseconds 120
    }
    throw "timeout waiting for $Method $Params"
}
function Wait-Idle() { Brp-Call "jackdaw/wait" @{ until = "idle" } 60 | Out-Null }

# --- a scratch project + the editor on its own port ---
$Project = Join-Path $env:TEMP "t-qt-t1-selfcheck-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $Project "assets"), (Join-Path $Project ".jackdaw") | Out-Null
Set-Content (Join-Path $Project ".jackdaw/project.json") '{"name":"t-qt-t1-selfcheck"}'
Set-Content (Join-Path $Project "Cargo.toml") "[package]`nname = `"selfcheck`"`nversion = `"0.1.0`"`nedition = `"2021`"`n`n[dependencies]`n"

$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_SKIP_SETUP_CHECK = "1"
$editor = Start-Process -FilePath $Exe -PassThru
try {
    # --- ready ---
    $ready = $false
    for ($i = 0; $i -lt 240; $i++) {
        try { $status = Brp-Call "jackdaw/status" @{} 5; $ready = $true; break } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $ready) { throw "editor never answered on $Port" }
    Write-Output ("READY pid=" + $editor.Id + " port=" + $Port)
    Wait-Idle

    # A Cargo project that was never set up opens on a setup dialog; its
    # "Open without setup" button is the first real control ui_click drives.
    $open = Brp-Call "jackdaw/ui_click" @{ text = "Open without setup" }
    Write-Output ("UI_CLICK setup dialog: " + ($open | ConvertTo-Json -Compress -Depth 10))
    Wait-Idle
    Wait-Idle

    # --- 1. ui_click + ui_input through real chrome: the Add Entity picker ---
    $add = Brp-Call "jackdaw/ui_click" @{ text = "Add Entity" }
    Write-Output ("UI_CLICK Add Entity: " + ($add | ConvertTo-Json -Compress -Depth 10))
    Wait-Idle

    $menu = Brp-Call "jackdaw/ui_tree" @{ text = "3D Objects"; depth = 1 }
    Write-Output ("UI_TREE 3D Objects: " + ($menu | ConvertTo-Json -Compress -Depth 10))
    if ($menu.nodes.Count -lt 1) { throw "Add Entity opened no picker with a 3D Objects row" }

    # The picker has a search field; type into it and click the filtered item.
    $inputs = Brp-Call "jackdaw/ui_tree" @{ kind = "text_input"; depth = 0 }
    $search = $null
    foreach ($n in $inputs.nodes) {
        if ($n.rect -and [double]$n.rect[2] -gt 400.0) { $search = $n; break }
    }
    if (-not $search) { throw "no wide text input (the picker search) among $($inputs.nodes.Count) inputs" }
    $typed = Brp-Call "jackdaw/ui_input" @{ entity = [UInt64]$search.entity; text = "Cube"; commit = "enter" }
    Write-Output ("UI_INPUT search: " + ($typed | ConvertTo-Json -Compress -Depth 10))
    Wait-Idle
    Start-Sleep -Milliseconds 500

    $cubeRow = Brp-Call "jackdaw/ui_tree" @{ text = "Cube"; depth = 0 }
    Write-Output ("UI_TREE Cube row: " + ($cubeRow | ConvertTo-Json -Compress -Depth 10))
    if ($cubeRow.nodes.Count -lt 1) { throw "typing Cube in the picker search surfaced no Cube row" }

    $cube = Brp-Call "jackdaw/ui_click" @{ text = "Cube" }
    Write-Output ("UI_CLICK Cube: " + ($cube | ConvertTo-Json -Compress -Depth 10))
    Wait-Idle

    $tree = Brp-Call "jackdaw/scene_tree" @{ depth = 0 }
    $names = @($tree.tree | ForEach-Object { $_.name })
    Write-Output ("SCENE_ROOTS: " + ($names -join ", "))
    if ($names -notcontains "Cube") { throw "the picker flow did not add a Cube (roots: $($names -join ', '))" }
    Write-Output "PASS ui_click/ui_input: Add Entity -> search Cube -> scene has Cube"

    # --- 2. input.motion turns the camera: press RMB over the viewport, rest, motion ---
    $before = Brp-Call "jackdaw/camera_state" @{}
    Write-Output ("CAMERA before: " + ($before | ConvertTo-Json -Compress))

    $fly = $false; $hitX = 0
    foreach ($x in 900, 800, 700, 1000, 600) {
        Brp-Call "jackdaw/call_operator" @{ id = "input.pointer"; params = @{ x = $x; y = 500; action = "move" } } | Out-Null
        Wait-Idle
        Brp-Call "jackdaw/call_operator" @{ id = "input.pointer"; params = @{ x = $x; y = 500; action = "press"; button = "secondary" } } | Out-Null
        Wait-Idle
        $state = Brp-Call "jackdaw/camera_state" @{}
        if ($state.fly -eq $true) { $fly = $true; $hitX = $x; break }
        Brp-Call "jackdaw/call_operator" @{ id = "input.pointer"; params = @{ x = $x; y = 500; action = "release"; button = "secondary" } } | Out-Null
        Wait-Idle
    }
    if (-not $fly) { throw "no viewport found under any probed x" }
    Write-Output ("FLY engaged at x=" + $hitX)

    # rest past the 3-frame suppression window, then small beats of motion
    Brp-Call "jackdaw/call_operator" @{ id = "input.pointer"; params = @{ action = "rest"; steps = 5 } } | Out-Null
    Wait-Idle
    Brp-Call "jackdaw/call_operator" @{ id = "input.motion"; params = @{ dx = 240; dy = 0; steps = 24 } } | Out-Null
    Wait-Idle
    Brp-Call "jackdaw/call_operator" @{ id = "input.pointer"; params = @{ x = $hitX; y = 500; action = "release"; button = "secondary" } } | Out-Null
    Wait-Idle

    $after = Brp-Call "jackdaw/camera_state" @{}
    Write-Output ("CAMERA after: " + ($after | ConvertTo-Json -Compress))
    $dyaw = [math]::Abs([double]$after.yaw - [double]$before.yaw)
    Write-Output ("YAW before=" + $before.yaw + " after=" + $after.yaw + " delta=" + [math]::Round($dyaw, 2))
    if ($dyaw -lt 1.0) { throw "input.motion did not turn the camera (delta $dyaw deg)" }
    Write-Output "PASS input.motion: yaw turned"

    Write-Output "SELFCHECK PASS"
}
finally {
    if (-not $editor.HasExited) { Stop-Process -Id $editor.Id -Force }
    Remove-Item -Recurse -Force $Project -ErrorAction SilentlyContinue
}
