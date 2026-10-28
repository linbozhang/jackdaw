# 仓库迁移手册（2026-10-28 生成）

> 用途：把本仓库（jackdaw 编辑器 + Loop 工作流）迁移到另一台电脑继续执行。
> 生成时状态：main = `fad046ce`；T11-T3 停在 WIP（见下）；用户指令=T11 闭环后暂停（暂停指令已在台账头部）。

## 一、恢复点（新机器上从这里继续）

1. **当前任务**：T11 任务 3（收官段）**中断于 WIP**——分支 `loop/t11-final` 提交 `406d116b`
   （C10 doc 五件套修复 + N14 首次 set 完整组件落库修复 + book `player-controller.md` 新章，8 文件 +334/−8）。
   **已完成**：全部 8 件门禁归档 `loop/reports/t11t3_*`（fmt/clippy_ws/clippy_physics/guards_regress/fast/doctests+bind 复跑/integration）。
   **未完成**：矩阵 12 格跑证、t11-t3-report.md 报告、QA 终验、合入、roadmap 勾选 T11。
2. **继续方式**：读 `loop/README.md`（契约）→ `loop/progress.md`（台账，恢复地图在头部）→ `loop/plans/roadmap-game-dev.md`（勾选状态）→ 派 agent 续跑 T11-T3（改动已提交在分支上，矩阵与报告从零补即可，门禁可先复核归档）。
3. T11-T3 完整闭环（程序→QA→合入→勾选）后 = 用户暂停指令生效点，等用户新指令再启 T12。

## 二、⚠️ 构建硬依赖：bevy fork（不在本仓库内！）

- 本仓 `[patch.crates-io]`/`[patch."git"]` 指向**本机路径** `E:/Project/rust/bevy-fork-pinned`（86MB git 仓库，锚文件 `jackdaw-pinned-rev`=c9c397ba）。
- 新机器两条路（任选）：
  1. **整体拷贝** `bevy-fork-pinned` 目录到新机器任意路径，然后把根 `Cargo.toml` 两段 patch 的路径改成新路径；
  2. **脚本重建**：`powershell scripts/make-bevy-fork.ps1 -Rev c9c397ba -OutDir <新路径>`（需网络，clone bevy+改 77 个 manifest 版本串+两 commit；产出后同样改根 Cargo.toml 路径）。
- 判定 fork 是否就位：`bevy-fork-pinned/jackdaw-pinned-rev` 文件存在且内容=c9c397ba…，根 Cargo.toml `version = "0.20.0"`。
- 见 `book/src/developer-guide/open-challenges.md` 第五条（CI fork 断裂 ledger，托管决策待用户）。

## 三、本次入库的 AI 工作流内容（原为本地 exclude，现已提交 git）

- `loop/` 全目录（契约 README/台账 progress/方案 plans/报告 reports/QA 脚本 qa/证据 t10b-live）——**新机器恢复工作流的全部上下文**。
- `buglist.md`（用户手写清单，P1 后阶段的核心交付物追踪；28 勾+N11/N12/N13/N14 在案）。
- 迁移前曾用 `.git/info/exclude` 排除 `loop/`（该文件不随仓库旅行，新机器无需恢复此排除——loop/ 已正式入库）。
- `loop/memory-snapshot-20261028.md`：旧机器跨会话记忆快照（大量操作教训：限额续跑/编码事故/探活纪律等，新机器 agent 可读但以 loop/README 契约为准）。

## 四、环境差异提示（旧机器特有，新机器需重新基线）

- **NVIDIA 驱动 591.86 崩溃族（nvcuda64@0x3ab984）是旧机器特有**：PIE 全形态 0xc0000005、DX12 OOM 等（详见 loop/qa/t10b-crash-workaround.md 与 t10b/t11t2 报告）。新机器大概率不复现——**PIE 相关的降级口径（C7 真机格/N13 复发率测定）应在新机器上重新尝试真跑**。
- 150% DPI、合成 raw 位移巨量（R1 系）也是旧机器特征。
- 工具链：仓库自带 rust-toolchain.toml（1.99.0），新机器装 rustup 即可；首次全仓构建约 1 小时级（先预热、期间禁跑其他 cargo）。
- `cargo xtask fast` / `integration` 门禁需 `cargo-nextest`（`cargo install cargo-nextest`）。

## 五、清理记录（2026-10-28 迁移时执行）

- 已删：本仓 `target/`（~307GB Debug 产物）；`H:\workspace_AI\{t10-phys, t11-live, t10b, t10b-qa}`（暖工程+外部证据，~166GB；t10b 2MB 证据已并入 `loop/evidence-migration/`）；`.mimosa/`。
- 均为可重建内容（fresh `jd new`+冷编已验证可复现全部暖工程）。

## 六、旧机器残留（人工处理）

- ZCode 定时任务「Loop 后台任务进度汇报（每30分钟）」id=`automation-f56af51a`（本会话无删除工具，请手动关闭）。
- 旧机器跨会话记忆目录（C:\Users\linbo.zhang\.zcode\...）不在仓库内，快照已存第三节路径。
