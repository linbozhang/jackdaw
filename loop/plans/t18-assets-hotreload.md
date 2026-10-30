# T18 资产导入与热重载闭环 — 实施方案

> 策划产物（2026-10-28，基于本地 main **7c3bdf3c**（T17 收官合入）全量只读调研：编辑器
> `src/asset_ingest.rs`/`src/hot_reload.rs`/`src/thumbnail.rs`/`src/project_window.rs`/
> `src/asset_index.rs`/`src/asset_files.rs`/`src/material_assets.rs`/`src/material_browser.rs`/
> `src/reference_image.rs`/`src/texture_import.rs`/`src/texture_files.rs`/`src/reference_audit.rs`/
> `src/reference_rewrite.rs`/`src/file_ops.rs`/`src/entity_ops.rs`/`src/launch.rs`/
> `src/inspector/{asset_row,file_card}.rs`/`src/prefab/watcher.rs`/`src/scenes/external_watch.rs`/
> `src/terrain/splat.rs`；`crates/jackdaw_runtime/src/{texture_import,lib}.rs`；
> `crates/jackdaw_bsn/src/apply.rs`；`crates/jackdaw_scene_types/src/model_import.rs`；
> `crates/jackdaw_scaffold/src/lib.rs` 模板 feature 链；fork `/Users/zhanglinbo/workspace/
> bevy-fork-pinned` 的 bevy_asset（io/source.rs、server/{mod,info}.rs、event.rs）、
> bevy_world_serialization（world_asset_spawner.rs）、bevy_image（image_loader.rs）、
> bevy_audio（audio_source.rs）实读；workspace `Cargo.toml`+`Cargo.lock`（jpeg 解码链考古）；
> `tests/prefabs/prefab_lifecycle.rs:683`、`tests/stage/{gltf_authoring,model_lod,lod_bar}.rs`；
> `loop/qa/manual.md`+`loop/qa/t16-live.sh`；buglist.md 全量资产域扫描。
> **零临时探针**——关键结论（file_watcher feature 链、spawner 的 Modified 语义、缩略图
> mtime 键、applied 锁、四 watcher 的事件种类面、jpeg feature 缺席）全是静态可复核事实；
> 唯一静态不可裁点（JPG 实际装载行为）以 Cargo.lock 依赖图三重旁证+T1 首步纯探针定案。
> 需求来源：`loop/plans/roadmap-game-dev.md` T18（第 32 行，T01-T17 已闭环）。
> **验收原文**（roadmap 第 32 行，逐字核实）：「**PNG/JPG/GLTF(GLB)/材质/音频优先；导入
> 选项/预览刷新/重导入/失败反馈。验收=外部改资产视口+Inspector+缩略图正确更新；坏文件
> 不崩不丢引用。**」
> **任务定性：混合型、验收型偏重（约 70/30 偏验收）**——T12/T15/T16 的「反转读法」在此
> 第四次适用且**反转得最彻底**：热重载链的四个层次**全部成晶**——①引擎层：workspace
> bevy `file_watcher` feature 已开（`Cargo.toml:231`）→编辑器 AssetServer watch 默认开
> （bevy_asset `lib.rs:369-371` 无 override 即 `cfg!(feature="watch")`=true）→外部改文件
> 同柄原地重载；②视口层：glTF 实例对 `AssetEvent::Modified` 做整个 despawn+respawn
> （fork `world_asset_spawner.rs:593-617`）；③编辑器自建层：**四个 notify watcher** 在岗
> （资产索引 walk 重导入/材质重载、prefab 缓存重解析（A6 票的测试主体）、开页文档外部
> 改动弹 reload 提示、Project 窗口目录树）；④游戏侧：`clear_modified_scene_roots` 场景
> 热重载机械成晶（T13 已消费，`jackdaw_runtime/src/lib.rs:592-620`）。真正的缺口是
> **三个窄门**：缩略图 tile 的 `applied` 锁+Project 窗口 watcher 不吃内容修改事件→「缩略图
> 正确更新」半边塌（**AR1**）；`AssetLoadFailedEvent` 全仓零接收端→「失败反馈」的作者态
> 半边塌（**AR3**）；JPG 被 import UI 摆在台上而解码 feature 从未开启（**AR2**）。
> AU6（坏音频 play 时 unwrap panic，T16 记档「T18 导入域领走」）在本任务点名吸收面内。
> 缺陷候选按 **AR 系**编号（Asset-Reload，避开 buglist R/Y/W/A/N 系与 T01-T17 各任务
> 编号系 U/I/F/C/PF/AN/AU），只记不修→主控裁定吸收面。
> 真机口径：**macOS（本机）**，bash+curl+jq 驱动编辑器 BRP 15703（`jackdaw/assets` 资产
> 清单通道+`jackdaw/audit` 审计通道+`jackdaw/screenshot` 视觉面，`src/remote/server.rs:
> 147-179`）；本任务核心动线是**外部进程改文件**——由 QA 脚本直接写盘（python3 生成 PNG/
> 手写 GLB/坏字节），编辑器只需被动响应，**零合成键鼠主链**（A7 家族咬不到主链，决策 7）；
> **勿设 RUST_BACKTRACE**（T11-T3 口径）；warn 形态扫描
> （`thumbnail|Failed to|failed to|UnresolvedTypes|cannot-apply`）入常备腿；
> **A6 家族隔离口径见 §一重叠表与 §六风险**（本任务 watcher 真机腿密度全任务史最高，
> 预算单独给+串行化+单触发源纪律）；**A9 自守不前置**（BRP 断言小响应体+settle 重试）。

---

## 0. 架构事实（核实结论，方案的地基）

**总判断：T18 不是「建热重载系统」——引擎 watch→同柄重载→视口重实例化的主干链、编辑器
四个域 watcher、材质重导入的「换值不换柄」协议、prefab/开页文档的外部改动响应，全部
在场且被既有测试覆盖；T18 的工作是把验收句的三个铁证（三面更新/坏文件双态/重导入）
的**触发面缺口**补上（内容修改事件不达缩略图、失败事件无接收端、JPG 无解码器），
然后把五类资产×三面的真机证据链跑实。** 十六条事实：

- **事实一：编辑器 AssetServer 的 watch 是开的——「外部改资产→引擎重载」的管线今天
  就活。** 三段链条：①workspace bevy 依赖 features 含 `file_watcher`（`Cargo.toml:231`），
  fork 内 `file_watcher = ["notify-debouncer-full", "watch", "multi_threaded"]`
  （fork `bevy_asset/Cargo.toml:14`）→`watch` feature 必然开；②bevy_asset 建
  AssetServer 时 `watch = self.watch_for_changes_override.unwrap_or(cfg!(feature =
  "watch"))`（fork `bevy_asset/src/lib.rs:369-371`），编辑器 `AssetPlugin` 只设
  `file_path` 不设 override（`src/launch.rs:122-126`）→watch=true；③默认资产源带
  300ms watcher（fork `bevy_asset/src/io/source.rs:303-307` `platform_default` 的
  `.with_watcher(get_default_watcher(path, 300ms))`），服务端热重载块在
  （`server/mod.rs:1944` 注释「The following code all deals with hot-reloading」）。
  文件一改→AssetServer 对该路径的全部活柄原地重载（同 AssetId）。**在案活证**：
  terrain splat 材质缓存系统 doc 明言「The editor build runs the asset file watcher,
  so editing a material's PNG raises `Modified` here」并消费
  `AssetEvent<Image>::Modified` 丢缓存（`src/terrain/splat.rs:700-727`）——引擎重载
  已经被产品代码依赖。
- **事实二：glTF 视口热重载=成晶（fork spawner 原生 Modified 语义）。**
  `AssetEvent::Modified { id }` 且该 id 已有 spawn 的实例→`update_spawned_instances`
  对每个实例「despawn_instance_internal + spawn_sync_internal + set_instance_parent_sync」
  （fork `bevy_world_serialization/src/world_asset_spawner.rs:593-600` 事件匹配、
  `:358-383` 更新体，注释自认「very heavy operation」）。编辑器摆放的模型是
  `GltfSource{path, scene_index}` 派生出 `WorldAssetRoot(Handle<WorldAsset>)`
  （`src/entity_ops.rs:252-289` 观察者，doc 明言「without the handle ever being written
  to the document」）→外部改 .glb→同柄 Modified→**实例整体重建、authored 实体不动**。
  「视口正确更新」的 glTF 半边是引擎送的。
- **事实三：Image 热重载=同柄换图，两个消费面自动跟随。** ReferenceImage 的材质
  `base_color_texture` 持 `asset_server.load` 的柄（`src/reference_image.rs:266-271`
  `reload_reference_render`），PNG 改→同 AssetId 重载→渲染面自动新图（宽高比只在
  首次解码时应用，`poll_reference_aspect` `:277-312`）；Inspector 文件卡预览
  `ImageNode` 持同一来源的柄（`src/inspector/file_card.rs:503-516` +
  `src/texture_files.rs:121-128` `load_thumbnail`=`asset_server.load`）→同样自动换。
  但文件卡的**文本行**（Path/Texture 描述/尺寸）只在选择变化或 `AssetPreviewState`
  变化时重建（`file_card.rs:216-228` `rebuild_on_preview_change`）——内容修改不触发，
  文本行陈旧是小缺口（AR4 附带格）。
- **事实四：编辑器自建四个 notify watcher，事件种类面各不相同——这是本任务定性表的
  骨架。** ①**资产索引 watcher**（`src/asset_index.rs:945-987`）：递归 watch assets，
  匹配 `Create|Remove|Modify(_)`（**:950-960，Modify 全 wildcard 含内容修改**）→
  `AssetScanPending`→walk 重扫；②**Project 窗口 watcher**（`src/project_window.rs:
  409-444`）：同递归 watch，但只匹配 `Create|Remove|Modify(Name)`（**:414-419——内容
  修改 `Modify(Data)` 被排除**）→`state.rebuild()`+`materials.needs_rescan`；③**prefab
  watcher**（`src/prefab/watcher.rs:1-30`）：watch 缓存中的 prefab 文件，150ms debounce
  （`:38`）+自家写入指纹豁免（`:268-280`）+稀疏捕获先于缓存更新（`:284-295`）→
  重解析+live 场景重 resolve——**A6 票的测试主体**（`tests/prefabs/prefab_lifecycle.rs:
  683` `prefab_file_change_triggers_reload`）；④**开页文档 watcher**
  （`src/scenes/external_watch.rs:1-40`）：hash 记录自家读写边界，外部改动弹 reload
  提示对话框。四 watcher 并存=真机腿的事件时序要多 watcher 共存的自觉（§六风险）。
- **事实五：材质/定义资产的重导入链=「换值不换柄」协议，成晶且有 unsaved 编辑门。**
  资产索引 watcher 触发 walk 后逐文件比对 mtime：变了→`card_has_unsaved_edits` 门
  （编辑中的卡不动，`:589-591`）→`reload_in_place`→`move_value` 用 `ReflectAsset`
  把新值 remove/insert 进**旧柄的 AssetId**（`src/asset_index.rs:464-507`）→一切持有
  该柄的面（材质球预览、笔刷、场景引用、缩略图 stage 的 `material_handle`
  `src/thumbnail.rs:769-783`）原地看到新值；文件没了→除非卡上有未保存编辑否则出索引
  关卡，柄保持活让既有引用继续渲染（`:563-580`+模块 doc `:540-543`）。材质浏览器随
  `resource_changed::<AssetIndex>` 重建 registry（`src/material_browser.rs:56-58`）。
  材质文件本身不走 AssetServer（`load_material_file` 手动读文件建柄，
  `src/material_assets.rs:314-334`）——所以引擎 watcher 对材质域**不适用**，
  这条索引链是材质唯一的重导入通路（这解释了为什么它必须存在）。
- **事实六：缩略图管线的机制层为「外部改文件」设计好了，但触发面断在两处。**
  机制层：缓存键=路径+mtime 纳秒（`src/thumbnail.rs:356-366`，mtime 进**文件名**所以
  陈旧 PNG 永不被误用）；`request` 对 mtime 变化自动失效重排队（`:221-232`）；失败按
  mtime 记账不重试、文件一改即获新尝试（`:211-216`，M12 钉死测试 `:1542-1559`）；
  「模型全装载失败→写 off 不吊死队列」测试在库（`:1437-1482`——T14 提过的 thumbnail
  写 off 测试）。触发断点：①tile 装上缩略图即 `applied=true` 退出逐帧工作
  （`:1305-1309,1327-1329`）——**永不复查 mtime**；②唯一能重建 tile 的 Project 窗口
  watcher 不吃 `Modify(Data)`（事实四②）。⇒ 外部改 .glb/.material：视口/Inspector
  更新而**缩略图 tile 永远停留在旧图**，直到某次 Create/Remove/改名顺带 rebuild
  ——**AR1 的完整机理**。`Thumbnails::forget` 全仓只有场景截图一处调用
  （`:1245`），模型/材质/预制体路径无人调用。
- **事实七：hot_reload.rs 名不符实——命名撞车要在教学里点名。** `src/hot_reload.rs`
  是**扩展 dylib** 热重载（watch 扩展构建产物库，`src/hot_reload.rs:1-7`「Loads
  extension builds made outside the editor」；File 菜单的 Hot Reload 开关
  `src/lib.rs:2366-2380` 控制的是它）。资产热重载没有同名开关（引擎 watch 恒开、无
  UI 面）——盘点表 61 行的旧读法（「`src/hot_reload.rs` 是扩展 dylib 热重载而非资产」）
  至今成立，本方案沿用。
- **事实八：游戏侧场景热重载机械成晶但默认 dormant——模板游戏不带 file_watcher。**
  `clear_modified_scene_roots` 消费 `AssetEvent::Modified|LoadedWithDependencies`
  清实例重 spawn（`crates/jackdaw_runtime/src/lib.rs:592-620`，doc 明言「Pair with
  Bevy's file_watcher feature to get hot reload … in the standalone game binary」）；
  T13 又交付 `respawn_on_scene_root_change`+`SpawnedSceneId` 按 AssetId 去抖
  （`loop/progress.md:251`，去抖键是柄身份「热重载不可误去抖」是 QA 亲读定论）。
  而模板游戏的 bevy 依赖只带 `["wav"]`（`crates/jackdaw_scaffold/src/lib.rs:2630-2634`），
  runtime features=模块+terrain+pie（`:2668-2680`）——**无 file_watcher** ⇒ 发货游戏
  不吃 watcher（合理设计），场景热重载是 dev 时手动开 feature 的能力。验收句的三面
  （视口/Inspector/缩略图）全是**编辑器进程**的面——游戏侧不进本轮验收矩阵（决策 6）。
- **事实九：五类资产的导入入口现状。** ①PNG/JPG/图片：拖放/粘贴→`classify` 认
  `png|jpg|jpeg|webp|bmp|tga` 为 Image（`src/asset_ingest.rs:29-34`）→拷进 assets+
  光标处生成参考图板（`:178-193`）；`entity.add.image` 走原生文件对话框
  （filter `png,jpg,jpeg,ktx2,bmp,tga,webp`，`src/reference_image.rs:133-142`）。
  ②GLTF/GLB：`entity.place_gltf`/拖放导入后摆放（`src/entity_ops.rs`），导入设置=
  模型 `.meta`（Unity 式 import settings，`crates/jackdaw_scene_types/src/model_import.rs:
  1-3`）持有 LOD levels（`:27-57`）+摆放级 override（lod_bar 面，`tests/stage/lod_bar.rs:
  189` 写 override 有测）；T10 教学面在库（`tests/stage/gltf_authoring.rs` 8+件：
  place/undo/纹理装载/hierarchy 恢复）。③材质：`.material.bsn`（每文件一个反射
  `StandardMaterial`，`src/material_assets.rs:1-24`；MATERIAL_KIND
  `src/definition_assets.rs:1339`）+texture set 检测与 layered_surface/foliage/water
  定义资产（`:1348-1354`）。④音频：`asset_row` 的 picker 认 `ogg|oga|wav`
  （`src/inspector/asset_row.rs:57,590-592`，T16 交付）；workspace+scaffold 双侧 wav
  feature（`Cargo.toml:236`+`scaffold lib.rs:2630-2634`，teaches 钉死 `:3749`）。
  ⑤音频外的解码 feature：fork 音频格式表 `mp3/flac/symphonia-wav` 等仍关
  （fork `bevy_audio/src/audio_source.rs:59-74` cfg 面）。
- **事实十：JPG 被导入 UI 摆上台而解码 feature 从未开启——AR2。** `bevy_image` 的
  JPEG 支持是 feature 门：`ImageLoader::extensions` 里 `ImageFormat::Jpeg` 挂
  `#[cfg(feature = "jpeg")]`（fork `bevy_image/src/image_loader.rs:33-34`），feature 链
  `bevy_image/jpeg → image/jpeg`（`bevy_image/Cargo.toml:28`）。而 workspace bevy
  features 全清单无 `jpeg`（`Cargo.toml:224-236`：bevy_feathers/bevy_scene/
  bevy_dev_tools/serialize/debug/bevy_remote/file_watcher/reflect_documentation/
  reflect_functions/wav），`bevy_feathers` 只连带 `png`（fork `bevy_internal/Cargo.toml:
  289`）。**Cargo.lock 三重旁证**：`image` crate（default-features=false，fork
  `bevy_image/Cargo.toml:74`）的直接依赖只有 `png`+`tiff`（`Cargo.lock` image 条目
  依赖表），`zune-jpeg` 仅作为 `tiff` 的依赖在链（tiff 条目依赖表）——image/jpeg 若
  开启则 `image` 必须直连 `zune-jpeg`。⇒ **`.jpg` 今天必被 ImageLoader 拒载**（无
  loader for extension），而 `classify`/pick filter 都在邀请用户放 JPG（事实九①）。
  真机腿以「拖一张 jpg→占位灰板+失败 warn」红证坐实，修复=workspace bevy features 加
  `"jpeg"`（一行，zune-jpeg 是轻依赖）。
- **事实十一：导入选项 UI 的现状=纹理两态+模型 LOD+sRGB 启发式，无通用 import
  面板。** 纹理：Inspector 文件卡 `Import` 行（"Compressed, mipmaps"/"Original file"）
  +`Compress`/`Original` 两按钮（`src/inspector/file_card.rs:561-612`
  `spawn_import_rows`）→`texture.import` op（`src/texture_import.rs:104-114`）写
  Bevy `.meta`（`write_import_meta :67`，meta 名 `TextureImportProcessor` 压缩管线，
  `crates/jackdaw_runtime/src/texture_import.rs:31-59`）；无 `.meta` 时由文件名启发式
  定 sRGB（`_albedo/_normal` 等后缀表，`src/texture_import.rs:35-53`）。模型：`.meta`
  LOD import settings（事实九②）。颜色空间显式开关、逐模型纹理翻转等**不存在**
  ——「导入选项」的验收按「既有两态可走通+重导入后选项仍生效」口径收（决策 8）。
- **事实十二：失败反馈的机制层分布。** ①**引擎失败语义**：本 fork 的 `AssetEvent`
  **没有 Failed 变体**（`Added|Modified|Removed|Unused|LoadedWithDependencies`，
  fork `bevy_asset/src/event.rs:50-58`）；失败走独立消息 `AssetLoadFailedEvent`/
  `UntypedAssetLoadFailedEvent{ id, path, error }`（`event.rs:30-36`、
  `server/mod.rs:1920-1941`）。②**重载失败保旧值=「不丢引用」的引擎底座**：
  `process_asset_fail` 只翻状态旗（`LoadState::Failed`+依赖树传播），**不从
  Assets 存储移除资产**（fork `bevy_asset/src/server/info.rs:685-712`）→重载失败时
  旧资产值与全部实例原地保留；spawner 只吃 `Modified`（事实二）→失败连实例重建都
  不触发。③**编辑器侧接收端**：`set_error_handler` 把系统 panic/error 转日志不退进程
  （`src/launch.rs:184,244-253`）；`UntypedAssetLoadFailedEvent` 的编辑器接收端
  **全仓 grep 零命中**——失败只有引擎日志一行，作者无状态栏/卡片提示（**AR3**）。
  ④图片域专用反馈已成晶：参考图 `LoadState::Failed` 时 warn 一次+灰板占位继续可选中
  （`src/reference_image.rs:288-312`）——AR3 的修法直接抄这个形态。⑤缩略图域专用
  反馈成晶：失败记档+每文件 warn 一次+不重试（事实六）。
- **事实十三：AU6（坏音频 unwrap panic）现状=编辑器被错误处理器兜住、游戏进程会
  崩。** fork 解码点：`Decodable::decoder` 对 `rodio::Decoder::builder()…build()` 的
  结果直接 `unwrap()`（fork `bevy_audio/src/audio_source.rs:96-103`，`:101` 是 unwrap
  行）——扩展名在册而字节坏/伪装时，**装载阶段无错**（AudioLoader 只存 raw bytes），
  **play 建 sink 那一刻 panic**。编辑器进程：系统 panic 被 bevy 错误处理器捕获存活
  （N13 实证「全部被 bevy 系统错误处理器捕获（编辑器存活）」，buglist:499），且
  T16 静音门让编辑器 sink 照建（`launch.rs:151-154` 乘 0 在建 sink 时）⇒坏音频实体
  在编辑场景里=每帧重 panic 重捕获的日志风暴；游戏进程（默认 handler）=崩。
  AU6/AU8 在 T16 结案清单里「如实留 T18」（roadmap :30 尾注）——本任务的裁定建议
  见 §五决策 1。
- **事实十四：审计三嘴+重绑定=「不丢引用」的可发现性半边，T05 已建。**
  `asset.audit` op（`src/reference_audit.rs:433-438`）+`jackdaw/audit` BRP 方法
  （`src/remote/server.rs:154`）+Missing References 清单（`asset.missing_list`，
  `:649`）+场景装载摘要行（`:499`）；findings 三类 Missing/Ambiguous/MachinePath
  （`:20-34`），审计覆盖「字段类型认资产路径」的全部字段（`takes_asset_path`
  泛化判定 `:288-292`）——五类资产的引用一网打尽。坏引用的 rebind 走
  `asset.rebind`（`:595`）。
- **事实十五：rename/move 的引用跟随=编辑器内操作成晶、外部操作按裁定只检测。**
  `file.move`/`file.rename` op 驱动 `follow_a_move`（`src/file_ops.rs:719,804`；
  `src/project_window.rs:2241,2313`）→AST 值替换改写全部引用文档+tab/卡片 retarget+
  索引迁移（`src/reference_rewrite.rs:482+` 模块 doc）。**外部（Finder）rename/move**
  ：watcher 只刷浏览器（事实四②的 Create/Remove/Name），引用不跟——这是 **T05 决策②
  的明文裁定**（「operator 侧同步重写，watcher 只检测报告」，`loop/progress.md:129`）
  ，不是缺口；外部改名的兜底=审计报告+Missing 清单 rebind。T18 矩阵把它记为
  「边界验证格」不记缺陷。
- **事实十六：QA 断言通道与 headless 锚现状。** 编辑器 BRP 已有 `jackdaw/assets`
  （glob 资产清单，`src/remote/server.rs:1541-1590`）、`jackdaw/audit`（结构化
  findings）、`jackdaw/screenshot`、`ui_tree`（面板行断言）——缩略图/审计/卡片的
  真机断言全有现成嘴；缩略图 PNG 落盘在 `<project>/.jackdaw/thumbnails/`（mtime 进
  文件名，事实六）——**缩略图更新的机械化证据=盘上 PNG 文件名变化+像素 md5 对比**
  ，不需要 GPU 断言。headless 锚：缩略图缓存规则/写 off/锁存 19 件纯逻辑测试在
  `thumbnail.rs:1355-1921`；资产索引重导入 walk 有 stage 先例
  （`src/material_assets.rs:1629-1777` 测试族直接调 `rescan_asset_index`）；
  A6 的 watcher 真件=`tests/prefabs/prefab_lifecycle.rs:683`。图片/模型域
  「外部写文件→watcher→重载」的 headless e2e 锚**不存在**（notify watcher 需真实
  文件系统事件，现有锚全是直接调函数）——T1 补一条真实 fs 事件锚（决策 3 附带）。

### 验收句逐词定性（矩阵化的前提）

| 验收词 | 定性 | 依据 |
|---|---|---|
| PNG/JPG | **PNG 成晶／JPG 缺口（AR2）** | PNG：导入（classify+参考图板）+解码（png feature 经 bevy_feathers）+热重载（事实三）全通；JPG：classify/pick filter 邀请导入但 jpeg feature 关、ImageLoader 拒载（事实十） |
| GLTF(GLB) | **成晶** | place_gltf+`.meta` LOD 导入设置（事实九②）+视口热重载（事实二）+缩略图管线（事实六机制层）；T10 教学面在库 |
| 材质 | **成晶** | `.material.bsn` 体系+「换值不换柄」重导入（事实五）+浏览器/卡随索引重建；材质域不走引擎 watcher 是设计而非缺口 |
| 音频 | **导入成晶/热重载半成晶/失败面缺口（AU6）** | picker 扩展名+wav 双侧 feature（事实九④）；引擎重载对 AudioSource 同样适用（事实一）但编辑器静音无听感面；坏文件 play panic（事实十三） |
| 导入选项 | **半成晶（范围裁定点）** | 纹理 Compress/Original+说明（事实十一）+模型 `.meta` LOD+sRGB 启发式在库；无显式 sRGB 开关/通用 import 面板——按「既有选项走通+重导入后仍生效」收口（决策 8） |
| 预览刷新 | **视口/Inspector 半成晶，缩略图缺口（AR1）** | 视口：gltf 重实例化+image 同柄换图（事实二/三）；Inspector：文件卡图自动换、文本行陈旧（事实三）；缩略图：机制层备好、tile `applied` 锁+watcher 事件面断（事实六） |
| 重导入 | **成晶（索引域）／引擎域成晶** | 材质/定义：walk→mtime 比对→unsaved 门→换值不换柄（事实五）；image/gltf/audio：引擎同柄重载（事实一） |
| 失败反馈 | **缺口（AR3）+域专用半成晶** | `UntypedAssetLoadFailedEvent` 无编辑器接收端（事实十二③）；参考图灰板 warn（④）与缩略图写 off（⑤）两域专用形态在库可抄 |
| 验收①外部改资产视口+Inspector+缩略图正确更新 | **半缺口（AR1 前置）** | 视口/Inspector 两面现成（真机腿未跑过）；缩略图面机制备而触发断（事实六） |
| 验收②坏文件不崩不丢引用 | **半成晶（AU6 吸收裁定+AR3 前置）** | 不崩：编辑器 error_handler+N13 实证捕获；不丢引用：process_asset_fail 保旧值+换值不换柄+文档存路径（事实十二②/十五）；反馈：AR3 缺口；AU6 panic 风暴待裁定（事实十三） |

---

## 一、缺陷候选（AR 系，只记不修→主控裁定吸收面）

| 编号 | 严重度 | 描述 | 证据 | 处置建议 |
|---|---|---|---|---|
| **AR1** | 🔴 | **外部内容修改不达缩略图/浏览器 tile**：Project 窗口 watcher 排除 `Modify(Data)`+tile `applied` 锁永不复查 mtime+`Thumbnails::forget` 无调用方——外部改 .glb/.material 后视口已新、tile 永旧（直到任意 Create/Remove/改名顺带 rebuild） | 事实四②/六全链 | **吸收（本任务建设主体）**。修向见决策 2：把内容修改事件引入 Project 窗口刷新+变更路径缩略图失效（debounce 防 rebuild 风暴） |
| **AR2** | 🔴 | **JPG 无解码器而导入 UI 邀请导入**：bevy `jpeg` feature 全链未开（workspace features/Cargo.lock 依赖图三重旁证），`classify`/pick filter 却收 jpg/jpeg——拖一张 jpg=装载失败灰板+「no asset loader」日志，作者无从知道是格式不支持 | 事实十全链 | **吸收（一行 feature+红绿腿）**：workspace bevy features 加 `"jpeg"`；模板游戏 bevy 依赖同步与否见决策 4 |
| **AR3** | 🟡 | **资产装载失败无作者态反馈**：`UntypedAssetLoadFailedEvent` 编辑器零接收端——外部改坏一个在用资产，重载失败静默保旧值（引擎日志一行），作者以为改成功了 | 事实十二①③ | **建议吸收**（验收词「失败反馈」的正主）：编辑器小系统读 untyped 失败消息→`status_bar::notify_warn` 一次/路径（参考图 warned 锁形态），文本含路径+「显示旧内容」语义；不改引擎 |
| **AR4** | 🟡 | **Inspector 文件卡文本行在重载后陈旧**：图/纹理卡 Path/Texture 描述/尺寸只在选择或 preview state 变化时重建；内容修改后 `ImageNode` 已新而文本行旧 | 事实三；file_card.rs:216-228 | **建议吸收（小件）**：AR3 的失败事件或决策 2 的变更信号顺带 `InspectorDirty` 该卡（`rebuild_on_preview_change` 同型）；主控可裁降级为记档 |
| **AR5** | ⚪ | **AU6 坏音频 play 时 unwrap panic（T16 移交）**：解码 `unwrap()`（fork `audio_source.rs:101`）——编辑器被错误处理器捕获存活但逐帧 panic 日志风暴；游戏进程默认 handler 会崩 | 事实十三 | **裁定面（决策 1）**：建议「吸收为编辑器侧导入校验探针（pick/import 时解码试解一次，坏文件 warn+拒写引用）+游戏侧残留 book 注记」；fork 修复否决（fork 纪律，T16 决策 2-C 先例） |
| **AR6** | ⚪ | **外部 rename/move 引用不跟随**：仅 Create/Remove/Name 事件→浏览器刷新，无 `follow_a_move`——引用断、audit 报 Missing | 事实十五；T05 决策②明文裁定 | **不吸收（设计边界）**：矩阵记「边界验证格」——外部改名后 `jackdaw/audit` 必报 Missing+Missing 清单可 rebind；book 注记「改名走编辑器」 |
| **AR7** | ⚪ | **纹理导入处理缓存孤儿积累**：TextureImportReader 按「源字节+meta」哈希落缓存文件（`texture_import.rs:115-163`），源文件反复改→旧 `.basis` 永不清；`.jackdaw/imported/` 随编辑期无界缓增 | 事实十一；runtime texture_import.rs:125-129 | 记档不修（低频低危）；book 注记「清 .jackdaw/imported 安全」 |
| **AR8** | ⚪ | **坏 GLB 的「首载失败」与「重载失败」双态差异未刻画**：重载失败保旧值有引擎语义背书（事实十二②），但**首载**失败（拖入前文件已坏）走 `PendingModelRoots` 等待链——`a_model_whose_source_went_while_its_root_waited_never_comes_on`（gltf_authoring.rs:144）只测了文件消失态 | 事实十二；tests/stage/gltf_authoring.rs:144-170 | 不吸收为缺陷：T2 真机腿 M 系补「先坏后修」红绿刻画腿，异常则立 AR9 |

统计：🔴 2（AR1/AR2，均为验收缺口的建设面）｜🟡 2（AR3/AR4）｜⚪ 4（AR5-AR8，AR5 为裁定面）。

### buglist 重叠表（资产/缩略图/导入/热重载域全量扫描）

| 条目 | 一句话 | T18 处置 |
|---|---|---|
| **A6**（buglist:455-457） | prefab watcher 满载 flaky（`prefab_file_change_triggers_reload`，tests/prefabs/prefab_lifecycle.rs:683）+磁盘高压家族——**T18 真机 watcher 腿密度全任务史最高，同族高发** | **隔离口径（§六风险第一条+决策 5）**：①真机腿全部**单一触发源**（每腿只写一个文件、写完显式 settle sleep≥2s>bevy 300ms watcher+索引 walk 周期）；②watcher 腿与门禁**不同窗**（T12-T3 §九-7 纪律）；③门前清磁盘照旧；④腿内断言预算单独给（10s 级），超时判 FAIL 不重试赌时序；⑤A6 维持「已定案环境票」放行口径不变，T18 不吸收其修复 |
| **AU6/AU8**（roadmap :30 尾注「如实留 T18」） | 坏音频 unwrap panic／音频加载失败静默 | **本任务点名吸收面**：AU6=AR5（决策 1 裁定）；AU8（静默不响）在编辑器静音门下无听感面，归 AR3 的失败反馈格覆盖（BRP 可断 load 状态） |
| W8 | drop 重复导入 assets 内文件 | **已修**（6ba0ce4b，buglist:329）——回归格 M 系拖放腿顺带复跑 guards 现有锚 |
| W7 | 资产索引 gone 检测 O(n·m) | **已修**（buglist:320-321 [x]）——本任务改索引 watcher 邻域时回归必跑 |
| Y31 | 内嵌资产 `#Name` 互引丢失 | **已修**（abf00a31 T05-T2，buglist:261）——T05 曾「备案 T18」的回落风险已结，无需动作 |
| R10 | 导出 staging 硬编码 assets 目录 | **已修**（ef353c57，buglist:73-78）——无动作 |
| W3 | 着色派生材质缓存永不淘汰 | ⚪ 记档：AR7 同族（编辑期无界缓存），不动 |
| W18 | 地形 yaw 导入不精确 | 无关（地形摆放域，非资产导入） |
| A7 | 真机驱动 6 腿工具债（对话框提交+字段行定位；T16 已并账第 6 腿=asset_row Pick 行定位） | **前置评估=不整体前置（决策 7）**：T18 主链动线是「脚本写盘+BRP 只读断言」，零对话框提交腿、零 Inspector 字段编辑腿；唯一沾边面=文件卡 ui_tree 行断言（只读，非交互驱动）——A7 咬不到；**吸取 stale-grep 教训**：`t18-live.sh` 的 warn 扫描随 `$PHASE` 日志名 |
| A9 | 游戏 BRP 间歇空响应 | **自守不前置（决策 7）**：本任务 BRP 用量中等（audit/assets/screenshot+ui_tree 全小响应体）；settle 重试+idle 探针+避开 scene.open/构建窗口（t16 口径）。游戏侧 BRP 本轮**零依赖**（验收三面全在编辑器进程）——A9 暴露面比 T16 还小 |
| A10/N13/N12 | PIE 指针／PIE drain panic／BRP 域界 | 无 PIE 主链（决策 6 把游戏侧移出矩阵）→A10/N13 咬不到；N12 口径照旧（编辑器侧 jackdaw 方法） |
| 其余 | R/Y/W 系均为 prefab/brush/chrome/键位域 | 无动作 |

---

## 二、验收矩阵设计

**两铁证×通道+导入选项横切=14 格主矩阵**。断言通道缩写：H=headless（root tests/
缩略图纯逻辑 19 件+索引 walk 先例+T1 新增 fs 事件锚）、R=真机编辑器 BRP 15703
（`jackdaw/assets`/`jackdaw/audit`/`jackdaw/status`/`ui_tree`）、PX=截图（PrintWindow
法）、FS=QA 脚本直接写盘（python3 生成/改写/破坏文件——「外部改资产」的字面驱动）、
MD5=盘上缩略图 PNG 文件名+像素对比（事实十六：mtime 进文件名，新缩略图必然新文件名）。

### 铁证①：外部改资产 → 视口+Inspector+缩略图正确更新

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| PNG | M1 | fixture 工程放 png→拖放成参考图板（R 断实体+PX）→脚本改写同路径 PNG（换色/尺寸）→视口板换图（PX 像素 diff）+文件卡预览换图（PX）+**AR4 红证**（文本行陈旧）→修后一致 | 视口/预览成晶（事实三）⚠️R 未跑；AR4 前置 |
| JPG | M2 | 拖入 jpg→现状红证（灰板+失败日志，AR2 修前）→**AR2 修复后**（feature 开）同 M1 全链绿 | 🔴AR2 前置；FS+R+PX |
| GLB | M3 | 摆放模型（place_gltf）→改写 .glb（几何变化：加一盒子节点）→视口实例重建（world.query 断新 mesh 数+PX）+缩略图 tile 更新（**MD5：新 mtime 文件名+像素 diff**）→AR1 红绿两段 | 视口成晶（事实二）；🔴AR1 前置缩略图半格；FS+R+PX+MD5 |
| 材质 | M4 | 建 .material.bsn（含纹理槽）→改写材质文件（base_color 变）→视口材质球/引用面换色（PX）+tile 更新（MD5）+浏览器列表原样（resource_changed 链） | 成晶（事实五）⚠️R；🔴AR1 前置缩略图半格；FS+R+PX+MD5 |
| 音频 | M5 | 场景带 AudioPlayer 指向 wav→改写 wav（同格式换内容）→R 断 AudioSource 资产重载（load 状态+无 panic 日志；编辑器静音门下无听感面如实注记） | 成晶（事实一）⚠️R；FS+R |
| 横切·重导入语义 | M6 | 材质改盘后 BRP 断**柄 id 不变**（`asset_index` 重导入换值不换柄的活证——`jackdaw/ui_tree` 或 status 侧写记录；对照：删除文件→柄活+卡关） | 成晶（事实五）⚠️R 活证未跑 |
| 横切·导入选项 | M7 | 纹理 Compress→`.meta` 落盘+file_card 显示 "Compressed, mipmaps"→**改源 PNG→重载后仍走压缩管线**（R 断 `.meta` 在+无回退日志）；模型 LOD：摆两层楼模型→`.meta` 生成→改动几何→LOD 设置仍生效（levels 面不塌） | 事实九②/十一 ⚠️R；FS+R+盘 |
| 横切·三面时序 | M8 | 一次外部写（M3 同款）→**单腿内三面同时断**：视口（PX）+Inspector（ui_tree 文件卡）+缩略图（MD5）全绿且互不依赖手工刷新——验收句的字面全称量词格 | 🔴AR1 前置；FS+R+PX+MD5 |

### 铁证②：坏文件 → 不崩不丢引用

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| 坏 PNG | M9 | 在用参考图的 PNG 写坏字节→编辑器存活（进程在+BRP 应答）+灰板占位/保旧图（PX）+warn 可见（参考图域 warn 已有；AR3 修后状态栏也有）→修好→恢复 | 参考图域成晶（事实十二④）；🟡AR3 前置状态栏半格；FS+R+PX |
| 坏 GLB | M10 | 在用模型 .glb 写坏→存活+**旧实例保留**（重载失败保旧值引擎语义，事实十二②）+缩略图写 off 不吊死（`thumbnail` warn 一次）→修好→重实例化（M3 复用）；**首载坏**（AR8 刻画腿）：坏文件直接 place→不入场景+无崩（红绿刻画） | 半成晶（AR8 刻画）；FS+R+PX+MD5 |
| 坏材质 | M11 | .material.bsn 写坏（非法 bsn）→存活+索引保旧值（`reload_in_place` 返 None 保旧）+warn 在案→修好→换新值 | 成晶（事实五）；FS+R |
| 坏音频 | M12 | wav 写坏字节→**编辑器存活**（AU6 panic 被捕获的现状实证+AR5 修后无 panic 的红绿对照）+引用（AudioPlayer 组件）原样→修好→恢复；决策 1 若裁探针则加「pick 坏 wav 被 warn 拒」腿 | AU6 现状红证；⚪AR5 裁定前置；FS+R |
| 不丢引用 | M13 | M9-M12 每格修好后：场景文档 SHA 不变（引用存的是路径，坏文件往返零写入——`GltfSource`/`ReferenceImage` 路径件面）+`jackdaw/audit` 零 Missing+实体/组件全数原样（重开验证） | 成晶（事实十二②/十五）；FS+R+盘 SHA |
| 边界·外部改名 | M14 | Finder 式脚本 mv 在用资产→浏览器刷新（Create/Remove/Name 链）+`jackdaw/audit` **必报 Missing**（AR6 边界验证格）+Missing 清单 rebind 回绿（T05 面） | 设计边界（AR6）；FS+R |
| 横切·warn 形态 | M15 | 全程扫描 `thumbnail|Failed to|failed to|UnresolvedTypes|cannot-apply|no asset loader`——零意外命中（修后 M2 的 jpg 命中消失即 AR2 红绿） | 脚本常备腿 |
| 横切·编辑器存活 | M16 | M9-M12 每段后 BRP `jackdaw/status` 应答+进程 pid 存活断言（「不崩」的机械化口径=BRP 活性+pid，非截屏） | 脚本常备腿 |

**矩阵统计**：🔴 修复前置 5 格（AR1×M3/M4/M8、AR2×M2）｜🟡 前置 3 半格（AR3×M9、
AR4×M1 附带、AR5 裁定×M12）｜⚠️ 真机腿缺口 9 格（成晶面未跑真机）｜边界验证 1 格（M14）。
T1 清源、T2 落判。

---

## 三、真机腿清单（Mac，bash+curl+jq+python3 写盘；T2 集中跑）

fixture 工程=`jd new` 出 `/Users/zhanglinbo/workspace/loop-mac/t18-assets`（T15/T16 同款
决策 6；模板自带 `assets/sounds/*.wav`+BGM 实体——T16 交付，M5 现成）。资产生成全脚本
化：python3 写 PNG（stdlib `zlib`+`struct` 手拼最小 PNG 或 `image` crate 不用——直接
字节级改写同尺寸 PNG 的 IDAT 最稳）、手写最小 GLB（T15 hero.glb 先例：合法 glTF 最小
段，T2 腿几何变化用「追加第二 primitive」或两份预制 .glb 轮换）、坏字节=好文件截断/
随机覆写头部四字节。流程脚本 `loop/qa/t18-live.sh`（t16-live.sh 形态：prep/editor/
export 相+leg/summary/cleanup trap+`$PHASE` 日志名 warn 扫描+A9 settle 重试助手）。

| # | 腿 | 通道 | 为什么必须真机 |
|---|---|---|---|
| L1 | M1 PNG 全链：拖放（ui_drag asset 区，A7 记数）→改写 PNG→三面断+AR4 红证 | FS+R+PX | 视口渲染与卡片 UI 是视觉结论 |
| L2 | M2 JPG 红绿：修前红证（灰板+日志）→修后全链 | FS+R+PX | feature 开关的装载行为 |
| L3 | M3/M8 GLB 三面同腿：改 .glb→单腿三断（视口 PX/卡 ui_tree/缩略图 MD5） | FS+R+PX+MD5 | 验收句全称量词正主；AR1 红绿两段 |
| L4 | M4 材质三面：改 .material.bsn→视口 PX+tile MD5+浏览器列表 | FS+R+PX+MD5 | 换值不换柄的真机活证 |
| L5 | M5/M6 音频重载+柄稳定：改 wav→BRP 断重载无 panic；删文件→柄活卡关 | FS+R | 引擎重载链编辑器侧活证 |
| L6 | M7 导入选项往返：Compress→改源 PNG→压缩管线仍走+`.meta` 在 | FS+R+盘 | 「重导入后选项仍生效」 |
| L7 | M9/M10 坏 PNG/坏 GLB：写坏→存活+保旧+缩略图写 off→修好→恢复（含 AR8 首载坏刻画） | FS+R+PX+MD5 | 坏文件双态正主 |
| L8 | M11/M12 坏材质/坏音频：写坏→存活+保旧+warn；AU6 红绿对照（AR5 修前 panic 日志在案/修后无） | FS+R | AU6 处置证据 |
| L9 | M13 不丢引用四件套：每坏文件格修好后文档 SHA+audit 零 Missing+重开原样 | FS+R+盘 | 验收句「不丢引用」铁证 |
| L10 | M14 外部改名边界：mv→audit 报 Missing→清单 rebind 回绿 | FS+R | AR6 边界的机械化 |

---

## 四、分任务拆解（T1/T2/T3）

### T1「缺口补齐轮」（建设小头：AR1/AR2/AR3/AR4+AR5 裁定落地；决策 1/2/3/4/8）

1. **首步探针（半日级，全静态或纯函数）**：①JPG 定案——root tests/ 单测直呼
   `ImageLoader` 类型注册面或 workspace 试装 `tests/fixtures` 下 1×1 jpg 断
   load_state（修前必红=AR2 钉死）；②决策 2 落地形态定案——读
   `ProjectWindowState::rebuild()` 的重建成本（tile 全量重 spawn vs 增量），选定
   事件通路（复用 asset_index watcher 的 pending 信号 vs project_window 自扩事件种类）。
2. **AR1（决策 2）**：①Project 窗口 watcher 事件面扩 `Modify(Data)`（或共享
   asset_index watcher 信号）→`state.needs_refresh`（debounce ≥300ms 防 rebuild
   风暴——外部工具连写时人眼可见节奏）；②`Thumbnails` 加「路径变更失效」入口：
   watcher 信号携带变更路径（notify `Event::paths` 可得）→对 model/material/prefab
   路径 `thumbnails.forget`；tile 侧靠 rebuild 重 spawn（`applied=false` 天然重走）。
   headless 锚：现有 19 件纯逻辑回归+新增「修改事件→forget→request 重排队」缓存
   单测；真机红绿=M3 两段。
3. **AR2（决策 4-A）**：workspace `Cargo.toml:224-236` bevy features 加 `"jpeg"`；
   teaches 断言（features 含 jpeg）；模板游戏**不同步**（决策 4：模板只保 wav，
   游戏 jpg 需求归 T20 验收时再议）——bsn_game fixture 的 Cargo.lock 若受 feature
   传播影响则刷新（T16 事实十五③同款注意）。
4. **AR3（决策 3-A）**：编辑器小系统读 `UntypedAssetLoadFailedEvent`（fork
   `bevy_asset/src/event.rs` 类型经 `bevy::asset` 预导出确认；不可达则回落
   `MessageReader<AssetEvent<Image>>` Removed/差分方案，探针定案）→
   `status_bar::notify_warn` 每路径一次（warned 集合，参考图 `:49` `warned` 形态）
   →文案含路径+「showing the previous content」；单测：假消息注入→warn 一次→重复
   不再 warn→文件恢复后清锁。
5. **AR4（决策 2 附带小件）**：决策 2 的变更信号或 AR3 事件→当前打开文件卡路径
   命中时 `InspectorDirty`（`file_card.rs:216-228` `rebuild_on_preview_change`
   同型一分支）。
6. **AR5 落地（按决策 1 裁定）**：建议 A=pick/import 校验探针——`asset_row` 音频
   pick 提交前+`file_card` 音频导入动作前，用已链接的解码器对文件试解一次（fork
   `rodio` 经 bevy_audio 可达性探针定案；不可达则探针降级为「非空+扩展名+头部魔数
   （RIFF/wav、OggS）检查」的纯字节校验）→坏文件 warn+不写引用；游戏侧残留 book
   注记。**不动 fork**。
7. **headless 新锚**：①「真实 fs 写→watcher→索引重扫→reload_in_place」e2e 一件
   （tempdir+真实 notify watcher+100ms 轮询窗，integration 档；A6 教训——锚独立
   tempdir、串行、预算 10s）；②AR1 缓存失效单测；③AR3 warn 锁单测。
8. **门禁**：fmt/clippy 全仓/单测/集成+teaches 全绿（fast 预期 2990→+n）。

**验收标准**：AR1 红绿（M3 两段 headless 预演+真机 T2 终判）；jpeg feature 红绿；
AR3 warn 三态在案；AR5 按裁定落地；headless 三锚+缩略图 19 件回归全绿；quick 四门。

### T2「真机矩阵轮」（验收主任务：M1-M16/L1-L10；决策 5/6/7）

1. fixture 工程+资产生成族+`loop/qa/t18-live.sh`（四相；**watcher 腿纪律**：单触发源/
   settle≥2s/预算 10s/超时即 FAIL 不赌——A6 隔离口径原文入脚本注释）。
2. L1-L10 全腿；M13 四件套逐格复核；AR2/AR1/AR3 红态先行归档（修前红证截图+日志）
   ——红态归档纪律（T16 首例）延续。
3. 缺陷只记不修：新发现按 AR 系续编（AR9 起），红证归档 `loop/reports/t18*/`。
4. QA 报告：14 格矩阵逐格判定+L 腿全证据+用户 30 秒清单草稿（拖张图改张图看三面、
   改坏一张看反馈）。

**验收标准**：M3/M4/M8（三面更新）全绿=铁证①；M9-M13（坏文件双态+SHA 铁证）全绿
=铁证②；M14 边界格红绿在案；M16 存活腿全过；四门禁绿。

### T3「终验 + 文档」

1. 14 格终态复跑+重点腿复跑（L3/L7/L9）。
2. book 新章 `book/src/user-guide/assets.md`（SUMMARY 排 prefabs/audio 之间）：
   导入面导览（拖放/粘贴/entity.add.image/place_gltf 五类入口表）、导入选项
   （纹理 Compress/Original+.meta 语义+sRGB 启发式+模型 LOD meta）、热重载教学
   （「编辑器开着改文件就行」+各面更新节奏+编辑器内改名=引用跟随、外部改名=audit
   兜底（AR6 边界））、坏文件双态（占位/保旧/反馈+「修好即恢复」）、缩略图缓存语义
   （mtime 键+`.jackdaw/thumbnails` 可清）；`prefabs.md`/`audio.md`/`asset-references.md`
   交叉引用；**hot_reload 撞名注记**（File 菜单 Hot Reload=扩展 dylib，事实七）；
   open-challenges 备选 7 条目按 T18 后现状改写。
3. buglist 处置：AU6 按决策 1 裁定打钩或改记；AR7/AR8 如实记档；roadmap T18 勾选、
   台账记行。
4. 终验门：全量门（fast/integration/doctests/docs/scaffold_e2e——日志全文复核；
   integration 唯一预期红=A6 定案口径隔离绿，照既往四任务口径）。

---

## 五、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **AU6 吸收裁定（T16 移交，AR5）** | A=**编辑器侧导入校验探针**（pick/import 时试解或魔数校验，坏文件 warn+拒写引用）：作者在最earliest时刻见到反馈、编辑器静音门下 panic 风暴源头（场景里已挂坏音频）仍存在但被 error_handler 兜住——诚实注记；零 fork 改动。B=fork `audio_source.rs:101` unwrap→返回静默 Decoder：根治双进程 panic；代价=**动 fork**（fork 纪律，T16 决策 2-C「扩 fork bevy_audio=否决」先例直接反对此路）+静默失败与 AU8 同型（比 panic 更难查）。C=编辑器侧播放门（坏 load 状态的 AudioPlayer 不建 sink 的小系统）：治编辑器风暴；代价=新系统+引擎播放面旁路语义要 book 注记。D=不修只记档：AU6 原样移交后续 | **A**；若 T2 真机实证编辑器 panic 风暴影响稳定性则升级 C（探针保留）——回落判据写进决策 |
| 2 | **AR1 落地形态（内容修改→缩略图/浏览器刷新）** | A=**扩 Project 窗口 watcher 事件面**（`Modify(Data)` 加入匹配+debounce 300ms+变更路径喂 `Thumbnails::forget`）：单文件改动、逻辑就近；代价=与 asset_index watcher 部分重复（两个 watcher 各吃各的面，现状本就如此）。B=**复用 asset_index watcher 信号**（它已收 Modify(_)，把 pending 广播给 Project 窗口+缩略图）：单一触发源；代价=跨模块耦合（project_window 依赖 asset_index 的内部资源语义）+asset_index 的 pending 无路径粒度要加字段 | **B 为主**（单一触发源+路径粒度顺带加）；A 作为 B 的耦合阻力大时回落；debounce 与重建成本探针在 T1 首步 |
| 3 | **AR3 反馈通路** | A=**读 `UntypedAssetLoadFailedEvent`**（fork 类型是否经 `bevy::asset` 预导出，探针半时定案）：语义正主（id/path/error 齐全）；不可达时回落=维护「在用资产 id→路径」差分读 `AssetEvent::*::Removed`+load_state 轮询（复杂度高一档）。B=只对 ReferenceImage/gltf 两域专用 warn（形态已在库）：零新消息依赖；代价=材质/音频域无反馈面，验收词「失败反馈」的覆盖窄 | **A**（探针先行，回落路径明确）；warn 每路径一次锁+恢复即清（参考图 warned 形态直抄） |
| 4 | **jpeg feature 范围（AR2）** | A=**只编辑器 workspace 开**：导入/视口/缩略图（缩略图不含图类 tile，无涉）全绿；模板游戏不开（发货游戏 jpg 资产仍需用户自加 feature——T20 示例游戏若用 jpg 再议）。B=编辑器+模板双侧开（scaffold `dependency_with_features(&["wav","jpeg"])`）：用户工程天然能装 jpg；代价=全体新游戏背 zune-jpeg 编译（轻，但「no rigs links neither」式的克制哲学反向）+模板 teaches/锁刷新面翻倍 | **A**；决策理由=T16 wav 开双侧是因为模板自带 sounds 资产，模板不带 jpg 资产故无此必要 |
| 5 | **A6 家族隔离口径（watcher 真机腿纪律）** | A=**纪律自守**（§一重叠表五条：单触发源/settle≥2s/预算 10s 超时判 FAIL/与门禁不同窗/门前清磁盘）：零前置成本；B=先修 A6（watcher 预算平台校准或测试域串行化）再开 T18：真机腿更稳；代价=A6 是基建票（测试负载形态）而非产品缺陷，修复方案未立项，前置拖节奏 | **A**；A6 维持放行口径；T18 不新增需 watcher 高并发的门禁件（新 headless 锚串行+独立 tempdir） |
| 6 | **游戏侧热重载是否进本轮范围** | A=**不进**（验收三面全是编辑器进程面；模板无 file_watcher 是发货克制的设计态；`clear_modified_scene_roots`+T13 切换原语已在库，book 注记「dev 时手开 feature 的路」）：范围守验收句字面。B=给 runtime/scaffold 加 dev 热重载模块（catalog 加条目带 file_watcher）：游戏侧热重载开箱；代价=预支 T20 后的域+「发货游戏不吃 watcher」设计注释反向（scaffold lib.rs:2668 现状） | **A**；B 记 open-challenges 一句话（T20 示例游戏若要「改场景即见」再立项） |
| 7 | **A7/A9 前置评估** | A=**不前置，脚本自守**：T18 主链=脚本写盘+BRP 只读+截图，零对话框提交腿、零 Inspector 交互腿（A7 六腿家族咬不到）；唯一 ui 交互=拖放一腿（ui_drag 现成通道，A7 记数绕行）；A9 面比 T16 更小（游戏 BRP 零依赖）+settle 重试照旧；`$PHASE` 日志名照 A7 教训。B=先修 A7 再开 T18：多一前置，对 T18 无收益 | **A**；真踩（拖放腿/ui_tree 行定位不稳）按 MCP 优先原则现场立项 |
| 8 | **「导入选项」本轮范围口径** | A=**既有选项走通+重导入后仍生效**（M7：Compress 往返+LOD meta 往返）：验收词按「选项存在且被重导入尊重」收；不做 sRGB 显式开关/通用 import 面板（现状启发式覆盖常见命名，book 注记命名约定）。B=加 sRGB 显式 UI（文件卡第三按钮写 meta 变体）：导入选项更完整；代价=meta 格式变体+加载侧匹配面+范围膨胀，验收句无此字面 | **A**；B 记 open-challenges（「导入选项扩展：sRGB 开关/纹理翻转/缩略图级」一句话） |

小定案（主控可否决）：缺陷编号 AR1-AR8（新发现自 AR9 续）；真机腿编号 L1-L10；
矩阵格 M1-M16；fixture 工程 `/Users/zhanglinbo/workspace/loop-mac/t18-assets`；
流程脚本 `loop/qa/t18-live.sh`；报告目录 `loop/reports/t18*/`；book 章
`book/src/user-guide/assets.md`；资产生成=t18-live.sh 内 python3（PNG 手拼/GLB 两份
预制轮换/坏字节=头四字节覆写）；缩略图证据根 `<fixture>/.jackdaw/thumbnails/`。

---

## 六、风险与回滚

| 风险 | 概率 | 缓解 |
|---|---|---|
| **watcher 真机腿 flaky（A6 同族）**——FSEvents 事件延迟/walk 周期叠加致 settle 不足 | 中-高（T18 腿密度最高+四 watcher 并存） | 决策 5 纪律五条全量入脚本：单触发源、settle≥2s（>bevy 300ms watcher+索引 walk 一个周期）、预算 10s 超时判 FAIL、与门禁不同窗、门前清磁盘；腿间互不共享触发文件 |
| `Modify(Data)` 引入 rebuild 风暴（外部工具连写/保存器 temp-swap 写两次） | 中 | debounce ≥300ms（决策 2）；重建成本探针先行（T1 首步②）；tile 重 spawn 是现有 rebuild 通路（非新路径） |
| jpeg feature 波及构建面（zune-jpeg 编译/lock 刷新/bsn_game fixture 锁） | 低-中 | 一行 feature+teaches 断言；lock 变更逐个核（workspace+fixture）；编译时长增量 T1 报告记档 |
| `UntypedAssetLoadFailedEvent` 类型不可达（未预导出） | 中 | 决策 3 探针先行+回落路径明确（差分/轮询方案）；回落也不堵 AR3 验收格 |
| 重载失败保旧值的「旧实例保留」在 gltf 子资产链不成立（依赖重载失败时子资产事件序） | 中 | M10 真机刻画先行；异常即立 AR9 记红证，语义面以引擎源码（info.rs:685-712）为准据写 book |
| AU6 探针的 rodio 可达性（bevy_audio 不 re-export rodio） | 中 | 探针降级为魔数校验（RIFF/OggS）——纯字节面零新依赖，决策 1-A 内置回落 |
| 材质重导入与引擎 watcher 双通路重入（材质不走 AssetServer 故无重叠；但 gltf 内嵌材质重载→实例重 spawn→ Inspector 引用刷新） | 低 | M4/M6 柄稳定断言即覆盖；异常记 AR9 |
| 缩略图 forget 误伤（路径粒度不准把未变文件重拍） | 低 | forget 只吃 watcher 报告的路径+mtime 键兜底（重拍代价=一次渲染，非正确性问题） |
| 拖放腿 ui_drag 不稳（A7 第 6 腿同族） | 中 | L1 备用通路=`entity.add.image`+path 参数（operator 直达，无坐标）；拖放腿标记「尽力而为+记数」（MCP 优先原则） |
| Mac debug 无 RUST_BACKTRACE | 确定 | 全程不设（T11-T3 口径）；panic 形态证据=日志消息签名 |
| 门链与编辑器/游戏同窗互踩 | 中 | T12-T3 §九-7 纪律：门链单独跑 |
| 回滚 | — | 五件各自独立可 revert（AR1=project_window/thumbnail 两文件的事件面+forget 入口；AR2=Cargo.toml 一行；AR3=一小系统；AR4=一分支；AR5=校验函数一文件）。全程零场景格式变更、零协议变更、零 fork 改动、零新插件组——建设面=事件接线+feature 行+反馈面，由定性表保障（四个热重载层次无一需要新机制） |

---

## 七、与 T01-T17 已建设施的衔接

1. **T05（引用稳定）=「不丢引用」的半边主体**：follow_a_move/asset.audit/jackdaw/audit/
   Missing 清单/asset.rebind 全在库（事实十四/十五）；M13/M14 直接复用其通道与守卫
   （`renaming_a_referenced_file_rewrites_its_referrers_and_nothing_else` 回归必跑）。
2. **T13（flow）=游戏侧热重载机械**：`clear_modified_scene_roots`+`respawn_on_scene_
   root_change`+AssetId 去抖已在库（事实八）；决策 6-A 只做 book 注记。
3. **T14（prefab）=watcher 响应面先例+A6 票来源**：prefab watcher 的 debounce/指纹
   豁免/稀疏捕获三件是 AR1 事件接线的形态参照；其缩略图 stage（Subject::Prefab）是
   M3/M4 MD5 证据链的载体；T14 交付的 thumbnail 写 off 测试（thumbnail.rs:1437）是
   M10 坏 GLB 格的 headless 锚。
4. **T16（音频）=AU6/AU8 移交方+静音门前置**：wav feature/scaffold 帮手/asset_row
   音频臂/M5 的 fixture 现成件全继承；AU6 处置证据回写 T16 结案清单（决策 1）。
5. **T15（动画）=GLB fixture 手艺**：hero.glb 手写先例=本任务 GLB 生成族的方法来源；
   其「自制 fixture 可复用为 T18」的原话（t15 方案决策 2-B）在此兑现。
6. **T04（原子写）/T08（asset.set+假脏 watcher）**：外部写盘腿与 hash 边界语义的
   底座；M13 文档 SHA 铁证=T04 形态复用；T08 的 `asset.set` 面是材质往返腿的编辑器侧
   对照。
7. **对 T19-T25 的奠基**：T19（画质一致性——纹理导入管线/压缩格式是其底座）；T20
   （示例游戏——五类资产齐备的 fixture 工程直接拼装，决策 4/6 的 jpg/file_watcher
   尾巴在该任务验收时再议）；T24（错误定位——AR3 的失败反馈面是其「错误可见」域的
   资产样本）。
8. **分支与行号基线**：本方案行号基于 main 7c3bdf3c；T18 从 main 拉 `loop/t18-assets`；
   loop/ 目录随 git 旅行（2026-10-28 迁移后），上游 PR 时按需剔除。

---

## 八、耗时预估

| 段 | 预估 | 大头 |
|---|---|---|
| T1 | 1.5-2 天 | 探针两件+AR1 事件接线（debounce/forget/rebuild 通路+缓存单测）+jpeg feature 链（lock 刷新）+AR3 反馈系统（探针/回落两案）+AR5 校验探针+headless 三锚 |
| T2 | 1-1.5 天 | fixture+资产生成族+脚本+L1-L10（watcher 腿纪律全量执行）+红证归档（决策 1 若裁 C +0.5 天） |
| T3 | 0.5-1 天 | 14 格终态+book 新章+全量门+AU6 结案回写 |
| 合计 | **3-4.5 天** | 视决策 2 落地形态与 watcher 腿稳定性浮动 |
