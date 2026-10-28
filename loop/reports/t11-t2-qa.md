# T11-T2 QA 验收报告：参数面+编辑器摆放链真机（只验不修）

> 验收对象：分支 `loop/t11-params`（**零提交验证型任务**，与 main **fad046ce** 同点）。
> 证据：程序 `loop/reports/t11-t2-report.md`+`t11t2_*` 归档（reports 实存 **11 件** log）
> +`loop/qa/t11t2-*.ps1` 脚本 10 件+`loop/t11t2-live/` 真机日志 20 件。
> QA 独立证据：`loop/qa/t11t2-qa-live-c-console.log`（七行为复跑全文）、
> `loop/qa/t11t2-qa-param-editor1/2.log`（QA 编辑器会话）、
> `H:\workspace_AI\t11-live\qa\`（qa-param/qa-param-reopen/qa-c11-probe 三个 bsn）、
> Windows 事件日志 5 条 WER 记录（本报告 §四内嵌）；程序轮 live 证据已先备份
> `loop/t11t2-live/t11t2-{b,c}-summary-prog.bak.txt` 等（防复跑覆盖）。

## 一、零改动声明核实——成立

- `loop/t11-params` 与 `main` 同点 fad046ce，**零提交**；`git diff main..loop/t11-params --stat` 输出为空。
- 工作区仅既存噪音两条：`.gitignore` M、`buglist.md` 未跟踪——与 T1 QA 开局自检一致。
- 「loop/ 被 exclude」属实：`.git/info/exclude` 第 10 行 `loop/ `（loop 产物不进版本库）。
  由此报告 §九「提交：显式 pathspec——…」与实际**零提交**不符——exclude 挡住 `git add`
  后措辞未更新（⚪ 记档，主控任务书已按零提交预期验收，无实质影响）。
- 门禁面：`cargo fmt --all --check` QA 亲跑 **CLEAN**（exit 0）；fast 归档复核
  `Summary [43.570s] 2961 tests run: 2961 passed (1 leaky), 2 skipped` 与 T1 基线逐位一致；
  零提交分支的代码与 T1 QA 已亲验的 fad046ce（fast 2961+clippy 物理双包）完全同点，
  其余三门等价成立。

## 二、摆放链独立复跑（验收句核心）——PASS，七行为 QA 单轮一次全绿

用程序沉淀脚本 `loop/qa/t11t2-live-c.ps1` 原样复跑（编辑器摆放场景
`t11t2-place.bsn`→注入 PlayerVelocity→direct run 游戏侧驱动；真机 start /B、
未设 WGPU_BACKEND、exit 0 零崩溃、跑后进程清零）：

| 腿 | QA 复跑数字（单轮） | 程序归档 | 判定 |
|---|---|---|---|
| C1 落定 | placedPlayer y=0.860、模板玩家在场、placed rig 物化+active | 同 | PASS |
| C2 走墙停 | z 1.697→…→−2.440 **−2.440 冻结** | −0.52→…→−2.440 | PASS |
| **C5 跟随**（必含） | local off (0.00,3.15,4.61)→(4.61,3.15,0.03)，\|.\| 均 **5.578**，**lenDrift=0.000**（distance-5 理论 (0,1.2+5sin0.4,5cos0.4) 精确命中） | 同（0.000） | PASS |
| C3 跳 | apex **1.993**（理论 1.892±0.3）、落地 0.860 稳定 | apex 2.007 | PASS |
| **C4 贴墙滑** | x 2.40→4.24 travel **1.84 m**、z 钳 **−2.440** | travel 2.20、−2.440 | PASS |
| **C6 半速**（必含） | placed **1.65 m/s**（authored 2.0）vs template **3.31 m/s**（4.0），比值 0.499≈0.5 | 1.62/3.25 | PASS |
| C7 哑相机 | strip ActiveCameraRig 后 placedRig active=False materialized=False（模板 rig 同哑，race 形态记录）；玩家仍被驱动 z **2.00→−0.43** | 同 | PASS |

三个必含腿（半速对照/相机跟随 drift=0/滑墙）全部独立复现，且第三腿选了程序侧
最有疑点的 C4（见 §六-QA1）。

**程序侧证据链疑点与裁定（⚪QA1）**：程序归档的两份 c_console（reports 与 live 同
内容）以 `GAME_BOOT_FAIL` 结尾（round 2 strip 后重启遇「另一个程序正在使用此文件」
——QA 复跑时亲历同款文件句柄竞态，**非产品缺陷**）；而 summary
`C4_SLIDE=False … C7_DEAD=True` 来自**另一轮 console 未存档**的运行。即程序报告
§一引用的七行为证据**跨两轮拼贴**（C1-C6 数字取自 GAME_BOOT_FAIL 轮、C7 结论取自
summary 轮），最终 summary 轮的 C4 FAIL 未在报告披露。裁定：QA 单轮全绿证明行为
断言本身真实稳定，程序结论成立；证据呈现口径记 ⚪（失败轮 console 未存档+跨轮
拼贴未披露）。

## 三、参数三态独立抽验——PASS（QA 分步交互链，含 C11 精确化）

QA 在独立编辑器会话（冷启动 start /B、BRP 15806）分步执行，全部保存走 QA 专属
绝对路径（源 `assets/t11t2-place.bsn` 零污染，保存后核验仍为程序留下的
move_speed=2.0/jump_speed 缺失态）：

| 步 | 操作 | 结果 |
|---|---|---|
| P1 编辑态 | `component.set` jump_speed=**6.0**（非默认值） | finished、零 warning、undo_len 0→1（T02 单记录语义顺带复核） |
| P1 盘上态 | `scene.save {绝对路径}` | 盘上 `move_speed: 2.0, jump_speed: 6.0` 双双落盘 |
| P2 再编辑 | `component.set` move_speed=**3.0**（只动这一个字段）→save | 盘上 `move_speed: 3.0, jump_speed: 6.0`——**未编辑的非默认兄弟字段保留** |
| P3 冷重启 | 杀编辑器→冷启动→`scene.open` QA 文档→save 第二文件 | `move_speed: 3.0, jump_speed: 6.0` 双保留 |

三处一致（编辑→盘上→重开）独立成立；运行态（Play 行为）由 §二 C6 半速腿承载
（同一场景文档同一 authored 参数）。CameraRig distance=5.0 在各轮盘上块中同步可见。

## 四、PIE 环境事件声明抽验——声明成立（3/3 崩，WER 签名与 T10b 逐字一致），N13 挂账维持

QA 独立抽验 3 次 PIE play（start /B 启动编辑器、RUST_BACKTRACE=1、默认 windowless
×2 + `pie.window_mode_toggle` windowed ×1）：

| # | 形态 | 结局 | 时序 |
|---|---|---|---|
| 1 | windowless | **exited before connecting, exit code 0xc0000005** | launched 后 ~7.5s |
| 2 | windowless | 同上 0xc0000005 | 同量级 |
| 3 | windowed | 同上 0xc0000005 | 同量级 |

**3/3 全崩、零 connected**——程序「PIE 全形态 100% 崩（≥10 play）」声明独立成立。
事件日志对照（Get-WinEvent Application Id=1000，本轮窗口 5 条，格式：全角冒号）：

```
出错应用程序名称： t11t1-game.exe   出错模块名称： nvcuda64.dll，版本： 32.0.15.9186
异常代码： 0xc0000005   错误偏移： 0x00000000003ab984   （5/5 条全同）
路径： H:\...\t11t1-game\.jackdaw\target\game\debug\t11t1-game.exe
模块： C:\Windows\System32\DriverStore\...\nvcuda64.dll
```

与 T10b 裁定签名 **nvcuda64.dll@0x3ab984（驱动 591.86，RTX 5070）逐字一致**——驱动态
持续，T10b 环境归因口径再次自洽；同时 direct run 同 exe 同场景在 QA 两轮（live-c
round1/round2）零崩，「PIE 进程创建形态特异性」旁证。**N13 状态：connected 从未
发生→drain panic 观察窗不存在→×10 复发率测定维持挂账**（不可达，非「窗口恢复」；
恢复后建议按 T10b 挂账合并跟踪，脚本 `t11t2-n13.ps1` 已备可直接跑）。

## 五、C10/C11/C12 分级裁定

| 编号 | 程序定级 | QA 裁定 | 依据与处置建议 |
|---|---|---|---|
| **C10** 文档口径缺口 | 🟡 | **🟡 维持** | 源码级核实：模板 `lib.rs.template` L277-280 doc 原文只说「add `PlayerMarker` and `PlayerController` to any entity」；**PlayerVelocity 在整个模板 doc 零出现**（纯运行态组件，仅 spawn 代码插入）；L99-132 Player controller 导览段讲物理机制但无组件清单。真机行为差已证（程序 A4：照 doc 摆的玩家 y=1.000 悬空+零位移；注入 PlayerVelocity 后七行为全绿——QA C 轮同链复现）。**处置：T3 book player-controller 章+模板 doc 双处补「物理四件套」指引（或 move_player 改 Required/按需插入——程序裁量），维持记档不修**。验收句「摆放链」的直接威胁成立但 C 腿注入链已证机制无碍 |
| **C11** patch 丢字段 | 🟡 | **🟡 维持（实锤）但危害描述需修正** | QA 定向复现（floor 实体）：`component.add PlayerController`→`set move_speed=7.0`→save→盘上块**只剩 `move_speed: 7.0`（jump_speed 消失）**——缺陷真实。但 QA 同时证明**触发窗口唯一**：①已被 set 过的字段在此后所有链路不丢（P2：非默认 jump_speed=6.0 + set move_speed → 保留；floor 二次 set → 合并 `{ms:7.0, js:8.0}`）；②文档加载态 set 单字段不丢（P1/P2）；③冷重启保留（P3）。**程序 §五「若 jump_speed 曾被改成非默认再编辑 move_speed，改值会丢」的担忧场景实测安全（P2 直接反证）**——丢的只是「从未被编辑过的默认值字段」（加载取 Default=同值，行为无感）。真实危害=文档完整性+Default 漂移二阶风险（模板 Default 未来改值时旧文档行为漂移）。**处置：建议立 buglist（A 节先例）+T3 顺手修（set 单字段从 schema 默认合并整组件再落 patch——程序方案可行），修复说明中修正危害表述** |
| **C12** 保存 skip 失效 | ⚪ | **⚪ 维持** | 源码级核实：`src/scene_io/mod.rs:72-97` SKIP_COMPONENT_PATHS 含 `jackdaw_camera_rig::ActiveCameraRig`+注释原文；L160-193 显示 skip 作用于 **world→text BSN writer**（`should_skip_component`/`editor_writer_config`）；而 `component.add` 的组件走 **document patch 通道**持久化（A3 `savedDocContainsActiveCameraRig=True` 在档）——patch 天然绕过 skip，「机制与注释不符」定性准确。Automatic 模式行为无害且恰是摆放链「手加标记→Play 即玩」的基础。**处置：T3 与 C9 book 章一并定案（skip 语义文档化或删 skip 行二选一），同意程序建议** |

## 六、QA 补充发现（⚪，全部不阻塞）

- **⚪QA1 C 腿证据跨轮拼贴**（§二详述）：summary 轮 C4_FAIL 的 console 未存档、
  报告未披露；行为结论经 QA 单轮全绿反证成立。A 腿 VERDICT 11 格 8 FAIL 的实况
  （PIE 死亡+C10 未发现前的行为崩+PS 数组转型 bug——C 腿脚本已修）亦未在报告
  文字直接呈现，但各 FAIL 归因在案、报告以「A1 构建+C 腿行为」拼接承载通道 2 的
  叙事自洽。
- **⚪QA2 归档件数差 1**：报告 §九称 `t11t2_*.log×12`，reports 目录实存 **11 件**
  （`Measure-Object` 清点）。证据链完整无缺件，计数误差。
- **⚪QA3 报告 §九「提交」措辞与零提交实际不符**（§一详述，exclude 所致）。
- **⚪QA4 boot 会话恢复便利**：QA 冷重启轮编辑器自动恢复上次打开的 QA 文档
  （status.scene 直指 qa-param.bsn）——编辑器会话恢复机制对验证链是便利非缺陷，
  QA 仍显式 `scene.open` 走完整链。

## 七、QA 过程记档（如实）

1. QA 参数腿长脚本 `t11t2-qa-param.ps1` 半途无输出（疑似 PS5.1 输出缓冲+BRP 长轮询
   黑盒化），终止后改**分步前台交互**完成同一断言链（P1/P2/P3/C11 全部数据在
   §三/§五）；脚本与 0 字节 console 留档 `loop/qa/`。PIE 腿脚本 `t11t2-qa-pie.ps1`
   沉淀未用（改逐轮手打+共享读轮询——`[IO.File]::ReadAllText` 独占打不开正被写的
   编辑器日志，改 `FileShare.ReadWrite` 解决；此坑即程序 live-c round2
   GAME_BOOT_FAIL 的同族形态，旁证其为文件句柄竞态而非产品缺陷）。
2. 冷启动一次顺序错误（env 在 start 之后设）→ 编辑器落默认端口，发现后杀掉按
   正确顺序重启，无副作用；另一次「另一个程序正在使用此文件」（刚杀进程句柄未
   释放）等待 3s 后重试通过。
3. 工程零污染：源 `assets/t11t2-place.bsn`/`scene.bsn` 未被 QA 改写（保存全走
   `H:\workspace_AI\t11-live\qa\` 绝对路径）；QA 跑后进程清零（jackdaw/t11t1-game
   均无）；live 目录程序轮 summary 已先备份防覆盖。

## 八、结论

- **验收面 1 摆放链**：QA 复跑七行为单轮全绿，必含三腿（半速 1.65/3.31≈0.5、
  drift=0.000、滑墙 1.84m/钳 −2.440）独立成立——PASS；
- **验收面 2 参数三态**：编辑→盘上→冷重启全链独立验证保留（含非默认值）——PASS；
- **验收面 3 PIE 声明**：3/3 崩+WER 五条 nvcuda64@0x3ab984 与 T10b 逐字一致——
  声明成立、归因口径维持，N13 ×10 挂账维持（观察窗不存在）；
- **验收面 4**：C10 🟡 维持（doc 缺口源码核实，T3 book+doc 双补）、C11 🟡 维持
  且实锤（窗口=add 后首次 set，危害描述修正后立账+T3 顺手修）、C12 ⚪ 维持
  （skip 只拦 writer 面、patch 旁路，T3 定案）；
- **验收面 5 零改动**：branch 同点零提交、diff 空、工作区仅既存噪音、exclude 属实——
  PASS；
- QA 补充 ⚪×4（跨轮拼贴/件数差 1/提交措辞/会话恢复便利），零新增 🔴🟡。

**VERDICT: PASS**

- 下游提醒（不阻塞）：①C11 修复时以本报告 §五 的窗口结论为验收基线（add→set→save
  不丢兄弟字段）；②N13 恢复复跑可直接用 `loop/qa/t11t2-n13.ps1`；③T3 book 的
  「类型面免费、行为面一行」口径（my-game：CameraRig=True/CameraLook=False）QA
  复核成立，照此写。
