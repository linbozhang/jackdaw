# T10b QA: independent event-log audit (Application, Id=1000, last 5 days)
# Pure-ASCII parser: event 1000 message line order is fixed
#   line0: app name + version, line1: module name + version,
#   line2: exception code,   line3: fault offset
$ErrorActionPreference = 'Continue'
$colon = [char[]]@(0x3A, 0xFF1A)   # ':' fullwidth ':'
$comma = [char[]]@(0x2C, 0xFF0C)   # ',' fullwidth ','
$since = (Get-Date).AddDays(-5)
$evts = @(Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000; StartTime=$since} -ErrorAction SilentlyContinue)
"TOTAL Id=1000 since {0:yyyy-MM-dd HH:mm}: {1}" -f $since, $evts.Count
""
"=== PARSED ROWS: time | app | module | code | offset ==="
$objs = foreach ($e in $evts) {
  $lines = $e.Message -split "`r?`n"
  $app = '?'; $mod = '?'; $code = '?'; $off = '?'
  try {
    $app   = ((($lines[0].Split($colon, 2))[1]).Split($comma, 2))[0].Trim()
    $mod   = ((($lines[1].Split($colon, 2))[1]).Split($comma, 2))[0].Trim()
    $code  = (($lines[2].Split($colon, 2))[1]).Trim()
    $off   = (($lines[3].Split($colon, 2))[1]).Trim()
  } catch {}
  [PSCustomObject]@{ T = $e.TimeCreated; App = $app; Mod = $mod; Code = $code; Off = $off }
}
$objs | ForEach-Object { "{0:yyyy-MM-dd HH:mm:ss} | {1} | {2} | {3} | {4}" -f $_.T, $_.App, $_.Mod, $_.Code, $_.Off }
""
"=== GROUPS: count x module | code | offset ==="
$objs | Group-Object Mod, Code, Off | Sort-Object Count -Descending | ForEach-Object { "{0,3} x {1}" -f $_.Count, ($_.Name -join ' | ') }
""
"=== FOCUS STATS ==="
$c5   = @($objs | Where-Object { $_.Code -eq '0xc0000005' }).Count
$nv   = @($objs | Where-Object { $_.Code -eq '0xc0000005' -and $_.Mod -eq 'nvcuda64.dll' }).Count
$nvOff = @($objs | Where-Object { $_.Code -eq '0xc0000005' -and $_.Mod -eq 'nvcuda64.dll' -and $_.Off.TrimStart('0', 'x') -match '3ab984$' }).Count
"0xc0000005 total: {0} | of which nvcuda64.dll: {1} | nvcuda64.dll @offset ..3ab984: {2}" -f $c5, $nv, $nvOff
"deviating samples (0xc0000005 but NOT nvcuda64@3ab984):"
$objs | Where-Object { $_.Code -eq '0xc0000005' -and -not ($_.Mod -eq 'nvcuda64.dll' -and $_.Off.TrimStart('0', 'x') -match '3ab984$') } | ForEach-Object { "  {0:yyyy-MM-dd HH:mm:ss} | {1} | {2} | {3} | {4}" -f $_.T, $_.App, $_.Mod, $_.Code, $_.Off }
