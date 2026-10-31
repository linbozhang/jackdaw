# T19 画质设置与游戏输出一致性 — 实施方案

> 策划产物（2026-10-28，基于本地 main **68df502f**（T18 收官合入）全量只读调研：编辑器
> `src/graphics_panel.rs`（794 行）、`src/viewport_settings.rs`（715 行）、
> `src/viewport_quality.rs`（473 行）、`src/environment_ops.rs`、`src/screenshot.rs`、
> `src/remote/server.rs` 截图/wait 面板、`src/pie.rs`/`src/pie_current.rs`（T06 启动链）、
> `src/scene_io/mod.rs` 场景相机停用面、`src/camera_preview.rs`；场景类型与表面层
> `crates/jackdaw_scene_types/src/environment.rs`（401 行）、
> `crates/jackdaw_surface/src/environment.rs`（1,419 行，含测试族）；游戏侧
> `crates/jackdaw_runtime/src/lib.rs`、`crates/jackdaw_runtime/src/pie_frames.rs`、
> `crates/jackdaw_runtime/Cargo.toml`、`crates/jackdaw_remote/src/lib.rs`、
> `crates/jackdaw_project_build/src/export.rs` staging、`crates/jackdaw_scaffold/src/lib.rs`
> 模板 feature 链+`templates/game/assets/scene.bsn`、`crates/jackdaw_camera_rig/src/lib.rs`；
> fork `/Users/zhanglinbo/workspace/bevy-fork-pinned` 的 `bevy_internal/Cargo.toml` +
> `bevy_solari/src/lib.rs`；workspace `Cargo.toml` bevy features；本地化
> `crates/jackdaw_localization/src/locales/en-US/main.ftl`；book
> `book/src/user-guide/graphics-panel.md`；tests/viewport/graphics_panel.rs（469 行 8 件）、
> tests/stage/scene_environment.rs；功能 #8 三份报告（t1/t2/final-qa）+方案；QA 先例
> `loop/qa/t16-live.sh`/`t18-live.sh`/`t14-live.sh`/`pixdiff.ps1`；buglist.md 全量
> graphics/exposure/bloom/AA/GI/截图域扫描。**零临时探针**——本方案的关键结论（双区
> operator 面、opt-out 恒真位、游戏侧 EnvironmentPlugin 挂载、导出 staging 携带面、
> viewport.json 用户级路径、solari feature 全链缺席）全是静态可复核事实，无需运行时探针。
> 需求来源：`loop/plans/roadmap-game-dev.md` T19（第 33 行，T01-T18 已闭环）。
> **验收原文**（roadmap 第 33 行，逐字核实）：「**画质设置与游戏输出一致性：Graphics
> 面板边界验证+游戏运行/导出应用链路。验收=场景级曝光/Bloom/AA 在 Play+导出生效；
> editor 偏好不污染游戏；GI 保持禁用说明。**」
> **任务定性：混合型、严重偏验收型（约 85/15）**——T12/T15/T16/T18 的「反转读法」在此
> 第五次适用：功能 #8 已交付 Graphics 面板双区成品（Viewport 区 editor-only 即时、
> Scene 区 `environment.set` UI 皮零双写、单 undo、空态/越界提示三态、GI 置灰行+tooltip
> 全在库且被 8 件 headless 测试覆盖）；画质数据模型与 dress 管线两侧同链（编辑器
> `src/lib.rs:452` 与游戏 `crates/jackdaw_runtime/src/lib.rs:347` 装**同一个**
> `EnvironmentPlugin`，`dress_the_cameras` 一份代码吃两条进程）。真正的缺口是**证据链
> 三个铁证各缺一块**：①「在 Play+导出生效」的场景级端到端证据零（机制在场、验收腿
> 从未跑过，T15 AN2 同型）；②「editor 偏好不污染游戏」的负向证据零——feature-08
> 终验自己记了 ⚪（「『A 区改动后 Play 不泄漏』真机 Play 专项未单独做」，
> feature-08-final-qa.md:68）；③「GI 保持禁用说明」是纯回归格（已交付，重验不破）。
> 缺陷候选按 **GR 系**编号（Graphics-Run parity，避开 buglist R/Y/W/A/N 系与 T01-T18
> 各任务编号系 U/I/F/C/PF/AN/AU/AR），只记不修→主控裁定吸收面。
> 真机口径：**macOS（本机）**，bash+curl+jq 驱动编辑器 BRP 15703 与游戏 BRP 15702
> （`loop/qa/t16-live.sh` 全套形态复用：leg/summary/cleanup trap/`$PHASE` 日志名/
> gbrp 重试助手/export_wait/staged 启动）；像素证据=T18 的 `png_pixels_md5`+`sips` 裁剪
> MD5 形态+feature-08 的 pixdiff 先例（通道内红绿，**不做跨通道逐像素相等**，决策 1）；
> **勿设 RUST_BACKTRACE**（T11-T3 口径）；游戏侧数值断言全走 bevy 原生
> `world.query`/`world.get_components`（N12 口径）；A9（游戏 BRP 空响应）gbrp 自守；
> A7（截图同帧 flake）脚本五招自守（决策 6）；N13（PIE drain panic，100% 复发）绕行+
> 记数；warn 形态扫描（`tonemapp|bloom|exposure|solari|ray|UnresolvedTypes|panicked`）
> 入常备腿。

---

## 0. 架构事实（核实结论，方案的地基）

**总判断：T19 不是「建应用链路」——场景级画质从作者（面板/`environment.set`）到编辑器
预览、PIE、direct run、导出 staged 四通道的**机制链今天就是同一份代码**：`Environment`
组件随 `.bsn` 存盘，游戏进程与编辑器进程装同一个 `EnvironmentPlugin`，`dress_the_cameras`
把 `Environment.post` 逐字段映射成 bevy 相机组件；编辑器独有的 `ViewportSettings` 存用户
级 config 目录、只 dress 编辑器视口相机、游戏进程根本没有这个类型。T19 的工作是把验收句
的三个铁证跑实：四通道一致性矩阵（数值+像素双轨）、editor 偏好不污染的负向三腿、GI
回归。** 十六条事实：

- **事实一：双区面板是交付成品，写入面零新增存储。** A 区（Viewport）控件全部落到
  `viewport.*` operator 家族：preset（`src/graphics_panel.rs:552-554`）、AA/SSAO 质量/
  render scale（`:555-560`+`:610-613`）、开关族（`:577-596`）、sharpen（`:614-616`）——
  全家 `allows_undo=false`（`src/viewport_settings.rs:355,380,453,486,522`），落盘走
  `store_viewport_settings`（resource_changed 即写，`:330-347`）进用户级 `viewport.json`
  （路径=`config_dir()/viewport.json`，`crates/jackdaw_env/src/paths.rs:59-62`；文件头
  doc 明言「kept per user…never in a scene…Play and the saved file are unaffected」
  `src/viewport_settings.rs:3-6`）。B 区（Scene）控件全部是 `environment.set` 的 UI 皮：
  post.enabled（`graphics_panel.rs:584-586`）、tonemapper（`:634-650`）、三条滑条只在
  release（`is_final`）提交（`:622-631`，一条拖动一条 undo）；`environment.set` 按
  reflect 路径写任意 `Environment` 字段（`src/environment_ops.rs:134-174`，枚举臂
  `:218+`——`post.antialiasing`/`post.msaa` 可写），内部 `SetEnvironment` 单条 undo
  （`:163-172`）。
- **事实二：场景级画质的数据模型完备且字段级默认清晰。** `Environment{sky,fog,ambient,
  post}`（`crates/jackdaw_scene_types/src/environment.rs:6-13`）；`PostProcess` 含
  `enabled/tonemapper/exposure/bloom_intensity/bloom_threshold/vignette×2/antialiasing/
  msaa/shadow_filtering`（`:271-306`），默认=9.7 EV100/TonyMcMapface/bloom 0/
  antialiasing Keep（`:308-329`）；`Antialiasing` 五态 Keep/Off/Fxaa/Smaa/Taa（`:222-237`）。
  **面板 B 区只有 4 行**（Post Processing/Tonemapper/Exposure/Bloom×2，
  `graphics_panel.rs:414-521`）——**场景级 AA 不在面板上**，其授权面=`environment.set`
  post.antialiasing（Inspector 同路径，tests/stage/scene_environment.rs 既有形态）。
- **事实三：dress 管线两侧同一份代码，「游戏输出」的画质就是它。**
  `jackdaw_surface::EnvironmentPlugin` 在 PostUpdate 链
  `follow_the_scene_environment→…→dress_the_cameras`（`crates/jackdaw_surface/src/
  environment.rs:71-87`）；取场景里**第一个** `Environment`（`:433-441`
  `Query<&Environment>.iter().next()`）；`dress_the_cameras` 对**每个默认 RenderLayers 的
  `Camera3d`**（`:473,503-505`）按 `EnvironmentOptOut`（`:125-135`）逐区 dress：
  `dress_post` 写 `Tonemapping/Exposure/ColorGrading`（`:689-695`）、Bloom 强度/阈值
  （`:696-703`）、AA+MSAA（`!left_out.antialiasing` 时，`:713-723`）、阴影滤波
  （`:724-729`）；`UndressedCamera` 保管原状、环境消失即还原（`:94-109,576-608`）。
  编辑器进程装它（`src/lib.rs:452`），游戏进程装它（`crates/jackdaw_runtime/src/lib.rs:
  341-352`，`render` feature 下 `:347`；模板 runtime features 恒含 terrain+pie，
  `crates/jackdaw_scaffold/src/lib.rs:2677-2685`，`render` 是 default
  `crates/jackdaw_runtime/Cargo.toml:76`）——**四通道的 dress 无 fork、无第二实现**。
- **事实四：编辑器与游戏的画质不对称只有两处，都是设计态。** ①**视口 opt-out**：编辑器
  视口相机挂着 `environment_opt_out(&ViewportSettings)` 推导的 `EnvironmentOptOut`，
  其中 `antialiasing: true` **恒真**（`src/viewport_quality.rs:93-102`，:100）——场景 AA
  永不落编辑器视口（book 明言，`book/src/user-guide/graphics-panel.md:69-70`）；
  post_processing/bloom 两把闸随 Viewport 质量走（`:96-99`，High 默认档全开：
  `viewport_settings.rs:108-109`+`ViewportQuality::default()=High` `:230-234`）。
  `dress_viewport_cameras` 只碰 `MainViewportCamera`（`:137-224`，AA 插拔 `:155-188`、
  SSAO 质量 `:189-202`、CAS `:203-215`、阴影 resource `:244-266`、render scale
  `:336-360`）。②**场景文档相机在编辑器不渲染**：`deactivate_document_cameras` 把
  文档相机 `is_active=false`（`src/scene_io/mod.rs:306,316-326`）——编辑器的活相机只有
  视口相机；游戏侧无此系统，模板游戏的相机=CameraRig 代码物化的 `Camera3d`
  （`crates/jackdaw_camera_rig/src/lib.rs:142-153`，`:152` `try_insert(Camera3d::default())`），
  不带任何 OptOut ⇒ 场景 AA/全量 post 只在游戏通道生效。
- **事实五：「editor 偏好不污染游戏」是三层架构边界，机械可断。** ①存储层：
  `viewport.json` 在**用户 config 目录**（事实一），不在工程树——导出 staging 按工程
  assets 树整树拷贝（事实九），物理上不可能带它；且 `JACKDAW_CONFIG_DIR` 可整体换向
  （`paths.rs:26-40`）——隔离腿的现成测试缝。②进程层：游戏二进制（模板只链
  jackdaw_runtime，不带编辑器 crate）**没有 `ViewportSettings` 类型**；`jackdaw_remote`
  注入面只有 app_info/scene_snapshot/diagnostics/playback/apply_bsn/archetypes/schedules
  （`crates/jackdaw_remote/src/lib.rs:100-117`）。③作用层：A 区 operator 只写
  `ViewportSettings` resource，`dress_viewport_cameras` 只查 `MainViewportCamera`
  （编辑器实体）；既有 headless 锚=面板 A 区全操作 undo 栈零条目
  （tests/viewport/graphics_panel.rs:245-249）。**缺的是把三层各钉一条真机/盘面证据**
  （GR2）。
- **事实六：PIE 通道=独立游戏进程读盘上场景，editor 偏好无从掺入。**
  `pie.play_current` 的未保存策略先走保存链或临时副本（`src/pie_current.rs:10-13,167-233,
  251+`；temp copy 同源原子写、不进 save journal）；启动即 `JACKDAW_PIE` 连 IPC
  （`crates/jackdaw_runtime/src/lib.rs:379-385`）；PIE 流送帧=**离屏渲染 active camera
  rig**（`crates/jackdaw_runtime/src/pie_frames.rs:110,298` FrameCaptureCamera+pace），
  与游戏窗口同相机组件面——流送帧是否忠实带 dress 组件是 GR8 探针点。
- **事实七：direct run 通道=模板工程 `cargo run`，与 PIE 同一二进制。** T16 真机腿形态：
  `direct_run`（t16-live.sh:273-278）+游戏 BRP 15702（`jackdaw_remote` 注入是**测试缝**，
  prep 相两行 sed，:458-465；发货游戏不带它——与 T18「游戏侧 dormant」同型的注入纪律）。
- **事实八：导出通道携带面=整棵 assets 树减编辑器私件。** `game.export` →
  `jackdaw_project_build::export`（`src/game_export.rs:11`）：assets_dir 按 `jackdaw.toml`
  （`crates/jackdaw_project_build/src/export.rs:97-108`），`copy_tree` 名单过滤只有
  PIE 临时目录/保存轮转/原子写残件（doc `:688-695`「deliberately narrow」、`copy_tree`
  `:696+`、过滤臂 `:710-712`）
  ⇒ 带 `Environment` 的 `scene.bsn` 原样进 staged 包；`export-manifest.json` 全清单
  （T07 交付）；t16 的 `export_wait` 以「staged scene.bsn SHA==工程」为就绪判据
  （t16-live.sh:335-351）——SHA 对比形态直接复用为 T19 的携带面断言。
- **事实九：编辑器侧数值与像素断言通道齐备。** 数值：编辑器 BRP `world.query`/
  `world.get_components` 对视口相机读 `Exposure/Bloom/Tonemapping/Fxaa/Smaa/
  TemporalAntiAliasing/Msaa` 组件（t16 编辑器腿同法，:504-506）；像素：
  `jackdaw/screenshot`（`src/remote/server.rs:1783-1864`，kind=viewport 渲染目标直拍/
  window；`request` 键+PendingWaits 防陈旧帧，:1798-1836；采集前 SETTLE_FRAMES=90
  `src/screenshot.rs:22`）。T18 的 `png_pixels_md5`（纯 python3 解 PNG 求 RGB md5，
  t18-live.sh:272-311）+`sips` 裁剪（:476-484）是 Mac 像素证据成熟形态。
- **事实十：游戏侧数值断言通道齐备，像素通道只有 OS 截图。** 游戏 BRP 无截图方法
  （事实五②清单）；像素证据=`screencapture -x`（t16/t15/t17 全用过，如
  t16-live.sh:225-226）+sips 裁剪游戏窗口区域。游戏侧组件读回用 bevy 原生
  `world.get_components`（t16 `gcomp` :283-293；N12 口径）。
- **事实十一：headless 锚两侧都在，缺的是跨通道锚。** 编辑器侧：面板 8 件
  （tests/viewport/graphics_panel.rs:120-469：注册/双区文本/A 区零 undo/B 区 release
  单 undo/GI 禁用+tooltip/opt-out hint/空态 hint）；dress 侧：
  `post_settings_reach_the_camera_components`（`crates/jackdaw_surface/src/environment.rs:
  995`）、AA/MSAA 替换与还原（`:1037,1083`）、环境移除还原（`:1130`）、非场景相机不动
  （`:1191`）；stage 侧：environment.set+undo（tests/stage/scene_environment.rs:110）、
  保存重载（:171）、**dress 不污染存档**（:219「a camera the environment dresses saves
  as it was authored」）。游戏侧端到端锚：`animation_scene_load.rs` 的 feature 转活是
  T15 先例，画质域**无对应物**（GR1 的一部分）。
- **事实十二：GI「保持禁用说明」已交付三层，本任务是纯回归格。** ①面板置灰行：
  `build_realtime_gi_row`（`graphics_panel.rs:525-540`，`InteractionDisabled`+`Tooltip`）；
  ②文案三层一致：ftl（`crates/jackdaw_localization/src/locales/en-US/main.ftl:36-37`，
  tooltip 含 Solari/experimental/未接入+四替代项）、book（`book/src/user-guide/
  graphics-panel.md:72-80`）；③headless 锚：GI 行禁用+tooltip 含 Solari
  （tests/viewport/graphics_panel.rs:373-394）。④机制缺席：workspace bevy features 无
  `solari`（`Cargo.toml:224-242`，全仓 grep 仅 graphics_panel.rs:11 doc 注释命中），
  fork 中 `bevy_solari` 是 optional feature（`bevy-fork-pinned/crates/bevy_internal/
  Cargo.toml:291`）且要求 `EXPERIMENTAL_RAY_QUERY` 硬件光追（`bevy_solari/src/lib.rs:52`）。
  「保持」=矩阵回归格，「说明」=文案三层仍在。
- **事实十三：模板 scene.bsn 无 Environment——「开箱一致」的对照态现成。**
  `crates/jackdaw_scaffold/templates/game/assets/scene.bsn:5-28` 只有 Sun+Ambient（音频）
  ⇒ 新工程 Scene 区空态提示（T08-T3 交付的 `GraphicsSceneEmptyHint` 三态）+四通道同为
  「无 dress 默认」。T19 的正矩阵需要 fixture 带 Environment（prep 注入），
  **对照矩阵**用无 Environment 态（四通道相机组件恒等=bevy 默认）。
- **事实十四：像素证据的既有先例与阈值手感。** feature-08（Windows pixdiff.ps1）：
  SMAA 3.89%/SSAO on-off 2.17%/bloom 77.11%（feature-08-final-qa.md:65-66）——
  通道内 before/after 的 %changed 是本域像素红绿的成熟判据；T18（Mac）改为
  `png_pixels_md5`+crop MD5 的「变/不变」判据（AR9 的 teal 判别色+双不等判据）。T19
  两套并用：编辑器视口用 % 形态（渲染目标直拍、尺寸稳定），游戏窗口用 MD5 变/不变+
  裁剪（窗口 chrome/标题栏噪声用 crop 隔离）。
- **事实十五：截图通道的两笔已知债正好压在本任务的证据主道上。** A7 家族并账条目明载
  「`jackdaw/screenshot` 同帧 flake（60s 两帧 md5 同）」（buglist:459-464，2026-10-30 并账）
  ——画质验收的像素证据全靠截图，flake 直接产假绿/假红；W4：截图观察者不触发时采集
  相机滞留、编辑器 gizmo 永久熄灭（buglist:303，`src/camera_capture.rs:144-164`）——
  高密度截图腿可能踩。缓解见决策 6（五招自守，不前置修票）。
- **事实十六：feature-08 终验遗留的 ⚪ 就是本任务的格。** 「TAA 自身 pixdiff、SSAO
  Low↔Ultra 档位 pixdiff、Play 泄漏真机专项未单独做」（feature-08-final-qa.md:100）——
  前两样归 M 系顺带腿，第三样是 M9-M12 的正主；「t2 concern#1（无环境时 B 区开关乐观
  回写）维持记录不修」（:71）原样维持，GR5 记档。

### 验收句逐词定性（矩阵化的前提）

| 验收词 | 定性 | 依据 |
|---|---|---|
| Graphics 面板边界验证 | **验成晶+负向证据缺口（GR2）** | 双区写入面/undo 语义/空态与 opt-out 提示全交付且 8 件 headless 在案（事实一）；「边界」的运行态半边（A 区改动不进文档/不进包/不进游戏）零真机证据，feature-08 终验 ⚪ 遗留（事实十六） |
| 游戏运行应用链路 | **机制成晶+端到端证据缺口（GR1）** | 游戏进程装同一 EnvironmentPlugin（事实三）；PIE/direct 通道机制在场（事实六/七）；「场景级值→游戏相机组件」的真机读回腿从未跑过 |
| 导出应用链路 | **机制成晶+端到端证据缺口（GR1）** | staging 携带整棵 assets（事实八）；「staged 场景的画质=编辑器所配」零证据（T12 格 9/T14 L6 同型腿在画质域缺位） |
| 场景级曝光在 Play+导出生效 | **半成晶（编辑器侧在案，游戏侧缺口）** | 编辑器侧：B 区滑条→`post.exposure`→`Exposure.ev100` 组件断言+`post_settings_reach_the_camera_components`（事实十一）；游戏侧零 |
| Bloom 在 Play+导出生效 | **半成晶（同上）** | dress_post 的 Bloom 映射+面板 release 提交成晶；游戏侧数值/像素零 |
| AA 在 Play+导出生效 | **机制成晶+授权面注记（GR3）** | `post.antialiasing`→`dress_antialiasing`、游戏相机无 opt-out（事实四）；**面板无 AA 行**，授权面=`environment.set`（事实二）；编辑器视口恒 opt-out=边界本身要断言而非缺陷 |
| editor 偏好不污染游戏 | **架构成晶+负向证据缺口（GR2）** | 三层边界全在场（事实五），负向三腿（SHA/包/游戏数值）零证据 |
| GI 保持禁用说明 | **验成晶（纯回归格）** | 置灰行+tooltip+book 三层在案（事实十二）；「保持」=M13 复验不破 |

---

## 一、缺陷候选（GR 系，只记不修→主控裁定吸收面）

| 编号 | 严重度 | 描述 | 证据 | 处置建议 |
|---|---|---|---|---|
| **GR1** | 🔴 | **「场景级画质在 Play+导出生效」零端到端证据**：机制链在场（事实三/八）但「同一场景文档在四通道的画质应用一致」无任何测试或真机腿；T15 AN2 同型（连手写文档的游戏侧运行证据都不跑） | 事实十一：游戏侧端到端锚不存在 | **吸收（验收主任务）**。T2 真机矩阵 M4-M8/L3-L6 落证；headless 侧可对照 T15 先例给一条 runtime e2e 锚（决策 3 附带，非硬性） |
| **GR2** | 🟡 | **「editor 偏好不污染游戏」负向证据零**：三层边界（存储/进程/作用）全在场，但「A 区全操作后场景文档不变+导出包不变+游戏相机组件不变」的证据链不存在——feature-08 终验 ⚪（:68,:100） | 事实五/十六 | **吸收（本任务建设小头）**：M9-M12 三腿+T1 补一条 headless 负向守卫（A 区操作→scene.save→文档字节 SHA 不变） |
| **GR3** | ⚪ | **场景级 AA 无面板行**：B 区 4 行不含 AA/MSAA/阴影滤波——「场景级 AA」作者只能走 Inspector/`environment.set`；feature-08 方案本来就把场景侧 preset/AA 面板化放 backlog（feature-08-graphics-panel.md:176） | 事实二 | **不吸收（范围边界）**：验收词不要求面板行；矩阵以 `environment.set` 为授权面跑通；book 注记「场景 AA 走 Inspector」；面板补行记 open-challenges 一句话 |
| **GR4** | ⚪ | **TAA 时间态使「即拍即比」有 settle 边界**：TAA 首帧 reset+历史收敛，截图过早则红绿差被时间噪声污染；feature-08 风险 2 已记 settle 惯例（≥2 帧） | 事实十四；`src/screenshot.rs:22` SETTLE_FRAMES=90 内置 | 不吸收为缺陷：腿内纪律（截图前 settle sleep≥2s+AA 切换后首拍丢弃）；写进脚本注释 |
| **GR5** | ⚪ | **视口 opt-out 关闭时 Scene 区仍可写（乐观回写瞬时态）**：t2 concern#1 维持记录不修（feature-08-final-qa.md:71）；提示行（`GraphicsOptOutHint`）已把「静默」改「明说」 | 事实十六；`graphics_panel.rs:745-759` | 维持不修；M 系顺带复验提示行三态（headless 锚 :400-427 复跑） |
| **GR6** | ⚪ | **R12（buglist:78 灯光投影开关无效果）与 A 区 Sun/Point Shadows 开关同域**：A 区回归腿顺带抽查开关的像素红绿与 `ShadowCasters`/shadow map resource 断言；若真踩 R12 形态（真机无效）如实立账不追修 | buglist:78；`viewport_quality.rs:244-266,370-418` | 抽查腿+记档；R12 本体不吸收（其表述「场景渲染模式」可能指 view modes 域，T19 只验 A 区开关自身） |
| **GR7** | ⚪ | **模板开箱无 Environment**：新工程 Scene 区空态+四通道同为 bevy 默认——「开箱一致」是对照态而非缺陷（空态提示已交付 T08-T3） | 事实十三 | 对照矩阵格（M0 形态）用之；book 注记 |
| **GR8** | ⚪ | **PIE 流送帧的画质忠实性未验证**：流送帧=离屏渲染 active camera rig（事实六），若 FrameCaptureCamera 链不吃 dress 组件，Game 面板所见与游戏窗口不一致——只影响「PIE 视觉证据通道」的可信度，不影响游戏本体 | 事实六；`pie_frames.rs:110,298` | **T1 首步探针定案**：PIE 流送帧 vs 游戏窗口截图对 bloom/exposure 红绿是否同向；若不忠实，PIE 通道降级为数值轨（决策 4） |

统计：🔴 1（GR1，验收缺口非产品缺陷）｜🟡 1（GR2）｜⚪ 6（GR3-GR8）。

### buglist 重叠表（graphics/exposure/bloom/AA/GI/截图/PIE 域全量扫描）

| 条目 | 一句话 | T19 处置 |
|---|---|---|
| **A7**（buglist:459-464） | 真机驱动工具债 6 腿+**截图同帧 flake（60s 两帧 md5 同）**+stale grep——画质验收重像素证据，正面撞上 | **不前置，脚本五招自守（决策 6）**：①每拍唯一 `request` 键+`rm -f` 先行（PendingWaits 防陈旧帧，server.rs:1798-1836）；②落盘后验文件 size>0（t16 shot 形态）；③**相邻两拍健全性断言**——判「红」前先拍两张同态对照，md5 相等即判 flake 重拍（flake 探针，非判据）；④失败降级 `screencapture -x`（t16 先例）；⑤warn 扫描日志名随 `$PHASE`（stale-grep 教训）。真踩不可绕则按 MCP 优先原则现场立项 |
| **A9**（buglist:485） | 游戏 BRP 间歇空响应+方法瞬失 | **自守不前置**：gbrp 重试+settle（t16-live.sh:104-123 原样复用）；数值断言全小响应体（单实体单组件）；避开 scene.open/构建窗口（editor_build_settled 先行） |
| **W4**（buglist:303） | 截图观察者不触发→采集相机滞留→gizmo 永久熄灭——高密度截图腿可能踩，且 gizmo 消失会**污染后续视口像素证据** | **自守**：每条截图腿后断言 BRP 活性；编辑器分相（editor 相跑完即 pkill 重启下相——t16 分相纪律）把 W4 的暴露窗压到单相内；真踩（gizmo 集体消失）记 GR 系红证不修 |
| **N13**（buglist:506） | PIE drain_game_events panic，Mac 100% 复发 | 绕行+记数（T11-T16 口径）：数值断言 panic 后重试读回；PIE 腿不依赖编辑器存活时序 |
| **N12**（buglist:501） | BRP 实体域界 | 游戏侧全用 bevy 原生 `world.query`/`world.get_components`；编辑器侧 operator 按名、引擎组件查询用原生方法（t16 双口径） |
| **A6**（buglist:455） | watcher flaky+磁盘高压家族 | 知悉：本任务无 watcher 依赖；门前清磁盘照旧；integration 唯一预期红=A6 定案口径隔离绿 |
| **A10**（buglist:465） | PIE 指针转发缩放布局 | 本任务**零指针交互主链**（画质配置全 operator 直达）——A10 咬不到 |
| **R12**（buglist:78） | 灯光投影开关无效果 | GR6 抽查腿+记档，不吸收 |
| **A12/A13/A11/A5/A3/A4/N10/N11/W1-W3** | 渲染提取/缓存/rebind/pie_log/standalone/基线/PIE 冻结/Inspector 驱动/视口性能域 | 无直接交集；W3（派生材质缓存）与本域相邻但视口模式域，不动 |
| 其余 | R/Y/W 系均为 prefab/brush/chrome/键位/地形/CSG 域 | 无动作 |

> 如实报告：graphics/画质域在 buglist 只有 R12（开放）与 W4/A7（截图工具债）三条沾边
> ——画质应用链路是功能 #8 刚交付的成品域，用户还没有可踩出「Play 不生效」bug 的
> 验收通路（GR1/GR2 挡在证据层）。T19 缺陷主体是本方案新发现的 GR1-GR8。

---

## 二、验收矩阵设计

**三铁证×通道=16 格主矩阵**。断言通道缩写：H=headless（tests/viewport/graphics_panel.rs
8 件+surface 测试族+stage scene_environment）、R=真机编辑器 BRP 15703（operator+原生
组件查询+`jackdaw/screenshot`）、G=游戏 BRP 15702（bevy 原生 `world.get_components`，
N12 口径）、PX=像素证据（编辑器=viewport 直拍 % 形态；游戏窗口=`screencapture`+sips
裁剪+MD5 变/不变）、FS=盘面（SHA/文件清单/config 目录）、EXPORT=staged 包
（manifest+SHA+staged 进程 BRP）。

**前置腿 L1 的两个前提态**（全矩阵共用）：①fixture 场景带 `Environment`（prep 注入：
`environment.set sky.enabled=true`+`post.enabled=true`——sky 保证画面有高亮部，
bloom/曝光红绿有可变素材；值落盘 scene.bsn）；②编辑器视口处于 High 默认档
（post_processing/bloom opt-in——`ViewportQuality::default()=High`，事实四）。

### 铁证①：场景级曝光/Bloom/AA 在 Play+导出生效

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| 编辑器视口 | M1 | `environment.set post.exposure=13` → R 读视口相机 `Exposure.ev100==13` +PX 红绿（像素 % 变化>阈值）→回 9.7 复原 | H 锚在案（surface:995）+⚠️R 真机腿未跑 |
| 编辑器视口 | M2 | `environment.set post.bloom_intensity=0.8` → R 读 `Bloom{intensity==0.8}` +PX 红绿（feature-08 先例 77.11%） | ⚠️R（Mac 通道首次） |
| 编辑器视口 | M3 | **AA 边界格**：`environment.set post.antialiasing=taa` → R 断视口相机**无** `TemporalAntiAliasing`（opt-out 恒真=边界本身）+`Environment.post.antialiasing==Taa` 文档值在 | H 锚（surface AA 测试族）+⚠️R |
| PIE | M4 | `pie.play_current` → G 读游戏相机 `Exposure/Bloom/Tonemapping` 逐字段==M1/M2 所设值 +PX 流送帧红绿（GR8 探针后定去留，决策 4） | 🔴GR1 前置；N13 绕行记数 |
| direct run | M5 | `cargo run`（15702）→ 同 M4 断言（数值逐字段相等=「一致性」的正主格） | 🔴GR1 前置 |
| 导出 staged | M6 | `game.export` → export_wait（staged scene.bsn SHA==工程）→ staged 进程启动 → 同 M4 断言 + manifest 含 scene.bsn | 🔴GR1 前置（T12 格 9/T16 L6 形态复用） |
| AA 三站 | M7 | `post.antialiasing=smaa` → PIE/direct/staged 三站 G 断游戏相机 `Smaa` 在+`Msaa::Off`；回 Keep → 组件退场 | 🔴GR1 前置（事实四：唯游戏通道生效） |
| 横切·往返 | M8 | M1-M2 值 → `scene.save` → FS 断 scene.bsn 含新值 → 重开 → R 再读一致（「编辑→保存→重开→Play→导出」全链的编辑器半边） | H 锚（stage:171,219）+⚠️R |

### 铁证②：editor 偏好不污染游戏（负向格）

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| 文档层 | M9 | **SHA 腿**：记 scene.bsn SHA → A 区全操作（preset Low/render 50/AA smaa/SSAO ultra on/sharpen on 0.8/fog off）→ FS 断 SHA 不变 → `scene.save` → **SHA 仍不变**+无脏标记弹窗 | ⚪GR2 前置；T1 补 headless 守卫同型 |
| 导出层 | M10 | **包腿**：A 区改动前后各 `game.export` 一次 → FS 断 staged `assets/scene.bsn` SHA 相等+manifest 文件清单 diff 为空 | ⚪GR2 前置（物理不可能带入 viewport.json 的架构证明） |
| 游戏层 | M11 | **数值腿**：A 区两态（AA=TAA+SSAO Ultra vs AA=Off+SSAO off）下各 direct run → G 断游戏相机组件矩阵两态**逐字段恒等**（AA 组件只随场景走） | ⚪GR2 前置；与 M5 同腿复用 |
| 配置层 | M12 | **隔离腿**：`JACKDAW_CONFIG_DIR=<scratch>` 启动编辑器 → A 区改动 → FS 断 viewport.json 落 scratch、工程树零 viewport.json；第二次启动（无 override）读到用户级原值=「per user」语义活证 | ⚪GR2 前置（paths.rs:26-40 测试缝） |

### 铁证③：GI 保持禁用说明（回归格）+横切

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| 面板回归 | M13 | GI 行 `InteractionDisabled`+tooltip 含 Solari/替代项（H 复跑）+真机 PX（置灰行+tooltip 展开） | ✅H 在案+⚠️PX |
| 全链缺席 | M14 | 全程 warn 扫描零 `solari/ray query` 命中+workspace features 无 solari（静态复核进报告） | 脚本常备腿 |
| 横切·对照 | M15 | **无 Environment 对照态**（GR7）：fixture 删 Environment → 四通道相机组件=bevy 默认恒等+面板空态提示可见 | H 锚（空态 hint 三态）+⚠️G |
| 横切·存活 | M16 | 每相每腿后 BRP 活性+pid（「不崩」机械化口径）+warn 扫描（`tonemapp|bloom|exposure|solari|UnresolvedTypes|panicked`，逐条归属） | 脚本常备腿 |

**矩阵统计**：🔴 前置 4 格（GR1×M4-M7）｜⚪ 前置 4 格（GR2×M9-M12）｜✅H 有锚 3 格
（M13/M15 半格/M8 半格）｜⚠️ 真机腿缺口 9 格。T1 清源（负向守卫+GR8 探针），
T2 落判。

---

## 三、真机腿清单（Mac，bash+curl+jq；T2 集中跑）

fixture 工程=`jd new` 出 `/Users/zhanglinbo/workspace/loop-mac/t19-graphics`（T15/T16
决策同款；`jackdaw_remote` 两行注入+lock 刷新+暖编=t16-live.sh prep 相 :458-469 原样）。
**prep 注入**：`write_scene_bsn` 在模板场景上加 `#Environment` 实体——
`jackdaw_scene_types::environment::Environment`（sky.enabled=true+post.enabled=true+
bloom_intensity=0.8 或腿内 operator 写，二选一按决策 3）；flow start_scene 指 scene.bsn
（游戏三站都要它）。流程脚本 `loop/qa/t19-live.sh`（t16-live.sh 形态全量复用+像素助手
族从 t18-live.sh 搬：`png_pixels_md5`/`sips` 裁剪 MD5/% diff 的 python3 版）。

| # | 腿 | 通道 | 为什么必须真机 |
|---|---|---|---|
| L1 | prep+boot+前提态：fixture/注入/暖编/编辑器开场景/environment.set 种子值/视口 High 档确认（`viewport.quality.preset high`） | R+FS | 全矩阵的前提态；opt-in 面是 M1/M2 像素红绿的先决 |
| L2 | M1/M2/M3 编辑器三件套：exposure/bloom/AA 边界各一腿（组件读回+像素红绿+复原） | R+PX | 视口渲染是视觉结论；像素 % 先例（feature-08）复刻 |
| L3 | M4 PIE parity：PIE→G 读回三组件逐字段==种子值+流送帧红绿（GR8 探针并行）+N13 记数 | G+PX | 游戏进程行为；「Play 生效」正主 |
| L4 | M5 direct parity：direct_run→同 L3 断言 | G | 与 PIE 互相印证（同二进制不同启动路径） |
| L5 | M6 export parity：export_wait（SHA 判据）→staged 启动→同断言+manifest 行 | EXPORT+G | 「导出生效」正主；staged 独立进程 |
| L6 | M7 AA 三站：smaa/Keep 两态×三站组件矩阵 | G | AA 唯游戏通道（编辑器视口 opt-out 是 M3 已断的边界） |
| L7 | M9-M12 负向三腿：SHA/包/游戏数值恒等/CONFIG_DIR 隔离 | R+FS+G | 「不污染」是负向断言，只能真机+盘面 |
| L8 | M13/M15 GI 回归+空态对照：面板截图+tooltip+删 Environment 对照站 | R+PX+G | 「保持」的回归格；对照态数值 |
| L9 | M8 往返+像素证据族归档：save/reopen 全链+每通道 before/after PNG+MD5/% 表落 `loop/t19-live/` | R+FS+PX | 验收通用交付铁证（编辑→保存→重开→Play→导出）的编辑器半边+证据归档 |
| L10 | M14/M16 warn 扫描+存活腿+viewport 菜单回归（`viewport_settings_menu` 四档行为不变——feature-08 回归面复跑） | R | 常备纪律+功能 #8 既有面不回归 |

---

## 四、分任务拆解（T1/T2/T3）

### T1「负向守卫+探针清源轮」（建设小头：GR2 守卫+GR8 探针+fixture prep；决策 3/4/6/8）

1. **首步探针（半日级）**：①GR8——headless 或真机单腿定案「PIE 流送帧是否带 dress
   组件」（读 `pie_frames.rs` 捕获相机的组件链+真机流送帧红绿对照）；②决策 3 落地
   形态定案——模板 scene.bsn 手写 `#Environment` 实体 vs prep 用 operator 写后存盘
   （后者同时验证 B 区写入链，倾向后者）。
2. **GR2 headless 守卫**（tests/viewport/ 新一件）：editor_test_app 开场景 → 跑全套
   `viewport.*` operator → `scene.save` → 断文档字节与改前 SHA 相等+undo 栈零条目
   （既有锚 :245-249 的盘面扩展）。
3. **像素助手入库**：`loop/qa/t19-live.sh` 携带 `png_pixels_md5`+`sips` 裁剪+%
   diff（python3 纯 stdlib）三助手（t18-live.sh 形态搬运+pixdiff.ps1 语义的 python 版）。
4. **GR3/GR7 book 注记草稿**（随 T3 落盘）；GR6 抽查腿脚本位预留。
5. **门禁**：fmt/clippy 全仓/单测/集成（graphics_panel 8 件+surface 测试族回归全绿）。

**验收标准**：负向守卫红绿在案（先写守卫、人为让 A 区写文档的假实现不现实——守卫以
「现状直绿」+断言消息自证覆盖面）；GR8 探针有结论（流送帧忠实/不忠实两案均进决策 4
回落路径）；fixture prep 全绿。

### T2「真机矩阵轮」（验收主任务：M1-M16/L1-L10；决策 1/2/5/6/7）

1. L1-L10 全腿；每腿独立探针开场（t12t3 形态）；红态先行归档（如 AA 三站的 Keep 态、
   opt-out 关闭态）——红证归档纪律（T16 首例）延续。
2. 像素证据全归档 `loop/t19-live/`（每通道 before/after PNG+MD5/% 表）。
3. 缺陷只记不修：新发现按 GR 系续编（GR9 起），红证归档 `loop/reports/t19*/`。
4. QA 报告：16 格矩阵逐格判定+L 腿全证据+用户 30 秒清单草稿（拖曝光滑条看 Play 变、
   拨视口预设看游戏不变、悬停 GI 行）。

**验收标准**：M4-M7（Play/导出生效）全绿=铁证①；M9-M12（不污染三腿）全绿=铁证②；
M13/M14（GI 保持）全绿=铁证③；M16 存活腿全过；四门禁绿。

### T3「终验 + 文档」

1. 16 格终态复跑+重点腿复跑（L5/L6/L7）。
2. book 扩节（`book/src/user-guide/graphics-panel.md`，不另立新章）：「Play 与导出」
   一节（场景 Environment 如何走到游戏相机——同一插件两侧同链/四通道一致性结论/
   场景 AA 只在游戏通道生效的边界/视口 opt-out 语义复述）、**「编辑器偏好与游戏」
   一节**（viewport.json 用户级/三不变边界/GR3 注记「场景 AA 走 Inspector」/GR7 开箱
   空态）；GI 节原样保持（回归通过即不动）；`play-in-editor.md`/`assets.md`（如涉）
   交叉引用一句话。
3. buglist 处置（预期无打钩；GR6 若真踩 R12 形态则回写该票证据）、roadmap 勾选 T19、
   台账记行。
4. 终验门：全量门（fast/integration/doctests/docs——日志全文复核；integration 唯一
   预期红=A6 定案口径隔离绿，照既往口径）。

---

## 五、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **「一致性」的像素判据形态** | A=**数值轨主断言+像素轨通道内红绿**：跨通道一致由组件逐字段相等背书（同一组件类型同一字段，BRP 读回），像素只证「该通道画面确实随值变」（feature-08 % 形态+T18 MD5 形态）。B=跨通道逐像素相等：编辑器视口直拍 vs 游戏窗口截图逐像素 diff——**否决**：两通道窗口尺寸/渲染目标/相机位姿/TAA 时间态/窗口 chrome 全不同，任何阈值都会产假红假绿，且「逐像素相等」从来不是验收词的字面（「生效」≠「画面逐字节相同」） | **A**；像素轨预算=每通道一对红绿+MD5 归档，不设跨通道像素相等格 |
| 2 | **场景级 AA 授权面（GR3）** | A=**不加面板行**：验收词字面是「生效」不是「面板可调」；功能 #8 交付口径 B 区 4 行是设计裁定（场景侧 AA 面板化在 feature-08 backlog）；本任务零 UI 改动=定性表成立。B=补一行 AA segmented（`environment.set post.antialiasing`）：面板更完整，但破坏「面板=成品、本任务零产品改动」的定性，引入 UI+测试+book 三面改动，验收句无此字面 | **A**；B 记 open-challenges 一句话（「Graphics 面板 Scene 区补 AA/MSAA 行」） |
| 3 | **fixture 的 Environment 注入形态** | A=**prep 用 operator 写后存盘**（`component.add Environment`+`environment.set` 种子值+`scene.save`）：顺带把 B 区写入链当 prep 跑了一遍（dogfood），scene.bsn 由编辑器自己写出=最真实载体。B=手写 scene.bsn 文本（t14/t16 `write_scene_bsn` 形态）：幂等可控，但 Environment 组件字段多、手写易与 stamp/格式漂移打架，且绕过了写入链 | **A**（prep 腿即 L1 的一部分；幂等性用「值已对则跳过」守卫）；B 作为 A 受阻回落 |
| 4 | **PIE 通道的视觉证据（GR8）** | A=**探针定案后两案分流**：流送帧忠实→M4 保留 PX 红绿；不忠实→M4 降级纯数值+GR8 记档（游戏窗口 truth 以 direct run 为准，PIE 只作数值 parity）。B=PIE 一律只走数值（不做探针）：省半日，但丢失「PIE 画面与游戏一致」的面级证据，且 GR8 悬置 | **A**（探针在 T1 首步，成本半日内）；N13 绕行纪律照旧（数值断言 panic 后重试） |
| 5 | **负向格的强度（M10 导出包腿）** | A=**manifest+scene.bsn SHA 两点对比**（改 A 区前后各导一次）：直接证明「包内容与 A 区无关」。B=只断 staged scene.bsn SHA（不重导）：省一次 export（release 冷编风险窗），但「包面不变」只剩推理。C=全包哈希清单 diff（manifest.files 全量 SHA 比对）：最强证据，export-manifest 已带 SHA-256 字段（T07 交付），对比成本≈零 | **C**（manifest 全清单 diff——字段现成，加腿不加窗；A 作为 manifest 结构意外时的回落） |
| 6 | **A7 截图 flake 缓解形态** | A=**脚本五招自守**（重叠表：request 键/rm -f/size 验证/相邻两拍 flake 探针/screencapture 降级）：零前置。B=先修 A7 的截图通道半边再开 T19：画质任务像素证据密度全任务史最高，先修收益大；代价=A7 是跨任务工具票（含对话框/行定位族），整票前置拖节奏，且截图半边修复方案未立项 | **A**；T2 真踩不可绕（如反复 md5 相等假红）→按 MCP 优先原则现场立项「截图通道 flake 探针」小票，不整体前置 |
| 7 | **headless 游戏侧 e2e 锚（GR1 的机制层半边）** | A=**补一条 runtime 测试**（T15 `animation_scene_load.rs` 转活先例）：模板形工程+带 Environment 的场景文档→JackdawPlugin→断游戏相机组件被 dress——把「机制在场」钉进 CI，真机矩阵烂了也有锚。B=不补，只靠真机矩阵：CI 视角持续零覆盖（GR1 只被真机证据覆盖一次） | **A**（预估半日内：surface 测试族已有 editor 形态可改造，runtime 侧只差 scene 文档装载+`render` feature 门——**注意 feature 门教训**：挂进 integration 档需显式 feature 行，否则 T15 AN2 死件复刻） |
| 8 | **文档落点** | A=**graphics-panel.md 扩两节**：面板章已有双区语义与 opt-out 节，补「Play 与导出」「编辑器偏好与游戏」顺理成章。B=新章「graphics-parity」：割裂（面板章已覆盖边界语义）+SUMMARY 膨胀 | **A**；GI 节回归通过则原文不动（「保持」的字面兑现） |

小定案（主控可否决）：缺陷编号 GR1-GR8（新发现自 GR9 续）；真机腿编号 L1-L10；
矩阵格 M1-M16；fixture 工程 `/Users/zhanglinbo/workspace/loop-mac/t19-graphics`；
流程脚本 `loop/qa/t19-live.sh`；报告目录 `loop/reports/t19*/`；证据目录
`loop/t19-live/`；book 扩节 `book/src/user-guide/graphics-panel.md`；种子值=
exposure 13.0/bloom_intensity 0.8/antialiasing smaa（红绿余量按 feature-08 先例）。

---

## 六、风险与回滚

| 风险 | 概率 | 缓解 |
|---|---|---|
| **PIE N13 panic 扰动 L3** | 高（Mac 100% 复发） | 绕行+记数（错误处理器捕获编辑器存活）；G 通道断言 panic 后重试；L3 的 PX 腿按决策 4 可降级 |
| **截图假证据（A7 flake 假绿/假红）** | 中-高（像素证据密度最高的一役） | 决策 6 五招全量入脚本；判「红」前必过相邻两拍 flake 探针；每通道红绿值与 feature-08 先例量级对照（bloom 红绿若 <5% 即可疑） |
| **W4 采集相机滞留污染后续像素腿** | 中 | 编辑器分相（每相重启）+每腿 BRP 活性断言；gizmo 集体消失即记 GR 红证并重启编辑器续跑 |
| **A9 游戏 BRP 空响应** | 中 | gbrp 重试+settle+小响应体（t16 全套）；staged 相先 `sleep 10`+`game_ready` 再采样（t16 L6 两段 settle 先例 :1123-1128） |
| **staged release 冷编长/资源窗** | 中 | export_wait 预算 1500s（t16 原样）；门前清磁盘（A6 家族）；export 只跑两次（M10 需要）——预算单列 |
| **曝光/bloom 红绿素材不足（画面无高亮部）** | 中 | prep 把 `sky.enabled=true`（天空+太阳盘=稳定高亮部）；红绿阈值按 M2 首腿实测校准后钉进脚本 |
| **TAA/管线切换首帧噪声污染像素对** | 中 | GR4 纪律：切换后 settle≥2s+首拍丢弃；screenshot 内置 SETTLE_FRAMES=90 兜底 |
| **`world.get_components` 对游戏 CameraRig 相机的可达性（N12 域界/组件名拼写）** | 中 | L3 首腿先 `world.query` 按 `Camera3d` 组件过滤枚举实体（t16 `gid` 同法）；组件名用全 generic 路径（A8 教训：全路径限定） |
| **A 区改动误触脏标记/保存弹窗（打断 L7 SHA 腿）** | 低 | headless 侧已有「A 区零 undo」锚；真机 L1 先验一次「viewport preset→无脏弹窗」；dialog.answer 兜底助手照搬 |
| **Mac debug 无 RUST_BACKTRACE** | 确定 | 全程不设（T11-T3 口径）；panic 形态证据=日志消息签名 |
| **门链与编辑器/游戏同窗互踩** | 中 | T12-T3 §九-7 纪律：门链单独跑 |
| 回滚 | — | **产品代码预期零改动**（T1 只有测试+脚本+探针；GR2 守卫=tests 一件、GR7 锚=runtime 测试一件、其余全在 loop/qa+loop/plans）——回滚=删两件测试+脚本；零场景格式变更、零协议变更、零 fork 改动、零 UI 改动。建设面最小化由定性表保障（应用链路无一需要新机制） |

---

## 七、与 T01-T18 已建设施的衔接

1. **功能 #8（画质面板）=本任务的交付基座**：双区 operator 面/undo 语义/提示三态/GI
   置灰行全部继承，8 件 headless 锚回归必跑；其终验 ⚪（Play 泄漏专项/TAA pixdiff/
   SSAO 档位 pixdiff）在本任务 M 系全部收口。
2. **T06（PIE 隔离）=Play 通道的底座**：`pie.play_current` 三态策略/temp 副本/Stop 还原
   链直接复用（L3）；N13 绕行纪律照旧。
3. **T07（导出）=导出通道的底座**：`game.export`/export-manifest.json（SHA-256 全清单
   =M10 决策 5-C 的字段来源）/`jackdaw/export` 轮询（export_wait）。
4. **T12/T14/T16（四通道 parity 先例）**：T12 格 9「编辑器改→Save→Play 生效→staged
   独立启动生效」、T14 L6 导出五点链、T16 L6 staged 三音 parity——T19 的 L5 是同形态
   在画质域的第三次复用；T16 的 gbrp/export_wait/direct_run 助手原样搬。
5. **T15（AN2 教训）**：游戏侧端到端被 feature 门裁掉的死件教训→决策 7-A 的 feature
   行显式化；「反转读法」第五次适用。
6. **T18（像素证据手艺）**：`png_pixels_md5`+sips 裁剪+红证归档纪律+A6 单触发源纪律
   全量继承；T18 的 A12（GPU 面冻结）是渲染侧邻域票，与本任务「组件值正确但画面不
   变」的假红鉴别相关（如遇先查 A12 同族）。
7. **T03（脏指纹）/T04（原子写）**：L7 SHA 腿的比对对象与场景落盘同链；saved_doc_hash
   全指纹是 M9「无脏标记」断言的机制底座。
8. **对 T20 的奠基**：T20 示例游戏「主要靠编辑器配置完成」——本任务的四通道画质 parity
   是其验收面的先例与 fixture 底座；GR3 的「面板补 AA 行」open-challenges 若被 T20
   需要，届时再立项。
9. **分支与行号基线**：本方案行号基于 main 68df502f；T19 从 main 拉
   `loop/t19-graphics-parity`；loop/ 目录随 git 旅行（2026-10-28 迁移后），上游 PR 时
   按需剔除。

---

## 八、耗时预估

| 段 | 预估 | 大头 |
|---|---|---|
| T1 | 0.5-1 天 | GR8 探针+GR2 headless 守卫+GR7 runtime 锚（若裁决策 7-A）+像素助手入库+fixture prep |
| T2 | 1-1.5 天 | fixture 全套+`t19-live.sh`+L1-L10（PIE/direct/staged 三站×两态+负向三腿）+像素归档+红证 |
| T3 | 0.5 天 | 16 格终态复跑+book 扩两节+全量门+收尾 |
| 合计 | **2-3 天** | 视决策 4/7 落地与 staged 导出窗稳定性浮动 |
