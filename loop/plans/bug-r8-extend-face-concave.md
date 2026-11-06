# R8 修复方案：Extend-to-Brush 用凸半空间交集重建，凹主笔刷被凸化（buglist 🔴）

> 立项：2026-11-06（buglist 第 5 票）。基线：main `b318c17a`（R7 闭环后）。libtests 基线
> **3117**（59 二进制）。

## 票面（buglist.md:58-62 摘要）

`src/draw_brush/extend_face.rs:288-329`（`compute_brush_geometry_from_planes` +
`clean_degenerate_faces` + `compute_brush_topology` 凸范式路径）；subtract 侧
（csg_ops.rs:253-259、preview_mesh.rs:587-591）注释已明确该路径「把凹笔刷坍缩成凸包
或空拓扑」并刻意绕开，extend 仍在用。后果：凹主笔刷执行 Extend 后几何被静默重铸为
凸体。修复方向：迁移到 mesh-CSG，或检测到非凸时拒绝执行并提示。

## 策划期核实（2026-11-06 主控亲读，R7 等待窗口完成）

1. **凸范式路径成立**：extend_face 尾段「Combine → `compute_brush_geometry_from_planes`
   → no-op 对比 → `clean_degenerate_faces` → `compute_brush_topology` →
   `sync_brush_to_ast`（undo-able SetBrush）」——与票面行号吻合（行号可能因 R7 漂移
   1-2 行，机制未变）。
2. **修复方向二选一的裁定**：**本票走「检测非凸→拒绝+提示」**（B 案）；mesh-CSG 迁移
   （A 案）是 feature 级工程量（M-L），不属于 bugfix 票范围，票面勾选时注明 A 案留
   roadmap 候选。理由：B 案关闭「静默毁几何」这一 🔴 本体；A 案是能力增强不是止血。

## 修复方案（主控已裁）

- **D1 非凸检测**：对主笔刷做凸性判定——任一顶点落在任一 face plane 正侧外
  （`plane.distance + eps < 顶点平面值`，eps 取 1e-4 量级与既有 no-op 对比一致）
  即非凸；O(V×F) 足够（笔刷顶点/面数为小量）。检测点放在 extend 入口（构造
  world_faces 之前），拒绝路径零副作用（不写 AST、不 push undo、不动预览）。
- **D2 拒绝反馈**：toast（`toast_terrain_notice` 是 terrain 通道——extend 属 brush 域，
  用 brush/编辑器既有 toast/状态栏通道；程序盘点后选最近先例并报告）；文案诚实：
  「凹笔刷不支持 Extend（凸重建会毁形），已拒绝」级，英文与既有句式一致。
- **D3 凸笔刷回归锚**：凸笔刷 Extend 行为零变化（含 no-op 对比、undo 一条语义）。
- **范围红线**：产品代码只动 `src/draw_brush/extend_face.rs`（含测试；凸性判定
  helper 可放同文件或 `src/brush/` 下、随报告说明）；不碰 compute_brush_geometry_
  from_planes/clean_degenerate_faces/compute_brush_topology 本体、不碰 mesh-CSG、
  不碰 subtract/knife。

## 测试方案（红→绿）

- **红证**：构造凹笔刷（R7 已沉淀 L 形构造手法，brush_element_ops 测试与
  apply_vertex_deltas_tests 先例），触发 extend 路径（函数级单测即可）——修前
  面/顶点数被凸化改变（红），断言「拒绝+几何逐位不变+无 undo」修后绿。
- **凸回归锚**：凸笔刷 extend 成功路径既有测试零回归 + 新增凸体 extend 断言。
- **边界**：近平非凸（eps 边界）判定稳定性测试；rotated 笔刷（plane 在 world/local
  间换算）凸性判定正确性。
- **真机腿（QA）**：L 形凹笔刷 → 触发 extend（operator 优先；若 extend 仅手势驱动
  且无结构化入口 → 报主控按 R7 先例补工具或 SendInput 兜底，如实记档）→ 断言拒绝
  反馈出现 + 几何不变（BRP 组件查询面/顶点数）+ 凸笔刷 extend 正常。

## QA 验收要求

门禁三连亲跑（libtests=R7 后基线+新增数·59 二进制口径）/红绿独立复核/真机腿
MCP 优先（环境情报同 R5-R7：Open without setup、A20/A21 绕行、r6/r7-live.sh 借鉴）/
报告 `loop/reports/bug-r8-{report,qa}.md`、证据 `loop/bug-r8*/`；不合入不打勾，
收尾归主控。发现新缺陷立票不并修。

## 决策点补遗

程序若发现 extend 的入口形态复杂（多入口/预览链带副作用）、非凸检测点难以单点安置，
停下报主控，不得自行扩大改动面。
