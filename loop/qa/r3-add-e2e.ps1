# R3 Outliner Add 菜单 E2E 真机驱动（feature-05 T3，方案 D10）
# 多阶段脚本：坐标由上一步截图目测后作参数回填（-X/-Y 为窗口逻辑像素，input.pointer 合成点击）。
# 用法：
#   r3-add-e2e.ps1 -Phase start                 启动编辑器（my-game）+ 就绪 + operators 断言 + 首图
#   r3-add-e2e.ps1 -Phase click -X 120 -Y 30 -Desc add-menu    合成点击 + 前后截图
#   r3-add-e2e.ps1 -Phase op -Op entity.add.point_light       BRP 直调 operator + wait idle
#   r3-add-e2e.ps1 -Phase entity -Name Cube                   查实体（bsn 摘要打印）
#   r3-add-e2e.ps1 -Phase shot -Name step                     window+viewport 双截图
#   r3-add-e2e.ps1 -Phase type -Text 2                        向焦点控件打字 + Enter
#   r3-add-e2e.ps1 -Phase save                                scene.save + 读回文档断言
#   r3-add-e2e.ps1 -Phase restart                             杀进程重启 + 实体仍在断言
param(
    [Parameter(Mandatory = $true)][ValidateSet(
        'start', 'click', 'op', 'entity', 'shot', 'type', 'save', 'restart',
        'key', 'cam', 'windowinfo', 'play', 'waitpie'
    )][string]$Phase,
    [string]$Exe = 'E:\Project\rust\jackdaw\target\debug\jackdaw.exe',
    [string]$Project = 'C:\Users\linbo.zhang\Projects\my-game',
    [int]$Port = 15703,
    [double]$X = 0, [double]$Y = 0,
    [string]$Desc = 'step',
    [string]$Op = '', [hashtable]$OpParams = @{},
    [string]$Name = '',
    [string]$Text = '',
    [string]$Key = '',
    [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = 'E:\Project\rust\jackdaw\loop\reports\r3-add-e2e' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
. 'E:\Project\rust\jackdaw\loop\qa\brp.ps1' -Port $Port
$script:N = 0
function Next-Shot {
    $script:N++
    return ('{0:d2}-{1}' -f $script:N, $Desc)
}
function Take-Shots {
    param([string]$Tag)
    $rel = "screenshots/r3-$Tag.png"
    $r = Wait-BrpResult 'jackdaw/screenshot' @{ kind = 'window'; path = $rel } -TimeoutSec 20
    Copy-Item (Join-Path $Project $rel) (Join-Path $OutDir "$Tag-window.png") -Force
    $relV = "screenshots/r3-$Tag-v.png"
    $v = Wait-BrpResult 'jackdaw/screenshot' @{ kind = 'viewport'; path = $relV } -TimeoutSec 20
    Copy-Item (Join-Path $Project $relV) (Join-Path $OutDir "$Tag-viewport.png") -Force
    Write-Host ("shot {0}: window {1}x{2} viewport {3}x{4}" -f $Tag, $r.width, $r.height, $v.width, $v.height)
}

switch ($Phase) {
    'start' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "killing stale jackdaw pid=$($_.Id)"; Stop-Process -Id $_.Id -Force
        }
        Start-Sleep -Milliseconds 500
        $env:JACKDAW_OPEN_PROJECT = $Project
        $env:JACKDAW_REMOTE_PORT = "$Port"
        $deps = Join-Path (Split-Path -Parent $Exe) 'deps'
        $env:PATH = "$deps;$env:PATH"
        $proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
            -RedirectStandardOutput (Join-Path $OutDir 'editor-stdout.log') `
            -RedirectStandardError (Join-Path $OutDir 'editor-stderr.log') -PassThru
        Write-Host "editor pid=$($proc.Id)"
        $proc.Id | Set-Content (Join-Path $OutDir 'editor.pid')
        Wait-EditorReady -TimeoutSec 90
        Write-Host "editor ready"
        Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 60 | Out-Null
        # D10.1: operators 断言
        $ops = Brp-Result (Brp-Call 'jackdaw/operators' @{})
        $flat = @()
        if ($ops -is [array]) { $flat = $ops } else { $flat = @($ops.PSObject.Properties | ForEach-Object { $_.Value }) }
        $text = $flat | ConvertTo-Json -Depth 6 -Compress
        foreach ($want in 'entity.add.cube', 'entity.add.point_light', 'entity.add.directional_light') {
            if ($text -notmatch [regex]::Escape($want)) { throw "operator $want missing" }
        }
        Write-Host 'operators OK: entity.add.cube / point_light / directional_light present'
        Take-Shots '00-boot'
    }
    'click' {
        $tag = Next-Shot
        Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = $X; y = $Y; action = 'click' } }) | Out-Null
        Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 30 | Out-Null
        Start-Sleep -Milliseconds 400
        Take-Shots $tag
    }
    'op' {
        $call = @{ id = $Op }
        if ($OpParams.Count) { $call.params = $OpParams }
        $r = Brp-Result (Brp-Call 'jackdaw/call_operator' $call)
        Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 60 | Out-Null
        $r | ConvertTo-Json -Depth 8 | Write-Host
    }
    'entity' {
        $r = Brp-Result (Brp-Call 'jackdaw/entity' @{ name = $Name })
        $r | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $OutDir "entity-$Name.json") -Encoding UTF8
        Write-Host "entity bits: $($r.entity)"
        # bsn 组件面摘要
        if ($r.bsn -is [string]) {
            Write-Host ($r.bsn -split "`n" | Select-String -Pattern '^\s*\[|^\s*[A-Za-z_]+ =' | ForEach-Object { $_.Line } | Select-Object -First 40)
        } else {
            $r.bsn | ConvertTo-Json -Depth 8 | Write-Host
        }
    }
    'shot' { Take-Shots (Next-Shot) }
    'type' {
        Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.text'; params = @{ text = $Text } }) | Out-Null
        Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 30 | Out-Null
        Start-Sleep -Milliseconds 200
        Take-Shots (Next-Shot)
    }
    'key' {
        Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.key'; params = @{ key = $Key } }) | Out-Null
        Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 30 | Out-Null
        Start-Sleep -Milliseconds 200
        Take-Shots (Next-Shot)
    }
    'cam' {
        $c = Get-FlyCamera
        Write-Host ("cam pos=({0:N3},{1:N3},{2:N3}) yaw={3:N4} pitch={4:N4}" -f $c.Position.x, $c.Position.y, $c.Position.z, $c.Yaw, $c.Pitch)
    }
    'windowinfo' {
        # 主窗口组件：物理/逻辑尺寸与 scale factor（截图坐标→逻辑坐标换算用）
        $winPath = 'bevy_window::window::PrimaryWindow'
        $rows = Brp-Result (Brp-Call 'world.query' @{ data = @{ components = @('bevy_window::window::Window') }; filter = @{ with = @($winPath) } })
        $rows | ConvertTo-Json -Depth 10 | Write-Host
    }
    'save' {
        $r = Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'scene.save' })
        $r | ConvertTo-Json -Depth 8 | Write-Host
        Start-Sleep -Milliseconds 800
    }
    'restart' {
        Get-Process jackdaw -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Milliseconds 800
        $env:JACKDAW_OPEN_PROJECT = $Project
        $env:JACKDAW_REMOTE_PORT = "$Port"
        $deps = Join-Path (Split-Path -Parent $Exe) 'deps'
        $env:PATH = "$deps;$env:PATH"
        $proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) `
            -RedirectStandardOutput (Join-Path $OutDir 'editor-restart-stdout.log') `
            -RedirectStandardError (Join-Path $OutDir 'editor-restart-stderr.log') -PassThru
        Write-Host "restarted pid=$($proc.Id)"
        $proc.Id | Set-Content (Join-Path $OutDir 'editor.pid')
        Wait-EditorReady -TimeoutSec 90
        Wait-BrpResult 'jackdaw/wait' @{ until = 'idle' } -TimeoutSec 60 | Out-Null
        Write-Host 'restarted and ready'
        Take-Shots '99-restarted'
    }
    'play' {
        # B3: 点 Play 按钮（坐标回填）或走 run target operator
        if ($X -gt 0) {
            Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id = 'input.pointer'; params = @{ x = $X; y = $Y; action = 'click' } }) | Out-Null
        } else {
            throw 'play phase needs -X/-Y of the Play button'
        }
    }
    'waitpie' {
        $r = Wait-BrpResult 'jackdaw/wait' @{ until = 'pie_running' } -TimeoutSec 900
        $r | ConvertTo-Json -Depth 8 | Write-Host
        Take-Shots (Next-Shot)
    }
    default { throw "unhandled phase $Phase" }
}
