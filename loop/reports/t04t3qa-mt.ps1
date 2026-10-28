# QA multi-tab recovery: named + untitled dirty tabs, kill, restore both.
$ErrorActionPreference = 'Stop'
$Port = 15815
function Post([string]$Method, $Params) {
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $deadline = (Get-Date).AddSeconds(25)
    while ((Get-Date) -lt $deadline) {
        try { $raw = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 10 }
        catch { Start-Sleep -Milliseconds 250; continue }
        if ($null -ne $raw.error) { return @{ error = $raw.error } }
        if ($null -ne $raw.result) { return @{ result = $raw.result } }
        Start-Sleep -Milliseconds 120
    }
    throw "timeout $Method"
}
$Step = $args[0]
switch ($Step) {
    'dirty2' {
        $r1 = Post 'jackdaw/call_operator' @{ id = 'entity.add.cube'; params = @{} }
        Write-Output ('cube on named: ' + $r1.result.result)
        Post 'jackdaw/call_operator' @{ id = 'scene.new'; params = @{} } | Out-Null
        Start-Sleep -Milliseconds 500
        $r2 = Post 'jackdaw/call_operator' @{ id = 'entity.add.cube'; params = @{} }
        Write-Output ('cube on untitled: ' + $r2.result.result)
        $deadline = (Get-Date).AddSeconds(30); $j = $null
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 500
            $j = Get-ChildItem "$env:TEMP\t04-final-cfg-qa\state\sessions" -Recurse -Filter journal.json -File -ErrorAction SilentlyContinue |
                Where-Object { $_.DirectoryName -notmatch '36796|43260' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($j) { $doc = Get-Content $j.FullName -Raw | ConvertFrom-Json; if (@($doc.tabs).Count -ge 2) { break } }
        }
        if (-not $j) { throw 'two-tab journal never landed' }
        $doc = Get-Content $j.FullName -Raw | ConvertFrom-Json
        Write-Output ("[journal] " + $j.Directory.Name + " tabs=" + @($doc.tabs).Count + " (" + (($doc.tabs | ForEach-Object { $p = 'untitled'; if ($_.path) { $p = 'named' }; $_.kind + ':' + $p }) -join ', ') + ")")
        $j.Directory.Name | Set-Content -Encoding UTF8 "$env:TEMP\t04-qa-mt-session.txt"
        $pidNow = (Post 'jackdaw/status' @{}).result.pid
        Write-Output ("PID=$pidNow")
    }
    'restore2' {
        $s = Get-Content "$env:TEMP\t04-qa-mt-session.txt" -Raw
        $s = $s.Trim()
        $rec = (Post 'jackdaw/recovery' @{}).result
        Write-Output ("[recovery] available=" + $rec.available + " sessions=" + @($rec.sessions).Count)
        $s0 = @($rec.sessions) | Where-Object { $_.session -eq $s }
        if (-not $s0) { throw "session $s not listed" }
        Write-Output ("[session tabs] " + @($s0.tabs).Count + " -> " + (($s0.tabs | ForEach-Object { "$($_.kind):$($_.display_name) path=$($_.path)" }) -join '; '))
        # restore tab 0 (the named scene)
        $r0 = Post 'jackdaw/call_operator' @{ id = 'recovery.restore'; params = @{ session = $s; tab = 0 } }
        Write-Output ('restore#0: ' + ($r0.result | ConvertTo-Json -Compress))
        $rec1 = (Post 'jackdaw/recovery' @{}).result
        $s1 = @($rec1.sessions) | Where-Object { $_.session -eq $s }
        $n1 = if ($s1) { @($s1.tabs).Count } else { 0 }
        Write-Output ("[after restore#0] journal tabs=" + $n1)
        $st0 = (Post 'jackdaw/status' @{}).result
        Write-Output ("[after restore#0] dirty=" + $st0.dirty + " scene=" + $st0.scene)
        # restore tab 1 (the untitled)
        $r1 = Post 'jackdaw/call_operator' @{ id = 'recovery.restore'; params = @{ session = $s; tab = 0 } }
        Write-Output ('restore#1: ' + ($r1.result | ConvertTo-Json -Compress))
        $rec2 = (Post 'jackdaw/recovery' @{}).result
        $s2 = @($rec2.sessions) | Where-Object { $_.session -eq $s }
        $n2 = if ($s2) { @($s2.tabs).Count } else { 0 }
        Write-Output ("[after restore#1] journal tabs=" + $n2)
        $st1 = (Post 'jackdaw/status' @{}).result
        Write-Output ("[after restore#1] dirty=" + $st1.dirty + " scene=" + $st1.scene)
        $still = Test-Path (Join-Path "$env:TEMP\t04-final-cfg-qa\state\sessions\01004ec43583bb23" $s 'journal.json')
        Write-Output ("[session dir journal exists] " + $still)
    }
    default { throw "unknown step $Step" }
}
