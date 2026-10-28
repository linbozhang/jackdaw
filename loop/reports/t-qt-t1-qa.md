# T-QT-T1 验收报告（QA）

> 对象：`loop/t-qt-qa-mcp` T-QT 任务 1（程序，commit `4433587f`，基于 main `bc5274ee`）。
> 验收人：QA（ZCode 子代理，GLM-5.3）。日期：2026-10-24（机器时间 10-25 凌晨）。
> **结论：PASS**。真机验证用新工具本身完成（dogfood）。

## 1. 门禁（本机独立重跑，提交树）

| 门 | 结果 | 备注 |
|---|---|---|
| fmt（含于 fast：`cargo fmt --all --check`） | PASS | xtask fast exit 0 |
| clippy（含于 fast：`--workspace --all-targets --features dylib -- -D warnings`） | PASS | 无新告警；日志仅存量 build-script 告警 |
| `cargo xtask fast` | PASS | 2863 passed / 2 skipped，31.4s（log: t-qt-t1-qa-gate-fast.log） |
| `cargo xtask integration` | PASS | 5023 passed / 3 skipped，324s；6 个 `controls::ui_probe_click` + 4 个新 `guards::editor_remote` 全部在列 PASS（log: t-qt-t1-qa-gate-integration.log） |
| mcp_smoke | 本机不可跑（既有） | `has_a_display` 只认 DISPLAY/WAYLAND_DISPLAY（Unix）——`git show main:tests/mcp_smoke.rs:42` 确认 main 上逐字相同，**非本任务引入**；扩展断言（+5 工具名 + ui_tree 真调）已随 diff 审阅，Linux CI 会跑 |

## 2. 代码审查（11 文件，+2170/-12）

- **真实事件链**：ui_click/ui_drag/ui_input 一律 `SyntheticInput.queue(...)` 排 beat（`click_gesture`/`drag_gesture`/`typing_gesture`），驱动走 First→winit 等价 WindowEvent→picking→observer 全链；`ui_probe.rs` 只做查找与 rect 数学，无任何直接 operator 调用/组件写入/事件伪造。headless `ui_probe_click.rs` 钉死 wireframe 翻转、TextEditValue="entity: 42"、滑条 ValueChange ramp（末值>0.8）——测的是真路径。
- **拒收语义**：歧义→INVALID_PARAMS 带 4 字段候选（entity/kind/text/rect，真机实测列出 4 条）；disabled/隐藏/无框→带原因拒绝；拒收时队列保持空（测试断言）。文案具体（"index N is past the M candidates; 0 is the first"）。
- **input.motion 双闸门**：单拍 >1000px → `warn_caller`（引用 `MAX_PLAUSIBLE_POINTER_DELTA`，input_contexts.rs 改 pub(crate) 仅此一处）；排在未播完手势后 → 告警（内嵌 3 帧抑制窗提示）。`Emit::Motion` 直写 `Messages<MouseMotion>`（First 注入→PreUpdate 累加→Update 消费，单测+headless 钉死）。方案口径是"warnings 带闸门提示"，非硬拒——实现与方案一致。
- **wait idle 并入**：`editor_is_busy` 加 `SyntheticInput` 非空判定（对齐 boot_ops 语义）；guards `a_queued_gesture_holds_idle_until_it_has_played` 钉死时序；真机所有 Wait-Idle 均在手势播完后应答。
- **MCP 薄翻译**：5 工具各一条 BRP POST，零自有状态零组合逻辑；UiInputLocator 无 text 防冲突；tools/list 20 个（实数核对）。`input.motion` 不另设工具（走 call_operator），符合裁定。
- **安全边界**：server.rs 绑 `Ipv4Addr::LOCALHOST`（loopback-only）+ 无 CORS 注释在案；5 个新 handler 首行 `check_enabled`（remote.enabled 开关，guards 专项测试）；不加 feature 门控 = 裁定 D2 原文。不扩大暴露面。
- **偏差（报告 6 项）核实**：① ObservedBy 兜底——真机证实启动卡片确为 kind=node/operator:null 的手搓按钮；② 精确标签优先——真机 text="Add" 命中 4 候选，需要消歧，精确匹配集非空才优先合理；③ picker 文本自身兜底——Sphere 行点中 [99,392.5] 且 scene 出 Sphere；④ Ctrl+A、⑤ move-before-press 均有代码+测试依据；⑥ 是 F8 证据注记非偏差。全部合理。
- **无任务 2 越界**：无 qt-*.ps1、无旧脚本取代注记、无 dogfood；manual.md 新增 §7 速查属 T2「manual v2」的预览性子集（报告已声明，loop/ 不入库，无害）。loop/ 确认 git-ignored。
- 工作区 `.gitignore`(+.mimosa/) 与 `buglist.md` 为 T02/本地残留，与本分支无关（buglist 内容是 main 分支 review 清单）。

## 3. 真机验证（新工具 dogfood，编辑器 target\debug\jackdaw.exe，BRP 15807）

脚本 `t-qt-t1-qa-live.ps1`（首启失败，见发现 2）/`t-qt-t1-qa-live2.ps1`（UI 部分）/`t-qt-t1-qa-live3.ps1`（相机+负用例）。

| 项 | 结果（数字） |
|---|---|
| ui_tree 过滤 | text="Open without setup" → 1 节点（rect [692,435,146,32]）；kind=button → **105** 个按钮 |
| ui_click（真 picking 链） | 启动卡片 clicked at **[765,451]**；"Add Entity" clicked at **[99,111]**（单次往返 163ms）；picker 打开（3D Objects rect [349,234,573,14]） |
| ui_input+提交 | picker 搜索框输入 "Sphere"+Enter → typed:true → 过滤出 Sphere 行 → 点击 [99,392.5] → scene_tree 根 = **Directional Light, Sphere**（与程序自验的 Cube 流程独立复现） |
| camera_state | yaw **0.000**°，pitch **26.565052**°，translation [0,4,8]，perspective（与程序自验完全一致——跨会话确定性） |
| input.motion 正用例 | RMB(x=900) fly=true → rest 5 拍 → dx=**-160**/16 拍 → release：yaw 0→**+20.626°**（pitch Δ0，dy=0 正确无俯仰泄漏；方向与程序 dx=+240→-41.25° 反号一致，灵敏度比 0.75 与窗口尺寸相关，同号同数量级） |
| 负用例 >1000px | dx=3000 steps=1 → warnings 返回 "**3000 px in one frame is beyond the 1000 px the camera treats as plausible… Raise `steps`**"，且 yaw Δ=**0.000°**（闸门确实整拍丢弃） |
| 负用例 排队告警 | 手势未播完时再排 motion → warnings 返回 "queued behind a gesture still playing… queue a `rest` of 3 or more beats" |
| 负用例 歧义拒收 | text="Add" → "**4 candidates**; pass \"index\" to pick one"，candidates 带 entity/kind/text/rect |

**对比旧 SendInput 法省了什么**：一次 HTTP 调用替代「AttachThreadInput+前台焦点+坐标手算+sleep 赌时序」——定位/换算在编辑器内完成，坐标零手算，提交时序由单队列+wait idle 消灭；环视不再依赖 OS 级注入通道。

## 4. 发现

- 🔴 无。
- 🟡 无。
- ⚪ [环境/工具链] `t-qt-t1-selfcheck.ps1` 默认直接跑 `target\debug\jackdaw.exe`，但 integration 门（--features dylib）终跑后该 exe 已重链为 dylib-host：PE 导入 `bevy_dylib-43235e9931895b3d.dll`、`std-512d688ad63bc3c4.dll`，二者在 `target\debug\deps\` 与 rustup toolchain lib 目录，不在 exe 目录——直接启动 = 0xC0000135 或加载器错误框（本次验收首发失败 40 分钟的根因）。程序自验当时跑在重链前的静态 exe 上所以成功。**T2 dogfood 重跑前必须把 deps+toolchain lib 加进 PATH**（本次 launch4.cmd 模式已验证可行）。非 T1 diff 引入，但 T2 会踩。
- ⚪ [T1] `ui_drag` 未实现方案规格表 3.1 的 `frames` 参数（handler 硬编码 1，MCP UiDragArgs 也只有 steps）；steps 已覆盖 QA 需要，报告未列此偏差。
- ⚪ [T1 报告口径] 「单测 test_input 12 个」实为 12 总数（其中新增 3）；17 = 12 总 + 5 新混计，数字口径易误读，不影响结论。
- ⚪ [QA 脚本] Invoke-RestMethod 陈旧 keep-alive 连接造成一次 20s 超时（live2 中断处）；live3 加重试后稳定。T2 的 qt-*.ps1 建议 Brp-Call 带 WebException 重试。
- ✅ 正向：跨会话确定性（两次独立真机会话点击坐标 [765,451]/[99,111]、pitch 26.565 完全一致）；负用例告警文案精确指向修复动作；拒收不污染队列。

## 5. 遗留确认

- 滑条 F8 定论归 T2（本任务 headless ramp 证据成立，报告预告合理）。
- picker 懒加载只见分类头属正常（搜索框可达，本次 Sphere 流程实证）。
- 真机环境注记：本 QA 子代理 harness 无法直接派生带窗口进程（编辑器经 Task Scheduler /IT + 完整 PATH 启动后完成全部验证）；脚本与日志见 loop/reports/t-qt-t1-qa-*。
