# T03 Undo/Redo 与脏状态加固 — 实施方案

> 策划产物（2026-10-25，基于 main 4a9f331e 全量代码核实）。需求来源：`loop/plans/roadmap-game-dev.md` T03。
> 验收原文：创建/删除/复制/改父级/组件增删/数值拖拽/资源编辑/Prefab 操作 undo 全覆盖；**一次连续操作一条记录；取消不留痕；undo 后再编辑、保存后 undo 的脏标记恒正确**。
> 已知缺陷直接吸收 buglist（R1/R2/Y1/Y2/Y4），行号已按当前代码重新定位核实；buglist 之外的新发现编号 **N1–N8**。

---

## 0. 架构事实（核实结论，方案的地基）

- **双轨撤销记录约定**（`crates/jackdaw_api_internal/src/operator.rs:650-665`）：operator 派发时，
  `creates_history_entry && allows_undo` 才捕获 before/after 文档快照，diff 非空推一条 `DocumentEdit`。
  - 模式 A（自推）：op 实现内自己 `push_executed(命令)`，**必须**声明 `allows_undo = false`；
  - 模式 B（框架快照）：op 只改 ECS/AST 不推命令，保持 `allows_undo = true`（宏默认值，`jackdaw_api_macros/src/lib.rs:22,75`）。
  - 违反模式 A 声明的 op，凡经 `creates_history_entry=true` 的派发点就**双记录**。
- **用户面派发点全部 `creates_history_entry=true`**：按钮/菜单 `core_extension.rs:57-59`、键位 `jackdaw_api_internal/src/lib.rs:726-732`、
  `JACKDAW_RUN_OP` 用户子句 `boot_ops.rs:612-614`、BRP `call_operator`（`history` 参数默认 true，`remote/server.rs:595-598`）。
  进程内直调（如 Inspector 组件 chip `add_header.rs:243-247`、Add Entity picker `lib.rs:2824`）用默认 false → 单条。
- **CommandHistory per-tab**（`scenes/swap.rs:76,287` 换 tab 时整体换栈）；undo=pop 到 redo 栈（`jackdaw_commands/src/lib.rs:171-183`）；
  `trim_to_budget` 从栈**头**丢弃最旧条目（256MiB 上限，`:160-169`）。
- **脏标记双轨且都不完备**：
  - `tab.dirty` + `history_depth_at_last_check`（watcher `scenes/mod.rs:270-293`）：**只认栈长增长**，注释明言"Shrinkage (undo) is ignored"；
  - `SceneDirtyState.undo_len_at_save` 全局单值 + `is_scene_dirty()` 精确栈长比较（`scene_io/mod.rs:325-337`），消费方仅 `asset_migration.rs:87`；
  - 两者在「保存后 undo」「undo 回存」场景互相矛盾（见 N4/N5）。
- **AST 异步同步缝隙**：`Brush` 有每帧 Update watcher `sync_changed_brushes_to_ast`（`brush/mod.rs:450`）；`Transform` **没有**对应物；
  动画实体靠 Update watcher `register_animation_entities_in_ast`（`lib.rs:2099-2119`）。凡是「op 内一次性改 ECS、靠 Update watcher 落 AST」的路径，
  框架在 op 系统返回瞬间取 after 快照时 **AST 还是旧的** → diff 为空 → 零记录（N2/N3 的根因）。

---

## 1. 范围与不做

**做**：
1. 五缺陷修复定案落地：R1、R2（含 N2 延伸）、Y1（含 N1 延伸）、Y2、Y4；
2. 脏标记语义修复：N4/N5（核心验收）/N6（per-tab 基准）/N7（trim 漏判）+ 脏标记用例矩阵全绿；
3. 撤销面 8 类操作的记录语义验证（矩阵 §2）；
4. BRP 补撤销栈状态查询工具（MCP 优先原则，§6）。

**不做**（明确出界）：
- redo 深度策略、撤销历史 UI 面板、跨 tab 全局撤销；
- buglist 相邻但非撤销语义项：Y3（吸附顺序）、Y11（自定义属性 parse 归零/无变化守卫——若 T2 有余量可顺手，默认不做）、
  Y19（地形 undo rebuild_all 性能）、R3（save_as_variant 拍平，数据缺陷归 T14 prefab 验收）；
- 动画时间线 scrub/拖动关键帧的撤销（归 roadmap T15）；PIE Live 模式的编辑流（归 T25）；
- `jackdaw/cancel` 与 modal cancel 系统本身的正确性重构（框架层契约已存在，只补契约测试）。

---

## 2. 撤销面盘点矩阵（8 类 × 现状）

状态记号：✅正确单条 ｜ ❌缺陷（buglist 编号）｜ 🆕buglist 外新缺口 ｜ ❓未证实（任务内补证）

| # | 操作类别 | 入口路径 | 现状 | 证据 |
|---|---|---|---|---|
| 1 | **创建** | Add 菜单/按钮 `entity.add.*`（~24 个，`entity_ops.rs:2632-2966`） | ❌ Y1 双记录 | `create_entity_in_world`（`:873-882`）自推 `SpawnEntity`，op 未声明 `allows_undo=false` |
| | | Add Entity picker（`lib.rs:2824` 默认 settings） | ✅ 单条 | 直调无框架快照，仅自推一条 |
| | | 放置 GLTF `entity.place_gltf`（`entity_ops.rs:2395-2443`） | ✅ 单条 | 显式 `allows_undo=true` + `spawn_gltf_in_world`（`:913-921`）不自推，模式 B |
| | | 资产浏览器拖入 GLTF | ❓ | 需确认是否经 operator（同 place_gltf 则 ✅） |
| 2 | **删除** | Delete 键/菜单 `entity.delete`、右键 `hierarchy.delete` | ✅ 单条 | `allows_undo=false`（`:2448`）+ `delete_entities` 自推分组（`:930-968`）；右键直调 `delete_selected` 同样单条 |
| | | 删除关键帧 `clip.delete_keyframes` / Delete 混合选择 | ❌ R1 | `DespawnKeyframeCmd` 裸 `despawn()`/裸 `spawn`（`lib.rs:1184-1239`），不走 `despawn_scene_entity`（`commands.rs:1274`），AST 残留→重复关键帧/幽灵复活 |
| 3 | **复制** | Ctrl+D `entity.duplicate`（`entity_ops.rs:2478-2489`） | ✅ 单条 | `duplicate_selected`（`:1118-1171`）不自推，模式 B 框架快照 |
| | | Outliner 右键 `hierarchy.duplicate`（`hierarchy.rs:2423-2427`） | ❌ Y2 零记录 | 直调 `duplicate_selected`，无 operator 无快照，Ctrl+Z 撤错对象 |
| | | 关键帧粘贴 `clip.paste_keyframes`（`SpawnKeyframeCmd`，`lib.rs:1910-1967`） | ❌ R1 | 裸 spawn/despawn 同病 |
| 4 | **改父级** | Outliner 拖拽（普通实体，`hierarchy.rs:1966-1974`） | ✅ 单条 | 事件直推 `ReparentEntity`，无 operator |
| | | 拖拽继承实体出实例（unpack 手势，`hierarchy.rs:1941-1961`） | ❌ Y4 双记录 | `prefab.unpack_child` 以 `creates_history_entry:true`（快照条 1）+ 手动 `ReparentEntity` push（条 2）；undo 中间态脏 |
| | | `entity.move_up/move_down` | ✅ 单条 | `allows_undo=false`（`:2507/2615`）+ 自推 |
| 5 | **组件增删** | Inspector chip 点击（`add_header.rs:225-248`） | ✅ 单条 | 直调 op 默认 settings，`component.add/remove` 内自推（`inspector/ops.rs:253-275,334-348`） |
| | | `component.add`/`component.remove` op 声明 | 🆕 **N1** | 两 op 未声明 `allows_undo=false`（`inspector/ops.rs:182-191,284-293`）却自推——凡经键位/菜单/BRP(`history:true`) 派发即**双记录**（buglist Y1 清单之外） |
| | | 自定义属性增删/改（`custom_props_display.rs`） | ❓ + Y11 相邻 | apply_custom_property_with_undo 无新旧值守卫（Y11），聚焦丢失也 mint；本任务只验证单条性 |
| 6 | **数值拖拽** | Inspector 数值行 scrub（`commands.rs:136-294` field_edit 会话） | ✅ 一手势一条 | preview 无记录、commit 一条 + 手势前基线；已有测试 `gesture_session_baseline_survives_live_preview_mutation`（`:2940`） |
| | | 视口 gizmo / modal 拖拽收笔（`modal_transform.rs:474-485`） | ✅ 一手势一条 | `push_executed_synced(SetTransform)` |
| | | Brush 笔刷/顶点拖拽 | ✅ 一手势一条 | 模式 B：每帧 watcher 保 AST 新鲜，`finalize_modal(true)` 快照收笔 |
| | | 数值变换 X+数字+Enter（`numeric_transform.rs:425-528`） | ❌ R2 零记录 | op `allows_undo=true`，`apply_object` 直改 ECS Transform 不落 AST；快照 diff 空 → 无记录；undo 撤错+保存丢+不置脏 |
| | | 同上 **BrushEdit 子元素分支**（`apply_sub_elements`:532+） | 🆕 **N2** 零记录 | 改 Brush 后靠 Update watcher 落 AST，晚于框架 after 快照 → 无撤销记录不置脏（保存在 watcher 跑后发生，不丢数据） |
| | | 取消：X+数字+Esc（`numeric_transform.rs:238-241`）、modal Esc（`operator.rs:889-957` `finalize_modal(false)` 弃快照） | ✅ 契约成立 | 框架层承诺在；缺的是契约测试（§5） |
| 7 | **资源编辑** | Resources 面板（`inspector/resource_commands.rs`） | ✅ 设计良好 | `ResourceSetField/Insert/Remove` 自推；preview 无记录；commit 带 `live_at_begin` 手势基线、值未变不推（`:341-400`） |
| | | 语义注记 | 🆕 **N8** | 资源编辑是 editor 会话态（模块注释明言不进文档），却因栈长联动把**场景 tab** 置脏——是否接受见裁决项 3 |
| 8 | **Prefab 操作** | `prefab.unpack_child` op 本体（`prefab/operators.rs:2463-2494`） | ✅ 单条 | 模式 B 快照（operators.rs 全文件无 push_executed） |
| | | unpack 拖拽手势 | ❌ Y4（见 #4） | |
| | | `prefab.unbundle_instance` / `apply_to_source` / override 编辑 | ❓ | 同为模式 B 推定单条，T2 真机矩阵抽验 2 项 |
| | | `save_as_variant` | ❌ R3（数据缺陷，非撤销） | 出界归 T14 |

**统计**：8 类中 5 类主体路径正确；缺陷=buglist 5 条（R1/R2/Y1/Y2/Y4）全部核实属实；**buglist 外新缺口 7 个**：N1（component.add/remove 双记录）、N2（brush 数值零记录）、N3（toggle_keyframe 零记录，见 §3.1）、N4–N7（脏标记，见 §4）、另 N8 语义注记。

---

## 3. 五缺陷修法定案

优先级：**R2 > R1 > Y4 > Y2 > Y1**（R2 直接丢保存数据；R1 数据损坏；Y 类是记录数错误）。

### 3.1 R1（含新延伸 N3）— 关键帧命令改走文档感知路径

核实：`DespawnKeyframeCmd::execute` 裸 `ent.despawn()`（`lib.rs:1192-1194`）、`undo` 裸 `spawn(.., ChildOf(*track))`（`:1197-1239`）；
`SpawnKeyframeCmd` 对称（`:1910-1967`）；`register_animation_entities_in_ast`（`:2099-2119`）把 `Added<Keyframe>` 注册进 AST——
因此 undo 重生的实体会被 watcher 注册成第二个节点（重复关键帧），整文档 respawn 类 undo 把已删关键帧复活。
🆕 **N3**：`animation.toggle_keyframe`（`inspector/ops.rs:445-472` → `anim_diamond.rs:134-178`）同样裸 spawn 靠 watcher 落 AST，
框架 after 快照取在 watcher 之前 → **toggle 没有自己的撤销条目**（静默并入下一条目的 diff）。

**修法（定案）**：不改成 `SpawnEntity/DespawnEntity` 泛型命令（其 `DynamicScene` 往返正是本命令当初要避开的 ID 复用坑，注释 `lib.rs:1130-1141` 成立），而是：
1. `DespawnKeyframeCmd::execute/undo`、`SpawnKeyframeCmd::execute/undo` 的 spawn/despawn 改为：
   despawn → `crate::commands::despawn_scene_entity`（AST 感知，`commands.rs:1274`）；
   spawn → 裸 spawn 后**同步** `scene_io::register_entity_in_ast(world, entity)`（不等 Update watcher）。
   保留 relive/字段捕获设计；`ChildOf` 红线不变。
2. N3：`animation.toggle_keyframe` 的 op 闭包内在 toggle 完成后同步注册新 clip/track/keyframe（调 `register_entities_in_ast` 等价逻辑），
   使模式 B 快照 diff 捕捉到关键帧增删；op 保持 `allows_undo=true`。
3. 验收测试（红→绿）：删关键帧→undo 恰一条→AST 节点数不变、时间轴只有一个该时刻关键帧；toggle→undo 恰一条→关键帧消失且 AST 干净；
   整文档 respawn undo 后已删关键帧不复活（对应 `undo_snapshot.rs` respawn 路径）。

### 3.2 R2（含新延伸 N2）— 数值变换统一走框架快照单条记录

核实：op `transform.numeric_apply` `allows_undo=true`（`numeric_transform.rs:431`），Enter 经 `creates_history_entry:true` 派发（`:243-255`）；
`apply_object` 直改 ECS `Transform`（`:475-528`），全仓无 `Changed<Transform>`→AST watcher（Brush 有 `brush/mod.rs:450`，Transform 无）→
快照 diff 空 → **零记录**：①undo 撤上一个无关操作（且其 respawn 顺带把 AST 旧位置写回，视觉"撤错"）；②保存从 AST emit 丢移动；③栈不增长不置脏。

**修法（定案，方案 A）**：op 保持 `allows_undo = true`（模式 B，框架快照恰一条）：
- **Object 分支**：对每个 `topmost_selected` 目标构造 `SetTransform{old,new}` 并调 `cmd.execute(world)`（ECS 写入 + **同步** AST sync，
  `commands.rs:365-376` 已具备），**不 push**——变化全部进入框架 after 快照。多选=一条记录（验收"一次连续操作一条记录"）。
- **BrushEdit 分支（N2）**：`apply_sub_elements` 完成后**内联** `run_system_cached(sync_changed_brushes_to_ast)`，
  让 after 快照看到 AST 变化 → 从零记录变一条。
- **与 buglist 建议的差异（裁决项 1）**：buglist 建议"object 路径改走 SetTransform + push_executed_synced（与拖拽提交一致）"，
  即模式 A（typed undo，undo 不触发文档 respawn）。不直接采纳的原因：无 `SetBrush` 命令，brush 分支只能走快照；
  两分支同 op 却两种记录机制需 `allows_undo=false`+快照混合，复杂度更高。方案 A 两分支一致、改动最小。
  代价：undo 走 `DocumentEdit` 单元 diff（in-place 优先、失败 respawn），与 brush 拖拽 undo 行为一致，用户已习惯。
- 验收测试：X+数字+Enter → undo 恰一条 → Transform 回旧值且 AST 一致；保存重开位置保持；`status.dirty` 亮；
  BrushEdit 模式同样恰一条（当前红：零条）。

### 3.3 Y1（含新延伸 N1）— 自推型 op 全量补 `allows_undo = false`

核实：宏默认 `allows_undo=true`；用户面派发点全部 `creates_history_entry=true`（§0）；以下 op 实现内自推却不声明 false → 双记录：

| 批次 | op 清单 | 自推证据 |
|---|---|---|
| 1 | `entity.add.*` 全部 ~24 个（`entity_ops.rs:2632-2966`） | `create_entity_in_world:873-882` push `SpawnEntity` |
| 2 | `transform.reset_position/rotation/scale`、`rotate_90_*`×6、`nudge_*`×6（`transform_ops.rs:121-380`） | `reset/nudge/rotate_selected`（`entity_ops.rs:1336-1470`）push `CommandGroup` |
| 3 | `entity.paste_components`（`entity_ops.rs:2568-2579`） | paste 链自推（兄弟 `entity.paste:2546` 已显式 false） |
| 4 | 🆕 N1：`component.add` / `component.remove`（`inspector/ops.rs:182,284`） | `:253-275,334-348` push `AddComponent/AddProjectComponent/RemoveComponent` |
| 5 | `spawn_undoable`（`lib.rs:2836-2846`）的 operator 调用点（实现时逐一清点，buglist 记 5+1 处） | `spawn_undoable` 自身 push |

**修法（定案）**：按 buglist 方向一——**全部补显式 `allows_undo = false`**（不删自推：Add picker、右键菜单、chip 直调等非 operator 调用方依赖自推获得撤销，
删自推会让这些入口彻底失去 undo）。**不得误伤模式 B**：`entity.duplicate`、`entity.toggle_visibility`（`hide_selected` 注释明言不推，`:2078-2080`）、
`entity.place_gltf`（显式 true 且不自推）保持现状。
验收：每个批次抽 1 个代表 op，经 `boot_ops::run_op_clause_as_user`（等价用户按键路径）执行后 `undo_stack.len()` 恰 +1；
全量清点用脚本扫描 `#[operator` 块 + 函数体 `push_executed` 交叉核对（防止漏网/误伤）。

### 3.4 Y2 — 右键 Duplicate 改派发操作符

核实：`hierarchy.rs:2423-2427` 直调 `duplicate_selected`（不自推、无 operator）→ 零记录；Ctrl+D 的 `entity.duplicate` 是模式 B 单条。
**修法（定案）**：右键菜单改派发 `entity.duplicate` 操作符，settings 与用户手势一致（`creates_history_entry:true`），
获得框架快照条目 + 正确 label；与同文件 `hierarchy.rename` 已有的 operator 派发写法（`:2415-2421`）对齐。
（备选"函数内补快照对"不采：需要暴露框架私有 `push_snapshot_diff`，为一个入口加 API 不值。）
验收：右键 Duplicate → `undo_stack.len()` +1 → Ctrl+Z 一次复制品消失。

### 3.5 Y4 — unpack 手势合并为单条框架快照

核实：`hierarchy.rs:1941-1961`：`prefab.unpack_child`（`creates_history_entry:true` → 快照条 1，只覆盖 AST unpack）
+ 手动 `ReparentEntity` push（条 2）。undo 先弹 ReparentEntity：把已 unpack 的 standalone 实体按旧 location 挂回（`set_hierarchy_location`
把 ECS 层挂回写进 AST，中间态文档与 ECS 不一致），再弹 unpack 快照 → 中间态脏。
**修法（定案）**：利用 operator.rs:650 已有的"外层快照覆盖内层变更"语义——把 **ECS reparent 移进 `prefab.unpack_child` op 的执行体**
（op 已接收 `drop_target_entity`；`unpack_child` 完成 AST 写入后，紧接执行 `ReparentEntity::execute`，**不 push**），
`hierarchy.rs` 删去自己的 operator settings 与手动 push，仅保留一次 `creates_history_entry:true` 调用 → 单条快照同时覆盖 AST + ECS。
唯一调用方即 hierarchy.rs:1942（已核实），改动无外溢。
验收：拖继承实体出实例 → undo **恰一次** → 文档字节等于手势前捕获；redo 恢复；中间无"挂回实例"瞬间。
实现注意：核实 unpack 的 standalone AST 副本与 live 实体 reparent 的最终文档一致性（两条写是否指向同一节点——当前双条目下就含糊，
合并后以「undo 一次文档回到手势前」为硬标准）。

---

## 4. 脏标记语义：缺陷清单（N4–N7）+ 用例矩阵

### 4.1 缺陷（均为 buglist 外新发现，已按代码核实）

| 编号 | 场景 | 现状 | 证据 | 后果 |
|---|---|---|---|---|
| **N4** | **保存 → undo**（验收原文直接命中） | `tab.dirty` 保持 false（watcher 忽略收缩，`scenes/mod.rs:282` 只判 `current_depth > recorded`）；`is_scene_dirty` 为 true | 双轨分歧 | **关 tab 无未保存提示 → 改动静默丢失**（用户可见脏标记以 tab.dirty 为准） |
| **N5** | 编辑 → undo 回到已保存内容；或 保存→undo→新编辑（栈长恰好回弹==保存栈长） | tab.dirty 不清除（多提示一次保存，轻）；`is_scene_dirty` **假阴性**（`scene_io/mod.rs:336` 精确比较 len） | | asset_migration 守卫在脏场景下放行 |
| **N6** | 多 tab 切换 | `activate_tab` 换 per-tab `CommandHistory`（`swap.rs:286-287`）但**不还原** `SceneDirtyState.undo_len_at_save`（全局单值） | | 换 tab 后 `is_scene_dirty` 拿 A tab 的基准比 B tab 的栈长，错位 |
| **N7** | 256MiB 预算触发 `trim_to_budget`（大地形长会话） | trim 从栈头丢条目使 len 下降甚至回落（`jackdaw_commands/lib.rs:160-169`），watcher 的"增长判脏"漏判 | | 极端场景真编辑不置脏（低概率，但修复便宜） |

另（§2 N8）：资源编辑把场景 tab 置脏——语义注记，默认维持现状（宁多提示不丢数据），见裁决项 3。

### 4.2 修法（定案）

1. **基准 per-tab 化（N6）**：`undo_len_at_save` 迁到 `SceneTab`（`scenes/mod.rs`），`SceneDirtyState` 改为读 active tab 的兼容视图或直接删除并改写 4 个写点
   （`load.rs:438`、`save.rs:265,364`、`prefab/operators.rs:1114`、`asset_migration.rs:862`）；`is_scene_dirty()` 与 tab.dirty 判定**统一为一个函数**，消除双轨分歧。
2. **增长判据换单调计数（N7）**：`CommandHistory` 暴露公开只读 `total_pushes()`（内部已有 `pushes: u64`）；watcher 用它判增长，trim 不再干扰。
3. **栈长回归保存点时做内容比对（N4/N5，裁决项 2）**：保存时把已到手的内容（`save.rs:342-344` 的 `contents`） hash 存 tab（`saved_doc_hash`）；
   watcher 发现 `undo_stack.len() == tab.saved_undo_len` 这一**迁移点**时，用与保存同源的 `emit_bsn_scene_for_file` emit 当前文档并 hash 比对：
   相等 → `tab.dirty=false`（undo 回存/保存后 undo 又 redo 回来），不等 → true（保存后 undo：len 已不等，直接 true，无需比对）。
   每帧成本 O(0)（仅在栈长恰好相等的罕见帧 emit 一次）。若裁决不接受 emit 成本 → 退化方案：接受 N5 假阴性记录为 known-issue，仅修 N4
   （保存后 undo 置脏：undo 后 len≠saved_len 本已成立，只需 tab.dirty 同步采纳"len 不等即脏"）。

### 4.3 脏标记用例矩阵（14 例，T1 验收全绿；列=期望 tab.dirty ≡ is_scene_dirty ≡ 关闭提示）

| # | 操作序列 | 期望 |
|---|---|---|
| 1 | 打开场景，无操作 | clean ≡ clean ≡ 无提示 |
| 2 | 一次编辑 | dirty ≡ dirty ≡ 提示 |
| 3 | 编辑 → undo（回到已保存内容） | **clean**（现 N5 红） |
| 4 | 编辑 → undo → redo | dirty |
| 5 | 保存 → undo | **dirty + 提示**（现 N4 红——本任务最高危用例） |
| 6 | 保存 → undo → redo | clean |
| 7 | 编辑A → 保存 → undo → 编辑B（栈长回弹==保存值，内容≠） | dirty（现 N5 假阴性红） |
| 8 | 编辑 → 保存 | clean |
| 9 | scrub 拖拽数值一整个手势 | dirty 且 undo 栈恰 +1 |
| 10 | 拖拽 modal 中 Esc 取消 | 栈长不变、dirty 不变、文档不变（快照空转承诺） |
| 11 | X+数字+Esc 取消数值输入 | 无记录无脏（`numeric_transform.rs:238-241` 契约） |
| 12 | 右键 Duplicate → undo | 复制品消失、dirty 随 undo 回落（Y2 修后） |
| 13 | tab A 编辑置脏 → 切 tab B（clean）→ 切回 A | A dirty 保持、B clean（N6 修后） |
| 14 | 资源面板改字段 → undo | 值回滚；dirty 行为按裁决项 3 的裁定断言 |

---

## 5. 测试策略

**Headless（每缺陷红→绿 + 脏断言）**：
- 位置：`src/commands.rs`、`src/lib.rs`、`src/numeric_transform.rs`、`src/scenes/mod.rs` 既有 `#[cfg(test)]` 扩展 + `tests/guards/`
  （`batch_undo.rs` 的 handler 调用模式可参照）；用户手势路径统一经 `boot_ops::run_op_clause_as_user`（它就是"按键级"派发，`boot_ops.rs:600-620` 注释即为此设计）。
- 必备断言三件套：`undo_stack.len()` 恰 +N、undo 后文档/ECS 值回滚、`tab.dirty`/`is_scene_dirty` 与 §4.3 矩阵一致。
- Y1 全量防回归：新增一个扫描型单测——注册表里所有 `allows_undo=true` 的 op，其实现模块不含 `push_executed` 直调
  （静态不可行则退化为清单测试：对 §3.3 表逐 op 断言 `ALLOWS_UNDO == false`）。

**真机（QA manual §7 工具链，窗口 1920x1080）**：
- 链 1（R2+scrub+脏）：选中实体 → `input.key` 序列 X、1、Enter → `jackdaw/history`（新工具）断言恰 1 条 → `call_operator history.undo` →
  `world.get_components` 断言 Transform 回原值 → `status.dirty` 断言灭 → 再拖 Inspector translation 行（`ui_drag`）一整个手势 → 恰 1 条。
- 链 2（Y2）：Outliner 右键菜单（`ui_click` context menu → Duplicate）→ 恰 1 条 → undo → `scene_tree` 断言复制品消失。
- 链 3（Y4+保存回环）：拖继承实体出 prefab 实例（`ui_drag` outliner 行）→ 恰 1 条 → undo 一次 → `jackdaw/scene_bsn` 与手势前捕获比对 → Ctrl+S → undo（用例 5：dirty 必须亮）。
- 工程与不存盘策略照 manual §7.5（my-game SHA256 校验或 fixture 工程）。

**工具补充（MCP 优先原则，并入 T2）**：
- 现状：`jackdaw/status` 已返回 `dirty`（`remote/server.rs:489`，脏状态查询**可达**）；**撤销栈状态不可达**（方法清单 `:147-166` 无历史查询）。
- 补 `jackdaw/history` BRP 方法：`{undo_len, redo_len, saved_len, dirty, entries:[{label}…] 末尾 N 条}`，读 `CommandHistory` + active tab 基准即可，
  挂 `remote/server.rs` 既有 `with_method_main`；配 headless 单测。此工具同时是 §4.3 矩阵真机断言的基础设施。

---

## 6. 任务拆分（2 个）

**T1「数据完整性与脏标记」（R2+R1+脏标记矩阵）**
1. R2：`numeric_transform_apply` 两分支改框架快照单条（§3.2，含 N2 内联 brush 同步）；
2. R1：关键帧四命令 + toggle_keyframe 文档感知化（§3.1，含 N3）；
3. 脏标记：per-tab 基准 + 单调计数 + 栈长回归点内容比对（§4.2，N4/N5/N6/N7，按裁决项 2 的裁定范围）；
4. 脏标记 14 例矩阵 headless 全绿；quick 门（fmt/clippy/lib tests + 被改 crate 集成/doctest）。

**T2「记录数一致性与真机」（Y 类 + 工具 + 全量门）**
1. Y1+N1：自推型 op 全量补 `allows_undo=false`（§3.3 五批次 + 扫描防回归）；
2. Y2：右键 Duplicate 派发 operator（§3.4）；
3. Y4：unpack 手势合并单快照（§3.5）；
4. `jackdaw/history` BRP 工具（§5）；
5. 真机 3 链 + 抽验 prefab unbundle/apply_to_source 单条性（❓ 项补证）；
6. 全量门（`xtask fast`/`integration`/docs/doctests）+ buglist 打钩（R1、R2、Y1、Y2、Y4 各追备注）。

---

## 7. QA 清单（放行标准）

- [ ] §2 矩阵 8 类全 ✅（含 ❓ 项补证或明确移交）；每缺陷有红→绿 headless 测试；
- [ ] §4.3 脏标记 14 例矩阵 headless 全绿，其中用例 5（保存后 undo）额外真机复现；
- [ ] 「一次连续操作一条记录」：scrub/拖拽/数值 Enter/unpack 手势/多选 reset 全部恰 1 条（`jackdaw/history` 断言）；
- [ ] 「取消不留痕」：modal Esc、数值输入 Esc 两契约测试绿；
- [ ] 真机 3 链全过（§5），截图与 BRP 日志留档 `loop/reports/`；
- [ ] quick 门全绿（T1）/ 全量门全绿（T2）；buglist 五条打钩；
- [ ] 用户 30 秒清单：①选中物体 X+1+Enter 移动后 Ctrl+Z 一次弹回且保存重开位置正确；②右键 Duplicate 后 Ctrl+Z 一次消失；
      ③保存后 Ctrl+Z 关标签页必须弹未保存提示。

## 8. 风险

| 风险 | 缓解 |
|---|---|
| R1 改 `despawn_scene_entity` 后关键帧 undo 走文档 respawn，实体 id 全换，timeline 高亮/选择短暂失效 | respawn 机制本就是全编辑器 undo 的既定行为（选择按 SceneNodeId 恢复，`undo_snapshot.rs:433`）；真机链观察即可 |
| R2 方案 A 的 undo 走 DocumentEdit diff，大场景 in-place 失败时 respawn 一帧闪变 | 与既有 brush 拖拽 undo 同体验；如用户裁决选方案 B（裁决项 1）则 object 分支无此问题 |
| Y1 批量翻 `allows_undo=false` 漏改/误伤模式 B op | §3.3 明确"不得误伤"清单 + 扫描型防回归测试 + 每批抽验 |
| Y4 合并后 unpack 的 AST standalone 副本与 live reparent 文档一致性存疑（现状本就含糊） | 验收硬标准=undo 一次后文档字节等于手势前；不一致则实现时收敛为单一写路径 |
| 脏标记内容比对在超大场景的 emit 成本 | 仅"栈长==保存栈长"迁移点触发； profiling 不达标则走裁决项 2 退化方案 |
| `SceneDirtyState` 迁移触碰 4 个写点 + asset_migration 行为变化 | 全部写点已定位（§4.2-1）；迁移守卫语义只会变严不会变松 |

## 9. 需用户裁决项

1. **R2 修法方向**：A=统一框架快照（本方案推荐，两分支一致、改动最小，undo 走文档 diff）；B=buglist 原建议（object 分支 typed `SetTransform` 自推 + `allows_undo=false`，undo 更轻，但 brush 分支仍需快照，同 op 双机制）。默认 A。
2. **N4/N5 修复深度**：完整方案（栈长回归保存点时做文档指纹比对，语义恒正确）vs 退化方案（仅修 N4 保存后 undo 置脏，接受 N5 假阴性记 known-issue）。默认完整方案。
3. **N8 资源编辑置脏语义**：资源面板编辑当前会把场景 tab 置脏（栈长联动）而资源本身不入场景文件。维持现状（推荐，宁多提示）还是隔离（资源编辑不置脏场景 tab，实现需区分命令域，成本中等）？
