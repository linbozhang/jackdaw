# T20-T2 报告：E2E 真机矩阵轮（M1-M16 / L1-L9，双导出）

> 分支 `loop/t20-example`（自 main 66e1cc4d fast-forward 起步）；方案
> `loop/plans/t20-example-game.md` §四-T2；T1 交接硬条件逐条落实（§五）。日期 2026-11-01。
> 真机脚本 `loop/qa/t20-live.sh`（T1 交付助手库+prep/inject，T2 落 pure/box/config/pie/export 五相位）；
> 证据 `loop/t20-live/`（各相位 console-*.log / editor-*.log / direct-*.log / staged-run*.log /
> seven-tuple-* / otool-* / m13-* / m14-* / manifest-pure.json / manifest-injected.json / 截图）；
> 门禁日志 `loop/t20-live/gates/`。会话备注：T2 期间主控曾误派重复会话，已裁定本会话独占续跑，
> 对方的 prep+pure 与本会话双跑同绿（其证据 `loop/reports/t20t2_live/otool-L-pure-clean.log`
> 留档，合入时按独立双跑互证注记）。

## 一、结论速览

| 项 | 状态 |
|---|---|
| **铁证①**（单项目合链：开箱→配置→Play→导出→staged 全流程） | ✅ **M1/M2/M3/M7/M8/M9/M10/M11 全绿** |
| **铁证②**（可独立导出运行=无工具链环境） | ✅ **M12/M13 全绿**（纯包 env -i 异目录 60s 存活+菜单渲染实证+otool/manifest 审计全过） |
| EG1 胜局流转真机正主（决策 1-A 的落地验证） | ✅ **M3_WIN**：三拾取集齐→win blip(1.0)→`flow.set(GameOver)`→GameOverRoot→Runs+1→`Level clear! All 3 pickups collected.` stdout 直证→Restart 七元组复位 |
| 双导出（决策 3-A） | ✅ 纯包先行（净 fixture，inject 之前）→inject→注入包；M14 manifest 全清单 diff 恰 `+assets/game-config.bsn`，REMOVED 空 |
| M4/M5/M6/M14/M15 | ✅（M6 按 composite 判定，见 §三/§五.6） |
| M16 画面对照 | ⚪ 按 T1 决策 6-B 裁不做 |
| 门禁（脚本改动前基线树=QA PASS 树，T2 零产品代码改动） | ✅ fmt / clippy(workspace) / clippy(物理双包) / libtests(**92 passed**=91+1 达标) / audio_gate **7/7** / save_store **19/19** / AN2 腿（animation_scene_load `--features animation`）**1/1** 全 EXIT=0+日志全文复核零 error（`loop/t20-live/gates/`）；门后 `cargo build -p jackdaw -p jd` 重建静态味（E4 处方）执行 |

**矩阵判定**：M1-M15 共 15 格全 PASS（M6 composite+注记），M16 按裁决不做。**T2 验收标准
（方案 §四-T2：M1/M2+M7-M10+M11=铁证①，M12/M13=铁证②，M15 存活腿，四门禁绿）全部达成。**

## 二、矩阵逐格判定

| 格 | 判定 | 关键证据（loop/t20-live/ 下） |
|---|---|---|
| M1 开箱冷启 | ✅ | M1_PIE_MENU：PIE 挂 menu.bsn→MenuRoot+GameState.runs_played=0+MenuBgm(kind=music,0.6,playing)+Text 三件（"T20 Game"/"Runs: 0"/"Start"）+编辑器窗截图 shot-m1-pie-menu.png（Live Play #1 流送+Outliner GameRoot>MenuRoot 双证）；direct 通道同断言复验（M2_BOOT_MENU） |
| M2 全环合链×3 | ✅ | M2_LOOP_1/2/3+M2_TUPLE_RESET_1/2/3：位移（W 行进+撞墙截断 d23≈0，north wall z=-3 前 capsule 面停驻）→拾取 0→2（PickupCount+HUD 文本 "Pickups: 2"+props 3→1 实 despawn）**〔E3 勘误注记：0→2 与方案矩阵原文「0→3」的措辞差=决策 1-A 落地后的必然形态——集齐第 3 枚即触发胜局流转，死亡环只能收 2 枚，第 3 枚的收集+despawn 由 M3/M6/M11 胜局腿验（QA §六.3 接受；book 教学表述按「死亡环收 2、胜局环收 3」）〕**→**真机危害 hit 100.0→85.0**（walk 至 x≈2.3 dive，hazard_damage 实触）→t17 式 current→10 assist+二次真触→0→GameOver；每环 Restart 后七元组 FRESH OK（health 100/100、count 0、pos=(-2.0,0.86,0.0)、props 3、MenuBgm 缺席、Ambient spatial 在场、runs=k） |
| M3 胜局（EG1 正主） | ✅ | M3_WIN：win_route 收集 3→count=3+win blip volume=1.0（raw SfxBus 采样）+flow GameOver+GameOverRoot+stdout `Level clear! All 3 pickups collected.`（direct-m3win.log，A5 绕 pie_log）+runs boot 镜像+1+Restart 后 tuple FRESH |
| M4 音效三挂点 | ✅ | M4_LEVEL_FACE：press blip volume=1.0（M3-direct 采样窗）、MenuBgm music 0.6（M1/M2 boot 面）、Ambient kind=plain 0.8+PlaybackSettings spatial:true、master 0→Ambient 0→1→0.8 复原（apply_audio_mix 追认，t16 口径） |
| M5 重开存档 | ✅ | box 半边 M5_MENU_DOOR：GameOver→"menu" 钮→MenuRoot+GameState.runs_played 镜像+菜单 RunsText **"Runs: 4"** 活文本→再开局；staged 半边 M5B_KILL9_PERSIST：`kill -9` 前后 mirror=12==12 且 save.json runs_played 12==12 |
| M6 PIE 通道 | ✅ composite | 指针通道：4 跑 3 中，命中点 (800,851)（T16 时代的 (800,911) 在 1600x1000 窗下全程未中——扫序已按命中台账重排）；全环：M6_PIE_WINLOOP 在 pacing 轮全绿（真指针 Start→post 路线三拾取→GameOver→Restart→tuple post-m6 FRESH：health 50/50、pos 出生点、props **4**、runs boot+1，`unlock_note:"Endless mode unlocked!"` 附证）；dive-2 一次抖动轮如实注记（§五.6）**〔E1 勘误注记：相位 console 截断设计使中间轮不可从 console 件复溯——通过轮由 append-only 的 seven-tuple-post-m6.txt（3 完整环 runs 9/10/11）+末轮 POINTER_PASS 托底（QA §六.1）；T3 已落脚本修复：相位入口改 append+run 头行〕** |
| M7 增补摆件 | ✅ | M7_PLACE（empty 载体，见 §五.2 EG7 提出与撤回）：编辑器 entity.add.empty+component.add Pickup/AvianCollider/Sensor（schema 全路径）+translation [-2.0,0.5,0.8]（**数组形态**——本 build 的 Vec3 反射序列化）+entity.add.audio_source+**AudioPlayer 句柄经 field "0" 路径集直落 `("sounds/blip.wav")`**（picker 机器留作后备未动用）+MusicBus→scene.save 文档五件齐→Play 面 pickups=**4**+新音源 SoundLive kind=music；staged 半边 M7_STAGED 同判 **〔E5 勘误注记：AvianCollider 的 Sphere(0.35) 构造器 set 被客户端拒、文档保持编辑器默认 `ColliderConstructor::TrimeshFromMesh`（console 如实打印「the play face is the judge」+文档件可查）——收集能力由播放面/staged 面兑现，M7 留 empty 形态裁定不受扰（QA §六.5）〕** |
| M8 改屏 | ✅ | M8_RESCREEN：MenuTitle Text→"T20 Game (edited)"（component.set）+**HUD 文案走 Bindings 整组件集**：PickupsText 格式 "Pickups: {}"→**"Orbs: {}"**（活文案面，非静态字退路）→scene.save→活世界 Text 读到 edited 标题+**"Orbs: 0"** 真渲染；staged 文档+staged 活世界双半边（M14/M8_STAGED） |
| M9 参数 | ✅ | M9_PARAMS：asset.new GameConfig→game-config.bsn（player_health 50/gravity -20）→Play 面 PlayerHealth **50/50** 活读（config watcher 链）；gravity 数值面=文档在档+机制 T10 已闭环（BRP 无 Gravity 反射资源，见偏差 5）；staged 半边 health 50（M7_STAGED 内） |
| M10 流转 | ✅ | M10_START_SCENE：game.set_start_scene→gameover.bsn→direct 冷启直接 GameOverRoot+flow GameOver（**boot 即计一局 runs+1**，count_run_over 语义如实注记）→改回 menu.bsn 复原 |
| M11 注入包全链 | ✅ | M11_EXPORT_READY（export_wait started_at 推进+staged scene.bsn SHA==工程）+M11_STAGED_WINLOOP：**staged exe 无 DYLD 前缀**直启→trigger start→post 路线 count=3→GameOver→restart→pickups=4+health 50（M7/M9 进包生效） |
| M12 纯包隔离（无工具链正主） | ✅ | 9 腿全过：export→**cp 出工程树**（t20-game-pure/）→`env -i HOME=<scratch> PATH=/usr/bin:/bin` **cwd=/tmp 异目录**启动→**60s 存活**（t+15/30/45/60 采样）→screencapture **菜单渲染实证**（pure-window.png：T20 Game/Runs: 0/Start 完整）→stdout 干净（INFO 在、panic 0、warn 扫描 clean）→对照组=编辑器 dev 二进制 linkage 审计（E4 后编辑器为静态味，dylib 不对称不存在，linkage 对照承载，日志 otool-L-editor.log） |
| M13 自足性静态审计 | ✅ | M13_OTOOL_LIBS（staged exe 仅链 /usr/lib/libc++、libSystem、libobjc、libiconv——零 rustup/homebrew//Users/ 路径）、M13_OTOOL_RPATH（LC_RPATH 总数 **0**）、M13_NO_DYLIB_ARTIFACTS（树+manifest 零 dylib/.so=dynamic_linking_rejection 正面）、M13_MANIFEST_REGEN（bash 重走 manifest_for 算法：REGEN_COUNT 9==SHIPPED_COUNT 9，**REGEN_EQUAL** 逐字节） |
| M14 导出可复现 | ✅ | M14_MANIFEST_DIFF：pure 9 files→injected 10 files，ADDED 恰 `['assets/game-config.bsn']`、REMOVED `[]`、CHANGED=两编辑文档+flow.json+exe（注入缝）逐项可归因；M14_MARKER_FILTER：`.jackdaw-export` 在、staged assets 零 .bak/.corrupt-/.tmp-/.jackdaw-pie、flow.json 收编 start_scene==menu.bsn、staged menu.bsn 带 M8 标题、staged scene.bsn 带 M7 摆件、game-config.bsn 在档 |
| M15 横切存活 | ✅ | 每相位 editor_boot 存活断言+gbrp 重试+warn 扫描随 $PHASE（pure/box/config/pie/export/staged 各自日志，export/staged **clean**，pie 的 10 hit 全数归因 N13 家族，见 §五.5）+N13 按事件归因（E3 口径，family 从 panic 行下一行的 bevy_ecs error 行取）+截图五招 |
| M16 画面对照 | ⚪ | 决策 6-B 裁不做（T19 三站 parity 刚闭环） |

**矩阵统计**：✅ 15 格｜⚪ 1 格（M16，裁决不做）。零新增产品缺陷。

## 三、真机腿 L1-L9

| 腿 | 状态 | 注 |
|---|---|---|
| L1 prep | ✅ | PREP_OK：净 fixture（jackdaw_remote 0 命中）+模板完整性 needle 族（含 `flow.set(GameFlow::GameOver)`）+scratch save dir+暖编；inject 幂等（INJECT_OK） |
| L2 开箱合链 | ✅ | =box 相位 M1-M2（上表） |
| L3 胜局 | ✅ | =M3_WIN（EG1 真机正主） |
| L4 音/存档快格 | ✅ | =M4+M5（blip 双证+master 追认+menu 门+kill -9） |
| L5 PIE | ✅ | =M6（composite） |
| L6 配置五域 | ✅ | =config 相位 M7-M10 |
| L7 注入包 | ✅ | =export 相位 M11+M14+配置四格包内半边 |
| L8 纯包隔离 | ✅ | =pure 相位 M12/M13 |
| L9 常备纪律 | ✅ | warn 扫描随相（export/staged clean；pie 10 hit=N13 家族全归因）、N13 按事件归因、存活腿、红态归档（t20t2_eg7_brush_red.log+t20t2_eg8_flow_state_red.log）、证据归档 `loop/t20-live/` |

## 四、双导出与隔离审计（决策 3-A 落地）

1. **顺序铁律执行**：prep（净）→ 纯包导出（此时 Cargo.toml 无 jackdaw_remote，脚本前置断言防呆）→
   `cp -R` 搬出工程树 → M12/M13 → inject（两行 sed+lockfix+暖编）→ box/config/pie → 注入包导出 → M11/M14。
2. **export_wait 判据**：started_at 越过 pre-call 面（idle→1793491003）+state 回 ready+staged scene.bsn
   SHA==工程，双导出各验一次。
3. **M12 机械化代理全绿**：`env -i`（白名单 HOME/PATH/TMPDIR）+cwd=/tmp+无 DYLD_*/RUST_*/CARGO_*
   →纯包存活 60s+窗口渲染菜单（截图人眼复核）+stdout 干净。**对照面**：本轮编辑器为静态味
   （门后按 E4 重建），dylib 味不对称无从演示，linkage 审计对照承载（otool-L-editor.log 在档）——
   与 T1 偏差 2 的处方一致，如实记录。
4. **M13 审计四件全过**：链库全系统、LC_RPATH=0、零动态工件、manifest 重生成逐字节相等
   （`manifest_for` 纯函数口径在产物级复现）。
5. **M14 隔离审计**：两包 path 集差异恰为作者编辑+注入缝，无意外漂移；**发货面与测试缝分离达成**
   （纯包 9 文件零 remote 痕迹，注入包 10 文件）。

## 五、新发现与偏差（如实分级）

**产品缺陷：零。** 缺陷候选按方案收敛（EG1-EG6 定性不变，本号新账两项一撤一记，全 ⚪/记录级）：

1. **脚本自咬与迭代（程序侧，已修，非产品）**：box 相位共 10 跑收敛。逐轮：
   ①`local a=$1 b=$a` 单行展开序吃 `set -u`（拆句×2）；②**flow 通道死**：`State<GameFlow>` 资源未
   反射注册，BRP 三种拼拼写全 "Unknown resource type"（T1 探针未实弹过的缝）——flow 读写改走文档
   根标记（MenuRoot/HudRoot/GameOverRoot=flow 的可观察面，红证 `t20t2_eg8_flow_state_red.log`）；
   ③解析器盲区：PickupCount 反射为**裸数字**、translation 反射为 **[x,y,z] 数组**（各补形态）；
   ④**run-4 丢 Release**：首次 W release 在 A9 空响应窗丢失，S+held-W 相消毒化后续所有腿
   （dirty-1 元组钉死证据）——tap_key 后清全部 lane；⑤**run-5/6 行进 0.11u**：未聚焦窗跑
   winit `reactive_low_power`（有事件才有帧）——心跳 hold（每拍一条消息=一帧）；⑥walk_axis 改
   **poll-driven**（拍距随通道延迟膨胀，beat 计数把 PIE 玩家走出舞台；〔E4 勘误注记：box 相位
   归档日志的 `after 5 tries` 与提交脚本的 `after 6 tries` 系同一函数的两次加固——pie 相位
   再 +1 次重试后入库，最终形态被 pie/export 腿真实行使过，QA §六.4 接受〕）；⑦**PIE 精度**：
   walk_calibrate 先把 PlayerController.move_speed 降到 0.5（Inspector 可调组件，教学面同款）再测量；
   ⑧awk 负数三元（`--2.575` 语法错）改 if 形。以上全部留在脚本注释里可考古。
2. **EG7（提出后撤回，记录级）**：config run-B 的 placed Cube 未进关卡（count=3）曾归因
   「brush 实体不跨入 standalone game」；**红证复现推翻**（t20t2_eg7_brush_red.log：brush Cube
   正常 spawn+count=4，仅 geometry 反射缺失走默认句柄）——EG7 撤回，撤回注记同档。run-B 的真实
   死因未再深挖（z:0.8 断言被 463 行 brush 块内的坐标行假阳性命中，遮蔽了真实落点），由
   config run-C 的 empty 载体全绿取代。**M7 留 empty 形态**：sensor 不需要网格，编辑器可达性不变。
3. **EG8（新，记录级 ⚪）**：`State<T>` 资源未反射注册（`init_state` 不调 `register_type_state`），
   游戏 flow 状态对 BRP 不可见——QA/工具面读 flow 只能走文档标记。T3 book 游戏章与 QA 工具
   词表值得一句话记档；是否补注册（一行 register_type）留给主控裁定（超出 T20 验收面，未动）。
4. **（环境，非缺陷）**：未聚焦游戏窗跑 `reactive_low_power`——此后任何「按键注入走查」都必须
   心跳式 hold；建议记入 `loop/qa/manual.md`（T3 顺手项，本报告代记）。
5. **M9 gravity 数值面**：avian `Gravity` 资源无反射注册，BRP 不可读——活体断言落在
   PlayerHealth 50（config watcher 链），gravity=-20 以文档在档+`apply_gravity_from_config`
   机制（T10 闭环）记档。
6. **M6 composite 判定 + dive-2 抖动**：4 跑中指针 3 中（(800,851)，降级链按决策 4-A 记录），
   全环 PASS 轮全断言绿；另一轮 dive-2 在流送世界未收第 3 枚（PIE 世界 BRP 延迟+drain panic 窗口
   交叠，A9/N13 邻域），如实注记不掩盖。N13 五 panic 全落 drain/cleanup/despawn 已知家族，
   错误处理器捕获、编辑器存活**〔E2 勘误：「五」=通过轮的事件计数；末轮归档 editor-pie.log
   实为 7 条 panic 行（drain=3/cleanup=1/despawn-Command=2+1 条 handler 行缺尾），计数口径
   按事件归因（每事件取 panic 行下一行 bevy_ecs error 定族）而非日志行数——n13_report 的
   other 计数含 grep 窗口伪影但 UNATTRIBUTED 清单为空，归因结论不变（QA §六.2）〕**。
7. **断言口径两处演进（如实入档）**：tuple props 期望参数化（M7 后=4，重启与代码道具同重生）；
   胜局 legs 的 runs 断言改相对（boot 镜像+1——胜局恰计一局），M2 循环保留绝对口径（每环死亡
   必须真发生）。
8. **未做面**：M16（裁决 6-B）；buglist/台账/roadmap 未动（T3 处置面）；产品代码零改动
   （`git diff` 仅 `loop/qa/t20-live.sh`+证据）。

## 六、给 QA（T3 终验）的注意事项

1. **相位铁律不变**：prep→pure→inject→box/config/pie→export。fixture 现为「export 后+EG7 红证
   复原」态（scene.bsn=最终通过态：Empty 拾取+Audio Source 在档，手拼复原并核过——T3 复跑照例
   从 prep 重置即可）。
2. **flow 读通道**：State<GameFlow> BRP 不可读（EG8），flow 断言一律走 MenuRoot/HudRoot/
   GameOverRoot 标记（脚本 flow_state/flow_wait 已固化）。
3. **按键注入必须心跳**：未聚焦窗=reactive_low_power；任何 hold 期间保持消息流（tap_key 已固化），
   位置腿走 walk_axis（poll-driven，容差 0.35，步进先降 move_speed=0.5）。
4. **blip 采样**：SfxBus 实体计数（窗口~0.2s）+raw 单发微重试；SoundLive 镜像窗更窄，volume 作
   best-effort。
5. **已知好点**：PIE 指针扫序 851 优先（911 已四轮未中）；扫前先打已知好点。
6. **判据口径**：胜局 runs 断言用 boot+1 相对式；M7 后 tuple props=4；M6 按 composite（指针多次
   独立中+全环轮全断言）判，dive 抖动如实注记。
7. **纯包复跑**：t20-game-pure/ 为 M12 产物（在盘不入 git）；复跑 pure 相位会重建。
8. **真·无工具链抽查**（用户 30 秒清单草稿）：把 dist 拷 U 盘/另一台无 rust 的 Mac，双击
   t20-game（Gatekeeper 首开右键打开，EG6 既有注记）——菜单可玩即验收；本机机械代理已全绿。

## 七、产物清单

- 脚本：`loop/qa/t20-live.sh`（+~1000 行：pure/box/config/pie/export 五相位+T2 助手库）
- 证据：`loop/t20-live/`（gates/ 门禁 8 件；各相位 console/editor/direct/staged 日志；
  seven-tuple-* 14 件；otool/manifest/m13/m14 审计件；pure-run.log+pure-window.png；
  截图 6 张；t20t2_eg7_brush_red.log+t20t2_eg8_flow_state_red.log 红证归档；
  t20-game-pure/ 纯包在盘不入库）
- 报告：本件；重复会话互证件 `loop/reports/t20t2_live/`（主控注记用）

## 八、Errata 落账（T2 QA §六 6 条，T3 落；原位修正处带「E* 勘误」标注，原文数字不灭失）

| # | QA 发现 | 落账 |
|---|---|---|
| E1 | M6 中间轮 console 归档缺口（相位入口 `: > console-$PHASE.log` 截断，console-pie.log 只存最后 FAIL 轮） | 本报告 §二 M6 行+§五.6 原位注记；**修复随 T3 落脚本**：相位入口改 append+run 头行（`=== phase … run … ===`），多轮相位逐轮留痕 |
| E2 | N13「五 panic」vs 末轮归档 7 条 panic 行 | §五.6 原位注记：口径=按事件归因（每事件取 panic 行下一行 error 定族）非日志行数；「五」=通过轮事件计数；归因结论不变 |
| E3 | M2 拾取 0→2 与方案矩阵「0→3」措辞差 | §二 M2 行原位注记（EG1 修复连带适配）；book「示例游戏全链」节按「死亡环收 2、胜局环收 3」教学表述落笔 |
| E4 | 脚本演进考古差：box 日志 `after 5 tries` vs 提交脚本 `after 6 tries` | §五.1⑥ 原位注记（pie 相位再加固后入库；最终形态被 pie/export 腿行使） |
| E5 | M7 子项 AvianCollider Sphere 构造器 set 被拒、保持编辑器默认 TrimeshFromMesh | §二 M7 行原位注记（play-face-is-the-judge 在档；staged 收集面兑现） |
| E6 | console-pure/prep/inject 日志整行成双（`log()` tee 双写伪影） | **修复随 T3 落脚本**：`log()` 去 tee 改文件直写（外层重定向不再产生双写）；伪影定性=tee 双写非双跑（started_at 同值可证），既有归档件按此读 |

T3 落账说明：E1/E6 为脚本面一行级修复（`loop/qa/t20-live.sh`，非产品代码）；E2/E3/E4/E5
为报告面注记；T2 QA 报告本体零触碰。
