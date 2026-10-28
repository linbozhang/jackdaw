# T02 任务 2（收尾）报告：可发现性两招 + 灯 color 真机闭环 + 全量 CI

> 程序（Rust/Bevy 工程师 Agent）。分支 `loop/t02-inspector-t2`，自 main `43901e9e` 拉出。
> **commit：`f31dbb57` `Show category headers and tooltips in the inspector`**（7 文件，+294/-8）。
> 日期：2026-10-25。方案来源：`loop/plans/t02-inspector-loop.md` §5/§7/§8-T2。

## 1. 门禁（全绿）

| 门 | 结果 | 数字 |
|---|---|---|
| cargo fmt --all --check（xtask fast 内嵌） | PASS | exit 0 |
| clippy --workspace --all-targets --features dylib -D warnings | PASS | exit 0 |
| `cargo xtask fast` | PASS | 2865 passed / 2 skipped（T1 后 2864，+1 = 新单测） |
| `cargo xtask integration` | PASS | 5035 passed / 3 skipped（T1 后 5032，+3 = 2 集成用例 + 1 单测），新增 3 用例全在列 PASS |
| `cargo doc --locked --workspace --document-private-items --no-deps` | PASS | exit 0 |
| doctests（`cargo test --workspace --doc --features dylib --no-fail-fast --locked`） | **基线非回归** | 55 suites：52 ok + 3 targets failed（jackdaw_bind / jackdaw_feathers / jackdaw_node_graph），与 `gate-doctests-finalqa.log` 基线同形，52 条 result 行逐行一致（唯一 diff 是一行时长数字）；Windows+dynamic_linking 环境既有 101 失败集合，零新增 |

日志：`loop/reports/t02-t2-gate-{fast,integration,doc,doctests}.log`。

## 2. D4 两招实现要点

1. **tooltip 加 description（registry 数据 + builder 接线）**
   - `InspectorCategory`（`crates/jackdaw_api_internal/src/inspector.rs`）新增 `pub description: Cow<'static, str>`（空串 = 无描述行）；六条 en-US 静态文案按方案 §5.1 表格逐字入 seed 表（registry 静态串，与 label 载体一致——裁定②）；单测 `builtin_categories_carry_descriptions` 锁非空。
   - `spawn_category_strip` 的 `Tooltip::title(label)` → `.with_description(cat.description)`（两级展开 300ms/1200ms 为 feathers 既有机制，零新代码）。
2. **内容列常显分类名标头**
   - 新 marker `ActiveCategoryLabel`（`src/inspector/category_strip.rs`）+ Text 节点插在内容列顶部 `InspectorAddHeaderMount` 上方（`src/layout.rs`）；样式 TEXT_SIZE_SM + SEMIBOLD + TEXT_SECONDARY（同 Graphics 面板 section 头等级）。
   - 小系统 `update_active_category_label`：`ActiveInspectorCategory.is_changed()` / registry 变 / label Added 时单写 Text（不并入 `rebuild_add_header` 的整套重生——方案 §5.2 明确分离）；注册为独立 `add_systems`，`.after(resolve_active_on_rebuild)` 保同帧跟随粘性解析（原 21 元组已达 Bevy 系统元组上限，加第 22 个会编译错，故拆出）。
3. **headless 断言 ×2**（`tests/inspector/category_strip.rs`，公共查询助手 `jackdaw::inspector::{active_category_label, category_tab_tooltips}` 仿 `field_edited_by` 先例）：
   - `category_tabs_carry_title_and_description_tooltips`：六个 seeded tab 的 (title, description) 全量比对；
   - `active_category_label_follows_tabs_and_selection_switches`：默认 Object → 手动切 Components 跟随 → Transform-only 实体重建后随粘性解析回 Object。

## 3. 灯 color 真机闭环（新 QA 工具，§7-1）

驱动脚本 `loop/qa/t02t2-light-color.ps1`（Brp-Call 重试模板）；证据目录 `loop/reports/t02t2-light/`。
环境：临时工程 `%TEMP%\t02t2-proj`（jackdaw.toml `bevy = "main"` 免版本对话框；assets 目录需预建），plain 调试 exe（launch4 PATH 模式），1920x1080。

| 腿 | 结果 | 数字 |
|---|---|---|
| ui 链选中灯（outliner ui_click）→ 展开 DirectionalLight 卡（粘性：重选后保持展开） | PASS | — |
| color 字段经 ui 链改色：hex 框 `ui_input`（聚焦→全选→逐字符→Enter）`ff0000` 再 `00ff00` | PASS | typed:true ×2 |
| ① ECS 镜像（world.query DirectionalLight.color） | PASS | 红 (1,0,0) → 绿 (0,1,0) 两轮全中 |
| ① authored bsn（jackdaw/entity） | PASS | `Color::Srgba(Srgba { red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0 })`、后 `green: 1.0` |
| ② 视口即变（pixdiff 红光 vs 绿光，场景含 cube 受光面） | PASS | 15374 px 变化（1.48%），mean diff 1.156 |
| ③ 存盘（scene.save 带 path）→ scene.bsn 落盘 | PASS | `assets/qa-scene.bsn` 15029 bytes 含 `green: 1.0` |
| ③ 重开一致（杀进程→重启→自动打开场景→world.query） | PASS | (r=0, g=1, b=0) 保持 |

headless 灯 color 用例：任务 1 矩阵已含（DirectionalLight color），核对无需重做（方案 §3 表）。
附带真机观察：新增 `ActiveCategoryLabel` 在 ui_tree 中实测可见（[1703,65,213,18]='Object'，切 Components 变 'Components' 由 headless 用例锁定）；tooltip 两级展开为 hover 计时器驱动，ui 工具不注入 hover 位移，留作用户 30 秒清单项。

## 4. book

`book/src/developer-guide/architecture.md` "Inspector and picker" 节补一句级说明（页签图标条 + 悬停 title/description + 常显标头）。user-guide 无 inspector 专页，按现有结构裁量落在 developer-guide。

## 5. 用户 30 秒手测清单（终验）

1. 选中场景里的 Sun/Directional Light → 右侧 Inspector 面板顶部显示 **Object** 标头，卡列表见 DirectionalLight 卡；
2. 展开卡 → color 行 hex 框输入 `ff0000` 回车 → **视口立方体立即变红**；
3. **Ctrl+S → 关掉编辑器重开工程 → 灯还是红**；
4. 悬停 Inspector 左侧图标条任一图标：约 0.3s 出分类名，停 1.2s 出一行说明（如 "Identity, transform and visibility: what this entity is."）；
5. 点 Components 页签 → 顶部标头变 **Components**；切到别的实体再回来，标头随粘性解析正确。

## 6. 偏差与 concerns

- **⚪ 集成测试树里双份 strip 无断言影响**：`selection_switch.rs` 等旧用例手动 spawn `inspector_components_content`，而默认 dock tree 也开一份 inspector 窗口 → headless 下 strip/标头双份。本任务新用例只用默认窗口（单份）。旧用例行为不受影响，不属本任务清理面。
- **⚪ `update_active_category_label` 拆出元组**：因 Bevy 系统元组 arity 上限（21），系统独立注册 + `.after()` 显式排序，注释已说明；无功能影响。
- **⚪ QA 脚本真机沉淀**（对 T-QT 有用）：`jackdaw/screenshot` 的 path 必须相对工程根；`scene.save` 无 path 对 untitled 场景静默不落盘（带 path + 预建 assets 目录才行，本次曾踩：os error 3）；`set VAR=value && ...` 的 cmd 尾随空格陷阱会让工程路径带尾随空格触发「不是 Rust project」对话框；ShellExecute 隐藏台启动在本环境不可靠，`cmd /c bat` 直连可行（manual §7.5 已有记载，本轮再证）。以上已随脚本沉淀进 `loop/qa/t02t2-light-color.ps1` 注释。
- **⚪ roadmap T02 勾选与台账**：progress.md 已记行（见下）；roadmap 复选框留待 QA 验收/merge 时勾，程序侧不预勾。

## 7. 台账

`loop/progress.md` 追加行（本次同步写入）。
