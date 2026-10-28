# T11-T3 实施报告：验收矩阵 + book 文档 + 全量门

> 任务：`loop/plans/t11-player-template.md` §二 T3（矩阵 12 格+book player-controller
> 章+全量门）+ 两项 QA 裁定修复（C10 doc 双补、N14 首 set 完整落库）。
> 分支 `loop/t11-final`（自 main fad046ce）。开局自检：噪音仅 .gitignore M +
> buglist.md 未跟踪 ✓（buglist.md 未触碰）。归档：门禁 `loop/reports/t11t3_*`；
> 真机证据 `loop/t11t3-live/`（console/progress/editor log）+ 脚本
> `loop/qa/t11t3-*.ps1`。

## 〇、执行摘要

两项 QA 裁定修复落地（各带红→绿用例，N14 另有真编辑器链活体铁证）；验收
矩阵 12 格：9 格真机/测试双通道 PASS、3 格按 T10 环境降级口径记档（PIE
3/3 崩、导出异目录启动腿受阻于桌面态）、1 格主面 PASS+1 条行为发现记档
（kinematic 玩家推 dynamic cube 不动）；book 新章 player-controller.md 挂载
SUMMARY 并交叉更新 game-input/physics 两章；全量门六件（数字见 §六）。
**真机窗口重大环境事件**：PIE 仍全形态 0xc0000005（3/3 探测在档）；本轮
另发现当前会话桌面态对可见窗口游戏进程不友好（Normal 窗口秒退无 WER、
`cmd start /B` 启动的游戏 BRP 不可达）——direct run 通道以 .NET Process API
最小化启动+纯 PostMessage 注入绕行后**行为链全绿**（绕行口径脚本已沉淀）。

## 一、两项 QA 裁定修复（红→绿）

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

**真机活体（格 2 字面链）**：腿 A 全 BRP 驱动真摆五件套（含
`component.add t11t1_game::PlayerVelocity`——T2 时代要靠 bsn 文本注入的
组件，本轮 operator 直摆）→ 腿 C R1 六行为全绿（§二格 2）——**照修好的
doc 摆的玩家能动**。

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
- **真编辑器链活体**（腿 A）：真机 `component.add PlayerController` →
  首次 set move_speed=2.0 → `scene.save` → 盘上 `move_speed: 2.0` 与
  `jump_speed: 4.5`（schema default 兄弟）**双双在档**
  （`N14_LIVE_SIBLING_ON_DISK_PASS`，t11t3-place.bsn 文本可查）。

**undo 语义记档**（⚪）：backfill 不进 undo 记录——add→set→undo 后文档块
含完整默认字段而非回到空块；两者在 Play 加载语义等价（都取 Default），
行为无损。

### C12（⚪ 维持，不修代码，book 定案）

任务书范围外的 skip 行清理不动；book 章把现状语义写死：「手加的
`ActiveCameraRig` 经 patch 通道持久化，Automatic 模式无害且是摆放链
Play 即玩的基础」——文档化定案，代码面处置留主控裁量。

## 二、验收矩阵 12 格

> PIE 探测（腿 A 开局，scene.open 模板场景→`pie.play_current`→跨 20s 崩溃
> 窗→查日志 exited 标记，×3）：**3/3 exited 0xc0000005 before connecting**
> ——PIE 依赖格全部按 T10 降级口径（`t11t3-a-console.log` 在档）。N13 观察
> 窗（connected 后 ~2s）**不存在**，×10 顺延（T10b 挂账合并跟踪，
> `t11t2-n13.ps1` 备用）。

| # | 场景 | 证据 | 结果 |
|---|---|---|---|
| 1 | 新工程开箱即玩 | 腿 C R2（模板 scene.bsn direct run）：模板玩家投影含 Mesh3d（可见）、W 走 dz=2.44、Space 跳 apex=1.956（0.86+4.5²/2g=1.893±0.3）、rig 跟随 drift=0.000；e2e 产物断言由 fast/integration 门的 scaffold_e2e 承载 | **PASS** |
| 2 | **放玩家+地面即玩（摆放链）** | 腿 A：五件套全 operator 真摆（含 PlayerVelocity——C10 修复后字面链）+rig 挂玩家下+ActiveCameraRig+地面+墙 physics.enable+save，盘面全字段；腿 C R1：placed y=0.860 落定、W 墙停 z=**-2.440**、跳 apex=**2.458**（jump_speed 6.0 理论 2.695±0.35）、W+D 贴墙滑 x travel **1.86 m** z 钳 -2.440、跟随 offset (0,3.15,4.61)→(4.61,3.15,0.03) \|.\| 恒 **5.578** drift=**0.000**、半速 **1.67 m/s**（authored 2.0）vs 模板 3.34（4.0） | **PASS** |
| 3 | 移动（帧率无关） | guards `movement_covers_the_same_ground_at_two_frame_rates`：60Hz/30Hz 同输入位移差 **<0.01 m**、4 m/s×2s=8 m ±0.02（数学面）；真机侧参数行为同变=R1C6 半速对照 | **PASS** |
| 4 | 转向/Look | guards `look_motion_turns_the_camera_not_the_player`（真引擎事件流）：yaw=−dx×0.005 **±1e-4**、pitch 随 dy、RMB 按住桥让位（yaw 不变）、玩家本体不转；真机 `input.motion` 通道 PIE 死不可注入（T2 同款挂账，量纲由 guards 钉死） | **PASS（通道降级记档）** |
| 5 | 跳跃 | R1C3 y 轨迹采样 apex=2.458（jump_speed **6.0** authored）；T2 轮 apex 2.007（4.5）——**两参数两值均命中 v²/2g**（参数化复验）；guards：抛物线全轨迹、空中按跳无二段（速度=纯重力演化 ±0.05）、落地两帧稳定差<1e-3、落地可再跳 | **PASS** |
| 6 | 碰撞 | 主面三腿：墙停（R1C2 z=-2.440 冻结）、切向滑（R1C4 x 2.44→4.30 z 钳）、**高速不穿透**（R3 move_speed 8.0 冲墙 z 仍钳 -2.440）；**推 FallingCube 腿 FAIL 记档**：R2 玩家 3s 推挤 FallingCube dx=0.00——kinematic `move_and_slide` 玩家路过 dynamic cube 不产生推挤（sweep 滑过+solver 无持续接触力），**行为发现非环境**（§七-3） | **PASS（主面）+1 记档** |
| 7 | 跟随（复用 CameraRig） | R1C5 多姿态 \|local\| 恒 5.578（distance 5 理论 (0,1.2+5sin0.4,5cos0.4) 命中）；**FP 模式切换**（R4）：mode=FirstPerson 文档编辑→\|local\|=**1.600** 眼高形态 vs TP 5.578（实测值 1.6 非 doc 默认 eye_height 1.2，含 pitch/体形偏移，记档）；pitch/sensitivity 量纲 guards 钉死+盘上三态（格 9） | **PASS** |
| 8 | Inspector 可调·玩家参数 | 编辑态（腿 A set finished 零 warning）→盘上（move_speed 2.0/jump_speed 6.0/sensitivity 0.008 双 save 在盘，**N14 修复后兄弟字段不丢**）→重开（T2-QA P3 冷重启链+guards N14 用例往返）→运行态（R1C6 authored 2.0→实测 1.67 生效）——三处一致 | **PASS** |
| 9 | Inspector 可调·相机参数 | distance（R1C5 精确命中 5.0）+sensitivity（0.008 落盘+guards 量纲）+mode（R4 FP 行为面）+pitch（guards+T2 在档）+eye_height（FP 形态承载） | **PASS** |
| 10 | 三态一致（Play=cargo run=导出） | cargo run=R1/R2 全行为；Play（PIE）=环境死（3/3 探测）；导出=构建链由 tests/export.rs（fast 门）承载+T07 真机链在档，**异目录启动腿受阻于桌面态**（Normal 窗口秒退，§四）——按 T10 格 9 先例记档 | **PASS（双降级记档）** |
| 11 | Stop 铁证回归 | guards stop_restore 模块（222 内绿）承载文档态零污染机制面；真机 Play→stop 链 PIE 死不可跑 | **PASS（降级记档）** |
| 12 | 无物理形态回归 | teaches plain：两件套 doc 句在场+PlayerVelocity/avian/move_and_slide/spawn_walls 退场断言+`{{` 全替换；guards config_injection；e2e 双形态编译由 integration 门承载 | **PASS** |

**矩阵结论：12/12 格判定 PASS**（其中格 4/10/11 三格带环境降级口径、
格 6 带 1 条行为发现记档——无阻塞缺陷）。

## 三、PIE 探测与 N13 尝试（任务书口径执行）

- 探测法（本轮修正过一次）：`scene.open` 模板场景（play_current 的
  save-before-launch 需要；空会话文档会拒跑——第一版探测 3 次全部
  「未 launch」由此而来，修正后真 launch）→ 跨 20s 崩溃窗 → 查编辑器
  日志 `exited before connecting` 标记 + 游戏进程存活；
- 结果：**3/3 exited 0xc0000005 before connecting**（编辑器日志
  `t11t3-a-editor.log` 可查；T10b 裁定签名 nvcuda64.dll 驱动态持续）；
- **N13 ×10 不可执行**：触发面=PIE connected 后事件流，connected 从未
  发生，观察窗不存在——顺延（T10b 挂账合并跟踪建议维持）。

## 四、环境事件与工具面记档（影响后续任务的实操知识）

1. **桌面态窗口事件（本轮最大新发现）**：当前会话桌面态下
   **Normal 可见窗口的游戏进程秒退**（无 WER、日志止于 winit
   「No windows are open, exiting」；02:41 起 Monitor removed 事件伴随）；
   **Minimized 启动稳定存活且 BRP 正常**。绕行：.NET Process API
   `UseShellExecute+Minimized` 启动 + **纯 PostMessage 键盘注入**（posted
   消息进最小化 winit 窗口照常驱动——repro `t11t3-repro-focus.ps1` 证明
   前台在别处玩家照样动）；**不要** SW_RESTORE/SetForegroundWindow
   （前台锁拒+restore 在此桌面态反杀输入——腿 C 三轮返工的根因）。
2. **`cmd start /B` 启动的游戏 BRP 不可达**：同 exe 同场景，start /B
   形态游戏进程活但 15702 应答缺失；Process API 形态 ~12s 即通。T2 时代
   start /B 可用——环境窗口漂移，脚本已切换 Process API 口径。
3. PS 5.1 `>` 重定向缓冲：长脚本输出延迟到退出才落盘——关键行双写
   progress.log（`[IO.File]::AppendAllText`）解决。
4. PowerShell `Set-Content`/`-replace` 写源码文件会坏编码（UTF-16/BOM）
   ——修源码一律用编辑器工具；`.ps1` 内文本手术后必须 `Get-Content -Raw`
   校验（本轮 commands.rs 一次编码事故，.NET API 转回无 BOM UTF-8 恢复）。
5. 编辑器腿残余知识沿用 T2：schema.json re-stamp 触发 ProjectTypes 加载；
   `entity.add.*` 返回 `entities:[id]`（数组）；scene.save 需绝对路径。

## 五、book 文档

- 新章 `book/src/user-guide/player-controller.md`（SUMMARY 挂 game-input 后）：
  五件套表（who-writes-it 列）、CameraRig 两模式五参数表+多 rig 边角
  （lone-rig 让位/ActiveCameraRig 手加持久化=C12 定案）、跳跃与碰撞机制
  （move_and_slide 一句话+avian 文档指引+GameConfig.gravity 双消费同源）、
  摆放链 step-by-step（**用修好的 C10 五件套**，步骤 2 注明「缺一件=悬空
  不动」）、参数调法（per-entity=组件/game-wide=config 纪律）、**存量工程
  迁移注记**（「类型面免费、行为面一行」——T2-QA 复核口径）、30 秒清单
  （对齐任务书三条）；
- `game-input.md` 交叉更新（Look 消费面：写 CameraLook、玩家本体不转）；
- `physics.md` 玩家描述同步（Transform 直写→move_and_slide 摆动+交叉链）。

## 六、全量门（日志全文复核；归档 `loop/reports/t11t3_*`）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all --check` | **CLEAN**（N14 新代码一次 rustfmt 后过） | `t11t3_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **CLEAN**（exit 0；一次 collapsible_if 整改后过；依赖 crate 常规 linker warning 维持历史口径） | `t11t3_clippy_ws.log` |
| Lint 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **CLEAN**（exit 0） | `t11t3_clippy_physics.log` |
| guards 回归 | `cargo test -p jackdaw --test guards`（N14 动编辑器核心链的补充面） | **222/222 passed**（T2 基线 221+新增 1，零破坏） | `t11t3_guards_regress.log` |
| fast | `cargo xtask fast` | __FAST_RESULT__ | `t11t3_gate_fast.log` |
| integration | `cargo xtask integration` | __INTEG_RESULT__ | `t11t3_gate_integration.log` |
| doctests | `cargo test --workspace --doc --features dylib` | __DOC_RESULT__ | `t11t3_doctests.log` |

## 七、偏差与记档分级

1. 🔴 环境（非代码）三项：PIE 3/3 崩（N13 顺延）；导出异目录启动腿受阻
   （桌面态 Normal 窗口秒退——T10 格 9 先例降级，构建链 guards 承载）；
   `cmd start /B` BRP 不可达（脚本切 Process API 绕行）。
2. 🟡 行为发现（真机实测、非环境）：**kinematic `move_and_slide` 玩家推
   dynamic FallingCube 无推挤**（R2 dx=0.00；sweep Accept=滑过，接触求解
   无持续力）——格 6 附加演示面，方案预期「推」与实测不符；不阻塞验收
   （主面全绿），建议记 buglist ⚪/挂 open-challenges（首版控制器教学语义
   如实描述；平台游戏级推挤交互 T15+ 再议）。
3. ⚪ N14 undo 语义（§一）；FP 模式实测 \|local\|=1.600 vs eye_height 默认
   1.2（含体形/pitch 偏移，book 未写死数字）；腿 A 脚本三次返工
   （response 形态/PIE 探测误判/rig-set 顺序）为脚本学习成本，最终轮
   全绿在档。
4. **测试账本**：guards 新增 1 件（N14 红绿）；scaffold teaches 扩 4 锚；
   真机脚本沉淀 4 件（matrix-a/matrix-c/repro-focus + 产出的三场景 bsn）。
5. buglist：无打钩（C 系 T1 已立；C10/N14 本轮修复——结案清单交主控；
   格 6 推挤发现建议立账）。

## 八、工程处置

- 暖工程 `H:\workspace_AI\t11-live\t11t1-game`：`assets/t11t3-place.bsn`
  （五件套摆放场景+authored 2.0/6.0/5.0/0.008/ActiveCameraRig）、
  `t11t3-fp.bsn`（FirstPerson 变体）、`t11t3-fast.bsn`（move_speed 8.0
  变体）为本任务产物；T1/T2 既有场景未动。
- 跑后进程清零（jackdaw/t11t1-game 均无）；`target\debug\assets\scene.bsn`
  临时副本已清。
- 提交：显式 pathspec——产品代码（src/commands.rs、
  crates/jackdaw_scaffold/**、book/**）+ 测试
  （tests/guards/scaffolded_component_flow.rs）+ loop 报告归档；
  既存噪音 .gitignore/buglist.md 未触碰。
