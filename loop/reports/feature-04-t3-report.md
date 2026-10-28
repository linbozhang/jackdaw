# 功能 #4「System Graph 增强」任务 3 报告：schedules 徽标 + 降级措辞修正 + 文档 + 盘点表 + 全量 CI 门

> 多 Agent 开发循环 · 程序（Rust/Bevy 工程师）
> 分支 `loop/system-graph` · 提交 **56f5011c** `Add schedules access badges, fix degraded-state hints, document access filtering`（5 文件，+230/-17，基于任务 2 合入后的 main 2c3b86dc）
> 方案：`loop/plans/feature-04-system-graph.md` 任务 3 + QA 移交项（任务 2 QA ⚪-1 断连措辞）；主控裁定：徽标做、隐藏 toggle 留 backlog（未做，符合裁定）。
> `loop/` 目录按仓库惯例不入 git（.git/info/exclude），盘点表与本报告为本地文件。

## 1. 全量 CI 门（逐条退出码，本会话实测）

| 门 | 命令 | 退出码 | 结果 |
|---|---|---|---|
| fast | `cargo xtask fast` | **0** | fmt check + clippy --workspace --all-targets --features dylib -D warnings + lib tests：**2798 passed / 2 skipped**（任务 2 基线 2796 → +2，恰为本任务新增单测 2 个） |
| integration | `cargo xtask integration` | **0** | **4929 passed / 3 skipped**（任务 2 基线 4927 → +2，同上两测） |
| docs | `cargo doc --locked --workspace --document-private-items --no-deps` | **0** | 两条 intra-doc 警告**均非本 diff**：`src/pie.rs` BuildKey 既有；`crates/jackdaw_remote/src/ecs_methods.rs:147` `system_access_entries`→私有 `ambiguities_for` 链接系任务 1（d914073e）引入、本任务全量 doc 门首次跑出（任务 1/2 QA 均未含 doc 门），⚪ 级、门仍 0；建议下轮一行小修（链接去 backtick 或改文字） |
| doctests | `cargo test --locked --workspace --doc --features bevy/dynamic_linking --no-fail-fast` | **101（既有，非回归）** | 失败集合**恰为** `-p jackdaw_bind --doc`、`-p jackdaw_feathers --doc`、`-p jackdaw_node_graph --doc` 三项，与 feature-01/02/03 基线逐项相同，零新增失败 → 非回归 |

另：`cargo fmt --all -- --check` 单跑 exit 0（fast 门内含）。

## 2. 范围四件事

### 2.1 schedules 面板读写徽标（主控裁定：做）

`src/remote/debug/schedules.rs`：`system_box` 的名字段抽为 `system_name_row`——短名 + 可选徽标（TEXT_SIZE_XS、TEXT_SECONDARY 小字，**文本非颜色**，照 depgraph 任务 2 徽标范式），徽标字符串**直接复用 `depgraph::access_badge`**（schedules.rs 新增 `use super::depgraph::access_badge`，两面板单一来源、语义不可能漂移）：`R2 W1` 读/写计数、`ALL`（unbounded）、`EXCL`（独占）、无访问数据无徽标。老回复 serde 缺省 `accesses` 为空 → 徽标自然缺席，**无需显式能力开关即自降级**（与 D5 字段缺席即降级的设计一致）。无 set chips 行为改动；隐藏 toggle 按裁定未做。

### 2.2 降级措辞两情形修正（任务 2 QA ⚪-1 处置）

`src/remote/debug/depgraph.rs` 新增纯函数 `degraded_filter_hint(Option<&SchedulesReply>) -> &'static str`：

| 情形 | reply 状态 | 过滤行文案 | meta 行 |
|---|---|---|---|
| 断连 | `None` | `connect to a game to filter by component access`（连接类文案，**不含 jackdaw_remote 字样**） | 仅 `no schedules`（后缀不追加——断连时"no schedules"已说明问题，恢复特性前形态） |
| 老游戏 | `Some` 且 `access_reported == false` | `component access data requires a newer jackdaw_remote`（沿用任务 2 原文，该情形下准确） | 追加 `, access data unavailable`（meta 后缀由「一律 !access_data」收紧为「仅连接且老」） |
| 正常 | `Some` 且 `access_reported == true` | 正常过滤行 | 无后缀 |

测试 `degraded_hint_distinguishes_disconnected_from_old_game`：三态各自断言文案 + **显式断言断连文案不含 "jackdaw_remote"**（防止回归）。`rebuild_depgraph` 调用点 `reply.as_deref()`（`Option<Res<T>>` → `Option<&T>`）。

### 2.3 book 文档

- **新页 `book/src/user-guide/remote-debugging.md`**（80 行）：连接方式（游戏 `JackdawRemotePlugin`、端口 15702/`with_port`、状态栏指示器 Connect、默认 endpoint）→ Remote Debug workspace 面板族 → Schedules 面板（运行序/set chips/徽标语义）→ System Graph（分层图/红边红框歧义/边截断说明/过滤行 AND 语义+恒命中+短名兜标/From selection 两级取值+OR 语义+计数/clear）→ 降级两情形（引用文案与代码逐字一致）+ 升级路径（升级 jackdaw_remote 重编即可、游戏代码零改动）。事实逐条对照源码（`panel.rs`/`connection.rs:31`/`lib.rs build_debug_tree`/`graph.rs MAX_EDGES`）。
- `SUMMARY.md` User Guide 增 `Remote Debugging`（Play-in-editor 之后）；`developer-guide/remote-control.md` 开头加一段「编辑器被远控 vs 编辑器远查游戏」的双向区分并互链。
- **链接核对（本机无 mdbook，沿 feature-03 基线人工核对法）**：新增链接恰 3 条——SUMMARY→`user-guide/remote-debugging.md`、remote-debugging→`../developer-guide/remote-control.md`、remote-control→`../user-guide/remote-debugging.md`，目标文件均存在，无断链；未动既有链接。

### 2.4 盘点表 `loop/plans/roadmap-gap-analysis.md`（本地不入 git）

- 未分类「system graph 可视化」🟡→✅：证据列指向 d914073e（访问表数据链）/ 88968fcf（depgraph 过滤着色反查）/ 本任务（56f5011c：徽标+措辞+文档）；**备注「set 过滤动词未单独落地（set 归属显示已有），留 backlog」**（D7/主控口径）。
- 统计行 75 项 **✅46 / 🟡14 / ❌15**（前值 45/15/15）；未分类小节标题 4✅/7🟡/12❌ → **5✅/6🟡/12❌**；备选 5 标题加「✅ 已落地」标记（沿备选 4 先例）。

## 3. 新增测试（2 个）

- `remote::debug::depgraph::tests::degraded_hint_distinguishes_disconnected_from_old_game`（三态文案 + 断连不含 jackdaw_remote 反断言）
- `remote::debug::schedules::tests::parsed_accesses_drive_the_box_badge`（serde 解析结果驱动徽标：新回复 `R2 W1` / 老回复 None——面板降级守卫的端到端纯函数链）

fast/integration 各 +2，与 §1 计数吻合；徽标复用的 `access_badge` 本体 6 断言系任务 2 既有测试，未重复计。

## 4. 未验证项（如实记录，留用户/终审）

- **真机 release 帧尖刺复测（<5ms/秒门槛）属人工项**：未验证，留用户/终审（方案 D2-3 的方案 B 拆分决策依赖此项）。
- `examples/remote_game.rs` + 编辑器 Connect 的人工 QA 走查（过滤高亮实机、From selection 实机、老版本降级驱动）属方案 §5 人工清单：本任务以 headless 纯函数 + serde 两态单测覆盖可自动化面，UI 实机**未验证**。
- book 未跑 mdbook build（本机无 mdbook，沿基线人工核对法）。

## 5. 遗留 / Concerns

1. doctests 门 exit 101：既有环境性失败（同基线三 crate 集合，`--no-fail-fast` 实核），非本任务引入，维持遗留。
2. `ecs_methods.rs:147` 的 intra-doc 私有链接警告（任务 1 引入、本次 doc 门首跑暴露）：不影响门退出码，建议下轮顺手一行小修。
3. 断连提示行静态文案未随连接状态横跳（reply 在断连后被 poll 清空即切换，与既有面板行为一致）；QA 曾提「断连后禁用态短暂滞后但 no-op 安全」，本任务未改该时序。
