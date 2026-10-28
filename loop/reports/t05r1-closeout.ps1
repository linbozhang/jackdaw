param(
    [Parameter(Mandatory = $true)][ValidateSet('launch', 'chain', 'cleanup')][string]$Phase,
    [int]$Port = 15841,
    [string]$Proj = "$env:TEMP\t05r1-proj"
)
$ErrorActionPreference = 'Stop'
# T05-T2 rework round 1 live closeout: the full rebind chain on a fixture
# whose bevy pin matches (the QA finding: a stale "0.20" pin put up the
# version-mismatch card and blocked the auto-open).
$OutDir = 'E:\Project\rust\jackdaw\loop\reports\t05r1-live'
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
    throw "timeout waiting for $Method"
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

switch ($Phase) {
    'launch' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if (Test-Path $Proj) { Remove-Item -Recurse -Force $Proj }
        New-Item -ItemType Directory -Force -Path "$Proj\assets\materials", "$Proj\assets\props", "$Proj\assets\zones" | Out-Null
        Set-Content -Encoding UTF8 "$Proj\Cargo.toml" "[package]`nname = `"t05r1-qa`"`nversion = `"0.1.0`"`nedition = `"2021`""
        # The pin the running editor reports (my-game's), so the mismatch
        # card does not block the auto-open.
        Set-Content -Encoding UTF8 "$Proj\jackdaw.toml" "[jackdaw]`nbevy = `"main`"`nchannel = `"bleeding-edge`"`nbevy_rev = `"c9c397ba1a73e6cfffe957318e0359330b701865`""
        # An asset of its own (the index has something to say "Indexed"
        # about), a held prefab, and a scene whose instance names one the
        # project does not hold.
        $q = [string][char]34
        $material = '#rust' + [char]10 + 'bevy_pbr::pbr_material::StandardMaterial { metallic: 0.25 }' + [char]10
        [System.IO.File]::WriteAllText("$Proj\assets\materials\rust.material.bsn", $material)
        $keeper = '#keeper' + [char]10 + 'bevy_transform::components::transform::Transform' + [char]10
        [System.IO.File]::WriteAllText("$Proj\assets\props\keeper.bsn", $keeper)
        $scene = '#Probe' + [char]10 + 'jackdaw::prefab::components::Prefab' + [char]10 + 'jackdaw::prefab::components::IsA { source: ' + $q + 'props/victim.bsn' + $q + ' }' + [char]10
        [System.IO.File]::WriteAllText("$Proj\assets\zones\scene.bsn", $scene)
        $cfg = "$env:TEMP\t05r1-cfg"
        if (Test-Path $cfg) { Remove-Item -Recurse -Force $cfg }
        New-Item -ItemType Directory -Force -Path $cfg | Out-Null
        $env:JACKDAW_OPEN_PROJECT = $Proj
        $env:JACKDAW_CONFIG_DIR = $cfg
        $env:JACKDAW_REMOTE_PORT = "$Port"
        $env:JACKDAW_SKIP_SETUP_CHECK = '1'
        $env:JACKDAW_WINDOW_SIZE = '1920x1080'
        Start-Process -FilePath 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe' -WorkingDirectory 'E:\Project\rust\jackdaw' -RedirectStandardError "$env:TEMP\t05r1-editor.log" -RedirectStandardOutput "$env:TEMP\t05r1-editor.out.log"
        # The endpoint and the project both take a moment.
        $deadline = (Get-Date).AddSeconds(90)
        $opened = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3
            try {
                $r = Brp-Call 'jackdaw/status' @{} 10
                if ($r.result.project) { Write-Output ('PROJECT OPEN: ' + ($r.result.project | ConvertTo-Json -Compress)); $opened = $true; break }
            } catch {}
        }
        if (-not $opened) { Fail 'the project did not open' }
        Wait-Idle 90
        Write-Output 'LAUNCHED'
    }
    'chain' {
        Wait-Idle
        # 1. The startup walk said what it did (the log line the QA run had
        #    none of).
        $log = Get-Content "$env:TEMP\t05r1-editor.log" -Raw
        if ($log -like '*Indexed 1 asset files*') { Pass 'startup walk logged "Indexed 1 asset files"' }
        else { Fail 'no "Indexed" line in the editor log' }

        # 2. The scene opens; the audit names the gone prefab as Missing,
        #    not a machine path.
        Op 'scene.open' @{ path = 'assets/zones/scene.bsn' } | Out-Null
        Wait-Idle 90
        $audit = (Brp-Call 'jackdaw/audit' @{} 60).result
        $victim = @($audit.findings) | Where-Object { $_.reference -like '*victim.bsn' }
        if (@($victim).Count -ne 1) { Fail "audit findings: $($audit | ConvertTo-Json -Depth 8)" }
        if ($victim[0].kind -ne 'Missing') { Fail "kind is $($victim[0].kind), not Missing" }
        Pass 'audit names the gone prefab Missing (relative spelling)'

        # 3. The list shows the row and its Rebind. The rebind itself is
        #    driven through the `asset.rebind` operator — the structured
        #    channel — because the remote click driver's coordinate math
        #    lands off small controls (the QA finding); the button stays for
        #    a person, padded roomy.
        Op 'asset.missing_list' @{} | Out-Null
        Wait-Idle
        $tree = Get-Tree
        $row = Find-Node $tree 'victim.bsn'
        if (-not $row) { Fail 'the Missing list has no row for the gone prefab' }
        $rebind = Find-Node $tree 'Rebind'
        if (-not $rebind) { Fail 'no Rebind button' }
        Pass 'the Missing list shows the row and its Rebind'
        Op 'asset.rebind' @{
            document = 'zones/scene.bsn'
            component = 'IsA'
            field = 'source'
            reference = 'props/victim.bsn'
            to = 'props/keeper.bsn'
        } | Out-Null
        Wait-Idle

        # 4. The authored document names the new path.
        $bsn = (Brp-Call 'jackdaw/scene_bsn' @{} 30).result | ConvertTo-Json -Depth 10
        if ($bsn -like '*props/keeper.bsn*') { Pass 'authored bsn names the held prefab' }
        else { Fail "authored bsn: $bsn" }
        if ($bsn -like '*victim.bsn*') { Fail 'authored bsn still names the gone prefab' }

        # 5. The save writes it; the file on disk says so.
        Op 'scene.save' @{} | Out-Null
        Wait-Idle
        $saved = Get-Content "$Proj\assets\zones\scene.bsn" -Raw
        if ($saved -like '*props/keeper.bsn*') { Pass 'the file on disk names the held prefab' }
        else { Fail "file on disk: $saved" }

        # 6. A fresh read of the scene audits clean.
        Op 'scene.new' @{} | Out-Null
        Wait-Idle
        Op 'scene.switch' @{ tab = 0 } | Out-Null
        Wait-Idle
        Op 'scene.close' @{} | Out-Null
        Wait-Idle
        Op 'scene.open' @{ path = 'assets/zones/scene.bsn' } | Out-Null
        Wait-Idle 90
        $audit2 = (Brp-Call 'jackdaw/audit' @{} 60).result
        $left = @($audit2.findings) | Where-Object { $_.reference -like '*victim.bsn' }
        if (@($left).Count -gt 0) { Fail "audit still names the gone prefab: $($audit2 | ConvertTo-Json -Depth 8)" }
        Pass 'the reopened scene audits clean'
        Write-Output 'CHAIN ALL PASS'
    }
    'cleanup' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Output 'CLEANED'
    }
}
