# T06-T1 QA 验收报告：「运行当前场景」通道

> QA 角色产出，2026-10-24（验收执行）/ 程序报告 2026-10-26。分支 `loop/t06-play`，提交 `1bf371c1`
> （父 `213e3370` = main 闭环点），10 文件 +2114/−46。
> 规格：`loop/plans/t06-play-isolation.md` §二 T1 + §三决策点（7 项已裁）。
> 程序报告：`loop/reports/t06-t1-report.md`。验收方法：归档日志全文复核 + 抽亲跑 + git 考古 +
> 独立真机复跑（只验不修）。

## 一、门禁复核（2026-10-25 升级标准：日志全文复核为主）

### 1.1 归档日志全文复核（loop/t06t1_*.log）

| 门 | 归档 | 复核结论 |
|---|---|---|
| fmt | `t06t1_fmt.log`（0 字节） | `--check` 通过时零输出，与空日志自洽；QA 亲跑 fmt（见 1.2）交叉验证 PASS |
| clippy | `t06t1_clippy.log` | 全文仅既有工具链噪音（rust-lld `-fuse-ld` ×1、build script duplicate ×4），workspace 全部 Checking 后 `Finished`，无 error。与程序报告描述一致 |
| lib | `t06t1_lib.log` | 逐 crate 加总 **2893 passed / 0 failed**（主编译器 crate 1155 含 pie_current 8）；日志中的 ERROR/WARN 行全部是测试故意制造的失败场景（`a_failed_*` 系列用例自身输出），非真实失败 |
| guards 全量 | `t06t1_guards_full.log` | **192 passed / 0 failed**（41.49s，2026-10-26T00:56Z）；Select-String 命中的 "failed" 全为测试名自带字样 |
| runtime | `t06t1_green_runtime_final.log` | **4 passed / 0 failed** |
| main 基线 | `t06t1_guards_main_baseline.log` | main 旧码全量 **180 passed / 0 failed**（=192−12，对照自洽：journal 计时测试在 main 并行度下不超限） |

门禁表引用日志均为终态绿版本，旧失败日志（guards1 等）系开发过程证据、未被门禁表引用，符合「重跑覆盖归档」标准。

### 1.2 QA 亲跑（必跑两项 + fmt 交叉）

| 命令 | 结果 |
|---|---|
| `cargo test -p jackdaw --test guards play_current_scene` | **12 passed / 0 failed**（180 filtered out，10.75s，exit 0） |
| `cargo test -p jackdaw_runtime --test pie_scene_override` | **4 passed / 0 failed**（0.06s，exit 0） |
| `cargo fmt --all -- --check` | exit 0，零输出（交叉验证 0 字节归档） |

**门禁四门：PASS。**

## 二、红→绿真实性

### N1（Play 恒跑游戏自决场景）

- 红证 `loop/t06t1_red_runtime.log`（2026-10-26 05:06，stash 旧码复演）：**0/3 failed**。
  核心红证 panic 属实：`the first root plays the override: ["Anchor", "Second", "scene", "second"]`
  ——旧 runtime 无视 `JACKDAW_PIE_SCENE`，spawn 的是游戏自决场景（Anchor=scene.bsn）的实体而非
  override 文档（Overridee）的实体。**行为级红证成立。**
- ⚪ **QA 补充披露（程序报告未记）**：0/3 中另两条（`the_override_scene_loads...`、`without_the_env...`）
  的 panic 是 `PoisonError` 连锁——第一条 panic 毒化了 env 锁（当时测试文件用裸 `.unwrap()`）。
  其中 `without_the_env`（回归锚点）在旧码上的失败是假失败（本应通过）。提交版测试已加
  poison recovery（`unwrap_or_else(|poisoned| poisoned.into_inner())` + 注释），红证的本质
  （旧码上行为缺失导致测试失败）由第一条独立成立，绿证 4/4 时三条均真过。不影响红→绿成立。
- 绿：亲跑 4/0（见 §1.2）。

### N2（untitled 两向都错）

- 红证 `loop/t06t1_red_probe_old_code.log`（08:08）：探针 `tests/play_current_red.rs` 在旧码上
  **0/1 failed**，panic 消息 `pie.play_current exists: UnknownId("pie.play_current")`——「运行当前
  场景」概念在旧编辑器侧不存在。**红证成立。**
- 绿：`loop/t06t1_red_probe_final.log` 1/1（副本落盘、含未保存编辑、tab 仍脏）。
- **删除顺序证据成立**：红证日志归档（08:08 old_code）→ 探针绿证归档（08:56:29 final）→
  提交 08:58:13（`git log --all -- tests/play_current_red.rs` 零结果，探针未入库）。
  常驻版本 `tests/guards/play_current_scene.rs` 12 条在库。

**红→绿：真实。**

## 三、真机独立复跑（QA 亲自执行，非程序 run6 回放）

构建：QA 先 `cargo build -p jackdaw`（1m01s，仅既有工具链噪音）确保 exe 为提交版。
脚本：`loop/qa/t06-play-current.ps1`（端口 15713 隔离，跑前杀旧进程）。**结果
`T06T1_PLAY_CURRENT_LIVE_PASS`，exit 0**，日志归档本次输出；四用例：

| 用例 | 关键断言（QA 复跑实测值） | 结果 |
|---|---|---|
| A untitled→副本 | 副本 `current-untitled-1-41200.bsn` 落盘含 cube 文档；**Live 树 count=3 names=[current-untitled-1-41200, Cube, Directional Light]**（游戏加载的就是点前缀副本，决策 6 复证）；stop 后副本清零 | 全过 |
| B named（pie-probe.bsn） | 日志 `launched with scene override 'pie-probe.bsn'`；无副本；Live 树 names=[pie-probe, Cube, Directional Light] | 全过 |
| C Ask | 对话框出现；三按钮齐（Save / Play Unsaved Copy / Cancel）；真机点 Play Unsaved Copy → 副本 `current-pie-probe-41200.bsn`、盘上 hash 不变、override 计数 2→3 | 全过（Ask 抽查=Copy 按钮） |
| D pie.play 对照 | override 计数保持 3（无新 override 行）；Live 树 count=24（=scene.bsn 大场景）——启动场景语义零回归 | 全过 |

- 验收要求的两例（①untitled 副本+投影 names 断言、②pie.play 无 override 对照）均独立复现。
- C 用例实测 `pie.stop` 首次返回 **cancelled**、重试后成功——偏差②竞态被 QA 复跑实测复现，
  佐证其真实性。
- **my-game「零源码改动」声明验证**：my-game 无 git 提交基线（全 untracked，无 diff 可看），
  但更强证据成立——`src/lib.rs` 的 `spawn_scene` 仍硬编码
  `commands.spawn(JackdawSceneRoot(asset_server.load("scene.bsn")))`，无任何 `pie_scene_or` 引用；
  换把完全依赖 runtime 侧 env 机制（决策 1-A「存量工程零改动受益」实证）。
- 残留清理：QA 复跑产生的 `assets/pie-probe.bsn` 已由 QA 删除（脚本自身不清理该文件，
  ⚪ 见 §7-⑩），`.jackdaw-pie/` 目录为空，无 jackdaw 残留进程。

**真机：PASS。**

## 四、代码 review（六重点）

1. **换把只作用首个 Added root、不碰非 JackdawSceneRoot 游戏**：
   `apply_pie_scene_override`（`crates/jackdaw_runtime/src/lib.rs:613-637`）query 只匹配
   `Added<JackdawSceneRoot>`，无 env 早退零查询零命令（回归锚点测试钉住）；非
   JackdawSceneRoot 加载路径零接触；支持面口径写在 `PIE_SCENE_ENV` 文档注释。
   **🟡 N-QA1（新发现）：「首个」按帧判定而非按进程**——系统挂 Update 每帧跑，游戏在运行期
   **后续帧**动态 spawn 的新 scene root 也会被换把（该帧 Added 集合的最小 index 者），与代码
   注释「Only the first added root is swapped; further roots keep the scenes the game's own
   code named」不符。同帧多 root 有测试（`only_the_first_scene_root_is_overridden`），跨帧无
   覆盖。影响面：PIE 会话中动态加载场景的游戏会静默拿到 override（N1 同类危害，触发面窄；
   动态场景加载归 T13 领域，T06 主链路=启动加载不受影响）。建议最小修复：`Local<bool>`
   已换标记，换过后 no-op。移交 T2/T3。
2. **三态 serde 兼容读 + 迁移用例真实性**：手写 `Deserialize`（`visit_bool` true→Save /
   false→PlayUnsavedCopy、`visit_str` snake_case 三值、未知值拒绝）+ `Serialize(rename_all =
   "snake_case")` 两侧一致；迁移用例 `the_settings_section_migrates_a_legacy_bool` 走真实
   `project_settings::load_section` 读整段 settings.json（非裸 serde 单测）。round-trip、
   未知值拒绝、sanitize、sweep、prefab 回落解析、assets 相对路径拒绝等单测齐全。✅
3. **temp 副本生命周期**：pid 防互踩（`current-<stem>-<pid>.bsn`，同 pid 重放覆盖旧副本无害）；
   孤儿清扫（project_select 项目打开时全清 `current-*.bsn`、非 current-* 不动、二次空操作，
   单测钉住）；stop 删除 + `PieSession::drop` 双保险（`remove_temp_copies` 容忍 NotFound，
   对应第二编辑器全清限制）；**刻意不进 journal**——`write_pie_temp_copy` 只走
   `emit_bsn_scene_for_file` + `write_atomic`（纯文件层 fsync+双 rename，与 journal 无耦合，
   `document.rs:105` 核对）；**不误触发 external_watch**——`scenes/external_watch.rs` 头注释
   实证「watcher over the files the open tabs point at」，副本非 tab 文件零联动。✅
   后台 tab emit 的 swap-in/out 换焦设计可接受（emit 需读 active 文档）。
4. **偏差③共享锁串行化：治了挤兑，不是掩盖**。证据链：(a) 锁粒度=play_current_scene 模块内
   12 用例互斥（12 个 `#[test]` 各持 `play_lock()`，其它 guards 模块照旧并行）；(b) journal 5ms
   计时门在锁外单跑恒准（`t06t1_journal_perf_rerun.log` 1/1、`t06t1_min_repro1.log` 1/1）；
   (c) main 基线全量并行 180/0（既有并行度不超限，问题随新 12 路重型测试引入）；
   (d) journal 测试本身未被改动（未放宽阈值/未跳过）——修复方向是新测试对既有脆弱计时测试
   礼让，正确；(e) 另做了空 workspace manifest 快失降低测试自身 IO（guards editor() 注释）。
   串行后全量 192/0 稳定。⚪ N-QA3：程序报告称「连续三次全量失败」，**直接的失败日志未归档**
   （归档只有对照组四件），定性结论由对照组闭环支撑，记档不阻断。
5. **F5 键位注册路径同构声明**：`bind_operator_host::<PiePlayCurrentOp>([PresetInput::key("F5")])`
   与仓库既有先例同构（`examples/extension/dynamic_extension` F9/F10、`viewable_camera_extension`
   F6/F7、navmesh Digit8+alt）。F5→op 派发走 keymap 通用设施，guards 层 op 经 operator surface
   可达（12 用例）。未做真机键盘注入——口径可接受，留 T3 用户 30 秒清单抽查。⚪
6. **toggle 三态循环与旧 id 兼容**：`project.toggle_save_before_play` 保留旧 id（diff 确认仅改
   description 与循环逻辑 Save→Ask→Copy→Save），旧脚本/BRP 调用零破坏（无参数 op）；新 op
   `project.set_save_before_play mode=` 显式设置并持久化（真机 C 用例实测生效）。
   ⚪ 记档语义变化：旧二态「两次 toggle 回原值」变为三态三次循环（声明过的升级）；
   键位清单无默认绑定 toggle。

**review 结论：无新 🔴；新 🟡 ×1（N-QA1 换把跨帧）+ ⚪ ×3。**

## 五、11 条偏差逐条裁定

| # | 偏差 | QA 裁定 |
|---|---|---|
| ① | wait `seen_active` 竞态 | **属实、既有**。git 考古：本提交对 `src/remote/server.rs` 零改动（`git log 213e3370..1bf371c1 -- src/remote/server.rs` 空）；main 213e3370 上 `seen_active: false` + `seen_active \|= status != "stopped"` 原样存在，竞态机理成立。QA 脚本轮询 `status.pie` 规避合理。接受，移交 T3 `jackdaw/pie` 设计消除 |
| ② | `pie.stop` avail 门竞态 | **属实、既有**。main 上 `pie.stop` 的 `is_available = play_is_running`（`state != Stopped`）原样，本提交未动；QA 真机复跑 C 用例**实测复现**（stop 首次 cancelled、重试过）。与 Y34/N6 近邻，T2 一并收口。接受 |
| ③ | temp 副本不含 terrain sidecar | 接受为已知限制（方案 §二 T1.3b 处方即「emit 当前文档」，非实现偷工）；T3 book 必须注记 |
| ④ | 孤儿清扫全清（双编辑器互踩） | 接受为已知限制（触发面：同项目双编辑器+PIE 并行，极窄；运行中游戏已载入内存仅 reload 受影响；stop 清理容忍 NotFound 已单测）。完整核对归 T3 矩阵 #9/#10 |
| ⑤ | Reload（current 模式）不重算 override | 接受（reload=重建会话、override 随 stop 丢弃的语义可辩护）；矩阵 #8 归 T3 时需把语义写明 |
| ⑥ | 启动场景三态保守映射（Ask→保守取 Save） | **裁定合理**。启动场景路径无「当前场景」心智，不弹窗不打断旧路径；不对称风险上误保存（有 .bak 可回退）远轻于误不保存（旧 false 的静默错场景），保守取 Save 方向正确；PlayUnsavedCopy→不保存忠实旧 false。doc 已写明。接受 |
| ⑦ | toggle 保旧 id + 新 op set | 实现与声明一致（diff 核实）。接受；⚪ 附带语义变化记档（见 §四.6） |
| ⑧ | F5 未真机注入验证 | 口径可接受（同构先例充分）；T3 用户清单抽查 |
| ⑨ | 模板毕业未 scaffold 实编 | **可接受但偏弱**。模板是文本、不受编译门覆盖，语法错误只在新工程暴露；缓解：改动极小（字面量→`pie_scene_or` helper，返回 String 与 `AssetServer::load` 的 `Into<AssetPath>` 兼容）+ helper 有单测。**行动项：T3 真机矩阵顺带 scaffold 一个 fixture 工程实编一次** |
| ⑩ | 真机后清理 | 程序侧已清理属实（QA 复跑前确认）；⚪ 补充：QA 脚本自身不在 finally 清 `pie-probe.bsn`（每次跑完留探针），本次由 QA 手动删除；建议脚本 finally 补一行 |
| ⑪ | Stop 时 ChildOf 悬空 WARN | 接受（一帧自愈的时序现象，方案 B 节 ❓selection 邻居）；T2 实测定性 |

## 六、方案 T1 验收清单逐项对照

| 方案 §二 T1 验收项 | 证据 | 判定 |
|---|---|---|
| runtime：override→换把→spawn 内容断言；无 env 锚点；多 root 只换首个 | `pie_scene_override.rs` 4 用例（QA 亲跑 4/0） | 过（跨帧缺口见 N-QA1，方案原文未细化到跨帧） |
| editor：dirty named+Save 保存链/override=相对路径；Copy 副本+盘上不变+同源 emit；untitled 两策略（N2 红先落） | guards 12 用例（QA 亲跑 12/0）+ N2 红证 | 过 |
| prefab 回落 / 全 prefab 拒绝 | guards 2 用例 + 单测（回落取最近、tie 取先、全 prefab None） | 过 |
| stop 清理（副本删、容忍已消失） | `stop_cleanup_tests` 3 例（删/容忍/去重登记） | 过 |
| 孤儿清理（预置被清、非 current 不动、二次空操作）+启动接入 | `pie_current.rs` 单测 + `project_select.rs` diff | 过 |
| 设置兼容（旧布尔两向、整段读、round-trip、未知拒绝） | `pie_current.rs` 单测 4 例 | 过 |
| 真机 BRP 链（非 scene.bsn→running→override 断言→投影对账→stop 清副本） | 程序 run6 + **QA 独立复跑 A-D 全过** | 过（口径备注两处，见下） |

**遗漏/口径降级（QA 发现）**：

- 🟡 **N-QA4：方案 §五.2 明文「T1 验收补一条衔接用例：dirty tab → Play（Save 态）→ kill 编辑器
  → 重启后 journal 无该 tab 条目（已持久化）」——报告 §六未列、guards 与真机脚本均未含**。
  风险评估：Play(Save) 走 `save_scene_inner` 原子链（journal 出局与普通保存同链），实际风险低，
  但方案明文要求的验收用例缺失。移交：并入 T2 Stop 还原铁证链（kill 重启链路天然覆盖）或 T3。
- ⚪ N-QA5：方案原文真机断言「投影流 scene_node_id 集合 ⊇ AST stable id 集合」，实际用 Live 树
  names 断言替代（B 用例 names 含 pie-probe、D 用例 count=24 对照）。对「游戏加载了哪个场景」
  证明力足够，但弱于 stable id 对账（同名歧义、无层级）；T3 `jackdaw/pie` 按方案原文补齐。

## 七、QA 汇总

- 新发现问题：🟡 ×2（N-QA1 换把跨帧与注释不符、N-QA4 方案 §五.2 衔接用例缺失），
  ⚪ ×5（N-QA2 红证 PoisonError 连锁未披露、N-QA3 journal 三连失败无直接归档、F5 未真机注入、
  toggle 三态语义变化记档、QA 脚本 finally 不清探针）。无 🔴。
- 工作树注记：`.gitignore` 本地改动（`.mimosa/`）与 `buglist.md`（未跟踪）系本任务之外残留
  （README 载明 buglist 归 roadmap 完成后处理），不影响本提交验收。

## 八、PASS 条件核对

| 条件 | 判定 |
|---|---|
| 四门过（归档全文复核 + 必跑两项亲跑） | ✅ |
| 红→绿真实（N1 行为红证 + N2 UnknownId + 删除顺序证据） | ✅ |
| 真机两例复现（untitled 副本投影断言 + pie.play 对照）+ Ask 抽查 | ✅（四用例全过） |
| review 无新 🔴 | ✅（🟡×2 ⚪×5 记档移交） |
| 11 偏差有裁定 | ✅ |

VERDICT: PASS
