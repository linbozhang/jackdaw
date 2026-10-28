# N10 修复报告：「dirty+Save play_current 冻结编辑器主线程」根因分析与加固修复

> 程序角色产出，2026-10-26。分支 `loop/n10-play-freeze`（自 main `d4d49dca` 拉出）。
> 任务：buglist N10（dirty 场景 + Save 态 `pie.play_current` 真机冻结，高优）。
> 结论先行：**触发面经 13 轮真机穷举（QA 4 轮 + 本任务 9 轮，含高负载/真门禁负载/connecting-stop/stop 锤变奏）不可稳定复现**，按任务书降级路径执行：静态根因分析 + 对自旋点全面加固修复 + 守卫测试 + dirty+Save 一步回归（QA 硬性后续）3/3 过。

## 一、触发面定位（第一目标）的结论

### 1.1 复现穷举记录（全部不冻）

| # | 轮 | 条件（对齐程序 freeze 归档逐项） | 结果 |
|---|---|---|---|
| 1-4 | QA v1-v4（t06-t3-qa.md §1.1） | cfg 干净/污染 × idle/prebuild in flight × 朴素/SpinningCube 场景 × recovery 对话框有无 | 全不冻 |
| 5-6 | 本任务 Case A ×2（`n10-fix-probeA-run{1,2}.log`） | 程序原条件复刻：t06t3-live cfg（残留会话→recovery 对话框）+ ready 即发（prebuild in flight）+ SpinningCube fixture + add.cube 脏 + 1s 后 play_current；run2 加 6 核 CPU 满载 | 不冻，pie=running |
| 7 | Case B（`n10-fix-probeB-run1.log`） | freeze_baseline 序列：clean play → stop → dirty play_current（连续两轮 play） | 不冻 |
| 8-10 | Case C ×3（300/500/900ms，`n10-fix-probeC-*`） | **放宽 pie.stop avail + 放宽 connecting 计 Playing**（复刻 T3 实验），等 idle 后 play → connecting 窗口内 stop（日志实证走了 `killing connecting child` 完整链 + OnEnter(Stopped) 全链） | 不冻（T3 注释称 100% 的路径在当前树上不再冻结） |
| 11 | Case D（`n10-fix-probeD-run1.log`） | stop 高频重试锤（100ms 间隔穿过 connecting 窗口）+ 连续 3 轮 play/stop/dirty-play 快速循环（原版 avail 语义） | 不冻，3 循环全 stopped |
| 12 | Case A run3（`n10-fix-probeA-run3-gateload.log`） | **真门禁负载**（后台 `cargo check --workspace --all-targets`，5 个 cargo/rustc 进程、CPU 57%）+ prebuild in flight + dirty play | 不冻 |
| 13 | Case D run2（修复后复测） | 同 11 | 不冻 |

程序 4 组 freeze 归档（`loop/t06t3_probe_freeze*.log`）与 QA/本任务复现的唯一系统性环境差 = **T3 工作期的机器状态**（门禁全量并发、连续冻结累积的 my-game target 状态、当时实验构建的代码形态），无法在当前环境重建。冻结形态（CPU 满载 + 日志停摆 + BRP 死 + 偶发 + 观察窗仅 3s 即判死）与「主线程陷入一个无界消费循环消化事件积压」完全吻合——见 §二。

### 1.2 一个重要的解矛盾线索

freeze 探针判定窗口只有 3 秒（`CPU/3s`）即 kill 编辑器；QA/本任务判定窗口 9-12 秒。若自旋是「积压消化型」（数秒~数十秒后自行恢复），**程序 3 秒判死、QA 9 秒判活，两边的观察都成立**——「程序 100% 复现 vs QA 零复现」的矛盾由此可解，且与 §二的自旋机制互证（本任务修复后此形态在结构上不再可能出现，见 §三）。

## 二、根因（静态分析，含降级说明）

**主嫌疑（修复对象）：`drain_received` 的无界 try_recv 循环跑在编辑器主线程**（`crates/jackdaw_pie_protocol/src/transport_ipc.rs`，T1 之前的既有基建，main 基线同在）。

机制链：
1. `drain_game_events`（Update 每帧，主线程）→ `transport.drain_received()` → `loop { try_recv() }` **直到管道空才返回**；
2. 游戏每帧流式发送 StateEvent（多实体场景每帧 N 条）。正常时编辑器消费速率 >> 生产速率，每帧 drain 追平即返回；
3. **触发面（窄）**：主线程任何一次长帧（dirty+Save 的保存链实测同步占主线程 ~1.5 秒——`Scene saved` 到 `launched` 的间隙；或 Live 投影重建/stop 的 `respawn_scene_from_ast` 整场景重放）期间游戏持续生产，积压滚雪球；积压超过阈值后**循环内消费速率 ≤ 生产速率，`try_recv` 永远见不到 Empty**——主线程被钉死在这个循环里：CPU 满载（持续反序列化热循环）、BRP 无响应、日志停摆，与全部 freeze 归档形态一致；
4. 同一机制覆盖三条已知触发路径：dirty+Save play（保存链是积压引信）、clean play+切 Live+stop（`revert_preview` 整场景重放是引信，freeze2 形态）、connecting 窗口 stop（T3 实验形态：kill+OnEnter(Stopped) 重链是引信）；
5. QA/本任务不复现的原因：测试场景 2-3 实体（每帧个位数事件），消费余量巨大，任何引信都到不了雪崩阈值；程序复现时的大场景/满载/实验构建组合恰好在窄窗口内。freeze 日志停在 `OPERATOR: pie.play_current` 后（连保存链第一条日志都没有）也与「下一帧起每帧系统里自旋、queued command 永不被 apply」的断点位置吻合。

**次嫌疑（记档不修）**：ipc-channel 0.22 Windows 实现的 `try_recv` 在读到**部分消息**（大帧分片/OOB big-data）时转 `GetOverlappedResultEx(INFINITE)` 阻塞等待（`receive_message` 内 `blocking_mode = Blocking`），主线程单次 drain 可能被一条残缺大帧卡住直到对端补齐或断开。该语义在 ipc-channel 内部，编辑器侧无法加超时（`try_recv_timeout` 的超时分支会 `cancel_io` 破坏消息完整性，不可用）；实际风险低（对端退出时管道断开即解除），记档于 buglist 备注。

**同族记档（不修）**：`handle_stop` 杀 connecting child 后 accept task 以 detach 语义遗留（bevy git 版 Task drop=detach，同步 `IpcOneShotServer::accept` 不可取消），每次泄漏一个 task-pool 线程 + named pipe 句柄；编辑器会话内多次 play/stop 会累积但无功能性影响，待 ipc 侧出现可中断 accept API 再收口。

## 三、修法

`crates/jackdaw_pie_protocol/src/transport_ipc.rs`：`drain_received` 加**帧数 + 墙钟双预算**（`DRAIN_FRAME_BUDGET = 256` 帧 / `DRAIN_TIME_BUDGET = 4ms`，每 32 帧查一次表）。单帧 drain 工作量有界：积压时以每帧 ≤256 帧/4ms 的速度跨帧消化——主线程永不失控（单帧最多多花 4ms），积压消化能力 60fps × 256 = 15360 帧/秒仍远超任何游戏生产率；可靠有序通道语义不变（延迟到达、不丢不乱）。`PieTransport::drain_received` 的 trait 文档同步改为「bounded batch」契约。正常负载（每帧个位数事件）零感知。

选 256/4ms 的依据：正常 play 每帧事件个位数（预算余量 2 个数量级）；最坏积压单帧 4ms ≤ 一帧 16ms 的 1/4，UI/BRP 保持响应。

## 四、验证数字

| 项 | 结果 | 日志 |
|---|---|---|
| 守卫测试（红→绿不可行，按任务书改单元级断言：洪泛 1024 帧下单次 drain ≤256、多次 drain 收齐 1024 不丢） | **PASS**（`one_drain_is_bounded_under_backlog_and_nothing_is_lost`；transport_ipc 3 passed/1 ignored[Windows 既有]） | `cargo test --workspace transport_ipc` |
| dirty+Save 一步真机回归（QA 硬性后续：dirty 直接 play_current 不预存，全流程 dirty→play→running→stop→stopped→BRP 活→盘内容增长） | **3/3 PASS** | `loop/n10-fix-verify-run1.log` |
| 三边界：clean+Save（B1）/ dirty+Copy（B2）/ untitled+Save（B3） | B1 ✓、B3 ✓；B2 隔离复测 **2/2 ✓**（全链 BRP 延迟 5-153ms；首轮 QA 脚本 B2 报 stopped=False 系脚本时序：stop 恰逢 connecting 窗口被 avail 拒绝后仅等 15s，编辑器日志实证 stop→exit→cleanup 全过，见 §五.2） | `loop/n10-fix-boundaries-run1.log`、`loop/n10-fix-b2check-run1.log` |
| stop 锤 + 3 轮 play/stop/dirty-play 快速循环（修复后） | 3 循环全过、BRP 活、不冻 | `loop/n10-fix-probeD-run2-fixed.log` |
| 门禁 quick 四门 | **全绿**：fmt 0 输出（PASS）；clippy --workspace --all-targets --features dylib -D warnings 0（无 error）；xtask fast **2906/2906 passed**（1 leaky 存量、2 skipped；较 T3 的 2905 +1=新守卫测试）；xtask integration **5178/5178 passed**（1 leaky 存量、2 skipped） | `loop/reports/gate-{fmt,clippy,xtask-fast,xtask-integration}-n10fix.log` |

冻结复现路径本身的「修后 ≥3 次不冻」不可执行（修前已不可复现，13 轮穷举在案）；等价物 = §四守卫测试（结构上封死无界自旋）+ 上述真机回归（触发面全域健康）。

## 五、偏差与记档

1. **降级执行**：任务书预设「穷举仍不复现则给出不可稳定复现+最可能根因静态分析并降级为加固修复」——本任务实际走了这条路径（§一 13 轮在案）。修复是**结构加固**（自旋点有界化），不是「对已复现冻结的定点修复」，验收口径相应为守卫测试+回归而非红绿。
2. **B2 首轮 stopped=False**：QA 沉淀脚本 `t06t3-qa-n10.ps1` 的 B2 段 stop 只调一次且恰逢 connecting 窗口（avail 拒绝，既定交互），此后仅轮询 15 秒；编辑器日志实证产品链全过（stop→游戏 2s 优雅退出→temp copy 清理）。隔离复测（`n10-fix-b2check.ps1`，每次 stop 计时重试）2/2 全过、无一次 BRP 超时。**非修复回归**；脚本时序缺陷（stop 应带重试，同 QA 自己的矩阵配方）记档给后续复用者。
3. **插桩已全部回退**：定位期的 N10PROBE 日志（pie/pie_current/pie_projection/scenes/swap 四文件 19 行）已 `git checkout --` 干净回退，最终 diff 只含修复本体。
4. **次嫌疑与 accept 泄漏记档**见 §二，buglist N10 条目备注同步。

## 六、提交

- 分支：`loop/n10-play-freeze`（父 `d4d49dca` = main）
- 文件：`crates/jackdaw_pie_protocol/src/transport.rs`（trait 契约文档）、`crates/jackdaw_pie_protocol/src/transport_ipc.rs`（预算常量+drain 改造+守卫测试）
- 提交信息：`Bound the PIE drain loop so a streaming backlog cannot pin the main thread (N10)`
- 哈希：`6cfb1358`（父 `d4d49dca` = main；未推远端；2 文件 +74/-2）
- loop/、buglist.md 不入库。
