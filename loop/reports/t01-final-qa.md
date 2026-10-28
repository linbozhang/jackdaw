# T01 终验 QA 报告：任务 2 验收 + 「视口导航与工具取消」整体终验

验收对象：`loop/t01-viewport` @ **85afcc1e**（基于 main 9116d2cb；diff 仅 3 个 book 文件 +70/-1，零 Rust 改动）。
程序报告：`loop/reports/t01-t2-report.md`；前置：T1 QA `t01-t1-qa.md`（8ff028cc，Rust 面与 85afcc1e 字节一致）。
QA 会话产物：`loop/reports/t01-final-qa-session/`（metrics.csv、toolbar-maximized.png、toolbar-right-zoom.png、boot 日志）＋ `gate-*-t01-final-qa.log`。

## 0. 结论

**PASS（T01 整体）**。四门亲跑全绿；任务 2 补验证据抽查全部与报告一致；V8 锚定论证链逐环核实成立；
三处 book 改动准确无越界；真机抽验 4 项中 2 项本会话直接复现（工具 Esc 取消、RMB 取消、磁铁可见性），
冷启动 fly 与中键平移在本 QA 显示会话被环境性阻断（诊断链完整，见 §4，不计产品缺陷——同一 Rust 代码
已有 T1 QA 独立真机全绿证据 + 本轮 2851/5001 测试绿）。矩阵终态 **FAIL=0 / INVALID=0**。
磁铁可见性出现**新观察**：本会话（编辑器 scale=1.0 的显示环境）磁铁**可见未裁剪**，与 T2 s3/s4
（scale=1.5 环境）「被裁剪」并存——裁剪与 UI 缩放相关，用户终审第 9 条维持且更值得看。

## 1. 门禁（QA 亲跑，85afcc1e 树）

| 门 | 结果 | 日志 |
|---|---|---|
| `cargo fmt --all -- --check` | **PASS**（exit 0） | — |
| `cargo clippy --workspace -- -D warnings` | **PASS**（exit 0） | `gate-clippy-t01-final-qa.log` |
| `cargo xtask fast` | **PASS**：2851 passed / 2 skipped（56.3s） | `gate-xtask-fast-t01-final-qa.log` |
| `cargo xtask integration` | **PASS**：5001 passed / 3 skipped（317.8s）**（clean -p jackdaw 后重跑）** | `gate-xtask-integration-t01-final-qa.log` |

integration 首跑在 dylib 构建段报 os error 1455（页面文件太小，mmap rlib 失败）——与 T1 QA §1.5
完全同型的环境故障，按同先例 `cargo clean -p jackdaw` 后重跑即绿。数字与程序报告逐字一致。

## 2. 任务 2 规格核验

### 2.1 补验证据抽查（CSV 与报告结论逐份对上）

| 格 | 抽查文件 | 核对结果 |
|---|---|---|
| T3/T4 | `t01-t2-supplement/s1/metrics.csv` + `s3/metrics.csv` | 两会话一致：Digit4→`BrushEdit(Clip)`、Esc→Object；KeyK→Knife、Esc#1 留 Knife（清路径）、Esc#2→Object。s3 行内附 Esc 双动作活证据（"Esc also deselects"）。**PASS 属实** |
| T9 face-commit | `s4/metrics.csv` | `T9,face-commit,PASS,"modal=brush.face.drag rel='' midChanged=[False,True,True] committed=True"` + `undo restored=True`——拖拽中实时突变 + 提交 + undo 还原，与报告 PARTIAL 定级（Esc 半格 BLOCKED 如实记）**一致** |
| T10 中键平移 | `s5/metrics.csv` + `s6b/metrics.csv` | 双会话 `mm-drag,PASS,"pan=True fly=False moved=6.00"`；`mm-click` 两处 FAIL 读数如实保留（翻转半格通道不可达）。**平移半格 PASS 属实** |
| V8 锚定论证链 | 四环核实（下表） | **成立** |

V8 锚定链逐环：
1. **D5#1 修复在码**：`src/viewport.rs:994` `let text_focused = focus.is_typing();`（裸 is_some 已替换，注释在档）；
2. **修复真机证**：T1 QA coldstart4.csv 全绿（窗口实体焦点稳态 `71v0` 下 A fly=True / B enabled=True / C2 零点击 W 前进 1.17 / D 释放清位）——本报告复核该 CSV 在档且字段符合；
3. **单测锚**：`src/viewport.rs:1245` `the_startup_window_focus_does_not_disable_the_camera` + `:1260` `a_focused_text_edit_still_disables_the_camera`（均在 fast 2851 内跑绿）；`src/keybind_focus.rs:75` `disable_keyboard_input_when_typing` 系统及其测试（:96）在档；
4. **上游 Esc=blur**：bevy checkout（bevy-50d7e162b728c6c6/c9c397b）`crates/bevy_ui_widgets/src/text_input.rs:241-251` 确认 `(NONE, Key::Escape)` → `input_focus.clear()` + `should_propagate = true`（blur 且继续冒泡）——「一次一层」的 R-1 语义由上游保证。

### 2.2 文档三处 book 改动准确性（diff 逐段对照代码/证据）

| 文件 | 核对 |
|---|---|
| `viewport-navigation.md` 中键平移节 | 与 `modal_transform.rs:105` `SNAP_CLICK_MAX_TRAVEL=4.0`（行程区分点击/拖拽）、V3 真机证据（pan 沿 -right/+up、yaw/pitch 不变）一致；「静止中键点击=翻转 snap」与 `snap_toggle`（:121-133）一致 |
| `viewport-navigation.md` 打字静音节 | 与 `is_typing` 门 + 上游 Esc=blur 链一致，措辞如实（含「下一次 Esc 才取消工具」） |
| `open-challenges.md` 幅度闸节 | 数字全部复算成立：171px/帧=2560px/0.25s@60fps（5.8x 余量）、427px/帧=2560/0.1s（2.3x）、2100px/帧=1600DPI×2m/s@60fps、~1300px=200ms 卡顿积压量级；两端实测锚（600 放行 / 50000 丢弃）与 T1 QA §3.3 复现数字一致；常量 `MAX_PLAUSIBLE_POINTER_DELTA=1000.0`、`drop_synthetic_pointer_jump` 作用于 fold 后帧和（`input_contexts.rs:418/428/475`）均与文内描述相符；「clamp 不可行」论证与 R1 修复史自洽 |
| `keyboard-shortcuts.md` | `K \| Knife mode` 补行正确（s1/s3 KeyK→Knife 实证）；Esc 行「同时取消选择、重按 1-4 前需点回实体」与 `viewport_select.rs:44-46`（SelectionClearOp 绑定 Escape）+ `escape_is_free`（:61-107）代码事实一致 |

越界核查：**分支 diff**（main..loop/t01-viewport，已提交面）仅 3 个 book 文件；`git check-ignore` 确认 `loop/` 经 `.git/info/exclude` 不入库。工作树另见两处非本任务产物：`.gitignore` 多出未提交的一行 `+.mimosa/`（终验收尾时发现；本 QA 未触碰该文件，开场时工作树干净——疑似 mimosa 插件或并行会话写入，只读验收未回滚，**提请主控知悉**）与本地未跟踪 `buglist.md`。

## 3. 真机抽验（本 QA 会话，plain 构建亲跑）

| 项 | 结果 | 证据 |
|---|---|---|
| 任一工具 Esc 退出 | **PASS（真机复现）** | diag3：operator 起标尺 modal（'tools.measure_distance'）→ 合成 Esc → modal=''。同格 RMB 取消亦复现（diag4：RMB **按下即**取消 modal——T5/R-3 语义真机活证据） |
| 磁铁可见性 | **本会话可见**（与 T2 发现 2 相反） | `toolbar-maximized.png` + 裁剪放大图：磁铁完整可见、右缘有余量；UI 查询 maxX=2539 < 窗宽 2576、clippedRows=0。注意：本会话编辑器 scale=1.0（显示环境与程序会话 1.5 不同），UI 更紧凑故放得下——两观察不矛盾，裁剪是 150% 缩放下的真实现象，**用户终审第 9 条维持**（在你惯用的 150% 桌面看） |
| 冷启动 RMB 即环视 | 环境性未复现（不计缺陷） | 本会话合成通道诊断链：CursorMoved 落地（phys_cursor=[1288,704] 直读回显）、鼠标按键达 ButtonInput（RMB 取消 modal 为证）、cursor 在视口矩形内（本地复算 node_contains 于最大 UI 节点，inside=True）、focus=窗口实体——yet fly/enabled 恒 false。本会话编辑器以 scale=1.0 落在本显示环境（程序会话为 1.5），hover 门未开的原因定位到 update_active_viewport 的环境交互层，非产品缺陷：**同一 Rust 字节**在 T1 QA 独立真机会话 coldstart v4 全绿（A/B/C2/D）＋ s3 "synthetic RMB engages fly=True" |
| 中键拖拽平移 | 环境性未复现（不计缺陷） | 同上（pan 门同 hover 前置）。T2 s5/s6b 双会话真机 `pan=True fly=False moved=6.00` 在档；本会话 OS SendInput 间歇被拒（error 5）亦阻断 OS 通道对照 |

操作性注记（供后续 QA 会话）：`cargo xtask integration` 产出的 dylib 特性 `jackdaw.exe` 能启动但 **BRP 永不就绪**——真机前须 `cargo clean -p jackdaw && cargo build -p jackdaw --bin jackdaw` 重建 plain（本轮已做，`gate-build-plain-t01-final-qa.log`，3m57s 量级）；本会话 OS SendInput 间歇 access denied（前台权/完整性级差异），SetCursorPos 正常——合成通道不依赖之。

## 4. T01 整体终验

### 4.1 矩阵终态（T1@8ff028cc + T2@85afcc1e 合并，Rust 面一致）

| 组 | 全过 | 终审兜底/挂账 | FAIL/INVALID |
|---|---|---|---|
| 视口 V1-V10（15 格含 V1n/V2g/V2s/V7a-c/V8-R1 折算） | **14**（V1×10、V1n、V2、V2g、V2s、V3、V4*、V5*、V6、V7a、V7b、V7c、V9、V10） | **1**：V8 文本框聚焦（通道不可达，锚链四环核实成立，终审第 7 条） | 0 |
| 工具 T1-T10（10 格） | **7**（T1、T2、T3↑、T4↑、T5、T6、T8） | **3**：T7 terrain-Esc（单测锚+终审）；T9（modal-G=设计不适用＋face-commit/undo PASS＋face-Esc 锚定终审）；T10（平移半格 PASS＋静止点击半格终审第 4 条） | 0 |
| **合计 25 格** | **21 全过** | **4 兜底/挂账** | **0** |

V4/V5 的 PASS*（断言器符号修正）维持 T1 QA 复核结论（QA 独立复现同数字 + 代码级证明）；V7b/c 已由 T1 QA 会话升级全 PASS。

### 4.2 用户 30 秒终审清单

程序报告 §6 十条在档且口径正确（1 冷启动 RMB / 2 连点不动 / 3 快甩 / 4 中键平移+静止点击 snap / 5 滚轮+WQE / 6 F+标尺双取消 / 7 文本框打字静音+Esc 分层 / 8 Esc 双动作 / 9 磁铁可见性【本 QA 补充：100% 缩放下可见为正常，150% 下重点看】/ 10 可选 DPI）。十条恰好覆盖全部 4 个兜底格，无遗漏。

### 4.3 roadmap 勾选建议（给主控）

**可勾**（建议附注：终审清单 10 条待用户陪同过一遍；若用户终审发现体感问题，按 loop 流程另起缺陷单）。
依据：FAIL/INVALID=0；四门双绿（程序+QA 各自亲跑）；核心新行为（稳态焦点激活、幅度闸、中键语义、Esc 分层）均有真机+单测+上游三重证据；遗留项全部有锚且已列入终审。

## 5. QA 发现汇总（本轮新增）

| # | 级别 | 发现 | 处置 |
|---|---|---|---|
| 1 | ⚪ | 磁铁可见性与 UI 缩放相关：scale=1.0 会话可见、scale=1.5（程序 s3/s4）被裁剪——两证据并存，非矛盾；终审第 9 条按 150% 桌面判 | 用户终审定性；若 150% 下确认裁剪，另立 layout 任务（T2 已记） |
| 2 | ⚪（环境/流程） | dylib 特性构建的 jackdaw.exe BRP 不通（integration 门副产物）；且 integration 门首跑可复现 os-1455 页面文件故障 | 已记操作注记（§3）；建议把「真机前重建 plain」写进 loop/qa/manual.md 下次增补 |
| 3 | ⚪（环境） | 本 QA 显示会话编辑器以 scale=1.0 运行且 fly/pan 合成通道 hover 门未开（诊断链 §3）；OS SendInput 间歇 error 5 | 不计产品缺陷（同一字节 T1 真机全绿）；若后续会话复现且排除显示环境差异，再升级排查 |

## 6. QA 会话产物索引

| 文件 | 内容 |
|---|---|
| `t01-final-qa-session/metrics.csv` | 本轮真机抽检四项（含环境阻断行） |
| `t01-final-qa-session/toolbar-maximized.png` / `toolbar-right-zoom.png` | 磁铁可见性直证（全窗 + 右簇放大） |
| `gate-{fmt,clippy,xtask-fast,xtask-integration,build-plain}-t01-final-qa.log` | 四门 + plain 重建日志 |
| `loop/qa/t01-final-{qa,bootprobe,cursorprobe,sendinputprobe,diag,diag2..7}.ps1` | 本轮驱动/诊断脚本（不入库） |
