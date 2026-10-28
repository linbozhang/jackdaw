# T04-T2 实施报告：crash journal 与自动备份

- 分支：`loop/t04-save-recovery`（T1 后同步 main 17272f8f）
- 提交：**75bfc76e** `Add the crash journal and single-file backups`（12 files, +1110/−4；`.gitignore` 的 `.mimosa/` 系主控侧改动未包含）
- 规格：`loop/plans/t04-save-backup-recovery.md` §二 T2；裁决 1（config_dir/state/sessions）、2（debounce 2s）、5（.bak 单份）、6（sidecar 不进 journal）已按主控裁定执行

## 改动逐项（对应改动清单 1-6）

| # | 改动 | 文件 | 说明 |
|---|---|---|---|
| 1 | journal 模块 | `src/scene_io/session_journal.rs`（新，~470 行） | 会话目录 `state_dir()/sessions/<project-hash16>/<pid>-<unix秒>/journal.json`（`JACKDAW_CONFIG_DIR` 整体覆盖=测试隔离免费，裁决 1）；启动建目录+轮转；正常退出删目录（`end_session`：`OnExit(Editor)`→`cleanup_editor` + `Last` schedule 的 `end_session_on_app_exit` 用 AppExit 计数快照检测，覆盖 deferred-command 写入帧）；轮转保留最近 5 个会话目录（mtime 排序+目录名 tie-break——活实例的 journal 每 2s 重写推新其目录 mtime，不会被误删）；`read_session_journal` 损坏安全读取（parse 失败→warn+None+文件保留，Y28 红线） |
| 2 | 触发系统 | session_journal.rs + scene_io/mod.rs | exclusive `session_journal_system`（Update，Editor 态）：对 tab 条计算 `dirty + observed_pushes + observed_undo_len` 签名（T03 信号原样，无第三轨），签名变化重置 2s debounce（常量 `JOURNAL_DEBOUNCE`）；到期对**所有脏 tab** 收集快照——active tab 走 save 分支同源 emitter（scene: `emit_bsn_scene_for_file`，prefab: `emit_bsn_scene_with_inline_assets`+relativize+`asset_file_text`，与 `save_prefab_to_disk` 同管线）；inactive tab 从其持有快照 emit（scene: capture 时的 AST，prefab: PrefabAstCache 条目；inactive 不可编辑=快照即最新）。全部变净时删除 journal 文件。**写盘拆分**：主线程只 collect（emit），serialize+`write_atomic` 走 `IoTaskPool` detach（debounce 路径）；保存边界的重写走同步（见 #4） |
| 3 | journal 条目 | session_journal.rs | `JournalFile{schema, editor_version, pid, started, terrain_note, tabs[]}`；`JournalTab{path\|null, kind, display_name, captured_at, saved_at, entity_count, document}`；`terrain_note` 常驻标注 sidecar 限制（裁决 6）；`SceneTab` 新增 `saved_at: Option<String>`（保存边界写入 RFC3339） |
| 4 | .bak 轮转 + 条目闭环 | `crates/jackdaw_api_internal/src/document.rs` + save.rs | `write_atomic` 覆盖前目标存在则先 rename `<name>.bak`（单份，Windows rename 覆盖旧 bak；第二步 rename 失败回滚 bak→path）；`save_scene_inner` 两个基线写入点（prefab/scene 分支）同点位调 `session_journal::on_tab_saved`→全量同步重写 journal（已保存 tab 不脏，自然出局；顺带清 Save-As 场景的失配旧条目） |
| 5 | 多实例隔离 | session_journal.rs | 会话目录 `<pid>-<ts>`；轮转按 mtime 排序使活实例目录恒新 |
| 6 | QA 🟡 吸收 | `crates/jackdaw_bsn/src/file.rs` | `convert`（text↔binary 孪生）裸 `fs::write` → crate 内私有 `write_atomic`（同 temp+sync+rename 模式；jackdaw_bsn 不能反向依赖 api_internal，模式重复而非链接，注释注明）——消除半截孪生+重试撞 TwinExists 卡死 |
| 既有测试更新 | `src/scene_io/save.rs` 测试 | `write_atomic_replaces_existing_content_and_cleans_up_its_temp_file` 原断言「目录无其它文件」与 .bak 新承诺冲突 → 更新为「无 temp 残留 + `.bak`=旧内容逐字节」（语义随设计演进，非放松） |
| 字段波及 | tests/scenes/scenes_swap.rs、tests/stage/asset_references.rs | `SceneTab` 字面量补 `saved_at: None`（其一为 compile-only 守卫，按预期拦住并同步） |

## 测试：tests/guards/session_journal.rs（9 用例）

| 用例 | 验收项 |
|---|---|
| a_dirty_tab_journals_the_save_emitters_own_text | **a**：journal 落地、条目 document 与 `emit_bsn_scene_for_file` 手动 emit 逐字节相等、entity_count=live roots、无 stamp 行 |
| a_clean_tab_journals_nothing | **a**：干净 tab 无 journal 文件 |
| a_crashed_session_leaves_its_journal_behind | **b**：drop app（无 AppExit）→ 会话目录+journal 残留且可读 |
| a_clean_exit_removes_the_session_directory | **b**：`write_message(AppExit)` + 一帧 → 目录删、资源清 |
| beginning_a_session_rotates_old_ones_beyond_five | **b**：7 残留+新会话 → 保留最新 5、最旧被扫 |
| a_damaged_journal_reads_as_none_and_stays_on_disk | **b**：坏 JSON → read None、不 panic、文件保留 |
| the_journal_lives_under_the_overridden_config_dir | **c**：journal 路径 starts_with(JACKDAW_CONFIG_DIR) |
| a_successful_save_spends_the_entry_and_backups_the_old_file | **d**：保存后 journal 无该 tab 条目 + `zone.bsn.bak` 内容=保存前逐字节 |
| the_journal_write_costs_no_more_than_five_milliseconds | **性能闸**（下节） |

guards 运行：`test result: ok. 9 passed; 0 failed`（loop/reports/t04t2-guards-run.log）；api_internal document 单测 5/5（write_atomic 成功/失败/**bak 轮转单份**/sweep）。

## 性能闸（≤5ms 帧尖刺）

| 场景 | emit-only | 主线程成本（debounce 触发帧：collect+spawn） |
|---|---|---|
| 400 实体生成场景 | 2.01ms | **962µs** |
| terrain-patch fixture（real_scene.bsn） | 1.50ms | **1.81ms** |

- 首版全同步（serialize+write_atomic 含 fsync+bak rename）实测 **13.29ms 超标**（Windows fsync 大头）——按方案预留的调整空间改为：写盘（serialize+fsync+rename）移 `IoTaskPool`，主线程只付 emit。两个场景主线程成本均 <2ms ✓。
- debounce 维持 2s 常量未调（单帧成本与 debounce 无关，无须放宽丢失窗口）。
- 保存边界的 journal 重写保持**同步**（保存帧本就是写盘帧，多一次 ~13ms 级写盘可接受；换取「保存成功→条目即刻消失」的强一致，规避异步竞态）。

## 真机 kill 链（loop/qa/t04-kill-recover.ps1 + t04-kill-recover-steps.ps1，证据 loop/reports/t04t2-kill/）

my-game + `JACKDAW_CONFIG_DIR=%TEMP%\t04-kill-cfg` 隔离 + 端口 15813：

1. **launch**：编辑器起（ShellExecute 冷启动失败一次，`cmd /c` 兜底，与 T1 同现象）；journal 会话目录 `state\sessions\01004ec43583bb23\5988-1792915901` 建立；
2. **置脏**：`call_operator entity.add.cube` → `status.dirty=true` → journal.json 落地（轮询命中时**新鲜度 0.1s**，135142 bytes）——条目 `1 -> scene:scene entities=12`；
3. **kill**：`taskkill /F /PID 5988` → journal **残留 135142 bytes**（KILL VERDICT: PASS）；
4. **relaunch**：同 config dir 重启 → 新会话 `20996-1792916758` 与死会话 `5988-1792915901` **并存**；死 journal 完整可读；新会话目录无 journal.json（干净 tab，正确）——RELAUNCH VERDICT: PASS（等效断言由文件系统直接验证）；
5. wrap：编辑器停，隔离 config 保留作证据。

脚本注记：phase 版（t04-kill-recover.ps1）的 launch/relaunch 长轮询在 my-game 后台 PIE prebuild 的 busy 期两度挂起（`jackdaw/wait until=idle` 长时间无 result），kill 链实际由 step 版脚本（t04-kill-recover-steps.ps1：dirty/check/kill 段原生跑通）+ 手动断言驱动完成；phase 版留档待 T3 修（缩短 wait 或改用 status 轮询）。

## 门禁（loop/reports/gate-*-t04t2.log，独立行 exit code，日志全文复核）

| 门 | 命令 | exit | 数字 |
|---|---|---|---|
| fmt | `cargo fmt --all -- --check` | **0** | 无 Diff |
| clippy | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **0** | 无 error |
| fast | `cargo xtask fast` | **0** | 2870 run: **2870 passed**, 2 skipped |
| integration | `cargo xtask integration` | **0** | 5096 run: **5096 passed**, 2 skipped |

## 偏差与如实记录

1. **写盘路径偏离方案原文**：方案写「emit 主线程+写盘经 IoTaskPool」但首版按同步实现（为消除保存移除竞态），性能闸实测 13.29ms 超标后**按方案预留的调整空间**改回 IoTaskPool（debounce 路径），保存边界保持同步。竞态窗口=debounce 快照 in-flight 时保存落地，最坏后果是 journal 短暂含一份已保存内容的条目（下一轮安静期被重写掉），不损坏任何权威文件。
2. **inactive tab 的 emit 非严格同源**：active tab 与保存逐字节同源（验收 a 断言）；inactive scene tab 的 journal 文本来自 capture 时刻的 AST（`emit_scene`，AsHeld 资产拼写），内容等价但资产路径拼写与保存（RelativeToFile）不同——inactive tab 无法在不动 world 的情况下走保存管线，恢复经标准打开链不受影响。
3. **journal JSON 改 compact**（非 pretty）：损坏可读性由旁边自动轮转的 `journal.json.bak` 承担。
4. **poll 接线的 AppExit 检测**用 `Messages<AppExit>` 计数快照（begin 时记录）在 `Last` schedule 比较——规避与写入系统的排序依赖，覆盖 deferred command 帧末写入的情况。
5. **`.bak` 两步 rename 的微小窗口**：path→bak 成功而 temp→path 前进程死 → 文件完整躺在 .bak（优于半截），下一步 open 会发现目标缺失而 bak 在——T3 恢复入口/用户可手动还原；已带回滚（第二步失败时 bak→path 恢复）。
6. **测试污染事故**：rotate 测试初版在 `JACKDAW_CONFIG_DIR` 隔离生效前调 `sessions_root`，把 4 轮测试残留写进了真实 `~/.jackdaw/sessions/`（共 4 hash×7 目录，全部为 `111111-*` 测试数据）——已全部清除（`~/.jackdaw/sessions` 整目录删除，该目录为 T2 新增、真实用户从无数据），测试改为先建 app 再取路径，并在断言中加「所有会话必须在隔离目录内」防回归。教训记入报告。
7. **门禁工具语义发现**：`cargo xtask fast` 的 exit code 不忠实反映段内失败（fmt Diff 与 1 test fail 时仍 exit 0）——本轮两度靠日志复核抓出（第一次：clippy 抓到 2 个我 gate-clippy 漏掉的 lint，疑似 feature 集差异；第二次：fmt 未跑；第三次：既有 write_atomic 测试与新 .bak 冲突）。最终数字以日志全文为准（Summary 行 + 无 error/Diff）。
8. **entity_count 口径**：active=live `SceneBsnAst` roots 数；inactive=快照 AST roots 数（与恢复预览展示一致）。
9. `write_unsaved_model_settings` 等链路无涉（T1 已核）；save_all/quit 链未动。

## 台账

- buglist.md：本轮无吸收条目（Y9/W9 已在 T1 打钩）。
- loop/ 未入库；未 push。
