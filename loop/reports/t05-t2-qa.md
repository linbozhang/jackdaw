# T05-T2 QA 验收报告：缺失引用审计、定位与重绑

- 角色：QA（只验不修）｜日期 2026-10-25/26｜分支 `loop/t05-audit`，提交 **abf00a31**（16 文件 +1960/−24，`git show --stat` 亲核一致）
- 输入：`loop/README.md`（2026-10-25 门禁证据标准）、`loop/plans/t05-reference-stability.md` §二 T2 + §三裁决、`loop/reports/t05-t2-report.md`（偏差 3 条：真机链未完成 / 红证 stash 不可行 / W7 对比未跑）
- QA 归档：`loop/reports/gate-*-t05t2qa.log`（亲跑 4 份）、`loop/reports/t05t2-rebind-qa/`（真机链 JSON/截图留档）、诊断脚本 `t05t2qa-*.ps1`（prep/live/rebind/closeout/diag1-9/winrect/fixture-prep）
- 真机环境：my-game（可构建工程，任务指定替代 fixture）+ 隔离 `JACKDAW_CONFIG_DIR` + 端口 15823；窗口物理 1920x1080（winrect 实测，UI 布局空间 4320x2430）

---

## 一、headless 门禁（程序归档全文复核 + QA 亲跑）

| 门 | 程序归档（QA 全文复核） | QA 亲跑 | 判定 |
|---|---|---|---|
| 格式 | t05t2_fmt2.log 0 行无 Diff | — | ✅ |
| Lint（契约版） | t05t2_clippy_ws4.log 12 行无 error | — | ✅ |
| 单测 lib | t05t2_lib_full.log 56 个 `test result:` 全 0 failed | `reference_audit` **6/6**（gate-lib-refaudit-t05t2qa.log EXIT 0） | ✅ |
| guards | guards_skip **163/0** + guards_final(refaudit) **3/0** + refrewrite_regression **12/0**（T1 回归）= 178 全覆盖 | `reference_audit` **3/3** + `reference_rewrite` **12/12**（EXIT 0） | ✅ |
| 加强门（非契约） | — | clippy --all-targets EXIT 101：`tests/guards/reference_audit.rs:160` unused mut（**本轮新增**，⚪）+ `tests/dylib_linkage_identity.rs:1` unfulfilled（既有历史，每轮随机暴露一个 tests 文件同类） | ⚪ |

migration 13/13 在 lib 归档内含幂等双用例；归档无独立 EXIT 行（同 R1 口径，以全文复核判定）。

## 二、真机终验链③（my-game）——**重绑闭环被产品缺陷阻塞，其余相位真机验证通过**

场景构造：scene.bsn 追加 `#Probe` + `Prefab` + `IsA { source: "props/victim.bsn" }`，盘上真实 `props/victim.bsn` 备份后删除、`props/keeper.bsn` 为现存重绑目标；跑前跑后 SHA256 校验（8222A13D…E011 一致，现场已还原）。

| 相位 | 结果 | 数字/留档 |
|---|---|---|
| launch | ✅ | JACKDAW_OPEN_PROJECT 直开、场景自动加载（editor log B0004 层级警告含 Probe；prefab watcher 对 victim 报 os error 2——缺失被感知） |
| **audit 四要素** | ✅ | `jackdaw/audit`：`{document:"scene.bsn", entity:"Probe", component:"IsA", field:"source", reference:"C:/…/props/victim.bsn", kind:"MachinePath"}`，count=1（phase1-audit.json）。**注意 kind=MachinePath 而非 Missing——见 review 🟡-1** |
| Inspector 选中回归 | ✅（降级口径） | outliner 行点击选中（状态栏 `Entity: Probe`）；Components 页显示 IsA 卡片；broken 红显为 tooltip 视觉态，截图留档。**IsA 无 asset_row 红行属架构现状（IsA 是文档级 patch 不进 ECS），非本任务回归** |
| **Missing 清单** | ✅ | `asset.missing_list` → 清单行（`Missing References` 标题 + victim 行 + Rebind/Locate/Show/Copy 四按钮），phase3-list-row.json |
| **Rebind picker** | **❌ 产品缺陷** | 点 Rebind 后 picker 不开；状态栏 warn **"this project holds no assets to rebind to"**（diag8 一手证据）——`open_rebind_picker` 的 `AssetIndex.iter()` 为空分支 |
| save / reopen | 未达（依赖 rebind） | — |

**阻塞归因的完整证据链（排除 QA 驱动手段）**：
1. **Close 对照**（closeout 脚本）：同构按钮（同 `spawn_text_button` + observe 模式）的 Close 点击**立即关闭清单**——合成点击到达 modal、observer 分发正常；
2. 三 scale `input.pointer`（2.25/1.5/1.0）+ `ui_click` 对 Rebind 容器全部无效，且 warn 文本明确走了 items 空分支（非点击落空）；
3. `jackdaw/assets` 返回 3 条（props/keeper.bsn、scene.bsn、scene.bsn.bak）——但该 handler **直扫文件系统**（server.rs:1312 IoTaskPool collect_assets），不证明 AssetIndex 非空；
4. **两份 editor 日志均零 "Indexed N asset files"**（apply_walk 仅 added 非空必打，asset_index.rs:908-909）——启动的异步 walk（OnEnter(Editor)→start_asset_walk→finish_asset_walk→apply_walk）在真机两次独立启动中**均未完成**，AssetIndex 资源保持空；
5. touch keeper 触发 watcher 也未产生 rescan（3s+idle 后仍零 Indexed）。

**🔴 严重（产品缺陷，回流主因）**：真机启动会话的 AssetIndex 填充链未完成 → T2 重绑闭环（picker 列空）不可用；**同根波及 T1 已合入功能**——`follow_a_move` 的 referrers 表、删除确认的影响面列表、文件卡 References 全部依赖该 index，在「启动后无文件变化」的真机会话同样退化为空集（headless 全绿是因为测试全部手动调 `rescan_asset_index` 填充，掩盖了该路径）。触发机制待产品侧诊断（候选：`finish_asset_walk` 的 `writes() != task.writes` 重启循环 asset_index.rs:900-905、walk task 未就绪/panic、OnEnter 时序）。快速复现器：my-game 静态启动 → `asset.missing_list` → 点 Rebind → 状态栏 "no assets"。

**过程性工具发现（⚪ 记录，非阻塞）**：`ui_click` 的坐标注入在「UI 布局空间 4320 vs 窗口物理 1920（约 2.25 倍）」的配置下换算偏差——at 输出为按钮中心 ÷1.5，物理命中需 ÷2.25；Close 对照证明该偏差在本链未构成阻塞（按钮够大），但小控件会脱靶。按 MCP 优先原则建议工具层修 ui_probe 的 scale 换算或提供窗口物理尺寸查询。

## 三、fixture 启动阻塞诊断（结论：②配置问题，非产品回归）

复现（t05t2-fixture-repro，程序脚本同形态工程：`Cargo.toml [package] t05t2-qa 无依赖` + `jackdaw.toml [jackdaw] bevy="0.20"`，隔离 config，端口 15831）：
- `status.project` 恒 null（复现程序报告的现象）；`dialog`/`modal` 均 null——**T04-T3 恢复对话框不在场，回归假设排除**（①否定）；
- **ui_tree 铁证**：屏上为 **Bevy 版本不匹配卡片**——"Choose how to open this project." / "Open a copy with jackdaw 0.21.0-dev - Bevy main" / "Convert this project" / "Look at scenes only"。代码链：`enter_project_with` → `compare_project` pins **blocking**（`bevy="0.20"` vs 运行中编辑器 Bevy main）→ `show_version_mismatch_card`（project_select.rs:455-458 一带），自动开门停在卡片等用户选择；
- 对照先例：T04 成功链用 **my-game**（`jackdaw.toml bevy = "main"` + `bevy_rev = "c9c397…"`，匹配不弹卡片）；T03 临时工程**无 jackdaw.toml**（形态不同，且为旧代码时点）。程序沉淀脚本 `loop/qa/t05-missing-rebind.ps1:55` 写 `bevy = "0.20"` 即病灶。

**裁定**：**②fixture 配置问题**（bevy pin 过时触发版本不匹配卡片），非 buildable target 缺失、非 T04 回归。处置：脚本 fixture 的 `jackdaw.toml` 改 `bevy = "main"`（+ `bevy_rev` 对齐当前编辑器）或启动后 ui_click "Look at scenes only"。程序报告对该卡的描述（"预构建前置/launch.rs:94-99"）定位不准，实际卡点在 project_select 的 pin 比对，早于任何构建。

## 四、代码 review（git show abf00a31）

### 🔴（真机实证，见 §二）
- **AssetIndex 启动填充未完成**（根因在既有启动 walk 基础设施，非 abf00a31 新码；T2 的 missing_list 是第一个暴露它的消费者）。

### 🟡 中等
- **🟡-1 audit 对打开 tab 的 IsA 引用报 kind 语义偏差**：live AST 经 `absolutize_isa_sources`（jackdaw_prefab/source.rs:130，加载规范化、保存时 relativize 反写——既有读写对）持有**绝对拼写**，audit 的 tab 替代逻辑（open_tab_documents 直读 live）把 `names_one_machine` 判成 **MachinePath 而非 Missing**（真机实证：盘上 `props/victim.bsn` → finding `C:/…/victim.bsn` MachinePath）。推论：**任何打开 tab 内健康的 IsA 引用同样会被报成 MachinePath**（重开场景后 keeper 的绝对拼写将进 findings——本链因 rebind 阻塞未及实证）。用户视角误导（"机器路径" vs 实际缺失/健康）。建议：audit 收集 candidate 时对 live 来源的 IsA/source 先 relativize（与保存侧同一函数），或 judge 前按 assets 根折叠。
- **🟡-2（连带 T1 同根）TupleStruct patch 的 Handle 引用三处同盲**：`collect_entity`（reference_audit.rs:242-301）只处理 Struct/`:`Base/`@`，**TupleStruct patch 不进 candidates**——与 T1 的 `spelled_references`/`rewrite_value` 同口径；`MeshMaterial3d<StandardMaterial>`（TupleStruct 包 Handle，bevy 场景最常见材质引用形态）若以非默认值 emit，audit 与 rename/move 重写**双双不可见**。实际 emit 形态未实证（现有场景默认值被省略），定 🟡 观察项：建议补一条「MeshMaterial3d 非默认材质引用」的探针用例钉死 emit 形态，若确为 TupleStruct(String) 则三处一起补 TupleStruct 分支（registry 的 TypeInfo::TupleStruct 可取 field 类型）。

### ⚪ 轻微
- `names_one_machine` 在 asset_fields 与 reference_audit **复制实现**（逻辑当前一致，一处改另一处易漂移；audit 侧注释已声明对应关系，建议共用）。
- Y31 第二遍在无 `AssetServer` 时静默跳过回填（editor 恒有 server，理论路径）；第一遍 assets=None 静默语义与方案偏差（避免假 warn）合理且报告如实。
- `tests/guards/reference_audit.rs:160` unused mut（all-targets 加强门暴露，契约门不含 tests target）；tests/ 下 dylib_linkage_identity 等一批 unfulfilled lint expectation 为既有历史。
- N5 的 `warn_on_load` 对 live AST deep_clone 后全量 audit 子集（每开一场景一次），大场景成本线性——与 referrers 内存态扫描同类，一次性行为可接受。

### ✅ 正向核实
- **audit 判定链**：MachinePath（绝对/`/`/`\\`/盘符`:`）→ `#`内嵌（文档名+BsnSceneAssets/BsnProjectAssets+stem 表四重判）→ `@`裸名（shared→Ambiguous）→ 其余 `project_holds_file`（Missing）；四要素（document/entity/component 短名/field）收集正确；`:`Base 与 `IsA.source` 特判入扫（ISA_TYPE 公开 pub(crate)）。
- **BRP `jackdaw/audit`**：`with_method_main` 挂表，返回 `{summary,count,findings[{document,entity,component,field,reference,kind}]}`，每次现算幂等——QA 真机断言通道实测可用。
- **W12**：`names_one_machine` 单字母盘符+`:` 即判（去掉分隔符要求）+ 用例（`C:props/x.bsn`/`z:whatever` 命中、`a1:`/`:props` 不命中）+ absolute_asset_fields/refusal 保存拒绝链。
- **W7**：`apply_walk` gone 检测 `found_set: HashSet` 差集（O(n·m)→O(n)），代码级确凿。
- **N5**：`open_read_scene` 尾部仅 Scene kind 一条汇总 warn（guards 真实 scene.open 链钉死），prefab 逐条投诉链未动。
- **N6**：探针实证 Entity 字段以原始 id emit（不静默丢）；`warn_on_dangling_entity_fields` 挂 `save_scene_inner` 边界 + 用例（文档内指向无 warn/despawn 后一条计数 warn）；全链重映射按裁决 8 挂账。
- **Y31 两阶段**：第一遍 no-assets 站起+`#`/`@` 双拼写暂存表、第二遍 `reflect_asset.insert` 回填同 handle；`load_asset_value` 单条目传 BsnSceneAssets 兜底；往返用例断言 `outer.inner == inner.handle` 质量合格。
- **missing_list UI**：未打开文档 Rebind 回 "open it first"（首版边界如实）、Locate/Show/Copy 齐备、重绑经 `rewrite_tab_reference` 三态（snapshot/prefab cache/live+逐实体 resync）写 tab 并置脏、"rebound to X; save the tab" 提示——headless gather 用例 + 真机清单行实测。
- **T1 两 ⚪ 兑现**：`rename_failed` → `scenes.set_changed()`（watch 重建，R1 建议的原样落实）；twin 单测 `std::slice::from_ref` 去 clone。

## 五、验收 6 项对照（方案 §二 T2）

| # | 方案验收项 | 证据 | 判定 |
|---|---|---|---|
| 1 | headless audit 四要素/Ambiguous/MachinePath + W12 保存拒绝 | lib `the_audit_names_every_break_with_its_four_locations` + guards operator 链 + W12 用例；**真机 audit 四要素亦验**（§二） | ✅（注意 🟡-1 的 kind 语义偏差） |
| 2 | headless 加载汇总一条 warn | lib + guards 双用例 | ✅ |
| 3 | headless Y31 往返 | lib（两阶段） | ✅ |
| 4 | W7 数量级（非硬闸） | 差集实现代码级确凿；**对比记录未跑——接受现状**（方案明言非硬闸，算法变化无歧义） | ✅（记录口径） |
| 5 | **真机终验链③** | audit/清单/选中三相真机过；**重绑闭环被 🔴 AssetIndex 启动为空阻塞**，save/reopen 未达 | ❌ |
| 6 | Inspector broken 红显回归 | IsA 无 asset_row 红行属架构现状（文档级 patch 不进 ECS，prefab 缺失走加载 warn 链——editor.log 实证）；Handle 材质红显未测（场景无 Handle 引用实体 + MeshMaterial3d 盲区 🟡-2） | 部分（记录口径） |

## 六、buglist 核对

W12（:338/:341）、Y31（:241/:245）、W7（:312/:315）均 `- [x]` + `> 已修复 abf00a31（T05-T2）` 备注含用例名与实现要点，与实际证据一致 ✅。

## 七、偏差 3 条裁定

1. **真机链未完成**：**成立且升级为 🔴 产品缺陷**（非环境阻塞）：程序归因"PendingAutoOpen 预构建前置"**不准**——fixture 卡点实为 bevy pin 版本不匹配卡片（§三），my-game 无此卡、真机链在 my-game 上推进到 rebind 才撞上 AssetIndex 启动为空（§二）。
2. **红证 stash 不可行**：**可接受**。方案全任务 QA 清单的红→绿要求明确列的是 N1/N3/Y8（皆 T1 项），T2 无规格强制红→绿项；lib 用例在源文件内 stash 确不可行。建议（⚪）：guards 侧 `asset.audit`/`asset.missing_list` 的 UnknownId 红证照 T1 模式成本极低，下轮顺手补。
3. **W7 对比未跑**：**接受现状**（§五 #4）。

## 八、结论与修复轮建议

- PASS 条件核对：headless 全绿 ✅；review 无新 🔴 ❌（AssetIndex 启动填充失败，真机实证）；真机链③跑通 ❌（重绑闭环产品侧阻塞）；fixture 阻塞有明确诊断结论 ✅（②配置问题，bevy pin 卡片，与 T04 无涉）。按任务预置条件「真机链在可构建工程上也跑不通属产品缺陷 → FAIL 回流」——**成立**。
- 修复轮建议（按优先级）：
  1. 🔴 AssetIndex 启动 walk 未完成：诊断 `finish_asset_walk` 的 writes 重启循环/task 未启动/panic（建议 OnEnter 后打一行诊断 log；用 §二 复现器验证）；修后真机链从 rebind 相位续跑（audit→list→rebind→save→reopen，脚本 `loop/reports/t05t2qa-closeout.ps1` 可复用）。
  2. 🟡-1 audit 对 live IsA 的 absolutize 拼写先 relativize 再 judge（消除 MachinePath 误报/健康引用误报）。
  3. 🟡-2 MeshMaterial3d（TupleStruct Handle）探针用例 → 三处（audit/spelled/rewrite）同补或文档化口径。
  4. fixture 脚本 bevy pin 修正（`"main"` + rev）或 ui_click "Look at scenes only"。
  5. ⚪：`tests/guards/reference_audit.rs:160` unused mut；ui_click 的 scale 换算（工具层）；audit 红证补齐。
- 残留进程：无（fixture 与 my-game 实例均已清理）；my-game 现场 SHA256 与测前一致。

VERDICT: FAIL

---

# 修复轮 1 重验（R1 QA，提交 85b11056，2026-10-26）

输入：程序返工自述 §返工第 1 轮 + 复现器 `loop/reports/t05r1-closeout.ps1`。QA 归档：`loop/reports/t05r1qa-chain.ps1`（独立加强链）、`gate-guards-refaudit-t05t2r1qa.log`（亲跑 5/5）、`gate-build-t05t2r1qa.log`、`t05r1-live/qa-*.json`。

## 一、根因反转裁定：**程序解释成立，上轮 🔴 定性修正**

QA 亲跑诊断（构建 85b11056 后独立 launch 修正 pin fixture），日志原文三段落档：
`asset index: walking … recursively` → `walk landed (documents 3, typed 3, referencing 1)` → `Indexed 1 asset files`——**walk 455ms 完整走完**（与程序 460ms 一致）；documents 3=材质+keeper+场景、referencing 1=场景引用 victim、"Indexed 1"=唯一**资产**条目 rust.material.bsn（文档不计入 added）。

上轮五环证据逐一重核（读 85b11056 diff：`apply_walk`/added 语义**未改**，旧码 added 空即零日志）：
| 环 | 上轮推断 | 重核结论 |
|---|---|---|
| 零 "Indexed" | walk 未完成 | **观测盲**：added 只计资产条目，my-game 当时零资产文件 → added 恒空 → 旧码静默 |
| warn "no assets" | AssetIndex 未填 | `iter()`=资产条目集（my-game 0 资产）空——实测不错，但 documents/referrers 随 walk 正常建立，「未填」推断错误 |
| touch 无日志 | watcher 哑 | 同观测盲（mtime 变化不进 added） |
| jackdaw/assets 直扫 | 上轮已自标不构成反证 | 中性（维持） |
| Close 对照 | 点击链通 | 中性（维持） |

**修正后的定性**：真根因=`open_rebind_picker` 旧 items 只列 `AssetIndex.iter()`（资产条目），prefab/场景**文档**不在其中——my-game（无资产文件）items 全空、程序 fixture（有资产）列表缺文档，统一由 `walk_document_files` 全文档集修复；上轮「AssetIndex 启动链未完成」为观测盲误判，「波及 T1 rename/move 联动」论断**撤回**（walk 一直正常，referrers 表随 walk 建立——本次 landed(referencing 1) + 零手动 rescan 守卫双实证）。观测盲正是上轮要求加诊断 log 才消除的——本轮三段 info 已保留为永久观测面。

## 二、真机链六点独立复跑（`t05r1qa-chain.ps1`，加强断言）：**ALL PASS**

①"Indexed 1 asset files" 在场（日志原文留档）；②audit 四要素逐项 + `reference="props/victim.bsn"` **相对拼写** + **kind=Missing**；③清单行 + Rebind 按钮（ui_tree）；④`asset.rebind` operator（document/component/field/reference/to）→ authored bsn 含 keeper 无 victim；⑤scene.save 盘上含 keeper 无 victim；⑥重开 audit **count=0 全量空**（加强断言：健康 keeper 的 IsA 未被误报——上轮 🟡-1 预言的误报路径真机堵死）。与程序 t05r1_live_chain10.log 六 PASS 一致。

## 三、守卫测试（亲跑 + review）：**有效**

`the_startup_walk_fills_the_index_without_a_manual_rescan` 亲跑绿（guards reference_audit **5/5**，EXIT 0）。断言挂 `AssetIndex.get(entries)` 且全程零手动 rescan——启动链（OnEnter→异步 walk→apply）任一环断则 entries 空、**必红**；以前测试手动 rescan 掩盖链断的路径自此有防线。⚪ 备注：30 帧 update 的余量对本地毫秒级 walk 足够，慢机理论 flaky 风险低。

## 四、新增面 review：无新 🔴

- **asset.rebind**（✅）：五参 operator 薄封装同按钮同 `rebind` 路径（驱动不再依赖 ui_click 坐标——MCP 优先原则落地）；`allows_undo=false` 与按钮路径一致（只置脏）；`entity_name: None` 在 `rewrite_ast_reference` 为全实体匹配 ✓。
- **IsA fold 口径**（✅）：audit 侧 `stashed_ast` 是三种 tab 形态统一入口（含活动 tab live deep_clone），fold 后判——修复完备；写侧 `rewrite_tab_reference` 三分支统一 `fold_sources_to_relative`。stash 红证 `t05r1_red_isa.log`：0 passed/1 failed、编译过、失败信息为缺失与**健康** IsA **双双 MachinePath**（左 2 右 1）——红证质量高（正含上轮预言的健康误报）。
- **prefab 分支 activate_tab 重激活**（✅）：既有切 tab 完整路径（take content/history/view_state → cache clone → 重装），与 `respawn_scene_from_ast` 同构；仅 `active == index` 时调用，重复实体/状态悬挂风险低。
- **tuple_held_type 三处 + 探针**（✅）：spelled_references/scan_value/rewrite_ast 对 patch 级与嵌套 TupleStruct 均按 `TypeInfo::TupleStruct.field_at(0)` 类型判定；lib 探针 `a_reference_worn_through_a_newtype_component_is_rewritten_on_rename`（Wearer newtype rename 恰 1 处）绿。⚪：audit 侧 `collect_entity` 的 TupleStruct 分支为内联同款（未复用 tuple_held_type，两处漂移风险）。
- **按钮加厚 16×8**（✅ 缓解）：ui_click 坐标换算本体留在 backlog（程序口径如实）。
- ⚪：live 分支 IsA **组件**更新在 folded 既非 chosen 又非 finding.reference 时静默不动（组件与 finding 不同步的边角，AST patch 已改、组件遗留旧值至下次 respawn——触发面极窄）。

## 五、门禁复核与三项核对

- 归档全文复核：fmt 0 行、clippy1 12 行无 error、lib_full 3511 行 56 组 result 全 0 failed、skip3 **162/0**（18 filtered=audit5+refw12+journal1）+ audit（QA 亲跑同 5/5）+ refw2 **12/12** + perf solo **1/0**——分治覆盖成立；skip2 的 1 failed 即 session_journal 并行超标（**T1 轮既有裁定：测试基建不拦**，单跑过）。**数字口径小误记录**：程序称"5+12+162=179"，实际用例总数 **180**（含 journal 门；红证"179 filtered out"+1 旁证），journal 有 solo 日志、覆盖无缺。
- 三项核对：fixture pin ✓（脚本 :48 `bevy="main"`+rev，QA launch `PROJECT OPEN` 实证）；unused mut ✓（:160 已清；all-targets 剩余 error 全为既有历史 unfulfilled expect——reflect_auto_register/component_shape_refresh 等，本轮未触碰）；红证 ✓（stash 形态，T1 模式）。
- 残留进程：无（cleanup 已杀）。

## 六、结论

上轮 FAIL 的唯一支柱（真机重绑闭环）已由 85b11056 修复并经 QA 独立六点复跑闭环；根因反转有定论（上轮定性如实修正，波及论断撤回）；守卫测试有效成为启动链永久防线；review 无新 🔴（⚪×3：audit tuple 内联重复、30 帧余量、IsA 组件边角，均备案）。

VERDICT: PASS
