# 功能 #1 Resource Inspector · 任务 3 验收 + 功能级终验 QA 报告

- QA：独立验收 Agent（第三方，逐条自证）· 2026-10-22
- 对象：`loop/resource-inspector` 分支提交 `4fa481ac`（任务 3：文档+会话态提示+全量门），及功能 #1 全程三提交（c461ba37 / 04d941ba / 4fa481ac）
- 需求口径：`loop/plans/feature-01-resource-inspector.md` §4 任务 3 验收清单 4 条 + §5「给 QA 的验收清单」全表
- 方法：CI 门全部独立重跑记退出码；任务 3 diff 逐行读；book 链接机器验证（Test-Path 全量）；盘点表逐行复算；不信任程序自述。
- 仓库状态核对：分支 = loop/resource-inspector，`git status` 干净，`git diff main..loop/resource-inspector` = 恰 6 文件（+147/-5），与程序报告改动清单一一对应；`loop/` 在 `.git/info/exclude`（不入库），故盘点表改动不在 git diff 内，口径自洽。

## 结论

**VERDICT: PASS（功能级）** — 任务 3 四条验收全部满足（第 1 条含 doctests known-issue 判定成立）；§5 确定性门 5✅ + 1 known-issue、headless 断言 5✅、文档项 3✅；视觉 3 项按主控裁定 ⚠️ 留用户终审（建议清单见文末）。无 🔴/🟡；⚪ 3 条不阻塞。

## 1. 任务 3 门（QA 独立重跑，退出码）

| 门 | 命令 | 退出码 | QA 实测 |
|---|---|---|---|
| fast | `cargo xtask fast` | **0** | 2716 passed / 2 skipped，40.8s（与程序报告 2716 一致） |
| integration | `cargo xtask integration` | **0** | 4831 passed / 3 skipped，333.9s（程序报告 4831 一致；t2 基线 4830 +1 = t3 新增 notice 测试） |
| docs | `cargo doc --locked --workspace --document-private-items --no-deps` | **0** | 1m05s；warning 仅 5 条既有 build script/linker 项（jackdaw_env/jackdaw_api_macros/jackdaw_project_build/jackdaw_package/lld），jackdaw lib rustdoc warning = 0——程序所修 2 处（`[`plugin`]`/`[`refresh_resource_panel`]` → code span）经 diff 核实且生效 |
| doctests | `cargo test --locked --workspace --doc --features bevy/dynamic_linking --no-fail-fast` | **101** | **known-issue 判定成立**，见下 |

### doctests known-issue 判定（按主控口径低成本核实）

- QA 实测 exit **101**，失败 3 个 target：`jackdaw_bind`、`jackdaw_feathers`、`jackdaw_node_graph` — **与程序报告失败 crate 集合完全一致**；
- 集合不含任何 resource/inspector 相关 crate；`Doc-tests jackdaw`（主 crate，本功能断言所在）ok（0 failed）；
- 本功能 diff 触碰文件（book/、main.ftl、resource_panel.rs、list_and_show.rs）与上述三 crate **零交集**；
- 失败模式复核：`Doc-tests jackdaw_bind` 段 merged doctests 编译+运行后直接 `error: doctest failed`，无失败测试名打印——与程序报告「输出被 merged doctest harness 吞掉」吻合。

**判定：既有环境问题（Windows + bevy_dylib + merged doctests），非本功能引入，非回归。记 known-issue 不阻塞。** 遗留：程序已建议非 Windows CI 复核，QA 附议。

## 2. 任务 3 验收清单（§4，逐条）

1. **CI 集四命令全绿 — ✅**（fast/integration/docs = 0；doctests = 101 经上述判定为既有环境问题，known-issue 不阻塞）。
2. **book 构建含新节且 SUMMARY 链接有效 — ✅**
   - `book/src/user-guide/resources.md` 存在（新文件 72 行）；
   - SUMMARY 链接：QA 用 PowerShell 对 SUMMARY.md **全部** `](....md)` 链接逐一 Test-Path —— 全部解析（含新增 `[Resources](user-guide/resources.md)`）；user-guide 9 链接 ↔ 目录 9 文件一一对应；
   - 本机无 mdbook（`where mdbook` 无）→ 静态核对为准；CI 有 `book.yaml`（push main 且 book/** 变更触发 `mdbook build book`），分支合入后链接有效性由 CI 兜底。
3. **盘点表三行改 ✅ 且证据列指向本功能提交 — ✅（含 1 处 ⚪ 统计偏差，见 §4 发现）**
   - 三行：`roadmap-gap-analysis.md` 行 38「资源可检查 ✅」（证据 c461ba37 + f4a72b5d + 4fa481ac）、行 47「增删资源 ✅」（04d941ba + e413f119）、行 48「改组件/资源值 ✅」（组件既有 + 资源 04d941ba，文档见 4fa481ac）——证据列合计覆盖 c461ba37 / 04d941ba / 4fa481ac 全部三个提交；
   - Stage 1 标题「11 ✅ / 1 🟡」、Stage 2 标题「7 ✅」已同步；
   - 统计行写「共 76 项：✅45/🟡15/❌16」（45+15+16=76 算术自洽）。**QA 逐行实数 = 75 项：✅44 / 🟡15 / ❌16**（Stage 0=5✅；Stage 1=11✅+1🟡；Stage 2=**6 行全 ✅**（标题写 7）；Stage 3=5✅4🟡1❌；Stage 4=8✅1🟡2❌；Stage 5=3✅1🟡；Stage 6=2✅1🟡1❌；未分类=4✅7🟡12❌）。矛盾唯一来源 = Stage 2 标题「7 ✅」vs 表 6 行；统计行按 Stage 标题加总得多 1。🟡15/❌16 逐行吻合，本功能三行改动本身正确 → ⚪ 轻微，不阻塞（修法：Stage 2 标题改 6 ✅、统计行改 75 项 44/15/16）。
4. **手册文案与实际 UI 文案一致 — ✅**
   - ftl：`resources-session-only = Resource changes apply to this editor session only and are not saved with the scene.`
   - book `resources.md` 黑体句与 ftl 文案**逐字一致**；语义（不落盘、会话态、重开即失）与 §D1 裁定一致；
   - headless 断言**真的断言了**：`tests/resource_panel/list_and_show.rs::the_panel_carries_its_session_only_notice`（:117-131）query `With<ResourceSessionNotice>` 的 `Text` == 完整英文文案（非键名），integration 实跑 PASS（QA 日志 17/17）；
   - 面板代码：`ResourceSessionNotice` + `LocalizedText::new("resources-session-only")` 置于 children 首位（搜索行之上），与程序报告「常驻提示行」一致；
   - resources.md 引擎 allowlist 描述（GlobalAmbientLight/ClearColor/GizmoConfigStore/Time\<Virtual\>/Time\<Fixed\>/Gravity-条件）与 `ENGINE_RESOURCE_ALLOWLIST` const 6 条**逐一对应**。

### custom-components.md「Custom resources」段 — ✅

含 `#[derive(Resource, Reflect, Default)] #[reflect(Resource, Default)]` 最小例（GameState{score:u32}）、is_game_type 自动进面板机制、与组件的会话态差异、schema-only 限制、相对链接 `../user-guide/resources.md`（目标存在，已验证）。

## 3. 功能级终验（§5 全表）

### 确定性门（QA 本轮全部独立重跑）

| 项 | 结果 | 证据 |
|---|---|---|
| `cargo fmt --all -- --check` | ✅ | exit 0 |
| `cargo clippy --workspace -- -D warnings` | ✅ | exit 0（CI 档 `--all-targets --features dylib` 由 fast 内含，fast=0） |
| `cargo xtask fast` | ✅ | exit 0，2716 passed / 2 skipped |
| `cargo xtask integration` | ✅ | exit 0，4831 passed / 3 skipped；`tests/resource_panel/` 5 测试文件 17 test **全 PASS、0 FAIL**（QA 逐条枚举核对） |
| `cargo doc --locked --workspace --document-private-items --no-deps` | ✅ | exit 0，jackdaw lib 零 rustdoc warning |
| `cargo test --locked --workspace --doc --features bevy/dynamic_linking` | ⚠️ known-issue | exit 101；失败集合 {jackdaw_bind, jackdaw_feathers, jackdaw_node_graph} 与程序一致、与本功能零交集 → 既有环境问题非回归（§1）；建议非 Windows CI 复核 |

### headless 行为断言（以三任务 QA 验收 + 本轮 integration 重跑为准）

| 项 | 结果 | 证据 |
|---|---|---|
| 白名单/游戏类型/deny 四类 case（visibility） | ✅ | 5 test PASS（deny>allow>game、game 零配置、allow 补入、默认 deny 8 路径、枚举分组 Game 前） |
| 列出→显示（行与字段名）（list_and_show） | ✅ | 4 test PASS（行覆盖/deny 压制/选中卡字段/空态文案/**会话态提示**） |
| 改值→undo→redo + 无空文档条目（edit_undo） | ✅ | 4 test PASS（round-trip 栈恰+1、no-op 零入栈、同组件实体误写守卫、卡片显示已提交值） |
| 增→删→undo→redo（insert_remove） | ✅ | 3 test PASS（缓存命中/幻影守卫/原值恢复/不可构造 no-op） |
| PIE 不泄漏（no_pie_leak） | ✅ | 1 test PASS（Live 模式 + 敌意投影布线下 LiveEditLog 为空） |

### 视觉项（人工）— ⚠️ 按主控裁定留用户终审

| 项 | 状态 | 备注 |
|---|---|---|
| 右栏 Resources tab：分组（Game 在前）、搜索过滤、卡片展开/折叠与 Components 观感一致 | ⚠️ 留用户终审 | headless 已断言结构与分组顺序；观感需人眼 |
| 数值拖拽（scrub）、颜色选择器、枚举下拉可用且一次拖拽一条 undo | ⚠️ 留用户终审 | 控件复用 reflect_fields 既有链路且 6 出口分流经测试；手感需手测 |
| 「会话态」提示文案可见 | ⚠️ 留用户终审（接近 ✅） | 存在性+文案已由 headless 断言锁定；仅剩视觉呈现（灰字小号、置顶）需人眼 |

### 文档项

| 项 | 结果 |
|---|---|
| book「Resources」节存在并解释范围与不落盘语义 | ✅（72 行：位置/列出/查看编辑/增删/三通道可见性/会话态/Limits 含 schema-only 与 PIE 边界） |
| custom-components.md 有 Resource 段（derive 即用） | ✅ |
| roadmap-gap-analysis.md 三行 ✅ | ✅（统计偏差 ⚪ 见 §2.3） |

## 4. 前两任务 QA concerns 处置核对

| concerns | 处置 |
|---|---|
| t1-c1 视觉验收顺延 | 按裁定留用户终审；可自动化部分（提示行存在性）t3 已补 headless 断言 → 闭环 |
| t1-c2 窄情形误写（资源编辑落 Selection） | t2 结构性消除 + 守卫测试（t2 QA 已验）→ 闭环 |
| t1-⚪4 `resources-empty` 渲染断言建议 | t3 未补 → ⚪ 遗留（渲染路径存在，低风险） |
| t2-c1 is_available 门挡副作用 | 设计权衡已披露，裁定无需处置 |
| t2-c2 Add picker headless 断言顺延 t3 | **t3 未补** → ⚪ 遗留（主链路已被 insert_round_trips 覆盖，低风险，建议记 backlog） |
| t2-c3 undo 空壳实体残留记入文档/清单 | **t3 文档未记** → ⚪ 遗留（建议记 backlog） |

## 5. 发现汇总

1. ⚪ [程序] `loop/plans/roadmap-gap-analysis.md` 统计行多数 1：逐行实数 **75 项（✅44/🟡15/❌16）**，文件写 76（✅45/🟡15/❌16）；根因 Stage 2 标题「7 ✅」vs 表 6 行（策划盘点既有矛盾，程序 t3 重算沿用 Stage 标题加总、未逐行复核；本功能三行改动与 🟡/❌ 计数本身正确）。修法一行：Stage 2 标题改「6 ✅」、统计行改「75 项：✅44/🟡15/❌16」。不阻塞。
2. ⚪ [程序] t2 QA 顺延任务 3 的两项（Add picker headless 断言、undo 空壳实体残留记录）未在 t3 处置，程序 t3 报告亦未回应。低风险，建议记入 backlog。
3. ⚪ [程序/环境] doctests 101 为 Windows + bevy_dylib + merged doctests 既有环境问题（本轮 QA 集合比对 + 零交集核实），建议记 CI known-issue 并择机在非 Windows 环境复核。

## 6. 用户手测建议清单（视觉项终审）

1. Level Design 工作区右栏打开 **Resources tab**：面板顶部应有常驻灰字小号提示「Resource changes apply to this editor session only...」；列表 Game 组在前、引擎组在后；顶部搜索框实时过滤行。
2. 点选 **Time\<Virtual\>**（或含游戏自定义资源的类型）行：卡片展开字段；**拖拽 scrub** 相对时间缩放数值 → Ctrl+Z 应恰好撤销这一条（连按逐条回退）；改 **ClearColor 颜色**（取色器）、切一个**枚举字段**，各应产生独立 undo 条目。
3. **Add Resource** 按钮：picker 应只列出可 Default 构造且可见性允许的类型；添加一个再 **Remove Resource**，Ctrl+Z / Ctrl+Shift+Z 验证往返（含原值恢复）。
4. 改一个资源值后 **Ctrl+S 保存场景并重开**：确认资源改动不持久化（会话态语义成立，与提示一致）。
5. **PIE Live 模式**下在面板改资源字段：确认编辑器侧生效、运行中游戏进程不受该编辑影响（资源编辑不流 PIE）。

## 7. 证据索引

- 门日志：`%TEMP%\qa-t3-gates.bat` 串行脚本；fast/integration/doc/doctests 日志 `%TEMP%\qa-t3-{fast,integration,doc,doctests}.log`；标记行 `*_EXIT=n` 见后台任务 stdout。
- diff：`git show 4fa481ac`（6 文件 +147/-5）；`git diff --stat main..loop/resource-inspector` 同集。
- 关键文件：`book/src/user-guide/resources.md`、`book/src/SUMMARY.md`、`book/src/developer-guide/custom-components.md`（Custom resources 段）、`crates/jackdaw_localization/src/locales/en-US/main.ftl:14`、`src/inspector/resource_panel.rs`（ResourceSessionNotice :266-270、children 首位 :315-328）、`tests/resource_panel/list_and_show.rs:117-131`、`loop/plans/roadmap-gap-analysis.md`（:8 统计、:38/:47/:48 三行、:41 Stage 2 标题）。
- SUMMARY 链接验证：PowerShell 全量 Test-Path（ALL RESOLVE）。
