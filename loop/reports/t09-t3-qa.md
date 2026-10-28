# T09-T3 QA 终验报告（兼 T09 整体闭环判定）

> 验收对象：分支 `loop/t09-final`（自 main bca7c5ba），提交 **5fd729a3** `Close out input actions with the live matrix`（4 文件 +158/−1：book 两章一目录+open-challenges ledger+game_input +52 行单测，与程序报告一致）。工作区核对：src/crates/book 与提交态一致。
> 证据：`loop/t09t3_qa_matrix.log`（**QA 12 格矩阵独立复跑**）、`loop/t09t3_gate_*`（程序归档六件）、QA 亲跑输出（doctests 单验）。真机前按纪律重编 exe/jd（jackdaw 34.8s+jd 12.1s——dll 失配防线）。

## 一、矩阵抽验独立复跑——12/12 全 PASS（超出 4 格要求，数字级复现程序归档）

QA 整跑 `t09-t3-matrix.ps1`（重建工程 `H:\workspace_AI\t09t2-live\t09t2-game`，两阶段会话，全程无冻结）。重点 4 格：

| 格 | QA 复跑数字 | 程序归档 | 判定 |
|---|---|---|---|
| **9 不混用·捕获态** | plain Esc 后 selection **存活**+相机静（RMB+W 不动）+游戏 **ArrowUp dz=-11.999964** | -11.8 | PASS |
| **10 不混用·未捕获态** | Escape → **selection 清除**（编辑器键位收到）+游戏 **dz=0** | 0 | PASS |
| 2 改键 | ArrowUp **dz=-12.000035**、**W dz=0**、盘上完整 | -12.00/0 | PASS |
| 7 重启三态 | SHA 同+`asset.get actions` 同值+**dz=-11.900034** | -11.9 | PASS |

其余 8 格顺带全过：格 1（schema default 五动作三源+新卡空 patch 设计语义）、格 3/5（三层证据口径+headless 钉）、格 4（motion 200→**yaw -0.841470897** 逐位级复现）、格 6（0 设备挂账）、格 8（dirty 卡 0.6→dist 含 0.6+manifest+ready）、格 11（删文件→W 复活 -12.000/ArrowUp 死 0）、格 12（stop 四 SHA/清单同）。**格 9 探针用 input.key（无光标移动）——auto_release 坑未复现**（程序过程学的 click-away 语义成立，复跑无触碰）。**「不混用」双向铁证成立**（9=编辑器压制+游戏收到；10=编辑器收到+游戏收不到——双向各三/两断言）。

## 二、门禁——干净（flaky 处置链合规；一处报告措辞矛盾记 ⚪）

- 归档六件复核：fast 0 error；docs clean；**integration 首轮 FAILED**（`session_journal` 5ms 条连续 3 TRY FAIL）——**处置链三档归档互证、合规**（隔离重跑 `journal_retry.log` **9/0**（4.93s）+串行全量 `integration2.log` **5236/0**（359s）——T08-T2 QA 同款负载 flaky 教训的合规重演；FAILED=8 系 nextest TRY 行输出形态非 8 条失败）。
- **doctests 归档 error=1**（jackdaw_bind merged 失败——T07-T3/T08-T3 同款 flaky）**与程序报告「doctests 全绿」措辞矛盾**——**QA 亲跑单验 `cargo test -p jackdaw_bind --doc`：1 passed**（flaky 结论成立）——记 ⚪ 证据纪律（报告应如实写「1 处既有 flaky 单跑过」而非「全绿」；T08-T3 轮同款）。
- QA 亲跑抽验：doctests 单验过；guards/scaffold/lib 数字已在 T2 轮 QA 亲跑覆盖（本任务代码改动=runtime +1 单测，lib 1176 含）。

## 三、偏差 4 条裁定——全部接受（一条附 ⚪）

1. **PIE 游戏日志不可见**（stderr 仅进崩溃 tail）：接受——格 3/5/11 三层证据口径（配置级盘上+转发链格 9/2 同链直证+headless 新钉 `mouse_buttons_and_plain_keys_drive_button_actions`）论证成立且 QA 复跑印证；「日志面板」ledger 在档（§四）。
2. **格 1 语义断言组合**（schema default 五动作+格 11 运行回落直证）：接受——schema-backed 空卡=增量存储设计语义，与「五动作可见」措辞的偏差按设计如实断言、不虚报，组合证据闭环。
3. **格 8 嵌套路径 no-such-field**：接受为 ⚪ 挂账——顶层 `actions` 整列表路径已验（改绑工作流不受影响）；深层索引路径（`actions.0.bindings.4.deadzone`）get/set 一致性属 definition_assets 通用面，**评：一行修复价值有限**（编辑器卡片 UI 走整值编辑不经索引路径；BRP 直驱场景可用整列表），挂 open-challenges 由 definition-assets 域统一处理，不单独立项。
4. **roadmap 勾选留主控**：程序姿态正确（报告为依据、勾选归主控）——本报告 §六给出明确建议。

## 四、backlog ledger 核实——3 条在档+1 条漏写（⚪）

`open-challenges.md`（5fd729a3 diff 核实）补入 input-actions 三条：schema watcher 初始刷新（idle≠kinds）、PIE 游戏日志面（日志面板）、stop 关卡残留多路径。**第四项「实体手柄复验」未入 ledger**（挂账散在 t09-t2-qa.md §三③/T3 报告格 6/方案 backlog 表）——⚪ 记档：建议主控顺手补一行到 open-challenges（硬件依赖项），不阻塞 T09。

## 五、工程处置核实——合规

程序已删 `t09t2-game`（报告偏差 5+重建法注明 `jd new t09t2-game --path H:\workspace_AI\t09t2-live`——QA 复跑实测重建法有效（含 lock 快照秒级））；QA 复跑后再次清理（`H:\workspace_AI\t09t2-live` 已删；遗留的 t09t2_guards1.log/t09t2_probe.rs 为历史证据文件保留）。无残留进程、无残留 fixture。

## 六、T09 放行清单

| 项 | 状态 |
|---|---|
| T0（环境结论） | 完成（环境归因修正：dll 失配可重编排除；两项 T08 补验在 T2 轮销案） |
| T1 | QA PASS（t09-t1-qa.md） |
| T2 | QA PASS（t09-t2-qa.md，含 T08 补验收口） |
| T3（本报告） | VERDICT 见末行 |
| 验收句「Move/Look/Jump/Interact/Pause 可配置生效」五动作格证 | Move=格 2（改键 dz 实证）+11（默认复活）；Look=格 4（yaw -0.841）；Jump=格 3（LMB 盘上+链+钉）；Interact/Pause=格 5（默认表+转发+钉）+格 9/10（Pause 的 Esc 捕获语义双向）；手柄源=格 6（合成链红绿）——**五动作三源各有格证** ✅ |
| 「不与编辑器键位混用」双向铁证 | 格 9（捕获：编辑器压制+游戏收到）+格 10（未捕获：编辑器收到+游戏收不到）——QA 独立复跑双双 PASS ✅ |
| buglist | 无打钩项（本轮无 I/W 系修复，一致） ✅ |
| roadmap T09 勾选 | **建议：合入 T3 后由主控勾选**（验收句两铁证全部落证+QA 独立复跑复现） |

**T09 可勾选建议：可以勾选**——四任务全 PASS、五动作三源格证齐、混用双向铁证、backlog 在档（一项漏写 ⚪ 补）、工程清理完毕。

## 七、结论

QA 矩阵 12/12 独立复跑全 PASS（重点 4 格数字级复现，auto_release 坑未触碰）；门禁六件复核干净（journal flaky 处置三档合规、doctests 归档矛盾由 QA 单验补全+⚪ 记录）；偏差 4 条裁定齐（全接受、格 8 挂账评一行修复价值有限）；backlog 3+1 核实；工程处置合规。

VERDICT: PASS（T09-T3 验收通过、**T09 整体建议勾选**——建议主控 --no-ff 合入 5fd729a3 后勾选 roadmap T09；补记：open-challenges 实体手柄一行、doctests flaky 建议某任务根治（T08 轮已提，第三次出现））
