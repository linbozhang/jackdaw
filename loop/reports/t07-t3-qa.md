# T07-T3 QA 终验报告：「异目录回归+工具面+收尾」（兼 T07 整体与 P0 收官判定）

> QA 角色产出，2026-10-24。分支 `loop/t07-final`，提交 `7eae91a9`（父 `5eae7988` = main），
> 14 文件 +693/−24。程序报告：`loop/reports/t07-t3-report.md`（§四偏差已逐条裁定）。
> 本报告兼 T07 整体（T1 `ef353c57` / T2 `9a80bcbc` / T3 `7eae91a9`）与 P0 收官判定。
> 纪律：buglist/loop 文本一律 findstr/Read（字节安全）；长命令后台+轮询。

## 一、heavy smoke 亲跑

`cargo test --test export` → **1 passed / 0 failed**（`an_exported_game_runs_from_a_moved_directory`；
编译 1m07s+测试 9.57s 热缓存——程序冷跑 82.68s 含首次构建，同测同绿）。断言链在测试内完整：
布局（exe+assets+marker+manifest）→ 过滤（预植 `.jackdaw-pie/`+`.bak` → skipped==2 且不在 dist）
→ manifest（`manifest_for` 重算与落盘一致）→ **dist 整体复制深层异目录 → staged exe cwd=新目录
跑 `--jackdaw-extract-schema` → exit 0+schema 可解析**——验收句④「挪盘可玩」的机制铁证。
**D6 双登记核实**：`xtask/src/main.rs:74`（`SDK_BINARIES` 排除串 `binary(export)`）+ `:234`
（heavy() 显式 `--test export` 列表）。

## 二、manifest（「可复现构建」验收句证据物）：断言实质，非空洞

- `the_manifest_lists_every_file_and_repeats_identically_except_time`（QA 亲跑过，32 匹配全绿）：
  逐字段（profile/jackdaw/bevy_rev）+ **files 路径数组精确排序**（排除 marker/manifest 自身）+
  sha256 64hex + size 精确；**幂等=strip_time 后两次导出 manifest 全等**（同输入同输出的直接证据）；
- `a_tampered_export_disagrees_with_its_manifest`：篡改 staged scene → **真实重算哈希与 shipped
  失配**（非字面量比较）——篡改可检出。

## 三、BRP/MCP 工具面

- `jackdaw/export` 三态 headless 亲跑：`the_export_face_reports_idle_ready_failed_and_building`
  **1/0**（idle/ready 含 dist+manifest+files+skipped+profile+started_unix/failed 含 outcome）；
- MCP **25 工具名单锁**：`tests/mcp_smoke.rs` 数组含 `export`（新）与 `pie`（**T06 遗漏本轮补锁**），
  逐工具 `contains` 断言；**smoke QA 亲跑 1/0（exit 0）**。

## 四、矩阵抽验独立复跑（cell 2/5 亲跑 + cell 7 读档+多层亲验）

- **cell 5（--out 三态）独立复跑 ✅ 三段全**（`loop/qa/t07t3-qa-cells.ps1`，my-game+CLI）：
  拒绝段 exit 1+文案命中；**保留段字节级证实**（补验脚本：拒绝前后 important.txt 8 字节逐字节
  一致——首轮脚本 `kept=False` 系 QA 自己的 CRLF 比较 bug，自纠后产品行为清白）；force 段 exit 0
  +important 消失+marker+manifest+exe+assets 五要素全。
- **cell 2（失败保旧）独立复跑 ✅**（换注入点，同格子语义）：staging 预占需 jd 子进程 pid 先知
  （机制性不可行），QA 改用**锁旧 dist 内 exe 句柄**（无 DELETE share）——swap 第一步父目录
  rename 被拒（T2 双探针已证任何句柄挡父 rename）→ export **failed exit 1 + 旧 dist 4 文件
  逐字节一致**。
- **cell 7（assets_dir=content）**：程序留档（构建 502 components+staged+manifest+N8 toolchain
  提示真机可见，`t07t3_cell7_assetsdir.log`/`cell7b.log`）+ 布局腿 T1 单测亲跑在案
  （`an_assets_dir_override_is_staged_under_its_own_name`：dist/content 一致+无幻影 assets）+
  schema 异目录启动 exit 0 的机制已被 QA 的 heavy smoke 亲跑覆盖——**多层证据判定通过**
  （⚪ 布局的真机断言行未见直接留档，原始日志为准）。
- 其余 7 格读留档判定：editor_cells（CELL 2/3 PASS 行+中间轮「7 过 3 失败」与 CMD 直驱补 5/6/7
  的链条自洽）、cell 6 拒绝文案在档（`refusing to stage ... holds the build's own sources`）。
- **force 遗漏 git 考古（QA 证实）**：`01eb4883`（T1 合入点）的 `crates/jd/src/main.rs` 中 export
  `flags: &[]`+入口 156 行未知旗标拒绝——**jd 入口 `--force` 自 T1 起确实不可达**（真遗漏声明
  属实）；当前 `flags: &["--force"]`+usage 两处修正落地。

## 五、门禁

| 门 | 归档 | 复核 |
|---|---|---|
| fmt | `t07t3_fmt.log` 0 字节 | ✅ |
| clippy --all-targets | `H:\workspace_AI\t07t3_clippy.log` | 零 error 行（5 处新 warning 已修后覆盖重跑）✅ |
| xtask fast | `t07t3_gate_fast.log` | **2926/2926** ✅ |
| xtask integration | `t07t3_gate_integration.log` | **5198/5198** ✅ |
| doctests | `t07t3_gate_doctests.log` | 8 组 ok；bind workspace flaky 的单独跑旁证 **QA 本轮再跑 1/0** ✅ |
| 专项 | build crate 27/主 1168+face+game_export/jd 22/cli 18 | 与报告一致 ✅ |
| QA 亲跑 | heavy export 1/1、mcp_smoke 1/0、manifest 32 匹配、BRP 三态 1/0 | 全绿 ✅ |

**xtask heavy 全档决策：不跑**。理由：heavy 档内容 = SDK 各 triple 构建 + `--test export` +
mcp_smoke——本任务改动面的两条 heavy 腿（export 1/1、mcp_smoke 1/0）**已双双亲跑绿**；SDK
triple 构建与本任务改动（manifest/export face/--force 白名单）零交集且成本 10-30 分钟，增量
信息趋零；`release-gate`（fast+integration+heavy）留 CI/主控终审的排期合理。

## 六、偏差裁定

| # | 偏差 | 裁定 |
|---|---|---|
| ① | jd.exe 0xC0000135=被杀构建的半写 dll（重建即愈） | **闭环可信**：机理成立（半写 dll→加载失败）+重建日志（jd_rebuild2 `Finished 6.45s`）+QA 自身 jd 重建（17.97s）后 cell 2/5 全通的旁证+「PS/CMD 假象=坏 dll 窗口两侧」的解释自洽。环境问题非产品缺陷，教训（杀构建后先重建再判定）在档 |
| ② | doctests 干净树 stash 证明未做 | **接受**：三重旁证（单跑×2 含 QA 本轮再跑 1/0、改动面不含 jackdaw_bind、T05/T06 历史同款 flaky 先例）；stash 悬挂风险的权衡如实记档 |
| ③ | cell5/6/7 改 CMD 直驱 | 接受（脚本本体保留）；⚪ **`loop/t07t3_cell5_refused.log` 为空文件**（留档缺陷，cell5 证据由 H 盘 leg1+QA 本轮复跑补齐） |
| ④⑤ | 矩阵脚本三轮修复/cell7 junction | 均脚本层/环境层记档，合理（junction 已拆未污染缓存） |
| ⑥ | heavy 全档 | 见 §五决策（不跑的理由） |
| ⚪ | 新发现残留 | `H:\workspace_AI\t07t3_clippy.log`n`（PowerShell 反引号未展开成字面文件名，同类事故第三起：`$null`/`.log'n`——脚本字符串习惯问题，建议全量清一次） |

## 七、T07 放行清单与 P0 收官判定

- **T07 三任务**：T1（QA PASS 2026-10-24，原子 staging+防护+红绿 4 铁证）→ T2（QA PASS
  2026-10-24，--locked 四入口+R9 等价验收）→ T3（本报告全绿）——**三任务全 PASS**；
- **方案 T3 QA 清单**：heavy 挪盘铁证（QA 亲跑）✓、manifest 一致（幂等+篡改检出）✓、矩阵
  10 格（3 格 QA 独立复跑+7 格留档）✓、全量门干净 ✓、book（What ships/The export manifest/
  Reproducible/失败保留/--force 五组扩写在）✓、30 秒清单三例（锁文件/挪盘/面板）在案 ✓；
- **buglist**：R9/R10/Y7 勾选在位，本轮无新钩 ✓；roadmap T07 勾选留主控；
- **验收句④铁证**：heavy smoke 的「dist 深层异目录复制+cwd 运行 schema exit 0」+ cell 4 程序
  真机窗口模式运行截图——「导出物离开原目录可玩」双层证据；
- **T1 遗漏（force 不可达）**：本轮发现-修正-验证闭环（QA 考古属实+复跑三段全过）——交付
  质量的自我修正链条健康。

**判定建议：T07 可勾选；P0 七项全部闭环**（T01-T07 的 QA PASS 链+台账在 loop/progress.md，
最终勾选动作由主控核对 roadmap 台账执行；T07 合入 `--no-ff` 即完成 P0 收官）。

## 八、QA 汇总

- 新发现 ⚪ ×3（cell5_refused.log 空、`t07t3_clippy.log`n` 字面文件名残留、cell7 布局真机断言
  行未直接留档）；无 🔴 无 🟡。QA 自纠 1 处（自己脚本的 CRLF 比较 bug，补验澄清产品清白）。
- 残留：QA 复跑产物已清（cell 临时 dist/keep-check）；无进程残留；工作区常规项（`.gitignore`/
  `.mimosa/`/buglist.md 不入库）。

## 九、PASS 条件核对

| 条件 | 判定 |
|---|---|
| heavy 亲跑绿（1/1+D6 双登记+断言链） | ✅ |
| manifest 断言实（幂等+篡改检出均实质） | ✅ |
| 抽验 3 格过（cell2/5 独立复跑+cell7 多层） | ✅ |
| force 遗漏考古属实（01eb4883 flags&[] 实证） | ✅ |
| 门禁复核干净（六门归档+亲跑 4 项+heavy 决策有理由） | ✅ |
| 无新 🔴 | ✅（⚪×3） |

VERDICT: PASS
