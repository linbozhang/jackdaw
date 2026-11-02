# T23 任务 1 报告：建设轮（MO1 报告系统 + MO2/MO3 特判 + MO4 warn 拒）

> 分支 `loop/t23-material`（自 main 12c0f9f1）；方案 `loop/plans/t23-material-override.md`
> §任务拆解 T1；主控裁定 7 决策点全按建议（1-A/2-A+附带/3-A/4-B/5-A/6-A/7-A）。
> 红态先行纪律遵守：`loop/reports/t23t1_red.log` 修前归档（2026-11-02 08:06）。

## 一、四件逐项状态（红绿证据）

### MO1 覆盖键/值结构变化报告系统（决策 1-A）— ✅ 落地，headless 绿

- **落点**：`src/material_overrides.rs` —— `ReportedOverrides(HashSet<(Entity, String)>)` 资源
  + `report_broken_overrides` Update 系统（`plugin` 挂 `src/lib.rs`，`AppState::Editor` 门内；
  asset_failures::plugin 旁）。~180 行含测试，抄 T18 asset_failures 的 (键) 一次锁形态。
- **触发集**：与 runtime `find_models_to_dress` 同型——`Changed<两覆盖组件>`×2 +
  `RemovedComponents`×2 + `Added<GltfMaterialName>`（新部件沿祖先链找 holders）+
  `BsnProjectAssets`/`JackdawCatalog` is_changed（全 holders 重判）。**注释互指已双向落地**
  （editor 侧系统 doc + runtime 侧 `find_models_to_dress` doc，方案 §六风险一缓解）。
- **判定**：对每个 holder 算 ①stale 键=覆盖键−子树 `GltfMaterialName` 集（GLB 改名/删除）
  ②unresolved 值=`material_of_reference` 返 None（**与 dressing 同一解析口**，报告的
  「broken」恰等于「不会穿」）；stale 优先（键失效时值健康暂不问，键回归后再看值）。
- **一次锁**：`(Entity, identity)`，identity=`name:{key}` / `file:{path}` 双身份；判定时
  自清（不再失效的锁丢弃→回归即再报）、重触发不重报、undo 还原同 map 不假报。
- **双嘴**：`warn!("material override: …")`（M12 扫描前缀形态，文案含 holder 名/键/路径 +
  「wear their own material until … returns」语义）+ `status_bar::notify_warn`。
- **单测 5 件**（src 内假世界 `run_system_once`，asset_failures 测试形态）：
  stale 报一次+重复不报 / 恢复清锁+再失效再报 / sound 不假报（undo 面）/
  unresolved 报一次+文件到位自清 / 实例层 stale 同报。
- **红绿形态**：MO1 的 headless 红证与 MO2/MO3 静默红证同族（audit/rewrite 双盲的同一
  静默）；stale 键的真机红证（M8 修前零报告）留 T2 按「红态先归档」纪律跑。

### MO2 覆盖路径进审计（决策 2-A+附带）— ✅ 落地，红绿在案

- **改动**：`src/reference_audit.rs` Struct 臂加 `crate::material_overrides::takes_string_path()`
  特判——`OVERRIDE_TYPE_PATHS` 两覆盖类型（`MaterialOverrides`/`InstanceMaterialOverrides`
  的 `materials` 值）+**附带 `GltfSource.path`**（决策 2 附带项），形态=IsA.source 先例同款
  （一个类型路径+字段名比较，不动 `takes_asset_path` 本体）。`strings_under` 原生深入 Map
  值收字符串，Map 键（材质名）不收——零误收。
- **红证**（修前，`t23t1_red.log`）：`tests/guards/reference_audit.rs::
  an_override_path_that_names_no_file_is_a_missing_finding`——失效覆盖路径+失效模型路径
  **零 findings**（`findings: []`）。
- **绿证**：同测过——`MaterialOverrides.materials` 报 Missing（四元组齐：document/entity/
  component/field/reference）、`GltfSource.path` 报 Missing、held 材质零 finding。
- **免费获得**：`jackdaw/audit` 结构化 findings、`asset.audit`、`asset.missing_list`、
  `asset.rebind` 修复通路、`warn_on_load` 载入摘要——全部无需改动。

### MO3 改名跟随覆盖路径（决策 2-A，与 MO2 同根因同一改动面）— ✅ 落地，红绿在案

- **改动**：`src/reference_rewrite.rs` —— `scan_struct`/`rewrite_struct` 按字段算
  `force` 标志下传 `scan_value`/`rewrite_value`（参数 `is_source` 泛化为 `force`），Map/List
  臂继承标志、TupleStruct/嵌套 Struct 臂按自身类型重算。语义=「这两类类型的 materials
  值是引用」，`@name` 分支与 `IsA.source` 行为不动。
- **红证**（修前，`t23t1_red.log`）：`tests/guards/reference_rewrite.rs::
  renaming_a_material_rewrites_the_overrides_holding_it_and_nothing_else`——rename 后覆盖
  条目仍指旧路径（`("Rock", "materials/rust.material.bsn")` 原样）。
- **绿证**：模型层+实例层双条目跟随改写；三个不动对照在案（不指向移动文件的 Moss 条目、
  W10 的 plain string、`GltfSource.path` 模型源）；既有
  `renaming_a_referenced_file_rewrites_its_referrers_and_nothing_else` 复跑绿。
- **链路附注**：index 的 referrers 表走 `asset_files.rs` 文本扫描（任何引号路径都收），
  故 rename 传播链的缺口只在 AST 重写层——本特判即闭合，无需动 index。

### MO4 operator 扩大化改 warn 拒（决策 4-B）— ✅ 落地，红绿在案

- **改动**：`src/material_overrides.rs::material_override` ——「选中部件无名+name 空」分支
  从静默扩大到模型全部命名材质，改为 `warn_caller`（文案列可命名清单「name= one of the
  materials the model does name: …」）+ `Cancelled`；模型全无名时仍走原「no named
  materials」拒绝（文案更贴切）。显式 `name=` 与「选根=换全模型」两通路不动。
- **探针②**（决策 4 的输入）：修前 `overriding_an_unnamed_part_expands_to_every_named_material`
  钉死扩大化现状（红档中绿段=陷阱活体）；全测试面扫描确认无人依赖扩大化路径
  （stage 六件全部显式 `name=`，`material.apply`/材质行 Pick 是独立通路不受影响）。
- **绿证**：翻转后 `overriding_an_unnamed_part_is_refused_instead_of_expanding_to_the_model`
  ——Cancelled+组件不在+无名部件不穿+warn 含清单+显式 `name=Rock` 仍通。

## 二、附带项：GltfSource.path 入审计 — ✅ 已做

决策 2 附带项落地（`takes_string_path` 第三支）。模型文件失效（GLB 删除/移走）从静默
挂起（PendingModelRoots 等待链）变为 audit Missing 可发现。**既有审计测试面零适配**
（guards 246 全绿）——未触发「适配超半日则回落不附带」的判据。

## 三、验收标准对照（方案 §T1）

| 项 | 状态 |
|---|---|
| MO1 红绿 | headless 四态绿在库（5 单测）；真机 T2 终判（M8 红证修前归档纪律延续） |
| MO2/MO3 红绿 | 红证 `t23t1_red.log` 修前归档；绿测在库且过 |
| MO4 按裁定落地 | 决策 4-B warn 拒落地+断言在案 |
| 探针两件结论在案 | ②在案（MO4 探针→翻转）；**①（MO5 卡片直编）未执行→偏差 D1** |
| headless 全绿+quick 四门 | ✅（见 §四） |

## 四、门禁（quick 四门+受影响域，日志全文复核）

| 门 | 命令 | 结果 | 归档日志 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | EXIT=0，零 Diff | `t23t1_gates_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | EXIT=0，全文零 error/warning 行 | `t23t1_gates_clippy_ws.log` |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | EXIT=0，零行 | `t23t1_gates_clippy_phys.log` |
| libtests | `cargo nextest run --profile ci --workspace --lib` | **3052/3052**（基线 3047+5 新增，方案 §T1-7「3047→+n」吻合） | `t23t1_gates_libtests.log` |
| 受影响域 | `nextest --profile ci -p jackdaw --test guards` / `--test stage` | guards **246/246**（244+2 新增，503.8s）；stage **572/572**（571+1 新增，577.4s） | `t23t1_guards.log`/`t23t1_stage.log` |

> clippy_ws 与 fmt 在末次追加 runtime 注释后**重跑覆盖归档**（覆盖归档纪律）；物理双包与
> libtests 在注释前跑（注释为纯 comment，fmt 复核零 Diff、clippy_ws 重跑零行兜底）。
> RUST_BACKTRACE 全程未设。

## 五、偏差清单（分级如实）

- **D1（范围外未做）**：探针① MO5 卡片直编探针未执行。两因：①不在本指令四件范围；
  ②计划原文设想「root tests/ 纯函数」，但 `field_edit_commit` 是 `pub(crate)` 且依赖
  session/selection/AST 链——纯函数形态在集成测试侧不成立，须 in-src 测试或真机腿。
  建议：T2 用真机卡片腿（ui_tree+world.get_components）定案，或 T1 补票 in-src 测试。
- **D2（落点偏差）**：新增锚按受影响域测试族落位（guards×2、stage×1、lib in-src×5），
  非计划「全 root tests/ 档」。理由：家族 helper 在（`editor_test_app`、override fixture、
  operator call 助手）、门禁覆盖同族；MO1 假世界单测=asset_failures 先例形态（in-src）。
- **D3（实现内迭代）**：报告系统首版以 `&World` 为系统参数，与 `ResMut<ReportedOverrides>`
  构成 bevy B0007 参数冲突（guards 首跑即挂、全量零测损）——改为 `commands.queue` 形态
  （`find_models_to_dress` 同款，查询侧收触发集、闭包侧做可变判定）。
- **D4（测试设计修正）**：恢复清锁单测首版预期错——材质文件未 held 时，键回归后条目仍
  unresolved（身份换键 `file:path` 而非清零）。修测试（setup 补 `holds`）非修系统；
  「恢复」语义按「名+路径双愈」定义，与「stale 优先」规则一致。

## 六、给 QA 的注意事项

1. **预期 warn 形态**：MO1 双嘴均为 `material override: …` 前缀（状态栏+日志）；MO4 拒绝
   走 `warn_caller`（OperatorWarnings）。M12 扫描正则 `material.override|…` 已天然覆盖。
2. **MO4 行为变更**：真机脚本若走「选无名部件、name 空」旧路径，现得 `Cancelled`——T2 L3
   的 MO4 腿应断言拒绝+warn 清单，不再是红证扩大化（红证已归档于 red.log）。
3. **audit 断言面扩容**：`jackdaw/audit`/`asset.audit`/`asset.missing_list` 新增两类候选
   （`MaterialOverrides`/`InstanceMaterialOverrides` 的 materials 值 + `GltfSource.path`）；
   含失效覆盖/失效模型路径的旧场景打开时，`warn_on_load` 的 missing 计数会随之变化——
   真机 M9/L7 断言 expected 集要含这两族（component 字段值=`MaterialOverrides`/`GltfSource`）。
4. **A11 关联（rebind→活世界重穿）**：本任务单测已证「`BsnProjectAssets` 变更→失效锁
   自清」（引用表变更触发全 holders 重判）；M9/L7 的 rebind→重穿刻画仍要做，若粘性真踩
   归 A11 红证不修。
5. **报告系统只在编辑器进程跑**（`AppState::Editor`）——游戏进程日志零噪音（决策 1-A 核心
   动机）；游戏侧静默 give_back 属设计（M10 注记）。
6. **MO7 语义在案**：报告后条目不自动清（决策 3-A「只报告+手动清」），`material.override
   material=""` 既有通路即手清门。
7. **无 open 项**：D3/D4 均实现内收敛；红态→绿态全链可复跑（命令见 §四表）。

## 七、产物清单

- 分支 `loop/t23-material`：7 文件 +799/−23（`src/{lib,material_overrides,reference_audit,
  reference_rewrite}.rs`、`crates/jackdaw_runtime/src/material_overrides.rs`（仅注释互指）、
  `tests/guards/{reference_audit,reference_rewrite}.rs`、`tests/stage/material_overrides.rs`）
- 归档：`t23t1_red.log`、`t23t1_gates_fmt.log`、`t23t1_gates_clippy_ws.log`、
  `t23t1_gates_clippy_phys.log`、`t23t1_gates_libtests.log`、`t23t1_guards.log`、
  `t23t1_stage.log`
- 未动：buglist.md / 台账 / roadmap / fork / 场景格式 / 协议
