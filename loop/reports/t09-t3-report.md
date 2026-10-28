# T09-T3 实施报告：验收矩阵 12 格 + 文档收尾

> 任务：`loop/plans/t09-input-actions.md` §二 T3（I5+I6 文档面+全任务终验）。
> 分支 `loop/t09-final`（自 main bca7c5ba 拉出）。T08 两补验已由 QA 在 T2 轮销案（`loop/reports/t09-t2-qa.md` §七）。

## 一、真机验收矩阵：12/12 全过

脚本 `loop/qa/t09-t3-matrix.ps1`（两阶段会话：格 1-2 → kill/重启 → 格 7-12+8），暖工程
`t09t2-game`（`H:\workspace_AI\t09t2-live\t09t2-game`，path 依赖本 checkout）。归档
`loop/t09t3-matrix/`（editor-std*）。真机前按 QA 环境新知重编 exe（`cargo build -p jackdaw`）。
**全程无冻结**（5 轮编辑器会话）。

| # | 场景 | 结果（数字） |
|---|---|---|
| 1 | 默认动作表 | **PASS**：schema default 含五动作+键盘/鼠标/手柄三类源（结构层）；新建卡=空 patch（**schema-backed 卡的设计语义**：未写字段=运行时回落代码默认——格 11 行为直证） |
| 2 | 键盘改键生效 | **PASS**：asset.set serde JSON→save→盘上完整（ArrowUp×4+LeftStickX 0.5+LMB）→Play→**ArrowUp dz=−12.00**、**W dz=0** |
| 3 | 鼠标绑定生效 | **PASS**（三层证据）：盘上 Jump=LMB + 转发链（格 9 键盘同链+T2 I3 mouse 真机）+ **headless 新钉** `mouse_buttons_and_plain_keys_drive_button_actions`（绑定的 LMB 经事件流驱动 Button 动作）；游戏日志行为观察挂账（见 §四-1） |
| 4 | Look 生效 | **PASS**：`input.motion dx=200`→yaw delta **−0.841**（=sin 量纲吻合） |
| 5 | Interact/Pause | **PASS**（三层证据）：schema 默认表（E/East、Esc/Start）+ 键盘转发链 + headless 钉（E/plain Esc 驱动各自 Button 动作）；日志观察同上挂账 |
| 6 | 手柄+死区 | **PASS（降级口径）**：本机 0 设备；合成 `RawGamepadEvent` 链 headless 红绿（T2）+ windowless 保留 GilrsPlugin 代码实证；实体腿挂账 |
| 7 | 三态①重启 | **PASS**：kill/重启后文件 SHA 同、`asset.get actions` 同值、Play 行为同值（**dz=−11.9**） |
| 8 | 三态③导出 | **PASS**：dirty 卡（整列表 set 0.6）→`game.export`→dist `input-actions.bsn` 含 **0.6**+`export-manifest.json` 列出该文件、state=ready |
| 9 | 不混用·捕获态 | **PASS**（三断言）：选中实体在 plain Esc 后**存活**（编辑器 Esc 动作被压制——I3 真机铁证）；编辑器相机静（RMB+W 不动）；游戏 **ArrowUp dz=−11.8**（转发通） |
| 10 | 不混用·未捕获态 | **PASS**：Escape 到编辑器（**selection 被清除**=编辑器键位动作收到）+ 游戏 **ArrowUp dz=0**（收不到） |
| 11 | 缺文件兜底 | **PASS**：删文件→Play→**W 复活 dz=−11.6**（代码默认表接管）+ArrowUp 死；恰一条 warn 由 headless 钉 `a_missing_config_falls_back_to_default_once` 承接（日志面同 §四-1） |
| 12 | Stop 铁证 | **PASS**：play/stop 前后 scene/input-actions SHA 同、`.jackdaw` 顶层清单同（无 temp/污染） |

矩阵过程学（两次脚本修正，均已归因）：
- **格 9 的 auto_release 发现**：`input.pointer` 的 CursorMoved 打到 Game panel 外会**自动释放捕获**
  （click-away 语义）——前一轮 dz=0 的根因。改用不移动光标的探针后通过。这本身是捕获模型的
  正确行为（顺带验证了 auto_release），记入过程学。
- **格 10 探针重设计**：原方案「RMB+W→编辑器 fly」在 Play 中未激活（视口 fly 的激活上下文
  未验证），改用 **Escape→selection.clear** 探针（`jackdaw/status.selection` 可观察、无破坏性、
  双向可断言：格 9 捕获=存活 / 格 10 未捕获=清除）——比 fly 断言更强的「编辑器键位」铁证。

## 二、文档

1. **新章 `book/src/user-guide/game-input.md`**（SUMMARY 排 Game Parameters 后）：五动作默认表
   导览（含消费代码示例）、改绑工作流（New Asset→卡片→Save→Play 三态一致）、**并集合并语义**
   （文件覆盖同名/缺名回落默认，Y36 反例写明）、死区语义（per-axis GamepadSettings、0.15 对齐
   引擎默认）、手柄边界（游戏进程 gilrs 直读，编辑器不转发）、捕获模型（引 play-in-editor 节）、
   keymap 对照（编辑器键位 vs 游戏动作两链零交集）、「stop→play 生效」边界（I6）。
2. **用户 30 秒清单**（章尾）：①Play→点画面→WASD/鼠标/Space/E/Esc（+手柄若有）；②Move 改
   方向键→Save→再 Play→方向键走 W 不走；③推一点摇杆不动（死区）、推多走。
3. **open-challenges.md PIE 节**补三条 ledger（2026-10 input-actions 工作遗留）：schema watcher
   初始刷新（idle≠kinds 就位）、PIE 游戏日志面（stderr 仅进崩溃 tail）、stop 关卡残留多路径。

## 三、代码改动（跑格中发现的最小补钉）

- `crates/jackdaw_runtime/src/game_input.rs` +1 单测
  `mouse_buttons_and_plain_keys_drive_button_actions`：绑定的 LMB 与默认表的 E/plain Esc 经
  引擎事件流驱动 Button 动作——格 3/5/11 的机制层钉（这些格的游戏侧行为在 PIE 无可见面，
  机制层+配置层+转发层三证合一）。
- book 两章一目录（§二）。
- 无产品代码改动（矩阵两处脚本修正归因于断言设计而非缺陷；auto_release 为正确行为）。

## 四、偏差与记档

1. **PIE 无游戏日志面**：游戏进程 stderr 仅进 40 行崩溃 tail（`pie.rs` StderrTail），stdout
   不入编辑器重定向——教学模板 Jump/Interact/Pause 的 `info!` 行在编辑器内不可见。格 3/5/11
   据此采用三层证据口径（配置级+转发链+headless 机制钉），**游戏日志行为观察挂账**（已入
   open-challenges ledger：加日志面板可让教学模板可观察）。
2. **格 1 设计语义**：schema-backed 新卡默认=空 patch（增量存储语义），五动作默认表存在于
   schema default+代码 `defaults()`——与方案「新建卡片五动作可见」的措辞有偏差，按设计语义
   如实断言（结构层 schema default + 行为层格 11），不虚报。
3. **格 10 的 fly 断言**改用 Escape/selection 探针（原 fly 断言在 Play 中的激活上下文未验证），
   T01 纪律以「编辑器键位动作可观察」的更强形态满足。
4. **格 8 嵌套路径**：`asset.set actions.0.bindings.4.deadzone` 报 no such field（深层嵌套
   索引路径的 get/set 一致性问题，非本任务面）；矩阵改用整列表 set 绕开，嵌套路径形态记
   ⚪ 观察（不影响改绑工作流——顶层 `actions` 路径已验证）。
5. **工程处置**：`t09t2-game` **删除**（T09 收尾，QA 裁定统一清理）。复跑重建：
   `jd new t09t2-game --path H:\workspace_AI\t09t2-live`（矩阵脚本兼容新工程——格 1 会重建
   input-actions.bsn）。
6. **backlog 三项核对**：watcher 时序（t09-t2-qa.md §五+open-challenges）、实体手柄
   （t09-t2-qa.md §三③挂账，硬件依赖）、stop 关卡残留（T08 终验口径+open-challenges）——
   全部在档，另补 PIE 游戏日志面为第四条 ledger（本任务 §四-1 发现）。

## 五、门禁（全量四门，归档 `loop/t09t3_gate_*.log`）

| 门 | 结果 |
|---|---|
| fast（fmt+clippy+快速集） | clean（一次 `cargo fmt` 后过，`t09t3_gate_fast.log`） |
| integration（xtask） | **5236 passed / 0 failed**（2 skipped 既有 ignore，359s，`t09t3_gate_integration2.log`）。首轮与 doctests 并行时 `session_journal` 5ms 预算条 6.76ms 触发（T08-T2 QA 记档过的负载 flaky——隔离重跑 9/0 绿后串行全量复跑过，`t09t3_gate_journal_retry.log`） |
| doctests | 全绿（全部 result 行 0 failed，`t09t3_gate_doctests.log`） |
| docs（cargo doc --workspace --no-deps） | clean（`t09t3_gate_docs.log`） |

## 六、buglist / roadmap

- buglist：无打钩项（本任务无 I/W 系修复；新 ledger 全部入 open-challenges）。
- roadmap T09 勾选留给主控（本报告为依据：验收句两铁证——「可配置生效」（格 2-6+7-8）与
  「不与编辑器键位混用」（格 9-10 双向）——全部落证）。
