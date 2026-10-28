# feature-05 任务 2 QA 验收报告：工具取消语义修复（R2）

> 多 Agent 开发循环 · QA（验收）· 2026-10-23
> 对象：`loop/interaction-ux` @ `178d8988`（基于 main `f9d85d8b`）
> 程序报告：`loop/reports/feature-05-t2-report.md` · 方案：`loop/plans/feature-05-interaction-ux.md` §R2/D4–D8
> 验收方式：四门 + 全量代码审查 + 真机驱动复验（OS 级 SendInput + BRP 断言 + 日志时间线 + 截图）

## 结论

**PASS**。无 🔴 / 🟡 产品缺陷；2 个 ⚪ QA 基建问题（本轮已修复驱动脚本），
1 个 ⚪ 报告口径偏差，1 个 ⚪ 语义备注。门全绿，核心修复机制、幂等性、双语义
均按方案与裁定落实；真机复验在 HEAD 二进制上两遍全过。

## 1. 门（逐条单命令，最终代码态）

| 门 | 结果 | 备注 |
|---|---|---|
| `cargo fmt --all -- --check` | ✅ 0 | |
| `cargo clippy --workspace -- -D warnings` | ✅ 0 | |
| `cargo xtask fast` | ✅ 0 | 2802 passed / 2 skipped（与程序报告一致） |
| `cargo xtask integration` | ✅ 0 | 4937 passed / 3 skipped（较 T1 +4，为新增 modal_escape 测试） |

日志：`loop/reports/gate-xtask-fast-qa2.log` / `gate-xtask-integration-qa2.log`。

## 2. 代码审查

### 2.1 核心修复（D6：ModalCancel 挂 `OperatorAction("modal.cancel")`）

- 实现点 `src/input_contexts.rs` spawn_contexts：`commands.entity(cancel).insert(OperatorAction(CancelModalOp::ID))`，
  单一事实源（`CancelModalOp::ID`），`core_extension.rs` 的 `cancel_modal` 改 `pub(crate)` 支撑之。
- **两链互斥（不会同帧双派发）**：modal 上下文 priority 10 + `consume_input=true`
  （evaluate.rs:480-540 的 `consumed` 集合），modal 运行时 Core 链（priority 0）的同
  trigger 绑定被屏蔽，只有新链 fire；无 modal 时 modal 上下文 INACTIVE（input_contexts.rs:489-507
  `update_modal_context_activity`），ModalCancel 不 fire，Core 链照旧。真机 toolState 例
  （无 modal Esc → 零 `modal.cancel` 派发）佐证。
- **幂等（不会双重 cancel / 重复 undo）**：
  - dispatch 侧 `creates_history_entry:true` 但快照门为 `creates_history_entry && allows_undo`
    （operator.rs:661），`modal.cancel` `allows_undo=false` → 无快照、无 history 条目；
  - `finalize_modal(false)` 本身不写 history（operator.rs:949 `!commit` 早退）；
  - 自 poll cancel 的 modal 与新链同帧双触发时，两路都汇入 `cancel_operator(modal_id)`，
    后到者被 `active.is_operator(id)` 门（operator.rs:908）与 `take::<ActiveModalOperator>()`
    （operator.rs:941）双保险挡下——无双重 teardown、无重复 undo。
  - Esc 后残留场景（modal 刚结束的过渡帧）新链 dispatch `modal.cancel`：availability 门
    不过 → Cancelled → `cancel_operator("modal.cancel")` 中 op.cancel 为 None、is_operator
    为假 → Ok(()) 无副作用。
- keybind 录制期间不误触发：`dispatch_operator_actions` 的 `capture.recording` 守卫（lib.rs:720）。

### 2.2 标尺 RMB 双语义（裁定 1：接受，双事件并存）

- `measure_distance` body：`modal_inputs.cancel() || mouse.just_pressed(MouseButton::Right)`
  → `None`（走 cancel system + finalize），与 brush topology 范式一致（measure_tool.rs 新增段）。
- NavFly 为 Nav 上下文（priority 0）代码级 RMB `Condition::Down` 绑定（input_contexts.rs:236-244），
  modal 上下文不绑 RMB 不消费 → **RMB 同时退出标尺并启动 fly**（两件事都发生），与裁定一致；
  `update_active_viewport`（viewport.rs:941）未改。真机 ruler-RMB 例：modal 清除 + ActiveTool=Select。

### 2.3 `#[reflect(Resource)]` 补注册（ActiveTool/EditMode）

- Resource 反射只影响 BRP `world.get_resources` 可见性；undo 快照为 document（SceneJsnAst）
  实体遍历实现（snapshot.rs，无 `extract_resources`），**不进快照、不进存档格式、无 TypeTree
  序列化副作用**。真机实测可读：`Select` / `Rotate` / `Object`。
- `register_type::<ActiveTool>()`（gizmos.rs plugin）；`EditMode` 注册原已有（brush/mod.rs:516）。

### 2.4 status_bar 重绘门

- `update_status_right` 参数列含 `tool_status: Res<ToolStatus>`（status_bar.rs:337），
  早退门新增 `!tool_status.is_changed()`；写侧（operator body `ResMut`）必然触发 change
  detection → 门正确。headless 断言写入与清除（见 §6 concern ②）。

### 2.5 测试质量（tests/operators/modal_escape.rs，4 个）

- 走真实输入栈（synthetic `input.key`/`input.pointer` → action 层 → Fire → dispatch），
  非直接调 cancel system；
- `escape_cancels_every_running_modal_operator` 全 modal 扫描：所有注册的 `modal=true`
  operator 逐个 dispatch，能到 Running 的必须一次 Esc teardown；gate 拒绝（Cancelled）跳过——
  报告 §6.2 对「3D-gate 外的 modal 未真实运行」有诚实披露；
- `escape_held_through_modal_start_needs_a_repress` 钉死 require_reset 首按吞并语义（方案风险 3）；
- 断言含状态复位（MeasureToolState）、ToolStatus 文案与清除、二次 Esc no-op——覆盖面合格。

### 2.6 范围核对（无越界 / loop 不入库）

- diff 共 10 文件（267+/3-）：CONTRIBUTING.md（D6 指定文档同步）、src×7、tests×2——
  全部在 R2 范围；无 Add 菜单/模板/文档等任务 3 内容。
- `git status` 干净，loop/ 被 git ignore（`git check-ignore loop` 命中）。

## 3. 真机驱动复验（契约）

### 3.1 程序真机证据的一个缺口（QA 补齐）

程序跑 r2-cancel 真机为 21:39（工程侧 png/metrics 时间戳），而最终二进制 21:47:54
链接（本轮 xtask 又于 22:02 重链，同一 HEAD 源码）——**程序的真机记录不覆盖最终二进制**
（21:44 的 measure_tool.rs 改动晚于其运行）。QA 在 HEAD 二进制上完整复验补齐此缺口。⚪ 口径偏差见 §7。

### 3.2 QA 复验 run（`loop/qa/r2-cancel-qa.ps1`，档案 `loop/reports/r2-cancel/qa-final/`）

my-game 工程，OS 级 SendInput + BRP 断言；**键盘用例逐例断言前台句柄 = 编辑器**（防注入丢失）：

| case | iter | modal 激活后 | 输入 | modal 结果 | ActiveTool | 前台 | 判定 |
|---|---|---|---|---|---|---|---|
| ruler-Esc | 1–2 | `tools.measure_distance` | SendInput Esc | null | Select | ✓ | ✅×2 |
| ruler-RMB | 1–2 | `tools.measure_distance` | SendInput RMB down/up @视口中心 | null | Select | — | ✅×2 |
| drawAdd-Esc | 1 | `viewport.draw_brush_modal`(Add) | SendInput Esc | null | — | ✓ | ✅（死路修通） |
| drawCut-RMB | 1 | `viewport.draw_brush_modal`(Cut) | SendInput RMB | null | — | — | ✅（回归保持） |
| toolState | 1 | —（tool.rotate） | Esc（无 modal） | null（no-op） | Rotate→Rotate→Select | ✓ | ✅ |

编辑器日志时间线佐证（qa-final/editor-stderr.log）：每个 Esc 用例后紧跟
`OPERATOR: modal.cancel`（×3），RMB 用例为 body 取消（无派发行，符合机制），
无 modal Esc 零派发。截图：`ruler-active-1.png`（948KB，标尺激活态整窗；亦证实
my-game 状态栏被 build-failed 文案占据，即程序 concern ② 现场）。

第二遍：healthy-proj 最小工程（`loop/qa/healthy-proj/`）同脚本 5 例全 PASS
（`loop/reports/r2-cancel/qa-healthy/metrics.csv`）——跨工程复证。

### 3.3 环境问题与定位（QA 基建教训，详见 §7）

1. **dylib 启动 PATH**：直接启动 `target\debug\jackdaw.exe` 因导入
   `bevy_dylib-<hash>.dll` / `std-<hash>.dll`（位于 deps 与 rustlib）解析失败，
   0xC0000135 静默秒退（`cargo run` 会自动设 PATH）。QA 以 PATH 前缀解决。
2. **SetForegroundWindow 前台锁**：后台进程调用被静默拒绝（探针实测前台句柄≠编辑器），
   导致 OS 级键盘注入落在他窗口——r2-cancel.ps1 的 ruler-Esc 用例首两轮"假失败"
   （日志证实 Esc 期间零 `modal.cancel` 派发；同一 Esc 在 drawAdd 例偶然通过，系其前
   ruler-RMB 的点击恰把编辑器带到前台）。进程内合成 `input.key Escape` 同链正常（探针 E）。
   驱动改为 **minimize+restore（系统授权激活）→ AttachThreadInput 兜底 → 真实点击 →
   前台句柄断言**（r2-cancel-qa.ps1），此后键盘用例 7/7 稳定通过。
3. **PrintWindow 陈旧帧**：后台窗口三次状态截图字节全同——UI 态截图必须前台化或走
   BRP screenshot（后者需已打开工程）。

## 4. 审计矩阵核实（9 类逐行对 diff 与源码）

| # | 程序判定 | QA 核实 |
|---|---|---|
| 1 QWER | 完好 | diff 未涉及 tool_ops；真机 toolState 例回归 ✓ |
| 2 编辑模式 | 完好 | diff 未涉及 edit_mode_ops ✓ |
| 3 Clip | 完好 | diff 未涉及 clip_ops ✓ |
| 4 Knife | 完好（非 operator modal，新链不涉足） | knife_mode.rs 未改，raw Esc 分级取消在位 ✓ |
| 5 标尺 | 修复（Esc 新链 + RMB body + ToolStatus） | diff 实改 measure_tool.rs；真机 Esc/RMB ×2 ✓ |
| 6 DrawBrush Add/Cut | Add 修复（根因链）；Cut 不变 | 根因机制覆盖（viewport.draw_brush_modal modal=true，cancel system 在位 draw_brush/mod.rs:122-123）；Cut 的 `cancel_cut` RMB 绑定为既有（:309 未改）；真机 drawAdd-Esc / drawCut-RMB ✓ |
| 7 Terrain stroke | 修复（同链） | terrain.paint/sculpt `modal=true` + `cancel=cancel_terrain_paint/sculpt` 在位（paint.rs:608-610 / sculpt.rs:261-263），根因修复覆盖 ✓ |
| 8 Gizmo 拖拽 | 修复（同链） | gizmo.drag / gizmo.drag_edit `modal=true` + cancel system（gizmos.rs:445-447 / :721-723）✓ |
| 9 拖拽/modal_transform | 拖拽修复（同链）；modal_transform 死代码豁免 | brush.face/vertex/edge.drag `modal=true` + cancel（brush_drag_ops.rs:194-195/790-791/1159-1160）；modal_transform 生产无激活路径（仅 `#[cfg(test)]` 写 active，plugin 注释自述系统禁用，modal_transform.rs:80-84）✓ |

结论：修的 5 类确有对应改动或被根因机制覆盖（modal/cancel 属性逐一坐实）；
完好 4 类 diff 零涉及，无退化；modal_transform 定性依据成立。

## 5. concerns 处置

- **①（terrain stroke / gizmo / brush-drag 未单独真机驱动）——放行**。理由：
  (a) 三者与真机已验的 measure/drawBrush 走**完全相同**的 Fire→`modal.cancel`→
  `cancel_operator` 派发链（同为 operator modal + cancel system，§4 已核属性）；
  (b) headless 全 modal Esc 扫描 + operators 全量回归通过；(c) QA 两遍真机（两工程）
  复证链路稳定。逐工具真机交互（需选中实体 + hover fixture）属锦上添花，不构成放行障碍。
- **②（my-game build-failed 遮挡状态栏）**——按任务允许的「headless 断言引用」结案：
  `modal_escape.rs::escape_cancels_the_measure_modal_and_resets_it` 断言精确文案
  `"Measure: LMB sets points · Esc or RMB cancels"` 的写入与清除；重绘门代码核验（§2.4）；
  遮挡现场有照片（qa-final/ruler-active-1.png 右侧 footer 为 rustc 报错文案）。
  视觉显示取证尝试受阻于 QA 环境（PrintWindow 陈旧帧 + 前台争用 + BRP screenshot 需
  已打开工程而 healthy-proj 走 setup 流程无 ProjectRoot），残余风险低（显示路径即同一
  footer Text 通道，Select/build 文案在截图中均正常渲染）。

## 6. 发现

| 级别 | 责任方 | 问题 + 证据 |
|---|---|---|
| ⚪ | QA 基建 | `r2-cancel.ps1` 直接启动 exe 依赖 PATH 含 `target\debug\deps` 与 rustlib（0xC0000135 静默秒退；探针 diag2 日志 0 字节 + 退出码 0xC0000135）。建议脚本内自设 PATH 或手册注明 |
| ⚪ | QA 基建 | `Focus-Jackdaw`（SetForegroundWindow）后台调用静默失败 → OS 键盘注入丢失，ruler-Esc 用例假失败（r2-cancel\qa-run\metrics.csv 两轮 False + 日志无 modal.cancel 派发；focus 探针 F1 前台≠编辑器）。已以 minimize+restore+AttachThreadInput+点击+前台断言修复于 `r2-cancel-qa.ps1`，建议并回 `r2-cancel.ps1` |
| ⚪ | QA 基建 | PrintWindow 对后台窗口返回陈旧帧（qa-healthy 三张状态截图字节全同），UI 态截图需前台化 |
| ⚪ | 程序（报告口径） | 程序真机记录（21:39）早于最终二进制（21:47 链接），未覆盖 HEAD；报告未注明。本轮 QA 已在 HEAD 复验补齐 |
| ⚪ | 产品（备注，无需改） | modal 与 picker 同时打开时，一次 Esc 同时取消 modal 并关 picker（`cancel_modal` body 既有行为，Core 链同 body；非本次引入，语义可辩护为「Esc=dismiss 弹层」） |

## 7. 交接

- 保留资产：`loop/qa/r2-cancel-qa.ps1`（确定性聚焦版驱动）、`r2-esc-diag.ps1` /
  `r2-esc-focus.ps1`（机制诊断）、`loop/qa/healthy-proj/`（最小工程 fixture）、
  `loop/reports/r2-cancel/qa-final|qa-healthy/`（本轮档案）。
- T3 建议：真机项可复用 r2-cancel-qa.ps1 的聚焦策略与 PATH 前缀。
