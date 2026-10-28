# T10b 调查报告：0xc0000005 启动崩溃根因定位（插队小任务）

> 任务：插队 T10b「0xc0000005 启动崩溃调查」（T10-T2 QA §四②/T10-T3 🟡-1 立账兑现）。
> 分支 `loop/t10b-crash`（基于 main）；**纯调查零代码改动**，无提交、门禁免跑（如实声明）。
> 开局自检：仅既存噪音（.gitignore M、buglist.md 未跟踪），未触碰。
> 证据归档：`loop/t10b-live/`（p1 崩溃编辑器日志 / p3 dx12 连通编辑器日志（尾部含
> drain panic 原件）/ 事件日志摘录 eventlog-0516-0527.txt + 返工复跑 p1r/p3r 系列）；
> 绕行指南：`loop/qa/t10b-crash-workaround.md`。
> 调查窗口：2026-10-28 05:16–05:31（首轮矩阵）；QA 核验 05:37–05:48；返工复测 05:52–05:59。
> **修订记录（v2，2026-10-28 返工轮）**：按 QA 核验报告 `t10b-qa.md`（PASS 有条件）
> 修正 §三/§四-1/§六-3 的 DX12 适配器误读、§七-2 撤回「P3 全链恢复」；新增 §八
> 驱动态再度转变观察与 P1'/P3' 复跑、§九 drain_game_events panic 特性刻画（立账材料）；
> 计数与时间线按 QA 实测校正（10-27 时段 33 条、主动复现 8 条、P3 实际执行 05:30:58–05:31:08）。

## 一、结论速览

**根因裁定：b) 环境（NVIDIA 驱动 591.86 的 nvcuda64.dll 于 wgpu Vulkan 后端初始化时段
对特定进程创建形态崩溃，固定偏移 0x3ab984）为主因，c) 工具链边界（PowerShell
Start-Process 与「编辑器内 spawn」两条进程创建路径是触发形态）为辅。a) 代码缺陷排除。**

处置 = 明确归因 + 绕行指南（`loop/qa/t10b-crash-workaround.md`），不做代码修复
（jackdaw 侧无可修缺陷；见 §五）。T2 的「windowless PIE × JackdawRemotePlugin 组合」
二分定性**被推翻**（§四-3）。

## 二、决定性被动证据：Windows 事件日志

`Get-WinEvent`（Application, Id=1000）全量拉取 2026-10-27~28 与 phys-game/mygame/jackdaw
相关崩溃，**所有样本零例外**：

- 出错模块：**nvcuda64.dll**，版本 32.0.15.9186（= 驱动 591.86，nvidia-smi 互证，
  RTX 5070），路径 `DriverStore\FileRepository\nv_dispi.inf_amd64_...`
- 异常代码：0xc0000005；**错误偏移全部同一值 0x00000000003ab984**
- 覆盖形态：phys-game debug / **release / dist-run 导出 exe** / mygame.exe
  （scaffold e2e 临时工程）——即 T2 direct run、T2 PIE、T3 格 1/9/12 的全部历史崩溃
  事件都在事件日志里且同模块同偏移
- 时间分布：10-27 20:23–23:52 共 33 条（T3 程序/QA 会话，QA 复核计数）；10-28 00:22–04:03
  共 10+ 条；本调查 05:16–05:27 主动复现 8 条。**当前驱动态自至少 10-27 20:23 持续至
  05:26（最后一条 nvcuda64 AV 为 P2 第二条 05:26:23），05:26–05:40 间再度转变（见 §八）**
- 唯一异类：10-27 01:44 my-game.exe 崩在**应用自身偏移** 0x9fb458b——早前无关事件，不入本账

崩溃点（全部样本一致）：游戏日志止于 `AdapterInfo { backend: Vulkan, driver: "NVIDIA",
driver_info: "591.86" }` 之后、`Creating new window` 之前——正是 NVIDIA Vulkan ICD 拉起
CUDA 用户态驱动（nvcuda64.dll）做设备初始化的时段。

## 三、形态矩阵（亲跑 15 格，全部同暖工程同二进制）

| # | 进程创建形态 | 目标/后端 | 结果 |
|---|---|---|---|
| A | PS Start-Process + Redirect + 直接 exe | 默认(Vulkan) | ✗ 崩（05:16:57 事件日志） |
| B | PS Start-Process + Redirect + cargo run | Vulkan | ✗ 崩（05:17:36） |
| A' | PS Start-Process **无** Redirect | Vulkan | ✗ 崩（05:21:48）→ 文件句柄非诱因 |
| F | PS Start-Process + 显式 `WGPU_BACKEND=vulkan` | Vulkan | ✗ 崩（05:19:54）→ 排除「设环境变量」安慰剂 |
| C | cmd **start /B** + 文件重定向 + 直接 exe | Vulkan | ✓ 窗口创建成功（QA 前科形态复现） |
| D | cmd start /B + 文件重定向 + cargo run | Vulkan | ✓ |
| E | PS Start-Process + `WGPU_BACKEND=dx12` | DX12（**当时落 AMD 集显**） | ✓ ——崩溃宿主下切后端即绕（**当时**；落点已漂移，见 §八） |
| E3 | 同 E + `WGPU_POWER_PREF=high` | DX12（仍 AMD，当时） | ✓（power pref/`WGPU_ADAPTER_NAME` 均未切到 NVIDIA DX12） |
| S | PS Start-Process + Redirect + `cmd /c ver` | 非 GPU exe | ✓ exit 0 → **「管道宿主启动任何 exe 都崩」宽假设排除** |
| R1 | 纯 Rust `std::process::Command` + stderr piped（target\debug exe） | Vulkan | ✓ |
| R4 | R1 + `JACKDAW_PIE_WINDOWLESS=1` | Vulkan | ✓ → windowless env 非诱因 |
| R6 | R1 但换 **PIE 构建的 game exe**（.jackdaw\target\game\debug） | Vulkan | ✓ → 该 exe 无罪 |
| R5 | R1 + `JACKDAW_PIE`（无真实 IPC server） | Vulkan | 渲染初始化通过，exit 101（IPC panic，非 AV）→ PIE env 不触发渲染期崩溃 |
| P1 | **编辑器 spawn** PIE windowless（编辑器 start /B、stdout=文件→子进程加 CREATE_NO_WINDOW） | Vulkan | ✗ 崩×2（game + schema extractor，05:25:12/19）——T2 PIE/T3 格 12 形态复现 |
| P2 | 编辑器 spawn PIE（编辑器 `start /D` 新 conhost、stdout=终端→子进程**不加** CREATE_NO_WINDOW） | Vulkan | ✗ 崩×2（05:26:16/23）→ **CREATE_NO_WINDOW 非决定因素** |
| P3 | 编辑器 + `WGPU_BACKEND=dx12` spawn PIE | DX12（game 时落 AMD） | ✓ PIE launched→连接成功→零崩溃事件（**连接 1.9s 后编辑器 drain panic，见 §九；「全链可用」表述由 §八复测重估**） |

补充对照：成功运行的 Vulkan 进程模块清单里 **nvcuda64.dll（连同 nvoglv64/nvapi64/
nvgpucomp64/nvrtum64）均在加载**——即两种宿主下驱动模块都会加载，分岔在驱动**初始化
路径**对进程创建形态的敏感性，而非「加载与否」。

T2「环境间歇性」口径修正：Start-Process 形态本机 5/5 全崩（100%）——所谓「间歇」实为
**启动形态差异**（程序当时跑通 = 交互终端 / start /B 形态；QA 崩 = Start-Process 形态）。

## 四、根因三分类裁定（逐条证据）

### 1. a) 代码缺陷 —— 排除

- 崩溃帧在 NVIDIA 驱动模块内固定偏移，非 jackdaw/游戏任何代码地址；
- 同一二进制在 4 类合法启动形态下 3 类完全正常（start /B / 纯 Rust Command / DX12 后端），
  每类多格复现；
- 编辑器侧无嫌疑：编辑器自身全程零崩溃；其进程 DX12 落点在**全部五份日志**（p1/p3/
  p1r/p1r2/p3r）中均为 **NVIDIA RTX 5070 + Dx12** 且稳定运行——编辑器=NVIDIA DX12 的
  稳定实证反而修正了首轮报告「编辑器=DX12+AMD」的误读（首轮把 game 进程当时的 DX12
  落点错误嫁接给了编辑器进程；`render_backend.rs` 只定后端 DX12 不定适配器，落点由
  运行时枚举决定且进程间不同、随时可漂移）；
- 游戏/PIE 的 spawn 写法（piped stderr、CREATE_NO_WINDOW 条件加、PIE env）均为正当
  工程实践且逐一被 R4/R6/P2 实验剥离后证明非诱因。

### 2. b) 环境（NVIDIA 驱动）—— 主因，成立

- 40+ 历史样本 + 9 主动复现全部 nvcuda64.dll@0x3ab984，驱动 591.86（RTX 5070）；
- 触发面 = wgpu **Vulkan 后端**初始化 ×（PS Start-Process 或编辑器内 spawn）；后端切
  DX12 立即豁免（E/P3），宿主换 start /B 立即豁免（C/D）；
- NVIDIA 驱动态劣化**前科**在案：2026-10-24 全机 nvoglv64.dll 损坏（重启即解）。
  本次为同家族不同模块（nvcuda64），且持续 30+ 小时未自愈；
- 偏移所在函数未能符号化（无 NVIDIA PDB，黑盒）——不影响归因（模块+版本+偏移一致性已足）。

### 3. c) 工具链边界 —— 辅因（构成触发面），部分成立

- PS Start-Process 与 cmd start /B 是可复现的触发/豁免开关（A vs C 全参数对照）；
- bash 管道宿主链**本身无罪**：C/D/R1-R6 全部在同一管道链内跑出存活；
- PIE 崩溃专属层：编辑器（bevy 渲染进程）spawn 的子进程崩（P1/P2），同一 exe 用纯进程
  最小 Command spawn 则活（R6）——差异收敛到「父进程为编辑器」的某属性（候选：父进程
  已持有 GPU 上下文导致的驱动并发初始化竞态、STARTUPINFO 细节）。该层机制未继续二分，
  归因决策不需要（无论机制如何，故障帧在驱动内）。

### T2 旧定性推翻

「windowless PIE × JackdawRemotePlugin 组合」不成立（指 **T2 程序报告**的二分定性；
T2 QA 记档 §四②当时已自行扩界为「非 windowless 特有、与宿主环境相关」，与 T10b 结论
同向，不在被推翻之列）：JackdawRemotePlugin 在崩格（A/A' direct run 无 PIE IPC）与活格
（R4/R6 带 windowless/同 exe）中均不在差异面；windowless env 同样被 R4 剥离。T2 当时的
二分维度没覆盖「进程宿主」，程序报告的结论是维度缺失下的局部最优。

## 五、处置与绕行指南

- **不做代码修复**：崩溃在驱动内，jackdaw 侧无可修缺陷。曾评估「Windows 下 PIE/extractor
  spawn 时强制子进程 WGPU_BACKEND=dx12」的防御性修复——不采纳并记为开放选项：会改变
  所有机器的后端选择（不少机器 Vulkan 更优）、掩盖驱动问题，且环境级变量即可干净绕行。
  **该裁定获 §八驱动态转变的事后强佐证**：dx12 绕行的前提（game 落 AMD）在 05:26–05:40
  间失效，game 的 DX12 枚举改落 NVIDIA 后设备创建 OOM panic——若当时采纳硬编码修复，
  现在等于把 game 永久锁死在必 panic 路径上。
- **指南已落盘并按返工轮重写**：`loop/qa/t10b-crash-workaround.md`——时效性核对（事件
  日志近 10 分钟增量判态 + dx12 探针前置验证）→ 两段驱动态实测速查表 → 三场景绕行
  （崩溃态/当前态分开）→ 判活双通道纪律 → 根治路径（更新/回滚 591.86）。
- **T10-T3 🟡-1 台账兑现**：0xc0000005 调查已立项并完成（本报告即立项交付物）；T2 §四②
  的 T3 处置建议同步闭环。

## 六、偏差分级与调查限制

- 🔴 严重：0；🟡 中等：0；⚪ 轻微（调查限制与首轮误读，返工轮已修，如实记档）：
  1. nvcuda64.dll 偏移 0x3ab984 所在函数未符号化（NVIDIA 无公开 PDB）；
  2. 「编辑器内 spawn 崩 / 纯进程 spawn 活」的精确机制未继续二分（候选：父 GPU 上下文
     竞态/STARTUPINFO）——归因不需要，留驱动态自证；
  3. **（v2 修正）**首轮「编辑器=DX12+AMD」「NVIDIA+DX12 未实测」为证据误读——编辑器
     进程实落 **NVIDIA DX12**（p1/p3/p1r/p1r2/p3r 五份 AdapterInfo 实证稳定运行）；
     game 进程的 DX12 落点系运行时枚举、本机已两次漂移（AMD→NVIDIA），落 NVIDIA 后
     设备创建 OOM panic（§八）——NVIDIA+DX12 的安全性**按进程、按时刻分别核对**，
     不存在静态结论；
  4. **（v2 补记）**P3 尾部 drain_game_events panic 首轮漏记，已补 §九刻画。
- 环境恢复动作（两轮）：实验进程清零（phys-game/jackdaw/mygame/orphans=0，返工轮终查
  同零）；首轮临时复现器与 10 组实验 stdio 日志已删；证据归档 `loop/t10b-live/`（首轮
  p1/p3/事件日志摘录 + 返工轮 p1r2/p1r3/p1r4/p3r 编辑器日志）；暖工程零持久改动
  （PIE 复测轮会重编 .jackdaw\target\game 的 game exe——构建产物更新属编辑器正常行为，
  非源码改动）。

## 七、对下游任务的可用结论（v2 按 §八复测重估）

1. QA 真机矩阵的「启动稳定性」从「环境间歇不可控」升级为「已知形态矩阵 × 时效性核对」：
   `start /B` 是两个驱动态下都稳定的唯一直跑形态（入 QA 纪律）；`WGPU_BACKEND=dx12`
   **不再是普适豁免开关**（当前态 game 侧必 panic，4/4），仅当指南 §一-1b 探针通过时可用。
2. PIE 通道（格 12 家族）：当前驱动态下**默认形态**（不设任何变量、`start /B` 编辑器）
   已实测连通（P1'r3/r4），T2-T3 的 PIE 降级链在当前态可解除；但 PIE 全链稳定性另受
   §九 drain panic 支配（非必现、另账），PIE 相关验收建议加「connected 后保持 ≥20s」
   观察窗。
3. 驱动更换后应复跑本报告矩阵（至少 A/C/P1/P3 四格）确认驱动态清除，并撤回一切
   WGPU_BACKEND；复跑脚本可直接复用 QA 归档 `loop/qa/t10b-qa-matrix*.ps1`。

## 八、（v2 新增）驱动态于 05:26–05:40 间再度转变：QA 复测 + 返工复跑

QA 核验（05:37–05:48）与返工复测（05:52–05:59）合并的当下矩阵：

| 形态 | 首轮（05:16–05:27） | 复测（05:37–05:59） | 证据 |
|---|---|---|---|
| PS Start-Process × Vulkan game | ✗ 崩 5/5 | **✓ 活 3/3**（QA CELL1/R2a ×2） | QA 矩阵日志 c1/r2a |
| cmd start /B × Vulkan game | ✓ | ✓（QA CELL2，BRP 200） | QA c2 |
| game `WGPU_BACKEND=dx12` | ✓（落 AMD） | **✗ OOM panic 4/4**（DX12 枚举改落 NVIDIA，`Queue creation failed 0x8007000E`→`RequestDeviceError(OutOfMemory)` unwrap panic） | QA R2b/R3 + 返工 P3' |
| 编辑器（NVIDIA DX12） | ✓ | ✓ | p1/p3/p1r/p1r2/p3r 五份日志 |
| 编辑器 spawn PIE game（默认 Vulkan） | ✗ 崩（P1/P2） | **✓ 连通**（P1'r3 连接成功；P1'r4 连接后 20s 双活零崩溃） | p1r3/p1r4 日志 |
| 编辑器 spawn PIE game（dx12） | ✓ 连通（P3） | ✗ game OOM panic 不连接（P3'） | p3r 日志 |

要点：
1. **nvcuda64 AV 态已消退**（最后一条 05:26:23；此后 Start-Process×Vulkan 复活）——
   首轮矩阵对「当时」仍成立（事件日志背书），但静态结论不可外推，一切以指南 §一
   时效性核对的当下读数为准。
2. **game 的 DX12 枚举落点漂移**（AMD→NVIDIA，05:20→05:45 之间）且落 NVIDIA 后设备
   创建 OOM——与编辑器进程（始终 NVIDIA DX12 稳定）形成进程间对照，进一步支持
   「驱动/系统层适配器报告不稳定」的环境归因。
3. PIE 首次 play 的后台增量构建在本工程实测可达 ~115s（P1'r2：05:54:49 play →
   05:56:44 exe 落盘），脚本判活窗须按分钟级给足。
4. 复测各轮收尾进程清零；无 WGPU_BACKEND 残留（会话级，P3' 后 Remove-Item）。

## 九、（v2 新增，立账材料）drain_game_events swap_remove panic 特性刻画

**现象（P3 原件 `loop/t10b-live/p3-pie-dx12-ok-editor.log:41-44`）**：
`thread 'main' panicked at library\alloc\src\vec\mod.rs:2258: swap_remove index (is 1)
should be < len (is 1)`，报点 `bevy_ecs::error::handler` 记录为 exclusive system
`jackdaw::pie::drain_game_events` panic（bevy 默认 handler 捕获，**编辑器不退出**，
PIE 事件流中断）。时间线：21:31:06.455 `PIE: Play #1 connected` → 21:31:08.32 panic
（连接后 ~1.9s）。

**定位链（无 backtrace，按代码面收敛）**：
1. `src/pie.rs:2564-2679` drain_game_events 本体**无** swap_remove；
2. 仓内仅 `crates/jackdaw_widgets/src/tree_view.rs:186/211` 两处，且均带
   `position()` 护航（Some(at) 必然 at<len）——**不可能产生该断言**；
3. 断言必来自依赖内标准 `Vec::swap_remove`。bevy fork（c9c397ba）bevy_ecs 内无护航
   候选：`archetype.rs:630`（bundle insert/remove 引发的 archetype 迁移删实体行）、
   `table/mod.rs:255/765`（表实体行）、`sparse_set.rs:717`（稀疏集 dense 索引删）；
   relationship（Children/ChildOf）路径带 `index<len` 护航可排除。
4. 「index 1, len 1」＝极小 vec 越界一格，与**陈旧 EntityLocation/ArchetypeRow**
   （实体刚被迁走、旧行号再次用于 swap_remove）的 panic 形态吻合——重入/交错操作特征。
5. drain 六条子路径中唯一做 ECS 结构写（spawn/despawn/insert/层级）的是
   `pie_projection::project_event`（镜像实体投影）；connected 后 ~2s 正是全量场景
   镜像投影窗口（几十实体连环 insert/层级变更）——时间点与高频路径吻合。

**与 N10 修复区的关系（对照 `loop/reports/n10-fix-report.md`）**：
- N10 主修复（drain 256 帧/4ms 双预算，transport_ipc.rs）只界定 drain 的**时长/批大小**，
  不改变 ECS 操作序列——与本 panic 无已证因果（既非引入也非修复面）；
- N10 次嫌疑 1（ipc try_recv 遇部分消息转 INFINITE 阻塞）：症状是**卡顿**非越界——排除
  直接成因；
- N10 次嫌疑 2（accept task detach 泄漏）：症状是**泄漏**——排除直接成因。
- 结论：本 panic 为**第三种独立问题**，与 N10 记档三项症状类型均不同。

**可复现性初判**：1 hit（P3，05:31，dx12 PIE、game 落 AMD）/ 1 clean（P1'r4，05:58，
默认 Vulkan PIE，connected 后保持 20s 零复发）+2 无观察窗样本（P1'r3 即连即杀、T2 probe
时代久远不可考）——**非必现**；hit 与 clean 分属 dx12/Vulkan 两形态，样本量不足以判别
「形态相关」还是「纯时序运气」。建议立账后以「PIE connected ×10 连跑（两形态各半，
每次 connected 后保持 ≥20s）」定复发率与形态相关性。

**嫌疑链排序（供立项调查）**：
①镜像投影重入/交错（project_event 在同一 exclusive system 内连环结构操作 × observer
链，connected 初期全量投影窗口最重）→ ②bevy_ecs 陈旧 location 类缺陷（fork c9c397ba
层面，archetype/table 行操作无护航断言点）→ ③上游树索引数据竞态（tree_view 自身
swap_remove 已被护航排除，但其输入 by_row/by_source 的交错更新未排除）。

**严重度建议**：编辑器主线程 panic（被 bevy 捕获不退出，但 PIE 事件流中断、当帧状态
不可信）——🔴 级潜伏缺陷候选；**与 0xc0000005 无关**（编辑器进程、ECS 内部越界、
非驱动模块），建议主控另立小任务调查（带 RUST_BACKTRACE=1 复跑拿真栈是第一步）。
