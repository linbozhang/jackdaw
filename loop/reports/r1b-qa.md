# R1b QA 验收报告：视口右键复发修复 + 中键平移

分支 `loop/viewport-unity-nav`，基线 main 1f8c4942，提交 **6dda4526**（5 文件 +335/-30）。
QA 会话 2026-10-24，真机驱动验收（plain debug 构建 exe）。
**最终 VERDICT: PASS**（首轮 FAIL 仅因门禁；fix1 43ba5cd8 复验通过，见文末 G 节）。

## 首轮 VERDICT: **FAIL（仅门禁一项；功能性证据达标，修复门禁后可 PASS）**

---

## A. 门（逐条单命令，QA 本机复跑）

| 门 | 结果 | 证据 |
|---|---|---|
| `cargo fmt --all -- --check` | ✅ 0 | FMT_OK |
| `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | ❌ 3 error | `doc_lazy_continuation` ×3 @ `src/modal_inputs.rs:55-57`（NavPan doc：54 行 `+ \`Condition::Down\`, so...` 被判 markdown 列表，后续行未缩进）。不带 `--features dylib` 同样复现 |
| `cargo xtask fast` | ❌ | 死于同一 clippy 步（fmt 步过）；`xtask/src/main.rs:39-51` 参数与上面完全一致，toolchain 固定 1.99.0 |
| `cargo xtask integration` | ✅ | 4951 passed / 3 skipped，362s |
| fast 内含 nextest（单独跑：`cargo nextest run --profile ci --workspace --lib --features dylib`） | ✅ | 2815 passed / 2 skipped |

**门禁虚报（🔴）**：程序报告 C 节声称「clippy 0 / xtask fast 0」，但程序自己留存的
`loop/reports/gate-xtask-fast-r1b.log`（第 38-81 行）就记录着**同样 3 个 doc_lazy_continuation
error**——报告与自身日志矛盾。修复本身是 3 行注释缩进（⚪），但「门禁红报绿」是流程红线。

单测确认：`input_contexts` 13/13（新增 4：`giant_delta_dropped_past_the_suppression_window`
/ `plausible_delta_at_the_limit_passes` / `middle_drag_pans_instead_of_looking` /
`giant_pan_delta_dropped`），`jackdaw_camera` 5/5（新增 3：pan 方向 / ∝speed / ∝ortho.scale）。

## B. 代码审查

1. **幅度闸 ✅**：`MAX_PLAUSIBLE_POINTER_DELTA=1000.0` + `drop_synthetic_pointer_jump()`
   整帧丢弃（返回 ZERO，非 clamp——clamp 仍会按上限转视角，违背「点击不动」契约）；
   作用于 fold 后的 motion（look 与 pan 双路径的共同上游，一处覆盖两路）；常量 doc
   注明实测来源（3.7e4–8.5e5 px，r1-disc-pm-none）；`FLY_LOOK_SUPPRESS_FRAMES=3`
   上升沿抑制原样保留。阈值两侧各约 3 个数量级余量。
2. **NavPan 互斥 ✅**：MMB+`Condition::Down` code-level 绑定（同 NavFly 型，不可
   preset 绑定）；motion 来自 NavLook 的**无条件** `Binding::mouse_motion()`（无 RMB
   门——中键拖拽拿得到 delta，关键风险点已核实）；`pan_active` 时 `(look=0, pan=motion)`
   中键优先；pan 走 ungated motion 绕过 fly 3 帧窗（注释论证成立：该窗为 grab 跳变而设，
   幅度闸已挡）。
3. **pan 方向 ✅**：`-right*dx + up*dy`，屏幕 y 向下 → 右拖=相机 -right、下拖=相机 +up
   = 内容跟手 = Unity Scene view grab 语义（与 2D viewport `pan_by` 同语义）；单测
   锁死。**ortho.scale ✅**：世界/像素 ∝ scale → pan 乘 scale 保持视野份额一致
   （单测 4× 验证）。⚪ 透视 pan 不随距离缩放（Unity Hand 按焦点距离缩放）——已知简化。
4. **会话管理 ✅**：`CameraPanActive` 与 fly 同构（hovered_world 起手 / MMB release 清 /
   focus loss+OnExit 双清 / pin 住 viewport）。跨视口无双 pan：2D latch 仅
   just_pressed+hovered 启动；node graph canvas 有 hovered 门 + drain；dock 走 UI
   picking。冲突论证核实成立。
5. **snap_toggle**：必要性成立（main 基线为 `just_pressed` 即切——若不改，中键平移每次
   起手误切 snap，已 `git show main:` 核实）。实现为 `just_released && travel≤4px`。
   **🟡 MessageReader 积压**：未按住期间不 `read()`，just_pressed 帧 read 会吃进前
   1–2 帧积压 motion——光标移动中点击 travel 可轻易超 4px → **点击漏切 snap**（方向
   安全：不误切，但漏切）。对照 viewport_2d/node_graph 均用 drain 模式，此处没有。
   修复一行：`just_pressed` 时 `motion.clear()`。次要：modal 早退在清零之前，退出后
   首击可能用旧 travel。⚪ snap_toggle 点击语义无单测。

## C. 真机验证（契约）

**注入能力探测（先做的）**：本 QA 会话移动类注入同样失效（`SendMoveRel` 不产生 winit
CursorMoved → hovered 门永不成立）——与程序会话同症、非会话态差异。**按钮/键盘注入
有效**：`r2-cancel-qa.ps1` 本会话复跑 **5/5 PASS**（RMB/Esc 到达并被处理，含
modal_before/after 断言），证明下述零跳变是「RMB 到达且相机不动」而非「RMB 未到达」。

| 契约项 | 数字 | 结论 |
|---|---|---|
| 1. 10 连按零跳变 | **三轮 30 次**（qa-full/2/3）全部 dyaw=dpitch=0.000000、pos_move=0.000 | ✅（程序轮 20 次一致） |
| 2. 右键拖拽旋转量 | look dyaw=0.0000 | ⚠️未覆盖-环境阻塞 |
| 3. 中键拖拽平移量 | panX len=0.000 / panY len=0.000（rot_ok=True） | ⚠️未覆盖-环境阻塞 |
| 4. 滚轮 dolly | wheel len=0.000 | ⚠️未覆盖-环境阻塞（hovered 门） |
| 5. WASD 位移 | wasd dist=0.000 | ⚠️未覆盖-环境阻塞（fly 门） |

数据：`loop/reports/r1b-qa-full{,2,3}/metrics.csv`。环境阻塞双证据：程序 stash 重建
HEAD 基线同样 look/move=0（r1-r1b-baseline）+ 本 QA 会话独立复现同症。
中键按钮路径到达佐证：pan 段 MMB 按住期间 rot_ok=True（yaw/pitch 纹丝不动）。

**截图**：`r1b-qa-full3/after-press-series.png`、`r1b-qa-full3/full-final.png`、
`r1b-qa-snap/qa-snap.png`。
**BRP 相机 Transform 亲查**：`world.query` 原始 JSON 存 `r1b-qa-snap/camera-raw.json`；
3D 视口相机 entity=3696v0 `translation=(0,4,8)` `rotation=(-0.22975,0,0,0.97325)`
（pitch≈-0.4636，与脚本 Get-FlyCamera 读数吻合）。

**snap_toggle 中键点击真机断言未成**：`SnapSettings` 未注册反射
（`world.get_resources` 返回 Unknown resource type，三种路径名均试），无法回读翻转
状态 → 列入用户手测。

## D. 判定理由

**FAIL 的唯一硬依据是门禁**：clippy 3 error → fast 红；且程序报告虚报门禁绿（自身
日志矛盾，🔴 流程问题）。功能面证据达标：契约 1 真机 30 次零跳变；幅度闸/NavPan/
方向/ortho/互斥的代码审查通过 + 18 项相关单测全绿 + integration 4951 全绿；拖拽类
四项属双会话一致的环境阻塞（移动注入不达 winit，HEAD 基线同样失败），非本改动回归。
**clippy 3 行缩进修掉、fast 复绿后即可 PASS**（拖拽类以单测 + 用户 30 秒手测收尾）。

## E. 用户手测清单（30 秒）

1. 3D 视口连点右键 5 次（不动鼠标）：视角纹丝不动（含第 2~5 次）。
2. 右键按住拖一圈：视角旋转，方向跟手。
3. 中键按住左右/上下拖：场景跟手平移（右拖场景右移），无旋转。
4. 滚轮 3 格 + 右键按住 W 两秒：前进/位移正常。
5. Translate 工具下：中键静止点击 → snap 开关翻转一次；中键拖拽平移 → 松开后 snap
   **不**被误切（移动中点击若偶发不切，属已知 🟡 积压问题，再静止点一次即切）。
6. 2D 画布中键拖拽 / node graph 中键拖拽 / dock 标签中键点击：各自原行为不变。

## F. 问题清单

- 🔴 [程序] 门禁虚报：报告 C 节「clippy 0 / fast 0」与自身留存 `gate-xtask-fast-r1b.log`
  （3 error）矛盾。
- 🟡 [程序] snap_toggle MessageReader 积压：移动中中键点击可能漏切 snap（修复：
  just_pressed 时 `motion.clear()`；顺带把清零挪到 modal 早退之前）。
- ⚪ [程序] clippy `doc_lazy_continuation` ×3（modal_inputs.rs:55-57，3 行缩进）——
  阻断门禁的直接原因。
- ⚪ [程序] snap_toggle 点击语义无单测；透视 pan 不随距离缩放（Unity Hand 语义差）。
- ⚪ [环境] **dylib 构建 exe 在本会话启动挂死**（进程活 CPU=0 无窗口 4 分钟；plain
  构建 5 秒就绪）——程序「静默不启动/重链恢复」之谜的定位；**后续真机一律用 plain
  构建**（`cargo build -p jackdaw`，258MB）。

## G. 复验章节（fix1：43ba5cd8，2026-10-24，QA 复验后 VERDICT: **PASS**）

程序提交 43ba5cd8（基线 6dda4526 之上，2 文件 +137/-8：`src/modal_inputs.rs` 注释重写、
`src/modal_transform.rs` snap_toggle 修复 + 3 新单测）。三项 FAIL 依据逐条复验：

1. **【🔴 门禁虚报】已闭环**。根因解释（CMD `%ERRORLEVEL%` 在 `&& a || b` 复合命令中
   按解析期展开旧值）与上轮观察自洽：上轮 `gate-xtask-fast-r1b.log` 日志本身如实记录
   3 error、只有探针误报——属工具缺陷非伪造数据，定性从「虚报」修正为「探针缺陷」，
   但上轮 🔴 记录维持存档。本轮四份日志（`gate-{fmt,clippy,xtask-fast,xtask-integration}-r1b-fix1.log`）
   核实：时间戳链连贯（04:17→04:29）、fmt 空文件=check 无输出、clippy 无 error、
   **测试计数 2815→2818 / 4951→4954 恰好 +3 = snap 新测试数**（日志与代码联动的一致性
   证据）、integration 日志全文无真实 FAIL（匹配到的字样均为 PASS 用例名）。
2. **【doc_lazy×3】QA 重跑归零**：`cargo clippy --workspace --all-targets --features
   dylib -- -D warnings` → 0 error（34.5s，CLIPPY_OK）。注释重写消除了行首 `+` 的
   markdown 列表误判。
3. **【🟡 snap_toggle 积压】修复正确**：重置块（`motion.clear()` + `travel=0`）前挪到
   modal 早退**之前**（modal 后首击旧 travel 边缘一并修复）；clear 仅在 just_pressed 帧
   调用，丢弃的是按下前积压的未读事件，按下后每帧 `pressed` 正常 read 累计——**正常
   拖拽行程判定不受影响**（唯一微损：按下同帧的新事件被清，1 帧几 px、方向安全）。
   3 个新单测（含 QA 指定的 `stale_motion_backlog_does_not_swallow_a_middle_click`）
   语义核实正确、harness 正确（frame() 手动清 edge 模拟 InputSystems），随 fast 全 PASS。
4. **无越界**：diff 仅 2 文件，与声称一致；工作区 clean（loop/ 为 QA 资产区，非 git 跟踪）。

QA 重跑门禁数字：**fmt=0（fast 内含）clippy=0 error fast=OK（2818 passed / 2 skipped，
含 3 个 snap 新测试 PASS）integration=程序日志 4954 passed / 3 skipped（核实+抽查，未重跑）**。

真机数据沿用上轮：43ba5cd8 相对 6dda4526 仅改注释与 snap_toggle（按钮路径），
R1b 核心路径（幅度闸/NavPan/pan 方向）代码逐字节相同，plain 构建的 30 次零跳变
继续有效；拖拽类环境阻塞维持原结论（双会话同症+HEAD 基线），用户手测清单兜底。

## H. QA 资产改动（loop/qa，非产品代码）

- `r1b-press.ps1`：修 panX/panY/wheel 三处 `-f` 参数中除法未括号（PS 逗号优先级，
  程序上轮「逗号解析修复」的漏网）；修后 Full 档五段全部走完。
- 新增 `r1b-qa-snap.ps1`：snap_toggle 中键点击真机驱动（因资源无反射未完成断言，
  保留供反射注册后复用）。
