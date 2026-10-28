# T03 返工第 1 轮复验（QA）— 提交 `765b4599`（分支 `loop/t03-undo`，7 文件 +203/−15，HEAD 与 diff 统计亲核一致）

口径：`loop/reports/t03-final-qa.md`（终验 FAIL + 返工清单）+ 程序自述 `loop/reports/t03-t2-report.md`「返工第 1 轮」节。QA 只验收、不修复。工作区干净（仅历轮遗留：`.gitignore` 本地改动、未跟踪 `buglist.md`）。

## VERDICT: FAIL（差一口）— 终验 🔴 修复本身成立、四门亲跑全绿、9 项自推声明与红→绿全部属实；但 QA 扩散面独立扫描发现 **1 个新 🔴 同型漏网**（`brush.extend_face_to_brush`，Ctrl+E 键位）+ 1 个 🟡（`pie.live_edit_save`），按本轮 PASS 条件（review 无新 🔴）判 FAIL，需一轮极小回流（预计 ≤0.5 小时：两行 attr + 清单 + 顺带测试）。

## 1. 门禁（QA 全部亲跑，批处理 `loop/reports/t03r1qa-gates.cmd`，独立行 exit code；日志 `gate-*-t03r1qa.log`）

| 门 | 命令 | 结果 | exit code |
|---|---|---|---|
| fmt | `cargo fmt --all -- --check` | 通过 | **0** |
| clippy | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | 通过（33.24s） | **0** |
| xtask fast | `cargo xtask fast` | **2866 passed, 2 skipped** | **0** |
| xtask integration | `cargo xtask integration` | **5073 passed, 2 skipped**（299.25s） | **0** |

数字与程序自述一致（5073 = 终验 5070 + 3 条新测试）。doctests 未亲跑：本轮 diff 未触碰 doc 面，非回归基线即可（任务书口径）。

## 2. 代码审查（`git show 765b4599` 逐文件 + op 体亲读）

### 2.1 九个自推声明逐个核实 — **全部属实**（push_executed 位置亲核）

| op | 声明处 | 自推证据（QA 亲读 op 体/被调 impl） |
|---|---|---|
| clip.delete_keyframes | src/lib.rs | queue 闭包内 `push_executed(CommandGroup "Delete keyframes")`（lib.rs:1344） |
| clip.paste_keyframes | src/lib.rs | `paste_clipboard_keyframes` 尾部 push（lib.rs:1859） |
| brush.join | src/draw_brush/csg_ops.rs | `join_selected_brushes_impl` 尾部 push（csg_ops.rs:441，确为「push 在被 queue 的具名 impl 里」——T2 双扫描漏网原因属实） |
| terrain.generate | src/terrain/ops.rs | queue 闭包内 `push_executed(SetTerrainHeights::whole)`（:272） |
| terrain.erode | 同上 | :323 |
| resource.insert | src/inspector/resource_ops.rs | :84 push `ResourceInsert` |
| resource.remove | 同上 | :126 push `ResourceRemove` |
| resource.set_field | 同上 | queue 闭包调 `resource_field_commit` → resource_commands.rs:399 push `ResourceSetField`（「闭包队列调自推 helper」判断依据属实） |
| pie.live_edits_apply_all | src/live_edits.rs | `apply_all_to_scene` push（:585 单条/:593 组） |

- `SELF_PUSHING` 41→50（+9，清单测试钉死）；`SNAPSHOT_BACKED` 10 项未动。
- **terrain 旧注释删除不失实**：旧注释的机制陈述（heights 在 AST 外 → 快照 diff 空）被新注释原文保留（"The snapshot diff is empty today because heights live outside the AST"）并显式降格为「偶然，非契约」；删除的是「靠空 diff 保安全」这一不可依赖的结论，与终验 🟡 的处置要求一致。
- **pie.live_edits_apply_all 定性可接受**：确为「退出 Live 写回 authored」按钮 op（`build_save_command` 组写 AST + 自推）。QA 补充事实：其全部 UI 入口（`live_edits_ui.rs:320` tray_footer_button、`:545` stop_prompt 按钮）实际以 `creates_history_entry:false` 派发——声明 `false` 防的是 F3 命令面板路径（OperatorAction → Invoke+true），处置正确（见 §4 concern 意见）。

### 2.2 新测试断言质量与红→绿 — 合格

- `keyframe_undo.rs` 的 `keybind` helper = `Invoke + creates_history_entry:true`（键位同路，对齐 `jackdaw_api_internal/src/lib.rs` 对绑定键的 Exact 行为）。
- delete 测试钉死 QA 探针症状：恰 1 条 + **撤完全部记录后 live keyframe 恰 1、文档节点恰 1**（双记录时会变 2/2）；paste 测试断言 copy 零记录、paste 恰 1、一次 undo 只撤粘贴（live 2→1、文档 1）；join 测试断言恰 1 条 + 一次 undo 双笔刷双文档节点复原，注释如实披露 recenter 缺口与不 assert 字节相等的原因。
- 红→绿对照（`t03r1-red-run.log`，stash 复演）：4 个 FAILED 的断言位置与数字逐一对上——delete `left: 2, right: 1` @keyframe_undo.rs:275、paste @:314、join `left: 2, right: 1` @record_counts.rs:167、`self_pushing_operators_declare_undo_transparent` 首个失败项 `clip.delete_keyframes` @:408。红证真实。
- ⚪ record_counts.rs:306 乱码：全仓 src/crates/tests `鈥` 零残留，SNAPSHOT_BACKED 注释现为正常 em-dash。**已清干净**。

## 3. QA 扩散面独立扫描 — **新发现（本轮 review 的关键产出）**

程序两个扫描脚本（`loop/t03r1-scan-selfpush.ps1` / `t03r1-scan-queued.ps1`）都有同一盲区：`commands.queue(|闭包| { 具名_impl(...) })` 的二层间接。QA 自写一层间接扫描 `loop/reports/t03r1qa-scan-indirect.ps1`（对每个未声明 `false` 的 op：fn 体直引 push 标记 **或其调用的本地 fn 含 push_executed** 即报），全仓命中 2 项，逐个亲核：

1. 🔴 **`brush.extend_face_to_brush`（Ctrl+E 键位绑定，`src/draw_brush/mod.rs:82` `bind_operator ... PresetInput::key("KeyE").ctrl_or_super()`）**
   - 自推：op 体 `commands.queue(闭包 → extend_face_to_brush_impl)`（extend_face.rs:150），impl 尾部 `push_executed`（:346）；
   - 写文档：Brush 族命令（与 brush.join 同族——join 的红测试已实证 Brush 写入产生非空快照 diff → 双记录）；
   - 未声明 `allows_undo=false`、不在 SELF_PUSHING；
   - 结论：**Ctrl+E 键位路径与 brush.join（J 键，本轮 🔴 级）完全同型**。未真机实证（Face 模式/remembered face 前置难驱动；真机 Object 模式无 remembered face 时 cancelled 零记录，探针 B obs-2 佐证其入口门槛），静态证据链完整。**非本轮引入**（T2 Y1 扫描漏网存量），但落在 Y1「自推 op 全量声明」的验收面内。
2. 🟡 **`pie.live_edit_save`**（live_edits.rs:628，queue 闭包调 `save_entry_to_scene` → :422 push + 写 AST）——自推未声明。但其全部确认 UI 入口（inspector dots 菜单 `live_edit_dots.rs`、tray、stop prompt，均 `creates_history_entry:false` 派发）**无**双记录；仅 F3 面板在 `live_edit_action_pending` available 时暴露——与终验 🟡（terrain/resource 潜伏）同一论证口径。与 apply_all 的处置不一致（一个声明一个不声明）。
3. 反向核实无误伤：`pie.live_edit_revert`（`revert_entry` 446-544 无 push）、`pie.live_edits_discard_all`（`discard_all` 清 log 不碰 AST，单测钉死 undo_stack==0）非自推，不声明正确。

## 4. 真机探针（BRP over HTTP，POST 127.0.0.1:<port>；脚本与日志留档 `loop/reports/t03r1qa-live-*.{ps1,log}`、`t03r1qa-diag.ps1`、`t03r1qa-dump.ps1`）

环境：无残留进程（tasklist 核查，任务书所述 PID 41312 旧实例已不在）；`cargo build -p jackdaw` EXIT:0；临时工程（Cargo.toml + .jackdaw/project.json）+ `JACKDAW_OPEN_PROJECT` 启动、1920x1080、`jackdaw/wait until=idle` 时序规约。

### c) registry（`t03r1qa-live-a.log`）— 9/9 PASS
clip.delete_keyframes / clip.paste_keyframes / brush.join / pie.live_edits_apply_all / terrain.generate / terrain.erode / resource.insert / resource.remove / resource.set_field 全部应答 `allows_undo=false`。

### d) 反向抽查 — PASS
`entity.duplicate`、`entity.toggle_visibility` 仍 `allows_undo=true`（未误伤）。e) 佐证：`brush.extend_face_to_brush` 真机应答 `allows_undo=true`（坐实 §3 新发现）、`pie.live_edit_save` 同。

### b) brush.join（`t03r1qa-live-b.log`，RESULT failures=0）— PASS
`entity.add.cube` ×2（真机 scene_tree 证实 cube 即 Brush 实体）→ `selection.select entities=<bits1>,<bits2>` 双选 →
**真实 J 键**（`input.key key=KeyJ`，合成 winit 键盘事件走 keymap chord）：
- `undo_len 2 → 3（恰 +1）`，`top="Join brushes"`（op 自推 CommandGroup 的 label——证明记录来自 op 自身而非框架快照）；
- 文档 `#Cube` 2 → 1（合并）；
- `history.undo` 一次：undo_len 回 2、`#Cube` 恢复 2、scene_tree 双 Cube 复活。
附带观察：`clip.delete_keyframes` 无 keyframe 选中时 `cancelled` 且零记录；`brush.extend_face_to_brush` Object 模式无 remembered face 时 `cancelled` 零记录。

### a) 键位路径双记录复演（终验 🔴 原探针）— 修复成立（组合证据链；完整真机用户态未能直接进入，如实注明）

真机直接复演受阻的客观原因（`t03r1qa-dump.ps1` 诊断）：keyframe 实体无 `Name`、本构建 bevy BRP `world.query` 恒返回 `{"result":[]}`（连 Name 组件也空）、timeline 选中 keyframe 的唯一 UI 路径是 marquee 框选（坐标驱动脆）——keyframe 实体无法经 BRP 进入 `Selection`，`has_selected_keyframes` 不可满足，clip op 在真机恒 `cancelled`。QA 以四层组合证据闭环：

1. **headless 键位级断言亲跑**：`the_delete_keybind_is_one_entry_and_undoes_to_one_keyframe` / `the_paste_keybind_is_one_entry_and_undoes_cleanly`（Invoke+true 派发：恰 1 条 + 撤完恰 1 keyframe/1 文档节点 + paste 一次 undo 干净）随 QA 亲跑的 `xtask integration` 5073 全量通过；
2. **快照机制源码等价**（`jackdaw_api_internal/src/operator.rs`）：快照捕获仅取决于 `creates_history_entry && allows_undo`，`Execute`/`Invoke` 仅选择 system 入口——BRP `call_operator`（Execute+history:true，server.rs:833）与键位（Invoke+true）记录行为等价，程序探针所用口径成立；
3. **同机制真机实证**（探针 B）：真实 J 键 → brush.join（同为「键位绑定 + 自推 + 写文档 + 本轮补 false」的完全同型修复）真机恰 1 条、top 为自推组 label、undo 干净——该机制在真实运行时环境的单记录行为已实证；
4. **真实键位栈贯通**（`t03r1qa-live-a.log`）：真实 Delete / Ctrl+C / Ctrl+V 合成键在真机可触发 chord（因 selection 未含 keyframe 被路由至同键的 entity.delete/entity.copy/entity.paste：delete 恰 +1 top="Delete entities"、copy 零记录、paste 恰 +1，undo 均干净——顺带反向验证键位栈与模式 B 单条，终验 🔴 症状未再出现于任何路径）。

## 5. 程序两项 concern 的 QA 意见（供主控裁决）

1. **brush.join 后异步 `recenter_brush_origins` 位移不入撤销**：同意范围外。该系统早于 T03 全部工作（`src/draw_brush/mesh.rs:147`，Bevy 0.20 升级提交 `18aab519` 已在），`765b4599` 的 diff 完全未触碰它；join 测试注释如实披露且按本轮保证断言。建议另开 buglist 条目（单次 join 的 undo 把保留笔刷 translation 留在 hull 质心）。
2. **pie.live_edits_apply_all 按「Apply All 按钮」处置**：可接受——确为「退出 Live 写回 authored」按钮 op，非 T25 Live 流本身；但按钮实际是 false 派发，声明 false 的真实防护面是 F3 面板路径。与 `pie.live_edit_save`（同自推、未声明）处置不一致，建议下轮一行补齐。

## 6. 问题统计

| 级别 | 条目 |
|---|---|
| 🔴 严重 | 1 |
| 🟡 中等 | 1 |
| ⚪ 轻微 | 0 新增（终验 ⚪ 乱码已清干净） |

1. 🔴 [程序，存量漏网/本轮扫描盲区] `brush.extend_face_to_brush`（Ctrl+E）：自推 `extend_face_to_brush_impl`（:346 push）+ 写文档 + 键位绑定，未声明 `allows_undo=false`、不在 SELF_PUSHING——键位路径与 brush.join 同型双记录（join 红证 left:2 已实证同机制）。未真机实证（前置门槛），静态链完整。
2. 🟡 [程序] `pie.live_edit_save`：自推（save_entry_to_scene :422）未声明；全部 UI 入口 false 派发故正常路径无碍，F3 面板 available 时暴露；与 apply_all 处置不一致。

**正向**：返工清单 5 项全部按最小集完成且质量高（红→绿证据链完整、9 项逐个亲核属实、terrain 注释删除把「偶然安全」升级为「契约安全」、join 测试对 undo 缺口的披露诚实）；brush.join 真机单记录 + 双笔刷复原一次通过；门禁数字与自述零偏差。

## 7. 回流清单（最小集，预计 ≤0.5 小时）

1. `src/draw_brush/extend_face.rs`：`brush.extend_face_to_brush` 补 `allows_undo = false`（对齐同族 brush.join）。
2. （建议一并）`src/live_edits.rs`：`pie.live_edit_save` 补 `allows_undo = false`（与 apply_all 一致）。
3. `tests/guards/record_counts.rs`：两者入 `SELF_PUSHING`（50→52）；建议为 extend_face 补一条键位派发（Ctrl+E）行为测试（参照 `the_join_keybind_is_one_user_entry`；Object 模式需 remembered face，可走 BrushEdit(Face) 路径或最小 world 搭建）。
4. 扫描脚本沉淀：把「queue(匿名闭包→具名 impl/helper)」一层间接并入自扫脚本（QA 的 `loop/reports/t03r1qa-scan-indirect.ps1` 可直接采用或移植）。
5. 重跑 quick 门 + guards；QA 重验 registry 两项应答 + extend_face 行为测试即闭。

## 8. 结论

终验 🔴 的修复（键位路径单记录、undo 干净）在本轮复验中**成立**；四门亲跑全绿；程序自述与实测零偏差。但 PASS 条件第三项（review 无新 🔴）被 `brush.extend_face_to_brush` 打破——属 T2 Y1「自推全量声明」的存量漏网（扫描盲区），非本轮引入，修复成本极小。

**VERDICT: FAIL（回流清单见 §7；回流后 QA 只需重验 registry 两项应答 + 新测试，预计一轮即闭）**
