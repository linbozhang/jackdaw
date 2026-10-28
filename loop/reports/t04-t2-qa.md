# T04-T2「crash journal 与自动备份」QA 验收 — 提交 `75bfc76e`（分支 `loop/t04-save-recovery`，12 文件 +1110/−4，HEAD/diff 亲核一致）

口径：`loop/plans/t04-save-backup-recovery.md` §二 T2 验收 5 项 + 程序报告 `loop/reports/t04-t2-report.md`（§偏差 9 条；任务书所指 #3 测试污染/#4 exit code 即报告 #6/#7）。QA 只验不修。工作区仅历轮遗留。

## VERDICT: PASS — 方案 T2 验收 5 项全绿（headless×4 由 9+5 条 guards/document 测试承载并随四门亲跑通过、kill 链独立复跑、性能闸实测同量级达标）；污染核查干净；无新 🔴。门禁归档日志存在「假 exit code + 陈旧留档」纪律问题（QA 亲跑证实当前树四门全绿），记 🟡 工具/流程项不阻塞。

## 1. 门禁（升级审查：日志全文复核 + 四门亲跑，`gate-*-t04t2qa.log`）

**归档日志复核发现**：`gate-clippy-t04t2.log` 为单次完整运行且**含 3 个真 error**（`session_journal.rs` 测试的 map_flatten + println×2——性能闸仪表的遗迹）+ `could not compile jackdaw (test "guards")`，末行却是 `CLIPPY_EXIT=0`——**exit code 不忠实的直接实证**（比程序自曝的 xtask fast 面更广：归档 clippy 日志本身失真/陈旧——3 处 error 在当前树已被修复，但修复后未重存门禁日志，程序报告门禁表「clippy exit 0 无 error」与归档证据矛盾）。

| 门 | 归档日志 | **QA 亲跑**（独立行 exit code） |
|---|---|---|
| fmt | 1 行 `FMT_EXIT=0`，无 Diff | **EXIT:0**（`gate-fmt-t04t2qa.log`） |
| clippy | **含 3 error + 编译失败段 + EXIT=0（失真）** | **EXIT:0，bad=0**（当前树干净；3 处 error 已修） |
| fast | Summary **2870 passed, 2 skipped** + EXIT=0 | **EXIT:0，2870 passed, 2 skipped**（34.642s）——与归档一致 |
| integration | Summary **5096 passed, 2 skipped** + EXIT=0 | **EXIT:0，5096 passed, 2 skipped**（319.742s）——与归档一致 |

增量自洽：fast +1（journal CONFIG_DIR 测试并入 lib 面）……实为 2870 = 2869+1、5096 = 5086+9(session_journal guards)+1；数字全部吻合。**处置**：四门以 QA 亲跑为准全绿；归档 clippy 日志失真记 🟡 门禁纪律项（修复后未重跑重存），建议后续把「重跑并覆盖留档」写进门禁流程。

## 2. kill 链独立复跑（`t04-kill-recover-steps.ps1` + QA 断言脚本，隔离 config `%TEMP%\t04-kill-cfg-qa`、端口 15814，证据 `loop/reports/t04t2-kill/` + QA 独立输出）

- **dirty**：`entity.add.cube` → `status.dirty=true`（pid 23236）→ journal.json 落地轮询命中（**fresh 8.6s、135145 bytes**，debounce 2s 后写入）→ DIRTY VERDICT: PASS；
- **check**：journal parse = 1 tab `scene:scene entities=13`；
- **kill**：`taskkill /F /PID 23236` → journal **残留 149813 bytes** → KILL VERDICT: PASS；
- **relaunch**：同 config 重启 → 死会话 `23236-1792918434` 与新会话 `33752-1792918472` **并存**；死 journal 完整可 parse（tabs=1、entities=13、saved_at 空=置脏未保存，正确）；**新会话目录无 journal.json（干净 tab 不写，正确）**；live pid 与会话目录名 pid 一致 → RELAUNCH VERDICT: PASS；
- 与程序链（5988/20996、135142 bytes）行为同型、数字独立成立。
- **复现程序工具现象两处**：①relaunch 步的 `jackdaw/status` 长轮询在 my-game busy 期挂起（程序偏差同款），按程序先例停任务改手动断言驱动完成（`t04t2qa-relaunch-assert.ps1`）；②QA 首次跑 dirty 时的参数转义小坑（CMD 不展开 `$env:`），换 `%TEMP%` 即解。**建议**：steps 脚本的 status 轮询加超时短路（程序已注记 phase 版待修，一并处理）。
- wrap 完成，无残留进程。

## 3. 性能闸复核（QA 亲跑 `the_journal_write_costs_no_more_than_five_milliseconds --nocapture`，1 passed）

| 场景 | emit-only | 主线程成本（QA 实测） | 程序数字 | 5ms 闸 |
|---|---|---|---|---|
| 400 实体生成 | 1.5068ms | **997.5µs** | 962µs | ✅ |
| terrain fixture | 1.102ms | **1.4538ms** | 1.81ms | ✅ |

同量级（±20% 抖动内）、均远低于闸门；断言 `cost < 5ms` 真实生效（测试通过）。

**IoTaskPool 竞态窗口源码核实（偏差#1）**：写路径分离成立（journal 写 `state/sessions`，权威文件写 assets——互不相碰）✅；保存边界同步重写（`on_tab_saved`→`write_snapshot`）在两个基线点位同点位调用 ✅。**QA 补充分析（程序竞态论证的盲点，⚪）**：`write_atomic` 的 tmp 名含 `pid` 而非唯一串——**同进程内** debounce 路径的 IoTaskPool persist 与保存边界的同步 persist 并发时共用同一 tmp 路径，理论上可交错（最坏=journal.json 短暂损坏，比程序所述「短暂含已保存内容」略糟）；但损坏前上一完整版已轮转入 `journal.json.bak`，且读取侧损坏安全跳过——**自愈、有兜底、不碰权威文件**。窗口极窄（2s debounce 与保存同帧落地）。建议后续 tmp 名加计数器/纳秒后缀消除。

## 4. 代码 review

### a. 测试污染事故核查 — 干净
- **`~/.jackdaw/sessions` 不存在**（整目录已清除；`~/.jackdaw` 仅剩 extension-quarantine）——程序「全部清除」声明属实；
- **隔离时序修复+防回归断言逐行核实**：rotate 测试改为「先建 app（隔离载体）再取路径」（:206 注释明示意图），断言 `kept.iter().all(starts_with(&sessions))`（:228「every session lives under the isolated state dir」）；CONFIG_DIR 覆盖测试断言 journal 路径 `starts_with(overridden)`（:278）；
- **同型风险全仓扫描**：`sessions_root/begin_session` 全部调用点（产品 2 + 测试 5）逐一核对——测试 5 处全部在 `editor()`（先建 app 隔离生效）之后调用，无「隔离生效前取真实路径」的同型残留。

### b. OnExit 双保险与活实例保护
- 双保险：`OnExit(Editor)`→`cleanup_editor`→`end_session`（lib.rs:2864）+ `Last` schedule 的 `end_session_on_app_exit`（AppExit **计数快照**比较，覆盖 deferred-command 写入帧，规避排序依赖——偏差#4 成立）；
- **活实例保护**：`list_sessions` 排序键（mtime DESC，目录名 DESC tie-break）+「正在写 journal 的活实例每 ≥2s rename 推新其目录 mtime」→ **并行活跃（置脏中）实例恒排保留 5 名额内，不会被误删** ✅。**边界（⚪）**：「打开工程但从未置脏」的活实例目录 mtime 停在创建时刻，若并行实例 rotate 时存在 ≥5 个更新的死会话，其**空目录**可能被扫——后果仅限该实例此后 journal 写入失败（目录缺失→write_atomic Err→warn，无崩溃），不损任何他人数据。危害极低，如实记录。

### c. 损坏 journal 安全读取 / Y28
`read_session_journal`：read 失败 `ok()?`、parse 失败 `warn + None + 文件保留`（「damaged journal is evidence, not garbage」）；**全 parse 路径无 unwrap/expect/panic 面**（Y28 红线）✅；headless 用例（坏 JSON→None+保留）在 9 条 guards 内随亲跑通过。

### d. .bak 轮转（document.rs）
- 目标存在 → rename path→bak → rename temp→path，**第二步失败回滚 bak→path** + 清 temp ✅；单份 bak（rename 覆盖），单测断言 v1/v2/v3 滚动 + 无 `.bak.bak` ✅；
- **tmp 不产生 .bak**：bak 分支仅在 staged 写成功且 `path.exists()` 时触及目标，tmp 从不作为 write_atomic 的目标 ✅；
- journal.json 自身获得 .bak（compact JSON 的可读性兜底，偏差#3 合理）；与轮转清目录交互无害（会话目录 `remove_dir_all` 连 bak 整体消亡，bak 生命周期随会话）✅；
- 两步窗口（#5）：path→bak 后死 → 完整旧版在 .bak、目标缺失——描述准确，优于半截。

### e. convert_to_binary 吸收（jackdaw_bsn 私有 write_atomic）
- 与 api_internal 版**行为等价**：同目录 tmp、同 `.{name}.tmp-{pid}` 模式、create→write_all→**sync_all**→rename（sync 位置一致）；**无 .bak**——convert 调用面上 target 几乎恒为新孪生文件（`TwinExists` 挡重复 + 同 form 早退），无需 bak，等价性成立 ✅；
- 依赖方向注释（crate 不能反向依赖 api_internal，模式重复而非链接）✅；tmp 模式与 T1 sweep 的清扫模式一致（可被启动清扫覆盖）✅。T1 QA 的 🟡 回流建议已兑现。

### f. inactive tab AsHeld 拼写（偏差#2）影响评估
- active tab 与保存**逐字节同源**（验收 a 断言 `document == emit_bsn_scene_for_file` 手动 emit，亲跑通过）；inactive scene tab 为 `emit_scene(capture AST)`（AsHeld）——**AST 是权威、emit 是纯函数**，两种 spelling 产出的文本 parse 回同一 AST 等价；
- 恢复链（T3）经标准打开链：BSN 读取接受任意拼写；恢复后的保存走保存管线（relativize 归一化重拼写）——**不产生 diff 噪声、不丢引用**（路径信息在 AST 中完备，仅表示法不同）。prefab inactive 走 `relativize_for_file + asset_file_text`（与保存同管线）✅。偏差成立且影响可控。

### 其它核实
- `SceneTab::saved_at`（RFC3339，保存边界写入）+ `on_tab_saved` 在 save_scene_inner 两个基线点位同点位调用（「与基线永不失配」）✅；既有 write_atomic 测试更新为「temp 无残留 + .bak=旧内容逐字节」——语义随设计演进，非放松 ✅；save_all/quit 链未动（T1 已核）✅；`write_unsaved_model_settings` 无涉 ✅。

## 5. buglist — 未误动

打钩 7 条与历轮完全一致（R1/R2/Y1/Y2/Y4/Y9/W9），本轮无新增/无撤销 ✅。

## 6. 偏差 9 条逐条裁定

| # | 偏差 | QA 裁定 |
|---|---|---|
| 1 | 写盘路径 IoTaskPool 化（首版同步超标→改回） | **合理**（13.29ms 超标实测驱动、方案预留调整空间；竞态写路径分离成立；QA 补充 tmp 同路径盲点见 §3，⚪ 有兜底） |
| 2 | inactive tab AsHeld 拼写 | 成立（AST 等价、恢复/保存链归一化，见 §4f） |
| 3 | journal JSON compact | 合理（.bak 承担可读性） |
| 4 | AppExit 计数快照检测 | 合理（规避排序依赖，源码核实） |
| 5 | .bak 两步 rename 窗口 | 成立（带回滚已核实；窗口内完整版在 .bak） |
| 6 | **测试污染事故** | **已妥善处置**（真实目录已清、时序修复+防回归断言逐行核实、同型风险清零） |
| 7 | **xtask fast exit code 不忠实** | **属实且 QA 实证更广**（归档 clippy 日志同样失真）；四门以 QA 亲跑为准全绿；留档纪律记 🟡 |
| 8 | entity_count 口径（live/快照 roots） | 合理（与恢复预览一致） |
| 9 | 无涉链路 | 属实 |

## 7. 问题统计

| 级别 | 条目 |
|---|---|
| 🔴 严重 | 0 |
| 🟡 中等 | 1（门禁留档纪律：clippy 修复后未重跑重存、归档日志含 error 段却标 EXIT=0——exit code 不可信的流程面；建议门禁脚本改为「重跑并覆盖 + 日志含 error 即 fail」） |
| ⚪ 轻微 | write_atomic tmp 名同进程并发冲突窗口（bak+安全读取兜底，建议 tmp 加唯一后缀）；rotate 可扫「从未置脏活实例」的空目录（后果轻）；kill 链 status 轮询 busy 期挂起（steps 版同受影响，建议加超时短路）；list_sessions tie-break 用名字符串序（非数值序，影响可忽略） |

**正向**：测试污染事故的处置是范本（清除→时序修复→防回归断言→同型扫描面清零）；性能超标→IoTaskPool 化的决策链有实测数字支撑；保存边界同步 vs debounce 异步的取舍论证清晰；kill 链行为与程序完全同型复现。

## 8. 方案 T2 验收 5 项对照

| 验收项 | 状态 |
|---|---|
| 1. headless 置脏→debounce→journal 落地、emit 同源、干净 tab 无条目 | ✅（guards 9 条随亲跑通过；同源逐字节断言在位） |
| 2. headless 崩溃残留/正常退出删除/轮转>5 清最旧/损坏 journal 安全读 | ✅ |
| 3. JACKDAW_CONFIG_DIR 覆盖隔离 | ✅（+ 防回归断言） |
| 4. 保存后条目移除 + `<scene>.bsn.bak`=保存前字节 | ✅ |
| 5. 真机 kill 链（置脏→kill→重启→会话残留并存）+ 性能闸 ≤5ms | ✅（独立复跑 PASS + 997µs/1.45ms 实测） |

**VERDICT: PASS**
