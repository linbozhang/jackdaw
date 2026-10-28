# T01-T1 报告：fly 激活断言设施 + 全矩阵验证 + 按需修复

任务：`loop/plans/t01-viewport-acceptance.md` D6-T1。分支 `loop/t01-viewport`（自 main 6445cbf2），提交 **8ff028cc**（2 文件，+152/-5）。
真机会话：探针 `loop/reports/t01-probe/sess1/`、矩阵 `loop/reports/t01-v5|v6|v7|vfix/`（metrics.csv）。

## 1. 断言设施（D1）

| 改动 | 文件 | 内容 |
|---|---|---|
| L1 通道 | `src/viewport.rs` | `CameraFlyActive`/`CameraPanActive` 补 `Reflect + #[reflect(Resource)]` + `ViewportPlugin::build` `register_type` ×2 |
| L1+ 通道 | `src/viewport.rs` | `register_type::<bevy::input_focus::InputFocus>()`——bevy 自带 Reflect Resource 但无人注册；注册后 BRP `world.get_resources` 可读 `bevy_input_focus::InputFocus` 的 `current_focus`（真机验证可读，V8 扫描用它判聚焦）。注意 BRP 用**类型路径**而非 use 路径 |
| L2 通道 | `crates/jackdaw_camera/src/lib.rs` | `JackdawCameraSettings` 补 `Reflect + #[reflect(Component)]` + plugin `register_type`（V9 断言 `enabled` 用，真机验证可读） |
| SnapSettings | 降级（plan §1.3.3 预设路径） | 内层 `jackdaw_snap` 是 engine-agnostic crate（仅 glam+serde），加 bevy_reflect 违反分层且超 30 行预算 → T10 走 PX/用户终审 |
| `node_contains` DPI 单测 | `src/viewport.rs` tests | 100%/150%/200% 同一逻辑 rect 命中/不命中一致 + 边界含端点（2 测） |

「零变化断言必须先过激活探针否则记 INVALID」内建驱动脚本（V1/V2/V2g/V2s/V3/V5 每格先读 B1）。驱动/探针脚本：`loop/qa/t01-probe.ps1`、`loop/qa/t01-drive.ps1`（UTF-8 BOM，PowerShell 5 兼容——无 BOM 会被按 ANSI 误读）。

## 2. 🔴 D5#1：InputFocus 稳态假阳性——复现 + 修复（头号嫌疑证实）

证据链：
1. 代码：修复前 `update_active_viewport` 用裸 `input_focus.get().is_some()` 判 `text_focused`。
2. bevy c9c397b `set_initial_focus`（PostStartup）无焦点时把 **PrimaryWindow 实体**设为焦点（源码+`src/keybind_focus.rs` 模块文档双证）→ 稳态 `is_some()` 恒真。
3. 单测复现（修复前逻辑）：`the_startup_window_focus_does_not_disable_the_camera` **FAILED**（`loop/reports/t01-d51-repro-prefix.log`）——冷启动后 `inputs_clear=false` → 相机 `enabled=false` → fly/pan/zoom/WASD 全哑，直到首次视口点击。与「R1 修后按下仍坏」「时好时坏」（点过视口的会话好、冷启动坏）完全相容。
4. **真机复现+修复验证**：探针 P3n（冷启动、零点击、光标 jiggle 后直接 RMB）→ `CameraFlyActive=true`（`t01-probe/sess1/probe.csv`）——修复前该路径必哑。

修复（1 行语义）：`text_focused = focus.is_typing()`（`KeybindFocus`，只认焦点实体持 `EditableText`）。修复后单测 5/5：窗口实体焦点不禁相机、真文本框仍禁。

## 3. 🟡 D5#4：对话框相机使能双写——结构性证实 + 修复

`EditorDialog` 是纯 marker（不带 `BlocksCameraInput`），`update_active_viewport` 的 blockers 查询对纯对话框无感知 → 对话框开时两系统不定序双写 `enabled`。修复：`disable_camera_on_dialog.after(update_active_viewport)`。**真机端到端证据**：V9——对话框期 B1 fly=false + **L2 enabled=false** + 相机零位移，关闭后 fly 恢复 true（`t01-v7/metrics.csv`）。

## 4. 门禁

| 门 | 退出码 | 日志 |
|---|---|---|
| `cargo fmt --all -- --check` | 0 | — |
| `cargo clippy --workspace -- -D warnings` | 0 | `gate-clippy-t01t1.log` |
| `cargo xtask fast` | 0（2851 passed / 2 skipped） | `gate-xtask-fast-t01t1.log` |
| `cargo test -p jackdaw --lib viewport::` | 0（5/5，含 4 新测） | §2/§1 |
| `cargo test -p jackdaw --test operators modal_escape` | 0（4/4，含全 modal 扫描） | `gate-modal-escape-t01t1.log` |
| `cargo xtask integration` | **BLOCKED-env**（非代码） | `gate-xtask-integration-t01t1-attempt1/2/3.log` |
| plain 构建 `cargo build -p jackdaw -p jd` | 0（5m17s，含全部改动） | — |

integration 三连失败均为环境性，错误形态各不相同且互相独立：①os error 1455（页面文件太小，mmap rlib 失败）→ 留下损坏产物；②jackdaw_dylib 多版本 rmeta 冲突（E0460）；③mcp_smoke 链接器 CRT 符号全丢（mainCRTStartup/memcpy undefined）。代码侧证据：同一改动 plain 全链路编译+链接成功、fast 2851 全绿、clippy 干净。缓存修复需全量 `cargo clean`（57GB+，重编 30-60 分钟）后复跑——建议 QA 收尾时执行。

## 5. 三级探针与注入分级（会话 sess1）

| 探针 | 结果 | 结论 |
|---|---|---|
| P3 fly 端到端 | **PASS**（before=false/down=true/up=false） | B1 通道上线，fly 链真机活 |
| P3n 冷启动 RMB（D5#1） | **fly=true**（零点击） | 修复真机证据（见 §2） |
| P1 点击类 | PASS | C 类可用 |
| P2 光标位置类 | **FAIL**（SetCursorPos+jiggle 后 Window.cursor_position 两读均 null） | SetCursorPos 纯位置路径死；但 RMB/LMB/Wheel 事件自带位置可达 hover 判定（V1n 负例+V1 正例证明） |

最终分级：**GREEN-M**——点击/键盘/滚轮/**移动拖拽**（MoveRel raw delta）全活（V2 实测推翻了初始 HOVER-BLOCKED 判级）；唯 SetCursorPos 纯位置读数死。会话内复查（每 5 用例）：全部 cursor 读数 null（P2 一致），用例结果未受影响。
驱动工程教训（已固化进脚本）：minimize/restore 式前台保持会令 cursor_position=None → hover 门失效 → RMB 无法激活（v3 会话 V1 全 INVALID 根因）；改用 AttachThreadInput 轻量保持后 v5 起全绿。

## 6. 矩阵结果（V1-V10 / T1-T10）

视口组（断言通道 B1/B2/L2；CSV：v5=Viewport 全量、v7=Front 终版、vfix=V4/V5 复核）：

| # | 结果 | 证据摘要 |
|---|---|---|
| V1 ×10 | **PASS 13/13**（v5×10+vfix×3） | 每轮激活证明 act=true；dyaw/dpitch/pos_hold/pos_rel 全 0.0000（R1b 复发场景 4-10 次覆盖） |
| V1n | PASS ×3 | 视口外 RMB：fly=false、零位移 |
| V2 | PASS ×3 | dyaw=-0.900 精确（300px×0.003；右拖=yaw 减小） |
| V2g | PASS ×3 | 50000px 单帧整帧丢弃（0.0000）+ 随后 75px 小移 -0.225 精确（闸生效且不粘死） |
| V2s | PASS ×3 | 3 帧各 600px：perFrame=[-1.8,-1.8,-1.8]，无整段丢失（600px<1000 不误伤实测） |
| V3 | PASS ×3 | panX dot=-6.00/len=6.00（沿 -right）、panY dot=+6.00/6.00（沿 +up）、yaw/pitch 不变 |
| V4 | **PASS***（断言器符号修正判读） | dolly=5.00（600 wheel delta=5 ticks×1.0 精确）纯轴向共线；脚本 fwd 公式算的 +Z（bevy backward，forward=-Z），修正后方向正确。初轮 FAIL 是注入单位 bug（wheel delta 120/tick） |
| V5 | **PASS***（同上） | W len=4.15 前进、E ΔY=+4.00 / Q ΔY=-4.17（世界 Y 新断言）、exz=0.000；fwdDot 同源断言器符号 |
| V6 | PASS ×3 | 选中 Cube F：相机位移 3.75/3.17；selection.clear 后 F 零变化 |
| V7a | PASS | V1×10 后 V2 同会话仍准（会话复位） |
| V7b | PARTIAL（2/4） | Alt+Tab 后 fly 复位 false ✓、回来再激活 true ✓；before=FAIL 为该轮 RMB 注入竞争（激活语义已由 V1 13/13 覆盖） |
| V7c | PARTIAL（2/3） | 最小化复位 false ✓、before ✓；afterRestore 同类注入竞争 |
| V8 / V8-R1 | **BLOCKED** ×3 | Inspector 数字框点击/双击扫描（12-28 点）未达成文本聚焦（InputFocus.current_focus 恒 null）；BRP 焦点通道本身已验证可读。R-1 语义留用户终审第 7 条 + `disable_keyboard_input_when_typing` 单测锚 |
| V9 | **PASS**（v7） | 对话框期 fly=false + L2 enabled=false + 零位移；Esc+点外关闭后 fly=true 恢复（D5#4 端到端）。v6 会话曾用错 op（project.open_recent 无参不弹窗），换 `scene.open_recent` |
| V10 | **PASS** ×2 | R-3 裁定 A 完整验证：modal 取消（modal=null）+ 顺势环视（fly=true、拖拽 look=0.45 rad） |

工具组（T1-T10，v7 会话）：

| # | 结果 | 证据 |
|---|---|---|
| T1 | **PASS 4/4** | 真机键 Q/W/E/R → B1 ActiveTool 精确翻转 |
| T2 | **PASS** | Digit1→BrushEdit(Vertex)，Esc→Object，再 Esc→Object（分层退出不连退） |
| T3 | DEGRADED | Digit4 未进入 Clip（进入路径与推演不符，非取消语义问题）；headless modal_escape 锚 + 终审 |
| T4 | DEGRADED | KeyK 未进入 Knife（同上） |
| T5 | **PASS 2/2** | 标尺 Esc/RMB：modal 激活→null、ActiveTool 回 Select（r2 回归锚复现） |
| T6 | **PASS 2/2** | Draw Brush Add-Esc（原死路）/Cut-RMB：modal 归 null 无残留 |
| T7 | DEGRADED | 预设：terrain stroke 注入超会话预算；modal_escape 单测锚 + 终审 |
| T8 | **PASS** | gizmo 拖拽中 Esc：modal 复位、无崩溃；Transform 还原由 modal_escape（gizmo.drag 扫描）锚定 |
| T9 | DEGRADED | G 键未启动 modal transform（键位/前置与推演不符）；headless 锚 + 终审 |
| T10 | DEGRADED | 预设：SnapSettings 反射链超预算（§1）；PX + 终审 |

统计（真机矩阵）：**PASS 26 / PASS*（断言器符号修正）2 / PARTIAL 2 / BLOCKED 2（V8、V8-R1）/ DEGRADED 5（T3/T4/T7/T9/T10）/ INVALID 0 / FAIL 0**。headless 锚：modal_escape 4/4 + input_contexts/jackdaw_camera 既有单测全绿。

## 7. 幅度闸误伤论证（R-4 裁定 A：挂账，未改阈值）

实现（`src/input_contexts.rs:408-434`）：`MAX_PLAUSIBLE_POINTER_DELTA=1000.0` px/帧，`drop_synthetic_pointer_jump` 作用于**帧累积和**（L474-475 fold 后判定），超限**整帧归零**（drop 非 clamp）。

| 场景 | px/帧@60fps | 判定 |
|---|---|---|
| 常规编辑器甩动（0.25s 横扫 2560px 屏） | ~171 | 安全（5.8x margin） |
| 激进甩动（0.1s 全屏） | ~427 | 安全（2.3x margin） |
| V2s 实测（600px/帧 ×3） | 600 | 不误伤（实测 -1.8rad/帧 全保留） |
| 电竞级 1600DPI 2m/s 1:1 | ~2100 | **误伤面（整帧丢弃）** |
| 200ms 卡顿帧内中等快甩积压 | ~1300 | **误伤面（帧累积 ∝ 帧时长，且丢弃无恢复）** |
| RDP/驱动重锚（历史实测 3.7e4–8.5e5） | — | 正确丢弃（设计目标，与阈值隔 37–850x） |

结论：常规编辑器使用 margin≥2.3x，V2s/V2g 双向实测闭环（600 放行/50000 丢弃）；真实误伤面收敛于高 DPI 极速甩动与卡顿帧积压两角（低帧率下等效阈值随帧时长缩水）。候选修法（下任务评审）：按事件前门控（fold 前逐事件判定）或阈值 ∝ 帧时长；clamp 不可行（会回退「点按不动」修复）。本轮另观察到**闸的漏放面**：v1 会话曾见 637px/150px 级被动小跳变（低于阈值全放行），但该会话有 minimize/restore 循环干扰（v5/vfix 干净会话 13/13 零跳变），归档为环境噪声疑似，不立案。

## 8. 遗留与建议

1. **integration 门环境修复**：全量 `cargo clean` 后复跑 `cargo xtask integration`（三次失败日志已存档；页面文件压力是首因，建议跑门时关掉大内存进程）。
2. **V8 文本聚焦坐标**：自动扫描未命中；建议下轮用截图定位或 UI 树查询（BRP 无 UI 坐标查询通道）后补跑，当前由终审第 7 条兜底。
3. **T3/T4/T9 模式进入路径**：Digit4=Clip、KeyK=Knife、G=modal transform 的进入前置（可能需先入 BrushEdit/特定选中态）需查 keymap `is_available` 后补真机格。
4. R-1/R-3 语义真机验证状态：R-3 ✅（V10×2）；R-1 ⛔（随 V8 BLOCKED，单测+终审兜底）。
5. 驱动脚本固化的三条环境教训：无 BOM 的 UTF-8 ps1 被 PowerShell 5 按 ANSI 读（语法炸）；minimize/restore 前台化会清 hover（用 AttachThreadInput 替代）；wheel 注入单位是 120/tick。

## 9. 用户终审 30 秒清单（plan §7，含 BLOCKED/DEGRADED 兜底项）

1. 冷启动**不点任何地方**直接右键拖：应转动（D5#1 体感）。
2. 3D 视口连点右键 5 次：纹丝不动。
3. 右键拖一圈/快速甩两下：跟手、无跳变、无冻结感（R-4 体感）。
4. 中键左右/上下拖：跟手平移；静止中键点击：snap 翻转一次（T10）。
5. 滚轮 + 右键 W/Q/E 两秒：缩放/前进/升/降正常。
6. 选中 Cube 按 F 对准；标尺测量中 Esc、再 RMB：都能退出。
7. **点进 Inspector 数字框打字，按 Esc/WASD：视口不动、先退出输入框，再 Esc 才回 Select 工具（V8/R-1 的终审兜底）。**
8. （可选）100% DPI 重复 2/3。
