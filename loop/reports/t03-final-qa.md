# T03 任务 2 验收 + T03「Undo/Redo 与脏状态加固」整体终验（QA）

QA 独立验收，commit `6df9ac89`（分支 `loop/t03-undo`，diff main..branch 恰为该 commit：14 文件 +760/−77）。
口径：`loop/plans/t03-undo-hardening.md` 任务 2 节 + §7 QA 清单；程序报告 `loop/reports/t03-t2-report.md`；T1 QA `t03-t1-qa.md`。

## VERDICT: FAIL（T03 整体）— 任务 2 编目内工作全部合格；一项 🔴 新发现（clip 关键帧 op 键位路径双记录 + undo 链重复关键帧）落在 T03 验收面内，需一轮小返工后重验

## 门禁（QA 全部亲跑，日志 `loop/reports/gate-*-t03final-qa.log`）

| 门 | 命令 | 结果 |
|---|---|---|
| fmt | `cargo fmt --all -- --check` | exit 0 |
| clippy | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | exit 0 |
| xtask fast | `cargo xtask fast` | 2866 passed, 2 skipped |
| xtask integration | `cargo xtask integration` | **5070 passed, 2 skipped, 0 failed**（与程序一致） |
| doctests 基线 | `cargo test --locked --workspace --doc --features dylib --no-fail-fast` | 失败集合恰为 {jackdaw_bind, jackdaw_feathers, jackdaw_node_graph}，与 T2 基线逐 crate 一致，**零新增** |

## 代码审查

### Y1（44 + brush 4）— 合格
- `entity_ops.rs` 22 处（add.* 21 + paste_components）、`transform_ops.rs` 15 处、`inspector/ops.rs` 2 处（N1）、`brush_display.rs` 4 处，全部显式 `allows_undo = false`；逐处过 diff 无遗漏无多余。
- **QA 独立扫描**（脚本解析全部 `#[operator]` 块 × 函数体 `push_executed`/自推 helper 交叉）：44+4 全部落网；
  `entity.delete/add.group/set_transform/reparent`、`lod.revert_override`、`terrain.paint/sculpt/detail.stamp` 均已声明 false；`entity.duplicate`/`place_gltf` 等模式 B 未误伤。
  **扫描另揪出 4 个 default-true 自推 op**（见 🔴/🟡 发现）。
- `entity.add.image` / `entity.add.prefab` 未改正当：op 体仅 `commands.queue(open_*_picker)`（异步启动器），无 push。
- 防回归钉死：`SELF_PUSHING`（41 项）+ `SNAPSHOT_BACKED`（10 项）清单测试在位；红日志中通过的唯一一条恰为 SNAPSHOT_BACKED（证未误伤）。
- 红证核实：`t03t2-red-run.log` 确为 record_counts **9 失败/1 通过**，失败项与修复一一对应。

### 3 条既有测试适配 — 均正当
- `batch_undo::each_path_outside_a_batch_pushes_what_it_always_has` +2→+1：旧断言把双记录钉成预期，正是 Y1 缺陷本体；改后菜单路径 +1、无 history 派发仍 +1（自推保留），语义正确。
- `undo_history::a_trimmed_history_still_undoes…`：Y1 后 add 的 SpawnEntity 条目不再持字节，改用 rock 实例（模式 B 快照持文档单元）驱动裁剪，意图（预算裁剪+逐条可撤）不变，且新断言 `per_rock == 1` 更严。
- `operator_undo` 两条：`entity.add.empty` 不再产生快照条目，改 `entity.duplicate`（模式 B 载体）+ 自建已注册实体，快照字节申报测试意图不变。

### Y2 — 合格
右键菜单改派发 `entity.duplicate`（Invoke + `creates_history_entry:true`，与 Ctrl+D 同路径）；测试经真实 `ContextMenuAction` trigger 走完整菜单链，undo 后文档字节还原。

### Y4（含偏差）— 合格，偏差处置正确
- 简报字面（`creates_history_entry:false`）确实会得零记录；按方案 §3.5 定案（保留一次 `true` 派发 + op 体内 `ReparentEntity::execute` 不 push）是对的。
- **单写路径收敛（方案风险表预授权）QA 独立评估**：旧语义确有害——旧 `unpack_child` 造**副本**（仅组件、滤 PEID、无孙代、无 live link）到 drop target，层级处 ReparentEntity 又把**原节点**（仍带 PEID）搬过去 → 前向文档两个节点、副本丢孙代、PEID 残留引 resolver 复配。新实现 `move_to_parent_at` 搬本体 + `remove_component_patch(PEID)`：恰一个节点、带孙代、无标记。`prefab_lifecycle.rs::unpack_child_adds_to_deleted_and_creates_standalone_node` 未改且通过（其断言"one child + no PEID"新旧实现均满足，直调 AST 层）；手势级单条性由 record_counts 新测试钉死（含前向恰 +1 个 `#Pebble`、undo 逐字节还原、redo）。
- `prefab.unpack_child` op 保持 `allows_undo=true`（模式 B），在 SNAPSHOT_BACKED 清单内。

### BRP `jackdaw/history` + MCP 薄工具 — 合格
- `history_handler` 挂 `with_method_main`；返回 8 字段与 manual §7.1 一致；dirty 与 `jackdaw/status` **同源**（均读 `scenes.tabs[active].dirty`，QA 读两处 handler 源码核实）；`entries` 默认 8/上限 64 有 clamp。
- MCP：`#[tool]` 计数 = **21**（20→21）；`mcp_smoke` 工具名清单已锁 `history`；返回结构由 headless `the_history_probe_reports_the_stacks` 锁定（undo_len/redo_len/top/label/清零往返）。

### buglist 打钩 — 合格（未入库）
R1/R2→`b9a8842d`、Y1/Y2/Y4→`6df9ac89`，五条均 `- [x]` + `> 已修复 <commit>` 备注；`buglist.md` untracked、不在 branch diff（`.gitignore` 的 `.mimosa/` 为前会话遗留本地改动，未提交）。
**注意**：R1 的"已修复"需补尾巴（见 🔴 发现——键位路径仍违反 R1 验收句）。

## QA 实证探针（临时测试，已删除、main.rs 已还原）

用键位派发设置（`Invoke + creates_history_entry:true`，即 `jackdaw_api_internal/src/lib.rs:726-732` 对绑定键的 Exact 行为）：

| 探针 | 结果 |
|---|---|
| `clip.delete_keyframes`（绑定 Delete/Backspace，`core_extension.rs:202`）删除 1 个关键帧 | **2 条记录**（before=0, after=2） |
| 上者后连按 undo 撤完全部 2 条 | **2 个 live keyframe（重复关键帧）** |
| `clip.paste_keyframes`（绑定 Ctrl+V，`core_extension.rs:232`）粘贴 | **2 条记录** |

机制：两 op 均自推 `CommandGroup` 却未声明 `allows_undo=false`（同族 `clip.copy_keyframes` 已声明 false——半修状态）；T1 的 R1 修复使关键帧增删落文档 → 快照 diff 由空变非空 → **双记录被 R1 激活**。undo 两次 = 快照复活 + 命令复活 = 重复。T1 的 keyframe_undo 测试用默认 `.call()`（无 history 条目）派发，未走键位路径，故全绿——偏离方案 §5「手势路径统一经 run_op_clause_as_user」的要求。

## 真机抽验（QA 自备 `t03-final-qa-live.ps1`，日志 `t03final-qa-live.log`，截图 `t03final-qa/`）

- **① history 一轮（亲调）**：clean 场景 `{undo_len:0, redo_len:0, saved_len:0, has_save_baseline:true, dirty:false}` → 用户路径（BRP `call_operator`，history 默认 true）`entity.add.cube` → `{undo_len:1, top:"Add Cube", dirty:true}` → 一次 undo → `{undo_len:0, redo_len:1, redo[0].label:"Add Cube", dirty:false}`。全过。
- **② scrub 拖拽链**：真实 UI 拖 Inspector translation X 整手势 → x 0→0.25，**undo_len 0→1（恰一条）**，top="Set component field"，dirty 亮；一次 undo → x=0、栈回 0、**dirty 灭**（指纹 clean）。全过。
- 日志中 2 个 FAIL 为 QA 脚本自身的基线重置算术错误（redo+delete 本就该 2 条；产品行为正确，h2 起点已归零且链路全过），非产品缺陷。

## T03 整体终验汇总（T1 + T2）

| 方案 §7 放行项 | 状态 |
|---|---|
| §2 矩阵 8 类全 ✅ | **未全过**：主体 7 类 ✅；class 2/3 关键帧删除/粘贴的**键位路径**双记录（🔴 发现）|
| §4.3 脏标记 14 例矩阵 | ✅（T1 headless 全绿；N4 案例真机两轮复现：程序链 3 + QA h1/h2 clean/dirty 往返）|
| 每缺陷红→绿 | ✅ 5/5（R1/R2 于 T1；Y1/Y2/Y4 于 T2；红日志逐条核实）|
| 「一次操作一条记录」（枚举手势） | ✅ scrub/拖拽/数值 Enter/unpack/多选 reset/右键 Duplicate/Add 菜单 |
| 「取消不留痕」两契约 | ✅（T1）|
| 真机 3 链 | ✅（程序，RESULT failures=0）+ QA 两项独立抽验 ✅ |
| quick/全量门 + doctests | ✅（QA 亲跑全绿/零新增）|
| buglist 五条打钩 | ✅（但 R1 需补尾巴）|
| 用户 30 秒清单 | ①✅ ②✅ ③✅（headless 关闭提示断言 + 真机 dirty 亮）；**但时间线 Delete/Ctrl+V 会踩 🔴** |

**roadmap T03 勾选建议：暂不勾**。待 🔴 返工（预计 ≤0.5 天：两 op 补 `allows_undo=false`、入 `SELF_PUSHING` 清单、keyframe_undo 测试改键位设置派发补红→绿、buglist R1 备注更新）后重验即可勾选。

## 问题统计

| 级别 | 条目 |
|---|---|
| 🔴 严重 | 1 |
| 🟡 中等 | 1 |
| ⚪ 轻微 | 3 |

1. 🔴 [程序] `clip.delete_keyframes`（Delete/Backspace）与 `clip.paste_keyframes`（Ctrl+V）键位/命令面板路径**双记录**（QA 实证 2 条），连按 undo 撤完产生**重复关键帧**（R1 验收症状在真实用户路径复现）。T1 R1 修复将其激活；T1 测试未用用户级派发故未拦截。修法同 Y1：补 `allows_undo = false` + 清单 + 键位设置红→绿测试。
2. 🟡 [程序] 同型潜伏（未实证、无确认 UI 入口，但 F3 命令面板经 OperatorAction 对全部注册 op 开放 `creates_history_entry:true`）：`terrain.generate` / `terrain.erode`（`src/terrain/ops.rs`，自推 SetTerrainHeights 组）与 `resource.insert` / `resource.remove`（`src/inspector/resource_ops.rs`，自推）。文档 diff 目前疑似为空（地形高度在 sidecar、资源为会话态）故未显双记录——建议返工时顺手定 attr 或补注记，防后续接入文档后引爆。
3. ⚪ [程序] `tests/guards/record_counts.rs:306` 注释含 mojibake「鈥?」（em-dash 双重编码），可读性微瑕。
4. ⚪ [程序] manual §7.3「20 个工具」表述过时（程序已披露，非本任务修）。
5. ⚪ [QA] 本 QA live 脚本两处基线重置断言算术错误（见上），已说明，不影响结论。

**正向**：Y4 双偏差处置（简报字面纠偏 + 单写路径收敛）判断准确、注释质量高；brush 4 op 主动扩scope；红→绿证据链与日志留档完整；history 工具设计与 manual/防回归测试同步落地。

## 返工清单（最小集）

1. `src/lib.rs`：`clip.delete_keyframes`、`clip.paste_keyframes` 补 `allows_undo = false`（对齐同族 `clip.copy_keyframes`）。
2. `tests/guards/record_counts.rs`：两 id 入 `SELF_PUSHING`；新增/改造 keyframe 用例以键位设置（Invoke+true）派发断言恰 1 条、撤完无重复。
3. （建议）🟡 四 op 处置：补 attr 或注释定案。
4. buglist：R1 条目追加键位路径备注（或新开一条），修复后打钩。
5. 重跑 quick 门 + guards；QA 重验 🔴 探针即闭。
