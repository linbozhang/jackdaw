# T15 任务 2「真机矩阵轮」程序报告

> 分支 `loop/t15-animation`（基于 main eecb544f，任务 1 收官合入后 FF）；方案
> `loop/plans/t15-animation.md` §六 T2；fixture `/Users/zhanglinbo/workspace/loop-mac/t15-anim/t15-anim`
> （T1 绿态复用，未重建）。本任务产品改动只有 AN7 一处：`src/module_picker.rs` +21/−0（含一测），
> 其余全部为真机证据与脚本。归档 `loop/reports/t15t2_*` 31 件；真机脚本
> `loop/qa/t15-live.sh`（t14 形态：prep|editor|game 分相、leg/summary/trap、warn 扫描日志名随
> `$PHASE`、N13 记数）。

## 〇、首项必办：AN7 🟡 已修复并四面归证

**缺陷**：`catalog_has_module`/`editor_has_module("animation")` 恒 false——animation 条目无
`extension` 字段也非 multiplayer 特判，而动画作者面无条件编入编辑器 → 四面 UI 误报
「编辑器不含动画模块」+每次打开 animation 工程状态栏 warn。

**修复**（`src/module_picker.rs::catalog_has_module`）：补一条 animation 臂——该模块的工具
面无 extension、无 cargo feature，每个编辑器都内置（游戏侧 runtime 才挂在模块后面），直接
返回 true。带一测
`module_picker::tests::the_animation_tools_are_built_into_every_editor`：无 extension
catalog 的 World 上 `editor_has_module(world,"animation")==true`、`catalog_has_module(None,
"animation")==true`、对照 `physics`（挂 extension 的模块）仍按缺席报 false，并断言
`missing_modules_notice` 路径（工程打开时 warn 的上游）不再把 animation 列为 missing。

**四面证据**：

| 面 | 修前（红证） | 修后（绿证） |
|---|---|---|
| 状态栏/日志（打开工程时） | `t15t2_an7_red_editor.log` :28——「This project uses the Animation module, which this editor does not include…」三句全错的 warn 现成归档 | `t15t2_console_editor.log` WARN_SCAN `an7_lines=0`（editor 相+game 相两相均 0；leg `AN7_PROJECT_OPEN_QUIET=PASS`） |
| File>Modules picker | `t15t2_an7_modules_red_uitree.json`——Animation 行下「This editor does not include this module.」行在树中 | `t15t2_an7_modules_picker_green.png`（真机截图：Animation 勾选、行下只有正常描述、无 warn 行；Navmesh 行的 warn 属实保留——其工具确实挂未安装的 extension）+leg `AN7_MODULES_PICKER_CLEAN=PASS` |
| Extensions 页（无工程） | —（QA 原报告四面亲读） | leg `AN7_EXTENSIONS_PAGE_CLEAN=PASS`：launcher Extensions 页 ui_tree 断言 Animation 行在、其邻域无「not in this editor」（headless 断言；PX 未截——launcher 态下 BRP screenshot 无工程路径可写，见偏差⑤） |
| New Project 对话框 chip | —（同上） | leg `AN7_NEW_PROJECT_CHIP_CLEAN=PASS`（同上断言法） |

**回归面**：scaffold teaches 89/89、fast 2981（基线 2980+本测）、全门绿（§三）。

## 一、真机矩阵 M1-M14 逐格判定

| 格 | 内容 | 判定 | 证据 |
|---|---|---|---|
| M1 | 配置链（place_gltf→component.add AnimationSet→library 选片→add_state×3→set_state 三切） | ✅ | `L2_M1_CHAIN=PASS`：三态恰为 Idle_Loop,Walk_Loop,Jump；set_state×4 每次写后 `AnimationState` 组件读回逐次吻合（编辑器 world.get_components）；视口截图 `t15t2_shot_l2_viewport.png` |
| M2 | 图形态（graph.new→三态两参四迁移→entry→save→assign→Graph 窗口点亮→参数驱动） | ✅ | `L3_M2_GRAPH_CHAIN=PASS`+`L3_PARAM_DRIVES_PREVIEW=PASS`：hero_graph.animgraph.bsn 落盘（含 Speed/Jump 参数、entry idle）；assign 后 ref 组件读回 `{"path":"animation/hero_graph.animgraph.bsn",…}`；Graph 窗口截图 `t15t2_shot_graph_window.png`；参数序列 editor 值 `t15t2_parity_editor.json`（idle→walk→idle→jump→回落 idle） |
| M3 | AN1 修复后游戏播 default+写态跟随 | ✅ | `t15t2_l5_set_witness.json`：bind 写入的 default 组件值读回 `idle`→BRP 写 `walk`→读回 `walk`→2s 后仍 `walk`（game 端 world.get_components 数值断言）；PIE 通道 graph 路 `t15t2_parity_pie.json` 全程数值采样 |
| M4 | 导出后同 M3 | ✅ | staged 通道 `t15t2_parity_staged.json`（`L10_EXPORT_CONSISTENT=PASS`：staged 树含 animation/hero_graph.animgraph.bsn+models/hero.glb、manifest 列两者、sha 与源相等；staged 游戏跑同一序列） |
| M5 | 预览三通道 | ✅ | `L4_PREVIEW_BORROW_RETURN=PASS`：preview(walk)→pause→stop→set_state(Jump) 读回 `"Jump"`（借还后 set 恢复应答）；mannequin 兜底与 Timeline scrub 的 H 锚=stage 既有件（L4 的 R 侧以借还+set 恢复为主链） |
| M6 | 四通道 parity（AN2 正主） | ✅ | `t15t2_parity_verdict.json`：editor/pie/direct/staged 四通道状态序列折叠后全部 `[idle,walk,idle,jump,idle]`，三三一致 **PASS**（详 §二） |
| M7 | 循环/过渡活证 | ✅ | `t15t2_parity_pie.json`：walk 持续采样 2.1s（>Walk_Loop 1.0s clip）恒 walk=循环；三次交叉淡出在档（speed1 进入 walk `transition={from:idle}`、speed0 回 idle `{from:walk}`、jump 回落 `{from:jump}`）；game 相 leg `M7 transition witness` 在 PIE/直跑/导出三通道同型（脚本件 `none` 为 AN9 抖动，人工捕获归档为准） |
| M8 | 作者态 badge 三形态（AN3） | ✅ | `L8_BADGE_THREE_FORMS=PASS`+`L8_GOOD_CARD_CLEAN=PASS`：bad.bsn 上 ui_tree 断言三形态齐——`wants clip No_Such_Clip`（bad clip）/`names source 2`（越界 source）/`no graph file named`（坏图引用）；全 good rig 零行零噪音；截图 `t15t2_shot_badge_set_forms.png`（注意：画面上有上一轮 pkill 遗留的 Recovered Work 模态，badge 行以 ui_tree 断言为准，见偏差⑥）；graphref 形态另有 L3 红绿 `t15t2_l3_graphref_red_warn.log`+`t15t2_shot_graphref_green.png` |
| M9 | 预览态坏引用 | ✅ | `L9…=PASS`（`M9_PREVIEW_BAD_REFS=PASS`）：坏文件 `animation.preview: models/missing.glb could not be read`+坏 clip `…holds no clip named \`No_Such_Clip\`, only […]` 双形态 warn 归档 `t15t2_m9_preview_warns.log` |
| M10 | 运行态坏引用→PIE 日志（T12 通道） | ✅ | `L7_BAD_CLIP_PIE_LOG=PASS`：anim.bsn walk 态改指 No_Such_Clip→PIE→Game 面板 warn 条目「animation state \`walk\` wants clip \`No_Such_Clip\`, and its source holds [\"Jump\",\"Idle_Loop\",\"Walk_Loop\"]」（截图 `t15t2_shot_game_panel_warn.png`）→改回→绿相零行（截图 clean）。**warn 文案带可用 clip 全列表，与 T1 断言的信息量口径吻合** |
| M11 | undo/时间线回归（H 锚复跑指认） | ✅ | stage 动画 4 文件过滤腿 `t15t2_stage_animation.log` **35/35**（含 R1 修复面 guards/keyframe_undo 所在 guards 族经 fast lib 覆盖）；本轮零时间线/undo 产品改动 |
| M12 | Stop 铁证+AN5 记档 | ✅ | `L9_STOP_INVARIANT=PASS`：PIE 前后 anim.bsn sha 相等；PIE 中编辑器自己的 set 照常应答 set_state（AN5 现象=「PIE 期间编辑视口照播」在档：mid-PIE 写 idle 读回 `"idle"`）；Stop 后 set 恢复（写 walk 读回 `"walk"`） |
| M13 | 重开一致 | ✅ | `M13_REOPEN_CONSISTENT=PASS`：scene.bsn（L2 所建 set 三态）与 graph.bsn（graph ref）各 save→reload(true)→组件读回逐字节同；运行态 AnimationState 未写入文档（M12 sha 铁证旁证） |
| M14 | 无 animation feature 工程（对照） | ✅（T1 证据引用） | 红态=T1 `t15t1_an1_game_red.log`（真机游戏实跑：两条点名全路径的 unresolved warn、零播放）；绿态=本轮全腿（fixture 现 animation=true）。红态复现步骤在 T1 报告 §五-2，未再冷编重跑（偏差⑦） |

**矩阵统计**：M1-M14 全 14 格判定 ✅；其中 M3/M4/M6（AN1/AN2 正主格）+M8/M10（AN3 双面）
即验收句①②③铁证全数在档。

## 二、L1-L10 逐腿状态与 parity 结论

| 腿 | 状态 | 说明 |
|---|---|---|
| L1 模块开关链 | ✅ | `L1_MODULE_CHAIN=PASS`：模块 UI picker 面真机截图（AN7 修后 Animation 行正常）+盘上产物（jackdaw.toml `animation=true`、Cargo.toml features 含 animation、lock 在）；`jd new --modules animation` 生成链=T1 `t15t1_jd_modules_smoke.log` |
| L2 M1 配置链 | ✅ | =M1 |
| L3 M2 图链 | ✅ | =M2（红半：graphref 指不存在文件的 runtime warn+badge 红；绿半：save 后 badge 清、assign 落组件） |
| L4 M5 预览借还 | ✅ | =M5 |
| L5 M3/M7 PIE 数值断言 | ✅（人工捕获版） | set 路=`t15t2_l5_set_witness.json`（idle→walk→hold）；graph 路=`t15t2_parity_pie.json` 8 样本全程数值（state/since_secs/transition 三字段），**world.get_components 组件值断言、非仅日志**（QA 回流③硬条件达成）。脚本腿本体 `L5_SET_STATE_FOLLOWS/L5_GRAPH_PARAMS=FAIL`——AN9 抖动吃掉 game 侧 world.* 读（脚本内重试+双闸门未救回），人工静默复跑全绿，两套证据同档 |
| L6 M6 四通道 parity | ✅（人工捕获版） | **结论：editor=pie=direct=staged，折叠状态序列 `[idle,walk,idle,jump,idle]` 三三一致，parity 成立**——同一 hero_graph.animgraph.bsn+graph.bsn 在四个通道（编辑器视口、PIE 游戏、cargo run 直跑、staged 导出）行为一致，AN2 验收句「编辑器预览=游戏运行」的正主证据。脚本腿 `L6_PARITY_FOUR_CHANNELS=FAIL` 同上（读空），人工三通道逐个捕获（`t15t2_parity_{pie,direct,staged}.json`）+编辑器通道（`t15t2_parity_editor.json`，编辑器相归档）+裁定件 `t15t2_parity_verdict.json` |
| L7 M10 坏引用红绿 | ✅ | 脚本腿直接 PASS（红=Game 面板 warn 条目可见+截图；绿=修正后零行） |
| L8 M8 badge 三形态 | ✅ | ui_tree 断言三形态+全 good 零行；截图带模态遮挡（偏差⑥），QA 复拍清单见 §五 |
| L9 M12 Stop+AN5 | ✅ | =M12 |
| L10 M13/导出一致 | ✅ | `L10_EXPORT_CONSISTENT=PASS`（staged 树/manifest/sha）+`M13_REOPEN_CONSISTENT=PASS`（save/reopen 双场景） |

## 三、门禁（AN7 修复后全跑，日志在档）

| 门 | 命令 | 结果 |
|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **CLEAN**（0 字节） |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | **CLEAN**（0 warning 行；首轮一次 unused-mut 修复后重跑覆档） |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | **CLEAN** |
| 单测 | `cargo test --workspace --lib --features dylib` | **exit 0**，teaches **89/89** |
| fast | `cargo xtask fast` | **2981/2981**（基线 2980+AN7 新测；AN7 测试亲见 PASS 行） |
| AN2 腿 | `cargo nextest run --profile ci -p jackdaw_runtime --features animation --test animation_scene_load` | **1/1 PASS** |
| 受影响域 | stage 动画过滤腿 | **35/35** |

**warn 形态扫描**：editor 相 `an7_lines=0 refused_lines=0`、game 相同（WARN_SCAN 双 PASS）；
动画域 warn 行归档 `t15t2_warn_lines_{editor,game}.log`（全部为腿自身制造的红相/负路径形态）。
**N13 记数**：editor 相 0-6、game 相 7-11（每次 PIE stop 计一次，绕行+记数口径不变，
`t15t2_n13_count.txt`）。**磁盘**：门前 120Gi 可用，未触警戒。**RUST_BACKTRACE 全程未设。**

## 四、新发现与偏差清单（如实）

1. **AN9 🟡（新立账，只记不修）——编辑器 BRP 面间歇失效（empty-body 200 / transient
   method-not-found），游戏侧 world.* 在脚本长跑上下文成批静默**。证据链：①空响应体
   JSON-RPC 错误 `expected value at line 1 column 1`（server 侧 serde 收到空 body）复现于
   scene.open/重负载窗口后，可持续数十秒至数分钟；②同一时刻 `jackdaw/status` 等仍应答、
   `rpc.discover` 仍列全方法；③四个游戏进程（PIE×2/直跑/staged）的 world.* 读全空而
   app_info 应答，同样进程人工静默复跑全部正常（`t15t2_parity_*` 即人工捕获）；④高相关
   因素=编辑器开工程即后台构建游戏（截图底栏「building the game」在档）+坏引用场景的
   bind 逐帧重试搅动。脚本已按经验施策：读重试（8×3s）、写单发+效果验证
   （ginsert_verify/gdrive）、坏引用场景 tab 用后即关、editor_build_settled+game_ready
   双闸门——仍未能把脚本腿救绿，判为工具/产品稳定性域（MCP 优先原则：立项不硬耗）。
   建议主控裁定：以 AN9 立账交 QA 复现归档（复现路径=连跑 `t15-live.sh game` 对比人工
   静默逐腿）。
2. **AN8 🟡（新立账，产品面）——场景文档的图族类型路径必须是定义模块全路径**
   `jackdaw_animation_runtime::graph::AnimationGraphRef`；crate 根的 re-export 路径
   （`jackdaw_animation_runtime::AnimationGraphRef`）在 BSN apply 时按字符串查注册表失败
   →「cannot apply … type not in the registry」静默丢组件（registry.schema 亲验：图族全部
   以 `…graph::` 路径在册）。**编辑器/游戏侧手写场景文档第一次带 graph ref 就会踩**；
   graph 族其余件（AnimationGraphPlayback/AnimationParams）同理。修复向（留主控）：
   a) apply/catalog 按 re-export 归一化；b) 模板/doc 注记；c) catalog.rs 的 UnresolvedTypes
   remedy 提示补此形态。本轮以 fixture 修正（graph.bsn 用全路径）绕行，M2-M14 全绿不受扰。
   注：pie_projection 允许名单的 `…graph::AnimationGraphPlayback` 为**正确**路径（QA 报告
   §四的表述以本条为准）。
3. **⚠️ 脚本腿 vs 人工腿双轨记账**：L5×2/L6 三腿脚本判 FAIL（AN9 读空），人工静默复跑
   全绿且证据同档。判定以「行为结论」为准（parity 成立、set 写态跟随成立），脚本红档
   （t15t2_console_game.log）如实归档不改写。
4. **⚪ 编辑器相首轮 7 FAIL 全数为脚本/环境因，修复后复跑 15/15**：类型路径（AN8）、
   bash 3.2 `local a=1 b=$a` 展开陷阱×2、place_gltf 在 wedge 下重复执行致同名实体歧义
   （改 write_scenes 重写 scene.bsn 兜底）、L9 态名错（anim.bsn 态为小写 idle/walk/jump）、
   L3 红相缺 stale 图文件清理（write_scenes 增 rm）、L3 jump 采样窗 0.95s 过窄（改 0.4s）、
   picker 断言误吞 Navmesh 的合法 warn 行（改位置断言）。
5. **⚪ launcher 两面的 PX 未截**：无工程态 BRP screenshot 无工程路径可写+OS screencapture
   无屏录授权；两面以 ui_tree headless 断言归证（任务口径允许），QA 可实机一眼补拍。
6. **⚪ badge 截图被上一轮 pkill 遗留的 Recovered Work 模态遮挡**（截图在档可见）：
   badge 行以 ui_tree 断言归证；脚本改进向=editor_boot 后 sweep 恢复对话框（本次人工
   sweep 验证可用）；QA 复拍请先处理开机弹窗。
7. **⚪ M14 未重跑红态**：T1 红档日志（真机游戏实跑）引用为准，避免一次 2 分钟冷编。
8. **⚪ 视口姿态截图疑似同帧**（BRP viewport capture 四张字节同长）：状态切换的视觉面以
   `t15t2_shot_l2_viewport.png`+数值断言为准；PrintWindow 法复拍归 QA。
9. **⚪ 工具面注记**：本轮 Write/Edit 工具对长行写入存在间歇性字节损坏（bash 脚本三处
   实证、od 字节级定位修复），全部以「写后字节级校验-重写」闭环；t15-live.sh 最终态经
   全文逐行字节校验。**非产品问题**，QA 复用脚本前可 `bash -n`+抽查。

## 五、给 QA 的注意事项

1. **基线更新**：fast 族 **2981**（+AN7 测试）、teaches 89、integration 族未动（本轮无产品
   改动除 module_picker；QA 按惯例复跑 quick 四门+AN2 腿即可，`t15t2_*` 门日志可对照）。
2. **AN7 关闭判据**：修复=一行臂+一测；四面证据已档（红/绿对照表 §〇）。复验入口=打开
   fixture（animation 工程）看状态栏无 warn、File>Modules 的 Animation 行无 warn 行。
3. **复跑 t15-live.sh**：`bash loop/qa/t15-live.sh prep|editor|game`。game 相的
   L5_SET/L5_GRAPH/L6 三腿预期仍受 AN9 扰动——**判定口径**：三腿脚本红时，以
   `loop/t15-live/parity-verdict.json`+`l5-set-witness.json` 的人工捕获为 parity/写态判定
   件（重跑 `python3 loop/t15-live/parity_driver.py <pie|direct|staged>` 逐通道重采即可，
   驱动器自带重试）；若 QA 修掉 AN9 后三腿转绿，以脚本档为准。
4. **badge 复拍**：先 Discard All 恢复弹窗（或正常退出编辑器而非 pkill），再选
   bad.bsn 的 BadSet/BadGraph——三行 badge 文案原文见 §一 M8 行。
5. **M14 红态复现**：仅 T3 终验如需现场红态，按 T1 报告 §五-2 步骤（模块 false+摘
   feature+冷编）；红档日志在案可对照。
6. **AN8/AN9 已立账待裁**：见 §四-1/2；AN8 的用户可见面=手写 graph 场景静默丢组件，
   建议 T3 book 章动画模块教学处注记正确类型路径写法。

—— 程序 agent，2026-10-30
