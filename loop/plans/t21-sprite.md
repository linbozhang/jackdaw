# T21 完整 Sprite 作者流程 — 实施方案

> 策划产物（2026-10-28 派单、2026-10-28 定稿，基于本地 main **79ec1994**（T20 收官合入，
> P1 段 T01-T20 全闭环）全量只读调研：fork `/Users/zhanglinbo/workspace/bevy-fork-pinned`
> （**版本 0.20.0**——派单口径「0.16 pinned fork」已过时，T10 已重制 fork 并钉 0.20.0，
> fork 根 `Cargo.toml:3`）的 `bevy_sprite` 全 4 文件+`bevy_sprite_render` 源清单+`bevy_image`
> 的 texture_atlas 三件+`bevy_camera/src/components.rs`（Camera2d）+`bevy_internal/src/
> default_plugins.rs`+fork 根 `Cargo.toml` feature 图；编辑器 `src/{viewport_2d,viewport_host,
> scenes/operators,scene_io/load,entity_ops,creation_taxonomy,ui_asset_drop,new_asset,
> definition_assets,inspector/{component_picker,asset_row,reflect_fields},asset_ingest,
> thumbnail,pie_projection,launcher/{mod,jd},new_project}`；`crates/jackdaw_scaffold/src/
> lib.rs`（StarterScene）、`crates/jackdaw_runtime/src/{lib,pie_frames}.rs`、
> `crates/jackdaw_api_internal/src/{asset_kinds,registries}.rs`、`crates/jackdaw_scene_types/
> src/lib.rs`（Scene2dRoot/UiSceneRoot/CanvasGuides）；**上游对照**：本地 git 里
> `nightly-2026-10-27` 标签（上游 2026-10-26 发布，领先 merge-base 5c3ba8ea 恰 40 commit，
> 含六大 sprite PR 的完整实现与约 3,300 行测试）；workspace `Cargo.toml`；
> `loop/plans/roadmap-game-dev.md` T21 行+`loop/plans/t16-audio.md`/`t19-graphics-parity.md`
> 范本；`buglist.md` 全量 sprite/2D/atlas 域扫描；`loop/qa/manual.md` §7。**零临时探针**——
> 关键结论（fork 2D 栈 default feature 在装、编辑器 2D 场景壳已成、上游六 PR 在 nightly
> 标签不在 main、绘制顺序=z 排序、TextureAtlasLayout 无 Default、PIE 投影跳 Camera2d）
> 全是静态可复核事实，标签/分支归属用 `git merge-base --is-ancestor` 逐个核实。
> 需求来源：`loop/plans/roadmap-game-dev.md` T21（P2 段开篇第 38 行，2D 域首个任务；
> 备注行：若首款游戏是 2D，T21/T22 升 P1）。
> **验收原文**（roadmap 第 38 行，逐字核实）：「**完整 Sprite 作者流程：导入/PPU/Pivot/
> 过滤/图集切分/绘制顺序/预览。验收=图片或 Sheet→可编辑可保存可运行的 2D 对象。**」
> **任务定性：建设型，主体=移植上游已交付的 sprite 交互套件+补齐四个引擎外授权面
> （约 65/35 偏建设）**——「2D 域现状未探明」的第一盘点项带来**本 loop 第七次定性反转、
> 也是最大的一次**：①引擎侧，fork 的完整 2D 栈（Sprite/Anchor/TextureAtlas/九宫格
> slicing/2D instancing/Camera2d/SpritePicking）经 default feature「2d」**在编辑器与游戏
> 两侧早已编译在装**，逐词能力全部机制成晶；②编辑器侧，2D 域并非空白——**2D 世界场景
> 壳已成**（`scene.new kind=2d`/`Scene2dRoot` 标记/文档 kind 检测/2D 画布 Camera2d 演示层/
> pan-zoom 随视图），游戏侧 **2D 模板已就绪**（`Template::TwoD`+Camera2d+Sprite 开箱场景）；
> ③**决定性发现：上游 `nightly-2026-10-27` 已合入六大 sprite PR（拾取/描边/移动/旋转缩放
> gizmo/吸附/参考线/Add 菜单与 `sprite.add`/图片拖放，约 3,800 行产品代码+3,300 行测试），
> 全部不在本地 main**——「可编辑」半边的主体不是发明而是移植；④真正要新建的是上游也
> 没有的四个面：图集切分授权（TextureAtlasLayout 无 authoring 面）、Pivot 九宫格面、
> 过滤授权面、以及 PPU 的诚实对应物定性。缺陷候选按 **SP 系**编号（Sprite，避开
> buglist R/Y/W/A/N 系与 T01-T20 各任务编号系 U/I/F/C/PF/AN/AU/AR/GR/EG），只记不修→
> 主控裁定吸收面。
> 真机口径：**macOS（本机）**，bash+curl+jq 驱动编辑器 BRP 15703 与游戏 BRP 15702
> （`loop/qa/t16-live.sh` 全套形态复用：leg/summary/cleanup trap/`$PHASE` 日志名/gbrp
> settle 重试/export_wait/staged 启动）；**sprite 画布交互腿全在 100% 缩放跑**（A10 绕行
> 口径）；像素证据=`jackdaw/screenshot`+T18 `png_pixels_md5`/sips 裁剪形态（A7 五招
> 自守，决策 8）；**勿设 RUST_BACKTRACE**（T11-T3 口径）；游戏侧数值断言全走 bevy 原生
> `world.query`/`world.get_components`（N12 口径）；N13（PIE drain panic）绕行+记数；
> warn 形态扫描（`sprite|UnresolvedTypes|cannot-apply|panicked`）入常备腿。

---

## 0. 架构事实（核实结论，方案的地基）

**总判断：T21 的引擎层与场景层是「开门」不是「造引擎」——2D 渲染栈、Sprite 组件族、
图集数据结构、2D 场景文档与 2D 游戏模板全部在位；缺的是三层：①交互授权层（把一张图
变成可选中/可拖动/可保存的 sprite 的编辑器通路，上游已写好、未合入 main）；②资产授权层
（图集切分资产的 authoring 面，上游也没有）；③三个属性词的授权面定性（PPU/过滤/绘制
顺序——两个上游也没有，一个是引擎语义注记）。** 十六条事实：

- **事实一：fork 2D 渲染栈经 default feature 在编辑器与游戏两侧编译在装，T21 零引擎
  接入工作。** workspace bevy 依赖无 `default-features=false`（`Cargo.toml:224-243`，
  仅追加 bevy_feathers/serialize/wav/jpeg 等）→fork 默认 feature `default=["2d","3d",
  "ui","audio"]`（fork 根 `Cargo.toml:139`）；`2d=["default_app","default_platform",
  "2d_bevy_render","scene","picking"]`（`:142`）；`2d_bevy_render=["2d_api",…,
  "bevy_sprite_render",…]`（`:225-232`）；`2d_api=["common_api","bevy_sprite"]`（`:222`）。
  DefaultPlugins 按 feature 装入 `SpritePlugin`+`SpriteRenderPlugin`（fork `bevy_internal/
  src/default_plugins.rs:65-67`）；编辑器走 DefaultPlugins（`src/launch.rs:122`）；模板
  游戏 bevy 依赖吃 default features（T16 事实二，`bevy_source.rs:35-40` 无
  default-features=false）。**编辑器与游戏进程今天就能渲染 Sprite**——2D starter 场景的
  Sprite 开箱可见是直接证据（事实七）。
- **事实二：Sprite 组件族权威面，逐词对应验收属性。** `Sprite`（fork `bevy_sprite/src/
  sprite.rs:14-42`）：`image: Handle<Image>`、`texture_atlas: Option<TextureAtlas>`、
  `color`、`flip_x/flip_y`、`custom_size: Option<Vec2>`（**PPU 的诚实对应物**，:29-31）、
  `rect: Option<Rect>`、`image_mode: SpriteImageMode`（**九宫格**）、`alpha_mode`；
  `#[require(Transform, Visibility, VisibilityClass, Anchor)]`+`#[reflect(Component,
  Default, Debug, Clone)]`（:15-16）。**Anchor 即 pivot**：`Anchor(pub Vec2)` 归一化偏移，
  九常量（BOTTOM_LEFT…TOP_RIGHT，:307-315），`#[doc(alias = "pivot")]`（:302），
  `#[reflect(Component, Default, Debug, PartialEq, Clone)]`（:301）。`SpriteImageMode`
  四态 Auto/Scale(Six-mode)/`Sliced(TextureSlicer)`/**Tiled{tile_x,tile_y,stretch_value}**
  （:200-221）——`TextureSlicer` 九宫格+borders（`texture_slice/slicer.rs`，56 行）。
  `SpriteAlphaMode` Opaque/Mask/Blend（:180-197）。`SpritePlugin` 还装
  `calculate_bounds_2d`（Aabb 随 Sprite/Anchor 变更，`lib.rs:63-100,107-203`）与
  `SpritePickingPlugin`（bevy_picking feature，:97-98；fork picking_backend.rs 全件
  SpritePickingSettings/SpritePickingMode 在）。
- **事实三：图集数据结构全套在库，但布局资产无 authoring 面——缺口在编辑器不在引擎。**
  `TextureAtlasPlugin`：`init_asset::<TextureAtlasLayout>()`+`register_asset_reflect`
  （fork `bevy_image/src/texture_atlas.rs:16-25`；SpritePlugin 无条件先装它，
  `bevy_sprite/src/lib.rs:68-70`）。`TextureAtlasLayout{size: UVec2, textures: Vec<URect>}`
  （:104-109）带 `from_grid(tile_size, columns, rows, padding, offset)`（:133-139）与
  `add_texture(rect)`（:180）；`TextureAtlas{layout: Handle<TextureAtlasLayout>, index:
  usize}`（:210-219，`reflect(Default,…)` :212——**有** ReflectDefault）；批量打包器
  `TextureAtlasBuilder`+`DynamicTextureAtlasBuilder` 均在 bevy_image。**关键缺口**：
  `TextureAtlasLayout` 的 derive 只有 `reflect(Debug, PartialEq, Clone)`（:96），**无
  `Default` impl、无 ReflectDefault**（:99-109）——①New Asset 门
  `has_default_value` 要求 `ReflectAsset`+`ReflectDefault` 双在（`src/new_asset.rs:55-65`）
  →不可能出现在 New Asset 清单；②编辑器 `compiled_kinds` 六种（Material/Animation
  Graph/Prefab/Layered Surface/Foliage/Water，`src/definition_assets.rs:1356-1378`）
  无图集；③部分补丁 apply 路径的 Default 依赖=T16 坑甲同构（T16 v2：ReflectDefault
  要求 `T: Reflect+Default` 且 `ReflectDefault` 无公共构造器，fork `bevy_reflect/src/
  std_traits.rs:23`——外部不可补，fork 加 derive 是唯一正门）。
- **事实四：编辑器 2D 世界场景壳已成——场景层零新建。** `SceneKind{ThreeD,TwoD,Ui}`
  （`src/scenes/operators.rs:58-66`，TwoD 注释「sprites in the world viewport, no 3D
  furniture」）；`scene.new kind=2d` → `seed_2d_scene_root`（`src/entity_ops.rs:900-913`
  spawn `Name+Scene2dRoot+Transform+Visibility` 并入 AST）；文档 kind 检测
  `declared_scene_kind`（`src/scene_io/load.rs:499-511`，读根标记，**重开识别 2D**，测试
  :1122-1148）；kind→面板模式 `mode_for_scene_kind`（`src/viewport_host.rs:20-29`，
  TwoD/Ui→`ViewportMode::TwoD`）。2D 画布演示层：每面板私有 `Camera2d`
  （`Viewport2dCamera`，`src/viewport_2d.rs:1568-1592`，渲染进面板私有 Image，
  **RenderLayers 含 layer 0**——注释明言「default-layer scene content still draws here」
  :1571-1572，即 2D 世界内容直接被画进画布）；`apply_2d_view` 把 pan/zoom 写上相机
  （:536-563，doc「It applies to 2D world content drawn into this panel, so sprites,
  gizmos and guides stay framed with the canvas」——**注释里的 sprites 今天是空头支票**）。
- **事实五：main 的 sprite 交互授权=零，且图片拖放进 2D 场景产的是错误形态。** 全
  `src/` 无任何 sprite 交互代码（grep `Sprite` 产品命中为零，仅 viewport_2d 注释）；
  Add 菜单 built-in 六组（3D Objects/Lights/Cameras/Audio & Animation/Environment/
  Regions，`src/creation_taxonomy.rs:144-153`）**无 Sprite 行**（grep 零命中），且六组
  在 2D 场景**照常全量出现**（无 kind 门——加 Cube 进 2D 场景不报错但 2D 相机画不出）；
  「Reference Image」是 3D 参考面（`entity.add.image`→`reference_image::open_reference_
  image_picker`，`src/entity_ops.rs:2785-2789`）；**图片拖到 2D 画布** `classify_drop`→
  `drop_image`→`spawn_image` 产 **UI `ImageNode`+`Node`** 节点（`src/ui_asset_drop.rs:
  67-99,188-207`）——在 2D 世界场景这是错误物种（UI 节点不吃 Camera2d/Transform 语义，
  也不落世界 z 排序）。
- **事实六（本方案最高权重事实）：上游 nightly 已交付完整 sprite 交互套件，全不在
  main。** 本地 git 有上游标签 `nightly-2026-10-27`（2026-10-26 发布），自 merge-base
  5c3ba8ea（=main 的上游基点，`git merge-base` 实证）领先 **40 commit**，其中 sprite
  域六连发（`git show --stat` 逐个核实）：
  **#650**（91fa6afe）拾取+描边——`src/sprite_stage.rs` 639 行（2D 世界适配器，拣选/
  outline/拖拽判定）+viewport_2d 坐标映射 80 行+`tests/stage/sprite_picking.rs` 546 行；
  **#653**（8b043358）移动 gizmo+方向键+undo——`src/sprite_gizmo.rs` 724 行+scene_io
  三文件小改+`tests/stage/sprite_gizmo.rs` 718 行；**#654**（e7cb8638）旋转+缩放 gizmo
  （sprite_gizmo +318）；**#655**（5e865fad）拖拽吸附（网格/像素/邻 sprite 边）——
  `src/sprite_snap.rs` 301 行+`crates/jackdaw_snap` +124 行；**#656**（edf167e5）2D 世界
  参考线+吸附（canvas_snap +187，`CanvasGuides` 扩展到世界场景）；**#657**（10a53456）
  **Add 菜单 2D 组+`sprite.add` operator+图片拖放**——`src/sprite_ops.rs` 307 行+
  creation_taxonomy +29（`two_d` 组按 `OpenScene2dRoot` 出现，含 Sprite/Empty 2D 两行）
  +ui_asset_drop 改路由。合计约 **3,800 行产品代码+3,300 行测试**。`sprite.add` 权威
  形态（nightly `src/sprite_ops.rs`）：params `path/x/y/parent/name`，spawn
  `Name+Sprite::from_image(AssetServer.load)+Anchor::default()+Transform(带 z)+Visibility
  +ChildOf`，**z=场景内最高 sprite+1**（注释「Sorting proper is defined by issue 03」——
  上游把排序面也 deferred 了）；`SpawnEntity` 命令入 `CommandHistory`（undo 白得）；
  `SpriteAddGate` 复用 `can_act_on_entities`。**cherry-pick 可行性正面信号**：上游
  sprite 代码引用的 bevy API（`SpritePickingMode/Settings`、`TransformSystems`、
  `UiTransform`）在本 fork 全部在位（逐个 grep 实证）；**风险面**：与本地 T08-T20 改动
  重叠文件 12 个（`git diff 5c3ba8ea..HEAD` 与六 PR 文件集求交：boot_ops/commands/
  creation_taxonomy/entity_ops/gizmos/lib.rs/scene_io/{load,mod,save}/test_input/
  transform_ops/viewport.rs），外加 #650 顺带修的 2D 画布 target size 物理/逻辑像素 bug
  （main 无此修，见 SP6）。
- **事实七：游戏侧 2D 模板已就绪——「可运行」基座零新建。** `StarterScene{ThreeD,
  TwoD,Empty}`+`STARTER_SCENE_2D`（`crates/jackdaw_scaffold/src/lib.rs:1104-1133`：
  根+#"Main Camera"`bevy_camera::components::Camera2d`+#"Sprite"`bevy_sprite::sprite::
  Sprite`+`Transform{scale: 64}`）；`write_starter_scene`（:1145-1150）；launcher
  `Template::TwoD`（"2D game"，`src/launcher/mod.rs:206-277`）与 `jd` 任务链
  （:525-533）；`scaffold_project_with`（`src/new_project.rs:46-54`）。**边界**：2D
  模板只换 starter 场景，游戏 lib 仍是 3D 风味（CameraRig 代码侧 spawn Camera3d+物理+
  T13 flow 三文档）——2D 场景跑起来=Camera2d 画 sprite、3D rig 相机画空 3D 图，能跑
  但有家具噪音（决策 6）。PIE 侧投影 skip 清单含 Camera2d（事实十四）。
- **事实八：绘制顺序的引擎语义=z 排序，无 Y-sort；编辑器授权面=裸 Transform.z。**
  sprite 提取进 `Transparent2d` 相位时 `sort_key = FloatOrd(extracted_sprite.transform.
  translation().z)`（fork `bevy_sprite_render/src/render/mod.rs:504`）——**绘制顺序=
  Transform.translation.z**（小 z 先画）。fork 无 Y-sort（grep 零命中）；上游亦无排序
  面（#657 注释自证 deferred 到上游 issue 03）。编辑器对 z 的授权=Inspector Transform
  字段裸编辑+上游 gizmo 的拖拽；「新 sprite z 最高」是 #657 的唯一秩序供给。
- **事实九：PPU 在引擎与编辑器都不存在——它是要「定性」不是要「实现」的词。** 全仓+
  fork+nightly grep `pixels_per_unit|PPU` 零命中。bevy sprite 量纲=1 world unit : 1
  纹素（`sprite_size` 取图像像素尺寸，fork `sprite.rs:166-178`；Anchor 偏移乘该尺寸），
  尺寸调节的引擎对应物=`Sprite.custom_size`（:29-31）与 `Transform.scale`（starter 场景
  用的就是后者，事实七）。Unity 的 PPU（pixels-per-unit 换算）在 bevy 语境的正确投影=
  「custom_size/scale 即换算结果」，无独立 PPU 概念需要引入（决策 2）。
- **事实十：过滤（sampler/filtering）是资产属性且不持久——上游也没有授权面。**
  `Sprite` 无 sampler 字段（事实二全字段清单）；bevy 的纹理过滤在 `Image.sampler`
  （per-asset）；编辑器只有**全局默认** `ImagePlugin default_sampler`（linear+repeat，
  `src/launch.rs:122-130`）。png→`ImageLoader` 每次装载重建 Image→任何运行态 sampler
  改动不落盘；持久化需 meta/import 管线面（T18 的 texture.import `.meta` 是压缩域
  先例，`A12/AR9` 域）——SP4 记档+决策 5。
- **事实十一：T18 导入面全量复用——「导入」词大量成晶。** 拖放/粘贴分类
  png|jpg|jpeg|webp|bmp|tga→`AssetKind::Image`（`src/asset_ingest.rs:31`）+落盘+重名
  退避（:145 W8 修）；资产行 picker 扩展名映射 `IMAGE_EXTENSIONS`（`src/inspector/
  asset_row.rs:48`,`:633-643` Image/AudioSource 两臂在册）；缩略图管线
  （`src/thumbnail.rs` 渲染进 `.jackdaw/thumbnails/`）；失败反馈横幅（`src/asset_failures.rs`，
  T18-AR3）+魔数校验先例（音频 `audio_file_plausible`，asset_row.rs:485-490）。
  Sprite 流程对图片文件零新增导入面；唯一接线=「拖进 2D 场景→成 sprite」（#657 已写）。
- **事实十二：Inspector 通用机器对 Sprite/Anchor 今天就可编辑——组件 picker 门全过。**
  picker 只门 `ReflectComponent` 等（`src/inspector/component_picker.rs:123-131`），
  fork 反射自动注册（bevy_app inventory auto-register，T16 事实四同源）使
  `Sprite`（reflect Component+Default，事实二）与 `Anchor`（同）**预期已在 Add Component
  picker**（T1 首步活证钉死）；字段面：`image` Handle→asset_row Pick/Clear/Browse/拖放
  全套（IMAGE_EXTENSIONS 臂现成，事实十一）；`Option<TextureAtlas>` 字段有 Option 编辑
  机器（`src/inspector/reflect_fields.rs:3579` Option 特判）；`image_mode/alpha_mode`
  枚举有 spawn_enum_field 机器（T09/T16 先例）；**`texture_atlas.layout` 的
  `Handle<TextureAtlasLayout>` 无 asset_row 臂**（:633-643 只映射 Image/AudioSource）→
  布局字段零候选（T16-AU3 同构，SP3 的_picker 面）。
- **事实十三：序列化与运行时装载两侧零障碍（图集布局资产待探针一条）。** 保存只跳
  `jackdaw::` 前缀（`src/scene_io/mod.rs:163-165`）——`Sprite`/`Anchor`/`TextureAtlas`
  是 bevy 原生类型，**直接进 scene.bsn**；游戏侧 `load_walked_assets` 走 catalog+walk
  （`crates/jackdaw_runtime/src/lib.rs:1700-1800`），头行类型未注册才跳过——
  TextureAtlasLayout 经 TextureAtlasPlugin 已 init_asset+register（事实三）→walk 预期
  装载（**探针一条钉死**：bsn 形态的 layout 资产+场景引用往返）；Handle 解析走
  `bsn_value_to_reflect` 的 `load_erased`（T16 事实五）。上游两条相关修复未合入
  main 也与本链相邻：2198c1c2「元组形态项目组件保存」（bsn parse）与 1655f425
  「Visibility::Inherited 不落盘」——T1 探针评估是否顺带。
- **事实十四：PIE 对 2D 场景有一个结构性疑点=本任务必做探针（SP7）。** PIE 窗口模式
  的流送帧由 `FrameCaptureCamera`（**Camera3d**，挂 rig）渲染（`crates/jackdaw_runtime/
  src/pie_frames.rs:108-110,188-200`）；windowless 模式才由「游戏自己的相机」渲染进
  共享目标（:114-118 doc）。且编辑器侧 PIE 投影 skip 清单跳全部 Camera 组件（含
  Camera2d，`src/pie_projection.rs:65-70`+测试 :975-978）——**经快照路径播放的 2D 场景
  可能丢它唯一的（authored）Camera2d**；文件路径（pie.play_current temp 副本）不受此
  影响（Camera2d 在盘上场景里）。GR8（T19「PIE 流送帧忠实性探针」）的 2D 版，探针
  定案后 PIE 通道分流（决策 7）。
- **事实十五：buglist 域内与邻域条目。** 域内：**W2**「多 UI 根时画布 reference size
  口径不一致」（buglist:295-297，`src/viewport_2d.rs:790-793` vs `:1119-1122`）——2D
  世界场景同病（同一套 `size_targets_to_reference`）；工具债：**A7**（:459-464 截图
  同帧 flake+字段行定位族）、**A9**（:497 游戏 BRP 空响应）、**A10**（:465-467 PIE
  指针缩放布局）、**A14**（:481 ui_tree 缺 display/hover）、**A15**（:485 preset
  flake）、**A16**（:489 flow 通道死——T21 无依赖）；邻域：A12（GPU 面冻结——像素
  红绿假红鉴别相关）、A13（imported 孤儿）。**sprite/图集域无开放 R/Y 条目**——用户
  从未有过可触达该域的通路（SP1 挡着），与 T16 音频域同构局面。
- **事实十六：文档与开箱描述面。** `book/src/user-guide/` 22 章无任何 2D/sprite 章
  （ls 实证）；launcher 对 2D 模板的用户可见描述「Camera2d and a sprite」（`src/launcher/
  mod.rs:243`）；`scene.new` 的 kind 子句 2d 已入 operator 面（`src/scenes/operators.rs:
  70-74`）与 UI（`src/lib.rs:2778,4280`）。T21 的 book 落点=新章 `sprites-2d.md`
  （SUMMARY 排 game-ui 附近）。

### 验收句逐词定性（矩阵化的前提）

| 验收词 | 定性 | 依据 |
|---|---|---|
| 导入 | **验成晶（T18 全量复用）** | png/jpg 分类+落盘+缩略图+失败横幅全在（事实十一）；唯一接线=拖放进 2D 场景成 sprite（#657 已写，main 无=SP1） |
| PPU | **定性缺口（SP5，决策 2）** | 引擎/编辑器/上游三方零命中（事实九）；bevy 对应物=custom_size/scale 已可编辑（事实十二）；诚实做法=量纲教学注记而非引新概念 |
| Pivot | **半成晶（SP10）** | `Anchor` 组件全套在+预期已在 picker+Inspector Vec2 可编辑（事实二/十二）；缺九宫格预设面（上游亦无） |
| 过滤 | **缺口（SP4，决策 5）** | 过滤是 per-asset sampler 且不持久（事实十）；无授权面无持久化面，上游亦无 |
| 图集切分 | **机制成晶+授权缺口（SP3，决策 4）** | TextureAtlasLayout/TextureAtlas/from_grid/Builder 全在库（事实三）；编辑器零 authoring 面（无 AssetKind/无 picker 臂/New Asset 门挡）；上游亦无 |
| 绘制顺序 | **机制成晶+授权半缺口（SP9）** | z 排序引擎语义明确（事实八）；授权=裸 z 字段（在）+上游 gizmo（main 无）；排序面板/Y-sort 双缺（上游亦 deferred） |
| 预览 | **成晶（2D 画布即预览）+PIE 探针（SP7）** | Camera2d 面板相机画 layer 0 世界内容+apply_2d_view 随视图（事实四）；PIE 2D 流送帧/快照路径存疑（事实十四） |
| 验收：图片→**可编辑** | **缺口（SP1/SP2=建设主体）** | Add 菜单无 Sprite/无 operator/拖放产错误物种+拾取描边 gizmo 全无（事实五）；上游六 PR 全量在 nightly（事实六） |
| 验收：→**可保存** | **成晶（机器侧）** | bevy 原生组件进 bsn 无障碍+kind 重开识别（事实十三/四）；Undo/脏标记链 T03 成品——矩阵落证即可 |
| 验收：→**可运行** | **基座成晶+PIE 疑点** | 2D starter 场景+Template::TwoD 开箱可跑（事实七）；direct/导出通道 T06/T07 成品；PIE 2D 待探针（事实十四） |

### 全链断点图（图片或 Sheet→可编辑→可保存→可运行）

```
图片文件 ──拖放进工程──▶ assets/（T18 ✓成晶）
   │
   ├─ A 路：拖进 2D 画布 ──▶ sprite.add（✗ main 无=SP1；#657 现成）──▶ Sprite 实体
   ├─ B 路：Add 菜单 2D 组（✗ main 无=SP1；#657 现成）─┘
   └─ C 路：Add Component picker 手挂 Sprite（≈✓ 机器现成，无图片、非作者路）
                │
                ▼
        画布拾取/描边（✗ SP2；#650 现成）→ 移动/旋转/缩放 gizmo+undo（✗；#653/#654）
        → 吸附/参考线（✗；#655/#656，优先级低）→ Inspector 属性面（✓ 事实十二）
        → Pivot（✓ 组件面 / ✗ 九宫格预设=SP10）→ 绘制顺序 z（✓ 裸字段 / ✗ 面板=SP9）
                │
   Sheet 路线：sheet.png 导入（✓）──▶ 图集布局资产（✗ SP3 全缺，决策 4）
                │                      ──▶ Sprite.texture_atlas 指认+index（半✓：
                │                          Option/usize 机器在，layout picker 无臂）
                ▼
        scene.save（✓ bevy 原生组件直落 bsn）──▶ 重开（✓ kind 识别+组件往返）
                │                                   └─ 图集布局引用往返（⚠ 探针钉死）
                ▼
        可运行：direct run（✓ Camera2d+SpritePlugin 在装）｜PIE（⚠ SP7 探针）
                ｜导出 staged（✓ assets 整树+T07 通道）｜开箱 2D 模板（✓ 事实七）
```

---

## 一、缺陷候选（SP 系，只记不修→主控裁定吸收面）

| 编号 | 严重度 | 描述 | 证据 | 处置建议 |
|---|---|---|---|---|
| **SP1** | 🔴 | **2D 场景零 sprite 授权通路**：Add 菜单无 Sprite 行、无 `sprite.add` operator、图片拖放进 2D 世界场景产 UI `ImageNode`（错误物种）——「图片→可编辑」第一断点 | 事实五 | **吸收（建设主体，#657 移植）**。三入口（菜单/operator/拖放）同归 `sprite.add` |
| **SP2** | 🔴 | **sprite 画布交互零**：无拾取、无描边、无 gizmo（移动/旋转/缩放）、无方向键微调——2D 场景里的 sprite 只能 Inspector 改数字 | 事实五；apply_2d_view 注释「sprites… stay framed」是空头支票（事实四） | **吸收（建设主体，#650/#653/#654 移植）**；#655/#656 吸附与参考线列可选项（决策 1） |
| **SP3** | 🟡 | **图集切分零授权面**：TextureAtlasLayout 无 Default/ReflectDefault（New Asset 门挡）+无 AssetKind+asset_row 无 layout 臂+无网格切分 UI——验收词「图集切分」在编辑器无落点 | 事实三/十二 | **吸收（决策 4）**。建议 fork 加 Default 一行+注册 compiled kind+网格切分 operator（`from_grid` 授权） |
| **SP4** | 🟡 | **过滤零授权面且不持久**：sampler 是 per-asset 属性，png 重载即重置；编辑器只有全局默认（linear） | 事实十 | **记档+book 注记（决策 5）**：本轮不做持久化面（meta/import 管线域，超任务边界）；nearest 的当前正道=全局默认或代码侧 |
| **SP5** | 🟡 | **PPU 概念不存在**：Unity 量纲习惯无对应物，教学缺失（作者不知道 64×64 图=64 单位） | 事实九 | **吸收（定性，决策 2）**：建议 A「量纲=世界单位」+book 对照表；引 PPU 桥接组件=过度建设 |
| **SP6** | 🟡 | **2D 画布 target size 物理像素 bug**：无 UI 根时 target size 用 `computed.size()`（物理 px），缩放因子≠1 时一 target px≠一逻辑 px——拾取/吸附坐标在 150% 缩放下漂移 | nightly #650 diff 实证（main 为旧代码路径，事实六） | **随 #650 移动 gizmo 移植带修**；真机腿在 100% 缩放跑（A10 口径双保险） |
| **SP7** | ⚪ | **PIE 对 2D 场景的流送帧与快照路径存疑**：FrameCaptureCamera 是 Camera3d（窗口模式）+投影 skip 含 Camera2d（快照路径丢 authored 相机嫌疑） | 事实十四 | **T1 首步探针定案（决策 7）**：忠实→矩阵保留 PIE PX 格；不忠实→PIE 降级数值轨+SP7 记档 |
| **SP8** | ⚪ | **绘制顺序只有裸 z**：无排序面板、无 Y-sort、无 hierarchy 拖拽重排映射——「绘制顺序」词的授权面最薄 | 事实八；上游 issue 03 deferred 自证 | **记档不修（决策 6）**：裸 z+gizmo 已满足「可编辑」字面；面板/Y-sort 记 open-challenges |
| **SP9** | ⚪ | **Anchor 无九宫格预设面**：裸 Vec2 归一化值对作者不友好（Unity 用户期待 3×3 预设） | 事实二/十二 | **吸收（小件，决策 3）**：Anchor 行加 3×3 预设 segmented（建议 B）；裸 Vec2 保留兜底 |
| **SP10** | ⚪ | **Add 菜单六组 3D 家具在 2D 场景照常全量出现**：加 Cube 进 2D 场景不报错但 2D 相机画不出（误导性） | 事实五 | **记档不修**：上游 #657 只加 2D 组不做 3D 组隐藏；book 注记「2D 场景用 2D 组」；3D 组按 kind 隐藏记 open-challenges |

统计：🔴 2（SP1/SP2，均为验收缺口的建设面）｜🟡 4（SP3-SP6）｜⚪ 4（SP7-SP10）。

### buglist 重叠表（sprite/2D/atlas/图集/纹理域全量扫描）

| 条目 | 一句话 | T21 处置 |
|---|---|---|
| **W2**（buglist:295-297） | 多 UI 根时画布 reference size 口径不一致（viewport_2d 三处取根各异） | **知悉+真机腿记数**：2D 世界场景同病；若 sprite 腿撞到画布 framing 异常，按 W2 归因记档不修；上游 #650 的逻辑像素修（SP6）不涉多根口径 |
| **A7**（buglist:459-464） | 截图同帧 flake+字段行定位族+stale grep | **不前置，五招自守（决策 8）**：唯一 request 键/rm -f 先行/size 验证/相邻两拍 flake 探针/screencapture 降级；`$PHASE` 日志名写法直接吸收 |
| **A9**（buglist:497） | 游戏 BRP 间歇空响应 | **自守不前置**：gbrp settle 重试+小响应体（单实体单组件）+避开构建窗口；游戏侧断言全 bevy 原生（N12 口径） |
| **A10**（buglist:465-467） | PIE 指针转发缩放布局 | **绕行**：画布交互腿全在 100% 缩放跑；PIE 真指针腿仅保一条（N13 记数同行） |
| **A14**（buglist:481） | ui_tree 缺 display/hover | **知悉**：Inspector 面板腿走 ui_tree 现有过滤（kind=text_input/slider）+operator 直达为主，不依赖缺的 display 面 |
| **A15**（buglist:485） | viewport preset 选取 flake | 无依赖（本任务不动 viewport preset）；知悉 |
| **A16**（buglist:489） | GameFlow BRP 通道死 | 无依赖（本任务不走 flow 通道）；知悉 |
| **A12/A13**（:474,:478） | 纹理导入 GPU 面冻结/imported 孤儿缓存 | **邻域知悉**：像素红绿出现「值改了画面不变」时先查 A12 同族再判 SP；图片资产用 plain png（无 .meta）避开 A12 触发面 |
| N13 | PIE drain panic 100% 复发 | 绕行+记数：数值断言 panic 后重试；PIE 仅保一腿 |
| 其余 | R/Y/W 系均为 prefab/brush/chrome/键位/地形域 | 无动作 |

> 如实报告：sprite/图集域 buglist 零直接条目（唯一近亲 W2 是画布 framing 面）——该域
> 用户从未有可触达通路（SP1 挡着），T16 音频域同构局面。T21 缺陷主体是本方案新发现
> 的 SP1-SP10 与移植面里的未知数（决策 1 的探针产物）。

---

## 二、验收矩阵设计

**三铁证×通道=16 格主矩阵+一张关键属性三态表**。断言通道缩写：H=headless（移植带上
来的 `tests/stage/sprite_picking|sprite_gizmo|sprite_snap|world_guides|sprite_drop|sprite_ops`
六族+新增单测）、R=真机编辑器 BRP 15703（operator+`jackdaw/*`+bevy 原生组件查询）、
G=游戏 BRP 15702（bevy 原生 `world.*`，fixture 注入 jackdaw_remote）、PX=像素证据
（`jackdaw/screenshot`+png_pixels_md5/sips 裁剪，A7 五招自守）、FS=盘面（bsn 文本/SHA/
文件清单）、EXPORT=staged 包（manifest+SHA+staged 进程）。

### 铁证①：图片或 Sheet→可编辑

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| 授权链 | M1 | `sprite.add` 三入口同归一形态：Add 菜单 2D 组行（真机 ui_click）/operator 直调（`path/x/y`）/图片拖放——三路各产 `Name+Sprite+Anchor+Transform+Visibility` 实体、undo 各一条、占位方块形态（无图）与图片形态（有图）双态 | 🔴SP1 前置（#657）；R+H |
| 拾取 | M2 | 画布真机点击 sprite→Selection 命中+hierarchy 行选中+描边可见（PX）；点击空白→取消；两 sprite 重叠择顶（z 高者） | 🔴SP2 前置（#650）；R+PX |
| gizmo | M3 | 移动 gizmo 拖拽+方向键微调+undo 逐级还原（T03 链 2D 形态）；旋转/缩放 gizmo 两态 | 🔴SP2 前置（#653/#654）；R+H |
| Inspector | M4 | 属性面逐格：换图（asset_row Pick）/color/flip_x/custom_size/alpha_mode/image_mode=Sliced——画布每格有视觉响应（PX 红绿） | ✅机器现成（事实十二）+⚠️真机腿未跑；R+PX |
| Pivot | M5 | Anchor 九宫格预设（决策 3 落地面）逐格切→画布 sprite 锚点位移可见（PX）+数值落 `Anchor.0` | 🟡SP9 前置；R+PX |
| 图集切分 | M6 | 决策 4 落地面全链：新建 Sprite Atlas→网格切分（tile_size/columns/rows）→Sprite.texture_atlas 指认→index 0→n 切换→画布帧切换（PX 红绿）；布局资产重开可编辑 | 🔴SP3 前置；R+PX+FS |
| 绘制顺序 | M7 | 两 sprite 重叠→改 z 翻转叠序（PX 红绿）+BRP 读 z 值；新加 sprite z=最高+1（上游语义） | 🟡裸 z 在/gizmo 前置；R+PX |
| 预览（画布） | M8 | 2D 画布即预览回归：pan/zoom/fit 下 sprite 恒入画（apply_2d_view 链）+画布标题/模式不回归 | ✅壳成晶（事实四）+⚠️回归格；R+PX |

### 铁证②：→可保存（重开一致）

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| 往返 | M9 | M1-M7 全部编辑后 `scene.save`→重开：Sprite/Anchor/Transform/texture_atlas 逐字段 BRP 读回相等+bsn 文本含全路径类型（A8 口径）+2D kind 重识别 | ✅机器成晶（事实十三）+⚠️真机腿；R+FS |
| 图集引用 | M10 | 布局资产引用往返：save→重开→layout handle 解析同路径；游戏侧 walk 装载同链（headless 探针转正格） | ⚠️探针前置（事实十三）；R+FS+H |
| 横切·Stop | M11 | PIE 播 2D 场景→Stop→场景文档 SHA 不变（T06 链 2D 形态） | ✅T06 成品；R+FS |
| 横切·undo/脏 | M12 | gizmo 拖拽/属性提交后 undo→脏标记恒正确（T03 per-tab 全指纹链 sprite 形态） | ✅T03 成品；R |

### 铁证③：→可运行

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| direct | M13 | `cargo run`（15702）→BRP 读 Sprite/Anchor/Transform 逐字段==编辑器所存+画布与游戏窗口 sprite 位姿一致（PX 双拍对照） | ✅基座（事实七）+⚠️真机腿；G+PX |
| PIE | M14 | `pie.play_current`→游戏窗口/流送帧 sprite 可见（SP7 探针后定 PX 去留，决策 7）+数值读回一致；N13 记数 | ⚠️SP7 前置；G（+PX 视探针） |
| 导出 | M15 | `game.export`→staged 异目录启动→同 M13 断言+包内图片文件清点+manifest 行 | ✅T07 通道；EXPORT+G |
| 开箱 | M16 | launcher `Template::TwoD` 新建→开箱冷启 run→starter sprite 可见（基座回归格，T20 铁证形态的 2D 版） | ✅事实七；G+PX |

### 关键属性×三态表（验收句「可编辑可保存可运行」的字面矩阵）

| 关键属性 | 可编辑（编辑器） | 可保存（重开一致） | 可运行（游戏+导出） |
|---|---|---|---|
| 图片引用（导入） | M1/M4（asset_row） | M9（路径往返） | M13/M15（load_erased+包内文件） |
| PPU 对应物（custom_size/scale，决策 2） | M4（Inspector 数值） | M9 | M13（BRP 读回） |
| Pivot（Anchor） | M5（九宫格+Vec2） | M9（`Anchor(Vec2)` 往返） | M13（Anchor 逐字段） |
| 过滤（SP4 记档） | ✗ 无面（book 注记） | —（不持久，如实） | —（全局默认 linear，如实注记） |
| 图集切分（layout+index） | M6（Atlas 资产+指认+index） | M9/M10 | M13/M15（游戏侧装载） |
| 绘制顺序（z） | M7（z 字段+gizmo） | M9 | M13（叠序 PX 对照） |
| 预览 | M8（画布）/M14（PIE 视探针） | — | M14/M16 |

**矩阵统计**：🔴 前置 5 格（SP1×M1、SP2×M2/M3、SP3×M6、SP7×M14）｜🟡 前置 2 格
（SP9×M5、gizmo×M7 半）｜✅ 机器/基座成晶 6 格（M4/M8/M9 半/M11/M12/M13/M15/M16 半）｜
⚠️ 真机腿缺口 9 格。T1 清源（移植+探针），T2 落建设面，T3 落判。

---

## 三、真机腿清单（Mac，bash+curl+jq；T3 集中跑）

fixture 工程=launcher `Template::TwoD` 出 `/Users/zhanglinbo/workspace/loop-mac/t21-sprite`
（2D starter 场景自带 Camera2d+Sprite；**建后注入 jackdaw_remote 两行 sed**（t15-live.sh
同款）+lock 刷新+暖编）。资产 prep：脚本生成 fixture png（纯 stdlib/`sips`：solid 色块
`hero.png`+2×2 sheet `sheet.png` 四色格，判帧切换的像素红绿正主）。流程脚本
`loop/qa/t21-live.sh`（t16-live.sh 形态全量复用+像素助手族从 t18-live.sh 搬）。

| # | 腿 | 通道 | 为什么必须真机 |
|---|---|---|---|
| L1 | prep+boot：fixture/注入/暖编/编辑器开 2D 场景（kind=2d 识别断言）+画布模式确认 | R+FS | 全矩阵前提态；kind 检测是 scene 层活证 |
| L2 | M1 三入口：菜单 ui_click（2D 组→Sprite）/operator（带 path/x/y）/拖放各一腿→组件四件断言+undo 一条+占位/图片双态 PX | R+PX | 菜单与拖放是编辑器 chrome 视觉面；三路同形=上游语义正主 |
| L3 | M2/M3 拾取与 gizmo：真指针点击（100% 缩放）→选中+描边 PX；拖拽位移+方向键+undo 链；旋转/缩放两态 | R+PX+H | 画布交互是纯真机域（合成指针）；坐标正确性即 SP6 回归面 |
| L4 | M4/M5 Inspector 面：ui_tree 定位属性行→改 color/flip/custom_size+Anchor 九宫格逐格→画布 PX 红绿 | R+PX | Inspector 驱动+视觉响应双侧证明 |
| L5 | M6 图集切分全链：New Asset→网格切分→指认→index 切换→画布帧 PX 红绿→布局资产重开再编辑 | R+PX+FS | SP3 建设面的端到端正主；「Sheet→可编辑」的字面格 |
| L6 | M7 绘制顺序：双 sprite 重叠→z 翻转 PX+读回；新建 z=最高+1 语义 | R+PX | 叠序是渲染事实，只能画布证 |
| L7 | M9/M10 保存重开链：全编辑后 save→重开→逐字段读回+bsn 文本核对+图集引用往返 | R+FS | 验收通用交付铁证（编辑→保存→重开）的编辑器半边 |
| L8 | M13 direct run：idle 探针→BRP 读回逐字段==编辑器值+窗口 PX 对照 | G+PX | 游戏进程行为；「可运行」正主 |
| L9 | M14 PIE：探针结论落地形态跑通（决策 7）+Stop 链 M11+脏标记 M12 | R+G+FS | T06 链 2D 形态+N13 记数 |
| L10 | M15 导出：export_wait（SHA 判据）→staged 异目录启动→同 L8 断言+包内图片清单+manifest | EXPORT+G | 「可运行」导出半边（T12 格 9/T16 L6 形态复用） |
| L11 | M16 开箱 2D 模板回归：再开一个纯 Template::TwoD 工程（不注入）→run→starter sprite 可见 PX | G+PX | 基座回归格（用户第一眼路径） |
| L12 | warn 扫描+存活：全程 `sprite|UnresolvedTypes|cannot-apply|panicked` 零意外命中+每腿 BRP 活性 | 脚本常备 | 常备纪律（T12-U7 教训：warn 形态扫描入常备） |

---

## 四、分任务拆解（T1/T2/T3）

### T1「探针清源+上游移植轮」（建设主体：SP1/SP2；决策 1/7/8）

1. **首步探针（半日级，全部静态+编译级，不跑编辑器）**：①**cherry-pick 试合**——
   `git cherry-pick -n` 六 PR 于 `loop/t21-sprite` 分支，冲突清单与解法记录（12 文件
   重叠面的实证）；②编译探针——移植补丁过 `cargo check`（fork API 兼容性实证，正面
   信号见事实六）；③**决策 1 定案门**：试合干净或冲突 ≤ 机械级→A 路移植；冲突深
   （语义级）→回落 B 路（参照重实现，估时 +3 天）。探针产物即 T1 报告附件。
2. **PIE 2D 探针（SP7，决策 7）**：真机单腿——2D 场景 `pie.play_current`（文件路径
   态）+快照态各一拍：流送帧/游戏窗口 sprite 是否可见+投影 skip 对 authored Camera2d
   的实际影响。定案→M14 形态（PX 保留/降级数值轨）。
3. **#655/#656 取舍**（决策 1 附带）：吸附与参考线随主链移植（测试免费）；若冲突深
   可裁剪，M 矩阵不设硬格（#653 测试族已覆盖拖拽主链）。
4. **移植收尾**：六 PR 产品代码+测试族入库；`tests/stage/main.rs` 等挂接；quick 四门
   （fmt/clippy/单测/stage 族）+移植测试全绿；SP6 逻辑像素修随之入库。
5. **上游相邻修复评估**（事实十三附注）：2198c1c2（元组形态保存）与 1655f425
   （Visibility::Inherited）——探针判定与 sprite 链的耦合度，独立小件则另立不混入。

**验收标准**：移植补丁全绿（含上游 3,300 行测试族）；SP1/SP2 红转绿的 H 侧证据在案；
两个探针有结论（决策 1/7 定案）；quick 门绿。

### T2「授权面建设轮」（SP3/SP9/SP5 落地；决策 2/3/4/5/6）

1. **SP3 图集切分（决策 4-A 建议形态）**：①fork `bevy_image` 的
   `TextureAtlasLayout` 加 `Default` derive+`reflect(Default)`（一行级，走
   `scripts/make-bevy-fork.ps1` 重制纪律，T10 先例）；②`AssetKinds::compiled`
   注册 "Sprite Atlas" kind（`definition_assets.rs:1356-1378` 同款）→New Asset/
   Inspector 编辑（`size+Vec<URect>`）/`asset.set`/保存/游戏 walk 装载全链走通用机器；
   ③`sprite.atlas.grid` operator（tile_size/columns/rows/padding/offset →
   `TextureAtlasLayout::from_grid` 写值）——「网格切分」的作者入口；④asset_row 加
   `TextureAtlasLayout` 臂（Sprite.texture_atlas.layout 字段有候选）。
2. **SP9 Pivot 面（决策 3-B）**：Anchor 行九宫格预设 segmented（3×3+Center，写
   `Anchor.0` 常量值）+裸 Vec2 保留——Inspector 小件+单测。
3. **SP5 定性落地（决策 2-A）**：零代码——量纲教学进 book（对照表：Unity PPU 100
   的 64px sprite ↔ bevy custom_size 0.64 或 scale 0.64）；SP5 关闭形态=文档+矩阵
   M4 的 custom_size 格承载。
4. **SP4/SP8/SP10 记档件**：book 注记草稿+open-challenges 两行（排序面/3D 组隐藏）。
5. **模板面裁定落地（决策 6）**：建议 A（本轮零模板改动，M16 以现状基座为准）；
   若裁 C（2D 示例段）则 lib.rs.template 加 sprite 移动+atlas 帧动画教学段（~40 行，
   T12 教学密度口径）。
6. **门禁**：quick 四门+fork 重制后全量编译+`tests/stage` 六族回归。

**验收标准**：图集切分全链 headless 绿（New Asset→编辑→保存→walk 装载探针转正）；
Anchor 九宫格单测绿；fork 变更记录在案（一行+重制脚本产物）；SP4/SP5/SP8/SP10 记档
文本在案。

### T3「真机矩阵轮+终验+文档」（验收主任务：M1-M16/L1-L12；决策 5/8）

1. fixture+`loop/qa/t21-live.sh`+L1-L12 全腿；每腿 idle 探针开场；A7 五招/A9 settle/
   A10 百分比缩放/N13 记数全量入脚本；红证归档 `loop/reports/t21*/`。
2. 缺陷只记不修：新发现按 SP 系续编（SP11 起）；W2 撞面按重叠表口径归因。
3. QA 报告：16 格矩阵逐格判定+关键属性三态表逐行指认+L 腿全证据+用户 30 秒清单草稿
   （拖一张 png 进 2D 场景→点选→拖动→改 Pivot→存→Play 看见）。
4. book 新章 `book/src/user-guide/sprites-2d.md`（SUMMARY 排 game-ui 附近）：2D 场景
   建立导览（scene.new kind=2d）/sprite.add 三入口/画布交互（拾取/gizmo/吸附）/属性面
   （Sprite 字段表+Anchor 九宫格）/量纲与 PPU 对照表（SP5）/图集切分（Atlas 资产+网格
   operator+index）/绘制顺序 z 语义（SP8 注记）/过滤的现状与正道（SP4 注记）/
   PIE 与导出（SP7 结论）；`game-ui.md`/`assets.md`/`scene-management.md` 交叉引用。
5. buglist 处置（预期无打钩；W2 若撞面回写证据）、roadmap T21 勾选、台账记行。
6. 终验门：全量门（fast/integration/doctests/docs/scaffold_e2e——日志全文复核；
   integration 唯一预期红=A6 定案口径隔离绿）。

---

## 五、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **上游 sprite 套件获取形态（本方案最高权重，SP1/SP2）** | A=**cherry-pick 六 PR**（~3,800 行产品+3,300 行测试白得；上游已真机验证过；风险=12 文件冲突面+nightly 与 main 的中间 34 commit 隐性依赖；T1 首步试合探针定案）。B=**参照重实现**（完全自主可控、零外来语义；代价 +3-4 天且丢上游测试族，同功能两份实现分叉）。C=**吸收整 nightly**（40 commit 全收含 jackdaw_tilemap——越 T22 界、含 release/extension 基建大爆炸，本任务无法收敛）——**否决** | **A**；试合冲突 ≤ 机械级→A 落地；语义级冲突→回落 B（回落判据=T1 探门，估时表按 A 报、B 浮动 +3 天记风险表） |
| 2 | **PPU 词的定性落点（SP5）** | A=**不引入 PPU**：量纲=世界单位（1 unit : 1 纹素），Unity PPU 的对应物=custom_size/scale（已可编辑），book 对照表教学——零代码、引擎正统。B=**SpritePpu 桥接组件**（`pixels_per_unit: f32`+派生 custom_size 的小系统，模板+编辑器双面注册）——Unity 手感直译，代价=新组件族+双端注册+与 fork 引擎语义并行的第二套尺寸真相（两个可编辑字段打架）。C=fork Sprite 加 PPU 字段——动引擎面，**否决** | **A**；B 记 open-challenges（若后续 2D 用户反馈量纲痛点再立）；M4 以 custom_size 格承载「PPU」验收词 |
| 3 | **Pivot 授权面（SP9）** | A=裸 Vec2+book 九值表（零 UI，零风险）。B=**九宫格预设 segmented**（3×3+Center 写 Anchor 常量，Inspector 小件 ~60 行+单测；Unity/主流直觉）。C=画布 pivot 手柄拖拽（上游无，gizmo 面扩展大） | **B**；A 兜底保留（预设行+数值行并存）；C 记 open-challenges |
| 4 | **图集切分授权形态（SP3，本任务最大新建面）** | A=**Sprite Atlas 定义资产**（fork 加 `Default`+`reflect(Default)` 一行+`AssetKinds::compiled` 注册+`sprite.atlas.grid` operator 写 `from_grid`+asset_row 臂）：全链走通用机器（New Asset/Inspector/asset.set/保存/游戏 walk 白得）、与「引擎原生资产=第一等公民」哲学一致；代价=fork 一行（重制纪律在，T10 先例）+Vec\<URect\> 手编体验一般（operator 补）。B=editor operator 直写 .bsn 绕 New Asset 门（无 fork 改动；代价=New Asset 面缺一格+writer 特例+ReflectDefault 缺仍是部分补丁 apply 隐患）。C=模板 Rust 面（T15 hero.glb 形态）：验收词「可编辑」打折——**不作主选**。D=自定义桥接组件（SceneSpriteAtlas 内嵌切分参数+展开系统）：T16 决策 1-B 同构、60 行功能背一个模块 | **A**；fork 探针（`Default` derive 编译+往返测试）在 T2 首步；B 作为 fork 变更被否时的回落 |
| 5 | **过滤授权形态（SP4）** | A=**本轮不做面**：过滤是 per-asset sampler 且 png 重载重置（事实十），持久化面=meta/import 管线域（超边界）；book 注记现状+正道（全局默认/代码侧）+SP4 记档。B=图片资产卡 sampler 行（运行态改 Image.sampler）：画布即时红绿但**不持久**——「可保存可运行」字面不满足，假授权比无授权危险。C=扩 T18 texture.import .meta 挂 sampler（仅 processed 路径，plain png 主流链不覆盖=A12 邻域风险） | **A**；B/C 记 open-challenges 与 book 注记；矩阵如实以「无面」入三态表（诚实边界格，M4 的 alpha/mode 格不受影响） |
| 6 | **模板 2D 面（T20 模板域改动定性）** | A=**零模板改动**：Template::TwoD 现状基座（Camera2d+Sprite starter+3D 家具 lib）已满足「可运行」字面；M16 以现状为回归格；家具噪音（3D rig 相机空图）book 注记。B=模板 lib 2D 化分支（starter==TwoD 时跳过 CameraRig/物理 spawn）：干净但要动模板条件链+双形态测试翻倍。C=模板加 2D 示例段（sprite 移动+atlas 帧动画教学 ~40 行）：教学最完整，T12 教学密度纪律可承载 | **A 本轮**；C 作为可选项并入决策（主控可裁加，估时 +0.5 天）；B 记 T22 前置建议（tilemap 任务若定 2D 关卡模板则必做） |
| 7 | **PIE 2D 流送帧（SP7，GR8 同型）** | A=**T1 探针定案后分流**：文件路径态+快照态各一拍，忠实→M14 保留 PX；不忠实→M14 降级数值轨+SP7 记档（游戏窗口 truth 以 direct run 为准，T19 决策 4 口径）。B=一律数值轨不做探针：省半日但 SP7 悬置、丢「PIE=游戏」面证据 | **A**（探针在 T1，半日内；快照态 skip Camera2d 的静态证据已把不忠实概率调高——预期就是降级，探针是走流程不是走形式） |
| 8 | **A7/A9/A10 工具债前置评估** | A=**不前置，脚本自守**（同 T19 决策 6）：A7 五招入脚本+判红前相邻两拍探针；A9 gbrp settle+小响应体；A10 全交互腿 100% 缩放+PIE 真指针仅一腿；`$PHASE` 日志名直接吸收。B=先修 A7/A10：sprite 画布交互的指针驱动密度高（拖拽/点选），先修有收益；代价=两票均无立项方案、拖节奏 | **A**；真踩（拖拽腿反复假红）→按 MCP 优先原则现场立项小票，不整体前置 |

小定案（主控可否决）：缺陷编号 SP1-SP10（新发现自 SP11 续）；真机腿编号 L1-L12；
矩阵格 M1-M16；fixture 工程 `/Users/zhanglinbo/workspace/loop-mac/t21-sprite`
（Template::TwoD+remote 注入）；fixture 资产 `assets/{hero.png,sheet.png}`（脚本生成
纯色 png；sheet 四色 2×2）；流程脚本 `loop/qa/t21-live.sh`；报告目录
`loop/reports/t21*/`；分支 `loop/t21-sprite`；book 章 `book/src/user-guide/
sprites-2d.md`；Atlas kind id `sprite_atlas`（label "Sprite Atlas"）；
operator id `sprite.atlas.grid`；上游移植基点=nightly-2026-10-27 六 PR
（91fa6afe→10a53456 链序）。

---

## 六、风险与回滚

| 风险 | 概率 | 缓解 |
|---|---|---|
| **cherry-pick 冲突深于预期（12 文件重叠面）** | 中 | T1 首步试合探针半日定案；冲突 ≤ 机械级现场消解，语义级→决策 1 回落 B 路（估时 +3 天已在表）；六 PR 内部链序保持（#650→#657）减少上下文漂移 |
| **nightly 与 main 的隐性依赖（六 PR 引用中间 34 commit 的符号/行为）** | 中-低 | 编译探针实证（fork API 逐个 grep 已过第一轮）；`sprite_stage` 依赖的 `OpenScene2dRoot`/`Scene2dRoots` 等随 #650 自带；stage 测试族全绿=行为级验证 |
| **fork 变更（决策 4-A）波及面** | 低 | 变更=TextureAtlasLayout 加 Default 一行；`make-bevy-fork.ps1` 重制+全量编译+bean 往返单测；fork 纪律（T10）全程可回退（fork 目录 git 化管理） |
| **Vec\<URect\> 手编体验差（atlas 手调逐格矩形）** | 确定 | `sprite.atlas.grid` operator 承载主路径（网格切分是 2D 主流形态）；自由矩形手编=高级用法，book 注记；体验差记 open-challenges 不阻塞验收 |
| **SP7 PIE 2D 不忠实（预期态）** | 高（静态证据指向） | 决策 7 预案：M14 降级数值轨+direct run 为 truth（T19 GR8 同口径）；book 如实注记 PIE 2D 边界 |
| **W2 多根口径撞画布 framing 腿** | 低 | 真机腿单场景单根运行；撞面按 W2 归因记档不修 |
| **拖拽/点选腿假红（A7 家族+A10 邻域）** | 中 | 100% 缩放+五招自守+判红前相邻两拍；真踩→MCP 优先原则现场小票 |
| **上游测试族在 Mac 的环境差（stage 族窗口驱动）** | 中-低 | 上游 stage 测试与既有 `tests/stage/`（ui_stage 族）同框架同机先例；首跑失败逐件归因（环境差≠语义差），如实记档 |
| **staged release 冷编长** | 中 | export_wait 预算 1500s（t16 口径）；门前清磁盘（A6 家族）；export 单次（M15） |
| **模板 2D 工程的 3D 家具噪音干扰 M13/M16 判定** | 中 | 判定锚=Camera2d 画布内容（sprite 位姿 PX+BRP 读回），与 3D 相机画面正交；家具噪音 book 注记（决策 6-A 的已知边界） |
| Mac debug 无 RUST_BACKTRACE | 确定 | 全程不设（T11-T3 口径）；panic 形态证据=日志消息签名 |
| 门链与编辑器/游戏同窗互踩 | 中 | T12-T3 §九-7 纪律：门链单独跑 |
| 回滚 | — | 移植补丁=一组原子 cherry-pick（逐 commit revert）；授权面三小件独立（Atlas kind 注册/operator/asset_row 臂）；fork 一行独立 revert+重制；Anchor 面独立。零场景格式破坏（Sprite 组件本就 bevy 原生）、零协议变更、零既有 3D 链触碰（viewport_2d 改动全在 2D 世界分支路径）。建设面由定性表保障：引擎与场景壳零新建，交互主体是移植而非发明 |

---

## 七、与 T01-T20 已建设施的衔接

1. **T18（资产导入）=「导入」词的底座**：分类/落盘/缩略图/失败横幅/魔数先例全量复用
   （事实十一）；Sprite 域零新增导入面；A12/A13 邻域知悉入风险表。
2. **T06/T07（PIE/导出）=「可运行」通道**：M11 Stop 铁证=T06 链 2D 形态；M15 staged
   五点链=T12 格 9/T16 L6 第四次复用；N13 绕行口径照旧。
3. **T03（undo/脏标记）=交互建设的护栏**：#653/#657 的 gizmo/spawn 全走
   `CommandHistory`/`SpawnEntity` 既有命令面（上游本就如此设计）——M12 回归格。
4. **T12/T13（模板纪律/flow）=模板域边界**：决策 6 的 A 裁定=零模板改动；若后续裁 C，
   教学密度/`ConfigPlugin` 范式/hud.bsn 形态全有先例；T22（tilemap）若定 2D 关卡模板，
   决策 6-B 的模板 2D 化分支是前置建议。
5. **T19（GR8 先例）=SP7 的方法论**：PIE 流送帧忠实性探针+降级数值轨的完整先例；
   「数值主断言+通道内像素红绿」判据直接复用。
6. **T16（AU 系方法论）**：SP3 的 New Asset 门/ReflectDefault 陷阱与 T16 坑甲同源
   （`std_traits.rs:23` 约束已探明）；「标记/授权门」定性法=本方案定性表的直接来源；
   asset_row 扩展名臂=AU3 修复的同型第三例。
7. **T15/T20（fixture 与开箱验收形态）**：fixture 注入两行 sed/脚本生成资产/
   「开箱冷启」回归格=M16 的直接模板；`jd new`→warm build→run 链全套搬运。
8. **上游关系注记**：本任务移植的六 PR 是上游 2026-10-26 已合并的成品（#650-#657），
   移植即与上游保持同构，后续 loop 与上游再同步时冲突面最小；jackdaw_tilemap 等
   其余 34 commit **不吸收**（T22 届时按需独立评估）。
9. **对 T22-T25 的奠基**：T22（Tilemap——上游 nightly 的 jackdaw_tilemap crate 与
   tileset 管线已在标签里备好，届时决策「吸收 vs 参照」即本任务决策 1 的复用）；
   T23（材质覆盖——Sprite 的 ColorMaterial 面在其域）；T24（错误定位——SP1 修复后
   2D 域才有错误可定位）；T25（Live 调参——sprite 变换/颜色是白名单候选域）。
10. **分支与行号基线**：本方案行号基于 main 79ec1994（上游对照基于本地标签
    nightly-2026-10-27）；T21 从 main 拉 `loop/t21-sprite`；loop/ 目录随 git 旅行。

---

## 八、耗时预估

| 段 | 预估 | 大头 |
|---|---|---|
| T1 | 2-3 天 | 试合探针+六 PR 移植与冲突消解+3,300 行测试族跑绿+SP6 随行+两探针（决策 1/7） |
| T2 | 1.5-2.5 天 | fork 一行+Atlas kind 全链+grid operator+asset_row 臂+Anchor 九宫格+book 注记件+（决策 6-C 若裁 +0.5 天） |
| T3 | 1.5-2 天 | fixture+脚本+L1-L12+16 格判定+红证归档+book 新章+全量门 |
| 合计 | **5-7.5 天** | 本 loop 史上最大单任务（移植体量所致）；决策 1 回落 B 路时 +3 天浮动 |
