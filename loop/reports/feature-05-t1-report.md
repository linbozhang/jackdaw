# feature-05 任务 1 报告：R4 交互驱动手册落地 + R1 视口右键视角重置修复

> 多 Agent 开发循环 · 程序（Rust/Bevy 工程师）· 2026-10-23
> 分支 `loop/interaction-ux`（基于 main 524ce1ab）· 提交 cb9a6661 · 仅改 `src/input_contexts.rs`

## 1. 真因判别实验（定 N 的依据）

方法：临时插桩构建（上升沿 ±2 帧日志 + `JACKDAW_FLY_GRAB` 环境变量切换抓取模式，
插桩已全部回滚、不入 commit），用 `loop/qa/r1-drive.ps1` SendInput 驱动真机编辑器。
档案目录：`loop/reports/r1-disc-*`。

| 组 | 模式 | 按下次数 | 巨 delta | 备注 |
|---|---|---|---|---|
| disc-locked2 | Locked + 静止按下 | 5 | **0** | edge/edge+1/edge+2 delta 全 0 |
| disc-pm-locked | Locked + 移动中按下 | 5 | **0** | edge 帧仅注入的 15px 在途移动 |
| disc-pm-locked8 | Locked + 移动中按下 | 8 | **0** | locked 合计 18 次按下零异常 |
| disc-pm-none | **None** + 移动中按下 | 2 | **2/2** | 见下表 |
| disc-pm-confined | Confined + 移动中按下 | 3 | （fly 未触发） | 环境 flake，无有效数据 |

`r1-disc-pm-none` 的单帧 raw delta（`[R1DBG]` 帧日志，单位 px）：

| 帧 | iter1 | iter2 |
|---|---|---|
| edge（按下帧） | (21401, 30218) len=**37028.78** | (21913, 29733) len=**36935.50** |
| edge+1 | (0, 0) | (262990, 355128) len=**441904.56** |
| edge+2 | (492988, 690804) len=**848673.88** | (197421, 263926) len=**329593.66** |

结论（写进代码注释的因果链）：

1. **真因 = 环境层合成的巨量 raw delta**（方向恒定 ≈(0.71, 1.0)、量级 10^4→10^6 px，
   远超任何真实环视手势；注入值仅 15px）。RDP / 厂商驱动在按下/指针锚定切换瞬间把
   绝对位移当作 raw 相对位移重放——方案候选 1 的「环境合成」家族，且不依赖 1×1 裁剪
   本身（None 模式同样出现）。
2. **本机默认 Locked 下不复现**（18/18 干净）；用户环境显然会在 Locked 下触发——
   Locked 下光标被 ClipCursor 钉住、hover 链路完好，巨 delta 直达
   `camera_system`（yaw −= 10^5×0.003 → 数千 rad/帧、pitch 打到 ±π/2 钳位）＝
   用户「右键按下瞬间视角重置/猛跳」。None 对照组里相机未动，正是因为巨 delta
   携带的光标甩飞破坏了 hover/enabled 门控——反证 Locked 下无此保护。
3. **帧时序（决定 N）**：`GRAB_APPLY` 稳定落在 populate 的 **edge+1**；bevy_winit
   `changed_cursor_options` 在该帧 `Last` 才调 `ClipCursor`，故裁剪引发的合成 delta
   最早在 **edge+2** 被 populate 读到；观测巨 delta 落点恰为 {edge, edge+1, edge+2}。
   **N = 3**（方案 D3 的 1/2 帧不够：方案假设 grab 在 press 帧或次帧 PreUpdate 生效，
   实测它在次帧 Last 生效，晚一整帧）。

## 2. 修复内容（`src/input_contexts.rs`，+147 行，单文件）

- 常量 `FLY_LOOK_SUPPRESS_FRAMES = 3`（含完整因果注释）。
- `populate_camera_nav_input` 增加 `Local<u32>` 会话年龄计数器：fly 上升沿起
  **前 3 帧 look_delta 置零**（edge/edge+1/edge+2），第 4 帧起正常；松开即复位，
  再次按下重新抑制。**WASD/QE（move_axes）与滚轮（zoom_ticks）路径一字未动。**
- 回归单测 ×4（populate 层 headless）：巨 delta 上升沿丢 3 帧后第 4 帧直通、
  松开重按复位抑制窗、非 fly 时 delta 直通（不误伤）、抑制帧内 move_axes/zoom 照常。
  `input_contexts` 模块 9/9 通过。
- 临时插桩（R1DBG 日志、JACKDAW_FLY_GRAB、viewport.rs 改动）全部回滚，不在 diff 中。

## 3. 各门退出码

| 门 | 退出码 | 备注 |
|---|---|---|
| `cargo fmt --all -- --check` | 0 | |
| `cargo clippy --workspace -- -D warnings` | 0 | |
| `cargo xtask fast` | 0 | 2802 passed / 2 skipped |
| `cargo xtask integration` | 0 | 4933 passed / 3 skipped |

## 4. 真机验证数字（修复前对照 vs 修复后）

修复后（`loop/reports/r1-fixed-final/metrics.csv`，Full ×10，SendInput 驱动，
BRP `world.query`/`world.get_components` 断言）：

- **按下不动 500ms（R1 主断言，容差 0.005 rad）**：dyaw=dpitch=**0.000000 ×10** →
  10/10 PASS（含 ±2px jiggle + 按下瞬间在途运动场景之外的标准路径）。
- **按住拖 20×(15,0)（环视）**：yaw 每轮精确 **−0.900000 rad**（= 300px×0.003），
  pitch 变化 **0.000000** ×10（iter4 记录 5.383 为 ±π 角度回绕，实际 0.9）。
- **W 按住 400ms（位移回归）**：3.995~4.172 units（理论 10×0.4=4.0）×10。
- pitch 全程恒 −0.4636（初始视角），无漂移、无 roll。

修复前对照（判别档案，同脚本同机器）：

- Locked 18 次按下（静止 5 + 移动中 13）：旋转变化 **0**（本机 Locked 不触发环境合成，
  无法直接重现用户症状——症状依赖用户输入环境）；
- None 2 次按下：单帧巨 delta len 37028→848674（= 真因因子在场实证）；同帧
  BRP 读数旋转变化 0（None 下光标甩飞破坏 hover 门控，见 §1.2 机制讨论）；
- 修复对巨 delta 的拦截由单测 `look_discarded_on_fly_rising_edge_then_passes`
  直接覆盖（喂入 iter1 实测的 (492988, 690804) 断言为 0）。

测量层勘误（教训）：第一轮 fixed-full 的 look 断言全 False 是 QA 脚本欧拉提取公式
把 yaw/pitch 标反（roll-free YXZ 应为 ψ=2·atan2(y,w)、θ=2·atan2(x,w)），修正后
所有历史数据完全自洽；`brp.ps1` 已留注释防再犯。**编辑器行为从未异常。**

## 5. loop/qa/ 脚本清单与用法（不入 git）

| 文件 | 用途 |
|---|---|
| `manual.md` | R4 手册落地版（方案 §5 誊抄 + 实测校正：`world.*` 方法名、类型路径、watching null 轮询、SetCursorPos 不被 winit 记账等） |
| `brp.ps1` | BRP 封装：`Brp-Call`/`Wait-EditorReady`/`Wait-BrpResult`/`Get-FlyCamera`/`Get-YawPitch` |
| `input.ps1` | SendInput OS 级注入：RMB/按键/相对移动/窗口定位/焦点 |
| `screenshot.ps1` | PrintWindow 全窗口截图 |
| `r1-drive.ps1` | R1 场景：`-Drive Press|PressMoving|Full`、`-Repeat N`、`-GrabEnv`（判别版专用）、`-Label` |

复跑示例：
`powershell -ExecutionPolicy Bypass -File loop\qa\r1-drive.ps1 -Drive Full -Repeat 10 -Label rerun`

## 6. 遗留

1. confined 判别组因环境 flake（fly 未触发）无数据；不影响结论（巨 delta 与抓取模式
   无关已由 None 组证明）。
2. 本机无法按需重现 Locked 巨 delta（环境相关间歇触发）；若用户环境合成持续 >3 帧，
   调大 `FLY_LOOK_SUPPRESS_FRAMES` 即可（常量化后备，方案风险 1）。
3. 方案 T1 附带项「ActiveTool/EditMode 补 Reflect 注册」主控任务书中未列入本次范围，
   未做（服务 T2/T3 QA 断言，建议随 T2 顺手）。
4. `.ps1` 需 UTF-8 BOM（PS 5.1 无 BOM 会按 ANSI 解析中文注释报语法错）——已在脚本
   内自我规避，但直接编辑器另存时注意。
