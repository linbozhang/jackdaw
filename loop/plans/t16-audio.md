# T16 基础音频播放与音量 — 实施方案

> **v2（2026-10-28，重派策划全量复核版）**：首轮策划 agent 静默中断后留稿，本版由重派
> 策划**独立重走调研后逐条交叉核验**留稿的全部 file:line 声明——13/14 条实证成立（修订
> 一处行号：fork 音频格式 feature 实在 fork 根 `Cargo.toml:540-566`）；并修正留稿三处
> 技术性错误：①**headless 测试锚**（留稿 T1-6-② 写在 `jackdaw_runtime` dev 环境——该
> crate 的 bevy 依赖 `default-features = false` 且**不含 bevy_audio**（`crates/jackdaw_
> runtime/Cargo.toml:11-26`），`-p jackdaw_runtime` 测试连音频类型都命名不了；正确锚=
> 仓库根 tests/（workspace bevy 默认 features，`Cargo.lock:5258` lewton 实据）+
> `tests/fixtures/bsn_game` 窗口无头游戏 e2e（`tests/bsn_game_run.rs`+`tests/util/
> mod.rs:330` 现成先例），见新增**事实十五**）；②**坑甲的修复方向**（`register_type_
> data::<AudioPlayer, ReflectDefault>` 不可行：`CreateTypeData for ReflectDefault` 要求
> `T: Reflect + Default`（fork `bevy_reflect/src/std_traits.rs:23`）而 `AudioPlayer` 无
> `Default`，且孤立规则禁止外部补 impl；`ReflectDefault` 字段私有无自定义构造器——回退
> 改为「picker 缺席记档+模板主入口+全值 patch 形态」）；③**决策 5 落地形态具体化**与
> **决策 6 扩入 SoundLive 模板镜像通道**（零产品 crate 改动的替代案，建议为主）。
> 留稿引用的 fixture 实证（`loop-mac/t15-anim/` Cargo.lock 含 lewton）因该 fixture 已被
> T14 磁盘清理族移除而不可复核，v2 以同源证据替代：编辑器 workspace `Cargo.lock:5258`
> lewton/`:2614` cpal/`:7147` rodio+模板 bevy 依赖展开路径（`bevy_source.rs:35-40` 无
> default-features=false）——结论不变，证据换源。
>
> 首轮策划产物（2026-10-28，基于本地 main **78f2fa43**（T15 收官合入）全量只读调研：fork
> `/Users/zhanglinbo/workspace/bevy-fork-pinned` 的 bevy_audio 全 7 文件（1,893 行）+bevy_internal/
> bevy 顶层的 feature 图+default_plugins；编辑器 `src/entity_ops.rs`/`src/asset_ingest.rs`/
> `src/typed_values.rs`/`src/inspector/{component_picker,asset_row,reflect_fields}.rs`/
> `src/scene_io/mod.rs`/`src/launch.rs`；`crates/jackdaw_bsn/src/{apply,writer}.rs`；
> `crates/jackdaw_bind/src/{types,resolve,evaluate}.rs`；`crates/jackdaw_runtime/`
> （Cargo.toml feature 图+lib.rs 插件面）；`crates/jackdaw_scaffold/templates/game/` 全件；
> `crates/jackdaw_remote/`（BRP 工具面+SKIP_PREFIXES）；`crates/jackdaw_project_build/src/
> {bevy_source,export,modules.json}`；fixture 实证 `/Users/zhanglinbo/workspace/loop-mac/
> t15-anim/`（bevy 依赖行+Cargo.lock 含 lewton 实据）；`loop/qa/manual.md`+`loop/qa/t15-live.sh`；
> buglist.md 全量音频域扫描。**零临时探针**——关键结论（编辑器/游戏均已链接 bevy_audio、
> AudioPlayer 无 ReflectDefault 不入组件 picker、bind 写路径拒资源）全是静态可复核事实。
> 需求来源：`loop/plans/roadmap-game-dev.md` T16（P1 第十一项，T01-T15 已闭环）。
> **验收原文**（roadmap 第 30 行，逐字核实）：「**Audio Source 从标记补齐为功能（引用/播放/
> 停止/循环/音量/空间衰减）。验收=BGM/按钮音/场景音 Play+导出可响；主音量/音乐/音效三类
> 控制。**」
> **任务定性：混合型、建设面比 T15 大但仍是「开门」不是「造引擎」（约 55/45 偏建设）**——
> 与 T12/T15 同款反转读法第三次适用，但反转不彻底：bevy_audio 播放引擎（fork 1,893 行+
> rodio）在**编辑器与游戏两侧都已链接且活着**（编辑器 DefaultPlugins 自带 AudioPlugin，
> 模板游戏 bevy 依赖吃 default features 的 `audio`——fixture Cargo.lock 已见 lewton 实据），
> 六个能力词中「播放/停止/循环/空间衰减」的**机制层逐词成晶**；真正的缺口是**授权门**：
> 编辑器的 Audio Source 至今只是「名字+标记组件+线框小方块」三件套（`SceneAudioSource`），
> `AudioPlayer`（引用的载体）因无 `ReflectDefault` 进不了组件 picker，资产 picker 只认图片
> 扩展名——作者**没有任何通路**把一个音频文件挂到实体上；加上「三类控制」（主/音乐/音效）
> 在 bevy 本版**没有内建 bus**（仅单一 `GlobalVolume`，且改它不影响已在播的 sink），需要
> 模板层建最小机制。缺陷候选按 **AU 系**编号（Audio，避开 buglist R/Y/W/A/N 系与
> T01-T15 各任务编号系 U/I/F/C/PF/AN），只记不修→主控裁定吸收面。
> 真机口径：**macOS（本机）**，bash+curl+jq 驱动编辑器 BRP 15703 与游戏 BRP 15702
> （fixture 注入 `jackdaw_remote`，t15-live.sh 同款两行 sed）；direct run 为主、PIE 腿最少化
> （N13 绕行口径）；**勿设 RUST_BACKTRACE**（T11-T3 口径）；macOS 音频**输出**无 TCC 权限门
> （只有麦克风有——本任务零麦克风使用，核实结论见 §0 事实十三）；warn 形态扫描
> （`audio|No audio device|SpatialListener|UnresolvedTypes|cannot-apply`）入常备腿；
> **A9 工具债前置评估=不整体前置**（§五决策 7：T16 游戏 BRP 用量中等，以「小响应体新方法
> +settle 重试+避开构建窗口」自守；「可响」数值化走决策 6（v2：A=模板 SoundLive 镜像
> 为主，零产品 crate 改动）。

---

## 0. 架构事实（核实结论，方案的地基）

**总判断：T16 不是「建音频系统」——bevy_audio 播放栈（AudioSource→AudioPlayer→
PlaybackSettings→sink→cleanup、Volume、spatial ears/emitter）在编辑器与游戏两侧都已链接、
插件已装、反射已自动注册；T16 的建设=把编辑器授权门打开（引用/文件 picker/模板升级/标记
持久）+把三类控制的最小机制建进模板（config 资源+bus 标签+mix 系统）+把「可响」的验收腿
跑实。** 十四条事实：

- **事实一：bevy_audio 播放栈全套在场，逐词对应验收词。** `AudioSource`（raw bytes 资产，
  `audio_source.rs:7-21`）→`AudioPlayer(Handle<AudioSource>)`（挂实体即触发播放，
  `audio.rs:248-253`，`#[require(PlaybackSettings)]`）→`PlaybackSettings{mode,volume,speed,
  paused,muted,spatial,spatial_scale,start_position,duration}`（`audio.rs:33-71`，
  `#[reflect(Clone, Default, Component, Debug)]`）→PostUpdate `play_queued_audio_system`
  建 sink（`audio_output.rs:84-282`）→`cleanup_finished_audio` 播完清理（:284-323）。
  `PlaybackMode::{Once,Loop,Despawn,Remove}`（`audio.rs:11-26`）——**「停止」**=Once 播完
  自止/Despawn 移除实体/运行中 `sink.stop()`（`sinks.rs:99`）；**「循环」**=Loop→
  `repeat_infinite()`（`audio_output.rs:145-166`）；**「音量」**=`Volume::{Linear,Decibels}`
  枚举（`volume.rs:36-94`，含 to_linear/to_decibels/乘除运算，reflect+PartialEq）+
  `sink.set_volume`（`sinks.rs:26-172`）；**「空间衰减」**=`spatial:true`+`SpatialListener
  {left_ear_offset,right_ear_offset}`（`audio.rs:170-197`，`#[require(Transform)]`）+
  `SpatialAudioSink.set_emitter_position/set_ears_position`（`sinks.rs:336-355`）+
  `update_emitter_positions/update_listener_positions` 随 Transform 变更自动更新
  （`audio_output.rs:331-374`）——bevy 文档明示 spatial=左右声像 pan，非 HRTF
  （`audio.rs:55-57`），「衰减」的引擎语义=pan+距离，验收教学要如实注记。
- **事实二：编辑器进程与模板游戏进程都已经链接并运行 bevy_audio。** 编辑器 bevy 依赖
  带默认 features（`Cargo.toml:224-233` 无 `default-features=false`）→fork 顶层
  `default = ["2d","3d","ui","audio"]`、`audio = ["bevy_audio","vorbis"]`（fork 根
  `Cargo.toml:139,167`）→DefaultPlugins 含 `AudioPlugin`（`bevy_internal/src/
  default_plugins.rs:80-81`），`launch.rs:122` 实证编辑器走 DefaultPlugins——**编辑器
  世界现在就能出声**：实体挂上 AudioPlayer+已装载的 AudioSource，PostUpdate 播放系统
  当场建 sink。模板游戏 `bevy = {{bevy_dependency}}`（`templates/game/Cargo.toml.template:17`）
  经 `bevy_source::dependency()` 产出 `{ git=…, branch="main" }`（`bevy_source.rs:35-40`），
  同样 default features——fixture 实证：`loop-mac/t15-anim/Cargo.toml:20` 该行+
  `Cargo.lock:4012` 已含 **lewton**（vorbis 解码器）。**游戏侧今天缺的不是引擎是场景里
  没有 AudioPlayer 实体**。
- **事实三：「标记」形态=三件套，实体里没有任何音频组件。** Add 菜单「Audio & Animation」
  组的 Audio Source 项（`creation_taxonomy.rs:150,190-193`）走 `entity.add.audio_source`
  operator（`entity_ops.rs:2840-2853`）→`EntityTemplate::AudioSource`（:577,600）→spawn
  仅 `Name("Audio Source")+SceneAudioSource+Transform+Visibility`（:802-809）；
  `SceneAudioSource` 是纯标记（doc 自述「so viewport overlays draw a marker gizmo for it…
  the marker is the only on-screen cue」，:551-556），视口画 0.18 倍线框小方块
  （`viewport_overlays.rs:753-773`），图标 Volume2（`builtin_extensions.rs:44`）。
  **全仓 `AudioPlayer|PlaybackSettings|SpatialListener|GlobalVolume` 在编辑器 src/+crates/
  的注册/引用为零**（grep 实证）——「从标记补齐为功能」的字面事实。
- **事实四：bevy_audio 的作者组件其实已在编辑器反射注册表里，但授权门差三块板。**
  `reflect_auto_register`（fork bevy default_app 自带）使 `AppTypeRegistry` 构建时经
  inventory 自动注册全部 `#[derive(Reflect)]` 类型（`bevy_app/src/app.rs:115-119`
  `new_with_derived_types`+`bevy_ecs/src/reflect/mod.rs:58`）→`PlaybackSettings`
  （有 ReflectComponent+ReflectDefault）**预期今天已出现在 Add Component picker**
  （picker 全量走注册表：`component_picker.rs:123-131` 只要求 ReflectComponent+
  ReflectDefault+不 hidden+不 deny；T1 首步活证钉死）；而 **`AudioPlayer` 只有
  `#[reflect(Component, Clone)]`、无 Default 注册（`audio.rs:249`）→
  `build_reflective_default` 大概率返 None（component_picker.rs:129）→不入 picker**
  （v2 注：`build_reflective_default`（`src/reflect_default.rs:28-127`）无 ReflectDefault
  时走字段递归回退——`AudioPlayer(Handle)` 的成败取决于 `Handle` 枚举首变体的默认可构
  造性，`Arc<AssetPath>` 反射形态可能落 Opaque 臂返 None（:117-122）——**静态不可裁，
  T1 首步纯函数探针半分钟定案**；若 Some=AudioPlayer 竟已在 picker，AU1 收窄）。
  三块板：①AudioPlayer 不可加；②`asset_row` 的文件扩展名映射只认 Image
  （`asset_row.rs:579-587` `file_extensions`，其余类型返空→picker 显示「this project
  holds no AudioSource」且无 Browse 项，:597-609）；③`entity.add.audio_source` 模板
  不带任何音频组件。**Handle 字段的编辑机器全是现成的**：Inspector 的 Handle 字段行
  （reflect_fields.rs:354-373→`asset_row::spawn_asset_row`，Pick/Clear/New/拖放+可撤销
  提交，`asset_row.rs:1-11` doc）+路径文本解析（`typed_values.rs:23-38` `takes_asset_path`
  →`bsn_value_to_reflect` 复用）。
- **事实五：bsn 对音频组件的读写两侧都通，但有一个 Default 边角与一个 A8 坑。** 写侧：
  文档 writer 只走类型注册表（`jackdaw_bsn/src/writer.rs:33,253-266`），AudioPlayer/
  PlaybackSettings 已注册→照常序列化，Handle 经 ReflectHandle 解析为相对路径
  （writer.rs:16-20）；未反射的 `AudioSink` 天然进不了文档。读侧：`bsn_value_to_reflect`
  对 Handle<T> 先查工程 catalog、`#`/`@` 引用 miss 则 warn、**其余任意非空路径直接
  `asset_server.load_erased`**（`apply.rs:976-1008`）——`AudioPlayer(0: "sounds/bgm.ogg")`
  在编辑器与游戏装载即解析。坑甲：`AudioPlayer` 无 ReflectDefault，jackdaw_bsn apply 对
  部分补丁的构建路径可能需要（runtime Cargo.toml 注释明言「A widget marker only survives
  a load if something registers its reflected default」）——**T1 首步探针**定案。
  **v2 更正（坑甲修复方向）**：留稿的「炸则 `register_type_data::<_, ReflectDefault>`」
  **不可行**——`CreateTypeData for ReflectDefault` 要求 `T: Reflect + Default`
  （fork `bevy_reflect/src/std_traits.rs:23`）而 `AudioPlayer` 无 `Default`；
  `ReflectDefault` 的 `default` 字段私有、无自定义构造器（std_traits.rs:12-21），外部
  无法手搓实例；`impl Default for AudioPlayer` 被孤立规则阻断（外类型+外 trait 双外）。
  真实回退序：①**全值形态授课**（bsn 写完整元组 patch `bevy_audio::audio::AudioPlayer(
  "sounds/bgm.wav")`——整值构造走 FromReflect 路径，绕开 Default 补丁构建；编辑器模板
  spawn 也是 Rust 侧 insert，不经反射 Default）；②仍炸（部分补丁路径确需）→记 AU9、
  回落决策 1-B（自建桥接组件，自带 Default）。坑乙：A8（buglist）——BSN 必须
  全路径模块限定，`AudioPlayer` 的 TypePath 是 `bevy_audio::audio::AudioPlayer`
  （定义在 `audio.rs`），PlaybackSettings 同模块，`PlaybackMode`/`Volume` 是
  `bevy_audio::audio::PlaybackMode`/`bevy_audio::volume::Volume`——模板 bsn 种子与教学
  一律全路径，re-export 短路径会静默丢弃（A8 现票）。
- **事实六：编辑器侧标记不持久——重开即失。** `should_skip_component` 对 `jackdaw::`
  前缀一律跳过（`scene_io/mod.rs:163-165`），`editor_writer_config` 同步该前缀
  （:187）→`SceneAudioSource` 从不落文档；加载侧也无任何从 AudioPlayer 反派生标记的
  系统（grep 零命中）——**今天 Add 一个 Audio Source，保存重开后线框小方块消失**，
  只剩裸实体。对照模型链的 `derive_world_asset_root` 派生先例（entity_ops.rs:60 观察者）。
- **事实七：三类控制在引擎侧无内建 bus，且 GlobalVolume 有「不追认」语义。** fork
  bevy_audio 的音量面=单资源 `GlobalVolume`（`volume.rs:8-13`）+每 sink `Volume`；**没有
  Main/Music/Sfx 分轨**。且 doc 明言「Changing GlobalVolume does not affect already
  playing audio」（volume.rs:7）——引擎只在**建 sink 那一帧**读它乘一次
  （`audio_output.rs:193,263` `settings.volume * global_volume.volume`），无传播系统
  （lib.rs:58-72 只装 emitter/listener/queued/cleanup 四系统）。⇒「主音量/音乐/音效」
  必须自建：bus 标签组件+config 资源+一个重应用系统（对 `AudioSink`/`SpatialAudioSink`
  的 Added/Changed 读 `PlaybackSettings.volume` 底数×bus×master 重写 `set_volume`），
  同时捕获「config 改后新建的 sink」（新 sink 由引擎只按底数建）。
- **事实八：模板的接线挂点全在，且有 config 资产的成熟范式。** `GameConfig` 范式：
  `init_asset::<T>()+register_asset_reflect::<T>()+ConfigPlugin::<T>`（lib.rs.template:
  262-264），编辑器 New Asset 流程出 `game-config.bsn`（doc 段 lib.rs.template:26-43
  「game-wide numbers belong in a config like this」——**T12「per-entity 组件/game-wide
  config」纪律的原文落点**）；`GameFlow` 状态机 Menu/Level/GameOver（:245-247）+
  `on_screen_pressed` 观察者（:857）=**按钮音的现成挂点**；`DespawnOnExit(GameFlow::…)`
  模式（:424）=**BGM 随流切换启停的现成原语**；`enter_menu/enter_level/enter_game_over`
  （:671,702,716）与 hud.bsn 两屏（hud.bsn.template，PauseScreen :54-98）=控制面/T17
  设置屏的落点；`spawn_player` 链=**SpatialListener 的挂点**（现状无人挂——grep 零命中，
  bevy 在无 listener 时退化为原点双耳，`audio_output.rs:53-67`）。
- **事实九：bind 通道能读资源不能写资源——设置屏接线要绕。** bind 读路径支持
  `Res(Type).field`（`resolve.rs:689-711`，测试里就有 `Res(AudioSettings).master` 样例
  :854,934）；**写路径强制组件**：`resolve_write` 对 Resource 拼法直接
  `BindError::WritePathNotComponent`（resolve.rs:760-764）。⇒T16 若做滑条控制面，滑条→
  config 资源要过模板 observer（ValueChanged→写资源），不能直连 Field 绑定——这是
  「控制面本轮范围」决策的关键输入（§五决策 3）。
- **事实十：游戏 BRP 断言面。** 游戏（fixture 注入 `jackdaw_remote`，t15-live.sh:488-497
  两行 sed 先例：Cargo.toml 加依赖+main.rs 挂 `JackdawRemotePlugin`）BRP 15702 上：
  `world.query`/`world.get_components`/`world.get_resources`/
  `world.mutate_resources`/`world.insert_resources`（fork `bevy_remote/src/builtin_methods.rs:
  79-92`）——`GlobalVolume`（ReflectResource）、`PlaybackSettings`/`AudioPlayer`/
  `SpatialListener`（ReflectComponent）、模板 `GameAudioConfig` 与模板镜像组件（决策 6）
  全部**可读可写**；**`AudioSink`/`SpatialAudioSink` 未反射（`sinks.rs:138-139,242-243`
  纯 Component）→BRP 不可见**——sink 级证据只能进程内断言（headless Rust 测试）、经
  自定义 BRP 方法（`jackdaw_remote` 的 handler 直接查世界，`playback.rs`/`scene_snapshot.rs`
  先例）、或**模板侧镜像组件**（Rust 系统每帧从 sink 读值写回一个 Reflect 组件→
  world.query 直读，决策 6-A）。**v2 补充**：`jackdaw_remote` 不在模板/runtime 依赖里
  （`templates/game/Cargo.toml.template`+`crates/jackdaw_runtime/Cargo.toml` grep 零命中
  ——真实用户游戏不链接它，注入是 QA 惯例且**导出腿同理先注入再导出**）——决策 6 权重
  的关键输入。另 `jackdaw_remote`
  的 components.json 生成器跳过 `bevy_audio::` 前缀（`methods.rs:29` SKIP_PREFIXES），
  对 T16 无碍（编辑器本就原生有这些类型，不需要 schema 代管）。
- **事实十一：解码 feature 现状=编辑器与游戏都只有 vorbis。** fork 音频格式 feature：
  `wav`=hound、`vorbis`=lewton、`mp3/flac/aac`=symphonia（fork 根 Cargo.toml:540-566）；
  编辑器/游戏当前经 default features 只得 `vorbis`。**后果**：`.wav` 文件今日不被
  AudioLoader 接受（`extensions()` 按 feature 列出，`audio_source.rs:59-74`）→资产装载
  失败→静默不响；而**伪装/损坏但扩展名在册的文件会在解码 `unwrap()` 处 panic**
  （`audio_source.rs:93-102`）——AU 系风险候选（记档）。仓库 `assets/` 与模板 `assets/`
  **零音频文件**（find 实证）；编辑器 workspace `Cargo.lock:5258` 已有 lewton（vorbis 解
  码器在链）、`:2614` cpal/`:7147` rodio（输出栈在链）——链接面实证；拖放导入把音频归
  `AssetKind::Other`（「audio land here until their handlers exist」，`asset_ingest.rs:23`）
  ——文件能进 assets/ 但无处理器（T18 域，T16 只需「已在 assets/ 的文件可选可播」）。
- **事实十二：资产与导出通道对音频零障碍。** 导出按 assets_dir 整树拷贝
  （`export.rs:4-9,71-75`）——音频文件自动入包；编辑器 Handle 字段写路径文本即可回放
  （事实四/五）；fixture 音频文件来源：**脚本生成 wav**（AN4 hero.glb 先例同型——
  t15-live.sh 内 prep 生成/校验资产，`t15-live.sh:470-505`；python3 stdlib `wave` 模块
  零依赖产 PCM 正弦短音），`afplay`（/usr/bin/afplay，macOS 自带）可播 wav=「文件本身
  可听」的对照腿；afplay 不播 ogg——wav fixture 兼作人耳对照（决策 4 的又一输入）。
- **事实十三：Mac 音频输出无 TCC 权限门。** macOS 只对麦克风（输入）有用户授权
  （TCC）；CoreAudio **输出**设备任何进程可直接打开——rodio/cpal 建默认输出流无需
  提示（`audio_output.rs:20-33`，设备缺失时 warn「No audio device found.」+流为 None
  →播放系统 early-return，`audio_output.rs:103-106`——**无设备环境下 sink 不会出现**，
  headless sink 断言的环境依赖要如实声明）。本任务全程零麦克风使用。
- **事实十四：编辑器内播放与 PIE 的双声边角未定语义。** 编辑器世界 AudioPlugin 活着
  （事实二）→**打开带 BGM 的场景，编辑视口当场出声**；PIE 时游戏进程再出一路声——
  双声。编辑器无任何音频 gate/静音系统（grep 零命中）。对照 T15-AN5（PIE 期间编辑
  视口照播动画）同型边角，但音频的听感侵扰远大于动画——需要主控裁定语义（§五决策 5）。
- **事实十五（v2 新增）：headless 测试面的 feature 事实——测试锚不能放
  `jackdaw_runtime`。** 三层：①`jackdaw_runtime` 的 bevy 依赖 `default-features = false`
  精简集**不含 bevy_audio**（`crates/jackdaw_runtime/Cargo.toml:11-26`）→`cargo test -p
  jackdaw_runtime` 环境连 `AudioPlayer` 类型都命名不了——留稿 T1-6-② 的「runtime dev
  环境」锚**作废**；②仓库根 tests/ 的编辑器测试 crate 吃 workspace bevy **默认
  features**（根 `Cargo.toml:224` 无 default-features=false→`audio+vorbis`，`Cargo.lock:
  5258` lewton 实据）→root 集成测试可以构建「DefaultPlugins −render −winit、留
  AudioPlugin」的 App（`src/fps_overlay.rs:379` 测试先例同款构造）；③**更强的现成锚=
  `tests/fixtures/bsn_game`**：一个走编辑器构建管线的完整 fixture 游戏（bevy=git 默认
  features，`tests/fixtures/bsn_game/Cargo.toml:12`），`tests/bsn_game_run.rs` 经
  `build_project_binary` 构建、`tests/util/mod.rs:330 run_windowless_game` 以
  `JACKDAW_PIE_WINDOWLESS=1` 窗口无头运行并**管道捕获 stderr**——给该 fixture 场景加
  音频实体+fixture 游戏代码加 sink 状态 stderr 标记行，即得「真实管线→BSN 装载→
  Handle 解析→真 AudioPlugin→sink 生灭」的引擎级 headless e2e，且**免费搭上既有
  integration 门禁档**（bsn_game_run 已在档，T15 终验 integration 5404 含它）。
  注意 fixture 自带 `Cargo.lock`（:3），bevy 加 `wav` feature 后需刷新该锁。

### 验收句逐词定性（矩阵化的前提）

| 验收词 | 定性 | 依据 |
|---|---|---|
| 引用 | **缺口（AU1/AU3）** | AudioPlayer 无 ReflectDefault 不入 picker+资产 picker 不列音频扩展+模板不带组件（事实三/四）；Handle 编辑机器全现成 |
| 播放 | **机制成晶/授权缺口** | AudioPlugin 两侧在装+queued→sink→cleanup 全链（事实一/二）；但无授权面→无可播之物；Play 真机腿未跑 |
| 停止 | **验成晶（机制）** | Once/Despawn/Remove 三模式+`cleanup_finished_audio`+`sink.stop/pause`（事实一）；模板 `DespawnOnExit` 原语（事实八）；编辑器试听停止不在验收句面（决策 5 附带） |
| 循环 | **验成晶** | `PlaybackMode::Loop`→`repeat_infinite`（事实一） |
| 音量 | **半缺口（AU2）** | Volume 枚举+每 sink set_volume+GlobalVolume 全在；Inspector 对 PlaybackSettings 的枚举/数值字段编辑机器现成（reflect_fields/schema_fields）；但三类分轨无形态+GlobalVolume 不追认（事实七） |
| 空间衰减 | **半缺口** | spatial/SpatialListener/ears/emitter 更新系统全在（事实一）；但模板无人挂 listener+无教学；bevy 语义=pan 非 HRTF 需如实注记 |
| 验收①BGM/按钮音/场景音 Play+导出可响 | **缺口（AU1 前置）** | 三音无一可授权；PIE/导出通道成品（T06/T07）；「可响」的机械化证据形态需立（§二 GS 通道+决策 6） |
| 验收②主音量/音乐/音效三类控制 | **缺口（AU2）** | bus 标签+config+mix 系统待建；控制面落点=决策 2/3；bind 写资源不通（事实九）约束滑条直连 |

---

## 一、缺陷候选（AU 系，只记不修→主控裁定吸收面）

| 编号 | 严重度 | 描述 | 证据 | 处置建议 |
|---|---|---|---|---|
| **AU1** | 🔴 | **引用授权门未开**：`AudioPlayer` 无 ReflectDefault 不入 Add Component picker（picker 修复不可用 ReflectDefault 硬开——事实四 v2 注+坑甲 v2 更正）；`entity.add.audio_source` 模板是空壳（无音频组件）；作者无任何通路把音频文件挂上实体——验收句「从标记补齐为功能」的正主 | 事实三/四全链 | **吸收（本任务建设主体）**。主入口=模板升级（决策 1-A：Rust 侧 insert 不经反射 Default）；picker 缺 AudioPlayer 记档（模板实体自带组件，picker 面非必需） |
| **AU2** | 🔴 | **三类控制无形态**：引擎无 bus；GlobalVolume 单轨且不追认已播 sink；模板无 config/标签/mix 系统——「主音量/音乐/音效」三词零落点 | 事实七/八 | **吸收（建设主体）**。落点决策 2（建议 A：模板内建，T12 纪律纯血） |
| **AU3** | 🟡 | **资产 picker 不认音频文件**：`file_extensions` 只映射 Image（asset_row.rs:579-587），AudioSource 字段的 picker 无候选无 Browse | 事实四 | **吸收（AU1 附带一格）**：加 `bevy_audio::audio_source::AudioSource` 臂（ogg/wav 按 feature） |
| **AU4** | 🟡 | **标记 gizmo 重开即失**：`jackdaw::` 前缀保存即跳+无重派生——Add Audio Source 的视觉标识活不过一次 save/reload | 事实六 | **吸收（小件）**：加载后从 AudioPlayer 派生标记（derive_world_asset_root 先例）；持久化方案会引游戏侧 UnresolvedTypes 噪音，否决 |
| **AU5** | 🟡 | **解码格式面窄**：编辑器+模板只有 vorbis；`.wav`（自制 fixture 的天然格式、afplay 可播）今日不被接受→静默不响 | 事实十一 | **吸收（决策 4）**：编辑器 workspace features+模板/scaffold bevy 依赖加 `wav`（hound 轻依赖）；mp3/flac 留 T18 |
| **AU6** | 🟡 | **坏音频文件解码 panic**：AudioSource::decoder 的 `unwrap()`（audio_source.rs:101）——扩展名在册而字节损坏/伪装=进程崩；对照 T18 验收「坏文件不崩」 | 事实十一 | **记档不修**（fork 层 unwrap+上游语义，T18 导入域领走；T16 矩阵记红证一腿） |
| **AU7** | ⚪ | **编辑态即播+PIE 双声语义未定**：编辑器世界 AudioPlugin 活着，开场景即出声；PIE 时双进程双声 | 事实十四 | **决策 5 裁定**（建议 A：编辑态静音门——编辑器进程不作为发声体，声属于 Play/游戏进程） |
| **AU8** | ⚪ | **音频资产加载失败静默**：句柄指向不存在/不可解码文件时 `play_queued` 对未就绪资产 `continue`（audio_output.rs:110-112），无 warn 无提示，实体永远无声 | 事实一/五 | **记档**（作者态提示精神同 T15-AN3，但本轮不建 badge；红证入矩阵 M6） |

统计：🔴 2（AU1/AU2，均为验收缺口的建设面）｜🟡 4（AU3-AU6）｜⚪ 2（AU7/AU8）。

### buglist 重叠表（audio/声音/音量/音效域全量扫描）

| 条目 | 一句话 | T16 处置 |
|---|---|---|
| （无） | **音频域 buglist 零直接条目**（全量 grep audio/声音/音量/音效/sound/BGM 无命中）——音频系统从未被用户通路触达（AU1 挡着，T15-AN1 同构局面） | 缺陷主体是本方案新发现的 AU1-AU8 |
| A7 | t14/t15 真机驱动工具债（对话框提交+行定位+`jackdaw/screenshot` 同帧 flake+stale grep） | **前置评估=不整体前置（决策 7）**：T16 主链全 operator/BRP 直达、零原生对话框腿（引用授权走 asset_row picker=编辑器 chrome，ui_tree/ui_click 已覆盖）；截图只承担卡片视觉格，flake 风险与 T15 同档；脚本 warn 扫描沿用 `$PHASE` 日志名（A7 教训原文） |
| A8 | BSN crate 根 re-export 路径静默丢弃 | **知悉+绕行**：模板 bsn 种子与教学一律全路径（`bevy_audio::audio::AudioPlayer` 等，事实五坑乙）；fixture 腿验证 |
| A9 | 游戏 BRP 间歇空响应（高发=构建/坏引用 bind 重试窗口；大响应体优先被吃假说） | **自守不前置（决策 7）**：游戏 BRP 断言用小响应体（SoundLive 单组件过滤查询；决策 6-B 若裁则 handler 刻意精简）+settle 重试+避开 scene.open/构建窗口；direct run 冷启动后先 idle 探针再断言（t15 口径） |
| N13 | PIE connected 后 drain_game_events panic（100% 复发） | **绕行+记数**：T16 以 direct run 15702 为主通道，PIE 仅保留一腿（按钮音真点击） |
| N12 | bevy 原生与 jackdaw 方法实体域互不相通 | **知悉+绕行**：游戏侧断言全 bevy 原生 `world.*`；编辑器侧 jackdaw 方法 |
| A6 | prefab watcher 满载 flaky+磁盘高压家族 | **知悉**：门前清磁盘照旧；音频无 watcher 依赖 |
| 其余 | R/Y/W 系均为 prefab/brush/chrome 域 | 无动作 |

---

## 二、验收矩阵设计

**两铁证×通道=13 格主矩阵**。断言通道缩写：H=headless（root tests：纯函数 mix 数学
无条件；sink 级断言**设备许可**——Mac 有输出设备，机器无设备时 sink 不出现（事实十三），
环境依赖在测试 doc 声明+「No audio device found.」warn 形态扫描兜底；引擎级 e2e=
`bsn_game` fixture 窗口无头腿（事实十五③，integration 档现成位）；R=真机编辑器 BRP
15703（jackdaw 方法+bevy 原生）；G=真机游戏 BRP 15702（bevy 原生 `world.*`，fixture
注入 jackdaw_remote）；GS=sink 数值的游戏侧读出通道（决策 6 两案任一：**A=模板
`SoundLive` 镜像组件**（Rust 系统每帧从 `AudioSink`/`SpatialAudioSink` 读
volume/paused/empty/position 写回 Reflect 组件→G 通道 `world.query` 直读；建议）或
**B=`jackdaw/audio_status` 自定义 BRP 方法**（未反射组件 handler 直查，playback.rs
先例）；PX=截图。**「可响」的诚实口径**：机械化证据=sink 在场+`volume()==预期 mix 值`+
`empty()==false`/position 前进（GS/H 数值断言）+fixture 文件本身 `afplay` 可播；
**耳听终审=用户 30 秒清单**（机器无耳，M3/L5 数值断言先例的音频版）。

### 铁证①：BGM/按钮音/场景音 Play+导出可响

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| 授权链 | M1 | `entity.add.audio_source`（升级后）→asset_row Pick 选 `sounds/…`→PlaybackSettings 改 Loop/音量→Save→重开四件原样（含标记 gizmo 派生）→场景文档含全路径组件 | 🔴AU1/AU3/AU4 修复前置；R+PX |
| BGM | M2 | menu.bsn 的 BGM 实体（AudioPlayer LOOP+MusicBus）：direct run→GS 读 sink {playing, volume=base×music×master, spatial:false}→`world.mutate_resources` 把 master 改 0→GS volume=0（静音活证）→复原 | 🔴AU1/AU2 前置；G+GS |
| 按钮音 | M3 | Start 点击→一次性 sink 出现（GS kind=sfx）→播完 empty→组件清（Once/DESPAWN 语义活证=「停止」词）；PIE 腿走真 picking（T12 通道），direct 腿走 `on_screen_pressed` 同链 | 🔴前置；PIE+G+GS（N13 记数） |
| 场景音 | M4 | scene.bsn 空间音（spatial:true+Music/Sfx）+玩家相机挂 SpatialListener：direct→GS sink kind=spatial+listener 实体在场；`input.motion`/移动玩家→emitter 位置更新（GS 读 GlobalTransform 侧写+H 侧 update 系统在案） | 🔴前置；G+GS+PX |
| 导出 | M5 | `game.export`→staged 异目录启动→GS 同读 M2/M4 两件（BGM+场景音 volume/paused/spatial 全一致）+包内 `assets/sounds/` 文件在 | G+GS+盘（T07 形态复用） |
| 坏引用 | M6 | BGM 句柄指不存在文件→装载后静默不响（AU8 现状红证：GS 无 sink）+warn 扫描记录；修正后响 | ⚪AU8 记档格；G+GS |

### 铁证②：主音量/音乐/音效三类控制

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| config 授权 | M7 | New Asset→GameAudioConfig（master/music/sfx）→编辑器卡片改值→Save→Play/导出三态读回一致（T08 机器） | 🔴AU2 修复前置；R+PX+G |
| mix 数学 | M8 | 纯函数断言 `effective = base × bus × master`（无条件）；设备许可时 sink 断言同值（AudioSink/SpatialAudioSink 双形态） | 🔴修复前置；H |
| bus 路由 | M9 | Music sink 只随 music×master、Sfx 只随 sfx×master、无标签=master×1：headless 双 bus 实体+live 抽查一腿 | 🔴修复前置；H+GS |
| live 控制 | M10 | `world.mutate_resources` GameAudioConfig（master 0.0→音乐音效全哑；music 0.0→仅音乐哑）→GS 逐 sink volume 数值随动→复原 | 🔴修复前置；G+GS（M2 复用） |
| 横切·Stop | M11 | PIE 播 BGM→Stop→场景文档 SHA 不变+文档无 AudioSink 痕迹（未注册天然免疫，writer.rs:253） | T06 链音频形态 |
| 横切·重开/导出一致 | M12 | 配置→存→重开→AudioPlayer/PlaybackSettings/bus 原样（编辑器 R）；导出包场景同（M5 附带） | R+盘 |
| 横切·warn 形态 | M13 | 扫描 `No audio device|Multiple SpatialListeners|Spatial AudioPlayer with no GlobalTransform|UnresolvedTypes|cannot-apply` 全程零意外命中 | 脚本常备腿 |
| 横切·双声边角 | M14 | PIE 期间编辑器进程是否出声实测一次→决策 5 落地后的红绿对照+book 注记 | PX+人耳记档 |

**矩阵统计**：🔴 修复前置 9 格（AU1×M1、AU2×M2/M7-M10、按钮音链×M3、空间×M4/M5 半）｜
⚠️ 真机腿缺口 4 格（M1/M3/M5/M14）｜H 兜底 2 格（M8/M9）。T1 清源、T2 落判。

---

## 三、真机腿清单（Mac，bash+curl+jq；T2 集中跑）

fixture 工程=`jd new` 出 `/Users/zhanglinbo/workspace/loop-mac/t16-audio`（T14/T15 决策
同款；**建后注入 jackdaw_remote 两行 sed**（t15-live.sh:488-497 同款）+按决策 2 给模板段；
`assets/sounds/*.wav` 由脚本 python3 生成（fact 12））。流程脚本 `loop/qa/t16-live.sh`
（t15-live.sh 形态：prep/editor/game/export 四相+leg/summary/cleanup trap+`$PHASE` 日志名
warn 扫描+N13 记数+A9 settle 重试助手）。

| # | 腿 | 通道 | 为什么必须真机 |
|---|---|---|---|
| L1 | M1 授权链全 operator 驱动：add.audio_source→ui_click asset_row Pick→选 wav→PlaybackSettings 改 Loop→Save→重开 | R+PX | picker/卡片是编辑器 chrome 视觉面；文档往返是盘上事实 |
| L2 | `afplay` 对照：生成的 wav 直接播（进程 exit 0+听感抽查记录） | shell+人耳 | 「文件可听」与「引擎可响」分层举证 |
| L3 | M2 BGM：direct run（15702）→idle 探针→GS 读 SoundLive（决策 6-A）→mutate master 0→读回 0→复原 | G+GS | 游戏进程行为+live 控制活证 |
| L4 | M3 按钮音：PIE 一腿真 picking 点 Start（N13 绕行记数）+GS 观察一次性 sink 生灭；direct 腿同链复证 | PIE+G+GS | 真点击链+「停止」词的 Once 生灭活证 |
| L5 | M4 场景音：direct→GS kind=spatial+listener 在场→驱动玩家位移→GS 读 emitter Transform 变化 | G+GS | 空间组件的运行时在场+更新链 |
| L6 | M5 导出：game.export→staged 异目录启动→GS 复读 BGM/场景音+包内 sounds/ 文件清点 | G+GS+盘 | 验收句「导出可响」正主 |
| L7 | M6 坏引用红绿：句柄指 missing.wav→GS 无 sink+warn 扫描→修正→sink 在 | G+GS | AU8 红证+红绿闭环 |
| L8 | M7 config 授权三态：编辑器 New Asset/改值/Save→Play 读回→导出读回 | R+G+PX | T08 三态纪律音频版 |
| L9 | M9/M10 bus 路由 live 抽查：mutate music 0→仅 Music sink 哑；mutate sfx 0→仅 Sfx 哑 | G+GS | 三类分轨的 live 数值证明 |
| L10 | M11 Stop 铁证+M14 双声记档：PIE 播 BGM→Stop→场景 SHA 不变；PIE 期间编辑器进程声况记录 | R+盘+人耳 | T06 链音频形态+决策 5 落地证据 |
| L11 | M12 重开一致：Save→重开→四件原样+gizmo 在（AU4 红绿两段） | R+PX | 验收通用交付铁证 |

---

## 四、分任务拆解（T1/T2/T3）

### T1「授权门 + 三类控制机制」（建设主体：AU1-AU5；决策 1/2/3/4/5/8）

1. **首步探针（半小时级，全在 root tests/ 环境——事实十五：jackdaw_runtime dev 环境
   无 bevy_audio，锚不放那里）**：①**纯函数探针**：root 单测直呼
   `build_reflective_default(AudioPlayer::<AudioSource>::type_id(), &registry)`——Some/
   None 定案 picker 面事实（事实四 v2 注）；②**apply 探针**：root 集成测试（或
   bsn_game fixture 临时腿）装载手写最小 bsn
   （`bevy_audio::audio::AudioPlayer("sounds/t.wav")` 全值形态+
   `PlaybackSettings{mode: …::Loop, volume: …::Volume::Linear(0.5)}`）→组件在/字段对。
   **两个已知险点**：AudioPlayer 无 ReflectDefault 的部分补丁 apply 路径（坑甲 v2 更正
   的回退序兜底）、Volume 元组变体往返——全绿则决策 1-A 直落；部分补丁炸则教学钉死
   全值形态+记 AU9。
2. **AU1（决策 1-A）**：①`entity.add.audio_source` 模板升级：spawn 时附
   `AudioPlayer(Handle::<AudioSource>::default())`+`PlaybackSettings::default()`（编辑器
   crate 已有 bevy_audio 类型，entity_ops.rs 直接 insert——**Rust 侧 insert 不经反射
   Default，模板是主入口**）；②EditorCategory「Audio」归类（PlaybackSettings/
   SpatialListener/AudioPlayer 同组，builtin_extensions 注册点）；**不**做
   register_type_data::<AudioPlayer, ReflectDefault>（坑甲 v2 更正：不可行）；picker 对
   AudioPlayer 的缺席记档（模板实体自带组件，非必需）。③`asset_row.rs`
   `file_extensions` 加 AudioSource 臂 `&["ogg","oga","wav"]`（按 feature 现实的扩展名面，
   决策 4 落地后含 wav）——Pick/Browse/拖放/可撤销提交全套免费获得（事实四）。
3. **AU4（决策 8-A）**：编辑器加载后从 `AudioPlayer` 派生 `SceneAudioSource` 标记的
   小系统（derive_world_asset_root 同型），红绿=gizmo 重开前后截图。
4. **AU5（决策 4-A）**：workspace `Cargo.toml:224-233` bevy features+`bevy_source::
   dependency()`/模板行加 `wav`（scaffold 帮手函数保 release 形态合法）+teaches 断言
   （模板 Cargo.toml 含 wav）；编辑器与模板游戏同获 hound。
5. **AU2（决策 2-A/3-A）模板音频段（lib.rs.template，对齐教学密度 ~80-100 行）**：
   - `GameAudioConfig { master: f32, music: f32, sfx: f32 }`（Reflect 资源）+
     `init_asset+register_asset_reflect+ConfigPlugin::<GameAudioConfig>::new("audio-config.bsn")`
     （GameConfig 三行同款，lib.rs.template:262-264 先例）——**编辑器 New Asset 即授权面，
     T17 设置屏的消费对象**；
   - `MusicBus`/`SfxBus` 两个 marker 组件（`#[reflect(Component, Default)]`，编辑器经
     project schema 可加、bsn 可写）；
   - `apply_audio_mix` 系统：config 变更或 sink Added/Changed 时
     `set_volume(base × bus × master)`（`AudioSink`/`SpatialAudioSink` 双查询——事实七
     的两个引擎语义缺口一次补齐）；doc 钉死「GlobalVolume 不追认已播 sink，模板不走它」；
   - **`SoundLive` 镜像组件（决策 6-A 采纳时）**：`#[reflect(Component, Default)]`+
     `mirror_sound_live` 系统每帧从 sink 读 `volume()/is_paused()/empty()/position()`
     写回（~15 行）——「可检视的音频」教学件+GS 数值通道载体（事实十：sink 未反射，
     镜像是 BRP 世界的窗口；T17 设置屏同享）；
   - `on_screen_pressed` 观察者加一行：spawn 按钮音一次性实体
     （`PlaybackSettings::DESPAWN`+SfxBus+按钮音句柄）——「停止」词的 DESPAWN 活证；
   - menu.bsn.template 加 BGM 实体（全路径组件+LOOP+MusicBus——A8 口径）；
     scene.bsn 加空间场景音实体；`spawn_player` 链给相机挂 `SpatialListener::default()`；
   - doc 头部新增「Game audio」导览段（三音三件套+三类控制+spatial=pan 注记）。
6. **headless 测试（全部 root tests/ 档——事实十五）**：①mix 纯函数数学（无条件绿）；
   ②`build_reflective_default` 探针钉形态（探针①转正为常驻断言）；③**bsn_game fixture
   e2e**（`tests/fixtures/bsn_game` 场景加音频实体+fixture lib.rs 加 sink 状态 stderr
   标记行——「sink live, volume=…, empty=false」；`tests/bsn_game_run.rs` 断言标记行；
   现有 integration 档免费携带，零新门）；④（设备许可分支）root 集成测试的 sink 建立与
   volume 断言、DESPAWN 播完组件清除；⑤scaffold teaches：模板含 GameAudioConfig/
   MusicBus/apply_audio_mix/SoundLive/menu.bsn BGM/Cargo.toml wav。
7. **门禁**：fmt/clippy 全仓/单测/集成+teaches 全绿（fast 预期 2981→+n）；bsn_game
   e2e 随 integration 档跑（无档位变更——T15 决策 4 的显式腿需求在此不适用）。

**验收标准**：探针结论在案（决策 1 定案）；编辑器 Add Audio Source→选文件→Save→重开
gizmo 在、四件原样（红→绿活证）；模板新工程 `cargo run` menu 出 BGM、点 Start 有按钮音
（设备许可下）；headless 五件（探针转正+bsn_game e2e+mix 数学）+teaches 绿；quick 四门。

### T2「真机矩阵轮」（验收主任务：M1-M14/L1-L11；决策 6/7）

1. fixture 工程+`assets/sounds/` 生成（bgm/music 盘旋乐型短循环+blip 短音+ambient 各一，
   python3 wave 生成入脚本）+`loop/qa/t16-live.sh`（四相；GS 通道按决策 6 落地形态——
   A=模板 SoundLive 经 world.query 直读（推荐，零额外面）；B=`jackdaw/audio_status`
   则本相在 fixture 侧验证 handler）。
2. L1-L11 全腿；每腿独立 idle 探针开场；A9 自守（settle 重试+小响应体+避开构建窗口）；
   N13 记数；M8 的 H 侧锚复跑指认。
3. 缺陷只记不修：新发现按 AU 系续编（AU9 起），红证归档 `loop/reports/t16*/`。
4. QA 报告：13 格矩阵逐格判定+L 腿全证据+用户 30 秒清单草稿（三音耳听+三类控制听感）。

**验收标准**：M2/M3/M5（三音 Play+导出）GS 数值在案=铁证①；M9/M10 live bus 路由数值
在案=铁证②；M6 红绿、M11 SHA 铁证、M13 零意外 warn；四门禁绿。

### T3「终验 + 文档」

1. 13 格终态复跑+重点腿复跑（L3/L6/L9）。
2. book 新章 `book/src/user-guide/audio.md`（SUMMARY 排 game-ui 后）：Audio Source 作者
   面导览（Add→引用 picker→PlaybackSettings 字段表）、三音范本（menu BGM/按钮音/场景
   音+SpatialListener）、三类控制（audio-config.bsn+bus 标签+mix 语义+「T17 设置屏将
   消费同一资源」指路）、格式与 feature 表（ogg/wav 在册；mp3/flac 指路 T18）、坏引用
   双态（AU8 静默现状+正确姿势）、spatial=pan 非 HRTF 注记、M14 双声语义注记；
   `game-ui.md`/`animation.md`/`game-parameters.md` 交叉引用。
3. buglist 处置（预期无打钩；AU6 若主控裁定升级则按流程）、roadmap T16 勾选、台账记行。
4. 终验门：全量门（fast/integration/doctests/docs/scaffold_e2e——日志全文复核）。

---

## 五、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **引用授权形态（本方案最高权重，AU1）** | A=**bevy 原生组件直接授权**（模板升级为主入口+asset_row 扩展名臂；**不做** ReflectDefault 硬开——坑甲 v2 更正：`register_type_data::<AudioPlayer, ReflectDefault>` 需 `T: Default` 且孤立规则阻断补 impl）：零新类型、游戏侧零运行时工作（bevy_audio 已在装）、Inspector/asset_row/bsn 三面机器全现成（事实四/五）、与「引擎原生组件=第一等公民」的编辑器哲学一致；代价=AudioPlayer 元组字段 `.0` 的展示形态（asset_row 有 label 兜底）+无 Default 的 apply 险点（探针+全值形态兜）。B=自建 `SceneAudio` 桥接组件（runtime/编辑器双侧新类型，内嵌 path/loop/volume/bus，桥系统展开成 AudioPlayer）：字段最贴作者、bus 内嵌一处、自带 Default 免坑甲；代价=新 crate 面+双端注册+桥系统两份+与 T15-AN1 同构的 feature 授权问题——60 行功能背一个模块的结构。C=doc 教手写 bsn：验收句「功能」字面落空——**否决** | **A**；探针①②炸且全值形态/模板主入口兜不住时回落 B（回落判据写进 T1 探针验收） |
| 2 | **三类控制机制落点（AU2）** | A=**模板内建**（GameAudioConfig+MusicBus/SfxBus+apply_audio_mix 全在 lib.rs.template）：T12「per-entity 组件/game-wide config」纪律纯血（GameConfig 先例同构）、零产品改动、T17 直接消费模板资源；代价=bus 类型每游戏自带（跨游戏不标准——但 bus 本就是游戏口味）。B=runtime `audio` feature+catalog 加模块（T15-AN1 形态）：标准化+模块 UI 开关；代价=为 ~60 行建模块+编辑器 Cargo.toml 加 feature+两侧注册面——结构超重。C=扩 fork bevy_audio 加 bus：动 fork——**否决**（fork 纪律） | **A**；「谁消费」=模板 apply_audio_mix 系统；编辑器经 project schema 授权 bus 标签（T12 hud.bsn 同款通路） |
| 3 | **三类控制的运行面本轮范围（验收句「控制」怎么算兑现）** | A=**config 资产授权+BRP/live mutate 演示**（M7/M10）：编辑器 New Asset 即控制面、BRP 数值证明三类独立可调；运行时 UI 留 T17（roadmap T17 明列「音量设置」——范围归位，bind 写资源不通也绕开了，事实九）。B=本轮做暂停屏三滑条（hud.bsn+ValueChanged→observer→写 config）：演示最直观；代价=滑条→资源的 observer 接线+feathers 滑条场景注入+T17 边界模糊。C=键位循环静音（M 键切 master 0/1）：最小但只演示一轨 | **A**；B 作为 T17 设置屏的实现素材记入 book 指路；C 并入 A 的可选教学行（主控可裁加） |
| 4 | **解码 feature 扩容（AU5）** | A=**加 `wav`**（hound，零传递重依赖）：自制 fixture 天然格式+afplay 对照可播（afplay 不播 ogg）+编辑器/模板/测试三面同获；代价=scaffold bevy 依赖行改造（`bevy_source::dependency()` 需 features 形态帮手，release 字符串形态要合法拼接）。B=wav+mp3+flac 全开（symphonia 系）：导入面宽；代价=symphonia 编译重+T18 导入任务的范围被预支。C=不扩、fixture 全用 ogg：零改动；代价=手工造 ogg 不现实（无编码器）、afplay 对照腿废——**否决** | **A**；mp3/flac 归 T18（资产导入域）记档 |
| 5 | **编辑态播放语义（AU7）** | A=**编辑态静音门**：编辑器进程不作为发声体——声属于 Play/游戏进程，验收句「Play+导出可响」字面吻合+PIE 双声免疫+Unity 同语义。**v2 具体化（推荐实现）**：`launch.rs` 的 `DefaultPlugins` 一行 `.set(bevy::audio::AudioPlugin { global_volume: GlobalVolume::from(Volume::Linear(0.0)), ..default() })`——引擎在建 sink 那帧乘一次 GlobalVolume（`audio_output.rs:193,263`），编辑器侧 sink 仍建、音量恒 0：零系统、零 AppState 时序、authored 数据零触碰；回落=编辑世界 sink 统一 pause 的小系统（~20 行，仅在 0 乘法被证明有边角时用）。代价=「开着场景即试听」的即时反馈没了（试听钮挂后续）。B=即开即播（T15 视口活哲学）：作者改 Loop 立刻听到；代价=打开任意带 BGM 场景即出声（侵扰）+PIE 双声需接受或另建门。C=按住试听钮：作者直觉最好；代价=新 UI 面+本轮范围膨胀 | **A**；B 的听感边角与 C 的试听钮记 book/open-challenges 一句话；M14 腿留落地前后对照 |
| 6 | **sink 数值的游戏侧通道（「可响」数值化，v2 重构）** | **A=模板 `SoundLive` 镜像组件**（~15 行模板系统每帧从 sink 读 volume/paused/empty/position 写回 Reflect 组件；GS=M2-M5/M9/M10 经标准 `world.query` 直读）：零产品 crate 改动、教学正向（「可检视的音频」，T17 设置屏同享读面）、PIE/direct/导出全通道有效（只要游戏带模板段，QA fixture 即模板游戏）；代价=仅模板游戏有（对本任务矩阵够用）+镜像滞后一帧（断言口径加 settle 即可）。**B=`jackdaw/audio_status` 自定义 BRP 方法**（jackdaw_remote handler 直查未反射 sink，playback.rs 先例）：对**任意**注入 remote 的游戏可用、读的是 sink 原值；代价=`jackdaw_remote` 不在模板/runtime 依赖（事实十 v2 补充）→真实用户游戏永不链接，实为 QA 工具面放产品 crate、正当性弱一档；+1 handler+测试+响应体控制。C=不加：sink 证据只剩 headless（设备依赖）+人耳——M2/M9/M10 的 live 数值格塌——**否决** | **A 为主**；B 作为 A 不足时的补面记档（后续任务需在非模板游戏读音频态再立）；A 的 SoundLive 字段名/口径入小定案 |
| 7 | **A7/A9 工具债前置评估** | A=**不前置，脚本自守**：T16 编辑器主链全 operator/BRP 直达零对话框腿（A7 家族咬不到）；A9 以小响应体（决策 6-A 设计约束）+settle 重试+idle 探针+避开构建窗口自守（t15 口径）；`$PHASE` 日志名写法直接吸收（A7 教训）。B=先修 A7/A9 再开 T16：多一个前置任务，A7 的对话框半边对 T16 无收益、A9 复现实验与本任务无交集 | **A**；真机若踩（截图 flake 影响视觉格/BRP 空响应超重试预算）按 MCP 优先原则现场立项 |
| 8 | **标记 gizmo 重开丢失处置（AU4）** | A=**派生**：加载后从 AudioPlayer 派生 SceneAudioSource（编辑器-only 小系统，derive_world_asset_root 先例）——游戏侧零噪音。B=持久化（ALWAYS_SAVE_PATHS 加白）：改动一行；代价=`jackdaw::entity_ops::SceneAudioSource` 进文档→游戏侧 UnresolvedTypes 噪音（skip 前缀的反面）——**否决** | **A** |

小定案（主控可否决）：缺陷编号 AU1-AU8（新发现自 AU9 续）；真机腿编号 L1-L11；矩阵格
M1-M14；fixture 工程 `/Users/zhanglinbo/workspace/loop-mac/t16-audio`；音频资产
`assets/sounds/{bgm,blip,ambient}.wav`（脚本生成，python3 wave）；流程脚本
`loop/qa/t16-live.sh`；报告目录 `loop/reports/t16*/`；book 章 `book/src/user-guide/
audio.md`；模板新类型名 `GameAudioConfig`/`MusicBus`/`SfxBus`/`apply_audio_mix`/
`SoundLive { kind: String, volume: f32, paused: bool, finished: bool, position_secs: f32 }`
（决策 6-A；kind 取 "music"/"sfx"/"plain"）；配置文件 `assets/audio-config.bsn`；
headless 锚 `tests/fixtures/bsn_game`（事实十五③）。

---

## 六、风险与回滚

| 风险 | 概率 | 缓解 |
|---|---|---|
| AudioPlayer 无 ReflectDefault 的 bsn apply 路径炸（部分补丁构建需 Default） | 中 | T1 首步探针半日定案；**v2 回退序**：全值形态授课（`AudioPlayer("path")` 整值 patch 走 FromReflect）+模板 Rust 侧 insert（不经反射）为主链兜底；**`register_type_data::<_, ReflectDefault>` 不可行已证**（`T: Reflect+Default` 约束+孤立规则+`ReflectDefault` 无公共构造器，std_traits.rs:12-29）；仍炸回落决策 1-B（桥接组件自带 Default） |
| Volume 元组枚举（`Linear(0.5)`）的 bsn/Inspector 往返边角（T09 enum-tuple 前科） | 中-低 | 探针覆盖；**成晶旁证**：模板 bsn 已日用元组枚举字段（hud.bsn.template `Val::Percent(100.0)`/`Val::Px(12.0)`）+SceneNodeId(999) tuple-variant patch（tests/fixtures/bsn_game/assets/scene.bsn）；炸则 PlaybackSettings 的 volume 授权降级为「模板代码写值」并记 AU9；Inspector 侧枚举编辑机器有 spawn_enum_field 先例（reflect_fields.rs:136） |
| scaffold bevy 依赖行改造波及 release 形态（`"0.20"` 字符串拼接 features 非法） | 中 | `bevy_source::dependency()` 出帮手（git 表形态 vs 版本字符串形态两分支，`version="0.20", features=["wav"]` 合法 TOML）+scaffold 单测两形态断言+fixture 冷编活证；**连带面**：workspace lock 进 hound→scaffold include_str 快照自动随（`lib.rs:1271`）；`tests/fixtures/bsn_game` 自带 Cargo.lock 加 wav feature 后需刷新（事实十五③） |
| 无设备环境下 sink 断言空转（CI/静音机器） | 低-中 | 测试 doc 声明环境依赖；纯函数数学断言无条件兜底（M8 双层）；「No audio device found.」warn 形态入扫描 |
| PIE 双声/静音门时序（决策 5-A） | 低（v2 降） | 一行 `AudioPlugin global_volume=0` 零时序面（建 sink 时乘一次，`audio_output.rs:193,263`）；M14 前后对照腿；回落=sink 统一 pause 小系统 |
| A9 撞面（GS 通道间歇空响应） | 中 | SoundLive 单组件过滤查询=小响应体（决策 6-A）+settle 重试+idle 探针+避开 scene.open/构建窗口；N12 口径全 bevy 原生方法 |
| N13（PIE 腿 100% 复发） | 确定 | 绕行+记数；PIE 仅 M3 一腿，direct run 为主通道 |
| 模板膨胀（现 957 行，音频段+~100 行） | 低 | doc 段精简指路 book；行数增量记 T1 报告（T12 先例口径） |
| bsn_game fixture 加音频实体波及既有断言（共享 fixture 被其他测试依赖） | 低-中 | 音频实体为**追加**（不动 SceneNodeId(999) 既有探针）；stderr 标记行前缀隔离（`audio:` 前缀 grep）；跑 bsn_game_run 全件确认零回归 |
| Mac debug 无 RUST_BACKTRACE | 确定 | 全程不设（T11-T3 口径）；panic 形态证据=消息签名 |
| 门链与编辑器/游戏同窗互踩 | 中 | T12-T3 §九-7 纪律：门链单独跑 |
| 回滚 | — | 五件各自独立可 revert（模板升级+picker 臂+派生系统=编辑器三小件；wav feature=scaffold 一帮手；模板音频段=模板两文件；SoundLive 镜像=模板段一成员；静音门=launch.rs 一行）。全程零协议破坏性变更、零场景格式变更、零 fork 改动、零新插件组、零产品 crate 改动（决策 6-A）——建设面=授权门开+模板段，由定性表保障（六个能力词无一需要新引擎机制） |

---

## 七、与 T01-T15 已建设施的衔接

1. **T06/T07（PIE/导出）=验收通道**：M3 PIE 真点击腿与 M5 staged 导出腿复用 T06/T07
   形态；M11 Stop 铁证=T06 链音频形态（未反射 sink 的文档免疫是天然助攻）。
2. **T08（GameConfig/ConfigPlugin）=三类控制的机器底座**：`ConfigPlugin::<GameAudioConfig>`
   完全复用 T08 的 config 资产三态纪律（编辑器 New Asset/Play/导出一致）；M7=T08 矩阵
   的音频版。
3. **T12（游戏 UI/模板纪律）**：「per-entity 组件/game-wide config」教学纪律是决策 2-A
   的直接依据；hud.bsn 暂停屏=T17 设置屏的落点（本轮只留 book 指路）；`on_screen_pressed`
   =按钮音挂点。
4. **T13（flow）**：BGM 的启停语义走 GameFlow 文档切换（menu.bsn 的实体随 Menu 态生灭，
   `DespawnOnExit` 同型）——「停止」词的模板活证。
5. **T15（动画）**：AN1 模块授权的教训反向适用（决策 2-A 避开建模块）；t15-live.sh 的
   相位/重试/`$PHASE` 扫描/fixture 注入四件直接继承；jackdaw_remote 自定义方法先例
   （playback/scene_snapshot）=决策 6-B 的合法性来源（v2：6-A 模板镜像使其非必需）。
6. **T05/T02（资产索引/Inspector）**：asset_row picker 与 EditorCategory 是 T02 分类
   体系与 T05 资产面的现成件；AU3 的修复=一行映射+回归。
7. **对 T17-T25 的奠基**：T17（存档/玩家设置——音量设置屏消费 GameAudioConfig，滑条
   接线路径已探明）；T18（资产导入热重载——音频解码 feature 扩容与 AU6 坏文件 panic
   都在其域，已备好证据）；T20（示例游戏——三音件+BGM/按钮音模板段直接拼装）；
   T24（错误定位——AU8 静默失败是「错误可见」域的音频样本）。
8. **分支与行号基线**：本方案行号基于 main 78f2fa43；T16 从 main 拉 `loop/t16-audio`；
   loop/ 目录不入库照旧。

---

## 八、耗时预估

| 段 | 预估 | 大头 |
|---|---|---|
| T1 | 1.5-2 天 | 探针定案+授权门三小件（模板升级/picker 臂/派生）+wav feature 链（scaffold 帮手+bsn_game fixture 锁刷新）+模板音频段（config/mix/SoundLive/三音种子/listener）+headless 五件 |
| T2 | 1-1.5 天 | fixture+音频生成+脚本+L1-L11 两段+红证归档（决策 6-B 若裁 +0.5 天） |
| T3 | 0.5-1 天 | 13 格终态+book 新章+全量门+收尾 |
| 合计 | **3-4.5 天** | 视决策 1 探针与决策 5/6 落地顺畅度浮动 |
