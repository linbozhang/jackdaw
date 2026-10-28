# N10 修复 QA 验收报告：「PIE drain 无界自旋加固」（只验不修）

> QA 角色产出，2026-10-24。分支 `loop/n10-play-freeze`，提交 `6cfb1358`（父 `d4d49dca` = main），
> 2 文件 +74/−2（`jackdaw_pie_protocol` 的 transport/transport_ipc）。
> 程序报告：`loop/reports/n10-fix-report.md`。验收方法：根因链逐环代码证据核验 + 修法 review +
> 守卫测试亲跑 + 真机回归独立复跑 + 门禁归档复核。

## 一、降级口径裁定（核心）：**成立**

### 1.1 根因论证链逐环代码证据（四环全实）

| 环 | 论证 | QA 证据 |
|---|---|---|
| 1 | drain 跑编辑器主线程 | `drain_game_events(world)` 拿 `&mut World` + `session.children.iter_mut()`（`src/pie.rs:2550-2560`）——Bevy exclusive 系统必在主线程 ✓ |
| 2 | 修复前无界循环直到空 | `git show d4d49dca:.../transport_ipc.rs` 直读：`loop { try_recv() }` 直到 `Empty` 才 break——**main 基线原样**（T1 之前既有基建，与「存量缺陷」声明一致）✓ |
| 3 | 长帧引信（保存链/投影重建同步占主线程→积压滚雪球→消费追不上生产→永不见 Empty） | 机制类型成立（同步长帧 × 对端持续生产 × 无界消费）；freeze 归档形态（play_current 后日志停摆+CPU 满载+BRP 死）与「下一帧起自旋、queued command 永不被 apply、连保存链第一条日志都不出」逐点吻合 ✓ |
| 4 | QA 四轮零复现=小场景低事件率 | QA T3 探针场景 2-3 实体（每帧个位数事件、消费余量巨大）事实自洽 ✓ |

**「3s 判死 vs 9s 判活」解矛盾**：程序探针 3 秒观察窗即 kill、QA 9-12 秒窗——若自旋是积压消化型
（自愈期落在两窗之间），两边观察都真。**逻辑自洽，但不可证伪**（无法重建 T3 期机器状态重验）。
QA 诚实定性：这是「最可能根因」而非「确证」——**降级验收的支柱不依赖该假设成立**，而依赖下条。

### 1.2 等价验收三支柱（不可复现缺陷的替代验收是否充分）

1. **静态缺陷真实存在**：无界 `loop { try_recv() }` 跑主线程本身即为真实缺陷（无论它是否 N10
   的唯一根因，该结构在任何积压场景下都可能钉死主线程）——main 基线代码直读证实；
2. **守卫测试结构封死**：回归到无界实现（删预算）会让守卫测试的 `first.len() ≤ 256` 断言失败
   （1024 帧积压下一次全拿）——反向回归被测试钉死；
3. **触发面全域回归健康**：程序 3/3 + **QA 独立复跑全过**（§四），含 QA 硬性后续要求的
   dirty+Save 一步真机回归。

**裁定：不可复现缺陷以「静态根因+守卫测试+触发面全域回归」等价验收成立。**

## 二、修法 review：无新风险

- **双预算实现**：帧数闸 `while out.len() < DRAIN_FRAME_BUDGET(256)` + 墙钟闸每 32 帧查
  `elapsed ≥ 4ms`（降低 Instant::now 调用频率）；单帧 drain 最坏 ≈4ms+32 帧余量——主线程单帧
  有界；帧数闸同时约束调用方反序列化量（drain_game_events 每帧至多处理 256 帧的 from_bytes），
  组合仍有界；
- **stop 延迟语义（任务书重点，T2 优雅停止邻居）——零风险**：`ControlEvent::Stop` 走 **send
  方向**（编辑器→游戏，`transport.send` 直发），**完全不经过 drain_received**；预算只作用于
  游戏→编辑器方向（投影 StateEvent 流，跨帧消化延迟几帧无损）；游戏退出检测由子进程 `try_wait`
  轮询驱动（advance_child），不依赖 drain。T2 的 2s 优雅窗口/恰一次 kill 语义不受影响；
- **顺序与不丢**：FIFO 管道 + 预算 break 后剩余滞留下次调用续收——可靠有序不丢；trait 契约文档
  同步改为 bounded batch（`transport.rs`），调用方 `drain_game_events` 是 InstanceBuffer 累积
  语义，分批天然兼容、无「一次拿全」假设（代码核实）；
- **队头延迟上界**：积压 N 帧时队尾消息最坏延迟 ⌈N/256⌉ 帧（@60fps 每帧 256≈64ms/千帧）——
  游戏→编辑器方向无延迟敏感消息，可接受；
- **改动面**：仅 2 文件（trait 文档 + ipc 实现/测试），无越界；插桩回退干净（工作区仅剩常规
  `.gitignore`/buglist.md；提交 diff 只含修复本体）。

## 三、守卫测试质量：有效

`one_drain_is_bounded_under_backlog_and_nothing_is_lost`：洪泛 1024 帧（4×预算）+ 200ms 落地 →
**首 drain ≤256 且非空（下界+上界）→ 逐批 ≤256 → total == 1024（不丢）**。回归到无界实现则
`first.len() = 1024 > 256` 必失败——封死成立。**QA 亲跑**：`cargo test -p jackdaw_pie_protocol`
**3 passed / 0 failed / 1 ignored**（ignored 为 Windows 既有语义说明用例）。
⚪ 局限记录：洪泛为 16B 小帧，时间闸（4ms）路径未被直接测（时间闸是防御纵深，帧数闸为主闸）；
200ms 落地假设对本地管道 16KB 绰绰有余。

## 四、真机回归独立复跑（QA 亲自执行，修复版 6cfb1358）

脚本 `loop/qa/n10-qa-regression.ps1`（QA 沉淀，stop 带 T2 稳定重试配方），SpinningCube 场景：

| 用例 | 实测 | 判定 |
|---|---|---|
| dirty+Save 一步回归 ×2 | 两轮全 OK：dirty 前提成立 → play_current → running → stop → stopped → BRP 全程活 → **盘内容真实增长（351→14566→28769，每轮 cube 落盘累积）** | ✅✅ |
| 边界抽一：dirty+Copy | running→stopped 干净落地，**盘逐字节不动** | ✅ |
| stop 锤 3 循环（clean play→stop→dirty play→stop 快速循环） | 3 循环全过（cleanStop/dirtyStop 全 True），BRP 全程活，无冻结 | ✅ |

复跑后清理：fixture/`.bak`/temp 副本/进程全清，无残留。**QA 硬性后续「修复后补 dirty+Save 一步
真机回归」已在 QA 侧独立执行确认。**

## 五、门禁复核

| 门 | 归档 | 复核 |
|---|---|---|
| fmt | `gate-fmt-n10fix.log` 0 字节 | ✅ |
| clippy --all-targets -D warnings | `gate-clippy-n10fix.log` | 65 行、0 error、仅既有工具链噪音 ✅ |
| xtask fast | `gate-xtask-fast-n10fix.log` | **2906/2906 passed**（1 leaky 存量、2 skipped；+1=新守卫）✅ |
| xtask integration | `gate-xtask-integration-n10fix.log` | **5178/5178 passed** ✅ |
| 守卫测试本体 | — | QA 亲跑 3/0/1 ignored ✅ |

## 六、buglist N10 备注与偏差核对

- **备注核对**：条目**未勾选** ✓；13 轮穷举/降级路径/主嫌疑/修法/守卫+回归数字/两条次嫌疑
  （ipc `try_recv` 部分消息 INFINITE 语义不可加超时、accept task detach 泄漏待可中断 API）全在档 ✓；
  次嫌疑两条的论证 QA 认可（crate 内部语义无法外层加超时且 cancel_io 破坏消息完整性；bevy Task
  detach+同步 accept 不可取消——均为记档不修的合理裁量）。
- ⚪ 两处备注瑕疵：**同段备注重复粘贴两遍**；修复指引写「<loop/n10-play-freeze 提交」而非哈希
  `6cfb1358`（分支唯一提交可追溯，但建议直接写哈希）。
- **B2 首轮 stopped=False 偏差**：定性「QA 脚本时序（stop 无重试恰逢 connecting 窗口 avail 拒绝
  +仅轮询 15s）非产品问题」——**证据充分接受**：首轮 `alive=True` 全程（编辑器未冻）+ 编辑器日志
  实证 stop→游戏 2s 优雅退出→temp 清理全链 + 隔离复测（带重试配方）2/2 全过（5ms/13ms 快速
  落地）。QA 回归脚本本轮已修正 stop 重试配方。

## 七、QA 汇总

新发现 ⚪ ×4（buglist 备注重复、指引未写哈希、解矛盾假设不可证伪——已诚实定性不影响支柱、
守卫未直测时间闸大帧路径）。无 🔴 无 🟡。
插桩回退与残留清理核实：工作区仅常规项（`.gitignore` 本地改动+buglist.md 不入库），无 $null 类
事故产物。

## 八、PASS 条件核对

| 条件 | 判定 |
|---|---|
| 根因论证自洽（四环代码证据+解矛盾假设自洽标注不可证伪） | ✅ |
| 修法无新风险（stop 延迟语义零风险——方向性隔离证实；顺序/不丢/调用方兼容全核） | ✅ |
| 守卫测试有效（封死反向回归+亲跑过） | ✅ |
| 回归复现（dirty+Save ×2+Copy 边界+stop 锤 3 循环独立全过） | ✅ |
| 门禁干净（四门归档+守卫亲跑） | ✅ |

## 九、buglist 可勾建议

**建议勾选**（`[x]`），同时三件小事一并做：清理重复备注段、指引改写哈希 `6cfb1358`、
**保留两条次嫌疑备注**（记档不修项不随主条目勾选消失）。

VERDICT: PASS
