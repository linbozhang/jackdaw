# T10-T1 QA 验收报告：物理栈解锁与双侧接线（只验不修）

> 验收对象：分支 `loop/t10-physics`，提交 **0972ee41**（+前置 1f4eb774 ledger 行）。工作区核对：与提交态一致。
> 证据：QA 亲跑（`loop/t10t1_qa_fast.log`、物理双 crate 测试、单包 clippy 区分实验、新测试）、`loop/t10t1_*`（程序归档 19 件）、fork 现场（`E:\Project\rust\bevy-fork-pinned`）。

## 一、门禁——**物理测试全绿，但 fast 的 clippy 段 QA 亲跑红（退回项）**

- **物理双 crate 亲跑 44/44 全绿**（4+4+6+5+5+20+0s；editor 复活 **20/20** 含两个机制测试 `space_keeps_where_a_thrown_body_settled_as_one_undo_step`/`escape_puts_a_thrown_body_back`）——与归档 `t10t1_physics_tests2.log` 一致。✅
- **反转新测试 `physics_is_on_by_default_and_ships_with_the_game` 亲跑 ok**（stage 集成，3.08s）。✅
- **🔴 退回项——`cargo xtask fast` 的 clippy 段在当前 HEAD 必红**：QA 亲跑爆 `error: unused import: ExtensionAppExt as _` + `unused import: PhysicsExtension` + `could not compile jackdaw_physics (test "editor")`（`loop/t10t1_qa_fast.log`）。**QA 区分实验定音**：`cargo clippy -p jackdaw_physics --all-targets`（无 -D）报同两 warning——util.rs:13/14 两 import **无 cfg 且使用点缺失**（55 行只用 `enable_extension`/`EXTENSION_ID`，trait 与类型无人用）；`--features dylib` 系 root feature 与物理包无关（`-p jackdaw_physics --features dylib` 直接报 does not contain this feature）。**程序归档 `t10t1_gate_fast5.log`（0 error+2955/2955）不可复现**——按契约门禁证据标准（日志全文复核+可复现），以 QA 亲跑为准：**退回小修**（util.rs 13 行删 `ExtensionAppExt as _` 保留 `enable_extension`；14 行删 `PhysicsExtension` 保留 `EXTENSION_ID`——两行改动），修后重跑 fast **覆盖归档**。fast 的 nextest 段（2955）与 fmt 段本身无恙（归档+QA 亲跑 fmt 段过）。

## 二、「源分裂非漂移」归因裁定——成立

- **机制核实**（主 Cargo.toml 双 patch 段 diff）：`[patch.crates-io]` 五包（bevy/curve/math/reflect/shape）→fork 统一 registry 源（avian+glam_matrix_extras）；`[patch."https://github.com/bevyengine/bevy"]` 同五包→fork 统一 git 源（24 个 git 声明 manifest）——cargo patch 按源键各自重定向、fork=同一 pinned commit 仅版本串改写（0.20.0-dev→0.20.0 满足 ^0.20）→**归一后全图单 bevy package id**。注释完备（三源因何存在/如何维护/git_deps 防漂移）。✅
- **探针日志抽查印证**：probe1 28 error 行=`MassProperties3d does not implement GetTypeRegistration/Typed/PartialReflect`（**reflect 源分裂**症状）；probe2 67 行=`avian3d::Collider is not a Component`（**Component trait 互不识别**=git 树与 fork 树双 package id 的经典症状）；probe3 **0 error**——「27+69 错全为源分裂、统一后零漂移」的归因与日志形态精确对应。✅
- **rmcp 3.7→3.8**：diff 纯机械改名（`ServerInfo`→`ServerConfig` 三处，jackdaw_mcp），无行为面。✅

## 三、反转红绿真实性——成立

新测试亲跑绿；红证（反转后首跑 FAIL：dev checkout 下 `jackdaw_avian_integration` path 指向不存在目录）揪出两真缺口——修法在 diff 核实：`build_source.rs` +17 行（`CRATES_ELSEWHERE` 位置表）+`dev_checkout.rs` `DEV_PATH_DEPS` 增补；第三缺口（toml_edit 隐式下标把 [patch] 写坏）由既有测试 `the_runtime_edit_keeps_manifest_comments` 揪出+显式 `Item::Table` 构造修复。**旧测试语义承接**：`an_unavailable_module_is_offered_but_cannot_be_ticked` 被替换——modules.json/new_project.rs 中 `unavailable` 现**零匹配**（physics 是唯一实例且已解封，语义无对象自然消亡，modules.rs 两测更新为直过）——口径可接受，⚪ 记：未来若新增 unavailable 模块需恢复该守卫用例。

## 四、fork 脚本 review+现场——可重制

脚本（93 行）：`-Rev`（默认 c9c397ba）/`-OutDir` 参数+cargo git 缓存优先（`Find-CargoCheckout`）+blobless 网络 clone 兜底+版本串对称替换+两 commit（改写+`jackdaw-pinned-rev` 锚）；头部 doc 写明「pin 前进→带新 rev 重跑+cargo update+git_deps 守卫防漂移」——**新 rev 流程自洽**。现场核实：`E:\Project\rust\bevy-fork-pinned\jackdaw-pinned-rev`=c9c397ba…+fork 根 Cargo.toml `version = "0.20.0"`（改写态）——**fork 在位且与 pin 一致**。✅

## 五、守卫放宽边界审——无安全洞，两 ⚪ 一 🟡

- **core_deps**：`violations.retain`（users 含**非集成**使用者才算违规）+`user_is_integration` **硬编码两名**（jackdaw_avian_integration/jackdaw_physics）——豁免最小化（编辑器核心 crates/ 零豁免）✅；⚪ 注释称"named by the jackdaw convention"但实现是硬编码名单——新增集成 crate 需手改守卫（保守方向，可接受，注释措辞宜对齐）。
- **git_deps**：唯一放行 `name.starts_with("bevy") && spec 为 path`——非 bevy 名/非 path 形态仍违规，**防其它 patch 静默溜进成立** ✓；⚪ 边界：`bevy` 前缀宽于实际五包（`bevyfoo` 亦放行）——低风险（manifest diff 评审可见），可选收紧为精确五包名单。
- **两守卫读位迁移**（template_versions/modules.rs：聚合 manifest→主 Cargo.toml workspace.dependencies）——diff 核实一致。✅
- **CI physics job 删 75 行**：该 job 的存在理由（unavailable 门+聚合 manifest）随解封消失，删除合理；**但 CI 主 job 的 fork 依赖是真断裂**（patch path `E:/...` 在 CI 不存在→workspace resolve 即失败，非仅物理）——程序偏差④已如实记档。🟡 裁定：**归 fork 托管/CI 适配决策一并处置**（上游正解范畴），Loop 契约（本地开发流、quick 门本地跑）下不阻塞本任务，**CI 断裂需主控明确排期**。

## 六、真机挂账裁定——成立

机制层证据（editor 两「扔出→落定」测试+游戏侧独立构建 GAME_BUILD_OK+avian 引擎自身测试套）对 **T1 放行充分**：T1 验收面=「解封+双侧接线+零漂移编译」，物理行为断言（不穿地首证）本就是 T2 触发器矩阵的真机本职。T2 清单明确性：程序给出暖工程直接用+首证场景——**明确**；QA 核实 `H:\workspace_AI\t10-phys\phys-game` 在位（含预构建 target）✅。

## 七、偏差五条裁定

| # | 偏差 | 裁定 |
|---|---|---|
| ①rmcp 3.8 机械适配 | 接受（§二核实纯改名） |
| ②fork 机器本地路径约定 | **接受（单机开发口径）**——协作者克隆后先跑 fork 脚本（脚本入仓+book 记录）；上游正解（fork 托管/官方选 registry）在 T0 报告记档，open-challenges 补行未做（程序称"可后续"）——⚪ 随退回修一并补一行 |
| ③真机首证挂账 T2 | 接受（§六论证充分） |
| ④CI fork 依赖断裂 | 接受记档+🟡 主控排期（§五） |
| ⑤buglist 无钩 | 一致 ✓ |

## 八、结论与退回清单

达标：归因成立（源分裂症状逐形态印证+三源统一机制自洽）、红绿真实（新测试+两真缺口修法）、fork 可重制（脚本+现场）、守卫边界无安全洞、真机挂账口径成立、物理 44/44+新测试亲跑绿、偏差五条有裁定。

**退回（一轮小修）**：①util.rs 两处 unused import 删除（§一红证）+`cargo xtask fast` 重跑**覆盖归档**；②（顺带）open-challenges 补 fork 上游正解一行（偏差②遗留动作）。复验最小集：fast 全量+物理单包 clippy `-D warnings`——两项绿即放行。

VERDICT: FAIL（退回小修一轮——唯一硬伤为 §一 的 clippy 红证（两行 unused import，QA 双形态复现、程序归档不可复现）；其余全部验收面达标，修后按最小集复验不重跑全量）

---

# 退回小修复验（357b6f80，2026-10-27 20:2x，聚焦·只验不修）

> 复验对象：提交 **357b6f80** `Drop two unused imports and ledger the CI fork gap`（2 文件 +20/−16，0972ee41 之上）。按 §八 复验最小集执行。

## 一、diff 核对——恰两 import 删除+ledger 第五行

- `util.rs`：13 行 `{ExtensionAppExt as _, enable_extension}`→`enable_extension`（删 trait 保函数）、14 行 `{EXTENSION_ID, PhysicsExtension}`→`EXTENSION_ID`（删类型保常量）——**与 QA §一 修法建议逐字一致**，无多余改动。
- `open-challenges.md`：新增第五条 ledger（fork 机器本地路径+CI/协作者断裂+「fork 托管或上游解决源分裂才是修复归属」）——**与 QA 偏差②上游正解补行+🟡 CI 断裂入账两项遗留动作一致承接**；「Four→Five smaller ledgers」计数含 T09 手柄行在内自洽。

## 二、复验最小集——两项绿

1. **物理单包 `clippy -p jackdaw_physics --all-targets -- -D warnings` 亲跑 CLEAN**（`t10t1_qa_clippy_fix.log`：0 error/0 unused，Finished 21.74s）——红证形态之一消除。
2. **`cargo xtask fast` 亲跑绿**：`t10t1_qa_fast2.log` **0 error/0 unused import+Summary 2955 tests run: 2955 passed**（36.32s，2 skipped 既有）——红证形态之二消除；**新归档 `t10t1_gate_fast_fix.log` 全文复核同绿**（0 error/2955 passed；全文唯一 "unused" 匹配系测试名 `an_empty_plugin_body_has_no_unused_parameter` 的 PASS 行，非警告）——覆盖旧 fast5 归档的矛盾状态，门禁证据链修复。

## 三、结论

退回项闭环：红证双形态消除（QA 亲跑+归档复核）、diff 最小且与建议一致、两项遗留动作（上游正解 ledger+CI 断裂入账）一并落地。§二至§七 的其余验收面（归因/红绿/fork/守卫/挂账/偏差）维持原判全部达标。

VERDICT: PASS（T10-T1 退回小修复验通过，建议主控 --no-ff 合入 357b6f80（连同 0972ee41）；T2 前置：真机不穿地首证用 `H:\workspace_AI\t10-phys\phys-game` 暖工程；主控记事：CI fork 断裂排期（ledger 在档））
