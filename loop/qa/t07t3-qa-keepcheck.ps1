$Repo = 'E:\Project\rust\jackdaw'
$Jd = Join-Path $Repo 'target\debug\jd.exe'
$Proj = 'C:\Users\linbo.zhang\Projects\my-game'
$d = Join-Path $Repo 'loop\t07t3-qa-live\keep-check'
Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $d | Out-Null
[IO.File]::WriteAllBytes((Join-Path $d 'important.txt'), [byte[]](112,114,101,99,105,111,117,115))
$before = [IO.File]::ReadAllBytes((Join-Path $d 'important.txt'))
& $Jd export --project $Proj --out $d 2>&1 | Out-Null
$code = $LASTEXITCODE
$after = [IO.File]::ReadAllBytes((Join-Path $d 'important.txt'))
$same = ($before.Length -eq $after.Length) -and (-not (Compare-Object $before $after -SyncWindow 0))
Write-Host ("refused exit={0} bytes-identical={1} len={2}" -f $code, $same, $after.Length)
Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
