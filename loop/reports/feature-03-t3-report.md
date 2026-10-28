# 功能 #3「Run targets / profiles」任务 3 报告：heavy smoke + 回归锚点 + 文档 + 盘点表 + 全量 CI 门

> 多 Agent 开发循环 · 程序（Rust/Bevy 工程师）
> 分支 `loop/run-targets` · 提交 **728c2c87** `Add run-target heavy smoke, docs and regression anchors`（7 文件，+456/-39，基于任务 2 合入后的 main 55ceedc7）
> 方案：`loop/plans/feature-03-run-targets.md` 任务 3 + §D7-5/D8；范围含历轮 QA 四项移交（见 §2）。
> 任务 3 之外无越界；`loop/` 目录按仓库惯例不入 git（.git/info/exclude）。
>
> **接管说明**：前任程序 agent 中途死亡，本报告由接管 agent 基于其半成品（全部代码/文档/测试改动 + 报告草稿）逐项核查后续跑全部门并终稿。半成品质量核查结论：代码与文档全部可留，零重写；报告草稿中的门数据**未经其提交验证**（哈希为占位符），下表为接管会话实测值——恰与前草稿声称值一致，唯 heavy 需先修复一处环境事故（见 §1b）。

## 1. 全量 CI 门（逐条退出码，接管会话实测）

| 门 | 命令 | 退出码 | 结果 |
|---|---|---|---|
| fast | `cargo xtask fast` | **0** | fmt check + clippy --workspace --all-targets --features dylib -D warnings + lib tests：**2776 passed / 2 skipped**（任务 2 基线 2771 → +5，恰为本任务新增单测 5 个：binary 4 + jackdaw_cli 1） |
| integration | `cargo xtask integration` | **0** | **4907 passed / 3 skipped**（基线 4902 → +5，恰为本任务新增单测中进该档的 5 个；heavy smoke 所在的 `bsn_game_run` 整个二进制在 `SDK_BINARIES` 排除串中——integration 会编译它但不运行） |
| docs | `cargo doc --locked --workspace --document-private-items --no-deps` | **0** | 仅既有 build script warning，零新 warning（输出逐行核对，改动 crate 无任何 rustdoc 告警） |
| doctests | `cargo test --locked --workspace --doc --features bevy/dynamic_linking` | **101（既有，非回归）** | 另用 `--no-fail-fast` 全量复跑核对：失败集合**恰为** `-p jackdaw_bind --doc`、`-p jackdaw_feathers --doc`、`-p jackdaw_node_graph --doc` 三项，与 feature-01/02-t3 基线逐项相同，零新增失败 → 非回归 |
| heavy | `cargo xtask heavy` | **0** | 修复环境事故后复跑：**4 tests run: 4 passed (1 slow), 0 skipped**——bsn_game_run 2/2（新 heavy smoke `a_run_target_builds_and_runs_its_example` 2.0s + 默认 target 回归 26.6s）、editor_journey `author_save_build_play` 115.6s、mcp_smoke 全绿。事故详情见 §1b |

## 1b. 环境事故：fixture 未入库 Cargo.lock 上游漂移（已修复，非代码回归）

首跑 heavy 失败（exit 1，3/4 败：bsn_game_run 两测试 + editor_journey），根因**不在本任务代码**：`tests/fixtures/bsn_game/Cargo.lock` 是**未入库**的本地解析产物（git 只跟踪 fixture 的 Cargo.toml/src/assets），前任会话时段（2026-10-23 11:53）被重新解析，解析器把 `gpu-allocator 0.28.0`（版本要求 windows `>=0.53,<=0.62`）落到 **windows 0.61.3**，而 `wgpu-hal 30.0.1` 要求 windows 0.62.2——同一图形栈两侧 windows 版本分裂，`wgpu-hal` 源内 `dx12/suballocation.rs:83` 直接 E0308（expected/ found 两个不同 `ID3D12Device`）。三个失败测试全是构建该 fixture 的路径，故一损俱损；`mcp_smoke` 不建 fixture 故过。

处置：对照根 workspace 锁（根锁同版本组合、gpu-allocator→windows 0.62.2，编辑器一直编译正常），对 fixture 锁做**单边手术**——仅把 gpu-allocator 的依赖边 `windows 0.61.3` 改为 `windows 0.62.2`（其版本要求区间内，cargo 校验通过且重写锁后保持）；ipc-channel（要求 ^0.61 不能动）、cpal/gilrs-core 留在 0.61.3（与 wgpu-hal 无 D3D12 类型交界，无害）。修补后先预热构建 fixture example（exit 0），heavy 复跑全绿。**该锁不入 git，本修复仅本机生效**；风险与建议见 §6.5。

## 2. 四项 QA 移交处置

### 2.1 任务 1 concern①：example + dynamic_linking 的 deps 推导 miss —— **已修（小修复）**

评估：`apply_dynamic_library_path` 原来只试 `binary.parent()/deps`；cargo 把 example 可执行文件放在 `<target-dir>/<profile>/examples/` 下，其 deps 在上一级 `<profile>/deps`——推导 miss，函数静默返回不加搜索路径。影响面：仅「游戏启用 `bevy/dynamic_linking` 且用 example target（Play / `jd run --config` / schema 提取器）」的组合，默认静态链接项目不受影响；但 PIE 的 spawn_instance 与 CLI 直启共用 `prepare_game_command`，该组合下 example 会因找不到 bevy dll 直接起不来——确认是真实缺陷而非理论问题。修复量小（按方案建议「向上回退」）：新增 `build_deps_dir`——从可执行文件父目录起向上找最近的现存 `deps/`（限两层，恰覆盖 cargo 布局 `<profile>/[examples/]`），`apply_dynamic_library_path` 改用它；bin/自定义 profile 行为逐字节不变（第一候选就是原路径）。测试 2 个：`the_deps_dir_is_found_for_bins_and_examples`（bin=兄弟目录、example=上一级、无 deps=None）+ `the_deps_dir_is_prepended_to_the_library_search_path`（deps 前置进搜索路径，经 `Command::get_envs` 实断言）。

### 2.2 任务 1 concerns：cargo JSON `target.kind` 实值 —— **heavy smoke 实机核对一致**

`a_run_target_builds_and_runs_its_example` 用真实 cargo 构建 fixture 的 `schema_echo` example：产物采纳（`executable_for_package`）要求 JSON 记录的 `target.kind` 数组**恰好含字面量 `"example"`**——若 cargo 实际拼写不同，构建会返回 "produced no executable" 而测试失败。Windows 真机构建通过 ⇒ 实值与单测字面量一致，任务 1 的「未验证」项关闭。

### 2.3 任务 2 QA ⚪3：裸命令回归锚点 —— **已落地（抽纯函数 + 精确断言）**

- `jd run`（无 --config）：`cmd_run` 裸路径的命令构造抽为 `bare_cargo_run(root)`；测试 `the_bare_run_path_runs_plain_cargo_run_in_the_project_root` 精确断言 program=="cargo"、args==["run"]、cwd==root、envs 恰 1 项（RUSTUP_TOOLCHAIN）——「无 target = 现行为」的 CLI 半边钉死。
- editor 默认构建路径：`build_project_binary_with_load` 的 cargo argv 拼接抽为 `cargo_build_argv(package, target, target_dir)`；测试 `the_build_command_is_the_historical_one_without_a_target` 断言 None target 的完整 argv 逐项等于历史六段（`build -p <pkg> --target-dir <dir> --message-format=json`），target 版断言旗标拼接位置。注：argv 接收**已解析**的 package（`package_or` 在调用点先行），覆盖行为由既有 `a_package_override_replaces_the_specs_package` 钉住。

### 2.4 任务 1 QA：`no_binary_message` example 文案 —— **已改（小改）**

签名改为 `no_binary_message(package, wanted)`：AnyBinary 分支文案逐字节保持历史原文（测试 `a_missing_executable_names_what_was_missing` 锚定）；example 分支点名 `` example `split_screen` produced no executable `` 并指向 `examples/split_screen.rs`（不再建议加 src/main.rs——测试断言其不出现）；bin 分支同理指向 `src/bin/<name>.rs` / `[[bin]]`。

## 3. heavy smoke（§D7-5，按方案设计执行）

- fixture：`tests/fixtures/bsn_game/examples/schema_echo.rs`（最小 main，打印 `SCHEMA_ECHO_MARKER` 即退；无 JackdawPlugin ⇒ schema 提取器对它快速失败、非致命降级）。
- 测试：`tests/bsn_game_run.rs::a_run_target_builds_and_runs_its_example`——`build_project_binary_with_load` 传 `CargoTarget { example: "schema_echo" }` 真实构建（Windows）→ 断言返回路径含 `examples` 目录段且存在（顺带即 §2.2 的 kind 实值核对）→ 断言 `build.schema.is_none()`（文档化降级）→ `prepare_game_command` + cwd 裸进程直跑 → 断言退出码 0 + 标记行输出。
- 默认 target 回归：同文件既有 `built_game_loads_and_spawns_a_bsn_scene`（无 target 构建→直跑）与本测试共享 `target/bsn_game_run` 构建目录，heavy 档一次跑两个，默认路径回归同档覆盖。
- xtask 规则：并入 `bsn_game_run`（方案允许的两个落点之一），`SDK_BINARIES` 排除串已含 `binary(bsn_game_run)`，integration 不为它编译游戏；heavy 档 `--test bsn_game_run` 原样带上新测试，`test-threads = 1` 保证两测试不并发抢构建锁。**xtask 零改动**（复用既有排除，方案 §3.1 的「SDK_BINARIES 加新测试二进制」仅在新建测试文件时需要）。
- `jd run --config` 完整 CLI 端到端（构建→直启→退出码）未做：方案 D7-5 的 heavy smoke 设计即「构建产物校验 + 直跑断言」（任务书「按方案设计执行」）；CLI 分支的解析/校验/参数路径已由任务 2 单测钉住，直启路径的命令构造与编辑器 spawn 同源（prepare_game_command）。QA 曾建议顺带瞄 `BEVY_ASSET_ROOT` 缺省行为——本 smoke 的直跑未设该变量且通过，但 example 不加载资产，资产根等价性仍是推定（QA 亦认定为理论等价），未验证项如实记录。

## 4. 文档与盘点表

- `book/src/user-guide/play-in-editor.md`：改写过时的「Configs differ only in launch environment, never in what gets built」；新增 `## Run targets` 节（target 四字段 + 两个 TOML 示例、缓存分键语义、Play 徽标、doctor 预检、`jd run --config`、首版限制：无自动发现/无预构建管理、无 --config 保持 cargo run）。
- `book/src/reference/configuration.md`：`[[run]]` 字段表增 `target` 子表（嵌套字段逐一说明 + 示例）；删除过时的「There is no bin or feature selection; runs don't build anything」；Command line 节 `jd build/run` 增 `[--config <label>]` 并加一句语义说明（与 Play 同语义 / 无 config 保持裸 cargo run）。
- `README.md` Features 列表增一行 Run targets。
- 链接核对（本机无 mdbook，与基线同法人工核对）：SUMMARY 两页链接既有；新增链接仅 2 条——configuration.md → `../user-guide/play-in-editor.md#run-targets`（目标文件与 `## Run targets` 标题均在本次提交中存在）、play-in-editor.md 页内锚 `#run-targets`；无断链。
- `loop/plans/roadmap-gap-analysis.md`（本地不入 git）：Stage 5「launch targets/profiles」行**保持 🟡**，证据列更新为四维已落地（899a8f27 / 751bb6b6 / 本提交 728c2c87，指向 t3 报告），缺的半明确写「预构建二进制缓存管理（非技术用户直启）未做 + target 自动发现 UI 未做」；统计行不动（75 项 ✅45/🟡15/❌15）。接管 agent 核查时顺带修正该行一处笔误：`crates/jackdaw_cli_internal` → `crates/jackdaw_cli`（前者是 crate 名、非目录名；fast 门编译输出 `Compiling jackdaw_cli_internal v0.21.0-dev (…\crates\jackdaw_cli)` 可证）。

## 5. 新增测试（6 个）

binary.rs 4（argv 锚点 / deps 目录两级 / deps 前置搜索路径 / no_binary 分文案）+ jackdaw_cli 1（裸 cargo run 锚点）+ bsn_game_run 1（heavy smoke，仅 heavy 档运行）。fast 档 +5、integration +5、heavy +1，与 §1 计数吻合。

## 6. 遗留 / Concerns

1. doctests 门 exit 101：既有环境性失败（同基线三 crate 集合，本会话 `--no-fail-fast` 实核），非本任务引入，维持遗留。
2. `jd run --config` 的完整 CLI 端到端（含 env/args/cwd 进程环境核验）与编辑器「点行即出状态栏错误」完整世界断言，仍未实机覆盖（同任务 2 concerns 口径，属 QA 人工项清单 §5）。
3. example + dynamic_linking 的修复以目录布局单测钉住，未做真机 dylib 组合构建（fixture 是静态 bevy；做该组合需 fixture 开 dynamic_linking 特性，构建代价大且属 cargo/bevy 语义）。若后续做 release-gate 级 dylib fixture，可顺带实机验证。
4. book 未跑 mdbook build（本机无 mdbook，沿基线人工核对法）。
5. **fixture 未入库 Cargo.lock 的解析漂移风险（§1b 根因，环境性、可能复发）**：fixture 锁不进 git，任何一次全新解析都可能再次把 gpu-allocator（宽版本区间 `>=0.53,<=0.62`）落到与 wgpu-hal 不同的 windows 版本上而重演 E0308；本机已修补，CI/新克隆机不受影响（CI 用 archive 档案），但下一台首跑 heavy 的机器或本地删锁后会再撞。建议后续把 fixture 的 Cargo.lock 提交入库（与根锁同受 `--locked` 保护），属仓库策略决定，未在本任务顺手做。另注：前任报告草稿声称 heavy exit 0，但无提交佐证（哈希占位）；本次接管以两次实跑（首跑失败→修锁→复跑全绿）为准，heavy 绿色结论现为实测。
