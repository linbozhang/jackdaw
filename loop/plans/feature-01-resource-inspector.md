# 功能 #1 实施方案：Resource Inspector（资源检查与编辑面板）

> 多 Agent 开发循环 · 策划产物（只写方案，不含代码实现）
> 日期：2026-10-22 · 策划：资深 Bevy 编辑器工程师 Agent
> 选题依据：`loop/plans/roadmap-gap-analysis.md`「备选 2」与「功能 #1 推荐」节。
> 主控已裁定：显示范围 = 白名单起步（项目定义类型自动进 + 精选引擎类型），白名单机制可扩展（allowlist + denylist）。
> Roadmap 验收锚点：Stage 1「资源可检查」；Stage 2「增删资源」「改组件/资源值」的资源部分。
> 调研方法：rg 文件搜索 + Read（含 bevy git main checkout `c9c397b`，与 Cargo.lock:573 锁定一致），未运行 cargo。

---

## 1. 范围与不做（含 7 个设计问题的结论）

### 1.0 功能范围总述

**做**：右侧栏新增「Resources」面板（窗口 id 已预留，见 D4），三段能力：
1. **列出**：world 中已实例化的 Resource，按可见性过滤器（白名单 + 游戏类型自动 + denylist）过滤，分组显示；
2. **显示**：选中一项，复用 `reflect_fields` 反射渲染链显示字段值（含嵌套 struct/enum/list，深度上限沿用 `MAX_REFLECT_DEPTH`）；
3. **编辑**：字段值可改（走 operator + 自建 EditorCommand 获得 undo），可增/删「可 Default 构造」的资源。

**不做**（首版明确排除）：
- 资源改动**不持久化**进 .bsn（格式不支持，见 D1；面板明示「会话态」语义）；
- PIE / 远程游戏的 Resource 编辑（不流 `pie_live` 通道；后续可挂 BRP 复用同一渲染）；
- Event 流观察、Resource 时间序列绘图；
- 逐字段的资源 schema patch（项目 schema 报告的资源类型在编辑器 world 无真实类型实例时不可编辑，见 D2 尾注）。

### D1. undo / 持久化语义（最关键）

**结论：资源编辑进 undo（自建 EditorCommand），不持久化（编辑器会话态，不落 .bsn）。operator 保持 `allows_undo` 默认 true 是安全且被文档认可的。**

证据链：
1. **.bsn 文档不覆盖 Resource**：`crates/jackdaw_bsn/src/document/mod.rs:96-108`（`SceneBsnAst` 只有 `roots`/`ecs_to_ast` 的 **entity patches** 映射）与 `:26-46`（`BsnPatch` 枚举：Name/Base/Type/Struct/TupleStruct/Template/Children——全是实体/组件概念，无资源节点）。资源改动无文档落点。
2. **自动快照对资源编辑空转、不报错**：`src/undo_snapshot.rs:177-179`，`BsnDocumentSnapshotter::history_entry` 在「文档无变化 && 编辑器状态无变化」时返回 `None`（跳过、不产生空条目）。快照源是文档 + EditMode/ActiveTool/GizmoSpace/SnapSettings（`:85-111`），不含任意 Resource。`CONTRIBUTING.md:276-278` 明文：operator 自建历史条目时仍可留 `allows_undo = true`，「自动快照会看到无变化并跳过重复条目」。因此资源 operator 依赖 `CommandHistory::push_executed`（`crates/jackdaw_commands/src/lib.rs:185`）的自建命令获得 undo，自动快照无害空转。
3. **不能蹭 `SetBsnField`**：`src/commands.rs:1482-1484`，`SetBsnField::execute` 在 `ast.ast_for(entity)` 为 `None` 时**直接 return**（静默丢弃编辑）。资源专属实体不在 `ecs_to_ast` 映射里，把资源实体当普通实体传入现有 field commit 管线（`commands.rs:183` `field_edit_commit`）会静默失败——资源必须有独立写路径。
4. **undo 混排安全**：资源命令与实体文档命令进同一条 `CommandHistory` 线性栈；实体侧 undo（`DocumentEdit`/`WholeSceneEdit::apply` → `respawn` → `reload_document_text`，`undo_snapshot.rs:280-330`）只重载场景实体，不触碰资源专属实体（bevy main 的 resource entities 独立于场景实体，见 D3）。两侧互不破坏。
5. **持久化裁定理由**：roadmap「增删资源/改资源值」的语义是编辑器运行态调试（改时间缩放、环境光、插测试资源），而非场景作者格式的一部分；扩 .bsn 格式（资源节点 + 加载器 + 迁移）是独立工程，超出本功能。roadmap 条目语义允许「不落盘」，**首版明确不做持久化**，并在面板 UI 与 book 文档写清「资源改动仅当前编辑器会话有效，不随场景保存」。

### D2. 白名单 / 枚举机制

**结论：双通道枚举（world 已实例化 + registry 可构造），过滤 = Resource 型 `ResourcePanelVisibility`（allow paths/prefixes + deny paths/prefixes，deny 最高优先）；「游戏自定义类型自动进」由 `is_game_type` 判定 + `ProjectTypes::resources()` schema 合并实现，引擎类型走编译期白名单 const。**

证据链与设计：
1. **枚举已实例化**：bevy main 提供 `World::resource_entities() -> &ResourceEntities`（`bevy_ecs/src/resource.rs:265` 与 `:93-107`，`iter()` 产出 `(ComponentId, Entity)`、`get(id)` 查询），以及 `World::iter_resources()`（`bevy_ecs/src/world/mod.rs:3666`，产出 `(ComponentId, &ComponentInfo, Ptr)`）。推荐用 `resource_entities().iter()`：直接拿到 resource entity（渲染复用需要它，见 D3），再经 `ComponentInfo::type_id()`（`src/inspector/component_picker.rs:218` 已有同款用法）到 `AppTypeRegistry` 反查 type_path。
2. **枚举可新增（未实例化）**：与 `enumerate_pickable_components`（`component_picker.rs:115-158`）同构——遍历 `registry.iter()`，过滤 `registration.data::<ReflectResource>().is_some()`（bevy main 上 `ReflectResource` 是标记类型，`bevy_ecs/src/reflect/resource.rs:30-41`，注册时附带 `ReflectComponent`）+ `crate::reflect_default::build_reflective_default` 可构造（`component_picker.rs:129` 同款）+ 排除已实例化集合。
3. **PickerDenylist 模式**（参照物）：`src/inspector/component_picker.rs:34-57`——`Resource` 持 `paths: HashSet<&'static str>` + `prefixes: Vec<&'static str>`，`deny_path`/`deny_prefix`/`contains` 三个方法；装配在 `src/inspector/mod.rs:97-99`（`insert_resource` + populate 函数）。新过滤器照此形状，双向（allow + deny）。
4. **可见性规则**（`contains` 的等价物 `visible(type_path) -> bool`）：
   - deny 命中 → 不可见（最高优先；用于压 `Assets<T>`、编辑器内部缓存等噪声，即便 allow 前缀命中也压）；
   - `is_game_type(type_path)`（`src/type_metadata.rs:75-81`：非 bevy/jackdaw 前缀且不在模块目录）→ **自动可见**——游戏经 dylib 扩展注册进编辑器 world 的真实资源类型零配置进面板；
   - 引擎白名单 const（`&'static [&'static str]`，见第 3 节清单）命中 → 可见；
   - 其余 → 不可见。
   - 扩展点：`ResourcePanelVisibility` 是 Resource，扩展/游戏可运行时 `allow_path`/`deny_prefix`（未来项目偏好文件亦可填充它）。
5. **项目 schema 资源**：`ProjectTypes` 已有 resources bucket（`src/project_types.rs:55-58` `resources()`，源头 `crates/jackdaw_schema/src/lib.rs:72-74` `ProjectSchema.resources: Vec<TypeSchema>`，schema 提取器已按 `ReflectResource` 分桶，`lib.rs:264-274`）。**注意**：schema 报告的资源类型在编辑器 world 中没有真实 ECS 类型（真实类型只在游戏二进制里，同 project component 的处境，`src/inspector/ops.rs:243-262` 注释），而 .bsn 又无资源 patch 可写（D1）——因此这些类型**只在 dylib 扩展把真实类型注册进编辑器后（已实例化或 registry 可见）才显示/可编辑**；纯 schema 字符串类型首版不展示为可实例化项。此限制写入文档。

### D3. 值渲染复用（reflect_fields 对裸 Resource 的适配）

**结论：bevy main 的「资源 = 专属实体上的组件」模型（`bevy_ecs/src/resource.rs:87` `pub trait Resource: Component`、`:120-181` `IsResource` marker + hook 维护 `ResourceEntities` 缓存）让渲染链几乎零适配：把 resource entity 当 `source_entity` 传入 `spawn_reflected_fields` 即可。唯一必须改的是编辑回写出口的分流。**

证据链与适配点：
1. **渲染入口**：`spawn_reflected_fields(commands, parent, reflected: &dyn Reflect, depth, base_path, source_entity: Entity, type_path, entity_names, type_registry, fonts...)`（`src/inspector/reflect_fields.rs:66-78`）。它对 `source_entity` 的全部用途是写进 `FieldBinding`（`src/inspector/mod.rs:377-381`）供 commit 回写与 Entity 链接显示；调用点 `src/inspector/component_display.rs:739-751`。**传 resource entity 即原样复用**（struct/enum/list/color 全部行控件、`EnumVariantHost`、`MAX_REFLECT_DEPTH` 深度限制都按原样工作）。
2. **取值**：`ReflectComponent::reflect(entity_ref)`（bevy main `bevy_ecs/src/reflect/component.rs:205-210`）对 resource entity 同样成立（资源就是组件）；或 `world.get_resource_by_id`（`world/mod.rs:3552`）。`inspected_value`（`reflect_fields.rs:2780-2793`）走 `definition_value` + `ReflectComponent::reflect` 的复合逻辑，资源面板用自己的直查版本（更薄）。
3. **回写分流（本功能对 reflect_fields.rs 的唯一侵入）**：现有 commit 观察者族（`on_text_edit_commit` `:2579`、`on_numeric_value_change_f64/i64` `:2676/:2714`、`on_checkbox_commit` `:2749`、color plane/slider `:1789/:1816`、list 按钮 `:3798`、enum 提交 `apply_enum_variant_with_undo` `:3445`）统一汇到 `apply_field_json_with_undo`（`:2158-2176`）→ `crate::commands::field_edit_commit` → `SetBsnField`——对资源实体会被 D1-3 描述静默丢弃。**方案**：FieldBinding 实体加伴生 marker `ResourceFieldTarget { type_path }`（资源面板 spawn 行时插入）；各 commit 出口在拿到 binding 后先查该 marker，命中则改走新的 `resource_field_commit(world, type_path, field_path, json)`（内含旧值捕获 + `ResourceSetField` 命令 + `push_executed`，preview/commit 两段与 `field_edit_preview/commit` 的手势语义对齐但只写 ECS 不写文档）。改动收敛为「每个 observer 出口一处早退 + 一个新函数」，不复制控件代码。
4. **刷新**：`refresh_inspector_fields`（`:2813`）绑定 selection 实体，资源面板另起轻量 refresh pass：按 `ResourceFieldTarget` 找 widget → 反射读当前值 → 更新显示；变更检测复用 `entity_components_changed`（`:2799-2809`，按 archetype 组件 tick，resource entity 同样适用——资源即组件，tick 语义一致）。
5. **PIE 旁路保证**：`try_route_pie_live_field_edit`（`:2066`）在 Live 模式路由实体编辑到运行游戏；资源实体的编辑**不得**流 PIE（首版明确编辑器会话态）。`ResourceFieldTarget` 分流天然保证这一点，但需在该函数入口加断言性早退以防未来误挂。

### D4. 面板挂载

**结论：窗口已注册且已是占位——`src/builtin_extensions.rs:447-470` 的 `jackdaw.inspector.resources`（WindowDescriptor，`DefaultArea::RightSidebar`，priority 4）当前 build 只渲染居中灰字 "Resources" 占位；替换该 build 为真面板内容即可，零新增注册点。**

- 默认位置证据：Level Design 工作区默认树 right_sidebar 标签组已含它——`src/lib.rs:3296-3305`（与 `jackdaw.inspector.components` / `.materials` / `.systems` 同区标签页，正是 Figma 风格 Inspector 同侧）；扩展装载点 `src/lib.rs:684`（`register_extension::<InspectorExtension>()`）。
- 面板内容构建模式参照 `src/layout.rs:955-985`（`inspector_components_content`：挂载 marker + observer 延迟构建）与 `src/inspector/mod.rs:100-194`（InspectorPlugin 的 observer/systems 注册）。资源面板在 `InspectorPlugin::build` 里追加自己的 observer/refresh 系统（`run_if(in_state(crate::AppState::Editor))`，同 `mod.rs:193`）。
- 面板结构（对齐 Components 面板）：顶部搜索框（过滤行）+ 分组列表（Game 组在前，`group_order` 语义同 `type_metadata.rs:85-91`）+ 选中资源的卡片区（复用 `spawn_reflected_fields`）+ 「Add Resource」按钮（弹 picker，复用 `PickerProps`，`component_picker.rs:270-281` 模式）。

### D5. operator 设计（遵循 CONTRIBUTING.md「Writing an operator」全规范）

注册方式：新 `src/inspector/resource_ops.rs` 提供 `add_to_extension(ctx)`，挂在 `src/core_extension.rs:332`（`crate::inspector::ops::add_to_extension(ctx)`）旁。描述均为一句话、面向用户、不提 undo/实现。均非 modal、均不做键绑定（面板按钮/命令面板入口即可）。

| id | label | params | is_available | 说明 |
|---|---|---|---|---|
| `resource.insert` | Add Resource | `type_path(String)`（doc: 要添加的资源类型的完整路径） | 恒 true（可改为「有项目打开」） | 添加一个该类型的资源（限可见性过滤器允许 + 可 Default 构造） |
| `resource.remove` | Remove Resource | `type_path(String)` | `has_visible_resource`（该资源已实例化且可见） | 移除该资源 |
| `resource.set_field` | Set Resource Field | `type_path(String)`、`field(String)`（点路径）、`value(String, JSON)` | 同上 | 设置资源的一个字段（对应 `field.set`（`src/inspector/ops.rs:376-408`）的资源版，参数形状一致） |

description 草案（面向用户）：`resource.insert` = "Add a resource of this type."；`resource.remove` = "Remove this resource."；`resource.set_field` = "Set one field on a resource."。`allows_undo` 全部保持默认 true（D1-2 证据：自动快照空转、自建命令成为唯一条目）。

### D6. 本地化

**结论：面板内动态文案走 `jackdaw_localization`（fluent），新增键写入 `crates/jackdaw_localization/src/locales/en-US/main.ftl`（现状仅此一方言）；窗口名 "Resources"（`WindowDescriptor::with_name`）与其它窗口保持一致的英文硬编码，不在本功能处理。**

参照：`src/workspace_dropdown.rs:22,361`（`LocalizedText::new("new-workspace")`）、`src/layout.rs:642,884`；ftl 键形如 `resources-empty = ...`、`resources-add = Add Resource`、`resources-session-only = ...`（会话态提示）。仅 en-US 一方言时不阻塞验收（roadmap Stage 6 已知项）。

### D7. 测试策略

**结论：沿用 `tests/` 的 headless 集成模式（`tests/util/mod.rs:127` `editor_test_app()`：headless_app + `JackdawEditorPlugins` + 首帧，全部内置扩展与 operator 就绪）；undo round-trip 不能用 `util::snapshot`（SceneSnapshot 只含文档+编辑器状态，资源不在覆盖内），改用「CommandHistory 栈断言 + 具体类型资源值断言」。**

- 模板证据：`tests/operators/operator_undo.rs:13-59`（`CallOperatorSettings { creates_history_entry: true }` + `CommandHistory::undo/redo`）——但其中 `assert!(!before.equals(&*after))` 一行**不适用于资源**（快照不变），资源版断言换成 `world.resource::<T>()` 的值比较。面板断言参照 `tests/inspector/`（19 个文件）+ `src/inspector/mod.rs:410-435` 的公开辅助（`component_cards_showing`/`component_card_text` 模式），为资源面板新增同款辅助（如 `resource_panel_rows(world)`、`resource_card_text(world, type_path)`）。
- 测试类型巧门：测试 crate 自定义 `#[derive(Resource, Reflect, Default)] #[reflect(Resource, Default)] struct TestScore(u32)` 的 type path 不以 bevy/jackdaw 开头 → `is_game_type` 自动可见，无需动白名单——正好覆盖「游戏自定义资源自动进面板」的需求路径。
- 测试草案（新目录 `tests/resource_panel/`，`main.rs` 挂 mod）：
  1. `visibility.rs`（单测，纯函数）：deny 压过 allow；is_game_type 自动可见；引擎白名单命中可见；bevy 其它类型不可见。
  2. `list_and_show.rs`（headless 集成）：`editor_test_app` → `insert_resource(TestScore(7))` + `AmbientLight` → update → 断言行文本含 `TestScore`/`AmbientLight`、不含 `Assets<...>` 类 deny 项；选中后卡片文本含字段名 `points`/`brightness`。
  3. `edit_undo.rs`（headless 集成）：`resource.set_field` dispatch（creates_history_entry）→ 资源值变 + undo 栈 +1 → `history.undo` 值还原 → `redo` 值再变；同时断言文档快照不产生空条目（栈恰 +1）。
  4. `insert_remove.rs`（headless 集成）：`resource.insert(TestScore)` → `resource_entities` 出现该 ComponentId 且面板行出现 → `resource.remove` → 消失 → undo 恢复 → redo 移除。
  5. `no_pie_leak.rs`：Live 模式投影存在时，资源字段编辑不产生 PIE 控制事件（`ResourceFieldTarget` 分流的回归守卫）。

---

## 2. 技术方案

### 2.1 模块 / 文件布局

```
src/inspector/
  resource_panel.rs        （新）面板：列表 + 选中卡 + 刷新 pass + ResourcePanelVisibility 过滤器
  resource_ops.rs          （新）3 个 operator + add_to_extension
  resource_commands.rs     （新）ResourceSetField / ResourceInsert / ResourceRemove 三个 EditorCommand
  reflect_fields.rs        （改）commit 出口分流（ResourceFieldTarget 早退，~8-10 处 + try_route_pie_live_field_edit 守卫）
  mod.rs                   （改）挂模块、注册 observer/systems、新增 resource_panel_rows 等测试辅助
src/builtin_extensions.rs  （改）:447-470 占位 build → resource_panel 面板内容
src/core_extension.rs      （改）:332 旁挂 resource_ops::add_to_extension
crates/jackdaw_localization/src/locales/en-US/main.ftl （改）新键
tests/resource_panel/      （新）main.rs + 5 个测试文件
book/src/user-guide/       （改/新）Resources 面板一节
book/src/developer-guide/custom-components.md （改）补「自定义 Resource」段
loop/plans/roadmap-gap-analysis.md （改）三行状态更新
```

### 2.2 关键接口草图（示意，非最终签名）

```rust
// resource_panel.rs（示意）
#[derive(Resource, Default)]
pub struct ResourcePanelVisibility {
    allow_paths: HashSet<&'static str>,
    allow_prefixes: Vec<&'static str>,
    deny_paths: HashSet<&'static str>,
    deny_prefixes: Vec<&'static str>,
}
impl ResourcePanelVisibility {
    pub fn allow_path(&mut self, p: &'static str) -> &mut Self;
    pub fn allow_prefix(&mut self, p: &'static str) -> &mut Self;
    pub fn deny_path(&mut self, p: &'static str) -> &mut Self;
    pub fn deny_prefix(&mut self, p: &'static str) -> &mut Self;
    pub fn visible(&self, type_path: &str) -> bool {          // deny > is_game_type > 白名单
        !self.denied(type_path)
            && (is_game_type(type_path)
                || self.allowed(type_path)
                || ENGINE_RESOURCE_ALLOWLIST.contains(&type_path))
    }
}
pub const ENGINE_RESOURCE_ALLOWLIST: &[&str] = &[ /* 第 3 节 */ ];

/// 面板行数据（纯函数，可单测）
pub fn enumerate_visible_resources(world: &World, registry: &TypeRegistry,
                                   vis: &ResourcePanelVisibility) -> Vec<ResourceRow>;

/// 与 FieldBinding 同实体插入的伴生 marker（reflect_fields 分流用）
#[derive(Component)]
pub struct ResourceFieldTarget { pub type_path: String }

// resource_commands.rs（示意）
pub struct ResourceSetField { pub type_path: String, pub field_path: String,
                              pub old: Option<BsnValue>, pub new: BsnValue }
impl EditorCommand for ResourceSetField { /* apply/json -> resource entity 组件；undo 回写 old */ }

pub struct ResourceInsert { pub type_path: String }   // build_reflective_default -> spawn + IsResource::new(id)
pub struct ResourceRemove { pub type_path: String, pub prev: Box<dyn Reflect> } // remove_resource_by_id；undo 重插
```

插入路径说明：bevy main 无安全的运行时泛型免型 `insert_resource` 反射包装；两条实现路线按序验证——
A（首选，全安全 API）：`reflect_component.register_component(world)` 拿 ComponentId（`bevy_ecs/src/reflect/component.rs:264`）→ `spawn_empty` + `reflect_component.insert(...)` + `IsResource::new(id)`（`bevy_ecs/src/resource.rs:126-181`，on_insert hook 自动登记 `ResourceEntities` 缓存——这是 bevy 官方暴露 `IsResource::new` 的用途）；
B（退路）：`pub unsafe fn World::insert_resource_by_id`（`world/mod.rs:3078`）。
移除直接用安全 API `World::remove_resource_by_id`（`world/mod.rs:3817`）。undo 的 `prev` 值经 `TypedReflectSerializer`/`BsnValue` 中转（`reflect_fields.rs:3930 reflect_to_json` 与 `src/inspector/ops.rs:118-128 default_component_json` 已有同类序列化用法）。

### 2.3 数据流

```
面板列表  ←enumerate_visible_resources← world.resource_entities() + AppTypeRegistry + Visibility
选中行    → spawn 资源卡（ResourceFieldTarget + FieldBinding{source_entity = resource entity}）
          → spawn_reflected_fields（原样复用）
控件 commit → reflect_fields observer（查 ResourceFieldTarget 早退）
           → resource_field_commit → ResourceSetField::execute（只写 ECS resource entity）
           → CommandHistory::push_executed（undo/redo 即得；自动文档快照空转跳过）
增/删按钮 → PickerProps / 直接 → resource.insert / resource.remove operator
          → ResourceInsert / ResourceRemove 命令（同上入栈）
场景实体的 undo（respawn/文档重载）不触碰资源；资源的 undo 只触碰资源。两条互不干扰（D1-4）。
```

---

## 3. 白名单初版清单建议

> 原则：只列**已验证存在**或**已标注核对方法**的类型，绝不猜。已验证 = 在 bevy git main checkout `c9c397b` 中确认 derive/注册；核对法 = `rg "pub struct <T>" bevy checkout` + 查 `#[derive(Resource, ...Reflect)]` 与 `register_type`。

**第一档：已验证可直接进白名单（bevy 引擎）**

| type path | 来源 crate | 关卡编辑意义 | 证据 |
|---|---|---|---|
| `bevy_light::ambient_light::AmbientLight` | bevy_light | 全局环境光颜色/亮度，场景氛围首要旋钮 | `bevy_light/src/ambient_light.rs:60-61`（`Resource, Clone, Debug, Reflect` + `reflect(Resource, Debug, Default, Clone)`） |
| `bevy_camera::clear_color::ClearColor` | bevy_camera | 视口清屏底色（天空替代） | `bevy_camera/src/clear_color.rs:54-56` |
| `bevy_gizmos::config::GizmoConfigStore` | bevy_gizmos | 调试 gizmo 开关/样式 | `bevy_gizmos/src/config.rs:97-99` |
| `bevy_time::Time<bevy_time::virt::Virtual>` | bevy_time | 时间缩放（慢动作调试） | `bevy_time/src/lib.rs:72,80`（init_resource + register_type；泛型 path 实现期以 registry 实际输出为准） |
| `bevy_time::Time<bevy_time::fixed::Fixed>` | bevy_time | 固定步长（物理节奏） | `bevy_time/src/lib.rs:73,81` |

**第二档：实现期核对后加入（存在性已见、Reflect 注册待核）**

| type path | 来源 | 意义 | 备注 |
|---|---|---|---|
| `bevy_time::Time`（默认时钟）与 `Time<bevy_time::Real>` | bevy_time | 只读参考 | `lib.rs:70,78`；与 Virtual/Fixed 二选一即可，倾向只收 Virtual/Fixed |
| `avian3d::math::Gravity` | avian3d（游戏侧 physics module） | 重力向量，3D 关卡调试刚需 | avian 不在本仓依赖内（`jackdaw_project_build/src/modules.rs:520` 引用 avian3d）；仅在游戏装 physics 模块且类型注册进编辑器时出现，白名单收 type path 字符串，枚举不到自动无效果（容错） |

**第三档：游戏/扩展自定义资源（自动，无需枚举）**

- 一切 `is_game_type`（非 bevy/jackdaw 前缀、非模块目录，`src/type_metadata.rs:75-81`）的已实例化资源自动可见；项目 schema 的 resources bucket（`src/project_types.rs:56`）作为描述/分组信息合入（D2-5 的限制条款）。

**建议的默认 deny（压噪声，首批即配）**：前缀 `bevy_asset::assets`（`Assets<T>` 存储）、`bevy_ecs::`（Schedules 等调度内部）、`bevy_render::`（除白名单精确命中外的渲染内部）、`bevy_window::`、jackdaw 前缀整体（编辑器自身状态，除非个别 allow 精确命中）。deny 优先于 allow 的规则保证「白名单精确定义 + 大前缀压噪」组合可用。

**后续建议（不在本轮）**：为 jackdaw 自身对关卡编辑有意义的资源补 `Reflect` derive 后纳入——`src/snapping.rs:76 SnapSettings`、`src/gizmos.rs:88 GizmoSpace`（当前均无 Reflect，列了也显示不了）。

---

## 4. 任务拆分（3 个任务）

### 任务 1（程序）：面板骨架与枚举（只读）

- **内容**：`resource_panel.rs`：`ResourcePanelVisibility`（含 `ENGINE_RESOURCE_ALLOWLIST` const 与默认 deny 填充）、`enumerate_visible_resources` 纯函数、面板 UI（搜索 + 分组列表 + 选中卡）、`ResourceFieldTarget` + 卡片渲染复用 `spawn_reflected_fields`（传 resource entity）、只读刷新 pass、替换 `builtin_extensions.rs:447-470` 占位 build；ftl 空态键；`mod.rs` 挂载与测试辅助（`resource_panel_rows`/`resource_card_text`）。
- **验收清单**（逐条可判定）：
  1. visibility 纯函数单测全绿（deny>allow>game 类型>默认不可见，四类 case）；
  2. headless：插入 `TestScore(7)` 与 `AmbientLight` 后一帧内，面板行含两者短名；插入 deny 前缀资源（如 `bevy_time::Time<Real>` 若未 allow）不出现；
  3. 选中行后卡片文本含字段名（如 `brightness`）；无选中时空态文案（ftl 键存在且渲染）；
  4. `cargo xtask fast` + `cargo xtask integration` 通过；
  5. Level Design 工作区默认布局中该 tab 打开即见面板（无空白占位残留）。
- **跑的门**：fmt / clippy -D warnings / lib tests（fast 档）+ 新增 integration。
- **预估触碰**：`src/inspector/resource_panel.rs`（新）、`src/inspector/mod.rs`、`src/builtin_extensions.rs`、`crates/jackdaw_localization/src/locales/en-US/main.ftl`、`tests/resource_panel/{main,visibility,list_and_show}.rs`。

### 任务 2（程序）：编辑链路与增删

- **内容**：`resource_commands.rs` 三命令（插入路径 A/B 按序验证）；`resource_ops.rs` 三 operator + 注册；`reflect_fields.rs` commit 出口分流（ResourceFieldTarget 早退 + `resource_field_commit` + PIE 守卫）；面板 Add/Remove 按钮与 picker；编辑控件全型可用（文本/数值拖拽/复选/颜色/枚举/列表）。
- **验收清单**：
  1. `resource.set_field` dispatch 后资源值改变、undo 栈恰 +1、undo 还原、redo 复现（`edit_undo.rs`）；
  2. 同一编辑后文档快照无空条目（栈长断言，防快照回归）；
  3. `resource.insert` 后 `world.resource_entities()` 含该 ComponentId 且面板行出现；`resource.remove` 后消失；两者均可 undo/redo（`insert_remove.rs`）；
  4. Live/PIE 投影在场时资源编辑不产生 PIE 控制事件（`no_pie_leak.rs`）；
  5. 既有 inspector 测试套（`tests/inspector/` 19 文件、`tests/operators/`）全绿（分流无回归）；
  6. `cargo xtask fast` + `integration` 通过。
- **预估触碰**：`src/inspector/{resource_commands,resource_ops}.rs`（新）、`src/inspector/reflect_fields.rs`（~10 处出口早退）、`src/core_extension.rs`、`src/inspector/resource_panel.rs`（按钮）、`tests/resource_panel/{edit_undo,insert_remove,no_pie_leak}.rs`。

### 任务 3（QA + 文档）

- **内容**：全量门跑（fast + integration + docs + doctests，CONTRIBUTING CI 集）；book 用户指南新增「Resources 面板」节（含「会话态、不落盘」语义与白名单说明）；`custom-components.md` 补「自定义 Resource」段（`#[derive(Resource, Reflect, Default)] #[reflect(Resource, Default)]` 即自动进面板）；`roadmap-gap-analysis.md` 三行状态更新（Stage 1 资源可检查 ✅、Stage 2 增删资源 ✅、改资源值 ✅）。
- **验收清单**：
  1. CI 集四命令全绿；
  2. book 构建含新节且 SUMMARY 链接有效；
  3. 盘点表三行改 ✅ 且证据列指向本功能提交；
  4. 手册文案与实际 UI 文案一致（ftl 键对齐）。
- **预估触碰**：`book/src/user-guide/*.md`、`book/src/SUMMARY.md`、`book/src/developer-guide/custom-components.md`、`loop/plans/roadmap-gap-analysis.md`。

---

## 5. 给 QA 的验收清单

**确定性门（全部必须绿）**
- [ ] `cargo fmt --all -- --check`
- [ ] `cargo clippy --workspace -- -D warnings`（CI 档含 `--all-targets --features dylib`）
- [ ] `cargo xtask fast`
- [ ] `cargo xtask integration`（含 `tests/resource_panel/` 5 文件）
- [ ] `cargo doc --locked --workspace --document-private-items --no-deps`
- [ ] `cargo test --locked --workspace --doc --features bevy/dynamic_linking`

**headless 行为断言（自动测试覆盖）**
- [ ] 白名单/游戏类型/deny 过滤四类 case（visibility）
- [ ] 列出→显示（行与字段名）（list_and_show）
- [ ] 改值→undo→redo round-trip + 无空文档条目（edit_undo）
- [ ] 增→删→undo→redo round-trip（insert_remove）
- [ ] PIE 不泄漏（no_pie_leak）

**视觉项（人工，少量）**
- [ ] Level Design 工作区右栏 Resources tab：列表分组（Game 在前）、搜索过滤、卡片展开/折叠与 Components 面板观感一致；
- [ ] 数值拖拽（scrub）、颜色选择器、枚举下拉在资源卡上可用且一次拖拽一条 undo；
- [ ] 「会话态」提示文案可见（不随保存持久化的预期管理）。

**文档项**
- [ ] book 用户指南「Resources」节存在并解释范围与不落盘语义；
- [ ] custom-components.md 有 Resource 段（derive 即用）；
- [ ] roadmap-gap-analysis.md 三行 ✅。

---

## 6. 风险与对策

1. **reflect_fields.rs 观察者分流改动面（~10 处出口）**：大文件（~4000 行）多出口，漏改一处即某控件类型静默不生效。对策：分流逻辑收敛为单一 helper（`binding_is_resource_target` + `resource_field_commit`），每处只加两三行早退；任务 2 验收含全控件型手测 + 既有 inspector 测试套回归。
2. **资源插入的安全路径不确定（IsResource spawn vs unsafe insert_resource_by_id）**：bevy main 较新，`IsResource::new` 的公开 spawn 用法与官方 `insert_resource_by_id` 行为等价性需实测。对策：任务 2 内置 A/B 两条路线按序验证，B 为 pub API 退路；`insert_remove.rs` 直接断言 `resource_entities` 缓存闭环。
3. **泛型资源 type path 匹配**（`Time<Virtual>` 等的 path 书写与 registry 输出一致性）：白名单是字符串匹配，写错即静默不显示。对策：实现期先打日志核对 registry 实际 path 再定稿 const；白名单 miss 无崩溃风险（枚举不到即不显示），测试锁定 2-3 个代表类型。
4. **不含 ReflectComponent data 的资源类型**（只 register_type 未注册组件数据）：渲染走 opaque fallback（`spawn_reflected_fields` 已有 `:274-283`）。对策：列表照常显示（可检查），编辑控件降级为只读文本；必要时借 `unavailable.rs` 的 notice 模式。
5. **资源 undo 与场景 respawn 的交互误解**：用户可能预期 undo 资源编辑也重载场景。对策：文档写明两套状态域；资源命令只动资源，不触发文档 reload（无 `reload_document_text` 调用），风险低。
6. **噪声资源漏网**（新 bevy 版本引入未 deny 的内部资源）：对策：默认 deny 采用大前缀 + 白名单精确 allow 的组合（第 3 节），新类型默认不可见，噪声面收敛为零。

---

## 7. ⚠️ 需用户裁决项

1. **「会话态」提示的呈现强度**：资源改动不落盘是既定语义（D1），但 UI 上是（a）面板顶部一行常驻说明文案（推荐，低成本），还是（b）编辑时 toast/状态栏提醒，还是（c）不做任何提示仅靠文档？影响任务 1/3 的文案工作量，不影响架构。
2. **jackdaw 自身编辑器资源是否本轮补 Reflect 纳入**（`SnapSettings`/`GizmoSpace` 等，第三档）：推荐**不本轮做**（纯增益项，避免范围膨胀）， backlog 留待下轮；若用户希望顺手做，任务 2 增加约半天工作量与两条白名单条目。

---
*证据快照：仓库 main（2026-10-22，49 crate workspace，bevy git main `c9c397b` 与 Cargo.lock 一致）。所有路径结论可按文中 file:line 复核；标注「实现期核对」处（泛型 path、avian Gravity、插入路径 A/B）已给出核对方法与退路。*
