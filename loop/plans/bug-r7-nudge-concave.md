# R7 修复方案：Nudge（PageUp/PageDown）走凸包重建摧毁凹笔刷（buglist 🔴）

> 立项：2026-11-06（buglist 第 4 票）。基线：main `a823f4da`。libtests 新基线 **3104**。

## 票面（buglist.md:53-56 摘要）

`brush_element_ops.rs` nudge 走 `rebuild_brush_from_vertices`（`src/brush/hull.rs:18`，
内部 `jackdaw_hull` 凸包）；vertex drag 走 `apply_vertex_deltas`（半边优先）。
对 CSG/Knife 产出的凹笔刷，选中面按 PageUp，整个 brush 被静默替换为顶点凸包
（L 形变方块）。修复方向：nudge 改走 `apply_vertex_deltas`（半边优先、hull 仅
legacy 兜底），与 vertex drag 共用路径。

## 策划期核实（2026-11-06 主控亲读）

1. **拆分现状成立**：nudge 入口 `nudge_brush_element`（brush_element_ops.rs:280）→
   逐 plan 构造 `new_verts` → `rebuild_brush_from_vertices`（凸包，face 索引重映射）；
   而 vertex drag（brush_drag_ops.rs）、numeric transform（numeric_transform.rs:646）、
   gizmo（gizmos.rs:930）三条路径全部走 `apply_vertex_deltas`（brush_drag_ops.rs:1641）。
2. **共用路径可行**：`apply_vertex_deltas` 在既有拓扑内位移顶点（半边优先），
   面索引**天然稳定**——修复后 nudge 的 face remap 逻辑应成恒等（程序核实后可简化，
   如实记档）。
3. **测试锚先例**：`apply_vertex_deltas_tests`（brush_drag_ops.rs:1708）在案；
   nudge 侧测试锚由程序盘点（brush_element_ops.rs 现有 #[cfg(test)] 情况）。

## 修复方案（主控已裁）

- **D1**：`nudge_brush_element` 改走 `apply_vertex_deltas`（pub(crate) 已导出）；
  位移语义=受影响顶点在 brush local space 加 offset（与 drag 的 local-space 口径
  对齐，世界 Y 网格步经 `start_world_to_local` 等价变换——具体换算按
  `apply_vertex_deltas` 签名与 drag 调用方先例写，报告说明）。
- **D2**：凸包重建路径 `rebuild_brush_from_vertices` **保留**（legacy 兜底 +
  其他调用方不动），仅 nudge 不再调用；不删不改 hull.rs。
- **D3**：Face 模式的 face 重映射：`apply_vertex_deltas` 路径面索引稳定，
  `nudge_faces` remap 逻辑核实后简化或保留恒等映射（报告写明取舍）。
- **D4**：undo/any_modified/历史语义与修前完全一致（一次 nudge=一条 undo）。
- **范围红线**：产品代码只动 `src/brush_element_ops.rs`（含测试）与
  `src/brush_drag_ops.rs`（仅当 `apply_vertex_deltas` 需要窄适配，如暴露 local-space
  简化入口；先在报告说明最小 diff）；不碰 hull.rs/CSG/Knife/gizmo/numeric_transform。

## 测试方案（红→绿）

- **红证（先于修复归档）**：新测试在 brush_element_ops 侧构造**凹笔刷**
  （L 形：至少 8 顶点带凹角、带 `BrushHalfedge` 拓扑——构造方式参照
  `apply_vertex_deltas_tests` 或 CSG 测试先例），nudge 一个面/顶点：
  断言「面数不变、拓扑不变、仅受影响顶点位移、其余顶点逐位不动」——修前
  凸包重建使面数/顶点位变化 = 红。
- **绿证**：上述断言全绿 + **凸笔刷回归锚**（立方体 nudge 行为与修前一致——
  修前凸包路径对凸笔刷 face 数可能已有行为，修后按 apply_vertex_deltas 语义
  面数不变；两语义对凸体的差异如实记档）+ 既有 nudge/brush 测试零回归。
- **真机腿（QA）**：boot 编辑器 → 两个 box 笔刷交叠 → subtract 出 L 形凹笔刷
  （CSG 先例）→ 选中其一个面 → 按 PageUp：
  断言①笔刷仍为 L 形（面数经 BRP 组件查询 Brush topology 断言 + 截图）；
  断言②undo 恰一条且可撤销还原；断言③凸笔刷 PageUp 不回归。
  （驱动先例：`loop/bug-r6-qa/r6-live.sh` + ui_input 键盘注入 R1 先例；
  环境情报同 R5/R6：无 jackdaw.toml 走 Open without setup、A20/A21 绕行。）

## QA 验收要求

门禁三连亲跑（libtests 新基线 3104+新增数·59 二进制口径）/红绿独立复核/
真机腿 MCP 优先/报告 `loop/reports/bug-r7-{report,qa}.md`、证据 `loop/bug-r7*/`；
不合入不打勾，收尾归主控。发现新缺陷立票不并修。

## 决策点补遗

程序若发现 `apply_vertex_deltas` 与 nudge 的基线构造（drag baseline）阻抗失配
过大（如需要引入整套 drag 状态机），**停下报主控**，不得自行大改共用函数签名。
