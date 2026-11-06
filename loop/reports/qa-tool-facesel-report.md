# QA 工具层小任务报告：`brush.selection.set_faces`

> 任务来源：R7 QA 真机腿死点（Face 模式视口 brush 子元素拾取无结构化工具入口），MCP 优先原则，
> 主控裁定补工具。程序 agent 执行，2026-11-06。
> **未合入 main，待主控/R7 QA 复跑验证。**

## 结论

新增结构化 operator **`brush.selection.set_faces`**：直写一个 brush 的面选择状态并进入 Face
编辑模式，达成与「视口点选一个面」完全相同的编辑器状态（`EditMode = BrushEdit(Face)` +
`BrushSelection` 面选中 + `active_brush`），供 QA/自动化经 BRP 驱动 Face 模式编辑链路
（nudge / drag / 材质应用等）。全部拒绝路径走结构化应答（`OperatorWarnings` + `Cancelled`），
不 panic。分支 `loop/qa-tool-brush-face-select`，单 commit，diff 面仅
`src/edit_mode_ops.rs` 一个产品文件。

## diff 面

| 文件 | 变更 | 说明 |
|---|---|---|
| `src/edit_mode_ops.rs` | +382 / -1 | operator 实现 + 参数解析/拒绝辅助 + 9 个单测；`add_to_extension` 注册一行；文件头注释补一段归属说明 |

无其它产品文件改动。注册聚合点 `core_extension.rs` 无需改（`edit_mode_ops::add_to_extension`
已在其中挂接，新 operator 并入该函数即可）。未触碰：拾取（viewport picking）代码、
`BrushSelection` 定义本身（无需加方法）、nudge/CSG/Knife、buglist/roadmap/progress。

### 归属文件选择说明

选 `edit_mode_ops.rs` 而非 `brush_element_ops.rs` 或新文件，理由：
1. 该文件拥有「如何正确进入 Face 模式」的既有语义（`switch_brush_edit_mode` 的
   Object→BrushEdit 置位链路），新 operator 写入的目标状态正是该链路的直写版；
2. 该文件是 `allows_undo = false`（「编辑模式是 UI 态而非场景变更」）先例所在，与新 operator
   的历史口径一致；
3. 最小文件面：其 `add_to_extension` 已被 `core_extension.rs` 调用，零注册胶水改动。

## operator 参数与应答形态

```
brush.selection.set_faces(entity: Entity, faces: String = 无默认)
```

- **`entity`**（`Entity` 型）：目标 brush 实体。经 BRP 调用时按 `resolve_entity_params`
  自动解析——传实体 id（`jackdaw/scene_tree` 报告的 bits，JSON number）或场景唯一名
  （JSON string）均可；BRP 层对「唯一 Entity 参数传 id」还会顺带 `select_only` 该实体。
  operator body 另容忍直传 `PropertyValue::Entity`（进程内调用）或 Int bits 兜底。
- **`faces`**（`String` 型）：逗号分隔的 authored 面索引，如 `"0,2,5"`。`PropertyValue` 无
  数组变体，故用字符串形态；BRP 层会把 JSON 数组参数 `to_string()` 成 `"[0, 2, 5]"`，
  解析器容忍一对方括号（strip 后按逗号分词、逐词 trim）。空串 = 合法写入「进入 Face 模式
  但不选任何面」。列表按给定顺序原样写入（不去重、不排序）。
- 索引校验边界：`face < brush.faces.len()`（与 `brush.face.drag` 的同一 bound，authored 真值）。

### QA 直调（BRP）

```json
{"id": "brush.selection.set_faces", "params": {"entity": 4294967301, "faces": "0,2,5"}}
```

或 `"entity": "Authored"`（按名字）。经 `jackdaw/call_operator`（`call_operator_handler`）调用。

### 应答形态

- 成功：`result = "finished"`，`warnings` 空。
- 拒绝（全部 `OperatorResult::Cancelled` + `warn_caller`，警告进入 outcome 的 `warnings`
  数组，不 panic）：
  - 缺 `entity` / 缺 `faces` 参数 → `expected ...`；
  - 实体不存在或无 `Brush` 组件 → `entity {id} does not exist or carries no Brush component`；
  - 面索引越界 → `face index {i} is out of range; the brush has {n} faces`；
  - token 无法解析为 usize（含负数）→ `"{token}" is not one`。
- 拒绝路径零状态写入：`EditMode` 与 `BrushSelection` 均保持原样（有测试锚定）。

### 成功写入的目标状态（与 QA 实测「已进入形态」一致）

- `EditMode = BrushEdit(Face)`（BRP 读资源形如 `{'BrushEdit':'Face'}`，状态栏 Edit: Face）；
- `BrushSelection.brushes` 被替换为恰好 {目标实体}（先 `clear()` 再插入，避免上次会话残留的
  编辑集合造成幽灵高亮/断言意外）；目标实体的 `sub.faces = faces`（vertices/edges 为空）；
- `BrushSelection.active_brush = Some(目标)`；
- `last_face_entity` / `last_face_index` 不触碰（它们是「上次退出面模式」的记忆，不属于本写入）；
- 实体级 `Selection` / `Selected` 不触碰（单一职责；BRP 层传 id 时已自动 select_only）。

可用性门：`can_change_edit_mode`（与 `edit_mode.face` 同款：无文本焦点、无 modal、无拖拽在途、
3D 视口前台）。门失败时 dispatch 层仅 debug 日志 + `Cancelled`——这是家族既有行为。

## 历史口径（如实记档）

**不 push undo，`allows_undo = false`。** 依据两条先例：

1. **实体级 `selection.set`**（BRP handler `jackdaw/selection.set`，`src/remote/server.rs`）：
   直接写 `Selection` 资源 + `Selected` 标记，全程不触碰 `CommandHistory`——实体选择不 push undo
   是既定口径；
2. **`edit_mode.face` / `brush.exit_edit_mode`**（同文件）：`allows_undo = false`，注释明言
   「edit-mode is UI state, not a scene mutation」。

机制保证：dispatcher（`crates/jackdaw_api_internal/src/operator.rs` 的 `dispatch_operator`）
按 `creates_history_entry && op.allows_undo` 门控快照与 `save_history`，故无论调用方
`history` 标志为何，本 operator 任何结果（含成功写入）都不产生快照、不进 undo 栈。
有测试锚定该常量（见下）。

## 测试清单（锚放 `src/edit_mode_ops.rs` `#[cfg(test)]`，9 个，全绿）

| 测试 | 锚定 |
|---|---|
| `a_valid_write_lands_faces_and_enters_face_mode` | 合法写入：faces `[0,2,5]` 落位、EditMode=BrushEdit(Face)、唯一 edit brush、active_brush、无警告 |
| `a_bracketed_faces_list_reads_the_same` | `"[1, 4]"` 括号形态（BRP 数组强转产物）等同 `"1,4"` |
| `raw_bits_entity_parameter_is_accepted_too` | 直传 Int bits 实体参数兜底路径 |
| `empty_faces_enters_face_mode_with_nothing_selected` | 空列表 = 进 Face 模式且不选面 |
| `an_out_of_range_index_is_refused_and_writes_nothing` | 越界拒绝（cuboid 6 面，索引 6 拒绝）：拒绝消息点名索引与面数，EditMode/BrushSelection 零写入 |
| `a_malformed_token_is_refused_and_writes_nothing` | 坏 token（`"0,two"`）拒绝并点名 token，零写入 |
| `an_entity_without_a_brush_is_refused` | 无 Brush 组件实体拒绝，消息含 "no Brush component"，零写入 |
| `a_missing_parameter_is_refused` | 缺 `faces` 参数拒绝 |
| `the_write_never_arms_undo` | 历史口径：`BrushSelectionSetFacesOp::ALLOWS_UNDO == false`（dispatcher 据此跳过快照与历史，见上文机制保证） |

## 门禁表（完整日志归档 `loop/qa-tool-facesel/`，全文复核制）

| 门 | 结果 | 证据 |
|---|---|---|
| `cargo fmt --all -- --check` | PASS（EXIT=0） | `gate-fmt.log`（首轮 4 处格式 diff，`cargo fmt` 修复后重跑覆盖归档，复核 0 处 Diff） |
| `cargo clippy --workspace -- -D warnings` | PASS（EXIT=0） | `gate-clippy.log`（全文复核 0 条 warning/error 行） |
| `cargo test --workspace --lib` | PASS（EXIT=0） | `gate-test.log`（59 二进制全 ok、0 FAILED、0 panic；总数 **3113**，逐行提取 `test result:` 求和） |

### 测试总数口径说明（如实记档）

任务简报写「基线 3108（59 二进制）」，但 3108 是 **R7 在途分支**的数字（R7 QA commit 记录
「3108 = 3104 + 4」）。本分支按契约自 **main（a823f4da）** 拉，main 基线为 **3104**
（R6 收尾 QA 记录「3104 = 3098 + 6」）。3113 = 3104（main 基线）+ 9（本任务新增），吻合。
主 jackdaw 二进制 1287 = 1278（main）+ 9，亦与定向运行时「1278 filtered out」一致。

## 偏差清单

1. **分支基点纠正（过程中自纠）**：首次 `git checkout -b` 从当时的 HEAD（`6086876a`，R7 在途
   分支）拉出，发现后立即删分支并自 main `a823f4da` 重拉。未产生任何基于 R7 分支的产物。
2. **测试基线数字**：如上节说明，3108 → 实际适用基线 3104，预期总数 3117 → 实际 3113，
   差异全部可追溯到「简报基线含 R7 在途改动」这一原因，非测试缺失。
3. **`faces` 参数为 String 形态而非原生数组**：`OperatorParameters` 的 `PropertyValue`
   无数组变体，结构化数组参数超出本任务范围（需改 `jackdaw_scene_types` 类型定义，触碰
   红线「不碰 BrushSelection 定义本身」同级别的公共类型面）；字符串 + 括号容忍已覆盖 BRP
   JSON 数组强转形态。若主控裁定后续升级为原生数组参数，属独立小任务。
4. **`bug-r7-qa.md` 未读**：该报告文件只在 R7 在途分支上、main 不存在；死点证据取自 R7 QA
   commit message（6086876a）原文，与任务简述一致。
5. 无其它偏差；未顺带修其它票，未动 nudge/CSG/Knife/拾取/`BrushSelection` 定义。

## 状态

- 分支 `loop/qa-tool-brush-face-select`（自 main `a823f4da`），单 commit，**未合入 main**。
- 待办移交：主控裁定 → R7 QA 复跑真机腿（用本 operator 替代「视口点选单面」步骤）→
  QA PASS 后按契约 `--no-ff` 合入。
