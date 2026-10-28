# feature-05 任务 2 报告：工具取消语义审计与修复（R2）

> 多 Agent 开发循环 · 程序（Rust/Bevy 工程师）· 2026-10-23
> 分支 `loop/interaction-ux`（基于 main f9d85d8b）· 仅改编辑器侧
> 需求来源：`loop/plans/feature-05-interaction-ux.md` §R2 / D4–D8 + 任务 2 节

## 1. 审计矩阵（9 类交互模式，最终版）

审计方法：rg + 全文读码逐类核实（真机核实项按方案由 QA 阶段逐行补做，本报告以
headless sweep + 真机抽查覆盖主要行，见 §4/§5）。判定依据：modal 是否轮询
`ModalInputs::cancel()` / 自读 raw Escape / 有 RMB 绑定 / 是否注册了 `cancel` system。

| # | 工具/模式 | 修复前 | 修复后 | 验证方式 |
|---|---|---|---|---|
| 1 | Select/Translate/Rotate/Scale（QWER） | ✅ 完好：非粘性工具，Q 即回 Select，无需 Esc | 不变 | 真机 toolState case（rotate→Esc no-op→select，BRP 断言）；代码核对 |
| 2 | Vertex/Edge/Face 编辑模式 | ✅ 完好：`brush.exit_edit_mode` 绑 Esc，与 clip/knife 分层让位 | 不变 | 代码核对（本任务未改）；headless operators 全量回归 |
| 3 | Clip 模式 | ✅ 完好：`brush.clip.clear` 绑 Esc | 不变 | 同上 |
| 4 | Knife 模式 | ✅ 完好：自读 raw Esc 分级取消（清路径→退模式）+ RMB 清路径；非 operator modal，新链不涉足 | 不变 | 代码核对（knife_mode.rs:459-471） |
| 5 | **标尺 Measure** | ❌ **Esc 死路**（不 poll ModalInputs；confirm 每次 Running）+ ❌ 无 RMB | ✅ Esc 取消（新链）+ ✅ RMB 退出（body）+ ToolStatus 提示 | headless ×2 + 真机 ruler-Esc ×3 / ruler-RMB ×3 |
| 6 | Draw Brush | Add ❌ Esc 死路（注释自认走 modal.cancel 链但链不通）；Cut ✅ RMB | Add ✅ Esc；Cut 不变 | headless sweep + 真机 drawAdd-Esc / drawCut-RMB |
| 7 | Terrain Sculpt/Paint | 工具态 ✅（`terrain.tool.exit_to_select` 绑 Esc，stroke 中让位）；**stroke 中 Esc 死路**（body 不 poll cancel，注释声称恢复快照但无实现通路） | stroke 中 ✅ Esc（`cancel_terrain_paint/sculpt` 恢复快照）；工具态不变 | 代码审计坐实；机制与 measure 同链（见 §5 标注） |
| 8 | Gizmo 拖拽（object + edit 两种） | ❌ **Esc 死路**：描述声称 "cancels on Escape"，body 不 poll 不读 raw；`cancel_gizmo_drag(_edit)` system 存在但无人触发 | ✅ Esc 取消（新链 → cancel system 恢复 start transform） | 代码审计坐实；机制同链 |
| 9 | 顶点/边/面拖拽 + modal transform（G 键） | 拖拽：RMB ✅（active 时 `just_pressed(Right)` → None），**Esc 死路**；modal_transform ＝ **死代码**（其 plugin 注释自述系统已禁用，`ModalTransformState.active` 永远 None）；numeric_transform ✅ 自读 raw Esc | 拖拽 ✅ Esc（新链）；modal_transform 维持死代码不修；numeric 不变 | 代码审计坐实；机制同链 |

**统计**：9 行中修通 Esc 退出 5 行（#5、#6 Add、#7 stroke、#8、#9 拖拽）；
补 RMB 退出 1 个工具（标尺，双语义按主控裁定接受：RMB 同时触发 NavFly）；
本就完好 4 行（#1–#4）+ #6 Cut / #9 RMB / #9 numeric / #7 工具态等子项；
死代码豁免 1 项（modal_transform）。

## 2. 核心修复实现（D6：一处修全部）

**根因**（方案 D4 代码级确证，本次复核一致）：Escape 有两条链——Core 扩展上下文的
`OperatorAction("modal.cancel")` 绑 Esc（core_extension.rs:174）与 modal 上下文
（priority 10）的 `ModalCancel`（绑 Esc，consume_input=true）。任何 operator modal
运行时 `update_modal_context_activity` 置 modal 上下文 ACTIVE，Esc 被 ModalCancel
消费、Core 链被屏蔽；而 ModalCancel 的 Fire 此前没有任何全局派发者 → 不自行轮询
cancel 的 modal 全部 Esc 死路。

**修复**（`src/input_contexts.rs` spawn_contexts）：给 `ModalCancel` action 实体附加
`OperatorAction(CancelModalOp::ID)`（"modal.cancel"）。其 Fire 经
`dispatch_operator_actions`（lib.rs:710 On<Fire> observer）自动 dispatch
`modal.cancel` → `cancel_active_modal` → 活动 modal 的 `cancel` system +
finalize(false)。零新系统、零新调度。配套：`core_extension.rs` 的 `cancel_modal`
改 `pub(crate)`（`CancelModalOp::ID` 单一事实源，避免魔法字符串）。

**两链互补**：modal 运行时新链生效、Core 链被屏蔽；无 modal 时 ModalCancel 不 fire、
Core 链照旧（picker/对话框 dismiss）——真机 toolState case 验证无 modal Esc 为
no-op。**幂等**：自 poll cancel 的 modal（brush topology 等）与新链同帧双触发时，
`cancel_operator` 对已 finalize 的 modal no-op（operator.rs:908 is_operator 检查）；
knife 等非 operator modal 的分级取消不受影响（modal 上下文不因其 ACTIVE）。

**require_reset 语义**（方案风险 3）：modal 启动帧已按住的 Esc 需先释放再按才生效
（evaluate.rs:437-439 既有语义）——集成测试 `escape_held_through_modal_start_needs_a_repress` 钉死该序列，防误归因。

## 3. 其余修复项

- **标尺 RMB/Esc 退出（D7）**：`measure_distance` body 补
  `modal_inputs.cancel() || mouse.just_pressed(MouseButton::Right)` → `None`（Cancelled
  → cancel system + finalize），与 brush topology 范式一致；启动帧写
  `ToolStatus("Measure: LMB sets points · Esc or RMB cancels")`，modal 结束由
  `clear_tool_status_after_modal` 自动清除（headless 断言写入与清除）。
- **status_bar 重绘门**：`update_status_right` 的 change-detection 门列表缺
  `tool_status`，提示可能不重绘——补 `!tool_status.is_changed()`（实现期发现，
  方案未列）。
- **T1 移交：工具态 BRP 可查**：方案/manual 说「补 Reflect 注册」，实际审计发现
  `EditMode`/`BrushEditMode` 已 derive Reflect 且已 register_type，真正缺的是
  **`#[reflect(Resource)]`**（pinned bevy 0.20-dev 的 `ReflectResource` type data
  必须显式声明，BRP `world.get_resources` 依赖它，缺则报 "isn't reflectable"）。
  补：`ActiveTool` derive Reflect + `#[reflect(Resource)]` + `register_type`
  （gizmos.rs plugin）；`EditMode` 补 `#[reflect(Resource)]`（注册已有）。
  真机实测：`world.get_resources` 返回 `{"value":"Select"}` / `{"value":"Object"}`。
- **CONTRIBUTING.md（D6 文档同步）**：modal 节补「Esc 取消已自动接线；可自行轮询
  ModalInputs::cancel() 做分级取消；两路幂等」。

## 4. 测试与各门退出码

新增集成测试 `tests/operators/modal_escape.rs`（4 个，走真实输入栈：synthetic
`input.key`/`input.pointer` → ActionSystems → Fire → dispatch）：

1. `escape_cancels_the_measure_modal_and_resets_it`：modal 运行 → Esc → 无
   ActiveModalOperator + MeasureToolState 复位 + ToolStatus 清除 + 无 modal 再 Esc
   no-op；
2. `right_click_cancels_the_measure_modal`：RMB → body 取消 + 状态复位；
3. `escape_cancels_every_running_modal_operator`：**全 modal 扫描**——每个
   `modal = true` operator，dispatch → Running → 一次 Esc → 断言 teardown
   （硬语义全局保证；gate 拒绝的返回 Cancelled 跳过）；
4. `escape_held_through_modal_start_needs_a_repress`：require_reset 吞首按序列。

| 门 | 退出码 | 备注 |
|---|---|---|
| `cargo fmt --all -- --check` | 0 | |
| `cargo clippy --workspace -- -D warnings` | 0 | |
| `cargo xtask fast` | 0 | 2802 passed / 2 skipped |
| `cargo xtask integration` | 0 | 4937 passed / 3 skipped（较 T1 +4：本任务新增） |

（两门均在最终代码态复跑——首跑后追加了 `#[reflect(Resource)]` 与 status_bar 门，
已重跑覆盖。）

## 5. 真机验证记录（loop/qa/r2-cancel.ps1，归档 `loop/reports/r2-cancel/t2-run/`）

debug 构建 + `JACKDAW_OPEN_PROJECT=my-game`，BRP 断言 + OS 级 SendInput：

| case | iter | modal 激活后 | 输入 | modal 结果 | ActiveTool | 判定 |
|---|---|---|---|---|---|---|
| ruler-Esc | 1–3 | `tools.measure_distance` | SendInput Esc | null（取消） | Select | ✅×3 |
| ruler-RMB | 1–3 | `tools.measure_distance` | SendInput RMB down/up @视口中心 | null（取消） | Select | ✅×3 |
| drawAdd-Esc | 1 | `viewport.draw_brush_modal` | SendInput Esc | null | — | ✅（原死路修通） |
| drawCut-RMB | 1 | `viewport.draw_brush_modal` | SendInput RMB | null | — | ✅（既有回归保持） |
| toolState | 1 | —（tool.rotate 调用） | Esc（无 modal） | null（no-op） | Rotate→(Esc 后仍 Rotate)→Select | ✅ |

`world.get_resources {resource:"jackdaw::active_tool::ActiveTool"}` 真机可读
（"Select"/"Rotate"），EditMode 同（"Object"）——T1 移交项落地。
截图留档：`ruler-active-1.png`、`final.png`（注意：状态栏被 my-game 工程
build-failed 文案占据——该 QA 工程 rustc 1.96 不被支持的既有环境问题；
状态栏优先级 phase > ToolStatus 属既有规则，ToolStatus 写入/清除已由 headless
断言，重绘门已补 tool_status.is_changed）。

**机制同链标注**：terrain stroke（#7）、gizmo 拖拽（#8）、brush 拖拽（#9）未单独
真机交互驱动（需选中实体 + 拖拽 hover fixture）；其取消走与真机已验的
measure/drawBrush **完全相同的 Fire→modal.cancel→cancel_operator 派发链**，且
headless 全 modal Esc 扫描 + operators 全量回归通过。逐行真机核对属 T2 QA 清单
（loop/plans §7 T2 真机项 3），留给 QA 阶段。

## 6. 遗留

1. my-game QA 工程 build failed（rustc 版本）遮挡状态栏——建议 QA 用健康工程截图
   核对 Measure 提示文案的实际显示。
2. headless Esc 扫描中仅 3D-gate 允许的 modal（measure、draw_brush 等）真实运行，
   其余（terrain/gizmo/drag 类）dispatch 即 Cancelled 被跳过——同链机制已由运行
   行覆盖，如需逐个 headless 驱动要造 fixture（建议随 QA 反馈按需补）。
3. `modal_transform.rs`（G 键）确认为死代码（系统禁用、状态恒 None）；如未来启用
   需接 Esc（新链只覆盖 operator modal，`ModalTransformState` 不产生
   ActiveModalOperator）。已在矩阵标注，未修。
