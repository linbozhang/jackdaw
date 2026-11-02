# T23 任务 1 QA 报告：建设轮验收（MO1 报告系统 + MO2/MO3 特判 + MO4 warn 拒）

> QA 独立复核（2026-11-02）。对象：分支 `loop/t23-material` @ **438ede6c**；程序报告
> `loop/reports/t23-t1-report.md`；红证 `t23t1_red.log`。方法=源码亲读 + 门禁/测试亲跑
> （后台+轮询，RUST_BACKTRACE 全程未设），QA 归档前缀 `t23t1_qa_*`。
> **裁决：PASS（附条件见 §六）——放行 T23-T2 真机矩阵轮。**

## 一、门禁亲跑（QA 全链复跑，非转录程序日志）

| 门 | 命令 | 结果 | QA 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | EXIT=0，零输出=零 Diff | `t23t1_qa_gates_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | EXIT=0，全文零 error/warning 行 | `t23t1_qa_gates_clippy_ws.log` |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | EXIT=0，零行 | `t23t1_qa_gates_clippy_phys.log` |
| libtests | `cargo test --workspace --lib` | **3052/3052**（与程序 nextest 口径同数；预期 3047+5 吻合） | `t23t1_qa_gates_libtests.log` |
| guards | `cargo nextest run --profile ci -p jackdaw --test guards` | **246/246**（244+2 新增） | `t23t1_qa_guards.log` |
| stage | `cargo nextest run --profile ci -p jackdaw --test stage` | **572/572**（571+1 新增） | `t23t1_qa_stage.log` |

- 程序侧归档日志（`t23t1_gates_*`/`t23t1_guards.log`/`t23t1_stage.log`）**全文复核**通过：
  数字与报告一致（3052/246/572），clippy 日志逐行扫描零 error/warning，fmt 零 Diff。
- 程序侧 libtests/guards/stage 用 nextest `--profile ci`，QA 用 `cargo test --workspace --lib`
  独立口径复跑得同一总数 3052——数字可信。
- 时间线核：红证 08:06 → 修复提交 09:23，红态先行纪律成立。

## 二、MO1 报告系统——源码级复核 + 五件单测亲跑（建设主件）

**源码亲读**（`src/material_overrides.rs`，+484 行主改动面）：

1. **一次锁形态**：`ReportedOverrides(HashSet<(Entity, String)>)` 资源 + 判定时
   `retain` 自清（不再失效的锁在 holder 被判时丢弃→失效回归会再报、undo 还原同 map
   不重报）。形态=T18 `asset_failures::WarnedFailures` 同款（HashSet 锁、`#[cfg(test)]
   len`、连「quiet second report looks exactly like a loud one」的注释句式都同源）。
2. **触发集与 runtime dressing 同型**：`Changed<两覆盖组件>`×2 + `RemovedComponents`×2 +
   `Added<GltfMaterialName>`（新部件沿祖先链找 holders）+ `BsnProjectAssets`/`JackdawCatalog`
   is_changed（全 holders 重判）——与 `crates/jackdaw_runtime/src/material_overrides.rs::
   find_models_to_dress` 逐参数对照**完全一致**。
3. **双向注释互指**：editor 侧 plugin doc（"The twin of the runtime's
   `find_models_to_dress`"）+ 系统 doc（"keep the two lists moving together"）；
   runtime 侧 `find_models_to_dress` doc（"when this list grows, grow that one with
   it"）——方案 §六风险一的缓解**双向落地**。
4. **判定语义**：stale 键=覆盖键−子树 `GltfMaterialName` 集，**stale 优先**（键失效时
   不问值，键回归再判值）；unresolved 值=`material_of_reference` 返 None——**与 dressing
   同一解析口**，报告的 broken 恰等于「不会穿」。身份双形 `name:{key}`/`file:{path}`
   与 D4 的「恢复=名+路径双愈」自洽。
5. **双嘴**：`warn!("material override: …")`（文案含 holder 名/键/路径 + wear-their-own
   语义）+ `status_bar::notify_warn`——源码两行相邻（:233-234）。
6. **仅编辑器进程**：plugin 挂 `src/lib.rs` EditorCorePlugin（asset_failures 旁）且系统带
   `run_if(in_state(AppState::Editor))` 双保险；游戏进程只链 runtime crate（其 dressing
   插件无任何报告面）——「游戏日志零噪音」结构性成立。

**五件假世界单测亲跑**（`cargo test -p jackdaw --lib material_overrides::tests -- --nocapture`）：

| 测试 | 断言面 | 结果 |
|---|---|---|
| a_stale_override_warns_once_and_stays_quiet_while_it_lasts | 报一次+重复判不重报（锁 1 不变+状态栏不活跃） | PASS |
| a_stale_override_that_recovers_clears_its_report_and_speaks_again | 名回归清锁→再失效再报（锁 1→0→1） | PASS |
| a_sound_override_never_warns_even_when_judged_again | sound 双判零锁零警告（undo 假报面） | PASS |
| an_override_whose_material_file_is_gone_warns_once_and_stops_when_it_arrives | unresolved 报一次+文件到位自清 | PASS |
| an_instance_stale_override_is_reported_too | 实例层 stale 同报 | PASS |

**日志嘴活体证据**（QA libtests 全量日志捕获）：恰好 **5 条**
`WARN jackdaw::material_overrides: material override: …`，与五测语义**精确对齐**——
stale 测 1 火（Cliff）、恢复测 2 火（初火+再失效火）、sound 测 **0** 火、unresolved 测
1 火、实例测 1 火。「报一次/不假报」在日志嘴上同样成立（`t23t1_qa_gates_libtests.log`）。

## 三、MO2/MO3/MO4 红绿亲核

**红证**（`t23t1_red.log`，修前归档，main=12c0f9f1 口径标注）：
- MO2 红：`an_override_path_that_names_no_file_is_a_missing_finding` FAILED——
  `findings: []`（失效覆盖路径+失效模型路径**零发现**，静默双盲实证）。
- MO3 红：`renaming_a_material_rewrites_the_overrides_holding_it_and_nothing_else`
  FAILED——覆盖条目仍指旧路径。
- MO4 探针（修前绿段=陷阱活体）：`overriding_an_unnamed_part_expands_to_every_named_material`
  ok——扩大化现状被钉死在档（该探针测随翻转被新拒绝测替代，红态只存 red.log，报告已如实注记）。

**绿测亲跑**（QA 独立运行，非转录）：

| 测试 | 结果 | 断言面 |
|---|---|---|
| guards reference_audit::an_override_path_that_names_no_file_is_a_missing_finding | PASS | `MaterialOverrides.materials` Missing 四元组齐（document/entity/component=MaterialOverrides/field=materials/reference）+ `GltfSource.path` Missing + held 材质零 finding |
| guards reference_rewrite::renaming_a_material_rewrites_the_overrides_holding_it_and_nothing_else | PASS | 模型层+实例层双条目跟随改写；三不动对照（Moss 条目/W10 plain string/`GltfSource.path` 模型源）+ Handle 字段对照 |
| guards reference_rewrite::renaming_a_referenced_file_rewrites_its_referrers_and_nothing_else（既有守卫） | PASS | 既有重写回归不破 |
| stage material_overrides::overriding_an_unnamed_part_is_refused_instead_of_expanding_to_the_model | PASS | Cancelled+组件不在+无名部件不穿+warn 含可命名清单（"wears an unnamed material"∧"Rock"）+显式 `name=Rock` 仍通 |
| stage material_overrides::an_override_naming_no_material_is_refused（邻测） | PASS | 「模型全无名仍走原拒绝」通路未被 MO4 分支破坏 |

源码亲读佐证：MO4 分支（`src/material_overrides.rs:469-496`）只收窄「选中部件无名+name
空」一条路，显式 `name=` 与选根换全模型两通路原样。

## 四、GltfSource.path 附带收录 + 特判收口核

- **`takes_string_path`**（`src/material_overrides.rs:27-33`，`pub(crate)`）：两覆盖类型
  `materials` 值 + `GltfSource.path` 三支，形态=IsA.source 先例同款（type_path+字段名
  比较）。**`takes_asset_path` 本体未动**（`src/typed_values.rs` 不在提交文件清单，
  Handle 字段拼写语义零波及）。
- **消费点**：audit Struct 臂（`reference_audit.rs` 在 `is_source` 特判旁并列一支）+
  rewrite `scan_struct`/`rewrite_struct` 按字段算 `force` 下传（Map/List 臂继承、
  TupleStruct 重置、嵌套 Struct 按自身 type_path 重算——`@name` 分支与既有行为不动）。
- **零误收**：`strings_under` 的 Map 臂只收值不收键（`reference_audit.rs:367-370`）——
  材质名（键）不进候选，报告声明属实。
- **既有审计测试面零适配**：guards 246 全绿（QA 亲跑）且 diff 中审计族只有新增文件内
  追加——「含失效路径旧场景的 warn_on_load 计数会变」未触发任何既有断言适配；该口径
  已在报告 §六-3 写明归 T2 真机 expected 集。
- **MO3 链路附注核**：`src/asset_files.rs` 确为引号值文本扫描（:108）——index referrers
  表天然收录覆盖路径，缺口只在 AST 重写层，本特判即闭合，报告附注准确。

## 五、warn 形态扫描归因（M12 预演）

- QA 自己的 guards/stage 全量日志：`material.override|holds no material|asset load
  failed|cannot-apply` 零命中（stage 的 7 处匹配全是 `material_overrides::*` 测试名
  PASS 行，非 warn 输出）——**零意外 warn**。
- libtests 日志的 5 处 `material override:` WARN 全部归于 MO1 新单测（§二逐条对齐），
  无一处溢出。

## 六、偏差裁定建议（3 条）与裁决

| 偏差 | 事实核 | 建议 |
|---|---|---|
| **D1** 探针①（MO5 卡片直编）未执行 | 技术论断属实：`field_edit_commit` 是 `pub(crate)`（`src/commands.rs:211`），tests/ 侧无引用——计划设想「root tests/ 纯函数」**形态不成立**；且探针①不在本指令四件范围 | **接受（范围外+形态不成立双因）**。MO5 维持 open；建议 T2 真机卡片腿（ui_tree+world.get_components）或 T3 文档轮补 in-src 小测定案，不再回 T1 |
| **D2** 新锚按家族落位（guards×2/stage×1/lib in-src×5）非「全 root tests/」 | guards/stage 锚本就在 root tests/ 家族文件；偏差仅 MO1 五件 in-src——asset_failures 先例同为 in-src，家族 helper（editor_test_app/override fixture/operator 助手）在场 | **接受**。落位与门禁覆盖同族，无覆盖缺口 |
| **D3/D4** 实现内收敛（B0007→commands.queue；恢复单测补 holds） | D3：源码即 `commands.queue` 形态（find_models_to_dress 同款），guards 首跑即挂、全量零测损（QA 复跑全绿佐证）；D4：「恢复=名+路径双愈」与 stale 优先规则自洽，修测试非修系统 | **接受**。均收敛、无遗留 |

### 裁决：**PASS**

依据：①门禁六门 QA 亲跑全绿且与程序归档一致；②MO1 源码级复核六面全过（一次锁/触发集
同型/双向互指/stale 优先/双嘴/仅编辑器）+五件单测亲跑+日志嘴 5 火精确对齐；③MO2/MO3/MO4
红证在档、绿测亲跑全过、既有守卫与邻测不破；④GltfSource.path 附带收录零适配、
takes_string_path 收口不碰本体；⑤三条偏差均有实证且不触验收标准。
**条件**：MO1 真机红绿（M8 修前零报告红证先行）与 MO2/MO3 真机腿（M5/M6/M9）按方案本就
归 T2 终判——本裁决只对建设轮 headless 面负责。

### 放行 T23-T2 建议（真机五链×属性）

放行。T2 必带四点注意（源自本次复核）：
1. **五链主干**：换装→存→重开→导出→重导入×属性（Standard/Layered/Water 三穿面），
   PX 像素 diff 用撞色（T19 口径）；
2. **M8 红态先行**：改 GLB 材质名的零报告红证须在真机上先行归档（headless 红证已在
   red.log，真机红证按纪律补）；
3. **MO4 腿改断言拒绝**：真机「选无名部件 name= 空」现得 `Cancelled`+warn 清单——断言
   拒绝而非扩大化（扩大化红证已归档）；
4. **audit expected 集扩容**：`jackdaw/audit`/`asset.missing_list`/`warn_on_load` 新增两族
   候选（component=`MaterialOverrides`/`GltfSource`），含失效路径旧场景的计数断言按此口径；
   M9/L7 的 rebind→活世界重穿刻画照做，粘性真踩归 A11 红证不修。

## 七、QA 产物清单

- 归档：`t23t1_qa_gates_{fmt,clippy_ws,clippy_phys,libtests,header}.log`、
  `t23t1_qa_guards.log`、`t23t1_qa_stage.log`、`t23t1_qa_mo1_tests.log`、
  `t23t1_qa_mo23_greens.log`、`t23t1_qa_mo4_green.log`
- 未动：产品代码 / buglist / 台账 / roadmap / fork；工作区仅新增本节归档与本报告。
