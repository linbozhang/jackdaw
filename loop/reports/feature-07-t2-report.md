# 功能 #7 任务 2 报告：编辑器导出入口 + heavy release 真机验证 + 文档收尾

- 分支 `loop/build-export`（7c513f64 起步，= main）
- 提交：**03f4d16d** `Add the Build Game menu entry and verify a staged release export`（7 files, +622/−27）
- 日期：2026-10-24 · 执行：程序 agent（Rust/Bevy 工程师）

## A. 编辑器入口

| 文件 | 改动 |
|---|---|
| `src/game_export.rs`（新） | `game.export` operator（id/label/description 按 CONTRIBUTING，`allows_undo = false`，`is_available` = 工程已打开且无导出进行中）；`GameExports` 资源 + 后台任务（复用 `pie::spawn_game_build` 同管线，`CargoTarget{profile:"release"}`，`BuildLoad::Background`）→ 任务内串联 `dynamic_linking_rejection` → `plan_export`/`stage_export`（全部复用任务 1 共享管线）；`poll_game_export` 轮询 → 成功 `BuildState::Ready`+outcome+`notify_info`+`reveal_in_file_manager`（主控裁定①），失败 `BuildState::Failed`+failed_log+`notify_error`；5 个单测 |
| `src/pie.rs` | ① `GameBuildResult` 增 `dylib_artifacts` 并 pub(crate)；② `spawn_game_build`/`project_root`/`reconcile_build_status` 提为 pub(crate)（export 共用）；③ `reconcile_build_status` 增 `GameExports::progress` 通路（footer/Build 面板零新 UI 复用）；④ `save_before_play` 提取 `save_scenes_before_launch(world, action)`（导出前保存，报错文案参数化）；⑤ **A② 移交项**：`spawn_instance` env 顺序对齐——提取 `apply_run_env`（`BEVY_ASSET_ROOT` 默认在前、`run.env` 在后，**用户 env 赢**，与 CLI `jd run --config` 语义一致）+ 单测钉死两种顺序； |
| `src/lib.rs` | `pub mod game_export;` + `GameExportPlugin`（init_resource + Editor 态轮询系统）+ `file_menu_rows` 增 `Build Game...` 行（Save 组后、Keybinds 前，独立 separator 分组） |
| `src/core_extension.rs` | `game_export::add_to_extension(ctx)`（operator 注册 → 命令面板/快捷键框架自动获得） |
| `crates/jackdaw_cli/src/lib.rs` | **A③ 移交项**：`validate_export_out` 挪到构建之前（原实现位于构建后，注释宣称 fail-fast 但行为相反——一次相对 `--out` 手误会白付 20-40 分钟 release 编译） |
| `book/src/user-guide/play-in-editor.md` | 新节「Building a standalone executable」：菜单入口、`jd export` 四种用法、staging 布局图、资产根三级回退原理、dynamic_linking/扩展项目两类拒绝、`pie` feature 惰性说明、与 `export-terrain`/`project.export_binary` 的区分 |
| `README.md` | Features 表一行 Game export |

防混项：菜单/面板文案 `Build Game...`/`Build Game Executable`（game.export）vs `Export Binary Assets`（project.export_binary，仅命令面板）vs `export-terrain`——三处文案互不含混。

## A 移交项处置（三件）

1. **cdylib kind 收紧评估 → 结论：不改**。实测证据：本机 cargo git checkout 两份 bevy（`84e2d2c`/`c9c397b`，含 my-game 锁定的 c9c397b）的 `crates/bevy_dylib/Cargo.toml` 均为 `crate-type = ["dylib"]`——bevy dynamic_linking 产物 kind 即 `dylib`，现有检测（binary.rs `dylib_artifact_in`）对目标场景**有效**，与任务 1 QA 实测一致。cdylib 非 bevy 场景的真风险：游戏图含自建 cdylib 插件（dlopen 型）时 dll 同样不进 staging，但那是运行时插件缺载（非「起不来」），且拒绝整个导出会误伤——按方案 MVP 边界（D2-4 只防 bevy dynamic_linking）不动，留待「插件 dll 打包」独立特性再议。
2. **spawn_instance env 顺序 → 已修**（见上表 pie.rs ⑤），`apply_run_env` 单测钉住「run 自带 BEVY_ASSET_ROOT 赢 / 无则默认项目根」两种取值。
3. **validate_export_out 提前 → 已修**（见上表 CLI 行），行为实测：`jd export --out .` 立即拒绝（无构建启动）。

## B. heavy release 真机验证（用户工程 my-game）

| 步骤 | 结果 | 证据 |
|---|---|---|
| B1 release 全量构建 + `jd export --profile release` | ✅ 本机 16 并行 rustc，全量 release 首编 + 导出约 5 分钟完成（远快于预估 20-40min）；staged `my-game.exe`（108.5MB）+ `assets/scene.bsn`；`assets/scene.bsn` 与源**逐字节哈希一致**（SHA256 match）；dist 内 **0 个 dll**（静态链接，印证模板形态） | `loop/t2_export_heavy.log` |
| B2 staged exe 独立进程启动（cwd=%TEMP%，非编辑器/非工程目录） | ✅ 12s 后进程存活、窗口 `my-game`（hwnd 有值、586MB 工作集）、PrintWindow 截图非黑屏——渲染出带棋盘格地面/侧墙/光照的 3D 场景，无错误弹窗；截图后仍存活，taskkill 收尾 | `loop/t2-shot-staged.png` |
| B3 dist 挪 `%TEMP%\jd-dist-test` 复跑 | ✅ 整目录 Move 后再启动：同样窗口+存活+**同一场景渲染**（棋盘格地面+墙体+光照，资产根随 exe 目录走实证）；验证后已移回工程原位 | `loop/t2-shot-moved.png` |
| B4 Play(dev) 回归冒烟 | ✅ plain 编辑器 exe（BRP 15703）打开 my-game → ready/idle（预构建完成）→ `pie.play` → `jackdaw/wait pie_running` 达成 → 截图（Game 面板流式渲染场景）→ `pie.stop` → idle、编辑器存活 → 正常退出 | `loop/t2-b4/b4-playing.png`、`b4-stopped.png` |
| B5（加验）编辑器 `game.export` 全链路 | ✅ 真编辑器 BRP `call_operator game.export` → dist 被清空重建（re-export 替换语义实证）→ 编辑器日志 `OPERATOR: game.export` 后 4s 完成（warm release 缓存）→ footer 显示 `Build succeeded - exported my-game.exe (3 files) to ...dist\release` → 编辑器全程存活 | `loop/t2-b5/b5-exported.png`、`editor-stderr.log` |

B4 首跑曾失败：与 doctests 门并行时 cargo 正在替换 `target/debug/deps` DLL（0xC0000135 启动即死，与任务 1 QA 遇到的 jd.exe 现象同源）——门禁结束后重建 exe 复跑即过，非代码问题（教训入「concerns」）。

B5 截图另捕获到 File 菜单展开态：`... Save Selection as Prefab / Build Game... / Keybinds... ...` 菜单行真实可见。

## 门禁（独立行探针 + 日志）

| 门 | 探针 | 日志 | 数字 |
|---|---|---|---|
| `cargo fmt --all -- --check` | FMT_OK | `loop/t2_fmt.log` | — |
| `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | CLIPPY_OK（修 1 处 `drop_non_drop` 后复跑） | `loop/t2_clippy.log` | — |
| `cargo xtask fast` | XTASK_FAST_OK | `loop/t2_xtask_fast.log` | **2845 passed / 2 skipped**（t1 基线 2839，+6 恰为本轮新单测） |
| `cargo xtask integration` | XTASK_INTEGRATION_OK | `loop/t2_xtask_integration.log` | **4982 passed / 3 skipped**（t1 4970，零失败） |
| `cargo doc --locked --workspace --document-private-items --no-deps` | DOC_OK | `loop/t2_doc.log` | — |
| doctests `cargo test --locked --workspace --doc --features bevy/dynamic_linking --no-fail-fast` | exit 101 | `loop/t2_doctests.log` | 失败集合**恰为** `jackdaw_bind`/`jackdaw_feathers`/`jackdaw_node_graph`，与 feature-01~05 基线逐项相同 → **非回归**（Windows+bevy_dylib merged doctests 既有环境问题） |

新单测 6 个：game_export 5（is_available 三态 / footer Building 镜像 / 成功 outcome+notify / 失败 failed_log / poll 释放槽位）+ apply_run_env 1（env 顺序两态）。

## 盘点表建议（只报告，不改）

roadmap Stage 5 的「预构建」维度经本轮已齐**游戏侧**半边（release 产物可独立双击运行、资产自包含、挪盘可跑）；**分发侧**（安装器/压缩包/交叉编译）仍缺——建议盘点表措辞保持 Stage 5 不动，或在说明里标注「standalone game export done (feature #7); installer/cross-compile out of scope」，由主控裁量。

## Concerns / 遗留

1. **QA ⑤ 剩余**：菜单 SendInput 点击、未保存场景导出先保存的 UI 实拍（B5 已覆盖 operator 通路与文案，QA 复核交互细节即可）。
2. B4 截图状态栏见 `Disconnected` 字样（remote 控制指示，与 PIE 无关，前轮截图同有）——非本轮引入，仅记录。
3. 编辑器/exe 与 cargo 门禁**并行**会因 deps DLL 被替换而 0xC0005 死亡（本轮 B4 首跑实证）——驱动真机用例须与 cargo 构建串行。
4. `game.export` 固定 release + 默认目录（首版最小形态，扩展位 `params(profile, out)` 留给后续）；导出无 EditorPhase 标注（BuildStatus footer 已覆盖呈现）。

## 提交

- **03f4d16d** `Add the Build Game menu entry and verify a staged release export`（src/game_export.rs 新 + pie.rs/lib.rs/core_extension.rs/cli + book/README，+622/−27；loop/ 经 `.git/info/exclude` 不入库）
