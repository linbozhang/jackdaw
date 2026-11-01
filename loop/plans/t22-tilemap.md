# T22 Tilemap 与 2D 碰撞关卡 — 实施方案

> 策划产物（2026-10-28 派单、2026-10-28 定稿，基于本地 main **ccca1c9e**（T21 收官 carry 合入，
> P2 段 T21 已闭环）全量只读调研：上游本地标签 `nightly-2026-10-27` 的 `crates/jackdaw_tilemap`
> 全 16 模块+15 commit 可分离性逐个核实；**生态网络查证**：crates.io 版本表与依赖端点
> （bevy_ecs_tilemap 0.20.0 / avian2d 0.8.0）+docs.rs 源码页 Reflect derive 实读；
> fork `/Users/zhanglinbo/workspace/bevy-fork-pinned`（**0.20.0**——派单口径「bevy 0.16」
> 已过时，T10 已钉 0.20.0，fork 根 `Cargo.toml:3`；fork 无任何内建 tilemap）的
> `bevy_sprite/src/sprite.rs`；编辑器 `src/{sprite_ops,sprite_stage,sprite_gizmo,sprite_snap,
> sprite_atlas,canvas_snap,creation_taxonomy,active_tool,tool_ops,viewport_2d,ui_asset_drop,
> scenes/operators,entity_ops,scene_io/{mod,load},definition_assets}`；`crates/jackdaw_scene_types/
> src/lib.rs`（register_type 面）；`crates/jackdaw_scaffold/templates/game/src/lib.rs.template`
> （3D 玩家）；`integrations/physics/jackdaw_avian_integration/src/{lib,triggers}.rs`；
> workspace `Cargo.toml`（patch 段+avian3d 段）；`loop/plans/{roadmap-game-dev.md,t10-physics-triggers.md,
> t21-sprite.md,t20-example-game.md}`；`buglist.md` 全量 tilemap/2D/碰撞域扫描；
> `book/src/user-guide/sprites-2d.md`。**零临时探针**——关键结论（上游内核是孤岛、15 commit
> 零外部文件、bevy_ecs_tilemap 0.20.0 组件族 Reflect 全在、TilemapTexture::Single 自算 UV
> 不经 TextureAtlasLayout、Sprite.rect 是 TextureAtlas 的官方替代语义）全部是静态可复核事实
> 或带出处的网络查证。
> 需求来源：`loop/plans/roadmap-game-dev.md` 第 39 行（P2 段第二项；备注行：若首款游戏是 2D，
> T21/T22 升 P1）。
> **验收原文**（roadmap 第 39 行，逐字核实）：「**Tilemap 与 2D 碰撞关卡：调色板/绘制/擦除/
> 填充/图层/碰撞配置。验收=可制作并运行含地面/墙/触发区的小 2D 关卡；undo/保存/重开。**」
> **任务定性：建设型，约 70/30 偏建设**——与 T21 的「移植为主」相反：**上游 nightly 备好的
> 是一个纯算法内核（`jackdaw_tilemap` 12,492 行 src+1,435 行测试，仅依赖 glam），编辑器
> `src/` 与全部其他 crate 对它零引用——tilemap 的 bevy 组件族、渲染、调色板 UI、绘制/擦除/
> 填充工具、碰撞配置面在上游与编辑器两侧都不存在，是要新建的**。成晶的部分在 **T21 交付面**：
> 2D 场景壳/Sprite 渲染全链/Add 菜单与拖放入口/图集切分/undo 命令机器/bsn 保存往返全部
> 在 main 上真机验证过——T22 的建设是把这些已证机器组织成「tile 网格作者工具」。
> **技术路线决策（本方案最高权重调研，决策 1）三条路线逐项对比后建议 C**：tile=
> `Sprite{image: sheet, rect: cell_rect, custom_size: cell_size}` 的自建轻量组件族——
> fork 文档亲证 `rect` 字段就是「TextureAtlas 的简易一次性替代」（`bevy_sprite/src/
> sprite.rs:36-41`），从而**结构性绕开 A17**（sprite `texture_atlas` 场景柄双柄空间、两侧
> 渲染全图的活票）并最大化复用 T21 已证的渲染/undo/保存/Inspector 四链。缺陷候选按
> **TM 系**编号（Tilemap，避开 buglist R/Y/W/A/N 系与 T01-T21 各任务编号系 U/I/F/C/PF/
> AN/AU/AR/GR/EG/SP），只记不修→主控裁定吸收面。
> 真机口径：**macOS（本机）**，bash+curl+jq 驱动编辑器 BRP 15703 与游戏 BRP 15702
> （t21-live.sh 形态全量复用）；**画布交互腿全在 100% 缩放跑**（A10 绕行）；像素证据=
> `jackdaw/screenshot`+png_pixels_md5/sips（A7 五招自守）；**勿设 RUST_BACKTRACE**；
> 游戏侧数值断言全走 bevy 原生 `world.query`（N12 口径）；PIE 像素证据只走 embedded
> （windowless）流送帧——T21-SP7 已定案 embedded 忠实/windowed 不忠实；warn 形态扫描
> （`tilemap|Tile|UnresolvedTypes|cannot-apply|panicked`）入常备腿。

---

## 0. 架构事实（核实结论，方案的地基）

**总判断：T22 的验收六个词（调色板/绘制/擦除/填充/图层/碰撞配置）在上游与编辑器两侧
全部没有作者通路——建设主体是编辑器工具族+游戏侧碰撞内核；但底层机器（2D 场景、sprite
渲染、图集参数、undo、bsn 保存、Inspector 组件面）在 T21 后全部成晶。三条可行路线中，
自建轻量组件族（路线 C）的发明面最小、A17 传导为零、且与 fork 引擎语义完全同向。**
十八条事实：

- **事实一（生态调研，路线 A 的根基）：bevy_ecs_tilemap 0.20.0 于 2026-10-21 发布，对齐
  fork 同款 bevy 0.20，维护活跃。** crates.io 版本表实查：0.20.0（2026-10-21）/0.19.0
  （2026-07-04）/0.18.x（2026-01-16）——每个 bevy 大版本 3-5 个月内跟发，bevy 0.20 正式版
  2026-10-08 后 13 天即跟发；维护自 0.14 起由 StarArawn 转手 ChristopherBiscardi，总下载
  ~300K，零 yank。**依赖面**（crates.io dependencies 端点实查）：`bevy ^0.20`
  no-default-features，features=`bevy_core_pipeline/bevy_render/bevy_asset/bevy_sprite_render/
  bevy_log`；serde 可选（feature `serde`→dep:serde+bevy/serialize）。workspace
  `[patch.crates-io]` 已把 bevy 全局重定向到 fork 路径（`Cargo.toml:436-448`）——**引入
  该 crate 零 Cargo 结构动作，唯一编译风险=registry 0.20.0 与 fork pinned rev 之间的 API
  漂移（编译探针半日可定案；T10 的 avian3d 0.8 同型先例已走通）**。
- **事实二（路线 A 的正面）：bevy_ecs_tilemap 组件族 Reflect 全在，且渲染不经
  TextureAtlasLayout——A17 天然免疫。** docs.rs 源码页实读 0.20.0：`TilePos/
  TileTextureIndex/TileVisible/TileFlip/TileColor` 全部 `#[derive(Component, Reflect,…)]`
  +`#[reflect(Component)]`+条件 serde derive——Inspector 组件 picker 门（`src/inspector/
  component_picker.rs:123-131` 只门 ReflectComponent）预期直接可编辑、bsn 往返理论可行。
  `TilemapTexture` 三态 `Single(Handle<Image>)`/`Vector`/`TextureContainer`——**Single 变体
  持纯 Image 柄，tile UV 由 crate 按 TilemapTileSize/Spacing 自算**（`verify_ready`/
  `set_images_to_copy_src` 文档自证）→ **不触碰 A17 的 TextureAtlasLayout 柄空间**（纯
  Image 柄的场景解析 T21 M9/M13 已证两侧都通）。渲染=自管 chunked mesh（「chunked approach
  for fast rendering」）+GPU 动画内建。**负面**：per-tile 实体模型（一个 30×16 关卡≈数百
  tile 实体进 AST/hierarchy/bsn）；上游与全网都没有它的任何编辑器 authoring 先例——调色板/
  绘制/擦除/填充/碰撞配置全部要新建（与路线 C 同量），另加画布渲染探针一项（chunk mesh
  提取与 `Viewport2dCamera` 私有相机的相容性）。
- **事实三（路线 B 的根基，本方案最高权重事实之一）：上游 nightly 已备好引擎无关的
  tilemap 算法内核，但它是孤岛。** 标签 `nightly-2026-10-27` 含 `crates/jackdaw_tilemap`：
  **src 12,492 行+tests 1,435 行，唯一依赖 glam**（crate `Cargo.toml:13`；workspace glam
  0.33 在装，根 `Cargo.toml:272`）——编译风险零。16 模块：grid(316 行)/layer(348)/tile(176)/
  path(328)/sidecar(850)/slice(1259)/solver(1866)/setup(1387)/collision_trace(1150)/
  region_text(817)/terrain_find(942)/layout_fit(1213)/stamp(534)/strip(364)/template(380)/
  report(499)。**孤岛实证**：全 workspace 零依赖它（grep 全部 Cargo.toml 唯一命中=它自己的
  package name）；编辑器 `src/` 零 tilemap 引用；`tests/` 零引用。**可分离性实证**：触及
  该 crate 的 15 个 nightly commit 逐个 `git show --name-only` 核实**全部零外部文件**
  （`#636`-`#647` 链，a013261f…c05d2f56）——cherry-pick 即得，无冲突面。lib.rs 自述：
  「Engine-agnostic tilemap kernel: square grid math, sparse 32x32 chunk storage, the
  per-cell value types stored in tile layers and tileset slicing over RGBA8 bytes」。
- **事实四（内核对六验收词的实际供给面）：三态碰撞枚举是现成语义，其余是「超供给」。**
  `CollisionMode{Solid,Trigger,Passable}`（内核 `setup.rs:77-82`）——**与 T22 验收词
  「地面/墙/触发区」一字对一字**（Passable=普通装饰层），移植语义即可。`ChunkedLayer<T>`
  稀疏 32×32 chunk 存储+dirty 追踪（layer.rs:26-33）；`TileRef{index: u16, orientation:
  翻转×2/转置/隐藏位}`（tile.rs）；`.jdtiles` v2 确定性二进制 sidecar 格式（sidecar.rs，
  `encode(decode(b))==b` 文档自证）——多层数据的紧凑落盘形态。**内核没有 flood fill**
  （path.rs 只有 `orthogonal_line`/`apply_path_stroke`/`apply_connect_stroke`——「填充」
  三路线都要自写 ~60 行）。**超供给部分**（terrain autotile 求解器 1866 行/像素级碰撞
  多边形推导 collision_trace 1150 行/layout_fit 1213 行/terrain_find 942 行/region_text
  817 行——ASCII 图→瓦片区域）**与 T22 六验收词零对应**，是未来任务（自动地形/自动碰撞）
  的地基。
- **事实五（路线 C 的根基，本方案最高权重事实之二）：`Sprite.rect` 是 fork 文档亲证的
  TextureAtlas 官方替代语义，且全链在 T21 已证机器上。** fork `bevy_sprite/src/sprite.rs`
  `Sprite` derive `Reflect` 全字段+`rect: Option<Rect>`，doc 原文「**An optional rectangle
  representing the region of the sprite's image to render…This is an easy one-off
  alternative to using a TextureAtlas**」——裁剪渲染是 sprite 核心路径（calculate_bounds_2d
  系），不经 A17 的 atlas 柄空间；`Sprite` 整体 `#[reflect(Component, Default, Debug,
  Clone)]` → rect 随 bsn 直落盘。**每 tile=一个子 Sprite 实体**（image=sheet 柄+rect=格
  矩形+custom_size=格尺寸）时：渲染（编辑器画布 Camera2d+游戏 Camera2d）、undo
  （SpawnEntity 命令）、保存（bsn 子实体）、Inspector（Sprite 字段面）四链全部是 T21
  真机验证过的机器（事实九/十/十二）。
- **事实六：2D 场景壳与画布——T22 的舞台全部现成。** `SceneKind{ThreeD,TwoD,Ui}`
  （`src/scenes/operators.rs:58-66`）；`scene.new kind=2d`→`seed_2d_scene_root`
  （`src/entity_ops.rs:917-922` spawn `Name+Scene2dRoot+Transform+Visibility`）；重开
  kind 识别 `declared_scene_kind`（`src/scene_io/load.rs:345,499`）；画布私有 `Camera2d`
  （`Viewport2dCamera`，`src/viewport_2d.rs:80`）渲染层含 layer 0（`:1664`
  `RenderLayers::from_layers(&[0, viewport_layer])`——2D 世界内容直入画布）；`apply_2d_view`
  （`:550-552`）pan/zoom 随视图。**T21 后画布对 sprite 的拾取/描边/gizmo 全链真机已证**
  （T21 终验 M2/M3 PASS）——tile=Sprite 意味着画布交互子集直接继承。
- **事实七：T21 三入口与 spawn 机器——「放置」语义现成，绘制工具是它的批量形态。**
  Add 菜单 2D 组（`src/creation_taxonomy.rs:246-261`：Sprite/Empty 2D 两行，按
  `OpenScene2dRoot` 出现）；`sprite.add` operator（`src/sprite_ops.rs:73-94`，params
  `path/x/y/parent/name`）；图片拖放（`src/ui_asset_drop.rs:91-100` `drop_image`→Canvas
  落点路由）。spawn 全链（`src/sprite_ops.rs:160-177`）：`SpawnEntity` 命令+
  `CommandHistory.push_executed`（undo 白得）+`register_entity_in_ast`+`select_only`。
  工具切换面：`ActiveTool{Select,Translate,Rotate,Scale}`（`src/active_tool.rs:15-23`），
  Q/W/E/R 键位 operator（`src/tool_ops.rs:15-24`）——**绘制工具加一个变体+键位是同型
  第四例**。
- **事实八：T21 图集机器给「调色板」提供参数面，但 tile 陈列 UI 全网无先例。**
  `sprite.atlas.grid` operator（`src/sprite_atlas.rs:31-87`）：`tile_size/columns/rows/
  padding/offset` → `TextureAtlasLayout::from_grid` → `reflect_to_json` →
  `commit_whole_definition`——**格参数→格矩形表的换算机器现成**（路线 C 复用同一 from_grid
  语义，写进 TilemapLayer 配置而非 Atlas 资产）。`SPRITE_ATLAS_KIND="sprite_atlas"` 已是
  第 7 个 compiled kind（`src/definition_assets.rs:1405,1445`）。**调色板面板**（sheet 格
  陈列+点选）在上游/编辑器/第三方都无先例——本任务最大新建 UI 面（渲染形态三案见决策 4）。
- **事实九：undo/脏标记机器成晶——「笔画=一条命令」是 T03 链的自然形态。**
  `SetTransform`/`SpawnEntity` 等 `EditorCommand` 入 `CommandHistory`（T21 gizmo 拖拽同款，
  `src/sprite_gizmo.rs:1244-1261`）；per-tab 全指纹脏标记（T03）；52 个自推 op 声明+
  `scan-selfpush` 扫描纪律（T03）——**绘制/擦除/填充的每个笔画应聚合为单条命令**
  （一次拖拽=一条 undo），新 op 进 SELF_PUSHING 清单评估。
- **事实十：保存/重开链成晶——bevy 原生组件直落 bsn。** 保存只跳 `jackdaw::` 前缀
  （`src/scene_io/mod.rs:39` 起 skip 表）——`Sprite`/`Transform`/自建标记组件（走
  `SceneTypesPlugin` 的 `register_type` 先例，`crates/jackdaw_scene_types/src/lib.rs:88-120`
  三十个 register_type 在册）全部直落 scene.bsn；2D kind 重开重识别（事实六）。**每 tile
  一个 Sprite 子实体的 bsn 体积**：30×16 关卡约 200-400 tile 实体——T21 M9 的往返机器
  量级内（brush 场景同量级），hierarchy 噪音是真实 UX 代价（TM4，决策 5）。
- **事实十一（碰撞路线调研）：avian2d 0.8.0 已发布且与 avian3d 0.8.0 同节奏，但整装集成
  是 T10 级子项目。** crates.io 实查：avian2d 0.8.0（2026-10-20，与 T10 用的 avian3d 0.8.0
  同日发版，同一维护者 Jondolf，~271K 下载）——patch 统一 bevy 源机制直接复用
  （`Cargo.toml:436-448` 全局生效）。**但**：T10 的整装集成=integrations/physics 双 crate
  +module catalog 条目+编辑器扩展（Physics Tool/gizmo/operator/Inspector chips）——约
  T10 本体 2-3 天的独立子项目，而 T22 验收只要求「地面站得住/墙挡住/触发区触发」三个
  行为。**自建 tile-grid 碰撞内核**（对 Solid 层做 AABB 落地/横移解析+Trigger 层 overlap
  查询，游戏侧 ~150-200 行纯函数+单测）是 tilemap 平台跳跃的正统形态、确定性、headless
  可测——建议为主线（决策 2）。
- **事实十二：触发器在 3D 域的先例完整，2D 域零。** `TriggerPlugin`（`integrations/
  physics/jackdaw_avian_integration/src/triggers.rs:28`，Sensor→TriggerEvents 桥）是 avian
  3D 域；T22 的 2D 触发区=Trigger 层 tile 的 AABB overlap（自建内核内一条查询）。
- **事实十三：游戏模板是 3D 风味——2D 关卡的「可运行」需要 2D 玩家探针体，模板主环不动。**
  模板 `spawn_player` 是 Capsule3d+avian3d（`crates/jackdaw_scaffold/templates/game/src/
  lib.rs.template:1179-1213`，`{{module_physics_player_body}}` 占位符）。Template::TwoD 工程
  的 starter 场景只有 Camera2d+Sprite（T21 事实七）——**2D 关卡跑起来需要游戏侧 2D 玩家
  探针体**（Sprite+速度+tile-grid 碰撞内核调用，~60 行教学段或 fixture 注入代码，决策 6）。
  module 占位符机制（`{{module_physics_*}}` 家族，`crates/jackdaw_scaffold/src/lib.rs:
  2579-2610`）给 2D 碰撞教学段提供了先例形态。
- **事实十四：PIE 2D 形态 T21 已定案——本任务直接复用结论。** embedded（windowless）
  流送帧忠实、windowed 不忠实（FrameCaptureCamera 疑点证实，T21-T2 SP7 判别）——T22 的
  PIE 像素证据只走 embedded 模式，M 格形态照抄 T21 M14 落地版。
- **事实十五：T13/T17/T20 挂点齐备，T22 关卡与示例游戏的关系=延伸格非验收格。**
  flow 面成熟（`game.flow.json` start_scene+`respawn_on_scene_root_change` 场景切换原语，
  T13）——2D 关卡可作为 fixture 工程的 flow 第二场景（延伸格 M13）；运行时存档
  （`SavePlugin<GameSave>` envelope，T17）与「undo/保存/重开」验收词无关（该词=编辑器
  场景保存域，T03/T04 机器）；T20 示例游戏是 3D 模板主环（度表+七元组整环已闭环）——
  「T22 关卡作为示例游戏第二关」受 EG2 边界（关卡道具代码常生）约束，**验收不要求、
  不混入**（延伸评估记 open-challenges）。
- **事实十六：buglist 域内零直接条目，A17 是唯一强关联活票。** 全量扫描：tilemap/tileset
  零命中；terrain 系条目全部是 3D 高度场 `jackdaw_terrain` 域（buglist:44-50 R 系）非
  tilemap；**A17**（buglist:493-498，T21 SP11 立票）——sprite `texture_atlas` 场景柄
  「双柄空间」，编辑器画布与游戏窗口两侧渲染完整全图——**凡走 TextureAtlasLayout 场景柄的
  路线必踩；路线 C 的 rect 字段与路线 A 的 UV 自算都结构性免疫**（TM5 转为守卫测试）。
  W2（:295-297 画布多根口径）邻域知悉。
- **事实十七：工具债四票的 T22 撞面评估。** A7（截图同帧 flake+字段行定位族，buglist:459-464）
  ——调色板面板断言与画布像素证据撞面，五招自守；A9（游戏 BRP 空响应，:502-505）——
  M10 碰撞断言腿自守（settle 重试+小响应体）；A10（PIE 指针缩放布局，:465-467）——
  画布交互腿 100% 缩放；A14（ui_tree 缺 display/hover，:481-483）——调色板面板断言不依赖
  缺面（走 operator/BRP 直达为主）。**绘制/擦除是全 loop 迄今指针驱动密度最高的工具**
  （拖拽过格），若真机腿反复假红，按 MCP 优先原则现场立项小票（决策 8）。
- **事实十八：文档面。** book `sprites-2d.md` 十节已落（T21）；T22 的 book 落点=新章
  `tilemaps-2d.md`（SUMMARY 排 sprites-2d 之后）；无 2D 关卡教学先例——章节内容=
  本方案矩阵的走查形态。

### 验收句逐词定性（矩阵化的前提）

| 验收词 | 定性 | 依据 |
|---|---|---|
| 调色板 | **缺口（TM1 建设主体）** | 格参数换算机器现成（`from_grid` 语义，事实八）；sheet 格陈列+点选 UI 全网无先例（事实八）；三渲染形态待探针（决策 4） |
| 绘制 | **缺口（TM1 建设主体）** | 拖拽→格的坐标机器现成（sprite_stage 指针/ui_scale，事实七）；SpawnEntity 批量=undo 白得（事实九）；工具变体+键位同型第四例（事实七） |
| 擦除 | **缺口（同绘制，despawn 侧）** | 同事实七/九；`despawn_scene_entity` 命令 T03 已修（buglist:19） |
| 填充 | **缺口（三路线都无现成算子）** | 内核 path.rs 只有 stroke 无 flood fill（事实四）；矩形/flood 算子 ~60 行+批量 spawn（决策 7） |
| 图层 | **半成晶** | 实体父子分组+bsn 层级往返机器现成（事实十）；TilemapLayer 标记/活动层/可见性 toggle 面新建 |
| 碰撞配置 | **缺口（TM2 建设主体）** | 三态枚举语义现成（内核 CollisionMode，事实四）；Inspector 枚举机器现成（spawn_enum_field，T09/T16 先例）；per-layer 组件+面板行新建 |
| 验收：可**制作**（含地面/墙/触发区） | **缺口=六词建设面** | 上表合计；工具族+组件族+面板 |
| 验收：可**运行**（地面站得住/墙挡住/触发区触发） | **缺口=TM2+玩家探针体** | avian 是 3D 域（事实十一/十二）；自建 tile-grid 碰撞内核+2D 玩家探针体（事实十三） |
| 验收：**undo** | **成晶机器+tilemap 形态腿** | T03 全指纹+命令机器（事实九）；笔画聚合是唯一新设计 |
| 验收：**保存/重开** | **成晶机器+tilemap 形态腿** | bsn 直落+kind 重识别（事实十/六）；rect 字段随 Sprite 往返（事实五） |

### 全链断点图（sheet→调色板→绘制→可保存→可运行）

```
sheet.png 导入（✓ T18/T21 成晶）
   │
   ▼
调色板面板（✗ TM1 新建）：格参数（from_grid 语义 ✓）→ 格陈列+点选（✗ 决策 4）
   │
   ▼
Tilemap 工具（✗ 新建：ActiveTool 变体+键位）──▶ 画布拖拽 ──▶ world_to_cell（✓ sprite_stage 机器）
   │                                                │
   ├─ 绘制：SpawnEntity 批量（✓ T03 命令机器，笔画=一条）→ tile 子 Sprite{rect}（✓ 事实五）
   ├─ 擦除：despawn 批量（✓ despawn_scene_entity T03 已修）
   └─ 填充：flood/矩形算子（✗ ~60 行）+批量
                │
   图层（半✓）：TilemapLayer 父实体×N（Ground/Wall/Trigger）+活动层/可见性（✗ 面板）
   碰撞配置（✗）：per-layer CollisionMode{Solid,Trigger,Passable}（语义 ✓ 内核移植）
                │
   scene.save（✓ bsn 直落）──▶ 重开（✓ kind 识别+Sprite.rect 往返）
                │
   可运行：游戏侧 tile-grid 碰撞内核（✗ TM2，~150-200 行+单测）
                ├─ 地面=Solid 层 AABB 落地 ──▶ 玩家 y 稳定
                ├─ 墙=Solid 层横移截断 ──▶ 位移受限
                └─ 触发区=Trigger 层 overlap ──▶ 事件/计数
   2D 玩家探针体（✗ ~60 行教学段/fixture 注入，决策 6）
                │
   direct run（✓ 通道）｜PIE（✓ embedded 忠实=T21 SP7 结论）｜导出 staged（✓ T07 通道）
```

---

## 一、缺陷候选（TM 系，只记不修→主控裁定吸收面）

| 编号 | 严重度 | 描述 | 证据 | 处置建议 |
|---|---|---|---|---|
| **TM1** | 🔴 | **tilemap 零授权通路**：调色板/绘制/擦除/填充/图层五词在编辑器无任何落点（上游内核是孤岛、编辑器 src/ 零 tilemap 引用）——「可制作」的全部断点 | 事实三/五/八 | **吸收（建设主体，路线 C）** |
| **TM2** | 🔴 | **2D 碰撞运行时零**：avian 集成是 3D 域（TriggerPlugin/Collider 全 3D），2D 关卡的地面/墙/触发区无任何运行时承载——「可运行」的全部断点 | 事实十一/十二 | **吸收（建设主体，自建 tile-grid 内核，决策 2）** |
| **TM3** | 🟡 | **tile 级预览机器缺**：缩略图管线是整图级（`src/thumbnail.rs`），调色板需要格级陈列——渲染形态三案待探针（决策 4） | 事实八 | **吸收（T2 落地面）** |
| **TM4** | 🟡 | **hierarchy/Inspector 噪音**：每 tile 一个子实体→200+ 行 hierarchy、误选中单格的 gizmo 干扰（T21 sprite gizmo 对子 Sprite 生效） | 事实十 | **吸收（决策 5）**：建议生成 tile 挂 `EditorHidden`+`Locked`（scene_types 现成标记，lib.rs:245,344）+hierarchy 折叠；单格编辑走调色板重绘 |
| **TM5** | 🟡 | **A17 同类柄空间风险**（守卫形态）：若实现误走 `Sprite.texture_atlas`+场景柄，两侧渲染全图（A17 实证形态） | 事实十六 | **转为守卫测试**：矩阵加负向格（tile 画布像素≠整图）+book 注记「tilemap 用 rect 不用 texture_atlas」 |
| **TM6** | ⚪ | **画布无网格线**：绘制时无 cell 边界参照（CanvasGuides 是自由线，非网格吸附面） | 事实六；T21 #656 语义 | **记档**：Tilemap 工具激活时画 cell 网格 overlay 是增强项（可并入 T2 若顺路）；矩阵不断言网格线 |
| **TM7** | ⚪ | **触发区无作者可视化**：Trigger 层 tile 无专属色罩（3D 域 Sensor 有青色 gizmo 先例，`integrations/physics/jackdaw_physics/src/overlays.rs`） | 事实十二 | **吸收（小件）**：Trigger 层 tile 半透明色罩 gizmo（T10 同型） |
| **TM8** | ⚪ | **PIE windowed 模式 2D 流送不忠实**（T21 SP7 既决） | 事实十四 | **直接复用结论**：PIE 像素证据只走 embedded；M11 形态照抄 T21 M14 落地版 |

统计：🔴 2（TM1/TM2，均为验收缺口的建设面）｜🟡 3（TM3-TM5）｜⚪ 3（TM6-TM8）。

### buglist 重叠表（tilemap/2D 碰撞/瓦片域全量扫描）

| 条目 | 一句话 | T22 处置 |
|---|---|---|
| **A17**（buglist:493-498） | sprite texture_atlas 场景柄双柄空间，两侧渲染全图 | **结构性绕开+守卫**：路线 C 用 rect 不用 atlas 柄（事实五）；TM5 守卫测试防实现回滑；修复 A17 归其本票（与 T22 无耦合） |
| **W2**（:295-297） | 画布多根 reference size 口径 | 知悉：真机腿单场景单根运行；撞面按 W2 归因记档不修 |
| **A7**（buglist:459-464） | 截图同帧 flake+字段行定位族 | **不前置，五招自守（决策 8）**；`$PHASE` 日志名写法吸收 |
| **A9**（:502-505） | 游戏 BRP 间歇空响应 | 自守：gbrp settle 重试+小响应体；碰撞断言在游戏侧 bevy 原生读 |
| **A10**（:465-467） | PIE 指针缩放布局 | 绕行：画布交互腿全在 100% 缩放；PIE 真指针仅一腿 |
| **A14**（:481-483） | ui_tree 缺 display/hover | 知悉：调色板面板腿走 operator/BRP 直达，不依赖缺面 |
| **A11**（:469-471） | rebind 只改文档层 | 邻域知悉：tile 的 image 柄 rebind 时 rect 不变（低危）；book 注记 |
| N13 | PIE drain panic | 绕行+记数（T21 口径照抄） |
| 其余 | R/Y 系 terrain 条目均 3D 高度场域；无 sprite/tilemap 直接条目 | 无动作 |

> 如实报告：tilemap 域 buglist 零直接条目——用户从未有可触达该域的通路（TM1 挡着），
> 与 T16 音频/T21 sprite 前置期同构局面。T22 缺陷主体是 TM1-TM8 新发现与建设面里的
> 未知数（T1 探针产物）。

---

## 二、验收矩阵设计

**三铁证×通道=14 格主矩阵+一张关键属性三态表**。断言通道缩写：H=headless（新增
`tests/stage/tilemap_*.rs` 族+tile-grid 碰撞内核单测）、R=真机编辑器 BRP 15703
（operator+`jackdaw/*`+bevy 原生组件查询）、G=游戏 BRP 15702（bevy 原生 `world.*`，
fixture 注入 jackdaw_remote）、PX=像素证据（`jackdaw/screenshot`+png_pixels_md5/sips，
A7 五招自守）、FS=盘面（bsn 文本/SHA）、EXPORT=staged 包。

### 铁证①：可制作（调色板/绘制/擦除/填充/图层/碰撞配置）

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| 调色板 | M1 | sheet.png→TilemapLayer 配置（cell_size/columns/rows）→调色板陈列格→点选 tile→BRP 读活动 tile index；调色板面板 PX | 🔴TM1/TM3 前置；R+PX |
| 绘制 | M2 | Tilemap 工具激活→画布拖拽过格→格实体出现（PX tile 位姿+BRP 数格）；**一笔=一条 undo**；拖出画布边界不炸 | 🔴TM1 前置；R+PX+H |
| 擦除 | M3 | 擦除模式（同工具右键或修饰键，决策 7 附带）拖拽→格消失（PX+计数归零）；擦空格不炸 | 🔴TM1 前置；R+PX+H |
| 填充 | M4 | 矩形填充一框→框内全格（计数+PX）；flood 同色区域一填充→区域满+边界不越（H 算子单测+R 腿） | 🔴TM1 前置；R+PX+H |
| 图层 | M5 | 建 Ground/Wall/Trigger 三层（TilemapLayer 父实体）→活动层切换（绘制落正确层）→可见性 toggle→画布 PX 隐现；层 bsn 往返 | 🟡分组机器现成/面板前置；R+PX+FS |
| 碰撞配置 | M6 | 层模式 Solid/Trigger/Passable 切换→BRP 读回+Inspector 枚举面（组件 picker 可编辑）；TM7 Trigger 色罩 PX | 🔴TM2 前置；R+PX |

### 铁证②：undo/保存/重开

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| undo 链 | M7 | 画 3 笔+擦 1 笔+填 1 框→undo 逐级（笔画为单位）→redo→再编辑；脏标记恒正确（T03 全指纹链 tilemap 形态）；undo 撤到层删除不炸 | 🟡笔画聚合是新设计+✅T03 机器；R+H |
| 保存重开 | M8 | 全编辑后 `scene.save`→重开：格数/格坐标/tile rect/层结构/碰撞模式逐字段 BRP 读回相等+bsn 文本核对+2D kind 重识别 | ✅机器成晶（事实十）+⚠️真机腿；R+FS |
| 横切·Stop | M9 | PIE 播 2D 关卡→Stop→场景文档 SHA 不变（T06 链 tilemap 形态） | ✅T06 成品；R+FS |

### 铁证③：可运行（地面站得住/墙挡住/触发区触发）

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| direct | M10 | `cargo run`（15702）→2D 玩家探针体：落地后 y 稳定（±阈值）=**地面站得住**；横移进墙列位移截断=**墙挡住**；进触发区格→TriggerEvents/计数翻转=**触发区触发**；三断言全 bevy 原生读 | 🔴TM2 前置（碰撞内核+探针体）；G |
| PIE | M11 | `pie.play_current`（embedded）→同 M10 三断言数值轨+流送帧 PX（T21 M14 形态照抄）；N13 记数 | 🟡SP7 结论复用；G+PX |
| 导出 | M12 | `game.export`→staged 异目录启动→同 M10 三断言+包内 sheet 文件清点+manifest 行 | ✅T07 通道；EXPORT+G |
| 延伸·flow | M13 | fixture 工程 flow.json 二场景（菜单→2D 关卡）→切换零残留（T13 链 2D 形态）——**可选延伸格**（事实十五） | ✅T13 通道；G（可选项） |
| 负向守卫 | M14 | TM5 守卫：tile 画布像素≠整图全图（A17 防回滑）；tile bsn 无 texture_atlas 字段断言（H+FS） | 🟡新守卫；H+FS+PX |

### 关键属性×三态表（验收句「可制作并运行…undo/保存/重开」的字面矩阵）

| 关键属性 | 可制作（编辑器） | undo/保存/重开 | 可运行（游戏+导出） |
|---|---|---|---|
| 调色板（sheet→格→点选） | M1 | M8（层配置往返） | M12（sheet 入包） |
| 绘制（tile 落格） | M2 | M7（笔画 undo）/M8（格往返） | M10/M12（渲染+碰撞承载） |
| 擦除 | M3 | M7 | —（负操作） |
| 填充 | M4 | M7/M8 | M10 |
| 图层（Ground/Wall/Trigger） | M5 | M8（层结构往返） | M10（层语义承载） |
| 碰撞配置（Solid/Trigger/Passable） | M6 | M8（模式往返） | M10（三行为） |
| 玩家探针（运行演示体） | —（代码侧） | — | M10/M11/M12 |

**矩阵统计**：🔴 前置 6 格（TM1×M1-M4、TM2×M6 半/M10、TM3×M1）｜🟡 前置 4 格
（M5 面板半/M7 笔画聚合/M11 复用/M14 新守卫）｜✅ 成晶机器 4 格（M8 半/M9/M12 半/
M13）｜⚠️ 真机腿缺口 10 格。T1 探针+碰撞内核原型，T2 落建设面，T3 落判。

---

## 三、真机腿清单（Mac，bash+curl+jq；T3 集中跑）

fixture 工程=launcher `Template::TwoD` 出 `/Users/zhanglinbo/workspace/loop-mac/t22-tilemap`
（T21 同款：建后注入 jackdaw_remote 两行 sed+lock 刷新+暖编；决策 6 若裁模板教学段则
fixture 直接带 2D 玩家探针体）。资产 prep：脚本生成 fixture png（`tiles.png` 4×2 八格
四色 sheet——判 tile 切换的像素红绿正主；纯 stdlib/`sips`）。流程脚本
`loop/qa/t22-live.sh`（t21-live.sh 形态全量复用+像素助手族）。

| # | 腿 | 通道 | 为什么必须真机 |
|---|---|---|---|
| L1 | prep+boot：fixture/注入/暖编/编辑器开 2D 场景+建 TilemapLayer 三层（BRP 断言） | R+FS | 全矩阵前提态 |
| L2 | M1/M2 调色板+绘制：面板点选（ui_click）→画布拖拽三笔→格 PX+计数+一笔一 undo | R+PX | 调色板是 chrome 视觉面；绘制是纯真机指针域 |
| L3 | M3/M4 擦除+填充：擦一笔+矩形填一框+flood 一区→计数+PX | R+PX+H | 批量算子的端到端正主 |
| L4 | M5/M6 图层+碰撞配置：三层切换绘制落点+可见性隐现+模式切换读回+色罩 PX | R+PX | 层语义=编辑器状态机面 |
| L5 | M7 undo 链：7 操作→逐级 undo→redo→脏标记每步断言 | R+H | T03 链 tilemap 形态正主 |
| L6 | M8 保存重开：save→重开→逐字段读回+bsn 文本核对 | R+FS | 验收通用铁证的编辑器半边 |
| L7 | M9 Stop 链+M14 守卫：PIE→Stop→SHA；tile 像素≠全图负向格 | R+FS+PX | T06 链+A17 防回滑 |
| L8 | M10 direct run：游戏侧三行为断言（落地稳定/横移截断/触发翻转）+idle 探针 | G | 「可运行」正主；碰撞只有物理行为能给 |
| L9 | M11 PIE：embedded 模式同 M10 数值+流送帧 PX；N13 记数 | G+PX | PIE=游戏 面（T21 形态） |
| L10 | M12 导出：export_wait→staged 异目录启动→同 L8 断言+包内清单 | EXPORT+G | 「可运行」导出半边 |
| L11 | M13 flow 延伸格（可选）：flow 二场景切换零残留 | G | T13 链 2D 形态 |
| L12 | warn 扫描+存活：全程 `tilemap|Tile|UnresolvedTypes|cannot-apply|panicked` 零意外命中+每腿 BRP 活性 | 脚本常备 | T12-U7 教训 |

---

## 四、分任务拆解（T1/T2/T3）

### T1「探针清源+碰撞内核原型轮」（决策 1/2/4/6/7 定案）

1. **首步探针（半日级，静态+编译级为主）**：①**rect 裁剪双端探针**——手写 2D 场景 bsn
   含 `Sprite{image, rect, custom_size}` 子实体，编辑器画布+direct run 双侧像素核对
   （红绿判据：画布只现选中格色，非整图）；②**决策 1 编译探针**（若主控裁 A 路参评）——
   `bevy_ecs_tilemap = "0.20"` 挂 fork patch `cargo check` 半日定案；③调色板渲染形态
   探针（决策 4 三案的最小样张）。
2. **tile-grid 碰撞内核原型（headless，无编辑器）**：`crates/jackdaw_tilemap`（或编辑器
   crate 内模块，决策 3 联动）——Grid 换算+Solid 层 AABB 落地/横移解析+Trigger 层 overlap
   查询，红绿单测族（落地稳定/穿墙红证→sweep 停绿证/触发翻转）——T11 物理守卫族同款
   形态。**不跑编辑器，纯函数可测**。
3. **决策 6 定案**：2D 玩家探针体形态（fixture 注入 vs 模板 module 教学段）探针=两形态
   各一个最小 demo 跑通 M10 三断言。
4. **quick 四门**（fmt/clippy/单测/stage 族）绿。

**验收标准**：rect 探针双端绿证；碰撞内核单测全绿（含红证演练）；三个决策点定案文档
入 T1 报告。

### T2「授权面建设轮」（TM1/TM2 落地；决策 3/4/5/7 落地面）

1. **组件族**：`TilemapLayer`（父实体标记：cell_size/columns/rows/image 柄/层序）+
   `TileGridCell(IVec2)`（tile 子实体标记）+`TileCollisionMode`（Solid/Trigger/Passable，
   per-layer 组件）——全部 `Reflect`+`SceneTypesPlugin` `register_type` 先例+
   `@EditorCategory` 面板分类（T11 PlayerController 同款）。
2. **调色板面板**（决策 4 落地面）：Tilemap 工具激活时出现——格陈列+点选写活动 tile
   （编辑器会话资源，非组件）+层选择器+模式行。
3. **绘制/擦除/填充 operator 族**：拖拽手势→`world_to_cell`（sprite_stage 坐标机器）→
   SpawnEntity/despawn 批量（**一笔=一条 EditorCommand**，SELF_PUSHING 清单评估）；
   flood/矩形算子单测。
4. **图层面板行**：建层/活动层/可见性/模式四件（operator 直达+面板双轨）。
5. **TM7 色罩 gizmo**：Trigger 层 tile 半透明罩（T10 Sensor 青色同型）。
6. **游戏侧接线**：碰撞内核进模板 module 占位符（`{{module_tilemap_collision}}` 家族，
   事实十三先例形态）或 fixture 注入件（决策 6 结论）；2D 玩家探针体教学段。
7. **门禁**：quick 四门+stage 新族+模板 teaches 锚；fork 零变更（路线 C 不触 fork）。

**验收标准**：M1-M6 的 H 侧证据在案（operator 直调全链 headless 绿）；碰撞内核
单测绿；teaches 计数落袋。

### T3「真机矩阵轮+终验+文档」（验收主任务：M1-M14/L1-L12）

1. fixture+`loop/qa/t22-live.sh`+L1-L12 全腿；A7 五招/A9 settle/A10 百分比缩放/N13
   记数全量入脚本；红证归档 `loop/reports/t22*/`。
2. 缺陷只记不修：新发现按 TM 系续编（TM9 起）；W2 撞面按重叠表口径归因。
3. QA 报告：14 格矩阵逐格判定+关键属性三态表逐行指认+L 腿全证据+用户 30 秒清单草稿
   （开 2D 场景→画几格地面→切 Trigger 层画触发区→存→Play 站得住→触发区翻灯）。
4. book 新章 `book/src/user-guide/tilemaps-2d.md`（SUMMARY 排 sprites-2d 后）：2D 关卡
   建立/调色板/绘制擦除填充/图层与碰撞模式/运行与导出/rect-vs-atlas 注记（TM5+A17
   现状）/规模边界注记（小关卡字面）；`sprites-2d.md`/`game-flow.md`/`physics.md`
   交叉引用。
5. buglist 处置（预期无打钩；A17 不动归本票）、roadmap T22 勾选、台账记行。
6. 终验门：全量门（fast/integration/doctests/docs/scaffold_e2e——日志全文复核）。

---

## 五、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **技术路线（本方案最高权重）** | A=**bevy_ecs_tilemap 0.20.0**：生态活跃（2026-10-21 对齐 bevy 0.20，事实一）+组件族 Reflect 全在（事实二）+渲染 chunk mesh 大图性能好+UV 自算 A17 免疫；代价=外部 crate 钉版（fork 编译漂移探针+升级节奏绑定第三方）+per-tile 实体膨胀同 C+画布渲染探针一项+authoring 全新建（与 C 同量）→**总成本=C+1-1.5 天探针与接线**。B=**上游内核+自建 bevy 壳**：架构正统（引擎无关+薄壳）+sidecar 确定性落盘+上游未来任务地基（15 commit 零冲突可收，事实三）；代价=渲染 sync 系统（生成 sprite SkipSerialization）+自建 Reflect/undo 族+`.jdtiles` loader 双侧新面（A17 同类风险）→**发明面最大，估 +2-3 天**。C=**tile=Sprite.rect 自建轻量族**：fork 文档亲证 rect=官方 atlas 替代（事实五）→渲染/undo/保存/Inspector 四链全白得+A17 结构免疫+零新依赖零 fork 变更；代价=大图无 chunk 优化（「小关卡」字面内不成立问题，规模边界 book 注记）+hierarchy 噪音（决策 5 治理） | **C**；A 的编译探针在 T1 顺跑（半日）留对照证据；B 记 open-challenges（待自动地形任务再评估内核吸收） |
| 2 | **碰撞运行时** | A=**自建 tile-grid 碰撞内核**：~150-200 行纯函数（AABB sweep 对 Solid 层+overlap 查询 Trigger 层）+红绿单测族，确定性、headless 可测、tilemap 正统（平台跳跃不引物理引擎是常态）；代价=自维护（但语义就是「格碰撞」没有泛化需求）。B=**avian2d 0.8 整装集成**：物理正统+T10 先例完整；代价=T10 级子项目（+2-3 天）+编辑器扩展面（工具/gizmo/operator）+模块目录——对「三个行为断言」过重。C=avian3d 2.5D（2D 关卡 z=0 薄盒）：复用 T10 现成栈零新依赖；代价=语义拧巴（Camera2d 画 XY、物理跑 XYZ）+玩家 z 锁定+3D 家具噪音，触发区粒度粗 | **A**；B 记 open-challenges（若后续 2D 游戏需要刚体/关节再立项）；C 否决 |
| 3 | **上游内核吸收（15 commit / 12.5k 行）** | A=**本轮吸收**（cherry-pick 零冲突实证，事实三）：CollisionMode/Grid/TileRef 语义直接引用+未来任务地基；代价=inert 12.5k 行+1,435 行测试进门禁（clippy/test 面扩大，超供给 80% 与 T22 无关）。B=**缓收**：T22 只移植 CollisionMode 三态语义（6 行枚举+doc 注明出处），内核整体留 nightly 标签；代价=将来收时再走一次（15 commit 零冲突可分离性已钉死，无衰减风险）。C=不收 | **B**；路线 C 不依赖内核任何代码（tile-grid 碰撞内核是自写的，语义对齐即可）；内核吸收与 T22 解耦是诚实的边界——「备好」不等于「本任务该收」 |
| 4 | **调色板渲染形态（TM3）** | A=**整图+网格叠加选格**：面板一张 sheet 图+cell 网格 overlay+点击算格——实现最薄（UI Image+坐标换算），零格级资产；代价=无格级视觉隔离（放大后可辨）。B=**格级裁剪小 Image**：启动时按格从 sheet Image 裁出小 Image（内存资产不落盘）→每格独立缩略——观感最好；代价=裁剪管线 ~80 行+内存。C=ImageNode+TextureAtlas：UI 域 atlas 路径；代价=A17 同族柄空间在 UI 域无 T21 验证、探针成本另计 | **A 主选**；B 作为 T3 真机腿观感不合格时的回落（+0.5 天浮动记风险表）；C 否决 |
| 5 | **tile 实体的 hierarchy/Inspector 治理（TM4）** | A=**生成面隐藏**：tile 子实体挂 `EditorHidden`+`Locked`（scene_types 现成标记）+TilemapLayer 单行+计数 badge——hierarchy 干净、gizmo 不误选 tile、Inspector 不见百行；代价=单格不可选中微调（重绘即可，tilemap 语义正确）。B=裸暴露：全部 tile 可见可选——单格可编辑；代价=200+ 行 hierarchy+sprite gizmo 对 tile 误触发+Inspector 噪音。C=折叠组（hierarchy 折叠 UI）——上游无折叠先例，发明面大 | **A**；B 记 open-challenges（单格级编辑是未来增强）；M2 的格断言全走 BRP 计数不依赖 hierarchy 行 |
| 6 | **2D 玩家探针体形态（「可运行」的演示载体）** | A=**模板 module 教学段**（`{{module_tilemap_player}}` 占位符家族）：Template::TwoD 工程+物理 module 勾选即得 2D 玩家——开箱完整、teaches 锚落袋、T12/T13 模板纪律承载；代价=动模板三面（lib.rs.template+scaffold+teaches）+双形态测试。B=fixture 注入代码（T11-T2 摆放链同款）：模板零改动；代价=教学价值零+fixture 特化代码每轮重贴。C=两手（教学段+fixture 不注入直用）：验收最顺；代价=维护两面 | **A**（与事实十三占位符先例同构）；M16 类开箱回归格顺势获得；估 +0.5 天计入 T2 |
| 7 | **填充算子语义** | A=**双模**：矩形填充（拖对角=框内全格）+flood fill（同色/同空连通域）——两算子各 ~60 行，绘制工具语义完整；代价=键位/模式约定。B=仅矩形：实现最薄；代价=「填充」词的 flood 直觉缺半。C=仅 flood：地图编辑器直觉；代价=矩形场景（整层铺地）反手 | **A**；擦除模式=同工具修饰键（或右键），T1 定键位约定 |
| 8 | **A7/A10 工具债前置评估** | A=**不前置，脚本自守**（T21 决策 8 同款）：绘制拖拽腿 100% 缩放+五招+判红前相邻两拍。B=先修 A7/A10：绘制拖拽是全 loop 指针密度最高面，先修有收益；代价=两票均无立项方案 | **A**；真踩（拖拽腿反复假红）→MCP 优先原则现场小票，不整体前置 |

小定案（主控可否决）：缺陷编号 TM1-TM8（新发现自 TM9 续）；真机腿编号 L1-L12；矩阵格
M1-M14；fixture 工程 `/Users/zhanglinbo/workspace/loop-mac/t22-tilemap`（Template::TwoD
+remote 注入）；fixture 资产 `assets/tiles.png`（4×2 八格四色 sheet，脚本生成）；流程
脚本 `loop/qa/t22-live.sh`；报告目录 `loop/reports/t22*/`；分支 `loop/t22-tilemap`；
book 章 `book/src/user-guide/tilemaps-2d.md`；组件族落点 `crates/jackdaw_scene_types`
（TilemapLayer/TileGridCell/TileCollisionMode 三件，register_type 先例）或编辑器
crate+runtime 各面（T1 定）；operator id `tilemap.layer.add`/`tilemap.paint`/
`tilemap.erase`/`tilemap.fill`/`tilemap.layer.mode` 五件起步；工具键位 T（tilemap），
Q/W/E/R 不动；碰撞内核落点=模板 module（`{{module_tilemap_collision}}`）。

---

## 六、风险与回滚

| 风险 | 概率 | 缓解 |
|---|---|---|
| **rect 裁剪在画布或游戏侧渲染异常**（路线 C 唯一引擎假设） | 低-中 | T1 首步双端探针半日定案；红证回落路线 A（编译探针同步跑，回落 +1-1.5 天已在决策 1 表） |
| **绘制拖拽腿假红**（A7 家族+A10 邻域，全 loop 最高指针密度） | 中 | 100% 缩放+五招自守+判红前相邻两拍；笔画断言以 BRP 计数为主、PX 为辅；真踩→现场小票 |
| **hierarchy 噪音伤真机腿**（200+ tile 实体） | 中 | 决策 5-A 生成面隐藏；层断言走 TilemapLayer 单行+BRP 计数；M5 不依赖 tile 行 |
| **undo 笔画聚合自推漏洞**（T03 二层盲区教训） | 中 | 新 op 全进 SELF_PUSHING 清单评估+`scan-selfpush` 全仓扫描+M7 每步脏标记断言 |
| **碰撞内核行为分叉**（落地抖动/穿墙角例） | 中 | 纯函数+红绿单测族先行（T1 原型）；行为断言阈值化（y 稳定 ±）；T11 物理守卫族形态复用 |
| **模板 module 段三面同步漏项**（T20 同步面教训） | 中 | 7 项同步清单先例照抄（模板函数真身/占位符拼接/嵌入断言锚/teaches/guards 副本/doc） |
| **PIE 2D windowed 不忠实干扰 M11** | 确定（既决） | T21 SP7 结论直接复用：embedded-only；N13 记数 |
| **A17 柄空间回滑**（实现者误用 texture_atlas） | 低 | TM5 守卫测试+book 注记；M14 负向格进矩阵 |
| **调色板 UI 观感不合格**（决策 4-A 整图叠加形态） | 中 | T3 真机腿验观感；不合格回落 B 案（+0.5 天） |
| **staged release 冷编长** | 中 | export_wait 预算 1500s（t16 口径）；门前清磁盘（A6 家族）；export 单次（M12） |
| Mac debug 无 RUST_BACKTRACE | 确定 | 全程不设（T11-T3 口径）；panic 形态证据=日志消息签名 |
| 门链与编辑器/游戏同窗互踩 | 中 | T12-T3 纪律：门链单独跑 |
| 回滚 | — | 建设面四块各自独立可 revert：组件族（scene_types 三件）/工具族（editor 新文件系）/碰撞内核（模板 module 占位符，不勾选即不存在）/调色板面板。零 fork 变更（路线 C）、零场景格式破坏（Sprite+标记组件全 bevy 反射原生）、零协议变更、T21 六 PR 零触碰（只在其上加 Tilemap 工具分支路径）。定性表保障：渲染/undo/保存/Inspector 四链全是已证机器的组织，发明面=工具手势+填充算子+碰撞内核三块，各自 headless 可测 |

---

## 七、与 T01-T21 已建设施的衔接

1. **T21（Sprite 域）=T22 的直接地基**：2D 场景壳/三入口/画布拾取 gizmo/undo 机器/
   Sprite Atlas 格参数/PIE 2D 结论全量复用（事实五-八/十四）；`sprites-2d.md` 是
   `tilemaps-2d.md` 的前置阅读；T22 工具族是 sprite 交互栈上的新增分支路径，零改动。
2. **T03（undo/脏标记）=笔画命令的护栏**：SpawnEntity/despawn_scene_entity 命令面+
   per-tab 全指纹+SELF_PUSHING 纪律（事实九）；M7 是 T03 链的 tilemap 形态回归格。
3. **T06/T07/T12（PIE/导出/模板纪律）=「可运行」通道**：M9 Stop 铁证/M12 staged 五点链/
   模板 module 占位符三面同步清单全部复用（事实十三/十五）。
4. **T10/T11（物理与玩家）=碰撞语义对照**：avian 是 3D 域成晶（不动）；决策 2-A 的
   tile-grid 内核语义与 T11 MoveAndSlide 守卫族同型（落地稳定/穿墙红证/触发翻转）；
   `physics.md` book 交叉引用注明 2D/3D 两栈分界。
5. **T13（flow）=M13 延伸格通道**；T17（存档）与本任务无耦合（验收词的「保存/重开」=
   编辑器场景域，事实十五——book 注记防混淆）；T20（示例游戏）主环不动，2D 关卡进
   示例游戏记 open-challenges（EG2 边界内）。
6. **T16/T18/T19（AU/AR/GR 方法论）**：register_type 显式注册纪律（T16 泛型教训）适用于
   组件族三件；A7 五招/T19 像素判据（数值主断言+通道内红绿）直接复用；GR8/SP7 的
   「探针定案→通道分流」方法论=决策 1/4 探针的模板。
7. **上游关系注记**：nightly `jackdaw_tilemap` 内核 15 commit 零冲突可分离性已钉死
   （事实三）——决策 3-B 缓收不衰减；bevy_ecs_tilemap 0.20.0 的存在与 Reflect 面已归档
   （事实一/二），路线 A 回落证据在案。
8. **对 T23-T25 的奠基**：T23（材质覆盖）无关；T24（错误定位）——TM1 落地后 2D 域才有
   tilemap 错误可定位（loader/引用类）；T25（Live 调参）——TileCollisionMode/玩家速度是
   白名单候选域。

---

## 八、耗时预估

| 段 | 预估 | 大头 |
|---|---|---|
| T1 | 1-1.5 天 | rect 双端探针+碰撞内核原型与红绿单测+调色板样张+三决策探针（决策 1-A 编译探针若裁另 +0.5） |
| T2 | 2.5-3.5 天 | 组件族三件+调色板面板+绘制/擦除/填充 operator 族+图层与模式面板+色罩 gizmo+模板 module 段（决策 6-A）+SELF_PUSHING/门禁 |
| T3 | 1.5-2 天 | fixture+脚本+L1-L12+14 格判定+红证归档+book 新章+全量门 |
| 合计 | **5-7 天** | 建设型主线；决策 1 回落 A 路 +1-1.5 天、决策 4 回落 B 案 +0.5 天浮动 |
