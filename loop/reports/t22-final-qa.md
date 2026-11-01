# T22 终验 QA 报告：任务 3（收官段）+ T22 整体终验（只验不修）

> 验收对象：分支 `loop/t22-tilemap` @ **ffed51ae**（基线 main=706f88f3=T2 收官合入点；程序
> 提交=T22-T3 收官，T1/T2 已分别经 b921b28e/427d7177 合入；T1 QA PASS（t22-t1-qa.md）、
> T2 QA PASS（t22-t2-qa.md，交接硬项五件本轮逐条核销见 §六）。程序报告：
> `loop/reports/t22-t3-report.md`。T3 diff 亲核（name-only/stat 全件）：**产品面=零改动**
> （commit 全件=loop/qa/t22-live.sh+loop/reports/t22t3_* 35 件+loop/t22-live/ 证据 26 件；
> `src/`、`crates/`、templates、fork、协议、场景格式、book、buglist、roadmap、台账零触碰
> ——T1 组件族/T2 工具族即 T22 全部产品面，本轮基线不漂）；工作树除 QA 归档外零触碰。
> QA 手段：**Mac 全量门亲跑**（两段后台链+轮询，全程未设 RUST_BACKTRACE，门链独窗不与
> 真机同窗，门前 df 106Gi）+**14 格矩阵证据原文全读**（13 件 live 日志+脚本断言对源+
> 两张关键 PNG 人眼复核）+**TM14 红证全读+源码级病灶复现+修法评估**+**warn 扫描独立
> 归因**（编辑器/游戏 22 份日志亲扫）+**三张确定性门红的断言原文与源码定位**。clippy
> 双包采信归档抽核（零行+EXIT 标记在文）；doctests T22 三轮零归档→QA 补跑（§一-9）。
> QA 归档 `loop/reports/t22t3_qa_*`：fmt/libtests/fast/audio_gate/save_store/doc/
> scaffold_e2e/scaffold_e2e_heavy/integration/integration2/a6_isolated/doctests/
> doctests_bind_rerun 十三件日志+两份门链脚本。

## 〇、结论

**PASS（有条件）——T22-T3 真机矩阵与证据链成立；T22 整体裁决为「有条件放行」：
integration 净跑带 3 个 T22 引入的确定性门红（QA 终验抓出，全是分类/声明一行族，见 §四），
TM14 🔴 未裁定，book 章（方案 §四-T3-4）未落——三件挂账闭单前 roadmap T22 建议暂缓勾选
（§九）。** 矩阵本尊无可挑剔：14 格全部落判且证据原文逐格亲读零虚报；碰撞三态教科书级
（direct run y=76.0009994506836 八拍逐位恒稳=内核 SEPARATION 算式原值、墙截
x=275.9989929199219=288−12−0.001、TriggerCensus.crossed=true+游戏日志自述）；PIE 与
staged 导出同数复现；M14 双半边负向守卫在案；TM14 红证先落盘（19:34:37）后绿相
（19:41:59）=T2-F1 纪律兑现。全量门：fmt/libtests 3047/fast 3047/audio 7/save_store 19/
docs 同面 17 行/heavy e2e 2/2 绿/doctests 处方维持八门绿；**integration 5604 跑 5600 过、
4 红**（3 确定性=§四+A6 flake，隔离 1/1 绿=定案口径维持）；scaffold_e2e 的 ci 轮红
（180s 硬杀×冷缓存）为门配置/环境面，heavy 轮真编译 2/2 绿闭合。D7 翻转（prep 15/15
含 TPL_TILEMAP_PRESENT）与 PX 三件不滑出两条 T2 硬项全部核销。任务书第 5/6 条书写的
book/EG1-EG6/无工具链/30 秒胜局句为 **T20 终验模板误植**（T22 无对应物，§六-3 如实
说明）；T22 自己的 book 缺口如实计入偏差。

## 一、Mac 全量门亲跑（权威口径，最终树 ffed51ae；门链独窗，未设 RUST_BACKTRACE）

门前 df 106Gi；链一后 97Gi；integration 两轮后 90Gi。

| # | 门 | 命令 | QA 亲跑结果 | 归档 |
|---|---|---|---|---|
| 1 | 格式 | `cargo fmt --all -- --check` | **EXIT=0**（零 Diff） | t22t3_qa_fmt.log |
| 2 | 单测 | `cargo test --workspace --lib` | **EXIT=0；3047 passed / 0 failed**（59 条 result 行逐行求和亲算=T2 采纳基线零漂移）；**scaffold 包 `running 93 tests` 亲点**——teaches 93=T21 收官 92+T22-T2 新增 1（任务书「预期 92」为 T20 口径，§六-3） | t22t3_qa_libtests.log |
| 3 | fast | `cargo xtask fast` | **EXIT=0；Summary 3047/3047（48.5s）**；全文 `^error/FAILED/warning:` 零命中 | t22t3_qa_fast.log |
| 4 | audio_gate | `cargo nextest run --profile ci --test audio_gate` | **7/7 PASS** | t22t3_qa_audio_gate.log |
| 5 | save_store | `cargo nextest run --profile ci -p jackdaw_runtime --test save_store` | **19/19 PASS** | t22t3_qa_save_store.log |
| 6 | docs | `cargo doc --workspace --no-deps` | **EXIT=0**；warning 面 **17 行与 t21t3_qa_docs.log 逐行 diff 为空**（零新增零消失） | t22t3_qa_doc.log |
| 7 | scaffold_e2e | ci 轮 `--profile ci` → **双测 180s×3 试全超时**（冷缓存+`terminate-after=6` 硬杀，门配置/环境面）；**heavy 轮 `--profile heavy` → 2/2 PASS（276.4s 冷构建真编译+schema 断言）**——e2e 实质绿，ci 轮超时形态记 ⚪（§八-6） | t22t3_qa_scaffold_e2e.log / t22t3_qa_scaffold_e2e_heavy.log |
| 8 | **integration** | `cargo xtask integration` | **净跑（第二轮）：5604 tests run: 5600 passed, 4 failed**（1658.5s）——3 确定性红+1 flake，逐条定性见 §四/§八；**A6 隔离复跑 1/1 PASS（2.5s）**=定案口径维持（今日两轮全量尽红+隔离绿，复发强度注记 §八-4）。**第一轮（852 红）作废**：QA 自身在 integration 跑到一半时并发执行了不带 `--features dylib` 的单包测试→cargo 以异 feature 重建 libbevy_dylib→已构建测试二进制 dyld 符号失配 SIGABRT 级联——QA 程序失误如实入档（§八-9），两红与 flake 均发生在污染时点之前且净跑逐条复现 | t22t3_qa_integration.log（作废）/ t22t3_qa_integration2.log（净跑）/ t22t3_qa_a6_isolated.log |
| 9 | doctests | `cargo test --workspace --doc` | **全树绿唯 `-p jackdaw_bind --doc` dyld 家族失败**（`@rpath/libstd-614bb9b33bbc23af.dylib`——**第 13 次目击**，T17 第 10/T18 第 11/T19 第 12 同签名，T15 定案环境票）；单包复跑 `cargo test -p jackdaw_bind --doc` → **1 passed，EXIT=0**；双日志 mtime 顺序可追。T22 三轮均无 doctests 归档（程序门禁表六门不含，方案 §四-T3-6 列明）——QA 补跑闭单 | t22t3_qa_doctests.log / t22t3_qa_doctests_bind_rerun.log |

**clippy（采信归档抽核，T18/T19 先例口径）**：程序归档 `t22t3_gates_clippy_ws.log`/
`t22t3_gates_clippy_phys.log` 抽核——`warning/error` 行计数 **0**（grep 亲算）+尾部
`CLIPPY_WS_EXIT=0`/`CLIPPY_PHYS_EXIT=0` 在文；QA fast 门内含同参数 clippy 段（`--deny
warnings`）零行互证。

**integration 数对账**：5604 = T21 收官 5575 + **29**（内核 crate 11=lib 8+App 3、editor
lib 9、scaffold teaches 1、stage 8=tilemap_ops 6+tilemap_guard 2）——拆账逐项与 T1/T2
报告基线吻合，无一多记。

## 二、关键格复核（14 格证据原文全读；正主三格+M6/TM7 重点核）

**抽读格=任务书建议格，全部 live 日志原文亲读+脚本断言对源+PNG 人眼：**

1. **M2 绘制（13/13 PASS）**：`t22t3_live_draw.log` 全读——三笔 9 格（脚本断言
   `count=9`，t22-live.sh:1089）+格值回读 `(0,2)=4`（:1095）+一笔=一条 undo（history
   深度基线 `+3` 恰三笔，:1120）+越界整笔拒后存活（DRAW_OFFCANVAS_ALIVE/COUNT）+
   **PX：viewport 品红 census 1.3298%、七负色（green/blue/yellow/cyan/orange…）全零=
   rect 裁剪非整图（M14_CANVAS_RECT_PASS，A17 防回滑画布半边）**+STROKE_ARMS/
   STROKE_CANCEL_CLEARS 两拍（手势武装/取消面=TM14 的绿侧边界，§三）。人眼复核
   `shot-draw-painted.png`：三笔各 3 格品红 tile（裁剪格非整图）+Hero 红块同框。
   手势面按 D1 以批算子门承载（console：stroke 武装后三笔走 `tilemap.paint` 算子，
   TM14 记档不阻断证据链）。
2. **M4 填充（7/7 PASS）**：`t22t3_live_fill.log` 全读+脚本断言亲核——矩形 6/6
   （count=6 blue=6，:1206）、环形 16+flood 9（red=16 mag=9，:1219）、越界种子拒后
   计数恒 31（:1226）、三色同框 PX（blue 0.8865/red 2.5118/magenta 1.3298）。
3. **M10 direct run（7/7 PASS，教科书级）**：`t22t3_live_run.log` 全读——探针八拍
   `y=76.0009994506836` 逐位恒稳（=内核 SEPARATION=1e-3 算式原值 76+0.001，T1 QA §四-5
   同款逐位复现口径）=**地面站得住**；满道位移截断 `x=275.9989929199219`
   （=墙面 288−半宽 12−分离 0.001）=**墙挡住**；`TriggerCensus: inside=0 crossed=true`
   +游戏 stdout 自述 "the trigger crossing was logged"=**触发区触发**；全部 bevy 原生
   读（N12 口径）；墙位 y 同值=驻墙不丢地面（WALL_GROUNDED）。
4. **M6 碰撞配置+TM7 色罩（7/7 PASS）**：`t22t3_live_layers.log` 全读——mode 算子写+
   BRP 回读 `modes: ground=Solid trigger=Trigger`（MODE_SET_PASS）+重开回读
   （REOPEN_MODES_PASS）；**TM7 色罩 PX 判据亲读脚本（t22-live.sh:1303-1315）：
   tool-in 环 0.0191 > Select 后 0.0000+0.01 阈 → PASS**。⚠️ 报告 §三 M6 散文写
   「工具在位 0.55%→Select 0.01%」与归档数（1.91%→0.00%）不符——机制同向
   （tool-gated tint 有无），判缀级 drift 记 ⚪（§八-5）。
5. **其余九格判定行全读无虚报**：M1 调色板（层切割 bsn 门 columns=16/rows=8+面板
   sheet 真点选读数 `'8589928892'→'Tile 101'` 翻转+PX chrome 66.47%/sheet 橙
   19.55%+六色在带；人眼 `shot-palette-panel.png`=整图+网格+高亮+Tile 4 读数+
   brush 四钮+层行 Eye/P Ground/+Add Layer+状态栏 Tilemap (World) 全渲染，**底部
   构建面板同时人眼可见 TM10 警告原文**）；M3 擦除（红 0.4433→0.1478 回落+擦空
   不炸）；M5 图层（路由 ground=2/wall=1 分账+活动层切回 ACTIVE_SWITCH+可见性
   0.4433→0.1478→0.4433 PX 三拍）；M7 undo（七操作步进全中+DIRTY_AFTER_SAVE 绿
   ——redo 脏面=TM15，§五）；M8 保存重开（20 格清单逐格列出+三层+零
   texture_atlas+2D kind 再识别+格值抽点 5,2=4/9,2=2/9,3=2）；M9 Stop（STOP_SHA
   +M14 双半边）；M11 PIE（同数 76.001/275.999/crossed+流送条带红 0.5035%）；M12
   导出（face `state=ready`+manifest 在包+staged 异目录同三断言）；M13 flow（3 层
   +探针进场景、Pause→menu 后 TilemapLayer=0 零残留、PlayerProbe=1=模板教学设计
   面）。**prep 15/15**（含 PREP_TILEMAP_ROW/DEP/LIB+TPL_TILEMAP_PRESENT+
   GAME_WARM=T2 交接硬项①核销）。

## 三、TM14 🔴 复核（终验重点）——定罪成立、修法评估、批算子门声明核

1. **红证全读**（`t22t3_tm14_stroke_red.log`）：repro=fixture 编辑器 2D 视口、Ground
   层+Tilemap 工具+zoom 1.0、`input.pointer` press/move/release 过世界格
   (8,72)→(88,72)；observed=`jackdaw/status` modal 停在 "tilemap.stroke" 不随 release
   释放、零 TileGridCell 行；cause=源码级（下条）；headless 盲区句见第 4 点勘误。
   红证运行时点 19:34:37 **先于**绿相 draw 19:41:59（先红后绿、红必落盘=T2-F1 纪律
   兑现，红证独立成件未被覆盖）。
2. **源码级病灶亲证（三链齐）**：①`src/tilemap_palette.rs:893-901`
   `fronted_stage_entity` 返回 **`host.stage`（stage 实体）**存入 `state.stage`；
   ②`:738` `stroke_cell` 用 `hosts.get(state.stage?)` 查 `Viewport2dPanelHost`——
   而该组件插在 panel 实体（`src/viewport_2d.rs:1764` `world.entity_mut(parent)
   .insert(Viewport2dPanelHost { camera, stage, … })`，组件自带 `.stage` 字段指向
   stage 子实体）→ 真机画布上恒 `None`；③`:833-835` None 早退 `Running` **先于**
   `:843` `just_released` 检查 → release 永不可见、模态不派发不自退（Esc/右键
   cancel 可清=绿侧 STROKE_CANCEL_CLEARS_PASS 吻合）。**定罪成立。**
3. **一线修法评估（程序在案的主控裁定面，QA 不修）**：最小修=`fronted_stage_entity`
   改返回 **host 实体**（查询改 `(Entity, &Viewport2dPanelHost)`，`.map(|(e,_)| e)`），
   `stroke_cell` 的 `hosts.get(state.stage)` 随即命中、`:739` `stages.get(host.stage)`
   原样解析——`state.stage` 全文件仅 ：738/:798/:906 三处读写，改动封闭在本模态内
   （约 3 行）。等价修=stroke_cell 按 `host.stage == state.stage` 反查。两案皆不触
   任何其他系统；修后应补 L2 拖拽腿一轮（T3 报告 §八-2 同建议）。
4. **红证盲区句勘误（⚪）**：红证与报告称「T2 stage 测试把 host 与 stage 共址一实体
   所以 headless 查得到」——**实测全仓不存在任何走 stroke 模态逐帧路径的 headless
   测试**（tests 树 grep `TileStrokeState|stroke_cell|fronted_stage_entity` 零命中；
   `tests/stage/tilemap_ops.rs:7-8` 头注自述「panel chrome 与 pointer gesture 是 T3
   live 腿」；`src/tilemap_palette.rs` mod tests 仅 2 条显示算术测）。盲区的真实成因
   是**零覆盖**而非共址——缺陷定罪不变，归因句随本报告更正（§八-7）。
5. **「批算子门不受影响」声明核——成立**：批算子（paint/erase/fill/fill.flood）是
   独立 `#[operator]` 直收 `cells/layer` 参数，代码路径不触 `stroke_cell`（T2 QA §五-3
   源码亲证链沿用）；同构建同时段算子腿 draw 13/13+erase 8/8+fill 7/7 全绿=经验互证。
6. **用户路径影响（裁决权重项）**：真机画布上点击与拖拽**均不落格**（None 早退不分支
   于是否拖动）——「可制作」的**用户手势面**被 TM14 整体阻断；算子面（QA/MCP 工具
   通道、`remote_hidden`）全绿。验收句「可制作」按**机判面成立、用户面带票**判定，
   吸收/修复归主控（§九）。

## 四、QA 终验新抓：三个确定性门红（T22 引入、T22 门全逃逸、净跑+隔离双复现）

**共性**：三个红全在 `tests/keymap`/`tests/operators` 二进制——T22 三轮门禁（libtests
只 lib、targeted 只 `--test stage 'sprite_' 'tilemap'`、fast=fmt+clippy+lib、
scaffold_e2e 单测）**没有一个跑到它们**；T21 收官 integration 5575/5575 全绿=红体
T22-T2 引入。三轮红均 3-4 次观察连红（两轮 integration+QA 单包复跑），**非 flake**。

| # | 测试 | 断言原文（关键行） | 源码定位 | 修法（主控裁） |
|---|---|---|---|---|
| R1 | `keymap_user_overrides::every_operator_is_bound_or_listed_as_unbound` | `these operators have an input action, no chord, and no entry saying that is deliberate: ["tilemap.stroke"]` | `tests/keymap/keymap_user_overrides.rs:285`；机制=算子注册自动派生 OperatorAction→无 preset 弦+未列 `UNBOUND_OPERATORS` | `src/keybind_settings.rs:73` 清单加 `"tilemap.stroke"` 一行——同族先例精确在列（`viewport.draw_brush_modal`/`tools.measure_distance` 全是「自有面板到达」的手势模态） |
| R2 | `authoring_ops::every_entity_taking_operator_is_classified` | `an operator gained or lost an Entity parameter; classify it in ENTITY_PARAM_OPS…` diff 实测恰差 7 条：`tilemap.erase/fill/fill.flood [layer]`+`tilemap.paint [layer]`+`tilemap.layer.active/mode/visible [entity]` | `tests/operators/authoring_ops.rs:608` | `ENTITY_PARAM_OPS` 补 7 条分类（含逐条裁「选区可否填参」） |
| R3 | `sprite_ops::the_add_menu_shows_the_2d_group_only_with_a_2d_scene_open` | 2D 组分类期望 `[Sprite, Empty 2D]` vs 实测 `[Sprite, ("Tilemap Layer","op:tilemap.layer.add"), Empty 2D]` | `tests/operators/sprite_ops.rs:269`；行来源=`src/tilemap.rs:470-471` 算子注册（label "Tilemap Layer"）自动进 taxonomy | 更新 T21 精确分类断言收录 Tilemap Layer 行（行本身是真机腿天天在用的活入口）；若主控裁该行不该进菜单则反向收行——两向皆一行族 |

**处置**：三红均为「声明/分类/期望」面、零行为缺陷症状；但收官门「全量门绿」字面
不成立——建议主控合入前修掉（三件合计 <15 行、互不耦合、修后 integration 预期
5604/5604）或立票（TM16/TM17/TM18）排修。**QA 只记不修。**

## 五、TM 系立票素材核（TM15/TM11/TM12/TM10+TM13 撤销+F5/F6）——全部立得住

| 票 | 素材核 | 判 |
|---|---|---|
| TM15 🟡（redo 越存档点脏旗不翻） | `t22t3_live_undo.log` 原文：`DIRTY_AFTER_REDO_FAIL`+`dirty after 2 redos: false (history: …"redo":[erase,fill,layer.mode,layer.visible])` 与 `after 2 redos: count=3` 同框（文档已≠盘上空场景而 dirty 恒 false）；undo 侧 UNDO_DIRTY_HELD/DIRTY_AFTER_SAVE 绿=T03 全指纹链的 redo 侧缺口 | **立票素材成立**（T03 族，复现步=undo 链尾 save→redo 读 `jackdaw/history`） |
| TM11 🟡（开窗误报 "editor does not include"） | 红证 log:28 警告原文在档（10 份 editor 日志各 1 条=每相 boot 一条）；`src/module_picker.rs` `catalog_has_module` 的 `id == "animation"` 特判先例亲读（「tools compile into every editor」）；`modules.json` tilemap 条目**无 `extension` 位**亲读→落入 false 分支 | **立票素材成立**（补 tilemap 特判即与 animation 同形） |
| TM12 ⚪（调色板空板门） | `src/tilemap_palette.rs:241-260` 亲读：指纹先存（:249-253）后查面板（:254-260）→面板后到即指纹恒等永不填充；脚本解法=挂载后强制异值 pick（palette log PALETTE_PICK_PASS 绿侧） | **成立**（⚪，用户路径不受影响） |
| TM10 ⚪（发射模板带编译警告） | `shot-palette-panel.png` 底部构建面板**人眼可见** `warning: unused variable: parent → src/lib.rs:2288:20 for (tile, parent) in tiles`；prep 尾段同文 | **成立**（修法=`_parent`，一行） |
| TM13（撤销） | 撤销理由亲核：面板截图整图+网格+七色在带（§二-5），「sheet 未渲染」怀疑基于 AST patch 视图的 `image: ""` 非活组件——撤销正确，编号不复用 ✓ | **撤销维持** |
| F5/F6（T2 交接⑤） | F5 全轮面板交互走主键合成未复现误派发（观察级维持）；F6 复现路径（越界整笔拒）与 draw 基线深度 +3 恰三笔吻合、空条面未再现 | **观察级维持 ✓** |

## 六、QA 放行清单对照（方案 §四-T3+T2 交接硬项+任务书条目映射）

| 条目 | 终态 |
|---|---|
| **T1 验收**（rect 探针+碰撞内核+三决策定案+四门） | ✅ QA PASS（t22-t1-qa.md）；D2 硬约束（rect 像素半边必落 T3 L2/L7）本轮核销：M14_CANVAS_RECT（画布七负色全零）+M14_BSN_NO_ATLAS/RECT 双半边在案 |
| **T2 验收**（模板五件+组件族+10 算子+面板+色罩） | ✅ QA PASS（t22-t2-qa.md）；基线 3047 本轮 libtests/fast 双门复现零漂移 |
| **T3 交接硬项① D7 翻转** | ✅ 核销：prep 15/15 含 PREP_TILEMAP_ROW/DEP/LIB+TPL_TILEMAP_PRESENT+GAME_WARM（2m17s 暖编），`jd new --modules physics,tilemap` 一手写对四处 |
| **T3 交接硬项② PX 三件不滑出** | ✅ 核销：rect 画布 PX（L2/L7）+palette PX（L2）+TM7 色罩 PX（L4）全在案 |
| **T3 交接硬项③ L2 拖拽自守** | ✅ 形态在案：100% 缩放（截图工具栏 100%）+A7 五招（shot+frame0 成对 md5 全部 13 张）+判据以 BRP 计数为主；真踩面=TM14（记档不前置，符合方案决策 8-A） |
| **T3 交接硬项④ TM9 素材** | ✅ 素材在案未丢（t22t2_targeted_red.log+T2 QA §六）；buglist 本轮零触碰=纪律正确（主控笔面） |
| **T3 交接硬项⑤ F5/F6 真机验后定** | ✅ 观察级维持（§五） |
| **T3 方案项 1-3**（fixture+脚本+L1-L12；缺陷只记不修；14 格判定+三态表+30 秒清单） | ✅/⚠️：矩阵与 L 腿全立（§二）；TM 系续编只记不修 ✓；三态表逐行指认在报告 ✓；**30 秒清单草稿缺**（方案 §四-T3-3 要求 T3 报告携带）——本报告 §十补草稿（⚪ §八-8） |
| **T3 方案项 4 book 新章** | ❌ **未落**：`book/src/user-guide/tilemaps-2d.md` 不存在（分支 diff 零 book 触碰）；程序自述「按派单边界……留给 T3 收尾/QA 后主控排」（报告 §八-8）——T2 QA 交接清单亦未含此项。方案 §四-T3-4 字面缺项，🟡（§八-1） |
| **T3 方案项 5 buglist/roadmap/台账** | ✅ 纪律正确：三者本轮零触碰（diff 亲核）；roadmap 第 39 行未勾（留主控）；台账末行=T22-T2 QA（T3 行留主控）；A17 归本票未动 ✓ |
| **T3 方案项 6 终验门全量门** | ⚠️ 程序轮只跑六门（fmt/clippy×2/libtests/kernel/targeted），fast/integration/doctests/docs/scaffold_e2e 未跑（方案 §四-T3-6 列明五件）——QA 本轮补齐全跑（§一）；逃逸代价=§四三红直达终验才暴露（🟡 §八-2） |
| **关联票纪律** | A6（维持定案口径：今日两轮全量尽红+隔离 1/1 绿，§八-4 注记复发强度）/A7（五招在案未真踩）/A9（brp 8 重试+gbrp settle 在脚本，全程零 flake 假红）/A10（100% 缩放在案）/A14（调色板断言走 operator/BRP 直达）/A15（T22 零关联零触碰）/A16（T20 票，T22 flow 走 start_scene+游戏侧自读不受其死通道影响）/A17（结构性绕开+TM5 守卫+三处 no-atlas 断言在案）✅ |
| **任务书第 5/6 条（book 三子节/度表七层/无工具链/EG1-EG6/Errata E1-E6/验收句七词+编辑器配置完成+无工具链环境）** | **T20 终验模板误植**：上述词汇全部属 T20（最小完整示例游戏）的收官面，`loop/progress.md` 296 行 T20-T3 DONE 行可逐词对上；T22 无 EG 系缺陷（T22 用 TM 系）、无 Errata 台账、验收句为六工具词+运行/undo/保存/重开（§七）。终验按 T22 实态执行，T22 自己的 book 缺口如实计入（§八-1） |

## 七、验收句逐词证据指认

roadmap 第 39 行验收原文（逐字在案）：「**Tilemap 与 2D 碰撞关卡：调色板/绘制/擦除/
填充/图层/碰撞配置。验收=可制作并运行含地面/墙/触发区的小 2D 关卡；undo/保存/重开。**」

| 验收词 | 证据（QA 亲读/亲验） |
|---|---|
| 调色板 | M1：面板立起+sheet 真点选（读数翻转）+PX+bsn 层切割门（16/8）；人眼复核全渲染 |
| 绘制 | **算子面 ✅**：三笔 9 格/格值回读/一笔一条 undo/PX 1.33% 品红；**用户手势面 ❌=TM14 🔴**（点击与拖拽均不落格，§三-6）——本词按「算子面成立+手势面带票」判定 |
| 擦除 | M3：算子擦 1+擦空不炸+PX 回落 |
| 填充 | M4：矩形 6+环形 16+flood 9+越界种子拒（31 恒）+三色 PX |
| 图层 | M5：三层建/路由 2+1 分账/活动层切换落对层/可见性 PX 三拍/bsn 往返（save 三层+逐字段回读） |
| 碰撞配置 | M6：Solid/Trigger 算子写+BRP 回读+重开回读+TM7 色罩 PX+Inspector 注册面（T2 QA §五-1 register_type 链） |
| 可**制作** | 编辑器全链 M1-M8 算子/面板通道 ✅；用户手势通道=TM14 带票；「小 2D 关卡」实体=20 格三层 fixture（save log 20 格清单） |
| 可**运行**（地面/墙/触发区） | M10 direct（八拍逐位恒稳/288−12−0.001 截断/crossed+日志自述）+M11 PIE 同数+流送帧红+M12 staged 同数+包内 tiles.png 字节等同+manifest——三通道三行为全绿 |
| **undo** | M7：七操作步进 undo 逐级反转+redo 复演+一笔=一条（M2 深度账）+mode/visible 单条命令 undo（T2 亲跑链）；TM15=redo 脏旗缺口带票（🟡，T03 族） |
| **保存/重开** | M8：20 格三层落盘+零 texture_atlas+2D kind 再识别+逐字段相等+抽点格值；M9 Stop 链 SHA 恒等 |

## 八、偏差与记档分级（QA 视角）

| # | 级 | 项 | 事实与处置 |
|---|---|---|---|
| 1 | 🟡 | **book 章（方案 §四-T3-4）未落** | `tilemaps-2d.md` 不存在、SUMMARY 未动；T2 交接清单未含、程序自述留主控排。T22 闭环挂账件：主控要么补一轮 book 收尾（章内容=本报告 §二矩阵走查形态，方案已有大纲），要么明示豁免记 open-challenges |
| 2 | 🟡 | **integration 三确定性红（§四）** | T22-T2 引入、三轮门全逃逸、终验抓出；一行族修复 <15 行；合入前修掉或立 TM16-18 |
| 3 | 🟡 | **pie-stop 双 panic 未归因** | `loop/t22-live/editor-pie.log` 两拍 `swap_remove index (is 0) should be < len (is 0)` @ `jackdaw::pie::cleanup_session_on_stop`（pie.stop 时点，N13 同签名家族）；**pie 相的 warn_scan 在 `op pie.stop` 之前跑（t22-live.sh pie_phase 尾段）→结构性看不见**；报告 §七 D5 三处排除未含它、报告矩阵亦未记数。同日 stop 相的另一次 pie.stop 未复现=flaky；编辑器存活+STOP_SHA 绿。处置：并入 N13 族记数（「每 PIE 相 ≤2 条、绕行+读回重试绿」口径不变）；warn 扫描脚本建议把 scan 挪到 pie.stop 之后（工具级，一行） |
| 4 | ⚪ | **A6 复发强度注记** | 今日两轮全量尽红（各 3 试）+隔离 1/1 绿；T19/T20 时代为「轮内未触发/三试尽红+隔离绿」——定案口径维持（满载 flaky、磁盘高压家族），主控合入时建议按「两轮尽红+隔离绿」措辞记录 |
| 5 | ⚪ | **TM7 报告数与归档 drift** | 报告 0.55%→0.01% vs 归档 1.91%→0.00%；判据（tool-in>tool-away+0.01 且 >0.01）同向成立，PASS 不受影响；主控合入时可顺手更正两数 |
| 6 | ⚪ | **scaffold_e2e ci 轮超时=门配置/环境面** | e2e 依赖缓存 `target/scaffold-e2e/<模板+lockfile 哈希>` 空（mtime 10-29）→冷构建远超 ci profile `terminate-after=6`×30s=180s 硬杀；heavy profile（为此类 e2e 而设，不硬杀）2/2 绿 276.4s。处置：T22 三轮的 e2e 绿证（T2 的 125.9s）皆暖缓存形态，建议收官门 e2e 固定走 heavy 或先暖后 ci——门配置小票候选 |
| 7 | ⚪ | **TM14 红证盲区句不准确** | 「T2 stage 测试共址」→实为「全仓零 stroke 模态 headless 覆盖」（§三-4）；定罪不变 |
| 8 | ⚪ | **30 秒清单草稿缺+程序门禁表窄** | 方案 §四-T3-3 要求 T3 报告带草稿——本报告 §十补；程序门禁表六门不含全量门五件（方案 §四-T3-6）——QA 补齐 |
| 9 | ⚪ | **QA 自身程序失误（如实入档）** | 第一轮 integration 在跑时 QA 并发执行了异 feature 单包测试→dyld 符号失配 852 级联→该轮作废重跑净轮；两红与 flake 先于污染时点且净跑复现。教训=门链独窗纪律对 QA 自己的抽查同样适用 |
| 10 | ⚪ | **任务书模板误植** | 任务书第 5/6 条 book/EG/无工具链/七词等系 T20 终验面（§六末行）；本终验按 T22 实态执行并如实说明 |

**未动面**：`src/`、`crates/`、templates、fork（status 干净亲验）、协议、场景格式、
book、buglist、roadmap、台账——T3 零改动；红线 `bevy_ecs_tilemap` 全树（除 loop/ 与
target/）grep 零命中亲验；probe-a 分支未触碰。工作树仅 QA 归档 13 件日志+2 脚本+本
报告；RUST_BACKTRACE 全程未设；结束零 jackdaw/nextest/cargo 残留进程（ps 亲验）。

## 九、最终裁决与 roadmap 建议

- **T22-T3 验收标准（方案 §四-T3）**：M1-M14 逐格判定+L1-L12 全腿 ✅（§二，零虚报）；
  缺陷只记不修 TM 系续编 ✅（§五）；30 秒清单 ⚠️ 缺→本报告补；book 章 ❌ 未落
  （§八-1）；buglist/roadmap/台账零触碰 ✅；全量门 ⚠️ QA 补跑、integration 带 3 红
  （§四）。**程序轮证据与矩阵：PASS；收官段字面项：部分缺。**
- **T22 整体（T1/T2/T3）**：验收句逐词在案（§七，绘制词用户面带 TM14 票）；三铁证
  立（可制作=算子面板链+可运行=三通道三行为+undo/保存/重开=T03/T06 机器 tilemap
  形态）；门禁：八门绿+integration 5600/5604（3 确定性红+A6 口径内）+e2e heavy 绿
  +doctests 处方维持；三轮 QA 裁决链 T1 PASS→T2 PASS→T3 终验（本报告）。
- **VERDICT: PASS（有条件）——T22-T3 真机矩阵与证据链放行；T22 整体闭环挂四件
  主控面，闭单前 roadmap T22（第 39 行）建议暂缓勾选：**
  1. **三红一行族修复**（§四 R1/R2/R3，<15 行）+净跑 integration 预期 5604/5604——
     建议合入前在分支上修掉（与 T2「门禁抓出即修」先例同形）；
  2. **TM14 🔴 裁定**（吸收为已知票 or 修复——修法 §三-3 约 3 行；修复则补 L2 拖拽
     腿一轮；吸收则 roadmap 勾选注记「画布手势待修、算子门为授权正主」）；
  3. **book 章 `tilemaps-2d.md`**（补一轮或明示豁免）；
  4. **TM15/TM11（🟡）+TM12/TM10（⚪）+TM16-18（若立）buglist 落账**——票面素材全部
     齐备（§五/§四）。
- **主控合入路径建议**：上述 1（必做）+2/3（裁定）落定后 `--no-ff` 合入（T3 单提交
  ffed51ae 随 T2 之后）；主控落笔面=roadmap 第 39 行勾选+收官行、台账 T22-T3/T22
  DONE 行、buglist TM 系落账；`git status` 除 QA 归档零触碰。
- **回滚面（如实）**：T22 产品面=T1 内核 crate+tests 两件+T2 组件族/工具族/模板
  module 三件，各自独立可 revert；T3 零产品改动=回滚零成本；fork 零触碰、协议零
  变更、场景格式零破坏。

## 十、用户 30 秒清单（草稿，替 T3 报告补交；TM14 修复前第 2 步不可用）

1. **开 2D 场景、按 T 切 Tilemap 工具**：右侧调色板面板出现——sheet 网格+七色格+
   高亮框+Tile 读数+层行（Eye/P·S·T）+「+ Add Layer」。点一个格，读数翻转为该 tile
   （M1）。
2. **画几格地面**：在画布上拖拽过格即落 tile——**TM14 修复前此步不工作**（模态挂死
   需 Esc）；修复后=M2 三笔 9 格+一笔一条 undo 的用户形态。（当前等价通路：Add 菜单
   「Tilemap Layer」建层后由脚本/算子画格。）
3. **建触发层并上色**：「+ Add Layer」建 Trigger 层→面板行 P·S·T 循环到 T→画两格→
   切回 Select 工具看青色罩消失/出现（M6+TM7）。
4. **撤销与保存**：Ctrl+Z 逐笔回退（一笔一条）、`scene.save` 落盘、重开——三层格全
   回来、2D 场景再识别（M7/M8）。
5. **Play 站得住**：Play（embedded）——小人落在地面 y=76 纹丝不动、横移撞墙截停、
   进触发区 crossed 翻灯+日志自述（M10/M11）；导出后无工具链机器同三行为（M12）。

## QA 会话产物索引

- QA 门禁：`loop/reports/t22t3_qa_{fmt,libtests,fast,audio_gate,save_store,doc,
  scaffold_e2e,scaffold_e2e_heavy,integration,integration2,a6_isolated,doctests,
  doctests_bind_rerun}.log` + 门链脚本 `t22t3_qa_gates.sh`/`t22t3_qa_gates2.sh`。
- 核验对象：`loop/reports/t22-t3-report.md`+归档 t22t3_*（live 13+editor 10+game 3+
  gates 6+TM14 红证）；T1/T2 报告与 QA；`loop/qa/t22-live.sh`（warn_scan/TM7/draw/
  fill/pie 相断言段亲读）；`loop/t22-live/`（editor/game 日志 22 份 warn 亲扫+13 张
  PNG 两张人眼）；`loop/plans/roadmap-game-dev.md` 第 39 行；`loop/progress.md`
  296-306 行；buglist A6/A7/A9/A10/A14/A15/A16/A17。
- 源码复核点：`src/tilemap_palette.rs`（:730-750 stroke_cell/:893-901 fronted_stage_
  entity/:241-260 sync_palette_content/:985 tests）、`src/viewport_2d.rs:1764`、
  `src/keybind_settings.rs:73`、`src/tilemap.rs:470`、`src/module_picker.rs`
  （catalog_has_module animation 特判）、`tests/keymap/keymap_user_overrides.rs:285`、
  `tests/operators/{authoring_ops.rs:608,sprite_ops.rs:269}`、`tests/stage/
  tilemap_ops.rs`（头注）、`crates/jackdaw_project_build/src/modules.json`、
  `.config/nextest.toml`（ci/heavy profile）、`tests/scaffold_e2e.rs`（缓存键）、
  `xtask/src/main.rs`（fast/integration 组成）。

—— QA agent（loop 自动化终验），2026-11-02
