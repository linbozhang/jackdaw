# T05-T2 实施报告：缺失引用审计、定位与重绑闭环

- 分支 `loop/t05-audit`（自 main 573dc204 拉出），提交 **abf00a31** `Add the missing-reference audit with a locatable rebind list`
- 规格：`loop/plans/t05-reference-stability.md` §二 T2（裁决 ③/⑦/⑧ 已按裁定落实）
- 改动量：16 文件 +1960/−24（`git diff --cached --stat`）

## 一、改动逐项（对应方案改动面 1–7）

1. **新模块 `src/reference_audit.rs`**（1015 行）+ **operator `asset.audit`**：遍历 AssetIndex
   文档集（`walk_document_files`，tab 打开时以 tab 的未保存版本替代盘上文件——活动 scene tab
   直读 live AST、prefab tab 读 cache、非活动 scene tab 读 snapshot）逐引用判定，产出
   `AuditFinding { document, entity_name, component, field, reference, kind:
   Missing|Ambiguous|MachinePath }`，存 `AuditFindings` resource +
   `report_to_caller` 摘要（"N broken references in M documents (x missing, y
   ambiguous…)"）。`:`Base（base scene 继承）与 `IsA.source` 特判（asset_fields 的 ISA_TYPE
   公开为 pub(crate)）一并纳入扫描。**BRP 方法 `jackdaw/audit`**（remote/server.rs 表加行）
   返回 `{summary, count, findings[]}` 结构化 JSON——QA 断言通道。
2. **N5 加载期汇总 warn**：`open_read_scene` 尾部（非 prefab、live AST 就绪后）跑
   `warn_on_load` 对该文档 audit 子集，缺失者 `warn_caller` **一条汇总**（"scene 'x': N
   references name files the project does not hold (M missing) — run asset.audit"）；
   prefab 既有逐条投诉链未动。
3. **Missing References 清单 UI**（`src/inspector/missing_list.rs`，602 行，recovery_dialog
   同款 scrim/card 模式）：入口 = 文件卡新按钮 "Missing References…" + operator
   `asset.missing_list`；行 = `document · entity · component.field → reference (kind)` 按
   kind 着色；按钮 **Rebind**（feathers picker 列项目资产，选中经 `rewrite_tab_reference`
   写打开中 tab 的文档——活动 tab 写 live AST + 逐实体 resync、非活动写 snapshot、prefab
   写 cache，tab 置脏）、**Locate**（已开 tab 选中实体/未开先 scene.open）、**Show**（资源管
   理器开文档所在文件夹）、**Copy**（剪贴板）；未打开文档的 Rebind 回应 "open it first"
   （首版边界）。
4. **W12**：`names_one_machine` 收紧为单字母盘符 + `:` 即判（无需分隔符）；lib 用例
   `a_drive_relative_spelling_is_a_machine_path_without_a_separator` 断言
   `C:props/x.bsn` 被 absolute_asset_fields 捕获且 refusal 文本含该串（保存拒绝防线）。
5. **Y31 两阶段加载**（jackdaw_bsn/src/catalog.rs）：`load_bsn_assets` 改两遍——第一遍
   assets=None（内嵌引用静默 default、不产生假 warn）逐条 `reflect_asset.add` 站起并收集
   `#name`/`@name`→handle 暂存表；第二遍 `local:Some(表)` 重读值并 `insert` 回填同一
   handle——同文档 `#` 互引保真。`load_asset_value` 单条目路径改传当前 `BsnSceneAssets`
   兜底。lib 用例 `an_embedded_reference_survives_the_two_phase_load`（emitter 原文模板
   + `#inner` 重拼）断言 outer.inner == inner.handle。
6. **W7**：`apply_walk` gone 检测 `found` 收 HashSet 再 contains 差集（O(n·m)→O(n)）。
7. **N6 实测 + 最小 warn**：探针用例
   `an_entity_field_is_emitted_as_its_id_and_points_where_the_reader_spawned` 实证
   **Entity 字段以无名原始 id emit、不静默丢**，重读后指向由读侧 spawn 顺序决定；落
   `warn_on_dangling_entity_fields`（save_scene_inner 边界，reflect 遍历场景实体组件的
   Entity 字段查 world 存在性，dangling 计数一条 warn）+ 用例
   `a_dangling_entity_field_warns_once_at_the_save_boundary`（文档内指向无 warn /
   despawn 后一条计数 warn）。全链重映射按裁决 8 挂 open-challenges（方案原文）。

顺带（T1 遗留 ⚪）：rename 失败分支 `rename_failed` 触发 tab strip set_changed 使释放的
watch 重建；reference_rewrite.rs 测试 `std::slice::from_ref` 去 clone。

## 二、门禁（quick 四门亲跑 + 日志全文复核）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | 通过 | t05t2_fmt2.log |
| Lint | `cargo clippy --workspace -- -D warnings` | 通过 0 error | t05t2_clippy_ws4.log |
| 单测 | `cargo test --workspace --lib` | 全绿（含 reference_audit 6/6、asset_fields W12 新用例、migration 13/13、T1 回归） | t05t2_lib_full.log |
| 集成 | guards：`reference_audit::` **3/3** + `reference_rewrite::` **12/12**（T1 回归）+ 其余 **163/163**，合计 178 用例全覆盖 | 全绿 | t05t2_guards_final.log / t05t2_refrewrite_regression.log / t05t2_guards_skip.log |

日志复核：最终门禁日志零 error/FAILED；check/clippy1-3 与 y31diag/guards1-6/diag_roots 为
开发中间产物（含失败）如实保留；真机日志（live_launch/editor.log）保留为偏差证据。

## 三、真机终验链③（loop/qa/t05-missing-rebind.ps1）——**未完成，如实报告**

脚本已沉淀（launch/audit/list/rebind/save/reopen 六 phase，IsA.source→缺失 prefab 的
fixture，BRP 断言四要素、ui_tree 清单行、ui_click Rebind→picker 选现存、scene_bsn 新串、
scene.save 盘上新串、重开 audit 空）。**执行受阻于环境**：debug exe 重建后两种启动方式
（bat ShellExecute / Start-Process 直启+env 继承）编辑器均停在项目选择/预构建阶段——
`JACKDAW_OPEN_PROJECT` 的 `PendingAutoOpen { skip_build: false }` 会走项目构建前置
（launch.rs:94-99），fixture 最小工程无法过该前置，status.project 恒 null（editor log 停
在扩展加载；`project.open` BRP 返回 finished 但主线程不消费）。此前任务真机链用的是可
构建工程或不同路径，本轮时间预算内未攻克该前置。**headless 侧已覆盖**：audit 四要素/
摘要（lib + guards operator 链）、missing_list gather（guards）、加载期一条汇总 warn
（guards 真实 scene.open 链）、Y31 两阶段（lib）、W12（lib）、N6（lib）；BRP handler 与
UI 交互链（ui_tree/ui_click/scene_bsn）待真机环境复验。真机链与 Inspector broken 红显
回归列为 QA 复验重点。

## 四、Y31 吸收结论

**已吸收**（未回落）：两阶段加载落地，往返用例绿；与方案风险预案的差别——第一遍用
assets=None 而非 local=Some(空表)，避免第一遍产生「did not resolve」假 warn。

## 五、验收清单对照（方案 T2 节 6 项）

1. headless audit 四要素/Ambiguous/MachinePath：✓ lib `the_audit_names_every_break_with_its_four_locations`
   （Missing×2+Ambiguous+MachinePath，board 存在字段零 findings）+ guards operator 链
   `asset_audit_reports_and_fills_the_findings`；`C:props/x.bsn` 保存拒绝 ✓（W12 用例
   absolute_asset_fields/refusal；audit 的 MachinePath 判定与保存防线同一条 names_one_machine 逻辑）
2. headless 加载汇总一条 warn：✓ lib `a_loaded_scene_warns_once_about_its_missing_references`
   + guards `a_loaded_scene_leaves_one_summary_warning`（真实 scene.open 链）
3. headless Y31 往返：✓ lib（见上）
4. W7 数量级：✓ 实现差集（性能对比记录未单独跑——W7 是 ⚪ 顺手项，无硬闸）
5. **真机终验链③：未完成（见偏差）**——脚本沉淀待复验
6. Inspector broken 红显回归：未真机复验（既有行为未改动，audit 链不触碰 asset_row；列 QA 复验）

buglist：W12/Y31/W7 已打 `- [x]` + `> 已修复 abf00a31` 备注（本地文件，不入库）。

---

## 返工第 1 轮（QA FAIL 回流，提交 85b11056 `Fix the startup asset walk and audit path spelling`，5 文件 +392/−18）

**🔴 AssetIndex 启动链 — 根因修正（QA 定性经实证部分推翻）**：按 QA 要求先加诊断 log
（start_asset_walk / finish_asset_walk 打 walking / landed(documents,typed,referencing) /
applied(added,removed,reloaded) 三段 info）→ my-game 真机复现：**启动 walk 链 460ms 内完整走完**
（walking → landed(documents 1, typed 1, referencing 0) → applied），**"零 Indexed 日志"的真因是
`scan.added` 为空时旧代码不打日志**（观测盲，非链断）——my-game assets 当时无可索引的资产文件。
QA 的五个证据环全部被这一观测解释（picker 空另有真因，见下）。**同根波及 T1 联动的推断不成立**
（referrers 表随 walk 正常建立；guards `the_startup_walk_fills_the_index_without_a_manual_rescan`
在完整 editor app、零手动 rescan 下一次通过——该守卫测试已沉淀为该链的永久回归防线）。
**真阻塞者是 `open_rebind_picker` 的 items 来源**：旧码只列 `AssetIndex.iter()`（资产条目），
prefab/场景等文档不在其中——QA 场景的重组目标 props/keeper.bsn 是 prefab 文档，永远不在列表
→ "this project holds no assets to rebind to"。**修**：items 改为
`jackdaw_bsn::walk_document_files(assets)` 全文档集（catalog 除外，排序），与「引用命名的是文档」
的语义一致。启动链的诊断三段 info 保留（QA 要的观测面）。

**🟡-1 audit 对 live tab IsA 绝对拼写误判**：`open_tab_documents` 对每个 tab 文档先
`jackdaw_prefab::relativize_isa_sources_under(ast, assets)`（与保存侧同一函数）再入 audit——
红证（stash src 后 guards `an_open_tabs_isa_source_is_judged_by_its_relative_spelling` 失败：
缺失与健康的 IsA **双双**误报 MachinePath，0 passed / 1 failed，t05r1_red_isa.log）→ 修复后恰 1 条
Missing、健康 keeper 零 finding。**同一口径修复补进 rebind 写侧**：`rewrite_tab_reference` 三分支
（snapshot/prefab cache/live AST）统一先 fold 到相对拼写再匹配——真机链中发现 live AST 的 IsA
绝对拼写与 finding 相对串不等导致替换落空，一并治好。

**🟡-2 TupleStruct 盲区（MeshMaterial3d 形态）——已修**：`reference_rewrite` 的 scan/rewrite 两处
对 patch 级 `BsnPatch::TupleStruct` 与嵌套 `BsnValue::TupleStruct` 补 `tuple_held_type`（registry
的 `TypeInfo::TupleStruct.field_at(0)` 类型）使 newtype 持有的 Handle 引用按类型判定；
`reference_audit::collect_entity` 补同款分支（field 记作 "0"）。lib 探针用例
`a_reference_worn_through_a_newtype_component_is_rewritten_on_rename`（`Wearer(pub
Handle<StandardMaterial>)` 顶层 newtype patch，rename 后 rewrite_document 恰 1 处、新值落盘）钉死。

**真机链③ — 从 rebind 相全通（t05r1-closeout.ps1 六 phase）**：fixture 修正 pin（bevy="main" +
bevy_rev，QA 定案 ④）→ JACKDAW_OPEN_PROJECT 直开成功。六 PASS：① 启动日志出现 **"Indexed 1
asset files"**（QA 对照要求）；② `jackdaw/audit` 四要素 finding **kind=Missing**（非 MachinePath）；
③ `asset.missing_list` 清单行 + Rebind 按钮（ui_tree 实测）；④ 重绑经新 operator
**`asset.rebind`**（document/component/field/reference/to → rebind 写 tab 文档并置脏——MCP 优先
原则补的结构化通道：remote ui_click 的坐标换算在小控件上脱靶是 QA 已记录的工具层缺陷，本轮把
清单按钮加厚 16×8 并沉淀 operator 通道，按钮留给人）后 authored bsn 名 keeper；⑤ `scene.save`
盘上 `props/keeper.bsn`；⑥ 重开场景 audit 空（**CHAIN ALL PASS**，t05r1_live_chain10.log）。
**rebind 修复的第三层**：真机链实证 QA 场景被开为 **Prefab tab**（文档含 Prefab 组件）——rebind
改 prefab cache 后 live world 仍持旧 spawn（cache insert 不触发对 tab 自身文档的 respawn，
sync.rs 的 drawn-from 判定不含 tab 自己）→ 修：prefab 分支 rewritten 后 `activate_tab(world,
index)` 重激活（从 cache 重装 world，undo/视图随 tab 保留）。guards 层另补启动守卫与 ISA 口径
两用例（见上）。

**⚪**：`tests/guards/reference_audit.rs:160` unused mut 已清；QA 建议的 guards UnknownId 红证以
stash 红证形态完成（isa 用例，见 🟡-1——lib 用例在源文件内 stash 不可行，guards 文件独立可
stash，T1 模式成本最低）。all-targets clippy 的 3 个 unfulfilled `print_stdout` expect
（reflect_auto_register/component_shape_refresh/dylib_linkage_identity）为 QA 报告已确认的
既有历史随机暴露，本轮未触碰这些文件。

**门禁（归档 t05r1_*）**：fmt ✓（t05r1_fmt.log 零 Diff）；clippy --workspace -D warnings ✓
（t05r1_clippy1.log 0 error）；lib 全量 ✓ 全 0 failed（t05r1_lib_full.log，56 行 test result 复核）；
guards `reference_audit::` **5/5** + `reference_rewrite::` **12/12**（T1 回归）+ 其余（性能门单跑）
**162/162**，合计 179 用例全覆盖；session_journal 性能门单跑 1.06ms/2.24ms（t05r1_perf_solo.log，
并行全量下超 5ms 的既有现象与 T1 相同，skip+单跑分治覆盖归档）。日志全文复核：最终门禁日志的
命中行均为 PIE 环境噪音 WARN（内含 "error:" 字样的 cargo 输出），各 test result 全 ok。
