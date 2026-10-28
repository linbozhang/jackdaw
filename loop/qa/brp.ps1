# BRP JSON-RPC 2.0 helper for jackdaw (R4 手册 §5.2)
# 用法: . E:\Project\rust\jackdaw\loop\qa\brp.ps1 -Port 15703
#   Brp-Call 'jackdaw/status' @{}
#   Brp-Result (Brp-Call 'jackdaw/call_operator' @{ id='entity.add.cube'; history=$false })
#   Wait-EditorReady; Wait-BrpResult 'jackdaw/wait' @{ frames=5 }
#   Get-FlyCamera   # 返回 3D 视口相机: @{ Entity=...; Position=...; Yaw=...; Pitch=... }
param([int]$Port = 15703)

$script:BrpPort = $Port
$script:CameraPath = 'bevy_camera::camera::Camera'
$script:TransformPath = 'bevy_transform::components::transform::Transform'
$script:ProjectionPath = 'bevy_camera::projection::Projection'

# ---- 基础调用 -------------------------------------------------------------
function Brp-Call {
    param([Parameter(Mandatory = $true)][string]$Method, $Params = @{})
    $body = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } |
        ConvertTo-Json -Depth 12 -Compress
    # 编辑器主线程忙（资产加载等）时请求会排队超时：超时重试一次。
    try {
        Invoke-RestMethod -Uri "http://127.0.0.1:$script:BrpPort/" -Method Post `
            -ContentType 'application/json' -Body $body -TimeoutSec 20
    } catch {
        Start-Sleep -Seconds 1
        Invoke-RestMethod -Uri "http://127.0.0.1:$script:BrpPort/" -Method Post `
            -ContentType 'application/json' -Body $body -TimeoutSec 30
    }
}

# 取 result；error 直接抛异常（不吞错误）。
function Brp-Result {
    param([Parameter(Mandatory = $true)]$Response)
    if ($Response.error) {
        throw "BRP error: $($Response.error | ConvertTo-Json -Depth 6 -Compress)"
    }
    return $Response.result
}

# ---- 就绪探测（R4 手册 §5.1 / §5.6）-------------------------------------
function Wait-EditorReady {
    param([int]$TimeoutSec = 60)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Brp-Call 'jackdaw/status' @{}
            if ($null -ne $r.result) { return $true }
        } catch { Start-Sleep -Milliseconds 500 }
    }
    throw "editor BRP not ready within ${TimeoutSec}s on port $script:BrpPort"
}

# ---- watching 型方法轮询（result=null 表示未完成；同 params 同 key）-------
function Wait-BrpResult {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        $Params = @{},
        [int]$TimeoutSec = 10
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Brp-Call $Method $Params
        if ($r.error) { throw "BRP error: $($r.error | ConvertTo-Json -Depth 6 -Compress)" }
        if ($null -ne $r.result) { return $r.result }
        Start-Sleep -Milliseconds 100
    }
    throw "watching method $Method timed out after ${TimeoutSec}s"
}

# ---- 相机读取（world.query 按 Camera 过滤；选 is_active 且 Perspective）---
# 注意：方法名是 world.query / world.get_components（pinned bevy 0.20-dev 无 bevy/ 前缀）。
# 实测：world.query 的 option 字段不回传 Projection，故对每个 active 相机再用
# world.get_components 单查 Projection 验证是 Perspective（=3D 视口相机）。
function Get-FlyCamera {
    $camPath = $script:CameraPath; $tfPath = $script:TransformPath; $projPath = $script:ProjectionPath
    $params = @{
        data   = @{ components = @($tfPath, $camPath) }
        filter = @{ with = @($camPath) }
    }
    $rows = Brp-Result (Brp-Call 'world.query' $params)
    if (-not $rows) { throw 'world.query returned no cameras' }
    $actives = @()
    foreach ($row in $rows) {
        $comps = $row.components
        $cam = $comps.$camPath
        if (-not [bool]$cam.is_active) { continue }
        $tf = $comps.$tfPath
        $actives += @{ Entity = [string]$row.entity; T = $tf.translation; R = $tf.rotation }
    }
    if ($actives.Count -eq 0) { throw 'no active camera found in world.query' }
    # 视口 3D 相机：active 且透视。场景预览相机 is_active=false；UI/2D 相机为 Orthographic。
    $fly = $null
    foreach ($c in $actives) {
        $r = Brp-Result (Brp-Call 'world.get_components' @{ entity = $c.Entity; components = @($projPath) })
        $proj = $r.components.$projPath
        if ($null -ne $proj -and $null -ne ($proj.PSObject.Properties | Where-Object Name -eq 'Perspective')) {
            $fly = $c
            break
        }
    }
    if (-not $fly) { throw "no active perspective camera among: $($actives.Entity -join ', ')" }
    # Vec3/Quat 经 reflect 序列化为 JSON 数组：translation=[x,y,z]，rotation=[x,y,z,w]。
    $yp = Get-YawPitch @([double]$fly.R[0], [double]$fly.R[1], [double]$fly.R[2], [double]$fly.R[3])
    return @{
        Entity   = $fly.Entity
        Position = @{
            x = [double]$fly.T[0]; y = [double]$fly.T[1]; z = [double]$fly.T[2]
        }
        Yaw      = $yp.yaw
        Pitch    = $yp.pitch
        Rotation = $fly.R
    }
}

# YXZ 欧拉提取（与 camera_system 的 EulerRot::YXZ 一致）。$Q = @(x, y, z, w)。
# camera_system 恒定 roll=0（Quat::from_euler(YXZ, yaw, pitch, 0.0)），故可用
# 精确闭式：yaw = 2·atan2(qy, qw)，pitch = 2·atan2(qx, qw)。
# 注意：勿用「yaw=atan2(2(wx+yz),1-2(x²+y²)) / pitch=asin(2(wy-zx))」那组公式——
# 对 roll=0 的 YXZ 会把 yaw/pitch 标反（T1 曾因此误判 look 断言失败）。
function Get-YawPitch {
    param([Parameter(Mandatory = $true)][double[]]$Q)
    $yaw = 2 * [Math]::Atan2($Q[1], $Q[3])
    $pitch = 2 * [Math]::Atan2($Q[0], $Q[3])
    return @{ yaw = $yaw; pitch = $pitch }
}

# 相机/modal 复位（用例间复位，手册 §5.6 第 4 条）
function Reset-Modal {
    try { Brp-Result (Brp-Call 'jackdaw/cancel' @{}) | Out-Null } catch { }
}
