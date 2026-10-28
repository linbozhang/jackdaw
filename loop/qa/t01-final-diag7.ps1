param(
    [int]$Port = 15723
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'brp.ps1') -Port $Port
. (Join-Path $PSScriptRoot 'input.ps1')

Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force }
Start-Sleep -Milliseconds 500
$env:JACKDAW_OPEN_PROJECT = 'C:\Users\linbo.zhang\Projects\my-game'
$env:JACKDAW_REMOTE_PORT = "$Port"
$proc = Start-Process -FilePath 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe' -WorkingDirectory 'E:\Project\rust\jackdaw\target\debug' -PassThru
try {
    Wait-EditorReady -TimeoutSec 240
    Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 60 | Out-Null
    Wait-BrpResult 'jackdaw/wait' @{ frames = 30 } | Out-Null
    Start-Sleep -Seconds 3

    # window geometry straight from the component (1280x720 default, no OS ops)
    $rows = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @('bevy_window::window::Window') } })
    $pw = 1280; $ph = 720; $scale = 1.0
    foreach ($row in $rows) {
        $w = $row.components.'bevy_window::window::Window'
        if ($w) {
            $pw = [double]$w.resolution.physical_width
            $ph = [double]$w.resolution.physical_height
            if ($w.resolution.scale_factor) { $scale = [double]$w.resolution.scale_factor }
            Write-Output ("window phys={0}x{1} scale={2} focused={3}" -f $pw, $ph, $scale, $w.focused)
        }
    }
    $lx = [Math]::Floor($pw / 2 / $scale); $ly = [Math]::Floor($ph / 2 / $scale)

    # T1 coldstart v4 shape: synthetic move to open hover, then RMB press, poll fly
    $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; history = $false; params = @{ x = $lx; y = $ly; action = 'move'; frames = 1 } })
    Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
    $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; history = $false; params = @{ x = $lx; y = $ly; action = 'press'; button = 'secondary'; frames = 1 } })
    Wait-BrpResult 'jackdaw/wait' @{ frames = 3 } | Out-Null
    $fly = $false
    foreach ($poll in 1..6) {
        $r = Brp-Result (Brp-Call 'world.get_resources' @{ resource = 'jackdaw::viewport::CameraFlyActive' })
        $v = $r.value
        if ($v -isnot [bool]) { $v = [bool]($v.PSObject.Properties | Select-Object -First 1).Value }
        $fly = $fly -or $v
        Write-Output ("fly poll {0}: {1}" -f $poll, $v)
        Wait-BrpResult 'jackdaw/wait' @{ frames = 3 } | Out-Null
    }
    # camera enabled read (B criterion)
    $cam = Get-FlyCamera
    $cr = Brp-Result (Brp-Call 'world.get_components' @{ entity = $cam.Entity; components = @('jackdaw_camera::JackdawCameraSettings') })
    Write-Output ("camera enabled: " + $cr.components.'jackdaw_camera::JackdawCameraSettings'.enabled)
    # release
    $null = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; history = $false; params = @{ x = $lx; y = $ly; action = 'release'; button = 'secondary' } })
    Wait-BrpResult 'jackdaw/wait' @{ frames = 5 } | Out-Null
}
finally {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
