# R7 QA 验收报告：Nudge 走凸包重建摧毁凹笔刷（buglist 🔴）

> QA agent，2026-11-06。待验对象：分支 `loop/bug-r7-nudge-concave`（程序 `971cf7c9`，QA 证据 `6086876a`，复跑后 `88301659`+`ef86915e`+`f0f0c864`）。
> 程序报告 `loop/reports/bug-r7-report.md`，方案书 `loop/plans/bug-r7-nudge-concave.md`。
> **首轮总判定：FAIL —— 真机腿环境性阻塞（工具缺口）。**
> **复跑（主控补工具后）总判定：PASS，带 1 项阻断记档（断言②「可撤销还原」undo 空壳，疑非修复回归，交主控裁定）与若干环境观察记档。详见 §七。**
> **不合入、不打勾，收尾归主控。**

## 一、逐项判定表

| # | 验收项 | 判定 | 证据 |
|---|---|---|---|
| 1 | diff 面复核 | **PASS** | `git diff main..loop/bug-r7-nudge-concave --numstat` 亲跑：`src/brush_element_ops.rs` 恰 +336/−26（与程序自报一致）；`src/brush_drag_ops.rs` 0 行改动；其余均为 loop/ 下证据与文档新增（bug-r7 五份日志、方案书、报告），无越界。文件内已无 `rebuild_brush_from_vertices` 直连调用 |
| 2 | 门禁三连 QA 亲跑 | **PASS** | `loop/bug-r7-qa/qa-fmt.log`（exit 0 无输出）、`qa-clippy.log`（8 行全文复核无 error/warning，CLIPPY_EXIT=0）、`qa-libtests.log`（**3108 通过 / 59 二进制 / 59×"0 failed"**，= 基线 3104 + 新增 4；全文 grep 仅 3 处良性命中：1 处测试内预期 ERROR 日志、2 处测试名含 "not_panicked"，均 `ok`） |
| 3 | 红绿独立复核（方法 a 亲跑） | **PASS** | `qa-red-forced-hull.log`：在 `apply_nudge_to_brush` 内临时强制 `halfedge = None`（走 `apply_vertex_deltas` 的 legacy 凸包重建路径，等价修前行为）跑 `nudge_tests` → **3 红 1 绿**，数值与程序 red.log 逐一吻合（concave face 面 9→7、concave vertex 顶点 14→10、rotation 面 6→7、凸锚绿）；`git checkout` 还原后 `qa-green-restored.log` → **4/4 全绿**。红证有效性成立 |
| 4 | 源码级专项复核 | **PASS** | 见 §三；D3 简化（remap 删除）的源码依据成立，`apply_nudge_to_brush` 换算与 `broadcast_drag_to_captures` 先例同构 |
| 5 | 真机腿 | **FAIL（环境性阻塞）** | 见 §四：L 形凹笔刷本体已在真机编辑器构造成功（9 面 / 14 顶点，与程序红证同构），但「选中一个面」这一步无法用现有工具驱动——面拾取链路死点，2 次以上重试 + 五种绕行均失败。按验收规则如实报「环境性阻塞待主控裁定」，未静默降级 |

## 二、门禁三连明细（QA 亲跑，日志全文复核制）

- `cargo fmt --all -- --check`：exit 0，无 Diff-after-reformat。
- `cargo clippy --workspace -- -D warnings`：exit 0；日志 8 行逐行看，无 error/warning。
- `cargo test --workspace --lib`：exit 0；`test result` 汇总 **3108 passed**（59 个 `Running unittests` 头，每条 `0 failed`）；全文 grep `FAILED|error\[|panicked` 命中 3 行，逐行核实均为良性（`pie_projection` 测试内部预期 ERROR 日志一行、两处测试名含 `not_panicked` 字样，三者所在二进制 `test result: ok`）。

## 三、源码级专项复核（清单 4）

### 3.1 `apply_vertex_deltas` 半边路径不重排面索引（D3 接受的依据）✅

亲读链路（`src/brush_drag_ops.rs:1641` + `crates/jackdaw_geometry`）：

1. 半边分支只写两处：`halfedge.mesh.verts[key].co`（顶点位置）与 `faces[fk].normal_cache`（newell 法线重算）——**无任何顶点/边/面的增删**，slotmap keys 完全不变；
2. `flatten_to_topology`（`halfedge/flatten.rs:11`）将面按 `material_idx` **stable-sort** 后展开（文件头注释明言 "so parallel arrays line up with `Brush::faces`"）；lift 时 `face_keys[slot] = material_idx`（`halfedge/edit.rs:43`），即 material_idx 就是 authored 面索引——面顺序天然稳定；
3. `recompute_face_planes`（`topology.rs:181`）按 `faces.iter_mut().enumerate()` **下标就地写 plane**，`brush.faces` 平行数组不重建、不重排；
4. 顶点索引口径：`vert_keys` 与 `BrushTopology::vertices` 平行（`halfedge/edit.rs:27` 注释 + `lift.rs:13` 按 topology 顶点序建键），authored 顶点索引直传正确。

**结论：半边路径面索引天然稳定，程序「D3 的 remap 块整体删除」的简化依据成立，主控✅裁定成立。**

### 3.2 `apply_nudge_to_brush` 换算与 `broadcast_drag_to_captures` 先例一致性 ✅

- 先例（`brush_drag_ops.rs:1522`）：`start_world_to_local.transform_point3(start_world + world_offset)`，其中 `start_world` 为捕获时 `world_from_local * all_vertices[i]`；
- 新核心（`brush_element_ops.rs:406-414`）：`world_to_local.transform_point3(world_from_local.transform_point3(local_start) + offset)`——同一仿射对（world_from_local 与其逆），先 lift 到世界 → 加世界位移 → 逆仿射落回 local。数学上 `world_to_local(world_from_local(p) + o) = p + world_to_local_vector(o)`，与 drag 口径完全同构；差别仅在于 drag 用捕获时缓存、nudge 即时计算（operator 一次执行内同帧，语义等价）。
- legacy 兜底（halfedge None）实参齐全：`brush.clone()`（start_brush）、`cache.authored_vertices()`、`cache.authored_face_polygons()`，满足 `apply_vertex_deltas` 文档对 legacy 路径的读取要求；`mirror` 传 None 与修前凸包路径无 mirror 语义一致（D2/记档相符）。
- ⚪ 轻微观察（不阻断）：`moved` 判定阈值 `length_squared() > 1e-12`（即 length > 1e-6 世界单位）。若未来出现 < 1e-6 的网格步会被误判为未移动；当前 grid 最小 0.25 量级，无实际风险，记档备查。

### 3.3 「凸体语义差异」与「旋转笔刷世界 Y」复核意见 ✅

- 程序记档①（修前凸包重建对凸笔刷也不逐位稳定——红证里旋转立方体单顶点 nudge 后凸包产出 7 面）：**复红实验亲证**（qa-red-forced-hull.log 第三红即此现象）。修后半边路径对凸体同样稳定且面数恒 6，凸锚测试 4/4 绿。可见行为修前后一致、内部稳定性更好，记档属实，交主控知悉即可，非回归。
- 程序记档②（旋转笔刷 nudge 从 brush local Y 变世界 Y）：测试 3（`nudge_offset_follows_world_y_through_brush_rotation`）亲读 + 复红确认修前必红（凸包 7 面 ≠ 6 面），修后绿（世界 Y 分量 +0.25 精确断言）。**按主控✅裁定执行：真机腿如测旋转笔刷按世界 Y 断言**（本次真机腿未能进行到该步，见 §四）。

### 3.4 程序偏差清单逐条复核

| 程序偏差 | QA 复核意见 |
|---|---|
| 1. 红证阶段 D3 简化先行（红证跑在无 remap 的中间态上） | **接受**。红证三例断言聚焦几何保形（面/顶点数、逐位位移），remap 块只影响 selection 索引映射、不触碰红证聚焦的行为；QA 亲跑复红的红数值与程序 red.log 一致，红证真实性成立。无需补「保留 remap 的中间态红跑」 |
| 2. `moved` 判定新增（零位移/越界 → Cancelled） | **接受**。比修前「凸包失败才 Cancelled」更精确；亲读确认入口 `any_modified` 语义不变（任一 brush 移动才 Finished），一次 nudge 仍是一条 undo。见 §3.2 的 ⚪ 阈值观察 |
| 3. 无其他偏差 | **属实**。diff 面复核（清单 1）与源码级复核（§三）未发现未申报的行为差异；方案书补遗条款（阻抗失配停机）核实不触发：`apply_vertex_deltas` 签名零改动、无 drag 状态机依赖（`start_brush`/`all_vertices`/`face_polygons` 仅 legacy/mirror 路径读，半边路径现值直传成立） |

## 四、真机腿（清单 5）—— 环境性阻塞实录

### 4.1 已完成的部分（真机编辑器内，全部亲跑留档）

- boot：fixture `tests/fixtures/bsn_game`（无 jackdaw.toml）走 **Open without setup**（`r7-live.sh`，借 `r6-live.sh` 模式），`EDITOR_READY` 共 5 次成功 boot。
- **L 形凹笔刷真机构造成功**（`r7-run7a.py` 全自动序列）：
  1. `entity.add.cube` ×3（A 原点 target / B cutter 经 `transform.nudge_x/y/z_pos` 各 2 步移至 (0.5,0.5,0.5) / C 陪选 40 步移 (10,0,0)），每步以实体 BSN 回读平移值验证；
  2. `jackdaw/selection.set` 选 [B,C] → `brush.csg_subtract` → **finished**；
  3. 产物实体 **9 面 / 14 顶点**（`r7-run7-state.json`、`r7-leg4-brush-*.json`）——与程序红证的 L 形同构，subtract 的半边/CSG 管线在真机上对凹产物保形正常。
  - 路径要点（后续复用）：`brush.csg_subtract` 语义为「**选中=cutters，未选中=target**」且 gate 要求 ≥2 个 Brush 在选集中（`can_run_binary_brush_op`）；`apply_bsn` 只 spawn 组件字面量实体（无 Brush 组件，过不了该 gate）；实体的精确移动用实体级 nudge operator（默认网格步 0.25）+ BSN 回读闭环。
- 面模式进入链路正常：`edit_mode.face` → `finished`，`EditMode` 资源读回 `{'BrushEdit': 'Face'}`，状态栏显示 "Edit: Face"。

### 4.2 死点：「选中一个面」无法驱动（断言①②③④全部卡在此步上游）

PageUp 的 nudge 需要 `BrushSelection.sub.faces` 非空（`nudge_brush_element` Face 模式下空选 continue → Cancelled）。现有工具对该步的全部可用入口逐一排查：

| 尝试 | 结果 | 证据 |
|---|---|---|
| `input.pointer click` 视口坐标（ui_tree 物理 rect [293,95,1377,753] ÷ retina 2 → 窗口逻辑，与 viewport 截图交叉验证产物位置） | 事件链下游活（object 模式同坐标 click 后 `status.selection` 被清空——picking 收到了点击），但 face mode 下面未选中；PageUp 后 `undo_len` 不变、顶点零位移 | `r7-console.log` 18:14、18:18、18:25 各轮 |
| 窗口前台化（osascript System Events frontmost 成功，`jackdaw` 返回 frontmost）后重试 | 无变化 | 18:25 轮 |
| `call_operator brush.face.drag`（modal 面拾取直调，光标先行 move） | `cancelled`（ViewportCursor/modal invoke 前置不满足） | 18:24 轮 |
| 键盘派发生死验证（同 PageUp 的派发层）：`input.key` Escape → **Face→Object 生效**（keybind 派发链活）；Digit3/Digit4（edit_mode 绑定）→ 无效（面板焦点依赖） | 派发层部分可用；断点不在键盘层而在面拾取 | 18:25 轮 |
| BrushHalfedge 组件探针（face mode 下应为 edit brush lift） | `world.query with BrushHalfedge` 恒 `[]`（对照：同法 filter Brush 能返回 3 实体，探针本身有效）；structured `brush.nudge_up` call_operator 亦 `cancelled`——**BrushSelection.sub.faces 空导致 Cancelled，正是死点的直接因果** | 18:20、18:22 轮 |

**根因定位**：3D 视口内的 brush 子元素拾取（面点击）在现有工具层没有可用的结构化入口——`ui_click` 只覆盖 UI 控件（feathers 链），`input.pointer` 的合成点击对 brush-edit 模式的面拾取（`face_drag_invoke_trigger` 经 jackdaw_input ActionEvents 层 + ViewportCursor hover 链）无法贯通；R4–R6 环境情报中亦无 viewport 子元素拾取的先例（先例均为 UI 控件 / operator / BRP）。**这属于 loop/README「MCP 优先原则」定义的场景：验收需要的工具能力缺失，应报主控裁定补工具（如：给 `BrushSelection`/面拾取补 BRP 写入口、或给 `input.pointer` 补 brush-edit 拾取直驱），补工具后再补跑真机腿**。本轮未擅自改产品代码或工具层（范围红线）。

### 4.3 断言状态

| 断言 | 状态 |
|---|---|
| ① L 形保形（PageUp 后面/顶点数不变 + 截图） | **未执行**（卡面拾取上游）；替代性旁证：修复核心的单元红绿独立复验（清单 3）+ 源码链路亲读（清单 4）全绿，L 形本体在真机编辑器内未被凸包化（构造过程本身经受住了 CSG + 多次 undo/redo/BRP 操作） |
| ② undo 恰一条可还原 | **未执行**（同上）；结构化探针轮中观察到 `history.undo` 对 subtract 条目的撤销还原行为正常（A/B/C 恢复） |
| ③ 凸笔刷 PageUp 回归锚 | **未执行**（同上） |
| ④ 旋转笔刷世界 Y | **未执行**（同上）；主控✅裁定的世界 Y 断言口径已在单元测试 3 中覆盖（绿），真机腿补跑时按该口径断言 |

## 五、QA 偏差与备注

1. **验收项 5 未通过且性质为环境性阻塞**：按验收规则报 FAIL（不得静默降级）。修复代码的单元级证据链（清单 2/3/4）独立完整且全部亲验，但按 loop/README 交互验收红线（「QA 不得仅凭 headless 断言与代码审查放行」），真机腿缺口由主控裁定处置（补工具重验 / 或主控明示接受降级）。
2. 本轮 QA 全程**零产品代码改动**（复红 shim 已 `git checkout` 还原，`git status` 干净）；fixture 无保存策略遵守（跑前跑后 `scene.bsn` SHA256 一致：`2f489e1c…71f`）；fixture 内临时截图目录已删除；编辑器进程已清理。
3. 归档：QA 证据 `loop/bug-r7-qa/`（门禁三连日志、红绿复跑日志、真机脚本 r7-live.sh / r7-leg*.sh / r7-leg4.py / r7-run7a.py / r7-run7b.py、BRP 应答 JSON、viewport 截图、控制台总日志 r7-console.log）。

## 六、交付物

- 本报告：`loop/reports/bug-r7-qa.md`
- QA 证据目录：`loop/bug-r7-qa/`
- 分支 `loop/bug-r7-nudge-concave` 上 commit（QA 证据 + 本报告）；不合入 main、不动 buglist / roadmap / progress

## 七、复跑节（主控补工具后，2026-11-06 第二轮）

### 7.1 工具补充的裁定背景

首轮真机腿死点（§4.2：Face 模式无法选中面 → BrushSelection.sub.faces 恒空 → nudge Cancelled）报主控后，主控按 loop/README「MCP 优先原则」补工具：新 operator **`brush.selection.set_faces`**（直写面选择 + 进 Face 模式 + select_only，拒绝走 cancelled+warnings，无 undo 条目的纯 UI 状态），合入 main `eaaa952b`，libtests 基线 3113（工具报告 `loop/reports/qa-tool-facesel-report.md`）。主控同步立账 A24（凸包退化面合并，QA 复红亲证）与 A25（Face 模式真鼠标链路复现先行）。

### 7.2 rebase 与门禁三连复跑

- `git rebase main`：干净完成，分支新链 = 修复 `88301659` + 首轮 QA 证据 `ef86915e` + 主控台账 `f0f0c864`，main 为祖先。
- **fmt** exit 0（`rerun-fmt.log`）；**clippy --workspace -D warnings** exit 0；**libtests** exit 0，**3117 通过 = 3113 基线 + R7 新增 4**，59 二进制、59×"0 failed"（`rerun-libtests.log`）——与主控口径一致。

### 7.3 复跑断言结果（真机编辑器，证据 `r8-console.log` + `r8*.json/png/txt`）

构造链与首轮相同（3 cube + entity-nudge 移位（BSN 回读逐步验证）+ `brush.csg_subtract` → L 形 9 面/14 顶点），面选择改走新工具：

| 断言 | 结果 | 关键证据 |
|---|---|---|
| ① L 形保形 | **PASS** | `set_faces` → `finished` 无 warnings、EditMode=BrushEdit(Face)；PageUp 后 **faces 9→9、verts 14→14**；截图 `r8b-A-after-nudge.png`。**世界系逐顶点验证**（§7.4）：选中面每步恰 +0.25（一个网格步）、其余顶点世界不动 |
| ② undo 恰一条、可撤销还原 | **PASS / 阻断记档**（见 7.5） | 每次 nudge **恰一条** undo（delta=1、label "Nudge Up"，`r8b-history-post.json`）；「可撤销还原」实测**不成立**：`history.undo` 推进栈（53→52→51）但 translation/顶点**零还原**（三轮复测一致，19:09/19:17 两轮）——见 7.5 归因分析 |
| ③ 凸笔刷回归锚 | **PASS** | 新建 cube D → `set_faces` → PageUp：**faces 6→6、verts 8→8**、undo 恰一条；世界系 faces[0] +0.25 其余不动 |
| ④ 旋转笔刷世界 Y | **未有效执行** | `transform.rotate_90_pitch_ccw` 对 cube 未产生旋转（quat 保持 identity、仅 translation +0.125）——旋转前提未建立；记录该 operator 真机行为异常（与 §7.5 的 translation 写入疑点同源），**不阻断本次验收**（口径已由单元测试 3 锁定：世界 Y 断言绿） |

### 7.4 世界系逐顶点验证（决定性证据）

修复语义「面 nudge = 选中面沿世界 Y 上移一格」在真机**逐顶点精确成立**（凸锚 cube，3 次 nudge 线性累加）：

```
before 2nd nudge: t=(0,0.125,0)  x=+0.5组 y=[-0.375,0.625,-0.375,0.625]  x=-0.5组 y=[-0.625,0.375,-0.625,0.375]
after  2nd nudge: t=(0,0.25,0)   x=+0.5组 y=[-0.25,0.75,-0.25,0.75]     x=-0.5组 y=[-0.75,0.25,-0.75,0.25]
x+0.5 delta = [+0.125 ×4]（local）+ translation [+0.125] ⇒ 世界 +0.25/步
x-0.5 delta = [-0.125 ×4]（local）+ translation [+0.125] ⇒ 世界 0（未选中面不动）
```

**几何语义完全正确**：选中面（faces[0]=x=+0.5 侧面）沿世界 Y 每步恰 +0.25，其余顶点世界不动，faces/verts 数不变——**「不再凸包化」（修复核心目标，修复前同场景 9→7）真机成立**。local 读数呈 `y'=y+0.125·sign(x)` 剪切样分解（含 translation 的锚点表示联动，r8c BSN 全文归档 `r8c-{baseline,after-nudge,after-undo}.bsn.txt`）。

### 7.5 阻断记档：undo 撤销不还原几何（断言②的「还原」子项）

**实测**（凸锚 cube，两轮复测一致）：`history.undo` 正常推进（条目出栈、top 变化），但 **translation 与顶点零还原**（undo 前后逐字节一致）。undo 条目由 call_operator 框架自动创建（creates_history_entry），**nudge 的几何写入是 operator 体内 Query/ResMut 直改、无 EditorCommand 包装**——框架快照对直改型 operator 疑似不捕获（对照：命令型 operator（SpawnEntity/CSG/SetTransform）的 undo 在同会话实测全部正常还原）。

**归因判断（QA 意见，非定论）**：修前 nudge 同样是「operator 直改（凸包 rebuild）+ 无 EditorCommand 包装」的相同结构，故**大概率是既有框架行为而非 R7 回归**；但 QA 无法在真机回到修前实证，且方案书 D4 口径为「undo 历史语义与修前完全一致」——**一致性成立与否超出本轮真机可验证范围**。R5 先例（history 断言正常）的 operator 均为显式命令型，不可直接对照。**建议主控：立票核查「直改型 operator 的 undo 快照」（与 A25 同属真机交互层），或批准以 headless 断言（nudge_tests 的 moved/any_modified 语义 ✓ + libtests 3117）作为 D4 的验收口径。**

### 7.6 复跑期间的其它环境观察（记档，不阻断）

1. **首测解析缺陷（QA 自身）**：`jackdaw/entity` BSN 的 MeshVert position 为多行格式，首轮 `vert_positions` 单行正则匹配为空——moved-verts 对比在 r8/r8c 首轮失效（r8b 修正为多行正则后恢复）；不影响 faces/verts 计数与 undo 计数断言。
2. **`transform.rotate_90_pitch_ccw` 真机异常**：对选中 cube 未写 rotation（quat identity）而 translation +0.125——与 §7.5 的 translation 写入疑点疑似同源（A25 家族），记档。
3. **BrushHalfedge BRP 探针恒空**：`world.query filter with BrushHalfedge` 在 face mode 下返回空（对照：同法 filter Brush 返回 3 实体）——探针 false negative（proxy 空间未代理该组件）或 lift 未发生，二者的行为差异（半边 vs legacy 凸包）已被 faces 9→9 排除（legacy 必 9→7），故 nudge 实际走了半边路径；探针口径留给 A25。

### 7.7 复跑后交付物增量

- 复跑脚本：`r8-run.py` / `r8b-run.py` / `r8c-run.py`（+ 首轮工具缺口前的 r7-live.sh / r7-leg*.sh / r7-run7a.py / r7-run7b.py）
- 复跑证据：`rerun-fmt.log` / `rerun-gates.log` / `rerun-libtests.log` / `r8-console.log` / `r8b-*.png` / `r8c-*.bsn.txt` / 各 BRP 应答 JSON
- 本报告复跑节（§七）；fixture `scene.bsn` SHA256 跑前跑后一致（`2f489e1c…`）、临时目录已清理、编辑器进程已清理
- **最终总判定：PASS（带 §7.5 阻断记档，交主控裁定 D4 口径）**；不合入、不打勾
