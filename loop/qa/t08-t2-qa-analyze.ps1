# T08-T2 QA: compare the 2.5 and 0.5 behavior legs from saved snapshots.
$T = 'bevy_transform::components::transform::Transform'
function Find-Moved([string]$f1, [string]$f2) {
    $j1 = Get-Content $f1 -Raw | ConvertFrom-Json
    $j2 = Get-Content $f2 -Raw | ConvertFrom-Json
    $out = $null
    foreach ($e2 in @($j2.result)) {
        foreach ($e1 in @($j1.result)) {
            if ($e1.entity -eq $e2.entity) {
                $a = $e1.components.$T
                $b = $e2.components.$T
                if ($a -and $b -and ([double]$a.translation[1] -ne [double]$b.translation[1])) {
                    $script:out = @{
                        e   = "$($e2.entity)"
                        dy  = [double]$b.translation[1] - [double]$a.translation[1]
                        drot = [double]$b.rotation[1] - [double]$a.rotation[1]
                    }
                }
                break
            }
        }
        if ($script:out) { break }
    }
    return $script:out
}
$s25 = Find-Moved 'snap1.json' 'snap2.json'
$s05 = Find-Moved 'snap3.json' 'snap4.json'
Write-Host ('2.5 leg: ' + ($s25 | ConvertTo-Json -Compress))
Write-Host ('0.5 leg: ' + ($s05 | ConvertTo-Json -Compress))
if ($s05 -and $s25) {
    $a25 = [double]($s25.drot.ToString('R')) * 1.0
    $spin25 = [Math]::Abs([double]$s25.drot)
    $spin05 = [Math]::Abs([double]$s05.drot)
    $ratio = $spin25 / [Math]::Max($spin05, 0.0000001)
    Write-Host ("spin25=$spin25 spin05=$spin05 ratio=" + [Math]::Round($ratio, 2))
    if ($s25.dy -lt 0 -and $s05.dy -lt 0) { Write-Host 'both legs fall (gravity live)' }
    if ($ratio -ge 2.5) { Write-Host 'BEHAVIOR PASS: spin scales with move_speed' }
    else { Write-Host 'BEHAVIOR FAIL: spin did not scale with move_speed' }
}
