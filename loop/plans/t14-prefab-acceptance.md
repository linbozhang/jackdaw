# T14 Prefab 工作流完整验收 — 实施方案

> 策划产物（2026-10-29，基于本地 main **ba9a53cc**（T13 收官合入）全量只读调研：编辑器
> `src/prefab/` 全 11 文件、`crates/jackdaw_prefab/`（resolve/source/model/components）、
> `crates/jackdaw_runtime/src/lib.rs` 装载链、`src/inspector/prefab_menu.rs`/
> `prefab_field_dots.rs`、`src/hierarchy.rs` 上下文菜单与四个 `prefab.*` operator、
> `src/undo_snapshot.rs`/`document_capture.rs` 撤销面、`tests/prefabs/`（5 文件 89 件）、
> `tests/operators/prefab_ops.rs`（16 件）、guards 邻域、buglist 全量 grep；**并写了三个
> 临时 headless 探针实测（跑完即删，工作树已还原干净）**，三个关键疑点全部定案，不靠猜测。
> 需求来源：`loop/plans/roadmap-game-dev.md` T14（P1 第八项，T01-T13 已闭环）。
> **验收原文**（roadmap 第 28 行，逐字核实）：「**验证既有创建/实例/覆盖/应用/还原/嵌套/
> 变体（不另起系统）。验收=改 Prefab 多实例更新+实例独有保留；undo/重开/导出一致。」**
> **任务定性（T01 同款验收型）**：主体是验证既有系统——Prefab 面在 T03（unpack 单写路径/
> SELF_PUSHING）、T04（write_atomic 落盘）、T05（rename retarget prefab cache）已有大改与
> 防线；「不另起系统」是硬约束。逐词拆解：七环节=创建/实例/覆盖/应用/还原/嵌套/变体，
> 五维=改 Prefab 多实例更新/实例独有保留/undo/重开/导出一致——可矩阵化的 35 格（§二）。
> 发现的缺陷按 T03 先例「只记不修→主控裁定吸收面」。缺陷主体是本方案新发现的
> **PF1-PF8**（PF 系：Prefab，避开 buglist R/Y/W/A/N 系与 T01-T13 各任务编号系），其中
> **PF1/PF2 经探针实证为 🔴 级**（§三）；buglist 既有 prefab 域条目 R3/Y32/W22/W23/A6
> 并账不重复开票（§四重叠表）。真机口径：**macOS（本机）**，bash+curl+jq 驱动编辑器 BRP
> 与游戏 BRP 15702（`loop/qa/t12t3-live-chains.sh` 形态复用）；**勿设 RUST_BACKTRACE**
> （T11-T3 口径）；N13 按 T11/T12/T13 口径绕行+记数；warn 形态扫描（`cannot apply|cannot
> read|does not read as|UnresolvedTypes|prefab`）入常备腿；门链与编辑器/游戏不同窗
> （T12-T3 §九-7）；A6 watcher flaky 按「已定案环境票」口径处置。

---

## 0. 架构事实（核实结论，方案的地基）

**总判断：Prefab 七环节的机制面全部建成且有相当厚的测试（tests/prefabs 89 件 + operators
16 件 + guards 邻域 + jackdaw_prefab/runtime 单测）；「应用（apply）」一条链上存在两个
探针实证的数据一致性缺陷（PF1/PF2），变体×嵌套一格有 buglist 既有 🔴（R3）——T14 的
工作不是建系统，是把 35 格矩阵跑出「哪些环节在真机+导出形态下真的成立」，并把 apply
链的两个数据缺陷按裁定吸收。** 十条事实：

- **事实一：词表与解析器是共享成品。** 三组件 `Prefab`/`PrefabEntityId`/`IsA`（含
  `deleted` 列表）定义在 `crates/jackdaw_prefab/src/components.rs:12-39`，`#[type_path]`
  钉死序列化路径（文件格式的一部分，防漂移测试 :57-64）；编辑器与游戏运行时共用同一
  解析器 `resolve_scene`（`crates/jackdaw_prefab/src/resolve.rs:92-100`：展开 IsA→继承根
  组件→按 PrefabEntityId 物化子孙（跳过 deleted）→稀疏覆盖合并），编辑器经
  `src/prefab/resolver_bsn.rs:6-12` re-export，游戏在装载时
  `resolve_prefab_references`（`crates/jackdaw_runtime/src/lib.rs:885-929`）调用——
  「编辑器所见=游戏所得」在解析层同源。环检测/深度帽（MAX_PREFAB_DEPTH=8，
  resolve.rs:24）双测在案（resolver 4 件+runtime 3 件）。
- **事实二：创建=四条入口一个落点。** ①选区打包 `prefab.save_as_prefab`（hierarchy 对话框
  `src/hierarchy.rs:3303-3345`→`save_as_prefab_from_selection`，`src/prefab/operators.rs:378-413`：
  选区归一化→BFS 稳定编号 PrefabEntityId 1..N→合成根→原位换实例）；②整场景转 prefab
  `prefab.save_scene_as_prefab`（hierarchy.rs:3349→`save_scene_as_prefab` operators.rs:1006-1124，
  多根自动加合成根）；③批量打包 `prefab.pack`/`prefab.pack_matching`（operators.rs:757-838，
  结构签名/名字前缀两种匹配）；④写盘统一 `write_prefab_doc`（operators.rs:246-284，
  .jsn 遗留重定向 .bsn+.bak 备份）。落盘原子性：`save_prefab_to_disk` 走 T04 的
  `write_atomic`（operators.rs:2026，「prefab 是权威作者数据」注释原文）。
- **事实三：实例化=稀疏 IsA 节点+解析物化。** `prefab.spawn_instance`（operators.rs:2085-2133，
  assets 相对路径+parent 参数+`resolve_asset_path` 越界拒绝 :665-686）→实例根只写
  `IsA{source,deleted}+PrefabEntityId(0)+Transform 平移稀疏 delta`（`instance_node_patches`
  operators.rs:1294-1365，UI 场景不带 Transform）；`entity.add.prefab`（entity_ops.rs:3042）
  走原生文件选择对话框（`open_prefab_picker`/`poll_prefab_pick` operators.rs:1134-1164）——
  **对话框路径无任何 headless 测试**；UI 场景导入同通道（`prefab_ui_import.rs` 7 件背书，
  `AuthoredUiSceneRoot`/`ImportedUiSceneRoot` 判别式 `src/prefab/mod.rs:43-56`）。
- **事实四：覆盖=稀疏 delta，三层判定机制齐备。** 覆盖判定 `field_is_overridden`/
  `collect_overridden_paths`（`src/prefab/overrides_bsn.rs:47-134`，struct 递归到
  `translation.x` 叶级）；保存时 sparsify 还原（`sparsify_inherited_descendants`
  resolve.rs:364-418，实例根也参与 :467-490）；Inspector 侧覆盖点标（实心=覆盖/空心=继承）
  `PrefabFieldOverrideDot`（`src/inspector/prefab_field_dots.rs:29-41`，点击即 revert），
  ECS-only 继承子孙回落 prefab 基线渲染（:49-84）。T03 交付的框架快照把「继承子孙上的
  编辑」捕获为覆盖（lifecycle `snapshot_captures_inherited_descendant_edit_as_override`:2832）。
- **事实五：应用（apply）三条路，全部只改缓存不落盘。** ①单字段 `prefab.apply_to_source`
  （operators.rs:1816-1876：`PrefabAstCache::mutate` 改基线+清场景侧 delta）②组件级/全量
  apply（inspector `apply_component_to_source` prefab_menu.rs:205-242 逐字段派发①；
  hierarchy 右键「Apply All」hierarchy.rs:2562-2574→`apply_all_overrides_to_source`
  operators.rs:1928-1990 diff 全部覆盖叶）；③场景内批量 `prefab.bulk_apply_in_scene`
  （operators.rs:1782-1810，**语义不同：给每个实例写各自的覆盖，不改基线**）。
  **`apply_to_prefab_source` 不调 `save_prefab_to_disk`**——落盘只发生在 `prefab.save`
  （激活 prefab tab）/`save_scene_as_prefab`/`repair_self_cycles` 三处（全仓 callers grep），
  「apply 不写盘、落盘推迟到显式保存」有测试钉着（lifecycle
  `apply_to_source_updates_cache_without_disk_write`:1230）。传播靠缓存 epoch 驱动器
  `drive_respawn_on_prefab_cache_change`（`src/prefab/sync.rs:25-41`：epoch 变→场景画自
  变更的 prefab→`reload_all_instances`）。
- **事实六：还原（revert）面完整。** 字段级 `prefab.revert_field`（operators.rs:1511-1533，
  基线经 `expanded_prefab_source` 预展开 IsA 链）、组件级 `prefab.revert_component`
  （:1538-1556，无基线时拒绝删除防静默毁数据）、全量 `prefab.revert_all`（:1570-1694，
  `RevertReport{reverted,unresolved}`+部分还原 warn 可见）；拆出单实例 `prefab.unpack_child`
  （:1887-1921，T03 返工后的单写路径：AST 节点本体 move+strip PrefabEntityId+IsA.deleted
  追加，ECS reparent 同 op 不双推——Y4 修复面）、`prefab.unbundle_instance`（:928-999，
  剥全部标记+placement 折入顶层子）。五者全部 operator 化（:2241-2540）+Inspector 右键
  五动作（prefab_menu.rs:32-36）+hierarchy 右键四动作（hierarchy.rs:2329-2350）。
- **事实七：嵌套与变体机制面建成，变体有一格已知 🔴。** 嵌套：外层 prefab 的实例节点
  携自己的 PrefabEntityId、子树按各自 prefab 编号（`scoped_descendants` resolve.rs:215-227，
  `nested_instance_ids` 两件测试钉 id 空间独立性）；缓存预载整条 IsA 祖先链
  （`cache_prefab_tree` save_load.rs:119-160）否则嵌套实例解不出。变体：`save_as_variant`
  （operators.rs:1701-1778，变体根 `Prefab+PrefabEntityId(0)+IsA(原件,deleted)`+实例覆盖
  成为变体基线+实例改接线到变体），runtime 端「变体经 base 解析」有测试
  （prefab_resolution.rs:330）；**但子孙全部挂到变体根下=深层级拍平，即 buglist R3
  （🔴，operators.rs:1718-1744 代码现状与条目描述逐字吻合，本轮复核仍存活）**。
- **事实八：撤销/脏/恢复三面已对 prefab 适配。** 撤销=框架快照（场景文档文本）+
  undo/redo 重装时**按当前缓存**重新解析（`undo_snapshot.rs:293-324`）；快照失效输入
  含 `changed::<PrefabAstCache>`（`src/document_capture.rs:364-399`）；T03 的
  SELF_PUSHING/SNAPSHOT_BACKED 双清单把 prefab 系 op 的 undo 声明钉死
  （`tests/guards/record_counts.rs:494-546`：spawn_instance/unpack_child/unbundle_instance/
  apply_to_source 在 mode-B 快照背书名单）；脏标记 per-tab 全指纹（T03-T1）对 prefab tab
  同样生效（lifecycle `scene_save_on_prefab_tab_clears_dirty_state`:1954）；T04 session
  journal 记 prefab tab 形态（`src/scene_io/session_journal.rs:379,436`）；T05 rename/move
  retarget prefab cache 与 tab（buglist Y8 已修+A3/A4 波次补 Mac 形态）。
- **事实九：外部编辑→编辑器更新走 watcher，且次序正确。** `src/prefab/watcher.rs`：
  watch 粒度=文件夹+150ms 去抖（:34,144-210），**先 `capture_sparse_scene_text`（旧基线
  下稀疏化）再更新缓存**（:296-306，注释明言「对新基线比较会把每个继承值误读为作者
  覆盖」），自写回声按指纹跳过（:278-289），只重载受影响实例保实体 id
  （`reload_instances_of` :352-456，其他实体不动），解析失败保留旧副本（:308-318）。
  打开中的 prefab tab 让位给 external_watch 提示（:247-254）。**该路径有测试但即 A6
  满载 flaky 件**（buglist A6：干净 main 同红 88/1 已定案环境票）。
- **事实十：导出对 prefab 零感知但天然兼容。** 导出 staging 整 assets 树拷贝
  （`crates/jackdaw_project_build/src/export.rs`），prefab .bsn 作为内容随包；游戏装载时
  解析 prefab 引用（事实一），assets 外引用拒绝（runtime lib.rs:912-918）+坏文档 fail-soft
  spawn as authored+warn 点名（:921-928）。**「编辑器改 prefab→导出→游戏更新」端到端
  无任何测试**（runtime 测试全部用手写文档，非编辑器产物）——导出维度是矩阵最大缺口。

### 策划探针定案（临时测试实测，跑完即删；程序实施前可低成本复跑）

三探针形态：全编辑器插件 headless app（`JackdawEditorPlugins`，tests/util 同构）+
`jd` 式工程（assets/p.bsn + assets/world.bsn 经 `scene_open_system` 打开）+ operator 框架
派发（`creates_history_entry:true`）+ `history.undo`。

1. **探针一（undo×apply）**：实例覆盖 x=0→5 → `prefab.apply_to_source` → cache 基线=5
   ✅；**场景侧 delta 未被清除（=buglist W23 的实锤放大：`retain(|f| f.name != "translation.x")`
   永不命中顶层字段名 `translation`）**；`history.undo` 后：cache=5、doc delta=5、ECS=5
   ——**undo 是一个不改变任何状态的历史条目**（快照只装场景文档，缓存不在快照内）。
2. **探针二（多实例传播）**：两实例 a/b → a 覆盖 x=5 → apply → cache 基线=5，**b 的 ECS
   x 仍=0，且 b 的文档节点从此持有 authored x=0 覆盖**；手动再跑
   `reload_all_instances` 十帧+一次，b 仍=0。机制（代码链定案）：编辑器装载把**已解析
   形态**装为活文档（打开后 b 节点即持完整 Transform=Some(0.0)，探针打印实证）；
   `reload_all_instances` 的稀疏 emit **按当前（新）缓存**做基线比对
   （`capture_sparse_scene_text` watcher.rs:508-520→emit 路径 sparsify），b 的 x=0 对新
   基线 5 不等→固化为作者覆盖→**b 永久冻结，不再跟随该字段**。watcher 路径无此问题
   （先捕获后更新，watcher.rs:291-306 次序注释即此病的防其他实例版）——**缓存突变
   （apply/propagate）后的 reload 全部踩雷**。
3. **探针三（apply×重开）**：apply（只改缓存）→ 存场景（自然手势 Ctrl+S）→ 新 app 从盘
   重开 → **实例 x=0，应用的 5.0 丢失**（盘上 prefab 未写、场景 delta 已被 sparsify 收走
   ——两处都不剩）。

---

## 一、验收句拆解 → 矩阵设计

「改 Prefab 多实例更新」=改 prefab 基线后，指向它的**全部实例**收到新基线（两条改法：
外部编辑文件/watcher 路、apply/propagate/缓存路）；「实例独有保留」=实例上的覆盖/新增
组件/unpack/unbundle 产物在基线变更后原样保留；「undo 一致」=每环节操作后 undo 恰当
回退、不产生重复/幽灵/坏中间态；「重开一致」=保存→关闭→重开（含编辑器重启形态）后
场景与 prefab 文件状态一致；「导出一致」=编辑器所见=direct run=导出 staged 独立启动
（T12 格 9 五点链「改→重导→变」为铁证形态）。七环节×五维=35 格主矩阵（§二），每格
标：✅ 现有测试锚（file:test）/⚠️ 缺口（T1 补）/🔴 预期 FAIL（缺陷候选，只记不修）。

**「重开」口径（决策 4）**：主口径=保存场景→关 tab→重开（headless 可断言）；加严格=
编辑器进程重启（真机腿）；prefab tab 自身的重开=重开 tab 后 cache 从盘重建。

## 二、35 格主矩阵与现状覆盖

断言通道缩写：H=headless guards/integration（现有测试锚或 T1 新增）、R=真机 BRP
（`jackdaw/call_operator`+`world.query`+`jackdaw/entity`）、PX=截图、G=游戏 BRP 15702。

### A. 创建（pack / save_scene_as_prefab / save_as_prefab_from_selection / pack_matching）

| 维度 | 现状 | 格判 |
|---|---|---|
| 多实例更新 | pack_matching 一口气把 N 个同形组换成同源实例（operators.rs:775-838；prefab_ops 4 件含 structural/prefix/差异拒绝/保 transform）| ✅H |
| 实例独有保留 | pack 后各实例保各自 transform（prefab_ops pack_writes...+three_instances_keep_independent_positions lifecycle:2573）| ✅H |
| undo | `undo_of_pack_puts_the_group_back_and_leaves_the_file`（prefab_ops:170，文件留下=既有约定）；快照族 3 件（lifecycle:3172/3248/3580）| ✅H |
| 重开 | `save_then_respawn_keeps_isa_on_instance_entity`:2515、`save_round_trip_preserves_prefab_markers`:1524、markers 防漂移（components.rs 测试）| ✅H |
| 导出 | packed 产物在游戏端解析：仅手写文档测试（prefab_resolution.rs），**编辑器 pack→导出→游戏**无测试 | ⚠️R+G（T1 真机格 A-5） |

### B. 实例（spawn_instance / entity.add.prefab 对话框 / UI 场景导入 / 多实例）

| 维度 | 现状 | 格判 |
|---|---|---|
| 多实例更新 | spawn 后新实例继承当期基线；`a_run_of_spawns_loads_each_instance_once`（prefab_ops:810） | ✅H |
| 实例独有保留 | `three_instances_keep_independent_positions`:2573+`each_carry_isa_on_ecs`:2662+batch_undo spawn 批量（guards:83-248） | ✅H |
| undo | `spawn_instance_undo_via_framework_snapshot_round_trip`:3248+guards `a_placed_prefab_instance_keeps_its_node_through_undo_and_redo`:686+redo 链 :574-598 | ✅H |
| 重开 | `load_resolves_isa_spawns_inherited_entities`:380+`opening_a_scene_names_its_prefab_instances_without_dirtying_the_tab`（guards undo_history:728） | ✅H |
| 导出 | 同 A-导出：无端到端 | ⚠️R+G（并入 A-5 同腿） |
| （入口面） | `entity.add.prefab` 原生对话框零测试；UI 导入 7 件（prefab_ui_import.rs） | ⚠️R（真机格 B-6：对话框腿）；UI 导入 ✅H |

### C. 覆盖（实例上编辑→稀疏 delta→点标/菜单可见）

| 维度 | 现状 | 格判 |
|---|---|---|
| 多实例更新 | 覆盖不外溢：`editing_an_inherited_child_writes_an_override_and_leaves_the_source_alone`（ui_import:229） | ✅H |
| 实例独有保留 | 外部改 prefab 后覆盖保留：watcher 先捕获后更新（事实九）+`snapshot_captures_inherited_descendant_edit_as_override`:2832+`prefab_file_change_triggers_reload`:683（**A6 flaky 件**——本格 headless 按 A6 口径隔离跑，真机腿为正主） | ✅H（A6 口径）+⚠️R |
| undo | `an_edit_on_a_prefab_instance_undoes_and_redoes`（guards undo_history:567）+typed/snapshot 交错 :3670 | ✅H |
| 重开 | `scene_save_reopen_round_trip_preserves_instance_and_override`:3801 | ✅H |
| 导出 | `an_authored_override_wins_over_the_inherited_value`（prefab_resolution.rs:65，手写文档）；端到端缺口同 A | ⚠️R+G（C-5=**验收句「实例独有保留」的导出正主格**） |
| （可见面） | 覆盖点标/右键五动作无 UI 级测试（prefab_menu.rs 逻辑有单测） | ⚠️R（真机格 C-6：点标视觉+右键菜单真点击） |

### D. 应用（apply_to_source / Apply All / bulk_apply / propagate）

| 维度 | 现状 | 格判 |
|---|---|---|
| 多实例更新 | cache 写入 ✅（lifecycle:1161）；**传播到兄弟实例 🔴 失效——PF1（探针二：b 冻结在旧值且被固化为作者覆盖，永不再跟随）**；watcher 路的外部编辑传播 ✅（:683，A6 口径） | 🔴PF1（缓存路）/✅H（文件路） |
| 实例独有保留 | 覆盖在 apply 后保留 ✅（W23 使 delta 不清）；**但兄弟实例的继承值被错误升格为作者覆盖=PF1 的另一面** | 🔴PF1 牵连 |
| undo | apply 的 undo 是 **no-op 历史条目**（探针一：undo 前后三态全等；快照不装缓存）——不损坏但不回退，语义未定案 | 🔴PF4（低危，决策 2） |
| 重开 | **apply 不落盘→存场景→重开，应用值丢失（探针三：5.0→0）**——应用成果只活在内存缓存 | 🔴PF2 |
| 导出 | 同 PF2：不存 prefab 就导出→游戏拿到旧基线（导出只打包磁盘） | 🔴PF2 牵连（与 PF2 同修） |
| （Apply All 面） | `apply_all_overrides_to_source`（operators.rs:1928）无直接测试 | ⚠️H（T1 补） |

### E. 还原（revert_field / revert_component / revert_all / unpack_child / unbundle）

| 维度 | 现状 | 格判 |
|---|---|---|
| 多实例更新 | 还原只动本实例；嵌套继承字段的还原 ✅（`revert_all_reverts_field_inherited_through_a_nested_prefab`:3917） | ✅H |
| 实例独有保留 | `revert_component_preserves_instance_only_addition`:974（实例新增组件保留）+无基线拒绝删除（operators.rs:1542-1547）+`revert_all_reports_targets_with_no_baseline`:4004 部分还原可见 | ✅H |
| undo | revert 系快照背书 op（component.revert_baseline 在 SNAPSHOT_BACKED 名单 record_counts.rs:545）——**undo-of-revert 无直接测试** | ⚠️H（T1 补 1 件） |
| 重开 | 还原后 sparsify 收走 delta→重开=基线 ✅（机制链，无独立测试——与 C-重开同锚，可并格） | ✅H（并格） |
| 导出 | 还原后导出=基线值——runtime 覆盖胜出测试的反面，无端到端 | ⚠️R+G（并入 A-5 腿参数化） |
| （unpack/unbundle 面） | unpack 单写路径+单条 undo（Y4 已修+lifecycle:1315/3407）；unbundle 提升+世界位置保位（:2239+operators.rs:928-999）；**嵌套实例内层子孙的 unpack 持久性（deleted 写到活文档内层实例节点上，重载后是否存活）无测试——T1 探针格，不定罪** | ⚠️H（T1 探针格 E-6） |

### F. 嵌套（IsA 链 / 深度帽 / 环 / 嵌套×unpack / 嵌套×变体）

| 维度 | 现状 | 格判 |
|---|---|---|
| 多实例更新 | 外层 prefab 变更沿链传播（watcher 路径 :683+sync.rs `prefabs_drawn_from` 递归跟随）；缓存预载整链（save_load.rs:119-160） | ✅H（A6 口径） |
| 实例独有保留 | 嵌套 id 空间独立两件（nested_instance_ids.rs:64/82）+嵌套覆盖合并（resolver nested_prefab_expands:762） | ✅H |
| undo | 嵌套实例的 spawn/unpack undo 走同快照机制（:3248 族覆盖单层；嵌套形态无独立 undo 测试——机制同源，低风险） | ✅H（锚单层） |
| 重开 | 嵌套重开解析（cache_prefab_tree+runtime read_prefab_sources 递归）✅ 机制链；`revert_all` 嵌套件背书 | ✅H |
| 导出 | 嵌套在游戏端解析：`read_prefab_sources` 递归+越界拒绝（runtime lib.rs:939-966+prefab_resolution.rs:285 两件） | ✅H；端到端并入 A-5 |
| （变体×嵌套） | **R3：3 层 prefab 存变体→拍平+位置错乱+内嵌 IsA 被烤死（buglist 🔴，本轮复核存活）** | 🔴R3（既有票，吸收裁定=决策 3） |

### G. 变体（save_as_variant / 变体再实例化 / 变体源路径）

| 维度 | 现状 | 格判 |
|---|---|---|
| 多实例更新 | 改 base→变体实例跟随（IsA 链直通）——机制链同 F；runtime `a_variant_resolves_through_the_base_it_was_cut_from`:330 | ✅H |
| 实例独有保留 | 变体把覆盖升为自身基线+实例改接线（operators.rs:1755-1777；lifecycle:1029） | ✅H |
| undo | 快照把实例接回原源；**变体文件留盘**（与 pack 同约定，无测试钉——T1 补 1 件） | ⚠️H（T1 补） |
| 重开 | `a_saved_variant_names_its_base_relative_to_itself`（prefab_source_paths:183）+UI 变体在 stage 编辑（ui_import:388） | ✅H |
| 导出 | 变体在游戏端经 base 解析 ✅（runtime:330）；端到端并入 A-5 | ⚠️R+G |
| （浅层形态） | 单层变体正确（lifecycle:1029 只覆盖根） | ✅H |

**矩阵统计**：✅ 有锚 24 格｜⚠️ 缺口（T1 补测试/真机格）8 格｜🔴 预期 FAIL 3 格
（PF1、PF2、R3——外加 PF4 语义格）。

## 三、缺陷候选（P 系编号，只记不修→主控裁定吸收面）

| 编号 | 严重度 | 描述 | 证据 | 处置建议 |
|---|---|---|---|---|
| **PF1** | 🔴 | **apply/propagate（缓存突变路）的传播把兄弟实例冻结**：改基线后 reload 的稀疏 emit 按新基线比对，兄弟实例的旧继承值被升格为作者覆盖，**永久不再跟随 prefab**；「改 Prefab 多实例更新」在 apply 路径失效 | 探针二（b_x=0 且 doc 持 Some(0.0)，手动 reload 仍 0）；机制链=事实五+事实九次序差；受害 callers=`drive_respawn_on_prefab_cache_change`（sync.rs:25）、`apply_to_prefab_source`/`bulk_apply`/`propagate_instance_to_prefab` 尾部的 `reload_all_instances` | **吸收**。修向 A：缓存突变路统一「先捕获稀疏文本再 mutate」（对齐 watcher.rs:291-306 既有正确次序，提取为共用前置）；修向 B：reload 的 emit 用「上次解析基线」快照比对。A 改动面小且与 watcher 同构 |
| **PF2** | 🔴 | **apply 成果不落盘，重开/导出即丢**：apply 只改缓存（现状有测试钉「不写盘」），用户自然手势=存场景→重开，应用的值两处皆无（盘上 prefab 旧、场景 delta 被 sparsify 收走）；导出同样拿到旧基线 | 探针三（REOPENED x=0，applied 5.0）；lifecycle:1230（不写盘是被钉的现状）；`save_prefab_to_disk` callers 仅 3 处 | **吸收**。修向 A：apply 后自动 `save_prefab_to_disk`（+指纹登记防 watcher 回声，机制现成 operators.rs:2028-2032）；修向 B：置 prefab tab/缓存脏+Play/导出前保存链覆盖（T08 三腿保护同款）；修向 C：维持现状+apply 后状态栏 warn「prefab 未保存」。决策 1 裁定 |
| **PF3** | 🔴（=buglist R3） | **save_as_variant 拍平任意深层级**：子孙全挂变体根、内嵌 IsA 被 drop_markers 烤死、世界位置错乱 | buglist R3（operators.rs:1718-1744 本轮复核逐字吻合）；lifecycle:1029 只测单层所以绿 | **建议吸收**（变体环节的验收格 F/G×嵌套直接踩）；修向=按 `ast_parent_of` 重建变体内父子（buglist 修复方向原文） |
| **PF4** | 🟡 | **apply 的 undo 是 no-op 历史条目**：快照只装场景文档，缓存不在快照内；undo 前后三态全等（探针一），撤销栈多一条无效记录；与 `allows_undo=true` 声明相悖 | 探针一；undo_snapshot.rs:293-324 只重装文档；record_counts.rs:543 把 apply 归 mode-B 快照背书 | 语义定案（决策 2）：A=apply 改 `allows_undo=false`（文件级操作不可撤销，Unity 同语义，改声明+名单）；B=快照扩展装缓存（重，不建议）；C=维持（无实效但无害） |
| **PF5** | 🟡（=buglist W23 放大） | **apply 清场景侧 delta 按顶层字段名整名匹配，点路径清不掉**：`translation.x` 永不命中顶层 `translation`——文档留脏（本轮探针一实测 doc_override=Some(5.0) 存续）；后果有限（sparsify 保存时收走）但使「apply 后文档=基线」的不变量破 | 探针一；buglist W23（operators.rs:1854-1871） | 随 PF1/PF2 同批顺手修（先按 `.` 取首段再 retain，buglist 修复方向原文） |
| **PF6** | ⚪（=buglist W22） | `json_to_bsn_value` 把 null 映射成空 List | buglist W22（operators.rs:2613-2634） | 维持 buglist 票，不吸收（T14 矩阵不经过 null 值路径） |
| **PF7** | ⚪（=buglist Y32） | `bsn_value_eq` O(n²) 位于 prefab 热路径 | buglist Y32 | 维持 buglist 票；T14 真机若遇大 prefab 卡顿按此归因，不另立 |
| **PF8** | ⚪ | **端到端导出链无测试**（编辑器产物→导出→游戏），矩阵 A/B/C/E/F/G 导出维全靠手写文档测试背书 | 事实十 | 非缺陷=验收缺口，T1 真机格 A-5 衡 |

统计：🔴 3（PF1/PF2/PF3）｜🟡 2（PF4/PF5）｜⚪ 3（PF6/PF7/PF8）。

### buglist 重叠表（prefab 域全量扫描）

| 条目 | 一句话 | T14 处置 |
|---|---|---|
| R3 | 变体拍平深层级 | **并账为 PF3**（本轮复核存活；吸收裁定=决策 3，修后 buglist 打钩） |
| Y4（已修） | unpack 双撤销记录 | 知悉：T03 修复面即本矩阵 E-undo 格的锚，回归必跑 |
| Y8（已修） | file.rename tab retarget | 知悉：T05 修复+A3/A4 Mac 补丁；矩阵 T1 补一条「rename 已开 prefab tab→cache retarget」回归腿 |
| Y32 | bsn_value_eq O(n²) | 并账为 PF7（不吸收） |
| W22/W23 | null→[] / 点路径清不掉 | W23 并账为 PF5（吸收）；W22 维持 |
| A1 | brush.join recenter 位移不入撤销 | **不吸收**（brush 域非 prefab）；prefab 矩阵 undo 格不受扰 |
| A6 | prefab watcher 满载 flaky+磁盘高压 | **知悉+按定案口径**：headless `prefab_file_change_triggers_reload` 相关件隔离跑/按环境票放行；**真机 watcher 格（外部编辑）在真机跑不受此票影响**；跑门前清磁盘 |
| N13 | PIE drain panic | 绕行+记数（T11/T12/T13 口径；PIE 格不受阻，错误处理器捕获编辑器存活） |
| R4 | 远程实体树父子解析失配 | **知悉+绕行**：真机断言不用 `jackdaw/scene_snapshot` 的实体树父子形态，用 `world.query`（组件值）+`jackdaw/entity`（BSN 文本）替代——prefab 实例断言主通道 |
| 其余 | 无 prefab 直接条目（R 系其余/Y/W 均 prefab 外域） | 无动作 |

## 四、headless vs 真机分格（T12 纪律：模板/交互类真机腿前置）

**headless 半边（T1 交付，guards/integration）**：35 格中 24 格的机制锚已有；T1 补 6 件
（§六 T1 清单）。BRP 工具面对 prefab 的可达性盘点：

- **operator 面（全可达）**：14 个 `prefab.*`/`entity.add.prefab` 全是注册 operator
  （operators.rs:2036-2557+entity_ops.rs:3042+hierarchy.rs:3303-3406），`jackdaw/call_operator`
  直达（batch_undo.rs:83-248 即 BRP batch 形态先例）——headless 与真机同通道。
- **读出面**：实例断言走 `world.query`（Transform/组件值）与 `jackdaw/entity`（BSN 文本含
  IsA/PrefabEntityId）；`IsA` 命名实体可在 `jackdaw/entity name=` 解析（server.rs:451-459
  为无名实例留了 IsA 回退查询）；N12 域界照旧（bevy 内建方法查不到 jackdaw 域实体时用
  jackdaw 方法）。**`scene_snapshot` 实体树父子不可用（R4）——绕行。**
- **语义边界**：`component.add` 对实例实体=写场景侧覆盖（走快照，与手改同路径）——矩阵
  C 格的覆盖注入通道；`scene_snapshot` 对 prefab 实例只投影 ECS 终态（已解析形态），
  IsA/稀疏层不可见——**验证「实例化机制」必须走 `jackdaw/scene_bsn`/`jackdaw/entity` 读
  文档层，不能只看 ECS**（headless 测试直读 SceneBsnAst 同理）。
- **watcher/文件系统**：外部编辑格 headless 依赖 notify 事件+A6 flaky——**此格真机优先**
  （真机 echo 写文件+观察编辑器 reload，一腿定案）。

**真机半边（Mac，bash+curl+jq；T1 末+T3 集中跑）**：

| # | 真机格 | 断言通道 | 为什么必须真机 |
|---|---|---|---|
| L1 | `entity.add.prefab` 原生对话框选文件→实例落地 | R（实例计数+transform）+PX | rfd 原生对话框无 headless 测试 |
| L2 | Inspector 覆盖点标（实/空）+右键五动作真点击（revert_field/apply_to_source/bulk_apply/revert_component/apply_field_to_source） | R（值翻转）+PX（点标） | UI 菜单链+视觉，headless 只测过逻辑函数 |
| L3 | hierarchy 右键 prefab 四动作（Revert All/Save as Variant/Apply All/Unbundle）+Save as Prefab 对话框 | R+PX（对话框） | 同上；对话框两条（名字输入+确认） |
| L4 | **外部编辑 prefab 文件→编辑器多实例更新+独有保留**（PF1 的文件路反证+矩阵 C-保持格真机主证） | echo 写盘→R 读两实例值 | watcher 真事件链；headless 该件 A6 flaky |
| L5 | PIE：场景含 prefab 实例→游戏 BRP 断言实例在游戏世界（继承+覆盖值）→Stop 后编辑态还原（T06 铁证链对 prefab tab 复跑） | G+R | 编辑器/游戏双世界同源解析的活证 |
| L6 | **导出一致五点链**：改 prefab→存→`game.export`→staged 独立启动→G 断言新值→改回重导复原 | G+盘上 SHA | 验收句「导出一致」正主格（PF2 修复后此链必须过） |
| L7 | 编辑器重启重开（加严重开口径）：存→退出→重启→实例/覆盖/应用值原样 | R | journal/恢复链与 prefab tab 恢复的活证 |
| L8 | 键位 undo 抽查（Cmd/Ctrl+Z 按 classic preset 实际键）对 spawn/pack 各一链 | R（history 工具） | T03 真机链的 prefab 形态复验 |

## 五、分任务拆解（T1/T2/T3）

### T1「矩阵补锚 + 探针复核 + 真机矩阵 + 缺陷只记不修」（验收主任务）

1. **headless 补锚 6 件**（tests/prefabs 或 tests/operators，形态照旧）：
   ①apply 多实例传播格（两实例→apply→断言兄弟实例值——**现状即 PF1 红证**，红→绿留
   T2）；②`apply_all_overrides_to_source` 直测（多字段 diff→cache 全量更新+实例侧清理）；
   ③undo-of-revert（revert→undo→覆盖回归）；④variant-undo（存变体→undo→实例接回原源
   +变体文件留盘约定钉死）；⑤嵌套实例内层子孙 unpack 持久性探针格（存活/丢失二值如实
   记录，不定罪）；⑥rename 已开 prefab tab 的 cache retarget 回归腿（Y8 面的 prefab 形态）。
2. **探针复核**：程序对 PF1/PF2/PF4 三个探针独立复跑（配方在本方案 §0 探针节，30 行级
   临时测试），红证归档 `loop/reports/t14t1-probe*.log`——不盲从策划结论。
3. **真机矩阵 L1-L8**（§四表；fixture 工程=`jd new` 出 `loop-mac/t14-prefab`，手写
   assets/prefabs/{rock.bsn(单层), barrel.bsn(嵌套一层), base.bsn(变体底板)}+world.bsn
   两实例+覆盖；流程脚本 `loop/qa/t14-live.sh`（t12t3-live-chains.sh 形态：leg/summary/
   cleanup trap+warn 形态扫描+N13 记数）。
4. **缺陷编目**（不修）：PF1-PF8 逐条复现在档；R3 维持 buglist 原票。
5. 出 QA 报告：35 格逐格判定（✅/⚠️/🔴+格号指认），四门禁绿。

**验收标准**：矩阵 35 格全部有判定（🔴 格=红证在档非悬置）；L1-L8 腿全跑（L4/L6 为
验收句正主格，FAIL 即 PF1/PF2 定罪证据）；探针独立复现 3/3；quick 四门+日志全文复核。

### T2「修复吸收轮」（按主控裁定，预计 PF1/PF2/PF5 必吸、PF3/PF4 待裁）

1. PF1：缓存突变路统一「先捕获后突变」（提取 watcher 的次序纪律为共用前置；全量
   reload callers 清单逐一对齐：sync.rs 驱动器/operators 三处/hierarchy apply-all）。
   T1-① 红转绿+新增「apply 后外部再改 prefab→兄弟实例仍跟随」深化格。
2. PF2：按决策 1 形态落地（建议 A：apply 后自动落盘+指纹登记；或 B：脏标记+T08 保存
   链覆盖）。真机 L6 五点链转绿为放行条件。
3. PF5 顺手修（首段匹配）；PF4 按决策 2（建议 A：apply 改不可撤销+名单同步）。
4. PF3（若裁定吸收）：按 buglist 修复方向重建变体内父子+内嵌 IsA 保留；嵌套×变体格
   红转绿+3 层夹具测试。
5. 回归放行条件：tests/prefabs 89 件+operators 16 件+guards 全绿零放宽；T03 undo 面
   （record_counts 双清单）、T05 引用面、T07 导出面、T13 flow 面回归逐条指认。

### T3「终验 + 文档」

1. 35 格终态复跑（含 T2 修复面转绿确认）；L1-L8 全腿复跑。
2. book 文档：`book/src/user-guide/prefabs.md` 增补（若已有则校订）——七环节工作流速览
   +apply 落盘语义（T2 后的定案）+变体层级规则+常见陷阱（PF1 修复前后的行为边界）。
3. buglist 处置：吸收修复的条目打钩+备注（R3/W23 若修）；台账 `loop/progress.md` 记一行；
   roadmap 勾选 T14。
4. 终验门：全量门（fmt/clippy 全仓/单测/integration/doctests/docs——日志全文复核标准）；
   A6 口径注记在案。

## 六、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **PF2 修复形态（本方案最高权重）** | A=**apply 后自动 `save_prefab_to_disk`**（+record_saved_fingerprint 防 watcher 回声，机制现成；语义直白「Apply=写源文件」与 Unity 一致；代价=apply 变重 IO+与「apply 不写盘」既有测试反向重钉）。B=**脏标记+T08 保存链覆盖**（Play/导出前自动保存扩展到改过的 prefab；不即时 IO；代价=「重开一致」在用户手动存盘前仍不成立，只保 Play/导出两态——验收句「重开一致」字面不满足）。C=维持现状+warn（零改动，但验收句 FAIL 坐实） | **A**；「不写盘」测试（lifecycle:1230）按新语义重钉为「apply 后盘上=新基线」；批量 apply（Apply All）一次落盘不逐字段 |
| 2 | **PF4 apply 的 undo 语义** | A=apply 改 `allows_undo=false`+SELF_PUSHING/名单同步（文件级操作不可撤销，Unity 同语义；undo 栈不再有无效条目）。B=快照扩展装 PrefabAstCache（undo 真回滚缓存；捕获/安装面大改，波及 document_capture 五输入——重）。C=维持（no-op 条目无害论） | **A**；若决策 1 选 A，「apply 写盘+不可撤销」语义自洽 |
| 3 | **PF3（R3）是否本任务吸收** | A=吸收（变体×嵌套是矩阵 🔴 格，验收句点名列的环节；修向明确=按 ast_parent_of 重建）。B=只记不修+真机格标预期 FAIL（T03 先例；变体深层级属边缘场景，1 层变体是主路径） | **A 吸收**（变体在验收句点名列，🔴 不修则 T14 无法宣称变体环节验收通过；改动面收敛在 save_as_variant 单函数） |
| 4 | **「重开」矩阵口径** | A=保存→关 tab→重开（headless 可断言，主口径）+编辑器重启为真机加严格 L7。B=只认进程重启（headless 全部降级为间接证据）。C=关 tab 重开即算（最弱） | **A**；重启格用 L7 真机腿满足字面 |
| 5 | **真机 fixture 工程形态** | A=`jd new` 新建 `loop-mac/t14-prefab`+手写 prefab 夹具（干净、可弃置；游戏腿要冷编一次 ~分钟级）。B=复用 t12t1-game 暖工程加 prefab 文件（暖编译省时；代价=工程被 T12/T13 防线共用，prefab 件失败可能污染邻腿归因） | **A**（冷编成本一次性，scaffold_e2e 先例在案；磁盘高压家族注意清盘） |
| 6 | **嵌套×unpack 持久性探针格（E-6）处置** | A=探针只记录不裁定（存活/丢失如实入档，缺陷另立票）。B=若丢失直接并入 T2 修 | **A**（机制链显示可能经 IsA-delta 存活，探针前不下注） |

小定案（主控可否决）：缺陷编号 PF1-PF8；真机腿编号 L1-L8；fixture 工程
`/Users/zhanglinbo/workspace/loop-mac/t14-prefab`；夹具 prefab
`assets/prefabs/{rock,barrel,base}.bsn`；流程脚本 `loop/qa/t14-live.sh`；
报告目录 `loop/reports/t14*/`。

## 七、风险与回滚

| 风险 | 概率 | 缓解 |
|---|---|---|
| PF1 修复波及面超预期（reload 前置提取触及 watcher/driver/operator 三路） | 中 | 修向 A 是把 watcher 既有正确次序提为共用函数，行为面=「多一次稀疏 emit」；三路 callers 各一条红→绿锚；watcher 路已有 6 件测试护体 |
| PF2 改 apply 语义与既有测试/用户预期冲突（「不写盘」是被钉的现状） | 中 | 决策 1 显式裁定；重钉测试逐条列 T2-2；Unity「Apply 即写盘」为语义对齐依据 |
| A6 watcher flaky 干扰 headless 外部编辑格判读 | 高（已定案） | 该件按环境票口径隔离跑；真机 L4 腿为该环节正主；门前清磁盘（46GB 泄漏家族） |
| R4 使真机实体树断言不可用 | 确定（未修） | §四已绕行：world.query+jackdaw/entity 双通道；不用 scene_snapshot 树形态 |
| N13 PIE panic 扰乱 L5 腿 | 高（100% 复发） | 绕行+记数（错误处理器捕获、编辑器存活；腿内断言在 panic 后仍可重试读回） |
| Mac debug 无 RUST_BACKTRACE，真机 panic 只有消息签名 | 确定 | 全程不设；T11-T3 口径 |
| 门链与编辑器/游戏同窗互踩 | 中 | T12-T3 §九-7 纪律：门链单独跑 |
| 矩阵真机时长超单会话稳定期 | 中 | L1-L8 分两段（L1-L4 编辑器段/L5-L8 游戏段），每段独立探针开场（t12t3 形态） |
| 回滚 | — | T1 纯验证+测试锚（revert 零痕）；T2 各修换单点（PF1=共用前置提取、PF2=apply 尾部落盘、PF3=save_as_variant 单函数、PF4=声明改）均独立可 revert；全程零格式变更、零新系统——「不另起系统」硬约束由矩阵本身保障（每格都是既有 operator/既有机制的验证） |

## 八、与 T01-T13 已建设施的衔接

1. **T03（undo 加固）**：SELF_PUSHING/SNAPSHOT_BACKED 双清单是本矩阵 undo 维的声明面
   锚（record_counts.rs:494-546）；unpack 单写路径=Y4 修复面=E 格主锚；`history` BRP
   工具=undo 腿断言通道。
2. **T04（原子写/journal/恢复）**：prefab 落盘走 write_atomic（operators.rs:2026）——
   「保存中断不损坏」对 prefab 文件同样成立（矩阵重开维隐含格）；journal 的 prefab tab
   形态=L7 重启腿的恢复通道。
3. **T05（引用稳定）**：rename/move retarget prefab cache=T1-⑥回归腿；missing_source
   抱怨面（save_load.rs:84-106）=坏引用可见性抽查。
4. **T06（PIE 隔离）**：L5 的 Stop 还原链对 prefab tab 复跑（SHA 双腿）。
5. **T07（导出）**：L6 五点链=staged 原子交换+manifest 收编的 prefab 形态复用。
6. **T08（三腿保护）**：PF2 修向 B 的保存链覆盖即此机制扩展（若裁 B）。
7. **T12/T13（真机脚本族+flow）**：t12t3-live-chains.sh 形态直用；t13 的 menu/level
   文档流不涉 prefab——两任务零交集，但 L5/L6 的 game BRP 通道与 warn 扫描纪律同源。
8. **对 T15-T25 的奠基**：T23（模型局部材质覆盖持久化）=本任务覆盖机制的近亲（材质
   覆盖跨重开/导出）；T24（错误定位）=prefab 解析 warn 点名（runtime lib.rs:921-928）是
   现成模板；T20 示例游戏若用 prefab 组关，本任务的 apply 链缺陷修复是其前置。

## 九、耗时预估

| 段 | 预估 | 大头 |
|---|---|---|
| T1 | 1-1.5 天 | 补锚 6 件+探针复跑+fixture 工程+真机 L1-L8 两段 |
| T2 | 1-2 天 | PF1（次序前置提取三路对齐）+PF2（落盘语义+重钉）+PF3 若吸收（变体重建）+回归面 |
| T3 | 0.5-1 天 | 35 格终态+全量门+book+buglist/台账/roadmap 收尾 |
| 合计 | **2.5-4.5 天** | 视决策 3（PF3 吸收与否）浮动 |
