# T23 模型局部材质覆盖持久化 — 实施方案

> 策划产物（2026-10-28，基于本地 main **7f460caa**（T22 收官合入）全量只读调研：编辑器
> `src/material_overrides.rs`/`src/inspector/material_row.rs`/`src/material_browser.rs`/
> `src/material_assets.rs`/`src/scene_io/mod.rs`/`src/reference_audit.rs`/
> `src/reference_rewrite.rs`/`src/typed_values.rs`/`src/asset_failures.rs`/`src/status_bar.rs`/
> `src/entity_ops.rs`/`src/asset_index.rs`/`src/lib.rs`/`src/core_extension.rs`/`src/commands.rs`/
> `src/inspector/reflect_fields.rs`；`crates/jackdaw_scene_types/src/types.rs`；
> `crates/jackdaw_runtime/src/{lib,material_overrides}.rs`；`crates/jackdaw_surface/src/worn.rs`；
> `crates/jackdaw_prefab/src/model.rs`；`src/terrain/scatter.rs`；
> `crates/jackdaw_project_build/src/export.rs`+`tests/export.rs`；fork
> `/Users/zhanglinbo/workspace/bevy-fork-pinned` 的 bevy_gltf（loader/mod.rs GltfMaterialName
> 插入点）+bevy_world_serialization（world_asset_spawner.rs Modified 语义）；测试面
> `tests/stage/{material_overrides,material_row,gltf_authoring}.rs`+`tests/inspector/
> scene_data_cards.rs`+`tests/operators/scatter_ops.rs`；`loop/qa/manual.md` §7；
> buglist.md 全量材质/覆盖/GLTF 域扫描。**零临时探针**——关键结论（覆盖三层组件模型、
> by-material-name 语义、保存/重开 headless 有证、audit/rewrite 对 Map 值的双盲区、
> fork loader 无名材质不插名、fork spawner 重导入幸存链）全是静态可复核事实；唯一静态
> 不可裁点（Inspector 卡片 `[key]` 直编路径是否走通）以 T1 首步纯函数探针定案。
> 需求来源：`loop/plans/roadmap-game-dev.md` 第 40 行（T01-T22 已闭环）。
> **验收原文**（roadmap 第 40 行，逐字核实）：「**模型局部材质覆盖持久化：GLTF 子节点
> 材质覆盖+重名/重导入/失效路径处理。验收=局部换材质重开+导出保留；结构变化明确报告
> 不静默丢。**」
> **任务定性：验收型偏重（约 30/70）**——T12/T15/T18/T19/T20 的「反转读法」在此
> **第八次适用且反转得近乎彻底**：材质覆盖不是空白域——上游 PR #438（c405b220「Let
> placed models and scatter entries keep material overrides」，loop 开工前上游已合）交付了
> 全套三层机制：**模型层 `MaterialOverrides`+预制体实例层 `InstanceMaterialOverrides`+
> 运行时 dressing 插件**（编辑器与游戏两侧同一插件，`src/lib.rs:465`+runtime
> `lib.rs:350`），六个验收词中「局部换材质/重开保留/导出保留/重导入保留」的**机制层
> 逐词成晶**，且保存→重开→撤销→预制体→实例分层五面各有 headless 测试在库
> （`tests/stage/material_overrides.rs` 六件）。真正的缺口收窄为一件事：**「结构变化明确
> 报告不静默丢」的半边整体缺席**——①GLB 重导入后材质名变/删，失效的覆盖键**静默失效**
> （部分部件悄悄穿回原材质，无 warn 无清单）；②覆盖里的材质路径失效（文件删除/外部改名）
> **静默回落**（`material_of_reference` 返 None→give_back，无任何报告）；③审计与改名跟随
> 对覆盖路径**双盲**（`takes_asset_path` 只认 Handle 字段，BTreeMap 值不进
> `asset.audit` 候选、不进 `follow_a_move` 重写）——编辑器内改名一个被覆盖引用的材质文件
> 同样产生静默失效。建设面=报告系统一件+audit/rewrite 两个同根因特判，全部是窄口。
> 缺陷候选按 **MO 系**编号（Material Override，避开 buglist R/Y/W/A/N 系与 T01-T22 各
> 任务编号系 U/I/F/C/PF/AN/AU/AR/SP/TM/EG/GR），只记不修→主控裁定吸收面。
> 真机口径：**macOS（本机）**，bash+curl+jq 驱动编辑器 BRP 15703（`jackdaw/audit`
> 结构化 findings+`ui_tree`+`jackdaw/screenshot`）与游戏 BRP 15702（bevy 原生
> `world.query`，fixture 注入 `jackdaw_remote`，t15-live.sh:488-497 两行 sed 先例）；
> direct run 为主、PIE 腿免（A10/N13 绕行口径，决策 5）；**勿设 RUST_BACKTRACE**
> （T11-T3 口径）；warn 形态扫描
> （`material.override|holds no material|asset load failed|UnresolvedTypes|cannot-apply`）
> 入常备腿；GLB fixture 手作沿 T15 hero.glb 先例（两命名材质+两子节点，python3 手拼）；
> **A7 家族前置评估=不整体前置**（§五决策 6：主链全 operator 直达，唯一 Pick 腿用
> T16 已并账的「None 行+最近邻图标」相对配对法）。

---

## 0. 架构事实（核实结论，方案的地基）

**总判断：T23 不是「建材质覆盖系统」——覆盖的授权（operator+Inspector 材质行+材质
浏览器三面）、存储（场景文档 patch）、undo、重开恢复、预制体/实例双层、运行时 dressing
（编辑器视口与游戏进程同一插件）、导出携带，全部在场且大部分有 headless 测试；T23 的
工作=把验收句后半句「结构变化明确报告不静默丢」从零建起来（失效键报告+失效路径可
发现性+改名跟随），然后把五链×属性的验收证据链跑实。** 十六条事实：

- **事实一：覆盖的数据模型=两个组件、两层、键是 glTF 材质名。**
  `MaterialOverrides { materials: BTreeMap<String, String> }`（材质名→材质资产路径）挂在
  摆放的模型根实体上，`#[reflect(Component, Default, EditorCategory("Rendering"))]`
  （`crates/jackdaw_scene_types/src/types.rs:985-991`，doc 明言「by the model's material
  name」）；`InstanceMaterialOverrides` 同构，挂预制体实例根，「laid over the
  `MaterialOverrides` of the models it holds」（:993-999）。摆放模型本身=`GltfSource
  { path, scene_index }`（:899-904）。**键不是子节点名而是 glTF 材质名**（`GltfMaterialName`，
  fork 在 glTF 材质有名字时插到穿该材质的 mesh 实体上，`bevy_gltf/src/loader/mod.rs:
  2068-2069` `if let Some(name) = material.name()`）——「GLTF 子节点材质覆盖」的引擎
  语义=按材质名寻址，同名材质的多个子节点一次换装，这是现状事实不是缺陷（决策 4
  的输入）。
- **事实二：授权面三口全通，且都落同一个 undo 命令。** ①operator
  `material.override`（`src/material_overrides.rs:209-287`，`core_extension.rs:254` 注册）：
  参数 entity/name/material，name 空且选中的是根=换模型全部材质（:250-257），材质路径
  不存在即拒（:269-277 校验 `material_of_reference`），模型全无命名材质 warn 拒
  （:258-263）；②Inspector 材质行：选中模型部件（无文档节点的 unauthored 实体）Pick
  一个材质→`wear_until_reloaded` 识别模型归属→对模型根写 `SetMaterialOverrides`
  （`src/inspector/material_row.rs:136-153`）；③材质浏览器 `material.apply`（`MaterialApplyOp`，
  `src/material_browser.rs:1149`）：选中含模型部件时按部件的 `GltfMaterialName`（或根的
  全部名）写覆盖（:577-643），未落盘材质 warn 拒（:605）。三口共用
  `SetMaterialOverrides`（`src/material_overrides.rs:109-188`）：**自动选层**——模型根
  在预制体实例内则写实例层 `InstanceMaterialOverrides`，否则写模型层（:118-122
  `enclosing_instance`）；写组件+`sync_component_to_ast` 落文档 patch（:165-186，
  `src/commands.rs:2360`），清空时连 AST patch 一起摘（:153-163）；undo/redo 双向
  （:190-206）。
- **事实三：保存/重开=成晶且有 headless 铁证。** `MaterialOverrides`/`InstanceMaterialOverrides`
  是 `jackdaw_scene_types::` 前缀，不在保存跳过清单（跳过面=`jackdaw::` 前缀+七个引擎
  前缀+精确路径，`src/scene_io/mod.rs:40-69,72-97,169-187`）→照常落文档；穿在部件上的
  `MeshMaterial3d<StandardMaterial>` 及 layered/foliage/water 变体**明确跳过**（:87,
  :184-186）——文档只存覆盖意图不存派生结果的正确设计。在库测试
  `an_override_on_a_placed_model_saves_reloads_and_dresses_its_part`
  （`tests/stage/material_overrides.rs:139-188`）：operator 换装→save→盘上文档含
  `MaterialOverrides`+路径（:168-172）→重开→组件原样（:174-182）→重开后的模型再
  spawn 出的部件**再穿**（:183-187）。撤销面同测（:191-221，undo 后组件不在+部件穿回
  原材质）。
- **事实四：运行时 dressing=编辑器与游戏同一插件，「换值不换装」协议。**
  `MaterialOverridesPlugin` 在 runtime `render` feature 装入（`crates/jackdaw_runtime/src/
  lib.rs:344-353`，:350），编辑器进程同样装配（`src/lib.rs:465`）。PostUpdate 系统
  `find_models_to_dress`（`crates/jackdaw_runtime/src/material_overrides.rs:29-65`）的
  触发集合：`Changed` 两组件（:31-37）+`RemovedComponents` 双侧（:40-41）+**新部件
  `Added<GltfMaterialName>`**（:38,53）+**项目引用表/目录变更**（:48-52，
  `BsnProjectAssets`/`JackdawCatalog` is_changed）——最后一条意味着**材质文件修好/
  恢复后部件自动重新穿**（在库测试 `a_reference_that_resolves_later_dresses_the_part_
  when_it_does`，:361-389）。穿法：`dress_part` 按 `overrides_reaching`（模型层打底、
  实例层自内向外叠、最外层赢，:82-106）查当前部件的材质名，命中则 `WornMaterial::wear`
  并把原材质存 `ModelMaterial` 备份组件（:132-155）；查不到（无此键或引用解析失败）
  **静默 give_back**（:139-144→:157-163）。解析口 `material_of_reference`：编辑器查
  `BsnProjectAssets`（资产索引发布的路径→柄映射，`src/asset_index.rs:737-766`
  `publish_reference_map`），游戏查 `JackdawCatalog`（:68-78）。
- **事实五：游戏侧引用解析链完整。** 模板游戏启动 `load_asset_files` 把 assets/ 下全部
  `.bsn` 资产文件按**assets 相对路径**+唯一 stem 读进 `JackdawCatalog`
  （`crates/jackdaw_runtime/src/lib.rs:1684+`，walk 与键生成 :1776-1790）——覆盖里存的
  `materials/mossy.bsn` 形路径在游戏中直接命中；同名 stem 歧义进 ambiguous 清单不占
  `@stem` 键（:1791-1800）。材质文件体系：`.bsn` 一文件一反射材质
  （`src/material_assets.rs:1-24`），四穿面 `WornMaterial::{Standard,Layered,Foliage,Water}`
  （`crates/jackdaw_surface/src/worn.rs:20-25`，wear 换组件+重特化 :59-74）。
- **事实六：导出携带=机制成晶（真机腿未跑过）。** 导出把 assets 整树拷进 staged
  （`crates/jackdaw_project_build/src/export.rs:4-9` doc、`stage_into` :429-436），场景文档
  与材质文件随树走，覆盖 patch 在场景文档内=天然携带；`game.export` op 成品
  （`src/game_export.rs:143-149`）；staged 异目录启动 e2e 在库（`tests/export.rs:33-69`，
  含 `.jackdaw-pie`/`.bak` 排除 :68-69）。游戏进程=runtime render feature→事实四/五
  链路齐全。**缺的只是「带覆盖的场景在 staged 游戏里确实穿对」这一条真机证据。**
- **事实七：重导入保留=成晶（fork spawner 语义+编辑器派生观察者共同保证）。**
  外部改 .glb→引擎同柄重载→fork spawner 吃 `Modified`（debounce 去重，
  `bevy_world_serialization/src/world_asset_spawner.rs:593-601`）对每个已 spawn 实例做
  despawn+respawn（:358-383）——**despawn 只清 `InstanceInfo.entity_map` 里的 spawn 实体**
  （:262-271），authored 根实体（携带 `GltfSource`+`MaterialOverrides`+Transform）不在
  其中、原地幸存；新部件带新 `GltfMaterialName` 出现→事实四的 `Added<GltfMaterialName>`
  触发→按幸存的覆盖重新穿装。authored 根本身的重生链：undo/重开/换页都重插
  `GltfSource`→`derive_world_asset_root` 观察者重派生柄（`src/entity_ops.rs:246-289`），
  「without the handle ever being written to the document」。⇒**同路径重导入后覆盖存活**
  是结构保证；存活的前提=材质名仍匹配（不匹配的键进事实八的静默失效，本任务正主）。
- **事实八：「结构变化明确报告」半边整体缺席——三个静默面。**
  ①**失效键静默**：GLB 重导入后某材质名消失/改名，覆盖 map 里该键永存但永不命中，
  部件静默穿回原材质；全仓无任何「覆盖键不再匹配」的报告面（`src/material_overrides.rs`
  与 runtime `material_overrides.rs` grep stale/no longer/orphan/missing 零命中），OP 手册
  亦零覆盖腿（`loop/qa/manual.md` 材质域 grep 零命中——覆盖特性是 loop 开工前上游
  PR #438 带入，loop 七轮从未验收过它）。
  ②**失效路径静默**：材质文件删除/移走→索引出卡→`BsnProjectAssets` 无此路径→
  `material_of_reference` 返 None→静默 give_back（事实四）；恢复文件→自动重穿（:48-52）。
  ③**审计与改名跟随双盲**：`takes_asset_path` 只认 `ReflectHandle` 类型与
  `Option<Handle>`（`src/typed_values.rs:23-39`）——`BTreeMap<String,String>` 不是
  Handle→审计扫描器对 Struct 字段按字段类型判定收不收（`src/reference_audit.rs:281-300`，
  `takes_path` :288-292；唯一特判是 IsA 的 source :280,290）→覆盖路径**不进
  `jackdaw/audit`/`asset.audit`/Missing 清单**；改名跟随同根因：`scan_value`/`rewrite_value`
  的 Map 臂把**Map 自身类型**当值类型传下去（`src/reference_rewrite.rs:171-176` scan、
  :392-396 rewrite），非 Handle→`follow_a_move` 不重写覆盖里的路径——**编辑器内改名
  一个被覆盖引用的材质=静默产生失效路径**（对比：Handle 字段与 `@name` 引用都会被
  重写，:359-363 守卫）。⇒「失效路径处理」与「明确报告」的正主，一次特判（事实十五）
  +一个报告系统（事实十六）可闭合。
- **事实九：「重名」一词的现状语义三层。** ①**同名多部件**：一个材质名被多个子节点穿
  →一个覆盖键换装全部部件（by-design，事实四 dressing 按名寻址；`model_material_names`
  排序去重，`src/material_overrides.rs:51-65`）；②**覆盖键冲突**：BTreeMap 同键后写覆盖
  前写，operator/undo 语义天然一致（:124-134）；③**实例层同名**：实例覆盖键与模型层
  键同名时实例赢（`overrides_reaching` 自内向外 extend，runtime :97-105；在库测试
  `an_instances_own_override_wins_over_its_prefabs`，tests/stage:323-379）。真正的边角=
  **无名材质**：glTF 材质无名字→fork 不插 `GltfMaterialName`（事实一）→该部件**不可被
  任何覆盖寻址**（`dress_part` 无名早退，runtime :133-138）；且 operator 对「选中无名
  部件、name 空」的场景会**静默扩大到模型全部命名材质**（`src/material_overrides.rs:
  252-255` `unwrap_or_else(|| model_material_names(world, root))`）——用户点一个部件却
  换了整模型的材质，语义陷阱（MO4）。
- **事实十：覆盖的第三张脸=预制体与散布域，全部有测试在库。** 预制体打包携带模型层
  覆盖（`a_models_overrides_survive_packing_into_a_prefab…`，tests/stage:280-320）；
  实例层只记改过的键、其余跟随预制体文件（`an_instance_keeps_following_the_prefab_
  entries_it_did_not_override`，:412-482，prefab watcher 重载链）；prefab 缩略图模型解析
  读覆盖 map（`crates/jackdaw_prefab/src/model.rs:108-121`）；地形散布条目把模型的覆盖
  一起带进存储再带回（`src/terrain/scatter.rs:1532,1642,1769,1782`；`tests/operators/
  scatter_ops.rs:455-482,484,512`）。T23 矩阵只需回归这些面的代表格，不新建设。
- **事实十一：Inspector 卡片面。** 两覆盖组件有 EditorCategory("Rendering")→Inspector 出
  现数据卡（`tests/inspector/scene_data_cards.rs:42-53,68-84` 钉死）；卡的 Map 字段走
  `reflect_fields` 的 Map 臂渲染成 `{ N entries }`+逐键行（`src/inspector/reflect_fields.rs:
  194-230`），值行是通用字段行——**直编路径文本走 `field_edit_commit` 通用链、无
  材质存在性校验**（对比材质行 Pick 面 `material_named` 验存在，material_row.rs:96-99,
  142-145）；`[key]` 形式的字段路径在 commit/AST 侧是否走得通静态不可裁（W23 前科
  在 prefab delta 域，已修 8f8581f6；通用域未证）——T1 探针定案（MO5）。
- **事实十二：失效加载的报告形态刚在 T18 建成，可直接抄。** `asset_failures` 模块
  （`src/asset_failures.rs:1-19` 模块 doc 自述 AR3）：`UntypedAssetLoadFailedEvent` 的
  编辑器监听端，**每 (path, mtime) 一次**的状态栏+日志 warn（:30-47 锁、:65-90 报告体，
  `status_bar::notify_warn` :140）——「一次锁靠换键自清，文件恢复零簿记」的形态就是
  覆盖失效报告的模板（事实十六的落点参照）。
- **事实十三：审计通道成品。** `asset.audit` op+`jackdaw/audit` BRP 结构化 findings
  （`src/remote/server.rs:154,593-615`）+Missing/Ambiguous/MachinePath 三类
  （`src/reference_audit.rs:20-34`）+`asset.missing_list` 清单+`asset.rebind` 重绑——
  覆盖路径一旦被收录为候选（事实八③特判），Missing 判定、清单、rebind 全部免费获得；
  注意 A11（buglist:469）：rebind 目前只改文档层、活世界组件不随动（newtype 组件
  世界侧粘性）——覆盖路径 rebind 后的活世界刷新依赖事实四的**引用表变更自动重穿**
  （`BsnProjectAssets` is_changed），两机制互补，A11 的粘性面对覆盖域大概率被
  `publish_reference_map` 重扫自动绕开（真机腿刻画，异常记 MO）。
- **事实十四：GLB 消失路径。** `GltfSource.path` 指向的 GLB 文件没了→`PendingModelRoots`
  等待链挂起不 spawn（`src/entity_ops.rs:109-135`；在库测试
  `a_model_whose_source_went_while_its_root_waited_never_comes_on`，
  `tests/stage/gltf_authoring.rs:144`）；`GltfSource.path` 是 String 字段同样不被审计收录
  （事实八同根因）——模型级失效与覆盖级失效共享「审计盲区」，本任务的特判若顺手
  把 `GltfSource.path` 一并收录（is_source 同款第二特判），模型失效也获得 Missing 报告
  （决策 2 附带项）。
- **事实十五：audit/rewrite 特判的最小形态=IsA 先例同款。** 审计侧：Struct 臂已有
  `is_source` 特判先例（`reference_audit.rs:280,290`，一个布尔+一个类型路径比较）——加
  「`data.type_path ∈ {两覆盖类型路径}` 时 `takes_path` 恒真」一个分支（~5 行），
  `strings_under`（:349-366）已能深入 Map 值收字符串；重写侧：`scan_struct`/`rewrite_struct`
  把「结构体类型路径是否覆盖类型」作为一个下传标志（~15 行+两处调用点）。**不动
  `takes_asset_path` 本体**（它服务 Handle 字段拼写语义，改它会波及全仓字段落盘形态）。
- **事实十六：报告系统的最小形态=编辑器侧比对小系统。** 触发集合与
  `find_models_to_dress` 同型（事实四）但**只读比对不穿装**：对每个持覆盖的模型根，
  `stale = 覆盖键集 − 当前子树 GltfMaterialName 集`，`unresolved = 覆盖值中
  material_of_reference 返 None 者`；新出现的 (根, 键/值) 以 (entity, String) 为键记一次
  （`asset_failures` 的 HashSet 锁形态，事实十二），`status_bar::notify_warn`+`warn!`
  各一条，键消失自清；放 `src/material_overrides.rs`（编辑器 crate 已依赖全部类型，
  ~80 行+单测）。**放编辑器不放 runtime**：runtime 报告会进游戏进程日志（噪音），
  且状态栏是编辑器 chrome（决策 1）。

### 验收句逐词定性（矩阵化的前提）

| 验收词 | 定性 | 依据 |
|---|---|---|
| 局部换材质 | **成晶（真机腿未跑）** | operator+材质行 Pick+浏览器 Apply 三口全通、同一 undo 命令、材质存在性校验在（事实二）；headless 六件在库 |
| 重开保留 | **成晶（headless 有证）** | 保存不跳过+文档带 patch+重开恢复+再穿，tests/stage:139-188 铁证；真机 R 通道未走过 |
| 导出保留 | **机制成晶/真机未证** | assets 整树拷贝+覆盖 patch 在场景文档+游戏侧插件/目录链齐全（事实五/六）；「staged 游戏穿对」的真机证据缺 |
| 重导入保留 | **成晶（机制）/真机未刻画** | fork spawner 只重建 spawn 子树、authored 根幸存+`Added<GltfMaterialName>` 再穿（事实七）；「改 GLB 几何/加盒子不丢覆盖」需真机刻画腿 |
| 重名处理 | **半成晶** | 同名多部件/键冲突/实例同名三层语义清晰且有测试（事实九+事实十）；**无名材质部件不可寻址+operator 扩大化陷阱=缺口（MO4）** |
| 失效路径处理 | **半缺口（MO2/MO3）** | 失效→静默 give_back（事实四）；恢复→自动重穿（成晶半边）；但审计不收录、编辑器改名不跟随——失效**不可发现**（事实八②③） |
| 结构变化明确报告 | **缺口（MO1，本任务正主）** | 失效键/失效路径均无任何报告面（事实八①）；AR3 的 (path,mtime) 一次锁形态在库可抄（事实十二） |
| 「不静默丢」 | **缺口（MO1/MO2 合力）** | 数据面覆盖条目确实不丢（文档永存），丢的是**可发现性**；报告+审计双面补齐即闭合 |

---

## 一、缺陷候选（MO 系，只记不修→主控裁定吸收面）

| 编号 | 严重度 | 描述 | 证据 | 处置建议 |
|---|---|---|---|---|
| **MO1** | 🔴 | **覆盖键结构变化零报告**：GLB 重导入后材质名改名/删除，失效键静默存留、部件静默穿回原材质；无 warn、无清单、无审计条目——验收句「结构变化明确报告不静默丢」的正主 | 事实八①；全仓 grep 零命中 | **吸收（本任务建设主体）**：决策 1 报告系统（stale 键+unresolved 值，(根,键) 一次锁，恢复自清） |
| **MO2** | 🔴 | **覆盖路径不进审计**：`takes_asset_path` 不认 BTreeMap 值→`MaterialOverrides`/`InstanceMaterialOverrides` 里的路径不出现在 `jackdaw/audit`/`asset.audit`/Missing 清单——失效路径不可发现；同病：`GltfSource.path` 也不被审计（模型文件失效同样静默） | 事实八③/事实十四；reference_audit.rs:288-292+typed_values.rs:23-39 | **吸收（建设主体第二件）**：决策 2 两类型路径特判（IsA 先例同款）；`GltfSource.path` 是否顺带收录入决策 2 |
| **MO3** | 🟡 | **编辑器改名/移动不跟随覆盖路径**：`follow_a_move` 的 scan/rewrite Map 臂不识别覆盖类型→编辑器内 rename 一个被覆盖引用的材质文件，覆盖静默指向旧路径（失效而不自知）——与 MO2 同根因 | 事实八③；reference_rewrite.rs:171-176,392-396 | **吸收（MO2 同一改动面）**：决策 2 特判同时下传 rewrite 侧；guards 既有「重写不影响无辜」回归必跑 |
| **MO4** | 🟡 | **无名材质部件不可寻址+operator 扩大化陷阱**：glTF 材质无名字→无 `GltfMaterialName`→部件永不可覆盖（fork loader :2068 只在有名时插）；且 operator 对「选中的部件无名、name 空」静默扩大到模型**全部**命名材质——点一个部件换全模型 | 事实九；src/material_overrides.rs:252-255 | **裁定面（决策 4）**：建议 B=扩大化改 warn 拒（行为变更面小、语义诚实）或 A=只 book 注记+报告系统附带计数 |
| **MO5** | ⚪ | **Inspector 覆盖卡直编路径无校验**：Map 值行走通用 `field_edit_commit`，可写不存在的材质路径（Pick 面有 `material_named` 校验、卡面没有）；`[key]` 字段路径能否走通 commit/AST 静态不可裁 | 事实十一；reflect_fields.rs:194-230+commands.rs:211 | **记档+T1 探针定事实**（决策 7）：走通且无校验=记档（正门是 Pick 面）；走不通=卡片值行只读属现状边界，一并记档 |
| **MO6** | ⚪ | **多模型预制体实例的覆盖死角**：`model_root` 对「实体下 0 或 2+ 个模型」返 None（src/material_overrides.rs:44-47）→选实例根本身 Apply 时既不写实例层也不写模型层（wear_on_meshes 的 targets 分支对无材质实体静默跳过，material_browser.rs:592-600）——多层实例的覆盖只能逐模型下钻 | 事实九；material_browser.rs:592-600 | **记档不修**（低频+下钻通路在）；book 注记 |
| **MO7** | ⚪ | **失效键条目永不清除**：即使 MO1 报告落地，失效键仍永存文档（下次重导入若同名材质回归会复活）——「报告后由谁清」无语义 | 事实八①+事实十六 | **决策 3**：建议 A=只报告+手动清（`material.override material=""` 既有通路）；自动清=验收句反面否决 |

统计：🔴 2（MO1/MO2，均为「明确报告/可发现性」的建设面）｜🟡 2（MO3/MO4）｜⚪ 3（MO5-MO7）。

### buglist 重叠表（材质/覆盖/GLTF 域全量扫描）

| 条目 | 一句话 | T23 处置 |
|---|---|---|
| **A11**（buglist:469） | 资产 rebind 只改文档层，活世界组件不随 AST 重绑定同步（newtype 组件世界侧粘性） | **关联+绕行**：覆盖域的 rebind 后活世界刷新走事实四「引用表变更自动重穿」（`BsnProjectAssets` is_changed→全 overridden 重穿），大概率自动绕开粘性；MO2 落地后 M 系加一条「rebind→重穿」刻画腿，若粘性真踩=红证归 A11 不修（A11 已是独立小任务） |
| **A12**（buglist:473） | 经 Basis/BC7 重载过的图片 GPU 面冻结（AR9 渲染侧） | **知悉**：覆盖矩阵的材质纹理腿用**无 .meta 的 plain 纹理**（A12 只咬带 meta 的），不吸收不回避 |
| **A13**（buglist:477） | `.jackdaw/imported/` 孤儿缓存 | 无关（覆盖域不触 texture_import）；fixture 纪律=不用 Compress 档 |
| **W3**（buglist:299-300） | 着色派生材质缓存永不淘汰 | 无关（视口着色模式域）；记档不动作 |
| Y31/W23/W8 | 内嵌 `#Name` 互引（已修）/prefab delta 清除（已修）/重复导入（已修） | 已结案无动作；W23 修复（8f8581f6 叶移除）是 MO5 探针的旁证——点路径清除在 prefab 域已通，通用域待探针 |
| **A7**（buglist:459） | 真机驱动工具债（对话框提交+字段行定位+截图同帧 flake+陈旧 grep） | **前置评估=不整体前置（决策 6）**：主链全 operator 直达（material.override/material.apply/scene.save/game.export）；唯一材质行 Pick 腿=T16 已并账第 6 腿同族，用「None 行+最近邻图标」相对配对法+记数；截图只承担视觉格（T19 像素助手库在库可做换装前后像素 diff）；warn 扫描随 `$PHASE` 日志名 |
| **A9**（buglist:502） | 游戏 BRP 间歇空响应 | **自守不前置（决策 6）**：游戏侧断言用小响应体（单组件过滤 `world.query`）+settle 重试+idle 探针+避开 scene.open/构建窗口（t15/t16 口径） |
| **A10**（buglist:465） | PIE 指针转发缩放布局失灵 | **PIE 腿免**（决策 5）：覆盖域验收不依赖 PIE 交互，direct run 为主 |
| **A14**（buglist:481） | ui_tree 不暴露 Display::None/hover | **知悉**：覆盖卡折叠态格不用 ui_tree 空态判据（A14 洞），改走 `world.get_components` 组件断言+盘上 SHA；若本轮需要 ui 空态格再按 MCP 优先原则现场立项 |
| N12/N13 | BRP 域界/PIE drain panic | 照旧口径：编辑器侧 jackdaw 方法、游戏侧 bevy 原生；PIE 腿免=N13 不暴露 |
| 其余 | R/Y 系 prefab/brush/chrome 域 | 无动作 |

---

## 二、验收矩阵设计

**两铁证×通道=13 格主矩阵**。断言通道缩写：H=headless（tests/stage 六件+T1 新增报告/
特判单测）、R=真机编辑器 BRP 15703（`jackdaw/audit`+`world.get_components`+ui_tree 只读）、
G=真机游戏 BRP 15702（bevy 原生 `world.query`，fixture 注入 jackdaw_remote）、
FS=QA 脚本直接写盘（python3 手拼/改写 GLB、删材质文件）、PX=截图（`jackdaw/screenshot`
+T19 像素助手库换装前后 diff）、盘=场景文档/导出包盘上事实（SHA+grep）。

### 铁证①：局部换材质→保存→重开→导出→重导入 五链保留

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| 五链主干 | M1 | 摆放两材质名 GLB（Rock/Trim）→operator 换 Rock→**PX 视口换装**（像素 diff）→Save→文档含 patch+路径（盘）→**重开**四件原样（R 组件断言+PX 仍换装）→`game.export`→staged 异目录启动→**G 断部件穿新材质**（catalog 解析+MeshMaterial3d 柄对上） | 🔴MO 修复不前置（成晶面）；H 已证（tests/stage:139-188）；R+G+PX+盘（T07/T20 形态） |
| 材质资产引用 | M2 | 四穿面各一腿：覆盖目标分别指 Standard/Layered/Water 材质文件（Foliage 记档不跑）→换装/重开/导出三态柄一致 | 成晶（WornMaterial 四态，事实五）；H+R+G |
| 子节点名匹配 | M3 | 同名材质双部件：一键换装两部件同变（by-name 语义活证）+另一名部件不动；部分无名材质部件：不可寻址红证（**MO4**）+operator 扩大化行为刻画 | 半成晶；H+R+PX |
| 多子节点/多层 | M4 | 预制体链回归格：pack 携带覆盖+实例层赢+实例跟随未覆盖键（tests/stage 三件转真机抽查一腿）+散布条目带回覆盖（scatter_ops 对应格抽查） | 成晶（事实十）；H 在库+R 抽查 |
| 失效路径·外部删 | M5 | 删除被覆盖引用的材质文件→部件**静默穿回**（MO2 红证现状：`jackdaw/audit` **零** Missing 条目=盲区实证）→**MO2 修后**：audit 报 Missing+状态栏 warn→恢复文件→自动重穿（成晶半边绿证） | 🔴MO2 前置（红绿两段）；FS+R |
| 失效路径·编辑器改名 | M6 | 编辑器 `file.rename` 被覆盖引用的材质→现状：覆盖仍指旧路径+静默失效（**MO3** 红证）→修后：覆盖路径被重写、部件穿新路径、audit 零 Missing | 🔴MO3 前置（红绿两段）；FS+R+盘 |
| 重导入保留 | M7 | 改写 .glb（追加一个盒子子节点，原材质名不动）→引擎重实例化→覆盖仍生效（新部件按名穿装）+authored 根与覆盖 patch 原样（盘 SHA+R）——「重导入保留」正主刻画 | 成晶机制（事实七）；FS+R+G+盘 |

### 铁证②：结构变化明确报告，不静默丢

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| 失效键报告 | M8 | 改写 .glb 把材质 `Rock` 改名 `Stone`→重实例化后部件穿回原材质→现状零报告（**MO1** 红证）→**修后**：状态栏 warn+日志各一次（(根,键) 一次锁；重复重导入不重复报）+恢复名字→锁自清、重穿 | 🔴MO1 前置（红绿两段）；FS+R |
| 失效路径报告 | M9 | M5 修后段：audit findings 含覆盖路径条目（type_path=MaterialOverrides/field=materials/reference=路径）+`asset.missing_list` 在列+rebind 修复通路走通（**A11 刻画**：rebind 后活世界是否重穿） | 🔴MO2 前置；FS+R |
| 失效值·游戏侧 | M10 | staged/direct 游戏里删材质文件的包：部件穿回原材质不崩（catalog miss→give_back 引擎语义）+无 panic——「不静默丢」的游戏侧边界（静默在游戏侧属设计，报告属编辑器侧，book 注记） | 成晶机制；G |
| 横切·undo | M11 | 换装→undo→组件不在+部件穿回（headless 已证转真机抽查）；报告系统不因 undo 产生假 warn（键回来即清） | 成晶；H+R |
| 横切·warn 形态 | M12 | 全程扫描 `material.override|holds no material|asset load failed|UnresolvedTypes|cannot-apply`——修后 M5-M8 的预期命中之外零意外 | 脚本常备腿 |
| 横切·T18 回归 | M13 | 改 GLB/改材质文件的两腿顺带复跑 T18 既有面：视口重实例化+缩略图 MD5+失败反馈（asset_failures）不回归 | T18 矩阵缩编回归；FS+R+MD5 |

**矩阵统计**：🔴 修复前置 6 格（MO1×M8、MO2×M5/M9、MO3×M6、MO1+MO2 合力×「不静默
丢」总格）｜⚠️ 真机腿缺口 7 格（M1/M2/M4/M7/M10/M11 成晶面未跑真机）｜红证刻画 2 格
（M3 的 MO4 面、M5 修前段）。T1 清源、T2 落判。

---

## 三、真机腿清单（Mac，bash+curl+jq+python3 写盘；T2 集中跑）

fixture 工程=`jd new` 出 `/Users/zhanglinbo/workspace/loop-mac/t23-materials`（T15/T16/T18
同款；**建后注入 jackdaw_remote 两行 sed**，t15-live.sh:488-497 先例）。GLB fixture=脚本
python3 手拼最小 glTF（T15 hero.glb 先例）：两 mesh+两命名材质 `Rock`/`Trim`+一纹理；
「结构变化版」GLB=同几何但 `Rock`→`Stone`、以及第三版追加盒子子节点；材质文件
`materials/{mossy,wet,deep}.bsn`（Standard+Layered+Water 各一，`asset.new` 或模板件）。
流程脚本 `loop/qa/t23-live.sh`（t18-live.sh 形态：prep/editor/game/export 四相+leg/summary/
cleanup trap+`$PHASE` 日志名 warn 扫描+A9 settle 重试助手+watcher 腿单触发源纪律）。

| # | 腿 | 通道 | 为什么必须真机 |
|---|---|---|---|
| L1 | M1 五链主干：place→operator 换装→PX 像素 diff→Save→重开→export→staged G 断柄 | R+G+PX+盘 | 验收句「重开+导出保留」正主；视口/游戏渲染是视觉结论 |
| L2 | M2 四穿面三态（Standard/Layered/Water；Foliage 记档） | H+R+G | WornMaterial 四态组件替换的柄一致性 |
| L3 | M3/M4 重名与多层：同名双部件一键换装+MO4 红证刻画+预制体/实例/散布抽查 | R+PX+H | by-name 语义与扩大化陷阱的行为刻画 |
| L4 | M5 失效路径红绿：rm 材质文件→静默红证（audit 零条目）→修后 Missing+warn→恢复→重穿 | FS+R | 「失效路径处理+明确报告」正主；审计盲区的活体证明 |
| L5 | M6 编辑器改名红绿：file.rename→修前静默失效/修后覆盖跟随 | FS+R+盘 | MO3 的编辑器内动线正主 |
| L6 | M7/M8 重导入双段：改 GLB 追加盒子（保留格）+改材质名（报告格红绿） | FS+R+G | 「重导入保留+结构变化报告」两词并腿；fork spawner 时序只有真机真 |
| L7 | M9 audit/rebind 通路：missing_list→asset.rebind→audit 归零+A11 活世界重穿刻画 | FS+R | 覆盖路径入审计后的完整修复环 |
| L8 | M10/M13 游戏侧边界+T18 回归：staged 缺材质包不崩+缩略图/反馈面不回归 | G+FS+MD5 | 「不静默丢」游戏侧边界+邻域回归 |

---

## 四、分任务拆解（T1/T2/T3）

### T1「报告面+可发现性建设轮」（建设主体：MO1/MO2/MO3+MO4 裁定落地；决策 1/2/3/4/7）

1. **首步探针（半日级，全静态或纯函数）**：①**卡片直编探针**：root tests/ 纯函数——对
   持 `MaterialOverrides` 的实体构造 `[Rock]` 字段路径的 `field_edit_commit` 调用，断
   组件值与 AST patch 是否落地（MO5 事实定案，`src/commands.rs:211` 链路）；②**MO4
   行为复核**：operator 对无名部件的 names 选择分支（src/material_overrides.rs:250-257）
   写一条断言测试钉死现状（决策 4 的输入）；③audit 特判形态定案——读 `is_source`
   特判的两处调用点，确定下传方式（决策 2）。
2. **MO1（决策 1-A）**：`src/material_overrides.rs` 加报告系统（~80 行）：
   `ReportedOverrides(HashSet<(Entity, String)>)` 资源+Update 小系统（触发=两覆盖组件
   Changed/Removed+`Added<GltfMaterialName>`+`BsnProjectAssets` changed——与
   find_models_to_dress 同集合，事实四/十六）；对每个持覆盖根算 stale 键+unresolved 值→
   新键 `notify_warn`+`warn!` 各一次（文案含模型名/材质名/路径+「wearing its own
   material until it returns」语义），键回归即清锁。单测：假世界构造四态（stale 报一次/
   重复不报/恢复清锁/undo 不假报）。
3. **MO2+MO3（决策 2-A，同一改动面）**：①`reference_audit.rs` Struct 臂加覆盖类型
   特判（is_source 同款：`OVERRIDE_TYPE_PATHS` 常量对，含
   `jackdaw_scene_types::types::{MaterialOverrides,InstanceMaterialOverrides}`）→Map 值
   字符串进候选；单测=持失效覆盖的文档 audit 必报 Missing（红→绿）。②`reference_rewrite.rs`
   的 scan_struct/rewrite_struct 下传「覆盖类型」标志→Map 臂对覆盖值按引用处理；单测=
   rename 被覆盖引用的材质→覆盖条目重写+**无关 Map 字段不受影响**（「nothing else」
   回归姊妹件）；guards 既有 `renaming_a_referenced_file_rewrites_its_referrers_and_
   nothing_else` 必跑。③决策 2 若裁附带：`GltfSource.path` 收录 audit（第二特判，模型
   失效可发现）。
4. **MO4（按决策 4 裁定）**：建议 B=operator 的「选中部件无名且 name 空」分支改 warn
   拒（文案「that part wears an unnamed material; name= one of …」列可命名清单）+断言
   测试；若裁 A=只 book 注记+MO1 报告系统附带「N parts wear unnamed materials」计数。
5. **MO5 探针落档**：按①结果记档（走通无校验/走不通只读），不修（决策 7）。
6. **headless 新锚**：报告系统四态单测+audit 特判红绿+rewrite 特判红绿+MO4 断言
   （全 root tests/ 档）；tests/stage 六件回归必跑。
7. **门禁**：fmt/clippy 全仓/单测/集成+teaches 全绿（fast 预期 3047→+n）。

**验收标准**：MO1 红绿（headless 四态+真机 T2 终判）；MO2/MO3 红绿；MO4 按裁定落地；
探针两件结论在案；headless 全绿+quick 四门。

### T2「真机矩阵轮」（验收主任务：M1-M13/L1-L8；决策 5/6）

1. fixture 工程+GLB 三版生成+材质三件+`loop/qa/t23-live.sh`（四相；watcher/重导入腿
   单触发源+settle≥2s+A6 隔离纪律照抄 t18 口径）。
2. L1-L8 全腿；MO1/MO2/MO3 修前红证先行归档（红态归档纪律，T16 首例延续）。
3. 缺陷只记不修：新发现按 MO 系续编（MO8 起），红证归档 `loop/reports/t23*/`。
4. QA 报告：13 格矩阵逐格判定+L 腿全证据+用户 30 秒清单草稿（换个材质重开看穿、
   删个材质文件看报告）。

**验收标准**：M1（五链）+M7（重导入保留）全绿=铁证①；M8/M9（报告+审计）红绿在案
=铁证②；M5/M6 红绿闭环；M12 零意外 warn；四门禁绿。

### T3「终验 + 文档」

1. 13 格终态复跑+重点腿复跑（L1/L4/L6）。
2. book 新章 `book/src/user-guide/material-overrides.md`（SUMMARY 排 materials 相关节
   后）：覆盖作者面导览（三口：材质行 Pick/浏览器 Apply/operator 表）、by-material-name
   语义（同名多部件一网打尽+无名材质边界=MO4 口径）、双层模型（模型层/实例层+预制体
   携带+散布带回）、持久化语义（存哪/何时穿/undo）、失效双态（报告+audit+恢复自愈；
   手清通路 `material.override material=""`）、GLB 结构变化语义（改名/删除的报告行为）、
   导出语义（目录链+游戏侧 catalog 解析+游戏侧静默属设计注记）；`materials.md`/
   `assets.md`/`prefabs.md` 交叉引用。
3. buglist 处置（预期无打钩；MO4/MO7 按决策落账）、roadmap T23 勾选、台账记行。
4. 终验门：全量门（fast/integration/doctests/docs/scaffold_e2e——日志全文复核）。

---

## 五、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **MO1 报告系统落点（本方案最高权重）** | A=**编辑器侧比对小系统**（触发集合与 find_models_to_dress 同型、只读比对、(根,键) 一次锁、恢复自清；~80 行在 src/material_overrides.rs）：状态栏+日志双嘴、游戏进程零噪音、单测好写；代价=触发集合与 runtime dressing 各一份（两处要同步演进——注释互指）。B=runtime `find_models_to_dress` 内直接 `warn!`：单一触发源、编辑器游戏都报；代价=游戏侧日志噪音（用户游戏被 QA 噪音污染）+状态栏够不着（runtime 无编辑器 chrome）+报告语义混进穿装热路径。C=只进 audit 不实时 warn：零新系统；代价=「明确报告」退化成「主动去查才知道」，验收句字面落空 | **A**；C 的 audit 面由决策 2 另行补齐（两者互补不互代） |
| 2 | **MO2/MO3 特判形态（audit 收录+改名跟随，同根因一件）** | A=**两覆盖类型路径显式特判**（is_source 先例同款：常量对+下传标志）：最小面、零误伤、语义精确（「这两个类型的 materials 值是引用」）；代价=类型清单硬编码（新覆盖类型要记得加——现全仓就这两个）。B=泛化「BTreeMap<String,String> 字段名含 material 就当引用」：免清单；代价=启发式误伤面（任何同名 Map 字段被拉进审计）——不可控。C=改 `takes_asset_path` 认 String-Map：波及全仓字段落盘/拼写语义——**否决**。附带项：`GltfSource.path` 是否顺带收录 audit（模型文件失效同样静默，事实十四）——收录=多一类 Missing（既有 GLB 消失测试面要适配），不收=维持现状 | **A+附带收录**（is_source 已开「个别 String 字段是引用」的先河，`GltfSource.path` 是同类语义；若既有测试面适配超半日则回落「不附带」记档） |
| 3 | **失效条目的清理语义（MO7）** | A=**只报告+手动清**（`material.override entity name material=""` 既有通路+book 教学）：数据零风险（同名材质回归自动复活是有益语义）；B=报告+「清失效条目」小 op：一键清；代价=+1 op 面+「清了之后材质回归不复活」语义分叉。C=报告时自动摘除失效键：作者少操心；代价=**静默丢**——验收句的反面，且丢掉「回归复活」语义——**否决** | **A**；B 记 open-challenges 一句话 |
| 4 | **MO4 无名材质面** | A=**只注记**：book 写明「glTF 材质须命名才能被覆盖」（DCC 导出建议），operator 扩大化行为文档化；零行为变更。B=**扩大化改 warn 拒**：选无名部件+name 空→拒并列出可命名清单（~10 行+测试）：语义诚实、防误换全模型；代价=行为变更（现有依赖此路径的工作流变严——headless/真机扫描确认无人依赖后落地）。C=fork loader 给无名材质合成名字（`Material 3`）：可寻址；代价=**动 fork**（fork 纪律，T16 决策 2-C/T18 AR5 先例一致反对）——**否决** | **B**（探针②确认无人依赖后）；若 T2 真机发现扩大化有真实用例则回落 A+book 注记 |
| 5 | **真机通道范围（PIE/游戏侧）** | A=**direct run 为主+staged 一腿、PIE 免**：覆盖域验收不依赖 PIE 交互（A10/N13 全绕开）；导出腿=T07/T20 成熟形态。B=加 PIE 腿（编辑器 PIE 启动带覆盖场景）：多一态；代价=N13 记数+A10 风险+增量信息薄（PIE 与 direct 同为 runtime render 链） | **A**；PIE 穿装语义与 direct 同链在 book 注记一句 |
| 6 | **A7/A9 前置评估** | A=**不前置，脚本自守**：主链全 operator 直达零对话框腿；唯一 Pick 腿用 T16 并账的相对配对法+记数（A7 家族咬不到主链）；A9 小响应体+settle+idle 探针；截图 flake 用「同腿双拍+像素助手库 diff」自守（T19 口径）。B=先修 A7/A9：多一前置任务，对 T23 无专项收益 | **A**；真踩按 MCP 优先原则现场立项 |
| 7 | **MO5 卡片直编处置** | A=**探针定事实+记档不修**：卡片值行走通用链（无校验/或走不通只读）都属现状边界——正门是材质行 Pick（有校验），book 注记「直编路径自担」；B=T1 顺带给卡片值行加材质存在性校验：一致性；代价=通用字段行链路里开特例（reflect_fields 是全 Inspector 公共路径，特例面宽） | **A**；B 若探针显示直编是常用通路再议 |

小定案（主控可否决）：缺陷编号 MO1-MO7（新发现自 MO8 续）；真机腿编号 L1-L8；
矩阵格 M1-M13；fixture 工程 `/Users/zhanglinbo/workspace/loop-mac/t23-materials`；
流程脚本 `loop/qa/t23-live.sh`；报告目录 `loop/reports/t23*/`；book 章
`book/src/user-guide/material-overrides.md`；GLB 生成=t23-live.sh 内 python3（两命名
材质+两 mesh 最小 glTF×三版：基准/改名版/加盒版）；材质资产
`assets/materials/{mossy,wet,deep}.bsn`（Standard/Layered/Water 各一）；报告系统资源名
`ReportedOverrides`；audit 特判常量 `OVERRIDE_TYPE_PATHS`。

---

## 六、风险与回滚

| 风险 | 概率 | 缓解 |
|---|---|---|
| 报告系统与 dressing 双触发集合漂移（runtime 改触发、编辑器漏跟） | 中 | 两处注释互指+单测钉「触发集合清单」；报告系统只读比对、漏报面由 audit 兜底（双保险互补） |
| audit/rewrite 特判误伤无辜 Map 字段 | 中-低 | 显式类型对特判（决策 2-A）非启发式；guards「nothing else」回归+T05 既有守卫全量必跑；`@name` 引用路径行为不变（scan_value 既有 `@` 分支不动） |
| 重导入腿时序（respawn→Added<GltfMaterialName>→dress→报告跨帧） | 中 | settle≥2s+A6 单触发源纪律（t18 口径全量入脚本）；腿内预算 10s 超时判 FAIL 不赌 |
| `GltfSource.path` 附带收录波及既有审计测试面 | 中 | 决策 2 附带回落判据写死（适配超半日即不附带记档）；T1 首步③先盘点既有 audit 断言面 |
| MO4 行为变更破坏既有工作流 | 低 | 探针②+全测试面扫描确认无人依赖扩大化路径；B 落地时 headless 六件回归必跑 |
| GLB 手作 fixture 质量（三版轮换的合法性） | 中 | T15 hero.glb 先例+T18「两份预制 .glb 轮换」手法；prep 相先验 loader 零 ERROR 再进正腿 |
| 截图/像素 diff flake（A7 家族） | 中 | 换装颜色差拉大（品红/青撞色）；同腿双拍+像素助手库阈值 diff（T19 口径）；截图只承担视觉格、组件柄断言为主判据 |
| staged 导出腿构建时长（T20 实测 145s 级） | 确定 | 腿预算单独给；导出相与门链不同窗（T12-T3 §九-7 纪律） |
| A9 游戏 BRP 空响应 | 中 | 小响应体（单组件过滤查询）+settle 重试+idle 探针+避开构建窗口 |
| Mac debug 无 RUST_BACKTRACE | 确定 | 全程不设（T11-T3 口径）；panic 形态证据=日志消息签名 |
| 门链与编辑器/游戏同窗互踩 | 中 | 门链单独跑 |
| 回滚 | — | 三件各自独立可 revert（MO1=一系统+一资源；MO2/MO3=两文件各一特判分支+常量对；MO4=一 warn 分支）。全程零场景格式变更、零协议变更、零 fork 改动、零新插件组、零组件结构变更（覆盖组件本就在档）——建设面=报告+可发现性，由定性表保障（六个验收词的机制层无一需要新引擎机制） |

---

## 七、与 T01-T22 已建设施的衔接

1. **T05（引用稳定）=MO2/MO3 的机器底座**：audit/missing_list/rebind/follow_a_move
   全在库（事实十三/十五）；覆盖特判=在其清单语义内加一类候选，Missing 判定/清单/rebind
   免费；guards 既有引用回归必跑。
2. **T18（资产热重载）=重导入腿的通道+AR3 形态来源**：GLB Modified→重实例化链、
   缩略图 MD5 证据法、asset_failures 的 (path,mtime) 一次锁（事实十二）全继承；
   M13 是 T18 矩阵缩编回归。
3. **T07/T20（导出）=M1 导出段形态**：`game.export`+staged 异目录启动+G 通道断言
   直接复用；`tests/export.rs` staged e2e 是 headless 侧锚。
4. **T14（预制体）/T10b（散布）=M4 多层格的既有面**：实例层赢/跟随/带回三件
   headless 在库，真机只抽查。
5. **T19（画质）=PX 像素证据手法**：像素助手库+阈值 diff 用于换装前后视口证据。
6. **T15（动画）=GLB 手作工艺**：hero.glb 先例是三版 GLB fixture 的方法来源。
7. **对 T24-T25 的奠基**：T24（调试反馈/错误定位）——MO1/MO2 的报告面是「资产缺失
   可从面板定位」域的覆盖域样本，audit findings 的实体名/字段/路径三元组正是跳转的
   定位锚；T25（运行态调参）——dressing 的 Changed 触发模型是 live 编辑回写的参照。
8. **分支与行号基线**：本方案行号基于 main 7f460caa；T23 从 main 拉
   `loop/t23-material-override`；loop/ 目录随 git 旅行（2026-10-28 迁移后），上游 PR 时
   按需剔除。

---

## 八、耗时预估

| 段 | 预估 | 大头 |
|---|---|---|
| T1 | 1-1.5 天 | 探针两件+MO1 报告系统（四态单测）+MO2/MO3 双特判（红绿+nothing else 回归）+MO4 裁定落地+门禁 |
| T2 | 1-1.5 天 | fixture 三版 GLB+脚本+L1-L8（红证先行归档+watcher 纪律）+staged 导出腿（构建窗口预算） |
| T3 | 0.5-1 天 | 13 格终态+book 新章+全量门+buglist/台账收尾 |
| 合计 | **2.5-4 天** | 视决策 2 附带项（GltfSource.path 收录）与重导入腿时序稳定性浮动 |
