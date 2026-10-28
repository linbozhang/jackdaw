# 功能 #8 · 任务 3 报告：Graphics 面板文档 + B 区空态提示 + 全量门

- 分支 `loop/graphics-panel`（基于 main `bf7ef2a6` = 任务 2 合入点），提交 **d80f5303** `Document the graphics panel and hint when the scene has no environment`
- 6 文件 +186/−7：`book/src/user-guide/graphics-panel.md`（新，81 行）、`book/src/SUMMARY.md`、`README.md`、`src/graphics_panel.rs`（+63）、`tests/viewport/graphics_panel.rs`（+47）、`crates/jackdaw_localization/src/locales/en-US/main.ftl`
- `loop/` 不入库（`.git/info/exclude`），门禁日志留本地

## 半成品核查（前任 agent 中途死亡，零提交，全部在工作区）

逐文件 diff 核查后**全量保留**，质量良好，仅需 1 处修正：

| 文件 | 核查结论 |
|---|---|
| `src/graphics_panel.rs` | 空态提示实现完整：`GraphicsSceneEmptyHint` marker + 构建期按「场景有无 `Environment`」种子 `Display`（首帧即正确）+ `update_scene_empty_hint` 系统随环境增删切换——与既有 `GraphicsOptOutHint` 同范式，无问题 |
| `tests/viewport/graphics_panel.rs` | 新测试 `the_scene_empty_hint_follows_the_scenes_environment`：无环境显示/有环境隐藏/despawn 后复现三段断言，headless 可靠（复用 `settle`/`panel_text` 既有 helper），保留 |
| `main.ftl` | 新键 `graphics-scene-empty-hint` 文案准确（与 book 口径一致），保留 |
| `book/src/user-guide/graphics-panel.md` | 内容逐条对源码核实**全部属实**（面板位置 Window 菜单/RightSidebar/`graphics.open`；双区存储语义；preset 四档表逐格比对 `QualityPreset::quality()`；默认值 9.7 EV100/TonyMcMapface/25–100%；GI 置灰原因=Solari）。**修 1 处**：AA 选项顺序 "Off, FXAA, SMAA or TAA" → "Off, FXAA, TAA or SMAA"（面板 segmented 实际顺序） |
| `SUMMARY.md` | 挂载于 Resources 与 Play-in-editor 之间，位置合理，保留 |
| `README.md` | 新增功能表一行 "Graphics panel … **Window > Graphics**"，与窗口注册（名 "Graphics"、Window 菜单/命令面板入口）核对**准确**，保留 |

前任死因复核：其 `gate-xtask-integration-f8t3.log` 止于 4731/4997 无 Summary（长前台命令被看门狗杀）；fast 门日志（11:30，晚于最后代码编辑 11:21）已 PASS。本轮全部四门由我重跑取证。

## B 区空态提示 + 断言

- **行为**：场景无 `Environment` 时 B 区显示一行提示（`graphics-scene-empty-hint`）替代 t2 报告 concern#1 的「静默 warn + 开关瞬时乐观」——控件仍在但提示行明说「these controls write nothing. Add an Environment component …」；环境出现（无论来源：Add 菜单/脚本/undo）提示即隐藏。
- **测试**：`the_scene_empty_hint_follows_the_scenes_environment`（三态往返：Flex → spawn Environment → None → despawn → Flex，另断言面板文本含 "no environment"）——integration 门实跑 PASS（日志 4847/4997 行）。

## 全量门（每门后台 + 轮询，独立探针行 + 日志）

| 门 | 命令 | 结果 | 日志 | 数字 |
|---|---|---|---|---|
| fast（含 fmt + 权威 clippy `--all-targets --features dylib --deny warnings` + lib 测试） | `cargo xtask fast` | **EXIT 0** | `loop/reports/gate-xtask-fast-f8t3b.log` | 2847 passed / 2 skipped（与 t2 基线持平，本轮无新 lib 单测） |
| integration | `cargo xtask integration` | **EXIT 0** | `loop/reports/gate-xtask-integration-f8t3b.log` | **4997 passed / 3 skipped**（t2 基线 4996 + 1 恰为新空态测试，零失败） |
| doc | `cargo doc --locked --workspace --document-private-items --no-deps` | **EXIT 0** | `loop/reports/gate-doc-f8t3.log` | jackdaw lib doc 3 warning 逐条核对**均存量**（game_export.rs ×2、pie.rs ×1，feature #5/#7 遗留），本 diff 零 rustdoc 告警 |
| doctests 基线 | `cargo test --locked --workspace --doc --features bevy/dynamic_linking --no-fail-fast` | 非零（**既有，非回归**） | `loop/reports/gate-doctests-f8t3.log` | `error: 3 targets failed` 失败集合**恰为** {jackdaw_bind, jackdaw_feathers, jackdaw_node_graph}，与 f7 终验基线（`gate-doctests-finalqa.log`）逐行相同、其余 test result 全 ok、零新增失败 → 101 基线非回归 |

## 盘点表建议（只报告，未改动）

**画质面板不对应盘点表（roadmap-gap-analysis.md）任何一行**——它是用户原话点名的需求（见方案文件选题依据），roadmap Stage 0–6 无「画质/后处理面板」条目。最接近的两行均**不因本功能翻绿**：行 96「偏好设置（热键/相机/语言/widgets 显隐）」🟡 的四个具体缺口（语言仅一方言、widgets 显隐无入口）无一被补；行 97「面板布局持久化」的 viewport.json 注记亦不受影响。建议主控：无需改盘点表；如欲留痕，可在行 96 备注加「viewport 画质偏好已面板化（#8）」——语义仍 🟡。

## 遗留 / Concerns

1. t2 报告 concern#1（无环境时 B 区开关点按的瞬时乐观回写）**未修**：空态提示从「静默」改善为「明说」，但 `on_toggle` 先回写 `Checked` 再被 operator cancel 的瞬时状态仍在（t2 已裁定记录不修，维持）。
2. 真机交互验收（命令面板 SendInput 开面板、空态提示截图、book mdbook build 渲染）归 QA/终审；本轮 headless + 门禁已覆盖状态机与事实准确性。
3. doctests 101 失败为 Windows + `bevy/dynamic_linking` 环境性既有问题（feature-01 起每轮同集合复现），建议非 Windows CI 复核（历轮已记录）。
4. QA 教训再证：本轮 doctests/门全程后台+轮询，无超时；重跑 doctests 后 `target\debug` plain exe 可能再次依赖 hashed DLL（后续真机驱动前须 `cargo build -p jackdaw -p jd` 重建）。
