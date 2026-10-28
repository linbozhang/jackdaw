# T02 任务 1 报告：编辑目标正确性 + 静默失败可观测 + save-skip + headless 一致矩阵

> 分支 `loop/t02-inspector`，提交 `dbe4d09f`（基于 main bc5274ee）。
> 方案：`loop/plans/t02-inspector-loop.md` 任务 T02-T1（§2/§3/§4/§6）。
> 日期：2026-10-24 · 程序：ZCode（GLM-5.3）

## 1. 🔴 D1 编辑目标正确性（竞态修复）

**缺陷**：提交链按*执行时选区*定位目标（`field_edit_session_targets` = 执行时刻
`Selection.entities`），与控件的 `FieldBinding.source_entity`（构建时烘焙）脱钩。同帧
「提交 A 行 + 切换选区到 B」会把 A 的值写进 B（最坏形态：编辑写进新目标）。

**修法**（裁决①语义：严格丢弃，不写旧目标）：

- `src/commands.rs`：
  - 新增公开 const `STALE_FIELD_EDIT_DROPPED: &str = "field edit dropped: its entity left the selection"`（仿 `PREVIEW_EDIT_REFUSED` 先例，QA 日志可 grep）；
  - 新增 `stale_bound_entity(world, bound)`：bound 不在当前 `Selection.entities`（或 Selection 缺失）→ 返回该实体；
  - `field_edit_commit` / `field_edit_preview` 增加 `bound: Option<Entity>` 参数：stale → `warn!` + `clear_field_edit_session` + return；在选区内 → 照旧整选区提交（多选多编原样）；`None` → 原行为（无绑定的调用者不变）；
- 三调用点透传绑定实体：`apply_field_json_with_undo`（文本/数值/勾选提交）、`apply_color_with_undo`（颜色）、`commit_val_to_field` + `apply_field_value_live`（Val 行与拖拽 live tick）；
- 其余 `field_edit_commit`/`field_edit_preview` 调用者（asset_row/bindings_card/node_card/ops/ui_text_edit/probe_bake/enum/list 路径与 commands.rs 单测）按方案 §2.3 传 `None` 不动语义，全仓清剿留 T03。

**红→绿证据**（用例 `field_targeting::an_edit_committed_as_the_selection_moves_writes_neither_entity`，
同帧 `trigger(ValueChange{4.0, is_final})` → `select_single(B)` → `update()`）：

- 红（临时将 `apply_field_json_with_undo` 还原为 `None` 复现旧行为）：
  `assertion 'the entity the user moved to was not written' left: 4.0 right: 2.0` —— B 被写成 4.0，
  另「丢弃可闻」用例同红（无 warn）；
- 绿（`Some(entity)` 门生效）：B 保持 2.0、A 保持 1.0（严格丢弃）、undo 栈深度不变、
  日志出现 `field edit dropped: its entity left the selection: 'bevy_transform...translation.y' bound to 4411v0`。

**D1 其余用例**（`tests/inspector/field_targeting.rs`，4/4 绿）：

| 用例 | 断言 |
|---|---|
| an_edit_committed_as_the_selection_moves_writes_neither_entity | 竞态红→绿（上） |
| an_edit_while_two_entities_are_selected_still_writes_both | 多选多编锁定：[A,B] 选区、primary=B 的卡提交 → A、B 同步 4.0（门不误伤） |
| after_the_same_frame_switch_no_binding_outlives_the_selection | settle 后无任何 `FieldBinding.source_entity` 落在选区外（stale-binding 不变量；借助新公开助手 `inspector::field_binding_entity`） |
| the_dropped_edit_says_so_in_the_log | 线程局部 tracing 订阅捕获日志，断言含 const 串（丢弃可闻） |

## 2. D3 静默失败三处补 warn（不改行为）

| 丢弃点 | 位置 | warn 内容 |
|---|---|---|
| `SetBsnField::execute` 实体不在文档 | commands.rs（原 :1482 静默 return） | `field write skipped: {entity} is not in the scene document ('{type_path}')` |
| `field_edit_commit` 目标不接收该值 | `field_edit_to_bsn_value` None 的 `continue` | `field edit did not convert: '{tp}.{fp}' on {target} has no field taking {json}` |
| `apply_json_field_to_ecs` 反序列化/路径失败 | 原 `if let Ok` 静默跳过两分支 | `live write skipped: ... did not deserialize / did not resolve ({error})`（未注册类型等深水区分支按方案不深究） |

## 3. D5 save-skip 前缀（T01 QA ⚪ 收口）

- `src/scene_io/mod.rs` `SKIP_COMPONENT_PREFIXES` 增 `"jackdaw_camera::"`（`editor_writer_config` 自动继承），附对照 `jackdaw_camera_rig::ActiveCameraRig` 先例的注释；
- 单测 `scene_io::camera_tests::editor_camera_settings_stay_out_of_the_save`：用 `JackdawCameraSettings::type_path()` 真实路径断言 skip 命中（防字符串拼错，仿 gltf_authoring 先例）。

## 4. D2 headless 三处一致矩阵（新增 4 用例，4/4 绿）

`tests/inspector/three_way_matrix.rs`，每格均覆盖 ①Inspector 编辑→ECS 即变 ②AST patch 落档 ③`save_scene`→重开（`scene_open_system` 重载）一致：

| 格 | 用例 | 字段链路 |
|---|---|---|
| 灯① DirectionalLight | a_directional_light_color_and_illuminance_edit_reach_everywhere | color（`ValueChange<Vec2>` 打红/蓝平面）+ illuminance（`ValueChange<f64>` 数值链）+ undo 回默认 10,000 + 存盘重开双值一致 |
| 灯② PointLight | a_point_light_range_edit_reaches_everywhere | range（数值链）三处一致 |
| 相机 | a_camera_field_edit_survives_save_and_reopen | `Camera3d.depth_texture_usages.0`（u32，`ValueChange<i64>`）三处一致（见偏差①） |
| Transform 锚点缝合 | a_transform_edit_survives_save_and_reopen | translation.y 编辑→AST→存盘→重开（typed_entry 的 ① 与既有 save 跳测缝合为一条） |

自定义组件/材质两类按方案矩阵免补（现成覆盖）。

## 5. 门禁（quick tier + 全量两门）

| 门 | 结果 | 数字 | 日志 |
|---|---|---|---|
| `cargo check -p jackdaw --tests` | ✅ exit 0 | — | 控制台 |
| `cargo fmt --all --check`（xtask fast 内含） | ✅ | — | loop/reports/t02-t1-gate-fast.log |
| clippy workspace all-targets dylib `-D warnings`（xtask fast 内含） | ✅ | — | 同上 |
| `cargo xtask fast`（fmt+core_deps+git_deps+clippy+nextest --lib） | ✅ exit 0 | **2856 passed / 2 skipped**（33.9s） | loop/reports/t02-t1-gate-fast.log |
| `cargo xtask integration` | ✅ exit 0 | **5014 passed / 3 skipped**（291.2s） | loop/reports/t02-t1-gate-integration.log |
| 定向回归：`--test inspector` 全量 | ✅ | 161/161（84.9s） | temp 日志（jd_full_inspector.log） |
| 定向回归：`--lib` | ✅ | 1124/1124（含 D5 新用例） | temp 日志（jd_lib.log） |

## 6. 与方案的偏差

1. **相机格字段**：方案候选 `Camera.order`/`Projection fov`/`Exposure` 在当前面板上**不存在可编辑行**——probe 实测 Camera3d 实体的卡只有 `bevy_camera::components::Camera3d` 自身字段（`depth_load_op.0`/`depth_texture_usages.0`）加 Transform，Camera/Projection/Exposure 无卡（required 派生体被卡片层抑制）。改用 `Camera3d.depth_texture_usages.0`（同为 Camera3d 实体上的相机字段）覆盖该格；真机 §7-6 的「改一个 Projection 字段」需先让这些卡可编辑，属可发现性/卡片层范围，移交 T02-T2 或后续裁定。
2. **DirectionalLight 数值字段用 illuminance**：该版本 DirectionalLight 无 `intensity` 字段（PointLight 才有），数值链以 illuminance 代表，符合方案「数值（intensity）」的意图。
3. 测试世界存在两个面板实例（编辑器默认布局 + 测试自建 content，既有 typed_entry 范式同此），颜色平面按「任取一个」定位，不影响断言。
4. D1 门同样作用于 preview tick（拖拽中切实体同帧的 live tick 也丢弃+warn），与方案 §2.3「含 live 分支」一致。

## 7. Concerns

- **丢弃 vs 写回的用户手感**：裁决①下，blur 提交遇上同帧切换会丢一次输入（无 UI 提示，仅日志）——方案已裁定一致性优先；UI 级提示挂 T24。
- `field_edit_commit_on`/`field_edit_commit_on_from`（单实体显式目标）与 enum/list 编辑链未接门（方案明确留 T03）；后者同样存在理论竞态面。
- 真机 QA（方案 §7-2/§7-3 快速切换实测、抽验）属任务 QA 段，未在本报告内（headless 已覆盖语义）。
