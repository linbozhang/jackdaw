# 功能 #1 任务 1 报告：Resources 面板骨架与枚举（只读）

- 分支：`loop/resource-inspector`，提交 `c461ba37`（`Add Resources panel skeleton with resource enumeration`，9 files，+1145/-21）
- 执行者：程序 Agent（Rust/Bevy 工程师），2026-10-22
- 需求来源：`loop/plans/feature-01-resource-inspector.md` §4 任务 1

## 1. 实现内容

### 新增 `src/inspector/resource_panel.rs`（约 900 行）

- **`ResourcePanelVisibility`**（Resource）：allow paths/prefixes + deny paths/prefixes 四组过滤器，
  `visible()` 语义 = `!denied && (is_game_type || allowed || ENGINE_RESOURCE_ALLOWLIST)`（deny 最高优先），
  builder 方法 `allow_path/allow_prefix/deny_path/deny_prefix` 与 `PickerDenylist` 同形（方案 D2-3）。
- **`ENGINE_RESOURCE_ALLOWLIST`** const 与默认 deny 前缀（`bevy_asset::assets`、`bevy_ecs::`、`bevy_render::`、
  `bevy_window::`、`jackdaw`），由 `default_resource_panel_visibility()` 装配（方案 §3）。
- **`enumerate_visible_resources(world, registry, visibility) -> Vec<ResourceRow>`** 纯函数：遍历
  `world.resource_entities().iter()`（bevy main `bevy_ecs/src/resource.rs:99`），经 `ComponentInfo::type_id()`
  反查 registry 取 type_path，排序 = `group_order` 降序（Game 在前）→ 组名 → 短名小写。
- **面板 UI** `resource_panel_content()`：搜索框（`ResourcePanelSearch` + text_edit，"Filter..." 占位）+
  滚动 body（`Overflow::scroll_y`）内含列表 mount 与卡片 slot。列表 = 分组头（空组名渲染 "Game"）+
  每资源一个 `button`（`ResourceRowButton{type_path, short_name}` + 全路径 Tooltip）；空态
  `LocalizedText("resources-empty")`。选中卡 = feathers `spawn_panel_card`（可折叠、折叠状态记忆
  `remembered_as("resource:<type_path>")`），body 复用 `spawn_reflected_fields`，`source_entity` = resource entity。
  无选中时 `LocalizedText("resources-none-selected")` 空态提示。
- **`ResourceFieldTarget { type_path }`** marker：卡片 spawn 后遍历卡片子树，给每个 `FieldBinding` 实体
  插入（任务 2 commit 分流的伴生标记，本任务只埋点不消费）。
- **只读刷新 pass** `refresh_resource_panel`（exclusive world，`run_if(in_state(AppState::Editor))`）：
  列表在可见集合或过滤词变化时整体重建（搜索框在 mount 外，输入焦点不受影响）；卡片在选择变化或
  resource entity 失效时重建；资源组件 tick 变化（复用 `entity_components_changed`）时做数值/复选/文本
  三类 widget 值同步（跳过正在 scrub/输入的控件，语义同 `refresh_inspector_fields`）。
- **`plugin(app)`** 注册：`register_type` 三个引擎资源 + visibility/selection 资源 + 行点击 observer +
  刷新 system，挂在 `InspectorPlugin::build`（方案 D4）。

### 改动

- `src/inspector/mod.rs`：挂 `pub mod resource_panel` + `plugin(app)`；新增公开测试辅助
  `resource_panel_rows(world) -> Vec<String>`（列表行短名，按显示序）与
  `resource_card_text(world, type_path) -> Vec<String>`（卡片子树全部文本行），与
  `component_cards_showing`/`component_card_text` 同模式。
- `src/builtin_extensions.rs`：`jackdaw.inspector.resources` 窗口占位 build（原 :447-470 居中灰字）
  替换为 `window.spawn(resource_panel_content())`。
- `crates/jackdaw_localization/src/locales/en-US/main.ftl`：新增 `resources-empty`、`resources-none-selected` 两键。
- `src/type_metadata.rs`：`is_game_type` 提升为 `pub(crate)`（原私有；方案 D2-4 依赖它）。
- `src/inspector/reflect_fields.rs`：**仅可见性提升 4 处**（`round_numeric_display`/`scrub_value_as_f64`/
  `reflect_field_to_f64`/`ShownFieldText` → `pub(crate)`），供刷新 pass 复用；无任何 commit 出口改动。

### 测试 `tests/resource_panel/`（main.rs + 2 文件，8 个测试）

- `visibility.rs`（5）：游戏类型零配置可见；allow 可见；deny 压过 allow 与游戏类型（四类 case）；
  默认可见性收引擎白名单/压其余；裸 World 枚举（TestScore + Time<Virtual>/Time<Real>）只列可见项、
  Game 组排前、每行 entity 存活、**白名单泛型拼写与 registry 实际输出一致**（防字符串漂移回归锁）。
- `list_and_show.rs`（3，headless `editor_test_app` + 手动进 `AppState::Editor`）：
  行含 `TestScore` 与 `GlobalAmbientLight` 短名、不含 `Assets`/`Real`；选中后卡片文本含字段名 `points`
  与类型名；无选中时空态文案渲染为解析后的英文（非键名）。

## 2. 与方案偏差（现场调整，均有证据）

1. **`AmbientLight` 已不是 Resource**：bevy main `bevy_light/src/ambient_light.rs:9-12` 为
   `#[derive(Component...)] #[require(Camera)]`（相机组件）；全局环境光是 **`GlobalAmbientLight`**
   （同文件 :60-62 `#[derive(Resource, Clone, Debug, Reflect)] #[reflect(Resource,...)]`，`LightPlugin`
   `lib.rs:167` init）。白名单与测试相应换用 `bevy_light::ambient_light::GlobalAmbientLight`
   （`brightness` 字段仍在，验收锚点不变）。
2. **`Time` 泛型 type path 拼写**：方案写 `bevy_time::Time<bevy_time::virt::Virtual>`；registry 实际输出
   **`bevy_time::time::Time<bevy_time::virt::Virtual>`**（运行时打印验证，结构体定义于 `bevy_time/src/time.rs`，
   TypePath 含定义模块段）。白名单按实测定稿，测试锁定（方案风险 3 的对策生效）。
3. **`GizmoConfigStore` 引用路径**需 `bevy::gizmos::config::GizmoConfigStore`（crate 根 re-export 私有）。
4. **白名单类型的 reflect 注册**：`GlobalAmbientLight`/`ClearColor`/`GizmoConfigStore` 无任何现成
   `register_type`（全仓检索无果），`plugin()` 里补注册（`#[reflect(Resource)]` 数据随 derive 自带）；
   `Time<Virtual>`/`Time<Fixed>` 已由 `TimePlugin` 注册，无需补。
5. **触碰文件超出方案预估**：`reflect_fields.rs`（4 处仅可见性）与 `type_metadata.rs`（1 处）——
   方案文件清单未列，但均为复用辅助的最小可见性调整，未触碰任务 2 的 commit 分流。
6. **卡片**用 feathers `spawn_panel_card`（现成可折叠卡，样式与 inspector 卡一致）而非手搓 pane——仓库复用优先。

## 3. 各门退出码与关键输出

| 门 | 命令 | 退出码 | 关键输出 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | 0 | 无 diff |
| Lint | `cargo clippy --workspace -- -D warnings` | 0 | 通过 |
| 快档 | `cargo xtask fast` | 0 | 含 fmt check + clippy `--all-targets --features dylib -D warnings` + nextest lib（dylib）：`2716 tests run: 2716 passed, 2 skipped` |
| 集成 | `cargo xtask integration` | 0 | nextest `--tests --features dylib`：`4822 tests run: 4822 passed, 3 skipped`，含全部 8 个 `jackdaw::resource_panel` 测试（日志行 1384-1419） |

附注（非本任务引入）：`cargo clippy -p jackdaw --all-targets -- -D warnings`（**不带** dylib feature）在
main 上即失败——`tests/stress_reload.rs:1` 的 `#![expect(clippy::print_stdout)]` 在无 dylib 时未触发
（unfulfilled lint expectation）；该文件本任务未触碰，CI/fast/integration 门配置均带 dylib 不受影响。

## 4. 视觉项结论（验收清单第 5 条）

**未验证，留 QA。** 依据：
1. 编辑器 CLI 无「直开项目」参数（`src/launch.rs:18-56`：仅 Editor/Help/Version/ExportTerrain），
   进入 `AppState::Editor` 需在项目选择 UI 中交互打开项目，无法零交互复现「Level Design 工作区打开即见面板」。
2. 仓库无 UI 窗口截图设施（`viewport.screenshot` 只截 3D 视口渲染，不截 UI 面板）。
3. headless 测试已断言面板结构存在（行/分组/卡片/空态文案渲染），但非视觉观感验证。不推定。

## 5. 遗留问题 / 交给任务 2

1. **只读语义的边界**：资源卡上的控件提交仍走 `SetBsnField` 管线，对资源实体被静默丢弃（方案 D1-3
   预期行为）。极窄角落：若当前选中场景实体恰有与某 Resource 同 type_path 的组件，输入可能写到该实体；
   任务 2 的 `ResourceFieldTarget` 分流（marker 已埋）消除之。
2. **枚举卡片的变体刷新**：`refresh_enum_variants` 以 selection primary 为门，资源枚举字段值会同步、
   变体结构变化需重新选中才重建；任务 2 可顺手处理。
3. **过滤输入每敲一字重建列表**（行数少、成本低；搜索框在重建区外，焦点不丢）。
4. `avian3d::math::Gravity` 白名单条目在游戏未带 physics 模块时静默无效（by design，容错）。
5. `GizmoConfigStore` 仅在 gizmo 组初始化后才出现（未实例化不枚举，by design）。

## 6. 自查确认

- `git diff main` 共 9 文件，无 operator/EditorCommand/commit 分流/Add-Remove 按钮（任务 2 内容零越界）。
- 无 `loop/` 改动（本报告除外，loop/ 不入 git）；`Cargo.lock` 未动。
- 新代码零 `#[allow]`/`#[expect]`；文档注释齐全；风格照邻近文件。
