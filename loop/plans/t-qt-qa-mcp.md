# T-QT 插队任务方案：QA 驱动工具层（MCP/BRP）

> 插队最高优先（用户 2026-10-24 动机原话：「为了方便测试，先给引擎设计一下 MCP……停留在让鼠标
> 点击到对应的框那里很久了，先设计 QA 工具然后再让 QA 干活」）。完成后用新工具重跑 T02-T1 QA
> （dogfood），再回 roadmap。
> 契约：`loop/README.md`（交互验收契约不变——工具只是手段，真机验收仍是门）。
> 现状核实基线：main `bc5274ee`，bevy git pin `c9c397ba`。

## 0. 范围与不做

**做**：
- BRP 方法层（编辑器内实现）：`jackdaw/ui_tree`、`jackdaw/ui_click`、`jackdaw/ui_drag`、
  `jackdaw/ui_input`、`jackdaw/camera_state`，`jackdaw/wait` idle 语义扩展；
- 合成输入补 raw `MouseMotion` 注入（新 operator `input.motion`，修「环视/平移测不了」根因）；
- MCP 薄翻译：上述 5 个 BRP 方法的 5 个新工具（`jackdaw_mcp`）；
- 测试：单测 + in-process 集成 + `mcp_smoke` 工具清单扩展 + headless 全链路点击；
- dogfood：T02-T1 QA 真机项用新工具重跑 + R1/R3 回归 + F8 滑条尾巴收口；
- 文档：book remote-control.md 工具表扩行、`loop/qa/manual.md` 增补。

**不做**（裁定，理由见 D1/D2）：
- 不做通用 `poll_until` 条件轮询方法（条件 DSL 膨胀；wait idle 扩展 + 客户端轮询已覆盖）；
- 不做截图区域裁剪参数（BRP `kind=window` 走 GPU readback 无陈旧帧，pixdiff 外置裁剪已够）；
- 不做 `tool_state`/`scene_text`/`fly_state` 专用方法（scene_bsn 已有；fly/pan 并入 camera_state；
  ActiveTool 走 `world.get_resources`，T1 顺手补 `register_type` 一行即可，见风险 6）；
- 不做 MCP `ui_find` 独立工具（ui_tree 自带过滤参数，薄翻译直接暴露）；
- 不给测试方法加 cargo feature 门控 / debug-only（见 D2 安全边界裁定）；
- 编辑器不内嵌 MCP server（沿用独立 bin 架构）；
- 不替换 OS 级 SendInput 通道（`input.ps1` 保留，测真输入栈仍有价值）；
- 不改任何被测交互行为本身——本任务只加观测与驱动手段。

## 1. 现状盘点（已核实，带证据）

### 1.1 jackdaw_mcp 现状

- 位置 `crates/jackdaw_mcp`（lib.rs + main.rs 两个文件，**无 crate 内测试**）；设计哲学写在 lib.rs
  头注释：「每个工具是一条 BRP 方法的薄翻译，无自有编辑器状态，所有写操作落 undo 栈」。
- **现有 15 个工具**（`#[tool]` 逐个核对）：`status`、`list_operators`、`call_operator`、`batch`、
  `scene_tree`、`get_entity`、`apply_bsn`、`scene_bsn`、`open_scene`、`save_scene`、`select`、
  `screenshot`（含 `look_at` 预对相机 + PNG base64 回传）、`cancel`、`wait`（frames/until，带
  request id 防并发共享倒计时）、`assets`；另有 2 个只读 resource：`jackdaw://operators`、
  `jackdaw://scene`。
- **启动链**：`jd mcp [--project <path>]`（`crates/jd/src/main.rs` `mcp_command`，先找同目录
  `jd-mcp` 二进制）→ `jackdaw_mcp::serve_stdio_blocking`（rmcp 3.2 stdio，stdout 即协议通道）→
  每个工具一次 BRP JSON-RPC POST（reqwest，120s 超时兜 watching 方法）→ 编辑器 endpoint 从
  `<project>/.jackdaw/editor.json` 发现（`jackdaw_env::editor_endpoint::read_endpoint`），
  端口默认 15703（`JACKDAW_REMOTE_PORT` 覆盖）。**编辑器与 MCP 是两个进程，MCP 栈不进编辑器
  依赖图**（main.rs 头注释言明）。
- **测试**：`tests/mcp_smoke.rs`（workspace 根，非 crate 内——任务简报说在 jackdaw_mcp 下，
  实际在根 tests/）：真编辑器 + `jd mcp` 子进程，initialize 握手 + tools/list 断言 15 工具名 +
  status 真调；无显示环境自动 skip（`JACKDAW_MCP_E2E_REQUIRED` 强制）。in-process 钉子在
  `tests/guards/editor_remote.rs`（BRP handler 直接 `run_system_cached_with` 跑，含 watching
  轮询语义模拟）。
- **文档**：`book/src/developer-guide/remote-control.md` 完整（工具表 + JSON 配置示例 + 用法）。

### 1.2 编辑器侧 BRP 方法面（src/remote/server.rs）

`JackdawEditorRemotePlugin` 注册 15 方法：`status`（含 modal/dialog/picker/pie 状态）、
`operators`、`call_operator`、`batch`、`cancel`、`scene_tree`、`entity`、`apply_bsn`、`scene_bsn`、
watching 型 `assets`/`screenshot`（kind=viewport|viewport2d|window）/`wait`（frames/until=
idle|pie_running|pie_stopped）。安全面：只绑 loopback、无 CORS（注释言明防 loopback 页面写权限）、
`remote.enabled` 项目级开关、端口探测失败放弃监听。bevy 标准 `world.*` 方法同端口可用。

### 1.3 合成输入现状与关键缺口

`src/test_input.rs`（extension `jackdaw.test_input`）提供 **operator**（经
`jackdaw/call_operator` 即可远程调）：`input.pointer`（move/press/release/click/dblclick/
drag_to/scroll/rest，space=window|canvas）、`input.key`（press/release/tap + mods）、
`input.text`。实现：排队 `Beat`（每帧一拍，帧间隔可调），每拍发 **winit 等价 `WindowEvent`**
（CursorMoved 物理坐标 / MouseButtonInput / MouseWheel / KeyboardInput），
`drive_synthetic_input` 在 `First`（PickingSystems::Input 之前）播放——下游 picking/UI 全当真，
`tests/controls/synthetic_click.rs` headless 钉死了全链路。

**关键缺口（环视/平移测不了的根因）**：`Emit` 只有四种，**从不写 `MouseMotion` 消息**。
`bevy_window` 只把 CursorMoved 拆进 cursor 流；raw delta 是 winit `DeviceEvent` 路径，
bevy_winit 才写 `Messages<MouseMotion>`。而编辑器 NavLook 链路
（`input_contexts.rs` `Binding::mouse_motion()` → `jackdaw_input/evaluate.rs` 读
`AccumulatedMouseMotion` → `populate_camera_nav_input` → `CameraNavInput.look_delta/pan_delta`）
全吃 AccumulatedMouseMotion，合成拖拽对它恒为 0。已核实 pinned bevy（c9c397b）
`bevy_input`：`accumulate_mouse_motion_system` 在 **PreUpdate** 从 `Messages<MouseMotion>`
累加——**直接 `world.write_message(MouseMotion{delta})` 即可喂到，无需绕 winit，且
First 注入 → 同帧 PreUpdate 累加 → Update 消费，顺序正确**。`loop/qa/manual.md` §3 早已
注明此边界（「R1 与 RMB-fly 验证必须走 §4 的 OS 级注入」），本任务把它变成不必。

**两个已有闸门（motion 手势参数必须绕开，否则 dogfood 误判无效）**：
- `FLY_LOOK_SUPPRESS_FRAMES = 3`（input_contexts.rs:406）：RMB 按下后前 3 帧 look 被丢弃——
  环视手势须「按下后空转 ≥3 帧（rest）再逐帧小 delta」；
- `MAX_PLAUSIBLE_POINTER_DELTA = 1000`（input_contexts.rs:418）：单帧 delta >1000px 整拍丢弃
  （RDP 重锚跳变防护）——motion 手势每拍 delta 必须小于此值。

### 1.4 QA 痛点史对照（新工具逐条对位）

| 痛点（出处） | 现状做法 | 根因 | 本方案 |
|---|---|---|---|
| UI 点击坐标换算脆弱：DPI `/1.5`、`cx>group.cx+150` 布局启发、checkbox 命中=「caption 左缘−12px 标定」（r3-menu-cube.ps1、f8-t2-ui.ps1 probe10-18、feature-08-t2-qa.md §3） | `world.query` 拉 Text+ComputedNode+UiGlobalTransform → 脚本端物理/逻辑换算 → `input.pointer` 注入 | 换算和命中共识在脚本端，编辑器内 `UiScale`/scale_factor 没参与 | `ui_click`：编辑器内按 synthetic_click.rs 验证过的公式 `UiGlobalTransform.translation * inverse_scale_factor * UiScale` 取中心，脚本端零坐标数学 |
| 数值框值非 Text 组件、dump 不可见；滑条合成点击值为 0（feature-08-t2-qa.md 发现 1） | release 等价一调绕过；真人补验 | bevy slider normalize 坐标空间失配 + 打字提交时序赌帧 | `ui_input`（聚焦+打字+提交一次调用）、`ui_drag`（控件相对分数→编辑器内换算真拖拽）；ui_tree slider 节点带 value/min/max |
| SendInput 需 AttachThreadInput 前置、时好时坏、被判 error 5 拒绝（r1b 系列、f8 发现 1） | 判别实验专属 | OS 级注入本质要求前台焦点 | 环视/平移改走 `input.motion`（进程内 raw delta），SendInput 仅保留给「测真输入栈」场景 |
| PrintWindow 后台陈旧帧 | screenshot.ps1 双通道 | PrintWindow 语义 | BRP `kind=window` 本就 GPU readback（src/screenshot.rs `Screenshot::primary_window()`），文档明确「UI 态优先 BRP window」，PrintWindow 降级为交叉验证 |
| 时序靠 sleep 赌（-Milliseconds 300/700 遍布 r3/f8 脚本） | 手工 sleep+固定帧 | `call_operator(input.*)` 返回时手势还没播完；`jackdaw/wait until=idle` 的 `editor_is_busy` **不含** SyntheticInput 队列空 | wait idle 扩展：SyntheticInput 非空即 busy（boot_ops.rs:630 对 JACKDAW_RUN_OP 链已是此语义，对齐） |
| dialog/picker 卡死会话 | `jackdaw/cancel`、`dialog.answer`、status 报 picker | 已解决 | 不动，仅在文档速查表收录 |

## 2. 设计问题裁定（D1–D7）

### D1 工具面（核心）

**裁定：BRP 层加 5 方法 + 1 operator + 1 语义扩展；MCP 层加 5 个薄工具。** 取舍：

- `ui_tree`（含过滤）：面板/控件树查询，节点带 {entity, kind, text, operator, disabled,
  checked, visible, rect(物理 px), value/min/max(slider)}。kind 按已知组件判定
  （FeathersButton/FeathersCheckbox/FeathersSlider/FeathersTextInput(Scrub 输入)/
  Picker/EditorDialog/menu 行 ButtonContentText/普通 Node/Text）。**取代** uitext.ps1 与
  r3/f8 的 Get-UiRows 模式。默认 depth 限制防全树爆炸（编辑器 UI 上千节点）。
- `ui_click`：定位（entity id / operator id / text 子串 + index 消歧）→ 编辑器内换算中心 →
  排 `SyntheticInput` move+press+release beats → **走真实 picking/observer 链**
  （synthetic_click.rs 已证 headless 可行）。目标 disabled / size==0 / 不可见 → 拒点带原因
  （比静默点空强）。多候选歧义 → INVALID_PARAMS 列出候选（学 `entity_from_params` 唯一语义）。
- `ui_drag`：entity + from/to（控件 rect 相对分数 [0..1]²）→ press → 插值 CursorMoved 拍 →
  release，绝对位置走 picking PointerDrag（number scrub / 滑条 / 分割条通用）。
- `ui_input`：定位 + text + commit=enter|blur|none → 单次调用内组合「click 聚焦 → 逐字符
  key beats → Enter/点外」进同一 SyntheticInput 队列（消「先 focus 再打字」时序坑）。
- `camera_state`：活动视口相机 translation/yaw(YXZ)/pitch/Projection 摘要 + fly/pan active +
  ortho scale。取代 brp.ps1 `Get-FlyCamera`/`Get-YawPitch`（脚本端四元数欧拉提取挪进编辑器）。
- operator `input.motion`：dx,dy（累计 delta，自动拆拍）+ steps/frames → 每拍
  `write_message(MouseMotion{delta})`。**修环视/平移根因**。文档写明两个闸门约束
  （3 帧抑制窗、1000px/帧上限）及推荐手势形状（rest 3 帧 → 小步多拍 → release）。
- `jackdaw/wait` 扩展：`until=idle` 增加「SyntheticInput 队列非空即 busy」。

**砍掉及理由**：
- `poll_until`：条件轮询通用化=条件 DSL+watching 超时语义重设计，收益低（客户端轮询
  ui_tree/camera_state 本就是 JSON 一次往返）；时序赌的真根因（手势未播完）由 wait 扩展消灭。
- `ui_find` 独立 BRP 方法/MCP 工具：过滤参数并入 ui_tree，避免两套遍历逻辑；MCP ui_find
  只是 ui_tree+filter 的别名，不值得一个工具位。
- 截图区域裁剪：外置 pixdiff 裁剪已够；BRP window 无陈旧帧。
- `fly_state`/`tool_state`/`scene_text`：并入 camera_state / 已有 scene_bsn / get_resources。
- `key_press`/`pointer_press` MCP 薄工具：`call_operator(input.key/input.pointer)` 已可直达
  且 book 有文档，不重复包（保持「每工具一条方法」哲学，避免 MCP 面膨胀）。

### D2 架构边界

- **进 BRP（编辑器内实现）**：ui_tree/ui_click/ui_drag/ui_input/camera_state（新文件
  `src/remote/ui_probe.rs`，server.rs 注册）+ input.motion（test_input.rs）+ wait 扩展
  （server.rs `editor_is_busy`）。理由：需要 World 访问、UiScale/scale_factor、SyntheticInput
  队列——全在编辑器进程内。
- **进 MCP（薄翻译）**：上述 5 方法的 5 工具，零自有状态、零组合逻辑（与 select 的 batch
  组合先例不同，组合已在编辑器内的 ui_input 做掉）。
- **复用真实事件管线的原则**：UI 交互工具**只做两件事——查找（读组件）与定位（rect 数学）**，
  触发一律排队进既有 `SyntheticInput` beat 队列（First→picking→observer），**绝不**直接调
  operator、写组件或触发 `ButtonClickEvent`/`Activate`。`ButtonOperatorCall` 只用于查找，
  不用于触发——保证测到的是「用户路径」（命中测试、hover、disabled 拦截、focus 链）。
  同一队列还保证与 `input.*` 手工调用串行（boot_ops 的 idle gating 不变）。
- **安全边界（裁定：不加 feature 门控）**：现有面已 loopback-only + 无 CORS +
  `remote.enabled` 项目开关 + 端口占用即弃听；`input.*` operator 本就在 operator 目录暴露
  （发布版同样可达），新工具不扩大权限面，只把「脚本端坐标数学」搬进进程内。加 debug-only
  feature 会割裂 mcp_smoke/发布测试矩阵、且与「MCP 是官方功能」（book 章节）定位矛盾。
  风险段 5 留复议口。

### D3 与现有 input.pointer 的关系

**并存 + 修正，不替换**。`input.pointer/key/text` 三个 operator 原样保留（菜单点击、Esc 到达
路径、打字路径均已被 R2/R3/F8 验证有效）；新增 `input.motion` 补 raw delta 维度；
`drag_to`（CursorMoved 绝对路径）不动。`loop/qa/manual.md` §3 的「能力边界」注记改为：
「环视/平移用 `input.motion`；`input.ps1` OS 级注入仅保留给真输入栈判别实验」。

### D4 QA 脚本迁移与 dogfood

- **取代**：`uitext.ps1`（整个）、r3-*.ps1 的 Get-UiRows/÷1.5/±150 定位段、f8-t2-ui.ps1 的
  checkbox −12px 标定与滑条坐标——全部改 `ui_tree` 定位 + `ui_click/ui_drag/ui_input` 驱动。
- **保留**：`brp.ps1`（底层封装 + 新方法 wrapper `Get-UiTree`/`Invoke-UiClick`/`Get-CameraState`）、
  `input.ps1`（OS 级真输入栈：R1 disc/grab 判别仍需）、`screenshot.ps1`（PrintWindow 交叉验证
  通道，降级为辅）、`pixdiff.ps1`、`r1-drive.ps1`（R1 回归骨架，驱动段换 input.motion）。
- **dogfood（= T-QT-T2 的真机验收，也是新工具的验收）**：
  1. **重跑 T02-T1 QA 真机项**（`loop/plans/t02-inspector-loop.md` §7）：§7-3 快速切换 5 轮
     （ui_input 打数值 + Enter 与 ui_click 点 outliner B 同发）、§7-2 Point Light
     color/intensity 抽验（ui_click 开 Add 菜单 → ui_input 填 intensity）；
  2. **R1 环视回归**：input.motion 手势 → camera_state yaw 变化断言（取代 SendInput 通道）；
  3. **R3 菜单回归**：ui_click(text="3D Objects" hover) → ui_click(text="Cube") → scene_bsn
     断言（废弃全部坐标数学）；
  4. **F8 尾巴**：滑条 ui_drag 到 0.85 → `world.get_components` 断言 `post.bloom_intensity`
     （收 feature-08-t2-qa.md 发现 1 的真人补验欠账）。
- 新脚本落 `loop/qa/qt-*.ps1`（如 `qt-t02t1.ps1`、`qt-look.ps1`、`qt-menu.ps1`、`qt-slider.ps1`），
  旧脚本不删（历史证据链），头部加「已被 qt-* 取代」注记。

### D5 agent 使用面

- **架构不变**：独立 bin `jd-mcp`（stdio）连编辑器 BRP 15703；编辑器不内嵌 MCP。
- **agent 接入**：MCP client 配置（ZCode/Claude 系）按 book 现成 JSON：
  `{"mcpServers":{"jackdaw":{"command":"jd","args":["mcp","--project","<项目根>"]}}}`。
  loop 的 QA 子代理继续走 PowerShell+BRP（无需 MCP client，brp.ps1 wrapper 即 API）；
  两条通道打到同一批方法，行为一致。
- **文档**：`loop/qa/manual.md` 增补「§7 UI 驱动通道（ui_*）+ §8 MCP 通道与速查表」
  （含两个 motion 闸门约束的手势模板）；book `remote-control.md` 工具表加 5 行。

### D6 测试策略

1. **单测**（test_input.rs / ui_probe.rs）：input.motion 写出 MouseMotion 消息（仿现有 wheel
   用例：init Messages 资源 → emit → read 断言）；ui 换算公式（UiGlobalTransform×
   inverse_scale_factor×UiScale）单测；ui_tree kind 判定单测。
2. **in-process 集成**（`tests/guards/editor_remote.rs` 扩展）：ui_tree 结构断言（spawn 带
   ButtonOperatorCall 的按钮）；ui_click 排入 SyntheticInput 队列 + 拒点分支（disabled/
   歧义/不可见）；camera_state 数值；wait idle 含 synthetic 队列（排队后 idle 不答、播完答）。
3. **headless 全链路**（新 `tests/controls/ui_probe_click.rs`，仿 synthetic_click.rs）：
   经 `jackdaw/ui_click` handler → 真 picking → ButtonOperatorCall 派发 operator，断言副作用。
4. **`tests/mcp_smoke.rs`**：工具名清单加 5 个；ui_tree 真调一次断言非空。
5. **dogfood**：T-QT-T2 全套（§D4）即真机验收，报告落 `loop/reports/`。

### D7 任务拆分（2 个，串行）

**T-QT-T1（程序）**：
1. `src/test_input.rs`：`Emit::Motion` + `input.motion` operator + 单测（含拆拍/上限钳制）；
2. `src/remote/ui_probe.rs`：ui_tree/ui_click/ui_drag/ui_input/camera_state 五个 handler +
   server.rs 注册 + `wait` idle 扩展（editor_is_busy 加 SyntheticInput 判定）+ 单测；
3. `tests/guards/editor_remote.rs` 扩展 + 新 `tests/controls/ui_probe_click.rs`；
4. `crates/jackdaw_mcp/src/lib.rs`：5 个新工具（Args 结构体 + 薄翻译）+ `tests/mcp_smoke.rs` 清单；
5. book remote-control.md 工具表扩行；
6. quick tier 四门（fmt/clippy/test --lib/被改 crate 集成）。

**T-QT-T2（QA + 轻量程序）**：
1. dogfood 全套（D4 四项：T02-T1 真机项重跑、R1 回归、R3 回归、F8 滑条尾巴）；
2. `loop/qa/qt-*.ps1` 新脚本 + 旧脚本取代注记 + `manual.md` v2（UI 驱动通道 + MCP 速查 + motion
   手势模板）；
3. 发现问题走修复循环（上限 5 轮），F8 发现 1 若根因在 pinned bevy slider 则出最小复现升级用户；
4. 台账 `loop/progress.md` 记行 + roadmap 回位。

## 3. 工具规格表

### 3.1 BRP 方法（编辑器内实现）

| 方法 | 参数 | 返回 | 实现 |
|---|---|---|---|
| `jackdaw/ui_tree` | `root?`(entity id)、`depth?`(默认 6)、`text?`(子串)、`operator?`(ButtonOperatorCall.id 前缀)、`kind?`(button/checkbox/slider/text_input/picker/dialog/menu_item/node/text)、`visible_only?` | `{nodes:[{entity,kind,text,operator,disabled,checked,visible,rect:[x,y,w,h](物理px),value,min,max?(slider),index(同过滤内序号),children:[…]}]}` | ui_probe.rs，walk UI 根（含编辑器 chrome；scene UI 以 UiSceneRoot 标注） |
| `jackdaw/ui_click` | `entity?` \| `operator?` \| `text?`+`index?`(消歧，默认 0)、`double?` | `{clicked:true,target:{entity,kind,text,operator},at:[x,y](逻辑px)}`；歧义→INVALID_PARAMS 列候选；disabled/不可见→INVALID_PARAMS 带原因 | 定位→中心换算→SyntheticInput click beats |
| `jackdaw/ui_drag` | `entity`、`from:[fx,fy]`、`to:[fx,fy]`(0..1 控件相对)、`steps?`(默认 8)、`frames?` | `{dragged:true,from:[x,y],to:[x,y]}` | rect×分数→press+插值 CursorMoved+release |
| `jackdaw/ui_input` | 定位同 ui_click、`text`、`commit?`(enter 默认/blur/none) | `{typed:true,focused:entity,commit}` | click 聚焦拍→逐字符 key 拍→Enter/点外拍，单队列 |
| `jackdaw/camera_state` | — | `{camera:entity,translation:[x,y,z],yaw,pitch(度,YXZ),projection:"perspective"/"ortho{scale}",fly:bool,pan:bool}` | ActiveViewport.camera → Transform/GlobalTransform + CameraFlyActive/CameraPanActive |
| `jackdaw/wait`(扩展) | `until:"idle"` 语义：+SyntheticInput 队列空 | 同现状 | server.rs editor_is_busy 加判定 |
| operator `input.motion` | `dx,dy`(累计)、`steps?`(默认 1)、`frames?` | call_operator 通用返回（warnings 带闸门提示） | Emit::Motion→write_message(MouseMotion) 拆拍 |

### 3.2 MCP 工具（薄翻译）

| 工具 | 参数 | 对应 BRP | 痛点映射 |
|---|---|---|---|
| `ui_tree` | 同 BRP | jackdaw/ui_tree | 取代脚本端 world.query+坐标 dump（DPI/裁剪脆弱） |
| `ui_click` | 同 BRP | jackdaw/ui_click | 磁铁按钮/菜单行/checkbox 定位半天地→语义定位 |
| `ui_drag` | 同 BRP | jackdaw/ui_drag | 滑条/scrub 值为 0（F8 发现 1） |
| `ui_input` | 同 BRP | jackdaw/ui_input | 数值框/文本框打字+提交时序 |
| `camera_state` | — | jackdaw/camera_state | 环视/平移断言不再脚本端提欧拉 |
| （既有 `call_operator` 即可调 `input.motion/input.key/input.pointer`，不另设工具） | | | |

## 4. QA 验收清单（T-QT 任务自身）

- quick tier 四门（fmt/clippy `-D warnings`/`test --workspace --lib`/被改 crate 集成）；
- `tests/controls/ui_probe_click.rs` headless 全链路绿（ui_click→picking→operator 副作用）；
- `tests/guards/editor_remote.rs` 新用例绿（结构/拒点/wait idle 含手势）；
- `tests/mcp_smoke.rs` 工具清单含 5 新工具 + ui_tree 真调非空（有显示环境时）；
- 真机快测（T-QT-T2 开跑前）：ui_click 走 Add 菜单建 Cube 成功；input.motion 环视 yaw 变化>0；
  滑条 ui_drag 后组件值=预期；
- dogfood 四项全绿 + T02-T1 QA 报告落 `loop/reports/`；
- 文档核对：book 表 5 行、manual.md 速查表与实际工具签名一致。

## 5. 风险

1. **motion 闸门误判**：FLY_LOOK_SUPPRESS_FRAMES(3) 与 1000px/帧上限未写进手势模板 → dogfood
   误判「motion 无效」。缓解：input.motion warnings 主动提示 + manual.md 模板（rest 3 帧→小步多拍）。
2. **pinned bevy slider normalize 根因未查**（F8 发现 1 归因坐标空间）：编辑器内换算后若 ui_drag
   仍得 0，是 bevy 侧 bug。降级路径：报告最小复现升级用户裁决（直插 SliderValue+trigger
   ValueChange 不作默认——非真路径）。
3. **ui_tree 体量**：全树上千节点。缓解：depth 默认 6 + 过滤参数 + 建议脚本带 text/operator 过滤；
   返回只含判定字段不反射全组件。
4. **ui_click 命中被遮挡控件**（同位置上层浮层）：picking 会点到上层——这**正是真实行为**，
   文档言明「ui_click 不保证命中目标实体本身，只保证点到目标位置」；需要确定命中时可先
   ui_tree 查 visible/Hovered。不为此做命中预演（会复刻一套 hit-test 与真实 picking 漂移）。
5. **不加门控的暴露面**：loopback+remote.enabled 已限；若后续发布版要收紧，可在 RemoteSettings
   加 `qa_tools` 子开关（本任务不做，裁决口留风险段）。
6. **ActiveTool Reflect 注册**：manual.md §2 说未注册、`world.get_resources` 读不到；T1 顺手
   `register_type::<ActiveTool>()` 一行（不动行为）；若 QA 实测已注册则跳过。
7. **wait idle 语义变化**：现有脚本所有 `until:idle` 会多等手势播完（方向正确但时长变长），
   dogfood 前知会；见裁决 2。

## 6. 需用户裁决项

1. **`ui_input` 默认 commit 语义**：Enter（键盘提交链）还是 blur（点外提交链）？
   建议 **Enter 默认 + blur 可选**（Enter 路径短、无二次点击副作用；T02-T1 §7-3 的「回车与
   切换连发」正需要 Enter 链）。
2. **`until:idle` 并入手势播完**：建议并入（消灭时序赌）；代价是既有 idle 等待在慢手势下变长
   （至多多几百 ms）。若不愿改语义，备选：加独立 `until:"input_idle"`。
3. （备注，非阻塞）MCP 是否要 `ui_find` 独立工具名——本方案裁掉（ui_tree 过滤参数替代），
   若用户偏好更多语义化工具名可加，成本一行。
