# T06-T2 QA 验收报告：「Stop 还原加固与优雅停止」

> QA 角色产出，2026-10-24（验收执行）/ 程序报告 2026-10-26。分支 `loop/t06-stop-restore`，
> 提交 `af93e730`（父 `fd37a79e` = main，即 T1 合入点），9 文件 +893/−41。
> 规格：`loop/plans/t06-play-isolation.md` §二 T2（决策 4/5）。上轮 QA 两个 🟡（N-QA1/N-QA4）
> 本轮吸收，验收其落地。验收方法：归档全文复核 + 抽亲跑 + git 考古 + 独立真机复跑（只验不修）。

## 一、门禁复核（2026-10-25 升级标准）

### 1.1 归档全文复核（loop/t06t2_*.log）

| 门 | 归档 | 复核结论 |
|---|---|---|
| fmt | `t06t2_fmt.log`（0 字节） | `--check` 通过零输出；QA 对 T2 代码亲跑 fmt exit 0 交叉验证 PASS |
| clippy | `t06t2_clippy.log` | 仅 5 条既有工具链噪音（rust-lld ×1、build script duplicate ×4），无 error 无新增 |
| lib | `t06t2_lib.log` | 逐 crate 加总 **2900 passed / 0 failed**（=2893+7：graceful_stop 5、val_resource_guard 2）；ERROR 行均系测试故意造的失败场景 |
| guards 全量 | `t06t2_guards_full.log` | **196 passed / 0 failed**（52.52s；=192+4 stop_restore；含 journal 计时门 ok） |
| runtime | `t06t2_runtime_override.log` | **5 passed / 0 failed** |

门禁表引用日志均为终态绿版本；过程日志（guards1-4、w17_run1-4、y34_run1-5 等）系开发证据未被门禁表引用。**四门：PASS。**

### 1.2 QA 亲跑

| 命令 | 结果 |
|---|---|
| `cargo test -p jackdaw --test guards stop_restore` | **4 passed / 0 failed**（192 filtered out，3.50s） |
| `cargo test -p jackdaw_runtime --test pie_scene_override` | **5 passed / 0 failed**（含新跨帧用例） |
| `cargo fmt --all -- --check` | exit 0 |
| `cargo test -p jackdaw --test guards`（全量） | **196 passed / 0 failed**（53.32s）——**journal 计时门在 QA 独立全量并行跑下稳定通过**，HEAVY_EDITOR_LOCK 修复获独立验证 |

## 二、红→绿真实性（三组全部核对）

| 项 | 红证核对 | 绿 |
|---|---|---|
| N-QA1 换把跨帧 | `t06t2_nqa1_red.log` 4/1，panic 消息 **`a root added while running keeps its own scene: ["Overridee", "Overridee", "other", "other"]`**——旧实现把运行期新增的第二个 root 也换成了 override（二次换把行为实锤） | 亲跑 5/0 |
| Y34 优雅停止 | `t06t2_y34_red.log` 4/1，panic `a live child holds the graceful window instead of dying now`——旧立即-kill 复演下 handle_stop 后 children 已空，优雅窗口无从谈起（行为级红证） | `t06t2_y34_green.log` 5/0 |
| W17 资源守卫 | `t06t2_w17_red.log` 0/2，两用例均 panic 于 `commands.rs:87`——守卫摘除后落入 selection 文档管线，`FieldEditSessions` 资源不存在（路径分流错误实锤；程序实测定性「旧路径 tick 连资源自身都不写」与此自洽） | `t06t2_w17_run4.log` 2/0 + 亲跑（lib 2900 含） |
| selection | 不实锤（无红可复演），guards 4 例作回归锚（方案预案路径） | 亲跑 4/0 |

**红→绿：真实。**

## 三、真机铁证链独立复跑（QA 亲自执行，非程序 run10 回放）

构建：QA 先 `cargo build -p jackdaw`（24.56s，仅既有噪音）确保 exe 为提交版。
脚本：`loop/qa/t06-stop-restore.ps1`（端口 15717、隔离 `JACKDAW_CONFIG_DIR`、1920x1080）。
**结果 `T06T2_STOP_RESTORE_LIVE_PASS`，exit 0：**

| 用例 | 关键断言（QA 复跑实测值） | 结果 |
|---|---|---|
| case 1 铁证链 | Spinner 投影文档两次采样在动（rotation 值变化）；stop **0.4s** 优雅落地；**盘上 SHA 逐字节一致 + emit SHA 逐字节一致**；history=0 不变、dirty=false 不变、实体名集精确复原、temp 零残留；ChildOf WARN 每会话 1 条（与程序观察一致） | 全过 |
| case 4 W26 kill 链 + N-QA4 | my-game.exe 找到 → 硬杀编辑器 → 3s 后游戏死（**job object 生效**）；**journal 零文件含 t06-spin 条目**（save 已把条目 spend 出局——N-QA4 真机半场成立）；预置孤儿 `current-untitled-9-99999.bsn` → 重启被清扫 | 全过 |
| case 5 大场景 | 500 实体 play→stop **0.7s** 落 stopped（≤deadline+1s）；Prop0 复原抽查 | 全过 |

- **QA 补强证据**：case 5 本轮 0.7s vs 程序 run10 的 2.2s——两轮恰好分别覆盖 Y34 的**期限内自退**与**超时 kill** 两条分支，deadline 机制两路径均获真机实证。
- 偏差② stop avail 门竞态本轮未复现（stop 一次成功，时序窗口随机）。
- 复跑后清理：QA 已删 t06-spin/t06-big 及 .bak（assets 复原为 scene.bsn + 既有 scene.bsn.bak）、`.jackdaw-pie/` 空、无 jackdaw/my-game 残留进程。

**铁证链：独立复现。**

## 四、代码 review（七重点）

1. **Y34 deadline 机制** ✅：`GRACEFUL_STOP_DEADLINE=2s` 常量化（决策 5-A）；`stop_instance` 已 arm 不重发 Stop；`handle_stop` drain→Live 全 arm（已有 deadline 取 `min`，早 arm 保留）；`advance_child` 到期 `kill()+wait()` 返回 None——**恰一次由 stage 按值传入随调用 drop 的所有权语义保证**（类型上不存在二次）；Connecting 维持立即 kill（「未连上无优雅可言」）；`handle_reload` → `force_stop_all`（原立即 kill 行为保留 + 注释注明 reload 语义）。测试 5 例覆盖窗内保留/自退 reap/超时 kill/留窗+早 deadline/force 立即清。
2. **W26 降级** ✅（结构保证）：`PIE_JOB: LazyLock<Option<Job>>`——`CreateJobObjectW` 空句柄与 `SetInformationJobObject` 失败均 `warn!`（含 GetLastError）+ `None`；`assign_to_process` 失败 `warn!` 继续；调用点 `if let Some(job)`。diff 核实**三处 `assert!` 全消**。GetLastError 的 SAFETY 注释正确（同线程失败调用后立即读）。⚪ N-QA-T2-3：方案处方「单测+代码审查」，实际降级分支无单测（LazyLock 全局态不可注入，程序已如实记档）——审查覆盖可接受。
3. **W17 守卫形状** ✅：`commit_val_to_field` 开头 `is_resource_entity` 分流（tick→`resource_field_preview`、commit→`resource_field_commit` 后 return），与 numeric 路径先例同构；测试 2 例用真实 resource entity + `read_field_path` 读回断言（tick 写资源自身 0 undo / commit 恰 1 undo 且 undo 回原值）。`resource_commands.rs` 仅 `live_resource_entity` 提为 `pub(crate)` 供测试，无行为改动。
4. **selection 不实锤结论** ✅：`apply_view_state` 按 SceneNodeId 重建、悬空句柄过滤的机制论述与代码一致；guards 4 例含**最恶劣构造**（authored 被 reparent 到 ephemeral 下 + Live 选中游戏私有实体），断言无悬空句柄、Selected 标记集与 selection 资源一致、authored 选择按 node id 复原。质量高。⚪ N-QA-T2-2：用例 1 的投影表断言（`by_bits.is_empty()`）无脏前提（fixture 未插入投影条目），断言仍有效但证明力弱于设计意图。
5. **旁路审计闭集** ✅（抽查成立）：`pie_projection.rs` 的 `resource_mut` 面全部为 `PieProjection`/`LiveEditLog`/`PieInstances` 自有资源，`SceneBsnAst` 仅只读查询（`entity_for_stable_id`），全文件无 authored 写——「投影只写 preview ECS」的核心证据独立核实；六显式门清单与 T1 旁路审计衔接一致（`write_atomic` 纯文件层、journal 非场景文件、temp 非 authored 文档）。
6. **HEAVY_EDITOR_LOCK 治本审查** ✅：二进制级锁，`play_current_scene`（12 例）+ `stop_restore`（4 例）+ **journal 计时测试本人**三方共持；注释明确「该测试在 T04 时期是独立测试进程（天然独占），合并 binary 后并行邻居破坏了预算设定的环境，挂锁恢复独占语义」——这是**恢复测量语义**而非掩盖（计时门未被改动/放宽/跳过）；其余 ~179 条非重型测试照旧并行（QA 亲跑全量 53.32s 与归档 52.52s 同量级，并行性未被误杀）；修复后归档全量 + QA 亲跑全量双绿。
7. **N-QA1 `Local<bool>` 换把一次/进程** ✅：实现正是 QA 上轮建议的最小修复（已换早退、换后置位、added 空不置位），注释同步改为「once per process」；跨帧用例先证首 root 换把（Overridee 出现）再后续帧 spawn second root，断言保持自载场景（Second）且不回落首个 root 原命名场景（Anchor 不现）——红证 panic 消息 `["Overridee","Overridee","other","other"]` 实锤旧行为二次换把。**N-QA1 闭环。**

**review 结论：无 🔴；⚪ ×3（见上）。**

## 五、偏差①裁定（本验收核心争议点）

**事实核定（QA 独立核实，三项全属实）**：
- 缺口 1（outliner Live 行不在 ui_tree）：`t06t2_probe_outliner.log` 实证——`ui_tree text=Spin` 命中 6 条 + 全树含 Spin 文本 32 条，全部是状态栏（"Playing 't06-spin'"）、tab 名与 Inspector 区零尺寸文本，**无任何 outliner 投影实体行以可点击控件（button/menu_item）形态出现**；
- 缺口 2（viewport pick 不中投影实体）：`t06t2_probe_select2.log` 实证——5 个坐标合成点击后 selection 状态均无变化；
- 缺口 3（无 selection.set）：QA 源码核——BRP 方法表共 20 个方法（status/operators/call_operator/batch/cancel/history/recovery/audit/scene_tree/entity/apply_bsn/scene_bsn/ui_*/camera_state/assets/screenshot/wait），**无 selection 类方法**；全仓 grep `selection.set` 零命中（operator 面亦无）。

**方案归属核定**：该 UI 链在方案中是**双归属**——§二 T2 验收标准第 4 条（「Live 模式 Inspector 改组件 → Stop → stop prompt 出现（ui_tree 断言）→ Discard → 文档不变；再 Play → 改 → Stop → Apply All → 恰一条 undo；全程无其它写盘」）**与** §二 T3 矩阵 #7（「Stop prompt Apply/Discard | 两分支文档期望态」终验）。程序报告 §七.1 只引 T3 归属；严格说这是**把 T2 验收标准的一条挪后到 T3 收口**，报告未明示 T2 清单欠账——记 ⚪ 表述缺口。

**充分性裁定：对 T2 放行充分，PASS 附条件。理由**：
1. 工具缺口属实且为 QA 面缺口非产品缺口；按 MCP 优先原则（README 2026-10-25 最高优先级裁定），补工具（T3 `jackdaw/pie` companion + selection 面）是正确路径，土法硬耗（坐标赌/前台化）反而是被明文禁止的做法；
2. 语义覆盖不缺：headless `live_edits.rs` 既有 3 例钉死 Apply（恰一条 undo）/Discard（不动 AST）/post-stop apply（走 node id）；真机 case 1 的 Spinner 运行态流动 vs 双 SHA 逐字节一致承担「运行态修改不写回」的正向铁证；
3. **T2 改动面不触碰 stop prompt 的 Apply/Discard 语义**（Y34/W26/W17/selection 均不在该链上），唯一交叉点是 stop 时序推迟到 reap 后（偏差⑤），已由 case 1/5 真机覆盖 + headless post_stop_apply 覆盖；
4. T3 矩阵 #7 本就是终验格，兜底存在。

**落账条件（必须执行）**：T3 计划必须含「补 selection 能力（`selection.set` 或 live-edit 注入面）并完成矩阵 #7（Stop prompt Apply/Discard 两分支真机链）」，并在 `loop/progress.md` 台账把本欠账记为 T3 前置项。**若 T3 未收口该格，T06 整体不得判完。**

## 六、其余偏差裁定

| # | 偏差 | QA 裁定 |
|---|---|---|
| ② | W26 降级无法真机模拟 | **接受**（方案原文允许：「真机模拟受限环境不可行，如实记档」）；三 assert 全消的结构保证 + warn+继续路径审查 + 正常路径真机回归（QA 复跑 case 4 job object 生效）。⚪ 附记：方案处方「单测+代码审查」的单测半边未做（LazyLock 全局态不可注入），程序已如实披露 |
| ③ | bevy 原生 BRP 与 jackdaw 实体面不通 | **属实、接受**（QA T1 验收时 manual §7.5/7.6 已有同款记载：实体格式不同构+world 视图差异）；真机改走 `jackdaw/entity` BSN 文本是正确绕行；T3 统一断言通道时一并记档 |
| ④ | ChildOf 悬空 WARN | **接受无害定性**（QA 复跑每会话同样 1 条；headless 复现不出；实体集/selection/文档/dirty 断言全不受影响）；T3 矩阵 #6 终验时评估是否消音 |
| ⑤ | Stop prompt 随优雅窗推迟 | 决策 5-A 预期行为（children 清空触发 OnEnter(Stopped)）；QA 复跑 stop 0.4s/0.7s 实测窗口内落地，无 pending live edit 时无 prompt 符合语义。接受 |
| ⑥ | ChildOf WARN | 同④（程序分两条记，实质同一现象） |
| ⑦ | buglist 打钩 | **核对属实**：Y34/W17/W26 三条均 `[x]`，W17/W26 带修复说明+红绿数字（与 QA 核对的日志一致） |

## 七、QA 汇总

- 新发现 ⚪ ×3：N-QA-T2-1（journal 6.8ms 失败的直接日志未归档——guards1-4 实为 stop_restore 开发过程证据（编译错误→1/3→3/1→4/0），「全量并行超限」结论由修复后双绿+QA 亲跑全量独立支撑，与 T1 N-QA3 同款记档模式）；N-QA-T2-2（stop_restore 用例 1 投影表断言无脏前提）；N-QA-T2-3（W26 降级分支无单测）。无 🔴 无 🟡。
- 上轮欠账闭环：N-QA1（Local<bool>+跨帧用例+红证）、N-QA4（headless journal spend 用例+真机 kill-重启零条目）双侧落地并经 QA 亲验。
- 纪律：真机复跑后 fixture 与进程已全部清理（assets 复原 scene.bsn + 既有 .bak；`.jackdaw-pie` 空；无 jackdaw/my-game 进程）；`.gitignore`（.mimosa/）与 buglist.md 仍为本任务外本地残留，不阻断。

## 八、PASS 条件核对

| 条件 | 判定 |
|---|---|
| 红→绿真实（三组红证核对+绿侧亲跑） | ✅ |
| 铁证链独立复现（双 SHA+kill 重启 N-QA4+大场景；两轮覆盖 Y34 双分支） | ✅ |
| review 无新 🔴 | ✅（⚪×3） |
| 偏差①有明确裁定 + T3 收口承诺落账 | ✅（PASS 附条件，§五；progress 台账记 T3 前置） |
| 门禁复核干净（归档+亲跑，journal 计时门双绿） | ✅ |

VERDICT: PASS
