# T07-T1 实施报告：staging 原子替换与目录防护

> 任务：`loop/plans/t07-export-reproducible.md` §二 T1（N1+Y7/R10+N4+N7，决策 1-A/2-A/5-A + 小定案）。
> 分支 `loop/t07-export`（自 main 54cd5ce6 拉出），提交 **ef353c57**
> `Make export staging atomic and guard the output directory`（3 文件，+810/−65）。未 push，未合入（待 QA）。

## 一、改动面

全部在 `crates/jackdaw_project_build/src/export.rs` + 两调用方少量接线（方案预估一致）：

| 项 | 实现 |
|---|---|
| **N1 🔴 原子替换** | `stage_export` 重写：normalize/护栏通过后，在 `dist.parent()` 下建 `.<profile>.staging-<pid>-<n>` 同级临时目录（同卷保证 rename 原子）→ `stage_into` 在其内完成 assets 拷贝→exe 拷贝→写标记（先 assets 后 exe 次序保留）→ `swap_into_place`：旧 dist 存在则 rename 为 `.<profile>.trash-<secs>-<n>`，staging rename 到 dist，删 trash（失败仅 `tracing::warn`+留给孤儿清理）；staging rename 失败则把 trash rename 回 dist（尽力恢复）。打包/交换任一步失败 → 删 staging、旧 dist 原样、错误上报。旧「先 remove_dir_all 再拷」路径删除 |
| **Y7 大小写绕过** | 新增 `path_contains(ancestor, descendant)`：Windows 按组件 `eq_ignore_ascii_case`（含盘符前缀），非 Windows 保持 `starts_with` 字节比较（`#[cfg]` 分开实现）；`staging_hazard` 的 ContainsSource/InsideSource 两处判定换用 |
| **R10 assets_dir** | `plan_export` 内部读 `ProjectManifest::read(root).assets_dir()` 作 `assets_source`（损坏 toml 已有回落 "assets"）；staged 目录名走新字段 `ExportPlan::assets_staged_subdir`（manifest 相对路径原样，`dist/content` 而非写死 `assets`）；签名不变、两调用方零改动（小定案执行） |
| **N4 名单过滤** | 决策 5-A 名单常量：目录 `SKIPPED_ASSET_DIRS = [".jackdaw-pie"]`（精确比较——Unix 上变体是不同目录，不能模糊），文件后缀 `.bak` / 含 `.tmp-` / 含 `.corrupt-`（`is_editor_private_file`）；命中计数进 `ExportReport.skipped`（目录计 1 条），CLI 成功输出在 skipped>0 时打印一行可审计说明 |
| **N7 --out 二道门** | 决策 2-A：导出成功在 dist 根写 `.jackdaw-export` 标记（内容=jackdaw VERSION+profile+unix 时间戳）；`stage_export` 发现目标**非空且无标记**（文件形态也视为非空）→ 新错误 `ForeignOutputDir`（文案点名 `--force` 与换 `--out` 两条出路）；`ExportPlan.force` 字段 + CLI `--force` 旗标（`parse_project_arg` 天然不当路径读取，已加断言）；编辑器入口不接 force（`plan_export` 默认 false，game_export.rs 零行为改动） |
| 孤儿清理 | 每次导出先清 parent 下本 profile 的 `.*.staging-*`/`.*.trash-` **目录**（非目录异物不删——unique_dir 遇文件占名会撞上并响亮报错，不静默绕过；其他 profile 的不误删），对齐 T04 启动清孤儿族 |
| 配套 | 模块/函数 doc 全面改写为新语义（staging 布局含标记图示）；`ExportReport` 构造点（game_export.rs 测试×2）补 `skipped`；错误文案中的 "clear" 措辞更新为 "replace/move" |

## 二、红→绿（方案 QA 清单要求：N1、Y7 真红证）

红证跑在**未改动基线**上（测试只用既有 API，保证可编译）：`loop/t07t1_red_run1.log`
—— **4 红 / 13 绿**。四条红的失败形态各自实证旧缺陷：

| 用例 | 注入 | 红形态（旧代码实跑日志） |
|---|---|---|
| `a_case_variant_of_the_output_directory_cannot_bypass_the_guard`（Y7） | `--out` 与 root 仅最后一段大小写不同 | **变体被接受**，随后真 assets 已被删（`could not read ...assets: 系统找不到指定的路径`）——字节比较放行+删源的铁证 |
| `a_locked_executable_source_keeps_the_previous_export_intact`（N1 打包中） | `share_mode(0)` 锁 exe 源 | exe 拷贝失败时旧 dist **已被清空**：digest 仅剩 2 个 assets 文件、`my-game.exe` 没了——「先清空后拷」不保旧的铁证 |
| `a_locked_previous_export_refuses_the_swap_and_stays_intact`（N1 交换中） | `share_mode(1\|2)`（无 DELETE share）锁旧 dist 内 exe | 旧代码报 `could not clear the existing staging directory ... 另一个程序正在使用此文件`——clear 语义且有部分删除风险；新代码必须报 `move the previous export`（文案断言保证红性确定）且 digest 逐字节完好 |
| `a_failure_while_staging_keeps_the_previous_export_intact`（N1 打包中，跨平台） | 预放文件挡 staging 目录名（save.rs blocked-parent 同族） | 旧代码无 staging 机制，注入无效、导出**成功**（`unwrap_err() on an Ok value`） |

实现后同套测试 `loop/t07t1_green_final.log`：**export 模块 25/25 绿**（17→25，新增 8 用例），红→绿 **4→0**。

注入可行性先行探针（PowerShell，`H:\workspace_AI\t07t1_probe*.ps1`）：无 DELETE share 句柄**阻止父目录 rename**（无论 share 模式如何）；readonly 子文件不阻止父 rename。

## 三、验收清单逐项（方案 T1 节全项）

| 验收项 | 证据（export.rs tests，全绿） |
|---|---|
| N1 红→绿：注入 staging 失败 → Err + 旧 dist 每文件逐字节不变（SHA 清单=tree_digest 相对路径+全字节） | 上表 4 用例（打包 create / exe 拷贝 / 交换第一步 / 大小写变体） |
| Y7 红证：大小写变体拒收且源树零损伤 | `a_case_variant_...`（拒收 + scene.bsn/binary 完好）；另 `path_containment_matches_the_filesystems_case_rules` 钉纯函数矩阵（同径异拼/相等/不同/反向/跨盘） |
| R10：`assets_dir = "content"` fixture → 导出成功且 `dist/content/` 与源一致；无配置 → `dist/assets/` 回归 | `an_assets_dir_override_is_staged_under_its_own_name`（含 `plan.assets_source == root.join("content")`、无幻影 assets）；`staging_copies_...`（默认 assets 布局）与 `the_default_staging_directory...`（plan 断言）维持绿 |
| N4：`.bak`/`.jackdaw-pie/`/`.tmp-` 不进包 + skipped 计数 | `editor_private_files_stay_out_of_the_export`：预置 4 类（验收三件套 + `.corrupt-` 同规则第 4 件）全部不在 dist，`skipped == 4`，正常资产全在 |
| N7 三态+force：非空无标记拒（目录原样）/标记放行/空目录放行/force 放行 | `an_output_directory_that_is_not_ours_is_refused_until_forced` 四段全断言（拒时 important.txt 逐字节原样；标记放行后整目录替换；CLI `--force` 解析断言在 cli crate） |
| 成功路径回归：staging 与 .trash 清理 + 孤儿清除 | `a_successful_export_leaves_no_staging_or_trash_behind`（parent 无任何本 profile staging/trash 残留）；`staging_and_trash_leftovers_are_cleaned_on_the_next_export`（预置 `.release.staging-999`/`.release.trash-old` 被清，`.dev.staging-1` 不误删） |
| 幂等：连续两次导出 dist 清单+逐字节一致 | `repeated_exports_stage_identical_content`（tree_digest 排除含时间戳的标记文件——布局与内容必须一致，标记时间允许变） |
| 标记文件内容 | `the_export_marker_names_the_version_and_profile`（VERSION/profile/at） |

## 四、门禁（quick 四门，2026-10-25 证据标准：日志全文复核）

| 门 | 命令 | 结果 | 日志（已归档 loop/） |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **clean**（空 diff） | `t07t1_fmt.log` |
| Lint | `cargo clippy --workspace -- -D warnings` | **exit 0**；全文复核无 error、无本改动引入的 warning（仅 4 条既有 build-script linker stderr 警告，与改动无关，历轮日志同在） | `t07t1_clippy.log` |
| 单测 | `cargo test -p jackdaw_project_build --lib` / `-p jackdaw_cli_internal --lib` / `-p jackdaw --lib` | **219 / 18 / 1167 全绿 0 failed**（lib 日志中一条 `ERROR jackdaw::pie ... E0560` 为 game_export 失败路径测试注入的样本输出，非故障） | `t07t1_green_final.log` / `t07t1_cli.log` / `t07t1_lib.log` |
| 任务相关集成 | `cargo test --test guards` | **197 绿 0 failed** | `t07t1_guards.log` |

红证日志 `loop/t07t1_red_run1.log`。被改 crate（jackdaw_project_build / jackdaw_cli_internal）无自有集成测试目录；tests/ 无 export 集成文件（heavy smoke 属 T3，方案 §0 已记）。

## 五、buglist 台账

- **R10**：打 `- [x]` + `> 已修复 ef353c57（T07-T1）` 备注（manifest 内部读、staged 目录名跟随、签名不变）。
- **Y7**：打 `- [x]` + `> 已修复 ef353c57（T07-T1）` 备注（path_contains、红证形态）。
- **W9**：核对原文——已由 T04-T1 打钩（`> 已修复 160893e6` 备注完整），本任务无动作，符合方案预期。
- R9（Build 面板空白）不在本任务（T2 处理）。

## 六、偏差与记档（3 项，均已论证或有兜底）

1. **「删 trash 中断」OS 级注入不可达（Windows）**——双探针论证：(a) 旧 dist 内任何打开句柄（有无 FILE_SHARE_DELETE 均同）都阻止「rename 到 trash」这一步，锁必然先命中交换第一步而非删除；(b) readonly 文件已不再阻止现代 std 的 `remove_dir_all`（实测 trash 被完整删除）。故 warn+留置分支为防御代码，其用户可见语义（残留 trash 由下次导出清掉）由孤儿清理测试钉住；「旧产物逐字节完好」的保证由 N1 三个可注入失败点共同覆盖。
2. **swap 第二步（staging→dist rename）失败的恢复分支无注入点**（目标位置刚被第一步腾空，同卷 rename 无现实失败面）——防御代码，代码审查覆盖；「交换中失败」由第一步 rename 注入覆盖（验收句满足）。
3. **skipped == 4 而非方案验收句的 ==3**：同一用例多覆盖 `.corrupt-` 类（名单第 4 成员），验收三件套（.bak/.jackdaw-pie/.tmp-）逐条断言均在内，计数语义（每命中条目计 1）与方案一致。

另：工作区遗留的 `.gitignore`（`+.mimosa/`）为环境工具改动，与本任务无关，未带入提交。

## 七、交接 QA 的注意点

- 行为变更锚点：`jd export` 成功输出在 skipped>0 时多一行；`--force` 新旗标；旧「先清空」错误文案（`clear the existing staging directory`）变为 `move the previous export ...`/`create the staging directory ...`——若有测试或脚本 grep 旧文案需同步（本任务已全库跑绿，无残留引用）。
- 编辑器入口零行为变化（force 默认 false；默认 dist 首次为父目录下新建、复导出有标记，均天然过门）。
- 真机矩阵（方案 T3 #1-#10）中 #2/#3/#5/#6/#7/#9 的 headless 腿已由本任务测试覆盖，真机腿待 T3。
