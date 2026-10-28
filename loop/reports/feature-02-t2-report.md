# 功能 #2「Panel Maximize」任务 2 报告：tab 栏图标入口 + 文档 + 全量 CI 门

> 多 Agent 开发循环 · 程序（Rust/Bevy 工程师）
> 分支 `loop/panel-maximize` · 提交 **ec8b8e96** `Add panel maximize tab-bar toggle and document it`（6 文件，+353/-5，基于任务 1 合并后的 main c7dfa7b1）
> 方案：`loop/plans/feature-02-panel-maximize.md` 任务 2（§3）。

## 实现内容

1. **`crates/jackdaw_panels/src/tabs.rs`**：
   - marker `DockTabMaximizeButton { area_entity }`（方案 §D5 逐字）+ 内层 glyph marker `DockTabMaximizeIcon`；按钮 spawn 在 `right_row` 的 `+` 与 grip 之间（方案指定位置），初始 `Icon::Maximize`，尺寸/排版与相邻两个图标完全一致。
   - `sync_maximize_button_glyphs` 系统（挂 `DockTabPlugin`）：`MaximizedLeaf` is_changed 或 `Added<DockTabMaximizeButton>` 时刷新——**本叶 == 最大化叶 → `Icon::Minimize` + `ACCENT_BLUE` 高亮**（还原态），其余/还原后 → `Icon::Maximize` + `TAB_INACTIVE_TEXT`。`Added` 触发覆盖「最大化中叶内加 tab 导致 bar 重建」的场景（重建时 glyph 恒为 Maximize 形态，需重同步）。资源用 `Option<Res<…>>` 容错裸 World。
2. **`Icon::Minimize` 存在性核对（方案唯一「实现期核对」项）**：lucide-icons 0.563.0 `src/icon.rs:2026` `Minimize,`（`\u{e11a}`）存在，`Maximize`（`:1934`，`\u{e112}`）已存在——**无需退化方案**，直接用图标切换 + 高亮双通道。
3. **`src/dock_ops.rs`**：`on_maximize_button_click` observer（照 `on_close_button_click` 模式），注册进 `DockOpsPlugin`；marker → `NodeBinding` 取叶 → 取该叶 active tab 的 window_id → `commands.operator(PanelToggleMaximizeOp::ID).param("window_id", …).call()`（用 `<Op>::ID` 常量）。空叶无 active window → 空串 → operator 自行走焦点解析（与 D5 的空串语义一致）。
4. **headless 断言**：`tests/panels/tab_button.rs`（新，3 测试 / 21 处 assert·expect）：
   - `every_tabbed_leaf_bar_grows_a_maximize_button`：按钮集合 == 树中 TabBar 风格叶集合（一一对应，无多无少；icon sidebar 不带）；
   - `the_maximized_leaf_s_button_swaps_to_the_restore_glyph`：toggle 后最大化叶按钮 Minimize 字形 + ACCENT_BLUE、其余 Maximize + 惰性色；toggle 回全部 Maximize；
   - `clicking_the_button_maximizes_and_restores_the_leaf`：真实 `PointerClick` 事件（照 segmented_controls 的 click harness 模式）驱动 observer 全路径（marker 查找 → binding → active window → operator 派发 → availability gate），最大化 → 二次点击还原。
5. **文档**：`book/src/user-guide/keyboard-shortcuts.md` 新增 `## Panels` 节（Shift+Space 表行 + 「Panel Maximize」小节：图标入口、再按还原、面板打开落点隐藏区先退出、不持久化、命令_palette/可重绑）；`README.md` 快捷键区新增 `### Workspace` 表（Shift+Space 一行）。并入现有节（未新开页面，SUMMARY 无需改动）。
6. **盘点表**（不入 git）：Stage 4「可全屏面板」❌→✅（证据列指向 92ff0049 + ec8b8e96）；Stage 4 标题 8✅/1🟡/2❌ → **9✅/1🟡/1❌**；统计行 **75 项：✅45/🟡15/❌15**；备选 4 节标注已落地。

## 实现期发现（值得记录）

- **operator availability gate 会拒绝无焦点点击**：headless 点击测试最初失败（`MaximizedLeaf` 保持 None）。定位：`dispatch_operator`（jackdaw_api_internal/operator.rs:634-647）先跑 `is_available`，`can_toggle_maximize` 未最大化时只读焦点链——headless 无光标无 last_pressed 即拒绝（与任务 1 报告「与方案偏差 3」同一根因）。修法：测试点击前设 `LastPressedPanel`（真实点击时光标就在该面板上，hover 链等价），与 `tests/panels/main.rs` 的 `toggle()` helper 同一约定。
- 点击事件沿 UI 层级冒泡，observer 会对每个祖先各触发一次（marker 过滤天然忽略），无额外处理必要。

## 全量 CI 门（逐条退出码）

| 门 | 命令 | 退出码 | 结果 |
|---|---|---|---|
| fast | `cargo xtask fast` | **0** | fmt check + clippy --workspace --all-targets --features dylib -D warnings + lib tests：2723 passed / 2 skipped |
| integration | `cargo xtask integration` | **0** | 4852 passed / 3 skipped（351.8s），含 tests/panels 14 个（11 旧 + 3 新，日志逐条核对 PASS） |
| docs | `cargo doc --locked --workspace --document-private-items --no-deps` | **0** | 1m52s；仅既有 build script warning（jackdaw_env/api_macros/package/project_build），本次改动零新 warning |
| doctests | `cargo test --locked --workspace --doc --features bevy/dynamic_linking` | **101（既有，非回归）** | 见下 |

### doctests 基线对比（vs loop/reports/feature-01-t3-report.md）

- 本任务：exit **101**；`--no-fail-fast` 全量枚举失败目标 **恰 3 个**：`jackdaw_bind`、`jackdaw_feathers`、`jackdaw_node_graph`（merged doctest harness 吞输出，无失败测试名，与基线描述一致）。
- 基线（feature-01-t3）：exit 101，同 3 crate 集合。
- **结论：同为 101 且失败 crate 集合逐项相同 → 非回归**。`jackdaw_panels` doctests 0 条 ok；jackdaw 主 crate 3 条 doctest 全 ignored（既有）；本任务改动（tabs.rs/dock_ops.rs/测试/文档）与三失败 crate 零交集。定性沿用基线：Windows + bevy_dylib + rustdoc merged doctests 环境性既有失败，遗留非 Windows 环境核实。

## book 链接核对方式

本机无 mdbook（`where mdbook` 无输出，与 feature-01-t3 基线一致）→ 人工核对：
- 本次**未新增页面**（并入 keyboard-shortcuts.md），SUMMARY 的 9 个 `user-guide/*.md` 链接与目录下 9 个文件仍一一对应；
- `keyboard-shortcuts.md` 全文件仅 1 个链接 `[Play-in-editor](play-in-editor.md)`（既有），目标存在；新 Panels 节未引入任何链接，无断链可能。

## 新增断言数

集成 3 个新测试（21 处 assert/expect）；无新 crate 单测（图标逻辑由集成测试覆盖）。

## 遗留 / Concerns

1. **doctests 门 exit 101**：既有环境性失败（见上），非本任务引入，维持基线遗留项。
2. **视觉验收未做**（方案任务 2 验收 2：最大化/还原截图、无幽灵 handle、图标悬停观感）——本 agent 无法驱动有头渲染，属 QA 子代理/人工清单；headless 已锁定可见性/fraction/图标态语义。
3. 单叶布局（无可最大化兄弟）时按钮仍显示但点击会被 availability gate 拒绝（Cancelled 不静默有 warn）——行为正确但视觉上未置灰，与方案「灰掉」语义差半步，未做按钮级 disabled 态（需 per-按钮可用性驱动，超出方案 D5 字面范围）。
4. 「未验证」：命令面板 GUI 内交互搜索（同任务 1 遗留口径，机制性推定）；真实键入 Shift+Space / 鼠标点击（需 OS 输入，headless 已用事件直发覆盖等效路径）。
