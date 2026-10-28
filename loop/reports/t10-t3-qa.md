# T10-T3 QA 终验报告：物理矩阵+文档+全量门，兼 T10 整体闭环判定（只验不修）

> 验收对象：分支 `loop/t10-final` 提交 **132ae3b7**（基于 main 1d0574be，7 文件 +251/−49）。
> 开局自检：分支/提交态一致；工作区仅剩既存噪音（.gitignore M、buglist.md 未跟踪）。
> QA 证据：main 基线 worktree 独立复跑（`t10t3_qa_main_baseline.log`+`t10t3_qa_main_baseline2.log`）、
> 真机格 5/3/6 复跑（`t10t3-game.ps1 -Drive` 亲跑）、格 8 verify 亲跑（`t10t3_qa_verify_rerun.log`
> 形态+console 抄录）、fast/clippy 亲跑（`t10t3_qa_fast.log`）、程序归档 10 件全文复核、
> 暖工程 scene.bsn/导出 dist 实物独立确证。

## 一、🔴 最高优先项：integration 9 红 main 既有声明——**独立核实成立（9/9 同红）**

**QA 复跑法**：`git worktree add` 于 **1d0574be 干净检出**（独立 target 全量冷编），按本轮
9 失败名单逐套件复跑（第一轮 cargo 首败套件中止后以 `--no-fail-fast` 补跑剩余 4 套件）：

| # | 失败测试（本轮 T3） | 套件 | main 复跑 | 形态（main 基线 panic 摘录） |
|---|---|---|---|---|
| 1 | template_versions::the_physics_module_tracks_the_integrations_avian | sdk_layout | **同红** | `workspace manifest: NotFound (os error 2)` |
| 2 | template_versions::the_substituted_version_is_the_anchored_minor_or_main | sdk_layout | **同红** | `left: "main" right: "0.21"`（channel 锚定） |
| 3 | a_project_resolves_no_feature_the_sdk_lacks | sdk_feature_superset | **同红** | `approx v0.5.1: ["default"]`（feature 集合比对） |
| 4 | authoring_ops::every_entity_taking_operator_is_classified | operators | **同红** | Entity 参数分类表漂移（physics.enable 等） |
| 5 | remote_coverage::every_modal_operator_has_a_parametric_answer | operators | **同红** | modal operator 缺 parametric twin（physics.activate） |
| 6 | launcher::the_new_project_page_creates_the_chosen_template_pinned_to_this_editor | stage | **同红** | `matches!(refused, Cancelled)` 断言失败（physics 可用后不再拒） |
| 7 | launcher::the_extensions_page_lists_optional_extensions_and_applies_module_changes | stage | **同红** | `left ["navmesh","physics"] right ["navmesh"]` |
| 8 | new_project::ticking_navmesh_gives_the_created_game_the_navmesh_feature | stage | **同红** | `gave up after 60s waiting for the new project to open`（超时） |
| 9 | extension_tooling::disabling_the_extension_takes_its_tooling_away | viewport | **同红** | `left: 1 right: 0`（禁用后工具数） |

**结论 a：程序声明成立**——9 红全部为 main（1d0574be=T1+T2 合入点）既有，**零本任务引入**。
9 红全部与 T1/T2 引入的 physics 语义变化相关（新 operator/模块默认启用/bevy channel 切换/
依赖树增长），断言面未跟上——「T1 反转族断言漂移库存」定性成立。

**QA 补充发现（净改善证据）**：程序 main 基线归档 14 红中另有 5 个（`physics_is_on_by_default_
and_ships_with_the_game`、`a_typed_name`、`while_a_create_runs`、`launcher::clicking`、
`a_preset_picked`）在 **T3 上已绿**——T3 的 scaffold patch 段修复实际治好了 main 上新工程流程族
4 红+1 flaky。**integration 门 14 红→9 红是净改善**，patch 修复有效性的又一侧面确证。

**结论 b：处置裁定=立项独立小任务（选项 b），不退回 T3**。理由：
- T3 代码无错（9 红 main 同在，退回无处可修）；
- 修复面**超出纯断言更新**：6 个为断言/清单对齐（channel 锚定语义、refused/toggle/工具数
  预期需按 physics 时代重设计、ENTITY_PARAM_OPS/POINTER_ONLY 清单），1 个需审视 SDK feature
  集合（avian 拉 `approx` 的 default feature），2 个需调查根因（template_versions 的 manifest
  NotFound——fork 本地路径敏感族；ticking_navmesh 60s 超时——非 patch 缺口所致，T3 上仍红）；
- main 的 integration 门红属破绿状态，**T10 闭环前置动作：主控立项该小任务并排期**（建议
  归入 T11 前的清账批，或独立 `loop/t-integration-9reds`）。

## 二、矩阵 12 格抽验（亲跑 4 格 + 降级格逐格裁定）

**通道纪律**：真机启动 `cmd start /B` 分离（QA 前科形态维持）；键盘 PostMessage
WM_KEYDOWN/UP 直投窗口。

| 格 | QA 动作 | 结果 |
|---|---|---|
| **格 5（必跑）** | `t10t3-game.ps1 -Gravity -9.81 -Drive` 亲跑全链 | **双 PASS**：GRID5A 反证 `midPickupPresent=True count=0`（落下的 cube 不收 x=0 拾取物——T2 旧行为反转，修复铁证）；GRID5B 真键盘 D 驱玩家 `PickupCount 1→3`、playerX -0.6→1.0000004（逐拍留档于 QA 会话 stdout） |
| **格 3** | 同上附带 | **PASS**：FallingCube y=0.29997307062149 三采样**差 0.0**（显示精度内完全静止，比程序报告的 ±3e-8 更强口径），半边长 0.3 停 stage 顶零穿透 |
| 格 6（随跑） | 同上附带 | **实质 PASS**（见 ⚪-1 观测假阳性裁定） |
| **格 8（缺陷② 抽验）** | verify 亲跑（见 §三） | **PASS**：修复编入后 add Sensor/CollisionLayers 双 `finished warn=[]` |
| 格 7 | 证据面复核+scene.bsn 实物 | 见降级裁定；`set memberships.0=2` 拒绝 warn 亲复现（⚪ LayerMask serde 记档形态核实） |

**5 个降级格逐格裁定**：

| 格 | 降级依据 | QA 裁定 |
|---|---|---|
| 1（cargo run 独立跑） | exe 窗口启动 0xc0000005 家族 | **降级成立**。非窗口运行成功（e2e schema 提取即运行 exe）；同模板暖工程窗口存活+行为全链（格 3/5 QA 亲跑）承担行为面。**但「QA 已立项调查」账实不符**——见 🟡-1 |
| 2（编辑器拖放） | 合成 pointer 五候选点无命中 | **降级成立，组合证据充分**：guards ④（真 avian：y=5 落地 120 帧收敛 y∈[0.24,0.26] 不穿地，`tests/guards/physics_triggers.rs` 四件 QA 实读确认覆盖前提红绿/桥链/互滤/不穿地）+物理双包编辑器测试族 20 件（含 Space 单 undo 两机制测试，51/51 亲跑复核） |
| 7（层互滤行为） | 编辑器内拖放不可达 | **降级成立**：guards ③（真 avian 互滤红绿对零接触 vs 全通对恰一接触+桥面 Enter 可见）承担行为面；文档面 bsn 往返由 QA 独立确证——暖工程 `scene.bsn`（多轮直写+编辑器 open/save 往返后的现存产物）含 Sensor/CollisionLayers(memberships/filters)/RigidBody Dynamic×2+Static/AvianCollider×4 全保真；bitmask 的 BRP set 不可用（LayerMask 无 serde）⚪ 维持，Inspector feathers 是 UI 替代 |
| 9（异目录启动） | 两轮死于 AdapterInfo 后 | **降级成立，导出实物 QA 全链确证**：`.jackdaw\dist\release\phys-game.exe` **138,203,136 字节**（与报告精确一致，avian 全家静态编入）；`export-manifest.json` 含 scene.bsn（17331B，与暖工程现存文件逐字节同长）+game-config.bsn+SHA256；异目录拷贝 `H:\workspace_AI\t10-phys\dist-run` exe 同大小+manifest 在（包自洽）；崩溃日志 `t10t3-grid9-dist-run.log` 止于 AdapterInfo 无窗口行（形态与记档一致）。行为一致性以「同 main.rs 同模板（游戏腿已端到端）+包完整性」承担——可接受 |
| 12（PIE 启动） | pie.play_current 300s 未 running | **降级成立**（0xc0000005 家族同族样本，见 🟡-1）；Stop 铁证前提腿以 T2 实测（PIE running→stop→SHA 不变）承担 |

## 三、两潜伏缺陷修复核实——**均属实且有效**

1. **scaffold patch 段补全**：diff 审查——`BEVY_FORK_CRATES`（5 crate）+`fork_crate_path` 抽取，
   `add_bevy_fork_patch`（存量工程）与 `module_patch_lines`（新工程）两处的 `[patch.git]` 段
   从仅 bevy 1 条补至 5 条（crates-io 段原本完整），与主 workspace 双段一致；钉死测试
   `a_physics_game_patches_every_fork_crate_on_both_sources` 以**真实 scaffold 产物文本**断言
   双段各 5 条（质量好）；e2e 增 `check_new_project` 产品链步+warnings 空断言；e2e 冷编
   1 passed in 247.44s 归档一致。源文件 UTF-8 完好（diff 中 em-dash 乱码仅 CMD 管道显示，
   Read 实读验证）。
2. **register_avian_types 一行修**：`PhysicsEditorPlugin::build` 首行调用+注释（动机/矩阵格
   7/8）。**QA 亲跑确证有效**：QA 复跑 verify 时二次踩中程序记档的「cargo 未级联重编
   jackdaw_physics」暂态（首验 exe 仍报 bsn apply `type not in registry`），touch 强制重编后
   亲跑：`add Sensor: finished warn=[]`+`add CL: finished warn=[]`——**修复编入后零警告成立**。
   ⚪-2：程序「修复后零警告」的验证 console 未归档（唯一 edv 归档是修复前红形态），QA 亲跑补链。

## 四、门禁复跑最小集——**全绿**

| 门 | QA 亲跑 | 程序归档复核 |
|---|---|---|
| clippy 物理双包 `-D warnings` | **CLEAN**（49.02s EXIT=0） | `t10t3_clippy_physics.log` 零匹配 ✓ |
| `cargo xtask fast` | **2960/2960 passed (1 leaky), 2 skipped, EXIT=0**；core_deps（no third-party）/git_deps（66 manifests bevy main c9c397ba）段过 | 同绿；error/FAIL 匹配全为测试名含字样的 PASS 行 ✓ |
| 归档 10 件 | — | fmt 空文件（--check CLEAN 合理）、clippy_ws 零匹配、physics_tests 51/51（5+4+6+5+5+6+0+20）、scenes_roundtrip 1/1、doctests 唯一 error=bind 首跑（`t10t3_doctests_bind_retry.log` 1 passed 对冲）、integration Summary 5303:9 失败与声明一致 ✓ |
| physics_round_trip 断言升级 | — | diff 审查：`!unresolved.any(avian3d)` 反转+doc 注明 UnresolvedTypes 仍是未知类型兜底——前提（T1 未注册）被修复消除，语义升级合理；测试名去 `without_the_module`（语义对象消亡，与 T1 QA 对 unavailable 口径一致） |

注：任务书称归档 11 件，实到 10 件 .log（清单核对无缺门——11 或计入了 doctests 的双件拆分）。

## 五、文档核对——**一致**

- `book/src/user-guide/physics.md` 五新节（Sensors and triggers/Collision layers/Two gravities,
  one number/The template's physics demo/The 30-second check）实读：玩家侧判定（"only the
  player's touch counts"）、互滤双向语义（"both directions must agree"）、静止体改层不重配对
  边界（T2 记档⑤如实入文档）、重力双源表+单向注入（apply_gravity_from_config）、30 秒清单
  三条与方案 §二 T3 逐条对应——与实现一致（T2 QA 已核的机制面+T3 修复面均吻合）。
- `open-challenges.md` 层命名账（Named collision layers：bitmask 可用/naming 是 gap，决策 4-B
  挂账）在 ✓。

## 六、T10 整体闭环判定

对照 roadmap 第 22 行验收句：「复用 Avian 集成，完善 Collider/RigidBody/Sensor/碰撞层/
调试显示；触发器连游戏行为。验收=不穿地/受力正确/拾取过关可做；Play 与导出一致。」

| 验收腿 | 证据 | QA 独立复核 |
|---|---|---|
| 复用 Avian（不另起栈） | avian3d 0.8+双 crate+patch 源统一 | T1 QA 归因裁定+fork 现场在位 ✓ |
| 不穿地 | 格 2（guards ④+编辑器测试族）+格 3（direct run 数值） | **格 3 QA 亲跑**（三采样差 0.0）✓ |
| 受力正确 | 格 4 组合证据（两轮 bsn 生效+静止 y 精确一致+fall csv）+通道限制记档（BRP 就绪晚于物理启动/游戏侧不识 avian Gravity——QA 复跑同形态复现 `Unknown resource type`） | 通道限制如实，组合证据链成立 ✓ |
| 拾取过关可做 | 格 5（双向区分）+格 6（clear log+组件）+模板 ~100 行教学段+teaches needle | **格 5 QA 亲跑双 PASS** ✓ |
| Play 与导出一致 | 格 9 导出链（exe 138MB+manifest+dist-run 拷贝）；异目录启动环境事件降级 | **导出实物 QA 确证**；降级链可接受 ✓ |
| 三任务链 | T1 PASS（含退回复验）→T2 PASS→T3 本报告 | 报告链完整 ✓ |

**结论：T10 可勾选**——验收句四腿各有独立证据且 QA 亲跑抽验通过；30 秒清单三条成立。
**两个闭环前置台账动作**（不涉 T10 代码返工，主控落账后勾选）：
1. 0xc0000005 启动调查立项落账（见 🟡-1）；
2. integration 9 红独立小任务立项排期（见 §一结论 b）。

## 七、问题统计与偏差分级

- 🔴 严重：0
- 🟡 中等：1——**0xc0000005 调查「已立项」账实不符**：T3 报告 §七-2 称「QA 已立项调查（§四②）」，
  但 open-challenges 无条目、loop/plans 无任务文件——T2 QA 的**建议**被引用为**已立项**。
  格 1/9/12 三处降级以此为据，账不落地则降级链悬空。处置：T10 勾选前补一行 open-challenges
  ledger（或并入 9 红小任务一起立项）。
- ⚪ 轻微：6——
  1. GRID6 复验的 `Find-At` 观测假阳性：R=True 命中的是玩家自身（playerX=1.00000035762787
     与命中坐标精确吻合——玩家恰停在第三拾取物原位），count=3+clear log 双独立证据在；
     脚本按坐标找实体不区分类型，下次先杀进程前验实体组件后缀；
  2. 程序 verify（修复后零警告）console 未归档，唯一 edv 归档为修复前红形态（QA 亲跑补链）；
  3. 真机脚本 GRID*_PASS console 标记无归档文件（editor 系脚本无 stdout 落盘）——本轮 QA 以
     日志时序+实物+亲跑复验补链，建议后续脚本加 console 落盘；
  4. `cargo build -p jackdaw` 对 integrations path 依赖改动不级联重编（QA 二次复现，touch 后
     才编入）——程序「工具链暂态」记档成立，量级上升为两次独立踩中，建议后续查 fingerprint
     失效条件；
  5. `t10t3-editorb2.ps1` 的 GRID9 轮询目录（`$Project\dist`）与实际导出目录
     （`.jackdaw\dist\release`）不符——45 分钟轮询必然空手（dist-path.txt 缺失的根因），
     不影响格 9 结论（导出实物 QA 直验）；
  6. 归档计数 11 vs 实到 10（见 §四注）。

## 八、结论与建议

达标：🔴 最高优先项独立核实成立（9/9 同红+净改善 14→9 侧面确证 patch 修复有效）；矩阵抽验
4 格亲跑全过（格 5 双 PASS/格 3 数值/格 8 零警告/格 6 实质过）；两潜伏缺陷修复属实且 QA 亲证
有效；门禁亲跑全绿（clippy 双包 CLEAN+fast 2960/2960）；文档五节+台账一致；降级格逐个裁定
成立（一处立项账缺口）。零 🔴、一 🟡（台账动作可闭环）。

**VERDICT: PASS**

- **合入建议**：主控 `--no-ff` 合入 132ae3b7 至 main。
- **T10 闭环建议**：可勾选；勾选前落两个台账动作——①open-challenges 补 0xc0000005 启动
  敏感性调查行（或独立立项）；②integration 9 红独立小任务立项（6 断言/清单对齐+1 SDK
  feature 集合审视（approx default）+2 根因调查（template_versions NotFound/ticking_navmesh
  60s 超时）），排期建议 T11 前。
- **环境处置**：QA worktree（jd-qa-t3main）已删；jackdaw/phys-game 进程清零；暖工程保留
  scene.bsn 受控物理场景+game-config gravity=-19.62 后态（程序 §八口径，下次跑前按需改回）；
  暖工程 exe 已被 QA 重编至含修复版本（lib.rs 00:12 修复在位）。
