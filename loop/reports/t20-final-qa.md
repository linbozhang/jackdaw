# T20 终验 QA 报告：任务 3（收官段）+ T20 整体终验（只验不修）

> 验收对象：分支 `loop/t20-example` @ **f637ed38**（基线 main=776639c5=T2 合入点；程序提交
> =T20-T3 收官；T1/T2 已分别于 0edf9536/2d4c19ce 完成并各获 QA PASS（t20-t1-qa.md、
> t20-t2-qa.md——T2 QA 附 6 条 errata，本轮逐条核落账兑现，见 §三-3）。程序报告：
> `loop/reports/t20-t3-report.md`。T3 diff 亲核（`git diff 776639c5..f637ed38 --stat` 全件）：
> **产品面=book 四文件（game-flow.md +98 行一大节三子节+audio/game-saves/game-ui 三处交叉
> 引用，SUMMARY 零 hunk 亲证）+loop/qa/t20-live.sh（E1/E6 脚本修复+box 恢复腿）+manual.md
> §7.5 两词+t20-t2-report.md Errata 落账+T3 报告与归档+loop/t20-live/ 证据刷新**——`src/`、
> `crates/`、templates、fork、协议、场景格式零改动（diff 文件清单 grep 该域路径零命中）；
> buglist/台账/roadmap 零触碰（diff 面零命中亲证，roadmap 第 34 行 `[ ]` 未勾=留主控正确）。
> QA 手段：**Mac 全量门亲跑**（后台链+轮询 10:32-11:04，全程未设 RUST_BACKTRACE，门链独窗
> ——本会话零编辑器/游戏真机腿，门前 df 37Gi/门后 37Gi）+ **关键格 console 原文全读**
> （t20t3_console-pure/box 提取件全文+append-only console 六轮头行可溯性亲数+七元组 10 件
> 终态块对读+pure-run.log/otool 双件/m13-regen/manifest 亲读复算+pure-window.png 人眼亲核）
> + **脚本面亲读**（t20-live.sh 的 E1/E6 修复、lane retry 恢复腿、NOT-SAMPLED best-effort、
> calibrate 还原、box scratch 重置逐处对源）+ **book 逐句对锚源码**（胜局臂/OnEnter 常生/
> existing 守卫/physics 总闸/dylib 拒绝门/资产根回退链六锚亲读）+ **Errata E1-E6 实证核**
> （脚本修复在终态 console 的活体效果逐行指认）+ clippy 双包/doctests/程序 fast+integration
> /docs/scaffold_e2e 归档抽核 + **A6 隔离腿亲跑 3/3**（本轮 QA integration 该件三试尽红后的
> 定案口径对照腿）。
> QA 归档 `loop/reports/t20t3_qa_*` 十一件（八门 log+exit 台账+门链脚本+A6 隔离复跑 log）。

## 〇、结论

**PASS（T20-T3 收官 + T20 整体，含 roadmap T20 可勾选建议）**——门禁 QA 独立复现：fmt 零
Diff、libtests **3002 passed/0 failed**（58 条 result 行逐行求和亲算，scaffold `running 92
tests`→**92 passed**=teaches 92 达标）、fast **3002/3002**（30.2s）、audio_gate **7/7**、
save_store **19/19**、docs **EXIT=0 且 17 行 warning 面与程序归档/T17/T19 基线同面**（13 条
实体警告 jackdaw 10+api_internal 1+project_build 1+remote 1+4 行包级汇总）、scaffold_e2e
**1/1**（150.8s）；**integration QA 亲跑 5458/5459**——唯一红=A6 家族
`prefab_file_change_triggers_reload` **三试尽红**（8.1/10.3/8.9s），**隔离复跑 3/3 绿**
（~1.5s×3，归档在案）=A6 定案口径（存量基建票/满载挤压/隔离绿）如实兑现，**0 新增红**；
程序轮同门 5459/5459（flaky TRY 3 PASS 重试预算行使过）两轮互证。关键格终态亲读：M12 纯包
隔离 **9 腿全 PASS**（export_wait 推进 `idle -> 1793494272`、env -i 白名单+cwd=/tmp 异目录
60s 存活×4、菜单渲染截图人眼亲核、stdout info=7/panic=0、warn clean、对照组=编辑器静态味
linkage 审计承载）+M13 四件 **QA 复算全过**（otool 非系统链库=0、LC_RPATH=0、树+manifest
零 dylib、重生成 9==9 逐字节等）；M2 全环合链×3 **11 腿全 PASS**（FRESH OK×7 判定行亲数、
runs 绝对口径 0→1→2→3、真机危害 hit 100→85×3、撞墙截断 d23=0.0000、拾取 0→2+HUD 文本、
loop-1 lane retry 恢复腿按设计行使）；M3 胜局 **全链亲读成立**（count 2→3、win blip
volume=1.0、flow GameOver、stdout `Level clear! All 3 pickups collected.` 直证、runs 4→5、
Restart 七元组 FRESH）——`win blip NOT-SAMPLED`+best-effort 形态在轮 5 console 亲见=设计内
口径；box 六轮收敛在 append-only console 六条 `=== phase` 头行**逐轮可溯**（E1 修复实证）。
book 扩节对锚全过（三子节+度表七层+EG2/EG5/EG6 诚实边界+A16 注记逐字+30 秒清单胜局句+
三交叉引用双向落位，六源码锚亲读）；**Errata E1-E6 全落账亲核**（E1/E6 脚本修复实证生效）。
验收句「开始菜单+玩家移动+碰撞+拾取+胜负+音效+重开」「新建工程主要靠编辑器配置完成」
「可独立导出运行（无工具链环境）」逐词证据在案（§五）。**EG1 吸收闭合、EG2-EG6/EG8 边界
兑现**。**偏差 0 🔴 + 0 🟡 + 8 ⚪/M（§六）**——全部为口径执行/记档精度/台账残留级，不动摇
裁决。

## 一、Mac 全量门亲跑（权威口径，最终树 f637ed38；门链独窗，未设 RUST_BACKTRACE）

门前 df 37Gi；门后 37Gi（无 A6 泄漏）。逐门 START/END 时序+exit+逐门 df：
`t20t3_qa_gates_exit.txt`（fmt 10:32:36 → scaffold_e2e 11:04:41）。

| # | 门 | 命令 | QA 亲跑结果 | 归档 |
|---|---|---|---|---|
| 1 | 格式 | `cargo fmt --all -- --check` | **EXIT=0**（0 字节=零 Diff） | t20t3_qa_fmt.log |
| 2 | 单测 | `cargo test --workspace --lib` | **EXIT=0；3002 passed / 0 failed**（58 条 test result 行逐行求和亲算）；**scaffold `running 92 tests`（:2686）→ `92 passed`（:2780）亲点**——teaches 92 与 T1 计数三源互证一致 | t20t3_qa_libtests.log |
| 3 | fast | `cargo xtask fast` | **EXIT=0；Summary 3002 tests run: 3002 passed, 0 skipped（30.2s）** | t20t3_qa_fast.log |
| 4 | audio_gate | `cargo nextest run --profile ci --test audio_gate` | **7/7 PASS**（3.4s）EXIT=0 | t20t3_qa_audio_gate.log |
| 5 | save_store | `cargo nextest run --profile ci -p jackdaw_runtime --test save_store` | **19/19 PASS**（0.1s）EXIT=0 | t20t3_qa_save_store.log |
| 6 | **integration** | `cargo xtask integration` | **EXIT=1；Summary [853.2s] 5459 tests run: 5458 passed (1 slow), 1 failed, 0 skipped**——唯一红=A6 家族 `prefab_file_change_triggers_reload`（TRY 1/2/3 全 FAIL：8.1s/10.3s/8.9s）；**QA 隔离复跑 3/3 PASS**（`-E 'test(prefab_file_change_triggers_reload)'`：1.587s/1.459s/第三跑 PASS，双跑全文归档）——**A6 定案口径如实兑现**（满载 watcher 挤压/隔离绿=存量基建票非产品缺陷，T13 四腿闭合链+T19「红时按隔离复跑对照」口径），**0 新增红**；程序轮 5459/5459（TRY 3 PASS）与本轮 5458/5459（三试尽红→隔离绿）两轮互证 flaky 双形态 | t20t3_qa_integration.log + t20t3_qa_integration_isolation_rerun.log |
| 7 | docs | `cargo doc --workspace --no-deps` | **EXIT=0**；warning 面 **17 行**（grep `^warning` 亲算）：13 条实体（jackdaw 10+api_internal 1+project_build 1+remote 1，private-doc-link 家族+`StateEvent::Log`）+4 行包级汇总——与程序归档逐行同面、T17/T19 基线同数同族（零 src/ 改动预存树态） | t20t3_qa_docs.log |
| 8 | scaffold_e2e | `cargo nextest run --profile ci -E 'binary(scaffold_e2e)'` | **1/1 PASS**（150.8s 冷编）EXIT=0 | t20t3_qa_scaffold_e2e.log |

**clippy 双包/doctests（采信归档抽核，T18/T19 先例口径）**：`t20t3_gates_clippy_phys.log`/
`t20t3_gates_clippy_ws.log` 抽核通过——`^warning|^error` 行计数 **0**（grep 亲算），物理双包
`Checking jackdaw_physics`+`Checking jackdaw_avian_integration`+`Finished` 在档、全仓
`Finished`（22.9s）；程序 exit 台账 clippy_ws/clippy_phys EXIT=0（09:58:56/09:59:09）。
`t20t3_gates_doctests.log` 主跑仅 `-p jackdaw_bind --doc` 处 dyld 家族失败
（`Library not loaded: @rpath/libstd-614bb9b33bbc23af.dylib` 原文在档——**第 13 次目击**，
T17 第 10/T18 第 11/T19 第 12 同族同签名，T15 定案环境票）+`t20t3_gates_doctests_bind_
rerun.log` 单包复跑 **`test result: ok. 1 passed`（EXIT=0）**——双 log mtime 顺序可追，采信。

**程序归档交叉复核**：`t20t3_gates_fast.log` Summary 3002/3002（28.1s）、
`t20t3_gates_integration.log` Summary 5459 run: 5459 passed (1 slow, 1 flaky)——flaky 件
TRY 1 FAIL→TRY 2 FAIL→**TRY 3 PASS**（FLAKY 3/3 行亲读，重试预算行使过）；exit 台账九门
（fmt/clippy_ws/clippy_phys/libtests/fast/integration/doctests=101/docs/scaffold_e2e）与
T3 报告 §四逐项一致；`t20t3_gates_docs.log` 17 行与 QA 亲跑同面。无隐瞒。

## 二、关键格复核（三格证据原文全读+append-only 可溯性+口径核）

### 1. M12/M13 纯包隔离+静态审计（pure 相一次全绿，console-pure.log 全文+盘面亲验）

- **九腿 PASS 判定行逐行亲读**：M12_ASYMMETRY_CONTROL（对照组=编辑器 E4 后静态味，dylib
  不对称无从演示，linkage 审计对照承载——T2 同口径如实）→ M12_PURE_EXPORT_READY
  （export_wait `run advanced (idle -> 1793494272) and is ready`=started_at 推进防树预满足）
  → M13_OTOOL_LIBS/RPATH/NO_DYLIB_ARTIFACTS/MANIFEST_REGEN → M12_ENV_I_ALIVE（t+15/30/
  45/60 alive×4）→ M12_PURE_WINDOW → M12_PURE_LOG_CLEAN（info=7 panics=0）→ VERDICT/RESULTS
  九腿全 PASS。
- **M13 QA 复算（不采信脚本计数）**：`t20t3_otool-L-pure.log` 全文亲读——LC_LOAD_DYLIB 全集
  =`/usr/lib/libc++.1.dylib`、`libSystem.B.dylib`、`libobjc.A.dylib`、`libiconv.2.dylib`
  +`/System/Library/` 十四框架（AppKit/Foundation/CoreGraphics/Metal/…），**零 rustup/
  Homebrew/`/Users/` 路径**；全部 34 条 load command **零 LC_RPATH**（QA 亲数；编辑器对照件
  `loop/t20-live/otool-L-editor.log` 同零，双件 grep 复核）；`t20t3_m13-regen.txt`
  `REGEN_COUNT 9 SHIPPED_COUNT 9 / REGEN_EQUAL`；`t20t3_manifest-pure.json` 9 文件（8
  assets+exe）。**四件全过属实。**
- **pure-run.log 原文亲读**：7 行 INFO（SystemInfo→Ctrl+C 跳装→AdapterInfo Metal→GPU
  clustering/preprocessing→**window `t20-game` 创建**→**catalog 解析到 pure 包自身目录
  `…/loop/t20-live/t20-game-pure/assets/catalog.bsn`——资产根 exe 目录回退链活体**）+4 行
  WARN（no-config×3+terrain no-Camera3d=模板已知面，T2 QA 同族归因）+**panic=0**。
- **截图人眼亲核**：`t20t3_pure-window.png` QA 亲看——纯包窗口标题 t20-game+**「T20 Game」
  「Runs: 0」「Start」三件完整可读**（一枚 macOS TCC 弹窗遮挡中上部，三件要素在其下方清晰
  在场，与 T2 同形）——**菜单渲染实证成立**。
- **隔离断言本体**：env -i 白名单（HOME/PATH=/usr/bin:/bin/TMPDIR，DYLD_*/RUST_*/CARGO_*
  全清）+cwd=/tmp 异目录（脚本 ：994-995 亲读）——「无工具链环境」本机机械代理维持事实九
  上限；真·无工具链抽查在用户 30 秒清单（§八）。

### 2. M2 全环合链×3（box 相终态轮 11 腿 PASS，console-box.log+七元组件对读）

- **三环结构亲读**：每环 `M2_LOOP_k`+`M2_TUPLE_RESET_k` 双腿；**FRESH OK 判定行亲数=7**
  （entry-1/2/3+post-1/2/3=M2 的 ×6+post-m3 归 M3 行——与报告「×6+Restart 七元组 FRESH」
  计数法吻合）；七元组字段逐项对读（health 100/100、pickups 0、pos (-2.0,0.86,0.0) 出生
  点、props 3、MenuBgm ABSENT、Ambient spatial 在场、runs 绝对口径 0→1→2→3 每环真 +1=
  每环死亡真发生）。
- **真机危害 hit ×3**：`real hazard hit -> health=85.0 (want 85)` ×3——poll-driven W hold
  直到 `health<99.9`（hazard_damage 实触非注入）；dirty 七元组件亲读血量 10→0 两段+props
  3→2→1→0 实 despawn。
- **撞墙截断**：`M2 walk: at wall … -> … -> … (d12=-0.1122 d23=0.0000)`——北墙面前 z=-2.44
  capsule 停驻两拍零位移（A2 推箱边界未断言「推动」，口径守住）。
- **拾取 0→2+恢复腿**：count=2+props_left=1+HUD 文本 "Pickups: 2" ×3；loop-1
  `collect under-shot (count=1) — lane retry`+`retry rest pos=(-0.6438, 0.2558)`→count=2
  ——**恢复腿设计内**（脚本 ：1186-1193 亲读：count=trigger-ENTER，从重钉点重走车道必穿盘
  缘 z≈0.29，穿越即收集；T3 报告 §五.2 预告的 QA 复跑形态），勿当红。
- **walk_calibrate 考古修复活体**：`measured at move_speed 0.5 (restored to 4.0)` 两处在
  终态 console（E4 家族 walk 速度考古的修法实证；pie/export 相显式 0.5 的分工在脚本
  ：574 注释亲读）。

### 3. M3 胜局（EG1 决策 1-A 的终态真机正主）

- **count 链**：boot mirror runs=4（=M2 三死+M5 menu door 半边一局，T2 QA 算术链沿用）→
  `final dive onto @1 (count 2 -> 3, the win fires mid-hold)`→**count=3**。
- **win blip volume=1.0**：终态轮 dive 窗采到（`blip-volume.txt`=1.0 盘面亲读）；
  **NOT-SAMPLED 形态亲见=设计内**——轮 5（09:42）console 原文
  `M3: count=3 win blip volume=NOT-SAMPLED`+best-effort 注记行+`M3_WIN_PASS`（脚本
  ：1338-1340 亲读：采样窗未中按 QA 交接口径记 best-effort，判定承载=count/flow/stdout/
  runs+M4 同款三组件活采），与 T3 报告 §六.2 预告逐字相符——QA 复跑再现此形态不败格。
- **流转正主**：GameOverRoot 在场+`flow_wait GameOver`（flow 断言走文档根标记=A16/EG8
  口径，manual.md §7.5 在案）→ runs 4→5（`post-m3` 七元组 runs_played=5 亲读）——胜局恰
  计一局；Restart→post-m3 FRESH（health 100/100、props 3、pos 出生点）。
- **stdout A5 绕行**：`loop/t20-live/direct-m3win.log:17`
  `INFO t20_game: Level clear! All 3 pickups collected.`——direct run stdout 直证不经
  pie_log（A5 口径）；scaffold 胜局臂 ：3195 同文亲读（源码锚 §三）。

### 4. box 六轮收敛的 append-only 可溯性核（E1 修复实证）

`loop/t20-live/console-box.log` 亲数：顶部=T2 时代终态轮（与 `git show ef006650` 尾部逐字
同文=append-only 跨任务完整性）+**六条 `=== phase box run` 头行**（09:03:01/09:15:57/
09:23:31/09:30:43/09:42:04/09:50:39）——每轮 RESULTS 行亲读，与 T3 报告 §三四根因表**逐轮
对得上**（轮 1=M2 三环+M3 FAIL（walk 速度考古）→轮 2=M1/M2 boot FAIL（scratch 污染——
七元组件中 `runs_played:4 "Endless mode unlocked!"` 污染块仍在档可溯）→轮 3=仅
M2_LOOP_1 →轮 4=LOOP_1+M3 blip 未采→轮 5=M3 PASS(best-effort)+LOOP_1→**轮 6=全绿**=
提取件 `t20t3_console-box.log`）。**E1 修复（相位入口 append+头行）由此实证生效**；
E6（log() 去 tee 文件直写 ：136-139）由终态 console 整文件单写实证——两修复非仅落注释，
是活体行使过的。

## 三、book 扩节核对（方案 §四-T3-2 书单；不另立新章，SUMMARY 零 hunk 亲证）

`git diff 776639c5..f637ed38` 亲读：game-flow.md +98 行、audio.md +4、game-saves.md ±1、
game-ui.md +5、SUMMARY.md 空 diff、player-controller.md/assets.md 未动（报告声明的择要裁量
如实）。

### 1. 「The example game, end to end」大节三子节——事实面逐句对锚（QA 亲验）

| 书内断言 | 锚源码/证据 | 判 |
|---|---|---|
| 开箱导览：菜单（theme/`Runs: 0`/Start）→关卡（玩家/地面/两墙/三拾取/危害/掉落立方体/HUD）→两种结束同屏（血尽 **或** 集齐三枚 blip+同款流转）→「死亡环至多收 2 枚、第 3 枚即胜局」（E3 教学表述） | M1/M2/M3 终态 console+direct stdout（§二）；0→2/2→3 判定行 | ✅ |
| Restart 复位/Menu 回环「nothing accumulates」 | FRESH OK×7+七元组件（§二-2） | ✅ |
| 度表七层（Behavior/Scene documents/Config assets/Where it starts/Placing things/The level's own props/Flow conditions——「编辑器可达？」逐层） | 源码锚亲读：OnEnter 无条件四组生成（scaffold :2793-2796）、玩家 existing 守卫（lib.rs.template :1179-1181）、physics 模块总闸=`catalog.defaults()=={"physics"}`（modules.rs :477）、「绑定只读资源不可写流转」=模板文档注释既定面 | ✅ |
| 「Placed props add; they do not replace」+玩家反向例外（EG2 诚实边界） | 同上两锚+T2 M7/M11 pickups=4 在档 | ✅ |
| 「Winning is template behavior」（collect_pickups 胜局臂+扣血臂，作者可复制改写） | 胜局臂亲读：`count.0 >= 3` → `info!`（:3195 保留）→blip 三行→`flow.set(GameFlow::GameOver)`（scaffold :3172-3206） | ✅ |
| A16/EG8 注记：「flow state 本身未反射注册——remote 通道读/写皆不可……以文档根标记观察……filed as ticket A16」（任务指定口径逐字兑现） | buglist :489-491 A16 票在案+manual.md §7.5 flow 走标记词+T2 红证 `t20t2_eg8_flow_state_red.log` 在档 | ✅ |
| 「Running without the toolchain」：静态链接拒绝门+资产树随 exe+资产根回退+otool 审计面+本机机械代理+EG5（发货面无 BRP）+EG6（ad-hoc 未签名他机首开右键 Open） | `dynamic_linking_rejection`（export.rs :750+测试 :1234 亲读）、资产根链 `BEVY_ASSET_ROOT > CARGO_MANIFEST_DIR > exe 目录`（export.rs :6 模块文档亲读）、otool 复算（§二-1）、pure 活体（§二-1） | ✅ |

### 2. 30 秒清单胜局句+三交叉引用（双向出链目标逐一核实存在）

- 30 秒清单 step 1（game-flow.md :261-266）：**「Or collect all three pickups: the same
  end screen, by winning.」**在档=胜局入用户走查面 ✅。
- audio.md 三音表后 **win fanfare 句**（blip 双职→game-flow）✅；game-saves.md Progress 行
  **「both endings are game-overs……counts like a run lost」**半句 ✅；game-ui.md 血条段
  **「gets there by winning instead (a blip, then the same screen)」**半句 ✅——三处位置
  与 T3 报告声称一致，目标文档全存在。

### 3. Errata E1-E6 落账逐条亲核（t20-t2-report.md §八+原位注记）

E1（console 截断缺口）→脚本修复落（append+头行 ：128-132 带勘误注释）+**六轮头行活体实证**
（§二-4）✅；E2（N13 计数口径）→§五.6 原位注记+终态 console `n13_report` 事件口径 box=0
在档 ✅；E3（0→2 措辞差）→§二 M2 行原位注记+book 教学表述落笔（§三-1 首行）✅；E4（walk
速度考古差）→§五.1⑥ 原位注记+**本轮活体再现并被修**（calibrate 还原两处在终态 console，
§二-2）✅；E5（M7 构造器 set 拒）→§二 M7 行原位注记 ✅；E6（tee 双写伪影）→脚本修复落
（log() 文件直写）+**终态 console 单写实证** ✅。**T2 QA 报告本体零触碰**（git diff 为空
亲证）。**六条全闭环，其中两条带本轮活体证据。**

## 四、QA 放行清单对照（方案验收面+任务书终验口径）

| 条目 | 终态 |
|---|---|
| **T1 验收（决策 1/2 落地+prep 腿+三探针+门禁）** | ✅ QA PASS（t20-t1-qa.md：EG1 修复源码级复核 7/7 同步面+prep/inject 亲跑+PIE 真指针独立复现同点）——胜局臂本轮源码再亲读同形（scaffold :3172-3206） |
| **T2 验收（铁证①M1/M2+M7-M10+M11；铁证②M12/M13；M15 存活；四门禁）** | ✅ QA PASS（t20-t2-qa.md：16 格判定逐格对得上+四格全读+双会话互证）——6 errata 本轮全部落账兑现（§三-3） |
| **T3 验收（关键格终态复跑+book 扩节+全量门+errata 落账）** | ✅ 本轮（§一/§二/§三：M2/M3/M12+M13 复跑亲读全绿+book 对锚+E 落账实证+八门亲跑+归档抽核）——执行规模注记见 §六-1 |
| **EG1 🟡 胜局无流转** | **吸收闭合（决策 1-A 兑现）**：模板扩落地+teaches 92+嵌入断言锚+M3 终态真机全链（count/blip/flow/stdout/runs 五件）——「赢」可达结束面 |
| **EG2 ⚪ 道具代码常生、摆件只增补** | **不吸收（范围边界）兑现**：度表层+「placed props add」边界段落 book 在案；**open-challenges.md 形式条目未落**（§六-5，book 用户面已承载，建议主控合入时补两行） |
| **EG3 ⚪ 拾取/胜负无事件音** | **随决策 2-A 兑现（胜局 fanfare blip）**：win 臂 blip 三行+volume=1.0 活采+book「win's fanfare」句；per-pickup 音未做（T1 QA §七.3 接受的落地形态，teaches `server.load(BLIP_SOUND)==2` 锚钉住） |
| **EG4 ⚪ A2 推箱边界** | **知悉不立票兑现**：碰撞格断言 stop/滑行不断言 push（d23=0.0000 口径）；book 玩家章边界段（T11 时代）在 |
| **EG5 ⚪ 纯包无 BRP** | **定性注记兑现**：双导出分工（pure=隔离正主/injected=全链）+book EG5 边界段+A16 票承载工具面 |
| **EG6 ⚪ 无签名公证** | **记档兑现**：book「right-click → Open past Gatekeeper」+30 秒清单；open-challenges 一句话同 §六-5 缺口 |
| **EG8=A16 flow 通道死** | **立票正确+未重开模板改动**：buglist :489-491 在案（主控批准立账）；book 注记+manual §7.5 两词落位；红证在档；`register_type_state` 一行留下轮模板触碰（守「零产品改动」定性） |
| **关联票纪律** | A6（定案口径两轮行使：程序重试过+QA 三试尽红→隔离 3/3 绿，0 新增红）/A7（不前置——operator 主链+截图五招，m1 shot ok 行在档）/A9（gbrp 重试+settle 全腿绿）/A10（PIE 真指针+direct 双链双记：M1_PIE_MENU+M2_BOOT_MENU）/A11（无 rebind 腿=明令不踩兑现）✅ |
| **buglist/roadmap/台账纪律** | T3 提交触碰零 buglist/台账/roadmap（diff 面亲核）；roadmap 第 34 行未勾（留主控）；台账 T20 行止于 T1 QA（T2/T3 行留主控，§六-6）✅ |

## 五、验收句逐词证据指认

roadmap 第 34 行验收原文（逐字在案）：「**最小完整示例游戏端到端验收：开始菜单+玩家移动+
碰撞+拾取+胜负+音效+重开。验收=新建工程主要靠编辑器配置完成；可独立导出运行（无工具链
环境）。**」

### 「开始菜单+玩家移动+碰撞+拾取+胜负+音效+重开」——成立（七词逐词）

| 验收词 | 证据（QA 亲读/亲验） |
|---|---|
| 开始菜单 | M1_PIE_MENU_PASS（MenuRoot/Runs: 0/Start/MenuBgm music 0.6）+M2_BOOT_MENU_PASS（direct 冷启同断言）+**pure-window.png 菜单三件人眼亲核**（发货纯包面）+Runs 跨 kill -9 保持（T2 M5b 12=12 在档） |
| 玩家移动 | walk_calibrate 实测位移（dx=0.2027/400ms→0.000507 u/ms）+poll-driven W 行进；七元组件三态 pos（entry 出生点→dirty 行进位→collect rest）逐环在档；T11 双机矩阵域证据+合链复验 |
| 碰撞 | 撞墙截断 d12=-0.1122→d23=0.0000（z=-2.44 面停驻不穿墙）+真机危害碰撞伤害 100→85×3（CollisionEvents→hazard_damage 实触）；A2 推箱边界知悉不立票 |
| 拾取 | count 0→2/环（props 3→1 实 despawn+HUD "Pickups: 2"）+loop-1 穿越恢复腿+1+M3 第 3 枚 count 2→3+T2 摆件第 4 枚可收（pickups=4 在档） |
| 胜负 | **负局**=危害→血量 0（dirty 件 10→0）→GameOver→runs+1×3；**胜局**=3 枚集齐→win blip 1.0→GameOverRoot（flow）→stdout `Level clear! All 3 pickups collected.`→runs 4→5——两门同屏，EG1 闭合后「胜负」字面双半兑现 |
| 音效 | M4 press blip volume=1.0（blip-volume.txt=1.0）+MenuBgm ABSENT in Level/Ambient spatial 在场（七元组逐环）+win blip 1.0（同三组件 trio）+T2 三 SoundLive/mix 追认域证据（零产品 diff 承载） |
| 重开 | Restart→七元组 FRESH×6+post-m3 FRESH（血满/count 0/回出生点/拾取物重生 props 3/MenuBgm 停 Ambient 起/runs 恒等+1）——七元组复位=重开语义的全字段铁证 |

### 「新建工程主要靠编辑器配置完成」——成立（度表七层+配置域四格合链证据）

今日 08:44 `jd new` 净工程（零作者代码）开箱全链（§二）；度表七层的源码锚逐条亲读（§三-1
表）——行为层=模板自带（作者零手写）、四文档层/配置资产层/启动层/摆件层编辑器可达、代码
常生层/流转条件层=两条诚实边界在案；T2 M7-M10 四格（摆件/改屏/参数/启动场景）各自
「编辑器改→Save→Play 生效→staged 包内生效」三点链在档（pickups=4/"Orbs: 0"/config
loaded/health 50/gameover boot），T3 零产品 diff=T2 证据在终态树承载。EG2 边界如实入 book。

### 「可独立导出运行（无工具链环境）」——成立（铁证②终态复绿+审计复算）

M12 九腿+M13 四件本轮终态复绿（§二-1）：env -i 清环境+异目录+异 cwd 启动 60s 存活×4+
菜单渲染（QA 亲看）+stdout 干净（info=7/panic=0/warn clean）+otool 全系统链/零 LC_RPATH
（QA 复算）+零 dylib 工件（树+manifest 双面）+manifest 重生成逐字节等（9==9）+静态链接
拒绝门+资产根 exe 目录回退活体（catalog 行指向 pure 包自身 assets）。对照组=编辑器静态味
linkage 审计承载（E4 后不对称无从演示——如实口径，§六-7）；**机械代理=事实九上限**，
真·无工具链机器抽查=用户 30 秒清单项（§八-3）。

## 六、偏差与记档分级（QA 视角，0 🔴 + 0 🟡 + 8 ⚪/M 不阻塞）

| # | 级 | 项 | 事实与裁定 |
|---|---|---|---|
| 1 | M | **T3 复跑规模=抽三关键格（M2/M3/M12+M13）**，非方案 §四-T3 字面的「16 格终态复跑+重点腿（L2/L7/L8）」——注入包 staged 整链（L7）T3 未复跑 | T2→T3 产品 diff=0（diff 面亲核）=同树态，T2 QA 16 格判定+四格全读在终态树承载；报告 §〇 如实写「关键格复跑=三格全绿」无虚报。QA 判：抽格合理、放行；**主控如需全 16 格字面兑现，可按 t20-live.sh 终态形态重跑 inject 相（脚本 §六.5 自描述「复跑即得同形」）** |
| 2 | M | **QA integration 本轮 A6 件三试尽红**（5458/5459，EXIT=1）vs 程序轮重试过（5459/5459） | 隔离复跑 3/3 绿（~1.5s vs 满载 8-10s=满载挤压签名，T13 定案同构）；A6 定案口径（环境票/隔离绿对照）如实兑现，**0 新增红**；两轮互证 flaky 双形态在档。非新缺陷、不改判 |
| 3 | ⚪ | T3 报告记 integration flaky「TRY 1 FAIL 重试过」——归档实为 **TRY 1+2 双 FAIL、TRY 3 PASS**（FLAKY 3/3） | prose 精度差；「重试过」实质成立（预算内收敛），主控合入时可顺手改「TRY 3 PASS 重试收敛」 |
| 4 | ⚪ | T3 报告「七元组 11 件」——归档 `t20t3_seven-tuple-*` 实为 **10 件**（loop/t20-live/ 含 T2 时代 post-m6 共 11）；报告「FRESH OK×6」=M2 三环 entry+post 计数，console 实有 7 条判定行（+post-m3 归 M3 行） | 计数法级；判定实质不受影响（§二-2 亲数） |
| 5 | ⚪ | **EG2/EG6 的 open-challenges.md 形式条目未落**（方案 §一处置表指定「记 open-challenges」） | 两条边界的用户面已在 book game-flow.md 诚实承载（度表层+Gatekeeper 句）；开发者向台账缺两行——建议主控合入时补（EG2 道具场景化/生成开关；EG6 codesign 公证超 loop 范围） |
| 6 | ⚪ | **台账无 T20-T2 弧线行**（progress.md 止于 T20-T1 QA；ef006650 提交语声称 "ledger the T1/T2 arcs" 但实际只落 T19 行序修复+T1 两行） | T3 报告明言台账未动（留主控合入落笔）——建议主控补 T2 程序/QA+T3 弧线三至四行；提交语与台账内容的差记档 |
| 7 | ⚪ | 对照组半格：编辑器 E4 重建后为静态味，**dylib 不对称无从演示**——M12 对照腿走 linkage 审计承载分支 | T2/T3 同口径、console 判定行如实打印；otool 双件（editor/pure）QA 复算同零非系统链——静态审计兜底成立 |
| 8 | ⚪ | 已知面照旧：docs 17 行=13 实体+4 包汇总两计数法（T19 QA 同款注记）；doctests bind-dyld 第 13 次目击（T15 处方单包复跑绿在档）；direct stdout WARN 族（no-config×3/terrain no-Camera3d/no-mass cube/HUD 首帧 no-context）全数模板已知归因不立新账；`walk_axis z=1.6: still off … after 6 tries` 每环一条=T2 QA 已裁「如实合理」的同族重定位腿（返回值不接 || loopok，二次真触由 poll hold 完成） | 照实记档 |

**未动面**：`src/`、`crates/`、templates、fork、协议、场景格式——T3 零改动（T20 全弧产品
面=T1 的模板胜局臂+teaches 92 一测，T2/T3 零产品改动）；buglist/台账/roadmap 本轮未写
（主控合入时落笔）；工作树仅 QA 归档 10 件+本报告（`git status` 亲录）；RUST_BACKTRACE
全程未设；门链与真机不同窗（本会话零真机腿）；fork 零触碰。

## 七、最终裁决与 roadmap 建议

- **T20-T3 验收标准（方案 §四-T3）**：关键格终态复跑=M2/M3/M12+M13 亲读全绿（过程六轮
  收敛 append-only 可溯、零产品改动、每轮红=脚本考古/环境前提，§二）✅；book 扩节+三交叉
  引用+30 秒清单胜局句 ✅（§三）；errata E1-E6 落账 ✅（§三-3，其中 E1/E6 带活体实证）；
  全量门=程序九门归档逐项吻合+QA 八门亲跑复现（integration 双轮 A6 口径，§一）✅。
- **T20 整体（T1/T2/T3）**：验收句七词+两句验收=逐词证据在案（§五）；两条铁证终态立住
  （铁证①=单项目合链：`jd new` 净工程 开箱→配置→Play→双导出→staged 整环，T2 立证+T3
  关键格复绿；铁证②=纯包隔离三断言+四件审计，T2 双会话互证+T3 复绿复算）；EG 终态=EG1
  吸收闭合（胜局全链五件证据）+EG2-EG6/EG8=A16 记档兑现（§四）；门禁=teaches 92/fast
  3002/integration 5459 双轮 A6 口径/audio 7/save 19/scaffold_e2e 1/docs 同面 17 行/clippy
  双包零 warning/bind-dyld 13 次目击处方过；三轮 QA 裁决链闭环（T1 PASS→T2 PASS（含 6
  errata 本轮全落账）→T3 终验）。
- **VERDICT: PASS——T20 整体闭环。roadmap T20（第 34 行）建议可勾选**，闭环注记建议含：
  验收句逐词证据（七词合链+度表七层源码锚+M12/M13 隔离三断言与四件审计）；EG 终态（EG1
  吸收闭合=示例游戏教会胜利；EG2/EG5/EG6/EG8 边界记档，EG8=A16 票在案）；integration
  5459 双轮（A6 定案口径维持：程序轮重试收敛+QA 轮三试尽红→隔离 3/3 绿，0 新增红）+
  teaches 92；book 一大节三子节+三交叉引用；T20 产品面=T1 模板单函数 diff（回滚=revert
  一处+teaches/嵌入断言同步）；⚪/M 偏差八项不阻塞（§六-3/§六-4 token 级勘误、§六-5/
  §六-6 两处台账补行建议随合入落笔）。
- **主控合入路径**：照旧 `--no-ff`（T3 单提交 f637ed38 随 T2 之后）；主控落笔面=roadmap
  第 34 行勾选+收官行、台账补 T20-T2/T3 弧线行（§六-6）、buglist 零新票（A6/A7/A9/A10/A11
  维持未勾选；A16 未勾=正确）+open-challenges 补 EG2/EG6 两行（§六-5）+§六-3/§六-4 两处
  可选 prose 勘误。

## 八、用户 30 秒清单（T2 草稿+胜局句终态，真机腿一一对映）

1. **新建工程按 Play**：菜单（主题音乐、`Runs: 0`）→点 **Start**——关卡带 HUD。走进红色
   危害让血条见底=结束屏；**或集齐全部三枚拾取物=同一结束屏，靠获胜**（一声 blip）。
   **Restart** 回满血/回出生点/拾取物回来；**Menu**（结束屏上）回开始屏。循环玩——什么
   都不累积（M1/M2/M3+七元组 FRESH 背书）。
2. **暂停屏三条音量滑条**（master/music/sfx）：来回拖——正在播的声音即刻跟随，重启后保持
   （M4/GameAudioConfig 存档回带背书）。
3. **改点东西再 Build Game**：改菜单标题/HUD 文案/摆第 4 个拾取物/建一个 GameConfig/右键
   Set as Startup Scene——双击 dist 产物，改动全在包里（M7-M10/M11 staged 面背书）；拷到
   **没装 Rust 的另一台 Mac** 双击=真·无工具链抽查（首开右键 → Open 过 Gatekeeper；M12
   env -i 机械代理+otool 审计背书）。

## QA 会话产物索引

- 门禁八门：`loop/reports/t20t3_qa_{fmt,libtests,fast,audio_gate,save_store,integration,
  docs,scaffold_e2e}.log`（QA 亲跑全覆盖；后台链+轮询 10:32-11:04，df 37Gi 开跑/收跑）+
  `t20t3_qa_gates_exit.txt`（逐门 exit+时序+逐门 df）+`t20t3_qa_gates.sh`（门链脚本，未设
  RUST_BACKTRACE）+`t20t3_qa_integration_isolation_rerun.log`（A6 隔离复跑双跑全文，
  3/3 绿证据另含会话首跑 PASS 1.587s）。
- 核验对象：`loop/reports/t20-t3-report.md`+归档 t20t3_* 二十四件（console pure/box 提取
  件+门禁九 log+bind 复跑 log+exit 台账+脚本+otool/m13/manifest/pure-run/pure-window+
  七元组 10 件）；T1/T2 报告与 QA（t20-t1-qa/t20-t2-qa 含 6 errata 交接）+t20-t2-report.md
  §八落账面；`loop/qa/t20-live.sh`（E1/E6/lane retry/NOT-SAMPLED/calibrate/scratch 六处
  亲读）；`loop/t20-live/`（append-only console-box 六轮头行+七元组 11 件+otool 双件+
  direct-m3win+pure-run+blip-volume）；book 四文件 diff 与源码对照点（scaffold
  collect_pickups :3172-3206/OnEnter :2793-2796、lib.rs.template :1179-1181、modules.rs
  :477、export.rs :6/:750/:1234）；buglist A6/A7/A9/A10/A11/A16+roadmap 第 34 行+
  progress.md 台账面。
- 进程收尾：QA 复查零 jackdaw/nextest/t20-game 残留进程（pgrep 亲录）；E4 处方静态味重建
  （`cargo build -p jackdaw -p jd`，22.1s 过）；df 出口 37Gi；工作树除 QA 归档 11 件+
  本报告外零触碰。

—— QA agent（loop 自动化终验），2026-11-01
