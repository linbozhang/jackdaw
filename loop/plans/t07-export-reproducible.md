# T07 导出安全与可复现构建 — 实施方案

> 策划产物（2026-10-26，基于本地 main **d4d49dca**（T06 闭环点 = P0 收官前最后基线）全量代码核实，只读调研；
> 并行的 N10 修复在分支 loop/n10-play-freeze 上进行，本方案不依赖其结果）。需求来源：
> `loop/plans/roadmap-game-dev.md` T07。**验收原文**：临时目录打包后替换（失败保留旧产物）；
> 保护非本工具目录；统一 --locked 锁定策略；导出→挪目录→异目录启动的最小自动化回归。
> （export.rs:168 现先清空再拷、binary.rs 无 --locked 为切入点。）
> buglist 吸收 **R9、R10、Y7**（progress 台账映射写的是「R10/Y7/W9」——W9 已被 T04-T1 修复打钩，
> 本任务只核验；R10 原文=staging 硬编码 assets 目录，**不是**构建面板空白——面板空白是 **R9**，
> 属导出 UX 排障面，本方案一并吸收）；新发现编号 **N1–N10**（沿用 T03–T06 命名风格）。

---

## 0. 架构事实（核实结论，方案的地基）

**导出链是功能#7 建立的「两入口一核心」结构，核心是纯函数 crate**：

- **核心**：`crates/jackdaw_project_build/src/export.rs`（bevy-light，无编辑器依赖）。
  `plan_export(root, profile, binary, out)` 构造 `ExportPlan {profile, dist_dir, exe_source,
  assets_source}`（`export.rs:51-62`）；`stage_export(plan)` 执行（`export.rs:168-225`）：
  **前置校验（exe 存在/assets 存在/路径护栏）→ `remove_dir_all(dist)` 清空 → `create_dir_all`
  → `copy_tree(assets)` → `copy(exe)`**——先 assets 后 exe 的次序有设计意图（exe 拷失败不会被
  误当完整导出），但「先清空」正是 roadmap 点名的缺口。护栏现状（功能#7 QA 修复轮 hardened）：
  `normalize_staging_dir` 拒相对路径、`dunce` 剥 verbatim 前缀、拒残留 `..` 组件
  （`export.rs:266-283`）；`staging_hazard` 拒文件系统根/包含源目录/嵌套源内
  （`export.rs:242-253`）——**全部基于 `Path::starts_with` 的字节比较，大小写敏感**。
- **两入口**：CLI `jd export`（`crates/jackdaw_cli/src/lib.rs:771-858`：`validate_export_out`
  在构建前预校验 `--out` `:897`；`--config/--profile` 解析、dylib 拒收 `:827-832`、成功打印
  路径并 `reveal_in_file_manager`）；编辑器 `game.export`（`src/game_export.rs:74-77` operator →
  `start_game_export :82-110`：extension 项目拒绝、`save_scenes_before_launch` 先存场景、
  `shim_spec_for_project` → `spawn_export_task :116-151` 后台任务（release+`BuildLoad::Background`，
  footer `BuildStatus` 进度）→ `poll_game_export :156-185` 汇报成功/失败）。单导出互斥已有
  （`GameExports.task`，`game_export.rs:56-61` 的 is_available 门）。
- **构建管线**：`crates/jackdaw_project_build/src/binary.rs` 的
  `build_project_binary_with_load`（`:264-369`）是 Play / `jd build` / `jd run` / 导出共用的
  唯一 cargo 入口；argv 由纯函数 `cargo_build_argv`（`:224-237`）拼装：`build -p <pkg> [target
  flags] --target-dir <dir> --message-format=json`——**无 `--locked`**（roadmap 第二切入点证实）。
  构建前先跑 `bevy_source::pin_project`（`binary.rs:288-292` → `bevy_source.rs:63-99`）：编辑器
  跟踪 bevy main 时**主动 `cargo update --package bevy --precise <BEVY_REV>` 改写用户工程
  Cargo.lock**（对齐编辑器类型；scaffold 生成的 bevy 注释明说 "The editor moves the lockfile
  back to it before each build"，`jackdaw_scaffold/src/lib.rs:2505-2508`）。pin 失败仅 warn 继续。
- **可复现基座现状**：工具链——模板带 `rust-toolchain.toml.template`（专项#5 成果，写入
  jackdaw 自身 RUSTUP_TOOLCHAIN）；编辑器构建时 `detach_from_host_build` 清掉 `RUSTUP_TOOLCHAIN`
  等 15+ 变量（`binary.rs:513-539`），rustup 落到工程自己的 toolchain 文件——机制成立，但
  **存量工程无该文件时无任何提醒**。锁——`tests/fixtures/bsn_game/Cargo.lock` **已入库**
  （feature#3 QA 建议已兑现）；scaffold 新工程**不生成 Cargo.lock**（首建解析，上游漂移敞口，
  feature#3 期间的 E0308 上游漂移事故是真实先例）。
- **T04/T06 之后 assets/ 里多了编辑器私有产物（本任务新挖的衔接缺口）**：T04 的 `.bak` 单份
  轮转写在**目标文件同目录**（`jackdaw_api_internal/src/document.rs:96-99,153-155`），场景/
  prefab 都在 assets/ 内 → 保存过就有 `<name>.bsn.bak`；原子写 temp 残留 `.*.tmp-<pid>` 同理。
  T06 的 PIE temp 副本在 `<assets>/.jackdaw-pie/`（T06 决策 6 点前缀目录）。而 `copy_tree`
  （`export.rs:301-326`）**无任何过滤规则，全量拷贝**——.bak 与 PIE 运行副本（内含用户
  未保存场景内容）会进发布包。缩略图缓存安全（`<root>/.jackdaw/thumbnails`，
  `src/thumbnail.rs:456`，不在 assets）。
- **QA 工具面现状**：BRP 20 方法（`src/remote/server.rs:147-171`，含 `jackdaw/wait`/`pie`/
  `recovery`/`audit`）；`wait(until:"idle")` 的 busy 判定**已含 `BuildStatus::Building`**
  （`server.rs:1916-1932` `editor_is_busy`）→ 导出构建期间 idle 挂住、结束放行——**等待能力
  已就位**；但 `BuildStatus` 的 state/outcome/dist **不在任何 BRP 回复里**（`jackdaw/status`
  只有 `progress[EditorProgress]`/`pie`，`server.rs:476-509`）→ 「导出成功与否、落在哪里」
  无结构化断言通道。MCP 24 工具（T06 后，`crates/jackdaw_mcp`）无导出面。
- **heavy 测试现状**：`tests/` 下**无 export 测试文件**（功能#7 QA 🟡 backlog「导出 smoke 未
  自动化」未兑现；当时真机手工证据覆盖）。游戏 exe 带 `--jackdaw-extract-schema` 旗标
  （`jackdaw_schema::SCHEMA_FLAG`，`crates/jackdaw_schema/src/lib.rs:17`）：打印 schema 即退、
  不开窗——异目录启动自动化的现成断言器（`run_binary_extractor` 先例 `binary.rs:442-464`）。

---

## 一、现状与缺陷矩阵

### A. 导出安全（验收句①②：临时目录替换、失败保留旧产物、保护非本工具目录）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **N1** | 🔴 | **先清空后拷贝，失败/中断不保旧产物**。`stage_export` 对已存在的 dist 先 `remove_dir_all`（`export.rs:197-202`），随后才 create/copy：assets 拷到一半 IO 失败（磁盘满/目标被占/只读）、exe 拷失败（旧导出还在运行被锁）、或进程被杀——旧导出已删、新导出半截，「失败保留旧产物」完全不成立。功能#7 的「先 assets 后 exe」只防「半截被误认为完整」，不保旧 | `export.rs:197-217` 全序 |
| **N2**（=buglist Y7） | 🟡 | **护栏可被 Windows 大小写变体绕过**：`staging_hazard` 与 `normalize_staging_dir` 全部走 `Path::starts_with` 字节比较（`export.rs:246-251`），NTFS 大小写不敏感——`--project c:\game` + `--out C:\Game\assets` 两种拼写指向同一目录却比较不等，ContainsSource 漏判，`remove_dir_all` 删掉真正的 assets/（仅 CLI `--out` 暴露；编辑器 `out=None` 不受影响）。功能#7 修复轮 hardened 的是 verbatim/相对路径面，大小写未动 | `export.rs:242-253`；现有测试无大小写变体用例（`export.rs:486-538`） |
| **N3**（=buglist R10） | 🟡 | **staging 硬编码 `assets` 目录**：`plan_export` 写死 `assets_source: root.join("assets")`（`export.rs:60`），staged 目录名也写死 `dist.join("assets")`（`export.rs:208`）。项目配 `jackdaw.toml assets_dir = "content"`（编辑器资产服务器/索引全读它，`src/project.rs:55-61,139-145`）→ 导出报 "no assets directory"（有配置却导不出），或残留旧 `assets/` 时把非索引旧内容打进包且无报错。修法零件现成：`jackdaw_project_build` 自己的 `ProjectManifest::read(root).assets_dir()`（`project_manifest.rs:88,105`，bevy-light 无依赖问题） | `export.rs:60,208`；`project.rs:55-61`；R10 原文 |
| **N4** | 🟡 | **staging 无内容过滤，编辑器私有产物进发布包**：`copy_tree` 全量拷贝 assets 树（`export.rs:301-326`）——T04 的 `.bak`（保存过即存在于 assets）、原子写 temp 残留 `*.tmp-*`、T06 的 `.jackdaw-pie/` PIE 运行副本（**内含用户未保存场景**，等于把未发布内容打进玩家包）全会进 dist。功能#7 早于 T04/T06，当时无此缺口——是 T04/T06 落地后新出现的衔接洞 | `export.rs:301-326`；`document.rs:96-99`；T06 决策 6（assets/.jackdaw-pie/） |
| **N7** | ⚪ | **`--out` 对非本工具目录无防误删保护**：任意绝对非空目录都会被清空重建（护栏只挡「源目录/根」两类）。`--out C:\Users\me\Documents` 一类手滑没有第二道门——「保护非本工具目录」验收句的直接对象 | `export.rs:51-55,197`；`validate_export_out`（`cli lib.rs:897`）只复验相对路径类错误 |

### B. 可复现构建（验收句③④：--locked、异目录启动回归）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **N5** | 🟡 | **cargo 构建无 `--locked`，依赖可静默漂移**：`cargo_build_argv` 不带 `--locked`（`binary.rs:224-237`）——Cargo.lock 缺失时全量重新解析（上游 crate 更新即变，feature#3 期间 E0308 上游漂移事故为真实先例）；lock 与 Cargo.toml 不一致时 cargo 静默更新 lock 继续。Play/build/run/export 四入口共用此 argv，一处加即全统一。配套事实：`pin_project` 每次构建前主动改 lock（bevy main 工程）→ `--locked` 与 pin 的时序需明确（pin 先跑、build 后锁，兼容） | `binary.rs:224-237,288-292`；`bevy_source.rs:63-99` |
| **N6**（=buglist R9） | 🟡 | **Build 面板永远空白**：`scrolling_log.rs` 的 `spawn` bundle 不含 `ScrollPosition`（`scrolling_log.rs:62-99`），`refresh_scrolling_logs` query 要求它（`:101-105`）→ 永不匹配、日志写不进面板。Build 面板是唯一消费者（`build_panel.rs`）——导出失败时用户唯一的排障面是盲的。一行修（bundle 补 `ScrollPosition::default()`） | buglist R9；`scrolling_log.rs:62-105` |
| **N8** | ⚪ | **可复现提醒缺位**：工程无 `rust-toolchain.toml`（存量工程常态）或无 `Cargo.lock` 时构建零提示——工具链落默认 rustc（专项#5 曾实证 my-game 默认 1.96 必失败）、首建解析全最新。有提醒才有「可复现」的可操作性 | `binary.rs:264-296`（无检测）；scaffold 仅新工程写 toolchain 模板 |
| **N10** | ⚪ | **导出产物无清单/哈希，「同输入同输出」不可验证**：`ExportReport` 只有 files 计数（`export.rs:66-76`）；两次导出是否一致、玩家手里的包是否完整，无任何凭据 | `export.rs:66-76` |

### C. 测试与工具面

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **N9** | ⚪ | **导出状态无 BRP/MCP 断言通道**：`wait(until:"idle")` 能等（busy 含 Building），但结果（成功/失败/outcome/dist 路径/文件数）不在任何 BRP 回复——QA 判定「导出成功」只能靠文件系统轮询+状态栏文本，长任务验收（release 构建 20-40 分钟）无结构化通道，违反 MCP 优先原则的正面立项点 | `server.rs:147-171` 方法表无 export；`server.rs:476-509` status 无 build 字段 |
| — | 🟡（backlog 兑现） | **异目录启动零自动化**：功能#7 真机做过一次「挪盘复跑（像素级一致）」手工证据，无测试沉淀——roadmap 验收句④「最小自动化回归」要求的正是把它变成 `tests/` 常驻 | 功能#7 final-qa 🟡 backlog；`tests/` 无 export 文件 |
| — | ✅ | 正向资产（不用重建）：护栏 normalize/verbatim/dot 检测族与 8 个 staging 拒收测试；`validate_export_out` 构建前预校验；先 assets 后 exe 次序；单导出互斥；`GameExports` 资源即导出状态的数据源（BRP 直读即可）；SCHEMA_FLAG 无窗启动断言器；fixture lock 已入库 | `export.rs:361-664`；`game_export.rs:35-61`；`binary.rs:442-464` |

**统计：🔴 1（N1）｜🟡 5（N2/Y7、N3/R10、N4、N5、N6/R9）｜⚪ 4（N7、N8、N9、N10）｜🟡 backlog 兑现 1（异目录启动自动化）**

### buglist 重叠表（导出/构建/staging/面板相关全量扫描）

| 条目 | 一句话 | T07 处置 |
|---|---|---|
| **R9** | Build 日志面板永远空白（ScrollPosition 未插入） | **吸收（T2）**——导出失败的唯一排障面，一行修+headless 红证 |
| **R10** | staging 硬编码 assets 目录，忽略 assets_dir 配置 | **吸收（T1）**（主控映射里的「T07←R10」即此条；构建面板空白是 R9 不是 R10，已按原文核实） |
| **Y7** | staging 守卫可被 Windows 大小写变体绕过 | **吸收（T1）** |
| W9 | jsn_to_bsn 裸写 | 已修（T04-T1 打钩）——本任务只核对打钩状态，无动作 |
| Y33/Y35 | 游戏 BRP CORS `*` / Content-Length 无上限 | 不吸收（游戏侧远程安全域，T06 已备案维持）；导出产物不含 BRP server（编辑器侧设施），无新暴露面 |
| W28 | 远程 schema 缓存主线程同步序列化写盘 | 不吸收（构建链旁支性能专项）；备注：导出构建后同样触发 schema 提取，其卡顿不在 T07 验收面，超标另立项 |
| Y28 | BSN 解析无深度上限 | 不吸收；T07 无新增不受信 .bsn 解析面（导出 manifest 是自有 JSON） |
| Y9 | project.json 损坏静默覆盖 | 已修（T04-T1）；导出链不写 project.json，无联动 |
| Y37 | PIE 每帧全量反射序列化 | 不吸收（性能专项，T06 备案维持）；PIE 运行中导出（矩阵 #9）会暴露但不阻塞 |
| R3/R4/R5/R6/R7/R8、Y3 等 | 视口/几何/prefab/Inspector 域 | 无关，不吸收 |

---

## 二、分任务拆解（T1/T2/T3）

### T1「staging 原子替换与目录防护」（N1+N2/Y7+N3/R10+N4+N7；决策 1/2/5）

**目标**：导出改为**临时目录打包、全部成功后一次性替换**（失败保留旧产物）；护栏补大小写
不敏感比较；assets 目录跟随 `assets_dir` 配置；编辑器私有产物不进发布包；`--out` 对非本工具
目录有第二道门。

**改动面预估**（全部在 `crates/jackdaw_project_build/src/export.rs` + 两个调用方的少量接线）：
1. **swap 语义（决策 1-A）**：`stage_export` 改为——在 `dist` 同级建 staging 临时目录
   `.<profile>.staging-<pid>-<n>`（`dist.parent()` 下，同卷保证 rename 原子）→ 在临时目录内
   完成 assets 拷贝+过滤+exe 拷贝+manifest（若 T3 决策 4-A 已定，则留钩子）→ 全部成功后交换：
   旧 dist 存在则先 rename 为 `.<profile>.trash-<ts>`，staging rename 到 dist，再尽力删
   `.trash`（删除失败仅 warn+留给孤儿清理，不阻塞成功路径）；任一步失败 → 删 staging 临时目录、
   旧 dist 原样保留、错误上报。exe 拷贝失败的「双路径」错误文案语义不变；
2. **大小写不敏感比较（Y7）**：新增 `starts_with_path_ci`（Windows 上按组件
   `eq_ignore_ascii_case`，非 Windows 走原 `starts_with`；`#[cfg]` 分开实现），`staging_hazard`
   两处判定换用；红证用例：`--out` 拼写与 root 仅大小写不同 → 拒收且源树零损伤；
3. **assets_dir 跟随（R10）**：`plan_export` 内部读 `ProjectManifest::read(root).assets_dir()`
   作为 `assets_source`，staged 内的目标目录名同步用 manifest 名（`dist.join(manifest 名)`，
   不再写死 "assets"——游戏运行时按自己 AssetPlugin 的 file_path 解析，与源目录同名才对）；
   签名不变、两调用方零改动；`ProjectManifest::read` 对损坏 toml 已有降级（读失败回落
   "assets"），单测用 `assets_dir = "content"` fixture 钉住；
4. **内容过滤（决策 5-A 名单制）**：`copy_tree` 增加排除规则——目录名 `.jackdaw-pie/`、
   文件名后缀 `.bak`、`*.tmp-*`（T04 原子写 temp 模式）、`*.corrupt-*`（T04 损坏备份）；
   过滤命中的计数进 `ExportReport`（`skipped` 字段），报告可审计；
5. **`--out` 非本工具目录保护（决策 2-A）**：导出成功时在 dist 根写标记文件
   `.jackdaw-export`（内容：jackdaw 版本+profile+时间）；`stage_export` 发现目标目录**非空且
   无标记** → 拒绝（错误文案说明该目录不属于 jackdaw 导出、可用 `--force` 覆盖或换目录）；
   CLI 加 `--force` 旗标转发（编辑器入口不暴露 force，默认 dist 永远有标记/为空不受影响）。

**验收标准（可执行可复现）**：
- [ ] headless 红→绿①（N1）：预置旧 dist（含旧 exe+旧 assets 快照+逐文件 SHA 清单）→ 注入
  staging 失败（blocked-parent 目录法：在 staging 临时路径预放同名文件挡 `create_dir`，先例
  `scene_io/save.rs` 故障注入族）→ `stage_export` 返 Err → **旧 dist 每个文件 SHA 逐字节不变**；
- [ ] headless 红证②（Y7）：Windows 上 `--out` 与 root 仅大小写不同的拼写 → 拒收
  （`refusing to stage`）且 assets/exe 零损伤（修复前该用例放行且删源=红）；
- [ ] headless（R10）：`jackdaw.toml` 写 `assets_dir = "content"` 的 fixture → 导出成功且
  `dist/content/` 与源一致；无配置工程 → `dist/assets/`（回归）；
- [ ] headless（N4）：assets 内预置 `scene.bsn.bak`、`.jackdaw-pie/current-x.bsn`、
  `scene.bsn.tmp-123` → 导出后 dist 内均不存在，`report.skipped == 3`，正常资产全在；
- [ ] headless（N7）：`--out` 指向非空无标记目录 → 拒绝且目录原样；写标记后（或空目录）放行；
  `--force` 跳过检查；
- [ ] headless：成功路径回归——staging 临时目录与 `.trash` 均被清理（预置孤儿
  `.release.staging-999` / `.release.trash-old` → 下次导出时清除，对齐 T04 孤儿清理族）；
- [ ] headless：幂等——同一 fixture 连续两次导出，dist 内容清单与逐文件 SHA 一致。

**测试设计**：`export.rs` tests 模块扩展（fixture 模式 `staged_fixture` 现成，`export.rs:367-378`），
新增约 8-10 用例；两调用方（`cli lib.rs`、`game_export.rs`）无行为断言变化（签名不变）。
**buglist 吸收**：R10、Y7 打钩。

### T2「统一 --locked 锁定与构建反馈」（N5+N6/R9+N8；决策 3）

**目标**：四入口（Play/`jd build`/`jd run`/导出）的 cargo 构建统一锁定策略——lock 在则
`--locked`、lock 缺则先生成并提示提交；Build 面板能显示日志（R9）；可复现缺位项有提醒。

**改动面预估**：
1. **`--locked`（决策 3-A）**：`cargo_build_argv` 追加 `--locked`（`binary.rs:224-237` 单点，
   四入口全统一）；`build_project_binary_with_load` 在 spawn 前查工程 workspace Cargo.lock
   （`bevy_source::workspace_lockfile` 现成，`bevy_source.rs:102-113`）：不存在 → 先跑
   `cargo generate-lockfile`（经 `rust_env_command`+`detach_from_host_build`，失败按现状
   build 自然报错）+ `BuildEvent::Log("generated Cargo.lock; commit it for reproducible
   builds")`；存在 → `--locked` 生效。**pin_project 时序**：pin 在 build 前（`binary.rs:288`）
   已用 `cargo update --precise` 把 lock 移到 BEVY_REV，随后 `--locked` 用的就是刚写的 lock——
   兼容，无需改 pin（pin 仅 bevy-main 工程动 lock，registry 工程不动）；
2. **失败翻译**：`--locked` 失败（lock 与 toml 不一致，cargo stderr 含
   "the lock file ... needs to be updated but --locked was passed"）→ 在 `Compile` 错误
   透出时追加一行指引（`cargo update` 后重试 / 或删 lock 重新生成），进 build log；
3. **R9 一行修**：`scrolling_log.rs` `spawn` bundle 补 `ScrollPosition::default()`；headless
   红证——现有机制下 `refresh_scrolling_logs` 永不匹配（query 缺件）：用 world 直插
   ScrollingLog+改 content → 断言子 Text 同步（修复前红、修复后绿）；
4. **N8 提醒**：`build_project_binary_with_load` 起始处检查工程根无 `rust-toolchain.toml`
   → `BuildEvent::Log` 一行提示（"no rust-toolchain.toml; builds use the default toolchain"）；
   `jd doctor` 出口补两行（lock 存在性、toolchain 存在性）——只提示不阻断；
5. **argv 锚点测试更新**：`the_build_command_is_the_historical_one_without_a_target`
   （`binary.rs:1323-1364`）断言集加 `--locked`——**这是有意的行为变更锚点**，报告需明示。

**验收标准**：
- [ ] headless：argv 锚点——无 target 命令含 `--locked` 且其余逐字节不变；target 命令同；
- [ ] headless：lock 缺失 → 先 `generate-lockfile`（命令断言/副作用断言二选一，报告说明）+
  log 含提示；lock 在 → 直接 `--locked` 构建；
- [ ] headless：`--locked` 失败文案翻译用例（喂 cargo stderr 字面量，纯函数钉住）；
- [ ] headless：R9 红→绿（ScrollingLog content 变化后子 Text 与滚动位置同步）；
- [ ] heavy/真机（复用既有 fixture）：`bsn_game`（lock 已入库）一次 `cargo build` 走
  `--locked` 成功——证明统一策略对存量工程不破坏；my-game 同测一次（Play 构建回归）；
- [ ] 真机：Build 面板显示编译日志（触发一次构建，`ui_tree`/截图断言面板文本非空——R9 的
  用户可见面）。

**测试设计**：`binary.rs` tests 扩展（argv/翻译/锁检查纯函数化）；`scrolling_log` 红证进
`tests/guards/` 或本文件 tests（世界直插模式，无 UI 依赖）；真机脚本复用
`loop/qa/t02t2-light-color.ps1` 的 BRP 调用模式。**buglist 吸收**：R9 打钩。

### T3「异目录启动回归自动化 + 导出工具面 + 收尾」（N9+N10+backlog；决策 4/6）

**目标**：roadmap 验收句④的最小自动化回归常驻 `tests/`；导出状态结构化可查（BRP+MCP）；
导出清单可验证；真机矩阵终验；文档与台账。

**改动面预估**：
1. **`tests/export.rs` heavy smoke（backlog 兑现 + 验收句④）**：fixture `bsn_game` →
   `build_project`（或预构建产物）→ `stage_export` → 断言 dist 布局/过滤/清单 → **把 dist
   整体挪到另一临时目录**（模拟挪盘）→ 以 staged exe 跑 `--jackdaw-extract-schema`
   （cwd=新目录，不开窗）→ exit 0 + schema 可解析 =「异目录启动」最小断言；xtask heavy 档
   排除串登记（`SDK_BINARIES` 机制，feature#7 方案 D6 先例）；
2. **导出 manifest（决策 4-A）**：`stage_export` 成功路径在 dist 根写
   `export-manifest.json`（每文件相对路径+SHA256+size+profile+jackdaw 版本+BEVY_REV；纯函数
   `manifest_for(dist)` 可测）——「同输入同输出」即「两次导出 manifest 一致（除生成时间）」；
   `jd export` 成功输出打印 manifest 前几行摘要；`ExportReport` 带 manifest 路径；
3. **BRP `jackdaw/export` + MCP 第 25 工具（决策 6-A）**：读 `GameExports`+`BuildStatus`
   组装 `{state: idle|building|ready|failed, outcome, dist_dir, files, profile, started_at}`
   （`game_export.rs:35-43` 资源即数据源，与 `jackdaw/pie`/`recovery` 同构，headless 可测）；
   `crates/jackdaw_mcp` 薄翻译 + `mcp_smoke` 锁定 25 工具；`jackdaw/wait` **不动**（idle 已
   覆盖 Building 等待，结果断言走新方法）；
4. **真机验收矩阵**（全 BRP/MCP 驱动，截图+日志留档 `loop/reports/`）：

| # | 场景 | 期望 |
|---|---|---|
| 1 | 编辑器 game.export 全链（File 菜单或 call_operator） | `wait idle` 放行后 `jackdaw/export` = ready+outcome 含路径；资源管理器打开 dist |
| 2 | 失败保旧（真机版） | 首次导出成功 → 注入失败（预占 staging 路径）再导出 → `jackdaw/export` = failed 且**旧 dist SHA 不变**（N1 的真机腿） |
| 3 | 重复导出幂等 | 二次导出后 dist 逐文件 SHA 与首次一致；manifest 一致（时间除外） |
| 4 | 挪盘复跑 | dist 复制到另一盘符/深层目录 → Start-Process 窗口模式 → 截图非黑屏（功能#7 真机先例复刻+自动化补 headless 腿） |
| 5 | `--out` 保护 | `--out` 非空无标记目录拒绝；`--force` 放行（CLI 侧） |
| 6 | 大小写绕过拒收 | `--out` 大小写变体 → 拒收（Y7 真机腿） |
| 7 | assets_dir 项目 | fixture 配 `content` → dist/content 布局 + schema flag 启动过 |
| 8 | Build 面板日志 | 构建期间面板滚动显示编译行（R9 真机腿） |
| 9 | PIE 运行中导出 | Play（temp 副本在 assets/.jackdaw-pie/）→ 导出 → dist 无 .jackdaw-pie/.bak |
| 10 | Play 回归 | T2 `--locked` 后 dev Play 构建正常（预构建→Play→Stop 链） |

5. book 文档（exporting 节扩写：staging 布局、assets_dir 支持、失败保留语义、manifest、
   `--locked` 策略与排错、`.bak`/PIE 副本不进包说明）；buglist R9/R10/Y7 打钩核对；
   roadmap T07 勾选；台账记行。

**验收标准**：
- [ ] `tests/export.rs` 进 xtask heavy 档并在本机跑过一次全绿（一次构建多次断言，D6 先例）；
- [ ] `jackdaw/export` BRP headless 测试（idle/ready/failed 三态构造世界直插）+ MCP smoke 25 工具；
- [ ] 矩阵 10 格全过（日志+截图留档）；
- [ ] 全量门（`xtask fast`/`integration`/docs/doctests）按 2026-10-25 升级版门禁证据标准
  （日志全文复核、重跑覆盖归档）；
- [ ] 用户 30 秒清单：①Build Game… 两次（第二次故意在导出时锁个文件制造失败也行）——旧的
  dist 始终能双击玩；②把 dist 拷到 U 盘/别的目录双击能玩；③打开 Build 面板能看到编译日志
  在滚（不再空白）。

**测试设计**：`tests/export.rs`（heavy）+ `export.rs`/`game_export.rs` 单测扩展 + 真机脚本
沉淀 `loop/qa/t07-final-live.ps1`（矩阵全链，参照 `t06-final-live.ps1` 模式）。
**buglist 吸收**：核对 R9/R10/Y7 备注。

**QA 清单（放行标准，全任务）**：
- [ ] T1/T2/T3 各自验收全绿；每个 🔴/🟡（N1-N6）有红→绿测试（Y7/R9 必须真红证：修复前用例失败）；
- [ ] 「失败保留旧产物」铁证：headless 注入 + 真机 SHA 双腿；
- [ ] 「保护非本工具目录」铁证：大小写变体拒收 + 非空无标记拒收，源树零损伤断言；
- [ ] `--locked` 统一后 Play/build/run/export 四入口回归（至少 fixture dev 构建 + 导出 heavy）；
- [ ] quick 门（T1/T2）/ 全量门（T3）；门禁证据以日志全文复核为准。

---

## 三、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **staging 原子替换机制** | A=**同级临时目录 + rename 交换**：全量在 `.<profile>.staging-*` 打包 → 旧 dist rename `.trash-*` → staging rename dist → 删 trash。目录 rename 原子（同卷），失败任一步旧产物完好；成本≈一次额外目录 rename。B=dist 内逐文件 write_atomic 替换+清扫多余：无「整目录交换」瞬间，但新旧混合窗口长、实现琐碎（每文件原子+末尾清扫失败语义复杂）。C=保留清空重建+失败回滚：回滚=先把旧 dist 拷贝备份（拷贝成本翻倍，大 assets 树不划算） | **A**（与 T04 `write_atomic` 的 temp+rename 同族思想，目录级实现） |
| 2 | **`--out` 非本工具目录保护** | A=**标记文件 `.jackdaw-export` + 非空无标记即拒 + `--force` 覆盖**：默认 dist 天然合规；空目录放行（首次导出到新位置）；复导出有标记放行；手滑指到用户数据目录有第二道门。B=仅警告继续：不打断但保护落空，验收句不成立。C=维持现状：护栏只挡源目录/根，`--out` 任意非空目录照删 | **A**（温和且「保护非本工具目录」字面兑现；编辑器入口不暴露 force） |
| 3 | **`--locked` 统一策略** | A=**lock 在即 `--locked`（四入口统一）；lock 缺则 `cargo generate-lockfile` 先生成+log 提示提交；失败文案翻译指引**。可复现最强，代价=用户手改 Cargo.toml 未更新 lock 时构建报错（有指引文案，一步 `cargo update` 解）。B=仅导出 `--locked`：改动小但 Play/dev 构建仍可漂移，「统一」落空（同一工程 dev 能玩导出失败/反之，体验更差）。C=`--locked` 失败自动回落非锁定重试：静默漂移风险，最不可取 | **A**（roadmap 原文「统一」；pin_project 时序已核兼容——pin 先跑改 lock、build 后锁） |
| 4 | **导出产物清单（manifest）** | A=**dist 根写 `export-manifest.json`（路径+SHA256+size+版本）**：「同输入同输出」可验证（两次导出 manifest 一致）、玩家包完整性可校验、成本一个纯函数。B=仅 CLI 打印哈希摘要：不留档，机器不可复核。C=不做：N10 挂账 | **A**（T07「可复现构建」验收的最直接证据物） |
| 5 | **staging 内容过滤规则** | A=**名单制**：`.jackdaw-pie/` 目录、`*.bak`、`*.tmp-*`、`*.corrupt-*`——精确对位编辑器已知私有产物，零误伤。B=点前缀一刀切：更省心但可能误伤用户合法 dot 文件（bevy 资产树里 dot 文件罕见但非零）；且 `.bak` 类不带点前缀，仍需名单补充 | **A**（名单常量化+报告 skipped 计数可审计；名单外新私有产物由后续任务补） |
| 6 | **导出状态断言通道** | A=**新 BRP `jackdaw/export` + MCP 第 25 工具**：读 `GameExports`/`BuildStatus`，idle/building/ready/failed+outcome+dist——与 pie/recovery 同构，MCP 优先原则正例。B=塞进 `jackdaw/status`：少一个方法但通用 status 被导出细节污染，且缺 started_at/outcome 历史。C=不加（QA 轮询文件系统）：违背 MCP 优先，长任务验收脆 | **A**（`jackdaw/wait` 不动——idle 已含 Building，等待与断言分离正交） |

另有小定案（主控可否决）：`plan_export` 读 manifest 的方式取**内部读**（签名不变、调用方零改动），
不取加参数（game_export/cli 两处都要跟着改，且编辑器侧 ProjectRoot 与 build crate 的
ProjectManifest 两套读取无需打通——build crate 自己的 reader 就是权威）。

---

## 四、风险与回滚

| 风险 | 缓解 |
|---|---|
| `--locked` 统一改变**所有**构建行为：用户改 Cargo.toml 加依赖未更新 lock → Play/构建报错（此前自动解析） | 失败文案翻译（指引 `cargo update`）；book 文档；fixture+my-game 双回归证明存量工程不受影响；argv 单点 builder 一处 revert 即全量回滚 |
| pin_project（每次构建 `cargo update --precise` 改用户 lock）与 `--locked` 的组合边界：pin 失败仅 warn（`binary.rs:291`）后 lock 仍与 toml 一致，`--locked` 构建可过——但 bevy rev 不齐的类型漂移语义维持现状不变 | 不在本任务扩面（pin 失败降级语义已有 warn）；报告如实记档 |
| rename 交换在 Windows 上：旧 dist 内有正运行的 exe（玩家还在玩）→ `.trash` 目录删除失败 | 删 trash 失败仅 warn+孤儿清理（下次导出/启动清 `.*.trash-*`），新 dist 已就位不受影响；book 说明残留目录可手删 |
| 同卷才能 rename 原子：staging 临时目录必须与 dist 同级（同卷）——`--out` 指向跨卷目录时 staging 也在该卷的父目录下建 | 实现约定 staging 永远在 `dist.parent()` 下；该父目录不可写时报 Io 错误（行为=失败保留旧产物，语义正确） |
| assets_dir 自定义项目的 staged 目录名变更（`dist/content` 替代 `dist/assets`）：旧导出（写死 assets）升级后布局不同 | swap 语义天然整目录替换，无混合布局窗口；book 记录布局跟随 assets_dir |
| 内容过滤名单漏新私有产物 | 名单常量化+skipped 计数进报告（可审计）；缺口由后续任务补名单（非破坏性） |
| heavy 导出测试时长（release 首编 20-40 分钟） | 沿用 feature#7 D6 策略：一次构建多次断言+xtask heavy 档排除；CI 常规档不付费 |
| `--force` 旗标被用于绕过保护 | 仅 CLI 暴露（显式意图）；编辑器入口不接；文档注明语义 |
| 回滚 | 三任务独立成分支段：T1 纯 export.rs 语义升级（revert 即回「清空重建」现状，零格式变更）；T2 argv 单点+一行 UI 修（revert 回无锁构建）；T3 纯测试+工具+文档。全程零场景格式变更、零协议破坏（新 BRP/新文件均为加法）——与 T05/T06 同款最大回滚保险 |

---

## 五、与已建设施的衔接

1. **T04 `write_atomic`/`.bak` = swap 语义的同族先例 + 过滤名单成员**：T1 的「临时目录+rename
   交换」是 `write_atomic`（temp+同目录 rename，`jackdaw_api_internal/src/document.rs:92-111`）
   的目录级同构；T04 落在 assets 内的 `.bak`/`*.tmp-*`/`.corrupt-*` 正是过滤名单的内容来源；
   孤儿清理（`.*.staging-*`/`.*.trash-*`）对齐 T04 启动清孤儿 tmp 族。
2. **T06 `.jackdaw-pie/` = 过滤名单成员 + 矩阵 #9 联动**：PIE 运行中导出（temp 副本在 assets）
   是 T06 决策 6 的点前缀目录——T1 过滤后「PIE 运行中导出」从缺陷变为受支持场景（矩阵 #9
   验收它）；`game.export` 与 PIE 并发的语义不需要互斥门（导出读 assets 树、PIE 写点前缀
   目录，过滤即隔离）。
3. **T05 引用稳定性 = 导出内容正确性的地基**：assets 根单一命名空间（T05 结论）保证整树
   拷贝即引用正确；R10 修复后自定义 assets_dir 工程同样保持该性质（目录名跟随、根语义
   不变）。audit 的 Missing 资产会照拷（垃圾进垃圾出）——不在本任务加耦合（导出前 audit
   是用户动作），book 提示一句「导出前跑 asset audit」。
4. **功能#7（导出体系前作）**：全部护栏测试、`validate_export_out` 前置、dylib 拒收、
   先 assets 后 exe 次序、`GameExports` 单导出互斥直接复用；本方案是其 QA 🟡 backlog
   （heavy smoke 未自动化）的兑现任务。功能#3 的 `--config/--profile` 透传语义不动。
5. **T-QT/MCP 工具族 = 第 25 工具的模板**：`jackdaw/export` 与 `jackdaw/pie`（T06）、
   `jackdaw/recovery`（T04）、`jackdaw/audit`（T05）完全同构（读资源组装 JSON+MCP 薄翻译+
   smoke 锁定）；`jackdaw/wait` 的 idle 判定已含 `BuildStatus::Building`（`server.rs:1925`），
   等待能力零改动。
6. **feature#3 事故档案 = `--locked` 的立项依据**：上游漂移 E0308（lock 从头解析遇上游
   breaking change）与「fixture Cargo.lock 提交入库」建议（已兑现）是 N5 的实证背景；
   `bevy_source::workspace_lockfile`（`bevy_source.rs:102-113`）为 lock 检查提供现成定位。
7. **分支与行号基线**：本方案行号基于 main d4d49dca（T06 闭环点）。T07 从 main 拉
   `loop/t07-export`（N10 修复在 `loop/n10-play-freeze` 并行，合流顺序由主控定，两者
   改动面无交集——N10 在 pie 保存链、T07 在 build/export crate）；行号按符号名重定位
   （矩阵证据均已给符号名）。
