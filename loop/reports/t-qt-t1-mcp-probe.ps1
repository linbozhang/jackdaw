# T-QT-T1: drive `jd mcp` over stdio against a live editor, the way the
# smoke test does on a display-capable host. Windows has no DISPLAY env var,
# so tests/mcp_smoke.rs cannot run here in either mode; this is the same wire.
param(
    [string]$Exe = "E:\Project\rust\jackdaw\target\debug\jackdaw.exe",
    [string]$Jd = "E:\Project\rust\jackdaw\target\debug\jd.exe",
    [int]$Port = 15794
)
$ErrorActionPreference = "Stop"

$Project = Join-Path $env:TEMP "t-qt-t1-mcp-$(Get-Random)"
New-Item -ItemType Directory -Force -Path (Join-Path $Project "assets"), (Join-Path $Project ".jackdaw") | Out-Null
Set-Content (Join-Path $Project ".jackdaw/project.json") '{"name":"t-qt-t1-mcp"}'
Set-Content (Join-Path $Project "Cargo.toml") "[package]`nname = `"mcpprobe`"`nversion = `"0.1.0`"`nedition = `"2021`"`n"

$env:JACKDAW_OPEN_PROJECT = $Project
$env:JACKDAW_REMOTE_PORT = "$Port"
$env:JACKDAW_SKIP_SETUP_CHECK = "1"
$editor = Start-Process -FilePath $Exe -PassThru
$mcp = $null
try {
    # --- editor ready ---
    $ready = $false
    for ($i = 0; $i -lt 240; $i++) {
        try {
            $b = @{ jsonrpc = "2.0"; id = 1; method = "jackdaw/status"; params = @{} } | ConvertTo-Json -Compress
            $raw = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -Body $b -ContentType "application/json" -TimeoutSec 5
            if ($raw.result) { $ready = $true; break }
        } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $ready) { throw "editor never answered" }
    Write-Output "READY editor pid=$($editor.Id)"

    # --- jd mcp over stdio ---
    # stderr is NOT redirected: rmcp logs there, and an undrained pipe
    # deadlocks the child once its buffer fills.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Jd
    $psi.Arguments = "mcp --project `"$Project`""
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $false
    $psi.UseShellExecute = $false
    $mcp = [System.Diagnostics.Process]::Start($psi)

    function Request([int]$id, [string]$method, $params) {
        $body = @{ jsonrpc = "2.0"; id = $id; method = $method; params = $params } | ConvertTo-Json -Depth 12 -Compress
        $mcp.StandardInput.WriteLine($body)
        $mcp.StandardInput.Flush()
        $deadline = (Get-Date).AddSeconds(60)
        while ((Get-Date) -lt $deadline) {
            $line = $mcp.StandardOutput.ReadLine()
            if ($null -eq $line) { throw "jd mcp closed stdout on $method" }
            try { $v = $line | ConvertFrom-Json } catch { continue }
            if ($v.id -eq $id) { return $v }
        }
        throw "timeout on $method"
    }

    $init = Request 1 "initialize" @{ protocolVersion = "2024-11-05"; capabilities = @{}; clientInfo = @{ name = "t-qt-t1"; version = "0" } }
    Write-Output ("MCP initialize: tools=" + ($null -ne $init.result.capabilities.tools))
    $mcp.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}')
    $mcp.StandardInput.Flush()

    $tools = Request 2 "tools/list" @{}
    $names = @($tools.result.tools | ForEach-Object { $_.name })
    Write-Output ("MCP tools/list: " + $names.Count + " tools: " + ($names -join ","))
    foreach ($wanted in @("ui_tree", "ui_click", "ui_drag", "ui_input", "camera_state")) {
        if ($names -notcontains $wanted) { throw "missing MCP tool $wanted" }
    }

    $ui = Request 3 "tools/call" @{ name = "ui_tree"; arguments = @{ depth = 1 } }
    $nodes = @($ui.result.structuredContent.nodes)
    Write-Output ("MCP ui_tree over the wire: " + $nodes.Count + " nodes")
    if ($nodes.Count -lt 1) { throw "ui_tree answered nothing over MCP" }

    $cam = Request 4 "tools/call" @{ name = "camera_state"; arguments = @{} }
    Write-Output ("MCP camera_state over the wire: " + ($cam.result.structuredContent | ConvertTo-Json -Compress))
    Write-Output "MCP PROBE PASS"
}
finally {
    if ($mcp -and -not $mcp.HasExited) { Stop-Process -Id $mcp.Id -Force -ErrorAction SilentlyContinue }
    if (-not $editor.HasExited) { Stop-Process -Id $editor.Id -Force }
    Remove-Item -Recurse -Force $Project -ErrorAction SilentlyContinue
}
