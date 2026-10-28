# 功能 #4 任务 2 报告：depgraph 过滤、着色、反查 UI

> 多 Agent 开发循环 · 程序（Rust/Bevy 工程师）· 2026-10-22
> 分支 `loop/system-graph`，基于 main `f3e08b88`（任务 1 已合入），提交见文末
> 改动 5 文件，+768/-20：`src/remote/debug/depgraph.rs`（主体）、`graph.rs`、`schedules.rs`（常量）、`relationships.rs`（构造点适配）、`debug/mod.rs`（注册）；另有本报告（`loop/reports/`）

## 实现内容（对照方案任务 2 清单 + D4/D3）

1. **`AccessFilter` resource + 过滤纯函数族**（`depgraph.rs`）：
   - `AccessFilter { components: Vec<String>, source: FilterSource }`，`FilterSource::Manual | Selection { used }`——手动编辑（picker 加/chip 删/清空）一律翻回 `Manual`，Selection 只在 From-selection 解析时写入；
   - `access_matches(&SystemInfo, &str)`：主键全路径相等 → `style::short_type_name` 短名兜底（D3-3 名字空间分歧对策）；`exclusive` 与 `kind == "unbounded"` 恒命中（QA ②，见下）；
   - `matches_filter`（Manual=AND 全命中才命中，空过滤=不过滤）/ `matches_any`（OR，反查语义）；
   - `access_component_options(&SchedulesReply)`：全 reply 访问名并集做 picker 候选（D3-5，候选必然可命中），**排除空串 component**（QA ①）；
   - `node_color(filtering, hit)`：未过滤=现状默认色（回归锚点）；命中=`ACCENT_BLUE.with_alpha(0.28)`（沿用 relationships 面板根节点先例）；非命中=同底色 `alpha 0.35` 暗化；歧义红边框在 `spawn_graph_positioned` 内逻辑不动、优先级最高；
   - `access_badge(&SystemInfo)`：`R{n} W{n}` 读/写计数；unbounded→`ALL`、exclusive→`EXCL`、无解读条目→`None`；
   - `selection_components(Option<u64>, &[RemoteEntity])`：BRP Live 反查纯函数（cache 键排序）；`local_selection_components(&World)`：本地 `Selection` 实体 archetype 兜底（`Components::get_info().name()`，与访问表同源命名）。
2. **过滤行 UI**（queries.rs 的 picker+chips 范式，D4-4）：
   - 面板骨架在 schedule 选择行与歧义 banner 之间加 `DepgraphFilterRow`；内容 = `Add component` 按钮（picker，标题 "Filter by component access"）+ 已选 chips（点击移除）+ `From selection` 按钮 + `Clear` 按钮（过滤非空时才出现）；
   - observers：`on_add_access_filter_clicked`（toggle 关已开 picker；候选空则不开）、`on_access_filter_chip_clicked`、`on_clear_filter_clicked`、`on_from_selection_clicked`，注册于 `debug/mod.rs`；
   - picker 选中写入 `AccessFilter` 且去重；与 queries 面板的 picker 通过各自 marker（`AccessFilterPicker` vs `FilterPicker`）互不干扰。
3. **From selection 反查**（D3，方案 OR）：
   - 点击 → `commands.queue` 延迟闭包（observer 参数与 `&mut World` 互斥，走仓库既有 deferred-world 模式）：优先 `RemoteSelection.selected` + `RemoteSceneCache` 组件键（`scene_snapshot` 的 reflect type_path）；远程空/实体已 despawn → 本地 `Selection`（authoring/PIE preview）archetype 兜底；两链皆空 → 过滤原样不动（不炸）；
   - 按钮禁用态在 rebuild 时按「两链任一有选中」评估（`ButtonVariant::Disabled` 自带 `InteractionDisabled`，不触发点击）；连接期间 1s 轮询每 tick 重写 `SchedulesReply`，禁用态随之刷新；
   - meta 行显示 `from selection: N components`（`used` 为解析时实际生效组件数——snapshot SKIP 前缀导致的缺项可感知，D3-3）。
4. **着色与徽标接线**（D4-2/3）：
   - `GraphNodeSpec` 增 `subtitle: Option<String>`（`#[derive(Default)]`，无 subtitle 时节点结构与现状逐字节一致）；徽标为节点框内 label 下小字（`TEXT_SIZE_XS` muted）；
   - `spawn_graph` 增 `node_colors: &[Color]` 参数（方案给出的「实现期取小改法」），depgraph 自算颜色传入；
   - `rebuild_depgraph` 触发条件追加 `filter.is_changed()`（与 `selected.is_changed()` 并列）。
5. **老游戏降级**（D4-7 + 本任务范围第 4 条）：`access_reported == false` 时过滤行整体替换为 muted 提示 `component access data requires a newer jackdaw_remote`，徽标/着色/反查/清空全部隐藏，图退回今天形态（`node_color(false, _)` = 默认色）；meta 行另附 `access data unavailable`。
6. **kind 字符串常量**（`schedules.rs`）：`ACCESS_READ/WRITE/UNBOUNDED`——过滤/徽标逻辑零魔法字符串（代码红线）。

## QA 两条交底落实证据

- **① picker 候选排除空串**：`access_component_options` 只收非空 `component`；单测 `access_options_exclude_empty_components_and_dedup`（reply 含 `{component:"", kind:"unbounded"}` 条目，断言候选恰为两个真实类型名且去重）PASS。
- **② kind/exclusive 恒命中**：`access_matches` 对 `exclusive == true` 直接 true、对任一 `kind == "unbounded"` 条目直接 true（EntityMut 类系统不漏）；单测 `unbounded_and_exclusive_match_any_component`（两个任意组件 × unbounded/exclusive 双系统 × `access_matches`/`matches_filter` 双入口）PASS；且反查 OR 路径 `matches_any` 复用同一 `access_matches`，语义自动一致。

## 测试（新增 11 个，全过；fast 门 2796/2796）

AND 全命中 / OR 任一命中 / 短名兜底（含跨名字空间正例+短名不匹配反例）/ unbounded+exclusive 恒命中 / 候选排除空串+去重 / 颜色三态（含无过滤=默认色回归锚点）/ 徽标 R2W1 计数 / ALL+EXCL+None / selection_components 排序提取 / 无选中与实体缺失两空态。纯函数全部单测（D6-3）；无 headless UI 遍历断言（D6-4 维持现状档位）。

## 各门退出码

| 门 | 结果 | 证据 |
|---|---|---|
| `cargo check -p jackdaw` | 0（PASS） | 迭代 2 轮后 `Finished`（首轮 `ComponentId` 解引用 + 测试模块导入两处小修） |
| `cargo fmt --all -- --check` | 0（PASS） | 应用 fmt 后复跑无 diff |
| `cargo clippy --workspace -- -D warnings` | 0（PASS） | 方案 §5 原文命令；let-chain 收敛 collapsible_if 后通过 |
| `cargo xtask fast` | 0（PASS） | `Summary: 2796 tests run: 2796 passed, 2 skipped`（任务 1 为 2785，+11 恰为新增测试）；链内含更严的 `clippy --workspace --all-targets --features dylib -- -D warnings` 亦过 |
| `cargo xtask integration` | 0（PASS） | `Summary: 4927 tests run: 4927 passed, 3 skipped` |

两门合计 7723 通过，零回归。

## 与方案偏差点

1. **`node_color(filtering, hit)` 双参**：方案草图 `node_color(hit)` 单参无法表达「未过滤=默认色」，双参使回归锚点可单测。
2. **`spawn_graph` 加 `node_colors` 参数**而非 depgraph 直调 `spawn_graph_positioned`：方案 D4-2 明示的两个小改法之一，layered 布局逻辑留在 graph.rs 内。
3. **From-selection 走 `commands.queue` 延迟闭包**：bevy observer 参数（`On<>`/`Query`/`Commands`）与 `&mut World` 互斥（bevy_ecs system_param 冲突测试证实），仓库既有模式（game_panel.rs 等）；本地兜底需要 archetype 遍历故必须 World。
4. **archetypal-only 系统无徽标**：方案只约定 R/W/ALL/EXCL 四态；纯 `Has<T>` 系统计数 R0 W0 → `None`（不加新徽标态，避免色彩/文案过载）。
5. **meta 行降级附注 `, access data unavailable`**：D4-7 只要求过滤行提示；此为 2 行补充（未连接/老游戏均可感知），如主控认为越界可删。
6. **kind 常量放 `schedules.rs`** 而非 depgraph 内：常量属 reply 线格式定义处，server（serde rename）/editor（常量）两侧各自声明、互不依赖（方案 D1 裁决维持）。

## 既有问题备注（非本次引入）

`cargo clippy --workspace --all-targets -- -D warnings`（无 `--features dylib`）在 `tests/component_shape_refresh.rs:1` 报 `unfulfilled-lint-expectations`：该文件整体 `#![cfg(feature = "dylib")]`，无 feature 时 crate 被剥空、`#![expect(clippy::print_stdout)]` 落空。该文件不在本次 diff（git log 证实先于任务 1 存在），官方两门（方案原文 clippy 命令、xtask fast 带 dylib 的 clippy）均不受影响。建议后续单独小修（expect 挪进 cfg 内或改 allow）。

## 遗留 / Concerns（给任务 3）

- schedules 面板 `system_box` 读写徽标、`examples/remote_game.rs` 人工 QA（过滤高亮/From selection/老版本降级驱动）、帧尖刺真机复测、book 文档、`roadmap-gap-analysis.md` 盘点行更新——全部留任务 3，本次未触碰。
- From-selection 按钮禁用态在「非连接且无本地选中」时由 rebuild 时机评估：BRP 断开后 reply 不再刷新，若此时本地选中从有到无，按钮可能短暂保持可点——点击后解析为空即 no-op（`apply_selection_filter` 空集合直接 return），无错误命中风险（方案风险 6 同款结论）。
- 本地兜底的组件名含编辑器视图类组件（如 hierarchy/transform 编辑器侧组件）——PIE preview 实体场景下过滤候选并集来自游戏侧访问表，短名兜底可能带来少量跨名字空间额外命中；保守方向（宁多亮不漏）且实际反查语境是 BRP Live（远程优先命中，不走兜底）。
- 无过滤时徽标恒渲染（方案 D4-3 主路径）；「仅过滤激活时渲染徽标」的一行开关备而未用，若大图卡顿任务 3 可启用。

## 提交

- 分支 `loop/system-graph`，单 commit：`Add component access filtering and selection-driven highlighting to the depgraph` = `88968fcf`（5 files，+768/-20）。`loop/` 目录按仓库惯例被 .gitignore，本报告仅落盘不入库。
