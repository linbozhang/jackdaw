# T02-T1 QA device spot check: an edit in flight while the selection moves must
# never land on the entity the user moved to (Cube2), and per ruling 1 the edit
# bound to the old entity (Cube) is dropped loudly.
#
# Round 1 (natural blur race): focus Cube.translation.y, type 9, then ONE click
#   on Cube2's outliner row -- blur commit and selection change contend.
# Round 2 (deterministic drop): batch [input.key Enter, field.set on Cube2]
#   moves the selection synchronously while the Enter beat is still queued.
param(
    [int]$Port = 15713,
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [string]$OutDir = 'E:\Project\rust\jackdaw\loop\reports\t02t1-race',
    [string]$ConsoleLog = 'E:\Project\rust\jackdaw\loop\reports\t02t1-race\console.log'
)
$ErrorActionPreference = 'Stop'
. 'E:\Project\rust\jackdaw\loop\qa\brp.ps1' -Port $Port

function Invoke-BrpRaw([string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 12 -Compress
    $w = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing -TimeoutSec 30
    return [System.Text.Encoding]::UTF8.GetString($w.RawContentStream.ToArray()) | ConvertFrom-Json
}
function Op([string]$Id, $Params) {
    $r = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = $Id; params = $Params })
    if ($Id -like 'window.*' -or $Id -like 'panel.*') { Write-Host ("op {0}: {1}" -f $Id, ($r | ConvertTo-Json -Depth 6 -Compress)) }
}
function Click-At([double]$x, [double]$y) { Op 'input.pointer' @{ x = $x; y = $y; action = 'click' } }
function Type-Text([string]$t) { Op 'input.text' @{ text = $t } }
function Key([string]$k) { Op 'input.key' @{ key = $k } }
function Wait-Frames([int]$n) {
    try { Wait-BrpResult 'jackdaw/wait' @{ frames = $n } -TimeoutSec 20 | Out-Null } catch { Start-Sleep -Milliseconds 200 }
}
function Wait-Idle { try { Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 60 | Out-Null } catch { Start-Sleep -Seconds 2 } }
function Get-UiRows {
    # Visibility filter: a maximized panel hides its siblings, but the hidden
    # nodes keep their old ComputedNode, so text at stale positions would fool
    # the row finders. Fall back to the unfiltered query when the Visibility
    # shape is not what we expect.
    $j = Invoke-BrpRaw 'world.query' @{ data = @{ components = @('bevy_ui::widget::text::Text', 'bevy_ui::ui_node::ComputedNode', 'bevy_ui::ui_transform::UiGlobalTransform'); option = @('bevy_render::view::Visibility') } }
    $all = @($j.result)
    if ($all.Count -gt 0 -and $all[0].components.'bevy_render::view::Visibility') {
        ($all[0].components.'bevy_render::view::Visibility' | ConvertTo-Json -Depth 4) | Out-File (Join-Path $OutDir 'visibility-shape.txt') -Encoding utf8
    }
    $visible = $all | Where-Object {
        $_.components.'bevy_ui::ui_node::ComputedNode'.size[0] -gt 0 -and
        "$($_.components.'bevy_render::view::Visibility'.is_visible)" -ne 'False'
    }
    if (@($visible).Count -eq 0) { $visible = $all | Where-Object { $_.components.'bevy_ui::ui_node::ComputedNode'.size[0] -gt 0 } }
    return $visible | ForEach-Object {
        $a = $_.components.'bevy_ui::ui_transform::UiGlobalTransform'
        $s = $_.components.'bevy_ui::ui_node::ComputedNode'.size
        [pscustomobject]@{ text = $_.components.'bevy_ui::widget::text::Text'; cx = [double]$a[4]; cy = [double]$a[5]; w = [double]$s[0]; h = [double]$s[1] }
    }
}
function Get-SceneBsn {
    $r = (Invoke-BrpRaw 'jackdaw/scene_bsn' @{}).result
    if ($r -is [string]) { return $r }
    return [string]$r.bsn
}
# Translation of the FIRST entity block named $Name (exact line '#<Name>').
function Get-EntityTranslation([string]$bsn, [string]$Name) {
    $idx = $bsn.IndexOf("#$Name`n")
    if ($idx -lt 0) { $idx = $bsn.IndexOf("#$Name`r") }
    if ($idx -lt 0) { return $null }
    $chunk = $bsn.Substring($idx, [Math]::Min(2500, $bsn.Length - $idx))
    if ($chunk -match 'translation:\s*glam::Vec3\s*\{\s*x:\s*([-\d.eE+]+),\s*y:\s*([-\d.eE+]+),\s*z:\s*([-\d.eE+]+)') {
        return @{ x = [double]$Matches[1]; y = [double]$Matches[2]; z = [double]$Matches[3] }
    }
    return $null
}
function Shot([string]$relName) {
    try {
        $r = Wait-BrpResult 'jackdaw/screenshot' @{ kind = 'window'; path = "screenshots/$relName" } -TimeoutSec 20
        Copy-Item "$Project\screenshots\$relName" (Join-Path $OutDir $relName) -Force
        Write-Host ("shot {0}" -f $relName)
    } catch { Write-Host "shot skipped: $_" }
}
function Get-ScaleFactor {
    try {
        $j = Invoke-BrpRaw 'world.query' @{ data = @{ components = @('bevy_window::window::Window') }; filter = @{ with = @('bevy_window::window::PrimaryWindow') } }
        $row = @($j.result)[0]
        if ($row) {
            $raw = $row.components.'bevy_window::window::Window' | ConvertTo-Json -Depth 6
            $raw | Out-File (Join-Path $OutDir 'window-raw.json') -Encoding utf8
            $sf = $row.components.'bevy_window::window::Window'.scale_factor
            if ($sf) { return [double]$sf }
        }
    } catch { Write-Host "scale probe failed: $_" }
    return 1.0
}
function Find-OutlinerRow([string]$Name) {
    $rows = Get-UiRows
    $hit = $rows | Where-Object { $_.text -eq $Name -and $_.cx -lt 400 -and $_.cy -gt 150 } | Sort-Object cy | Select-Object -First 1
    if (-not $hit) { throw "no outliner row '$Name'" }
    return $hit
}
# The translation.y input on the selected entity's Transform card: the row's
# second numeric value text (x, y, z), clicked directly the way r3 did. Falls
# back to the axis-letter offset when the value texts are clipped away.
function Find-TranslationYField {
    $rows = Get-UiRows
    # Layout changes leave stale nodes at the old strip position: when several
    # candidates match, the rightmost is the live one.
    $panel = $rows | Sort-Object cy
    $label = $panel | Where-Object { $_.text -eq 'translation' } | Sort-Object cx -Descending | Select-Object -First 1
    if (-not $label) {
        # The card may start collapsed: its header toggles it. Expand, wait,
        # and look again.
        $header = $panel | Where-Object { $_.text -eq 'Transform' } | Sort-Object cx -Descending | Select-Object -First 1
        if ($header) {
            Click-At ($header.cx / $script:Scale) ($header.cy / $script:Scale)
            Wait-Frames 6; Start-Sleep -Milliseconds 500
            $rows = Get-UiRows
            $panel = $rows | Sort-Object cy
            $label = $panel | Where-Object { $_.text -eq 'translation' } | Sort-Object w -Descending | Select-Object -First 1
        }
    }
    if (-not $label) {
        $panel | Where-Object { $_.cx -gt 1100 } | ForEach-Object { Write-Host ('  dbg {0,7:N0} {1,7:N0} w={2,5:N0}  [{3}]' -f $_.cx, $_.cy, $_.w, $_.text) }
        Shot 't02t1-dbg-panel.png'
        throw 'no translation row in inspector'
    }
    $band = $panel | Where-Object {
        $_.cy -gt $label.cy -and $_.cy -lt ($label.cy + 40) -and
        [math]::Abs($_.cx - $label.cx) -lt 350
    }
    # Values may carry a typographic minus; the letter labels give the
    # x/y/z order when not all three value texts are measurable.
    $values = $band | Where-Object { $_.text -match '^[-−+]?[\d.]+$' } | Sort-Object cx
    $y = $band | Where-Object { $_.text -eq 'Y' } | Select-Object -First 1
    if (@($values).Count -ge 3) {
        Write-Host ("  y-field: value text '{0}' at ({1:N0},{2:N0})" -f $values[1].text, $values[1].cx, $values[1].cy)
        return $values[1]
    }
    if ($y -and @($values).Count -ge 1) {
        # The value right of the Y letter (or the nearest one after it).
        $after = $values | Where-Object { $_.cx -gt $y.cx } | Select-Object -First 1
        if ($after) {
            Write-Host ("  y-field: value text '{0}' at ({1:N0},{2:N0}) after the Y label" -f $after.text, $after.cx, $after.cy)
            return $after
        }
    }
    if ($y) {
        # Last resort: the letter is a label left of its value input; click
        # into the value box.
        Write-Host ("  y-field: falling back to Y label offset at ({0:N0},{1:N0})" -f ($y.cx + 25), $y.cy)
        return [pscustomobject]@{ cx = $y.cx + 25; cy = $y.cy }
    }
    $near = $panel | Where-Object { $_.cy -ge ($label.cy - 5) -and $_.cy -le ($label.cy + 60) }
    $near | ForEach-Object { Write-Host ('  dbg {0,7:N0} {1,7:N0} w={2,5:N0}  [{3}]' -f $_.cx, $_.cy, $_.w, $_.text) }
    Shot 't02t1-dbg-panel.png'
    throw 'no translation value or Y label found'
}
function Drop-WarnCount {
    if (-not (Test-Path $ConsoleLog)) { return 0 }
    return (Select-String -Path $ConsoleLog -Pattern 'field edit dropped: its entity left the selection' -SimpleMatch -ErrorAction SilentlyContinue | Measure-Object).Count
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (Test-Path $ConsoleLog) { Remove-Item $ConsoleLog -Force }

# --- boot ---------------------------------------------------------------
Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$p = Start-Process -FilePath $Exe -WorkingDirectory $Project -RedirectStandardError "$ConsoleLog.err" -RedirectStandardOutput "$ConsoleLog.out" -PassThru
try {
    Wait-EditorReady   # from brp.ps1
    Wait-Idle
    $script:Scale = Get-ScaleFactor
    Write-Host ("editor ready (scale factor {0})" -f $script:Scale)
    # Give the inspector dock room: reset layout, open + maximize the panel so
    # its content column is fully laid out (the saved layout squeezes it to a
    # rail).
    Op 'window.reset_layout' @{}
    Wait-Frames 10; Start-Sleep -Milliseconds 600
    Op 'window.open' @{ window_id = 'jackdaw.inspector.components' }
    Wait-Frames 10; Start-Sleep -Milliseconds 600; Wait-Idle

    $warnBase = 0  # console log file is fresh; drops counted from zero

    # Both rounds: the maximized inspector hides the outliner, so selection
    # moves BRP-side through field.set (which selects its target first), while
    # the edit itself goes through the real focused text widget:
    #   1. field.set <A> (its current z) -> selects A, shows A's card
    #   2. click A's translation.y, type <value>
    #   3. batch [input.key Enter, field.set <B> (its current z)] -> the Enter
    #      beat is still queued when the selection already moved: the race.
    # Invariant under ruling 1: B's translation.y must never be written; A's
    # edit either lands on A (commit ran first) or is dropped with the warn.
    function Invoke-RaceRound([string]$Label, [string]$A, [string]$B, [double]$Value) {
        Write-Host "--- round ${Label}: type $Value into $A.translation.y, batch-switch to $B ---"
        $bsn = Get-SceneBsn
        $beforeA = Get-EntityTranslation $bsn $A
        $beforeB = Get-EntityTranslation $bsn $B
        Write-Host ("{0} before:  y={1}" -f $A, $beforeA.y)
        Write-Host ("{0} before: y={1}" -f $B, $beforeB.y)

        # Select A through a no-op value write on another field.
        Op 'field.set' @{ entity = $A; type_path = 'bevy_transform::components::transform::Transform'; field = 'translation.z'; value = "$($beforeA.z)" }
        Wait-Frames 8; Start-Sleep -Milliseconds 500

        $yfield = Find-TranslationYField
        Click-At ($yfield.cx / $script:Scale) ($yfield.cy / $script:Scale)
        Wait-Frames 5; Start-Sleep -Milliseconds 300
        Type-Text "$Value"
        Wait-Frames 3; Start-Sleep -Milliseconds 200
        # The typed draft must show in the field; otherwise the click never
        # focused the input and the round proves nothing.
        $draft = Get-UiRows | Where-Object { $_.text -eq "$Value" -and $_.cx -gt 1000 }
        if (-not $draft) {
            Shot 't02t1-dbg-typing.png'
            throw "ROUND ${Label} SETUP FAIL: typed $Value did not reach the field (focus miss)"
        }
        $warnBefore = Drop-WarnCount

        $batch = @{ calls = @(
            @{ id = 'input.key'; params = @{ key = 'Enter' } },
            @{ id = 'field.set'; params = @{ entity = $B; type_path = 'bevy_transform::components::transform::Transform'; field = 'translation.z'; value = "$($beforeB.z)" } }
        ) }
        $null = Brp-Result (Brp-Call 'jackdaw/batch' $batch)
        Wait-Frames 12; Start-Sleep -Milliseconds 800

        $afterA = Get-EntityTranslation (Get-SceneBsn) $A
        $afterB = Get-EntityTranslation (Get-SceneBsn) $B
        $warnAfter = Drop-WarnCount
        Write-Host ("{0} after:  y={1} (before {2})" -f $A, $afterA.y, $beforeA.y)
        Write-Host ("{0} after: y={1} (before {2})  MUST be unchanged" -f $B, $afterB.y, $beforeB.y)
        Write-Host ("drop warns: {0} -> {1}" -f $warnBefore, $warnAfter)
        Shot ("t02t1-r{0}-after.png" -f $Label)
        if ([math]::Abs($afterB.y - $beforeB.y) -gt 1e-4) {
            throw "ROUND ${Label} FAIL: $B.translation.y changed from $($beforeB.y) to $($afterB.y) -- edit leaked to the new target"
        }
        if ([math]::Abs($afterA.y - $beforeA.y) -gt 1e-4) {
            Write-Host ("ROUND ${Label} NOTE: {0} edit committed before the selection moved (acceptable ordering; invariant held)" -f $A)
        } elseif ($warnAfter -gt $warnBefore) {
            Write-Host "ROUND ${Label} PASS: edit dropped loudly (warn seen)"
        } else {
            throw "ROUND ${Label} FAIL: $A edit vanished with no drop warn"
        }
    }

    Invoke-RaceRound 1 'Cube' 'Cube2' 9
    Invoke-RaceRound 2 'Cube' 'Cube3' 11
    Write-Host 'DEVICE SPOT CHECK DONE'
}
finally {
    Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force
}

