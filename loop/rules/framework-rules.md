# Jackdaw 代码框架规则（新增功能框架验收标准）

> 生效：2026-11-09（用户指令：后续新增功能按本规则做框架验收，不得突破框架限制）。
> 适用范围：全部新增功能/修复/重构；上游同步按其自身政策执行，但**同样不得使本规则
> 的既有守卫变红**（上游引入的破坏按融合政策处理并记档）。
> 每条规则标注【验收方式】：M=人工 review 项（策划/程序/QA/主控检查），A=自动化守卫
> （已存在的测试/门禁，必须持续绿）。新增需要强制的规则时应同步新增守卫测试。

## R0 圈层与依赖方向（不可协商）

依赖方向唯一合法：**装配层(src/) → 编辑器核心(editor/jackdaw_editor_core) → 编辑器功能
域(editor/jackdaw_editor_*) → 游戏/共享运行时(crates/jackdaw_{runtime,scene_types,
pie_protocol,remote,commands,api*}) → 领域内核(crates/jackdaw_{terrain,tilemap,geometry,
…}) 与 UI kit(feathers/widgets/panels)**。禁止任何反向依赖。

- R0.1【M+A】游戏侧 crate（runtime 及游戏模板依赖清单）**禁止依赖** editor_core/
  editor_*/feathers/panels（widgets_runtime 的 feathers feature 除外，属共享 UI 数据面）。
  验收：`cargo tree` 抽查 + `tests/fixtures/bsn_game` 真实构建（含 modules.json 各开关组合）。
- R0.2【M】编辑器专属类型**不得**放入共享运行时 crate（scene_types/runtime）。确需
  「编辑器有、游戏不读」的作者类型放 scene_types 时，必须 `#[reflect(@EditorHidden)]`
  且在文档注释里论证为何不能放编辑器 crate（先例：`Locked`——save filter 剔除
  `jackdaw::` 前缀、类型必须随文档存活）。
- R0.3【M+A】领域内核 crate（⑤）**禁止**出现编辑器 UI/面板/菜单代码；纯算法+数据。
- R0.4【M】根包 `jackdaw`（src/）保持薄外壳：只允许 plugin group 组装、re-export、
  测试助手与二进制入口；新功能逻辑一律进 ②③ 或新 editor crate。
- R0.5【M】新功能域默认新建 editor crate（先例：#762-769 七件套）；core 内加模块仅限
  与既有 core 模块强耦合的小面，且必须在报告里说明为什么不独立成 crate。

## R1 Operator 纪律（能力最小单元）

一切用户可触达的能力必须以 Operator 形态存在（自动获得键位/菜单/BRP 远程/测试四个
驱动面）。直接写 system 吃输入而绕过 operator 框架 = 突破框架。

- R1.1【M+A】`#[operator]` 必须显式声明：`id`（`域.动作` 命名）、`is_available` 谓词
  （Selection/模式门）、`allows_undo`、`writes_disk`（写盘者 true）。缺省即违规，
  census 守卫（record_counts 的 SELF_PUSHING 表、remote_batches 的写盘/换页开关表、
  authoring_ops 的 ENTITY_PARAM_OPS 分类表）必须同步登记。
  验收：`authoring_ops::every_entity_taking_operator_is_classified` 等 census 全绿。
- R1.2【M】自推历史的算子（自己 `push_executed`）必须 `allows_undo = false`，否则
  dispatcher 快照+自推=一动作两记录（Y1 病灶）。先例：clip.delete/paste（A 轮补声明）。
- R1.3【M】一键一 entry：一次用户动作恰好一条 undo 记录；**禁止新旧值全等的垃圾
  entry**（R5 先例：拒绝路径不得写 undo/不得置 dirty）。
- R1.4【M】算子的拒绝必须结构化：`Cancelled` + `OperatorWarnings`/toast 通道给用户
  可见理由（先例：R5 地形拒绝、R8 凹笔刷拒绝）；**禁止静默 Cancelled 无任何反馈**。
- R1.5【M+A】新算子必须带测试锚（headless 单测或 guards），并检查是否需要进
  creation_taxonomy（Add 菜单）与 book 文档。
- R1.6【M】算子命名空间按功能域（terrain./brush./tilemap./entity./clip./pie.…），
  跨域借用算子须在方案书里论证。

## R2 文档-世界分离（AST 真理之源）

`.bsn` 文档（SceneBsnAst）是作者态真理之源；ECS 世界是投影。**只改 ECS 不回写文档 =
突破框架**。

- R2.1【M+A】一切对作者实体的编辑必须最终落到 AST：直接改 ECS 的路径必须经
  `sync_component_to_ast`/`sync_hierarchy_to_ast` 或注册路径（`register_entity_in_ast`）。
  验收：keyframe_undo/dirty_matrix/reference_* guards 全绿。
- R2.2【M+A】load 不回写文档（#793 语义）：加载是纯投影，禁止在 load 路径写盘/写
  dirty 基线。验收：`play_saves_nothing`/`scenes_swap` 系列。
- R2.3【M】undo 统一走 `EditorCommand`（execute/undo 对）或 CommandGroup；禁止在
  operator 里手搓分离的 undo 逻辑。
- R2.4【M+A】删除/晋升等改变实体集合的操作必须走文档感知路径
  （`despawn_scene_entity`/`register_entity_in_ast`，R1 语义先例）——裸 despawn 会留
  幽灵 AST 节点被快照 undo 复活。验收：keyframe_undo guards。

## R3 Extension 与注册纪律（防死代码）

- R3.1【M+A】新功能域 = 新 editor crate 或 core 内模块，且**必须接线**：plugin 加入
  `JackdawEditorPlugins`（src/lib.rs）或算子经 `add_to_extension` 注册进 core_extension；
  禁止「pub mod 声明了但无任何接线」的死模块入库（先例：本地 tilemap 两模块因上游
  #762 取代而被整删的教训）。
- R3.2【M】扩展的 feature gate 用 `#[cfg(feature = "…")]` 局部化在注册点旁
  （multiplayer/camera_rig 先例），不许 cfg 散布实现体。
- R3.3【M+A】扩展注册的算子必须过 census（作者分类表会逐一对照实际注册表——漏分类
  即红）。
- R3.4【M】删除功能域时必须连同：注册点、census 表行、taxonomy 行、测试锚一起删
  （先例：第三轮同步本地 tilemap 簇整删），并在台账记档取代关系。

## R4 Runtime/Editor 独立

- R4.1【M+A】PIE 通信只走 `jackdaw_pie_protocol`（IPC 帧/ControlEvent/StateEvent/
  SceneAnswer）；游戏世界查询只走 BRP（`jackdaw/scene_snapshot`/`ecs_methods`）。
  禁止新增任何「编辑器直接引用游戏进程内部」的通道。
- R4.2【M】运行时实体→作者实体的晋升（Save to Scene / promote）必须经过
  `should_skip_component` 复用 + 关系内件/逐帧字段过滤（LT10 语义先例）——运行时状态
  不得污染文档。
- R4.3【M】游戏侧代码不得出现编辑器符号；编辑器侧不得 `unsafe` 穿透游戏进程。
  跨进程问题一律：协议新方法（#804 先例）或 BRP 新方法。
- R4.4【M+A】编辑器专属组件不得被游戏反序列化路径看见（save filter 保证）；新增
  `jackdaw::` 前缀外的编辑器侧类型若可能出现在文档里，必须论证类型路径稳定性。
- R4.5【M】类型跨 crate 迁移/改名必须同步 `jackdaw_bsn::migrate::MOVED_TYPES`
  （#761 机制）；**禁止用「改类型名+不迁移」的方式消解合并/重构冲突**（TilemapGridLayer
  事故先例：毁掉全部已存文档的 layers）。

## R5 并发与 IO

- R5.1【M+A】后台线程**禁止触碰 World**：结果以 Task/消息回流，主线程 poll 系统收割
  （先例：spawn_game_build 的 AsyncComputeTaskPool、save_worker、ServingScene）。
- R5.2【M+A】项目文件写盘一律 `write_atomic`/`write_durable`（唯一临时名+rename）；
  **禁止裸 `std::fs::write`/`File::create` 落项目文件**（jsn_to_bsn 先例走 stamped
  atomic write）。临时文件必须可被 `is_temporary_name` 清扫器识别。
- R5.3【M】主线程禁止阻塞式 IO/长计算（>帧预算）：下沉 worker + continuation 形态
  （`AfterSaves`/`launch_after_saves` 先例）；**禁止 sleep/轮询硬等待**，等待一律用
  完成信号原语（`wait_for_saves` 先例）。
- R5.4【M】新并发资源需 NonSend/Send 标注审查（PieSession 先例）；锁只用于短临界区
  进度共享（`Arc<Mutex<BuildProgress>>` 先例），不得持锁跨 await。
- R5.5【A】测试竞态：凡依赖异步落盘/线程完成的断言必须用等待原语；并行间歇红按
  A28 族记档并给单跑绿证据。

## R6 序列化与资源

- R6.1【M+A】大块数据不进文档：走 sidecar（`.jdtiles` 先例），文档只存 `data_path`；
  派生/粘贴必须 fork 侧车（`ensure_paths`），坐标/范围越界必须有闸（R6 位置闸先例）。
- R6.2【M】新持久类型 = `Reflect` + `Default` + `register_type` + 稳定 saved type path；
  字段新增必须保默认可反序列化（旧文档可读）。
- R6.3【M+A】资产引用的改名/移动/删除必须走 `reference_rewrite`/`asset.rebind` 通道；
  禁止裸改路径字符串。验收：reference_rewrite/audit guards。
- R6.4【M+A】保存语义=紧凑形（缺省省略）+ 文档指纹维护（settle 双臂保持本地基线字段
  与上游机制的共存）；新增 Tab 字段必须并入 settle 路径（先例：#799 merge 的双臂）。
- R6.5【M】运行时数据不得写入文档（#806 revert 语义、LT10 过滤先例）；「内容 vs 旗标」
  dirty 语义分歧走设计轮（A30/A31 先例），不得在算子层私自定语义。

## R7 UI 纪律

- R7.1【M】UI 一律 feathers token + widgets/panels 组件；功能 crate 内禁止手写颜色/
  字号/间距常量。
- R7.2【M】新面板/窗口必须经 layout 注册 + 算子开关（A22 教训：窗口必须有 operator/
  命令面板入口，禁止只能改 project.json 才能打开）；新实体类型必须登记
  creation_taxonomy（Add 菜单）。
- R7.3【M+A】编辑器 chrome 不得泄漏进 scene_tree/场景快照（chrome 拒绝语义）。
  验收：editor_remote guards。
- R7.4【M】交互类功能验收必须含真机腿（MCP 优先：ui_tree/BRP/算子驱动；坐标注入仅
  兜底）——loop/README.md 既有契约。

## R8 门禁底线（不可协商）

- R8.1【A】fmt / clippy `-D warnings` / libtests 全绿；`--test editor guards::` 全绿；
  六模块单跑无**新增**红。
- R8.2【A+M】已知预存红清单（A28 族 stage footer/gltf 并行间歇、A30、A31、viewport
  quality menu）由台账维护；**新增红必须当轮修复或立票**，禁止静默接受。
- R8.3【A】已闭环修复的守卫（R4-R8 系列、dirty_matrix、keyframe_undo、reference_*、
  atomic_writes、census 三表）必须持续绿——**回退修复 = 突破框架**。
- R8.4【M】基线数字变化必须拆账（新增/删除测试逐项对得上，禁止「总数对了就行」）。

## R9 验收流程（怎么用这份规则）

1. **策划**：方案书必须含「框架影响面」小节——列出触碰的圈层/R 条目与计划中的守卫更新。
2. **程序**：实现自检按 R0-R7 逐条过；长命令后台+轮询；范围红线在方案书内。
3. **QA**：门禁亲跑（日志全文复核制）+ 按 R1-R7 的【M】项逐条 review + 真机腿；
   发现规则违反 → FAIL 阻断，报主控。
4. **主控终审**：例外处理——确需突破框架限制的（如上游主线翻案、取代式删除），必须在
   方案书/报告里**显式记档**（哪条规则、为何、取代关系），并经用户确认重大项；静默突破
   一律返工。
5. **上游同步**：按同步政策执行（上游主线），但同步后本规则全部【A】守卫必须恢复绿；
   上游造成的破坏按融合政策修复或记档立票。
6. 本规则的修订：修改须在台账记档（改了哪条、为何），并同步知会 QA 检查清单。

## 附：快速自检清单（程序提交前逐条勾）

- [ ] 依赖方向没有新增反向边（R0）
- [ ] 新能力以 operator 暴露且四声明齐全、census 表已登记（R1）
- [ ] 编辑落 AST、undo 走 EditorCommand、无垃圾 entry（R2）
- [ ] 新模块有接线、无死声明（R3）
- [ ] 游戏/编辑器边界未穿透、晋升有过滤（R4）
- [ ] 后台线程不摸 World、写盘原子、无 sleep 等待（R5）
- [ ] 大数据走 sidecar、持久类型路径稳定、引用走重写通道（R6）
- [ ] UI 走 feathers、面板有 operator 入口、chrome 不泄漏（R7）
- [ ] 四门+六模块无新增红、基线拆账、已知红清单未变长（R8）
