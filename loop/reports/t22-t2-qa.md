# T22-T2 QA 报告：建设轮（模板接入+调色板+绘制/擦除/填充+图层）—— 裁决 PASS（放行 T22-T3）

> 验收对象=`loop/reports/t22-t2-report.md`（分支 `loop/t22-tilemap`，程序提交 427d7177，
> 自 main f24e86cc）。方案=`loop/plans/t22-tilemap.md` §四-T2+§五决策表（主控 8 点全裁
> 建议：1=C 路 / 2=自建内核 / 3=缓收 / 4=A / 5=A / 6=A / 7=A / 8=不前置）+台账 T22 方案行。
> T1 QA 回流四件（TPL 翻转必做/门禁表 fast 行/基线 3037/D2 rect 像素硬项 T3）逐项核销见 §三/§二/§七。
> QA 亲跑日期 2026-11-02。归档=`loop/reports/t22t2_qa_*`（九门日志+live 两件）。
> RUST_BACKTRACE 全程未设；门链与 live 脚本分窗串行（T12-T3 纪律）；门禁前 df 137Gi free。

## 一、结论

**PASS。** 六件建设面（组件族三件/Tilemap 工具/调色板面板/10 算子族含一笔=一条 undo/
画布 stroke 模态/TM7 色罩）源码级逐项复核成立；模板接入五件同步面亲读+守卫翻转
`TPL_TILEMAP_PRESENT` 亲跑 PASS；e2e 编译测试亲跑（125.9s 真构建+schema 断言）——
「emitted 代码真实编译」声明成立；九门亲跑全绿（日志全文复核，exit 仅辅助）；
三处门禁抓出的缺陷**修复面全部源码级亲证、绿侧全部亲跑复现**（红侧归档质量按 F1/F2
记档，不影响裁决）；D1-D8 逐条裁定（§七）。无阻断项。

## 二、门禁表（QA 亲跑终树 427d7177；日志全文复核为准）

| 门 | 命令 | 结果 | 证据 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | ✅ EXIT=0 零 Diff | t22t2_qa_gates_fmt.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | ✅ EXIT=0，全文零 error/warning 行 | t22t2_qa_gates_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | ✅ EXIT=0，全文零行 | t22t2_qa_gates_clippy_phys.log |
| libtests | `cargo nextest run --profile ci --workspace --lib` | ✅ **3047/3047**（=T1 基线 3037+editor lib 9+scaffold teaches 1，拆账亲核 §六-3） | t22t2_qa_gates_libtests.log |
| libtests（dispatch 字面形态） | `cargo test --workspace --lib` | ✅ EXIT=0，全部 `test result: ok`，与 nextest 同源 3047 互证 | t22t2_qa_gates_libtests_cargo.log |
| 内核 crate | `cargo nextest run --profile ci -p jackdaw_tilemap_collision` | ✅ 11/11（未触碰） | t22t2_qa_gates_kernel.log |
| 受影响域 | `cargo nextest run --profile ci -p jackdaw --test stage 'sprite_' 'tilemap'` | ✅ **71/71**（拆分亲核：sprite_drop 6+sprite_gizmo 31+sprite_picking 11+sprite_snap 13+world_guides 2+tilemap_guard 2+tilemap_ops 6；报告「sprite 四族 63」把 world_guides 2 计入——测试名含 `sprite_` 所致，总数无误） | t22t2_qa_gates_targeted.log |
| e2e 编译 | `cargo nextest run -p jackdaw --test scaffold_e2e scaffold_tilemap` | ✅ **125.894s** 真构建+schema 断言（§四） | t22t2_qa_gates_e2e.log |
| fast | `cargo xtask fast` | ✅ EXIT=0：fmt 段零 Diff、clippy 段 `--deny warnings` 零行、lib 段 **3047/3047**；全文零 error/FAILED/Diff（唯一 `error:` 命中=测试模块路径子串 `jackdaw_bind error::tests::…` 的 PASS 行，归因非警） | t22t2_qa_gates_fast.log |

- **live 亲跑**：`bash loop/qa/t22-live.sh prep` = **11/11**（JD_NEW/REMOTE_INJECT/SHEET/
  SCENE_2D/TPL_module_physics_*×4/SCAFFOLD_FAMILY/**TPL_TILEMAP_PRESENT**/GAME_WARM），
  PREP_EXIT=0（t22t2_qa_live_prep.log/t22t2_qa_live_console_prep.log）。**canonical 日志已
  还原**（`loop/t22-live/console-prep.log`/`editor-warmbuild-prep.log` 先备份后复原，工作树
  与程序态一致）；我的 prep 日志 warn 扫描（`warn|error|panic|unresolved|cannot-apply`）
  **零命中**。fixture 盘面亲验：scene.bsn rect 形态在位、tiles.png 128×64（4×2×32px）、
  remote 注入在位、`jackdaw.toml` 带 `tilemap = false`（D7 实态，§七）。进程清理亲验
  （零残留）。
- 程序归档（t22t2_gates_*）与 QA 复跑逐门同形；程序门禁表含 fast 行（T1-F2 回流项已核销）。

## 三、模板接入同步面复核（五件清单逐项亲读）——全过

1. **modules.json `tilemap` 条目**（`crates/jackdaw_project_build/src/modules.json` 亲读）：
   opt-in（无 default 位，fixture `jd new` 实产 `tilemap = false` 行为证）、
   crates=[`jackdaw_tilemap_collision` 无 version]、provides+component_prefixes 齐、
   零 runtime_features。无 version 语义源码亲证（`modules.rs` `ModuleCrate::requirement`
   doc：「Absent for a jackdaw crate, which follows the project's jackdaw_runtime」——
   与报告「dep 同源」声明一致）。
2. **三占位符落位**（`lib.rs.template` 亲读）：`{{module_tilemap_doc}}`（头文档
   `# Tilemap & 2D collision` 节，紧跟 physics doc 位）/`{{module_tilemap_collision}}`
   （`GamePlugin::build` 内，physics statements 后，emitted=8 空格缩进
   `app.add_plugins(TilemapProbePlugin);`）/`{{module_tilemap_player}}`（文尾
   physics_demo 后）。发射函数三件全部 `!modules.contains("tilemap") → String::new()`
   ——非 default 模块的散文与代码同撤，无模块零残留**双机判护栏**：新 teaches 测试
   无模块支四 token 断言+既有默认脚手架测试 `!lib.contains("{{")`（tilemap 非 default，
   残留即红）。
3. **scaffold 接线**（`substitute_placeholders` 亲读）：三 emitter 接线在 physics 家族
   之后逐一 `replace_line`，形态同源。
4. **teaches 测试亲跑绿**（libtests 3047 内含，PASS 行在案）：
   `new_game_project_teaches_the_tilemap_collision_pattern`——带模块：manifest 内核
   crate 行断言+**锚断言实测 14 条**（报告写 13，见 F3）+`!lib.contains("{{")` 零残留；
   无模块：四 token（内核 crate 名/TilemapProbePlugin/struct PlayerProbe/头文档节）
   零残留。教学段内容亲读=LevelGrid（order 高者胜/层偏移折叠/越界跳三语义源码亲证）+
   PlayerProbe（内核 Probe+色块）+TriggerCensus（`#[reflect(Resource)]`，BRP 可读）+
   四系统链 chain+Camera2d(order=1)+flow/pause 门——确为 T1 `player_probe_app` 样张转正。
5. **守卫翻转亲跑**：`t22-live.sh` TPL 腿亲读（`TPL_TILEMAP_ABSENT`→
   `TPL_TILEMAP_PRESENT`，断言=模板占位符**且** scaffold 双函数
   `fn module_tilemap_collision`/`fn module_tilemap_player` 存在）+prep 亲跑
   TPL_TILEMAP_PRESENT_PASS（§二）——T1 交接必做件核销。

## 四、e2e 编译测试核（T1 QA 要求的新门）——全过

- 测试源码亲读（`tests/scaffold_e2e.rs::scaffold_tilemap_module_builds_the_probe`）：
  真脚手架（`scaffold_new_project_with` + tilemap module）→`check_new_project`
  （fresh 工程解析断言）→依赖缓存复用→`build_project_binary` 真构建→
  **schema 含 `::TriggerCensus` 断言**——schema 只能出自真跑过
  `TilemapProbePlugin::build`（`register_type::<TriggerCensus>`）的二进制，
  「插件真跑」机判成立。
- **亲跑复现**：125.894s build PASS（§二），与程序归档 125.654s 同形——emitted
  ~200 行教学段（LevelGrid/Probe/move_probe/TriggerCensus + jackdaw_runtime
  三件 re-export + 内核 crate 依赖）**真实编译**非纸面锚。
- **红线复核**：`grep -r bevy_ecs_tilemap` 全树——**manifests/源码/Cargo.lock/模板/
  scaffold 零命中**，唯 loop/plans、loop/progress.md、loop/reports（T1 探针文档）提及；
  fork 零触碰（零 diff）。A 路不进主线红线维持。

## 五、六项逐项复核（源码级）——全过

1. **组件族三件**（`crates/jackdaw_scene_types/src/lib.rs` 亲读）：`TilemapLayer`
   （cell_size/columns/rows/image/order+`tile_rect`/`cell_center`/`world_to_cell` 三换算，
   floor 除法负坐标正确有单测）+`TileGridCell`（cell:IVec2/tile:u32，
   `@EditorHidden`=决策 5-A）+`TileCollisionMode`（Passable#[default]/Solid/Trigger，
   doc 注明上游 setup.rs:77-82 语义源，决策 3-B）；`register_type` 三件链尾在册；
   `jackdaw_runtime` re-export 三件在册（模板 use 直证）。tiles 落点 scene_types 的
   save-filter 理由（`jackdaw::` 跳过）与 CanvasGuides 同款 doc 自洽。
   微注：报告「三件 @EditorCategory」实为两件（TileGridCell 是 @EditorHidden，
   决策 5-A 正确形态），措辞级。
2. **调色板面板**（`src/tilemap_palette.rs` 亲读）：sheet 整图 ImageNode+内部网格线
   （列×行白线）+活动 tile 高亮框（y 上/y 下翻转换算有单测）+brush 四钮
   （Paint/Erase/Fill/Flood，活动色 `sync_brush_button_look`）+tile 读数+每层一行
   （Eye 显隐/P·S·T 循环徽/名点=激活）+「+ Add Layer」全在；指纹重建
   （PaneState 五元组）+exclusive system 直写 world；riding 前置 2D 面板 area
   （terrain palette 同型先例在 `viewport.rs` 亲证）；工具随行
   （`sync_palette_panel` Tilemap 才挂/否则撤）。
3. **10 operator 全算子化+一笔=一条 undo**（`src/tilemap.rs` 亲读+亲跑）：十个
   `#[operator]`（layer.add/active/mode/visible、tile.select、brush、paint、erase、
   fill、fill.flood）与报告表逐行一致；**批命令** `PaintTiles`/`EraseTiles` 自定义
   EditorCommand，execute 从头重建 created/repainted（redo 重派生不回放陈旧 id），
   undo 走 `live_entity`→`despawn_scene_entity`（AST 同步）；**stage 亲跑**
   `call_ok` 对 paint/erase/fill/flood/layer.mode/layer.visible 六 op 逐笔断言
   `scene_pushes()==before+1`（T03 家族纪律机判，71/71 内含）；会话态三 op
   （layer.active/tile.select/brush）+stroke 均 `allows_undo=false`+`remote_hidden`
   ——「一笔画不进史」分类正确。fill 双模亲跑：矩形（对角序无关，cells_in_rect
   纯函数单测）+flood（连通域/边界停/越界种子空/无可写格拒，三态单测）。
   repaint 占格重绘+undo 恢复旧 tile 亲跑绿。
4. **图层父子分组+面板行双轨+mode/visible undo**：层=Scene2dRoot 子实体分组
   （stage 测试断言父链）+面板行（Eye/徽/名）双轨；`SetTileCollisionMode`/
   `SetLayerVisible` 单条命令 undo/redo 亲跑（Trigger↔Passable、Hidden↔Inherited），
   且两命令 undo 同步 AST patch（`sync_mode_doc`/`sync_visibility_doc`）。
5. **画布手势 stroke 模态**（`tilemap.stroke` 亲读）：绑 `MouseButton::Left+Press`
   deferred（measure 同款）；availability=Tilemap 工具+2D Edit 面板+活动层在；
   拖拽访格累积（HashSet 去重）/FillRect 记对角/Flood 按下即派发即收；
   **release 派发对应批量算子**（模态自身不入史=一笔一条的结构保证）；右键/Esc
   取消；ToolStatus 提示条；画布让位两处亲读（`on_sprite_press`/`box_select_
   pending_trigger` Tilemap 下 stand down）。cell 换算复用 `stage_world_point`
   （T21 已证机器，D1 前提成立）。
6. **TM7**：`draw_trigger_overlays`（PostUpdate/JackdawDrawSystems）——Tilemap 工具
   激活时对 Trigger 层每 tile `rect_2d` 半透明青环（srgba(0,0.9,0.9,0.55)，
   T10 Sensor 同型），z=层 order。像素证据留 T3（D2 口径）。

## 六、三处门禁抓出的真缺陷：修复面亲证 + 绿侧亲跑；红侧归档质量记档（F1/F2）

| # | 缺陷 | 修复面（源码亲证） | 绿侧（QA 亲跑） | 红侧归档实态 |
|---|---|---|---|---|
| ① | palette 观察者无目标过滤（PointerPress 冒泡→每次画布点击误派 `tilemap.layer.add`） | **六个 observer 全部按 event.entity 的 marker 查询过滤**（on_sheet_press/on_layer_row_press/on_mode_badge_press/on_eye_press/on_add_layer_press 带显式冒泡注释/on_brush_button_press） | targeted 71/71（sprite_gizmo 31+world_guides 2 全绿） | `t22t2_targeted_red.log` 仅 10 行尾段：一个可见失败测（world_guides「the UI guide is not the world's」——机制自洽：layer.add 误派发污染选择态）+**`TARGETED_EXIT=0` 与「error: test run failed」并存（红跑 exit 捕获 bug）**；「sprite_gizmo 四测」计数不可回溯（F2） |
| ② | `DEV_PATH_DEPS` 四件漏列第五件（checkout 脚手架把内核写成 git+rev→`cargo metadata` 解析失败） | `dev_checkout.rs` 清单 `[&str; 5]` 含 `jackdaw_tilemap_collision` 亲读在案 | e2e 亲跑 PASS（§四） | **`DependenciesUnresolved` 全归档树零命中**——报告 §六/§八「首轮红在案」与盘面不符（疑被绿跑覆盖，F1） |
| ③ | repaint 只改活组件、AST patch 不同步（保存写 patch→读回陈旧 tile） | `repaint_tile` 对 **Sprite.rect 与 TileGridCell.tile 双面** `sync_component_to_ast` 亲读在案；save-写-AST 机制源码亲证（`save_scene_inner`→`emit_bsn_scene_authored` 走 `doc_entities_in_order(ast)` patch 面，非活组件反序列化）；**永久回归格在案**：`the_tilemap_scene_saves_and_reopens` 把「重绘后保存读回 5」机判进 save/reopen 往返 | 该测 71/71 内含 PASS | `t22t2_repaint_sync_redgreen.log` 红侧为一行散文（「RED: reopened (0,0) reads tile 2 (stale patch) instead of 5 — see session transcript」），真红跑输出未落盘（F1） |

**质量判定**：三缺陷均真实（机制源码级+绿侧机判+回归护栏），裁决不受影响；但 §八
「红绿双证在案三处」**高估了盘面**——三件红侧无一达到 T1 的红证标准（红跑完整日志
先于绿证落盘）。修复建议：报告 §八 索引更正+T3 起恢复「先红后绿、红必落盘」纪律。

**基线拆账亲核（D8）**：我的 libtests PASS 行逐一点验——editor lib 新增恰 9
（tilemap::tests 7+tilemap_palette::tests 2）+scaffold teaches 恰 1+内核 8 未动；
3037+10=3047 算术成立，fast lib 段同 3047 互证。**采纳基线 3047**。

## 七、偏差 D1-D8 裁定建议（QA 意见）

| # | 偏差 | QA 裁定建议 |
|---|---|---|
| D1 | 手势/面板/TM7 零真机证据（headless 在案） | **同意记档**。方案 §四-T2 验收标准原文即「M1-M6 的 H 侧证据在案（operator 直调全链 headless 绿）」，L 腿属 T3（§三「T3 集中跑」）；T2 口径成立，T3 硬项不滑（§八交接） |
| D2 | 调色板/TM7 零像素证据 | **同意记档，并入 D2 硬约束链**：T1 的 rect 像素半边+本轮 palette PX+TM7 色罩 PX 三件 PX 全部落 T3 L2/L4/L7，不得滑出 T3 |
| D3 | 擦除=brush 模式切换（面板钮+`tilemap.brush`），非决策 7 括注的「修饰键（或右键）」 | **同意记档**：擦除功能面完整（operator+手势+undo 全链亲证），偏差只在供型；右键=stroke 取消是全模态一致惯例（measure 同款），理由成立；T3 L3 真机验观感，若别扭补修饰键属两处小票，不回改 T2 |
| D4 | dispatch 词「TilemapBundle 族」vs route C 无 bundle | **同意记档**：派单词汇面非实现缺口；tile 生成形态被 TM5 守卫+stage 活体断言双覆盖 |
| D5 | 图层面板行并入调色板面板（非独立图层面板） | **同意记档**：「operator 直达+面板双轨」两轨都在（§五-4）；决策 5 允许最小面，层分组+面板行两层齐做，超而非欠 |
| D6 | 门禁链首轮三红修后覆盖归档 | **同意结案（门禁语义）**：门禁类日志按契约覆盖归档合规；但红绿证据类日志**不得覆盖**——三件红侧实态见 §六（F1），处置并入 F1 |
| D7 | fixture=默认模块（无 tilemap module 行） | **同意记档+措辞更正**：亲验实态=fixture `jackdaw.toml` **有** `tilemap = false` 行（`jd new` 按 catalog 全键写入），且 fixture 游戏 Cargo.toml 零内核 crate（亲验）——实质（模块未启、模板段缺席、L8/L9 需翻转）与处置完全成立；T3 前置硬项=翻转 `tilemap = true`+re-lock+暖编 |
| D8 | libtests 3047 vs dispatch「3037+新增」 | **认可并采纳**：3047=3037+editor 9+scaffold 1（§六拆账亲核）；**基线自此 3047**（fast/targeted 同源口径） |

## 八、QA 发现清单与放行建议

**发现（均记档级，无阻断）：**

| # | 发现 | 建议 |
|---|---|---|
| F1 | 三处红绿的**红侧归档无一达证**：①红日志 10 行尾段且 `TARGETED_EXIT=0` 与失败并存（exit 捕获 bug）；②`DependenciesUnresolved` 归档树零命中，报告「首轮红在案」不实；③repaint 红侧=散文行引用未归档 transcript | **本轮不阻断**（修复面/绿侧/回归护栏三重成立，§六）；报告 §八 索引需更正；T3 起恢复 T1「先红后绿、红证完整落盘」纪律——红绿证据类日志禁覆盖 |
| F2 | 「sprite_gizmo 四测假红」计数归档不可回溯（红日志仅见 world_guides 一测） | 记档；缺陷真实性不受影响（冒泡机制+六 observer 过滤亲证）；TM9 记档建议成立（§九-4） |
| F3 | teaches 锚实测 **14 条**（报告写 13） | 记档；锚集只多不少，测试绿在案 |
| F4 | D7 措辞（fixture 有 `tilemap = false` 行，非「无行」） | 记档；实质与处置不变（§七-D7） |
| F5 | 调色板 chrome 观察者中仅 on_sheet_press 门 Primary 键，层行/模式徽/Eye/brush 钮对任意键 press 均派发 | 观察级：右/中键点面板 chrome 会误派发；T3 真机 L2/L4 验观感，若踩再收窄（一处小改） |
| F6 | 全格已持同 tile 的 paint 笔画仍压入一条空 undo（created/repainted 皆空） | 观察级：无正确性影响（脏指纹不变），UX nit 记档 T3 |

**裁决 PASS，放行 T22-T3（真机矩阵轮+终验+文档），交接清单：**

1. **D7 前置硬项（先于 L8/L9）**：fixture `jackdaw.toml` 翻 `tilemap = true`→resolve→
   暖编重跑；游戏侧 `TilemapProbePlugin` 随模块行真实进包（teaches/e2e 已证形态）。
2. **像素证据三件不滑出 T3**：rect 裁剪画布像素≠整图（T1-D2+M14，L2/L7）、
   palette PX（L2）、TM7 色罩 PX（L4）。
3. **L2 拖拽腿自守**照方案风险表：100% 缩放（A10）+A7 五招+判红前相邻两拍；笔画
   断言以 BRP 计数为主。
4. **红绿纪律**：红证先落盘再修（F1）；F5/F6 真机验后再定是否小票。
5. **TM9 记档建议**（全局 PointerPress 观察者必须按 event.entity marker 过滤）素材
   在 `t22t2_targeted_red.log`+本报告 §六，buglist 处置归 T3 步骤。
6. **门禁基线 3047**；程序门禁表已含 fast 行（T1-F2 核销）。
7. **红线维持**：`bevy_ecs_tilemap` 不进主线（grep 即红）；probe-a 分支保留勿删。

## 九、证据索引

- QA 门禁：`loop/reports/t22t2_qa_gates_{fmt,clippy_ws,clippy_phys,libtests,
  libtests_cargo,kernel,targeted,e2e,fast}.log`（九门全 EXIT=0+全文扫描）
- QA live：`loop/reports/t22t2_qa_live_prep.log` + `t22t2_qa_live_console_prep.log`
  （canonical `loop/t22-live/console-prep.log`/`editor-warmbuild-prep.log` 已还原保全）
- 程序归档（复核对象）：`loop/reports/t22t2_gates_*`、`t22t2_targeted_red.log`、
  `t22t2_scaffold_tilemap_e2e.log`、`t22t2_repaint_sync_redgreen.log`、`t22t2_live_prep.log`
- 源码复核面：`crates/jackdaw_scene_types/src/lib.rs`、`crates/jackdaw_runtime/src/lib.rs`、
  `src/tilemap.rs`、`src/tilemap_palette.rs`、`src/{active_tool,tool_ops,gizmos,sprite_gizmo,
  sprite_stage,viewport_select,status_bar,modal_transform,numeric_transform,layout,
  creation_taxonomy,core_extension,lib}.rs`、`crates/jackdaw_scaffold/src/{lib,dev_checkout}.rs`、
  `crates/jackdaw_scaffold/templates/game/src/lib.rs.template`、
  `crates/jackdaw_project_build/src/{modules.json,modules.rs}`、`src/scene_io/save.rs`、
  `src/commands.rs`、`tests/stage/tilemap_ops.rs`、`tests/scaffold_e2e.rs`、`loop/qa/t22-live.sh`
