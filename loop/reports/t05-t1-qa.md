# T05-T1 QA 验收报告：改名/移动/删除的引用联动与 tab retarget

- 角色：QA（只验不修）｜日期 2026-10-25｜工作目录 `E:\Project\rust\jackdaw`，分支 `loop/t05-references`，提交 **6ba0ce4b**（10 文件 +1945/−135，`git show --stat` 亲核一致）
- 输入：`loop/README.md`（含 2026-10-25 门禁证据标准：日志全文复核为主、exit code 辅助、重跑覆盖归档）、`loop/plans/t05-reference-stability.md` §二 T1（验收 9 项）+ §三裁决、`loop/reports/t05-t1-report.md`、`loop/qa/manual.md`
- 门禁日志归档：`loop/reports/gate-*-t05t1qa.log`（8 份，脚本 `loop/reports/t05t1qa-gates.cmd`，2026-10-25 22:58–23:01 亲跑）

---

## 一、门禁独立复核（quick 四门亲跑 + 加强门）

| 门 | 命令 | EXIT | 日志全文复核 | 判定 |
|---|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | 0 | gate-fmt-t05t1qa.log 仅 1 行 EXIT，无 Diff | ✅ |
| Lint（契约版） | `cargo clippy --workspace -- -D warnings` | 0 | 17 行全文复核：无 error，仅既有 build script linker warning（`linker_messages` lint 自述忽略 -D warnings） | ✅ |
| 单测 | `cargo test --workspace --lib` | 0 | 3493 行全文复核：无 FAILED/error:/panicked；`asset_migration::tests` **13/13**（含 `a_second_run_has_nothing_to_do`、`a_reference_that_already_spells_its_file_is_left_as_it_is` 幂等双钉）、`reference_rewrite::tests` 2/2 | ✅ |
| 相关集成（guards 全量，含新测试） | `cargo test --test guards` | 101 | **172 passed; 1 failed**（唯一失败 = `session_journal::the_journal_write_costs_no_more_than_five_milliseconds`，12.08ms vs 5ms，见 §三偏差#1；PIE cannot build 为既有环境噪音） | ✅\*（唯一失败为偏差#1 环境性，裁定见 §三） |
| （补充）guards reference_rewrite 单跑 | `cargo test --test guards reference_rewrite` | 0 | **10 passed; 0 failed**（绿终态亲跑） | ✅ |
| （补充）journal 性能门单独 ×2 | 同名过滤 | 0 / 0 | 两次均 1 passed（1.46s / 1.49s） | ✅ |
| （加强门，非契约） | `cargo clippy --workspace --all-targets -- -D warnings` | 101 | 2 error 在**本任务新增** `tests/guards/reference_rewrite.rs:188/:578`（unused `OperatorResult`）；1 error 在既有 `tests/reflect_auto_register.rs:1`（本提交未改该文件，历史遗留） | ⚪ 记录（见 review ⚪-2），不拦放行 |

- 程序自述数字核对：绿 10/10（t05t1_green_final.log）、skip 版 163/163（t05t1_guards_skip.log）、全量 172+1（guards_full/full2.log）——三份归档日志与报告一致；**唯一不精确处**：报告称 journal 门两次失败均为 13.8ms，实测 full=7.72ms、full2=13.84ms（一次 7.7ms）。
- 覆盖完备性：173 用例（163 skip 版 + 10 模块版两份绿日志合计）+ QA 全量一次，无重复无遗漏，符合「重跑覆盖归档」标准。

## 二、红→绿真实性

- **红证方法有效性**：`git stash push -- src` 只回退 src 下已跟踪文件到 HEAD（旧实现），未跟踪的 `src/reference_rewrite.rs` 留在工作区但旧 `lib.rs` 无 `mod` 声明故**不参与编译**；新测试文件 `tests/guards/reference_rewrite.rs` 未被 stash（use 列表亲核：仅 `run_op_clause`/`Scenes`/`OperatorReports`/`OperatorWarnings` 等旧有 API，**不引用新模块符号**）→ 旧 src + 新测试可编译。方法成立。
- **红轮形态**（t05t1_red_run.log 亲读）：`Finished test profile in 1m 20s` 后 `running 10 tests` → **`0 passed; 10 failed`**，失败全部为断言 panic 非编译失败，且失败信息直指旧行为缺失的铁证：`the move runs: UnknownId("file.move")`（旧代码无该 operator）、`no copy ... left: ["moss-1.png","moss.png"]`（W8 旧行为）、`the refusal says the file is open in a tab: []`（N3 旧无守卫）、`the reference follows the file: ...rust.material.bsn`（N1 零联动）。**真红成立**。
- **绿终态亲跑**：`cargo test --test guards reference_rewrite` 10/10（gate-guards-refrewrite-t05t1qa.log，EXIT 0）。

## 三、偏差#1 裁定（重点：journal 5ms 性能门）

独立复现数据（QA 亲跑）：
- guards **全量**（含新 10 用例，全并行）：`12.0773ms` FAIL —— 与程序两次（7.72/13.84ms）合计 **全量并行下 3/3 超标**；
- **单独**跑该门 2 次：均 1 passed（程序 rerun 亦过：2.85ms/1.78ms）——单独 **5/5 过**（程序 1 次 + QA 2 次 + skip 全量中 2 次）。

裁定：**并行负载归因成立**。本任务新增 10 个重量级 editor-app 用例与之并行时挤兑主线程/IO，使 journal emit 超帧预算；本任务 src 侧不触碰该链路（session_journal.rs 本提交仅新增 `stashed_document` 纯辅助函数，未被该测试调用，亲核 diff）。属**测试基建问题**（毫秒级性能门对重量级用例并行不可靠），非本任务功能缺陷，**不因环境性波动 FAIL 本任务**。

🟡 处置建议（可执行，建议归 T05-T2 或独立小任务）：①给该性能门串行化——cargo-nextest profile 将 `session_journal::*` 性能门放入 threads=1 组（或 guards 拆两个 target：重负载组 + 性能门组）；或②该门改多次采样取中位数再判 5ms；或③至少把 5ms 预算对并行环境的方差留出（如 5ms 单跑 / 15ms 并行双阈值）。若不治理，后续每增重量级 guards 用例该门会愈常红，侵蚀门禁信号。

## 四、代码 review（git show 6ba0ce4b 逐文件）

### 🟡 中等（2）

- **🟡-1 `retarget_tabs` 文件夹场景丢失子路径后缀**（`src/reference_rewrite.rs:511` `tab.path = Some(new_canonical.clone())`；prefab 分支 :556 同）：文件夹 rename/move 时，`stands_on`（:617-622）会命中「站在 old 下」的所有 tab，但 tab.path 被无条件指到 **new 根目录**而非 `new + 原相对后缀`。同函数族内 `migrate_index_entries`（:642-644 `new.join(was.strip_prefix(old))`）与 `retarget_cards`（:671-676 同构拼接）都正确保留后缀，唯 tab 分支不一致。后果：文件夹改名后其下已打开场景的 tab.path 指向目录，下次保存落空/异常（Y8 语义在文件夹维度未闭合）。guards 未覆盖「文件夹 rename + 打开 tab」组合（文件夹用例无 tab、tab 用例非文件夹）。建议：仿 retarget_cards 按后缀拼接，并补组合用例。触发面窄于原 Y8，未构成 🔴。
- **🟡-2 `close_open_holders` 守卫条件过窄，N3 复活洞在「全部 tab 均持有」组合重开**（`src/file_ops.rs` close_open_holders）：守卫仅拒 `tabs.len()==holding.len()==1`。当 tabs.len()=N≥2 且**全部** tab 都站在被删路径（force 删目录、目录下场景全开）时，rev 循环关闭至只剩 1 个时被 `scene_close_system_unprompted` 的 `tab_count <= 1` 静默拒绝（`src/scenes/operators.rs:629-632`），函数仍返回 true → 删除继续 → 残留唯一 tab 指向已删文件，Ctrl+S 复活（N3 同族）。建议：守卫推广为 `holding.len() == tabs.len()`，或关闭后复查仍有 tab 站在 path 上则拒绝删除。

### ⚪ 轻微（5）

- **⚪-1 `replacement` twin 分支产双扩展**（`src/reference_rewrite.rs:196-199`）：`ReferenceMove::Names` 唯一构造点 follow_a_move 传入的 `to` 恒为**含扩展**新路径，twin 命中（引用串 `.bsb` 拼写、目标 `.bsn`）时 `format!("{to}{}", &reference[dot..])` 为追加而非替换扩展 → 产出 `x.bsn.bsb` 断链串。触发面窄（仅 .bsn 被 .bsb 拼写引用的遗留文档 + rename），guards 无 twin 用例（模块单测只测 `is_twin_spelling` 谓词本身）。建议改 `to` 按引用串扩展 `with_extension` 并补 twin 用例。
- **⚪-2 新测试文件 2 处 unused `OperatorResult`**（`tests/guards/reference_rewrite.rs:188/:578`，即 clippy --all-targets 加强门 2 个 error）：契约 clippy 门不含 tests target 故未拦。红证日志亦见同位 warning，说明开发期已存在。建议补 `.assert_finished()` 消费或 `let _ =`。
- **⚪-3 W11 中转名未被孤儿清理族认领**：`rename_through_a_middleman` 产物 `.{name}.case-{pid}-{n}`，而 `sweep_orphan_temp_files`（`crates/jackdaw_api_internal/src/document.rs:190-203`）只认 `.<name>.tmp-<pid>` 形态——方案 §四风险表承诺「中转名进 T04-T1 的孤儿 tmp 清理族」实际未进。两步之间崩溃窗口极窄且回滚已尽力，风险低，但与方案文本不符，备案。
- **⚪-4 `file.move` 的占用检查无大小写特判**（`target.exists()` 误判，W11 同族在 move 侧未做 canonicalize 判定）：NTFS 下移入仅大小写不同同名文件的目录会误拒。触发窄。
- **⚪-5 `references_of_tab` 每 tab deep_clone / 活动场景 emit+parse 全量**：删除确认对话框构造时一次性开销随 tab 数与场景规模线性放大；方案风险评估已预判（千节点毫秒级），当前可接受，留意大场景。

### ✅ 正向核实

- **AST patch 值替换（W10 本体）扎实**：`rewrite_value`（:328-337）先判 `takes_asset_path || starts_with('@')` 不符即 return，非资产 String 恰等路径串不动；guards 用例 1/2 的 note 字段断言直接钉死。
- **三种匹配齐备**：整串（Spelled/Names 精确）、`@stem` 裸名（`names_by_stem` 要求 `stems().unique()` 命中同一路径，歧义 stem 不动）、目录前缀按组件边界（`folder_tail` 以 `path + "/"` strip，`props2`/`propsurement` 均不触，模块单测 4 断言 + `Path::starts_with` 组件级语义双保险）。
- **twin/形态**：`rewrite_documents` 经 `existing_form` 尊重文档自身 .bsb/.bsn 形态（`:Base` 引用亦入扫描与重写）。
- **文件夹重写去重**：holders 走 `BTreeSet`，测试断言 `matches == 1` 恰一处。
- **rescan 时序（偏差#4 修复态）**：`rename_file` 与 `move_file` 两处 rescan 均在 `fs::rename` **之前**，注释论证一致（旧路径消失后引用不再解析、referrers 表丢持有者）。
- **rename/move 无分叉**：两者共走 `follow_a_move`（盘上重写→tab/卡片 retarget→index 挪键保 handle→rescan→干净 tab 基线重算→journal write_snapshot→报告+状态栏）；`migrate_index_entries` 保 handle 挪键 + 借 rename 不改 mtime 让 rescan 不重载，设计干净。
- **干净/脏两态**（裁决 5）：`recompute_clean_baselines` 活动tab 用 `document_fingerprint`、非活动用新 `session_journal::stashed_document`，dirty/refused 跳过保持脏——与用例 3/4 断言互证。
- **W8 一行守卫**（canonicalize + starts_with(assets)→跳过导入转 select）不破坏外部文件正常导入复制路径；**note_written 双登记**防 watcher 误报由用例 8 `prompts==0` 钉死；**迁移改道**：旧 `String::replace` 文本替换实现整体删除无死代码，`target==reference` 不产 move 保幂等（13/13 含 `a_second_run_has_nothing_to_do`）。

## 五、验收 9 项清单对照（方案 §二 T1）

| # | 方案验收项 | 证据 | 判定 |
|---|---|---|---|
| 1 | 改名：引用串更新 + W10 非资产字段不误改 + 重载 path_of_id 新路径 + metallic 不变 | guards 用例 1（:156-210 四段断言 + 报告行 + `indexed_path`） | 直接用例 ✅ |
| 2 | 文件夹改名前缀**各恰一处** + props vs props2 | guards 用例 2（`matches==1` ×2 文档、props2 两字段 2 处不动）+ 模块单测 folder_tail | 直接用例 ✅ |
| 3 | Y8：干净 tab retarget + Ctrl+S 新路径**旧文件不复活**；脏 tab 保持脏内存同步；卡片同链 retarget | 用例 3（save 落新路径且旧路径 `!exists`）+ 用例 4（脏保持+save 写新引用）；**卡片 retarget 无 rename 链直接用例**，由用例 7（move 链卡片+asset.save）+ follow_a_move 同链代码组合证明 | 组合证据 ✅（rename 链卡片直测留 T3 矩阵） |
| 4 | N3：非 force 拒绝+描述；force 关 tab 再删、无 tab 可写回 | guards 用例 5（"is open in a tab"、force 后 tabs=1、无 tab 站旧文件） | 直接用例 ✅ |
| 5 | W11 仅大小写：恰一文件、内容不变 | guards 用例 6（`eq_ignore_ascii_case` 计数==1、bytes 逐位相等）；方案举例含大小写两个方向，用例只测单向（canonicalize 判定两向同路，语义等价） | 直接用例 ✅ |
| 6 | file.move 全联动（引用串/tab/卡片/报告） | guards 用例 7（盘上引用、`moved`+`rewrote` 报告、卡片 path、asset.save 落新路径；tab 走同链） | 直接用例 ✅ |
| 7 | 重导入回归：note_written 不弹 reload + 同路径覆盖同 handle 换值 | guards 用例 8（0.9 换值 + `ExternalSceneChanges.prompts==0`） | 直接用例 ✅ |
| 8 | W8：drop assets 内文件无 `xxx-1.ext` | guards 用例 9（`pngs == ["moss.png"]`） | 直接用例 ✅ |
| 9 | 迁移回归幂等（13 用例） | lib 门 `asset_migration` 13/13（幂等双用例在内） | 直接用例 ✅ |
| 补 | §五衔接 2：脏 tab→rename→journal 新路径 | guards 用例 10 | 直接用例 ✅ |

**遗漏项**：无方案验收项落空。特别核对项确认：前缀「各恰一处」断言在（用例 2 :269-283）；note_written 不弹 reload 在（用例 8 :619-630）；W8 无副本断言在（用例 9 :661-665）。

## 六、buglist 核对

`buglist.md`（本地未跟踪，UTF-8 亲读）：Y8（:121 `- [x]`，:125 备注）、W8（:315/:319）、W10（:326/:329）、W11（:331/:334）——四条均打钩 + `> 已修复 6ba0ce4b（T05-T1）` 备注含 guards 用例名；**W10 备注确按偏差#3 的组合口径**（迁移 13 用例 + guards note 字段断言），与实际证据一致。✅

## 七、偏差 4 条逐条裁定

1. **journal 性能门并行超标**：**成立，不拦放行**（详见 §三）：全量并行 3/3 超标（7.72/13.84/12.08ms）、单独 5/5 过；归因测试基建（重量级用例并行挤兑），非本任务 src 缺陷；🟡 处置建议已给（nextest 串行化/采样中位数/双阈值）。
2. **唯一打开 tab 时 force 删除被拒**：**成立且合理，非本任务新造行为**。既有设计证据：`src/scenes/operators.rs:629-632`（`scene_close_system_unprompted`：`if tab_count <= 1 { info!("scene.close: cannot close the last open tab"); return; }`）与 :593-600（`scene_close_system` 同守卫，doc 注释 "Blocks closing the last open tab"）——本提交未触碰该文件（git show 文件清单可证）。明确拒绝 + "open another scene first" 优于静默。连带发现 🟡-2（守卫推广遗漏）。
3. **W10 误伤用例位置**：**可接受**。验收原文第 9 项仅要求迁移 13 用例全绿（幂等保持），已满足；W10 的「误伤不发生」本体由 guards 用例 1（:164-167 note 断言）+ 用例 2（:274-277）对新重写器直接钉死，迁移走同一 `rewrite_document`。`@` 前缀串在迁移语义中视为引用属既有设计，备注如实。无需返工。
4. **rescan 时序（曾在 rename 后，已移前）**：**成立，修复态已核**。rename_file 与 move_file 两处 rescan 均在 fs::rename 前 + 注释论证；临时诊断 println 无残留（契约 clippy -D warnings 0 error 为证；check1-8/clippy1/diag* 为开发中间产物日志，红/绿链如实归档，与「重跑覆盖」标准不冲突——最终门禁日志四份 QA 已亲跑覆盖）。

## 八、结论

- PASS 条件逐项：四门过（✅，guards 全量唯一失败为偏差#1 环境性且 173 用例有 skip+模块两份绿日志 + QA 全量复现三方印证）；红→绿真实（✅）；9 项验收全有证据（✅，8 直接 + 1 组合）；review 无新 🔴（✅，🟡×2 + ⚪×5）；偏差#1 裁定有结论（✅）。
- 🟡×2（retarget_tabs 文件夹后缀、close_open_holders 守卫推广）建议并入 T05-T2/T3 或下轮小修，不阻塞本任务；⚪×5 备案。
- 残留进程检查：无 jackdaw/cargo/rustc 残留。

VERDICT: PASS
