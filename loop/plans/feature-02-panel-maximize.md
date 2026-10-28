# 功能 #2 实施方案：可全屏面板（Panel Maximize）

> 多 Agent 开发循环 · 策划产物（只写方案，不含代码实现）
> 日期：2026-10-22 · 策划：资深 Bevy 编辑器工程师 Agent
> 选题依据：`loop/plans/roadmap-gap-analysis.md`「备选 4」节。Roadmap 验收锚点：Stage 4「toggleable fullscreen panes」（编辑器专用：可全屏面板 ❌ → ✅）。
> 调研方法：rg 文件搜索 + Read，未运行任何 cargo 命令（避免与构建锁冲突）。

---

## 1. 范围与不做（含 6 个设计问题的结论）

### 1.0 功能范围总述

**做**：对「当前激活叶面板」（一个 `DockLeaf` 标签区）toggle 最大化——激活时其余兄弟区域全部隐藏、该叶占满整个工作区；再按一次恢复原布局。三件套：

1. **operator**：`panel.toggle_maximize`（命令面板 / 远程 API / UI 共用，遵循 CONTRIBUTING operator 范式）；
2. **快捷键**：Shift+Space（进 keymap preset、用户可重绑）；
3. **UI 入口**：面板标签栏右侧一个最大化/还原图标按钮（与现有 `+`/grip 同排）。

**不做**（首版明确排除）：
- 多面板分屏全屏（同时全屏多个叶）、浮动/独立 OS 窗口（roadmap 另一条「Run Game 新窗口」语义）；
- **不持久化最大化状态**（重启后布局还原为未最大化——最大化是视图态不是布局态，见 D3）；
- Escape 退出最大化（Escape 已被 ExitEditMode/ClipClear/CancelDraw/ModalCancel 占用，不绑）；
- 最大化期间叶内拖拽调整分割条（兄弟已隐藏，无 handle 可拖，天然不存在）。

### D1. 树变换语义：**视图层叠加（view overlay），不动 `DockTree`**（最关键）

**结论：最大化 = 独立资源 `MaximizedLeaf(Option<NodeId>)` 记录目标叶；reconciler 在 materialize 时沿 root→目标叶路径，把每层 split 的另一侧子树（含相邻 handle）`Display::None`，可见子树按现有 `recalculate_group` 逻辑自动占满。`DockTree`（含全部 fraction / tabs / active）一个字节都不改。**

证据链与两条路线对比：

1. **树结构**（`crates/jackdaw_panels/src/tree.rs`）：`DockTree` 是 `nodes: HashMap<NodeId, DockNode>` + 单 `root`（`:232-245`）；`DockNode` 为 `Leaf(DockLeaf)` / `Split(DockSplit{axis, fraction, a, b})`（`:191-195`）。文档注释明确「tree 是唯一真理之源，reconciler 每帧按树 materialize UI，拖拽/缩放只改树」（`:227-231`）。
2. **路线 A（树替换/换 root + 影子栈保存恢复）被否决**，两个硬伤：
   - **持久化必然踩坏**：`src/lib.rs:3404-3437` `auto_save_layout_on_change` 在 `tree.is_changed()` 后 **0.5s 防抖自动把 live tree 存进工程配置**（`scene_io/save.rs:502-525` 直接 clone live tree 入 `WorkspacePersist`）。最大化若换 root，0.5 秒后自动保存就把「只剩一个叶的树」写成用户布局——**其余面板全部丢失**。要堵这个洞需改所有快照点（`save_layout_to_project`、`sync_active_workspace_from_live_tree`、workspace 切换 observer），面大且漏一处即坏数据。
   - **NodeId 悬空**：换 root 后隐藏节点仍在 `nodes` map 里，而 `find_leaf_with_window` / `leaves()` / `tabs()` **遍历整个 map 而非从 root 走**（`tree.rs:351-356, 390-395`）——`window.resize_panel`、`open_window_in_default_area_if_absent`（`lib.rs:3595`）等会命中隐藏叶，把新 tab 加进不可见区域。
3. **路线 B（推荐，视图叠加）有现成基建**：
   - `set_host_visible`（`crates/jackdaw_panels/src/reconcile.rs:435-522`）已经实现「隐藏 host + 相邻 `PanelHandle` + 几何清零 + 标记 `Panel` changed」，空叶自动折叠（`reconcile_leaf:176-183`）就在用它——最大化只是把同一机制用于「兄弟子树」。
   - `recalculate_group`（`crates/jackdaw_panels/src/split.rs:103-152`）**只对 `Display != None` 的 Panel 求和再分配**（注释 `:117-118`："Hidden (Display::None) panels are out of layout"）——隐藏兄弟后剩余子树自动 100% 占满，**无需任何新布局代码**。
   - reconciler 入口 `reconcile_tree` 目前只 gate 在 `is_resource_changed::<DockTree>()`（`reconcile.rs:106-118`）——扩展为 `|| is_resource_changed::<MaximizedLeaf>()` 即可让 toggle 触发全树重物化（叶级 `needs_rebuild` 判定按 binding/tab 不变即跳过，无重建churn）。
4. **恢复语义（用户手动布局调整是否保留）**：**完全保留**。树未动（fraction 不变，`split.rs:276-283` 拖拽 handle 时已把比例镜像进树）；隐藏用的 `Panel.ratio` 也未动（`set_host_visible` 只改 `Node` 的 display/几何）。还原 = 重新 `Display::Flex` + `Panel.set_changed()` → `recalculate_group` 按原 ratio 重算——最大化前的每根分割条位置原样回来。最大化**期间**没有可拖的 handle，无「期间调整」需要保留。
5. **隐藏的施加顺序**：`reconcile_split` 先递归两个子节点（子叶可能因 persistent 空叶把自己设为可见），**后**对本层兄弟施加隐藏（post-order，父层后写者胜）——保证隐藏不被叶级 auto-collapse 可见性覆盖。

### D2. 「当前激活面板」判定：**复用 `PanelFocus`（hover 优先、last-pressed 兜底），新增一个只读访问器**

**结论：编辑器已有「这个按键属于哪个面板」的现成概念——`src/panel_focus.rs` 的 `PanelFocus`（SystemParam）：光标所在面板优先，光标不在任何面板上时用最后按过的面板（`is_focused`，`:27-32`；`LastPressedPanel` 由 PointerPress observer 维护，`:66-75`）。最大化目标 = 该焦点 window 所在叶（`DockTree::find_leaf_with_window`，`tree.rs:351`）。零新增跟踪状态。**

- 需要的小改动：`panel_focus.rs` 现有 `hovered_panel()` 是私有 fn，只暴露了布尔版 `is_focused`；新增 `PanelFocus::focused_panel(&self) -> Option<String>`（hovered→`last_pressed` 同一决策链取值版），供 operator 与 is_available 用。
- **目标确定后**：`tree.set_active(leaf, tab)` 把焦点窗口所在 tab 带到前台再最大化（Blender 同款「光标下区域的当前 tab 全屏」语义）。
- 边界：焦点 window 已被关闭（`LastPressedPanel` 陈旧）→ `find_leaf_with_window` 落空 → operator `Cancelled`、is_available false——不静默。
- 叶内多 tab：最大化的是**整个叶**（标签栏保留，可继续切 tab）；这是「叶面板」粒度，与范围草案一致。
- headless 测试下无光标：operator 带 `window_id` 参数（显式指定时不走焦点解析），测试走该参数（同 `dock.close_tab` 带 `tab_id` 参数的模式，`src/dock_ops.rs:25-42`）。

### D3. 持久化交互：**树不变 ⇒ 最大化状态下保存天然无害；不持久化 maximized 标志**

**结论：选 D1 路线 B 后，这个问题被架构消解，无需任何持久化代码改动。** 逐点证据：

1. **自动保存（最凶险的路径）**：`auto_save_layout_on_change`（`lib.rs:3404-3437`）的触发源包括 `Changed<Panel>` / tree / registry 变化——最大化 toggle 确实会触发它（隐藏兄弟改了 Panel 实体的 Node）；0.5s 后 `save_layout_to_project` clone **live `DockTree`**——该资源从未被最大化改动，**存下去的就是正确的完整布局**（含用户全部面板与 fraction）。
2. **手动保存 / workspace 快照**：`scene_io/save.rs:502-514` 与 `sync_active_workspace_from_live_tree`（`lib.rs:3698-3710`）都只读 `DockTree` 资源——同样天然正确。
3. **重载**：`init_layout`（`lib.rs:3453-3510`）反序列化 `WorkspacesPersist` → 树即未最大化布局；`MaximizedLeaf` 默认 `None`。**跨会话不保留最大化**（与 Blender 一致：maximize 是会话视图态）。也不在 `WorkspacePersist`（`workspace.rs:95-104`）加字段——加 `maximized` 标志需要处理「保存的叶重载后 NodeId 语义漂移」，收益为零，明确不做。
4. 若当初走路线 A，需在 ≥3 处快照点做「投影还原」，且自动保存防抖 0.5s 意味着**用户最大化后 1 秒内关编辑器都可能存坏布局**——这是否决 A 的决定性证据。

### D4. reconcile 交互：**NodeId 生命周期三规则——显式清除 > 校验自愈 > 语义保持**

最大化期间树仍会变（关 tab、扩展启停、面板开关、workspace 切换），`MaximizedLeaf` 的 NodeId 必须跟上：

1. **workspace 切换：显式清除（必须）**。`on_workspace_changed_swap_tree`（`crates/jackdaw_panels/src/workspace_tabs.rs:585-613`）整体 `*tree = target_tree`——新树的 NodeId 计数器空间与旧树重叠，`NodeId(5)` 在新树里可能是完全不同的节点，**校验无法识别这种碰撞**，所以在此 observer 里同步清 `MaximizedLeaf`（同 crate，顺手）。同规则的还有两处树整体替换点：`init_layout` / `reset_layout`（`lib.rs:3499, 3691`）。
2. **reconcile 时校验自愈（兜底）**：`reconcile_tree` 读 `MaximizedLeaf` 时校验「节点存在 && 是 Leaf && 从 root 可达（`leaves_under(root)` 含它）」，不满足则视为 None 并清资源（清一次触发下一帧全树重物化，兄弟自动复显）。覆盖场景：最大化叶的最后一个 tab 被关（`dock.close_tab` → `remove_tab` → `simplify` 把非 persistent 空叶折叠，`tree.rs:562-573, 657-709`）→ 叶消失 → 最大化自动退出、布局自动还原；**persistent 叶**（built-in 区域，`tree.rs:107-116`）被清空则保留空占位、维持最大化——与非最大化时空占位行为一致。
3. **扩展启停：语义保持（不清除）**。`cleanup_window_on_remove`（`crates/jackdaw_api_internal/src/lifecycle.rs:738-754`）对 live tree 与所有 workspace 树做 `remove_window_kind`——树变化 → 全树重物化：被移除的正是最大化窗口且叶内还有别的 tab → 最大化保持（显示剩余 tab）；叶空则走规则 2 自动退出。无需新代码。
4. **面板打开操作的退出规则**：新面板可能被加进**被隐藏**的叶（`open_window_in_default_area` 的 canonical 查找 `find_by_area_id` 遍历全 nodes 含隐藏叶，`lib.rs:3638`；`add_window_popup` 的 `add_window_to_area` 按 area entity 定位，`add_window_popup.rs:202-214`），用户会「点了没反应」。规则：**打开动作的落点叶 ≠ 最大化叶时，先退出最大化再执行**（含 PIE 自动 surface Game 面板的路径 `game_panel.rs:446-448` → `open_window_in_default_area_if_absent`）。落点 == 最大化叶则不退出（最大化视口里点 `+` 加 tab 不应跳回）。实现为 panels crate 的单个 helper（`exit_maximize(world)`），在 `open_window_in_default_area`、`open_window_in_default_area_if_absent`、`add_window_to_area` 三处落点判断后调用；`open_window_in_default_area_if_absent` 需为测试放开可见性（有先例：`init_layout` 为测试 pub，`lib.rs:3451-3452`）。

### D5. operator + 键位（遵循 CONTRIBUTING.md「Writing an operator」全规范）

注册在 `src/dock_ops.rs` 的 `add_to_extension`（`dock_ops.rs:20-23`，与 `dock.close_tab` / `window.resize_panel` 同家）：

| 项 | 值 |
|---|---|
| id | `panel.toggle_maximize` |
| label | Toggle Panel Maximize |
| description | "Expand the panel under the cursor to fill the layout, or restore it."（面向用户一句话，不提实现） |
| params | `window_id(String, default = "", doc = "Window the panel holds, such as \"jackdaw.inspector.components\". Empty means the panel under the cursor.")`（String default 已支持，CONTRIBUTING:199；空串 = 走 `PanelFocus` 解析） |
| is_available | `can_toggle_maximize`：已最大化 → true（可还原）；否则焦点可解析出叶 **且该叶有父 split**（root 单叶布局无可隐藏的兄弟 → 灰掉）。签名 `fn(PanelFocus, Res<DockTree>, Res<MaximizedLeaf>) -> bool`（SystemParam 可用，先例 `no_modal_active(ActiveModalQuery)`，`command_palette.rs:98`） |
| allows_undo | `false`（布局视图态，同 `dock.close_tab` / `window.resize_panel` 均不进 undo） |
| modal | 否 |

**快捷键：Shift+Space，冲突检查结论——无 preset 冲突，一处 minor 竞争需顺带修复：**

- **preset 侧**：operator 默认键经 `ctx.bind_operator::<CoreExtensionInputContext, DockToggleMaximizeOp>([PresetInput::key("Space").shift()])` 记入 `DefaultKeymap`（`jackdaw_api_internal/src/lib.rs:420-448`；`.shift()` 存在，`keymap/types.rs:130-137`）。全仓 preset 绑定中**没有任何绑定用 Space 键**（rg `KeyCode::Space` / preset 扫描仅命中：命令面板 **Ctrl**+Space（`command_palette.rs:28-37`，修饰键不同不冲突，且走 `bindings!` 不进 preset）；`key_display_name` 表；测试工具）。
- **需顺带修复的竞争**：`crates/jackdaw_feathers/src/tree_view.rs:1652` 树行键盘激活吃 **裸 Space**（`just_pressed(Space)`，不看修饰键）——焦点在树行上按 Shift+Space 会「展开行 + 最大化」双发。修法：该处加 Shift 排除（`!any_pressed([ShiftLeft, ShiftRight])`），与 `src/keybinds.rs:28-34` `unwanted_modifier` 的哲学一致（更具体和弦胜过裸键）。
- **文本输入安全**：`disable_keyboard_input_when_typing`（`src/keybind_focus.rs:75-90`）在 typing/录制/Live 捕获时整体关掉键盘 action 源——输入框里按 Space 不会误触发，零额外代码。
- Alt+Space 被否（Windows 系统菜单键）；Ctrl+Space 被否（命令面板）；F11 被否（语义是整个 OS 窗口全屏，易混）。

**UI 入口（成本允许，加）**：面板标签栏右排（现有 `+` 与 grip 之间，`crates/jackdaw_panels/src/tabs.rs:91-148` `right_row`）加一个图标按钮：

- panels crate 侧：marker `DockTabMaximizeButton { area_entity }` + `Icon::Maximize` 图标（lucide 该图标已被 `src/ui_layout_presets.rs:230` 使用，存在性已验证）；最大化中换 `Icon::Minimize`（实现期核对 lucide_icons 版本是否有 `Minimize`，无则保持 Maximize 图标 + 高亮态）。
- editor 侧：`src/dock_ops.rs` 加 click observer（照抄 `on_close_button_click` 模式 `:179-191`：marker → `NodeBinding` → 取该叶 active tab 的 window_id → `commands.operator(PanelToggleMaximizeOp::ID).param("window_id", …).call()`）。
- 图标状态切换（maximize↔restore 视觉）挂进 `sync_leaf_visuals` 同款时机（tree 或 `MaximizedLeaf` is_changed 时刷叶右排图标）。
- 不做面板标签右键菜单：tabs 目前无 context menu 接线，从零接 `jackdaw_feathers::context_menu` 成本高于一个常驻图标，收益相同。

### D6. 测试策略

**结论：三层——panels crate 纯单测（树查询/校验函数）+ `tests/panels/` headless 集成（树状态与 UI 可见性断言、持久化 round-trip、reconcile 用例），全部走 `tests/util/mod.rs:127` `editor_test_app()` 模式；operator 派发照抄 `tests/resource_panel/edit_undo.rs:49-62` 的 `world_mut().operator(id).param(...).call()`。**

- 树/UI 断言不走快照（`util::snapshot` 只含文档+编辑器状态）：直接断言 `MaximizedLeaf` 资源、`NodeBinding` 实体的 `Node.display`、`DockSplit.fraction`。
- 自动保存防抖：`fixed_frame_clock`（`util/mod.rs:198`）+ `update_until`（`:155`）推进 >0.5s 虚拟时间。
- 测试草案（新目录 `tests/panels/`，`main.rs` 挂 mod）：
  1. `maximize_toggle.rs`：Editor 态 → 对 inspector 所在叶 toggle → `MaximizedLeaf == Some(leaf)`、其余叶宿主 `Display::None`、最大化叶内容可见、各 split `fraction` 逐项不变 → 再 toggle → 资源 None、全部 `Display::Flex`、fraction 仍逐项不变（D1 恢复语义回归）。
  2. `persistence_roundtrip.rs`：最大化 → 推进 >0.5s 触发自动保存 → 读 `ProjectRoot.config.layout` 反序列化 `WorkspacesPersist` → 断言树 == 最大化前快照（叶数/tabs/fraction）；再走 `init_layout` 重载 → 树正确且 `MaximizedLeaf == None`（D3）。
  3. `reconcile.rs`：（a）最大化 → `WorkspaceChanged` 事件切换 workspace → 断言树已换且 `MaximizedLeaf` 清除；（b）最大化 → `dock.close_tab` 关掉最大化叶最后一个 tab（用运行时 split 出的非 persistent 叶，或断言 persistent 叶保留占位）→ 自动退出、兄弟复显（D4-2）；（c）最大化 → `open_window_in_default_area` 打开隐藏区窗口 → 先退出最大化（D4-4，需把该 fn 放开为 pub）；（d）`window_id` 指向不存在窗口 → `Cancelled` 且状态不变。
  4. panels crate 单测：`subtree_contains`（新树查询 helper）、`MaximizedLeaf` 校验/清除纯逻辑。

---

## 2. 技术方案

### 2.1 模块 / 文件布局

```
crates/jackdaw_panels/src/
  maximize.rs              （新）MaximizedLeaf 资源 + exit_maximize(world) helper + 校验函数
  tree.rs                  （改）新增 subtree_contains(root, target) 查询（含单测）
  reconcile.rs             （改）reconcile_tree gate 加 MaximizedLeaf 变化；读入时校验自愈；
                            reconcile_split 末尾按最大化状态对兄弟 set_host_visible（post-order）；
                            sync_leaf_visuals 同步图标状态（若做图标切换）
  workspace_tabs.rs        （改）on_workspace_changed_swap_tree 切树时清 MaximizedLeaf
  tabs.rs                  （改）tab 栏 right_row 增 DockTabMaximizeButton 图标（marker + spawn）
  lib.rs（panels）         （改）挂 maximize 模块、init_resource
src/
  dock_ops.rs              （改）PanelToggleMaximizeOp operator + is_available + 注册/绑键
                            （Space+shift）+ 图标 click observer
  panel_focus.rs           （改）新增 PanelFocus::focused_panel() -> Option<String>
  lib.rs                   （改）init_layout / reset_layout 清 MaximizedLeaf；
                            open_window_in_default_area[_if_absent] 落点在隐藏叶时 exit_maximize；
                            open_window_in_default_area_if_absent 放开为 pub（测试用，有 init_layout 先例）
crates/jackdaw_feathers/src/tree_view.rs （改）裸 Space 树行激活排除 Shift
README.md / book/src/user-guide/keyboard-shortcuts.md （改）快捷键表加 Shift+Space
tests/panels/              （新）main.rs + 4 个测试文件
loop/plans/roadmap-gap-analysis.md （改）Stage 4「可全屏面板」❌ → ✅
```

### 2.2 关键接口草图（示意，非最终签名）

```rust
// crates/jackdaw_panels/src/maximize.rs（示意）
#[derive(Resource, Clone, Debug, Default)]
pub struct MaximizedLeaf(pub Option<NodeId>);

/// 退出最大化（不动树；清资源即触发 reconciler 复显兄弟）。
pub fn exit_maximize(world: &mut World);

/// reconcile 读入用：节点存在 && 是 Leaf && root 可达。不可达返回 None。
pub fn validate(tree: &DockTree, candidate: Option<NodeId>) -> Option<NodeId>;

// reconcile.rs 内（示意，post-order 施加）
fn reconcile_split(...) {
    ...现有子节点递归...
    let max = validate(tree, maximized.0);
    if let Some(target) = max {
        if tree.subtree_contains(split.a, target) { set_host_visible(child_b_entity, false); }
        else if tree.subtree_contains(split.b, target) { set_host_visible(child_a_entity, false); }
    }
}

// src/dock_ops.rs（示意）
#[operator(
    id = "panel.toggle_maximize",
    label = "Toggle Panel Maximize",
    description = "Expand the panel under the cursor to fill the layout, or restore it.",
    allows_undo = false,
    is_available = can_toggle_maximize,
    params(window_id(String, default = "",
        doc = "Window the panel holds, such as \"jackdaw.inspector.components\". \
               Empty means the panel under the cursor."))
)]
fn panel_toggle_maximize(
    In(params): In<OperatorParameters>,
    focus: PanelFocus,
    mut tree: ResMut<DockTree>,
    mut maximized: ResMut<MaximizedLeaf>,
) -> OperatorResult {
    // 已最大化 → 无条件还原（toggle 的另一半）
    if maximized.0.is_some() { maximized.0 = None; return OperatorResult::Finished; }
    // 解析目标：参数 > 焦点
    let window_id = params.as_str("window_id").filter(|s| !s.is_empty())
        .or_else(|| focus.focused_panel());  // 或 None → Cancelled
    ...find_leaf_with_window → set_active(leaf, tab) → maximized.0 = Some(leaf)...
}
```

### 2.3 数据流

```
Shift+Space（keymap action）──┐
tab 栏图标 click（observer）──┼→ panel.toggle_maximize operator
命令面板 / 远程 API ──────────┘        │
                                       ├─ 已最大化 → MaximizedLeaf = None
                                       └─ 否则 → PanelFocus/参数解析 window → find_leaf_with_window
                                                  → set_active(leaf, tab) → MaximizedLeaf = Some(leaf)
reconciler（tree 或 MaximizedLeaf 变化时全树重物化）
  └─ 每层 split：subtree_contains 判方向 → set_host_visible(兄弟, false/true)（post-order）
       └─ Panel.set_changed → recalculate_group（只算可见 Panel）→ 最大化子树占满 / 还原比例
持久化：DockTree 全程未动 → auto-save / 手动保存 / workspace 快照天然存"未最大化"的正确布局
树整体替换（workspace 切换 / init / reset）→ 显式清 MaximizedLeaf
树局部变化（关 tab / 扩展启停）→ 重物化时 validate 自愈（叶没了自动退出）
面板打开落点在隐藏叶（Window 菜单 / + 弹窗 / PIE surface）→ exit_maximize 后再开
```

---

## 3. 任务拆分（2 个任务）

### 任务 1（程序）：核心机制——最大化状态 + reconciler + operator + 键位

- **内容**：`maximize.rs`（资源/helper/校验）+ `tree.rs` `subtree_contains` + `reconcile.rs` gate 扩展与兄弟隐藏（post-order）+ 三处树替换点清除 + 三处面板打开路径退出规则 + `panel_focus.rs` 访问器 + `dock_ops.rs` operator（is_available/注册/绑 Shift+Space）+ `tree_view.rs` Shift 排除 + panels crate 单测 + `tests/panels/` 四个集成测试。
- **验收清单**（逐条可判定）：
  1. `maximize_toggle.rs` 全绿：toggle 后资源/可见性/fraction 断言 + toggle back 完整还原（fraction 逐项相等）；
  2. `persistence_roundtrip.rs` 全绿：最大化状态自动保存的 layout JSON == 最大化前树；重载后 `MaximizedLeaf == None`；
  3. `reconcile.rs` 四个用例全绿（workspace 切换清除 / 叶清空自动退出（persistent 叶保留占位）/ 隐藏区打开先退出 / 坏 window_id Cancelled）；
  4. Shift+Space 无 preset 冲突（`find_conflicts` 空）；焦点在树行上按 Shift+Space 不再触发树展开（tree_view 单测或集成断言）；
  5. 命令面板可搜到 "Toggle Panel Maximize" 并执行；`cargo xtask fast` + `integration` 通过。
- **跑的门**：fmt / clippy -D warnings / lib tests + 新增 `tests/panels/` 集成。
- **预估触碰**：见 2.1 中除 tabs 图标、README/book、盘点表外的全部条目。

### 任务 2（程序 + QA + 文档）：tab 栏图标入口 + 文档 + 全量门

- **内容**：`tabs.rs` `DockTabMaximizeButton` 图标（最大化态图标/高亮切换，`Icon::Minimize` 不存在则退化方案）+ `dock_ops.rs` click observer + README 快捷键表 + book `keyboard-shortcuts.md` 补 Shift+Space 一行与「最大化面板」小节 + `roadmap-gap-analysis.md` Stage 4 行改 ✅；全量 CI 门（fast + integration + docs + doctests）+ 视觉验收截图（最大化/还原两态，QA 子代理看图）。
- **验收清单**：
  1. 每个叶的 tab 栏出现最大化图标，点击等效 operator；最大化中图标呈「还原」态（或高亮态）；
  2. 最大化/还原过程无 UI 残留（无幽灵 handle、无空白条）——截图比对；
  3. README/book 快捷键表含 Shift+Space；盘点表 Stage 4「可全屏面板」✅ 且证据列指向本功能提交；
  4. CI 集四命令全绿（fmt / clippy --all-targets --features dylib / xtask fast / xtask integration / doc / doctests）。
- **预估触碰**：`tabs.rs`、`reconcile.rs`（图标态刷新）、`dock_ops.rs`、`README.md`、`book/src/user-guide/*.md`、`loop/plans/roadmap-gap-analysis.md`。

---

## 4. 给 QA 的验收清单

**确定性门（全部必须绿）**
- [ ] `cargo fmt --all -- --check`
- [ ] `cargo clippy --workspace -- -D warnings`（CI 档含 `--all-targets --features dylib`）
- [ ] `cargo xtask fast`
- [ ] `cargo xtask integration`（含 `tests/panels/` 4 文件）
- [ ] `cargo doc --locked --workspace --document-private-items --no-deps`
- [ ] `cargo test --locked --workspace --doc --features bevy/dynamic_linking`

**headless 行为断言（自动测试覆盖）**
- [ ] toggle 进出：资源态、兄弟 Display、最大化叶内容可见（maximize_toggle）
- [ ] 布局还原：toggle 前后每个 split 的 fraction 逐项相等（maximize_toggle）
- [ ] 最大化中自动保存 → 持久化树 == 最大化前；重载后无最大化态（persistence_roundtrip）
- [ ] workspace 切换清最大化；最大化叶被清空自动退出（persistent 叶保留占位）；隐藏区开窗先退出；坏 window_id Cancelled（reconcile）
- [ ] Shift+Space 不与命令面板（Ctrl+Space）/树行裸 Space 激活冲突

**视觉项（人工，少量）**
- [ ] 最大化/还原过渡无闪烁、无残留 handle/空白；tab 栏与 `+`/grip 排布不跳版；
- [ ] 视口、Inspector、动画时间线各最大化一屏截图，观感与 Figma 风格一致；
- [ ] 图标悬停/还原态可辨识。

**文档项**
- [ ] README 与 book 快捷键表含 Shift+Space；
- [ ] roadmap-gap-analysis.md Stage 4「可全屏面板」✅。

---

## 5. 风险与对策

1. **reconciler 隐藏与叶级 auto-collapse 的写序竞争**（`reconcile_leaf` 的 `set_host_visible(visible)` 可能与兄弟隐藏互相打架）：对策已内建——隐藏严格 post-order（子先父后），本方案在 `reconcile_split` 末尾施加；测试 1 的可见性断言即回归守卫。
2. **NodeId 跨树碰撞**（workspace 切换后同 id 异节点）：显式清除是主防线，校验自愈是兜底；测试 3(a) 锁定。残余风险：未来新增「整体换树」的代码点忘记清除——对策：`validate` 的可达性检查覆盖绝大多数错乱形态，且本方案在 `maximize.rs` 文档注释里写明「任何整体替换 DockTree 的路径必须清 MaximizedLeaf」。
3. **`Icon::Minimize` 在当前 lucide_icons 版本可能不存在**：实现期核对；退化方案 = 常驻 Maximize 图标 + 最大化态高亮（ACCENT_BLUE 边框，同 sidebar icon active 样式 `reconcile.rs:630-634`）。纯视觉，不阻塞。
4. **隐藏子树内的延迟初始化**（面板 build fn 在 Display::None 下首次构建，个别面板可能假设自己可见，如视口相机尺寸）：最大化叶本身始终可见，风险仅在**被隐藏**的兄弟——它们多数在会话早前已构建过；新会话立即最大化的场景由 QA 视觉项覆盖。若发现具体面板异常，单独修该面板的 resize 监听，不改本机制。
5. **PIE 期间最大化他处**：Game 面板按规则 4 会先退出最大化（`game_panel.rs:446` 走 `open_window_in_default_area_if_absent`），Play 自动可见——正是想要的；但如果 Game tab 已在其（隐藏）叶中存在且为 active，`if_absent` 只 `set_active` 不开新窗——需确认该路径也走退出判断（落点叶 != 最大化叶即退出）。已列入测试 3(c) 变体。
6. **`window.resize_panel` 等按 window_id 找叶的 operator 在最大化期间命中隐藏叶**：行为语义正确（改的是真实树的 fraction，还原后生效），仅即时视觉不可见——文档写明即可，不改。

---

## 6. ⚠️ 需用户裁决项

1. **最大化期间打开面板的默认行为**：本方案取「落点在被隐藏区域 → 自动退出最大化再打开」（推荐，用户永远看得见结果）；备选「Blender 式严格保持最大化，新 tab 静默进隐藏叶等还原」。影响 D4-4 的三处调用点与测试 3(c)，不影响架构。
2. **tab 栏图标是否首版就做**（任务 2 的主体）：不做则功能纯靠 Shift+Space + 命令面板，任务 2 缩为纯文档+QA。本策划倾向做（成本小、可发现性大增），但若希望本轮再瘦身可砍。

---
*证据快照：仓库 main `35db5c74`（2026-10-22，含功能 #1 Resource Inspector）。所有路径结论可按文中 file:line 复核；未运行任何 cargo 命令。`Icon::Minimize` 存在性、lucide 版本差异为唯一标注「实现期核对」项。*
