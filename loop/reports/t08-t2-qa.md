# T08-T2 QA 验收报告：作者态生命周期保护（只验不修）

> QA 角色：Loop 工作流验收。分支 `loop/t08-lifecycle`，提交 **d213f627**（12 文件 +457/−38，与程序报告一致）。
> 验收日期 2026-10-27。工作区核对：仅 `.gitignore` 本地改动（`++.mimosa/`，与本任务无关，不计数）；src/tests 与提交态一致。
> 证据文件：`loop/t08t2_qa_live.log`（真机 v1）、`loop/t08t2_qa_live2.log`（真机 v2）、`loop/t08t2_qa_behavior*.log`+`loop/t08t2_qa_diag*.log`（行为腿 8 轮）、`loop/t08-t2-qa-live/snap*.json`（两帧原始快照）、`loop/t08t2_*.log`（程序归档）。

## 一、门禁（归档全文复核 + 亲跑）

| 门 | 归档复核（loop/t08t2_*） | QA 亲跑 | 结论 |
|---|---|---|---|
| fmt | 空文件=clean | `cargo fmt --all -- --check` exit 0 无输出 | ✅ |
| clippy | 仅 linker 环境 warning（`-fuse-ld=lld`，`linker_messages` lint 不受 `-D` 管），无 error | exit 0，全文无 error（同款 linker warning） | ✅ |
| lib | `1171 passed; 0 failed`（日志中 "failed" 字样均为测试名/fixture 预期注入） | 56 个 `test result` 行全 `0 failed`，主 crate **1171**（1.08s） | ✅ |
| guards | `202 passed; 0 failed`（50.61s）；asset_lifecycle 3 条+dirty_matrix 14 格全 ok 在列 | 201+1：`session_journal::the_journal_write_costs_no_more_than_five_milliseconds` 首跑 FAILED（journal 写 7.0ms 超帧预算）——**QA 隔离重跑该条 PASS**（写入 1.53-2.03ms，远低预算；首跑失败与 QA 并行启动的模板工程编译抢 CPU 同期，属负载 flaky）；亲跑日志中 asset_lifecycle 3+dirty_matrix 14 无任何非 ok 行 | ✅（有效 202/202） |

门禁结论：四门全过。红线索引：`rust-lld -fuse-ld=lld` warning 为环境项；journal 性能条历史敏感（建议 guards 跑时勿并行重编译——QA 教训记档）。

## 二、红→绿

- **P5 回退模拟红——QA 亲验复现**：将 `mark_active_dirty_on_history_growth`（scenes/mod.rs:346）与 `active_tab_modified`（scenes/operators.rs:761）两处临时改回 `total_pushes()` → `cargo test --test guards an_asset_field_edit_does_not_dirty_the_scene_tab` → **FAILED**（panic 于 asset_lifecycle.rs:94，即 `active_tab_modified` 断言=main 行为）→ 还原 → **PASS** → `git status src/` 干净。红证真实、可复现，回退模拟形态对「main 无新 API 无法 stash」的 P5 是唯一正确做法。✅
- **P4 结构红+行为红**：结构红（main 无 `save_dirty_assets` 编译不过）+行为红（pie.rs `save_before_launch_tests`：index-miss 卡使启动拒绝并点名资产，guards 同法）。T3 教训先例下可接受；但失败注入仅覆盖 `save_indexed_asset` 第一道拒绝（偏差 5，程序已记），真实 IO 失败分支未测——⚪ 维持记档。✅（形态）
- **P4 退出腿结构红**：条件扩展+文案+SaveAll 接线由真机走查覆盖（见 §四），形态可接受。✅
- **W13 代码红**：main 源码事实（`notify_warn`=`notify(world,text,false)` 与 info 同实现；渲染 `error?TEXT_ERROR:TEXT_WARNING` 即非 error 一律警告色）。buglist 原文「警告色永远不可达」方向与代码事实相反（实为**警告色被滥用、正文色不可达**），但实质缺陷（warn/info 无区分）与修复方向一致，打钩成立。✅

## 三、代码 review

### 1. `touches_scene_document` 覆写面完整性（全仓扫描）

全仓 47 个 `impl EditorCommand for`。4 个覆写 false 正确：`SetDefinitionField`+`ResourceInsert/Remove/SetField`。抽查 `SetBrush`（写 Brush 组件+sync AST）、`SetCanvasGuides`（写实体组件+sync_component_to_ast）、`SnapshotDiff`（场景快照对）等均写场景文档，默认 true 正确。

**🟡 漏网（任务书未列，记档跟进）——动画图域 7 个命令**：`GraphDefEdit`（animation/graph_doc.rs:510，写 `AnimationGraphDoc`——**带独立 path+dirty 的独立文件文档**，与 `DefinitionAssetEdit` 同构）、`ClipEventEdit`（timeline_ops.rs:562，timeline UI 事件实体）、`jackdaw_node_graph` 5 命令（commands.rs，画布 GraphNode 实体）。它们默认 touches=true：**编辑动画图会把场景 tab 弄脏（P5 同性质残留面）**；且 `AnimationGraphDoc.dirty` 不在任何保存链/退出保护里（P4 同性质洞）。不属于本任务交付范围（任务书 §二 T2 只点名 definition assets+资源三命令），建议挂 open-challenges 或下任务吸收。

### 2. scene_pushes 与 total_pushes 双计数一致性

`count_push` 在 `execute`/`push_executed` 两入口一致计入；两者都永不递减；`redo` 两者都不计（与既有 `pushes` 语义对齐，T03 已验收）；`CommandGroup` 覆写 any（混组偏保守=朝脏，注释说明取舍）。`commands` crate 单测 `non_scene_commands_share_the_history_without_counting_as_scene_pushes` 钉死分离。✅

**🟡 但注意（见 §五 QA-1）**：过滤计数只接住了「无保存基线」的 tab 路径与两处比对点；watcher 对**已保存基线** tab 的置脏分支不看任何 push 计数——P5 承诺在真机最常见形态不成立（详见下）。

### 3. save_dirty_assets 拒绝语义

先收集 dirty path 再逐个 `save_indexed_asset`（借用安全）；失败收 path 名（空=全成）；失败卡保持 dirty 供下次重试；Play 链（pie.rs `save_scenes_before_launch`：场景失败与资产失败并入同一 failures，`Not {action}: could not save <names>`）与导出链（game_export.rs:162，**导出第一步同步执行**）同语义拒绝。✅

### 4. 退出对话框与 NoticeLevel

触发条件 `tabs.any(dirty) || asset_edits.any(dirty)`；文案追加 `Unsaved assets: <stems>`；SaveAll 先场景后资产、场景失败不试资产（`assets_saved` 仅 `scenes_saved` 为真才计算），两失败源 warn 分开。真机走查见 §四。NoticeLevel 三档（Info→TEXT_SECONDARY/Warning→TEXT_WARNING/Error→TEXT_ERROR）+ `notices_carry_their_level` 单测。✅

## 四、真机独立复跑（my-game + 模板 fixture，全部 BRP 驱动）

脚本：`loop/qa/t08-t2-qa-live.ps1`（v1）、`t08-t2-qa-live2.ps1`（v2）、`t08-t2-qa-behavior3.ps1`/`t08-t2-qa-diag*.ps1`（行为腿）。my-game `scene.bsn` 前后 SHA256 不变（v2 验证）；测试资产 t08qa2/t08qa3 及 .bak 已清理。

- **真机① N10 前科区 PASS**：dirty 资产卡（0.8）+ named 场景（scene.bsn Save 态 clean）+ 默认 Save 档 `pie.play_current` → 编辑器全程存活无冻结、play running、stop 归位，**盘上资产被启动链写入 0.8**（pre-play 无值→post-play 有值）。`LEG A PASS`。
- **真机② scene_snapshot 通道 PASS（计数+行为两级）**：
  - 计数：编辑器端口 play 中 **count=54**（my-game，程序报 18→54 的复现）；模板 fixture **count=19**。
  - 行为（T1 遗留腿，QA 补齐）：模板工程（scaffold 生成，GameConfig+FallingCube）上两帧差——**FallingCube 投影实体 y：-14.42 → -46.12（3s）**，-9.81 重力轨迹成立；**gravity 改 -19.62 再 Play：dy 加倍（-61.28）**——「编辑器改配置→下一次 Play 行为随文件值变化」**端到端证实**（T1 当年未跑成的一腿，T3 矩阵格 4 的重力断言可用）。
  - 附带沉淀：snapshot 的 `Transform` JSON 形态为**数组**（`translation:[x,y,z]`、`rotation:[x,y,z,w]` 四元数），T1 脚本注释的 `.translation.y` 取法自始错误；详见 §六 QA 失误与工具层建议。
- **真机③ 退出对话框资产腿 PASS**（v2 干净会话）：dirty 资产卡+`WM_CLOSE` → 对话框出现且文案含 **"You have unsaved changes. Save all before quitting?
Unsaved assets: t08qa3"**（ui_tree text 过滤实证）→ **Cancel**：编辑器留存+0.9 不落盘 → 再 WM_CLOSE+**Save All**：编辑器退出+**盘上写入 0.8999999761581421**（0.9 的 f32 全精度；脚本正则 `0\.9` 失配系 QA 断言缺陷，文件内容人工复核成立）。
- **LEGB 导出保存腿 PASS（补程序证据链缺口）**：dirty 卡 0.75+`game.export` → **5 秒内正本落盘 0.75**（同步保存链，代码 game_export.rs:162 印证）→ release 构建（缓存增量）完成后 **dist staging 携带 0.75**（state=ready）。程序报告偏差 3（release 超窗）就此关闭。
- **P5 真机腿——发现残留缺陷（见 QA-1）**：named 场景保存 clean（history dirty=false, undo_len=1）→ `asset.set` 资产字段（undo_len 1→2，scene_pushes 零增长）→ **tab dirty=true**。
- 附带 ⚪ 观察：**PIE stop 会关闭打开的资产卡**（后续 `asset.set` 报 `no asset is open`）——stop 恢复域 UX 小项，不阻塞，建议记 open-challenges。

## 五、QA 新发现缺陷（按严重度）

### QA-1 🟡（必修，退回理由之一）：P5 脏标隔离在「已保存基线」的 tab 上失效

`mark_active_dirty_on_history_growth` 的离开基线分支（scenes/mod.rs:384-387）：

```rust
let needs_dirty_flip = match saved_doc_hash {
    Some(_) => !was_dirty,      // 有保存基线：只要深度离开 saved 且当前 clean 就置脏，不看 grew、不看 scene_pushes
    None => grew && !was_dirty,
};
```

有保存基线的 tab（真机最常见形态：打开/保存过的场景）上，**资产字段 push（undo_len+1、scene_pushes 不变）→ `Some(_) => !was_dirty` 无条件置脏**。guards 的 `an_asset_field_edit_does_not_dirty_the_scene_tab` 用 `scene.new`（无保存基线）恰好走 `None` 分支——**测试盲区**。真机复现：clean 已保存场景+一次 asset.set → `jackdaw/history` dirty=true（undo 1→2）。影响：假脏误导（多一次无谓保存提示/退出确认），undo 回基线或保存后指纹比对自愈（LEG A post-stop dirty=False 佐证），无数据丢失。**修复方向**：`Some(_)` 分支按「基线之上的深度差是否由场景命令造成」收窄（如记录 save 时 scene_pushes 基线，比对 scene_pushes 增量），并**补一格「已保存场景+资产编辑不置脏」的 guards 用例**（dirty_matrix 或 asset_lifecycle）。

### QA-2 🟡（必修裁定，见 §七）：untitled+Save 档 Play 的资产腿缺失

### QA-3 🟡（记档，不阻塞 T2）：FallingCube 旋转速率与 move_speed 脱钩

三档实测（同一模板工程、`scene_snapshot` 两帧展开角 Δθ=2·atan2(y,w)）：

| 档（盘上文件） | dy（3s） | 角速度（Δθ/游戏时间） |
|---|---|---|
| move_speed=2.5, gravity=-9.81 | -31.703 | ≈1.98 rad/s |
| move_speed=0.5, gravity=-9.81 | -30.949 | ≈1.88 rad/s |
| move_speed=0.5, gravity=-19.62 | -61.281 | ≈1.88 rad/s |

gravity 腿三档精确跟随文件（注入链成立），但**旋转角速度恒 ≈1.9 rad/s**（接近 spin_cubes 1.0+某恒定 ≈0.9~1.0 的叠加），与 move_speed（2.5/0.5 应差 5 倍）无关——源码 `falling_cubes` 的 `rotate_y(cube.speed * config.move_speed * dt)`（fixture lib.rs:159）与实测不符，根因候选：运行构建与源不一致（构建缓存/dylib 陈旧）、旋转另有来源、或注入值形态问题。**未定谳**（8 轮真机后边界止损）；影响：T1 验收句「行为随值变化」在 move_speed 腿存疑、**T3 矩阵格 4 断言应改用 gravity/dy**（已验证可靠）；建议修复轮或 T3 前定位（首选排查 `.jackdaw/target/game` 构建新鲜度与实际旋转公式）。

### QA-4 ⚪（证据纪律）：程序 Leg B 归档矛盾

程序归档 `t08t2_live.log` 末轮记录 `LEG B FAIL: state=building stagedHas=False`，报告却称 PASS（语义证据=「staging 拷贝含 0.75」）。QA 现场复核：dist/release/assets 残留 `perceptual_roughness: 0.75`（mtime 01:58 晚于 exe 01:33，说明存在多轮导出、staging 确实携带过卡片值）——**结论方向正确、但证据取得过程未入归档日志**（违反 README 门禁证据标准「以日志全文复核为准」的精神）。QA 本轮 LEGB 已以自有归档补全双证据，不推翻结论，记档警示。

## 六、QA 自身失误记档（透明起见）

1. **覆盖 T1 归档**：复用 t08-config-play.ps1（其 OutDir 硬编码 `loop\t08-t1-live`）跑行为腿，覆盖了 T1 的 editor-stdout/stderr.log 现场日志（T1 主日志 `t08t1_*.log` 未动）。后续复用历史脚本须先改 OutDir。
2. **QUIT2 正则失配**：`-match '0\.9'` 对 f32 全精度 `0.8999999761581421` 不匹配（0.9 不可精确表示）。数值断言应匹配写入形态或用容差。
3. **PowerShell 5.1 两坑**（行为腿 8 轮中 6 轮被耗在此）：PSCustomObject 无字符串索引器（`$o.components[$TKEY]` 恒 null 静默）；`$script:out` 跨函数调用残留（analyze.ps1 首版 0.5 腿数据实为 2.5 腿残留）。**工具层建议（MCP 优先原则）**：scene_snapshot 类结构化断言应下沉为 BRP/MCP 工具（如 `scene_snapshot_diff {frames:N, seconds:F}` 或 wait 扩展返回两帧差），或在 manual.md §7 固化「5.1 索引坑+数组取值+四元数展开角」样板；T1 脚本的 Sample-FallingCube 取法（`.translation.y`）自始错误，若后续复用须改 `translation[1]`+展开角。
4. guards 全量跑时并行启动了模板工程编译，制造 journal 性能条 flaky（已隔离重跑排除）。

## 七、untitled 分叉语义裁定（核心争议）——**裁定 A：T2 内必须补**

「untitled 场景 Play 走 scene-only 保存分叉致 dirty 资产卡不自动保存」的裁定：**A（一行补齐，退回修复）**。理由链，不接受 B：

1. **默认档即中招**：`SaveBeforePlay::Save` 是 `#[default]`，其 doc 自述「Save every modified scene that has a file, then launch, **so the game loads what the editor shows**」——untitled+默认设置+dirty 卡 = 零配置踩中分叉，非「罕见组合」；程序真机 run1/2 自己就踩中（QA 复核 pie_current.rs:281-293 确认分叉结构）。
2. **验收句无 named 限定**：任务书 T2 验收标准「dirty 资产卡 + `pie.play_current` → 盘上资产新值」与 P4 缺陷定义（「卡片可见 150→Play 仍盘上 100」）均未限定场景形态；named 修了、untitled 没修=同一动作两种语义。
3. **程序辩护理由自相矛盾**：「卡未保存=跑盘上值=既定语义」——named+Save 档恰恰把「跑盘上旧值」定为 🔴 修复了；且「temp 副本路径的资产即 assets 正本」正说明游戏读正本、卡值更应落盘。
4. **T3 兜不了**：矩阵格 5 是「Play 中编辑未保存→运行中按盘上值」（Copy/运行中语义），与此处的「Save 档启动前保存」是两回事；把一行缺陷推给纯验收任务不合理。
5. 修复成本：untitled 分支（pie_current.rs:285）的 failures 并入 `save_dirty_assets` 即可，程序自估「一行可加」。

Copy/PlayUnsavedCopy 档不保存资产**可接受**（用户显式选择跑盘上值，语义自洽），本裁定仅针对 Save 档。

## 八、程序 4 条偏差的裁定

| # | 偏差 | 裁定 |
|---|---|---|
| 1 | untitled Play 保存分叉 | **退回修复**（§七裁定 A） |
| 2 | P4/W13 红证形态（结构红+行为红） | **接受**（T3 教训先例+P5 回退红 QA 亲验成立；index-miss 注入法 ⚪ 维持记档） |
| 3 | release 导出超窗 | **关闭**（QA LEGB 补证：同步落盘+dist 双证据，见 §四） |
| 4 | journal 不扩资产 | **维持**（决策 3 既定裁定，book 记录归 T3） |

另：偏差 5（blocker-directory 注入在 Windows rename 语义下失效）属实，如实记档可接受。

## 九、buglist W13 打钩核对

`buglist.md:351` `- [x]` + `> 已修复 d213f627（T08-T2）...` 备注，Edit 工具修改、格式与族内一致、备注如实（含渲染色映射与单测名）。**打钩成立**。原文「警告色永远不可达」的表述与代码事实方向相反（§二），不影响勾。

## 十、结论与退回清单

已达标：门禁四门（归档+亲跑）、红→绿（P5 回退红亲验）、真机①③+LEGB+scene_snapshot 通道与 gravity 行为腿、W13、buglist 勾、决策 3-A/4-A 主体实现质量（含双计数/拒绝语义/SaveAll 接线）。

**退回修复（一轮内可完成）**：
1. untitled+Save 档 Play 的资产保存腿（§七，一行）；
2. QA-1 watcher `Some(_)` 分支收窄 + 补「已保存场景+资产编辑不置脏」guards 用例；
3.（随本轮或挂账 T3 前）QA-3 move_speed 旋转脱钩根因排查。

复验最小集：新用例 headless 红→绿、真机 untitled+dirty 卡 Play 落盘、真机 P5 已保存场景腿（history dirty 保持 false）、dirty_matrix/asset_lifecycle 全量回归。

VERDICT: FAIL（退回修复一轮；门禁与三段真机主体全过，两项必修均为验收句直接失败路径：untitled+默认 Save 档资产腿缺失、P5 脏标隔离在已保存 tab 失效；修后按上列最小集复验，不重跑全量）

---

# 修复轮 1 重验（afe4ec41，2026-10-27 05:5x，聚焦复验·只验不修）

> 复验对象：提交 **afe4ec41** `Keep authored assets out of the scene dirty flags on every path`（15 文件 +211/−14，分支同段）。证据：`loop/t08t2r_qa_live.log`（QA 真机两腿）、`loop/t08t2r_spin.log`+`loop/t08-t2-qa-live/spinr*.json`（旋转腿）、guards 亲跑输出、`loop/t08t2r_*`（程序归档）。工作区核对：src/tests 与提交态一致（QA 回退红临时改动已还原，`git status src/` 干净）。

## 一、必修① untitled+Save 档资产腿——复现 PASS

QA 独立复跑（非程序归档路径）：my-game，dirty 卡（0.7 未保存、盘上确认无值）+ `scene.new`（untitled 在前）+ **默认 Save 档** `pie.play_current` → play running、编辑器存活、stop 归位、**盘上 t08rw3.bsn 落盘 0.7**（`LEGA PASS`，`loop/t08t2r_qa_live.log`）。修法与 QA §七建议同位（pie_current.rs else 臂 `failures.extend(save_dirty_assets)`，注释引用 QA 裁定 A）。Copy/PlayUnsavedCopy 档未动（裁定边界遵守）。

**⚪ 证据纪律记档（第二次）**：程序归档 `t08t2r_live.log` 中该腿记录为 `card-value-on-disk=False`，其「聚焦复跑通过」未入归档——与首轮 QA-4 同款（结论正确、复跑过程未留痕）。本次由 QA 归档补全。程序侧建议：每轮真机结论以最终归档日志为准，中间失败轮保留标注。

## 二、必修② QA-1 已保存基线路径——修复核实+复现 PASS（四层证据）

1. **修法 review**：`SceneTab` 新增 `saved_scene_pushes` 基线；watcher `Some(_)` 臂由无条件 `!was_dirty` 收窄为 `(below || scene_pushes > saved_scene_pushes) && !was_dirty`（上探只认场景命令、下探保守置脏）——语义正确，栈序边角（资产条目在上+undo 场景命令到基线下）保守方向正确。
2. **七处基线记录点全量核对（「漏一处就是新洞」法）**：全仓 `saved_undo_len =` 写点比对——产品代码 7 写点（save.rs×2、load.rs、open_read_scene、prefab save_as_prefab、recovery_dialog restore_tab、external_watch 归零）**全部配对** `saved_scene_pushes`；唯一未配对者（save.rs:1665）系测试内手工构造，非产品路径。**无漏网**。`recovery_dialog.rs` 的 `total_pushes`→`scene_pushes` 同性质漏网系程序自查补修（QA 未点名），核实正确。
3. **新用例亲跑**：`a_saved_scene_stays_clean_when_an_asset_field_edits_the_shared_history`（手工保存基线+资产 push→5 帧后 clean）与 `undoing_below_the_saved_baseline_still_marks_the_tab_dirty`（下探置脏）均 ok；graph 用例 `a_graph_edit_does_not_count_as_a_scene_document_push` ok（lib 1172 之一）。
4. **独立回退红**：QA 将 `Some(_)` 臂临时改回 `!was_dirty`（缺陷形态）→ 新用例 FAILED（asset_lifecycle.rs:160 断言处）+ Case 14 新期望 FAILED（dirty_matrix.rs:490）→ 还原 → 三条全绿、工作区净。程序报告的回退模拟红证据链成立。
5. **真机复现路径直接对拍**：已保存 clean 场景+`asset.set` → `jackdaw/history` dirty **before=False after=False**（undo 1→2，资产 push 在栈）——上轮 FAIL 路径翻绿（`LEGB PASS`）。

## 三、同性质补完——核实成立 + QA 上轮记录修正

- `GraphDefEdit`+node_graph 5 命令全部覆写 `touches_scene_document()=false`（注释互引说明画布数据层镜像进图文档），用例钉住。
- **ClipEventEdit 反裁定核实成立，QA 上轮误判修正**：其 `spawn()` 第 530 行调 `crate::scene_io::register_entity_in_ast`、despawn 走 `despawn_scene_entity`——事件实体注册进场景文档 AST，**属场景文档命令，默认 true 正确，不覆写是对的**。本报告 §三-1 原将其列入「动画图域漏网」清单系 QA 误判（当时只查了实体形态未查 AST 注册），如实更正；该清单修正为「GraphDefEdit+node_graph 5 命令（已由本轮覆写闭环）」。
- `AnimationGraphDoc.dirty` 自身保存链/退出保护缺口不在本轮、挂 T3 评审——归属确认合理（独立工作量，非 T2 范围）。

## 四、Case 14 期望更新——裁定成立

程序将 `resource_field_edit_undone_rolls_back_and_settles_clean` 的旧期望「资源编辑弄脏 tab（ruling 3）」更新为「资源编辑不脏 tab、undo 回滚全程 clean」并 doc 注明。**论证核实**：(a) ruling 3 是 T03 时代裁定，T08 决策 4-A 与方案 §一 P5（资源 push 点在列）已明确推翻该耦合；(b) 掩盖效应——QA 回退红实证：缺陷形态下 Case 14 **新期望必红**（本次亲测 FAILED at :490）、首轮旧期望必绿（`Some(_)` 无条件置脏满足旧断言）——首轮全绿恰是 QA-1 洞的掩盖，修复后旧期望自然暴露。这不是回归而是 4-A 语义显形，doc 注明如实。更新后用例亲跑 ok。

## 五、旋转腿（QA-3）——破案核实+新模板抽验 PASS

- **程序破案核实**：旧模板 `spawn_falling_cube` 同实体挂 `SpinningCube{1.0}`，`spin_cubes`(1.0)+`falling_cubes`(1.0×ms) 双系统叠加——成立（源码核实）；其 fixture 复验 ms=0.5 实测 **1.504 rad/s ≈ 1.0+1.0×0.5**，公式精确命中（归档 `t08t2r_live.log` LEG C）。
- **一行修核实**：新模板去掉 SpinningCube 挂载+注释写明陷阱（diff 核实+新 fixture 生成件核实）。
- **QA 独立抽验（新模板 fixture，ms=2.5）**：8 秒暖机后 2.1s 窗两帧快照——展开角 Δθ 回绕解 5.428 rad，与 dy(-21.3) 联立自洽（windowless PIE 游戏按需步进：暖机期无 BRP 请求游戏冻结、窗口 ΔT≈2.17s、从静止加速）——**角速度 5.428/2.17=2.50 rad/s，精确命中 1.0×move_speed**（`loop/t08t2r_spin.log`+`spinr*.json`）。
- **偏差 7 接受**：程序 ms=2.5 首跑 0.419 的「冷启动采样」记档口径与上述按需步进机制一致（首请求窗口小/游戏未及追帧），QA 以暖机+联立解钉住公式后该记档成立。

## 六、门禁（返工轮）

归档复核（`loop/t08t2r_*`）：fmt 空=clean；clippy 0 error；lib **1172**/0（+1 graph 用例）；guards **204**/0（55.29s，无 FAILED/panicked，5 条 asset_lifecycle 在列）。QA 亲跑：guards 全量 **204 passed / 0 failed**（56.26s，本轮无并行编译干扰）；新用例/Case 14/graph 用例单跑全绿。

## 七、结论

QA 退回单闭环：两项必修（untitled 资产腿、QA-1 已保存基线路径）修复核实+真机复现+新用例红绿；两项同性质（动画图域覆写、recovery_dialog）补完；QA-3 破案+模板一行修+抽验命中；Case 14 期望更新裁定成立；门禁全过。QA 上轮 ClipEventEdit 误判已更正。残留记档：程序真机归档证据纪律（两次，⚪）；`AnimationGraphDoc` 保存链与 PIE stop 关闭资产卡挂 T3（⚪）。无新 🔴/🟡。

VERDICT: PASS（修复轮 1 验收通过，建议主控 --no-ff 合入；T3 前置提醒：矩阵格 4 行为断言主腿用 gravity/dy，旋转腿可用新模板；AnimationGraphDoc 保存链与 stop 关卡两项 T3 评审）
