# 功能 #4「System Graph 增强」终验 QA 报告（任务 3 + 功能级）

> 多 Agent 开发循环 · QA（独立第三方验收）· 2026-10-22
> 对象：分支 `loop/system-graph` @ `56f5011c`（基于 main `2c3b86dc`，任务 2 合入后）
> 方式：四门全部自跑（真实退出码经 `cmd /v:on` 延迟展开复核，规避 CMD `%ERRORLEVEL%` 解析期展开陷阱）+ diff 逐行核实 + 盘点表独立脚本验算 + 文档事实逐条对照源码。未采信程序报告自述数字。

## VERDICT: **PASS（功能级）**

---

## 1. 确定性门（全部亲跑，真实退出码）

| 门 | 退出码 | 证据 |
|---|---|---|
| `cargo xtask fast`（内含 fmt + clippy --all-targets --features dylib -D warnings） | **0** | Summary: **2798 tests run: 2798 passed, 2 skipped**（任务 2 基线 2796 → +2 恰为本任务新增 2 测，两测均亲见 PASS：`degraded_hint_distinguishes_disconnected_from_old_game`（#615）、`parsed_accesses_drive_the_box_badge`（#646））；仅有 toolchain 级 `linker_messages` warning（rust-lld 忽略 `-fuse-ld=lld`，lint 自述 ignores `-D warnings`），与历轮一致、非代码问题 |
| `cargo xtask integration` | **0** | Summary: **4929 passed / 3 skipped**（基线 4927 → +2，同上两测亲见 PASS） |
| `cargo doc --locked --workspace --document-private-items --no-deps` | **0** | 恰 2 条 intra-doc 警告：(a) `src/pie.rs:10:45` BuildKey——既有；(b) `crates/jackdaw_remote/src/ecs_methods.rs:147:42` `system_access_entries` → 私有 `ambiguities_for`——**定性核实为任务 1 引入**（见 §3.1） |
| `cargo test --locked --workspace --doc --features bevy/dynamic_linking --no-fail-fast` | **101（既有，非回归）** | `error: 3 targets failed: -p jackdaw_bind --doc / -p jackdaw_feathers --doc / -p jackdaw_node_graph --doc`——失败集合与 feature-01/02/03 终验基线**逐项相同**；本功能改动与三失败 crate 零交集。注：QA 首次取退出码时被 CMD 解析期展开污染显示 0，经 `cmd /v:on !ERRORLEVEL!` 复核为 **101**，与程序报告一致 |

## 2. 任务 3 规格（逐条）

### 2.1 三态提示 — ✅
`depgraph.rs` 新纯函数 `degraded_filter_hint(Option<&SchedulesReply>) -> &'static str`：`None` → `"connect to a game to filter by component access"`（连接类文案）；`Some && !access_reported` → `"component access data requires a newer jackdaw_remote"`（升级提示）；`Some && true` → `""`。meta 行后缀由「一律 !access_data」收紧为 `reply.as_ref().is_some_and(|r| !r.access_reported)`（仅连接且老才追加，断连时 "no schedules" 已说明问题）。测试含**真实反断言** `!disconnected.contains("jackdaw_remote")`（亲见 PASS）——任务 2 QA ⚪-1 断连措辞失真问题处置到位。

### 2.2 schedules 徽标单一来源 — ✅
`use super::depgraph::access_badge`（schedules.rs），diff 中**零复制粘贴**：`system_name_row` 仅调用 depgraph 的同一函数生成 `R2 W1`/`ALL`/`EXCL`（TEXT_SIZE_XS + TEXT_SECONDARY，文本非颜色，照 depgraph 范式）。老回复 serde 缺省 `accesses` 为空 → `access_badge` 返回 None → 徽标自然降级，测试 `parsed_accesses_drive_the_box_badge` 端到端钉住（新回复 `Some("R2 W1")` / 老回复 `None`，亲见 PASS）。set chips 行为零改动（diff 无涉）。

### 2.3 隐藏 toggle 确未做 — ✅（符合裁定）
`rg -i "hide|toggle"` 全查 depgraph.rs 唯一命中为 picker 开关注释（:608），无隐藏节点 toggle。

### 2.4 book 文档 — ✅（附一条 ⚪ 见 §5）
- 新页 `user-guide/remote-debugging.md`（80 行）+ SUMMARY（Play-in-editor 之后）+ `remote-control.md` 双向互链，三条新链接目标均存在（沿 feature-03 人工核对法，本机无 mdbook）。
- **内容与实现一致性逐条对照源码**：AND 语义（picked 全命中）、From selection OR 语义 + 两级取值（远程优先/本地兜底）+ meta 组件计数、`ALL`/`EXCL` 恒命中、全路径+末段短名兜底、降级两情形文案与代码**逐字一致**、升级零游戏代码改动（D5）——均与 `access_matches`/`matches_filter`/`selection_components`/`degraded_filter_hint` 实现相符；事实项核实：`DEFAULT_PORT=15702` + `with_port`（lib.rs:21,54）、默认 endpoint `http://127.0.0.1:15702`（connection.rs:31）、状态栏指示器 + Connect 按钮（panel.rs:41,188）、边截断 meta 行 ", showing N of M edges"（depgraph.rs:469 + graph.rs MAX_EDGES=120）。

### 2.5 盘点表 — ✅（独立验算）
- 未分类「system graph 可视化」🟡→✅，证据含 d914073e（数据链）+ 88968fcf（过滤/着色/反查）+ 任务 3 指针（指向 `feature-04-t3-report.md`，报告内有 56f501c；`loop/` 不入 git 故指针合理）；**set 过滤动词 backlog 备注在行内**（主控裁定口径）。
- **统计独立验算**（PS 脚本逐节逐行实数）：✅46 / 🟡14 / ❌15 = **75**，与统计行一致；未分类节标题「5✅/6🟡/12❌」与实数行自洽；Stage 2 标题「7✅」实为 6 行系 feature-01 期已知历史偏差（统计行自注在案），非本次引入。

### 2.6 无越界 — ✅
diff 恰 5 文件（SUMMARY.md、remote-control.md、remote-debugging.md 新、depgraph.rs、schedules.rs）；任务 1/2 已验收的 ecs_methods.rs / graph.rs / debug/mod.rs / relationships.rs **零触碰**；depgraph.rs 内改动仅限三态提示（+模块文档措辞）、schedules.rs 内仅徽标行——均在任务 3 范围内，无需「修复必需性」辩护。

## 3. 功能级终验（方案 §5 清单）

### 3.1 确定性门 6/6 — ✅
fmt ✓（fast 内含，0）· clippy -D warnings ✓（fast 内含）· fast ✓0 · integration ✓0 · doc ✓0 · doctests 101 基线集合逐项相同非回归 ✓。
**ecs_methods.rs:147 警告定性（QA 独立核实）**：警告源为 doc 注释 `` [`ambiguities_for`] `` 链接——`git show d914073e` 证实该行**由任务 1 添加**；任务 3 的 5 文件 diff 不含 ecs_methods.rs；任务 1/2 QA 门清单均未含 cargo doc，故本轮 doc 门首跑才暴露。**一行可修**（去链接反引号或改纯文字），⚪ 级不阻塞，建议下轮顺手修。

### 3.2 headless 行为断言 7/7 — ✅（全部在本次 fast 门亲见 PASS）
server 五类访问 + 能力标志 + 数字回退（`jackdaw_remote ecs_methods::tests::*` 7 测，#1875-1881）· 老回复 serde 降级守卫（`reply_defaults_access_fields_when_absent`）· AND/OR/恒命中/短名兜底（`manual_filter_requires_every_component` / `selection_filter_matches_any_component` / `unbounded_and_exclusive_match_any_component` / `short_name_fallback_matches_across_namespaces`）· 反查提取（`selection_components_{sorted,empty}_*` 两测）· 徽标文本（`access_badge_counts_reads_and_writes` / `access_badge_marks_all_and_exclusive_and_none`）· 回归锚点（`node_color_defaults_without_filter`）· 新增三态/徽标两测。

### 3.3 文档项 2/2 — ✅
book remote debugging 节（过滤/徽标/From selection/降级条件全含）+ roadmap 未分类行更新（D7 口径 + 统计 46/14/15）。

### 3.4 人工项 — 留用户手测（建议清单见 §6）
真机 release 帧尖刺（<5ms 门槛，方案 B 裁决依据）、过滤/反查实机走查、老游戏降级目验。程序报告 §4 已如实自列未验证，QA 认定保留合理。

## 4. 问题统计

| 级别 | 数量 |
|---|---|
| 🔴 严重 | 0 |
| 🟡 中等 | 0 |
| ⚪ 轻微 | 3 |

## 5. 发现（分级）

- ⚪ [程序] book 新页将 queries 面板称作 "**Live Queries**"，实际注册窗口名为 "**Remote Queries**"（`builtin_extensions.rs:150`，其余面板 doc 用简称可对应，唯此词改变识别词）——一词之差、无功能影响，建议下轮文档微调顺带修正。
- ⚪ [程序/任务 1 遗留] `ecs_methods.rs:147` intra-doc 私有链接警告——任务 1 引入、本轮 doc 门首暴露，一行可修（§3.1），不阻塞。
- ⚪ [环境] doctests exit 101——Windows + bevy_dylib + merged doctests 既有环境问题，失败集合与 feature-01/02/03 基线逐项相同，非回归，维持 CI known-issue（附议非 Windows 复核）。

## 6. 用户手测建议（3-5 条）

1. **真机 release 帧尖刺复测**：`examples/remote_game.rs` 以 `--release` 运行 + 编辑器 Connect，对比连接前后帧时间，确认 1s 轮询周期尖刺 <5ms——超标即触发方案 B（拆 `jackdaw/system_access` 独立方法）裁决，这是功能级唯一未闭环的量化门槛。
2. **过滤/反查实机走查**：输入 `Transform` 过滤看命中高亮/非命中暗化/歧义红框保留；远程树选中实体 → From selection 看 meta 行组件数与 OR 命集是否符合直觉；chip 移除与 Clear 恢复。
3. **老游戏降级目验**：用旧版 `jackdaw_remote` 编译的游戏连接（或临时 mock 无新字段 reply），确认过滤行显示升级提示、徽标消失、图渲染如旧；再断开连接，确认提示切换为 "connect to a game…" 且 meta 行无 `, access data unavailable` 后缀。
4. **大 schedule 目验**：选边数超 120 的 schedule，确认 meta 行截断说明与布局稳定（本功能只改色/加小字，不应引入新卡顿）。
5. （可选）mdbook 渲染下走查 SUMMARY → Remote Debugging → Remote Control 互链可点击（本机无 mdbook，QA 仅静态核对目标存在）。

---
*证据：门日志 `%TEMP%\t3_{fast2,int2,doc2,doctest3}.log`（真实退出码经 `cmd /v:on` 延迟展开复核）；盘点表验算 PS 脚本逐节实数输出 46/14/15=75。*
