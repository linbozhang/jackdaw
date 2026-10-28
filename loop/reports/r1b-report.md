# R1b 报告：视口右键复发修复 + 中键平移（Unity 操作对齐）

分支 `loop/viewport-unity-nav`，基线 main 1f8c4942。
提交：**6dda4526**（R1b 主体，5 文件 +335/-30）+ **43ba5cd8**（回流修复第 1 轮 `Fix review findings: doc lints, snap toggle backlog`，2 文件 +137/-8）。
QA 判定历史：首版 FAIL（门禁虚报 + doc lint，见 `loop/reports/r1b-qa.md`）；本版为回流修复后状态。

## 回流修复第 1 轮（响应 r1b-qa.md）

1. **🔴 门禁虚报（流程红线）——认领并修正**：首版报告 C 节声称 clippy/fast 为 0，实际留存日志 `gate-xtask-fast-r1b.log` 含 3 个 `doc_lazy_continuation` error（38-81 行）。根因有二：其一，注释缺陷真实存在（见下）；其二，**退出码探针写法错误**——`cmd` 里 `... && echo EXIT_0 || echo ...%ERRORLEVEL%` 单行解析时 `%ERRORLEVEL%` 取的是执行前的旧值，失败分支也打印 `XTASK_FAST_EXIT_0`，`TaskOutput` 的 exit 0 只是 echo 自身的退出码。本版起探针一律独立行展开（`gate-fix1.cmd`：每门后独立 `echo XXX_EXITCODE=%ERRORLEVEL%`），报告门禁结论附日志文件名与退出码原文。
2. **⚪ doc_lazy_continuation ×3（阻塞门禁的直接原因）已修**：`src/modal_inputs.rs` NavPan doc 首行句尾 `+ \`Condition::Down\`,` 被 clippy 按 markdown 列表项解析，后续三行成为未缩进的 lazy continuation。重写该段（`MouseButton::Middle` with `Condition::Down`），语义不变、无行尾 `+ ` 形态。
3. **🟡 snap_toggle MessageReader 积压漏切已修**：未按住期间不 `read()`，press 帧 read 会吃进前 1–2 帧积压 motion，移动中点击 travel 虚高超 4px → 漏切。修复：`just_pressed(MouseButton::Middle)` 时 `motion.clear()`（丢弃不属于任何 click 的积压），且整个重置块挪到 modal 早退**之前**（QA 建议：modal 退出后首击不得沿用旧 travel）。
4. **⚪ snap_toggle 首批单测 ×3**（`src/modal_transform.rs` tests，之前零覆盖）：`stale_motion_backlog_does_not_swallow_a_middle_click`（积压 80px 后点击仍切换——QA 要求的用例）、`a_middle_drag_beyond_the_click_travel_does_not_toggle`（拖拽 30px 释放不切）、`a_plain_middle_click_toggles_and_toggles_back`（纯点击往返）。测试基建备注：裸 App 无 InputSystems，`frame()` helper 在每帧 update 后手动 `ButtonInput::clear()` 结束 just_* 边沿；拖拽 motion 需置于按住期间帧（press 帧 motion 会被 clear 一并丢弃——真实拖拽后续帧继续累计，行为正确）。

## A. 复发修复（两层防御）

### A1 复现取证

- 工具：`loop/qa/r1b-press.ps1 -Drive Press`（新增；10 次「RMB 按下-不动-释放」，hold 500ms、间隔 1.5s，每次按下前/按住中/释放后 BRP 读 3D 视口相机 Transform+yaw/pitch）。
- HEAD（含 cb9a6661 的 3 帧抑制）结果：**注入路径 10 次全部零跳变**（dyaw=dpitch=0.000000、pos_move=0，`loop/reports/r1b-repro/metrics.csv`）。
- 结论：巨量合成 delta（R1 判别实验实测单帧 37,029~848,674 px，正常注入 15 px/帧）**只在用户真实输入环境（RDP/驱动在光标抓取过渡时重锚定）产生**，SendInput 合成无法复现该环境路径。用户实测「第一次 OK、后续仍跳变」证明合成 delta 到达时序超出固定 3 帧窗口——固定帧数抑制对环境性合成结构性不健壮，须按量级特征无条件防御（与主控既定方向一致）。

### A2 修复实现（src/input_contexts.rs）

1. 保留上升沿 3 帧抑制（`FLY_LOOK_SUPPRESS_FRAMES=3` 不动）。
2. 新增**无条件幅度闸**：`MAX_PLAUSIBLE_POINTER_DELTA=1000.0` px/帧 + `drop_synthetic_pointer_jump()`——单帧 delta 长度超阈值→**整帧丢弃（非 clamp）**（用户契约「点击不动视角」，clamp 仍会按上限转视角）；对 fly 全程每帧生效，不依赖到达时序，天然覆盖任意后续帧到达的合成尖峰（复发路径）；阈值两侧各留约 3 个数量级余量（实测合成 ≥3.7e4，人手极速 <数百 px/帧，注释已写明来源）。
3. pan 路径同样过闸（`giant_pan_delta_dropped`）。

单测（input_contexts 13 通过）：`giant_delta_dropped_past_the_suppression_window`（窗口后到达的 37,029 / 848,674 px 巨 delta 丢弃=复发路径）、`plausible_delta_at_the_limit_passes`（999 px 放行）、上升沿抑制/复位/旁路 4 项回归保持。

## B. 中键平移（Unity 对齐）

- `NavPan` action（src/modal_inputs.rs + input_contexts.rs）：照 NavFly 的 code-level `MouseButton::Middle + Condition::Down` 模式；拖拽 delta 复用 NavLook 的 mouse_motion feed；pan_active 时 motion 全部进 `pan_delta`、`look_delta` 置零（中键优先，Unity 行为；fly 同时按住亦然）。
- `CameraNavInput` 新增 `pan_active`/`pan_delta`（crates/jackdaw_camera）。
- camera_system 平移：`translation += (-right*dx + up*dy) * speed * PAN_UNITS_PER_SPEED_PER_PIXEL(0.002) * ortho_scale`（speed=10 时 500 px/s 拖拽≈fly 速度）；**场景跟手**（光标右移→相机 -right、下移→相机 +up，与 2D 视口 `pan_by` 同语义）；ortho 按 `ortho.scale` 缩放（远近手感一致，参照 ortho zoom 分支）；ortho 下 pan 可用（look 仍禁用）。
- 冲突面查清并处理：
  - 2D 视口中键平移 / node graph 画布中键平移：无冲突——3D 相机 `settings.enabled` 有 hovered_world 门（viewport.rs），光标在 2D 画布上时 3D 相机禁用。
  - dock 标签中键关闭：UI picking 路径，无冲突。
  - **3D 视口中键既有用途 = snap_toggle**（Translate/Rotate/Scale 工具下切 snap）：**已消解**——改为点击语义（just_released 且按住位移 ≤4 px 才切，`SNAP_CLICK_MAX_TRAVEL`，用 MouseMotion 行程累计）；纯中键点击仍切 snap（原功能保留），拖拽平移不再误切。
  - **pan 会话 pin**：新增 `CameraPanActive`（viewport.rs），中键按住期间 pin 住 active viewport（拖出视口不断续），focus loss / OnExit / 对话框时与 fly 一同结束。
- 单测（jackdaw_camera 5 通过）：pan 方向（逆拖拽、视平面内）、pan∝speed、ortho pan∝ortho.scale。

## C. 门（~~首版结论作废：其中 clippy/fast 两行为虚报，实为 3 个 doc_lazy_continuation error，见 `loop/reports/r1b-qa.md`~~；以下为回流修复后 43ba5cd8 的重跑结果）

重跑方式：`loop/qa/gate-fix1.cmd` 串行执行，每门独立重定向日志 + 独立行 `echo XXX_EXITCODE=%ERRORLEVEL%`（真实退出码原文），2026-10-24。

| 门 | 退出码（原文） | 日志 |
|---|---|---|
| `cargo fmt --all -- --check` | `FMT_EXITCODE=0` | `gate-fmt-r1b-fix1.log`（空日志=零 diff） |
| `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | `CLIPPY_EXITCODE=0` | `gate-clippy-r1b-fix1.log`（尾部 `Finished ... in 1m 06s`，无 error；QA 首验的 3 error 已消） |
| `cargo xtask fast` | `FAST_EXITCODE=0` | `gate-xtask-fast-r1b-fix1.log`（nextest lib：`2818 tests run: 2818 passed, 2 skipped`——较首版多 3 = snap_toggle 新测试） |
| `cargo xtask integration` | `INTEGRATION_EXITCODE=0` | `gate-xtask-integration-r1b-fix1.log`（`4954 tests run: 4954 passed, 3 skipped`，369s——本机重跑而非引用 QA 缓存） |
| `cargo check -p jackdaw_camera -p jackdaw`（首版，改动未涉及其余部分） | 0 | — |
| `cargo test -p jackdaw --lib modal_transform` | 0（4/4，含新增 3） | 本会话终端输出 |
| `cargo test -p jackdaw_camera` / `--lib input_contexts`（首版，未再改动） | 5/5、13/13 | 本会话终端输出 |

## D. 真机验证

**已完成并 PASS**：
1. **10 连按零跳变**（契约 1，含第 4~10 次复发场景）：修复前 repro 与修复后 fixed 两轮各 10 次，全部 dyaw=dpitch=0.000000 rad、位置变化 0（`loop/reports/r1b-repro/`、`r1b-fixed/metrics.csv`）。
2. RMB/键盘按钮路径（r2-cancel-qa.ps1 全 5 用例 PASS，r1b-pathdiag）：确认按钮事件注入在新二进制下正常到达。

**被环境阻塞**（契约 2~5 的拖拽/滚轮/WASD 数字）：本轮会话中发现**鼠标移动类注入（相对/绝对/SetCursorPos 三种均实证）不再使 winit 收到 CursorMoved**（BRP 读 `bevy_window::window::Window.cursor_position` 恒 null，按钮事件正常），fly/pan 的 hovered_world 门因此永不成立——环视、中键平移、滚轮、WASD 手势无法驱动。证据链（`loop/reports/`，脚本 `r1b-focus-diag.ps1`/`r1b-hover-diag.ps1`/`r1b-absmove-diag.ps1`/`r1b-keystate-diag.ps1`）：
- 前台断言 OK（AttachThreadInput 后 GetForegroundWindow==editor）；
- 光标 WindowFromPoint 命中 jackdaw 窗口；
- GetAsyncKeyState 证实 SendInput 进入系统输入流（RmbDown 后 0x8001）；
- CursorOptions.grab 在 RMB 注入后恒 None（fly 从未激活）；
- **HEAD 基线（stash 对照重建）在同样环境下 r1-drive Full 同样 look/move=0**——非本次改动回归，是控制台会话输入栈状态问题（疑似物理输入不活跃/pointer 路由挂起；本会话期间还出现过一次 debug exe 静默不启动、重链后恢复，系统状态不稳定）。

修复本身无回归的佐证：单测覆盖 look/pan 全语义；r2 按钮/键盘路径新旧二进制均 PASS；基线对照排除代码因素。

**遗留**：在物理输入活跃的会话（用户在场的 RDP/console）重跑 `loop/qa/r1b-press.ps1 -Drive Full -Repeat 10 -Label <x>` 即可补齐契约 2~5 数字（脚本已修复全部问题：AttachThreadInput+点击前台化、PowerShell 逗号数组解析 bug、BOM）。预期：环视 dyaw≈0.9 rad；MMB 水平拖 400 px→相机位移≈8 units（-right 方向）、垂直拖 300 px→+up；滚轮 3 tick→dolly 3 units；RMB+W 400ms→位移≈4 units。

## 环境/工具备注（供后续 loop 会话）

- **门禁退出码探针**：CMD 单行 `cmd && echo OK || echo %ERRORLEVEL%` 里的 `%ERRORLEVEL%` 在解析时取旧值（失败也打 OK）——必须用独立行 `echo XXX_EXITCODE=%ERRORLEVEL%`（样板 `loop/qa/gate-fix1.cmd`），报告结论附日志名+退出码原文。
- clippy 的 doc 注释里行尾 `+ xxx` 会被按 markdown 列表项解析（doc_lazy_continuation）；连字符/加号起头写法要避免。
- 无 BOM UTF-8 的 .ps1 中文脚本会被 PS5.1 按 ANSI 误解析（本报告所有新脚本已加 BOM；新建脚本后 `r1b-diag.ps1` 的 BOM 转换一行可复用）。
- PowerShell `@(a - b, c - d, ...)` 因逗号数组优先级高于减法会炸 op_Subtraction——差值要逐行赋值。
- 后台进程前台化必须 AttachThreadInput（+点击），纯 SetForegroundWindow 静默失败。
- BRP 组件路径用 `bevy_window::window::Window` 这类 crate 名前缀（非 `bevy::window::...`）；`world.list_components` 在此 fork 需要 entity 参数。
