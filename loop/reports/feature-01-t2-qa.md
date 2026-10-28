# 功能 #1 任务 2 QA 验收报告：Resources 面板编辑链路与增删

- QA：独立验收 Agent，2026-10-22
- 对象：`loop/resource-inspector` 分支提交 `04d941ba`（11 files，+1312/-48，基于 main `f4a72b5d`）
- 需求口径：`loop/plans/feature-01-resource-inspector.md` §4 任务 2 验收清单（6 条）+ §D1/D3/D5/D7；任务 1 QA 报告 concerns ②（窄情形误写）为本次必须消除项
- 方法：四门自己重跑记退出码与测试计数；全量 diff 逐行读；关键机制（IsResource required component、remove_resource_by_id、资源唯一性 hook）到 bevy checkout `c9c397b` 独立核实；不信任程序自述。

## 结论

**VERDICT: PASS** — 四门全 0，规格 6 条全部 ✅，任务 1 QA concerns ② 已消除且有守卫测试，偏差 ①-⑤ 抽验全部属实合理，无 🔴/🟡；5 条 ⚪ 不阻塞。

## 1. 门（QA 重跑，退出码）

| 门 | 命令 | 退出码 | 关键输出 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | 0 | 无 diff |
| Lint | `cargo clippy --workspace -- -D warnings` | 0 | 通过（仅既有 build script `linker_messages` 噪声，与任务 1 时一致，非本任务代码） |
| 快档 | `cargo xtask fast` | 0 | `2716 tests run: 2716 passed, 2 skipped`（内含 fmt check + clippy `--all-targets --features dylib -D warnings`） |
| 集成 | `cargo xtask integration` | 0 | `4830 tests run: 4830 passed, 3 skipped`（334.5s；任务 1 基线 4822 → +8 恰为本任务新增测试数；行首 FAIL 计数 = 0） |

编译日志中 `jackdaw` 各测试 target 报 "1 warning (1 duplicate)" 为同一既有全局 build script 警告的折叠重放（所有测试 target 均有，非 resource_panel 特有），两档 clippy `-D warnings` 均通过证实非 lint 问题。

## 2. 规格符合性（任务 2 验收清单逐条）

1. **set_field 改值 → undo 栈恰 +1 → undo 还原 → redo 复现 — ✅**
   `tests/resource_panel/edit_undo.rs::a_field_edit_round_trips_through_undo`（:64-96）：`resource.set_field` dispatch（`creates_history_entry: true`）→ `points=42` → 栈长恰 `+1`（:70-74）→ `history.undo` → `points=7` → `redo` → `points=42`。integration 实跑 PASS。

2. **文档快照无空条目 — ✅（断言存在且真断言了）**
   栈恰 +1 断言即证明：自动文档快照若在资源命令旁产生条目，栈会 +2；断言注释言明此语义（edit_undo.rs:71-74，insert 侧同款 insert_remove.rs:73-77）。另 `a_no_op_edit_pushes_nothing`（:100-112）断言 no-op 编辑零入栈，`resource_field_commit` 的去重规则（old == new 不入栈）与 `field_edit_commit` 对齐。

3. **insert/remove：缓存出现/消失 + 面板行 + undo/redo — ✅**
   `insert_round_trips_through_undo`（:61-132）：insert → 默认值 0 + `resource_entities().get(id)` 命中（:84-87）+ 面板行出现（:93-97）→ undo → 资源消失 + 缓存无幻影（实体已死仍被缓存则判幻影，:106-114）+ 行消失（:118-122）→ redo 复现。`remove_round_trips_and_restores_the_value`（:134-169）：remove → 消失 + 行消失 → undo 原值 5 恢复。`an_unconstructible_type_inserts_nothing`（:174-187）：`Entity`/`Name` 不可构造不产生条目。

4. **PIE 不泄漏 — ✅**
   `no_pie_leak.rs::resource_edits_do_not_stream_to_pie_in_live_mode`（:42-98）：Live 模式 + 资源实体被人为接入 `PieProjection.by_bits` 的敌意布线下，set_field 后资源值变、栈 +1、`LiveEditLog.entries` 为空。
   **入口守卫代码真实存在**：`try_route_pie_live_field_edit`（reflect_fields.rs:2078-2082）首行对 `is_resource_entity` 直接 `return false`——且 diff 证实各控件出口的资源早退位于所有 `try_route_pie_live_field_edit` 调用之前，守卫为第二道防线（防未来新出口误挂），符合 §D3-5。

5. **既有 inspector/operators 套全绿 — ✅（以 QA 自跑 integration 为准）**
   integration 0 fail：`jackdaw::inspector` 套 153 PASS（`tests/inspector/` 19 文件）、`jackdaw::operators` 套 151 PASS、`tests/resource_panel` 16/16 PASS（任务 1 的 8 个 + 本任务 8 个均绿）——出口分流对既有场景实体路径零回归。

6. **四门通过 — ✅**（见第 1 节，QA 独立重跑）。

### 三 operator 与 §D5 表核对 — ✅

- **id/label/description**：`resource.insert`/"Add Resource"/"Add a resource of this type."、`resource.remove`/"Remove Resource"/"Remove this resource."、`resource.set_field`/"Set Resource Field"/"Set one field on a resource."——三句 description 与 §D5 草案**逐字一致**，均一句话、面向用户、不提 undo/实现 ✅。
- **params**：insert `type_path(String)`（doc 同义）✅；set_field `type_path`/`field`(点路径)/`value(JSON)` 与 `field.set`（ops.rs:376-408）参数形状逐字一致（`param_json` helper 同款，String 先 JSON 解析退字符串）✅；remove `type_path` 加 `default = ""`（空 = 面板选中）——超出 D5 表但为 Remove 按钮无参 dispatch 所需，合理增强。
- **is_available**：insert 未指定 = 宏默认恒可用（`jackdaw_api_internal/src/operator.rs:110-114` "Default: always callable"）✅ 与 D5「恒 true」一致；remove/set_field = `has_visible_resource` ✅（偏差④见 §3）。
- **allows_undo**：三者均未显式设置 = 宏默认 true（`jackdaw_api_macros/src/lib.rs:75`）✅ 与 D1-2 一致（对照：`field.set` 是 `allows_undo = false` 因走自动快照，资源版自建命令是唯一条目，差异正是设计要点）。
- **insert 前置校验**：`buildable`（ReflectResource + 可默认构造）+ 可见性过滤器（resource_ops.rs:67-75），不可构造/不可见早退不入栈 ✅ 与 D5 表说明一致。

## 3. 偏差抽验（程序报告 5 处偏差，重点抽验）

### 偏差①：分流锚点 marker → `is_resource_entity`（6 汇聚点）— ✅ 六出口完整、无一遗漏

diff 逐一核实 6 处全部早退：

| # | 汇聚点 | 位置（新行号） | 覆盖的 §D3-3 observer 族 |
|---|---|---|---|
| 1 | `apply_field_json_with_undo`（final commit 汇聚） | reflect_fields.rs:2173-2179 | 文本提交（:2726）、数值 final（:2726/:2764）、复选（:2764） |
| 2 | `apply_field_value_live`（拖拽 tick 预览） | :2673-2680 | 数值 drag tick（:2728/:2766）、颜色 drag（:1596） |
| 3 | `apply_color_with_undo`（颜色 final） | :1868-1872 | 颜色 plane/slider/hex final（:1593） |
| 4 | `apply_enum_variant_with_undo`（枚举） | :3489-3496 | 枚举菜单提交（:3385） |
| 5 | `edit_reflect_list`（列表增删移） | :3884-3897（if/else） | 列表按钮（:3840） |
| 6 | `try_route_pie_live_field_edit`（PIE 守卫） | :2078-2082（入口 return false） | 所有 PIE 路由的兜底 |

- 文件内 4 处 `crate::commands::field_edit_commit` 直调（:1881/:2185/:3500/:3894）**全部**位于早退之后，资源编辑无路径可达 `SetBsnField`/Selection 管线。
- 各 observer 从 `FieldBinding.source_entity`（资源卡 = resource entity，任务 1 已验收）取 target；颜色/枚举/列表三处闭包只捕获 `source_entity`——程序「拿不到 binding 实体」的改锚理由属实，实体判定不受 marker 漏 stamp/过期影响。
- **资源路径不读 Selection**：`rg Selection` 证实 resource_commands.rs 零 `crate::selection::Selection` 引用（resource_ops.rs 的命中全是面板自身 `ResourcePanelSelection`）；写路径 `resource_field_commit → live_resource_entity` 按 ComponentId 查 `resource_entities` 缓存，全程不触碰场景选择。

### 上轮 QA concerns ②（窄情形误写）— ✅ 已消除且守卫测试真实

- **结构性消除**：见偏差①——资源实体在 6 出口被 `is_resource_entity` 早退，不可能落入按 Selection 写的 `field_edit_commit`。
- **守卫测试非空转**：`edit_undo.rs::an_edit_never_writes_a_selected_entity_with_the_same_component`（:153-181）真实构造「`Selection.entities` 含带 `TestScore` 组件的场景实体」场景，set 42 后断言资源变 42 且**场景实体组件不在（被 bevy 资源唯一性延迟移除）或在（值仍 100）两态都不为 42**。bevy checkout 核实 `IsResource::on_insert`（resource.rs:137-182）确实会对重复实例 deferred 移除并 warn——测试注释与两态断言诚实严谨，覆盖了 bevy 清理窗口期与清理后两种现实。

### 偏差②：`ResourceSetField` 存 JSON 的 undo round-trip — ✅ 读码链路核实

- 旧值捕获三源：手势基线（`ResourceFieldEditSessions` 在**首个 preview tick** 捕获，防止拖拽已改 ECS 后 commit 读到脏现值）→ or commit 时 live 读（`reflect_to_json` canonical JSON）→ 或 operator 直调（commit 无 preview）。undo 回写经 `apply_json_map_entry_to_ecs`/`apply_json_field_to_ecs`（与既有 field_edit 管线同源实现，map-entry 与嵌套点路径复用既有已测代码）；`old = None`（字段原本不可读）时 `reset_ecs_field_to_default` 兜底。
- `serde_json::Value` 自包含深拷贝，嵌套字段路径经 `read_field_path` 支持；edit_undo/insert_remove 的值断言（42↔7、5 恢复）integration 实跑背书。

### 偏差③：插入路径结论 A（全安全 API）— ✅ bevy 源码独立证实

- `bevy_ecs/macros/src/resource.rs:18-25`（checkout c9c397b）：`derive_resource` 确实 `register_required::<IsResource>(move || IsResource::new(resource_component_id))`——required component 机制存在。
- `ReflectComponent::insert`（`reflect/component.rs:153-160`）经 `(self.0.insert)` 走 typed insert → required 拉入 `IsResource` → `on_insert` hook 维护 `ResourceEntities` 缓存。路径 B（unsafe `insert_resource_by_id`）确实无需使用 ✅。
- remove 侧缓存闭环：bevy `remove_resource_by_id`（world/mod.rs:3817-3827）只摘资源组件不清缓存——jackdaw 的「残留则摘 IsResource marker」兜底（resource_commands.rs:311-322）触发 `on_discard`（resource.rs:184-206）清缓存 + 摘残余值，**必要且正确**；`insert_round_trips_through_undo` 的 phantom 断言为证。

### 偏差④：is_available 落为「面板选中项」— ⚠️ 合理，接受

`is_available` 是无参 Bevy system（宏强制 `jackdaw_api_macros/src/lib.rs:131-137`），拿不到本次调用的 type_path 参数；「选中项是当前列表行」是「已实例化且可见」的构造性证据（行由枚举过滤生成）。副作用（未打开面板/未选中时命令面板调用被门挡）程序已披露，属可接受权衡，符合 CONTRIBUTING「state 检查进 is_available」。

### 偏差⑤⑥（测试不再手动 spawn 面板 / 触碰文件超预估）— ✅

新测试用内置窗口单实例避免双面板竞争，与任务 1 测试模式的差异在 headless 下是正确性所需；`commands.rs` 仅 2 处 `fn → pub(crate) fn` 无行为改动；颜色出口顺带合并重复 canonical JSON 构造（行为等价，diff 核实仅把构造提前复用）。

## 4. 代码质量（全量 diff 通读）

- **无 unwrap 滥用 — ✅**：`resource_commands.rs`/`resource_ops.rs`/`resource_panel.rs` 新增代码零 `unwrap()`/`expect()`/`panic!`/`#[allow]`/`#[expect]`（rg 证实）；全部 let-else/`?` 优雅降级，资源不在场时命令静默 no-op 不产生条目——与仓库 lint 口径一致。
- **undo 旧值深拷贝 — ✅**：`ResourceSetField` 走 JSON（Value 深拷贝自包含，嵌套点路径经 `read_field_path`）；`ResourceRemove`/`ResourceInsert` 走 `cloned_value`（`reflect_clone` 优先得同类型 typed clone、失败退 `to_dynamic` 经 `apply_or_insert` 重插）——比方案 §2.2 草图的序列化中转**更**保真，类型一致性由 typed clone 保证；`remove` undo 后 points=5 恢复为证。
- **redo 幂等 — ✅**：`ResourceInsert::execute` 每次重捕获 `replaced`（undo 恢复旧值后 redo 重新捕获得旧值，语义一致）；`ResourceRemove::execute` 仅 `prev.is_none()` 时捕获，redo 不覆盖。
- **`<Op>::ID` 红线 — ✅**：Add picker 接线 `commands.operator(ResourceInsertOp::ID)`（resource_panel.rs `on_resource_picker_select`）、Remove 按钮 `ButtonProps::from_operator::<ResourceRemoveOp>()`——无裸字符串 dispatch（CONTRIBUTING.md:174 红线；测试内按 id 字符串 dispatch 是测试惯例）。
- **无任务 3 越界 / 无 loop 改动 — ✅**：diff 11 文件全部为 §2.1 预估 + 程序报告披露的 2 处（commands.rs 可见性提升、mod.rs/core_extension.rs 挂载）；无 `book/`、无 `loop/plans/roadmap-gap-analysis.md`、`Cargo.lock` 未动；`git status` 干净。

### 轻微发现（⚪，不阻塞）

1. ⚪ [程序] **资源实体空壳残留**：insert→undo（或 remove→redo）后，承载资源的实体被清空（资源组件与 `IsResource` 均摘）但不 despawn；下次 insert 因缓存已清而 `spawn_empty` 新实体（resource_commands.rs:84-87）——每轮 undo/redo 循环残留 1 个空实体。编辑器会话态、量级极小（空实体每 个 ~几十字节），无功能影响；后续可在摘 marker 前记录实体并 despawn。
2. ⚪ [程序] **`ResourceFieldEditSessions` 基线残留**：preview 后永不 commit（异常手势终止）时基线留在 map，后续同字段 commit 的 undo 会回到残留基线而非提交前现值——与既有 `FieldEditSessions`（commands.rs:48-52 起）**完全相同**的残留语义，照搬既有模式，非新引入缺陷。
3. ⚪ [程序] **空 field_path 的旧值捕获跳过**：`ResourceSetField::execute` 惰性捕获仅在 `!field_path.is_empty()` 时进行（:152），显式传空 field 的边缘调用 undo 会整资源 reset 到类型默认（`reset_ecs_field_to_default("")` 复位整个组件）；正常 UI 流（控件行/operator field 参数）不可达，整资源替换语义已由 `ResourceInsert` 正确覆盖。
4. ⚪ [程序] **`param_json` 重复**：resource_ops.rs:34-46 与 ops.rs:355-368 逐字重复（~13 行）——照抄现有模式，可留待后续提取公共 helper。
5. ⚪ [程序] **Add picker 无 headless 断言**（程序报告遗留 1 自述）：picker 枚举为模块私有函数，主链路已由 `insert_round_trips_through_undo` 覆盖；建议任务 3 补公开辅助后加断言。

## 5. concerns（需主控知悉，无阻塞项）

1. 偏差④副作用：`resource.remove`/`resource.set_field` 在面板未打开/未选中时经命令面板调用会被 `is_available` 门挡——设计权衡已披露，若后续有脚本化/远程调用需求可考虑为显式传参路径放宽。
2. 程序报告遗留 1（picker 断言）与视觉项（观感、Add/Remove 按钮布局）顺延任务 3，请任务 3 跟踪闭环。
3. ⚪-1（实体空壳残留）建议记入任务 3 文档或后续优化清单，不阻塞本任务。

## 6. 证据索引

- 分支/提交：`git branch` = loop/resource-inspector；`04d941ba`（基线 main `f4a72b5d`）；`git status` 干净。
- 四门日志：`%TEMP%\zcode-bash-dQe55e\...\call_ff88375c34d945bc894b9ec6-stdout.log`（fmt/clippy/fast/integration 串行，含 `===*_EXIT=n===` 标记行）。
- bevy checkout：`%USERPROFILE%\.cargo\git\checkouts\bevy-50d7e162b728c6c6\c9c397b`（`crates/bevy_ecs/macros/src/resource.rs:18-25`、`crates/bevy_ecs/src/resource.rs:120-209`、`crates/bevy_ecs/src/world/mod.rs:3817-3827`、`crates/bevy_ecs/src/reflect/component.rs:153-160`）。
- 关键文件：`src/inspector/resource_commands.rs`（400 行新增）、`src/inspector/resource_ops.rs`（148）、`src/inspector/reflect_fields.rs`（6 出口分流 + PIE 守卫）、`src/inspector/resource_panel.rs`（picker/Remove/dirty/refresh 收敛）、`tests/resource_panel/{edit_undo,insert_remove,no_pie_leak}.rs`（+8 测试）。
