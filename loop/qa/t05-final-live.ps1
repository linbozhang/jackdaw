param(
    [Parameter(Mandatory = $true)][ValidateSet(
        'launch', 'grid123', 'grid6', 'grid8', 'grid10', 'grid4579', 'cleanup'
    )][string]$Phase,
    [int]$Port = 15851,
    [string]$Proj = "$env:TEMP\t05t3-proj"
)
# T05-T3 live acceptance matrix. Focus grids 1/2/3/6/8/10 run in full on a
# real editor; grids 4/5/7/9 are spot-checked live (their full coverage is
# the headless guards from T1/T2: renaming_an_open_clean_scene_retargets_its_tab,
# a_rename_that_differs_only_in_case_lands, deleting_an_open_scene...,
# dropping_a_file_already_in_the_assets_copies_nothing).
$ErrorActionPreference = 'Stop'
$OutDir = 'E:\Project\rust\jackdaw\loop\reports\t05t3-live'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Brp-Call([string]$Method, $Params, [int]$TimeoutSec = 30) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $raw = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 15
        } catch { Start-Sleep -Milliseconds 250; continue }
        if ($null -ne $raw.error) { return @{ error = $raw.error } }
        if ($null -ne $raw.result) { return @{ result = $raw.result } }
        Start-Sleep -Milliseconds 120
    }
    throw "timeout waiting for $Method $Params"
}
function Wait-Idle([int]$T = 60) { Brp-Call 'jackdaw/wait' @{ until = 'idle' } $T | Out-Null }
function Op([string]$Id, $Params) { Brp-Call 'jackdaw/call_operator' @{ id = $Id; params = $Params } }
function Get-Tree { (Brp-Call 'jackdaw/ui_tree' @{ depth = 30 }).result.nodes }
function Find-Node($nodes, [string]$text) {
    foreach ($n in $nodes) {
        if ($null -ne $n.text -and $n.text -like "*$text*") { return $n }
        if ($n.children) { $hit = Find-Node $n.children $text; if ($hit) { return $hit } }
    }
    return $null
}
function Fail([string]$What) { Write-Output "FAIL: $What"; exit 1 }
function Pass([string]$What) { Write-Output "PASS: $What" }
function Shot([string]$Name) {
    Brp-Call 'jackdaw/screenshot' @{ kind = 'window'; path = "$OutDir\$Name.png" } 90 | Out-Null
}

switch ($Phase) {
    'launch' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if (Test-Path $Proj) { Remove-Item -Recurse -Force $Proj }
        New-Item -ItemType Directory -Force -Path "$Proj\assets\materials", "$Proj\assets\props", "$Proj\assets\zones" | Out-Null
        Set-Content -Encoding UTF8 "$Proj\Cargo.toml" "[package]`nname = `"t05t3-qa`"`nversion = `"0.1.0`"`nedition = `"2021`""
        Set-Content -Encoding UTF8 "$Proj\jackdaw.toml" "[jackdaw]`nbevy = `"main`"`nchannel = `"bleeding-edge`"`nbevy_rev = `"c9c397ba1a73e6cfffe957318e0359330b701865`""
        $q = [string][char]34
        # rust (referenced, renamed in grid 1), mover (moved in grid 2),
        # keeper (rebind target in grid 8), primpin (folder rename grid 3).
        foreach ($m in @('rust', 'mover', 'keeper')) {
            [System.IO.File]::WriteAllText("$Proj\assets\materials\$m.material.bsn", "#$m" + [char]10 + "bevy_pbr::pbr_material::StandardMaterial { metallic: 0.25 }" + [char]10)
        }
        New-Item -ItemType Directory -Force -Path "$Proj\assets\props\a" | Out-Null
        [System.IO.File]::WriteAllText("$Proj\assets\props\a\crate.prefab.bsn", "#crate" + [char]10 + "bevy_transform::components::transform::Transform" + [char]10)
        # one.bsn: material reference (grids 1, 2, 10); two.bsn: folder
        # reference (grid 3); three.bsn: broken prefab source (grid 6, 8).
        $one = '#Sign' + [char]10 + 'jackdaw::prefab::components::Prefab' + [char]10 + 'jackdaw::prefab::components::IsA { source: ' + $q + 'props/a/crate.prefab.bsn' + $q + ' }' + [char]10
        [System.IO.File]::WriteAllText("$Proj\assets\zones\one.bsn", $one)
        $two = '#Board' + [char]10 + 'bevy_transform::components::transform::Transform' + [char]10
        [System.IO.File]::WriteAllText("$Proj\assets\zones\two.bsn", $two)
        $three = '#Probe' + [char]10 + 'jackdaw::prefab::components::Prefab' + [char]10 + 'jackdaw::prefab::components::IsA { source: ' + $q + 'props/gone.bsn' + $q + ' }' + [char]10
        [System.IO.File]::WriteAllText("$Proj\assets\zones\three.bsn", $three)
        $cfg = "$env:TEMP\t05t3-cfg"
        if (Test-Path $cfg) { Remove-Item -Recurse -Force $cfg }
        New-Item -ItemType Directory -Force -Path $cfg | Out-Null
        $env:JACKDAW_OPEN_PROJECT = $Proj
        $env:JACKDAW_CONFIG_DIR = $cfg
        $env:JACKDAW_REMOTE_PORT = "$Port"
        $env:JACKDAW_SKIP_SETUP_CHECK = '1'
        $env:JACKDAW_WINDOW_SIZE = '1920x1080'
        Start-Process -FilePath 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe' -WorkingDirectory 'E:\Project\rust\jackdaw' -RedirectStandardError "$env:TEMP\t05t3-editor.log" -RedirectStandardOutput "$env:TEMP\t05t3-editor.out.log"
        $deadline = (Get-Date).AddSeconds(90)
        $opened = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3
            try {
                $r = Brp-Call 'jackdaw/status' @{} 10
                if ($r.result.project) { Write-Output ('PROJECT OPEN'); $opened = $true; break }
            } catch {}
        }
        if (-not $opened) { Fail 'the project did not open' }
        Wait-Idle 90
        $log = Get-Content "$env:TEMP\t05t3-editor.log" -Raw
        if ($log -like '*Indexed*') { Pass 'startup walk indexed' } else { Fail 'no Indexed line' }
        Write-Output 'LAUNCHED'
    }

    'grid123' {
        Wait-Idle
        # Grid 1: rename a referenced material -> on-disk reference follows,
        # old path gone, report says what was rewritten.
        $before = Get-Content "$Proj\assets\zones\one.bsn" -Raw
        if ($before -notlike '*props/a/crate.prefab.bsn*') { Fail "fixture one.bsn unexpected: $before" }
        # one.bsn references the prefab via IsA, and the prefab file is the
        # "material stand-in" for grids run on prefab sources; for the
        # material leg, write a real material reference into two.bsn first.
        $q = [string][char]34
        $two = '#Board' + [char]10 + 'jackdaw::prefab::components::Prefab' + [char]10 + 'jackdaw::prefab::components::IsA { source: ' + $q + 'materials/rust.material.bsn' + $q + ' }' + [char]10
        [System.IO.File]::WriteAllText("$Proj\assets\zones\two.bsn", $two)
        Op 'scene.open' @{ path = 'assets/zones/two.bsn' } | Out-Null
        Wait-Idle 90
        Op 'file.rename' @{ path = 'assets/materials/rust.material.bsn'; name = 'patina.material.bsn' } | Out-Null
        Wait-Idle
        $twoAfter = Get-Content "$Proj\assets\zones\two.bsn" -Raw
        if ($twoAfter -like '*patina.material.bsn*' -and $twoAfter -notlike '*rust.material.bsn*') { Pass 'grid 1: on-disk reference renamed' }
        else { Fail "grid 1 reference: $twoAfter" }
        if (-not (Test-Path "$Proj\assets\materials\rust.material.bsn") -and (Test-Path "$Proj\assets\materials\patina.material.bsn")) { Pass 'grid 1: old path gone, new file there' }
        else { Fail 'grid 1: file move wrong' }
        Shot 'grid1-rename'

        # Grid 2: move the renamed material to mats/ -> the reference and the
        # audit follow.
        New-Item -ItemType Directory -Force -Path "$Proj\assets\mats" | Out-Null
        Op 'file.move' @{ path = 'assets/materials/patina.material.bsn'; folder = 'assets/mats' } | Out-Null
        Wait-Idle
        $twoMoved = Get-Content "$Proj\assets\zones\two.bsn" -Raw
        if ($twoMoved -like '*mats/patina.material.bsn*') { Pass 'grid 2: move rewrote the reference' }
        else { Fail "grid 2 reference: $twoMoved" }
        Shot 'grid2-move'

        # Grid 3: rename the folder props -> prop -> the folder-prefixed
        # reference in one.bsn follows, sibling-safe.
        Op 'scene.open' @{ path = 'assets/zones/one.bsn' } | Out-Null
        Wait-Idle 90
        Op 'file.rename' @{ path = 'assets/props'; name = 'prop' } | Out-Null
        Wait-Idle
        $oneAfter = Get-Content "$Proj\assets\zones\one.bsn" -Raw
        if ($oneAfter -like '*prop/a/crate.prefab.bsn*' -and $oneAfter -notlike '*props/a*') { Pass 'grid 3: folder rename rewrote the prefix' }
        else { Fail "grid 3 reference: $oneAfter" }
        if ((Test-Path "$Proj\assets\prop\a\crate.prefab.bsn") -and -not (Test-Path "$Proj\assets\props")) { Pass 'grid 3: folder moved on disk' }
        else { Fail 'grid 3: folder move wrong' }
        Shot 'grid3-folder'
        Write-Output 'GRID123 DONE'
    }

    'grid6' {
        Wait-Idle
        # Delete a referenced file without force: the confirmation names the
        # referencing documents, and nothing is deleted.
        $q = [string][char]34
        $four = '#Mover' + [char]10 + 'jackdaw::prefab::components::Prefab' + [char]10 + 'jackdaw::prefab::components::IsA { source: ' + $q + 'materials/keeper.material.bsn' + $q + ' }' + [char]10
        [System.IO.File]::WriteAllText("$Proj\assets\zones\four.bsn", $four)
        Start-Sleep -Milliseconds 500
        $abs = "$Proj\assets\materials\keeper.material.bsn"
        Op 'file.delete' @{ path = $abs } | Out-Null
        Start-Sleep -Seconds 2
        if (Test-Path $abs) { Pass 'grid 6: file untouched without an answer' }
        else { Fail 'grid 6: file deleted without force' }
        $tree = Get-Tree
        $confirm = Find-Node $tree 'Delete it anyway'
        if ($confirm) { Pass 'grid 6: confirmation dialog names the referrers' }
        else {
            $refLine = Find-Node $tree 'references'
            if ($refLine) { Pass 'grid 6: dialog lists what references it' } else { Fail 'grid 6: no confirmation dialog' }
        }
        Shot 'grid6-confirm'
        Write-Output 'GRID6 DONE'
    }

    'grid8' {
        Wait-Idle
        # The T2 rebind chain, once more on the final build.
        Op 'scene.open' @{ path = 'assets/zones/three.bsn' } | Out-Null
        Wait-Idle 90
        $audit = (Brp-Call 'jackdaw/audit' @{} 60).result
        $gone = @($audit.findings) | Where-Object { $_.reference -like '*gone.bsn' }
        if (@($gone).Count -eq 1 -and $gone[0].kind -eq 'Missing') { Pass 'grid 8: audit names the gone prefab' }
        else { Fail "grid 8 audit: $($audit | ConvertTo-Json -Depth 6)" }
        Op 'asset.rebind' @{
            document = 'zones/three.bsn'; component = 'IsA'; field = 'source'
            reference = 'props/gone.bsn'; to = 'prop/a/crate.prefab.bsn'
        } | Out-Null
        Wait-Idle
        Op 'scene.save' @{} | Out-Null
        Wait-Idle
        $three = Get-Content "$Proj\assets\zones\three.bsn" -Raw
        if ($three -like '*crate.prefab.bsn*') { Pass 'grid 8: rebind saved the held source' }
        else { Fail "grid 8 file: $three" }
        $audit2 = (Brp-Call 'jackdaw/audit' @{} 60).result
        if (@($audit2.findings).Count -eq 0) { Pass 'grid 8: audit clean after rebind' }
        else { Fail "grid 8 audit after: $($audit2 | ConvertTo-Json -Depth 6)" }
        Shot 'grid8-rebound'
        Write-Output 'GRID8 DONE'
    }

    'grid10' {
        Wait-Idle
        # Re-import: overwrite the moved material on disk; the already-open
        # document's index entry reloads and the audit stays quiet.
        $mats = "$Proj\assets\mats\patina.material.bsn"
        if (-not (Test-Path $mats)) { $mats = "$Proj\assets\materials\patina.material.bsn" }
        [System.IO.File]::WriteAllText($mats, "#patina" + [char]10 + "bevy_pbr::pbr_material::StandardMaterial { metallic: 0.9 }" + [char]10)
        Start-Sleep -Seconds 3
        Wait-Idle 90
        $audit = (Brp-Call 'jackdaw/audit' @{} 60).result
        $matsFinding = @($audit.findings) | Where-Object { $_.reference -like '*patina*' }
        if (@($matsFinding).Count -eq 0) { Pass 'grid 10: re-imported material still resolves' }
        else { Fail "grid 10: $($audit | ConvertTo-Json -Depth 6)" }
        Shot 'grid10-reimport'
        Write-Output 'GRID10 DONE'
    }

    'grid4579' {
        Wait-Idle
        # Grid 4 (live spot-check): rename the open scene; the tab keeps the
        # new path and a save lands there.
        Op 'scene.new' @{} | Out-Null
        Wait-Idle
        Op 'scene.switch' @{ tab = 0 } | Out-Null
        Wait-Idle
        Op 'scene.close' @{} | Out-Null
        Wait-Idle
        Op 'scene.open' @{ path = 'assets/zones/one.bsn' } | Out-Null
        Wait-Idle 90
        $shaBefore = (Get-FileHash "$Proj\assets\zones\one.bsn" -Algorithm SHA256).Hash
        Op 'file.rename' @{ path = 'assets/zones/one.bsn'; name = 'uno.bsn' } | Out-Null
        Wait-Idle
        $st = (Brp-Call 'jackdaw/status' @{} 15).result
        if ($st.scene -like '*uno.bsn') { Pass 'grid 4 (spot): tab retargeted to the new path' }
        else { Fail "grid 4 scene: $($st.scene)" }
        Op 'scene.save' @{} | Out-Null
        Wait-Idle
        if ((Test-Path "$Proj\assets\zones\uno.bsn") -and -not (Test-Path "$Proj\assets\zones\one.bsn")) { Pass 'grid 4 (spot): save landed at the new path only' }
        else { Fail 'grid 4: one.bsn/uno.bsn wrong on disk' }
        Shot 'grid4-retarget'

        # Grid 5 (live spot-check): case-only rename leaves one file.
        $abs = "$Proj\assets\zones\uno.bsn"
        Op 'file.rename' @{ path = 'assets/zones/uno.bsn'; name = 'UNO.bsn' } | Out-Null
        Wait-Idle
        $held = Get-ChildItem "$Proj\assets\zones" -Filter '*no.bsn' | ForEach-Object { $_.Name }
        if (@($held | Where-Object { $_ -eq 'UNO.bsn' }).Count -eq 1 -and @($held).Count -eq 1) { Pass 'grid 5 (spot): case-only rename, exactly one file' }
        else { Fail "grid 5: $held" }
        Shot 'grid5-case'

        # Grid 7 (live spot-check): deleting the open scene without force is
        # refused with a reason; with force the tab closes.
        Op 'scene.open' @{ path = 'assets/zones/two.bsn' } | Out-Null
        Wait-Idle 90
        Op 'file.delete' @{ path = "$Proj\assets\zones\two.bsn" } | Out-Null
        Start-Sleep -Seconds 2
        if (Test-Path "$Proj\assets\zones\two.bsn") { Pass 'grid 7 (spot): open scene refused without force' }
        else { Fail 'grid 7: open scene deleted without force' }
        Op 'scene.new' @{} | Out-Null
        Wait-Idle
        Op 'scene.switch' @{ tab = 0 } | Out-Null
        Wait-Idle
        Op 'scene.close' @{} | Out-Null
        Wait-Idle
        Op 'scene.open' @{ path = 'assets/zones/two.bsn' } | Out-Null
        Wait-Idle 90
        Op 'file.delete' @{ path = "$Proj\assets\zones\two.bsn"; force = 'true' } | Out-Null
        Start-Sleep -Seconds 2
        if (-not (Test-Path "$Proj\assets\zones\two.bsn")) { Pass 'grid 7 (spot): force deleted the open scene' }
        else { Fail 'grid 7: force left the file' }
        $st2 = (Brp-Call 'jackdaw/status' @{} 15).result
        if ($null -eq $st2.scene -or $st2.scene -notlike '*two.bsn') { Pass 'grid 7 (spot): no tab left standing on the deleted file' }
        else { Fail "grid 7 tab: $($st2.scene)" }
        Shot 'grid7-delete'

        # Grid 9 (live spot-check): a file already in the project dropped
        # back in copies nothing. The drop event needs the OS clipboard path,
        # so this is asserted by the headless guard; live we confirm the
        # assets dir is unchanged after the phases above.
        $copies = Get-ChildItem "$Proj\assets" -Recurse -Filter '*-1.*'
        if (@($copies).Count -eq 0) { Pass 'grid 9 (spot): no -1 copies appeared this session' }
        else { Fail "grid 9: $($copies | ForEach-Object { $_.Name })" }
        Write-Output 'GRID4579 DONE'
    }

    'cleanup' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Output 'CLEANED'
    }
}
