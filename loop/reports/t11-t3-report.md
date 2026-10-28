# T11-T3 实施报告：验收矩阵 + book 文档 + 全量门（Windows 段 + macOS 续跑段）

> 任务：`loop/plans/t11-player-template.md` §二 T3（矩阵 12 格+book player-controller
> 章+全量门）+ 两项 QA 裁定修复（C10 doc 双补、N14 首 set 完整落库）。
> 分支 `loop/t11-final`：产品代码全部在 **406d116b**（Windows 段产出，8 文件
> +334/−8）；**macOS 续跑段**（仓库自 Windows 迁至 Apple M1 Pro/macOS 26.6/Metal，
> 恢复点 `loop/MIGRATION.md`）补齐：矩阵 12 格 Mac 侧新证据、旧机 PIE 死亡降级格的
> 真机转正（C7/格 11/N13 ×10）、导出腿、无物理真工程落袋、cell6 判定、bash 脚本
> 移植。归档：门禁 8 件 Windows 产物 `loop/reports/t11t3_*`；真机证据
> `loop/t11t3-live/`（Windows `t11t3-*` + Mac `*-mac` 后缀）；脚本
> `loop/qa/t11t3-matrix-{a,a2,a3,c}.{ps1,sh}`（a2/a3 为 Mac 新增、.ps1 原件保留）；
> 暖工程 `/Users/zhanglinbo/workspace/loop-mac/{t11t1-game,t11t3-nophys}`（仓库外，
> 仪表记档见 §九-3）。

## 〇、执行摘要（两段合并）

Windows 段：两项 QA 裁定修复落地（各带红→绿用例，N14 另有真编辑器链活证）；
矩阵 9 格 PASS、3 格 PIE 死亡降级（T10 口径）、cell6 推 FallingCube 一条行为发现
记档（dx=0.00）；book 新章+两处交叉更新；全量门归档 8 件。

macOS 段（本文件增量）：**12 格收口为 11 PASS + 1 语义边界格**——旧机三大挂账
（C7 真机注入/格 11 Stop 铁证/N13 ×10）因 **PIE 全链在 Metal 上存活**而全部转正：
C7 开通道 **−1.0 rad 量纲精确命中（1e-5 度）**+RMB 让位单写验证；格 11 SHA 不变+temp
清零；**N13 复发率=100%（10/10 轮、累计 57 次 panic，并挖出第二个受害系统
`cleanup_session_on_stop`）**。格 12 无物理真工程编译+行为抽查落袋；导出腿
`jd export` release+staged 冒烟补全（§三-4）。**cell6 判定=决策 1-A 的 kinematic
语义边界而非缺陷**（双机 dx=0.00/1.1e-07 一致；avian 源码级证据链 §四；book 补
边界段、buglist 立 A2；不为过格改引擎）。Mac 数字与 Windows 逐位对齐（落定 0.860、
墙停 −2.440、跟随 drift 0.000/8.5e-07、半速 1.57-1.67 m/s），迁移基线零漂移。

## 一、两项 QA 裁定修复（红→绿；Windows 段原文）

### C10：模板 doc 摆放组件清单双补（🟡→修复）

**机制**：physics 形态 `move_player` 的 Query 要求五组件
`(PlayerController, Collider, PlayerVelocity, Transform) With<PlayerMarker>`，
模板 spawn 的玩家四件齐（Collider 来自 AvianCollider 桥）；旧 doc 只教
「add PlayerMarker and PlayerController」两件——照摆的玩家悬空不动（T2 真机
实锤）。

**修复面**（doc 是 physics-gate 的，避免无物理工程提及不存在的符号）：
1. 模板导览段新增占位行 `{{module_physics_player_doc}}`：
   - physics 形态=五件套 bullet（PlayerMarker、PlayerController、零值
     `PlayerVelocity`、Kinematic `RigidBody`、`AvianCollider` 胶囊 0.35×1.0
     ——「queries five components together … one missing and it does not
     move at all」）；
   - 无物理形态=两件套 bullet（walk 仍相机相对+帧率无关，无跳无碰撞）；
2. `PlayerMarker` 的 doc 注释改为指向导览段（不再自带不完整清单）；
3. teaches 红绿：`new_game_project_teaches_the_player_controller_pattern`
   needle 扩三条 physics 锚（`queries five components together`、
   ``zero `PlayerVelocity` ``、`` `AvianCollider` (a capsule of radius 0.35``）
   +plain stays 扩一条（`needs two components`）——doc 完整性以 teaches
   对照式钉死（红=旧 doc 两件套不含这些锚——QA t11-t2 §五已源码级核实，
   绿=4/4 teaches 测试全过）。

**真机活体（格 2 字面链，双机）**：Windows 腿 A 全 BRP 驱动真摆五件套（含
`component.add t11t1_game::PlayerVelocity`——T2 时代要靠 bsn 文本注入的组件，
operator 直摆）→ 腿 C R1 六行为全绿；**Mac 同链复跑全绿**（五 add 全 finished，
`M2_BUILD=PASS`，`t11t3-a-mac-*`）——**照修好的 doc 摆的玩家能动，双机在案**。

### N14：add 后首 set 单字段落库丢同组件兄弟字段（🟡→修复）

**机制**（源码级定位）：`component.add`（project 组件）写**空字段** Struct
patch（`AddProjectComponent`，注释明言空块=Default 物化）；首 set 单字段走
`SetBsnField::execute` → `set_project_field` 只 push 该字段——盘上块从此
只拼 set 过的字段（QA 窗口=add 后首次 set；bare-type 场景 authoring 同族）。

**修复**（`src/commands.rs`）：`SetBsnField::execute` 的 project 分支，在
写入单字段前若发现文档 patch 是「无字段形态」（空 Struct 或 bare Type），
先以 schema 提取的组件默认值（`ReflectSerializer`-wrapped，经
`schema_values::bsn_for_json` 转换）**整体灌入 patch**，再落单字段——首
set 后文档块=完整组件值。新增 helper：`project_patch_is_fieldless` /
`project_schema_default_bsn`；schema 无 default 时保持现状稀疏形态（不
恶化）。Inspector UI 字段提交链同路（`field_edit_commit` 也产
`SetBsnField`），统一受益。

**红→绿**：
- 用例 `a_first_field_set_after_add_authors_the_whole_component`
  （tests/guards/scaffolded_component_flow.rs，schema 带 default 的
  PlayerTuning）；
- 红：临时禁用 backfill（`false // RED-PROOF`）复跑——`left: None,
  right: Some(4.5)`（jump_speed 兄弟丢失，QA 复现形态逐字一致）；
- 绿：启用后全过（模块 15/15，guards 全量 222/222——原 221+新增 1）；
  用例同时钉死盘上面（emit 文本含 jump_speed）与二次 set 合并不回退
  （QA P2 对照）；
- **真编辑器链活体（双机）**：Windows `N14_LIVE_SIBLING_ON_DISK=True`
  （`t11t3-a-summary.txt`）+ **Mac `N14_LIVE_SIBLING_ON_DISK=PASS`**
  （`t11t3-a-mac-summary.txt`：真机 add PlayerController→首 set move_speed 2.0→
  save→盘上 `move_speed: 2.0` 与 `jump_speed: 4.5` 并存）。

**undo 语义记档**（⚪）：backfill 不进 undo 记录——add→set→undo 后文档块
含完整默认字段而非回到空块；两者在 Play 加载语义等价（都取 Default），
行为无损。

### C12（⚪ 维持，不修代码，book 定案）

skip 行清理不动；book 章把现状语义写死：「手加的 `ActiveCameraRig` 经 patch
通道持久化，Automatic 模式无害且是摆放链 Play 即玩的基础」——文档化定案，
代码面处置留主控裁量。Mac 侧双 rig 时序竞争（模板 rig 偶发抢激活）维持旧机
记档口径（§七-4）。

## 二、验收矩阵 12 格（双机合并表）

> Windows 证据：`loop/t11t3-live/t11t3-{a,c}-*`；Mac 证据：`t11t3-{a,a2,a3,c}-mac-*`。
> Windows PIE 探测 3/3 exited 0xc0000005（T10b NVIDIA 驱动态）；**Mac PIE 探针
> PASS**（`t11t3-a2-mac-*`：游戏进程+游戏 BRP 双证存活，connected 0.27s——
> 首轮腿 A 误判 DEAD 的两处 Mac 工具差见 §八-4）。

| # | 场景 | Windows | macOS | 结论 |
|---|---|---|---|---|
| 1 | 新工程开箱即玩 | PASS（R2：visible/dz=2.44/apex 1.956/drift 0.000） | **PASS**（R2：dz=2.440、apex 1.914、drift 8.5e-07） | **PASS** |
| 2 | **放玩家+地面即玩（摆放链）** | PASS（M2+N14+R1_C1 落定 0.860） | **PASS**（同链：五件套 operator finished、落定 0.860） | **PASS**（验收句铁证一） |
| 3 | 移动（帧率无关+参数行为） | PASS（R1_C6 1.67/3.34；两档 dt=guards <0.01m） | **PASS**（R1_C6 1.57/3.15） | **PASS** |
| 4 | 转向/Look（C7） | 降级（PIE 死；guards yaw=−dx×0.005 ±1e-4） | **PASS**（a3：开通道 rig 角 0→**−57.2958°=−1.0 rad 精确**；RMB 按住帧**恰单写** −57.2958°，双写会是 −114.59°） | **PASS**（真机转正，§三-1） |
| 5 | 跳跃 | PASS（apex 2.458；T2 轮 2.007——两参数两值均命中 v²/2g） | **PASS**（apex 2.727，窗口 ±0.35 内） | **PASS** |
| 6 | 碰撞 | 墙停 −2.440/贴墙滑 1.86m/高速 −2.440 全 PASS；**推 FallingCube FAIL（dx=0.00）记档** | 墙停 −2.440/滑/高速 −2.440 全 PASS；**推箱 FAIL（dx=1.1e-07）** | 主面 **PASS**；推箱子项=**语义边界**（§四判定，非缺陷不修，双机一致） |
| 7 | 跟随（复用 CameraRig） | PASS（drift=0.000；R4 FP \|local\|=1.600） | **PASS**（drift=0.000；R4 FP \|local\|=**1.2999998=authored eye_height 1.3**——M9 补腿） | **PASS** |
| 8 | Inspector 可调·玩家参数 | PASS（三态一致+行为生效） | **PASS**（M8 复跑：move_speed 2.0/jump_speed 6.0/sensitivity 0.008 同盘+行为 R1C3/C6） | **PASS**（验收句铁证二） |
| 9 | Inspector 可调·相机参数（M9） | distance/mode/pitch 有证；sensitivity 盘上；**eye_height 无证据** | **PASS**（distance 5.578 双机；**eye_height 1.3 编辑→盘上 `1.2999999523162842`→行为 1.2999998 三处闭环**；sensitivity 盘上+量纲 0.005 由 C7 活证） | **PASS**（sensitivity 的 authored-0.008 行为面双机未采样，⚪ 残留 §七-3） |
| 10 | 三态一致（Play=direct=导出） | direct PASS；PIE 降级；导出异目录启动受阻（桌面态）记档 | 编辑腿+**PIE 腿（C7/格 11 全走 PIE）**+direct 腿 PASS；**导出腿=release 构建+staged 冒烟 PASS**（§三-4） | **PASS**（降级格全部转正） |
| 11 | Stop 铁证回归 | 降级（PIE 死；guards 承载机制面） | **PASS**（a2：驱动中（z=−2.440）stop→**SHA256 不变**+`.jackdaw-pie/current-*` 清零） | **PASS**（真机转正） |
| 12 | 无物理形态回归 | PASS（teaches 85/85+e2e 门；真工程编译未达） | **PASS**（真工程 `t11t3-nophys` 冷编 1m44s；行为抽查：W 走 z 0→−4.93/1.2s、**Space→`Jump! (needs the physics module…)`+y 1.0→1.0**、世界零 avian 组件、无重力落定） | **PASS** |

**矩阵结论：12 格判定 11 PASS + 1 格主面 PASS/推箱子项语义边界记档（cell 6，
§四）**；Windows 段的全部降级格（4/10/11）与导出腿在 Mac 转正。

## 三、Mac 专节

### 1. C7 Look 真机注入格（旧机挂账→转正）

- **观察通道**：`CameraLook` 组件**刻意无 Reflect**（runtime-only，任何机器的
  scene_snapshot 都看不见——旧机若跑也会撞这堵墙）；改读轨道 rig 的 local
  Transform：offset=(0,h,distance) 被 yaw 旋转，XZ 角=yaw 的忠实投影。
- **开通道**：PIE capture on，`input.motion {dx:200,steps:20}` → rig 角 0→
  **−57.29578°**（=−dx×sensitivity=−1.0 rad，T09 格 4 新语义量纲**精确到 1e-5 度**；
  窗口 57.2958±8.5°）。
- **RMB 让位（决策 3-③）**：经 PIE 游戏自身 BRP（15702，`JackdawRemotePlugin` 在
  PIE 形态同样监听）写 `ButtonInput<MouseButton>` 按住 Right → 同注入 rig 恰再转
  −57.29578°。语义澄清（记档）：合成 motion 经 capture 以**真 MouseMotion 事件**
  入游戏，RMB 按住帧 **crate 自有通道合法消费它**（「两通道一致」的设计本义），
  故断言=「**恰单写**」：若桥不让位则双通道各写一次=−114.59°；实测单写。
- 证据：`t11t3-a3-mac-console.log`（三轮迭代：atan2 形态错/资源路径形态错修正后
  终轮双 PASS，中间轮留档）。

### 2. N13 复发率 ×10（旧机挂账→完成；buglist N13 已更新）

10 轮 PIE connected（每轮 hold ~6s 跨 T10b 的 1.9s 窗口）：**10/10 全复发，累计
57 次 panic（~5-6 次/周期）**。三项新刻画：①Mac 签名 `swap_remove index (is 0)
should be < len (is 0)`（空 vec 退化形态，与旧机 is 1/len 1 同根）；②**第二个受害
系统 `jackdaw::pie::cleanup_session_on_stop`**（原刻画只有 drain_game_events）；
③Mac 上全部被 bevy 系统错误处理器捕获（`Encountered an error in system …:
Exclusive system panicked`，编辑器全程存活），旧机形态直接杀死编辑器——严重度依
机器形态。**真栈仍缺**：RUST_BACKTRACE=1 在 Mac debug 构建不可用（§八-3），panic
消息签名是唯一形态证据。计数行在 `t11t3-a2-mac-console.log`（N13_X10 行）。

### 3. 格 11 Stop 铁证（旧机降级→转正）

`t11t3-place.bsn` SHA256 前后一致 + `assets/.jackdaw-pie/current-*` 清零；stop 时
玩家正被 W 驱动至墙（z=−2.440）、rig 每帧跟随——文档态零污染回归面成立
（`t11t3-a2-mac-console.log` CELL11 行）。

### 4. 格 10 导出腿（Mac 补全三态）

`jd export`（release profile，631 components）→ staged `.jackdaw/dist/release/`
（exe+assets+export-manifest.json 5 files，editor-private 条目正确排除）；
**staged exe 独立启动冒烟 PASS**：模板玩家落定 (-2, 0.860, 0)，事件注入 W 1s →
z −2.440 墙停——与 direct run（debug）、PIE、编辑器通道同数字。证据
`t11t3-export-mac-console.log`（构建+staging 全文）+ `t11t3-export-mac-smoke.log`
（staged 运行日志）。至此格 10 四通道（编辑器/PIE/direct/导出）齐——**三态一致
升级为四通道一致**。

### 5. 格 12 无物理形态（真工程落袋）

`jd new --no-modules` + 暖工程仪表（§九-3）→ 冷编 1m44s 绿（Transform fallback
编译面）；行为抽查（事件注入）：W 按住 1.2s 玩家 z 0→−4.93（fallback 步进、无碰撞
穿过墙位——教学语义「nothing stops the player」字面验证）；Space 点击 → 游戏日志
`Jump! (needs the physics module to leave the ground)` + y 恒 1.0（**教学退场断言
的真机形态**）；快照世界零 avian/RigidBody/Collider 组件；无重力落定。证据
`t11t3-nophys-mac-game.log`。与 scaffold teaches 85/85（T1）互补闭环。

## 四、R2_CELL6_PUSHCUBE 判定：kinematic 语义边界，非缺陷

**双机事实**：Windows dx=0.00（`t11t3-c-progress.log`）= macOS dx=1.14e-07
（`t11t3-c-mac-progress.log`）——玩家按 4 m/s 撞向落定的 FallingCube（Dynamic），
立方体纹丝不动。Windows 段已定性「行为发现非环境」；本段完成源码级判定。

**机制链（avian3d 0.8 源码实读）**：
1. `MoveAndSlide::move_and_slide`（`character_controller/move_and_slide.rs:483`）是
   **纯 shape-cast 数学**：sweep→接触面裁剪→返回 `MoveAndSlideOutput{position,
   projected_velocity}`，不写任何 body 状态；模板随后 `transform.translation =
   output.position`（位置直写形态）。
2. sweep 以 skin width 停在立方体表面外（T11-T1 已证 sweep 只见带 `ColliderOf` 的
   collider）——**永不产生重叠**；`depenetrate` 只解自己的位置，不推对方。
3. 求解器侧（`dynamics/solver/plugin.rs:713`）：`ContactConstraint::generate` 消费
   双方的 **`LinearVelocity` 分量**算相对速度——模板玩家的 avian `LinearVelocity`
   恒零（从未写入），无重叠+无相对速度 → 法向约束无冲量可发，立方体不动。
4. avian RigidBody 文档「kinematic 会真实影响碰撞的 dynamic 体」成立于**有重叠**
   （位置直写推进重叠，penetration 修正推开 dynamic）或**有速度**（velocity-based
   kinematic）两种形态——本模板两者皆无，是**决策 1-A 选取形态的直接后果**（方案
   明言其收益「不被 FallingCube 推挤」；「不推挤别人」是该取舍的另一面）。

**处置**（方案决策 1 预期口径，不为过格改引擎/avian/模板）：book
`user-guide/player-controller.md` 碰撞节补边界段（说明+将来形态指引：写
`projected_velocity` 进 avian `LinearVelocity` + `CustomPositionIntegration`，或
Dynamic+锁轴）；buglist 立 **A2**（⚪ 设计边界，含完整证据链）；矩阵该子项记
**FAIL（语义边界，双机一致，已文档化）**。墙停/贴墙滑/高速不穿透三子项不受影响。

## 五、book 文档与 doc 核对

- 新章 `book/src/user-guide/player-controller.md`（406d116b，SUMMARY 挂 game-input
  后）：五件套表、CameraRig 两模式五参数表+多 rig 边角、跳跃与碰撞机制
  （move_and_slide 一句话+avian 指引+GameConfig.gravity 双消费同源）、摆放链
  step-by-step（修好的 C10 五件套，「缺一件=悬空不动」）、参数调法（per-entity=
  组件/game-wide=config）、存量工程迁移注记（「类型面免费、行为面一行」）、30 秒
  清单；**Mac 段补「不推挤 Dynamic 体」边界段**（§四）。
- `game-input.md` 交叉更新（Look 消费面）、`physics.md` 玩家描述同步——Windows
  段产出，Mac 段核对无进一步缺口。
- **doc 五件套（C10）Mac 链上复证**：照 doc 字面五 component.add 全 finished +
  行为复活（§二格 2）。

## 六、全量门（Windows 归档 8 件；QA 将在 Mac 亲跑复核）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all --check` | **CLEAN** | `t11t3_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **CLEAN**（一次 collapsible_if 整改后过） | `t11t3_clippy_ws.log` |
| Lint 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **CLEAN** | `t11t3_clippy_physics.log` |
| guards 回归 | `cargo test -p jackdaw --test guards` | **222/222 passed**（T2 基线 221+N14 新增 1） | `t11t3_guards_regress.log` |
| fast | `cargo xtask fast` | **2961/2961 passed (1 leaky), 2 skipped** | `t11t3_gate_fast.log` |
| integration | `cargo xtask integration` | nextest 启动行在档；**归档止于编译 warning、无终局 Summary 行**（迁移中断形态）——以 QA Mac 亲跑为准 | `t11t3_gate_integration.log` |
| doctests | `cargo test --workspace --doc --features dylib` | workspace doctests 过；Windows 环境性 jackdaw_bind 1 失败→**复跑 PASS（1 passed）**（历史口径） | `t11t3_doctests.log` + `t11t3_doctests_bind_rerun.log` |

Mac 段新增改动（book 边界段+buglist 三条+loop 证据）不改 Rust 代码面；QA 复核
随全量门重跑（注意 §八-3 RUST_BACKTRACE 禁令）。

## 七、偏差与记档分级

1. **🔴 环境-工具面（Mac，非代码）**：RUST_BACKTRACE=1 + debug wgpu 构建 =
   libunwind SIGSEGV（wgpu-core `snatch::trace::LockTrace` 在 debug_assertions 下
   每次锁获取调 `Backtrace::capture()`；实测编辑器外直跑游戏 164s 后崩于
   `bevy_pbr GPU clustering upload→create_buffer_init→LockTrace::enter→
   _Unwind_Backtrace→decodeFDE KERN_INVALID_ADDRESS 0x0`，崩溃报告
   `t11t1-game-2026-10-28-121743.ips` 系统在档）。**Mac 全部脚本禁用
   RUST_BACKTRACE**；代价=N13 真栈不可得。QA 在 Mac 跑门禁/真机同样勿设。
2. **🔴 环境（Windows 段原记）**：PIE 3/3 崩（Mac 已转正）；导出异目录启动受阻
   （Mac 已转正）；`cmd start /B` BRP 不可达（Windows 工具史，脚本已切 Process API）。
3. **⚪ M9 sensitivity 行为面残留**：authored 0.008 的行为断言双机均未采样（盘上
   M8 有证、量纲 0.005 由 C7 开通道活证到 1e-5 度）；guards 有等价数学面。eye_height
   补腿已闭环（§二格 9）。
4. **⚪ 双 rig 时序竞争**（旧机已知）：Mac fp 场景快照实证双 active=true（模板 rig
   抢激活窗口），行为无害（R4 断言不受扰），维持记档口径。
5. **🟡 Mac 脚本断言/实现返工**（不改产品结论，中间轮 console 全留档）：a3 两轮
   （jq atan2 参数形态/资源路径 re-export 形态）；腿 C 两轮（`py()` 双 `-c`、
   rig_local 插值+取 first、resource 写无法表达 just_pressed——RemoteLast 时序活探
   针实证，改 `world.write_message` KeyboardInput 事件通道）；腿 A 一轮（PIE 探针
   冷编窗口+进程路径）。M7PRE 正则 BUG：`1\.3` 不匹配 f32 序列化
   `1.2999999523162842`——盘上核验属实、正则已修、行为面由 R4 PASS 闭环，未重跑
   整链（记 FAIL-as-assertion-bug 于 `t11t3-a-mac-summary.txt`）。
6. **⚪ N14 undo 语义**（§一）；Windows 段腿 A 脚本三轮学习成本（原记维持）。
7. **测试账本**：Windows 段 guards +1、teaches 扩 4 锚；Mac 段零新增测试（真机
   验证段），bash 脚本沉淀 4 件（a/a2/a3/c）。
8. buglist：**无打钩**；N13 补 Mac 测定注记、N14 闭环注记（待 QA 勾）、A2 新立
   （§四）。

## 八、macOS 环境与工具面记档（QA/Mac 重跑须知）

1. **nohup 剥 DYLD_***：`nohup exe` 丢 DYLD_LIBRARY_PATH（实砣隔离三连测），
   编辑器启动必须 `nohup env DYLD_LIBRARY_PATH=… exe`；路径=
   `~/.rustup/toolchains/1.99.0-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/lib`
   （编辑器=bevy dynamic_linking 构建）。
2. **输入注入双通道**（无 PostMessage 等价物）：按住=BRP `world.insert_resources`
   写 `ButtonInput<KeyCode>`（pressed 跨帧持久；**just_pressed 被输入 clear 吃掉，
   不可表达点击**）；点击=`world.write_message` 写
   `bevy_input::keyboard::KeyboardInput`（需 `world.query` Window 实体 id；经游戏
   自有 keyboard system，与原生键同时序——jump 由此通）。RMB 同理（mouse 资源需
   fixture register_type）。封装可复用 `t11t3-matrix-{a3,c}.sh`。
3. **RUST_BACKTRACE 禁令**（§七-1）。
4. **PIE 游戏进程**在 `<project>/.jackdaw/target/game/debug/`；首跑冷编数分钟——
   判活= `pgrep -f 't11t1-game$'` + 游戏 BRP 15702 双证（勿用 `target/debug/`
   路径模式与短窗口）。
5. **BRP 资源键=定义路径**（`bevy_input::mouse::MouseButton`），非 re-export；
   f32 序列化长尾（1.3→1.2999999523162842）注意文本断言正则。
6. **Cargo 锁竞争**：编辑器 PIE 构建（`.jackdaw/target`）与外部 `cargo build` 并行
   偶发一方等锁（N13 #6 轮 connected 延迟一轮自愈），避免同窗操作。
7. 截图通道未启用（screencapture 权限未验）——BRP scene_snapshot 主证据通道，
   与既定口径一致，本段无截图需求。

## 九、工程处置与提交清单

1. **进程清零**：两段各自收尾（jackdaw/t11t1-game/t11t3-nophys pkill）。
2. **Windows 段提交**（=406d116b 已含）：产品代码（src/commands.rs、scaffold、
   book）+测试+报告初稿+归档。
3. **暖工程记档（Mac）**：`/Users/zhanglinbo/workspace/loop-mac/t11t1-game` =
   `jd new` 产物 + main.rs 三处仪表（`JackdawRemotePlugin`（t11t2 §6.5 惯例）+
   `register_type` 键盘/鼠标 ButtonInput（注入通道前置））+ Cargo.toml 加
   jackdaw_remote path 依赖；**模板本体零改动**（scaffold 产物与 406d116b 同源）。
   `t11t3-nophys` 同款。产物场景 `assets/t11t3-{place,fp,fast}.bsn`（Mac 重建，
   authored 值同 Windows：2.0/6.0/5.0/0.008/FP+eye_height 1.3/8.0）。
4. **Mac 段提交**（loop/t11-final，英文，风格随 406d116b）：bash 脚本 4 件、
   `loop/t11t3-live/` Mac 证据、本报告（合并版）、book 边界段、buglist 三条。
   无产品代码修复（cell6 判定=不修），无红绿测试提交。
