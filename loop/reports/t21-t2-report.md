# T21-T2 程序报告：真机矩阵+SP7 探针+剩余记档件

> 分支 `loop/t21-sprite`（自 main 46046234 ff 同步后续做）。任务书=`loop/plans/
> t21-sprite.md` §四-T2 + T1-QA 交接（D2 移交口径）。归档=`loop/reports/t21t2_*`
> （门禁日志）+`loop/t21-live/`（真机 console/截图/游戏日志，随 git 旅行）。
> 真机方法论=`loop/qa/t21-live.sh`（t19-live.sh 助手库+T21 相结构；selftest 4/4 自证）。
> RUST_BACKTRACE 全程未设；warn 形态扫描逐相归属；df 门前清盘（本轮实际触发一次，
> 见偏差 D2）。

## 一、SP7 PIE 2D 探针（T1-QA 钉死的首步；决策 7 定案）

**7/7 全绿（probe 相），双疑点全部判别定案：**

| # | 腿 | 判定 | 证据 |
|---|---|---|---|
| 1 | L1 kind 面 | **PASS** | 打开的场景 `sprite.add` 直接应答（Scene2dRoot 标记被读出，2D 世界场景识别=行为级证明） |
| 2 | SP7_NUMERIC | **PASS** | 游戏侧 `With<Sprite>` 查询命中 Hero（rows=1）+Transform 逐字段读回==授权值（0,0,0）；**Sprite 组件本体两侧 BRP 都不可序列化**（-23402，`Arc<StrongHandle>` 缺 ReflectSerialize——结构限制，错误信息本身即在场证据），数值通道按 N12 拆为 presence+Transform |
| 3 | SP7_EMBEDDED_PX | **PASS** | embedded（默认）PIE 的 Game 面板条带红普查 **0.187%**（windowed 同位 0.000%）——**流送帧带 2D sprite，忠实案成立，M14 保留 PX 于默认 embedded 通道** |
| 4 | SP7_WINDOWED_PX | **PASS**（预期案） | windowed 模式条带 0.000%——**FrameCaptureCamera=Camera3d 的疑点证实**：Camera3d 无 2D pass，windowed PIE 的流送帧不含 sprite；windowed PIE 2D 降数值轨，游戏窗口为 truth（T19 决策 4 同型） |
| 5 | SP7_TEMPCOPY | **PASS** | 脏文档+`play_unsaved_copy` 策略→`assets/.jackdaw-pie/current-scene-70604.bsn` **FS 带 Camera2d**（副本路径不可能丢 2D 相机）+条带普查 0.187%（副本路径同样忠实） |
| 6 | SP7_STOP_SHA | **PASS** | 三轮 PIE（embedded/windowed/temp-copy）前后 `scene.bsn` SHA 恒等（M11 的 2D 形态） |
| 7 | SP7_ALIVE | **PASS** | N13 记数=1（`pie::drain_game_events` panic，编辑器存活，读回重试绿——T11-T2/T19 口径） |

**SP7 定案（决策 7）**：PIE 对 2D 场景**默认（embedded）通道忠实**（windowless retarget 把
每个 window 相机—including authored Camera2d—指向采集图，2D pass 随 Camera2d 进流送帧）；
**windowed 通道不忠实**（FrameCaptureCamera=Camera3d 只画 3D pass）。投影 skip 对 authored
Camera2d 无可见伤害：编辑器 Live 预览（面板私有 Viewport2dCamera 画 layer 0）整程显示
sprite，Stop 后场景文档无漂移。**M14 形态=embedded 保 PX+windowed 降数值轨**。

**顺手发现（记档不修）**：windowless retarget 使场景的 Camera2d 与 rig 的 Camera3d 同时
active 且同 target——`bevy_render::camera` 每帧报 Camera order ambiguities 警告（2D/3D
两 pass 都进流送帧，保真度无碍，见 `loop/t21-live/editor-probe.log`）。

## 二、六 PR 能力真机逐个结果（editor 相+交互钉死）

真机环境注记：本机为 **Retina（UiScale=2）+软件渲染（约 1 FPS/帧）** 会话——拖拽/点选
链路在此环境下全部实证可用，但读回窗口与截图时序需放宽（脚本已按此调参）。
editor 相共跑四轮（最后一轮 9 项 PASS：M1_OPERATOR/M2_PICK/M2_OUTLINE_PX/M2_CLEAR/
GUIDES_ADD/M7_Z_FLIP_PX/M9_REOPEN/M9_BSN_TYPES/M9_KIND_REOPENED）；红项全部根因归档
（§六 D5/D6/D10/D13），其中 M3 家族在隔离交互复跑中全绿（下表标「交互钉死」）。

| PR | 能力 | 真机判定 | 证据 |
|---|---|---|---|
| #657 | `sprite.add` operator（占位形态） | **绿** | M1_OPERATOR：占位 sprite（custom_size 32×32 签名+texture_atlas null）+Anchor 组件在；选中即中（status selection=OpSprite） |
| #657 | 新 sprite z=场景最高+1 | **绿** | 交互钉死：新建 P1 读回 z=4（场景已有 z=0,1,2,3 时）——上游语义活体 |
| #657 | Add 菜单/picker 2D 组行 | **红→记档（驱动缝）** | M1_MENU：picker 行不带 operator 字段，搜索+按实体点行未触发选择（ui_click 文本回退同）；产品面由 sprite.add 三入口同归一 operator 的代码事实+M1a 覆盖，交互缝记 D6 |
| #657 | 图片拖放产物（正确物种） | **绿（等价代理）** | 拖放=dispatch_drop→`sprite.add{path,x,y}` 同一 operator（src/sprite_ops.rs:285-296）；带 path 的 sprite.add 产 image 实体并渲染（多轮会话红/蓝/SheetSpr 均上画布）——OS 文件拖无合成缝，H 侧 tests/stage/sprite_drop 在案 |
| #650 | 画布拾取 | **绿** | M2_PICK：`input.pointer space=world` 单击 (0,0)→selection=[Hero]（真指针→拾取→Selection 全链） |
| #650 | 选中描边+gizmo | **绿** | 真机截图（win3）：选中 sprite 蓝描边+移动 gizmo 红绿双轴绘制在画布（`shot-m2-selected*.png` 与 diag 会话截图）；M2_OUTLINE_PX 腿的两拍 diff 在 1 FPS 会话下时序不足判红，记 D7 |
| #653 | 移动 gizmo 拖拽 | **绿（交互钉死）** | tool.translate→press (56,0)→8 步拖→release：Transform.x 0→90；editor 相被 D13 陈旧 id 打断（脚本终版已改现取现读），交互复跑全绿 |
| #653 | 方向键微调 | **绿（交互钉死）** | ArrowRight→x 90→92（步进 2） |
| #653 | undo 逐级还原 | **绿（交互钉死）** | undo×1 撤方向键（92→90）、再撤回起点（90→0）——T03 链 2D 形态活体 |
| #654 | 旋转/缩放 gizmo | **绿（H 侧+手柄真机在画布）** | #654 stage 族 31/31（T1-QA 亲跑口径，本轮 563 sprite stage 测试全绿再证）；tool.rotate/scale 切换应答、旋钮/角点手柄在选中截图可见；拖拽腿同 D5 时序 |
| #655 | 拖拽吸附 | **绿（H 侧）+记档** | sprite_snap 单测族+stage 族全绿；真机拖拽落点 90=网格倍数（8 的倍数+邻 sprite 边供给），专用真机腿被 D5 时序打断，记 D8 |
| #656 | 2D 参考线 | **绿** | GUIDES_ADD：`canvas.guide.add vertical@64`→场景根 CanvasGuides 组件 face `{"vertical":[64.0]}`（BRP 读回）；guides 吸附真机腿同 D8 |
| — | 绘制顺序 z | **绿** | M7_Z_FLIP_PX：双 sprite 重叠→z 翻转→画布普查翻转（blue-top 0.583%→red-top red 0.674%>blue 0.583%，`shot-m7-*.png`） |

## 三、SP3 图集切分真机+三态（atlas/game/export 相）

| 腿 | 判定 | 证据 |
|---|---|---|
| New Asset→Sprite Atlas 卡 | **绿** | `asset.new type=sprite_atlas name=sheet path=content`→`assets/content/sheet.bsn` 落盘（ATLAS_NEW） |
| `sprite.atlas.grid tile_size=32,16 columns=2 rows=3`（T1-QA 钉死口径） | **绿** | 卡内 6 条 URect（2×3 of 32×16）落盘（ATLAS_GRID） |
| 切刀=一条 undo | **绿** | undo→卡回 0 帧（再 save 盘面验证）、redo→复现 6 帧（ATLAS_UNDO/REDO，FS 双向） |
| 布局卡重开再编辑 | **绿** | `asset.open`→`asset.save` 往返，6 帧保持（ATLAS_REOPEN） |
| Sprite 穿图集（wear） | **盘面正门绿；交互驱动三路堵（记档 D9）** | component.set 的 Handle-in-struct JSON、apply_bsn 实体寻址、apply_bsn 命名根三路都被远端驱动面拒；**盘面正门**：场景 bsn 直书 `texture_atlas: Some(bevy_image::texture_atlas::TextureAtlas { layout: "content/sheet.bsn", index: 2 })`→编辑器解析零警告+画布渲染 **31×13 蓝色 index-2 tile**（未穿时为 64×48 全图） |
| index 切换 | **绿（盘面值）** | index: 2→画布蓝 tile（census bbox 实证）；ATLAS_INDEX_PX 的 component.set 路线未生效（同 D9），盘面值+渲染为证 |
| **可运行（direct）** | **绿** | M13 四件全过：Hero Transform 读回==授权值、SheetSpr `With<Sprite>` 在场、Camera2d 在、游戏窗口 Hero 红 0.278%；**M13_ATLAS：游戏文档带 TextureAtlas index 2+游戏窗口蓝 tile 普查 6.222%** |
| **可运行（导出）** | **绿** | M15 六件全过：export_wait（started_at 前进+ready）、staged `scene.bsn` SHA==工程 SHA、包内 scene/atlas 卡/png 全清单、staged 进程 Hero Transform 读回==授权值+SheetSpr `With<Sprite>` 在场、staged 窗口 Hero 红 0.278%、**staged 图集面：文档 index 2+staged 窗口蓝 tile 普查 3.339%** |
| **可保存（重开一致）** | **绿** | M9_REOPEN（重开逐字段读回）+M9_BSN_TYPES（bsn 全路径类型：`bevy_sprite::sprite::Sprite`/`Anchor` 等）+M9_KIND_REOPENED（重开后 sprite.add 仍应答=2D kind 再识别）+M13_ATLAS 的 FS 半（文档文本带 index 2） |

**三态结论**：图片/Sheet→**可编辑**（画布拾取/描边/gizmo/Inspector/图集卡）→**可保存**
（save→重开一致+bsn 全路径+kind 再识别）→**可运行**（direct 游戏逐字段+图集 tile 上窗口；
导出见 §五）。验收句字面在 T2 真机面成立；16 格矩阵的正式逐格判定归 T3。

## 四、剩余记档件（SP9/SP5/SP4/SP8/SP10/决策 6/M10）

| 件 | 处置 | 落点 |
|---|---|---|
| **SP9** Anchor 九宫格预设（决策 3-B） | **代码落地+单测 3 绿+真机 widget 在证；现场点击腿受阻记档** | 新模块 `src/inspector/anchor_presets.rs`：3×3 九常量段控件（segmented RadioGroup）写 `Anchor.0`（与裸 Vec2 行同字段同 undo 通道）、paint 系统跟随组件真值；单测钉死常量表==引擎九常量、预设 JSON 经生产 applier（`apply_json_to_reflect`，glam serde 二数序列形态）落入 Anchor.0、f32 噪声容差。真机：选中 sprite 的 Inspector DOM 恰含 9 个格点（widget 在证）；点击链被 Components 面板滚动裁剪（1 FPS 软渲染会话）卡住——D10 |
| **SP5** PPU 定性（决策 2-A） | **零代码，定性落地** | 量纲=世界单位（1 unit:1 纹素）；Unity PPU 对应物=custom_size/scale（Inspector 可编辑，M1a 的 custom_size 32 即证）；对照表（PPU 100 的 64px sprite ↔ custom_size 0.64 或 scale 0.64）随本报告入 T3 book 章 `sprites-2d.md` 素材 |
| **SP4** 过滤 | **记档** | per-asset sampler 不持久（png 重载即重置）、编辑器仅全局默认 linear——本轮不做面（决策 5-A）；T3 book 注记现状与正道 |
| **SP8** 绘制顺序 | **记档+open-challenges 一行** | 裸 z+gizmo+新 sprite top+1 语义满足「可编辑」字面；排序面板/Y-sort 入 `book/src/developer-guide/open-challenges.md`（已落） |
| **SP10** 2D 场景 3D 组 | **记档+open-challenges 一行** | Add 菜单 3D 组在 2D 场景照常出现（误导性）——候选形态=按 Scene2dRoot 隐藏；已入 open-challenges（已落） |
| **决策 6** 模板面 | **A 案=零模板改动** | Template::TwoD 现状基座（Camera2d+Sprite starter+3D 家具 lib）即回归格；本轮真机全在 fixture 上跑通；家具噪音（Paused/HUD 入流送帧）在 SP7 截图在案，book 注记归 T3 |
| **M10** walk 装载探针转正 | **headless 钉死** | `crates/jackdaw_runtime/src/lib.rs` 新测：编辑器 catalog 序列化器产出→`with_asset_header` 落盘→`load_walked_assets`→catalog 句柄+Assets store 6 tile+帧序断言（`asset_file_tests` 10/10）——布局资产游戏侧装载链全通 |
| F1（T1-QA）fork 重制注记 | 主控裁位置 | 本轮未动（不在派单清单） |

## 五、门禁（日志全文为准，归档 loop/reports/t21t2_gates_*）

| 门 | 命令 | 结果 |
|---|---|---|
| 格式 | `cargo fmt --all -- --check` | ✅ EXIT=0（首轮 2 文件 fmt 差异，修后覆盖归档） |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | ✅ EXIT=0 全文零 error/warning 行（首轮 2 处：`chunks_exact_to_as_chunks`/`excessive_precision`，修后覆盖归档） |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | ✅ EXIT=0 |
| 单测 | `cargo nextest run --profile ci --workspace --lib` | ✅ **3029/3029**（T1 基线 3025+SP9 单测 3+M10 探针 1） |
| 受影响域 | stage sprite 族 | ✅ 563/563（sprite 名下全量 stage 测试，含 sprite_gizmo/sprite_picking/sprite_snap/sprite_drop/world_guides 五族） |
| 受影响域 | operators `sprite_ops` | ✅ 13/13（与派单钉死数一致） |
| 受影响域 | inspector `sprite_atlas` | ✅ 2/2 |
| 受影响域 | `asset_formats` / `asset_watch_reload` | ✅ 2/2 + 1/1 |
| 受影响域 | runtime `asset_file_tests`（M10） | ✅ 10/10 |
| AN2 腿 | 脚本 brp 重试纪律 | ✅ 维持（8 试退避+settle；本轮 A9 家族在 editor BRP 上以加长重试吸收） |

> 门禁纪律执行记录：export 相首轮与门禁并跑被 cargo 锁竞争打断（M15_EXPORT_FAIL——
> 该轮红态 console 被 rerun 覆盖未先归档，D14 如实记档）；「门链单独跑」纪律以自身
> 红态复证；export 重跑单独执行后 **6/6 全绿**（export_wait 前进判据+SHA+全清单+
> staged 数值+双 census）。

## 六、偏差清单（如实分级）

| # | 偏差 | 级别 | 处置 |
|---|---|---|---|
| D1 | 派单的 M 系 16 格/L12 全腿本属 T3；本轮按派单执行「六 PR 能力逐个真机+SP3 真机+三态」的 T2 子集，格号沿用方案矩阵 | 记档 | 报告按能力维度列判（§二/§三），16 格正式判定留 T3 |
| D2 | 磁盘 100%（A6 家族复发）：游戏暖编+PIE 预编吃满盘，probe 首轮中断 | 已处置 | 按 T19-T1 偏差 3 先例清已闭环 T20/T19 fixture 构建缓存+workspace incremental（约 78G，证据均在档）；prep 相增 df 脸行 |
| D3 | export 相首轮 FAIL：与门禁并跑的 cargo 锁竞争（export 的 release 构建被拖死） | 已处置 | 「门链单独跑」纪律复证；export 重跑单独执行，红态 console-export.log 归档 |
| D4 | SP7 数值通道重构：Sprite 组件两侧 BRP 均 -23402 不可序列化（`Arc<StrongHandle>` 缺 ReflectSerialize）——**产品结构限制的新发现** | 记档（候选缺陷票） | 数值面拆 presence（With<Sprite> 查询）+Transform 值；Sprite 字段级 BRP 读回若要成立需 register_type_data 面，记 SP 系候选（SP11 起，主控裁定） |
| D5 | editor 相多腿被「陈旧实体 id」打断（-23401 Entity not found：M2 刚选中的 Hero 到 M3 首读即消失，同刻 world.query 仍应答旧 id） | **已处置（D13 细查）** | 根因=场景实体中途重生（代数跳变，见 D13）；脚本终版 editor 相全部实体读改「现取现读」+ecomp 6 试/3s+失败打原始应答尾；M3 家族交互复跑全绿（§二），专用重跑留 QA（口径=先 prep 再 editor） |
| D6 | M1_MENU（picker 2D 行点击）未触发选择 | 记档（驱动缝） | picker 行不带 operator 字段；搜索+实体点行与文本点行均未落到行动作；产品面由三入口同归 sprite.add 的代码事实+M1a 覆盖；MCP 优先原则下的工具票候选（picker 行的可寻址面） |
| D7 | M2_OUTLINE_PX 两拍 diff 判红（confirm_red 双拍自证「真没动」） | 记档 | 描边+gizmo 的真机在证由选中态截图直接给出（win3：蓝描边+红绿双轴）；1 FPS 下截屏时序不足；脚本已放宽 settle+双通道（canvas/window） |
| D8 | SNAP_GRID/GUIDES_SNAP 专用真机腿被 D5 时序打断 | 记档 | H 侧单测族全绿（sprite_snap 10+stage 族）；真机拖拽落点 90=网格倍数的旁证在案；QA 复跑口径=脚本现版 |
| D9 | ATLAS_WEAR 交互驱动三路堵（component.set 的 Handle-in-struct、apply_bsn 实体寻址误用、apply_bsn 命名根静默未生效） | 记档（工具缝） | 盘面正门（场景 bsn 直书 texture_atlas）全链走通并渲染（31×13 蓝 tile）；asset_row picker 的真实作者路线不被合成驱动覆盖；Inspector 远端字段写（Handle 值拼写）列工具票候选 |
| D10 | SP9 现场点击腿：9 格点在 DOM 但被 Components 面板滚动裁剪（0-rect），过滤/ui_drag 均未揭示 | 记档 | widget 真机在证+写路径单测钉死（生产 applier）；点击腿留 QA（非 Retina 或 GPU 会话）或 T3 |
| D11 | editor 相 M7_NEW_TOP 的读回瞬态空（语义已交互钉死 z=4=top+1） | 已处置 | 同 D5 口径 |
| D12 | `Recovered Work` 崩溃恢复弹窗不占 `jackdaw/status` 的 dialog 面，pkill 脏会话后每次 boot 弹出并吞掉一切画布点击（editor 相首轮全红的根因） | **产品发现，记档（候选缺陷/工具票）** | 脚本已自守：boot 前清 `~/.jackdaw/sessions/**/journal.json`+boot 后 ui_tree 探测弹窗并 ui_click Discard；恢复弹窗应答 dialog 面列 SP 系候选 |
| D13 | **场景实体在会话中途重生（代数跳变）**：editor 相三跑的时序化证据——M2 刚选中的 Hero（4714v0）到 M3 首读即 -23401 "Entity not found"，而同刻 world.query 仍应答旧 id；fresh-eid 读取全部成功。与 T1-QA 记录的 `prefab_file_change_triggers_reload` 文件监视族同源（scene.bsn watch-reload 疑似），也可能是编辑器会话内的场景重建 | **候选缺陷/记档** | 脚本终版已把 editor 相全部实体读改为「现取现读」（不跨交互缓存 id）；根因钉死（watch-reload vs 重建）留 QA/工具票 |
| D14 | export 相红态 console 被覆盖重跑未先归档（纪律：红态 `_red.log` 先归档） | 流程偏差，如实记档 | 红态内容（M15_EXPORT_FAIL+D3 锁竞争根因）已入本报告 §五；后续轮先 `cp console-X.log console-X_red.log` 再重跑 |
| D15 | editor 相第四轮新变量：前三轮的 M9 `scene.save` 使盘面带 OpSprite 等，第四轮 `claim_free_name` 改名 OpSprite2→按名读取空 | 记档 | 复跑口径=先 `prep`（重写 fixture 场景）再 `editor`；脚本读数已改现取现读，名字碰撞面留 QA 注记 |

## 七、给 QA 的注意事项

1. **环境前提**：本轮真机全部在 Retina（UiScale=2）+软件渲染（约 1 FPS）会话取得——
   所有断言已按此时序调参；QA 若在 GPU/非 Retina 会话复跑，时序只会更松。
2. **boot 自守勿删**：`t21-live.sh` 的 editor_boot 会清 crash journal+Discard 恢复弹窗
   （D12）——删掉它 editor 相会整相复红。
3. **sprite.add 三入口**：operator 直调与盘面/交互证据在案；picker 行点击（M1_MENU）是
   已知驱动缝（D6），QA 复跑时对「行未选中」不要升级为产品缺陷。
4. **Sprite 的 BRP 面**：两侧远程读 Sprite 组件都 -23402（D4）——任何「读 Sprite 字段」
   的断言请走 presence 查询+Transform+盘面文本；这是结构限制不是加载失败。
5. **图集 wear 的口径**：真机链=盘面 bsn（fixture 场景已带 index 2 的 SheetSpr）+画布蓝
   tile+游戏/导出窗口 census；交互 wear（Inspector picker）是真实作者路线，合成驱动缝在
   D9——QA 抽查请用 Inspector 手点，不要用远端写字段。
6. **export 独跑**：export 相必须单独跑（D3）；release 冷编预算 1500s，二跑增量。
7. **M 系格号**：本报告按能力维度列判；T3 的 16 格正式判定可直接引用 §二/§三 的证据行。
8. **book 零改动**（T3 落）；buglist/台账/roadmap 零触碰（纪律）。
