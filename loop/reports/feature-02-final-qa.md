# 功能 #2「Panel Maximize」终验报告（任务 2 验收 + 功能级）

> 多 Agent 开发循环 · QA（独立第三方验收）
> 分支 `loop/panel-maximize` · 提交 `ec8b8e96`（任务 2，6 文件 +353/-5）· 日期 2026-10-22
> 输入：方案 `loop/plans/feature-02-panel-maximize.md` §3 任务 2 + §4 验收清单；任务 1 QA `loop/reports/feature-02-t1-qa.md`；程序报告 `loop/reports/feature-02-t2-report.md`
> 方法：四门全部亲跑记退出码 + 全量 diff 通读 + 盘点表逐行脚本计数 + 关键源码/依赖核对，全部独立复核。

## VERDICT: **PASS**（功能级；视觉项按主控裁定 ⚠️ 留用户终审）

## 1. 确定性门（全部亲跑）

| 门 | 命令 | 退出码 | 结果 |
|---|---|---|---|
| fast | `cargo xtask fast` | **0** | fmt check + clippy --all-targets --features dylib -D warnings + lib tests：2723 passed / 2 skipped |
| integration | `cargo xtask integration` | **0** | 4852 passed / 3 skipped（357.8s） |
| docs | `cargo doc --locked --workspace --document-private-items --no-deps` | **0** | 46.5s；仅既有 4 个 build script warning（env/api_macros/package/project_build），零新 warning |
| doctests | `cargo test --locked --workspace --doc --features bevy/dynamic_linking --no-fail-fast` | **101（既有）** | 见基线对比 |

**doctests 基线对比（亲跑）**：`error: 3 targets failed: -p jackdaw_bind --doc / -p jackdaw_feathers --doc / -p jackdaw_node_graph --doc`——失败集合恰为 {jackdaw_bind, jackdaw_feathers, jackdaw_node_graph}，与 feature-01-t3 基线（exit 101、同 3 crate）**逐项相同 → 非回归**。附证：jackdaw 主 crate 3 条 doctest 全 ignored、jackdaw_panels doctests 0 条，与程序报告一致；本功能改动与三失败 crate 零交集。

**integration 日志逐条核对**：`jackdaw::panels` 14 条全 PASS（keybind 2 / maximize_toggle 2 / persistence_roundtrip 2 / reconcile 5 / **tab_button 3 新增**）。3 个新测试：
- `tab_button::every_tabbed_leaf_bar_grows_a_maximize_button` PASS
- `tab_button::the_maximized_leaf_s_button_swaps_to_the_restore_glyph` PASS
- `tab_button::clicking_the_button_maximizes_and_restores_the_leaf` PASS（真实 `PointerClick` 事件驱动 observer 全路径）

## 2. 任务 2 规格逐条核实

| # | 条目 | 结论 | 证据（QA 独立取得） |
|---|---|---|---|
| 1 | 图标与 TabBar 叶一一对应 | ✅ | `tabs.rs` spawn 于 `right_row` 的 `+` 与 grip 之间（读源码确认顺序）；测试断言按钮绑定叶集合 == 树中 `DockAreaStyle::TabBar` 叶集合（排序后 `assert_eq`，icon sidebar 天然排除），我的 integration 运行 PASS |
| 2 | 最大化态图标/颜色切换 | ✅ | `sync_maximize_button_glyphs`：本叶==最大化叶 → `Icon::Minimize` + `ACCENT_BLUE`，其余/还原 → `Icon::Maximize` + `TAB_INACTIVE_TEXT`；`MaximizedLeaf` is_changed + `Added<DockTabMaximizeButton>` 双触发（覆盖最大化中 bar 重建）；测试断言 Minimize 字符串、ACCENT_BLUE、还原后全部回到 Maximize+惰性色，PASS |
| 3 | `Icon::Minimize` 存在性（方案唯一「实现期核对」项） | ✅ | 本机 lucide-icons 0.563.0 `src/icon.rs:2026` `Minimize,`（`:1934` `Maximize,`）——与程序报告行号一致，无需退化方案 |
| 4 | PointerClick→operator 全路径 | ✅ | `on_maximize_button_click`（照 `on_close_button_click` 模式）：marker → `NodeBinding` → 叶 active tab 的 window_id → `commands.operator(PanelToggleMaximizeOp::ID).param("window_id", …)`；测试用真实 `PointerClick` trigger 驱动（marker 查找→binding→active window→operator 派发→availability gate），最大化+二次还原均断言 `MaximizedLeaf` 资源态，PASS |
| 5 | `<Op>::ID` 常量引用非字符串 | ✅ | `src/dock_ops.rs:310` `PanelToggleMaximizeOp::ID`，为 operator trait `const ID: &'static str`（`operator.rs:67`），非裸字符串 |
| 6 | 单叶布局按钮未置灰遗留 | ✅ 如实记录 | 程序报告遗留 #3 明确记录「按钮仍显示但点击被 availability gate 拒绝（Cancelled 有 warn 不静默），差按钮级 disabled 态」；任务 1 测试 `a_root_leaf_layout_refuses_to_maximize` 锁定 gate 拒绝语义——遗留声明与代码行为一致，未虚报 |
| 7 | book 内容准确性 | ✅ | `keyboard-shortcuts.md` 新 `## Panels` 节逐句对照实现：Shift+Space ✓；「再按还原、split positions included」== maximize_toggle fraction 逐项相等断言 ✓；「Window 菜单 / tab 栏 `+` / starting Play 落隐藏区先还原」== 三处 `exit_maximize_for_leaf` 调用点（`lib.rs:3617/3677` + `add_window_popup.rs:210`，`+` 按钮 popup 确走 `add_window_to_area`）✓；「保存存正常排布、新会话非最大化」== persistence_roundtrip ✓；「palette 列为 Toggle Panel Maximize、可重绑」== label 与 preset 绑定 ✓ |
| 8 | README 快捷键行 | ✅ | 新 `### Workspace` 表 `Shift+Space | Maximize / restore the focused panel`，位置合理，无其它行被改 |
| 9 | book 链接有效 | ✅ | SUMMARY 9 个 user-guide 链接 == 目录 9 文件一一对应（本次未新增页面）；`keyboard-shortcuts.md` 全文仅 1 个既有链接 `play-in-editor.md`（目标存在），新节零链接 |
| 10 | 盘点表 Stage 4 | ✅ | 行 80「可全屏面板 ✅」，证据列含两哈希 `92ff0049` + `ec8b8e96` 及机制摘要 |
| 11 | 盘点表统计 75=45/15/15 | ✅（脚本逐行实测） | 独立脚本按表格行逐行计数：**TOTAL ✅45 / 🟡15 / ❌15，sum 75**——与统计行完全吻合；Stage 4 节实测 9✅/1🟡/1❌（11 行）== 节标题。注：Stage 2 标题「7✅」实为 6 行，系功能 #1 时已记录的既有标题口径问题（统计行已注明），非本次引入 |
| 12 | 无越界 | ✅ | `git diff main..loop/panel-maximize` 恰为任务 2 的 6 文件（README/book/tabs.rs/dock_ops.rs/tests main.rs+tab_button.rs）；任务 1 已 QA 的核心机制文件（maximize.rs/reconcile.rs/tree.rs/panel_focus.rs/tree_view.rs/workspace_tabs.rs）**零改动**；dock_ops.rs 仅增量添加 observer（任务 1 operator 代码未动） |

## 3. 功能级终验（方案 §4 清单逐项）

**确定性门 6 项**：fmt ✓（fast 内含）· clippy -D warnings（--all-targets --features dylib，fast 内含）✓ · xtask fast ✓(0) · xtask integration ✓(0) · cargo doc ✓(0) · doctests 基线对比非回归 ✓（101，失败集合与基线逐项相同）

**headless 行为断言 5 项（我的 integration 运行全部 PASS）**：
- toggle 进出（资源态/兄弟 Display/最大化叶可见）✓ `maximize_toggle::a_toggle_hides_the_siblings_and_a_second_restores_them`
- 布局还原 fraction 逐项相等 ✓（同上测试精确值断言）
- 持久化 round-trip + 重载无最大化态 ✓ `persistence_roundtrip` 2 条
- workspace 切换清除 / 叶清空自动退出（persistent 保留占位）/ 隐藏区开窗先退出 / 坏 window_id Cancelled ✓ `reconcile` 5 条
- Shift+Space 无冲突（Ctrl+Space palette、树行裸 Space）✓ `keybind` 2 条

**文档项 2 项**：README + book 快捷键表含 Shift+Space ✓；盘点表 Stage 4 ✅ ✓

**视觉项 3 项**：⚠️ 留用户终审（程序遗留 #2 如实声明无法有头渲染；QA 同为 headless，headless 已锁定可见性/fraction/图标态语义）：
- [ ] 最大化/还原过渡无闪烁、无残留 handle/空白；tab 栏与 `+`/grip 排布不跳版
- [ ] 视口、Inspector、动画时间线各最大化一屏截图观感
- [ ] 图标悬停/还原态可辨识

## 4. 任务 1 QA concerns 处置核对

- T1 ⚪×3（Enter+Shift 无断言 / roundtrip 共享 scratch 目录 / observer 无条件清）：均为不阻塞遗留，任务 2 未恶化（相关文件零改动），状态如实延续。
- T1 §6「palette GUI 内真实键入/鼠标执行」：任务 2 如实声明仍未验证（遗留 #4），机制性证据链（注册路径与 `dock.close_tab` 一致 + 集成 dispatch 成功）成立——转入用户手测建议。

## 5. 用户手测建议（视觉项终审，5 条）

1. **Shift+Space 全链路**：光标置于 Inspector → Shift+Space 最大化占满工作区 → 再按还原，确认每根分割条位置与最大化前一致、无幽灵 handle/空白条、无闪烁。
2. **图标入口**：点 tab 栏 Maximize 图标（`+` 与 grip 之间）→ 图标变 Minimize 且高亮蓝 → 点击/再按 Shift+Space 还原后所有 tab 栏图标回到 Maximize 态。
3. **命令面板**：最大化状态下 Ctrl+Space 搜 "Toggle Panel Maximize" 执行应还原；顺带在任意文本输入框内按 Shift+Space 确认不误触发。
4. **隐藏区开面板**：最大化 Inspector 后从 Window 菜单（或他叶 tab 栏 `+`）打开一个默认落在被隐藏区域的面板 → 应自动退出最大化且新面板可见；在最大化叶内自己的 `+` 加 tab 则**不应**跳回。
5. **持久化**：手动拖几根分割条 → 最大化 → 等约 1 秒（自动保存防抖）→ 关闭重开编辑器：布局与比例无损、启动为非最大化态。

## 6. 质量发现（均 ⚪，不阻塞）

1. ⚪[程序] 单叶布局（root 无兄弟）按钮视觉未置灰，点击被 availability gate 拒绝（warn 不静默）——程序遗留 #3 已如实记录；距方案 D5「灰掉」字面差按钮级 disabled 态，行为正确。
2. ⚪[程序] 图标同步系统实现在 `tabs.rs` `DockTabPlugin`（`MaximizedLeaf` is_changed + `Added` 双触发），未按方案 §2.1 预估触碰放 `reconcile.rs` `sync_leaf_visuals` 同款位置——触发源等价且覆盖 bar 重建场景，验收清单未强制位置，测试锁定行为。
3. ⚪[承接] 命令面板 GUI 交互、真实 OS 键鼠事件（任务 1 QA §6 / 任务 2 遗留 #4 口径一致）——headless 已用事件直发覆盖等效路径，GUI 交互留手测（见 §5.3）。
4. doctests exit 101 为 Windows + bevy_dylib merged doctests 环境性既有失败（失败集合与基线逐项相同），非本功能引入，维持遗留项。

## 7. 结论

四门：fast=0 / integration=0 / docs=0 / doctests=101（与基线失败集合逐项相同，非回归）。任务 2 规格 12 项全 ✅（含盘点表统计脚本实测 45/15/15=75）；功能级方案清单确定性门 6/6、headless 断言 5/5、文档 2/2 全绿，视觉 3 项按主控裁定留用户终审（附 5 条手测建议）。无 🔴/🟡。**功能 #2 Panel Maximize 终验 PASS**。
