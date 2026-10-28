# MCP smoke: initialize + tools/list over stdio; assert the pie tool is present.
$ErrorActionPreference = 'Stop'
$Repo = 'E:\Project\rust\jackdaw'
$exe = Join-Path $Repo 'target\debug\jd.exe'
if (-not (Test-Path $exe)) { $exe = Join-Path $Repo 'target\debug\jackdaw_mcp.exe' }
Write-Host "binary: $exe"
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}'
$list  = '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
$stdin = $init + "`n" + $list + "`n"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $exe
$psi.Arguments = 'mcp'
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
$p.StandardInput.Write($stdin)
$p.StandardInput.Flush()
Start-Sleep -Seconds 6
$out = ''
try { $p.Kill() } catch {}
# Reread via a fresh run capturing to files instead (PS async read is flaky):
$psi2 = New-Object System.Diagnostics.ProcessStartInfo
$psi2.FileName = $exe
$psi2.Arguments = 'mcp'
$psi2.RedirectStandardInput = $true
$psi2.RedirectStandardOutput = $true
$psi2.RedirectStandardError = $true
$psi2.UseShellExecute = $false
$p2 = [System.Diagnostics.Process]::Start($psi2)
$outFile = "$Repo\loop\t06t3_mcp_out.txt"
$errFile = "$Repo\loop\t06t3_mcp_err.txt"
$job = Start-Job -ScriptBlock {
    param($proc, $path)
    $sw = [IO.StreamWriter]::new($path)
    while (-not $proc.HasExited) {
        $line = $proc.StandardOutput.ReadLine()
        if ($null -ne $line) { $sw.WriteLine($line); $sw.Flush() }
    }
    $sw.Close()
} -ArgumentList $p2, $outFile
$p2.StandardInput.Write($stdin)
$p2.StandardInput.Flush()
Start-Sleep -Seconds 8
try { $p2.Kill() } catch {}
Stop-Job $job -ErrorAction SilentlyContinue
Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
Remove-Job $job -Force -ErrorAction SilentlyContinue
$content = ''
if (Test-Path $outFile) { $content = Get-Content $outFile -Raw }
Write-Host ("output bytes: " + $content.Length)
$names = @()
foreach ($m in [regex]::Matches($content, '"name"\s*:\s*"([a-z_]+)"')) { $names += $m.Groups[1].Value }
$names = $names | Sort-Object -Unique
Write-Host ("tool names seen: " + ($names -join ', '))
if ($content -match '"pie"') { Write-Host 'MCP_SMOKE_PASS: the pie tool is listed' }
else { Write-Host 'MCP_SMOKE_FAIL: no pie tool in the listing'; exit 1 }
