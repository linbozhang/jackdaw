# T16 任务 1「引用授权门 + 三类控制机制」QA 验收报告

> 分支 `loop/t16-audio` @ 65e38efe（工作树 clean，验收零改动）；核实对象
> `loop/reports/t16-t1-report.md`；任务书 `loop/plans/t16-audio.md` §四-T1 + §五决策点表
> （主控 8 点全裁建议）；T08 ConfigPlugin 三态纪律为同构先例。
> QA 全程只读+亲跑：门禁 7 门、探针 7 测试、e2e 真管线、AU 六项、偏差 9 条全部本机复证。
> 未设 RUST_BACKTRACE；未改产品代码/buglist/台账/方案；QA 日志归档 `loop/reports/t16t1_qa_*`（8 件）。

## 裁决：**PASS**（放行 T16-T2 真机矩阵轮）

依据浓缩：门禁 7 门亲跑全绿（fast/libtests 双通道 2987、teaches 90）；决策 1 探针 7/7 亲跑，
四断言与编辑器源码+fork 源码语义互证成立；AU1-AU5/AU7 处置逐条源码级实证；三类控制数学
（0.4×0.8×0.5=0.16、bus 路由、master 0 追认已播）headless 亲跑+真管线 e2e 双源一致；偏差
9 条全部建议吸收，其中 2 条带证据精度附注（非阻塞，见 §五-观察）。

## 〇、门禁表（QA 亲跑，2026-10-30 12:38-12:47，日志归档 `loop/reports/t16t1_qa_*`）

| 门 | 命令 | 结果（全文复核，exit 仅辅助） | QA 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **CLEAN**（exit 0，零 diff 输出） | t16t1_qa_fmt.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | **CLEAN**（`warning` 零命中行） | t16t1_qa_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | **CLEAN** | t16t1_qa_clippy_phy.log |
| 单测 | `cargo test --workspace --lib --features dylib` | **2987/2987**（逐 crate `test result` 求和=2987 与 fast 复证一致；scaffold=**90**=teaches 预期、jackdaw=1192、project_build=227）；4 个 error 形态命中**全部归因为负例测试**（material 解析失败喂错/PIE E0560 喂错/jackdaw.toml 喂错/`error::tests::` 测试名），零真失败 | t16t1_qa_libtests.log |
| 音频门（任务相关） | `cargo test --test audio_gate` | **7/7** | t16t1_qa_audio_gate.log |
| 真管线 e2e | `cargo test --test bsn_game_run built_game_loads -- --nocapture` | **PASS**（17.5s；`AUDIO_SINK_LIVE kind=music volume=0.160 paused=false finished=false`；stderr `WARN/cannot-apply/No-audio-device/UnresolvedTypes/panic` 扫描**零命中**） | t16t1_qa_e2e.log |
| fast | `cargo xtask fast` | **2987/2987**（末行 `Summary 2987 tests run: 2987 passed, 0 skipped`；error/FAILED/Diff 扫描仅 2 个含 "panicked" 的**测试名**命中=负例命名；warning 命中=clippy 命令行自身+2 个测试名；内含 fmt --check 步） | t16t1_qa_fast.log |

与程序报告门禁表交叉核：程序 2987（nextest profile ci）/QA 2987（cargo test 求和）双通道一致；
程序 clippy/物理双包/fmt 归档与 QA 重跑一致；`cannot apply ...AudioPlayer` 红态形态在 QA
绿态两轮（audio_gate+e2e）零复现=泛型注册回归信号未触发。磁盘门前 28Gi 可用（偏紧，T2 前照旧清盘）；
结束核查无残留游戏/编辑器进程。

## 一、决策 1 探针复核（`tests/audio_gate.rs` 7/7 亲跑 + 源码/registry 语义互证）

| # | 断言 | 亲跑结果 | 互证（源码级） |
|---|---|---|---|
| ① | AudioPlayer 无 ReflectDefault ⇒ 永不入 Add Component picker（模板主入口=唯一正门） | `audio_component_default_constructibility_matches_the_gate_analysis` 绿（None 断言） | fork `bevy_audio/src/audio.rs:249` `#[reflect(Component, Clone)]`（无 Default）；`build_reflective_default`（src/reflect_default.rs）语义=ReflectDefault 优先、否则字段递归，`Handle` 枚举首变体叶子 Opaque 无 ReflectDefault ⇒ `return None`——字段递归被 Handle 挡死的机制逐行成立；对照 PlaybackSettings（:34）与 SpatialListener（:172）均 `#[reflect(Clone, Default, Component, Debug)]` ⇒ 测试双 Some 断言成立 |
| ② | bsn 泛型全路径全值 patch 可用（`AudioPlayer<bevy_audio::audio_source::AudioSource>("sounds/probe.wav")`） | 绿（Handle 解析到 authored 路径） | apply 全值构造走 tuple-struct 路径不经 Default；短写=另一 TypePath=未注册类型（机制同 A8，红态引文 `type not in the registry` 机制见下） |
| ③ | PlaybackSettings 部分 patch 走 ReflectDefault 种子；裸类型行 warn-and-skip | 绿（部分 patch volume 缺省 1.0；裸行不落地断言） | apply.rs:378 `cannot apply '...': no ReflectDefault registered`（裸行走的正是「无值可建」路径）——「作者必须写全值」教学点钉死 |
| ④ | Volume 元组变体往返（`Linear(0.5)` 写入读回） | 绿（②内嵌：`to_linear()-0.5<1e-6`；T09 前科未复发） | fork volume.rs Volume derive Reflect + PartialEq |

**偏差 1 新发现核实（「泛型类型不在 reflect inventory 自动注册」）——fork 文档原文实锤**：
`/Users/zhanglinbo/workspace/bevy-fork-pinned/crates/bevy_reflect/src/lib.rs`（`auto_register_inventory`
节）逐字："However, this does not apply to types with generics: their desired monomorphized
representations must be registered manually."——泛型单态化表示**必须手动注册**，方案 v2 未载属实。
三处显式注册逐一在位：编辑器 `EntityOpsPlugin`（src/entity_ops.rs `.register_type::<AudioPlayer<AudioSource>>()`）、
模板 `GamePlugin`（lib.rs.template:300）、bsn_game fixture（tests/fixtures/bsn_game/src/lib.rs:164）。

**「漏注册=保存重开整组件静默丢弃」红态证据是否在档：不在档（🟡 证据精度点，见 §五-观察 A）**。
但机制代码级成立：`crates/jackdaw_bsn/src/apply.rs:401/563` `cannot apply '<type_path>': type not
in the registry`=warn-and-skip（实体照生成、组件被丢——作者视角静默）；且该红态形态已进 QA warn
词表（见 §四-8）。采信程序报告引文（红态首轮实录）+机制复核+修后绿证双源。

## 二、AU 逐条复核（源码级，全部实证）

| AU | 程序处置 | QA 复核结论 | 关键证据 |
|---|---|---|---|
| AU1 🔴 引用授权门 | 已开（决策 1-A） | **实证成立** | `create_entity` AudioSource 模板 spawn 附 `AudioPlayer(Handle::default())+PlaybackSettings::default()`（src/entity_ops.rs，Rust insert 不经反射 Default，探针①钉死 picker 缺席=结构性而非遗漏）；EntityOpsPlugin 泛型注册；picker 缺席=常驻断言记档 |
| AU2 🔴 三类控制无形态 | 已建（决策 2-A/3-A/6-A） | **实证成立** | 模板 `GameAudioConfig`（Asset+Resource、Default 全 1.0、`ConfigPlugin::new("audio-config.bsn")` T08 三行同款）+`MusicBus`/`SfxBus`（@EditorCategory("Audio")）+`apply_audio_mix`（`is_changed()` 全量重应用）+`apply_audio_mix_to_new_sinks`（Added 追认）+`SoundLive{kind,volume,paused,finished,position_secs}`（=小定案五字段）+`mirror_sound_live` 自动插入在响实体；fork `volume.rs:7` 原文 "Changing GlobalVolume does not affect already playing audio" 实证双系统补的正是这个引擎缺口 |
| AU2·偏差⑨ mix 链序 | `.chain()` 修 | **实证成立（红证不在档，见观察 A）** | 两处 `(apply_audio_mix, apply_audio_mix_to_new_sinks, mirror_sound_live).chain()`（lib.rs.template:305+fixture lib.rs:182）注释钉死「tuple order is not execution order」——与 bevy 多线程执行器语义一致；修后 e2e 双源绿（0.160） |
| AU3 🟡 资产 picker | 已修 | **实证成立** | `file_extensions` AudioSource 臂 `["ogg","oga","wav"]`+`DialogPurpose::Sound` 贯穿 Browse 记忆（`AssetBrowsePick.purpose` 回填同 purpose）+单测（音频臂不扩图片臂断言在内）。📋 观察 C：loader 真实 vorbis 扩展面含 `spx`（fork audio_source.rs `extensions()`），picker 刻意不列（代码注释自述 speech 非此 row 用途）——文档化选择，非缺陷，T18 导入域复核一句 |
| AU4 🟡 标记重开丢失 | 已修（决策 8-A） | **实证成立** | `derive_audio_source_marker` 观察者 `On<Insert<AudioPlayer>>`→补插 `SceneAudioSource`（derive_world_asset_root 同型，文档重载/undo/tab swap 全路径）+单测 `an_audio_player_from_any_source_derives_the_marker`；标记仍 `jackdaw::` 保存跳过=游戏侧零噪音 |
| AU5 🟡 解码面窄 | 已修（决策 4-A） | **实证成立（三处全在）** | ①workspace `Cargo.toml` bevy features `+"wav"`；②`bevy_source::dependency_with_features()`（git/version 双形态 inline table，TOML 解析单测双形态断言）+scaffold 依赖行改走帮手+`standalone_scaffold.rs` 断言同步；③fixture `Cargo.lock` hound 入锁（:3270）+workspace lock（:3948）。模板自带三 wav（bgm 88,244+ambient 132,344+blip 5,336=225,924B≈225KB 与报告一致）；`gen_wavs.py` 22050Hz/mono/16-bit 与报告口径一致 |
| AU6 ⚪ 解码 panic | 记档不修 | 符合方案口径 | fork `audio_source.rs` unwrap 层，T18 领走 |
| AU7 ⚪ 编辑态即播/双声 | 已修（决策 5-A v2） | **实证成立+语义边界核实** | `launch.rs` `DefaultPlugins.set(AudioPlugin { global_volume: Linear(0.0), ..default() })` 一行；引擎语义=fork `audio_output.rs:193/263` 建 sink 帧乘一次（`settings.volume * global_volume.volume`）⇒ 编辑器 sink 仍建、音量恒 0、authored PlaybackSettings 零触碰；**边界**：游戏 `main.rs.template` 用裸 `DefaultPlugins`（无 AudioPlugin 覆写）⇒ Play/游戏进程/导出包 GlobalVolume=1.0 不受扰——「编辑器不作为发声体、声属于 Play/游戏进程」裁定语义字面落地；M14 活体对照留 T2 |
| AU8 ⚪ 加载失败静默 | 记档 | 符合方案口径 | T2 M6 红证腿 |

## 三、三类控制数学复核（铁证②的 H+e2e 双层）

- **H 层（audio_gate 亲跑，设备许可分支本机走通）**：
  `a_sink_receives_base_times_bus_times_master_and_follows_a_config_change`——sink `volume()`
  =0.4×0.8×0.5=**0.16** 断言（`empty()==false`+未 pause 同钉）→ `master=0.0` 后两帧内已播 sink
  归零断言（GlobalVolume「不追认」的反证活体）；`bus_routing_sends_each_sink_its_own_factor`
  ——music 0.5/sfx 0.25/plain 1.0 各随其道；`despawn_mode_removes_the_audio_entity_when_the_clip_ends`
  ——「停止」词的 DESPAWN 机形（播完实体自灭）。设备依赖已 doc 声明且 fail-with-reason（观察 D）。
- **spec-实现同型三方锚**：`effective_volume`（audio_gate）≡`mix_volume`（模板 lib.rs.template）≡
  `mix_volume`（fixture lib.rs）——测试侧为 spec、模板/fixture 为实现，同型互审。
- **真管线 e2e 双源一致**：程序归档 `t16t1_bsn_game_e2e.log` 与 QA 亲跑 `t16t1_qa_e2e.log` 同录
  `AUDIO_SINK_LIVE kind=music volume=0.160 paused=false finished=false position=0.35`——
  编辑器构建管线→BSN 全泛型路径装载→Handle 解析→真 AudioPlugin→sink→`.chain()` mix→SoundLive
  镜像全链；`Bgm Probe` 实体在 `BSN_SCENE_LOADED` 名单；stderr 零意外 warn。
  （`position` 时值逐 run 波动=音频流实时读数，正常口径，两轮恰好同值。）

## 四、偏差 9 条裁定建议（逐条）

| # | 程序偏差 | QA 裁定建议 |
|---|---|---|
| 1 | ⚠️ 泛型类型不自动注册（本轮最重要发现） | **吸收**。fork 文档原文实锤（§一）；三处注册在位；红态性质认定（不只是 picker 进不去，更是文档重载整组件丢弃）与 apply.rs warn-skip 机制一致。词表新增：`cannot apply '...AudioPlayer<...>': type not in the registry` = **泛型注册回归信号**。后续任务引入带泛型的 bevy 组件一律显式 register_type |
| 2 | ⚪ BSN 音频行必须泛型全路径 | **吸收**。A8 纪律的泛型版；短路径红态与偏差 1 同机制（未注册类型）；模板 bsn 种子/教学/fixture 三处拼写一致（menu.bsn.template:43 实证） |
| 3 | ⚪ AudioSource 非 Reflect ⇒ typed_values TypeId 特判回退 | **吸收**。回退有单测（反射资产走 registry/非反射走特判双断言）；备注一句：硬编码 TypeId 特判在非反射资产类型增多时宜注册表化——归 T18 资产导入域记档，不阻塞 |
| 4 | ⚪ EditorCategory Audio 落点折衷 | **吸收**。`TypeChrome::group` crate 名回退实证（type_metadata.rs 测试组：无 authored category 时 `bevy_pbr::…`→"bevy_pbr"）；inspector strip 新 "audio" 类目（order 45/Volume2 图标，builtin_extensions 注册点=方案指名点）+模板四类型 @EditorCategory("Audio") 双面如实；bevy_audio 三件在 Add picker 分组名 "bevy_audio" 的视觉口径已给 T2 |
| 5 | ⚪ 模板自带三个生成 wav（~225KB 二进制入库） | **吸收**。文件与尺寸核符；`gen_wavs.py` 复跑方法在档；「验收要求模板新工程开箱出 BGM ⇒ bsn 路径引用必须落盘」的理由成立；仓库 assets/ 二进制族先例同型 |
| 6 | ⚪ audio_gate 无设备处置=panic 非 skip | **吸收**。fail-with-reason 与 bsn_game e2e 硬断言口径一致（「静默 pass」会伪造 sink 事实）；clippy print_stderr 禁 eprintln 的理由成立；环境依赖已在测试 doc 头声明 |
| 7 | ⚪ bsn_game_run 档位现状=heavy 非 integration | **吸收**。xtask `SDK_BINARIES` 实证 `binary(bsn_game_run)` 在列、integration filter=`not (SDK_BINARIES)`——方案 §四-T1-7「随 integration 档」确与现状不符，程序按 heavy 现状直跑+不改档位是对的做法；QA 门禁表按直跑/heavy 计 |
| 8 | ⚪ press_sound 需 turbofish | **吸收**。模板 :1188-1190 带注释（「默认泛型参数不参与表达式推断」）；E0283 教学件与偏差 2 互文 |
| 9 | 🟡 mix 三系统链漏 `.chain()`，e2e 抓到真竞态 | **吸收+证据精度附注**。修在两处（模板+fixture）且注释钉死机制；竞态形态（mirror 抢跑一帧落 base 0.400）与 bevy 元组序≠执行序语义一致、修后绿证双源——但**红证日志不在档**（观察 A）。程序报告 §五-9 的 T2 注意事项（见 volume=base 先查系统链再查 config）有效，照单吸收 |

## 五、QA 观察（证据精度点，全部非阻塞）

- **A·红态日志不在档（两份）**：泛型注册红态 e2e（`cannot apply ... type not in the registry`）
  与竞态红态 e2e（volume=0.400）均被修后绿档**覆盖式归档**覆盖——覆盖纪律的字面执行，但红证只剩
  报告引文。采信依据=机制代码复核（apply.rs:401/563+bevy 执行器语义）+探针常驻断言+修后双源绿。
  **回流建议**：自 T2 起，红态日志先存 `*_red.log` 再修再覆盖绿档（一行 mv 的成本，红绿对照是
  M1/L7/M6 等腿的验收形态）。
- **B·冷编日志只有尾段**：`t16t1_fixture_coldbuild.log` 4 行（3 行 Compiling+Finished 3m22s），
  非零起全程记录（bevy 无 Compiling 行=含增量段）；「3m22s」宜读作修后增量段口径。冷编结论本身
  成立：Finished 行+fixture 工程 arm64 二进制在盘（QA 实证 target/debug/t16-audio 存在）+e2e 走
  同源构建管线。T2 若需严格冷编口径，清 fixture target 重跑一次即可。
- **C·AUDIO_EXTENSIONS 少 `spx`**：loader 在 vorbis 下接受 spx，picker 刻意不列（代码注释自述）；
  文档化选择，T18 导入域复核一句。
- **D·设备依赖 fail-loud**：audio_gate 三件与 e2e 音频断言在无输出设备机器上 fail 非 skip——
  声明过的环境依赖（doc+偏差 6），不算产品回归；本机（M1 Pro/macOS 26.6）sink 全链走通。

## 六、T2 放行建议

**放行**。交接面与风险面：

1. **fixture 交接**：`/Users/zhanglinbo/workspace/loop-mac/t16-audio/t16-audio` 已建且可编
   （wav feature、sounds 三件、模板音频段、arm64 二进制与热 target）；T2 注入 jackdaw_remote
   两行 sed（t15-live.sh:488-497 先例）复用；`assets/sounds/*.wav` 可 `afplay` 人耳对照（L2）。
2. **GS 通道口径**：BRP 只读 `SoundLive` 镜像（kind/volume/paused/finished/position_secs，
   模板/fixture 自带）；sink 本体未反射不可直查；镜像一帧滞后 ⇒ 每腿 settle 再断言。
3. **warn 词表**：`cannot apply '...AudioPlayer<...>'`＝泛型注册回归（红态形态，见档外引文+机制）；
   `No audio device found`＝无设备环境；`volume=base 而非 mix 值`先查系统链再查 config（偏差 9
   词形）；其余音频域 warn 逐条归因，零意外命中是 M13 的门。
4. **L 腿风险面**：N13 PIE 腿（L4/M3）绕行+记数，direct 为主通道；A9 自守=SoundLive 小响应体
   +settle 重试+避开构建窗口；M14 双声对照按 AU7 语义执行——**编辑器进程应静音，听到声=AU7
   回归立账**，PIE 游戏侧应出声；L7/M6 坏引用红绿腿的红证先归档（观察 A 纪律）。
5. **环境与磁盘**：音频腿要求输出设备（本机有）；磁盘 28Gi 偏紧，T2 开门前清盘照旧（T15 口径）；
   门链与编辑器/游戏同窗互踩纪律照旧（单独跑）。
6. **验收句提醒**：机械化证据=GS 数值在案（铁证①②各格）；「可响」的耳听终审=用户 30 秒清单
   （三音+三类控制听感）随 QA 报告草稿交主控。

## 七、QA 归档清单（`loop/reports/t16t1_qa_*`，8 件）

`fmt / clippy_ws / clippy_phy / libtests / audio_gate / e2e / fast` 七门日志+本报告。
（注：e2e 日志名 `t16t1_qa_e2e.log`；其余按 `t16t1_qa_<门>.log`。）
