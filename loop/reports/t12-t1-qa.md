# T12-T1 QA 报告：模板四屏 UI + 活数据源 + 接线

> 验收对象：`loop/reports/t12-t1-report.md`，提交 7515fa11（分支 `loop/t12-game-ui`，
> 工作树 QA 时点干净——探针临时改动已 revert，`git status` 仅剩 loop 归档）。
> 方案：`loop/plans/t12-game-ui.md` §二-T1（167-239 行）+ §0 架构事实。
> 门禁归档 `loop/reports/t12t1_qa_*`（10 件：8 门禁 + 2 探针证据）。全部亲跑（Mac，
> 未设 RUST_BACKTRACE），日志全文复核（契约 2026-10-25 标准），exit code 仅辅助。

## 裁决：**FAIL —— 退回小修（一轮，范围极小）**

T1 验收清单（方案 227-239 行）逐项**全绿**（亲跑复核，见 §二）；但 QA 在红证复演中发现
**1 个程序未上报的产品缺陷**：`hud.bsn.template` 暂停/结束两屏的遮罩色静默丢失（方案改动面
2 明文「半透明遮罩」「game_over 遮罩」，实际两遮罩全透明）——方案点名的交付项未按 authored
形态生效，且恰是报告 §六-2 声称「全数钉进测试」的同一类形状 bug 的**第四处**（三处之外的
漏网）。修正=种子两行（re-export 路径改规范 TypePath）+一条 guards 永久断言+重跑覆盖归档，
预计 30 分钟内。修完 QA 快速复核（只需 guards+种子 diff+报告勘误）即可转 PASS 放行 T2。

---

## 一、门禁（QA 亲跑，日志全文复核零 error/FAILED/Diff）

| 门 | 命令 | QA 亲跑结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **CLEAN**（0 字节输出） | `t12t1_qa_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **CLEAN**（Finished 24.6s，零 warning/error） | `t12t1_qa_clippy_ws.log` |
| Lint 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **CLEAN**（Finished 12.3s） | `t12t1_qa_clippy_physics.log` |
| 单测 | `cargo test --workspace --lib` | **全绿**（scaffold **87/87**=85+2 亲数） | `t12t1_qa_libtests.log` |
| fast | `cargo xtask fast` | **2963/2963 passed**（≥2963 达标；内含 clippy 段同上形态） | `t12t1_qa_gate_fast.log` |
| guards | `cargo test --test guards` | **228/228**（50.4s；game_ui 6 件逐名核对 ok） | `t12t1_qa_guards.log` |
| bind 全测 | `cargo test -p jackdaw_bind --tests` | 全绿（action_bindings **21/21** 含 U7 探针亲跑 ok） | `t12t1_qa_bind_tests.log` |
| runtime 全测 | `cargo test -p jackdaw_runtime --tests` | 全绿（含 hud_scenario/runtime_bindings/ui_scene_ownership 先例） | `t12t1_qa_runtime_tests.log` |
| 暖工程 | `cargo build`（loop-mac/t12t1-game） | 通过（增量 0.5s 落袋；冷编 3m45s 归档在场，`assets/hud.bsn` 渲染正确 `t12t1_game::HudRoot`） | —（复用程序 `t12t1_warm_build.log`） |

程序归档日志抽查：`t12t1_guards.log` 与 QA 亲跑同形态（2963/228 可复现）；程序归档中
**已有 20 处** `cannot apply value 0 of 'bevy_ui::ui_node::BackgroundColor'` warn（见 §四
新发现）——程序侧未复核 warn 面，契约「日志全文复核」在程序侧执行不完整（随退回项一并整改
意识，不另计偏差）。

## 二、方案 §二-T1 验收清单逐项核实（全部亲验）

| 验收项 | 核实方式 | 结果 |
|---|---|---|
| U7 探针（unit-struct 事件） | 亲跑 `a_unit_struct_event_is_sent_by_a_fieldless_action`（21/21 内）；探针测 StartPressed 观察计数+BindFailures 空 | **PASS**（可用；定稿仍单事件+literal，合理） |
| 红→绿① 装载 | guards `the_hud_is_the_only_ui_and_it_loads_with_its_bindings_resolved` 亲跑 ok：红腿=无 hud 时 Node 实体数 0+BindFailures 空（钉死 T12 前形态）；绿腿=HudRoot 标记/无父 UI 根/四屏七部件/BindContext=玩家/零失败 | **PASS** |
| 红→绿② 血条 | guards `the_bar_follows_player_health_and_misses_it_loudly` 亲跑 ok + **QA 亲自复演红证**（§三）：缺组件→BindFailures 2 条+warn 原文可见+Progress 不动不 panic；绿腿 0.87/"87 / 100"/0.3/"30 / 100"/钳 0/game_over 两档精确 | **PASS** |
| 红→绿③ 按钮 | guards `buttons_flip_state_only_through_the_observer` 亲跑 ok：无 observer 时 Activate 三态不变（不 panic）；Start/Resume/Restart 各翻对应态+restart 血回满+位移 (9,9,9) 精确复位 PLAYER_SPAWN | **PASS** |
| 分辨率数学四档 | guards `one_layout_holds_across_the_four_common_resolutions` 亲跑 ok：800×600/1280×720/1920×1080/2560×1440 每档同断言（遮罩左上 (0,0) 铺满、HudRoot 铺满、血条 (12, y∈[11,40)) 180×10 恒定、按钮窗内+水平居中 ±2px）；机制=Camera2d+Viewport+IsDefaultUiCamera+`UiGlobalTransform` 平移=中心（偏差 3 口径属实，taffy ComputedLayout 确非公开导出） | **PASS** |
| 暖工程实编+teaches 87/87 | 暖工程增量 build 过；scaffold 87 亲数 | **PASS** |
| T09/T10/T11 回归 | §五 | **PASS**（headless 面） |
| quick 四门 | §一 | **PASS** |

## 三、guards 六组亲跑 + 红绿复核（抽血条②复演）

六组逐组核对（guards 文件 341-880 行 vs 方案改动面 4 之①-⑥）：**一一对应，无缺组**。
①装载红绿（含三处形状 bug 的永久断言，见 §四）②屏随状态（menu 开关互换/paused 显/game_over 显+Pause 回藏；Hud 遮罩下仍在=绑 menu 不绑 paused 的教学语义与报告口径一致）③血条红绿 ④按钮红绿 ⑤四档分辨率 ⑥暂停 gate（menu/paused/game_over 三态 W 零位移+运行态 4×0.1=0.4m 精确+Escape 解暂停+Interact 扣 15+game_over 态零位移）。

**血条②红证亲自复演**（临时探针挂入 game_ui.rs，跑毕即 revert，工作树已核净）：
缺 PlayerHealth 的 context 实体下，**失败形态=绑定失败可见，非测试自身报错、非 panic**：

```
WARN jackdaw_bind::evaluate: binding 0 on 225v0: no context for 'guards::game_ui::PlayerHealth.current'   （首帧 wire 前）
WARN jackdaw_bind::evaluate: binding 0 on 225v0: context entity lacks 'guards::game_ui::PlayerHealth'
WARN jackdaw_bind::evaluate: binding 0 on 223v0: context entity lacks 'guards::game_ui::PlayerHealth'
QA-PROBE BindFailures entries = 2   （(entity, binding index) 台账；PickupCount 一条 context 落位后自清=clear_failure 机制活证）
QA-PROBE Progress.value stays at authored 1
```

归档 `t12t1_qa_probe_red_health.log`。guards 红腿断言（`failure_count > 0` + Progress 恒
1.0）确实机械捕获缺件——U2 运行态机制面红证成立。绿腿数字断言两档精确亦亲跑过。

## 四、hud.bsn 种子形状核实（三处在案 + **一个新发现**）

| 声称 | 核实 | 结果 |
|---|---|---|
| ① Text TypePath=`bevy_ui::widget::text::Text` | fork 实读：`bevy_ui/src/widget/text.rs:126` 定义；编辑器 Label（`builtin_extensions.rs` ui.label 经 prelude 用的正是此型）同款；种子 8 处全用该路径 | **在案属实**；永久断言=guards ①部件在场+③Text 内容/BindFailures 空（错路径→组件不落→双断言必红） |
| ② `Node` 无 `position:` 字段 | fork 实读 `ui_node.rs:491-560`：有 `position_type`+`left/right/top/bottom`，无 `position`；种子遮罩写法正确 | **在案属实**；永久断言=guards ①Node 在场（错字段→组件级静默丢弃）+④遮罩 (0,0) 铺满（position_type 生效） |
| ③ 裸类型需 Default derive | fork `bevy_ecs/reflect/mod.rs:108-131` `from_reflect_with_fallback`：ReflectFromReflect→**ReflectDefault** 回退链，缺 Default 即静默不落；模板 HudRoot 带 `#[reflect(Component, Default)]`+doc 注明 load-bearing | **在案属实**；永久断言=guards ① `world.get::<HudRoot>()`「marker loaded」 |
| （新）④ **遮罩色静默丢失** | 见下 | **未在案——本次 QA 发现** |

**🔴→🟡 新发现（退回项本体）：暂停/结束屏遮罩 `BackgroundColor` 静默全透明。**
种子两行写 `bevy_color::Color::Srgba(bevy_color::Srgba { … })`——`Srgba` 用了 **re-export
路径**；规范 TypePath 是 `bevy_color::srgba::Srgba`（fork `bevy_color/src/srgba.rs:30`）。
加载时 `jackdaw_bsn::apply` 每实体两连 warn：

```
WARN jackdaw_bsn::apply: cannot read 'bevy_color::color::Color::Srgba': value 0 does not read as 'bevy_color::srgba::Srgba'
WARN jackdaw_bsn::apply: cannot apply value 0 of 'bevy_ui::ui_node::BackgroundColor': it does not read as 'bevy_color::color::Color'
```

组件**仍被插入但值是回退默认**——QA 探针实测 `PauseScreen/GameOverScreen` 的
`BackgroundColor` = `LinearRgba(0,0,0,alpha 0.0)`（全透明），非 authored 的 α=0.6/0.92。
即：方案改动面 2 点名的「半透明遮罩」「game_over 遮罩」实际不生效（文本/按钮/显隐正常，
纯视觉降级，无功能腿破坏、不进 BindFailures——与报告 §六-2 描述的「组件级静默丢弃」同族）。
**与编辑器真实序列化形状的对照铁证**：本仓 T02 归档 `loop/reports/t02t2-light/
13-scene-on-disk.bsn:21`（编辑器亲存场景）写的正是 `bevy_color::srgba::Srgba { … }`。
**修复形态已 QA 亲证**：同种子仅改规范路径→`PauseScreen Color=Some(Srgba(0,0,0,0.6))`
精确落位（归档 `t12t1_qa_probe_veil_canonical_fix.log`）。

退回修正单（给程序）：
1. `crates/jackdaw_scaffold/templates/game/assets/hud.bsn.template` 两行
   `bevy_color::Srgba {` → `bevy_color::srgba::Srgba {`（:135、:185）；
2. guards `game_ui.rs` 补一条永久断言（暂停/结束屏 BackgroundColor alpha>0 且为
   Srgba 形态，钉死「遮罩色不再静默丢失」）；
3. 重跑 guards 覆盖归档 `t12t1_guards.log` + 报告 §六-2 勘误（三处→四处）。
   （暖工程 `assets/hud.bsn` 是渲染产物，scaffold 重跑 `jd new` 或手工同步，程序裁量。）

其余种子形状核实：根=`UiSceneRoot`+Node 100%×100%+align Start，与编辑器
`seed_ui_scene_root`/`ui_scene_root_node`（`src/ui_palette.rs:528-557`）同款；
Button/Progress 部件形状与编辑器 `builtin_widget_definitions()` 同族（min 96×32、
padding 12/6、track+fill+theme token）；feathers token 行零 warn 全落位。

## 五、模板改动面逐项对照（lib.rs.template vs 方案 §二-T1-1）

| 方案项 | 落点 | 核实 |
|---|---|---|
| GameState bool 三字段 | :502-518（Default menu=true） | ✅ |
| ScreenPressed{button} | :524-528，plain Event+`#[reflect(Event, Default)]` | ✅（形态偏差见 §六-1） |
| PlayerHealth+EditorCategory+config 注入 | :535-540、:646-657（`config.is_changed()` 门，与 gravity 同构）；GameConfig doc 改口 | ✅ |
| via 三枚 register_function | :232-234（ratio 钳 0..1/is_zero/not） | ✅（hud.bsn 实用 ratio+not；is_zero 为教学对子+doc 注明，可接受） |
| wire_hud=Added<HudRoot>+BindContext | :594-603（runtime doc 钦点形态；runtime 侧 prelude re-export 见 §六-2） | ✅ |
| ScreenPressed observer（start/resume/restart 复位） | :610-629 | ✅ |
| handle_pause_action（T09 升级+守卫） | :635-639（`!menu && !game_over`）；显式 `.before(move_player)` 边 ：247 | ✅ |
| damage 双形态 | 物理=`hazard_damage`（TriggerEvents enters+同 gate，scaffold 占位族）+`take_damage` 钳 0+`update_game_over`（≤0→game_over）；无物理=Interact 扣血（move_player 无物理形态内联） | ✅（函数名非方案字面 `damage_player`，拆为 take_damage+hazard_damage，实质等价） |
| move_player gate 双形态 | scaffold 占位族两形态同一 `if state.menu || state.paused || state.game_over { return; }`（diff 亲核） | ✅ |
| spawn_hud 第二根（spawn_scene 之后） | :199 `(spawn_scene, spawn_hud)` 顺序元组+:577-579 | ✅ |
| doc 头「Game UI」导览段 | :143-182（画布→控件→绑定→Play 全链+percent/flex 纪律+U5 边角注记） | ✅ |

改动面 3（scaffold 零 gating+physics 占位族扩腿+teaches +2）与改动面 4（guards 六组）见 §二/§三。
「编辑器往返零 diff」：报告口径属实——§八-3 明言未验、归 T2/T3；注意决策 1 原文写「T1 验收
含此断言」，此为**声明式计划偏移**（主控指令已预授权按声明核口径，故计 ⚪ 记档不阻放行），
T2 放行条件必须含该往返实测（其优先级因 §四新发现而升高——该发现正是「手工种子漂移」风险
的实锤第二次发生）。

## 六、偏差分级

| 级 | 项 | 处置 |
|---|---|---|
| 🟡 | **hud.bsn 遮罩色静默丢失（第四处形状 bug，程序未上报）**+报告「三处全数钉进测试」口径不完整+guards 无遮罩色断言 | **退回小修**（§四修正单）；修完转 PASS |
| ⚪ | EntityEvent→plain Event（EntityEvent derive 强制实体字段，编译期阻断；U7 探针同时钉死 unit-struct 可用） | 接受（探针+报告口径属实） |
| ⚪ | runtime prelude re-export BindContext（改动面未列的一行；CameraRig 同款先例，模板零 Cargo 改动） | 接受 |
| ⚪ | 编辑器往返零 diff 声明式移 T2/T3（决策 1 原钉 T1） | 接受但**升权**：§四新发现证明手工种子漂移风险连续两次实锤，T2 首项应做往返实测 |
| ⚪ | 红证=in-run 双 app+开发期三次红跑未逐次归档（永久断言在场可复现） | 接受（T11 同款口径） |
| ⚪ | scaffold_e2e 冷编归 T3（T10-T2/T11-T1 同款声明） | 接受 |
| ⚪ | 报告 §一-2 `"{current} / {max}"` 笔误（实际 format=`"{} / {}"`，guards 断言与种子一致） | 报告勘误随退回项顺手带上 |

## 七、T09/T10/T11 回归抽验（headless 面，真机归 T2/T3）

- **T09**：guards `game_input` 6 件亲跑全绿（Pause 内建 Escape union 合并/死区/部分合并
  等量纲未动）；消费面重钉=模板 `handle_pause_action` 真翻转+guards ⑥ Escape 双态；四
  动作量纲未动（Interact 仅无物理形态从 info! 升级扣血=决策 8-A）。重钉表与报告 §三一致。
- **T10**：`collect_pickups`/`PickupCount` 函数体 diff 零改动（仅注册行+注释+新增
  respawn observer/spawn_pickup_line 重构）；guards `physics_triggers` 4 件全绿；hazard
  行 0b100×0b001 与拾取互不扰（teaches 针+doc 表在）。
- **T11**：guards `player_controller` 5 件全绿；paused gate=WASD 位移双态断言（guards ⑥
  三屏态零位移/运行态精确），双占位形态文本级一致（teaches 双形态针亲读在案）。

## 八、teaches 87/87 抽查（+2 针）

- `new_game_project_teaches_the_ui_pattern`：lib 18 针（GameState/menu:true/ScreenPressed/
  三枚 register_function/spawn_hud/`load("hud.bsn")`/wire_hud/BindContext/HudRoot/Added/
  observer/三 literal 分支/handle_pause_action/just_pressed("Pause")）+ hud.bsn 15 针
  （UiSceneRoot/四屏名/GameState+PlayerHealth raw/绑定五形/ratio+not via/`[["button",
  "start"]]`/ProgressFill）+无物理 6 保留针=零 gating 活证——覆盖本任务 mandate 列的
  GameState/BindContext/hud.bsn 在场+四屏名 全项。✅
- `new_game_project_teaches_the_health_pattern`：通用 12 针（PlayerHealth/current/max/
  apply_health_from_config/take_damage/PLAYER_DAMAGE/PLAYER_SPAWN/update_game_over/
  血回满/ratio…）+hazard 形态 7 针（Hazard/spawn_hazards/hazard_damage/respawn/
  CollisionLayers/0b100/0b001）+无物理 3 退场针+5 保留针（含 `take_damage(&mut health,
  PLAYER_DAMAGE)` Interact fallback）——damage 双形态覆盖。✅
- 亲数 87/87（`t12t1_qa_libtests.log`）；fast 2963=2961 基线+2 自洽。

## 九、用户 30 秒清单（本任务层面，修复退回项后）

1. `jd new` 建新工程（physics 默认开）→ Play：**看到开始屏**（项目名标题+Start 按钮，
   深色不透明底）；点 **Start** 进入 3D 世界+左上**HUD 血条在场**（"100 / 100"）+
   "Pickups: 0"。
2. 走到 (2, 0.5, 0) 红色 hazard：血条 100→85、文本同步；血尽出结束屏（修后：近黑遮罩），
   Restart 满血回出生点；Escape 出暂停屏（修后：半透明变暗），Resume 回来。
3. ⚠️ 修复前实测会看到：暂停/结束屏**没有变暗遮罩**（文字按钮直接浮在游戏上）——这正是
   退回项，修复后此条应变成「遮罩变暗」。

## 十、放行 T2 建议

- 先落退回修正单（§四）→QA 快速复核（guards+种子 diff+归档覆盖）→转 PASS 合入→T2 开工。
- T2 首项建议加做「编辑器打开 hud.bsn→Save→重开零行为差」往返实测（§五升权理由）；T2 的
  PIE 日志通道（决策 4-A）落地后，本次 `jackdaw_bsn::apply` 这类静默 warn 即有真机可见面，
  同类第四处 bug 将不再依赖 QA 探针才能发现。
- 暖工程保留复用（T2 真机四链+绑定错误可见素材）；BRP 15702 注入仍为测试挂载。

---

## 十一、复验节（rework e984ee1f，2026-10-28）——最终裁决：**PASS**

退回修正单（§四）四项逐项复核，全部落实；QA 亲跑复验如下（工作树时点干净，负向复演
临时改动已 revert 并核实）：

| 修正单项 | 复核方式 | 结果 |
|---|---|---|
| 1. 种子 ：135/:185 规范路径 | diff+文件实读：两行均改 `bevy_color::srgba::Srgba`（α=0.6/0.92 不变）；暖工程 `assets/hud.bsn` 已同步（:135/:185 亲读）；scaffold lib 零 Srgba 引用（teaches 不受扰，87/87 亲跑） | **落实** |
| 2. guards 遮罩色永久断言 | `game_ui.rs` 装载腿新增：两遮罩 `BackgroundColor` 与 `Color::srgba(0,0,0,0.6/0.92)` **精确相等**断言（:425-434）。**QA 亲自负向复演**：临时回退两行旧拼写→装载腿即红 `assertion left == right failed: PauseScreen: the authored veil color must land exactly, left: LinearRgba(0,0,0,0) vs right: Srgba(0,0,0,0.6)`（:431）→恢复→单腿复绿。断言确实捕获回归，红形态=「authored 值未落」非测试自身错 | **落实** |
| 3. guards 重跑覆盖归档+warn 扫描 20→0 | QA 亲跑 `cargo test --test guards`：**228/228**（51.8s，覆盖 `t12t1_qa_guards.log`）；warn 形态扫描（`cannot apply|cannot read|does not read as`）**=1 条**且即 `scaffolded_component_flow.rs` 故意的 `NotBuiltYet` fixture（该测试的对象本身，:558/:569 在案，上轮 20 处遮罩 warn 全数消失） | **落实** |
| 4. 报告勘误 | `t12-t1-report.md` §六-2 改「四处」并如实记载第四处=QA 新发现+负向复演+暖工程同步+20→0+余 1 条归因；§八新增**常备纪律：warn 形态扫描**（grep 四形态、逐条归因、故意 fixture 与真漏网分开计数） | **落实** |

复验门禁（QA 亲跑，归档覆盖）：fmt **CLEAN**（0 字节，`t12t1_qa_fmt.log`）｜clippy 全仓
`--all-targets --features dylib -D warnings` **CLEAN**（`t12t1_qa_clippy_ws.log`；程序侧
另附 `-p jackdaw --all-targets` 归档零 error/warning）｜guards **228/228**｜teaches **87/87**
（`t12t1_qa_teaches_rerun.log`）。fast/物理双包/bind/runtime 未受 rework 触碰面（仅模板
字符串+测试断言+报告），首轮亲跑结论继续有效。

**最终裁决：PASS——T12-T1 闭环。** 建议主控：`--no-ff` 合入 `loop/t12-game-ui`
（7515fa11+e984ee1f）入 main，派发 T12-T2（绑定错误可见+真机交互链）；T2 首项带 §十
两条建议（hud.bsn 编辑器往返零 diff 实测、PIE 日志通道落地后 warn 面真机化）。
