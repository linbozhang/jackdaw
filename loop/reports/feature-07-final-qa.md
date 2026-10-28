# 功能 #7 整体终验（QA）：Play + 打包输出可执行程序

- 分支 `loop/build-export` · 任务 2 提交 **03f4d16d**（基于 main 7c513f64）· diff = 恰 7 文件（README/book/cli/core_extension/game_export(新)/lib/pie），全在计划清单内
- 日期：2026-10-24 · 执行：QA agent（只读验收 + 真机复验）· 日志/截图/脚本归档 `loop/qa-final/`
- **VERDICT: PASS（功能级）**

## 1. 门禁（独立行探针 + 日志，全部亲跑）

| 门 | 结果 | 日志 |
|---|---|---|
| `cargo fmt --all -- --check` | OK | `qa-final/fmt.log` |
| `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | OK | `qa-final/clippy.log` |
| `cargo xtask fast` | **2845 passed / 2 skipped**（与 t2 报告一致，含 6 新单测） | `qa-final/xtask_fast.log` |
| `cargo xtask integration` | **4982 passed / 3 skipped**（heavy 按 SDK_BINARIES 排除） | `qa-final/xtask_integration.log` |
| `cargo doc --locked --workspace --document-private-items --no-deps` | OK | `qa-final/doc.log` |
| doctests（`--features bevy/dynamic_linking`） | 失败集**恰为** {jackdaw_bind, jackdaw_feathers, jackdaw_node_graph}，与 feature-01~06 基线逐项相同（exit 101 同源）→ **非回归** | `qa-final/doctests.log` vs `reports/gate-doctests-finalqa.log` |

## 2. 代码审查（diff 逐文件）

- **operator 规范**：`game.export`（id/label/description 按 CONTRIBUTING；`allows_undo=false` 合理；`is_available`=工程开且无导出在途，菜单置灰而非静默无效）；`file_menu_rows` 走 `op_entry::<GameExportOp>` 泛型 → `<Op>::ID` 常量引用，无字符串 id。`crates/jd` SPECS/usage 完整（--project/-p/--config/--profile/--out）。
- **进度通路**：`reconcile_build_status` 增 `GameExports::progress` 通路（优先级 pie builds > export > extension，零新 UI 复用 footer/Build 面板）；单测钉住 Building 镜像与导出结束后的 Idle 释放。
- **错误通路**：`poll_game_export` 失败 → `BuildState::Failed` + `failed_log`（Build 面板全文）+ `notify_error`；`dynamic_linking_rejection(build.dylib_artifacts)` 在构建后、staging 前，编辑器与 CLI 共用同一函数（透传一致）。
- **三移交项处置核实**：
  1. cdylib 不改——**亲自复核属实**：本机两份 cargo git checkout（84e2d2c / c9c397b，含 my-game 锁定的 c9c397b）`crates/bevy_dylib/Cargo.toml` 均为 `crate-type = ["dylib"]`（:12）→ 现有 `dylib_artifact_in` 检测对 bevy dynamic_linking 有效；cdylib 误伤论（运行时插件缺载≠起不来）成立，按 MVP 边界不动合理。
  2. `apply_run_env` 顺序——`spawn_instance` 改为默认 `BEVY_ASSET_ROOT=cwd` 在前、`run.env` 在后（**用户 env 赢**），与 CLI `configured_game_command` 语义一致；单测 `a_runs_own_asset_root_beats_the_launch_default` 钉住两态。
  3. `validate_export_out` 前移——现在位于构建之前（cmd_export :805-814）；真机实测见 §3-1。
- **6 新单测质量**：is_available 三态 / footer Building 镜像+释放 / 成功 outcome+notify / 失败 failed_log / poll 释放槽位（刻意走失败路径避免测试打开资源管理器）/ env 顺序两态——断言具体、注释说明意图，质量良好。
- **无越界**：diff 无 book 之外的文档改动；盘点表（roadmap）未动；`loop/` 不入库（`git ls-files loop/` 为空 + `.git/info/exclude` 命中，亲查）。

## 3. 真机复验（契约：plain 构建、与 cargo 串行；共 5 项）

前置事故（非代码问题，契约教训实证）：t2 遗留的 `target\debug` exe 是 bevy/dynamic_linking 构建产物（导入 `deps\bevy_dylib-<hash>.dll`、`std-<hash>.dll`），我的 doctests 门重排了 hash 后缀 DLL → 旧 exe 0xC0000135（DLL not found）。按契约 `cargo build -p jackdaw -p jd` 重建 plain 静态 exe（`qa-final/build_plain.log`）后续跑：

1. **`--out .` 秒拒**：`jd export --out .` → 立即 `--out needs an absolute path, not `.`; the staging directory is cleared...`，exit 1，**无任何 building 输出**（构建未启动）→ A③ 防回归确认。
2. **staged release exe 独立启动**（Explorer 等价：新进程 + cwd=%TEMP%）：12s 后存活、窗口 `my-game`（hwnd 有值、521MB 工作集）、PrintWindow 截图渲染棋盘格地面+侧墙+光照 3D 场景非黑屏、截图后仍存活 → 截图 `qa-staged-exe.png`。
3. **真编辑器 BRP `game.export`**（plain jackdaw.exe，JACKDAW_OPEN_PROJECT=my-game）：`OPERATOR: game.export` 分发 → 4s（warm 缓存）dist **清空重建**（mtime 06:45→07:19）→ footer/通知 `exported my-game.exe (2 files) to C:\Users\linbo.zhang\Projects\my-game\.jackdaw\dist\release` + Build 面板 `exporting: building the game with the release profile` → 资源管理器打开 dist → 编辑器全程存活 → `qa-editor-exported.png` + `editor-stderr.log`。
4. **（加验）dist 挪盘复跑**：整目录 Move 到 `%TEMP%\jdqa-final-dist` 后启动——同样存活+窗口，渲染与原位**像素级一致**（pixdiff：983,664 px，changed 0.00%，mean diff 0.000）→ 相对布局自包含实证；验证后已移回工程原位。
5. **File 菜单真实 UI 点击链路**（QA 清单 ⑤ 补全）：BRP `input.pointer` 点击菜单栏 File（UiGlobalTransform 原值坐标，无 DPI 除法）→ 下拉展开含 **Build Game...**（顺序 New/.../Save Selection as Prefab | **Build Game...** | Keybinds...，双分隔线结构正确，截图 `qa-menu-open.png` 1280x720）→ 点击该行 → dist 重建（07:19:22→07:23:40）→ footer 成功提示（`qa-menu-exported.png`）→ 编辑器存活、无错误弹窗。菜单文案与 `project.export_binary`（Export Binary Assets）、`export-terrain` 无混用。

收尾核查：无遗留 my-game/jackdaw 进程；dist 原位完整（assets + my-game.exe）。

## 4. 文档核查

- book「Building a standalone executable」：菜单入口 / `jd export` 四种用法 / staging 布局图 / **资产根三级回退**（与 `jackdaw_runtime` `asset_folder` :1795-1808 实码一致：BEVY_ASSET_ROOT > CARGO_MANIFEST_DIR > exe 目录）/ dynamic_linking 与扩展工程两类拒绝 / pie feature 惰性与一行去除法 / 与 export-terrain、project.export_binary 区分——**内容准确**。
- README Features 表一行（File > Build Game... / jd export）与实现一致；`jd --help` usage 含 export。

## 5. 功能级终验（方案 QA 清单逐项）

- 确定性门 ✓（§1）；headless 断言 ①④ ✓（t1 单测全绿续命 + 本轮代码复核）；heavy ② 手工覆盖 ✓（t1 fc/b 逐字节、t2 B1 SHA256、本轮 dist 重建×2）；真机 ③⑤ ✓（§3 共 5 项，含清单 ⑤ 的菜单点击链路）；文档项 ✓（§4，除下述 ⚪）。
- **用户需求闭环判定**：「把当前场景 Play+打包输出可执行程序」——Play 侧前置已合（dev 回归 t2 B4 过）；打包侧从**编辑器一键**（File > Build Game...：先存场景→release 构建→footer 进度→staging→成功提示+打开目录）到 **CLI 全维度**（--config/--profile/--out）到**独立可运行产物**（双击等价启动渲染正常、挪盘自包含、0 dll 依赖）全链路真机走通，防呆完备（dynamic_linking/扩展工程/相对 --out/危险 dist 路径）。**链路完整可用 → PASS**。
- **盘点表 Stage 5 建议（给主控）**：游戏侧半边已齐——建议 Stage 5 措辞保持不动、说明里标注 `standalone game export done (feature #7); installer/cross-compile out of scope`（分发侧：安装器/压缩包/交叉编译仍缺，非本轮范围）。

## 6. 发现（分级 + 责任方）

| 级别 | 责任方 | 发现 |
|---|---|---|
| 🟡 | 程序 | 计划任务 2 内容中的 `tests/export.rs` heavy smoke（fixture export → dist 断言 + xtask 排除串）**未交付为自动化测试**；heavy 语义现由真机手工覆盖（t1 fc/b、t2 B1 SHA256、B5 与本轮 dist 重建），缺自动化回归线。建议另立小任务补齐或在台账明确接受手工基线。 |
| ⚪ | 程序 | `src/game_export.rs:42` `GameExports.root` 字段只写不读（`start_game_export` 写入后无任何读取方），死字段，下轮顺手清理。 |
| ⚪ | 程序 | book `play-in-editor.md:102` 示例 `--out D:\ Builds\game` 路径中 `D:\ ` 带空格（疑似折行拼接伪影）；按字面复制会把 `D:\` 当 --out 值（随后被 Root hazard 拒）。建议改 `D:\Builds\game`。 |
| ⚪ | QA/环境 | 契约教训再实证：dylib-feature 构建的 target\debug exe 依赖 `deps\*-<hash>.dll`，任何后续 cargo 全量门（尤其 doctests --features bevy/dynamic_linking）重排 hash DLL 即令旧 exe 0xC0000135。真机驱动前必须重建 plain exe（本轮已执行）。非代码问题。 |

## 7. 归档清单（loop/qa-final/）

fmt / clippy / xtask_fast / xtask_integration / doc / doctests / build_plain / out-dot 日志；qa-staged-exe.png、qa-editor-exported.png、qa-menu-open.png、qa-menu-exported.png、qa-moved-dist.png；qa-editor-export.ps1、qa-menu-export.ps1、qa-menu-click-finish.ps1、dbg-rows.ps1、dbg-click.ps1；editor-stdout/stderr.log。
