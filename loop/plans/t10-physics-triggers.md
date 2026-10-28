# T10 物理与触发器制作闭环 — 实施方案

> 策划产物（2026-10-28，基于本地 main **e0df824e**（T09 闭环点 = P1 前两项基线）全量代码只读调研 +
> 上游版本网络查证；不建分支、不改代码）。需求来源：`loop/plans/roadmap-game-dev.md` T10（P1 第三项，
> T01-T09 已全部闭环）。
> **验收原文**（roadmap 第 22 行，已逐字核实）：「物理与触发器制作闭环：**复用 Avian 集成**，完善
> Collider/RigidBody/Sensor/碰撞层/调试显示；触发器连游戏行为。**验收=不穿地/受力正确/拾取过关可做；
> Play 与导出一致。**」
> 拆解（策划口径，供矩阵与验收对齐）：「复用 Avian 集成」=在既有 avian 双 crate（编辑器扩展+游戏桥）上
> 补全，**禁止**另起物理栈（rapier 等）；「不穿地」=dynamic 体落在 static 碰撞面上稳定静止、无穿透；
> 「受力正确」=重力/力参数可配且数值行为与配置一致（对齐 T08 行为断言模式）；「拾取过关可做」=Sensor
> 触发体→游戏行为（despawn/计数/过关路由）的制作链在模板里可复刻；「Play 与导出一致」=PIE 行为=导出
> 包行为（T07 三态③同口径）。
> buglist 物理/触发域**零直接条目**（全量扫描：Y6 是视口像素、W? 仅 terrain 字样撞词，见 §一重叠表）；
> 缺陷主体是本方案新发现的 **F1-F8**（physics F 系，避开 buglist N 系/T08 P 系/T09 I 系）。
> **附带钦点**（progress.md 2026-10-27 T09 闭环行）：T10-T1 顺带给 open-challenges 补「实体手柄」
> ledger 一行（T09-T3 QA 发现漏写）——纳入 T0 执行（见二、）。

---

## 0. 架构事实（核实结论，方案的地基）

**「物理」在 jackdaw 里=一套写完但被依赖闸门整体封印的双 crate + 零触发器链路 + 全链就绪的模块机制**。
五条事实决定方案走向：

- **事实一：物理栈两侧代码已完整，且被 `unavailable` 标记整体封印**。`integrations/physics/` 是
  **独立 workspace**（`integrations/physics/Cargo.toml:5-7`，成员 `jackdaw_avian_integration`+
  `jackdaw_physics`；:2-4 注释明言设计意图「the editor's workspace and lockfile never resolve avian」）。
  两个 crate 均标 `package.metadata.jackdaw.unavailable = "avian has no release for Bevy main"`
  （`jackdaw_avian_integration/Cargo.toml:14-15`、`jackdaw_physics/Cargo.toml:14-15`）。已写完的能力：
  - **游戏侧桥**（`jackdaw_avian_integration`）：`AvianCollider(pub ColliderConstructor)` newtype 绕开
    avian 消费型构造器（`src/lib.rs:25-40`）；`AvianColliderBridgePlugin` 从 brush 几何/模型网格/图元
    三源构建 `Collider`（`:49-91`，Changed 驱动+Remove observer 清理）；`StaticCollidersPlugin` 给无
    body 的 collider 自动 `RigidBody::Static`+`ImpliedStaticBody` 标记（`static_bodies.rs:13-77`）；
    `register_avian_types` 注册 RigidBody/**Sensor**/速度/阻尼/力/睡眠/**CollisionLayers** 等 24 类型
    （`lib.rs:139-177`，**未注册 `CollisionEventsEnabled`**——avian 0.8 事件前提组件，见事实四）；
    `ModelCollidersPlugin` + `terrain` feature 高度场地形 collider。
  - **编辑器扩展**（`jackdaw_physics`，EXTENSION_ID=`jackdaw.physics`，`src/lib.rs:32`）：编辑器进程内
    直接跑 `PhysicsPlugins::default()`（`:67-80`）；Physics Tool（`tool.rs:37-43`：Shift+P 激活 modal、
    选中体模拟/其余 RigidBodyDisabled 冻结、Space 单 undo 提交、Esc 还原）；collider 线框 gizmo
    （`overlays.rs:87-135`，**Sensor 已有专属青色**，:16-18）；`physics.enable/disable` operator
    （`components.rs:58-98`，一步加 AvianCollider+Static，undo span）；Inspector physics 分类 chips+
    brush 默认物理组件（`:16-23`）；Sensor→NavmeshIgnored 联动（`bodies.rs:83-104`）。**编辑器测试六件
    已在但不可构建**（`jackdaw_physics/tests/editor/{tool,picker,toggles,physics_ops,round_trip,
    preview_guard}.rs`）。
  - **封印效果实证**：本地无 `integrations/physics/Cargo.lock`（workspace 从未解析构建）；主
    workspace `Cargo.lock` 无 avian（编辑器二进制零物理）；新工程对话框 physics 勾选框 disabled+
    "not compatible"（`src/launcher/pages/new_project.rs:323-341`）；模块切换同样拒绝
    （`src/module_picker.rs:153-158,244-247`）；**还有一条断言「不能启用」的测试**（`tests/stage/
    new_project.rs:289-303`，"a new game cannot start with physics yet"——T10 解锁后这条测试反转，
    是现成的红→绿用例）。
- **事实二：unavailable 的根因是 bevy 源不统一，且该障碍在 T10 策划期已实质消失（本方案网络查证）**。
  jackdaw 主 workspace bevy = **git main pin** `c9c397ba`（`Cargo.toml:206`，lock 里版本 `0.20.0-dev`，
  提交日期 **2026-10-21**——即 bevy 0.20.0 正式版（crates.io **2026-10-08** 发布）之后 13 天的 main
  增量）；而 avian 依赖 registry bevy。git bevy 与 registry bevy 在 cargo 里是**两个不同包实例**，
  Plugin trait 等类型不互通 → 任何「jackdaw crate（git bevy）+ avian（registry bevy）」的组合都编不过
  ——这就是 unavailable 注释「avian has no release that builds against Bevy's main branch」的机制。
  **关键新事实**：avian3d **0.8.0 已于 2026-10-20 发布**，依赖 registry `bevy ^0.20`（crates.io 依赖
  声明实查），对应版本表 Bevy 0.20↔Avian 0.8。即「无版本可用」已变为「有版本、但源不统一」——
  **一条 `[patch.crates-io] bevy = { git, rev }` 把 registry bevy 0.20 重定向到 c9c397ba git 树，类型
  即统一**；c9c397ba 距 0.20 final 仅 13 天 main 增量，avian 0.8 对 0.20 final 写，直接编译通过的概率
  高（残余 API 漂移量未知，T0 编译探针先行钉死，决策 1）。
- **事实三：模块机制全链就绪，闸门只有 unavailable 一个**。`modules.json:2-35` 定义 physics 模块
  （`default: true`、crates=avian3d "0.8"（plugin 表达式 `PhysicsPlugins::default()`）+
  jackdaw_avian_integration（path 随 jackdaw_runtime）、`component_prefixes: ["avian3d::",
  "jackdaw_avian_integration::"]`、`hidden_components` 内部件屏蔽、`extension: "jackdaw.physics"`）。
  解锁后免费获得：新工程/模块切换 UI 可勾（disabled 逻辑自动失效）、scaffold `add_module_crates`
  自动给游戏 Cargo.toml 写 avian3d+bridge 依赖（`crates/jackdaw_scaffold/src/lib.rs:2065-2096`）、
  plugin_notes 提示 wiring（`:2100-2110`）、`jackdaw.toml [modules]` 记录
  （`crates/jackdaw_project_build/src/project_manifest.rs:67-70`）、**avian 源一致性守卫测试已在**
  （`tests/sdk_layout/template_versions.rs:118-171`，模块目录与 integrations workspace 的 avian 源
  不许漂移）。注意 `ModuleCrate` 已预留 `git`/`rev` 字段（`modules.rs:80-88`，注释明言「for a crate
  with no release on jackdaw's Bevy yet」）——决策 1 的 B 路线有现成载体。游戏工程的 bevy 同样来自
  git pin（模板 `Cargo.toml.template:16-17` 的 `{{bevy_dependency}}` 占位），**游戏侧 avian 同样需要
  patch**（与编辑器侧同病同药，scaffold 注入）。
- **事实四：触发器链路完全空白——Sensor 只差「最后一公里」**。avian 0.8 事件 API（docs.rs 0.8.0 实查）：
  `CollisionStart`/`CollisionEnd` 两事件（Message 或 observer 双通道消费）+ **前提组件
  `CollisionEventsEnabled`**（不带它的实体不发事件）+ `Sensor`（只检测不施力）+
  `CollidingEntities`/`Collisions`（持续接触查询）。jackdaw 现状：Sensor 类型已注册+青色 gizmo+
  navmesh 联动（事实一），但 `CollisionEventsEnabled` **未注册**、全仓**零** CollisionStart/End/
  CollisionEvent 消费（rg 实证）、无任何「触发→游戏行为」桥、模板零触发器教学。Inspector 侧
  `CollisionLayers` 的 u32 bitmask 编辑 feathers 已有专门支持（`crates/jackdaw_feathers/src/text_edit.rs:
  317,1158,1275,1295`、`src/inspector/reflect_fields.rs:733,2000`）——**碰撞层的数据面编辑能力已在**，
  缺的是类型注册进 picker 之后的真机验证与层语义（命名/预设）作者面。
- **事实五：编辑器核心已「认识」物理组件，保底与断言面现成**。①分类路由内置：
  `crates/jackdaw_api_internal/src/inspector.rs:214-224` 把 AvianCollider/RigidBody 精确条目+
  `avian3d::`/`jackdaw_avian_integration::` 前缀全部路由到 physics 分类（模块没加载编辑器也认）；
  ②无模块保底已验证：物理组件以 UnresolvedTypes 保真存于场景文档，open→resave 零丢失
  （`tests/scenes/physics_round_trip.rs:19-58`）；③PIE 投影排除 avian 内部件
  （`crates/jackdaw_pie_protocol/src/snapshot.rs:57,69`），实体+组件投影可断言物理行为
  （scene_snapshot 两帧差，T08/T09 同款行为断言模式）；④Resources 面板 allowlist 已含
  `avian3d::math::Gravity`（`src/inspector/resource_panel.rs:66`）；⑤扩展注入点一行式
  （`src/lib.rs:657-664` `ExtensionPlugin::with_extension::<T>`）；⑥MCP 25 工具+22 BRP 方法
  （T09 口径）构成验收驱动面。**注意**：事件是瞬时 Message，投影流不含事件——触发器断言需设计
  「事件→可观察落点」（组件计数/实体消失），与 T08 决策 6（行为断言优先）同族（决策 6）。

---

## 一、现状与缺陷矩阵

### A. 物理栈可用性（验收句主体「复用 Avian 集成」）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **F1** | 🔴 | **物理栈整体被封印**：unavailable 标记让新工程不可启用 physics 模块（UI disabled+测试断言「不能启用」）、物理 workspace 从未构建、游戏工程零 avian 依赖——一切 Play 零物理（物理组件 unresolved 保留、不实例化、不受力）。「不穿地/受力正确」全部落空。根因=git bevy 与 registry bevy 源不统一（事实二），而 avian 0.8.0（2026-10-20，依赖 registry bevy ^0.20）发布后该障碍实质已消——标记过期，解锁=patch+摘标记 | `modules.json:34`；`new_project.rs:289-303`；`Cargo.toml:206`+lock `0.20.0-dev`；crates.io 实查（bevy 0.20.0 2026-10-08/avian3d 0.8.0 2026-10-20） |
| **F2** | 🔴 | **编辑器零物理工具**：`jackdaw_physics`（Physics Tool/gizmo/enable-disable/chips）未随编辑器构建（独立 workspace 不进主编译，扩展无任何加载路径——既非 builtin 也非 dylib）。编辑器内模拟摆放、collider 线框、Sensor 可视化全部不可用；「调试显示」验收句的编辑器腿落空 | `integrations/physics/Cargo.toml:5-7`；`src/lib.rs:637-664`（注入点无 physics）；`src/builtin_extensions.rs`（无 physics） |

### B. 触发器与碰撞层（「Sensor/碰撞层/触发器连游戏行为」）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **F3** | 🔴 | **触发器零链路**：无 `CollisionEventsEnabled` 注册（avian 0.8 事件前提组件缺席→即使场景写了 Sensor，Play 中也不发事件）；全仓零 CollisionStart/End 消费；无「触发→游戏行为」桥（拾取/过关/onEnter/onExit 无从制作）；模板零触发器教学。「拾取过关可做」落空 | `lib.rs:139-177`（注册清单缺）；rg 全仓零消费；`lib.rs.template:1-231`（零 Sensor） |
| **F4** | 🟡 | **碰撞层作者面残缺**：`CollisionLayers` 类型已注册+feathers bitmask 编辑支持已在，但①无层命名（作者面对 `memberships=0b…10` 无语义提示，只能心算 bit）；②picker 引导/分类未真机验证；③层间互滤行为（触发器只对某层触发）零文档零示例 | `lib.rs:170`；`text_edit.rs:317,1158`；`reflect_fields.rs:733,2000`；book 无碰撞层节 |

### C. 模板与教学

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **F5** | 🟡 | **模板零物理且双重力教学冲突**：模块解锁后（default=true）新工程默认带 avian，但模板 `GamePlugin` 无 PhysicsPlugins/bridge wiring、无物理示例；现有 `falling_cubes` 用 `GameConfig.gravity` **手动位移**模拟下落（`:179-189`）——物理启用后与 avian 真重力并存，同一 cube 双重下落，教学语义打架（见 F8） | `lib.rs.template:68-89`（build 无物理）、`:179-189`（手动重力）；`modules.json:6`（default true） |
| **F8** | ⚪ | **重力双源无说明**：`GameConfig.gravity`（T08 配置资产）与 avian `Gravity` Resource（Resources 面板 :66 allowlist 可见）是两个互不相干的重力；物理启用后模板/文档需写明分工（作者态全局参数 vs 引擎物理 Resource），否则作者困惑 | `lib.rs.template:134`；`resource_panel.rs:66`；avian `Gravity` |

### D. 测试与断言面

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **F6** | ⚪ | **触发事件无直接断言通道**：事件是瞬时 Message，PIE 投影只流实体+组件——「进入触发体」断言需要可观察落点（组件计数/实体 despawn/Transform 骤变）。零新工具即可满足（行为断言设计），但需在示例与矩阵里**设计好落点**，否则 QA 只能靠日志（PIE 日志面尚是 backlog） | `pie_protocol/snapshot.rs`（投影域）；open-challenges.md:50-53（日志面 ledger） |
| **F7** | ⚪ | **调试显示边界未钉死**：编辑器 gizmo（overlays）默认关、无 PIE/导出侧 collider 显示策略（avian debug-plugin feature 在 `jackdaw_physics/Cargo.toml:31`，游戏侧 `PhysicsPlugins::default()` 不含 debug render）；「调试显示」验收句需要两侧边界写清（编辑器=always 可开；游戏=默认关、可开） | `overlays.rs:50`（默认 false）；`modules.json:12`（default 插件表达式） |
| — | ✅ | **正向资产（不用重建）**：双 crate 全部功能代码+编辑器六件测试；模块机制全链（catalog/scaffold/manifest/UI/一致性守卫）；「不能启用」断言测试（现成红证）；无模块 round-trip 保真；inspector physics 分类路由内置；feathers bitmask 编辑；Sensor gizmo 青色；PIE 投影排除内部件；MCP 25 工具+22 BRP；T08 行为断言/T07 导出链/T03 undo span（Physics Tool commit 设计本就单 undo） | 事实一/三/五 |

**统计：🔴 3（F1、F2、F3）｜🟡 2（F4、F5）｜⚪ 3（F6、F7、F8）｜✅ 双 crate+模块机制+保底三块地基**

### buglist 重叠表（物理/碰撞/触发/sensor/rigid/collider 域全量扫描）

| 条目 | 一句话 | T10 处置 |
|---|---|---|
| **Y6** | 坐标轴指示器物理/逻辑像素混用（字面撞「物理」词） | **不吸收**：视口 UI 像素域，与物理栈零交集。备注维持 |
| W?（terrain scatter） | scatter yaw 修正假设刚体变换（字面撞「rigid」词） | **不吸收**：地形散射域。备注维持 |
| Y37 | PIE 每帧全量反射 JSON 序列化（性能） | **不吸收但知悉**：物理行为断言继续吃该投影流的性能账；physics 组件增多（Collider 内部件已排除）不放大投影 |
| N12/Y33 | BRP 实体域不通/游戏侧 BRP CORS | **不吸收**：物理断言走投影域（scene_snapshot），按域选方法（T08/T09 同款裁定） |
| 其余 | 无物理域条目 | 无动作 |

> 如实报告：物理/触发域 buglist 零直接条目——该域从未可用过，没有用户可踩出的 bug；T10 的缺陷主体是
> 本方案新发现的 F1-F8。唯一「准历史账」是 unavailable 标记本身（上游欠的依赖账，本方案查证已可还）。

---

## 二、分任务拆解（T0 前置 + T1/T2/T3）

### T0「编译探针 + 手柄 ledger 补行」（前置，调查性，产出=裁决依据，主控零代码决策输入）

**背景**：决策 1（解锁路线）的物理事实只剩一个未知数——avian 0.8（registry bevy ^0.20）被 patch 到
c9c397ba（git main，0.20.0+13 天增量）后**是否直接编译通过**。这决定 T1 走 A 路线（patch）还是
B 路线（avian git rev，见决策 1）。探针必须在 T1 开工前出结论。

**执行方式**（不动主 workspace，不建分支）：
1. **探针 A（patch 路线）**：复制 `integrations/physics/` 到临时目录（或直接在原地，反正是独立
   workspace 不影响主编译），`Cargo.toml` 加 `[patch.crates-io] bevy = { git =
   "https://github.com/bevyengine/bevy", rev = "c9c397ba…", features 同主 workspace }`，`cargo check
   --workspace`（首次解析 avian 全家桶，预留 10-30 分钟）。结论三选一：①零错误零警告→A 路线直通；
   ②少量错误（bevy main 13 天增量的 breaking）→逐条记录错误面（预估修复量：若 ≤5 处且集中在
   integration/physics 两 crate 内→A 路线带小适配；若集中在 avian 内部→升级 B 路线评估）；③大量
   错误→B 路线探针（avian main 分支找依赖 git bevy 的 rev，`ModuleCrate.git/rev` 载体）；
2. **探针 B（若 A 失败）**：查 avian 仓库 main 分支 Cargo.toml 的 bevy 依赖形态（registry or git）；
   若为 git main 分支依赖→与 jackdaw `branch = "main"` 声明统一解析（cargo 对同 URL+branch 单点解析，
   但会解析到**最新头**而非 c9c397ba——需同时把主 workspace bevy 声明锁 rev 或接受齐头并进，风险
   见决策 1-B）；若 avian main 也是 registry→B 不可行，回 A 带适配或提请主控裁定量级；
3. **手柄 ledger 补行（台账钦点，字节安全操作）**：`book/src/developer-guide/open-challenges.md:47-55`
   的 input-actions ledger 段（"Three smaller ledgers from the input-actions work (2026-10)"）追加
   第四条：实体手柄（physical gamepad）端到端腿无硬件验证，机制层以 GilrsPlugin+合成事件链钉死，
   真机腿挂账待设备——与既有三条（schema watcher/PIE 日志面/stop 残留）并排，"Three"改"Four"；
   该文件是 book 文档，改动过 docs 门（fmt 不涉，book build 校验一次）；
4. **产出**：`loop/reports/t10-t0-probe.md`（探针结论+错误清单+A/B 裁定建议+重编时间记录）。

**验收标准**：
- [ ] 探针结论明确（直通/带小适配/转 B），证据=完整 cargo 输出留档（门禁证据标准：日志全文，不信
  exit code 单值）；
- [ ] open-challenges 手柄行落盘且 book 三条原文未被破坏（Read/Edit 工具操作，前后 SHA 留档）；
- [ ] 不触碰主 workspace 任何文件（`git status` 干净佐证，integrations 原地探针除外——若原地做，
  摘除探针 patch 行恢复原状并 diff 留档）。

**耗时预估**：2-4 小时（大头是 avian 首次解析编译）。

### T1「物理栈解锁与双侧接线」（F1+F2；决策 1/2/5）

**目标**：物理模块从 unavailable 到「新工程开箱可用」——编辑器带 Physics Tool/gizmo/chips；新工程
（模板）默认启用 physics 模块、Cargo.toml 自动带 avian3d+bridge、Play 中动态体落地不穿、静态碰撞面
可用；「不能启用」测试反转为「开箱启用」。

**改动面预估**：
1. **bevy 源统一（决策 1-A 主体，按 T0 结论）**：
   a) `integrations/physics/Cargo.toml` 加 `[patch.crates-io] bevy = { git, rev=c9c397ba }`（探针
      验证过的形态）；主 workspace 接入两个物理 crate（members 或 path 依赖，决策 2-A 形态）——
      主 `Cargo.toml` 同步同一条 patch（主编译拉 avian 0.8 registry+patch 统一源）；若 T0 判定需
      小适配，适配落在 integration/physics 两 crate 内（禁改 avian 源码——除非走 vendored fork，
      那是 B 路线领地）；
   b) 游戏侧 patch 注入：scaffold `add_module_crates`（`scaffold/lib.rs:2065-2096`）对 physics 模块
      的工程在 Cargo.toml 追加同款 `[patch.crates-io]`（模块 crate 级注入，模板 `{{}}` 占位同族）；
      **scaffold 内嵌 lock 快照机制（T08 lockfix）联动**：快照需覆盖 avian 依赖树（测试族验证新工程
      lock 可解析）；存量工程（如 my-game）启用模块的路径=Edit Project Modules UI→patch 由
      `runtime_wiring`/文档给出（book 写手动两行）；
2. **编辑器集成（决策 2-A）**：`src/main.rs`（或 App 构建处）`ExtensionPlugin` 加
   `.with_extension::<jackdaw_physics::PhysicsExtension>()`（`src/lib.rs:657-664` 注入点）；确认
   `PhysicsEditorPlugin` 与编辑器既有 schedule/picking 无冲突（Physics Tool 的 MeshRayCast 过滤
   EditorEntity 约定已在）；编辑器进程内 avian 常驻的编译时间账量级记录进报告；
3. **模块闸门开放**：`modules.json:34` 摘除 `unavailable` 行（+两 crate Cargo.toml 的 metadata 同步
   摘）；`tests/stage/new_project.rs:289-303` 断言反转（红→绿主证：main 上「不可勾」→本任务
   「默认勾且 jackdaw.toml 记 physics=true」）；`tests/sdk_layout/template_versions.rs:118-171`
   avian 源一致性守卫不动（仍防漂移）；
4. **模板接线（wiring 层，示例系统留 T2）**：`lib.rs.template` 的 `GamePlugin::build` 加
   `PhysicsPlugins::default()`+`AvianColliderBridgePlugin`（modules.json plugin 表达式同款，注释
   写明「physics 模块（默认启用）带来的插件」）；模板 `Cargo.toml.template` 的 avian3d 依赖由
   scaffold 模块机制注入（模板本体零硬编码 avian 版本，一致性守卫保证）；
5. **Resources 面板回归**：`Gravity` allowlist（`resource_panel.rs:66`）在模块加载后真实可见/可改
   （会话态语义不变，book 钉边界，见 F8 处置——文档腿留 T3）。

**验收标准（可执行可复现）**：
- [ ] headless 红→绿①（模块闸门）：`new_project.rs` 反转断言——新建工程 physics 默认勾选、
  `jackdaw.toml` `modules["physics"]=true`、Cargo.toml 含 `avian3d = "0.8"`+`jackdaw_avian_integration`
  +`[patch.crates-io]` bevy 行（红证=main 上同操作 disabled/false/无依赖）；
- [ ] headless（编辑器扩展）：编辑器 App 构建含 PhysicsExtension——catalog 出现 `jackdaw.physics`、
  physics 分类 chips 可见（inspector 分类路由既有测试扩一腿）；`physics.enable` operator 走通
  （复用 `jackdaw_physics/tests/editor/physics_ops.rs` 六件套——**随主 CI 复活并全绿**）；
- [ ] headless（编译面）：主 workspace `cargo check`/clippy/test 全绿（avian 进主编译的增量面）；
  integrations workspace `cargo check` 绿；
- [ ] **真机（编辑器腿，BRP 驱动）**：scaffold 新工程 → 编辑器打开 → 视口 Add Entity Cube →
  `call_operator physics.enable` → Inspector 出 physics 分类+AvianCollider/RigidBody(Static) →
  `view.toggle_collider_gizmos` → 截图见绿色线框 → 再加一个 Cube 置 `component.set
  RigidBody="Dynamic"`、抬高 y=3 → 进 Physics Tool（合成 `input.key P+Shift`）→ `input.motion`
  拖拽释放 → `jackdaw/wait` 后 `scene_snapshot`：dynamic 体 y 落到 static 面上稳定（两帧差≈0）、
  **无穿透（y 不低于面上沿）**——「不穿地」编辑器腿首证；Space 提交 → `jackdaw/history` 栈顶恰
  一条 Physics commit（T03 域回归）；
- [ ] **真机（PIE 腿）**：同工程 `pie.play_current` → `scene_snapshot` 两帧差：dynamic 体先动后停
  （落地稳定），与编辑器 Tool 模拟终态一致；stop 后场景文档 SHA 不变（T06 Stop 铁证回归）；
- [ ] 模板 scaffold 测试族扩展（物理 wiring 断言+实编 cargo check——T06/T09 先例）。

**测试设计**：`tests/stage/new_project.rs` 反转+扩展；`jackdaw_physics/tests/editor/` 六件并入主 CI
（xtask 覆盖面扩容说明）；guards 新 `tests/guards/physics_module.rs`（模块启用→Cargo.toml/lock
解析往返）；真机脚本沉淀 `loop/qa/t10-physics-unlock.ps1`。**buglist 吸收**：无打钩（F 系新发现）。

### T2「触发器/碰撞层/模板教学」（F3+F4+F5+F8；决策 3/4/6）

**目标**：「Sensor/碰撞层/触发器连游戏行为」闭环——Sensor 触发体在编辑器可制作（组件+gizmo+层过滤）、
Play 中进入/离开事件可达游戏代码（可读 API+模板示例）、模板开箱有「拾取物」示例（踩到→despawn+计数），
「拾取过关可做」成立。

**改动面预估**：
1. **事件前提补齐（F3 机制层）**：`register_avian_types` 补 `CollisionEventsEnabled` 注册
   （`lib.rs:139-177` 清单）+ bridge 侧「Sensor 实体自动补 CollisionEventsEnabled」系统（作者只加
   Sensor，前提组件零心智——Added<Sensor> 驱动 insert，与 static_bodies 同族模式）；单测：无组件
   不发事件（avian 语义钉死）→补组件后发（红→绿）；
2. **触发器桥（决策 3-B'，runtime 薄层 `crates/jackdaw_runtime` 新模块 `triggers.rs`，对齐 T09
   InputActionsPlugin 形态）**：
   a) `TriggerPlugin`：读 CollisionStart/End（MessageReader）→ 维护 `TriggerEvents` Resource
      （`Vec<TriggerContact { trigger: Entity, other: Entity, phase: Enter/Exit }>` 每帧重置）+
      持续态 `CollidingEntities` 直查文档化；sensor 侧判定=触发体带 Sensor（进入对中 sensor 一侧
      为 trigger，另一侧为 other；双侧 sensor 的边角规则写死：双方都算 trigger）；
   b) 与 T09 `GameActions` 同族哲学：游戏读命名/实体级状态不碰 avian 细节；`TriggerEvents` 入
      `jackdaw_runtime::prelude`；
   c) **断言落点设计（F6）**：模板示例把触发计数写进组件（见 3），不新增 BRP/投影通道（Y37 性能账
      不加码）；若 QA 实跑发现投影不含该组件再按 MCP 优先流程评估（预案：`jackdaw/scene_snapshot`
      已投实体+组件，自定义组件默认在投影面）；
3. **模板教学（F5，`lib.rs.template`）**：
   a) 新示例段「# Physics & triggers」：Startup spawn 拾取物（小立方+AvianCollider(Sphere)+
      **Sensor**+自发光材质）×3 与地面（大 Cuboid+AvianCollider+Static——或直接教 brush 建地面，
      模板 spawn 简单可控优先）；玩家侧 PlayerMarker 补 AvianCollider(Capsule)+RigidBody::Dynamic
      （**T09 的 PlayerMarker 获得物理身**，Move 动作驱动的位移改走 LinearVelocity 或保持 Transform+
      collider 跟随——决策 6 拍板，模板注释写明取舍）；
   b) 拾取系统（~15 行）：`TriggerEvents` 读 Enter（trigger 侧带 `Pickup` 标记组件）→ despawn 拾取物
      + `PickupCount(u32)` 组件写计数（挂玩家，**投影可断言**）→ 集齐 3 个 `info!("Level clear!")`
      ——「拾取过关可做」的最小完整教学；
   c) `falling_cubes` 处置（F8/F5 冲突，决策 6）：物理启用后手动重力与 avian 打架——**falling_cubes
      改造为 avian 版**（FallingCube spawn 带 AvianCollider+Dynamic，下落交给 avian，
      `GameConfig.gravity` 改写 avian `Gravity` Resource 初值——Startup 一行 insert，物理时代语义
      归一：T08 配置资产依旧作者态真相，注入面从「手动位移」升级为「物理 Resource」；move_speed
      继续驱动 spin 组件行为保持）；
   d) doc 注释：触发器工作流（加 Sensor→可选 CollisionLayers 过滤→Play 触发→读 TriggerEvents）、
      gizmo 青色=Sensor 的提示、CollisionEventsEnabled 自动补齐说明；
4. **碰撞层作者面（F4，最小面）**：CollisionLayers 的 picker 可加性验证（类型已注册+bitmask 编辑
   已支持——真机证明一次全链：给拾取物设 `memberships=0b10, filters=0b01`、玩家 0b01——层互滤下
   不触发，改 filters 后触发，红绿两格）；**层命名资产挂 backlog**（决策 4：首版 bitmask+文档表
   格足够，命名层是体验增强，挂 open-challenges/T25 邻域）；层语义示例写进模板 doc+book；
5. **调试显示边界（F7）**：编辑器 gizmo 既有（T1 已验）；游戏侧验证一次「PhysicsPlugins 含
   debug-plugin feature 时 Play 中 collider 线框可开」或如实记录 default 插件不含 debug render 的
   边界（模块 feature 协商：`jackdaw_avian_integration` 加 `debug-render` feature 透传，默认关——
   book 钉死）。

**验收标准**：
- [ ] headless 红→绿①（事件前提）：Sensor 实体无 CollisionEventsEnabled → avian 不发 CollisionStart
  （红）；自动补齐系统在 → 发（绿）；两侧实体对/同帧 enter-exit 边角用例；
- [ ] headless 红→绿②（桥）：无 TriggerPlugin 时 `TriggerEvents` 不存在；注册+注入 CollisionStart
  （sensor A × 玩家 B）→ Enter 对 (A,B)；CollisionEnd → Exit 对；非 sensor 碰撞不进列表；
- [ ] headless（层过滤）：CollisionLayers 互滤下 avian 不发事件（avian 语义）→ 桥零输出；
- [ ] 模板：scaffold 测试族扩展（拾取物/TriggerPlugin/FallingCube 物理版，实编 cargo check）；
- [ ] **真机（编辑器制作链）**：选中拾取物实体 → Inspector physics 分类 → Add Component `Sensor` →
  gizmo 变青色（截图断言色值）；`CollisionLayers` 字段编辑（bitmask 输入）往返保存重开一致（T02
  三处一致口径）；
- [ ] **真机（PIE 拾取链，验收句主体）**：Play → 合成 `input.key W` 持续 1s（T09 链复用）驱 PlayerMarker
  走向拾取物 → `scene_snapshot`：拾取物实体消失+玩家 `PickupCount` 0→1（**触发器连游戏行为的端到端
  首证**）→ 集齐 3 个 → （日志/组件断言 clear）；层过滤格：改层后同路径不触发（红绿对比）；
- [ ] 真机（受力正确）：`game-config.bsn` 改 gravity=-19.62 → Play → dynamic 体下落位移速率精确加倍
  （两帧差数学断言，T08 C4 同款方法学）；Resources 面板改 `Gravity`（会话态）行为同变——两重力源
  语义钉死（F8 边界文档腿）；
- [ ] 「不穿地」PIE 腿回归：高速下落（gravity 加倍）dynamic 体仍停在地面上（数值采样多帧）。

**测试设计**：runtime `triggers.rs` 内嵌单测（桥三组）+ guards 新 `tests/guards/physics_triggers.rs`
（场景含 Sensor 存档→runtime 加载→事件链）；真机脚本沉淀 `loop/qa/t10-triggers.ps1`。
**buglist 吸收**：无打钩。

### T3「验收矩阵 + 文档收尾」（F4 文档腿+F7+F8+全任务终验）

**目标**：验收句「不穿地/受力正确/拾取过关可做；Play 与导出一致」终验矩阵（全 BRP/MCP 驱动）；
book 物理文档改写（unavailable 语境退役）+触发器/碰撞层节；roadmap 勾选。

**改动面预估**：
1. **真机验收矩阵**（截图+日志留档 `loop/reports/`，模板工程 fixture）：

| # | 场景 | 期望 |
|---|---|---|
| 1 | 新工程开箱物理 | scaffold 新工程 → jackdaw.toml physics=true + Cargo.toml avian/bridge/patch 三件在 + 模板 wiring 在（T1 链复验）+ cargo run 独立跑同行为 |
| 2 | **不穿地·编辑器** | Physics Tool 拖放 dynamic → 落 static 面稳定；Esc 还原；Space 单 undo（T03 回归） |
| 3 | **不穿地·PIE** | Play 中 dynamic 抬高坠落 → 多帧 y 采样收敛于面、无穿透（含 gravity 加倍压力格） |
| 4 | **受力正确** | game-config gravity 改值 → 下落速率数值断言（两帧差）；LinearVelocity/外力组件（ConstantForce）Inspector 编辑→行为变化一格 |
| 5 | **拾取（触发器连行为）** | 合成输入驱玩家 → PickupCount 递增+实体消失（T2 链复跑）；Exit 事件格：离开触发区再进入→计数再增（Enter/Exit 双沿各有证据） |
| 6 | **过关** | 集齐 3 拾取物 → clear 可观察（组件/日志）；过关路由=TriggerEvents 消费系统，模板可复刻 |
| 7 | 碰撞层 | 层互滤不触发/改层触发红绿两格（T2 链复跑）；bitmask 编辑重开一致 |
| 8 | Sensor 可视化 | gizmo 青色断言；隐藏/显示 toggle 往返 |
| 9 | **Play=导出一致** | `game.export` → dist 内 avian 依赖编译进 exe + assets 场景含物理组件 → **异目录启动 dist exe**（T07 heavy 链）：拾取链行为=PIE 行为（桌面真机驱一次，输出日志/截图比对） |
| 10 | 三态①重启 | 物理场景（Sensor+层+dynamic 布局）保存→重开→组件全在且 Inspector 正常（round-trip 已有保底，此处真机复验编辑态） |
| 11 | 无模块保底回归 | physics_round_trip 既有用例 + 手动验证：模块关闭的工程打开物理场景 → unresolved 保留+提示（T10 不破坏保底语义） |
| 12 | Stop 铁证回归 | Play（物理跑动中）→ stop → 场景 SHA/资产 SHA 不变、temp 清理（物理链零污染） |

2. **book 文档**：`user-guide/physics.md` 改写（unavailable/模块语境退役→开箱默认启用；补触发器节：
   Sensor/TriggerEvents/拾取教学导览；碰撞层节：bitmask+层表+互滤示例；调试显示节：编辑器 gizmo+
   游戏 debug-render 边界；重力双源说明 F8）；`developer-guide/crate-structure.md`/`editor-tooling.md`
   的物理 crate 描述同步（编进编辑器后形态）；open-challenges 不新增（若层命名挂账则加一行）；
3. **工具面核对（MCP 优先评估结论）**：现有 25 工具+22 BRP **足够**——`component.*`（加 Sensor/
   CollisionLayers）、`physics.enable/disable`（call_operator）、`input.key/motion`（驱动 Physics Tool
   拖拽+玩家移动）、`jackdaw/pie`/`scene_snapshot`（行为断言）、`jackdaw/export`（格 9）、
   `jackdaw/history`（格 2 undo）；**唯一评估项**=事件直查面（F6）按 T2-2c 预案处理（行为落点够用
   则不立项）；导出 exe 的真机驱动（格 9）若桌面合成输入困难，允许立项最小 BRP 脚注（dist exe 开
   BRP 的端口策略）——按 MCP 优先流程裁量，不硬耗；
4. buglist 核对（无打钩预期）、roadmap T10 勾选、台账记行（含 T0 探针结论与手柄补行结果）。

**验收标准**：
- [ ] 矩阵 12 格全过（无设备/环境降级格如实标注，不虚报）；
- [ ] 全量门按 2026-10-25 升级版门禁证据标准（日志全文复核、重跑覆盖归档）；物理 crate 进主 CI
  后的覆盖面说明（xtask 面扩容）；
- [ ] 用户 30 秒清单：①新工程 Play——立方体掉在地上弹一下停住，不穿地；②给小方块加 Sensor、
  走过去碰它——它消失、计数+1（青色线框=触发器）；③Build Game… 双击 dist exe——同样的拾取
  同样能玩。

**QA 清单（放行标准，全任务）**：
- [ ] T0 探针结论留档+路线经主控裁定；T1/T2/T3 各自验收全绿；F1/F2/F3 各有机制层红→绿
  （F1 红证=main「不能启用」测试，F2 红证=编辑器无 jackdaw.physics，F3 红证=无组件不发事件）；
- [ ] 验收句四腿铁证：不穿地（格 2/3 数值采样）、受力正确（格 4 数学断言）、拾取过关（格 5/6 端到端）、
  Play=导出（格 9 异目录启动）各有独立证据；
- [ ] T01/T02/T03/T06/T07/T08/T09 既有防线回归：fly/输入断言（格 5 用 T09 链）、三处一致（格 7/10）、
  undo（格 2）、Stop 铁证（格 12）、导出 manifest（格 9）、dirty 三腿（格 9 前置）、不混用（格 5
  合成输入走捕获态）；
- [ ] quick 门（T1/T2）/ 全量门（T3）；门禁证据以日志全文复核为准。

---

## 三、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **物理栈解锁路线（本方案最高权重）** | A=**`[patch.crates-io]` bevy→git rev c9c397ba**（integrations workspace+主 workspace+游戏工程 scaffold 注入三处同一条 patch）：avian 0.8（registry bevy ^0.20）被重定向到与 jackdaw 同一棵 git bevy 树，类型统一；c9c397ba 距 0.20 final 仅 13 天 main 增量（2026-10-21 实查），avian 0.8 对 0.20 final 写，直通概率高；改动面=三处 Cargo.toml+scaffold 注入逻辑，零 Rust 代码改动（若直通）。缺点：patch 是维护面（bevy pin 前进时 patch rev 同步——可加一致性守卫测试钉死，template_versions.rs 同族）；avian 升版仍需重新验证。B=**avian git rev**（`ModuleCrate.git/rev` 载体现成）：需 avian 仓库存在依赖 git bevy main 的 rev 且与 c9c397ba 兼容（avian main 通常在 release 后基于 registry 开发，窗口不确定）；即便有，其 bevy 若为 branch 声明会解析到最新头而非 c9c397ba——**rev 对齐脆弱**。C=等 avian 0.9/bevy 0.21 或主 workspace 切 registry bevy 0.20：前者时间不可控，后者推翻 bleeding-edge 哲学（`template_versions.rs:113-115` 断言 pins bevy=main/channel=bleeding-edge）且牵动全仓版本协商——均不做。D=换 rapier：违反验收句「复用 Avian 集成」字面，物理栈两侧代码全废——**否决** | **A**（T0 探针先行钉死直通/小适配量；小适配若 ≤5 处且在 integration 两 crate 内→A 带适配；触及 avian 内部→回主控重裁 A+/B）；**bevy pin 前进时的 patch 同步**加守卫（新 guards：主 lock bevy rev == patch rev == integrations rev 三方一致） |
| 2 | **编辑器物理工具的集成形态** | A=**编进编辑器二进制**（主 workspace members/path 依赖 `jackdaw_physics`，`ExtensionPlugin::with_extension::<PhysicsExtension>()` 一行，物理 crate 进主 CI）：加载零机制（builtin 形态）、T10 验收的编辑器腿直接可用、六件编辑器测试随主 CI 复活；代价=主 workspace 开始解析 avian（编译时间+编辑器体积增长，量级 T1 记录；上游「never resolve avian」设计被有意推翻——注释与相关防线同步改）。B=**dylib 按工程加载**（游戏工程启用 physics 模块→编译扩展 dylib→loader 加载）：编辑器保持零 avian、模块化纯净；但构建链复杂（ABI/loader 纪律）、每工程首开编译等待、QA 驱动面变长（先 build 扩展再验），且「模块工程的编辑器无物理工具」对格 2（编辑器腿）反而是障碍——工具何时在场依赖工程，心智重 | **A**；上游双 workspace 设计的初衷（锁文件隔离）在 bevy 源统一后已无必要，主编译的 avian 成本由 dev profile/按需 feature 控制（debug-plugin 保持 feature 门）；B 挂 open-challenges 一句话（若将来编辑器体积成账再评估）。**integrations workspace 去留**：随 A 并入主 workspace（members 化、独立 workspace 退役）——单一 lock 单一真相，避免双 workspace lock 漂移（程序任务裁量实现细节：terrain feature 边界保留） |
| 3 | **触发器事件路由机制** | A=**纯文档直通**（游戏自写 CollisionStart observer/reader，零新抽象）：机制最小，但每游戏重写样板+Sensor 判定+Enter/Exit 配对散在用户代码——T09 已裁定同族问题不做直通（决策 2「只给数据层」被否）。B=**runtime 薄桥 `TriggerPlugin`→`TriggerEvents` Resource**（Enter/Exit 实体对每帧列表+sensor 侧判定+CollidingEntities 直查文档化）：与 `GameActions` 同构（引擎细节→游戏可读状态）、模板一行接线、断言落点天然（列表驱动示例组件）；桥本身 ~60 行+单测，零依赖新增。C=完整触发器框架（命名触发器/动作绑定/可视化连线）：Unity Playmaker 级野心，T12 UI 能力与 T15+ 行为系统未到，过度建设 | **B**；命名触发器（`GameTrigger{name}`+按名路由）作为 B 的糖看模板需求（若示例需按名区分再加一个 marker 组件，不加机制）；C 挂 open-challenges（T20 示例游戏若需要再议） |
| 4 | **碰撞层作者面形态** | A=**首版 bitmask+文档**（CollisionLayers 既有 bitmask 编辑+层语义表进 book/模板 doc）：零新机制，feathers 编辑已在，真机验证+教学即可；缺点=作者心算 bit（0b100=层 3）。B=**层命名配置资产**（T08 族 `GameCollisionLayers { layers: Vec<String> }`，Inspector 显示层名下拉/复选、运行时零消费——纯作者态 UI 糖）：体验对齐商业引擎；代价=bitmask↔层名的 Inspector 桥接是新编辑面（schema 卡片管 Vec、但 CollisionLayers 是 avian 组件的**字段级**友好化，要走自定义字段渲染或 chip——改动面不小且 avian 类型不可加 attribute） | **A 首版**（验收句「碰撞层」=可配可生效，bitmask+互滤示例已满足）；B 挂 backlog/open-challenges（真需要时从「Inspector 层名 tooltip/十六进制分组显示」这类只读糖起步，不动 avian 类型） |
| 5 | **physics 模块默认启用策略** | A=**维持 `default: true`**（modules.json 上游意图；解锁后新工程开箱即物理，模板/T11/T20 全部受益；验收句「新工程放玩家+地面即玩」（T11）依赖物理在场）：代价=所有新工程编译 avian（冷编分钟级增量，lock 快照已控树形）。B=改 `default: false` 显式勾选：编译可选，但「开箱即玩」落空、模板需分「有物理/无物理」两形态（复杂度反升）、新工程对话框多一步 | **A 维持**；编译账由 T08 lockfix 机制+共享 target 目录（物理 workspace 的 dev profile 对齐主 workspace 的设计本就在，`integrations/physics/Cargo.toml:57-70`）压住；若实测新工程冷编超阈值（>5 分钟增量）再回落 B，主控留裁量 |
| 6 | **模板改造与双重力处置** | A=**物理化收编**（FallingCube 改 avian dynamic 下落、`GameConfig.gravity` Startup 注入 avian `Gravity` Resource、PlayerMarker 获得 capsule 碰撞体、Move 驱动改 LinearVelocity）：模板只教一套物理真相，T08 的配置资产语义升级为「物理 Resource 初值」（ConfigLoader→Resource 的一次新用法，与 T08 机制兼容——Startup 系统读 Resource 值 insert 即可）；PlayerMarker 位移从 Transform 直写改 Velocity——T09 的 Move 示例语义变化需在 doc 写明（动作→速度的物理化驱动是 T11 控制器的预演）。B=**并存分区**（保留手动 falling_cubes+另设物理示例段）：教学保留「无物理也行」的对照，但同帧双重力冲突（物理启用后 FallingCube 若带 collider 会双重下落，不带则永远穿地——两种都教坏） | **A 收编**；对照教学改为 doc 说明（「无物理时代的手动位移已退役，物理默认在场」）；PlayerMarker 若 Velocity 化导致 T09 已验矩阵语义漂移（格 10 位移断言口径），改法=保留 Transform 版玩家+新增物理版玩家实体二选一由程序裁量，**T09 矩阵复跑是放行条件** |
| 7 | **游戏侧调试显示（gizmo）边界** | A=**默认关+feature 透传可开**（`jackdaw_avian_integration` 加 `debug-render` feature（透传 avian debug-plugin），modules.json 不默认开；book 写明「Play 里看 collider 线框=开 feature 重编」）：游戏画面干净、发布包零调试残留；缺点=PIE 里直观调试要多一步。B=PIE 默认开 gizmo（游戏子进程带 debug render）：直观但污染最终画面语义、导出腿要记得关——两态不一致风险 | **A**；编辑器内 gizmo（overlays）已覆盖制作期调试需求（青色 Sensor+线框），PIE 侧按需 feature；book 钉死边界（F7 结案） |

小定案（主控可否决）：方案内编号 F1-F8；触发器桥命名 `TriggerPlugin`/`TriggerEvents`/`TriggerContact`
（入 `jackdaw_runtime::prelude`，与 `GameActions` 家族并列）；模板拾取物命名 `Pickup`+计数组件
`PickupCount`；自动补齐 CollisionEventsEnabled 的系统与 `StaticCollidersPlugin` 同族（Added<Sensor>
驱动）；「过关」首版=`info!`+组件可断言（T12 UI/T20 示例游戏再升真正的过关流转）；物理 crate 并入主
workspace 后 `integrations/physics` 独立 workspace 退役（terrain feature 保留为 crate feature）。

---

## 四、风险与回滚

| 风险 | 缓解 |
|---|---|
| **avian 0.8 对 c9c397ba（0.20+13 天增量）编译不过**（决策 1 的核心未知数） | T0 探针先行，结论三档（直通/≤5 处小适配/转 B）各有预案；小适配集中在 integration 两 crate 内可 A 带适配；触及 avian 内部→升主控重裁；B 路线（avian git rev）探针脚本同批准备；最坏回退=unavailable 维持+T10 挂起升级用户裁决（roadmap 维护规则：「执行中发现清单外依赖（如 T10 依赖引擎物理版本），按需插入并标注」——roadmap 第 53 行原文已预判本风险） |
| **patch 维护面**（bevy pin 前进/avian 升版时三方 patch 漂移） | 守卫测试钉死三方一致（主 lock bevy rev==patch rev==integrations rev）；avian 源一致性守卫（template_versions.rs:118-171）已在；pin 前进流程=改 patch+跑守卫+探针复验，写进 book developer 节 |
| **主 workspace 引入 avian 的编译时间/体积账**（编辑器全量构建变慢，CI 时长涨） | T1 记录增量数字（冷/热编）；dev profile 已对齐（integrations Cargo.toml:57-70）；debug-plugin 等 feature 保持门控；若账超阈值→决策 2-B（dylib）为后手，open-challenges 留档 |
| **Physics Tool（modal）与既有输入链交互**（Shift+P 键位、capture 态、T01 工具取消纪律） | 六件编辑器测试随主 CI 复活护航；真机格 2 全链（激活/拖拽/Space/Esc）；若与 capture 态（Play 中 Shift+P）冲突→工具可用性 gate 在 Editor 态（`run_if(in_state(AppState::Editor))` 已在 components.rs:28 同族），如实测冲突按 T01 纪律补断言 |
| **模板 PlayerMarker 物理化破坏 T09 已验矩阵**（格 10 位移断言、五动作语义） | 决策 6 备选（双玩家实体/保留 Transform 版）；**T09 矩阵 12 格复跑是 T2 放行条件**；冲突时保守取「新增物理玩家，Marker 原样」 |
| **双重力教学语义（F8）** | T2-3c 收编方案+Startup 注入链单测（GameConfig.gravity→avian Gravity Resource 值相等断言）；Resources 面板会话态改 Gravity 的行为差异（物理时代=即时生效 vs 配置资产=下次启动）在 book 写明 |
| **事件桥边角**（同帧 enter-exit、双侧 sensor、despawn 时 End 是否发、层过滤与事件次序） | avian 语义以 headless 用例逐条钉死（T2 验收①②）；桥不过滤不排序（透传语义），边角文档化；模板示例避开依赖边角顺序的写法 |
| **游戏工程 patch 的存量工程覆盖**（老工程启用模块缺 patch→编不过） | scaffold 只管新工程；存量路径=Edit Project Modules UI 启用→`runtime_wiring`/book 给手动两行；可选增强：模块启用 operator 检测并自动补 patch 行（T1 程序裁量，超面则文档化） |
| **导出腿的 avian 编译**（dist 构建=游戏工程 cargo build，avian 全家桶进发布链） | 格 9 异目录启动全链验证（T07 heavy 链）；`--locked` 四入口统一（T07-T2）已保证 lock 树稳定；导出体积增量记录进报告 |
| **回滚** | T0=纯调查+book 一行（revert 无痕）；T1=解锁段（modules.json 摘行+patch+扩展注册+模板 wiring+测试反转——revert 即回「不能启用」现状，物理场景文件是用户数据、unresolved 保底语义兜底旧工程零残留）；T2=runtime 新模块+模板扩展（加法，revert 即回无触发器现状，场景里 Sensor/CollisionLayers 是 avian 组件、保底保留）；T3=纯矩阵+文档。全程零场景格式变更、零 PIE 协议破坏（投影排除清单不动）——与 T05-T09 同款最大回滚保险 |

---

## 五、与 T01-T09 已建设施的衔接

1. **T08（配置资产族）=受力正确的作者态载体**：`GameConfig.gravity` 从「手动位移参数」升级为「avian
   Gravity Resource 初值」（ConfigLoader→Startup 注入，T08 机制零改动的新用法）；三态一致链
   （重启/Play/导出）在格 4/9 直接复用；层命名资产（决策 4-B）将来同族。
2. **T09（InputActions）=触发链的驱动源**：拾取链验收用 `input.key W` 合成输入驱玩家（捕获态转发
   链零改动复用）；`TriggerEvents` 与 `GameActions` 构成「输入状态+世界状态」的双 Resource 消费面，
   模板 doc 并排教学；PlayerMarker 物理化时 T09 矩阵复跑是放行条件（决策 6）。
3. **T06（PIE/Stop 铁证）=行为断言与零污染通道**：`jackdaw/pie`/`scene_snapshot` 两帧差承担全部物理
   行为断言（不穿地/受力/拾取）；Stop 铁证在格 12 回归（物理组件流不写回 authored AST 的既有保证）。
4. **T07（导出/manifest）=Play=导出一致腿**：格 9 异目录启动复用 heavy 链；avian 进 dist 的 lock
   稳定性吃 `--locked` 四入口统一红利；体积增量入报告。
5. **T02/T03（Inspector/undo）=物理组件编辑与工具提交的地基**：CollisionLayers bitmask 编辑走 feathers
   既有特判；Physics Tool 的 Space 提交=单 undo span（`with_history_span`，T03 体系内）；physics 分类
   chips 是 `register_inspector_chip` 机制（T02 分类显示的扩展形态）。
6. **T05（引用稳定性）**：物理组件全部是内联组件（无资产引用），场景 rename/move 零交集；格 10 重开
   一致顺带回归其往返面。
7. **T-QT/MCP 工具层**：25 工具直接构成验收驱动面（`component.*`/`physics.*` operator/`input.*`/
   `scene_snapshot`/`jackdaw/{pie,export,history,wait}`）；F6 事件断言走行为落点（组件计数）零新工具，
   预案留档（MCP 优先流程裁量）。
8. **对 T11-T20 的奠基**：T11 玩家控制器=物理玩家身（模板 capsule 碰撞体+Velocity 驱动的预演）+
   「新工程放玩家+地面即玩」直接吃模块默认启用；T20 示例游戏（拾取/胜负/重开）消费 TriggerEvents
   全链；T22（2D Tilemap 碰撞）若首款游戏 2D 升 P1 时再评估 avian 2D 面（本任务 3D 域，2D 零涉）。
9. **上游对齐账**：unavailable 摘除+物理 crate 并主 workspace 是对上游 jackdaw 设计的有意偏离
   （决策 2），在 book developer 节与 CHANGELOG 类面写明动因（bevy 0.20 发布后源统一成本已低于
   workspace 隔离收益）；avian patch 守卫是长期防线。
10. **分支与行号基线**：本方案行号基于 main e0df824e（T09 闭环点）。T10 从 main 拉
    `loop/t10-physics`（T0/T1/T2/T3 分段续用同分支族，T06/T08/T09 先例）；T0 在 main 工作区执行、
    不建分支（探针临时物事后复原）；行号按符号名重定位（矩阵证据均已给符号名）。
