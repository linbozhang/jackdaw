param(
    [int]$Port = 15709,
    [int]$TimeoutSec = 300
)
$env:JACKDAW_OPEN_PROJECT = 'C:\Users\linbo.zhang\Projects\my-game'
$env:JACKDAW_REMOTE_PORT = "$Port"
$p = Start-Process -FilePath 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe' -WorkingDirectory 'E:\Project\rust\jackdaw\target\debug' -PassThru
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$portUp = $false
$titleSeen = ''
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 2000
    if ($p.HasExited) {
        Write-Output ("EXITED at {0}" -f (Get-Date).ToLongTimeString())
        break
    }
    $t = (Get-Process -Id $p.Id -ErrorAction SilentlyContinue).MainWindowTitle
    if ($t -and $t -ne $titleSeen) {
        $titleSeen = $t
        Write-Output ("title='{0}' at {1}" -f $t, (Get-Date).ToLongTimeString())
    }
    if (-not $portUp) {
        try {
            $c = New-Object Net.Sockets.TcpClient
            $r = $c.BeginConnect('127.0.0.1', $Port, $null, $null)
            if ($r.AsyncWaitHandle.WaitOne(300)) {
                $c.EndConnect($r)
                $c.Close()
                Write-Output ("PORT-UP title='{0}' at {1}" -f $t, (Get-Date).ToLongTimeString())
                $portUp = $true
                break
            }
            $c.Close()
        } catch { }
    }
}
if (-not $p.HasExited) {
    Write-Output ("alive title='{0}' portUp={1}" -f $titleSeen, $portUp)
}
