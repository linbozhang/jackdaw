# T13 启动场景、场景列表与切换 — 实施方案

> 策划产物（2026-10-28，基于本地 main **28eaf410**（T12 收官合入）全量只读调研：编辑器
> src/（scenes/pie/pie_current/project/project_select/project_settings/game_export）、
> crates/（jackdaw_runtime / jackdaw_project_build / jackdaw_cli / jackdaw_scaffold /
> jackdaw_pie_protocol）、bevy pinned fork `/Users/zhanglinbo/workspace/bevy-fork-pinned`
> 的 bevy_state / bevy_ui / bevy facade feature 表实读；不建分支、不改代码）。
> 需求来源：`loop/plans/roadmap-game-dev.md` T13（P1 第七项，T08-T12 已闭环）。
> **验收原文**（roadmap 第 27 行，逐字核实）：「**启动场景+构建场景清单+运行时切换+跨场景
> 对象规则。验收=菜单↔关卡↔结束往返无残留/重复加载；导出从指定场景启动。**」
> 拆解（策划口径，供矩阵与验收对齐）：「启动场景」=游戏进程开场加载哪张场景文档的
> **项目级配置**（编辑器 Play「启动场景跑」/`cargo run`/导出双击三形态同源，pie_current
> 的「当前场景」是另一条轴，见决策 7）；「构建场景清单」=项目声明「哪些场景构成这个游戏」
> 的清单面（Unity Build Settings → Scenes In Build 的对应物）——可作者、可校验、导出核对；
> 「运行时切换」=游戏进程内把一张场景文档的实体整体替换为另一张（**真·文档切换**，不是
> T12 的同文档显隐切屏，两线关系见 §二）；「跨场景对象规则」=「谁随场景亡、谁跨场景存」
> 的机制边界+教学（首版=规则文档+模板演示，不做 DontDestroyOnLoad 级机制，决策 8）；
> 「无残留/重复加载」=切换后旧场景实体/观察者/绑定上下文零残留，多轮往返后实体计数、
> 事件分发、资源面与单轮恒等；「导出从指定场景启动」=staged 产物双击启动进入配置的启动
> 场景（改配置→重导→变，T12 格 9 的五点链同款铁证）。
> buglist 场景/tab/journal 域**零直接条目**（全量扫描：Y8 tab retarget 已修、Y9 project.json
> 原子写已修、W2 多 UI 根测量、N10 已修、N13 PIE panic 挂账——见 §一重叠表）；缺陷主体是
> 本方案新发现的 **S1-S8**（S 系：Scene flow，避开 buglist R/Y/W/A/N 系与 T08 P、T09 I、
> T10 F、T11 C、T12 U 系）。真机口径：**macOS（本机）**，bash+curl+jq 驱动编辑器 BRP 与
> 游戏 BRP 15702（`loop/qa/t12t3-live-chains.sh` 形态复用）；**勿设 RUST_BACKTRACE**
> （T11-T3 §八-3 口径）；N13 按 T11/T12 口径绕行+记数；warn 形态扫描（`cannot apply|
> cannot read|does not read as|UnresolvedTypes`）入常备腿；门链与编辑器/游戏不同窗
> （T12-T3 §九-7）。

---

## 0. 架构事实（核实结论，方案的地基）

**总判断：编辑器的多场景「会话面」（tab 开关切/持久化/恢复）与运行时的单场景「装载面」
（JackdawSceneRoot 全链+集成测试）都已是成品；缺的是两者之间的**项目级游戏流面**——
启动场景配置、构建场景清单、运行时切换原语、跨场景对象规则四件事**全部不存在**，但每件
的地基都在场，T13 是「把三块已建成面缝合出一个新面」，不是建新系统。** 九条事实：

- **事实一：编辑器多场景会话面是成品。** `Scenes { tabs, active }` 资源持有 tab 列表
  （`src/scenes/mod.rs:87-91`），tab 内容=场景文档 AST 快照+视图态+历史（`:133-184`），
  激活切换走 `swap_active_tab`（`src/scenes/swap.rs`，捕获/复活语义）；operator 面
  `scene.new`（kind=3d/2d/ui，`src/scenes/operators.rs:57-109`）、`scene.open`
  （`:183-226`，含已开 tab 原位激活+重读策略）、`scene.switch tab=N`（`:680-698`）、
  `scene.close`（`:590-634`，脏 tab 对话框）、`scene.save_all`（`:700-726`）、
  `scene.cycle_next/prev`（`:817-856`）；tab 列表持久化进 `.jackdaw/project.json` 的
  `last_open_tabs`/`last_active_tab`（`src/scenes/mod.rs:280-311`），项目打开时按序恢复
  （`src/project_select.rs:619-631`，`PendingSceneOpens` 两帧一场景）。**这些都是「编辑
  会话」概念，与游戏进程零关系**——编辑器切 tab 不会让任何游戏换场景。
- **事实二：「启动场景」概念不存在，但语义挂钩点已被 T06 备好。** 三层缺口与一个挂点：
  ①`.jackdaw/project.json` 有 `default_scene` 字段（`src/project.rs:73-75`「Default scene
  to open」）但**全仓零消费者**（grep 仅定义与测试构造 `None`）——是 JSN 时代遗留死字段，
  且语义是「编辑器打开哪张」不是「游戏从哪张跑」；②游戏侧启动场景=模板代码里的字面量
  `asset_server.load(jackdaw_runtime::pie_scene_or("scene.bsn"))`
  （`crates/jackdaw_scaffold/templates/game/src/lib.rs.template:259-262`）——每个游戏
  硬编码，项目级无处可配，导出与 direct 只能从这张跑；③编辑器 Play 下拉已有两态区分
  （T06 交付）：`pie.play`「启动场景跑」=原样启动游戏进程、**不带场景覆盖**
  （`src/pie.rs:1217-1245` `handle_play` → `launch_instance` 无 `scene_override`），
  `pie.play_current`「当前场景跑」=把在前场景经 `JACKDAW_PIE_SCENE` 换进游戏第一根
  （`src/pie_current.rs:98-106` `SceneOverrideLaunch`+`src/pie.rs:2414-2418` env 注入）。
  **「启动场景」这个概念编辑器已经在消费（pie.play 的文案与行为），只差一个可配置的来源。**
- **事实三：运行时装载机制全套在场，且「切换」的机械半成品——装载门闸让 handle 换绑成为
  no-op。** 装载链：`JackdawSceneRoot(Handle<JackdawScene>)` 根实体（`crates/jackdaw_runtime/
  src/lib.rs:461-463`，require Transform+Visibility+SceneInstanceMembers）→ Update 期
  `spawn_loaded_scenes` 只处理 `Without<SceneSpawned>` 的根（`:687-689` QueryState 过滤），
  解析文档→prefab 解析→`spawn_node` 逐根生成成员；`SceneSpawned`（`:486`）是「装载过」
  的门闸。**推论（机制缺口，S2 的核心）：对一个已 spawn 的根换绑新 handle（insert 新
  `JackdawSceneRoot`）是 no-op**——没有任何系统消费 `Changed<JackdawSceneRoot>`；PIE 覆盖
  只在首次 `Added` 时换一次（`apply_pie_scene_override` `:656-681`，`Local<bool>` 单次）。
  **清理通道双向齐备**：3D 成员随根 despawn（ChildOf 层级递归），UI 无父成员由
  `cleanup_orphaned_scene_members`（`:607-618`）下一帧按 `JackdawSceneMember.root` 孤儿
  判定清理——`tests/ui_scene_ownership.rs` 两条测试背书（含「销毁一张场景不伤另一张的
  UI 根」）；**热重载路径就是切换需要的全部机械**：`clear_modified_scene_roots`
  （`:566-594`）在 `AssetEvent::Modified/LoadedWithDependencies` 时 despawn 全部成员+
  移除 `SceneSpawned`+复位 members，下一帧 `spawn_loaded_scenes` 重实例化——**触发器
  只有资产事件这一条，切换需要的是同一套机械对「handle 换绑」也生效**（T1 的最小
  runtime 增量，决策 2）。
- **事实四：PIE 覆盖语义对运行时切换天然安全。** `apply_pie_scene_override` 只在
  `Added<JackdawSceneRoot>` 时、以最低实体序号为准换一次（`:656-681`）——游戏运行中
  despawn 旧根再 spawn 新根不会触发它（`Local<bool>` 已耗尽+新根不是 PIE 目标），PIE 的
  「在前场景」语义只在启动那一次；`pie.play_current` 的未保存场景走
  `assets/.jackdaw-pie/` temp copy（`src/pie_current.rs:31,437-486`），Stop 即清、导出
  名单过滤该目录（`crates/jackdaw_project_build/src/export.rs:48-49`）——**运行时切换与
  PIE 换场景两条轴互不越界**（S6 的错位只在「游戏怎么初始化自己的流状态」一层，见决策 7）。
- **事实五：bevy_state 是游戏默认能力，State 驱动流转的惯用法开箱即用。** fork bevy
  facade `default = ["2d","3d","ui","audio"]`，`2d/3d → default_app → bevy_state`
  （`bevy-fork-pinned/Cargo.toml:139,142,183` 与 `crates/bevy_internal/Cargo.toml:179`
  的 `default_app` 特性表），`bevy::prelude` 全量 re-export state prelude
  （`crates/bevy_internal/src/prelude.rs:103-104`）；惯用法三件在场：`States` 派生+
  `OnEnter/OnExit` 系统、`DespawnOnExit<S>(pub S)` 状态作用域实体组件
  （`crates/bevy_state/src/state_scoped.rs:145`，带 doc 示例）、`StateTransitionEvent`
  驱动的清理系统自带。**游戏侧不需要为「状态机驱动场景流」引任何新依赖。**
- **事实六：模板现状=T13 演进的改动面。** 装载序：`(spawn_scene, spawn_hud).chain()`
  在 Startup（`lib.rs.template:200`，链序防 PIE 换掉 hud 根——T12-T2 真机教训的针）；
  主场景 `scene.bsn`（:259-262）+HUD 四屏 `hud.bsn`（:580-582）两根并存；相机在关卡场景：
  模板代码给玩家挂 CameraRig（T11），`scene.bsn:2-3` 注释明言「game's camera is the
  CameraRig its code parents under the player」——**UI 场景文档单独显示时没有相机可渲染
  （S5）**；流状态=`GameState { menu, paused, game_over }` bool 资源（`:507-511`）驱动
  hud.bsn 四屏 Visibility（T12 形态）；重开复位链=`respawn_pickups_on_restart`
  observer（`crates/jackdaw_scaffold/src/lib.rs:3256`，gate `button != "restart"` return）
  +血回满+回 PLAYER_SPAWN；`pie_scene_or` 链=PIE env > 模板字面量（runtime
  `lib.rs:628-643`）。teaches 87 针（`jackdaw_scaffold/src/lib.rs:3510-3955` 六件），
  guards 229 件（`tests/guards/game_ui.rs` 等 26 文件）。
- **事实七：配置面候选盘点（决策 1 的地形图）+导出零场景语义。** 项目级可落配置的四层：
  ①`jackdaw.toml`（项目根、入库、构建管线与 run 配置的家——`ProjectManifest` 字段面
  `crates/jackdaw_project_build/src/project_manifest.rs:50-79`；run 配置同文件编辑器侧
  解析 `crates/jackdaw_pie_protocol/src/manifest.rs:15-115`，**「游戏永不解析它」是双方
  共识注释** `:8-9`，游戏依赖里没有 toml 解析器）；②`.jackdaw/project.json`
  （`ProjectConfig`，`src/project.rs:66-95`——`.jackdaw/` 是 gitignore 的本地编辑器态，
  `project.rs:131-134` 自述）；③`.jackdaw/settings.json`（编辑器偏好 read-modify-write
  面，`src/project_settings.rs:15-100`，PlaySettings/save_before_play 都在这）；④
  **assets 树=游戏唯一可读+导出自然入包的层**（运行时 `AssetPlugin` 读 assets；导出
  staging 整树拷贝 `export.rs:70-78,325-337`，`export-manifest.json` 只是收据无游戏语义
  `:148-176`；`game.export` operator 无场景参数（`src/game_export.rs:133-143`）、
  `jd export` 无场景旗标（`crates/jackdaw_cli/src/lib.rs:784-903`）——**导出对「哪些场景/
  从哪张启动」零感知，双击启动哪张全由游戏代码里的字面量决定（S1/S3）**）。另一候选：
  `catalog.bsn` 是 runtime Startup **唯一已读**的项目级文件（`CATALOG_FILE`
  `runtime lib.rs:1589,1601-1661`），但词表是资产定义（材质/网格），塞场景流语义=混词表。
- **事实八：场景实体不经 Startup 预载，切换走 AssetServer 按路径异步加载（同路径 handle
  去重）。** Startup 的资产行走只收**单值资产文档**（`load_asset_file` 对多根/带
  Children 的实体文档 return None，`runtime lib.rs:1829-1835`）——`scene.bsn` 这类场景
  不在 catalog 预载内；切换目标经 `server.load(path)` 异步加载，bevy AssetServer 对同
  路径返回同一 handle、已加载资产直接复用——**「重复加载」的机制面=句柄去重+实体计数
  守卫（ guards 断言行为），而非「磁盘 IO 不发生」**；新场景未就绪的窗口期（旧场景已
  despawn、新场景未 spawn）是黑屏帧，属可接受过渡（风险表）。
- **事实九：QA 通道齐备，四通道先例在案。** 游戏 BRP 15702（`crates/jackdaw_remote/
  src/lib.rs:21`）直接 `world.query` 游戏世界断言实体计数/组件值（T12 各 cell 同款）；
  编辑器侧 `jackdaw/scene_snapshot`+`jackdaw/pie` 工具面（T06/T07 交付）；真机脚本形态
  `loop/qa/t12t3-live-chains.sh`（STAND_CHAIN/STAND_PAUSE_SINGLE 命名腿+leg/summary 纪律）
  直接复用；headless 先例：`tests/guards/play_current_scene.rs`（play_current 全策略矩阵，
  T06）与 `crates/jackdaw_runtime/tests/pie_scene_override.rs`（env 覆盖红绿对）——
  T13 的 guards 是这两族与 `game_ui.rs` 的合流。

---

## 一、现状与缺陷矩阵

### A. 配置面（验收词「启动场景/构建场景清单」）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **S1** | 🔴 | **启动场景无处可配**：游戏开场场景=模板代码字面量 `pie_scene_or("scene.bsn")`，项目级零配置面；`default_scene` 是死字段且语义错位（编辑器打开，非游戏启动）；「导出从指定场景启动」因此在机制上不可能——三形态（Play/direct/导出）只能从模板写死的场景跑 | `lib.rs.template:259-262`；`src/project.rs:73-75`；事实二 |
| **S3** | 🔴 | **构建场景清单零面孔**：项目没有任何「这个游戏由哪些场景构成」的声明——无作者面、无校验（清单里名字拼错/文件删了无提示）、导出不核对（staging 整 assets 树照搬，`export-manifest.json` 无游戏语义）；菜单/关卡/结束的关系只存在于游戏代码与作者的脑子里 | 事实七；`export.rs:70-78`；`game_export.rs:133-143` |
| **S8** | ⚪ | **坏数据无反馈**：T13 引入清单/启动场景后，缺失/拼错/损坏的回落路径必须可见（现状范式是静默回落模板默认——`pie_scene_or` 无 env 时无声回落；`load_project_config` 损坏静默默认是 Y9 修过的前科）——本任务把 warn 面作为交付的一部分而非事后补丁 | `runtime lib.rs:632-643`；buglist Y9 备注 |

### B. 运行时切换与跨场景规则（验收词「运行时切换/跨场景对象规则/无残留/重复加载」）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **S2** | 🔴 | **运行时切换无原语无语义无测试**：已 spawn 根的 handle 换绑是 no-op（无系统消费 `Changed<JackdawSceneRoot>`）；能用的路只有游戏代码裸 despawn+spawn（可行——`ui_scene_ownership.rs` 证明清理通道通——但零测试、零教学、每游戏各写各的，双切换竞态（同帧两次切换/目标未就绪再切）无人把关）；`clear_modified_scene_roots` 的重载机械只认资产事件 | `runtime lib.rs:687-689`（门闸过滤）、`:656-681`（PIE 单次）、`:566-594`（重载触发器）；事实三 |
| **S4** | 🟡 | **跨场景对象规则未定义**：成员生命周期的事实散在代码注释（`JackdawSceneMember` doc `runtime lib.rs:471-477`「UI 根无父但随场景亡」）与两条测试里，「谁跨场景存」的规则无文档无教学——游戏态（Resource/代码 spawn 的实体）与场景态（成员实体）的边界、BindContext 随旧成员失效、跨场景重接（wire_hud 型）全靠踩；验收句有「跨场景对象规则」一词，规则面是交付而非可选 | 事实三/事实六；`runtime lib.rs:471-477` |
| **S5** | 🟡 | **UI 场景独立显示无相机即黑屏**：模板唯一相机经 CameraRig 活在关卡场景里；菜单/结束作为独立 UI 场景文档显示时没有任何相机（UI 渲染与 picking 都挂在相机上）——真·多场景流转的第一个必踩坑，机制上需要「UI 态的相机从哪来」的定案（决策 4） | `templates/game/assets/scene.bsn:2-3`；事实六 |
| **S6** | 🟡 | **PIE 换场景与游戏流状态的错位语义未定**：`pie.play_current` 把在前场景换进第一根后，游戏的流状态（以为是菜单/以为是关卡）与世界内容脱节——需要定案「游戏如何感知被换」（推荐：读 `pie_scene_override()` 初始化流状态，见决策 7）；T12 的 U5 只文档化了单文档四屏形态的边角，多文档形态是新面 | `pie_current.rs:98-146`；`runtime lib.rs:632-643` |
| **S7** | ⚪ | **重开/复位链在真切换下需重钉**：T12 的 restart 复位链（拾取重生/血回满/回出生点）是「单场景内翻 bool」形态；关卡成为真场景文档后，重开语义=「重载关卡场景+重置跨场景态」，模板复位链的触发点与量纲要重钉（T12 数字级断言迁移到新形态） | `jackdaw_scaffold/src/lib.rs:3256`；t12-final-qa §四-4 |
| — | ✅ | **正向资产（不用重建）**：编辑器多 tab 会话面全套+持久化（事实一）；运行时装载/清理/热重载机械+`ui_scene_ownership`/`pie_scene_override` 测试（事实三/四）；bevy_state 默认在场+`DespawnOnExit` 惯用法（事实五）；`pie.play` vs `play_current` 双语义+`.jackdaw-pie` temp copy 隔离（事实二/四）；导出原子 staging+manifest（T07）；guards/play_current 先例+真机脚本族（事实九） | §0 |

**统计：🔴 3（S1、S2、S3）｜🟡 3（S4、S5、S6）｜⚪ 2（S7、S8）｜✅ 六块地基**

### buglist 重叠表（场景/tab/journal/导出域全量扫描）

| 条目 | 一句话 | T13 处置 |
|---|---|---|
| W2 | 多 UI 根时画布/标尺测量口径不一致 | **不吸收**：T13 模板每态单 UI 根（菜单/结束/HUD 三文档互斥在场），不踩多根并存；buglist 维持 |
| Y8（已修） | tab retarget 在 Mac 从未生效（A3/A4 波次补修） | **知悉**：T13 编辑器作者面若按路径引用场景，走 canonical 形态，先例已修 |
| Y9（已修） | project.json 非原子写 | **知悉且回避**：决策 1 建议不把游戏流配置放 project.json（编辑器本地态，游戏不可读），Y9 教训仅作写盘纪律参考 |
| N10（已修） | dirty+Save 态 play_current 冻结 | **知悉**：T13 真机沿用 play_current 通道（格 10）；T03 教训「保存链+PIE 启动同帧」已修，矩阵照常跑 |
| N13 | PIE connected 后 drain panic | **绕行+记数**（T11/T12 口径）；真机各腿 PASS 不受扰 |
| A5/A6 | pie_log 溢出静默丢弃/prefab watcher flaky | **知悉**：格 5 的日志零增长断言按 A5 口径只计 warn/error 形态行，不数 info |
| Y28-Y30 | BSN 解析递归无上限/窄化/遍历 | **不吸收**：menu/gameover 文档用编辑器往返零 diff 钉（T12 hud.bsn 同款），不新增解析面 |
| 其余 | 无场景流/启动场景/清单域条目 | 无动作 |

> 如实报告：该域 buglist 零直接条目——多 tab 编辑会话（T04 前后波次）与运行时装载
> （fork 升级波次）都是建成面，但「游戏流」从未成为产品概念，没有用户可踩出的 bug；
> T13 缺陷主体是本方案新发现的 S1-S8。

---

## 二、T13 与 T12 单文档形态的关系（brief 第一问，先答）

**两条路线是两个正交的教学与机制层，不是二选一，演进方式是「拆分」而非「废弃」：**

- **T12 的同文档显隐切屏（hud.bsn 四屏+GameState bool）是「场景内 UI 状态机」的正解**：
  它教的是数据绑定驱动 UI（bool 翻转=整屏机制），成本一帧、无加载、绑定可断言——暂停屏/
  HUD 这类「同一世界上的覆盖层」永远该这么做。**这部分不废弃、不迁移机制。**
- **T13 的文档级切换是「场景生命周期」的教学**：菜单/关卡/结束是三个**世界**（菜单没有
  玩家与关卡实体），用可见性伪装它们的代价是全量实体常驻+伪生命周期；验收句「往返无残留
  /重复加载」字面要求的就是真文档的卸载与装载。若 T13 只加 level1↔level2 而菜单/结束仍
  是 hud.bsn 覆盖层，则「菜单↔关卡」一线根本不是场景切换，验收词被架空（决策 3-B 否决
  理由）。
- **演进落点（决策 3-A）**：`hud.bsn` 从四屏收缩为两屏（HUD+暂停屏=关卡内覆盖层，角色
  不变）；新种子 `menu.bsn`（开始屏）与 `gameover.bsn`（结束屏）成为真场景文档，进出走
  运行时切换；`GameState` 收缩：`menu` bool 退役（场景在场即菜单态）、`paused` 留任、
  `game_over` 从「显示哪屏」变「触发流转」；T12 的 guards（四屏断言/分辨率断言的 Start/
  GameOver 部分）、teaches（ui/health 两针）、book（game-ui.md 四屏表）同步重钉——这是
  本任务最大的回归面，已列入 T3 放行条件。
- **PIE 双语义保持**：`pie.play`（启动场景跑）在新形态下=从配置的启动场景（菜单）开始
  完整游戏流；`pie.play_current`（当前场景跑）=编辑器预览语义不变——T06 的区分在 T13
  获得第二个受益者。

---

## 三、分任务拆解（T1/T2/T3；无 T0 探针）

> **无 T0 的理由**（对齐 T10/T11/T12 逻辑）：T13 的两大机制问都有代码级定论——①切换
> 机械=「despawn 成员+移除 SceneSpawned+重实例化」这条链已被热重载路径与
> `ui_scene_ownership.rs` 双向背书（事实三），T1 的 runtime 增量是给既有机械换一个触发器，
> headless 红→绿在 T1 内完成；②bevy_state 能力是 fork feature 表静态事实（事实五）。
> 唯一的实现小问号（同帧 despawn+spawn 的渲染过渡帧、异步加载窗口期）不阻塞设计，属 T2
> guards 的断言窗口问题（风险表）。

### T1「运行时切换原语 + 无残留机制面」（S2；决策 2）

**目标**：`jackdaw_runtime` 提供一个最小的、机械上复用热重载链的切换原语；headless
guards 钉死「无残留/无重复加载/无重复注册」三件事，成为 T3 真机矩阵的机制半边。

**改动面预估**：
1. **runtime 新系统 `respawn_on_scene_root_change`**（~20-30 行，决策 2-A）：Update 期
   在 `clear_modified_scene_roots` 之后、`spawn_loaded_scenes` 之前链入；对
   `Changed<JackdawSceneRoot>` 且带 `SceneSpawned` 的根执行与 `clear_modified_scene_roots`
   完全相同的三步（despawn 成员、移除 `SceneSpawned`、复位 `SceneInstanceMembers`）——
   **把两处的共同机械提为一个私有函数，触发器并存**（资产事件=热重载语义不变；handle
   换绑=切换语义新增）。游戏侧切换从此是一行：
   `commands.entity(root).insert(JackdawSceneRoot(server.load("level.bsn")))`；
   doc 钉死边界：换绑保留根实体（Name/标记/根上组件），异步加载未就绪期间根空转
   （`spawn_loaded_scenes` 的就绪门闸与 `SceneRefused` 拒载路径原样生效）。
2. **guards 新文件 `tests/guards/game_flow.rs`**（headless 真插件链，runtime 测试
   `pie_scene_override.rs`/`ui_scene_ownership.rs` 的 app 形态）：
   - ①**零残留**：menu→level 一次换绑，等 settle 后断言：menu 文档实体（按 Name/marker
     查询）==0、level 实体==单载基线、`JackdawSceneRoot` 数不变、`JackdawSceneMember`
     数==level 基线、`BindFailures` 空；反向 level→menu 同断言；
   - ②**往返恒定**：menu↔level↔gameover 循环 5 轮，每轮后全实体计数/`Assets<JackdawScene>`
     len/catalog len 与第 1 轮后值逐项相等（重复加载缺陷=计数增长，机械捕获）；
   - ③**观察者单次**：按钮 `Activate` 手动 trigger 一次→`ScreenPressed` 恰到达一次
     （STAND_PAUSE_SINGLE 同款：双注册缺陷净零签名；跨场景重生成的成员 observer 随亡随生，
     全局 observer 不得重复挂）；
   - ④**绑定重接**：带 `BindContext` 接线的 UI（wire_hud 形态）在新一轮 spawn 后绑定
     resolved（`Progress.value` 跟随），旧 context 引用不残留；
   - ⑤**拒载可见**：换绑到不存在/坏文档的目标→`SceneRefused` 在根上+warn 文案含目标名
     （S8 的 runtime 半边）；换绑到加载中目标→不崩溃、就绪后正常 spawn。
3. **runtime 集成测试**（`crates/jackdaw_runtime/tests/`，`scene_root_change.rs` 一件
   3-4 断言）：换绑重载/二次换绑/refusal，guards 之外的最小回归针（对齐既有 per-file
   惯例）。

**验收标准（可执行可复现）**：
- [ ] headless 红→绿①（原语）：无 runtime 增量时换绑 no-op（根上旧场景实体原封不动——
  红证钉死 S2）；有增量后换绑即重载（绿）；
- [ ] headless 红→绿②（无残留/恒定）：五轮循环计数恒等+零残留断言全绿；
- [ ] ③④⑤ 全绿；既有 `ui_scene_ownership`/`pie_scene_override`/热重载相关测试零回归
  （机械提取是等价重构+新触发器，放行条件）；
- [ ] quick 四门（fmt/clippy 全仓/单测/集成）。

### T2「配置面 + 导出面」（S1+S3+S8；决策 1/6）

**目标**：「启动场景+构建场景清单」落在一个**游戏可读、编辑器可写、导出自然入包**的
单一来源；编辑器有最小作者面与校验；三形态（Play 启动场景跑/direct/导出）同源启动。

**改动面预估**：
1. **流清单文件（决策 1-A）**：`assets/game.flow.json`——`{"start_scene": "menu.bsn",
   "scenes": ["menu.bsn", "scene.bsn", "gameover.bsn"]}`（路径=assets 相对、`/` 分隔；
   `scenes` 缺省视作「仅 start_scene」）。选 json 因 `serde_json` 已是 runtime 依赖
   （`crates/jackdaw_runtime/Cargo.toml:67`）；**不放 jackdaw.toml**（游戏不可读 TOML、
   导出不入包）、**不放 project.json/settings.json**（`.jackdaw/` 编辑器本地态，gitignore
   +不入包，事实七）。
2. **runtime 读取链（~40-60 行）**：`jackdaw_runtime::flow::start_scene_or(fallback)
   -> String`——Startup 早期读 `assets/game.flow.json`（损坏/缺字段→warn+fallback，S8）；
   优先级钉死文档：**`JACKDAW_PIE_SCENE`（play_current 覆盖，既有机制）> game.flow.json
   的 start_scene > 调用方 fallback**——模板改为
   `asset_server.load(pie_scene_or(&flow::start_scene_or("scene.bsn")))` 一行换字面量为
   配置。清单的 `scenes` 在 runtime 首版**只读不强制**（游戏不必声明也能跑；清单的消费
   主体是编辑器校验+导出核对+文档）。
3. **编辑器作者面（决策 6-A，最小）**：
   - operator `game.set_start_scene path=<assets 相对>`：写 game.flow.json 的
     `start_scene`（read-modify-write，缺文件创建；原子写走 T04 的 `write_atomic` 纪律）；
   - Project 窗口对 `.bsn` 场景文件右键加「Set as Startup Scene」+ 当前启动场景标识
     （项目窗口已有文件列表与右键菜单面，`src/project_window.rs` 域）；
   - BRP 面：`jackdaw/game_flow` 读方法（start_scene+scenes+盘上存在性），QA 与未来
     UI 的结构化口（MCP 优先原则：真机验收「改配置→启动场景变」走这条，不土法编辑 json）；
   - **校验 warn（S3 的编辑器半边）**：项目打开时与 flow 文件变更时核对 start_scene 与
     scenes 逐项在盘上存在，缺→状态栏 warn（文案含路径），不弹窗不阻塞。
4. **导出核对（决策 7-A，零 staging 改动）**：`game.export`/`jd export` 在导出前读
   game.flow.json：start_scene 缺失或不在盘上→导出继续但结果 warn（「导出已生成，但启动
   场景 X 不在盘上，游戏将以模板默认场景启动」）；清单 scenes 缺项→同款 warn 逐项列出。
   **不改 staging/manifest 结构**——game.flow.json 在 assets 树里随整树自然入包并被
   manifest 收编（事实七），`jd export` 与 `game.export` 两入口同一段校验函数。
5. **scaffold 种子+teaches**：新工程模板 assets 带 `game.flow.json`
   （`{"start_scene": "menu.bsn", "scenes": ["menu.bsn","scene.bsn","gameover.bsn"]}`，
   与 T3 的三文档对齐）；teaches +1 针
   `new_game_project_teaches_the_scene_flow_pattern`（needle：game.flow.json 在场+
   start_scene 键+`flow::start_scene_or` 调用+三文档名）；87→88。

**验收标准**：
- [ ] headless 红→绿①：无 game.flow.json 时 direct run 从模板 fallback 启动（现状）；
  有且指向 `menu.bsn` 时从 menu 启动（runtime 测试+guards）；
- [ ] 优先级红绿②：game.flow.json 与 `JACKDAW_PIE_SCENE` 并存时 PIE 覆盖赢
  （`pie_scene_override.rs` 同族新针）——play_current 语义不破；
- [ ] 编辑器链：`game.set_start_scene`/右键→json 落盘（原子写）→`jackdaw/game_flow`
  读回一致；拼错路径→warn 可见（文案原文归档）；
- [ ] 导出链：flow 指向存在的场景→导出零 warn；指向缺失场景→导出成功+warn 原文；
  staged 树含 game.flow.json 且在 manifest files 里（盘上核）；
- [ ] teaches 88/88；quick 四门。

### T3「模板三文档演进 + 真机矩阵 + book」（S4 文档半+S5+S6+S7；决策 3/4/5/8）

**目标**：新工程=菜单场景启动→Start 真点击进关卡（真切换）→血尽进结束场景→Restart
回关卡，往返零残留；导出从指定场景启动；跨场景对象规则成文成针；T08-T12 防线全绿。

**改动面预估**：
1. **模板文档**：新种子 `assets/menu.bsn`（开始屏：全屏遮罩+标题+Start 按钮，`Action`
   绑定 `ScreenPressed{button:"start"}`，T12 同款形状；根带 `MenuRoot` 标记）与
   `assets/gameover.bsn`（结束文案+Restart 按钮 `button:"restart"`，`GameOverRoot` 标记）；
   `hud.bsn` 收缩为 HUD+暂停屏两屏（Start/GameOver 屏摘除），`UiSceneRoot`/布局纪律/
   绑定形状不动；**种子以「编辑器打开→Save→重开→Play 往返零行为差」为验收钉**
   （T12 hud.bsn 同款，漂移以编辑器产物为准回写）。
2. **模板 lib.rs.template 流段（~80-100 行，对齐既有教学密度）**：
   - `GameFlow` States 枚举 `Menu/Level/GameOver`（决策 5-A，bevy_state 默认在场，事实五）
     +`init_state`；OnEnter/OnExit 驱动：
     `enter_menu`（spawn 主根=menu.bsn+UI 相机）、`enter_level`（spawn 主根=scene.bsn+
     spawn_hud 链序保持「主场景第一」的 PIE 纪律）、`enter_game_over`（spawn 主根=
     gameover.bsn+UI 相机）——**切换动作=T1 原语的一行换绑**，根实体跨场景复用
     （Name/标记稳定，教学直白）；`ScreenPressed` observer 改为翻 `NextState<GameFlow>`
     （start→Level、restart→重置运行态后→Level）；`update_game_over` 血尽→
     `NextState::set(GameOver)`（game_over bool 退役）；
   - **UI 相机（决策 4-A）**：`OnEnter(Menu/GameOver)` spawn `Camera2d+IsDefaultUiCamera`
     并挂 `DespawnOnExit(...)`（状态作用域实体，bevy_state 惯用法、fork
     `state_scoped.rs:145`）——关卡态由 CameraRig 独扛，无双相机双渲染；
   - **跨场景对象规则演示（决策 8-A）**：玩家/`PlayerHealth`/`PickupCount` 保留为代码
     spawn 的非成员实体（跨场景存续的教学实体）+`reset_run` 系统（OnEnter(Level)：
     血回满自 config、位置回 PLAYER_SPAWN、PickupCount 清零——T12 restart 复位链的触发点
     从按钮处理器挪到进关沿线，数字级语义不变）；场景物（拾取/危险块/hud）随根亡的教学
     写进 doc；`handle_pause_action` 的 menu 门控改 States 判式（仅 Level 态响应）；
   - **PIE 对齐（S6/决策 7）**：Startup 时 `if jackdaw_runtime::pie_scene_override()
     .is_some() { 初始态=Level }`——play_current 换进来的场景按关卡对待，世界与流状态
     不再错位；doc 一段教学注记（play=完整游戏流、play_current=预览在前场景）；
   - doc 头部「Game Flow」导览段（三文档+flow.json+States+切换一行+跨场景规则表）。
3. **guards/teaches 重钉**：`game_ui.rs` 四屏断言迁移（Start/GameOver 屏断言移入新的
   `game_flow.rs` 真机侧；HUD/暂停屏断言保留）；`game_flow.rs` 增模板级集成断言
   （三文档经 runtime 链全流程 headless 跑通：States 翻转→实体集合切换→reset_run 数字级）；
   teaches ui/health 两针按新文档面更新；guards 229→~240、teaches 88。
4. **真机验收矩阵**（Mac；bash+curl+jq；编辑器 BRP+游戏 BRP 15702+t12t3 脚本形态）：

| # | 场景 | 期望 |
|---|---|---|
| 1 | 新工程开箱=启动场景 | `jd new`+scaffold→`cargo run`/Play（pie.play）：**菜单场景先见**（Start 按钮可点）；`jackdaw/game_flow` 读回 start_scene=menu.bsn |
| 2 | **菜单→关卡** | Start 真点击→关卡世界+HUD 在场；菜单文档实体**零残留**（游戏 BRP 计数）+关卡实体=首载基线 |
| 3 | **关卡→结束** | 走到 hazard 血尽→结束场景在场；关卡实体+HUD 成员**零残留**；gameover 按钮 Action 绑定 resolved（BindFailures 空） |
| 4 | **结束→重开（往返闭合）** | Restart 真点击→关卡重载：玩家回 PLAYER_SPAWN/血满/拾取重生×3/PickupCount 0（T12 数字级断言迁移）；关卡实体计数=首次加载值（无重复加载） |
| 5 | **往返稳定性** | 菜单↔关卡↔结束循环 3 轮：每轮后实体计数/`JackdawSceneMember` 数逐项恒等；一次点击恰一次事件（STAND_PAUSE_SINGLE 同款）；日志零 warn 形态行 |
| 6 | **跨场景对象规则** | 玩家实体 Entity id 在 2→3→4 全程不变（跨场景存续）；拾取/危险块/hud 的 id 每轮更换（随场景亡）；`game.flow.json`+规则表入 book |
| 7 | 启动场景改配置三形态同源 | `game.set_start_scene`→gameover.bsn→Play（启动场景跑）/direct/`game.export` staged 独立启动**三者都从结束场景启动**→改回 menu 三者复原 |
| 8 | **导出从指定场景启动** | 格 7 的导出腿独立成格：staged exe 双击启动=flow 指定场景（像素/BRP 双证）；staged 树含 game.flow.json 且在 manifest files；**改 flow→重导→独立启动变**（五点链 T12 格 9 同款） |
| 9 | 清单校验与坏数据 | flow 指向不存在场景：编辑器 warn+导出 warn+游戏 fallback 到模板默认且 warn 文案点名（S8 三面）；修正后消失 |
| 10 | PIE 双语义 | pie.play=菜单起步完整流程；pie.play_current（关卡 tab 聚焦）=直接在关卡+流状态=Level（Start 后 HUD 在场、菜单不在场）——S6 错位不存在 |
| 11 | 编辑器再编辑闭环 | menu.bsn 双击打开（2D 画布）→改标题→Save→Play 生效→`game.export` staged 保留（T12 格 9 五点链迁移） |
| 12 | 回归根 | T09 五动作（Pause 仅 Level 态+改绑）、T10 拾取链 0→3、T11 玩家链（WASD/跳跃/跟随）、T12 HUD+暂停屏（血条 ratio/Escape 双路）在新流程下全部复跑通过；T06 Stop 铁证（Play 中切换→Stop→scene.bsn/menu.bsn SHA 不变） |

5. **book 文档**：新章 `book/src/user-guide/game-flow.md`（SUMMARY 排 game-ui 后）：
   启动场景与 game.flow.json、构建场景清单与校验、运行时切换（States+一行换绑+T1 原语
   边界）、**跨场景对象规则表**（随场景亡=成员实体；跨场景存=代码 spawn 实体与 Resource，
   过渡态自行 reset——DontDestroyOnLoad 级机制挂 open-challenges）、UI 场景的相机纪律
   （状态作用域 Camera2d）、PIE 双语义、restart 语义（重载关卡+重置运行态）；
   `game-ui.md` 交叉更新（四屏表改两屏表+指向新章）、`game-parameters.md`（config→组件
   注入链的触发点挪移注记）。

**验收标准**：
- [ ] 矩阵 12 格全过（环境降级格如实标注+替代证据链，T10-T12 口径）；
- [ ] 验收句三铁证独立证据：往返无残留/重复加载（格 2/3/4/5 四腿）、导出从指定场景启动
  （格 8 改→重导→变）、跨场景对象规则（格 6 存续/随亡双证+book 格）；
- [ ] T08-T12 防线回归（放行条件，§三-4 格 12 清单）；guards/teaches 全绿；
- [ ] 全量门（fmt/clippy 全仓/单测/集成/doctests/docs——日志全文复核标准）；物理双包
  单跑维持 T10 口径；scaffold_e2e 冷编落袋一次（模板/种子变更必致冷）。

**QA 清单（放行标准，全任务）**：
- [ ] T1/T2/T3 各自验收全绿；S1/S2/S3 各有机制层红→绿（S1 红证=无 flow.json 时启动场景
  唯一来源是模板字面量、绿=三形态从配置启动；S2 红证=换绑 no-op 实测、绿=T1 原语；
  S3 红证=拼错清单零反馈、绿=warn 三面）；
- [ ] 验收句四铁证各有独立证据（矩阵格号指认）；
- [ ] T01-T12 既有防线回归逐条指认（格 12+T2 的 PIE 优先级针）；
- [ ] quick 门（T1/T2）/ 全量门（T3）；门禁证据以日志全文复核为准；warn 形态扫描+
  N13 记数+无 RUST_BACKTRACE 三纪律在案。

---

## 四、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **流配置落点（本方案最高权重）** | A=**assets 内 `game.flow.json`**（runtime 直读，serde_json 已是依赖；导出随整树自然入包+manifest 收编，零 staging 改动；direct/Play/导出三形态**同一读取代码**；代价=assets 里多一个机器文件——doc 说明它是内容不是编辑器态）。B=jackdaw.toml `[game]` 段为源+导出物化进 staged assets+cargo run 依赖编辑器回写副本：源单一入库面好，但**两份产物必有漂移窗口**（改 toml 未回写时 direct/导出不同源——恰是 T08 三态一致验收要杀的形态），游戏不可读 TOML 是双方共识（manifest.rs:8-9）——**否决**。C=project.json+env（PIE）+导出物化：`.jackdaw/` 是 gitignore 编辑器本地态，导出/协作/CI 拿不到——**否决**。D=扩 catalog.bsn 词表：runtime Startup 唯一已读文件，但词表是资产定义，塞流语义混词表且 catalog 缺省缺席语义复杂——**否决** | **A**；命名与字段（`start_scene`/`scenes`）主控可改；`scenes` 首版只读不强制（游戏不声明也能跑），消费主体=编辑器校验+导出核对+文档 |
| 2 | **运行时切换原语形态** | A=**「handle 换绑即重载」系统**（`Changed<JackdawSceneRoot>`+`SceneSpawned`→复用热重载机械；游戏侧一行换绑；根实体跨场景稳定；与资产事件触发器并存、机械提取为私有函数）：runtime 增量 ~25 行、语义与热重载一致、最可教。B=零 runtime 改动，模板裸 despawn+spawn：机械已被 ui_scene_ownership 证明可行，但每游戏各写各的、同帧双切换竞态（despawn 旧根的命令队列 vs 两次 spawn）无单点把关、教学零抽象——作为 A 受阻回落。C=runtime `SceneSwitch` 消息+「主根」概念（按最低实体序或标记组件寻根）：API 更声明式，但 runtime 从此持有「哪根是主」的语义（PIE 用实体序约定，再立一个标记约定=两套真相），且消息时序（加载中再切）要自己排队——超出验收句必需 | **A**；B 写入方案作回落；「主根」概念留给游戏模板自己（模板记得自己的根 Entity，runtime 不记） |
| 3 | **模板演进形态（T12 衔接）** | A=**拆分**：menu.bsn/gameover.bsn 成真场景文档、hud.bsn 收缩两屏、GameState 收缩（§二）：验收句字面命中（菜单↔关卡↔结束全是真文档流转）、教学各归其位（覆盖层=绑定，世界切换=场景）；代价=T12 面重钉（guards 四屏/teaches 两针/book 四屏表+restart 链触发点）——重钉面已逐项列 T3。B=T12 不动+加 level1↔level2 演示：零 T12 回归，但菜单/结束仍非场景，「菜单↔关卡」一线不是切换，**验收词被架空**——**否决**。C=全并一文档（menu/level/gameover 全是 hud 型覆盖层+伪切换）：与「无残留」验收直接冲突（无实体可卸载）——**否决** | **A**；hud.bsn 收缩后的两屏保持 T12 全部既有断言（分辨率四档/血条 ratio/Escape 双路）不放松 |
| 4 | **UI 态的相机来源（S5）** | A=**模板代码状态作用域相机**（OnEnter(Menu/GameOver) spawn `Camera2d+IsDefaultUiCamera`+`DespawnOnExit`）：~5 行、教 bevy_state 惯用法、关卡态无双渲染（唯一相机=CameraRig）；代价=相机不在文档里（作者自建菜单想加相机得自己处理重复）。B=menu.bsn/gameover.bsn 文档内授权相机（编辑器有 Scene Camera；IsDefaultUiCamera 已 reflect 可入注册表）：场景自包含，但 UI 场景文档里放 3D 相机与画布/预览语义纠缠（编辑器 UI 画布对相机实体的处理未验证）、且关卡+菜单同帧窗口双相机——需探针。C=常驻 UI 相机（Startup spawn 一次）：最少代码，但关卡态双相机同渲 UI（双亮/双 picking）要压 order，反而复杂 | **A**；B 列为 T3 内 10 分钟探针项（若画布对相机实体无恙可改教 B，主控裁定） |
| 5 | **流状态机形态** | A=**bevy `States` 枚举+OnEnter/OnExit**：互斥天生、状态作用域实体/系统是 fork 默认能力（事实五）、headless 断言直读 `State<GameFlow>`；与 T12 的 GameState bool 并存（paused bool 继续喂 hud 绑定——绑定读不了 States 反射路径是 T12 决策 3-B 已钉的边界，不重复踩）。B=继续纯 bool（menu/game_over bool 保留驱动切换）：与 T12 连续性最好，但「互斥」靠纪律、切换竞态（血尽与 Restart 同帧）无守卫、bevy_state 在场不用=教学逆行。C=runtime 内置通用流状态机：游戏流是游戏语义，runtime 越界——**否决** | **A**；`GameFlow` 命名避撞 bevy `State`；bool 与 States 的分工（States=世界态、bool=绑定数据）写进 book |
| 6 | **编辑器作者面粒度** | A=**operator+Project 窗口右键+BRP 读面+校验 warn**（§三-T2-3）：用户有发现面（右键即见）、QA 有结构化口（`game.set_start_scene`/`jackdaw/game_flow`）、MCP 优先原则达标。B=仅 operator+BRP 无 UI：省 UI 面，但用户零发现性（功能等于不存在）——**否决**。C=独立 Game Flow 面板（清单拖拽排序+启动场景高亮）：最完整，超出验收句必需——挂账不做 | **A**；右键菜单项文案「Set as Startup Scene」；清单的 UI 编辑（增删排序）不做——手编 json+校验 warn 已够首版 |
| 7 | **PIE/编辑器与启动场景的关系** | A=**启动场景配置只影响「游戏自己跑」的三形态；play_current 语义不动**（换在前场景+游戏读 `pie_scene_override()` 把初始流状态对齐为 Level，§三-T3-2）：两轴正交、T06 语义零破坏、S6 错位消解。B=Play 下拉按清单场景生成快捷项（每个场景一个「Play from X」）：顺手，但 run 配置面（jackdaw.toml `[[run]]`）已能表达（env 无门、需新机制读清单生成 UI）——挂账不做。C=编辑器 Play 强制从启动场景跑（play_current 降级）：推翻 T06——**否决** | **A**；`jd run --config` 不加启动场景旗标（flow.json 已随项目，run 的 env 可覆写 `JACKDAW_PIE_SCENE` 已够高级用户用） |
| 8 | **跨场景对象首版范围** | A=**规则成文+模板演示**（玩家/血/计数=代码 spawn 实体跨场景存续+reset_run 沿重置；场景物随根亡；BindContext 随亡重接）：验收词「跨场景对象规则」的「规则」二字落实为可验证行为+book 规则表。B=runtime 持久标记组件（`SceneIndependent`：despawn 成员时豁免+换场景重挂）：机制扩张，当前模板没有一个真实需求需要它（玩家本来就是代码 spawn 的非成员）——**挂账**。C=只文档不做演示：验收词有「规则」，无演示的规则不可验证——**否决** | **A**；B 一句话挂 open-challenges（真需求出现再立项）；规则表里显式写「Prefab 实例与嵌套场景随宿主场景亡」（现状语义，防误解） |

小定案（主控可否决）：方案内编号 S1-S8；流文件名 `assets/game.flow.json`（字段
`start_scene`/`scenes`，路径 assets 相对 `/` 分隔）；runtime 模块 `flow`（`start_scene_or`）；
States 枚举 `GameFlow { Menu, Level, GameOver }`；菜单/结束根标记 `MenuRoot`/`GameOverRoot`；
种子文件名 `assets/menu.bsn`/`assets/gameover.bsn`；UI 相机=`Camera2d+IsDefaultUiCamera+
DespawnOnExit`；重开=Restart→`reset_run`+切 Level（T12 数字级断言原样迁移）；清单校验
warn 文案前缀 `game flow:`；teaches 针名 `new_game_project_teaches_the_scene_flow_pattern`。

---

## 五、风险与回滚

| 风险 | 缓解 |
|---|---|
| **切换过渡帧**：同帧 despawn 旧成员+新场景异步加载未就绪→黑屏/空窗数帧；加载失败（坏文档）→根空转+SceneRefused | guards 断言窗口用「update×2+等 settle」惯例（T12 同款）；黑屏过渡帧记档为可接受（不为此做预加载——资产同路径二次加载走缓存，事实八）；SceneRefused 路径 warn 点名（T1-⑤） |
| **同帧双切换竞态**（血尽与 Restart 同帧、连点两次 Start）：换绑触发器每帧合并，最后一次换绑获胜——但 despawn 成员的命令按帧落，两次换绑同帧只应产生一次重载 | T1 机械天然按帧合并（Changed 查询一帧一遍）；guards 加一条同帧双换绑断言（只重载一次、计数=基线）；模板侧 States 单点翻转（决策 5-A）从源头压竞态 |
| **T12 面回归**（hud.bsn 收缩/GameState 收缩/restart 链触发点挪移波及 guards/teaches/book 三面） | 重钉清单逐项列 T3-3；T12 数字级断言（血 ratio/Pause frozen/restart 五断言）原样迁移不放松；T12 QA 的 STAND_CHAIN/STAND_PAUSE_SINGLE 命名腿语义迁移为 STAND_FLOW（格 5） |
| **menu/gameover 手工种子与编辑器序列化漂移** | 编辑器打开→Save→往返零行为差为验收钉（T12 hud.bsn 同款）；种子用 T12 既有 bsn 形状（UiSceneRoot/面板/按钮/绑定） |
| **flow.json 手编坏数据**（坏 json/路径错/自引用） | S8 三面 warn（编辑器校验/导出核对/runtime fallback）；runtime 解析失败→warn+模板 fallback，**永不 panic**；guards ⑤+T2 坏数据腿覆盖 |
| **PIE 覆盖与 flow 的初始化时序**（`pie_scene_override()` 读 env 是进程常量，Startup 读一次即可） | 模板 Startup 读一次入资源；`pie_scene_override.rs` 同族新针（T2 红绿②）钉优先级；play_current 的 temp copy 路径（`.jackdaw-pie/`）不进清单校验范围（编辑器侧校验跳过该前缀） |
| **N13 复发**（PIE connected panic，T11/T12 实测高频） | 绕行+记数（不阻塞：错误处理器捕获，编辑器存活）；真栈仍缺（buglist 挂账，非 T13 域） |
| **Mac debug 无 RUST_BACKTRACE** | 全程不设；panic 形态证据=消息签名（T11-T3 口径）；门链与编辑器/游戏不同窗（T12-T3 §九-7） |
| **回滚** | T1=runtime 一个系统+机械提取（revert 即回现状，无调用方时零行为差）；T2=flow 读取链是纯增量（无文件=现状 fallback）、编辑器面独立 operator+菜单项、导出校验只 warn 不阻塞（摘除零痕）；T3=模板三文档+flow 段（hud.bsn 回滚到 T12 种子即回四屏形态）。全程零场景格式变更、零 PIE 协议变更、零导出 staging 结构变更——与 T05-T12 同款最大回滚保险 |

---

## 六、与 T01-T12 已建设施的衔接

1. **T06（Play 双语义/Stop 铁证）**：`pie.play` 启动场景跑获得配置来源（决策 1/7）；
   `pie.play_current` 语义不动、S6 对齐腿（格 10）；Stop 铁证扩展到 menu.bsn（格 12）。
2. **T07（导出）**：零 staging 改动，flow 文件随整树入包+manifest 收编；导出校验 warn
   复用 `game.export`/`jd export` 现有通知面；格 8 的「改→重导→变」五点链是格 9（T12）
   的直系迁移。
3. **T08（GameConfig）**：`reset_run` 沿的「config=作者意图、组件=活状态」注入链不变，
   触发点从 restart 按钮处理器扩展到 OnEnter(Level)（一格两用：首次进关与重开同路径）；
   三态一致验收方法学直接复用到启动场景（格 7）。
4. **T09（InputActions）**：Pause 动作的 menu 门控从 bool 判式改 States 判式（仅 Level
   态响应——语义与 T12 相同，形态重钉）；Interact 扣血 fallback 不动。
5. **T10（物理/拾取）**：拾取/危险块=场景成员随关卡场景亡（跨场景规则的反面教材+正面
   演示）；拾取链 0→3 与 level clear 行为在「重开=重载关卡」形态下复跑（格 12）。
6. **T11（玩家）**：玩家=代码 spawn 非成员实体，是「跨场景存续」的正例（格 6 的 Entity
   id 恒等断言）；CameraRig 随玩家跨场景、关卡相机独扛渲染（决策 4-A 的依据）。
7. **T12（游戏 UI）**：hud.bsn 收缩两屏、绑定/分辨率纪律/wire_hud 接线全部原样保留；
   `ScreenPressed` 事件与 via 库（ratio/not/is_zero）原样复用；格 9 编辑器再编辑链迁移到
   menu.bsn（格 11）；T12 的 STAND 腿语义迁移为 STAND_FLOW。
8. **T04（备份/journal）与 T05（引用稳定）**：flow.json 写盘走 `write_atomic` 纪律；
   场景文件改名对清单条目的引用影响=编辑器校验 warn 的职责（T05 的 rename retarget 不
   扩展到 flow.json——挂账一句话，warn 兜底）。
9. **对 T14-T20 的奠基**：T20 示例游戏（菜单+胜负+重开=本任务产物的拼装）；T17 存档
   （跨场景规则=「进度存 Resource 不存场景」的教学前置）；T15 动画状态机（GameFlow 的
   States 形态是另一台状态机的先例）；T24 错误定位（flow warn 是场景域的第一个可定位
   错误面）。
10. **分支与行号基线**：本方案行号基于 main 28eaf410；T13 从 main 拉
    `loop/t13-scene-flow`（T1/T2/T3 分段续用同分支族）；既存噪音 `.gitignore`/
    `buglist.md` 不触碰（提交显式 pathspec）。

---

## 七、耗时预估

| 段 | 预估 | 大头 |
|---|---|---|
| T1 | 1-1.5 天 | runtime 换绑系统+机械等价提取零回归+guards 五件（恒定计数/观察者单次两件最费） |
| T2 | 1-1.5 天 | flow 读取链+优先级针+编辑器作者面（operator/右键/BRP/校验）+导出核对两入口 |
| T3 | 1.5-2 天 | 三文档种子往返钉死+模板流段+T12 面重钉+12 格真机矩阵+book 新章 |
| 合计 | **4-5 天** | 与 T10-T12 单任务体量持平；无 T0 |
