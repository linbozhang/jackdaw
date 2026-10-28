# 功能 #3 任务 1 QA 验收报告：Run targets 核心机制

> 多 Agent 开发循环 · QA（独立第三方）· 2026-10-22
> 验收对象：分支 `loop/run-targets`，提交 `899a8f27`（基于 main `eb45a3a3`，7 files，+1053/-50）
> 需求口径：`loop/plans/feature-03-run-targets.md` 任务 1 + §D1-D3/D6；主控裁定：含 package 覆盖；无 target = 现行为
> 程序报告：`loop/reports/feature-03-t1-report.md`（4 偏差 + 3 concerns）

## 结论

**VERDICT: PASS**。四门全 0，规格逐条 ✅（向后兼容不变量经独立 diff 核实通过），无 🔴/🟡，⚪ 3 条不阻塞。

## 1. 确定性门（本机实测）

| 门 | 命令 | 退出码 | 计数 |
|---|---|---|---|
| fmt | `cargo fmt --all -- --check` | 0 | — |
| clippy | `cargo clippy --workspace -- -D warnings` | 0 | 日志 0 条 `error`（仅 build-script 级 `linker_messages` 警告，该 lint 明示忽略 `-D warnings`，非本 diff 引入） |
| fast | `cargo xtask fast` | 0 | 2750 run / 2750 passed / 2 skipped |
| integration | `cargo xtask integration` | 0 | 4879 run / 4879 passed / 3 skipped |

计数与程序报告逐字一致。本次未遇进程锁（程序报告第一次 integration 因残留编辑器进程锁失败后 taskkill 重跑全绿，属环境问题，本次复验干净通过）。

## 2. 规格符合性（逐条独立核实）

### 2.1 向后兼容不变量（最重要）— ✅

- **我自己 diff 核实**：main 侧命令构造（`git show main:...binary.rs`）为 `cargo build -p <spec.package_name> --target-dir <dir> --message-format=json`；新代码仅两处触碰——`.args(cargo_target_args(target))`（None 时返回 `Vec::new()`，`.args([])` 对 argv 是 no-op）与 `-p package`（target=None 时 `package = spec.package_name`，逐字节相同）。构建日志行用的 `package` 变量在 None 时同值。**无其它 target 分支改动命令**。
- **测试真实断言**：`no_target_adds_nothing_to_the_cargo_command`（binary.rs）断言 `cargo_target_args(None) == []` 与 default 结构体 == []，精确 Vec 相等，非子串弱断言；配合构造点唯一（binary.rs 拼接处），不变量成立。
- **API 级兼容**：3 参 `build_project_binary` 签名未变（内部传 None），全部既有调用点（`tests/bsn_game_run.rs:36`、`tests/scaffold_e2e.rs:31`、`crates/jackdaw_cli/src/lib.rs:625`、`tests/editor_journey.rs:110`、`binary.rs:820`）零改动。

### 2.2 schema（D1）— ✅

- `RunTarget { package?, bin?, example?, features: Vec, profile? }` 全 `#[serde(default)]`；`RunConfig.target: Option<RunTarget>`；`validate()` bin XOR example + 非空白名，不用 serde untagged（按 D1-4）。
- 互斥校验测试真实存在且过：both / neither / 空白名（bin 与 example 各一） / 恰一合法，共 4 个拒绝/接受用例（manifest.rs）。
- 旧 TOML 解析不变：`a_manifest_from_before_targets_parses_field_by_field` 用 LOCKSTEP_FIXTURE（plugin/package/[jackdaw] 节/3 个 run/instances/env/args/cwd/mode）逐字段断言，无 target 的 run 断言 `target.is_none()`。全仓 `rg deny_unknown_fields` 零命中（我复核）。
- 锁步测试两侧各半（pie_protocol + run_manifest），同一 TOML 字面量（LOCKSTEP_FIXTURE 注释互指），任一侧字段名漂移即红。

### 2.3 构建透传（D2）— ✅

- argv 顺序：`cargo build -p <覆盖或spec包> [--bin X | --example X] [--features a,b] [--profile P] --target-dir … --message-format=json`。features 逗号连接为单参数（cargo 标准，`--features net,dedicated`）；cargo 对这些旗标顺序不敏感，语义正确。
- **产物路径零拼路径**：`executable_for_package` 仅取 JSON `executable` 字段（`PathBuf::from(executable)`），diff 中无任何路径拼接新增；`WantedArtifact::{AnyBinary, CargoTarget{name, example}}` 收紧为 `target.name` + `target.kind`（`"bin"`/`"example"`）双匹配，带 sibling bin 不采纳（有测试）；无 `target` 表的记录 AnyBinary 照旧采纳（有测试）。
- package 覆盖同时作用于 `-p`、`package_id` 过滤与 `no_binary_message`，一致。
- `cargo_target_args` 测试为精确逐项 Vec 相等（None=空 / bin+features+profile / example / 矛盾与空白降级）。

### 2.4 PIE 缓存分键（D3）— ✅

- `builds: HashMap<BuildKey, BuildState>`，`type BuildKey = (PathBuf, Option<CargoTarget>)`；`build_key(root, run)` 纯函数。
- **取键点全覆盖（rg 逐点核实，无遗漏裸 root 键）**：`launch_instance` 4 处（命中/remove/挂 pending/新插，pie.rs:653/665/675/684）、`prebuild_play_target`（首个 run 的 target，:1344/1364）、`spawn_project_build`（Rebuild/auto-build 固定 `(root, None)`，:1459/1469）、`watch_project_source_for_edit`（`(root.clone(), None)`，:1519——程序偏差②，方案未列但 auto-build 监视默认产物语义必需）、`poll_builds`（`key.0` 取项目名）；`is_pending/is_launching/launch_failed/handle_stop/reconcile_build_status` 走 `values()`/`clear()` 多键天然泛化；`handle_reload` 经 `launch_instance`（pie.rs:565）天然携带各自 target。
- `build_key` 三性质测试真实存在：无 target 共默认键 / 有 target 独键 / 同 root 异 target 不撞且同 target 命中（`build_key_tests` 3 个）；prebuild 世界模式两例（首个 run 带 target 越过暖默认键继续尝试到 Blocked + 暖默认键存活；无 target 时暖键早退、builds.len()==1）。
- `spawn_game_build` 增 `target` 参数透传 `build_project_binary_with_load`。

### 2.5 无任务 2/3 越界 — ✅

diff 仅 7 文件（manifest.rs / binary.rs / project_build lib.rs / run_manifest.rs 新 / src/pie.rs / src/project_build.rs / src/run_config.rs）。无 `crates/jd` SPECS 改动、无 `--config` 旗标（rg 全查仅 run_manifest.rs 文档注释提及与 xtask/release.rs 既有无关命中）、无 doctor、无 pie_menu 徽标、无 fixtures/xtask 改动、无文档。

### 2.6 偏差抽验（4 项抽 3）

- **④ `no_binary_message` 收包名**：✅ 等价。私有 fn 签名 `&ShimSpec` → `&str`；调用点唯一（binary.rs:274，传已解析 `package`）；package 覆盖时错误指对包、默认路径 `package == spec.package_name` 文案逐字节不变。
- **① prebuild 暖缓存检查前移**：✅ 实质等价。读代码核实：`builds.insert` 全部三处入口（launch_instance/prebuild/spawn_project_build）都要求 `shim_spec_for_project` 先成功，暖键存在即蕴含 spec 曾解析成功；唯一分叉场景（暖键存在且 spec 此刻失败）需在一次性 prebuild（attempted 门闩）窗口内项目被改坏，实际不可达。前移使「首 run 带 target 时预构建带 target」可在 headless 世界模式下断言，方案 D7-4 允许。
- **③ launch 前预校验只做 schema 级 validate**：⚠️→接受。metadata 存在性预检（列可用 bins/examples）依赖任务 2 的 CargoMeta 访问器，程序已声明留给任务 2；`launch_instance` 入口的 `validate()` + `notify_error`（pie.rs:626-634，镜像 save_before_play 失败路径）真实落地且先于 build_key。**主控需确认任务 2 覆盖 D6-1 三处 metadata 预检**。

### 2.7 新增测试计数复核

逐文件数 `#[test]`：manifest.rs 7 + binary.rs 8 + run_manifest.rs 5 + run_config.rs 2 + pie.rs 5 = **27**，与程序报告一致。

## 3. 代码质量

- **类型边界** ✅：`RunTarget`（pie_protocol，serde，无 Hash）/ `CargoTarget`（project_build，无 serde，`Hash/Eq/Clone`）/ `RunTargetSpec`（run_manifest CLI 镜像）；生产代码中 `RunConfig → CargoTarget` 转换唯一点 `src/run_config.rs:59 cargo_target`（rg 核实其余构造均在测试内）。两读者共存哲学与 `project_manifest.rs` 头注释一致。
- **无 unwrap 滥用** ✅：diff 新增行的 `.unwrap()` 全部在 `#[cfg(test)]` 内；无 `allow`/`unsafe`/`todo!`/`unimplemented!`。
- **断言质量** ✅：argv/解析断言全部精确 Vec/字段相等对比，无子串弱断言（错误文案测试用 `contains` 属合理）。

### 质量发现（⚪ 不阻塞）

1. **⚪[程序报告] 「LOCKSTEP_FIXTURE 含 pins」表述不准确**：fixture 实含 plugin/package/[jackdaw]/多 run，无 `pins` 表（pins 是 `project_manifest.rs` 概念，pie_protocol Manifest 本就不解析它）。旧文件守卫实质成立（无 target 的 run 逐字段断言 + 全仓无 deny_unknown_fields），仅报告措辞失实。
2. **⚪[程序] `prebuild_play_target` 未对首个 run 的 target 先 `validate()`**：若首 run target 同时写 bin+example（无效配置），prebuild 仍会以降级语义（bin 胜出）白构建一次存入永远不会被消费的键；launch 侧 validate 会拦截启动，无正确性风险，仅极端配置下浪费一次后台构建。
3. **⚪[程序] bin 优先/空白降级先序逻辑在 `cargo_target_args` 与 `WantedArtifact::from` 两处重复**：注释互指且各有测试钉住，但仍是需手工同步的重复；后续若改先序（如 example 优先）须两处同改。

## 4. Concerns（移交主控 / 任务 2/3）

- 程序自报 3 条未验证项属实且已如实声明：example + `bevy/dynamic_linking` 的 deps 目录推导 miss（`apply_dynamic_library_path`）、不响应 SCHEMA_FLAG 的 target 提取 120s 延迟、cargo JSON `target.kind` 实值未真机核对——均指向任务 3 heavy smoke 实机核对点，QA 认可该移交。
- 偏差③：D6-1 的 metadata 存在性预检（编辑器 launch/`jd run/build --config`/doctor 三处）为任务 2 必做项，主控已在任务 2 范围内，需验收时盯住。
- `no_binary_message` 文案对 example target 略欠贴切（仍建议「加 src/main.rs」），预存文案，非本任务引入，可留任务 3 文档/打磨顺带。

## 5. 证据索引

- 不变量：`git show main:crates/jackdaw_project_build/src/binary.rs`（旧 argv）vs 分支 binary.rs:225-231（新拼接）；测试 `no_target_adds_nothing_to_the_cargo_command`（binary.rs 测试模块）。
- 分键：`src/pie.rs` BuildKey 定义（:39 附近）、`build_key`（:697-700）、取键点行号见 §2.4；`build_key_tests` / `prebuild_tests`（pie.rs:2661+/2712+）。
- 转换唯一性：`rg "CargoTarget \{|cargo_target\("` 生产代码命中仅 `src/run_config.rs:59` 与 `src/pie.rs:699`（调用点）。
- 门与计数：本报告 §1，均为本机实测退出码。
