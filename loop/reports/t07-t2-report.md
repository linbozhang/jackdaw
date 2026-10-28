# T07-T2 实施报告：统一 --locked 与构建反馈

> 任务：`loop/plans/t07-export-reproducible.md` §二 T2（N5+R9+N8，决策 3-A 已裁）。
> 分支 `loop/t07-t2-locked`（自 main 01eb4883 拉出），提交 **9a80bcbc**
> `Build with --locked everywhere and show the build log`（5 文件，+325/−11）。未 push，未合入（待 QA）。

## 一、改动面

| 项 | 实现 |
|---|---|
| **N5 --locked 四入口统一** | `cargo_build_argv`（`binary.rs`）单点追加 `--locked`（argv 尾）；`build_project_binary_with_load` 在 pin_project **之后**、spawn 之前接 `ensure_lockfile`（lock 缺则 `cargo generate-lockfile` + log「generated …; commit it for reproducible builds」，失败仅 warn 由 build 自然报错）；构建失败时 stderr 含 cargo 的 `--locked was passed` 拒绝文案 → 追加一行 remedy（`cargo update`/删 lock 重生成/提交），经 BuildEvent::Log 进 Build 面板 |
| **R9 面板空白** | `scrolling_log.rs` `spawn()` bundle 显式补 `ScrollPosition::default()`（方案一行修）；世界直插回归测试钉住「content 变化 → 子 Text 同步 + 钉底」 |
| **N8 提醒** | `reproducibility_notices`（binary.rs）：工程根无 `rust-toolchain.toml` → build log 一行提示（新工程有该文件零打扰）；`jd doctor` 的 `report_project` 补 lock/toolchain 两行（`[warn]` 不阻断，带 note） |
| 配套 | `BuildEvent` 加 `#[derive(Debug)]`（测试断言用）；argv 锚点测试更新为**有意行为变更锚点**（`the_build_command_locks_the_dependency_resolution`，断言集含 `--locked`）；`bevy_source::workspace_lockfile` 改 `pub(crate)`（lock 检查复用） |

## 二、四入口验证（全部经 binary.rs 单点，无旁路）

调用链证据（rg 全仓）：
- **jd build**：`crates/jackdaw_cli/src/lib.rs:673,686` → `build_project` → `build_project_binary_with_load:1017`
- **jd run**：`cli lib.rs:727` → 同上
- **jd export**：`cli lib.rs:847` → 同上
- **Play（编辑器）**：`src/pie.rs:1109` → `build_project_binary_with_load`；**编辑器导出（game.export）**：`game_export.rs` → `spawn_game_build` → 同 `pie.rs:1109`

`"build"` argv 拼装全仓仅 `binary.rs:237` 一处（bootstrap.rs/plan.rs 的 SDK/扩展管线是 jackdaw 自身 workspace 构建，不属游戏工程四入口，不动——边界记档）。

**--locked 生效与存量工程兼容**：
- bsn_game fixture（lock 已入库）：`cargo metadata --locked` **exit 0**（解析层完整一致性检查）；
- my-game（用户工程）：`cargo metadata --locked` **exit 0**；
- **真跑**：新版编辑器对 my-game 的 prebuild（全链 `--locked` argv）完成 → `jackdaw/wait idle` 放行（loop/t07t2-live/）；变更对照=argv 锚点测试断言集 diff（旧数组无 `--locked`）。

**pin_project 时序回归**：pin 先跑（bevy-main 工程改 lock）→ ensure_lockfile（pin 已生成的 lock 直接过）→ build --locked——`bevy_source` 既有测试全绿（223 lib 含），stale-lock 集成用例里 pin 失败仅 warn 的降级语义亦实测（fixture 无 bevy → warning 后继续）。

## 三、红→绿

- **N5 对照用例**（任务要求的「旧行为静默漂移 vs 新行为报错有指引」）：
  - 新行为腿（真跑 cargo 集成）：`a_stale_lockfile_fails_locked_with_the_remedy_in_the_log`——fixture 生成 lock 后 bump version 制造过期 → build → `Err(Compile)` 且 log 含 cargo 原始拒绝（`--locked was passed`）+ BuildEvent 流含 `cargo update` remedy。**修复前该测试无法编译**（argv/hint 不存在）——旧行为由 argv 锚点断言集变更承担对照（旧断言数组=无 `--locked` 的历史 argv，本提交 diff 可见）。
  - 纯函数钉：`a_locked_failure_is_translated_into_a_remedy`（真实 cargo 文案字面量匹配/无关 stderr 返 None）。
- **R9 红证：不可得，已论证**——修复前跑世界直插测试**直接绿**（`t07t2_red_run1.log`: 1 passed）。根因核实（bevy git 源码）：上游 `eb19a9ea0`（PR #15898「Migrate UI bundles to required components」）已把 `ScrollPosition` 列入 `Node` 的 `#[require]` 列表——任何 spawn `Node` 的实体自动获得该组件，`refresh_scrolling_logs` 的 query 恢复匹配。buglist R9 的诊断（「已对照 bevy 源码不自动插入」）写作时为真，其后的 bevy rev 升级已使症状自愈。处置：显式 `ScrollPosition::default()` 落进 bundle（方案修法，防上游回退+意图显式化）+ 回归钉 + 真机验证（见 §四）。
- 数字：新增/更新测试 6 个（argv 锚点、hint 纯函数、notices、lockfile 生成/不动、stale-lock 集成、scrolling_log 回归钉）；红→绿形态=1 处真红不可得（论证替代），1 处以断言集变更+集成绿腿承担。

## 四、真机抽验（R9 用户可见面 + --locked 真跑）

`loop/qa/t07t2-buildpanel-live.ps1`（沉淀）+ 手动断言（`H:\workspace_AI\t07t2_live_manual.ps1`，脚本首轮 BRP 超时后复用存活编辑器补测）：
- 新版编辑器（含本次全部改动）打开 my-game → prebuild 全链 `--locked` → `jackdaw/wait {until: idle}` 放行（**--locked 构建真跑成功**）；
- `jackdaw/ui_tree {text: 'as a cargo binary'}` 命中 Build 面板文本节点（entity 4294963362），内容为完整构建日志：`building the game / building my-game as a cargo binary in C:\...\my-game, into ...\.jackdaw\target/game / Compiling jackdaw_bsn / Compiling jackdaw_pie_protocol / Compiling jackdaw_prefab / Compiling jackdaw_terrain / …`——**面板不再空白**；
- N8 提醒接线真机构成证据：stale-lock 集成用例的 BuildEvent 流里出现 `no rust-toolchain.toml in ...` 行（fixture 无该文件时）；
- 截图留档 `loop/t07t2-live/t07t2-buildpanel.png`。

## 五、门禁（quick 四门，日志全文复核+归档 loop/t07t2_*.log）

| 门 | 命令 | 结果 | 日志 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **clean** | `t07t2_fmt.log` |
| Lint | `cargo clippy --workspace -- -D warnings` | **exit 0**，无 error、无新 warning（既有 build-script linker 警告同历轮；首跑揪出 1 个 `bool::then` 闭包告警已修为 `then_some` 后覆盖重跑） | `t07t2_clippy.log` |
| 单测 | `-p jackdaw_project_build --lib` / `-p jackdaw_cli_internal --lib` / `-p jackdaw --lib` | **223 / 18 / 1168 全绿 0 failed**（lib 日志中 ERROR 行为 game_export 失败路径测试注入样本；stale-lock 集成首跑揪出 cargo 实际文案是 `because --locked was passed`，匹配串修正后覆盖重跑） | `t07t2_lib_buildcrate.log` / `t07t2_cli.log` / `t07t2_lib.log` |
| 任务相关集成 | `cargo test --test guards` | **197 绿 0 failed** | `t07t2_guards.log` |

## 六、buglist

- **R9**：打 `- [x]` + `> 已修复 9a80bcbc（T07-T2）` 备注（自愈根因 + 显式化 + 回归钉 + 真机验证全记录）。
- R10/Y7 上轮已勾，未动；W9 已由 T04 勾。

## 七、偏差与事故记档（重要）

1. **开局误 `git pull` 事故（已完全恢复，零损失）**：开局在 main 上误执行 `git pull`，与 origin/main（上游远端）合并冲突四文件、索引进入中间态。`git merge --abort` 因 MERGE_HEAD 丢失失败，改用 `git reset --hard 01eb4883` 清干净后重拉分支——工作内容零损失（全部在 01eb4883 内）。**教训已内化：loop 本地 main 与上游远端分叉是常态，永不 pull。**
2. **buglist.md 编码损坏事故（部分恢复）**：为回填 R9 提交哈希，用 PowerShell `Get-Content -Raw`+`-replace`+`Set-Content` 管道编辑 buglist.md，系统代码页 GBK 往返导致文件字节层损坏（该文件未入库、无 git 版本）。已按字节层恢复：**英文、路径、行号、哈希、75 条结构零损失；约 300 个汉字/标点（多为句读，显示 `�?`）不可恢复**；R9/R10/Y7 三条按上下文原文精确重写；文件头加事故注记；中间产物 `buglist.recovered.md`。**教训：对非 ASCII 文件永远用 Edit/Read 工具，不用 PowerShell 文本管道。**
3. **R9 红证不可得**（§三）：bevy 上游 required components 迁移已使症状自愈，红证在当前 rev 无从跑起；以源码证据+测试直接绿+真机面板验证替代。
4. heavy 全链 `cargo build`（bsn_game 无缓存，20-40 分钟）未跑：以 `cargo metadata --locked`（正是 --locked 一致性检查所在层）双 exit 0 + my-game 真机 prebuild 全链跑通承担；T3 的 heavy 导出 smoke 将覆盖完整构建腿。
5. `compile_failure_log`（Compile 错误的 log 字段）未追加 remedy 文本：remedy 经 BuildEvent::Log 已达面板/footer（用户可见面），两处重复无增益。

## 八、交接 QA 注意点

- 行为变更锚点：argv 断言集（`--locked` 进四入口构建命令）；无 lockfile 工程首次构建会看到 generate+提示行；jd doctor 输出多两行（warn 不影响 exit code）。
- 真机复核建议：①无 lock 工程 Play 一次看生成提示；②手改 Cargo.toml 加依赖后构建看拒绝+remedy 文案；③Build 面板构建期间滚日志（截图基线 `loop/t07t2-live/t07t2-buildpanel.png`）。
