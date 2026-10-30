# T16 任务 1「引用授权门 + 三类控制机制」程序报告

> 分支 `loop/t16-audio`（自 main 053eed43）；任务书 `loop/plans/t16-audio.md` §四-T1；
> 主控裁定 8 决策点全按建议执行（1=bevy 原生组件直接授权+模板主入口 / 2=模板内建三类控制 /
> 3=config 资产+BRP mutate 演示 / 4=加 wav / 5=launch.rs 静音门一行 / 6=SoundLive 镜像 /
> 7=A7A9 不前置脚本自守 / 8=标记派生全组件）。改动 19 文件 +943/−30（7 件模板/门禁，
> 3 个生成 wav 入库），零 fork 改动、零协议变更、零场景格式变更、零产品 runtime crate 改动。

## 〇、决策 1 首步探针结论（必记项）：**A 成立，不回落 B**

探针以常驻断言落位 `tests/audio_gate.rs`（7 测试全绿），四个事实定案：

| # | 探针 | 结论 |
|---|---|---|
| ① | `build_reflective_default(AudioPlayer<AudioSource>)` | **None**（v2 预测实锤：无 `ReflectDefault`+`Handle` 字段挡死字段递归回退）⇒ AudioPlayer 永不入 Add Component picker，**模板主入口是唯一正门**，picker 缺席记档 |
| ② | bsn 全值 patch `AudioPlayer<bevy_audio::audio_source::AudioSource>("sounds/probe.wav")` | **应用成功**（tuple-struct 无 Default 回退路径，prefab IsA 先例同路）——但**必须泛型全路径**：短写 `AudioPlayer(...)` 报 `type not in the registry`（A8 纪律的泛型版，模板 bsn 与教学一律全路径） |
| ③ | PlaybackSettings 部分 patch | 成功（有 `ReflectDefault`，字段种子正确）；**裸类型行** `bevy_audio::audio::AudioPlayer`（无值）warn-and-skip，钉死「音频作者必须写全值」教学点 |
| ④ | Volume 元组变体往返 | `bevy_audio::volume::Volume::Linear(0.5)` 场景往返无碍（T09 元组枚举前科未复发） |

**探针过程新发现（方案 v2 未载，偏差 1）**：**泛型类型不在 reflect inventory 自动注册范围**
（bevy_reflect 文档明言 auto-register 不适用于带泛型的类型）。后果=`AudioPlayer<AudioSource>`
在任何进程（编辑器/游戏）都必须显式 `register_type` 才能进 AppTypeRegistry——本轮在三处补齐
（编辑器 `EntityOpsPlugin`、模板 `GamePlugin`、bsn_game fixture `GamePlugin`）。
这正是首轮探针 bsn 腿红掉（`cannot apply '...AudioPlayer<...>': type not in the registry`）
的根因；未注册时编辑器保存的 AudioPlayer 在**重开时会整组件被丢弃**——授权门不只「加得上」，
还要「回得来」，三处注册是门框本身。

## 一、AU 系处置（对应验收词）

| AU | 严重度 | 处置 | 落点 |
|---|---|---|---|
| AU1 引用授权门 | 🔴 | **已开（决策 1-A）** | ①`entity.add.audio_source` 模板升级：spawn 即附 `AudioPlayer(Handle::default())`+`PlaybackSettings::default()`（Rust 侧 insert 不经反射 Default）；②编辑器 `EntityOpsPlugin` 注册 AudioPlayer（泛型注册补丁，见上）；③asset_row 扩展名臂（AU3）；④typed_values 非反射资产回退（偏差 3）；⑤picker 对 AudioPlayer 的缺席=探针①常驻断言记档 |
| AU2 三类控制无形态 | 🔴 | **已建（决策 2-A/3-A）** | 模板 `GameAudioConfig{master,music,sfx}`（Asset+Resource，`ConfigPlugin::new("audio-config.bsn")`，T08 三态纪律同款）+`MusicBus`/`SfxBus` 标记（@EditorCategory("Audio")）+`apply_audio_mix`（config 变更→全 sink 重应用）+`apply_audio_mix_to_new_sinks`（Added→建帧追认）双系统——GlobalVolume「不追认」缺口补齐（fork volume.rs:7 语义）+`SoundLive` 镜像（决策 6-A）；BRP mutate 演示腿归 T2 L3/L9 |
| AU3 资产 picker 不认音频 | 🟡 | **已修** | `asset_row.rs` `file_extensions` 加 `AudioSource` 臂 `["ogg","oga","wav"]`+Browse 对话框记忆新 `DialogPurpose::Sound`；Pick/Browse/拖放/可撤销提交全套机件免费获得 |
| AU4 标记 gizmo 重开即失 | 🟡 | **已修（决策 8-A）** | `derive_audio_source_marker` 观察者（`On<Insert<AudioPlayer>>`→补插 `SceneAudioSource`，derive_world_asset_root 同型）：文档重载/undo/tab swap 全路径重派生，游戏侧零噪音（标记仍是 `jackdaw::` 保存跳过） |
| AU5 解码面窄 | 🟡 | **已修（决策 4-A）** | 三处：workspace bevy features+`"wav"`；`bevy_source::dependency_with_features()` 帮手（git/version 双形态合法 TOML，TOML 解析单测钉死）+scaffold `{{bevy_dependency}}` 改走帮手；fixture Cargo.lock 刷新（hound 3.5.1 入锁）。编辑器与模板游戏同获 hound |
| AU6 坏音频解码 panic | ⚪ | 记档不修（方案口径） | fork 层 unwrap，T18 导入域领走 |
| AU7 编辑态即播+PIE 双声 | ⚪ | **已修（决策 5-A v2 形态）** | `launch.rs` DefaultPlugins 一行 `AudioPlugin { global_volume: 0.0 }`：引擎建 sink 帧乘一次 GlobalVolume ⇒ 编辑器侧 sink 仍建、音量恒 0，零系统零时序；PIE 双声免疫 |
| AU8 加载失败静默 | ⚪ | 记档 | T2 M6 红证腿（坏引用→GS 无 sink） |

决策 6（SoundLive 镜像）落地为模板组件 `{kind, volume, paused, finished, position_secs}`
（kind∈music/sfx/plain，小定案字段名），`mirror_sound_live` 每帧从 `AudioSink`/`SpatialAudioSink`
读值回写并**自动插入**到一切在响实体——「可检视的音频」教学件+T2 GS 数值通道载体
（sink 本体未反射，BRP 读不到；镜像一帧滞后，断言口径加 settle）。

## 二、模板音频段（lib.rs.template +957→约 +250 行；决策 2-A）

- **doc 头部新增「Game audio」导览段**：三音三件套（menu BGM/按钮 blip/场景 spatial drone）、
  三类控制语义（base×bus×master+「引擎不追认已播 sink」注记）、SoundLive 镜像指路、
  spatial=pan 非 HRTF 注记。
- **类型**：`GameAudioConfig`（Default 全 1.0）/`MusicBus`/`SfxBus`/`SoundLive`+`mix_volume`
  纯函数（与探针测试、fixture 三方同型——测试侧为 spec，模板/fixture 为实现）。
- **系统**：`apply_audio_mix`（config changed→双形态 sink 全量重应用）+
  `apply_audio_mix_to_new_sinks`（Added 追认）+`mirror_sound_live`。写成两系统是刻意的：
  单系统混 Added 滤镜与全量查询会 &mut AudioSink 冲突，且「每帧无条件写」会踩掉游戏自己的
  sink 调音——只在 Added/config 变更两个时机出手。
- **按钮音**：`on_screen_pressed` 三分支（start/restart/menu/resume）各发一个一次性实体
  `AudioPlayer::<AudioSource>(server.load("sounds/blip.wav"))`+`PlaybackSettings::DESPAWN`+`SfxBus`
  ——「停止」词的 DESPAWN 活证；turbofish 必须（默认泛型参数不参与表达式推断，冷编第一轮实测）。
- **SpatialListener**：`spawn_player` 的相机 rig 实体附 `SpatialListener::default()`——空间音随玩家。
- **场景种子**：menu.bsn.template 加 `#MenuBgm`（AudioPlayer 全泛型路径+sounds/bgm.wav+Loop+0.6+MusicBus，
  A8 口径全路径拼写）；scene.bsn 加 `#Ambient`（Loop+0.8+`spatial: true`，位置 (6,2,-4)）。
  流切换换文档时随文档生灭（runtime 的 switch 语义）——BGM 只在 Menu 响，场景音只在 Level 响。
- **模板自带三个生成 wav**（偏差 5）：`assets/sounds/{bgm,blip,ambient}.wav`（python3 `wave`
  生成，22050Hz/mono/16-bit：bgm 2.0s 双正弦相位连续可无缝 Loop；blip 0.12s 指数衰减；
  ambient 3.0s 低鸣循环；共 ~225KB）。生成器 `loop/t16-live/gen_wavs.py`（AN4 hero.glb
  先例同款不入库保留件，`python3 gen_wavs.py <assets>/sounds` 可复跑）。`afplay`
  实播对照腿已过（blip exit 0）。
- **冷编落袋**：`jd new t16-audio` 全新工程（wav feature+sounds 三件）`cargo build` **3m22s 过**
  （M1 Pro，物理模块默认开）——模板音频段真实可编的活证；工程保留
  `/Users/zhanglinbo/workspace/loop-mac/t16-audio/t16-audio` 供 T2 注入 jackdaw_remote 复用。

## 三、红→绿证据

| 腿 | 红证 | 绿证 |
|---|---|---|
| 授权门（picker 拒绝/接受） | 探针①：AudioPlayer 不可默认构造=picker 结构性拒绝，**常驻断言**（`audio_component_default_constructibility_matches_the_gate_analysis`）；泛型未注册时 bsn 红证=`cannot apply ... type not in the registry`（bsn_game e2e 首轮实录） | 三处注册后 e2e 零 warn 装载+出声；asset_row/typed_values 新单测钉住接受面 |
| 引用通路（bsn 全值形态） | 探针②短路径红（type not in registry） | 全泛型路径装载成功、Handle 解析到 authored 路径、字段值逐一对（audio_gate 2/3/4 号测试） |
| 三类控制（mix 数学+追认） | —（新功能，红=代码形态） | headless sink 三件：mix 数值（0.4×0.8×0.5=0.16）、bus 路由（music/sfx/plain 各随其道）、**config 改 0 追认已播 sink**（GlobalVolume 不追认的反证）；真管线 e2e=AUDIO_SINK_LIVE volume=0.160 |
| 静音门（AU7） | —（一行配置） | 引擎语义由探针「master 0→sink 0」同机制钉住；编辑器进程活体对照归 T2 M14 |
| 标记重开（AU4） | —（新功能） | `an_audio_player_from_any_source_derives_the_marker`：裸实体 insert AudioPlayer→观察者补标记（文档重载/undo 同路径） |
| wav 解码（AU5） | — | fixture e2e 实证 .wav 经 AudioLoader 解码出声（wav feature 绿态）；模板冷编含 sounds 装载路径 |

## 四、门禁（最终树重跑，日志归档 `loop/reports/t16t1_*`）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **CLEAN**（先行 `cargo fmt --all` 修 7 文件格式） | （check exit 0） |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | **CLEAN（0 warning/error 行）**；最终树由 fast 的 clippy 步覆盖复证（t16t1_fast.log:4 起，0 warning） | t16t1_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | **CLEAN** | t16t1_clippy_physics.log |
| 单测 | `cargo nextest run --profile ci --workspace --lib --features dylib` | **2987/2987（基线 2981+6）** | t16t1_libtests.log |
| fast | `cargo xtask fast` | **2987/2987（exit 0）；全文复核：0 error/0 FAILED/0 Diff（唯一 grep 命中系测试名 `error::tests::…`）** | t16t1_fast.log |
| 音频门（新常驻） | `cargo test --test audio_gate` | **7/7** | t16t1_audio_gate.log |
| bsn_game e2e | `cargo test --test bsn_game_run built_game_loads -- --nocapture` | **PASS**（`AUDIO_SINK_LIVE kind=music volume=0.160 paused=false finished=false`；stderr 扫描 WARN/cannot-apply/No-audio-device **零命中**） | t16t1_bsn_game_e2e.log |
| 模板冷编 | fixture 工程 `cargo build` | **3m22s 过**（首轮 E0283 教出偏差 8，修后过） | t16t1_fixture_coldbuild.log |
| teaches | scaffold lib tests | 89→**90**（+1 音频针；8 teaches 全绿） | （libtests/fast 内） |

新增测试计数：scaffold +1（teaches audio）、jackdaw src +4（entity_ops×2/asset_row/typed_values）、
jackdaw_project_build +1（feature 依赖双形态）、root integration 新二进制 +7（audio_gate）。
fast 实数 **2987**（=基线 2981+6；audio_gate 是 integration 二进制，不入 fast lib 计数）。

**warn 形态扫描**：bsn_game e2e 绿态 stderr 扫描 `audio|No audio device|cannot-apply|WARN`
**零命中**（红态首轮的 `cannot apply ... AudioPlayer` 已由三处注册消除，红态实录见 §三）；
fast/libtests 日志 0 warning 行。`position=0.35` 等时值逐 run 波动属正常（音频流实时读数）。

**磁盘**：门前 37Gi 可用（92% 用量，偏紧——fixture target 与 repo target 并存；T2 前 QA 照旧清盘）。

## 五、偏差清单（如实）

1. **⚠️ 泛型类型不自动注册（方案 v2 未载，本轮最重要发现）**：`AudioPlayer<AudioSource>`/
   `Handle<T>` 等泛型类型被 reflect inventory 自动注册跳过——编辑器/模板/fixture 三处显式
   `register_type::<AudioPlayer<AudioSource>>()`。它改变了坑甲的性质：不只是「picker 进不去」，
   而是「不注册则文档重载整组件静默丢弃」。方案回退序①「全值形态授课」仍成立但不够，
   注册是前置。三处注册均已带测试或 e2e 锚。
2. **⚪ BSN 音频行必须泛型全路径**：`AudioPlayer<bevy_audio::audio_source::AudioSource>(...)`——
   A8 纪律的泛型版；模板 bsn、教学、fixture 全按此拼写，探针红绿两态均在档。
3. **⚪ AudioSource 非 Reflect**：方案「Handle 编辑机器全现成」在 `typed_values::asset_type_path`
   一环不成立（资产类型须在注册表才能命名）——加一个 TypeId 特判回退（非反射资产类型表），
   单测钉住。AudioPlayer.0 字段由此获得完整 asset row（Pick/Clear/拖放）。
4. **⚪ 「EditorCategory Audio 归类」落点折衷**：bevy 类型无法外加 reflect 属性（fork 纪律），
   picker 分组回落 `TypeChrome::group` 的 crate 名（"bevy_audio"）——Audio 归类落在
   **inspector strip 新 "audio" 类目**（builtin_extensions 注册点，与方案指名的注册点一致）：
   PlaybackSettings/SpatialListener/AudioPlayer 卡进同组 Audio tab；模板新类型（MusicBus/SfxBus/
   SoundLive/GameAudioConfig）带 @EditorCategory("Audio")，在 Add Component picker 的分组名
   正确显示 "Audio"。
5. **⚪ 模板自带三个生成 wav（二进制入库 ~225KB）**：方案小定案只把脚本生成列给 QA fixture；
   但 T1 验收「模板新工程 cargo run menu 出 BGM」要求模板带真文件（bsn 路径引用经 AssetServer
   必须落盘）。生成参数与再生成方法本报告 §二；仓库先例=assets/ 二进制资产族（glb/png/ttf）。
6. **⚪ audio_gate 无设备处置=panic 非 skip**：clippy `print_stderr` 禁 eprintln；且「无设备时
   静默 pass」与 bsn_game e2e 硬断言口径不一致——统一为 fail-with-reason（环境依赖已 doc 声明）。
7. **⚪ bsn_game_run 档位现状=heavy 非 integration**（xtask `SDK_BINARIES` 常量实证）：方案
   §四-T1-7「随 integration 档」与现状不符；本轮未改档位（T15 决策 4 的显式腿模式不适用于本
   无 feature-gate 腿），按 heavy 现状直跑验证，QA 门禁表按 `cargo test --test bsn_game_run`
   或 heavy 档计。
8. **⚪ press_sound 需 turbofish**：`AudioPlayer::<AudioSource>(server.load(...))`——默认泛型
   参数不参与表达式推断（冷编 E0283 实测）；教学价值正向（与 bsn 全路径纪律互文）。
9. **🟡 mix 三系统链漏 `.chain()`，e2e 抓到真竞态**：fixture/template 初版把
   `(apply_audio_mix, apply_audio_mix_to_new_sinks, mirror_sound_live)` 写成裸元组并注释
   「Chained:」——bevy 元组顺序只是歧义消解提示**不是执行顺序**，mirror 抢跑一帧时
   SoundLive 落下原始 base（e2e 复跑实录 `volume=0.400`≠0.160，17s 那轮）。修=三系统
   `.chain()`（模板+fixture 两处），复跑 28.9s 绿、归档日志 volume=0.160。**QA 注意**：
   归档链里 17s/0.400 那份已被覆盖（覆盖式归档纪律），竞态本身是本报告偏差 9 的活样本；
   T2 若再见到 volume=base 而非 mix 值，先查系统链再查 config。

## 六、给 QA 的注意事项

1. **编辑器进程现在是静音的（AU7 裁定语义）**：编辑视口/PIE 编辑侧 sink 音量恒 0——「打开带
   BGM 的场景就出声」按裁定**不该发生**；「可响」验证一律走游戏进程（direct run/PIE 游戏侧/
   导出包）。若 QA 在编辑器听到声音=静音门被破，按 AU7 回归立账。
2. **inspector 出现新 "Audio" 类目**（PlaybackSettings/SpatialListener/AudioPlayer 卡）；Add
   Component picker 里 bevy_audio 三件分组名仍是 "bevy_audio"（偏差 4），模板四类型分组名是
   "Audio"——视觉腿按此口径核对。
3. **T2 GS 通道**：游戏 BRP 读 `SoundLive` 镜像（模板/fixture 游戏自带；字段 kind/volume/paused/
   finished/position_secs），一帧滞后需 settle；sink 本体（AudioSink/SpatialAudioSink）未反射，
   BRP 不可见——别按组件名直查 sink。
4. **e2e 音频腿的设备依赖**：`audio_gate` sink 三件与 `bsn_game_run` 音频断言都要求本机有音频
   输出设备（本机有）；无设备机器 fail 而非 skip，属声明过的环境依赖，不算产品回归。
5. **fixture 工程**：`/Users/zhanglinbo/workspace/loop-mac/t16-audio/t16-audio` 已建（wav feature、
   sounds 三件、音频段模板），T2 注入 jackdaw_remote 两行 sed 即可复用；`assets/sounds/*.wav`
   可 `afplay` 人耳对照（ogg 不行，wav 可以）。
6. **teaches/fast 新基线**：scaffold 90、fast **2987**；audio_gate 7 件
   是 root integration 档新二进制，QA 的「任务相关门」建议显式列 `cargo test --test audio_gate`。
7. **warn 扫描口径**：`cannot apply 'bevy_audio::audio::AudioPlayer...` 出现=泛型注册回归
   （红态形态，见 §三）；`No audio device found`=无设备环境；两者以外音频域 warn 均应归因。
8. 未动面：buglist/台账/roadmap 未改（T3 口径）；A7/A9 未前置（决策 7），T2 脚本自守
   （`$PHASE` 日志名+SoundLive 小响应体+settle 重试）。
