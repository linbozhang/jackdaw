# 功能 #1 任务 2 报告：Resources 面板编辑链路与增删

- 分支：`loop/resource-inspector`，提交 `04d941ba`（`Add resource editing commands, operators and field routing`，11 files，+1312/-48）
- 基线：任务 1 提交 `c461ba37`（经 main 合并 `f4a72b5d` fast-forward）
- 执行者：程序 Agent（Rust/Bevy 工程师），2026-10-22
- 需求来源：`loop/plans/feature-01-resource-inspector.md` §4 任务 2 + §D1/D3/D5/D7 + §2.2

## 1. 实现内容

### 新增 `src/inspector/resource_commands.rs`

- **`ResourceSetField`**（EditorCommand）：单资源单字段写。`old_value/new_value` 存
  **serde_json::Value**（非方案草图的 `BsnValue`，见偏差 2）：资源无文档落点，JSON 直接对接既有
  `apply_json_field_to_ecs` / `apply_json_map_entry_to_ecs`（map-entry 感知）与 `reflect_to_json` 旧值捕获；
  `execute` 首次执行时若未带基线则惰性捕获 live 值；`undo` 回写 old，old 为 None 时字段复位类型默认
  （复用 `reset_ecs_field_to_default`）。
- **`ResourceInsert`**：默认构造值写入资源。`ResourceInsert::buildable(world, type_path)` 先校验
  （registry 有 `ReflectResource` 标记 + `build_reflective_default` 可构造），不可构造则 operator 早退、
  不产生空 undo 条目；execute 时若资源已存在则捕获被替换值（undo 恢复旧值而非删除）。
- **`ResourceRemove`**：`from_world` 构造时捕获当前值（`reflect_clone`，失败退 `to_dynamic`）；
  execute 走安全 API `World::remove_resource_by_id`，随后若 `resource_entities` 缓存仍有残留条目，
  经 commands 摘 `IsResource` marker（其 discard hook 清缓存与残余值）——保证缓存闭环无幻影行；
  undo 用捕获值原样重插。
- **`resource_field_preview` / `resource_field_commit`**：与 `field_edit_preview/commit` 手势语义对齐的
  资源版两段提交。`ResourceFieldEditSessions`（Resource）在首个 preview tick 捕获 pre-gesture 基线
  （拖拽每 tick 改 ECS，commit 时基线不能读已变的现值）；commit 时 no-op 编辑（old == new）不入栈，
  对齐 `field_edit_commit` 的去重规则；入栈走 `CommandHistory::push_executed`。
- **`is_resource_entity(world, entity)`**：实体上有 bevy `IsResource` marker 即资源实体（见偏差 1）。
- 所有命令 execute/undo 均置 `ResourceCardDirty`（面板卡片重建信号）。

### 新增 `src/inspector/resource_ops.rs`（挂在 `src/core_extension.rs:333`，紧邻 inspector::ops）

按 §D5 表三 operator，`allows_undo` 全部保持默认 true（自动文档快照空转，自建命令是唯一条目）：

| id | label | is_available | params |
|---|---|---|---|
| `resource.insert` | Add Resource | （恒可用） | `type_path(String)` |
| `resource.remove` | Remove Resource | `has_visible_resource` | `type_path(String, default = "")`，空 = 面板当前选中 |
| `resource.set_field` | Set Resource Field | `has_visible_resource` | `type_path` / `field` / `value(JSON)` |

description 逐字采用 §D5 草案（"Add a resource of this type." 等）。`has_visible_resource` =
面板选中项是当前列表行（行即"已实例化且可见"的构造性证据）；insert 另校验可见性过滤器，
insert 成功后自动选中新资源（卡片立即打开）。

### `src/inspector/reflect_fields.rs` 出口分流（6 处，均在汇聚点）

- `apply_field_json_with_undo`（文本/数值/复选的 final commit 汇聚点）→ 资源实体早退到 `resource_field_commit`；
- `apply_field_value_live`（拖拽 tick 预览）→ `resource_field_preview`；
- `apply_color_with_undo`（颜色 final；顺带把 canonical JSON 构造从两份合并为一份，非资源行为不变）；
- `apply_enum_variant_with_undo`（枚举）；
- `edit_reflect_list`（列表增删移）；
- **PIE 守卫**：`try_route_pie_live_field_edit` 入口对资源实体直接 `return false`（D3-5 的断言性早退）。

分流判定统一为 `is_resource_entity`（源实体带 bevy `IsResource`），资源卡控件从不落回
`SetBsnField`/Selection 管线——QA 披露的"选中实体恰有同 type_path 组件被误写"情形从结构上消除
（资源路径不读 `Selection`）。

### `src/inspector/resource_panel.rs`

- **Add Resource 按钮**（搜索框旁，`Icon::Plus`）+ 资源类型 picker（复用 `PickerProps` 模式：
  `Matchable`（haystack=短名、category=分组序）+ `picker_item`/`match_text`/Tooltip，全路径作 tooltip
  描述；`EditorEntity` + `BlocksCameraInput` 与组件 picker 一致；再点关闭）。
  `enumerate_insertable_resources`：registry 有 `ReflectResource`、可默认构造、可见性允许、未实例化。
- **Remove 按钮**：卡片 body 顶部 `ButtonProps::from_operator::<ResourceRemoveOp>()`（无参 dispatch，
  operator 回退到面板选中即本卡资源）。
- **`ResourceCardDirty`**：commit/insert/remove 后强制重建卡片（列表长度、枚举变体形状等结构变化；
  任务 1 遗留 2 的枚举部分由此覆盖，undo/redo 同样触发）。
- **refresh 收敛**：列表 shown/wanted 比较从"全 world 的 ResourceRowButton"改为"该 mount 子节点内的行"
  ——消除多面板实例并存时（测试手动 spawn + 内置窗口）的每帧无谓重建（探测证据：修复前 shown 恒含
  另一实例的 5 行导致 shown≠wanted 每帧成立）。
- `plugin()` 补 `init_resource::<ResourceFieldEditSessions>` 与 Add 按钮 observer。

### 改动（既有文件最小触碰）

- `src/commands.rs`：`reset_ecs_field_to_default`、`apply_json_map_entry_to_ecs` 两处 `fn` → `pub(crate) fn`
  （资源写路径复用，无行为改动）。
- `src/core_extension.rs`：+1 行注册。`src/inspector/mod.rs`：+2 行挂模块。

### 测试 `tests/resource_panel/`（+3 文件 8 测试，套内合计 16）

- `edit_undo.rs`（4）：值改 + 栈恰 +1（同时证明自动文档快照无空条目）+ undo 还原 + redo 复现；
  no-op 编辑不入栈；卡片重建后数值控件持有新值（`ScrubNumberInputValue::I64(42)`，断言控件值组件
  而非 feathers 文本上屏时机）；**窄情形守卫**：选中实体带同 type_path 组件时资源卡编辑绝不写该实体
  （bevy 资源唯一性会延迟移除重复组件，测试对"组件在/不在"两态都断言其值不为 42）。
- `insert_remove.rs`（3）：insert → `resource_entities` 缓存命中 + 面板行出现 + 默认值；undo → 资源消失 +
  缓存无幻影 + 行消失；redo → 复现；remove → undo 原值恢复（points=5 保留）；不可构造/非资源类型
  （`Entity`、`Name`）insert 不产生条目。
- `no_pie_leak.rs`（1）：Live 模式 + 把资源实体人为接入 `PieProjection.by_bits` 的敌意布线下，
  set_field 后资源值变、`LiveEditLog` 条目为零（无 PIE 控制流/记录）。

undo 断言口径按 §D7：CommandHistory 栈长 + `world.resource::<T>()` 值断言，未用 `util::snapshot`。

## 2. 与方案偏差（均有现场证据）

1. **分流锚点从 marker 改为实体判定**：方案 D3-3 让各 observer 出口查 `ResourceFieldTarget` marker。
   实现改为在 6 个汇聚点查 `is_resource_entity`（bevy `IsResource` marker 在源实体上）。原因：颜色
   commit 闭包、枚举菜单 observer、列表按钮三处拿不到 binding 实体（闭包只捕获 source_entity）；
   且实体判定不受 marker 漏 stamp/过期影响，天然覆盖 QA 披露的窄情形。`ResourceFieldTarget` marker
   保留，供面板刷新 pass 区分自家控件（任务 1 用途不变）。
2. **`ResourceSetField` 存 JSON 而非 `BsnValue`**（§2.2 草图）：资源不落 .bsn，JSON 直接对接既有
   apply/serialize 辅助，省一次有损转换。
3. **插入路径 A/B 结论：A（全安全 API）成立，B 未用**。比方案预想更简单：bevy `#[derive(Resource)]`
   把 `IsResource::new(id)` 注册为 **required component**（`bevy_ecs/macros/src/resource.rs:18-25`），而
   `ReflectComponent::insert` 走 typed `entity.insert(component)`（`reflect/component.rs:314-319`），
   required component + `IsResource::on_insert` hook 自动维护 `ResourceEntities` 缓存——无需手插 marker，
   更不需要 unsafe `insert_resource_by_id`。`insert_round_trips_through_undo` 的缓存闭环断言为证。
4. **`resource.remove`/`set_field` 的 `is_available`**：D5 的"该资源已实例化且可见"依赖 type_path 参数，
   而 `is_available` 是无参 system——落为"面板选中项是当前列表行"（行的存在性即实例化+可见）。
   副作用：未打开面板/未选中时命令面板调用会被门挡（按 CONTRIBUTING「state 检查进 is_available」）。
5. **新测试不再手动 spawn 面板内容**（偏离任务 1 的测试模式）：headless 下进入 Editor 态会构建内置
   `jackdaw.inspector.resources` 窗口面板，手动再 spawn 会形成双实例；任务 1 测试因内容恒定未暴露，
   本任务的"插入后行出现"断言则会读到未刷新的那块。改用窗口面板（单实例）+ refresh 的 shown 比较
   收敛到 mount（偏差见上），双实例下也不再每帧重建。
6. **触碰文件超方案预估**：`src/commands.rs`（2 处可见性提升）未列于 §2.1 清单；`reflect_fields.rs`
   的颜色出口顺带合并了重复的 canonical JSON 构造（行为等价）。

## 3. 各门退出码与测试数

| 门 | 命令 | 退出码 | 关键输出 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | 0 | 无 diff |
| Lint | `cargo clippy --workspace -- -D warnings` | 0 | 通过 |
| 快档 | `cargo xtask fast` | 0 | 含 fmt check + clippy `--all-targets --features dylib -D warnings` + nextest lib：`2716 tests run: 2716 passed, 2 skipped` |
| 集成 | `cargo xtask integration` | 0 | nextest：`4830 tests run: 4830 passed, 3 skipped`（任务 1 基线 4822 → +8 恰为本任务新增测试数） |

**既有套回归**：integration 全绿含 `tests/inspector/`（19 文件）与 `tests/operators/` 全部——出口分流
无回归；`tests/resource_panel/` 原有 8 测试（任务 1）也全绿（单跑确认 16/16）。
另注：调试期间一次非标准部分过滤运行中 `reflect_auto_register::auto_registered_types_cross_the_dlopen_boundary`
曾失败一次（dlopen dylib 与并行构建竞态），标准 `cargo xtask integration` 门内通过，非本任务代码路径。

## 4. 遗留问题 / 交给任务 3

1. **Add picker 无 headless 断言**：picker 枚举为模块私有函数，主链路（insert operator + 面板行出现）
   已由 `insert_round_trips_through_undo` 覆盖；picker 自身的过滤/选择可留 QA 或任务 3 补公开辅助后加。
2. **"会话态"提示文案**未加（方案 §7.1 主控裁决项，任务 3 文档口径）。
3. **map-entry 字段**的 preview/commit 走 `apply_json_map_entry_to_ecs`（与 field_edit 同源），无专门测试
   （既有 map-entry 覆盖在 `src/commands.rs` 单测，资源路径复用同一实现）。
4. 视觉项（scrub/颜色/枚举下拉在资源卡上的观感、Add/Remove 按钮布局）留任务 3 人工验收，同任务 1 顺延项。

## 5. 自查确认

- `git diff main..HEAD` 相对任务 1 仅新增本任务内容；无 book 文档、无盘点表更新（任务 3 范围）、
  无 `loop/` 改动入 git（本报告在 loop/ 下不入库）。
- 新代码零 `#[allow]`/`#[expect]`；operator id 全部经 `<Op>::ID` 常量或宏注册引用，无裸字符串 dispatch
  （测试内按 id 字符串 dispatch 是测试惯例）。
- `Cargo.lock` 未动。
