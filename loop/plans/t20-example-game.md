# T20 最小完整示例游戏端到端验收 — 实施方案

> 策划产物（2026-10-28，基于本地 main **ca38c389**（T19 收官合入）全量只读调研：模板全家
> `crates/jackdaw_scaffold/templates/game/`（`src/lib.rs.template` 1,699 行、`src/main.rs.template`、
> `Cargo.toml.template`、`jackdaw.toml.template`、`assets/{menu,gameover,hud}.bsn.template`、
> `assets/scene.bsn`、`assets/game.flow.json`、`assets/sounds/{bgm,blip,ambient}.wav`）、模板物化层
> `crates/jackdaw_scaffold/src/lib.rs`（`module_physics_*` 七占位符 :2779-3288、`template_runtime_features`
> :2677、`scaffold_new_project` :1159）、模块目录 `crates/jackdaw_project_build/src/modules.rs`（physics
> 默认开）、运行时 `crates/jackdaw_runtime/src/{flow.rs,lib.rs,save.rs,pie_log.rs}`、游戏 BRP
> `crates/jackdaw_remote/src/lib.rs`（15702）、导出链 `crates/jackdaw_project_build/src/export.rs`
> （1,570 行）+`src/game_export.rs`、编辑器 operator 面（`src/entity_ops.rs:2678-3072`、
> `src/game_flow.rs:121-148`、`src/definition_assets.rs:1418`、`src/environment_ops.rs`）、QA 工具面
> `loop/qa/manual.md` §7+真机脚本范本 `loop/qa/t16-live.sh`/`t17-live.sh`/`t19-live.sh`、buglist.md
> 全量（75+15 条逐条过筛）。**零临时探针**——本方案的关键结论（模板=成品示例游戏、胜负链的
> 单腿缺 glue、staged 自足性、physics 默认开、编辑器配置五域面）全是静态可复核事实。
> 需求来源：`loop/plans/roadmap-game-dev.md` T20（第 34 行，T01-T19 已闭环）。
> **验收原文**（roadmap 第 34 行，逐字核实）：「**最小完整示例游戏端到端验收：开始菜单+玩家移动+
> 碰撞+拾取+胜负+音效+重开。验收=新建工程主要靠编辑器配置完成；可独立导出运行（无工具链
> 环境）。**」
> **任务定性：合成任务、严重偏验收型（约 90/10）——第六次「反转读法」的最彻底一次**：
> T09 输入/T10 物理/T11 玩家/T12 UI 四屏/T13 场景流转/T16 音频/T17 存档/T07 导出/T19 画质
> 九个已闭环任务的产品面，在**同一个新建工程的模板里已经长成一个完整可玩的游戏**——
> 新工程开箱即有 menu/level/gameover 三文档流转+代码生成的玩家/物理关卡+HUD+三音+存档
> （§0 事实一至六）。T20 的工作不是建设，而是把「合成」钉成铁证：①一条从 `jd new` 到
> staged 独立跑的**单项目全链验收**（此前各任务各自验各的域，从未在一个工程里串过全链）；
> ②「主要靠编辑器配置完成」的**度**要格化并真机走查（§0 事实七）；③「无工具链环境」的
> **隔离断言**要机械化（§0 事实九）；④一处真正的**编排 glue 缺口**（胜局不驱动流转，
> EG1——本任务唯一可能的产品改动面，决策 1）。缺陷候选按 **EG 系**编号（Example Game），
> 只记不修→主控裁定吸收面。真机口径：**macOS（本机）**，bash+curl+jq，`t16-live.sh` 全套
> 形态复用（brp/gbrp 重试、op、wait_idle、export_wait、editor_boot 的 DYLD 前缀）；**编辑器
> 启动要 DYLD_LIBRARY_PATH=工具链 lib（:36,:170），staged 游戏 exe 恰好必须**不要**它——
> 这个不对称正是「无工具链」隔离腿的断言本体（事实九）**；勿设 RUST_BACKTRACE（T11-T3
> 口径）；游戏侧数值断言全走 bevy 原生 `world.query`/`world.get_components`/`world.trigger_event`
> （N12 口径，t16-live.sh:802 先例）；A9 gbrp 自守、A10 PIE 指针绕行链、N13 记数、A7 五招
> 自守（决策 6）；warn 形态扫描入常备腿。

---

## 0. 架构事实（核实结论，方案的地基）

**总判断：T20 的「最小完整示例游戏」今天已经存在——它就是游戏模板本体。**`jd new` 出来的
每个工程自带：三文档流转的完整游戏代码（`lib.rs.template` 生成物）、四个 UI 文档、三个音效、
存档、flow 配置、默认开启的物理模块（`modules.rs:477` `catalog.defaults()=={"physics"}`）。
**开箱按 Play：菜单→Start→关卡（玩家/地面/墙/三个拾取物/危害物/掉落立方体全部代码生成）
→碰撞/拾取/扣血→血尽→Game Over→Restart 重开——这条链 T10/T11/T12/T13 各自验过腿，
但从未在「一个新建工程、一次连续操作」里作为整体验收过，也从未在导出包里整链跑过。**
T20 的第二个验收词「主要靠编辑器配置完成」则需要格化定「度」：模板=零手写代码可玩
（代码属模板，不属作者），作者侧的五域配置面（摆件/改屏/参数/流转/音频挂点）全部编辑器
可达（事实七），唯「关卡道具代码常生」是边界（事实七③、EG2）。十五条事实：

- **事实一：流转链成品——菜单/关卡/结束三文档+状态机+按钮事件，T13 闭环。**
  `GameFlow{Menu,Level,GameOver}`（`lib.rs.template:1311-1320`）；boot 三级源
  `pie_scene_or(flow::start_scene_or(MENU_SCENE))`（`:304-306`；`crates/jackdaw_runtime/src/
  flow.rs:47` `start_scene_or`、`crates/jackdaw_runtime/src/lib.rs:720` `pie_scene_or`），
  `boot_state` 把 menu.bsn/gameover.bsn 映射为 Menu/GameOver、其余任意场景映射为 Level
  （`:1326-1332`，Play-Current 双语义的机制底座）；流转=一个 `JackdawSceneRoot` handle
  重绑（`spawn_scene:458-468`、`enter_menu:1364-1389`、`enter_level:1395-1405`、
  `enter_game_over:1409-1429`）+每 UI 态自带状态作用域 `Camera2d`（`DespawnOnExit`）；
  按钮=场景文档里的 `Binding::Action` 发 `ScreenPressed{button}`（`menu.bsn.template:45`
  "start"、`gameover.bsn.template:40` "restart"/`:63` "menu"、`hud.bsn.template:92` "resume"），
  `on_screen_pressed` 观察者转流转（`lib.rs.template:1560-1585`）。**「开始菜单」与「重开」
  的机制与真机证据均已闭环**（T13 矩阵 12 格：真指针点击/三循环七元组恒等/玩家 id 三站
  恒等拾取每轮重生/导出五点链，roadmap :27）。
- **事实二：重开=状态重入，零专用逻辑，T13 闭环+真机修过 reset_run 缺陷。**
  Restart 与 Start 走同一 `"start"|"restart" => flow.set(Level)` 臂（`lib.rs.template:1571-1574`）；
  重开复位=每次 Level 重入的 `(spawn_player, reset_run).chain()`（`:409`）+
  `reset_run_counters`（物理半边，`scaffold/src/lib.rs:3278-3285`）——血量回满+回出生点
  （`reset_run:1614-1623`，`PLAYER_SPAWN:1503`）、PickupCount/PlayerVelocity 清零；关卡道具
  靠 `DespawnOnExit(GameFlow::Level)` 死于换态、重入重生成（`spawn_pickup_line:3104-3130`）。
  玩家本体跨态存活不重生成（`spawn_player:1170-1178` 的 `existing` 守卫）——T13 格「玩家
  id 三站恒等」验过。
- **事实三：玩家移动+碰撞成品，T11/T10 闭环。** 玩家=代码生成 capsule（`spawn_player`）+
  `PlayerController{move_speed,jump_speed}`（`:1145-1161`，Inspector 可调）+物理模块下五组件
  全集（Kinematic RigidBody/AvianCollider capsule 0.35×1.0/PlayerVelocity/PickupCount，
  `scaffold:2867-2883`）；`move_player` 物理形态=相机相对 Move+重力积分+地面 short-cast+
  Jump+avian `move_and_slide` 扫掠（`scaffold:2963-3034`；「不穿地 y=0.3000 零穿透」T10
  真机首证，roadmap :22）；墙=两道静态 collider（`spawn_walls:3137-3161`）——「碰撞」词的
  物理半边。已知语义边界：Kinematic 玩家推不动 Dynamic 掉落立方体（buglist A2，buglist.md
  :438-439，双机实证，设计取舍非缺陷——T20 碰撞格若踩「推箱不动」按 A2 记档不立新票）。
  编辑器手摆玩家=受支持路径（五组件清单在模板文档 `scaffold:2856-2864`，C10 教训）。
- **事实四：拾取+胜负(负)半边成品，T10/T12 闭环。** `collect_pickups`（`scaffold:3170-3193`）：
  玩家触碰 `Pickup` sensor→despawn+计数（他侧触碰不收，`:3178` 玩家判定）；计数上 HUD
  （`hud.bsn.template:51` `PickupCount.0` 绑定，T12 闭环）；三枚集齐→`info!("Level clear!…")`
  （`scaffold:3190-3192`）。**负局链完整**：`Hazard` sensor（`spawn_hazards:3217-3245`，
  CollisionLayers 0b100/0b001 只打玩家 `:3240-3243`）→`hazard_damage` 扣 15（`:3253-3270`）→
  血量≤0→`update_game_over` 流转 GameOver（`lib.rs.template:1670-1686`）→结束屏。**胜局
  只有日志没有流转**——`collect_pickups` 数到 3 打一条 `info!` 就返回，GameFlow 纹丝不动：
  集齐三枚后游戏永远停在 Level，只有去撞 Hazard 才能见到结束屏。这是本方案找到的唯一
  编排 glue 缺口（**EG1**，决策 1；见编排缺口清单）。
- **事实五：音效三挂点+三类 bus 成品，T16 闭环。** 模板自带三音：菜单 BGM
  （`menu.bsn.template:52-58` `MenuBgm` bgm.wav Loop+MusicBus——**场景作者组件挂点**的
  活标本）、按钮确认音（`press_sound:1594-1602`，blip.wav 一次性 DESPAWN+SfxBus，每个
  ScreenPressed 臂都响）、关卡空间音（`scene.bsn:17-27` `Ambient` ambient.wav spatial=true，
  SpatialListener 挂玩家相机 `lib.rs.template:1202`）；`GameAudioConfig` 三路 mix
  （`apply_audio_mix:599-641` 追认已播 sink）+`SoundLive` 镜像可读（`:692-769`）——
  BRP 断言面现成（t16-live.sh `gsound/sfx_count` :297-317 全套）。**缺口半格：拾取/胜负
  无专属音效**（拾取只有 HUD 计数与日志；编排列为 glue 缺口第 2 条，决策 2 可吸收为
  模板三行扩或定性不做）。
- **事实六：存档/进度数据现成，T17 闭环——菜单的 Runs 行就是存档读取面。**
  `SavePlugin::<GameSave>`（`lib.rs.template:374`；`save.rs:97` `JACKDAW_SAVE_DIR` 测试缝、
  `:92` save.json、`:360-369` 目录解析）；`count_run_over`（`:936-947`）每局终+1、三局解锁
  endless；`mirror_save_display`（`:953-971`）把 runs_played/unlock_note 镜进 `GameState`
  （`:1463-1472`），菜单/结束屏两处 Text 绑定直读（`menu.bsn.template:22,27`、
  `gameover.bsn.template:22`）。T20 的「开始菜单」格顺带驮这个半格（Runs 数字跨进程重启
  保持=T17 铁证在模板面的复用格）。
- **事实七：「主要靠编辑器配置完成」的度——五域编辑器可达面全部成晶，一域有边界。**
  逐域盘点（「哪些必须编辑器摆/哪些允许代码已有」的格化基础）：
  ①**摆件域**：`entity.add.*` 全族（cube/sphere/灯光/camera_rig/audio_source/spawn_point/
  zone_transition 等，`src/entity_ops.rs:2678-3072`）+`component.add`/Inspector Add Component
  （模板组件全带 `@EditorCategory`：Pickup/Hazard/PlayerMarker/PlayerController/PlayerHealth/
  PickupCount/SpinningCube/MusicBus/SfxBus…`lib.rs.template:476,552,556,566,1091,1138,1146,
  1491` + 物理组件 T10-T3 补 `register_avian_types`）——编辑器可以摆玩家（五组件清单受支持）
  、摆拾取物（Pickup+AvianCollider+Sensor）、摆音源（T16 L1 四件套真机链）。
  ②**改屏域**：menu/hud/gameover 是真场景文档（2D 画布+Bindings 面板可编辑可保存；
  T12 格 9「编辑器再编辑→Save→Play 生效→staged 生效」五点链闭环，roadmap :26）。
  ③**参数域**：`asset.new`（`src/definition_assets.rs:1418`）New Asset 出
  GameConfig/GameAudioConfig/GameInputConfig 卡（T08 闭环：重启+Play+导出三态一致）。
  ④**流转域**：`game.set_start_scene` operator（`src/game_flow.rs:128-148`）+Project 窗右键
  Set as Startup Scene（`src/project_window.rs:1700,1753`）+flow.json 七类校验（T13 闭环，
  导出零 staging 改动收编 manifest）。
  ⑤**音频挂点域**：AudioPlayer/PlaybackSettings/MusicBus/SfxBus 场景组件挂点（T16 L1
  真机四件套链闭环）。
  ⑥**边界（EG2）**：**关卡道具是代码常生**——`OnEnter(GameFlow::Level)` 的
  `(spawn_stage, spawn_pickups, spawn_walls, spawn_hazards)`（`scaffold:2793-2796`）无条件
  生成地面/三拾取/两墙/一危害，编辑器摆的同类件与它们**并存**（不替换：玩家有 existing
  守卫 `lib.rs.template:1174-1178`，道具没有）；且 GameFlow 流转条件（血尽/按钮）与拾取
  计数都是 Rust 系统，**绑定不能写资源/事件**（`on_volume_changed` 文档注释 `:1030-1031`
  明言「a binding can read a resource but not write one」）——**流转条件不可配置化**。
  「主要靠编辑器配置完成」的格化定义见矩阵节前的**度表**。
- **事实八：导出链成品且 T19 刚三站复验过。** `game.export`（`src/game_export.rs:143`，
  File 菜单 Build Game，`EXPORT_PROFILE="release"` `:31`）→`jackdaw_project_build::export`：
  staging 原子交换+`.jackdaw-export` 标记门（`export.rs:40`）+export-manifest.json 全清单
  SHA-256（`:45,:173-209`，两次同输入仅 generated_unix 可异）+assets 整树拷贝（过滤名单
  deliberately narrow `:688-695`）+`jackdaw/export` BRP 轮询（`src/remote/server.rs:718-720,
  2383-2424`）；export_wait 判据=staged scene.bsn SHA==工程（t16-live.sh:335-351）。T07
  闭环+T19 L5 staged 三站腿刚跑通（roadmap :33）。
- **事实九：「无工具链环境」的机制面——staged 包自足性有双保险，隔离断言可机械化。**
  ①**静态链接拒绝门**：构建报告含 dylib 工件即拒绝导出（`dynamic_linking_rejection`，
  `export.rs:747-754`；测试 `:1230-1237` bevy_dylib 拒绝在案）——staged exe 不拖 cargo dylib；
  ②**资产回退链**：游戏 exe 的 asset root 解析 `BEVY_ASSET_ROOT`>CARGO_MANIFEST_DIR>
  **exe 自身目录**（`export.rs:3-11` 模块文档）——staged 布局 exe+assets/ 自解释；
  ③**本机不对称正是断言本体**：编辑器 debug exe 启动要 `DYLD_LIBRARY_PATH=$TOOLCHAIN_LIB`
  （rustup 工具链 lib，t16-live.sh:36,:170；manual.md §7.5 launch4 模式）——**staged 游戏
  exe 在 `env -i`（清 PATH/清 DYLD_*/清 RUST_*）下异目录启动成功**，就是「无工具链环境」
  在本机的最强机械化代理；④**静态审计**：`otool -L`/`otool -l`（LC_RPATH）断言无
  rustup/homebrew/.jackdaw 路径、只链系统框架；⑤manifest 重生成比对（`manifest_for` 幂等，
  T07 可复现口径）。**真·无工具链机器不可得**（本机必有 CLT），机械代理+用户抽查
  （拷 dist 到 U 盘/另一台无 rust 的 Mac 双击）是如实上限——写进用户 30 秒清单。
- **事实十：QA 驱动面全套现成（Mac 通道）。** 编辑器侧：`ui_tree/ui_click/ui_input`+
  operator 直达（`loop/qa/manual.md` §7）+`dialog.answer` 兜底（t16-live.sh:137-144）；
  游戏侧：BRP 15702（`crates/jackdaw_remote/src/lib.rs:21`）`world.query`/`world.get_components`/
  `world.get_resources`/`world.mutate_resources`/`world.trigger_event`（t16-live.sh:802
  `ScreenPressed` 无指针链先例）——**注入缝**=prep 两行 sed（Cargo.toml+main.rs，
  t16-live.sh:458-465；发货游戏不带它，T18「dormant」同款纪律）。PIE 通道：
  `pie.play_current`/`pie.stop`（T06）+PIE 日志流（T12-T2 4-A，`pie_log.rs:11` StateEvent::Log
  →Game 面板；direct run 的 `info!` 直落 stdout 日志）。fixture 创建=`jd new <name> --path
  <dir> --no-git`（t17-live.sh:344 先例）。
- **事实十一：既有闭环任务把七验收词的域证据全数覆盖，T20 是「合链」不是「补域」。**
  对照：开始菜单（T13 真指针点击+流转）｜玩家移动（T11 矩阵 12 格双机）｜碰撞（T10
  不穿地/推墙滑行）｜拾取（T10 拾取链端到端 PickupCount+T12 HUD 绑定）｜胜负（T12 血尽
  结束屏+T13 流转；**胜局流转缺=EG1**）｜音效（T16 三音三 bus 五点链）｜重开（T13
  reset_run 真机+道具重生）——T20 矩阵的每格都标「域证据指针+合链新证据」两层。
- **事实十二：E2E 的真机先例形态齐备，T20 脚本是既有手艺的组装。** `jd new`（t17）+
  remote 注入/暖编（t16 prep）+PIE 真指针双链（T16 L4/T13）+direct_run+stdout 日志断言
  （t16 :273-278）+export_wait+staged BRP 断言（t16 L6 五点链）+T19 像素助手库
  （`png_pixels_md5`+sips 裁剪，视觉格备用）+分相纪律（`$PHASE` 日志名）+红态归档纪律
  （T16 首例）。
- **事实十三：模板即示例的「教学面」也被测试钉着，T1 若动模板要过三重门。**
  `scaffold/src/lib.rs` 内嵌断言族（`:3838-3191` "PickupCount"/"Level clear" 字符串锚、
  `:4177-4203` spawn_hazards/hazard_damage 有无随模块、`:4094,:4283` GameOverRoot 形态）+
  `tests/guards/` 模板副本守卫（T17-T3 补字段教训）+`scaffold_e2e` 冷编门（xtask:70）。
  决策 1-B（胜局流转模板扩）动的是 `collect_pickups` 一处+可能加一个 teaches——预估
  ±20 行，但 guards/嵌入断言/teaches 计数三面要同步。
- **事实十四：A6 家族（磁盘高压）+两次 release 导出是本轮最大的时间/稳定性预算项。**
  每次 `game.export`=release 全量冷编（T16 export_wait 预算 1500s）；本方案矩阵需要
  **两次导出**（纯包跑隔离腿+注入包跑全链腿，决策 3）⇒ 预算单列 ~50min；scaffold_e2e
  临时目录泄漏前科（A6，buglist.md:455-457）⇒ 门前清磁盘+事后查 `.jackdaw` 残留。
- **事实十五：warn 扫描/RUST_BACKTRACE 禁令/N13 记数为 Mac 常备纪律。** N13 PIE drain
  panic Mac 100% 复发（buglist.md:514-520，T13 单轮 22 条四类受害面）——PIE 腿逐条记数
  归因；RUST_BACKTRACE 在 Mac debug 构建=SIGSEGV（T11-T3）——全程不设；warn 形态扫描
  （`UnresolvedTypes|panicked|SceneRefused|BindContext|failed`）随 `$PHASE` 日志（A7 stale
  grep 教训：grep 文件名随相位）。

### 验收句逐词定性（矩阵化的前提）

| 验收词 | 定性 | 依据 |
|---|---|---|
| 开始菜单 | **验成晶（域闭合）+合链格** | menu.bsn 真文档+Start 按钮 ScreenPressed→流转+MenuBgm+Runs/Unlock 存档显示（事实一/五/六）；T13 真指针点击闭环——T20 新证据=同一格在「jd new 新工程」里从冷态一次走通+进导出包 |
| 玩家移动 | **验成晶（域闭合）+合链格** | move_player 相机相对+Jump+落地（事实三）；T11 双机矩阵闭环——T20 新证据=合链内移动（菜单进关卡后的位移 BRP 读回）+编辑器改 PlayerController 参数生效格 |
| 碰撞 | **验成晶（域闭合）+合链格** | 墙 stop/滑行+不穿地（事实三）；T10 闭环——T20 新证据=合链内撞墙位移截断断言；A2 推箱边界知悉不立票 |
| 拾取 | **验成晶（域闭合）+合链格** | collect_pickups+HUD 计数（事实四）；T10/T12 闭环——T20 新证据=合链内计数 0→3+HUD 文本+编辑器摆的增补拾取物可被收（事实七①） |
| 胜负 | **半成晶（唯一真缺口 EG1）** | 负局链完整（危害→血尽→GameOver 流转，事实四）；**胜局=日志无流转**（`scaffold:3190-3192` 只 info!，GameFlow 不动；流转条件不可配置化，事实七⑥）——「胜负」字面要求胜局可达结束面：EG1 是吸收（模板扩 5-10 行）还是降格（胜负=「负局流转+胜局日志+计数」）=决策 1 |
| 音效 | **验成晶（域闭合）+半格缺口** | 三挂点（BGM/按钮 blip/空间 Ambient）+三类 bus+SoundLive 断言面（事实五）；T16 闭环——半格：拾取/胜负无音效（决策 2：模板三行扩 vs 定性不做） |
| 重开 | **验成晶（域闭合）+合链格** | Restart→Level 重入→reset_run/reset_run_counters/道具重生（事实二）；T13 真机修过 reset_run——T20 新证据=合链内重开七元组复位（血量/计数/位置/拾取物重生/声音再挂） |
| 新建工程主要靠编辑器配置完成 | **格化后验成晶（度表见下）+边界记档（EG2）** | 模板=零手写代码可玩（代码属模板）；编辑器五域配置面全部成晶可走查（事实七①-⑤）；「关卡道具代码常生+流转条件不可配置」是度的边界（事实七⑥） |
| 可独立导出运行（无工具链环境） | **机制成晶+隔离证据缺口** | 静态链接拒绝门+exe 目录资产回退（事实九①②）；「无工具链机器」真机腿从未跑过——本机机械代理（env -i 异目录启动+otool 审计+manifest 重生成比对）零证据，T19 L5 只跑过注入包全链 |

### 「主要靠编辑器配置完成」度表（格化定义）

| 层 | 内容 | 归属 | T20 断言格 |
|---|---|---|---|
| 模板代码层 | 游戏行为（系统/流转/观察者/玩家/道具生成） | **允许代码已有**（新建工程自带，作者零手写）——「配置完成」的对立面是「作者写代码」，不是「世上无代码」 | 开箱 Play 全链格（零编辑、零代码） |
| 场景文档层 | menu/hud/gameover 四 UI 文档+scene.bsn 光照/音源 | **必须编辑器可达**（真文档，画布/Bindings 可改可存） | 改屏格：编辑器改菜单标题+HUD 文案→Save→Play 生效→进包生效（T12 格 9 形态） |
| 配置资产层 | GameConfig/GameAudioConfig/GameInputConfig | **必须编辑器可达**（New Asset+卡编辑） | 参数格：New Asset 出 game-config.bsn 改 gravity/health→Play 数字生效（T08 形态） |
| 流转配置层 | game.flow.json start_scene/scenes | **必须编辑器可达**（右键 Set as Startup Scene/operator+校验） | 流转格：set_start_scene→导出从指定场景启动（T13 格 8 形态） |
| 摆件层 | 玩家/拾取物/墙体/音源（entity.add+component.add） | **必须编辑器可达**（受支持路径）；**与代码常生道具并存不替换**（EG2 边界） | 增补格：编辑器摆第 4 个 Pickup+摆一个 AudioSource 挂点→Save→Play 生效→进包生效 |
| 代码常生层 | 地面/三拾取/两墙/一危害（OnEnter 生成） | 模板行为（作者不可关、不可替——无模块开关入口在 jackdaw.toml `[modules] physics=false` 可整模块关，但关掉连碰撞拾取一起没） | 边界记档 EG2（open-challenges：道具场景化/生成开关） |
| 流转条件层 | 血尽/按钮→GameFlow | 模板代码（绑定只读不可写，事实七⑥） | 边界记档（胜局流转=EG1/决策 1） |

---

## 编排缺口清单（既有能力串成完整游戏的「胶水」盘点）

| # | 缺口 | 现状证据 | 配置可达？ | 定性与处置 |
|---|---|---|---|---|
| G1（=EG1） | **胜局不驱动流转**：三拾取集齐只有 `info!("Level clear!")`，GameFlow 停在 Level，永远见不到「胜利结束面」；玩家只能靠撞 Hazard 输出局才能走完 menu→level→gameover→restart 全环 | `scaffold:3190-3192`（count>=3 只 info!）；`update_game_over` 只认血量（`lib.rs.template:1670-1686`） | **不可达**——GameFlow 是 `States` 资源，绑定只读（事实七⑥）；场景文档无法表达「计数达标→换世界」 | 决策 1：**A=模板扩 5-10 行**（`collect_pickups` 加 `NextState<GameFlow>` 参数，count>=3 → `flow.set(GameOver)`，teaches 文档两句话，guards/嵌入断言同步）——「胜负」字面的最小兑现；**B=零改动降格**（胜负=「负局流转+胜局日志+计数 UI」，验收矩阵把胜局格记 EG1 ⚪）。建议 A（T20 是「示例游戏」的门面任务，示例本身应教会胜利；改动面在模板域、有事实十三三重门护栏） |
| G2 | **拾取/胜负无音效**：拾取只有计数+日志；「音效」词由三挂点（BGM/blip/Ambient）覆盖，但「事件反馈音」这个最常见挂点示例缺席 | 事实五；`collect_pickups` despawn 处无 spawn 音 | 不可达（despawn 瞬间的音效是代码语义） | 决策 2：**A=随 G1 顺手扩**（collect 臂 `press_sound` 同款三行 spawn blip——`press_sound` 已是现成函数 `lib.rs.template:1594-1602`）；**B=不做**（T16 三挂点已够「音效」字面）。建议 A-if-G1-A（同一处代码、边际成本≈0）；G1-B 则 B |
| G3 | **编辑器摆件与代码常生道具并存**：编辑器摆 Pickup 会被收（真组件真系统）、但代码三枚照生——「编辑器配的关卡」是增补不是替换 | `scaffold:2793-2796` 无条件生成 vs `spawn_player:1174-1178` 有守卫 | 摆件可达、替换不可达 | 不修（EG2 ⚪ 记档+open-challenges「道具场景化/生成开关」）；矩阵增补格按「并存可玩」设计 |
| G4 | **「开始菜单→关卡→胜负→重开」无单项目整链证据**：T12/T13/T16 各验各域，从未在 `jd new` 冷工程一次连续走完全环+导出包整链 | 事实十一 | —（验收本体） | **T20 主任务**：矩阵 M1-M12 |
| G5 | **「无工具链」隔离证据零**：T07 验过异目录启动（本机满环境）、T16/T19 验过注入包——纯包+env -i+otool 审计从未做 | 事实九④⑤ | —（验收本体） | **T20 第二主任务**：矩阵 M13-M16 |

> 除 G1/G2 外**零产品改动预期**；G1/G2 全部收敛在 `scaffold/src/lib.rs` 模板函数域（非引擎、
> 非编辑器），最坏情况（决策 1-B/2-B）回到纯验收型。

---

## 一、缺陷候选（EG 系，只记不修→主控裁定吸收面）

| 编号 | 严重度 | 描述 | 证据 | 处置建议 |
|---|---|---|---|---|
| **EG1** | 🟡 | **胜局无流转**：拾取达标（count>=3）只产日志，GameFlow 不动，「赢」不可达结束面——示例游戏教学面缺「胜利」半边 | `scaffold:3190-3192`；`lib.rs.template:1670-1686`；事实四/七⑥ | **吸收候选（决策 1-A）**：模板扩 5-10 行（collect 臂 set GameOver）；或降格记 ⚪（决策 1-B） |
| **EG2** | ⚪ | **关卡道具代码常生、编辑器摆件只能增补不能替换**：OnEnter 无条件生成四组道具，无场景化路径无开关；「编辑器配关卡」的度的硬边界 | `scaffold:2793-2796` vs `lib.rs.template:1174-1178`；事实七⑥ | **不吸收（范围边界）**：记 open-challenges（「模板道具场景化或 `[modules]` 下细分生成开关」）；矩阵按并存可玩设计 |
| **EG3** | ⚪ | **拾取/胜负无事件反馈音**：G2 的缺陷面登记（若决策 2-A 吸收则本条关闭） | 事实五 | 随决策 2 |
| **EG4** | ⚪ | **A2 推箱边界在示例游戏可见**：玩家撞掉落立方体如撞墙（dx≈0 双机实证）——新工程开箱即见，用户可能报「碰撞坏了」 | buglist.md:438-439 | 不立新票；T20 碰撞格知悉+book 玩家章已有边界段（T11 补过）；如真机复踩引 A2 原文 |
| **EG5** | ⚪ | **纯包（无注入）跑全链不可断言**：发货游戏无 BRP，隔离腿只能 alive+截图+日志三断言——「独立跑全流程」的全流程断言依赖注入包（测试缝） | 事实九/十；T18 dormant 纪律 | 定性注记不修：双导出分工（决策 3）；纯包的全流程以「可玩性」留给用户 30 秒清单真机 |
| **EG6** | ⚪ | **staged exe 无签名/公证**：cargo 产物 ad-hoc，拷到别的 Mac 首次打开过 Gatekeeper 要右键——「无工具链环境」的用户面小坎 | 事实九 | 记 open-challenges 一句话（codesign 公证超出 loop 范围）；本机验证不受扰（无 quarantine 位） |

统计：🟡 1（EG1，编排缺口非引擎缺陷）｜⚪ 5（EG2-EG6）。

### buglist 重叠表（示例/编排/导出/PIE/BRP 域全量过筛，75+15 条逐条）

| 条目 | 一句话 | T20 处置 |
|---|---|---|
| **A7**（buglist.md:459-463） | 真机驱动工具债：对话框提交+字段行定位+stale grep+**截图同帧 flake**+ui 坐标漂移——改屏格（ui_input 改文本）与截图格正面撞上 | **不前置，脚本自守**：改屏主链走 operator（`component.set`/`apply_bsn` 文档面）+ui_input 真机面为辅；截图五招（request 唯一键/rm -f/size 验证/相邻两拍 flake 探针/screencapture 降级，T19 决策 6 全套）；grep 随 `$PHASE` |
| **A9**（buglist.md:493-495） | 游戏 BRP 间歇空响应+方法瞬失 | gbrp 重试+settle（t16-live.sh:104-123 原样）；数值断言小响应体（Name+单组件）；避开 scene.open/构建窗口（editor_build_settled 先行） |
| **A10**（buglist.md:465-467） | PIE 指针转发缩放布局未达游戏 UI | **双链纪律**：PIE 点击腿先真指针（T16 L4/T13 先例，`JACKDAW_WINDOW_SIZE=1600x1000` 固定窗降低缩放暴露），失败即降 `world.trigger_event` 无指针链（t16-live.sh:794-802 现成）——两条都记进格判定 |
| **A11**（buglist.md:469-471） | rebind 只改文档层、newtype 组件世界侧粘性 | **编排不踩**：T20 无资产改名/rebind 腿；唯一 newtype 面=AudioPlayer 场景挂点（增补格），只写不 rebind——知悉；若 QA 顺手做「改音效文件名」扩展腿则撞面，明令不做 |
| **A5**（buglist.md:451-453） | pie_log 窗口溢出静默丢弃 | 胜局日志断言主通道走 **direct run stdout**（t16 direct-*.log 形态，不经 pie_log）；PIE 通道的日志断言降为辅证 |
| **A6**（buglist.md:455-457） | watcher flaky+磁盘高压+scaffold_e2e 临时目录泄漏 | 门前清磁盘照旧；integration 唯一预期红=A6 定案口径隔离绿；导出/scaffold_e2e 后查 `.jackdaw` 与临时目录残留 |
| **A8**（buglist.md:489-491） | BSN apply 静默丢弃 crate 根 re-export 路径 | **手写/注入 scene.bsn 全 generic 全路径**（write_scene_bsn 纪律，t16-live.sh:365-416 范本）；编辑器写的文档天然全路径不受扰 |
| **A2**（buglist.md:438-439） | Kinematic 玩家推不动 Dynamic 体 | EG4 知悉；碰撞格断言「停止/滑行」不断言「推动」 |
| **N12**（buglist.md:509-512） | BRP 实体域界 | 游戏侧全 bevy 原生方法；id 域换算按 manual.md §7.5（`"NvM"` vs raw bits） |
| **N13**（buglist.md:514-520） | PIE drain panic 100% 复发 | PIE 腿逐条记数归因（错误处理器捕获编辑器存活）；PIE 不做存活时序依赖断言 |
| **W4**（buglist.md:303-305） | 截图采集相机滞留 | 截图腿后 BRP 活性断言；分相重启压暴露窗 |
| **Y33/Y37/W25** | 游戏 BRP CORS/PIE 全量序列化/调试轮询 | 知悉：注入缝仅测试工程；PIE 腿实体量小（模板关卡 <30 实体）；不关面板即可 |
| **R4**（buglist.md:37-41） | scene_snapshot 父子解析失效 | 矩阵不依赖层级树断言（用 Name→组件表，manual §7.5 数据断言形态） |
| **R5-R8/R11-R14/Y16-Y27/W18-W21** | terrain/CSG/笔刷/Inspector/灯光投影域 | 无交集（示例游戏零地形零笔刷） |
| **A3/A4/N10/N14/W7-W12/W13/W17/W23/W26/Y34** | 已勾选/已修 | 回归面（导出门/walker/原子写），矩阵顺带复验不立项 |

> 如实报告：**示例/编排域在 buglist 零预期缺陷**——模板游戏是 T09-T17 九任务的验收产物本身，
> 每个域各自真机闭环过。T20 的缺陷主体是新查出的编排缺口 EG1（+EG2-EG6 定性边界），
> 真机矩阵的新发现空间在「合链时序」（如 PIE 重启后的存档镜像、双导出间的 flow 状态），
> 出新账按 EG7 续编。

---

## 二、验收矩阵设计

**两条铁证×合链=16 格主矩阵**。断言通道缩写：H=headless（guards/嵌入断言/scaffold_e2e）、
R=真机编辑器 BRP 15703（operator+ui 工具）、G=游戏 BRP 15702（bevy 原生方法，N12 口径；
注入包）、LG=游戏日志（direct stdout / staged stdout / PIE Game 面板）、PX=像素（编辑器
viewport 直拍+`png_pixels_md5`，视觉格备用）、FS=盘面（SHA/manifest/save.json/flow.json）、
EXPORT=staged 包（manifest+otool+异目录启动）。

**前置腿 L1 的三个前提态**：①fixture=`jd new t20-game --path /Users/zhanglinbo/workspace/
loop-mac/ --no-git`（t17-live.sh:344 形态）+remote 注入两行 sed+暖编（t16-live.sh:458-469）；
②`JACKDAW_SAVE_DIR=<scratch>` 指向 scratch（save.rs:97 测试缝）——runs_played 断言确定性
+不污染真存档；③flow start_scene=menu.bsn（模板默认，`game.flow.json`）。

### 铁证①：一个新建工程的完整游戏合链（开箱→配置→Play→导出→staged 全流程）

| 格 | 内容 | 通道 | 现状 |
|---|---|---|---|
| M1 | **开箱冷启格**：`jd new`→编辑器开工程→Play（零配置零代码）→菜单出现（MenuRoot+Runs: 0+Start 钮）→MenuBgm SoundLive kind=music playing | R+G | 域证据 T13 ✅；**合链冷态首跑零证据** |
| M2 | **全环合链格**：Start→Level→玩家位移断言（Transform 前后 delta>阈值，W 注入 400ms）→撞墙位移截断→拾取 0→3（PickupCount+HUD 文本+三枚 despawn）→危害扣血（血条 ratio 降）→血尽→GameOverRoot+Runs: 1→Restart→七元组复位（血满/计数 0/回出生点/拾取物重生/MenuBgm 停 Ambient 起） | G+LG | 域证据 T10/T11/T12/T13 ✅（各自分腿）；**单项目连续整环+循环×3 无残留零证据**（T13 三循环格在 flow 域，本格扩到道具/音/存档七元组） |
| M3 | **胜局格（EG1/决策 1）**：三拾取集齐→（决策 1-A）GameFlow→GameOver + 结束屏；或（1-B）`Level clear!` 日志+计数恒 3 断言 | G+LG | 🔴EG1 前置；direct stdout 日志断言（A5 绕 pie_log） |
| M4 | **音效三挂点格**：MenuBgm(music)/blip(sfx 一次性，press 后 sfx 计数+1、 finished 翻 true)/Ambient(spatial) 三 SoundLive 逐字段+bus mix 改 GameAudioConfig 追认 | G | 域证据 T16 ✅；合链内复验（快） |
| M5 | **重开存档格**：gameover→menu→再开局→Runs 累加；`kill -9` staged 进程→重启→Runs 保持（save.json 持久+菜单镜像） | G+FS | 域证据 T17 ✅；合链复验（JACKDAW_SAVE_DIR scratch） |
| M6 | **PIE 通道格**：pie.play_current（flow 启动语义）全环一遍（真指针点击 Start；A10 降级链备用）+N13 记数 | R+G | 域证据 T13/T16 ✅；PIE=导出包语义同源验证 |
| M7 | **增补摆件格**：编辑器在 scene.bsn 摆第 4 个 Pickup（entity.add.cube+component.add Pickup/AvianCollider/Sensor）+摆一个 AudioSource 挂点（MusicBus）→Save→Play→第 4 枚可收（count 4）+新音源 SoundLive；导出包内同验 | R+G+EXPORT | 域证据 T16 L1（音源四件套）+T10（组件授权）✅；**「编辑器摆件参与游戏」合链格零证据** |
| M8 | **改屏格**：编辑器改 menu 标题文本+HUD 文案（ui_input 真机面/operator apply_bsn 主链双轨）→Save→Play 生效→**staged 包内生效**（T12 格 9 五点链在 T20 的复刻） | R+G+EXPORT | 域证据 T12 格 9 ✅；新工程复刻 |
| M9 | **参数格**：`asset.new` 出 game-config.bsn（health=50, gravity=-20）→Play（血条半格+下落变快）→导出生效 | R+G+EXPORT | 域证据 T08 ✅；新工程复刻 |
| M10 | **流转格**：Project 右键 Set as Startup Scene 指 gameover.bsn→direct run→boot 即结束屏（boot_state 映射）→改回 menu | G+FS | 域证据 T13 格 8 ✅；新工程复刻 |

### 铁证②：可独立导出运行（无工具链环境）

| 格 | 内容 | 通道 | 现状 |
|---|---|---|---|
| M11 | **注入包全链格**：game.export→export_wait（SHA 判据）→manifest 校验→staged 异目录启动→M2 全环在 staged 包复跑（BRP 注入包，决策 3 的第二导出） | EXPORT+G | 域证据 T16 L6/T19 L5 ✅；T20 换成「整环」而非单域 |
| M12 | **纯包隔离格（无工具链正主）**：干净工程（决策 3 的第一导出，无 remote 注入）→staged 拷到项目外 scratch（异目录）→`env -i HOME=<scratch> PATH=/usr/bin:/bin` 启动（清 DYLD_*/RUST_*/CARGO_*）→**进程存活 60s+窗口出现+菜单渲染（screencapture）+stdout 日志干净（warn 扫描零命中+boot 行在）** | EXPORT+LG+PX | 🔴 事实九④⑤零证据；编辑器同机启动**要** DYLD 前缀=不对称对照组 |
| M13 | **自足性静态审计格**：staged exe `otool -L` 只链系统库（/usr/lib//System/Library）零 rustup/homebrew/.jackdaw 路径；`otool -l` LC_RPATH 审计；`dynamic_linking_rejection` 语义复述（dylib 报告=空）；manifest 重生成比对（`manifest_for` 幂等） | FS | 机制在案（事实九①②）+**审计腿零证据** |
| M14 | **导出可复现回归格**：两次导出（纯/注入）manifest.files 结构对比+`.jackdaw-export` 标记在+flow.json 收编（T13）+assets 过滤面（无 .jackdaw-pie/.bak） | FS | 域证据 T07 ✅；快格 |
| M15 | **横切·存活**：每相每腿后 BRP 活性+pid；warn 形态扫描（`UnresolvedTypes\|panicked\|SceneRefused\|BindContext\|refused`）逐条归属；N13 逐条记数 | 脚本常备 | 纪律腿 |
| M16 | **横切·画面对照（可选半格）**：编辑器 PIE 流送帧 vs staged 窗口截图（T19 GR8 已定案「流送帧忠实」）同向对照一拍——示例游戏画面 sanity | PX | ⚪ 可选（T19 手艺现成，决策 6 裁去留） |

**矩阵统计**：🔴 前置 2 格（M3=EG1、M12=隔离正主）｜域闭环复验 9 格（M1/M2/M4-M10/M11）
｜纯新证据 5 格（M12/M13/M14+M7/M8 的 staged 半边）｜⚪ 可选 1 格（M16）。
T1（若决策 1-A）模板扩+prep；T2 落判。

---

## 三、真机腿清单（Mac，bash+curl+jq；T2 集中跑）

fixture=`/Users/zhanglinbo/workspace/loop-mac/t20-game`（`jd new`；T15/T16/T17 决策同款）。
流程脚本 `loop/qa/t20-live.sh`（t16-live.sh 形态全量复用+`export_wait`+`direct_run`+`gsound`
族原样搬；两导出分支）。**分相**：prep｜box（M1/M2/M3/M4 开箱合链）｜config（M7-M10 配置
域）｜pie（M6）｜export（M11/M14+M7-M10 包内半边）｜pure（M12/M13 隔离腿，不注入不依赖
BRP）——每相独立 editor_boot（分相纪律+A6/W4 暴露窗压缩）。

| # | 腿 | 通道 | 为什么必须真机 |
|---|---|---|---|
| L1 | prep：jd new+模板完整性预检（guards 同款 grep：GameSave/hud 滑条行/三 wav/flow.json）+remote 注入+暖编+scratch save dir+编辑器 boot（DYLD 前缀） | FS+R | 全矩阵前提态；注入缝纪律（发货面不带 BRP） |
| L2 | M1+M2 开箱合链：菜单→Start（真指针优先，trigger_event 降级双记）→七元组整环×3 循环→每环断言七元组恒等（T13 形态扩维） | R+G+LG | 「合成任务」的合链正主；域证据是分腿的，合链时序只有真机给 |
| L3 | M3 胜局：拾取集齐→按决策 1 判（流转或日志）；红态先行：EG1-B 案归档「集齐后停在 Level」红证 | G+LG | EG1 的证据正主；决策 1 落地验证 |
| L4 | M4+M5 音/存档快格：三 SoundLive+mix 追认+Runs 累加+kill -9 重开保持 | G+FS | T16/T17 铁证在新工程的复用格（防模板漂移） |
| L5 | M6 PIE：play_current 整环+真指针+win 日志双通道+N13 记数+pie.stop 还原（T06 SHA 双腿） | R+G | 编辑器内「Play 即所玩」通道 |
| L6 | M7-M10 配置五域：摆件/改屏/参数/流转四格（每格=编辑器改→Save→Play 生效三点） | R+G+FS | 「主要靠编辑器配置完成」的正主；ui_input 主链双轨（A7 自守） |
| L7 | M11+M14 注入包：export_wait→manifest→staged 整环复跑+M7-M10 包内半边（改屏/参数/摆件进包生效） | EXPORT+G | 「编辑→保存→Play→导出」通用铁证的 T20 全域版 |
| L8 | M12+M13 纯包隔离：异目录+env -i 启动+alive/截图/日志三断言+otool 审计+manifest 重生成比对 | EXPORT+LG+PX+FS | 「无工具链环境」正主；本机最强机械代理（事实九③不对称对照） |
| L9 | M15/M16 warn 扫描+存活+N13/A5 记数归档+（决策 6）画面对照一拍；证据归档 `loop/t20-live/` | 全 | 常备纪律+验收铁证归档 |

---

## 四、分任务拆解（T1/T2/T3）

### T1「编排 glue 清源轮」（视决策 1/2 裁定，0.5-1 天；全决策点）

1. **决策 1/2 落地**（若 A/A）：`scaffold/src/lib.rs` `collect_pickups` 扩胜局流转
   （+G2 音效三行）——同步面：`lib.rs.template` 对应函数、嵌入断言族（事实十三）、
   guards 模板副本、teaches 计数、模板头文档两句话（胜利/音效教学）；**门禁**：
   fmt/clippy/libtests/integration+scaffold_e2e 冷编（模板改动必过门）。
2. **T20 prep 脚本入库**：`loop/qa/t20-live.sh` 骨架+L1 prep 腿（jd new+注入+暖编+
   scratch save dir+模板完整性预检）。
3. **首步探针（半日）**：①决策 3 定案——双导出顺序与判据落脚本；②M2 七元组清单
   定稿（血量/计数/位置/拾取物数/MenuBgm 态/Ambient 态/Runs 值）；③PIE 真指针在
   1600x1000 固定窗的可用性一拍（A10 暴露面预判）。
4. **EG1-B 案红证预备**：若决策 1-B，先归档「集齐后停留 Level」红证（T3 报告用）。

**验收标准**：门禁全绿（若 1-A）；prep 腿绿；探针三定案在案。

### T2「E2E 真机矩阵轮」（验收主任务：M1-M16/L1-L9；1.5-2 天）

1. L2-L9 全腿；每腿独立探针开场；红态先行归档（如 EG1-B 红证/纯包日志样张）。
2. 两次导出（决策 3）：先纯包（M12/M13）后注入包（M11+配置四格包内半边）——预算
   1500s×2 单列，门前清磁盘。
3. 缺陷只记不修：新发现按 EG 系续编（EG7 起），红证归档 `loop/reports/t20*/`。
4. QA 报告：16 格逐格判定+L 腿全证据+用户 30 秒清单草稿（**含真·无工具链抽查**：
   把 dist 拷 U 盘/另一台无 rust 的 Mac 双击跑——机械代理的诚实上限，事实九）。

**验收标准**：M1/M2（开箱合链）+M7-M10（编辑器配置域）+M11（staged 整链）全绿=铁证①；
M12/M13（隔离+审计）全绿=铁证②；M15 存活腿全过；四门禁绿。

### T3「终验 + 文档」

1. 16 格终态复跑+重点腿复跑（L2/L7/L8）。
2. book 扩节：`book/src/user-guide/` 下**游戏模板章**（t11-t13 已建的 player-controller/
   game-ui/game-flow 章族）补「示例游戏全链」一节（开箱可玩清单/编辑器配置五域导览/
   胜负两链/导出与无工具链运行边界——含 EG5/EG6 注记：纯包无 BRP、Gatekeeper 首开右
   键）；不另立新章。
3. buglist 处置（预期零打钩；EG1 若 1-B 则 open-challenges 记「胜局流转」）、roadmap 勾选
   T20、台账记行。
4. 终验门：全量门（fast/integration/doctests/docs/scaffold_e2e——日志全文复核；
   integration 唯一预期红=A6 定案口径隔离绿，照既往口径）。

---

## 五、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **EG1 胜局流转：模板扩还是降格** | A=**模板扩 5-10 行**（`collect_pickups` 加 `NextState<GameFlow>`，count>=3→GameOver；teaches/guards/嵌入断言三面同步）——「胜负」字面兑现、示例教会胜利、改动面小且有三重门护栏；代价=T20 从纯验收变 90/10、模板域 diff 一处。B=**零改动降格**（胜负=负局流转+胜局日志+计数 UI；EG1 记 ⚪ 挂 open-challenges）——纯验收定型守住；代价=验收词「胜负」只按半边兑现、示例游戏永远「只能输」 | **A**（T20 是示例游戏的门面任务，「赢不了」的示例是教学缺陷；改动收敛模板域可回滚） |
| 2 | **EG3 拾取音效** | A=随决策 1-A 顺手扩（collect 臂 spawn blip 三行，`press_sound` 现成）；B=不做（T16 三挂点已够「音效」字面） | **A-if-1-A**（同处代码边际≈0）；1-B 则 B |
| 3 | **导出次数与分工** | A=**双导出**：纯包（无注入）跑 M12/M13 隔离正主+注入包跑 M11 整链——发货面与测试缝分离、otool 审计落在真·发货产物上；代价=两次 release 冷编 ~50min 预算。B=单注入包双职责（otool 断言自足即可，注入只加进程内 HTTP listener 不改链接面）——省一次导出；代价=「无工具链」正主不是发货形态、EG5 扩大 | **A**（预算可控；「可独立导出运行」的字面值得一个未动过的包） |
| 4 | **M2 真指针 vs 事件链的主辅** | A=**真指针优先+trigger_event 降级双记**（T16 L4 先例；A10 在固定窗下的暴露面 T1 探针预判）。B=一律 trigger_event（快、稳）；代价=「按钮触发真行为」的交互面铁证降格，违背交互验收契约精神 | **A**（ui_click/ui_tree 现成；降级链是记录在案的合法回落） |
| 5 | **配置域走查的驱动形态（A7 撞面）** | A=**operator 主链+ui 真机辅面**：改屏/摆件/参数每格先 operator 直达（apply_bsn/component.set/asset.new）钉数据面，再 ui_input/ui_click 走一遍真机交互面——A7 的对话框/行定位债只咬辅面。B=全 ui 真机（最忠实用户）；代价=A7 家族直接决定本任务节奏（工具债前置论再起） | **A**（数据面与交互面双轨记格；A7 不前置，真踩按 MCP 优先原则现场立小票） |
| 6 | **M16 画面对照去留** | A=做一拍（T19 手艺现成，PIE 流送帧 vs staged 截图同向 sanity）。B=不做（画质域 T19 刚闭环，示例游戏无画质断言词） | **B**（省预算；「音效/胜负」无像素判据需求；T19 三站 parity 刚验过渲染面） |
| 7 | **存档隔离缝** | A=全程 `JACKDAW_SAVE_DIR=<scratch>`（save.rs:97；断言确定性+不污染真存档）。B=用真实用户目录（最真实）——代价=runs_played 断言受历史污染+动用户数据 | **A**（T17 同款纪律；M5 的「真实目录」面由用户 30 秒清单覆盖） |
| 8 | **缺陷编号与台账** | EG 系（EG1-EG6 已用，新发现自 EG7 续）；矩阵格 M1-M16；腿 L1-L9；fixture `/Users/zhanglinbo/workspace/loop-mac/t20-game`；脚本 `loop/qa/t20-live.sh`；报告 `loop/reports/t20*/`；证据 `loop/t20-live/` | 小定案，主控可否决 |

---

## 六、风险与回滚

| 风险 | 概率 | 缓解 |
|---|---|---|
| **EG1 决策分歧拖节奏** | 中 | T1 首日即裁；B 案红证预备（T1.4）使两案都可立即开工 |
| **两次 release 导出超时/磁盘高压（A6 家族）** | 中-高 | 预算 1500s×2 单列；门前清磁盘；export_wait SHA 判据不赌时间；导出后查 `.jackdaw` 与 scaffold_e2e 临时残留 |
| **纯包隔离腿假绿（env -i 不彻底）** | 中 | `env -i` 显式白名单（HOME/PATH=/usr/bin:/bin/TMPDIR）；对照组=编辑器同机**要** DYLD 前缀启动成功；otool 审计兜底静态面 |
| **A9 游戏 BRP 空响应扰动 staged 断言** | 中 | gbrp 重试+settle+小响应体（t16 全套）；staged 相 sleep+game_ready 再采样 |
| **A10 PIE 指针在部分布局不可用** | 中 | 固定 1600x1000 窗；T1 探针预判；trigger_event 降级链双记（决策 4-A） |
| **N13 PIE panic 记数膨胀** | 确定（100% 复发） | 逐条记数归因（T13 口径）；PIE 腿不依赖编辑器存活时序 |
| **A7 家族咬改屏/摆件辅面** | 中 | 决策 5-A 双轨；截图五招；ui_input 前先 `JACKDAW_WINDOW_SIZE` 对齐（manual §7.5） |
| **模板改动（若 1-A）波及存量工程/守卫** | 低-中 | 改动收敛单函数；guards/嵌入断言/teaches 三面同步；scaffold_e2e 冷编必过；存量工程不受扰（模板只在 jd new 时物化） |
| **合链时序新缺陷（重启后存档镜像/双导出间 flow 态）** | 低 | 每格独立前提态；发现即 EG 记账不现场修 |
| **Mac debug 无 RUST_BACKTRACE** | 确定 | 全程不设（T11-T3 口径）；panic 证据=日志消息签名 |
| **门链与编辑器/游戏同窗互踩** | 中 | T12-T3 纪律：门链单独跑 |
| 回滚 | — | **决策 1-B/2-B 案=产品代码零改动**（全在 loop/qa+loop/plans+book）；**1-A 案=模板域单函数 diff**（回滚=revert 一处+guards 同步）；零引擎改动、零编辑器改动、零协议变更、零 fork 改动、零场景格式变更。建设面最小化由度表保障（五域配置面无一需要新机制） |

---

## 七、与 T01-T19 已建设施的衔接 + Mac 通道注意

1. **T10/T11（物理/玩家）=关卡行为底座**：TriggerEvents 桥/碰撞层/move_and_slide/五组件
   清单全部继承；A2 推箱边界知悉（EG4）。
2. **T12/T13（四屏/流转）=合链骨架**：ScreenPressed 事件链/GameFlow 三态/真指针点击/
   reset_run 真机修/T12 格 9 五点链——M2/M8 的直接母版。
3. **T16（音频）=断言面手艺**：SoundLive 镜像查询/gsound 族/注入缝 sed/export_wait——
   t20-live.sh 的主要搬运源。
4. **T17（存档）=进度格**：JACKDAW_SAVE_DIR 缝/kill -9 恢复链/runs_played 镜像——M5 直接复用。
5. **T07/T19（导出/三站 parity）=铁证②底座**：staging 原子交换/manifest/otool 语义面/
   staged BRP 断言形态/T19 像素助手库（M16 备用）——L7/L8 是 T16 L6+T19 L5 的整环升级版。
6. **T15（A8 教训）**：手写/注入 bsn 全 generic 全路径；T18（dormant 纪律）=注入缝的
   发货面分离原则——决策 3-A 是该原则在导出域的延伸。
7. **对 T21+ 的奠基**：T20 的「度表」是 T21/T22（2D 作者流程）评判「编辑器配置完成」的
   格化先例；EG2 的「道具场景化」open-challenges 是模板演进方向的第一次正式记账。
8. **Mac 通道注意汇总**：①编辑器 boot 带 DYLD 前缀、staged 纯包**禁**带（隔离腿本体）；
   ②RUST_BACKTRACE 全程不设；③warn 扫描随 `$PHASE`（A7 stale grep 教训）；④A 系票
   关联：A7/A9/A10 自守不前置、A5 绕 pie_log 走 stdout、A11 明令不踩（无 rebind 腿）、
   A6 磁盘纪律、A15 不涉、A2/A12/A13/A14 知悉；⑤`JACKDAW_SAVE_DIR`+`JACKDAW_CONFIG_DIR`
   双 scratch（如涉编辑器偏好——本任务不动 Graphics 面板，config 缝备用）。
9. **分支与行号基线**：本方案行号基于 main ca38c389；T20 从 main 拉 `loop/t20-example-game`；
   loop/ 目录随 git 旅行（2026-10-28 迁移后），上游 PR 时按需剔除。
