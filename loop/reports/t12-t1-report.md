# T12-T1 实施报告：模板四屏 UI + 活数据源 + 接线

> 任务：`loop/plans/t12-game-ui.md` §二-T1（改动面 1-4；决策 1-A/2-A/3-A/5-A/6-A/7-A/8-A
> 按主控裁定全按建议实施；§0 架构事实作地基）。分支 `loop/t12-game-ui`（自 main 1e5bc617）。
> 门禁日志归档 `loop/reports/t12t1_*`；暖工程 `/Users/zhanglinbo/workspace/loop-mac/t12t1-game`
> （新独立暖工程，不触碰 t11t1-game/t11t3-nophys）。

## 一、范围逐项与产品改动（7 码文件：tracked +645/−20；新增 hud.bsn.template 219 行+game_ui.rs 880 行）

1. **模板 `lib.rs.template` 新增 UI 教学段**（改动面 1，全项落地）：
   - `GameState { menu, paused, game_over }`（`Resource, Reflect` +
     `#[reflect(Resource, Default)]`；手写 `Default`，**开局 menu=true**）——决策 3-A：
     bool 字段直读，四屏 `Visibility` 绑定免 via；
   - 事件 `ScreenPressed { button: String }`（`Event, Reflect, Clone, Default` +
     `#[reflect(Event, Default)]`）——单事件多按钮（literals `"start"/"resume"/"restart"`）。
     **U7 探针后定稿形态：plain `Event` derive**——bevy 0.20 fork 的
     `#[derive(EntityEvent)]` **要求实体字段**（宏报错「EntityEvent derive expected a
     field name 'entity' or a field annotated with #[event_target]」；`derive_entity_event`
     同时生成 Event+EntityEvent 两个 impl 但取 entity 字段做 target），无实体字段的事件
     必须用 plain `Event`（探针测试 `a_unit_struct_event_is_sent_by_a_fieldless_action`
     同时钉死 unit-struct 事件可用）；
   - `PlayerHealth { current, max }` 组件（`#[reflect(Component, Default)]` +
     `EditorCategory("Actor")`）挂玩家（`spawn_player` 元组 `PlayerHealth::default()`）；
     **初值注入链=config→组件**：`apply_health_from_config`（Update，
     `config.is_changed()` 门）把 `GameConfig.player_health` 交给组件 max/current——
     与 `apply_gravity_from_config` 同构（首载+编辑器 mid-run 改都生效）；GameConfig
     doc 的「player_health has no system yet」改为指向该链（作者意图 vs 活状态钉死）；
   - via 函数三枚：`ratio`（clamp 0..1）/`is_zero`/`not`——`register_function` 三行，
     doc 钉「类型自动注册、via 函数是绑定面唯一要手动注册的东西」；
   - `spawn_hud`：Startup 里 `(spawn_scene, spawn_hud)` **顺序元组**——主场景保住
     第一根（PIE 只换第一根），hud 每形态随行；
   - `wire_hud`：`Query<Entity, Added<HudRoot>>` + 玩家查询 → hud 根插
     `BindContext(player)`（runtime doc 钦点接线形态）；
   - 行为侧：`on_screen_pressed` observer（start 离菜单/resume 解暂停/restart 复位
     血量+出生点+三屏 bool）；`handle_pause_action`（T09 Pause 从 info! 占位升级为
     `state.paused` 翻转，`!menu && !game_over` 守卫——与 Resume 按钮同走一 bool）；
     `take_damage`（钳 0）+ `update_game_over`（current≤0→game_over）；
     `PLAYER_DAMAGE=15`/`PLAYER_SPAWN`（spawn 与 restart 共用，重开落回原点）；
   - **move_player 双形态加 gate**（决策 8/放行条件）：`if state.menu || state.paused
     || state.game_over { return; }`——physics 形态与无物理 fallback 形态都加；
   - **`handle_pause_action.before(move_player)` 显式边**：暂停翻转独占该帧（一次
     实施发现：bevy 元组 `add_systems` **不链序**——无显式边时 Escape 帧可能先移动
     后翻转，guards 实测捕获）；
   - doc 头新增「Game UI」导览段（hud.bsn=2D 画布产物/四屏绑定机制/按钮事件流/
     via 注册/分辨率纪律 percent-flex+px 仅尺寸/U5 边角注记「UI tab 聚焦 Play 预览
     画布」）。
2. **模板 `assets/hud.bsn.template` 种子**（新文件，改动面 2）：`UiSceneRoot` +
   `HudRoot` 标记 + 四顶层面板（Start/Hud/Pause/GameOver），单文档——
   - 四屏 `Visible` 绑定：read `Res(<crate>::GameState).menu/.paused/.game_over`
     bool 直读（Hud 屏经注册的 `not`——菜单开时藏）；
   - HUD：`Progress`+`ProgressFill` 血条（Field 绑定 read
     `[PlayerHealth.current, .max]` via `ratio` write `Progress.value`）+ `"{current} /
     {max}"` 文本 + `"Pickups: {n}"` 文本（`PickupCount.0`）；
   - 三按钮：`bevy_ui_widgets::Button` + Action 绑定 `ScreenPressed` literals
     `button=start/resume/restart`；feathers 主题 token 上色（ThemedText/
     ThemeBackgroundColor/InheritableThemeTextColor）；
   - 布局 percent/flex 纪律：遮罩 Absolute+四边 0+100%×100%、HUD Row 顶左、
     按钮列居中（flex_column align center）；px 仅尺寸/内边距；
   - **种子形状经真实 loader 全链验证**（下 §二）——三处类型路径/字段形状 bug
     被探针与 guards 先后捕获修正（见 §六 偏差 2）。
3. **scaffold**（改动面 3）：无新 module（UI 零 gating，事实四）；physics 占位族
   扩腿——`{{module_physics_statements}}` 增 `spawn_hazards`/`hazard_damage`/
   `respawn_pickups_on_restart` 注册；`{{module_physics_demo}}` 增 `Hazard` 组件+
   `spawn_hazards`（碰撞层教学表 0b100/0b001 行**从 doc 变活**）+`hazard_damage`
   （TriggerEvents `enters()`→`take_damage`，同 GameState gate）+
   `respawn_pickups_on_restart`（重开=拾取重生+计数/速度清零；`spawn_pickups` 重构出
   `spawn_pickup_line` 复用）；collision-layers doc 段指向活的 `spawn_hazards`。
   **teaches +2：85→87**——`new_game_project_teaches_the_ui_pattern`（lib.rs 17 针+
   hud.bsn 15 针含 UiSceneRoot/四屏名/绑定五形/raw 路径/`[[\"button\",\"start\"]]`；
   无物理形态 6 项保留针=UI 零 gating 活证）+ `new_game_project_teaches_the_health_
   pattern`（12 针通用+7 针 hazard 形态；无物理 3 退场针[struct Hazard/hazard_damage/
   avian3d]+5 保留针含 `take_damage(&mut health, PLAYER_DAMAGE)` Interact fallback）。
4. **guards 新文件 `tests/guards/game_ui.rs`**（改动面 4，六组断言，228=222+6）：
   种子经 CARGO_MANIFEST_DIR 读模板渲染（`{{crate_name}}→guards::game_ui`，与测试
   crate 类型注册路径一致），系统为模板忠实本地移植（T11 口径）。
5. **jackdaw_runtime prelude 增 `pub use jackdaw_bind::BindContext;`**（模块级+prelude
   各一处，T11 CameraRig re-export 同款先例）——模板 Cargo 零新依赖即可接线；
   存量工程零 Cargo 改动获得 BindContext。
6. **T09 引用面**：`action_bindings.rs` 增 U7 探针测试（+21 件中第 21 件，见 §二）；
   book/game-input 的 Pause 消费面重述按方案归 T3（本轮零 book 改动）。

## 二、U7 探针 + 红绿证据（机制层）

**U7 探针结论（方案 227 行首项验收）**：unit-struct 事件**可用**——
`#[derive(Event, Reflect, Clone, Default)] #[reflect(Event, Default)] struct StartPressed;`
+ 空字段 Action 绑定（`fields: [], literals: []`）→ `Activate` 触发后事件到达 observer、
`BindFailures` 空（`t12t1_u7_probe.log`，action_bindings 21/21）。**事件形态定稿仍按
裁定取 `ScreenPressed { button: String }` 单事件多按钮**（payload 区分按钮，教学面最小；
探针保底证明「将来拆四事件」也无机制障碍）。附带定案：**带 literal 但无实体字段的事件
必须 derive plain `Event`**——`EntityEvent` derive 强制实体字段（编译期报错，见 §一-1）。

**红→绿三件**（guards/game_ui.rs 内 in-run 红腿，T11 碰撞件同款口径）：

| # | 红腿（缺件失败形态） | 绿腿 | 结果 |
|---|---|---|---|
| ① 装载（U1） | 不 spawn_hud 的游戏（T12 前全部工程的形态）：`Node` 实体数=0、`BindFailures` 无——模板零 UI 的红形态钉死 | spawn+wire 后：HudRoot 标记在、UiSceneRoot 在、**UI 根无父**、四屏+七部件在场、`BindFailures` 空、BindContext=玩家 | PASS |
| ② 血条（U3，兼 U2 运行态红证） | hud 已载但 context 玩家**无 PlayerHealth**：三条组件路径绑定失败进 `BindFailures`（warn-once 台账），`Progress.value` 保持作者值 1.0 不动 | 87/100→value=0.87 精确、文本「87 / 100」、拾取「Pickups: 3」；30/100→0.3+「30 / 100」；`take_damage(200)`→钳 0+「0 / 100」+**game_over 翻转**；全程零失败 | PASS |
| ③ 按钮 | 无 observer 的 app：`Activate` 派发 `ScreenPressed` 无人听——三态 bool 原样（不 panic） | Start→menu=false；Resume→paused=false；Restart→game_over=false+**血回满+回 PLAYER_SPAWN**（位移过 (9,9,9) 后精确复位） | PASS |

④**分辨率数学断言四档**（800×600/1280×720/1920×1080/2560×1440，每档同断言）：无头
布局的机制=Camera2d+`Viewport.physical_size`+`ComputedCameraValues.target_info`+
`IsDefaultUiCamera`（无 camera 时 bevy_ui 按零尺寸布局）；断言用 `UiGlobalTransform`
（**平移=节点中心**）+`ComputedNode.size`：StartScreen 遮罩左上 (0,0)+铺满窗口、
HudRoot 铺满、血条左上内边距 (12, y∈[11,40))、像素尺寸 180×10 恒定、StartButton
在窗口内+水平居中（±2px）——**四档全绿**（percent/flex 纪律的机械化定义）。
⑤**屏随状态**：menu 开→Start 可见/Hud 藏；menu 关→互换；paused→Pause 屏（Hud 仍在
遮罩下——绑 menu 不绑 paused，教学语义）；game_over→结束屏+Pause 屏回藏。⑥**暂停
gate**：menu/paused/game_over 三态 W 按住零位移；运行态 4 m/s×dt 精确位移；Escape
翻转 paused；Interact 键扣血 15（无物理 fallback 活证）。**全套 PASS**
（`t12t1_guards.log`，guards 全量 228/228=222+6）。

## 三、T09/T10/T11 回归（放行条件）

| 任务 | 腿 | 证据 | 结果 |
|---|---|---|---|
| T09 | 五动作行为格 | guards `game_input` 模块全绿（fast+guards 双含）；**Pause 消费面重钉**：info! 占位→`handle_pause_action` 真翻转（guards ⑥ Escape 双态断言+模板显式 `.before(move_player)` 边）；Move/Jump/Look/Interact 量纲未动（T11 形态保留） | PASS |
| T10 | 拾取链 | guards `physics_triggers` 全绿；模板侧 `collect_pickups`/`PickupCount` 零改动（diff 核实）；新增仅 restart 重生 observer（不触碰既有链）；hazard 碰撞层行与拾取互不干扰（memberships 0b100×filters 0b001 数值表在 teaches+doc 钉死） | PASS |
| T11 | 玩家链+paused gate | guards `player_controller` 全绿（5 件）；move_player 双形态 gate 增补（guards ⑥ **WASD 位移双态断言**：三屏态零位移/运行态精确位移）；gate 在两占位形态文本级一致（teaches 双形态针） | PASS |
| — | crate 级回归 | jackdaw_bind 全部集成测试（含 hud_scenario/runtime_bindings 先例）+ jackdaw_runtime 全部集成测试 + jackdaw_scaffold lib 87/87 + fast 2963/2963 | PASS |

**T09 量纲重钉表（消费面变化，钉死非放宽）**：

| 动作 | T09 旧量纲 | T12 新量纲 | 证据 |
|---|---|---|---|
| Pause | `info!("Pause!")` 日志占位 | **Escape→`state.paused` 翻转**（menu/game_over 守卫）→暂停屏显隐+move_player gate；Resume 按钮同 bool | guards ⑥（Escape 解暂停+gate 双态）；teaches ui_pattern 针 |
| Move/Jump/Look/Interact | T11 形态 | 未动（Interact 仅在**无物理形态**从 info! 升级为扣血 fallback——决策 8-A，物理形态保持 info!） | guards ⑥+teaches health_pattern |

## 四、模板实编与暖工程

- **暖工程**：`/Users/zhanglinbo/workspace/loop-mac/t12t1-game/t12t1-game`（`jd new`，
  physics 全开，9 文件含 **assets/hud.bsn**=种子渲染产物）；main.rs 挂
  `JackdawRemotePlugin(15702)`（T11-T2 暖工程惯例，测试注入非模板本体，已记档）。
  `cargo build` 冷编**完整通过**（`Finished ... in 3m 45s`，含 avian 全家桶）——模板
  UI 段活体编译证据（`t12t1_warm_build.log`；日志内 "error" 字样全为 thiserror 等
  crate 名，全文复核零编译错误）。
- scaffold_e2e（嵌套冷编 20-40 min）本轮未跑，归 T3 落袋（T10-T2/T11-T1 同款偏差）。

## 五、门禁（日志全文复核；归档 `loop/reports/t12t1_*`）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **CLEAN** | `t12t1_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets -- -D warnings` | **CLEAN** | `t12t1_clippy_ws.log` |
| Lint 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **CLEAN**（例行；本轮未改物理 crate） | `t12t1_clippy_physics.log` |
| 单测 | `cargo test --workspace --lib` | **全绿**（scaffold **87/87**=85+2） | `t12t1_libtests.log` |
| fast | `cargo xtask fast` | **2963/2963 passed**（T11 基线 2961+2 teaches） | `t12t1_gate_fast.log` |
| guards 全量 | `cargo test --test guards` | **228/228**（222+6 新） | `t12t1_guards.log` |
| 改动面 crate 测试 | `cargo test -p jackdaw_bind --tests` / `-p jackdaw_runtime --tests` | 全绿（action_bindings 21/21 含 U7；hud_scenario/runtime_bindings/ui_scene_ownership 等先例全数不破） | `t12t1_bind_tests.log` / `t12t1_runtime_tests.log` |
| U7 探针 | `cargo test -p jackdaw_bind --test action_bindings` | 21/21 | `t12t1_u7_probe.log` |
| 暖工程实编 | `cargo build`（loop-mac/t12t1-game） | 通过 | `t12t1_warm_build.log` |

## 六、偏差与记档

1. **⚪ `jackdaw_runtime` prelude re-export `BindContext`**（方案改动面 1-4 未列
   runtime 改动）：模板与 guards 只依赖 `jackdaw_runtime`（不直接依赖 jackdaw_bind），
   `wire_hud` 需要 `BindContext` 类型；T11 CameraRig re-export 同款先例（决策 2 同
   精神：存量工程零 Cargo 改动）。一行+注释，runtime 侧无逻辑改动。
2. **🟡→已修 种子形状 bug 四处**（前三处⚪为本轮探针/guards 捕获；第四处为 QA
   红证复演发现、按 `t12-t1-qa.md` §四修正单返工——QA 判 FAIL 退回一轮小修）：
   ①`Text` 的 TypePath 是 `bevy_ui::widget::text::Text`（编辑器 Label 同款），不是
   `bevy_text::text::Text`——错误路径静默不落组件、绑定进 `BindFailures`（runtime
   loader 集成探针捕获）；②`Node` 无 `position:` 字段——遮罩定位须写
   `left/right/top/bottom` 四字段（组件级静默丢弃，guards 加 Node 在场断言钉死）；
   ③**裸类型行（HudRoot 标记）需 `#[reflect(Component, Default)]`**——apply 走
   ReflectDefault 构造，缺 Default 时类型已在注册表但**静默不落**、也不进
   UnresolvedTypes（guards ①「marker loaded」红→绿捕获）；
   ④**【QA 新发现】暂停/结束屏遮罩 `BackgroundColor` 静默全透明**——种子
   `bevy_color::Color::Srgba(bevy_color::Srgba { … })` 内层 `Srgba` 用了 re-export
   路径，规范 TypePath 是 `bevy_color::srgba::Srgba`（fork srgba.rs:30；编辑器亲存
   `t02t2-light/13-scene-on-disk.bsn:21` 同款拼写为铁证）：组件仍插入但值落回退默认
   `LinearRgba(0,0,0,0)`——「半透明遮罩」实际不生效，不进 BindFailures 不可见。
   首轮归档 `t12t1_guards.log` 内本有 20 处该 warn 未复核（QA 计数核实），漏网通道
   与 §六-2①③同族。修正：两行改规范路径（:135/:185）+ guards ①新增遮罩色永久
   断言（`BackgroundColor == Srgba(0,0,0,0.6/0.92)` 精确相等；负向复演：回退旧路径
   断言即红，落 LinearRgba(0,0,0,0)）；暖工程 `assets/hud.bsn` 已手工同步；guards
   全量 228/228 重跑覆盖归档，**warn 形态扫描（cannot apply/cannot read/does not
   read as）20→0**（余 1 条=`scaffolded_component_flow.rs` 故意的 `NotBuiltYet`
   fixture——该测试的对象本身，非漏网）。「编辑器实开往返零 diff」的验收钉按方案
   归 T2/T3 真机腿。**修正提交**：本报告所在的 rework 提交（`loop/t12-game-ui`
   HEAD，标题 `T12-T1 rework (QA correction, t12-t1-qa.md §四): ...`）。
3. **⚪ guards 布局断言用 `UiGlobalTransform`+`ComputedNode`**：taffy `ComputedLayout`
   非 bevy_ui 公开导出（`pub use layout::*` 未含——内部私有 use）；transform 平移=
   节点中心，断言换算 `center - size/2` 为左上角（文件注释钉死）。
4. **⚪ guards 移动系统移植取无物理形态**（模块无关形态）：physics 形态 gate 与其
   文本级一致（teaches 双形态针+占位族同段），avian 深层行为由 player_controller
   既有 5 件继续承载（不重复移植）。
5. **⚪ 红证为 in-run 红腿+开发期实败记录**：装载/血条/按钮三红腿都是 guards 内
   双 app 对照（T11 碰撞红证同款）；开发期种子 bug 的实败形态（Text 路径/position
   字段/marker 三次红跑）未逐次归档——失败机制已全部钉进永久断言（Node 在场/marker
   在场/BindFailures 空），可随时复现。
6. **⚪ `update_game_over` 不改 PlayerHealth**（只读判定）：doc 钉「blood out means
   game over」；钳 0 的责任在 `take_damage`（绑定原样镜像组件——guards ③实测
   current=-5 时文本「-5 / 100」而 ratio 钳 0，故测试改经 take_damage 驱动血尽，
   组件源头钳制的教学形态）。
7. **⚪ 元组 `add_systems` 不链序的实施发现**：暂停翻转与 move_player 曾无显式序
   （guards ⑥捕获 Escape 帧先移动后翻转）→模板加 `handle_pause_action.before(
   move_player)` 注释边；UI 元组内部（wire_hud/pause/health/game_over）互不依赖
   保持无序。
8. **⚪ scaffold_e2e 归 T3**（T10-T2/T11-T1 同款）；warm build 已是本轮模板活体
   编译证据。
9. **buglist**：无打钩项（W2 多 UI 根测量口径维持不吸收——模板单 UI 根不踩）。

## 七、测试账本

| 套件 | 数量 | 结果 |
|---|---|---|
| guards game_ui（新文件） | +6 | ok |
| scaffold teaches（ui/health 形态） | +2（85→**87**） | ok |
| action_bindings（U7 探针） | +1（20→21） | ok |
| guards 全量 | 222→**228** | ok |
| fast（2961 基线） | +2 → **2963/2963** | ok |
| 暖工程实编 cargo build | — | 通过 |

## 八、工程处置与移交

- 暖工程 `/Users/zhanglinbo/workspace/loop-mac/t12t1-game/t12t1-game` **保留**
  （T2 绑定错误可见/真机四链直接复用；main.rs 的 JackdawRemotePlugin 为测试注入；
  `assets/hud.bsn` 已随 rework 手工同步规范 Srgba 路径）。
- **门禁日志纪律（QA 修正单要求，两轮漏网教训）**：后续每轮归档日志做 warn 形态
  扫描——`grep -E "cannot apply|cannot read|does not read as|UnresolvedTypes"`，
  逐条归因（测试故意 fixture 与真漏网分开计数）；本轮 rework 已执行（20→0，余 1 条
  为 scaffolded_component_flow 的测试对象）。
- 给 QA 的注意事项：
  1. **hazard 触碰即扣血**：物理形态走到 (2, 0.5, 0) 的红色传感器→血条 100→85；
     `enters()` 只在重叠开始帧触发（离开再进再扣）；menu/paused/game_over 态不扣。
  2. **无物理工程**：hud.bsn 原样携带（零 gating）；`PickupCount` 绑定会失败一条进
     `BindFailures`（拾取文本保持作者值「Pickups: 0」静态）——方案矩阵格 12 预期
     形态（「静态拾取文本」），也是 T2 绑定错误可见的真机素材；Interact(E) 键扣血。
  3. **编辑器实开验证（方案钉「往返零 diff」）归 T2/T3**：本轮种子经真实 loader 全链
     +四档布局断言，但「编辑器打开 hud.bsn→Save→重开零行为差」尚未真机验证。
  4. **UI tab 聚焦 Play 的 U5 边角**：UI-only 世界（预览画布语义），doc 已注记，T2
     实测记档。
  5. 暖工程 BRP 15702 在场（JackdawRemotePlugin 测试注入）；`GameState`/`PlayerHealth`
     经 reflect 自动注册可直接 scene_snapshot/BRP 采样（四屏 bool 断言通道现成）。

**提交**：见 git log（显式 pathspec：runtime 一文件+scaffold 一文件+模板两文件+
bind 测试一文件+guards 两文件；既存噪音 .gitignore/buglist.md 未触碰）。
