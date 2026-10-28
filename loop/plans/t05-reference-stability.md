# T05 资产与实体引用稳定性 — 实施方案

> 策划产物（2026-10-25，基于分支 `loop/t04-save-recovery` HEAD **7caf0bad** 全量代码核实；T04-T3 终验进行中，
> 若 T04 返工合入 main 后行号漂移，按符号名重定位，结论不受影响）。需求来源：`loop/plans/roadmap-game-dev.md` T05。
> 验收原文：纹理/模型/材质/Prefab/实体引用在改名/移动/删除/重导入后的行为，补稳定标识或引用更新。
> **验收=改名移动不丢引用；删除示影响面；缺失可定位重绑。**（file.rename 现不联动引用，为已知切入点。）
> buglist 吸收 Y8/W8/W11/W12（progress 台账既定映射）+ 漏映射的 **Y31/W10/W7**（见重叠表）；新发现编号 **N1–N8**。

---

## 0. 架构事实（核实结论，方案的地基）

**引用的身份是路径字符串，全链无 GUID**。这三条事实决定了方案走向：

- **资产引用 = 文档内相对路径字符串**。相对项目 assets 根、单一命名空间（`props/crate.bsn`），
  保存时绝对路径被拒（`src/scene_io/asset_fields.rs:1-7,117-127`）；旧格式 `@name`（裸名按 stem 解析）/
  `#name`（内嵌资产）仍被读。哪些字段算引用由 `#[reflect(@AssetRef(..))]` 属性、`Handle<T>` 类型
  （`src/typed_values.rs:23-38` `takes_asset_path`）与 `IsA.source` 特判（`asset_fields.rs:93`）共同识别。
  prefab `IsA.source` 同为路径，解析先 assets 根后文档旁（`crates/jackdaw_prefab/src/source.rs:33-49`）。
- **AssetIndex 以 path 为身份**，且**引用反查表已存在**：`referrers: BTreeMap<PathBuf, Vec<PathBuf>>`
  由每次 walk 扫盘上文档的引用串构建（`src/asset_index.rs:89,157-186,365-371,614-640`），消费方有三——
  `file.delete` 确认对话框（`src/file_ops.rs:132-155`，前 3 名+余数）、`asset.references` operator
  （`file_ops.rs:477-511`，`report_to_caller` 走 BRP 可断言）、文件卡 References 列表
  （`src/inspector/file_card.rs:671-713`）。模块头注释明说意图："a delete can say what it would break"。
- **实体级稳定标识已完备，是资产级的最强先例**：`SceneNodeId(u64)` 以普通组件 patch 持久化进文档
  （`crates/jackdaw_bsn/src/document/query.rs:101-153`），PIE 跨进程映射、undo、selection 全用它。
  资产级无任何 GUID/.meta（全仓搜证无命中）。

**引用重写有整套先例**：`project.migrate_asset_references` 一次性把裸名重写为路径
（`src/asset_migration.rs:290-478`：AST 扫描 `name_references` → `resolve_reference` → 写回 + `note_written`
双登记防 watcher 误报 `:221-226`）。缺的是把它从"一次性迁移"改造成"改名/移动时增量执行"，以及把
`String::replace` 写回换成 AST 级（W10）。

**重导入已经是对的**：mtime 变化 → `reload_in_place` 同 handle 换值，引用者自动跟随
（`asset_index.rs:443-456,577-586`）。删除资产时索引摘条目但 handle 保活，已渲染对象不断
（`asset_index.rs:487-494` 注释）——重开场景后才真正断。

**缺失引用的现有表现分两档**：prefab `IsA` 缺失在加载时 `warn_caller` 逐条报告（`src/scene_io/load.rs:315-322`
→ `src/prefab/save_load.rs:84-115`）；其余资产（纹理/材质/模型）缺失**静默**——`bsn_value_to_reflect`
直接 `server.load_erased`，成败交给 bevy 失败路径（`crates/jackdaw_bsn/src/apply.rs:993-1001`）；`#`/`@`
引用解析失败才 warn+默认 handle（`apply.rs:988-992`）。Inspector 资产行已有 broken 态：红字+tooltip
"… is not in the project"（`src/inspector/asset_row.rs:366-399`，判据 `project_holds_file`
`asset_index.rs:282-293`），且行内 Pick picker（`asset_row.rs:591-`）与拖拽 drop（`:276-288`）就是现成重绑 UI。

**file.rename 现状**（已知切入点，`src/project_window.rs:2149-2209`）：`fs::rename` → 更新
`ProjectWindowState`（current_directory/expanded/rebuild）→ `select_path`。不重写任何引用者、
不 retarget 打开中 tab（Y8）。`target.exists()`（`:2190`）在 NTFS 大小写不敏感下误判（W11）。
`target == path`（`:2186`）是 OsStr 字节比较，仅大小写不同会走到 exists 误判分支。**无 file.move
operator**——编辑器内移动资产无入口，跨目录移动只能靠 OS 文件管理器（watcher 只看到 gone+added，
引用全断、无人重连）。

**加载管线无实体重映射**：`load_bsn_scene` 直接 spawn（`crates/jackdaw_bsn/src/catalog.rs:142-`、
`apply.rs:193-220`），全链无 `EntityMapper`/entity_map（仅 undo 快照与 PIE 投影各自内用）。
自定义组件里的 `Entity` 字段无 `ReflectEntity` 特判分支——其跨"保存→重开"的保真性**无任何测试与先例**
（全仓无 `bevy_ecs::entity::Entity` 序列化命中），按现状推断会按 reflect 结构体原样 emit、重开后指向
错误实体（N6，❓任务 1 先实测钉死）。

**BRP/MCP 工具面**：现有 19 方法（`src/remote/server.rs:147-168`）中，`call_operator`（返回体含
operator reports，`server.rs:847,894,936`）、`scene_tree`/`entity`/`scene_bsn`、`assets`(watching) 覆盖
T05 大部分断言需要；`asset.references` 可直接经 `call_operator` 断言影响面。缺口仅一项：结构化
"缺失引用审计"查询（见 T2 的 `asset.audit`）。

---

## 一、现状与缺陷矩阵

### A. 改名 / 移动（验收主线「改名移动不丢引用」）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **N1** | 🔴 | **rename 后引用者零联动**。`file.rename` 只动盘上文件与 ProjectWindowState；所有引用该资产的场景/prefab/材质文档里的引用串原样指向旧路径——Inspector 逐字段红显、重开场景资产丢失，无重写、无提示、无报告 | `project_window.rs:2175-2209` 全函数无引用处理；对照 `asset_migration.rs:290-349` 已有整套重写能力却只在迁移 op 调用 |
| **Y8**（buglist） | 🟡 | rename 不 retarget 打开中 tab：`Scenes.tabs[].path` 不更新（`scenes/mod.rs:131`），Ctrl+S 按旧路径写盘 → 旧文件"复活"、两份分叉。**同型扩展（本方案新核实）**：`DefinitionAssetEdit.path`（资产卡片编辑态，`definition_assets.rs:53,662,698`）同样不 retarget，卡片保存写回旧路径；对照 `file.convert` 有 `is_open_in_a_tab` 守卫（`file_ops.rs:564-570`），rename/delete 都没有 | buglist Y8 + `rename_file` 无 tab/卡片分支 |
| **N2** | 🟡 | **编辑器内无移动入口**：无 `file.move` operator，跨目录移动只能 OS 外部操作 → watcher rescan 视为 gone+added，引用全断且无人报告。验收句「移动不丢引用」在编辑器内无操作可验 | 全仓无 move operator（file_ops.rs 注册表 :45-52 仅 delete/duplicate/references/convert×2/export） |
| **W11**（buglist） | ⚪ | 仅大小写重命名失败：`Rat.bsn`→`rat.bsn` 时 `target.exists()` 因 NTFS 不区分大小写误判"已被占用" | `project_window.rs:2190` |
| — | ✅ | rename 文件夹时 `current_directory` 前缀有跟随（`:2199-2201`），但引用串的目录前缀无联动（并入 N1 的重写范围） | |

### B. 删除（验收句「删除示影响面」）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| — | ✅ | **影响面提示已存在**：非 force 删除弹确认对话框，列出引用者（前 3+余数），目录删除用 `referrers_under`；`asset.references` op 随时可查；文件卡有 References 区 | `file_ops.rs:132-155,159-190,477-511`、`file_card.rs:671-713` |
| **N3** | 🔴 | **删除正打开的场景/prefab 文件后 Ctrl+S 把旧文件写回**。`delete_path` 无 open-tab 守卫（对照 convert 有），tab 与其 `path` 原样留存，下次保存即复活刚删除的文件——用户明确的删除被静默回滚，与 Y8 同族但方向相反 | `file_ops.rs:211-240` 无守卫；守卫先例 `file_ops.rs:564-570` |
| **N4** | 🟡 | 影响面数据只看盘：`referrers` 由 walk 扫盘上文档构建，**不含打开中未保存 tab 的内存引用**——正在编辑的场景对某材质的引用不在确认对话框里，删除后保存才发现断。删除后也无全局"断链清单"，断链只在逐实体选中时以 Inspector 红行呈现 | `asset_index.rs:365-371`（数据源仅 `cache.references_of(盘上文件)`）；无任何 audit 入口 |

### C. 缺失定位 / 重绑（验收句「缺失可定位重绑」）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **N5** | 🟡 | **非 prefab 资产缺失加载静默**：纹理/材质/模型路径解析失败直接 `load_erased` 交 bevy 失败路径（紫/白材质或空 mesh），编辑器零提示；对照 prefab 有逐条 `warn_caller`。加载完成的场景里"哪个实体哪个组件引用了缺失资产"只能逐个点开看红行 | `crates/jackdaw_bsn/src/apply.rs:993-1001` vs `load.rs:315-322`；红行 `asset_row.rs:366-399` |
| **N6** | 🟡/❓ | 自定义组件 `Entity` 字段跨"保存→重开"不保真：加载无实体重映射（§0），Entity 字段按 reflect 原样序列化则重开指向错误实体。**无测试无先例，任务 1 先实测 emit 形态再定级** | `apply.rs` 无 ReflectEntity 分支；全仓无 Entity 字段序列化用例 |
| **N7 = Y31**（buglist，漏映射） | 🟡 | 内嵌资产互相引用静默丢失：逐条加载时 `local: None`，同文档 `#Name` 互引回落默认 handle——save→load 往返丢引用（仅资产→资产方向） | buglist Y31；`crates/jackdaw_bsn/src/catalog.rs:60,318` |
| — | ✅ | 重绑 UI 已有：Inspector 资产行 Pick picker + 拖拽 drop（`asset_row.rs:591-,276-288`）；行级 broken 红显+tooltip | |

### D. 保存防线 / 重写机制 / 性能

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **W12**（buglist） | ⚪ | 盘符相对路径漏判：`C:props/x.bsn`（盘符后无分隔符）不被判机器路径，可写进场景文件，换机解析到意外位置 | `asset_fields.rs:124-126`（要求 `C:/` 形态）；测试 `:282-288` 恰未覆盖无分隔符拼写 |
| **W10**（buglist，漏映射） | ⚪ | 迁移重写用 `String::replace` 全文替换，同文档另一类型的同值同名字段会被误改——T05 的引用重写器若直接复用会继承此缺陷，应一并治好 | `asset_migration.rs:312-321` |
| **W7**（buglist，漏映射） | ⚪ | `gone` 检测 O(n·m) 主线程，T05 若提高 rescan 频率（watcher 侧报告）会放大，顺手修 | `asset_index.rs:540-545` |
| **W8**（buglist） | ⚪ | OS 拖放不查来源是否已在项目内，拖自家文件复制出 `xxx-1.ext` 副本 | `asset_ingest.rs:143-150` |
| — | ✅ | 重导入（同路径覆盖）行为正确：同 handle 换值，引用者自动跟随（T05 只需回归钉死） | `asset_index.rs:443-456` |

**统计：🔴 2（N1、N3）｜🟡 5（Y8、N2、N4、N5、N6❓/N7=Y31 合并计 2）｜⚪ 5（W7、W8、W10、W11、W12）｜❓ 1（N6 实测定级）**
> N3 定 🔴 理由：删除被静默回滚属数据级（用户意图被推翻）；与 Y8（🟡，分叉）同族但更违反意图，QA 可下调。

### buglist 重叠表（引用稳定性相关全量扫描）

| 条目 | 一句话 | T05 处置 |
|---|---|---|
| Y8 | file.rename 不联动打开中 tab，Ctrl+S 写旧路径两份分叉 | **吸收（T1）**，含 definition 卡片同型扩展 |
| W8 | 拖自家文件复制副本 | **吸收（T1 顺手，ingest 一行守卫）** |
| W11 | 仅大小写重命名失败 | **吸收（T1，两步 rename）** |
| W12 | 盘符相对路径漏判 | **吸收（T2，保存防线补漏+测试）** |
| **Y31** | 内嵌资产 `#` 互引 save→load 丢失（progress 映射表漏列） | **建议吸收（T2，两阶段加载）**；若主控裁定缓做则备案 T18（热重载闭环） |
| **W10** | 迁移重写 String::replace 误伤同值字段（漏映射） | **吸收（T1，重写器 AST 化时迁移 op 改走同一实现）** |
| **W7** | gone 检测 O(n·m)（漏映射） | **吸收（T2 顺手，HashSet 差集）** |
| R3 | Save as Variant 拍平子树 | 不吸收（prefab 结构域，归 T14） |
| W23 | 覆盖清除按顶层字段名匹配不中点路径 | 不吸收（prefab 覆盖域，归 T14） |
| Y28/Y30 | BSN 解析深度无上限 / 文档遍历无环保护 | 不吸收（T04 已备案 Y28；Y30 是解析器域；T05 新增的 audit 遍历按 `MAX_AST_DEPTH` 家族写） |
| W13 | notify_warn 与 info 同实现 | 不吸收（状态栏域），但 T05 的"重写 N 处引用"提示需要 warn 色，T2 视实现顺手（超范围不承诺） |

---

## 二、分任务拆解（T1/T2/T3）

### T1「改名/移动/删除的引用联动与 tab retarget」（N1+Y8+N3+N2+W11+W8+W10）

**目标**：编辑器内 rename/move/delete 成为引用感知操作——重写引用者文档（AST 级）、retarget 打开中
tab 与卡片、堵住删除复活洞；顺手补 move 入口、大小写 rename、W8、W10。

**改动面预估**：
1. **新模块 `src/reference_rewrite.rs`**：AST 级引用重写器。输入 `(assets 根, old 相对路径, new 相对路径)`
   与目标文档集合（来自 `AssetIndex.referrers`/`referrers_under`），对每个文档 parse → 按节点 patch
   定位引用字段（复用 `asset_migration.rs:359-444` 的 `scan_struct/scan_value` 枚举逻辑，**写回侧换
   AST patch 值替换**而非文本替换）→ emit → `write_atomic` → `note_written`（`asset_migration.rs:221-226`
   双登记先例）。支持三种匹配：整串相等、`@stem` 裸名（仍存旧拼写的文档）、目录前缀（文件夹 rename/
   move 时 `old/` 前缀替换）；twin 形态（`.bsb`/`.bsn`）按 `existing_form` 对齐。文件夹重写后要去重
   （同文档多字段同引）。**`project.migrate_asset_references` 的 `rewrite_documents` 改走本模块**
   （W10 一并治好，迁移测试回归钉死不误伤同值字段）；
2. **`rename_file` 扩展**（`project_window.rs:2175-2209`）：rename 成功后——
   a) 重写引用者（含目录前缀情况）；b) retarget `Scenes.tabs[].path`（含 journal/external_watch 侧的
   路径登记，见 §五）与 `DefinitionAssetEdit.path`；c) 同步重写打开中 tab 的**内存 AST** 引用值
   （干净 tab 重算 `saved_doc_hash` 基线保持干净；脏 tab 保持脏——裁决 6）；d) 状态栏报告
   "renamed; rewrote N references in M documents"（`report_to_caller`）。W11：目标与源仅大小写不同时
   两步 rename（`tmp` 中转名）放行；
3. **新 operator `file.move`**（`file_ops.rs` 注册表加行）：参数 `path`+`folder`，`fs::rename` 跨目录 +
   走 2 的同一条联动链（重写引用/retarget/报告）。右键菜单 Move to… 入口走既有对话框模式；
4. **`delete_path` 补 open-tab 守卫**（N3）：目标被任一 tab/卡片打开时非 force 拒绝并在确认对话框
   描述里说明（"it is open in a tab; close it first"，convert 守卫模式扩展）；`force` 分支同时关闭
   对应 tab/卡片再删；
5. **W8**：`handle_file_drops` 对 `path` 已在 `assets_dir` 下的 drop 跳过复制、直接 `select_path`
   放置（`asset_ingest.rs:143-150` 一行守卫 + 用例）；
6. **`referrers` 数据补内存态**（N4 的 T1 半）：`referrers_of`（`file_ops.rs:159-170`）在索引表之外
   追加扫描打开中 `Scenes` tabs 的 AST 引用（同 `scan_struct` 枚举器），使删除确认覆盖未保存编辑。

**验收标准（可执行可复现）**：
- [ ] headless 改名：场景文档引用 `materials/rust.material.bsn`（`Signpost.board`）→ `file.rename`
  `rust`→`patinated` → 盘上场景文档引用串变 `materials/patinated.material.bsn`（AST 级：同文档另设一个
  **非资产字段恰好等于旧路径串**，断言其不被误改——W10 红绿）；重载场景后 `AssetIndex.path_of_id(handle)`
  == 新路径；材质本体字段值（如 metallic）加载不变；
- [ ] headless 文件夹改名：引用 `props/a/crate.bsn` 与 `props/b/box.bsn` 的两个文档在 rename
  `props`→`prop` 后全部前缀更新，各恰一处；
- [ ] headless Y8 红绿：打开中场景 tab（named，干净）→ `file.rename` 场景文件 → `tab.path` == 新路径；
  Ctrl+S 落盘在新路径且**旧路径不存在**；同场景为脏时 rename 仍可执行，内存 AST 引用值同步、tab 仍脏；
  definition 卡片（材质编辑中）同链 retarget，保存写新路径；
- [ ] headless N3 红绿：打开中场景 → `file.delete`（非 force）→ 拒绝 + 描述说明 open in a tab；force →
  tab 关闭 + 文件不存在 + Ctrl+S 无处可写（无 tab）；
- [ ] headless W11：`Rat.bsn`→`rat.bsn` 成功且盘上恰一个文件、内容不变；`Rat.bsn`→`RAT.bsn` 同理；
- [ ] headless file.move：材质 `materials/x.material.bsn` → move 到 `mats/` → 引用串、tab、卡片、
  状态栏报告全联动（断言同改名链）；
- [ ] headless 重导入回归（钉死既有正确行为）：改写引用者文档后 `note_written` 生效——rescan 不把
  重写读成外部修改（`external_watch` 不弹 reload）；同路径覆盖材质内容 → 已加载 handle 值更新；
- [ ] headless W8：drop 一个 `assets_dir` 内文件 → 目标路径无副本文件（`xxx-1.ext` 不出现）；
- [ ] 迁移回归：`asset_migration` 既有测试全绿（重写器换实现后 `nothing to migrate` 幂等性保持）。

**测试设计**：guards 新 `tests/guards/reference_rewrite.rs`（上述 headless 链；harness 复用
`asset_migration.rs:558-588` 的 `migration_app()` 模式 + T03 `dirty_matrix.rs` 的 editor/save 模式）。
**buglist 吸收**：Y8、W11、W8 打钩；W10 打钩（迁移测试补误伤用例）。

### T2「缺失引用审计、定位与重绑闭环」（N4 后半+N5+N7/Y31+W12+W7）

**目标**：把"缺失可定位重绑"从逐实体翻找变成一条链：加载/审计时汇总缺失 → 清单可定位到文档/实体/
组件/字段 → 一键重绑（复用既有 picker）→ 保存落盘。

**改动面预估**：
1. **新 operator `asset.audit`**（file_ops 或新 `src/reference_audit.rs`）：遍历 `AssetIndex` 引用表
   （盘上文档）+ 打开中 tabs AST，对每个引用串调 `project_holds_file`/`resolve_reference` 家族判定，
   产出结构化清单 `[{document, entity_name?, component, field, reference, kind: Missing|Ambiguous|MachinePath}]`；
   `report_to_caller` 摘要（N 条 broken in M documents）。同时挂 BRP 方法 `jackdaw/audit`
   （`remote/server.rs:147-` 表加一行，返回 JSON——QA 断言通道，MCP 优先原则：无需土法）；
2. **加载期非 prefab 缺失提示**（N5）：场景加载完成后对该文档跑一次 audit 子集（引用串判
   `project_holds_file`），缺失者 `warn_caller` **一条汇总**（"scene 'x': 3 references name files the
   project does not hold — open the Missing list"），不逐字段刷屏；prefab 既有逐条投诉保持；
3. **Missing References 清单 UI**：挂在文件卡/状态栏入口的一个列表视图（列表行 = audit 条目；
   双击行为：文档在项目中 → 打开该文档对应 tab 并选中实体（经 `SceneNodeId`/Name 定位，复用
   `selection` 链）；行内 Pick 按钮复用 `asset_row` 的 picker 直接改引用值（写打开中 tab 的 AST /
   未打开文档走"打开→改→标记外部重载"链，首版只对打开中 tab 行内重绑，未打开文档提示打开后重绑——
   裁决 3 的范围边界）；每行提供"在资源管理器中显示"与复制路径）；
4. **W12**：`names_one_machine`（`asset_fields.rs:117-127`）补 `<alpha>:` 前缀即判机器路径（无论后随
   分隔符与否）+ 用例 `C:props/x.bsn` 拒绝保存；
5. **Y31（按裁决 7，默认吸收）**：`load_bsn_assets`/内嵌加载改两阶段——先收集全部条目建
   `name→handle` 暂存表再逐条转换（`catalog.rs:58-61,315-319` 两处 `local: None` 改传暂存表），
   现有 warn 用例转绿断言（save→load 往返 `#` 互引保持）；
6. **W7**：`apply_walk` 的 gone 检测（`asset_index.rs:540-545`）`found` 收 HashSet 再差集；
7. **N6 处置（按裁决 8，默认最小）**：任务首步写一个实测用例（组件含 `Entity` 字段 → 保存 → 读回文本
   断言 emit 形态 → 重载断言指向），按结果落"检测+warn"（保存时发现 Entity 字段引用了文档外实体/
   已消亡实体则 warn_caller），全链重映射记 open-challenges 挂账。

**验收标准（可执行可复现）**：
- [ ] headless audit：预置场景引用 1 个存在材质 + 2 个缺失路径 → `asset.audit` 清单恰 2 条 Missing，
  字段定位到 `组件.字段`；`@ambiguous` 双 stem 场景报 Ambiguous；含 `C:props/x.bsn` 的文档在 W12 后
  保存被拒（防线）而 audit 标 MachinePath（旧文档）；
- [ ] headless 加载汇总：加载上述场景 → OperatorReports 恰一条汇总 warn（含计数），无逐字段刷屏；
- [ ] headless Y31 红绿（若吸收）：材质 A 内嵌纹理 `#b`、同文档定义 `#b` → save → load → A 的 texture
  字段 handle 指向 b 的 handle（往返不丢）；
- [ ] headless W7：10k 假条目 walk 的 gone 检测耗时对比记录（数量级下降即可，非硬闸）；
- [ ] **真机（BRP/MCP 驱动，验收句③「缺失可定位重绑」终验链）**：fixture 工程 → 预删一个被引用的材质
  文件 → `JACKDAW_OPEN_PROJECT` 直开 → 加载场景 → `call_operator asset.audit` 断言清单含该条（文档/
  实体/字段/路径四要素齐）→ `ui_tree` 断言 Missing 清单行 → `ui_click` 行内重绑 picker → 选现存材质 →
  `jackdaw/scene_bsn` 断言引用串已换 → `scene.save` → 盘上文档新引用串 + 重开场景 audit 清单为空；
- [ ] 真机：Inspector 资产行 broken 红显（既有）在新链下仍工作（选中引用缺失资产的实体 → 红行 + tooltip）。

**测试设计**：guards 新 `tests/guards/reference_audit.rs`（audit/加载汇总/Y31/W12）；真机脚本沉淀
`loop/qa/t05-missing-rebind.ps1`（BRP 链如上，参照 `t02t2-light-color.ps1` 的 scene.save/预建 assets 模式）。
**buglist 吸收**：W12 打钩；Y31 打钩（若裁决吸收）；W7 打钩。

### T3「真机验收矩阵 + 工具镜像 + 文档收尾」

**目标**：验收三句话的真机终验；`jackdaw/audit` 的 MCP 镜像；book 文档；台账与勾选。

**改动面预估**：
1. **MCP 镜像**：`crates/jackdaw_mcp` 补第 23 个工具 `audit`（薄翻译 `jackdaw/audit`，与 recovery 工具
   同模式）——QA 断言结构化清单不必解析 report 文本；
2. **真机验收矩阵（全 BRP/MCP 驱动，截图+日志留档 `loop/reports/`）**：

| # | 场景 | 期望 |
|---|---|---|
| 1 | 材质改名（被场景引用） | rename 后状态栏报告 N 处重写；`scene_bsn` 引用串已新；旧路径不存在；重开场景渲染/audit 正常 |
| 2 | 材质移动到另一目录 | 同上（file.move 链） |
| 3 | 文件夹改名 | 前缀级重写 + 报告 |
| 4 | 打开中场景改名（Y8 终验） | tab 标题变新名；Ctrl+S 落新路径；旧路径不存在；SHA 比对无第二份 |
| 5 | 仅大小写改名 | 成功、单文件 |
| 6 | 删除被引用材质（非 force） | 确认对话框列出引用文档名（前 3 格式） |
| 7 | 删除打开中场景（非 force/force） | 拒绝说明 / force 后 tab 关闭无复活 |
| 8 | 缺失定位重绑 | T2 真机链复跑（终验） |
| 9 | 拖自家文件入窗 | 无副本 |
| 10 | 重导入 | 外部改材质文件 → 编辑器内引用它的实体渲染更新（同 handle 换值） |

3. book 补「Asset references」节（引用即路径、rename/move 联动语义、缺失清单、外部改名建议在编辑器内
   做或改完用 audit 检查）；buglist 打钩核对；roadmap T05 勾选；台账记行。

**验收标准**：
- [ ] 矩阵 10 格全过（BRP 日志+截图留档）；
- [ ] 全量门（`xtask fast`/`integration`/docs/doctests）按 2026-10-25 升级版门禁证据标准（日志全文复核，
  重跑覆盖归档）；
- [ ] 用户 30 秒清单：①给材质改名 → 打开引用它的场景 → 一切照旧；②删一个被引用的材质 → 看到谁在用
  它；③删掉一个纹理文件重开场景 → Missing 清单里找到它并一键换绑。

**测试设计**：真机脚本沉淀 `loop/qa/t05-final-live.ps1`（rename/move/delete/audit 全链，参照
`t04-final-live.ps1` 模式）。**buglist 吸收**：核对 Y8/W8/W10/W11/W12（+Y31/W7）备注与打钩。

**QA 清单（放行标准，全任务）**：
- [ ] T1/T2/T3 各自验收全绿；每个 🔴（N1/N3）与 Y8 有红→绿测试；
- [ ] 「不丢引用」铁证：rename/move 后旧路径不存在 + 引用串逐串比对 + 重载后 handle 指向新路径，三腿齐；
- [ ] quick 门（T1/T2）/ 全量门（T3）；
- [ ] 门禁证据以日志全文复核为准（README 2026-10-25 标准）。

---

## 三、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **稳定标识要不要引入 GUID/.meta** | A=**不引入**，路径即身份 + 操作联动重写（Godot 式）：零格式变更，与 `AssetIndex`「path is the identity」全链设计（头注释 `asset_index.rs:1-16`）、`AssetRef` 标注、migration 先例全部兼容；代价是编辑器外改名仍断（由 audit+重绑兜底）。B=资产 GUID（`.meta` sidecar 或中心 registry）：外部改名可重连，但 bevy `AssetServer` 以路径为键，需要全链间接层（index/referrers/加载/picker/migration 全改）+ 格式膨胀 + 外部工具删 meta 即断 + 存量迁移，工作量超 T05 一倍以上。C=轻量重连缓存（rename/move/delete 时落 old→new 映射，缺失时提示一键重连）：覆盖外部改名恢复，但缓存失配（他机/清缓存）即失效，多一套状态要维护 | **A 为主体**（roadmap 验收两句「改名移动不丢引用/删除示影响面」编辑器内操作即满足），B 明确不做（open-challenges 挂账说明取舍），C 不做（audit+重绑已是更通用的兜底） |
| 2 | **引用更新放 rename 侧还是 watch 侧** | A=operator 侧同步重写（rename/move/delete op 内一并落定）：事务性强、一次操作一个终态、note_written 先例现成；外部变化不覆盖。B=watcher 侧（rescan 推断 del+add 为改名并重写）：覆盖 OS 外部操作，但 notify 事件时序推断不可靠（同名歧义、部分写入、编辑中 tab 竞态），误重写风险高 | **A**；watcher 侧只做**检测与报告**（发现 gone 引用 → 下次 audit 呈现，不自动重写）。与「删除示影响面而非拦截」的现有哲学一致 |
| 3 | **影响面/断链的 UX 形态** | A=状态栏摘要（op 报告）+ Missing 清单视图（T2-3）：轻、可定位、有跳转与重绑入口。B=引用中心面板（双向浏览 who-uses-whom）：功能全但过重，file_card References + `asset.references` 已覆盖正向查询。C=rename 前预览确认对话框（列受影响文档+diff）：打断每次改名流，重 | **A**；B 的正向查询维持现状即可；C 不做（rename 保持轻操作，事后报告可展开） |
| 4 | **file.move 入口** | A=本任务补 `file.move` operator：验收句「移动不丢引用」才有编辑器内路径可验，实现复用 rename 联动链增量小。B=不补，只处理 OS 外部移动的报告：验收要走 OS 移动+watcher（裁决 2 已排除自动重写），等于验收句落空一半 | **A** |
| 5 | **打开中干净 tab 被 rename 联动后的基线** | A=内存 AST 重写 + 重算 `saved_doc_hash` 基线（保持干净）：编辑器自己写的变更不算用户编辑，语义最顺。B=重写后置脏（用户再 Ctrl+S 一次）：实现最少一行，但用户没动过却见脏标记。C=干净 tab 不改内存、强制从盘 reload：多一次读盘与闪烁 | **A**（T03 指纹设施直接支持：基线就是 `save.rs:413-433` 那组 setter）；脏 tab 保持脏、引用值照样重写 |
| 6 | **N6 Entity 字段处置** | A=实测定级 + 最小警示（保存时 Entity 字段指向文档外/已消亡实体则 warn）：诚实、小步。B=SceneNodeId 重映射全链（保存把 Entity 值译为目标节点 id、加载反译）：保真但要 reflect 转换层+类型约定+迁移，接近半稳定标识工程 | **A**（本任务）；B 连同裁决 1-B 一起挂 open-challenges；实测若发现现状是"字段根本不 emit"（静默丢），则升格为文档化限制+warn，同样走 A |
| 7 | **Y31（内嵌互引）归属** | A=T05-T2 吸收：两阶段加载改动集中在 `catalog.rs` 两处，有既有测试语境，且它就是"save→load 丢引用"本体。B=备案 T18（资产导入与热重载）：T18 也碰资产加载，但它是导入域不是引用保真域 | **A**（改动小、正属 T05 验收范畴；若程序侧评估两阶段加载风险超预期可回落 B，QA 不因此 FAIL） |
| 8 | **删除打开中场景的守卫强度** | A=非 force 拒绝 + force 关 tab 再删（T1-4 方案）：与 convert 守卫同构。B=直接允许但删除后自动关 tab：少一步确认，但"误删正编辑场景"无缓冲 | **A** |

---

## 四、风险与回滚

| 风险 | 缓解 |
|---|---|
| 引用重写波及面大（多文档批量改写），一次误写伤多个场景 | 重写器 AST 定位 + write_atomic + 每文档改写前后 `note_written`；guards 用例覆盖"同值非资产字段不误改"（W10）；`.bak`（T04-T2 已落）天然兜底可手回 |
| rename 联动与 external_watch/journal 的时序竞态（重写被读回当外部修改弹 reload） | `note_written` 双登记（asset_index + external_watch `note_known_content`）是 migration 已验证的模式，照搬；tab retarget 后 journal 条目路径同步（§五）；真机用例 T1 验收 7 钉死 |
| 文件夹 rename 的前缀重写把 `props2/` 误当 `props/` 前缀 | 前缀匹配按**路径组件边界**（`old == p || p.starts_with(old + "/")`），用例覆盖 `props` vs `props2` |
| 大小写两步 rename 中断留 `tmp` 中转名 | 中转名进 T04-T1 的孤儿 tmp 清理族；失败分支先尝试回滚第一步 |
| 内存态 referrers 扫描（打开中 tab AST）在大场景拖慢删除确认 | 扫描在确认对话框构造时一次性、只扫 AST 引用字段（scan 已按类型过滤），千节点量级毫秒级；超预期再加脏缓存 |
| audit 遍历不受信文档继承 Y28/Y30 类解析/遍历风险 | audit 沿用 `parse_bsn_text` 失败即跳过该文档（migration 同策略）；遍历按 `MAX_AST_DEPTH` 家族 cap |
| Y31 两阶段加载改动 catalog 热路径 | 改动限定内嵌资产加载入口两处，材质既有测试全绿为闸；风险超预期按裁决 7 回落备案 |
| 回滚 | 三任务独立成分支段：T1 重写器+三 op 扩展（revert 即回现状，无格式变更）；T2 audit/面板/防线（纯新增面，摘除无残留）；T3 工具+文档。全程零文件格式变更——这是本方案最大的回滚保险 |

---

## 五、与 T03/T04 已建设施的衔接

1. **T03 per-tab 指纹 = retarget 后干净态的维护者**：tab retarget 路径 + 内存 AST 重写后，按裁决 5 重算
   `saved_doc_hash`（`SceneTab` 基线 setter 在保存边界 `save.rs:413-433` 一侧），干净 tab 保持干净、
   脏 tab 保持脏——不引入第三轨脏判定。
2. **T04 journal = rename/move 的路径同步点**：`session_journal` 条目按 tab 持路径（`session_journal.rs`
   条目含 `tab 路径|null`）；retarget 时须同步在写 journal 条目的数据源（Scenes）上做，崩溃恢复后路径
   不落旧值。T1 验收补一条：脏 tab → rename → kill → 重启恢复的 tab 路径为新路径（与 T04 kill 链脚本
   复用）。
3. **T04 `.bak`/`write_atomic` = 重写器的写盘基座**：所有引用重写走 `write_atomic`（自动获得 `.bak`
   单份轮转），失败不损旧文件；「删除复活」类缺陷的防线与 T04「保存中断不损坏」共用同一基座。
4. **T04 `note_known_content` = 重写不被 external_watch 误报的关键**：migration 的 `note_written` 模式
   （`asset_migration.rs:221-226`）就是给 T05 准备的先例，重写器原样复用。
5. **T03 `jackdaw/history` / T04 `jackdaw/recovery` 的 BRP 模式 = `jackdaw/audit` 的模板**：读全局状态返
   JSON 的挂法与 headless 测法照此办理；MCP 第 23 工具与 recovery 工具同构。
6. **分支与行号基线**：本方案行号基于 `loop/t04-save-recovery` 7caf0bad。T04 终验 PASS 合入 main 后，
   T05 从 main 拉 `loop/t05-references`，行号按符号名重定位（矩阵证据均已给符号名）。
