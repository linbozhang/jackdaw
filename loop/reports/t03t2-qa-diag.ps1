# Diagnose: where is the Zone row in the ui_tree?
param(
    [string]$Exe = "E:\Project\rust\jackdaw\target\debug\jackdaw.exe",
    [int]$Port = 15813
)
$ErrorActionPreference = 'Stop'
function Brp-Call([string]$Method, $Params, [int]$TimeoutSec = 30) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try { $raw = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 15 }
        catch { Start-Sleep -Milliseconds 250; continue }
        if ($null -ne $raw.error) { return @{ error = $raw.error } }
        if ($null -ne $raw.result) { return @{ result = $raw.result } }
        Start-Sleep -Milliseconds 120
    }
    throw "timeout waiting for $Method $Params"
}
function Wait-Idle([int]$T = 90) { Brp-Call 'jackdaw/wait' @{ until = 'idle' } $T | Out-Null; Start-Sleep -Milliseconds 400 }
function Op([string]$Id, $Params) { Brp-Call 'jackdaw/call_operator' @{ id = $Id; params = $Params } }
function Key([string]$K) { Op 'input.key' @{ key = $K; action = 'tap' } | Out-Null; Wait-Idle }

$Project = Join-Path $env:TEMP "t03t2-diag-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $Project "assets"), (Join-Path $Project ".jackdaw") | Out-Null
Set-Content (Join-Path $Project ".jackdaw/project.json") '{"name":"t03t2-diag","remote":{"enabled":true}}'
Set-Content (Join-Path $Project "Cargo.toml") "[package]`nname = `"qa`"`nversion = `"0.1.0`"`nedition = `"2021`"`n`n[dependencies]`n"
Set-Content (Join-Path $Project "assets/zone.bsn") "#Zone`nbevy_transform::components::transform::Transform`n"

$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_WINDOW_SIZE = "1920x1080"
$env:JACKDAW_SKIP_SETUP_CHECK = "1"
$editor = Start-Process -FilePath $Exe -PassThru
try {
    $ready = $false
    for ($i = 0; $i -lt 240; $i++) {
        try { $s = Brp-Call 'jackdaw/status' @{} 5; if ($s.result) { $ready = $true; break } } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $ready) { throw "no editor" }
    Wait-Idle
    $setup = Brp-Call 'jackdaw/ui_tree' @{ text = 'Open without setup'; depth = 0 }
    if (@($setup.result.nodes).Count -gt 0) {
        Brp-Call 'jackdaw/ui_click' @{ text = 'Open without setup' } | Out-Null
        Wait-Idle; Wait-Idle
    }
    Key 'Escape'
    Op 'scene.open' @{ path = 'assets/zone.bsn' } | Out-Null
    Start-Sleep -Seconds 4
    Wait-Idle; Wait-Idle

    # any node whose text mentions Zone
    $hits = Brp-Call 'jackdaw/ui_tree' @{ text = 'Zone'; depth = 4 }
    Write-Output ("text=Zone filter nodes: " + @($hits.result.nodes).Count)
    foreach ($n in @($hits.result.nodes)) {
        Write-Output ("  hit e=" + $n.entity + " kind=" + $n.kind + " text=" + $n.text + " rect=[" + ($n.rect -join ',') + "] children=" + @($n.children).Count)
    }
    # text_input rows in the right half
    $fields = Brp-Call 'jackdaw/ui_tree' @{ kind = 'text_input'; depth = 8 }
    $rows = @($fields.result.nodes | Where-Object { $_.rect -and $_.rect[0] -gt 1000 })
    Write-Output ("right-half text_inputs: " + $rows.Count)
    foreach ($n in ($rows | Select-Object -First 8)) {
        Write-Output ("  field e=" + $n.entity + " rect=[" + ($n.rect -join ',') + "]")
    }
    # Hierarchy-ish title
    $panel = Brp-Call 'jackdaw/ui_tree' @{ text = 'Hierarchy'; depth = 2 }
    Write-Output ("Hierarchy-filter nodes: " + @($panel.result.nodes).Count)
    foreach ($n in @($panel.result.nodes)) { Write-Output ("  panel e=" + $n.entity + " kind=" + $n.kind + " text=" + $n.text + " rect=[" + ($n.rect -join ',') + "]") }

    # full walk, then find rows whose direct child text is Zone
    $script:All = @()
    function Walk2($n) {
        $script:All += ,$n
        if ($null -ne $n.children) { foreach ($c in @($n.children)) { if ($null -ne $c) { Walk2 $c } } }
    }
    $full = (Brp-Call 'jackdaw/ui_tree' @{ depth = 30 }).result.nodes
    foreach ($n in $full) { Walk2 $n }
    Write-Output ("full walk nodes: " + $script:All.Count)
    $labelled = @($script:All | Where-Object { $_.children -and @($_.children | Where-Object { $_.text -eq 'Zone' }).Count -gt 0 })
    Write-Output ("rows with direct Zone child: " + $labelled.Count)
    foreach ($n in $labelled) { Write-Output ("  row e=" + $n.entity + " kind=" + $n.kind + " rect=[" + ($n.rect -join ',') + "]") }
    $nullkids = @($script:All | Where-Object { $null -eq $_.children }).Count
    Write-Output ("nodes without children field: " + $nullkids)
    $texts = @($script:All | Where-Object { $_.text -eq 'Zone' })
    Write-Output ("nodes with text Zone: " + $texts.Count)
    foreach ($n in $texts) { Write-Output ("  label e=" + $n.entity + " kind=" + $n.kind + " rect=[" + ($n.rect -join ',') + "]") }

    # the QA Row-Of, verbatim
    function Row-Of([string]$Label, [double]$MaxX = 600) {
        $rows = @($script:All | Where-Object {
            @($_.children | Where-Object { $_.text -eq $Label }).Count -gt 0 -and $_.rect -and $_.rect[0] -lt $MaxX -and $_.rect[1] -gt 100
        } | Sort-Object { $_.rect[1] })
        return $rows
    }
    $qa = Row-Of 'Zone'
    Write-Output ("QA Row-Of matches: " + @($qa).Count)
    foreach ($n in @($qa)) { Write-Output ("  qa row e=" + $n.entity + " rect=[" + ($n.rect -join ',') + "]") }

    # raw jackdaw/history
    $body = '{"jsonrpc":"2.0","id":1,"method":"jackdaw/history","params":{"entries":5}}'
    $w = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing -TimeoutSec 20
    Write-Output ("[history] HTTP " + $w.StatusCode + " body: " + $w.Content)
    $body2 = '{"jsonrpc":"2.0","id":2,"method":"jackdaw/status","params":{}}'
    $w2 = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -Method Post -ContentType 'application/json' -Body ([System.Text.Encoding]::UTF8.GetBytes($body2)) -UseBasicParsing -TimeoutSec 20
    Write-Output ("[status] HTTP " + $w2.StatusCode + " len " + $w2.Content.Length)
}
finally {
    try { Stop-Process -Id $editor.Id -Force -ErrorAction SilentlyContinue } catch {}
    Remove-Item -Recurse -Force $Project -ErrorAction SilentlyContinue
}
