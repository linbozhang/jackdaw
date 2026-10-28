# T06「当前场景 Play」与编辑态隔离 — 实施方案

> 策划产物（2026-10-26，基于本地 main **213e3370**（T05 闭环点）全量代码核实，只读调研）。
> 需求来源：`loop/plans/roadmap-game-dev.md` T06。验收原文：区分「运行当前场景」vs「启动场景运行」，
> 处理未保存场景，摆脱模板固定 scene.bsn。**验收=任意打开场景可运行；Stop 后编辑态还原；
> 运行态修改不写回。**（pie.rs:741 保存链、模板 lib.rs.template:42 固定加载为切入点。）
> buglist 吸收 Y34/W26/W17（progress 台账映射：W26 已备案"崩溃源治理归 PIE 主任务"即本任务）；
> 新发现编号 **N1–N9**（沿用 T03/T04 命名风格）。

---

## 0. 架构事实（核实结论，方案的地基）

**PIE 是「子进程 + IPC 投影」架构，不是 in-process 隔离**。这三条事实决定了方案走向：

- **游戏跑在自己的进程里**：Play = `cargo build` 游戏二进制 → 子进程（Windows Job Object /
  Linux PDEATHSIG 随编辑器死，`src/pie.rs:153-168,2071-2117`）→ ipc-channel 三通道
  （Reliable/Unreliable/Frames）双向通信（`pie.rs:89-105`、`crates/jackdaw_pie_protocol/src/event.rs`）。
  编辑器 world 从不执行游戏系统——**进程级隔离本身就是现状**，"编辑态被游戏污染"不会发生。
  `ControlEvent` 现有 Pause/Resume/Stop/Set/Add/RemoveComponent/帧流/输入/Pick/Highlight
  （`event.rs:59-106`），**无任何场景类消息**。
- **编辑器不知道、也不告诉游戏要跑哪个场景**：`spawn_instance` 的 env 面 = `BEVY_ASSET_ROOT`
  （=run.cwd，默认项目根，`pie.rs:2012-2018,2044-2047`）+ `JACKDAW_PIE`（rendezvous，`:2054`）+
  `JACKDAW_PIE_WINDOWLESS`（`:2062-2069`）+ run env/args 与 PlaySettings env/args（`:2052-2059`）。
  **没有任何场景信息**。游戏侧场景加载完全自决：模板 `spawn_scene` 硬编码
  `asset_server.load("scene.bsn")`（`crates/jackdaw_scaffold/templates/game/src/lib.rs.template:42-43`），
  游戏代码自己 spawn `JackdawSceneRoot(handle)`（`crates/jackdaw_runtime/src/lib.rs:419-421`），
  消费系统 `spawn_loaded_scenes` 挂在 Update（`runtime lib.rs:276-284`）。`RunConfig`
  （`jackdaw_pie_protocol/src/manifest.rs:18-41`）只有 name/instances/env/args/cwd/mode/target，
  **无 scene 字段；全仓无 startup scene 概念**（搜证零命中）。
- **编辑态的还原机制已存在且语义正确**：游戏状态以 overlay 投影进编辑器 preview ECS
  （`src/pie_projection.rs:258-358`，authoried 实体按 `SceneNodeId` 映射、游戏私有实体标
  `PieEphemeral`）；authored AST 从不被 PIE 写（`pie.rs:6-7` 模块文档 "the authored scene is
  never mutated"）。Stop = 杀子进程 → `OnEnter(PlayState::Stopped)`（`pie.rs:265-272`）→
  `cleanup_session_on_stop`（清 buffers/focus + `revert_preview`，`:293-299`）→
  `revert_preview` = despawn 全部 ephemeral + 清投影表 + **从 AST 重建 preview**
  （`pie_projection.rs:136-148`）。运行态回写只有**显式门**：Save to Scene
  （Path A/B promote，`pie.rs:1109-1306`）与 Live Changes tray / Stop prompt
  （`src/live_edits_ui.rs:384-408`，Stop 时对未决 live edits 弹 Apply All / Discard / Review）。

**保存链现状**（切入点 pie.rs:741）：`save_before_play`（`pie.rs:741-749`）受
`EditorBuildSettings.save_before_play` 布尔控制（默认 true，`:1477-1487`，持久化在项目
settings 顶层）→ `save_scenes_before_launch(world, "playing")`（`:756-773`）：**active tab 是
「修改过的 untitled」→ Err 硬拒绝**（"Save the scene before playing"）；否则
`save_modified_scenes`（`src/scenes/operators.rs:729-744`）——只保存 `path.is_some()` 的 tab
（**untitled 脏 tab 静默跳过**），逐 tab 走 `save_scene_inner`（T03/T04 同一原子化保存边界，
journal/.bak/基线自动正确，见 §五）。

**Play 入口现状**：主按钮 `pie.play` → `handle_play`（`pie.rs:977-1005`）从 Stopped 取
**第一个 run config** 启动；Play 下拉 = run config 实例列表 + 无 jackdaw.toml 时的 scaffold 行
（`src/pie_menu.rs:104-172,264-310`）。**没有「当前场景」入口**。

**QA 基础现状**：BRP `jackdaw/status` 已含 `pie: building|running|failed|stopped`
（`src/remote/server.rs:504-506`，`play_status` `pie.rs:211-226`）；`jackdaw/wait` 已支持
等待 pie running/pie_stopped（`server.rs:1680-1736`）；`call_operator` 可驱
pie.play/pause/stop/reload；MCP 23 工具含 status/wait/call_operator/ui_* 全套
（`crates/jackdaw_mcp/src/lib.rs:391-826`）。专项#5-T3 已跑通过一次 Play 真机全链
（pid 实跑→Stop 退出）。

---

## 一、现状与缺陷矩阵

### A. 「任意打开场景可运行」（验收句①，主体缺口）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **N1** | 🔴 | **编辑器无法指定运行场景**。Play 恒跑游戏自决场景（模板=固定 scene.bsn）。打开 `props/other.bsn` 点 Play，用户看到的是 scene.bsn 的内容（或该文件不存在时的空场景），零提示、零联动、零断言面——「运行当前场景」这个概念在编辑器侧不存在 | `spawn_instance` env 面 `pie.rs:2049-2069` 无场景变量；模板 `lib.rs.template:42`；`RunConfig` 无 scene 字段 `manifest.rs:18-41` |
| **N2** | 🔴 | **未保存（untitled）场景一刀切且两向都错**：① active=untitled 且修改 → `Err` 硬拒绝 Play（`pie.rs:757-763`）；② active=untitled 且干净 → 过拒绝门、什么都不存、游戏照跑 scene.bsn——**静默错场景**（用户以为在测自己的新场景，实际跑的是另一个）。验收句「处理未保存场景」两个方向都不合格 | `pie.rs:756-773` + `active_tab_modified`（`scenes/operators.rs:748-761`，干净 untitled 不触发拒绝门） |
| **N3** | 🟡 | **背景脏 untitled tab 静默出局**：`save_modified_scenes` 过滤 `tab.path.is_some()`，后台脏 untitled 不存、不拒、不提示；多 tab 会话下 Play 的游戏内容与编辑器所见无对账报告 | `scenes/operators.rs:736-737` |
| **N4** | 🟡 | **保存策略两态语义弱**：`save_before_play` 只有布尔。关闭时 Play 直接跑盘上旧内容（编辑器所见≠游戏所跑，无提示）；无「询问」选项；Play 后无「保存了哪些/跑了哪个副本」反馈 | `pie.rs:741-749`、`EditorBuildSettings` `:1462-1488` |

### B. Stop 还原与运行态不写回（验收句②③）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| — | ✅ | 隔离与还原主干已成立：子进程隔离、AST 恒不被 PIE 写、revert_preview 从 AST 重建、回写只有显式门（Save to Scene / Stop prompt）——T06 的工作是**验收钉死+补旁路**，不是重建机制 | §0 三条事实 |
| **N5**（=buglist W17） | 🟡 | **运行态 Inspector 预览 tick 可误写文档管线**：`commit_val_to_field` 非 final 直接 `field_edit_preview`，缺 `is_resource_entity` 守卫（对照 `val_field.rs:370-399` 有守卫）——「运行态修改不写回」的旁路 | `src/inspector/reflect_fields.rs:643-655` |
| **N6**（=buglist Y34） | 🟡 | **Stop 立即 kill，优雅停止契约不成立**：发 `ControlEvent::Stop` 后同函数内 `child.kill()`，游戏永远没机会跑 Stop→`AppExit::Success` 的优雅退出（runtime 侧整套机制是死代码）。Stop 还原链的收尾确定性缺口（未来运行时快照/存档钩子全被废） | `pie.rs:951-956`（stop_instance）、`:1024-1034`（handle_stop）；runtime `crates/jackdaw_runtime/src/pie.rs:314` |
| **N7**（=buglist W26） | 🟡 | **Job Object 三处 `assert!` 把启动失败变编辑器崩溃**：受限环境（AppContainer/沙箱/部分 CI 不允许嵌套 job）下 `AssignProcessToJobObject` 失败 → 点 Play 直接 panic 整个编辑器。T04 方案已备案"崩溃源治理归 PIE 主任务"，即本任务 | `pie.rs:1970-2004`（pie_windows::PIE_JOB） |
| — | ❓ | **Stop 还原后的 selection/焦点从未系统验收**：`revert_preview` respawn 后 preview 实体 id 全换，`Selection`/`Selected` 组件是否残留旧实体句柄（悬空）需实测；ViewState.selection 存的是 SceneNodeId（`scenes/mod.rs:401`），修复面预计是 cleanup 时按其重建 | `pie_projection.rs:145-148` + `scenes/mod.rs:399-405`；进 T2 验收矩阵实测后定 |

### C. 概念与工具面

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **N8** | ⚪ | **无启动场景概念**：全仓无 startup scene / 启动场景配置。T13（启动场景、场景列表与切换）是其主任务；T06 只需把「启动场景运行」入口**语义命名化**（=现状 run config 启动、游戏自决加载），配置面留给 T13，不重复建设 | 全仓搜证零命中；roadmap T13 定义 |
| **N9** | ⚪ | **PIE 断言面不足**：`status.pie` 只有一个粗字符串；无「哪个实例在跑/传了什么场景 override/投影实体数与 authored 对不对得上」的结构化查询——QA 验收「游戏真的加载了当前场景」缺结构化通道（MCP 优先立项） | `server.rs:504-506`；方法表 `server.rs:147-169` 无 pie 专项方法 |

**统计：🔴 2（N1、N2）｜🟡 5（N3、N4、N5/W17、N6/Y34、N7/W26）｜⚪ 2（N8、N9）｜❓ 1（Stop 还原 selection 核对）｜✅ 隔离主干**

### buglist 重叠表（PIE/Play/运行/Stop/预览相关全量扫描）

| 条目 | 一句话 | T06 处置 |
|---|---|---|
| Y34 | 发 Stop 后立即 kill，"优雅停止"契约不成立 | **吸收（T2）** |
| W26 | Job Object 三处 assert! 启动失败变编辑器崩溃 | **吸收（T2）**（T04 方案备案的"PIE 主任务"即此） |
| W17 | Val/UiRect 编辑路径不含 PIE Live 预览 tick 的资源守卫 | **吸收（T2，一行守卫+用例；「运行态修改不写回」验收句本体）** |
| Y37 | PIE 每帧对全场实体全量反射 JSON 序列化 | 不吸收（性能专项）；备注：T2 大场景 Stop 链验收会暴露它，超标则记档另立项 |
| Y33 | 游戏 BRP CORS `*` 任意网页可读写运行中游戏 | 不吸收（游戏侧远程安全域）；备注：T06 断言通道选 PIE IPC 投影（编辑器侧可见），**不依赖游戏自愿开启的 BRP**，避开该面 |
| Y35 | BRP 响应 Content-Length 无上限可 OOM | 不吸收（编辑器 BRP 客户端域，与 PIE 启停无关） |
| R4 | 远程实体树父子解析与协议失配，层级面板失效 | 不吸收（远程调试面板域，归 T24；非 Play 启停/隔离链路） |
| Y36/W27 | 键位域（旧链路序列化） | 无关，不吸收 |
| A1 | brush.join 后 recenter 位移不入撤销 | 已另立项（T03 遗留），与 PIE 无关 |

---

## 二、分任务拆解（T1/T2/T3）

### T1「运行当前场景」通道（N1+N2+N3+N4；决策 1/2/3/6）

**目标**：Play 能把「编辑器当前场景」喂给游戏子进程——任意 named 场景、任意 untitled/未保存
场景都可运行；保存策略从布尔升级三态；「启动场景运行」入口命名化。摆脱模板固定 scene.bsn。

**改动面预估**：
1. **runtime 侧（机制核心）**：`crates/jackdaw_runtime/src/lib.rs` 新增
   `apply_pie_scene_override` 系统（挂 `Update, .before(spawn_loaded_scenes)`，`:276-284`
   调度点）：读 env `JACKDAW_PIE_SCENE`（assets 根相对路径），有值时把**首个**
   `Added<JackdawSceneRoot>` 的 handle 换成 override 场景的 handle（info 日志记录原 handle
   一次；多 root 只换第一个=「主场景」惯例，book 注明）。runtime 侧补 env 常量与
   `pie_scene_override()` helper（对齐 `JACKDAW_PIE`/`JACKDAW_PIE_MODE` 家族，
   `crates/jackdaw_runtime/src/pie.rs:22-47` 先例）。**存量游戏工程零改动受益**（凡走
   `JackdawSceneRoot` 加载的场景都被覆盖）；
2. **模板教学面**：`lib.rs.template:40-44` 的 `spawn_scene` 改用
   `jackdaw_runtime::pie_scene_or("scene.bsn")`（helper：PIE override 优先，独立 cargo run
   时回落参数默认）——新工程显式可读，"固定 scene.bsn"从模板毕业；
3. **editor 侧 `src/pie.rs`**：
   a) 新 op `pie.play_current`（label "Play Current Scene"）：解析当前场景——active tab 为
   `TabKind::Scene` 即它；为 Prefab 时回落**最近的 Scene tab**（回落也无可运行场景 →
   拒绝 + 状态栏 notify_error + report_to_caller）；
   b) 按保存策略（决策 2，三态 `Save | Ask | PlayUnsavedCopy`，serde 兼容旧布尔：
   true→Save、false→PlayUnsavedCopy——旧 false 的"跑盘上旧内容"危险语义就此消灭）产出
   override 路径：named+clean → tab.path 的 assets 相对路径；named+dirty → Save 态先走
   `save_scenes_before_launch` 现链（T03/T04 边界）后用其路径 / Copy 态或 untitled →
   **temp 运行副本**：`document_fingerprint` 同源 emitter（`scene_io/save.rs:90-129`）emit
   当前文档 → `write_atomic` 写 `<assets>/.jackdaw-pie/current-<display>-<pid>.bsn`
   （不置 dirty、不动 saved 基线、不进 journal——它是运行副本不是编辑态；文件名含 pid
   防多实例互踩，对齐 T04 journal 多实例隔离先例）。Ask 态复用 confirm_dialog 模式
   （Save / Play Copy / Cancel）；
   c) `spawn_instance` 增设 env `JACKDAW_PIE_SCENE`（仅 current 模式）；
   `InstanceKey`/`PieSession` 记录本次 launch 的 `scene_override` 与来源
   （named | unsaved-copy | none），供 BRP 断言与清理；
   d) 清理：`cleanup_session_on_stop`（`:293-299`）删除本会话 temp 副本；编辑器启动时
   清孤儿 `.jackdaw-pie/current-*`（对齐 T04 孤儿 tmp 清理族）；
   e) `project.toggle_save_before_play` 升级为 `project.set_save_before_play(mode)`
   （保留旧 id 兼容或并列新 op，实现择一并在报告说明）；
4. **UI（按决策 3）**：主 Play 按钮 → `pie.play_current`；Play 下拉（`pie_menu.rs`）顶部
   加分隔组「Play Startup Scene」（=原 `pie.play` 第一个 run config 的语义命名化，无
   override env），下接既有 run 实例列表；键位建议 F5=当前场景、下拉入口=启动场景
   （对齐 Godot F6/Unity 主按钮语义，具体随决策 3）；
5. **背景脏 untitled（N3）**：current 模式下 active 场景明确（不再是"全部赌 active"），
   `save_scenes_before_launch` 的 active-untitled 拒绝门**只保留给启动场景运行**；
   current 模式下后台其它脏 tab 的处理 = 按 Save 态照旧全存（named）/逐 tab 报告
   （untitled 记入 launch report"not included"，状态栏提示），不再静默。

**验收标准（可执行可复现）**：
- [ ] headless（runtime crate）：`JackdawSceneRoot(handle A)` + env override 指 b 文档 →
  `spawn_loaded_scenes` 前换成 b handle → spawn 的实体来自 b 文档（内容断言，非仅 handle
  相等）；无 env → 行为逐字节同现状（回归锚点）；多 root 只换首个；
- [ ] headless（editor）：dirty named tab + 策略 Save → play_current 链保存走完（tab clean、
  盘上新内容）且 override=相对路径；策略 PlayUnsavedCopy → tab 仍 dirty、盘上旧文件不变、
  temp 副本内容与 `emit_bsn_scene_for_file` 同源；untitled 两策略均可运行（N2 红→绿：
  旧代码 Err 拒绝的红证先落）；
- [ ] headless：active=prefab tab → 回落最近 scene tab；全 prefab → 拒绝 + report 描述；
- [ ] headless：stop 清理——构造 temp 副本 → `cleanup_session_on_stop` → 文件不存在；
  预置孤儿 `current-99999-*.bsn` → 启动被清；
- [ ] headless：设置兼容——settings.json 旧布尔 true/false 分别读为 Save/PlayUnsavedCopy
  （迁移用例）；
- [ ] 真机（BRP 链）：my-game 打开**非 scene.bsn** 的场景 → `call_operator pie.play_current`
  → `wait(pie=running)` → `jackdaw/pie`（T3 工具；T1 阶段先用 `status.pie`+`scene_tree`
  投影实体过渡）→ 断言 `scene_override` 指向该场景 → 投影流实体对账（流回的
  `scene_node_id` 集合 ⊇ 该场景 AST stable id 集合）→ `pie.stop` → temp 副本已清理。

**测试设计**：guards 新 `tests/guards/play_current_scene.rs`（editor 侧 headless 链，harness
复用 T03 `dirty_matrix.rs` 的 editor/place/save 模式）；runtime crate 单测新模块；真机脚本
沉淀 `loop/qa/t06-play-current.ps1`（复用专项#5 沉淀的 Play 冒烟 + `t02t2` 的 BRP 调用模式）。
**buglist 吸收**：无直接打钩（N1/N2 新发现）；W17 归 T2。

### T2「Stop 还原加固与优雅停止」（N6/Y34+N7/W26+N5/W17+❓selection；决策 4/5）

**目标**：验收句②③的铁证化——Stop 后编辑态逐项还原（实体/脏标记/盘上文件/selection/视图）；
堵住运行态写回旁路；Stop/启动自身的崩溃与契约缺口收口。

**改动面预估**：
1. **Y34 优雅停止**：`stop_instance`/`handle_stop` 改为「发 `ControlEvent::Stop` → 记
   deadline（常量 2s）→ 不立即 kill」；`advance_child`（`pie.rs:1851-1937`）对带 deadline
   的 Live child 到期才 kill（Connecting 路径维持现状——未连上的子进程无优雅可言）；
   `reconcile_play_state` 已有（children 空 → Stopped），Stop prompt 因此最迟 2s 出现。
   `handle_reload` 保留立即 kill（reload 语义=重建会话，注释说明）；
2. **W26 降级**：`pie_windows::PIE_JOB` 三处 `assert!` 改失败降级——`assign_to_process`
   返回 Result，失败 `warn!` 后无 job 保护继续；LazyLock init 失败改 `Option<Job>`；
3. **W17 守卫**：`commit_val_to_field` 开头补 `is_resource_entity` 分流（照抄
   `val_field.rs:370-399` 的守卫形状）+ 红绿用例（资源卡 Val 字段在 Live 预览 tick 不再写
   selection 文档管线）；
4. **❓selection 还原**：实测 `revert_preview` respawn 后 `Selection`/`Selected` 是否残留
   旧实体句柄；若有 → `cleanup_session_on_stop` 补按 `ViewState.selection`（SceneNodeId
   集）重建 selection（复用 tab 激活路径的恢复逻辑），红绿用例钉死；
5. **验收句③的旁路审计**：全链复查「Play 运行期间编辑器侧有哪些路径会写 authored
  文档/盘上文件」——预期唯一集 = 显式 Save to Scene / Apply All / 用户 Ctrl+S / Play 前保存
  策略；审计结论落报告（含 PIE 投影写 preview ECS 不入此集的证据）。

**验收标准**：
- [ ] headless：优雅停止——advance_child 新分支：deadline 内子进程退出→优雅路径、超时→
  kill 恰一次（现有 ChildStage 测试族扩展；伪造 stage 驱动，不起真进程）；
- [ ] headless：W17 红→绿；selection 残留（若实锤）红→绿；
- [ ] **真机 Stop 还原铁证链（验收句②，SHA 双腿对齐 T04 模式）**：fixture 打开场景 →
  `scene.save` → 记录 `jackdaw/scene_bsn` SHA + 盘上文件 SHA + `jackdaw/history` 栈深 +
  tab dirty → Play（游戏含会移动实体的系统，跑 ≥2s）→ `pie.stop` → `wait(pie_stopped)` →
  断言①scene_bsn/盘上 SHA 与 Play 前逐字节一致②dirty 与栈深不变③`scene_tree` 实体
  名集与 Play 前一致④world.query 无 `PieEphemeral`/投影残留⑤selection 有效（或按修复
  断言还原）⑥temp 副本已清；
- [ ] 真机（验收句③显式门）：Live 模式 Inspector 改组件 → Stop → stop prompt 出现
  （`ui_tree` 断言）→ Discard → 文档不变；再 Play → 改 → Stop → Apply All → 文档恰含
  该显式改动（undo 一条，T03 已钉）；全程无其它写盘（journal/文件系统双侧断言）；
- [ ] 真机：W26 生效性回归——kill 编辑器 → 游戏子进程死（进程枚举断言，job object 正常
  路径）；降级分支以单测+代码审查覆盖（真机模拟受限环境不可行，如实记档）；
- [ ] 大场景 Stop 链不卡顿：500+ 实体场景 Stop → pie_stopped 在 deadline+1s 内到达
  （Y37 若在此暴露超标，记档另立项）。

**测试设计**：guards 新 `tests/guards/stop_restore.rs`（headless 半场）；真机铁证链沉淀
`loop/qa/t06-stop-restore.ps1`（复用 T04 kill 链脚本的轮询/等待模式与 manual §6 时序规约）。
**buglist 吸收**：Y34、W26、W17 打钩。

### T3「PIE 断言工具面 + 真机矩阵 + 文档收尾」（N9；决策 7）

**目标**：把 PIE 会话态变成结构化可查（QA 断言通道，MCP 优先）；验收三句的真机矩阵终验；
文档与台账。

**改动面预估**：
1. **BRP 新方法 `jackdaw/pie`**（挂 `server.rs:147-169` 方法表）：返回
   `{status, view_mode, focused, instances:[{key, stage: connecting|live, config,
   scene_override, scene_source: named|unsaved-copy|none, cwd}], projection:{entities,
   authored, ephemeral}, live_edits: N}`——读 `PieSession`/`PieInstances`/`PieProjection`/
   `LiveEditLog` 组装，headless 可测（`jackdaw/history`/`recovery` 同模式）；
2. **MCP 第 24 工具 `pie`**（`crates/jackdaw_mcp` 薄翻译，与 audit/recovery 工具同构）；
3. **真机验收矩阵（全 BRP/MCP 驱动，截图+日志留档 `loop/reports/`）**：

| # | 场景 | 期望 |
|---|---|---|
| 1 | 任意 named 场景运行 | `jackdaw/pie` 的 scene_override=该场景；投影对账（scene_node_id 集 ⊇ AST 集）；游戏画面含该场景实体 |
| 2 | untitled 场景运行 | scene_source=unsaved-copy；temp 副本存在；游戏加载其内容；Stop 后副本清理、tab 仍 dirty |
| 3 | dirty named × 三策略 | Save=落盘+clean；Ask=对话框三按钮语义；Copy=盘上不变+副本跑 |
| 4 | prefab tab 在前 | 回落最近 scene tab；全 prefab=拒绝+提示 |
| 5 | 启动场景运行（下拉/run config） | scene_override=null（不干预游戏自决）；原 run 语义零回归 |
| 6 | Stop 还原铁证 | T2 链复跑（终验） |
| 7 | Stop prompt Apply/Discard | 两分支文档期望态 |
| 8 | Reload 链（current 模式） | 重启后 override 重算（编辑过则新副本） |
| 9 | 崩溃孤儿 | kill 编辑器 → 游戏死 + 重启后孤儿 temp 清理 |
| 10 | 多实例（instances>1） | 全部实例带同一 override；逐实例 stop/reap |

4. book 补「Play-In-Editor」节（运行当前场景 vs 启动场景、未保存三策略、Stop 还原语义、
   `.jackdaw-pie/` 运行副本说明、多 root 只换首个的限制）；buglist 打钩核对（Y34/W26/W17）；
   roadmap T06 勾选；台账记行。

**验收标准**：
- [ ] 矩阵 10 格全过（BRP 日志+截图留档）；
- [ ] 全量门（`xtask fast`/`integration`/docs/doctests）按 2026-10-25 升级版门禁证据标准
  （日志全文复核、重跑覆盖归档）；
- [ ] 用户 30 秒清单：①打开任意一个不是 scene.bsn 的场景点 Play——看到的就是这个场景；
  ②Play 里让游戏把东西弄乱（移动/生成实体）→ Stop → 编辑器里一切如初，文件没被碰；
  ③新建一个没保存的场景直接 Play 也能跑起来，Stop 后场景仍是未保存状态。

**测试设计**：真机脚本沉淀 `loop/qa/t06-final-live.ps1`（矩阵全链，参照 `t04-final-live.ps1`
模式）。**buglist 吸收**：核对 Y34/W26/W17 备注与打钩。

**QA 清单（放行标准，全任务）**：
- [ ] T1/T2/T3 各自验收全绿；每个 🔴（N1/N2）与 Y34/W17 有红→绿测试；
- [ ] 「不写回」铁证：Stop 链 SHA 双腿（emit+盘上）+ 显式门两分支（Discard=不变 /
  Apply=恰一条）+ journal 侧无未预期写；
- [ ] 「任意场景可运行」铁证：named/untitled/dirty/prefab-回落四形态各一格真机 + 投影
  scene_node_id 对账；
- [ ] quick 门（T1/T2）/ 全量门（T3）；门禁证据以日志全文复核为准（README 2026-10-25 标准）。

---

## 三、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **场景传递机制** | A=**env `JACKDAW_PIE_SCENE` + runtime 换把**：编辑器把 assets 相对路径塞进 env；`JackdawPlugin` 在 `spawn_loaded_scenes` 前把首个 `JackdawSceneRoot` 的 handle 换成 override 场景。存量工程零改动受益（凡走 JackdawSceneRoot 即覆盖）；env 是现有 PIE 配置通道的自然延伸（JACKDAW_PIE/WINDOWLESS 家族）。B=只改模板让游戏自己读 env：教学清晰但**存量工程（含 my-game）无效**，"任意打开场景可运行"验收对旧工程落空。C=协议加 `ControlEvent::LoadScene`：启动期时序复杂（Startup 已加载完才收到消息要换场景重 spawn），且属 T13 运行时场景切换的领地 | **A**（模板同时改教学面，A+B 叠加）；C 记 T13 候选 |
| 2 | **Play 前保存策略** | A=**三态枚举 `Save \| Ask \| PlayUnsavedCopy`**，默认 Save；旧布尔兼容映射 true→Save、false→PlayUnsavedCopy（旧 false 的"跑盘上旧内容"危险语义就此消灭）；current 模式下 untitled 恒走 temp 副本（不落盘不打断）。B=维持布尔+current 模式特判：少一个设置项但语义分裂（config 模式跑旧的、current 模式跑新的）。C=每次 Play 弹询问：最安全但打断流（专项#5 教训：modal 链是历史雷区） | **A**；Ask 用 confirm_dialog 现成 scrim+card 模式（T04 N9 矩阵已验过该对话框族） |
| 3 | **「运行当前场景」UX 入口形态** | A=**主 Play 按钮=运行当前场景**；下拉首组「Play Startup Scene」（原首 run config 语义）+ 既有 run 列表。对齐 Unity（主按钮跑当前）与 Godot F6；一个主按钮一个心智。B=双按钮（Play Current / Play Game）：入口都显式但工具栏拥挤、新用户困惑"该点哪个"。C=run config 加 scene 字段：那是 T13 的启动场景配置面，本任务做会与 T13 撞车 | **A**；键位 F5=当前场景（主按钮），启动场景走下拉（后续可加 Shift+F5，非本任务必须） |
| 4 | **Stop 还原机制选型** | A=**保持 respawn-from-AST 现状**（revert_preview）+ 补 selection/视图还原核对与修复：AST 本就是唯一权威基线，机制已对，缺的是验收。B=Play 前 ECS 快照、Stop 回滚快照：与 undo/AST 双轨状态，复活 T03 之前的双源漂移问题。C=play 期间冻结编辑器交互：过度限制，Unity 也不这么做 | **A**（B 明确不做；隔离主干已在，铁证化+补旁路即验收句②③全部） |
| 5 | **优雅停止修法（Y34）** | A=**deadline 非阻塞 reap**：发 Stop 后 child 留在 children 表带 2s deadline，`advance_child` 到期 kill；Stop prompt 最迟 2s 出现；机制（reconcile_play_state/advance_child）全部现成。B=同步等待（block 最多 2s）：实现最少但冻 UI。C=维持立即 kill：不修，游戏侧优雅退出永为死代码 | **A**（deadline 常量化 2s；Reload 保留立即 kill 并注释） |
| 6 | **未保存副本（temp）位置** | A=`<assets>/.jackdaw-pie/current-<display>-<pid>.bsn`：**点前缀目录被资产 walk 天然跳过**（`crates/jackdaw_bsn/src/header.rs:230-231` 跳 `.` 开头），不污染 AssetIndex/audit/referrers；bevy AssetServer 显式相对路径加载（虚拟路径单组件 `.jackdaw-pie/x.bsn` 不越根，桌面后端按路径读）——**需 T1 真机验证一次**，不通过则回落 B。B=非隐藏保留目录（如 `assets/play-preview/`）+ walk 加显式跳过规则：控制力强但要改公共 walk 语义，风险大于收益。C=不允许 untitled/未保存运行：违反"任意打开场景可运行"验收 | **A**（B 为回落备案；场景文档引用是 assets 根单一命名空间（T05 结论），副本放 assets 内不破坏引用解析） |
| 7 | **PIE 断言通道** | A=**editor 侧新 BRP `jackdaw/pie` + MCP 镜像**：读 PIE 会话/投影/编辑日志组装，不依赖游戏配合；「游戏真加载了场景 X」用投影流 scene_node_id 对账证明。B=经游戏 BRP（15702）断言：依赖游戏自愿加 `JackdawRemotePlugin`（模板没加），且 Y33 的 CORS 面挡路。C=只用 status.pie 字符串：无法证明加载了哪个场景 | **A**（MCP 优先原则的正面案例：QA 需要什么断言，工具层就补什么） |

另有小定案（主控可否决）：`pie.play` 保留原 id 不动语义（启动场景运行），current 走新 op
`pie.play_current`——operator 注册表向后兼容，BRP 键位/旧脚本零破坏。

---

## 四、风险与回滚

| 风险 | 缓解 |
|---|---|
| bevy AssetServer 对 `.jackdaw-pie/x.bsn` 点前缀路径加载失败（个别后端规范化点路径） | T1 首个真机用例即验；失败回落决策 6-B（保留目录+walk 显式跳过）；headless 先用 runtime 单测钉住"env→换把→spawn"机制层，路径形态问题不伤机制 |
| runtime 换把系统与游戏自定义场景加载逻辑冲突（游戏在 Startup 同帧多次增删 root / 手动 spawn 场景实体不走 JackdawSceneRoot） | 换把只作用于首个 Added root，不改其余；book 明示"运行当前场景"支持面=JackdawSceneRoot 路径；投影对账断言（scene_node_id ⊇ AST）会让不支持的游戏在 T06 验收矩阵如实暴露而非静默错场景 |
| temp 副本写入 assets 触发 watcher rescan churn（notify 事件→walk→dot 目录跳过） | walk 跳点目录=索引不变，rescan 空转一次无害；真机矩阵 #2 观测确认；`note_written` 不适用（非 tab 文件），external_watch 只 watch 打开 tab 的文件，天然无联动 |
| 优雅停止改动引入 Stop 卡死（游戏吞 Stop 不退出） | 2s deadline 硬上限 + `wait(pie_stopped)` 的帧上限（server.rs:1684 现有）双保险；deadline 分支单测覆盖"永不退出的 child 恰被 kill 一次" |
| 保存策略三态的 serde 迁移破坏老项目 settings.json | 兼容读（bool→枚举映射）+ 迁移用例；写回新枚举；`.bak`（T04）天然兜底 |
| Play 主按钮语义变化（老用户习惯=跑首 run config） | 下拉首组显式命名「Play Startup Scene」保住旧路径；book/release note 说明；键位清单进 final-qa 用户 30 秒清单 |
| current 模式与多实例（instances>1）叠加：N 个进程同时读同一 temp 副本 | 只读无竞争；文件名含 pid 防多编辑器实例互踩；矩阵 #10 覆盖 |
| 回滚 | 三任务独立成分支段：T1 换把机制+新 op+设置枚举（revert 即回现状布尔/固定 scene.bsn，零格式变更——temp 副本是可再生文件）；T2 停止/守卫三处局部修（各自独立 revert）；T3 纯工具+文档。全程零场景格式变更、零协议破坏（新 env 是加法）——与 T05 同款的最大回滚保险 |

---

## 五、与 T03/T04/T05 已建设施的衔接

1. **T03 per-tab 指纹 = Play 前保存链的脏判定权威**：`save_modified_scenes`/`active_tab_modified`
   全走 `tab.dirty + observed_pushes`（T03 建立，`scenes/operators.rs:729-761`）；T1 的三态
   策略只决定"存还是跑副本"，脏判定不另造第三轨。Play 运行期间用户继续编辑（Scene 视图）
   的 dirty/journal 行为不变（journal 触发系统只看 per-tab 状态，与 PlayState 无关）。
2. **T04 保存边界 = Play 保存与 temp 副本的双重基座**：Save 态走 `save_scene_inner` 原子链
   （journal 条目出局 + `.bak` 轮转 + saved 基线更新全免费）；temp 副本走同一 `write_atomic`
   （同步 fsync），但**刻意不进 journal**（它不是编辑态，崩溃后恢复它毫无意义——恢复源是
   编辑器里的 tab 本身）。孤儿清理对齐 T04 孤儿 tmp 族。**T1 验收补一条衔接用例**：
   dirty tab → Play（Save 态）→ kill 编辑器于 Play 后 → 重启 journal 无该 tab 条目（已持久化）。
3. **T04 `jackdaw/recovery` 的 BRP 模式 = `jackdaw/pie` 的模板**：读全局状态返 JSON 的挂法、
   headless 测法、MCP 薄翻译三件套照此办理（第 24 工具与 audit/recovery 同构）。
4. **T05 audit/referrers 与 temp 副本互不干扰**：副本在点前缀目录，`walk_document_files`
   跳过（`header.rs:230`）→ 不入 AssetIndex、不进 audit 清单、不参与 referrers——无需为
   T06 加任何特判（这是决策 6 选 A 的核心理由）。
5. **T05 `SceneNodeId` 稳定标识 = 投影对账断言的地基**：「游戏真加载了当前场景」用 PIE
   流回的 `scene_node_id` 集合与当前 tab AST 的 stable id 集合比对（`pie_projection.rs:262-264`
   映射先例 + `snapshot.rs` 的 scene_node_id 字段）——不依赖游戏 BRP、不改协议。
6. **Live edits 门与 T03 的联动维持**：`pie.live_edit_save`/`apply_all` 已声明 undo-transparent
   （T03 SELF_PUSHING 52 清单）；T2 的显式门验收（Apply All=恰一条 undo）是对该清单的
   回归复核，不需新声明。T25（Live 调参与选择性回写）未来扩展时，本任务的 `jackdaw/pie`
   工具与 Stop prompt 语义直接复用。
7. **分支与行号基线**：本方案行号基于 main 213e3370（T05 闭环点）。T06 从 main 拉
   `loop/t06-play`，行号按符号名重定位（矩阵证据均已给符号名）。
