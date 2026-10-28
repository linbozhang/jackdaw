# T06-T2 实施报告：「Stop 还原加固与优雅停止」

> 程序角色产出，2026-10-26。分支 `loop/t06-stop-restore`（自 main `fd37a79e` 拉出，即 T1 合入点）。
> 规格：`loop/plans/t06-play-isolation.md` §二 T2（决策 4/5 已按裁定实施）。
> 提交信息：`Restore the edit state on stop and stop the game gracefully`。
> 提交哈希：见文末。

## 一、改动面（简报 5 项 + QA 吸收 2 项）

| # | 项 | 落点 |
|---|---|---|
| 1 | **Y34 优雅停止** | `src/pie.rs`：`ChildStage::Live` 增 `stop_deadline: Option<Instant>`；常量 `GRACEFUL_STOP_DEADLINE = 2s`；`stop_instance`/`handle_stop` 对 Live 子进程发 `Stop` 后**不 kill**、放回 children 带 deadline（早 arm 的更早 deadline 保留，`min` 语义）；`advance_child` 的 Live 分支：期限内自退→优雅 reap（success 日志）、到期→`kill()+wait()` **恰一次**（stage 随调用 drop，类型上不存在二次）；Connecting 路径维持立即 kill（未连上无优雅可言）；`handle_reload` 走新增 `force_stop_all`（= 原立即 kill 行为，注释注明 reload 语义=重建会话）；PlayState 回 Stopped 由 children 清空驱动（reconcile），stop prompt 因此最迟 deadline 后到达——方案决策 5-A 逐条落地 |
| 2 | **W26 降级** | `src/pie.rs::pie_windows`：`PIE_JOB: LazyLock<Option<Job>>`——`CreateJobObjectW` 空句柄 / `SetInformationJobObject` 失败 → `warn!`（含 GetLastError）+ `None`；`assign_to_process` 失败 → `warn!` 继续（游戏照跑，仅失去随编辑器死保障）；调用点 `if let Some(job) = PIE_JOB.as_ref()`。三处 `assert!` 全消 |
| 3 | **W17 守卫** | `src/inspector/val_field.rs::commit_val_to_field`：开头补 `is_resource_entity` 分流（照 `reflect_fields.rs::apply_field_value_live` 的形状）——tick→`resource_field_preview`（写资源自身 live ECS）、commit→`resource_field_commit`（恰一条 ResourceSetField undo），不再落入 selection 文档管线 / PIE live 流。实测定性：旧路径的真实缺陷是**资源 Val 字段 tick 连资源自身值都不写**（`stale_bound_entity` 守卫恰好挡住了跨目标写盘的灾难分支），修复后资源 Val 编辑全通 |
| 4 | **❓selection 还原** | **实测不实锤，机制已对，不修（按方案预案记档）**：Stop 链 = `revert_preview` → `respawn_scene_from_ast`（capture→clear→activate），`activate_tab` → `apply_view_state` 已按 `ViewState.selection`（SceneNodeId 集）在 respawn 后的新实体 id 上重建 `Selection` 资源与 `Selected` 标记（死句柄被 `filter_map(nid_map)` 过滤）。guards 新增 4 例钉死防回归（含「authored 实体被 reparent 到 ephemeral 下 + Live 选中 ephemeral」的最恶劣构造） |
| 5 | **验收句③旁路审计** | 见 §四。结论：Play 期间写 authored 文档/盘上场景文件的路径闭集 = 六个显式门；投影/journal/temp/settings 均不在集内 |
| 6 | **N-QA1 换把跨帧**（QA 🟡①） | `crates/jackdaw_runtime/src/lib.rs::apply_pie_scene_override` 增 `Local<bool> swapped`——换把一次/进程，运行期后续帧新增的 root（流式加载、玩法二场景）保持其自载场景，与注释语义一致；跨帧用例入 `pie_scene_override.rs` |
| 7 | **N-QA4 journal 衔接**（QA 🟡②） | guards `stop_restore.rs::a_save_before_play_spends_the_journal_entry`（dirty→journal 有条目→save→条目出局）+ 真机 kill-重启链（§三 case 4）双侧 |

新增测试载体：`src/pie.rs::graceful_stop_tests`（5 例）、`src/inspector/val_field.rs::val_resource_guard_tests`（2 例）、`tests/guards/stop_restore.rs`（4 例）、`crates/jackdaw_runtime/tests/pie_scene_override.rs` +1 例（跨帧）。

## 二、🔴 红 → 绿（全部 stash 复演或等价旧行为复演）

| 项 | 红（旧码/旧行为） | 绿 |
|---|---|---|
| N-QA1 | `cargo test -p jackdaw_runtime --test pie_scene_override`（stash 掉 lib.rs 改动）→ **4 passed / 1 failed**：`a_root_added_while_running_keeps_its_own_scene` panic——旧实现按帧 Added 判「首个」，运行期新增 root 被二次换把。日志 `loop/t06t2_nqa1_red.log` | **5 passed / 0 failed**（`loop/t06t2_nqa1_green.log`） |
| Y34 | handle_stop 临时复演为旧立即-kill 体 → `graceful_stop_tests` **4 passed / 1 failed**：`handle_stop_arms_the_window_and_waits_for_the_reap`（children 已空、deadline 无从谈起）。日志 `loop/t06t2_y34_red.log` | **5 passed / 0 failed**（期限内保留 / 自退优雅 reap / 超时 kill 恰一次 / handle_stop 留窗+早 deadline 保留 / force_stop_all 立即清）。`loop/t06t2_y34_green.log` |
| W17 | 守卫临时摘除（`if false &&`）→ **0 passed / 2 failed**：两用例 panic 于 `commands.rs:87`（旧路径踩进 selection 文档管线的资源查询）。日志 `loop/t06t2_w17_red.log` | **2 passed / 0 failed**（tick 预览写资源自身 / commit 恰一条 undo 且 undo 回原值）。`loop/t06t2_w17_run4.log` |
| ❓selection | 无红可复演（不实锤）——guards 4 例作为回归锚 | guards `stop_restore` **4 passed / 0 failed** |

## 三、真机铁证链（`loop/qa/t06-stop-restore.ps1`，run10 = `T06T2_STOP_RESTORE_LIVE_PASS`）

fixture：`t06-spin.bsn`（`my_game::SpinningCube{speed:2}` 自转实体 + 静态实体，零源码改动的存量工程）+ `t06-big.bsn`（500 实体）+ 隔离 CONFIG_DIR + 1920x1080 窗口。证据通道：BRP（status/scene_bsn/scene_tree/entity/history）+ 盘上 SHA + 进程枚举 + 截图留档 `loop/t06t2-live/`。

| 用例 | 断言与结果 |
|---|---|
| **case 1 铁证链（验收句②）** | open→save→记基线（盘 SHA / emit SHA / history=0 / dirty=false / 实体名集）→ play_current → Live 视图下 **Spinner 的投影文档两次采样在动**（运行态修改流实锤，rotation 值变化）→ 切回 Scene → stop（**0.3s 优雅落地**）→ 断言全过：盘上文件 SHA 逐字节一致、emitter 输出 SHA 逐字节一致、history 深度不变、dirty 不变、实体名集精确复原、temp 副本零残留。ChildOf 悬空 WARN 每会话 1 条（见偏差⑥） |
| **case 4 W26 kill 链** | Play 运行中找到子进程 `my-game.exe` → `Stop-Process -Force` 硬杀编辑器 → 3s 后游戏进程已死（**job object 生效**）→ **N-QA4**：save 过的场景在 kill-重启后 recovery 无 journal 条目可读（journal 目录 0 个含 t06-spin 的条目——文件就是恢复源）→ 预置孤儿 `current-untitled-9-99999.bsn` → 重启打开项目 → **孤儿被清扫** |
| **case 5 大场景** | 500 实体场景 play→running→stop：**2.2s 内 status 落 stopped**（deadline 2s + 1s slack 内）；且 2.2s > 2s 本身即 **deadline 硬上限分支的真机实证**（该游戏进程未在期限内自退，`advance_child` 的 kill 恰一次路径收尾）。实体复原抽查通过 |

**截图**：`1-live-spinning.png`（Live 投影在动）等留档于 `loop/t06t2-live/`。

## 四、验收句③旁路审计（代码审查结论）

Play 运行期间，编辑器侧会写 authored 文档 / 盘上场景文件的路径**闭集**（逐入口核实）：

1. `save_scene_inner`（T03/T04 原子保存边界，唯一写盘方）——上游全部显式：`scene.save`/Ctrl+S、`scene.save_all`（含退出确认链）、**Play 前保存策略（Save 态，T1 三态允许集）**、恢复对话框保存；
2. `Save to Scene`（Path A/B promote，`pie.rs`）与 **Live Changes Apply All / Stop prompt Apply**（`live_edits.rs`，pending live edit 的显式门）；
3. 其余写入面均**不在集内**：journal（state 目录，非场景文件，且 save 后条目出局=N-QA4）、`.jackdaw-pie` temp 副本（运行副本非 authored 文档）、settings.json/project.json（设置）、terrain sidecar（随 1 的门）、.bak/tmp（1 的内部产物）；
4. **投影写 preview ECS 不入集的证据**：`pie_projection.rs` 对 world 的全部写为 `entity_mut().insert(...)`/`spawn`/`despawn`（overlay 实体 + `PieEphemeral`），全文件无 `resource_mut::<SceneBsnAst>()`；authored 读取经 `deep_clone()` + `suspend_preview_writes`；模块文档明言 "the authored scene is never mutated"。真机兜底：case 1 全链双 SHA 双腿一致。

## 五、❓selection 与 ChildOf WARN 定性

- **selection：不实锤**。Stop 链复用 tab 激活的 view-state 重建（`apply_view_state` 按 SceneNodeId 映射 respawn 后新 id，`Selection`/`Selected` 双侧重建，悬空句柄被过滤）。guards 最恶劣构造（authored 被挂到 ephemeral 下 + Live 选中游戏私有实体）下 Stop 后：无悬空句柄、authored 选择按 node id 复原、ephemeral 选择随实体消亡（合理语义）。
- **ChildOf 悬空 WARN**：真机每会话 1 条（`bevy_ecs::relationship`：ChildOf 指向已不存在实体后自动移除），来自 `clear_projection` despawn ephemeral 的同帧时序；headless 复现不出（guards 无此输出），实体集/selection/文档/dirty 全部断言不受影响。定性：**无害噪音，非数据缺陷**；若后续要消音（detach 顺序收紧），归 T3 矩阵 #6 终验时顺手评估。

## 六、门禁（quick 四门亲跑 + 日志全文复核 + 覆盖归档）

| 门 | 结果 | 日志 |
|---|---|---|
| `cargo fmt --all -- --check` | PASS（0 diff） | `loop/t06t2_fmt.log` |
| `cargo clippy --workspace -- -D warnings` | PASS；全文复核仅 5 条既有工具链噪音（rust-lld 参数 ×1、build script duplicate ×4），无 error 无新增 | `loop/t06t2_clippy.log` |
| `cargo test --workspace --lib` | **56 crates / 2900 passed / 0 failed**（+7：graceful_stop 5、val_resource_guard 2） | `loop/t06t2_lib.log` |
| 集成：`--test guards` 全量 + `--test pie_scene_override` | guards **196 passed / 0 failed**（+4 stop_restore；runtime override **5/5**） | `loop/t06t2_guards_full.log`、`loop/t06t2_runtime_override.log` |

**门禁过程中的一个真实问题与修复（续 T1 的同类教训）**：journal 计时测试（5ms 预算）在全量并行下再次超限（6.8ms）——T1 的「模块内串行锁」不够，因为 `stop_restore` 新增的重型用例与 journal 模块**跨模块并行**。治本：`tests/guards/main.rs` 增二进制级 `HEAVY_EDITOR_LOCK`，两个编辑器启动型模块（play_current_scene、stop_restore）与 journal 计时测试**本人**全部挂同一把锁——该测试在 T04 时期本就是独立测试进程（天然独占机器），合并 binary 后并行邻居破坏了它预算设定的环境，挂锁恢复了独占语义（测试内注释说明）。修复后全量 196/0 稳定。

## 七、偏差与记档

1. **显式门 UI 级真机链未跑（工具面缺口，非产品缺口）**：Inspector 拖拽→stop prompt→Discard/Apply All 按钮的链路需要「选中投影实体」，三次探针证明现有 QA 面做不到——outliner 的 Live 行不出现在 `ui_tree`、viewport 点击 pick 不中投影实体、无 `selection.set` 方法（`loop/t06t2_probe_outliner.log`、`t06t2_probe_select2.log`）。按 MCP 优先原则记档归 **T3**：`jackdaw/pie` companion 落地时补 `selection.set`（或 live-edit 注入面）后完成矩阵 #7。语义覆盖不缺：headless `live_edits.rs` 既有 `apply_all_groups_into_one_history_entry_and_clears` / `discard_all_clears_without_touching_ast` / `post_stop_apply_writes_via_node_id`；真机「运行态修改不写回」由 case 1 的 Spinner 流动 vs 双 SHA 铁证承担。
2. **W26 降级分支**：真机模拟受限环境不可行（如实记档）——以「三处 assert 全消」的结构保证 + 失败路径均为 `warn!`+继续的代码审查覆盖；正常路径（job object 生效）真机回归通过。
3. **bevy 原生 BRP 与 jackdaw 方法实体面互不相通**（world.get_components 用 `{index}v{generation}` 且其 world 视图不含 scene_tree 报告的实体）：真机读组件值改走 `jackdaw/entity`（节点 BSN 文本）。记档给 T3 工具设计（统一断言通道的动机之一）。
4. **大场景 stop 2.2s**：> 2s deadline 本身即 Y34 超时分支的真机实证（游戏未自退、kill 硬上限收尾）；验收口径 deadline+1s 内达标。
5. Stop prompt 出现时机随优雅窗口推迟到 reap 完成（children 清空触发 OnEnter(Stopped)），最迟 deadline 后一帧——决策 5-A 预期行为；真机链 stop 无 pending live edit 时无 prompt，符合语义。
6. ChildOf WARN 定性见 §五（无害时序噪音，记档观察）。
7. buglist Y34/W26/W17 已打钩并附修复说明（buglist.md 不入库，打钩供用户侧台账）。

## 八、提交

- 分支：`loop/t06-stop-restore`（父 `fd37a79e` = main）
- 文件：`src/pie.rs`（Y34/W26 + graceful_stop_tests）、`src/inspector/val_field.rs`（W17 + 测试）、`src/inspector/resource_commands.rs`（`live_resource_entity` pub(crate) 供测试）、`crates/jackdaw_runtime/src/lib.rs`（N-QA1）、`crates/jackdaw_runtime/tests/pie_scene_override.rs`（跨帧用例）、`tests/guards/main.rs` + `tests/guards/stop_restore.rs`（新）
- 提交信息：`Restore the edit state on stop and stop the game gracefully`
- 哈希：`af93e730`（父 `fd37a79e` = main；未推远端；9 文件 +893/-41）
- loop/ 与 buglist.md 不入库；QA fixture（t06-spin/t06-big 及 .bak）已从 my-game 清理。
