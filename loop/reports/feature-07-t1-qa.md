# 功能 #7 任务 1 QA 验收报告：`jd export` + staging + 资产根修复

- 验收对象：`loop/build-export` 提交 `b2b30092`（基线 main `46d7efa8`，diff 5 文件 +897/−21）
- 日期：2026-10-24 · 验收：QA agent（只读验收，未改任何仓库代码；探针工程建于 `%TEMP%`）
- **最终结论（复验后）：PASS** —— 首轮 FAIL 的 🔴 绕过与 🟡 自嵌套已由 `c907ce00` 修复并经探针真跑复验（§6）；首轮详情见 §2-§5

## 1. 确定性门（自跑，独立行探针 + 日志于 `loop/qa_t1_*.log`）

| 门 | 退出码 |
|---|---|
| `cargo fmt --all -- --check` | **0** |
| `cargo build -p jd` | **0** |
| `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | **0** |
| `cargo xtask fast` | **0** |
| `cargo xtask integration` | **0** |

## 2. 代码审查

### 2.1 删盘风险护栏（重点）——发现 🔴 绕过

`staging_is_unsafe`（export.rs:194-196：`dir.parent().is_none() || source.starts_with(dir)`）对**绝对普通路径**防护完备：
- 跨盘符场景（staging `H:\`、源在 `C:\`）：`C:\...` 确实不 `starts_with` `H:\`，但 `H:\` 的 `parent()` 为 `None` → 拒绝。同理 `C:\`、`/`、`\\?\C:\`、`\\server\share`（UNC 根）探针实测 parent 均为 None → 全部拒绝，无绝对形态绕过。
- `remove_dir_all` 仅在 `stage_export` 内、护栏通过且 `dist_dir.exists()` 时可达（export.rs:158）。

**但护栏按字面拼写比较，未做规范化，存在两类绕过（探针实证，`%TEMP%\jdqa_probe` 已清理）：**

| 绕过形态 | 机理 | 实测后果 |
|---|---|---|
| `--out .` / `--out ..`（相对路径） | `Path::new(".").parent()` = `Some("")` 非None；绝对源路径 `starts_with(".")` = false → 双检查全过 | **`remove_dir_all(".")` 递归删除了 cwd 全部内容**（keep.txt、nested/keep2.txt 全没了，仅目录自身因占用报 code 32）；`..` 同样删父目录内容 |
| shell cwd 位于工程根时的相对 `--out assets` 等 | 同上，且相对路径解析后即命中源 | 删除工程 assets/构建产物 |
| `--out \\?\C:\game`（verbatim，源在 `C:\game`） | 探针实测 `C:\game\assets`.starts_with(`\\?\C:\game`) = **false**（前缀组件不同） | 删除整个工程目录 |

根因：`cmd_export`（jackdaw_cli lib.rs:823）把 `--out` 原样传入 `plan_export`，`staging_is_unsafe` 拿原始拼写与绝对源比较。**建议修复**：进护栏前对 `dist_dir` 做 `std::path::absolute`/canonicalize（源同步规范化），或直接拒绝相对 `--out`；同时补 `dir.starts_with(source)` 反向包含检查（见 🟡-1）。单测 `a_filesystem_root_is_always_an_unsafe_staging_directory` 只测了绝对形态，未覆盖相对/verbatim。

### 2.2 staging 布局 / 清理语义 —— 通过

- 布局 `<dist>/<name>.exe + assets/**`，`--out` 只换目录不换布局（export.rs:49-64；实跑见 §3）；profile 作 dist 子目录名，多 profile 并存。
- re-export 先 `remove_dir_all` 清空再全量拷（export.rs:155-160），单测钉 stale 不残留 + **实跑验证**（§3）。
- io 错误双路径：拷贝/清空动作均含源与目的（`copy X to Y` / `clear the existing staging directory X`）；先 assets 后 exe，exe 成功才算导出成功。

### 2.3 防呆 —— 通过（留 1 个 🟡 给任务 2）

- dylib kind 拒绝：`dylib_artifact_in`（binary.rs:731-757）只认 `compiler-artifact` 且 `target.kind` 含 `"dylib"`；`lib`/`proc-macro`/`bin`/非 artifact 行单测钉住不误报；拒绝文案含 crate 名 + `dynamic_linking` + 静态链接指引。
- 🟡-2 `cdylib` 未拒（程序自述）：bevy `dynamic_linking` 产物 kind 为 `dylib`，对目标场景有效；若游戏图含运行时加载的原生插件（cdylib），dll 同样不进 staging。建议任务 2 heavy 实测后评估收紧为 `["dylib","cdylib"]`。
- profile 校验复用 `profile_is_available` + `declared_profiles`，未知名报错并列可用项（**实跑验证** §3）；扩展工程直接拒绝。

### 2.4 资产根修复 —— 通过

- `configured_game_command`（jackdaw_cli lib.rs:726-747）：`.env("BEVY_ASSET_ROOT", cwd)` 在 `.envs(&entry.env)` **之前** → 用户 env 赢（方案 D6-7 裁定），两个单测分别钉默认值=cwd 与用户覆盖赢。
- 无 `--config` 路径逐字节不变：`bare_cargo_run` 未动，锚点测试 `the_bare_run_path_runs_plain_cargo_run_in_the_project_root`（lib.rs:1166-1182）钉 program/args/cwd/仅 RUSTUP_TOOLCHAIN。
- ⚪-1 编辑器 `spawn_instance`（src/pie.rs:2018-2021）顺序仍为 `.envs(&run.env)` 在 `.env(BEVY_ASSET_ROOT)` 之前（默认赢）——与 CLI 新语义相反，属方案已记录的既有差异，建议任务 2 接编辑器入口时一并对齐，非本任务缺陷。

### 2.5 reveal 共享与越界检查 —— 通过

- `reveal_in_file_manager`（export.rs 末尾）在共享 crate `jackdaw_project_build::export`，CLI/编辑器可复用；spawn 不等退出、失败仅警告（正确：explorer 在 Windows 返回码不可靠，spawn 不受影响）。实跑确认导出成功后自动开资源管理器（裁定①预期行为）。
- 无任务 2 越界：diff 仅 5 文件（export.rs 新增 + binary.rs + project_build/lib.rs + jackdaw_cli/lib.rs + jd/main.rs），无 `src/`、无 `file_menu_rows`/`game_export`/`BuildStatus`、无 book/README/xtask/tests 改动；`loop/` 未入库（`git ls-files loop/` 为空、status 干净、`.git/info/exclude` 含 loop）。
- jd 侧：SPECS/usage/`print_usage` 均含 export 且与 `export-terrain` 文案区分清晰（实跑 §3）；运行时 `check_options` 先行校验未知旗标/缺值（`--out --profile` 被拒"needs a value"）。

## 3. CLI 实跑（dev profile，用户工程 my-game）

| 步骤 | 结果 |
|---|---|
| `jd export --profile dev --out %TEMP%\jdqa_t1_dist`（cwd=%TEMP%） | exit 0，日志含构建+staged 报告；用户 `.jackdaw\dist` 未被创建（--out 生效） |
| staging 布局 | `my-game.exe` + `assets\scene.bsn`；`fc /b` 逐字节一致；未触发 dylib 拒绝（静态构建） |
| **负对照**：未 staging 的构建产物从 %TEMP% 启动 | `ERROR bevy_asset::server: Path not found: ...\.jackdaw\target\game\debug\assets\scene.bsn` + `Cannot spawn scene` + `no active Camera3d`（完美复现资产根缺口签名） |
| **staged exe 从 %TEMP%（异目录）启动** | 进程存活 8s+、窗口 "my-game" 打开、资产根指向 staging 内 `...\jdqa_t1_dist\assets\`（catalog 行为证）、**无 Path not found / 无 Cannot spawn scene** → 资产根修复最直接验证通过 |
| `jd export --help` / `jd --help` | usage 正确（`--project/-p/--config/--profile/--out`），exit 0 |
| `--profile nope` | exit 1，`profile \`nope\` is neither dev, release, nor one this Cargo.toml declares; available: dev, release`（构建前快速失败） |
| re-export 幂等 | 预植 `assets\stale.bsn` + `game.pdb` 后重导 → 两文件消失、布局不变，exit 0 |
| `jd run --config Play` 实跑 | 游戏由 jd 启动，资产根=**工程根** `...\my-game\assets\`（catalog 行为证）、scene.bsn 无报错加载、进程存活 → BEVY_ASSET_ROOT 修复端到端生效 |

注：staged exe 启动时有一条 `no active Camera3d` WARN——场景异步加载与 terrain 系统 Startup 的竞态（仅出现一次，scene.bsn 60KB 实含 Camera/Cube/Light/Transform 内容且无任何加载错误），非本任务缺陷；任务 2 真机截图比对时再留意。reveal 打开的资源管理器窗口均已关闭，无残留 my-game 进程。

## 4. 发现汇总

| 级别 | 责任方 | 问题 |
|---|---|---|
| 🔴 | 程序（任务1修复） | `staging_is_unsafe` 未规范化路径：相对 `--out .`/`--out ..`/cwd 重叠相对名、verbatim `\\?\` 均绕过护栏，实测 `remove_dir_all` 递归删除目录内容（探针 A/B/C 实证；export.rs:194 + jackdaw_cli lib.rs:823）。修复建议见 §2.1 |
| 🟡 | 程序 | 反向包含未防护：staging 目录位于 assets 源内部（如 `--out <root>\assets\dist`）可通过检查，`copy_tree`（export.rs:202）会把树拷进自身子树，污染工程 assets（建议护栏补 `dir.starts_with(source)`） |
| 🟡 | 任务 2 | `cdylib` kind 未拒绝；bevy 场景（dylib kind）有效，heavy 实测后评估收紧 |
| ⚪ | 任务 2 | 编辑器 `spawn_instance` env 顺序与 CLI「用户 env 赢」语义相反（pie.rs:2018-2021），接编辑器入口时对齐 |
| ⚪ | — | `--out` 无法表达以 `-` 开头的目录名（check_options 拒绝）；staged 启动的 Camera3d WARN 为启动竞态 |

## 5. 验收判定（首轮，已被 §6 复验推翻）

- 门禁 5/5 绿；staging 布局/幂等/dylib 防呆/profile 校验/资产根修复全部按方案落地且实跑验证通过；无越界。
- 首轮 **FAIL**：🔴 数据删除绕过成立（护栏可被相对/verbatim 路径绕过）。

## 6. 复验（修复提交 `c907ce00` "Harden export staging path guards"，2026-10-24）

程序采纳全部三条建议：`normalize_staging_dir`（相对即拒 → `std::path::absolute` → `dunce::simplified` 剥 verbatim → `carries_dot_components` 残留 `../.` 即拒）+ CLI 层 `validate_export_out` 双层拒相对 `--out` + `staging_hazard` 三态（Root / ContainsSource / **InsideSource 反向包含**）。

### 🔴 复测：已修复，全部被拒且零损伤（jd.exe 重建后真跑，工程在 C:）

| 探针 | 结果 |
|---|---|
| `--out .` | CLI 层拒：`--out needs an absolute path, not '.'`，exit 1 |
| `--out ..` | CLI 层拒，exit 1 |
| `--out \\?\C:\...\my-game`（verbatim 指向源根） | 库层拒（normalize 后 containment 命中）：`holds the build's own sources`，exit 1 |
| `--out <root>\assets\dist`（源内嵌套） | 库层拒：`sits inside the build's own sources`，exit 1，且未创建任何目录 |
| `--out H:\`（跨盘，源在 C:） | 库层拒（Root 态）：exit 1，无回归 |
| 对照：绝对路径正常导出 | exit 0，布局 exe+assets、`fc /b` 逐字节一致 |
| fixture 零损伤 | 用户 `assets\scene.bsn` 60,237 字节不变；cwd 存活标记文件在；无嵌套 dist 残留 |

**规范化消费抽查**：`stage_export` 内 clear/create/copy/report 全部使用 normalize 后的 `dist`（`remove_dir_all(&dist)`、`create_dir_all(&dist)`、`assets_dir = dist.join`、`executable = dist.join`、`ExportReport::dist_dir = dist`）；`plan.dist_dir` 仅出现在错误文案——无字面路径残留消费。源侧同样经 `dunce::simplified`。新增 5 个单测覆盖全部形态（相对 4 拼写 / verbatim 走私 / verbatim 藏 `..` / 源内嵌套 / 跨盘根），`Path` 组件级比较下正/反斜杠拼写亦无绕过。

### 🟡 复测：已被 `StagingInsideSource` 覆盖

嵌套探针被拒 + 单测 `a_staging_directory_inside_the_assets_tree_is_refused` 断言源树无污染。已修复。

### 门禁核实

| 项 | 结果 |
|---|---|
| `cargo fmt --all -- --check` | **0**（复验亲跑） |
| `cargo clippy -p jackdaw_project_build -p jackdaw_cli_internal -p jd --all-targets -- --deny warnings` | **0**（复验亲跑；仅既有 build-script linker 噪声） |
| 三 crate lib 测试 | **247/247**（18+207+22，复验亲跑） |
| `cargo xtask fast` | **0，2839/2839 passed, 2 skipped**（复验亲跑，`loop/qa_t2_xtask_fast.log`） |
| `cargo xtask integration` 未全量重跑 | **替代成立**：rg 核实 `tests/` 对 `plan_export`/`stage_export`/`ExportPlan`/`ExportReport`/`dylib_artifact_in`/`"export"` **零消费**（唯一命中是 `terrain::export` 同名巧合，属 export-terrain）；改动仅 export.rs 纯函数 + CLI 校验，integration 在 b2b30092 全绿且不触达改动面；heavy export smoke 本就排期任务 2 |

### 复验遗留（均 ⚪，不阻塞）

- `validate_export_out` 文档注释称 "fails before the build is paid for"，但调用点在 `build_project` 之后——注释不准；行为安全（库层兜底），仅坏输入时白付一次热构建，后续可把校验上移到构建前。
- 8.3 短路径名（`C:\PROJ~1`）等极端拼写不在意外输入防护范畴（备注，非发现）。

## 7. 最终判定

**VERDICT: PASS** —— 🔴 与 🟡 均已修复且探针真跑证实被拒+零损伤；跨盘与正常导出无回归；门禁经复验亲跑全绿（integration 缺席经 rg 零消费核实，替代成立）。任务 1 可合入，进入任务 2。
