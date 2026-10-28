# T05-T1 实施报告：改名/移动/删除的引用联动与 tab retarget

- 分支 `loop/t05-references`（自 main c6279d61 拉出），提交 **6ba0ce4b** `Rewrite asset references on rename, move and delete`
- 规格：`loop/plans/t05-reference-stability.md` §二 T1 + §0 架构事实 + §三裁决（8 项已裁定）+ §五衔接
- 改动量：10 文件，+1945/−135（`git diff --cached --stat`）

## 一、改动逐项（对应方案改动面 1–6）

1. **新模块 `src/reference_rewrite.rs`**（718 行）：
   - `ReferenceMove`（`Spelled` 精确拼写 / `Names` 路径+twin+唯一 stem / 目录前缀按组件边界，
     `folder_tail` 的 `props/` 前缀不触 `props2/`——模块单测 2 条钉死）；
   - `rewrite_ast`：AST patch 值替换（Struct/TupleStruct/Template fields/`:`Base），只动
     `takes_asset_path` 类型字段或 `@` 串——非资产 String 恰等旧路径串不被改（W10 本体）；
   - `rewrite_document(s)`：read_document → rewrite → `document_as_text`（保留 preamble/stamp）→
     `write_atomic` → `note_written` 双登记（asset_index + external_watch，migration 先例）；
   - `follow_a_move(old, new)` 联动链：盘上重写 → tab/卡片 retarget → 内存 AST 重写 →
     **index 条目挪键保 handle**（`migrate_index_entries`，rename 不孤儿化已加载 handle，
     path_of_id 立即指向新路径，live emit 不再写回旧串）→ rescan（referrers 表/stems 重建）→
     干净 tab 重算 `saved_doc_hash`（活动 tab 用 `document_fingerprint`，非活动用新暴露的
     `session_journal::stashed_document`）、脏 tab 保持脏 → journal `write_snapshot` 路径同步 →
     `report_to_caller` "renamed/moved; rewrote N references in M documents" + 状态栏。
   - `spelled_references` 扫描器自 asset_migration 迁来共用（含 `:`Base 扩展）。
2. **`rename_file` 扩展**（project_window.rs）：**fs::rename 前 rescan**（旧路径引用可解析，
   referrers 表不丢持有者——曾放错到 rename 后，红→绿间修复，见偏差）；rename 后走
   `follow_a_move`；ProjectWindowState 联动保持。W11：canonicalize 相等且拼写不同 →
   `.name.case-<pid>-<n>` 中转名两步 rename，第二步失败回滚第一步。
3. **新 operator `file.move`**（file_ops.rs 注册表 + `move_file`）：path+folder，目标须在
   assets 内目录，fs::rename 跨目录 + 同一条 `follow_a_move` 链。右键 **Move to...** 入口
   （project_window 菜单项 + `MovePickTask` 走 native_dialog 既有 pick_folder 模式 + poll 系统）。
4. **`delete_path` open-tab 守卫（N3）**：`ask_to_delete` 前置 `open_holder`（tab 或卡片命中，
   目录删除含其下，比较忽略大小写）——非 force 拒绝并 warn_caller "... is open in a tab;
   close it first, or pass force"；force 先关卡片与 tab（`scene_close_system_unprompted`，
   唯一 tab 无法关时拒绝删除并说明，防复活）再删。
5. **W8**（asset_ingest.rs）：drop 的文件 canonicalize 后仍在 assets 内 → 跳过导入直接
   select_path，无 `xxx-1.ext` 副本。
6. **`referrers_of` 补内存态（N4 T1 半）**（file_ops.rs）：索引表之外追加扫描打开中 tabs 的
   AST 引用（`references_of_tab`：非活动 scene tab snapshot / prefab cache / 活动 tab live
   emit），经 `referenced_path`（asset_index 新 pub(crate)）命中目标，删除确认覆盖未保存编辑。

附带：`AssetIndex::referrers_including_within`（含目录内文档的文件夹重写集）；
`project.migrate_asset_references` 的 `rewrite_documents` 改走本模块（W10），其
`name_references/scan_*` 文本替换实现删除。

## 二、红→绿（红证方法：`git stash push -- src` 后旧代码跑同一测试文件）

归档 `loop/t05t1_red_run.log`：**0 passed; 10 failed**——旧代码上全部用例失败。

| 必红项 | 用例 | 红证（行号/断言） | 绿 |
|---|---|---|---|
| **N1** rename 后引用者零联动 | renaming_a_referenced_file_rewrites_its_referrers_and_nothing_else | :152 盘上引用串未变 | PASS |
| **N3** 删除打开中场景复活 | deleting_an_open_scene_is_refused_and_forced_close_removes_it | :386 无 "open in a tab" 拒绝 | PASS |
| **Y8** rename 不 retarget tab | renaming_an_open_clean_scene_retargets_its_tab | :279 tab.path 仍旧 | PASS |

绿证 `loop/t05t1_green_final.log`：**10 passed; 0 failed**。其余 7 用例：文件夹前缀组件边界
（props vs props2 + note 字段 W10 断言）、脏 tab 保持脏且内存引用同步、W11 大小写、file.move
全联动（引用串/卡片 retarget/asset.save 落新路径/报告）、note_written 不弹 reload + 同路径
覆盖 reloaded 同 handle 换值（0.9）、W8 无副本、journal 新路径。

## 三、门禁（quick 四门亲跑 + 日志全文复核）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | 通过，无 Diff | t05t1_fmt.log |
| Lint | `cargo clippy --workspace -- -D warnings` | 通过，0 error/warning | t05t1_clippy_ws.log |
| 单测 | `cargo test --workspace --lib` | **1135+ 全绿**（含 asset_migration 迁移回归 13/13、reference_rewrite 模块 2/2） | t05t1_lib_full.log、t05t1_migration_regression.log |
| 相关集成 | guards 全量 | `-- --skip reference_rewrite`：**163 passed; 0 failed**（t05t1_guards_skip.log）+ `reference_rewrite::`：**10 passed; 0 failed**（t05t1_green_final.log），两日志合计覆盖全部 173 用例 | 同左 |

日志复核：对全部 t05t1_*.log 逐行扫 `error[/FAILED/Diff in/panicked`——最终门禁日志四份零命中；
check1-7/clippy1/diag* 为开发中间产物（编译错误/诊断），红/绿链日志如实保留；guards 运行中的
`PIE: cannot build` WARN 为环境噪音（pie 工具不在 PATH），非失败。

## 四、偏差（如实）

1. **guards 同进程并行全量失败 1 项（性能门，与本改动无关的负载问题）**：
   `session_journal::the_journal_write_costs_no_more_than_five_milliseconds` 在
   `cargo test --test guards` 全并行下两次失败（13.8ms vs 5ms 预算，guards_full/full2.log）；
   单独重跑通过（t05t1_journal_perf_rerun.log）；`-- --skip reference_rewrite` 的 163 用例
   全量通过（同测试 2.85ms/1.78ms）。归因：本任务新增 10 个重量级 editor-app 用例并行时
   抢占主线程使 journal emit 超帧预算——本任务的 src 改动不触碰该链路（session_journal.rs
   仅新增未被该测试调用的 `stashed_document`）。已按「重跑覆盖归档」标准以 skip 版+模块版
   两份绿日志覆盖；若 QA 认为必须同进程全绿，需要给该性能门加串行化或降载，超出本任务范围。
2. **N3 force 分支语义**：目标场景是**唯一打开 tab** 时 force 删除被拒绝（"open another
   scene first"）——tab strip 至少保留一个 tab 的既有设计，关闭它没有落点；已作为明确
   拒绝+说明而非静默处理，测试以两个 tab 场景覆盖主路径。
3. **migration 的 W10 误伤用例位置**：按验收原文以迁移既有 13 用例全绿（幂等保持）+
   guards rename 链的 note 字段断言（恰等旧路径串不被改）共同钉死，未在 lib 内另加
   migration 专属误伤用例（@ 前缀字符串在迁移语义中本就视为引用，属既有设计）。
4. 开发中一次 `rename_file` 的 rescan 放在 fs::rename 之后导致 referrers 表丢持有者
   （首绿 5/10），移到 rename 前修复；期间定位引入的临时诊断 println 已全部移除
   （clippy -D warnings 全过为证）。

## 五、验收清单对照（方案 T1 节 9 项）

1. headless 改名（W10 误伤断言 + 重载 path_of_id + metallic 不变）✓ 用例 1
2. 文件夹改名前缀恰一处 + props2 不误伤 ✓ 用例 2
3. Y8 干净 tab retarget + Ctrl+S 新路径旧文件不复活；脏 tab 保持脏内存同步 ✓ 用例 3/4
4. N3 非 force 拒绝说明 / force 关 tab 再删 ✓ 用例 5
5. W11 仅大小写 rename 盘上恰一文件内容不变 ✓ 用例 6
6. file.move 全联动（引用串/tab/卡片/报告）✓ 用例 7（卡片 retarget + asset.save）
7. 重导入回归（note_written 不弹 reload + 同路径覆盖同 handle 换值）✓ 用例 8
8. W8 drop 无副本 ✓ 用例 9
9. 迁移回归幂等（asset_migration 13/13）✓ lib 门
§五衔接 2 的 journal 补验：脏 tab → rename → journal entry 新路径 ✓ 用例 10

buglist：Y8/W8/W10/W11 已打 `- [x]` + `> 已修复 6ba0ce4b` 备注（本地文件，不入库）。

---

## 返工第 1 轮（QA PASS 后 review 的 2 🟡 + 1 ⚪，主控裁定合入前修）

提交 **69e44589** `Fix folder-move tab retarget and the all-tabs delete guard`（5 文件 +238/−14）。

1. **🟡① retarget_tabs 文件夹移动丢子路径后缀**：tab.path 的 retarget 由
   「一律设为文件夹新路径」改为按 `strip_prefix(old)` 保留 tail 拼接（对齐
   `migrate_index_entries`/`retarget_cards` 同族逻辑）；prefab cache 的 key 迁移与
   display_name 同步改用拼接后的新文件路径。**根因修复过程中发现并一并修掉一个
   Windows 平台障碍**：external_watch 对打开 tab 父文件夹持有 watch 句柄，rename/
   move 目录树会被系统拒绝（fs::rename 失败、联动链根本不执行）——新增
   `external_watch::release_watch_under`（unwatch 被移动树内的文件夹，tab strip 下一
   次变化自动在 tab 新路径重建 watch），`rename_file`/`move_file` 的目录分支在
   fs::rename 前调用。
   新用例 `renaming_a_folder_retargets_a_tab_under_it_onto_the_same_tail`
   （红 :745 → 绿）。
2. **🟡② close_open_holders 全部 tab 站在被删路径时失效**：判定由
   `tabs.len()==holding.len() && holding.len()==1` 收紧为
   `holding.len() == tabs.len()`（关闭后将无 tab 幸存，最后一个必被既有 close 系统
   静默拒绝、删除照常进行 = N3 复活洞）；拒绝文案改为
   "closing it would close the last open tab, so nothing was deleted; close it
   first"。
   新用例 `a_forced_delete_that_would_close_the_last_tab_is_refused`
   （双 tab 同目录树 force 删 → 拒绝 + 文件完好 + tab 不少；红 :820 → 绿）。
3. **⚪ twin 双扩展**：`replacement` 的 twin 分支由 `to + reference[dot..]`
   （会拼出 `x.bsn.bsb`）改为 `binary_twin(to)`（新路径自己的 twin 形态）；lib 新单测
   `a_twin_spelling_is_rewritten_as_the_new_paths_own_twin` 断言产出是
   `b/patinated.material.bsb` 而非 `b/patinated.material.bsn.bsb`。
4. 顺手：QA 点名的 tests/guards/reference_rewrite.rs 两处 `unused must_use`
   （:188 scene.close / :578 asset.save）改 `let _ =`；file_ops.rs 两处此前 UTF-8
   损坏的 em dash 注释字符修复。

**返工门禁（quick 四门，归档 t05t1_r1_*）**：fmt ✓；clippy --workspace -D warnings ✓
0 error；lib 全量 ✓（56 行 test result 全部 0 failed，含 reference_rewrite 模块
3/3——新增 twin 单测）；guards `--skip reference_rewrite` **163 passed / 0 failed**
（r1_guards_skip.log）+ `reference_rewrite::` **12 passed / 0 failed**
（r1_green_final.log），合计 175 用例全覆盖。红证：两新用例在修复前
（stash src）各 0 passed / 1 failed（r1_red1/r1_red2.log）。日志全文复核：最终门禁
日志零 error/FAILED；diag 系中间产物如实保留。
