# T16 任务 3「终验 + book 章」程序报告

> 分支 `loop/t16-audio`（自 main 5a59f016 fast-forward 同步）；任务书 `loop/plans/t16-audio.md`
> §四-T3。真机 macOS arm64（M1 Pro），fixture `/Users/zhanglinbo/workspace/loop-mac/t16-audio/
> t16-audio`（T1 建、T2 注入），编辑器 BRP 15703 / 游戏 BRP 15702，全程未设 RUST_BACKTRACE。
> **判语：book 音频新章落地；14 格终态两相全 PASS（16 腿判定，数值与 T2/QA 双轮一致）；
> 全量门绿——integration 终树复跑 5417/5418、唯一红=A6 已知件（隔离 1/1 绿）。本轮另修
> 两处 T1 遗留测试债（详见偏差 1，均为 tests/ 测试基建，src/ 零改动）。**

## 〇、最终判定汇总（日志全文复核，exit 仅辅助）

```
editor 相（终树复跑）: L1_M1_CHAIN=PASS M12_REOPEN_CONSISTENT=PASS M14_EDITOR_MUTED=PASS
                       M7_AUTH_FACE=PASS WARN_SCAN_EDITOR=PASS
game 相（本轮复跑）:   L2_AFPLAY_CONTROL=PASS L3_M2_BGM=PASS M3_DIRECT_CHAIN=PASS
                       L5_M4_SPATIAL=PASS L9_M10_ROUTING=PASS M7_PLAY_FACE=PASS
                       L7_M6_BADREF=PASS L4_M3_PIE_CLICK=PASS L10_M11_STOP_INVARIANT=PASS
                       L6_M5_EXPORT=PASS WARN_SCAN_GAME=PASS
```

归档：`loop/reports/t16t3_live-*`（36 件：console 两相、summary 两相、warn 五件、n13 计数、
15 件 witness/快照、4 张截图）+ 门禁 `t16t3_{fmt,clippy_ws,clippy_physics,audio_gate,libtests,
fast,integration,doctests,doctests_bind_rerun,doc,scaffold_e2e,a6_isolated}_log` +
`t16t3_gates_progress.log`（逐门时间线）。`loop/t16-live/` 工作目录同步随本轮刷新入库。

## 一、book 新章（方案 §四-T3-2 全项）

**`book/src/user-guide/audio.md`**（新章，SUMMARY 排 Game UI 后），八节：

1. 开篇导览——「编辑器=作者面、永不发声；游戏=发声体」的分工声明（三音先行的模板承诺）。
2. **The editor is silent**（M14/AU7 语义）：静音门=编辑器进程 GlobalVolume 钉 0，authored
   数字零触碰；「听见编辑器出声=回归要上报」写明；线框标记 survive save/reopen（派生）。
3. **Adding a sound**：Add > Audio & Animation > Audio Source；`AudioPlayer`（asset row：
   Pick/Browse/拖放/路径/Clear）+ `PlaybackSettings` 字段表（mode 四值含 Despawn 的自灭
   语义/volume/spatial/speed/paused/muted）；**AudioPlayer 不在 Add Component picker 的
   原因如实写**（句柄无意义默认值，模板实体=正门；bevy_audio 三件在 picker 按 crate 组
   名出现——T1 偏差 4 的口径）；BSN 全泛型路径纪律带代码样例；存/重开四件原样。
4. **The template's three sounds**：三音表（MenuBgm 0.6 Loop MusicBus / press_sound
   DESPAWN SfxBus / Ambient 0.8 Loop spatial (6,2,-4)）；「循环音的停止=不再承载它」
   （文档生灭→[Game Flow] 指路）；SpatialListener 挂玩家相机 rig→[Player Controller]
   指路；**spatial=按距离/方位的双声道 pan，非 HRTF** 如实注记。
5. **The three-way mix**：`base × bus × master` 公式；GameAudioConfig 三字段+New Asset
   （config-asset 范式→[Game Parameters] 指路）；MusicBus/SfxBus/plain 路由表；**引擎
   「GlobalVolume 只在建 sink 帧读一次、不追认」的 quirk 与模板 mix 双系统补齐**；运行中
   改 config 即刻生效写明；SoundLive 镜像字段表（kind/volume/paused/finished/position_secs，
   Resources 面板+BRP 可读=「可检视的音频」）；T17 设置屏指路（资源非绑定目标，经少量
   游戏代码写→[Game UI] 绑定种类指路）。
6. **Files and formats**：ogg/wav 在册；mp3/flac 未启用（picker 不列、loader 不解）→
   T18 指路如实。
7. **When a sound doesn't play**：AU8 静默态（实体在、sink 无、日志一行）vs 坏字节崩溃态
   （AU6 现状如实）；30 秒版红绿对照（missing.wav→静音+日志点名；改回→乐声回来）。
8. **The 30-second check**：五步（afplay 预检→cargo run 三音→config 三态→导出→编辑器静音）。

交叉引用落地：`SUMMARY.md` 挂目；`player-controller.md`（相机 rig 一节加 SpatialListener
指路）；`game-flow.md`（跨场景规则表 Scene members 行补主题乐例+一段「换文档=循环音的
停止钮」）；`game-ui.md`（按钮段补 click 指路）。mdbook 不在门禁内（book 构建为外部面），
章内相对链接六目标逐一核实存在。

## 二、关键格终态复跑（AN10 先例口径：修后 game 通道核对）

方案 §四-T3-1 点名 L3/L6/L9 三腿；本轮实跑**两相 16 判定全 PASS**（game 相 11+editor 相 5），
超出下限。数值与 T2/QA 双轮对齐：

| 腿/格 | 本轮数值 | 与 T2/QA 对齐 |
|---|---|---|
| L3 BGM（M2） | SoundLive `{music, 0.6}`，position **6.62→8.67** 前进；master mutate 0→已播 sink 即刻 0.0→复原 0.6 | volume/mute 周期一致；position 属实时流读数逐 run 不同（T2=3.12→5.17），前进语义一致 |
| L9 三 bus（M9/M10） | baseline sfx:0.4/music:0.5/plain:0.8 → music 0 只哑 MusicProbe → sfx 0 只哑 SfxProbe → master 0 全哑 → 复原 | **四步数值与 T2/QA 两轮逐字节一致** |
| L6 导出（M5） | staged 异目录启动：plain:0.8 + music:0.5 + sfx:0.4 + 包内 sounds/ 三件+manifest | 与 T2 staged 三值一致 |
| M3 按钮音 | direct：blip 0.4 生灭+flow 切 Level（MenuBgm 消、Ambient 进=停止词）；PIE：真点击命中（+911 带）caught=2 | 与 T2 一致 |
| M7 play 面 | 编辑器改 music 0.5 → 运行游戏资源读回 `{1.0, 0.5, 1.0}`，MenuBgm=0.3 | 与 T2 一致（0.6×0.5） |
| L7 坏引用（M6） | 红：settings 0.6 原样在+SoundLive ABSENT+`Path not found` ERROR（`*_red` 归档）；绿：0.6 回归 | 与 T2/QA 红绿一致 |
| L10/M11 | PIE 往返 menu.bsn SHA 不变；全部 .bsn 零 AudioSink 痕迹 | 一致 |
| L5 空间（M4） | Ambient plain:0.8+listener 717v0+emitter (6,2,-4)=authored；KeyW 驱动 z→-2.44，listener 9.21→6.77 跟随 | 一致 |
| M14 编辑器静音 | 编辑器 `GlobalVolume={"volume":{"Linear":0.0}}`，authored MenuBgm **0.6 原样未触碰** | 一致（AU7 门在位；**编辑器出声=AU7 回归立账** 口径沿用） |
| M12 重开一致 | before/after 全等（player present+Loop 0.6+handle+bus+文档泛型路径） | 一致 |
| warn 扫描（M13） | 两相泛型注册回归（`cannot apply…AudioPlayer`）=**0**；游戏通道音频域 warn=**0**；非音频模板态归因 **14 条**（config 缺省×5+bind 首帧×9=勘误口径复现）；`No audio device`/`decoder`/`UnresolvedTypes` 全零 | 一致 |
| N13 记数 | **2**（PIE 腿 connect 后 drain panic，`vec/mod.rs:2258` 同签名×2；T2=3，随 PIE 连接次数浮动）；PIE 腿照常完成=绕行有效 | 签名一致 |

## 三、门禁（终树，日志归档 t16t3_*；逐门时间线在 gates_progress.log）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **CLEAN**（0 字节） | t16t3_fmt.log |
| 音频门（M8 终锚） | `cargo test --test audio_gate` | **7/7**（2.65s） | t16t3_audio_gate.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | **CLEAN**（终树复跑） | t16t3_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | **CLEAN** | t16t3_clippy_physics.log |
| 单测 | `cargo test --workspace --lib` | **2987/2987**（teaches 90） | t16t3_libtests.log |
| fast | `cargo xtask fast`（终树复跑） | **2987/2987**（Summary 净；2 处 "panicked" 命中=PASS 测试名） | t16t3_fast.log |
| integration | `cargo xtask integration`（**终树复跑**） | **5417/5418，唯一红=A6 已知件**（prefab_lifecycle.rs:714 三 try 同签名；隔离复跑 1/1 绿 2.97s=`t16t3_a6_isolated.log`，口径达成；A10 无涉、零新增红） | t16t3_integration.log |
| doctests | `cargo test --workspace --doc` | bind dyld rpath 家族**第 9 次目击**（`libstd-*.dylib not loaded`，仅 `-p jackdaw_bind --doc`）→**单包复跑 PASS**（T15 处方） | t16t3_doctests.log + t16t3_doctests_bind_rerun.log |
| docs | `cargo doc --workspace --no-deps` | **EXIT=0** | t16t3_doc.log |
| scaffold_e2e | `cargo nextest run --profile ci -p jackdaw --test scaffold_e2e` | **PASS 1/1**（149.3s） | t16t3_scaffold_e2e.log |

**integration 首跑（本轮 17:27，修复前树）曾见 3 红**：A6 已知件 + 下列偏差 1 的两处
T1 遗留测试债——修后终树复跑如上（5417/5418）。修复只动 tests/ 两文件，src/ 零 diff
（`git diff` 可证），其余门在终树复跑（fmt/clippy 双包/fast）。

## 四、偏差清单（如实）

1. **⚠️ integration 层自 T1 以来首跑揭出两处 T1 遗留测试债，本轮修复**（T1 QA 七门不含
   integration 层、T2 QA 零产品改动采信 T1——该层实际从未在 T16 产品改动后跑过）：
   - **`inspector::category_strip::category_tabs_carry_title_and_description_tooltips`**
     断言 diff 实证：`category_tab_tooltips` 实返 **7 元组含 `("Audio","How this entity
     sounds: playback, bus and listening.")`**，期望表 6 元组——`spawn_category_strip` 按
     注册表**逐类目出 tab**（category_strip.rs:146 循环无可见性过滤），T1 注册的 Audio
     类目（builtin_extensions.rs:423，order 45）天然在列。修=期望表补 Audio 元组+注
     （`tests/inspector/category_strip.rs`）。
   - **`stage::new_project::create_in_the_new_game_dialog…`** fork panic
     （bevy_asset server/info.rs:869 "asset type has not been initialized"）：测试基建
     `ambient_app_reading` **disable AudioPlugin**（tests/util/mod.rs:93 注释原由=无头
     不连后端）→ `AudioSource` 未 init；T1 模板 scene.bsn 从此带 `#Ambient`
     （`AudioPlayer("sounds/ambient.wav")`）→ 新工程打开场景时 handle 分配 panic。真编辑器
     无涉（AudioPlugin+静音门在装）。修=`ambient_app_reading` 补 `init_asset::<AudioSource>`
     + `init_asset_loader::<AudioLoader>`（纯解码零后端，无头场景装载与编辑器同行为）
     （`tests/util/mod.rs`）。
   **验证**：两测试隔离复跑各 1/1 绿；inspector 二进制全跑 **166/166**、stage 二进制 nextest
   **489/489**；终树全 integration 复跑仅 A6 红（上表）。
2. **⚪ modality 附注（防误读）**：`cargo test -p jackdaw --test stage`（cargo test 同进程
   并发）出现多测红（`isolate_config_dir` 全局态互斥，进程内并发互踩）——**门禁口径是
   nextest（进程隔离）**，同二进制 nextest 489/489 全绿。非本轮引入（基建既有性质），QA
   复核勿以 cargo-test 同进程形态判红。
3. **⚠️ 真机复跑首轮被两件工具问题拖掉（已修，红态在案）**：①编辑器二进制对 dylib 陈旧
   （T2 QA 门禁跑在真机后重编了 dylib 未重链 bin——T2 偏差 8 的复发）→ dyld Symbol not
   found 启动即死；②`brp()` 八次重试穷尽后的裸 `echo` 兜底**返回 echo 的退出码 0**→
   `editor_boot` 的 EDITOR_BOOT_FAIL 守卫失效→对死端口「boot 成功」，wait_idle 白烧 900s
   预算。修：`brp` 穷尽显式 `return 1`；`editor_boot` 判定加进程存活条件（`loop/qa/
   t16-live.sh` 两处小改，QA 工具面）。重链编辑器（23s）后复跑全绿。
4. **⚪ 编辑器相顺序重排（QA 回流§五-c 落实）**：L1 的 Pick 浮层跨越 save/reopen 存活并
   污染后续截图（T2 实况）——editor 相改序 **M14→M12→M7→L1**，浮层只出现在 L1 自己的两张
   截图（picker 本身即其拍摄对象）；本轮 m14/m7 截图亲验无浮层。断言面本就全在 BRP 读回+
   文档 grep，截图只升视觉证据质量。
5. **⚪ N13=2**（见 §二表）；**⚪ M13 归因拆分 5+9** 与勘误口径吻合。
6. **⚪ doctests bind dyld rpath 家族第 9 次目击**，T15 处方（单包复跑）有效，双日志归档。
7. **⚪ 磁盘**：integration 复跑前 9.8Gi（A6 家族压力区）——按 T14 磁盘清理族先例清
   `target/debug/incremental`（39Gi）+ 陈旧 fixture `t15-anim`（34Gi）/`t14-prefab`（20Gi）
   （T15/T14 已闭环、再生成脚本在案）→ **100Gi 可用**；`t16-audio` fixture 保留。
8. **⚪ fixture 终态核查**（QA 清单口径）：flow=menu.bsn、无 missing.wav 残留、无
   assets/assets 杂树、audio-config.bsn 缺省态、menu.bsn BGM 四件原样；scene.bsn 含 L1
   遗留 Audio Source 实体（T2 同款已知尾迹，任一相位开场的 write_scene_bsn canonical 即
   复位）+ 三份编辑器原子写 .bak（T2 同款无害）。

**未动面**：`src/`、`crates/`、fork、协议、场景格式——零改动（本轮产品面改动仅 tests/ 两
文件的测试基建）；buglist/台账/roadmap 未写（主控合入时落笔）；A10 已立票无动作。

## 五、给 QA 终验的注意事项

1. **门禁复核顺序**：`t16t3_gates_progress.log`（时间线）→ `t16t3_integration.log` 末行
   Summary（5417/5418+唯一红）→ `t16t3_a6_isolated.log`（A6 隔离绿）→ fast/libtests/fmt/
   clippy 各 log 全文。integration 首跑 3 红与终树复跑 1 红的差异=偏差 1 的两修复；首跑红态
   按 `*_red` 纪律摘录归档 `t16t3_integration-first-run-red_red.log`（终树复跑按覆盖式纪律
   覆盖了主日志，摘录系覆盖前 grep 原行，断言 diff 全文在案）。
2. **真机复跑可重入**：`loop/qa/t16-live.sh game` / `editor` 单相均可重入（prep 幂等）；
   门前先 `cargo build` 重链编辑器（偏差 3 的结构性守卫已在脚本内，但重链仍是前置）。
3. **截图**：本轮四张已净（浮层只属 L1 自身）；m14 截图=静音门视觉面（无浮层版）。
4. **词表沿用**：`cannot apply…AudioPlayer`=泛型注册回归（两相 0 命中）；`No audio device`=
   无设备；`volume=base 而非 mix 值`先查系统链再查 config。
5. **用户 30 秒耳听清单**（T2 QA §九采信版，本轮 book §8 已同步收录）：afplay 预检→
   cargo run 三音→config 三态→导出→**编辑器静音（听到=AU7 回归立账）**。
6. **heavy 档提示**：`bsn_game_run`/`editor_journey` 与本轮 tests/util 改动共享
   （两行 init_asset/init_asset_loader，无后端）——终验 QA 照旧跑 heavy 档即可，预期零影响。
7. **book 章**：`book/src/user-guide/audio.md` 八节+SUMMARY+三处交叉引用；事实面全部锚
   模板/编辑器源码（GameAudioConfig/SoundLive 字段、AudioPlayer picker 缺席缘由、
   spatial=pan 非 HRTF、AU8/AU6 双态）——QA 校对以章内断言对照 T1/T2 报告为准。
