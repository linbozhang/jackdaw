# T20-T2 QA 报告：E2E 真机矩阵轮验收

> QA 独立验收（2026-11-01）。对象：分支 `loop/t20-example` @ **2d4c19ce**、报告
> `loop/reports/t20-t2-report.md`、证据 `loop/t20-live/`+归档 `loop/reports/t20t2_live/`。
> 验收方式=门禁七门**亲跑**（后台顺序执行+日志全文复核）+ 程序归档证据**全读/亲验**
> （M2/M3/M12/M13 四格全读，M1 截图与 M12 纯包截图**人眼亲核**，M7-M10 脚本+编辑器日志+
> 文档三面对读，红证两件全文亲读）+ 真机腿未重跑（T2 为程序亲跑轮，QA 按「亲验归档全读」
> 口径；方案 T3 将终态复跑 L2/L7/L8）。QA 归档 `loop/reports/t20t2_qa_*.log`（7 门日志+
> exit 码+门链脚本）。全程未设 RUST_BACKTRACE；loop markdown 只用 Read/Edit/Write；
> 产品代码/buglist/台账未动。

## 一、裁决

## **PASS —— 放行 T20-T3**

T2 验收标准（方案 §四-T2）逐条达成且证据可复溯：①铁证①（M1/M2+M7-M10+M11 单项目合链）
全绿；②铁证②（M12/M13 隔离+审计）全绿且**双会话互证**；③M15 存活腿全过（export/staged
warn 零命中，pie 的 panic 全落 N13 已知家族）；④四门禁绿（QA 亲跑）。16 格判定 15 PASS+1
按裁决不做，与归档证据**逐格对得上**；5 项如实入档（五件）全部亲核属实。回流项全 ⚪ 记录级
（M6 中间轮 console 截断的归档面缺口为最重一条，有 append-only 七元组文件托底，不改判）。

## 二、门禁表（QA 亲跑，2026-11-01 08:16-08:21；基线树=2d4c19ce 即程序门禁树，T2 零产品改动）

| 门 | 命令 | 亲跑结果 | 证据 |
|---|---|---|---|
| fmt | `cargo fmt --all -- --check` | **EXIT=0**，零输出零 Diff | t20t2_qa_fmt.log（空文件=无 Diff） |
| clippy 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **EXIT=0**，零 warning（全文扫） | t20t2_qa_clippy_ws.log |
| clippy 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **EXIT=0**，零 warning | t20t2_qa_clippy_phys.log |
| libtests | `cargo test --workspace --lib` | **EXIT=0**；全仓 `test result:` 行 **0 failed**（逐行核）；合计 **3002 passed**；scaffold **`running 92 tests` → 92 passed**（:2686 起，teaches 92 达标） | t20t2_qa_libtests.log |
| audio_gate | `cargo nextest run --profile ci --test audio_gate` | **7/7 PASS**（Summary 7 run: 7 passed） | t20t2_qa_audio_gate.log |
| save_store | `cargo nextest run --profile ci -p jackdaw_runtime --test save_store` | **19/19 PASS** | t20t2_qa_save_store.log |
| AN2 腿 | `cargo nextest run --profile ci -p jackdaw_runtime --features animation --test animation_scene_load` | **1/1 PASS** | t20t2_qa_an2_scene.log |

退出码七门全 0（t20t2_qa_gates_exit.txt，逐门 START/END 时序在档）；按门禁证据标准做了
**日志全文复核**：libtests 的 87 处 error/warn 形态命中逐一归因为**负路径测试的预期日志**
（`scene save failed … not-a-directory`、`PIE: game build … failed E0560` 等皆测试自造的
失败面，对应测试全部 ok），非真失败。磁盘纪律：门前 df=37Gi（高于上轮出口 26Gi，本轮门禁
全缓存热跑后仍 37Gi，无 A6 泄漏——`.jackdaw/` 残留仅 32K 编辑器态）。门后 QA 已按 E4 处方
重建静态味（`cargo build -p jackdaw -p jd`，20s 过）。

**产品零改动亲核**：`git diff 66e1cc4d..2d4c19ce --name-only` 中 `loop/` 外文件数=**0**
（+7276/−192 全部是脚本+证据+报告）——与报告 §五.8 口径逐字吻合。

## 三、抽深四格证据全读（任务指定格）

### M2 全环合链×3（console-box.log + direct-m2loops.log + seven-tuple-* 全读）

- **三环 PASS 结构亲读**：每环 `M2_LOOP_k` + `M2_TUPLE_RESET_k` 双腿，entry-k/dirty-k/post-k
  七元组 9 件全在档。三环 entry/post 元组逐字段一致（health 100/100、pickups 0、pos
  (-2.0,0.86,0.0)、props 3、MenuBgm ABSENT、Ambient present、runs=k−1→k）——**七元组
  FRESH OK ×6 次亲读**，`runs` 绝对口径每环真 +1（每环死亡真发生）。
- **危害 hit 真触**：`M2 loop k: real hazard hit -> health=85.0 (want 85)` ×3——walk 至
  x≈2.3 后 poll-driven W hold 直到 `health<99.9` 才松键（脚本 ：1146-1153），扣 15=
  hazard_damage 实触非注入；随后 current→10 assist（:1161，t17 形态）+**二次真触**（W hold
  直到 GameOverRoot 出现才 break，:1164-1168）→0→GameOver。死亡链两次都经真实伤害系统。
- **撞墙截断**：`M2 walk: at wall … -> … -> … (d12=0.0000 d23=0.0000)`——两拍 W 位移零，
  北墙面前 capsule 停驻（z=-2.44，未穿墙断言 z>-2.7 过）。
- **拾取 0→2**：count=2 + props_left=1（3→1 实 despawn）+ HUD 文本 "Pickups: 2" ×3。
  **口径注记**：方案 §二 M2 行原文「拾取 0→3」，落地为 0→2——脚本注释明言「the third is
  M3's」（:1130）：EG1 修复后集齐 3 枚即触发胜局流转，死亡环只能收 2 枚；第 3 枚的收集+
  despawn 由 M3/M6/M11 胜局腿验。属决策 1-A 的连带适配，报告如实写 0→2，判定成立。
- **偏差实录**：每环一条 `walk_axis z=1.6: still off (≈0.54-0.59) after 5 tries`——这是
  二次 hit 前的重定位腿（脚本 ：1156，返回值未接 `|| loopok=false`），玩家停在 z≈0.58 仍
  在危害触盘可达路径上，二次真触由 poll-driven hold 完成后 `flow_wait GameOver` 判定——
  非致命、PASS 判定不受扰。QA 判：**如实、合理**。
- **warn 面**：`warn-scan box: clean`（editor-box.log 对 WARN_PATTERN_EDITOR 零命中，QA
  复扫同零）+N13 box=0。direct-*.log 的 stdout WARN（no-config-asset×3/no-Camera3d/
  no-mass cube/binding no-context×15）在既定 WARN_PATTERN 之外，全是模板已知面
  （M9 前无 config 属时序必然；HUD 绑定进 Level 首帧无 context 与 falling cube 无质量
  为 T10/T12 时代已知形态），归因成立，不立新账。

### M3 胜局（EG1 真机正主；console-box + direct-m3win.log 全读）

- **stdout A5 绕行亲读**：direct-m3win.log :18 `INFO t20_game: Level clear! All 3 pickups
  collected.`——direct run stdout 直证，不经 pie_log（A5 口径）；脚本 ：1265 以 grep 该行
  为硬断言。
- **win blip 1.0**：`M3: count=3 win blip volume=1.0`——raw SfxBus 实体计数+微重试采样窗
  （:1246-1256），T1 的 win 臂三行 blip 真机响证。
- **流转正主**：count=3→`flow_wait GameOver`+GameOverRoot 在场；runs 相对断言 boot 镜像
  4→胜后 5（`$((runs3_0 + 1))`，:1268）——胜局恰计一局；Restart→post-m3 七元组 FRESH
  （health 100/100、props 3、runs=5）。
- **算术链亲核**：boot mirror runs=4=M2 三死+M5 半边一局（M5 的 assist-to-0+menu 门+再开局
  各计一局），逐段对得上。M3_WIN_PASS 判定成立——**决策 1-A 的落地真机验证属实**。

### M12/M13 纯包隔离+静态审计（console-pure.log、pure-run.log、otool/m13/manifest 全件亲读+复算）

- **M13 QA 复算**（不采信脚本计数，自己重跑同一组 grep）：非系统链库=0、LC_RPATH 总数=0、
  树内 dylib/.so=0、manifest 内 dylib=0；m13-regen.txt `REGEN_COUNT 9 SHIPPED_COUNT 9 /
  REGEN_EQUAL`；manifest-pure.json 9 文件=8 assets+exe，零动态工件。**四件全过属实**。
- **M12 断言链**：`env -i HOME=<scratch> PATH=/usr/bin:/bin TMPDIR=…`+cwd=/tmp（脚本
  :994-995，DYLD_*/RUST_*/CARGO_* 全清）→t+15/30/45/60 alive ×4→`M12_ENV_I_ALIVE_PASS`；
  pure-run.log 亲读：7 行 INFO（SystemInfo→window 创建→catalog 跳过）+4 WARN（config
  默认值×3+terrain）+**panic=0**；资产根解析到 **pure 包自身目录**
  （`…/loop/t20-live/t20-game-pure/assets/catalog.bsn`——exe 自目录回退链活体）。
- **截图人眼亲核**：pure-window.png QA 亲看——T20 Game/Runs: 0/Start 三件完整可读（一枚
  macOS TCC 弹窗遮挡中上部，三件菜单要素在其下方清晰在场），**菜单渲染实证成立**。
- **对照组口径**：otool-L-editor.log 亲读=编辑器仅链 /usr/lib 四件（E4 门后重建→静态味）
  →dylib 不对称不存在，脚本走 `M12 control: editor is static-flavored…linkage audit
  contrast carries` 分支（console-pure :1-2）——与 T1 偏差 2/QA-E4 处方一致，**如实**。
- **纯包隔离双跑互证**：console-pure.log 每行成双是 **tee 双写伪影**（`log()` tee -a 落
  文件+stdout 再落同一文件；两行 `export_wait … idle -> 1793480566` 同一 started_at=同一次
  导出回显两次），**非两次独立跑**；独立第二跑=另一会话（被误派的重复会话）05:16 的
  `loop/reports/t20t2_live/otool-L-pure-clean.log`，QA 亲读：与本会话 otool-L-pure.log
  同构（仅 /usr/lib+/System/Library 全系统链）——**双跑同绿成立**，报告头注与 §四.3 的
  互证注记落位属实。
- **口径澄清（⚪）**：PURE_DIST=loop/t20-live/t20-game-pure/ 在 jackdaw 仓库内、fixture
  工程树（loop-mac/t20-game）外；报告「cp 出工程树」按 fixture 树读成立。隔离断言本体
  （env -i+cwd=/tmp+exe 目录资产根）不受此影响；在盘不入 git 与现状相符（untracked）。

### M7-M10 配置五域（editor-config.log + direct-m7place/m8live/m9face/m10boot + 文档件三面对读）

- **M7 数组形态 Vec3**：编辑器日志两次 component.set（22:54:18/19）+**第三次缺失**=对象
  形态 set（脚本 ：1390）客户端即拒未达 operator——**数组形态落、对象形态拒**与注释口径
  一致；文档件 m7-pickup-doc.txt 亲读：`translation: glam::Vec3 { x:-2.0, y:0.5,
  z:0.800000011920929 }`（文档侧结构体序列化——BRP 反射面 vs 文档序列化面两态并存，
  报告「本 build 的 Vec3 反射序列化=数组」属实）；`grep "z: 0.8"` 文档断言过=落点真达。
- **M7 AudioPlayer 句柄 field "0"**：22:54:25 component.set on Audio Source→文档件
  `bevy_audio::audio::AudioPlayer<bevy_audio::audio_source::AudioSource>("sounds/blip.wav")`
  亲读在档——句柄经 field "0" 路径直落，picker 机器未动用（后备未触发）。
- **M7 播放面**：direct-m7place.log 亲读——`config 'game-config.bsn' loaded`（M9 的 config
  先行在档）+pickups=4（3 代码+1 摆件，pickup_count 计 Pickup 组件实体）+Audio Source 的
  SoundLive kind=music；**收集面**由 M11 staged 胜局腿补证（post 路线骑过摆件、count=3 含
  其一+restart 后 props=4）。**一处子断言缺口（⚪ 如实）**：AvianCollider 构造器 Sphere 0.35
  的 set 被拒，文档保持编辑器默认 `ColliderConstructor::TrimeshFromMesh`（m7-pickup-doc.txt
  亲读+console `M7: the constructor stayed the editor default (the play face is the judge)`）
  ——脚本明言以播放面为判，staged 收集面兑现，判定成立；报告 M7 行未展开此子项，注记归档。
- **M8 Bindings 整组件集**：component.set on PickupsText `jackdaw_bind::types::Bindings`
  field ""（整组件值 `[{"Text":{"format":"Orbs: {}","args":[{"raw":"t20_game::PickupCount.0"}]}}]`）
  →hud.bsn 文档 grep "Orbs: {}" 过（QA 对盘上 fixture 亲验同命中）→**活文案面**
  `M8: the HUD binding copy reads Orbs: 0 live`（direct-m8live 活世界 Text 读回）——静态字
  退路分支未走。MenuTitle→"T20 Game (edited)" 文档+活世界双面同过。
- **M9**：asset.new GameConfig→asset.set player_health 50/gravity -20→文档件亲读
  （m9-game-config.bsn：`player_health: 50.0, gravity: -20.0`）→活体 `M9: live
  PlayerHealth={"current":50.0,"max":50.0}`（config watcher 链）→staged 包内
  `config 'game-config.bsn' loaded`（staged-run.log 亲读）。gravity 数值面=文档在档+
  T10 机制记档（BRP 无 Gravity 反射资源，报告偏差 5 口径）——**如实**。
- **M10**：game.set_start_scene→gameover.bsn→flow.json 断言→direct 冷启
  GameOverRoot+flow_state=GameOver+runs=8（boot 即计一局，`count_run_over` 语义如实注记）
  →复原 menu.bsn（QA 对盘上 flow.json 亲验=start_scene menu.bsn）。

## 四、其余格抽核与红证亲读

- **M1**：m1_pie_menu 断言面（MenuRoot/runs 0/MenuBgm music 0.6 playing/Text 三件）全过+
  **截图亲看**（shot-m1-pie-menu.png：LIVE Play #1 徽标+Outliner GameRoot>MenuRoot>
  MenuUiCamera+viewport 流送菜单三件+PIE console 行「playing the editor's scene menu.bsn」
  ——报告「双证」逐字兑现）；direct 通道同断言复验（M2_BOOT_MENU PASS：MenuRoot+runs 0+
  MenuBgm 0.6）。
- **M4**：press blip volume=1.0（M3-direct 采样窗捕获）+MenuBgm 0.6+Ambient plain 0.8+
  PlaybackSettings spatial:true+master 0→Ambient 0→复原 0.8（apply_audio_mix 追认）——
  console-box :6/:45+脚本 ：1194-1212 逐断言对读，PASS 成立。
- **M5**：box 半边——GameOver→menu 钮→MenuRoot+镜像 runs=4+菜单 RunsText **"Runs: 4"
  活文本**（game_texts 读的是活世界绑定输出值非文档占位）→再开局；staged 半边——
  `M5b: before kill -9: mirror=12 file=12 / after restart: mirror=12 file=12`
  （console-export :12-13）+脚本 pkill -9+pgrep 反证+重启后 mirror/file 双等断言。PASS 成立。
- **M6（composite）**：归档 console-pie.log=**最后一轮（dive-2 抖动轮，WINLOOP=FAIL 如实
  在档）**：真指针 `(800,851)` 首点命中（`op input.pointer click`→Ambient 出现为判，
  :1585-1595）`M6_PIE_POINTER_PASS`；count=2 未达 3→flow 未动→**FAIL 不掩盖**。
  **通过轮证据由 append-only 件托底**：seven-tuple-post-m6.txt 亲读=**三次完整胜局环**
  （runs_played 9/10/11 各一条：health 50/50——M9 config 跨相持续、pos 出生点、props **4**、
  MenuBgm 缺席、Ambient 在场、`unlock_note:"Endless mode unlocked!"`）——M6 判据
  （§六.6：指针多次独立中+全环轮全断言）成立，composite ✅ **维持**。⚪ 归档缺口见 §六.1。
- **M11/M14**：export_wait `idle -> 1793491003` 推进+state ready+staged SHA 判据；
  staged-run.log 亲读：staged exe 携注入缝（`JackdawRemote: Generated 472 new component
  definitions`）+game-config 载入+**`Level clear! All 3 pickups collected.`（staged 包内
  胜局 stdout 直证）**；启动命令 `env -u DYLD_LIBRARY_PATH -u RUST_BACKTRACE`（脚本 ：1700 段
  ——staged 无 DYLD 前缀亲核）；restart 后 pickups=4+health 50（M7/M9 进包生效）；
  m14-diff.txt 亲读：PURE 9→INJECTED 10、ADDED 恰 `['assets/game-config.bsn']`、REMOVED
  `[]`、CHANGED 5 件（flow/hud/menu/scene/exe=注入缝+作者编辑，逐项可归因）；
  M14_MARKER_FILTER PASS。全数与报告 M11/M14 行吻合。
- **红证两件全文亲读**：①`t20t2_eg8_flow_state_red.log`（08:07:11）：`State<t20_game::
  GameFlow>` 三种 BRP 拼写（bevy_ecs/bevy_state 两路径+短拼）全 `Unknown resource type`
  （code -23501）+world.list_resources 无 GameFlow 行——**EG8 红证成立**；替代断言面有效性
  =flow_state/flow_wait 走 MenuRoot/HudRoot/GameOverRoot 文档标记（脚本 ：327-338/:429-444），
  其效力由 M2×3/M3/M5/M10 各腿 flow 断言全过反证——**替代面成立**；eg8-red-run.log（运行
  载体日志）同档。②`t20t2_eg7_brush_red.log`（08:08:29）：brush Cube 场景下 Start 后
  Pickup 计数=**4**+Name 查询含 "Cube"+仅 Visibility::Inherited 回退 WARN——**EG7 假设被
  现场推翻**，文末 CORRECTION 注记同档亲读（run-B 真死因=translation 未落 brush+`z: 0.8`
  在 463 行 brush 块内假阳性 grep，被 empty 载体全绿取代）——**「brush 可跨入游戏」撤回
  注记在档且自证成立**（报告 §五.2 属实）；direct-eg7red.log/editor-eg7red.log 支撑日志
  同档（08:08 时序与红证吻合）。
- **五件如实入档 ③④⑤ 脚本面核**：③反射形态——count_of 兼容裸数字/对象/数组（:499-503）、
  pos_of/count_of 数组形态（:491-494）、translation 对象拼写被拒的注释（:1386-1387）；
  ④run-4 丢 Release——tap_key 末尾清全部四 lane（:485-489）+walk_reset 每腿边界调用+
  注释「run-4's lesson」；⑤reactive_low_power——tap_key 心跳 hold 注释（:472-478）+
  walk_axis poll-driven（:559-565）+walk_calibrate move_speed→0.5（:536-548，gcomp_mut
  Inspector 可调组件）。**三件全部落实且与报告 §五.1 逐条对应**。

## 五、两条铁证独立性判定

**铁证①（单项目合链）——成立。** 全部相位日志的工程路径同一（/Users/zhanglinbo/workspace/
loop-mac/t20-game）；时序亲核：jd-new.log（`jd new: created … scaffolded`）→PREP_OK（净
fixture+needle 族+scratch save dir）→纯包导出（05:11-05:12，inject 之前）→INJECT_OK→box
（06:29-06:35）→config（06:55-06:57）→pie（07:46-07:52）→注入包导出+staged（08:03-08:08）
——**同一次 jd new 的工程上连续走完 开箱→配置→Play→双导出→staged 整环**；编辑器配置四格
（M7 摆件/M8 改屏/M9 参数）的产物在 staged 包内逐格复现（pickups=4/"Orbs: 0"/config loaded/
health 50）。相位铁律（pure 先于 inject）有脚本防呆（pure 开头 `grep jackdaw_remote
Cargo.toml` 即退出）+时序证据双保险。

**铁证②（纯包隔离三断言+审计）——成立。** 三断言=env -i 异目录 60s 存活+窗口菜单渲染
（截图 QA 亲看）+stdout 干净（info 7/panic 0/pattern 扫描净）；审计四件=otool 链库全系统
（QA 复算 0 非系统）/LC_RPATH=0/零动态工件（树+manifest 双面）/manifest 重生成逐字节相等
（REGEN_EQUAL 9==9）。双会话独立双跑同绿（本会话+另一会话 otool 件互证）。**「无工具链
环境」的本机机械代理到达方案事实九的上限**；真·无工具链抽查已按方案写入用户 30 秒清单
（报告 §六.8）。

## 六、偏差裁定与发现（QA 新增 6 条，全 ⚪ 不改判）

| # | 发现 | 裁定 |
|---|---|---|
| 1 | **M6 中间轮 console 归档缺口**：相位入口 `: > console-$PHASE.log` 截断设计使 console-pie.log 只存最后一轮（恰为 FAIL 抖动轮）；报告「4 跑 3 中」「N13 五 panic」的中轮计数不可从 console 件复溯 | **接受（放行）**。通过轮由 append-only 的 seven-tuple-post-m6.txt（3 次完整环 runs 9/10/11）+最后一轮的 POINTER_PASS 托底，composite 判据满足；改判无据。**建议 T3 顺手**：相位 console 改 append（或按轮落 console-<phase>-<n>.log），一行改动消此类缺口 |
| 2 | 报告 §五.6「N13 五 panic」vs 归档末轮 editor-pie.log 实为 **7 panic**（QA 复算 drain=3/cleanup=1/despawn-Command=2+1 条 handler 行缺尾）；「五」应指通过轮；n13_report 的 other 计数含 grep 窗口伪影但 UNATTRIBUTED 清单为空 | **接受**。全数落 drain/cleanup/despawn 已知家族，归因结论不变；计数口径建议按 E3 注事件数 |
| 3 | M2 拾取断言 0→2 与方案矩阵原文「0→3」的措辞差（EG1 修复连带适配，脚本注释在档） | **接受**。适配正确（集齐即胜），第 3 枚由 M3/M6/M11 验；建议 T3 book 扩节时按「死亡环收 2、胜局环收 3」教学表述 |
| 4 | 脚本演进考古差：box 日志 `after 5 tries` vs 提交脚本 `after 6 tries`（walk_axis 于 pie 相位再加固） | **接受**。最终形态被 pie/export 腿真实行使过；注释可考古 |
| 5 | M7 子项：AvianCollider Sphere 构造器 set 被拒、保持编辑器默认 TrimeshFromMesh（console 如实打印+文档件可查）；收集能力由播放面/staged 面兑现 | **接受**。play-face-is-the-judge 在档；M7 留 empty 形态的裁定（§五.2）不受扰 |
| 6 | console-pure/prep/inject 日志整行成双（tee 双写伪影，非双跑——started_at 同值可证） | **接受**。纯外观；互证以 t20t2_live/otool 件为准（QA 已亲读）。T3 顺手可把 `log()` 去 tee 或外层去重定向 |

**程序侧 5 项如实入档复核结论**：①flow 通道死（红证亲读成立+替代面有效）✅；②未聚焦窗
reactive_low_power→心跳 hold+poll-driven+move_speed=0.5（脚本三处面核）✅；③反射形态
（裸数字/数组/对象拼写拒绝）✅；④run-4 丢 Release→lane 清理✅；⑤EG7 提出后经红证复现
撤回（撤回注记同档且自证）✅。**产品缺陷零**的口径维持（EG8 记录级 ⚪，register_type_state
一行补注册留给主控裁定，超出 T20 验收面——QA 同意不动）。

**M16 按裁决不做口径核**：决策 6-B（主控 8 点全按建议，台账 T20 行在案）；脚本无 M16 腿
（唯一提及是头注释陈旧措辞），报告 ⚪ 记法与裁决一致。**红证先归档纪律核**：EG7/EG8 红证
08:07-08:08 产出→08:12 报告落盘→同 commit 入库；抖动轮 FAIL 日志未删除未覆盖（恰是归档
面本身）——**纪律成立**。

## 七、给 T20-T3 的放行建议

1. **相位铁律与前提**：fixture 现为「export 后+EG7 红证复原」终态，QA 对盘亲验（scene.bsn
   Empty 拾取+Audio Source 在档、hud "Orbs: {}"、menu "T20 Game (edited)"、game-config
   50/-20、flow start_scene=menu.bsn）——T3 复跑照例从 prep 重置（脚本 destructive）；
   live 前 `cargo build -p jackdaw -p jd`（QA 已重建静态味，E4 处方）。
2. **T3 复跑重点**（方案 §四-T3）：L2/L7/L8 复跑+16 格终态；M6 复跑按 §六.6 判据，建议
   带上 §六.1 的 console append 小改让每轮留痕。
3. **book 扩节书单交接**（游戏模板章「示例游戏全链」一节的素材面）：开箱可玩清单=M1-M2
   证据面；编辑器五域导览=M7-M10（数组形态 Vec3/AudioPlayer field "0"/Bindings 整组件集
   三个「怎么配」的实操点值得写入）；胜负两链=负局（hazard→血尽）+胜局（3 拾取→win blip
   →GameOver，teaches 92 第 92 测同源）；导出与无工具链边界=EG5（纯包无 BRP）/EG6
   （Gatekeeper 首开右键）注记+30 秒清单（报告 §六.8 草稿在案）。flow 断言走文档标记
   （EG8）建议在 QA 工具词表记一句。
4. **磁盘/导出预算口径**：本轮实测两次 release 导出+全矩阵在 37Gi 空闲下完成、门禁热跑
   后仍 37Gi（无 scaffold_e2e 泄漏复发）；T3 终验全量门（fast/integration/doctests/docs/
   scaffold_e2e）照 T19 口径预留，export_wait 1500s×2 上限维持，门前 df+事后查 `.jackdaw`
   残留照旧。t20-game-pure/（198M）在盘不入 git，T3 pure 相位复跑会重建。
5. **buglist/台账**：仍归 T3 处置面（T2 零新增产品缺陷；EG8 一句话记档建议随 book/QA
   词表走）。warn 扫描随 `$PHASE`、RUST_BACKTRACE 禁令、N13 按事件归因（E3）三纪律对 T3
   继续有效。

## 八、QA 归档清单（loop/reports/）

- `t20t2_qa_{fmt,clippy_ws,clippy_phys,libtests,audio_gate,save_store,an2_scene}.log`
  （七门全文）
- `t20t2_qa_gates_exit.txt`（逐门退出码+时序）、`t20t2_qa_gates.sh`（门链脚本，未设
  RUST_BACKTRACE）
- 程序侧证据未改样（`loop/t20-live/`、`loop/reports/t20t2_live/` 经 git 核对保持提交态）
- QA 收尾动作：进程清理（jackdaw/t20-game 零残留）+静态味重建（20s 过）
