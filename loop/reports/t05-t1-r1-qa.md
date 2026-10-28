# T05-T1 修复轮 1 重验报告（R1 QA）

- 角色：QA（只验不修）｜日期 2026-10-25｜分支 `loop/t05-references`，修复提交 **69e44589**（5 文件 +238/−14，`git show --stat` 亲核一致），基于已验 PASS 的 6ba0ce4b。
- 上轮报告：`loop/reports/t05-t1-qa.md`（VERDICT: PASS，附 🟡×2 + ⚪ 若干）；本报告为其修复轮重验，最小范围。
- 程序返工自述：`loop/reports/t05-t1-report.md` §返工第 1 轮。
- QA 亲跑归档：`loop/reports/gate-guards-refrewrite-t05t1r1qa.log`（12 条单跑，EXIT 0）、`loop/reports/gate-clippy-alltargets-t05t1r1qa.log`（加强门复跑，EXIT 101，见 §三）。

---

## 一、两 🟡 组合复验（红→绿真实 + 断言质量）

### 🟡① 文件夹移动丢子路径后缀 → 亲验绿

- **亲跑**：`renaming_a_folder_retargets_a_tab_under_it_onto_the_same_tail ... ok`（含全部 12 条 12 passed / 0 failed，EXIT 0，gate-guards-refrewrite-t05t1r1qa.log）。
- **红证对上**（t05t1_r1_red1.log 亲读）：编译过（`Finished in 28.54s`）、`0 passed; 1 failed`、:745 断言失败。**红因信息量关键**：失败输出 tab.path 为**旧完整路径** `...\assets\props\sub\scene.bsn`（若仅是"错指根目录"应显示 `assets\props`）——证明修复前该组合里 `fs::rename` 被 Windows watch 句柄拒绝、**联动链整体未执行**（tab 原样、文件夹未动）。即 🟡① 的真实严重度比上轮判的更高（文件夹 rename + 树内有打开 tab = 整个操作失败），程序发现的平台级障碍是真问题而非虚构（headless editor_test_app 的 watcher 确持句柄，红证即复现）。
- **断言质量核**：tail 拼接真断言（`ends_with(assets/prop/sub/scene.bsn)`）+ 文件夹本体移动（旧 `!exists` / 新 `is_dir`）+ `save_scene` 成功且落盘 `assets/prop/sub/scene.bsn`——三段齐。**缺口（⚪）**：prefab cache key 迁移（`canonical_prefab_path(&now)`）与 display_name 无直接断言（用例为 scene tab；文件夹 rename 不改文件名，display_name 语义上不变；prefab tab 组合留 T3 真机矩阵 4/2 格覆盖）。
- 代码修复核对（reference_rewrite.rs:508-530）：per-tab `strip_prefix(old_canonical)` 保留 tail 拼接，与 `migrate_index_entries`/`retarget_cards` 同族逻辑对齐 ✓；prefab 分支改用 `&now` ✓。

### 🟡② 全部 tab 站在被删路径时 N3 复活洞 → 亲验绿

- **亲跑**：`a_forced_delete_that_would_close_the_last_tab_is_refused ... ok`（同上日志）。
- **红证对上**（t05t1_r1_red2.log）：编译过、`0 passed; 1 failed`、:820 `nothing was deleted behind the refusal`——旧守卫（`==1`）下 2/2 tab 全持有时删除照常进行、文件真被删，正对缺陷本体。
- **断言质量核**：逐项断言 ✓——两个场景文件分别 `is_file`（"nothing was deleted behind the refusal"）、`tabs.len() == 2`（"no tab was closed either"）、警告含 "would close the last open tab"（拒绝文案）。
- **「部分在路径」组合**：守卫改为 `holding.len() == tabs.len()`（file_ops.rs:362-365，正是上轮建议的推广形式）；部分持有时不拒绝、循环全关持有者（close 时 tabs.len() 恒 ≥2）——由既有用例 5 `deleting_an_open_scene_is_refused_and_forced_close_removes_it`（2 tab 删 1，force 关 1 留 1）覆盖，本轮 12 条单跑中绿。两组合（全在/部分在）均有用例。
- move_file 侧对称加 `release_watch_under`（file_ops.rs:790-794）✓。

## 二、release_watch_under 审查（简报外平台级新行为）

**修法**（scenes/external_watch.rs:186-210 + project_window.rs:2214-2219 + file_ops.rs:790-794）：rename/move **目录**前，对 watched 集合中 `== moved 或 starts_with(moved)` 的条目 unwatch 其 parent folder（watch 挂文件夹，与 watch 侧 :473-480 对称）并从 watched 移除；fs::rename 放行。

**重建与窗口期漏检分析**（refresh_watch_list :438-509 亲读）：
- 重建机制：`refresh_watch_list` 每帧以 `scenes.is_changed()` 短路；`retarget_tabs` 内 `scenes.set_changed()` → 下一帧 current（tab 新路径）≠ watched → **整体重建 watcher**（notify 每次新建，本就是全量重建模式而非增量）→ 对 newly_watched 逐条 `queue_recheck`（手动 pending 补查一次，注释明言弥补 "notify reports nothing from before watch() returned"）+ known 无记录时读盘记基线。
- **窗口期（释放→重建）丢 notify 事件的后果**：由 newly_watched 的强制 recheck + hash 对账兜底——盘上内容与 known 不符即弹 reload prompt，不依赖事件本身。语义一致性：新路径首次入表从盘取基线 = 「关 tab 再开/新开 tab」的既有语义；watch/unwatch 均挂 parent folder 语义对称。**审查通过，无新 🔴**。
- **🟡→⚪ 缺口（新发现，失败分支）**：`fs::rename` **失败**时（rename_file/move_file 的 Err 分支直接 notify_error + return），release 已执行（watched 条目已删、句柄已放）但无 `set_changed` → refresh 不重跑 → 这些 tab 的 watch **静默丢失直到下次 tab strip 变化**，且该路径不走 newly_watched recheck（无 hash 对账兜底）。触发窄（目录 rename/move 失败本身异常，如目标被外部进程占用），后果为异常后一段时间的外部修改检测静默。修复前该场景 rename 必败但 watch 完好，故此为修复引入的退化窗口。定 ⚪ 偏上：建议失败分支补一行 `scenes.set_changed()`（或对被释放路径 queue_recheck）触发重建，归 T2 顺手。

## 三、⚪ 复核

- **twin 双扩展**：`replacement` twin 分支改 `binary_twin(Path::new(to))` ✓（reference_rewrite.rs:196-203）；lib 新单测 `a_twin_spelling_is_rewritten_as_the_new_paths_own_twin` 亲核在跑且 ok（r1_lib.log），断言产出 `b/patinated.material.bsb` 且明示拒绝 `bsn.bsb` ✓。
- **must_use 两处已清**：本轮 all-targets 复跑无 :188/:578 的 unused `OperatorResult` error（diff 改 `let _ =` 亲核）✓。
- **但加强门新发现一处本轮引入的 lint error**：`src/reference_rewrite.rs:754`（新 twin 单测 `&[moved.clone()]`，clippy `cloned_ref_to_slice_refs`，在 lib test target 才被检查）——契约 clippy 门（无 --all-targets）不拦，r1_clippy 归档 12 行无 error ✓。⚪ 同性质（测试代码 lint 卫生）：建议去 `.clone()`（`&[moved_ref]` 或先 let moved2）；另 `tests/extern_redirect_ecosystem.rs:1:11` unfulfilled lint expectation 为既有历史（上轮为 reflect_auto_register.rs 同类），非本任务。

## 四、quick 门抽验（t05t1_r1_* 归档全文复核）

| 门 | 归档 | 结果 | 全文复核 |
|---|---|---|---|
| 格式 | t05t1_r1_fmt.log | 通过 | 0 行输出，无 Diff |
| Lint | t05t1_r1_clippy.log | 通过 | 12 行，无 error/warning（仅编译进度行） |
| 单测 | t05t1_r1_lib.log | 通过 | 56 个 `test result:` 行**全部 0 failed**（含 reference_rewrite::tests 3/3）；"error" 匹配行均为测试内容噪音（PIE build failed 等预期输出） |
| guards | t05t1_r1_guards_skip.log | **163 passed / 0 failed**（12 filtered） | 失败匹配行均为测试名/环境噪音（PIE cannot build） |
| guards 补 | t05t1_r1_green_final.log | **12 passed / 0 failed**（163 filtered） | 同上，噪音行非失败 |
| 红证 | t05t1_r1_red1/red2.log | 各 `0 passed; 1 failed` 断言失败 | §一已核 |

- **guards 175 覆盖核对**：163（skip 版）+ 12（单跑版）= **175** ✓（原 173 + 2 新用例；红证日志 "174 filtered out" 旁证总数 175）。
- **口径备注（⚪）**：程序 r1 归档日志**无独立 `EXIT:` 行**（上轮同风格），按 2026-10-25 标准（全文复核为主、exit code 辅助）以内容判定均通过；QA 亲跑两份（12 条 + all-targets）带 EXIT 行归档。
- 日志复核补充：diag/check 系为开发中间产物（含编译错误），最终门禁日志干净，符合「重跑覆盖归档」口径。

## 五、PASS 条件核对与结论

- 两组合绿（QA 亲跑 ok）+ 红证对上（各 0/1 failed、断言失败、红因与缺陷对应——red1 更揭示平台级障碍为真实根因）✅；
- release_watch_under 审查**无新 🔴**（重建有 recheck+hash 对账兜底、语义同构；新发现 rename 失败分支的 watch 恢复缺口 ⚪ + twin 单测一处 all-targets lint ⚪，均不拦放行、建议归 T2 顺手）✅；
- 门禁日志干净（四门 + guards 175 覆盖）✅；
- 上轮 🟡×2 修复质量：tail 拼接对齐同族逻辑、守卫推广为建议形式、move 侧对称覆盖 ✅。

VERDICT: PASS
