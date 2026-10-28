# 功能 #6 实施方案：Inspector 分类映射补齐（Camera/Sun 报障② 收尾）

> 多 Agent 开发循环 · 策划产物（只写方案，不含代码实现）
> 日期：2026-10-22 · 策划：资深 Bevy 编辑器工程师 Agent
> 选题依据：**用户真实报障② 的收尾**（feature-05 终验 QA 已定位根因，见
> `loop/reports/feature-05-final-qa.md` §5 —— **本文的事实基线，必读**）。
> 用户现象：新建工程里选中 Camera/Sun 实体，Inspector 只看到 Transform+Visibility
> 两个卡；期望：选中后**直接可见并可编辑**它们的灯/相机组件。
> QA 定性（已修正程序口径）：数据完好（活 ECS / scene.bsn / AST 三腿核实）、编辑卡
> 存在且可达（灯卡在 Components tab 真机亲见）；真因 = `seed_default_categories`
> **缺 bevy_light::\*/bevy_camera 相机类映射** → 卡落兜底 tab + 默认打开的 Object tab
> 只有 Transform/Visibility + 分类条纯图标可发现性差。**是信息架构/可发现性缺陷，
> 不是渲染缺陷。**
> 调研方法：rg + Read，未运行任何 cargo 命令。bevy 证据取自
> `%USERPROFILE%\.cargo\git\checkouts\bevy-50d7e162b728c6c6\c9c397b`
> （Cargo.lock 锁定 `c9c397ba…`，bevy 0.20.0-dev，下文记作 bevy@main）。

---

## 1. 范围与不做

**做**（四件，前两件是报障修复主体）：

1. **映射补齐**：`seed_default_categories` 增补灯/相机（及 Add 菜单可达的环境类）
   的 type_path → category 条目，使灯/相机卡进入**默认打开的 Object tab**（D1/D2）；
2. **粘性空 tab 兜底**：选中切换引发的 Inspector 重建时，活动分类不再自动停留在
   **无卡**的分类上（改按「有卡分类」解析，D3）——同源残留（QA 发现 ⚪4，曾致
   `r3-inspector.ps1` 假失败）；
3. **分类条可发现性**：tab tooltip 增强 + 内容列常显当前分类名标头（D4）；
4. **灯 color 编辑真机验证**：卡落对 tab 后 color picker 链路即通（引现成证据），
   补一次真机验证收尾 feature-05 残余（D5）。

**不做**（首版明确排除）：

- **不新建 Lights/Camera 分类 tab**（裁决项 1 的备选，不默认做）：strip 现宽
  30px（`tokens::SIDEBAR_WIDTH`，jackdaw_feathers/src/tokens.rs:418），加 tab 只加图标
  仍不可发现，且新 tab 仍需依赖第 2 件的粘性修复才生效——收益/扰动比不如归入 object；
- **不改右栏 dock 窗口名 "Components"**（builtin_extensions.rs:405 与分类 id "components"
  撞名，确有混淆，但改名波及面板注册/文档全链，本专项只用标头缓解，见 D4）；
- **不做「空 tab 内联提示文案」**（空 Components tab 现存 Add Component 按钮头
  `add_header.rs:120-128`，语义已自洽；粘性修复后自动落空场景消失）；
- **不补 bevy_render::/bevy_pbr:: 大 namespace 前缀**：其下大量派生/内部件
  （RenderLayers、Tonemapping、ColorGrading 等在 bevy@main 属 bevy_render，且被
  save-skip 挡在卡外，见 D2），宁缺毋滥；
- 不动卡片创建/过滤/反射编辑链路（QA 已证通畅，见 D5）。

---

## 2. D1. 映射表现状：六 tab、两级匹配、fallback="components"

全部证据在 `crates/jackdaw_api_internal/src/inspector.rs`：

- **tab 清单**（`seed_default_categories` :121-136，`order` 决定 strip 顺序）：
  | id | label | icon | order | 现有内容（语义） |
  |---|---|---|---|---|
  | object | Object | Box | 0 | Transform / Name / Visibility / bevy_ui Node——「实体是什么」（Node 的注释：layout is what the node *is*，:143-147） |
  | mesh | Mesh | Grid3x3 | 10 | Brush 几何（`jackdaw_scene_types::types::Brush` + 短别名，:148-152） |
  | modifiers | Modifiers | Wrench | 20 | `jackdaw_geometry::modifiers::ModifierStack`（:154） |
  | material | Material | Palette | 30 | `MeshMaterial3d<StandardMaterial>` 精确 + `material_card::*` 前缀（:156-159, :173） |
  | physics | Physics | Orbit | 40 | AvianCollider/RigidBody 精确 + `avian3d::`/`jackdaw_avian_integration::` 前缀（:161-162, :169-170） |
  | components | Components | Component | 50 | **兜底**（:97） |
- **现有精确条目共 10 条**（:138-164）：Transform、Name、Visibility、bevy_ui Node、
  Brush×2、ModifierStack、MeshMaterial3d<StandardMaterial>、AvianCollider、RigidBody。
- **缺失清单**（QA §5 :81 已证「无任何 bevy_light::\*、Camera3d、Camera 映射」）：
  灯全家（PointLight/DirectionalLight/SpotLight/AmbientLight/FogVolume）、相机全家
  （Camera/Camera2d/Camera3d/Projection/Perspective/OrthographicProjection/RenderTarget/
  Exposure/CameraMainTextureUsages/Hdr/TonemappingPass/CompositingSpace）、Add 菜单可达的
  `jackdaw_scene_types::types::ReflectionProbe`（creation_taxonomy.rs:195-204 的
  Fog Volume/Reflection Probe 实体模板，entity_ops.rs:771-775/:2824-2825）。
  以上类型**全部按现有 tab 语义归 "object"**（灯/相机/雾/探针就是该实体「是什么」，
  与 Node 入 object 同一判据），不臆造新 tab。
- Registry 是开放结构：扩展可 `register_category`/`set_component_category`（:48-75），
  本功能只改内置种子表。

## 3. D2. 匹配规则与条目粒度：精确优先、前缀按插入序、fallback 兜底

- **匹配规则**（`category_for` :84-98）：① 先查精确 HashMap（须命中已注册 category）；
  ② 再按 `component_category_prefixes` **插入序**做 `starts_with` 前缀匹配；③ 都不中
  → 返回 **"components"**。精确优先于前缀是显式契约（:66-67 注释 + 单测
  `prefix_routing_and_exact_wins` :231-246）——**压回条目**（把某派生类型精确指回
  components）天然被支持。
- **粒度决策**：
  - 灯用**精确条目**（不做 `bevy_light::` 全前缀）：DirectionalLight/PointLight 在
    bevy@main 通过 `#[require]` 拖入大量派生组件——Cascades/CascadesFrusta/
    CascadeShadowConfig/CascadesVisibleEntities（directional_light.rs:63-69）、
    CubemapFrusta/CubemapVisibleEntities/VisibilityClass（point_light.rs:41-47）、
    Frustum/VisibleMeshEntities（spot_light.rs:32）。其中仅 `bevy_light::cascade::Cascades`
    在 save-skip 精确表里（scene_io/mod.rs:66），**其余派生件会过 save-skip 进 AST
    成为卡**（register_entity_in_ast 全量同步，registration.rs:40-52）。全前缀会把
    这批只读派生卡一起搬进 object（QA 只 dump 过 Spot/Point 灯的兜底 tab=3 张卡，
    Sun 的卡集合未实测——T1 真机观察，见风险 1）。
  - 相机用**三条子模块前缀**（`bevy_camera::camera::`、`bevy_camera::components::`、
    `bevy_camera::projection::`）：编辑器 spawn 的相机（entity_ops.rs:683-701：
    Camera3d + Camera + RenderTarget）经 require 拉入 Projection/Frustum/
    CameraMainTextureUsages/VisibleEntities 等（bevy@main camera.rs:377-384、
    components.rs:24），其中 Frustum 在 `bevy_camera::primitives::`、可见性内部件在
    `bevy_camera::visibility::`——**这两个子模块恰好被 save-skip 前缀挡在卡外**
    （scene_io/mod.rs:43-44），故三条前缀圈进来的恰是可编辑的相机本体
    （Camera/Exposure/RenderTarget/CameraMainTextureUsages/Camera2d/Camera3d/Hdr/
    TonemappingPass/CompositingSpace/Projection/Perspective/OrthographicProjection，
    路径逐一核实于 bevy@main camera.rs:233/385/1049、projection.rs:217/284/580、
    components.rs:16/25/87/100/103）。`bevy_camera::visibility::Visibility` 已有
    精确条目→object（:142），不受影响。
- **fallback tab 行为**：id 为 "components"；strip 中 **恒显示**（`shown_categories`
  category_strip.rs:55-57：`"object" | "components" => true`，注释明示设计意图
  「每个实体都可能收组件，Components tab 必须可达」），空时面板剩 add-header
  （Add Component 按钮）+ Filter 行——**不隐藏**。粘性问题在
  `ActiveInspectorCategory`（Resource，默认 "object"，category_strip.rs:6-14），
  详见 D3。

## 4. D3. 粘性 + 空兜底：改「重建时按有卡分类解析」

- **现状**：`resolve_active_on_rebuild`（category_strip.rs:246-269）在卡增删
  （含换选中引发的整卡重建）后调
  `resolve_active_category(active, &shown)`——`shown` 里 object/components **恒在**
  （:266-268），所以停在 Components tab 时选中一个无兜底卡的实体（如 Cube），
  active 仍是 "components" → 面板只剩 Filter 行。这正是 QA 复跑亲历的
  「粘性 + 兜底 tab 无卡 → 整面板显空」（feature-05-final-qa.md 发现 ⚪4 :117）。
  `resolve_active_category`（inspector.rs:109-118）本身语义正确（current 在列表内则
  保持，否则取首项，空则不变）——**问题在喂给它的列表**。
- **改法（推荐）**：`resolve_active_on_rebuild` 改喂 **`applicable`**（有卡分类，
  category_strip.rs:18-31，strip 序）而非 `shown`。效果：
  - 换选中时，若当前分类对新实体**无卡** → 自动落到首个有卡分类（Sun/Camera →
    object，正好是报障想要的「直接可见」）；
  - 当前分类有卡（跨实体浏览 Components 里的 SubEntity/SyncToSubWorld 等）→ 照旧
    粘住，**不破坏粘性设计**；
  - **手动点击空 Components tab 仍可停留**（点击走 observer 直写
    category_strip.rs:146-150，不触发重建）——「Components 必须可达」的设计意图
    保住。语义变化仅在「自动复位」一侧（裁决项 2）。
- **否决的替代**：隐藏空兜底 tab（与「必须可达」显式设计冲突，代码注释即反证）；
  空 tab 显示占位文案（add_header 的 Add Component 按钮已自洽，加了反而重复）。
- **顺手修正（⚪ 文档债）**：`paint_category_tabs` 的 doc 注释（category_strip.rs:161-166）
  称「components: shown only when applicable」，与 `shown_categories` 实码（恒显示）
  矛盾——以码为准改注释，防后人再误判（QA §5 程序口径偏差的近亲）。

## 5. D4. 可发现性：tooltip 已存在（title-only）→ 增描述 + 内容列常显分类名

- **现状**：分类条是 30px 宽纯图标竖列（category_strip.rs:94-151），每个 tab 生成时
  **已挂 `Tooltip::title(label)`**（:117）。Tooltip 是两级延迟（300ms 出 title、长停
  展开 description/footer，jackdaw_feathers/src/tooltip.rs:63-116）——**机制在，但
  title-only + hover 门控，用户没发现**（QA 发现 2）。右栏 dock 窗口名又叫
  "Components"（builtin_extensions.rs:405），与分类名撞车，加重误导。
- **最小改法（推荐，两招）**：
  1. **tooltip 增 description**：`Tooltip::title(label)` → 追加 `.with_description(...)`
     （builder 已有，tooltip.rs:100-105），每个内置 tab 一句静态文案（如 object：
     "Identity, transform and what this entity is"、components: "Everything else on
     this entity"）。纯 spawn 期改动，零新系统。
  2. **内容列常显当前分类名**：`layout.rs` 的 `inspector_components_content`
     （:955-1029）在 add-header 上方加一个小标头 Text（新 marker，如
     `ActiveCategoryLabel`），`category_strip.rs` 加一个 Update 小系统在
     `ActiveInspectorCategory` 变化时写 label。面板里**常显**当前 tab 名，不依赖
     hover——直接回答「我的卡被分到哪个页签了」。
- **否决的替代**：图标下加文字 label（30px 轨道放不下，需加宽 rail——Figma 风格
  窄轨是既定视觉，不动）；tab 上加卡数角标（过度设计）。

## 6. D5. 灯 color 编辑残余：链路现成，仅需真机验证

- QA 已证卡可达、卡片创建链通畅（feature-05-final-qa.md §5 :82-83：AST 过滤
  component_display.rs:446-462 通过、`register_entity_in_ast` 全量同步）。
- **color 编辑是通用反射通道，非灯专属**：`reflect_fields.rs:626-627` 对任何
  `Color` 类型反射字段渲染 color picker（FeathersColorPlane + 每通道 Slider + swatch，
  :1507-1543），提交走 `on_color_plane_change`（:1789）/`on_color_slider_change`
  observer——**已在 InspectorPlugin 注册**（mod.rs:118-119），与已验通的 Transform
  编辑同为 reflect_fields/ScrubNumberInput 通道（QA 定性「风险低」§5 :90）。
  三种灯均有 `pub color: Color` 字段（bevy@main spot_light.rs:38 等）。
- **结论：零代码工作**。唯一注意：picker 值不是 Text widget，BRP 断言不可见
  （QA 基建沉淀，发现 ⚪5 :118）——验证用「组件 bbox 定位法」驱动 + scene.bsn
  断言 color 值 + 视口截图三件套。

---

## 7. 技术方案与文件布局

| 文件 | 改动 |
|---|---|
| `crates/jackdaw_api_internal/src/inspector.rs` | `seed_default_categories` 增条目（见下）+ 单测扩充 |
| `src/inspector/category_strip.rs` | `resolve_active_on_rebuild` 喂 applicable；`paint_category_tabs` doc 注释修正；新 `ActiveCategoryLabel` 小系统；（T2）spawn 时 tooltip 加 description |
| `src/layout.rs` | `inspector_components_content` 内容列顶部加 `ActiveCategoryLabel` Text 节点（T2） |
| `loop/qa/`（不入库） | 真机脚本复用 f5 系列 + manual.md 契约 |

**映射条目一览（全部 → "object"；3 前缀 + 6 精确）**：

```text
# 灯（精确，避免 require 拖入的派生卡跟迁）
bevy_light::point_light::PointLight                     → object
bevy_light::directional_light::DirectionalLight         → object
bevy_light::spot_light::SpotLight                       → object
bevy_light::ambient_light::AmbientLight                 → object   # 相机挂载的环境光覆盖（bevy@main Component）
bevy_light::volumetric::FogVolume                       → object   # Add 菜单 Fog Volume 实体
# 相机（三条子模块前缀；primitives/visibility 子模块被 save-skip 挡在卡外，天然排除）
bevy_camera::camera::                                   → object   # Camera/Exposure/RenderTarget/CameraMainTextureUsages
bevy_camera::components::                               → object   # Camera3d/Camera2d/Hdr/TonemappingPass/CompositingSpace
bevy_camera::projection::                               → object   # Projection/Perspective/Orthographic
# Add 菜单 Reflection Probe 实体（jackdaw 用户类型，现落兜底）
jackdaw_scene_types::types::ReflectionProbe             → object
# 条件性压回（T1 真机若见 Sun 的派生卡进 object，按此式精确压回，exact 优先于前缀）
# bevy_light::cascade::CascadesFrusta                   → components
```

**headless 单测**（`inspector.rs` tests 扩充 + `category_strip.rs`）：
- 每条新映射命中 "object"（含前缀路径拼出的完整 type_path，如
  `bevy_camera::projection::Projection`、`bevy_light::spot_light::SpotLight`）；
- 未映射类型仍落 "components" 不炸（既有用例扩参：`bevy_light::cascade::CascadesFrusta`
  → components，正好钉住「灯走精确不走前缀」的决策）；
- `Visibility` 精确条目仍 object（既有回归）；
- 粘性新语义：resolve 目标列表从 shown 换 applicable 后，
  `resolve_active_category("components", &[object 有卡集])` → object；
  有卡时保持；空集保持不变（纯函数既有用例覆盖，补喂参用例）。

---

## 8. 任务拆分（2 个任务，串行）

### T1：映射补齐 + 粘性解析修复（报障② 主体）

- 程序：
  1. `seed_default_categories` 增 3 前缀 + 6 精确（§7 表）；
  2. `resolve_active_on_rebuild` 改喂 `applicable`（D3）+ `paint_category_tabs`
     过期注释修正；
  3. headless 单测（§7）；
  4. 真机观察项：Sun 的 object tab 卡集合（是否混入 CascadesFrusta 等派生卡），
     混入则加压回条目（exact→components，一行一事）。
- QA：真机核心项（§9 T1 清单）+ quick tier 四门。
- 产出：QA 报告（Sun/Camera 卡集合 dump 留档，反哺压回条目决策）。

### T2：可发现性 + 灯 color 编辑真机验证 + 收尾

- 程序：
  1. tab tooltip 加 description（D4-1，spawn 期常量表）；
  2. `ActiveCategoryLabel` 标头（layout.rs + category_strip.rs 小系统，D4-2）；
  3. T1 观察到的压回条目定稿（如有）。
- QA：真机 T2 清单（§9）+ quick tier + 全量门（`cargo xtask fast`，QA 认为必要时）
  + 最终 QA 报告 + `loop/progress.md` 记一行。

---

## 9. QA 验收清单（含真机项具体步骤）

**Quick tier 门（每任务）**：`cargo fmt --all -- --check`；`cargo clippy --workspace --
-D warnings`；`cargo test --workspace --lib`；被改 crate 相关集成测试。
真机流程一律照 `loop/qa/manual.md` 契约（就绪判定、BRP 调用、合成输入、时序、留档）。

**T1 真机项（my-game）**：
1. [ ] 启动（`JACKDAW_OPEN_PROJECT`）→ 就绪 ≤60s；
2. [ ] outliner UI 点击选中 **Sun** → **不点任何 tab 图标**（复刻用户原始操作）→
   UI Text dump 断言 Inspector 面板出现 "DirectionalLight" 卡文本（默认 tab 即可见，
   报障② 核心验收）+ 截图留档；
3. [ ] 选中 **Main Camera** → dump 断言 "Camera3d" 与 "Projection"（或 Camera）卡文本
   出现；dump 留档（顺带记录 Sun/Camera 的 object tab 完整卡集合——压回条目依据）；
4. [ ] **粘性**：点 Components tab 图标 → 选中 Cube → 断言自动回 object（dump 出现
   Transform 卡、Components 下无卡）→ 复跑 `r3-inspector` 类断言不再假失败；
5. [ ] **回归**：Cube/Sphere 的 object tab 卡集合与改动前一致（灯/相机映射不波及
   brush）；手动点空 Components tab 仍可停留且 Add Component 按钮在；
6. [ ] `jackdaw/entity {name:'Sun'}` bsn 数据与改动前一致（映射纯 UI 路由，不碰数据）。

**T2 真机项**：
1. [ ] **灯 color 编辑**（feature-05 残余收尾）：选中 Sun → DirectionalLight 卡内
   color picker（`world.query` by FeathersColorPlane/Slider 组件 bbox 定位，QA 沉淀法）
   改为红色 → ① `jackdaw/entity {name:'Sun'}` 断言 bsn `color` 值变化 ② 保存重开
   值保持 ③ viewport 截图亮度/色偏可见变化；
2. [ ] 同法抽验 Point Light（Add 菜单新建）color 编辑一轮；
3. [ ] tooltip：悬停 tab 图标 ≥300ms 出 title + description（两级展开）；
4. [ ] 内容列顶部常显当前分类名（"Object"/"Components"/…），切 tab 即变；
5. [ ] quick tier + 全量门 + 台账。

---

## 10. 风险

1. **Sun 的派生卡混入 object tab**（D2 粒度决策的已知不确定点）：CascadesFrusta 等
   会过 save-skip 进 AST，若真机确见混入，用压回条目（exact→components）一行解决，
   机制已备（exact 优先）。影响=观感，不动摇方案。
2. **粘性语义变化**：换选中不再停留无卡分类（自动落到首个有卡分类）。手动点空 tab
   仍可停。跨实体浏览兜底卡的工作流（SubEntity/SyncToSubWorld 有卡）不受影响——
   有卡即粘住。需在 QA 手册记一句新语义。
3. **`bevy_camera::camera::` 前缀圈进未来新增类型**：bevy 升级若在 camera.rs 新增
   Component，会自动进 object——方向正确（相机本体），概率低、影响正面向；单测钉
   现有集合即可。
4. **BRP 断言面**：color picker 值非 Text widget（f5 发现 ⚪5），断言依赖
   scene.bsn + 截图三件套；ScrubNumberInput 类比教训（f5 发现 ⚪3）提示 QA 脚本
   不要假设输入框交互语义（颜色滑条用组件 bbox 定位，不用 Backspace 假设）。
5. **Tooltip 文案语言**：UI 现全英文，description 沿用英文（一致性优先）；对中文
   用户可发现性增益主要靠 T2 的常显标头而非 tooltip。

---

## 11. 需用户裁决项

1. **灯/相机卡归 tab**：推荐 **object**（默认 tab 直接可见，最小扰动，与 Node 入
   object 同一语义判据）。备选：新建 Lights/Camera tab（strip 加图标、需选 icon 与
   order，且仍依赖粘性修复才自动可达——若用户更想要「灯归灯页签」的信息架构可选
   此项，工作量 +小半）。
2. **粘性语义变化**（D3）：换选中时自动离开无卡分类。推荐：接受（这正是报障②
   「直接可见」的机制半边；手动浏览空 tab 的能力保留）。
3. **可发现性两招取舍**（D4）：推荐 tooltip 增描述 + 内容列常显分类名两招都做
   （都很小）；若要更保守可只做常显标头（收益主力）、tooltip 维持 title-only。
