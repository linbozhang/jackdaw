# 功能 #2「Panel Maximize」任务 1 报告：核心机制

> 多 Agent 开发循环 · 程序（Rust/Bevy 工程师）
> 分支 `loop/panel-maximize` · 提交 `92ff0049`（基于 main `35db5c74`）· 日期 2026-10-22
> 方案：`loop/plans/feature-02-panel-maximize.md` 任务 1（§3）。

## 实现内容

按方案 §2.1 任务 1 范围全部落地，`DockTree`（含 fraction/tabs/active）全程零改动：

1. **`crates/jackdaw_panels/src/maximize.rs`（新）**：`MaximizedLeaf(Option<NodeId>)` 资源；`exit_maximize(world)`（树整体替换点用）；`exit_maximize_for_leaf(world, landing)`（落点 != 最大化叶才退出，供三处打开路径）；`validate(tree, candidate)`（存在 + 是 Leaf + root 可达）；模块文档写明「任何整体替换 DockTree 的路径必须清 MaximizedLeaf」（方案风险 2 对策）。`ReconcilePlugin` 注册 `init_resource`。
2. **`tree.rs`**：`DockTree::subtree_contains(node, target)` 查询（含单测）。
3. **`reconcile.rs`**：`reconcile_tree` gate 扩展为 `DockTree` **或** `MaximizedLeaf` is_changed；读入时 `validate` 自愈（坏 id → None 并清资源，重新武装 gate 下帧复显）；`reconcile_split` 末尾 post-order 施加 `hide_maximize_sibling`（复用 `set_host_visible`：隐藏兄弟 host + 相邻 handle + 标记 `Panel` changed → `recalculate_group` 只对可见 Panel 求和，可见子树自动 100% 占满）。
4. **三处树整体替换点显式清除**：`on_workspace_changed_swap_tree`（workspace_tabs.rs，随 `*tree = target_tree`）、`init_layout` / `reset_layout`（src/lib.rs，reconcile 前）。
5. **三处面板打开路径退出规则**（主控裁定 ①：落点在隐藏区 → 自动退出再开）：`open_window_in_default_area`、`open_window_in_default_area_if_absent`（含已存在窗口只 `set_active` 的 PIE surface 路径，方案风险 5 变体）、`add_window_popup::add_window_to_area`。`open_window_in_default_area_if_absent` 放开为 `pub`（测试用，有 `init_layout` 先例）。
6. **operator `panel.toggle_maximize`**（dock_ops.rs，按 §D5 全表）：id/label/description 逐字、`allows_undo=false`、`is_available = can_toggle_maximize`（已最大化 → true；否则焦点可解析叶且**该叶有父 split**）、params `window_id(String, default="")` 空串走 `PanelFocus`。已最大化时无条件还原（toggle 另一半，参数不参与）；目标叶 `set_active` 把焦点 tab 带到前台；root 单叶 `Cancelled` 不静默。
7. **键位 Shift+Space**：`bind_operator::<CoreExtensionInputContext, PanelToggleMaximizeOp>([PresetInput::key("Space").shift()])`，进 `DefaultKeymap` preset、用户可重绑。**`tree_view.rs:1652` 裸 Space 树行激活加 `!any_pressed([ShiftLeft, ShiftRight])` 排除**（方案 D5 指定修法），Enter 一并排除（全仓无 Shift+Enter 绑定，rg 核实）。
8. **`panel_focus.rs`**：`PanelFocus::focused_panel() -> Option<String>`（hovered → last_pressed 同一决策链取值版）。
9. **测试**：panels crate 单测 7 个新增（`maximize::tests` 6：validate 各拒绝分支 + live 叶通过；`tree::tests::subtree_contains` 1）+ `tests/panels/` 集成 11 个（4 文件 + main.rs，见下）。

### tests/panels 明细（11 个，全过）

- `maximize_toggle.rs`（2）：toggle 进出全链（资源态 / 全叶有效可见性 / fraction 逐位不变 / 最大化叶 active tab 内容可见 / 二次 toggle 完整还原）；root 单叶布局拒绝（`Cancelled`）。
- `persistence_roundtrip.rs`（2）：最大化 + `fixed_frame_clock` 推进 >0.5s 触发自动保存 → `ProjectRoot.config.layout` 反序列化树 == 最大化前（fraction 逐项、叶数、inspector 叶仍在）；`init_layout` 重载后 `MaximizedLeaf == None` 且全叶可见。
- `reconcile.rs`（5）：(a) `WorkspaceChanged` 切到 level_design → 清除 + 树已换（按 level_design 特有 `split.jackdaw.viewport.qv_top` 断言）；(b) runtime split 非 persistent 叶最大化 → `dock.close_tab` 关最后 tab → validate 自愈退出 + 兄弟复显；(b') persistent 叶清空 → 最大化保持（空占位仍 Flex）；(c) `open_window_in_default_area_if_absent` 落点在隐藏 bottom_dock → 先退出 + 全复显；(d) 坏 `window_id` → `Cancelled` 且状态不变；已最大化 + 坏 id → 仍还原。
- `keybind.rs`（2）：preset 中 Shift+Space 属于 `panel.toggle_maximize` 独有、`find_conflicts` 无任何含 Space 的冲突行；树行键盘激活 Shift 排除（最小 world 直跑 `tree_keyboard_navigation`，observer 计数 `TreeRowClicked`：裸 Space=1、Shift+Space=0）。

## 与方案偏差

均为实现细节层面，无架构偏离（D1 视图叠加 / D3 不持久化 / D4 三规则 / D5 operator+键位全按方案）：

1. **恢复路径比方案草图更简**：不需要任何显式「恢复」代码。全树重物化时每个 host 自然复显（`reconcile_leaf` 的 auto-collapse 判定、`reconcile_split` 末尾无条件 show），post-order 隐藏只需单向施加、父层后写者胜；清 `MaximizedLeaf` 后同一 pass 即还原（fraction 逐位不变由测试锁定）。方案 D1.5 的 post-order 结论照用。
2. **`exit_maximize_for_leaf` 新增**：方案草图只有 `exit_maximize(world)`；三处打开路径都要「落点 != 最大化叶才退出」判断，收敛成一个带落点参数的 helper（方案指定的 `exit_maximize(world)` 仍存在，树替换点用）。
3. **headless 测试喂 gate 的方式**：方案 D2 说测试「走 window_id 参数、不走焦点解析」，但 operator 派发先过 `is_available` gate，而 gate 只读焦点链不看参数——headless 下无光标无 last_pressed 会被 gate 拒。测试通过设置 `LastPressedPanel`（焦点链的 last-pressed 兜底）喂 gate，顺带覆盖了 `focused_panel()` 的兜底路径。
4. **`tests/panels` 为 4 文件而非方案 2.1 字面的「4 个测试文件 + main.rs」歧义解**：D6 草案第 4 条（crate 单测）落在 crate 内 `#[cfg(test)]`，第 4 个集成文件换成 `keybind.rs`（验收清单第 4 条的两个断言：preset 冲突 + 树行 Shift 排除）。
5. **两处测试断言口径修正（方案未预见的现实）**：(a) level_design 工作区树也含 right_sidebar/inspector，workspace 切换断言改用 level_design 特有 area id；(b) 隐藏施加在「承载兄弟子树的 host」上，子树内部叶 host 自身 `Display` 不变（祖先 None 已截断布局），集成断言用祖先链「有效可见性」，与方案「其余叶宿主 Display::None」语义一致（方案的「宿主」即被隐藏的子树根 host）。
6. **验收 4 的「find_conflicts 空」按口径执行**：整体冲突报告含既有 advisory 项（如 entity.copy / clip.copy_keyframes 共享 Ctrl+C），非本次引入；断言为「无任何含 Space 的冲突行」+ Shift+Space 单一 owner。

## 各门退出码

| 门 | 退出码 | 结果 |
|---|---|---|
| `cargo fmt --all -- --check` | 0 | 通过（先 `cargo fmt --all` 应用后复核干净） |
| `cargo clippy --workspace -- -D warnings` | 0 | 通过（修 1 处 `clippy::doc-markdown`：文档 `NodeId` 加 backticks） |
| `cargo xtask fast` | 0 | 2723 passed, 2 skipped（既有 skip） |
| `cargo xtask integration` | 0 | 4849 passed, 3 skipped（含 tests/panels 11 个 + panels crate 新单测 7 个，日志逐条核对 PASS） |

## 测试数

- 新增 18 个测试，18 通过：集成 11（tests/panels）+ crate 单测 7（maximize 6 + tree 1）。
- 既有套零回归：fast + integration 合计 4849 全绿。过程性修复 1 次：初版 `exit_maximize_for_leaf` 用 `resource_mut` 读资源，4 个既有裸-World 单测（dock_open_tests ×2、terrain_focus_guard ×2）panic「resource 不存在」，改为 `get_resource` 容错读取后全绿（该修复在提交内）。

## 遗留（任务 2 范围，未动）

- `tabs.rs` tab 栏最大化/还原图标按钮 + `dock_ops.rs` click observer + `Icon::Minimize` 存在性核对；
- README 快捷键表 + book `keyboard-shortcuts.md` + `roadmap-gap-analysis.md` Stage 4 打勾；
- 全量 CI 门（doc / doctests / dylib clippy）与视觉验收截图。

**未验证项**：命令面板 GUI 内实际搜索 "Toggle Panel Maximize" 的交互（未驱动 palette UI；operator 经 `add_to_extension` 注册的路径与 `dock.close_tab` 完全一致，palette 从 `OperatorEntity` 枚举，收录机制相同，属机制性推定而非运行证据）。真实键入 Shift+Space 触发（需 OS 键盘事件，headless 不可测；preset 归属与树行排除断言已覆盖冲突面）。
