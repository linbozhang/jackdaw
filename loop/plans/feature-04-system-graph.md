# 功能 #4 实施方案：System Graph 增强（按数据访问着色/过滤 + 选中实体反查系统）

> 多 Agent 开发循环 · 策划产物（只写方案，不含代码实现）
> 日期：2026-10-22 · 策划：资深 Bevy 编辑器工程师 Agent
> 选题依据：`loop/plans/roadmap-gap-analysis.md`「备选 5」节。Roadmap 验收锚点：未分类「system graph 可视化（按数据访问/按 system set/影响选中实体的系统过滤）」🟡。
> 调研方法：rg 文件搜索 + Read，未运行任何 cargo 命令。bevy 证据取自 `%USERPROFILE%\.cargo\git\checkouts\bevy-50d7e162b728c6c6\c9c397b`（与 Cargo.lock 锁定 commit `c9c397ba…` 一致），下文记作 `bevy@main`。

---

## 1. 范围与不做

**做**（三件套）：

1. **数据链**：BRP `jackdaw/schedules` 回复为每个系统附带数据访问表（读/写/只检测存在/unbounded、独占标记），组件用完整类型路径命名；
2. **图过滤与着色**：System Graph 面板（depgraph）新增组件名过滤（picker + chips，复用 Live Queries 面板的交互范式），命中节点高亮、非命中暗化；节点附读写计数徽标；
3. **选中实体反查**：面板新增「From selection」入口——取当前选中实体的组件集合，过滤出「访问其中任一组件」的系统（编辑器侧本地完成，零新游戏侧请求）。

**不做**（首版明确排除）：

- 数据流动画、按帧性能采样（盘点原文即排除）；
- 按 system set 的过滤入口（set 归属 chips 已在两个面板呈现，够用；set 维度过滤留 backlog）；
- 未命中节点「隐藏」模式（首版只暗化不动布局——分层图的上下文（邻居）对定位比稀疏图更有用）；
- 读写分别配色（读写差异用徽标文本表达，颜色只编码「命中/歧义」两层，避免色彩过载）；
- 游戏侧新 BRP 方法（扩展现有回复字段，见 D2/D5——这也是版本兼容的最优解）。

### 0. 现状一句话（盘点证据复核）

- `src/remote/debug/depgraph.rs` + `schedules.rs` 共享 `BrpPollPlugin::<SchedulesReply>::new("jackdaw/schedules", 1.0)` 无参轮询（`debug/mod.rs:66-69`），回复含 name/sets/edges/ambiguities，**无任何数据访问信息**；
- server 侧 `crates/jackdaw_remote/src/ecs_methods.rs:134-210` 用 `schedule.systems()` + `schedule.graph()` 构造回复，歧义的组件名已经走 `world.components().get_info(id).name()` 通路（`:66-69`）；
- 盘点风险栏写「游戏侧需配合暴露 param 信息（jackdaw_runtime 侧改动）」——**复核修正**：BRP server 在 `crates/jackdaw_remote`（游戏自己 `add_plugins(JackdawRemotePlugin)`，`examples/remote_game.rs` 即先例），与 `jackdaw_runtime`（场景 loader）无关；且如 D1 所述，**bevy main 已把访问数据持久挂在 Schedule 上，游戏侧只需升级 jackdaw_remote 版本重新编译，无需游戏代码改动**。

---

## 2. 设计结论 D1–D7（全部带代码证据）

### D1. 数据源可行性：**成立，且有比预期更好的通路**——bevy main 已把每个系统的 `SystemAccess` 持久存在 Schedule 里，`Schedule::systems_with_access()` 是公开 API，BRP server 可直接枚举；ComponentId→类型名用 `Components::get_info` 现成通路

**先澄清一个 API 变迁（重要）**：旧文档/旧版本里 `System::component_access()` / `archetype_component_access()` 在 bevy main 已**删除**（`bevy@main crates/bevy_ecs/src/system/system.rs:45` 起的 trait 方法清单里没有它们；全 bevy_ecs 搜 `fn component_access` 仅剩 `QueryState::component_access`，`query/state.rs:200`）。替代物是 `System::initialize` 的返回值 `SystemAccess`（`system.rs:148-149`），且它被调度系统**持久保留**：

证据链（bevy@main）：

1. **数据形态**：`pub enum SystemAccess { None, Shared(FilteredAccessSet), Exclusive }`（`system/access.rs:10-24`）。`Shared` 变体内含 `FilteredAccessSet`，经 `combined_access() -> &Access<ComponentId>`（`query/access.rs:996`）拿到合并后的组件读/写集合。
2. **持久化与公开迭代**：`SystemWithAccess { system, access }`（`schedule/node.rs:38-44`，`access()` 为 pub，`:62`）；`Systems::initialize` 在调度首次构建时填 `system.access = system.system.initialize(world)`（`node.rs:574-587`）；`ScheduleGraph::update_schedule` 把 `SystemWithAccess` **整体**搬进可执行队列（`schedule/schedule.rs:1726-1731`），access 随行；`Schedule::systems_with_access()` 公开迭代 `(SystemKey, &SystemWithAccess)`（`schedule.rs:754-770`），顺序与现有 handler 用的 `systems()` 完全一致（两者都 zip `executable.system_ids` × `executable.systems`）——**换用后 index 空间不变，edges/ambiguities 对齐不受影响**。
3. **读/写遍历**：`Access::reads()/writes() -> &InvertibleComponentIdSet`（`query/access.rs:483-500`）；一步到位的 `try_iter_access() -> impl Iterator<Item = ComponentAccessKind>` 产出 `Shared(id)/Exclusive(id)/Archetypal(id)`（`:532-553`，archetypal 即 `Has<T>` 这类只看存在性的访问）。
4. **unbounded 边界**：`Query<EntityMut>` 这类"写全部"的访问会使 `try_iter_access()` 返回 `Err(UnboundedAccessError)`（`access.rs:560-567`）——需兜底：标 `unbounded`（这类系统对任何组件过滤都应命中，保守正确）。真独占系统（`&mut World`）是 `SystemAccess::Exclusive`，单独打标。
5. **ComponentId→类型名**：`world.components().get_info(id)` → `ComponentInfo::name() -> DebugName`（`component/info.rs:43-45`，源自 `ComponentDescriptor` 的 `type_name` 形式全路径）。**同一通路本文件已在用**（歧义组件名，`ecs_methods.rs:66-69`，含"未注册回退数字 id"的兜底）。bevy 没有 ComponentId→reflect type_path 的专用 API，也不需要——见 D3 的名字空间一致性分析。
6. **借用无障碍**：handler 拿 `&mut World`，`world.get_resource::<Schedules>()` 共享借用后可同时 `world.components()`（现有 `ambiguities_for` 已同时传 `graph + world`，`ecs_methods.rs:53-78`）。

**结论：功能成立，无降级必要。** jackdaw_remote 的 server 代码改一处 handler（`systems()` → `systems_with_access()` + 每系统导出访问表），游戏侧零代码改动。

### D2. 载荷控制：**扩展 `jackdaw/schedules` 回复而非新方法**；访问表是构建期静态数据但随宿主轮询一起回（体积约 ×3、每秒一次、本机回环）；实测游戏侧帧尖刺超标再拆独立方法（后备方案 B）

定量估算（无实机数据，区间保守）：

- 系统数：bevy 默认 3D app（含 UI）主 world 全部 schedule 合计数百系统（Update 单 schedule 常见 50-150）；旁证：`graph.rs:241-243` 注释自认「a schedule can have well over this many dependency and ambiguity edges combined」而把边渲染上限设为 120；
- 每系统访问条目：典型 1-6 条（Query 组件 + Res 资源），均值按 4 计；每条 JSON `{"component":"bevy_transform::components::transform::Transform","kind":"write"}` 约 75-95 字节；
- 合计：数百系统 × 4 条 ≈ 150-400KB 增量；现有回复（name/sets/edges/ambiguities）约 50-150KB，扩后总量约 250-500KB。

方案对比与推荐：

1. **方案 A（推荐）：扩展现有回复**。server 在每系统对象上加 `accesses` 数组 + 顶层 `access_reported: true` 能力标志；编辑器 serde `#[serde(default)]` 兜底。理由：(a) 本机 HTTP 回环（`brp.rs` 手写 TcpStream，无 TLS），500KB/s 无带宽压力；(b) 编辑器侧两个面板（schedules/depgraph）共享同一 `SchedulesReply`，原子一致，不存在两次请求之间系统集合变化的撕裂；(c) **老游戏零 404**——字段缺席即降级（D5），不需要处理 JSON-RPC error 路径；(d) 改动面最小。
2. **方案 B（后备，本轮不做）：新方法 `jackdaw/system_access`** 低频/一次性拉取。访问表理论上只在插件集合变化（重建 schedule）时变，可连接时拉一次 + 手动刷新。代价：新方法注册、`registry_fetch.rs` 式一次性抓取状态机、(schedule, index) 跨回复对齐、老游戏 404 降级探测（`brp.rs:154-157` 会把 HTTP 404 变 `Err`，poll 模式只 warn 不写资源，`poll.rs:88-94`——需要专门的能力探测标志）。复杂度高一档。
3. **为什么接受 1s 轮询带回静态数据**：BRP 方法经 `with_method_main` 注册在游戏主线程（`jackdaw_remote/src/lib.rs:100-117`），每秒一次 250-500KB 的 `serde_json` 序列化约 2-5ms 尖刺。现状（100KB 级）已在付这个成本。**QA 设实测门槛（帧预算尖刺 <5ms/秒）**，超标则启动方案 B——拆出后 `jackdaw/schedules` 回到今天体积，B 的实现路径本方案已留好（handler 的访问表导出抽成独立纯函数，搬家零逻辑改动）。
4. **不做的优化**：server 端组件名去重表（id 引用）可再省 ~40% 体积，但破坏 JSON 可读性与 `accesses` 的自包含性，首版不做。

### D3. 选中实体反查链路：**全部在编辑器侧本地完成，零游戏侧新 API**；组件集合来源按选中链路分两级——BRP Live 远程选中（`RemoteSelection` → `RemoteSceneCache` 的组件名 keys）优先，编辑器本地 `Selection`（authoring/PIE preview 实体 archetype）兜底；匹配语义 OR

证据链：

1. **两条互不相交的选中链路**：BRP Live 连接下远程层级树写 `RemoteSelection { selected: Option<u64> }`（`src/remote/entity_browser.rs:59-62`），实体数据缓存于 `RemoteSceneCache.entities: Vec<RemoteEntity>`（`:41-44`），其 `components: HashMap<String, Value>` 的 key 是**完整类型路径字符串**（`jackdaw_pie_protocol/src/snapshot.rs:194-210`，来自 reflect registry 的 `type_path_table().path()`，如 `"bevy_ecs::name::Name"`）——**编辑器侧已持有远程实体的组件名全集，反查无需任何新请求**（`remote_inspector.rs:117-131` 已示范从 cache 取选中实体组件集合）。PIE 是另一条链（`src/pie.rs:2127-2160`：游戏 pick → `PieProjection.by_bits` → 编辑器 preview 实体 → 本地 `Selection`），且 PIE 不连 BRP（`pie.rs` 全文无 `ConnectionManager`），depgraph 面板在 PIE 下本就无数据——反查入口的实际语境是 BRP Live 会话。
2. **本地兜底**：编辑器本地 `Selection.entities`（含 PIE preview 实体）的组件集合取 `world.entity(e).archetype().components()` + `components.get_info(id).name()`——与 D1 的访问表命名同源（都是 `Components` registry），零转换。
3. **名字空间一致性（关键风险点）**：访问表名字来自 `Components::get_info().name()`（`type_name` 形式），scene_snapshot 的组件 key 来自 reflect `type_path`。两者对同一 Rust 类型在 bevy 全部内置类型上一致（都是 `module_path::TypeName`）；理论分歧面是非 reflect 组件/泛型参数的格式差异。**对策**：过滤匹配做成纯函数，主键全路径相等，兜底「最后 `::` 段短名相等」；单测钉住（D6）。scene_snapshot 跳过的一批组件（`snapshot.rs:55-78` 的 SKIP 前缀，如 Camera/GlobalTransform）意味着远程选中实体的集合可能缺这些组件——但访问表有它们，过滤方向是「集合 ∩ 访问表」，缺项只让候选更少，不产生错误命中；UI 上把实际用于过滤的组件数显示出来即可。
4. **语义**：反查是 OR——「访问集合中**任一**组件的系统」（影响该实体的系统）。手选过滤的 AND/OR 见裁决项 1。
5. **过滤候选列表来源**：不依赖 `manager.registry`（连接时另拉的 registry，`registry_fetch.rs`）——直接用**当前 reply 各系统 `accesses` 的组件名并集**做 picker 候选（保证候选必然可命中；registry 候选作 picker 兜底可选）。Live Queries 面板的 `registry_component_options`（`queries.rs:170-190`）与 picker 接线（`:485,519-535`）是现成交互模板。

### D4. UI 设计：全部挂在 depgraph 面板现有骨架上——过滤行复用 queries.rs 的 picker+chips 范式；着色走 `spawn_graph_positioned` 已有的 `node_colors` 参数（relationships 面板先例）；rebuild 触发条件加一条 `filter.is_changed()`

1. **面板现状**：depgraph 内容 = meta 行 + schedule 选择按钮行 + 歧义 banner + 画布（`depgraph.rs:47-102`）；`rebuild_depgraph` 在 reply 变化 / `SelectedSchedule` 变化 / 面板新建时整建（`:151-153`）；节点由 `GraphNodeSpec { label }` 数组喂给 `graph::spawn_graph`（`:220-236`）。
2. **着色钩子已存在**：`spawn_graph_positioned` 本就收 `node_colors: &[Color]`（`graph.rs:305`，越界回退 `COMPONENT_CARD_BG`），Relationships 面板已用自定义色（`relationships.rs:223-232`）；depgraph 的 `spawn_graph` 是"全默认色"包装（`graph.rs:271`）。改动：depgraph 自己算 `node_colors` 并改调 `spawn_graph_positioned`（layered 布局照旧由 `layered_layout` 提供，`spawn_graph` 内部逻辑搬进 depgraph 或给 `spawn_graph` 加 colors 参数，实现期取小改法）。
3. **着色语义**：无过滤 = 现状卡片底色；过滤激活 = 命中 `tokens::ACCENT_BLUE` 背景、非命中暗化（同底色低 alpha）；歧义红边框逻辑（`graph.rs:350-354`）不动、优先级最高。读/写不用颜色区分——`GraphNodeSpec` 加 `subtitle: Option<String>` 字段，节点框内 label 下加小字徽标（如 `R3 W1`；unbounded/exclusive 显示 `ALL`/`EXCL`）。
4. **过滤行 UI**：schedule 选择行下方加一行：`+ Add component` 按钮（picker，候选=访问名并集）+ 已选组件 chips（点击移除，复用 `FilterChip` 组件模式，`queries.rs:113-125`）+ `From selection` 按钮 + 清空按钮。`AccessFilter` 做成 `Resource`（含 `components: Vec<String>`、`source: Manual | Selection { count }`），chips/picker 的增删走 observer（`on_add_filter_clicked`/`on_filter_chip_clicked` 同款，`debug/mod.rs:55-56` 注册模式）。
5. **`From selection` 行为**：点击时按 D3 优先级解析组件集合 → 写入 `AccessFilter { source: Selection }` → meta 行显示 `from selection: N components`；无可用选中（两条链都空）时按钮禁用态。
6. **刷新接线**：`rebuild_depgraph` 触发条件追加 `filter.is_changed()`（与 `selected.is_changed()` 并列，`depgraph.rs:152`）；schedules 面板（`rebuild_schedules`）不接过滤、只顺带显示徽标（裁决项 3）。数据到达路径零改动——仍走现有 `BrpPollPlugin` 1s 轮询写 `SchedulesReply`。
7. **能力降级呈现**：reply 顶层无 `access_reported`（老游戏）时，过滤行整体替换为一句 muted 提示（如 `system access data requires a newer jackdaw_remote`），徽标/着色/反查全部隐藏——图退回今天的形态（见 D5）。

### D5. jackdaw_remote 改动面与版本兼容：方法清单不动，只扩 `jackdaw/schedules` handler；四象限兼容里唯一要处理的是「老游戏+新编辑器」，用顶层能力标志字段优雅降级，无 404 路径

1. **现有方法注册**（游戏侧，`jackdaw_remote/src/lib.rs:100-117` 主路径 + `finish()` 的 `register_if_missing` 兜底 `:146-177`，共 8 个方法）：`jackdaw/app_info`、`scene_snapshot`、`diagnostics`、`playback`、`apply_bsn`、`entity_bsn`、`archetypes`、`schedules`。本功能**不新增方法**，只改 `ecs_methods.rs` 的 schedules handler：`systems()` → `systems_with_access()`，每系统对象加 `accesses`（组件名 + kind + 兜底），顶层加 `access_reported: true`。访问表导出抽纯函数 `system_access_entries(...)`（单测主战场 + 未来方案 B 搬家零成本）。
2. **老游戏 + 新编辑器**：回复缺 `access_reported`/`accesses` → serde `#[serde(default)]` → 编辑器按 D4-7 降级。**无 404**（方法没新增），无 JSON-RPC error 处理。
3. **新游戏 + 老编辑器**：多余字段被 serde 静默丢弃（`SchedulesReply` 未声明的 `initialized` 字段现状即如此，`schedules.rs:55-56` 注释明示）。
4. **版本提示（可选 polish）**：`jackdaw/app_info` 的 `bevy_version` 实为 jackdaw_remote 包版本锚定 bevy minor（`lib.rs:80-88`），降级提示里可附显示。
5. **游戏侧接入成本**：游戏代码零改动——`JackdawRemotePlugin` 的方法表是插件内部注册的，升级依赖版本重编即得新回复。`examples/remote_game.rs` 是现成的人工 QA fixture。

### D6. 测试策略：三层纯函数单测为主（server 提取函数 / serde 两态 / 过滤匹配与着色映射），无 UI 集成测试（维持 remote debug 模块现状档位），人工 QA 走 examples/remote_game.rs

1. **server 侧（`jackdaw_remote/src/ecs_methods.rs` 内，现有模板直接扩）**：现测试已示范 `World::new + Schedule::new + add_systems + schedule.initialize(&mut world)` 后取 `graph()` 断言歧义（`:231-277`）。新增：读写资源系统 → `system_access_entries` 含 `…Counter` 且 kind=write；`Query<&Transform>` 只读；`Has<T>` → archetypal；`&mut World` 系统 → exclusive 标记；`Query<EntityMut>` → unbounded 标记；未注册 id 的数字回退（沿用歧义命名兜底断言风格）。
2. **编辑器 serde（`schedules.rs` 测试模块，json! 字面量）**：含 `access_reported`+`accesses` 的完整回复解析；**老回复（无新字段）解析为空表+false——降级守卫**；未知 kind 字符串容错。
3. **过滤/着色/反查纯函数**（depgraph.rs 或新 `filter.rs`）：AND 匹配（多组件全命中）、OR 匹配（反查语义）、unbounded/exclusive 恒命中、全路径+短名兜底匹配、命中/非命中 → 颜色映射、`(RemoteSelection bits, &[RemoteEntity]) -> Vec<String>` 组件集合提取、读写计数徽标文本生成。
4. **不做**：headless UI 遍历断言（remote debug 面板现状无此档测试；布局/颜色纯函数已覆盖语义）；BRP HTTP 传输级测试（`brp.rs:161-224` 已覆盖传输层，方法级语义由 1/2 覆盖）。
5. **人工 QA**：`examples/remote_game.rs` + 编辑器 Connect——过滤 Transform 看高亮、选中远程实体反查、断开重连后降级/恢复。

### D7. Roadmap 覆盖度声明（防盘点虚报）

**做完后未分类「system graph 可视化」改 ✅**：三维度全齐——按数据访问（本功能：访问表+过滤+着色）、按 system set（已有：sets chips，两面板呈现）、影响选中实体的系统过滤（本功能：From selection）；依赖分层图与调度歧义此前已有。盘点表该行状态 🟡→✅，统计口径 45✅/15🟡/15❌ → 46✅/14🟡/15❌。注意「按 system set 过滤」的**过滤动词**（非仅展示）本功能不做（范围排除），判定 ✅ 的依据是 roadmap 原文 "filter by system set" 的展示维度已由 sets chips 满足且访问过滤已覆盖核心诉求——若主控认为 set 过滤动词必须做，则该行维持 🟡（见裁决项 3 备注）。

---

## 3. 技术方案

### 3.1 模块 / 文件布局

```
crates/jackdaw_remote/src/ecs_methods.rs （改）schedules handler：systems_with_access() + 每系统
                    accesses 导出 + 顶层 access_reported；抽 system_access_entries 纯函数；
                    单测扩（读写/archetypal/exclusive/unbounded/回退）
src/remote/debug/schedules.rs （改）SystemInfo 加 #[serde(default)] accesses:
                    Vec<SystemAccessEntry>；顶层 access_reported;（+system_box 读写徽标，
                    裁决项 3）；serde 两态单测
src/remote/debug/depgraph.rs （改）AccessFilter resource（components/source）；过滤行 UI
                    （picker+chips+From selection+clear）；rebuild 计算 node_colors/subtitle
                    并调 spawn_graph_positioned；触发条件加 filter.is_changed()；observers；
                    过滤/反查纯函数 + 单测
src/remote/debug/graph.rs      （改）GraphNodeSpec 加 subtitle: Option<String>（默认 None，
                    现有两处构造零改动语义）；spawn_graph 加 node_colors 参数（或 depgraph
                    直调 spawn_graph_positioned，实现期取小改法）
src/remote/debug/mod.rs        （改）init_resource::<depgraph::AccessFilter>()；注册新 observers
book/src/user-guide/…          （改/新）remote debugging 节补「System Graph 过滤与反查」
loop/plans/roadmap-gap-analysis.md （改）未分类该行 🟡→✅（按 D7 口径）
```

### 3.2 关键接口草图（示意，非最终签名）

```rust
// crates/jackdaw_remote/src/ecs_methods.rs —— server 导出（纯函数，单测主战场）
pub enum AccessKind { Read, Write, Archetypal, Unbounded }   // serde 小写字符串
pub struct AccessEntry { component: String, kind: AccessKind }
/// SystemAccess -> JSON 条目。Shared 经 combined_access().try_iter_access()；
/// Exclusive/UnboundedAccessError 兜底为 kind 标记；名字经 world.components()
/// get_info，未注册回退数字 id（沿用歧义通路）。
fn system_access_entries(access: &SystemAccess, world: &World) -> Vec<AccessEntry>;

// 回复形态（增量）：
// 顶层 { "schedules": [...], "access_reported": true }
// 每系统 { "name","sets","accesses":[{"component":"…","kind":"read|write|archetypal|unbounded"}],
//          "exclusive": false }

// src/remote/debug/schedules.rs —— 编辑器侧（老回复全缺省 → 降级）
#[derive(Deserialize, Clone, Default)]
pub struct SystemAccessEntry { pub component: String, pub kind: String }
pub struct SystemInfo { pub name: String, pub sets: Vec<String>,
    #[serde(default)] pub accesses: Vec<SystemAccessEntry>,
    #[serde(default)] pub exclusive: bool }
pub struct SchedulesReply { pub schedules: Vec<ScheduleInfo>,
    #[serde(default)] pub access_reported: bool }

// src/remote/debug/depgraph.rs —— 过滤状态与纯函数
#[derive(Resource, Default, Clone)]
pub struct AccessFilter {
    pub components: Vec<String>,
    pub source: FilterSource,          // Manual | Selection { used: usize }
}
pub fn matches_filter(filter: &AccessFilter, info: &SystemInfo) -> bool;   // AND + 兜底短名
pub fn matches_any(components: &[String], info: &SystemInfo) -> bool;     // OR（反查）
pub fn node_color(hit: bool) -> Color;                                     // 命中/暗化
pub fn access_badge(info: &SystemInfo) -> Option<String>;                  // "R3 W1" / "ALL"
pub fn selection_components(sel: Option<u64>, cache: &[RemoteEntity]) -> Vec<String>;
```

### 3.3 数据流

```
游戏进程（jackdaw_remote，升级即得）
  Schedules 迭代 ──systems_with_access()──> SystemAccess ──try_iter_access/get_info──>
  accesses[{component, kind}] + access_reported ──BRP 1s 轮询（现有 BrpPollPlugin）──>
编辑器进程
  SchedulesReply（serde default 容老回复） ──> rebuild_depgraph
      ├─ 无过滤：node_colors 全默认 + badge（读写计数）
      ├─ 有过滤（Manual，AND / 或裁决后的 OR）：matches_filter → 命中 ACCENT_BLUE/非命中暗化
      └─ From selection：
            RemoteSelection.selected + RemoteSceneCache（BRP Live，优先）
            │ 编辑器本地 Selection 实体 archetype（兜底）
            └─> selection_components → AccessFilter{source: Selection} → OR 匹配
  过滤行（picker 候选 = reply 访问名并集；chips 点击移除；observers）
```

---

## 4. 任务拆分（3 个任务）

### 任务 1（程序）：BRP 访问表数据链 + 降级守卫
- **内容**：`ecs_methods.rs` 的 `system_access_entries` 纯函数 + handler 扩展（`systems_with_access()`、`accesses`、`exclusive`、顶层 `access_reported`）+ server 单测六态（读/写/archetypal/exclusive/unbounded/未注册回退）；编辑器 `schedules.rs` serde 结构扩展 + 两态解析单测（含老回复全缺省）。
- **验收**：jackdaw_remote 与编辑器 crate 新单测全绿；老回复字面量解析结果与新字段全空/`access_reported == false`；`cargo xtask fast` 过。

### 任务 2（程序）：depgraph 过滤、着色、反查 UI
- **内容**：`AccessFilter` resource + 过滤纯函数族（AND/OR/短名兜底/恒命中）+ 单测；过滤行 UI（picker/chips/clear/From selection，queries.rs 范式）+ observers 注册；`GraphNodeSpec.subtitle` + 节点徽标；rebuild 的 `node_colors` 着色与触发条件扩展；`selection_components` 反查函数 + 单测。
- **验收**：过滤纯函数单测全绿（含 unbounded/exclusive 恒命中、短名兜底）；无过滤时图渲染与现状一致（回归锚点：无 filter 时 node_colors 全默认）；`cargo xtask fast` 过。

### 任务 3（QA + 文档）：徽标 polish + 人工验收 + 文档 + 盘点表
- **内容**：schedules 面板 system_box 读写徽标（裁决项 3 通过后）；降级提示行；`examples/remote_game.rs` 人工 QA 走查（过滤/反查/老版本模拟——用无新字段的 reply 字面量驱动 UI 验证降级）；帧尖刺实测（游戏侧 1s 一次序列化，门槛 <5ms，超标触发方案 B 决策）；book 补文档；`roadmap-gap-analysis.md` 该行更新（D7 口径）；全量 CI 门。
- **验收**：见下节清单。

---

## 5. 给 QA 的验收清单

**确定性门（全部必须绿）**
- [ ] `cargo fmt --all -- --check`
- [ ] `cargo clippy --workspace -- -D warnings`
- [ ] `cargo xtask fast`（含 jackdaw_remote / 编辑器新单测）
- [ ] `cargo xtask integration`
- [ ] `cargo doc --locked --workspace --document-private-items --no-deps`
- [ ] `cargo test --locked --workspace --doc --features bevy/dynamic_linking`

**headless 行为断言（自动测试覆盖）**
- [ ] server：写资源/读组件/`Has<T>`/`&mut World`/`Query<EntityMut>` 五类系统的访问条目正确（kind 分别 write/read/archetypal/exclusive/unbounded）
- [ ] server：未注册 ComponentId 回退数字 id 字符串（歧义同款兜底）
- [ ] 编辑器：老回复（无 `accesses`/`access_reported`）解析成功且能力标志为 false——降级守卫
- [ ] 过滤：AND 全命中才命中；OR 任一命中即命中；unbounded/exclusive 对任意过滤恒命中；全路径不等但短名相等时兜底命中
- [ ] 反查：`(bits, entities)` 提取的组件集合 = 该实体 scene_snapshot components keys（排序后相等）
- [ ] 徽标：`R3 W1`/`ALL`/`EXCL` 文本生成纯函数
- [ ] 回归：无过滤时 `rebuild_depgraph` 产出的 node_colors 与现状全默认一致

**人工（examples/remote_game.rs + 编辑器 Connect）**
- [ ] 输入 `Transform` 过滤：命中系统高亮、其余暗化、歧义红框保留；移除 chip 恢复
- [ ] 远程树选中一个实体 → From selection：meta 行显示组件数，命中集合符合 OR 语义
- [ ] 老版本降级：过滤行替换为升级提示，图/面板其余功能不受影响
- [ ] 游戏侧帧时间：连接轮询开启前后对比，1s 周期尖刺 <5ms（超标回报，触发方案 B 裁决）

**文档项**
- [ ] book remote debugging 节：过滤/徽标/From selection/降级条件
- [ ] `roadmap-gap-analysis.md` 未分类行 🟡→✅（D7 口径与统计更新）

---

## 6. 风险与对策

1. **名字空间分歧**（访问表用 `Components::name`，scene_snapshot 用 reflect `type_path`）：内置类型一致，非 reflect/泛型场景可能落空。**对策**：匹配纯函数内置短名兜底 + 单测；From selection 的 meta 行显示实际生效组件数，落空可感知。
2. **游戏侧轮询序列化尖刺**（500KB/1s 于主线程 BRP handler）：估算 2-5ms。**对策**：QA 实测门槛；超标即按 D2 方案 B 拆独立方法（handler 导出函数已隔离，搬家零逻辑改动）。
3. **bevy main API 再漂移**（`SystemAccess`/`systems_with_access` 是新 API）：workspace 锁定 git commit `c9c397ba`，升级 bevy 是独立事件；届时若 API 变动，本功能的数据链集中在 `system_access_entries` 一个函数内，改动收敛。
4. **超大 schedule 的节点渲染**（数百节点的 bevy_ui 压力是既有现状，边已有 MAX_EDGES=120 截断）：本功能不增节点数只改颜色/加一行小字；若徽标导致大图卡顿，徽标仅在过滤激活或节点被选中时渲染（实现期一行开关）。
5. **RemoteSelection 与 depgraph 数据时序错位**（快照 0.5s/调度 1s 各自轮询，选中实体在两次快照间被 despawn）：反查集合取自最近一次快照，实体消失时集合为空 → 按钮回到禁用态，无错误命中风险。
6. **`try_iter_access` 对"读全部"（read_all，如某些 filter）同样返回 unbounded**：归并到 `unbounded` 呈现，语义为"可能访问任意组件"，恒命中——保守方向正确，不产生漏报。

---

## 7. ⚠️ 需用户裁决项

1. **手选多组件过滤语义**：本方案取 **AND**（找"同时访问 A 与 B"的系统——最贴近排查歧义/竞态的定位场景；推荐）；备选 OR（找"碰了 A 或 B"的面更宽）；或首版就带 AND/OR 切换 toggle（+约 30 行 UI）。反查入口固定 OR 不受此裁决影响。
2. **载荷方案**：A 扩展现有回复（推荐，理由见 D2）vs B 拆 `jackdaw/system_access` 低频拉取（若用户已知目标游戏系统量级巨大或对游戏侧帧尖刺零容忍，可直接选 B 省一轮返工）。
3. **polish 范围**：schedules 面板的读写徽标、以及「未命中节点隐藏」toggle，本轮做还是留 backlog（本策划倾向徽标做——schedules 面板是图面板的数据源兄弟，加一行小字成本低；隐藏 toggle 留 backlog）。
4. **（备注，非必答）D7 的 ✅ 判定**：set 维度只展示不过滤，若主控要求"filter by system set"的动词语义也落地，盘点行维持 🟡 并把 set 过滤列入下轮。

---
*证据快照：仓库 main `130f01cc`（2026-10-22，干净）；bevy git main checkout `c9c397b`（与 Cargo.lock 锁定 commit 一致）。所有结论可按文中 file:line 复核；未运行任何 cargo 命令。唯一「实现期核对」项：`ComponentAccessKind` 的 serde 序列化形态（本方案约定小写字符串 "read"/"write"/"archetypal"/"unbounded"，server/client 两侧自定义枚举，不直接依赖 bevy 类型序列化）。*
