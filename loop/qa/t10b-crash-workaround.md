# T10b 绕行指南：0xc0000005 启动崩溃（nvcuda64.dll，NVIDIA 591.86）

> 适用症状：jackdaw 编辑器 PIE、schema extractor、或直接跑的 bevy 游戏进程在启动
> 几秒内死亡，exit code `0xc0000005`（STATUS_ACCESS_VIOLATION），游戏日志止于
> `AdapterInfo { ... backend: Vulkan, driver: "NVIDIA" ... }` 之后、
> `Creating new window` 之前。T10b 调查时段（10-28 05:16–05:27）实证 + 事件日志
> 61 样本零例外，全部 `nvcuda64.dll @ 0x3ab984`（驱动 591.86）。
>
> 根因（裁定依据见 `loop/reports/t10b-report.md`）：NVIDIA 驱动 591.86 的
> `nvcuda64.dll` 在 wgpu Vulkan 后端初始化时段对特定**进程创建形态**崩溃，
> 属环境问题，非 jackdaw/游戏代码缺陷。
>
> **⚠ 时效性警告（2026-10-28 05:26–05:40 观察到驱动态再度转变）**：本机驱动
> 591.86 已呈现**两段行为**——转变前（05:16–05:27）Start-Process×Vulkan 必崩、
> `WGPU_BACKEND=dx12` 的 game 落 AMD 集显可活；转变后（05:37–05:59，QA 与 T10b
> 返工复测合并）Start-Process×Vulkan 复活（3/3 活）、game 的 DX12 枚举改落
> **NVIDIA** 且设备创建 OOM（`Queue creation failed 0x8007000E` →
> `RequestDeviceError(OutOfMemory)` panic，4/4）。**任何绕行前先做 §一 的时效性
> 核对，再按 §二 当下实测态选择。**

## 一、时效性核对（先做，30 秒）

### 1a. 确认崩溃是否仍是本问题 + 是否仍在发生

```powershell
Get-WinEvent -MaxEvents 5 -FilterHashtable @{LogName='Application'; Id=1000} |
  Where-Object { $_.Message -match 'phys-game|mygame|jackdaw' } |
  ForEach-Object { ($_.Message -split "`n")[0..3] -join "`n" }
```

- 命中 `出错模块名称: nvcuda64.dll` + `异常代码: 0xc0000005` = 本问题家族；
- **最近 10 分钟无新增** → 驱动态可能已转变，直接按 §二 当前实测态跑默认形态，
  不要预先设置任何 WGPU_BACKEND；
- **最近 10 分钟有新增** → 处于崩溃态，按 §二 场景 1/2 绕行；
- 模块若是别的（如 `nvoglv64.dll`、应用自身偏移）→ 按新问题另查，勿套用本指南。

### 1b. 若准备用 dx12 绕行，先验 game 的 DX12 落点可用性

game 进程的 DX12 适配器枚举落点是**运行时决定、已两次漂移**（AMD→NVIDIA，
05:20→05:45 之间），且落 NVIDIA 后设备创建 OOM panic（4/4 实测）。用前先单跑
一次 game 验证：

```powershell
$env:WGPU_BACKEND='dx12'; cmd /c "start /B /D H:\workspace_AI\t10-phys\phys-game cmd /c ""H:\workspace_AI\t10-phys\phys-game\target\debug\phys-game.exe > H:\workspace_AI\dx12-probe.log 2>&1"""
# 15 秒后看 dx12-probe.log：有 AdapterInfo 且无 panic = dx12 当前可用；出现
# "Queue creation failed" / RequestDeviceError(OutOfMemory) = dx12 当前不可用，撤变量。
Remove-Item Env:WGPU_BACKEND
```

## 二、按场景绕行

### 当前实测态速查（2026-10-28 05:37–05:59，QA + 返工复测合并）

| 形态 | T10b 时段（05:16–05:27） | 当前（05:37–05:59） |
|---|---|---|
| PS `Start-Process` × Vulkan game | ✗ 崩 5/5 | **✓ 活 3/3** |
| `cmd start /B` × Vulkan game | ✓ | ✓ 1/1 |
| game `WGPU_BACKEND=dx12` | ✓（当时落 AMD） | **✗ OOM panic 4/4**（落 NVIDIA） |
| 编辑器（NVIDIA DX12） | ✓ | ✓（五份日志实证从未崩） |
| 编辑器 spawn 的 PIE game（默认 Vulkan） | ✗ 崩（P1/P2） | **✓ 连通（P1'r3/r4）** |
| 编辑器 spawn 的 PIE game（dx12） | ✓ 连通（P3，但见 §四 panic） | ✗ game panic 不连接（P3'） |

**当下结论：默认形态（不设任何 WGPU_BACKEND）即可用；`WGPU_BACKEND=dx12`
在 game/PIE 通道当下有害，禁用直至 §一-1b 复验通过。**

### 场景 1：脚本直跑游戏（QA/CI direct run）

- 稳态推荐：`cmd /c "start /B /D <game_dir> cmd /c ""<game.exe> > out.log 2>&1""`
  ——两个驱动态下均存活的唯一直跑形态（T10-T2/T3 前科 + 两轮复测）。
- `Start-Process` 在崩溃态必崩（历史 5/5）；当前虽复活（3/3），脚本仍建议统一
  `start /B`，一份脚本对两态都稳。
- `cargo run` 轴同理。

### 场景 2：编辑器 PIE 全链

- **崩溃态时**（§一-1a 有新增事件）：`start /B` 启动编辑器 + `$env:WGPU_BACKEND='dx12'`
  （P3 实证当时可连通）——**前提是 §一-1b 探针通过**；探针不过则该态下 PIE 只能等
  驱动侧处理（更新/回滚 591.86），无 game 侧绕行。
- **当前态**（05:37+ 实测）：不设任何变量，`start /B` 启动编辑器直接
  `pie.play_current`（P1'r3/r4 连通）。
- 注意 PIE 首次 play 前有后台增量构建，暖工程实测可长达 ~2 分钟（05:54–05:56
  一轮 115s）——脚本判活窗给足，勿在构建完成前判死。

### 场景 3：交互手测（真人前台）

双击运行、交互终端里 `cargo run` / 直接跑 exe：**两个驱动态下均未复现崩溃**，
无需任何绕行。

## 三、注意事项

- **判活双通道**：统一用「BRP `jackdaw/status` 应答 + 事件日志零新增」双通道；
  单看 exit code 会漏判——Redirect 形态下 panic(101) 的 ExitCode 实测显示 0x0
  （QA R2b 实证），必须配合 stderr/日志。
- game 的 DX12 落点与后端可用性随时可漂移（本机已两次）；任何「落谁家」的静态
  断言都以启动日志的 AdapterInfo 行为准，不预设。
- 编辑器进程的 DX12 落点在本机全部轮次均为 NVIDIA RTX 5070（五份日志）且从未
  崩溃——NVIDIA+DX12 在**编辑器进程**稳定成立；不能外推到 game 进程（见上条）。
- 根治路径不变：更新或回滚 NVIDIA 驱动（591.86 已呈现两段劣化形态 + 10-24
  nvoglv64 前科 + NVDisplay.Container 自崩前科）。驱动更换后复跑 T10b 报告
  §八矩阵（至少 A/C/P1/P3 四格）确认清除，再撤一切 WGPU_BACKEND。

## 四、附带观察（另账，勿并入 0xc0000005）

P3 时段（05:31）PIE connected 后 ~1.9 秒编辑器主线程出现
`drain_game_events` exclusive system 内 `swap_remove index (is 1) should be
< len (is 1)` panic（bevy 捕获不退出）。返工复测（P1'r4，connected 后保持
20s）零复发——非必现。与 nvcuda64 崩溃无关（编辑器进程、ECS 内部越界），
特性刻画与嫌疑链见 `loop/reports/t10b-report.md` §九，已建议主控另立项。
