# T-QT-T1 报告：BRP 方法层 + input.motion + MCP 工具 + 测试 + book

> 任务：插队 T-QT「QA 驱动工具层」任务 1（程序）。
> 分支 `loop/t-qt-qa-mcp`（基于 main `bc5274ee`）。方案：`loop/plans/t-qt-qa-mcp.md`。
> 日期：2026-10-24。dogfood/脚本迁移/台账归 T-QT-T2，未做。

## 交付一览

### BRP 5 方法（`src/remote/ui_probe.rs` 新文件，server.rs 注册）

| 方法 | 实现要点 |
|---|---|
| `jackdaw/ui_tree` | root/depth(默认6)/text/operator/kind/visible_only 过滤；节点 {entity,kind,text,operator,disabled,checked,visible,rect(物理px),value/min/max(slider),index,scene,children}；kind 按组件判定（dialog/picker/checkbox/slider/text_input/menu_item/button/text/node）；过滤时定位器映射到 actionable 祖先 |
| `jackdaw/ui_click` | entity/operator/text(+index)/double；定位→sized_placement（自身→后代→祖先 box 兜底）→SyntheticInput click beats（真实 picking 链）；歧义→INVALID_PARAMS 列候选（entity/kind/text/rect）；disabled/隐藏/无框→带原因拒绝 |
| `jackdaw/ui_drag` | entity + from/to(0..1 控件相对) + steps(默认8)；move→press→插值 CursorMoved→release，走真 picking PointerDrag |
| `jackdaw/ui_input` | 定位（entity/operator+index；**text 是打字内容不能定位**）+ text + commit(enter 默认/blur/none)；单队列 click 聚焦→Ctrl+A→逐字符→Enter/点外 |
| `jackdaw/camera_state` | ActiveViewport.camera（回退唯一 MainViewportCamera）；translation/罗盘 yaw/俯仰 pitch（度，同 view.orbit 口径）/projection(+ortho_scale)/fly/pan；无相机时 camera:null 不报错 |

### operator 与语义扩展

- `input.motion`（src/test_input.rs）：dx/dy/steps/frames，每拍 `write_message(MouseMotion)`（First 注入→PreUpdate 累加→Update 消费，方案核实链）；单拍 >1000px 告警（引用 `MAX_PLAUSIBLE_POINTER_DELTA`，input_contexts.rs 改 pub(crate)）；排在未播完手势后告警（3 帧抑制窗提示）。
- `jackdaw/wait until=idle` 扩展（server.rs `editor_is_busy`）：SyntheticInput 队列非空即 busy（对齐 boot_ops 语义，裁定②）。

### MCP 5 工具（crates/jackdaw_mcp/src/lib.rs，薄翻译）

`ui_tree` / `ui_click` / `ui_drag` / `ui_input`（UiInputLocator 无 text 防冲突）/ `camera_state`。tools/list 共 **20** 个。`input.motion` 按方案走 `call_operator` 不另设工具。

### 测试

- 单测：test_input 12 个（motion 消息流/拆拍/手势构造器）、ui_probe 5 个（可见性/禁用/kind/欧拉/fraction）。
- in-process guards（tests/guards/editor_remote.rs +4）：ui_tree 结构、排队手势挂住 idle 播完才答、camera_state 无相机、remote.enabled 关闭拒答。
- headless 全链路（tests/controls/ui_probe_click.rs 新 6 个）：ui_click 文本定位→真 picking→operator 副作用（wireframe 翻转）；歧义/禁用/落空拒收；ui_input 打字+提交（TextEditValue="entity: 42"）；ui_drag 滑条 ValueChange ramp（0.1125→0.9）；input.motion→AccumulatedMouseMotion 帧内 (40,-10)；camera_state 欧拉回读（yaw135°/pitch30° ±0.01）。
- mcp_smoke：工具清单 +5，status 后加 ui_tree 真调断言。

### 文档

- book/src/developer-guide/remote-control.md：工具表 +5 行，新增「Driving the screen」「Turning the camera」两节（含 motion 双闸门模板）。
- loop/qa/manual.md：新增 §7 新工具速查（7.1 BRP 方法表 / 7.2 operator / 7.3 motion 手势模板 / 7.4 headless 已核边界）。

## 真机轻量自验（`loop/reports/t-qt-t1-selfcheck.ps1`，PASS）

编辑器 `target\debug\jackdaw.exe` + 临时工程，BRP 15794，全 PowerShell：

| 步骤 | 结果 |
|---|---|
| ui_click「Open without setup」（启动卡片**手搓** ObservedBy 按钮） | clicked at [765,451]，编辑器进入主界面 |
| ui_click「Add Entity」（outliner 真按钮） | clicked at [99,111]，实体 picker 打开（ui_tree 见 3D Objects 等 11 分类） |
| ui_input picker 搜索框（宽 556px 的 text_input 实体）打 `Cube`+Enter | typed:true，过滤出 Cube 行 |
| ui_click「Cube」 | clicked at [99,392.5]；scene_tree = Directional Light, **Cube** |
| input.motion 环视：press RMB(x=900 探测 fly=true)→rest 5 帧→dx=240/24 拍→release | yaw **0°→-41.25°（Δ41.25°）**，pitch 26.565° 不变 |

MCP 薄层另验（`t-qt-t1-mcp-probe.ps1`，PASS）：`jd mcp` stdio initialize→tools/list **20 工具**（5 新全在）→ui_tree 真调非空→camera_state 应答。

## 门禁

| 门 | 结果 | 日志 |
|---|---|---|
| cargo check -p jackdaw_remote -p jackdaw_mcp -p jackdaw | PASS | （终端） |
| cargo xtask fast（fmt+clippy -D warnings+lib） | exit 0；2863 passed / 2 skipped | loop/reports/t-qt-t1-gate-fast.log |
| cargo xtask integration | exit 0；5023 passed / 3 skipped（提交树终跑，无 flaky） | loop/reports/t-qt-t1-gate-integration.log |
| mcp_smoke（强制） | **无法在本机跑**：`has_a_display` 只认 DISPLAY/WAYLAND_DISPLAY（Unix），Windows 恒 skip；强制位则断言失败。等价 wire 路径已用 t-qt-t1-mcp-probe.ps1 验证；Linux 有显示环境时 CI 会跑扩展断言 | loop/reports/t-qt-t1-gate-mcp-smoke.log |

## 与方案偏差（自验驱动，均先证实再改）

1. **is_actionable 加 `ObservedBy` 兜底**：启动卡片/project_select 的按钮是手搓 Node+`On<PointerClick>` observer，无任何 widget 标记——不兜底则 ui_click 对整个启动面失明（方案未预见）。
2. **精确标签优先**：`Add` 会歧义命中 5 个 `Add …` 按钮；精确匹配集非空时优先（方案只说 index 消歧）。
3. **picker/dialog 根兜底改点文本自身**：分类头等惰性文本的 actionable 祖先是全屏 picker 根，点根中心会命中随机行（自验中点出过 Cone）。
4. **ui_input 加 Ctrl+A**：click 的 MoveToPoint 定位光标会清掉选区，覆盖输入必须显式全选（真实用户路径）。
5. **drag/click 手势 press 前先 move**：press 时无光标位置则 picking 落空（drag_to 原语义 bug，同步修正 drag_gesture）。
6. **滑条断言口径**：widget 不自持 SliderValue（宿主回写），headless 断言 ValueChange ramp——**F8 发现 1 的 headless 证据：编辑器内换算后绝对坐标拖拽链路是通的**，「值为 0」疑在旧脚本的坐标换算/时序，非 bevy slider normalize 根因；T2 dogfood 定论。

## Concerns / 遗留

- mcp_smoke 的 display 探测对 Windows 失明（既有问题，未动；改它超出本任务边界，T2 或用户裁决）。
- wait idle 语义变长（慢手势多等几百 ms）——裁定②预告，dogfood 前知会。
- picker 列表条目懒加载：ui_tree 只见分类头属正常；条目经搜索框过滤可达（自验路径已验证）。
- label_of 的 ObservedBy 兜底理论上可能把带 hover-observer 的容器当可点祖先（取最近 actionable，风险低）。
- `input.motion` 的 dy 符号按 winit 语义（正=向下拖），手册已写。
