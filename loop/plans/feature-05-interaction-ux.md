# 功能 #5 实施方案：工具交互与视口体验（视口跳变 / 工具取消 / Add 菜单 E2E / 交互驱动手册）

> 多 Agent 开发循环 · 策划产物（只写方案，不含代码实现）
> 日期：2026-10-22 · 策划：资深 Bevy 编辑器工程师 Agent
> 选题依据：**用户实机使用报障 4 项**（R1 视口右键按下视角重置；R2 标尺等工具无法取消；
> R3 用户插入任务——outliner Add 菜单建实体 E2E，见 loop/README.md「主动插入任务」；
> R4 loop/README.md 2026-10-23 交互验收新契约）。
> 调研方法：rg + Read，未运行任何 cargo 命令。bevy 证据取自
> `%USERPROFILE%\.cargo\git\checkouts\bevy-50d7e162b728c6c6\c9c397b`（Cargo.lock 锁定 `c9c397ba…`，
> bevy 0.20.0-dev，下文记作 bevy@main）；winit 证据取自
> `…\registry\src\index.crates.io-…\winit-0.30.13`（Cargo.lock 锁定版本，下文记作 winit-0.30.13）。

---

## 1. 范围与不做

**做**（四件，R4 是其余三项的验收基础设施）：

1. **R1** 修复「右键按下瞬间视角被重置/猛跳」：定位真因（给出两候选 + 真机判别法），
   修复后右键按住拖拽环视正常、按下瞬间视角不动；
2. **R2** 全部工具取消语义审计与修复：统一「Esc 取消当前工具/手势」的可靠通路，
   点选式工具（标尺）补 RMB 退出，产出审计矩阵；
3. **R3** Outliner Add 菜单建实体 E2E：真机验证「Add Cube/灯光 → viewport 可见 →
   Inspector 编辑生效 → 保存重开仍在」，按需修复发现的问题；
4. **R4** 交互驱动手册：可复用的真机 QA 方法（启动、BRP 断言、合成输入、OS 级输入注入、
   截图、时序），作为本专项及后续所有交互类任务的验收基础设施。

**不做**（首版明确排除）：

- 不改 NavFly/NavLook 的绑定架构与 QWER 工具键分配（fly 与工具键的冲突处理维持现状）；
- 不引入「一次 Esc 连退多层」语义（采用分层退出，每次 Esc 退一层，见 D8）；
- 不给 stroke/drag 类 modal 统一加 RMB 取消（RMB 已被各自手势占用；仅点选式工具加，见 D7）；
- 不新建 QA 基建 crate / 录制回放框架（手册用现成 BRP + `input.*` 合成 operator +
  PowerShell SendInput + PrintWindow 组合）；
- 不动游戏侧 `crates/jackdaw_remote`（本专项全部为编辑器侧改动）。

---

## 2. R1 视口：右键按下瞬间视角重置（bug 修复）

### D1. 链路复核：look 的唯一数据源与「warp 注入」假设的证伪

链路（全部代码级证据）：

1. fly 进入：`src/viewport.rs:941-943` `update_active_viewport`（RMB press + hovered_world →
   `CameraFlyActive.0 = true`）；`hold_cursor_while_flying`（`src/viewport.rs:781-801`）在
   `fly.is_changed()` 时把主窗口 `CursorOptions` 设为 `CursorGrabMode::Locked` + `visible=false`。
2. look 数据源：`NavLook` action ← `Binding::mouse_motion()`（`src/input_contexts.rs:227-234`）→
   求值于 `crates/jackdaw_input/src/evaluate.rs:176-185`，值直接取
   **`AccumulatedMouseMotion`**（`evaluate.rs:393`）→ `populate_camera_nav_input`
   （`src/input_contexts.rs:378-379`）折进 `CameraNavInput.look_delta` →
   `camera_system`（`crates/jackdaw_camera/src/lib.rs:100-109`）按 `sensitivity`（默认 0.003
   rad/px）应用为 yaw/pitch。
3. bevy@main 的 `MouseMotion` **只来自 winit `DeviceEvent::MouseMotion`**
   （bevy_winit/src/state.rs:459-462），Windows 上即 raw input（WM_INPUT）。
   `SetCursorPos` / `ClipCursor` 产生的 WM_MOUSEMOVE **不会**变成 `MouseMotion`。
4. winit-0.30.13 Windows 的 `CursorGrabMode::Locked` 实现：`set_cursor_flags(GRABBED|LOCKED)`
   → `refresh_os_cursor`（window_state.rs:487-503）→ **`ClipCursor` 到「当前光标位置」的
   1×1 rect**（`get_cursor_position()` 失败才退化为窗口中心），**全程无 `SetCursorPos`**
   （warp）。bevy_winit 的 `attempt_grab` 只是透传（winit_windows.rs:443-450）。
5. bevy 的 `CursorOptions` 无 warp 字段（bevy@main bevy_window/src/window.rs:754-789 只有
   visible / grab_mode / hit_test）；`set_cursor_position` 仅在显式调用
   `Window::set_cursor_position` API 时执行（bevy_winit/src/system.rs:416-426），
   **jackdaw 全仓无任何调用**（rg `set_cursor_position` 于 src/ 与 crates/ 均无命中）。
6. 次嫌疑排除：`jackdaw_camera_rig` 的运行时 driver（`JackdawCameraRigPlugin`，其
   `drive_camera_rig` 才会读 RMB+motion 重置朝向，lib.rs:184-278）**不在编辑器 app 注册**
   ——编辑器只注册类型插件 `JackdawCameraRigTypesPlugin`（src/lib.rs:704-706，仅反射注册
   供 Inspector/序列化）；viewport 相机（`build_3d_presentation`，src/viewport.rs:336-376）
   不携带 `CameraRig` 组件。编辑器内 fly 与 camera_rig 无交集。

**结论**：主控前期「头号嫌疑」（Windows 下进入 Locked 瞬间 winit/warp → 一帧 look_delta）
在**默认 Windows 桌面 + 当前锁定依赖版本**下不成立：Locked 无 warp，raw input 不受
ClipCursor/SetCursorPos 影响。真因需按下面两候选真机判别。

### D2. 真因两候选 + 判别法（T1 先判别后定稿修复帧数）

- **候选 1（最可能）：环境相关的 raw delta 注入。** 用户实际输入环境（RDP/远程会话、
  触控板或高采样率游戏鼠标的厂商驱动、多显示器 DPI 混合）在 ClipCursor 收紧到 1×1 的
  瞬间，由驱动把光标「拉回」合成为一次 raw delta → 单帧巨大 look_delta → 视角猛甩。
  *判别法*：T1 临时加一帧日志（`camera_system` 或 `populate_camera_nav_input` 中
  `look_delta.length() > 0.5 时 warn!` 帧号+数值，验收后移除），真机复现「按下瞬间跳变」；
  同时临时把 `hold_cursor_while_flying` 的 Locked 换成 Confined / None 各复现一次对照。
  若 Confined/None 下不复现而 Locked 复现 → 坐实「1×1 clip 触发的驱动合成 delta」。
- **候选 2（次可能）：press 帧的事件批合并。** winit 事件循环在 grab 应用与输入混合的
  帧里把积压 motion 一并投递，`AccumulatedMouseMotion` 单帧聚合出大 delta。
  *判别法*：同一份日志看大 delta 出现的帧号（press 帧 vs grab 应用帧，即 press 后第 1/2 帧）。
- 注意：`input.pointer` 合成输入**无法复现本 bug**（它只写 `WindowEvent::CursorMoved`，
  src/test_input.rs:169-207，不产生 raw `MouseMotion`），R1 真机验证必须用 OS 级 SendInput
  （见 R4 手册）。

### D3. 修复设计（对两候选机制均有效，先修后验）

- **主修复：fly 上升沿丢弃 look_delta。** 在 `populate_camera_nav_input`
  （src/input_contexts.rs:370）记录上帧 `fly_active`（Local 状态即可），`false→true` 的帧把
  `look_delta` 置 `Vec2::ZERO` 写入 nav（`move_axes`/`zoom_ticks` 不动——用户确认 WASD/QE
  正常，不动它们）。首版丢 1 帧；若 D2 日志显示大 delta 落在 grab 应用帧（press 后第 2 帧），
  扩为「fly 进入后丢 2 帧」（press 帧 + grab 应用帧，常量 `FLY_LOOK_SUPPRESS_FRAMES`）。
- **否决的替代**：清零 `AccumulatedMouseMotion` 资源（modal 上下文也绑了 mouse_motion，
  src/modal_inputs.rs:43 会受波及）；默认改 Confined（语义变化：光标不再钉在按下位置，
  拖到视口外行为改变——仅作 D2 判别对照，不作修复）。
- **回归保护**：现有 camera 单测不受影响；新增 headless 单测（populate 层纯逻辑）：
  上升沿帧 delta 被置零、持续帧正常传递、下降沿不丢。
- **验收（真机）**：SendInput 注入「RMB press（不带移动）→ hold 500ms → 小幅移动 →
  release」：press 瞬间视角不动（日志无大 delta + 截图前后一致）；小幅移动环视正常；
  重复 10 次无一次跳变。相机 Transform 断言走 BRP `bevy/query`（按 `Camera` 组件过滤，
  见 R4 手册 §5.3）。

---

## 3. R2 工具取消语义：全部工具审计与统一修复

### D4. 根因（代码级确证）：Escape 有两条链，modal 运行时全局链被高优先级上下文消费掐断

- 全局链：Core 扩展上下文有 `OperatorAction("modal.cancel")` 绑 Escape Press
  （src/core_extension.rs:170-177）；action Fire → `dispatch_operator_actions`
  （crates/jackdaw_api_internal/src/lib.rs:710-733）自动调用 `modal.cancel` operator
  （core_extension.rs:349-369）→ `cancel_active_modal` → 当前 modal 的 `cancel` system。
  **这是 CONTRIBUTING.md「Pressing Escape calls your cancel system for you」的实现。**
- 消费链：modal 运行时 `ModalInputContext`（priority 10，src/input_contexts.rs:180-187）
  被 `update_modal_context_activity`（src/input_contexts.rs:426-444）置 ACTIVE；其
  `ModalCancel` action 绑 Escape（DefaultKeymap，src/input_contexts.rs:313-322）且
  `consume_input = true`。求值器按 priority 降序、`consume_input` 把 trigger 加入
  `consumed` 集合、低优先级上下文同 trigger 绑定被屏蔽（crates/jackdaw_input/src/
  evaluate.rs:480-540，`:506` 的 `!consumed.contains`）。
- **因此：只要任何 modal 在跑，Core 上下文（默认 priority 0）的 Escape → `modal.cancel`
  operator 永远收不到输入。** Escape 只到达 `ModalCancel` action，而它没有任何全局派发者
  （rg 全仓：无系统观察 ModalCancel 的 Start/Fire 去调 cancel_active_modal）。
  Escape 能用的 modal，全是**自己轮询** `ModalInputs::cancel()`（读 ModalCancel 的
  ActionEvents::START，crates/jackdaw_api_internal/src/tools.rs:83-107）或直接读 raw
  `ButtonInput<KeyCode>` 的。没轮询的 modal（标尺等）→ Esc 死路；confirm 又永远
  `Running`（每次点击重新开始测量，src/measure_tool.rs:199-204）→ 用户「无法取消」。
  唯一出口：点其它工具栏按钮（`queue_operator_dispatch` 会先 cancel 活动 modal，
  core_extension.rs:49-55）/ undo / 切场景——普通用户根本想不到。

### D5. 工具/交互模式审计矩阵（9 类；退出路径现状）

| # | 工具/模式 | 激活 | Esc 退出现状 | RMB 退出现状 | 结论 |
|---|---|---|---|---|---|
| 1 | Select/Translate/Rotate/Scale（ActiveTool，QWER） | `tool.select/translate/rotate/scale`（src/tool_ops.rs:82-108） | 非粘性工具，按 Q 即回 Select；无需 Esc | — | ✅ 语义完好 |
| 2 | Vertex/Edge/Face 编辑模式 | `brush.edit_mode.*`（Digit1-3 等） | `brush.exit_edit_mode` 绑 Escape（src/edit_mode_ops.rs:48-50，`can_exit_brush_edit` 分层让位） | — | ✅ |
| 3 | Clip 模式 | Digit4 / KeyK 旁路 | `brush.clip.clear` 绑 Escape（src/clip_ops.rs:34）；有 pending 点时 #2 让位给它 | — | ✅ |
| 4 | Knife 模式 | KeyK | 自读 raw Escape（清路径）/ K 再按退出（src/brush/knife_mode.rs:459-471） | RMB 清路径（:463-465） | ✅ |
| 5 | **标尺（Measure）** | `tools.measure_distance`（modal） | **❌ 死路**：不轮询 ModalInputs（rg 证），confirm 永远 Running（src/measure_tool.rs:106-121,194-204） | ❌ 无 | **修复** |
| 6 | Draw Brush（Add/Cut） | `viewport.draw_brush_modal`（modal） | Add 模式 ❌ 同死路（注释自认走 modal.cancel 链，src/draw_brush/mod.rs:306-307，但无轮询）；Cut 模式有自己的 RMB 绑定 | Cut ✅（`viewport.draw_brush.cancel_cut` 绑 RMB，src/draw_brush/mod.rs:46-51）；Add ❌ | **修复** |
| 7 | Terrain Sculpt/Paint | `terrain.tool.*` + stroke modal | 工具态 ✅（`terrain.tool.exit_to_select` 绑 Escape，src/terrain/ops.rs:66-71，stroke 中 is_available 让位）；stroke 中注释称 Escape 恢复快照（src/terrain/paint.rs:6）但**待真机核实**（是否轮询 ModalCancel） | — | 待核实 |
| 8 | Gizmo 拖拽（两种） | `gizmo.drag` / `gizmo.drag_edit`（modal） | 描述声称「cancels on Escape」（src/gizmos.rs:437-446,713-723）但 body 不轮询 ModalInputs、不读 raw Escape → **疑似死路，待真机核实** | — | 待核实/修复 |
| 9 | 顶点/边/面拖拽 + modal transform（G 键） | brush drag ops / modal_transform | 拖拽 body 只用 ModalInputs 的 axis 约束（src/brush_drag_ops.rs:979-985）**不 poll cancel** → 疑似死路；modal_transform 读 raw keyboard（src/modal_transform.rs:138）用途待核实；numeric_transform ✅ 自读 raw Escape（src/numeric_transform.rs:238-241） | — | 待核实/修复 |

统计：**9 类交互模式中，确证缺 Esc 退出 2 项（标尺、Draw Brush Add），高度疑似 3 项
（gizmo 拖拽 ×2 计 1 类、brush 拖拽/modal transform 计 1 类、terrain stroke 待核 1 项），
完好 5 类**。T2 第一步是用 R4 手册逐项真机核实「疑似」行，再统一修复。

### D6. 机制修复（一处修全部）：把 ModalCancel 的 Fire 自动接到 `modal.cancel` operator

- **做法**：`spawn_modal_action::<ModalCancel>`（src/input_contexts.rs:192）所生成的 action
  实体上附加 `OperatorAction("modal.cancel")` 标签。`dispatch_operator_actions`
  （On<Fire> observer，lib.rs:710）会自动调用 `modal.cancel` → `cancel_active_modal`
  → 当前 modal 的 `cancel` system + finalize(false)。零新系统、零新调度。
- **两链互补不重复**：modal 运行时（Modal 上下文 ACTIVE）Escape 被 ModalCancel 消费 →
  新链生效、Core 链被屏蔽；无 modal 时（上下文 INACTIVE）ModalCancel 不 fire →
  Core 链照旧处理「无 modal 但 Picker/菜单打开」的 dismiss（core_extension.rs:364-366）。
- **幂等安全**：已自行轮询 cancel 的 modal（brush topology 7 项）与新链同帧双触发时，
  `cancel_operator` 先查 `active.get(world).is_operator(id)` 才 finalize
  （operator.rs:894-910），operator body 自行 Cancelled 的路径 finalize 已发生，
  cancel_active_modal 找不到活动 modal 直接 Ok(())——幂等。`modal.cancel` 本身
  `allows_undo = false`，`creates_history_entry` 无副作用。
- **语义变化（需裁决 2）**：从此「任何 modal 一按 Esc 立即取消」成为硬保证，
  CONTRIBUTING.md 的承诺真正成立。
- **文档同步**：CONTRIBUTING.md modal 节补一句「modal 也可以自己轮询 ModalInputs::cancel()
  做更细的分级取消（如 knife 只清路径不退模式）」。

### D7. 标尺/Draw Brush 的 RMB 退出 + 与 RMB 飞行的冲突

- 仅给**点选式工具**（标尺；Draw Brush Add 模式可选）补 RMB 退出：body 内
  `modal_inputs.cancel() || mouse.just_pressed(MouseButton::Right)` 返回 Cancelled——
  与 brush topology 范式完全一致（src/brush/topology_ops/extrude.rs:260 等）。
- RMB 双语义冲突：NavFly 绑在 Nav 上下文（priority 0，常 ACTIVE），modal 上下文没有 RMB
  绑定不消费它——标尺运行中按 RMB 会**同时**取消工具并按下 fly（若按住不放则进入飞行）。
  brush topology 现状即如此（cancel 与 fly 并存），**推荐接受该双语义**（Blender 亦然），
  不改 `update_active_viewport` 的 fly 启动条件（避免与 R1 修复交叉）；裁决项 1。
- Draw Brush Add 模式不加 RMB（RMB 是 Cut 的既有取消 + fly；Add 的 Esc 修通即可）。

### D8. 「Esc 回 Select」的统一分层语义（定稿，不做一键到底）

每按一次 Esc 退一层：① 有进行中手势/modal → 取消之（D6 机制保证）；
② 处于粘性模式（brush 编辑模式 / terrain 工具态）→ 退到 Object/无工具
（既有 `brush.exit_edit_mode` / `terrain.tool.exit_to_select`，二者已做 stroke 让位）；
③ 已是最外层（Select/无工具）→ 无操作。理由：一键连退会让「取消一次误拖」变成
「意外退出模式」，分层语义各层已有实现、零新状态机。工具栏/状态栏的 ToolStatus
（tools.rs:27-33）在标尺启动时提示「Esc / RMB 取消」。

---

## 4. R3 Outliner Add 菜单建实体 E2E（用户插入任务 #1）

### D9. 现状结论：代码链路完整，无已知断点——本任务是「真机验证 + 按需修复」

证据链（全通）：

1. 词汇表：`CreationTaxonomy`（src/creation_taxonomy.rs:144-229）内置 Empty/Prefab/Image +
   Cube/Sphere/Plane/Cylinder/Wedge/Cone/Pyramid + Point/Directional/Spot Light + Camera
   （+Camera Rig，feature camera_rig 默认开）+ Audio/Animation + Fog/Reflection Probe +
   Terrain（+multiplayer 三项，feature 门控）。
2. 入口 ×2 共享同一词汇表：工具栏 Add 菜单（`add_menu_rows`）与场景树 Add Entity 按钮
   （`AddEntityButton`，src/layout.rs:623-628 → `entity.add_picker` → 可搜索 picker，
   src/add_entity_picker.rs:78-95）。菜单行 action 形如 `op:entity.add.cube`。
3. 落地：`entity.add.*` operator（src/entity_ops.rs:2632-2705 等）→
   `create_entity_in_world`（:873-882）→ `SpawnEntity` EditorCommand（可 undo）→
   `spawn_template_in_document`（选中 + 注册 AST）。Cube 在原点 0.5 尺寸
   （`Brush::cuboid(0.5,0.5,0.5)`），初始相机 `(0,4,8) looking_at 原点`
   （src/viewport.rs:358）→ **新建 Cube 必在视野内**；点光在 (0,3,0)。
4. Stage 2 盘点为 ✅（含测试）；用户「实测可能不通或不可发现」的真因（入口藏得深？
   picker 交互问题？某个模板坏？）**只能真机定位**，方案按「验证优先、修复随发现」设计。

### D10. E2E 验收定义（真机，用 R4 手册执行）

1. Add 菜单含 Cube / 点光 / 平行光（`jackdaw/operators` 断言 `entity.add.cube|point_light|
   directional_light` 存在；真机打开 Add 菜单截图可见分组）。
2. 创建后 viewport 立即可见：合成输入点 Add 菜单（或 BRP 直调 `entity.add.cube`）→
   `jackdaw/entity {"name":"Cube"}` 返回实体与 bsn → `jackdaw/screenshot kind=viewport`
   比对画面出现立方体。
3. Inspector 编辑生效：真机点选该实体（SendInput 点击 viewport 中立方体或 outliner 行）→
   Inspector 显示 Transform/Brush → 合成输入在 Transform.x 输入 `2` 回车 →
   `bevy/get+components` 断言 Transform.x=2 且 screenshot 中立方体移动；点光颜色同理
   （改 color → 截图亮度变化）。
4. 保存重开仍在：`scene.save`（BRP 直调或 Ctrl+S 合成）→ 杀进程 → 同工程重启 →
   `jackdaw/entity {"name":"Cube"}` 仍在且 Transform 保持。
5. **UI 入口可用性**（「不可发现」的真机检查）：Add 菜单/ Add Entity picker 的打开、
   搜索 "cube"、点选三项全走真实鼠标；任何一步卡死/不可达即记缺陷并修复。

---

## 5. R4 交互驱动手册（本专项基础设施；QA 照抄执行）

### 5.1 启动与就绪

- **带工程直开**：CLI **不接受**位置参数路径（src/cli.rs:30-38，非 `-` 参数被忽略）。
  用环境变量：`set JACKDAW_OPEN_PROJECT=C:\Users\linbo.zhang\Projects\my-game` 后启动
  `jackdaw.exe`（fixture 工程亦可）。
- 多实例并行时给独立端口：`set JACKDAW_REMOTE_PORT=15713`。
- 启动即跑 operator 序列（无人值守冒烟）：`set JACKDAW_RUN_OP=entity.add.cube; input.key
  key=Escape`（`JACKDAW_RUN_OP_GAP` 控制子句间隔；boot_ops 会等合成手势播完，
  src/boot_ops.rs、src/test_input.rs:1-18）。
- **就绪判定（稳定时序）**：轮询两件事之一即认为编辑器可服务：
  ① 工程目录出现/更新 `.jackdaw/editor.json`（server 启动后由 `publish_endpoint` 写出，
  src/remote/server.rs:184+）；② `POST http://127.0.0.1:15703/` 的 `jackdaw/status` 应答。
  端口默认 **15703**（`DEFAULT_PORT`，`JACKDAW_REMOTE_PORT` 可覆盖；绑定 loopback，
  端口被占则放弃监听并 warn——多开必须显式分端口；`remote.enabled` 默认 true，可被
  工程 `.jackdaw/settings.json` 关闭，QA 工程勿关）。

### 5.2 BRP 调用方式（JSON-RPC 2.0 over HTTP，curl / PowerShell 皆可）

```powershell
# PowerShell 通用调用
function Brp($method, $params) {
  Invoke-RestMethod -Uri http://127.0.0.1:15703/ -Method Post -ContentType 'application/json' -Body (
    @{ jsonrpc='2.0'; id=1; method=$method; params=$params } | ConvertTo-Json -Depth 8)
}
# 示例：调 operator 建实体（history=false 避免污染 undo 栈——按需）
Brp 'jackdaw/call_operator' @{ id='entity.add.cube'; history=$false }
# 按名字查实体（返回 entity bits + bsn 全量组件）
Brp 'jackdaw/entity' @{ name='Cube' }
```

编辑器方法面（src/remote/server.rs:146-158 + bevy@main RemotePlugin::default 自带全套
`bevy/*` 标准方法，bevy_remote/src/lib.rs:782-922）：`jackdaw/status | operators |
call_operator{ id, params, history } | batch{ calls } | cancel | scene_tree | entity
{ entity|name } | apply_bsn | scene_bsn`，watching 型（首次挂起、同 key 重调取结果）：
`jackdaw/screenshot { kind=viewport|…, path }`、`jackdaw/assets`、
`jackdaw/wait { until:'idle'|'pie_running'…, frames:N }`；标准方法 `bevy/query | get+components
| inspect | get_resource | list+methods(rpc.discover) | app_info` 等。
`jackdaw/cancel` 可远程取消活动 modal（server.rs:629+），QA 复位用。
注意：`ActiveTool`/`EditMode` 未注册 Reflect，BRP 读不到——T2 顺手补 `derive(Reflect)+
register_type`（小改动），供 QA 断言「Esc 后回 Select」；相机 Transform 用
`bevy/query` 按 `bevy_camera::components::camera::Camera` 过滤（scene 相机 is_active=false，
viewport 相机 true，可区分）。

### 5.3 合成输入（进程内，BRP 可驱动）：`input.pointer` / `input.key` / `input.text`

- 能力：把 winit 会投递的 `WindowEvent` 排队播放（逐 beat、可隔帧），下游 picking/UI
  全部当真（src/test_input.rs:139-207）。pointer 动作 `move/press/release/click/dblclick/
  scroll/drag_to/rest`，`button=primary|secondary|middle`（RMB 可发），坐标为窗口逻辑像素；
  key 用键名（`Escape`/`KeyC`…）+ `mods=ctrl,shift`。
- **能力边界（关键）**：只产生 `CursorMoved`/按键事件，**不产生 raw `MouseMotion`** →
  无法驱动 NavLook（相机环视）与任何读 `AccumulatedMouseMotion` 的路径。R1 验证、
  RMB-fly 行为验证必须用 5.4 的 OS 级注入。
- 适性：菜单/按钮点击（R3 Add 菜单）、Inspector 数字框输入（`input.text`）、
  Esc/RMB 的「事件到达」路径（R2 部分——注意 R2 的 Esc 走 action 消费链，
  `input.key key=Escape` 产生的 KeyboardInput 同样进 ButtonInput，可用）。

### 5.4 OS 级输入注入（PowerShell SendInput 脚本骨架，可照抄）

```powershell
Add-Type @"
using System; using System.Runtime.InteropServices;
public class KB {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT { public uint type; public MK u; }
  [StructLayout(LayoutKind.Explicit)]
  public struct MK { [FieldOffset(0)] public MOUSE mo; [FieldOffset(0)] public KEY k; }
  [StructLayout(LayoutKind.Sequential)]
  public struct MOUSE { public int dx, dy; public uint data, flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)]
  public struct KEY { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [DllImport("user32.dll", SetLastError=true)]
  public static extern uint SendInput(uint n, INPUT[] i, int size);
  public static void RmbDown(){ var i=NewMouse(0x0008); SendInput(1,new INPUT[]{i},Marshal.SizeOf(typeof(INPUT))); }
  public static void RmbUp(){ var i=NewMouse(0x0010); SendInput(1,new INPUT[]{i},Marshal.SizeOf(typeof(INPUT))); }
  public static void MoveRel(int dx,int dy){ var i=NewMouse(0x0001); i.u.mo.dx=dx; i.u.mo.dy=dy; SendInput(1,new INPUT[]{i},Marshal.SizeOf(typeof(INPUT))); }
  static INPUT NewMouse(uint f){ var m=new MOUSE(); m.flags=f; var i=new INPUT(); i.type=0; i.u.mo=m; return i; }
}
"@
$hwnd = (Get-Process jackdaw | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1).MainWindowHandle
[KB]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 300
# RMB 按下（先 SetCursorPos 到视口中心再按；窗口无标题栏文本，按进程找句柄）
[KB]::RmbDown(); Start-Sleep -Milliseconds 500   # 观察按下瞬间是否跳变
1..20 | ForEach-Object { [KB]::MoveRel(15, 0); Start-Sleep -Milliseconds 16 }  # 环视
[KB]::RmbUp()
```

（正式版脚本落 `loop/qa/` 目录：键盘 vk 码、绝对坐标换算、逐 key 事件齐全；
键盘 Esc 用 `SendInput` key 型 `vk=0x1B`。）

### 5.5 视觉：双通道截图

- **首选 `jackdaw/screenshot`**（BRP watching，`kind=viewport` 取视口内容，写工程相对
  path）——所见即所渲染，无窗口遮挡/最小化问题。
- **PrintWindow 全窗口截图**（比对整体 UI/工具栏高亮态时用）：user32 `PrintWindow
  (hwnd, hdc, 2)` 到 Bitmap 存 PNG（`PW_RENDERFULLCONTENT`）。骨架同 5.4 的 Add-Type 模式，
  落 `loop/qa/screenshot.ps1`。
- 比对：QA 子代理肉眼看图（loop 契约既定做法）+ 像素 diff 辅助（R1 前后两张视口图
  应几乎一致——除噪点/抗锯齿外）。

### 5.6 时序规约（防 flaky）

1. 启动 → 等 `.jackdaw/editor.json` 或 `jackdaw/status`（上限 60s）。
2. 每个 UI 操作（合成输入/SendInput）后 `jackdaw/wait {"until":"idle"}`（报告含活动
   modal，正好当 R2 断言用）或 `{"frames": 5}` 固定帧。
3. BRP watching 方法（screenshot/wait）轮询同 key 直到返回结果，超时 10s。
4. 断言前置 `jackdaw/cancel` 复位活动 modal，保证用例间无残留状态。
5. 每个用例结束 `jackdaw/screenshot` 留档到 `loop/reports/`。

---

## 6. 任务拆分（3 个任务，串行）

### T1：R4 手册落地 + R1 视口跳变修复（验证同手册）

- 程序：
  1. `loop/qa/` 落正式脚本（brp.ps1 / input.ps1 / screenshot.ps1）+ 手册誊抄（本方案 §5）；
  2. R1 判别日志（临时）+ 真机复现记录（候选 1/2 判别，D2）；
  3. R1 主修复（D3：fly 上升沿丢 look_delta，帧数按判别结果定 1 或 2）+ headless 单测；
  4. 给 `ActiveTool`/`EditMode` 补 Reflect 注册（D 5.2 备注，服务 T2/T3 QA 断言）。
- QA：真机 SendInput 复现-验证（D3 验收标准：10 次零跳变 + 环视正常 + WASD/QE 回归）；
  quick tier 四门。
- 产出：判别结论写进 QA 报告（真因落档）。

### T2：R2 工具取消审计修复

- 程序：
  1. 按 D5 矩阵真机核实 4 个「待核实」行（Esc 是否实际生效：标尺/DrawBrushAdd 作为
     阳性对照应失败，gizmo/brush-drag/terrain-stroke 逐个测）；
  2. D6 机制修复（ModalCancel 挂 OperatorAction("modal.cancel")）+ 单测
     （modal 运行时 Escape → cancel system 被调；无 modal 时 Picker dismiss 不回归）；
  3. 标尺 body 补 `modal_inputs.cancel() || RMB`（D7）；ToolStatus 提示文案；
  4. CONTRIBUTING.md modal 节补充分级取消说明（D6）；
  5. 审计矩阵更新为最终版（修复/完好全标）。
- QA：真机逐工具验证矩阵每一行（Esc 逐层退出语义 D8；RMB 标尺退出 + 与 fly 双语义；
  brush topology / clip / knife / numeric 回归）。

### T3：R3 Add 菜单 E2E + 全量门收尾

- 程序：按 D10 真机跑通 5 项验收；发现缺陷按需修复（预期小修或零修——链路已完整）；
  「不可发现」若成立，做入口可见性微调（如 Add 按钮图标/tooltip，仅限真机证据支持的最小改）。
- QA：D10 全项 + quick tier + 全量门（`cargo xtask fast`，契约允许 QA 认为必要时）；
  最终 QA 报告 + 台账 `loop/progress.md` 记一行。

---

## 7. QA 验收清单（含真机交互步骤与预期）

**Quick tier 门（每任务）**：`cargo fmt --all -- --check`；`cargo clippy --workspace --
-D warnings`；`cargo test --workspace --lib`；被改 crate 相关集成测试。

**T1 真机项**：
1. [ ] 启动（JACKDAW_OPEN_PROJECT）→ editor.json/status 就绪 ≤60s；
2. [ ] SendInput「RMB press 不动 500ms → release」×10：每次 `bevy/query` 相机 rotation
   前后一致（阈值：yaw/pitch 变化 < 0.005 rad）且视口截图 diff ≈ 0；
3. [ ] RMB 按住 + 20×(15px,0) 相对移动：yaw 单调变化、pitch 不跳（日志无 >0.5 delta 尖峰）；
4. [ ] RMB 按住 + WASD/QE：位移正常（回归用户确认的可用路径）；
5. [ ] （判别）Confined/None 对照日志归档，真因结论写入 QA 报告。

**T2 真机项（逐矩阵行）**：
1. [ ] 标尺：激活 → Esc 退出 ✅；RMB 退出 ✅；退出后 `jackdaw/wait` 报 idle 且无活动
   modal；再 Esc 无副作用（分层第 ③ 层）；
2. [ ] Draw Brush Add 模式：Esc 退出且草绘取消；Cut 模式 RMB 依旧；
3. [ ] gizmo 拖拽 / brush 顶点拖拽 / terrain stroke（以 T2 程序员 1 的核实结果为准的
   行项）：Esc 均能取消并恢复拖拽前状态；
4. [ ] Vertex 编辑模式内 Esc 逐层：清手势 → 退模式 → 无操作（三层各一次 Esc 验证）；
5. [ ] 无 modal 时 Esc：打开的 Add Entity picker / 命令面板关闭（Core 链回归）；
6. [ ] 工具栏按钮在标尺运行中点击其它工具：先取消标尺再切换（既有行为回归）。

**T3 真机项**：D10 的 1–5 全项（Add 菜单可见 / viewport 可见 / Inspector 编辑实时生效 /
保存重开持久 / 入口可用性），每步 BRP 断言 + 截图留档。

---

## 8. 风险

1. **R1 真因落在 OS/驱动层且单帧丢弃不够**（如 RDP 注入 delta 持续多帧）：判别日志会
   直接暴露；后备=丢 N 帧常量化（N 由日志定）或裁决项 3 的 Confined 方案。
2. **D6 机制修复改变所有 modal 的 Esc 语义**：个别工具若未来需要「Esc 不取消」需显式
   退出该机制（文档写明）；现状无此类工具（盘点 9 类均以取消为期望行为）。
3. **ModalCancel 挂 OperatorAction 后的 `require_reset` 交互**：modal 启动帧按住的键需
   先释放（evaluate.rs:437-439 既有语义），对「启动 modal 的同一手势按住期间按 Esc」
   的极端序列可能吞第一次 Esc——T2 单测覆盖该序列。
4. **BRP 断言依赖 Reflect 注册**（ActiveTool/EditMode 补注册属行为无关的序列化面变化，
   但会进 TypeTree/保存格式——需确认无 `.jsn` 兼容问题；若有疑虑降级为截图断言）。
5. **SendInput 脚本对窗口焦点/DPI 敏感**（多显示器缩放使逻辑/物理坐标错位）：脚本统一
   用物理像素 + 进程句柄定位，首跑校准；QA 环境固定单显示器最佳。
6. **多编辑器实例端口冲突**：手册已约定 `JACKDAW_REMOTE_PORT`；QA 流程固定先杀旧进程。

---

## 9. 需用户裁决项

1. **标尺 RMB 双语义**（D7）：RMB 退出标尺的同时若按住会进入 fly（与 brush 范式一致）。
   推荐：接受。备选：modal 运行中禁用 fly 启动（改 `update_active_viewport`，与 R1 修
   改交叉，不建议本专项做）。
2. **D6 的全局语义**：「任何 modal 一按 Esc 立即取消」成为硬保证（含 gizmo 拖拽等原本
   声称支持但实际失效的场景一并修通）。推荐：接受（这正是用户诉求）。
3. **R1 修复形态**（仅当判别结果为「驱动持续注入」时触发）：接受「丢 N 帧」为最终方案，
   还是默认改 `Confined`（光标不锁定、可移出视口，长按飞行体验变化）。推荐：丢 N 帧。
4. **QA 脚本沉淀位置**：`loop/qa/`（不入库，本方案默认）vs 入库 `tools/qa/`（进上游
   PR 面）。推荐：留 loop/qa/，成熟后再议入库。
