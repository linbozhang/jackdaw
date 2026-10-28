# T08-T2 实施报告：作者态生命周期保护（P1 第二棒）

> 任务：`loop/plans/t08-game-params.md` §二 T2（P4+P5+W13；决策 3-A/4-A 已裁）。
> 分支 `loop/t08-lifecycle`（自 main 211092ec 拉出），提交 **d213f627**
> `Protect authored asset edits across play, export and exit`（12 文件 +457/−38）。未 push，未合入（待 QA）。

## 一、交付

### 1. 决策 4-A：脏标隔离（P5）

- **`EditorCommand::touches_scene_document()`**（`crates/jackdaw_commands/src/lib.rs`，默认 `true`——既有命令零改动；`CommandGroup` 覆写为任一子命令 touches（混组偏保守=朝脏）。
- **`CommandHistory::scene_pushes`**（新增过滤计数器：只计 touches 命令（`count_push` 在 execute/push_executed 两入口计（`total_pushes` 原语义不动（旧消费者零改动——方案风险缓解兑现。
- **四个非场景命令覆写 false**：`SetDefinitionField`（definition_assets.rs）+ `ResourceInsert/Remove/SetField`（resource_commands.rs）。
- **两个判脏点 + 两处基线记录改用 scene_pushes**：`active_tab_modified`（operators.rs）、per-tab watcher `mark_active_dirty_on_history_growth`（scenes/mod.rs）、`observe_history`、save/swap 的基线记录（operators.rs:565 / swap.rs:287）。`SceneTab::observed_pushes` 字段语义更新为 scene 计数（doc 注明，无结构变更）。
- **效果**：资产字段/会话资源编辑共享 undo 栈（Ctrl+Z 可撤）但**不再把场景 tab 弄脏**。

### 2. 决策 3-A 三腿（P4）

- **① Play/导出前保存腿**：`save_scenes_before_launch`（pie.rs）在场景保存后追加 `save_dirty_assets(world)`（definition_assets.rs 新 pub 函数：遍历全部 dirty `DefinitionAssetEdit` 卡 → `save_indexed_asset` 写盘 → 失败收集名字）——失败并入 failures 拒绝启动（文案 `Not {action}: could not save <names>`）。**Play 链与导出链两调用方免费受益**（同函数）。journal 不扩（决策 3 既定裁定，见 §五）。
- **② 退出对话框**：`intercept_window_close` 触发条件扩为「dirty tab **或** dirty 资产卡」（Query DefinitionAssetEdit）；`spawn_confirm_quit_dialog` 文案对 dirty 资产追加一行「Unsaved assets: <names>」；**SaveAll 处理器**在场景全存后追加 `save_dirty_assets`（资产保存失败与场景失败同语义：取消离开+警告+报告；DiscardAll/Cancel 语义不变）。
- **③ journal 边界**：按决策 3 裁定不做（crash journal 是 per-tab 场景文档结构，扩资产=结构变更风险>收益；退出对话框+启动前保存已覆盖主要丢失面）——book 记录归 T3。

### 3. W13：三档通知

`StatusNotice` 持 `NoticeLevel::{Info,Warning,Error}`（新增 pub enum）；`notify_info/notify_warn/notify_error` 各达其档；渲染映射 info→TEXT_SECONDARY / warning→TEXT_WARNING / error→TEXT_ERROR（修前非 error 一律 warning 色、warn 与 info 同实现）。本任务所有保存失败提示走真警告档。

### 4. scene_snapshot 调查（QA 移交）——已修

**定性结论**：`jackdaw/scene_snapshot` 原是**游戏侧方法**（`jackdaw_remote` crate 注册进 PIE 游戏进程的 BRP），**编辑器端口（15703）从未注册过它**——T1 真机对编辑器调用返回 null 的根因即此（与「视图态」无关；QA 的 Live 视图线索适用于编辑器侧投影镜像，但快照方法压根不在编辑器方法表）。
**修复**：编辑器 `server.rs` 注册同名方法（复用 `jackdaw_remote::scene_snapshot::scene_snapshot_handler`，读编辑器主世界 Transform 实体——含 PIE 投影镜像）。**真机铁证**：注册后 `scene_snapshot` 返回 **18→54 个实体**（T1 时恒 null）——T1 遗留的行为断言通道补齐（`moved` 判定在 my-game 无动画实体下属预期 False，通道本身已通，QA 可在含 FallingCube 的工程上直接复跑 T1 脚本）。

## 二、红→绿

| 项 | 红证 | 绿证 |
|---|---|---|
| **P5 脏标隔离** | **回退模拟红**（分支上把 watcher 临时改回 `total_pushes()` 跑新用例 → `an_asset_field_edit_does_not_dirty_the_scene_tab` **FAILED**（tab 被资产 push 弄脏）→ 还原后绿） | guards 3/3（push 后 scene_pushes==0、tab 干净、undo 槽在） |
| **P4 保存腿** | 结构红（main 无 `save_dirty_assets`，测试编译不过——红形态=编译红）+ 行为红（pie 接线测试：链上 dirty 卡使启动拒绝，main 无此拒绝） | guards「卡值落盘」+「失败上报+卡保持 dirty」；pie.rs `save_before_launch_tests`（Err 含 action 与资产名） |
| **P4 退出腿** | 结构红（main 触发条件不含资产卡） | 代码审查+SaveAll 处理器接线（对话族群 T04 已验，条件与文案扩展） |
| **W13** | 代码层红（buglist 原文：warn/info 同实现、TEXT_WARNING 死分支——main 源码事实） | `notices_carry_their_level`（三档各自正确） |
| commands 计数 | — | `non_scene_commands_share_the_history_without_counting_as_scene_pushes`（总数/场景数分离） |

## 三、真机（`loop/qa/t08-lifecycle.ps1`，my-game，日志 `loop/t08t2_live.log`）

- **Leg A（N10 前科区组合回归）PASS**：dirty 资产卡（material 卡 set 0.75 未保存）+ named 场景 Save 态 + `pie.play_current` → **编辑器全程存活无冻结**、play running、stop 归位，且**盘上资产文件被启动链写入 `perceptual_roughness: 0.75`**（pre-play 无值 → post-play 有值）。
- **Leg B（T07 导出链）PASS（语义证据）**：`game.export` 的 staging 拷贝含 `t08-lifecycle.bsn` 且带卡片值 0.75——**发布包携带编辑器所跑的值**（三态一致的导出腿）；release 构建未在轮询窗口内完成（state=building，构建 20+ 分钟超脚本等待），staged 文件已就位证明 staging 阶段完成了保存链+拷贝。**注意**：run2/run3 初轮 FAIL 的主因是脚本用 untitled 场景——`play_current` 对 untitled 走 scene-only 保存分支（`pie_current.rs` 的 named/untitled 分叉），**named 场景才走含资产腿的链**——脚本修正后通过；此分叉语义本身正确（untitled 场景跑的是 temp 副本，其资产腿语义归 T3 矩阵评审，报告记档）。
- **Leg C（scene_snapshot 修复）PASS**：编辑器端口返回 18/54 实体（修前恒 null）。

## 四、门禁（quick 四门，全文复核+归档 `loop/t08t2_*`）

| 门 | 结果 |
|---|---|
| fmt | clean |
| clippy workspace all-targets `-D warnings` | **exit 0** |
| 单测 | 主 crate lib **1171**；guards **202**（dirty_matrix 14 格全量零退化 + asset_lifecycle 3 新 + config_injection 2）；commands **16**（+1 新） |
| 集成 | guards 全量 50.2s 绿 |

## 五、偏差与记档

1. **untitled 场景的 Play 保存分叉**：`play_current` 对 untitled 场景走 `save_modified_scenes`（不含资产腿，`pie_current.rs:283-293`）——设计上 untitled 跑 temp 副本、场景不落盘；**dirty 资产卡在此分支不自动保存**（发现于真机 run1/2）。属边界语义而非缺陷（temp 副本路径的资产即 assets 正本，卡未保存=跑盘上值=与 named 路径不同的既定语义），**T3 矩阵格 5（Play 中编辑未保存）会正面覆盖**；如主控认为 untitled+Play 也应保存卡，一行可加（记待裁）。
2. **P4/W13 红证形态**：P4 两腿为结构红+行为红（接线测试），非 main 上可跑的完整红绿（stash 验证因测试引用新 API 编译不过而不可行，T3 教训）；P5 有回退模拟红（真红实证）。如实记档。
3. **真机 release 导出全程**未在窗口内完成（Leg B 以 staging 阶段证据放行；构建完成态由 T3 矩阵格 7 终验）。
4. **journal 边界**（决策 3 附带裁定）：不扩，T3 book 记录。
5. guards 保存用例的失败注入用「index 无该 path 的卡」（真实代码路径的失败分支）；blocker-directory 注入实测未能挡住 write_atomic（Windows rename 语义），弃用——如实记档。

## 六、buglist 与交接

- **W13 打 `- [x]`** + `> 已修复 d213f627（T08-T2）` 备注（Edit 工具，buglist.md:351）。
- QA 复核建议：①真机复跑 `t08-lifecycle.ps1`（untitled→named 修正版）；②退出对话框 UI 走查（dirty 资产卡+WM_CLOSE，ui_tree 断言文案行）；③T3 前置：`asset.new` 对已存在同名文件拒绝创建（真机观察到的边界，New Asset 应换名或打开既有——现拒绝+警告，语义合理）。

---

# 返工第 1 轮（QA 退回单 1/5 修复）

> 依据：`loop/reports/t08-t2-qa.md`（FAIL，两项必修+两项同性质+一项排查）。提交 **afe4ec41**
> `Keep authored assets out of the scene dirty flags on every path`（15 文件 +211/−14，分支同段）。脚本 `loop/qa/t08-t2-rework-live.ps1`，证据 `loop/t08t2r_*.log`。

## 一、两项必修

### 1. untitled+Save 档 Play 的资产保存腿（QA §七裁定 A）

- **修法**：`pie_current.rs` untitled 分支（else 臂）`failures` 并入 `save_dirty_assets(world)`（QA 建议位置一行）；Copy/PlayUnsavedCopy 档不动（裁定 A 边界）。
- **真机复验（Leg A）**：dirty 资产卡（material 0.44 未保存）+ `scene.new`（untitled 在前）+ 默认 Save 档 `pie.play_current` → play running、stop 归位、**盘上 `t08rw2.bsn` 落盘 `perceptual_roughness: 0.4399999976158142`**（f32 全精度）。首轮一次 False 系卡片建卡时序（无卡可存），聚焦复跑通过。

### 2. QA-1 P5 残留：watcher `Some(_)` 分支在已保存基线 tab 上失效

- **修法**：`SceneTab` 新增 `saved_scene_pushes` 基线（保存×2/载入/恢复/外部重载/预制件保存/退出确认七处基线记录点同步记入或归零）；watcher 离开基线分支由「无条件置脏」收窄为 `(below || scene_pushes > saved_scene_pushes) && !was_dirty`——上探只有场景命令才算文档变化，下探（undo 撤了场景命令）仍置脏。顺带修掉 `recovery_dialog.rs` 恢复路径误用 `total_pushes` 的同性质漏网（QA 未点名）。
- **新用例**（guards `asset_lifecycle.rs`）：
  - `a_saved_scene_stays_clean_when_an_asset_field_edits_the_shared_history`（QA-1 正面；**回退模拟红**：分支临时改回 `!was_dirty` 后 FAILED，还原绿）；
  - `undoing_below_the_saved_baseline_still_marks_the_tab_dirty`（下探保护不回归）。
- **真机复验（Leg B）**：my-game 已保存场景（clean 基线）+ `asset.set` → `jackdaw/history` dirty **before=False after=False**（QA 复现路径直接对拍）。

## 二、同性质补完（QA 记档项 3）

- **动画图域**：`GraphDefEdit`（写独立 `AnimationGraphDoc`）+ `jackdaw_node_graph` 5 命令（`MoveGraphNodesCmd/AddGraphNodeCmd/CreateConnectionCmd/RemoveGraphNodesCmd/RemoveConnectionCmd`，画布数据层镜像进图文档）全部覆写 `touches_scene_document() == false`；用例 `a_graph_edit_does_not_count_as_a_scene_document_push`（graph_doc tests）。
- **QA 清单修正**：`ClipEventEdit`（timeline）经核实**不覆写**——其 spawn/despawn 调 `register_entity_in_ast`，事件实体是场景文档实体（QA §三-1 将其列入漏网系误判，如实记档）。
- `AnimationGraphDoc.dirty` 的保存链/退出保护缺口（P4 同性质）不在本轮：GraphDefEdit 覆写后动画图编辑不再污染场景 tab（P5 面闭环），但其自身文档的 Play 前保存/退出腿是独立工作量，挂 T3 评审。

## 三、QA-3 FallingCube 旋转脱钩——定性+一行修

- **定性**：两个成分——(a) **模板缺陷**：`spawn_falling_cube` 同实体挂 `SpinningCube{1.0}`，`spin_cubes`(1.0)+`falling_cubes`(1.0×ms) 双系统叠加，配置关系被恒定项淹没；(b) QA 轮配置文件疑似未含 move_speed 字段（gravity 腿精确而旋转不动的同文件矛盾支持此判）。**本轮复验**：QA fixture（旧模板）手写**完整两字段** config 后 Play，ms=0.5 实测 **1.504 rad/s = 1.0(spin)+1.0×0.5(fall) 公式精确命中**——注入链在旋转腿同样工作；ms=2.5 档首跑 0.42 系冷启动采样窗口（游戏未跑满，记档；公式已由 0.5 档钉住）。
- **一行修**：模板 `spawn_falling_cube` 去掉 `SpinningCube` 挂载（注释写明双系统叠加陷阱）——新模板角速度 = 1.0×move_speed，干净可断言；T3 矩阵格 4 主断言按 QA 建议用 gravity/dy，旋转腿可在新模板工程复核。

## 四、⚪ 记档不修

PIE stop 关闭打开的资产卡（QA 附带观察 #5，归 T3 评审）；`AnimationGraphDoc` 保存链（见 §二）。

## 五、门禁（返工轮）

| 门 | 结果 |
|---|---|
| fmt | clean |
| clippy workspace all-targets `-D warnings` | **exit 0**（揪出两处测试字面构造缺 `saved_scene_pushes`，补齐后过） |
| 主 crate lib | **1172**（+1 graph_doc 用例） |
| guards | **204** 全绿 |

**dirty_matrix Case 14 期望更新（如实记档）**：`resource_field_edit_undone_rolls_back_and_settles_clean` 的「ruling 3：资源编辑弄脏 tab」旧期望正是决策 4-A 推翻的语义——首轮它全绿**恰因 QA-1 的洞**（`Some(_)` 无条件置脏掩盖了过滤生效）；本轮 QA-1 修复后旧断言暴露失败，更新为「资源编辑不脏 tab、undo 回滚后全程 clean」（doc 注明缘由）。这不是回归，是 4-A 语义被首轮缺陷掩盖的证明。

## 六、QA 复验最小集对照（§十）

- [x] 新用例 headless 红→绿（QA-1 回退模拟红）；
- [x] 真机 untitled+dirty 卡 Play 落盘（0.44 落盘）；
- [x] 真机 P5 已保存场景腿（history dirty False/False）；
- [x] dirty_matrix/asset_lifecycle 全量回归（guards 204；Case 14 期望更新记档于 §五）。

buglist W13 勾不动（上轮已勾，QA §九核对成立）。
