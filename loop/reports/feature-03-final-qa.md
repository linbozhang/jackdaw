# 功能 #3「Run targets / profiles」任务 3 + 功能级终验 QA 报告

> 多 Agent 开发循环 · QA（独立第三方）· 2026-10-22
> 验收对象：分支 `loop/run-targets`，提交 **728c2c87** `Add run-target heavy smoke, docs and regression anchors`（7 files，+456/-39，基于 main 55ceedc7 = 任务 1/2 已合入）
> 需求口径：`loop/plans/feature-03-run-targets.md` 任务 3 + §5 QA 验收清单 + D7-5/D8；历轮盯住/移交项处置
> 程序报告：`loop/reports/feature-03-t3-report.md`（含接管事故记录、四项移交处置、fixture 锁 concern）
> QA 本轮全部亲跑/亲读核实：五门全量重跑（含 heavy）、diff 逐文件读、接管半成品质量、concern 独立评估

## 结论

**VERDICT: PASS（功能级）**。五门全过（heavy 亲跑 4/4 绿）；任务 3 规格逐条 ✅；四项移交处置全部核实为正确落地（deps 推导修复经独立判断成立）；接管半成品质量干净（无前任遗留垃圾）；fixture 锁 concern 属实并建议入库（见 §6）。无 🔴/🟡，⚪ 4 条不阻塞（§8）。

## 1. 确定性门（本机亲跑，2026-10-22）

| 门 | 命令 | 退出码 | 计数/备注 |
|---|---|---|---|
| fast | `cargo xtask fast` | **0** | 2776 passed / 2 skipped（t2 基线 2771 → +5，恰为本任务新增单测：binary 4 + jackdaw_cli 1）；fast 内含 fmt --check 与 clippy --workspace --all-targets --features dylib -D warnings，均绿 |
| integration | `cargo xtask integration` | **0** | 4907 passed / 3 skipped（基线 4902 → +5）；输出首行即可见 filter `not (binary(bsn_game_run) \| …)`——heavy smoke 所在二进制被排除规则命中，未在 integration 运行 |
| docs | `cargo doc --locked --workspace --document-private-items --no-deps` | **0** | Finished in 2m17s。注意：输出含 **1 条 rustdoc warning**（`public documentation for pie links to private item BuildKey`）——经 `git log -S` 核实由任务 1 提交 899a8f27 引入、已在 main，非任务 3 引入（任务 3 diff 不含 src/pie.rs）；但 t3 报告「零新 warning」的逐行核对未提及此条存量 lib doc warning（见 ⚪2） |
| doctests | `cargo test --locked --workspace --doc --features bevy/dynamic_linking --no-fail-fast` | 101（既有） | `error: 3 targets failed: -p jackdaw_bind --doc / -p jackdaw_feathers --doc / -p jackdaw_node_graph --doc`——失败集合与 feature-01/02 基线**逐项相同 → 非回归**；本功能改动与三失败 crate 零交集；jackdaw 主 crate 3 条 doctest 全 ignored 与基线一致 |
| heavy | `cargo xtask heavy` | **0** | **4 tests run: 4 passed, 0 skipped**——`a_run_target_builds_and_runs_its_example` PASS 1.7s（新 heavy smoke）、`built_game_loads_and_spawns_a_bsn_scene` PASS 4.7s（默认 target 回归）、`editor_journey::author_save_build_play` PASS 6.3s、`mcp_smoke` PASS 0.03s（本机 target 预热充分，故远快于程序会话的首跑值）。**一次通过、无需修锁**：fixture 锁的 windows 双版本修补（0.61.3+0.62.2）在本机仍有效（§6） |

## 2. 任务 3 规格（逐条独立核实）

### 2.1 heavy smoke（§D7-5）— ✅
- fixture `tests/fixtures/bsn_game/examples/schema_echo.rs`：最小 main，打印 `SCHEMA_ECHO_MARKER` 即退；doc 注释明说不接 JackdawPlugin（schema 提取器对它快速失败、非致命降级）。
- 测试 `a_run_target_builds_and_runs_its_example`（tests/bsn_game_run.rs）：`build_project_binary_with_load` 传 `CargoTarget { example: "schema_echo" }` **真实构建**（Windows）→ 断言 `binary.exists()` 且路径 components 含 `examples` 段（产物采纳自 cargo JSON `executable`，零拼路径）→ 断言 `build.schema.is_none()`（文档化降级）→ `prepare_game_command` + cwd 裸进程直跑 → 断言退出码 0 + 标记行。**本 QA 亲跑 heavy 全绿。**
- **`target.kind` 实值断言存在（实机核对链路成立）**：`executable_for_package` 的 `WantedArtifact::CargoTarget::matches`（binary.rs:656-666）要求 JSON 记录 `target.kind` 数组**含字面量 `"example"`** 且 `name` 匹配，否则产物不被采纳 → 构建返回 "produced no executable" → 测试红。heavy 真机构建通过 ⇒ cargo 实值与单测字面量一致，任务 1 「未验证」项关闭。
- **heavy 档被 integration 排除（核实）**：`xtask/src/main.rs:69` `SDK_BINARIES` 含 `binary(bsn_game_run)`，integration filter `not (SDK_BINARIES)`（:123/137）；heavy 档 `--test bsn_game_run` 带上新测试（:226-227），nextest heavy profile 串行。**xtask 零改动**合理：方案 §3.1 的「SDK_BINARIES 加新测试二进制」仅在新建测试文件时需要，本测试并入既有 bsn_game_run 二进制。

### 2.2 deps 推导修复（t1 concern①，程序自称「真实小缺陷已修」）— ✅ 修复正确（独立判断）
- **缺陷定性属实**：cargo 把 example 可执行文件放 `<target-dir>/<profile>/examples/`，其动态库在 `<profile>/deps/`（上一级）；原 `apply_dynamic_library_path` 只试 `binary.parent()/deps` = `<profile>/examples/deps`（不存在）→ 静默不加搜索路径 → `bevy/dynamic_linking` 游戏用 example target 时 bevy dll 找不到、起不来。PIE `spawn_instance` 与 CLI 直启共用 `prepare_game_command`，影响真实。
- **修复读代码核实**：`build_deps_dir`（binary.rs:609-616）从可执行文件父目录起 `ancestors().take(2)` 找最近现存 `deps/`——bin 第一候选即原路径（行为逐字节不变），example 第二候选恰命中 `<profile>/deps`；自定义 profile 同布局成立；无 deps → None，`apply_dynamic_library_path` 早退（等价旧行为）。`take(2)` 是 cargo `<profile>/[examples/]` 两级布局的准确刻画。
- **2 单测核实且过**：`the_deps_dir_is_found_for_bins_and_examples`（真实 temp 目录：bin 兄弟命中 / example 上一级命中 / 无 deps=None，精确 `assert_eq!`）+ `the_deps_dir_is_prepended_to_the_library_search_path`（经 `Command::get_envs` 实断言 deps 前置于 PATH 首位）。

### 2.3 裸命令双锚点（t2 QA ⚪3）— ✅
- `bare_cargo_run(root)`（jackdaw_cli lib.rs:723-730）= `rust_env_command("cargo")` + `arg("run")` + `current_dir(root)`，与 main 侧 cmd_run 构造逐字节相同（我 diff 两侧核对）；`rust_env_command` 只设 `RUSTUP_TOOLCHAIN`（jackdaw_env lib.rs:15-19），`without_console_window` 只设 creation flag 不加 env。测试 `the_bare_run_path_runs_plain_cargo_run_in_the_project_root` 精确断言 program=="cargo"、args==["run"]、cwd==root、envs 恰 1 项（RUSTUP_TOOLCHAIN）。
- `cargo_build_argv(package, target, target_dir)`（binary.rs:208-231）纯函数；测试 `the_build_command_is_the_historical_one_without_a_target` 断言 None target 完整 argv 逐项等于历史六段（`build -p <pkg> --target-dir <dir> --message-format=json`），target 版断言旗标拼接位置（-p 之后、--target-dir 之前）。main 侧旧构造 `.args(cargo_target_args(None))` 为 no-op ⇒ 机制性等价，非目测。

### 2.4 no_binary_message（t1 QA 文案项）— ✅
- AnyBinary 分支文案逐字节保持历史原文（Rust `\` 续行吞行首空白，缩进加深不改字面量；测试 `a_missing_executable_names_what_was_missing` 用硬编码 expected 锚定，我对照 main 的 `-` 侧文案逐词一致）。
- example 分支点名 `` example `split_screen` produced no executable `` 并指向 `examples/split_screen.rs`，测试断言 `src/main.rs` 建议不再出现；bin 分支同理指向 `src/bin/<name>.rs` / `[[bin]]`。

### 2.5 book 两页 + README — ✅
- `reference/configuration.md`：`[[run]]` 字段表增 `target` 子表（bin/example 恰一、package、features、profile 四字段逐一说明 + 双 TOML 示例）；删除过时的「There is no bin or feature selection; runs don't build anything」；Command line 节 `jd build/run` 增 `[--config <label>]` + 语义说明（与 Play 同语义 / 无 config 保持裸 cargo run）。与实现逐点对得上（schema 字段 = manifest.rs RunTarget；profile 说明 = doctor `profile_is_available` 行为，lib.rs:484-487）。
- `user-guide/play-in-editor.md`：新增 `## Run targets` 节（四字段、缓存分键语义「playing Play and then Server launches each its own binary」、Play 行 `bin:…`/`example:…` 徽标、doctor 预检三查、`jd run --config` 语义、**首版限制明写**：无 workspace bins/examples 自动发现、无 prebuilt-binary 管理）；改写过时的「Configs differ only in launch environment, never in what gets built」。锚点链接 `#run-targets` 目标存在，SUMMARY 两页链接既有。
- `README.md` Features 列表增一行 Run targets（位置按字母序合规）。

### 2.6 盘点表 — ✅（一处小出入见 ⚪3）
- Stage 5「launch targets/profiles」行**保持 🟡**；已落地半边证据完整（schema/透传/分键/徽标/CLI/doctor/heavy smoke/文档，逐一列文件路径）；剩余半边明写「**预构建二进制缓存管理（非技术用户直启，prebuilt binaries）未做**——现状 `.jackdaw/target/game` 只有隐式 cargo 缓存，无跨 target 产物登记/复用；target 自动发现 UI 亦未做」——与 D8 声明一致。
- 统计行不动：75 项 ✅45 / 🟡15 / ❌15（行 8 原文核对）。
- `jackdaw_cli` 笔误修正核实：行文现为「`crates/jackdaw_cli`，crate 名 jackdaw_cli_internal」——目录名/crate 名分开表述，修正到位（doctests 输出 `Compiling jackdaw_cli_internal v0.21.0-dev (…\crates\jackdaw_cli)` 可证）。
- 小出入：任务书口径「证据列三哈希」——实际行文为 `899a8f27` + `751bb6b6` 两个显式哈希 + 「任务 3 提交见 `loop/reports/feature-03-t3-report.md`」间接引用（报告头部有 728c2c87）。可追溯性等价，与字面不全符。

### 2.7 接管质量（前任半成品全量保留）— ✅
- diff 全文 rg `TODO|FIXME|XXX|unimplemented|todo!|HACK|placeholder` **零命中**；无死代码（clippy --all-targets -D warnings 全绿即隐式覆盖未用项）；无半成品占位符；测试断言全部精确相等/contains 合理混用。程序报告「代码与文档全部可留，零重写」的核查结论与我所见一致。

## 3. 四项移交处置核实（各一行）

1. **deps 修复**：✅ 真实缺陷、修复正确、双单测真实且过（§2.2，独立判断成立）。
2. **target.kind 实值**：✅ heavy smoke 产物采纳隐含精确断言（matches 要求 kind 数组含 "example"），真机通过即实值核对（§2.1）。
3. **裸命令双锚点**：✅ `bare_cargo_run` + `cargo_build_argv` 两测试存在且过（fast 2776 内），无 --config 命令串逐字节钉死（§2.3）。
4. **no_binary_message**：✅ AnyBinary 历史逐字节兼容（续行语法核实）+ example/bin 分支文案测试（§2.4）。

## 4. heavy 亲跑记录（接管事故的独立复核）

程序报告 §1b 称首跑 heavy 因 fixture 未入库锁的上游漂移失败、修锁后复跑全绿。本 QA 环境：fixture `Cargo.lock` 现含 windows 0.61.3 + 0.62.2 双版本（与报告描述的修补态一致），heavy **一次通过、无需任何修复**——侧面印证报告的「修锁后全绿」非孤例，且锁定状态下结果可复现。前任报告草稿门数据为占位符、接管会话以实测为准的处理方式正确（fast/integration 计数本轮逐字复现：2776/2、4907/3）。

## 5. 功能级终验（方案 §5 清单逐项）

**确定性门 6/6**：fmt ✓（fast 内含）· clippy -D warnings ✓（fast 内含）· fast ✓0 · integration ✓0（SDK_BINARIES 排除生效，filter 见输出首行）· doc ✓0（1 条存量 warning 见 ⚪2）· doctests 101 基线集合相同非回归 ✓。

**headless 行为断言 6/6**：旧 TOML 逐字段+完整快照 ✓（t1 QA §2.2，测试在本轮 fast 全绿内）· cargo_target_args 组合 ✓（t1 §2.3）· validate 双拒 ✓（t1 §2.2）· builds 分键三性质+prebuild 首 run target ✓（t1 §2.4，含 t2 补的先 validate）· 未知 --config label 列名 ✓（t2 单测+实机）· `jd run` 无 --config 逐字节 ✓（本轮 bare_cargo_run 锚点）。

**heavy 档 2/2**：example target 构建→examples/ 段→存在→运行标记行 ✓（本轮亲跑）；默认 target 构建后可跑回归 ✓（`built_game_loads_and_spawns_a_bsn_scene` 同档绿）。

**文档项 2/2**：book run targets 节四字段+示例+README 一行 ✓；roadmap Stage 5 证据更新仍 🟡（D8 原文）✓。

**人工 3 项**：留用户手测（§7 建议），按历轮口径非阻塞。

**方案范围裁定遵守**：无 target 自动发现 UI、无预构建二进制缓存、无 triple 透传、无 --no-default-features——diff 全文核实无越界实现。

## 6. Concern 评估与建议

- **fixture Cargo.lock 不入库 → 全新解析可能上游漂移（程序 §6.5）——风险描述属实，QA 建议入库**。证据：git 仅跟踪 fixture 的 Cargo.toml/src/assets/examples（`git ls-files` 核实），锁纯属本地产物；gpu-allocator 版本区间宽（`>=0.53,<=0.62`），重解析可再现 windows 版本分裂 → wgpu-hal E0308。本次事故中「单边手术」（gpu-allocator 边改 windows 0.62.2，其余留 0.61.3）与根 workspace 锁同组合、cargo 校验通过，处置得当。**给主控的建议（一句）：建议把 `tests/fixtures/bsn_game/Cargo.lock` 提交入库、与根锁同受 `--locked` 保护——fixture 依赖闭包（bevy 全家桶）本就该锁死可复现，入库后 CI/新机/删锁机全部免疫此类漂移；属仓库策略决定，QA 未自行改动。**
- **example + dynamic_linking 真机组合未验——属实，属已知限制**：修复由目录布局单测钉住（§2.2），fixture 是静态 bevy，做 dylib 组合需 fixture 开特性、构建代价大；deps 目录推导逻辑与链接方式无关（纯路径规则），风险低。记录为已知限制，建议随未来 release-gate 级 dylib fixture 顺带实机验证。

## 7. 用户手测建议（视觉/人工项，3-5 条）

1. **Play 下拉徽标**：带 target 的 run 行出现行尾暗色小徽标（`bin:server` / `example:split_screen`），不与 label 重叠错位、与无 target 行（无徽标）视觉可辨；点击可正常启动/停止。
2. **错误呈现**：拼错 bin 名 → 点击行，**不等构建**即出状态栏错误并列出该包声明的可用名；拼错 feature → 构建面板/footer 出现 cargo 原始 error 行（状态栏取首条 error 摘要）。
3. **缓存分键手工复验**：同项目依次 Play 默认 → Play example target → 切回默认，确认各自起正确二进制（第二次起默认时不再重编 example、反之亦然）。
4. **`jd run --config` 真 CLI 手感**：终端跑一次带 target 的 run config（含 env/args/cwd），确认进程环境生效、退出码透传；再跑 `jd run`（无 --config）确认仍是熟悉的裸 `cargo run` 输出。
5. **doctor 呈现**：带 target 项目跑 `jd doctor`，看 run targets 节 `[ ok ]`/`[fail]`/`[warn]` 三态排版与 fix 提示行（t2 QA 已实测内容正确，此项看观感）。

## 8. 发现（不阻塞）

1. **⚪[程序报告] 盘点表「三哈希」实为两哈希 + 报告指针**：Stage 5 行证据列第三项写「任务 3 提交见 t3 报告」而非显式 728c2c87（§2.6）。可追溯性等价，措辞与任务书字面不全符。
2. **⚪[程序报告/前序任务] doc 门存量 rustdoc warning 未被报告提及**：`pie` 公共文档链接私有项 `BuildKey`（src/pie.rs:10/115，任务 1 提交 899a8f27 引入、main 已有，t3 报告「零新 warning」逐行核对漏计此条存量）。修复一行（去链接文字或 [`BuildKey`][private] 注解），建议顺手清。
3. **⚪[程序] heavy smoke 与方案 §D7-5 字面差异未明示为偏差**：方案写「`util::run_windowless_game` 跑之断言标记输出」，实现用 `prepare_game_command` 裸进程直跑。核实为**必要且正确**的偏差——`run_windowless_game` 起 PIE IPC 并等待 `BSN_SCENE_LOADED`，要求游戏接 JackdawPlugin；schema_echo 故意不接插件，走该 util 永远等不到信号。报告 §3 未将该差异列为偏差项。
4. **⚪[程序/既有] `jd run --config` 完整 CLI 端到端（构建→直启→退出码、env/args/cwd 进程环境核验）与编辑器状态栏错误完整世界断言仍未实机覆盖**（同 t2 concerns 口径，程序已如实声明；`BEVY_ASSET_ROOT` 缺省等价为推定）。归入 §7 用户手测 4/2。

## 9. 证据索引

- 门日志：本轮五门亲跑（fast/integration/heavy 后台任务输出 + doc/doctests 前台/后台输出），计数见 §1。
- 修复与锚点：`crates/jackdaw_project_build/src/binary.rs`（cargo_build_argv :208 / build_deps_dir :609 / no_binary_message :718+ / matches :656；四测试在文件尾 tests 模块）、`crates/jackdaw_cli/src/lib.rs`（bare_cargo_run :723 + 测试）。
- 排除规则：`xtask/src/main.rs:69`（SDK_BINARIES）/ :123/:137（integration filter）/ :165-233（heavy 定义 `--test bsn_game_run`）。
- fixture 锁：`git ls-files tests/fixtures/bsn_game`（无 Cargo.lock）；锁内 windows 0.61.3+0.62.2 双版本。
- 盘点表：`loop/plans/roadmap-gap-analysis.md` Stage 5 行 + 统计行（本地不入 git）。
- BuildKey warning：`git log -S "BuildKey" -- src/pie.rs` → 899a8f27（任务 1，已在 main）。
