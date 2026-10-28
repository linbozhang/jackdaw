# Jackdaw Loop 工作契约

> 本目录被 .git/info/exclude 本地忽略，不入库、不影响上游 PR。

## 目标

按 README 指定的官方 Bevy Editor Roadmap（Stage 0–6 + 未分类）与设计原则，补完 jackdaw 中
缺失/半成品的功能。**每完成一个功能，必须走完整 策划 → 程序 → QA 循环并合入后才进入下一个。**

## 输入（需求真理之源）

- **新 Roadmap（最高优先级，用户裁定 2026-10-24）：`loop/plans/roadmap-game-dev.md`（P0-P3 任务清单 T01-T25）**
- 旧参考：官方 Bevy Editor Roadmap 盘点表 `loop/plans/roadmap-gap-analysis.md`（不再作为选题依据）
- 设计原则: bevy_editor_prototypes /vision.html、/architecture.html
- 设计图: Bevy Editor Figma（README 内链接）
- 本地已知缺口: book/src/developer-guide/open-challenges.md
- 仓库约定: CONTRIBUTING.md（operator 模式、检查分级、PR 规范）

## 验收门（QA 每任务必跑，quick tier）

| 门 | 命令 |
|---|---|
| 格式 | `cargo fmt --all -- --check` |
| Lint | `cargo clippy --workspace -- -D warnings` |
| 单测 | `cargo test --workspace --lib` |
| 任务相关 | 被改 crate 的集成测试 / doctest（视任务而定） |

CI 全量（`cargo xtask fast` / `integration` / docs / doctests，需 cargo-nextest）：QA 认为必要或
任务跨 crate 面大时跑；该偏差已在此记录（主控裁定 2026-10-22）。
视觉验收：涉及 UI 的任务跑编辑器截图（PrintWindow 法），QA 子代理看图比对 Figma 风格。

**门禁证据标准（2026-10-25 升级，T04-T2 教训）**：`xtask fast` 等 exit code 不忠实（实证：归档
clippy 日志含 3 个真 error 末行仍 `EXIT=0`）。门禁证据以**日志全文复核**为准（逐行看
error/FAILED/Diff-after-reformat），exit code 仅作辅助；修完问题重跑必须**覆盖归档日志**（旧日志
残留=门禁表与证据矛盾，按未过处理）。

**文本文件写操作纪律（2026-10-26 升级，buglist 编码事故教训）**：对 `buglist.md`、`loop/` 下所有
markdown 等非 ASCII 文本文件的读改，**只准用字节安全工具（Read/Edit/Write），禁 PowerShell 文本
管道**（`Get-Content`/`Set-Content`/`-replace` 走系统 GBK 代码页往返，会不可逆摧毁 emoji 与散点
汉字——实证一次损失 790 字符）。PowerShell 对这些文件只允许只读且**不落盘回写**的检查。另：
**本地 loop main 永不 `git pull`**（与远端永久分叉是设计态，pull 必产冲突；曾致 reset --hard 抢救）。

## 循环规则

- 分支 `loop/<feature-slug>` 自本地 main 拉；QA 判 PASS 后由主控 `--no-ff` 合入 main（不推远端）。
- 单任务修复循环上限 5 轮，超出升级用户裁决。
- 程序/QA 报告、策划方案分别落 `loop/reports/`、`loop/plans/`（不入库）。
- 台账 `loop/progress.md`：每个功能闭环后记一行；中断恢复以台账为准。
- 本仓库不受 P4 管理，纯 git。

## 交互验收（2026-10-23 用户裁定新增，适用于所有交互/工具/视口类任务）

QA 不得仅凭 headless 断言与代码审查放行，必须包含**真机操作验收**：

- 启动编辑器（用户工程 `C:\Users\linbo.zhang\Projects\my-game` 或 fixture 工程），用合成输入
  （PowerShell SendInput / SendKeys）驱动真实键鼠交互；
- 状态断言优先走编辑器 BRP 通道（查询实体/资源、调用 operator——`tests/guards/batch_undo.rs` 的
  handler 调用模式可参照），视觉结论用 PrintWindow 截图比对；
- 「留用户手测」不再是交互类任务的放行条件，只作为终审抽查项。

## MCP 优先原则（2026-10-25 用户裁定新增，最高优先级工作准则）

**如果一个验收/测试步骤用现有工具驱动很麻烦（坐标注入、时序赌、前台化、控件交互困难），
正确做法是给 QA 工具层（BRP 方法 / jackdaw_mcp MCP 工具）补上这个能力，而不是让 QA 用土法硬耗。**

- 工具层现状速查：`loop/qa/manual.md` §7（ui_tree/ui_click/ui_drag/ui_input/camera_state/input.motion/wait idle）
  + 既有 20 个 MCP 工具（`jd mcp --project`）。
- 流程：QA 遇到「麻烦步骤」→ 报主控 → 主控裁定补工具（走小任务或并入当前任务）→ 用新工具完成验收。
  工具补充本身也要过门禁与测试（不能为测代码引入不受测的代码）。
- OS 级 SendInput 仅保留用于「测真实输入栈」本身；其余交互驱动一律优先结构化工具。

## 自主推进与用户验收（2026-10-25 用户裁定新增）

- Loop 任务闭环（QA PASS + 合入）后**不等用户验收，直接继续 roadmap 下一任务**；
  用户验收改为事后抽查（各任务的用户 30 秒清单累积在 final-qa 报告里）。
- roadmap（loop/plans/roadmap-game-dev.md）全部完成后：处理仓库根 `buglist.md`——逐条
  复现→修复→打勾（`[x]`）→标注留用户验收。

## 主动插入任务

在这里，可以主动插入roadmap里没有列出或者策划没有规划的任务。需要完成一下任务：

1. 在outliner 里通过Add  菜单增加Cube、灯光等支持的Entity ，并且能在viewport看到+在Inspector 编辑运行

