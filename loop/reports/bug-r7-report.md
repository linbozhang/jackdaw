# R7 修复报告：Nudge（PageUp/PageDown）改走 apply_vertex_deltas，凹笔刷保形

> 程序 agent，2026-11-06。方案书 `loop/plans/bug-r7-nudge-concave.md`，分支 `loop/bug-r7-nudge-concave`（自 main `a823f4da` 拉）。
> **未合入 main，待 QA。**

## 结论

nudge（`nudge_brush_element`）不再调 `rebuild_brush_from_vertices`（凸包），改走
`apply_vertex_deltas` 半边优先路径，与 vertex drag / numeric transform / gizmo 共用
同一条保形管线。凹笔刷（CSG subtract 产物）PageUp/PageDown 不再被静默凸包化。
`src/brush_drag_ops.rs` **零改动**——`apply_vertex_deltas` 现有签名直接满足 nudge
形态，无需窄适配；方案书补遗条款（阻抗失配停机）未触发。

## 两路径对照（修前盘点）

| 维度 | nudge 修前（brush_element_ops.rs:280） | drag 共用（brush_drag_ops.rs:1641） |
|---|---|---|
| 核心 | `rebuild_brush_from_vertices`（src/brush/hull.rs:18 → `jackdaw_hull` 凸包） | `apply_vertex_deltas` 半边优先（`halfedge: Some` 时） |
| 顶点位移 | `new_verts[vi] += (0, ±grid, 0)` **直接加在 brush local** | new_positions 是**绝对 brush-local 目标位**；世界位移经 `start_world_to_local.transform_point3`（先例 `broadcast_drag_to_captures` :1522） |
| 凹形 | 凸包重建摧毁（L 形→方块），红证实测面 9→7、顶点 14→10 | 半边 mesh 内直接改 `v.co` + newell 重算法线 + `flatten_to_topology`，保凹（edit_mode_systems.rs:30 注释明言） |
| 面索引 | 凸包重排，需 `old_to_new` remap（:362-371） | **天然稳定**：`brush.faces` 平行数组就地更新 plane，列表不动 |
| 失败语义 | 凸包 None → continue（Cancelled） | 半边路径总成功；legacy（None halfedge）凸包兜底 |
| indices 口径 | authored 顶点索引（sub.vertices/edges/faces×`authored_face_polygons`） | 同口径：`halfedge.vert_keys` 平行于 `BrushTopology::vertices`（edit.rs:26-33），authored 索引直传 |

三个既有调用方换算写法：vertex/edge drag（`broadcast_drag_to_captures`）、numeric
transform（`apply_capture_plan`）、gizmo（gizmos.rs:930）同构——`start_world` lift 到
世界 → 加世界位移 → `world_to_local.transform_point3` 落回各 brush local。nudge 取
`broadcast_drag_to_captures`（形态最接近：单一位移、无 pivot 变换）为蓝本。

## 修复内容（D1-D4）

- **D1** 新增私有核心 `apply_nudge_to_brush`（brush_element_ops.rs:392）：世界
  offset 按先例换算（`world_from_local.transform_point3` lift → 加 offset →
  `world_to_local.transform_point3` 落回 local），调 `apply_vertex_deltas`。
  `halfedge` 取自新增的 `Query<&mut BrushHalfedge>`；组件缺失（legacy 平面笔刷无
  topology，`sync_brush_halfedge_on_edit_mode` 不 lift）时传 None 落 legacy 凸包
  兜底——**凸包路径保留但仅作兜底**（D2：hull.rs 零改动，其他调用方不动）。
  语义变化记档：修前 offset 直接加 local（旋转笔刷走 local Y），修后按方案书 D1
  裁定为**世界 Y 网格步**（与 drag 口径对齐）；有专门红证测试覆盖（见测试清单 3）。
- **D2** `rebuild_brush_from_vertices` 保留在 hull.rs，nudge 不再调用；
  `use` 移除（本文件不再直连凸包，兜底在 `apply_vertex_deltas` 内部）。
- **D3** Face 模式 remap **简化为删除**：`apply_vertex_deltas` 半边路径面索引稳定，
  `NudgePlan.nudge_faces` 字段与 `old_to_new` 过滤块整体移除，`sub.faces` 天然保持
  有效。红证阶段该简化已随重构先行（remap 只影响 selection 索引、不触碰红证聚焦
  的几何行为，红证真实性不受影响），如实记档。
- **D4** undo/any_modified 语义不变：入口 operator 返回值规则不变（Finished /
  Cancelled）；核心加了 `moved` 判定（零步位移或索引越界返回 false → Cancelled），
  比「凸包失败才 Cancelled」更精确，一次 nudge 仍是一条 undo。
- **mirror 语义记档**：nudge 保持不接 mirror clip（传 None）。修前凸包路径同样无
  mirror 语义，行为不变；drag 的 mirror clip 不在本次范围。

## 范围红线自查

产品代码只动 `src/brush_element_ops.rs`（+336/-26，含测试模块）；`brush_drag_ops.rs`
零改动；hull.rs / CSG / Knife / gizmo / numeric_transform 零改动；buglist / roadmap /
progress 未动。发现的新现象（见「凸体语义差异」）不立票、记档交主控判断。

## 测试清单（brush_element_ops.rs `nudge_tests`，4 例）

凹笔刷构造：`Brush::cuboid(1,1,1)` 减 `translated_cuboid(0.5, (0.75,0.75,0.75))`
（`jackdaw_csg::brush_boolean` Difference，同 CSG 测试先例）→ 实测 14 顶点 / 9 面，
含 >4 顶点凹环。

1. `face_nudge_on_concave_brush_preserves_the_shape` —— 面 nudge：面数 / 多边形数 /
   顶点数不变，受影响顶点逐位 = 旧位 + offset，其余顶点逐位不动。
2. `vertex_nudge_on_concave_brush_preserves_the_shape` —— 顶点模式（凹环单顶点），
   同保形断言。
3. `nudge_offset_follows_world_y_through_brush_rotation` —— 笔刷绕 Z 转 90° 时
   nudge 沿**世界 Y** 上升一格（D1 口径；修前 local 直加语义此测试必红）。
4. `face_nudge_on_a_convex_brush_keeps_cuboid_shape` —— **凸笔刷回归锚**：立方体
   nudge 后 6 面 / 8 顶点，位置多重集合按「底面不动、顶环 +offset」完全匹配
   （顺序无关容差断言）。

## 红证（loop/bug-r7/red.log，修前行为上跑）

红证方法：先以最终结构落地抽函数，但内部保持修前凸包行为（等价重构），测试在其
上跑红归档后，才切 `apply_vertex_deltas`。

- face_nudge_on_concave：**红**（面数 9→7，凸包摧毁）
- vertex_nudge_on_concave：**红**（顶点数 14→10）
- world_y_through_rotation：**红**（凸包重建产出 7 面 ≠ 6 面；同时体现修前 local
  口径）
- convex_cuboid 锚：绿（凸体在凸包路径下形状不变——锚测试定位即「修后不回归」，
  修前绿符合预期）

## 绿证（loop/bug-r7/green.log）

fmt 后状态重跑覆盖归档：4/4 全绿（顶点顺序逐位比对通过，证明 flatten 保序）。

## 门禁三连（日志全文复核制，证据 loop/bug-r7/）

| 门 | 结果 | 证据 |
|---|---|---|
| `cargo fmt --all -- --check`（先 fmt 落盘） | 干净（fmt 仅重排本文件长行） | fmt.log |
| `cargo clippy --workspace -- -D warnings` | 干净（exit 0，无 warning/error 行） | clippy.log |
| `cargo test --workspace --lib` | **3108 通过 / 0 失败**（59 二进制；= 基线 3104 + 新增 4），日志逐行复核无 FAILED/error/panicked | libtests.log |

## 凸体语义差异记档（交 QA/主控）

1. 修前凸包重建对**凸笔刷**也不保证逐位稳定：凸包重算会重排顶点索引、对退化共面
   三角形合并不净（红证里旋转立方体单顶点 nudge 后凸包产出 **7 面**而非 6 面）。
   修后半边路径对凸体同样逐位稳定，凸锚由多重集合断言升格为逐位（凹测试同款）也
   会通过——凸体的可见行为（形状、面数）修前后一致，内部索引稳定性修复后反而更
   好。
2. 旋转笔刷的 nudge 方向语义从「brush local Y」变为「世界 Y」（D1 裁定）。QA 真机
   腿如测旋转笔刷请按世界 Y 断言。

## 偏差清单

1. **红证阶段 D3 简化先行**（见 D3 段）：红证测试聚焦几何保形，remap 删除不影响
   红证有效性；如主控认为需严格「红证=修前完整行为」，可要求补一次保留 remap 的
   中间态红跑。
2. **`moved` 判定为新增**（D4 段）：修前凸包失败才 Cancelled；修后零位移/越界也
   Cancelled。边缘行为更精确，非回归。
3. 无其他偏差。方案书 D1-D4 全部落实，补遗条款（阻抗失配停机）核实为**不触发**：
   `apply_vertex_deltas` 无 drag 状态机依赖（`start_brush`/`all_vertices`/
   `face_polygons` 仅 legacy/mirror 路径读，半边路径可传 cache 现值），签名零改动。

## 交付物

- 分支 `loop/bug-r7-nudge-concave`，**未合入 main，待 QA**
- 证据：`loop/bug-r7/{red,green,fmt,clippy,libtests}.log`
- 报告：`loop/reports/bug-r7-report.md`（本文件）
