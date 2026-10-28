# T11-T1 QA 验收报告：玩家控制器核心+CameraRig 接线+模板改造（只验不修）

> 验收对象：分支 `loop/t11-player` 提交 **fb4d7e45**（基于 main 7dc1f7a8，8 文件 +1086/−53）。
> 开局自检：分支/提交态一致；工作区仅剩既存噪音（.gitignore M、buglist.md 未跟踪）✓。
> QA 证据：guards 5 件亲跑、clippy 物理双包亲跑、`cargo xtask fast` 亲跑
> （`loop/qa/t11t1_qa_fast.log`）、真机三腿独立复跑（QA 自写脚本
> `loop/qa/t11t1-qa-live.ps1`，独立于程序 `t11t1-live.ps1`）、归档 5 件全文复核、
> avian 0.8 registry 源码对照、git 考古（7dc1f7a8 旧模板原文）。

## 一、放行双条件独立复核——双双成立

### ① T09 行为格量纲重钉——重钉真实，基线未篡改

**旧值 git 考古**（`git show 7dc1f7a8:.../lib.rs.template` 原文在案）：

| 动作 | 旧模板原文（7dc1f7a8 实存） | 程序对照表旧值 | T09-T3 QA 归档旧值 |
|---|---|---|---|
| Move | `transform.translation.x += r#move.x * 0.1;`（L265-266，每帧无 dt） | 0.1/帧 ≈6 m/s@60fps | 格 2 ArrowUp 2s dz=−11.999964（QA 逐位复现）✓ |
| Look | `transform.rotate_y(-look.x * 0.01);`（L281，写 player quat） | dx=200→yaw −2.0→quat.y −0.841 | 格 4 yaw −0.841470897（QA 逐位复现）✓ |
| Jump | `info!("Jump!");`（L269，零位移） | info! 零位移 | 格 3 链路原样 ✓ |

旧值三方一致（git 原文=程序对照表=T09 QA 归档）——**对照表不是把基线改小再「钉死」**。
一处数字出入如实记档（⚪D，见 §五）：程序表引格 11 "W 2s dz=−11.6"，T09-T3 QA 归档为
−12.000——同为旧量纲家族的采样抖动（60fps×2s×0.1=−12 理论值），非篡改。

**新值钉死证据**（QA 亲跑）：
- Move 4.0 m/s×dt：guards 帧率件亲跑绿（60Hz×120 与 30Hz×60 同持 W 位移差<0.01、
  均≈−8.0——数学断言形态，非放宽容差）；live L2 墙停 z=−2.440 冻结（见 ②）。
- Look 0.005 写 CameraLook：guards Look 件亲跑绿（MouseMotion(200,100)→yaw −1.0、
  ThirdPerson pitch +0.5，±1e-4）；符号/钳制与 crate RMB 通道逐字镜像（QA 对照
  `camera_rig/src/lib.rs:233-239`：`yaw -= dx*sensitivity`/`clamp(0.05,1.4)`/
  `clamp(-1.4,1.4)` 完全一致）。
- Jump 抛物线：guards 跳跃件亲跑绿（v0=4.5±0.2、apex=rest+v²/2g±0.15、空中再按=纯重力
  ±0.05、落地两帧差<1e-3、可再跳）。

### ② T10 拾取链独立复跑——QA 自写脚本三腿全 PASS

暖工程 `H:\workspace_AI\t11-live\t11t1-game`（exe 2026-10-28 06:14，fb4d7e45 实编产物；
工作区干净、代码未动），每腿独立冷启动，`cmd start /B` 分离，未设 WGPU_BACKEND，
零崩溃零驱动态事件：

| 腿 | QA 复跑数字 | 程序归档 | 判定 |
|---|---|---|---|
| L1 基线 | player(−2.000, 0.860, 0) count=0 pickups=3 rigActive=True rigCamera=True | 同 | PASS |
| L2 墙停 | z 序列 −0.521→−1.399→−2.126→**−2.440 冻结** | −0.59→−1.26→−1.91→−2.440 | PASS |
| L4 **T10 拾取链** | **c0→c1→c2→c3、pickupsLeft=0、clearLog=True**（"Level clear!"） | 同 | PASS |

放行条件②的「count 0→3+Level clear」QA 独立复现成立。

## 二、红绿真实性——guards 新 5 件亲跑 5/5 全绿（1.75s，216 filtered 与账本一致）

| # | 测试 | 亲跑 | 红面形态 |
|---|---|---|---|
| 相机接线 | a_scene_rig_follows_only_through_the_runtime_plugin | ok | 功能性红真跑：无插件→无 ActiveCameraRig/无 Camera3d（真断言） |
| 碰撞滑动 | the_sweep_stops_the_player_at_walls_and_slides_along_them | ok | **推导式红**（见 ⚪C）：`plain_z=−(4.0×1.5)=−6.0 < −3.4` 恒真数学；绿面真跑（停 z∈[−2.50,−2.40]、零穿透、斜向 x 滑>3.0） |
| 跳跃 | a_jump_flies_the_parabola_and_lands_ready_again | ok | 全真跑（v0/apex/二段禁/落地稳定/再跳） |
| 帧率无关 | movement_covers_the_same_ground_at_two_frame_rates | ok | 真跑（ManualDuration 两钟对照） |
| Look 量纲+让位 | look_motion_turns_the_camera_not_the_player | ok | 真跑（真事件流 MouseMotion/MouseButtonInput→InputActionsPlugin→桥；RMB 按住帧 yaw 不变） |

**碰撞红证重点核裁定（⚪C）**：任务书重点质疑的「直写穿墙 z=−6 数值红」实为**推导式
常量断言**（编译期数学：直写无碰撞 1.5s 必达 −6.0，墙远端 −3.4），直写路径未在 world
里实际执行——非「实测红」。但：直写行为的数学无可争议（旧模板代码无任何碰撞检查）、
绿面三断言真跑、live L2 真机墙停 −2.440 双重复现——红绿链条闭合，结论成立。记 ⚪ 证据
纪律（报告「数值红」措辞易读作实测）。

## 三、门禁复跑最小集——全绿

| 门 | QA 亲跑 | 程序归档复核 |
|---|---|---|
| clippy 物理双包 `-D warnings` | **CLEAN**（21.45s EXIT=0） | `t11t1_clippy_physics.log` 3085B 零 error/FAILED 匹配 ✓ |
| `cargo xtask fast` | **2961/2961 passed (1 leaky), 2 skipped**（42.4s，`loop/qa/t11t1_qa_fast.log`） | `t11t1_gate_fast.log` Summary 逐位同 ✓；error/FAILED 匹配全为测试名假阳性 ✓ |
| fmt | —（quick 口径） | `t11t1_fmt.log` 空文件（--check CLEAN 合理形态，T10 先例）✓ |
| clippy 全仓 | —（物理双包+改面复核代） | `t11t1_clippy_ws.log` 1556B 零匹配+Finished ✓ |
| crate 测试 | guards 亲跑 5/5（含在全量） | `t11t1_crate_tests.log`：scaffold **85**、runtime lib **40**、物理双包 5+4+6+5+5+6+0+20=**51**、guards **221**，与报告账本逐项一致 ✓ |

## 四、代码 review 五重点——全部落实

1. **runtime 无条件依赖改动（决策 2-A）**：diff 干净——optional 移除+pie feature 内
   `dep:jackdaw_camera_rig` 行同步清理+模块级 re-export 6 类型+prelude 并入（不
   physics-gate，模板一行接线）。全仓 `git grep jackdaw_camera_rig` 检索：**无 pie 残留
   假设**——pie_frames.rs 的 use 在无条件依赖下恒可用；根 Cargo.toml 的 `camera_rig`
   feature+optional 是**编辑器主 crate 自有形态**（默认开、Add Entity Camera Rig 模板
   用），与 runtime 无条件化正交，非残留。注意 ⚪A：prelude 实际 5 项（缺
   `JackdawCameraRigTypesPlugin`，仅模块级导出）vs 报告称 6 项并入——无功能影响。
2. **avian MoveAndSlide「只见 ColliderOf」发现真实性**：QA 对照 registry 源码
   `avian3d-0.8.0/src/character_controller/move_and_slide.rs`——L81 `colliders` Query
   带 `(With<ColliderOf>, Without<Sensor>)` 过滤；`cast_move`（L768-780）predicate
   `|e| self.colliders.contains(e)`；`intersections`（depenetrate 底层，L1035-1039）
   同样 `self.colliders.get()` 否则 continue。**sweep 与 depenetrate 双路径均只见挂
   RigidBody（ColliderOf）的 collider——实施发现源码级成立**。guards 静态体显式
   `RigidBody::Static` 与游戏侧链终态对齐：`static_bodies.rs` StaticCollidersPlugin
   给无 body 的 AvianCollider 插 `RigidBody::Static`（implied static）→ avian 挂
   ColliderOf——语义正确；「地面检测（spatial_query.cast_shape 走 collider tree）可见、
   sweep 不可见」的解释与两套 API 的分野一致。
3. **physics-gated 双形态占位（决策 8-A）**：`{{module_physics_player_move}}` 注入 +
   `module_physics_player_body` 扩 PlayerVelocity + `module_physics_statements` 挂
   spawn_walls，与 T10 手动重力 fallback 同构；无物理形态=dt 修正 Transform 移动
   （`controller.move_speed * dt`）+Jump/Interact/Pause info! 保留；teaches 双形态断言
   （退场 5 针+保留 6 针+双 `!contains("{{")` 零残留）亲见于归档 85/85 内。计数小出入
   ⚪B：physics 形态针实为 18 个（报告写 17）。
4. **Look 桥 RMB 让位（决策 3-③）**：`look_into_camera` 以 `ButtonInput<MouseButton>`
   gate（RMB 按住帧 return），零引擎改动；符号/钳制与 crate RMB 通道逐字镜像（§一①）。
   guards 亲跑证 RMB 按住帧同注入 yaw 不变——机制面成立；PIE 真机 RMB 语义（编辑器
   按住时转发事件是否也让位）+「RMB 抬起同帧」边角按方案归 T2 C7 格，程序裁量记档口径
   在案。
5. **scene.bsn 模板改动**：删固定 Main Camera+头注释指向 Add Entity > Scene Camera
   （决策 5-A 原样）；暖工程产物 `FC /b` 与仓库模板**逐字节一致**；rig 唯一相机+游戏
   可玩由 live L1 证；scenes_roundtrip 族在 fast 全量内绿（减法改动，往返面无新风险）。
   book `game-input.md` dt 修正示例+指向模板一句在案；源文件 UTF-8 完好（diff 中
   em-dash 乱码仅 CMD 管道显示，Read 实读验证，T10 教训复查）。

## 五、偏差 8 条裁定——全部接受（程序分级合理）

| # | 偏差 | QA 裁定 |
|---|---|---|
| 1 | 相机红证收窄为功能性红 | **接受 ⚪**——in-process 二进制经 prelude 引用 camera_rig，类型注册恒生效，UnresolvedTypes 红面无法呈现（T10 register_avian_types 注释同因先例）；T05 保底防线覆盖残余风险；绿面含「resolved 非 unresolved leftover」断言 |
| 2 | scene_snapshot skip 相机内部件 | **接受 ⚪**——skip 清单是 PIE 协议既有设计；live 以 ActiveCameraRig+Projection 承载、Camera3d/CameraLook 物化断言由 guards 承担（QA 亲跑） |
| 3 | L4 编排 hop 越 FallingCube | **接受 ⚪**——QA 复跑同形态 3/3+clear log；「demo 编排非控制器缺陷」成立；推挤语义归 T3 格 6（建议顺带评估挪 cube 落点，非阻塞） |
| 4 | Look 真机格改 headless 重钉 | **接受 ⚪**——direct-run 无 motion 注入通道是既有账（T10 记档未愈）；量纲由 guards ±1e-4 钉死（QA 亲跑），真机 Look 格留 T2/T3 按方案矩阵走 |
| 5 | guards 控制器为忠实本地移植 | **接受 ⚪**——QA 逐行对照 guards 与模板/占位代码（同常数同次序）；teaches+暖工程实编+live 数值三重对冲，T10 同构先例 |
| 6 | C5/C9 行为面归 T2 | **接受（按方案原定，非偏差）**——doc 注记已在模板头 |
| 7 | 环境纪律 | **接受**——QA 复跑同纪律（start /B、无 WGPU_BACKEND、零崩溃）；跑后进程清零（QA 复查 tasklist 无 t11t1-game/jackdaw） |
| 8 | buglist 无打钩 | **接受**——C 系为本方案新发现，机制面本任务闭环，无 buglist 修复面 |

**QA 补充发现（全部 ⚪，不阻塞）**：
- ⚪A：报告 §一-1 称 6 类型「并入 prelude」，实际 prelude 5 项（TypesPlugin 仅模块级
  导出）——措辞 vs 实物差异，无功能影响；
- ⚪B：teaches physics 形态针实为 18（报告写 17）——计数差 1；
- ⚪C：碰撞滑动红证为推导式常量断言（§二裁定，结论成立、措辞记档）；
- ⚪D：程序对照表引 T09 格 11 旧值 −11.6 vs QA 归档 −12.000——同量纲采样抖动，非篡改。

## 六、结论

- 放行双条件：T09 量纲重钉（git 考古三方对照，重钉真实非篡改）+T10 拾取链（QA 独立
  复跑 0→3+Level clear）——**双双成立**；
- 红绿真实性：guards 5/5 亲跑绿（4.5/5 红面执行式、1 处推导式已记 ⚪C，链条闭合）；
- 门禁：clippy 物理双包亲跑 CLEAN、fast 亲跑 2961/2961、归档 5 件全文复核一致；
- 代码 review 五重点全落实（含 avian 源码级对照、pie 残留零、镜像逐字、产物逐字节）；
- 偏差 8 条全接受+QA 补充 ⚪×4，零 🔴 零 🟡。

**VERDICT: PASS**

- 合入建议：主控 `--no-ff` 合入 fb4d7e45 至 main。
- 下游提醒（不阻塞）：T2 面临的 PIE Look 注入通道缺口（偏差 4）与 L4 cube 编排（偏差 3）
  已在案；QA 独立脚本 `loop/qa/t11t1-qa-live.ps1` 与程序脚本并存可复用。
- 工程处置：暖工程保留（程序 §八口径）；QA 跑后进程清零、真机日志
  `loop/t11t1-live/t11t1-qa-game-stdout.log` 在档。
