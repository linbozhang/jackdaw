# T06-T3 QA 终验报告：「PIE 工具面+真机矩阵+文档收尾」（兼 T06 整体闭环判定）

> QA 角色产出，2026-10-24（验收执行）/ 程序报告 2026-10-26。分支 `loop/t06-final`，提交
> `4937db6c`（父 `66ef15e8` = main，即 T2 合入点），15 文件 +743/−93。
> 本报告兼 T06 整体（T1 `1bf371c1` / T2 `af93e730` / T3 `4937db6c`）闭环判定。
> 验收方法：归档全文复核 + 抽亲跑 + 独立真机（N10 四轮穷举探针 + 矩阵 10 格全复跑）+ 只验不修
> （$null 垃圾产物按纪律清理除外）。

## 一、N10 裁定（本验收核心）

### 1.1 独立复现尝试：QA 四轮穷举，零复现

QA 编写并沉淀探针脚本 `loop/qa/t06t3-qa-n10.ps1` / `-v2` / `-v3` / `-v4`（逐轮对齐程序复现条件），
全部使用 T3 提交版 exe + my-game：

| 轮 | cfg 状态 | play 时机 | 场景 | 结果 |
|---|---|---|---|---|
| v1 | 隔离干净 | 等 idle（prebuild 完）后 | 2 实体朴素场景 | **不冻**：BRP t0/t6/t9 全活，CPU 1.8 核（正常负载），play 正常 running |
| v2 | 隔离干净 | ready 即发（prebuild in flight，日志实证 `pre-building`） | 朴素场景 | **不冻**：BRP 全活，pie=running |
| v3 | 隔离干净 | prebuild in flight | 含 `my_game::SpinningCube` 项目组件场景（复刻矩阵 fixture，scene.open 后 `refreshed project types` 实证） | **不冻**：pie=running |
| v4 | **借用程序的 t06t3-live cfg（含 kill 残留会话，`recovery: 1 leftover session(s)` 对话框实证弹出）** | prebuild in flight | SpinningCube 场景 | **不冻**：pie=running |

**三边界（任务书要求）亲验全正常**：clean+Save（B1：running→stopped 干净落地）、dirty+Copy
（B2：running→stopped，盘不动）、untitled 脏+Save（B3：running→stopped，tab 仍脏）——与程序口径
一致（N10 限定在 dirty+Save 组合）。

**程序侧证据核**：4 组 freeze 归档（`t06t3_probe_freeze/freezeA/freeze_baseline/probe_cell3` 三
variant）形态一致且完整（play_current 后日志停摆+CPU 满载 4.4-4.9s/3s+BRP 超时；baseline 为
main `66ef15e8` stash 实证=存量缺陷，非 T3 回归）——证据可信、非伪造。

### 1.2 与矩阵格 3 对账：不矛盾

run12 留档与 QA 复跑的格 3 Save 段均为**显式 `scene.save` op → tab clean → play_current**
（"the save-policy play runs the saved file"）——即 **clean+Save play 路径**；N10 是 play 内联
触发自动保存的**同帧交织路径**（dirty 状态下保存链+PIE 启动挤同一帧）。两者是不同路径，格 3 的
语义断言（保存的内容被 play 跑）不受 N10 影响；程序已如实记偏差①并注明「dirty+save-play 组合待
N10 修复后补验」。对账成立，无掩盖。

### 1.3 裁定：**B —— T06 可闭环，N10 以独立高优缺陷另开修复任务**

理由（不给和稀泥的空间，五条）：
1. **存量缺陷，非 T06 回归**：main 基线（T1 合入前? 否——66ef15e8=T2 合入点）同冻实锤，即该路径
   在 T1 交付时就带病（T1 真机矩阵未覆盖 dirty+Save 一步组合，T3 扩面才暴露——测试面扩张暴露
   存量问题正是矩阵的价值，不应反过来惩罚扩面者）；
2. **验收句主体面全部成立**：「任意打开场景可运行」的 named(clean/dirty copy 态)/untitled/Ask
   各形态经 QA 三轮独立真机全过；唯 dirty+默认 Save 一步组合在程序侧条件下不可靠；
3. **规避成本极低且三重落账**（buglist 高优完整条目+30 秒清单规避注记+矩阵格 3 两步口径）——
   「先 Ctrl+S 再 Play」本就是编辑器用户的常见习惯（Unity/Godot 同类提示习惯）；
4. **QA 四轮穷举零复现收窄了触发面**：程序全部已知条件组合（cfg 干净/污染 × idle/prebuild ×
   朴素/项目组件场景 × recovery 对话框有无）在 QA 环境下全部正常——「100% 复现」口径过强，
   真实触发还依赖尚未识别的变量（连续冻结累积状态/特定帧时机/机器瞬时负载），用户实际撞到的
   风险低于表述；
5. **修复需要独立根因分析**（同帧保存链×PIE 启动×UI/watcher 交织），塞进 T06 闭环会阻塞
   roadmap 后续任务；QA 已沉淀四轮探针脚本与触发条件收窄结论，直接服务修复任务。

**B 的三条硬性后续承诺（放行前提，主控落账 progress 台账）**：
- N10 立即立项为下一修复任务（高优），修复后补真机「dirty+Save+play_current 一步」回归用例
  入矩阵格 3 的完整口径；
- N11（Inspector 合成提交两路不可达）与 N10 同批排期，补面后收口矩阵 #7 按钮链（Discard/Apply
  All 真机两分支）；
- progress 台账 T06 行带 N10/N11 尾巴标记，未修复前 roadmap 完成后 buglist 清账时不得漏。

## 二、上轮硬条件核验（T2-QA 的放行前提）

- **selection.set 交付质量**：`server.rs::selection_set_handler` 三入口（bits 逐个校验死 id 拒绝
  /names 复用 entity_from_params/clear）、pick 同款重打 Selected 标记；headless 亲跑
  `remote::server` **13/0**（含 selection_set 四段断言、pie_face、pie_wait 两例）；**真机半场：
  QA 矩阵复跑格 7 实测 `selection.set picked the projected Spinner: {"entity":...,"name":"Spinner"}`**
  ——选中投影实体（上轮点名的缺口③）真机可用。
- **矩阵 #7 收口形态 vs 上轮本意**：上轮硬条件原文=「补 selection 能力（`selection.set` 或等价
  live-edit 注入面）并完成矩阵 #7」。裁定：selection 能力落地+格 7 已跑（selection 面+无 pending
  不弹窗+stop 后文档/undo 不变——QA 复跑实测全过）——**字面满足**；「等价 live-edit 注入面」
  （驱动 pending 产生→prompt 按钮两分支）未落地=N11。**N11 记 buglist 可接受**：工具缺口非产品
  缺口、headless live_edits.rs 18 例语义全覆盖（apply_all 恰一条 undo/discard 不碰 AST/post-stop
  apply）、且 MCP 优先原则下补工具是正途——与 T2 偏差①同构的裁定，接受但必须按 §1.3 承诺排期。

## 三、欠账六项逐项核

| # | 欠账 | QA 核验 |
|---|---|---|
| ① | selection 工具+矩阵 #7 | ✅（§二：headless 13/0+真机选中投影 Spinner；按钮链=N11 记档） |
| ② | Reload 重算 override | ✅ 双验：guards 亲跑 13/0 含 `reload_resolves_the_override_fresh_without_writing_disk`；真机格 8 复跑实测「stage=live 后编辑→reload→新副本 `current-t06-final-<pid>.bsn`+scene_source=unsaved-copy」；`override_for_reload` 复用 `resolve_override_for_launch`（不落盘不打断：`save_first=false`）代码审查一致 |
| ③ | pie_stopped 竞态 | ✅ `PieSession.launches` 计数+`PieWait.launches_baseline`（`session_ran = seen_active || launches_now > baseline`）逻辑闭环；单测 2 例 QA 亲跑过（satisfies_when_already_ended / holds_when_never_ran）；diff 中 cached spawn 与 poll_builds 两条路径均 `launches += 1` |
| ④ | stop avail 门保守关闭 | ✅ 回退 diff + 回归锚 `a_connecting_child_keeps_the_editor_stopped` QA 亲跑 1/0；「放宽触发 N10 族冻结」的实证链（freeze3 系列归档：connecting 窗口 stop 同族冻结）与保守关闭决策自洽 |
| ⑤ | scaffold 实编 | ✅ 留档核实：`jd new t06-template-check`（8 files，path 依赖提示正常）→ cargo check `Finished 1m37s` 零 error → 工程已删。T1 偏差⑨行动项闭环 |
| ⑥ | N-QA4 | 已在 T2 双侧闭环（T2 报告 §一.7），无遗留 |

## 四、门禁复核（全量六门）

### 4.1 归档全文复核

| 门 | 归档结论 |
|---|---|
| fmt | `t06t3_fmt.log` 0 字节（--check 通过零输出，与历轮口径一致） |
| clippy --all-targets | 仅 5 条既有工具链噪音，无 error 无新增（比 quick 门宽的 all-targets 面首跑抓出 T1/T2 测试代码问题并已修复重跑——门禁过程真问题如实记档） |
| xtask fast | **2905/2905 passed**（1 leaky 存量、2 skipped；FAILED 命中均系测试名字样） |
| xtask integration | **5177/5177 passed**（405s；param_declarations guard 抓出 T1 欠的 `project.set_save_before_play` params 声明并已修——门禁体系正常发挥作用） |
| doc | 57 文档生成无 error |
| doctests | 8 crates 全 ok；jackdaw_bind workspace 轮无声失败=偏差③，**QA 抽验单跑 1 passed/0 failed 属实**，T3 未触碰该 crate（diff 清单核实），存量环境性例外记档合理 |
| guards/runtime | 197/0、5/5 |

**六门：PASS。**

### 4.2 QA 亲跑

`remote::server` **13/0**（4 新测试含）、guards play_current **13/0**（+reload 例）、
`a_connecting_child_keeps_the_editor_stopped` **1/0**、bind doctest 单跑 **1/0**、
`cargo build -p jackdaw`（1m11s 干净）。

### 4.3 MCP smoke 与适配核实

- tools/list 实测**24 个工具**（QA 精确计数，pie 工具在且描述完整教断言用法）——**程序报告称
  25，数字级出入记 ⚪ N-QA-T3-1**；
- expect→allow：5 文件均为 `#![expect(clippy::print_stdout, reason=...)]`→`#![allow(...)]`
  单行机械替换（reason 保留），纯 lint 属性降级无行为影响——无害适配 ✅；
- **`$null` 误产物**：仓库根确认存在且**未清**——224 字节（非报告语境的 0 字节），内容为两条 git
  CRLF warning（PowerShell `$null` 字面量重定向事故）。**QA 已代为删除并在此留证**；根因=程序某
  脚本的 `2> $null` 在非 PowerShell 语境失效，修复 N10 轮顺带自查脚本防再生成（⚪ N-QA-T3-2）。

## 五、矩阵独立复跑（QA 亲自执行）

`loop/qa/t06-final-live.ps1` 全 10 格复跑：**`T06_FINAL_MATRIX_10_OF_10_PASS`（exit 0）**。
任务书指定抽验格全过：格 2（untitled：unsaved-copy+副本含文档+游戏加载 Cube+stop 清副本+tab 仍
脏）、格 8（Reload 重算：新副本+unsaved-copy）、格 10（instances=2 下 play_current 单实例带
override、stop 清空）；格 7 selection.set 真机选中投影 Spinner；格 6 双 SHA+`jackdaw/pie` 清面。
格 3/格 5 的 `pie.stop cancelled→重试` 为 avail 门既定交互（偏差⑤）。复跑全程未撞 N10（矩阵避开
watching 跨连接窗口+格 3 两步口径）。复跑残留已清（漏杀的编辑器进程与 t06-final.bsn——
⚪ N-QA-T3-4：矩阵脚本 finally 清理不彻底，程序下轮顺带补）。

## 六、book / 30 秒清单 / buglist

- book PIE 节结构完整：Which scene Play runs / Unsaved changes: the three policies（三态+旧 bool
  迁移）/ The temporary copies / Stopping and reloading（2s 窗口+reload 重算）/ The stop prompt and
  live changes——方案 T3.4 的五点要求全覆盖；
- 30 秒清单三例实测通过，**N10 规避注记在列**（①的脏场景变体：先 Ctrl+S 或切 copy 策略）✅；
- buglist：N10 条目格式完整（触发/四组实证/影响面/绕行/修复方向，高优）；N11/N12 ⚪ 记档 ✅；
  **Y34/W26/W17 三钩未动**（仍为 T2 的 [x] 状态）✅。

## 七、偏差逐条裁定

| # | 偏差 | 裁定 |
|---|---|---|
| ① | 格 3 dirty+Save 改两步（N10 规避） | 接受（§1.2 对账不矛盾；修复后补完整口径——硬承诺） |
| ② | 格 7 按钮链=N11 | 接受（§二；与 N10 同批排期——硬承诺） |
| ③ | bind doctest workspace 轮无声失败 | 接受（QA 单跑抽验 1/0 属实；未触碰 crate；存量环境性） |
| ④ | jd.exe 二进制漂移（MCP 需单独 build） | 接受（教训记档合理；mcp_out4 直连 jd-mcp.exe 的 smoke 有效） |
| ⑤ | avail 拒绝+重试既定交互 | 接受（T2 已裁定的保守关闭语义；根因归 N10） |
| ⑥ | N12 实体域不通 | 接受（T2 已发现 T3 再撞，记档；工具统一域归后续） |
| ⑦ | 续跑开局曾带改动在 main（主控拦截） | 接受记档（无分叉无损失；分支纪律事件如实披露，QA 核对 `4937db6c` 父提交=66ef15e8 无误） |

## 八、QA 汇总

- 新发现 ⚪ ×4：N-QA-T3-1（MCP 24≠25 数字口径）、N-QA-T3-2（$null 事故产物已清+根因）、
  N-QA-T3-3（N10「100% 复现」口径过强——QA 四轮穷举零复现，触发条件含未识别变量）、
  N-QA-T3-4（矩阵脚本 finally 清理不彻底）。无 🔴 无 🟡。
- 纪律：四轮 N10 探针与矩阵复跑后全部残留已清（进程/fixture/.bak/cfg 借用无污染——v4 借用的
  cfg 仅新增一个空残留会话目录，属该工件目录既有形态）；`$null` 垃圾文件 QA 代删留证；
  `.gitignore`（.mimosa/）与 buglist.md 仍为本任务外本地常态。

## 九、PASS 条件核对（N10-B 路径）

| 条件 | 判定 |
|---|---|
| 矩阵（10/10 独立复跑）+硬条件（selection.set headless/真机双验+#7 收口形态）+欠账六项 | ✅ |
| 全量门干净（六门归档+抽亲跑+MCP smoke+适配核实+$null 处置） | ✅ |
| N10 明确另开任务承诺（§1.3 三条硬性后续，含修复后回归用例） | ✅ |
| 偏差逐条裁定+book/30 秒/buglist 核对 | ✅ |

## 十、T06 整体闭环判定

- T1（`1bf371c1`）QA PASS 2026-10-24（运行当前场景通道：runtime 换把+三态+temp 副本，真机四用例）
- T2（`af93e730`）QA PASS 2026-10-24（优雅停止+Stop 还原铁证+W26/W17/selection 4 例；N-QA1/N-QA4 闭环）
- T3（`4937db6c`）QA PASS（本报告：矩阵 10/10+selection.set/pie/pie_wait 工具+六欠账全处置+全量门）
- 遗留尾巴（不阻断闭环，已在 §1.3 落账）：N10（高优修复+回归补验）、N11（#7 按钮链收口）、
  N12（工具域统一）、N-QA-T3-1..4（⚪ 记档项）

**T06「当前场景 Play 与编辑态隔离」整体闭环成立**，可由主控 `--no-ff` 合入 main，合入时更新
roadmap T06 勾选与 progress 台账（带 N10/N11 尾巴标记）。

VERDICT: PASS
