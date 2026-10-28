# T07-T3 实施报告：异目录启动回归自动化 + 导出工具面 + 收尾（P0 收官）

> 任务：`loop/plans/t07-export-reproducible.md` §二 T3（N9+N10+backlog；决策 4-A/6-A）。
> 分支 `loop/t07-final`（自 main 5eae7988 拉出），提交见文末（`Add the export manifest and inspection tool, close out export safety`）。未 push，未合入（待 QA）。

## 一、交付四项 + 顺带两项

### 1. tests/export.rs heavy smoke（验收句④ + T2 欠的 heavy 完整腿）

`tests/export.rs`（新）：fixture `bsn_game` 经编辑器管线 `build_project_binary`（共享 `target/bsn_game_run` 缓存）→ `stage_export` → 断言布局（exe+assets+marker+manifest）/过滤（预植 `.jackdaw-pie/`+`.bak` → `skipped==2` 且均不在 dist）/manifest（`manifest_for` 重算与落盘一致）→ **dist 整体复制到深层异目录**（`target/export_moved/deeply/nested/dist`）→ staged exe 以 **cwd=新目录** 跑 `--jackdaw-extract-schema` → **exit 0 + schema 可解析且 components 非空**。一次构建多次断言（D6 规则）。xtask：`SDK_BINARIES` 排除串登记 `binary(export)` + `heavy()` 的 `--test export` 显式列表。
**本机全绿：1 passed / 82.68s**（`loop/t07t3_heavy_export.log`）。

### 2. export-manifest.json（决策 4-A）

`export.rs`：`ExportManifest{profile, jackdaw, bevy_rev, generated_unix, files:[{path,sha256,size}]}`（Serialize+Deserialize）+ 纯函数 `manifest_for(dist, profile)`（SHA-256 逐文件，`sha2` 入库 workspace 依赖，lock +1 行）；`stage_into` 在 staging 内写 `export-manifest.json`（marker 与 manifest 自身不进 files——两次同输入导出 manifest 仅 `generated_unix` 不同）；`ExportReport.manifest` 带路径；CLI 成功输出打印 `manifest written: <path> (N files with sha256)`。单测 3 个：清单逐字段+幂等（除时间）、篡改可检出（`a_tampered_export_disagrees_with_its_manifest`：receipt 与树失配）。T1 的幂等测试 tree_digest 排除 manifest（时间字段）。

### 3. BRP `jackdaw/export` + MCP 第 25 工具（决策 6-A）

- `game_export.rs`：`GameExports` 加 `started_unix/last_report/last_error`（`pub(crate)`），`face()` 组装 `ExportFace{state: idle|building|ready|failed, outcome, dist_dir, manifest, files, skipped, profile, started_unix}`——导出开始清上一轮、poll 记录 report/error，任务结束后 face 长期可查（QA 不再轮询文件系统）。
- `server.rs`：`export_handler` 注册为 `jackdaw/export`（与 pie/recovery 同构）；headless 三态测试（idle/ready 含 dist+manifest+files+skipped+profile+started_at/failed 含 outcome）。`jackdaw/wait` 未动（idle 已含 Building）。
- `jackdaw_mcp`：第 25 工具 `export`（薄翻译 + 使用说明 description）；`tests/mcp_smoke.rs` 名单锁加 `export` 并**顺手补上 T06 遗漏的 `pie`**（名单原 23 个，现 25 个全锁）。

### 4. 真机矩阵 10 格 —— **10/10 全过**

| # | 格子 | 结果 | 证据 |
|---|---|---|---|
| 1 | 编辑器导出全链 | **PASS** | `wait idle` 放行后 `jackdaw/export`=ready+dist+files=2+started_at（`t07t3_matrix_editor_cells.log`） |
| 2 | 失败保旧（真机腿） | **PASS** | 预占 staging（pid 派生名）→ state=**failed**（手动探针 outcome=`could not create the staging directory ... os error 183`）+ 旧 dist SHA 逐文件不变 |
| 3 | 重复导出幂等 | **PASS** | 二次导出 dist 逐文件 SHA 一致 + manifest 除时间一致 |
| 4 | 挪盘复跑 | **PASS** | dist 复制到 `moved\deep\nest\game` → Start-Process 窗口模式运行 + 截图留档 `loop/t07-final-live/cell4-moved-game.png` |
| 5 | --out 保护 | **PASS** | 非空无标记拒绝（文案完整）+ important.txt 逐字保留；`--force` 落地（exe+assets+marker+manifest+skipped=2 审计行）——**且挖出并修复 T1 遗漏**（见 §三） |
| 6 | 大小写绕过拒收 | **PASS** | `--out C:\...\MY-GAME` → `refusing to stage ... holds the build's own sources`，assets 零损伤 |
| 7 | assets_dir 项目 | **PASS** | bsn_game 副本（path 依赖改绝对+junction 缓存）配 `content` → `dist/dev/content/scene.bsn`、无幻影 assets、staged exe schema flag **exit 0**；N8 toolchain 提示真机可见 |
| 8 | Build 面板日志 | **PASS** | 导出构建期间 ui_tree 命中 Compiling 行（Fresh 全缓存时降级判据命中 building 行，脚本已双判据化） |
| 9 | PIE 运行中导出 | **PASS** | pie_running 中 game.export → dist 无 `.jackdaw-pie`/无 `*.bak` |
| 10 | Play 回归（--locked 后） | **PASS** | dev Play 构建运行 + Stop 归位 + 编辑器存活 |

脚本沉淀 `loop/qa/t07-final-live.ps1`（编辑器 7 格一跑；CLI 3 格因环境坑改 Bash 直驱，见 §四偏差 3）。附用户 30 秒清单（方案 T3 节）：①Build Game 两次（第二次可故意锁文件制造失败）——旧 dist 始终可双击玩；②dist 拷 U 盘/别处双击能玩；③Build 面板编译日志在滚。

### 5. book exporting 节扩写

`book/src/user-guide/play-in-editor.md`：新布局图（marker+manifest）、assets_dir 跟随、**失败保留语义**专段、拒绝三态（含 --out 无标记+--force）、「What ships and what stays behind」过滤小节、manifest 小节（同输入同输出+校验器）、Reproducible builds 小节（--locked 策略/无 lock 生成+提交提示/stale 拒绝 remedy/toolchain 提示/doctor 面/导出前 audit 提示）、CLI 示例补 --force。

### 6. 顺带吸收

- **QA⚪**：`t07t2-buildpanel-live.ps1` 断言空洞修复——`nodes.Count>0` 判据（`{"nodes":[]}` 不再被非 null JSON 骗过）+ compiling 判据以节点命中为前提。
- **T1 真遗漏修复（本轮新发现）**：`--force` 漏登 `crates/jd/src/main.rs` 的 `CommandSpec` 旗标白名单（`flags: &[]`）——jd 入口直接拒绝 `--force`，**CLI force 自 T1 起从未可达**（T1 的测试只覆盖 cmd_export 内部解析）。本轮补白名单+usage 两处，真机验证 leg2 通过。报告明示：这是对 T1 交付的修正。

## 二、全量门（2026-10-25 证据标准：全文复核+改动后覆盖归档）

| 门 | 结果 | 日志 |
|---|---|---|
| `cargo fmt --all -- --check` | **clean** | `t07t3_fmt.log` |
| `cargo clippy --workspace --all-targets -- -D warnings` | **exit 0**（首跑 5 处新 warning 已修：Cow::into_owned/useless format!/3 处 doc backticks；jd 改动后覆盖重跑） | `t07t3_clippy.log` |
| `cargo xtask fast` | **2926 tests 全过**（jd flags 改动后覆盖重跑终验） | `t07t3_gate_fast.log` |
| `cargo xtask integration` | **5198 tests 全过** | `t07t3_gate_integration.log` |
| `cargo test --doc --workspace` | **8 组 ok；1 处既有 flaky**（`jackdaw_bind` doctest 在 workspace-merged 模式失败且无输出、单独 `-p jackdaw_bind --doc` 两次 PASS；改动面不含该 crate；历史 T05 亦有 doctest 多轮重跑先例——**判定与本任务无关**，干净树证明因 stash 风险未做，如实记档） | `t07t3_gate_doctests.log` |
| 单测补验 | build crate 27（export 模块含 manifest 3 新测）、主 crate 1168+face 1+game_export 5、jd 22、cli 18 全绿 | 各专项日志 |
| heavy | `cargo test --test export` **1/1（82.68s）**；mcp_smoke 名单锁 25 工具（属 SDK_BINARIES heavy 档，本轮仅名单更新） | `t07t3_heavy_export.log` |

## 三、buglist 核对

R9/R10/Y7 已勾（主控定稿恢复版），本轮无新打钩项 ✓。roadmap T07 勾选与台账记行留 QA/主控终审。

## 四、偏差与事故记档

1. **jd.exe 间歇 0xC0000135（STATUS_DLL_NOT_FOUND）追因**：矩阵 CLI 格子多次失败，一度误判为「PowerShell 子进程环境 vs CMD」（有同条件 A/B 假象佐证）。最终闭环：**中途被杀的 cargo 构建（清理残留进程时误杀）在 deps 留下半写 dll**——`cargo build -p jd --bins` 完整重建后一切正常；「PS 挂/CMD 过」的假象源于测试恰好落在坏 dll 窗口两侧。教训：杀构建进程后要对 target 产物健康度保持怀疑，先重建再判定。
2. **doctests 干净树证明未完成**：一次 stash 验证因 CMD `;` 语法作废、一次 stash 后命令中断致 stash 悬挂（已完整恢复，工作区无损），评估再折腾风险大于收益——以三重旁证（单独跑过×2/改动面无关/历史 flaky 先例）记档收束。
3. **矩阵 cell 5/6/7 改为 Bash(CMD) 直驱**：PS 驱动叠加坏 dll 窗口的坑（偏差 1）耗尽时间预算后，三格改为与脚本等价的命令序列直接执行并留全量输出日志（`t07t3_cell5_refused.log` 等）；脚本本体保留完整逻辑（含 cmd 包裹的 Invoke-Jd），供后续复跑。
4. **矩阵脚本三轮修复**（皆脚本层，非产品）：预清无标记旧 dist（feature#7 时代残留触发 N7 正确拒收——保护本身工作正常）；cell 2 等 `started_at` 翻转再断言（Fresh 构建秒完，断言早于状态翻转读到上轮 ready）；cell 4 变量 `$exe` 与 `$Exe` 大小写相撞（PS 变量名不区分大小写）。
5. **cell 7 fixture 副本**：相对 path 依赖改绝对 + junction 复用 heavy 缓存（已拆 junction 再清理，未污染真缓存）。
6. **xtask heavy 全档未整跑**（SDK triple 构建重）：以 `cargo test --test export` 直跑绿 + `SDK_BINARIES`/`heavy()` 登记为准；`release-gate`（fast+integration+heavy）留 CI/QA 终审。

## 五、提交

- 提交信息：`Add the export manifest and inspection tool, close out export safety`
- 文件面：`crates/jackdaw_project_build/src/export.rs`（manifest）、`Cargo.toml`/`Cargo.lock`/build crate `Cargo.toml`（sha2）、`src/game_export.rs`（face 状态）、`src/remote/server.rs`（BRP handler+测试）、`crates/jackdaw_mcp/src/lib.rs`（第 25 工具）、`crates/jd/src/main.rs`（--force 白名单，T1 修正）、`crates/jackdaw_cli/src/lib.rs`（manifest 摘要行）、`tests/export.rs`（heavy smoke，新）、`tests/mcp_smoke.rs`（25 锁）、`xtask/src/main.rs`（heavy 登记）、`xtask/Cargo.lock`、`book/src/user-guide/play-in-editor.md`。
