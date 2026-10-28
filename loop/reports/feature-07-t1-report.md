# 功能 #7 任务 1 报告：`jd export` + staging + `jd run --config` 资产根修复

> **⚠️ 修订记录（2026-10-24 修复回流第 1/5 轮）**
> - 初版结论（下文「门禁 4/4 绿 / 新增 16 测试」）随 QA FAIL **部分作废**：QA 报告 `loop/reports/feature-07-t1-qa.md` 实证 `staging_is_unsafe` 护栏可被相对 `--out .`/`--out ..`、cwd 重叠相对名、verbatim `\\?\` 前缀绕过（`remove_dir_all` 递归删目录内容），另 🟡 反向包含（`--out <root>\assets\dist` 自嵌套拷贝）未防护。
> - 修复提交：**c907ce00** `Harden export staging path guards`（2 files, +293/−40）。修法（按 QA §2.1 建议）：
>   1. `normalize_staging_dir`：进护栏前 `std::path::absolute` + `dunce::simplified`（剥 verbatim `\\?\` 前缀），规范化后残留 `..`/`.` 组件即拒（`InvalidStagingPath`）；**staging 后续 clear/copy/报告全部使用规范化路径**（判的即写的）；
>   2. **相对 `--out` 双层拒绝**：CLI `validate_export_out`（构建前快速失败，文案要求绝对路径）+ 库层 `RelativeStagingDir`（纵深，保护非 CLI 调用方）；
>   3. **反向包含**：`staging_hazard` 补 `dir.starts_with(source)` → `StagingInsideSource`（源内嵌套拒绝，assets 树零污染）。
>   - 旧 `staging_is_unsafe` 字面比较已删除，替换为 `staging_hazard`（Root/ContainsSource/InsideSource 三类）+ `normalize_staging_dir`。
> - 四类绕过新测试（全部 PASS，见 `loop/t1r_unittest.log` / `t1r_xtask_fast.log`）：
>   `a_relative_staging_directory_is_refused_before_anything_is_touched`（`.`/`..`/`dist`/`assets`，附 fixture 完好断言）、`a_verbatim_prefix_cannot_smuggle_a_directory_past_the_guard`（verbatim 工程根 + verbatim 盘根）、`verbatim_prefixes_are_stripped_and_hidden_dots_are_still_detected`（剥前缀 + 隐藏 `..` 检出，均 cfg(windows)）、`a_staging_directory_inside_the_assets_tree_is_refused`（源内嵌套 + 无污染断言）；跨盘不回归：`a_drive_root_is_a_hazard_across_drives`（cfg(windows)）、`a_filesystem_root_is_always_a_staging_hazard`（平台无关重写）；CLI：`an_out_directory_must_be_absolute`。
> - 修复轮门禁（独立行探针+日志）：fmt=FMT_OK(`loop/t1r_fmt.log`)；clippy=CLIPPY_OK exit 0(`t1r_clippy.log`)；xtask fast=XTASK_FAST_OK exit 0，**2839 passed**/2 skipped(`t1r_xtask_fast.log`，较初版 +6 恰为本轮新测试)；受影响 crate（jackdaw_project_build/jackdaw_cli_internal/jd）lib 测试 **247/247**(`t1r_unittest.log`)。**integration 未全量重跑**：本轮改动仅 export 护栏纯函数与 CLI 校验函数及其测试，`tests/` 集成二进制零消费（rg 证实仅 src/terrain/export.rs 同名无关模块），初版全量 integration 4970 绿结论不受影响；如 QA 需要可重跑全量。
> - 下文初版内容保留作历史记录，其中「实现要点」的护栏描述以本节为准。

- 分支 `loop/build-export`（自 main 46d7efa8 切出）
- 提交：**b2b30092** `Add jd export with staged dist and fix run-config asset root`（5 files, +897/−21）
- 日期：2026-10-22 · 执行：程序 agent（Rust/Bevy 工程师）

## 改动清单

| 文件 | 改动 |
|---|---|
| `crates/jackdaw_project_build/src/export.rs`（新） | `ExportPlan` / `plan_export` / `stage_export` / `ExportReport` / `ExportError` / `dynamic_linking_rejection` / `reveal_in_file_manager`；8 个单测 |
| `crates/jackdaw_project_build/src/binary.rs` | `ProjectBinaryBuild.dylib_artifacts` 字段 + `dylib_artifact_in(line)` 纯函数（cargo JSON `target.kind` 含 `dylib` 检测）+ 构建流收集 + 1 个单测 |
| `crates/jackdaw_project_build/src/lib.rs` | `pub mod export;` + `dylib_artifact_in` re-export |
| `crates/jackdaw_cli/src/lib.rs` | `cmd_export`（`--config`/`--profile`/`--out`）；`configured_game_command` 提取并补 `BEVY_ASSET_ROOT`（**bug 修复**）；`build_project` 返回 `BuildOutcome`（binary+dylib 检测）；`export_profile` / `validate_export_profile` / `parse_profile_arg` / `parse_out_arg`；`parse_project_arg` 跳过新旗标值；6 个新单测 |
| `crates/jd/src/main.rs` | SPECS 增 `export`（values: `--project/-p/--config/--profile/--out`）+ dispatch + `print_usage` 一行 + 1 个新单测 |

## 门禁（独立行探针 + 日志文件）

| 门 | 探针结果 | 进程退出码 | 日志 |
|---|---|---|---|
| `cargo check -p jd -p jackdaw_cli_internal -p jackdaw` | CHECK_OK | 0 | `loop/t1_check.log` |
| 三 crate lib 单测 | TEST_OK | 0 | `loop/t1_unittest.log`（240/240） |
| `cargo fmt --all -- --check` | FMT_OK | 0 | `loop/t1_fmt.log` |
| `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | CLIPPY_OK | 0 | `loop/t1_clippy.log` |
| `cargo xtask fast` | XTASK_FAST_OK | 0 | `loop/t1_xtask_fast.log`（2833 passed, 2 skipped） |
| `cargo xtask integration` | XTASK_INTEGRATION_OK | 0 | `loop/t1_xtask_integration.log`（4970 passed, 3 skipped） |
| `jd export --help` | usage 输出正确 | 0 | （终端验证，见上） |

新增测试 **16 个**（export.rs 8 + binary.rs 1 + jackdaw_cli 6 + jd 1），全部通过。

## 实现要点

- **staging 布局**：`<root>/.jackdaw/dist/<profile>/{<name>.exe, assets/**}`；`--out` 只换目录不换布局。`stage_export` 先 assets 后 exe（exe 拷贝成功才算成功）；dist 已存在时**先清空再全量拷**（re-export 是替换不是合并，陈旧资产不残留）；io 错误消息含源与目的双路径。
- **防呆（超方案部分）**：staging 目录含构建源（工程根/构建目录/assets 本身）或**文件系统根**（`/`、`C:\`——跨盘符时 `starts_with` 抓不住，单测实跑时曾触发 `remove_dir_all("/")`，已改为 `parent().is_none()` 纯函数防护 `staging_is_unsafe`）时拒绝。测试暴露该漏洞后已修复并加纯函数测试钉死。
- **dynamic_linking 防呆（方案 D6）**：构建 JSON 流中 `target.kind` 含 `"dylib"` 的 compiler-artifact（如 `bevy_dylib`）→ 收集 crate 名 → `cmd_export` 拒绝导出，文案指明去掉 `dynamic_linking` feature；`lib`/`proc-macro`/`bin` kind 不误报（单测钉住）。
- **`jd run --config` 资产根修复（D3-4 / pie.rs:2021 对齐）**：`configured_game_command` 设 `BEVY_ASSET_ROOT=<run cwd>`，且 `.envs(&entry.env)` 在其后——**用户 env 赢**（与编辑器 `spawn_instance` 现有顺序相反，按方案 D6-7 裁定实现并加单测钉顺序）。无 `--config` 路径命令串逐字节不变（既有回归锚点测试续命，xtask fast 全绿佐证）。
- **导出成功自动开目录（主控裁定①）**：`reveal_in_file_manager`（explorer/open/xdg-open）放共享 crate `jackdaw_project_build::export`，CLI 成功后调用（失败仅警告），任务 2 编辑器入口可复用。
- **profile 决策**：`--profile` 旗标 > `--config` 选中 run 的 `target.profile` > 默认 `release`；合法性复用 `profile_is_available` + `declared_profiles`，未知 profile 报错并列出可用名。
- **扩展项目拒绝**：`bootstrap::project_needs_sdk` → `jd export` 直接报错（扩展无游戏可导）。

## 与方案偏差

1. `plan_export` 签名加了 `binary: &Path` 参数（方案的 `exe_source` 本就来自构建结果，纯函数化更清晰）；`stage_export` 返回 `Result<ExportReport, ExportError>`（方案即如此）。
2. 新增方案未列的防呆：文件系统根 / 源包含 staging 目录拒绝（测试实跑暴露真实删盘风险，属必要加固）。
3. `reveal_in_file_manager` 未改 `src/project_window.rs::open_with_desktop`（那是编辑器 crate，任务 1 不动编辑器侧；任务 2 接编辑器入口时可委托共享函数）。

## 未做（任务 2 范围，未越界）

`src/game_export.rs` operator、`file_menu_rows` 菜单行、BuildStatus 进度复用、`tests/export.rs` heavy smoke、book/README 文档、xtask SDK_BINARIES 增项——均未触碰（`rg game_export|file_menu_rows|BuildStatus` 于改动文件中零命中）；`loop/` 目录经 `.git/info/exclude` 不入库。

## Concerns（供 QA/任务 2 参考）

1. dylib 检测中 `cdylib` kind 未一并拒绝（方案只点名 `dylib`；游戏依赖图出现 cdylib 非 bevy dynamic_linking 信号）——heavy 实测若发现需要可再收紧。
2. `stage_export` 的 `remove_dir_all` 在 Windows 对被占用文件（Explorer 预览锁）报错路径已含双路径，但未做重试——真机验证时留意。
3. 首次 release 构建时长（20-40 分钟级）属任务 2 heavy/真机环节，本任务未跑真实 release 构建（按指令）。
