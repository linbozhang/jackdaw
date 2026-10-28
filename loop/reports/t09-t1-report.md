# T09-T1 实施报告：游戏动作系统核心 + 模板教学 + 混用消解补齐

> 任务：`loop/plans/t09-input-actions.md` §二 T1（I1+I2+I3+I5；决策 1/2/6 已裁）。T0 补验被环境事件
> （第 3 次完全冻结形态）阻断，按主控指示照常推进 T1。
> 分支 `loop/t09-input`（自 main 9a874945 拉出），提交 **f06b63ed**
> `Add the game-side input action system with editable bindings`（6 文件 +778/−5）。未 push，未合入（待 QA）。

## 一、交付

### 1. runtime 求值层（`crates/jackdaw_runtime/src/game_input.rs`，新模块）

- **数据类型**（决策 1-A 配置资产同族）：`GameInputConfig{actions: Vec<GameActionDef>}`（Asset+Resource+Reflect+Clone，手动 `Default`=内置五动作表）；`GameActionDef{name, kind, bindings}`；`GameInputBinding` enum：`Key(KeyCode)`/`MouseButton(MouseButton)`/`MouseMotion`/`GamepadButton(GamepadButton)`/`GamepadAxis{axis, deadzone}`——**bevy 原生类型字段**（serialize feature，绕开 display-name 往返=W27 病结构免疫）；`GameActionKind`（Button/Axis2D/Delta2D）。prelude 出口 `GameInputConfig/GameActions/InputActionsPlugin`（小定案）。
- **求值系统 `InputActionsPlugin`**（PreUpdate，`.after(InputSystems)` 保证引擎 ButtonInput 重建/鼠标累计先完成——bevy main 的 `keyboard_input_system` 每帧 clear 后从事件重建，求值必须在其后读最终态）：读 `GameInputConfig`（无资源时 plugin `init_resource` 注入内置默认——ConfigPlugin 覆盖后换文件值）+ 键盘/鼠标/`AccumulatedMouseMotion`/手柄 ButtonInput/Axis → 产出 `GameActions` Resource（`HashMap<String, GameActionState>`：pressed/just_pressed/just_released/value:Vec2）。Axis2D 多键合成+clamp 单位长度；Delta2D 帧累计；Button 读 just-pressed 直通引擎变更跟踪（PIE 注入事件=原生事件一帧后达，同真窗口语义）。
- **并集合并 `merge_actions`**（决策 1-A 修正，治 Y36 同款全量落盘病）：文件同名覆盖（kind 用文件值）、缺名回落代码默认、重复名留首条——文件缺省动作照样有（加载即并集，每帧重算使 ConfigPlugin 晚到也立即生效）。
- **死区**（决策 4-A）：`apply_deadzones` 把每个 `GamepadAxis` 绑定的 deadzone 写入 bevy `GamepadSettings` 组件的 per-axis `AxisSettings`（bevy main 该类型是 gamepad 实体上的 Component 而非 Resource——实现按此适配，Query 遍历写入）；引擎过滤后的 `Axis<GamepadAxis>` 读数即滤后值（所有读轴者一致）。
- Cargo：runtime bevy features 加 `bevy_gilrs`（workspace 树本带，游戏进程内 gilrs 后端常驻——事实四）。

### 2. I3 捕获态鼠标压制（一行级）

`keybind_focus.rs` 的 `disable_keyboard_input_when_typing`：`sources.mouse = !capture.active`——Live capture 激活时编辑器自己的 mouse action bindings 与 keyboard 同步压制；键盘独占场景（chord recording/typing）不占鼠标。UI picking 不走 InputSources（读事件流），捕获态点 Stop/面板不受影响（机制性确认，事件流断言在 T3 矩阵格 9 覆盖 mouse 腿）。

### 3. 模板教学面（`lib.rs.template`）

- 注册三行（`init_asset`+`register_asset_reflect`+`ConfigPlugin::<GameInputConfig>::new("input-actions.bsn")` 与 GameConfig 并排）；plugin 行 `InputActionsPlugin`。
- **消费示例**（~20 行）：`PlayerMarker` 实体 + `move_player_by_actions`——`Move` Axis2D 驱动 XZ 平移、`Look` Delta2D 驱动 yaw、`Jump/Interact` just_pressed 打日志（可观察）、`Pause` 同；系统只读具名动作不碰原始输入。
- doc「# Input actions」节：五动作默认表说明、`input-actions.bsn` 改绑流程、**捕获模型**（点击捕获/Shift+Esc 释放/**plain Esc 转发给游戏**——Pause 绑 Escape 的正确性依据，I5）。

### 4. 混用基线（I 系「不混用」的现状梳理，供 T2/T3 验收）

- **键盘维度**：机制已存在——`disable_keyboard_input_when_typing` 的 keyboard 腿（capture.active 压制）+ 既有单测 `capture_active_suppresses_action_keybinds`（keybind_focus tests）；数据面隔离——编辑器键位存 `PresetInput`（keymap/types.rs，全局 config 目录 keymap.json，per-user 不进工程/导出包）vs 游戏动作表 `GameInputConfig`（assets/ 工程内、随导出包走）——**两条链路零交集**（格式/存储/评估三处独立）。
- **鼠标维度**：本任务修复后两维同压制（见 §一-2）；UI picking 事件流独立通道确认。
- **手柄维度**：编辑器 `Binding`/`PresetInput` 均无 gamepad 变体（零消费=零混用面）；游戏侧本任务新增手柄绑定（读 gilrs 进程内直读，T2 调查 PIE 可达性）。
- **PIE 转发链**（事实一）：LiveInputCapture→PieInputEvent→apply_input 全链零改动复用（本任务唯一动点=I3 一行）。

## 二、红→绿（headless，环境劣化下先证机制）

| 项 | 用例（game_input.rs tests） | 形态 |
|---|---|---|
| **I1 求值核心** | `a_pressed_key_drives_the_action_it_is_bound_to`（W→Move pressed+value(0,1)；红半=无 plugin 时 GameActions 不存在——机制不存在的存在性红证，同 T1 ConfigLoader 先例）+ `rebinding_moves_the_action_with_the_binding`（**改绑红绿**：W 不再驱动、ArrowUp 驱动——「可配置生效」机制层） |
| **I2 并集合并** | `a_file_merges_over_the_defaults_as_a_union`（文件只含 Move → 五动作全在，Move 用文件 kind/绑定、Jump 用默认；重复名折叠）+ `a_partial_config_still_evaluates_the_full_action_set`（活资源上：只配 Jump 的 config → 五动作全评估）——Y36 病反证 |
| **死区** | `axis_deadzones_apply_through_the_engine_settings`（绑定死区 0.5 → GamepadSettings 该轴 bounds=±0.5——引擎过滤链确认） |
| **鼠标腿** | `mouse_motion_and_buttons_feed_actions`（MouseMotion 事件→Look Delta2D value；LMB 不驱动 Jump） |
| **I3** | keybind_focus tests 2/2：`capture_active_suppresses_action_keybinds`（**扩腿**：断言 mouse 同压制+释放后双维恢复；红=修复前 mouse 恒 true）+ `keyboard_spoken_for_leaves_the_mouse_free`（chord recording 只压键盘不占鼠标——双维门的存在意义） |

bevy main API 适配记档：`GamepadButton` 为直接 enum（无 GamepadButtonType/new()）；`GamepadAxis::LeftStickX`（非 LEFT_X）；`GamepadSettings` 是 gamepad 实体 Component（非 Resource）；`keyboard_input_system` 每帧 clear 重建（测试必须走事件注入而非直改 ButtonInput——求值系统 `.after(InputSystems)` 后读终态）。

## 三、真机腿（环境劣化，降级口径）

按任务书环境事件指示：headless 优先已完成全部机制红绿（§二）；真机腿（合成输入→capture→游戏→scene_snapshot 行为断言）**未尝试**——环境事件第 3 次完全冻结形态，T0 补验即被阻断在先。处置：留 T2（手柄调查+改键三态链本就需真机，届时环境恢复一次跑齐）；**模板实编替代证据已取**：`jd new input-game --path ...`（新 jd 含新模板+lock 快照）→ `cargo check` **exit 0**（InputActionsPlugin/ConfigPlugin/GameActions/PlayerMarker 全链编译通过，`loop/t09t1_scaffold_check.log`）。

## 四、门禁（quick 四门，全文复核+归档 `loop/t09t1_*`）

| 门 | 结果 |
|---|---|
| fmt | clean |
| clippy workspace all-targets `-D warnings` | **exit 0**（揪出 5 处 doc/backticks/重复 match 臂，修后过） |
| 单测 | runtime **37**（+6 game_input）、主 crate lib **1175**（+1 keybind_focus 新用例）、scaffold **82**（+1 input 模式断言） |
| guards | **204** 全绿 |
| 实编 | 新模板工程 `cargo check` exit 0 |

## 五、偏差与记档

1. **真机腿整体留 T2**（环境事件第 3 次冻结；任务书降级口径执行，headless 红绿+实编 check 为本层证据）。
2. **bevy main gamepad API 与方案假设有出入**（§二记档）：`GamepadButton` 无 (gamepad, button) 构造对（单 enum）——绑定语义为「任意手柄的该按钮」（per-gamepad 区分留 backlog，引擎 ButtonInput<GamepadButton> 键即单 enum，本就全手柄并集）；`GamepadSettings` per-device 组件——死区写入所有已连接手柄。
3. **I3 的 UI picking 不受影响**为机制性确认（事件流 vs InputSources 双通道），事件级断言归 T3 矩阵格 9 的 mouse 腿。
4. **`GameInputConfig` 的 `#[reflect(Default)]` 依赖手动 Default**（derive 会冲突）——schema 卡片 default 构造可用。
5. T0 两项补验（T08 遗留）被环境事件阻断，未执行，留环境恢复后按方案 T0 节跑（主控已知，本报告记档）。

## 六、buglist

无打钩项（I 系新发现；W27/Y36 教训已内化进并集合并与 bevy 原生类型字段设计）。
