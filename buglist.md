> ⚠️ **2026-10-26 编码事故与恢复注记（主控）**：本文件曾于 18:0x 被一次 PowerShell 文本管道（GBK 代码页往返）损坏（790 个 U+FFFD+行合并）。已从 T07 策划 agent 上下文的健康快照（10-26 15:0x 读取）全文重建，并回放其后全部合法变更（R9/R10/Y7 勾选与备注、N10 勾选与修复备注）；N11/N12 为事故后按报告底稿重建（标注见条目）。受损原件存档 `loop/reports/buglist.damaged-20261026.md`。**此后对本文件的一切写操作只准用字节安全工具（Read/Edit），禁 PowerShell 文本管道。**

# Jackdaw Code Review Buglist（main 分支，2026-10-24）

> **使用说明（给核验 agent）**：每条以 `- [ ]` 开头，核验确认问题属实且已处理（修复或有明确处置结论）后改为 `- [x]`。
> 核验方法：按 `文件:行号` 读当前代码，确认问题仍存在 → 修复 → 复核 → 打钩，并在条目末尾追加一行备注（如 `> 已修复 <commit/说明>` 或 `> 误报，原因：…`）。
> 编号规则：`R`=🔴 严重（功能错误/崩溃/数据损坏），`Y`=🟡 中等（隐患），`W`=⚪ 轻微/优化。
> 共 **75 条**：R 10 条、Y 37 条、W 28 条。行号为 review 时快照，若代码已变动请按符号名重新定位。

---

## 🔴 严重（10 条）

- [x] **R1. 关键帧 undo 绕过文档 AST，产生重复关键帧与"幽灵复活"**
  `src/lib.rs:1191-1193`（`DespawnKeyframeCmd::execute` 裸 `ent.despawn()`）、`src/lib.rs:1961-1965`（undo 裸 `spawn` + `ChildOf(*track)`）。
  问题：关键帧实体经 `register_animation_entities_in_ast`（`src/lib.rs:2098`）注册进文档，但删除/重生不走 `despawn_scene_entity` / AST 注册，直接违反 `commands.rs:502-507` 的 ChildOf 红线。
  后果：文档节点残留 → undo 重生的实体被 `Added` watcher 注册成第二个节点 → 同一时间出现两个关键帧；整文档 respawn 的 undo（`undo_snapshot.rs:296`）会把已删关键帧复活。
  修复方向：改用 `commands::despawn_scene_entity` / `scene_io` 的 AST 注册，或复用 `SpawnEntity`/`DespawnEntity` 命令。
  > 已修复 b9a8842d（T03-T1）：关键帧四命令 despawn 改 `despawn_scene_entity`、spawn 后同步 `register_entity_in_ast`；toggle_keyframe op 内同步注册（N3）。guards keyframe_undo 全绿复测（T03-T2，6df9ac89）。
  > 尾巴已补 765b4599（T03-T2 返工 1，终验 FAIL 项）：键位路径（Delete/Backspace 删、Ctrl+V 粘）的 `clip.delete_keyframes`/`clip.paste_keyframes` 自推却默认 allows_undo=true，T1 修复使关键帧落文档后快照 diff 非空 → 双记录、undo 撤完出重复关键帧（R1 症状真实用户路径复现）。补显式 false + 键位设置（Invoke+history:true）红→绿测试（红 2≠1）+ SELF_PUSHING 清单钉死；同轮补齐 brush.join（J 键，双记录实证）、pie.live_edits_apply_all、terrain.generate/erode、resource.insert/remove/set_field 共 9 个自推声明，live 探针 10/10。
  > 返工 2 补齐 4a2cf332（QA 复验揪出的同型漏网，二层间接盲区）：`brush.extend_face_to_brush`（Ctrl+E 键位，queue 闭包→`extend_face_to_brush_impl` 自推 SetBrush 写文档，与 join 同型，红 2≠1 + 键位行为测试）与 `pie.live_edit_save`（自推 save 命令）补声明入清单（50→52）；一层间接扫描并入 `loop/qa/scan-selfpush.ps1`，全仓零未声明自推 op（含 sanity 反证）。

- [x] **R2. 数值变换（X+数字+Enter）不落文档：不可撤销、保存丢移动、脏标记不亮**
  `src/numeric_transform.rs:433-471`（op）、`:475-528`（`apply_object` 直改 ECS `Transform`）。
  问题：op 带 `allows_undo=true`，但不推 `SetTransform` 也不写 AST；全仓不存在 `Changed<Transform>`→AST 的镜像 watcher（Brush 有 `sync_changed_brushes_to_ast`，Transform 没有对应物）；gizmo/拖拽路径靠 `SetTransform::sync_after_external_execute` 补文档，唯独此路没有。
  后果：① undo 快照 diff 不到变化 → Ctrl+Z 撤的是上一个操作；② 保存从 AST emit → 移动丢失；③ 脏标记按 undo 栈判 → 标签页显示"未修改"，关窗无提示。
  修复方向：object 路径改走 `SetTransform` + `push_executed_synced`（与拖拽提交一致），或补 `Changed<Transform>` 的 AST watcher。
  > 已修复 b9a8842d（T03-T1）：两分支改统一框架快照单条（Object 分支执行 SetTransform 不 push，BrushEdit 分支内联 brush→AST 同步）。guards numeric_transform_undo 全绿复测（T03-T2，6df9ac89），真机链 X+1+Enter→恰一条→保存保移动亦复测通过。

- [ ] **R3. Save as Variant 把任意深度的子树拍平成一层，变体层级与位置错乱**
  `src/prefab/operators.rs:1715-1741`（`save_as_variant`）。
  问题：`descendant_data` 收集任意深度子孙，但每个节点都 `add_child_to_ast(variant_root, child)` 挂到 variant 根下；变体展开按 PrefabEntityId 匹配到已拍平节点，原 prefab 不再按原层级克隆。`copy_component_patches(.., drop_markers=true)` 还会丢弃嵌套子实例的 `IsA`（内嵌 prefab 被烤死）。
  后果：3 层 prefab 存变体后，所有实例孙级提升为一级子节点、世界位置可见错乱。
  修复方向：按 `ast_parent_of` 重建父子关系，每个子孙挂到其原父节点在变体中的对应节点下。

- [ ] **R4. 远程实体树父子解析与协议格式失配，远程层级面板整体失效**
  `src/remote/entity_browser.rs:92-97`（`extract_parent` 用 `as_u64()`）。
  问题：生产端 `crates/jackdaw_pie_protocol/src/snapshot.rs` 序列化的 `ChildOf` 是实体文本形式（如 `"0v1"`）或 `[bits]` 数组，`as_u64()` 均返回 `None`；协议 crate 专门提供了 `entity_bits()`（`src/pie_projection.rs:79` 用的就是它），此处没用。
  后果：`jackdaw/scene_snapshot` 拉回的所有实体被判为根、`has_children` 恒 false、懒展开永不填充，远程层级树退化为平铺列表。
  修复方向：改用 `jackdaw_pie_protocol::snapshot::entity_bits(&value)`。

- [ ] **R5. 空地形上点 Erode 直接 panic**
  `crates/jackdaw_terrain/src/erosion.rs:75` + `src/terrain/ops.rs:308-312`（`terrain_erode`）。
  问题：`rng.random_range(1.0..(res - 2) as f32)` 对 resolution 0–3 为空/反区间，rand panic（`terrain_generate` 在 ops.rs:246-251 有空地形分支，erode 没有）；面板 Erode 按钮（`src/terrain/panel.rs:2449-2456`）只有 `has_selected_terrain` 门槛，UI 可直接触达。
  修复方向：kernel 开头 `if resolution < 4 { return; }`，或 op 里拒绝 `grid_resolution() < 4`。

- [ ] **R6. Scatter placement 坐标无界，一个远点撑爆稠密网格导致编辑器 abort**
  `crates/jackdaw_terrain/src/sidecar.rs:1431-1441`（`add_placement`）、`region.rs:622-628`（`stored_extent` 平方化）、`src/terrain/scatter.rs:744-753`（import 无范围检查）。
  问题：坐标只有 region 总量上限（1024），无位置边界；远处坐标分配 region 后 `stored_extent` 包围盒平方化至 ~100 万格/轴，`sync_terrain_surface` 每帧 `sample_grid_heights_into` 的 `reserve(resolution²)` 达 TB 级 → 下一帧分配失败 abort，撤销救不回来。
  修复方向：`add_placement` 拒绝超出当前 regions 包围盒合理余量（如 2 倍跨度）的坐标，import/adopt 报"落在地形外"。

- [ ] **R7. Nudge（PageUp/PageDown）走凸包重建，直接摧毁凹多面体笔刷**
  `src/brush_element_ops.rs:356-357`（`rebuild_brush_from_vertices`，实现在 `src/brush/hull.rs:18`，内部为 `jackdaw_hull` 凸包）。
  问题：vertex drag 走 `apply_vertex_deltas`（半边优先），nudge 完全不查 `BrushHalfedge`。对 CSG/Knife 产出的凹笔刷，选中面按 PageUp，整个 brush 被静默替换为顶点凸包（L 形变方块）。
  修复方向：nudge 改走 `apply_vertex_deltas`（半边优先、hull 仅 legacy 兜底），与 vertex drag 共用路径。

- [ ] **R8. Extend-to-Brush 用凸半空间交集重建，凹主笔刷被凸化**
  `src/draw_brush/extend_face.rs:288-329`（`compute_brush_geometry_from_planes` + `clean_degenerate_faces` + `compute_brush_topology` 凸范式路径）。
  问题：subtract 侧（`csg_ops.rs:253-259`、`preview_mesh.rs:587-591`）注释已明确该路径"把凹笔刷坍缩成凸包或空拓扑"并刻意绕开，extend 仍在用。
  后果：凹主笔刷执行 Extend 后几何被静默重铸为凸体。
  修复方向：迁移到 mesh-CSG，或检测到非凸时拒绝执行并提示。

- [x] **R9. Build 日志面板永远空白（ScrollPosition 从未插入）**
  `src/scrolling_log.rs:62-99`（`spawn()` bundle 无 `ScrollPosition`）、`:101-105`（`refresh_scrolling_logs` query 要求它）。
  问题：bevy 中 `ScrollPosition` 不随 `Overflow::scroll_y()` 自动插入（已对照 bevy 源码），query 永不匹配 → `ScrollingLog.content` 永远写不进内部文本、也不会 pin 到底。唯一消费者是 Build 面板（`src/build_panel.rs:123`）。
  修复方向：`spawn()` bundle 里加 `ScrollPosition::default()`。
  （2026-10-26 T07-T2 修复：bevy 上游 `eb19a9ea0`（PR #15898）已把 `ScrollPosition` 列为 `Node` required component，症状随 rev 升级自愈——红证因此不可得（测试未修先绿，bevy 源码核实）；处置=按方案显式 `ScrollPosition::default()` + 回归钉 + 真机铁证（`ui_tree` 命中面板文本节点、含完整 `building/Compiling` 日志，截图 loop/t07t2-live/）。提交 `9a80bcbc`。）

- [x] **R10. 导出 staging 硬编码 `assets` 目录，忽略 `jackdaw.toml` 的 `assets_dir` 配置**
  `crates/jackdaw_project_build/src/export.rs:60`（`assets_source: root.join("assets")`），调用方 `src/game_export.rs:147`、`crates/jackdaw_cli/src/lib.rs:835`。
  问题：项目可配 `assets_dir = "content"`（`src/project.rs:56-61` `configured_assets_dir`，编辑器资产服务器/索引读的就是配置目录），导出却写死 `<root>/assets`。
  后果：自定义目录的项目导出永远报 "no assets directory"；若残留旧 `assets/` 则把非索引目录的旧内容打进发布包且无报错。
  修复方向：`plan_export` 接受 manifest 解析出的 assets 目录（`ProjectRoot::assets_folder()`）。
  （2026-10-26 T07-T1 修复：`plan_export` 内部读 `ProjectManifest::assets_dir()`（签名不变、调用方零改动），staged 目录名跟随配置。提交 `ef353c57`。）

- [ ] **R11，Transform 的 Inspector面板中， Scale带W通道，Rotation不是欧拉角。希望Scale，Position 以XYZ 三通道展示。Rotation 以欧拉角形式展示，不要用四元数**
- [ ] **R12，场景渲染模式中的主光源和LocalLight(point,spot) 灯光的投影 开关没有效果，检查一下原因 并修复**
- [ ] **R13, 在ViewPort 窗口 使用鼠标右键旋转，体感有延迟，不跟手，体验上就会感觉操作不流畅** 
- [ ] **R14, 在ViewPort 窗口，选中物体，切换到旋转模式时，三个旋转轴的操作是反向的，不是所见即所得** 
---

## 🟡 中等（37 条）

### 场景核心 / 撤销 / 视口交互（6）

- [x] **Y1. 一批自推命令的操作符默认 `allows_undo=true`，每次动作产生两条撤销记录**
  `src/entity_ops.rs:2632-2810`（全部 `entity.add.*`）、`src/transform_ops.rs:121-380`（reset×3 / rotate90×6 / nudge×6）、`src/lib.rs:2835`（`spawn_undoable` 的 5+1 个调用点）、`src/entity_ops.rs:2568-2579`（`entity.paste_components` 漏了兄弟 op `entity.paste:2546` 显式的 `allows_undo=false`）。
  问题：op 内部已 `push_executed(SpawnEntity)`，用户面派发（`core_extension.rs:57-59`、`api_internal/lib.rs:726-732`、`boot_ops.rs:612-614`）又带 `creates_history_entry: true`，框架再补一条快照条目——违反 `operator.rs:661-688` "二选一"约定；Add Entity picker 入口（`lib.rs:2824`）只有一条，行为不一致。
  修复方向：这批 op 显式 `allows_undo = false`（或删自推统一走框架）。
  > 已修复 6df9ac89（T03-T2）：21 个 entity.add.*、transform 15 个、paste_components、component.add/remove（N1 延伸）及新发现的 brush 面板 4 个 op 全部显式 `allows_undo=false`；duplicate/toggle_visibility/place_gltf 等模式 B op 未动，registry 清单测试防回归（guards record_counts 全绿 + 真机三链）。

- [x] **Y2. Outliner 右键菜单 Duplicate 完全不产生撤销记录**
  `src/hierarchy.rs:2423-2427`（`"hierarchy.duplicate"` 事件路径调 `duplicate_selected`，自身不 push 历史）；对照 Ctrl+D 走 `entity.duplicate` 有框架条目。
  后果：右键复制后 Ctrl+Z 撤的是上一个不相关操作，复制品永久无法撤销。
  修复方向：右键菜单改派发 `entity.duplicate` 操作符，或函数内补快照对。
  > 已修复 6df9ac89（T03-T2）：右键菜单改派发 `entity.duplicate`（creates_history_entry:true，与 Ctrl+D 同路径）。真机链 2：右键 Duplicate → undo_len 恰 +1 → 一次 undo 复制品消失。

- [ ] **Y3. 对齐参考线吸附写 Transform 与拖拽更新系统无执行顺序约束**
  `src/alignment_guides.rs:374-383`（`draw_alignment_guides` 在 `Update` 直改被拖实体 Transform）；与 `modal_transform.rs:87-97` 拖拽链、`gizmos.rs:172-187` 无任何 `.after()`。
  后果：同帧读写同一 Transform 顺序不保证，吸附时灵时不灵、拖拽抖动。
  修复方向：显式 `.after` 拖拽更新，或拆独立系统排在拖拽后、渲染前。

- [x] **Y4. 拖入 prefab 实例的 unpack 手势一次产生两条撤销记录，undo 中间态不干净**
  `src/hierarchy.rs:1941-1961`：`prefab.unpack_child`（`creates_history_entry: true`）+ 再推 `ReparentEntity`；undo 先把已 unpack 实体按旧 location 挂回子树（此时已非 inherited，`sync_hierarchy_to_ast_at` 写回语义可疑），再弹 unpack。
  修复方向：合并为一个 `CommandGroup`，unpack 的 operator 调用改 `creates_history_entry: false`。
  > 已修复 6df9ac89（T03-T2）：ECS reparent 移进 `prefab.unpack_child` op 执行体（执行不 push），层级处只留一次快照派发 → 单条；同时 unpack_child 收敛为单写路径（AST 节点本体 move+strip PrefabEntityId，不再留副本），文档中 unpack 子项恰一个。真机链 3：undo 一次文档逐字节回滚，redo 恢复。

- [ ] **Y5. `handle_gizmo_hover` 读 `ActiveViewport` 却未声明排在 `update_active_viewport` 之后**
  `src/gizmos.rs:172-181`（只 `.in_set(EditorInteractionSystems)`，无 `.after`）；契约仅靠 `lib.rs:420/427` 插件注册顺序兑现（`viewport.rs:895-897` 注释断言该契约）；对照 `snapping.rs:21`、`viewport.rs:247` 都显式写了 `.after`。
  后果：插件顺序一变，光标跨视口那一帧会投影错相机，产生幻影 `hovered_axis`，可能据此在错误视口抓起 gizmo。
  修复方向：补 `.after(update_active_viewport)`。

- [ ] **Y6. 坐标轴指示器标签混用物理/逻辑像素，非 100% UI 缩放下错位**
  `src/viewport_overlays.rs:1014-1022`：`ComputedNode::size()`（物理 px）除以 `logical_viewport_size` 得物理 px 结果，却写进逻辑 px 空间的 `Val::Px`；同文件 `fps_overlay::keep_overlay_on_the_viewport:321-323` 和 `ViewportRemap::new` 都正确乘了 `inverse_scale_factor`。
  后果：DPI 缩放 ≠1 或 Ctrl+=/Ctrl+- 缩放 UI 时，XYZ 标签按缩放倍数偏离尖端。附带 `:983-985` 正交视图下直接 `continue`，指示器悬停在旧透视姿态。
  修复方向：`ui_pos` 乘 `computed.inverse_scale_factor()` 再写 `Val::Px`；正交分支至少隐藏。

### 场景 IO / 项目 / 导出（3）

- [x] **Y7. 导出 staging 守卫在 Windows 上可被大小写变体绕过**
  `crates/jackdaw_project_build/src/export.rs:246-251`（`Path::starts_with` 逐组件字节比较，大小写敏感；NTFS 大小写不敏感）。
  后果：`jd export --out c:\game\assets`（项目实际 `C:\Game`）守卫放行，`dist.exists()` 命中真实目录后 `remove_dir_all` 删掉真正的 assets/（仅 CLI `--out` 暴露；编辑器内 `out=None` 不受影响）。
  修复方向：Windows 上按组件做不区分大小写比较，或两侧 canonicalize 后再比。
  （2026-10-26 T07-T1 修复：护栏改 `path_contains` 组件级 `eq_ignore_ascii_case` 比较（Windows/非 Windows cfg 分开实现），大小写变体不再绕过；红证=旧码下变体被放行且真删了 assets 源（os error 3 日志实锤）。提交 `ef353c57`。）

- [x] **Y8. `file.rename` 不处理正在打开的场景/prefab 标签页**
  `src/project_window.rs:2190-2208`：只更新 `ProjectWindowState`，不 retarget `Scenes` 里该 tab 的 `path`（对照 `file_ops.rs:564-570` convert_document 有守卫）。
  后果：重命名已打开场景后 Ctrl+S 仍按旧路径写盘——旧文件"复活"，两份内容分叉。
  修复方向：命中任一 tab 路径时拒绝（同 convert），或对匹配 tab 一并 retarget。
  > 已修复 6ba0ce4b（T05-T1）：`reference_rewrite::follow_a_move` retarget `Scenes.tabs[].path`/prefab cache/`DefinitionAssetEdit.path`，干净 tab 重算 `saved_doc_hash` 保持干净、脏 tab 保持脏，journal 路径同步重写（guards: renaming_an_open_clean_scene_retargets_its_tab / a_dirty_tab_journals_under_the_renamed_path / renaming_a_referenced_material_under_a_dirty_tab_keeps_it_dirty_and_in_step）。
  > 2026-10-28 注记（A3+A4 任务）：T05-T1 修复在 **macOS 从未生效过**——tab 持 canonical 路径（`/private/var`）而 `retarget_tabs` 对已移走的旧路径 canonicalize 失败回落原始拼写，比较永不相等（Y8 症状在 Mac 静默存活，reference_rewrite ×3 确定性红）。f7f57ab7 以 `canonical_of_moved`（最深存在祖先 canonical 化拼尾、双侧同 resolver）补齐，保持 [x]。

- [x] **Y9. `project.json` / `settings.json` 非原子写 + 损坏后被默认值静默覆盖**
  `src/project.rs:311`、`src/project_settings.rs:95`（裸 `std::fs::write`）；触发点 `src/scene_io/save.rs:380`（每次保存场景）与 `native_dialog.rs:255`（每次选目录）。损坏后 `load_project_config` 返回 None，`project_select.rs:524-525` 走 `create_default_project` 直接覆盖。
  后果：崩溃/断电留半截 JSON，下次启动布局、last_open_tabs 无提示全丢。
  修复方向：改用仓内现成 `write_atomic`，损坏时先备份再重建。
  > 已修复 160893e6（T04-T1）：save_project_config/create_default_project/project_settings 全部走 write_atomic；损坏的 project.json 先 rename 为 `.corrupt-<ts>` 再重建，状态栏告知备份路径（guards: a_damaged_project_json_is_backed_up_before_the_default_replaces_it）。

### Inspector / UI 框架（6）

- [ ] **Y10. 持久化恢复的 DockTree 无环校验，坏文件可致栈溢出崩溃**
  `crates/jackdaw_panels/src/tree.rs:335-345, 424-431`（`leaves_under_inner`/`dfs_into`/`subtree_contains`/`reconcile_at` 均无环假设递归）；来源 `workspace.rs:135-175` 直接 `persist.tree.clone()`。附带：`next_tab_id=u64::MAX` 时 `fresh_tab_id` 永远返回同一 TabId。
  后果：手改/损坏的 project 文件造成 `Split{a:1,b:1}` 或环 → 无限递归崩溃。
  修复方向：反序列化后做一次可达性+无环校验（从 root DFS 限深），不过则回默认布局。

- [ ] **Y11. 自定义属性数值字段解析失败静默归零，且无"值未变"守卫**
  `src/inspector/custom_props_display.rs:717-719`（`text.parse().unwrap_or(0)` / `unwrap_or(0.0)`）、`:658-675`（`apply_custom_property_with_undo` 不比较新旧值；主 inspector 的 `field_edit_commit` 有守卫 `src/commands.rs:217`）。
  后果：非法输入/清空失焦后属性被静默写成 0；焦点进出未修改也 mint undo + 标脏。
  修复方向：parse 失败放弃本次 commit；apply 前比较旧值。

- [ ] **Y12. u64 字段经 `as i64` 饱和截断，编辑会写回错误值**
  `src/inspector/reflect_fields.rs:2000-2004`、`:2969-2973`（`value.round() as i64` 同类）。
  问题：代码支持 u64 行（749-860），但 `u64 > i64::MAX` 被饱和钳到 `i64::MAX`，显示错误值，用户一动就当 final 提交——静默改写实体数据。`crates/jackdaw_feathers/src/text_edit.rs:1154-1167` 刚修过同类（i32→i64）并配了测试，此处是漏网镜像。
  修复方向：值域超 i64 的整数字段走 `F64` 或校验后再转。

- [ ] **Y13. 通知存续期间每帧 `String::clone` + Text 改写，触发无谓 relayout**
  `src/status_bar.rs:365-374`：notice 分支在 change-detection 早退守卫（390-405）之前，激活的 6 秒内每帧无条件写 `Text`（其它行 359、547 都做了比较，唯独这里漏了）。
  修复方向：`if text.0 != notice.text { ... }`。

- [ ] **Y14. `LastPressedPanel` 关闭面板后不清除，键位可用性落在幽灵面板上**
  `src/panel_focus.rs:74-83` + `src/dock_ops.rs:47-57`：`dock.close_tab` 不清理；`focused_panel()` 永远回落到已关闭的 window id，`is_focused` 型 operator 的 `is_available` / `can_toggle_maximize` 拿到树里不存在的"焦点面板"。
  修复方向：close 后若 last_pressed 即该 window_id 则清掉。

- [ ] **Y15. 折叠态按组件短名做 key，同名组件共享折叠状态**
  `src/inspector/mod.rs:43-50`（`InspectorCollapseState(HashMap<String, bool>)`）+ `src/inspector/component_display.rs:1173`（key 用 short_path 而非 type_path）。
  后果：不同模块的同名组件（如游戏 crate 与扩展 crate 各一个 `Health`）展开其一另一个跟着开。
  修复方向：key 换 type_path（或 type_path + name）。

### Terrain（5）

- [ ] **Y16. Channels/Detail 笔刷每帧全网格 gather+scatter**
  `src/terrain/paint.rs:654,693`（Channels）与 `:861,908`（Detail）：每帧 `channel_values` 整张读出 + `set_channel_values` 整张写回（逐 cell region 查找）。对照：高度走 `brush_heights`（rect 原地）、control/tint 走 `control_rect_mut`/`tint_rect_mut`。
  后果：4096 地形一笔 mask 每帧 1600 万次查找，必然卡顿。
  修复方向：仿 `ControlGrid` 为 channel 引入 rect 作用域的 gather/写回。

- [ ] **Y17. scatter/detail count 的 f32→u32 饱和转换可致小时级挂死**
  `crates/jackdaw_terrain/src/scatter.rs:180-181`、`detail.rs:322-324`（`as u32` 饱和）、`stochastic_round` 的 `wanted.floor() as u32` 同型。
  问题：`density<=0` 有防护、巨大有限值/inf 没有；应用层 `MAX_SCATTER_INSTANCES`（scatter.rs:1285-1300）只挡 UI，kernel 是公开库 API。
  后果：脚本调 `density=1e30` → `u32::MAX` 次循环 / `min_spacing==0` 时 ~100GB 分配。
  修复方向：kernel 内对 `expected` 设上限或 `u32::try_from(...).unwrap_or(0)`。

- [ ] **Y18. 每次起笔/收笔全地形拷贝**
  `src/terrain/sculpt.rs:294,307`（起笔快照 `heights().to_vec()` 全地形 ~67MB@4096；收笔 `store.heights()` 全网格 gather 只为读一个 rect）；`paint.rs:721,730,808,815` 同型（control/tint 收笔全量 `control()`/`tint()`）。
  后果：单次点击 5-20ms 卡顿。
  修复方向：收笔按 rect 逐 region 读；快照延迟到首帧 rect 前值采集。

- [ ] **Y19. 撤销/重做一律 `rebuild_all`**
  `src/terrain/sculpt.rs:129-131`（`SetTerrainHeights::restore`）、`paint.rs:220-222`（`SetTerrainChannel::apply`）无条件 `dirty.rebuild_all = true`；正向笔刷只 mark 受影响 chunk（sculpt.rs:340-344），patch 的 rect 已知（`HeightPatch::Rect`）。
  后果：大地形上每次 Ctrl+Z 全 clipmap 层重网格化，卡一帧。
  修复方向：按 rect 折算脏 chunk。

- [ ] **Y20. "fell outside the terrain" 提示与实际行为相反**
  `src/terrain/scatter.rs:758-762`：`add_placement` 的 None 只在 region 总量达上限时返回；落在地形外的 placement 会成功存储并分配新地面（见 R6），达上限被拒的反被报为 "fell outside"。
  修复方向：import/stamp 前做地形范围检查；达上限时报 "region cap"。

### 几何 / CSG / 拾取（7）

- [ ] **Y21. Knife 跨面弦搜索接受 `seg_t > 1` 的越界交点**
  `src/brush/knife_mode.rs:1970-1976`：嵌套 if 意图"≈1 可接受、越界拒绝"，但 `seg_t > 1.0+1e-4` 时外层为真、内层为假直接放行 → `find_outgoing_face_and_edge` 把交点在段外的边 `split_edge`，`split_face(va, inter)` 切出错误的面。
  修复方向：内层改 `if seg_t >= 1.0 + 1e-4 { continue; }`（或只保留下界判断，去掉外层）。

- [ ] **Y22. CSG Intersect 的退化面兜底仍是凸重建**
  `src/draw_brush/csg_ops.rs:710,731-735`：kernel 交结果只要有一个面被判退化就整体回退 `compute_brush_topology`（凸范式）——正是 subtract 注释点名要避开的路径；且 `faces` 与 `topology.polygons` 平行数组不变量在此分支被破坏。
  修复方向：退化面直接丢面并同步删 topology 中对应 polygon，保持平行数组。

- [ ] **Y23. CSG 碎片生成只补偿父节点平移，忽略旋转/缩放**
  `src/draw_brush/csg_ops.rs:44-49`：`Transform::from_translation(transform.translation - *parent_translation)`；碎片是世界空间数据，挂回同父节点时 `T_p ∘ (centroid − t_p) ≠ centroid`。`csg_subtract_selected_impl`、`csg_intersect_selected_impl`、`subtract_drawn_brush` 三处同病（新实体经 `entity_ops.rs:1672` 挂同父）。
  修复方向：用父 GlobalTransform 的仿射逆把碎片整体变换到父局部空间。

- [ ] **Y24. 面法线一律「旋转×法线」变换，非均匀缩放下错误（多处）**
  `src/brush/knife_mode.rs:1131-1132,1240-1241`、`src/brush_drag_ops.rs:462-463,487-488`、`crates/jackdaw_geometry/src/lib.rs:381-406`（`brush_planes_to_world`）。
  问题：非均匀缩放下正确法线是 `(R·S)⁻ᵀ·n`，`R·n` 方向不对。另 `compute_brush_drag_offset`（interaction.rs:161）Free 模式少除缩放，跨笔刷群组拖拽（`broadcast_drag_to_captures`）两笔刷缩放不同时位移量错。
  后果：knife 点击落点不在真实面平面（commit 报 "no live face contains click position"）、face drag 沿错误轴推拉。
  修复方向：统一用 `Affine3A` 的 inverse-transpose 变换面法线。

- [ ] **Y25. 吸附格距用 `translate_increment`，可见网格画的是 `grid_size()`，二者错配**
  `src/draw_brush/plane_math.rs:104`（`snap_to_plane_grid`）、`src/brush/knife_mode.rs:402-415`、`src/draw_brush/interaction.rs:259-266`；对照可见网格 `draw_plane_grid`（plane_math.rs:54）与 face_grid 用 `grid_size()`（尊重 `grid_increment`）。
  后果：用户把网格调成 1.5m 后，画笔刷永远吸不到可见网格点上。
  修复方向：这些吸附点统一改用 `grid_size()`。

- [ ] **Y26. 顶点/边拾取无深度过滤、阈值写死 20px**
  `src/brush_drag_ops.rs:909,1221`、`src/draw_brush/interaction.rs:621,658`：仅按屏幕距离取最近，无视遮挡，可能抓到投影重合的背面顶点/边；20 未按 HiDPI 换算（knife_mode 已有 `DEPTH_TIE_EPSILON` 深度排序 + `window_pixels_to_target_pixels`，此路未同步）。
  修复方向：复用 knife 的深度优先 + 屏距 tie-break 与像素换算。

- [ ] **Y27. `face_from_ray` 命中判定只做凸半空间测试**
  `crates/jackdaw_pick/src/lib.rs:63`（`point_inside_all_planes`，不对命中面 ring 做 `point_in_polygon`）。
  后果：CSG 现已"默认凹"（带孔 annulus 面），射线穿过窗洞时在洞口平面误报命中。当前仓内无生产调用方（仅自测试），属 API 级隐患。
  修复方向：补一次对候选面 ring 的 `point_in_polygon`（同 crate 已有实现）。

### BSN / 序列化（5）

- [ ] **Y28. BSN 解析器递归无深度上限，深嵌套不受信 `.bsn` 可栈溢出**
  `crates/jackdaw_bsn/src/syntax/parse.rs:126-213`（`BsnValue::parse`→`parse_values`→`BsnValue::parse`）、`parse/mod.rs:77-87`（`spawn_bsn` Children 递归）、`syntax/lex.rs:263-278`（`lex_block_comment` 嵌套）。
  问题：`MAX_AST_DEPTH=256` 只护住 parse 之后的遍历，解析本身没有；拖入几万个 `[` 或嵌套 `/*` 的 .bsn 即 panic 编辑器。
  修复方向：`ParseStream`/`parse_bsn` 入口带深度计数，超 `MAX_AST_DEPTH` 返回 `ParseError`。

- [ ] **Y29. `int_to_reflect` 用 `as` 窄化，越界整数静默回绕**
  `crates/jackdaw_bsn/src/apply.rs:1222-1245`（`i as u8` 等）。
  后果：`300` 写 `u8` 变 `44`、`-5` 写 `u64` 变巨数；NonZero 分支特意用 try_from 拒绝，普通整型却静默回绕，行为不一致且是数据损坏。
  修复方向：统一 `try_from`，失败 warn + 拒绝该字段。

- [ ] **Y30. 文档遍历缺少环保护，与同 crate 其它被 cap 的遍历不一致**
  `crates/jackdaw_bsn/src/document/query.rs:264-274`（`descendants_of` 显式栈无 visited）、`:220-235`（`find_parent_in_subtree` 无界递归）、`:119-147`（`node_by_stable_id`）、`:287-295`（`ancestor_with_component`）。
  问题：`mutate.rs:430` 测试明确"环可来自剪贴板"，`deep_clone`/`clone_subtree_into`/`emit_patches`/`spawn_ast_node` 都有 cap，但 resolver 走的这几个遍历没有。
  修复方向：补 `MAX_AST_DEPTH` 或 visited 集，与 `despawn_recursive_to_depth` 对齐。

- [x] **Y31. 内嵌资产加载时 `local: None`，同文档资产间 `#Name` 互相引用静默丢失**
  `crates/jackdaw_bsn/src/catalog.rs:58-61, 315-319`：逐条加载内嵌资产时 `local` 恒为 None，`BsnSceneAssets` 要等全部条目加载完才发布（163-173）。
  后果：内嵌材质引用同文档内嵌纹理时 `'#'` 前缀分支 warn 后回落默认 handle——save→load 往返丢引用（实体组件引用不受影响，仅资产→资产方向）。
  修复方向：两阶段加载（先收集全部条目建名字→handle 暂存表再逐条转换），或占位 handle 回填。
  > 已修复 abf00a31（T05-T2）：`load_bsn_assets` 两阶段（第一遍 no-assets 站起各条目收集 `#name`→handle 暂存表，第二遍带 local 重读并 insert 回填同 handle）；`load_asset_value` 单条目路径传当前 BsnSceneAssets 兜底（lib: an_embedded_reference_survives_the_two_phase_load 断言 outer.inner == inner.handle）。

- [ ] **Y32. `bsn_value_eq` 对 Map 是 O(n²)、struct 字段比较 O(n·m)，位于 prefab 热路径**
  `crates/jackdaw_bsn/src/delta.rs:47-53, 60-69`；调用方 `merge_descendant_overrides`、`sparsify_node_against_baseline`、`shallow_diff` 每次 prefab resolve/sparsify/override 判定都对每个组件调用。
  后果：`CustomProperties` 大 map × 多实例时开销二次方放大。
  修复方向：map 按 key 排序后线性归并比较（发射端 `sorted_map_entries` 已有同款排序）。

### 运行时 / 远程 / PIE / 键位（5）

- [ ] **Y33. 游戏 BRP 加 `Access-Control-Allow-Origin: *`，任意网页可读写运行中的游戏**
  `crates/jackdaw_remote/src/lib.rs:118-126`：游戏端 BRP（默认 127.0.0.1:15702，含 bevy 内建写方法 `bevy/insert`/`mutate_component`/`spawn`/`destroy`）显式放行所有跨域来源；同仓 `src/remote/server.rs:160` 编辑器端明确写了相反结论却不在游戏端执行。
  修复方向：去掉 CORS 头或仅对已知编辑器 origin 放行。

- [x] **Y34. 发送 `ControlEvent::Stop` 后立即 `kill()`，"优雅停止"契约实际不成立**
  `src/pie.rs:951-956`（`stop_instance`）、`:1024-1034`（`handle_stop`）。
  问题：ipc 消息异步，游戏至少一帧才能处理 Stop→`AppExit::Success`（`crates/jackdaw_runtime/src/pie.rs:314`），紧接着 TerminateProcess/SIGKILL 使其永远没机会跑；游戏端整套优雅退出机制在编辑器 Stop/Reload 路径上是死代码。
  修复方向：发 Stop 后带超时轮询 `try_wait`（如 2s），超时才 kill。
  （2026-10-26 T06-T2 修复：`GRACEFUL_STOP_DEADLINE` 2s + `ChildStage::Live.stop_deadline`，`advance_child` 到期才 kill 恰一次；Reload 走 `force_stop_all` 保留立即 kill 并注明；单测 5 例 + 真机（小场景 0.3s 优雅退出、500 实体 2.2s 走 deadline 硬上限）。提交 `Restore the edit state on stop and stop the game gracefully`。）

- [ ] **Y35. BRP 响应 `Content-Length` 未设上限，可直接打爆内存**
  `src/remote/brp.rs:147-149`：`body.resize(length, 0)` 先 resize 再读；endpoint 可配置指向任意主机。
  后果：恶意/出错服务器回 `Content-Length: 10^15` → TB 级零初始化分配 → OOM abort。
  修复方向：body 加上限（如 256 MiB），超限报错。

- [ ] **Y36. 旧版键位文件把全部默认绑定一起落盘，默认键位变更永远无法触达老用户**
  `src/keybinds.rs:105-123`（`save_keybinds` 存 registry 全集 ~100 条；`load_keybinds` 逐条覆盖默认）。新 `UserKeymap` 路径（`keybind_settings.rs`）只存 diff 并有测试 `saving_writes_only_the_operators_that_changed` 防回归——旧路径恰是它防的反模式。
  修复方向：保存时按 `KeybindRegistry::default()` 求差，只写非默认项。

- [ ] **Y37. PIE 每帧对全场实体做全量反射 JSON 序列化**
  `crates/jackdaw_runtime/src/pie.rs:151-281`（`stream_state`）：首帧之后每帧仍对所有 `With<Transform>` 实体序列化每个 reflectable 组件再 diff（diff 只省发送，省不掉序列化），外加 `last_sent` 全量 HashMap 重建。
  后果：上千实体时游戏主线程每帧固定大额 CPU/分配。
  修复方向：用 change-tick 只重序列化有变化组件，或无结构变化时降频。

---

## ⚪ 轻微 / 优化（28 条）

### 视口 / 渲染（4）

- [ ] **W1. 选中实体的包围盒每帧全量收集网格顶点 + 求凸包，无缓存**
  `src/viewport_overlays.rs:209-244`：非 brush 网格选中即必画（不受 show_bounding_boxes 开关控制），每帧对全部后代网格 transform_point 全顶点遍历 + `Vec` 分配；ConvexHull 模式每帧对几十万顶点重建凸包。brush 路径已有 `BrushMeshCache`，非 brush 无对应物。
  修复方向：按（实体, mesh 资产 id, 变换指纹）缓存，资产或变换变更时失效。

- [ ] **W2. 多个 UI 根时"畸形态选根"口径不一致（archetype 序 vs 实体序）**
  `src/viewport_2d.rs:790-793`（`size_targets_to_reference` 用 `roots.iter().next()`）vs `:1119-1122`（`sync_rulers` 用 `min_by_key`，注释称跨系统一致）；`ui_palette::ui_scene_root:316-326`、`preview_context.rs:712` 都取最小实体。文档含 2+ 根时画布 reference size 与标尺/参考线可能各按不同根测量。`update_viewport_2d_title:1980` 同病（仅标题，影响小）。
  修复方向：统一走 `ui_palette::ui_scene_root`（或都 `min_by_key`）。

- [ ] **W3. 着色派生材质缓存永不淘汰，长会话无界增长**
  `src/view_modes.rs:152,257-262`：Unlit/LightingOnly 每遇新源材质生成派生材质永久入缓存；源材质卸载后派生句柄仍钉住 GPU 材质。
  修复方向：切回 Lit 且无人引用时清理，或弱引用淘汰。

- [ ] **W4. 截图观察者不触发时采集相机滞留，编辑器 gizmo 永久熄灭**
  `src/camera_capture.rs:144-164`：`PendingCapture` 归零后相机消失完全依赖 `ScreenshotCaptured` 到达；渲染端异常时不来，带 `KeepsGizmosOut` 的相机常驻，`keep_gizmos_out_of_recordings:39-49` 把 gizmo 组永远压 disabled。
  修复方向：超时兜底（SETTLE_FRAMES + N 帧强制 despawn 并告警）。

### 场景核心（2）

- [ ] **W5. 粘贴/复制大子树时命名去重 O(n²)**
  `src/entity_ops.rs:1196-1217`（`assign_unique_entity_names`）+ `:1249-1278`（`claim_free_name` 每节点全量扫 `taken` 含逐名 parse）。
  后果：几千节点子树复制/粘贴可感知卡顿（一次性）。
  修复方向：建 `base → 当前最大序号` HashMap 一次遍历。

- [ ] **W6. `copy_components` / `paste_components` 名实不符**
  `src/entity_ops.rs:1616-1621, 2023-2031`：Ctrl+Shift+C/V 实为整实体子树复制/粘贴（粘贴到场景根），与 `:2326` 注释 "whole-component clipboard" 及操作符标签 "Copy Components" 矛盾，没有组件级剪贴板。
  修复方向：改名或真正实现组件级语义。

### 场景 IO / 项目（6）

- [x] **W7. 资产索引 `gone` 检测 O(n·m)，每次保存都全量跑在主线程**
  `src/asset_index.rs:540-545`：`found.iter().any(...)` 全交叉 PathBuf 比较，万级资产约 1 亿次比较/次（任何资产一保存就触发一次 walk）。
  修复方向：`found` 的 relative 路径收进 HashSet 再做差集。
  > 已修复 abf00a31（T05-T2）：`apply_walk` 的 gone 检测把 walk 发现的 relative 路径先收 HashSet 再 `contains` 差集（asset_index.rs apply_walk，O(n·m)→O(n)）。

- [x] **W8. OS 拖放不检查来源是否已在项目内，拖自家文件会复制出副本**
  `src/asset_ingest.rs:143-150`：对每个 `DroppedFile` 一律导入 assets 根目录，不查 `path` 是否已在 `assets_dir` 下。
  后果：从资源管理器把项目内文件拖回窗口得到 `xxx-1.ext` 重复文件。
  修复方向：`path.starts_with(&assets_dir)` 则跳过复制直接放置。
  > 已修复 6ba0ce4b（T05-T1）：`handle_file_drops` 对 canonicalize 后仍在 assets 目录内的 drop 跳过导入、直接 select_path（guards: dropping_a_file_already_in_the_assets_copies_nothing）。

- [x] **W9. JSN→BSN 转换是唯一不走 `write_atomic` 的场景写盘路径**
  `src/jsn_to_bsn.rs:300-301`：裸 `fs::write`，中途崩溃留截断 .bsn；写入内容不带版本 stamp。
  修复方向：改 `write_atomic` 并补 `stamp::with_stamp`。
  > 已修复 160893e6（T04-T1）：commit_conversion 与 convert_catalog_file 改 write_atomic；场景 .bsn 落盘补 with_stamp（catalog 是资产文档不加场景 stamp，维持原语义）（guards: a_failed_conversion_keeps_the_old_bsn_and_the_source_in_place / a_committed_conversion_carries_the_version_stamp）。

- [x] **W10. 迁移重写文档用全文替换而非按 AST 写回**
  `src/asset_migration.rs:316-321`：`format!("{field}: \"{reference}\"")` + `String::replace`，同文档另一类型的同值同名字段（如展示文案 `board: "slate"`）会被一起改写。
  修复方向：解析 AST 后按节点改写再 emit。
  > 已修复 6ba0ce4b（T05-T1）：迁移的 `rewrite_documents` 改走新 `src/reference_rewrite.rs`（AST 值替换，类型限定字段才动，非资产 String 恰等引用串不误改）；迁移既有 13 用例全绿含幂等（guards: renaming_a_referenced_file_rewrites_its_referrers_and_nothing_else 的 note 字段断言钉死误伤面）。

- [x] **W11. Windows 上无法做仅大小写的重命名**
  `src/project_window.rs:2190`：`Rat.bsn`→`rat.bsn` 时 `target.exists()` 因文件系统不区分大小写误判"已被占用"。
  修复方向：目标与源仅大小写不同时放行（两步 rename 经临时名）。
  > 已修复 6ba0ce4b（T05-T1）：canonicalize 相等且拼写不同判为仅大小写，经 `.name.case-<pid>-<n>` 中转名两步 rename，第二步失败回滚第一步（guards: a_rename_that_differs_only_in_case_lands）。

- [x] **W12. 机器路径检测漏掉盘符相对拼写**
  `src/scene_io/asset_fields.rs:124-126`：`C:props/x.bsn`（无分隔符盘符相对路径）不被判机器路径，保存写进场景文件后在别的机器解析到意外位置。
  修复方向：出现 `<alpha>:` 前缀即视为机器路径。
  > 已修复 abf00a31（T05-T2）：`names_one_machine` 收紧为「单字母盘符 + `:` 即判」（不再要求后随分隔符）；保存拒绝与 audit 的 MachinePath 判定同步（lib: a_drive_relative_spelling_is_a_machine_path_without_a_separator 断言 C:props/x.bsn 被报且 refusal 含该串）。

### Inspector / UI（5）

- [x] **W13. `notify_warn` 与 `notify_info` 完全同实现，警告色永远不可达**
  `src/status_bar.rs:127-129`：`notify(world, text, false)` 与 info 一致，`TEXT_WARNING` 分支（371）死代码；调用方（如 `ui_layout_presets.rs:333`）本意警告呈现实际普通 info 色。
  修复方向：`StatusNotice` 增加 warning 档或 `notify` 区分三级。
  > 已修复 d213f627（T08-T2）：`StatusNotice` 改持 `NoticeLevel::{Info,Warning,Error}` 三档（渲染色 secondary/warning/error），`notify_info/notify_warn/notify_error` 各达其档（主 crate 单测 notices_carry_their_level）；本任务所有保存失败提示走真正的警告档。

- [ ] **W14. 每帧为每个文本字段做一次 String 分配**
  `src/inspector/mod.rs:222-262`（`refresh_name_field`）、`crates/jackdaw_feathers/src/text_edit.rs:1187-1210`（`sync_text_edit_values` 每帧 `editable_text_string` 一次堆分配只为相等性比较）。
  修复方向：先比较 `editable.value()`（Cow）再决定 to_string。

- [ ] **W15. `sync_leaf_visuals` O(tabs × areas) 双重全表扫描**
  `crates/jackdaw_panels/src/reconcile.rs:655-731`：外层按 area、内层遍历全部 tab/icon/content 三遍；可按 `tab_to_area` 反向分组。
  修复方向：建 `HashMap<Entity, Vec<...>>` 一次分组 + `Changed` 过滤。

- [ ] **W16. 数值拖动每 tick 两次字符串格式化绕一圈**
  `src/ui_stage.rs:2698-2731`（f64 版）、`:2736-2769`（i64 版）：非 final tick `format!("{value}")` → `apply_field_value_live` → `parse_to_json_value` 再 parse 回数字；`is_final` 分支（2764）已直接用 `json!(value)`。
  修复方向：非 final 分支直接传 `json!(value)`。

- [x] **W17. `Val`/`UiRect` 编辑路径不含 PIE Live 预览 tick 的资源守卫**
  `src/inspector/reflect_fields.rs:643-655`（`commit_val_to_field`）：非 final 直接 `field_edit_preview`，没像 `apply_field_value_live`（2675）先拦 `is_resource_entity`；对照 `val_field.rs:370-399`。
  后果：资源卡带 Val 字段且选中态特殊时 preview 误写 selection 文档管线。
  修复方向：`commit_val_to_field` 开头补 `is_resource_entity` 分流。
  （2026-10-26 T06-T2 修复：`val_field.rs::commit_val_to_field` 补资源分流（tick→`resource_field_preview`、commit→`resource_field_commit`，照 `apply_field_value_live` 形状）；实测旧路径的真实缺陷是资源 Val 字段 tick 连资源自身都不写（stale 守卫挡住了跨目标写盘分支）——红 0/2 panic、绿 2/2。提交同 Y34。）

### Terrain（1）

- [ ] **W18. 导入 yaw 只减了地形 yaw，斜放地形不精确**
  `src/terrain/scatter.rs:750`：位置走全仿射逆变换精确，yaw 修正假设地形只有 Y 旋转；带 pitch/roll 的地形折算不精确（adopt 路径有 `is_rigid_with_uniform_scale` 提示，import 没有）。
  修复方向：同 adopt 给出告警或按完整旋转分解。

### 几何 / CSG（3）

- [ ] **W19. Cut 预览每帧全量跑 kernel，含 O(n²) 去重**
  `src/draw_brush/preview_mesh.rs:237-361` + `crates/jackdaw_csg/src/lib.rs:545-565`：拖拽深度时 cache key 每帧变，对每个 AABB 相交笔刷每帧 `brush_difference_split`；`dedup_positions` O(n²) 线性扫描、共面分组 O(三角数×组数)。
  修复方向：空间哈希/排序去重；预览只算受 cutter 影响的 face 子集或降帧。

- [ ] **W20. face drag 热路径 O(V) 线性查 key**
  `src/brush_drag_ops.rs:535-539`：每帧对每个被拖顶点 `vert_keys.iter().position(...)`；相邻 `compute_edge_snap_all` 等每帧每面分配 `Vec<Vec2>` 屏幕投影缓冲。
  修复方向：拖拽开始时建一次 `VertKey→usize` HashMap（`jackdaw_select` 已有同款 `vert_key_to_index`）。

- [ ] **W21. `subtract_brush` 对凹 cutter 数学上就是错的，且仍作为公共 API 导出**
  `crates/jackdaw_geometry/src/lib.rs:446-506`：逐 cutter 面半空间交割分裂，等价 `target − ∩(cutter 半空间)`（挖掉的是凸化区域），碎片最坏 O(2^面数)；当前 src 无实际调用（仅 `src/brush/csg.rs` 转发导出），属误导性死代码。
  修复方向：删除导出或 `#[doc(hidden)]`/deprecated，指向 `jackdaw_csg::brush_difference_split`。

### BSN / Prefab（3）

- [ ] **W22. `json_to_bsn_value` 把 JSON `null` 映射成空 List**
  `src/prefab/operators.rs:2593-2596`：`prefab.apply_to_source`/`bulk_apply_in_scene` 的 `value_json=null`（语义应为"清空/取默认"）被写成 `[]`，非列表字段被拒并 warn、列表字段被清空。
  修复方向：null 跳过写入或映射为"删除该 authored 字段"。

- [ ] **W23. 清除场景侧覆盖按顶层字段名整名匹配，点路径清不掉**
  `src/prefab/operators.rs:1854-1871`：`retain(|f| f.name != field_path)`，`field_path="scale.x"` 时顶层字段名是 `scale` 永不命中，旧覆盖残留（resolve 结果一致，仅文档留脏、下次保存前 `sparsify` 才收掉）。
  修复方向：先按 `.` 取首段再 retain。

- [ ] **W24. `show_file` 对同一路径连续两次 `read_asset_kind`**
  `src/inspector/file_card.rs:67,80`：每次都是完整读盘 + `asset_file_type` 全量 parse（header 解析整个文档只为嗅探类型）。
  修复方向：复用第一次结果；`asset_text_type` 已读 header，可先命中再决定全量 parse。

### 运行时 / 远程 / 杂项（4）

- [ ] **W25. 调试面板轮询不随面板关闭而停，且每请求一线程一连接**
  `src/remote/debug/mod.rs:32-92` + `src/remote/brp.rs:29-36`：连接期间恒定 0.25/0.5/1.0/1.5s 四频率 + entity_browser 0.5s 轮询，不看面板是否打开；`brp_request` 每次 `thread::spawn` + `Connection: close`，每秒 ~5-6 个线程生灭。
  修复方向：按面板可见性门控、复用连接或共享工作线程。

- [x] **W26. Job Object 三处 `assert!` 会把"启动失败"变成"编辑器崩溃"**
  `src/pie.rs:1970-2004`（`pie_windows::PIE_JOB`）：受限环境（AppContainer、部分 CI/沙箱不允许嵌套 job）下 `AssignProcessToJobObject` 失败 → 点 Play 直接 panic 整个编辑器。
  修复方向：失败 `warn!` 并继续降级为无 job 保护启动。
  （2026-10-26 T06-T2 修复：`PIE_JOB` 改 `LazyLock<Option<Job>>`（init 两处失败 warn+None），`assign_to_process` 失败 warn 继续；正常路径真机回归：kill 编辑器 → my-game.exe 随之死（job object 生效）。降级分支无法真机模拟受限环境，以代码结构（assert 全消）+ 审查覆盖，如实记档。提交同 Y34。）

- [ ] **W27. 旧键位链路对表外按键的序列化丢数据**
  `crates/jackdaw_commands/src/keybinds.rs:762-763, 842`：`key_display_name` 对表外键（小键盘/Intl/媒体键）返回 `"???"`，`key_from_display_name("???")` → None，保存重载后自定义绑定静默回退默认（仅 warn）。新 keymap 已有 `key_code_from_name` 防线，旧链路未对齐。
  修复方向：解析失败保留原绑定不覆盖，或统一走新 keymap。

- [ ] **W28. 远程 schema 缓存在主线程同步序列化+写盘**
  `src/remote/registry_fetch.rs:75-90`：`serde_json::to_string_pretty` 整个 Bevy 类型 schema（可达数 MB）+ `fs::write` 在 `Update` 系统里同步执行，连接建立瞬间卡一帧到几十毫秒。
  修复方向：挪到 `IoTaskPool`（同文件 server.rs 的 assets 已有先例）。

---

## 🤖 Agent 工作中新发现（非用户原始清单；2026-10-25 T03 undo 加固期间发现并经程序+QA 双确认，主控批准立项）

- [ ] **A1. brush.join 后异步 recenter 位移不入撤销记录**
  `src/draw_brush/mesh.rs:147`（`recenter_brush_origins`，早于 T03 全部工作、Bevy 0.20 升级提交 18aab519 已在）：join 保留笔刷后下一帧异步把笔刷 Transform 移到 hull 质心，该位移不在任何撤销命令组内——单次 undo 能复原双笔刷与几何，但保留笔刷的 translation 停在质心不回原位。BRP history:false 路径同样存在。
  修复方向：把 recenter 位移并入 join 的自推命令组，或撤销时以快照基线恢复 Transform。

- [ ] **A2. Kinematic 玩家推不动 Dynamic 体（T11 决策 1-A 语义边界，非缺陷；立账备将来）**
  `crates/jackdaw_scaffold/templates/game/src/lib.rs.template`（move_player，T11 引入）：模板玩家=Kinematic+MoveAndSlide 直写 Transform——sweep 停在目标 skin 宽度外、`LinearVelocity` 恒零，avian 接触约束既无重叠也无相对速度可解 → 玩家撞 FallingCube 如撞墙（**双机复现实证**：Windows dx=0.00、Mac dx=1.1e-07，`loop/t11t3-live/t11t3-c-*`/`t11t3-c-mac-*`）。机制链：`wgpu` 无关；`ContactConstraint::generate` 消费双方 `LinearVelocity`（solver/plugin.rs:713），`move_and_slide` 纯 shape-cast 数学不写任何 body 状态（move_and_slide.rs:483）。这是决策 1-A「不被推挤」取舍的另一面（「也不推挤别人」）。若将来要「推箱子」玩法：把 `output.projected_velocity` 写进 avian `LinearVelocity` + `CustomPositionIntegration`（avian 官方 character-controller 注记的 solver-visible 形态），或改 Dynamic+锁轴。T11 范围内不动引擎/模板——book `player-controller.md` 已补边界段（406d116b 之后）。⚪ 设计边界。

- [x] **A3. standalone 发货测试红：脚手架 [patch] 无条件注入本机 fork path（T10 血统潜伏缺陷，非 T11 引入）**（2026-10-28 T11-T3 QA Mac 迁移冷编首次暴露；主控批准立账）
  `crates/jackdaw_scaffold/src/lib.rs` `module_patch_lines`（T10-T3 引入）：工程含 physics 模块即无条件把 `BEVY_FORK`（编译期烘入的本机 fork 绝对路径）写进游戏 Cargo.toml 两段 `[patch]`——standalone 发货（无本机 fork 的机器）解析即红；且 `jackdaw_project_build/build.rs` 不监视 workspace `Cargo.toml`，fork 路径变更后 `BEVY_FORK` 停留旧值。Windows T10a 全绿系增量构建沿用无 fork 烘入的旧产物，**任何清洁重建都会红**（QA 亲证：Mac integration standalone 发货 1 红，隔离复跑与 T11 diff 零交集，`loop/reports/t11t3_qa_mac_integration*.log` + t11-final-qa.md）。
  修复方向：gate 在 `jackdaw_dev_checkout()`（仅开发 checkout 注入 fork patch）或 standalone 剥离 path patch；build.rs 补 `rerun-if-changed=Cargo.toml`。建议小任务立项（T10a「PASS+立项」同款先例）。
  > 2026-10-28 勾选：f7f57ab7 修复（`module_patch_lines`/`add_module_crates` 两处注入 gate 在 `jackdaw_dev_checkout()`+build.rs 补 workspace Cargo.toml 监视；红证 :132 panic→绿）；QA PASS a3a4-mac-baseline-qa.md（integration 5331/531）。主控裁定：shipped binary+physics 的两 bevy resolve 风险**维持既有降级路径**（产物 note 指引用户自建 fork；可分发 fork 形态超出本账，见 open-challenges fork ledger）。

- [x] **A4. Mac integration 环境基线红（迁移首基线；处置前该门按「无新增红」口径）**（2026-10-28 T11-T3 QA 建账；主控批准）
  Mac 首个全量 integration 基线：5331 跑 5323 过+8 红（EXIT=1 如实 FAIL 在档）。逐项诊断：1 项产品侧根源=A3（standalone 发货），其余为 macOS 环境族——/private/var TMPDIR 规范化路径断言 ×5、journal 5ms 预算在 APFS 实测 300-570ms、panels observer 竞态、合成键盘多字符（逐项清单见 `loop/reports/t11-final-qa.md`）——与 T11 三提交 diff 零交集，隔离复跑零 T11 引入。
  修复方向：路径断言 canonicalize 比较、平台预算校准、键位映射平台表。归「Mac 基线清理」账。
  > 2026-10-28 勾选：f7f57ab7 修复——深挖反转：7 红中 **5 项实为产品缺陷**（Y8 tab retarget 在 Mac 从未生效=canonical 比较形态／indexed_path 断链告警在 Mac 零警告／journal emit 被 autofs `/home` stat 拖到 70ms×N 次（5ms 预算未动，修后 0.62-1.0ms）／project_window observe 生命周期缺护航 11 处换 `observe_if_alive`），仅 #6 双侧 canonicalize（测试侧）+#9 `select_all_gesture` 平台键（helper）为环境侧；QA PASS a3a4-mac-baseline-qa.md，**Mac integration 基线全绿 5331/5331**（T10a 5303/5303 后新基线）。⚪ 遗留：`canonical_prefab_path` FS 行走通用性能面；lod_group flaky 首见观察（TRY2 过，零复发数据，暂不立账）。

- [ ] **A5. pie_log 窗口上限溢出静默丢弃（与帧排空溢出的明报不对称）**（2026-10-28 T12-T2 QA 回流③建议开票；主控批准立账）
  `crates/jackdaw_runtime/src/pie_log.rs`（T12-T2 引入）：节流层每秒窗口上限（32 条/秒）溢出时静默丢弃，而每帧 512 条排空溢出有明报——同一转发层两种溢出语义不对称；唯一性错误恰逢窗口满时可能被丢（低概率、低危，但日志即 T12 的验收面）。
  修复方向：窗口溢出补一条自身计数 warn（或尾条替换+计数标注，形态与帧排空对齐）。小票，下轮触碰 pie_log 时顺手。

- [x] **N10. dirty 场景 + Save 态 play_current 真机冻结编辑器主线程（2026-10-26 T06-T3 矩阵 cell 3 发现）**
  触发：打开已保存场景 → 任意编辑（脏）→ `pie.play_current`（save 策略，默认态）→ play_current 调用正常返回，**下一帧起主线程满 CPU 自旋**（实测 CPU/4s≈5s），BRP 全部无响应，日志停在 `OPERATOR: pie.play_current` 后零输出（保存链最早期）。
  实证（`loop/t06t3_probe_freeze*.log`）：① main 基线（66ef15e8，无 T3 改动）同样冻结=**既有 bug**（T1 的 Save 态 dirty play 真机路径从未跑过，headless guards 全绿）；② clean 场景 play、untitled/dirty + Copy 态 play、Ask→Copy 均不冻；③ connected 后 stop 不冻，但 connecting 窗口内 stop 也触发同款冻结（T3 曾放宽 avail 门后实测 100% 复现，已回退该放宽，connecting-stop 恢复 avail 拒绝+重试语义封路）；④ 保存链单独走（scene.save op）不冻——冻结需要「保存链 + PIE 启动」同帧组合。
  影响面：T1 交付的默认策略（save）在真机上不可用于脏场景 play（用户主路径！）。绕行：先 Ctrl+S 再 Play，或切 play_unsaved_copy。
  修复方向：冻结在 `launch_current_scene → resolve_override_for_launch → save_scenes_before_launch` 之后的同帧 PIE 启动段；重点排查保存后同帧 `spawn_instance`/asset watcher 重扫/编辑器 UI 重建的交互循环。优先级高（默认策略主路径）。
  （2026-10-26 N10 修复任务备注：触发面 13 轮真机穷举（QA 4 + 程序 9，含高负载/真门禁负载/connecting-stop/stop 锤变奏）**不可稳定复现**，按降级路径执行静态根因+加固修复：主嫌疑=主线程 `drain_received` 无界 try_recv 循环（积压下消费≤生产则永不 Empty→满 CPU 自旋，三条触发路径的保存链/投影重建/OnEnter 重链都是积压引信；程序 3s 判死窗 vs QA 9s 判活窗解「100% vs 零复现」矛盾）。修法：drain 加 256 帧/4ms 双预算（跨帧消化积压，主线程单帧有界），trait 契约改 bounded batch；守卫测试（洪泛有界+不丢）+ dirty+Save 一步回归 3/3 + 三边界（B2 隔离复测 2/2）+ stop 锤 3 循环全过。记档：ipc try_recv 部分消息转 INFINITE 阻塞（crate 内部语义，不可加超时，风险低）；connecting-stop 的 accept task detach 泄漏（bevy Task 语义+同步 accept 不可取消，待 ipc 侧可中断 API）。**已修复 6cfb1358（合入 main 54cd5ce6，QA PASS 2026-10-26）**：验收报告 loop/reports/n10-qa.md；QA 硬性后续 dirty+Save 一步回归已独立复跑确认。次嫌疑两条保留在档待后续。）

- [ ] **N11. Inspector 合成提交驱动缺口（Live 预览 UI 级验收的工具面洞）**（2026-10-26 T06-T3 发现；**本条为 2026-10-26 编码事故后按报告底稿重建，措辞待用户校订**——首次写入未落地，无原文）
  背景：T06-T2 显式门 UI 级真机链（Inspector 拖拽/敲键→字段提交→stop prompt 按钮）三次探针证明两条合成输入路径均不可达（outliner Live 行不在 `ui_tree`、viewport pick 不中投影实体），矩阵 #7 只能以 selection 面（`selection.set`）收口。
  影响：Inspector 交互级验收链缺一条腿；语义已由 headless live_edits 18 例+真机双 SHA 铁证覆盖，非产品缺陷。
  修复方向：补 field.set 类 BRP 或 Inspector 合成提交通道后，收口 T06 矩阵 #7 按钮链完整形态。T06 终验落账的排期项。

- [ ] **N12. bevy 原生 BRP 与 jackdaw 方法实体域互不相通**（2026-10-26 T06-T3 发现；**本条为编码事故后按报告底稿重建，措辞待用户校订**——首次写入未落地，无原文）
  现象：真机断言读实体值时，bevy 内建方法（`world.query` 等）查不到 jackdaw 方法（`jackdaw/entity` 等）管理的实体（id 域两套），反之亦然；本构建 bevy BRP `world.query` 实测恒空。
  影响：QA 断言与工具层需按域选方法；`jackdaw/entity` 以 BSN 文本绕行可用。
  修复方向：统一实体 id 域或在 jackdaw 方法侧提供同域查询面（`jackdaw/pie` 投影流已部分承担）。T3 域记档项。

- [ ] **N13. PIE 连接后 drain_game_events swap_remove panic（疑似潜伏缺陷）**（2026-10-28 T10b QA 核验发现；主控批准立账；T10b 返工轮已完成特性刻画）
  现象：`swap_remove index (is 1) should be < len (is 1)`，位于 `jackdaw::pie::drain_game_events` exclusive system（bevy 捕获不退出进程），PIE connected 后 1.9s（原件 `H:\workspace_AI\t10b-qa\`+T10b 报告 §九）。
  刻画（T10b 返工轮）：本体无 swap_remove、仓内 tree_view 两处带 position() 护航——断言收敛到 bevy_ecs 内三处无护航点（archetype.rs:630 / table/mod.rs:255/765），「index 1 len 1」匹配**陈旧 EntityLocation**（重入/交错操作特征）；调用链唯一 ECS 结构写路径=pie_projection::project_event 全量镜像投影窗口。与 N10 三项症状类型均不同=**第三种独立问题**。非必现（1 hit/1 clean）。
  修复方向：先 PIE connected ×10 连跑定复发率+RUST_BACKTRACE=1 拿真栈（折入 T11-T2 真机腿）；嫌疑链排序①投影重入→②bevy_ecs 陈旧 location→③树索引上游竞态；🔴 严重度候选（数据结构级 panic）。
  > 2026-10-28 更新：N13 复发率测定因驱动态（PIE 全形态崩）不可执行，挂账维持（t11-t2-qa.md §四-3）。
  > 2026-10-28 更新（T11-T3 Mac 真机 ×10 完成）：**复发率=100%**——10/10 轮 connected 全复发，累计 **57 次 panic**（每 connect/stop 周期 ~5-6 次）；同签名第二个受害系统 **`jackdaw::pie::cleanup_session_on_stop`**（原刻画未含）；Mac 上全部被 bevy 系统错误处理器捕获（编辑器存活，`Encountered an error in system ...: Exclusive system panicked`），旧机形态直接杀死编辑器——严重度依机器形态不同；Mac 签名 `swap_remove index (is 0) should be < len (is 0)`（空 vec 退化形态，与旧机 is 1/len 1 同根）。RUST_BACKTRACE=1 在 Mac debug 构建不可用（wgpu LockTrace→libunwind SIGSEGV，见 t11-t3-report 环境节），真栈仍缺。证据 `loop/t11t3-live/t11t3-a2-mac-*`。

- [x] **N14（=T11 方案 C11）. 单字段 set 后存档丢同组件未编辑字段**（2026-10-28 T11-T2 程序发现+QA 定向复现实锤；主控批准立账）
  现象：entity add 组件后首次单字段 set（如 set move_speed）→save，同组件其他字段（jump_speed）从文档消失（QA 复现链 t11-t2-qa.md §四-2；程序发现 t11-t2-report.md）。
  危害边界（QA 收窄）：触发窗口唯一=add 后首次 set；「非默认改值被丢」场景实测安全（P2 反证——先改过值的字段不会被丢）；当前行为无损系默认值巧合。
  修复方向：add 后首 set 应以「完整组件值」落文档而非仅 set 字段（T3 顺手修，QA 建议）。
  > 2026-10-28 更新（T11-T3）：**已修**（406d116b，T3 分支）——add 后首 set 以 schema 默认合并整组件落库；Windows 活证（t11t3-a-summary `N14_LIVE_SIBLING_ON_DISK=True`）+ Mac 复证（t11t3-a-mac-summary `N14_LIVE_SIBLING_ON_DISK=PASS`：move_speed 2.0 与 sibling jump_speed 4.5 同在盘上）。勾选留待 QA 复核。
  > 2026-10-28 勾选：QA 终验四重复核通过（代码审查+guards 测试亲跑 PASS+双机活证+盘上 .bak 时序证据，t11-final-qa.md §N14）——主控勾选。
