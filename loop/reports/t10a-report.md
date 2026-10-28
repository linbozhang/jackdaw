# T10a 报告：integration 9 红清理（T1 断言漂移库存清账）

> 任务：QA 于 t10-t3-qa.md §一结论 b 裁定的插队小任务。分支 `loop/t10a-intfix`
> （基于 main 75a0d0be）。提交 **bb178d11** `Align integration tests with builtin
> physics and restore the SDK feature superset`（9 文件 +139/−37，显式 pathspec，
> 既存噪音 .gitignore/buglist.md 未触碰）。
> 开局自检：git status 仅既存噪音（.gitignore M、buglist.md 未跟踪），符合记档。

## 一、范围真理之源：本会话独立复跑

开工即以 `cargo nextest run --profile ci -E <9 测试名过滤>` 独立复跑（归档
`t10a_9reds_repro.log`，`--workspace --features dylib --tests` 与 xtask integration
同口径）：**9/9 复现，每件 3 试 3 败（非 flaky）**，逐件记录失败断言形态。
一处与 QA 记档形态不同（#8，见下）——QA 记档的超时形态出自 main 基线
（T3 patch 修复前、依赖缓存冷），当前 main（75a0d0be，含 T3 修复+缓存热）
上它 5.9s 即败于断言而非超时，根因分类随之下修。

## 二、9 红逐个处置表

| # | 测试（套件） | 复跑失败形态 | 根因分类 | 修法 | 验证 |
|---|---|---|---|---|---|
| 1 | `template_versions::the_physics_module_tracks_the_integrations_avian`（sdk_layout） | `tests/sdk_layout/template_versions.rs:127 workspace manifest: NotFound (os error 2)` | **真实缺陷（测试自身路径 bug）**：读 `CARGO_MANIFEST_DIR/../../Cargo.toml`，而 jackdaw 包就在仓库根（package 与 workspace 同 manifest），`../../` 越界到 `E:\Cargo.toml`——任何机器上恒 NotFound。T1 只跑 fast 门（不含此套件）故未暴露 | 改读 `CARGO_MANIFEST_DIR/Cargo.toml`，加注释言明「本包即 workspace root」 | 修复后 PASS（0.393s）；主体断言（workspace avian3d `version="0.8"` ↔ scaffold 产物一致）随之真实执行 |
| 2 | `template_versions::the_substituted_version_is_the_anchored_minor_or_main`（sdk_layout） | `:77 left: "main" right: "0.21"` | **测试环境形态（fork 本地路径敏感，断言未跟上）**：workspace bevy 被 `[patch]` 重定向到本地 fork 后 Cargo.lock 里 bevy 是 path 源、无 git rev，测试 helper `locked_bevy_rev()` 只有 lock 分支 → 误走「crates.io 锚定」分支。而产品侧 build.rs `emit_bevy_source` 本就有 fork fallback（读 fork 的 `jackdaw-pinned-rev`，实测 = c9c397ba，与 T3 记档一致）——测试 helper 缺同一分支 | helper 补 fork fallback：lock 无 git rev 时解析 workspace manifest `[patch.crates-io] bevy.path` → 读 `jackdaw-pinned-rev`（与 build.rs 同源逻辑），注释互指 | 修复后 PASS（0.126s）；`BEVY_VERSION=="main"` + `BEVY_REV==Some(c9c…)` 走 Some 分支成立 |
| 3 | `sdk_feature_superset::a_project_resolves_no_feature_the_sdk_lacks`（单测套件） | 7 项 divergent：approx v0.5.1[default] / crossbeam-utils v0.8.23[default] / disqualified v1.1.0[default] / downcast-rs v2.0.2[sync] / glam v0.33.12[encase,encase-012] / hashbrown v0.16.1[serde] / jackdaw_geometry[default] | **SDK feature 集合缺口（QA 点名的 approx 审视项，实际比 QA 报告多 6 项）**：物理默认开后 scaffold 工程图带 avian3d 全家，共享 crate 的 feature 多于 SDK 图——SDK 不再是任何工程图的超集，属真实缺口（测试文档自身的失败指导即「Enable them from crates/jackdaw_sdk/Cargo.toml」） | `crates/jackdaw_sdk/Cargo.toml` 按既有模式（bevy_math/curve/shape approx 行、rand 行先例）补 7 项直接依赖：`approx "0.5"`、`crossbeam-utils "0.8"`、`disqualified "1"`、`downcast-rs {version "2", features ["sync"]}`、`glam {0.33, ["encase"]}`、`hashbrown {0.16, ["serde"]}`、`jackdaw_geometry（path 依赖，default on）`，附语义注释（avian 开 default、parry 要 glam/encase、物理集成拉 geometry default）。feature 名均对照 registry 实物核实（glam 0.33.12 有 encase/encase-012；downcast-rs 2.0.2 有 sync）。Cargo.lock 随动 +57 行（仅 sdk 新边、glam 双版本 encase 0.12.1/0.13 对齐、hashbrown 补 serde），逐行核对无意外版本跳变 | 修复后 PASS（7.269s，输出 `compared N crates` 零 divergent）；core_deps 段复核不受影响（新增均非 Bevy-based 第三方） |
| 4 | `authoring_ops::every_entity_taking_operator_is_classified`（operators） | diff：found 比 ENTITY_PARAM_OPS 表多 `("physics.disable", ["entity"])`、`("physics.enable", ["entity"])` | **清单漂移**：T1 新增两个 Entity 参数 operator 未入分类表 | 表加两行（字母序插于 material.override 后），fallback=**true**——依据 operator 声明原文 `doc = "Entity to make physical. Defaults to the selection."` 且实现为 `.or(selection.primary())`；同时把两 id 补进产品侧 `src/boot_ops.rs::SELECTION_FALLBACK_OPS`（T1 漏加：不加时 clause 路径 resolver 会误报 NeedsAName 警告，与 operator 自身 selection fallback 行为不一致——一并对齐） | 修复后 PASS（0.783s）；SELECTION_FALLBACK_OPS 与表的双向一致性断言同测通过 |
| 5 | `remote_coverage::every_modal_operator_has_a_parametric_answer`（operators） | `undeclared: ["physics.activate"]` | **清单漂移**：T1 的 modal 物理工具未在 POINTER_ONLY 声明 remote 替代 | POINTER_ONLY 加 `physics.activate → None` 行，理由 "dragging a selected body to let it settle under gravity; a settle has no parametric form yet"（依据 tool.rs：模拟=拖拽驱动+settle，无参数化形式；physics.commit 是工具内收尾非启动替代） | 修复后 PASS（0.791s）；同文件 `the_pointer_only_table_names_operators_that_exist` 验证 id 已注册、理由非空 |
| 6 | `launcher::the_new_project_page_creates_the_chosen_template_pinned_to_this_editor`（stage） | `:457 matches!(refused, Cancelled)` 失败 | **断言漂移**：断言 physics toggle 被拒（旧 unavailable 语义）；物理默认开箱后 toggle 成功 | 改断言 `Finished` + NewProjectForm.modules 含 physics；manifest 断言补 `physics = true`（与 T3 已绿的 `physics_is_on_by_default` 同语义互证） | 修复后 PASS（1.720s） |
| 7 | `launcher::the_extensions_page_lists_optional_extensions_and_applies_module_changes`（stage） | `:591 left ["navmesh","physics"] right ["navmesh"]` | **断言漂移**：期望 pending 仅 navmesh（旧语义把 physics 当 incompatible module 拒 toggle） | 期望改 `["navmesh", "physics"]`（BTreeMap id 序，与实测一致）；apply 后断言 navmesh 与 physics 均 true（消息 "a missing extension cannot be toggled; both module changes wait"——acme.dialogue 缺失拒 toggle 的语义保留不动） | 修复后 PASS（2.580s） |
| 8 | `new_project::ticking_navmesh_gives_the_created_game_the_navmesh_feature`（stage） | 当前 main：`:339 assert!(!cargo.contains("avian3d"))` 失败（5.9s，测试完整输出含 scaffold 出的 Cargo.toml，其中 `avian3d = "0.8"` 在）；QA 记档的「60s 超时」是 main 基线（T3 patch 修复前）形态 | **断言漂移（非时序）**：根因调查结论——当前 main 上打开链路正常（本会话 3 次复跑均快速走到断言，非超时；打开流程 5s 内完成），红因纯为旧语义断言「navmesh-only 工程不含 avian3d」被「physics 默认开箱」推翻。QA 记档超时与当前差异归因：QA 复跑用独立 worktree 冷缓存（首次 resolve avian 全家超 60s），本机缓存已热后瓶颈消失 | `:339` 反转为 `contains("avian3d")`（消息注明 physics 默认开箱）；`modules["physics"]` 期望 `Some(false)→Some(true)`；`multiplayer Some(false)` 与 navmesh features 断言保留（复跑输出证实它们仍过） | 修复后 PASS（6.986s）；与同流程的 `physics_is_on_by_default`（绿）语义一致 |
| 9 | `extension_tooling::disabling_the_extension_takes_its_tooling_away`（viewport） | `:300 left: 1 right: 0`（全局 ToolbarButton count） | **断言漂移**：断言禁用扩展后全编辑器 ToolbarButton 数为 0，但内置物理扩展（T1 起默认启用）有自己的工具按钮（`register_toolbar_button::<PhysicsActivateOp>`），全局计数不再为 0 | 计数改为**按本扩展的工具过滤**：按钮按 `ButtonOperatorCall.id == BallastToolOp::ID`、overlay 按 `label == "Ballast"`（沿同文件既有辅助的口径），注释言明「内置物理扩展的工具不该被牵连」；顺带移除失活的 `ToolbarButton` import。测试意图（禁用扩展→它的工具全消失）不变，只是不再与内置工具冲突 | 修复后 PASS（1.960s） |

**根因分类汇总**：断言/清单漂移 6 件（#2/#4/#5/#6/#7/#9，其中 #2 兼测试环境形态、
#4 含产品侧 SELECTION_FALLBACK_OPS 一并对齐）；SDK feature 集合缺口 1 件（#3，
修复集合而非改断言——语义上 SDK 必须是任何工程图的超集）；测试自身路径 bug
1 件（#1）；QA 记档的「60s 超时根因调查」（#8）经复跑降级为断言漂移（打开链路
本会话实测正常），无环境/时序残留。

## 三、同型扫描

- `tests/` 全量扫 `physics` 引用（排除 guards/fixtures）：命中均在已处置文件
  或绿测试内——`inspector/unloaded_component_card.rs:136`（"Enable the Physics
  module" 提示文案，属「工程未开模块」面，语义不同且绿）、`outliner/
  component_picker.rs:212`（avian 路径归 physics 分类，绿）、`scenes/
  physics_round_trip.rs`（T3 已升级语义，绿）。**无第 10 处遗漏**。
- 附带发现并验证：#2 helper 修复激活了 `template_versions::
  a_game_on_bevy_main_records_the_editors_commit`——此前因 helper 返回 None
  **静默 return（假绿跳过）**，现真实执行（scaffold+git/branch/rev/bevy_rev
  断言）并通过。sdk_layout 全套 20/20 PASS（`t10a_sdklayout_check.log`）。
- ENTITY_PARAM_OPS/POINTER_ONLY/SELECTION_FALLBACK_OPS 三清单同测内自洽断言
  （表与产品清单一致性）随 #4/#5 修复同步通过。

## 四、门禁归档（日志全文复核为准，`loop/reports/t10a_*`）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **CLEAN**（0 行日志零 diff；首跑红 2 处→`cargo fmt --all` 仅重排本任务 2 文件→重跑覆盖归档绿） | `t10a_fmt.log` |
| Lint | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **CLEAN**（EXIT=0；日志 17 个 `^warning` 匹配逐条目检全为 bevy 宏 crate/build script 的既有「generated N warning」编译行，非 clippy lint） | `t10a_clippy.log` |
| fast | `cargo xtask fast` | **2960/2960 passed (1 leaky), 2 skipped**（=T3 基线 2960；core_deps 段「no third-party Bevy crate」过、git_deps 段「66 manifests … bevy main c9c397ba」过、clippy 段过；error/FAILED 匹配逐条目检全为测试名含字样的 PASS 行。首跑因 fmt 格式红止步 fmt 段，修格式后重跑覆盖归档） | `t10a_fast.log` |
| **integration（主门）** | `cargo xtask integration` | **5303/5303 passed (1 leaky), 2 skipped**（0 失败；1 leaky+2 skipped 为 T3 记档既有形态；fmt 修复前后各跑一次全绿，后者覆盖归档；error/FAILED 匹配逐条目检全为测试名含字样的 PASS 行） | `t10a_integration.log` |
| 过程证据 | 9 红复现 / 9 红修复验证 / sdk_layout 全套 / 门禁 exit codes | 9 红 3 试 3 败复现→修复后 9/9 PASS→sdk_layout 20/20→全门禁 EXIT=0 | `t10a_9reds_repro.log`、`t10a_9reds_fixcheck.log`、`t10a_sdklayout_check.log`、`t10a_gates_exitcodes.log` |

**验收目标达成**：main integration 门回绿（5303 全过，无环境性残留需记档）。

## 五、偏差与记档

- 🔴 严重：0
- 🟡 中等：0
- ⚪ 轻微：
  1. **#8 与 QA 记档形态差异**（超时→断言失败）：定性从「根因调查（时序）」
     降级为「断言漂移」。差异归因=QA 干净 worktree 冷缓存 vs 本机热缓存
     （首次 resolve avian 全家的耗时差）。已如实记档，非代码缺陷。
  2. **#3 divergent 规模**：QA 报告点名 1 项（approx），实测 7 项——物理
     默认开箱对 SDK 超集的侵蚀面比 QA 抽样大，本次一并补齐（测试自身的
     比对就是全量口径，无需再扫同型）。
  3. **#1 的路径 bug 属 T1 漏网**：T1 只跑 fast 门未跑 integration 的直接
     后果之一（与 9 红同因不同形）；修复即测试原意，无产品侧改动。
  4. `cargo fmt` 首跑 2 处格式红为本人新代码（长行断行/断言宏换行），非
     既存；`cargo fmt --all` 全仓仅重排本任务 2 文件（其余文件零触碰，
     git diff 复核）。
  5. sdk 新依赖使 workspace Cargo.lock +57 行（sdk 新边+glam 双版本 encase
     对齐+hashbrown serde），逐行核对无意外版本跳变；随提交一并入库。

## 六、提交与交接

- 提交 `bb178d11`（9 文件：tests×6、src/boot_ops.rs、crates/jackdaw_sdk/
  Cargo.toml、Cargo.lock），分支 `loop/t10a-intfix` 待主控 `--no-ff` 合入。
- 不写 loop/progress.md（主控专责）。QA 复验建议重点：#3 的 SDK 超集补齐
  （语义判断点：是否同意「补 SDK」而非「砍工程图」）、#4 的 fallback=true
  定性、#8 的降级定性。
