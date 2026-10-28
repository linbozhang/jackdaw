# T03 任务 1 报告：数据完整性与脏标记（R2 / R1 / N4–N7）

提交 `b9a8842d`（分支 `loop/t03-undo`，自 main `4a9f331e`），方案 `loop/plans/t03-undo-hardening.md` 任务 1。
裁决采用：①R2=方案 A（统一框架快照）；②N4/N5=完整方案（指纹比对）。

## 修复内容

### R2（含 N2）— `transform.numeric_apply` 两分支改框架快照单条
- `src/numeric_transform.rs`：Object 分支改为 `plan_object` 产出 `(entity, old, new)` 计划，经
  queued command 逐个执行 `SetTransform::execute`（ECS 写入 + 同步 AST sync），**不 push**——全部变化
  进入框架 after 快照 diff，恰一条（多选同一条）。BrushEdit 分支在 `apply_sub_elements` 后内联
  `run_system_cached(sync_changed_brushes_to_ast)`，使 after 快照看到 AST 变化。
- `src/brush/mod.rs`：`sync_changed_brushes_to_ast` 提为 `pub(crate)`（供内联）。

### R1（含 N3）— 关键帧四命令 + toggle 文档感知化
- `src/lib.rs`：`DespawnKeyframeCmd::execute` 与 `SpawnKeyframeCmd::undo` 的 despawn 改
  `commands::despawn_scene_entity`（AST 感知）；`DespawnKeyframeCmd::undo` 与 `SpawnKeyframeCmd::execute`
  的 spawn 后同步 `scene_io::register_entity_in_ast`。保留 relive/字段捕获/`ChildOf` 设计。
- `src/inspector/anim_diamond.rs`：`toggle_keyframe` 改为返回本次新建的 clip/track/keyframe 实体列表。
- `src/inspector/ops.rs`：`animation.toggle_keyframe` op 闭包内 `register_entities_in_ast` 同步注册，
  使模式 B 快照 diff 捕捉关键帧增删（op 保持 `allows_undo=true`）。

### 脏标记 N4/N5/N6/N7（裁定②完整方案）
- `crates/jackdaw_commands/src/lib.rs`：新增 `CommandHistory::total_pushes()` 公开只读单调计数（N7）。
- `src/scenes/mod.rs`：`SceneTab` 基准 per-tab 化——`observed_undo_len`/`observed_pushes`（watcher 观察
  基准）+ `saved_undo_len`/`saved_doc_hash`（保存点栈深 + 内容指纹）；watcher
  `mark_active_dirty_on_history_growth` 重写：快路径 (len, pushes) 均不变则 O(1) 返回；有变化时按
  「len≠saved → 脏；len==saved → 指纹比对（queued command 内 emit）」判定；无基准（未保存 tab）退化为
  单调增长判脏。**保持非 exclusive 签名**（指纹比对经 Commands 闭包执行，避免 exclusive 系统重塑
  Update 调度——曾引发 ui_probe_click 时序回归，见「偏差与说明」）。
- `src/scene_io/save.rs`：新增 `document_hash` 与 `document_fingerprint`（与保存同源的
  `emit_bsn_scene_for_file` / prefab 分支 `emit_bsn_scene_with_inline_assets`）；两个保存分支
  （scene + prefab）写 per-tab 基准。
- `src/scene_io/load.rs`、`src/scenes/operators.rs::open_read_scene`、`src/prefab/operators.rs`、
  `src/scenes/external_watch.rs::adopt_reloaded_document`：全部写点改 per-tab 基准。open_read_scene
  对「升级打开」的 tab 保持 dirty=true 且无指纹基准（磁盘仍旧格式，保存前必须提示）。
- `src/scene_io/mod.rs`：删除 `SceneDirtyState`；`is_scene_dirty()` 统一为读 active tab 的 `dirty`
  （单轨真源）。消费方 `src/status_bar.rs`、`src/asset_migration.rs` 同步改造。
- `src/scenes/swap.rs::activate_tab`：换栈时同步 per-tab 观察基准（N6）。
- `src/scenes/operators.rs::active_tab_modified`：增长判据换单调 pushes（trim 安全）。

## 红→绿证据（同一测试集，stash src/crates 前后）

红（未修复代码，`loop/reports/t03t1-red-run.log`，13 失败/9 通过）：
- R2 零记录：`numeric_transform_undo::a_numeric_move_is_one_entry...` 「left: 0, right: 1」；
  多选 `a_numeric_move_over_a_multi_selection` 「left: 2, right: 3」；
  保存丢移动：`a_numeric_move_survives_save_and_reload`——保存文件中无 translation 字段。
- R1：`delete_then_undo_restores_exactly_one_keyframe`——despawn 后文档仍有关键帧（left 1 right 0）；
  `a_deleted_keyframe_stays_dead_through_a_document_undo`——文档 respawn 复活已删关键帧；
  `toggle_keyframe_is_one_entry_and_undoes`——toggle 零记录（left 0 right 1，N3）。
- 脏标记矩阵红格：case 3 / 5 / 6 / 7 / 12 / 13 / 14（详见下表）。

绿（修复后，`loop/reports/t03t1-green-run.log` 与 `t03t1-guards-full.log`）：
`cargo test -p jackdaw --test guards` 全量 **123 passed / 0 failed / 0 ignored**（含 3 个新文件 22 个
用例 + 既有全部 guards 用例 + 启用的既有 ignore 测试）。

## 脏标记 14 用例矩阵（§4.3 逐格）

| # | 用例 | 位置 | 红 | 绿 |
|---|---|---|---|---|
| 1 | 打开无操作 → clean | tests/guards/dirty_matrix.rs | - | PASS |
| 2 | 一次编辑 → dirty | dirty_matrix.rs | - | PASS |
| 3 | 编辑→undo 回保存内容 → clean | dirty_matrix.rs | RED | PASS |
| 4 | 编辑→undo→redo → dirty | dirty_matrix.rs | - | PASS |
| 5 | 保存→undo → dirty+提示 | dirty_matrix.rs | RED | PASS |
| 6 | 保存→undo→redo → clean | dirty_matrix.rs | RED* | PASS |
| 7 | 编辑A→保存→undo→编辑B → dirty | dirty_matrix.rs | RED | PASS |
| 8 | 编辑→保存 → clean | dirty_matrix.rs | - | PASS |
| 9 | scrub 一整个手势 → dirty 且恰 +1 | src/commands.rs（手势会话机器可达处） | - | PASS |
| 10 | modal Esc 取消 → 栈/脏/文档不变 | dirty_matrix.rs（自建 allows_undo modal + cancel 恢复，契约缩影） | - | PASS |
| 11 | X+数字+Esc → 无记录无脏 | dirty_matrix.rs | - | PASS |
| 12 | Duplicate→undo → 复制品消失+脏回落 | dirty_matrix.rs（经 `entity.duplicate` 操作符派发，即 Y2 修后右键将走的路径） | RED | PASS |
| 13 | tab A 脏→切 B→回 A | dirty_matrix.rs | RED | PASS |
| 14 | 资源字段→undo → 值回滚+clean | dirty_matrix.rs（按裁决③默认：编辑本身置脏维持现状；undo 后文档未变按统一语义 clean） | RED | PASS |

\* case 6 旧代码红是双轨分歧的另一面：watcher 在 undo 帧把 recorded 深度降到 0，redo 增长被误判为新编辑。

## 门禁（全部通过）

| 门 | 命令 | 结果 | 日志 |
|---|---|---|---|
| fmt | `cargo fmt --all -- --check` | exit 0 | loop/reports/gate-fmt-t03t1.log |
| clippy（权威口径） | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | exit 0 | loop/reports/gate-clippy-t03t1.log |
| xtask fast | `cargo xtask fast` | exit 0（2866 lib tests passed, 2 skipped） | loop/reports/gate-xtask-fast-t03t1.log |
| xtask integration | `cargo xtask integration` | exit 0（5059 tests: 5057 passed, 2 skipped, 0 failed） | loop/reports/gate-xtask-integration-t03t1.log |

guards 全量（123/123）：loop/reports/t03t1-guards-full.log；红/绿运行：t03t1-red-run.log / t03t1-green-run.log。

## 偏差与说明（concerns）

1. **watcher 架构自纠**：第一版把 watcher 写成 exclusive 系统（`&mut World` 直接 emit），xtask
   integration 暴露 `controls::ui_probe_click::a_ui_click_refuses_what_it_cannot_honestly_click` 失败
   （main 上通过）。实证（探针日志已复核）：exclusive 系统重塑 Update 调度后，测试排队的合成点击手势
   在 play() 内被投递 → `RefreshOperatorButtons` → availability driver（core_extension.rs，按设计
   「拥有」operator 按钮的 InteractionDisabled）把测试手工禁用的按钮重新启用。已回退为**非 exclusive**
   签名（指纹比对走 Commands 闭包），并把该测试的 disabled 按钮改为不挂 `ButtonOperatorCall`（结构上
   免疫 driver，测试意图不变）。这也再次确认 driver 语义：**operator 按钮的禁用态必须由 operator 可用性
   驱动，手工 InteractionDisabled 会被摘除**。
2. **load 基准补点**：方案列的 load.rs:438 写点实际不在 `scene.open` 主路径上（`open_read_scene` 自建
   tab），已在 `open_read_scene` 尾部补 per-tab 基准；并发现方案未列的写点
   `scenes/external_watch.rs::adopt_reloaded_document` 与 `scenes/operators.rs::active_tab_modified`，
   一并改造。LOD 升级打开的 tab 保持 dirty=true（磁盘仍旧格式），`lod_upgrade` 既有测试因此保绿。
3. **启用既有 ignore 测试**：`tests/guards/undo_history.rs::undoing_back_to_the_saved_scene_leaves_the_tab_clean`
   原 `#[ignore = "a tab is marked dirty when its history grows and undo never clears it"]`——正是 N5 语义，
   修复后移除 ignore 并通过。
4. **N2 brush 分支的红未能独立复现**：未修复代码上 brush 分支的恰一条断言已通过（推测 undo 快照的
   document capture 读取路径已覆盖 ECS 侧 Brush 值）；内联 brush 同步作为防御性修复保留，且断言
   （恰一条 + undo 文本回滚 + 置脏）在修复前后均绿。
5. **任务 2 边界**：Y1/Y2/Y4 修复、`jackdaw/history` BRP 工具、真机 3 链、buglist 打钩均未触碰；
   `buglist.md` 与 `loop/` 未入库（.gitignore 的 `.mimosa/` 行为前会话遗留，亦不入本次提交）。
6. case 12 以 `entity.duplicate` 操作符派发验证（右键菜单改派发同一操作符是任务 2 的 Y2 内容）。
