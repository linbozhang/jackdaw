# T16 任务 2「真机矩阵轮」程序报告

> 分支 `loop/t16-audio` @ 5b062fc7（含 T1 merge，零产品代码改动——本轮全部产出为 QA 工具
> 脚本 `loop/qa/t16-live.sh` + 本报告与归档）；任务书 `loop/plans/t16-audio.md` §四-T2 +
> §六格表；fixture `/Users/zhanglinbo/workspace/loop-mac/t16-audio/t16-audio`（T1 遗留，
> 注入 jackdaw_remote 两行 sed + 规范场景重写 + 热编 3m58s 过）。
> 真机：macOS arm64（M1 Pro），编辑器 BRP 15703 / 游戏 BRP 15702，全程未设 RUST_BACKTRACE。
> **判语：13 格矩阵 M1-M14 全 PASS；真机腿 L1-L11 全 PASS；三铁证全部立住。**

## 〇、最终判定汇总（日志全文复核，exit 仅辅助）

```
editor 相: L1_M1_CHAIN=PASS M12_REOPEN_CONSISTENT=PASS M14_EDITOR_MUTED=PASS
           M7_AUTH_FACE=PASS WARN_SCAN_EDITOR=PASS
game 相:   L10_M11_STOP_INVARIANT=PASS L2_AFPLAY_CONTROL=PASS L3_M2_BGM=PASS
           L4_M3_PIE_CLICK=PASS L5_M4_SPATIAL=PASS L6_M5_EXPORT=PASS
           L7_M6_BADREF=PASS L9_M10_ROUTING=PASS M3_DIRECT_CHAIN=PASS
           M7_PLAY_FACE=PASS WARN_SCAN_GAME=PASS
```

归档：`loop/reports/t16t2_live-*`（console 两相、summary、warn 四件、n13 计数、13 件
witness、4 张截图）+ `t16t2_editor-phase1_red.log`（首轮工具红态）+ `t16t2_fast.log`/
`t16t2_quick-gates.log`（门禁）。

## 一、13 格矩阵逐格判定

| 格 | 腿 | 判定 | 关键证据（数值在案） |
|---|---|---|---|
| M1 授权链 | L1 | **PASS** | 全作者链：`entity.add.audio_source` → Audio 类目 tab → AudioPlayer 卡展开 → **Pick 列出 Browse+三 wav 并选中 sounds/blip.wav**（截图 `t16t2_live-shot-l1-audio-picker.png`）→ component.set 改 Loop+0.55 → save → **重开四件原样**（handle 在场 query 判定+PlaybackSettings `mode:Loop,0.55`+派生 marker+文档 `AudioPlayer<bevy_audio::audio_source::AudioSource>("sounds/blip.wav")` 全泛型路径） |
| M2 BGM | L3 | **PASS** | direct run 菜单：SoundLive `{kind:music, volume:0.6, paused:false}`，position 9.31→11.40 前进（loop 活证）；**master mutate 0 → 已播 sink 即刻 0.0 → 复原 0.6**（引擎不追认缺口由模板 mix 系统补齐的活证） |
| M3 按钮音 | M3-direct + L4 | **PASS（双链）** | direct：`world.trigger_event ScreenPressed{button:start}` → sfx sink 0→1、blip volume=0.400（0.4×sfx1×master1）→ flow 切 Level、MenuBgm 随文档消失（**停止词活证**）→ Ambient 进场；PIE：真指针点击底部面板 Start（实测 (800,911)，扫格命中）→ **blip 0.4 再次现场生灭** → Level 三音进场（`m3-pie-witness.txt` caught=2） |
| M4 场景音 | L5 | **PASS** | Ambient `{kind:plain, volume:0.8}`（无 bus=master 独轨）；SpatialListener 实体在场（717v0，挂在玩家相机 rig）；emitter GlobalTransform `[6,2,-4]`=authored；**KeyW 驱动玩家 z 0→-2.44，listener GlobalTransform 9.21→6.77 同步跟随**（bevy 每帧 listener 更新链活证） |
| M5 导出 | L6 | **PASS** | `game.export` → staged 树 `assets/sounds/` 三件+manifest 行；staged 二进制（异目录启动）**三 SoundLive 同数值**：Ambient plain:0.8 + MusicProbe music:0.5 + SfxProbe sfx:0.4 + spatial:true + config 1/1/1 ——「导出可响」正主 |
| M6 坏引用 | L7 | **PASS（红→绿）** | 红：句柄改 sounds/missing.wav → MenuBgm PlaybackSettings 原样在、**SoundLive settle 后 ABSENT**（AU8 静默失败现形；bevy_asset `Path not found` ERROR 归档 `t16t2_live-direct-badref_red.log`）；绿：修正 → 0.6 回归 |
| M7 config 授权 | M7 两面 | **PASS** | 授权面：`asset.new t16_audio::GameAudioConfig`（卡开、文件落 `assets/audio-config.bsn`）→ 卡编辑 music 0.5 → save 落盘 → 回滚；play 面：编辑器改 music=0.5 → **运行中游戏资源读回 `{"master":1.0,"music":0.5,"sfx":1.0}` 且 MenuBgm=0.3（0.6×0.5）**——T08 三态纪律音频版 |
| M8 mix 数学 | H 侧 | **PASS** | `cargo test --test audio_gate` 终树复跑 **7/7**（0.4×0.8×0.5=0.16 断言、bus 路由、master 0 追认、DESPAWN 播完自灭、探针①-④ 常驻）；真管线 e2e 数值 0.160 为 T1 在档证据 |
| M9 bus 路由 | L9 | **PASS** | 三音同场 live：music→0 只哑 MusicProbe（SfxProbe 0.4/Ambient 0.8 不动）；sfx→0 只哑 SfxProbe；master→0 全哑；复原逐一回位（`l9-*-zero.txt` 三份快照） |
| M10 live 控制 | L3+L9 | **PASS** | `world.mutate_resources` 全周期：mutate→读回一致→SoundLive 逐 sink 随动→复原（复用 M2/M9 证据） |
| M11 Stop 铁证 | L10 | **PASS** | PIE 往返后 menu.bsn **SHA 不变**；全部 .bsn 文档零 AudioSink 痕迹（未反射组件的文档免疫核验） |
| M12 重开一致 | — | **PASS** | save→重开：AudioPlayer query 在场+PlaybackSettings `Loop,0.6` 前后全等；文档 `sounds/bgm.wav` 泛型路径+`t16_audio::MusicBus` 行原样 |
| M13 warn 形态 | 常备腿 | **PASS** | 编辑器相：泛型注册回归（`cannot apply…AudioPlayer`）**0** 命中；game 相：音频域 warn **0** 命中（`No audio device`/`decoder`/`Multiple SpatialListeners`/`UnresolvedTypes` 全零）；14 条非音频模板态逐条归因不计数（`t16t2_live-warn-attributed.log`：game-config.bsn 缺省×7+bind 首帧无上下文×7）；L7 红腿的 missing.wav ERROR=该腿设计证据，按 `*_red` 同规则跳过 |
| M14 双声边角 | — | **PASS** | 编辑器进程 `GlobalVolume = {"volume":{"Linear":0.0}}`（AU7 静音门在位），authored MenuBgm PlaybackSettings **0.6 原样未触碰**——编辑器不作为发声体；声属于游戏进程（L3/L4 实听面） |

## 二、L1-L11 逐腿

全 PASS。L2（afplay 对照）blip/bgm/ambient 三 wav exit 0（文件可听层）；L1/L3/L4/L5/L6/L7/L9
见上表；L8=M7（授权+play 两面）；L10=M11+M14 记档；L11=M12。

## 三、三铁证结论

1. **三音 Play+导出可响（铁证①）**：BGM 0.6（L3）、按钮 blip 0.4（M3-direct+L4 真点击双链）、
   场景音 0.8 spatial（L5）——direct run 数值全在案，导出包 staged 二进制同值复现（L6）。
   GS 通道=模板 SoundLive 镜像（一帧滞后，settle 口径），afplay 提供文件可听对照层。
2. **主/音乐/音效三类控制（铁证②）**：L9 三 bus 互不串扰的 live 数值+L3 master 对已播 sink
   的追认归零+M7-play 编辑器改值直达运行游戏——三类独立可调机械化成立。
3. **静音门语义（AU7）**：M14 双证——编辑器 GlobalVolume 0.0、authored 数据零触碰；游戏进程
   出声（L3/L4）。**QA 在编辑器听到任何声音=AU7 回归立账。**

## 四、偏差清单（如实，含工具链教训）

1. **⚠️ 脚本 `brp()` 首版丢 `local method="$1" params="${2:-}"`**：`set -u` 下全部读空、
   `wait_idle` 全超时，首轮相位 50 分钟爬行且四腿全假红（归档 `t16t2_editor-phase1_red.log`）。
   修后相位 ~6 分钟。**工具脚本复用 t15 函数时逐行 diff 的教训。**
2. **⚠️ `asset.new` 两个拼写面**：kind 需全类型路径（裸名 "GameAudioConfig" warn
   "nothing registers"）；path 相对 assets 根（写 "assets/…" 落出 `assets/assets/` 杂树，
   已清理）。
3. **⚠️ 本 fork 的 `world.get_resources` 形**：参数单数 `{"resource":"<path>"}`、响应
   `.result.value`——脚本初版的 `resources` 数组形拿到的是 `missing field resource` 错误。
4. **⚠️ `GlobalTransform` 的 BRP 序列化=12 元 Affine3A 数组**（无 `.translation` 键），
   平移=末 3 元；Transform 才是对象形。L5 首轮假红即此。
5. **⚠️ AudioPlayer 活值跨 reopen 序列化为空**（未装载依赖的 ReflectHandle），BRP 读不可作
   断言面——在场判定改 component-filtered `world.query`，路径断言落保存文档（更强）。
6. **⚠️ PIE 真点击通道三个必须**：`pie.play_input_toggle`（capture 先行，T12 先例）、点击
   目标=底部游戏面板带（非 viewport 中心；本布局 Start 实测 (800,911)）、面板按钮无文本
   （图标 E247）且 picker 项是 TextSpan（Text query 不可见）——L1 的 Pick 以「None 行+最近
   邻 E247」几何配对定位（**编辑器 UI 坐标空间逐 run 漂移**：显示缩放/窗口落位所致，绝对
   坐标窗口会差 2px 而失配，相对锚定+最近邻才稳）。这三件已固化进脚本。
7. **⚪ N13 计数=3**（PIE connect 后 drain panic，`vec/mod.rs:2258`，100% 复发口径）；
   本轮 PIE 腿照常完成，绕行有效。
8. **⚪ 编辑器二进制 dylib 不同步**（merge 后 target 陈旧，dyld Symbol not found）——
   `cargo build` 重链 3m12s 修复；真机门前「先起一次编辑器」应成为脚本前置。
9. **⚪ M13 词表两轮收紧**：game-channel 扫描以**音频域形态**判（`No audio device|Spatial|
   decoder|AudioSource|AudioPlayer|cannot apply|missing.wav`），模板 benign 态归因另档；
   调试期一次 menu.bsn 污染（operator save 落活动 tab）已清理并验证——**QA 注意：对编辑器
   世界的 save 永远先确认活动 tab**。
10. **⚪ 截图生命周期**：write_scene_bsn 的 canonical 清理会删项目 screenshots/——shot()
    现同步落证据目录（`t16t2_live-shot-*.png` 四张已归档）。

## 五、门禁（最终树，日志归档）

| 门 | 结果 | 归档 |
|---|---|---|
| `cargo xtask fast` | **2987/2987**（全文复核 0 error/0 FAILED/0 Diff） | t16t2_fast.log |
| fmt/clippy-physics/audio_gate（quick 合卷） | fmt exit 0；physics clippy CLEAN；audio_gate 7/7 | t16t2_quick-gates.log |
| `cargo test --test audio_gate`（M8 终锚复跑） | **7/7**（2.63s） | （本报告引述，可重跑） |

本轮零产品代码改动，以上即全部门；物理双包 clippy 在 quick 合卷内 CLEAN。

## 六、给 QA 的注意事项

1. **放行建议**：M1-M14/L1-L11 全绿+三铁证在案，T16-T3（终验+book 章）可开。
2. **复核顺序建议**：先 `t16t2_live-summary.txt`（两相判语）→ `t16t2_live-console-*.log`
   （逐腿数值行）→ witness 13 件 → 截图 4 张（M1 picker/Audio tab 面、M14 静音面）。
3. **L4 PIE 几何**：真点击依赖面板带坐标（1600x1000 窗口实测 (800,911)）；换显示器/缩放会
   漂——扫格+blip/流切换双判据已是口径，复跑时勿固定单点。
4. **词表口径**：`cannot apply '…AudioPlayer…'`=泛型注册回归；`No audio device found`=无设备；
   `volume=base 而非 mix 值`先查系统链再查 config（T1 偏差 9）；其余音频域 warn 逐条归因。
5. **耳听终审 30 秒清单（草稿）**：① `cargo run` 新工程 → Menu 听到 BGM 循环；② 点 Start →
   短 blip、进 Level 听到空间嗡鸣且走动时声像移动；③ 编辑 `assets/audio-config.bsn`
   music=0.5 重跑 → BGM 变小（0.3），master=0 → 全静音；④ 导出包同样出声；⑤ 打开编辑器
   浏览带 BGM 的场景 → **听不到任何声音**（AU7）。
6. fixture 终态 canonical（menu.bsn 原样、flow=menu.bsn、无 missing.wav 残留、无
   assets/assets 杂树）；`loop/qa/t16-live.sh` 三相可重入（prep 幂等）。
7. 未动面：buglist/台账/roadmap 未改（T3 口径）；本轮新发现的非音频缺陷候选 **「PIE 面板
   指针转发在本布局下初测未达游戏 UI（坐标空间混用嫌疑）」** 已在 L4 解决过程中被绕开
   （面板带扫格直达），是否立账归主控裁定——证据链：`l4-debug-*.png` 分析过程不在档，
   结论性证据为本报告 §四-6 与 `t16t2_live-shot-l1-audio-picker.png` 所示的面板/图标
   坐标空间差异。
