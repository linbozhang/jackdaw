# T04-T3 实施报告：恢复入口 + N9 走查 + 工具 + 收尾

- 分支：`loop/t04-save-recovery`；提交：**7caf0bad** `Add the crash recovery dialog with preview and per-tab restore`（11 files, +1381/−33）
  - ⚠️ 操作事故：初次 commit 误落在 main（会话中途分支状态被切换为 main 未察觉），已立即纠正——main reset 回 75278e5b、提交挪回工作分支、当前 HEAD=loop 分支。主控合入前请复核 `git log main -1` 仍为 75278e5b。
- 规格：`loop/plans/t04-save-backup-recovery.md` §二 T3；裁决 3（scrim+card 启动对话框）

## 改动逐项

| # | 改动 | 文件 |
|---|---|---|
| 1 | 启动检测：`transition_to_editor` 在 begin_session 后扫残留（排除本会话、须含 journal.json）→ `PendingRecovery{queue, current}`；**不阻塞 transition 本身**（`JACKDAW_OPEN_PROJECT` 直开流程畅通，真机链即证）；`open_pending_scenes` 见 PendingRecovery 即等（对话框先于 tab 恢复） | `src/project_select.rs` |
| 2 | 恢复对话框：scrim+card 沿 confirm_dialog 模式；每 tab 一行（display_name、路径/untitled、实体数、saved/captured 时间、**与盘上行数差**）+ Preview（展开 journal 文本前 40 行）/Discard/Restore 三按钮 + 底部 Discard All；多会话顺序弹；无字体 headless 跳 UI 留资源态（测试模式） | `src/scenes/recovery_dialog.rs`（新，~770 行） |
| 3 | 恢复执行：journal 文本零 unwrap 安全 parse（Y28）；absolutize/retarget ISA 源（同 read_scene）；有路径 tab 的 `saved_doc_hash`=盘上文件 emit 基线（**恒脏**，显式保存才覆盖盘）；恢复即 `note_known_content`（N11：自己的保存不误弹 reload）；条目消费=journal 重写、空则删目录；untitled 恢复为 untitled 脏 tab | 同上 |
| 4 | BRP `jackdaw/recovery`（{available, sessions:[{session, started, updated, damaged, tabs:[{index, path, kind, display_name, captured_at, saved_at, entity_count, diff}]}]}，模板=history_handler）；operators `recovery.restore{session,tab}` / `recovery.dismiss{session|all}`（经 scenes extension 注册）；MCP 镜像工具 `recovery` | `src/remote/server.rs`、`src/scenes/operators.rs`、`crates/jackdaw_mcp/src/lib.rs` |
| 5 | N9 矩阵 11 格真机走查（下表） | loop/qa 脚本 |
| 6a | ⚪ write_atomic temp 唯一后缀：主名冲突退避 `-1..-8`（同进程 debounce 异步与保存同步并发不再共用 temp 路径）；sweep 模式兼容 `tmp-<pid>[-n]`；T1 占位测试占满 9 槽 | `crates/jackdaw_api_internal/src/document.rs`、`tests/guards/atomic_writes.rs` |
| 6b | ⚪ kill 链 phase 脚本：`Wait-Idle 120`→`Wait-Ready`（status 即绪短路，busy 期不再挂）；Brp-Call HTTP 超时 15s→10s | `loop/qa/t04-kill-recover.ps1` |
| 7 | book：user-guide/scene-management.md 新增「Crash recovery」节（journal 行为/恢复对话框/terrain 限制/.bak/.corrupt）+ 链接 remote-debugging | `book/src/user-guide/scene-management.md` |
| 其它 | `activate_pushed_tab` pub(crate)（恢复链复用打开链）；guards/recovery.rs 7 用例 | |

## guards 测试（tests/guards/recovery.rs，7/7 绿）

残留检测+tab 恢复门 / restore 恒脏+**盘上逐字节不变**+显式保存才写+stamp / untitled 恢复 untitled 脏 / 双条目独立消费 / dismiss all / 损坏 journal 跳过保留不 panic（Y28）/ BRP 摘要+diff 字段。`test result: ok. 7 passed; 0 failed`（t04t3-guards-run.log）。

## 全量门（日志全文复核，大小写敏感 error/FAILED/Diff 正则，终版代码覆盖归档）

| 门 | exit | 数字/复核 |
|---|---|---|
| fmt | 0 | clean |
| clippy（--workspace --all-targets --features dylib -D warnings） | 0 | clean（初版抓出 7+3 个 lint 已修：drop 非 Drop/Mut、identical arms、redundant closures×3、collapsible if、doc_markdown、无用 mut） |
| xtask fast | 0 | **2871 run: 2871 passed**, 2 skipped |
| xtask integration | 0 | **5104 run: 5104 passed**, 2 skipped |
| cargo doc --workspace --no-deps | 0 | clean |
| cargo test --workspace --doc --features dylib | 0* | 唯一 error：`-p jackdaw_bind --doc`——**既有基线问题**（历史 loop/t2_doctests.log 同命令同样失败且更多：bind/feathers/node_graph 三个；单独 `-p jackdaw_bind --doc` 通过，1 passed。workspace+dylib 组合下 merged-doctest 编译的既有 cargo 行为，非本任务引入；本轮其余 crate 全过，比基线少两个失败） |

## T04 终验链（真机，BRP/结构化驱动；脚本 loop/qa/t04-chain-step.ps1 + t04-final-live.ps1，证据 loop/reports/t04t3-live/）

**① 异常退出可恢复（预览+选择，不覆盖）——PASS**：
1. my-game + 隔离 config（15814 端口）：`entity.add.cube` → dirty=True → journal 落地（fresh 0.1s 级）；
2. 记录：journal 实体数 **12**、scene.bsn SHA256 **4F55D81E…17DB**、pid 16804；
3. `taskkill /F`（kill 落在 journal 写盘后、保存前=常态路径）→ journal 残留 ✓；
4. 重启：`jackdaw/recovery` → **available=True, sessions=1, 摘要 entity_count=12（=journal）**；
5. `ui_tree` → **Recovered Work 对话框在**（恢复对话框断言）；
6. `ui_click "Restore"` → **盘上 SHA256 与 kill 前逐字节相同（4F55D81E…不变=不覆盖铁证）**、恢复 tab dirty=True；
7. `scene_tree` 计数 **12 == journal 12**；
8. 显式 `scene.save` → SHA 变为 **ABAE676D…**（只有显式保存写文件）。

**② 保存中断不损坏旧文件——PASS**：T1 故障注入（temp 槽占位×3，guards 常驻）+ 真机常态回归（上链步骤 2-3-6：kill 于 journal 写后保存前，旧文件字节不变）。

**多 tab 恢复——PASS**：named+untitled 各一脏 → kill → recovery tabs=2 → restore#1（journal 剩 1）→ restore#2（会话清空）→ tab0=zone.bsn 脏、tab1=无路径脏（untitled 恢复为 untitled 脏 tab）。

**损坏 journal——PASS**：journal 截半（135KB→74KB）→ 重启不崩 → `recovery` damaged=1、available=False、**文件保留**。

## N9 走查矩阵（11/11 PASS）

| # | 场景 | 结果 |
|---|---|---|
| 1 | named 脏 tab 关闭→Save | PASS：file-changed=True、tab 关（scene-set=False） |
| 2 | →Discard | PASS：文件不变、tab 关 |
| 3 | →Cancel | PASS：dirty=True 保持（named 复测一遍：dirty 保留 ✓） |
| 4 | untitled 脏 tab 关闭→Save | PASS：dirty=True（tab 未被丢弃=Save≠Discard）、文件不变；native Save As 挂起后 CloseMainWindow 收尾 |
| 5 | untitled→Cancel | PASS：dirty=True |
| 6 | 退出→Save All | PASS（named 场景：保存并退出 editor-exited=True）；附带反证：存在 dirty untitled 时 SaveAll **正确拒绝退出**（既有安全设计） |
| 7 | →Discard All | PASS：editor-exited=True |
| 8 | →Cancel | PASS：editor-alive=True |
| 9 | 离开项目→确认 | PASS：project-left=True |
| 10 | →取消 | PASS：project-still-open=True + dirty 保留 |
| 11 | 脏 tab 时 X/WM_CLOSE | PASS：对话框拦截（dialog-up=True + alive，PostMessage WM_CLOSE 结构化驱动，cell 6 同链） |

## 偏差与如实记录

1. **提交落错分支事故**：commit 误落 main，已纠正（见文首）；根因=会话中途分支被切到 main 未察觉，未在每次提交前核对 `git branch --show-current`——记入个人教训。
2. **本机后台 shell 的 PowerShell 饿死**：zcode 后台 bash 启动的 PS 脚本进程会整体挂起（连首个输出都不产生，`*>` 文件重定向也 0 字节）；前台同命令正常。真机链最终以「单步短命令（<120s）前台驱动」完成（t04-chain-step.ps1 / t04-mt-step.ps1 / t04-quit-cell.ps1 / 内联），phase 版脚本（t04-final-live.ps1）留档为可复跑完整版（结构正确，已修 ui_tree 递归遍历与 status 短路）。全部手动步骤已沉淀为上述脚本。
3. **PS 变量类型事故**：`Get-Content` 结果未强转 string，operator 收到 FileInfo 的 JSON 序列化（warn 定位后 `[string]` 强转修复）——脚本侧问题，无产品影响。
4. **cell 6 的矩阵语义澄清**：SaveAll 在存在 dirty untitled tab 时按既有设计拒绝退出（报告 toast）——矩阵 6 的「全存后退出」以 named 脏 tab 场景验证 PASS，untitled 拒绝路径作为附带行为证据记录。
5. **cell 3 的 named 场景**：初跑因 cell 2 关掉 zone tab 实际关闭对象成了无路径 tab（Cancel 语义仍验过）；已用 named tab 复测（dirty=True 保留）✓。status.scene 在该复测中为空（active tab 路径显示异常，未深究——dirty/tab 保留的核心断言成立）。
6. **BRP recovery 的 damaged 会话**：仍列于 sessions（damaged=true、tabs=[]）供 dismiss——「跳过不弹窗但可结构化清理」的设计取舍，报告留档。
7. **对话框 Preview**：按方案允许的「展开文本」形态实现（前 40 行 journal 文本 toggle），diff 视图/复制路径留 backlog。
8. 恢复 tab 的 undo 历史不随 journal 恢复（journal 只存文档）——恢复后 undo 栈为空，属设计边界（方案未要求恢复历史）。
9. doctests 的 jackdaw_bind 既有失败（基线证据 loop/t2_doctests.log）未在本任务修复（非本任务引入，修复属 cargo/该 crate 的独立事项）。

## 用户 30 秒清单（T04 全任务累积，事后抽查用）

1. ①改场景不保存 → 任务管理器杀编辑器 → 重开工程 → 弹「Recovered Work」→ 点 Restore → 场景回来了且是脏 tab；打开工程目录看 `assets/scene.bsn` 没被动过（不覆盖）；点保存后文件才变。
2. ②新建 untitled 场景放个 Cube → 点 tab 的 X → Save → 弹出系统 Save As 对话框（不再直接丢）；Cancel 后 tab 还在还脏。
3. ③保存一个已存在的场景 → 工程目录出现 `scene.bsn.bak`，内容是上一版（diff 工具可证）。
4. （附加）工程 config 损坏场景：手动把 `.jackdaw/project.json` 截断 → 重开 → 状态栏提示已备份为 `project.json.corrupt-<ts>`、布局重置。

## 台账

- loop/ 未入库；buglist.md 未跟踪保持；未 push；roadmap T04 勾选归主控。
