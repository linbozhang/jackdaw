# 功能 #3 任务 1 报告：schema + 构建透传 + PIE 缓存分键

> 多 Agent 开发循环 · 程序（Rust/Bevy 工程师）· 2026-10-22
> 分支 `loop/run-targets`，基于 main `eb45a3a3`，提交 `899a8f27`
> （`Add CargoTarget run config with build passthrough and PIE cache keying`，7 files，+1053/-50）

## 实现内容（对照方案任务 1 清单）

1. **pie_protocol schema**（`crates/jackdaw_pie_protocol/src/manifest.rs`）
   - `RunTarget { package?, bin?, example?, features: Vec<String>, profile? }`，全字段 `#[serde(default)]`，derive `Deserialize/Clone/Debug/Default/PartialEq/Eq`；
   - `RunConfig` 增 `#[serde(default)] target: Option<RunTarget>`；改写过时注释（原「Every run launches the same game binary」）；
   - `RunTarget::validate()`：bin/example 二选一 + 名字非空白，可读错误文案（不用 serde untagged，按 D1-4）。
2. **project_build 构建透传**（`crates/jackdaw_project_build/src/binary.rs`）
   - `CargoTarget`（Hash/Eq/Clone/Debug/Default，无 serde）+ `package_or()`（package 覆盖 `-p`）；
   - `cargo_target_args(Option<&CargoTarget>) -> Vec<String>` 纯函数（`--bin`/`--example`/`--features` 逗号连接/`--profile`）；
   - `build_project_binary_with_load` 增 `target: Option<&CargoTarget>` 参数；命令拼接 `cargo build -p <覆盖或spec包> [target片段] --target-dir … --message-format=json`；**target=None 时 argv 与改前逐字节相同**（`cargo_target_args(None)=[]`、package=spec 包名，`build_project_binary` 三参包装不改签名，既有调用零改动）；
   - `executable_for_package` 收紧：新增 `WantedArtifact::{AnyBinary, CargoTarget{name, example}}` 过滤——带 bin/example 的构建同时匹配 JSON `target.name` + `target.kind`（`"bin"`/`"example"`），产物路径仍只取 cargo JSON `executable` 字段，零拼路径；缺 `target` 表的记录（旧 cargo/旧 fixture）在 AnyBinary 路径照旧采纳。
3. **`run_manifest.rs`（新）**：jd 用极简 `[[run]]` 读取器（`RunManifest/RunEntry/RunTargetSpec`，`parse`/`by_name`/`label` 默认 "Play"，`RunTargetSpec::validate` 与协议侧同文案），`lib.rs` 导出 `run_manifest`、`CargoTarget`、`cargo_target_args`。
4. **编辑器转换点**（`src/run_config.rs`）：`pub(crate) fn cargo_target(&RunConfig) -> Option<CargoTarget>` 逐字段一对一（方案 D3-4 的唯一合法转换点）；`src/project_build.rs` 转发层补导出。
5. **PIE 缓存分键**（`src/pie.rs`）
   - `builds: HashMap<BuildKey, BuildState>`，`type BuildKey = (PathBuf, Option<CargoTarget>)`；`fn build_key(root, run)` 纯函数；
   - 取键点：`launch_instance`（缓存命中/remove/挂 pending/新插 4 处）、`prebuild_play_target`（首个 run 的 target，通常 None）、`spawn_project_build`（Rebuild/auto-build 固定默认键）、`watch_project_source_for_edit`（默认键查找，方案未列但同语义必需）、`poll_builds`（键元组取 `.0` 作项目名）；`handle_reload` 复用 `launch_instance` 天然携带各自 target，零改动；
   - `spawn_game_build` 增 `target: Option<CargoTarget>` 参数透传给 `build_project_binary_with_load`；
   - `launch_instance` 入口对 `run.target` 做 `validate()`，失败 `notify_error`（镜像 save_before_play 失败路径）；
   - `is_pending/is_launching/launch_failed/handle_stop` 按 values()/clear() 遍历，多键天然泛化，零改动。

## 测试（新增 27 个，全过）

- **binary.rs（8 新 + 1 改）**：cargo_target_args None=空片段/bin 组合/example/矛盾与空白名降级；package_or 覆盖与回退；CargoTarget Hash/Eq 分键性质（同名 bin vs example vs 加 feature 互不撞）；executable_for_package 的 example/bin 名+kind 过滤（含 sibling bin 不采纳、kind 不符不采纳、AnyBinary 兼容无 target 表记录）。
- **manifest.rs（7 新）**：target 子表逐字段解析、缺省 None、缺字段默认、validate 三种拒绝 + 空白名 + 恰一合法；**旧文件快照**（LOCKSTEP_FIXTURE 含 plugin/package/[jackdaw] pins/多 run/env/args/cwd/mode，逐字段断言 = 「旧 TOML 解析不变」守卫）。
- **run_manifest.rs（5 新）**：锁步另一半（同一 LOCKSTEP_FIXTURE 字面量逐项相等）+ label 默认/空 runs/坏 TOML/validate 同形。
- **run_config.rs（2 新）**：无 target → None；有 target 逐字段转换。
- **pie.rs（5 新）**：build_key 三性质（无 target 共键、有 target 独键、同 root 异 target 不撞/同 target 命中）；prebuild 世界模式两例（首个 run 带 target 时越过暖默认键继续尝试、无 target 时暖默认键早退）。

**锁步测试实现方式**：两 crate 无依赖关系（CLI 不得依赖 pie_protocol），故同一 TOML 字面量在两侧各放一份（`LOCKSTEP_FIXTURE`，注释互指），两侧各自断言相同的 name/target 期望值——任一侧字段名漂移即本侧变红。

## 各门退出码

| 门 | 结果 | 证据 |
|---|---|---|
| `cargo fmt --all -- --check` | 0（PASS） | 迭代中一次应用 fmt 后复跑通过；xtask fast 链内该项亦过 |
| `cargo clippy --workspace -- -D warnings` | 0（PASS） | `GATE_CLIPPY_EXIT=0`；另跑过更严的 `--all-targets --features dylib -D warnings` 亦 0 |
| `cargo xtask fast` | 0（PASS） | Summary: 2750 tests run, 2750 passed, 2 skipped（链条含 fmt/core_deps/git_deps/clippy/nextest --lib） |
| `cargo xtask integration` | 0（PASS） | Summary: 4879 tests run, 4879 passed, 3 skipped。**注意**：第一次尝试在构建阶段失败（`failed to remove target\debug\jackdaw.exe`——残留编辑器进程锁文件，环境问题非代码问题），`taskkill` 杀掉 PID 114948 后重跑全绿 |

既有套回归结论：fast 2750/2750、integration 4879/4879 全过，零回归。既有测试仅两类机械适配（pie.rs 测试内 builds.insert 键改元组；binary.rs 产物过滤测试加 `WantedArtifact` 参数），语义断言未动。

## 与方案偏差点

1. **prebuild 暖缓存检查前移**：原实现先 `shim_spec_for_project`（失败报 Blocked）后查缓存；现改为先查 `(root, first_target)` 暖键再解析 spec。语义等价（能插入 builds 的键必然解析成功过），且使「首个 run 带 target 时预构建带 target 参数」可在 headless 世界模式下断言（不存在路径的 root 下，越过暖默认键=继续尝试到 Blocked）。方案 D7-4 允许「把 spawn 决策抽纯函数」，取了等效的前移方案。
2. **`watch_project_source_for_edit` 也改了取键**：方案「四处取键点」未列它，但它读 `builds.get(&root)` 必须跟随分键（auto-build 监视的是默认产物，用 `(root, None)`）。属分键的必要伴随改动，非越界。
3. **launch 前 validate（notify_error）做了纯校验版**：方案任务 1 写有「launch 前预校验」，但基于 cargo metadata 的存在性预检（列可用 bins/examples）依赖任务 2 的 CargoMeta 访问器，未做。本任务只接了 schema 级 `validate()`（互斥 + 非空），metadata 存在性预检留给任务 2。
4. **`no_binary_message` 改为接收包名**（原来收 `&ShimSpec`）：package 覆盖时错误信息要指对包。私有函数签名调整，非行为变更。

## 遗留 / Concerns（给任务 2/3 与 QA）

- **（未验证）example target + `bevy/dynamic_linking` 的 dll 路径**：`apply_dynamic_library_path` 用 `binary.parent()/deps` 推导 deps 目录，example 产物在 `examples/` 子目录下，推导会 miss（函数静默返回，不加 PATH）。默认静态链接 bevy 的项目不受影响（exe 自包含）；方案未涉及此点，建议任务 3 heavy smoke 或 QA 人工项覆盖一次 dynamic_linking 场景，或后续把 deps 推导改为向上查找。
- **（未验证）不响应 SCHEMA_FLAG 的 target 的提取延迟**：`run_binary_extractor` 对不认识旗标的 example/bin（无 JackdawPlugin）会跑到 120s 超时才放弃（非致命，schema=None 后照常启动）。方案 D2-4/风险 7 已声明「失败非致命、无需处理」，但延迟面未提；任务 3 的 schema_echo fixture（立即退出）不受影响。
- **cargo JSON `target.kind` 取值**：按方案脚注以字面量 JSON 单测钉住（`"bin"`/`"example"`），未跑真机 example 构建核对——任务 3 heavy smoke 的路径断言（`examples/` 目录段）即为实机核对点。
- 任务 2 待接：`jd run/build --config`、doctor 预检（含 CargoMeta bin/example 访问器与编辑器/CLI 两处 metadata 存在性预检）、SPECS/usage；任务 3 待接：下拉徽标、heavy smoke、文档、盘点表。
