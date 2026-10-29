# T15 基础动画制作闭环 — 实施方案

> 策划产物（2026-10-28，基于本地 main **4f1a1cd2**（T14 收官合入）全量只读调研：编辑器
> `src/animation/` 全 10 文件（6,076 行）、`crates/jackdaw_animation/`（8 文件 5,425 行）、
> `crates/jackdaw_animation_runtime/`（3 文件 3,835 行 + 2,215 行测试）、`src/inspector/
> animation_graph_card.rs`、`src/entity_ops.rs`/`src/pie_projection.rs`/`src/pie_game_log.rs`
> 动画邻域、tests/stage 4 个动画文件（1,693 行 69 件）+ tests/guards/keyframe_undo.rs、
> `crates/jackdaw_runtime/`（feature 门+animation_scene_load.rs）、`crates/jackdaw_project_build/
> src/modules.json` + `crates/jackdaw_scaffold/src/lib.rs` 模板 feature 链、fork
> `/Users/zhanglinbo/workspace/bevy-fork-pinned` 的 bevy_animation 实读；**零临时探针**——
> 本方案的关键结论（module catalog 无 animation 条目、feature 门裁掉端到端测试）都是
> 静态可复核的配置事实，无需运行时探针。需求来源：`loop/plans/roadmap-game-dev.md`
> T15（P1 第九项，T01-T14 已闭环）。
> **验收原文**（roadmap 第 29 行，逐字核实）：「**片段选择/预览/循环/状态切换/过渡/参数
> 驱动。验收=待机↔行走↔跳跃可配；编辑器预览=游戏运行；坏引用有提示。**」
> **任务定性：混合型、但严重偏验收型（约 85/15）**——与 T12「补齐」同款反转读法：动画
> 作者面与运行时面是**已建成的成品系统**（两 crate+编辑器模块+面板+26 个 operator+约
> 9,000 行测试全在库，fork bevy_animation 全栈背书），六个能力词**逐词都是「验成晶」**；
> 真正的缺口收敛在**验收句的三个铁证各缺一块**：①「游戏运行」半边——module catalog 无
> animation 条目，scaffold/PIE/导出的游戏拿不到 `animation` feature，编辑器可配而游戏不响
> （**AN1**）；②「=游戏运行」的 parity 端到端证据链不存在，且唯一的游戏侧端到端测试被
> feature 门在门禁里编译裁掉（**AN2**）；③「坏引用有提示」的作者态 badge 缺——运行态
> warn 三处齐备，但作者不 Play 就看不见（**AN3**）。缺陷候选按 **AN 系**编号（Animation，
> 避开 buglist R/Y/W/A/N 系与 T01-T14 各任务编号系），只记不修→主控裁定吸收面。
> 真机口径：**macOS（本机）**，bash+curl+jq 驱动编辑器 BRP 与游戏 BRP 15702
> （`loop/qa/t12t3-live-chains.sh`/`t14-live.sh` 形态复用）；**勿设 RUST_BACKTRACE**
> （T11-T3 口径）；N13（PIE drain panic，100% 复发）绕行+记数；N12（BRP 域界）游戏侧
> 断言用 bevy 原生 `world.query`（N12 口径：不用 jackdaw 方法查 game 域实体）；warn 形态
> 扫描（`animation|clip|graph|could not|holds no|UnresolvedTypes`）入常备腿；**A7 工具债
> 前置评估=不整体前置**（§五决策 5：动画域 26 个 operator 全 BRP 直达、零原生对话框腿，
> A7 的对话框/行定位家族咬不到主链；仅吸取其 stale-grep 教训写脚本）。

---

## 0. 架构事实（核实结论，方案的地基）

**总判断：T15 不是「建动画系统」——编辑器侧（clip 库/时间线/blend graph 画布/预览运输/
Inspector 卡）与运行时侧（AnimationSet 状态机/animgraph 参数状态机/骨架绑定/过渡/事件）
已经全套在场且被约 9,000 行测试覆盖；T15 的工作是把验收句的三个铁证跑实，并修掉
「游戏侧拿不到动画」这一个结构性断点。** 十二条事实：

- **事实一：两 crate 分工清楚，全链走 Bevy 原生播放路径。** `jackdaw_animation`（编辑器
  作者面，5,425 行）：doc 自述「Thin UI layer over Bevy's `AnimationClip`, `AnimationGraph`,
  and `AnimationPlayer`… No custom curve evaluator; everything flows through Bevy's own
  playback path」（`crates/jackdaw_animation/src/lib.rs:1-10`）；`AnimationPlugin` 注册 23 个
  资源/6 个消息/11 个 observer/两组系统（lib.rs:63-142，`compile_clips`+`compile_blend_graphs`
  在 PostUpdate :114，播放/seek/游标同步链在 Update :115-140）。`jackdaw_animation_runtime`
  （游戏运行时，3,835 行）：`AnimationRuntimePlugin` 装 bind→merge→apply→report 链与
  graph 求值链、ClipEvent 面（`crates/jackdaw_animation_runtime/src/lib.rs:177-229`）。
  fork bevy_animation 全栈在场：`graph`/`transition`（`AnimationTransitions::play`）/`
  animation_event`/`morph`/`gltf_curves`（`bevy-fork-pinned/crates/bevy_animation/src/lib.rs:12-23`、
  `transition.rs:33,78`）——「过渡」的机制底座是 Bevy 0.16+ 官方 transition API，零自研。
- **事实二：编辑器两插件都装，动画场景在编辑视口「活着」。** `src/lib.rs:531-533` 依次
  装 `AnimationPlugin`+`AnimationRuntimePlugin`+`animation::plugin`（编辑器 UI 层）——
  运行时插件在编辑器进程内无 state 门，**打开的场景里带 `AnimationSet` 的实体会当场
  绑定骨架并播 default_state**（bind 链 run_if 只查资产资源存在，
  jackdaw_animation_runtime lib.rs:198-202）。这是「编辑器预览」的第一通道：作者改配置，
  视口立即动。
- **事实三：动画面板是三 tab 成品，且已在工位上。** dock 面板「Animation」注册在
  BottomDock（`src/builtin_extensions.rs:340-363`），另有 Animation 工作区预设
  （`src/lib.rs:3195-3201`）。三 tab：**Library**（项目全量 gltf clip 索引，面板
  `src/animation/panel.rs:33-39`）/**Timeline**（关键帧编辑器）/**Graph**（状态机画布，
  打开独立窗口 `graph_window.rs`）。「tab strip 点击与脚本同走一个 operator」是明文设计
  （panel.rs:133-136 注释），`animation.panel.tab` 参数 library/timeline/graph（panel.rs:142）。
- **事实四：「片段选择」=Library tab+两 operator，索引零文档污染。** 项目级扫描走
  IO 池逐帧一个文件读 glTF JSON（`.gltf` 与 `.glb` 双形态，`src/animation/library.rs:101-145`），
  深度帽 12（:18），**只在 Library tab 可见或 remote listing 请求时才走全量 walk**
  （`LibraryDemand` :194-206）；开放场景的 `GltfSource`/`AnimationSet.sources` 优先索引
  （:231-244）。clip 名以 `_Loop`/`Loop` 结尾给循环提示（`looped_hint` :92-94）。
  「曾经把 clip 实体写进文档」的旧设计已被废除（library.rs:1-7 doc：nothing about it
  reaches a document），旧文档兼容有测试（stage `a_document_holding_old_clip_children_loads_
  clean_and_saves_without_them`，animation_library.rs:142）。
- **事实五：「预览」三通道齐备，借还协议是核心机制。** ①`animation.preview` op（:117，
  参数 `file#clip`+entity）在编辑视口播任一 gltf clip：目标解析序=选中实体下有
  `AnimationSetBound` 用其 player→有裸 `AnimationSet` 找其 `skeleton_root`→gltf 装载自带
  player→都没有就 **spawn 一次性 PreviewMannequin**（`preview.rs:26,420-431`，600 帧耐心
  :47）；播放经 **`lend_player`/`return_player` 借还协议**（`crates/jackdaw_animation/src/
  graph_owner.rs`）——把被 set 占用的 player 换上预览图，停止时归还并 `restart_returned_sets`
  让 set 接着播自己的状态（preview.rs:511-535），全套有 stage 测试
  （`previewing_a_clip_on_a_bound_set_restores_the_set_state_on_stop`/`previewing_on_a_bare_
  skeleton_leaves_no_player_behind`，animation_library.rs:228/279）。②坏文件/坏 clip 名
  当场 warn（preview.rs:273-276,278-286,359-365，**「坏引用」预览态提示已在此**）。
  ③时间线 scrub/seek 与预览游标互通（`drive_preview_player` preview.rs:469-504）。
- **事实六：「状态切换」双模型并存，operator 全直达。** 模型 A=`AnimationSet`（组件内嵌
  状态表）：`AnimationSet{sources,states,default_state,skeleton_root}`（runtime lib.rs:53-76）、
  状态定义含 `looped/transition_secs/speed/then`（:79-110，`then`=非循环态播完回落，:617-654
  报 `AnimationStateFinished` 并自动回落）；游戏/编辑器写 `AnimationState` 组件即切换
  （:441-465）。**编辑器专设 `animation.set_state` op，doc 原文「so an authored set previews
  in the viewport the way it plays in the game」**（`src/entity_ops.rs:3053`）——验收句
  「编辑器预览=游戏运行」在状态切换面上已是设计意图。模型 B=animgraph 文件状态机
  （事实八）。Library 的 `animation.library.add_state` 把选中的 clip 追加为选中实体 set 的
  新状态（panel.rs:191，自动补 sources，stage 测试 `add_as_state_appends_to_the_selected_
  set_and_undoes` animation_library.rs:319）。
- **事实七：「循环/过渡」逐字段在场。** 循环：编辑器 clip 有 `LoopMode`（clip.rs）、预览
  按 `looped_hint` 自动循环（preview.rs:300）；运行时 `AnimationStateDef.looped`→
  `RepeatAnimation::Forever/Never`（runtime lib.rs:681-685）。过渡：set 路经
  `AnimationTransitions::play(player,node,Duration::from_secs_f32(transition_secs))`
  （runtime lib.rs:686-689），`already_running` 幂等防重播（:674-679）——runtime 测试
  `setting_a_state_plays_its_clip_and_fades_the_previous_one_over_the_transition`
  （animation_sets.rs:297）。
- **事实八：「参数驱动」=animgraph 文件状态机，全部建成。** 图是独立资产
  `assets/animation/<name>.animgraph.bsn`（graph.rs:4-8 doc）；`AnimationGraphDef{parameters,
  states,transitions,entry}`（graph.rs:43-54）；参数三型 Float/Bool/Trigger（:70-80）；状态
  motion 双形态 Clip|Blend1d（1D 混合沿参数阈值，:123-152）；迁移带条件表
  （六比较算子 :201-231）+`require_all`+`exit_time`+`crossfade_secs`（:155-183）+any-state
  （`from` 空 :158-159）；`AnimationParams` 是「游戏的全部写入口」（:272-275 doc：it names
  parameters, never states）——`set_float/set_bool/trigger` 私有字段但
  `#[reflect(Component,Default)]`+Serialize（:272-275）=**BRP/BSN 可写可读，真机断言通道**；
  `AnimationGraphPlayback{state,since_secs,transition}` 是读回面（:332-339）。编辑器侧
  13 个 `animation.graph.*` operator 全套（`src/animation/graph_ops.rs:38-552`：new/open/
  save/add_state/set_state/remove_state/add_transition（`when` 条件文本解析 :632-647）/
  remove_transition/set_entry/add_param/set_param/assign/convert_set），图窗口把运行态
  点亮（`light_running_state` graph_window.rs:702-714）。**stage 测试已钉「窗口里写的参数
  到达预览中的 rig」**（`a_parameter_written_in_the_window_reaches_the_rig_being_previewed`，
  animation_graph.rs:239）与画布 undo/二进制往返（:186,209,272,305）。
- **事实九：游戏侧唯一断点——`animation` feature 没有授权路径。** `jackdaw_runtime` 的
  `animation` feature 装运行时插件+bevy_animation/gltf（`crates/jackdaw_runtime/src/lib.rs:
  359-362`），**默认关**，Cargo.toml 明言「Off by default: a game with no rigs links neither」
  （`crates/jackdaw_runtime/Cargo.toml:116-124`）。模板游戏的 feature 来自 modules：`{{jackdaw_
  runtime_features}}`=各模块 runtime_features+terrain/pie 兜底（`crates/jackdaw_scaffold/src/
  lib.rs:2673-2685`），**而 module catalog 只有 physics/navmesh/multiplayer 三条，无
  animation**（`crates/jackdaw_project_build/src/modules.json` 全 56 行 3 条目；
  `jackdaw_project_build` 全 crate 零 animation 引用）。⇒ 今天用户在编辑器里配好
  `AnimationSet`，Play/导出的游戏**不播、不报**（类型未注册，bsn 落 `UnresolvedTypes`
  fail-soft，`crates/jackdaw_bsn/src/apply.rs:123-185`）——「待机↔行走↔跳跃可配」的
  可配半边成、运行半边断。
- **事实十：游戏侧端到端测试存在但在门禁里是死件。**
  `crates/jackdaw_runtime/tests/animation_scene_load.rs`（`#![cfg(feature = "animation")]` :1）
  是 JackdawPlugin+场景文档+AnimationSet 的真端到端（含 idle 状态、真实 gltf 装载形态）；
  **门禁全部不带 animation feature**（`xtask/src/main.rs:36-66` fast 的 clippy/nextest 均为
  `--workspace --features dylib`，loop README quick 门 `cargo test --workspace --lib` 同）——
  该文件在任何常跑门档编译为空。「游戏播放编辑器所配」在 CI 视角零覆盖。
- **事实十一：坏引用的运行态 warn 三处齐+PIE 日志面是现成接收端。** runtime：坏 source 序号
  （runtime lib.rs:301-308）、坏 clip 名（列出可用名 :310-317）、未知状态名（warn-once
  :334-338 与 :450-453）；编辑器预览：文件读不了/无此 clip/骨架没出现（preview.rs:273-286,
  359-365）；图文件引用坏→`a_graph_reference_naming_no_file_leaves_the_set_beside_it_to_play`
  （animation_graphs.rs:894）。T12 交付的 PIE 日志通道把游戏 warn 流进 Game 面板
  （`src/pie_game_log.rs:1-40`，cap 100 条，W13 三档色）——运行态「提示」的接收面现成。
  **作者态缺**：Inspector 动画卡无任何校验 badge——`AnimationGraphRef` 卡只是文件列表
  picker（`src/inspector/animation_graph_card.rs:17-65`，指向不存在文件仅表现为不高亮）、
  `AnimationSet` 卡只有 Convert to graph 钮（:68-85）；对照 T12 绑定卡的
  `path_error`/`binding_error` 行 badge 先例（`src/inspector/bindings_card.rs:797-955`）。
- **事实十二：fixture 资产现成——jan.gltf。** `assets/jan/jan.gltf`：1 蒙皮+67 节点+
  **5 个命名动画 dance/idle/run/typing/walk**（编辑器测试工程即仓库根，四个 stage 动画
  测试全用它：animation_library.rs:36 等）；「跳跃」无现成 clip（缺陷 AN4）。模型摆放
  `entity.place_gltf` 走 path/pos 参数（`src/entity_ops.rs:2411-2441`），**零原生对话框**；
  `tests/stage/gltf_authoring.rs` 已钉模型摆放/undo/纹理装载 8 件。gltf 骨架与 clip 按
  **骨骼名哈希**寻址（runtime lib.rs:10-14 doc+`tag_animation_targets` :747-778，public
  注释明言编辑器预览复用同款），部件骨架折并/独立双路有测试（animation_sets.rs:426,514,593）。

### 验收句逐词定性（矩阵化的前提）

| 验收词 | 定性 | 依据 |
|---|---|---|
| 片段选择 | **验成晶** | Library tab+`animation.library.select/add_state`+Inspector 图 picker（事实四/六）；stage 8+ 件 |
| 预览 | **验成晶** | 三通道：live 视口（事实二）/preview op 借还+mannequin（事实五）/Graph 窗口运行态点亮（事实八） |
| 循环 | **验成晶** | `LoopMode`+`looped_hint`+`AnimationStateDef.looped`→`RepeatAnimation`（事实七） |
| 状态切换 | **验成晶** | `animation.set_state`+`AnimationState`+`then` 回落（事实六）；runtime 25+ 件 |
| 过渡 | **验成晶** | `AnimationTransitions::play`+crossfade/exit_time/any-state（事实七/八）；runtime 过渡 5 件 |
| 参数驱动 | **验成晶** | Float/Bool/Trigger+六算子条件+Blend1d+graph operator 13 枚+参数到预览 rig 已测（事实八） |
| 验收①待机↔行走↔跳跃可配 | **半缺口（AN1+AN4）** | 可配面成晶；游戏运行半边无 feature 授权路径（事实九）；jump clip 无现成（事实十二） |
| 验收②编辑器预览=游戏运行 | **缺口（AN2）** | parity 端到端证据链零；门禁里游戏侧 e2e 是死件（事实十） |
| 验收③坏引用有提示 | **半缺口（AN3）** | 运行态 warn 齐+PIE 日志面现成；作者态 badge 缺（事实十一） |

---

## 一、缺陷候选（AN 系，只记不修→主控裁定吸收面）

| 编号 | 严重度 | 描述 | 证据 | 处置建议 |
|---|---|---|---|---|
| **AN1** | 🔴 | **游戏侧动画无授权路径**：module catalog 无 animation 条目→scaffold/PIE/导出的游戏链接不进 `AnimationRuntimePlugin`；带 `AnimationSet` 的场景在游戏端落 `UnresolvedTypes` 静默跳过——「编辑器可配、游戏不响」且**无提示**（UnresolvedTypes 有 remedy 文案但不在动画域语境） | 事实九全链；`modules.json` 3 条目；scaffold lib.rs:2673-2685 兜底仅 terrain/pie | **吸收（本任务建设主体）**。修向 A：catalog 加 animation 模块（数据驱动一条 JSON+编辑器模块 UI 即得开关+模板 features 自动带出）；修向 B：模板永远开 feature（与「no rigs links neither」注释反向+全体游戏背链接成本）；修向 C：doc 教手改 Cargo.toml（验收句「可配」字面落空）。决策 1 裁定，建议 A |
| **AN2** | 🔴 | **「编辑器预览=游戏运行」零端到端证据**：`animation_scene_load.rs` 被 feature 门在门禁裁掉（事实十）；parity（编辑器所见=PIE=direct=导出）无任何测试或真机腿——T14 PF8 同型缺口，且比 PF8 更根本（连手写文档的运行证据都不跑） | 事实十；xtask fast 无 animation | **吸收（验收主任务）**。双层：门禁层把该文件挂进一个明确档位（决策 4）；真机层 M3-M5 三通道 parity 腿（§四）。非缺陷=验收缺口 |
| **AN3** | 🟡 | **坏引用作者态无 badge**：`AnimationSet.states[].source` 越界/clip 名不存在/`sources` 文件不在盘、`AnimationGraphRef.path` 不存在——Inspector 卡零静态提示（graph picker 只是「不高亮」，set 卡只有 Convert 钮）；对照 bindings_card `path_error`/`binding_error` 先例。作者必须 Play 或预览才见 warn | 事实十一；animation_graph_card.rs 全 85 行无校验 | **建议吸收**（验收句「坏引用有提示」的作者半边；数据源现成——Library 索引即「哪些文件有哪些 clip」的真相源，graph_files 即图文件真相源）。修向见决策 3 |
| **AN4** | 🟡 | **「跳跃」无现成 clip**：jan.gltf 有 idle/walk/run/dance/typing 五 clip，无 jump；「待机↔行走↔跳跃」的第三态要么顶替（dance/typing 名不符实）要么自制 fixture | 事实十二 | 随验收腿处置（决策 2）：A=jan 现有三 clip 演示（typing/dance 代 jump，教学注记说明）；B=自制 mini rig（三 clip 手写 glTF，骨骼滑动动画，命名 Idle/Walk/Jump，one-shot jump 演示 `then` 回落）。建议 B（约 1-2 小时一次性成本，换验收句逐字对齐+`then` 回落有真演示） |
| **AN5** | ⚪ | **PIE 期间编辑器世界照播动画**：编辑器运行时插件无 state 门（事实二），PIE 连接后编辑视口自己的 set 仍在播——与 PIE 流回画面并存，语义未文档化（T12 U5 同型边角） | 事实二；preview 借还协议不受扰（stop_preview 恢复） | 记档+book 注记，不改机制；Stop 铁证腿顺带覆盖（M9） |
| **AN6** | ⚪ | **门禁档位错位**：动画域 headless 锚 69 件全在 tests/stage（集成档）+2,215 件行在 runtime crate 测试，guards 档无动画专项（keyframe_undo.rs 是 T03 的 undo 守卫）——若 QA 需要按 quick 门跑动画面需指明 stage 档 | tests/stage/animation_*.rs 4 文件；tests/guards 仅 keyframe_undo.rs | 测试组织注记，不吸收；T1 按「任务相关门=stage 动画 4 文件+runtime 两文件」口径写门禁表 |

统计：🔴 2（AN1/AN2，其一为验收缺口而非产品缺陷）｜🟡 2（AN3/AN4）｜⚪ 2（AN5/AN6）。

### buglist 重叠表（动画/clip/gltf/骨骼域全量扫描）

| 条目 | 一句话 | T15 处置 |
|---|---|---|
| R1（已修 b9a8842d+尾巴 765b4599） | 关键帧 undo 绕过 AST 产重复关键帧/幽灵复活；键位路径 clip.delete/paste_keyframes 双记录 | **知悉**：修复面=本矩阵时间线/undo 格的既有锚（guards/keyframe_undo.rs 331 行）；回归必跑 |
| A7 | t14 真机驱动脚本工具债（对话框提交+字段行定位 5 腿+stale grep）；**原文点名「T15 动画面板驱动同族将再踩，宜先修」** | **前置评估=不整体前置**（决策 5）：动画域 26 operator 全 BRP 直达、`entity.place_gltf`/`animation.graph.open` 均走参数无原生对话框（事实十二/entity_ops.rs:2411）——A7 的对话框家族咬不到 T15 主链；**吸取其 stale-grep 教训**：t15-live.sh 的 warn/N13 扫描直接用 `$PHASE` 感知日志名（A7 修复方向原文）；若 QA 真踩 Graph 画布行定位（唯一风险面），按 MCP 优先原则现场立项不硬耗 |
| N11 | Inspector 合成提交驱动缺口 | **知悉**：动画域不依赖 Inspector 合成键鼠（配置全走 operator），Inspector 只承担 badge 视觉断言（截图腿） |
| N12 | bevy 原生 BRP 与 jackdaw 方法实体域互不相通 | **知悉+绕行**：游戏侧断言（AnimationGraphPlayback.state/AnimationState）用 bevy 原生 `world.query`；编辑器侧用 jackdaw 方法（T12-T3 既有口径） |
| N13 | PIE 连接后 drain_game_events swap_remove panic（100% 复发） | 绕行+记数（T11/T12/T13/T14 口径；错误处理器捕获编辑器存活，腿内断言 panic 后重试读回） |
| A6 | prefab watcher 满载 flaky+磁盘高压家族 | **知悉**：本任务 watcher 面无直接格（动画无 watcher 依赖；glTF 变更经库重扫是增量 IO）；门前清磁盘照旧 |
| 其余 | 无动画直接条目（R/Y/W 其余均为 prefab/brush/chrome 域） | 无动作 |

> 如实报告：动画域 buglist 只有 R1（已修）与 A7（工具债，点名 T15）两条沾边——动画
> 系统是 fork 升级波次建成的成品，用户还没有可踩出「游戏动画」bug 的通路（AN1 挡着）；
> T15 缺陷主体是本方案新发现的 AN1-AN6。

---

## 二、验收矩阵设计

**三铁证×四通道=12 格主矩阵**；断言通道缩写：H=headless（stage/guards/runtime 测试）、
R=真机 BRP（编辑器 `jackdaw/call_operator`+`world.query`）、G=游戏 BRP 15702
（bevy 原生 `world.query` 读 `AnimationGraphPlayback.state`/`AnimationState`/`AnimationParams`）、
PX=截图（PrintWindow 法）。

### 铁证①：待机↔行走↔跳跃可配

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| 编辑器 | M1 | fixture 工程放 jan（place_gltf）→加 `AnimationSet`→Library 选 idle/walk/跳→`add_state`×3→`set_state` 三次切换视口即切 | 可配面 ✅H（stage 在案）+⚠️R（M1 真机链未跑过） |
| 图形态 | M2 | `animation.graph.new`→三态（idle 循环/walk 循环/jump one-shot+then）+参数 Speed+条件+entry→`assign` 给 rig→Graph 窗口点亮+改参数预览 rig 随动 | ✅H（animation_graph.rs 12 件）+⚠️R（真机 operator 链） |
| 游戏运行 | M3 | **AN1 修复后**：fixture 工程 features 含 animation→PIE→游戏播 default 态→`world.query` 断 `AnimationGraphPlayback.state`→写 `AnimationState` 切态断言（set 路）/写 `AnimationParams` 触发条件迁移（graph 路） | 🔴AN1 修复前置；H 侧=`animation_scene_load.rs` 转活（AN2） |
| 导出 | M4 | `game.export`→staged 独立启动→同 M3 断言 | 🔴同上（T12/T14 导出腿形态复用） |

### 铁证②：编辑器预览=游戏运行

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| 编辑器预览面 | M5 | 预览三通道各一腿：preview op 播 clip+暂停/停止（借还后 set 恢复）；Timeline scrub 驱动；mannequin 兜底形态 | ✅H（stage 三件）+⚠️R（真机借还+截图） |
| parity | M6 | **同一配置四态行为一致**：编辑器视口播的状态=PIE=`cargo run` direct（15702）=staged 导出，逐通道断 `state` 名+循环性（循环态反复采样 state 恒定；one-shot 采样到 `then` 回落） | 🔴AN2 正主格（T11 格 10 四通道先例形态） |
| 循环/过渡活证 | M7 | 循环：walk 态两窗口期采样 `since_secs` 回绕；过渡：jump→idle 采样过渡窗口 `transition` 字段在档（`AnimationGraphPlayback.transition`，graph.rs:337-338） | ✅H（runtime sets/graphs 测试）+⚠️G（真机读回） |

### 铁证③：坏引用有提示

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| 作者态 | M8 | ①set 的 state 指不存在 clip/越界 source→Inspector badge（AN3 修复后）红行可见→修正消失；②`AnimationGraphRef` 指不存在文件→badge；③graph op 的 warn（set_state/add_transition 未知状态名）日志可见 | 🔴AN3 修复前置；修复前=红证在档（截图「无提示」现状） |
| 预览态 | M9 | preview op 指坏文件/坏 clip→编辑器 warn+面板不动（红绿同屏） | ✅H+⚠️R（一处 warn 文案断言） |
| 运行态 | M10 | set 指坏 clip→PIE→Game 面板日志条出现 `animation state ... wants clip ...` warn（T12 PIE 日志通道）→修正后消失；graph ref 坏文件→set 不被顶替（`a_graph_reference_naming_no_file...` 的真机形态） | ⚠️G+PX（接收面现成，腿未跑过） |

### 横切回归格（复用既有防线，不新建）

| 格 | 内容 | 锚 |
|---|---|---|
| M11 | undo：add_state/图画布/关键帧/clip event 的 undo（已测面复跑） | stage 4 文件+guards keyframe_undo.rs |
| M12 | Stop 铁证：PIE 播动画中→Stop→场景文档 SHA 不变（动画配置不写运行态回文档——`AnimationState`/`AnimationGraphPlayback` 非 reflected 保存件/编辑器侧反射件边界以实测为准）+Stop 后视口 set 恢复播放 | T06 链复跑；AN5 记档点 |
| M13 | 重开一致：配置→存→重开→states/graph 引用/参数原样 | 走场景文档与 .animgraph.bsn 原子写（T04 面） |
| M14 | 无动画 feature 工程（对照）：features 无 animation 的游戏装载带 set 场景→不播且按 AN1 修后**有明确提示**（doc/unresolved remedy 注记，决策 1 附带面） | 现状红证=静默 UnresolvedTypes |

**矩阵统计**：✅H 有锚 5 格｜⚠️ 真机腿缺口 5 格｜🔴 修复前置 4 格（AN1×M3/M4、AN2×M6、
AN3×M8）。T1 建设把 🔴 清源，T2 真机把 ⚠️/🔴 格全数落判定。

---

## 三、真机腿清单（Mac，bash+curl+jq；T2 集中跑）

fixture 工程=`jd new` 出 `/Users/zhanglinbo/workspace/loop-mac/t15-animation`（T14 决策 5
同款，冷编一次；**建后按决策 1 给 jackdaw.toml modules 加 animation 或直接验模块 UI 开关
链**），拷 `assets/jan/` 三件+（若裁决策 2-B）自制 mini rig `assets/models/hero.glb`。
流程脚本 `loop/qa/t15-live.sh`（t14-live.sh 形态：leg/summary/cleanup trap+warn 形态扫描
**日志名随 `$PHASE`**（A7 教训）+N13 记数）。

| # | 腿 | 通道 | 为什么必须真机 |
|---|---|---|---|
| L1 | 模块开关链：模块 UI（或 jackdaw.toml）启用 animation→`cargo build` 活体证据+模板 Cargo.toml features 含 animation | PX+盘上文件 | feature 授权是编辑器↔Cargo 的生成链，headless 只能断字符串 |
| L2 | M1 配置链全 operator 驱动：place_gltf→component.add AnimationSet→library.select→add_state×3→set_state 三切 | R+PX（视口姿态） | 视口动起来是视觉结论；operator 链 headless 已验过同型 |
| L3 | M2 图链：graph.new→三态+Speed 参数+jump 条件迁移→save→assign→Graph 窗口点亮+参数写入预览随动 | R+PX | 画布点亮是视觉面 |
| L4 | M5 预览借还：preview 播 walk→pause→stop→set 的 idle 恢复（视口+`world.query` 双断言） | R+PX | 借还协议的时序活证 |
| L5 | M3 PIE parity：PIE→G 断 default 态→写 `AnimationState("walk")` 断跟随→（graph 路）写 `AnimationParams` 触发 jump 迁移断 `state` 变化+`transition` 在档 | G | 游戏进程行为 |
| L6 | M6 四通道 parity：L5 态序在 direct run（15702）与 staged 导出重放一致 | G+盘 SHA | T11 格 10 先例；AN2 正主 |
| L7 | M10 坏引用红绿：set 指 bad clip→PIE→Game 面板 warn 条目可见（PX）→修正→消失 | G+PX | PIE 日志面是 T12 通道，视觉断言 |
| L8 | M8 作者态红绿：badge 现状红证截图（AN3 修前）→修后 badge 可见→修正消失（T2 内两段各一腿） | PX+R | Inspector 视觉面 |
| L9 | M12 Stop 铁证+AN5 记档：PIE 播放中 Stop→场景 SHA 双不变→视口 set 恢复；PIE 期间编辑视口照播现象记档 | R+盘 SHA | T06 链动画形态 |
| L10 | M13 重开/导出一致：存→重开→配置在（states/图文件）→导出包内 .animgraph.bsn+模型在 | R+盘 | 验收通用交付铁证 |

---

## 四、分任务拆解（T1/T2/T3）

### T1「缺口补齐轮」（建设小头：AN1+AN3+AN2 门禁层+AN4；决策 1/2/3/4）

1. **AN1（决策 1-A）**：`crates/jackdaw_project_build/src/modules.json` 加 animation 模块
   条目（`runtime_features:["animation"]`，requires 空，labels/doc 对齐既有三条）；核对
   模块 UI/`jd modules` 面自动出项（catalog 是数据驱动，预期零代码）；teaches/guards 各
   +1：scaffold 模板 features 断言（含 animation 当且仅当模块开）+catalog 单测（modules.rs
   测试族追加一条）；**决策 1 附带面**：无 animation feature 的游戏装载带 set 场景的
   提示文案核验（UnresolvedTypes remedy 是否点名类型路径，不达标则一句 doc 化，不新机制）。
2. **AN3（决策 3-A）**：`src/inspector/animation_graph_card.rs` 加校验 badge 行——数据源：
   `AnimationLibrary`（clip 真相源）+盘上 gltf 存在性+`graph_files`（图文件真相源）；badge
   形态复刻 bindings_card 行 badge（`path_error` 先例：行内标记+Tooltip）；校验范围=
   set.states 每条（source 越界/clip 名不在该 source/sources 文件缺失）+graphref.path；
   单测：校验函数纯逻辑三件（坏 clip/坏 path/全好）；**不建新面板不动播放面**。
3. **AN2 门禁层（决策 4）**：`animation_scene_load.rs` 挂进一个明确执行的档位——建议
   integration 档单跑一条 `cargo test -p jackdaw_runtime --features animation --test
   animation_scene_load`（xtask heavy 或 QA 门禁表「任务相关门」行；不进 fast，避免全体
   链接 bevy_animation）。
4. **AN4（决策 2）**：B=写 mini rig 生成脚本或手写 `hero.glb`（三骨骼滑动 clip：
   Idle_Loop/Walk_Loop/Jump（one-shot），合法 glTF 最小动画段，runtime 测试的
   `source_holding` 形态证明手造 gltf 可行）；A=零资产直接用 jan（jump 用 dance 顶替+
   注记）。落地后 fixture 工程用它跑 L2。
5. 出报告：AN1-AN6 逐条处置记录；红证收集（AN3 修前 badge 缺席截图、AN1 修前游戏
   静默 UnresolvedTypes 日志）。
6. **门禁**：fmt/clippy 全仓/单测/集成（stage 动画 4 文件+runtime 两文件为「任务相关门」
   显式行）+scaffold teaches 全绿。

**验收标准**：模块 UI 出 animation 开关且 fixture 工程 Play 播出动画（AN1 红转绿活证）；
badge 三形态各一截图；`animation_scene_load` 在指定档位绿；AN1-AN4 每条有 before/after
证据；T12/T13/T14 回归零破坏（fast 2975 族）。

### T2「真机矩阵轮」（验收主任务：M1-M14/L1-L10；决策 5/6）

1. fixture 工程落盘（含 jan+hero）+`loop/qa/t15-live.sh`（A7 教训版）。
2. L1-L10 全腿；每腿独立探针开场（t12t3 形态）；M5-M7 的 H 侧锚复跑指认。
3. 缺陷只记不修：真机新发现按 AN 系续编（AN7 起），红证归档 `loop/reports/t15*/`。
4. 出 QA 报告：12 格矩阵逐格判定+L 腿全跑证据。

**验收标准**：M3/M4/M6（AN1/AN2 正主格）全绿=验收句①②铁证在档；M8/M10（AN3+PIE
日志）双面红绿=验收句③铁证在档；L4 借还恢复活证；四门禁绿。

### T3「终验 + 文档」

1. 12 格终态复跑+L 腿抽重点复跑（L5/L6/L7）。
2. book 新章 `book/src/user-guide/animation.md`（SUMMARY 排 player-controller 后）：
   动画面导览（面板三 tab/Library/时间线/Graph）、双模型教学（AnimationSet 内嵌表 vs
   animgraph 文件状态机+何时用哪个）、预览三通道与借还语义、参数驱动（游戏写
   AnimationParams 的模板段+条件/exit_time/crossfade 语义）、坏引用双面（badge+PIE 日志）、
   **模块开关教学**（animation 模块=游戏侧能播的前置）、AN5 边角注记；`game-ui.md`/
   `player-controller.md` 交叉引用；`book/src/developer-guide/open-challenges.md:86`
   「Animation graph editor. Started in…」条目按 T15 后现状改写（已远超 started）。
3. 模板教学评估（小步）：`lib.rs.template` 是否加 3-5 行「写 AnimationParams」示例段
   （对齐 T12 教学密度，主控可裁不加——图参数写入已有 book 章承担）。
4. buglist 处置（预期无打钩；A7 若 T2 真踩则按流程修后更新）、roadmap 勾选 T15、
   台账记行。
5. 终验门：全量门（fast/integration/doctests/docs——日志全文复核）+`animation_scene_load`
   档位腿。

---

## 五、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **游戏侧 animation 授权形态（本方案最高权重，AN1）** | A=**module catalog 加 animation 模块**：一条 JSON+预期零代码（catalog 数据驱动），模块 UI/jackdaw.toml/模板 features 三面自动带出，与 physics/navmesh/multiplayer 同构；代价=默认不开的存量工程仍需开一次模块（教学+book 章覆盖）。B=模板永远开：零用户动作，但与 runtime Cargo.toml「a game with no rigs links neither」的设计注释反向+无 rig 游戏背 bevy_animation 链接成本。C=doc 教手改 Cargo.toml：零产品改动但验收句「可配」在游戏半边靠人肉——**否决** | **A**；决策 1 附带面=核验无 feature 装载带 set 场景的提示文案（现状 UnresolvedTypes remedy 是否够用，不够则 doc 化一句，不建新 warn 面） |
| 2 | **「跳跃」fixture 形态（AN4）** | A=jan 三 clip 顶替（dance 代 jump）：零资产成本、与 stage 测试同源；代价=验收句「跳跃」字面名不符实，one-shot `then` 回落语义演示弱（dance 循环性存疑需实测）。B=**自制 mini rig hero.glb**（Idle_Loop/Walk_Loop/Jump 三 clip，jump one-shot+then=idle）：逐字对齐验收句+`then` 回落有真演示+fixture 可复用为 T18/T20 资产；代价=1-2 小时手写 glTF（runtime 测试手造 gltf 先例在案，风险低） | **B**；A 作为 B 受阻回落（hero.glb 装载问题 1 小时内不破则切 A 并注记） |
| 3 | **坏引用作者态 badge 形态（AN3）** | A=**Inspector 卡行 badge（bindings_card 先例）**：校验数据源现成（Library/graph_files），改动面=animation_graph_card.rs 一文件+纯逻辑可测；代价=set 大时逐行校验的更新时机（跟随卡片重建即可）。B=Library tab 交叉标注（坏 set 高亮 clip 列表）：面反了（作者看的是 Inspector 不是库）。C=不加，靠预览/Play warn：验收句③作者半边落空——**否决** | **A**；校验函数放 `src/animation/library.rs` 或独立小模块以利单测；badge 文案含「可用 clip 列表」对齐 runtime warn 的信息量 |
| 4 | **AN2 门禁层落位** | A=**integration/QA 档单跑 `--features animation --test animation_scene_load`**：最小链接成本、档位明确；代价=fast 不含（与现状同，但「任务相关门」行显式化）。B=fast 常开 animation feature：全体 `--workspace` 构建背 bevy_animation 链接，门时长涨。C=只靠真机腿：CI 视角持续零覆盖 | **A**；QA 门禁表把该腿写成显式命令行，T3 终验门必跑 |
| 5 | **A7 工具债前置评估** | A=**不前置，脚本自守**：动画域 26 operator 全 BRP 直达+零原生对话框腿（place_gltf/graph.open 走参数，事实十二），A7 的对话框/行定位家族咬不到主链；t15-live.sh 直接用 `$PHASE` 日志名（A7 stale-grep 教训原文）；真踩 Graph 画布行定位再按 MCP 优先现场立项。B=先修 A7 全部再开 T15：多花一个任务前置，且其对话框半边对 T15 无收益 | **A**；buglist A7 条目的「T15 同族将再踩」预警以本节评估回应——同族面在 T15 主链不存在，预警部分采纳（脚本写法）+部分排除（不前置） |
| 6 | **fixture 工程形态** | A=`jd new` 新建 `loop-mac/t15-animation`（干净可弃置；冷编一次，AN1 修复后二开模块冷编第二次）。B=复用 t12t1-game 暖工程：省冷编但工程被 T12/T13 防线共用，归因污染 | **A**（T14 决策 5 同款；磁盘高压家族门前清盘照旧） |

小定案（主控可否决）：缺陷编号 AN1-AN6（新发现自 AN7 续）；真机腿编号 L1-L10；
矩阵格编号 M1-M14；fixture 工程 `/Users/zhanglinbo/workspace/loop-mac/t15-animation`；
mini rig `assets/models/hero.glb`（决策 2-B）；流程脚本 `loop/qa/t15-live.sh`；报告目录
`loop/reports/t15*/`；book 章 `book/src/user-guide/animation.md`。

---

## 六、风险与回滚

| 风险 | 概率 | 缓解 |
|---|---|---|
| modules.json 加条目波及面超预期（模块 UI/jd CLI/scaffold 三消费方之一假设错误） | 低 | catalog 数据驱动有单测族（modules.rs:469-524 测试形态）；T1 第一步即跑三面活证，受阻回落决策 1-B（模板常开，代价已知） |
| 手写 hero.glb 不被 bevy_gltf 装载（采样器/插值边界） | 中 | runtime 测试 `source_holding` 手造形态+Library JSON 解析器双先例；1 小时不破切决策 2-A |
| AN1 修复后 fixture 工程 Play 不播（装载链某环：GltfSource 派生/skeleton_root 命名/tag 时机） | 中 | 编辑器视口先播起来（事实二，与游戏同插件）再上 PIE；`animation_scene_load.rs` 转活即机制层红绿对照；真机 L5 前置探针腿 |
| PIE parity 腿被 N13 扰动 | 高（100% 复发） | 绕行+记数（既有口径）；腿内断言 panic 后重试读回；G 通道断言不依赖 PIE 存活时序 |
| N12 域界踩坑（game 实体 jackdaw 方法查不到） | 确定 | §0/重叠表已绕行：游戏侧全用 bevy 原生 `world.query`；`AnimationGraphPlayback.state` 是公开字段可反射读 |
| `AnimationState` 等运行态组件经 PIE 流回编辑器世界引发未注册类型噪音 | 低-中 | 编辑器已注册全套类型（事实二）；PIE 投影 allow 名单只特批 `AnimationGraphPlayback`（`src/pie_projection.rs:56-61`），其余动画组件走常规投影路径——L5 首跑即验证，异常则记 AN7 查投影 skip 面 |
| badge 校验把「合法但库未索引」误报（Library 按需 walk 未扫到） | 中 | 校验数据源=Library∪开放场景 sources（两者都已强制索引，library.rs:231-244）；badge 文案区分「未索引」与「不存在」两态 |
| Mac debug 无 RUST_BACKTRACE | 确定 | 全程不设（T11-T3 口径） |
| 门链与编辑器/游戏同窗互踩 | 中 | T12-T3 §九-7 纪律：门链单独跑 |
| 回滚 | — | T1 四件各自独立可 revert（catalog JSON 一条/badge 一文件/门禁腿一命令/fixture 一资产）；全程零场景格式变更、零协议变更、零新 plugin/系统（AN1 是数据行、AN3 是 UI 行、AN2 是门禁行）——建设面最小化由定性表保障（六个能力词无一需要新机制） |

---

## 七、与 T01-T14 已建设施的衔接

1. **T03（undo 加固）**：R1 修复面（keyframe AST 注册+SELF_PUSHING 名单）=时间线 undo
   格的既有锚；guards/keyframe_undo.rs 回归必跑。
2. **T04（原子写）**：.animgraph.bsn 与场景文档落盘同链——M13 重开一致格的底座。
3. **T06（PIE 隔离）**：M12 Stop 铁证=动画形态复跑；`pie_game_log` 接收面=T12 交付。
4. **T08（GameConfig）/T09（输入）/T10（触发器）/T11（玩家）**：参数驱动的游戏侧
   写入口教学素材（速度→Speed 参数、跳跃键→Trigger 参数）；T20 示例游戏若给玩家上
   动画，本任务的 hero.glb+graph 链是现成件。
5. **T12（游戏 UI）**：PIE 日志通道=M10 接收端；badge 先例=bindings_card；「补齐」定性
   反转的读法本任务第二次适用。
6. **T13（flow）/T14（prefab）**：零直接交集；L6 导出 parity 腿与 L10 导出一致格复用
   T07/T14 的 staged 启动与 SHA 双腿形态。
7. **对 T16-T25 的奠基**：T18（资产导入热重载——glTF 是其首批类型，本任务的 Library
   索引/坏 gltf warn 是邻域）；T20（示例游戏——角色动画拼装件）；T24（错误定位——
   动画 warn 已含实体/clip 名点名，形态对齐）。
8. **分支与行号基线**：本方案行号基于 main 4f1a1cd2；T15 从 main 拉 `loop/t15-animation`；
   loop/ 目录不入库照旧。

---

## 八、耗时预估

| 段 | 预估 | 大头 |
|---|---|---|
| T1 | 1-1.5 天 | modules.json 三消费方活证+badge（校验+UI+单测）+hero.glb（若裁 B）+门禁腿落位 |
| T2 | 1-1.5 天 | fixture 工程+脚本+L1-L10 两段（编辑器段 L1-L4/L8-L9/游戏段 L5-L7/L10）+红证归档 |
| T3 | 0.5-1 天 | 12 格终态+book 新章+全量门+收尾 |
| 合计 | **2.5-4 天** | 视决策 1/2 落地顺畅度浮动 |
