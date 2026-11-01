# 交互驱动手册 v2（T-QT-T2，2026-10-25）

> v2 口径（T-QT-T2 dogfood 后落定）：**驱动 UI 一律优先 §7 新工具**
> （`ui_tree`/`ui_click`/`ui_drag`/`ui_input`/`camera_state`/`input.motion` 手势模板）；
> 本手册 §2–§5 的旧法（world.query 坐标定位、input.pointer 坐标点击、Get-YawPitch、
> OS 级 SendInput 环视）降为**辅助/对照手段**——仅两类场景仍必须走旧法：
> ① **真输入栈测试**（raw WM_INPUT、RMB fly 抢焦点、DPI/前台焦点时序、驱动器层差异），
> 用 §4 `input.ps1`；② 与旧构建（2026-10-24 工具合入前）对话时无新方法可调。
> v1 来源：`loop/plans/feature-05-interaction-ux.md` §5，按 T1 落地实测校正；
> loop/ 不入 git，本手册与脚本随 loop 目录留存，成熟后再议入库（方案裁决 4）。

## 0. 脚本清单（本目录）

| 脚本 | 职责 | v2 状态 |
|---|---|---|
| `brp.ps1` | BRP JSON-RPC 封装：`Brp-Call` / `Brp-Result` / `Wait-EditorReady` / `Wait-BrpResult`（watching 轮询）/ `Get-FlyCamera` / `Get-YawPitch` / `Reset-Modal` | 基础设施，保留；`Get-FlyCamera`/`Get-YawPitch` **由 `camera_state` 取代**（仅旧构建对照用） |
| `input.ps1` | OS 级 SendInput：RMB/LMB 按放、相对移动、按键按住（`Send-KeyHold W -Ms 400`）、`Get-JackdawHwnd` / `Focus-Jackdaw` / `Set-CursorToWindowPoint`（窗口内比例坐标→屏幕物理像素） | **保留**（真输入栈测试唯一手段，见 v2 口径） |
| `screenshot.ps1` | `Save-WindowScreenshot`（PrintWindow + PW_RENDERFULLCONTENT 全窗口 PNG） | 保留（视觉留档） |
| `uitext.ps1` | world.query 拉取 UI Text/UiGlobalTransform → 脚本端坐标定位 | **deprecated**：被 `ui_tree` 取代（文件头已注记）；仅 diff 对照用 |
| `r1-drive.ps1` … `t01-*.ps1`/`t2-*.ps1`/`f5-*`/`f8-*`/`r2-*`/`r3-*` | 历史轮次驱动/诊断脚本 | **历史证据留档**：其「ui text 坐标定位 + input.pointer 坐标点击」方法已被 §7 取代，新脚本勿再仿写；R1/R1b 的 OS 级环视方法仍有效 |
| qt 脚本模式（`t-qt-t1-*`、`t-qt-t2-*`，loop/reports/） | 新工具驱动脚本 | **必须带 Brp-Call 重试**（catch WebException → 250ms 退避重发，T-QT-T1 ⚪ 教训：陈旧 keep-alive 偶发 20s 超时；`t-qt-t2-qa-live.ps1` 的 `Brp-Call` 为标准模板） |

用法（可直接复跑）：

```powershell
# 完整验收（修复后）
powershell -ExecutionPolicy Bypass -File E:\Project\rust\jackdaw\loop\qa\r1-drive.ps1 `
  -Exe E:\Project\rust\jackdaw\target\debug\jackdaw.exe -Repeat 10 -Label fixed -Drive Full
# 判别实验（配合判别版二进制的 JACKDAW_FLY_GRAB）
powershell -ExecutionPolicy Bypass -File ...\r1-drive.ps1 -Drive Press -Repeat 5 -GrabEnv confined -Label confined
```

## 1. 启动与就绪

- CLI 不接受位置参数路径；用环境变量：
  `JACKDAW_OPEN_PROJECT=C:\Users\linbo.zhang\Projects\my-game`，然后启动
  `target\debug\jackdaw.exe`（或指定 Exe）。
- 多实例分端口：`JACKDAW_REMOTE_PORT=15713`；默认 **15703**（`DEFAULT_PORT`，
  绑 loopback；端口被占则放弃监听并 warn；`remote.enabled` 默认开，QA 工程勿关）。
- 无人值守冒烟：`JACKDAW_RUN_OP=entity.add.cube; input.key key=Escape`
  （`JACKDAW_RUN_OP_GAP` 控制子句间隔）。
- 就绪判定：轮询 `jackdaw/status` 应答（上限 60–90s），或工程目录出现
  `.jackdaw/editor.json`。就绪后先 `jackdaw/wait {"until":"idle"}` 等资产管线静默。

## 2. BRP 调用（JSON-RPC 2.0 over HTTP，POST http://127.0.0.1:15703/）

- **实测校正**：pinned bevy 0.20-dev 的标准方法前缀是 `world.*` 而非 `bevy/*`：
  `world.query` / `world.get_components` / `world.list_components` / `world.get_resources`
  / `app.info` / `registry.schema` 等。jackdaw 自有方法保持 `jackdaw/*`：
  `status | operators | call_operator{id,params,history} | batch | cancel | scene_tree |
  entity{entity|name} | apply_bsn | scene_bsn`；watching 型：`jackdaw/screenshot
  {kind=viewport|window|viewport2d, path}`、`jackdaw/wait {until:'idle'|'pie_running'|
  'pie_stopped', frames:N}`、`jackdaw/assets`。
- **watching 轮询语义（实测）**：方法未完成时 HTTP 响应的 `result` 为 `null`，
  客户端**用相同 params（同 key）重发**直到 `result` 非 null；10s 超时。
  `wait` 的 key 由 params 决定，不同 frames 值是不同 key。
- 相机 Transform 读取（R1/R3 用）：

```json
{ "method": "world.query", "params": {
    "data":   { "components": ["bevy_transform::components::transform::Transform",
                               "bevy_camera::camera::Camera"] },
    "option": ["bevy_camera::projection::Projection"],
    "filter": { "with": ["bevy_camera::camera::Camera"] } } }
```

  选 `Camera.is_active == true` 且 `Projection` 为 `Perspective` 的行＝3D 视口相机
  （场景预览相机 is_active=false；2D 画布相机为 Orthographic）。
  yaw/pitch 用 YXZ 欧拉从四元数提取（`Get-YawPitch`，与 `camera_system` 一致）。
- `jackdaw/cancel` 远程取消活动 modal（QA 复位用）。
- 注意：`ActiveTool`/`EditMode` 未注册 Reflect，BRP 读不到（T1 顺手补，见方案备注）。

## 3. 合成输入（进程内，BRP）：`input.pointer` / `input.key` / `input.text`

- 只产生 winit `WindowEvent`（`CursorMoved`/键盘），下游 picking/UI 全当真；
  适合菜单点击（R3）、Inspector 输入（`input.text`）、Esc 事件到达路径（R2）。
- **能力边界**：不产生 raw `MouseMotion` → 无法驱动 NavLook / 任何读
  `AccumulatedMouseMotion` 的路径。**R1 与 RMB-fly 验证必须走 §4 的 OS 级注入。**

## 4. OS 级输入注入（`input.ps1`，SendInput）

- SendInput 是 OS 级注入，产生真实 WM_INPUT raw delta（与物理鼠标不可区分），
  可驱动环视；`SetCursorPos` 只产生 WM_MOUSEMOVE（不影响 raw delta）。
- 坐标：`GetWindowRect`/`SetCursorPos`/相对移动全用物理屏幕像素，避开 DPI 缩放；
  窗口定位按进程 MainWindowHandle（窗口无标题栏文本）。
- 注入前必须 `Focus-Jackdaw`（焦点丢失会触发 `end_fly_on_focus_loss` 提前结束 fly）；
  视口命中点默认窗口中心（可用 `-XFactor/-YFactor` 调整）。

## 5. 视觉双通道

- 首选 BRP `jackdaw/screenshot kind=viewport`（所见即所渲染，不受遮挡/最小化影响）；
- 整体 UI 态（工具栏高亮、modal 提示）用 `Save-WindowScreenshot`（PrintWindow）；
- 比对：QA 肉眼看图 + 像素 diff 辅助（R1 前后视口图应几乎一致）。

## 6. 时序规约（防 flaky）

1. 启动 → `jackdaw/status` 就绪（上限 90s）→ `wait until=idle`。
2. 每个 UI 操作后 `jackdaw/wait {"until":"idle"}`（报告含活动 modal）或
   `{"frames": N}` 固定帧。
3. watching 方法轮询同 key，超时 10s。
4. 用例前 `jackdaw/cancel` 复位活动 modal。
5. 每用例截图留档 `loop/reports/`。
6. 跑前先杀旧 jackdaw 进程（端口冲突）；判别实验多 run 用不同 `-Label` 目录隔离。

## 7. 新工具速查（T-QT-T1 落地，2026-10-24）

> 本节是速查；脚本迁移（qt-*.ps1、旧脚本废弃注记）与 dogfood 归 T-QT-T2。
> 来源：`loop/plans/t-qt-qa-mcp.md`，实现 `src/remote/ui_probe.rs` + `src/test_input.rs`。

### 7.1 BRP 新方法（`jackdaw/*`，POST 15703）

| 方法 | 参数 | 返回/语义 |
|---|---|---|
| `ui_tree` | `root?`(entity)、`depth?`(默认6)、`text?`(标签子串)、`operator?`(ButtonOperatorCall id 前缀)、`kind?`(button/menu_item/checkbox/slider/text_input/picker/dialog/text/node)、`visible_only?` | `{nodes:[{entity,kind,text,operator,disabled,checked,visible,rect:[x,y,w,h]物理px,value/min/max(slider),index,scene,children}]}`。带过滤时只返回命中的控件（及其子树）；无过滤走编辑器 chrome + 场景 UI 根。取代脚本端 world.query+坐标换算 |
| `ui_click` | `entity?` \| `operator?` \| `text?`+`index?`、`double?` | `{clicked,target:{entity,kind,text,operator},at:[x,y]}`；定位→编辑器内换算中心→SyntheticInput 排 move+press+release（真实 picking/observer 链）。歧义→INVALID_PARAMS 列候选；disabled/隐藏/无框→INVALID_PARAMS 带原因。**注意 ui_click 只保证点到目标位置，被浮层遮挡时点到的是浮层（真实行为）** |
| `ui_drag` | `entity`、`from:[fx,fy]`、`to:[fx,fy]`(0..1 控件相对)、`steps?`(默认8) | `{dragged,from,to}`；move 到 from→press→插值 CursorMoved→release。滑条/scrub/分割条通用。**滑条输出看 ValueChange 事件（宿主回写 SliderValue），断言组件值需走宿主侧（如 world.get_components 读 post.bloom_intensity）** |
| `ui_input` | 定位= `entity?`/`operator?`(+`index?`)（**text 是要打的内容，不能当定位符**）、`text`、`commit?`(enter 默认/blur/none) | `{typed,focused,commit}`；单队列：click 聚焦→Ctrl+A→逐字符→Enter/点外。消「先 focus 再打字」时序坑 |
| `camera_state` | — | `{camera,translation,yaw,pitch(度,罗盘/俯仰,同 view.orbit 口径),projection:"perspective"/"ortho"(+ortho_scale),fly,pan}`；无相机时 `camera:null` 不报错。取代 brp.ps1 Get-YawPitch |
| `history` | `entries?`(末尾 N 条标签,默认8,上限64) | `{undo_len,redo_len,saved_len,has_save_baseline,dirty,top,undo:[{label}],redo:[{label}]}`（undo/redo 最新在前）。撤销记录数断言的基础设施（T03-T2 落地）；MCP 侧同名薄工具 |
| `wait`(扩展) | `until:"idle"` 语义扩展 | **SyntheticInput 队列非空即 busy**：ui_click/ui_drag/ui_input/input.* 排的手势播完才答 idle（消灭 -Milliseconds 300/700 赌帧） |

### 7.2 新 operator（`jackdaw/call_operator` 直达）

| operator | 参数 | 语义 |
|---|---|---|
| `input.motion` | `dx`,`dy`(累计px)、`steps?`(拆拍,默认1)、`frames?` | 每拍 `write_message(MouseMotion)`（First 注入→PreUpdate 累加→Update 消费），驱动 NavLook/环视/平移——`input.pointer` 无法产出的 raw delta 维度。单拍 >1000px 会告警（闸门丢弃整拍） |

### 7.3 motion 手势模板（两个闸门，勿踩）

1. **1000px/帧幅度闸**（`MAX_PLAUSIBLE_POINTER_DELTA`）：单帧 delta>1000 整拍丢弃。
   大位移必须 `steps` 拆小（如 dx=320 用 steps=16 → 20px/拍）。
2. **fly 3 帧抑制窗**（`FLY_LOOK_SUPPRESS_FRAMES=3`）：RMB 按下后前 3 帧 look 全丢。
   环视手势：`input.pointer action=press button=secondary` →
   `input.pointer action=rest steps=4` → `input.motion dx=… steps=…` →
   `input.pointer action=release button=secondary`，每步之间 `wait until=idle`。
3. 断言：前后各 `camera_state` 比 yaw（motion dx 正=向右转，罗盘角变化）。
4. MCP 侧同一批能力：工具 `ui_tree/ui_click/ui_drag/ui_input/camera_state`，
   `input.motion` 经 `call_operator`（tools/list 共 20 个工具）。

### 7.4 已核边界（headless 全链路已钉死，tests/controls/ui_probe_click.rs）

- ui_click 定位文本→嵌套 FeathersButton→operator 派发：全链路 OK；
- ui_drag → 真 picking PointerDrag → ValueChange ramp OK（ValueChange 是 widget 真输出）；
- ui_input → click 聚焦（feathers input 自带 press observer 设焦点）→ Ctrl+A 覆盖 →
  打字到 TextEditValue OK；**点击 aim 的是 input 自身框**（点 wrapper 会冒泡清焦点，
  sized_placement 自身→后代→祖先回退已处理）；
- input.motion → AccumulatedMouseMotion 帧内到达 OK。

### 7.5 真机 dogfood 沉淀（T-QT-T2，2026-10-25，T02-T1 验收实战）

- **窗口尺寸先对齐布局**：编辑器 UI 按较大逻辑尺寸布局，默认 1280x720 窗口下右侧
  Inspector 输入列（x≈1250+）部分越出可拾取区——ui_click/ui_input 会 `clicked:true` 但
  **手势静默落空**（无命中无告警）。真机驱动 Inspector 一律先 `JACKDAW_WINDOW_SIZE=1920x1080`
  （实测同一步骤在 1920 窗口立即生效）。对比证据见 `t-qt-t2-qa-switch.ps1` 两轮输出。
- **Inspector 数值行的本体是 ScrubNumberInput 内嵌的 FeathersTextInput**：`ui_tree
  kind=text_input` 才是可点对象；X/Y/Z 标签 glyph 是**兄弟节点**（不在输入子树内），
  点标签=点空。行分组法：h≈24 的 text_input 按 y 分组，首行 3 个=translation（X/Y/Z），
  取中位=Y。
- **卡片默认折叠**（`Display::None` → 子树 rect 全零）：定位字段前先点卡片标题行展开；
  折叠状态按组件名粘滞（selection 重建后保持展开）。
- **bevy BRP 与 jackdaw BRP 的实体格式不同构**：`world.query`/`world.get_components` 用
  `"NvM"` 字符串，`jackdaw/*`（ui_tree/ui_click/scene_tree）用 raw bits u64——跨方法换用
  需重建映射；数据断言建议直接 `world.query`（Name+组件）一次拉全量建 name→value 表。
- **ui_tree text 过滤返回"命中子树的根"**，非文本载体本体；取本体要 walk children 找
  `text == 目标` 的节点（outliner 行=「直接子文本==名字」的父节点）。
- **禁触 y<40 的顶部条节点**：对标题栏区域（如 [1142,0,46,34]）的合成点击曾两次把窗口
  缩成 16x16（根因未查，winrect 实测）——定位过滤一律带 `rect[1] > 100` 下限。
- **编辑器直连后台派生在本轮环境可行**（`cmd /c` 前缀 PATH + 输出重定向 + run_in_background），
  上轮「harness 无法派生窗口进程」的结论已过时；dylib-host exe 需 deps+toolchain lib 前缀
  （launch4 模式，见 `t-qt-t2-qa-live.ps1` launch 段）。
- **临时工程门槛**：`JACKDAW_SKIP_SETUP_CHECK=1` 不跳过「无 Cargo.toml/jackdaw.toml」的
  启动对话框；临时工程要齐 `Cargo.toml`+`jackdaw.toml`（fixture: tests/fixtures/definition_project），
  否则直接用 my-game（**不存盘策略**：跑前跑后 SHA256 校验 scene.bsn）。
- **游戏窗按键注入必须心跳式 hold**（T20-T2，2026-11-01，macOS）：未聚焦的游戏窗跑
  winit `reactive_low_power`（有事件才有帧）——按键按下后若无后续事件，帧停滞、系统不消费。
  任何 hold 期间保持消息流（每拍一条=一帧，t20-live.sh `tap_key`/`walk_axis` 已固化）；
  位置腿走 poll-driven 步进（先降 `move_speed` 到 0.5 再测量）。
- **游戏 flow 断言走文档根标记**（T20-T2，EG8/A16 关联）：游戏侧 `State<GameFlow>` 未
  反射注册，BRP 读/写 flow 通道死（`Unknown resource type`，红证 `t20t2_eg8_flow_state_red.log`）
  ——flow 断言一律读 MenuRoot/HudRoot/GameOverRoot 标记（`world.query` 有无即可）；
  通道开放归 A16（buglist），勿在 QA 脚本里重试 BRP flow 拼写。
