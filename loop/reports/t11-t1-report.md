# T11-T1 实施报告：玩家控制器核心 + CameraRig 接线 + 模板改造

> 任务：`loop/plans/t11-player-template.md` §二 T1（C1+C2+C3+C4；决策 1-A/2-A/3-③/4-A/5-A/6-A/8-A
> 按方案建议实施，无主控否决项）。分支 `loop/t11-player`（自 main 7dc1f7a8）。
> 门禁日志归档 `loop/reports/t11t1_*`；真机证据 `loop/t11t1-live/`（summary/transcript/游戏日志）
> 与 `loop/qa/t11t1-live.ps1`（每腿独立冷启动，cmd start /B 口径，全程未设 WGPU_BACKEND）。

## 一、范围逐项与产品改动（8 文件，+461/−53）

1. **CameraRig 游戏侧接线（C1，决策 2-A）**：`jackdaw_runtime` 的 `jackdaw_camera_rig`
   从 pie-gated optional 改**无条件依赖**（Cargo.toml，pie feature 内 `dep:` 行移除），模块级
   re-export `CameraRig/CameraMode/CameraLook/ActiveCameraRig/JackdawCameraRigPlugin/
   JackdawCameraRigTypesPlugin` 并入 **prelude**（与 GameActions/TriggerEvents 家族并列）；
   模板 `GamePlugin::build` 一行 `.add_plugins(JackdawCameraRigPlugin)`（不 physics-gate）。
   存量工程（暖工程）零 Cargo 改动即得类型解析。
2. **PlayerController 组件+驱动系统（C2+C5 载体，决策 1-A/6-A/4-A）**：模板新增
   `PlayerController { move_speed: 4.0, jump_speed: 4.5 }`（Reflect+`EditorCategory("Actor")`，
   GameConfig 式手写 Default）与运行态 `PlayerVelocity(pub Vec3)`（physics 形态内）；
   `move_player`（替换 `move_player_by_actions`）= avian 0.8 **MoveAndSlide SystemParam**
   官方示例形态：`move_direction`（相机相对，`CameraLook.yaw` 单一真相，单位长度钳制）→
   重力积分（读 `GameConfig.gravity`，与 `apply_gravity_from_config` 同源）→ 下投 0.1 m
   地面检测（法线 y>0.7 防斜坡起跳）→ just_pressed Jump → `move_and_slide`
   （sweep+slide+depenetrate 一体，`SpatialQueryFilter::from_excluded_entities` 排自身）；
   玩家朝向 `face_movement_direction`（Quat::slerp，PLAYER_TURN_RATE=12 平滑转向）。
   Kinematic capsule（0.35/1.0）保留零迁移；glam 无 rotate_towards，转向用 slerp+dt 比例。
3. **Look 双通道（C7，决策 3-③）**：模板 `look_into_camera` 把 `GameActions.value("Look")`
   写进 rig 的 `CameraLook`（符号/钳制逐字镜像 crate RMB 通道）；RMB 按住帧桥让位
   （`ButtonInput<MouseButton>` gate，零引擎改动）——双通道永不双写。
4. **physics-gated 双形态（决策 8-A）**：新占位 `{{module_physics_player_move}}`（有物理=
   MoveAndSlide 全家 ~70 行；无物理=dt 修正版 Transform 相机相对移动 fallback，无跳无碰），
   `{{module_physics_player_body}}` 扩腿 `PlayerVelocity(Vec3::ZERO)`，
   `{{module_physics_statements}}` 挂 `spawn_walls`；teaches 新测试钉双形态
   （physics 17 针+占位零残留；无物理 5 项退场针[avian3d/PlayerVelocity/move_and_slide(/spawn_walls/
   PickupCount 不得出现]+6 项保留针[fn move_player/`controller.move_speed * dt`/look_into_camera/
   CameraRig::default()/JackdawCameraRigPlugin/just_pressed("Jump")]）。
5. **模板场景升级（C4+C6+C3 演示面，决策 5-A）**：玩家补 **capsule mesh+材质**
   （Capsule3d(0.35,1.0) 与 collider 尺寸一致）；同帧 spawn **CameraRig 子实体**
   （`ChildOf(player)`，lone-rig 自动激活=跟随即装即用）；`spawn_walls` 两面正交静态矮墙
   （北墙 12×1.5×0.4 @ z=−3、西墙 0.4×1.5×8 @ x=−4，均高 1.5 挡跳跃）；初始
   `assets/scene.bsn` **删除固定 Main Camera**（只留 Sun，注释指向 Add Entity > Scene Camera）；
   doc 头新增「Player controller」导览段（组件/相机/跳跃碰撞/双 rig 边角 C9）。
   玩家出生点上移 (−2, 0.5, 0)→(−2, **1.0**, 0)：胶囊全高 1.7（段 1.0+球冠 2×0.35），
   落定中心 0.85+skin≈0.86，与拾取线（半径和 0.7）不初触。
6. **T09 引用同步（方案小定案）**：`book/src/user-guide/game-input.md` 代码示例改 dt 修正
   形态+一句指向模板完整控制器；完整 player-controller 新章归 T3。仓库无其它
   `move_player_by_actions` 残留引用（全量 grep 核实）。

## 二、红绿证据（机制层，guards 新 5 件全绿 + 既有 216 不破）

`tests/guards/player_controller.rs`（真 avian 引擎 + `TimeUpdateStrategy::ManualDuration`
+ 真事件流 KeyboardInput/MouseMotion→InputActionsPlugin→GameActions→控制器；控制器逻辑为
模板忠实本地移植——见偏差 5）：

| # | 断言 | 结果 |
|---|---|---|
| 相机接线（C1） | 无插件：场景 bsn 带 rig→实体在而**无 ActiveCameraRig/无 Camera3d**（红）；加一行插件：组件 resolved+激活+物化 Camera3d/CameraLook，anchor 平移 +3 x 后 rig 世界位移=+3.0、offset 常量（绿） | PASS |
| 碰撞滑动（C3） | 数值红：直写步进同输入 1.5 s 达 z=−6（穿墙而过）；绿：W 顶墙停 z∈[−2.50,−2.40] 零穿透，W+D 斜向 z 停而 x 切向滑 >3 m | PASS |
| 跳跃（C2） | just_pressed→v0=4.5±0.2；apex=rest+4.5²/(2·9.81)±0.15；空中再按速度演化=纯重力 ±0.05（禁二段）；落地两帧差<1e-3 且再跳升高 | PASS |
| 帧率无关（C2） | 60 Hz×120 帧与 30 Hz×60 帧同持 W：位移差<0.01 且均≈−8.0（4 m/s×2 s） | PASS |
| Look 量纲+让位（C7） | MouseMotion(200,100)→yaw −=200×0.005、ThirdPerson pitch +=100×0.005（±1e-4 数学断言）；RMB 按住帧同注入 yaw 不变；player transform 不因 Look 转动 | PASS |

关键实施发现：avian 0.8 `MoveAndSlide` 的 sweep/depenetrate **只看见带 `ColliderOf` 的
collider**（=挂 RigidBody 者；`cast_move` 的 predicate 过滤），裸 `Collider` 只进 spatial
pipeline（地面检测 cast 可见、sweep 不可见）——guards 静态体显式 `RigidBody::Static`
（=游戏侧 AvianCollider→StaticCollidersPlugin implied static 链的终态）；游戏侧该链
经暖工程/live 全部验证（拾取、停墙、落定均通）。

## 三、放行条件复跑（真机 direct run，游戏 BRP 15702，六腿全绿）

`loop/qa/t11t1-live.ps1`，暖工程 `H:\workspace_AI\t11-live\t11t1-game`（新独立暖工程，
不触碰并行 QA 的 t10-phys），每腿独立冷启动，`cmd start /B` 分离启动，未设
WGPU_BACKEND（遵主控环境更新纪律）。誊本 `loop/t11t1-live/t11t1-live-final-transcript.txt`。

| 腿 | 断言 | 数值 |
|---|---|---|
| L1 基线 | 玩家落定、rig 子实体激活、3 拾取在场 | player(−2.000, 0.860, 0) count=0 pickups=3 rigActive=True rigCamera=True |
| L2 T09-Move 重钉+墙停 | W 走速 4 m/s，北墙前停 | z 序列 −0.59→−1.26→−1.91→**−2.440 冻结**（面 −2.8+半径 0.35+skin） |
| L5 贴墙滑 | W+D 斜向：法向钳制、切向保留 | 沿墙 x 滑 **6.84–7.41 m**，z 恒 −2.440 |
| L4 **T10 拾取链复跑** | 玩家触 sensor→despawn→计数→集齐 | c0→c1→c2→c3，pickupsLeft=0，游戏日志 **"Level clear! All 3 pickups collected."** |
| L3 T09-Jump 重钉 | 抛物线顶点+落地稳定 | y 序列 1.41→1.85→**1.95–1.97**(理论 1.892)→落 0.860 恒定 |
| L6 相机跟随 | rig 世界位−玩家位=常量 offset | offset=(0.00, 5.09, 9.21) 两采样点**完全一致**（理论：1.2+10·sin0.4 / 10·cos0.4），drift=0.000 |

顺带真机证据：走出地面边缘（x>10）后 y 持续下落（重力积分对无地面情形正确，probe2 记录）。

### T09 行为量纲重钉表（旧→新，钉死非放宽）

| 动作 | T09 旧量纲 | T11 新量纲 | 证据 |
|---|---|---|---|
| Move | `x += move.x*0.1` **每帧无 dt**（≈6 m/s@60fps，帧率相关；格 2 "ArrowUp 2s dz=−12.00"、格 11 "W 2s dz=−11.6"） | **4.0 m/s×dt**（PlayerController.move_speed，帧率无关）；W 2s 理论 dz=−8.0 | guards 帧率无关件（两钟差<0.01、≈−8.0）；live L2 走速与墙停位置 |
| Look | `rotate_y(−look.x*0.01)` 写 **player quat**（dx=200→yaw −2.0→quat.y −0.841，格 4 实测） | **`CameraLook.yaw −= dx×sensitivity(0.005)`** 写相机（dx=200→−1.0 rad），player 不转；与 crate RMB 通道同符号同钳制 | guards Look 件（±1e-4+RMB 让位）；真机格走记档（偏差 4） |
| Jump | `info!("Jump!")` 零位移 | **v0=jump_speed 4.5、g=−9.81 积分、apex+1.03、空中禁二段、落地可再跳** | guards 跳跃件+live L3（apex 1.95–1.97） |
| Interact/Pause | info! 日志 | 保留（move_player 内，physics 形态） | teaches 针 |
| 碰撞 | Kinematic 直写**穿墙** | **停在墙面+沿墙滑+depenetrate 零穿透** | guards 滑动件+live L2/L5 |

T09 格 9/10（捕获语义）链路未动（InputActionsPlugin 原样），guards game_input 件在 fast
全量内绿；其真机格归 T2/T3 矩阵。

## 四、模板实编与暖工程

- **暖工程实编**：`H:\workspace_AI\t11-live\t11t1-game`（path 依赖本 checkout，physics 全开）
  `cargo build` **完整通过**（含 avian 全家桶）——模板实编活体证据（T10-T2 先例口径）；
  main.rs 挂 `JackdawRemotePlugin(15702)` 为测试注入（模板本体不含）。
- scaffold_e2e（20–40 min 嵌套冷编）本轮未跑，记档归 T3 落袋（T10-T2 同款偏差）。

## 五、门禁（日志全文复核；归档 `loop/reports/t11t1_*`）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all --check` | **CLEAN**（修复 10 处 Diff 后复跑零输出；exit code 陷阱按 T10 教训以日志全文为准） | `t11t1_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **CLEAN**（一轮修复：guards doc 注释 CameraRig 补反引号；warning 全为 fork/宏 crate 既有） | `t11t1_clippy_ws.log` |
| Lint 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **CLEAN**（本任务未改物理 crate，按门禁清单例行） | `t11t1_clippy_physics.log` |
| fast | `cargo xtask fast` | **CLEAN，2961/2961 passed**（基线 2960+1 新 teaches；1 leaky+2 skipped 既有） | `t11t1_gate_fast.log` |
| 改动面 crate 测试 | scaffold / runtime lib / 物理双包 / guards 全量 | scaffold **85/85**（84+1）、runtime lib **40/40**、物理双包 ok（triggers/mesh 图元等全绿）、guards **221/221**（216+5 新） | `t11t1_crate_tests.log` |

## 六、偏差与记档

1. **⚪ guards 相机红证的收窄**：in-process 测试无法呈现「类型未注册→UnresolvedTypes」
   （测试二进制引用了 jackdaw_camera_rig→注册恒生效，T10 register_avian_types 注释同因）；
   红证收窄为功能性红「无驱动插件→不激活/不物化/不跟随」。UnresolvedTypes 保底由 T05
   既有防线覆盖；「游戏侧类型注册链」绿证=guards prelude 路径接线+live rig resolved。
2. **⚪ 快照 skip 项**：`scene_snapshot` 不序列化 Camera3d/CameraLook（相机内部件 skip
   清单）——live rig 证据以 ActiveCameraRig+Projection 承载（Projection 随 Camera3d 物化
   而来），Camera3d/CameraLook 物化断言由 guards 承担。
3. **⚪ Live L4 编排**：T10 模板把 FallingCube 落点放在拾取线上（x=0），地面直线走会被
   立方体扰（首跑 2/3）；终跑以一次 Space hop 越过立方体完成 3/3——demo 世界编排非控制器
   缺陷；hop 顺带演示跳跃。玩家×FallingCube 推挤语义归 T3 格 6 正面覆盖。
4. **⚪ Look 真机格改 headless 重钉**：direct-run 无 mouse-motion 注入通道（`input.motion`
   为编辑器/PIE 侧 BRP），PIE 投影采样通道 T10 已记档未愈；量纲以 guards 数学断言钉死，
   真机 Look 格（PIE 注入）留 T2/T3。
5. **⚪ guards 控制器为模板忠实本地移植**（模板代码住在 scaffold 渲染产物里，repo 内不可
   import）：漂移风险以 teaches 针+暖工程实编+live 六腿数值对冲（T10 模式同构）。
6. **C5/C9 的行为面**：PlayerController 字段 Inspector 三态与多 rig 边角按方案归 T2；
   C9 的 doc 注记已入模板头（第二 rig 需手加 ActiveCameraRig）。
7. **环境**：全程 start /B，未设 WGPU_BACKEND=dx12（遵主控 05:26 后更新：dx12 绕行失效
   0x8007000E）；本轮真机零崩溃、零驱动态事件。并行 QA 的 phys-game 进程未触碰。
8. **buglist**：无打钩项（C 系为本方案新发现，机制面 C1/C2/C3/C4/C6/C7/C8 已在本任务
   闭环；C5 行为面+ C9 文档面归 T2/T3）。

## 七、测试账本

| 套件 | 数量 | 结果 |
|---|---|---|
| guards player_controller（新文件） | +5 | ok |
| scaffold teaches（player controller 形态） | +1（84→85） | ok |
| guards 全量 | 216→**221** | ok |
| fast（2960 基线） | +1 → **2961/2961** | ok |
| 暖工程实编 cargo build | — | 通过 |

## 八、工程处置

- 暖工程 `H:\workspace_AI\t11-live\t11t1-game` **保留**（T2 参数面/摆放链真机直接复用；
  main.rs 的 RemotePlugin 为测试注入）。
- 归档：`loop/qa/t11t1-live.ps1`（正式脚本）+ `t11t1-probe.ps1`/`t11t1-probe2.ps1`（调试
  探针，穿墙误报的归因过程学）+ `loop/t11t1-live/`（summary/transcript/游戏日志）。

**提交**：见 git log（显式 pathspec：runtime 两文件+scaffold 两文件+模板两文件+guards
两文件+book 一章；既存噪音 .gitignore/buglist.md 未触碰）。
