# R8 程序报告：Extend-to-Brush 凸半空间重建凸化凹主笔刷（buglist 🔴）

> 分支 `loop/bug-r8-extend-face-concave`（自 main `b318c17a` 拉出）。裁定口径：**检测非凸
> → 拒绝 + 提示**（B 案；mesh-CSG 迁移为 A 案，留 roadmap 候选，本票不做）。
> **未合入 main，待 QA。** 修复循环：1 轮（上限 5）。

## 1. Extend 链清单（读透结果）

入口系统 `brush_extend_face_to_brush`（`#[operator id="brush.extend_face_to_brush",
is_available=can_run_extend_face, allows_undo=false]`），两条入口在 resolve 之后汇于一点：

1. **Face 模式路径**：primary = `BrushSelection::active_brush`，face =
   `sub.faces.last()`，targets = `Selection::entities` − primary；
2. **Object 模式路径**：primary = `Selection::primary()`，face = hover raycast
   （`find_hovered_face_on_brush`，纯只读）或 remembered face。

修前副作用时序：resolve → **（副作用①）Face 模式退出 + `brush_selection.clear()`** →
`commands.queue(extend_face_to_brush_impl)` → 返回 `Finished`（`None` → `Cancelled`，
两者都不产生历史条目）。

`extend_face_to_brush_impl`（deferred closure，副作用②③④全在这里）：

- 读 `Brush` + `GlobalTransform`（丢弃 scale）→ `brush_planes_to_world` 构造
  world_faces（去掉被 extend 的面）；
- 目标面收集：翻转半空间（「墙延伸到目标表面为止」），angled 过滤
  （dot ∈ (−0.99, −0.01)），空则 opposing 回退（dot < −0.01）；
- **`compute_brush_geometry_from_planes`——凸化根源**：凸半空间交集，内部用
  `point_inside_all_planes` 过滤，只保留落在所有半空间内的顶点，凹形被静默重铸为
  半空间交集（凸体）；
- no-op 对比（verts 数量 + 逐点 1e-4）→ `clean_degenerate_faces` →
  `compute_brush_topology` → **（副作用②）`sync_brush_to_ast`**（BSN AST patch）→
  ECS `Brush` 覆盖 → **（副作用③④）`history.push_executed(SetBrush)`**（undo 一条）。

几何 API 签名（只读未动）：`compute_brush_geometry_from_planes(&[BrushFaceData]) ->
(Vec<Vec3>, Vec<Vec<usize>>)`；`clean_degenerate_faces(&[BrushFaceData]) ->
Vec<BrushFaceData>`；`compute_brush_topology(&[BrushFaceData]) -> BrushTopology`；
`point_inside_all_planes(Vec3, &[BrushFaceData]) -> bool`（EPSILON = 1e-4）。

检测点安置结论：两条入口汇于 operator 单点，且 impl 亦为单入口（全库仅 operator 一处
调用），守卫可单点安置、无需停下报主控（补遗条款未触发）。

## 2. Diff 面（仅 `src/draw_brush/extend_face.rs`，+333/−3）

- 导入 `point_inside_all_planes`；
- `brush_query: Query<(), With<Brush>>` → `Query<&Brush>`（`contains` 语义不变，
  增加 `get` 读取；`can_run_extend_face` 可用性函数未动，凹笔刷仍显示可用——按 D2
  在调用时拒绝并提示，而非静默不可用）；
- **operator 入口守卫**（位于 Face 模式退出**之前**，两条入口汇合点）：非凸 →
  `warn!` + `commands.queue(toast)` + 返回 `None`（= Cancelled，零副作用：不退出
  编辑模式、不清 BrushSelection、不 queue impl、不写 AST、不 push undo、不动预览）；
- **`brush_is_convex` helper**（同文件，D1）：对笔刷自身 `topology.vertices` 逐点跑
  `point_inside_all_planes`（任一顶点落在任一 face plane 正侧外即非凸）；**本地空间
  判定**（凸性是刚体变换不变量，rotated 笔刷无需 world 换算，专测锁定）；eps =
  `jackdaw_geometry::EPSILON` = 1e-4，与凸范式内部容差和 extend 既有 no-op 对比一致；
  **不可用 `compute_brush_geometry_from_planes` 的输出做检测**——它就是半空间交集
  本身，永远「凸」（红证阶段实测确认）；legacy plane-only 笔刷（topology 空、无顶点）
  形状即半空间交集、凸由构造保证，判凸放行；
- **`toast_brush_notice` helper**（同文件，D2）+ `CONCAVE_EXTEND_REFUSAL` 文案常量；
- **impl 深防御守卫**（world_faces 构造之前）：非凸 → `warn!` + `toast_brush_notice`
  + 返回（geometry/AST/undo 零变化）；生产路径 operator 已先拒，此守卫不会被双触发，
  不存在双 toast；
- operator 文档补拒绝说明；`#[cfg(test)] mod extend_face_tests`（5 测试）。

未触碰：`compute_brush_geometry_from_planes` / `clean_degenerate_faces` /
`compute_brush_topology` 本体、mesh-CSG、subtract/knife/nudge、buglist/roadmap/progress。

## 3. 红证（`loop/bug-r8/red.log`，pre-fix 实跑）

构造：R7 手法 L 形凹笔刷（`Brush::cuboid(1,1,1)` − 角部 `cuboid(0.5)`，9 面/14 顶点），
移除 **+Y 凹角咬墙**（normal +Y、distance 0.25 的 re-entrant 面，打开咬口后凸范式把
笔刷重铸为盒）；目标 = 本地 cuboid + GT(rotY 45° @ (3,0,0))（record_counts 守卫同款
斜墙构造）。红证模块只含 impl 级测试（不引用修复期才存在的 helper），挂回 pre-fix
源码实跑：

- `extend_refuses_a_concave_primary_and_touches_nothing` **红**：9 面 → 6 面凸体重建、
  undo +1、无 toast；
- `extend_refuses_a_rotated_concave_primary`（GT 绕 Z 转 90°）**红**：同样被重建；
- `extend_still_rebuilds_a_convex_primary`（D3 锚）修前即绿（锚本身有效）。

绿证 `loop/bug-r8/green.log`：同一测试体在修复版上 5/5 绿。红绿共用测试体，红证是把
修复回退后实跑取得（见偏差 1）。

## 4. 测试清单

| 测试（均在 `extend_face_tests`） | 断言 | 阶段 |
|---|---|---|
| `extend_refuses_a_concave_primary_and_touches_nothing` | 面逐位不变 + 顶点逐位不变 + undo 0 + `EditorToast`×1 | 红→绿 |
| `extend_refuses_a_rotated_concave_primary` | 同上（少 toast 断言），GT 旋转 90° 下拒绝 | 红→绿 |
| `extend_still_rebuilds_a_convex_primary` | undo 恰一条 + 几何确实重建 + 无 toast（D3 凸回归锚） | 修前修后均绿 |
| `convexity_helper_tells_the_l_from_the_cuboid` | L 判非凸、cuboid 判凸 | 随修复加入 |
| `convexity_eps_ignores_subepsilon_poke_out` | 顶点漂 5e-5（<eps）仍判凸；漂 1e-3（>eps）判非凸 | 随修复加入 |
| 既有 `record_counts::the_extend_face_keybind_is_one_user_entry`（tests/guards） | 凸笔刷 operator 全链（可用性→dispatch→undo 一条→文档变更→undo 恢复） | 通过，零回归 |

## 5. 门禁表（日志全文复核制，归档 `loop/bug-r8/gate-*.log`）

| 门 | 结果 | 证据 |
|---|---|---|
| `cargo fmt --all -- --check` | 过（首跑有 diff，`cargo fmt` 后复跑，归档日志 0 行覆盖旧日志） | `gate-fmt.log`（空=无 diff） |
| `cargo clippy --workspace -- -D warnings` | 过，exit 0，全 log 无 warning/error 行 | `gate-clippy.log` |
| `cargo test --workspace --lib` | **3122 通过 / 0 失败，59 二进制 = 基线 3117 + 新增 5**，exit 0，逐行复核无 FAILED/error | `gate-libtests.log` |

「任务相关」补充：`tests/guards`（含 extend 守卫）通过。`tests/stage` 套件在本机有
7 个失败（`launcher`/`new_project`/`extension_app_plugin`，均需派生外部编辑器进程）；
把本改动 stash 后在**纯净 main** 上过滤重跑同族测试同样失败（9 failed / 19 filtered，
含相同测试名）——甄别为**预存环境失败**，与本票无关，已如实记录、不并修（发现即报，
如主控认为值得立票请裁定）。

## 6. D2 拒绝通道选型理由（盘点结论）

brush 域**没有**既有 toast/notice wrapper；全库 toast 唯一通道是
`jackdaw_feathers::toast::toast(...)` 直接 spawn。最接近先例：

- `crate::terrain::toast_terrain_notice`（R5「拒绝+toast」用的 wrapper）：Error 变体 +
  `DEFAULT_TOAST_DURATION` + 字体资源缺失时 headless 静默 no-op guard；
- R5 拒绝形状：`warn!("{message}")` + `commands.queue(move |world| toast(world, &msg))`
  + 返回 `None`（terrain/ops.rs refused 分支）；
- `OperatorResult` 无消息变体（仅 Finished/Cancelled/Running），提示只能走 toast。

选型：本文件本地 `toast_brush_notice`（原样镜像 `toast_terrain_notice` 的 spawn + guard，
Error 变体 + 默认时长），配合 R5 的 warn!+queue 形状；不借用 terrain 通道（方案书明确
terrain 通道不跨域）。文案（英文、诚实句式）：「Extend to Brush refused: the primary
brush is concave, and the extension rebuilds the brush as the intersection of its face
planes, which would collapse it into a convex hull.」若日后 brush 域拒绝点增多，可把
wrapper 上移为共享 `toast_brush_notice` 到中立模块（超出本票红线，未做）。

## 7. 偏差与备注（如实）

1. **红证取得方式**：先写好修复与全量测试，再 `git checkout` 回退产品代码为 pre-fix、
   挂上同一测试体的红证子集（不含依赖 helper 的两个 helper 单测）实跑取得 red.log，
   然后恢复修复版跑 green.log。红绿测试体一致，红证真实（红证文件里即 pre-fix 行为）。
2. **测试构造定位经过**：首选用 record_counts 同款构造（移除 cuboid +X 面）做凹红证时，
   斜墙翻转面与 L 自带的 `x<=1` 原始面冲突 → 半空间交集为空 → impl 早返回（无重建），
   探针实测确认后改用「移除 +Y 凹角咬墙」构造——无需目标面参与即必然重建凸化，红证
   稳定。凸锚测试在裸 World 中复现了 record_counts 的行为（undo 恰一条 + 文档变更）。
3. **凸笔刷 extend 现状语义**（探针观察，未改动）：cuboid 向斜墙 extend 的产物是退化
   几何（6 面/2 顶点）且 push undo——这是 pre-existing 行为，D3 锚按现状锁定；如认为
   值得立票请主控裁定。
4. QA 真机腿提示：extend 有结构化 operator 入口（`brush.extend_face_to_brush`，
   `run_op_clause` 可驱动，record_counts 守卫即此驱动），QA 无需 SendInput 兜底；凹笔刷
   可经 `brush.selection.set_faces` 或 CSG subtract 造出。
5. 红线遵守：产品代码仅动 `src/draw_brush/extend_face.rs`；凸性 helper 与 toast helper
   均在同文件（红线允许的另一选项 src/brush/ 未用）。

## 8. 结论

R8 修复完成：凹主笔刷 Extend 现在被拒绝并 toast 提示，几何/AST/undo/编辑器状态零副作用；
凸笔刷 Extend 行为零变化（既有守卫 + 新锚双重锁定）。**未合入 main，待 QA**（QA 报告
落 `loop/reports/bug-r8-qa.md`）。
