# 功能 #3 实施方案：Run targets / profiles（多目标启动配置）

> 多 Agent 开发循环 · 策划产物（只写方案，不含代码实现）
> 日期：2026-10-22 · 策划：资深 Bevy 编辑器工程师 Agent
> 选题依据：`loop/plans/roadmap-gap-analysis.md`「备选 3」节。Roadmap 验收锚点：Stage 5「launch targets/profiles（预构建二进制、workspace apps 与 examples、feature flags、默认 profile）」🟡。
> 主控已裁定：首版 target 手动写在 `jackdaw.toml`；**不做** target 自动发现 UI、不做预构建二进制缓存管理；无 target 字段保持现行为（合成默认，向后兼容）。
> 调研方法：rg 文件搜索 + Read，未运行任何 cargo 命令（避免与构建锁冲突）。

---

## 1. 范围与不做

**做**（三件套）：

1. **配置维度**：`jackdaw.toml` 的 `[[run]]` 条目新增可选 `target` 子表（bin/example 名 + 可选 package + 可选 features + 可选 cargo profile）；无 target 字段解析与行为完全不变；
2. **构建透传**：`jackdaw_project_build` 游戏二进制构建命令按 target 透传（`--bin`/`--example`/`--features`/`--profile`/`-p` 覆盖），产物路径从 cargo JSON 流读取（不手工拼路径）；编辑器 PIE 构建缓存按 target 分键；
3. **入口对齐**：Play 下拉（`pie_menu.rs`）零结构改动即支持多 target 行；`jd run`/`jd build` 增加按 run config 名选择的 `--config <label>`；`jd doctor` 增加各 run target 的存在性预检。

**不做**（首版明确排除，主控裁定）：
- target 自动发现 UI（枚举 workspace bins/examples 供点选）——首版手动写 manifest；
- 预构建二进制缓存管理（roadmap 原文的 "prebuilt binaries" 维度）——见 D7 覆盖度声明；
- `--target-dir` 三元组（交叉编译 triple）透传——`game_target_dir` 固定 `.jackdaw/target/game`（`binary.rs:85-87`）；
- cargo `--no-default-features`、RUSTFLAGS 级定制、`[[run]]` 之间的 target 继承/组合语法。

### 0. 现状一句话（盘点证据复核）

- `crates/jackdaw_pie_protocol/src/manifest.rs:13-15` 注释自认「Every run launches the same game binary; configs differ only in launch environment, not in what gets built」；RunConfig 字段仅 name/instances/env/args/cwd/mode（`:16-36`）。
- 构建命令在 `crates/jackdaw_project_build/src/binary.rs:132-147`：`cargo build -p <package> --target-dir <.jackdaw/target/game> --message-format=json`——无任何 bin/example/features/profile 维度。
- `jd run` 与编辑器 Play **并不对齐**：`crates/jackdaw_cli/src/lib.rs:566-588` 构建后直接在项目根跑裸 `cargo run`（不读 run config，甚至不透传 `jackdaw.toml` 的 `package`）。

---

## 2. 设计结论 D1–D7（全部带代码证据）

### D1. 配置 schema：`[[run]]` 内嵌可选 `target` 子表；向后兼容零成本；未知字段三方读取天然容错

**结论：推荐 schema 为 RunConfig 增 `#[serde(default)] target: Option<RunTarget>`，`RunTarget { package?, bin XOR example, features: Vec<String>, profile? }`。旧文件（无 target）解析结果逐字段不变；`jd doctor`/`jd upgrade`/scaffold 对未知字段现状即容错，无需任何迁移代码。**

推荐 schema 示例（`jackdaw.toml`）：

```toml
[[run]]
name = "Play"                    # 无 target 子表 → 现行为（合成默认，构建命令一字节不变）

[[run]]
name = "Server"
target = { bin = "server", features = ["net", "dedicated"], profile = "release" }

[[run]]
name = "Split-screen"
target = { example = "split_screen", package = "game-client" }   # package 可选，覆盖 -p

[[run]]
name = "Headless"
instances = 2                    # 与 target 正交：同一 target 起多份
env = { SEED = "42" }
target = { bin = "headless" }
```

证据链：

1. **归属**：`RunConfig`/`Manifest` 定义在 `crates/jackdaw_pie_protocol/src/manifest.rs`，编辑器经 `src/run_config.rs:6` 导入解析（`toml::from_str::<Manifest>`）。游戏进程不解析该文件（`manifest.rs:3-5`「The game never parses them」），在此扩字段**不影响游戏侧 ABI**。
2. **向后兼容**：全仓 `rg deny_unknown_fields` **零命中**——serde 默认忽略未知键；新字段全部 `#[serde(default)]`，旧文件解析路径与结果不变（现有 manifest.rs 三个单测即回归守卫）。parse 失败现状是 warn + 空 Manifest（`src/run_config.rs:38-46`），维持。
3. **doctor/upgrade 容错现状**：doctor 经 `ProjectManifest::read_checked`（`project_manifest.rs:95-100`）只报「文件不存在/不解析」两级错，未知键静默忽略——`project_manifest.rs:1-7` 头注释明文「unknown keys are ignored on both sides, so the two readers coexist」；scaffold/upgrade 全部走 `toml_edit` 定点改值（`crates/jackdaw_scaffold/src/lib.rs:20,890-892`、`project_manifest.rs:144-168` `with_extensions`），**未触碰的内容原样保留**，`[[run]]` 与其 `target` 子表不会被升级改写。⇒ 新增子表无需写任何迁移。
4. **`bin` XOR `example` 用显式双 Option + 校验函数**（`validate()` 返回 `Result<(), String>`），不用 serde `untagged`——untagged 报错信息不可读，且 launch/doctor 两处都要给出「列出现有 bins/examples」的可行动错误。
5. **scaffold 不变**：`scaffold_manifest`（`src/run_config.rs:65-76`）产出的默认 `[[run]]` 无 target；`synthesize_default`（`:56-61`）同样产 `RunConfig::default()`——「无 target = 合成默认」由类型系统自然成立。

### D2. 构建命令构造：透传点全在 `binary.rs`；产物路径不拼、从 cargo JSON 读；与 env/args/cwd 天然正交

**结论：`build_project_binary_with_load` 增一个 target 参数（bevy-light 的 `CargoTarget` 结构），命令拼接处按 target 追加 `--bin X` / `--example X` / `--features a,b` / `--profile P` /（可选）`-p` 覆盖；可执行文件路径继续取自 cargo JSON 流的 `executable` 字段——因此 example 落在 `<target-dir>/debug/examples/`、自定义 profile 落在 `<target-dir>/<profile>/` 等 cargo 产物路径规则全部被吸收，不需也不该在我们这边拼路径。**

证据链：

1. **拼接点唯一**：`binary.rs:132-147`（`cargo build -p <pkg> --target-dir … --message-format=json`）是游戏二进制构建的唯一命令构造处；`build.rs:325-353` 的 `cargo rustc` 是扩展 dylib 管线，与本功能无关（target 只作用于游戏路径）。
2. **产物解析已就绪**：`executable_for_package`（`binary.rs:464-477`）从 JSON `compiler-artifact` 记录取 `executable` 字段。cargo 对 example 产物的 `executable` 指向 `examples/` 子目录、对自定义 profile 指向对应 profile 目录——**路径规则由 cargo 报告，我们零拼路径**。需顺手收紧：现只按 `package_id` 过滤（`:473`），多 target 后应同时匹配 `target.name`/`target.kind`（JSON 里都有），否则 `cargo build -p pkg`（默认全 bins）时 `executables.pop()`（`:180-184`）取「最后一条」存在多 bin 乱序隐患——带 target 的构建因只编一个产物天然精确；默认路径行为保留不动（见风险 1）。
3. **默认合成逻辑**：无 target 时 `shim_spec_for_project`（`build.rs:457-474`）按 `jackdaw.toml` 的 `package` key（或唯一 bevy 成员启发式）解析出 `ShimSpec.package_name`，构建 `-p <pkg>` 全部 bins——**这就是「无 target = 现行为」的具体锚点**，本功能不改它。
4. **features/profile 透传语义**：`--features` 逗号连接（cargo 标准）；`--profile P`（cargo ≥1.57）：`dev→debug/`、`release→release/`、自定义 `foo→foo/` 目录——因路径取自 JSON，无需处理映射；schema 提取 `run_binary_extractor`（`binary.rs:279-301`）对 release/example 产物同样工作，且失败本就非致命（`:188-197` 返回 `Option`）。
5. **正交性**：`spawn_instance`（`src/pie.rs:1886-2005`）只消费 `run.env/args/cwd/instances` + `binary: &Path`——target 维度完全被 build 层吸收，PIE 启动路径零语义变化。features 变化导致 target-dir 内重编由 cargo fingerprint 正确处理（同目录不同 feature 解析自动分产物），无正确性风险。

### D3. PIE 链路影响：唯一硬改动是构建缓存分键；spawn/preload/Reload 链路靠参数透传自然成立

**结论：`PieSession.builds` 的键从 `PathBuf`（项目根）改为 `(PathBuf, Option<CargoTarget>)`——这是**必须**的结构改动（否则切 target 命中错误缓存二进制）；`launch_instance`/`prebuild_play_target`/`handle_reload`/`spawn_project_build` 四处取键点把 run 的 target 带上；`spawn_instance` 零改动（拿到不同 binary 路径即结束）。**

证据链：

1. **缓存键现状**：`src/pie.rs:134-138` `builds: HashMap<PathBuf, BuildState>`，注释明说「deduped by project root」。`launch_instance`（`:609-672`）三处按 `&root` 读写：缓存命中判定（`:632`，`source_is_current` 只比 src/ mtime 与二进制 mtime——**不含 target 语义**）、pending 加入（`:654-657`）、新构建插入（`:659-670`）。若不分键，「Play(bin A) 后 Play(example B)」会直接用 A 的二进制跑 B——功能错误级别，必须改。
2. **分键自带的正确性收益**：`CargoTarget` derive `PartialEq/Eq/Hash/Clone` 后，同 target 缓存命中/源码过期判定（`source_is_current`，`:706-710`）逐键独立，语义不变；`is_pending`/`is_launching`/`launch_failed`（`:172-191`）遍历 `builds.values()`，对多键天然泛化，零改动。
3. **四处取键点**（全部已有现成 `run: RunConfig` 在手，透传即可）：`launch_instance`（`:609`）、`prebuild_play_target`（`:1274-1330`，预构建**首个** run config——传它的 target，通常 None，行为不变）、`handle_reload`（`:529-560`，逐 key 重查 run config 后 relaunch，天然携带各自 target）、`spawn_project_build`（`:1412-1432`，auto-build/手动 Rebuild——保持默认 target，Rebuild 语义是「重建默认产物」）。
4. **类型放置与依赖方向**（关键约束）：`jackdaw_pie_protocol` 依赖 **bevy git main**（其 Cargo.toml `[dependencies] bevy`），而 `jackdaw_project_build`/`jackdaw_cli` 是 bevy-light——**CLI 绝不能依赖 pie_protocol**（否则把 bevy 拖进 `jd`）。因此：serde 配置类型 `RunTarget` 定义在 pie_protocol `manifest.rs`（紧邻 RunConfig）；bevy-light 构建参数类型 `CargoTarget`（含 package/bin/example/features/profile 字段，`Hash/Eq/Clone`，无 serde 依赖）定义在 project_build；**编辑器侧一对一转换**（`src/run_config.rs` 加 `fn cargo_target(&RunConfig) -> Option<CargoTarget>`，编辑器同时依赖两者，是唯一合法转换点）。`jd` 读 run 配置用 project_build 内新增的极简 `[[run]]` 读取器（只解析 name+target 子键）——这正是 `project_manifest.rs:1-7` 已声明的「多读者共存、各取所需」既有哲学；两套字段名用「schema 锁步测试」钉住（D6）。
5. **Play 启动的 run 选择不变**：`handle_play` 起 `runs[0]`（`pie.rs:899-917`）——多 target 时代第一条仍是默认入口，语义不动。

### D4. Play 下拉：零结构改动；仅加可选的目标徽标（低优先 polish）

**结论：run config 下拉不在 `game_panel.rs`（该文件是画面串流面板，rg `RunConfig` 零命中），而在 `src/pie_menu.rs`——`collect_rows`（`:140-166`）对 `manifest.runs` 逐条 × instances 展开成行，点击经 `run_by_name` + `launch_instance`（`:277-306`）。多 target 后**每个带 target 的 `[[run]]` 自动多出一行**，启动链路自动带上 target——UI 结构零改动。**可选 polish：行尾加暗色小字标注（如 `bin:server` / `example:split_screen`），帮用户区分同名不同 target 的行。**

### D5. `jd run` 对齐：`--config <label>` 选择 run config（含 target + env/args/cwd 整套），未指定时保持现行为

**结论：`jd run --config <label>` / `jd build --config <label>`：按 label 解析 run config；有命中则用其 `CargoTarget` 走 `build_project` 管线，`jd run` 随后**直接启动刚构建的二进制**（`prepare_game_command` + run.env/args/cwd，镜像 `spawn_instance` 的裸进程语义），不再退回裸 `cargo run`；未指定 `--config` 时与今天逐字节相同（裸 `cargo run`）。未知 label 报错并列出可用名（照抄 `ResolveError::UnknownPackage` 的列表式错误，`cargo_meta.rs:85-92`）。**

证据与理由：

1. **现状**：`crates/jackdaw_cli/src/lib.rs:566-588` `cmd_run` 构建后裸 `cargo run`（不读任何 run config，也丢掉了 `package` 解析）；`cmd_build`（`:555-561`→`build_project:603-644`）走 editor 同款管线。选 *run config* 而非裸 bin 名做选择器，因为「与 Play 下拉对齐」意味着 env/args/cwd/instances 语义一起带走——裸 target 名复现不了一次 Play 启动。
2. **选项表接线**：`crates/jd/src/main.rs` 的 `SPECS`（`:61-125`）是唯一选项白名单，`check_options`（`:133-155`）对未知选项**显式报错**——`run`/`build` 两个 spec 的 `values` 数组须加 `--config`，`print_usage`（`:233-268`）同步两行；`crates/jackdaw_cli/src/lib.rs:734-744` `parse_project_arg` 旁加同款 `parse_config_arg`。
3. **instances > 1 在 CLI 不展开**：`jd run` 起一个进程即可（下拉里的 `#1..#N` 是编辑器多开语义）；文档写明。

### D6. 校验与诊断：bin/example 名预校验（cargo metadata，秒级）；features/profile 错拼交给 cargo 快速失败，走既有 Compile 错误通路；doctor 增 run targets 一节

**结论分三层：**

1. **预校验（做）**：bin/example 名与 `cargo metadata --no-deps` 的 targets 比对——`MetaTarget { name, kind }`（`cargo_meta.rs:37-41`）已含 `bin`/`example` kind（`packages()` 只展平了 has_bin，需加一个「列出某 package 全部 bin/example 名」的小访问器）。错误信息列出可用名（复用 `ResolveError` 式措辞）。挂在三处：编辑器 `launch_instance` 构建前（`status_bar::notify_error`，参照 `save_before_play` 失败路径 `pie.rs:622-626`）、`jd run/build --config` 解析后、`jd doctor`。
2. **交给 cargo（不做预校验）**：features 拼错、profile 未在 Cargo.toml 定义（cargo 报 `error: profile 'foo' is not defined`）都在编译开始前秒级失败，stderr 经既有链路透出：`failure_stderr`（`binary.rs:210-226`）滤掉进度行 → `Compile { log }` → `BuildEvent::Log` 行 → 构建面板/footer（`pie.rs:844-860`）+ `failure_summary`（`:753-776`）取首条 `error` 行进状态栏。**零新增管道。**
3. **doctor**：`report_project`（`jackdaw_cli/src/lib.rs:212-410`）在 runtime wiring 节后加一节：逐 `[[run]]` 报 `run target: bin 'server' present / [fail] example 'foo' not found (available: …)`；profile 仅 `dev/release` 或 Cargo.toml `[profile.*]` 已定义时 `[ ok ]`，否则 `[warn]`（非阻断）。

### D7. 测试策略（Windows 构建慢）：三层零编译单测为主 + 恰一个 heavy 级端到端

**结论：命令构造/校验/解析全部做成纯函数后单测覆盖（不触发 cargo）；编辑器侧缓存分键用纯 helper + pie.rs 既有 `#[cfg(test)]` 世界模式；端到端 smoke 恰好一个，进 heavy 档（`xtask` 的 `SDK_BINARIES` 排除清单），复用 `tests/fixtures/bsn_game` fixture 加一个最小 example。**

1. **project_build 单测（零编译）**：`cargo_target_args` 纯函数断言各组合产出的 argv（None / bin / example / +features / +profile / +package）；`executable_for_package` 收紧后的 target 名+kind 过滤（现有测试 `binary.rs:736-748` 直接扩两行 example 用例）；`[[run]]` 极简读取器解析/缺字段/旧文件；`CargoTarget` 的 `Hash/Eq` 分键性质。
2. **pie_protocol 单测（现有文件内）**：target 子表解析、缺省 None、bin+example 同时存在的 validate 拒绝、**旧 TOML 字符串原样解析不变**（现三个测试即守卫，再加一条含 plugin/package/pins 的完整旧文件快照）。
3. **schema 锁步测试**：同一 TOML 字符串分别经 pie_protocol `Manifest` 与 project_build 极简读取器解析，断言 name/target 字段逐项相等——钉住两套 serde 字段名不漂移（两 crate 各放一半，共享同一段字面量 fixture）。
4. **编辑器侧（`src/pie.rs` 测试模块）**：`builds` 分键逻辑若抽成 `fn build_key(root, target)` 纯函数则单测；预构建路径沿用 `prebuild_tests` 的 `world_ready_to_prebuild` 世界模式（`pie.rs:2612-2634`，指向不存在路径的 root → 不真跑构建）断言「首个 run 带 target 时预构建带 target 参数」（可通过注入的参数捕获或把 spawn 决策抽纯函数）。
5. **端到端 smoke（唯一，heavy 档）**：`tests/fixtures/bsn_game` 加 `examples/schema_echo.rs`（打印一行标记即退出的最小 main）；新测试（并入 `tests/bsn_game_run.rs` 或新 `tests/run_targets.rs`）：`build_project_binary_with_load` 传 `CargoTarget { example: "schema_echo" }` → 断言返回 binary 路径含 `examples` 目录段且存在 → `util::run_windowless_game`（`tests/util/mod.rs:330-348`）跑之断言标记输出。**必须**把新测试二进制名加进 `xtask/src/main.rs:67-73` `SDK_BINARIES` 排除串，使 `xtask integration` 不为它编译游戏（现 `bsn_game_run` 即如此），Windows 上只在 heavy/release-gate 档付出一次构建。
6. **不做的测试**：features/profile 全组合真机构建矩阵（cargo 语义，不测我们代码）；多实例 × 多 target 的 UI 快照（下拉结构未变）。

### D8. Roadmap 覆盖度声明（防盘点虚报）

**做完后 Stage 5 该条仍为 🟡（半缺），但缺的半边换成了明确的一项**：workspace apps（bin/package 选择）、examples、feature flags、默认 profile 选项四维 ✅（本功能）；**预构建二进制（prebuilt binaries 缓存管理）明确不做**（主控裁定；现状 `.jackdaw/target/game` 只有隐式 cargo 缓存，无跨 target 的产物登记/复用 UI）。盘点表该行更新证据为「target 维度已落地（本功能提交）+ 预构建二进制维度仍缺」，统计口径不变（🟡 15）。另注：该条与 Stage 3「Run Game 独立新窗口」的半缺互不影响。

---

## 3. 技术方案

### 3.1 模块 / 文件布局

```
crates/jackdaw_pie_protocol/src/manifest.rs （改）RunTarget serde 结构 + RunConfig.target 字段
                              + validate()；改写 :13-15 过时注释；单测（含旧文件回归）
crates/jackdaw_project_build/src/
  binary.rs        （改）CargoTarget 参数结构（Hash/Eq/Clone）；build_project_binary[_with_load]
                   增 target 参数；命令拼接处透传；executable_for_package 增 target 名/kind
                   过滤；cargo_target_args 纯函数 + 单测
  run_manifest.rs  （新）jd 用的极简 [[run]] 读取器（name + target 子键，serde）+ 锁步 fixture
  lib.rs           （改）pub mod run_manifest; pub use binary::CargoTarget
src/run_config.rs  （改）RunConfig → CargoTarget 转换 fn（唯一合法转换点）+ 单测
src/pie.rs         （改）builds 键改 (PathBuf, Option<CargoTarget>)；launch/prebuild/reload/
                   rebuild 四处带 target；launch 前 bin/example 预校验（notify_error）；
                   prebuild_tests 扩用例
src/pie_menu.rs    （改，可选 polish）行尾 target 徽标小字
crates/jackdaw_cli/src/lib.rs （改）parse_config_arg；cmd_run/cmd_build --config 分支
                   （构建后直启 built binary，prepare_game_command + env/args/cwd）；
                   doctor 增 run targets 一节；单测（参数解析、未知 label 列名）
crates/jd/src/main.rs        （改）SPECS run/build 增 --config；usage 两行
tests/fixtures/bsn_game/examples/schema_echo.rs （新）最小 example
tests/run_targets.rs 或 bsn_game_run.rs 扩 （新）heavy 级 smoke
xtask/src/main.rs            （改）SDK_BINARIES 排除串加新测试二进制
README.md / book/src/user-guide/run-configs.md（新或并入现有 Play 文档）（改）配置说明
loop/plans/roadmap-gap-analysis.md （改）Stage 5 行证据更新（仍 🟡，见 D8）
```

### 3.2 关键接口草图（示意，非最终签名）

```rust
// crates/jackdaw_pie_protocol/src/manifest.rs（serde 配置类型，编辑器侧）
#[derive(Deserialize, Clone, Debug, PartialEq, Eq, Default)]
pub struct RunTarget {
    #[serde(default)] pub package: Option<String>,
    #[serde(default)] pub bin: Option<String>,
    #[serde(default)] pub example: Option<String>,
    #[serde(default)] pub features: Vec<String>,
    #[serde(default)] pub profile: Option<String>,
}
impl RunTarget {
    /// bin 与 example 恰好其一；名字非空。
    pub fn validate(&self) -> Result<(), String>;
}
pub struct RunConfig { /* 现字段不动 */ #[serde(default)] pub target: Option<RunTarget> }

// crates/jackdaw_project_build/src/binary.rs（bevy-light 构建参数，CLI/编辑器共用）
#[derive(Clone, Debug, PartialEq, Eq, Hash, Default)]
pub struct CargoTarget {
    pub package: Option<String>, pub bin: Option<String>,
    pub example: Option<String>, pub features: Vec<String>, pub profile: Option<String>,
}
/// 透传到 cargo build 的 argv 片段（纯函数，单测主战场）。
pub fn cargo_target_args(t: &CargoTarget) -> Vec<String>;   // --bin/--example/--features/--profile
pub fn build_project_binary_with_load(
    spec: &ShimSpec, jackdaw_dir: &Path, target: Option<&CargoTarget>,
    load: BuildLoad, report: &mut dyn FnMut(BuildEvent),
) -> Result<ProjectBinaryBuild, ProjectBuildError>;

// src/pie.rs：缓存分键
builds: HashMap<(PathBuf, Option<CargoTarget>), BuildState>,
fn build_key(root: &Path, run: &RunConfig) -> (PathBuf, Option<CargoTarget>);  // 纯函数可单测
```

### 3.3 数据流

```
jackdaw.toml [[run]] ──编辑器──> pie_protocol::Manifest（RunConfig.target）
                    └──jd------> project_build::run_manifest（name+target，锁步测试钉齐）
RunConfig.target ──src/run_config.rs 转换──> CargoTarget
Play 下拉行点击（pie_menu）/ handle_play / Reload ──> launch_instance(key, run)
   └─ build_key(root, run) 查 PieSession.builds
        ├─ 命中且 source_is_current → spawn_instance(binary)（零改动，吃现成路径）
        └─ 未命中 → spawn_game_build(spec, target) → cargo build -p [pkg]
                     [--bin X | --example X] [--features …] [--profile P] --target-dir …
                     → JSON executable 字段即产物路径（examples//<profile>/ 目录规则由 cargo 报告）
                     → run_binary_extractor（失败非致命）
jd run --config Server ──> run_manifest 解析 → 校验 label/bin/example → build_project(target)
                     → Command::new(binary) + prepare_game_command + env/args/cwd
jd doctor ──> cargo metadata --no-deps → 逐 [[run]] target 名存在性 + profile 已定义性
```

---

## 4. 任务拆分（3 个任务）

### 任务 1（程序）：schema + 构建透传 + PIE 缓存分键（核心机制）
- **内容**：pie_protocol `RunTarget` + RunConfig 字段 + validate + 单测（含旧文件回归）；project_build `CargoTarget` + `cargo_target_args` + `build_project_binary_with_load` 签名扩展 + `executable_for_package` 收紧 + `run_manifest` 读取器 + 锁步测试；`src/run_config.rs` 转换 fn；`src/pie.rs` builds 分键 + 四处取键点 + launch 前预校验；`prebuild_tests` 扩展。
- **验收**：project_build/pie_protocol 全部新单测绿；旧 `jackdaw.toml` 解析输出与改前逐字段相等；`cargo xtask fast` 过；分键纯函数单测（同 root 不同 target 不互撞、同 target 命中）。

### 任务 2（程序）：`jd run/build --config` + doctor + 预校验接线
- **内容**：`jackdaw_cli` `parse_config_arg`/`cmd_run`/`cmd_build` 分支（构建后直启 built binary，镜像 spawn_instance 裸进程语义）+ 未知 label 列名错误；doctor run targets 节 + `CargoMeta` 列 bin/example 名访问器；`crates/jd/src/main.rs` SPECS/usage。
- **验收**：CLI 单测（参数解析、label 解析、缺 label 时命令串与现状一致）；doctor 对带 target 的 fixture 输出 `[ ok ]`/`[fail]` 行；`cargo xtask fast` 过。

### 任务 3（QA + 文档）：heavy smoke + 文档 + 全量门 + 盘点表
- **内容**：`tests/fixtures/bsn_game/examples/schema_echo.rs` + heavy smoke（example 构建→路径断言→运行断言）+ `xtask` SDK_BINARIES 排除；book `user-guide` 补 run targets 配置节 + README 功能表一行；`roadmap-gap-analysis.md` Stage 5 行按 D8 更新；全量 CI 门。
- **验收**：见下节清单。

---

## 5. 给 QA 的验收清单

**确定性门（全部必须绿）**
- [ ] `cargo fmt --all -- --check`
- [ ] `cargo clippy --workspace -- -D warnings`（CI 档含 `--all-targets --features dylib`）
- [ ] `cargo xtask fast`（含 project_build/pie_protocol/jackdaw_cli 新单测）
- [ ] `cargo xtask integration`（新 heavy smoke 不在其中——SDK_BINARIES 排除生效）
- [ ] `cargo doc --locked --workspace --document-private-items --no-deps`
- [ ] `cargo test --locked --workspace --doc --features bevy/dynamic_linking`

**headless 行为断言（自动测试覆盖）**
- [ ] 旧 `jackdaw.toml`（无 target）解析结果与改前逐字段相等；带 plugin/package/pins/多 run 的完整旧文件快照测试过
- [ ] `cargo_target_args`：None=空片段；bin/example 互斥透传；features 逗号连接；profile 原样透传
- [ ] bin 与 example 同时写的 `validate()` 报错；空名报错
- [ ] `builds` 分键：同 root 异 target 不互撞、同 target 缓存命中；prebuild 用首 run 的 target
- [ ] 未知 `--config` label：报错并列出全部可用名
- [ ] `jd run`（无 --config）生成的命令与现状逐字节一致（回归锚点）

**heavy 档（release-gate 触发一次）**
- [ ] example target：构建返回路径在 `examples/` 目录段、文件存在、运行输出标记行
- [ ] 默认 target（无 --config）构建后直接可跑（回归）

**人工（少量）**
- [ ] 编辑器 Play 下拉：带 target 的 run 行出现并可启动/停止；行尾徽标（若做）不错位
- [ ] 拼错 bin 名 → 点行即出状态栏错误并列可用名（不等构建）；拼错 feature → 构建面板出现 cargo 原始 error 行
- [ ] 同项目先 Play 默认、再 Play example target、再切回——各自起正确二进制（缓存分键的手工复验）

**文档项**
- [ ] book run-configs 节含 target 子表四种字段与示例；README 功能表一行
- [ ] `roadmap-gap-analysis.md` Stage 5 行证据更新（仍 🟡：预构建二进制维度未做——D8 声明原文）

---

## 6. 风险与对策

1. **默认路径（无 target）多 bin 包的既有隐患**：`cargo build -p pkg` 构建全部 bins，`executables.pop()`（`binary.rs:180-184`）取「最后一条 compiler-artifact」，多 bin 包下顺序不稳。**对策**：本功能不改默认行为（向后兼容裁定优先）；带 target 的构建天然单产物；`executable_for_package` 收紧 target 匹配后，未来把默认路径也切到「精确匹配第一个 bin」只需一行（不在本轮）。QA 人工项覆盖一次默认路径回归。
2. **两套 serde 字段名漂移**（pie_protocol `RunTarget` vs project_build `run_manifest`）：依赖方向（pie_protocol 拖 bevy）决定必须两份。**对策**：锁步测试共享同一段 TOML 字面量，任一侧改字段名即红。
3. **`jd run` 语义分叉**：无 `--config` 走裸 `cargo run`、有 `--config` 走 built binary 直启，两条路径并存。**对策**：无 `--config` 的命令串逐字节回归测试钉死；文档写明 `--config` 才是 Play 对齐路径。
4. **`source_is_current` 对 workspace 成员源码的盲区**（既有）：只扫项目根 `src/` 与根 `Cargo.toml`（`pie.rs:714-727`），成员目录源码改动不触发重建。分键不放大该问题（逐键同语义），但 example target 的源码在 `examples/` 下**同样不被扫描**——mtime 过期判定沿既有语义（Play 每次全量 fingerprint 由 cargo 把关）。文档标注；不在本轮修。
5. **Windows heavy smoke 构建时长**：example 首编要走一遍 fixture 依赖闭包。**对策**：heavy 档独享 + fixture 已在 `bsn_game_run` 预热过依赖；QA 可跳过（标 `#[ignore]` 规则沿用 SDK_BINARIES 机制而非 attribute，与仓库现状一致）。
6. **profile 与 `--profile dev` 目录映射误解**：我们零拼路径（D2-2），映射错误类风险不存在；仅 doctor 的「profile 已定义」检查需读根/成员 Cargo.toml 的 `[profile.*]` 表（`declared_bevy_minor` 已有同型 toml 读取先例，`project_manifest.rs:291-310`）。
7. **schema 提取对 example/release 产物的适配**：example 未接 JackdawPlugin 时提取失败——现状即非致命降级（`binary.rs:188-197`），编辑器保留旧 schema；无需处理，文档注明。

---

## 7. ⚠️ 需用户裁决项

1. **`jd` 选择器旗标名**：本方案取 `--config <label>`（选整条 run config，含 env/args/cwd，与 Play 下拉严格同语义；推荐）；备选 `--target <bin-or-example-name>`（更贴 roadmap 措辞，但复现不了 Play 启动环境，且与 cargo 自身 `--target`（triple）旗标撞名易混）。
2. **target 是否支持 `package` 覆盖（跨 workspace 成员选 app）**：本方案首版即含（roadmap 原文 "workspace apps" 直指此意，实现只是多一个 `-p` 覆盖 + 分键字段）；若求更小步可裁掉，`[[run]]` 只在已解析 package 内选 bin/example。
3. **下拉行尾 target 徽标**：本轮做（任务 3 顺带，十几行）还是推迟到「target 自动发现 UI」一并做。本策划倾向本轮做（多行同名时必要辨识）。

---
*证据快照：仓库 main `eb45a3a3`（2026-10-22，含功能 #1/#2）。所有路径结论可按文中 file:line 复核；未运行任何 cargo 命令。唯一「实现期核对」项：cargo JSON `compiler-artifact` 的 `target.kind` 对 example 的取值（预期含 `"example"`，收紧过滤器时以实测为准，纯单测可先行用字面量 JSON 钉住）。*
