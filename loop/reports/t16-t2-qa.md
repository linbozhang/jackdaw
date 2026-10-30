# T16 任务 2「真机矩阵轮」QA 验收报告

> 分支 `loop/t16-audio`，核实对象=程序提交 28a6d930（零产品代码改动：`git diff
> 5b062fc7..28a6d930` 在 src/crates/templates/book/tests/根 Cargo.toml 上 **0 行差异**，
> 30 件=脚本+报告+归档，逐一清点相符）；核实依据 `loop/reports/t16-t2-report.md` +
> 任务书 §四-T2/§二格表 + T1 qa 回流三项（红态归档纪律/词表两项/fixture 交接）。
> QA 全程只读+亲跑：门禁四门亲跑、四格证据全读（L3/L4/L6/L9）、三腿亲跑复现
> （L9/M6/M3-direct）、fixture 终态与 staged 导出树盘上实证。未设 RUST_BACKTRACE；
> 未改产品代码/buglist/台账/方案。QA 归档 `loop/reports/t16t2_qa_*`（6 件）。

## 裁决：**PASS**（放行 T16-T3 终验+book 章）

依据浓缩：门禁四门亲跑全绿（fast 2987=程序归档双通道一致、teaches 90、audio_gate 7/7）；
M1-M14 十四格+L1-L11 十一腿归档证据逐格核符，零假绿；三铁证独立性判定成立；红态归档
纪律（T1 回流）首次执行且两处落地；L9/M6/M3-direct 三腿 QA 亲跑逐字节复现程序数值；
两处报告证据精度附注（非阻塞，§五）；PIE 指针转发缺陷候选裁定=独立小票不并 A7（§六）。

## 〇、门禁表（QA 亲跑 2026-10-30 16:41-16:48，门前磁盘 36Gi，日志归档 t16t2_qa_*）

| 门 | 命令 | 结果（全文复核，exit 仅辅助） | QA 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **CLEAN**（exit 0，零 diff 输出） | t16t2_qa_fmt.log（空=净） |
| 音频门（任务相关） | `cargo test --test audio_gate` | **7/7**（2.77s；含 M8 终锚：0.4×0.8×0.5=0.16/bus 路由/master 0 追认/DESPAWN/探针①-④ 常驻） | t16t2_qa_audio_gate.log |
| 单测 | `cargo test --workspace --lib` | **2987/2987**（jackdaw=1192、scaffold=**90**=teaches 预期、project_build=227、terrain=531——与 T1 分布逐 crate 一致=零产品改动的旁证）；error 形态命中仅 1 处=PIE E0560 负例喂错（T1 同款归因），零真失败 | t16t2_qa_libtests.log |
| fast | `cargo xtask fast` | **2987/2987**（末行 Summary 2987 passed 0 skipped；error/FAILED/Diff/panicked 扫描 **0** 命中、warning **0** 行） | t16t2_qa_fast.log |

交叉核：程序 `t16t2_fast.log` 2987（nextest ci profile）↔ QA cargo test 求和 2987 双通道
一致；程序 quick 合卷（fmt exit 0/物理双包 clippy CLEAN/audio_gate 7/7）与 QA 重跑一致。
**本轮零产品代码改动（QA 独立 diff 实证）→ 全仓 clippy/integration 采信 T1 归档**（T1 qa
七门全绿在案），符合任务口径。磁盘门前 36Gi（上轮 28Gi 偏紧已缓解）；结束核查无残留
jackdaw/t16-audio 进程，fixture 终态 canonical（flow=menu.bsn、无 missing.wav 残留、
无 assets/assets 杂树、audio-config.bsn 缺省态）。

## 一、M1-M14 逐格核实（归档证据全读；带 ⟳ 者为 QA 亲跑复现）

| 格 | 腿 | 程序判定 | QA 复核 | 关键证据（QA 亲见） |
|---|---|---|---|---|
| M1 授权链 | L1 | PASS | **核符** | console 全链读回（Loop+0.55+marker 四件）+文档 grep `AudioPlayer<...>("sounds/blip.wav")` 全泛型路径+picker 截图亲览：**Pick AudioSource 模态列出 Browse+ambient/bgm/blip 三行**、Audio 类目栏、AudioPlayer/Playback 卡在位 |
| M2 BGM | L3 | PASS | **核符** ⟳ | witness JSON `{kind:music, volume:0.6, paused:false}`；position 前进活证（归档 3.12→5.17→5.26，见 §五-a）；master mutate 0→已播 sink 即刻 0.0→复原 0.6 |
| M3 按钮音 | M3-direct+L4 | PASS（双链） | **核符** ⟳（direct 侧） | direct：trigger→blip 0.4 生（caught=1）→flow 切 Level、MenuBgm 消失、Ambient 进场（停止词活证）；PIE：真指针 (800,911) 命中、caught=2、blip 0.4（`m3-pie-witness.txt`）；QA 亲跑 direct 链全复现 |
| M4 场景音 | L5 | PASS | **核符** | Ambient plain:0.8+SpatialListener 717v0 在场+emitter [6,2,-4]=authored；KeyW 驱动玩家 z 0→-2.44、listener 9.21→6.77 跟随（更新链活证） |
| M5 导出 | L6 | PASS | **核符（盘上复核）** | staged 树三 wav+manifest 三行+staged exe 在盘（QA 今日实证）；staged 三 SoundLive 同值：plain:0.8+music:0.5+sfx:0.4+spatial:true+config 1/1/1——五点链齐 |
| M6 坏引用 | L7 | PASS（红→绿） | **核符** ⟳ | 红：settings 0.6 原样在+SoundLive settle 后 ABSENT+`Path not found` ERROR 在 `direct-badref_red.log`+`l7-red-world_red.json` 空 result；绿：0.6 回归；**QA 亲跑红绿两段全复现**（红证另档 `t16t2_qa_direct-badref_red.log`） |
| M7 config 授权 | L8 两面 | PASS | **核符** | 授权面：asset.new→卡编辑 0.5→save→回滚（截图亲览：master 1.00/music 0.50/sfx 1.00+Save 钮）；play 面：资源读回 `{"master":1.0,"music":0.5,"sfx":1.0}`+MenuBgm=0.3（0.6×0.5）——T08 三态纪律音频版 |
| M8 mix 数学 | H 侧 | PASS | **核符** | audio_gate 7/7 QA 终树复跑（见门禁表）；0.160 真管线 e2e 数值=T1 在档 |
| M9 bus 路由 | L9 | PASS | **核符** ⟳ | 三快照（music-zero/sfx-zero/master-zero）互不串扰逐值在案；**QA 亲跑四步 mutate 全循环，数值与程序轮逐字节一致**（见 §三） |
| M10 live 控制 | L3+L9 | PASS | **核符** | mutate→读回一致→逐 sink 随动→复原，全走 `world.mutate_resources`（M2/M9 证据复用成立） |
| M11 Stop 铁证 | L10 | PASS | **核符** | PIE 往返后 menu.bsn SHA 不变+全部 .bsn 零 AudioSink 痕迹（console `sha stable=y`） |
| M12 重开一致 | L11 | PASS | **核符** | before/after 全等（player=present+Loop 0.6）；menu.bsn 全泛型路径+MusicBus 行 QA 盘上亲见 |
| M13 warn 形态 | 常备腿 | PASS | **核符**（两处附注） | 泛型注册回归（`cannot apply…AudioPlayer`）编辑器 0/游戏通道 0；`No audio device/decoder/Spatial/UnresolvedTypes` 全零（两件 0 字节日志）；14 条归因件在档（拆分勘误见 §五-b）；N13=3（vec/mod.rs:2258）在档计数、PIE 腿照常完成=绕行有效 |
| M14 双声边角 | — | PASS | **核符** | 编辑器 `GlobalVolume={"volume":{"Linear":0.0}}`+authored MenuBgm PlaybackSettings 0.6 原样（console 全文）——静音门在位、数据零触碰；声属于游戏进程（M2/M3 数值+position 前进=真在响） |

**L1-L11 逐腿**：全 PASS 与归档相符——L2（afplay 三件 exit 0，console 在案）、
L1/L3/L4/L5/L6/L7/L9（上表）、L8=M7 两面、L10=M11+M14 记档、L11=M12。
**格子计数勘误**：方案 §二/程序报告均写「13 格」，矩阵实为 **M1-M14 十四行**（措辞沿袭，
非漏格——QA 上表按 14 格逐格判定）。

## 二、脚本与归档纪律复核（A7 教训+红态归档首例）

1. **日志随 $PHASE（A7 教训落实）**：`console-$PHASE.log`/`editor-$PHASE.log`/
   `walk-$PHASE.json` 全部随相位，全脚本零陈旧文件名 grep——T14 红牌条款逐字执行。
2. **三相幂等可重入声明成立**（静态逐段核+fixture 终态旁证）：每相位以
   `write_scene_bsn` canonical 复位开场（含 L1 遗留实体清理、flow start、tab journal、
   screenshots 清理）；remote 注入 grep 守门不重复；RESULTS_FILE mktemp 每轮独立；
   summary 相位开场 rm -f。L7 红态先 `cp *_red.log` 再绿轮覆盖=纪律内建。运行后
   fixture 的 project.json 有运行尾迹（layout/tabs 写回——编辑器被 pkill 前的落盘），
   无害且每相位开场即被复位（可重入设计的自证）。
3. **红态归档纪律首例执行核实（T1 回流第 1 项）**：`t16t2_editor-phase1_red.log` 在档，
   四腿 FAIL+读数全空=brp() 首版丢参数声明的事故形态原样；L7 红态双件
   （`direct-badref_red.log`+`l7-red-world_red.json`）=第二处落地。**纪律已从「回流建议」
   变成「两例在档的实践」**。
4. **词表两项交接（T1 回流第 2 项）落实**：`cannot apply.*AudioPlayer`=泛型注册回归信号
   （两相位各设 `reg` 计数门）+`No audio device`=无设备（game-channel 词表成员）——均在
   `t16-live.sh` 词表内。
5. **fixture 交接（T1 回流第 3 项）兑现**：注入两行 sed 在档（Cargo.toml:25+main.rs:38）、
   lock 含 jackdaw_remote、wav feature 行、三 wav、模板音频段、热 target——五件盘上亲验。

## 三、三铁证独立性判定

| 铁证 | 三条腿的证据源 | 独立性判定 |
|---|---|---|
| ① 三音 Play+导出可响 | BGM 0.6（menu 场景/music bus/position 前进）；blip 0.4（按钮链一次性生灭，direct+PIE 双通道）；Ambient 0.8 spatial（level 场景/plain） | **独立成立**：三音各自独立实体×独立场景×独立证据链（数值+镜像 kind+position 推进），导出腿 staged 同值+包内资产盘证。任一音的证据不依赖其余两音 |
| ② 主/音乐/音效三类控制 | BRP mutate 逐 bus 隔离（L9 四步循环）；master 对已播 sink 追认归零（L3）；编辑器改值直达运行游戏（M7-play 0.3） | **独立成立**：L9 证明三旋钮互不串扰（动 music 时 sfx/plain 数值纹丝不动）；M7-play 证明授权面（编辑器 authored）与运行面同值；三个控制面（config 资源/music/sfx）机制分离 |
| ③ 静音门语义（AU7） | 编辑器 GlobalVolume 0.0（BRP 直读）+authored PlaybackSettings 0.6 未触碰+游戏进程出声（M2/M3 数值与 position） | **双证成立**：「编辑器不作为发声体」与「authored 数据零触碰」同时成立；游戏侧出声独立可证。**QA 附注：编辑器内听到任何声音=AU7 回归立账**（口径沿用 T1 qa） |

## 四、QA 亲跑复现（2026-10-30 16:49-16:51，日志 `t16t2_qa_live-legs.log`）

- **L9 全循环复现**：baseline 三值 → music 0 仅哑 MusicProbe → sfx 0 仅哑 SfxProbe →
  master 0 全哑 → 复原三值——**四步数值与程序轮逐字节一致**。
- **M6 红绿复现**：红段 MenuBgm settings 0.6 在+SoundLive ABSENT（红证归档
  `t16t2_qa_direct-badref_red.log`，含 `Path not found` ERROR）→绿段 0.6 回归。
- **M3-direct 复现**：sfx 0→blip 0.4 生（caught=1）→flow 切 Level（MenuBgm 消、Ambient 进）
  ——停止词活证复现。
- 结束清场：游戏进程杀净、flow start 复原 menu.bsn、无 missing.wav 残留。

## 五、报告证据精度附注（全部非阻塞，建议 T3 引数以归档为准）

- **a·L3 position 数值**：程序报告 §一-M2 写「9.31→11.40」，归档 console/witness 实为
  **3.12→5.17（→5.26）**——报告引了早一轮同腿数值；两轮均证 position 前进，判定不变。
  T3 终验引用归档数值即可。
- **b·M13 归因拆分**：报告写「game-config 缺省×7+bind 首帧×7」，归档 14 条实拆
  **config 缺省×5+bind 首帧×9**——总数 14 正确，拆分笔误。
- **c·截图证据面**：`l1-reopened-inspector`/`m14`/`m7` 三张截图均带 L1 遗留的 Pick
  AudioSource 模态浮层（picker 点选后模态未关，跨越 save/reopen 与场景切换）——截图的
  证据价值限于「模态面/卡片面」本身；四件套/静音门等状态断言全部落在 BRP 读回+文档
  grep（console 在案），判定不受影响。**T3 复跑建议：截图前先关浮层（Esc/点击 ×）。**
- **d·报告头基线**：报告头写 `@5b062fc7`（运行时代码态），产物在 28a6d930 提交——T2
  工作形态使然，无矛盾。
- **e·loop/ 契约文本漂移（非 T2 偏差）**：`loop/README.md` 写「本目录不入库」，但 loop/
  自 T15 收官前即入 git 追踪（今 2597 件，`.git/info/exclude` 无 loop 条目）——实践已变、
  文本未更，提请主控在方便时更正 README 一句话，不属本轮偏差。

## 六、程序偏差 10 条裁定（§四逐条对归档）

| # | 程序偏差 | QA 裁定 |
|---|---|---|
| 1 | ⚠️ brp() 首版丢参数声明，首轮相位全假红 | **吸收+纪律核实通过**：红态在档（§二-3），修后相位 ~6 分钟（console 时间戳 16:24-16:34 两相佐证）；「复用 t15 函数逐行 diff」教训成立 |
| 2 | ⚠️ asset.new 拼写两面（全类型路径/相对 assets 根） | **吸收**：脚本注释+守卫在位（M7 注释原文）；杂树已清理（QA 盘验无 assets/assets） |
| 3 | ⚠️ get_resources 单数 `resource` 形 | **吸收**：`gconfig_get` 注释钉死 fork 形；M7-play/L9 读回全对 |
| 4 | ⚠️ GlobalTransform=12 元 Affine3A | **吸收**：`gt_translation` 双形 jq 兜底；L5 数值正确 |
| 5 | ⚠️ AudioPlayer 活值跨 reopen 序列化为空 | **吸收**：在场判定改 component-filtered query+路径断言落文档（更强）；编辑器相唯一 warn 行（serialize 失败）即此现象，归因在报告 §四-5，M13 门不误报 |
| 6 | ⚠️ PIE 真点击三必须+L1 相对几何配对 | **吸收，见 §七几何复核**：capture 先行/面板带/双判据已固化脚本 |
| 7 | ⚪ N13=3 | **吸收**：n13-count.txt 三行同签名 vec/mod.rs:2258；PIE 腿完成=绕行有效 |
| 8 | ⚪ dylib 不同步重链 3m12s | **吸收**：「先起一次编辑器」进脚本前置（editor_boot+editor_build_settled 已实现） |
| 9 | ⚪ 词表两轮收紧+menu.bsn 污染清理 | **吸收**：音频域形态词表在脚本；「save 先确认活动 tab」QA 照单全收（本轮 M12 save 时 menu 为活动 tab，操作合规） |
| 10 | ⚪ 截图生命周期（canonical 清理删 screenshots/） | **吸收**：shot() 同步落证据目录，四张归档在案 |

## 七、L1 Pick 几何配对复核（偏差 6 后半）

**机制**：以 None 行自身 rect 为锚（同一 walk 快照内取值）→ 右侧 ±45px 带内过滤 E247
glyph 文本节点 → 按 |dy| 最近邻取 entity → `ui_click by entity`；卡片展开竞态 5× 重试。
**稳定性判定：稳**——锚与目标同快照，窗口落位/显示缩放的全局漂移在差分中抵消；E247
glyph 过滤排除同行其它图标（Clear/× 等非同 glyph）；比绝对坐标窗口稳健（报告偏差 6 的
2px 失配教训即其反例）。
**归账建议：并入 A7（字段行定位族第 6 腿）**——「无文本图标行的结构化寻址」与 A7 票面
「对话框提交+字段行定位」同族；现行绕行（ui_tree 相对几何配对+glyph 过滤）已固化
`t16-live.sh`，修复方向按 MCP 优先原则=结构化图标寻址（ui_tree 按 kind/glyph 寻址或
ui_click 扩展目标形态），与 T12-T3 挂账的 input.pointer frame-relative 模式同批考虑。

## 八、非音频缺陷候选裁定建议：「PIE 面板指针转发未达游戏 UI（坐标空间混用嫌疑）」

**建议：立独立小票，不并入 A7**（复现先行，A9 同款纪律）。理由与票面：

1. **性质归属**：A7=QA 脚本工具债（编辑器 chrome 缺口的脚本侧绕行）；本候选质疑的是
   **产品侧通道契约**——`ui_tree` rect 序列化坐标空间与 `input.pointer` 的对应关系
   （脚本 frame_rect 注释自证观察到 origin 出窗的节点=「另一量制」痕迹），属通道契约票
   而非脚本债。硬并 A7 会稀释两边的修复方向。
2. **证据现状=弱**：`l4-debug-*.png` 不在档（报告自认）；幸存证据=console 行
   「frame rect (0,0 1280x720), clicking (640,360)」+实命中 (800,911)+脚本注释。**且 T12
   在档事实（t12-t2-report:140/177）已明示流送帧=底部条带形（非 16:9 档）**——T16 的
   frame_rect 以 1.6-1.95 宽高比过滤选中的 1280x720 节点极可能是**编辑器 viewport 而非
   游戏流**，「未达游戏 UI」的第一成因可能是**几何误识**而非转发缺陷；是否另存坐标空间
   混用需定向实验分辨。故先复现后立账。
3. **建议票面**：「PIE 流送帧几何辨识+ui_tree rect 坐标空间一致性+input.pointer
   frame-relative 寻址」。复现实验=变显示缩放×窗口尺寸两档，PIE 运行中分别点
   ①流送帧（底部条带）矩心 ②frame_rect 选中节点的矩心，以游戏侧可观测反应（blip/状态
   翻转）判达达性；顺带把 T12-T3:108 挂账的 frame-relative 模式并入本票收口。
4. **对 T16 无阻塞**：绕行口径（面板带扫格+blip/flow 双判据）已固化脚本且本轮 PASS；
   T12 通道本身（capture 先行→条带点击→转发→picking）在 L4 是**走通**的——候选不推翻
   T12 验收，只框定其几何适用面。

## 九、T16-T3 放行建议+用户 30 秒耳听清单

**放行 T16-T3**。交接面：

1. **T3 引数纪律**：终验矩阵引用归档数值（§五-a 类）；截图先关浮层（§五-c）。
2. **终验重点腿**：L3/L6/L9（方案 §四-T3-1）——L9/L3 的数值本轮 QA 已双轮一致，T3 第三
   轮照 `t16-live.sh game` 相位单相重入即可。
3. **book 章素材已备**：capture 先行+面板带点击口径（§四-6）、AU8 坏引用双态（L7 红绿
   在档）、静音门语义（M14）、spatial=pan 注记——归档证据链齐全。
4. **词表沿用**：`cannot apply…AudioPlayer`=泛型注册回归；`No audio device`=无设备；
   `volume=base 而非 mix 值`先查系统链再查 config。
5. **用户 30 秒耳听清单**（程序 §六-5 草稿逐条对照证据核验通过，采信+一句设备预检）：
   - ① `cargo run` 新工程 → Menu **听到 BGM 循环**（对照 L3 position 前进）；
   - ② 点 Start → 短 blip（对照 M3 0.4 生灭）；进 Level 听到空间嗡鸣且走动时声像移动
     （对照 L5 listener 跟随）；
   - ③ 编辑 `assets/audio-config.bsn` music=0.5 重跑 → BGM 变小（0.3，对照 M7-play）；
     master=0 → 全静音（对照 L9）；
   - ④ 导出包同样出声（对照 L6 staged 三值）；
   - ⑤ 打开编辑器浏览带 BGM 的场景 → **听不到任何声音**（对照 M14；听到=AU7 回归立账）；
   - （QA 增补）开始前 `afplay assets/sounds/blip.wav` 3 秒预检本机输出设备在位。

## 十、QA 归档清单（`loop/reports/t16t2_qa_*`，6 件）

`fmt（空=净）/ audio_gate / libtests / fast` 四门日志+`live-legs.log`（三腿亲跑全程）+
`direct-badref_red.log`（QA 亲跑红证）+本报告。临时脚本 /tmp/t16qa-legs.sh（不入库）。
