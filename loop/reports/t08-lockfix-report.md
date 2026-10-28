# T08-T3 前置小任务报告：scaffold fresh lock 漂移 + pin 失效

> 任务书：QA 硬性前置（t08-t1-qa.md §六-②：fresh scaffold 工程编辑器 prebuild 必炸）。
> 分支 `loop/t08-lock-fix`（自 main e70348d5 拉出），提交见文末。证据 `loop/t08lf_*.log`。

## 一、根因（一句话 + 展开）

**一句话**：`jd new` 的依赖检查步骤（`cargo metadata`）在无 lock 时做**无约束全量解析**，把新工程锁到「索引当日最新」组合（上游窗口内 windows 系新宏与 wgpu-hal 30.0.1 失配 + bevy 移至 fe544043）；此后 `pin_project` 只用 `cargo update --package bevy --precise` 移动 **bevy 主 crate 一个包**的 rev，同 repo 的 bevy_* 子 crate 与 wgpu/windows 树保持 fresh 组合；T08-T2 起 `--locked` 又把这个坏组合锁死——三环相扣，每个 fresh 工程的 prebuild 必炸。

**pin「失效」的真相**：pin 生效了（bevy 主 crate 确实回到 c9c397ba——QA 工程 lock 里 rev 在），但 `--precise` 单包移动不重排传递树，QA 实测的「windows_core 宏失配族（两边 windows 版本相同）」正是 **bevy 子 crate 混 rev / wgpu-hal 同版本不同邻接组合**的深层失配——修 pin 本身（全树重排）没有可靠的 cargo 原语，修不动。

## 二、修复：模板携带 workspace lock 快照

- **`jackdaw_scaffold`**：`workspace_lock_snapshot() = include_str!("../../../Cargo.lock")`（编译期嵌入——与模板 `include_dir` 同款新鲜度规则：checkout 构建每次重编即更新；发布 jd 打包发布时验证过的组合）；`scaffold_new_project_with` 对 **Game** 工程在写完模板后写入 `<dest>/Cargo.lock` = 快照。
- **修剪链（核心机制）**：`jd new` 本就跑 `cargo metadata`（`check_new_project`）——从「坏锁生成器」变为「好锁修剪器」：cargo 对已有 lock 取**最小变动**策略（只添加本工程条目、剔除未引用包、**保留全部已锁版本**）。
- **真机实证修剪不漂移**：fresh 工程建后 lock 检查——`my-game` 条目已补入、bevy 仍锁 **c9c397ba**（未漂到 fe544043）、wgpu/windows 树=workspace 组合。
- 之后编辑器 prebuild：`pin_project` 见 lock 已在目标 rev → no-op；`ensure_lockfile` 见 lock 在 → no-op；`--locked` 构建命中已含本工程条目的好 lock——**一次过**。

## 三、真机验证（三腿全过）

| 腿 | 结果 |
|---|---|
| **fresh scaffold → 编辑器 prebuild**（`loop/t08lf_prebuild.log`） | `jd new my-game --path ...`（新 jd）→ 编辑器 `JACKDAW_OPEN_PROJECT` 打开 → **IDLE 到达、`.jackdaw/schema.json` 产出、编辑器存活、stderr 零 error**（含 `--locked` 全程）——QA 记录的必炸路径一次过 |
| **cargo build（游戏自身）**（`loop/t08lf_game_build.log`） | 同工程 `cargo build` **exit 0** |
| **活样本 `H:\workspace_AI\t08-qa-game`**（`loop/t08lf_qagame_build.log`） | 拷 workspace lock + manifest 对齐模板写法（`branch = "main"`）→ `cargo build` **exit 0**（QA 记录的漂移样本恢复可编译） |

活样本首试失败记档（§五-1）。

## 四、`jd new` 路径名拒绝（⚪ 顺带）

`validated_project_name` 前置检查：raw 含 `/`、`\` 或 `file_name() != raw` → 拒绝并提示「pass the directory with --path and only the name here」（QA 复现的 `jd new E:\...` 静默错名目录事故根因关闭）。用例 `a_project_name_that_is_really_a_path_is_refused_with_guidance`。

## 五、偏差与记档

1. **活样本需 manifest 对齐**：直接拷 lock 到 QA 手改过的工程（bevy 依赖写 `rev = "..."` 固定）首次 build 失败——错误形态从「windows 宏失配」变为「bevy::winit 等找不到」（rev 固定写法与快照 lock 组合时 cargo 对包集部分重解）；把 manifest 改回模板写法（`branch = "main"`）后干净通过。**修复本身不受影响**（`jd new` 产出的工程 manifest 本就是模板写法）；此差异属 QA 样本的手改状态，记档供 T3 若复用该样本时先对齐。
2. **嵌入快照的新鲜度规则**：改 workspace Cargo.lock 后需重编 `jd`（与模板 include_dir 同款）——T1 已有教训记档惯例，本任务沿袭并在 `workspace_lock_snapshot` doc 写明。
3. **extension 模板不写快照**（依赖树窄，且任务范围为 Game；extension 走同一 resolve 路径若有漂移窗口再扩）。
4. pin 机制本身未修（`--precise` 单包移动的局限是 cargo 语义，见 §一）；lock 快照让 pin 在新工程上变成 no-op（lock 已在目标 rev）——比修 pin 更稳的路线。

## 六、门禁

| 门 | 结果 |
|---|---|
| fmt | clean |
| clippy workspace all-targets `-D warnings` | **exit 0**（揪出 1 处 map_or 简化，修后过） |
| scaffold crate | **81/81**（+2 新用例：lock 快照逐字等于 workspace lock、路径名拒绝） |

主 crate/构建链零改动（只动 `crates/jackdaw_scaffold`），guards/lib 未重跑（clippy all-targets 覆盖编译面）。

## 七、提交

`Pin fresh scaffold locks to the workspace bevy tree`（单文件 `crates/jackdaw_scaffold/src/lib.rs`；临时工程与探针脚本已清；活样本 t08-qa-game 保留但 manifest 已对齐+lock 已换好组合——供 T3 复用或删除）。
