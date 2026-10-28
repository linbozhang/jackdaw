# T11-T2 实施报告：参数面 + 编辑器摆放链真机

> 任务：`loop/plans/t11-player-template.md` §二 T2（C5+C6+C9；决策 6/7）+ 附带任务
> N13 复发率测定。分支 `loop/t11-params`（自 main fad046ce）。**零产品代码改动**
> （纯验证+文档核对+脚本沉淀；发现的缺陷候选全部记档不修——归 T3/另立项）。
> 开局自检：main=fad046ce，噪音仅 .gitignore M+buglist.md 未跟踪 ✓。
> 归档：门禁 `loop/reports/t11t2_*`；真机证据 `loop/t11t2-live/`（console/editor/game
> 日志）+ 正式脚本 `loop/qa/t11t2-{probe*,live-a,live-b,live-c,n13,mygame}.ps1`。

## 〇、执行摘要

「放玩家+地面即玩」的编辑器摆放链与「关键参数 Inspector 可调」两验收腿在真机
走通；三通道（模板链/摆放链/存量工程链）各有独立证据。**环境重大事件**：T10b
挂账的 0xc0000005 在本任务窗口复发并**杀死了全部 PIE 形态**（windowless 与
windowed 均 100% 崩，≥10 次 play 尝试零 connected）——PIE 依赖的行为断言全部
按 T10 降级口径转 direct run 通道承载（同一 exe、同一场景文档），C7 Look 真机
注入格与 N13 ×10 复发率测定因通道死亡**不可执行**（诚实记档）。真机过程新发现
缺陷候选 C10-C12 三条（文档口径缺口/patch 丢字段/保存 skip 失效——均不阻塞验收
链，机制与证据见 §五）。

## 一、三通道验证（验收句核心）

| # | 通道 | 证据 | 结果 |
|---|---|---|---|
| 1 | **模板开箱链**（T1 已证，本任务回归） | 腿 C 每轮 direct run：模板玩家 (-2,0.86,0) 落定、W 走墙停、跳 apex、rig 自动激活 | PASS（T1 六腿复验口径） |
| 2 | **编辑器摆放链**（本任务核心） | 腿 A 全 BRP 驱动构建（Add Entity cube → component.add `t11t1_game::PlayerMarker`/`PlayerController`/`avian3d::dynamics::rigid_body::RigidBody`=Kinematic/`jackdaw_avian_integration::AvianCollider`=Capsule{0.35,1.0} → `entity.add.camera_rig`+`entity.reparent` 挂玩家下 → 地面 cube+`physics.enable` → `scene.save`）；腿 C 该场景文档 direct run：用户玩家落定 0.860、W 走 z 序列 → **-2.440 墙停冻结**、Space 跳 y 序列 apex **2.007**（理论 1.892±0.3）、W+D 贴墙滑 x travel 2.20 m z 钳 -2.440、rig 物化（Projection+ActiveCameraRig） | **PASS**（`t11t2_a_console.log`/`t11t2_c_console.log`） |
| 3 | **存量工程升级链**（re-export 收益面） | my-game（T06 时代老工程，早于 PlayerMarker/GameConfig）：Cargo.toml **零改动**（无 camera_rig 直接依赖）；预热构建编译清单含 `jackdaw_camera_rig`；游戏自身 schema extractor 报告 `CameraRig`/`ActiveCameraRig` 作者面类型在场（场景加载 resolve 的 registry） | **PASS**（`t11t2_mygame_extractor_stderr.log`+console） |

通道 3 的语义边界（如实记录）：零改动获得的是**作者面类型**（CameraRig/
ActiveCameraRig 可摆放可存档可 resolve）；**运行面**（CameraLook 类型+驱动系统）
需要工程 lib.rs 一行 `add_plugins(JackdawCameraRigPlugin)`（my-game 未接线故无
驱动）——「类型面免费、行为面一行」即 re-export 决策（2-A）收益面的准确口径，
T3 book 迁移注记照此写。

## 二、C5 参数面三处一致（Inspector 可调验收腿）

对象：摆放链用户玩家 `PlayerController` 与用户 rig `CameraRig`（都在场景文档里，
区别于模板 spawn 的运行态实体——后者本就不可编辑）。

| 态 | 证据 | 结果 |
|---|---|---|
| **编辑态**（Inspector 编辑） | `component.set` move_speed 4.0→2.0、distance 10.0→5.0（零 warning；T02 面的 B3 另证 2.0→3.5→2.0 往返） | PASS |
| **盘上态**（保存落盘） | `scene.save` 后 bsn 文本 `move_speed: 2.0` ✓ `distance: 5.0` ✓ | PASS |
| **重开态**（冷重启编辑器→scene.open→再存） | B1：reopen→save 后 move_speed=2.0、distance=5.0 保留；jump_speed 见 C11 记档 | PASS |
| **运行态**（Play 行为） | 腿 C 同场景同参数：placed 玩家 **1.62 m/s**（authored 2.0）vs 模板玩家 **3.25 m/s**（4.0）同窗对照=「改半→走速减半级」；rig local offset=**(0, 3.15, 4.61)**（distance 5 理论 (0, 1.2+5sin0.4, 5cos0.4) 精确命中）；跟随恒定性：玩家转向前后两次采样 \|local\| 均 **5.578**、lenDrift=**0.000** | **PASS** |

PIE 编辑器内 Play 的行为面因 PIE 死亡不可采样（§四），行为断言由 direct run
承载（同一 exe 同一文档，T10b 绕行口径+T10 格 9 降级先例）。

**T02/T03 回归**（B3/B4）：
- T02：component.set 一次=undo 恰 +1 条（0→1→0）；undo 后字段回 2.0（存档文本核）
  ——**PASS**（含 C11 丢字段记档）。
- T03：真 reparent（rig→floor，域 id 4488v0→4490v0）= undo 恰 +1/-1；undo 后
  ChildOf 回 4488v0（玩家）——**PASS**。

## 三、C9 多 rig 机制验证 + 文档核对

| 格 | 断言 | 证据 | 结果 |
|---|---|---|---|
| 哑相机（双 rig 无标记） | lone-rig 让位：无一物化 | 腿 A A2：PIE（崩前一轮）双 rig 场景投影无 ActiveCameraRig、`pie.play_input_toggle` 被拒（cancelled，帧流无图）；腿 C round 2（strip ActiveCameraRig 后）：placedRig active=False materialized=False | PASS |
| 玩家仍被驱动（哑≠死） | 无相机不阻 ECS | 腿 C round 2：strip 态下 W 注入 placed 玩家 z 2.00→-0.40 | PASS |
| 手加激活（文档化语义） | 手加 ActiveCameraRig → 物化 | 腿 A A3：文档态 add finished+**存档保留**（`savedDocContainsActiveCameraRig=True`）；腿 C round 1：游戏加载该文档 → placedRig materialized=True active=True | PASS |
| 启动时序竞争（边角发现） | 模板 rig 可能抢激活 | 腿 C 三轮中一轮模板 rig 在场景实体 spawn 前被 lone-rig 抢先激活（tplRig materialized=True）、其余轮没有——**时序敏感**，双相机并存与 C6 同族（order 未定），如实记档不修 | 记档（⚪） |
| 模板 doc 口径核对 | 「加 PlayerMarker+PlayerController」够吗 | **不够**（C10 发现，见 §五）：physics 形态 move_player 的 Query 还要求 `PlayerVelocity`+Kinematic `RigidBody`+`AvianCollider`——照 doc 摆的玩家**不动**（腿 C 首轮实测：用户玩家 y 悬空 1.000 不落定、W 零位移；补 PlayerVelocity 后全行为复活） | **记档（C10，文档缺口）** |

## 四、C7 Look 真机格 + N13 复发率（环境受阻记档）

### C7（T1 偏差 4 留给 T2 的项）

原计划：经 PIE 的 `input.motion` 注入通道补 Look 量纲真机证据（桥让位+crate RMB
通道单倍/零/双倍对照）。**不可执行**：`input.motion` 是编辑器侧 BRP，转发链
（`live_input.rs` collect_forwards）要求 capture active，capture 依赖 PIE 帧流，
PIE 本体在当前环境窗口 100% 崩溃（见下）。direct run 无 motion 注入通道（真
raw input 不可 PostMessage 合成；键盘改绑 Look 不可行——`game_input.rs` 的 Key
绑定对 Delta2D 无 value 贡献，仅 MouseMotion/GamepadAxis 产生 delta，本机无实体
手柄）。**量纲断言由 guards 数学面承载**（T1 已 ±1e-4 钉死：`yaw -= dx×0.005`、
RMB 让位镜像 crate 通道）——与 T1 偏差 4 同因升级：通道缺口从「direct-run 无注入」
恶化为「PIE 整体死亡」，真机格挂账 T3 矩阵（环境恢复后补）。

### N13（drain_game_events swap_remove panic 复发率）

**×10 连跑不可执行**：N13 触发面=PIE connected 后 ~2s 的 `drain_game_events`
事件流；当前环境 PIE 游戏**connected 之前**即崩（exit code 0xc0000005，launched
后 ~7s），事件链从未建立——drain panic 的观察窗不存在。实测 play 尝试 ≥10 次
（腿 A v2 三次、v3 三次、probe2 windowed 一次、腿 B 首轮探针等）**全部
0xc0000005、零 connected、零 drain panic**。RUST_BACKTRACE=1 全程在编辑器环境
（`t11t2_pie_crash_editor.log` 在档，无 swap_remove/panic 于 drain 面）。**按
T10b 环境归因口径记档不虚报**：0xc0000005 是 T10b 已裁定的 NVIDIA 驱动态
（T10b 报告 §四-b 主因），本次复发把 windowed PIE 形态也杀死（T10b §八之后
驱动窗口又变）。N13 的 ×10 与真栈获取**顺延到 PIE 环境恢复后**（建议主控在
T10b 挂账调查里合并跟踪；本任务产出的环境数据=10+ 次崩溃形态样本，归档
`t11t2_pie_crash_*.log`）。

## 五、真机新发现（缺陷候选 C10-C12，只记不修）

- **C10（🟡，文档口径缺口——摆放链验收句的直接威胁）**：模板 doc「add
  PlayerMarker and PlayerController to any entity」不完整——physics 形态
  `move_player` 的 Query 要求 `(PlayerController, avian Collider, PlayerVelocity,
  Transform) With<PlayerMarker>`，模板 spawn 的玩家四件齐、编辑器摆放的实体按
  doc 只加两件 → **玩家不被驱动（重力都不积分）**。真机证据：腿 C 首轮 placed
  玩家 y=1.000 悬空+W 零位移（模板玩家同窗全动）；bsn 注入
  `t11t1_game::PlayerVelocity(Vec3::ZERO)` 后七行为全绿。修复方向：T3 的
  player-controller book 章+模板 doc 补「物理四件套」（或 PlayerVelocity 由
  move_player 用 Required 组件/按需插入——程序裁量）。
- **C11（🟡，patch 丢字段）**：单字段 `component.set`（move_speed）后保存，
  PlayerController 的**未编辑字段 jump_speed 从文档消失**（B1 dump：块内只剩
  move_speed）。行为无损（游戏加载缺字段取 Default=4.5 恰为原值），但若
  jump_speed 曾被改成非默认再编辑 move_speed，改值会丢。修复方向：set 单字段
  时从 schema 默认合并整组件再落 patch。
- **C12（⚪，保存 skip 失效/机制与注释不符）**：`scene_io/mod.rs:78`
  SKIP_COMPONENT_PATHS 明确排除 `jackdaw_camera_rig::ActiveCameraRig`（注释：
  persisting it plants a rig that fights those systems），实测
  `component.add` 的 ActiveCameraRig **保存进 bsn**（A3：bsn 文本含之）。当前
  Automatic 激活模式下行为无害（且恰是摆放链「手加标记→Play 即玩」可用的
  基础——若 skip 生效字面链反而断）；Gated（multiplayer）模式下的打架面与
  注释警告一致。修复方向：明确语义二选一（skip 生效+摆放链文档改「Play 后
  Live 加标记」；或承认作者可持久化标记+删 skip 行+改注释）——建议 T3 与
  C9 book 章一并定案。
- 顺带 ⚪：「Outliner: 7324v0 never joined the document after 64 passes」WARN
  出现于摆放链构建中（`t11t2_pie_crash_editor.log` 00:44:47）——某实体未入档，
  未影响本链断言（文档核对全过），记档备查。

## 六、环境事件与工具面记档（影响后续任务的实操知识）

1. **PIE 全形态死亡**（本任务最大环境事件）：windowless+Vulkan（腿 A v2/v3
   共 6 次 play）与 windowed+Vulkan（probe2）均 0xc0000005 于 connected 前
   ~7s；direct run 同 exe 同场景稳定（腿 C 两轮+多探针零崩）。T10b 绕行口径
   中「PIE 用 dx12」已被主控禁用（0x8007000E）——**当前无可用 PIE 形态**。
2. **编辑器内 schema extractor 环境性失败**：prebuild 后的
   `run_binary_extractor` 每轮 ~8s 非零退出（stderr 止于 AdapterInfo，非
   120s/600s 超时）；同一 exe 手动跑（编辑器死后）~15s 成功产出 901KB schema
   （含 PlayerMarker/PlayerController）。处置：手动 extractor 产物写入
   `.jackdaw/schema.json`+时间戳重触发 watcher（`PIE: refreshed project types
   from schema (8 project components)` 证实拾取）——等效正规链，脚本已固化。
   `JACKDAW_SCHEMA_EXTRACT_TIMEOUT_SECS=600` 对该失败无效（非超时形态）。
3. **component.add 需 FQ type_path**：短名（'PlayerMarker'/'ActiveCameraRig'）
   报 no registration；全路径（`t11t1_game::PlayerMarker`、
   `jackdaw_camera_rig::ActiveCameraRig`）通过。
4. **`scene.save {path}` 需绝对路径**：相对路径按编辑器 cwd 解析 → os error 3
   （play_current 的 save-before-launch 连带拒跑）。
5. **project 组件值不在编辑器 ECS 快照**（patch 形态）：值断言走「save→bsn
   文本」面；ChildOf patch 的域 id（`4488v0` 形态）与快照 entity id 不同域。
6. 15702 红利通道：暖工程 main.rs 的 `JackdawRemotePlugin` 使 direct run 游戏
   可 BRP 采样（`jackdaw/scene_snapshot` 可用；`jackdaw/status` 在游戏侧本就
   不存在——T1 脚本判活实为非 null 容错）。

## 七、门禁（日志全文复核；归档 `loop/reports/t11t2_*`）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all --check` | **CLEAN**（exit 0 零输出） | `t11t2_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **CLEAN**（exit 0，log 6819B 无 error） | `t11t2_clippy_ws.log` |
| Lint 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **CLEAN**（exit 0） | `t11t2_clippy_physics.log` |
| fast | `cargo xtask fast` | **CLEAN，2961/2961 passed (1 leaky), 2 skipped**（=T1 基线 2961，零漂移） | `t11t2_gate_fast.log` |
| 改动面测试 | 本任务零产品代码改动，fast 全量覆盖既有防线 | — | — |

## 八、偏差与记档分级

1. **🔴 环境（非代码）：PIE 全形态 0xc0000005 复发**——C7 真机格、N13 ×10、
   编辑器内 Play 行为采样三条腿受阻，按 T10b 归因+T10 降级口径处置（direct
   run 承载行为、guards 承载量纲、N13 顺延）。不虚报、不当代码问题。
2. **🟡 C10/C11**：摆放链文档缺口+patch 丢字段——记档不修（C10 建议随 T3
   book 章收口；C11 独立小修候选）。
3. **⚪ C12+竞争边角+extractor 失败+outliner WARN**：机制偏差与时序敏感边角，
   证据在档。
4. **⚪ 腿 B 首两轮的断言面返工**（快照 patch 值/域 id/实体选择器）为脚本侧
   学习成本，最终轮全绿；中间轮 console 留档可考。
5. **测试账本**：零新增测试（纯验证任务；guards 221/teaches 85 维持 T1 面），
   脚本沉淀 8 件（probe×5 复用 2、live-a/b/c、n13、mygame）。
6. **buglist**：无打钩（C 系 T1 已立；本任务新发现 C10-C12 待主控立账）。

## 九、工程处置

- 暖工程 `H:\workspace_AI\t11-live\t11t1-game`：`assets/t11t2-place.bsn` 为本
  任务摆放链场景（含 authored 2.0/5.0/ActiveCameraRig/PlayerVelocity 注入版
  仅存在于 target\debug\assets 的临时副本，源 assets 版未注入 PlayerVelocity）；
  `.jackdaw/schema.json` 为手动 extractor 产物（官方命令输出）。T1 的
  `assets/scene.bsn` 模板场景未动。
- my-game：预热构建产物在（编译清单含 camera_rig 为本任务证据）；工程零改动。
- 跑后进程清零（jackdaw/t11t1-game/my-game 全无）。
- **提交**：显式 pathspec——`loop/qa/t11t2-*.ps1`×8、
  `loop/reports/t11-t2-report.md`、`loop/reports/t11t2_*.log`×12；既存噪音
  .gitignore/buglist.md 未触碰。
