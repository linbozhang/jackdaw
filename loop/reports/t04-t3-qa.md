# T04-T3「恢复入口+N9 走查+工具+收尾」QA 终验（兼 T04 整体闭环判定）— 提交 `7caf0bad`（分支 `loop/t04-save-recovery`，11 文件 +1381/−33，HEAD/diff 亲核一致）

口径：方案 §二 T3 验收原文两句话 + 程序报告 `loop/reports/t04-t3-report.md`（偏差 9 条）。QA 只验不修。工作区仅历轮遗留。

## VERDICT: PASS — 六门过（doctests 按基线非回归）；终验链①独立复现含 SHA 铁证；多 tab/损坏 journal 复现；N9 抽验 7 格全过（三必测含）；review 无新 🔴；事故核实干净。**T04 建议：可勾选**（T1/T2 已 PASS 合入，T3 本轮 PASS——整体闭环）。

## 0. 提交落错分支事故复核（QA 独立）

`git log --oneline main..loop/t04-save-recovery` **恰 1 行**（7caf0bad）；分支 tip 父 = `75278e5b`；**`git log main -1` = 75278e5b（T04-T2 合入点）完好**；diff 无孤儿残留（工作区仅历轮遗留 .gitignore/buglist）。与主控复核与程序自述一致——**事故已完全纠正**。程序教训（提交前核对 branch）记入流程。

## 1. 全量六门（QA 亲跑，`gate-*-t04t3qa.log`，独立行 exit code + 日志全文复核）

| 门 | exit | 数字/复核 |
|---|---|---|
| fmt | **0** | clean |
| clippy（workspace+all-targets+dylib+`-D warnings`） | **0** | clean（bad=0） |
| cargo doc（--locked --workspace --document-private-items --no-deps） | **0** | clean |
| xtask fast | **0** | **2871 passed, 2 skipped**（33.5s；与程序一致） |
| xtask integration | **0** | **5104 passed, 2 skipped**（314.6s；与程序一致） |
| doctests（--locked --workspace --doc --features dylib） | 101 | 失败集合 = **{jackdaw_bind, jackdaw_feathers, jackdaw_node_graph}** ——与 T02/T03 历史基线**完全一致、零新增** |
| （单跑）`-p jackdaw_bind --doc`（无 features） | **0** | **1 passed**（4.58s）——单 crate 编译路径通过，佐证 workspace+dylib merged-doctest 为既有 cargo 行为 |

**与程序描述的差异（如实记录，⚪）**：程序报告「唯一 error=jackdaw_bind、比基线少两失败」在其归档日志（`gate-doctests-t04t3.log`）成立，但 **QA 亲跑复现回三 crate 失败（=基线）**——程序的「少两失败」不可复现（构建缓存态差异）。按「doctests 基线非回归」的 PASS 标准：**QA 结果满足**（零新增）；程序该句描述不作为证据采信。（另：QA 首次单跑 bind 误加 `--features dylib` 报「does not contain this feature」——命令面属 jackdaw 主 crate，程序口径为无 features 单跑，已按此复跑通过。）

## 2. T04 终验链①「异常退出可恢复（预览+选择，不覆盖）」独立复跑 — PASS

程序沉淀脚本 `loop/qa/t04-chain-step.ps1`（record/kill/verify/save 单步）+ QA 补充断言，隔离 config `%TEMP%\t04-final-cfg-qa`、端口 15815、全程 `JACKDAW_CONFIG_DIR` 隔离（真实用户目录零触碰）：

| 步 | QA 实测 |
|---|---|
| 置脏 | `entity.add.cube` → dirty=True → journal 落地（debounce 后 fresh<1s，**193817 bytes**） |
| record | pid 36796、journal entities **16**、scene.bsn SHA256 **2FD51D4A…86686** |
| kill | `taskkill /F /PID 36796` → journal 残留 ✓ |
| 重启 | `jackdaw/recovery`：**available=True, sessions=1**，摘要 entities **16（=journal）**、diff="**+452 lines vs the file on disk**"；ui_tree 实证 **Recovered Work 对话框在**（标题+行内容「scene -- scene.bsn · 16 entities · saved never · captured … · +452 lines」+ Preview/Discard/Restore/Discard All 四按钮坐标正常） |
| ui_click Restore | **盘上 SHA256 = 2FD51D4A…（与 kill 前逐字节相同——不覆盖铁证）**；**DIRTY=True**（恢复 tab 恒脏）；scene_tree **16 roots == journal 16** |
| 显式 scene.save | SHA 变为 **8F7FD600…**（只有显式保存写文件） |

链②（保存中断不损坏）：T1 故障注入 guards 常驻（随 integration 亲跑）+ 本链 kill 落在 journal 写后保存前旧文件字节不变（同链覆盖）✅。

**QA 环境注记（⚪，非产品缺陷）**：首次 relaunch 用 `start /MIN` 启动（bat 模板默认），对话框 UI 布局落在**负坐标**（-115,-88）导致 ui_click 合成点击落窗口外、Restore 无效（首跑 DIRTY=False 的根因）；去掉 /MIN 可见启动后对话框坐标正常（295,400）、点击生效。**沉淀给后续 QA：驱动 scrim+card 对话框前必须确保窗口非最小化**。另：`t04-chain-step.ps1` 的 relaunch 步 status 长轮询在 my-game busy 期仍会挂（T2 同款），QA 按程序先例停任务改手动断言——建议 relaunch 步也加超时短路（kill-recover.ps1 已修，chain-step 未同步）。

## 3. 多 tab 恢复 + 损坏 journal — 独立复跑 PASS

**多 tab**（named+untitled 各一脏，session `40572-1792935020`，journal 224161 bytes）：
- kill → 重启 → recovery tabs=**2**（`scene:named path=scene.bsn` + `scene:untitled-2 path=空`）；
- `recovery.restore{tab:0}`（named）：journal **2→1**（独立消费）、dirty=True、active scene=scene.bsn；
- 再 restore（untitled）：journal **1→0**、**会话目录随之删除**、recovery available=False、active scene=**空**（untitled 恢复为无路径脏 tab）✅。

**损坏 journal**（截半 224161→**112080 bytes**，session `41800-1792935146`）：
- 重启**不崩**（status 正常应答，pid 42192）；recovery：**damaged=True、available=False**、sessions 仍列出（tabs=0，供 dismiss——偏差#6 设计取舍，QA 认可）；**损坏文件原样保留（112080 bytes）** ✅。

## 4. N9 矩阵抽验（7 格独立复跑，三必测全含）— 全 PASS

QA 脚本 `t04t3qa-n9.ps1`（WM_CLOSE=PostMessage 0x0010 结构化、按钮=ui_click）：

| cell | 场景 | QA 结果 |
|---|---|---|
| 1 | named 脏 close→Save | **PASS**：file-changed=True + tab 关（两 tab 前置：add+scene.new+Ctrl+Tab 切回 named） |
| 2 | →Discard | **PASS**：file-unchanged=True + tab 关 |
| 4（必测①） | untitled 脏 close→Save | **PASS**：dirty=True（tab 未被丢=Save≠Discard）+ 文件不动；native Save As 挂起按程序先例 kill 收尾 |
| 6（必测②） | 退出→Save All（纯 named 脏） | **PASS**：editor-exited=True + file-saved=True |
| 6 反证 | dirty untitled 时 Save All | **PASS**：editor-alive=True + dirty=True（**拒绝退出语义实测成立**——偏差#4 裁定成立） |
| 8 | 退出→Cancel | **PASS**：alive=True + dirty 保留 |
| 11（必测③） | 脏 tab WM_CLOSE | **PASS**：quit 对话框弹（Save All 按钮在）+ alive（拦截） |

其余 4 格（3/5/7/9/10）：程序留档 = 报告矩阵表 + `t04-quit-cell.ps1`（cell 7/8 可复跑脚本；8 已由 QA 复验）；cell 3 的 named 复测结论与 QA c8（Cancel 保留 dirty）同语义。**注记**：程序 N9 独立日志留档不全（多数为表格自述+内联驱动），QA 已用 7 格实测覆盖关键面。
QA 前置教训（⚪）：`scene.close` 阻止关闭最后一个 tab（产品语义）——cell 1-3 驱动需两 tab + active=named。

## 5. 代码 review（七点）

1. **对话框单实例互斥+多会话顺序弹**：`recovery_dialog_system` 以 `RecoveryDialogRoot` 存在性互斥；queue `pop_front` 逐会话、current 会话消费完（journal 空/损坏）才下一；全清后移除 `PendingRecovery` ✅。
2. **恢复动作不写盘**：`restore_tab` 全程只读（journal+盘上文件），唯一写=journal 自身条目消费（`journal_without`→write_atomic journal.json）——**无任何权威文件写调用**（写盘面扫描实证：recovery_dialog.rs 仅 :490 journal.json 与 :498 会话目录删除）✅。
3. **恢复 tab saved 基线=盘上文件**：`disk_baseline`（盘上文件去 stamp 行后 document_hash）→ `saved_doc_hash=baseline`，journal 版本≠盘上 → **恒脏直至显式保存**（真机 DIRTY=True 实证）✅；untitled 无基线（成长型脏）✅。
4. **note_known_content**（N11）：恢复时以盘上当前内容注册 known → 自身保存不误弹 reload ✅（源码在位；external_watch 行为由既有 dirty_matrix 面覆盖）。
5. **Y28**：restore 全路径 map_err/warn，**零 unwrap/expect**（扫描实证）；坏条目按名拒绝且一切保留 ✅。
6. **BRP `jackdaw/recovery`**：挂法 `with_method_main` 与 history 同列一致；返回 available/sessions/damaged/tabs 摘要（含 diff 字段——真机实测 +452 lines）✅；`recovery.restore/dismiss` 经 scenes extension 注册的 operator（真机实测可用）✅。
7. **MCP 镜像**：第 22 个工具 `recovery`（brp_text 薄转发+准确描述，restore/dismiss 走 call_operator 的用法写明）✅。
8. **write_atomic tmp 唯一后缀退避**：attempt 0..=8（主名+`-1..-8`，9 槽），成功即 break、全失败返回 Err；`is_temp_file_name` 放宽接受 `数字-数字`（`tmp-<pid>[-n]`）——sweep 兼容 ✅；T1 占位测试更新为**占满全部 9 槽**（保语义：无法 stage 必须失败）✅；消除 QA 在 T2 报的「同进程并发共用 tmp 路径」窗口（T2 ⚪ 建议兑现）。

## 6. book 文档与用户清单

- `book/src/user-guide/scene-management.md`「Crash recovery」节在位，内容与实现一致（journal 路径/Recovered Work 对话框/Restore 语义/terrain sidecar 限制/五个会话目录保留/.bak 单槽/.corrupt 备份）✅。
- 用户 30 秒清单 4 项在程序报告文末 ✅（①杀进程→恢复→不覆盖 ②untitled Save→Save As ③.bak 上一版 ④corrupt 备份提示）。

## 7. 偏差 9 条逐条裁定

| # | 偏差 | QA 裁定 |
|---|---|---|
| 1 | 提交落错分支 | **已复核干净**（§0）；教训采纳 |
| 2 | PS 后台饿死→单步前台 | **沉淀脚本可复跑成立**（record/kill/verify/save 单步均复跑成功）；已知卡点：relaunch 步 status 轮询 busy 期挂（QA 两次遇到，建议同 kill-recover.ps1 的短路修法） |
| 3 | PS 变量类型事故 | 脚本侧，无产品影响 ✅ |
| 4 | cell 6 语义澄清 | **成立且 QA 双向实测**（纯 named=保存退出；dirty untitled=拒绝退出+alive） |
| 5 | cell 3 named 复测 | 执行瑕疵已披露；结论由 QA c8 同语义覆盖 ✅ |
| 6 | damaged 会话仍列出可 dismiss | 设计取舍合理（QA 实测 damaged=True/tabs=0/文件保留）✅ |
| 7 | Preview 前 40 行文本 | 方案允许形态 ✅（diff 视图 backlog 已记录） |
| 8 | 恢复 tab 无 undo 历史 | 设计边界（方案未要求）✅ |
| 9 | doctests bind 既有失败未修 | 合理；**但程序「唯一 bind/少两失败」描述 QA 不可复现**（QA=基线三 crate，零新增）——按基线非回归 PASS，描述差异记录 |

## 8. 问题统计

| 级别 | 条目 |
|---|---|
| 🔴 严重 | 0 |
| 🟡 中等 | 0 |
| ⚪ 轻微 | doctests「少两失败」描述不可复现（按基线判定无影响）；chain-step relaunch 步 status 轮询无短路；程序 N9 独立日志留档不全（多数内联驱动）；QA 工具沉淀两条（对话框驱动需非最小化窗口、scene.close 最后 tab 阻挡） |

**正向**：事故自曝+根因教训（提交前核对分支）是诚实范本；恢复链的设计三铁律（不写盘/盘上基线恒脏/note_known_content）实现与文档完全一致；tmp 唯一后缀兑现 T2 QA 建议；`scene.close` 最后 tab 保护在 QA 驱动失误时正确拦截（顺带验证）；单步脚本沉淀让 QA 全程独立复跑成为可能。

## 9. T04 整体闭环判定

| 任务 | 状态 |
|---|---|
| T1 写盘原子化与损坏防御 | PASS（QA `t04-t1-qa.md`，已合入 17272f8f） |
| T2 crash journal 与自动备份 | PASS（QA `t04-t2-qa.md`，已合入 75278e5b） |
| T3 恢复入口+N9+工具+收尾 | **PASS（本报告）** |

方案 T3 验收原文两链（①异常退出可恢复不覆盖 ②保存中断不损坏）真机复现 + headless 恢复 7 用例 + 多 tab/损坏 journal + N9 抽验 7 格 + 六门 + 工具（BRP/MCP）+ book + 用户清单——**全部落位**。

**VERDICT: PASS — T04 可勾选（roadmap），建议主控 `--no-ff` 合入 `7caf0bad`**
