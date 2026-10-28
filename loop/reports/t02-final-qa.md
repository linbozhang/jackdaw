# T02 终验报告（QA）：任务 2 验收 + T02「Inspector 参数编辑闭环」整体终验

> QA（ZCode 子代理，GLM-5.3）。2026-10-25。
> 对象：`loop/t02-inspector-t2` commit `f31dbb57`（基于 main `43901e9e`，工作树与 commit 一致，
> 仅历史残留 `.gitignore`（.mimosa/ 行）与未跟踪 `buglist.md`，均**未混入提交**，commit 恰 7 文件、无 loop/）。
> 需求真理之源：`loop/plans/roadmap-game-dev.md` T02 条目；方案 `loop/plans/t02-inspector-loop.md`；
> 程序报告 `loop/reports/t02-t2-report.md`；T1 QA `loop/reports/t02-t1-qa.md`。
> **VERDICT: PASS（T02 整体）**，附 1 条 🟡（灯 color 真机链当日不可复现，判环境性，附证据链与用户手测兜底）。

## 1. 门禁（QA 亲跑，全部 PASS）

| 门 | 结果 | 数字 |
|---|---|---|
| `cargo fmt --all --check` | PASS | exit 0 |
| clippy（xtask 权威口径 `--workspace --all-targets --features dylib -- --deny warnings`，fast 内嵌） | PASS | exit 0 |
| `cargo xtask fast` | PASS | 2865 passed / 2 skipped（与程序报告一致；T1 后 2864 +1） |
| `cargo xtask integration` | PASS | 5035 passed / 3 skipped（与程序报告一致；3 新用例在列：tooltips 全集 / 标头跟随 / registry 单测） |
| docs（程序已跑，cargo doc exit 0） | PASS | 未重跑（book 仅 +5 行 prose，低风险） |
| doctests（QA 亲跑 `--workspace --doc --features dylib --no-fail-fast --locked`） | **基线非回归** | 52 条 result 行与 `gate-doctests-finalqa.log` 归一化（去时长）后**逐行一致**；失败目标同为 jackdaw_bind / jackdaw_feathers / jackdaw_node_graph 三处 Windows+dynamic_linking 环境性基线，零新增 |

日志：`loop/reports/t02-final-qa-gate-{fast,integration,doctests}.log`。

## 2. 代码审查（对 commit f31dbb57 全量 diff，7 文件 +294/-8）

- **六条 description 文案**：与方案 §5.1 表格**逐字一致**（object/mesh/modifiers/material/physics/components 六条 en-US 全对）；registry 扩展字段 `description: Cow<'static,str>` 空串语义与 feathers `Tooltip` 一致（「Empty = skipped」实读 tooltip.rs:67-103 核实）。
- **`ActiveCategoryLabel` 排序正确性**：独立 `add_systems` + `.after(resolve_active_on_rebuild)`（mod.rs:202-207）。标头读的正是 resolve 写完的资源，**同帧一致**成立；手动点页签（observer 先于 Update 写资源）同帧跟随（headless 用例锁定 + 本轮真机实测）。触发条件三重（active.is_changed / registry.is_changed / Added<label>）覆盖初帧。**「元组已达上限」声明属实**：pinned bevy（c9c397b）`bevy_ecs/src/schedule/config.rs` `all_tuples!(…, 1, 20, …)` 上限恰 20，现有外层元组恰 20 元素（内嵌 9 元组算 1 个）。程序报告写「21/22」为措辞数字偏差，代码注释与决策正确（⚪）。
- **headless 断言 ×2 质量**（tests/inspector/category_strip.rs）：tooltips 用例六条 (title,description) 排序后集合全等；标头用例覆盖 默认 Object → 手动切 Components → Transform-only 实体重选后随粘性解析回 Object → 显式切回。用 `inspector.category` operator + 真实 selection 切换，非伪造资源写入。公共查询助手（`active_category_label`/`category_tab_tooltips`）仿 `field_edited_by` 先例，非 cfg(test) 与仓库既有模式一致。
- **book**：architecture.md +1 句（页签图标条 + 悬停 title/description + 常显标头），与实现相符，无过度承诺。
- **无越界**：无 D1/D3/资源面板/PIE/Graphics 改动；未动 strip 轨道宽度与 tab 集合（#6T1 裁决维持）；Cargo.toml 零改动。
- **残留**：`.gitignore` 工作区改动（.mimosa/）与 `buglist.md` 均未提交；commit 内无 loop/、无 report 产物。

## 3. 真机抽验（新工具 §7/§7.5）

- **① 分类标头跟页签：PASS**（`loop/qa/t02-final-qa.ps1` -Phase header，1920x1080，ui_click 真实点击链）：
  灯选中 → 标头 "Object" → ui_click strip 底部 tab（[1688,116]）→ 标头 "Components" → 切 Cube → 粘性解析 → 标头回 "Object"。**D4.2 两腿（跟页签 + 粘性同帧一致）真机实证**。附带定位事实：strip 轨 x≈1673（30px 格）、标头 [1703,65]，与程序报告观察一致。
- **② 灯 color 一轮：当日不可复现（🟡，判环境性，非 T2 回归）**。详见 §3.1。
- **③ 快速切换污染回归：本轮 INCONCLUSIVE（环境性，见 §3.1）**，语义覆盖不缺席：T1 QA 真机 5/5（2026-10-25）+ headless 红绿/不变量/可闻三用例在本轮 integration 门全绿 + T2 diff 不触碰 D1 bound 门（§2 审查）。

### 3.1 灯 color 真机链复现失败调查（判环境性）

复现尝试 ×4（我方临时工程 / 程序工程配置副本 / 前台恢复尝试 / **commit 树全量重链 exe 后**），驱动脚本 = 程序原版 `t02t2-light-color.ps1` 未改动：**全部同一形态失败**——ui_input `typed:true`、点击链全部有效（选中/展开卡/切 tab 均工作），但 color 不变、pixdiff 0 像素。

逐层判别（证据在 `loop/reports/t02final-qa/` 与本节文字）：
1. `ui_click` 单点 hex 框 → `bevy_input_focus::InputFocus` 确实落到内层输入（"5297v5"/"5179v6" 等）→ **press→focus 链活着**；
2. 分解式逐键注入（ctrl+a / input.text / Enter）焦点保持稳定 → 但 Enter 提交后 color 仍白；
3. **被聚焦的输入实体在数十秒空闲后死亡**（两次读到 "Entity NvM not found"），而未交互时实体 id 稳定 9s+——面板内容存在**交互后/空闲期重建churn**；
4. **T2 未触碰的既有链路同样死**：name 字段改名（通用字符串提交链，T1 期功能，昨日 T1 QA 真机同机制 intensity 编辑通过）在本轮同样 typed:true 无效果——失败面横跨 T2 diff 之外；
5. 排除项：非 exe/dylib 陈旧（全量 `cargo build -p jackdaw --features dylib` 重链 07:09 后复测仍失败）；非窗口最小化（SW_RESTORE 后仍失败）；非工程配置（程序 .jackdaw/Cargo.toml/jackdaw.toml 原样副本仍失败）；日志无 D1/D3 丢弃 warn（提交链从未收到事件）。

环境差异主嫌疑：**本 harness 无法取得 OS 前台**（SetForegroundWindow 被系统拒绝，isForeground=False），机器桌面交互状态与晨间不同；晨间程序会话（05:50-05:58，pre-commit 同源码构建）与昨日 T1 会话同一流程均通过。

**程序侧证据独立复核（通过）**：
- pixdiff 复算其留档 PNG：12-after-red vs 14-after-green = **15374 px / 1.48% / mean 1.156**，与报告数字逐位一致（另算 10-before→12-after-red = 15470px/1.49%）；
- `13-scene-on-disk.bsn` 15029 bytes 含 `green: 1.0` + DirectionalLight 块；
- `11-authored-bsn.txt` 含 Srgba 红→绿两轮色值；
- headless 灯 color 矩阵（编辑→ECS→AST→save→reopen）在本轮 integration 门全绿。

结论：代码链路有 headless 全矩阵 + 程序真机闭环 + 工件复核三重证据；当日 QA 环境键盘提交链系统性失效（含既有功能），判**环境/QA 驱动因素**。兜底 = 用户 30 秒清单第 2/3 条（灯改红→存档重开），若手测失败再启动 main 构建对照 bisect。

### 3.2 QA 过程瑕疵（如实记录）

- 复跑程序脚本时其硬编码 OutDir 覆盖了 `loop/reports/t02t2-light/` 三个证据文件（`10-before.png`、`11-scene-tree-for-name.txt`、`12-after.png`）。关键证据（12-after-red.png / 14-after-green.png / 11-authored-bsn.txt / 13-scene-on-disk.bsn）完好未动。后续复用该脚本须先改 `-OutDir` 参数化（脚本本身无此参数，建议 T-QT 顺手修）。
- `t02t2-light-color.ps1` 新建工程时写入 `bevy = "0.20"` 会触发启动版本对话框（本轮实测），与程序报告「bevy="main" 免对话框」结论矛盾——脚本种子行与实际用法不一致（⚪，脚本内容问题）。

## 4. T02 整体终验

### 4.1 方案 QA 清单（§7）逐项汇总

| 项 | 证据 | 结论 |
|---|---|---|
| Quick tier 四门（每任务） | T1 QA 亲跑 + 本轮亲跑 | ✅×2 |
| 全量门（fast/integration/docs/doctests 基线） | 本轮亲跑（docs 承程序） | ✅ |
| §7-1 灯 color 闭环（ECS/bsn/视口/存盘/重开） | 程序真机 6 腿全 PASS + 工件独立复算；QA 当日复现受阻（§3.1，环境性） | ✅（附 🟡 兜底手测） |
| §7-2 Add 菜单新建灯数值抽验 | T1 QA（intensity 100000→5.0 ECS+bsn） | ✅ |
| §7-3 快速切换 5 轮 | T1 QA 真机 5/5 零污染；本轮 headless 全绿 | ✅ |
| §7-4 标头可见/跟页签/粘性 | headless ×2 + **本轮真机 PASS** | ✅ |
| §7-5 tooltip 两级展开 | headless 数据断言（六条 title+description 全集）；计时器驱动留用户手测 | ✅（数据）/ 用户手测（时序） |
| §7-6 相机抽查 | headless 主覆盖（Camera3d 字段 roundtrip 既有 + T1 编辑用例）；真机腿承 T1 移交说明未单做 | ✅（headless 口径） |
| §7-7 object tab 卡集合回归 | integration 门（#6T1 用例 + 全套 inspector 17 文件）全绿 | ✅ |

### 4.2 用户验收语句逐条判定

| 验收语句 | 结论 | 依据 |
|---|---|---|
| 相机/灯光/模型/材质/自定义组件的**分类显示编辑刷新** | ✅ | 分类显示 #6T1（用户已验收）+ D4 标头/tooltip（本轮真机+headless）；五类编辑刷新 headless 矩阵 + 既有材质/自定义套件，integration 门全绿 |
| **切换实体后不得编辑旧目标** | ✅ | D1 bound 门（T1）：headless 红绿 + T1 真机 5/5；T2 diff 不触碰该门（审查）；B 污染路径在门存在性下封死 |
| 改参数**三处一致（组件/视口/存档）** | ✅ | 编辑→ECS 镜像→AST→save/reopen headless 全矩阵（灯×2/相机/Transform 锚点）+ 材质/自定义既有 roundtrip；灯 color 真机三处另有程序闭环+工件复核 |
| **重开一致** | ✅ | 同上 save/reopen 腿 + 程序灯色重开 (0,1,0) 保持 |
| **无隐藏无静默失败** | ✅ | D3 三 warn + D1 丢弃可闻（headless 断言 const 串）；T2 无新静默路径；resource/PIE 路由原样（审查） |

### 4.3 roadmap T02 勾选建议

**建议勾选**（roadmap-game-dev.md 第 11 行 `- [ ] T02 …` → `- [x]`），条件 = 用户 30 秒清单通过（尤其第 2/3 条灯色存档重开，作为 §3.1 🟡 的终审兜底）。台账 `loop/progress.md` 已有 T1/T2 两行，可补一行 QA 终验结论。

### 4.4 用户 30 秒终审清单

1. 选 Sun/Directional Light → Inspector 面板顶部显示 **Object** 标头；
2. 展开卡 → color 行 hex 框输 `ff0000` 回车 → **视口立方体立即变红**；
3. **Ctrl+S → 关编辑器重开 → 灯还是红**；
4. 悬停左侧图标条任一图标：约 0.3s 出分类名，停 1.2s 出一行说明（如 "Identity, transform and visibility: what this entity is."）；
5. 在 Cube x 输入框敲数字后**立刻点**旁边的灯 → 灯的 Transform 没被写入；
6. 点 Components 页签 → 标头变 **Components**；切实体再回来标头随粘性正确。

## 5. 发现汇总

- 🟡 [环境/QA] **键盘提交链当日真机系统性失效**（灯色/改名/复合与分解注入皆 typed-无效果；指针链正常；既有功能同样中招；全量重链排除构建陈旧）——判环境性（前台被拒/桌面状态），兜底=用户手测；若手测失败再 main 对照 bisect。含两条 §7.5 候选沉淀：ShellExecute 在本 harness 不可靠（cmd /c 直连可行，已有记载本轮再证）、**前台不可得时合成键盘事件不可作为通过性证据**。
- ⚪ [程序报告] 「原 21 元组达上限」数字偏差（实际 20 = pinned bevy 上限），代码注释与拆分决策正确。
- ⚪ [QA 自身] 复跑脚本覆盖程序证据 3 文件（§3.2）；`t02t2-light-color.ps1` 新工程种子 `bevy="0.20"` 触发版本对话框，与报告口径矛盾。
- ⚪ [T-QT] `ui_input` 返回的 `typed:true` 仅表示手势入队（ui_probe.rs:794-801），不证明落字——真机断言勿单独依赖该字段（本轮教训）。

## 6. QA 工具沉淀

本轮新增 `loop/qa/t02-final-qa.ps1`（launch/header/light/save/switch/reopen/wrap 七相；header 相可直接复用：标头跟页签+粘性真机断言）。真机定位事实：strip 轨 x≈1673、内容列 x≈1713、标头 [1703,65]（1920 窗口）。
