# 功能 #2 任务 1 QA 验收报告：Panel Maximize 核心机制

> 多 Agent 开发循环 · QA（独立第三方验收）
> 分支 `loop/panel-maximize` · 提交 `92ff0049` · 日期 2026-10-22
> 输入：`loop/plans/feature-02-panel-maximize.md` 任务 1 + §D1-D6 + 主控裁定；程序报告 `loop/reports/feature-02-t1-report.md`
> 方法：四门亲跑 + 全量 diff 通读（15 文件 +1054/-12）+ 关键函数读源 + 日志逐条核对，全部独立复核。

## VERDICT: **PASS**

## 1. 确定性门（全部亲跑，退出码为准）

| 门 | 退出码 | 结果 |
|---|---|---|
| `cargo fmt --all -- --check` | 0 | 通过 |
| `cargo clippy --workspace -- -D warnings` | 0 | 通过（日志仅 linker stderr 消息，`linker_messages` lint 豁免 `-D warnings`，非本次代码） |
| `cargo xtask fast` | 0 | 2723 passed, 2 skipped |
| `cargo xtask integration` | 0 | 4849 passed, 3 skipped |

新增 18 个测试在 integration 日志逐条核对 PASS：`jackdaw::panels`（keybind 2 / maximize_toggle 2 / reconcile 5 / persistence_roundtrip 2 = 11）+ `jackdaw_panels` crate 单测（maximize::tests 6 / tree::tests 1 = 7）。与程序报告计数一致，无虚报。

## 2. 规格符合性（逐条）

| # | 条目 | 结论 | 证据 |
|---|---|---|---|
| 1 | **核心不变量：toggle 不改 DockTree 结构与 fraction** | ✅ | 全量 diff 内对 `DockTree` 的唯一写入是 operator 中 `tree.set_active(leaf, tab)`（`src/dock_ops.rs`）——方案 D2 明文要求的「焦点 tab 带前台」，仅改叶内 active tab 指针，不触结构/fraction；reconciler 链路（gate 扩展、validate 自愈、`hide_maximize_sibling`）只写 `MaximizedLeaf` 与 UI 实体；`set_host_visible`（`reconcile.rs:502`）只改 `Node.display`/几何/相邻 `PanelHandle` 并标记 `Panel` changed，**不接收 DockTree**；diff 中无 split/merge/remove_tab/simplify/set_fraction 调用（测试构造除外）。最大化/还原 = `set_host_visible` + `recalculate_group` 纯视图操作，与 D1 路线 B 一致 |
| 2 | 三处换树点显式清除 MaximizedLeaf | ✅ | `workspace_tabs.rs`（`*tree = target_tree` 后同步清）、`src/lib.rs` `init_layout`（reconcile 前）、`reset_layout`（换树后）；另 `maximize.rs` 模块文档写明「任何整体替换 DockTree 的路径必须清」（风险 2 对策） |
| 3 | reconcile 叶失效自愈 | ✅ | `reconcile_tree` 经 `validate`（存在 + Leaf + root 可达）读入；坏 id 本帧即按 None 物化（兄弟复现）+ 清资源重新武装 gate；`maximize::tests` 6 个单测覆盖全部拒绝分支（missing/split/detached/rootless/None/live） |
| 4 | 隐藏叶开窗先退出（主控裁定①） | ✅ | `exit_maximize_for_leaf(landing)`：landing ≠ 最大化叶才退出；三处调用点收敛（`open_window_in_default_area`、`open_window_in_default_area_if_absent` 的 PIE set_active 分支 + None 分支转发、`add_window_popup::add_window_to_area`）；landing == 最大化叶不退出（最大化视口内加 tab 不跳回）；集成测试 `opening_a_window_into_a_hidden_leaf_restores_the_layout_first` 锁定 |
| 5 | operator 全项 | ✅ | id `panel.toggle_maximize`、label/description 与 D5 表逐字一致、`allows_undo=false`、`can_toggle_maximize` 语义精确（已最大化→true；焦点可解析叶且有父 split；root 单叶→false 不静默 Cancelled）、`window_id(String, default="")` 空串走 `PanelFocus`；注册于 `dock_ops::add_to_extension`（`core_extension.rs:340` 调用，与 `dock.close_tab` 同路径）；已最大化时无条件还原（toggle 半边优先于参数，测试覆盖） |
| 6 | 键位 Shift+Space | ✅ | `bind_operator::<CoreExtensionInputContext, …>([PresetInput::key("Space").shift()])` 进 `DefaultKeymap` preset 可重绑；`tree_view.rs:1652` 加 `!any_pressed([ShiftLeft, ShiftRight])` 排除，测试双断言：preset 中 chord 唯一 owner + `find_conflicts` 无含 Space 行；树行激活测试（observer 计数 `TreeRowClicked`）证明裸 Space 仍激活、Shift+Space 不激活——原行为未破坏 |
| 7 | 持久化零改动 | ✅ | diff 未触碰 `scene_io/save.rs` / `auto_save_layout_on_change` / `WorkspacePersist`；round-trip 测试**真实断言**：虚拟时钟（16ms/帧）推进 >0.5s 真实触发自动保存防抖 → 反序列化后 `assert_eq!(saved, fractions_before)`（Vec<(u64,f32)> 逐项精确值，非弱断言）+ 叶数相等 + inspector 叶仍在；`init_layout` 重载后 `MaximizedLeaf == None` |
| 8 | `panel_focus.rs` 访问器 | ✅ | `focused_panel()` 与 `is_focused` 同一决策链（hovered → last_pressed）取值版，零新增跟踪状态 |

## 3. 程序 6 偏差抽验（抽 3）

1. **偏差 2（`exit_maximize_for_leaf` 收敛 helper）✅**：三处打开路径全部走该 helper（`lib.rs` ×2 + `add_window_popup.rs` ×1），无散落判断；`landing == maximized` 不退出的语义与方案 D4-4 一致。
2. **偏差 5（「有效可见性」断言语义）✅**：`leaf_displays` 沿祖先链检查 `Node.display == None`——与实现机制（隐藏承载兄弟子树的 split child host，深层叶自身 display 不变、由祖先 None 截断布局）精确吻合，语义等价于方案「其余叶宿主 Display::None」，且逐叶断言精确值（`expected = key.starts_with("right_sidebar")`），非弱断言。
3. **偏差 3（headless 喂 gate 方式）✅**：`is_available` 不读参数是**方案 D5 原文设计**（「焦点可解析出叶且该叶有父 split」），非程序偏离；测试 insert `LastPressedPanel` 喂焦点链兜底，顺带真实覆盖 `focused_panel()` 的 last_pressed 分支。声明合理。

## 4. 代码质量（全量 diff 通读）

- **post-order 隐藏正确** ✅：`reconcile_split` 顺序 = 子递归 → 本层 show → `hide_maximize_sibling`；每层只隐藏不含目标侧的 child host（沿 root→叶路径，**非递归整树**）；隐藏侧内部 split no-op（祖先已覆盖），与 D1.5「父层后写者胜」一致。
- **恢复机制自洽** ✅：每次物化先全量 show（`reconcile_leaf` auto-collapse 判定 / `reconcile_split` 无条件 show）再单向施加隐藏，清资源后同一 pass 复原——`maximize_toggle` 测试断言还原后 displays 与 fraction 逐项相等。
- **无多余 allow / 死代码** ✅；validate 自愈只在值变化时写资源（无 change churn）。
- **测试断言质量** ✅：fraction 精确值断言；坏 id `assert_cancelled` + 状态不变；已最大化 + 坏 id 仍还原。

## 5. 质量发现（均 ⚪，不阻塞）

1. ⚪[程序] `tree_view.rs` Shift 排除同时作用于 **Enter**（方案 D5 仅指定 Space）：Shift+Enter 不再激活树行。全仓无 Shift+Enter 绑定（rg 零命中），无功能损失，报告偏差 7 已声明；但测试仅覆盖 Space 分支，Enter+Shift 无断言。属超方案指示的行为收窄，方向一致（「带修饰键交给 keymap」统一语义）。
2. ⚪[程序] `persistence_roundtrip.rs` 两个测试共享同一 scratch 目录（`temp_dir + process::id()`，同 bin 默认并行）：磁盘文件理论写读 race；但两测试写内容相同（同一默认布局）、断言读各自 World 的**内存** `ProjectRoot.config.layout`，B 的 `init_layout` 即使读到对方写的文件结果也一致——实际无碍。建议后续以测试名区分目录。
3. ⚪[程序] `workspace_tabs.rs` observer 无条件 `maximized.0 = None`（`exit_maximize` 是「仅 Some 时写」）：多一次 change tick；换树本身必触发重物化，无实际开销差异。

## 6. concern 核实：命令面板可搜性

**机制性证实（headless）**：`register_operator` spawn `OperatorEntity`（`jackdaw_api_internal/src/lib.rs:376-391`）→ palette 以 `Query<&OperatorEntity>` 无名单枚举（`command_palette.rs:104-131`），唯一过滤是运行时 `is_available()`（无面板焦点时 palette 不显示该条目——正是 D5 is_available 语义的预期）。新 operator 与 `dock.close_tab` 注册路径完全一致（`core_extension.rs:340`）；集成测试 `.operator("panel.toggle_maximize")` 真实 dispatch 成功证明注册生效。
**未验证**：palette GUI 内真实键入搜索/鼠标执行的交互——headless 不可测，**任务 2 视觉项带过**。

## 7. 结论

四门全 0；规格 8 项全 ✅（核心不变量成立——这是否决树替换方案的全部理由，已被 diff 与测试双重锁定）；偏差抽验 3/3 通过；无 🔴/🟡，⚪ ×3 不阻塞。**PASS**，可进入任务 2。

遗留（任务 2 范围，程序已声明）：tab 栏图标入口、README/book/盘点表文档、全量 CI 门（doc/doctests/dylib clippy）、视觉验收截图。
