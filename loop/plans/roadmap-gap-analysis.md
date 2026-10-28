# Jackdaw × 官方 Bevy Editor Roadmap 差距盘点

> 策划文档（多 Agent 开发循环 · 功能 #0 选题依据）
> 日期：2026-10-22 · 盘点人：策划 Agent（资深 Bevy 编辑器架构师）
> 方法：仅用 rg 文件搜索 + Read + WebFetch，未运行任何 cargo 命令（避免与后台全仓编译锁冲突）。
> 需求真理之源：官方 Roadmap（bevy_editor_prototypes/roadmap.html），Stage 0–6 + 未分类。
> 状态标记：✅ 完成 / 🟡 部分（缺哪半见说明）/ ❌ 缺失。证据给到文件路径（能定位到行为佳）。
> 统计口径：按本文表格逐行计数，共 **75 项：✅ 46 / 🟡 14 / ❌ 15**（2026-10-23 功能 #4 System Graph 任务 3 落地后更新：未分类「system graph 可视化」🟡→✅；前值 45/15/15 为功能 #2 Panel Maximize 落地后口径；再前值 44/15/16 为功能 #1 Resource Inspector 落地后口径——功能 #1 更新时曾复核发现原统计多计一项，根因是 Stage 2 小节标题与表格行数不一致——标题「7✅」实为 6 行，三行功能#1 改动本身正确）。

---

## 1. 逐项盘点表

### Stage 0 Hello Project（5/5 ✅）

| Roadmap 项 | 状态 | 证据 |
|---|---|---|
| repo / README | ✅ | `README.md`：功能清单、安装、Figma 设计对齐声明、快捷键表 |
| CONTRIBUTING | ✅ | `CONTRIBUTING.md`：operator 范式完整文档（id/label/params/modal/is_available/undo） |
| 基础工程（构建/测试/CI） | ✅ | `Cargo.toml`（49 crate workspace、xtask 测试分层、clippy lints 集中定义）；`CONTRIBUTING.md` Quick/CI 检查集 |
| 总体规划与约束 | ✅ | `book/src/SUMMARY.md` 完整文档树；`book/src/developer-guide/open-challenges.md` 未完成清单 |
| 共同愿景 | ✅ | README 直接链接官方 vision/architecture/roadmap 三文，并声明 UX/UI 已向官方 Figma 靠拢 |

### Stage 1 只读场景查看器（11 ✅ / 1 🟡）

| Roadmap 项 | 状态 | 证据 |
|---|---|---|
| 原生文件选择加载场景 | ✅ | 根 `Cargo.toml:158`（rfd 依赖）；`src/native_dialog.rs`、`src/scenes/ui.rs`、`src/file_ops.rs` |
| 2D/3D 查看器 | ✅ | `src/viewport.rs`（3D 主视口）+ `src/viewport_2d.rs`（Camera2d 渲染进 `Scene2dViewport` UI 面，滚动/中键拖拽导航） |
| 无限网格（2D/3D） | 🟡 | 3D ✅：`src/viewport.rs:6,62-95` 用 bevy `dev_tools::infinite_grid`，每视口一个 grid entity、随视图轴重定向、可步进缩放（`src/grid_ops.rs`）。缺的半：2D 视口只有 UI 像素吸附网格（`src/viewport_2d.rs:132-145` `Ui2dView::grid`，8px 步进），无 2D 世界空间无限网格 |
| 简单相机控制器（2D/3D） | ✅ | `crates/jackdaw_camera`（+ 可选 `jackdaw_camera_rig` feature）；README 快捷键表（RMB look / WASD / Q/E / F focus） |
| 可切换物理实体 gizmo（outlines/lights/AABBs/cameras） | ✅ | `src/viewport_overlays.rs:26-176`：point/spot/dir light gizmo、camera/AABB 标记、`show_brush_outline` 开关、选中恒显 outline |
| 层级树视图 | ✅ | `src/hierarchy.rs` + `src/outliner_rows.rs` + `crates/jackdaw_widgets` tree_view（行内重命名/显隐/锁定） |
| 选择实体（按名/场景拾取/inspector） | ✅ | 场景拾取 `src/viewport_select.rs` + `crates/jackdaw_pick`；按名 `src/command_palette.rs`（picker）；层级点选 `src/hierarchy.rs` |
| 选中实体在 inspector 显示 | ✅ | `src/inspector/`（mod.rs 等 27 个模块） |
| 世界中清晰高亮选中（单/多） | ✅ | `src/selection.rs`（Selection/多选）；`src/viewport_overlays.rs:124-176`（selection always outline；brush 走 chunk-material 高亮） |
| 组件带值显示（含游戏自定义组件） | ✅ | `src/inspector/component_display.rs`、`reflect_fields.rs`（反射值渲染）、`project_component_display.rs` + `crates/jackdaw_schema`（ProjectSchema，游戏定义类型） |
| 资源可检查 | ✅ | 功能 #1（loop/resource-inspector，c461ba37 + f4a72b5d）：`src/inspector/resource_panel.rs`（Resources 面板：枚举/过滤/分组列表 + 选中卡片复用 `reflect_fields` 渲染）；book `user-guide/resources.md`（4fa481ac） |
| 已加载资产基本信息检查 | ✅ | `src/asset_catalog.rs`、`src/asset_index.rs`、`src/inspector/asset_row.rs` / `file_card.rs`（缩略图/路径/信息） |

### Stage 2 基础编辑（7 ✅）

| Roadmap 项 | 状态 | 证据 |
|---|---|---|
| 生成实体 | ✅ | `src/entity_ops.rs`、`src/add_entity_picker.rs`、`src/creation_taxonomy.rs`（CONTRIBUTING spawn_cube 示例即此范式） |
| 增删组件 | ✅ | `src/inspector/ops.rs:285` `component.remove` operator、`:301` ComponentAddOp；`src/inspector/component_picker.rs`（枚举可加类型） |
| 增删资源 | ✅ | 功能 #1（04d941ba + e413f119）：`src/inspector/resource_ops.rs`（`resource.insert`/`resource.remove` operator）+ `resource_commands.rs`（ResourceInsert/ResourceRemove，undo/redo round-trip 见 `tests/resource_panel/insert_remove.rs`） |
| 改组件/资源值 | ✅ | 组件值：`src/inspector/reflect_fields.rs`、`val_field.rs`、`schema_fields.rs` + `src/live_edits*.rs`（PIE 回写）。资源值：功能 #1（04d941ba）`resource.set_field` operator + `ResourceFieldTarget` commit 分流（`tests/resource_panel/edit_undo.rs`，编辑器会话态不落盘，文档见 4fa481ac） |
| 交互式 transform gizmo（作用于全部选中） | ✅ | `src/modal_transform.rs`（自研 GizmoAxis/GizmoDragState/GizmoHoverState）、`src/transform_ops.rs`、`src/snapping.rs`（网格吸附+轴约束，README 功能表） |
| 场景存回磁盘（.bsn 为佳） | ✅ | `src/scene_io/save.rs` + `crates/jackdaw_bsn`（作者格式即 .bsn，.jsn 只读迁移：`src/jsn_to_bsn.rs`）——超出 roadmap 预期 |

### Stage 3 技术难点（5 ✅ / 4 🟡 / 1 ❌）

| Roadmap 项 | 状态 | 证据 |
|---|---|---|
| undo-redo 抽象（用于所有修改） | ✅ | `crates/jackdaw_commands/src/lib.rs:38-111`（EditorCommand trait + CommandHistory undo/redo 栈）；`src/undo_snapshot.rs:120`（BsnDocumentSnapshotter 自动快照）；CONTRIBUTING `allows_undo` 默认 true。README 自述「some bugs atm」，视为带瑕疵的完成 |
| 编辑器可调用 bevy_cli | ❌ | 全仓 `bevy_cli` 仅 `crates/jackdaw_project_build/src/lib.rs:102` 一处注释性 JSON 示例，无实际调用。自有替代：`crates/jd` CLI + `crates/jackdaw_project_build` 自建构建管线 |
| 游戏自定义组件可编辑可实例化 | ✅ | `src/project_definitions.rs:21`（register_project_definitions）、`crates/jackdaw_schema`（ProjectSchema/TypeSchema）、`src/definition_assets.rs`、`book/src/developer-guide/custom-components.md` |
| 游戏特定渲染技术正确显示 | 🟡 | `src/view_modes.rs:30-32`：Lit/Unlit/Wireframe 等视口模式对 ExtendedMaterial（LayeredSurface/Foliage/Water）有 fallback；PIE 侧游戏进程外渲染天然正确。缺的半：编辑器视口内直接预览游戏自定义材质扩展仍受 fallback 限制（`src/worn_material.rs` 的 wear_until_reloaded 语义即其体现） |
| 独立编辑器可执行/启动器发布 | ✅ | `README.md` install.sh/install.ps1/cargo install；`crates/jackdaw_releases`；`src/launcher/`（首页项目选择/New 项目/extensions 页）；release job 见 open-challenges「release export check」 |
| 资产热重载 | 🟡 | 引擎侧 ✅：workspace `Cargo.toml:213` bevy `file_watcher` feature 已开。缺的半：编辑器侧成体系的资产 watcher 工作流未证实（`src/hot_reload.rs` 是**扩展 dylib** 热重载而非资产；仅 `src/prefab/watcher.rs`、`src/reference_image.rs` 局部监听）——外部改资产→视口/inspector 更新的完整闭环**未证实** |
| Run Game（合适二进制新窗口） | 🟡 | 进程模型超出 roadmap：`src/pie.rs` + `crates/jackdaw_pie_protocol`（ipc-channel、进程外 cargo binary、帧流/输入/拾取/Live tree 齐备，见 open-challenges PIE 节）。缺的半：无独立 OS 新窗口——画面固定串流进编辑器内嵌 Game panel（`src/game_panel.rs`「a pure monitor」） |
| tooltips | ✅ | `src/operator_tooltip.rs`（operator 元数据→`jackdaw_feathers::tooltip::Tooltip`，含 keybind 显示）；CONTRIBUTING：params schema 呈现为 call signature hover |
| hotkeys（标准化框架/集中清单/动作热键） | ✅ | `crates/jackdaw_input`（Bindings/Keymap）、`src/keybinds.rs`、`src/keybind_settings.rs`（用户重绑）、`load_active_keymap_preset`（`src/lib.rs:555`）；book `user-guide/keyboard-shortcuts.md` |
| 键盘 UI 导航 | 🟡 | 有基础：bevy `InputFocus` 焦点管理（`src/hierarchy.rs:4`、`src/inspector/reflect_fields.rs:1749,3004`）、`src/keybind_focus.rs`、tree_view 的 TreeFocused。缺的半：跨 widgets 的系统化箭头/Tab/Enter 键盘导航（菜单、列表、面板条）**未证实** |

### Stage 4 Design Time（9 ✅ / 1 🟡 / 1 ❌）

| Roadmap 项 | 状态 | 证据 |
|---|---|---|
| 1.0 编辑器开箱 mockup | ✅ | README：UX/UI 重构为「very similar to the official Bevy Editor Figma design」并附链接 |
| 默认主题书面/视觉规范 | ❌ | `src/default_style.rs` + `crates/jackdaw_feathers/src/tokens.rs` 全部为编译期 const 颜色（ACCENT_BLUE/WINDOW_BG…），无书面主题规范文档（book/docs 无 theme 章节；repo 无 docs/ 目录） |
| 主题化 widgets（文本/数值/文件路径输入、单选、下拉、复选、滑条、取色、图片预览、进度条、音频播放） | 🟡 | `crates/jackdaw_feathers/src/`：text_edit、number_input、file_browser、segmented/picker（单选）、combobox、checkbox、slider_row、color_picker/、progress 全有 ✅。缺的半：**音频播放 widget 无**（feathers/widgets 内无 audio 模块）；图片预览散落在 `src/material_preview.rs`、`src/thumbnail.rs`、`src/inspector/file_card.rs` 等处为 ad-hoc 实现而非统一 widget |
| 编辑器专用：可缩放面板 | ✅ | `crates/jackdaw_feathers/src/split_panel.rs` + `crates/jackdaw_panels/src/split.rs`、`drag.rs` |
| 编辑器专用：可滚动工具详情面板 | ✅ | `crates/jackdaw_feathers/src/scroll.rs`、`options_bar.rs`、`panel_section.rs` |
| 编辑器专用：工具栏 | ✅ | `src/toolbar_overflow.rs`（主工具栏溢出处理）、`crates/jackdaw_animation/src/toolbar.rs`、viewport 工具栏（fps_overlay 注释提及「viewport toolbar and the tool palette」） |
| 编辑器专用：Blender 风格工作区 | ✅ | `crates/jackdaw_panels/src/workspace.rs`、`workspace_tabs.rs` + `src/workspace_dropdown.rs`（工作区增删改名切换） |
| 编辑器专用：右键菜单 | ✅ | `crates/jackdaw_feathers/src/context_menu.rs` + `crates/jackdaw_widgets/src/context_menu.rs`（hierarchy/viewport/inspector 多处接入） |
| 编辑器专用：命令面板 | ✅ | `src/command_palette.rs`（Ctrl+Space / F3，fuzzy picker，operator 全集） |
| 编辑器专用：可全屏面板 | ✅ | 功能 #2（loop/panel-maximize，任务 1 `92ff0049` + 任务 2 `ec8b8e96`）：视图层最大化不动 `DockTree`（`crates/jackdaw_panels/src/maximize.rs` `MaximizedLeaf` + reconciler 兄弟隐藏）；`panel.toggle_maximize` operator + Shift+Space（`src/dock_ops.rs`）+ tab 栏 Maximize/Minimize 图标入口（`crates/jackdaw_panels/src/tabs.rs`）；最大化态不持久化、保存天然存完整布局（`tests/panels/` 14 测试）；book `user-guide/keyboard-shortcuts.md` Panels 节 |
| 编辑器自身只用这些 widgets | ✅ | `src/ui_palette.rs:122` instantiate_widget 统一入口；src/ 全量使用 jackdaw_feathers/jackdaw_widgets（bevy_feathers 主题+自研 widget 层） |

### Stage 5 端到端项目（3 ✅ / 1 🟡）

| Roadmap 项 | 状态 | 证据 |
|---|---|---|
| 下载独立可执行 | ✅ | README 三平台安装方式 + `crates/jackdaw_releases`；`jd doctor` 环境自检（`src/launcher/jd.rs`） |
| 新建项目（最小/空白/模板/模板浏览） | ✅ | `src/launcher/pages/new_project.rs`（Template/Modules/Extensions/Details 四步流程 + TemplateCard 画廊）；`src/new_project.rs` + `crates/jackdaw_scaffold/templates/`（内嵌模板）；`jd new` |
| 浏览打开既有项目 | ✅ | `src/project_select.rs`、`src/launcher/pages/projects.rs`、`src/project_window.rs`；Import Bevy Project 带预览（`src/migrate_dialog.rs`、`jd import`） |
| 启动 targets/profiles（预构建二进制、workspace apps 与 examples、feature flags、默认 profile） | 🟡 | target 四维已落地（功能 #3 loop/run-targets，任务 1 `899a8f27` + 任务 2 `751bb6b6` + 任务 3 提交见 `loop/reports/feature-03-t3-report.md`）：`jackdaw.toml` `[[run]].target = { bin/example, package?, features?, profile? }`（`crates/jackdaw_pie_protocol/src/manifest.rs` RunTarget + `crates/jackdaw_project_build/src/run_manifest.rs` CLI 读取器）；构建透传与产物过滤（`binary.rs` `cargo_target_args`/`WantedArtifact`）；PIE 缓存按 target 分键（`src/pie.rs` BuildKey）；Play 徽标（`src/pie_menu.rs`）；`jd run/build --config` + doctor 预检（`crates/jackdaw_cli`，crate 名 jackdaw_cli_internal）；heavy smoke `tests/bsn_game_run.rs` example 端到端；文档 `book/src/user-guide/play-in-editor.md`「Run targets」+ `reference/configuration.md`。缺的半：**预构建二进制缓存管理（非技术用户直启，prebuilt binaries）未做**——现状 `.jackdaw/target/game` 只有隐式 cargo 缓存，无跨 target 产物登记/复用；target 自动发现 UI 亦未做（首版手写 manifest） |

### Stage 6 定制即无障碍（2 ✅ / 1 🟡 / 1 ❌）

| Roadmap 项 | 状态 | 证据 |
|---|---|---|
| 偏好设置（热键重绑/相机控制/首选语言/隐藏显示 widgets） | 🟡 | 热键重绑 ✅（`src/keybind_settings.rs`）；相机控制 ✅（`src/camera_settings.rs`，存 `.jackdaw/settings.json`）；首选语言 🟡（`crates/jackdaw_localization` 的 SelectedLocale 存在，但 locales 仅 en-US 一种）；隐藏显示 widgets ❌（无面板显隐偏好证据）。半缺：语言仅一方言、widgets 显隐无偏好入口 |
| 面板布局跨会话持久化 | ✅ | `crates/jackdaw_panels/src/workspace.rs:90-137`（WorkspacesPersist/WorkspacePersist，merge 语义）；序列化进场景文档：`src/scene_io/save.rs:516`、`src/lib.rs:3447-3462` 反序列化；另有用户级 `src/viewport_settings.rs`（config 目录 viewport.json）。注：存于场景文档而非独立用户 prefs，语义与 roadmap 的「用户偏好」有偏差（见裁决项 4） |
| 主题化 UI（亮/暗模式） | ❌ | `src/lib.rs:554` 仅 `insert_resource(UiTheme(create_dark_theme()))`（上游 bevy feathers 暗色主题）；全仓无 light theme/dark mode 切换实现（rg 无匹配） |
| 本地化框架（第一方英语） | ✅ | `crates/jackdaw_localization`（LocalizationPlugin/SelectedLocale/LocalizedText，fluent 栈：根 Cargo.toml fluent/unic-langid/sys-locale）；`src/locales/en-US`；UI 侧已接入（workspace_dropdown、status_bar 等） |

### 未分类（5 ✅ / 6 🟡 / 12 ❌）

| Roadmap 项 | 状态 | 证据 |
|---|---|---|
| 亮色主题 | ❌ | 同上：仅暗色（lib.rs:554 + tokens.rs 全部暗色常量） |
| system stepping 支持 | ❌ | 全仓无 bevy_stepping/stepping 匹配 |
| 编辑器内代码热补丁 | ❌ | 无实现；`crates/jackdaw_rustc_wrapper` 是扩展构建的 rustc 拦截器（非运行时热补丁） |
| 编辑器扩展 | ✅ | `crates/jackdaw_extension` + `jackdaw_api`/`jackdaw_api_internal`/`jackdaw_api_macros` + `jackdaw_loader`（signed `.jdext` 安装、启停、卸载，README；`src/extensions_dialog.rs`） |
| 扩展与资产中心 | 🟡 | 有包机制：`crates/jackdaw_package`（.jdext 打包/安装）、`src/extensions_dialog.rs`（列表 + 本地 install）。缺的半：无中心化 registry/市场浏览 |
| 各类性能 overlay | ✅ | `src/fps_overlay.rs`（fps+帧时图+场景统计）、`src/perf_probe.rs`（JD_PERF_PROBE per-schedule CPU 分片）、`src/render_diagnostics.rs`（GPU per-pass）、`src/remote/debug/diagnostics.rs`（远程游戏诊断+sparkline） |
| system graph 可视化（按数据访问/按 system set/影响选中实体的过滤） | ✅ | 功能 #4（loop/system-graph）：BRP 访问表数据链（d914073e：`crates/jackdaw_remote/src/ecs_methods.rs` 每系统 `accesses` 读/写/archetypal/unbounded + 顶层 `access_reported` 能力标志，`systems_with_access()` 通路）+ depgraph 组件访问过滤/着色/From-selection 反查（88968fcf：`src/remote/debug/depgraph.rs` `AccessFilter` AND/OR 匹配+短名兜底、命中高亮/非命中暗化、`selection_components` 两级取值）+ schedules 徽标、断连/老游戏两态降级措辞、book `user-guide/remote-debugging.md`（任务 3，提交见 `loop/reports/feature-04-t3-report.md`）。既存底盘：分层依赖图+调度歧义红边（`depgraph.rs`/`graph.rs`）、两面板 system set 归属 chips（`schedules.rs`）。备注：set 维度**过滤动词**未单独落地（set 归属显示已有），留 backlog（主控裁定口径） |
| Tracy 运行时 profiling | ❌ | 全仓无 tracy 匹配；bevy workspace features 未含 trace 相关 |
| 基于 BRP 的分进程模型调研 | ✅ | 已落地（超出调研）：`crates/jackdaw_remote`（BRP server：bsn_methods/ecs_methods/diagnostics）+ `src/remote/`（BRP client 调试面板族）；PIE 走自研 ipc 协议（`jackdaw_pie_protocol`） |
| 代码热重载与动态链接调研 | ✅ | 已落地：`crates/jackdaw_sdk`/`jackdaw_dylib`（SDK dylib、TypeId 跨 dlopen 一致），Windows PE 导出上限问题与拆分方案成文于 open-challenges |
| 动画图编辑器 | 🟡 | `crates/jackdaw_animation`（blend_graph/timeline/sheet/toolbar/player）+ `src/inspector/animation_graph_card.rs` + `jackdaw_animation_runtime`。open-challenges 自述「Started, not finished」 |
| 粒子特效编辑器 | ❌ | open-challenges「Not started」 |
| tilemap 支持 | ❌ | 全仓无 tilemap 匹配 |
| .bsn AST 编辑 | 🟡 | 活文档即 BSN AST：`src/undo_in_place.rs`、`undo_snapshot.rs`（BsnDocumentSnapshotter）、open-challenges「the live in-editor document is the BSN AST」。缺的半：无 .bsn 文本/AST 源码级编辑视图 |
| 游戏内 dev console | ❌ | 无匹配（`src/editor_log.rs` 是日志文件，`src/scrolling_log.rs` 是滚动日志面板，非交互 console） |
| MaterialX 材质创建器 | ❌ | 全仓无 materialx 匹配 |
| 基础音频编辑 | ❌ | 无音频编辑（feathers 亦无音频播放 widget；audio 命中仅为资产类型枚举等） |
| 组件值图形可视化 | 🟡 | 基建已有：`src/remote/debug/sparkline.rs`（RingBuffer+SparklineMaterial，UiMaterial 绘图）+ shaders/sparkline.wesl，现仅用于诊断指标。缺的半：未接入 inspector 组件值的时间序列绘图 |
| 实体聚类与内存用量分解 | 🟡 | `src/remote/debug/archetypes.rs`（archetype 可排序表，BRP `jackdaw/archetypes`）。缺的半：无内存用量维度 |
| Component/Resource/Event 类型编辑器内生成文档 | 🟡 | bevy `reflect_documentation` feature 已开（根 Cargo.toml workspace features）；`src/inspector/type_metadata_pane.rs`、`component_tooltip.rs` 呈现 doc。缺的半：无系统性「类型文档页」（尤其 Resource/Event 覆盖未证实） |
| go to definition 打开 IDE | ❌ | 无匹配 |
| 事件诊断 | ❌ | `remote/debug/diagnostics.rs` 是性能诊断（fps/帧时/实体数）；无 Event 流观察面板 |
| 集中设计方法论 | ❌ | book 无 design methodology 章节；仅 README 引用 Figma 链接 |

---

## 2. 设计原则摘要

### vision.html 要点（≤5）

1. 定位是「Valve Hammer 而非 Rust 版 Unity」：不做一体化大而全应用，不取代 Rust 代码。
2. 解决纯代码工作流痛点：美术/设计师依赖程序员集成内容、定制工具链缺失、Rust 编译时间拖慢迭代型任务（UI/光照微调）。
3. 工具链协作枢纽：用户在喜爱的 DCC 软件创作资产，编辑器负责 Bevy/游戏专属修改、快速调整、测试与调试。
4. 可定制性是核心：按项目/角色安装扩展、定制工作区、自写扩展。
5. 立足 Bevy 既有优势：ECS 快速灵活、极致模块化、Rust all the way down。

### architecture.html 要点（≤5）

1. 编辑器是用 Bevy + bevy_ui 构建的普通二进制，最终须进主仓库随引擎同步演进。
2. 依赖约束：编辑器不能依赖任何反向依赖 bevy 的 crate（须跟得上 main）。
3. 功能分层复用：项目创建等放 bevy_cli 由编辑器调用；widget/undo-redo/偏好/viewport/节点图等先在编辑器内原型化，成熟后拆独立 crate；自包含 GUI 工具做成可复用 Plugin。
4. 编辑器不靠检查运行中进程工作；鼓励用户经 `dev_tools` feature 把模块化工具编进自己项目。
5. 开放问题：分发方式、编辑器↔游戏通信（含自定义类型）、undo/redo 模型。

### Jackdaw 的对齐 / 偏离

对齐点：
- **operator 范式超出文档设想**：CONTRIBUTING 的带 id operator（按钮/菜单/快捷键/命令面板/远程 API 共用）正是「一切修改可 undo、可脚本化」的统一抽象，架构文档尚停留在「undo-redo 待设计」。
- **分层复用做得非常彻底**：49 个 crate 把 widgets/feathers/panels/undo(commands)/schema/animation 拆出为独立可复用 crate，正对「成熟后拆 crate」原则（甚至一步到位）。
- **扩展体系**（.jdext 签名包、SDK dylib、TypeId 跨 dlopen 一致）兑现了「可定制性」愿景。
- **独立于引擎仓库**：现阶段作为仓库外项目按需跟踪 bevy main（git branch = "main" 依赖），符合过渡期安排。

偏离点：
- **不用 bevy_cli**：自建 `jd` CLI + `jackdaw_project_build` 构建管线（roadmap Stage 3「编辑器可调用 bevy_cli」因此 ❌）。
- **进程模型偏离「dev_tools 编进游戏」**：Jackdaw 选择 PIE 进程外运行（自研 ipc 协议）+ 编辑器侧 BRP server，而非把工具编进用户项目；官方分进程调研项反而被 Jackdaw 提前落地。
- **主题基建薄**：颜色大量是编译期 const（tokens.rs）+ 上游 feathers 单暗主题，未形成官方设想的「主题化 widgets / 亮暗 / 规范」层。
- **场景格式先行**：自研 .bsn（AST 活文档）作为作者格式，官方 .bsn 尚在演进（open-challenges「Upstream BSN alignment」）——方向押注一致但需持续对齐上游。

---

## 3. 选题备选清单（重点）

> 从 ❌/🟡 中按「高价值、可独立验收、一个 Loop 迭代能吃完或可明确拆分」筛选，按建议优先级排序。规模：S（~数百行）/ M（千行级）/ L（多迭代）。

### 备选 1：亮色主题 + 主题切换（Theme: Light/Dark）
- **Roadmap 映射**：Stage 6「主题化 UI（亮/暗模式）」+ 未分类「亮色主题」+ Stage 4「默认主题书面/视觉规范」（顺带补规范文档）。
- **用户价值**：亮环境用户/无障碍诉求的一键明暗切换，编辑器完成度观感的大头。
- **范围草案**：做到——`UiTheme` 运行时切换 operator + 设置持久化（viewport_settings 模式）；tokens.rs 常量改主题资源驱动（或引入 theme-aware token 查询）；亮色 palette 调一版；book 补「主题规范」简文。不做——第三方自定义主题/主题市场。
- **预估触碰 crate**：`crates/jackdaw_feathers/src/tokens.rs`（重点）、`src/default_style.rs`、`src/lib.rs:554`、`src/viewport_settings.rs`、若干直接引用常量的 UI 模块。
- **风险**：技术低（bevy feathers 本身有 light/dark 两套 theme 构造器，UiTheme 是运行时资源）；**审美风险高**（亮色配色需用户过目，见裁决项 1）；const 颜色引用点分散，改造面可能比预估大。
- **规模**：M。

### 备选 2：Resource Inspector（资源检查与编辑面板）
- **Roadmap 映射**：Stage 1「资源可检查」❌ + Stage 2「增删资源/改资源值」❌（后两条同链路顺带解锁）。
- **用户价值**：补齐 ECS「实体/组件/资源」检查闭环，游戏调试（时间/重力/自定义 GameState）直接可读可改。
- **范围草案**：做到——新 dockable 面板：枚举 type registry 中 world 已实例化的 Resource（PickerDenylist 同款过滤），选中用 `reflect_fields` 现成渲染显示值；改值走 operator（`allows_undo` 默认 true，自动获得 undo）；增删资源限定为「可 Default 构造的注册类型」的 insert/remove。不做——PIE 远程 Resource 编辑（后续可挂 BRP 通道）、Event 显示。
- **预估触碰 crate**：`src/inspector/`（复用 reflect_fields/val_field/component_picker 模式）、`crates/jackdaw_panels`（面板注册）、`src/lib.rs`（面板清单）。
- **风险**：低。范式全有现成（component 面板即模板）；主要风险是 Resource 数量噪声（denylist 需整理）与个别不可反射友好类型的渲染 fallback。
- **规模**：M（偏小）。

### 备选 3：Run targets / profiles（多目标启动配置）
- **Roadmap 映射**：Stage 5「启动 targets/profiles（workspace apps 与 examples、feature flags、默认 profile）」🟡。
- **用户价值**：cargo workspace 多 bin/examples 的真实项目可在 Play 下拉直接切换启动目标（现固定同一游戏二进制，manifest.rs:13 注释自认）。
- **范围草案**：做到——`jackdaw.toml` 的 RunConfig 增 `target`（bin/example 名 + 可选 features + profile），`jackdaw_project_build` 构建命令按 target 透传；Play 下拉与 `jd run` 对齐；无 target 字段时保持现行为（合成默认）。不做——预构建二进制缓存管理、target 自动发现 UI（首版手动写 manifest 即可）。
- **预估触碰 crate**：`crates/jackdaw_pie_protocol/src/manifest.rs`、`crates/jackdaw_project_build`、`src/run_config.rs`、`src/pie.rs`、`crates/jd`。
- **风险**：中。构建参数组合的测试矩阵；Windows 构建慢导致验收周期长；需 fixture 工程配合（tests/ 下已有 fixtures 模式）。
- **规模**：M-L。

### 备选 4：可全屏面板（Panel Maximize/Fullscreen）——✅ 已落地（功能 #2，Stage 4 行已改 ✅）
- **Roadmap 映射**：Stage 4「可全屏面板」~~❌~~ ✅（任务 1 `92ff0049` + 任务 2 图标入口/文档）。
- **用户价值**：视口/检查器/动画时间线一键放大到整个工作区（Blender/Figma 皆有），小屏用户刚需。
- **范围草案**：做到——`jackdaw_panels` 树上对当前激活叶面板 toggle 最大化（operator + 快捷键，如 Shift+Space），布局栈保存/恢复原树；workspace 持久化兼容。不做——多面板分屏全屏、浮动窗口。
- **预估触碰 crate**：`crates/jackdaw_panels/src/tree.rs`、`layout.rs`、`src/dock_ops.rs`、`src/panel_focus.rs`。
- **风险**：低-中。与 dock reconcile/持久化的交互是唯一复杂点；验收可 headless 测树变换。
- **规模**：S-M。

### 备选 5：System Graph 增强（按数据访问着色/过滤 + 选中实体反查系统）——✅ 已落地（功能 #4，未分类行已改 ✅）
- **Roadmap 映射**：未分类「system graph 可视化」🟡（补齐缺的半）。
- **用户价值**：从「能看图」升级到「能定位」——哪个系统读写了 Transform？选中实体被哪些系统影响？
- **范围草案**：做到——BRP `jackdaw/schedules` 回复已含依赖/歧义，扩展协议带各系统 param 访问表；depgraph 节点按组件访问着色 + 组件名过滤；「选中实体→其组件集合→相关系统」过滤入口。不做——数据流动画、性能采样。
- **预估触碰 crate**：`crates/jackdaw_remote`（方法扩展）、`src/remote/debug/depgraph.rs`、`schedules.rs`、`graph.rs`。
- **风险**：中。BRP 载荷变大（需抽样/懒加载）；游戏侧需配合暴露 param 信息（jackdaw_runtime 侧改动）。
- **规模**：M。

### 备选 6（备选池）：键盘 UI 导航补全（Stage 3 🟡）
- 映射 Stage 3「键盘 UI 导航」。价值：无障碍主干。范围：tree_view/list_view/menu_bar/picker 的箭头+Enter+Tab 焦点循环，集中 focus 管理模块。触碰 `jackdaw_feathers`、`jackdaw_widgets`、`src/keybind_focus.rs`。风险：bevy input_focus 能力边界需先探。规模 M。

### 备选 7（备选池）：资产热重载工作流收口（Stage 3 🟡）
- 先做一轮真机验证（改纹理/网格→视口与 inspector 是否更新），按结果决定补 watcher 还是仅补文档与设置开关。触碰面小但验收依赖人工观察，自动化弱。规模 S-M。

**不建议本轮做**（未分类 L 级大件）：粒子特效编辑器、tilemap、MaterialX、音频编辑、dev console、Tracy、代码热补丁、go to definition——或未启动、或依赖大基建、或官方 roadmap 亦列为远期；建议保持 backlog，待主干（Stage 4/5/6 缺口）清完再议。

---

## 4. 功能 #1 推荐

### 推荐：备选 2 —— Resource Inspector（资源检查与编辑面板）

**理由**：
1. **主干缺口**：Stage 1 是官方 roadmap 的地基 Stage，「资源可检查」是其中唯一 ❌，且直接连带 Stage 2 两条 ❌（增删资源/改资源值）——一次选题补三行盘点，是主干线上含金量最高的洞。
2. **范围可控可自动验收**：渲染复用 `reflect_fields` 现成链路、交互复用 operator + undo 现成范式（CONTRIBUTING 明文：`allows_undo` 默认即得 undo）；headless 集成测试可覆盖「列出→显示→改值→undo round-trip」，不依赖人工目检，也不需要新基建。
3. **不依赖大基建、不动构建链**：纯编辑器侧面板，对比备选 3（构建矩阵）与备选 1（分散常量改造+审美裁决）风险最低；对比备选 4 体量略大但价值密度高得多。
4. 与作者自述的扩展哲学一致：做成可复用面板（jackdaw_panels 注册），将来 PIE/BRP 通道可直接复用同一渲染。

**任务拆分草案（1–3 个任务）**：
- **任务 1（程序）**：Resource 浏览面板骨架——枚举 world 中已实例化的 Resource 类型（含 denylist 过滤，参照 `component_picker.rs` 的 PickerDenylist 模式），dockable 面板 + 选中后复用 `reflect_fields` 渲染只读值；含基本单测（枚举过滤纯函数）。
- **任务 2（程序）**：编辑链路——`resource.set_value` 类 operator 改值（走 CommandHistory/快照获得 undo），`resource.insert` / `resource.remove`（限可 Default 构造的注册类型）；面板 UI 接 operator 按钮（ButtonProps::from_operator）。
- **任务 3（QA + 文档）**：headless 集成测试（列出/显示/改值/undo round-trip/增删）、book `user-guide` 补「Resources 面板」一节、盘点表三行状态更新。

## 5. ⚠️ 需用户裁决项

1. **亮色主题配色**（若做备选 1）：亮色 palette 由用户给参考（截图/色板）还是程序自行调一版后给用户过目？影响是否可纯自动验收。
2. **Resource Inspector 显示范围**：全部已实例化 Resource（信息全但噪声大，需 denylist 维护）vs 仅项目定义类型 + 白名单常用引擎类型（首版干净但覆盖窄）。本策划倾向后者起步。
3. **Run targets 首版形态**（若做备选 3）：仅支持手动在 `jackdaw.toml` 写 target，还是要求 UI 自动发现 workspace 的 bins/examples？前者快但体验糙。
4. **面板布局持久化归属**：现布局存进**场景文档**（`scene_io/save.rs:516`），与 roadmap「跨会话用户偏好」语义有偏差（换场景即丢布局、也无法按用户共享）。是否安排一次「布局迁移到用户级 prefs」的专项？影响备选 4（全屏面板）与后续主题/偏好工作的存储路径设计。

---
*盘点依据快照：仓库 main 分支（2026-10-22），bevy git main 依赖，49 workspace crate。所有结论均可由文中路径复核；标注「未证实」处需真机/后续验证。*
