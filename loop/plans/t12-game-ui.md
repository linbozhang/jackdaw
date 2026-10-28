# T12 游戏 UI 制作与交互闭环 — 实施方案

> 策划产物（2026-10-28，基于本地 main **aece6ddf**（T11 闭环 2bae9629 → A3/A4 闭环 ba5f1b58 →
> ledger aece6ddf）全量只读调研：编辑器 src/、crates/（jackdaw_bind / jackdaw_widgets_runtime /
> jackdaw_runtime / jackdaw_scene_types / jackdaw_scaffold）、bevy pinned fork
> `/Users/zhanglinbo/workspace/bevy-fork-pinned` 的 bevy_ui / bevy_ui_widgets / bevy_feathers
> 实读；不建分支、不改代码）。需求来源：`loop/plans/roadmap-game-dev.md` T12（P1 第六项，
> T08-T11 已闭环，A3/A4 已闭环）。
> **验收原文**（roadmap 第 26 行，逐字核实）：「补齐 UI 画布/布局/按钮事件/数据绑定+四个示例
> 界面（开始/HUD/暂停/结束）。**验收=按钮触发真行为、血条绑数据、常用分辨率布局正确、
> 绑定错误可见。**」
> 拆解（策划口径，供矩阵与验收对齐）：「UI 画布」=编辑器 2D UI 画布（**已在场**，见事实一）
> +游戏侧把画布产物当真 UI 用（模板装载）；「布局」=flex/grid 授权（控件面板已在）+**常用
> 分辨率下正确**（=分辨率档位表内锚定/比例/居中不破，验收句的独立腿）；「按钮事件」=授权
> Button 的点击经 picking→`Activate`→绑定 `Action`→游戏事件→**真行为**（状态切换/重开），
> 不是 log 占位；「数据绑定」=授权 `Bindings` 把活数据（随玩法变化的 Health/PickupCount）驱
> 到血条/文本；「四个示例界面」=模板自带的开始/HUD/暂停/结束四个可编辑可运行的屏；
> 「绑定错误可见」=**作者能看见**绑定坏了（编辑器 badge=作者态已有；**Play/PIE 形态的运行期
> 失败当前不可见**，见 U2——验收腿的缺口主体）。
> buglist 游戏-UI 域**零直接条目**（全量扫描：Y6 是视口坐标轴标签、W2 是画布多 UI 根测量口径、
> Y10-Y15/W13-W17 是编辑器 chrome、W27 键位——见 §一重叠表）；缺陷主体是本方案新发现的
> **U1-U8**（U 系：UI，避开 buglist R/Y/W/A/N 系、T08 P 系、T09 I 系、T10 F 系、T11 C 系）。
> 真机口径：**macOS（本机）**，bash+curl+jq 驱动 BRP（`t11t3-matrix-{a3,c}.sh` 形态复用）；
> direct run 走游戏自身 BRP 15702；**勿设 RUST_BACKTRACE**（Mac debug 构建不可用且污染
> panic 形态，T11-T3 §八-3 口径）；N13（PIE connected panic）按 T11 口径绕行+记数。

---

## 0. 架构事实（核实结论，方案的地基）

**总判断：T12 不是「从零建 UI 系统」——编辑器画布/控件/绑定作者面与游戏侧 UI 加载/绑定/
widget 运行时已经全套在场且被测试覆盖；T12 的「补齐」=把这些能力闭环成模板自带的四屏
示例+活数据源+错误可见面。** 七条事实：

- **事实一：编辑器的 UI 画布与可视化摆 UI 已经是成品面，本轮零新建需求。**
  - 画布：`scene.new kind=ui` 建 UI 场景文档（`src/scenes/operators.rs:64`「A UI screen,
    authored on the 2D canvas」、`:80-106` kind=ui/ui=true、`:154` seed）；2D 画布视口
    （`src/viewport_2d.rs`，缩放/标尺/参考线）；根组件 `UiSceneRoot { reference_size }`
    默认 1280x720（`crates/jackdaw_scene_types/src/lib.rs:179-194`）；画布参考线
    `CanvasGuides`（同文件 :206-228，"authored pixels from the canvas's top-left corner"）。
  - 控件：Add 菜单「UI」组 16 个控件族——Panel/Row/Column/Grid/Spacer/Separator/Progress
    Bar/Label/Image/Button/Checkbox/Radio/Toggle/Slider/TextInput/Dropdown/RadioGroup/Tabs/
    ScrollArea/Nine-patch（`src/builtin_extensions.rs:591-642` 图标表 16 条、`:688` 起
    `builtin_widget_definitions()` 全部定义；`src/add_entity_picker.rs:34` `UI_SECTION_PREFIX`）。
    **「编辑器可视化摆 UI」对 scene.bsn 的支持已存在**：控件以普通 Reflect 组件落文档
    （`bevy_ui::Node`+`bevy_ui_widgets::Button` 等，`spawn_widget` `src/builtin_extensions.rs:543-549`）。
  - 布局：flex/grid（fork bevy_ui layout）+ 一键布局预设 `ui.layout_preset`（锚定四角/
    居中/拉伸，`src/ui_layout_presets.rs:17-224`）+ 对齐吸附（`src/ui_align.rs`、
    `src/canvas_snap.rs`）+ 成组（`src/ui_grouping.rs`）。
  - 绑定作者面：Inspector 绑定卡 2817 行（`src/inspector/bindings_card.rs`）——五种绑定的
    结构化编辑、类型/字段/事件下拉（schema 驱动 `gather` :468-575）、**作者态校验 badge**
    （`path_error`/`binding_error` :797-955，行 badge+Tooltip :1349-1370）。
- **事实二：游戏侧运行时的 UI 装载与绑定求值已经全套在场，模板只是没用它。**
  `JackdawPlugin` **无条件**装 `jackdaw_widgets_runtime::AuthoredWidgetPlugin`（widget 载入
  默认值+自更新 observers）与 `jackdaw_bind::JackdawBindPlugin`（绑定求值），并排好三条
  PostUpdate 顺序边（text/node/chrome 都在 `BindEvaluationSystems` 之后、UI Layout 之前，
  `crates/jackdaw_runtime/src/lib.rs:267-294`）。UI 场景文档经 `JackdawSceneRoot` 加载时
  **UI 根保持无父 ECS 根**（`lib.rs:1174-1215`，注释「Bevy's layout only lays out `Node`
  trees that start at an unparented entity」），所有权/清理由 `JackdawSceneMember` 承担
  （`lib.rs:456-471`；测试 `tests/ui_scene_ownership.rs` 两条）。多根并存：一个游戏可 spawn
  多个 `JackdawSceneRoot`（3D 主场景+UI 场景并行），**PIE 覆盖只换第一个根**（"further
  roots are left alone"，`lib.rs:615-618`、`apply_pie_scene_override` :636-646）——模板
  「先 scene.bsn 后 hud.bsn」的装载序即天然 PIE 兼容。
- **事实三：绑定机制完备且 HUD 场景已有端到端测试先例。** 五种 `Binding`（Field/Text/
  Visible/Value/Action，`crates/jackdaw_bind/src/types.rs:97-158`）；`via` 函数走
  `AppFunctionRegistry`（`evaluate.rs:62-127`，**游戏侧 `register_function` 注册，运行时零
  内置库存**——仅 `schema_cli.rs:161` 测试注册过）；`as_percent` 把分数写成 `Val::Percent`
  （`evaluate.rs:598-601`）；`Field`→组件字段、`Text`→`Text.0` 格式化（`evaluate.rs:637-653`，
  "{}" 占位）、`Visible`→`Visibility`（:605-634）、`Action`→点击 `Activate` 构造命名域结构体
  事件并 `world.trigger`（`actions.rs:33-70,262-406`；事件须 named-field struct +
  `#[reflect(Event, Default)]`，Entity 字段仅 `entity` 名可由 context 填）。**直接先例**：
  `crates/jackdaw_bind/tests/hud_scenario.rs`——`Health{current,max}` 组件 + `BindContext`
  + `ratio`/`is_zero` via + 血条宽度 as_percent + "{} / {}" 文本 + `Visible` 血尽变红 +
  按钮 `Activate`→`OpenSettingsMenu` 事件 observer，全链 headless 断言。场景文档往返先例：
  `crates/jackdaw_runtime/tests/runtime_bindings.rs`（bsn 里带 `Bindings` 组件加载即求值）、
  `progress_bindings.rs`/`text_value_bindings.rs`/`authored_widgets.rs`。
- **事实四：widget 运行时+主题在游戏构建里默认全开。** `jackdaw_widgets_runtime`（1594 行）
  提供 `Progress/ProgressFill`（`progress_fill_follows_value` 把 `Progress.value`→填充
  `Node.width` 百分比，`lib.rs:992-1007`）、`TextValue`（文本输入的 Reflect 半边）、
  Dropdown/Radio/TabStrip chrome 重建等；游戏 `jackdaw_runtime` 的 **`render` feature 默认开**
  且拉 `jackdaw_widgets_runtime/feathers`（`crates/jackdaw_runtime/Cargo.toml:71,84-86`），
  暗色主题自动兜底安装（`widgets_runtime lib.rs:277-290`）——**UI 段无需任何 module/
  feature gating**（bevy_ui/bevy_ui_widgets 在游戏 bevy default features 里，
  `templates/game/Cargo.toml.template:17` + `jackdaw_project_build/src/bevy_source.rs:24,35-40`）。
- **事实五：PIE/导出通道对游戏 UI 天然友好。** windowless PIE 的虚拟主窗口让「cursor
  position, **UI layout**, and focus reads all keep working … **menus stream without a camera
  rig**」（`crates/jackdaw_runtime/src/pie_windowless.rs:5-12`，虚拟窗 :99-118，
  `IsDefaultUiCamera` 单标记 :120-145）；流尺寸=Game 面板像素尺寸（`src/live_frame_view.rs:169-178`
  `game_panel_pixel_size`），`StartFrameStream{width,height}` 可随时重设（协议
  `jackdaw_pie_protocol/src/event.rs:84-95`）——**分辨率档位测试的 PIE 腿可直接驱动**；
  输入转发 `Key{logical}/MouseButton/CursorMoved`（协议 `input.rs:15-28`）——**按钮点击链
  可走真 picking**（编辑器 `input.pointer` press→转发→游戏 picking→`Activate`→绑定→事件，
  T09 capture 通道同款）。四通道（编辑器/PIE/direct/导出）先例：`loop/reports/t11-t3-report.md`
  格 10。
- **事实六：模板与数据源现状——零 UI、零活数据。** `lib.rs.template` 无任何 UI 引用；
  `GameConfig.player_health` doc 明言「has no system yet; a HUD or player module reads it
  when you write one」（`templates/game/src/lib.rs.template:204-206,42`）——静态 config 数字，
  不是「绑数据」的教学本意；在场的活数据只有 T10 的 `PickupCount`（组件，拾取链已验）与
  T09 的 Pause 动作（Escape，现仅 info）。模板装载序现状只有 `spawn_scene` 一个根
  （`lib.rs.template:177-181`）。
- **事实七：绑定错误可见性的现状=作者态可见、运行态盲区。** `BindError` 36 变体
  （`crates/jackdaw_bind/src/error.rs`），求值失败 warn-once 进 `BindFailures` 台账
  （`types.rs:191-197`）；crate doc 自述：「**The log is the only place a runtime failure
  shows up: the editor badges what it can see from the type registry, but does not read
  `BindFailures`**」（`jackdaw_bind/src/lib.rs:74-80`）。PIE 协议里 `StateEvent::Log{level,
  message}` **变体已定义但两端零接线**（`event.rs:39-42`；grep 证实 runtime/editor 的 pie.rs
  均不产生不消费）；编辑器侧 `StderrTail` 只在 stop/崩溃诊断时报告（`src/pie.rs:2163,2183,
  2207,2243`），无活日志面。T09 尾巴「PIE 日志面挂 backlog」正是同一缺口。
- **附带核实（A3+A4 遗留问）：`bevy_ui_widgets/text_input.rs` 平台键的归属。** 该 crate 属
  **bevy pinned fork 本体**（`bevy-fork-pinned/crates/bevy_ui_widgets/`，19 个文件），游戏以
  `bevy::ui_widgets` 引用（`jackdaw_widgets_runtime` 已 import 并注册全部类型
  `lib.rs:19-22,313-329`）；「平台键」=其 `mac_host()` 快捷键布局（macOS 用 Cmd 做
  Home/End/词导航，非 wasm 编译期 `cfg!(target_os="macos")`，`text_input.rs:44-63`）——
  **Mac 游戏侧开箱即 Cmd 语义，无额外接线**；A3+A4 的「platform select-all key」修复
  （ba5f1b58）是编辑器侧 observe 守卫，不影响本归属结论。`bevy_feathers` 同为 fork crate，
  经 feathers feature 可达（事实四）。

---

## 一、现状与缺陷矩阵

### A. 模板与示例面（验收词「四个示例界面/UI 画布」）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **U1** | 🔴 | **模板零 UI、四屏无载体**：新工程无 UI 场景文件、无装载代码、无屏显状态机/事件——「开始/HUD/暂停/结束」四词无任何落点；用户在编辑器画好 UI 也没有「游戏怎么把它当真 UI 用」的范本（装载序/BindContext 接线/数据源三件事全缺教学） | `templates/game/src/lib.rs.template` 全文零 UI；`templates/game/assets/` 仅 scene.bsn |
| **U3** | 🔴 | **血条无活数据源**：`GameConfig.player_health` 是静态作者数字（doc 自述无消费者）；无 Health 组件、无伤害/恢复通路——「血条绑数据」若绑静态 config 则数据永不变化，教学与验收双落空 | `lib.rs.template:204-206`；事实六 |
| **U6** | 🟡 | **via 函数零库存**：`AppFunctionRegistry` 无任何内置函数（仅测试注册过 `my_game::double`）——血条 current/max→分数、血尽判定（is_zero）这类最常用的换算，每个游戏都要从零发现「要自己 register_function」 | `jackdaw_bind/src/evaluate.rs:62-127`；`schema_cli.rs:161` |
| **U7** | ⚪ | **无字段（unit struct）事件未验证**：`action_bindings.rs` 所有测试事件都带字段；`event_shape` 走 `as_struct()`（`actions.rs:272-283`），unit struct 的 TypeInfo 也是 Struct 形态——大概率可用但无测试背书；模板四屏事件若想写 `struct StartPressed;` 需 5 分钟探针定案（或直接带字段规避） | `actions.rs:262-296`；`tests/action_bindings.rs` 事件形态盘点 |

### B. 可见性与通道（验收词「绑定错误可见/布局正确」）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **U2** | 🔴 | **绑定错误 Play 形态不可见**：运行期绑定失败（context 实体缺组件、资源不在、事件字段不匹配、via 不存在——恰是用户最常犯的错）只 warn-once 进游戏进程日志；PIE 里用户看不到（`StateEvent::Log` 零接线、StderrTail 仅 stop 时报告）；direct/导出形态看得到但散在 stderr。「绑定错误可见」验收腿的缺口主体 | 事实七全文 |
| **U4** | 🟡 | **分辨率缩放语义未定**：`reference_size` 只有编辑器画布消费（`viewport_2d.rs:793,1122,1220`），游戏侧零消费——授权布局按游戏窗口实际尺寸排布，px 元素不随窗口缩放、reference 不产生缩放因子。「常用分辨率布局正确」需要钉死语义（percent/flex 纪律 vs 新增 UiScale 机制，见决策 5） | grep `reference_size` 全仓仅编辑器+scene_types |
| **U5** | ⚪ | **PIE 下 UI-tab 聚焦时 Play 的语义边界未文档化**：编辑器把当前 tab 文档经 `JACKDAW_PIE_SCENE` 换进第一个根——UI 场景 tab 聚焦时 Play，3D 主场景被替换成 UI-only 世界（可解读为「预览这张 UI」，但模板玩家/相机链全失效）。行为合理、需文档+矩阵记档，不需改机制 | `runtime lib.rs:615-646`；事实二 |
| **U8** | ⚪ | **多 UI 根画布测量口径**（buglist W2）：2+ UI 根时画布尺寸/标尺各按不同根测量——模板单 UI 根不踩；buglist 维持不吸收 | `buglist.md` W2（`viewport_2d.rs:790-793` vs `:1119-1122`） |
| — | ✅ | **正向资产（不用重建）**：编辑器画布+16 控件+布局预设+绑定卡（事实一）；运行时 UI 装载/绑定/widget/主题全链+6 件集成测试（事实二/三/四）；PIE windowless UI 流送+输入转发+流尺寸可控（事实五）；bevy fork 的 flex/grid 布局、`bevy_ui_widgets` 全家、feathers 主题、Mac Cmd 快捷键（事实四/七附带） | §0 |

**统计：🔴 3（U1、U2、U3）｜🟡 2（U4、U6）｜⚪ 3（U5、U7、U8）｜✅ 四块地基**

### buglist 重叠表（UI/按钮/血条/HUD/绑定/widget 域全量扫描）

| 条目 | 一句话 | T12 处置 |
|---|---|---|
| W2 | 多 UI 根时画布/标尺测量口径不一致 | **不吸收**：模板单 UI 根不踩；buglist 维持（T12 矩阵记档边界） |
| Y6 | 坐标轴指示器物理/逻辑像素混用 | **不吸收**：视口 gizmo 域。备注维持 |
| Y10-Y15、W13-W17 | DockTree 环校验/自定义属性静默归零/u64 截断/状态栏通知/文本分配/双扫描/字符串绕圈/Val 资源守卫 | **不吸收**：编辑器 chrome 域；W17 已修。备注维持 |
| W27 | 旧键位链路表外键序列化丢数据 | **不吸收但知悉**：若 T12 真机用键位输入 UI（Tab 导航）遇怪象先查此账 |
| A3/A4（已闭环） | standalone fork 注入/Mac 基线 | **知悉**：T12 导出腿 standalone 发货已修（f7f57ab7 gate 在 dev checkout）；text_input 平台键归属已核实（事实七附带） |
| 其余 | 无游戏 UI/绑定运行时域条目 | 无动作 |

> 如实报告：该域 buglist 零直接条目——编辑器 UI 作者面与绑定运行时是此前（fork bevy 0.20
> 升级波次）建成的，游戏模板侧从未接入，没有用户可踩出的「游戏 UI」bug；T12 缺陷主体是
> 本方案新发现的 U1-U8。

---

## 二、分任务拆解（T1/T2/T3；无 T0 探针，U7 五分钟探针并入 T1 首步）

> **无 T0 的理由**（对齐 T10/T11 逻辑——探针只为消除「版本未知数」）：T12 两大依赖面均无
> 未知数——①UI/绑定机制全部是第一方 crate+集成测试常绿（事实二/三/四），HUD 场景端到端
> 测试就是本任务形态的先行示范（`hud_scenario.rs`）；②bevy fork 的 UI 能力已被编辑器自身
> 日用（feathers 面板）。唯一小问号 U7（unit-struct 事件）是 T1 内 5 分钟断言，不配 T0。

### T1「模板四屏 UI + 活数据源 + 接线」（U1+U3+U6+U7；决策 1/2/3/7/8）

**目标**：新工程模板自带开始/HUD/暂停/结束四屏——编辑器可打开再编辑（hud.bsn 是普通 UI
场景文档）、`cargo run`/Play/导出三态即玩；血条/文本绑活数据（Health/PickupCount）；按钮
经绑定事件触发真行为（开局/恢复/重开）；T08-T11 已验链路零破坏。

**改动面预估**：
1. **模板 lib.rs.template 新增 UI 教学段（~110-130 行，对齐既有教学密度）**：
   - `GameState`（`Resource, Reflect`，`#[reflect(Resource, Default)]`）——字段
     `menu/paused/game_over: bool`（决策 3：bool 字段直读，Visible 绑定免 via）；
   - 事件 `ScreenPressed { button: String }`（`EntityEvent, Reflect` + `#[reflect(Event,
     Default)]`；literals 填 `"start"/"resume"/"restart"`——单事件多按钮，教学面最小；若
     U7 探针支持 unit struct 也可拆四事件，程序裁量）；
   - `PlayerHealth { current: f32, max: f32 }` 组件挂玩家（`#[reflect(Component, Default)]`
     + EditorCategory）——初值从 `GameConfig.player_health` 注入（config 是作者数字、组件
     是活状态，doc 钉死两者关系，对齐模板「one value one behavior」纪律）；
   - via 函数注册：`ratio`（current/max→0..1）+ `is_zero`（hud_scenario.rs 同款两枚，
     决策 7）——`app.register_function(...)` 三行；
   - `wire_hud` 系统：等 hud 场景 spawn 后（`Added<JackdawSceneMember>` 或组件标记）给
     UI 根插 `BindContext(player)`——**runtime doc 钦点的接线形态**（`runtime lib.rs:462-466`
     「Mark the document's root with a component of the game's own and insert the context
     on the entity carrying it once the scene has spawned」）；hud 根以模板自有组件
     （如 `HudRoot`）标记，该组件 authored 进 hud.bsn；
   - 行为侧：`ScreenPressed` observer（menu→playing / paused 切换 / game_over→重置：
     血/拾取/玩家位置复位+回 playing）；`handle_pause_action`（T09 Pause 动作与 Resume 按钮
     同走一处状态翻转）；`damage_player`（决策 2/8：物理形态=T10 hazard 传感器经
     `TriggerEvents` 扣血——顺带把 T10 碰撞层教学的 hazards 0b100 行从 doc 变成活的；
     无物理形态=Interact 键扣血 fallback）；`move_player` 加 `!paused && !menu && !
     game_over` gate（暂停语义真行为）；血≤0→game_over；
   - `spawn_hud`：`.add_systems(Startup, spawn_hud)`——**在 `spawn_scene` 之后**注册第二
     个 `JackdawSceneRoot(asset_server.load("hud.bsn"))`（PIE 只换第一根=主场景，事实二）；
   - doc 头部新增「Game UI」导览段（画布→控件→绑定卡→Play 的全链路指引+分辨率纪律
     （决策 5）+U5 边角注记）。
2. **模板 `assets/hud.bsn` 种子**（新文件，编辑器序列化同款形状）：`UiSceneRoot{1280x720}`
   + `HudRoot` 标记 + 四个顶层面板：
   - 开始屏：全屏遮罩 Panel+标题 Label+Start Button（`Bindings`：Action→`ScreenPressed`
     literals `button=start`）；
   - HUD：左上血条（`Progress`+`ProgressFill`；`Bindings` Field：read `[PlayerHealth.current,
     PlayerHealth.max]` via `ratio` write `Progress.value`）+血量文本（Text `"{} / {}"` args
     同源）+拾取计数文本（Text `"Pickups: {}"` args `PickupCount.0`——组件路径走
     BindContext=玩家）；
   - 暂停屏：半透明遮罩+Resume Button（literals `resume`）+标题；
   - 结束屏：`game_over` 遮罩+结束文案+Restart Button（literals `restart`）；
   - 各屏根的 `Visible` 绑定：read `Res(GameState).menu / .paused / .game_over`（bool 直读）；
     HUD 反向（`via` 取反或用 `paused==false`——程序选最简教学形态，必要时加 `not` via）。
   - 布局全部 percent/flex+锚定预设形状（决策 5 的纪律示例：四角元素用 margin/百分比容器，
     无绝对定位依赖）。
3. **scaffold**：无新 module（UI 不是模块——零 gating，事实四）；teaches 测试 +2：
   `new_game_project_teaches_the_ui_pattern`（needle：GameState/ScreenPressed/BindContext
   接线/hud.bsn 文件在场+含 UiSceneRoot/四屏名/绑定 raw 路径抽查）+ `new_game_project_
   teaches_the_health_pattern`（PlayerHealth/ratio 注册/damage 通路双形态）；85→87。
4. **guards 新测试** `tests/guards/game_ui.rs`（headless，真插件链）：①hud.bsn 种子经
   runtime 加载→四屏实体在场（UiSceneRoot 无父）；②`GameState` 翻转→对应屏 Visibility
   切换（绑定求值后断言）；③Health 降→`Progress.value`==ratio（数值断言）+文本变更；
   ④按钮 `Activate` 手动 trigger→`ScreenPressed` 到达+状态翻转（hud_scenario.rs 形态）；
   ⑤**分辨率数学断言**（决策 5）：四档虚拟窗口（800x600/1280x720/1920x1080/2560x1440）
   跑 UI 布局后断言 ComputedNode：血条在左上角内边距处、开始屏遮罩铺满、按钮在容内——
   **每档同断言**（比例/锚定不破的机械化定义）；⑥暂停 gate：paused 时 move_player 零位移。

**验收标准（可执行可复现）**：
- [ ] U7 探针：unit-struct 事件可/不可用的 5 分钟断言（结果记入 T1 报告，事件形态定稿）；
- [ ] headless 红→绿①（装载）：无 `spawn_hud` 时 Play 无 UI（红）；有→hud 实体在场+绑定
  resolved 非 `BindFailures`（绿——顺带是 U2 的机制面红证）；
- [ ] headless 红→绿②（血条）：无 Health 组件时血条绑定失败进 `BindFailures`（红）；
  有→`Progress.value` 精确跟随 ratio（绿，两档 health 数值断言）；
- [ ] headless 红→绿③（按钮）：无 `ScreenPressed` observer 时点击无状态变化（红）；有→
  三按钮各翻对应状态（绿）；
- [ ] 分辨率数学断言四档全绿（⑥）；
- [ ] 暖工程实编 `cargo build` 通过+teaches 87/87（T10/T11 同款活体证据）；
- [ ] **T09/T10/T11 回归（放行条件）**：T09 五动作矩阵行为格（Pause 消费面变化=暂停真
  行为，量纲重钉）；T10 拾取链（PickupCount 0→3 复跑+HUD 文本随之变化是新增断言）；
  T11 玩家链（paused gate 只在暂停帧生效——WASD 位移断言双态）；
- [ ] quick 四门（fmt/clippy 全仓/单测/集成）。

### T2「绑定错误可见 + 真机交互链」（U2+U5；决策 4）

**目标**：「绑定错误可见」验收腿闭环——Play/PIE 形态下绑定失败用户看得见；四屏真机链
（按钮点击/血条变化/分辨率）全部真 picking 通道走通。

**改动面预估**：
1. **PIE 日志通道打通（决策 4-A）**：
   - runtime 侧：PIE attach 时给 bevy 的 tracing/log 面装转发层——`info/warn/error` 落
     `StateEvent::Log{level,message}`（节流：去重+每秒上限，帧流 lane 之外走 Reliable）；
     **首步探针**：bevy_log 的 Layer 接入形态（`LogPlugin` 的 default_filter 兼容/
     双订阅冲突）——受阻回落 4-B（编辑器读 StderrTail 活体轮询，管道已有 `src/pie.rs:97-118`）；
   - 编辑器侧：Game 面板（或 PIE 状态条）显示最近 N 条游戏日志——`warn/error` 用
     W13 的三档通知色；绑定失败（warn 文案含 BindError 语义）无需特判即入列；
   - `BindFailures` 读取面：编辑器不读该资源（crate doc 明言）；以日志行为准（错误文案
     已含实体/绑定序号）——不为此建 BRP 面（YAGNI，主控可否决升级）。
2. **坏绑定红绿（U2 机制证）**：fixture 里 author 一个 typo 绑定（如 `Health.currrent`）
   → Play → 日志面一条 `context entity lacks`/`unknown type` warn 可见→修正后消失；
   headless 侧 `BindFailures` 断言已有测试先例（`field_bindings.rs:118,148`）补 guards 一条。
3. **真机四链（Mac，bash+curl+jq，t11t3-matrix 形态）**：
   - 开始屏：PIE capture on→`input.pointer` 移到 Start 按钮坐标→press/release→（转发
     CursorMoved+MouseButton→游戏 picking→Activate→绑定→事件）→`GameState.menu` 经
     scene_snapshot/游戏 BRP 断言翻转+HUD 屏可见；
   - 血条：驱动伤害源（物理形态=移玩家入 hazard；无物理形态=`input.key E`）→多帧采样
     `Progress.value`/`Node.width` 或帧流像素抽验（血条色块宽度比）；
   - 暂停/结束/重开：Escape（T09 通道）与按钮两路各断言；重开=血/拾取/位置复位数字级；
   - 分辨率：PIE 流尺寸两档（如 1280x720 与 1920x1080）——Game 面板尺寸由编辑器布局
     驱动（panels 预设/布局 op 实测选定；不可达则用窗口化 direct run 手动 resize+截图，
     记档通道差异）→截图像素抽验（左上血条色块存在性+中央按钮存在性两档一致）；
   - 四通道一致（格 10 先例）：PIE=direct run（15702）=导出 staged 异目录启动，四屏
     行为+血条数字一致。
4. **U5 记档**：UI tab 聚焦 Play 的行为（UI-only 世界）实测一次+doc/教学注记。

**验收标准**：
- [ ] 真机①（按钮真行为）：Start/Resume/Restart 三按钮真 picking 点击链各有状态断言
  （非 log 占位）；Escape 与 Resume 双路一致；
- [ ] 真机②（血条绑数据）：伤害→血条填充与文本双通道变化（数值或像素）；血尽→结束屏；
- [ ] 真机③（绑定错误可见）：typo 绑定→PIE 日志面可见一条+修正消失（红绿同屏）；
- [ ] 真机④（分辨率）：两档流尺寸像素抽验布局不破+headless 四档数学断言（T1-⑥）互证；
- [ ] 真机⑤（四通道）：四屏+血条在 direct/导出通道同行为（环境降级口径按 T10/T11 先例）；
- [ ] T02/T03 回归：绑定卡编辑的提交链/undo（Bindings 组件是新可编辑类型）；T06 Stop
  铁证预演（Play 中绑定求值→Stop→hud.bsn SHA 不变）；
- [ ] quick 四门。

### T3「验收矩阵 + 文档收尾」（U4 文档腿+全任务终验）

**目标**：验收句四铁证（按钮真行为/血条绑数据/分辨率布局/绑定错误可见）矩阵化终验；
book 游戏 UI 章；roadmap 勾选。

**改动面预估**：
1. **真机验收矩阵**（截图+日志留档，模板工程+编辑器链双 fixture）：

| # | 场景 | 期望 |
|---|---|---|
| 1 | 新工程开箱四屏 | scaffold 新工程 → `cargo run`/Play：开始屏先见；Start 后 3D 世界+HUD 同屏（T11 玩家链在场） |
| 2 | **按钮触发真行为** | Start/Resume/Restart 真点击各翻状态；暂停时玩家不可动（WASD 零位移）；重开=血/拾取/位置复位 |
| 3 | **血条绑数据** | 伤害→`Progress.value`=current/max 精确比（数值断言）+像素抽验；文本 "{}/{}" 同步；血尽→结束屏 |
| 4 | HUD 第二数据 | PickupCount 0→3（T10 链复跑）HUD 文本随之；拾满的既有 level clear 行为不破坏 |
| 5 | 暂停双路 | Escape（T09）与 Resume 按钮等价；暂停屏遮罩下游戏冻结（move/gravity 面抽查） |
| 6 | **绑定错误可见** | typo 绑定红绿（T2-③ 复跑）；编辑器 badge（作者态）与 Play 日志面（运行态）双面各一格 |
| 7 | **布局·headless** | 四档分辨率数学断言全绿（T1-⑥ 复跑） |
| 8 | **布局·真机** | PIE 两档流尺寸像素抽验；导出腿窗口截图抽查一档 |
| 9 | 编辑器再编辑闭环 | hud.bsn 在编辑器打开（2D 画布）→改血条颜色/加按钮→Save→Play 生效→导出保留（「编辑→保存→重开→Play→导出」全链，roadmap 通用交付要求） |
| 10 | 四通道一致 | 编辑器/PIE/direct/导出四屏行为一致（t11t3 格 10 形态） |
| 11 | Stop 铁证回归 | Play（绑定求值中）→Stop→scene.bsn+hud.bsn SHA 双不变 |
| 12 | 无物理形态回归 | no-modules 工程：UI 全功能在场（Interact 扣血 fallback+静态拾取文本）；teaches 退场断言复跑 |

2. **book 文档**：新章 `book/src/user-guide/game-ui.md`（SUMMARY 排 game-input 后）：
   UI 画布（scene.new kind=ui/控件/布局预设/参考线）、四屏范本导览（hud.bsn 结构+GameState
   事件流）、绑定教学（五种 Binding+via 注册+BindContext 接线）、**分辨率纪律**（决策 5
   定案：percent/flex 优先、reference_size 只是画布基准、px 的适用边界）、绑定错误两面
   （作者 badge/Play 日志面）、U5 边角；`game-input.md` 交叉引用（Pause 消费面变化）；
   `player-controller.md`/`physics.md` 交叉（hazard 伤害源）；
3. **工具面核对（MCP 优先原则）**：现有工具预判足够——`ui_tree/ui_click`（编辑器 chrome+
   场景 UI 根，manual §7 已覆盖授权 UI）、`input.pointer/input.key/input.motion`（PIE 转发
   链）、`scene_snapshot`+游戏 BRP 15702（GameState/Progress/Node 断言）、`jackdaw/pie/
   export/wait`；**两个预判评估项**：①Game 面板流尺寸的程序化驱动（panels 布局 op 可达
   性——不可达则降级窗口化通道并记档）；②PIE 转发点击的坐标换算（面板 letterbox 内比例
   坐标→流坐标——若现成工具缺这一步，按 MCP 优先流程立项最小补面，不硬耗）；
4. buglist 核对（无打钩预期；W2 维持）、roadmap T12 勾选、台账记行、U 系结案清单。

**验收标准**：
- [ ] 矩阵 12 格全过（环境降级格如实标注+替代证据链，T10/T11 口径）；
- [ ] 全量门（fmt/clippy 全仓/单测/集成/doctests/docs——日志全文复核标准）；物理双包
  单跑维持 T10 口径；scaffold_e2e 冷编落袋一次（T11-T3 先例）；
- [ ] 用户 30 秒清单：①新工程直接 Play——看到开始屏，点 Start 出 HUD，走到 hazard 血条
  掉、血尽出结束屏，点 Restart 满血重来，Escape 出暂停屏点 Resume 回来；②在编辑器打开
  hud.bsn，把血条 Fill 换个颜色、开始屏标题改字，Save 再 Play——变了；③故意把一条绑定
  的字段名打错，Play 时 Game 面板能看到一条红色告警。

**QA 清单（放行标准，全任务）**：
- [ ] T1/T2/T3 各自验收全绿；U1/U2/U3 各有机制层红→绿（U1 红证=无 spawn_hud 无 UI、
  U2 红证=typo 绑定 Play 静默（改前）/可见（改后）、U3 红证=无 Health 时 BindFailures）；
- [ ] 验收句四铁证各有独立证据：按钮真行为（格 2）、血条绑数据（格 3）、分辨率布局
  （格 7+8 双通道）、绑定错误可见（格 6 双面）；
- [ ] T01-T11 既有防线回归：T09（Pause 消费面+改绑）、T10（拾取/hazard）、T11（玩家链+
  paused gate）、T02（绑定卡提交链/三处一致）、T03（undo）、T06（Stop 铁证=格 11）、
  T07（导出 manifest/异目录）、T08（GameConfig.player_health 注入语义）；
- [ ] quick 门（T1/T2）/ 全量门（T3）；门禁证据以日志全文复核为准。

---

## 三、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **「UI 画布/布局」的落点（本方案最高权重）** | 调研结论：编辑器可视化摆 UI **已是成品**（画布/16 控件/预设/绑定卡，事实一）且游戏侧装载/绑定运行时**已接线进 JackdawPlugin**（事实二）——不存在「代码式 vs 可视化」的二选。A=**编辑器授权 UI 场景（hud.bsn 种子）+ 模板游戏侧接线**（状态机/事件/数据源/via/BindContext 系统在 lib.rs.template，UI 结构在 bsn 里可编辑）：验收句「补齐」字面命中（把已有面闭环进模板）、用户拿到的就是可视化摆 UI 的范本、编辑器零新机制；代价=模板加 ~120 行+一个 bsn 种子文件（手工维护其序列化形状）。B=模板纯代码式 UI（Rust 构建 Node 树）：绕开 bsn 种子维护，但把「画布」验收词架空（用户在编辑器画的 UI 依旧无范本可循）、与已建成的绑定/控件体系割裂——**否决**。C=两者都教（代码式+授权式双范本）：模板膨胀一倍——**否决**（doc 一句话指路即可） | **A**；hud.bsn 的手工形状以「编辑器打开再保存往返零 diff」为验收钉（T1 验收含此断言） |
| 2 | **血条数据源（「血条绑数据」的"数据"）** | A=**`PlayerHealth{current,max}` 组件挂玩家 + 伤害/恢复通路 + `ratio` via 绑定**（hud_scenario.rs 同款）：数据随玩法活、组件 Inspector 可调（T02 三处一致顺带覆盖）、物理形态伤害源=hazard 传感器（把 T10 碰撞层教学的 hazards 行变活）；代价=模板多两系统。B=绑静态 `Res(GameConfig).player_health`：零新代码但数字永不变化——「绑数据」退化为「绑配置」，验收腿空转——**否决**。C=HudState view-model 资源（游戏系统汇总再喂 UI）：多一层间接，教学价值低于直绑组件 | **A**；初值注入链=config→组件（startup 一行），doc 钉死「config 是作者意图、组件是活状态」 |
| 3 | **屏显状态机形态** | A=**`GameState` Resource（bool 字段）+ `Visible` 绑定 + 单 hud.bsn 四面板**：切屏全走绑定（数据驱动 UI 的最纯教学）、headless 可断言、无新机制；代价=「互斥屏」靠纪律（多 bool 同真时多屏叠加——模板 observer 单点翻转规避）。B=bevy `States` + OnEnter/OnExit 系统插拔屏：互斥天生；但切屏是代码不是绑定，「数据绑定」教学面减半且 States 与绑定读面（`State<T>` 的 reflect 路径）要额外接。C=四文档动态加载/卸载：动 root 生命周期，T13（场景切换）域——越界 | **A**；B 的互斥严格性如 QA 实测踩到叠加怪象，回流按偏差流程记档 |
| 4 | **绑定错误可见的落点（U2）** | A=**PIE 日志通道打通**（runtime：log→`StateEvent::Log` 转发层；编辑器：Game 面板/状态条显示最近日志，warn/error 三档色）：顺带吸收 T09 尾巴「PIE 日志面」、全游戏调试受益（不止绑定）、协议变体已定义零格式协商；代价=转发层节流/双订阅边角（T2 首步探针）。B=游戏内 on-screen 诊断浮层（ BindFailures 画到游戏画面）：错误与游戏同屏最直观；代价=侵入每个游戏画面+发布形态要摘+编辑器里看不见。C=维持现状+文档：Play 形态依旧盲——验收腿落空——**否决** | **A**；B 作为 A 的游戏侧可选补丁（模板不加，doc 提示可自建）；A 受阻回落=编辑器活读 StderrTail（管道已有） |
| 5 | **分辨率语义（「常用分辨率布局正确」的机制面）** | A=**percent/flex 授权纪律 + 双通道断言**（headless 四档数学断言+真机两档像素抽验），不新增缩放机制：bevy UI 的百分比/弹性布局天然适配（血条宽=父容器%、遮罩=100%×100%、四角=margin 锚定）；reference_size 定位为「画布设计基准」；代价=px 元素（字号/内边距）不随分辨率放大——doc 写明适用边界。B=新增 `UiScale`=窗口/reference 缩放系统（运行时或模板）：整屏等比缩放、所见即所得最强；代价=新机制+新语义（谁缩、何时不缩）+与 bevy UiScale 既有 DPI 语义叠加的边角——超验收句必需。C=模板固定窗口 1280x720=reference：零成本但「常用分辨率」腿空转——**否决** | **A**；B 挂 open-challenges 一句话（T19 画质一致性/T20 示例游戏若需再议）；档位表=800x600/1280x720/1920x1080/2560x1440（headless 全档，真机两档） |
| 6 | **四屏一次做全 vs 分阶段** | A=**一次做全四个**：验收句列全四个名；四屏共享同一状态机/绑定面，边际成本低；血条/HUD 与开始/暂停/结束互为对照教学。B=先 HUD+暂停（数据面）、开始/结束延后：范围小但验收句四词缺二——矩阵直接缺格 | **A** |
| 7 | **via 函数归属** | A=**模板注册**（`register_function(ratio/is_zero)` 三行+doc 一段「游戏自带换算」教学）：零 runtime 改动、教学直面（用户学会 via 要自己注册）；代价=每个游戏重复三行。B=runtime 内置常用 via（ratio/not/format 等入 JackdawBindPlugin）：全局可用、绑定卡下拉即选；代价=runtime 面扩张+「内置集该多大」的口味问题+编辑器/游戏两侧注册同步 | **A**；B 的最小集（ratio+not）若 QA 实测绑定卡 via 下拉空得难受，可并入 T2 一并小步补（主控可否决） |
| 8 | **无物理形态的伤害 fallback** | A=**Interact 键扣血**（T09 五动作在场，无物理工程也有活数据）：输入驱动、可断言（`input.key E`）；与 T10/T11 fallback 形态同构（教学退场而非功能断崖）。B=时间自动掉血：无需输入但演示态突兀（放着不管就死）。C=无物理形态无血条数据（显示满条静态）：数据腿在 no-modules 工程空转 | **A**；物理形态=hazard 传感器扣血（TriggerEvents 复用）——两形态同一 Health 组件，`{{module_physics_*}}` 占位族扩一腿（hazard spawn+trigger 扣血段），teaches 双形态断言同步 |

小定案（主控可否决）：方案内编号 U1-U8；状态资源命名 `GameState`（避撞 bevy `State`）；
事件 `ScreenPressed { button: String }`；健康组件 `PlayerHealth { current, max }`；UI 根标记
`HudRoot`；hud 文件名 `assets/hud.bsn`；via 两枚 `ratio`/`is_zero`（+视决策 3 的取反需要
补 `not`）；分辨率档位表如决策 5；「血尽」=current≤0（clamp 显示 0）；模板 UI 段不做
module gating（事实四，零条件编译）；模块占位族仅 physics 段加 hazard 一腿（决策 8）。

---

## 四、风险与回滚

| 风险 | 缓解 |
|---|---|
| **PIE 日志转发层的 bevy_log 集成形态**（决策 4-A：tracing Layer 与 LogPlugin 默认订阅的冲突/重复输出/性能） | T2 首步探针（headless App 装 LogPlugin+转发层跑通再上真机）；受阻回落 StderrTail 活读（管道已有，编辑器侧改动不变）；节流（去重+每秒上限）+`Frames` lane 之外走 Reliable |
| **hud.bsn 手工种子与编辑器序列化漂移**（编辑器重存后格式/组件集合变化） | T1 验收钉「编辑器打开→Save→重开→Play 往返零行为差」；种子用 `runtime_bindings.rs`/`authored_widgets.rs` 测试里的同款 bsn 形状；漂移了以编辑器产物为准回写种子 |
| **headless 布局断言的字体检索异步**（Text 首帧空/布局未 settle） | hud_scenario/runtime_bindings 先例的「update×2+等 settle」模式；断言 ComputedNode 几何而非文本内容（文本断言等 asset 加载完成；分辨率断言只看盒子） |
| **模板膨胀**（lib.rs.template 现 17.6KB，UI 段再加 ~120 行） | doc 导览段精简（指向 book game-ui 章）；代码段对齐既有教学密度上限；T3 报告记录行数增量 |
| **PIE 点击的坐标换算与面板尺寸驱动**（T2 两个工具面预判项） | 先用现有 `input.pointer`+capture 通道试真（T09/T11 已验 motion 同链）；卡住按 MCP 优先原则立项最小补面（比例坐标→流坐标一步），不硬耗 |
| **N13 复发**（PIE connected panic，T11-T3 实测 10/10） | 按既有口径绕行+记数（不阻塞：Mac 上被系统错误处理器捕获不杀编辑器）；真栈仍缺（buglist 挂账，非 T12 域） |
| **Mac debug 无 RUST_BACKTRACE** | 全程不设；panic 形态证据=消息签名（T11-T3 口径） |
| **T09 Pause 消费面变化**（info! 占位→真暂停） | T1 放行条件含 T09 行为格复跑+量纲重钉（暂停=玩家冻结的位移断言）；`game-input.md` 交叉更新 |
| **回滚** | T1=模板两文件+teaches/guards（revert 即回现状，hud.bsn 不加载则 UI 缺席=现状）；T2=转发层插件式挂载（PIE attach 内条件装，摘除零痕）+编辑器日志面独立节点；T3=矩阵+book。全程零协议破坏性变更（`StateEvent::Log` 变体早已在枚举里）、零场景格式变更、零 PIE 投影改动——与 T05-T11 同款最大回滚保险 |

---

## 五、与 T01-T11 已建设施的衔接

1. **T09（InputActions）=暂停链与按钮外的输入面**：Pause 动作从 info! 占位升级为真暂停
   （本任务的「真行为」第一例）；Interact 键在无物理形态承担扣血（决策 8）；capture/
   `input.pointer` 转发通道是真机按钮点击的载体。
2. **T10（物理/触发器）=伤害源与拾取计数**：hazard 传感器+`TriggerEvents` 扣血（物理
   形态）；`PickupCount` 是 HUD 文本绑定的第二个数据源（格 4）；碰撞层教学表（0b100
   hazards 行）从 doc 变活。
3. **T11（玩家控制器）=HUD 的观察对象**：`BindContext(player)` 指向 T11 玩家；paused gate
   加在 `move_player`（新量纲=暂停帧零位移，T09 矩阵重钉的一部分）；四屏与玩家链同场景
   共存即「示例游戏」雏形（T20 的地基）。
4. **T08（GameConfig）=player_health 的作者半边**：config 数字→组件初值的注入链 doc 钉死
   （「作者意图 vs 活状态」），三态验收方法学复用。
5. **T02/T03（Inspector/undo）=绑定卡与 hud.bsn 的编辑面**：`Bindings` 是新的可编辑组件
   类型（提交链/三处一致/undo 顺带回归）；hud.bsn 的编辑→保存→Play 链走 T04 的原子写盘。
6. **T06/T07（PIE/导出）=验收通道**：PIE windowless 的 UI 流送/输入转发/流尺寸（事实五）
   是分辨率与点击链的主通道；四通道一致（t11t3 格 10 形态）；Stop 铁证扩到 hud.bsn 双文件
   SHA（格 11）。
7. **编辑器 UI 作者面（fork 升级波次建成）=本轮的地基本身**：画布/控件/预设/绑定卡/badge
   零改动复用；T12 只补「游戏把它当真」的范本与可见面——这正是「补齐」的准确读法。
8. **对 T13-T20 的奠基**：T13 启动场景（开始屏→关卡的正式形态=GameState+场景切换合流）；
   T16 音频（按钮音/BGM 挂进同一 hud.bsn）；T17 存档（音量/进度设置屏的控件面已在
   palette）；T20 示例游戏（四屏+玩家+拾取+胜负=本任务产物的拼装）。
9. **分支与行号基线**：本方案行号基于 main aece6ddf；T12 从 main 拉 `loop/t12-game-ui`
   （T1/T2/T3 分段续用同分支族）；既存噪音 `.gitignore`/`buglist.md` 不触碰（提交显式
   pathspec）。

---

## 六、耗时预估

| 段 | 预估 | 大头 |
|---|---|---|
| T1 | 1.5-2 天 | 模板 UI 段+hud.bsn 种子往返钉死+guards 六件+T09/T10/T11 复跑校准 |
| T2 | 1-1.5 天 | 日志转发层探针+编辑器日志面+真机四链（点击/血条/分辨率/四通道） |
| T3 | 1 天 | 12 格矩阵+book 新章+全量门（含 e2e 冷编落袋） |
