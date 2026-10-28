# T04-T1 实施报告：写盘原子化与损坏防御

- 分支：`loop/t04-save-recovery`（自 main 9175028f）
- 提交：**160893e6** `Make every authoritative write atomic and add corruption defenses`（13 files, +776/−29；`.gitignore` 的 `.mimosa/` 行系主控侧改动，未包含在提交内）
- 规格：`loop/plans/t04-save-backup-recovery.md` §二 T1 + §0 + §五；裁决 4 选 A（sync_all）；小定案（untitled Save 走 Save As 子流程）

## 改动逐项（对应方案改动面 1-5）

| # | 改动 | 文件 | 说明 |
|---|---|---|---|
| 1 | prefab 落盘原子化 | `src/prefab/operators.rs`（save_prefab_to_disk） | `fs::write` → `write_atomic`；`write_upgraded_prefabs`/场景保存链经此函数自动覆盖。`write_unsaved_model_settings` 的落盘点 `write_levels`（`src/model_lod.rs:392`）**已经**走 `write_atomic`（核实现状，无需改动） |
| 2 | 配置/转换写盘原子化 | `src/project.rs`（save_project_config + create_default_project）、`src/project_settings.rs:95`、`src/jsn_to_bsn.rs`（commit_conversion + convert_catalog_file） | 全部改 `write_atomic`；jsn_to_bsn 场景 `.bsn` 补 `stamp::with_stamp`（catalog 是资产文档，不加场景 stamp，维持既有语义） |
| 3 | 损坏配置先备份再重建 | `src/project.rs`（新 `back_up_corrupt_project_config`）、`src/project_select.rs`（transition_to_editor） | 坏 `project.json` rename 为 `project.json.corrupt-<毫秒ts>` 后走默认重建；状态栏 `notify_info` 告知备份名（Y9「损坏静默覆盖」红→绿） |
| 4 | write_atomic 补 fsync + 孤儿 tmp 清扫 | `crates/jackdaw_api_internal/src/document.rs` | temp 写后 `sync_all()` 再 rename（裁决 4-A）；新 `sweep_orphan_temp_files(root)`：只删 `.{name}.tmp-{pid}` 模式、mtime 早于 60 秒（保护并发实例在写）的文件，跳过 `.git`/`target`，返回删除数；挂在 transition_to_editor（打开工程必经点），不触碰 `JACKDAW_CONFIG_DIR` 语义（清扫范围=工程目录树） |
| 5 | N8：untitled Save = Save As 子流程 | `src/scenes/confirm_dialog.rs` + `src/scene_io/load.rs` | 新资源 `PendingSaveAsClose{tab_index}`；apply 的 untitled Save 分支：swap 到目标 tab → `save_scene_with_outcome` → `DialogOpened` 时挂起 deferred close（tab 保持打开且脏）；`poll_scene_dialog` Save 分支：保存成功 → `finish_pending_save_as_close`（执行 `scene_close_system_unprompted`），取消/保存失败/refused 早退 → `cancel_pending_save_as_close`（回到未关闭状态）。模块 doc 同步改写（删除「Save falls back to Discard」的自认偏差） |
| 垫片 | 可见性放宽（无行为变化） | confirm_dialog.rs / project_select.rs / scene_io | `apply_confirm_dialog_action`、`transition_to_editor` pub 化；`SceneDialogTask` pub + scene_io re-export——为 guards 集成测试可达；红证即跑在「垫片 + 旧行为」上 |

## 测试（tests/guards/atomic_writes.rs，9 用例 + document.rs 内 3 单测）

| 用例 | 覆盖 |
|---|---|
| a_failed_prefab_save_keeps_the_old_file_byte_for_byte | N4：temp 槽被占 → 保存 Err + 旧 prefab 字节不变 |
| a_failed_project_config_save_keeps_the_old_file_byte_for_byte | Y9 原子侧：同法 project.json |
| a_failed_conversion_keeps_the_old_bsn_and_the_source_in_place | W9 原子侧：旧 .bsn 不变 + .jsn 未被 rename .bak |
| a_committed_conversion_carries_the_version_stamp | W9 stamp：转换产物首行 `// jackdaw ` 且可 parse |
| a_damaged_project_json_is_backed_up_before_the_default_replaces_it | Y9 全链：.corrupt-<ts> 存在且内容=坏文件、新 config 可解析、状态栏含 "damaged" |
| an_untitled_tabs_save_opens_save_as_instead_of_discarding | N8 前半：Save 后 tab 留开、SceneDialogTask 已排队、仍脏 |
| a_resolved_save_as_closes_the_confirmed_tab | N8 后半：deferred close 在保存落地后关 tab |
| a_dismissed_save_as_leaves_the_tab_open_and_dirty | N8 取消：tab 保留仍脏、PendingSaveAsClose 清空 |
| startup_sweeps_orphan_temp_files | N6：`.zone.bsn.tmp-999999`（backdate 2min）启动被清；`zone.bsn.tmp-1`（无点前缀）、`.zone.bsn.tmp-not-a-pid` 保留 |
| document.rs 单测 ×3 | write_atomic 成功清理 / 失败保旧文件 / sweep 只取陈旧编辑器 tmp |

## 红→绿（🔴 三条必修全有数字）

跑法：同一测试文件，先在「垫片 + 旧行为」上跑（`loop/reports/t04t1-red-run.log`），再在产品改动后跑（`loop/reports/t04t1-green-run.log`）。

| 缺陷 | 红证断言（旧行为 FAIL 位置） | 红 | 绿 |
|---|---|---|---|
| **N4** prefab 保存中断损坏旧文件 | `result.is_err()` + 旧文件字节不变（裸 fs::write 直接写穿目标 → 保存 Ok、旧字节丢失） | FAILED | ok |
| **N8** untitled Save=Discard | Save 后 `tabs.len()==2` + SceneDialogTask 存在（旧代码直接关 tab） | FAILED | ok |
| **Y9** 损坏静默覆盖 | `.corrupt-*` 备份存在且内容=坏文件（旧代码直接覆盖） | FAILED | ok |
| （伴生）W9 原子/stamp、W9 伴生 project.json 原子、N6 sweep | 同上文件 | FAILED | ok |

- **红：`test result: FAILED. 0 passed; 7 failed; 0 ignored`**（t04t1-red-run.log:189）
- **绿：`test result: ok. 9 passed; 0 failed; 0 ignored`**（t04t1-green-run.log，guards atomic_writes）
- 另 `cargo test -p jackdaw_api_internal document`：**4 passed; 0 failed**

## 门禁（quick 四门，亲跑，日志 loop/reports/gate-*-t04t1.log，各行独立 exit code）

| 门 | 命令 | exit | 数字 |
|---|---|---|---|
| fmt | `cargo fmt --all -- --check` | **0** | — |
| clippy | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **0** | — |
| fast | `cargo xtask fast` | **0** | 2869 run: **2869 passed**, 2 skipped |
| integration | `cargo xtask integration` | **0** | 5086 run: **5086 passed**, 2 skipped |

## 真机链（BRP，脚本 `loop/qa/t04t1-save-sha.ps1`，证据 `loop/reports/t04t1-live/`）

my-game（`C:\Users\linbo.zhang\Projects\my-game`）→ 新构建编辑器（dylib host，端口 15812）→ `jackdaw/status` 就绪（active scene=`assets\scene.bsn`）→ `jackdaw/call_operator scene.save`：

```
[save] {"id":"scene.save","result":"finished"}
[saved file] assets\scene.bsn (116352 bytes)
[stamp line] '// jackdaw 0.21.0-dev | bevy main' ok=True
[sha disk body]  B35F49482162D87AFD2549D9ED864748CE2F2B646B04D8C69F4D1429C6568CB0 (116318 bytes)
[sha editor emit] B35F49482162D87AFD2549D9ED864748CE2F2B646B04D8C69F4D1429C6568CB0 (116318 bytes)
SAVE VERDICT: PASS (stamp=True sha_match=True)
```

盘上去掉 stamp 首行后的字节与 `jackdaw/scene_bsn` 的内存 emit **SHA256 逐字节一致**；保存后工程内 `*.tmp-*` 残留 = 0。保存前原文件已备份至 `scene.bsn.pre-save.bak`。

## 偏差与取舍（如实记录）

1. **故障注入法由 blocked-parent 改为 temp-槽占用法**：blocked parent（父目录被文件挡住）下新旧实现的 open 都直接失败、都不碰旧文件，无法区分裸写与原子写，红证不成立。改为预创建 `.{name}.tmp-{本进程pid}` 目录占住 write_atomic 的暂存位：裸 `fs::write` 照样写穿目标（保存 Ok、旧字节丢失 → 断言 FAIL），原子写失败并保留旧文件（PASS）。三条红证全部由该差异支撑。跨平台、零新依赖。
2. **sync_all 无 headless 断言点**：掉电语义无法在单测注入；实现层保证（temp 写 → `sync_all` → rename）+ 注释，真机链验证正常保存。
3. **真机 SHA 对比口径**：`jackdaw/scene_bsn` 返回内存 emit body（无 stamp，设计使然——stamp 只在落盘边界加，`scene_io/stamp.rs` 注释），故断言为「盘上文件首行匹配 stamp 格式 + 去首行后与 emit 逐字节一致」，而非全文件原样 SHA。stamp 行格式已单独断言。
4. **catalog 不加 stamp**：`convert_catalog_file` 只改原子写；catalog 是资产文档非场景文档，读取方现状无 stamp，加了反而引入未验证行为。buglist W9 备注已注明。
5. **N8 的 poll 接线**由 fn 级测试（finish/cancel）+ 现有 poll 代码路径覆盖：headless 无法构造「已完成并返回路径的 rfd task」（SceneDialogTask 内字段不可从外部伪造）。集成层已断言「Save 后 SceneDialogTask::Save 已排队」（方案指定的 headless 化方式，先例 confirm_dialog.rs:215-219）。
6. **垫片**：红证依赖三处可见性放宽（见改动表），均为 pub 化、零行为差异；红证跑在垫片之后、行为改动之前，有效性不受影响。
7. **write_unsaved_model_settings 无需改**：其落盘函数 `write_levels` 已是 `write_atomic`（765b4599 现状），方案预估项按实际核实免除。
8. **save_all 链未动**：核查确认 quit 的 SaveAll 对 dirty untitled tab 本就安全（`scene_save_all_system` 返回 false 阻止退出，不丢数据），无 N8 类缺陷。
9. **真机 launch 的 ShellExecute 冷启动失败一次**（bat 生成但编辑器未起，原因未查）：手动 `cmd /c` 执行同 bat 兜底成功；脚本已重构为 before 快照落盘（`before-bsn.txt`），launch/save/wrap 三阶段可独立复跑（辅以 `loop/qa/t04t1-before-snapshot.ps1` 单步补快照）。
10. **并发实例误删防护**：sweep 跳过 mtime 60 秒内的 tmp（另一个实例可能正在写）；极端撞窗的后果 = 那次保存失败可重试，权威文件不受损（tmp 与目标分离）。`.corrupt-<ts>` 用毫秒时间戳，Windows 文件名安全。

## 台账

- buglist.md（未跟踪，保持未跟踪）：**Y9、W9 打 `- [x]` + `> 已修复 160893e6` 备注**（含覆盖用例名）。
- loop/ 目录未入库（.git/info/exclude 排除）；loop/README.md、loop/progress.md、loop/plans/ 未触碰。
- 未 push。
