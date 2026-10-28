# 功能 #8 实施方案：画质设置面板（Graphics 面板）

> 多 Agent 开发循环 · 策划产物（只写方案，不含代码实现）
> 日期：2026-10-22 · 策划：资深 Bevy 图形工程师 + 引擎设计师 Agent
> 选题依据：用户原话「加一个能让我调整画质设置，比如实时GI、TAA、bloom等功能的编辑面板」——即一个横跨抗锯齿 / 后处理 / 阴影 / 观感特性的参数级画质控制面板，所见即所得。
> 调研方法：rg + Read。bevy 源码锁定 `~/.cargo/git/checkouts/bevy-50d7e162b728c6c6/c9c397b`（下文 bevy 路径均相对其 `crates/`）；未运行任何 cargo 命令。

---

## 1. 范围与不做

**做**（判定依据见 D1–D3）：

1. **新 dockable 面板「Graphics」**（窗口 id `jackdaw.graphics`，注册进 `WindowRegistry`，命令面板可搜可开）；
2. **A 区「Viewport（编辑器预览）」**：editor-only、即改即生效、存用户级 `viewport.json`、不进 undo——preset 四档、render scale、抗锯齿（Off/FXAA/**SMAA(新)**/TAA）、SSAO 开关+**质量档(新)**、太阳/点光阴影开关、雾开关、**CAS 锐化(新)**；
3. **B 区「Scene（随场景保存）」**：tonemapper、曝光 EV100、bloom 强度/阈值——全部是**既有 `environment.set` operator 的 UI 皮**（写 `Environment.post.*`，单条 undo，`.bsn` 持久化）；
4. **「Realtime GI」置灰项 + tooltip**（bevy 实时 GI = Solari，实验性、需硬件光追、独立 cargo feature，jackdaw 未启用——诚实标注，见 D1-实GI）；
5. 预览可见性联动提示：B 区效果在视口的可见性受 A 区 post-processing/bloom 开关钳制时，面板显示一行提示。

**不做**（首版明确排除，归 backlog，见 D6）：

- **接入 Solari 实时 GI**（experimental + `EXPERIMENTAL_RAY_QUERY` 硬件光追 + 逐 mesh `RaytracingMesh3d` 组件，接入面是独立特性级工作）；
- DoF（景深）调参、MotionBlur、Volumetric fog / FogVolume 体积雾面板化、SSR（**要求 deferred 渲染**，jackdaw 视口 forward，不适用）、DLSS（`dlss` cargo feature + NVIDIA 硬件）、SSAO 高级参数（radius/thickness）、B 区 vignette/调色（grading）、场景侧 preset 一键档位、阴影贴图精细尺寸（保留现有三档）；
- **面板直接写游戏相机实体组件**（个别相机差异化走 Inspector `component.add`，`.bsn` 已可存这些组件——见 D3-持久化，是后门不是面板职责）；
- 废弃/改动 viewport 工具栏的设置菜单（与新面板双入口、同一 resource，天然一致）。

### 0. 现状一句话

画质「两层架构 + 全部底层管线」**已经存在**：视口层（`src/viewport_settings.rs` 的 `ViewportSettings` + `src/viewport_quality.rs` 的 `dress_viewport_cameras` 插拔 Fxaa/Smaa/TAA/SSAO 组件、opt-out 场景环境、改阴影贴图 resource）管 editor-only 预览；场景层（`crates/jackdaw_scene_types/src/environment.rs` 的 `Environment.post` 完整参数模型 + `crates/jackdaw_surface/src/environment.rs` 的 `dress_the_cameras` 映射到 bevy 相机组件）管随场景保存的观感。**缺的只是：① 一个参数级的面板 UI（现在视口菜单只有档位开关）；② 视口层 3 个缺口（SMAA 选项、SSAO 质量档、CAS 锐化）。**

---

## 2. 设计结论 D1–D6（全部带代码证据）

### D1. bevy main 画质特性清点（锁定 checkout 逐个核实）

**总结论：可进面板的「组件插拔式」特性 11 项齐备且全部支持运行时热切换（per-view 组件，插入/移除下一帧生效）；实时 GI 存在但名为 Solari——experimental、硬件光追、独立 cargo feature、jackdaw 未启用，MVP 不可提供。**

#### D1-a. 抗锯齿（`crates/bevy_anti_alias/`）

| 特性 | 组件 | 挂载 | 默认 | 热切换 | 证据 |
|---|---|---|---|---|---|
| TAA | `TemporalAntiAliasing { reset: bool }` | 相机；`#[require(TemporalJitter, MipBias, DepthPrepass, MotionVectorPrepass)]` | `reset: true`（首帧重建历史） | 即时 | `src/taa/mod.rs:112-131`；要求 `Msaa::Off`（`:102` 文档、`:153-156` 运行时 warn+跳过） |
| SMAA | `Smaa { preset: SmaaPreset }` | 相机 | `SmaaPreset::High`（另有 Low/Medium/Ultra） | 即时（pipeline 特化，首 1-2 帧延迟） | `src/smaa/mod.rs:82-122` |
| FXAA | `Fxaa { edge_threshold, edge_threshold_min }` | 相机 | `Sensitivity` 各默认 | 即时 | `src/fxaa/mod.rs:58` |
| CAS 锐化 | `ContrastAdaptiveSharpening { enabled, sharpening_strength, denoise }` | 相机（2D/3D 皆可） | `enabled: true, sharpening_strength: 0.6` | 即时（`enabled=false` 或强度 0 时 extract 直接跳过，`:87-89`） | `src/contrast_adaptive_sharpening/mod.rs:37-64` |
| DLSS | `Dlss`（泛型 `Dlss<F>`） | 相机 | — | — | `src/dlss/mod.rs:205`；**cargo feature `dlss` 门控**（bevy_internal `Cargo.toml:102`），MVP 排除 |

#### D1-b. 后处理（`crates/bevy_post_process/`）

| 特性 | 组件 | 挂载 | 默认 | 热切换 | 证据 |
|---|---|---|---|---|---|
| Bloom | `Bloom { intensity, prefilter: BloomPrefilter { threshold, .. }, .. }` | 相机；`#[require(Hdr)]` | `Bloom::NATURAL`：`intensity 0.15`，prefilter threshold 0.0 | 即时 | `src/bloom/settings.rs:30-189` |
| Vignette | `Vignette { intensity, radius, smoothness, .. }` | 相机 | `intensity 1.0, radius 0.75, smoothness 5.0` | 即时 | `src/effect_stack/vignette.rs:29-75` |
| DoF | `DepthOfField { mode: Bokeh/Gaussian, focal_distance, sensor_height, aperture_f_stops, .. }` | 相机；`#[require(TonemappingPass)]` | `mode: Gaussian`，sensor 18.66mm | 即时 | `src/dof/mod.rs:76-167` |
| MotionBlur | `MotionBlur { shutter_angle, samples }` | 相机；`#[require(MotionVectorPrepass, TonemappingPass)]` | `shutter_angle 0.5, samples 1` | 即时 | `src/motion_blur/mod.rs:73-116` |

#### D1-c. 屏幕空间光照（`crates/bevy_pbr/`）

| 特性 | 组件 | 挂载 | 默认 | 热切换 | 证据 |
|---|---|---|---|---|---|
| SSAO | `ScreenSpaceAmbientOcclusion { quality_level, radius, constant_object_thickness }` | 相机；`#[require(DepthPrepass, NormalPrepass)]` | `quality_level: High`（Low/Medium/High/Ultra/Custom），radius ≈0.7285，thickness 0.25；官方建议配 TAA 降噪 | 即时 | `src/ssao/mod.rs:111-182`；文档注明 WebGL2/WebGPU(浏览器) 不支持——桌面 wgpu(Vulkan/DX12) 可用（jackdaw 视口已在用，见下） |
| SSR | `ScreenSpaceReflections { min/max_perceptual_roughness, thickness, linear_steps, .. }` | 相机；`#[require(DepthPrepass, DeferredPrepass)]` | — | — | `src/ssr/mod.rs:52-130`；**「currently require deferred rendering in order to appear」（`:53-61`）**，jackdaw forward 渲染，不适用 → backlog |

#### D1-d. 调色 / 曝光 / 抖动

| 特性 | 类型 | 挂载 | 默认 | 证据 |
|---|---|---|---|---|
| Tonemapping | enum `Tonemapping`（None/**Linear**/Reinhard/ReinhardLuminance/AcesFitted/AgX/SomewhatBoringDisplayTransform/**TonyMcMapface**/BlenderFilmic/KhronosPbrNeutral） | 相机组件 | `TonyMcMapface` | `crates/bevy_render/src/view/mod.rs:277-336`；注意 bevy main 比 jackdaw 的 `Tonemapper` enum（`jackdaw_scene_types/src/environment.rs:207-220`）**多一个 `Linear` 变体**（backlog：jackdaw enum 补齐） |
| 曝光 | `Exposure { ev100 }` | 相机组件 | 预设常量 `EV100_BLENDER = 9.7`（与 jackdaw `PostProcess::default().exposure = 9.7` 一致） | `crates/bevy_camera/src/camera.rs:227-277` |
| 去色带 | enum `DebandDither` | 相机 | `Camera3d` 默认 require `DebandDither::Enabled` | `crates/bevy_core_pipeline/src/core_3d/mod.rs:104` |

#### D1-e. 阴影（`crates/bevy_light/`）

| 特性 | 类型 | 挂载 | 默认 | 热切换 | 证据 |
|---|---|---|---|---|---|
| 太阳阴影贴图 | `DirectionalLightShadowMap { size }` | **全局 Resource** | `size: 2048`；非 2 的幂被 `validate_shadow_map_size` 自动纠正 | 即时 | `src/directional_light.rs:191-214` |
| 点光阴影贴图 | `PointLightShadowMap { size }` | 全局 Resource | `size: 1024` | 即时 | `src/point_light.rs:178-191` |
| 阴影边缘滤波 | enum `ShadowFilteringMethod`（Hardware2x2/**Gaussian**/Temporal） | 相机组件 | `Gaussian` | 即时 | `src/lib.rs:284-310` |

#### D1-f. 体积光 / 雾

- `VolumetricFog { step_count: 64, ambient_color, ambient_intensity, jitter }`（相机）+ `VolumetricLight`（挂方向光，出光轴/god rays）+ `FogVolume`（体积实体）——`crates/bevy_light/src/volumetric.rs:14-120`。组件插拔式、即时；backlog（jackdaw 场景已有线性/指数 `DistanceFog` 模型，见 D2）。

#### D1-g. 实时 GI（重点核实，诚实结论）

- **bevy main 有实时 GI：`bevy_solari` crate**（`crates` 目录实存）。`SolariPlugins`（plugin group）= `SolariLightingPlugin`（raytraced 直接+间接光照）+ `RaytracingScenePlugin`（BLAS 构建）；相机组件 `SolariLighting`（`src/realtime/mod.rs:119`，含 reSTIR 参数），mesh 实体组件 `RaytracingMesh3d`；**标注 experimental**（`src/lib.rs:29` "An experimental set of plugins"），要求 `WgpuFeatures::EXPERIMENTAL_RAY_QUERY | BUFFER_BINDING_ARRAY | ...`（`lib.rs:49-57`，即硬件光追，DX12/Vulkan RTX 级）；
- **它是 bevy 的 optional cargo feature**（`crates/bevy_internal/Cargo.toml:291` `bevy_solari = ["dep:bevy_solari", "bevy_pbr"]`，默认关），**jackdaw 未启用**（全仓 Cargo.toml 搜 `solari` 无命中）；
- 烘焙类替代（存在但非实时）：`Lightmap` 组件（`crates/bevy_pbr/src/lightmap/mod.rs:1-6` 文档明说需外部烘焙器 addon「The Lightmapper / bevy-baked-gi」）；irradiance volumes（`bevy_pbr/src/light_probe/irradiance_volume.rs`，烘焙辐照体积）；
- **jackdaw 自己的观感替代已就位**：`ReflectionProbe` + 六面烘焙（`src/probe_bake.rs:1-16`）、SSAO（视口已可开）、天空环境反射（`Environment.ambient.reflections = Reflections::Sky`，`jackdaw_surface/src/environment.rs:543-556`）、体积光（bevy 组件，见 D1-f）。

**⇒ 结论：MVP 不可提供实时 GI；面板显示置灰项 + tooltip 指明 Solari 状态与替代项（推荐显示而非隐藏——用户点名要，直接消失更困惑）。**

#### D1-h. jackdaw 侧现状（这些组件哪些已在用）

- `src/viewport_quality.rs:9-27` 已 import 并由 `dress_viewport_cameras`（`:120-176`）在**视口相机**（`MainViewportCamera`）上插拔：`Fxaa` / `Smaa`（现状只删不插，`:144-146`）/ `TemporalAntiAliasing`（含 `TemporalJitter`/`MipBias`/`MotionVectorPrepass` 保管）/ `ScreenSpaceAmbientOcclusion`（含 `NormalPrepass` 保管）；阴影贴图 resource 由 `follow_shadow_settings`（`:196-218`）写入；渲染缩放改 render target 尺寸（`:288-312`）；
- 场景层 `jackdaw_surface/src/environment.rs` 的 `dress_the_cameras`（`:467-563`）把 `Environment.post` 映射到**所有场景 `Camera3d`**：`Tonemapping`/`Exposure`/`ColorGrading`/`Bloom`/`Vignette`/`Fxaa`/`Smaa`/`TemporalAntiAliasing`+`Msaa`/`ShadowFilteringMethod`（`:678-779`），并以 `UndressedCamera` 保管/恢复相机原状态（`:94-109`）；
- 视口相机本身：`Camera3d`（默认 HDR，Bloom 可直接生效）+ `OrderIndependentTransparencySettings`（强制 `Msaa::Off`，`src/viewport.rs:359-369` 注释言明）+ `ScreenSpaceTransmission` 已开（`:351`）。

### D2. 与现有配置的边界：新面板 = 「双区聚合视图」，不接管、不另立、不扩展 environment 字段

**结论：画质数据模型零新增层级——A 区（视口预览）走既有 `viewport.*` operator 家族 + `viewport.json`；B 区（场景画质）是既有 `environment.set` 的 UI 皮。新面板只补「参数级 UI + 视口层 3 个缺口」，两侧各写各的存储，无双写。**

证据链：

1. **场景级 post 模型已完备**：`Environment.post`（`PostProcess`，`jackdaw_scene_types/src/environment.rs:271-329`）已有 tonemapper/exposure/post_exposure/contrast/saturation/hue/temperature/tint/bloom_intensity/bloom_threshold/vignette×2/antialiasing(FXAA/SMAA/TAA)/msaa/shadow_filtering 全套字段；`environment.set` 按字段路径写入（`src/environment_ops.rs:127-174`，`reflect_path_mut` 通用解析 `:177-233`），测试已覆盖 `post.bloom_intensity` / `post.antialiasing=Smaa` / `post.shadow_filtering=Gaussian`（`tests/stage/scene_environment.rs:184,245-247`）。**若新面板另立一套场景画质存储，必然与 Environment 双写打架**——B 区复用它即可，一行数据模型都不用加。
2. **视口层 opt-out 机制已定义两者关系**：`EnvironmentOptOut { fog, ambient, post_processing, bloom, antialiasing }`（`jackdaw_surface/src/environment.rs:125-135`）——视口相机挂着它即可单独豁免场景环境的某部分；`environment_opt_out()`（`src/viewport_quality.rs:88-97`）由 `ViewportSettings` 推导（`antialiasing: true` 恒真——**视口 AA 永远视口说了算**，场景 AA 不落视口）。这正是「视口=预览质量总控、场景=最终观感」的既有分界，新面板只是把这个分界画成 UI。
3. **undo 语义两侧已定型**：viewport 侧文件头注释明说「Kept out of the undo snapshot, and set through operators that make no history entry」（`src/viewport_settings.rs:4-6`，operator 全部 `allows_undo = false`）；environment 侧 operator `allows_undo = false` + 内部 `CommandHistory.execute(SetEnvironment{before, after})` 一调一条 undo（`src/environment_ops.rs:163-174, 235-273`）。新面板控件只是调 operator，语义自动继承。
4. **为什么不扩展 environment 到「画质总控」**：Environment 是场景资产（随 .bsn 走、Play/导出带走），render scale/SSAO 质量等是编辑器预览性能权衡（用户机器相关），塞进场景会把编辑器性能偏好污染进游戏——两层必须分开，现状已分对。

### D3. 面板设计：dockable「Graphics」双区 + 置灰 GI 项

**结论：新窗口 `jackdaw.graphics`（RightSidebar 默认区），A 区（Viewport，editor-only 即时预览）+ B 区（Scene，environment.set 逐控件）+ 置灰「Realtime GI」。B 区在视口的可见性受 A 区 opt-out 开关钳制时给出提示行。**

1. **挂载**：`ctx.register_window(WindowDescriptor::new("jackdaw.graphics").with_name("Graphics").with_default_area(DefaultArea::RightSidebar).with_priority(...).with_build(...))`——照抄 `src/builtin_extensions.rs:89-102`（Outliner 注册模式）；开窗入口 = operator `graphics.open`（`allows_undo=false`，内部 `crate::open_window_in_default_area_if_absent(world, "jackdaw.graphics")`——同 `src/game_panel.rs:448` 的 `GAME_WINDOW_ID` 模式）+ Window 菜单一行 + 命令面板（operator 注册表全量枚举，`src/command_palette.rs:102-130`，零额外接入）。
2. **分组与控件**（MVP 明细见 §3 面板规格表；分组依据 D1 特性归属）：
   - **A 区 Viewport（编辑器预览）**：Preset（radio×4）/ Render Scale（slider 25–100）/ Anti-aliasing（segmented Off·FXAA·SMAA·TAA）/ SSAO（toggle + 质量 segmented Low·Medium·High·Ultra）/ Sun Shadows（toggle）/ Point Shadows（toggle）/ Fog（toggle）/ Sharpening（toggle + 强度 slider 0–1）；
   - **B 区 Scene（随场景保存）**：Tonemapper（dropdown，jackdaw `Tonemapper` 9 项）/ Exposure EV100（slider）/ Bloom Intensity（slider，>0 生效）/ Bloom Threshold（slider）；
   - **置灰区**：Realtime GI（disabled 行 + tooltip：Solari experimental / 未接入 / 替代项列表）。
3. **作用对象**：A 区 = `MainViewportCamera`（`dress_viewport_cameras` 既有插拔路径，新组件 CAS 走同一函数）；B 区 = 场景 `Environment` 实体（dress 所有场景 `Camera3d`）。**游戏相机差异化**（某相机单独 TAA/Bloom）：不走面板，走 Inspector `component.add`——**`.bsn` 已放行**：`SKIP_COMPONENT_PREFIXES`（`src/scene_io/mod.rs:38-61`）含 `bevy_render::` 但**不含** `bevy_anti_alias::`（TAA/SMAA/FXAA/CAS）、`bevy_post_process::`（Bloom/DoF/MotionBlur/Vignette）、也不含 `bevy_pbr::ssao::`；`bevy_camera::` 只 skip `primitives::`/`visibility::`（`Exposure` 可存，`Camera3d` 可存即功能 #6 已证）。
4. **预览语义（B 区可见性）**：B 区经 `dress_the_cameras` 也会落到视口相机，但受视口 opt-out 钳制——A 区「post_processing/bloom」关（Low/Medium preset 或手动关）时 B 区的 tonemap/exposure/bloom 在视口不可见。面板在检测到 `ViewportSettings.quality.post_processing == false`（或 `bloom == false` 且用户在动 bloom 滑条）时显示一行提示「Viewport opt-out：场景后处理未在视口预览（Viewport quality 的 Post-processing/Bloom 已关）」。
5. **「实时 GI」处置（推荐：显示置灰，不隐藏）**：用户原话点名；置灰 + tooltip「Bevy 的实时全局光照（Solari）是实验性硬件光追特性，需 `bevy_solari` cargo feature 与 RTX 级 GPU，jackdaw 尚未接入。可用替代：SSAO、天空环境反射（Environment → Ambient → Reflections: Sky）、反射探针烘焙、体积光」。

### D4. operator / undo 语义

| 控件区 | operator | allows_undo | 历史 | 存储 |
|---|---|---|---|---|
| A 区 preset/单项 | `viewport.quality.preset` / `viewport.quality.set`（**扩展**：anti_aliasing 枚举加 `smaa`；新增参数 `ssao_quality`、`sharpen`、`sharpen_strength` 或并入） | `false` | 无 | `viewport.json`（用户级，`store_viewport_settings` 自动落盘，`src/viewport_settings.rs:292-309`） |
| A 区 SSAO/锐化 | **新增** `viewport.ssao.set`（on, quality）与 `viewport.sharpen.set`（on, strength）——与 `viewport.show.toggle` 平级、职责单一，不把 `quality.set` 参数表撑爆 | `false` | 无 | 同上 |
| B 区每控件 | **既有** `environment.set`（每控件每操作一调，路径如 `post.bloom_intensity`） | `false`（operator 层） | **单条 undo**（内部 `SetEnvironment` EditorCommand） | `Environment` 组件 → `.bsn` |
| 开窗 | **新增** `graphics.open` | `false` | 无 | dock tree（用户布局） |

- 视口项 undo=false 的正当性：editor-only 用户偏好、非场景数据、改一次落一次盘——与既有 `viewport.*` 全家（`src/viewport_settings.rs:312-495`）完全一致，不新开先例；
- B 区 undo 必须保留（场景资产编辑）——由既有 `environment.set` 自动获得，滑条拖动建议只在松手（release）时发一调，避免 undo 栈被中间值灌爆（实现注意项，进 T2 验收）；
- 命令面板：所有新旧 operator 注册即被 `get_operators` 枚举（`src/command_palette.rs:102-130`），无需单做接入。

### D5. 测试策略

**headless（`tests/viewport/` 新文件 + 扩既有，形态照 `tests/viewport/viewport_settings.rs:14-39` 的 `editor_test_app + operator call` helper）**：

1. A 区模型：`anti_aliasing=smaa` 往返；旧 `viewport.json`（无 ssao_quality/sharpen 字段）加载走 serde default（`#[serde(default)]` 已兜底，`viewport_settings.rs:180-181`，测试钉住不回归）；
2. A 区生效：`viewport.ssao.set quality=ultra` → `MainViewportCamera` 上 `ScreenSpaceAmbientOcclusion.quality_level == Ultra`；SSAO 关 → 组件消失 + `NormalPrepass` 按保管逻辑回收（照 `viewport_quality.rs:158-167` 现有语义）；`viewport.sharpen.set on=true strength=0.8` → `ContrastAdaptiveSharpening` 出现/移除；AA 切 SMAA → `Smaa` 组件在（并验证 TAA↔SMAA 互斥切换清理 `TemporalJitter/MipBias`）；
3. B 区：面板控件参数映射 → `environment.set` → `Environment.post` 字段断言 + 相机 dress 断言（`jackdaw_surface/src/environment.rs` 的 `post_settings_reach_the_camera_components` 测试 `:995-1034` 已是现成形态）；undo 一条回滚；
4. 面板本身：`WindowRegistry` 含 `jackdaw.graphics`；`graphics.open` 后 dock tree 出现该 tab（照 `src/lib.rs:4034-4056` `the_default_tree_docks_one_viewport_panel` 测试形态）；命令面板可搜到（operator 枚举既有测试覆盖模式）；
5. 面板 spawn 的 UI 快照：A/B 区控件行存在、GI 行置灰（find text/状态断言，headless UI world）。

**真机（loop/qa 资产：BRP + SendInput + PrintWindow 截图，契约 loop/README.md「交互验收」）**：

1. 命令面板搜 "Graphics" 开面板（SendInput）→ 截图确认面板可见、双区布局、GI 行置灰；
2. A 区 AA 切 TAA → BRP 查 `MainViewportCamera` 实体断言 `TemporalAntiAliasing` 存在 → 切换前后 PrintWindow 截图 pixdiff > 阈值（loop/qa/pixdiff.ps1）；
3. A 区 SSAO Low↔Ultra 切换 → 组件断言 + 截图 diff；
4. B 区 bloom 滑条（先 `environment.set post.enabled=true`）→ BRP 读 `Environment` 实体 `post.bloom_intensity` == 滑条值 → 截图 diff（需场景有 emissive/亮部）；Ctrl+Z 一条 undo 回滚断言；
5. A 区改动不进 undo 栈（操作后 undo，场景无变化）；
6. 回归：viewport 设置菜单四档 preset 行为不变；Play 后场景相机仍按 Environment dress（BRP）。

### D6. 规模控制：MVP 12 项 + 置灰 1 项

**MVP 清单（12 项）**——A 区 9（其中 6 项为既有设置的面板化、3 项新增）、B 区 4（全为既有 operator 的 UI 化）：

| # | 项 | 区 | 新增性 |
|---|---|---|---|
| 1 | Quality preset（Low/Medium/High/Full） | A | 既有，面板化 |
| 2 | Render Scale 25–100 | A | 既有，面板化（slider 取代菜单子项） |
| 3 | Anti-aliasing Off/FXAA/**SMAA**/TAA | A | **SMAA 新增**（`AntiAliasing` enum 加变体 + dress 插拔） |
| 4 | SSAO on/off | A | 既有，面板化 |
| 5 | SSAO 质量 Low/Medium/High/Ultra | A | **新增**（`ViewportQuality` 加 `ssao_quality` 字段） |
| 6 | Sun Shadows on/off | A | 既有，面板化 |
| 7 | Point Shadows on/off | A | 既有，面板化 |
| 8 | Fog on/off | A | 既有，面板化 |
| 9 | Sharpening（CAS）on/off + 强度 | A | **新增**（`ViewportSettings` 加 `sharpen`/`sharpen_strength`） |
| 10 | Tonemapper | B | 既有 operator UI 化 |
| 11 | Exposure EV100 | B | 既有 operator UI 化 |
| 12 | Bloom Intensity + Threshold | B | 既有 operator UI 化 |
| — | Realtime GI | 置灰 | 显示 + tooltip |

**backlog（按价值排序）**：B 区 Vignette/调色（grading 参数组）、DoF 调参子面板、MotionBlur、Volumetric fog（FogVolume 体积实体面板化）、SSAO 高级参数（radius/thickness）、`Tonemapper` 补 `Linear` 变体（D1-d）、阴影贴图精细尺寸（脱离三档）、场景侧 preset 一键档位、**Solari 接入评估**（独立特性，先决：bevy feature 启用 + GPU 探测 + `RaytracingMesh3d` 自动标注策略）、SSR（先决：deferred 渲染路径）、DLSS（先决：cargo feature + NVIDIA 检测）。

**preset 成本评估（用户问点）**：视口侧四档 preset **已经存在**（`QualityPreset::quality()` 一张映射表，`src/viewport_settings.rs:70-111`），面板只是把它画成 radio 行——成本≈0，**包含**。场景侧 preset（一键把 Environment.post 设成档位）涉及「档位定义覆盖哪些字段、与用户手调值的关系」语义问题，成本不对称地高，backlog。

---

## 3. 技术方案

### 3.1 模块 / 文件布局

```
src/viewport_settings.rs   （改）AntiAliasing 加 Smaa 变体；ViewportQuality 加 ssao_quality；
                           ViewportSettings 加 sharpen/sharpen_strength；Preset 映射表补新字段
                           （Full 档 = SSAO High + 锐化 0.6 之类，保持既有档位语义只增不改）；
                           serde 兼容单测（旧文件无新字段 → default）
src/viewport_quality.rs    （改）dress_viewport_cameras 插拔 Smaa（含 preset 特化）与
                           ContrastAdaptiveSharpening；SSAO 组件写入 quality_level；
                           组件互斥清理（TAA↔SMAA）沿用现有 EffectPrepasses 保管模式
src/graphics_panel.rs      （新）面板构建（A/B 区控件行、GI 置灰行、opt-out 提示行）、
                           GraphicsOpenOp（graphics.open）、控件↔operator 绑定（radio_row/
                           segmented/slider 照 jackdaw_feathers 既有控件）、headless 单测
src/builtin_extensions.rs  （改）CoreWindowsExtension 注册 jackdaw.graphics 窗口 +
                           Window 菜单一行（或并入既有菜单行生成）
src/lib.rs                 （改）plugin 挂载 graphics_panel；（undo/存储零改动）
tests/viewport/graphics_panel.rs （新）headless：§D5-1~5 全部断言（复用 viewport_settings.rs
                           的 app_keeping_settings_in/call helper 模式）
loop/qa/graphics-*.ps1     （新）真机脚本：BRP 断言 + SendInput 驱动 + pixdiff
book/src/user-guide/        （改）Graphics 面板一节（含「视口预览 vs 场景画质」边界说明、GI 现状）
README.md                  （改）功能表一行
```

### 3.2 面板规格表（MVP）

| 分组 | 控件 | 类型 | 绑定（读源 / 写 operator） | 默认值 |
|---|---|---|---|---|
| Viewport · Preset | Quality Preset | radio ×4 | `ViewportSettings.preset()` / `viewport.quality.preset(preset=…)` | High |
| Viewport | Render Scale | slider 25–100 | `quality.render_scale` / `viewport.quality.set(render_scale=…)` | 100 |
| Viewport | Anti-aliasing | segmented Off·FXAA·SMAA·TAA | `quality.anti_aliasing` / `viewport.quality.set(anti_aliasing=…)` | FXAA |
| Viewport | SSAO | toggle + segmented Low·Medium·High·Ultra | `quality.ambient_occlusion` + `ssao_quality` / `viewport.ssao.set(on,quality)` | off（仅 Full 档开） |
| Viewport | Sun Shadows | toggle | `quality.sun_shadows` / `viewport.show.toggle(flag=sun_shadows)` | on |
| Viewport | Point Shadows | toggle | `quality.point_shadows` / `viewport.show.toggle(flag=point_shadows)` | on（High+） |
| Viewport | Fog | toggle | `quality.fog` / `viewport.show.toggle(flag=fog)` | on（Medium+） |
| Viewport | Sharpening | toggle + slider 0–1 | `sharpen`+`sharpen_strength` / `viewport.sharpen.set(on,strength)` | off / 0.6 |
| Scene | Tonemapper | dropdown ×9 | `Environment.post.tonemapper` / `environment.set(post.tonemapper=…)` | TonyMcMapface |
| Scene | Exposure (EV100) | slider（建议 -5..20） | `post.exposure` / `environment.set(post.exposure=…)` | 9.7 |
| Scene | Bloom Intensity | slider 0–1 | `post.bloom_intensity` / `environment.set(post.bloom_intensity=…)`（B 区组开关 = `post.enabled`） | 0 |
| Scene | Bloom Threshold | slider 0–1 | `post.bloom_threshold` / `environment.set(post.bloom_threshold=…)` | 0 |
| （置灰） | Realtime GI | disabled 行 + tooltip | 无（Solari 未接入） | — |

### 3.3 关键接口草图（示意，非最终签名）

```rust
// src/viewport_settings.rs（扩展）
pub enum AntiAliasing { Off, #[default] Fxaa, Taa, Smaa }          // serde snake_case，旧文件无损
pub struct ViewportQuality { /* 既有… */ pub ssao_quality: SsaoQuality }   // Low/Medium/High/Ultra
pub struct ViewportSettings { /* 既有… */ pub sharpen: bool, pub sharpen_strength: f32 }

// src/graphics_panel.rs（新）
#[operator(id = "graphics.open", label = "Open Graphics Panel",
           description = "Open the graphics quality panel: viewport preview settings and scene post-processing.",
           allows_undo = false)]
fn graphics_open(world: &mut World) -> OperatorResult;   // open_window_in_default_area_if_absent(…, "jackdaw.graphics")

#[operator(id = "viewport.ssao.set", label = "Set Viewport SSAO", allows_undo = false,
           params(on(bool), quality(String /* low|medium|high|ultra */)))]  fn …;
#[operator(id = "viewport.sharpen.set", label = "Set Viewport Sharpening", allows_undo = false,
           params(on(bool), strength(f64 /* 0..1 */)))]  fn …;
```

### 3.4 数据流

```
面板控件（release/选择时）
 ├─ A 区 → viewport.*.set/preset/toggle → ViewportSettings（resource_changed）
 │    ├→ viewport.json 落盘（store_viewport_settings，既有）
 │    └→ dress_viewport_cameras → MainViewportCamera 插拔 Smaa/TAA/CAS/SSAO(quality)
 │         （场景相机不受影响；场景 Environment 经 opt-out 机制不落视口的 AA）
 └─ B 区 → environment.set(post.*) → SetEnvironment（1 条 undo）→ Environment 组件
      └→ dress_the_cameras → 所有场景 Camera3d（+ 视口，按 opt_out）
           （.bsn 保存时随场景写盘；Play/导出带走）
```

---

## 4. 任务拆分（3 个任务）

### 任务 1（程序）：视口画质模型扩展（SMAA / SSAO 质量 / CAS）
- **内容**：`viewport_settings.rs` 模型扩展（enum/字段/preset 映射/serde 兼容）；`viewport_quality.rs` dress 插拔（SMAA preset、CAS、SSAO quality_level，互斥清理）；`viewport.ssao.set` / `viewport.sharpen.set` operator；`tests/viewport/viewport_settings.rs` 扩测（往返/旧文件兼容/组件断言）。
- **验收**：新增单测全绿（含旧 viewport.json 无新字段加载、AA 四态相机组件矩阵、SSAO 开关回收 NormalPrepass）；`cargo fmt/clippy` 过；既有 preset/菜单测试不回归。

### 任务 2（程序）：Graphics 面板 UI + 注册 + headless 测试
- **内容**：`src/graphics_panel.rs`（双区控件 + GI 置灰 + opt-out 提示 + `graphics.open`）；`builtin_extensions.rs` 窗口注册 + Window 菜单入口；`tests/viewport/graphics_panel.rs`（D5 headless 1–5）；B 区滑条 release-时-提交（undo 栈不灌爆）。
- **验收**：headless 全绿（窗口注册/dock tab/控件↔设置↔组件三段映射/B 区 undo 单条）；命令面板可搜到 graphics.open 与全部新 operator。

### 任务 3（QA）：真机验收 + 文档
- **内容**：loop/qa 脚本（BRP 组件断言 + SendInput + pixdiff，§D5 真机 1–6）；book 文档节 + README 行；回归 viewport 菜单/Play 链路。
- **验收**：§5 清单全勾。

---

## 5. 给 QA 的验收清单

**确定性门（全部必须绿）**
- [ ] `cargo fmt --all -- --check`；`cargo clippy --workspace -- -D warnings`；`cargo test --workspace --lib`
- [ ] `cargo xtask fast`（含 graphics_panel / viewport_settings 扩测）；doctests 基线非回归

**headless 行为断言**
- [ ] `anti_aliasing=smaa`：`Smaa` 组件插上、`TemporalAntiAliasing/TemporalJitter/MipBias` 清理干净；切回 TAA 反向成立
- [ ] `viewport.ssao.set quality=ultra on=true`：SSAO 组件 `quality_level == Ultra`；off 时组件与 `NormalPrepass`（若为效果所加）回收
- [ ] `viewport.sharpen.set`：`ContrastAdaptiveSharpening` 出现/消失，strength 透传
- [ ] 旧 `viewport.json`（无 ssao_quality/sharpen）加载 = 各字段 default；四档 preset 映射含新字段且 `preset()` 识别往返
- [ ] B 区控件参数 → `Environment.post` 字段断言；相机 dress（Tonemapping/Exposure/Bloom）断言；一条 undo 全回滚
- [ ] `WindowRegistry` 含 `jackdaw.graphics`；`graphics.open` 后 dock tree 有该 tab；A 区改动不产生 undo 条目

**真机（BRP + SendInput + PrintWindow）**
- [ ] 命令面板开 Graphics：面板可见、双区布局正确、Realtime GI 行置灰且 tooltip 含「Solari / experimental / 未接入」与替代项
- [ ] AA 切 TAA：BRP 断言视口相机组件 + 截图 pixdiff 超阈值；SSAO Low↔Ultra 同法
- [ ] bloom 滑条：BRP 读 `post.bloom_intensity` == UI 值；截图出现辉光变化；Ctrl+Z 回滚
- [ ] A 区（视口）改动后 Play：场景相机画质仍由场景 Environment 决定（编辑器预览设置不泄漏进游戏）
- [ ] 回归：viewport 设置菜单四档/单项行为不变；`tests/stage/scene_environment.rs` 全绿

**文档项**
- [ ] book：Graphics 面板节（双区边界图、viewport.json vs .bsn 归属、GI 现状与替代、SSAO 桌面后端说明）
- [ ] README 功能表一行

---

## 6. 风险与对策

1. **组件组合矩阵**（TAA×SSAO×SMAA×CAS×prepass 保管）：dress 逻辑集中在 `dress_viewport_cameras` 一处 + 组合单测矩阵（Off/FXAA/SMAA/TAA × SSAO on/off），prepass 回收严格走既有 `EffectPrepasses` 保管（`src/viewport_quality.rs:99-176`）——不另起状态。
2. **SMAA/TAA 首帧管线特化延迟**：视觉 1–2 帧滞后，无害；QA 截图前等待 ≥2 帧（pixdiff 脚本已有 settle 帧惯例，参照 `probe_bake.rs:19-20` SETTLE_FRAMES 思路）。
3. **B 区在视口不可见引发「面板坏了」错觉**：opt-out 提示行（D3-4）+ QA 专项（Low preset 下动 bloom 滑条 → 提示行出现）。
4. **滑条灌爆 undo 栈**：release-时-提交 + 单测断言 undo 栈长度；若 feathers slider 无 release 回调则用防抖（一拖一条合并），实现时二选一并写进测试。
5. **`bevy_solari` 误启用风险**：方案零接触 bevy feature；GI 行无任何运行时逻辑，仅文案。
6. **窗口面积挤压**：RightSidebar 已有 Inspector/多个窗口——`priority` 排后 + 用户可拖拽（dock tree 持久化），非默认自动打开（仅 `graphics.open`/菜单显式开），避免每次启动挤占。
7. **SSAO 平台边界**：浏览器 WebGPU/WebGL2 不支持（bevy 文档原文）；jackdaw 桌面（Vulkan/DX12）不受影响——文档注明即可。
8. **preset 语义漂移**：新字段加入 `QualityPreset::quality()` 映射时保持既有四档的原字段值不变（只增不改），测试钉住旧档位映射。

---

## 7. ⚠️ 需用户裁决项

1. **「Realtime GI」置灰显示 vs 不显示**：推荐**显示置灰 + tooltip 说明**（用户点名，隐藏反而困惑；tooltip 给出 Solari 现状与四个替代项）；备选：完全不显示该行。
2. **B 区（Scene 场景画质）是否进首版**：推荐**双区都做**（用户「画质设置」直觉通常含游戏最终观感，且 B 区只是既有 operator 的 UI 皮、成本约 1/4）；备选：首版只做 A 区（纯视口预览），B 区砍掉（少一个任务分量，但 bloom 强度这类最典型的「画质滑条」就不在面板里了）。
3. **面板默认停靠区**：推荐 RightSidebar（与 Inspector 同区、宽度适合滑条列）；备选 BottomDock（宽扁布局，横向分组）。
4. **CAS 锐化是否进 MVP**：推荐进（新组件插拔成本最低、与 TAA 搭配是常见画质项）；可砍（省约半天，减至 11 项）。

---
*证据快照：仓库 main `709c14ca`（干净）；bevy 锁定 checkout `bevy-50d7e162b728c6c6/c9c397b`。文中 file:line 均可复核；未运行任何 cargo 命令。实现期唯一「以实测为准」项：feathers slider 的提交时机（release 回调 vs 防抖，风险 4 的二选一）。*
