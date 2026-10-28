# T03 任务 2 报告：记录数一致性 + BRP history 工具 + 真机三链 + 全量门 + buglist 打钩

提交 `6df9ac89`（分支 `loop/t03-undo`，自 main `f558ec2f` = T03-T1 合入点），方案 `loop/plans/t03-undo-hardening.md` 任务 2。
**返工第 1 轮（终验 FAIL 回流）追加于文末**：提交 `765b4599`，见「返工第 1 轮」节。

## 修复内容

### Y1（含 N1 与新发现）— 自推型 op 全量补 `allows_undo = false`
- `src/entity_ops.rs`：`entity.add.*` 21 个（cube/sphere/point_light/directional_light/spot_light/camera/camera_rig/empty/plane/cylinder/wedge/cone/pyramid/animation_player/audio_source/fog_volume 走 `create_entity_in_world`；reflection_probe/spawn_point/zone_transition/network_room/terrain 走 `spawn_undoable`）+ `entity.paste_components`，共 22 处。
- `src/transform_ops.rs`：reset×3 / rotate90×6 / nudge×6，共 15 处。
- `src/inspector/ops.rs`：`component.add` / `component.remove`（方案 N1）。
- **新发现（方案清单外，同缺陷类）**：`src/inspector/brush_display.rs` 的 `brush.face.clear_material` / `brush.face.apply_texture_to_all` / `brush.face.set_uv_scale_preset` / `brush.clear_all_materials`——在 op 体系内直接改 Brush 并 push `SetBrush`/`CommandGroup`，按钮派发（`creates_history_entry:true`）同样双记录。一并修复。
- **未动**（按方案"不得误伤"+核实）：`entity.add.image` / `entity.add.prefab`（异步 picker 启动器，op 体不 push，真正的 spawn 是 picker 回调里的直调=单条）；模式 B 清单 `entity.duplicate`、`entity.toggle_visibility`、`entity.place_gltf`、`prefab.spawn_instance/unpack_child/unbundle_instance/apply_to_source`、`transform.numeric_apply`、`animation.toggle_keyframe`、`component.revert_baseline`——由 `SNAPSHOT_BACKED` 清单测试钉死 `allows_undo == true`。

### Y2 — 右键 Duplicate 改派发操作符
- `src/hierarchy.rs` `"hierarchy.duplicate"` 分支改 `entity.duplicate` 派发（`creates_history_entry:true` + `ExecutionContext::Invoke`，与键位/工具栏一致），不再直调 `duplicate_selected`（零记录）。

### Y4 — unpack 手势合并单快照 + **收敛单写路径**
- `src/prefab/operators.rs`：`prefab_unpack_child` op 体内、`unpack_child` 之后执行 `ReparentEntity`（**执行不 push**）；`src/hierarchy.rs` 删去手动 push，仅保留一次 `creates_history_entry:true` 派发 → 框架单条快照同时覆盖 AST unpack 与 ECS reparent。
- **单写路径收敛**（方案风险表预授权）：按方案默认实现（unpack 建副本 + reparent 搬原节点）实测前向文档在 drop target 下留**两个**节点（无名副本 + 带 PEID 的原节点，且副本语义丢孙代）。据此把 `unpack_child` 改为：`IsA.deleted` 增补后，**AST 节点本体 `move_to_parent_at` 搬到 drop target 并 `remove_component_patch(PrefabEntityId)`**，不再造副本。前向文档恰一个 `#Pebble`；`tests/prefabs/prefab_lifecycle.rs::unpack_child_adds_to_deleted_and_creates_standalone_node`（直调 AST 函数）原断言全部保持通过。
- 偏差说明：任务简报把 Y4 概括为「unpack_child 改 creates_history_entry:false」，本实现按方案 §3.5 定案（保留唯一一次 `true` 派发 + op 内执行 reparent）——简报字面方案会得到零记录。

### BRP `jackdaw/history` + MCP 薄工具
- `src/remote/server.rs`：`history_handler` 挂 `with_method_main`。返回 `{undo_len, redo_len, saved_len, has_save_baseline, dirty, top, undo:[{label}], redo:[{label}]}`（label 自 `EditorCommand::description()`，最新在前；`entries` 参数默认 8、上限 64）。读 `CommandHistory` + active tab（T1 的 per-tab 基准），与 `jackdaw/status` 的 dirty 同源。
- `crates/jackdaw_mcp/src/lib.rs`：同名薄工具 `history`（tools/list 20 → 21，`tests/mcp_smoke.rs` 期望清单已加）。
- `loop/qa/manual.md` §7.1 已补该行。

## 红 → 绿证据（`git stash src crates` 前后，同一测试集）

红（未修复代码，`loop/reports/t03t2-red-run.log`，record_counts **9 失败 / 1 通过**）：
- Y1 批次抽验全红：add cube / spawn_undoable 探针 `left: 2, right: 1`；reset 和弦 `left: 3, right: 2`；paste_components、component.add / component.remove 同型 `+2`；`self_pushing_operators_declare_undo_transparent` 首个失败项即 `entity.add.cube`。
- Y2：`the menu item is one entry` `left: 0, right: 1`（零记录）。
- Y4：手势经 op 派发时旧代码只做 AST（红日志为文档形状断言 `0 != +1`）；双记录证据在旧 hierarchy 手势路径，由下述既有测试改前红钉死。
- 既有测试中钉死旧行为的两条改前即红：`batch_undo::each_path_outside_a_batch_pushes_what_it_always_has`（旧断言 `+2`，本任务改为 `+1`，即 Y1 批次 1 的红→绿）；`undo_history::a_trimmed_history_still_undoes` 与 `operator_undo` 两条 snapshot/trim 测试（依赖 add 的双条目持字节，Y1 后失效，见"既有测试适配"）。
- 通过的 1 条 = `snapshot_backed_operators_keep_allows_undo`（模式 B 保护清单，修复前后都应通过——证未误伤）。

绿（修复后，`cargo test --test guards`）：**134 passed / 0 failed**（T1 的 123 + 新 `tests/guards/record_counts.rs` 11 条：Y1 批次抽验 ×4、N1 ×2、清单 ×2、Y2 ×1、Y4 ×1、history 工具 ×1）；`tests/prefabs` unpack 生命周期 1 条原样通过；`tests/operators/operator_undo` 11/11。

## 既有测试适配（3 处，均因 Y1 语义变更而非回归）

| 测试 | 旧依据 | 适配 |
|---|---|---|
| `guards/batch_undo.rs::each_path_outside_a_batch_pushes_what_it_always_has` | 显式断言 add 菜单 `+2`（把双记录钉成预期） | 断言 `+1`（即本缺陷红→绿锚点） |
| `guards/undo_history.rs::a_trimmed_history_still_undoes_every_entry_it_kept` | cube 双条目里快照条目持有字节，预算据此裁剪 | 改放 rock 实例（模式 B 快照条目持有文档单元）驱动裁剪，意图不变 |
| `operators/operator_undo.rs::a_snapshot_entry_reports…` / `snapshot_entries_are_trimmed…` | 用 `entity.add.empty` 当快照条目载体 | 改用 `entity.duplicate`（模式 B，每轮产生持字节的 DocumentEdit） |

## 全量门（全部通过）

| 门 | 命令 | 结果 | 日志 |
|---|---|---|---|
| fmt | `cargo fmt --all -- --check` | exit 0 | loop/reports/gate-fmt-t03t2.log |
| clippy | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | exit 0 | loop/reports/gate-clippy-t03t2.log |
| xtask fast | `cargo xtask fast` | 2866 passed, 2 skipped | loop/reports/gate-xtask-fast-t03t2.log |
| xtask integration | `cargo xtask integration` | **5070 passed, 2 skipped, 0 failed**（首轮仅上述 operator_undo 两条红，适配后全量复跑干净） | loop/reports/gate-xtask-integration-t03t2.log |
| doc | `cargo doc --locked --workspace --document-private-items --no-deps` | exit 0 | loop/reports/gate-doc-t03t2.log |
| doctests 基线 | `cargo test --locked --workspace --doc --features dylib --no-fail-fast` | 非零=既有基线：失败集合恰为 {jackdaw_bind, jackdaw_feathers, jackdaw_node_graph}，FAILED 行 56 == T1 基线 56，零新增 | loop/reports/gate-doctests-t03t2.log |

## 真机三链（`loop/reports/t03t2-qa-live.ps1`，窗口 1920x1080，临时工程，截图 `loop/reports/t03t2-qa/`）

全程用新 `jackdaw/history` 断言记录数；日志 `loop/reports/t03t2-qa-live.log`，**RESULT failures=0**。

| 链 | 数字 |
|---|---|
| 1 拖拽数值（scrub） | 选中 Zone → 展开 Transform 卡 → 拖 translation X 行整个手势：x 0→0.25，**undo_len 0→1**（top=“Set component field”），dirty 亮；一次 undo → x=0、undo_len 回 0、redo_len 1、dirty 灭（回到已存内容） |
| 2 右键 Duplicate | 合成 RMB 点击 Zone 行（scale=1）→ 真实上下文菜单 → 点 Duplicate：**undo_len 0→1**（top=“Duplicate”），文档 #Zone 1→2；一次 undo → #Zone 回 1 |
| 3 unpack 手势 | 放 rock 实例（落于 Zone 下，`selection.select name=Pebble` 触发展开揭示）→ 真实 outliner 拖 Pebble 行到 Zone 行：**undo_len 1→2**（top=“Unpack Prefab Child”），文档 `#Pebble` 0→**1**（恰一个）；一次 undo → scene_bsn 与手势前**逐字节相等**；redo 恢复；保存→clean；保存→undo→**dirty 亮**（N4 真机复现） |

## buglist 打钩（文件改动，不入 git——buglist.md 历来不入库）

R1、R2、Y1、Y2、Y4 五条改 `- [x]` 并追加 `> 已修复 <commit>` 备注：
- R1 / R2 → `b9a8842d`（T03-T1 修复；本轮 guards keyframe_undo / numeric_transform_undo 全绿 + 真机链复测）
- Y1 / Y2 / Y4 → `6df9ac89`（本任务）

## 偏差与说明（concerns）

1. **Y4 走了方案定案而非简报字面**：保留唯一一次 `creates_history_entry:true` 派发（简报的 `false` 字面会导致零记录）；并按方案风险表预授权收敛 unpack 单写路径（move+strip，删除副本语义——顺带修掉了旧副本语义丢孙代的问题）。
2. **brush 4 op 为方案清单外新发现**（同 Y1 类），已修复并入 `SELF_PUSHING` 防回归清单；`entity.add.image/prefab` 核实为异步启动器不需改。
3. **三条既有测试适配**（见上表）——它们把修复前的行为当预期；适配后意图不变（裁剪/快照字节申报改由模式 B 条目承载）。
4. MCP 工具数 20→21（manual §7.3 的「20 个工具」表述已随 §7.1 更新过时差，非本任务修）。
5. QA 脚本沉淀：PowerShell `History` 函数名撞内建 alias（Get-History）导致探针空读——改名 `HistProbe`；单行返回值 `.Count` 需 `@()` 包裹；outliner 揭示行用 `selection.select`（reveal 驱动器自动展开祖先）比点 disclosure 稳。
6. `loop/` 与 `buglist.md` 未入库（`git status` 仅余 `.gitignore` 本地改动与未跟踪 buglist.md，与历轮一致）；`.gitignore` 的 `.mimosa/` 行为前会话遗留，未提交。

## 返工第 1 轮（终验 FAIL 回流，提交 `765b4599`）

需求来源 `loop/reports/t03-final-qa.md`（VERDICT: FAIL）返工清单 + QA 顺手处置项。

### 🔴 clip 关键帧 op 键位路径双记录（QA 实证项）

- `src/lib.rs`：`clip.delete_keyframes`（Delete/Backspace）与 `clip.paste_keyframes`（Ctrl+V）补 `allows_undo = false`，对齐同族 `clip.copy_keyframes`。两 op 均自推关键帧 `CommandGroup`，T1 的 R1 修复使关键帧增删落文档后快照 diff 由空变非空 → 键位派发（Invoke+history:true）双记录，undo 撤完出 2 个 live keyframe。
- 测试（`tests/guards/keyframe_undo.rs` 新 2 条，键位设置派发）：`the_delete_keybind_is_one_entry_and_undoes_to_one_keyframe`（恰 1 条 + 撤完全部记录后恰 1 个关键帧/1 个文档节点——QA 探针症状的钉死）、`the_paste_keybind_is_one_entry_and_undoes_cleanly`（copy 零记录、paste 恰 1 条、一次 undo 只撤粘贴）。红（stash 后 `t03r1-red-run.log`）：delete/paste 均 `left: 2, right: 1`；绿：keyframe_undo 6/6。

### 🟡 同型潜伏处置（QA 提示 4 项 + 本轮自扫新增 3 项，共 7 项声明）

逐个核实确属自推后补 `allows_undo = false`：
- `terrain.generate` / `terrain.erode`（`src/terrain/ops.rs`，自推 `SetTerrainHeights`；顺带删除两条「快照 diff 为空所以无碍」的过时注释——空 diff 是文档覆盖面的偶然，不是可依赖的契约）。
- `resource.insert` / `resource.remove` / **`resource.set_field`**（`src/inspector/resource_ops.rs`；set_field 为 QA 扫描漏网、本轮经闭包队列核实自推的新发现）。
- **新发现（🔴 级实证）**：`brush.join`（**J 键位绑定**，自推 SetBrush+Despawn 组且写文档 → 键位路径实证双记录，红 `left: 2, right: 1`；T2 与 QA 双扫描均漏网——push 在被 queue 的具名 impl 里）。行为测试 `the_join_keybind_is_one_user_entry` 钉死恰 1 条 + 一次 undo 双笔刷复原。
- **新发现**：`pie.live_edits_apply_all`（PIE "Apply All" 按钮派发，自推编辑组）。
- 9 项全部入 `SELF_PUSHING` 清单（41→50 项）。

### ⚪

- `record_counts.rs` SNAPSHOT_BACKED 注释 mojibake（em-dash 双重编码）修复。
- buglist R1 备注补尾巴：键位路径补丁 commit `765b4599`（buglist.md R1 条目第二行备注）。

### 门禁（四门重跑，日志 `gate-*-t03r1.log`）

| 门 | 结果 |
|---|---|
| fmt | exit 0 |
| clippy（workspace+dylib+deny warnings） | exit 0 |
| xtask fast | 2866 passed, 2 skipped |
| xtask integration | **5073 passed, 2 skipped, 0 failed**（+3 新测试） |
| guards | **137/137**（134 + keybind×2 + join×1） |

### 独立行探针（`loop/reports/t03r1-probe.ps1` → `t03r1-probe.log`，真机 BRP）

- registry：9 个 op 在 `jackdaw/operators` 全部回答 `allows_undo=false`（9 PASS）。
- 行为：`entity.add.terrain` → `terrain.generate` 经 `call_operator`（history 默认 true，即用户路径）→ `jackdaw/history` undo_len 1→2 恰一条（top="Generate Terrain"）。
- RESULT failures=0。

### 偏差与说明（本轮）

1. **brush.join undo 完整性缺口（范围外，已知遗留）**：join 后下一帧的异步 `recenter_brush_origins` 会移动保留笔刷的 Transform，join 自身命令组未记录该位移——单条 undo 复原双笔刷与几何，但保留笔刷 translation 留在 hull 质心。此为 join 与异步 recenter 的既有交互（BRP `history:false` 路径同样存在），非本轮记录数修复引入；join 测试按本轮保证断言（恰 1 条 + 双笔刷/双文档节点复原）并在注释中说明，建议另开 buglist 条目。
2. `pie.live_edits_apply_all` 属「退出 Live 模式写回 authored 场景」的按钮 op（非 T25 的 Live 流编辑本身），按自推类处置；若裁决认为越界可单点回退（一行声明）。
3. 扫描方法沉淀：本轮补扫两类盲区——「op 体 queue 具名 impl 且 impl 内 push_executed」（brush.join、pie.apply_all 由此落网）与「闭包队列调自推 helper」（resource.set_field）；扫描脚本 `loop/t03r1-scan-selfpush.ps1` / `t03r1-scan-queued.ps1` 留档。

## 返工第 2 轮（QA 复验 FAIL 回流，提交 `4a2cf332`）

需求来源 `loop/reports/t03-r1-qa.md` §7 回流清单（5 项最小集）。

### 🔴 `brush.extend_face_to_brush`（Ctrl+E 键位）
- `src/draw_brush/extend_face.rs` 补 `allows_undo = false`：op 体 :150 queue 闭包 → `extend_face_to_brush_impl`（:347 push `SetBrush "Extend face to brush"` + 写文档），与 brush.join 完全同型（QA 判定的二层间接盲区）。
- **行为测试（无需取舍，几何前置已解）**：`the_extend_face_keybind_is_one_user_entry`——双 authored 笔刷、Face 模式选 face 0（面模式入口，Object 模式的 remembered/hovered face 无头环境无法诚实产生）、目标笔刷绕 Y 转 45°（**斜面才是 extend 的 angled 约束面**：轴对齐 cuboid 对的所有面 dot 为 0/±1，angled 滤空、opposing 只给单侧界 → 半空间交非空盒失败、impl 早退零 push——首轮 target 平移 4 单位实测即此；斜置后约束有界、push 成立）。断言：键位设置派发恰 1 条、文档变化、一次 undo 双笔刷（`#ExtendBrush`/`#TargetBrush` 各 1）复原。红（stash 后 `t03r2-red-run.log`）：`left: 2, right: 1`。

### 🟡 `pie.live_edit_save`
- `src/live_edits.rs` 补 `allows_undo = false`（queue 闭包 → `save_entry_to_scene` :422 区域 push；与 apply_all 处置对齐，防护面为 F3 面板路径）。

### 清单与扫描
- `SELF_PUSHING` 50→52（两 id 入列）。
- 扫描脚本沉淀：QA 间接扫描（fn 体一层 called-local-fn 归纳）与轮 1 双脚本合并为 **`loop/qa/scan-selfpush.ps1`**；当前树跑出 **0 未声明自推 op**，并做 sanity 反证（临时摘掉 resource.insert 声明 → 扫描命中该 op → 还原复跑 0 命中）。

### 门禁（quick 四门亲跑，日志 `gate-*-t03r2.log`）与探针
| 门 | 结果 |
|---|---|
| fmt | exit 0 |
| clippy（workspace+dylib+deny warnings） | exit 0 |
| xtask fast | 2866 passed, 2 skipped |
| xtask integration | **5074 passed, 2 skipped, 0 failed**（+1 extend 测试） |
| guards | **138/138**（137 + extend×1） |

独立行探针（`t03r2-probe.ps1` → `t03r2-probe.log`，真机 BRP registry）：`brush.extend_face_to_brush`、`pie.live_edit_save` + 轮 1 九项共 11 op 全答 `allows_undo=false`；锚点 `entity.duplicate`/`entity.toggle_visibility` 仍 true（未误伤）。**failures=0**。

### 说明（本轮）
1. extend_face 行为测试**未走 QA 预授权的「静态+Invoke 组合」替代**——Face 模式前置可用 numeric_transform_undo 的既有搭建模式满足，几何前置（angled 约束面）经一次失败尝试后以斜置目标解出，测试为完整行为断言（恰 1 条 + undo 复原）。测试注释写明斜面原因。
2. buglist R1 备注追加「返工 2 补齐 4a2cf332」一行；buglist/loop/.gitignore 照旧不入库。
