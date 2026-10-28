# One-off helper for the interrupted T04-T1 live run: take the `before`
# snapshot the launch phase would have written, with the already-running
# editor, and back the scene file up before any save touches it.
$ErrorActionPreference = 'Stop'
$Proj = 'C:\Users\linbo.zhang\Projects\my-game'
$OutDir = 'E:\Project\rust\jackdaw\loop\reports\t04t1-live'
$before = @{}
Get-ChildItem -Path $Proj -Recurse -Filter *.bsn -File | ForEach-Object {
    $before[$_.FullName] = $_.LastWriteTimeUtc.Ticks
}
$before.GetEnumerator() | ForEach-Object { "$($_.Key)|$($_.Value)" } |
    Set-Content -Encoding UTF8 (Join-Path $OutDir 'before-bsn.txt')
Write-Output ("BSN_COUNT=" + $before.Count)
Copy-Item (Join-Path $Proj 'assets\scene.bsn') (Join-Path $OutDir 'scene.bsn.pre-save.bak') -Force
Write-Output "PRE_BACKUP_OK"
