# 功能 #3 任务 2 程序报告：`jd --config` + cargo metadata 预检 + Play 徽标

> 多 Agent 开发循环 · 程序（Rust/Bevy 工程师）· 2026-10-22
> 分支 `loop/run-targets`，提交 `751bb6b6`（基于任务 1 合入后的 main `21c7dd1e`，8 files，+1096/-71）
> 需求口径：`loop/plans/feature-03-run-targets.md` 任务 2 + §D4（Play 下拉徽标）/§D5（CLI）/§D6（校验与诊断）；主控裁定：旗标名 `--config`、徽标本轮做。
> 任务 3 范围（heavy smoke、book/README 文档、roadmap 盘点表、全量 CI 门）**未做**。

## 1. 确定性门（本机实测，均为退出码 0）

| 门 | 命令 | 结果 |
|---|---|---|
| fmt | `cargo fmt --all -- --check` | 0 |
| clippy | `cargo clippy --workspace -- -D warnings` | 0 |
| fast | `cargo xtask fast`（内含 fmt + clippy `--all-targets --features dylib` + 全 workspace `--lib` 测试） | 0；2771 run / 2771 passed / 2 skipped（任务 1 基线 2750 → +21，jd bin crate 的 2 个测试不进 `--lib` 档） |
| integration | `cargo xtask integration` | 0；4902 run / 4902 passed / 3 skipped（任务 1 基线 4879 → +23，恰为本次新增测试总数） |

环境备注：第一次 integration 因 `prefabs` 测试 exe 被残留进程锁（linker `permission denied`）失败，与任务 1 QA 遇到并记录的同类环境问题一致；`tasklist` 无可见占用、删除该 exe 后重跑全绿，非本 diff 引入。

## 2. cargo metadata 存在性预检（QA 盯住项，§D6-1 三处全部落地）

预检核心是 project_build 的纯函数（`crates/jackdaw_project_build/src/cargo_meta.rs`）：

- `CargoMeta::target_names(package, kind)` / `CargoMeta::has_package(package)` —— 从 `--no-deps` metadata 展平某成员的全部 `[[bin]]`/`[[example]]` 名（双拼写：`my-game`/`my_game` 均匹配，与 `resolve_package` 口径一致）；
- `cargo_meta::check_run_target(meta, spec_package, target) -> Result<(), String>` —— 先解析生效 package（target 自带 `package` 覆盖，经 `CargoTarget::package_or`，与构建命令同源），再比对 bin/example 名。错误措辞镜像 `ResolveError`：未知的包列成员名（`` `x` is not a package here (found: a, b) ``）、未知的 bin/example 列可用名（`bin `x` is not a target of package `p` (available bins: …)`，包无该类 target 时说 `declares no examples`）。无 target（package 默认）不检查、返回 Ok。

### 三处挂接点

| # | 位置 | 通路 | 证据 |
|---|---|---|---|
| 1 | 编辑器 `launch_instance`（构建前） | `src/pie.rs` 新增 `preflight_run_target(root, spec.package_name, target)`：`CargoMeta::load`（失败则降级放行——构建自己会报，预检只精化错误、不制造错误）→ `check_run_target`。挂在 spec 解析之后、挂 pending/发起构建之前；失败 `warn!` + `status_bar::notify_error`（镜像 `save_before_play` 失败路径，pie.rs:641-645 同款）。**位于暖缓存命中检查之后**：暖 Play 不付出 metadata 延迟；正确性由「删掉 `[[bin]]` 必改 Cargo.toml → `source_is_current` 判过期 → 走构建路径被预检拦截」保证，代码注释写明该推理 | pie.rs `preflight_run_target` 定义 + `launch_instance` 内 8 行挂接；测试 `a_preflight_without_metadata_lets_the_build_speak`（降级路径） |
| 2 | CLI `jd run/build --config` 解析后 | `crates/jackdaw_cli/src/lib.rs` `resolve_run_config`：`read_run_manifest` → `by_name`（未知 label 列出全部可用名，空清单时说 `jackdaw.toml lists no runs`）→ `target.validate()`（schema 形状，先于任何 cargo 调用）→ `shim_spec_for_project` → `CargoMeta::load` + `check_run_target`（metadata 失败降级）。`cmd_run`/`cmd_build` 共用 | 测试：`an_unknown_label_lists_the_runs_the_manifest_has`、`an_invalid_target_reports_its_shape_before_resolving_anything`、`a_missing_manifest_names_the_file` |
| 3 | `jd doctor` | 同文件 `report_run_targets(root, package.name)`，在 plugin 节后（runtime wiring 节之后）：逐带 target 的 `[[run]]` —— validate 形状 `[fail]`；`check_run_target` 存在性 `[ ok ]`（`run `Server`: bin `server` present[, profile `release`]`）/ `[fail]` + fix 行；profile 按 §D6-3：`dev`/`release` 或根 Cargo.toml `[profile.*]` 已声明 → ok，否则 `[warn]` 非阻断。`declared_profiles`/`profile_is_available` 纯函数在 run_manifest.rs | 测试：`declared_profiles_read_from_the_manifests_profile_tables`、`a_profile_is_available_when_builtin_or_declared`（doctor 的逐行输出本身无 headless 断言，见 concerns） |

### prebuild-validate 修复（任务 1 QA ⚪2）

`prebuild_play_target` 现在对首个 run 两级把关：**(a)** 构建/入键之前先 `target.validate()`（此前无效 target——如 bin+example 同写——会以降级语义白构建一次、存入 launch 永远拒绝的死键）；失败 → `BuildStatus::Blocked { reason }`（prebuild 既有的失败通道），不建不入键。**(b)** spec 解析成功后做与 launch 同款的 `preflight_run_target` 存在性预检，失败同样 Blocked。测试 `an_invalid_first_run_target_blocks_instead_of_building` 断言：builds 为空、Blocked reason 含 "both"、attempted 置位。

## 3. `jd run/build --config`

- `crates/jd/src/main.rs`：SPECS 的 `run`/`build` `values` 加 `--config`，usage 字符串与 `print_usage` 两行同步（`check_options` 对缺值 `--config` 报 "needs a value"、对不认识它的命令报 unknown option——已有机制，新测试钉住）。
- `jackdaw_cli`：`parse_config_arg`（照 `parse_project_arg` 式）；**顺带修了一个真 bug**：`parse_project_arg` 原会把 `--config Server` 的值 `Server` 当裸位置参数读成项目路径，现跳过 `--config` 的值（测试 `a_config_label_is_not_read_as_a_project_path`）。
- `cmd_run --config`：构建该 run 的 target（`build_project_binary_with_load` 透传）后**直启刚构建的二进制**——`prepare_game_command` + run 的 cwd（相对路径按项目根 join，镜像 `spawn_instance`）+ env + args，前台继承 stdio；**无 `--config` 路径逐字节保持现行为**（裸 `cargo run`，构建经 `build_project(root, None)` 命令不变）。
- `cmd_build --config`：构建该 target；扩展项目 + `--config` 明确报错（run target 选的是游戏二进制）。
- `build_project` 签名改为 `Result<PathBuf, ExitCode>`（返回产物路径供 `jd run --config` 启动），extension 分支返回 dylib 路径，行为不变。
- `RunManifest`（CLI 读取器）新增 `env/args/cwd` 三字段 + `RunTargetSpec::cargo_target()` 转换（CLI 侧的唯二转换点之一，镜像编辑器 `src/run_config.rs::cargo_target`）；锁步测试同步断言 Server run 的 env/args/cwd（与 pie_protocol 侧孪生测试同字段）。

## 4. Play 下拉 target 徽标（§D4）

`src/pie_menu.rs`：`RowSpec.badge: Option<String>`；`target_badge(run)` 经 `run_config::cargo_target` → `CargoTarget::named()` 生成 `bin:server` / `example:split_screen`——**与构建同源**（同一 `named()` 先序），徽标不可能显示与实际构建不同的 target；无 target 行零改动。渲染为行尾 `TEXT_SIZE_XS` + `TEXT_MUTED_COLOR` 小字（全仓暗色注记的既有 token 组合）。headless 断言：`a_targeted_row_carries_a_dim_badge_after_its_label`（badge 文本、字号、颜色 + label 共存）、`a_row_without_a_target_renders_no_badge`、纯函数 `the_badge_names_the_cargo_target_kind`。

## 5. 顺带重构：bin/example 先序统一（回应任务 1 QA ⚪3）

`binary.rs` 新增 `pub enum TargetKind`（`as_str`/`Display`）与 `CargoTarget::named() -> Option<(TargetKind, &str)>`（bin 优先、空白视作缺失——原 `cargo_target_args` 与 `WantedArtifact::from` 各自内联的同一先序）。现在四处消费者（argv 构造、产物过滤、存在性预检、Play 徽标）全部走 `named()`，先序只剩一份，测试 `named_resolves_one_target_with_bin_first_and_blank_absent` 直接钉住。`cargo_target_args`/`WantedArtifact::from` 的既有测试未动、全绿（行为等价重构）。

## 6. 新增测试（23 个，全部进 integration 档）

binary.rs 1 / cargo_meta.rs 6 / run_manifest.rs 4 / jackdaw_cli 5 / jd main.rs 2（bin crate 单测，不进 fast 的 `--lib` 档，integration 档计入）/ pie.rs 2 / pie_menu.rs 3。计数与门增量吻合（2750→2771 fast、4879→4902 integration）。

## 7. 与方案偏差点（4）

1. **CLI 读取器含 env/args/cwd**：方案 D3-4 说极简读取器「只解析 name+target」，但 D5 要求 `jd run --config` 带走 run 的 env/args/cwd——两处矛盾，按 D5 落地（`jd run` 不带走这些就无法「与 Play 下拉对齐」）。锁步测试同步扩展，两侧字段名仍锁死。
2. **launch 预检位于暖缓存检查之后**（D6-1 只说「构建前」）：暖 Play 不付出 metadata 延迟；「删 bin 后仍命中旧缓存」的场景由 Cargo.toml mtime 过期机制兜住（见 §2 表格第 1 行推理）。若 QA 期望点行即校验（含暖路径），前移是一行改动，代价是每次 Play 多一次 metadata。
3. **doctor 的 profile 检查按方案字面「仅 dev/release + [profile.*]」**：cargo 实际还内建 `test`/`bench` profile，名字用到它们会得到一条 [warn]（非阻断、不影响构建），按方案原文执行未放宽。
4. **`--config` 选中无 target 的 run（如默认 Play）**：按「选整条 run」语义走 package 默认构建 + 直启，不报错——与下拉行为一致，非异常路径。

## 8. 未验证项 / concerns（移交 QA）

1. `jd run --config` 的真机端到端（构建→直启→退出码）与 `--config` 选中带 env/args/cwd run 的进程环境，属任务 3 heavy smoke 的自然扩展点；本轮以单测钉住解析/校验/参数路径，构建路径复用 `build_project_binary_with_load` 既有测试。
2. doctor 的逐行 `[ ok ]/[fail]/[warn]` 输出没有 headless 快照断言（`report_run_targets` 打印到 stdout，无返回值可断言；分支逻辑由其调用的纯函数测试覆盖）。QA 复验时跑 `jd doctor --project <带 target 的 fixture>` 目视即可。
3. 编辑器 launch 侧预检的「点行即出状态栏错误」为 5 行接线（与 prebuild 同款 helper），headless 单测覆盖降级路径与纯函数；完整世界模式断言需要可解析 spec 的真实工程，留给 QA 人工项（清单 §5 已列）。
4. `jd run --config` 前台运行、继承 stdio——这是 CLI 语义（用户自己的终端）；不像编辑器有 stderr tail/超时。若将来要无人值守跑法（如 CI 冒烟）需另加。
