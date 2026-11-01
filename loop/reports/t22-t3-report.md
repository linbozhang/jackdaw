# T22-T3 程序报告：真机矩阵轮（M 系+L 腿）+ 终验准备

> 分支 `loop/t22-tilemap`（自 main 706f88f3 fast-forward 同步后直接续做，merge 零冲突）。
> 任务书=`loop/plans/t22-tilemap.md` §二/§三/§四-T3 + T2 QA 交接硬项（D7 翻转/PX 三件不
> 滑出/L2 自守/TM9 素材/F5·F6 真机验后定）。归档=`loop/reports/t22t3_*`（34 件）+ 真机
> 工件 `loop/t22-live/`（console/editor/game 日志+shot-*.png）。报告日期 2026-11-02。
> RUST_BACKTRACE 全程未设；门链与 live 脚本分窗串行（T12-T3 纪律）；脚本长命令全部
> 后台+轮询；门前 df 109Gi free；每 phase 自 pkill 清理。

## 一、结论（定案门）

**T3 真机矩阵 14 格全部落判：13 绿 + M2 绿（手势面带 TM14 记档）+ M7 绿（redo 脏面带
TM15 记档）；L1-L12 十二条腿全部跑到，L11（flow 可选延伸格）亦跑通。** 碰撞三态真机
教科书级：direct run 探针落地面 y=76.001（理论 76）、满道位移被墙截在 x=275.999
（理论 288−12−0.001）、TriggerCensus.crossed=true 且游戏日志自述"the probe walked
into a trigger cell"；PIE 与 staged 导出同数复现（M11/M12）。D7 翻转以 `jd new
--modules physics,tilemap` 落进 prep（行翻转+内核 crate 入游戏 manifest+占位符发射+
re-lock 暖编 2m17s，一次到位），prep 重跑 15/15 绿。**本轮零产品代码改动**（分支 diff=
脚本+报告+归档）；新缺陷 TM10/TM11/TM12/TM14/TM15 记档待裁（TM13 立项后撤）。

## 二、D7 翻转 + prep 重跑（交接硬项①）

T2 QA 硬项原文：fixture `jackdaw.toml` 的 `tilemap = false` 翻 true+re-lock+暖编。
落地形态：prep 的 `jd new` 追加 `--modules physics,tilemap`——脚手架一手写对四处：
①`jackdaw.toml` `tilemap = true`；②游戏 Cargo.toml 增 `jackdaw_tilemap_collision`
path dep（re-lock 证据=console-prep.log 的 Locking 29 packages 段）；③`src/lib.rs`
发射 `TilemapProbePlugin`+LevelGrid/PlayerProbe/TriggerCensus 教学段；④暖编真编译
（2m17s）。新增四条 prep 断言腿：PREP_TILEMAP_ROW/DEP/LIB + 既有 GAME_WARM。
**prep 重跑=15/15 PASS**（t22t3_live_prep.log）。flow `start_scene` 同时指到
scene.bsn（t19/t21 形态），run/pie/export 三腿的 Level 门一次到位。

## 三、14 格矩阵逐格判定（铁证索引=loop/reports/t22t3_live_*.log + loop/t22-live/shot-*.png）

| 格 | 判定 | 真机证据（L 腿） |
|---|---|---|
| M1 调色板 | ✅ | palette 8/8：层切割回读（bsn 门 columns=16/rows=8）、面板立起、**面板 sheet 真点选**（ui_drag 入格→读数 Tile 0→Tile 101 翻转）、tile.select 算子门、面板 PX（chrome 66.5%+sheet 橙块 19.6%+七色在带，截图 shot-palette-panel.png 人眼复核=整图+网格+高亮+读数+层行全渲染） |
| M2 绘制 | ✅（手势面记档 TM14） | draw 13/13：三笔 9 格、格值回读 (0,2)=4、viewport PX（品红 1.33%、七负色全零=rect 裁剪非整图）、一笔=一条 undo（深度基线 +3，undo 一笔退 3 格）、越界格整笔拒后存活。**画布拖拽手势=TM14**（能武装、永不放笔，见 §六）；批算子=MCP-first 正主门 |
| M3 擦除 | ✅ | erase 8/8：算子擦 1、擦空格不炸（计数恒 0）、PX（红 0.44%→擦后回落） |
| M4 填充 | ✅ | fill 7/7：矩形 6 格、环形 16 格+flood 9 格（边界停在 ring）、越界种子拒后计数不动（31）、三色同框 PX（blue 0.89/red 2.51/magenta 1.33%） |
| M5 图层 | ✅ | layers 7/7：**无层名 paint 落在活动层**（Ground 2/Wall 1 分账）、活动层切回后再画落 Ground、可见性 PX（隐→红 0.44%→0.15%→复现 0.44%，Hero 自带红=残留份额）、层 bsn 往返（save 三层 grep=3+逐字段回读） |
| M6 碰撞配置 | ✅ | mode solid/trigger 算子写+BRP 回读（"Solid"/"Trigger"）+重开回读、**TM7 色罩 PX**（工具在位 0.55%→Select 工具 0.01%）、Inspector 门（组件 Reflect 注册在册） |
| M7 undo | ✅（redo 脏面记档 TM15） | undo 14/15：七操作步进 undo 逐级计数/模式/可见反转全中、redo 复演、脏旗 save 后 false——**redo 越过存档点脏旗不翻=TM15**（§六） |
| M8 保存重开 | ✅ | save 12/12：20 格三层落盘、bsn 无 texture_atlas、重开 2D kind 再识别（tilemap 算子应答）、逐字段相等（form 16/8、模式 Solid×2+Trigger、每层格数 15/3/2、格值抽点 7,1=0 / 9,3=2 / 5,2=4） |
| M9 Stop | ✅ | stop 7/7：PIE 播→Stop→场景文档 SHA 不变 |
| M10 direct run | ✅ | run 7/7：y=76.001 八拍恒稳=**地面站得住**；x=275.999=**墙挡住**（面 288−半 12−分离 0.001）；crossed=true+游戏日志自述=**触发区触发**；全部 bevy 原生读（N12 口径） |
| M11 PIE | ✅ | pie 7/7：embedded 流送窗同数（76.001/275.999/crossed）、流送条带红 census 0.50%（SP7 结论复用：embedded 忠实） |
| M12 导出 | ✅ | export 11/11：staged 异目录 env -i 启动、包内 tiles.png 字节等同、scene.bsn 带格、flow 指 scene.bsn、export-manifest.json 在包；staged 同三断言（76.001/275.999/crossed） |
| M13 flow（可选延伸） | ✅ | flow 3/3：menu→Start→2D 关卡加载（3 层+探针）、Pause→menu→场景世界零残留（层 0）；探针存活=模板教学的设计面（player 不属于任何 scene 文档） |
| M14 负向守卫 | ✅ | 画布半边=draw 七负色全零（rect 裁剪）；bsn 半边=零 texture_atlas+rect: Some 在位；TM5 守卫测试仍在 stage 族随行 |

关键属性三态表逐行指认：调色板 M1/M8/M12、绘制 M2/M7/M10、擦除 M3/M7、填充 M4/M7/M10、
图层 M5/M8/M10、碰撞配置 M6/M8/M10、玩家探针 M10/M11/M12——**全行有真机证据**。

## 四、L 腿全量（12/12 跑到）

L1 prep+boot+三层（prep 15/15+各 phase 自启+save 层断言）；L2 palette+draw；
L3 erase+fill；L4 layers+collision（mode 回读+色罩 PX）；L5 undo 链；L6 save/reopen；
L7 Stop+M14 守卫；L8 direct run；L9 PIE；L10 export；L11 flow（可选格跑通）；
L12 warn 扫描+存活=每 phase 尾腿（见 §七扫描口径）。

## 五、门禁（终树；产品零改动，基线不漂）

| 门 | 结果 | 证据 |
|---|---|---|
| `cargo fmt --all -- --check` | ✅ EXIT=0 | t22t3_gates_fmt.log |
| `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | ✅ EXIT=0，全文零 warning 行 | t22t3_gates_clippy_ws.log |
| `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | ✅ EXIT=0 | t22t3_gates_clippy_phys.log |
| `cargo nextest run --profile ci --workspace --lib` | ✅ **3047/3047**（=T2 基线，零漂移） | t22t3_gates_libtests.log |
| 内核 crate | ✅ **11/11** | t22t3_gates_kernel.log |
| 受影响域 `-p jackdaw --test stage 'sprite_' 'tilemap'` | ✅ **71/71** | t22t3_gates_targeted.log |
| AN2 腿 | ✅ 维持 | 脚本 `brp()` 8 次重试读+`gbrp()` 3 次短 settle，全程零 flake 假红 |

全日志逐行扫描 `^error|FAILED`：六件全零命中（exit 仅辅助，全文复核为准）。

## 六、新缺陷（TM 系续编，只记不修；红证先落盘）

| 编号 | 严重度 | 描述与诊断 | 证据 |
|---|---|---|---|
| **TM14** | 🔴 | **画布拖拽手势在真机画布上挂死**：`tilemap.stroke` 能武装（PRESS 到位）但永不完成——`stroke_cell()` 用 `hosts.get(state.stage?)` 在**被捕获的 stage 实体**上查 `Viewport2dPanelHost`，而该组件挂在 stage 所挂的 panel content 实体上（viewport_2d.rs:1764 insert 在 `parent`，`stage` 是持 `Scene2dViewport` 的另一实体）→ 每帧 None→None 早退先于 just_released 检查→release 永远看不见，模态持续到 Esc/cancel。headless 盲区：T2 stage 测试把 host 与 stage 共址在一实体上。修法一线（改查 panel 实体或组件挪位），归主控裁。批算子门不受影响（本轮全部绘制/擦除/填充真机证据走算子门） | 红证=`t22t3_tm14_stroke_red.log`（先落盘）；绿侧旁证=算子门 draw 13/13 |
| **TM15** | 🟡 | **redo 越过存档点脏旗不翻**：undo 到基线→save（dirty false ✓）→redo ×2（文档已现 3 格≠盘上空场景）→`jackdaw/history` 与 `jackdaw/status` 的 dirty 恒 false（重试 8s+）。undo 侧旗面正常（存档点回零=clean）。存档指示说谎面，T03 族 | 红证=存档 `t22t3_live_undo.log` 尾段（history JSON 在案） |
| **TM12** | ⚪ | **调色板面板空板门**：`sync_palette_content` 的指纹在面板挂载前先行入库（panel 不在时 insert 后 return），面板后到则指纹恒等→永远不填充；同值 `tile.select` 不改指纹救不了。脚本解法=面板挂载后强制一次异值 pick。用户路径（工具先出、画布在前）不受影响 | `t22t3_live_palette.log` 前两轮红+本轮 setup 注释 |
| **TM11** | 🟡 | **tilemap 工程打开即报"editor does not include"**：modules.json 的 tilemap 条目无 `extension` 位，`editor_has_module()` 走 false——但 tilemap 作者面（src/tilemap.rs 全族）编译进每个编辑器，只有游戏侧内核随模块走（与 animation 的 module_picker.rs:43 特判同形，特判缺席）。警告文本"cannot be edited here"与行为相反（Tilemap 工具一切正常）。每 phase 的 WARN 扫描按已知面排除该行（脚本注明） | 每 phase editor 日志首段；本报告 §七 |
| **TM10** | ⚪ | **发射的模板代码带一个编译警告**：每个启用 tilemap 模块的脚手架工程 `cargo build` 出 `unused variable: parent`（lib.rs.template 的 `collect_level_grid` 循环绑定 `for (tile, parent)`，body 只用 tile；filter 闭包里的是另一个同名）。修法=`_parent`。本轮 fixture 首次真编译暴露（T2 的 e2e 只断言 schema 未盯警告） | `t22t3_live_prep.log` 尾段 |
| ~~TM13~~ | — | **立项后撤**：调色板 sheet 图未渲染的怀疑基于 `jackdaw/entity` bsn 读出 `image: ""`（AST patch 视图的序列化，非活组件）；面板带像素复查=七色在带+橙块 19.6%，截图人眼复核整图渲染完好。编号不复用 | 本报告 §三-M1 证据链 |

T2 QA 交接硬项⑤（F5 面板 chrome 非主键 press、F6 空笔画空 undo 条）真机面：F5 本轮
全部面板交互走 ui_click/ui_drag 主键合成，未复现误派发（观察级维持）；F6 复现路径
（越界整笔拒不压条）与 draw 基线深度账吻合（+3 恰三笔），空条面未再现（观察级维持）。

## 七、偏差与脚本口径（如实）

| # | 偏差 | 处置 |
|---|---|---|
| D1 | M2 的「画布拖拽过格」以**批算子门**承载（TM14 记档），拖拽手势只有武装+挂死两拍真机证据 | 方案 MCP 优先原则：算子=QA 工具层正主门；手势修复归 TM14 主控裁，修后 L2 拖拽腿应补一轮 |
| D2 | 调色板 sheet 点选判定=**读数翻转**（Tile 0→Tile 101）而非预设格号：合成拖拽入格的落点随通道标度浮动，一次标定不跨会话稳 | 判据保真（点选写活动 tile 的行为面）；确定性格号面由 tile.select 算子腿承载（TILE_SELECT PASS） |
| D3 | prep 的 D7 翻转用 `--modules` 旗（一手写对四件）而非手改 `jackdaw.toml`+编辑器 resolve | 终态逐字段与 QA 硬项等价（行/dep/发射/锁+暖编），四断言腿在案；且 prep 的 rm -rf 重建使「先翻后跑 prep」必然丢翻转——翻转必须住在 prep 里 |
| D4 | 脚本 `setup_tool_session` 在**每次会话前重写 starter 场景**：无此守卫时上一 phase 落盘的层会让 `Ground` 撞名 fork 成 `Ground2`（实证一次：4 行 TilemapLayer、作者层被改名），run 腿吃到脏盘 | 防污染守卫+save 阶段同守卫；代价=save 之后重跑任何编辑器 phase 会清掉关卡（**run/pie/export 前必须最后跑 save**——顺序依赖已写进脚本头注） |
| D5 | warn 扫描三处已知面排除（逐条注明）：①T2 的 TileBrush/tile_size 对；②TM11 的 module 警告行；③`no in-bounds cells to paint`（越界整笔拒的**设计内**拒绝警告）+fixture 路径子串 | 扫描收紧为 ` WARN | ERROR |panicked ` 级别行再带 token（裸 token 被 INFO 的 `OPERATOR: tilemap.*` 自名日志淹没）；排除清单全在脚本注释 |
| D6 | export 面状态词=`ready`（非 idle）、outcome=产物名（非 "ok"）——首轮按臆测词轮询烧满 1500s 预算 | 已按真词修正（face JSON 全文在案 t22t3_live_export.log）；首轮红归档于 /tmp/t22-export-run1.log（未入 reports，脚本轮询 bug 非产品面） |
| D7 | libtests 归档日志取 tail -6 摘要（Summary 行 3047/3047 全文在案），非全量流水 | nextest 摘要即机判面；QA 复跑可用同命令全文 |

## 八、给 QA 的注意事项

1. **零产品改动**：分支 diff=loop/qa/t22-live.sh（T3 腿正式化+D7 翻转+守卫）+本报告+归档。
   门禁六门全绿=基线复证（3047/11/71），QA 可全信归档或按命令复跑。
2. **TM14 是本轮唯一红级新缺陷**（画布拖拽挂死）——QA 裁决时请先读
   `t22t3_tm14_stroke_red.log`（红证+源码级病灶+一线修法）；M2 的放行口径建议按
   「算子门绿+手势面带票」处理，修复落地后补一轮 L2 拖拽腿。
3. **TM15**（redo 脏旗）建议并入 T03 族评估；复现=undo 链尾 save→redo，读
   `jackdaw/status` 的 dirty（脚本 undo 腿尾段即现成复现步）。
4. **顺序依赖**：复跑任何编辑器 phase 会把盘上场景重置为 starter；要复跑 run/pie/export
   先复跑 save。脚本头注已写。
5. 调色板 sheet 点选腿的判据=读数翻转（D2）；若 QA 复跑落出别的格号（非 101）属正常，
   判「Tile 0→非 0」即绿。
6. prep 现产 **512×256** sheet（16×8×32px）——T2 QA 记录的 128×64 已被 T3 扩容（层
   columns/rows=切割=关卡网格一体，16×8 才装得下地面/墙/触发的三态几何）；fixture
   jackdaw.toml 带 `tilemap = true`（D7 终态）。
7. 归档索引：门禁 6 件 `t22t3_gates_*`、live 13 件 `t22t3_live_*`、editor 10 件、
   game 3 件、TM14 红证 1 件；PNG 证据在 `loop/t22-live/shot-*.png`（palette-panel /
   draw-baseline / draw-painted / erase-before / erase-after / fill-canvas /
   layers-visible / layers-hidden / layers-again / tm7-tint / tm7-off / stop-canvas /
   pie-stream）。
8. 本轮未动（按派单边界）：book 新章 `tilemaps-2d.md`、buglist/台账/roadmap、
   F5/F6 的收窄小票——留给 T3 收尾/QA 后主控排。**TM9**（T2 的 PointerPress 冒泡教训）
   素材仍在 T2 QA 报告 §六/§九+`t22t2_targeted_red.log`，buglist 记档同样待主控排
   （本轮未触碰 buglist）。
9. 本轮零 RUST_BACKTRACE；所有红态先落盘再修（TM14 红证独立成件；其余红=脚本口径
   迭代，按门禁日志覆盖归档契约处理，唯 TM14/TM15 的产品面红永在存档内）。

---

## 补：T3.5 小修轮（2026-11-02，合入前置；主控裁定：终验已覆盖矩阵面，余项 docs+机械修复）

**四件全落 + 门禁全绿。** 分支同一（`loop/t22-tilemap`，T3.5 提交注明）；本轮**产品代码首次改动**=TM14 修复（+派单外的第二病灶，见下）。

### 1. book 章补落 ✅

`book/src/user-guide/tilemaps-2d.md` 新章（~150 行，house voice 对齐 sprites-2d.md）：2D 关卡制作导览（T 工具+调色板面板：sheet 陈列/格点选/`Tile N` 读数/highlight/brush 四钮/层行 Eye·P·S·T·激活/+ Add Layer——全部 UI 名现场核对源码防杜撰）、绘制/擦除/矩形+flood 填充（一笔=一 undo、Esc/右键取消、越界整笔拒）、图层与碰撞三态（P 装饰/S 地面墙/T 触发的运行时语义）、undo/保存重开、tilemap 模块与游戏侧教学块（三行为+census 反射注册对 A16/EG8 的对照注记）、**无工具链独立运行**（jd export staged 包内运行说明）、rect-vs-atlas 双柄空间注记（A17/TM5：「tile 渲染成整图=bug 非设置」）、规模边界注记（sheet=关卡，小关卡字面）、EG2 边界（关卡道具行为归游戏代码，编辑器authoring 网格）、30 秒清单。SUMMARY 挂目（Sprites in 2D 之后）+三交叉引用（sprites-2d 正向引新章、physics.md 新增「两栈分界」节、新章内引 game-flow）；全链接机查零缺失。

### 2. TM14 🔴 修复 ✅（红绿+真机翻转验证）

**两处病灶，主控裁的 ~3 行修法之外还藏着第二个：**
1. **host 实体**（QA 评估的面）：`TileStrokeState.stage`（stage 节点实体）→ `host`（携带 `Viewport2dPanelHost` 的 panel content 实体），`fronted_stage_entity`→`fronted_host_entity`（查询改 `(Entity, &Viewport2dPanelHost)`）——stroke_cell 的 host 查找真机命中。
2. **派发时序**（修完 1 后真机仍 0 格的实测逼出）：release 帧 `commands.queue` 的批算子调用在**同一 tick 的 invoke 内自动应用**——此刻 `ActiveModalOperator` 尚未拆除（finalize 在 invoke 返回后才跑）→ `can_act_on_entities` 见模态运行 → `tilemap.paint` 可用性拒绝 → `Ok(Cancelled)` 静默（dispatch_operator.rs:646 的 debug 级）。修法=**延迟一帧派发**：`PendingStrokeDispatch` 资源（release 帧落 Cells/Fill 意图），新 `apply_pending_stroke` Update 系统次帧应用（模态已退；若同帧尚在则顺延一帧）。flood 的 init 帧派发同路径同修。

**红绿**：红证=`t22t3_tm14_stroke_red.log`（T3 轮已落盘）+ T3.5 两轮中间态实测（修 1 后 modal 清但 0 格；插桩 `T35PROBE release: visited=3 / dispatch: Ok(Cancelled)` 实锤时序病灶，插桩已移除）；绿=真机拖拽落格（下）+headless tilemap 8/8+operators 169/169+clippy 0。
**真机翻转验证**（`t22t35_tm14_drag_green.log`）：press→3 moves→release：mid-drag modal=tilemap.stroke → release 后 **cells=3**、history+1（一笔=一条）、modal=null 干净退场 → 一次 undo cells=0。**M2 手势面翻转完成**——draw phase 恢复真实拖拽腿（STROKE_RELEASES/DRAW_DRAG_LANDS 两新腿）并全重跑 **13/13 PASS**（t22t35_live_draw.log）。

### 3. 三个确定性门红修复 ✅（各 <15 行）

| # | 修复 | 红证→绿证 |
|---|---|---|
| ① | `tilemap.stroke` 入 `UNBOUND_OPERATORS`（src/keybind_settings.rs，draw_brush_modal 同族） | `t22t35_unbound_red.log`（"no entry saying that is deliberate: [\"tilemap.stroke\"]"）→ keymap 50/50（t22t35_unbound_green.log/t22t35_gates_keymap.log） |
| ② | 7 个 tilemap 实体参算子入 `ENTITY_PARAM_OPS`（tests/operators/authoring_ops.rs；全部 `false`=不食 selection——层缺省走调色板活动层，选择回填语义错误） | `t22t35_entityparam_addmenu_red.log`（left 恰缺 7 行实捕）→ operators 169/169 |
| ③ | T21 add-menu 精确分类断言随「Tilemap Layer」行更新（tests/operators/sprite_ops.rs：三行序 Sprite/Tilemap Layer/Empty 2D） | 同上红 log（left==right 断言原文）→ 同绿 |

**fast 重跑覆盖归档**：`t22t35_gates_fast.log` EXIT=0、lib **3047/3047**、全文零 `^error`/FAILED/Diff。受影响域终归档：tilemap stage **8/8**（t22t35_gates_tilemap.log）、keymap **50/50**、operators **169/169**。integration 按 A6 口径采信 T3 轮归档（本轮 diff：tilemap_palette 模态内+三个测试文件，与 integration 域零交集）。

### 4. TM15/TM11 立票落 buglist ✅

buglist.md 代理发现节尾追加两条（主控批准立账=T3.5 裁定）：**TM15**（redo 越存档点 dirty 不翻：现象/证据/修法=redo 后按深度+指纹重算 dirty，🟡 建议）；**TM11**（tilemap 工程开窗误报 editor does not include：机制=editor_has_module 缺 animation 式特判，修法=一行特判或 catalog 加 editor_builtin 位，🟡 建议）。其余 buglist/台账/roadmap 未动（按裁定）。

### 5. 门禁 ✅

fast EXIT=0（3047/3047 全文复核零红）+ 受影响域三族全绿（8/50/169）+ TM14 触碰面的 clippy `-p jackdaw -D warnings` 0。integration 采信归档（A6 口径）。

### T3.5 遗留与说明

- TM12（调色板空板门）、TM10（模板编译警告）按裁定**维持记档**未修（TM14 修复顺带消除了 TM12 对 live 腿的阻断——setup 的两-pick 解法保留为防御）。
- 派单注：draw phase 的 STROKE_ARMS/STROKE_CANCEL_CLEARS 两腿随 TM14 修复被真实拖拽腿（STROKE_RELEASES/DRAW_DRAG_LANDS）取代——旧腿验证的是挂死态，新腿验证落格态。
- TM14 修复插桩（T35PROBE info!）已全部移除，clippy -D warnings 干净为证。
