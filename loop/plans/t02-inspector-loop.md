# T02 实施方案：Inspector 参数编辑闭环

> 多 Agent 开发循环 · 策划产物（只写方案，不含代码实现）
> 日期：2026-10-24 · 策划：资深 Bevy 编辑器工程师 Agent（只读调研：rg + Read，未跑 cargo）
> 需求真理之源：`loop/plans/roadmap-game-dev.md` T02 条目（用户裁定 2026-10-24）。
> 验收语句：相机/灯光/模型/材质/自定义组件的**分类显示编辑刷新**；**切换实体后不得编辑旧目标**；
> 改参数**三处一致（组件/视口/存档）**，**重开一致，无隐藏无静默失败**。
> 基线：main 66c35b0a + 91459d34（dx12 任务在 loop/dx12-backend 分支进行中；本任务分支自其合入后的 main 拉）。
> 历史包袱（吸收）：#6T1 已修分类映射+粘性（commit 12318dab，用户已验收）；#6T2 遗留
> （可发现性 tooltip+标头、灯 color 真机验证、全量 CI）；T01 QA ⚪（`jackdaw_camera::` save-skip 脚枪）。

---

## 1. 范围与不做

**做**（五件）：

1. **D1 编辑目标正确性**（T02 核心新语义）：修掉「提交链按*执行时选区*而非*绑定实体*定位目标」的竞态——
   切换实体同帧到达的编辑提交可能把 A 的值写到 B。修复 + 竞态用例 + 不变量用例；
2. **D2 三处一致矩阵补齐**：灯（三种）、相机字段的 headless「编辑→AST→存盘→重开」用例；
   Transform 补一条「Inspector 编辑→存盘→重开」锚点用例（复用 `typed_entry.rs` 骨架）；
3. **D3 静默失败面收口**：编辑提交链上三个静默丢弃点补 warn（可观测，不改行为语义）；
4. **D4 可发现性两招**（#6T2 遗留）：分类条 tooltip 加 description + 内容列常显当前分类名标头；
   灯 color 编辑真机验证（链路 #6T1 后理论零代码，需实证）；
5. **D5 `jackdaw_camera::` save-skip 一行**（T01 QA ⚪ 顺手收口）+ 全量 CI 门（doc/doctests 基线，#6T2 遗留）。

**不做**：

- **不改 Resources 面板链路**（`resource_commands` 有自己的 ResourceFieldTarget/`is_resource_entity`
  路由，功能#1 已闭环；本任务只保证实体卡链路不误伤它——`apply_field_json_with_undo` 开头的
  resource 路由分支原样保留）；
- **不动 PIE Live 编辑流**（`try_route_pie_live_field_edit` 分支原样；运行态调参属 T25）；
- **不做 B 区 Graphics 面板 Environment 乐观回写**（功能#8 ⚪backlog，非本任务）；
- **不做灯/相机编辑的专项 UI**（通用反射通道已覆盖，见 D2；不新做卡片）；
- **不补 `bevy_render::`/`bevy_pbr::` 大 namespace 映射**（#6T1 宁缺毋滥决策维持）；
- **Undo/Redo 全面加固**（含本任务 D1 修复区的 undo 语义核查只限新增改动）属 T03；
- 视觉上不新增分类 tab、不加宽 strip 轨道（#6T1 裁决维持）。

---

## 2. D1. 编辑目标正确性：提交链竞态（🔴 本任务头号缺陷，先修）

### 2.1 现状机制（证据链，全部实读）

- **绑定**：每个字段控件挂 `FieldBinding { source_entity, type_path, field_path }`
  （`src/inspector/mod.rs:381-385`），**构建时烘焙**所属实体；
- **重建**：选区变化 → `sync_inspector_to_selection`（`src/inspector/component_display.rs:74-195`）
  移除 `InspectorTarget`/`Monitor` 并 `despawn_inspector_display_children`（:970-988，
  **commands 队列，延迟到 sync 点执行**；despawn 递归带掉全部嵌套 binding）；
- **提交观察者**（`on_text_edit_commit` / `on_numeric_value_change_f64/i64` / `on_checkbox_commit` /
  `on_color_plane_change` / `on_color_slider_change` / `val_field::on_val_*`）读出
  `binding.source_entity` 后调用：
  - `apply_field_json_with_undo(world, entity, tp, path, json)`（`src/inspector/reflect_fields.rs:2166-2192`）：
    `entity` **只用于 resource/PIE 路由判断，随后的
    `crate::commands::field_edit_commit(world, tp, path, ...)` 把实体丢弃**；
  - `apply_color_with_undo(world, _entity, ...)`（同文件 :1849-1888，参数名 `_entity` 即自白，:1881 同样落
    `field_edit_commit`）；
  - `commit_val_to_field`（`src/inspector/val_field.rs:370-399`，:389 同）；
  - 拖拽 live tick 同样：`apply_field_value_live` → `field_edit_preview`（commands.rs:160-176），
    也按执行时选区定位。
- **目标解析**：`field_edit_commit`（`src/commands.rs:183-245`）→ `field_edit_session_targets`
  （:54-59）= **执行时刻的 `Selection.entities`**；
- **选区写入是立即的**：`Selection::select_single` 当场改 `self.entities`（`crates/jackdaw_api_internal/src/selection.rs:64-78`，
  仅 `Selected` 标记走 commands 延迟）。

### 2.2 竞态定性

窗口 = **同帧内**「选区已从 A 改为 B」到「旧卡 despawn 执行完」之间。任何在此窗口触发的
ValueChange 提交（触发源：blur 提交——点击 B 抢走输入焦点时文本框 is_final 提交与选区变更同帧；
Enter 提交与键盘/拾取选区变更同帧；scrub 拖拽释放在 outliner 行上方；BRP/合成输入脚本同帧注入两条操作）：

1. 观察者读到旧 widget 的 `FieldBinding` → 实体 A；
2. 闭包在 sync 点执行，`field_edit_commit` 读到 `Selection.entities = [B]`；
3. **A 的字段值写到 B**（B 有同 type_path 组件时；组标签 "Set field on multiple entities" 还会误广播）；
   B 没有该组件时 `field_edit_to_bsn_value` 返回 None → `continue` **静默丢弃**（commands.rs:209-213）。

这正是验收语句「切换实体后不得编辑旧目标」要堵的洞——而且是最坏形态（**编辑写进新目标**）。

**反向核查（已正确的部分，不重造）**：
- 重建完成后旧 binding 全灭（递归 despawn），新卡绑定新 primary——静态正确；
- 刷新链按 `binding.source_entity == primary` 过滤（`reflect_fields.rs:2873/2891/2908/3116`、
  `val_field.rs:590`）——旧值不会被刷进新卡；
- 远端代理只读守卫在观察者内（`reflect_fields.rs:2646/2709/2786`）；
- `on_inspector_dirty` 的「目标实体已 despawn → 回退 primary」重指向（component_display.rs:1041-1057）
  只影响显示，不产生编辑写入。

### 2.3 修法（保住多选多编，堵住跨实体写）

多选多编是既有特性（多选时 inspector 显示 primary 的卡，编辑广播整组——
`component_display.rs` 多选头注释 + 组标签 "Set field on multiple entities"）。修法不动它的语义：

- `field_edit_commit` / `field_edit_preview` 增加**绑定实体门**参数（`bound: Option<Entity>`）：
  - `bound` 实体 **仍在当前 `Selection.entities`** → 照旧整选区提交（多选多编原样）；
  - 不在 → **丢弃 + warn**（新 const 串，仿 `PREVIEW_EDIT_REFUSED` 先例
    `src/preview_context.rs:70` + warn 调用 :199-202 的写法），QA 日志可 grep；
- 三个调用点把已有的实体参数传进去：`apply_field_json_with_undo`、`apply_color_with_undo`、
  `commit_val_to_field`（含 live 分支 `apply_field_value_live`）；
- 其余 `field_edit_commit` 调用者（bindings_card/node_card/ops/ui_text_edit/probe_bake/animation 等
  无实体绑定或自带实体的路径）**不动**，本任务不做全仓清剿（T03 视需要）。

语义效果：切换实体后，飞行中的编辑要么落在仍被选中的整组上，要么显式丢弃（日志可闻），
**绝不落在新目标上**。丢弃语义（vs 仍写给绑定实体 A）见裁决项 1。

### 2.4 验证用例设计

headless（`tests/inspector/` 新增，骨架抄 `typed_entry.rs` / `selection_switch.rs`）：

1. **竞态红→绿用例**（核心）：A、B 均为带 Transform 的文档实体；select A 并 settle；
   找到 `field_edited_by == (Transform, "translation.y")` 的 A 行控件；**同一帧内**
   先 `world.trigger(ValueChange{source: A行, value: 4.0, is_final: true})`、再
   `selection.select_single(B)` + flush、再 `app.update()`。断言：
   - B 的 `translation.y` **未被写**（今天此断言红——现状会写 B）；
   - A 的值或被丢弃或落 A（按裁决 1 的语义定二选一断言），undo 栈不得出现指向 B 的条目；
   - settle 后不存在 `source_entity != Selection::primary()` 的 `FieldBinding`（stale-binding 不变量）。
2. **多选保留用例**：select [A,B]（primary=B），编辑 A 行提交 → A、B 同步变更（现行为锁定，
   防修复误伤多编）。
3. **丢弃可闻用例**：裁决 1 语义下，同帧切换丢弃时日志出现新 const 串（Recorder 模式，
   `selection_switch.rs:18-55` 现成）。

真机：见 §7 QA 清单「快速切换实测」。

---

## 3. D2. 三处一致矩阵：现成 / 补齐

「三处」= ① Inspector 改（提交链）→ ② 视口即变（ECS 镜像）→ ③ Ctrl+S 存盘 + 重开一致
（AST 文档 + roundtrip）。链路事实：`SetBsnField::execute` 文档写入后 `mirror_patch_to_ecs`
镜像回 ECS（commands.rs:1515-1517），视口随 ECS 即变；脏状态由 `CommandHistory` 长度对
`SceneDirtyState.undo_len_at_save` 求差（save.rs:265/364）——**编辑必入历史，Ctrl+S 必捕获**。

| 组件类 | ① 编辑链 | ② 视口即变 | ③ 存盘/重开 | 现成测试 | 缺口（本任务补） |
|---|---|---|---|---|---|
| Transform（数值/拖拽/Enter/blur） | ✅ 通用反射链 | ✅ ECS 镜像 | ✅ 文档写（#6T1 后必过 save-skip） | `tests/inspector/typed_entry.rs`（commit/blur/undo/refresh 全套） | **锚点用例**：typed_entry 骨架 + `save_scene` + 重开断 translation（把①③缝成一条） |
| 相机 Camera3d+Camera/Projection 等 | ✅ 通用反射链（#6T1 后卡在 object tab 可见） | ✅（`deactivate_document_cameras` 只关渲染不影响数据，scene_io/mod.rs:306-310） | ✅（`bevy_camera::` 不在 skip 名单；`tests/stage/scene_environment.rs:219` a_camera_..._saves_as_it_was_authored 证 roundtrip） | 可见性+保存 roundtrip 有；**编辑无** | **新用例**：select 相机实体 → trigger 字段提交（如 `Camera.order`/Projection fov）→ AST patch + save/reopen 断言 |
| 灯 DirectionalLight / PointLight / SpotLight | ✅ 通用反射链（color 走 ColorFieldState→`apply_color_with_undo`，reflect_fields.rs:1789-1888） | ✅ | ✅ | **编辑链全缺**（`selection_switch.rs:144` 仅重建无错误；真机验证 #6T2 遗留未做） | **新用例**：① color（trigger `ValueChange<Vec2>` 平面 / `ValueChange<f32>` 滑条）② 数值（intensity）→ AST patch + undo + save/reopen；真机闭环见 §7 |
| Mesh 材质参数（material 卡片，编辑的是材质资产） | ✅ material 卡编辑资产值 | ✅ | ✅ 资产随场景 inline 保存（`emit_bsn_scene_with_inline_assets`，save.rs:972） | `tests/inspector/material_row.rs`（pick/undo/清除）、`tests/stage/material_row.rs:253` pick 后 save+reopen、`save.rs:2074` authored_paint_and_materials_survive_save_and_reload | 不新增（复用现成；QA 真机抽验一条参数编辑即可，见 §7） |
| 自定义组件（用户 Reflect 组件 / 项目 schema 组件 / CustomProperties） | ✅ | ✅（项目组件文档即状态） | ✅ | **最全**：`typed_entry.rs` Sign 全套、`tests/guards/scaffolded_component_flow.rs:189/253`（edit→ECS+AST、undo）、:453（project 组件 open+reserve roundtrip）、:624（color 读回）、`tests/inspector/project_component_card.rs:451`（枚举编辑） | 不新增 |

**统计**：5 类中 **2 类现成免补**（自定义、材质），**3 类补齐**（相机、灯 = 全新 headless 用例；
Transform = 一条锚点缝合用例）。全部走 `field_edited_by` / 直接 trigger 的既有测试方法论，
不新建测试基建。

---

## 4. D3. 静默失败面：三个丢弃点补 warn（一行级，不改行为）

| 丢弃点 | 位置 | 现状 | 处置 |
|---|---|---|---|
| `SetBsnField::execute`：实体不在文档（`ast_for` None） | `src/commands.rs:1482-1484` 静默 `return`（undo 条目仍入历史 = 假条目） | 无声 | **warn**（列名实体+type_path；T02 做） |
| `field_edit_commit`：`field_edit_to_bsn_value` None 丢目标 | commands.rs:209-213 `continue` | 无声 | **warn**（T02 做） |
| `apply_json_field_to_ecs`：反序列化/路径失败 | commands.rs:1646-1672（`if let Ok` 悄悄跳过、reflect_path_mut Err 跳过） | 无声（`parse_to_json_value` 的 doc 注释 :2194-2197 自认 "the edit silently reverts"） | **warn**（T02 做，仅 deserialize/路径两分支；「未注册类型」可能来自卡本不该出现的深水区，只 warn 不深究） |
| `mirror_patch_to_ecs` 无 patch | commands.rs:1435 | 无声（多为合理状态） | 不动（跟随上一行的 warn 即可分辨） |
| D1 新增丢弃 | §2.3 | — | **必带 warn**（const 串，QA 可 grep） |

风格：沿用 `PREVIEW_EDIT_REFUSED` 的「公开 const 串 + warn!」模式，QA 真机日志按串断言。
范围外：给编辑失败加 UI 级提示（toast/红框）——交互面大，挂 T24（调试反馈）。

---

## 5. D4. 可发现性两招落地（#6T2 遗留）

### 5.1 tooltip 加 description（数据进 registry）

- `InspectorCategory`（`crates/jackdaw_api_internal/src/inspector.rs:13-18`）增
  `pub description: Cow<'static, str>` 字段（扩展 `register_category` 天然可带，空串 =
  无描述行，Tooltip builder 自动跳过空行）；
- `spawn_category_strip` 的 `Tooltip::title(label)`（`src/inspector/category_strip.rs:117`）改为
  `.with_description(cat.description)`（builder 现成：`crates/jackdaw_feathers/src/tooltip.rs:100-103`，
  两级展开机制 300ms/1200ms 已在 tooltip.rs:32-38）；
- **en-US 文案**（存 registry 种子表；label 本就是硬编码英文，与现状一致——ftl 化是裁决项 2）：

| id | title | description |
|---|---|---|
| object | Object | Identity, transform and visibility: what this entity is. |
| mesh | Mesh | Brush geometry for this entity. |
| modifiers | Modifiers | Geometry modifiers applied to the brush. |
| material | Material | The material assets this entity's surfaces wear. |
| physics | Physics | Colliders and rigid bodies. |
| components | Components | Every other component on this entity. Add one here. |

### 5.2 内容列常显当前分类名标头

- 位置：`inspector_components_content` 内容列顶部（`src/layout.rs:955-1039`，AddHeaderMount 上方）
  加一个 `ActiveCategoryLabel`（新 marker + Text 节点）；
- 更新：小 Update 系统（`category_strip.rs`）在 `ActiveInspectorCategory.is_changed()` 时查
  registry label 写 Text（**不并进** `rebuild_add_header`——那个连带重生整套 add UI，label 单写更便宜；
  两者触发条件本就同源）；
- 样式：`tokens::TEXT_SIZE_SM` + `TEXT_SECONDARY` 小写字距标头（同 Graphics 面板 section 头的
  视觉等级，参考 `graphics_panel.rs` section 实现），文案 = 分类 label 原文（如 "Object"）；
- 不加卡片计数角标、不加宽 strip（#6T1 裁决维持）。

---

## 6. D5. `jackdaw_camera::` save-skip 脚枪：并入任务1，一行

- 证据：`should_skip_component`（`src/scene_io/mod.rs:150-168`）跳过 `jackdaw::` 前缀但**无
  `jackdaw_camera::`**；`JackdawCameraSettings` 是 `#[derive(Component, Reflect)] #[reflect(Component)]`
  可序列化组件（`crates/jackdaw_camera/src/lib.rs:55-57`），目前只 spawn 在编辑器视口相机
  （`src/viewport.rs:398`）——该相机带 `EditorEntity` 且不进 AST，**今天无实害**；
- 脚枪场景：它是注册过的 Reflect 组件，任何扩展/Add Component picker 把它加到**文档实体**上
  （或未来代码给文档相机佩戴），存档就会带上编辑器会话相机设置（对照先例
  `jackdaw_camera_rig::ActiveCameraRig` 的 skip 注释，scene_io/mod.rs:67-70）；
- 处置：**并入 T02 任务1**——`SKIP_COMPONENT_PREFIXES` 加一行 `"jackdaw_camera::"`
  （`editor_writer_config` :179-182 自动继承），配一行单测
  `should_skip_component("jackdaw_camera::JackdawCameraSettings") == true`。不值得单独任务/裁决。

---

## 7. QA 验收清单（真机为主，照 loop/qa/manual.md 契约）

**Quick tier 门（每任务）**：fmt / clippy -D warnings / test --workspace --lib / 被改 crate 集成测试。
**全量门（任务2 收尾，#6T2 遗留）**：`cargo xtask fast` + `integration` + docs + doctests 基线
（Windows 本机 doctests 101 环境性失败为已知基线，对照非回归）。

**真机项（fixture 或 my-game，plain 构建非 dylib——QA 教训）**：

1. **灯 color 编辑闭环**（#6T2 残余收尾）：选 Sun → DirectionalLight 卡 color picker
   （组件 bbox 定位法，f5 沉淀）改红 → ① `jackdaw/entity {name:'Sun'}` BRP 断言 bsn `color`
   变化 ② Ctrl+S 存盘、重开编辑器断言值保持 ③ 视口截图色偏可见（pixdiff）；
2. 同法抽验 Add 菜单新建 Point Light 的 color 或 intensity 一轮（数值链路）；
3. **快速切换实测**（D1）：A 行输入数值后**立即**（同帧合成：输入回车与 outliner 点击 B 连发）
   切到 B → BRP 断言 B 未被写、A 状态符合裁决 1 语义、日志出现/不出现丢弃 warn 与语义一致；
   连跑 5 轮换实体组合；
4. **标头可见**：内容列顶部常显 "Object"/"Components" 等当前分类名，切 tab 即变、切实体
   粘性解析（#6T1 语义）下仍正确；
5. **tooltip**：悬停 tab 图标 ≥300ms 出 title、≥1200ms 出 description 全文；
6. **相机抽查**：选 Main Camera → 改一个 Projection 字段（如 fov）→ 存盘重开一致（真机一轮，
   headless 已有主覆盖）；
7. 回归：Sun/Camera/Cube 的 object tab 卡集合与 #6T1 验收时一致（映射不被本任务波及）。

**用户 30 秒手测清单**（终审）：
- 选 Sun 把灯改成红色 → 视口立即变红 → Ctrl+S 关掉重开 → 还是红；
- 在 Cube 的 x 输入框敲数字后**马上点**旁边的灯实体 → 灯的 Transform 没被写进刚才的数字；
- 悬停 Inspector 左侧图标条任一图标 → 一秒后能看到一行说明；面板顶部能看到当前页签名。

---

## 8. 任务拆分（2 个任务，串行）

### T02-T1：目标正确性 + 静默失败 + save-skip + headless 矩阵（程序主体）

1. `field_edit_commit`/`field_edit_preview` 绑定实体门（§2.3）+ 三调用点透传 + D1 丢弃 warn const；
2. D3 三处 warn（§4）；
3. D5 save-skip 一行 + 单测（§6）；
4. headless：D1 三用例（竞态红→绿 / 多选保留 / 丢弃可闻 + stale-binding 不变量）；
   灯 ×2（color、数值）、相机 ×1、Transform 锚点 ×1（§3 缺口列）；
5. quick tier 四门。

QA：四门 + 真机 §7-3（快速切换）+ §7-2 抽验；报告落 `loop/reports/`。

### T02-T2：可发现性两招 + 真机闭环 + 全量 CI（收尾）

1. D4：registry description 字段 + 六条 en-US 文案 + tooltip builder 接线 + `ActiveCategoryLabel`
   标头（§5）+ 标头/tooltip 的 headless spawn 断言各一；
2. 真机 §7-1/4/5/6/7 + 用户 30 秒清单整理；
3. 全量 CI（fast/integration/docs/doctests 基线）；
4. 台账 `loop/progress.md` 记行 + roadmap T02 勾选。

---

## 9. 风险

1. **D1 修法波及面**：`field_edit_commit` 的其它调用者（bindings_card/node_card/ops/ui_text_edit/
   probe_bake/animation）行为不变（不传门参数），但 QA 需跑 inspector 全套集成测试防误伤
   （tests/inspector/ 17 文件 + guards）；多选多编用例锁定现行为；
2. **裁决 1 语义若选「仍写绑定实体」**：blur 提交体验更顺，但与验收语句字面冲突且 undo 条目
   指向非选中实体——undo 面板显示可能困惑；推荐丢弃+warn（一致性优先）；
3. **灯 color 真机若不绿**：#6T1 结论「链路零代码可用」基于代码审读，若真机实证失败（如
   ColorFieldState 初始化缺陷），修复范围以复现报告为准，不预设方案；
4. **Tooltip 标头视觉**：30px 窄轨 + Figma 风格约束下标头只放内容列（方案已避开轨道加宽）；
   视觉终审留用户；
5. **相机字段 headless 用例的组件依赖**：`Camera3d` require 链可能拖入额外派生卡干扰
   `field_edited_by` 定位（#6T1 已知现象，object tab 可能混 CascadesFrusta 等派生卡）——用例
   按 field_path 精确找控件不受卡片数量影响；
6. **doctests Windows 环境性 101 失败**：全量门以「基线恰同、零新增」口径放行（既有裁定）。

---

## 10. 需用户裁决项

1. **切换实体后飞行中编辑的语义（D1）**：推荐 **丢弃 + warn**（严格满足「切换后不得编辑旧目标」，
   一致性最强）；备选 **仍写给绑定实体 A**（blur 提交不丢用户输入、更贴 Unity 手感，但字面上
   编辑了「旧目标」）。影响 §2.4 断言与 §7-3 步骤文案。
2. **分类描述文案载体（D4）**：推荐 **registry 静态 en-US 字符串**（与 label 现状一致、扩展
   API 天然支持）；备选 **ftl + LocalizedText**（本地化正确，但 label/六 tab 文案须一起迁移，
   范围扩大到半个 UI 本地化工程，建议挂亮色主题同档低优先积压）。
3. D5 并入 T02-T1（默认执行，无成本，如有异议请提出）。
