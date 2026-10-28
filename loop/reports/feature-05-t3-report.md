# feature-05 任务 3 报告：R3 Add 菜单 E2E 真机验证 + 工具链锁定 + 全量门收尾

> 多 Agent 开发循环 · 程序（Rust/Bevy 工程师）· 2026-10-23/24
> 分支 `loop/interaction-ux`（基于 main 113732ba，任务 1/2 已合入）· 提交 f6c12924
> 需求来源：`loop/plans/feature-05-interaction-ux.md` §R3 / D10 + 任务 3 节

## 1. R3 五项验收（D10，真机，全部走真实 UI 输入）

真机环境：`target\debug\jackdaw.exe`（T3 代码态重建）+ `JACKDAW_OPEN_PROJECT=my-game`，
驱动方式 = BRP `input.pointer`（合成 winit 事件，下游 picking/UI 全当真）+ BRP 断言 +
双通道截图。**坐标定位法（本任务新方法论，可复用）**：`world.query` 拉取全部
`bevy_ui::widget::text::Text + ComputedNode + UiGlobalTransform` 行——`UiGlobalTransform`
为**物理像素**（验证：点击 逻辑(107,167) 命中 物理(160,250) 的 Spot Light 树行），
`input.pointer` 坐标 = 物理/1.5（scale_factor 1.5）。不再依赖截图目测（本环境截图只出
CDN 链接，无法目检；改用像素 diff + UI 文本 dump 作客观证据）。

| # | 验收项 | 结论 | 证据 |
|---|---|---|---|
| 1 | Add 菜单含 Cube/点光/平行光 | ✅ 全通 | `jackdaw/operators` 断言三 id 在场；真实点击标题栏 Add（逻辑 133,17.3）→ 下拉打开，分组结构完整 dump：Empty/Prefab/Reference Image + **3D Objects**/**Lights**/Cameras/Audio & Animation/Environment/Terrain/Multiplayer/UI/Assets；截图 `r3-02-addmenu-3dobjects-window.png`（3D Objects 子菜单含 Cube 行，物理 518,179）、`r3-03-addmenu-lights-window.png`（Lights 子菜单含 Point Light 行，物理 543.5,212） |
| 2 | 创建后 viewport 立即可见 | ✅ 全通（Cube + Point Light 双验，全部真实 UI 点击） | Cube：悬停 3D Objects（dwell 展开子菜单）→ 点击 Cube 行 → `scene_bsn` 精确 `#Cube` 计数 1→2；Point Light：悬停 Lights → 点击行 → `#Point Light` 0→1。新 Cube bsn 含 `Brush`（cuboid 0.5）+ `Transform`（原点），初始相机 (0,4,8)→原点必在视野。视口像素 diff（boot vs 添加后）：**8.43%** 像素变化（701,722 px，容差 12）＝新实体确实渲染 |
| 3 | Inspector 编辑生效 | ✅ Transform 全通；⚠ 灯光卡不可达（见 §2 发现 1） | 真实 UI 路径：outliner 点击新 Cube 行选中（status.selection 确认）→ 展开 Transform 区 → 点击 translation.x 数字框 → Backspace×4 清空 → 合成输入 `2` → Enter → `scene_bsn` 断言 **translation.x=2.0** ✔；视口像素 diff 2.47%（立方体移动）。灯光颜色编辑被 §2 发现 1 阻断（Inspector 无可达的 PointLight 卡片） |
| 4 | 保存重开仍在 | ✅ 全通 | BRP `scene.save`（finished）→ 文档含新实体（`assets/scene.bsn` 校验 `#Cube`×2、`#"Point Light"`、x=2.0）→ 杀进程 → 同工程重启 → 就绪后 `scene_bsn`：**#Cube×2、Point Light×1、translation.x=2.0 全保持** |
| 5 | UI 入口可用性 | ✅ 通（含 1 个观测限制） | outliner `Add Entity` 按钮（物理 107,167）真实点击 → 可搜索 picker 打开（标题 "Add Entity"、搜索框物理 612,157）；输入 "cube" 过滤后行点击创建第 3 个 Cube（bsn 2→3 ✔）。限制：过滤过程的行快照因行位漂移未能干净 dump（截图 `r3-07/07b/07c` 留档）；另注：picker 输入框不自动聚焦，需先点击（用户可发现性 OK） |

**链路结论**：Add 菜单 → picker → operator → 文档（含 undo 栈）→ 保存/重载 全链路真实
UI 驱动下无断点；「用户实测可能不通」的真因不在链路，落档为两条感知问题（§2）。

**现场清理**：QA 产生的 3 个 Cube + 1 个 Point Light 已通过真实 UI（Esc 清焦点 → 树行点击
选中 → `entity.delete`）逐个删除并 `scene.save`，my-game 场景恢复原 6 行
（Cube/Spot Light/Cube2/3/4/Root），状态栏 12 entities / 4 meshes / 2 lights 与开机一致。
注：`entity.delete` 曾连续 Cancelled——根因是 picker 遗留的**键盘焦点占用**
（`can_act_on_entities` 的 `keyboard_is_spoken_for` 门拒绝），Esc 释放后立即通过；这本身
印证了 T2 的 Esc 分层语义在真机工作正常。

## 2. 真机发现（缺陷/感知问题，未修，按任务要求记档）

1. 🔴 **灯光实体在 Inspector 无可达编辑卡片（用户感知问题 #1，主候选）**：选中
   `Point Light`（或任一灯）后，Inspector 分类条（object/mesh/modifiers/material/
   physics/components 六分类）中：object 只显示 Visibility+Transform 两卡；components
   分类为空（仅 Filter 行）；其余分类无灯卡。`bevy_light::point_light::PointLight` 在
   `seed_default_categories` 无映射（落到 "components" 兜底，但 components 面板不渲染
   它）。**灯的颜色/强度/范围在 Inspector 不可编辑、不可发现**——建议主控排期补
   light 卡分类映射（一行 `set_component_category` + 卡片渲染核实）。
2. 🟡 **分类条可发现性差**：Inspector 分类条是纯图标竖列（无文字、仅 hover tooltip），
   真机盲找 Light 卡时需逐个点开；配合发现 1，构成「Inspector 编辑灯光不可达」的完整
   感知问题。
3. ⚪ **pin_project 只回钉 bevy，不统一 range 依赖**（B 节根因，见 §3）：编辑器把工程
   lockfile 的 bevy 移到自家 rev，但 gpu-allocator/cpal/gilrs-core 这类
   `windows >=x, <=0.62` 宽范围依赖保持旧解（0.61.3），与 wgpu-hal 30.0.1 的
   windows 0.62.2 形成类型冲突（E0308/E0277，编辑器自身 lockfile 是统一到 0.62.2 的）。
   建议后续在 `pin_project` 后补一次 `cargo update -p windows@0.61.x`（或像 shim 那样
   种子化共享闭包）。本任务按最小修复面只改了用户工程（§3），未动 pin_project。
4. ⚪ 编辑器进程一次静默消失（无 panic/崩溃事件，日志止于一次 operator 派发；疑似环境/
   人工干预，重启后不复现）：记录备查，不计缺陷。

## 3. 工具链锁定（B：模板 + 用户工程 + Play）

**B1 模板**（入库 diff，2 文件 +38 行）：
- 新增 `crates/jackdaw_scaffold/templates/game/rust-toolchain.toml.template`：占位符
  `{{rust_toolchain}}`，注释说明「钉住到脚手架这一版编辑器所用的 rustc；rustup 首用自动
  安装；删除则回落默认工具链」。
- `substitute_placeholders` 增加一条替换：`{{rust_toolchain}}` →
  `jackdaw_env::RUSTUP_TOOLCHAIN`（与现有占位符体系一致；该常量即构建此编辑器的
  rustup channel，本机 1.99.0）。
- 测试：`tests/sdk_layout/template_versions.rs` 新增
  `scaffolded_games_pin_the_editors_toolchain`（占位符在场 + 真实 scaffold 后文件解析为
  toml 且 channel 等于 `jackdaw_env::RUSTUP_TOOLCHAIN` + 无未填占位符）。sdk_layout
  8/8 通过。**不动 extension 模板**：扩展经 shim 构建，shim 已自写 rust-toolchain.toml
  （build.rs:237-244 既有机制）。

**B2 用户工程 my-game（已明确授权工具链文件；lockfile 为最小真因修复，特此说明）**：
- 写入 `C:\Users\linbo.zhang\Projects\my-game\rust-toolchain.toml`（channel 1.99.0 +
  上述同款注释）；`rustup show` 实测解析为 1.99.0（原默认 stable=1.96）。
- **追加真因修复**：仅钉工具链后 PIE 构建仍失败——wgpu-hal 30.0.1（要求 windows 0.62.2）
  与 gpu-allocator 0.28.0（宽范围 `>=0.53,<=0.62`，lockfile 旧解 0.61.3）类型冲突
  （§2 发现 3）。对 `Cargo.lock` 做**三行**最小对齐：cpal/gilrs-core/gpu-allocator 的
  `"windows 0.61.3"` → `"windows 0.62.2"`（三者 manifest 范围均允许；与编辑器自身
  lockfile 的解一致；ipc-channel 的 0.61 精确要求不动）。`cargo metadata --locked`
  通过（lockfile 与 manifests 一致）。备份 `Cargo.lock.r3bak` 留在工程内。

**B3 Play 真机验证（全链路走通）**：
- 重开编辑器即触发 PIE 后台预构建：stderr `PIE: pre-building...` →
  **`PIE: refreshed project types from schema (1 project components)`**（构建+schema
  提取器成功；对比任务 2 时同工程 build failed rustc 1.96）。
- `my-game.exe`（219MB debug）落盘于 `.jackdaw\target\game\debug\`。
- 真实 UI：点击标题栏传输条 Play 按钮（物理 1372.5,26）→ `jackdaw/wait until=
  pie_running` 返回 `{"pie":"running"}`，`my-game.exe` pid 5268 实跑（截图
  `01-pie-running`）；Stop 按钮停止 → status `pie: stopped`、进程退出。
- 构建时长未超预期（预构建复用缓存约 3.5 分钟，无需长等）。

## 4. 各门退出码

| 门 | 退出码 | 备注 |
|---|---|---|
| `cargo xtask fast` | **0** | **2802 passed / 2 skipped**（任务 2 基线 2802/2 持平；本任务零新增 lib 测试）。quick tier：`cargo fmt --all -- --check` 0；`cargo clippy --workspace -- -D warnings` 0（4 条 build script lld 告警为既有且忽略 -D） |
| `cargo xtask integration` | **0** | **4938 passed (1 flaky) / 3 skipped**（任务 2 基线 4937/3 → +1，恰为本任务新增 sdk_layout 模板测试） |
| `cargo doc --locked --workspace --document-private-items --no-deps` | **0** | 9 条 warning 逐条核对**均非本 diff**：4×build script 既有 lld 警告 + 任务 1 引入的 `system_access_entries`→私有 `ambiguities_for` 链接（feature-04-t3 已记录的遗留）等；改动 crate（jackdaw_scaffold）零 rustdoc 告警 |
| doctests（`cargo test --locked --workspace --doc --features bevy/dynamic_linking --no-fail-fast`） | **101（既有，非回归）** | 日志尾 `error: 3 targets failed`：失败集合**恰为** `-p jackdaw_bind --doc`、`-p jackdaw_feathers --doc`、`-p jackdaw_node_graph --doc`，与 feature-01~04 基线逐项相同，零新增失败 → 非回归（日志 `loop/reports/gate-doctests-t3.log`） |

## 5. 自查 diff 与提交

入库改动（`git status` 核对，loop/ 不入库）：
- `crates/jackdaw_scaffold/templates/game/rust-toolchain.toml.template`（新增）
- `crates/jackdaw_scaffold/src/lib.rs`（+4：占位符替换一条）
- `tests/sdk_layout/template_versions.rs`（+34：新测试）

提交信息：`Pin the scaffolded toolchain and verify the Add menu end to end`。

用户工程侧改动（不入库，均已在上文说明）：
- `my-game/rust-toolchain.toml`（新增，授权内）
- `my-game/Cargo.lock`（3 行 windows 边对齐；备份 `.r3bak`）
- `my-game/assets/scene.bsn`（QA 实体已清理后重新保存；内容与原场景等价——实体集合
  恢复原 6 行，仅 bsn 序列化层面可能有等价重排）
- `my-game/.jackdaw/`、`screenshots/`（编辑器构建产物与 QA 截图，gitignore 覆盖）

## 6. 遗留

1. 发现 1/2（灯光 Inspector 卡片不可达 + 分类条可发现性）——建议下轮修复（小改）。
2. 发现 3（pin_project 不统一 range 依赖）——建议后续任务处理；当前靠工程侧 3 行对齐。
3. QA 截图无法在本环境目检（图片读取只回 CDN 链接），证据链以 bsn 断言 + 像素 diff +
   UI 文本 dump 为准；截图文件已归档 `loop/reports/r3-add-e2e/` 供人工复核。
