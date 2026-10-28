# T07-T2 QA 验收报告：「统一 --locked 与构建反馈」（只验不修）

> QA 角色产出，2026-10-24。分支 `loop/t07-t2-locked`，提交 `9a80bcbc`（父 `01eb4883` = main），
> 5 文件 +325/−11（binary.rs 主体 / cli 接线 / bevy_source / scrolling_log / build.rs 一行）。
> 程序报告：`loop/reports/t07-t2-report.md`（§七两事故+R9 红证不可得论证已逐项裁定）。
> 纪律：本轮起对 buglist/loop 文本一律字节安全工具（findstr/Read），未用 PowerShell 文本管道。

## 一、--locked 四入口：全覆盖核验通过

- **单点**：`cargo_build_argv`（`binary.rs:242`）argv 尾追加 `--locked`——QA grep 全仓
  `"--message-format=json".into()` argv 拼装**仅此一处**；四入口调用链核实（cli lib.rs:1019 的
  `build_project_binary_with_load` 汇聚 jd build/run/export；`src/pie.rs:1109` 汇聚 Play 与编辑器
  导出）。
- **无旁路抽验**：`build.rs:335` 是 `cargo rustc --crate-type dylib`（编辑器扩展 shim 构建，非游戏
  工程发布物）、`plan.rs:143` 是 SDK 管线、`bootstrap.rs:624` 是 jackdaw 自身 workspace——程序
  「不属四入口、不动」的边界记档成立。
- **stale-lock 集成亲跑**（真跑 cargo，0.98s）：`a_stale_lockfile_fails_locked_with_the_remedy_
  in_the_log` **1/0**——fixture 生成 lock→bump version→build→`Err(Compile)`+cargo 原始拒绝存活
  +`cargo update` remedy 进 BuildEvent 流。旧「静默重_resolution」行为由 argv 锚点断言集变更
  （`the_build_command_locks_the_dependency_resolution`，旧数组无 `--locked` 的历史锚）承担对照。
- **remedy 文案一致性**：`locked_failure_hint` 匹配串 `--locked was passed` 为实测 cargo 文案
  （程序首跑揪出差异后修正，纯函数测试字面量注明 "captured from a real stale-lockfile build"）；
  无关 stderr 返 None 有断言。
- **lock 缺失/不动用例**：亲跑含（生成+`commit it for reproducible builds` 提示；已存在不提且逐
  字节不动）——`a_missing_lockfile_is_generated_and_an_existing_one_is_left_alone` 过。
- **pin_project 时序**：`ensure_lockfile` 在 pin **之后**、spawn 之前（diff 位置核实）；pin 生成的
  lock 直接过；pin 失败仅 warn 降级（fixture 无 bevy 实测）。
- **QA 亲跑合计**：`-- lockfile locked_failure toolchain build_command_locks` 过滤 **8/0** 全过。

## 二、R9 红证不可得：等价验收裁定**成立**

1. **bevy 源码 QA 独立核实**：当前 rev（Cargo.lock 声明源 `c9c397ba`，本地 checkout
   `~/.cargo/git/checkouts/bevy-50d7e162b728c6c6/c9c397b`）的 `crates/bevy_ui/src/ui_node.rs` 中
   `pub struct Node` 的 `#[require(...)]` 列表**明确含 `ScrollPosition`**——任何 spawn `Node` 的
   实体自动获得该组件、`refresh_scrolling_logs` 的 query 恢复匹配——**症状随 rev 升级自愈的
   机制源码级证实**（比提交追溯更直接：证据就在被编译的源码里）。
2. **红不可得实证**：`H:\workspace_AI\t07t2_red_run1.log`——修复前跑世界直插测试**直接绿**
   （1 passed / 1167 filtered），红证在当前 rev 无从跑起。
3. **等价四支柱**（与 N10 降级先例同构）：源码根因（QA 独立核实）+ 红不可得归档 + 显式化修复
   （`ScrollPosition::default()` 落 bundle，防上游回退+意图显式）+ 回归钉（guards 197 含）+ 真机
   面板硬证据（§三）——**裁定：成立**。
- ⚪ 附记：提交号 `eb19a9ea0`（PR #15898）无法在 cargo 裁剪 checkout 中独立复核（checkout 无
  完整历史）；不影响裁定（机制证据自足）。

## 三、真机 buildpanel 抽验（QA 亲自复跑）

`T07T2_BUILD_PANEL_LIVE_PASS`（exit 0）：新版编辑器打开 my-game → **prebuild 全链 `--locked`
完成 → `jackdaw/wait idle` 放行**（--locked 构建真跑成功——比 metadata 解析层更强的证据）→
截图留档。
- **截图硬证据裁决**：QA 复跑窗口截图中 Build 面板**非空白**——含 `building the game`、
  `building my-game as a cargo binary in C:\...\my-game, into ...`、`game ready (492 types)` 日志行
  （QA 复跑为增量构建故无 Compiling 行；程序首轮全量构建截图含完整 Compiling 流，两证据互补）。
  **R9 用户可见面事实为真。**
- ⚪ **QA 发现：脚本断言空洞**——`t07t2-buildpanel-live.ps1` 的 `panel carries` 检查只排除
  `'null'`/`'{}'` 字面量，`{"nodes":[]}`（ui_tree 零命中）不触发 throw；`compiling lines: True`
  判据（JSON ≠ 'null'）同样可被空 nodes 假真。QA 复跑的两断言实为空洞通过，**事实靠截图裁决**。
  建议：断言改为检查 `nodes.Count > 0`（后续复用者注意；ui_tree 对滚动日志文本的命中性本身是
  工具面特性，非产品问题）。

## 四、门禁复核

| 门 | 归档 | 复核 |
|---|---|---|
| fmt | `t07t2_fmt.log` 0 字节 | ✅ |
| clippy | `t07t2_clippy.log` | 无 error，仅既有 5 条 build-script/linker 警告（`then_some` 修正后覆盖重跑）✅ |
| project_build lib | `t07t2_lib_buildcrate.log` | **223/0** ✅ |
| cli lib | `t07t2_cli.log` | **18/0** ✅ |
| jackdaw lib | `t07t2_lib.log` | **1168/0**（+1 scrolling_log 回归钉）✅ |
| guards | `t07t2_guards.log` | **197/0** ✅ |
| QA 亲跑 | binary.rs 8 条 + stale-lock 集成 | **8/0 + 1/0 全过** ✅ |

## 五、两事故记档核实

1. **git pull 误操作**：QA 核实 main HEAD = `01eb4883`（T1 合入点，完好）、`9a80bcbc` 父 =
   `01eb4883`（分支基点正确）、工作树干净——`reset --hard 01eb4883` 的声明与仓库现场一致，
   **零损失属实、记档如实无隐瞒** ✅（教训「loop 本地 main 与上游分叉常态、永不 pull」在档）。
2. **buglist 编码事故**：T2 报告 §七.2 **主动记档**事故经过（PowerShell 管道+GBK 往返+无 git
   版本）与教训（字节安全工具）——**无隐瞒** ✅。但其「75 条结构零损失」声明与最终事实不符：
   主控收口注记+QA 上轮清点证明 **W 组 28 条与 N11/N12 曾实际丢失**（T2 实施者未逐条清点即作
   结构零损失声明——定性为自我评估错误而非隐瞒）。主控定稿重建现状 QA 复核：**83 条全**
   （75 用户+A1+N10+N11/N12+R11-R14）、勾选 **21=20 用户+N10**（恢复时点 19 用户勾+T2 轮 R9
   勾=20，自洽）、N11/N12 带重建标注、受损原件存档 `loop/reports/buglist.damaged-20261026.md`
   在——**实际处置已闭环**。

## 六、buglist 台账核对

- **R9**：`[x]` + 括号段备注（bevy 上游 eb19a9ea0/PR #15898 required components 自愈根因、红证
  不可得、显式化+回归钉+真机铁证处置、提交 `9a80bcbc`）——哈希与说明齐全 ✅（⚪ 格式为括号段
  而非 `> 已修复` 行，与 Y34/W17/W26 同风格，语义等价）；
- **R10/Y7** 上轮勾未动 ✅；W 组 8 勾（W7-W12/W17/W26）在位；A1 不勾。

## 七、偏差裁定

| # | 偏差 | 裁定 |
|---|---|---|
| ① | R9 红证不可得 | 成立（§二等价四支柱） |
| ② | heavy 全链构建未跑 | 接受——`cargo metadata --locked` 双 exit 0 声明的归档不可读（⚪），但 QA 复跑的 **idle 放行=--locked 全链真跑成功**是更强证据；T3 heavy 导出 smoke 补完整腿的排期合理 |
| ③ | remedy 不重复进 `compile_failure_log` | 接受（BuildEvent::Log 已达面板/footer 用户可见面，双写无增益） |
| ④ | `t07t2_red_run1.log` 归档在 H:\workspace_AI 而非 loop/ | ⚪ 归档位置不规范（内容在、可信） |
| ⑤ | metadata 双日志归档不可读 | ⚪（同②，替代证据更强） |

## 八、QA 汇总

- 新发现 ⚪ ×5：真机脚本断言空洞（建议修 `nodes.Count>0`）、eb19a9ea0 提交号不可独立复核、
  red_run1 归档位置、metadata 双日志不可读、R9 备注括号段格式。无 🔴 无 🟡。
- 残留：无 jackdaw 进程、my-game assets 干净（`.jackdaw-pie` 空目录常态）、工作区仅常规项
  （`.gitignore`/`.mimosa/`/buglist.md 不入库）。

## 九、PASS 条件核对

| 条件 | 判定 |
|---|---|
| --locked 面全覆盖（单点+四入口+无旁路+stale/缺失/pin 三用例亲跑） | ✅ |
| R9 等价验收裁定成立（源码根因独立核实+红不可得归档+四支柱） | ✅ |
| 门禁干净（归档六件+亲跑 8+1） | ✅ |
| 事故记档属实（git pull 零损失核实；buglist 主动记档无隐瞒、声明失准已由主控闭环） | ✅ |

VERDICT: PASS
