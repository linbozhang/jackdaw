# T01 任务 2（收尾）报告：遗留格子补验 + 幅度闸论证文档化 + book 增补 + 终验材料

任务：`loop/plans/t01-viewport-acceptance.md` D6-T2。分支 `loop/t01-viewport`（基于 main 9116d2cb，T1 已合入），提交 **85afcc1e**（3 book 文件 +70/-1）。
补验会话：`loop/reports/t01-t2-supplement/s1..s6b/`（metrics.csv + console.log），脚本 `loop/qa/t2-supplement*.ps1`、`t2-diag.ps1`（均不入库）。
代码 diff：**零 Rust 改动**（补验未发现需要修的真缺陷）；仅 book 三文件。

## 0. 结论

补验 5 格中 **3 格升级为真机 PASS**（T3/T4/T9-modalG）+ T9 face 拖拽提交/undo 链真机 PASS；
V8 与 T10 的剩余半格在本环境**通道不可达**，如实记 BLOCKED 并按 plan §3 规则锚定（单测+代码+终审兜底）——比 T1 多拿到的是「为什么不可达」的完整通道诊断。
附带 2 条新观察（Esc 双动作语义、工具栏磁铁在 2560 宽屏被裁剪）。R-4 幅度闸论证已按裁定 A 文档化进 book。

## 1. 补验格子结果

| 格 | 结果 | 证据 |
|---|---|---|
| **T3 Clip（Digit4）** | **PASS**（s1 首过，s3 复证） | 合成通道（BRP `input.pointer`/`input.key`）：视口点击选中 brush → Digit4 → `EditMode=BrushEdit(Clip)`；Esc → Object（`s1/s3: T3` 行）。进入前置实证=「选中含 brush + InputFocus 已清 + 3D 前台」，与 `can_change_edit_mode`（edit_mode_ops.rs:107-125）逐条对上 |
| **T4 Knife（KeyK）** | **PASS**（s1 首过，s3 复证） | KeyK → Knife；视口点击放上刀路点后 Esc#1 → **仍在 Knife**（Esc#1 归 `handle_knife_mode` 清路径，knife_mode.rs:467）；Esc#2 → Object。分层退出语义与矩阵一致 |
| **T9 modal-G** | **PASS**（s1/s3） | G 按下不启动任何 modal（modal null→null）。**T1 的 DEGRADED 前提过时**：modal transform 系统被设计性禁用（modal_transform.rs:81-84 注释：G/R/S 走 TrenchBroom 弦键；G 无绑定、Alt+G=transform.reset_position，transform_ops.rs:44-47）。矩阵该半格=按设计不适用，非缺陷 |
| **T9 face 拖拽 Esc** | **PARTIAL** | 提交链 PASS（s4）：LMB 于 Face 模式点 brush 面 → `brush.face.drag` modal Running → +300px 拖拽中几何**实时变化** → 释放提交 → `history.undo` 完整还原。Esc 中途还原半格 BLOCKED：s6b 会话 modal 可启动（Digit1 预热后）但 pending→active 提升拒绝（+600px 仍零突变，会话间不稳定，BrushDragState 无反射无法外读定位）。Esc 取消链由通用 modal cancel（T5/T6/T8 已真机证）+ `cancel_face_drag→restore_captures`（brush_drag_ops.rs:195,1397）锚定，终审兜底 |
| **T8 补充（Esc 双动作发现）** | 见 §3 发现 1 | 解释 T1 v7 T3/T4 DEGRADED 根因 |
| **V8 文本框聚焦** | **BLOCKED**（通道不可达，非产品缺陷判定） | 四轮通道尝试（s1 EditableText 反射查询失败×3 路径；s2 右面板 Text 行点击聚焦了非文本实体；s4/s6b 层级 Filter 输入框三种点击变体 click/+80px/dblclick 全部 focus=null；Inspector 数字框所在右面板在窗口内被布局溢出裁剪，物理坐标 > 窗宽）。语义锚：D5#1 修复已真机证 is_typing 门（T1 coldstart B 判据）+ 单测 `a_focused_text_edit_still_disables_the_camera`（viewport.rs）+ `disable_keyboard_input_when_typing`（keybind_focus.rs）+ R-1 一次一层由上游 text_input Escape=blur+传播（bevy_ui_widgets/text_input.rs:241-251）与本仓静音门共同保证。终审第 7 条兜底 |
| **T10 snap 中键语义** | **PARTIAL** | **拖拽半格 PASS**（s5/s6b 双会话一致）：MMB 按住 + 真实位移拖拽 → `CameraPanActive=true`、fly=false、相机位移 6.00（中键=平移，不进 fly，即「拖拽不翻转 snap」的行程侧语义）。静止点击翻转半格通道全不可达：SnapSettings 反射（T1 已裁定超预算）；工具栏磁铁 ButtonVariant 查询 0 实体（bevy_feathers 路径注册但无实体携带）、BackgroundColor 校准 0 变化；**磁铁按钮本身在 2560px 宽屏最大化下被工具栏溢出裁剪**（物理 x≈2600-2900 > 窗宽 2576，s3/s4 实测）；行为探针（亚格 face 拖拽作 snap 读出）依赖的拖拽提升同 T9 不稳。终审第 4 条兜底 |

矩阵终态（T1+T2 合并口径）：V1-V7/V9/V10 同 T1；T1/T2/T5/T6/T8 PASS；**T3/T4 PASS（本轮升级）**；T9 = modal-G 不适用（设计）+ face-commit/undo PASS + face-Esc 锚定；T7 维持锚定；T10 = 平移半格 PASS + 点击翻转半格终审；V8 = BLOCKED-通道 + 锚链 + 终审。INVALID/FAIL 仍为 0。

## 2. 会话与环境方法论（供后续 QA 复用）

- **注入通道分级（本 agent 会话实测）**：BRP 合成通道（input.pointer/key/text）全活；OS 通道（SendInput/SetCursorPos）**依赖前台权**——AttachThreadInput+SetForegroundWindow 可能失败，兜底=标题栏真实点击抢前台（s3 起生效，fg=True 后 OS MMB 拖拽可用）。
- **真光标驻留**：把真实光标 SetCursorPos 停在视口上，合成 CursorMoved 的 hover/`ViewportCursor` 才稳定存活（face drag/pan 都读 `Window.cursor_position` 派生值；BRP 直读该字段恒 null 是读数侧死，功能侧活——与 T1 P2 结论一致）。
- **窗口必须最大化**：默认 1280x720 下右面板/工具栏右簇物理坐标超出窗宽被裁剪（s2/s4 实测 maxX=1780/2897）。
- **face 拖拽**：需先有一次编辑模式交互预热（冷启动首按 face pick 不中，Digit1→Esc→Digit3 后 modal 可启动）；拖距需 >~300px（+100px 零变化、+300px 起效，疑 snap 量化，s4 三段探针）。提升（pending→active）跨会话不稳定（s4 成功 s6b 拒绝），根因未定位（状态无反射）。
- **不要与 cargo 门并发跑真机会话**（s6 教训：xtask fast 抢资源令编辑器 BRP 超时）。

## 3. 新发现（无 🔴/🟡，2×⚪）

| # | 级别 | 发现 | 处置 |
|---|---|---|---|
| 1 | ⚪ | **Esc 双动作**：从 BrushEdit 按 Esc = 退出编辑模式 + **同时取消选择**（`SelectionClearOp` 绑定 Escape 且 `escape_is_free`（viewport_select.rs:44-99）在无 modal/手势时放行）。后果：Esc 后再按 1/2/3/4/K 需先点回实体才生效。这也正是 T1 v7 会话 T3/T4「进入失败」的根因（T2 的 Esc 已取消选择）。与「Esc=通用退避」设计自洽，非缺陷；已在用户文档「一次一层」段落如实描述（见 §4） | 记录+文档；若用户希望「Esc 只退模式不清选择」，需单独裁决改绑定 |
| 2 | ⚪ | **工具栏右簇溢出**：2560px 物理宽屏最大化下，grid 步进/磁铁按钮物理坐标 ~2600-2900 超出窗口（s3/s4 UI 查询实测）——用户可能看不到磁铁按钮 | 记录待用户在真屏确认（终审第 9 条）；若复现属 layout 问题另立任务 |

## 4. 文档改动（本次 commit 全部内容）

1. `book/src/developer-guide/open-challenges.md` 新增 **Pointer-delta gate headroom** 一节（R-4 裁定 A 挂账的论证文档化）：1000px/帧阈值的作用点（帧累积和、整帧丢弃非 clamp）、两端校准数字（常规甩动 171px/帧 5.8x 余量、激进 427px/帧 2.3x、V2g/V2s 双向实测锚 600 放行/50000 丢弃）、两个真实误伤角（1600DPI 2m/s ~2100px/帧、200ms 卡顿积压 ~1300px/帧）、候选修法（事件前门控或 ∝帧时长；clamp 不可行会回退点按修复）——供后续调阈值者参考。
2. `book/src/user-guide/viewport-navigation.md` 增补两节：**中键平移**（含「静止中键点击=翻转 snap，行程区分点击与平移」语义）；**打字时相机静音**（文本框聚焦时 WASD/滚轮/右键环视全哑；Esc 一次一层——先出文本框、下一次 Esc 才取消工具）。
3. `book/src/user-guide/keyboard-shortcuts.md`：Brush Editing 表补 `K | Knife mode` 行（原文档缺该键位）；Esc 行如实标注「退出 brush edit 的同时取消选择，重新按 1-4 前需先点回实体」（发现 1 的用户面文档）。

## 5. 门禁

| 门 | 结果 | 日志 |
|---|---|---|
| `cargo fmt --all -- --check` | **PASS**（exit 0） | `gate-fmt-t01t2.log`（空） |
| `cargo clippy --workspace -- -D warnings`（权威口径） | **PASS**（exit 0，1m20s） | `gate-clippy-t01t2.log` |
| `cargo xtask fast` | **PASS**：2851 passed / 2 skipped（49.5s） | `gate-xtask-fast-t01t2.log` |
| `cargo xtask integration` | **PASS**：5001 passed / 3 skipped（397.8s） | `gate-xtask-integration-t01t2.log` |

（diff 仅 book/*.md 两个文件，零 Rust 面；四门跑在 9116d2cb 树 + book 改动之上。）

## 6. 用户终审 30 秒清单（T01 全收口，agent 陪同一次过）

1. 冷启动编辑器，**不点任何地方**，直接右键按住拖：视角应转动（T1 D5#1 修复体感）。
2. 3D 视口连点右键 5 次：纹丝不动。
3. 右键拖一圈/快速甩两下：跟手、无跳变、无冻结感（幅度闸体感）。
4. 中键左右/上下拖：跟手平移；**静止中键点击：snap 翻转一次**（T10 点击半格的兜底；观察磁铁/状态栏）。
5. 滚轮 + 右键 W/Q/E 两秒：缩放/前进/升/降正常。
6. 选中 Cube 按 F 对准；标尺测量中 Esc、再 RMB：都能退出。
7. 点进 Inspector 数字框或层级 Filter 框打字，按 Esc/WASD：视口不动、**第一次 Esc 只退出输入框**，第二次 Esc 才回 Select/取消工具（V8/R-1 兜底）。
8. 按 4 进 Clip、按 K 进 Knife，Esc 退出后再按 4：**需先点一下 Cube** 才再进（Esc 双动作语义，发现 1 的体感确认）。
9. （可选）确认工具栏最右侧的磁铁/网格步进按钮是否可见（发现 2 溢出复现确认）。
10. （可选 DPI）系统缩放 100% 重复 2/3：不跳视角。

## 7. 遗留

1. **T9 face-Esc 中途还原**、**T10 静止中键翻转**、**V8 文本聚焦**三处 live 断言通道在本环境不可达/不稳定（§1 证据链）；语义由单测+代码+终审兜底。若后续任务给 `BrushDragState`/`SnapSettings` 补反射（各 ~10 行注册面），三格可机读断言。
2. face 拖拽 pending→active 提升的会话间不稳定（s4 过 / s6b 拒绝）未定位——状态无反射，建议下次触碰 brush_drag_ops 时加日志核实（不排除与预热/snap 状态交互）。
3. 发现 2（工具栏溢出）待用户真屏确认后决定是否立项。
4. R-4 幅度闸按裁定 A 挂账维持（本轮仅文档化）；候选修法（事件前门控 / ∝帧时长）留待专门评审。
