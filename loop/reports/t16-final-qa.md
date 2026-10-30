# T16 终验 QA 报告：任务 3（收官段）+ T16 整体终验（只验不修）

> 验收对象：分支 `loop/t16-audio` @ **e65a4f9e**（基线 main=5a59f016+T1/T2 合入；程序提交
> =T16-T3 收官）。程序报告：`loop/reports/t16-t3-report.md`。前置：T16-T1 QA PASS
> （t16-t1-qa.md）、T16-T2 QA PASS（t16-t2-qa.md，回流三项+A10 立票已由主控落账）。
> T3 diff 亲核：**产品面=book 四文件+tests/ 两文件（+14 行测试基建）+live 脚本加固，`src/`、
> `crates/`、模板、fork、协议、场景格式零改动**（`git diff e65a4f9e~1..e65a4f9e -- src/ crates/
> templates/ Cargo.toml` 逐目录实证为空；tests/ 恰 `tests/inspector/category_strip.rs` +6 与
> `tests/util/mod.rs` +8）。
> QA 手段：**Mac 全量门亲跑**（串行后台脚本 `loop/qa/t16t3-qa-gates.sh`，全程未设
> RUST_BACKTRACE，门前 df=98Gi、零遗留进程、门链独窗）＋**门后定向腿**（A6 隔离复跑 1/1 绿）
> ＋**两处测试债 diff/覆盖关系亲核**＋fixture 盘上亲验＋T3 真机 36 件证据全文核对（16 判定
> console+13 witness+4 截图亲览）＋book 五文件亲读并与模板/编辑器源码逐项对照。QA 归档
> `loop/reports/t16t3_qa_*` 10 件。

## 〇、结论

**PASS（T16-T3 收官 + T16 整体，含 roadmap T16 可勾选建议）**——全量门亲跑复现：integration
**QA 独立复现 5418 跑 5417+唯一红=A6 同件同签名**（prefab_lifecycle.rs:714 三试全败
`watcher reloaded prefab; v2 should be in world. Got ["v1"]`）＋**隔离复跑 1/1 绿 3.071s**（定案
口径放行，与程序轮逐位吻合）；integration 首跑 3 红与终树复跑 1 红的覆盖关系亲核成立（§二）；
两处 T1 遗留测试债修复**恰为 tests/ 两文件 +14 行、src/ 零 diff**，终树全二进制 inspector
166/166+stage nextest 489/489（QA 从终树 integration 日志逐行点数实证）；book 音频新章八节
+SUMMARY+四处交叉引用逐项过且事实面全部对得上模板/编辑器源码（§三）；验收句三铁证各有
独立证据、T3 两相 16 判定复跑与 T2/QA 轮确定性数值**逐字节一致**（QA diff 实证）（§四）；
T2 QA 回流三项全部兑现（§五）；AU1-AU8 结案清单全绿、「Audio Source 从标记补齐为功能」
字面闭环成立（§六）。**偏差 0 🔴 + 0 🟡 + 5 ⚪（§七）**——全部为归档精度/措辞级，不动摇裁决。

## 一、Mac 全量门亲跑（权威口径，最终树 e65a4f9e）

| # | 门 | 命令 | QA 亲跑结果 | 归档 |
|---|---|---|---|---|
| 1 | 格式 | `cargo fmt --all -- --check` | **CLEAN**（exit=0，日志 0 字节） | `t16t3_qa_fmt.log` |
| 2 | 单测 | `cargo test --workspace --lib --features dylib` | **exit=0；2987/2987**（`test result: ok` 求和亲算=2987，0 FAILED 行；**scaffold teaches `90 passed` 行亲点**） | `t16t3_qa_libtests.log` |
| 3 | fast | `cargo xtask fast` | **2987 run: 2987 passed, 0 skipped**（exit=0；Summary 行亲读） | `t16t3_qa_fast.log` |
| 4 | 音频门（M8 终锚） | `cargo test --test audio_gate` | **7/7**（2.88s；含探针①-④ 常驻+mix 数学+bus 路由+master 0 追认+DESPAWN） | `t16t3_qa_audio_gate.log` |
| 5 | 物理双包 clippy | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | **CLEAN**（exit=0，仅 Checking/Finished） | `t16t3_qa_clippy_physics.log` |
| 6 | **integration** | `cargo xtask integration` | **5418 run：5417 passed (13 slow)，1 failed**（2056.8s）——唯一红=`jackdaw::prefabs prefab_lifecycle::prefab_file_change_triggers_reload`，3 试全败（20.3s/…），panic 同签名 `watcher reloaded prefab; v2 should be in world. Got ["v1"]` @ **prefab_lifecycle.rs:714 = A6 存量票原签名**；零 nextest 重试自愈、非 A6 失败为零；两处测试债修复件（category_strip/new_project）链内 **PASS 亲见** | `t16t3_qa_integration.log` |
| 7 | docs | `cargo doc --no-deps --workspace` | **exit=0**；warning 面 **17 条与程序归档逐字同**（QA `diff` 两轮 warning 行排序后**全等**）——全部为存量私项链接族，T16 触碰面（launch/entity_ops/asset_row/typed_values/模板）零新 warning | `t16t3_qa_docs.log` |
| 8 | scaffold_e2e | `cargo nextest run --profile ci -p jackdaw --test scaffold_e2e` | **PASS 1/1**（150.5s；与程序轮 149.3s 同档） | `t16t3_qa_scaffold_e2e.log` |

**门后定向腿**（QA 独立）：**A6 件隔离跑 ✅ 1/1 PASS（3.071s，100 skipped）**——「红跟随二进
制内并行负载」定案形态在 T16 终树复现，与程序轮 `t16t3_a6_isolated.log`（2.966s）互证。归档
`t16t3_qa_a6_isolated.log`。

**doctests（采信归档抽核）**：程序双日志在案——`t16t3_doctests.log` 主跑在 `-p jackdaw_bind
--doc` 处 dyld rpath 家族失败（`libstd-*.dylib not loaded`，**第 9 次目击**，T15 已定案环境票）；
`t16t3_doctests_bind_rerun.log` 单包复跑 **1 passed**（T15 处方有效）。QA 抽核两日志全文，与
T15-T3 同形，采信。

**程序归档交叉复核**：fmt 0 字节、clippy 双包 0 warning 行、libtests teaches 90、fast Summary
`2987 passed, 0 skipped`、audio_gate 7/7（2.65s）、integration 终树 Summary `[2044.855s] 5418
run: 5417 passed, 1 failed`（唯一红 A6 同签名三试）、a6_isolated 1/1 绿（2.966s）、docs exit=0
（17 条 warning）、scaffold_e2e PASS（149.3s）、`t16t3_gates_progress.log` 逐门时间线（首跑
integration exit=1+doctests exit=101 如实留痕，终树复跑按 mtime 链可追）——与 t16-t3-report §三
门禁表逐项一致，无隐瞒。

**计数核对**：integration **5418**=T15 基线 5405+13（分解=T1 新增 lib 测试 6 件——scaffold
teaches 1+jackdaw src 4+project_build 1，随 `--tests` 计入；audio_gate 新二进制 7 件）——
逐位吻合无隐藏件；fast **2987** 与 T1/T2 基线严丝合缝（T3 零 fast 侧新增，两测试债全在
integration 档二进制）。**首跑 3 红→终树 1 红的差额=偏差 1 两修复**（§二）。**磁盘**：门前
98Gi/门后 89Gi（A6 家族压力区全程宽裕；偏差 7 的清盘——`target/debug/incremental`+陈旧
fixture `t15-anim`/`t14-prefab` 移除、`t16-audio` 保留——盘上亲验成立）。**RUST_BACKTRACE
全程未设**；结束零残留进程（亲查仅门链自身件）；门链独窗。

## 二、T3 两处 T1 遗留测试债终核 → **核实成立，处置合格**

integration 层自 T1 产品改动以来首跑（T1 QA 七门不含该层、T2 零产品改动采信 T1——该层
在 T16 弧内确属首次运行）揭出 3 红=A6 已知件+下列两处 T1 遗留测试债；T3 自捕自修。

| 债 | 首跑红证（`t16t3_integration-first-run-red_red.log` 亲读） | 修复 diff（QA 亲读） | 终树绿证 |
|---|---|---|---|
| **category_strip 期望表缺 Audio tab** | `category_tabs_carry_title_and_description_tooltips` 断言 diff 实证：实返 **7 元组含 `("Audio","How this entity sounds: playback, bus and listening.")`** vs 期望 6 元组（三试同签名）——根因=`spawn_category_strip` 按注册表逐类目出 tab，T1 注册的 Audio 类目天然在列 | `tests/inspector/category_strip.rs` **+6 行**：期望表补 Audio 元组+注 | 终树 integration `PASS (4224/5418)`（程序轮）+ QA 轮 PASS 亲见；**inspector 二进制全跑 166/166、0 FAIL（QA 从终树日志逐行点数）** |
| **headless 测试 app 缺 AudioSource init** | `stage::new_project::create_in_the_new_game_dialog…` fork panic（bevy_asset info.rs:869 "asset type has not been initialized"）——测试基建 `ambient_app_reading` disable AudioPlugin（无头不连后端）→`AudioSource` 未 init，T1 模板 scene.bsn 带 `#Ambient` 后打开场景 handle 分配即 panic | `tests/util/mod.rs` **+8 行**：`init_asset::<AudioSource>`+`init_asset_loader::<AudioLoader>`（纯解码零后端）+注释原由 | 终树 integration `PASS (4935/5418)`（程序轮）+ QA 轮 PASS 亲见；**stage 二进制 nextest 489/489、0 FAIL（同上点数）** |

三点裁定：①**改动面合规**——`git diff e65a4f9e~1..e65a4f9e -- tests/` 恰两文件 +14 行，
src/crates/零 diff（§〇），「程序自捕自修、tests/ 基建」字面成立；②**覆盖关系成立**——首跑
摘录归档（`*_red` 纪律：Summary 5415/5418+3 failed+逐红 TRY 行/断言 diff 全文）与终树复跑
（5417/5418 唯一 A6）的差异恰为两修复件转绿，首跑红态按覆盖式纪律先摘录后覆盖，链路可追；
③**nextest 口径记档核实**——integration 门本体即 `cargo nextest run --profile ci`（QA 亲读日
志命令行），「stage/inspector 判红必须 nextest 口径」的偏差 2 附注（cargo-test 同进程并发踩
`isolate_config_dir` 全局态）成立为防误读记档；隔离复跑与全二进制计数不需要独立归档日志——
终树 integration 日志本身即更强源（166/489 全绿零 FAIL 在案）。

## 三、book 核对（方案 §四-T3-2 八节书单+交叉引用）

`book/src/user-guide/audio.md`（205 行新章）逐项亲读，**事实面逐条对照模板/编辑器源码**：

| 书单项 | 落点 | 源码对照（QA 亲验） | 判 |
|---|---|---|---|
| 1 开篇分工（编辑器=作者面永不发声/游戏=发声体；三音先行承诺） | 首两段 | launch.rs:151-154 `AudioPlugin{global_volume: Linear(0.0)}` 亲读在位 | ✅ |
| 2 The editor is silent（M14/AU7：GlobalVolume 钉 0+authored 数字零触碰+「听见编辑器出声=回归要上报」+线框标记 survive reopen（派生）） | §2 | 静音门一行在编辑器 setup 非 authored 数据；派生标记=T1 `derive_audio_source_marker`（T1 QA 源码级在案） | ✅ |
| 3 Adding a sound（Add > Audio & Animation > Audio Source；AudioPlayer asset row Pick/Browse/拖放/路径/Clear；PlaybackSettings 字段表 mode 四值含 Despawn 自灭/volume/spatial/speed/paused/muted；**AudioPlayer 不入 Add picker 的原因如实写**（句柄无意义默认值，模板实体=正门；picker Audio 区=MusicBus/SfxBus+bevy_audio 组的 PlaybackSettings/SpatialListener）；BSN 全泛型路径纪律带代码样例；存/重开四件原样） | §3 | menu.bsn.template:42-48 全泛型路径实文与章内代码块逐字同型；picker 缺席=audio_gate 探针①常驻断言；MusicBus/SfxBus `@EditorCategory("Audio")`（lib.rs.template:464/469）亲读 | ✅ |
| 4 The template's three sounds（三音表 MenuBgm 0.6 Loop MusicBus / press_sound DESPAWN SfxBus / Ambient 0.8 Loop spatial (6,2,-4)；「循环音的停止=不再承载它」→[Game Flow]；SpatialListener 挂玩家相机 rig→[Player Controller]；**spatial=双声道 pan 非 HRTF** 如实注记） | §4 | scene.bsn:17-27（ambient.wav/Loop/Linear(0.8)/spatial:true/(6,2,-4)）与 lib.rs.template:1181-1190（BLIP_SOUND+DESPAWN）逐字对上 | ✅ |
| 5 The three-way mix（`base × bus × master` 公式；GameAudioConfig 三字段+New Asset→[Game Parameters]；MusicBus/SfxBus/plain 路由表；**引擎「GlobalVolume 只在建 sink 帧读一次、不追认」的 quirk 与模板 mix 双系统补齐**如实写；运行中改 config 即刻生效；SoundLive 五字段表（kind/volume/paused/finished/position_secs，Resources 面板+BRP 可读=「可检视的音频」）；T17 设置屏指路（资源非绑定目标，经少量游戏代码写→[Game UI]）） | §5 | `mix_volume`（lib.rs.template:496-505）+`apply_audio_mix`/`apply_audio_mix_to_new_sinks` 双系统+`SoundLive`（:479-490 五字段）全对上；「缺 config 全 1.0 运行」与 Default 实现一致 | ✅ |
| 6 Files and formats（ogg/wav 在册；mp3/flac 未启用=picker 不列+loader 不解→T18 指路如实） | §6 | fork feature 面（方案事实十一）+asset_row `["ogg","oga","wav"]` 臂（T1 QA 在案） | ✅ |
| 7 When a sound doesn't play（**AU8 静默态**：实体在/sink 无/日志一行 vs **AU6 坏字节崩溃态**如实；30 秒红绿对照 missing.wav→静音+日志点名→改回→乐声回来） | §7 | 双态与 T2/T3 L7 红绿实录一致（`Path not found` ERROR 归档+SoundLive ABSENT） | ✅ |
| 8 The 30-second check（五步：afplay 预检→cargo run 三音→config 三态→导出→编辑器静音） | §8 | 与 T2 QA §九采信版逐条一致（含设备预检句） | ✅ |

**SUMMARY+交叉引用**：SUMMARY.md 挂目于 Game UI 后 ✅；`game-flow.md`（Scene members 行补
"the menu's theme music"例+新增一段「换文档=循环音的停止钮」+回链）✅；`game-ui.md`（按钮
段补 click 指路+回链）✅；`player-controller.md`（相机 rig 段补 SpatialListener 句+回链）✅；
章内相对链接六目标（player-controller/game-flow/game-ui/game-parameters/remote-debugging/
game-input）**逐一存在亲验** ✅。偏差注记：方案书单点名 `animation.md` 交叉引用——实际双向
均未挂链（动画与音频在本里程碑无自然交点；T3 报告如实列了实际落点），措辞级偏差记 §七-4。

## 四、验收句三铁证终态——独立性判定

roadmap 第 30 行验收原文：「BGM/按钮音/场景音 Play+导出可响；主音量/音乐/音效三类控制」
（逐字在案）+AU7 裁定的「编辑器静音」语义。

| 铁证 | 终态证据链 | 独立性判定 |
|---|---|---|
| ① BGM/按钮音/场景音 Play+导出可响 | T2：L3 BGM 0.6（position 3.12→5.17 前进）、M3-direct+L4 blip 0.4（真点击 (800,911) 双链、一次性生灭）、L5 Ambient 0.8 spatial、L6 staged 三值+包内 sounds/ 盘证；**T3 终树复跑 16 判定全 PASS**（L3 6.62→8.67 前进、M3 direct caught=1/PIE caught=2、L6 staged plain:0.8+music:0.5+sfx:0.4） | **独立成立**。三音各自独立实体×独立场景×独立证据链（SoundLive 数值+kind+position 推进），任一音的证据不依赖其余两音；导出腿异目录启动同值复现；**QA 对 T2/T3 两轮 witness 逐文件 diff——L9 三快照/L5 路由基线/L6 路由/M7 资源值全部逐字节一致**（position 属实时流读数按前进语义判，T2 QA 勘误口径） |
| ② 主音量/音乐/音效三类控制 | L9 四步循环（baseline→music 0 仅哑 MusicProbe→sfx 0 仅哑 SfxProbe→master 0 全哑→复原）两轮数值互不串扰逐字节一致；L3 master mutate 0→已播 sink 即刻 0.0→复原（「不追认」引擎缺口由模板 mix 补齐的活证）；M7-play 编辑器改 music=0.5→运行游戏读回 `{1.0,0.5,1.0}`+MenuBgm=0.3（0.6×0.5） | **独立成立**。三个控制面机制分离（config 资源×bus 标签×mix 双系统——模板源码亲读）；L9 证明三旋钮互不串扰（动 music 时 sfx/plain 数值纹丝不动）；master 追认与分轨隔离互不依赖；授权面（M7 编辑器卡，截图亲览净态）与运行面（资源读回）同值 |
| ③ 「编辑器静音」语义（AU7/M14） | M14 双证两轮一致：编辑器进程 BRP 直读 `GlobalVolume={"volume":{"Linear":0.0}}`+authored MenuBgm PlaybackSettings **0.6 原样未触碰**；游戏进程出声独立可证（①的数值+position）；QA 源码级复核：launch.rs 静音门一行在位、**游戏侧 main.rs.template/fixture 均裸 DefaultPlugins 无 AudioPlugin 覆写**（GlobalVolume=1.0 不受扰） | **独立成立（双证+语义边界核实）**。「编辑器不作为发声体」与「authored 数据零触碰」同时成立；游戏侧出声链不依赖编辑器侧任何状态；book §2「听到编辑器出声=回归要上报」口径入章。**QA 口径沿用：编辑器内听到任何声音=AU7 回归立账** |

## 五、T2 QA 回流兑现核对（三项全兑现）

| 回流项 | 兑现证据（QA 亲验） | 判 |
|---|---|---|
| L1 浮层关闭复跑（截图净） | 编辑器相改序 **M14→M12→M7→L1**（t16-live.sh:712-720 注释明引 t16-t2 QA reflow item c）；T3 四张截图 **QA 亲览**：m14（菜单视口+静音主题，无浮层）、m7（config 卡 master 1.00/music 0.50/sfx 1.00+Save，无浮层）——T2 污染面消除；浮层只出现在 L1 自身两张（picker 本身即拍摄对象；断言面全在 BRP 读回+文档 grep） | ✅ |
| 勘误四项引数以归档为准 | ①T3 报告 §二引 L3 position 归档值（3.12→5.17 作 T2 对照、6.62→8.67 为本轮）✅；②M13 归因拆分 5+9=14——QA 对 `t16t3_live-audio-warn-attributed.log` 逐条点数：config 缺省 5+bind 首帧 9 ✅；③「14 格」口径沿用 ✅；④loop/README 漂移由主控随迁移入库更正（T2 勘误第 4 条在档）✅ | ✅ |
| 词表两项入扫描 | t16-live.sh 两相各设 `cannot apply.*AudioPlayer` 泛型注册回归计数门（:728/:1199，本轮两相均 0）+`No audio device` 入 game-channel 词表（:1216/:1218）——词表成员亲读在位 | ✅ |

附带兑现（T3 报告偏差 3 的脚本加固，QA 亲读）：`brp()` 穷尽显式 `return 1`（:102）+
`editor_boot` 判定加进程存活条件（:181 `pgrep -x jackdaw`）——该轮工具红态在档可追：
`loop/t16-live/console-all.log`（`PREP_OK`+`EDITOR_BOOT_FAIL`）+`loop/t16-live/editor-all.log`
（dyld `Symbol not found` 原文），已随 e65a4f9e 入库。

## 六、QA 放行清单对照（方案 §六+§四各任务验收标准）

| 条目 | 裁定 |
|---|---|
| **T1/T2/T3 验收全绿** | T1 QA PASS（七门亲跑+AU1-AU5/AU7 源码级实证+探针四断言互证）；T2 QA PASS（M1-M14 十四格+L1-L11 十一腿零假绿+三铁证独立+L9/M6/M3 QA 亲跑逐字节复现）；T3=本轮（§一/§二/§三：16 判定复跑+book 章+全量门） |
| **AU1 🔴 引用授权门** | **已修结案**。模板主入口（spawn 即附 AudioPlayer+PlaybackSettings，Rust insert 不经反射 Default）+三处泛型显式注册+asset_row 音频臂+typed_values 回退；picker 缺席=探针①常驻断言记档（结构性而非遗漏）；活证=M1 授权链两轮 PASS+picker 截图（Browse+三 wav）亲览 |
| **AU2 🔴 三类控制无形态** | **已修结案**。模板 GameAudioConfig+MusicBus/SfxBus+apply_audio_mix 双系统+SoundLive 镜像（T1 QA 源码级）；活证=L9/M7/L3（铁证②） |
| **AU3 🟡 资产 picker 不认音频** | **已修结案**。AudioSource 臂 `["ogg","oga","wav"]`+DialogPurpose::Sound；活证=M1 Pick 截图三 wav 在列（spx 刻意不列=T1 QA 观察 C 文档化选择，T18 复核一句） |
| **AU4 🟡 标记 gizmo 重开即失** | **已修结案**。derive_audio_source_marker 观察者；活证=M12/L1 重开 marker 读回两轮 PASS+book §2 如实记载派生语义 |
| **AU5 🟡 解码面窄** | **已修结案**。wav feature 三处（workspace/bevy_source 帮手/fixture 锁）+模板自带三 wav；活证=L2 afplay 对照+fixture e2e wav 解码出声 |
| **AU6 ⚪ 坏音频解码 panic** | **记档留 T18**（方案口径：fork unwrap 层，资产导入域领走）；book §7「Broken file (loud)」如实向作者披露 |
| **AU7 ⚪ 编辑态即播/PIE 双声** | **已修结案**。launch.rs 一行静音门（QA 源码亲读）；活证=M14 两轮双证+铁证③；book §2 口径入章 |
| **AU8 ⚪ 加载失败静默** | **记档结案**（不修）。M6/L7 红证腿两轮红绿闭环（红：settings 0.6 原样+SoundLive ABSENT+`Path not found` ERROR 归档；绿：0.6 回归）；book §7「Missing file (silent)」作者面如实披露+30 秒红绿对照 |
| **「Audio Source 从标记补齐为功能」字面闭环** | **成立**。六能力词逐词：**引用**=M1（Add→Pick/Browse→存/重开四件+派生标记）；**播放**=L3/M3/L5+staged 三通道 sink 数值+position 前进；**停止**=Once 播完自止+DESPAWN 自灭（M3 生灭）+文档切换停承载（flow 切 Level→MenuBgm 消、Ambient 进）；**循环**=Loop+position 前进活证；**音量**=三类 mix live 数值+master 追认；**空间衰减**=spatial+listener 挂相机 rig+emitter authored 位+KeyW 驱动 listener 跟随（9.21→6.77），bevy 语义=pan 非 HRTF 如实注记。三件套从「名字+标记+小方块」变为「说话的实体」，且游戏侧零新引擎机制（定性表兑现） |
| **buglist/roadmap/台账纪律** | buglist T16 域关联票 A6/A8/A9/A10 **均未打钩=正确**（A6 定案口径放行未修；A8 知悉绕行=全泛型路径纪律；A9 脚本自守未前置；A10 复现先行无动作）——git log 亲核 buglist 仅被 T1/T2 收官提交触碰（QA verdict 归档+A10 立票+A7 并账=合规动作）；roadmap 第 30 行未勾（留主控合入）；台账 progress.md 含 T16 方案/T1/T2 行，T3 行留主控合入 |

## 七、偏差与记档分级（QA 视角，全部 ⚪ 不阻塞）

| # | 项 | 处置 |
|---|---|---|
| 1 | **两测试债的隔离复跑/全二进制计数无独立归档日志**（报告称「隔离复跑各 1/1 绿；inspector 166/166；stage nextest 489/489」）——QA 未复跑隔离件，改为**从终树 integration 日志逐行点数**：inspector 二进制 PASS 恰 166、stage 恰 489、两二进制 FAIL=0、两修复件 PASS 在案——比独立日志更强的源，声明采信成立 | 已闭合（以终树日志为准） |
| 2 | **doctests bind dyld 家族第 9 次目击**：主跑仅 `-p jackdaw_bind --doc` 失败、单包复跑 1 passed，双日志归档齐备——T15 定案环境票口径，非 T16 引入 | 记档（T15 口径沿用） |
| 3 | **T3 报告偏差 3 的「红态在案」位置含糊**：工具红态（EDITOR_BOOT_FAIL+dyld 死）实际存于工作目录 `loop/t16-live/{console-all,editor-all}.log`（已随提交入库），非 `loop/reports/` 归档名——QA 找到并亲读，声明属实但检索面不直观 | 措辞勘误随本报告入档 |
| 4 | **book 交叉引用 vs 方案书单**：方案 §四-T3-2 点名 `animation.md`，实际动画章双向均未挂链（动画↔音频本里程碑无自然交点；实际落点=SUMMARY+player-controller+game-flow+game-ui，T3 报告如实列明） | 措辞级偏差记档；不影响验收 |
| 5 | **L1 reopened 截图浮层仍在**（模态跨 save/reopen 存活）——按改序设计该浮层只属 L1 自身证据（两轮同形），状态断言全在 BRP+文档 grep；且该卡面 AudioPlayer 显示 None=T2 偏差 5 已记档的 ReflectHandle 序列化现象，路径断言落盘（QA 在 fixture scene.bsn 亲见 blip.wav 行）为更强证据 | 记档（A7 邻域工具票：模态生命周期归脚本面，随 A7 第 6 腿同批） |

**未动面**：`src/`、`crates/`、fork、协议、场景格式——T3 零改动（T16 全弧产品面=T1 的 19 文件
+T3 的 book/tests 两件）；buglist/台账/roadmap 本轮未写（主控合入时落笔）。

## 八、最终裁决与 roadmap 建议

- **T16-T3 验收标准（方案 §四-T3）**：14 格终态复跑（两相 16 判定，超出 L3/L6/L9 下限）✅；
  book 新章八节+SUMMARY+交叉引用 ✅（§三）；buglist 预期无打钩 ✅；台账/roadmap 留主控 ✅；
  终验门全量（fast/integration/doctests/docs/scaffold_e2e 日志全文复核+QA 亲跑八门）✅（§一）。
- **AU 系收口**：🔴 AU1/AU2 全修、🟡 AU3/AU4/AU5 全修、⚪ AU7 修（静音门语义）、⚪ AU6/AU8
  记档（T18 域+book 作者面披露）；探针副产物（泛型不自动注册=三处显式注册）带常驻断言结案。
- **T16 整体（T1/T2/T3）**：验收句三铁证全数独立在案（§四）；「Audio Source 从标记补齐为功能」
  字面闭环成立（§六）；fast 2987/teaches 90/integration 5417/5418（唯一红=A6 定案口径，QA 独立
  复现同签名+隔离绿）双轮吻合；integration 层两处 T1 遗留测试债自捕自修且仅触 tests/（§二）；
  T2 QA 回流三项全兑现（§五）。
- **VERDICT: PASS——T16 整体闭环。roadmap T16（第 30 行）建议可勾选**，闭环注记建议含：
  三铁证独立在案（三音三通道 sink 数值+staged 导出同值/L9 三 bus 隔离+master 追认+M7 授权面/
  M14 双证+launch.rs 静音门）；AU1-AU5/AU7 修、AU6/AU8 记档留 T18；integration 5417/5418 唯一
  红=A6（QA 独立复现同签名+隔离绿，定案口径；首跑 3 红=两测试债已修，仅 tests/ diff）；A10 立
  票复现先行、A8 绕行（全泛型路径纪律）、A9 自守；⚪ 偏差五项不阻塞。
- 主控合入路径照旧 `--no-ff`（e65a4f9e 单提交）；台账 T16 行、roadmap 勾选由主控合入时写
  （本轮 QA 零产品/台账/buglist/roadmap 触碰，工作树仅新增 QA 归档 10 件+门链脚本+本报告）。

## 九、用户 30 秒耳听清单（book §8 的实机版，T2 QA 采信版沿用）

1. **设备预检**：`afplay assets/sounds/blip.wav` —— 3 秒内听到一声短 blip（输出设备在位）。
2. **三音**：新工程 `cargo run` → Menu **听到 BGM 循环**；点 **Start** → 一声点击，进 Level 听到
   空间嗡鸣，**走动时声像随距离/方位移动**。
3. **三类控制**：编辑 `assets/audio-config.bsn`：`music: 0.5` 重跑 → BGM 变小；`master: 0.0` →
   **正在响的乐声当场全静**（不追认缺口已被模板 mix 补齐的听感面）；改回复原。
4. **导出可响**：导出包启动 → 与 Play 同样出声。
5. **编辑器静音**：打开编辑器浏览带 BGM 的场景 → **听不到任何声音**（听到=AU7 回归立账）。

## QA 会话产物索引

- 门禁八门+定向一腿：`loop/reports/t16t3_qa_{fmt,libtests,fast,audio_gate,clippy_physics,
  integration,docs,scaffold_e2e,a6_isolated}.log`+`t16t3_qa_gates_progress.log`；脚本
  `loop/qa/t16t3-qa-gates.sh`（串行，unset RUST_BACKTRACE）。
- 核验对象：`loop/reports/t16-t3-report.md`+归档 t16t3_* 37 件（门禁 12+真机 36 中亲读
  console 两相/summary 两相/warn 五件/n13/13 witness/4 截图/首跑红摘录）+`loop/t16-live/`
  工作目录（偏差 3 红态两件+staged/direct 日志）；`loop/qa/t16-live.sh` 加固三处+词表亲读；
  T1/T2 报告与 QA+buglist A6/A7/A8/A9/A10+roadmap 第 30 行+progress 台账 T16 行；两测试债
  diff 全文+终树 integration 日志点数；book 五文件+模板/编辑器/fork 源码对照点（menu.bsn.
  template/scene.bsn/lib.rs.template 三音与 mix 与 SoundLive/launch.rs 静音门/main.rs.template
  裸 DefaultPlugins）；fixture 盘上终态（flow/sounds 三件/audio-config 缺省/menu 四件/L1 尾迹/.bak 三份）。
- 进程收尾：QA 复查零 jackdaw/t16-audio/afplay 残留进程（门链自身件随链退出）；数据卷
  89Gi；门链独窗；RUST_BACKTRACE 全程未设；工作树除 QA 归档新增外零触碰。

—— QA agent，2026-10-30
