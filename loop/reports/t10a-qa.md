# T10a QA 验收报告：integration 9 红清理（只验不修）

> 验收对象：分支 `loop/t10a-intfix` 提交 **bb178d11**（基于 main 75a0d0be，9 文件 +139/−37）。
> 开局自检：分支/HEAD 一致（git status 仅既存噪音 .gitignore M、buglist.md 未跟踪；
> `git show --stat` 与报告 9 文件 +139/−37 逐一吻合）。
> QA 证据：主门 integration 与 fast 亲跑归档（`t10a_qa_integration_rerun.log` /
> `t10a_qa_fast_rerun.log`）、9 红 repro 形态逐件复核、SDK feature 名 registry 实物
> 抽查 3 个、#4 SELECTION_FALLBACK_OPS git 考古、#8 记档出处交叉核查（T3 归档
> baseline2/9tests/integration 三份日志比对）、程序归档 8 件全文复核、同型扫描独立复扫。

## 一、主门复跑——QA 亲跑全绿，与程序归档及 T3 既有形态一致

| 门 | QA 亲跑结果 | 对照 |
|---|---|---|
| **integration（主门）** | **5303/5303 passed (1 leaky), 2 skipped**，Summary 517.309s（归档 `t10a_qa_integration_rerun.log`） | 程序归档 `t10a_integration.log` 5303 passed (1 leaky), 2 skipped **完全一致**；1 leaky+2 skipped 对照 T3 归档 `t10t3_integration.log` Summary「5294 passed (1 flaky, 1 leaky), 9 failed, 2 skipped」——leaky/skipped 为 T3 记档既有形态，本次 9 failed→0 ✓ |
| fast | **2960/2960 passed (1 leaky), 2 skipped**，36.621s，EXIT=0（归档 `t10a_qa_fast_rerun.log`） | =程序归档=`t10t3_gate_fast.log` T3 基线（2960 数不变）；core_deps 段「the core crates depend on no third-party Bevy crate」过、git_deps 段「66 manifests … bevy main at c9c397ba…」过 ✓ |
| 全文复核纪律 | 两份 QA 亲跑日志 + 程序两份归档的 `^error`/`error[`/`FAILED`/`Diff after reformat` 匹配逐条目检：全部为测试名含 failed/is_skipped 字样的 PASS 行，**零真实失败、零格式 diff** | README 门禁证据标准（日志全文复核为准）满足 |

## 二、「不为绿而绿」审查（本任务核心风险）——9 红期望值变更逐项有据，零「改断言凑绿」

逐件核对结论（复跑失败形态以程序 `t10a_9reds_repro.log` 为准，QA 逐条检索复核：
9 tests run: 0 passed, 9 failed，每件 3 试 3 败）：

| # | 变更依据 QA 独立核实 | 裁定 |
|---|---|---|
| 1 | 路径 bug 定性成立：`E:\Cargo.toml` **亲证不存在**；仓库根 `Cargo.toml` 行 65 `[workspace]` **亲证在**（jackdaw 包 manifest 即 workspace root，`../../` 从 `E:\Project\rust\jackdaw` 越界到 `E:\` 恒 NotFound）。修复=读自身 manifest，测试主体断言（workspace avian3d 0.8 ↔ scaffold 产物一致）随之真执行（fixcheck 0.393s PASS） | 成立 |
| 2 | 与产品侧同源：`crates/jackdaw_project_build/build.rs:106-112` `emit_bevy_source` 本就是 `locked_rev().or_else(fork_pinned_rev)`——读 `[patch.crates-io].bevy.path` → `jackdaw-pinned-rev`。QA 逐环实物验证：主仓 Cargo.lock 的 bevy 条目**无 source 行**（path 源）→ helper 必走 fallback；manifest 行 430 patch path=绝对路径 `E:/Project/rust/bevy-fork-pinned`；`jackdaw-pinned-rev` 亲读 = `c9c397ba1a73e6cfffe957318e0359330b701865`（40-hex，与 T3 记档一致） | 成立 |
| 3 | 修复方向正确：测试失败指导原文即「Enable them from crates/jackdaw_sdk/Cargo.toml」，SDK 必须是任何工程图的超集——**补 SDK 而非砍工程图**是唯一正确方向。**feature 名 registry 实物抽查 3/3**：glam 0.33.12 有 `encase`/`encase-012`/`encase-013`、downcast-rs 2.0.2 有 `sync`、hashbrown 0.16.1 有 `serde`（`~/.cargo/registry/src/index.crates.io-*/` 实物 manifest）。Cargo.lock +57 行 QA 逐行复核：仅 sdk 7 新边 + encase 0.12.1/0.13.0 双版本消歧并存（glam 的 encase→encase-012 映射所致）+ hashbrown 补 serde/serde_core，**无意外版本跳变**；core_deps 段（no third-party Bevy crate）复跑仍过 | 成立 |
| 4 | **①产品侧 SELECTION_FALLBACK_OPS 补两项——三依据全坐实**：(a) operator 声明原文亲证（`integrations/physics/jackdaw_physics/src/components.rs:59-93`，doc = "Entity to make physical. Defaults to the selection."，实现 `.or(selection.primary())`）；(b) 误报机制亲证（`src/boot_ops.rs:460,533`：`takes_selection = SELECTION_FALLBACK_OPS.contains(...)`，`None if !takes_selection => NeedsAName`——不加则 clause 路径与 operator 自身 fallback 行为不一致）；(c) **git 考古**：e78c16fe（2026-10-14 上游「Move physics editor tooling into a module」）曾把旧 cfg-feature 形态的这两项**从清单删除**；T1（0972ee41）解封物理（modules.json 摘 unavailable+编辑器内置注册）使 operator 真实存在，但 `-S` 检索证实 T1 未动 boot_ops.rs 清单——「T1 漏加（解封时未恢复）」定性成立，补回不带 cfg（现为常驻 extension 非 cargo feature）正确 | 成立 |
| 5 | 语义正确：`tool.rs:59-66` 声明亲证——`modal = true`，description「Simulate the selected bodies: **drag** one to release it under gravity, Space **keeps where they settle**…」。模拟=拖拽驱动+settle，确无参数化形式；`physics.commit` 是工具内收尾非启动替代，`POINTER_ONLY → None` 行的理由准确。同文件 `the_pointer_only_table_names_operators_that_exist` 随测过（id 注册+理由非空） | 成立 |
| 6 | diff 审查：physics toggle 从 `matches!(refused, Cancelled)`（旧 unavailable 语义）改为 `Finished` + modules 含 physics + manifest `physics = true`——与 T3 已绿的 `physics_is_on_by_default` 同语义互证；navmesh/pinned/no-git 等不动断言保留 | 成立 |
| 7 | diff 审查：pending 期望 `["navmesh"]`→`["navmesh","physics"]`（BTreeMap id 序）；apply 后两模块均 true；「acme.dialogue 缺失扩展拒 toggle」语义保留（untouched 断言在） | 成立 |
| 8 | **②降级定性成立但记档出处有混淆（见 ⚪-1）**：QA 检索 T3 归档三份日志交叉核查——「gave up after 60s」超时形态**仅**出自程序的 `t10t3_main_baseline_9tests.log`（main 基线 1d0574be）；**QA 自己的 `t10t3_qa_main_baseline2.log`（同为 1d0574be 干净 worktree）里 #8 实为 5-6s 断言失败**（`new_project.rs:339` panic + scaffold 产物 `avian3d = "0.8"` 完整输出 + Scaffolded INFO 在场——打开链路正常）；T3 分支 `t10t3_integration.log` 亦为 2.6-5.7s 断言失败×3 试。三方日志一致支持「断言漂移（非时序/环境）」定性，T10a 反转为 `contains("avian3d")` + `physics=Some(true)` 有据（multiplayer Some(false)/navmesh features 断言保留）。**定性正确；但 T3 QA 报告表格 #8 形态列誊写了程序基线的超时形态未注明出处，T10a 报告又将该超时归因为「QA worktree 冷缓存」——与 QA baseline2 实际（未超时）矛盾，如实记档** | 定性成立（记档偏差见 ⚪-1） |
| 9 | 语义正确：旧断言全局 `ToolbarButton count==0` 被内置物理扩展自己的工具按钮（`register_toolbar_button::<PhysicsActivateOp>`，T1 起默认启用）打破。新口径按**本扩展的工具过滤**（按钮 `ButtonOperatorCall.id == BallastToolOp::ID`、overlay `label == "Ballast"`，沿同文件既有辅助口径），测试意图（禁用扩展→它的工具全消失）不变，内置工具不再被牵连；失活 `ToolbarButton` import 顺带移除（clippy 佐证） | 成立 |

**无一例「为绿而绿」**：6 件断言/清单对齐均有产品语义依据（operator 原文/T1 解封语义/T3 已绿互证）；#3 修复的是 SDK 集合本身（非改断言）；#1 修复的是测试自身 bug（主体断言因此**更严格**了——从 NotFound 假失败变真比对）；#9 收窄计数范围有「内置工具不该被牵连」的明确语义注释。

## 三、假绿激活附带项——机制与真执行证据链闭合

- **机制亲证**：`template_versions.rs:102-105` 测试体开头 `let Some(rev) = locked_bevy_rev() else { return; }`——修复前 helper 仅 lock 分支，fork 重定向后 lock 无 git rev 恒 None → **静默 return 假绿**；且该测试从未在任何红名单（因为它「绿」着）。
- **真执行证据链**：(a) helper 链路每环 QA 实物验证（见 #2，必然返回 Some(c9c397ba…)）；(b) **同 helper 的 #2 测试 PASS 本身即证明 Some**（若 None 会走 crates.io 锚定分支红于 "main"≠"0.21"）；(c) QA 亲跑该测试 PASS 0.288s（单测）——scaffold IO 量级而非纯跳过的 0.00s（对照：--exact 误过滤空跑 0.00s）；(d) 归档 `t10a_sdklayout_check.log` 全套 **20/20 PASS**（该件 1.465s，20 并发争用下的 scaffold 量级）。真执行后 scaffold+git/branch/rev/bevy_rev 断言全程在跑。

## 四、同型扫描复核——「无第 10 处」独立复扫成立

QA 以 `git grep -l -i physics -- tests/`（排除 fixtures/guards）独立复扫，命中 13 文件：

- 已处置 6：authoring_ops / remote_coverage / template_versions / launcher / new_project / extension_tooling（即 #1/#2/#4/#5/#6/#7/#8/#9 所在）；
- 程序裁定绿且语义不同的 3：`inspector/unloaded_component_card.rs`（「工程未开模块」提示文案）、`outliner/component_picker.rs`（avian 路径归 physics 分类）、`scenes/physics_round_trip.rs`（T3 已升级语义）——主门全绿佐证；
- #3 测试本体 1：`sdk_feature_superset.rs`（修复对象自身）；
- **程序未点名的 3 处 QA 逐一核验均无关**：`extern_redirect_ecosystem.rs`（`ecosystem_game::PhysicsBody` 示例自定义组件名）、`inspector/category_strip.rs`（inspector 分类条目表含 ("Physics", "Colliders and rigid bodies.") 条目——与 T1 语义一致的新世界形态，主门绿）、`scenes/main.rs`（`mod physics_round_trip;` 模块声明，指向已裁定文件）。

**「无第 10 处遗漏」结论成立**。

## 五、程序归档 8 件全文复核

| 归档 | QA 复核 |
|---|---|
| `t10a_fmt.log` | 0 字节（--check CLEAN 零输出，合理） |
| `t10a_clippy.log` | `^error` 匹配 0 行（17 个 warning 为宏 crate「generated N warning」编译行，程序逐条目检 + QA error 级抽验一致） |
| `t10a_fast.log` | 2960/2960 (1 leaky), 2 skipped；core_deps/git_deps 段过；error/FAILED 匹配全为测试名字样 PASS 行 |
| `t10a_integration.log` | 5303/5303 (1 leaky), 2 skipped；error/FAILED 匹配全为测试名字样 PASS 行（37 行逐条目检） |
| `t10a_9reds_repro.log` | 9 tests run: 0 passed, 9 failed；每件 3 试 3 败；#6 `launcher.rs:457 matches!(refused, Cancelled)`、#8 `new_project.rs:339`+avian3d="0.8"（5.9s）、#9 `extension_tooling.rs:300 left:1 right:0` 等形态逐条与报告一致 |
| `t10a_9reds_fixcheck.log` | 9/9 PASS，逐件耗时与报告「验证」列一致（0.126s/0.393s/0.783s/0.791s/1.720s/2.580s/1.960s/7.269s/6.986s） |
| `t10a_sdklayout_check.log` | 20/20 PASS |
| `t10a_gates_exitcodes.log` | `FMT=1 CLIPPY=0 FAST=1 INTEGRATION=0` → `RERUN FMT=0 FAST=0 INTEGRATION=0`——首跑 fmt 红止步、修格式后重跑覆盖归档，与报告叙述一致（符合 README「修完重跑覆盖归档」纪律） |

## 六、问题统计与偏差分级

- 🔴 严重：0
- 🟡 中等：0
- ⚪ 轻微：3——
  1. **#8 记档出处混淆（如实记档，不推翻修复）**：「60s 超时」形态仅出自程序 T3 时期的
     main 基线归档（`t10t3_main_baseline_9tests.log`，1d0574be）；QA 自己的 baseline2
     （同为 1d0574be 干净 worktree、冷缓存独立 target）里 #8 实为 5-6s 断言失败。
     T3 QA 报告表格 #8 形态列誊写了程序基线形态而未注明出处；T10a 报告又把该超时
     归因为「QA 复跑用独立 worktree 冷缓存」——与 QA baseline2 日志矛盾。**定性结论
     （断言漂移，无环境/时序残留）本身反而被 QA baseline2 直接支持，三方日志一致**。
     建议：后续报告引用失败形态注明日志出处，避免归因叙事漂移。
  2. #2 helper 的 fork fallback 是产品侧 build.rs 同源逻辑的简化复刻，缺产品侧的
     40-hex pin 校验与 rerun-if-changed（后者 build script 专属，前者测试语义可接受）。
  3. fast/integration 首跑因 fmt 格式红止步、`cargo fmt --all` 后重跑覆盖归档——
     exitcodes 归档如实记录两轮，符合纪律；格式重排仅涉本任务 2 文件（程序 git diff
     复核声明，QA 提交 stat 9 文件吻合佐证）。

## 七、结论

- 验收目标达成：main integration 门回绿（QA 亲跑 5303/5303 全过，1 leaky+2 skipped
  为 T3 记档既有形态），fast 2960/2960 基线数不变。
- 「不为绿而绿」审查 9/9 有据（含 #4 产品侧改动的三重依据与 git 考古、#3 registry
  实物抽查 3/3、#8 三方日志交叉核查）；假绿激活证据链闭合；同型扫描无第 10 处；
  程序归档 8 件全文复核无矛盾。零 🔴、零 🟡、3 ⚪（均记档类，无返工项）。

**VERDICT: PASS**

- 合入建议：主控 `--no-ff` 合入 bb178d11 至 main。
- 台账提示：T3 QA 遗留的「integration 9 红独立小任务」立项账随本任务完成闭环，
  可销账；⚪-1 的记档出处混淆仅涉报告质量，无需代码动作。
