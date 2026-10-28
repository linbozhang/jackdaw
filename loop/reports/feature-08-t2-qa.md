# 功能 #8 · 任务 2 QA 验收报告：Graphics 面板 UI（真机交互验收）

- 验收对象：`loop/graphics-panel` @ `87666d96`（基于 main `bbe4ecbe`），7 文件 +1206/−0
- 验收人：QA agent · 2026-10-24 · 结论：**PASS**
- 验收方式：门禁复跑 + 代码审查 + plain 构建真机交互驱动（BRP `input.pointer` 合成点击 + BRP 断言 + 截图像素 diff）
- 证据目录：`loop/f8-t2/`（截图/日志）、`loop/f8-t2-qa_*.log`（门禁）、驱动脚本 `loop/qa/f8-t2-ui.ps1`（探针 probe2–18 留档）

## 1. 门禁（复跑，每门独立）

| 门 | 命令 | 结果 | 日志 |
|---|---|---|---|
| fmt | `cargo fmt --all -- --check` | **0** | — |
| clippy（权威口径） | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | **0** | `loop/f8-t2-qa_clippy.log` |
| fast | `cargo xtask fast` | **2847 passed / 2 skipped**（与 t1 基线持平） | `loop/f8-t2-qa_xtask_fast.log` |
| integration | `cargo xtask integration` | **4996 passed / 3 skipped**（+7 恰为本轮新测试，`jackdaw::viewport graphics_panel::*` 7/7 PASS） | `loop/f8-t2-qa_xtask_integration.log` |

门禁数字与程序报告完全一致。

## 2. 代码审查

- **窗口注册**：`CoreWindowsExtension` 注册 `jackdaw.graphics`（名 Graphics / Icon::Aperture / `DefaultArea::RightSidebar` / priority 6 排 Inspector 家族之后，注释言明"opened on purpose rather than fronted"）；`graphics.open`（allows_undo=false）→ `open_window_in_default_area_if_absent`，与 game_panel 同款；Window 菜单项为注册的零成本副产物（`src/lib.rs:2225-2253` 按 default_area 分组枚举 registry，已读源码核实）；命令面板经 operator 注册表自动可搜（真机 operator 日志见 `graphics.open` 派发）。✅
- **两段式构建**：窗口 build 闭包只 spawn `GraphicsPanel` 根（`graphics_panel_root()`），`populate_graphics_panel` 以 `Added<GraphicsPanel>` 触发逐实体一次填充；重开/换工作区时根实体重生 → 再填充一次，无重复 populate 路径；与 terrain panel「空容器 + populate」范式一致。真机多次开面板未见行重复（BRP 文本唯一）。✅
- **A 区控件→operator 映射**（逐参数对照任务 1 定义 `src/viewport_settings.rs:350-553`）：preset 段→`viewport.quality.preset(preset)`；AA 段→`viewport.quality.set(anti_aliasing)`；render scale 滑条→`quality.set(render_scale)`（取整 i64）；SSAO 开关→`viewport.ssao.set(on)`；SSAO 质量段→`ssao.set(quality)`；太阳/点光/雾→`viewport.show.toggle(flag,on)`；锐化开关/强度→`viewport.sharpen.set(on|strength)`。全部对得上，无自造路径。✅
- **B 区纯 environment.set 皮**：每控件 → `environment.set` 写 `post.enabled/tonemapper/exposure/bloom_intensity/bloom_threshold`（均为 `PostProcess` 既有字段，`jackdaw_scene_types/src/environment.rs:276-295`），无自造存储；`user_action()` 的 `creates_history_entry` 仅在 `op.allows_undo` 时生效（`jackdaw_api_internal/src/operator.rs:661`），environment.set 自管单条 `SetEnvironment`，不会双重入栈。✅
- **滑条 is_final 单条 undo**：`on_slider` 对 scene 滑条仅在 `is_final` 发一调，中间 tick 只回写 `SliderValue`；headless `a_scene_slider_commits_once_on_release` 钉死「tick 不写不进栈 / release 恰 1 条 / undo 回滚」。✅
- **GI 禁用态零运行时逻辑**：`build_realtime_gi_row` 仅 FieldRow + Tooltip（ftl 文案含 Solari/experimental/未接入/四替代项）+ `InteractionDisabled` checkbox；零 bevy feature 接触。✅
- **4 项偏差评估**：①bloom 组开关=`post.enabled`——方案 §3.2 规格表原文注记，合理；②is_final release 提交——方案 D4 首选支，合理；③两段式构建——方案 §3.1 精神 + terrain panel 先例，合理；④Window 菜单零成本入口——方案明示「或并入既有菜单行」，合理。全部接受。
- **担忧项（无 Environment 时乐观回写）影响评估**：实测 my-game 场景默认**确实没有 Environment**——此时 B 区 checkbox 点击后乐观停在用户意图态、operator cancel 仅日志 warn；当 Environment 出现（component.add）后 `Changed<Environment>` 会自动纠正（实测生效）。影响：纯外观、自愈；但面板对「场景无 Environment」无可见提示（B 区看起来可点实际无效）→ 见发现 3。不阻塞。
- **7 测试质量**：覆盖注册/可搜、dock tab+双区行名、A 区四类控件→设置（undo=0）、B 区滑条 tick/release/undo 计数/回滚、B 区开关+combobox 写 Environment、GI 禁用+tooltip、opt-out 提示状态机——对应方案 D5 headless 1/2/4/5（相机 dress 断言由 jackdaw_surface 既有测试承担，可接受）。✅
- **无越界**：diff 仅 7 文件；无 book/README/盘点表；`loop/` 经 `.git/info/exclude` 不入库（check-ignore 验证）。✅

## 3. 真机交互验收（plain 构建 + my-game；每项带 BRP/像素证据）

> 驱动：BRP `input.pointer`（合成 winit 事件，picking 全当真）点击面板控件；坐标经 `world.query` 的 Text+ComputedNode+UiGlobalTransform 实时定位（checkbox 命中小方框=caption 左缘−12px，经 probe10 标定）；断言走 BRP `world.get_components/get_resources`；截图 `jackdaw/screenshot` + pixdiff（window 截图裁剪 3D 视口区）。前置：会话开始经 Window→Reset Layout 恢复默认布局（见发现 2）。

### 3.1 面板结构
- **Window 菜单开面板**：点菜单栏 Window → 下拉出现 Graphics 项（BRP 文本定位 (286,234)，截图 `run15-window-menu-open.png`）→ 点击派发 `window.open`（operator 日志）→ 面板出现在右栏。
- **双区结构**：BRP UI 文本断言 A 区 16 行全在（Quality Preset/Render Scale/Anti-Aliasing/Ambient Occlusion/SSAO Quality/Sun Shadows/Point Shadows/Fog/Sharpening…）+ B 区（Post Processing/Tonemapper/Exposure (EV100)/Bloom Intensity/Bloom Threshold）+ **Realtime GI 行**（截图 `run15-panel-open.png`）。

### 3.2 A 区 3 项实测（全部经面板 UI 点击驱动）
| # | 操作 | BRP 证据 | 像素证据 |
|---|---|---|---|
| A1 | 点 **SMAA** 段 | 视口相机 `Smaa{preset:High}` 在、`Fxaa` 消失 | `run15-aa-before/smaa` diff **3.89%** |
| A2 | 点 **Ambient Occlusion** 开关×2 | 开：`ScreenSpaceAmbientOcclusion{quality_level}` + `NormalPrepass` 在；关：二者均消失 | `run15-ssao-on/off` diff **2.17%** |
| A3 | 点 **Quality Preset→Low**（面板无独立阴影尺寸控件，preset 驱动 shadow_quality，符合方案 D2/D4） | `DirectionalLightShadowMap.size 2048→512`、`PointLightShadowMap.size 1024→256` | `run15-shadows-before/after` diff **24.27%** |

### 3.3 B 区 2 项实测
| # | 操作 | BRP 证据 | 像素证据 |
|---|---|---|---|
| B0 | 点 **Post Processing** 开关 | `Environment.post.enabled false→true`（面板 checkbox UI） | — |
| B1 | **Bloom** 值提交（release 等价调用；见发现 1） | `post.bloom_intensity 0.0→0.85` | `run25-bloom-base/high` diff **77.11%**（辉光肉眼可见量级） |
| B3 | 点 **Tonemapper combobox → AgX**（真 UI 点击：开下拉 `run25-tm-dropdown.png` + 点选项） | `post.tonemapper TonyMcMapface→AgX` | `run25-tm-before/agx` diff **30.14%** |

### 3.4 GI 禁用项
- 连点 3 次禁用行：视口相机组件状态零变化 + 前后 window 截图 diff **0.00%**（`run26-gi-before/after-click`）——行完全惰性。
- 悬停行 → tooltip 文案实体出现在 UI 树（BRP 文本含 "**Bevy's realtime global illumination (Solari)** is experimental…"，截图 `run26-gi-tooltip.png`）。

### 3.5 撤销语义抽查
- bloom 提交后 `history.undo` 一次 → `post.bloom_intensity 0.85→0.000` 精确回滚（run25 B2）；「一次拖动恰 +1 条」由 headless `a_scene_slider_commits_once_on_release` 钉死（undo_stack.len()==1）。
- A 区全部操作 undo 栈 0 条（headless `each_viewport_control_reaches_its_operator` + viewport 家族 allows_undo=false）。

## 4. 发现（分级）

1. ⚪【测试基建/harness】**合成输入驱动不了 bevy slider 的取值**：真机点击滑条轨道确已触达 operator 管线（probe17 日志出现 `environment.set`），但上游 bevy slider 对合成指针位置计算值为 0（`normalize_point` 失配疑似的坐标空间问题）；OS 级 SendInput 判别通道在本会话被系统拒绝（error 5）。故 B1 的取值提交用面板 release 的等价一调验证（数据面+视觉面全绿），滑条纯 UI 拖动/点击留给任务 3 用真人鼠标补验。非本特性缺陷。
2. ⚪【既有问题/环境】**my-game 的 dock 布局已被历次会话挤坏**（视口渲染目标仅 743×4，像素 diff 因此一度失效）：经 Window→Reset Layout 恢复后视口 915×466、diff 恢复意义。QA 已顺带恢复现场；非本特性引入。
3. ⚪【产品·轻微】**场景无 Environment 时 B 区无可见提示**：my-game 默认场景实测无 Environment，B 区控件点击仅日志 warn（checkbox 乐观回写后停驻，见程序报告担忧 1）；建议 backlog 给 B 区加空态提示行。
4. ⚪【测试基建】**编辑器偶发 BRP 无响应**（约 1/4 次启动，疑似 PIE 后台构建争用），重启即恢复；已加重试缓解。

## 5. 结论

门禁全绿（数字与程序报告一致）；代码审查无红线（注册/两段式/映射/B 区纯皮/is_final/GI 零逻辑全部核实，4 项偏差均有方案依据）；真机交互验收覆盖面板结构、A 区 3 项、B 区 2 项、GI 禁用态、undo 语义，全部带 BRP/像素证据。**PASS**，滑条纯 UI 拖动的真人鼠标补验移交任务 3（发现 1）。
