# 功能 #3 任务 2 QA 验收报告：`jd --config` + 预检 + 徽标

> 多 Agent 开发循环 · QA（独立第三方）· 2026-10-22
> 验收对象：分支 `loop/run-targets`，提交 `751bb6b6`（基于 main `21c7dd1e`，8 files，+1096/-71）
> 需求口径：`loop/plans/feature-03-run-targets.md` 任务 2 + §D4/§D5/§D6-1；上轮 QA（t1）盯住项：三处 metadata 预检落地、prebuild 先 validate
> 程序报告：`loop/reports/feature-03-t2-report.md`（4 偏差 + 4 concerns）

## 结论

**VERDICT: PASS**。四门全 0（计数与程序报告逐字一致），规格逐条 ✅（含两项实机目验），偏差 4 项全部核实为正确取舍，无 🔴/🟡，⚪ 4 条不阻塞。

## 1. 确定性门（本机实测）

| 门 | 命令 | 退出码 | 计数 |
|---|---|---|---|
| fmt | `cargo fmt --all -- --check` | 0 | — |
| clippy | `cargo clippy --workspace -- -D warnings` | 0 | 日志仅 6 条既有 build-script `linker_messages` 警告（该 lint 明示忽略 `-D warnings`，与 t1 记录同类，非本 diff 引入） |
| fast | `cargo xtask fast` | 0 | 2771 run / 2771 passed / 2 skipped |
| integration | `cargo xtask integration` | 0 | 4902 run / 4902 passed / 3 skipped |

计数与程序报告逐字一致；本次无进程锁问题。新增 `#[test]` 我在 diff 里独立数得 **23**（binary 1 / cargo_meta 6 / run_manifest 4 / jackdaw_cli 5 / jd main 2 / pie 2 / pie_menu 3），与门增量吻合（fast 2750→2771 = +21，jd 的 2 个只进 integration；integration 4879→4902 = +23）。

## 2. 规格符合性（逐条独立核实）

### 2.1 三处 metadata 预检落地（t1 盯住项，§D6-1）— ✅

预检核心 `cargo_meta::check_run_target`（cargo_meta.rs）：经 `CargoTarget::package_or` 解析生效包（与构建命令同源）→ `--no-deps` metadata 比对 bin/example 名（`CargoMeta::load` 确认跑 `cargo metadata --no-deps`，`packages()` 只含 workspace 成员）；错误措辞镜像 `ResolveError`（未知包列成员、未知 target 列可用名、无该类 target 明说）。6 个单测覆盖双拼写/包覆盖重定向/三分支错误文案/无名单不检查。

| 挂接点 | 位置与顺序（我读代码核实） | 降级 | 测试 |
|---|---|---|---|
| 编辑器 launch | pie.rs:673-685，spec 解析后、pending join/发起构建前；失败 `notify_error`（镜像 save_before_play） | metadata 失败放行（`preflight_run_target` None→Ok） | `a_preflight_without_metadata_lets_the_build_speak`（真实空目录） |
| CLI | `resolve_run_config`：read → by_name 列名 → `validate()`（先于任何 cargo 调用）→ spec → metadata 预检；`cmd_run`/`cmd_build` 共用 | metadata 失败放行 | 3 测试 + 我实机复验（见 §2.6） |
| doctor | lib.rs:351 `report_run_targets`，在 runtime wiring（:296）与 plugin 节之后；validate 形状 `[fail]`、存在性 `[ ok ]/[fail]`+fix 行、profile `[warn]` 非阻断 | metadata 失败跳过存在性（由上面 package 行报过） | 纯函数测试 + 我实机目验（见 §2.6） |

### 2.2 prebuild-先-validate 修复（t1 QA ⚪2）— ✅

pie.rs:1354-1367：构建/入键之前对首个 run `target.validate()`，失败 → `BuildStatus::Blocked`、不入键；:1409-1417 spec 解析后再做同款存在性预检，同样 Blocked。测试 `an_invalid_first_run_target_blocks_instead_of_building` 断言 `builds.is_empty()` + Blocked reason 含 "both" + attempted 置位——死键场景确实堵死。

### 2.3 `jd run/build --config` 与裸路径不变 — ✅

- SPECS（jd/src/main.rs）：run/build `values` 加 `--config`，usage 与 `print_usage` 两行同步；`check_options` 机制测试 2 条（缺值报 "needs a value"、setup 拒绝 unknown option）。
- **裸路径逐字节等价（我 diff 两侧核对）**：`cmd_run` 无 `--config` 分支的 `rust_env_command("cargo").arg("run").current_dir(&root).status()` 与 main 构造逐字节相同；`build_project(&root, None)` 内部走 `build_project_binary_with_load(…, None, Foreground, …)`，而旧 3 参 `build_project_binary`（binary.rs:218-223）恰是该调用的包装——机制上等价，非仅目测。`cmd_build`/`cmd_run` 控制流改 `Result<PathBuf, ExitCode>` 后裸路径语义逐分支等价，输出文案不变。
- `--config` 分支：构建后 `prepare_game_command` + cwd（`root.join`，与 `spawn_instance` pie.rs:2011-2014 同式）+ env + args 直启；镜像成立（spawn_instance 独有的 `JACKDAW_PIE`/windowless 正确缺席；`BEVY_ASSET_ROOT=cwd` 未显式设，裸进程 cwd 即默认资产根，实际等价，heavy smoke 顺带看一眼即可）。`without_console_window` 仅在非终端加 flag，前台终端运行不受影响。
- 扩展项目 + `--config`：`build_project` 明确报错（run target 选的是游戏二进制）。

### 2.4 Play 下拉徽标（§D4）— ✅

`target_badge`（pie_menu.rs）→ `run_config::cargo_target` → `CargoTarget::named()`——与 `build_key`/argv 构造同源，徽标不可能与实际构建的 target 不一致。无 target 行 badge=None 不 spawn。headless 断言 3 条核实：`a_targeted_row_carries_a_dim_badge_after_its_label`（badge 文本+TEXT_SIZE_XS+TEXT_MUTED_COLOR+label 共存，查世界实际组件）、`a_row_without_a_target_renders_no_badge`（labels 精确等于 `["Play"]`，非子串弱断言）、`the_badge_names_the_cargo_target_kind`（bin:/example:/None 三态）。

### 2.5 顺带修复核验：`parse_project_arg` 误读 label — ✅（修复正确；「既有 bug」定性见 ⚪1）

`git show main` 核实：main 的 `parse_project_arg` 无 `--config` 跳过，且 main 的 SPECS 里 run/build/doctor `values` 仅 `--project/-p`——`--config` 在 main 被 `check_options` 整体拒绝，**误读路径在 main 上不可达**（不是已出厂的 bug，是本提交引入旗标时同步消除的隐患）。现修复跳过 `--config` 的值，测试 `a_config_label_is_not_read_as_a_project_path` 钉住，行为正确。

### 2.6 实机复验（本 QA 新增证据，gitignore 的 target 下搭临时项目，跑完已删）

`jd doctor --project <临时 bsn_game 副本 + 带 target 的 jackdaw.toml>` 实测输出：

```
  [ ok ] run `Good`: bin `bsn_scene_game` present
  [fail] run `Bad`: package `bsn_scene_game` declares no examples, so `nope` cannot be one
         fix: name one of the targets the package declares, or add it in Cargo.toml
  [ ok ] run `Prof`: bin `bsn_scene_game` present, profile `custom-fast`
  [warn] run `Prof`: profile `custom-fast` is neither dev, release, nor a [profile.custom-fast] Cargo.toml declares; ...
```

无 target 的 `Play` 行正确跳过；`[fail]` 正确拉低 doctor 退出码。`jd run/build --config Nope` 实测：报 `` `Nope` is not a run in jackdaw.toml (found: Play, Good, Bad, Prof) ``、`--config Bad` 被存在性预检在构建前拦截，run/build 退出码均非 0。—— 程序报告 concern 2（doctor 逐行无 headless 断言）由本节实测补足。

### 2.7 无任务 3 越界 — ✅

diff 仅 8 个源码文件（jackdaw_cli / binary.rs / cargo_meta.rs / pb lib.rs / run_manifest.rs / jd main.rs / pie.rs / pie_menu.rs）。无 fixtures/schema_echo、无 xtask SDK_BINARIES、无 book/README/roadmap 盘点表改动。工作树干净、HEAD=751bb6b6。

## 3. 偏差抽验（4 项全查）

- **① CLI 读取器含 env/args/cwd（D3-4 vs D5 矛盾）— 取舍正确**。两节原文确实矛盾：D3-4 说极简读取器「只解析 name+target 子键」，D5 要求 `jd run --config`「prepare_game_command + run.env/args/cwd，镜像 spawn_instance」。D5 是行为规格（不带 env/args/cwd 就无法「与 Play 下拉对齐」），按 D5 落地正确。**锁步测试同步**：两侧 LOCKSTEP_FIXTURE 均含 Server 的 env SEED/args/cwd（protocol manifest.rs:273-275 断言 :302-304；CLI run_manifest.rs 新增同字段断言），字段名仍被两侧钉死。
- **② launch 预检在暖缓存检查后 — 兜底成立（常见路径），边缘有既有盲区**。暖 Play 在 pie.rs:662 早退，零 metadata 开销 ✅。mtime 兜底：`source_unchanged_since`（pie.rs:774-787）递归监视根 `src/` + 根 `Cargo.toml`——删根包声明的 `[[bin]]`/`[[example]]` 必改根 Cargo.toml → 判过期 → 走构建路径被预检拦截，兜底真实成立。残余盲区：package 覆盖的**成员** Cargo.toml 不在监视集（方案风险 4 既有文档化盲区）；删除目标文件不抬 newest-mtime（影响一切 Play 的既有通病，非 target 特有）。均非本 diff 引入或放大，见 ⚪2 注释措辞。
- **③ profile 检查按方案字面（仅 dev/release + `[profile.*]`）**：cargo 内建 `test`/`bench` 会得一条 `[warn]`（非阻断、不影响构建），方案原文如此，按字面执行可接受。
- **④ `--config` 选中无 target run 走默认构建+直启不报错**：与「选整条 run」语义及下拉行为一致；主控「无 target=现行为」裁定约束的是 manifest/构建路径（`target=None` → 默认构建，已保持），非 `--config` 入口。一致。

## 4. 代码质量

- **`CargoTarget::named()` 四处统一（t1 ⚪3 收口）— ✅ 无残留**：`cargo_target_args`（binary.rs:181-186）、`WantedArtifact::from`（:610-622）、`check_run_target`（cargo_meta.rs）、`target_badge`（pie_menu.rs）全部经 `named()`；rg 全仓核实 `bin.as_deref…filter` 式先序仅剩 `named()` 定义处一处（:153-155）。测试 `named_resolves_one_target_with_bin_first_and_blank_absent` 直接钉住先序。
- doctor/CLI 输出沿用既有 `println!` 风格，clippy `-D warnings` 全绿；diff 新增 `.unwrap()` 均在 `#[cfg(test)]`。
- 测试断言质量：argv/解析/徽标均精确 Vec/字段相等（无 badge 行断言 labels==["Play"]），错误文案 contains 属合理。
- `RunEntry` 增 env/args/cwd 全 `#[serde(default)]`，旧 TOML 解析不受影响（`a_run_without_a_target_converts_to_no_cargo_target` 钉住空缺省）。

### 质量发现（⚪ 均不阻塞）

1. **⚪[程序报告] 「顺带修了一个真 bug」定性不准确**：main 上 `--config` 被 `check_options` 整体拒绝（SPECS values 仅 `--project/-p`），误读路径不可达，非已出厂 bug；属本提交引入旗标时同步消除的隐患。修复本身正确且有测试。
2. **⚪[程序] pie.rs:675-678 注释 "a manifest edit that drops the target also marks the cache stale" 对 package 覆盖不精确**：只有根 Cargo.toml 在监视集；成员 Cargo.toml 编辑/删除目标文件两场景暖缓存不会过期（均属方案风险 4 既有文档化盲区，非本 diff 引入）。注释宜收敛为「根 manifest」，或任务 3 文档顺带标注。
3. **⚪[程序] 方案 D5 风险 3 对策点名的「无 `--config` 命令串逐字节回归测试」未落地**：裸路径等价性本 QA 已由 diff + 包装函数（binary.rs:218-223）机制性核实成立，但缺测试锚点，后续重构失去守卫——建议任务 3 顺带把 `cmd_run` 裸命令构造抽纯函数钉住。
4. **⚪[程序] `report_run_targets` Ok 分支的 else "the package's default binary" 为不可达死分支**：validate 通过后 `named()` 必为 Some；防御性写法无行为影响。

## 5. Concerns（移交主控 / 任务 3）

- 程序自报 concerns 1/3/4 属实：`jd run --config` 端到端（构建→直启→退出码、env/args/cwd 进程环境）与编辑器「点行即出状态栏错误」完整世界模式断言，均归任务 3 heavy smoke/人工项；前台继承 stdio 的无人值守跑法暂不需要。concern 2（doctor 逐行输出）已由本 QA 实测补足（§2.6）。
- 任务 3 顺带建议：⚪3 的裸命令回归锚点；heavy smoke 里瞄一眼 `jd run --config` 未显式设 `BEVY_ASSET_ROOT` 的行为（理论上与 spawn_instance 等价，默认资产根=cwd）。
- 偏差③若后续想放宽 `test`/`bench`，一行改动（`profile_is_available` 加两个内建名），非本轮事项。

## 6. 证据索引

- 预检三处：pie.rs:673-685（launch）/ :721-732（preflight_run_target 定义）/ jackdaw_cli lib.rs `resolve_run_config` 全链 / :351 `report_run_targets`；cargo_meta.rs `check_run_target` + `CargoMeta::load`（`--no-deps` :163）。
- prebuild：pie.rs:1354-1367（validate 先行）/ :1409-1417（存在性）→ 1421 才 insert；测试 :2887+。
- 裸路径等价：`git show main:crates/jackdaw_cli/src/lib.rs` cmd_run vs 分支同函数；binary.rs:218-223 包装。
- 实机目验：§2.6（target\qa_tmp 下临时副本，跑毕删除，`git status` 干净）。
- 门与计数：本报告 §1，均本机实测退出码。
