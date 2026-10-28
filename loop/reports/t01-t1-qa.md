# T01-T1 QA 验收报告：fly 激活断言设施 + 矩阵验证 + D5#1 修复

任务：`loop/plans/t01-viewport-acceptance.md` D6-T1 · 分支 `loop/t01-viewport` @ **8ff028cc**（基于 main 6445cbf2，2 文件 +152/-5）
程序报告：`loop/reports/t01-t1-report.md` · QA 会话：`t01-qa/`（qa1 探针、coldstart v1-v4、qa-viewport、qa-front）

## 0. 结论

**PASS**。四门禁全绿（含 clean 后 integration 5001/5001），🔴 D5#1 修复获本方独立真机直接判据证实，矩阵证据链核实无虚报，
QA 独立会话复现全部抽验格（V4/V5 PASS* 另获代码级证明），V7b/c 在 QA 会话中升级为全 PASS。
发现 7 条 ⚪（无 🔴/🟡），不阻塞。

## 1. 门禁（QA 亲跑）

| 门 | 结果 | 日志 |
|---|---|---|
| `cargo fmt --all -- --check` | **PASS**（exit 0） | — |
| `cargo clippy --workspace -- -D warnings`（权威口径） | **PASS**（exit 0，独立复跑） | `gate-clippy-t01t1-qa-authentic.log` |
| `cargo xtask fast` | **PASS**：2851 passed / 2 skipped（与程序报告一致） | `gate-xtask-fast-t01t1-qa.log` |
| `cargo test -p jackdaw --lib viewport::` | **PASS** 5/5（4 新测全过） | §会话记录 |
| `cargo test -p jackdaw --test operators modal_escape` | **PASS** 4/4 | §会话记录 |
| `cargo xtask integration`（clean -p jackdaw 后重跑） | 见 §1.5 | `gate-xtask-integration-t01t1-qa.log` |

### 1.5 integration 门

程序三次失败日志核实（attempt1/2/3）：均为 `--features dylib` **构建阶段** exit 101——
①E0786 mmap rlib「页面文件太小 (os error 1455)」→ 坏元数据级联 E0463/E0432；②同源级联；
③rust-lld 链接 mainCRTStartup/memcpy 等 CRT 符号全丢。三形态互不相同、均非本分支 diff 所能触发
（diff 仅 `src/viewport.rs` + `crates/jackdaw_camera/src/lib.rs`：游戏逻辑 + reflect 注册，零 dylib/链接/构建面）。
QA 执行 `cargo clean -p jackdaw` 后重跑：**PASS——5001 tests run: 5001 passed, 3 skipped（exit 0，
Summary 439.4s）**。证实程序「环境性（页面文件压力产生坏 rlib 级联）非代码」的判定正确；
最小清理（clean -p jackdaw）即足以修复，无需全量 cargo clean。
（QA 收尾已重建 plain `jackdaw.exe`/`jd.exe` 供用户终审，`gate-build-plain-t01t1-qa.log`。）

## 2. 代码审查

### 2.1 🔴 D5#1 修复语义（`text_focused = focus.is_typing()`）——正确
- `KeybindFocus::is_typing()`（keybind_focus.rs:38-43）：焦点实体持 `EditableText` 才 true；
  窗口实体焦点（bevy `set_initial_focus` 稳态）→ false。与全局键盘归属规则
  `keyboard_is_spoken_for`（is_typing || is_recording）同语义，相机门与 keybind 门口径一致。
- 反向风险核查：非文本可聚焦 UI（按钮等键盘焦点）聚焦时相机放行——**by-design**，与 keybind
  静音逻辑一致（按钮不吞 WASD），Unity 亦然；「真文本框仍禁」由单测
  `a_focused_text_edit_still_disables_the_camera` 锁定。未发现误放行面。
- 单测 5/5：`gate_app_with_fly` 巧妙隔离 gate（hovered=false 由 fly 会话补偿，enabled==inputs_clear
  成为唯一变量）；`the_startup_window_focus_...`（修复前 FAILED，`t01-d51-repro-prefix.log` 存证）。
- ⚪ 注记：相机门未查 `is_recording`（录和弦时相机仍动）——极端角落、与旧码一致，非回归。

### 2.2 D5#4 对话框排序（`.after`）——正确
`disable_camera_on_dialog.after(update_active_viewport)`（viewport.rs:246-247）：同在 Update 调度，
对话框开时 dialog-kill 帧内后行、结果态确定 disabled；注释准确。真机 V9（QA 会话复现）端到端证实。

### 2.3 reflect 注册 ×4——无序列化副作用（含一处潜在脚枪）
- `CameraFlyActive`/`CameraPanActive`/`InputFocus`：Resource，文档保存（`scene_io/save.rs` author 路径）
  只走实体组件（`doc_entities_in_order(&ast)`），资源不进 .bsn ✓。
- `JackdawCameraSettings`（Component）：仅挂编辑器视口相机（viewport.rs:398 `build_3d_presentation`），
  非 authored 实体，文档 walk 不达 ✓。真机 BRP 可读（V9 的 enabled 断言 + QA coldstart B 判据均依赖）。
- ⚪ 潜在脚枪：`should_skip_component` 的 `jackdaw::` 前缀**不**覆盖 `jackdaw_camera::` 路径
  （cf. `jackdaw_camera_rig::ActiveCameraRig` 需显式入 SKIP_COMPONENT_PATHS 的先例）——当前无害，
  若未来 authored 实体获得该组件会静默进场景文件。建议下次触碰 scene_io 时补名单。

### 2.4 node_contains DPI 单测——质量合格
2 个新测覆盖 plan D4 要求的 1.0/1.5/2.0 三档命中/不命中 + 边界含端点；构造真实
`ComputedNode{size∝dpi, inverse_scale_factor=1/dpi}` + 物理平移，实际执行 `node_contains` 的折算链。

### 2.5 越界核查
diff 仅 2 文件，无文档/盘点表改动；`loop/` 经 `.git/info/exclude` 排除不入库 ✓；`git status` 无未预期 tracked 改动。

## 3. 真机抽验（QA 独立会话，自己跑）

### 3.1 注入分级（qa1 探针）
P3 PASS（fly before=false/down=true/up=false）；P2 FAIL（SetCursorPos 纯位置读数死，与程序会话同型）；
P1/前台断言失败 → 脚本判 INJ-DEAD(HOVER-BLOCKED)。但后续 qa-viewport V2 dyaw=-0.900 精确成立
证明 MoveRel raw delta 通道活——功能等效程序会话的 GREEN-M 分级，仅前台断言通道劣于程序会话。

### 3.2 冷启动零点击 RMB（D5#1 修复核心场景）——四脚本递进锁定
- v1（qa-coldstart.ps1）：探针式 minimize/restore 前台化丢前台权 → 非诊断（见发现 #3）。
- v2/v3：`input.pointer` 进程内 CursorMoved 开 hover 门后：**A** fly 激活=True、**B** enabled=True
  （窗口实体焦点稳态 `current_focus="71v0"` 直读为证——旧码此处必 enabled=False）、**C1** 按下零跳变
  （dyaw/dpitch/pos 全 0.0000）；一次运行中 OS 级 RMB 亦激活成功（os_rmb=True）。
- v4（通道隔离，零 OS 鼠标）：A 激活 ✓ / B enabled=True ✓ / **C2 KeyW 零点击前进 1.17** ✓ /
  D 释放清位 ✓。v3 中 C2/D 的异常确认为脚本自身 OS RMB 残留按住的通道干扰，非产品问题。
- 结论：稳态窗口焦点 → 零点击 RMB 激活 → 相机使能 → 按下零跳变 → WASD 端到端 → 释放清位，
  全链真机成立；B/C2 两项为旧代码行为的直接反证。

### 3.3 V2 + 幅度闸（qa-viewport 会话）
V2 PASS dyaw=-0.900 精确；V2g PASS：50000px 单帧整帧丢弃（0.0000）+ 随后 75px 小移 -0.225 精确
（闸生效且不粘死）；V2s PASS perFrame=[-1.8,-1.8,-1.8]（600px/帧不误伤）；V3 PASS（pan 方向/转角不变）。

### 3.4 V9 / R-3（qa-front 会话）
V9 PASS：对话框期 fly=False + enabled=False（L2）+ 零位移，关闭后 fly=True 恢复（D5#4 端到端复现）。
V10 PASS：R-3 裁定 A——标尺 modal RMB 取消（modal→null）+ 顺势环视（fly=True，look=0.45 rad）。

## 4. 矩阵证据抽查

- **PASS*（V4/V5）**：QA 会话独立复现出与 vfix **完全相同**的数字（dolly=5.00/dot=-5.00；
  W 4.16/Ey +4.00/Qy -4.17/exz 0.000）。代码级证明符号修正正当：`camera_system` 正 zoom_ticks 沿
  `transform.forward()`（bevy forward=−Z_local）位移（jackdaw_camera lib.rs:166-167），而脚本
  `Cam-Axes.fwd` 取旋转矩阵第三**列**=local **+Z**（backward，命名误导）；dot=−len 且共线度 1.0
  = 恰好沿真实 forward 前进 5.00（5 ticks × scroll_speed 1.0）。E/Q 世界 Y 与 exz 断言原本就 raw PASS。
  **PASS* 定级正当**。
- **PARTIAL（V7b/c）**：v7 CSV 的 before 失败确系注入竞争——QA 会话同格 **V7b 4/4、V7c 3/3 全 PASS**，
  PARTIAL 升级为 PASS 证据成立。（程序报告 V7b 写 2/4 实为 3/4，见发现 #1。）
- **INVALID=0 可信度**：激活探针逐轮内嵌（t01-drive.ps1:240-241、:277-241 等，失败即记 INVALID）；
  早期脏会话（t01-v/t01-v3 metrics.csv）中激活失败**如实记 INVALID**（V1 连续 6 轮 INVALID 存档），
  证明机制真实非装饰；最终统计仅计 v5/v7/vfix 干净会话。V8 的 CSV INVALID 为「前置未达成」用法，
  报告重标 BLOCKED 属分类学辩护，但口径不一致（发现 #2）。

## 5. 发现汇总

| # | 级别 | 责任方 | 问题 |
|---|---|---|---|
| 1 | ⚪ | 程序报告 | V7b「2/4」实为 3/4（away/backIdle/reengage 过，仅 before 注入竞争）；不影响定级 |
| 2 | ⚪ | 程序报告 | V8 CSV 记 INVALID vs 报告统计 INVALID=0/BLOCKED 2——同词两义，建议后续 CSV 用 NOT-Achieved/BLOCKED |
| 3 | ⚪ | 程序脚本 | t01-probe.ps1 Assert-Foreground 的 minimize/restore 丢新进程前台权 → P3n 在前台敏感会话非诊断（qa1 复现）；§8.5 教训清单未收录此条 |
| 4 | ⚪ | 程序（后续） | `jackdaw_camera::` 前缀不在 scene skip 名单（§2.3）——当前无害的潜在脚枪 |
| 5 | ⚪ | 环境/非本分支 | clippy `--all-targets`（超权威口径）在 tests/dylib_linkage_identity.rs 触发 unfulfilled-lint-expectations（无 dylib feature 时 `#![cfg]` 清空文件体）；main 既有，分支未触碰 tests/ |
| 6 | ⚪ | 程序 | 相机门未考虑 KeymapCapture::is_recording（§2.1 注记） |
| 7 | ⚪ | 程序脚本 | V2s CSV detail 的 `total={0:N2}` 格式串未插值（perFrame 数组已足证） |

## 6. 遗留确认（与程序报告 §8 对齐）

- integration 门环境修复：QA 已执行 clean -p jackdaw + 重跑，结果见 §1.5。
- V8 文本聚焦坐标、T3/T4/T9 进入路径、T10 snap 反射：维持程序报告的降级/终审安排，QA 无异议
  （V8-R1 语义由终审第 7 条 + `disable_keyboard_input_when_typing` 单测锚兜底）。
- 用户终审 30 秒清单（程序报告 §9）待用户执行。

## 7. QA 会话产物索引

| 文件 | 内容 |
|---|---|
| `t01-qa/coldstart.csv` .. `coldstart4.csv` | 冷启动 D5#1 判据链（v4 为最终版全绿） |
| `t01-probe/qa1/probe.csv` | QA 探针分级 |
| `t01-qa-viewport/metrics.csv` | V1-V5 独立复现（V4/V5 数字与 vfix 一致） |
| `t01-qa-front/metrics.csv` | V6-V10 独立复现（V7b/c 全 PASS、V9/V10 复现） |
| `gate-clippy-t01t1-qa(-authentic).log`、`gate-xtask-fast-t01t1-qa.log`、`gate-xtask-integration-t01t1-qa.log` | 门禁日志 |
