# T10-T2 报告：触发器/碰撞层/模板教学+真机不穿地首证

> 任务：`loop/plans/t10-physics-triggers.md` §二 T2（F3+F4+F5+F8；决策 3/4/6 实施裁
> 定已按方案执行，1 处选址偏差见 §六）。分支 `loop/t10-triggers`（基于 main fcaba7c7）。
> 门禁日志归档：`loop/reports/t10t2_*`（fmt/clippy_ws/clippy_physics/gate_fast/
> physics_tests）；真机证据：`loop/t10t2-live/`（编辑器/游戏日志+快照落盘）与
> `loop/qa/t10-triggers.ps1`（首证脚本）+本报告 §四数值抄录。

## 一、TriggerPlugin→TriggerEvents 薄桥（F3 机制层，决策 3-B'）

**架构**（1 处选址偏差，记档 §六-1）：core_deps 守卫（T1 QA 裁定「编辑器核心零第三方
Bevy 生态」为 ✅ 既有约束）不允许 `jackdaw_runtime` 依赖 avian3d——方案字面「runtime
薄层 triggers.rs」拆为两半，依赖边恰好已存在（terrain feature 早有 integration→runtime）：

- `crates/jackdaw_runtime/src/triggers.rs`（新，~130 行）：`TriggerPhase`
  （Enter/Exit）、`TriggerContact { trigger, other, phase }`、`TriggerEvents`
  Resource（每帧重建的 Vec+`enters()/exits()/iter()/len()/is_empty()/push/clear`）——
  **零 avian 依赖**，三类型入 `jackdaw_runtime::prelude`（方案字面
  「TriggerEvents 入 prelude」达成），内嵌单测 1 件（相位过滤）。
- `integrations/physics/jackdaw_avian_integration/src/triggers.rs`（新，~140 行）：
  `TriggerPlugin`——①`register_avian_types` 补 `CollisionEventsEnabled` 注册
  （场景存档可保真+inspector 可见）；②`On<Add<Sensor>>` observer 自动补齐
  `CollisionEventsEnabled`（作者只加 Sensor，零心智）；③PreUpdate
  `collect_trigger_events`：MessageReader<CollisionStart/End>→TriggerEvents 每帧
  清空重建（Enter/Exit 语义，sensor 侧=trigger，双侧 sensor 双记，非 sensor 接触
  不进列表；despawn 一侧读作 false 仍报 Exit——`Query::get().unwrap_or(false)`）。
  插件 build 时 init 两个 collision Messages buffer（avian 懒注册，PreUpdate reader
  首帧会 panic——修复记录）。

**自动补齐为何是 observer 而非 Added<Sensor> 系统**（实施发现，非方案预见的 avian
语义）：CollisionEventsEnabled 的 flag 在 collider 进入 broad phase collider tree 的
**proxy 构建时快照**（`collider_tree/update.rs` 读 `Has<CollisionEventsEnabled>`），
之后不重读、也无 Insert observer 触发重插——后加组件对已存在 collider 无效。observer
形态保证 prerequisite 与 Sensor 同帧落实体（先于 bridge 任何系统构建的 Collider），
顺序恒定。

**红绿证据**：
- 合成事件层（`tests/triggers.rs` 新 6 件全绿）：无插件=无 Resource 无补齐（红）；
  插件在=sensor 获 prerequisite、玩家不获；sensor 对落 Enter、End 落 Exit；非 sensor
  对（message 有）零进列表；双侧 sensor 双记；列表逐帧重置。
- 真物理层（`tests/guards/physics_triggers.rs` 新 4 件全绿，编辑器 app 真引擎，
  `TimeUpdateStrategy::ManualDuration` 驱动）：①前提红绿（同场景两对 sensor——无
  CollisionEventsEnabled 的零 start，带的恰一对 start）；②桥端到端（spawn 重叠→
  逐帧捕获 Enter；despawn 玩家→Exit）；③层过滤红绿（互滤对零接触 vs 全通对恰一
  接触且桥面 Enter 逐帧可见）；④不穿地 headless 版（§四）。

## 二、碰撞层作者面（F4，决策 4-A）

- **组件面**：`CollisionLayers`（`memberships/filters: LayerMask(u32)`）注册在
  （T1 前已有）+ feathers bitmask 编辑既有——本任务补**语义红绿**（§一 guards ③）
  与**文档首版**：模板 doc 注释内置层表示例（hazard 0b100/player 0b001 的互滤表）
  +互滤规则一句话（each side's memberships meet a layer the other filters in）。
  层命名资产不做（backlog，方案决策 4 已裁）。
- **引擎边界记档**：avian 增量 broad phase 对**静止 collider 后改层不重配对**（红绿
  测试原设计的「re-layer 后触发」绿半在静止场景不成立——诊断：collider/tree 均在、
  事件不来；改测为初始层决定配对的红绿对，静止体重配对留真机「改层+移动」格与 T3
  矩阵）。

## 三、模板教学（F5+F8，决策 6-A 收编）

`lib.rs.template` 物理化（physics 模块 default=true 下全部在场；关闭时全部退场、
手动重力回归——**5 个行级占位** `{{module_physics_*}}` 由 scaffold 注入，与
`{{module_plugins}}` 同族机制）：

1. **falling_cubes 收编**：FallingCube spawn 带 `RigidBody::Dynamic`+
   `AvianCollider(Cuboid)`（下落交给引擎）；`falling_cubes` 系统的手动重力行退场
   （占位反转：非物理工程时 scaffold 注回手动行——模板双形态均编译）。
2. **重力双源归一（F8）**：`apply_gravity_from_config`（Update，`Res<GameConfig>`
   is_changed 驱动）把 config.gravity 注入 avian `Gravity` Resource——T08 配置资产
   语义升级为「物理 Resource 初值」，doc 写明两源边界（文件改=下次启动；Resources
   面板改=会话内生效）。
3. **玩家物理身（决策 6 裁量：保守路线）**：PlayerMarker 加 `RigidBody::Kinematic`+
   capsule collider——**Transform 版 move_player_by_actions 原样保留**（T09 矩阵
   语义零漂移，方案决策 6 允许的保守备选），kinematic 让 collider 跟随手写 Transform、
   与 sensor 产生检测且不被推挤。
4. **拾取过关教学段**（~100 行 doc+代码）：`Pickup` 标记+`PickupCount(u32)`（挂
   玩家，投影可断言）+`spawn_stage`（大 static 地面）+`spawn_pickups`（3 个发光
   sensor 立方）+`collect_pickups`（TriggerEvents enters→trigger 带 Pickup→despawn
   +计数→集齐 `info!("Level clear!")`）——方案 T2-3b 的最小完整教学。
5. **触发器工作流 doc**（模板头部无条件段，~50 行）：collider/sensor/TriggerEvents/
   层表/重力双源五节教学导览。

**scaffold 侧**：`substitute_placeholders` 接 5 占位（physics 判定
`modules.contains("physics")`）；新增 teaches 测试
`new_game_project_teaches_the_physics_and_trigger_pattern`（physics 形态 12 断言+
占位零残留+无 physics 形态 5 项退场断言+手动重力回归断言）。scaffold 84/84（83+新 1）。

**bridge 补一路（模板教学的硬前提）**：`build_mesh_primitive_colliders`——带自身
Mesh3d 的实体（模板 spawn 的地面/cube/拾取物）此前**两路都不覆盖**（brush 路径要
Brush、model 路径排除 Mesh3d），图元构造器现在直接构建。lib 内嵌测试+1 件。

**实编验证**：暖工程 `H:\workspace_AI\t10-phys\phys-game` 的 lib.rs 以新模板渲染产物
替换（doc 头 project-name 修正），`cargo build` 完整通过（含 avian 全家桶）——
模板实编的活体证据；scaffold_e2e（嵌套冷编 20-40 分钟级）本轮未重跑，记档 §六-4。

## 四、真机不穿地首证（T1 挂账清偿）+拾取链真机证据

**PIE 腿**（编辑器 15703，真机脚本 `loop/qa/t10-triggers.ps1` 归档）：
- PIE `pie.play_current` → **running**（物理工程 windowless PIE 全链启动、画面流
  正常——T1 挂账的「PIE 腿跑通」部分）；
- `pie.stop` → **场景 SHA 不变**（Stop 铁证顺路，物理组件流零污染）。

**direct run 腿**（窗口模式真实进程，游戏侧 BRP 15702——暖工程 main.rs 加
`JackdawRemotePlugin`（测试注入，模板本体不加，T08 决策 6 口径维持））：

| 断言 | 数值 | 判定 |
|---|---|---|
| 模板 FallingCube 落定 y | **0.2999731 / 0.2999730 / 0.2999731**（三次采样，间隔 2s） | 半边长 0.3，停在地面顶面（stage 顶 y=0），零穿透 |
| 两帧差 dy | **-6.0e-8 / +6.0e-8** | 浮点噪声级，完全静止 |
| stage 地面 | y=-0.5 在场 | 模板 spawn ✓ |
| 拾取物 | x=-1 与 x=1 两枚在场（y=0.5），**x=0 一枚被落下的 cube 触发 despawn** | 拾取链端到端真机闭环（任何 collider 进 sensor 即触发——语义正确） |
| 玩家 | x=-2, y=0.5 kinematic 在场，**PickupCount=1** | 触发器连游戏行为：Enter→despawn→计数全链 |

**不穿地铁证组合**：headless（guards ④：y=5 落地 120 帧，两帧差<0.001，静止
y∈[0.24,0.26]）+direct run 真机（上表）+PIE running（画面流）——T1 挂账的
「编辑器/PIE 双腿 Play 中动态体带重力落地静止」以 headless+direct run 数值+PIE
窗口流组合清偿（PIE 内部数值采样受 §六-2 通道限制，如实记档）。

## 五、门禁（日志全文复核，exit code 辅助）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all --check` | **CLEAN**（修复 13 处 Diff 后重跑覆盖归档；exit code 曾报 0 而日志有 13 Diff——门禁证据标准再证） | `t10t2_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **CLEAN**（三轮：from_raw→obfuscated-if-else→manual_range_contains 逐个修复；最终日志零 error，warning 全为 fork/bevy 宏 crate 既有） | `t10t2_clippy_ws.log` |
| Lint 物理单包（T1 教训必跑） | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **CLEAN** | `t10t2_clippy_physics.log` |
| fast | `cargo xtask fast` | **CLEAN，2959/2959 passed**（基线 2955+4 新 lib 测试；fmt/core_deps「no third-party Bevy crate」/clippy 段全过；1 leaky+2 skipped 既有） | `t10t2_gate_fast.log` |
| 物理双 crate 测试 | `cargo test -p jackdaw_avian_integration -p jackdaw_physics` | **51/51**（基线 44+7 新：triggers 6+mesh 图元 1） | `t10t2_physics_tests.log` |
| guards 物理四件（终态复跑） | `cargo test --test guards physics_triggers` | **4/4** | `t10t2_guards.log` |

## 六、偏差与记档

1. **TriggerPlugin 选址偏差**（§一）：方案决策 3-B' 字面「runtime 新模块 triggers.rs
   全套」→ 实施数据类型入 runtime（prelude 达成）、消费插件入 integration——
   core_deps 守卫（T1 QA ✅ 的「豁免最小化」）不允许 runtime 依赖 avian；哲学
   （游戏读可读状态不碰 avian 细节）完整达成（TriggerEvents 三类型零 avian）。
   TriggerPlugin 从 `jackdaw_avian_integration` 导出（物理模块工程天然依赖）。
2. **PIE 内数值采样通道限制**：编辑器端口的 `jackdaw/scene_snapshot` 快照编辑器
   世界（文档实体+视口 19 实体），PIE 投影镜像实体（PieEphemeral）在物理工程未
   出现（投影流断或延迟，未深挖——时间预算）；Live 镜像驱动文档实体的形态在
   DroppingCube 场景实体上未生效（诊断未完成）。真机数值断言改走 direct run
   游戏 BRP（15702）。**game-config.bsn 改 gravity→两帧差**（受力正确格）留 T3
   矩阵（格 4，方案 T3 范围）。
3. **windowless PIE × JackdawRemotePlugin 崩溃**（0xc0000005×2，游戏初始化后期）
   ：二分定位（空插件/A 仅插件/B 仅 spawn/C +dynamic/D +mesh/E +场景/F 完整模板
   全 PASS——完整模板+JackdawRemotePlugin 组合崩）。真机纪律命中「构建竞态」偶
   发一次后，稳定复现于 remote 组合。已隔离：PIE 腿不带 remote 插件（跑通），direct
   run 带（跑通）。**根因未修**（T3 真机矩阵将回避该组合或立项调查——记档给主控）。
4. **scaffold_e2e 未重跑**：模板改动使 e2e 缓存键变化触发 20-40 分钟冷编，本轮
   以暖工程实编替代官方 e2e（时间预算）；建议 QA 或 T3 复跑。
5. **静止体改层不重配对**（§二）：avian 引擎边界，测试形态已如实调整，真机
   「改层+移动」格留 T3。
6. **模板 doc 对非物理工程无条件在场**：教学段措辞已声明「physics 模块（默认
   启用）」前提；代码全部条件退场（teaches 测试钉死）。
7. buglist：无打钩项。
8. **game.pid/direct-brp.log 等暖工程运行残留**：留在暖工程目录（不入库）。

## 七、测试账本

| 套件 | 数量 | 结果 |
|---|---|---|
| runtime lib（triggers 内嵌） | +1 | ok |
| integration tests/triggers.rs | +6 | ok |
| integration lib（Mesh3d 图元） | +1 | ok |
| guards physics_triggers | +4 | ok |
| scaffold teaches | +1（83→84） | ok |
| 物理双 crate（44 基线） | +7 → **51/51** | ok |
| fast（2955 基线） | +4 → **2959/2959** | ok |

**提交**：`bd83b3da` `Bridge sensor contacts into a readable trigger resource with
physics-shaped templates`（12 文件 +1189/−10；分支 `loop/t10-triggers` 基于 main
fcaba7c7；既存噪音 .gitignore/buglist.md 未触碰，提交显式 pathspec）。

## 八、工程处置

- 暖工程保留（T3 真机矩阵直接用）；main.rs 的 JackdawRemotePlugin 与 scene.bsn 的
  DroppingCube 为测试注入（T3 复用或清除）。
- `loop/qa/t10-triggers.ps1`（首证脚本）+ 4 个调试探针脚本（probe/snap-dump/
  game-dump/sample）归档。
