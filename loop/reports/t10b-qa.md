# T10b QA 核验报告：0xc0000005 启动崩溃调查（只验不修）

> 核验对象：`loop/reports/t10b-report.md`（主报告）+ `loop/qa/t10b-crash-workaround.md`（绕行指南）
> + `loop/t10b-live/` 证据三件；T10b 为纯调查零代码改动，main=7dc1f7a8 无新提交（开局核对一致）。
> QA 方法：事件日志独立拉取复核（自写解析脚本，近 5 天全量）、真机矩阵抽验 3 格 + 补跑 2 轮
> （暖工程 `H:\workspace_AI\t10-phys\phys-game\target\debug\phys-game.exe`，三轮共 6 次启动，进程清零）、
> 两份旧 QA 报告崩溃段对照审查、`src/render_backend.rs` 实读、指南命令逐条实测。
> QA 证据：脚本归档 `loop/qa/t10b-qa-eventlog.ps1` / `t10b-qa-matrix{,2,3}.ps1`；
> 真机日志留档 `H:\workspace_AI\t10b-qa\`（c1/c2/r2a/r2b/r3 的 out/err）。
> 核验窗口：2026-10-28 05:37–05:48（紧接调查窗口 05:16–05:27 之后）。

## 一、核验面 1：事件日志独立复核——**声明成立（61/61 零例外）**

自写脚本（FilterHashtable 拉 Application/Id=1000 近 5 天全量 76 条，按消息行结构解析
app/模块/异常码/偏移，不依赖程序归档）：

- **0xc0000005 共 65 条，其中 jackdaw 家族应用（phys-game.exe / mygame.exe / my-game.exe）
  共 61 条，全部 `nvcuda64.dll @ 0x00000000003ab984`，零例外**——远超 ≥5 条抽查要求。
  时间跨度 10-27 20:23:17 → 10-28 05:26:23，与报告「持续 30+ 小时未自愈（至调查结束）」一致。
- 异模块 0xc0000005 样本 3 起（YunShu Plugin.exe@unknown、NVDisplay.Container.exe@nvxdplcy.dll），
  **均非 jackdaw 家族应用，落在报告声明范围（phys-game/mygame/jackdaw 相关）之外**，不构成
  「零例外」声明的反例；如实记档。
- **10-24 nvoglv64.dll 前科独立证实**：10-24 20:00:12/20:02:10 两条 `jackdaw.exe × nvoglv64.dll
  @ 0xb7bd7f`（0xc0000005）在档——报告 §四-2「前科在案」属实。
- 「唯一异类 10-27 01:44 my-game.exe 应用自身偏移 0x9fb458b」独立复核精确一致
  （实测该条为 0xc0000409 @ 0x00000000009fb458b）。
- 驱动版本互证：nvidia-smi 实测 `591.86, NVIDIA GeForce RTX 5070`；归档摘录 8 条模块版本
  32.0.15.9186；p1/p3 编辑器日志同时出现 DX12 视角 `driver: "32.0.15.9186"` 与 Vulkan 视角
  `driver_info: "591.86"`——映射自洽。
- 计数出入（⚪-1，不改结论）：报告「10-27 20:23–23:52 共 32 条」实测 **33** 条；
  「主动复现 9 条」实测 **8** 条（归档摘录亦 8 条；矩阵时间戳 8 个全部与事件日志对上）。

## 二、核验面 2：形态矩阵真机抽验——**3 格中 1 格符合；2 格偏离，系驱动态已再度转变（非报告失实）**

三轮真机（同 exe、cwd=工程根、判活双通道=进程态+事件日志边界增量；BRP 探测加分项）：

| 轮次 | 形态（对应 T10b 格） | 报告预期 | 实测 | 实测后端/适配器 |
|---|---|---|---|---|
| CELL1 05:40 | PS Start-Process+Redirect（A） | ✗ 崩 | **✓ 存活 90s，零崩溃事件** | Vulkan / NVIDIA 591.86 |
| CELL2 05:41 | cmd start /B+重定向（C） | ✓ 活 | **✓ 存活**，'Creating new window' 在 log，BRP :15702 HTTP 200，零崩溃事件 | Vulkan / NVIDIA 591.86 |
| CELL3 05:42 | Start-Process+WGPU_BACKEND=dx12（E） | ✓ 活 | **✗ exit 0x65(101)**，零崩溃事件 | （未捕获） |
| R2a 05:45 | 同 CELL1（A 二次） | ✗ 崩 | **✓ 存活 45s** | Vulkan / NVIDIA 591.86 |
| R2b 05:46 | 同 CELL3+stderr 捕获（E） | ✓ 活 | **✗ panic**：DX12 枚举落 **NVIDIA**，`Queue creation failed 0x8007000E` → `RequestDeviceError(OutOfMemory)` → bevy renderer unwrap panic | **DX12 / NVIDIA** |
| R3 05:47 | 清场 30s 后复跑（E 三次） | ✓ 活 | **✗ 同款 OOM panic 复现**（排除前一进程资源残留混杂） | DX12 / NVIDIA |

结论解读：

1. **CELL2（start /B 活）复现成功**——矩阵豁免面之一仍然成立。
2. **A 形态 2/2 存活 + 零新增 nvcuda64 事件**：最后一条 nvcuda64 AV 是 05:26:23（P2 第二条），
   之后 Start-Process×Vulkan 形态不再崩——**驱动态在 05:26–05:40 之间发生了转变**（T10b 时段
   A 形态 5/5 必崩为事件日志背书，非编造；转变后历史归因对「当时」仍成立）。
3. **E 形态（dx12）当下 3/3 panic**：game 进程的 DX12 枚举已从 AMD 变为 NVIDIA（R2b/R3
   AdapterInfo 实证），且 NVIDIA DX12 上设备创建 OOM（编辑器进程同后端正常，见 §四）。
   **指南场景 2 的 dx12 绕行在当前驱动态下会把 game 打成 panic**——指南「落 AMD 集显」前提失效。
4. 三轮收尾 phys-game 进程清零（final sweep=0×3）；无 WGPU_BACKEND 环境残留
   （HKCU/HKLM/会话三级核对）。

## 三、核验面 3：T2 旧定性推翻审查——**实验设计支撑结论，成立**

对照 `t10-t2-qa.md` 原文（§一/§四②）与 T10b §四：

- 推翻逻辑链核实：A/A'（direct run 无 PIE 无 windowless 也崩→该组合非必要）＋R4/R6
  （同 exe＋windowless env 纯 Command spawn 活→组合非充分）＋P2（窗口模式 PIE 也崩→
  windowless 非必要）＋C/D（同一 exe 仅换 start /B 即活→同组件下分岔在宿主形态）——
  四面夹逼下「组件无关、进程创建形态才是差异变量」成立，「维度缺失下的局部最优」表述准确。
- ⚪-3 措辞瑕疵：被推翻的是 **T2 程序报告**的二分定性；T2 **QA** 记档（§四②）当时已自行扩界为
  「非 windowless 特有、与宿主环境相关」——与 T10b 结论同向。报告笼统说「T2 的定性被推翻」
  对 T2 QA 的记档略不公平，建议表述区分两口。

## 四、核验面 4：「不做代码修复」裁定审查——**裁定成立（并获事后强佐证）**

- 「崩溃帧在驱动内」证据充分：61/61 模块+偏移一致（本 QA 独立复核）；WER 出错模块为 OS 级
  归因；同二进制多形态存活。NVIDIA 无公开 PDB 不影响归因，报告如实记档 ✓。
- 「强制 PIE dx12 不采纳」权衡成立：改默认后端影响所有机器（Vulkan 在别处更优）＋掩盖驱动
  问题＋环境级变量可绕——三条理由均实。**事后佐证**：本 QA 实测驱动态转变后 dx12 形态在
  game 进程上 OOM panic——若当时采纳该「修复」，现在等于把 game 永久锁死在必 panic 路径上。
  「记为开放选项、环境级变量绕行」的裁定方向正确。
- **但两处证据误读（🟡-2）**：报告 §四-1「编辑器自身（DX12+AMD）」与 §六-3「NVIDIA+DX12
  未实测、本机 DX12 枚举始终落 AMD」被 T10b **自家归档**反驳——p1/p3 编辑器日志的
  AdapterInfo 均为 `NVIDIA GeForce RTX 5070, backend: Dx12`（编辑器进程 NVIDIA+DX12 两份
  稳定运行实证）。`render_backend.rs` 实读：编辑器 Windows 默认 DX12 ✓ 但不指定适配器，
  落点由运行时枚举决定（编辑器进程落 NVIDIA、调查时段 game 进程落 AMD——进程间不同）。
  「编辑器默认 DX12」引述正确，「+AMD」为错误嫁接。同理 E 格 game「落 AMD」在当时为真、
  现已落 NVIDIA（§二 R2b/R3）。

## 五、核验面 5：绕行指南可用性——**结构可操作，三处需修**

1. 🟡-1 **30 秒确认法命令实测报错**：`Get-WinEvent -FilterHashtable @{LogName='Application';
   Id=1000; -MaxEvents 3}`——`-MaxEvents` 误作 hashtable 键，实测「哈希文本不完整」解析错误，
   指南第一入口命令不可直接执行。修正：移为 `Get-WinEvent -MaxEvents 3 -FilterHashtable @{...}`。
2. 🟡-4（并入 §二结论）**场景 2 当下有害**：dx12 绕行的前提「落 AMD 集显」已失效，当前
   3/3 OOM panic。指南需加时效性核对步骤（套用绕行前先确认 30 秒确认法在**当下**仍命中
   新增崩溃；以及 §三「DX12 落点」表述改为动态核对）。
3. 场景 1（start /B）与 C/D 一致且本 QA 复证 ✓；场景 3 引 T2 记档、报告未将其虚列为矩阵格 ✓；
   「判活双通道（BRP 应答+事件日志）、单看 exit code 会漏判」纪律获本 QA 再证实
   （R2b panic 退出在 Redirect 形态下 ExitCode 显示 0x0，与 stderr 矛盾）——⚪-4 记档。

## 六、问题统计与偏差分级

- 🔴 严重：0
- 🟡 中等：4——
  1. 指南 30 秒确认法命令跑不通（-MaxEvents 误入 FilterHashtable，实测报错）；
  2. 报告 §四-1/§六-3 与指南 §三的「编辑器=DX12+AMD」「NVIDIA+DX12 未实测」「DX12 枚举
     始终落 AMD」被自家归档（编辑器 AdapterInfo=NVIDIA DX12）及本 QA 实测反驳——证据误读，
     误导下游对 NVIDIA+DX12 安全性的判断；
  3. P3 归档日志尾部存在 `jackdaw::pie::drain_game_events` swap_remove 越界 panic
     （PIE connected 2 秒后，p3-pie-dx12-ok-editor.log:41-44）——报告未记档，「PIE 全链绕行
     验证/恢复全链可用性」（§三 P3、§七-2）成色不足，且疑为 jackdaw 潜伏代码缺陷，建议立账；
  4. 驱动态已于 10-28 05:26–05:40 间再度转变（A 形态 2/2 存活、E 形态 3/3 OOM panic、game
     DX12 枚举落 NVIDIA、零新增 nvcuda64 事件）——报告矩阵与指南场景 2 当下失效，需补时效性
     记档并重估下游纪律（§七-1 Start-Process 禁用、§七-2 P3 恢复、§七-3 复跑触发条件已满足）。
- ⚪ 轻微：4——①计数 ±1（10-27 时段 32→实测 33；主动复现 9→实测 8，归档亦 8）；
  ②调查窗口声明 05:16–05:27 与 P3 实际执行 05:30:58–05:31:08 不符；③「T2 定性被推翻」未
  区分 T2 程序口径与 T2 QA 已扩界口径；④Redirect 形态下 ExitCode 与真实退出原因矛盾
  （0x0 vs panic 101）——判活双通道纪律的又一实证，建议指南 §三补一句。
- 真机纪律：三轮 6 次启动全部收尾杀进程，phys-game orphans=0；WGPU_BACKEND 会话级设置
  已清除、注册表无残留；暖工程零持久改动；临时日志留档 `H:\workspace_AI\t10b-qa\`（仓库外）。

## 七、结论

核验面 1/3/4 主体成立：**根因归因证据链（61 样本 nvcuda64@0x3ab984 驱动内崩溃帧 ×
形态分岔矩阵）经独立复核为真**，T2 旧定性推翻与「不做代码修复」裁定均站得住（后者并获
驱动态再度转变的事后佐证）。但交付物存在 4 项 🟡：指南入口命令跑不通、DX12 适配器表述
与自家证据矛盾、P3 panic 不利证据遗漏、矩阵/指南在调查结束后约 13 分钟即因驱动态再度
转变而失效（dx12 绕行当下必 panic）——均为文档修订级，不动摇根因结论。

**VERDICT: PASS（有条件）**——4 项 🟡 修订完成后 T10b 方可闭环：

1. 修指南 30 秒确认法命令（-MaxEvents 移出 FilterHashtable）；
2. 修报告 §四-1/§六-3 与指南 §三的 DX12 适配器表述（编辑器实落 NVIDIA DX12 有两份归档
   实证；game 落点系运行时枚举、随时可变，改为「启动后看 AdapterInfo」的动态口径）；
3. 补记 P3 尾部 drain_game_events swap_remove panic，撤回或降格「PIE 全链恢复」表述，
   并为 `jackdaw::pie::drain_game_events` 越界立账（潜在 jackdaw 缺陷，与 0xc0000005 无关）；
4. 补记「10-28 ~05:26–05:40 驱动态再度转变」观察（A 形态复活、E 形态 OOM panic 三连、
   game DX12 枚举落 NVIDIA），下游纪律按 §七-3 的自设机制进入「复跑矩阵」状态——
   建议主控安排 P1/P3 编辑器形态复跑（本 QA 轻量范围未覆盖），并暂缓一切
   WGPU_BACKEND=dx12 强制绕行，直至矩阵重测通过。

随行建议：①驱动侧仍是元凶（591.86 两次劣化形态 + NVDisplay.Container 自崩前科），
根治路径维持指南场景 2-2（更新/回滚驱动）不变；②事件日志解析脚本与三轮真机脚本已归档
`loop/qa/t10b-qa-*.ps1`，驱动态复测可直接复用；③loop/ 整体在 `.git/info/exclude`
忽略规则内，本 QA 的报告与脚本均不进版本控制——工作区仍仅既存噪音
（.gitignore M、buglist.md 未跟踪），与开局自检一致。
