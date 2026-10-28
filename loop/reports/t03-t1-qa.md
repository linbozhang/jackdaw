# T03 任务 1 QA 验收报告（数据完整性与脏标记）

QA 独立验收，commit `b9a8842d`（`loop/t03-undo`，基于 main `4a9f331e`，34 文件）。
口径：`loop/plans/t03-undo-hardening.md` 任务 1 节 + 裁定①（R2=方案 A 统一框架快照）②（N4/N5=完整指纹方案）。

## VERDICT: PASS

## 门禁（QA 全部独立重跑）

| 门 | 命令 | 结果 | 日志 |
|---|---|---|---|
| fmt | `cargo fmt --all -- --check` | exit 0 | gate-fmt-t03t1-qa.log |
| clippy（权威口径） | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | exit 0 | gate-clippy-t03t1-qa.log |
| xtask fast | `cargo xtask fast` | exit 0 | gate-xtask-fast-t03t1-qa.log |
| xtask integration | `cargo xtask integration` | exit 0 | gate-xtask-integration-t03t1-qa.log |

## 代码审查

### R2（numeric_transform，含 N2）— 通过
- Object 分支：`plan_object` 纯读产 `(entity, old, new)` 计划，queued command 逐个 `SetTransform::execute`
  （`src/commands.rs:365-376`：ECS 写 + `sync_component_to_ast`，不 push）——全部变化进框架 after 快照，多选同一条。
  **时序已核实**：`crates/jackdaw_api_internal/src/operator.rs:661-688`，`run_system_with` 在系统收尾 apply
  deferred commands，`save_history` 的 after capture 在其后——queued 写入必入 diff。
- BrushEdit 分支：`apply_sub_elements` 后 queued `run_system_cached(sync_changed_brushes_to_ast)`
  （`src/brush/mod.rs` 提为 pub(crate)），防御语义成立。
- 三症状断言齐：`tests/guards/numeric_transform_undo.rs` 4 测试（恰一条 / undo 值回滚+文档回滚 /
  **存盘文件含移动 + reload 往返** / 多选恰一条）。

### R1（关键帧四命令 + N3 toggle）— 通过
- `DespawnKeyframeCmd::execute` 与 `SpawnKeyframeCmd::undo` → `despawn_scene_entity`
  （`src/commands.rs:1274`：`delete_entity_from_ast` + despawn，只删实体本身不递归，keyframe 为叶子安全）；
  `DespawnKeyframeCmd::undo` 与 `SpawnKeyframeCmd::execute` spawn 后同步 `register_entity_in_ast`
  （`src/scene_io/registration.rs:10`：死实体守卫 / 已注册幂等 / mint SceneNodeId / parent 需在 doc）。
- Update watcher `register_animation_entities_in_ast`（`src/lib.rs:2110`）经同一幂等函数，不会对同步注册的
  实体二次 mint——重复关键帧根因消除。
- relive/字段捕获/`ChildOf` 设计保留（`src/lib.rs:1165-1181` 未动语义）。
- `tests/guards/keyframe_undo.rs` 4 测试含「删除经文档 undo 不复活」「toggle 恰一条且撤净」。

### 脏标记（N4/N5/N6/N7，裁定②完整方案）— 通过
- per-tab 四字段：`observed_undo_len`/`observed_pushes`（观察基准）+ `saved_undo_len`/`saved_doc_hash`（保存点）。
- **指纹时机与开销**：快路径 `(len,pushes)` 均不变 O(1) 返回；仅「有变化且 len==saved_undo_len」的迁移帧经
  queued command emit 一次（`src/scenes/mod.rs::mark_active_dirty_on_history_growth`）——不是每次 push，
  稳态成本符合方案 §4.2-3 预算。
- **同源性**：scene 分支保存 hash 与 watcher 比对均出自 `emit_bsn_scene_for_file`（stamp 仅写盘包装，
  `save.rs` 注释明言 in-memory emit 无 stamp）；prefab 分支两侧均 `emit_bsn_scene_with_inline_assets`。
- **竞态**：指纹在 queued 闭包（帧 sync 点）执行；若同帧后续系统再改栈长，最多一帧中间值，下帧 watcher
  以新 observed 重判——最终一致，无持续错判。闭包内重验 `tabs.len() <= active` 防关 tab 越界。
- 写点全改 per-tab：save 两分支、finish_load_scene、open_read_scene（升级打开保持 dirty=true 且无指纹）、
  save_scene_as_prefab、adopt_reloaded_document、activate_tab（N6：观察基准随目标 tab 自身栈）。
- N7：`active_tab_modified` 与 watcher 增长判据均换单调 `total_pushes()`（`jackdaw_commands/lib.rs:185`，
  trim/undo/redo 不回拨，语义正确）。
- 单轨：`SceneDirtyState` 删除，`is_scene_dirty` = active tab.dirty（消费方 `asset_migration.rs:87`、
  status_bar 改造齐）；全仓无旧字段代码残留。
- ui_probe_click 偏差①：watcher 保持非 exclusive（Res/ResMut/Commands），Update 注册处无调度残留；
  测试「结构免疫」改造**保义**——disabled 按钮拒收意图的断言仍在（`InteractionDisabled` + ui_click 拒绝），
  只是把按钮从 operator 按钮换为普通按钮（operator 按钮的禁用态由可用性 driver 拥有、手工 disabled 会被
  摘除——产品语义正确，改造顺带将其文档化）。

### N2 concern 评估
分支现有断言（恰一条 + 文档变化 + 置脏 + undo 回滚）**可证伪**：brush 分支若回归零记录会红。但修复的
必要性未获独立红证实（程序 stash 修复代码时 brush 断言已绿；推测 undo 快照的 document capture 读取路径
已覆盖 ECS 侧 Brush 值）。防御保留无破坏，记 ⚪。

### 矩阵抽查（case 5/7/13）与边界
- case 5（保存→undo dirty+提示）、case 7（编辑A→保存→undo→编辑B：显式断言 depth==saved 且 dirty——反
  假阴性）、case 13（N6：B clean 且 is_scene_dirty 读 B 不读 A）：断言实、路径经 `run_op_clause_as_user` 按键级派发。
- case 10 为自建 modal 契约缩影（报告已如实标注），可接受。
- **无任务 2 越界**：diff 无 hierarchy.rs / entity_ops.rs / transform_ops.rs / remote/server.rs；
  `jackdaw/history` BRP 未注册（已核 `src/remote/server.rs:147-166` 方法清单）。
- `buglist.md` 未入库（untracked；`git diff main..loop/t03-undo` 无 buglist、无 .gitignore）。

## 真机抽验（QA 自备脚本 `loop/reports/t03t1-qa-live.ps1`，日志 `t03t1-qa-live.log`，14/14 PASS）

链①（R2+指纹）：预置 zone.bsn → scene.open → ui_click outliner 选中 Zone（真实点击链）→ save（clean）
→ `input.key` KeyX/Digit1/Enter 全键盘链 → x=1 且 dirty 亮 → undo 一次 x=0 且 **dirty 灭**（指纹 clean 语义）
→ 第二次 undo 无操作（**恰一条**的对外证明）→ redo x=1 且 dirty 亮。
链②（N4 核心）：save → dirty 灭且**磁盘文件含 x:1**（R2 保存丢失症状消除）→ undo → x=0 且 **dirty 亮**
（关 tab 必提示）。

## 问题统计

| 级别 | 条目 |
|---|---|
| 🔴 严重 | 0 |
| 🟡 中等 | 0 |
| ⚪ 轻微 | 3（见下） |

1. ⚪ [程序] N2 brush 分支修复必要性未获独立红证实（断言在位可防回归，防御保留无破坏；程序报告已如实披露）。
2. ⚪ [程序] `tests/prefabs/prefab_lifecycle.rs:1993` 注释仍引用已删除字段名 `undo_len_at_save`（代码无残留，仅文案过时）。
3. ⚪ [程序] `scenes/external_watch.rs::adopt_reloaded_document` 对非活动 tab 不写指纹基准（退化为增长判脏）；该 tab 栈刚清空无可 undo，实际影响趋零，代码注释已说明取舍。

正向：偏差①处置正确（exclusive 回退彻底 + 测试免疫改造保义 + driver 语义文档化）；指纹 emit 成本严格限定在
迁移点帧；R1 同步注册与 watcher 幂等双保险。

## 结论

门禁 4/4 绿（QA 独立重跑）、红→绿证据链完整（13 红→123 绿，QA 复核关键断言）、真机两链 14/14 PASS、
无越界无入库违规。**T03 任务 1 验收 PASS**，可进任务 2（Y 类 + `jackdaw/history` 工具 + 真机 3 链）。
