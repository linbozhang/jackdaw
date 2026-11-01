# T22-T2 程序报告：建设轮（模板接入+调色板+绘制/擦除/填充）

> 分支 `loop/t22-tilemap`（自 main f24e86cc fast-forward 同步后直接续做）。任务书=
> `loop/plans/t22-tilemap.md` §四-T2 + dispatch（T1 QA 回流四件：TPL 翻转/门禁表
> fast 行/libtests 基线 3037/D2 硬约束知悉）。主控裁定沿用：决策 1=C 路（Sprite.rect
> 自建族）、决策 2=自建 tile-grid 碰撞内核、决策 4=A（整图+网格叠加）、决策 5=A
> （生成面隐藏）、决策 6=A（模板 module 教学段）、决策 7=A（填充双模）。归档=
> `loop/reports/t22t2_*`。报告日期 2026-11-02。RUST_BACKTRACE 全程未设；
> 门链/live 脚本分窗串行（T12-T3 纪律）。

## 一、结论（定案门）

**T2 建设面六件全部落地且 headless 全绿：组件族三件、Tilemap 工具（T 键）、
调色板面板、绘制/擦除/填充/图层算子族（一笔=一条 EditorCommand）、TM7 色罩、
模板 module 接入（`{{module_tilemap_collision}}` 族落地+守卫翻转+真机编译验证）。**
门禁七门全绿（libtests **3047/3047**=T1 基线 3037+10）；prep 腿 11/11 含翻转后的
`TPL_TILEMAP_PRESENT`；新增 tilemap module 的脚手架工程**真实编译过**（e2e 125s
build+schema 断言），emitted 模板代码非纸面锚。红绿双证在案三处（§六）。

## 二、组件族（方案 §四-T2-1）

`crates/jackdaw_scene_types/src/lib.rs` 三件（`register_type` 链尾，`@EditorCategory`
picker 分组 "Tilemap"）：

| 组件 | 形态 | 语义 |
|---|---|---|
| `TilemapLayer` | `cell_size: Vec2, columns/rows: u32, image: Handle<Image>, order: i32` | 层父实体；sheet 切割参数+层序；`tile_rect/cell_center/world_to_cell` 三个换算方法（floor 除法，y 上） |
| `TileGridCell` | `cell: IVec2, tile: u32` | tile 子实体标记；带 `@EditorHidden`（决策 5-A：重绘不拾取） |
| `TileCollisionMode` | `enum { Passable, Solid, Trigger }` | per-layer 三态；逐字对齐内核 `CollisionMode`（nightly setup.rs:77-82 语义，决策 3-B） |

`jackdaw_runtime` re-export 三件（game 侧模块经 `jackdaw_runtime::{...}` 引用）；
`SceneTypesPlugin` 注册→bsn 往返/Inspector 门全开。

**tile 实体形态**（`src/tilemap.rs::spawn_tile`，route C/TM5 守卫覆盖）：`Sprite{image:
sheet 柄, rect: 格矩形, custom_size: cell}`+`Anchor::CENTER`+`TileGridCell`+
`EditorHidden`+`Locked`+`ChildOf(layer)`+AST 注册。z=层 order。

## 三、Tilemap 工具（方案 §四-T2 前置）

- `ActiveTool::Tilemap` 第五变体+`is_manipulator()` 助手——Select/Tilemap 不驱动 gizmo；
  全仓 7 处 match/守卫同步（gizmos×4/sprite_gizmo/status_bar×2/modal_transform/
  numeric_transform×2）。**Q/W/E/R 不动，T=tilemap**（方案小定案）。
- `tool.tilemap` operator+`KeyT` 键位（tool_ops 同型第五例）；工具栏第六按钮
  （`Icon::Grid3x3`，`is_main_toolbar_op`+高亮 match 同步）。
- 画布让位：`on_sprite_press`（sprite 拾取）与 `box_select_pending_trigger`（框选）
  在 Tilemap 工具下 stand down——左键是笔画，不是选择。

## 四、算子族（方案 §四-T2-3/4；T03 家族纪律）

`src/tilemap.rs`（新文件，~800 行含单测）十个 operator 全部 operator 化：

| operator | 语义 | undo |
|---|---|---|
| `tilemap.layer.add` | 建 TilemapLayer 父实体（SpawnEntity 命令，选中+active） | 1 条 |
| `tilemap.layer.active` | palette.active_layer 切换 | 会话态，不入史 |
| `tilemap.layer.mode` | 三态切换（SetTileCollisionMode 命令） | 1 条 |
| `tilemap.layer.visible` | 显隐（SetLayerVisible 命令） | 1 条 |
| `tilemap.tile.select` | 活动 tile（面板点击写这里） | 会话态 |
| `tilemap.brush` | paint/erase/fill/flood 切换 | 会话态 |
| `tilemap.paint` | cells=`"x,y;x,y"`→批量 ensure（新 spawn/占用 repaint） | **一笔=1 条** |
| `tilemap.erase` | 批量 despawn（记录 cell+tile） | **一笔=1 条** |
| `tilemap.fill` | 对角矩形（cells_in_rect 纯函数） | 1 条 |
| `tilemap.fill.flood` | 连通同 tile 区域（flood_cells 纯函数，空格=可填充域） | 1 条 |

- **批命令**：`PaintTiles`/`EraseTiles` 自定义 `EditorCommand`——execute 从头重建
  记录（created/repainted/erased），redo 重派生不回放陈旧 entity id；undo 经
  `despawn_scene_entity`/确定性 respawn 保 AST 同步。
- **文档同步**：repaint/mode/visible 三处显式 `sync_component_to_ast`——**红绿证明
  在案**（`t22t2_repaint_sync_redgreen.log`）：去掉同步后重绘格保存读回陈旧 tile 2
  （红），恢复后读回 5（绿）。save 写的是 AST patch 不是活组件。
- 边界语义：越界格整笔拒（`Cancelled`+warn——游戏侧 grid 就是 sheet 切割尺寸）；
  flood 种子越界=空；flood 无可写格=拒。
- 单测 7 件（cell 解析/负坐标/矩形行主序/flood 三态/tile_rect 切割）+palette 2 件。

## 五、调色板面板+画布手势+TM7（方案 §四-T2-2/5，`src/tilemap_palette.rs`）

- **面板**（决策 4-A）：`TilemapPalettePanel` 绝对定位浮于前置 2D 面板 area 右上
  （terrain palette 同型）；内容按指纹重建（层列表/活动层/活动 tile/brush/sheet
  参数），exclusive system 直接写 world（`Commands`+`&mut World` 冲突实证 B0008）。
  内容：sheet 整图 ImageNode+网格线+活动 tile 高亮框+brush 四按钮（Paint/Erase/
  Fill/Flood 文本钮，活动色区分）+tile 读数+每层一行（Eye 显隐/模式字母 P·S·T
  循环/名字=激活）+「+ Add Layer」。点击=派发算子（观察者只认带自己标记的
  entity——**PointerPress 冒泡教训**：无过滤的 handler 在每次画布点击都触发，
  门禁抓出后全数加 marker 查询过滤）。
- **画布手势**：`tilemap.stroke` 模态 operator，绑 `MouseButton::Left+Press`
  （measure 同款 deferred 绑定）；availability=Tilemap 工具+2D Edit 面板+活动层在。
  拖拽访格累积（FillRect 记对角/Flood 按下即派发即收），release 派发对应批量
  算子——**一笔=一条 undo**，右键/Esc 取消（每个指针模态的惯例）。ToolStatus 提示条。
- **TM7 色罩**：`draw_trigger_overlays`（PostUpdate/JackdawDrawSystems）——工具激活时
  对 Trigger 层每 tile 画半透明青环（T10 Sensor 同型）。

## 六、模板接入（dispatch 决策 6 语义；四件同步面清单自查）

1. **module 目录条目**（`modules.json`）：`tilemap`（opt-in，default=false；
   crates=[jackdaw_tilemap_collision 无 version→jackdaw_dep_requirement 同源]；
   provides+component_prefixes）。零 runtime_features。
2. **占位符族**（`lib.rs.template` 三点+`substitute_placeholders` 三函数）：
   - `{{module_tilemap_doc}}`——模板头 `# Tilemap & 2D collision` 节（模块开才有；
     physics 的「无模块 prose 留、code 撤」形态在这里收紧为头文档一并撤——tilemap
     非 default，默认游戏不该带未启用模块的散文）；
   - `{{module_tilemap_collision}}`——`GamePlugin::build` 内
     `app.add_plugins(TilemapProbePlugin)`；
   - `{{module_tilemap_player}}`——文尾 ~200 行教学段：`LevelGrid`（场景
     TilemapLayer+TileGridCell→内核 TileGrid，order 高者胜、层偏移折叠、越界跳）、
     `PlayerProbe`（内核 Probe+色块 Sprite）、`TriggerCensus`（Reflect 资源，
     BRP 可读）、四系统链 `collect_level_grid →(apply_walk_input, resolve_probe,
     census_triggers).chain() → sync_probe_sprite`、Camera2d(order=1)、
     flow/pause 门——**即 T1 `player_probe_app.rs` 样张的模板转正**。
3. **嵌入断言**：scaffold teaches 测试 `new_game_project_teaches_the_tilemap_
   collision_pattern`（带模块：manifest 内核 crate 行+13 锚+占位符零残留；无模块：
   四 token 零残留）；**e2e 编译测试** `scaffold_tilemap_module_builds_the_probe`
   （真脚手架→lock 解析→二进制构建 125s→schema 含 `TriggerCensus`——emitted 代码
   编译+插件真跑的证据，非纸面锚）。
4. **守卫翻转**：`t22-live.sh` `TPL_TILEMAP_ABSENT`→`TPL_TILEMAP_PRESENT`（模板
   占位符+scaffold 双函数存在断言）。prep 实跑 PASS。
5. **模板头文档**：=2 的 doc 节（同步面第 4 件）。

**模板接线真缺陷（e2e 抓出，已修）**：`dev_checkout::DEV_PATH_DEPS` 四件清单漏掉
新的 jackdaw crate——checkout 运行时脚手架的工程把内核写成 git+rev，`cargo
metadata` 解析失败（`t22t2_scaffold_tilemap_e2e.log` 首轮红）。加第五件后绿。
**红线复核**：`grep bevy_ecs_tilemap` 全树零命中（A 路不进主线）；fork 零触碰。

## 七、门禁结果（终树；日志全文 `loop/reports/t22t2_*`，exit 仅辅助）

| 门 | 命令 | 结果 | 证据 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | ✅ EXIT=0（fmt 修正后终树） | t22t2_gates_final.log §fmt |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | ✅ EXIT=0 | t22t2_gates_final.log §clippy / t22t2_gates_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | ✅ EXIT=0 | t22t2_gates_clippy_phys.log |
| libtests | `cargo nextest run --profile ci --workspace --lib` | ✅ **3047/3047**（=T1 基线 3037+editor lib 9+scaffold teaches 1） | t22t2_gates_libtests.log / final §libtests |
| 内核 crate | `cargo nextest run --profile ci -p jackdaw_tilemap_collision` | ✅ 11/11（未触碰） | t22t2_gates_kernel.log |
| 受影响域 | `cargo nextest run --profile ci -p jackdaw --test stage 'sprite_' 'tilemap'` | ✅ **71/71**（sprite 四族 63+tilemap_guard 2+tilemap_ops 6） | t22t2_gates_targeted.log |
| fast | `cargo xtask fast` | ✅ EXIT=0，lib 段 3047/3047 | t22t2_gates_fast.log / final §fast |
| e2e 编译 | `cargo nextest run -p jackdaw --test scaffold_e2e scaffold_tilemap` | ✅ 125s build+schema 断言 | t22t2_scaffold_tilemap_e2e.log |
| live prep | `bash loop/qa/t22-live.sh prep` | ✅ **11/11**，`TPL_TILEMAP_PRESENT` PASS | t22t2_live_prep.log + loop/t22-live/console-prep.log |

> 门禁纪律注记：首轮三红全部修后覆盖归档——①clippy_ws（`semicolon_if_nothing_
> returned` 一处）；②**targeted 红抓出真缺陷**（`t22t2_targeted_red.log`：palette
> 观察者无目标过滤，PointerPress 冒泡使每次画布点击都派发 `tilemap.layer.add`，
> sprite_gizmo 四测假红）；③e2e 红（DEV_PATH_DEPS 漏列）。终树全绿链=
> `t22t2_gates_final.log`（fmt/clippy_ws/libtests/targeted/fast 五段一档）。

## 八、红绿证据索引

| 红→绿 | 证据 | 缺陷/面 |
|---|---|---|
| targeted 4 测红（每次画布点击误派 layer.add）→ 观察者 marker 过滤 → 71/71 | t22t2_targeted_red.log → t22t2_gates_targeted.log | 指针事件冒泡语义（新工具债教训，TM9 记档建议） |
| e2e `DependenciesUnresolved` 红 → DEV_PATH_DEPS+1 → build PASS | t22t2_scaffold_tilemap_e2e.log（首轮红在案） | 模板 dev-checkout 改写面漏新 crate |
| repaint 无 AST 同步 → 保存读回陈旧 tile（红）→ sync → 读回正确（绿） | t22t2_repaint_sync_redgreen.log | 文档 patch 与活组件双写纪律 |

## 九、方案对照与偏差清单

| # | 偏差 | 处置 |
|---|---|---|
| D1 | 方案估「拖拽手势→world_to_cell→批量 spawn」在 T2 真机验证——本轮手势链 **headless 编译+availability 在案，零真机证据** | 如实记档：T2 验收口径=M1-M6 的 H 侧证据（方案 §四-T2 验收标准），指针域留 T3 L2；stroke 的 cell 换算复用 `stage_world_point`（T21 已证机器） |
| D2 | 调色板面板/TM7 色罩零像素证据 | 同口径：chrome/PX 留 T3 L2/L4（A7 五招自守）；本轮 headless 断言=指纹重建+工具随行+会话资源 |
| D3 | 决策 7「擦除=修饰键或右键」落地为 **brush 模式切换**（面板按钮+算子），非修饰键 | 记档：右键在 stroke 中=取消（每个指针模态的既有惯例，measure 同款）；brush 切换走面板+`tilemap.brush`，T3 真机验观感后如需修饰键再补 |
| D4 | dispatch 词「TilemapBundle 族」——route C 无 bundle 族可落 | 按方案事实五落地为 tile spawn 形态（Sprite.rect+标记组件），TM5 守卫覆盖；如实记档 |
| D5 | 「图层面板行：operator 直达+面板双轨」——面板行=调色板面板内层行（Eye/模式/激活），非独立图层面板 | 记档：最小面（方案决策 5 允许「面板新建或父子分组择一」，两层都做了：层=Scene2dRoot 子实体分组+面板行） |
| D6 | 门禁链首轮三红（clippy lint/targeted 观察者冒泡/e2e 解析） | 修后覆盖归档（§七注记）；冒泡+漏列两处为真缺陷，红绿双证在案（§八） |
| D7 | prep 的 fixture 工程=**默认模块**（无 tilemap module 行） | T3 前置作业：fixture `jackdaw.toml` 需加 `[modules] tilemap = true` 并 resolve（L8/L9 依赖游戏侧内核；无模块=模板段缺席、占位符空，暖编不受影响） |
| D8 | libtests 3047 ≠ dispatch 口径「3037+新增」逐字 | 3047=3037+10，拆账见 §七 libtests 行；基线自此 **3047** |

## 十、给 QA 的注意事项

1. **零 fork 变更、零 buglist/台账/roadmap 触碰**；依赖树 `grep bevy_ecs_tilemap`
   零命中（红线维持）；新 workspace 成员仅 T1 的内核 crate，本轮零 Cargo 结构动作
   （`DEV_PATH_DEPS` 是代码清单非 manifest）。
2. **模板同步面五件**复核入口：modules.json `tilemap` 条目 / lib.rs.template 三占位符
   （head doc+build 段+文尾段）/ scaffold 三函数+substitute_placeholders / teaches
   测试（scaffold lib 93 件内）/ t22-live.sh `TPL_TILEMAP_PRESENT`（prep 亲跑 PASS）。
   **e2e 的 tilemap 编译测试是本轮新增门**——后续模板/lock 变更会连带真实重编
   （target 缓存按 template_revision 键控），预计单次 +2min（依赖缓存共享后）。
3. **libtests 基线自此 3047**（3037+editor 9+scaffold 1）；fast/targeted 同源口径。
4. TM5 守卫两件未动仍在 stage 族；本轮 tile 生成代码（spawn_tile）被其覆盖——
   rect 形态即绿、滑回 atlas 即红的机判面继续有效。
5. **T3 交接硬项**：①fixture 加 `tilemap = true` 模块行（D7）；②L2 画布拖拽腿——
   stroke 的指针密度照方案风险表自守（100% 缩放+五招+相邻两拍）；③palette PX 与
   TM7 色罩 PX 在 L2/L4 补；④面板观察者只认 marker entity（冒泡教训）——真机
   点击面板按钮时若发现误触发别的面，先查气泡链再查算子。
6. `loop/qa/t22-live.sh`：本轮仅动 TPL 预检腿（翻转）；selftest/prep 口径不变，
   12 个 T3 stub 原样。门链与脚本不同窗（T1 D6 教训持续有效）。
7. 建议记档 TM9（指针事件冒泡：全局 PointerPress 观察者必须按 event.entity 的
   marker 过滤，否则每次画布点击全城误触发）——素材在 t22t2_targeted_red.log。
