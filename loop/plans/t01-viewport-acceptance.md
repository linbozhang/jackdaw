# T01 实施方案：视口导航与工具取消完整验收

> 任务来源：`loop/plans/roadmap-game-dev.md` P0-T01（用户裁定 2026-10-24）。
> 基线：main `6445cbf2`（工作树干净）。契约：`loop/README.md`（交互真机验收）+ `loop/qa/manual.md`。
> 本任务性质：**验证+收尾为主**（R1 cb9a6661 / R1b 6dda4526+43ba5cd8 / 专项#5 T2 178d8988 已有大改），第一要务是重建「可断言 fly 激活」的测量有效性。
> 策划预读完成于 2026-10-22，全部结论带 file:line 证据；程序实施前需逐条复核（不盲从）。

## 0. 范围

**范围内**：
- 3D 视口导航 Unity 对齐验收：右键点按不动 / 右键拖拽环视（含幅度闸生效证明）/ 中键平移 / 滚轮 / WASD+QE / F 聚焦 / 多次进出 fly 会话。
- 前置条件交叉：悬停视口 / 焦点在文本框 / 对话框开 / modal 工具激活中。
- 9 类交互模式 Esc/RMB 取消回归（专项#5 T2 修复面）+ snap_toggle 点击语义（R1b）+ 焦点切换语义（文本框聚焦时 Esc 归属）。
- 测量有效性设施：fly 激活 BRP 断言（reflect 注册小改）+ 注入活性探针与降级路径。
- DPI：本机 150% 实测 + 坐标换算校验；100% 列用户可选项。

**范围外**：2D 画布/节点图自身的导航功能（仅回归「中键行为不被 3D 改动波及」）；透视 pan 不随距离缩放（Unity Hand 语义差，已知简化，r1b-qa.md B3）；键位重绑 UI；T02+ 的 Inspector 项。

## 1. D1：fly 激活断言方案（测量有效性核心）

### 1.1 为什么必须资源化断言（历史污染复盘，证据确凿）

R1b QA（`loop/reports/r1b-qa.md`）的真机证据链有两处无效：

1. **移动注入死**：该会话 `Send-MoveRel` 不产生 winit CursorMoved（C 节自述），`r1b-qa-full3/metrics.csv` 实测 look/panX/panY/wheel/wasd **全部 0.000**（look=False、move_ok=False）——四项「环境阻塞未覆盖」，仅靠单测+用户手测兜底放行。
2. **fly 激活从未被证明**：`r1b-press.ps1` Press 段断言「按下零跳变」，但脚本从不断言 fly 已激活。若 fly_state 未置位，零跳变是「无输入」而非「过滤生效」——roadmap 明确定性为嫌疑、不得沿用旧 PASS。
3. **策划预读新发现的双重污染链**（程序需复核）：`update_active_viewport` 用裸
   `input_focus.get().is_some()` 判 `text_focused`（`src/viewport.rs:964`），而
   `src/keybind_focus.rs` 模块文档明确警告：bevy `set_initial_focus`（PostStartup）会在无焦点时把
   **PrimaryWindow 实体设为焦点**，稳态下 `is_some()` 恒真。视口 LMB 点击才 `input_focus.clear()`
   （`src/viewport_select.rs:222`）。⇒ **启动后未点过视口前，`inputs_clear=false`（viewport.rs:966）→
   `settings.enabled=false`（:975）→ fly/pan/zoom/WASD 全部哑火**。r1b-press 的 press 序列不 LMB 点击
   视口（`Assert-Foreground` 仅前台失败时才点），fly 大概率从未激活。这与用户「R1 修后按下仍坏」的
   主观报告和「时好时坏」都相容，列为重点核查清单 #1。

### 1.2 断言通道设计（三层）

| 层 | 通道 | 断言内容 | 前置小改 |
|---|---|---|---|
| L1 激活态 | BRP `world.get_resources` 读 `jackdaw::viewport::CameraFlyActive` / `CameraPanActive` | RMB 按下（悬停世界视口）后 ==true，释放后 ==false | **需补注册**，见 1.3 |
| L2 相机使能 | BRP `world.query` 读相机实体 `JackdawCameraSettings.enabled`（可选补 ReflectComponent） | 激活且 inputs_clear 时目标相机 enabled=true；文本框聚焦/对话框开时 false | 可选 |
| L3 行为 | `Get-FlyCamera`（BRP 相机 Transform，`loop/qa/brp.ps1`） | 数字级位移/转角 | 已有，零改动 |

**规约：每个「零变化」类断言（点按不动/负例）必须先过 L1 激活探针（press 后读到 true），PASS 才有效。**
仅有 L3 零变化的用例一律记 INVALID，不得记 PASS。

### 1.3 最小改动点（reflect 注册，程序侧 T1 第一步）

现状核实（本次预读逐一定位）：
- `CameraFlyActive` / `CameraPanActive`：`#[derive(Resource, Default)]`，无 Reflect（`src/viewport.rs:182-189`）→ BRP 读不到。
- `ActiveTool`：已注册（`src/active_tool.rs:13-14` + `src/gizmos.rs:165`）✅。
- `EditMode`：已注册（`src/brush/mod.rs:233-234,516`）✅。
- `JackdawCameraSettings`：`#[derive(Component)]` 无 Reflect（`crates/jackdaw_camera/src/lib.rs:51`）→ L2 需补 `Reflect + #[reflect(Component)]` + plugin `register_type`。
- `SnapSettings`（`src/snapping.rs:76` wrapper，内层 `crates/jackdaw_snap/src/lib.rs:24`）：无 Reflect——R1b QA 想断言 snap 翻转未成（r1b-qa.md C 节），`r1b-qa-snap.ps1` 留存待复用。

最小改动清单（预计 ≤6 处、全部为注册无逻辑变化）：
1. `src/viewport.rs`：`CameraFlyActive`/`CameraPanActive` 加 `Reflect` + `#[reflect(Resource)]`，`ViewportPlugin::build`（:199-200 附近）补 `app.register_type::<...>()` ×2。
2. `crates/jackdaw_camera/src/lib.rs`：`JackdawCameraSettings` 加 `Reflect + #[reflect(Component)]` + plugin 注册（L2 用，可选但建议）。
3. `src/snapping.rs` + `crates/jackdaw_snap`：SnapSettings 反射链（wrapper 是 Deref newtype，需内层字段类型一并 Reflect；程序核实成本，若超 ~30 行则此格降级为像素 diff + 用户终审，不阻塞）。
4. 顺带核实 bevy `InputFocus` 资源是否已可 `world.get_resources` 读（bevy 自带注册）；可读则文本焦点态直接断言，不可读不强求。

## 2. D2：验证矩阵

断言通道缩写：B1=BRP 资源态（L1）、B2=BRP 相机 Transform（L3）、PX=截图/像素 diff、INJ=注入类别
（C=点击/键盘【历来可用】、M=鼠标移动【时好时坏】、W=滚轮【随 M，依赖 hover 门】）。

### 2.1 视口组（每格=用例 × 前置 × 断言）

| # | 用例 | 前置 | INJ | 断言与判定 | 降级 |
|---|---|---|---|---|---|
| V1 | 右键点按不动（×10 连按，覆盖 R1b 复发场景：第 4~10 次） | 悬停世界视口；**先 LMB 点一次视口**（清 InputFocus，规避 1.1.3 污染） | C | 每轮：press 后 B1 `CameraFlyActive==true`（激活证明）；hold 500ms B2 dyaw/dpitch<0.005、pos_move<0.01；release 后 B2 回基线 | 激活断言不依赖 M，**必须真机过**；不过=🔴 |
| V1n | 负例：右键在视口外（侧栏上）按下 | 光标置于面板区（XFactor 0.05） | C+M | B1 fly==false；B2 不动 | M 死则此格降 headless 判定 hovered 逻辑+用户终审 |
| V2 | 右键拖拽环视（小位移） | 悬停视口 | M | 20×(15,0)px → B2 dyaw≈0.900（R1 锚点，feature-05-t1-qa.md §3.2）且 dpitch<0.02 | MOVE-BLOCKED → 单测锚（input_contexts 13 个）+ 用户终审 |
| V2g | 幅度闸生效证明（新） | V2 进行中注入一帧巨移 | M | 环视拖拽中 `Send-MoveRel 50000 0` 单帧 → B2 dyaw 增量 <0.005（整帧丢弃）；随后 15px 小移仍生效（闸不粘死） | 同上；headless 已有 `giant_delta_dropped_past_the_suppression_window` 等 4 测锁定 |
| V2s | 快速甩动不误伤（新，人手上限论证） | 悬停视口 | M | 连续 3 帧各 600px（合计<1000/帧）→ B2 累计转角≈3×单帧期望，无整段丢失 | 用户终审清单补「真鼠标快速甩一圈无冻结感」 |
| V3 | 中键平移 | 悬停世界视口 | C+M | panX：相机位移沿 −right（dot<−0.5·len）；panY：沿 +up；全程 B2 yaw/pitch 不变（r1b-press.ps1 §3 段断言直接复用） | MOVE-BLOCKED → 单测（pan 方向/∝speed/∝ortho）+ 终审 |
| V3n | 中键在 2D 画布/节点图/dock 标签：原行为不回归 | 各面板 | C+M | 各自原语义（2D 画布自持 pan）；不启动 3D CameraPanActive（B1==false） | 用户终审 |
| V4 | 滚轮缩放 | 悬停视口 | W | B2 位移沿 forward（dot>0.5·len），len>0.5；**前置 B1 或 hover 探针先证 hovered 门开** | hover 探针死 → 记环境阻塞，单测+终审 |
| V5 | WASD+QE（RMB 持住） | 悬停视口 | C | RMB+W 400ms：pos 前进 >0.5；RMB+E/Q：**世界 Y 分量** ±变化（新断言，其余轴≈0） | C 类必真机 |
| V6 | F 聚焦（`viewport.focus_selected`，viewport.rs:1084） | 选中 Cube（复用 r3 picker 注入） | C | B2：相机 translation 向目标位移（方向 dot>0）或 \|pos−target\| 收敛；无选中时 F 无操作（B2 不变） | C 类必真机 |
| V7 | 多次进出会话/焦点鲁棒性 | — | C | ① V1 ×10 后 V2 仍准（会话复位）；② Alt+Tab 出入（`end_fly_on_focus_loss` viewport.rs:813 触发）后 B1 复位 false、回来后 fly 可再激活；③ 最小化/还原（r1b Assert-Foreground 模式） | C 类必真机 |
| V8 | 前置×文本框聚焦 | Inspector 数字框 `input.text` 聚焦 | C | B2 相机全程不动（RMB/WASD/滚轮均哑）；Esc 语义见 2.3 | C 类必真机 |
| V9 | 前置×对话框开 | 打开任一对话框（BlocksCameraInput / no_dialog_open） | C | B2 不动；B1 若已 fly 则释放；对话框关后导航恢复 | C 类必真机 |
| V10 | 前置×modal 工具激活中 RMB | 标尺测量中，光标在视口内按 RMB | C+M | 语义断言（待裁决 R-3）：工具取消；fly 激活与否按裁决记录 B1 实际值，与裁定比对 | — |

### 2.2 工具组（9 类交互模式取消回归，基线=178d8988 修复面）

headless 基线已有：`tests/operators/modal_escape.rs` 四测（measure Esc/RMB、**全 modal operator 扫描**、Esc 长按 require_reset）+ `r2-cancel-qa.ps1` 5 用例（5/5 PASS 先例）。本组先跑这两套回归，再补真机格：

| # | 模式（激活） | Esc | RMB | 真机断言通道 | 判定 |
|---|---|---|---|---|---|
| T1 | Select/Translate/Rotate/Scale（QWER，非粘滞） | n/a | n/a | B1 `ActiveTool` 回 Select（Q） | 状态翻转 |
| T2 | Brush 编辑模式 Face/Vertex/Edge（Digit1-3） | 退层一层 | — | B1 `EditMode`：BrushEdit→Object；再 Esc 无害 | 分层退出，不连退 |
| T3 | Clip（Digit4） | 清 pending/退 | — | `EditMode` + `jackdaw/cancel` 复位 | 状态归位 |
| T4 | Knife（KeyK） | 清路径/退出 | 清路径 | `EditMode` + 截图 PX（刀路消失） | 视觉+状态 |
| T5 | 标尺（tools.measure_distance） | 取消+状态栏落 | 取消 | modal 报告（`Get-ModalReport`）before/after；截图 | modal==null |
| T6 | Draw Brush Add / Cut | Add：Esc（原死路）；Cut：Esc | Cut：RMB | modal 报告 + 场景无残留 brush（scene_tree） | 无痕 |
| T7 | Terrain stroke 中 Esc（恢复快照） | 恢复 | — | 高度图前后一致：`scene_bsn`/截图 diff（stroke 改地形后 Esc，前后图一致） | 无痕 |
| T8 | Gizmo 拖拽中 Esc | 还原拖拽前 | — | 选中实体 Transform 前后一致（B2 泛型 world.query） | 还原 |
| T9 | 顶点/边/面拖拽 + modal transform（G）中 Esc | 还原/取消 | — | 同 T8 | 还原 |
| T10 | snap_toggle 中键点击语义（43ba5cd8） | — | MMB 点击 | B1 SnapSettings 翻转一次；MMB 拖拽平移后**不**翻转 | 无反射则 PX/终审（见 1.3.3） |

### 2.3 焦点切换语义（工具组横切）

文本框聚焦时键盘归属：代码事实（预读）——`disable_keyboard_input_when_typing`（keybind_focus.rs:80-90）把
`sources.keyboard=false`，**Esc→modal.cancel 两条链都被静音**；Esc 归 UI 文本框。V8/T 组交叉断言：
「文本框聚焦 + 工具激活」时 Esc **不**取消工具（一次一层：先出文本框），出框后下一次 Esc 取消工具。
此语义待用户裁决 R-1 确认后固化为断言。

## 3. D3：注入自检与降级

会话开始必跑 **三级探针**（新脚本 `loop/qa/t01-probe.ps1`，复用 r1b-hover-diag.ps1 的 Window 查询与
r1b-press.ps1 的前台化）：

| 探针 | 步骤 | 判定 | 结论 |
|---|---|---|---|
| P1 点击类 | Assert-Foreground → Send-Esc → `jackdaw/status` 应答正常 | Esc 注入不崩、前台句柄==编辑器 | C 类可用（历史上一直可用） |
| P2 光标位置类 | Set-CursorToWindowPoint(0.35,0.5)→frames 3→BRP `world.query` 读 `bevy_window::window::Window.cursor_position`；移至 (0.65,0.5) 再读 | 两读数值均非 null 且差值≈窗口宽 30%（逻辑像素） | hover 门可开；死→HOVER-BLOCKED |
| P3 fly 端到端 | LMB 点视口一次（清 InputFocus）→ RMB down → B1 `CameraFlyActive==true` → RMB up → false | 激活翻转正确 | fly 链真机活；true 但 V2 不动 → MOVE-BLOCKED（raw delta 路径死，位置路径活，可分离） |

**分级降级**（写进 QA 报告环境节，非静默）：
- **全绿**：全矩阵真机跑（含 V2/V2g/V3 拖拽类）。
- **HOVER-BLOCKED**（P2 死）：fly/pan/zoom 全链降级——(a) 幅度闸/抑制/snap 语义用已锁单测
  （input_contexts 13 + jackdaw_camera 5 + modal_escape 4 + snap 3）作回归锚；(b) 拖拽手感、幅度闸体感
  留用户终审清单；(c) V1 激活断言仍可跑（不依赖 M——但需 P2 活才能置 hover！若 P2 死则 V1 一并降级，
  仅保留 P3 的 LMB 点击置 hover 变体：**LMB 点击本身产生 CursorMoved 吗？点击注入历来可用且
  viewport_select 的点击选择工作正常，说明点击位置可达 hover 判定**——程序核实此推理后决定 V1 去留）。
- **MOVE-BLOCKED**（P2 活 P3 后拖不动）：V1/V4/V5/V6/V7（C/W 类）照跑；V2/V3 降级同上。
- 点击类永不降级（历史稳定：r2-cancel-qa 5/5）。

**会话内动态复查**：每 5 个用例重跑 P2 一次（注入会中途失效的先例：feature-05 T1 活、R1b 死）；
探针结果与用例结果同 CSV 落 `loop/reports/t01-*/`。

## 4. D4：DPI 策略

- 本机 150%（实测主力）：脚本坐标全物理像素（input.ps1 头注释、Set-CursorToWindowPoint），引擎侧收
  逻辑像素（winit ÷ scale）。新增**换算校验**：P2 探针的两读差值与 GetWindowRect 物理宽 × 0.30 ÷ 1.5
  比对，容差 ±2 逻辑 px——锚死「物理→逻辑」链，写进探针而非单独用例。
- 引擎内 hover 数学自校验：`node_contains`（viewport.rs:845-855）混用 physical ComputedNode.size 与
  logical transform，靠 `inverse_scale_factor` 折算——预读未见错，但多 DPI 行为无测试。给
  `node_contains` 补 3 个单测（scale=1.0/1.5/2.0 下命中/不命中），锁 DPI 无关性（程序侧小改）。
- 100% 场景：**不强制改系统设置**，列为用户终审可选项（`用户可选 DPI 复核` 见 §7）。
- 复发跳变与 DPI 无关的历史结论维持（r1-disc 系列：RDP/驱动重锚 3.7e4–8.5e5px，与缩放无关）。

## 5. D5：重点核查清单（预期发现面，交程序逐条核实）

1. **🔴 候选·InputFocus 稳态假阳性**：viewport.rs:964 裸 `is_some()`（详见 §1.1.3）。核查法：headless
   启动后读 InputFocus 是否 Some(window)；真机 P3 探针（不先 LMB 点视口直接 RMB）直接复现。若成立，
   修复=改用 `KeybindFocus::is_typing()`（同文件已有依赖），并补单测「焦点为窗口实体时 fly 可激活」。
   这可能是「R1 修后按下仍坏」的真正残留根因，优先级最高。
2. **🟡 候选·幅度闸误伤快速甩动**：闸作用于**帧累积和**（input_contexts.rs:474-475 fold 后），非单事件。
   论证：60fps、800DPI、1m/s 甩=525px/帧（安全）；**1600DPI、2m/s 甩=2100px/帧（被整帧丢弃）**；低帧率
   /卡顿帧积压同险。核查法：V2s 真机 + 论证文档；若确认误伤面，方向=按事件前门控或按帧时长归一（本任务
   只记录+用户可感知项，修复裁决归用户/程序 T2）。
3. **🟡 文本框聚焦时 Esc 链全静音**（keybind_focus.rs:89 `sources.keyboard=false`）：「工具激活+打字」
   并存时 Esc 不达工具。核查法：V8×T5 交叉。语义待 R-1 裁决。
4. **🟡 对话框期间相机使能双写**：`update_active_viewport`（EditorInteractionSystems 集合）与
   `disable_camera_on_dialog`（独立系统，viewport.rs:223-228）同写 `JackdawCameraSettings.enabled`，
   未见显式互相排序——同帧竞争可能闪 enable。核查：app.schedule 顺序导出或补 `.after/.before`。
5. **⚪ CameraFlyActive 全局单例 vs 多 3D 视口**：两视口同时只能一个会话、互踩 just_released
   （viewport.rs:898-903）。Unity 亦单会话，记录即可。
6. **⚪ F 键无 modal 门**：`ViewportFocusSelectedOp` is_available 只查选中（viewport.rs:1076-1081），
   modal 拖拽中按 F 可能挪相机。核查：T9 中夹一次 F。
7. **⚪ snap_toggle 反射缺失**（§1.3.3）与 r1b-qa-snap.ps1 复用。
8. **⚪ QE 位移无真机断言先例**（V5 新增世界 Y 断言；EditorAction::CameraUp/Down 存在于
   populate_camera_nav_input:517-522，未经真机验证过）。

## 6. D6：任务拆分（1-2 个）

**T1（主任务）·断言设施+全矩阵验证+按需修复**
1. reflect 注册小改（§1.3 全部或 1/2 项，视成本）+ `node_contains` DPI 单测。
2. `loop/qa/t01-probe.ps1`（三级探针）+ `loop/qa/t01-drive.ps1`（矩阵驱动，大量复用 r1b-press.ps1 骨架
   与 r2-cancel-qa.ps1 用例）。
3. D5#1 核查（若成立即修，一行语义修复+单测）。
4. 跑全矩阵（含降级判定），出 QA 报告。
验收：V1-V10、T1-T10 按矩阵过（或按 §3 降级规则记明），四门禁绿（loop/README.md）。

**T2（收尾，若 T1 无 🔴 发现则并入 T1 合并交付）**
1. T1 遗留 🟡/⚪ 修复（如 D5#2/#4 的最小修复或论证留档）。
2. 幅度闸人手上限论证文档化（常量注释补论证或引用本方案）。
3. `loop/qa/manual.md` 增补 T01 章节（探针规约、B1 断言模式、降级标记法）。
4. 终验 + 用户终审清单回收。

## 7. QA 验收清单

**QA 自动门（每任务必跑）**：fmt / clippy / `--lib` 单测（loop/README.md 表）；本任务追加
`cargo test --test operators modal_escape`（工具组回归锚）。

**真机矩阵 PASS 标准**：
- 所有非降级格绿；降级格按 §3 规则记 HOVER/MOVE-BLOCKED 并附单测锚，**不得记 PASS**；
- 每个「零变化」格均附 L1 激活证明（B1 快照存 reports）；
- 探针 CSV 完整（P1-P3 + 每 5 用例复查行）。

**用户终审 30 秒清单**（在 r1b-qa.md E 节基础上增补，agent 陪同一次性过）：
1. 冷启动编辑器，**不点任何地方**，直接右键按住拖：视角应转动（D5#1 修复的体感验证）。
2. 3D 视口连点右键 5 次：纹丝不动。
3. 右键拖一圈/快速甩两下：跟手、无跳变、无冻结感（D5#2 体感）。
4. 中键左右/上下拖：场景跟手平移；静止中键点击：snap 翻转一次。
5. 滚轮 + 右键 W/Q/E 两秒：缩放/位移正常。
6. 选中 Cube 按 F：相机对准；标尺测量中按 Esc、再按 RMB：都能退出。
7. 点进 Inspector 数字框打字，此时按 Esc/WASD：视口不动、先退出输入框。
8.（可选 DPI 复核）系统缩放切 100% 后重复 2/3：不跳视角。

## 8. 风险

| 风险 | 概率 | 缓解 |
|---|---|---|
| 注入全程死（P2/P3 双死） | 中（有先例） | §3 分级降级已有完整路径；V1 有效性依赖点击可达 hover 的推理，程序先核实 |
| reflect 注册引发序列化/TypeTree 类边界问题 | 低 | 照 ActiveTool 现成模式（active_tool.rs 注释：非场景序列化，仅 BRP）；不进 TypeTree 的 Resource 无 prefab 面 |
| SnapSettings 反射链成本超预期 | 中 | 已设降级（PX+终审），不阻塞主线 |
| D5#1 修复改变启动期焦点行为，波及其它快捷键 | 低 | 修复仅收紧 `text_focused` 误判（窗口实体≠打字），KeybindFocus 同语义已在 bookmark 路径验证；跑全量单测+integration |
| RDP 环境跳变复发与注入干扰混淆 | 中 | V2g 巨移注入是主动注能，与被动复发区分靠 B1 激活态 + 单帧性判别（r1-disc 方法论沿用） |
| 矩阵真机时长超单会话稳定期 | 中 | 分段跑（V1-V5 / V6-V10 / T 组三段），每段独立探针开场 |

## 9. 需用户裁决项

| # | 问题 | 选项与建议 |
|---|---|---|
| R-1 | 文本框聚焦 + modal 工具激活时，Esc 给谁？ | 建议 **A：维持一次一层（先出文本框，再按 Esc 取消工具）**——与专项#5 D8「不连退多层」一致，代码现状即此；B：Esc 直接取消工具并保留文本焦点（需改静音逻辑，不建议） |
| R-2 | 100% DPI 场景是否纳入本轮必测？ | 建议 **A：不纳入**（150% 实测+换算校验+单测锚定，100% 列用户可选）；B：纳入（需用户配合改系统设置一次） |
| R-3 | modal 工具激活中、光标在视口内按 RMB：取消工具的同时本次按住是否直接进入环视？ | 建议 **A：允许**（现行为推演：取消后 inputs_clear 恢复、fly_state 已置位，按住即环视；与 Unity 体感一致）；B：本次 RMB 仅取消不环视（需加一次性抑制）。裁决仅固化断言语义，非必改项 |
| R-4 | D5#2（幅度闸误伤高 DPI 快甩）若 V2s/论证确认存在：本轮修还是挂账？ | 建议 **A：挂账 T2 或下任务**（本任务以验收为主，闸改动敏感需单独评审）；B：本轮一并修 |
