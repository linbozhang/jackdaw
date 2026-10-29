# T15 任务 1「缺口补齐轮」程序报告

> 分支 `loop/t15-animation`（自 main 6f170325）；方案 `loop/plans/t15-animation.md` §六 T1；
> 主控裁定 6 点全按建议执行（AN1=catalog 模块 / AN4=自制 hero.glb / AN3=bindings_card
> 行先例 badge / AN2=integration 档单跑 feature 腿）。改动 9 文件 +355/−31（7 改 2 新），
> 零场景格式变更、零协议变更、零新 plugin/系统——AN1 是数据行、AN3 是 UI 行、AN2 是门禁行。

## 一、AN1-AN6 逐条处置

### AN1 🔴 游戏侧动画无授权路径 → **已修（决策 1-A：catalog 数据行）**

| 项 | 内容 |
|---|---|
| 数据行 | `crates/jackdaw_project_build/src/modules.json` 追加 animation 条目：`runtime_features:["animation"]`、`provides:["jackdaw_animation_runtime"]`、`component_prefixes:["jackdaw_animation_runtime::"]`、requires 空、default=false（对齐 navmesh 简形+multiplayer 前缀形；「no rigs links neither」设计注释保持成立，默认不开） |
| 零代码预测成立 | catalog 是数据驱动：模块 UI（File>Modules/module_picker）、`jd new --modules`、scaffold 模板 features、`with_modules`/`modules_toml` 三面全自动出项，无一代码改动 |
| catalog 单测 +1 | `modules.rs::the_animation_module_carries_the_feature_that_plays_its_sets`：feature 恰为 `["animation"]`、零 crate、零 requires、`providing_crate` 归属、`detect` 经 feature 识别模块 |
| scaffold teaches +1 | `new_game_project_enables_animation_only_through_its_module`：开模块⇒Cargo.toml `features = ["animation",…]`+jackdaw.toml `animation = true`；不开⇒manifest 零 animation（88→89） |
| 消费链活证 | `jd new --modules animation` 冒烟：Cargo.toml features `["animation", "terrain", "pie"]` + `[modules] animation = true`（`t15t1_jd_modules_smoke.log`） |
| doc 同步 | `project_modules.rs:75`、`launcher/ops.rs:595/841` 三处「physics, navmesh or multiplayer」枚举补 animation（project.set_module/install 等 operator 参数 doc） |
| **红证** | `t15t1_an1_game_red.log`：fixture 工程（`jd new`，默认模块=physics，无 animation）装载带 `AnimationSet` 场景（anim.bsn，`jd new`+手写，flow start_scene 指向）→ 游戏两条通用 warn：`embedded asset type 'jackdaw_animation_runtime::AnimationSet' is not registered in this app; entities referencing it will fall back to a default handle`（jackdaw_runtime）+ `cannot apply 'jackdaw_animation_runtime::AnimationSet': type not in the registry`（jackdaw_bsn::apply）——点名类型路径但零动画域指引、零播放 |
| **绿证（红转绿活证，提前落袋 T2 L1/L5 机制半边）** | `t15t1_an1_an4_game_green.log`：同一 fixture 开 animation 模块（jackdaw.toml `animation=true`+Cargo.toml features 追加，即编辑器模块开关的盘面产物）重建后：两条 unresolved warn **双双消失**、场景装载、set 绑定、default idle 播出（坏 clip 会 warn `animation state … wants clip …`，静默=三 clip 全解析） |
| **附带面：UnresolvedTypes remedy 核验** | 游戏（无 feature）装载带 set 场景**不走** catalog.rs 的 UnresolvedTypes remedy（「N types…rebuild the project」编辑器语境文案），走上述两条 runtime/apply warn；**判据「是否点名类型路径」达标**（两条都点名 `jackdaw_animation_runtime::AnimationSet` 全路径）→ 按「不新机制」裁定不改文案；**缺口=不指路模块开关**，留 T3 book 章动画模块教学一句覆盖（「无 animation 模块的游戏装载带 set 场景报这两条 warn，开模块即修」），不另建 warn 面 |

### AN2 🔴 「编辑器预览=游戏运行」零端到端证据 → **门禁层已修（决策 4-A：integration 档单跑腿）**

- `xtask/src/main.rs::integration()` 末尾追加 `animation_scene_load()` 腿，命令行：
  **`cargo nextest run --profile ci -p jackdaw_runtime --features animation --test animation_scene_load`**
- **真实执行位置**：`cargo xtask integration`（含全部 shard 切片与 `--archive` 形态）与 `cargo xtask release-gate` 每次必跑；**不进 fast**（避免全体 workspace 链接 bevy_animation，与 runtime Cargo.toml 设计注释一致）。QA 门禁表请把该行写成显式命令。
- 腿绿证：`t15t1_an2_scene_load.log`——`a_loaded_scene_plays_its_default_state PASS`（此前在一切常跑档位编译为空的死件，现 compile-checked+executed）。
- parity 真机层（M6 四通道）归 T2 L5/L6，本腿只清「门禁里死件」的机制层。

### AN3 🟡 坏引用作者态无 badge → **已修（决策 3-A：bindings_card 行先例）**

- `src/inspector/animation_graph_card.rs`（一文件）：
  - `set_reference_problems(set, clips_of, on_disk)` 纯函数：逐 state 校验 source 越界（含 0 源特判文案）/source 文件不在盘/clip 名不在该 source（文案含该文件持有的 clip 全列表，对齐 runtime warn 信息量，措辞镜像 `wants clip … and its source holds`）；**未索引但在盘的文件不报**（区分「未索引」与「不存在」，按方案风险表防误报）；
  - 渲染=bindings_card 行 badge 先例：行内 `TextColor(TEXT_ERROR)` 文本+`Hovered`+`Tooltip::title`（tooltip 渲染器读该二元组），badge 非 gate；
  - `AnimationGraphRef` 卡：held 非空且不在 `graph_files`（AssetIndex 真相源）→ 「no graph file named `…` in this project」行；
  - 数据源=`AnimationLibrary`（clip 真相源，开放场景 sources 强制索引）+`ProjectRoot.assets_dir` 盘上存在性+`graph_files`。**不建新面板不动播放面**。
- 单测三件（纯逻辑，文件内 tests mod）：坏 clip（含可用列表断言）/source 越界+文件不在盘/全好（含「未索引但在盘不报」半边）。
- 集成测试三件（新文件 `tests/inspector/animation_cards.rs`，tests/inspector 合并二进制）：set 指不在盘文件⇒恰一 error 行+行上 badge 可读；graphref 指不在档文件⇒恰一 error 行+badge；全 good set⇒零行零 badge。
- **红证**：`t15t1_an3_badge_red.log`——修前树上同型测试通过：坏 set+坏 graphref 卡片照常构建（Convert 钮/picker 在），错误行与 badge **双零**（结构性缺席：修前 fill 只产 Convert 钮）。修前树上还可见 runtime 域 warn 已在场（日志内 `animation graph 'rigs/nope.bsn' could not be read`）——「运行态有 warn、作者态零提示」同屏，即 AN3 原始缺陷形态。
- 绿证：`t15t1_an3_badge_green.log` 三件全绿。
- **偏差**：badge 三形态截图（PX）未做——任务口径允许「headless 断言或截图」，红绿均以 headless 断言归档；真机截图腿归 T2 L8（M8 作者态红绿，届时编辑器实机截 badge 行）。

### AN4 🟡 「跳跃」无现成 clip → **已修（决策 2-B：自制 mini rig，未受阻）**

- 生成器 `loop/t15-live/make_hero_glb.py`（loop/ 不入库，保留可复跑/T18/T20 复用）→
  fixture 资产 `/Users/zhanglinbo/workspace/loop-mac/t15-anim/t15-anim/assets/models/hero.glb`（1,676 字节）。
- 形态：合法最小 glTF 2.0 GLB，节点 `Armature>Hips`，三 translation 动画：**Idle_Loop**（2.0s 首尾同帧循环）/ **Walk_Loop**（1.0s 循环）/ **Jump**（0.8s one-shot 跳跃弧，配 set `then: idle` 演示回落）——与 fixture 的 anim.bsn 三态逐字对齐验收句「待机↔行走↔跳跃」。
- 结构校验：GLB 双 chunk 长度/魔数、三动画命名、input accessor min/max（spec 必需，也是 Library 时长读法）、buffer 字节数全过（生成时内联断言脚本）。
- 装载活证：AN1 绿腿同日志——bevy_gltf 解析+三 clip 绑定静默（坏文件/坏 clip 名必有 warn）=**手造 glb 被 bevy_gltf 装载且按名解析**，方案风险表「1 小时不破切 A」未触发。
- jan 仍拷入 fixture（`assets/models/jan`），A 回落路径随时可用。

### AN5 ⚪ / AN6 ⚪ → 按裁定记档不修

- AN5（PIE 期间编辑视口照播）：T2 M12/L9 的记档点，本任务零改动（借还协议不受扰已由既有 stage 测试锚定）。
- AN6（门禁档位错位）：本报告门禁表即「任务相关门」显式行（stage 动画 4 文件+runtime 两文件+AN2 新腿）；QA 需要按 quick 门跑动画域时指明 stage 档。

## 二、fixture 工程（决策 6-A）

`/Users/zhanglinbo/workspace/loop-mac/t15-anim/t15-anim`（`jd new t15-anim`，`--no-git`）：anim.bsn（三态 set，sources=[models/hero.glb]，jump one-shot then:idle）+flow start_scene 重指向+jan+hero.glb。冷编两次落袋：红态 2m07s（无 animation feature）、绿态 19.8s（feature 增量）。**保留给 T2 全腿复用**（现为模块开=绿态）。

## 三、门禁（全部最终树重跑，日志归档 loop/reports/t15t1_*）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **CLEAN** | t15t1_fmt.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | **CLEAN（0 warning 行）** | t15t1_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | **CLEAN（0 warning 行）** | t15t1_clippy_physics.log |
| 单测 | `cargo test --workspace --lib --features dylib` | **exit 0**，scaffold teaches **89/89**（88+1） | t15t1_libtests.log |
| fast | `cargo xtask fast` | **2980/2980**（基线 2975+5 新：catalog 1+teaches 1+badge 单测 3）；全文复核 0 error/0 FAILED/0 Diff | t15t1_fast.log |
| 受影响域：stage 动画 4 文件 | `cargo nextest run --profile ci -p jackdaw --features dylib --test stage -E 'test(/animation/)'` | **35/35** | t15t1_stage_animation.log |
| 受影响域：runtime 两文件 | `cargo test -p jackdaw_animation_runtime --lib`（animation_sets/animation_graphs 测试族） | **exit 0** | t15t1_animruntime_lib.log |
| 受影响域：inspector | `cargo test --test inspector animation_cards` | **3/3** | t15t1_an3_badge_green.log |
| AN2 新腿 | `cargo nextest run --profile ci -p jackdaw_runtime --features animation --test animation_scene_load` | **1/1** | t15t1_an2_scene_load.log |
| 红绿日志 | fixture 游戏两次实跑 | 红=generic unresolved warn；绿=零 unresolved+绑定静默 | t15t1_an1_game_red.log / t15t1_an1_an4_game_green.log |

**warn 形态扫描归因**：门禁日志 WARN 形态扫描 50 条（libtests）全部为测试对象自身的负路径告警（terrain sidecar 拒载/prebuild 不存在工程/assets 目录外纹理/viewport 元数据坏档/asset.audit 缺文件等既有形态），**零动画域新增、零未归因**；clippy 双日志 0 warning。动画域 warn 形态（`animation state … wants clip …`/`could not read`）不在 lib 门出现，其活体在 fixture 红绿日志（测试对象本体）。

**磁盘**：门前 143Gi 可用；期间峰值两 target 并行（repo+fixture），未触警戒。

## 四、偏差清单（如实）

1. **⚠️（口径）方案「stage 动画 69 件」实为 35 件**：四文件 `#[test]` 实数 10+8+10+7=35，过滤腿 35/35 全绿；69 系方案调研口径偏差，门禁表按实数记。
2. **⚪ badge 截图未做**：headless 断言替代（任务允许）；PX 腿归 T2 L8。
3. **⚪ AN1 绿活证提前落袋**：方案把「fixture Play 播出动画」列为 T1 验收但腿形属 T2 L1/L5——本轮以「模块开关盘面产物+重建+装载绑定静默」完成机制半边，BRP 采样（`AnimationGraphPlayback.state` 数值断言）留给 T2。
4. **⚪ UnresolvedTypes remedy 路径与方案描述有出入**：游戏侧实走 runtime/apply 两条 warn 而非 catalog.rs remedy；判据（点名类型路径）仍达标，处置不变（doc 化留 T3）。
5. **⚪ AN3 红证断言域**：红档测试把「卡体」锚在了按钮包装层（绿轮才发现包装层级）；红证结构性成立（修前 fill 只产按钮、错误行零可能），红档日志如实归档不改写。
6. **⚪ jd 二进制 dylib 失配**：`target/debug/jd` 直接执行遇 rust std dylib 失配（Abort trap 6），一律改 `cargo run -p jd`（t14 先例同款）——工具面注记，非本任务产物。

## 五、给 QA 的注意事项

1. **门禁表新增显式行**：`cargo xtask integration`（与 release-gate）现已**每次自动附跑** AN2 腿；若 QA 单独写门禁表，请用 §三 AN2 行的原命令。该腿首次编译 jackdaw_runtime+animation 增量约 11s（暖）。
2. **fixture 现为绿态**（animation=true）：T2 若要复现 AN1 红态，把 `jackdaw.toml [modules] animation` 改回 false+features 摘除 animation 再冷编；红态日志已在档可对照。
3. **模块 UI 视觉腿**（L1 的 PX 半边）未跑：File>Modules 应出现 Animation 开关（数据驱动，headless 已证 catalog/模板/jd 三面）；QA 在编辑器实机核一眼即可。
4. **badge 行为**：全 good 卡零噪音（不添视觉负担）；badge 是行+tooltip，非 gate，误报面=「文件在盘但 Library 尚未索引完」已防（不报，运行时 warn 兜底）。若 QA 实机看到「在盘未索引却报缺失」，按 AN7 立账。
5. **teaches 计数**：scaffold 89、fast 族 2980，后续任务基线以此为准。
6. **hero.glb 生成器**在 `loop/t15-live/make_hero_glb.py`（不入库）；若 T2/T18/T20 需要改 clip，改脚本重跑即可，勿手编二进制。
7. T12/T13/T14 回归：fast 2980 全绿+stage 全绿（含 R1 修复面 guards/keyframe_undo 所在的 guards 族未动，fast lib 覆盖）；integration 全档本轮未跑（T1 门禁口径不含，主链由 QA 按 T14 口径执行）。

—— 程序 agent，2026-10-30
