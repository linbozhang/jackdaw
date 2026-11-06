# R8 QA 证据清单（loop/bug-r8-qa/）

验收对象：分支 `loop/bug-r8-extend-face-concave` @ `ed35c781`（自 main `b318c17a` 拉）。
报告：`loop/reports/bug-r8-qa.md`。

## 门禁三连（QA 亲跑，全文复核）

| 文件 | 内容 | 结果 |
|---|---|---|
| `qa-gate-fmt.log` | `cargo fmt --all -- --check` | exit 0，0 行 diff |
| `qa-gate-clippy.log` | `cargo clippy --workspace -- -D warnings` | exit 0，全文 8 行无 warning/error |
| `qa-gate-libtests.log` | `cargo test --workspace --lib` | exit 0；59 个 unittests 二进制、59 行 `test result: ok`、passed=3122 failed=0（=基线 3117+5）；`... FAILED` 行数 0；5 条新测试（extend_face_tests）全部 ok |

## 红绿独立复核（方法 a：摘除守卫复红→还原复绿）

| 文件 | 内容 |
|---|---|
| `qa-red-repro.log` | 临时摘除 operator 入口守卫 + impl 深防御后 `cargo test --lib extend_face_tests`：2 个 concave 测试 FAILED（实际 6 面凸体 vs 期望 9 面 L），凸锚/helper 测试仍绿——凹笔刷被凸化的缺陷真实存在 |
| `qa-green-repro.log` | `git checkout` 还原源码后复跑：5/5 绿 |

## 源码级复核

亲读 `src/draw_brush/extend_face.rs`（守卫位置/本地空间判定/plane-only 放行/toast 镜像），
比对 `crates/jackdaw_geometry/src/lib.rs`（`point_inside_all_planes`、`EPSILON=1e-4`）与
`src/terrain/mod.rs`（`toast_terrain_notice` 逐行一致）。`extend_face_to_brush_impl`
全库调用点唯一（operator 内一处 + 测试）。

## 真机腿（编辑器实跑，七轮 + debug 日志编辑器）

- 编辑器：`tests/fixtures/bsn_game`（Open without setup），port 15703，1920x1080；
  fixture `scene.bsn` SHA256 跑前跑后一致 `2f489e1c…`（不存盘策略，零污染）。
- 驱动脚本：`qa-r8-boot.sh`（boot）、`qa-r8-legs.py`（leg1/leg2）、`qa-r8-leg1b.py`、
  `qa-r8-leg1c.py`、`qa-r8-probe1.py`、`qa-r8-leg1f.py`（inline 脚本见 console log）。
- 控制台全记录：`r8qa-console.log`；编辑器日志：`r8qa-editor.log`（info 级）、
  `r8qa-editor-debug.log`（debug 级，含 `OPERATOR:` 事件行）。

### 成立的断言

- **operator 应答**：`brush.extend_face_to_brush` 结构化应答 `"result": "cancelled"`（Face
  入口，凹 L）——`r8qa-console.log` leg1b/1c/1f 段。
- **零副作用**：拒绝前后 L 的 BSN 逐位相同（faces=9/verts=14，`r8qa-leg1*-baseline/
  after*.bsn.txt` 对比 `bsn_identical=True`）、undo 零新增（`undo_delta=0`，top 保持）。
- **Face 模式保持**（同场对照-实验法，`qa-r8-leg1b.py`）：set_faces→PageUp（无 extend
  对照）与 set_faces→extend（拒绝）→PageUp 的行为逐位一致（translation +0.125 重基形态、
  face0 顶点世界 +0.25、其余顶点不动）——拒绝调用未改变 Face 模式/BrushSelection 状态。
- **set_faces 状态真实生效**：PageUp 面 nudge 生效证明 EditMode=Face + faces=[0] +
  active_brush 全部写入成功。
- **Object 入口**：leg1g（armed Face→视口点击→补选 [C,L]→Ctrl+E）extend 应答
  `finished`——Object 分支 resolve 成功（但 impl 静默早退，见阻塞章节）。

### 未达成（环境性阻塞，待主控裁定）

- **真机 toast 断言**（断言①③的 toast 部分）：七轮（leg1/1b/1c/1d/1e/1f/1g）覆盖
  Face/Object 双入口、BRP call_operator/Ctrl+E 键盘双通道、info/debug 双日志级——守卫
  的 `warn!` 与 toast 均未出现。debug 日志证明 operator 体已执行（`OPERATOR:
  brush.extend_face_to_brush`）且 availability 通过（无 `Availability check failed`
  行），`return None` 发生在 resolve 段；凸笔刷 leg2 同样 cancelled+零变化，证明与凹凸
  无关，是 **BRP 实体参数链在真机上的深层错位**（`loop/qa/manual.md` §7.5「bevy BRP 与
  jackdaw BRP 实体格式不同构」同族的更深形态）。headless 探针（下节）证实同一批实体参数
  经 run_ops 文本路径（Int bits→`Entity::try_from_bits`）无法命中实体——
  `set_faces` Cancelled 复现。
- **真机凸回归锚**（断言②）：同一阻塞，凸笔刷 extend 在真机同样 cancelled+零变化
  （`r8qa-console.log` leg2 段）。

### headless 探针（tests/guards/qa_r8_probe.rs，临时文件已删还原）

以 guards 测试框架（`run_op_clause_as_user`，按钮/键绑同路径）复刻真机状态：

```
PROBE edit_mode=BrushEdit(Face)
PROBE active_brush=Some(..) faces=Some([0]) selection=[L,Wall] all_have_brush=true
PROBE is_available=true
WARN jackdaw::draw_brush::extend_face: Extend to Brush refused: the primary brush is concave, ...
PROBE operator result=Ok(Cancelled)
PROBE faces_after=9 (before 9)
PROBE undo_len=0
PROBE toasts=1
```

**守卫触发、warn 文本、Cancelled、几何逐位不变、undo 零、EditorToast spawn 1 个——
修复语义在 operator 全链（用户路径）上全部成立。**

## toast 文案（断言③，headless 证）

`CONCAVE_EXTEND_REFUSAL`（src/draw_brush/extend_face.rs）与 headless warn 输出一致：
"Extend to Brush refused: the primary brush is concave, and the extension rebuilds the
brush as the intersection of its face planes, which would collapse it into a convex
hull."——含「凹/concave」语义与 Extend 拒绝义。真机截图（toast 过期未捕获）：
`r8qa-leg1f-toast-window.png` 等为当时窗口留档（无 toast）。

## A27/A28 裁定执行情况

- **A27**（凸笔刷斜墙退化几何）：QA 凸回归锚避开斜墙——leg2 目标为无旋转正对面墙
  （opposing 回退路径，无 angled 斜墙），未触碰 A27 形态 ✓。
- **A28**（stage 套件 7 用例预存失败）：本票门禁不含 stage 套件，`--workspace --lib`
  不涉及 ✓。
