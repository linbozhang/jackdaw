param([string]$Lock = 'E:\Project\rust\jackdaw\Cargo.lock')
$lines = Get-Content $Lock
$names = @{}
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^name = "(.+)"') { $names[$i] = $Matches[1] }
}
foreach ($i in 0..($lines.Count - 1)) {
    if ($lines[$i] -match '"windows 0\.6') {
        $j = $i
        while (-not $names.ContainsKey($j)) { $j-- }
        Write-Host ($names[$j] + ' -> ' + $lines[$i].Trim())
    }
}
