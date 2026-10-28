# T08 游戏参数配置与运行时加载 — 实施方案

> 策划产物（2026-10-24，基于本地 main **6119a066**（T07 闭环点 = P0 收官基线）全量代码核实，只读调研；
> 不建分支、不改代码）。需求来源：`loop/plans/roadmap-game-dev.md` T08（P1 第一项，T01-T07 已全部闭环）。
> **验收原文**（roadmap 第 20 行，已核实）：「游戏组件/配置资产/游戏 Resource 初值的作者态持久化+运行时注入
> （与 editor 会话态 Resources 面板区分）。**验收=生命值/移速/重力等重启+Play+导出三态一致。**」
> 注意：派发任务书的转述为「重启+Play 后仍生效且可在编辑器改」，原文多「**+导出三态一致**」——本方案以
> 原文为准，三态=①重启编辑器 ②Play 运行 ③导出发布包，三处参数值一致生效。
> buglist 直接重叠条目少（参数/资源域历史条目大多已在 T03-T07 处理）；顺手吸收 **W13**；关联注意事项
> Y33/N12/N11。方案内新发现编号 **P1–P8**（Params，避免与 buglist N 系撞名）。

---

## 0. 架构事实（核实结论，方案的地基）

**「游戏参数」在 jackdaw 里已经分成三条载体链，成熟度极不均衡**。这三条事实决定方案走向：

- **事实一：场景内组件参数已经是作者态闭环，T08 不需要为它建设**。模板教学件 `SpinningCube.speed`
  （`crates/jackdaw_scaffold/templates/game/src/lib.rs.template:50-70`）挂实体、Inspector 编辑、bsn 落盘、
  undo/脏标全走 T03 体系；T02 已验收「改参数三处一致、重开一致」；T06 PIE 换把（`JACKDAW_PIE_SCENE` env +
  runtime 首个 root 换把，`crates/jackdaw_runtime/src/lib.rs:585-644`）让任意场景可运行；T07 导出 staging 全量
  拷 assets。Graphics 面板 Scene 区的场景级参数（Environment 组件）是同一条链的先例
  （`src/environment_ops.rs:126-174`，`environment.set` 单 undo 写场景文档）。验收句的「生命值/移速」若建模为
  组件，**现状已满足三态一致**。
- **事实二：游戏 Resource 初值完全无作者态，且编辑器改动对游戏进程不可见**。Resources 面板（功能#1）
  的语义被三处文档钉死为**纯会话态**：模块文档「Edits are therefore editor-session state, not part of the
  saved scene」（`src/inspector/resource_panel.rs:11-18`）；常驻提示文案「Resource changes apply to this editor
  session only and are not saved with the scene.」（`crates/jackdaw_localization/src/locales/en-US/main.ftl:14`）；
  operator 注释「resources are session state the document does not hold」（`src/inspector/resource_ops.rs:48-51`）。
  `resource.insert/remove/set_field` 三 op（`resource_ops.rs:52-157`）只写**编辑器 world 的 ECS**。而 PIE 是
  子进程架构（T06 §0），投影流只回**实体+组件**、无任何 Resource 通道（`ControlEvent` 无资源类消息、
  `crates/jackdaw_runtime/src/pie.rs` `stream_state` 只序列化实体）——编辑器里改 Gravity（面板 allowlist 含
  `avian3d::math::Gravity`，`resource_panel.rs:58-67`，游戏携带物理模块时可见）改的是编辑器自己的 world，
  **游戏子进程永远看不到，重启编辑器也丢**。这正是 roadmap 括号里「与 editor 会话态 Resources 面板区分」
  要区分的对象。
- **事实三：配置资产（definition assets）体系已存在且两侧全链齐备，缺的只有中间一环**。
  - 编辑器侧：`AssetKinds` 三源（Compiled/Schema/Extension，`crates/jackdaw_api_internal/src/asset_kinds.rs:15-106`），
    其中 Schema 源=「the open project's schema, which reports every type the game registers as a reflected
    asset」（模块文档 `:1-8`）——**游戏只要 `init_asset::<T>() + register_asset_reflect::<T>()`，编辑器无需编译
    游戏代码就能创建/编辑该类型的资产文件**（schema-backed，值以文档 patch 形态编辑）。全链 operator 已有：
    `asset.new/new_picker/open/save/delete/set/get/list/pick/clear`（`src/definition_assets.rs:1295-1306` 注册表、
    `:1412-2013` 实现）——**BRP `call_operator` 可驱，QA 不需要新工具**。写盘已走 T04 `write_atomic` + 幂等跳过
    （`write_asset_file`，`definition_assets.rs:218-245`）；字段编辑是 `SetDefinitionField` EditorCommand，进
    全局 `CommandHistory`（`:740-790`）——即 **active tab 的工作栈**（`src/scenes/swap.rs:76,128,288` take/装回，
    `src/history_ops.rs:65,88` 的 Ctrl+Z 走它），Ctrl+Z 可撤资产编辑。
  - 游戏侧：`JackdawPlugin` 的 `load_asset_files`（Startup，`crates/jackdaw_runtime/src/lib.rs:275`）walk 全部
    assets 下 `.bsn`——**单根、无子、类型注册为 Asset** 的文件被 `load_asset_root` 载入 asset store 并进
    `JackdawCatalog`（路径键 + `@stem` 键，`lib.rs:1560-1691`）。Play 时 `BEVY_ASSET_ROOT`=项目根
    （`src/pie.rs:2351-2357,2385-2393`）→ **配置资产文件天然被游戏读到，不需要 env/协议新通道——「文件即
    真相」，与 T06 的场景通道平行且更简单**。导出 `copy_tree` 全量拷 assets（T07 过滤名单只排
    `.bak/.jackdaw-pie/*.tmp-*/.corrupt-*`）→ **配置资产天然进发布包**。
  - **缺的一环**：runtime 没有「配置资产 → Resource 初值」的机制（全仓无此概念）；模板没有任何 Resource
    配置示例；于是「重力」这类 Resource 参数既配不了、也注不进。

**生命周期边界现状（缺陷的温床）**：资产卡片的未保存编辑有独立 dirty 标志
（`DefinitionAssetEdit.dirty` + `open_card_has_unsaved_edits`，`definition_assets.rs:53-67,667-689`），但该函数
**全仓无外部消费者**——Play 前保存链 `save_scenes_before_launch` 只遍历 `Scenes.tabs`
（`src/pie.rs:965-982`、`src/scenes/operators.rs:729-744`）；导出走同一条链（`src/game_export.rs`
`start_game_export`）；T04 退出对话框与 crash journal 都只看场景 tab。同时全局栈的 push 计数被
`active_tab_modified` 用来判脏（`operators.rs:748-761`，`tab.dirty || pushes > tab.observed_pushes`）——
**资产/资源编辑的 push 会把场景 tab 弄脏**（P7，见矩阵）。

---

## 一、现状与缺陷矩阵

### A. 游戏 Resource 初值的作者态与注入（验收句主体）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **P1** | 🔴 | **游戏 Resource 参数无任何作者态路径**：Resources 面板纯会话态（设计如此）、重启即丢；引擎/游戏 Resource（重力、时间缩放、自定义 PlayerConfig）无法像组件那样「编辑器改、存盘、重开还在」。验收句「重力」一类参数完全落空 | `resource_panel.rs:11-18`；`resource_ops.rs:48-51`；`main.ftl:14` |
| **P2** | 🟡 | **runtime 无「配置资产→Resource 初值」机制**：即便手工放一个配置资产文件，游戏启动也不会把它变成 Resource 初值——`JackdawPlugin` 只把资产载入 store/catalog，没有任何 `insert_resource` 步骤；全仓无此概念 | `crates/jackdaw_runtime/src/lib.rs:210-334`（build 全量）、`:1560-1819`（walk/load 无资源步骤） |
| **P3** | 🟡 | **模板无教学**：`lib.rs.template` 只有组件示例（SpinningCube），没有配置资产/Resource 示例；新工程用户无从发现「全局参数」模式。T11（玩家控制器「关键参数 Inspector 可调」）/T16（音量三类控制）/T17（玩家设置）/T20（「主要靠编辑器配置完成」）全部依赖此模式 | `lib.rs.template:1-70`；roadmap T09-T20 定义 |

### B. 会话态/作者态边界与生命周期

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **P4** | 🔴 | **资产卡片未保存编辑三不管，直接违反三态一致**：卡片 dirty 不挡 Play（跑的是盘上旧值）、不挡导出（发布旧值）、不挡退出（编辑丢失）。用户在编辑器里把 player_health 改到 150（卡片可见 150）→ Play/导出仍是盘上 100——「编辑器所见≠游戏所跑≠发布内容」 | `definition_assets.rs:667-689`（无消费者）；`pie.rs:965-982`；`game_export.rs`（save_scenes_before_launch 调用侧）；T04 N9 对话框条件只看场景 tab |
| **P5** | 🟡 | **资产/资源编辑污染场景 tab 脏标**：全局 `CommandHistory` 的 push 计数被 active tab 判脏复用（`pushes > observed_pushes`），`SetDefinitionField` 与 `ResourceInsert/Remove/SetField` 的 push 会让一个内容未变的场景 tab 显示 dirty（watcher 实证：`mark_active_dirty_on_history_growth` 在 push 使 undo_len 离开 saved 深度时无条件 `needs_dirty_flip` 置 dirty，`scenes/mod.rs:327-384`；指纹比对只在深度回到基线时才参与）——要 undo 掉该编辑或触发一次「假保存」才清，脏标语义与场景文档内容脱钩，违背 T03 per-tab 指纹的初衷（指纹只看场景文档 emit，pushes 是它的前置粗筛） | `scenes/operators.rs:748-761`；`scenes/mod.rs:327-384`（watcher）；`definition_assets.rs:770-780`（push 点）；`resource_ops.rs:80-84,122-126,154`（push 点）；`swap.rs:76,288`（全局栈=tab 工作栈） |
| **P6** | ⚪ | **crash journal 不含资产编辑**：kill 编辑器时未保存的资产卡片编辑无恢复（场景 tab 有 journal、资产没有——边界不一致，但 journal 是 per-tab 场景文档结构，扩资产=结构变更） | `session_journal` 只遍历 `Scenes.tabs`（T04 建立时口径） |
| **P7** | ⚪ | **会话态/作者态两套编辑面零桥接、可发现性弱**：作者态入口（Project 窗口 New Asset...）深；Resources 面板会话态提示有了，但没告诉用户「要持久化该怎么走」；同一游戏类型若同时是 Resource 与 Asset，两处编辑语义无说明 | `resource_panel.rs:266-269`；`src/new_asset.rs:1-7` |

### C. 测试与断言面

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **P8** | ⚪ | **「Play 后 Resource 生效」无直接断言通道**：PIE 投影只流实体+组件（无 Resource 流）；游戏侧 BRP 有 Y33(CORS)/N12(实体域不通) 两道坎。可用替代=**行为断言**（`jackdaw/scene_snapshot` 读投影实体 Transform，参数变化→位移/旋转速率变化）；「重启仍在」「导出生效」用 `asset.get` + `jackdaw/export` + dist 文件断言，均现成 | `crates/jackdaw_runtime/src/pie.rs:151-281`（stream_state 实体面）；`src/remote/server.rs:145-172`（22 个 BRP 方法）；buglist Y33/N12 |
| — | ✅ | **正向资产（不用重建）**：asset.* 九 operator 全套（BRP 可驱）；`write_atomic`+幂等写盘；T05 rename/move 已联动 `DefinitionAssetEdit.path`（buglist Y8 备注）；AssetIndex/audit/referrers 对资产文件的治理全链；T06 `jackdaw/pie`+`scene_snapshot` 投影断言；T07 `jackdaw/export`+manifest；22 BRP 方法+25 MCP 工具；模板 scaffold 测试族（T06-T3 实编先例） | `definition_assets.rs`；`asset_kinds.rs`；`server.rs:145-172` |

**统计：🔴 2（P1、P4）｜🟡 3（P2、P3、P5）｜⚪ 3（P6、P7、P8）｜✅ definition assets 两侧全链+组件参数链闭环**

### buglist 重叠表（参数/配置/Resources/持久化/资产域全量扫描）

| 条目 | 一句话 | T08 处置 |
|---|---|---|
| **W13** | `notify_warn` 与 `notify_info` 同实现，警告色不可达 | **顺手吸收（T2）**：Play/导出前资产保存失败要走真正的警告档，一行修+文案测试 |
| Y33 | 游戏 BRP CORS `*` 任意网页可读写运行中游戏 | 不吸收；**断言通道设计避开游戏 BRP**（走编辑器侧投影/文件断言），备注维持 |
| N12 | bevy 原生 BRP 与 jackdaw 方法实体域不通 | 不吸收；`scene_snapshot`（投影域）承担行为断言，按域选方法知悉 |
| N11 | Inspector 合成提交工具缺口 | 不吸收、不阻塞：`asset.set`/`resource.set_field` op 可 BRP 驱，无需 UI 合成输入；T06 排期项维持 |
| W17（已勾） | Val 编辑路径资源守卫 | 无动作；T08 的 Resources 面板回归用例会顺带复核 |
| Y8 备注（已勾） | rename 已 retarget `DefinitionAssetEdit.path` | 无动作；T08 矩阵格 2（重开一致）覆盖其回归面 |
| W24 | `show_file` 对同一路径连续两次 `read_asset_kind` | 不吸收（Inspector 性能小项，与本任务验收无交集） |
| R3-R8、Y10/Y11/Y15、W14 等 | prefab/几何/Inspector 域 | 无关，不吸收 |

> 如实报告：与「参数/配置/Resources/持久化」直接重叠的 buglist 条目确实少——该域历史问题（undo 双记录、
> 资源守卫、保存原子化）已在 T03/T04/T06 处理完毕；T08 的缺陷主体是**本方案新发现的 P1-P8**。

---

## 二、分任务拆解（T1/T2/T3）

### T1「配置资产 → Resource 初值注入链 + 模板教学」（P1+P2+P3；决策 1/2）

**目标**：游戏侧获得「定义配置类型 → 编辑器作者态创建/编辑/保存 → 游戏启动自动注入为 Resource 初值」的
完整链；新工程模板开箱即有一个三字段示例（player_health/move_speed/gravity，对齐验收句例示）；Play 与
独立 cargo run 同一文件同一行为。

**改动面预估**：
1. **runtime 注入机制（`crates/jackdaw_runtime`）**：新增 `ConfigLoader<T>` 泛型组件 +
   `apply_config_defaults` 通用系统（挂 `Update`、一次/进程，对齐 `apply_pie_scene_override` 的
   Added+Local 模式，`lib.rs:615-644` 先例）：游戏 spawn
   `ConfigLoader::<GameConfig>::new("game-config.bsn")`（assets 相对路径或约定路径），系统在资产就绪后把
   `T` 的值 `clone` 进 `insert_resource`（info 日志一次）；文件缺失/未注册 → `T::default()` 兜底 + warn 一次
   （缺配置不是错误——游戏要能跑）；资产热改不重注入（启动初值语义，Live 热调参是 T25 领地，注释写明）。
   约束 `T: Asset + Resource + Clone + FromReflect`。runtime 零新依赖；
2. **模板教学面（`crates/jackdaw_scaffold/templates/game/src/lib.rs.template`）**：
   a) 新示例类型 `GameConfig { player_health: f32, move_speed: f32, gravity: f32 }`，
      `#[derive(Asset, Resource, Reflect, Default, Clone)] #[reflect(Resource, Default)]`——
      **同时是 Asset 与 Resource**（Asset 给编辑器/文件链，Resource 给 ECS 消费），带
      `@EditorCategory::new("Game Config")` 分类；
   b) `GamePlugin::build` 加 `app.init_asset::<GameConfig>().register_asset_reflect::<GameConfig>()`
      （两行，游戏注册资产类型——schema 提取据此把类型报给编辑器 AssetKinds）；
   c) Startup spawn `ConfigLoader::<GameConfig>::new("game-config.bsn")`（对齐 `spawn_scene` 旁的写法）；
   d) 一个消费系统（约 8 行）：`FallingCube` 示例实体按 `config.gravity` 下落 + spin 倍率读
      `move_speed`——「全局参数」与「组件参数」（既有 SpinningCube）的对照教学；
      `player_health` 字段保留（T11/T12 的伏笔，注释注明供 HUD/玩家系统读）；
   e) 模板 doc 注释补「# Tuning parameters」一节：改参数=编辑器打开 `game-config.bsn` 卡片改字段 → Save
      → Play/cargo run 生效；
3. **编辑器侧零改动验证**：schema-backed 资产链（New Asset→卡片→asset.set→asset.save）对 `GameConfig`
   的可用性来自既有机制（`AssetKind::from_schema`），T1 只需真机证明一次全链（验收⑤）；
4. **存量工程路径（文档面）**：book 给出 my-game 类工程的接入两行（derive+注册）+ 说明
   「`@stem`/路径引用可从任何场景引用同一份配置」。

**验收标准（可执行可复现）**：
- [ ] headless（runtime crate）红→绿：spawn `ConfigLoader<GameConfig>` + assets 下配置文件（值非默认）→
  `apply_config_defaults` 后 world 含 `GameConfig` Resource 且三字段值=文件值（红证=无该系统时 Resource
  不存在/为默认）；文件缺失 → `T::default()` + 恰一条 warn；同帧再改 store 内资产值 → Resource 不变
  （一次/进程钉死）；
- [ ] headless（往返一致性）：用编辑器 `emit_definition_patch` 同族文本（header+`#Name`+Struct patch，
  `definition_assets.rs:250-300` 形态）作为配置文件 → runtime `load_asset_files` walk 载入 +
  `ConfigLoader` 读到同值——**编辑器写盘形态 ↔ 游戏读取形态兼容**是本任务的隐含契约，必须有用例；
- [ ] headless：untitled/dirty 场景 + Play(Copy 态) 组合语义——配置资产不受 PIE temp 机制影响
  （`.jackdaw-pie/` 只装场景副本，`game-config.bsn` 仍从 assets 正本读）——用 runtime 测试钉死；
- [ ] 模板：scaffold 测试族扩展——生成的模板含 GameConfig/ConfigLoader（T06-T3「实编 cargo check」先例）；
- [ ] 真机（BRP 全链，验收句「可在编辑器改」+三态②）：新建模板工程（scaffold）→ 打开编辑器 →
  `call_operator asset.new_picker kind=game_config`（schema 报告后 New Asset 列表出现）→ `asset.set
  move_speed=2.5` → `asset.save` → `pie.play_current` → `wait(pie=running)` → `scene_snapshot` 断言
  FallingCube 位移速率/spin 倍率与 2.5 一致（行为断言：采样两帧 Transform 差）→ `pie.stop` → 盘上
  `game-config.bsn` 仍 2.5；改 0.5 再 Play → 行为随值变化（注入真的在读文件）；
- [ ] 真机：`cargo run`（编辑器外）同一配置文件同一行为（抽查一次，schema flag 不可用，用窗口截图/或
  headless 组合由 QA 定驱动方式，如实留档）。

**测试设计**：runtime crate 新模块单测（`ConfigLoader` 机制层）+ guards 新
`tests/guards/config_injection.rs`（编辑器↔游戏往返用例，复用 scaffolded_component_flow.rs 的
fixture 模式）；真机脚本沉淀 `loop/qa/t08-config-play.ps1`（复用 t06 链的 BRP 调用模式）。
**buglist 吸收**：无打钩（P1-P3 新发现）。

### T2「作者态生命周期保护」（P4+P5+P6+W13；决策 3/4）

**目标**：堵住三态一致的静默差异洞——Play 前/导出前自动保存 dirty 资产卡片；退出保护覆盖资产编辑；
资产/资源编辑不再污染场景 tab 脏标；保存失败有真警告色。

**改动面预估**：
1. **脏标隔离（P5，决策 4-A）**：`jackdaw_commands::EditorCommand` trait 增加虚方法
   `touches_scene_document(&self) -> bool { true }`；`SetDefinitionField`（`definition_assets.rs:740`）与
   `ResourceInsert/ResourceRemove/ResourceSetField`（`src/inspector/resource_commands.rs`）覆写返回
   `false`；`CommandHistory` 增加「只计 touches 命令的 push 计数器」，`active_tab_modified`
   （`scenes/operators.rs:748-761`）与 T03 per-tab watcher 的 `observed_pushes` 比对改用过滤计数器。
   **undo 栈本身不动**（资产/资源编辑仍可 Ctrl+Z——它们本就落在全局栈）；
2. **Play/导出前保存资产腿（P4，决策 3-A）**：`save_scenes_before_launch`（`pie.rs:965-982`）函数内加一段：
   遍历 world 中 dirty 的 `DefinitionAssetEdit` → `save_indexed_asset`（`definition_assets.rs:1273-1291`
   现成）→ 失败者进 failures 拒绝 Play/导出（对齐场景保存失败语义，文案 "could not save <asset>"）。
   两调用方（`pie.rs` Play 链 + `game_export.rs` 导出链）免费受益；函数文档注释更新（"scenes and open
   definition assets"）；
3. **退出保护（P4 腿）**：T04 关闭确认对话框的触发条件加「或存在 dirty 资产卡片」
   （`open_card_has_unsaved_edits`，`definition_assets.rs:667`——本任务终于给它接上消费者）；对话框文案
   列出未保存资产名（逐 tab 列表旁加一行）；T04 N9 真机矩阵加一格走查；
4. **W13 顺手修**：`notify_warn` 真警告档（`src/status_bar.rs:127-129,365-374`——加 warning 色级或最小
   实现 `notify(world, text, true)` 恢复 TEXT_WARNING 分支）+ 一条文案测试；本任务所有「保存失败」提示
   走它；
5. **journal 边界（P6，决策 3 附带裁定=不做）**：crash journal 不扩资产（结构变更风险>T08 收益，退出
   对话框+Play 前保存已覆盖主要丢失面）——book 如实记边界，挂 open-challenges。

**验收标准**：
- [ ] headless 红→绿①（P5）：场景 tab clean → 编辑资产字段（asset.set 未 save）→ tab **仍 clean**
  （红证=main 上同操作 tab 变 dirty，`jackdaw/status` 或 dirty_matrix 断言）；同操作后 Ctrl+Z 恰撤资产
  编辑一条（undo 能力不回归）；资源面板 `resource.set_field` 同用例；
- [ ] headless 红→绿②（P4 保存腿）：dirty 资产卡 + Play（Save 态）→ 盘上资产文件=卡片最新值
  （红证=main 上盘上旧值）；保存失败注入（只读目录）→ Play 被拒 + 状态栏真警告色文案；
- [ ] headless：dirty_matrix（T03 14 格）全量回归零变化——过滤计数器不破坏既有指纹语义；
- [ ] 真机：dirty 资产卡 + `pie.play_current` → `jackdaw/pie` running + 盘上资产新值 + stop 后卡片
  clean；**N10 组合回归**（dirty 场景+dirty 资产卡+Save 态 Play——保存链+PIE 启动同帧组合是 N10 冻结
  前科区，必跑，复用 n10-qa 的 dirty+Save 一步回归脚本扩一腿）；
- [ ] 真机：退出走查——dirty 资产卡 + WM_CLOSE → 确认对话框出现（`ui_tree` 断言）且列资产名 → Cancel
  留存 → Save All/确认后盘上新值；
- [ ] 真机：导出腿——dirty 资产卡 + `game.export` → `jackdaw/export` ready + dist 内 `game-config.bsn`
  值=新值（三态③的直接保障，T3 矩阵格 7 复用）。

**测试设计**：guards 扩展 `dirty_matrix.rs`（资产/资源编辑不置脏两格）+ 新
`tests/guards/asset_lifecycle.rs`（保存腿/退出条件 headless）；真机脚本沉淀
`loop/qa/t08-lifecycle.ps1`。**buglist 吸收**：W13 打钩。

### T3「三态一致验收矩阵 + 文档收尾」（P7+P8；决策 5/6）

**目标**：验收句「生命值/移速/重力等重启+Play+导出三态一致」的终验矩阵（全 BRP/MCP 驱动）；会话态/
作者态边界的文档钉死；book + buglist 核对 + roadmap 勾选。

**改动面预估**：
1. **真机验收矩阵**（截图+日志留档 `loop/reports/`，模板工程为 fixture）：

| # | 场景 | 期望 |
|---|---|---|
| 1 | 编辑器创建+编辑+保存配置资产 | `asset.new_picker(kind=game_config)` 创建 → `asset.set` 三字段 → `asset.save` → `asset.get` 读回一致 + 盘上文件含同值（bsn 文本断言） |
| 2 | **三态①重启编辑器** | kill/关闭→重开工程→`asset.get` 同值；双击资产打开卡片显示同值；rename 后引用与卡片路径联动（T05 回归） |
| 3 | 三态②组件腿（回归） | SpinningCube.speed 编辑→Play 行为变化（T02/T06 既有链，证明组件参数腿无回归） |
| 4 | **三态②Resource 腿** | `game-config.bsn` 改 move_speed/gravity → `pie.play_current` → `scene_snapshot` 两帧 Transform 差与配置值一致；改值重 Play 行为随之变 |
| 5 | Play 中编辑器再改（未保存） | 运行中游戏仍按盘上值（文件即真相）；卡片 dirty 可见；stop 后 `asset.save` 生效 |
| 6 | Stop 还原（回归） | T06 Stop 铁证链复跑：scene_bsn/盘上 SHA 不变、dirty/栈深不变、temp 副本清理——配置链零污染 |
| 7 | **三态③导出** | dirty 资产卡+`game.export` → `jackdaw/export` ready → dist/assets/game-config.bsn 值=编辑值 + `export-manifest.json` 含该文件（T07 manifest 复用） |
| 8 | 导出产物自含 | T07 heavy smoke（tests/export.rs）扩展一格：fixture 带 game-config.bsn → dist 断言存在+内容一致（staged exe 的值级行为验证成本高，以文件一致性+T7 矩阵 cell 7 已验的挪盘链覆盖，如实记档） |
| 9 | 会话态边界（负面断言） | Resources 面板改一个会话资源（如 Time<Virtual> 或游戏 Resource）→ 不落盘（`asset.list`/文件系统断言零新文件）→ 重启编辑器回默认；面板常驻「session only」提示在（ui_tree 断言）——**「与 Resources 面板区分」的字面验收** |
| 10 | 存量工程接入 | my-game（或 bsn_game fixture）加 derive+注册两行 → schema 刷新 → 同链格 4 复跑（Play 腿） |

2. **book 文档**：新节「Game parameters」（或并入现有 authoring 节）：三种载体对照表（场景内组件=实体级
   / 配置资产=全局 Resource 初值 / Resources 面板=编辑器会话调试）、配置资产工作流（New Asset→编辑→
   Save→Play/导出）、`ConfigLoader` 用法与约定、缺文件回落语义、journal 边界（资产编辑不入）、模板示例
   导览；T08 的 Resources 面板行为在 remote-debugging/Resources 相关页补一句指向；
3. **工具面核对（MCP 优先原则评估结论）**：现有 22 BRP 方法+25 MCP 工具**足够**——`asset.*` 九 op
   （call_operator 驱动）+ `jackdaw/pie`/`scene_snapshot`（行为断言）+ `jackdaw/export`（三态③）+
   `jackdaw/history`（undo 面）+ `jackdaw/wait`/`status`；**不新增工具**。若 QA 实跑发现
   `scene_snapshot` 两帧采样表达不便，允许立项最小增强（如 wait 帧/时间参数），按 MCP 优先流程走，
   不硬耗；
4. buglist 打钩核对（W13）；roadmap T08 勾选；台账记行。

**验收标准**：
- [ ] 矩阵 10 格全过（BRP 日志+截图留档）；
- [ ] 全量门（`xtask fast`/`integration`/docs/doctests）按 2026-10-25 升级版门禁证据标准（日志全文复核、
  重跑覆盖归档）；
- [ ] 用户 30 秒清单：①模板工程里打开 game-config（Project 窗口双击）把 move_speed 从 1 改 2，Save，
  Play——转得明显快一倍；重启编辑器再 Play 还是快的；②Build Game… 后双击 dist 里的 exe——一样快；
  ③Resources 面板随便改一个值，重启编辑器——它回默认了（会话态边界，预期行为）。

**QA 清单（放行标准，全任务）**：
- [ ] T1/T2/T3 各自验收全绿；每个 🔴（P1/P4）与 P5 有红→绿测试（红证=main 上可复现的旧行为）；
- [ ] 「三态一致」铁证：格 2/4/7 三腿各有独立断言（文件值+行为+dist 内容），且格 5 证明「未保存不入
  游戏态」、格 9 证明「会话态不入任何文件」——正向与负向都钉死；
- [ ] N10 组合回归（dirty 场景+dirty 资产+Save 态 Play）真机不冻结；
- [ ] T03 dirty_matrix/T06 Stop 铁证/T07 导出 heavy 三条既有防线全量回归；
- [ ] quick 门（T1/T2）/ 全量门（T3）；门禁证据以日志全文复核为准。

---

## 三、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **配置的载体形态** | A=**独立配置资产**：游戏类型 `#[derive(Asset, Resource, Reflect, Default, Clone)]`，assets 下 `.bsn` 单值文件（definition assets 形态）。复用面最大：编辑器 New Asset/卡片/asset.* op/write_atomic/T05 rename+audit 全链免费；「与 Resources 面板区分」=资产卡片即作者态、面板即会话态，边界天然清晰；文件即真相→Play/导出/重启三态一致性是**结构保证**而非逐点修补。代价：存量游戏类型要加 derive+注册两行（文档给出）。B=场景内配置实体（GameConfig 组件挂根）：零新机制（T02/T06/T07 已闭环），但 Resource 语义（重力/时间缩放这类**引擎 Resource**）无法组件化、每场景一份不共享、验收句「游戏 Resource 初值」落空。C=Resource 注册表持久化（把 Resources 面板编辑序列化进场景文档/独立文件）：需新序列化格式+面板语义翻转（推翻功能#1 已验收的会话态设计），引擎 Resource 跨工程类型匹配脆 | **A 为主，B 保留为既有组件参数路径**（B 是现状、零建设，与 A 并存互补：实体级参数用组件、全局参数用配置资产——book 对照表写清）；C 不做，挂 open-challenges |
| 2 | **runtime 注入机制（Play 怎么拿到参数）** | A=**`ConfigLoader<T>` 泛型组件+通用系统**：游戏 spawn 一行，路径显式（约定 `game-config.bsn` 可缺省）、缺文件 default+warn 兜底、一次/进程。与 T06 `JACKDAW_PIE_SCENE` 同为「编辑器侧零协议」但更简单——**参数不需要 env/协议：配置文件本来就在 assets 里，Play(`BEVY_ASSET_ROOT`=项目根)/cargo run/导出 exe 三种启动读同一文件**。B=JackdawPlugin 全自动（约定名自动 init 所有 Asset+Resource 双 derive 类型）：零游戏代码但魔法约定、多配置组合与显式性差、误 init 风险。C=Play 时 env/ControlEvent 注入编辑器面板值：与文件双源、导出链断裂（dist 无 env）、违反三态一致——否决 | **A**（教学透明+显式；B 的约定路径缺省可作为 A 的糖——`ConfigLoader::<T>::default_path("game-config.bsn")`，非必须） |
| 3 | **dirty 资产卡片的 Play/导出/退出保护** | A=**三腿全做**：Play/导出前自动保存（进 `save_scenes_before_launch`，失败拒绝）+退出对话框覆盖（`open_card_has_unsaved_edits` 接上消费者）+journal 不扩（边界如实记录）。与场景 tab 同等待遇，「编辑器所见=游戏所跑=发布内容」成为不变量。B=仅警告不保存：不打断但差异仍在，验收句不成立。C=维持现状：P4 🔴 原样 | **A**；journal 不做的理由：T04 journal 是 per-tab 场景文档结构（含 view-state/history 快照），资产是另一形态（值在 AssetIndex），扩它=结构变更+崩溃恢复语义复杂化，退出对话框+Play 前保存已覆盖主要丢失面——book 记边界，挂 open-challenges |
| 4 | **资产/资源编辑与场景 tab 脏标的隔离** | A=**`EditorCommand::touches_scene_document()` 虚方法+过滤 push 计数**：默认 true（既有命令零改动），文档外命令（SetDefinitionField/资源三命令）返回 false；`active_tab_modified`/per-tab watcher 改用过滤计数。脏标回归「只反映场景文档内容」的 T03 本义；同时治了资源面板编辑弄脏场景 tab 的既有小病。B=资产编辑独立小历史栈：与「Ctrl+Z 在 active tab 栈可撤资产编辑」的现状语义分裂，栈切换成本高。C=容忍现状（保存一次清掉）：脏标长期误导+假保存 | **A**（改动集中在 `jackdaw_commands`+两个判脏点；dirty_matrix 14 格全量回归护航） |
| 5 | **会话态/作者态的可发现性桥** | A=**文档+文案微调**：Resources 面板会话态提示句尾加「持久化请用配置资产（New Asset）」类指向（改 `resources-session-only` 文案一处）；book 对照表；不做新 UI。B=面板加「Pin as config asset」按钮（把当前面板值导出成配置资产文件）：心智桥最短，但只对 Asset+Resource 双 derive 类型可行、面板值→资产文件的映射语义（哪个文件/新建还是合并）复杂，且与「面板是调试面」的定位冲突 | **A 首版**；B 挂 open-challenges（T25 Live 调参「预览差异→应用/放弃」时一并考虑，彼时才有值回写需求） |
| 6 | **「Play 后 Resource 生效」断言通道** | A=**行为断言**：模板示例参数刻意选可观察行为（move_speed→旋转/移动速率、gravity→下落速率），`scene_snapshot` 两帧 Transform 差断言；零新工具。B=PIE 协议扩 Resource 流/查询：结构化最直接，但协议+两侧实现的改动面大，且运行时值回读是 T25 Live 调参的需求本体——提前做会与 T25 撞车。C=游戏侧 BRP（15702）读运行值：被 Y33(CORS)/N12(域不通) 挡+依赖游戏自愿开 BRP | **A**（模板示例字段设计已配合：三字段都有可断言行为或存在性断言）；B 挂 T25 候选；C 不取（Y33 备注维持） |

另有小定案（主控可否决）：方案内编号 P1-P8（与 buglist N 系区分）；模板示例字段定
`player_health/move_speed/gravity` 三件套对齐验收句例示；`ConfigLoader` 命名与
`jackdaw_runtime::PIE_SCENE_ENV` 家族同居 prelude。

---

## 四、风险与回滚

| 风险 | 缓解 |
|---|---|
| `ConfigLoader<T>` 泛型系统在 bevy 的注册/调度边角（泛型 Component 的 system param 推导、`Asset+Resource` 双 trait 约束的反射面） | T1 首批就是 runtime crate 机制层单测；若泛型注册受阻，回落形态=模板内联两行加载系统（零 runtime 抽象版，教学透明度反而更高）——保底路径在方案内写明，程序报告需先试 A 再回落并说明 |
| `touches_scene_document` 改 `CommandHistory` 计数器，波及 T03 per-tab 指纹/watcher 既有语义 | dirty_matrix 14 格+undo_history/record_counts 全量回归为放行条件；过滤计数器是**新增**计数而非改旧字段（`total_pushes` 原语义保留），旧消费者零改动 |
| Play 前保存腿新增「保存资产+PIE 启动」同帧组合——N10 冻结前科区（已修但有次嫌疑在档） | T2 验收必含 N10 组合回归（dirty 场景+dirty 资产+Save 态 Play），复用 n10-qa 脚本扩腿；若触发，按 N10 档案次嫌疑两条优先排查（drain 预算路径） |
| 模板变长（GameConfig+FallingCube）影响 scaffold 测试基线与新用户体验 | scaffold 测试族同步扩展；模板 doc 结构化（Try it/Adding components/Tuning parameters 三节）； FallingCube 控制在 ~8 行 |
| schema-backed 资产对旧 schema/未 Rebuild 工程不可见（`AssetKinds` 无该 kind → New Asset 不显示） | 属既有 Rebuild 流程语义（改游戏代码本就需要 Rebuild，模板注释已有）；book/Try it 写明「Rebuild 后出现」；矩阵格 1 前置 Rebuild 步骤 |
| 编辑器↔游戏资产文件形态漂移（emit/parse 两侧各自演化） | T1 往返一致性用例（编辑器 emit 形态→runtime 读）常驻 guards，形态破裂即红 |
| 退出对话框条件扩展影响 T04 N9 已验收矩阵 | 矩阵加一格走查+原 11 格回归；对话框族 T04 已验过，改动仅条件与文案 |
| 回滚 | 三任务独立成分支段：T1 runtime helper+模板（revert 即回无配置链现状，零格式变更——配置资产文件是用户数据、-schema kind 自动消失不残留）；T2 三处局部修（trait 虚方法默认 true→revert 无痕；保存腿/对话框条件各自独立）；T3 纯矩阵+文档。全程零场景格式变更、零协议破坏（新组件/新命令均为加法）——与 T05/T06/T07 同款最大回滚保险 |

---

## 五、与 T01-T07 已建设施的衔接

1. **T02（组件三处一致）=组件参数腿的地基**：矩阵格 3 直接回归其灯色/Transform 链；T08 不重复建设，
   只在 book 把「组件参数 vs 配置资产 vs 会话面板」三载体对照表写清（T02 的可发现性成果——分类
   tooltip+标头——对 GameConfig 卡片同样生效，schema-backed 字段走 schema_fields.rs 既有渲染）。
2. **T03（undo/脏标）=T2 脏标隔离的基座**：`touches_scene_document` 是对 T03 per-tab 指纹体系的**收窄补
   全**（pushes 粗筛从「所有命令」收窄到「场景文档命令」，指纹精确层不动）；dirty_matrix/record_counts/
   undo_history 三套 guards 全量回归是放行条件；资产编辑的 undo 语义（进 active tab 栈、Ctrl+Z 可撤）是
   既有现状，T08 保持不另造。
3. **T04（保存/journal/恢复对话框）=写盘与退出保护的基座**：资产写盘已走 `write_atomic`+幂等（本就同
   族）；退出对话框复用 confirm_dialog 族（N9 矩阵加一格）；journal 边界如实记录不扩（决策 3）。
4. **T05（引用稳定性/AssetIndex/audit）=配置资产的治理面**：rename/move 已联动 `DefinitionAssetEdit.path`
   （Y8 备注）；配置资产天然入 AssetIndex/audit/referrers 面 audit 的 Missing 检查对其同样生效——矩阵格 2
   顺带回归；场景引用配置资产用既有 `@stem`/路径引用（`JackdawCatalog` 两键），无需新引用形态。
5. **T06（PIE 换把/Stop 铁证/pie 工具）=Play/Stop 语义与断言通道**：配置资产与 `JACKDAW_PIE_SCENE` 平行
   不相交（场景换把只动场景 handle；配置文件恒从 assets 正本读——T1 有用例钉死）；Stop 铁证链（SHA 双腿
   +temp 清理）在矩阵格 6 回归，证明配置链零污染；`jackdaw/pie`/`scene_snapshot`/`selection.set` 直接复用。
6. **T07（导出/manifest/--locked）=三态③的验证工具**：`jackdaw/export`+`export-manifest.json`（格 7 断言
   manifest 含配置文件）；heavy smoke（tests/export.rs）扩展格 8；过滤名单不含 `.bsn` 正本（只排
   `.bak/.jackdaw-pie/` 等），配置资产进包无需改导出——这是「文件即真相」载体选型的直接红利。
7. **对 T09-T20 的奠基**：T09 Input Action 配置保存（动作表可作配置资产同族）、T11 玩家控制器「关键参数
   Inspector 可调」、T16 音量三类控制、T17 玩家设置（与场景分离的持久数据面）、T19 画质游戏输出一致、
   T20「主要靠编辑器配置完成」——全部消费 T08 的「配置资产+注入链」模式；T25（Live 调参）将来在
   `ConfigLoader` 的一次/进程语义之上做热重载，接口边界已留（决策 6-B 挂档）。
8. **分支与行号基线**：本方案行号基于 main 6119a066（T07 闭环点）。T08 从 main 拉 `loop/t08-game-params`
   （三任务分段续用同分支族，T06 先例）；行号按符号名重定位（矩阵证据均已给符号名）。
