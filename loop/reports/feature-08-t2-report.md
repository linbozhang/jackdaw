# 功能 #8 · 任务 2 报告：Graphics 面板 UI + 窗口注册 + headless 测试

- 分支 `loop/graphics-panel`（基于 main `bbe4ecbe` = 任务 1 合入点），提交 **87666d96** `Add the Graphics quality panel with viewport and scene sections`
- 改动 7 文件，+1206 / −0：`src/graphics_panel.rs`（新，741 行）、`tests/viewport/graphics_panel.rs`（新，426 行）、`builtin_extensions.rs`、`core_extension.rs`、`lib.rs`、`tests/viewport/main.rs`、`en-US/main.ftl`
- `loop/` 不入库（`.git/info/exclude`），门禁日志留本地

## 门禁（每门独立行，探针 + 日志）

| 门 | 命令 | 退出码 | 日志 | 数字 |
|---|---|---|---|---|
| fmt | `cargo fmt --all -- --check` | 0 | `loop/f8-t2_fmt.log` | — |
| clippy | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings`（权威口径，与 t1 同） | 0 | `loop/f8-t2_clippy.log` | — |
| fast | `cargo xtask fast` | 0 | `loop/f8-t2_xtask_fast.log` | 2847 passed / 2 skipped（t1 基线 2847，本轮无新 lib 单测故持平） |
| integration | `cargo xtask integration` | 0 | `loop/f8-t2_xtask_integration.log` | **4996 passed / 3 skipped**（t1 基线 4989，+7 恰为本轮新集成测试，零失败） |

- 针对性探针：`cargo test -p jackdaw --test viewport graphics_panel` → 7 passed / 0 failed。

## 面板结构（`jackdaw.graphics`，RightSidebar 默认区，priority 6 排在 Inspector 家族之后；Icon::Aperture；命令面板搜 `graphics.open` / Window 菜单 RightSidebar 组自动出现）

**A 区 Viewport**（editor-only，控件全部接任务 1 的 `viewport.*` 家族，`allows_undo=false`，viewport.json 自动落盘）：

| 控件 | 形态（feathers 范式） | 绑定 operator |
|---|---|---|
| Quality Preset | segmented ×4（数据驱动 `QualityPreset::ALL`） | `viewport.quality.preset` |
| Render Scale | slider_row 25–100（Count 整数档） | `viewport.quality.set render_scale` |
| Anti-Aliasing | segmented Off·FXAA·SMAA·TAA | `viewport.quality.set anti_aliasing` |
| Ambient Occlusion | checkbox | `viewport.ssao.set on` |
| SSAO Quality | segmented Low·Medium·High·Ultra | `viewport.ssao.set quality` |
| Sun Shadows / Point Shadows / Fog | checkbox ×3 | `viewport.show.toggle flag=…` |
| Sharpening | checkbox | `viewport.sharpen.set on` |
| Strength | slider_row 0–1（indented） | `viewport.sharpen.set strength` |

**B 区 Scene**（纯 `environment.set` UI 皮，单条 undo）：

| 控件 | 形态 | 绑定 |
|---|---|---|
| Post Processing | checkbox | `environment.set post.enabled`（§3.2 注明的 B 区组开关） |
| Tonemapper | combobox ×9（变体名即 operator 值） | `environment.set post.tonemapper` |
| Exposure (EV100) | slider_row −5…20 | `environment.set post.exposure`（**仅 release 提交**） |
| Bloom Intensity / Threshold | slider_row ×2 0–1 | `environment.set post.bloom_*`（仅 release 提交） |

- **B 区滑条 release 语义**：`ValueChange::is_final==false` 的拖动中间值只回写 `SliderValue`（fill/数字随手势走），`is_final==true` 才发一调 `environment.set` → 内部 `SetEnvironment` 一条 undo——用 bevy slider 原生 `is_final` 实现，无需防抖（方案风险 4 的二选一取 release 回调支）。
- **实时 GI 置灰**：FieldRow 行携带 `GraphicsRealtimeGi` + `Tooltip`（含 Solari/experimental/未接入/四个替代项文案，ftl 键 `graphics-realtime-gi-tooltip`），行内 FeathersCheckbox 挂 `InteractionDisabled`（禁用态由 feathers 主题灰显），无任何运行时逻辑、零 bevy feature 接触。
- **opt-out 提示行**（D3-4）：`GraphicsOptOutHint` 一行文案，`ViewportSettings.quality.post_processing == false` 时显示（Display 切换），提示 B 区后处理未在视口预览。
- **文案**：全部行/节标题 + 提示走 en-US ftl（`graphics-*` 22 个键，构建期经 `Localization::content` 解析，缺键回退键名本身）；分段选项文字（Low/FXAA…）数据驱动自模型枚举 label。
- **同步闭环**：`sync_viewport_fields`（settings 变更 → segment Checked/背景/字色、checkbox Checked、SliderValue）与 `sync_scene_fields`（`Changed<Environment>` → B 区滑条/combobox/开关）让菜单、脚本、undo 的外部改动回流到面板；分段行构建期即种子当前选中态。

## 新增测试（7 个，`tests/viewport/graphics_panel.rs`）

1. `the_graphics_window_is_registered_and_searchable` —— WindowRegistry 含 `jackdaw.graphics`（名 "Graphics"、区 right_sidebar）+ `graphics.open` 在 operator 注册表（命令面板可搜）；
2. `opening_the_panel_docks_a_tab_with_both_sections` —— `graphics.open` 后 DockTree 出现该 tab；面板文本含 A/B 两区全部行名与 "Realtime GI"；
3. `each_viewport_control_reaches_its_operator` —— A 区四类控件（segmented/checkbox/flag checkbox/live slider）逐个触发 → `ViewportSettings` 断言（preset=Low、AA=SMAA、SSAO=Ultra+开、fog 关、render_scale=60、strength=0.8），且 undo 栈长度 0；
4. `a_scene_slider_commits_once_on_release` —— bloom 滑条两个中间 tick 不写 Environment、不进 undo；release 一调 → 值 0.6、undo 栈恰 1 条、`history.undo` 回滚到 0.0；
5. `the_scene_rows_write_the_environment` —— Post Processing 开关与 tonemapper combobox 事件 → `Environment.post` 断言；
6. `the_realtime_gi_row_is_shown_but_disabled` —— GI 行存在、子树含 `InteractionDisabled`、tooltip 含 "Solari"；
7. `the_opt_out_hint_follows_the_viewport_setting` —— 关 post_processing 提示行 Display::Flex，默认 None。

## 实现要点 / 与方案偏差

- **窗口注册放 `CoreWindowsExtension`**（方案 §3.1 原文即此）；Window 菜单入口与命令面板可搜均为注册的零成本副产物（菜单自动按区分组枚举 registry），未另做菜单行。
- **B 区「bloom 开关+强度」的实现裁量**：`Environment.post` 无独立 bloom 开关，按 §3.2 规格表「B 区组开关 = post.enabled」的注记落为 Post Processing checkbox（`post.enabled`）+ intensity 滑条（0=无辉光）；未另造存储。
- **面板构建两段式**：窗口 build 闭包只 spawn `GraphicsPanel` 根节点（`graphics_panel_root()`），`Added<GraphicsPanel>` 系统经 Commands 填充——为直接复用 `spawn_slider_row`/`spawn_field_row`/`combobox` 等 Commands 型 feathers 控件（与 terrain panel 的 populate 模式同款）。
- **observer 全部 plugin 级注册**（`add_observer` + tag 查询过滤），同 terrain panel 范式；segmented 事件读 `event.value`（RadioGroup 语义：value=被选 segment 实体）。
- 分段行/复选框构建期种子当前态（否则首次设置变更前面板无选中显示）。
- clippy 门沿用 t1 确立的权威口径（`--all-targets --features dylib --deny warnings`）。

## Concerns

1. **场景无 Environment 时 B 区开关的瞬时乐观**：`on_toggle` 先回写 `Checked` 再发 operator，operator 在无 Environment 时 cancel（日志 warn），复选框会短暂停留在用户意图态直到下一次 `Changed<Environment>`（无环境则不来）。影响极小（默认 unchecked、真实场景必有环境），记录不修。
2. B 区可见性受 A 区钳制的完整真机验证（截图 pixdiff、命令面板 SendInput 开面板、Low preset 下动 bloom 出提示行）归任务 3 QA；本轮 headless 已覆盖提示行状态机。
3. Exposure 滑条范围取方案建议 −5..20（PostProcess 默认 9.7 居中偏右）；bevy `Tonemapper` 比 jackdaw 多 `Linear` 变体（方案 D1-d backlog），面板按 jackdaw 9 项呈现。
4. 任务 3 范围（真机脚本/book 文档/README/盘点表）未触碰；preset 未加锐化（遵任务 1 QA 备注，保持现状）。
