# 功能 #7 实施方案：Play + 打包输出可执行程序（验证与补全）

> 多 Agent 开发循环 · 策划产物（只写方案，不含代码实现）
> 日期：2026-10-22 · 策划：资深 Bevy 编辑器工程师 Agent
> 选题依据：用户原话「把当前场景 Play+打包 输出可执行程序的工作还没有进行验证，可以做这个」——即从编辑器工程出发，把游戏变成**能独立运行的可执行发布产物**，验证既有链路、补齐缺口。前置：PIE/Play 已真机跑通（dev）；Run targets/profile 透传已合入（功能 #3）。
> 调研方法：rg 文件搜索 + Read + 用户工程 `C:\Users\linbo.zhang\Projects\my-game` 实地查验，未运行任何 cargo 命令。

---

## 1. 范围与不做

**做**（判定依据见 D3）：

1. **`jd export` 子命令**：`jd export [--project <path>] [--config <label>] [--profile <name>] [--out <dir>]`——用现有 `build_project_binary_with_load` 管线构建（默认 `--profile release`，`--config` 可带上 run target 的全部维度、`--profile` 覆盖其 profile），然后 **staging**：把 exe 与工程 `assets/` 拷成「双击即可运行」的目录，默认 `<root>/.jackdaw/dist/<profile>/`；
2. **修复 `jd run --config` 资产根缺口**：直启 built binary 时补 `BEVY_ASSET_ROOT`（对齐编辑器 Play 的 `spawn_instance` 行为），否则带 target 的 run 在终端里启动必找不到资产（D2 证据 3，#3 引入的真实缺陷）；
3. **编辑器入口**：operator `game.export`（label "Build Game Executable"）+ File 菜单一行 "Build Game…"；构建进度复用 footer `BuildStatus`；成功后状态栏提示输出路径并打开输出目录（`open_with_desktop`）；导出前保存修改过的场景（复用 `save_modified_scenes`）；
4. **dynamic_linking 防呆**：构建 JSON 流中出现 dylib 产物时明确报错拒绝导出（模板工程静态链接，见 D2 证据 4）。

**不做**（首版明确排除）：

- 多平台交叉编译（`--target <triple>` 透传——#3 已裁定不做，本轮不翻案）；
- 安装器 / zip 压缩包 / 单文件嵌入打包（bevy 嵌入资产需改游戏代码，非零成本）；
- 资产加密、ico / 版本资源编辑、exe 重命名；
- `--no-default-features` 透传以剥离 `pie` feature（#3 裁定不做；`pie` 在无编辑器环境变量时惰性无害，文档说明即可，见 D6 风险 5）;
- dynamic_linking 项目的 dll 自动拷贝（MVP 拒绝 + 清晰报错；是否自动拷为裁决项 2）。

### 0. 现状一句话（盘点证据复核）

- 构建能力**已全量就位**：`CargoTarget.profile` 透传（`cargo_target_args`，`binary.rs:202-204`）→ `cargo build --profile release`，产物路径从 cargo JSON 读（零拼路径）——「release 游戏 exe」今天就能产出，但**没有任何入口、没有 staging、独立启动找不到资产**。
- 编辑器与 CLI 均**无游戏导出入口**：File 菜单无 Build/Export 项（`src/lib.rs:2666-2687`），operator 全集无 export（D1 证据 3）；`jd` 无 `--release`/`export` 子命令（`crates/jd/src/main.rs:88-99`，build/run 只收 `--project/-p/--config`）。

---

## 2. 设计结论 D1–D6（全部带代码证据）

### D1. 现有构建/导出故事盘点：构建管线完备、导出语义零存在；「export」之名已被地形/场景二进制占用

**结论：现有 = 「能编出 release exe」；缺 = 「独立可运行产物」的全部外围（入口、staging、资产根、防呆）。**

证据链：

1. **`jd` 子命令全集**（`crates/jd/src/main.rs:23-44` + `SPECS:61-125`）：`new / import / open / editor / self / upgrade / export-terrain / extension / mcp / build / run / setup / doctor / version`。`export-terrain` 是地形高度图导出（`:30` 转发编辑器进程）；`extension pack` 是扩展 dylib 打包（`:477-602`）——均与游戏可执行无关。`build`/`run` 的选项白名单只有 `--project/-p/--config`（`:88-99`），**无 `--release`**：release 只能靠 `jackdaw.toml` 写 `[[run]] target.profile = "release"` + `--config` 间接触达。
2. **`jackdaw_project_build` 的 profile 支持**：`CargoTarget { package?, bin?, example?, features, profile? }`（`binary.rs:123-135`）；`cargo_target_args` 透传 `--profile`（`:202-204`）；基础命令 `cargo build -p <pkg> [--target flags] --target-dir <.jackdaw/target/game> --message-format=json`（`cargo_build_argv:218-231`）；产物路径取 cargo JSON `executable` 字段（per-profile / examples 目录规则由 cargo 报告，零拼路径）。profile 合法性已有校验器：`declared_profiles` / `profile_is_available`（`run_manifest.rs:121-141`，dev/release 内建 + `[profile.*]` 已声明）。
3. **编辑器 UI 无导出入口**：File 菜单 `file_menu_rows`（`src/lib.rs:2666-2687`）= New/Open/Recent/Close/Save 组/Keybinds/Extensions/Modules/Hot Reload/Home，无 Build/Export；PIE operator 家族 = `pie.play/pause/stop/reload/window_mode_toggle` + `project.build`（"Rebuild Project"，`src/pie.rs:340-530`）+ `project.toggle_auto_build/prebuild/save_before_play`——**没有「导出游戏」operator**；命令面板从 operator 注册表全量枚举（`src/command_palette.rs:102-127`），新 operator 注册即自动进面板，无需为面板单做接入。
4. **`jackdaw_releases` 与游戏导出无关（确认）**：头注释自述「Jackdaw's signed release index and the registry of installed editors」——`releases.json` 签名索引 + `editors/<version>/` 安装注册（`crates/jackdaw_releases/src/lib.rs:1-15`），是编辑器自身的分发机制。
5. **命名注意**：「export」在仓库已有两处语义——`project.export_binary`（场景树二进制化，`src/file_ops.rs:600-649`）与 `jd export-terrain`。游戏导出取 **`game.export`**（operator）/ **`jd export`**（子命令）独立命名，文档与菜单文案明确区分（QA 有对应防混项，D5-⑤）。

### D2. 发布产物语义：资产根三级回退决定 staging 布局；模板 release 静态自足；staging 目录选 `.jackdaw/dist/` 天然入库豁免

**结论：一个「独立可运行」的游戏目录 = `<name>.exe` + `assets/`（与 exe 同级）。staging 是必需品而非锦上添花——`cargo build --release` 的产物在 `.jackdaw/target/game/release/`，旁边没有 assets，双击必空场景。**

证据链：

1. **资产根解析**（`crates/jackdaw_runtime/src/lib.rs:1793-1813` `asset_folder`，镜像 bevy `FileAssetReader`）：base = `BEVY_ASSET_ROOT` 环境变量 > `CARGO_MANIFEST_DIR` > **exe 所在目录**，再拼 `AssetPlugin::file_path`（默认 `assets`）。⇒ Explorer 双击（无任何 cargo 环境变量）时资产根 = `<exedir>/assets`。游戏加载场景的方式：模板 `GamePlugin` 里 `assets.load("scene.bsn")`（my-game `src/lib.rs` 实测，模板同构 `templates/game/src/lib.rs.template`），场景及其 sidecar（terrain 等）全部在 `assets/` 树内（`load_walked_assets` 全目录扫描，`runtime lib.rs:1554+`）——**整目录拷贝即完整**。
2. **工作目录不是资产根**：编辑器 Play 之所以能用项目根资产，是因为 `spawn_instance` 显式设了 `BEVY_ASSET_ROOT = cwd`（`src/pie.rs:2016-2024`）；`cargo run` 之所以能用，是因为 cargo 给子进程注入 `CARGO_MANIFEST_DIR`。**双击 exe 时 cwd = exe 目录且两者皆无**——必须靠 staging 布局满足三级回退的最后一档。
3. **`jd run --config` 的资产根缺陷（#3 引入，本轮必修）**：`cmd_run` 的 `--config` 分支构建后直启 built binary（`crates/jackdaw_cli/src/lib.rs:710-712`：`Command::new(&binary)` + `prepare_game_command` + `current_dir(&cwd)` + `envs(&entry.env)`），**没有设 `BEVY_ASSET_ROOT`**，也无 `CARGO_MANIFEST_DIR`（终端里没有）→ 资产根落到 `.jackdaw/target/game/<profile>/assets`（不存在）→ 场景加载必失败。修法一行：`command.env("BEVY_ASSET_ROOT", &cwd)`，与 `spawn_instance` 逐字对齐（`pie.rs:2021`）。
4. **运行时 dylib 依赖：模板形态静态自足**。my-game（及 `jd new` 模板）的 bevy 依赖**无 `dynamic_linking` feature**（my-game `Cargo.toml` 实测：`bevy = { git = ..., branch = "main" }` 裸依赖）→ release exe 静态链接、无外部 dll。反例通路已有文档锚点：`apply_dynamic_library_path`（`binary.rs:585-603`）注释明说「a game built with `bevy/dynamic_linking` does not start without it: the bevy dll it needs sits in `deps/`」——该函数只服务 Play/extractor，导出 staging 不受益。**检测信号现成**：cargo JSON 流的 `compiler-artifact` 记录含 `target.kind`（#3 收紧 `executable_for_package` 时已在消费），出现 `dylib` kind 的 bevy 产物即说明开了动态链接 → 导出拒绝并提示。
5. **输出目录约定**：构建产物在 `<root>/.jackdaw/target/game/<profile>/[examples/]<name>.exe`（`game_target_dir`，`binary.rs:85-87`）。staging 默认 **`<root>/.jackdaw/dist/<profile>/`**：工程 `.gitignore` 模板保证 `/.jackdaw` 被忽略（`jackdaw_scaffold/src/lib.rs:1633-1646` 写入 + `:2324-2328` `has_jackdaw_gitignore` 兼容检查，my-game `.gitignore` 实测 `/target` + `/.jackdaw` 两行）⇒ 零 `.gitignore` 改动、零误提交风险。`jackdaw_metadata.toml` / `.jackdaw/schema.json` 是编辑器侧元数据，运行时不读（runtime 只扫 `assets/`），不进 staging。
6. **release profile 现状**：模板 Cargo.toml 无 `[profile.release]` 节（my-game 实测 + scaffold 模板无 profile 处理）→ 用 cargo 默认（opt-level 3 / lto off / codegen-units 256）。**能跑、无优化加成**；是否给模板加 `lto = "thin"` 等属裁决项 4（会显著拉长用户首次 release 构建）。
7. **工具链已锁定**：模板带 `rust-toolchain.toml.template`（功能 #5 任务 3 成果），release 构建不会落错编译器——该风险已被前置消除。

### D3. 缺口判定：MVP = CLI 导出命令 + staging + 资产根修复 + 编辑器 File 菜单一行入口

**结论：按用户语义「（当前场景）→ 一键得到可执行程序」，现状最短路径 = 手改 `jackdaw.toml` 写 release target → `jd build --config` → 手动拷 assets 到 exe 旁——四个断点（无 CLI 直达、无 staging、无编辑器入口、`jd run --config` 资产根 bug）。MVP 补齐前三个 + 修第四个；编辑器入口做成最小形态（operator + File 菜单一行），不做导出对话框/进度弹窗。**

- **补**：`jd export`（构建 + staging + 报告输出路径）；`game.export` operator + File 菜单 "Build Game…"（后台构建复用 footer `BuildStatus` 进度与 Build 面板日志，成功 `notify_info` + `open_with_desktop` 打开 dist）；`jd run --config` 补 `BEVY_ASSET_ROOT`；dynamic_linking 防呆；book 文档 + README 一行。
- **不补**（除第 1 节排除项外）：导出选项对话框（profile/out 选择 UI——CLI 旗标先行，编辑器首版固定 release + 默认目录）；导出产物版本管理/增量（每次全量覆盖 staging）；自动剥离 `pie` feature。

### D4. 交互设计：File 菜单一行 + 复用既有构建进度与 shell-open，全部零件现成

**结论：最小改动面 = 一个新 operator + `file_menu_rows` 一行 + 后台任务串联（构建→staging→通知→reveal）。所有支撑件已存在，无新 UI 组件。**

1. **operator 设计**（按 CONTRIBUTING operator 模式）：
   - `id = "game.export"`，`label = "Build Game Executable"`，`description = "Build the game with the release profile and stage it with its assets into .jackdaw/dist/."`；
   - `allows_undo = false`（非场景操作，CONTRIBUTING「undo entry would be wrong」类）；
   - `is_available` = 工程已打开（`ProjectRoot` 存在）且无导出正在进行；
   - 无参数（首版固定 release + 默认目录；扩展位留给后续 `params(profile, out)`）。
2. **入口**：`file_menu_rows` 的 Save 组后、Keybinds 前插 `op_entry::<GameExportOp>("Build Game...")`（`src/lib.rs:2666-2687` 现有模式逐字照抄）；命令面板/快捷键框架自动获得（operator 注册表驱动，D1 证据 3）。Play 工具栏/pie 下拉**不加**——导出是低频发布动作，归 File 菜单语义（与 Unity Build 菜单同位）。
3. **进度呈现**：复用 `BuildStatus`/`BuildState::Building`（`src/build_status.rs:17-57`）——footer 已渲染 "Compiling X (12/47)"（`src/status_bar.rs:411+`）+ Build 面板日志 + 失败可点开日志。导出构建走 `spawn_game_build` 同款 `AsyncComputeTaskPool` 任务（`src/pie.rs:841+`，已带 `BuildProgress` sink 与 `BuildLoad` 后台限载），staging 完成后写 `BuildState::Ready`-style outcome 文本（或 `notify_info`，`status_bar.rs:122`）。
4. **导出前保存**：复用 `save_before_play` 的语义（`src/pie.rs:737-760`：拒绝未保存的 untitled 前台场景 + `save_modified_scenes` 保存全部修改场景，`scenes/operators.rs:685` 公开）——提取为 `save_scenes_before_launch` 或直接调用，保证「当前场景」进 `assets/scene.bsn` 后才构建。
5. **成功提示 + 打开目录**：`open_with_desktop` 现成（`src/project_window.rs:2066-2076`，Windows = `explorer <dir>`），先例 `project.reveal`（`:2036-2043`）与 `launcher.reveal_project`（`src/launcher/ops.rs:287-302`）。**推荐：成功后自动 `open_with_desktop(dist)` 一次**（零新 UI；裁决项 1）。

### D5. 验证矩阵（QA/程序用；①②④自动、③⑤真机）

| # | 验证项 | 手段与判据 |
|---|---|---|
| ① | staging 纯函数 + argv + 修复锚点 | headless 单测：`plan_export`（目录布局/拷贝清单/out 覆盖）、`--profile` 默认 release 与 `--config` 优先级、`cmd_run --config` 命令断言含 `BEVY_ASSET_ROOT=<cwd>`、dylib-kind 拒绝逻辑（字面量 JSON 钉住） |
| ② | `jd export` 产出正确 | heavy 档（fixture `tests/fixtures/bsn_game` 或 my-game）：dist 目录含 exe + `assets/` 且与源 assets 抽样逐字节一致、无 target 中间物；重复导出幂等覆盖 |
| ③ | **独立运行（真机）** | 从 Explorer 双击 dist 内 exe（QA 用 `Start-Process` 任意 cwd 等价模拟 + 用户终审真双击）：进程存活 ≥ 数秒、窗口打开、场景渲染（PrintWindow 截图非黑屏、与编辑器视口结构比对）、贴图/网格正常、关闭正常退出；把 dist 整体挪到别的盘符再跑一遍（相对布局自包含） |
| ④ | 回归 | 编辑器 Play（dev）不回归（BRP `pie_running` + 预构建链路）；`jd run --config <带 profile 的 label>` 修复后场景正常加载（进程输出/截图）；`jd run`（无 --config）命令串逐字节不变（既有回归锚点测试续命） |
| ⑤ | （UI）导出全链路（真机） | File 菜单 "Build Game…" 可见可点（SendInput，loop/qa 资产复用）→ footer 出现构建进度 → 成功提示含路径 → 资源管理器打开 dist；菜单中 `project.export_binary`（场景二进制）与 `game.export` 两个 export 字样入口不混淆（文案检查）；未保存场景时导出先保存或明确拒绝 |
| ⑥ | doctor（若做该行） | `jd doctor` 输出 export 前置状态（assets/ 存在、profile 合法） |

### D6. 风险与对策

1. **Windows 全量 release 首编 20-40 分钟级**：验证策略 = 一次构建多次断言——QA 先跑一次 `jd export`（或 `jd build --config` 同 target-dir 预热 cargo 缓存），后续断言全走 fresh/拷贝路径；编辑器内导出走 `BuildLoad` 后台档（半核限载，不冻编辑器）；heavy 测试沿用 `xtask` `SDK_BINARIES` 排除机制，只在 heavy 档付费一次。
2. **资产根歧义（非 staging 目录直拷 exe）**：文档写死「exe 与 assets/ 同级是唯一受支持布局」；`jd export --out` 允许自定义目录但布局不变。
3. **workspace 工程**：`[[run]] target.package` 跨成员时 assets 仍在工程根（模板约定）——staging 从 ProjectRoot 拷 `assets/`，不从 `package_dir` 拷（`shim_spec_for_project` 两者都解析，用 root）。
4. **exe 被占用 / 杀毒锁文件**：staging 拷贝失败 = 明确 io 错误路径（报错含源与目的路径），不静默半成品——先拷 assets 再拷 exe，exe 拷贝成功才算导出成功。
5. **`pie` feature 滞留在发布物**：模板默认 `features = ["terrain", "pie"]`，`pie` 在无 `JACKDAW_PIE` 环境变量时惰性（`pie_windowless.rs:57-69` 环境门控原样返回）——无害但拖 `jackdaw_pie_protocol/ipc` 依赖。文档注明「发布可从 jackdaw_runtime features 去掉 pie」（改 my-game Cargo.toml 一行事，属用户工程决策，工具不代改）。
6. **命名混淆**：`jd export` vs `jd export-terrain`、`game.export` vs `project.export_binary`——usage 文案与菜单 label 已区分（"Build Game Executable"），D5-⑤ 有防混检查项。
7. **`jd run --config` 修复的边界**：只补 `BEVY_ASSET_ROOT`，不动 env/args/cwd 语义；`run.env` 显式设置的 `BEVY_ASSET_ROOT` 必须仍能覆盖（envs 顺序：先设默认后 `entry.env`——与 `spawn_instance` 的 `.envs(&run.env)` 在 `.env(BEVY_ASSET_ROOT)` 之后的既有顺序相反，实现时对齐「用户 env 赢」语义并加单测）。

---

## 3. 技术方案

### 3.1 模块 / 文件布局

```
crates/jackdaw_project_build/src/
  export.rs        （新）bevy-light 纯函数：ExportPlan { profile, dist_dir, exe_source, assets_source }；
                   plan_export(root, profile, out) → ExportPlan；stage_export(&plan)（先 assets 后 exe，
                   返回报告/错误）；dist 子目录名用 profile 名（展示语义），exe 路径来自 build 结果（零拼）；
                   json_dylib_detected(report 记录) → Option<拒绝文案>；单测（布局/幂等/拒绝）
  binary.rs        （改，小）构建事件流旁暴露「本次构建是否出现 dylib 产物」（kind 过滤，纯函数 + 单测）
  lib.rs           （改）pub mod export; pub use
crates/jackdaw_cli/src/lib.rs （改）cmd_export（--config 解析复用 resolve_run_config → CargoTarget，
                   --profile 覆盖/默认 "release"，走 build_project 同管线 → stage_export → 打印 dist 路径）；
                   cmd_run --config 分支补 BEVY_ASSET_ROOT（用户 env 赢）；parse_profile/out_arg；单测
crates/jd/src/main.rs        （改）SPECS 增 export（values: --project/-p/--config/--profile/--out）+ usage 两处
src/game_export.rs （新）GameExportOp（game.export）+ 后台任务（save scenes → build（CargoTarget{profile:
                   release}，BuildLoad 后台档）→ BuildStatus 进度 → stage_export → notify_info(路径) +
                   open_with_desktop(dist)）；单测（op 注册/is_available/世界模式）
src/lib.rs         （改）注册 plugin/operator；file_menu_rows 增 op_entry::<GameExportOp>("Build Game...")
tests/export.rs 或扩 run_targets.rs （新）heavy smoke：fixture export → dist 断言（exe+assets 一致）
xtask/src/main.rs  （改，如新增测试二进制）SDK_BINARIES 排除串
book/src/user-guide/ （改/新）play-in-editor.md 增「Build a standalone executable」节或独立 exporting.md
README.md          （改）功能表一行
```

### 3.2 关键接口草图（示意，非最终签名）

```rust
// crates/jackdaw_project_build/src/export.rs（bevy-light，CLI/编辑器共用）
pub struct ExportPlan {
    pub profile: String,          // 展示名（"release"），同时是 dist 子目录名
    pub dist_dir: PathBuf,        // 默认 root/.jackdaw/dist/<profile>
    pub exe_source: PathBuf,      // build_project_binary_with_load 返回的 binary
    pub assets_source: PathBuf,   // root/assets（模板约定）
}
pub fn plan_export(root: &Path, profile: &str, out: Option<&Path>) -> ExportPlan;   // 纯
pub fn stage_export(plan: &ExportPlan) -> Result<ExportReport, ExportError>;        // 先 assets 后 exe

// src/game_export.rs（编辑器侧）
#[operator(id = "game.export", label = "Build Game Executable",
           description = "Build the game with the release profile and stage it with its assets into .jackdaw/dist/.",
           allows_undo = false)]
fn game_export(/* … */) -> OperatorResult;   // save → spawn_game_build(target=release) → stage → notify + reveal
```

### 3.3 数据流

```
jd export [--config L] [--profile P] [--out D]
  └─ resolve_run_config(L)（可选）→ CargoTarget；--profile P 覆盖 target.profile，缺省 "release"
  └─ build_project(root, target)  → build_project_binary_with_load（.jackdaw/target/game/<cargo 目录>）
       ├─ JSON 流出现 dylib kind → 报错拒绝（dynamic_linking 防呆）
       └─ build.binary（cargo JSON executable）
  └─ plan_export(root, profile, out) → stage_export：dist/ = exe + assets/**（整树拷贝）
  └─ 打印 "exported <name> to <dist>"；失败打印首条 error

编辑器 game.export
  └─ save scenes（save_before_play 同款）→ 后台任务（BuildStatus 进度）→ 同上 build+stage
      → notify_info("Exported to <dist>") → open_with_desktop(dist)

独立运行（发布物消费者）
  └─ 双击 dist/<name>.exe：BEVY_ASSET_ROOT ✗ CARGO_MANIFEST_DIR ✗ → base=exe 目录 → assets 命中 ✓
```

---

## 4. 任务拆分（2 个任务）

### 任务 1（程序）：`jd export` + staging + `jd run --config` 资产根修复
- **内容**：`jackdaw_project_build::export`（plan/stage/dylib 检测 + 单测）；`jackdaw_cli` `cmd_export` + `cmd_run --config` 补 `BEVY_ASSET_ROOT`（用户 env 赢，单测钉顺序）；`crates/jd` SPECS/usage；profile 合法性复用 `profile_is_available`。
- **验收**：全部新单测绿（staging 布局/幂等/dylib 拒绝/BEVY_ASSET_ROOT 命令断言/无 --config 路径逐字节不变）；`cargo xtask fast` 过；`jd export --help` 与 usage 输出正确。

### 任务 2（程序 + QA）：编辑器入口 + heavy/真机验证 + 文档
- **内容**：`src/game_export.rs` operator + `file_menu_rows` 一行 + BuildStatus 进度复用 + 成功 notify/reveal；`tests/export.rs` heavy smoke（fixture export → dist 断言）+ xtask 排除；book 文档节 + README 一行；全量 CI 门。
- **验收**：见下节清单（含真机③⑤）。

---

## 5. 给 QA 的验收清单

**确定性门（全部必须绿）**
- [ ] `cargo fmt --all -- --check`；`cargo clippy --workspace -- -D warnings`
- [ ] `cargo xtask fast`（含 project_export/cli/game_export 新单测）；`cargo xtask integration`（heavy smoke 被排除）
- [ ] `cargo doc --locked --workspace --document-private-items --no-deps`；doctests 基线非回归

**headless 行为断言（①④）**
- [ ] `plan_export`：默认 dist = `<root>/.jackdaw/dist/release`；`--out` 覆盖；exe/assets 源路径正确
- [ ] `stage_export`：目录内容清单正确、重复执行幂等、exe 被锁时错误信息含双路径
- [ ] JSON 含 `kind:["dylib"]` 产物 → 导出拒绝、文案指明 dynamic_linking；静态流 → 通过
- [ ] `--profile` 缺省 "release"；`--config` 的 target.profile 被 `--profile` 覆盖；未知 profile 报错（列可用）
- [ ] `jd run --config` 生成的命令含 `BEVY_ASSET_ROOT=<cwd>`；`run.env` 显式 BEVY_ASSET_ROOT 时用户值赢
- [ ] `jd run`（无 --config）命令串与现状逐字节一致（既有锚点测试续命）

**heavy 档（②，一次构建多次断言）**
- [ ] fixture `jd export` → dist 含 exe + assets（抽样逐字节一致）；二次导出幂等
- [ ] dist exe 从 staging 目录直接 `Start-Process` 启动：场景实体加载（截图/输出标记）

**真机（③⑤，loop/qa 资产 + SendInput；「留用户手测」仅终审抽查）**
- [ ] my-game 导出后：Explorer 双击 dist exe——窗口开、场景渲染非黑屏（PrintWindow 比对编辑器视口）、贴图正常、关闭退出；dist 整体挪盘后再跑仍正常
- [ ] 编辑器 File > Build Game…：菜单可见 → 点击 → footer 构建进度出现 → 成功提示含路径 → 资源管理器打开 dist；未保存场景先被保存（或明确拒绝）
- [ ] 菜单/面板中 `project.export_binary`（场景二进制）与 `game.export` 文案不混淆
- [ ] 编辑器 Play（dev）回归：预构建→Play→Stop 链路正常（BRP `pie_running`）

**文档项**
- [ ] book：导出节含命令、staging 布局图、资产根三级回退说明、dynamic_linking/pie feature 两条注意事项
- [ ] README 功能表一行；`jd --help` usage 含 export

---

## 6. 风险与对策

（D6 全文即风险清单，摘要）release 首编时长→一次构建多次断言+heavy 档；资产根歧义→文档钉死 exe+assets 布局；workspace assets 在根→从 root 拷；dynamic_linking→JSON kind 检测拒绝；exe 占用→先 assets 后 exe+明确报错；pie feature 滞留→惰性无害+文档；命名混淆→文案区分+QA 防混项；`jd run` 修复的 env 顺序→「用户 env 赢」单测钉死。

---

## 7. ⚠️ 需用户裁决项

1. **导出成功后是否自动打开资源管理器**：本方案推荐自动 `open_with_desktop(dist)` 一次（零新 UI、Unity 式体感）；备选：仅状态栏提示路径（更安静，用户自己开）。
2. **dynamic_linking 项目的处置**：MVP 推荐**拒绝导出 + 明确报错**（模板工程不受影响）；备选：自动把 `deps/*.dll` 拷进 dist（约 20 行，但 dll 集合推导有漏拷风险，维护面大）。
3. **staging 默认目录**：推荐 `.jackdaw/dist/<profile>/`（已被模板 .gitignore 覆盖、零误提交）；备选 `build/<profile>/`（更用户可见，但需改 scaffold .gitignore 模板并处理存量工程）。
4. **模板是否加 `[profile.release]` 优化**（如 `lto = "thin"`、`codegen-units = 1`）：不加 = cargo 默认即可运行（现状）；加 = 发布性能更好但用户首次 release 构建显著变慢、且只影响 `jd new` 的新工程。本策划倾向**本轮不加**（验证优先，优化另立小任务）。

---
*证据快照：仓库 main `46d7efa8`（2026-10-22 台账 R1b 后）；用户工程 my-game 实地查验（Cargo.toml / main.rs / lib.rs / assets / .gitignore）。所有路径结论可按文中 file:line 复核；未运行任何 cargo 命令。实现期唯一「以实测为准」项：cargo JSON `target.kind` 对 dylib 产物的确切取值（预期 `"dylib"`，纯单测可先以字面量 JSON 钉住，heavy 实测复核）。*
