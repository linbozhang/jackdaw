# T11 最小玩家控制器模板 — 实施方案

> 策划产物（2026-10-24，基于本地 main **7dc1f7a8**（T10a 闭环点 = T10b 之前的最新 main）全量代码
> 只读调研（含 avian 0.8.0 registry 源码实查）；不建分支、不改代码）。需求来源：
> `loop/plans/roadmap-game-dev.md` T11（P1 第五项，T08/T09/T10 已闭环，T10a 已闭环，T10b 挂账中）。
> **验收原文**（roadmap 第 25 行，已逐字核实）：「最小玩家控制器模板：**复用 CameraRig**，开箱即用
> 玩家（移动/转向/跳跃/碰撞/跟随）。**验收=新工程放玩家+地面即玩；关键参数 Inspector 可调。**」
> 拆解（策划口径，供矩阵与验收对齐）：「复用 CameraRig」=复用 `crates/jackdaw_camera_rig`（上游
> 设计即「ships inside games」的双端 crate，见事实一），**禁止**另写一套跟随相机；「开箱即用玩家」
> =新工程模板自带的玩家在 Play/`cargo run`/导出三态下即具备五能力；「放玩家+地面即玩」=两条链路
> 同时成立——①模板开箱链（新工程零操作即玩）+②编辑器摆放链（Add Entity 放玩家实体+Add Component
> `PlayerMarker`/`PlayerController`+Camera Rig 挂玩家下+地面，Play 即玩）；「Inspector 可调」=
> 关键参数（移动速度/跳跃力/相机距离与灵敏度等）在编辑器 Inspector 组件字段可编辑、Play 生效、
> 保存重开一致（T02 三处一致口径）。
> buglist 玩家/游戏相机域**零直接条目**（全量扫描：R13/R14 是编辑器视口旋转 gizmo 域，W4 是截图
> 观察相机，Y33/Y35/Y37/N12 是 BRP 域，见 §一重叠表）；缺陷主体是本方案新发现的 **C1-C9**（C 系：
> Camera/Controller，避开 buglist R/Y/W/A/N 系、T08 P 系、T09 I 系、T10 F 系）。
> 真机口径：全程按 `loop/qa/t10b-crash-workaround.md` 绕行（direct run 用 `cmd start /B`，PIE 用
> `WGPU_BACKEND=dx12`，判活走 BRP `jackdaw/status`+事件日志双通道）——T10b 根因调查挂账不阻塞
> 本任务（环境归因已裁定）。

---

## 0. 架构事实（核实结论，方案的地基）

**「玩家控制器」在 jackdaw 里 = 一个双端就绪但游戏侧未接线的相机 crate + 一个 Transform 版演示
marker + avian 0.8 现成的 character-controller 工具集**。六条事实决定方案走向：

- **事实一：CameraRig 是上游设计好的「双端复用」crate，不是编辑器视口 fly 相机**。
  `crates/jackdaw_camera_rig`（`src/lib.rs` 全 460 行实读）由三部分组成：
  - **作者态组件**：`CameraRig { mode: ThirdPerson/FirstPerson, distance, pitch, eye_height,
    sensitivity }`（`EditorCategory("Camera")`，Inspector 可调）+ `ActiveCameraRig`（启用标记，
    **保存链明确排除**——`src/scene_io/mod.rs:78`「persisting it plants a rig that fights those
    systems」）+ `CameraLook { yaw, pitch }`（运行态，doc 明言「games may write `yaw` directly」）。
  - **编辑器侧**：`JackdawCameraRigTypesPlugin`（类型注册）已在编辑器 App 默认接线
    （`src/lib.rs:716-722`，`camera_rig` feature 默认开）；Add Entity「cameras > Camera Rig」模板
    （`src/entity_ops.rs:716-724`——注意 spawn 的是**顶层实体无 parent**）、hierarchy/Inspector
    Orbit 图标（`src/hierarchy.rs:191`、`src/builtin_extensions.rs:53-54`）。
  - **游戏侧**：`JackdawCameraRigPlugin`（运行时驱动）——`activate_lone_rig`（单 rig 自动激活/
    多 rig 让位/Gated 三态）→ `materialize_active`（插 `Camera3d`+`CameraLook`）→ PostUpdate
    `drive_camera_rig`（after `TransformSystems::Propagate`：读 parent `GlobalTransform`，世界系
    计算环绕/第一人称位姿，RMB 按住 + `AccumulatedMouseMotion` 驱动 look）。**相机挂玩家子实体
    即得「跟随」**——这就是「复用」的直接形态。crate 内嵌测试 7 件（激活/物化/环绕解耦/眼高）。
  - **bevy 依赖最小**（`Cargo.toml`：default-features=false，仅 std/serialize/reflect_auto_register/
    bevy_camera），注释明言「this crate ships inside games, so its bevy features unify into theirs」。
  - 区分：编辑器视口 fly（`EditorAction::CameraForward` 等，`keybinds.rs:98-104`）是编辑器会话
    相机系统，与 `jackdaw_camera_rig` **零交集**——验收句「复用 CameraRig」指后者（组件名同名
    仅此一家）。
- **事实二：CameraRig 的 PIE 链路已经半通**。①windowless PIE 帧捕获消费它：
  `crates/jackdaw_runtime/src/pie_frames.rs:174`（`With<CameraRig>, With<ActiveCameraRig>`，
  windowed fallback 在 active rig 下 spawn 捕获相机）；②windowless 相机重定向把所有 window 相机
  指到捕获图（`pie_windowless.rs:127` `retarget_cameras`——场景相机/rig 相机都覆盖）；
  ③PIE 投影认知它：`jackdaw_pie_protocol/src/snapshot.rs:49-54` skip 相机内部件并注释「编辑器从
  CameraRig 和 Projection 重建相机状态」+ `src/pie_projection.rs:60` skip `ActiveCameraRig`。
  **但游戏模板没有 `JackdawCameraRigPlugin`**：编辑器摆的 Camera Rig 实体在 Play 中——CameraRig
  类型未在游戏侧注册（模板代码零 camera_rig 引用，schema 提取不到该类型）→ 场景组件以
  UnresolvedTypes 保底保留（T05 保底）→ 不物化不驱动 → **编辑器摆放链「跟随」落空**（C1）。
- **事实三：游戏工程已传递依赖 camera_rig，但 Rust 层不可用**。`jackdaw_runtime` 的
  `jackdaw_camera_rig` 是 **optional 依赖，仅 `pie` feature 拉入**（`crates/jackdaw_runtime/
  Cargo.toml`：`pie = ["dep:jackdaw_camera_rig", ...]`）；而新工程 runtime features 固定含
  `"pie"`（`crates/jackdaw_scaffold/src/lib.rs:2660` `for always in ["terrain", PIE_FEATURE]`）——
  即**依赖树里已经有它**（暖工程实查：`jackdaw_runtime = { features = ["terrain","pie"] }`），但
  模板 lib.rs 不能 `use`（传递依赖不可直接引用），runtime `prelude`（`lib.rs:162-173`）也**没有
  re-export**。接线路径二选一：runtime 无条件依赖+prelude 导出（决策 2-A），或 scaffold 给游戏
  Cargo.toml 显式注入依赖（决策 2-B，`jackdaw_dep_requirement` 机制现成，`lib.rs:2954-2956`）。
- **事实四：avian 0.8 的 character controller 是 `MoveAndSlide` SystemParam 工具集（非旧版挂件
  式 KinematicCharacterController）**（registry 源码 `character_controller/move_and_slide.rs`
  实读，进 avian prelude）：`move_and_slide(collider, pos, rot, velocity, dt, config, filter,
  on_hit) -> MoveAndSlideOutput { translation, projected_velocity }`（sweep+slide+depenetrate 一体，
  `MoveAndSlideConfig` 控迭代/皮肤宽度），辅以 `depenetrate`/`cast_move`/`intersections`/
  `project_velocity`。**官方 doc 示例就是「自建 `CharacterController { velocity }` 组件 +
  `perform_move_and_slide` 系统」**——这正是 T11 模板该教的形态。配合：`RigidBody::Kinematic`
  （`dynamics/rigid_body/mod.rs:298-304`：「不受外力/碰撞影响、引擎不改其组件、全手控」，T10 已给
  模板玩家装上）；`LinearVelocity` 已注册 Inspector（`jackdaw_avian_integration/src/lib.rs:177`）；
  `register_avian_types` 24 类型已进游戏 schema（T10 链）。
- **事实五：T09/T10 模板的玩家是「演示 marker」，五能力只有一能力半**。现状
  （`templates/game/src/lib.rs.template:242-283` + scaffold 占位 `:2810-2825`）：
  `PlayerMarker`（空标记）+Kinematic capsule collider（radius 0.35/height 1.0）+`PickupCount`，
  `move_player_by_actions`：`transform.translation.x += move.x * 0.1`（**无 dt，帧率相关**；
  速度硬编码）；Jump/Interact/Pause 仅 `info!`（**无 y 动力学、无地面检测**）；Look 驱
  `rotate_y(-look.x*0.01)`（yaw 雏形在）。Kinematic 直写 Transform → **穿墙**（T10 的 kinematic
  只为 sensor 检测服务，碰撞响应为零）。玩家**无 mesh**（编辑器/游戏里都看不见）。模板自带初始
  `assets/scene.bsn`（固定机位 Main Camera + Sun——**与玩家跟随相机会双相机并存**，见 C6）。
  正向面：`spawn_stage`/`spawn_pickups`/`collect_pickups`（拾取链 T10 已验）、`GameConfig`
  （player_health/move_speed/gravity+ConfigPlugin 三态）、`InputActionsPlugin` 五动作（Move=
  Axis2D、Look=Delta2D、Jump/Interact/Pause=Button，`game_input.rs` 实读）全部在场可复用。
- **事实六：编辑器摆放链的组件面已经天然成立**。模板类型经 `reflect_auto_register`+schema 提取
  进 Add Component（T02「零注册码」模式，SpinningCube 同族先例）；`PlayerMarker`/新
  `PlayerController` 同理；Add Entity「Camera Rig」+ hierarchy 拖拽父子化（T03 改父级域）+
  physics.enable（地面一步静态化）全部就绪。**「放玩家+地面即玩」缺的只是游戏侧驱动链**（C1-C3）
  与参数面（C5），零编辑器机制新需求（决策 8 的 UI 增强为可选）。

---

## 一、现状与缺陷矩阵

### A. 相机与跟随（验收词「复用 CameraRig/跟随」）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **C1** | 🔴 | **游戏侧零相机链路**：模板无 `JackdawCameraRigPlugin` 接线、runtime 无 re-export、游戏 Cargo.toml 无直接依赖——编辑器摆的 Camera Rig 在 Play 中 UnresolvedTypes 保底不驱动；模板玩家无跟随相机；windowless PIE 的 rig 帧捕获在「游戏侧类型未注册」时同样 query 不中。「跟随」与「复用 CameraRig」验收腿落空 | 事实二/三；`lib.rs.template` 零 camera_rig；暖工程 Cargo.toml 实查 |
| **C6** | 🟡 | **双相机并存边角**：模板初始 scene.bsn 的固定机位 Main Camera（Camera3d）与玩家 rig 物化的 Camera3d 并存——两台 active 相机无 order 区分，windowless 下同渲一个捕获图（叠加/覆盖顺序不定），窗口模式下视口互抢 | `templates/game/assets/scene.bsn:7-14`；`camera_rig/src/lib.rs:146-176`（materialize 不排他） |
| **C7** | ⚪ | **Look 双通道写冲突**：CameraRig 驱动用 RMB+`AccumulatedMouseMotion` 写 `CameraLook`，T09 的 Look 动作（MouseMotion 绑定）读**同一事件流**——PIE 转发的合成 MouseMotion 两路都活，RMB 按住时双写=双倍转速（独立跑时同源同理） | `camera_rig/src/lib.rs:196-241`；`game_input.rs` MouseMotion 绑定；T09-T2 §三⑤（input.motion→Look 链） |

### B. 玩家控制器机制（验收词「移动/转向/跳跃/碰撞」）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **C2** | 🔴 | **控制器零机制**：移动帧率相关（`x += move.x * 0.1` 无 dt——60Hz 与 144Hz 手感不同）、速度硬编码不可调；跳跃是 `info!("Jump!")` 占位——无 y 速度、无重力积分、无地面检测；Jump 动作有了（T09）但无消费面。「跳跃」验收腿落空 | `lib.rs.template:259-283` |
| **C3** | 🔴 | **玩家碰撞无响应**：Kinematic 直写 Transform，撞静态体/墙直接穿过（T10 kinematic 的语义只服务 sensor 触发与推挤 dynamic）；模板 stage 无墙可撞（连「撞墙」的演示面都没有）。「碰撞」验收腿（撞墙停/贴墙滑）落空 | avian `RigidBody::Kinematic` 文档（事实四）；`module_physics_demo` 的 stage 仅地面 |
| **C4** | 🟡 | **玩家不可见**：PlayerMarker 无 mesh 无材质——编辑器场景与游戏画面里玩家都不存在视觉体，「放玩家」无从谈起、真机断言也只能靠 Transform 数字 | `lib.rs.template:246-252`（spawn 无 Mesh3d） |
| **C5** | 🟡 | **参数无作者态载体**：玩家移速/跳跃力无组件字段（硬编码 0.1）；CameraRig 的 distance/pitch/sensitivity 组件可调但游戏侧不生效（C1 依赖）；GameConfig.move_speed 语义已被 falling cube 占用（模板自己的教学纪律「one value changes one behavior」，`lib.rs.template:211-214`）。「关键参数 Inspector 可调」缺玩家侧载体 | 事实五 |
| **C8** | ⚪ | **移动参考系未定义**：现状世界系直写（x/z）；第三人称惯例=相机相对（W=相机前方）+玩家朝向随移动方向/相机 yaw——需要模板层面定死一套并写进 doc | `lib.rs.template:263-267` |
| **C9** | ⚪ | **多玩家/多 rig 边角**：模板代码 spawn 的玩家与编辑器摆放的玩家并存（Query 双驱动——语义 OK）；但 CameraRig 的 lone-rig 便利在「模板 rig+用户 rig」两 rig 时**全部不激活**（`activate_lone_rig` 设计使然），首玩用户相机会哑 | `camera_rig/src/lib.rs:123-140` |
| — | ✅ | **正向资产（不用重建）**：camera_rig crate 全套（组件+驱动+激活三态+7 测试）；MoveAndSlide SystemParam+avian prelude；T09 五动作+改绑链；T10 物理身（Kinematic capsule）+拾取链+重力注入；T08 GameConfig 三态族；编辑器 Add Entity Camera Rig/physics.enable/三处一致/undo；PIE 投影与帧捕获的 rig 认知；MCP 25 工具驱动面 | 事实一-六 |

**统计：🔴 3（C1、C2、C3）｜🟡 3（C4、C5、C6）｜⚪ 3（C7、C8、C9）｜✅ 六块地基**

### buglist 重叠表（玩家/相机/跳跃/jump/controller 域全量扫描）

| 条目 | 一句话 | T11 处置 |
|---|---|---|
| R13/R14 | 编辑器视口鼠标旋转体感/旋转轴反向 | **不吸收**：视口 gizmo 域（编辑器会话相机），与游戏 CameraRig 零交集。备注维持 |
| W4 | 截图观察相机 gizmo 熄灭 | **不吸收**：camera_capture 域。备注维持 |
| Y33/Y35/Y37/N12 | BRP CORS/Content-Length/PIE 投影性能/实体域不通 | **不吸收但知悉**：T11 真机断言继续走 scene_snapshot 投影+direct run BRP（T10 同款域选法）；跳跃多帧采样吃 Y37 的投影性能账（采样密度控制） |
| Y6 | 坐标轴指示器物理/逻辑像素 | **不吸收**：视口 UI 域。备注维持 |
| 其余 | 无玩家控制器/游戏相机域条目 | 无动作 |

> 如实报告：该域 buglist 零直接条目——玩家控制器此前从未存在（T09 的 PlayerMarker 是输入动作的
> 演示载体），没有用户可踩出的 bug；T11 缺陷主体是本方案新发现的 C1-C9。

---

## 二、分任务拆解（T1/T2/T3；无 T0 探针）

> **无 T0 的理由**（对齐 T10 的 T0 逻辑——探针只为消除「版本未知数」）：T11 的两大依赖面都没有
> 未知数——①camera_rig 是第一方 crate、七件测试在主 CI 常绿、bevy 依赖最小且与游戏侧 feature
> 统一（事实一）；②MoveAndSlide 与 T10 已用的 avian 0.8 同 crate 同 patch 链（零新源）。若 T1
> 实做中发现 camera_rig 与游戏 feature 统一有问题（如 bevy_camera feature 冲突），按偏差流程记档
> 回报，不设前置探针。

### T1「玩家控制器核心 + CameraRig 接线 + 模板改造」（C1+C2+C3+C4；决策 1/2/3/4）

**目标**：模板玩家从「演示 marker」升级为「最小角色控制器」——Kinematic+MoveAndSlide 的
移动/跳跃/碰撞滑动、CameraRig 跟随相机（复用 crate）、玩家可见、三态（Play/`cargo run`/导出）
行为一致；T09/T10 已验链路不破坏（放行条件见验收标准末条）。

**改动面预估**：
1. **CameraRig 游戏侧接线（C1，决策 2 按主控裁定实施）**：
   - 路线 A（runtime re-export）：`jackdaw_runtime` 的 `jackdaw_camera_rig` 从 pie-gated
     optional 改无条件依赖（core_deps 守卫不涉——第一方 crate；bevy 依赖最小实查），prelude
     导出 `JackdawCameraRigPlugin`（与 `GameActions`/`TriggerEvents` 家族并列）；模板
     `GamePlugin::build` 一行 `.add_plugins(JackdawCameraRigPlugin)`；
   - 路线 B（scaffold 显式依赖）：`module_crate_lines`/固定注入给游戏 Cargo.toml 写
     `jackdaw_camera_rig = { ... }`（`jackdaw_dep_requirement` 现成）+ 模板 use 该 crate；
   - 两条路线模板侧形态等价（一行插件接线）；存量工程（如暖工程）A 免 Cargo 改动、B 需加一行
     ——写入 book 迁移注记；
2. **玩家控制器组件与系统（C2+C3，决策 1-A 实施）**：模板新增教学段（~60-80 行，对齐
   avian 官方 doc 示例形态）：
   - `PlayerController { move_speed: f32, jump_speed: f32 }`（`#[reflect(Component, Default)]`
     +`EditorCategory`——C5 的组件载体；`Default`：move_speed 4.0、jump_speed 4.5 量级，程序
     定稿）；`PlayerVelocity(Vec3)` 运行态组件（或内嵌 Local——选组件：投影可断言 y 轨迹）；
   - `move_player` 系统（替换 `move_player_by_actions` 的 Transform 直写）：读 `GameActions`
     （Move=Axis2D、Look=Delta2D、Jump=Button）→ 相对相机 yaw 合成期望水平速度（C8 定死一套：
     建议 yaw 以 `CameraLook` 为单一真相，玩家 Transform 朝向=移动方向平滑转向或=相机 yaw——
     程序裁量，doc 写明）→ 重力积分（读 `GameConfig.gravity`？不——重力已由 T10
     `apply_gravity_from_config` 注入 avian `Gravity` Resource，玩家 y 积分读同一 GameConfig
     值，doc 写明两消费者同源）→ Jump just_pressed 且地面检测通过 → `move_and_slide(...)`
     一体完成碰撞滑动+depenetration，输出写回 Transform+保存 `projected_velocity`；
   - 地面检测：`MoveAndSlide::cast_move` 向下短投（或 on_hit 法线判定——程序裁量，教学注释
     写清取舍）；
   - **Look→CameraLook 桥**（决策 3）：模板系统把 `GameActions.value("Look")` 写进玩家/相机
     的 `CameraLook { yaw, pitch }`（crate doc 明言外部可写）；C7 冲突按决策 3 裁定处理；
   - Kinematic capsule 保留（T10 形态不动），`SpatialQueryFilter::from_excluded_entities`
     排除自身；
3. **模板场景升级（C4+C6，决策 5）**：`spawn_player` 补 capsule mesh+材质（可见）；同帧 spawn
   Camera Rig 子实体（`CameraRig::default()`+`ChildOf(player)`——跟随即装即用，lone-rig 自动
   激活）；初始 `assets/scene.bsn` 的固定 Main Camera 按决策 5 处置（A 删除=模板 rig 唯一相机 /
   B 保留不动+rig 相机 order 压制）；`spawn_stage` 加一面矮墙（或 spawn_wall——给「撞墙滑」
   演示面与真机断言锚点，C3）；doc 头部新增「Player controller」导览段（组件/相机/跳跃碰撞
   教学导览+多相机/多 rig 边角说明 C9）；
4. **scaffold 占位机制扩展**：玩家控制器段是纯模板代码还是 physics-gated？**决策 1-A 下依赖
   MoveAndSlide（avian）——挂 `{{module_physics_*}}` 占位族**（无物理工程退回 Transform 版
   移动+无跳跃，与 T10 手动重力 fallback 同构——`module_physics_statements` 等占位函数扩腿，
   teaches 测试同步扩断言（双形态均编译+行为面在场/退场））；
   CameraRig 接线**不**physics-gate（crate 无物理依赖，无物理工程也该有跟随相机）。

**验收标准（可执行可复现）**：
- [ ] headless 红→绿①（相机接线）：无 `JackdawCameraRigPlugin` 时 rig 实体无 Camera3d/不移动
  （红——用场景带 CameraRig 的 world 模拟编辑器摆放链）；插件在+rig 挂移动 parent 下 → rig
  世界位随 parent 移动（绿——跟随的机制层）；编辑器摆放链模拟：场景 bsn 带 CameraRig 实体+
  游戏加载 → 组件 resolved（非 UnresolvedTypes）且驱动（C1 红绿主证）；
- [ ] headless 红→绿②（碰撞）：无 MoveAndSlide 时玩家直写 Transform 穿墙（红：撞墙位=穿过后
  位置）；接入后同输入撞墙——沿墙滑动（法向位移≈0、切向保留）+depenetrate 后零穿透（绿）；
- [ ] headless 红→绿③（跳跃）：Jump 按下 → y 速度=jump_speed 初值、轨迹抛物线（离散积分
  断言 v×dt−g×dt²）；空中再按不二段跳；落地后 y 稳定（两帧差<ε）且可再跳；
- [ ] headless（帧率无关性）：手动 Time 两档 dt 驱动同输入，位移差在浮点容差内（C2 红绿的
  数学断言形态，T08 C4 同款方法学）；
- [ ] 模板：scaffold teaches 测试族扩展（PlayerController/MoveAndSlide/rig spawn needle+
  无物理形态退场断言）+暖工程实编 `cargo build` 通过（T10 同款活体证据）；
- [ ] **T09/T10 回归（放行条件）**：T09 矩阵的行为格复跑（格 2/4/9/10——Move/Look 的 dz 断言
  按「速度×dt」新语义重新校准数字，**量纲重新钉死而非放宽**）；T10 拾取链复跑（玩家移动系统
  替换后 PickupCount 0→3 端到端）；
- [ ] quick 四门（fmt/clippy 全仓/单测/集成——T09-T2 口径）。

**测试设计**：模板内嵌测试随 teaches；guards 新 `tests/guards/player_controller.rs`（真 avian
引擎+ManualDuration：碰撞滑动/跳跃轨迹/地面检测/帧率无关四件）；真机脚本沉淀
`loop/qa/t11-player-live.ps1`。**buglist 吸收**：无打钩（C 系新发现）。

### T2「参数面 + 编辑器摆放链真机」（C5+C6+C9；决策 6/7）

**目标**：「关键参数 Inspector 可调」与「放玩家+地面即玩」的编辑器侧闭环——PlayerController/
CameraRig 组件字段在 Inspector 编辑→Play 生效→保存重开一致；Add Entity 摆玩家链真机走通。

**改动面预估**：
1. **参数三态面（C5）**：`PlayerController` 字段（move_speed/jump_speed）与 `CameraRig` 字段
   （mode/distance/pitch/eye_height/sensitivity）Inspector 编辑（feathers 既有字段面，零新
   编辑器机制）；验证链：编辑→Play 行为变化（速度翻倍=位移速率精确翻倍的两帧差断言；
   distance 改=rig 世界位半径变化）→save→重开一致（T02 三处一致口径：组件面+存档面+行为面）；
   Resources 面板不涉（组件态非 Resource 态）；
2. **编辑器摆放链真机（验收句主体）**：Add Entity（Cube/Capsule 形态）→ Add Component
   `PlayerMarker`+`PlayerController` → Add Entity「Camera Rig」→ hierarchy 拖到玩家下 →
   地面（physics.enable 或 Brush+静态化）→ Play：玩家可动可跳可撞、相机跟随——**「放玩家+
   地面即玩」的字面链真机铁证**（每步 BRP 驱动可断言：`component.add`/`selection.set`/
   hierarchy 拖拽或 parent set operator/T03 改父级域）；
3. **多相机/多 rig 边角收口（C6+C9）**：按决策 5 裁定验证双相机行为（删或压制后：模板 rig
   唯一渲染相机的截图/像素或 BRP 相机清单断言）；「用户再摆一个 Camera Rig」→ lone-rig 不
   激活的行为如实文档化（教学 doc+book：多 rig 需手加 `ActiveCameraRig`——该组件 Inspector
   可加（已注册））——不引入新机制（C9 挂 backlog 与否按决策 7）；
4. **真机三通道**：PIE（`WGPU_BACKEND=dx12` 绕行口径）/direct run（`start /B`+游戏 BRP 15702，
   T10 通道复用）/导出（`game.export`→异目录启动——行为=PIE，T07 heavy 链）；跳跃轨迹/贴墙
   滑动/相机跟随的多帧采样断言（scene_snapshot 投影：玩家 Transform y 序列+rig 实体 Transform
   跟随差=常量 offset）；
5. **Look 双通道验证（C7）**：capture 态 RMB 按住+`input.motion` 双注入 → yaw 增量与单通道
   对照，按决策 3 裁定断言（若模板桥 gated RMB：RMB 时零叠加）。

**验收标准**：
- [ ] 真机①（参数）：move_speed 1.0→2.0 编辑→Play 位移速率精确翻倍（两帧差数学断言）；
  distance 10→5 → rig 距玩家世界距离=5（投影断言）；save→重开→值与行为一致（三处一致）；
- [ ] 真机②（摆放链）：上述编辑器链全 BRP 驱动走通，Play 中玩家动/跳/撞墙滑/相机跟随四行为
  各有投影或日志证据；
- [ ] 真机③（三通道一致）：direct run 跳跃轨迹 y 峰值≈理论 v²/2g（重力 -9.81 数字级容差）；
  导出 dist 异目录启动同行为（环境事件降级口径按 T10 格 9 先例记档）；
- [ ] 真机④（边角）：双 rig 不激活的哑相机行为如实断言（投影无 Camera3d 物化）；模板 rig+
  用户 rig 场景 doc 注记在案；
- [ ] C7 双通道：按裁定形态的断言一格（无叠加或有叠加且文档化）；
- [ ] T02 回归：PlayerController 字段编辑的提交链/脏标/undo（切实体不写错目标——T02 🔴 教训域）；
  T03 回归：hierarchy 拖 rig 入玩家的 undo 单记录；
- [ ] quick 四门。

### T3「验收矩阵 + 文档收尾」（C8 文档腿+全任务终验）

**目标**：验收句两铁证（「新工程放玩家+地面即玩」/「关键参数 Inspector 可调」）矩阵化终验；
book 玩家控制器章节；roadmap 勾选。

**改动面预估**：
1. **真机验收矩阵**（截图+日志留档，模板工程+编辑器链双 fixture）：

| # | 场景 | 期望 |
|---|---|---|
| 1 | 新工程开箱即玩 | scaffold 新工程 → Play/`cargo run`：玩家可见、WASD 动、Space 跳（落地可再跳）、撞墙滑、相机跟随（T1 链复验+e2e 产物断言模板新段在场） |
| 2 | **放玩家+地面即玩（摆放链）** | 空场景 Add Entity 玩家（+PlayerMarker/PlayerController/相机 rig 挂靠+地面）→ Play 即玩（T2 链复跑，验收句字面） |
| 3 | 移动（帧率无关） | 两档 dt headless 数学断言真机侧抽查（速度改参数行为同变） |
| 4 | **转向/Look** | `input.motion`→yaw 量纲断言（T09 格 4 新语义）；RMB 通道行为=决策 3 裁定形态 |
| 5 | **跳跃** | y 轨迹采样：峰值/落地时刻/落地后静止；空中无二段跳；jump_speed 参数化复验 |
| 6 | **碰撞** | 走向墙：法向停（位移≈0）切向滑（保留）；高速（move_speed 加倍）不穿透；玩家推 FallingCube（kinematic→dynamic 语义） |
| 7 | **跟随（复用 CameraRig）** | rig 世界位−玩家位=常量 offset（多帧采样）；pitch/distance 参数即时生效；FirstPerson 模式切换（mode 字段编辑）行为面抽查 |
| 8 | **Inspector 可调·玩家参数** | move_speed/jump_speed 编辑→Play 精确行为变化→save→重开一致（T02 三处一致） |
| 9 | **Inspector 可调·相机参数** | CameraRig 五字段同链（distance/sensitivity 行为断言；eye_height FP 模式断言） |
| 10 | 三态一致（Play=cargo run=导出） | 同工程三通道同行为（导出腿 T10 格 9 降级口径先例：环境事件如实记档） |
| 11 | Stop 铁证回归 | Play（玩家跑动/相机驱动中）→stop→场景 SHA 不变+temp 清理（rig Transform 每帧被游戏驱动——文档态零污染的回归面） |
| 12 | 无物理形态回归 | physics 关闭工程：Transform 版移动 fallback 编译+行为（教学退场断言复跑） |

2. **book 文档**：新章 `book/src/user-guide/player-controller.md`（SUMMARY 排 game-input 后）：
   PlayerController/PlayerVelocity 组件导览、CameraRig（两模式五参数/挂玩家下/多 rig 边角）、
   跳跃与碰撞滑动的机制说明（MoveAndSlide 一句话+avian 文档链接）、移动参考系（C8 定案）、
   参数调法（Inspector 直调 vs GameConfig 边界——玩家实体级参数=组件、全局参数=config，对齐
   模板既有教学纪律）、摆放链 step-by-step；`game-input.md` 交叉引用更新（Look 消费面变化）；
   open-challenges 视决策 7 增补（C9 多 rig 便利化若挂账）；
3. **工具面核对（MCP 优先原则）**：现有 25 工具+BRP **预判足够**——`component.add/set`
   （PlayerController/CameraRig/ActiveCameraRig）、`input.key/motion`（移动/跳跃/Look/RMB）、
   `scene_snapshot`（位移/y 轨迹/rig 跟随投影断言）、`selection.set`（T06 后在场，hierarchy
   链）、`jackdaw/{pie,export,wait,history}`；**唯一预判评估项**=跳跃时序控制（按住时长影响
   初速？——首版 jump_speed 恒定初速则 `input.key` press/up 两拍即可）与 hierarchy 拖拽的 BRP
   可达性（改父级 operator 在 T03 域——若合成拖放不可达，用 `component.set ChildOf` 或
   parent-set operator 直调替代，T10 格 2 拖放不可达的先例口径：记档+operator 链承担）；
   若真机卡死在工具面（如 ChildOf 的 component.set 被拒），按 MCP 优先流程立项最小补面；
4. buglist 核对（无打钩预期）、roadmap T11 勾选、台账记行、C 系结案清单。

**验收标准**：
- [ ] 矩阵 12 格全过（环境降级格如实标注+替代证据链，T10 口径）；
- [ ] 全量门（fmt/clippy 全仓/单测/集成/doctests/docs，2026-10-25 升级版门禁证据标准——日志
  全文复核）；物理双包单跑维持 T10 口径；
- [ ] 用户 30 秒清单：①新工程直接 Play——看到胶囊玩家，WASD 走、Space 跳、走到墙边贴着滑、
  相机跟着转；②Inspector 把 move_speed 改 8.0、相机 distance 改 4——再 Play 明显变快变近，
  保存重开还是这俩数；③自己 Add Entity 摆一个 Cube 玩家（加 PlayerMarker+PlayerController）+
  拖一个 Camera Rig 到它下面——Play 一样能跑能跳。

**QA 清单（放行标准，全任务）**：
- [ ] T1/T2/T3 各自验收全绿；C1/C2/C3 各有机制层红→绿（C1 红证=场景 rig 在无插件游戏
  UnresolvedTypes 保留，C2 红证=两档 dt 位移差，C3 红证=穿墙位）；
- [ ] 验收句两铁证：「即玩」（格 1/2 开箱链+摆放链双 PASS）、「Inspector 可调」（格 8/9
  三处一致）各有独立证据；
- [ ] T01/T02/T03/T06/T07/T08/T09/T10 既有防线回归：T09 行为格复跑（新量纲重钉）、T10 拾取/
  不穿地复跑、T02 三处一致（格 8/9）、T03 undo（T2-3）、T06 Stop 铁证（格 11）、T07 导出链
  （格 10）、T08 配置族（gravity 双消费同源断言）；
- [ ] quick 门（T1/T2）/ 全量门（T3）；门禁证据以日志全文复核为准。

---

## 三、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **玩家物理形态（「碰撞/跳跃」的实现路线，本方案最高权重）** | A=**Kinematic+`MoveAndSlide`**（avian 0.8 官方 character-controller 工具，自写 ~60 行驱动系统：碰撞滑动+depenetration+手写重力/地面检测+恒定 jump 初速）：手感可控（不被 FallingCube 推挤、不被斜坡弹飞）、教学价值高（控制器机制全透明）、与 T10 的 Kinematic capsule 零迁移（形态不动）、headless 可测（真引擎 ManualDuration）；代价=重力/落地是游戏侧代码（两消费者与 avian `Gravity` 同源但不同路——doc 写清）。B=**Dynamic+`LinearVelocity` 驱动**：重力/碰撞全交引擎（跳跃=写 velocity.y 一行）；但玩家被 dynamic 体推挤/被压台阶挤飞、capsule 受扭（需锁轴）、移动是「施力风格」非角色控制、T10 模板 FallingCube 落玩家头上的演示场景会持续干扰。C=保持 Kinematic 直写（现状）：「碰撞」验收词落空（C3）——**否决** | **A**；B 的「引擎管重力」作为 doc 对照一句话（不做双形态）；A 的手写重力读 `GameConfig.gravity`（与 `apply_gravity_from_config` 注入 avian 的同一真相源——改一处全局生效，doc 钉死） |
| 2 | **CameraRig 游戏侧接线形态（「复用」的实现路径）** | A=**runtime 无条件依赖+prelude re-export**（`jackdaw_camera_rig` 从 pie-gated 改无条件——crate bevy 依赖最小（default-features=false 四 feature），无 render/GPU 账；prelude 导出 `JackdawCameraRigPlugin`）：模板/存量工程一行接线零 Cargo 改动、与 GameActions/TriggerEvents 家族形态统一、schema 提取自动带上类型（游戏侧类型注册链）；代价=动 runtime Cargo.toml（pie feature 的 optional dep 语义微调——pie 的注释「Frame capture … needs camera_rig」变为无条件后 pie 不再需要声明）。B=**scaffold 给游戏 Cargo.toml 显式注入依赖**（`jackdaw_dep_requirement` 现成）：runtime 零改动；代价=存量工程要手动加行、模板 use 路径与家族不统一、每工程 lock 面变化。C=模板复制 CameraRig 源码（同构借鉴）：违反「复用」字面+双份维护——**否决** | **A**（上游「ships inside games」设计的本意路径；pie feature 里 `dep:jackdaw_camera_rig` 行同步清理）；B 作为 A 实施受阻时的回落（如实记档） |
| 3 | **Look 驱动源与 C7 双写冲突** | A=**模板桥系统为真相源+crate RMB 通道退让**：GameActions.Look→写 `CameraLook`（PIE 合成与真鼠标同链，T09 已验），CameraRig 自带 RMB 驱动与桥并存会双倍转速——需要一处退让：①模板桥只在 Look 非零帧写+doc 声明「RMB 按住时叠加」接受双写（最省但有怪手感）；②camera_rig 加一叶开关（如 `CameraRig { look_from_input: bool }` 或 gate 资源——引擎侧微调一行级，违反「引擎零改动」最小化但可控）；③模板 gate：桥系统查 RMB 未按下才写（`ButtonInput<MouseButton>` 可读，零 crate 改动——**推荐**）。B=只用 crate RMB 通道（游戏里按住右键才转——不常规，且 PIE 的 capture 态 RMB 语义纠缠编辑器）。C=只用 Look 动作+fork 掉 RMB 通道（改 crate 删功能——破坏复用语义） | **A-③**（模板桥为真相源，RMB 按住帧桥让位——零引擎改动，怪手感面最小）；真机 C7 格按此断言；若 QA 实测让位逻辑有边角（RMB 抬起同帧），记档程序裁量 |
| 4 | **移动参考系与玩家朝向（C8 定案）** | A=**相机相对移动+玩家朝向=移动方向平滑转向**（第三人称惯例：W=相机前方；朝向插值 `Quat::slerp`）：手感正确；代价=转向系统多几行+「玩家 yaw」不再是真相源（CameraLook.yaw 是）。B=相机相对移动+玩家 yaw=CameraLook.yaw（转身即转视角——「坦克式」变体，省事但模型永远面向镜头侧向移动时别扭）。C=保持世界系移动（现状——与跟随相机组合手感错乱，W 不朝屏幕前方） | **A**（模板 doc 写明参考系与朝向规则；程序裁量插值速度常数；首版不做「相机自动回正」——挂 doc 已知边界） |
| 5 | **初始 scene.bsn 固定 Main Camera 处置（C6）** | A=**删除初始 Main Camera**（scene.bsn 只留 Sun/环境；模板代码 spawn 的 rig 是唯一相机）：渲染语义最干净（无双相机叠加）、即玩链直接正确；代价=失去「场景里摆固定机位相机」的现成示例（教学面由 Camera Rig 实体+book 承担）。B=**保留+rig 相机 order 压制**（Main Camera 降 inactive 或 rig order=1）：保留示例；代价=order 语义进模板心智+windowless 双渲叠加面仍在（inactive 方案规避但要动 scene.bsn 的 Camera 字段——is_active=false 是 T01 相机模板同款手法 `entity_ops.rs:702-709`）。C=不动（双相机叠加随机覆盖——现状缺陷） | **A**（新工程首玩体验决定性；「摆固定相机」教学一句 doc 指向 Add Entity > Scene Camera 模板——该模板已存在且天生 inactive） |
| 6 | **玩家参数载体（C5，「Inspector 可调」的落点）** | A=**实体级组件 `PlayerController`**（move_speed/jump_speed 挂玩家，Inspector 直调、随场景存档）+**相机参数沿用 CameraRig 组件**：与「per-entity 数字是组件、game-wide 数字是 config」的模板既有教学纪律（`lib.rs.template:41-42`）完全同构、验收句字面命中；GameConfig.move_speed 不复用（falling cube 已占语义——one value one behavior 纪律）。B=全进 `GameConfig`（新字段 player_move_speed/player_jump_speed）：New Asset 卡片统一调；代价=实体级参数全局化（多玩家不同速度不可）、Inspector 直调验收句绕路（config 卡片不是实体 Inspector）。C=双载体（组件默认+config 覆盖）：过度设计 | **A**；B 的「全局调参」诉求由 T12 HUD/T17 存档再议（届时 config 可引用组件默认——不预建） |
| 7 | **多 rig/多玩家便利化（C9）** | A=**首版如实文档化**（lone-rig 便利已有明确语义：多 rig 不激活需手加 `ActiveCameraRig`——该组件 Inspector 可加；模板 doc+book 写明）：零机制；代价=首玩用户摆第二个 rig 时相机哑（有文档无引导）。B=编辑器「Camera Rig」Add Entity 模板给一次性提示/hierarchy 哑 rig 图标（UI 增强——编辑器侧新面，超出 T11 游戏侧主体）。C=改 crate 激活语义（最近优先/命名激活——引擎侧行为变更，破坏上游 multiplayer gate 设计） | **A**；B 的最小形态（hierarchy icon 变化一行级）作为 T2 程序裁量可选项；C 否决；C9 挂 open-challenges 一句话（T20 示例游戏若需再议） |
| 8 | **无物理工程的玩家形态（模板双形态）** | A=**控制器段 physics-gated**（`{{module_physics_*}}` 占位族扩腿：有物理=MoveAndSlide 全家；无物理=退回「Transform 移动（带 dt 修正）+无跳跃+无碰撞」最小 fallback）：teaches 双形态断言（T10 同构）；代价=scaffold 占位函数+测试面扩容。B=控制器不 gate（无物理工程编译失败或运行 panic——MoveAndSlide 需要 avian）：**不可行**。C=无物理形态删除玩家 spawn（无物理工程无玩家演示）：语义断崖（输入动作五动作失去载体——T09 教学在无物理工程也要能跑） | **A**（与 T10 手动重力 fallback 完全同构的退场机制；dt 修正是顺手修复 C2 的帧率相关面） |

小定案（主控可否决）：方案内编号 C1-C9；玩家控制器组件命名 `PlayerController { move_speed,
jump_speed }`+运行态 `PlayerVelocity(pub Vec3)`；驱动系统命名 `move_player`（替换
`move_player_by_actions`——T09 doc 里对该系统的引用同步）；相机桥系统命名 `look_into_camera`；
模板矮墙命名 `spawn_walls`（stage 补两面正交墙）；「碰撞」首版=滑动+depenetration（不含台阶
攀爬/斜坡限制——MoveAndSlide 天然滑斜坡，教学如实描述）；导出体积增量记录进 T3 报告。

---

## 四、风险与回滚

| 风险 | 缓解 |
|---|---|
| **T09 已验矩阵语义漂移**（move_player 改造后 dz 断言数字变化、Look 量纲变化） | T1 放行条件=T09 行为格复跑+量纲**重新钉死**（速度×dt×敏感度的数学断言，非放宽容差）；漂移清单在 T1 报告列表报主控（T10 决策 6 同款处置） |
| **T10 拾取链/不穿地回归**（玩家移动与 stage 改动） | T1 验收含 PickupCount 0→3 复跑+落地静止复验；stage 加墙不动既有几何（地面尺寸/位置零变化） |
| **runtime 无条件依赖 camera_rig 的连锁**（决策 2-A：feature 统一/lock 面/headless 体积） | crate bevy 依赖最小实查（四 feature 无 render）；T1 首步跑 fast 门+core_deps 守卫确认；受阻回落 2-B（scaffold 注入，scaffold 侧机制现成） |
| **MoveAndSlide 教学边角**（skin_width 卡缝/斜坡滑落/高速穿透） | avian 默认 config 起步（doc 示例同款）；真机格 6 含高速（move_speed 加倍）不穿透压力格；边角如实文档化不追求平台游戏级手感（T15+ 再议） |
| **双相机叠加（C6）** | 决策 5-A 删除初始 Main Camera 根治；编辑器摆第二相机的用户行为由 order 语义 doc 钉（首版不引入自动排他机制） |
| **跳跃断言的采样通道**（BRP 就绪晚于物理启动的 T10 记档限制——首跳可能采样不全） | 跳跃断言以 direct run BRP（15702）多帧序列为主（T10 格 4 同款通道裁定）；headless ManualDuration 全轨迹断言兜底数学面 |
| **0xc0000005 环境事件复发**（T10b 挂账中） | 全程绕行口径（start /B+`WGPU_BACKEND=dx12`+双通道判活）；环境窗口恶化时按 T10 降级口径记档不虚报 |
| **scaffold_e2e 冷编时长**（模板改动触发 20-40 分钟冷编） | T1 以暖工程实编替代（T10-T2 先例）、T3 落袋一次（T10-T3 修复后链路健康） |
| **回滚** | T1=runtime 一行依赖+prelude 导出+模板段+占位扩腿（revert 即回现状，场景里的 CameraRig/CameraLook 组件在无插件侧退回 UnresolvedTypes 保底——T05 保底语义兜底零损坏）；T2=纯验证+文档；T3=矩阵+book。全程零场景格式变更、零 PIE 协议改动（投影 skip 清单不动）——与 T05-T10 同款最大回滚保险 |

---

## 五、与 T01-T10 已建设施的衔接

1. **T09（InputActions）=控制器的输入源**：五动作直接消费（Move/Look/Jump 三动作为控制器
   主体）；改绑链/死区/捕获模型全部继承；Look 消费面变化（yaw 单一真相=CameraLook）在
   game-input.md 交叉更新。
2. **T10（物理）=控制器的碰撞与触发地基**：Kinematic capsule 形态保留零迁移；MoveAndSlide
   同 crate 同 patch 链（零新源零新版本协商）；TriggerEvents/拾取链是控制器驱动后的行为验收
   面（T1 复跑）；`apply_gravity_from_config` 与玩家手写重力同源 `GameConfig.gravity`（doc 钉
   双消费者边界）。
3. **T08（GameConfig）=全局参数真相**：gravity 双消费同源；玩家实体级参数走组件（决策 6）与
   config 的边界写进教学（模板既有纪律的延续）；三态验收方法学（两帧差/精确翻倍）复用。
4. **T02/T03（Inspector/undo）=参数面与摆放链的地基**：组件字段编辑三处一致；hierarchy 拖
   rig 入玩家=改父级域单 undo；Add Component 零注册码模式（reflect_auto_register+schema）。
5. **T06（PIE/Stop 铁证）=行为断言与零污染通道**：scene_snapshot 投影断言（玩家 y 轨迹/rig
   跟随 offset）；Stop SHA 铁证在格 11 回归（rig Transform 被游戏每帧驱动的文档态零污染面）；
   windowless 相机 retarget 天然覆盖 rig 物化的 Camera3d。
6. **T07（导出）=三态③**：格 10 复用 heavy 链+manifest 断言（camera_rig 无新资产面，体积增量
   预期微小——记录进报告）。
7. **T05（引用稳定性）**：控制器全是内联组件零资产引用；场景往返（rig 挂玩家下+组件字段）在
   格 8/9 顺带回归。
8. **MCP 工具层**：25 工具预判足够（§二-T3-3 工具面核对）；跳跃时序与 hierarchy 改父级的 BRP
   可达性是两个预判评估项，卡住按 MCP 优先流程立项（不硬耗）。
9. **对 T12-T20 的奠基**：T12 HUD（血条绑数据——player_health 已在 GameConfig 待消费）、
   T20 示例游戏（玩家移动/碰撞/拾取/胜负全链= T11 玩家+T10 触发器+T12 UI 的拼装）、T15 动画
   （玩家朝向/移动状态是动画参数驱动的第一个消费者）。
10. **分支与行号基线**：本方案行号基于 main 7dc1f7a8（T10a 闭环点；T10b 若先行闭环则按符号名
    重定位——所有证据均已给符号名）。T11 从 main 拉 `loop/t11-player`（T1/T2/T3 分段续用同
    分支族，T06/T08/T09/T10 先例）；既存噪音 `.gitignore`/`buglist.md` 不触碰（提交显式
    pathspec）。

---

## 六、耗时预估

| 段 | 预估 | 大头 |
|---|---|---|
| T1 | 1.5-2 天 | 控制器系统+headless 红绿三件+T09/T10 复跑校准 |
| T2 | 1 天 | 摆放链真机+参数三态+三通道 |
| T3 | 1 天 | 12 格矩阵+book 新章+全量门（含 e2e 落袋 20-40 分钟冷编） |
