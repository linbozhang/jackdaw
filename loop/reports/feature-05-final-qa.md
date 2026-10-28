# feature-05 终验报告：任务 3 验收 + 专项「工具交互与视口体验」整体终验

> 多 Agent 开发循环 · QA（验收工程师）· 2026-10-24
> 验收对象：`loop/interaction-ux` @ `f6c12924`（基于 main `113732ba`；diff = scaffold/lib.rs + rust-toolchain.toml.template + sdk_layout/template_versions.rs 共 3 文件 +46 行，亲核与声明一致，工作树 clean）
> 程序报告：`loop/reports/feature-05-t3-report.md` · 方案：`loop/plans/feature-05-interaction-ux.md` 任务 3 节 + QA 验收清单节
> **专项级结论：PASS**

## 0. 结论速览

| 项 | 结论 |
|---|---|
| 门（fast / integration / doc / doctests） | ✅ 0 / 0 / 0 / 基线（QA 亲跑，§1） |
| 任务 3 模板机制（B1） | ✅ 占位符体系一致、机制闭环亲核（§2.1） |
| 用户工程改动（B2） | ✅ rust-toolchain.toml 1.99.0 + Cargo.lock 恰 3 行，逐行亲核（§2.2） |
| A 五项验收（D10） | ✅ 证据链抽查三处逐位吻合 + QA 真机独立复验 3 项（§3、§4） |
| concerns① 定性 | **程序结论需修正**：灯卡在 Components tab **可达**（程序称不可达）；真实根因=分类映射缺失+图标条可发现性（§5） |
| Play（B3） | ✅ QA 亲跑全链路：Play→running（pid 实跑）→Stop→退出（§4.3） |
| 用户报障 ①②③ + 插入任务#1 | ①已修 ②根因定位（定性修正）待下轮修 ③已修 插入#1 完成（§6） |

## 1. 门（QA 自己跑，最终代码态 f6c12924）

| 门 | 退出码 | 数字 | 日志 |
|---|---|---|---|
| `cargo xtask fast` | 0 | **2802 passed / 2 skipped**（与 T2/T3 基线持平） | `gate-xtask-fast-finalqa.log` |
| `cargo xtask integration` | 0 | **4938 passed / 3 skipped**（含新增模板测试 #1404 `scaffolded_games_pin_the_editors_toolchain` PASS；本轮无 flake） | `gate-xtask-integration-finalqa.log` |
| `cargo doc --locked --workspace --document-private-items --no-deps` | 0 | 9 warning 逐条核对**均存量非本 diff**（4×build script lld、`system_access_entries`/`pie` 私有链接遗留等；**jackdaw_scaffold 零告警**） | `gate-doc-finalqa.log` |
| doctests `--workspace --doc --features bevy/dynamic_linking --no-fail-fast` | 101（既有基线） | 失败集合恰为 jackdaw_bind / jackdaw_feathers / jackdaw_node_graph 三目标，与 feature-01~04 基线相同，零新增 | `gate-doctests-finalqa.log` |

二进制核验：`target\debug\jackdaw.exe`（00:41:39）晚于 f6c12924（00:34:55）且树 clean → 真机验收即 HEAD 态。

## 2. 任务 3 规格

### 2.1 模板工具链（B1）——机制闭环 ✅

- diff 亲核：template 8 行（`channel = "{{rust_toolchain}}"` + 注释）；`substitute_placeholders` +4 行（`.replace("{{rust_toolchain}}", jackdaw_env::RUSTUP_TOOLCHAIN)`，与 `{{bevy_dependency}}`/`{{jackdaw_version}}` 既有占位体系同型）；测试 +34 行（占位符在场 + 真实 scaffold + toml 解析 + channel 等于 `RUSTUP_TOOLCHAIN` + 无残留 `{{`）。
- 值链亲核：`jackdaw_env/build.rs` 取 `rustc -vV` 的 **release 精确版**（非 moving stable），本机 rust-toolchain.toml（1.99.0-x86_64-pc-windows-msvc）→ 常量 `RUSTUP_TOOLCHAIN = "1.99.0"` → 脚手架产物 channel=1.99.0。机制自洽。
- extension 模板不动（shim build.rs:237-244 自写工具链文件，既有机制）——与报告声明一致。

### 2.2 用户工程改动（B2，git 不管辖，读文件核实）✅

- `C:\Users\linbo.zhang\Projects\my-game\rust-toolchain.toml`：`channel = "1.99.0"` + 语义注释，与模板机制一致（= 编辑器构建所用 rustc）。
- `Cargo.lock` vs `Cargo.lock.r3bak`（Compare-Object 全量）：**恰好 3 行差异**，均为 `"windows 0.61.3"` → `"windows 0.62.2"`，归属 **cpal（L2350）/ gilrs-core（L2918）/ gpu-allocator（L3020）** 三包，行数 6922=6922——与报告 §3 B2 所述逐项一致；备份在工程内。

## 3. A 五项验收：证据链抽查（程序档案亲核）

| 抽查点 | 程序声称 | QA 亲核结果 |
|---|---|---|
| bsn 计数 | `#Cube` 1→2 | `r3-add-e2e/bsn-names.txt`：#Root/#Sun/#Cube/#Cube2/#Cube3/#Cube4/**#Cube**（2 个 #Cube）✅；`pointlight-bsn-full.txt` 含 `bevy_light::point_light::PointLight { range: 10.0 }` ✅ |
| 像素 diff | 8.43%（701,722 px，容差 12） | QA 用 `pixdiff.ps1` 对档案 `00-boot-viewport.png` vs `r3-04-after-pointlight-viewport.png` 复算：**8.43% / 701,723 px / tol 12**，逐位一致 ✅ |
| UI dump | Add 菜单 3D Objects 子菜单 Cube 行 物理(518,179) | `group3d.json`：3D Objects [239,172]、Cube [518,179]、Lights [218.5,205]——坐标逐位一致 ✅ |

（QA 复跑时 Add 菜单展开坐标与档案完全一致：dropdown 3D Objects (239.0,172.0)、Cube 行 (518.0,179.0)。）

## 4. 真机复验（QA 亲跑，HEAD 二进制，my-game，全部真实 UI 输入 + BRP 断言）

### 4.1 Add Cube E2E（必复验项 1）✅

- 标题栏 Add（逻辑 133,17.3）→ 下拉开 → 悬停 3D Objects 展开 → 点 Cube 行 → `scene_bsn` 亲数 `#Cube` **1→2**（新 Cube 为文档末尾节点）。
- outliner 点击新 Cube 行（146,456）→ status `Entity: Cube`；Inspector 分类条点回 Object tab → Transform 卡**点击展开**（卡默认折叠态）→ translation 行 X/Y/Z + ScrubNumberInput 定位（组件查询 bbox：X 输入框 cx=1450 w=170）。
- 数值编辑亲证：单击+打字为 scrub 累积（两次输入叠加出现 x=22.0——本身即证明键盘直通文档）；**dblclick 全选 + Delete + 输入 `2` + Enter → `scene_bsn` 断言 translation.x = 2.0** ✅（截图 `f5-after-translate-viewport.png`）。

### 4.2 保存重开保持（必复验项 2）✅

- `scene.save`（finished）→ 落盘文件亲读：`#Cube`×2、`#"Point Light"`×1、lastCube x=2.0 → 杀进程（pid 85476 前任）→ 重启就绪 → `scene_bsn`：**Cube×2 / PointLight×1 / lastCube x=2.0 全保持** ✅（截图 `99-restarted`）。
- 现场清理（UI 选中→entity.delete，含灯）：终态 **12 entities / 4 meshes / 2 lights**，与开机状态栏一致；`scene.save` 落盘恢复原 6 行实体集合。

### 4.3 Play 冒烟复跑（低成本复跑，构建已缓存）✅

- 真实 UI 点 Play（物理 1372.5,26）→ `jackdaw/wait until=pie_running` 返回 `{"pie":"running"}`，**my-game.exe pid 28700 实跑（605MB）**，截图 `f5-pie-running-window.png`（Stop 按钮 UI dump 定位在物理 1503.5,26）→ 点 Stop → `pie: stopped`、**进程退出** ✅。与程序 B3 证据一致，且覆盖了程序记录未覆盖最终二进制的缺口（程序真机记录 23:18~00:09 早于 00:41 最终链接，本节补齐）。

## 5. concerns① 重点核实（用户报障② 闭环定性）——**程序定性部分修正**

**真机证据（QA 亲测，两次独立会话）**：

1. 选中**原有 Spot Light**（outliner UI 点击）→ Object tab（默认）只显示 Visibility+Transform 两卡（与用户感知「只显示 Transform+Visibility」吻合）；点击分类条**第二个图标**（物理 1330,172.5）→ Components tab 打开（"Components" 标头出现）→ 面板显示 **SubEntity<RenderApp> / SyncToSubWorld<RenderApp> / SpotLight 三张卡**（SpotLight 卡 [1452,351]，dump 存档 `l7-icon-1330-173.json`）。
2. **新建 Point Light**（BRP `entity.add.point_light`，bsn 0→1）→ outliner UI 选中 → Components tab → **PointLight 卡可见**（[1454,351]，存档 `newpointlight-components-tab.json`）。
3. 数据在的双腿证明：**活 ECS** `world.query` 过滤 SpotLight → 1 个持有者（entity 4132v0）；**文档/存档** `assets/scene.bsn` 的 `#"Spot Light"` 节点含完整 `bevy_light::spot_light::SpotLight { color, range }` 字段、`#Sun` 含 `DirectionalLight`、`#"Main Camera"` 含 `Camera3d`。

**代码链定性（全部亲读源码）**：

- `crates/jackdaw_api_internal/src/inspector.rs::seed_default_categories` 的映射表**只覆盖** Transform/Name/Visibility/Node/Brush/ModifierStack/Material/Avian——**无任何 `bevy_light::*`、`Camera3d`、`Camera` 映射** → `category_for` 落 `"components"` 兜底。
- 卡片创建链通畅：AST 过滤（component_display.rs:446-462，bevy 前缀组件需在 authored_type_paths）通过——`register_entity_in_ast`（scene_io/registration.rs）全量同步实体反射组件入 AST，`bevy_light::` 不在 `SKIP_COMPONENT_PREFIXES`（仅 `bevy_light::cascade::Cascades` 精确跳过）。
- 卡片可见性：`filter_inspector_components`（component_display.rs:1524）按 `category_for(type_path)==active_cat` 显隐——灯卡只在 Components tab 激活时显示；`ActiveInspectorCategory` 默认 "object"，分类条为**纯图标竖列**（程序发现 2）。

**结论（修正程序报告 §2 发现 1 的机制描述）**：

- 程序所称「components 面板不渲染它」「components 分类为空（仅 Filter 行）」**不成立**——灯组件卡在 Components tab **存在且可达**（两实体两轮真机证实）。程序档案 light-comps*.json 的空面板成因无法确证（其 tab 点击生效——object 卡确实隐藏了——但无灯卡；可能与其会话状态/点击目标有关）。
- **用户报障②「Camera/Sun 只显示 Transform+Visibility」被真实解释且完全成立**：数据在（ECS+文档+存档三腿），显示层**缺分类映射**把灯/相机卡埋进兜底 Components tab + 默认打开的 Object tab 只有 Transform/Visibility + 图标条无文字——普通用户找不到。**不是渲染缺陷，是信息架构/可发现性缺陷**。
- 对下轮修复范围的影响：比程序建议更收敛——补 `set_component_category`（PointLight/SpotLight/DirectionalLight/Camera3d/Camera → object 或新建 Lights 类）即可让灯卡进默认视野；「components 面板渲染核实」一项可从范围移除。附带建议处理分类条可发现性（发现 2）与粘性空 tab（见发现 3）。
- 残余未验：灯光 color 字段的**实际编辑**（程序与我均未做——原以为被阻断；卡的可达性已证，字段编辑器与已验通的 Transform 同为通用反射/ScrubNumberInput 通道，风险低）。

## 6. 专项 #5 终验（R1–R4 + 用户报障处置）

| 项 | 依据 | 结论 |
|---|---|---|
| R1 视口跳变修复 | T1 QA 报告（真机 13+1 轮 press 跳变=0、环视精确 0.9rad、判别档案逐数核对）——本轮引用，不复跑 | ✅ 已修，已验 |
| R2 工具取消语义 | T2 QA 报告（机制/幂等/双语义代码核 + 真机两工程 5 例×两遍 + 9 类矩阵逐行）——本轮引用 | ✅ 已修，已验 |
| R3 Add 菜单 E2E | 本报告 §3/§4（程序五项 + QA 抽查三处 + 独立复验 Add Cube/编辑/保存重开/清理/Play） | ✅ 完成（灯 color 编辑残余，§5） |
| R4 交互驱动手册 | loop/qa/manual.md + 脚本链，T1 建、T2/T3/本轮 QA 复用（本轮新增 UI dump 组件定位、ScrubNumberInput bbox 查询、粘性 tab 复位经验） | ✅ 交付可用 |
| 门/边界 | 四门全绿；diff 恰 3 文件无越界；loop/ 不入库 | ✅ |

**用户三条报障处置**：

1. **① 视口右键按下视角重置 → 已修复**（T1：fly 上升沿 3 帧抑制；真因=grab 切换瞬间环境合成巨量 raw delta，判别档案落档）。
2. **② Inspector 缺卡（Camera/Sun 只显示 Transform+Visibility）→ 根因定位，待下轮修复**（本轮定性修正：卡可达但被埋，缺分类映射是根因；修复面收敛为映射补齐 + 可发现性，§5）。
3. **③ 标尺/工具无法取消 → 已修复**（T2：modal.cancel 通用 Esc 链一处修全部 + 标尺 RMB；真机逐例）。

**用户插入任务#1（Outliner Add 菜单建实体 E2E）→ 完成**：D10 五项全过（菜单内容/viewport 可见/Inspector 编辑/保存重开/入口可用性），链路无断点，真因归 ② 的可发现性而非功能断点。

## 7. 发现（分级）

| 级别 | 责任方 | 问题 |
|---|---|---|
| 🟡 | 程序（报告口径） | **concerns① 机制描述错误**（§5）：「components 面板不渲染灯卡/分类为空」被真机证伪；真实机制=分类映射缺失导致卡落兜底 tab。影响下轮修复范围评估，务必以本报告 §5 为准 |
| ⚪ | 程序（QA 脚本） | `r3-menu-cube.ps1` 断言正则 `^#Cube\r?$` 不匹配 bsn 缩进行，计数恒 0（复跑必 throw）；程序当时的 E2E 结论实际依赖后续人工计数而非该断言。QA 已用正确正则（`^\s*#Cube\s*$`）亲核 1→2。建议修脚本 |
| ⚪ | 程序（报告口径） | 报告 §1 表 3 称「Backspace×4 清空」——真机实测 ScrubNumberInput **单击后 Backspace 不清空**（scrub 模式数字累积；程序档案 lastcube.txt 的 0.002 中间值即此症状）。实测有效打法=**dblclick 全选 + Delete + 输入 + Enter**。结论（x=2.0）不受影响，QA 已亲证 |
| ⚪ | 产品（下轮一并修） | 分类 tab 粘性 + 兜底 tab 无卡时空面板：选中 Cube 停在 Components tab → 面板只剩 Filter 行（QA 复跑时亲历，导致 r3-inspector.ps1 假失败）。与报障② 同源的可发现性问题 |
| ⚪ | QA 基建 | ScrubNumberInput 值不是 Text widget，UI 文本 dump 不可见——已沉淀「组件查询 bbox 定位」法（world.query by `jackdaw_feathers::number_input::ScrubNumberInput`）；本环境读图仍只回 CDN 链接（与程序环境一致），视觉证据继续以 bsn/像素 diff/UI dump 三件套为准 |
| ⚪ | 程序（转记维持） | 发现 3 pin_project 不统一 windows range 依赖（工程侧 3 行手工对齐是权宜）——留 backlog |

## 8. 交接

- QA 档案：`loop/reports/f5-final-qa/`（lightprobe/translate/persistence/play 各步 dump+截图+bsn）、四门日志 `gate-*-finalqa.log`；新脚本 `loop/qa/f5-final-lightprobe*.ps1`、`f5-final-translate.ps1`。
- my-game 终态：场景恢复原 6 行实体集合并已保存（12/4/2 与开机一致）；`Cargo.lock.r3bak` 备份仍在工程内。
- 下轮建议（报障② 修复任务）：分类映射补齐（含 Camera3d/Camera）+ 分类条可发现性 + 粘性空 tab 兜底；灯光 color 编辑补一次真机验证。

## 9. 结论

**专项 #5「工具交互与视口体验」：PASS**。四门全绿、任务 1–3 逐项验收通过、用户三条报障两条修复一条定位待修、插入任务#1 完成、用户工程恢复原状。唯一遗留（报障②）已收敛为明确的小修范围并修正了机制定性。
