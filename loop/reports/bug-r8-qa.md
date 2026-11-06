# R8 QA 验收报告：Extend-to-Brush 凸路径毁凹笔刷 → 非凸拒绝

> QA：jackdaw Loop QA agent。验收对象：分支 `loop/bug-r8-extend-face-concave`
> @ `ed35c781`（自 main `b318c17a` 拉）。验收日期：2026-11-06。
> **总判定：PASS（附 1 项环境性阻塞子项，待主控裁定）——不合入、不打勾，收尾归主控。**

## 一、逐项判定表

| # | 验收项 | 判定 | 证据 |
|---|---|---|---|
| 1 | diff 面复核 | **PASS** | `git diff main..分支 --stat` 亲跑：产品代码恰为 `src/draw_brush/extend_face.rs`（+333/−3），其余为程序归档证据（`loop/bug-r8/` 5 日志 + 报告），无越界 |
| 2 | 门禁三连 QA 亲跑 | **PASS** | `loop/bug-r8-qa/qa-gate-{fmt,clippy,libtests}.log`：fmt exit 0 / 0 行；clippy exit 0 / 全文 8 行无 warning-error；libtests exit 0、**59 二进制、3122 通过 / 0 失败**（=3117+5），`... FAILED` 行数 0，5 条新测试全 ok，逐行复核 |
| 3 | 红绿独立复核（方法 a） | **PASS** | 摘除两处守卫后复红（`qa-red-repro.log`：2 concave 测试 FAILED，实际 6 面凸体 vs 期望 9 面 L）；还原后复绿（`qa-green-repro.log`：5/5） |
| 4 | 源码级专项复核 | **PASS** | 见第三节 |
| 5 | 真机腿 | **PASS，附环境性阻塞子项** | 见第四节；零副作用/模式保持/cancelled 断言成立；toast/凸锚两子项被工具层阻塞，以 headless user-path 全链探针补证 |
| 6 | QA 报告 | **完成** | 本文件 |
| 7 | 证据提交 | **完成** | `loop/bug-r8-qa/` + 本报告 commit 到分支；不合入 main；fixture 临时改动零残留（scene.bsn SHA256 跑前跑后一致 `2f489e1c…`） |

## 二、门禁三连明细

| 门 | 命令 | exit | 全文复核 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | 0 | 0 行输出 |
| Lint | `cargo clippy --workspace -- -D warnings` | 0 | 8 行，无 warning/error 行 |
| 单测 | `cargo test --workspace --lib` | 0 | **59 个 unittests 二进制**、59 行 `test result: ok`、**passed_total=3122 failed_total=0**（=R7 后基线 3117+5）；`grep '\.\.\. FAILED'` 命中 0；日志中的 failed/error 字样均为测试名与测试注入的预期日志（全部 `... ok` 结尾） |

新测试 5 条（`draw_brush::extend_face::extend_face_tests`）全部 ok：
concave refusal（面/顶点逐位不变+undo 0+toast×1）、rotated-concave refusal、
convex anchor（undo 恰一条+确实重建+无 toast）、convexity helper L-vs-cuboid、
eps 边界（0.5x/10x EPSILON）。

## 三、源码级专项复核（亲读结论）

1. **`brush_is_convex` 本地空间判定正确**（extend_face.rs:243-249）：逐顶点跑
   `point_inside_all_planes`（任一顶点落在任一 face plane 正侧外即非凸）——凹体的
   hull 角必戳出 re-entrant 面，判定数学成立。**rotated 笔刷无需 world 换算的依据
   （刚体变换不变性）成立**：`faces` 与 `topology.vertices` 同处笔刷本地空间，点-平面
   带符号距离在旋转+平移下不变（`dot(Rn, Rp+t) + d_l − dot(Rn,t) = dot(n,p) + d`），
   在哪个刚体变换后的空间判结果都相同；非均匀 scale 不参与（impl 丢弃 scale）。
   eps=`jackdaw_geometry::EPSILON`=1e-4（lib.rs:42），与凸范式内部容差及 extend 既有
   no-op 对比一致——凸笔刷浮点残差不会误判为凹。
2. **双重守卫位置**：operator 入口守卫（152-158 行）位于 resolve（两入口汇合点）之后、
   **Face 模式退出（161-164 行）之前**——拒绝路径 warn+queue toast+`return None`，
   不触碰 `edit_mode`/`brush_selection`/不 queue impl，零副作用亲读确认（Object 分支
   的 hover raycast 只读无副作用）。impl 深防御守卫（299-303 行）位于 `world_faces`
   构造（315 行）之前、`old_brush.clone()` 之后——生产路径 operator 已先拒，不存在
   双 toast。两守卫各自独立可拒。
3. **plane-only legacy 笔刷放行语义正确**：topology 空（无 authored 顶点）时 `all()`
   空真→判凸放行；此类笔刷形状即半空间交集、凸由构造保证，凸重建无损，注释（241-242
   行）与实现一致。
4. **`toast_brush_notice` 与原型逐行一致**：与 `crate::terrain::toast_terrain_notice`
   （terrain/mod.rs:499-517）逐行比对——EditorFont/IconFont 提取、双 Some else 静默
   no-op（headless guard）、`ToastVariant::Error` + `DEFAULT_TOAST_DURATION`（3s），
   「本地原样镜像」声明属实。文案常量含「concave」语义与 Extend 拒绝义（断言③文本面）。
5. **改动面附加核对**：`brush_query` 由 `Query<(), With<Brush>>` 加宽为 `Query<&Brush>`
   ——`contains` 语义不变（均=实体有 Brush 组件），新增 `get` 只读；`can_run_extend_face`
   未动（凹笔刷仍显示可用，调用时拒绝并提示，非静默灰掉）。`extend_face_to_brush_impl`
   全库调用点唯一（operator 内一处 + 测试直调），单点安置成立，方案书补遗条款未触发。

## 四、真机腿（编辑器实跑）

环境：`tests/fixtures/bsn_game`（无 jackdaw.toml，Open without setup 路径），port 15703，
1920x1080，不存盘策略（scene.bsn SHA256 `2f489e1c…` 跑前跑后一致）。驱动复用 R7 QA
沉淀（`entity.add.cube` ×3 + nudge 摆位 + `brush.csg_subtract` 构造 L，
`brush.selection.set_faces` 置面）。全记录：`loop/bug-r8-qa/r8qa-console.log` +
`r8qa-editor.log`（info）+ `r8qa-editor-debug.log`（debug）。

### 4.1 成立的断言

- **断言①-拒绝应答**：armed 状态下 `brush.extend_face_to_brush` 结构化应答
  `"result": "cancelled", "warnings": []`（Face 入口，多轮复现）。
- **断言①-零副作用**：拒绝前后 L 的 BSN **逐位相同**（faces=9/verts=14，
  `bsn_identical=True`，基线/事后快照归档），undo **零新增**（`undo_delta=0`，栈顶
  不变），L 全程未被凸化——「凹笔刷不被 Extend 毁掉」的终态行为在真机成立。
- **断言①-模式保持**：同场对照-实验法（leg1b）——「set_faces→PageUp（无 extend 对照）」
  与「set_faces→extend（拒绝）→PageUp」行为逐位一致（face0 顶点世界 +0.25、其余不动、
  translation +0.125 重基形态）→ 拒绝调用未改变 Face 模式/BrushSelection 状态；亦证明
  set_faces 的 Face 状态真实生效（PageUp 面 nudge 工作）。
- **Object 入口 resolve 成功**：leg1g（armed Face→视口点击触发 remembered-face 保存→
  补选 [C,L] 使 primary=L→Ctrl+E）extend 应答 `finished`——Object 分支可达（impl
  因同一实体链问题静默早退，见 4.3）。

### 4.2 环境性阻塞（toast/凸锚两子项，待主控裁定）

**守卫的 warn! 与 toast 在真机七轮（leg1/1b/1c/1d/1e/1f/1g）均未出现**，凸锚（leg2）
同样 cancelled+零变化。取证链（全部归档）：

1. debug 日志证明 **operator 体已执行**（`OPERATOR: brush.extend_face_to_brush` 行，
   该行只在 availability+modal 检查通过且系统执行后打）且 **availability 通过**
   （无 `Availability check failed` 行；同日志其它 operator 的失败均有记录）；同状态
   sandwich 查询 `available=true`。
2. `return None` 发生在 operator 体 resolve 段（`active_brush.filter(contains)?` /
   `sub.faces.last()?` / `targets.is_empty()` 三点之一），非守卫（守卫必 warn）。
3. dispatch 层的 `Availability check failed` 分支返回 `Ok(Cancelled)`（operator.rs
   646 行），与 operator 体 None 应答同形——排除了「cancelled=availability 失败」的
   另一种解释后，锁定 resolve 段。
4. **凸笔刷同样 cancelled**（leg2：D=新 cube+正对面墙 E，set_faces finished→extend
   cancelled、几何零变化）——与凹凸无关。
5. headless 探针复现同族问题：`brush.selection.set_faces` 的 entity 参数经 run_ops
   文本路径（Int bits→`Entity::try_from_bits`）**Cancelled**（无法命中实体）。
6. 结论：**真机 BRP 实体参数链存在深层错位**（`loop/qa/manual.md` §7.5「bevy BRP 与
   jackdaw BRP 实体格式不同构」的同族更深形态），使 set_faces-armed 的 Face 状态与
   Selection 中实体在 extend 的 resolve 读到的不是同一实体，resolve 静默 None。
   **pre-fix 代码在同一链上同样不会执行重建**（同样 cancelled）——该阻塞与本票修复
   无关、非本票引入，且超出本票红线（不碰 BRP/工具层），按清单条款如实报
   **环境性阻塞待主控裁定**（建议立票：修 BRP 实体参数链，或裁定 headless user-path
   全链为 extend 类 operator 的等价真机验收通道）。

### 4.3 headless user-path 全链探针（阻塞下的补证，临时测试已删还原）

以 guards 框架 `run_op_clause_as_user`（按钮/键绑同一 dispatch 路径）复刻真机状态
（BrushEdit(Face) + active_brush=L + faces=[0] + selection=[L,Wall]）：

```
PROBE edit_mode=BrushEdit(Face)
PROBE active_brush=Some(..) faces=Some([0]) selection=[L,Wall] all_have_brush=true
PROBE is_available=true
WARN: Extend to Brush refused: the primary brush is concave, and the extension
      rebuilds the brush as the intersection of its face planes, which would
      collapse it into a convex hull.
PROBE operator result=Ok(Cancelled)
PROBE faces_after=9 (before 9)
PROBE undo_len=0
PROBE toasts=1
```

**守卫触发、拒绝文案（断言③文本面：含 concave 语义+拒绝义）、Cancelled、几何逐位
不变、undo 零、EditorToast spawn 1 个——修复语义在 operator 全链上成立**（真机截图
`r8qa-leg1f-toast-window.png` 为无 toast 状态留档；toast 视觉确认未取得，属 4.2 阻塞）。

### 4.4 凸回归锚（断言②）的替代证据

真机凸锚被 4.2 同一阻塞挡死；凸路径回归由三层既有证据承担：单元锚
`extend_still_rebuilds_a_convex_primary`（绿：undo 恰一条+确实重建+无 toast）、
guards `record_counts::the_extend_face_keybind_is_one_user_entry`（凸笔刷 operator
全链可用性→dispatch→undo 一条→undo 恢复，零回归）、以及源码层凸路径行为未触碰
（diff 只加守卫，重建尾段逐行未动）。

## 五、A27/A28 裁定执行情况

- **A27**（凸笔刷斜墙退化几何=既有缺陷不阻断）：QA 凸锚目标用无旋转正对面墙
  （opposing 回退路径），全程未构造斜墙、未触碰 A27 形态 ✓。
- **A28**（stage 套件 7 用例预存失败）：本票门禁不含 stage 套件（`--workspace --lib`
  不涉及），未跑未判 ✓。

## 六、偏差清单（单列，如实）

1. **真机 toast 断言未达成**（断言①③的 toast 部分）：环境性阻塞，见 4.2；以 headless
   user-path 全链探针补证（toasts=1）+ 文案源码/warn 亲读（断言③文本面成立）。
2. **真机凸锚断言②未达成**：同一阻塞；以单测锚+record_counts 全链+diff 面未触碰凸
   路径三层替代证据。
3. **PageUp 行为链与 R7 记录形态不同**（本地重基：translation+0.125、face0 顶点局部
   +0.125、其余局部−0.125，世界结果=面 +0.25）：未按 R7 的「顶点多集 +0.25」形态
   直接判读，改用对照-实验同场设计（唯一变量=extend 拒绝调用），转化为 Face 模式保持
   断言的有效证据（对照=实验逐位一致）。
4. **headless 探针临时测试**（`tests/guards/qa_r8_probe.rs` + main.rs 一行注册）在
   排障期使用，跑完即删并还原，不属产品代码改动；`git status` 确认仓库干净。
5. **leg1g 的 extend=finished 但 impl 静默早退**（Object 入口 resolve 成功、impl 无
   warn/无 undo/几何不变）：与 4.2 同族实体链错位的另一表现，记录在案。
6. 程序腿报告偏差 1-5（红证取得方式、测试构造定位、凸笔刷斜墙现状=A27、QA 提示、
   红线遵守）复核属实，无新增异议。

## 七、结论

**PASS（附 1 项环境性阻塞子项待主控裁定）。** R8 修复（凹笔刷 Extend 拒绝+提示）
在门禁三连、红绿独立复核、源码级复核、headless operator 全链（用户路径）上全部成立；
真机腿上「凹笔刷不被凸化」的终态行为成立（零副作用），toast/凸锚两子项被真机 BRP
实体参数链的既有工具层问题挡死（pre-fix 同链同样不可达，非本票引入），按清单条款
如实报环境性阻塞，**待主控裁定**（建议立票修实体参数链或裁定 headless user-path
全链为等价验收通道）。

**不合入、不打勾，收尾归主控。**
