# 功能 #1 任务 1 QA 验收报告：Resources 面板骨架（只读）

- QA：独立验收 Agent，2026-10-22
- 对象：`loop/resource-inspector` 分支提交 `c461ba37`（9 files，+1145/-21）
- 需求口径：`loop/plans/feature-01-resource-inspector.md` §4 任务 1 + §2.1 + D2/D3/D4/D6
- 方法：四门自己重跑记退出码；全量 diff 逐行读；关键偏差到 bevy checkout（`c9c397b`，与 Cargo.lock 一致）独立核实；不信任程序自述。

## 结论

**VERDICT: PASS** — 四门全 0，规格 1-4 全部符合（含偏差抽验），无 🔴/🟡；验收第 5 条（视觉）按主控裁定 ⚠️ 顺延。

## 1. 门（QA 重跑，退出码）

| 门 | 命令 | 退出码 | 关键输出 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | 0 | 无 diff |
| Lint | `cargo clippy --workspace -- -D warnings` | 0 | 通过（日志仅既有 linker_messages 噪声，来自 build script，非本任务代码） |
| 快档 | `cargo xtask fast` | 0 | `2716 tests run: 2716 passed, 2 skipped` |
| 集成 | `cargo xtask integration` | 0 | `4822 tests run: 4822 passed, 3 skipped`；`jackdaw::resource_panel` 8 个测试全部 PASS（日志行 1369-1404） |

## 2. 规格符合性（逐条）

### 任务 1 验收清单

1. **visibility 纯函数单测四类 case — ✅**
   `tests/resource_panel/visibility.rs`：
   - game 类型零配置可见（:19-23 `a_game_type_is_visible_without_any_configuration`）；
   - allow 可见（:26-33，path + prefix 两种）；
   - deny 压过 allow 与 game（:36-50 `a_deny_suppresses_even_an_allow_and_a_game_type`，deny_path 压 allow_path、deny_prefix 压 game 规则，且不误伤同前缀其余类型）；
   - 默认不可见 + 白名单命中可见（:53-76，8 个应隐藏路径含 `Time<Real>`/`Assets<...>`/`jackdaw::`/`bevy_ecs::`/`bevy_render::`/`bevy_window::`）。
   四类 case 齐全，integration 门全 PASS。

2. **list_and_show 行文本/deny 不出现 — ✅**
   `tests/resource_panel/list_and_show.rs`：
   - 行含 `TestScore` 与 `AmbientLight` 短名（:44-51，GlobalAmbientLight 含子串）；
   - 不含 `Assets`/`Real`（:52-59）——**非空转断言**：`util::editor_test_app` 走 DefaultPlugins（`tests/util/mod.rs:80-83`），TimePlugin 必然 init `Time<Real>`/`Time<Virtual>`，编辑器也必然持有大量 `Assets<T>`，deny 项真实存在于 world 中被压掉；
   - 白名单泛型拼写锁定（:64-74）：断言 registry 实际输出的 `bevy_time::time::Time<bevy_time::virt::Virtual>` 出现在按钮 type_path 中。
   另 `visibility.rs:79-122` 裸 World 显式插入 `Time<Real>` 断言被枚举排除、Game 组排前、每行 entity 存活。

3. **选中卡字段名 + 空态 ftl — ✅**
   - 选中后卡片文本含字段名 `points` 与类型名（list_and_show.rs:78-96）；方案锚点 `brightness` 随 AmbientLight→GlobalAmbientLight 替换改用 TestScore 的 `points`，"含字段名"语义满足。
   - 无选中空态渲染为解析后的英文 `"Select a resource to inspect its fields."` 而非键名（:99-113）。
   - ftl 新键 `resources-empty`、`resources-none-selected`（main.ftl diff +2 行），kebab-case 与现有键一致；卡片无 ReflectComponent 数据时复用既有 `read-only` 键（resource_panel.rs:558）。

4. **占位 build 真替换 — ✅**
   `src/builtin_extensions.rs` diff：原 :450-466 居中灰字 "Resources" 占位 spawn 整段删除，替换为 `window.spawn(crate::inspector::resource_panel::resource_panel_content())`；WindowDescriptor（id/priority/area）未动。

5. **视觉（Level Design 工作区打开即见面板）— ⚠️ 顺延**
   按主控裁定顺延至任务 3/用户终审，不计 FAIL。headless 断言已覆盖面板结构渲染：搜索框 + 滚动 body + 分组列表（行按钮、Game 组头）+ 选中卡（spawn_reflected_fields 全部文本行）+ 两种空态 hint，均经 `resource_panel_content()` spawn + refresh pass 后逐实体断言。

### 无任务 2 越界 — ✅

- diff 仅 9 文件：无 `resource_ops.rs`/`resource_commands.rs`/`ResourceSetField`/`ResourceInsert`/`ResourceRemove`（rg 全仓零命中）；无 `core_extension.rs` 改动、无新 operator、无 Add/Remove 按钮。
- `reflect_fields.rs` diff 仅 4 处 `fn` → `pub(crate) fn`（`round_numeric_display`/`scrub_value_as_f64`/`reflect_field_to_f64`/`ShownFieldText` 字段同提 pub(crate)），零 commit 出口改动。
- `ResourceFieldTarget` 仅作 marker：定义（resource_panel.rs:267-270）+ 卡片 spawn 后 stamp（:579-597）+ 刷新 pass 查询过滤（:610/:622/:634）；`reflect_fields.rs` 全文无引用，无消费方。
- `type_metadata.rs` 仅 `is_game_type` 提 `pub(crate)` + doc，无行为改动。

### 程序报告 4 处偏差抽验（实抽 2+2 项，全部属实）

1. **AmbientLight → GlobalAmbientLight — ✅ 属实**
   bevy checkout `c9c397b` `crates/bevy_light/src/ambient_light.rs`：
   - :9-12 `AmbientLight` 为 `#[derive(Component, Clone, Debug, Reflect)] #[reflect(Component, Debug, Default, Clone)] #[require(Camera)]` —— 相机组件，非 Resource；
   - :60-62 `GlobalAmbientLight` 为 `#[derive(Resource, Clone, Debug, Reflect)] #[reflect(Resource, Debug, Default, Clone)]`，`brightness` 字段仍在（:71）。
   白名单与测试换用正确；方案 §3 的 `AmbientLight` 条目基于过期调研（方案自注"实现期核对"），现场替换合理。
2. **Time 泛型 path 拼写 — ✅ 属实且被真实锁定**
   `crates/bevy_time/src/time.rs:192-194`：`pub struct Time<T: Default = ()>` 定义于 `time` 模块 → TypePath 含模块段 `bevy_time::time::Time<...>`。测试从两个方向锁定 registry 实际输出（visibility.rs:96-99 枚举断言、list_and_show.rs:69-74 面板按钮断言），非字符串常量自证；integration 门通过证明断言真实成立。
3. **GizmoConfigStore 引用路径 — ✅**：注册用 `bevy::gizmos::config::GizmoConfigStore`（resource_panel.rs:783），白名单写 type path `bevy_gizmos::config::GizmoConfigStore`（:53）——TypePath 走 crate 名，二者不矛盾。
4. **白名单补注册 — ✅**：`plugin()` 注册 GlobalAmbientLight/ClearColor/GizmoConfigStore（:781-783）；ClearColor 已在 checkout 核实 `bevy_camera/src/clear_color.rs:54-56` 为 `Resource+Reflect`，白名单拼写 `bevy_camera::clear_color::ClearColor` 正确。

## 3. 代码质量（全量 diff 通读）

- **visible() 优先级 — ✅**：`!denied && (is_game_type || allowed || ENGINE_RESOURCE_ALLOWLIST)`（resource_panel.rs:131-136），deny 先判短路，严格 deny > game > allow > 白名单；与方案 D2-4 一致。默认 deny 的 "jackdaw" 前缀压死自身 allow 是注释言明的有意行为（:72-74）。
- **UI 照抄现有模式 — ✅**：`spawn_panel_card`（可折叠 + `remembered_as("resource:<type_path>")`）、`button`/`text_edit`/`Tooltip`/tokens 全部复用 feathers；"Filter..." placeholder 与 `src/layout.rs:597/1016` 现有面板一字不差；刷新 pass 的 exclusive-world + query_filtered + lookup 收集 + tick 早退结构与 `refresh_inspector_fields`（reflect_fields.rs:2813-2853）同款。
- **无 lint 豁免 — ✅**：新代码（resource_panel.rs + tests/resource_panel/）零 `#[allow]`/`#[expect]`（rg 唯一命中是测试的正常 `.expect()` 调用）。
- **测试未放松 — ✅**：deny 断言针对真实存在于 world 的资源（见规格第 2 条）；默认 deny 用 8 个路径双向断言（可见/不可见各一组）。
- **测试基建模式一致 — ✅**：手动 spawn `resource_panel_content()` 与 `tests/inspector/*` 手动 spawn `inspector_components_content` 的既有模式一致（rg 8 处既有先例）。

### 轻微发现（⚪，不阻塞）

1. ⚪ [程序] `refresh_resource_panel`（resource_panel.rs:339-443）每帧全量 `enumerate_visible_resources` + 行 type_path 三处 String clone + shown/wanted 双 Vec 排序比较——列表部分无 tick 早退（资源增删无组件 tick 可用，全量比较是正确性所需），行数规模（通常 <50）下可接受；未来行数增长可考虑缓存。与程序报告遗留 3 自述一致。
2. ⚪ [程序] `resource_card_text`（mod.rs:429-447）与 `component_card_text` 实现近乎重复（~20 行），可提取公共子树文本 helper；照抄现有测试辅助模式是任务口径，可留待后续统一。
3. ⚪ [程序] 白名单 6 条中仅 `Time<Virtual>`、`GlobalAmbientLight` 被测试间接锁定 registry 实际输出（前者双向字符串断言，后者经列表行断言）；`ClearColor`/`GizmoConfigStore` 拼写未被测试锁定（QA 已在 bevy checkout 人工核实无误；且 miss 仅静默不显示，无崩溃风险——方案风险 3 已评估）。
4. ⚪ [程序] 列表空态 `resources-empty` 键已存在且有渲染路径（rebuild_resource_list :456-465），但无 headless 断言其渲染文本（验收第 3 条只要求"无选中"空态，已覆盖；过滤空态留任务 3 补断言即可）。

## 4. concerns（需主控知悉，无阻塞项）

1. 视觉验收（验收第 5 条）顺延任务 3 + 用户终审；headless 已覆盖结构渲染，缺的是观感/交互确认。
2. 程序报告遗留 1 的边界在任务 1~2 之间真实存在：资源卡上的输入控件提交仍走 `SetBsnField` 管线被静默丢弃；极窄情形（当前选中场景实体恰有与资源同 type_path 的组件）输入可能误写到该实体。任务 2 分流落地前，属已知且已披露的风险，无需任务 1 返工。

## 5. 证据索引

- 分支/提交：`git branch` = loop/resource-inspector；`c461ba37`。
- 四门日志：本机 temp 会话日志（fmt/clippy 前台输出，fast/integration 后台任务 stdout）。
- bevy checkout：`%USERPROFILE%\.cargo\git\checkouts\bevy-50d7e162b728c6c6\c9c397b`。
- 关键文件：`src/inspector/resource_panel.rs`（840 行新增）、`src/inspector/mod.rs:417-461`（测试辅助）、`src/builtin_extensions.rs:450-456`（替换处）、`tests/resource_panel/{main,visibility,list_and_show}.rs`。
