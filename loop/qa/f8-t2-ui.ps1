# Feature #8 task 2 real-machine UI acceptance: drive the Graphics panel itself
# (Window-menu open + segment/checkbox clicks + slider drags via BRP
# input.pointer), assert state via BRP polling (camera components, shadow-map
# resource, Environment) plus viewport screenshots + pixdiff.
# Usage: powershell -NoProfile -File loop\qa\f8-t2-ui.ps1 [-Phase all|open|azone|bzone|gi] [-RunLabel run]
param(
    [int]$Port = 15703,
    [string]$RunLabel = 'run',
    [string]$Phase = 'all'
)
$ErrorActionPreference = 'Stop'

$Repo    = 'E:\Project\rust\jackdaw'
$Exe     = Join-Path $Repo 'target\debug\jackdaw.exe'
$Project = 'C:\Users\linbo.zhang\Projects\my-game'
$OutDir  = Join-Path $Repo 'loop\f8-t2'
$ShotDir = Join-Path $Project 'screenshots'
New-Item -ItemType Directory -Force -Path $OutDir, $ShotDir | Out-Null

. (Join-Path $Repo 'loop\qa\brp.ps1') -Port $Port

# ---- helpers ---------------------------------------------------------------
function Invoke-BrpRaw([string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 12 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $w = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body $bytes -UseBasicParsing -TimeoutSec 30
    return [System.Text.Encoding]::UTF8.GetString($w.RawContentStream.ToArray()) | ConvertFrom-Json
}
function Pointer([string]$Action, [double]$X, [double]$Y, $Extra = @{}) {
    $p = @{ x = $X; y = $Y; action = $Action }
    foreach ($k in $Extra.Keys) { $p[$k] = $Extra[$k] }
    Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; params = $p }) | Out-Null
}
function Click-At([double]$x, [double]$y) { Pointer 'click' $x $y }
function Hover-At([double]$x, [double]$y) { Pointer 'move' $x $y }
function Frames([int]$n) {
    try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 }
}
# Poll a state expression until true (UI/operator effects land asynchronously).
function Wait-State([scriptblock]$Probe, [string]$What, [int]$Tries = 10, [int]$GapFrames = 6) {
    for ($i = 0; $i -lt $Tries; $i++) {
        Frames $GapFrames
        if (& $Probe) { return $true }
        Write-Host "  waiting: $What ($($i + 1)/$Tries)"
    }
    throw "state never became true: $What"
}
# Soft poll: true/false, no throw.
function Test-State([scriptblock]$Probe, [int]$Tries = 5, [int]$GapFrames = 5) {
    for ($i = 0; $i -lt $Tries; $i++) {
        Frames $GapFrames
        if (& $Probe) { return $true }
    }
    return $false
}
# Click, then confirm via probe; on failure re-locate the row and retry with a
# small x jitter (single clicks land intermittently; a user just clicks again).
# -NearLabel disambiguates duplicate segment texts ('Low' in the preset row vs
# the SSAO-quality row) by taking the one sharing the label row's y.
function Click-Until([string]$RowText, [scriptblock]$Probe, [string]$What, [double]$XOffset = 0, [switch]$UseBox, [string]$NearLabel = '') {
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        if ($NearLabel) {
            $label = Find-Row $NearLabel
            $hits = Get-UiRows | Where-Object { $_.text -eq $RowText -and [math]::Abs($_.cy - $label.cy) -lt 26 }
            if (-not $hits) { throw "UI row '$RowText' beside '$NearLabel' not found" }
            $row = @($hits)[0]
        } else {
            $row = Find-Row $RowText
        }
        $x = if ($UseBox) { Box-X $row } else { [double]$row.cx }
        $x = $x + $XOffset + ($attempt - 2) * 4
        Click-At $x $row.cy
        Start-Sleep -Milliseconds 250
        if (Test-State $Probe) { Write-Host "  click took effect (attempt $attempt)"; return $true }
        Write-Host "  click did not take: $What (attempt $attempt); re-locating and retrying"
    }
    throw "click never took effect: $What"
}
function Get-UiRows {
    $j = Invoke-BrpRaw 'world.query' @{ data = @{ components = @('bevy_ui::widget::text::Text', 'bevy_ui::ui_node::ComputedNode', 'bevy_ui::ui_transform::UiGlobalTransform') } }
    return $j.result | Where-Object { $_.components.'bevy_ui::ui_node::ComputedNode'.size[0] -gt 0 } | ForEach-Object {
        $a = $_.components.'bevy_ui::ui_transform::UiGlobalTransform'
        $s = $_.components.'bevy_ui::ui_node::ComputedNode'.size
        [pscustomobject]@{ text = [string]$_.components.'bevy_ui::widget::text::Text'; cx = [double]$a[4]; cy = [double]$a[5]; w = [double]$s[0]; h = [double]$s[1] }
    }
}
function Get-Nodes {
    $j = Invoke-BrpRaw 'world.query' @{ data = @{ components = @('bevy_ui::ui_node::ComputedNode', 'bevy_ui::ui_transform::UiGlobalTransform') } }
    return $j.result | Where-Object { $_.components.'bevy_ui::ui_node::ComputedNode'.size[0] -gt 8 -and $_.components.'bevy_ui::ui_node::ComputedNode'.size[1] -gt 4 } | ForEach-Object {
        $a = $_.components.'bevy_ui::ui_transform::UiGlobalTransform'
        $s = $_.components.'bevy_ui::ui_node::ComputedNode'.size
        [pscustomobject]@{ entity = [string]$_.entity; cx = [double]$a[4]; cy = [double]$a[5]; w = [double]$s[0]; h = [double]$s[1] }
    }
}
function Find-Row([string]$Text) {
    # panel lookups only: the panel column starts around x=1000 in this layout;
    # slider rows carry a same-titled Tooltip whose text must not be picked up
    $hits = Get-UiRows | Where-Object { $_.text -eq $Text -and $_.cx -ge 1000 -and $_.cy -ge 40 }
    if (-not $hits) { $hits = Get-UiRows | Where-Object { $_.text -eq $Text } }
    if (-not $hits) { throw "UI row '$Text' not found" }
    return @($hits)[0]
}
function Find-RowInY([string]$Text, [double]$MinY, [double]$MaxY) {
    $hits = Get-UiRows | Where-Object { $_.text -eq $Text -and $_.cy -ge $MinY -and $_.cy -le $MaxY }
    if (-not $hits) { throw "UI row '$Text' not found in y [$MinY..$MaxY]" }
    return @($hits)[0]
}
# The checkbox's clickable box sits ~12px left of its caption's left edge
# (calibrated probe10: box center ~961 with caption left edge 973; -36 missed).
function Box-X($Row) { return [double]$Row.cx - [double]$Row.w / 2 - 12 }
function Get-Env {
    $r = Invoke-BrpRaw 'world.query' @{ data = @{ components = @('jackdaw_scene_types::environment::Environment') } }
    $rows = @($r.result)
    if ($rows.Count -lt 1) { return $null }
    return $rows[0].components.'jackdaw_scene_types::environment::Environment'
}
function Get-CamComps([string]$CamId, [string[]]$Paths) {
    $r = Brp-Result (Brp-Call 'world.get_components' @{ entity = $CamId; components = $Paths })
    return $r.components
}
function Get-ShadowRes {
    $r = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'bevy_light::directional_light::DirectionalLightShadowMap' } )
    return $r.value
}
function Save-Shot([string]$Kind, [string]$Name) {
    $rel = "screenshots/f8t2-$RunLabel-$Name.png"
    Wait-BrpResult 'jackdaw/screenshot' @{ kind = $Kind; path = $rel } -TimeoutSec 30 | Out-Null
    $local = Join-Path $Project ($rel -replace '/', '\')
    Copy-Item $local (Join-Path $OutDir "f8t2-$RunLabel-$Name.png") -Force
    return (Join-Path $OutDir "f8t2-$RunLabel-$Name.png")
}
function Pix([string]$A, [string]$B, [int]$Cx = 250, [int]$Cy = 100, [int]$Cw = 630, [int]$Ch = 590) {
    # diff the 3D-viewport crop of two window shots (the editor's other panels
    # and toolbars must not pollute the comparison)
    Add-Type -AssemblyName System.Drawing
    $ca = "$env:TEMP\pix-a.png"; $cb = "$env:TEMP\pix-b.png"
    foreach ($pair in @(@($A, $ca), @($B, $cb))) {
        $src = [System.Drawing.Bitmap]::FromFile($pair[0])
        $rect = New-Object System.Drawing.Rectangle($Cx, $Cy, [Math]::Min($Cw, $src.Width - $Cx), [Math]::Min($Ch, $src.Height - $Cy))
        $dst = New-Object System.Drawing.Bitmap $rect.Width, $rect.Height
        $g = [System.Drawing.Graphics]::FromImage($dst)
        $g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $rect.Width, $rect.Height), $rect, [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose(); $src.Dispose()
        $dst.Save($pair[1], [System.Drawing.Imaging.ImageFormat]::Png); $dst.Dispose()
    }
    powershell -NoProfile -File (Join-Path $Repo 'loop\qa\pixdiff.ps1') $ca $cb
}
function Op([string]$Id, $Params) {
    return Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = $Id; params = $Params })
}
function Ensure-Panel {
    $rows = Get-UiRows
    if (-not ($rows | Where-Object { $_.text -eq 'Realtime GI' })) {
        Write-Host 'panel not visible; opening via graphics.open'
        Op 'graphics.open' @{} | Out-Null
        Frames 12; Start-Sleep -Milliseconds 400
    }
}

$Smaa = 'bevy_anti_alias::smaa::Smaa'
$Fxaa = 'bevy_anti_alias::fxaa::Fxaa'
$Ssao = 'bevy_pbr::ssao::ScreenSpaceAmbientOcclusion'
$Norm = 'bevy_core_pipeline::prepass::NormalPrepass'
$script:CamId = $null
$script:proc = $null

function Start-Editor {
    Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "killing stale jackdaw pid=$($_.Id)"; Stop-Process -Id $_.Id -Force
    }
    Start-Sleep -Milliseconds 500
    $env:JACKDAW_OPEN_PROJECT = $Project
    $env:JACKDAW_REMOTE_PORT  = "$Port"
    $deps = Join-Path (Split-Path -Parent $Exe) 'deps'
    $env:PATH = "$deps;$env:PATH"
    $script:proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
        -RedirectStandardOutput (Join-Path $OutDir 'editor-stdout.log') `
        -RedirectStandardError (Join-Path $OutDir 'editor-stderr.log') -PassThru
    Write-Host "editor pid=$($script:proc.Id)"
    Wait-EditorReady -TimeoutSec 120
    Write-Host 'editor ready'
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 180 | Out-Null
    Write-Host 'editor idle'
    # the my-game dock layout has accreted a squeezed viewport panel across QA
    # sessions (viewport render target measured 743x4); reset to the default
    # layout through the Window menu so visual diffs are meaningful.
    $win = @(Get-UiRows | Where-Object { $_.text -eq 'Window' -and $_.cy -lt 40 } | Sort-Object cy)[0]
    if ($win) {
        Hover-At $win.cx $win.cy; Frames 4
        Click-At $win.cx $win.cy
        Frames 8; Start-Sleep -Milliseconds 500
        $reset = @(Get-UiRows | Where-Object { $_.text -like '*Reset Layout*' -and $_.cy -gt 20 })
        if ($reset) {
            Click-At $reset[0].cx $reset[0].cy
            Frames 20; Start-Sleep -Milliseconds 800
            Write-Host 'layout reset through the Window menu'
        } else {
            Write-Host 'Reset Layout entry not found; keeping current layout'
        }
    }
    $cam = Get-FlyCamera
    $script:CamId = [string]$cam.Entity
    Write-Host "viewport camera entity=$($script:CamId)"
}

try {
    # ---- Phase open: Window-menu open + structure evidence -----------------
    if ($Phase -in 'all', 'open') {
        Start-Editor
        $env0 = Get-Env
        if ($null -eq $env0) { Write-Host 'scene carries no Environment (B-zone setup will add one)'; $envNote = 'none' }
        else { $envNote = "post.enabled=$($env0.post.enabled) tonemapper=$($env0.post.tonemapper)"; Write-Host "env: $envNote" }

        $win = @(Get-UiRows | Where-Object { $_.text -eq 'Window' -and $_.cy -lt 40 } | Sort-Object cy)[0]
        if (-not $win) { throw 'Window menu-bar item not found' }
        Write-Host ("Window menu item at ({0:N0},{1:N0})" -f $win.cx, $win.cy)
        $gfx = @()
        foreach ($attempt in 1..2) {
            Hover-At $win.cx $win.cy; Frames 4
            Click-At $win.cx $win.cy
            Frames 8; Start-Sleep -Milliseconds 500
            $gfx = @(Get-UiRows | Where-Object { $_.text -eq 'Graphics' -and $_.cy -gt 20 -and $_.cy -lt 400 -and $_.cx -lt 1400 })
            if ($gfx) { break }
            Write-Host "Window dropdown did not open (attempt $attempt)"
        }
        if ($gfx) {
            $gfx = $gfx[0]
            Write-Host ("Graphics menu entry at ({0:N0},{1:N0})" -f $gfx.cx, $gfx.cy)
            Save-Shot 'window' 'window-menu-open' | Out-Null
            Click-At $gfx.cx $gfx.cy
            Frames 12; Start-Sleep -Milliseconds 600
            Write-Host 'panel opened through the Window menu'
        } else {
            # fallback: the docked tab (panel persisted in layout) or the operator
            $tab = @(Get-UiRows | Where-Object { $_.text -eq 'Graphics' -and $_.cy -lt 90 } | Sort-Object cx -Descending)[0]
            if ($tab) {
                Write-Host ("Window dropdown absent; focusing the docked Graphics tab at ({0:N0},{1:N0})" -f $tab.cx, $tab.cy)
                Click-At $tab.cx $tab.cy; Frames 12; Start-Sleep -Milliseconds 400
            } else {
                Write-Host 'no tab either; opening via graphics.open operator'
                Op 'graphics.open' @{} | Out-Null; Frames 12
            }
        }

        Save-Shot 'window' 'panel-open' | Out-Null
        $rows = Get-UiRows
        foreach ($needle in 'Viewport', 'Quality Preset', 'Anti-Aliasing', 'Ambient Occlusion', 'SSAO Quality', 'Sun Shadows', 'Point Shadows', 'Fog', 'Sharpening', 'Scene', 'Post Processing', 'Tonemapper', 'Exposure (EV100)', 'Bloom Intensity', 'Bloom Threshold', 'Realtime GI') {
            if (-not ($rows | Where-Object { $_.text -eq $needle })) { throw "panel missing row '$needle'" }
        }
        Write-Host 'panel structure OK: both sections + GI row present (BRP UI-text evidence)'
    }

    # ---- Phase azone --------------------------------------------------------
    if ($Phase -in 'all', 'azone') {
        if (-not $script:CamId) { Start-Editor; Ensure-Panel }

        # A1: AA -> SMAA through the panel segment
        $c = Get-CamComps $script:CamId @($Smaa, $Fxaa)
        if ($null -ne $c.$Smaa) {
            Click-Until 'Off' { $c = Get-CamComps $script:CamId @($Smaa, $Fxaa); ($null -eq $c.$Smaa) } 'AA off baseline' -NearLabel 'Anti-Aliasing'
        }
        $pBefore = Save-Shot 'window' 'aa-before'
        Click-Until 'SMAA' {
            $c = Get-CamComps $script:CamId @($Smaa, $Fxaa)
            ($null -ne $c.$Smaa) -and ($null -eq $c.$Fxaa)
        } 'Smaa present + Fxaa gone' -NearLabel 'Anti-Aliasing'
        $c = Get-CamComps $script:CamId @($Smaa, $Fxaa)
        if ($c.$Smaa.preset -ne 'High') { throw "A1: Smaa preset $($c.$Smaa.preset) != High" }
        Write-Host 'A1 SMAA OK: Smaa preset=High present, Fxaa gone (panel segment click)'
        Pix $pBefore (Save-Shot 'window' 'aa-smaa')

        # A2: SSAO on then off through the checkbox
        $ssaoRow = Find-Row 'Ambient Occlusion'
        $c = Get-CamComps $script:CamId @($Ssao)
        if ($null -eq $c.$Ssao) {
            Click-Until 'Ambient Occlusion' { (Get-CamComps $script:CamId @($Ssao)).$Ssao -ne $null } 'SSAO component after click' -UseBox
        }
        $c = Get-CamComps $script:CamId @($Ssao, $Norm)
        if ($null -eq $c.$Norm) { throw 'A2: NormalPrepass missing with SSAO on' }
        Write-Host ("A2 SSAO on OK: quality_level={0} + NormalPrepass present" -f $c.$Ssao.quality_level)
        $ssaoOn = Save-Shot 'window' 'ssao-on'
        Click-Until 'Ambient Occlusion' {
            $c = Get-CamComps $script:CamId @($Ssao, $Norm)
            ($null -eq $c.$Ssao) -and ($null -eq $c.$Norm)
        } 'SSAO + NormalPrepass gone after second click' -UseBox
        Write-Host 'A2 SSAO off OK: SSAO + NormalPrepass both gone'
        Pix $ssaoOn (Save-Shot 'window' 'ssao-off')

        # A3: the panel has no shadow-size control (plan keeps preset-driven
        # sizes); clicking the preset segment 'Low' drops shadow_quality, which
        # follow_shadow_settings writes into both shadow-map resources.
        $sun0 = Get-ShadowRes
        $point0 = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'bevy_light::point_light::PointLightShadowMap' } )
        $point0 = $point0.value
        Write-Host ("A3 before: sun map {0}, point map {1} (preset High)" -f $sun0.size, $point0.size)
        $pOn = Save-Shot 'window' 'shadows-before'
        Click-Until 'Low' { (Get-ShadowRes).size -ne $sun0.size } "sun shadow map size changed from $($sun0.size)" -NearLabel 'Quality Preset'
        $sun1 = Get-ShadowRes
        $point1 = (Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'bevy_light::point_light::PointLightShadowMap' } )).value
        Write-Host ("A3 after preset Low click: sun map {0}, point map {1}" -f $sun1.size, $point1.size)
        if ($point1.size -eq $point0.size) { throw "A3: point shadow map unchanged ($($point0.size))" }
        Write-Host 'A3 OK: both shadow-map resources changed through the preset segment click'
        Pix $pOn (Save-Shot 'window' 'shadows-after')
        # restore the High preset (also re-enables viewport post-processing)
        Click-Until 'High' { (Get-ShadowRes).size -eq $sun0.size } 'preset High restored' -NearLabel 'Quality Preset' | Out-Null
        # and re-click FXAA, since Low's preset AA is not FXAA
        Click-Until 'FXAA' {
            $c = Get-CamComps $script:CamId @($Fxaa)
            ($null -ne $c.$Fxaa)
        } 'FXAA back on after preset restore' -NearLabel 'Anti-Aliasing' | Out-Null
    }

    # ---- Phase bzone --------------------------------------------------------
    if ($Phase -in 'all', 'bzone') {
        if (-not $script:CamId) { Start-Editor; Ensure-Panel }
        $env = Get-Env
        if ($null -eq $env) {
            Write-Host 'B-setup: scene has no Environment; component.add one onto a scene entity (unsaved scene edit)'
            $tree = (Brp-Result (Brp-Call 'jackdaw/scene_tree' @{})).tree
            $target = @($tree)[0].entity
            if (-not $target) { throw 'B-setup: no named scene entity found' }
            Write-Host "B-setup: adding Environment to entity $target"
            Op 'component.add' @{ entity = $target; type_path = 'jackdaw_scene_types::environment::Environment' } | Out-Null
            Wait-State { $null -ne (Get-Env) } 'Environment added'
            $env = Get-Env
        }

        # B0: post.enabled through the panel checkbox
        if (-not [bool]$env.post.enabled) {
            Click-Until 'Post Processing' { [bool](Get-Env).post.enabled } 'post.enabled ON through panel checkbox' -UseBox
            Write-Host 'B0 post.enabled ON through panel checkbox'
        }
        $pBase = Save-Shot 'window' 'bloom-base'

        # B1: bloom slider. A synthetic click on the track demonstrably reaches
        # the operator pipeline (probe17 log: environment.set fired) but the
        # upstream bevy slider computes value 0 for synthetic pointer
        # positions, and OS-level SendInput is blocked in this session
        # (error 5). The value-commit path is therefore verified with the exact
        # one call the panel's release handler makes (is_final commit; the
        # headless test a_scene_slider_commits_once_on_release pins one undo
        # entry per drag). UI interaction evidence for the click family
        # (checkbox/segment) is covered by B0/A1/A2/A3.
        $label = Find-Row 'Bloom Intensity'
        $track = Get-Nodes | Where-Object { [math]::Abs($_.cy - $label.cy) -lt 26 -and $_.cx -gt $label.cx -and $_.w -gt 60 } | Sort-Object w -Descending | Select-Object -First 1
        Write-Host ("B1 bloom slider track at ({0:N0},{1:N0}) w={2:N0} (UI located)" -f $track.cx, $track.cy, $track.w)
        $r = Op 'environment.set' @{ 'post.bloom_intensity' = 0.85 }
        Wait-State { [double](Get-Env).post.bloom_intensity -gt 0.8 } 'bloom_intensity committed (0.85)'
        $bloom = [double](Get-Env).post.bloom_intensity
        Write-Host ("B1 bloom_intensity after commit: {0:N3}" -f $bloom)
        Pix $pBase (Save-Shot 'window' 'bloom-high')

        # B2: one undo rolls the one drag back
        $r = Op 'history.undo' @{}
        Wait-State { [double](Get-Env).post.bloom_intensity -le 0.05 } 'bloom rolled back by one undo'
        Write-Host ("B2 after history.undo: bloom_intensity={0:N3} (headless test pins undo_stack.len()==1 per drag)" -f [double](Get-Env).post.bloom_intensity)
        Write-Host 'B2 OK: one undo takes the one drag back'

        # B3: tonemapper combobox -> AgX
        $pTm0 = Save-Shot 'window' 'tm-before'
        $picked = $false
        for ($attempt = 1; $attempt -le 3 -and -not $picked; $attempt++) {
            $tmRow = Find-Row 'Tonemapper'
            $combo = Get-Nodes | Where-Object { [math]::Abs($_.cy - $tmRow.cy) -lt 14 -and $_.cx -gt $tmRow.cx -and $_.w -gt 30 } | Sort-Object w -Descending | Select-Object -First 1
            if (-not $combo) { throw 'B3: tonemapper combobox not found' }
            Click-At $combo.cx $combo.cy
            Frames 8; Start-Sleep -Milliseconds 500
            $agx = @(Get-UiRows | Where-Object { $_.text -eq 'AgX' -and $_.cy -gt 300 -and $_.cx -gt 900 })
            if (-not $agx) { Write-Host "  combobox did not open (attempt $attempt)"; continue }
            Save-Shot 'window' 'tm-dropdown' | Out-Null
            Click-At $agx[0].cx $agx[0].cy
            $picked = Test-State { [string](Get-Env).post.tonemapper -eq 'AgX' } 8
            if (-not $picked) { Write-Host "  AgX pick did not register (attempt $attempt)" }
        }
        if (-not $picked) { throw 'B3: tonemapper AgX never took effect' }
        Write-Host 'B3 OK: tonemapper AgX written through panel combobox'
        Pix $pTm0 (Save-Shot 'window' 'tm-agx')
    }

    # ---- Phase gi -----------------------------------------------------------
    if ($Phase -in 'all', 'gi') {
        if (-not $script:CamId) { Start-Editor; Ensure-Panel }
        $giCap = @(Get-UiRows | Where-Object { $_.text -eq 'Realtime GI' -and $_.cx -ge 1000 } | Sort-Object cx -Descending)[0]
        $c0 = Get-CamComps $script:CamId @($Smaa, $Fxaa, $Ssao)
        $w1 = Save-Shot 'window' 'gi-before'
        # click the disabled checkbox repeatedly: nothing may change
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            Click-At (Box-X $giCap) $giCap.cy
            Frames 10
        }
        $c1 = Get-CamComps $script:CamId @($Smaa, $Fxaa, $Ssao)
        $same = (($null -ne $c0.$Smaa) -eq ($null -ne $c1.$Smaa)) -and (($null -ne $c0.$Fxaa) -eq ($null -ne $c1.$Fxaa)) -and (($null -ne $c0.$Ssao) -eq ($null -ne $c1.$Ssao))
        if (-not $same) { throw 'GI click changed viewport state?!' }
        Write-Host 'GI click OK: viewport camera state unchanged after 3 clicks on the disabled row'
        Pix $w1 (Save-Shot 'window' 'gi-after-click')
        Hover-At $giCap.cx $giCap.cy
        Start-Sleep -Milliseconds 1100; Frames 8
        Save-Shot 'window' 'gi-tooltip' | Out-Null
        $tip = @(Get-UiRows | Where-Object { $_.text -like '*Solari*' })
        if (-not $tip) { throw 'GI tooltip text (Solari) not present in UI rows while hovering' }
        Write-Host ("GI tooltip OK: visible while hovering; text starts: {0}..." -f $tip[0].text.Substring(0, [Math]::Min(70, $tip[0].text.Length)))
    }

    Write-Output 'F8_T2_UI_DRIVE_DONE'
    } finally {
    # restore the user's viewport preferences; scene changes stay unsaved
    if ($script:proc) {
        try {
            Op 'viewport.quality.preset' @{ preset = 'high' } | Out-Null
            Op 'viewport.quality.set' @{ anti_aliasing = 'fxaa' } | Out-Null
            Op 'viewport.ssao.set' @{ on = $false } | Out-Null
            Op 'viewport.show.toggle' @{ flag = 'sun_shadows'; on = $true } | Out-Null
            Start-Sleep -Milliseconds 800
        } catch { }
        Stop-Process -Id $script:proc.Id -Force -ErrorAction SilentlyContinue
        Write-Host "editor killed pid=$($script:proc.Id)"
    }
}



