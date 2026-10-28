# T09-T1 QA 验收报告：游戏动作系统核心+模板+混用补齐（只验不修）

> 验收对象：分支 `loop/t09-input`（自 main 9a874945），提交 **f06b63ed** `Add the game-side input action system with editable bindings`（6 文件 +778/−5，与程序报告一致）。工作区核对：与提交态一致。
> 环境说明：机器劣化第 3 次冻结期延续——本轮以 headless 为主（任务书口径），未尝试真机（T0 补验即被同环境阻断在先）。
> 证据：`loop/t09t1_*`（程序归档五件+实编 check）、QA 亲跑输出（game_input 6/keybind_focus 2/runtime 37/scaffold 82/guards 204）。

## 一、门禁——干净

归档全文复核：fmt 空=clean；clippy 0 error 行；runtime **37**/0（+6 game_input）；主 crate lib **1175**/0（+1 keybind_focus）；scaffold **82**/0（归档数字由 QA 亲跑印证：runtime 37 passed 0.11s、scaffold 82 passed 2.13s）；guards **204**/0（60.03s，无 FAILED/panicked）。QA 亲跑 guards 全量 **204 passed / 0 failed**（51.63s）。✅

## 二、红→绿 8 用例——亲跑全绿+断言质量审

**QA 亲跑 8/8 绿**（game_input 6/6 0.02s+keybind_focus 2/2 0.02s）。重点审：

- **改绑红绿**（`rebinding_moves_the_action_with_the_binding`）：config 把 Move 绑定改为 ArrowUp → **先断 W 不再驱动**（旧绑定失效）→ **再断 ArrowUp 驱动**——双向钉死「绑定可编辑且生效」，断言质量好，机制层实证成立。✅
- **并集合并 ×2**（Y36 病反证）：
  - `a_file_merges_over_the_defaults_as_a_union`（纯函数层）：**len==defaults.len()（五动作全在=Y36 病的直接反证）**+file kind wins（Button 显式覆盖默认 Axis2D，kind 覆盖被钉住）+omitted Jump 保留默认绑定（精确到 `Key(Space)` 变体 match）+dup 折叠 count==1——四点断言完备。✅
  - `a_partial_config_still_evaluates_the_full_action_set`（活资源层）：只配 Jump(J) → just_pressed("Jump")+Move/Pause 存在——与纯函数用例互补，覆盖 ConfigPlugin 晚到/活资源路径（每帧重算 union）。✅
- **红半形态**：存在性红（无 plugin 时 `GameActions` 资源不存在——全新功能的机制不存在红，同 T1 ConfigLoader 先例）+**事件注入**（`press_key` 走 `write_message(KeyboardInput)` 真事件流，注释写明「直改 ButtonInput 会在求值前被引擎 clear」——与 PIE 转发共享同一路径，注入等价性在机制层成立）。**形态可接受**。✅

## 三、代码 review 六项——无新 🔴/🟡，三项 ⚪ 观察

1. **求值时序**：`PreUpdate, (apply_deadzones, evaluate_actions).chain().after(bevy::input::InputSystems)`——引擎 ButtonInput 重建/鼠标累计之后、死区先于求值（chain）；`Option<Res<...>>` 参数使缺 Gilrs/鼠标资源的游戏不 panic。keyboard 每帧 clear 重建的适配（事件注入而非直改）在实现与测试双侧一致。✅
2. **并集合并语义**：`merge_actions` 文件先（首条保留治手改分叉）+默认补缺；同名整条替换（kind 用文件值）；每帧重算使 ConfigPlugin 晚到立即生效（活资源用例钉住）。✅
3. **死区写入 GamepadSettings**：Query 遍历**每台**已连接手柄写入 per-axis `AxisSettings::new(-1.0, -d, d, 1.0, 0.01)`——**QA 对照 c9c397b bevy 树核实五参序**（livezone_lower/deadzone_lower/deadzone_upper/livezone_upper/threshold）正确；每帧重算覆盖热插拔（新手柄下一帧即生效）。多手柄同表写入与「任意手柄」语义一致。✅
4. **I3 双维压制**：`sources.keyboard = keyboard_free`（三条件）+`sources.mouse = !capture.active`（**鼠标只看 capture**——chord recording/numeric entry 不占鼠标，`keyboard_spoken_for_leaves_the_mouse_free` 钉住）；UI picking 走事件流不受 InputSources 影响（机制性确认+注释写明，事件级断言留 T3 格 9 mouse 腿）。✅
5. **bevy main API 适配 4 条——QA 对照本仓 bevy 树（c9c397b checkout）逐条核实全部属实**：`GamepadButton` 单 enum（gamepad.rs:581，无 (gamepad,button) 构造对）；`GamepadAxis::LeftStickX`（:677）；`GamepadSettings` 带 `reflect(Component)`（:744，per-device 组件）；`keyboard_input_system` clear 重建（测试事件注入自证）。✅
6. **W27 病结构免疫**：`GameInputBinding` 字段全部为 bevy 原生类型（KeyCode/MouseButton/GamepadButton/GamepadAxis）经 Reflect+Serde 直序列化，无 display-name 往返——免疫声明成立。✅

**⚪ 观察三项（不阻塞）**：①实编 probe 工程 `H:\workspace_AI\t09t1-probe\input-game` 未清理（T09 收尾处置）；②`evaluate_actions` 每帧重算 `merge_actions`（每帧 clone 默认表+Vec 分配）——五动作小表可忽略，动作表若长到几十条可考虑缓存+变更检测（记 open-challenges 备查）；③`GamepadAxis` 绑定对 Button 动作按 0.5 阈值直通（未接 `GamepadSettings.button_settings` 的阈值链）——当前无手柄 Button 动作默认绑定（默认表 Button 均为按键/手柄按钮），语义未错但阈值口径与轴死区不同源，留 backlog 注释级观察。

## 四、模板与混用基线

- **模板三行注册+plugin 行**（diff 核实：`init_asset`+`register_asset_reflect`+`ConfigPlugin::<GameInputConfig>::new("input-actions.bsn")`+`InputActionsPlugin`，与 GameConfig 并排）；`PlayerMarker` 于 (-2,0.5,0)+`move_player_by_actions`（Move Axis2D→XZ 平移/Look Delta2D→yaw/Jump/Interact/Pause just_pressed 日志）。**T3 矩阵断言可行性预核：可行**——PlayerMarker 位移走 Transform.x/z，`scene_snapshot` 两帧差法（T2 已验证通道）可直接断言；按键经 PIE `input.key`/Live capture 注入。✅
- doc「# Input actions」节含捕获模型（点击捕获/Shift+Esc 释放/**plain Esc 转发游戏**=Pause 绑 Escape 的正确性依据，I5）——与 LiveInputCapture 既有转发语义（零改动复用）一致。✅
- **混用基线落档质量**（供 T2/T3 验收的现状梳理）：三维度（键盘=既有机制+数据面 PresetInput vs GameInputConfig 零交集；鼠标=本任务双维门；手柄=编辑器零消费）+PIE 转发链零改动（本任务唯一编辑器侧动点=I3 一行，diff 核实属实）——落档完整、无与代码矛盾的断言。✅

## 五、实编替代证据+真机腿降级口径裁定

- **实编证据核实**：`loop/t09t1_scaffold_check.log` 完整 cargo check——`Checking input-game v0.1.0`→**`Finished dev profile in 1m 19s`**（全依赖含新增 bevy_gilrs feature 编译通过，InputActionsPlugin/ConfigPlugin/GameActions/PlayerMarker 全链）。✅
- **真机腿留 T2 的降级口径——裁定成立**。理由：T1 验收重心在机制层，headless 8 用例已覆盖求值/改绑/并集/死区/鼠标/I3 六面；PIE 转发链零改动+注入等价性（事件注入用例与 PIE 转发共享 ButtonInput 重建路径）在机制层覆盖了「编辑器输入到游戏动作」的到达性；真机的净增量价值（capture 生命周期 UI 面/手柄实测/行为断言）本就规划在 T2/T3。**T2 需真机一次跑齐的清单（QA 补列，程序报告未列全）**：①改绑三态链（编辑器改 input-actions.bsn→Play 生效→导出包生效）；②capture 生命周期（点击捕获→游戏收键→Shift+Esc 释放→编辑器键位恢复+plain Esc 到游戏 Pause）；③手柄 PIE 可达性调查（gilrs 进程内直读 vs PIE 子进程——方案遗留问题）；④PlayerMarker 行为断言（W 注入→scene_snapshot 两帧 x/z 差）；⑤I3 事件级抽验（capture 中点 Stop 面板仍响应）。
- **T0 两项 T08 补验仍挂起**（环境事件，程序偏差 5 记档一致）——不并入本任务。

## 六、偏差 4 条裁定

| # | 偏差 | 裁定 |
|---|---|---|
| 1 | 真机腿整体留 T2 | **接受**（§五论证+T2 清单补全） |
| 2 | bevy main gamepad API 出入（单 enum=任意手柄语义；per-gamepad 区分 backlog） | **接受**（QA 对照 bevy 树核实 4 条属实；「任意手柄」与引擎 ButtonInput 键形态自洽） |
| 3 | I3 UI picking 机制性确认（事件级留 T3 格 9） | **接受** |
| 4 | `GameInputConfig` 手动 Default+`#[reflect(Default)]` | **接受**（derive 冲突系语言限制；defaults() 五动作表即 Default，schema 卡片可用） |

## 七、结论

8 用例亲跑绿（改绑红绿与并集合并×2 断言质量审过）；review 六项无新 🔴/🟡（API 4 条 QA 对照 bevy 树逐条核实、AxisSettings 五参序确认）；模板与混用基线核实；实编证据成立；真机腿降级口径成立（T2 真机清单已补列）；门禁归档+亲跑干净；偏差 4 条接受。

VERDICT: PASS（建议主控 --no-ff 合入；T2 前置：真机清单 §五 五项一次跑齐+T08 两项补验仍挂起待环境；T09 收尾处置 t09t1-probe 实编工程）
