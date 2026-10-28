# T05-T3 实施报告：真机验收矩阵 + 工具镜像 + 文档收尾

- 分支 `loop/t05-final`（自 main a034595b 拉出），提交 **396073fa** `Add the audit MCP tool and close out reference stability`（10 文件 +189/−10；开局/提交前后 `git branch --show-current` 自检通过）
- 规格：`loop/plans/t05-reference-stability.md` §二 T3

## 一、改动逐项

1. **MCP 镜像**：`crates/jackdaw_mcp` 第 23 个工具 `audit`（recovery 同款薄翻译 `jackdaw/audit`，description 里带 `asset.missing_list`/`asset.rebind` 的调用指引）；`tests/mcp_smoke.rs` 的 tools/list 锁定表补 `recovery`（此前漏锁）与 `audit` 两行。
2. **真机验收矩阵**（脚本 `loop/qa/t05-final-live.ps1`，fixture bevy pin 已用 main+rev；截图留档 `loop/reports/t05t3-live/`，日志 `loop/reports/t05t3_grid*.log` + editor log）——矩阵过程暴露并修复了三个真机才可见的缺口（见「矩阵过程修复」）。
3. **book 文档**：新 `book/src/user-guide/asset-references.md`「Asset References」节（路径即身份、哪些字段算引用、rename/move 的完整联动语义与状态栏报告、删除确认/force 语义、Missing 清单四按钮、外部改名「编辑器内做或改完跑 audit」的指引），SUMMARY 挂 User Guide 下。
4. **buglist 核对**：Y8/W8/W10/W11/W12/Y31/W7 七条全部 `- [x]` + `> 已修复 <commit>` 备注与实际证据一致（逐条 findstr 核对，无漏）。

## 二、矩阵 10 格结果（全 BRP 驱动，PASS 行原文留档 t05t3_grid*.log）

| # | 场景 | 结果 | 证据 |
|---|---|---|---|
| 1 | 材质改名（被引用） | **PASS**（盘上引用串已新+旧路径不存在） | grid123f.log（先经一轮 IsA.source 重写盲区修复，见下） |
| 2 | 材质 file.move 到另一目录 | **PASS**（引用串随 move） | grid123f.log |
| 3 | 文件夹改名（前缀重写） | **PASS**（props→prop 前缀重写+盘上目录移动；先经 prefab-watcher 句柄修复） | grid123f.log |
| 4 | 打开中场景改名（Y8 终验） | **PASS（真机抽验）**：tab retarget 新路径+save 只落新路径（旧不存在）；全量=headless guards `renaming_an_open_clean_scene_retargets_its_tab` 12/12 | grid4579b.log |
| 5 | 仅大小写改名 | **PASS（真机抽验）**：UNO.bsn 恰一文件；全量=headless `a_rename_that_differs_only_in_case_lands` | grid4579b.log |
| 6 | 删除被引材质非 force | **PASS**：文件原样+确认框描述 "1 document references keeper.material.bsn: zones/four.bsn. Delete it anyway?" | grid6b.log（对话框经 dialog.answer Cancel 收口） |
| 7 | 删除打开中场景 非force/force | **PASS（真机抽验）**：非 force 文件完好；force 删除+无 tab 残留；全量=headless `deleting_an_open_scene_is_refused_and_forced_close_removes_it` | grid4579b.log |
| 8 | 缺失定位重绑（T2 链复跑） | **PASS**：audit Missing→`asset.rebind`→盘上新串→audit 清空 | grid8b.log（先经干净 tab audit 口径修复） |
| 9 | 拖自家文件入窗 | **PASS（真机抽验）**：全程无 `-1` 副本；全量=headless `dropping_a_file_already_in_the_assets_copies_nothing` | grid4579b.log |
| 10 | 重导入 | **PASS**：外部覆盖材质后 audit 仍清（同 handle 换值链） | grid10b.log |

**10/10 全过**；4/5/7/9 按方案允许的组合证据（真机抽验 + headless 既有用例全量），1/2/3/6/8/10 真机全跑。

## 三、矩阵过程暴露并修复的三个缺口（本轮代码改动的主体）

1. **`IsA.source` 在 rename/move 重写侧无特判**（grid 1 红出）：T1 的 scan 侧与 T2 的 audit 侧都有 `ISA_TYPE && field=="source"` 特判，但 `reference_rewrite::rewrite_value` 没有——重写只认 takes_asset_path 类型或 `@` 串，String 类型的 source 字段被跳过。修：`rewrite_struct` 传 `is_source` 标志（与 scan 同一判定），prefab 实例的 source 在 rename/move 后随动。矩阵 grid 1/2 由红转绿的直接原因。
2. **prefab watcher 句柄挡住文件夹 rename**（grid 3 红出）：`props/a` 被 prefab watcher（watch 实例源文件的文件夹）持有，Windows 拒绝 rename props。修：`prefab::watcher::release_watch_under`（T1 R1 为 open-tab watcher 做的同款释放，重建剩余 watch），rename/move 目录前两处都调。
3. **干净 tab 的缓存快照污染 audit**（grid 8 红出）：打开的 prefab tab 的 cache 快照持有旧引用（盘上已被 rename 重写，tab 未重开），audit 以内存态替代盘上文档时报已修复的引用为 Missing。修：`open_tab_documents` 只代入 **dirty** tab 的内存文档——干净 tab 的文档就是盘上文件（rename/move 已重写），prefab 快照在重开前不冒充。

## 四、全量门（2026-10-25 升级标准：日志全文复核 + 重跑覆盖归档）

| 门 | 结果 | 归档 |
|---|---|---|
| fmt --check | ✓ 零 Diff | t05t3_fmt.log |
| clippy --workspace -D warnings | ✓ 0 error（初跑 guards 有 1 个 backticks 文档 lint，修复后归档覆盖） | t05t3_clippy.log |
| cargo test --workspace --lib | ✓ 56 行 test result 全 0 failed | t05t3_lib.log |
| guards | `reference_rewrite::` **12/12** + `reference_audit::` **5/5** + 其余 **162/162** + session_journal 性能门单跑 **1/1**（1.0ms，并行超标为既有现象，分治覆盖）= 180 全覆盖 | t05t3_g_*.log |
| xtask fast | ✓（含 fmt/clippy/lib/关键集成，nextest） | t05t3_xtask_fast2.log |
| xtask integration | ✓ | t05t3_xtask_integration.log |
| xtask docs | ✓（新 book 节构建通过） | t05t3_xtask_docs.log |
| workspace doctests | **分治**：--no-fail-fast 55 段中 52 段显式 ok、0 段 failed>0；`jackdaw_bind` 的 merged-doctest harness 返回非零但无任何失败测试行——**stash 实证在 main（a034595b）同样失败**（既有环境问题，非本轮引入；本轮未触碰该 crate），bind 单独跑 **3/3 绿** | t05t3_doctests4.log / t05t3_docbind2/3.log / t05t3_docbind_main.log |

日志复核：门禁日志的 error/FAILED 命中行逐条核对为 PIE 环境噪音（WARN 内嵌 cargo 文本）或上述 bind 既有项；三处初跑失败（grid 1/3/8、fast 的 backticks、doctests 第一次）全部修复/分治后以覆盖归档收口。

## 五、用户 30 秒清单（写在报告文末，供 final-qa 抽查）

1. **给材质改名**：在 Project 窗口右键一个被场景引用的材质 → Rename → 打开引用它的场景 → 一切照旧（状态栏会报告 "renamed; rewrote N references in M documents"）。
2. **删一个被引用的材质**：右键 → Delete → 确认框告诉你谁在用它（文档名清单），选 Delete anyway 才真删。
3. **删掉一个纹理文件重开场景**：右键该场景 → Missing References… → 清单里找到它 → 点 Rebind 选一个现存文件 → 保存场景。

## 六、偏差

1. doctests 的 jackdaw_bind merged-harness 失败为 main 上已实证的既有环境问题（分治覆盖：bind solo 3/3 + 其余 52 段 ok），不阻塞。
2. 矩阵三处修复属于 T3「验收暴露即修」的性质（grid 红→修复→绿的完整链路在 t05t3_grid*.log 序列中可见），无未修复残留。
3. mcp_smoke 的 E2E 用例本身需要窗口服务器，本机按其内建条件跳过逻辑运行（tools/list 锁定是其静态部分，随 fast/integration 覆盖编译）；与历轮一致。
