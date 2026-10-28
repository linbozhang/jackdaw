# 功能 #8 终验报告：画质设置面板（Graphics 面板）

- 验收对象：`loop/graphics-panel` @ `d80f5303`（任务 3 接管完成）；功能级 = 三任务合链（`9148873d` → `87666d96` → `d80f5303`）
- 验收人：QA agent（终验）· 2026-10-24 · 契约：真机验收
- 需求口径：`loop/plans/feature-08-graphics-panel.md` 任务 3 节 + §5 QA 清单；程序报告 `feature-08-t3-report.md`；T1/T2 QA 报告 `feature-08-t1-qa.md` / `feature-08-t2-qa.md`
- **VERDICT: PASS（功能级）**

## 1. 门禁（本轮亲跑，每门后台+轮询，独立日志）

| 门 | 结果 | 日志 | 对基线 |
|---|---|---|---|
| `cargo xtask fast` | **EXIT 0** · 2847 passed / 2 skipped | `gate-xtask-fast-f8-finalqa.log` | 与 t2/t3 基线持平 |
| `cargo xtask integration` | **EXIT 0** · 4997 passed / 3 skipped | `gate-xtask-integration-f8-finalqa.log` | 与 t3 基线持平；`jackdaw::viewport graphics_panel::*` 8/8 PASS（新空态测试 @4848/4997） |
| `cargo doc --locked --workspace --document-private-items --no-deps` | **EXIT 0** | `gate-doc-f8-finalqa.log` | 警告集合与 t3 基线逐行一致（3 条 rustdoc 私有链接均存量），零新增 |
| doctests 基线 | **非回归**（对比） | `gate-doctests-f8t3.log` vs `gate-doctests-finalqa.log` | 两日志均 52 suites ok + 同 3 targets failed（jackdaw_bind/jackdaw_feathers/jackdaw_node_graph），逐行相同 → 101 失败集合为 Windows+dynamic_linking 环境既有 |

## 2. 任务 3 规格验收

### 空态提示（`GraphicsSceneEmptyHint`）
- **测试真实存在且过**：`tests/viewport/graphics_panel.rs` 的 `the_scene_empty_hint_follows_the_scenes_environment`（无环境→`Display::Flex` + 面板文本含 "no environment"；spawn `Environment`→`None`；despawn→`Flex` 三态往返），本轮 integration 门实跑 PASS（日志 4848/4997 行）。
- **实现核实**：构建期按「场景有无 Environment」种子 `Display`（首帧即正确，`build_scene_section(..., scene_has_environment, ...)`）+ `update_scene_empty_hint` 系统随 `Query<(), With<Environment>>.is_empty()` 切换——与既有 `GraphicsOptOutHint` 同范式，无隐式状态。
- **ftl 键渲染英文非键名**：headless 断言面板文本含 "no environment"；真机 BRP 读 Text 组件原文 = "This scene has no environment, so these controls write nothing. Add an Environment component to the scene to start authoring its look."（`graphics-scene-empty-hint` 键未泄漏）。

### book（`book/src/user-guide/graphics-panel.md`）逐条对照
| 文档内容 | 实现核对 | 结论 |
|---|---|---|
| 双区语义（Viewport=editor-only/即改即生效/无 undo/`viewport.json`；Scene=`Environment.post`/单条 undo/随场景保存） | `viewport.*` 家族 `allows_undo=false` + `store_viewport_settings`；B 区 `environment.set` 内部单条 `SetEnvironment`（T2 QA §2 + headless 测试） | ✅ |
| 控件清单（A 区 7 行 / B 区 4 行） | `build_viewport_section`/`build_scene_section` 控件行一一对应（T2 QA §3.1 真机 16 行断言） | ✅ |
| preset 表 4 档 × 8 列 | `QualityPreset::quality()` 逐格比对：Low=50%/Off/low/off×5；Medium=75%/FXAA/medium/off/on/on/off/off；High=100%/FXAA/high/on/on/on/on/off；Full=100%/TAA/high/on/on/on/on/SSAO on(High) | ✅ 全吻合 |
| GI 原因（Solari experimental / 硬件光追 / 独立 cargo feature / 未接入 + 四替代项） | ftl `graphics-realtime-gi-tooltip` 同文案；真机 T2 run26 tooltip 截图 | ✅ |
| AA 顺序 "Off, FXAA, TAA or SMAA"（t3 修正后） | `AntiAliasing::ALL = [Off, Fxaa, Taa, Smaa]`（`viewport_settings.rs:129`） | ✅ 修正准确 |
| 默认值（Exposure 9.7 / TonyMcMapface / Nine tonemappers / Render Scale 25–100%） | `environment.rs:312-313`（9.7/TonyMcMapface）；`Tonemapper` enum 恰 9 变体；`MIN_RENDER_SCALE=25` | ✅ |
| 空态提示文案（"a scene with no environment shows a note"） | 见上，真机实证 | ✅ |
- **SUMMARY 链接有效**：`user-guide/graphics-panel.md` 条目指向真实文件（本机未装 mdbook，未跑 build 渲染，以文件存在性+格式验证——⚪ 见发现）。
- **README 行准确**："**Graphics panel** … **Window > Graphics**"——窗口注册名 "Graphics"（`builtin_extensions.rs:211`）+ Window 菜单由 WindowRegistry 自动生成（`lib.rs` 按区分组枚举）。

### 无越界
- diff = 恰 6 文件（README/SUMMARY/graphics-panel.md/main.ftl/graphics_panel.rs/tests），**无盘点表（roadmap-gap-analysis.md）改动**，与程序报告「不对应 roadmap 行不改表」一致。
- `loop/` 不入库：`.git/info/exclude` 含 `loop/`，`git status` 干净。

## 3. 真机验收（轻量，T2 已深验）

脚本 `loop/qa/f8-final-hint.ps1`（三态主流程）+ `f8-final-hint-diag.ps1`（诊断复现）；plain 构建（`cargo build -p jackdaw` 先行重建防 hashed DLL）；my-game + BRP 15703。

| 态 | 操作 | BRP 断言 | 截图 |
|---|---|---|---|
| 空态（my-game 本无 Environment） | `graphics.open` | 提示行 `display=Flex`、size=145×44、Text=英文文案全文 | `loop/f8-final-qa/final-empty-hint.png`（灰字提示肉眼可见，双区在右栏渲染） |
| 有环境 | `component.add` Environment + `environment.set post.enabled=true` | `display="None"`、size=0 | `final-with-environment.png`（提示消失；控件恢复：Post Processing 勾选、TonyMcMapface、9.70、0.00/0.00；Realtime GI 行同帧可见） |
| 删除复现 | `component.remove` | `display=Flex` 回来（诊断探针两次复现，其一含 environment.set 完整序列） | —（BRP 字段级证据 + headless despawn 测试） |

- 首跑第三态误报 FAIL：**QA 脚本 bug**（PowerShell 标量字符串 `[0]` 取到实体 id 首字符 → remove 打到无效实体且错误被丢弃），诊断脚本以正确实体引用两次复现三态全对——非产品缺陷。

## 4. 功能级终验：方案 §5 QA 清单逐项汇总

**确定性门**：fmt/clippy（fast 内嵌权威口径）×4 轮全绿（T1/T2/T3/本轮）；doctests 基线非回归。✅
**headless 行为断言**（T1/T2 QA 报告 + 本轮 integration 复跑）：
- AA=smaa 组件矩阵/TAA↔SMAA 互斥清理 ✅（T1 §2 + BRP 真机）
- SSAO ultra 透传 + off 回收组件与 NormalPrepass ✅（T1）
- CAS 出现/消失/强度透传 ✅（T1）
- 旧 viewport.json 无新字段 → default + preset 往返 ✅（T1）
- B 区字段/相机 dress/一条 undo 全回滚 ✅（T2；dress 由 `jackdaw_surface` 既有测试承担）
- WindowRegistry/dock tab/A 区零 undo ✅（T2 + 本轮 integration）✅
**真机**（T2 深验 + 本轮）：
- 命令面板/Window 菜单开面板、双区、GI 置灰 + tooltip ✅（T2 §3.1/3.4）
- AA 切换 ✅（TAA 组件断言 T1-BRP + SMAA pixdiff 3.89% T2）；SSAO ✅（on/off 组件+回收+pixdiff 2.17%）
- bloom 滑条 ✅（`post.bloom_intensity`==UI 值 + pixdiff 77.11% + Ctrl+Z 精确回滚）
- viewport 菜单回归 ✅（`viewport_settings_menu.rs` 数据驱动零改动 + 测试全绿）；`tests/stage/scene_environment.rs` 全绿 ✅
- 「A 区改动后 Play 不泄漏」真机 Play 专项未单独做——由架构边界（viewport.json/.bsn 双层分离 + `EnvironmentOptOut` 机制）与 scene_environment 既有测试支撑，⚪ 记录
**文档**：book ✅（一处括号提示项「SSAO 桌面后端说明」未落，⚪）；README ✅

**t2 遗留 concern#1**（无环境时 B 区开关乐观回写）：t3 空态提示已将「静默」改善为「明说」，维持 t2 裁定（记录不修）。

## 5. 用户需求闭环判定

用户原话「加一个能让我调整画质设置，比如实时GI、TAA、bloom等功能的编辑面板」：

| 点名项 | 处置 | 判定 |
|---|---|---|
| 实时 GI | 置灰 + tooltip（Solari experimental/硬件光追/feature 未启用 + SSAO/天空反射/探针烘焙/体积光四替代项），真机点按零变化 | **诚实闭环**（方案 §7-1 用户裁决推荐项：显示置灰优于消失） |
| TAA | AA 四态（Off/FXAA/TAA/SMAA）面板可切，组件/视觉双证据 | ✅ |
| bloom | 强度/阈值滑条 + 组开关，pixdiff 77.11% + 单条 undo | ✅ |
| 「等」（SSAO/CAS/tonemapping/exposure/preset/render scale/阴影/雾） | A 区 9 项 + B 区 4 项全可用 | ✅ |

**判定：闭环。** 面板所见即所得，存储边界（编辑器预览 vs 场景资产）清晰且有文档。

## 6. 用户手测清单（30 秒）

1. 编辑器里 Window > Graphics（或命令面板搜 "Graphics"）→ 面板开在右栏；
2. Anti-Aliasing 行点 **TAA** → 视口拖动相机，边缘锯齿明显变化；
3. Scene 区先开 Post Processing，再拖 **Bloom Intensity** 到 0.8 → 亮部出现辉光；Ctrl+Z 一次即回滚；
4. 悬停 **Realtime GI** 行 → tooltip 说明 Solari 现状与替代项；
5. （可选）新空场景无 Environment 时，Scene 区有灰字提示「no environment…」。

## 7. 发现

| 级别 | 责任方 | 问题 |
|---|---|---|
| ⚪ | QA（本轮） | 首版真机脚本 PowerShell 标量字符串 `[0]` 索引 bug 造成一次误报；已诊断纠正（`f8-final-hint-diag.ps1` 留档正确写法） |
| ⚪ | 程序（文档） | book 未落方案 §5 括号提示的「SSAO 桌面后端说明」（浏览器 WebGPU/WebGL2 不支持、桌面可用）——括号提示非硬性行，可随下次文档迭代补 |
| ⚪ | QA 覆盖 | TAA 自身 pixdiff、SSAO Low↔Ultra 档位 pixdiff、Play 泄漏真机专项未单独做：组件断言 + 同族 pixdiff（SMAA 3.89%/SSAO on-off 2.17%）+ 架构边界 + 既有测试已覆盖同一通路 |
| ⚪ | 环境 | 本机未装 mdbook，SUMMARY 链接以目标文件存在性验证，未跑 build 渲染 |
| ⚪ | 既有 | t2 concern#1（无环境时 B 区乐观回写瞬时态）维持记录不修；doctests 101 失败集合为 Windows 环境既有（历轮同集合） |

无 🔴 / 🟡。

## 8. 结论

四门全绿（亲跑）、任务 3 规格（空态提示测试+实现+ftl 渲染 / book 逐条属实 / 无越界 / loop 不入库）全过、真机空态提示三态实证（截图+BRP 字段级）、功能级 QA 清单汇总闭环。**功能 #8「画质设置面板」PASS 收口**，可合入 main。
