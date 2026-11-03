# T24 任务 1 报告：建设轮（诊断行结构化 + 绑定错误结构化落点 + 代码位置跳转 + W3/A8/A5 顺手）

> 分支 `loop/t24-debug`（自 main a63fcb84，含 T24 方案）；方案
> `loop/plans/t24-debug-feedback.md` §四-T1；主控裁定 9 决策点全按建议
> （1-A/2-A/3-C带A回落/4-A/5-A8吸收+W3面板化/6-A/7-A/8-A/9-A）。
> 红态先行纪律遵守：`t24t1_dfr1_red.log` / `t24t1_dfr2_red.log` / `t24t1_dfr3_red.log`
> 修前归档（2026-11-03，预 T1 构建 = main a63fcb84 的 target/debug/jackdaw，红窗独立，
> 证据全文在 `loop/t24-red/`）。RUST_BACKTRACE 全程未设。

## 〇、决策 3 探针（T1 首步定案门）— ✅ 3(c) 带行跳转可用

探针表（`src/build_diagnostics.rs` `EDITOR_PROBES`，可扩展：一行=名字+协议形态）：

| 候选 | PATH 探测 | 协议 |
|---|---|---|
| code / code-insiders / vscodium | **无** | `--goto file:line:col` |
| **cursor** | **有（/usr/local/bin/cursor，3.18.9）** | `-g --goto <file:line[:character]>`（VS Code 协议亲验 `--help`） |
| windsurf | 无 | `--goto` |
| **zed** | **有（/opt/homebrew/bin/zed，1.26.2）** | 位置参数 `path:line:column`（`--help` 亲验） |

**定案：决策 3(c) 落地**——点击行级动作按表序探 PATH，首个在册编辑器以协议形态带行
打开（本机命中 cursor `--goto`）；表全空或进程拒绝启动回落 3(a)
`open_with_desktop` reveal 文件夹（全机可用兜底）。归档
`loop/reports/t24t1_probe_editor_cli.log`。

## 一、红证三件（修前归档，纪律遵守）

| 腿 | 归档 | 现场与断言（全文见档） |
|---|---|---|
| **DF-R1（W2）** | `t24t1_dfr1_red.log` + `loop/t24-red/{walk-dfr1.json,editor-dfr1-final.log}` | jd-new 工程模板 `src/lib.rs` 注入一处 E0308 → `pie.play_current` → PIE 失败闩在档（editor log「PIE: game build of t24-red failed…(src/lib.rs:2077:18)」）；Build panel **日志全文在屏**（walk 内 20 条 `--> src/lib.rs:2077:18` 箭头行）+「Build failed」状态行渲染，但 **行级动作为零**（Rebind/Locate/Copy/Open 等 action 标签 walk 全无；全文独骑单一滚动文本节点）。 |
| **DF-R2（A8）** | `t24t1_dfr2_red.log` + `loop/t24-red/{walk-dfr2.json,editor-dfr23-final.log}` | 手写 `assets/t24r2.bsn` 以 crate 根 re-export 拼写（`jackdaw_animation_runtime::AnimationGraphRef`）载入：console 唯二嘴=裸「type not in the registry」+误导「rebuild the project」remedy；**组件不落**（BRP world.query：注册定义路径 `…::graph::AnimationGraphRef` 0 持有 vs Transform 17 持有=实体真实存在）；audit findings=0、Missing References 面板答「no broken references」。 |
| **DF-R3（W1）** | `t24t1_dfr3_red.log` | 手写 `assets/t24r3.bsn`（Transform 带不存在的字段）载入：console 唯一嘴=「unknown field 'nonexistent_field' on 'bevy_transform…Transform'」；面板答「no broken references」、字段名在 walk 中零出现（log 唯嘴，面板/结构化清单零行）。 |

> **A8 口径校准**（红证如实归档所得）：buglist A8 的「无 warn」表述与活体不符——warn
> **有**（T15-T2 QA 亦已纠此，本红证在 main a63fcb84 上复核成立）；真正的静默是
> **结构化面**：warn 无指引（不指注册拼写）、remedy 单因误导、面板零行。建设按此校准
> 落地（见下 3）。红窗脚本 `loop/qa/t24-red.sh`（prep/dfr1/dfr23 三相，A6/A9 纪律
> 全随：单触发源、settle、预算判 FAIL、勿设 RUST_BACKTRACE）。
> 红窗注记：dfr1 相 `DFR1_LOG_FULL_TEXT_ON_PANEL` 腿的**脚本内** grep 把 `-->` 前缀
> 误当选项判了 FAIL——证据文件复核 20 条箭头在档，红档 verdict 以离线复核为准
> （脚本已修 `-e`，见偏差 D2）。

## 二、六件逐项状态

### 1. 诊断行结构化（W2，决策 2(a)+3(c)）— ✅ 落地，11 单测

- **落点**：新模块 `src/build_diagnostics.rs`（~430 行含测试）——`parse_diagnostics`
  纯函数正则提 rendered 文本 `--> file:line:col`（从右向左切分，路径含冒号也稳）；
  severity 随诊断块（`error[E0308]:`/`warning:` 行设色，note/help 继承）；非匹配行
  安静跳过。`BuildDiagnostics { rows, errors }` 伴生资源挂 `BuildStatus` 变更解析
  （`sync_build_diagnostics`，管线 cargo argv/JSON 流零改动——决策 2(a) 红线遵守）。
  `errors` 独立计数 `^error` 行（链接器失败无箭头也有诚实计数）。
- **面板**：`src/build_panel.rs` 头板与日志之间新行带（`BuildPanelRows`）——
  「N errors · first: src/lib.rs:12:5」汇总+首错钉住+每位置一行（`--> …` 按 severity
  着色+Open 按钮），上限 6 行溢出「... and N more (see the log below)」；解析空/零行
  →行带隐藏（**解析失败回落现状**：全文照旧、不报错——方案 §六风险一的缓解落地）。
- **点击动作**（决策 3(c)）：Open → `resolve_source_file`（工程根→各含 Cargo.toml 的
  一级目录候选，纯 stat 零 cargo spawn）→ 探针表首个在册编辑器带行打开（cursor
  `--goto`/zed 位置参数）→ 表空或进程拒启回落 `open_with_desktop` reveal 文件夹；
  状态栏回报落点。单元测试钉：箭头提取格式、非匹配安静、severity 跟随、冒号路径、
  协议参数两形态、探针表首中、路径解析、行带渲染/清空/上限、无箭头计数、severity 着色。

### 2. 绑定错误结构化落点+面板行（W1，决策 4(a)）— ✅ 落地，jackdaw_bsn 4 单测+guards 2

- **落点**：`crates/jackdaw_bsn/src/apply.rs` 新 `BindingIssues` 资源
  （`rows()`+`record()`+`start_scene()`）——**行身份=实体+组件+字段+kind 一次锁**
  （对照 MO1 失败身份形；`reported` 跨载持久，rows 每场景清=面板行恒描述当前文档；
  UnresolvedTypes 的「unchanged remedy stays quiet」同款去重语义）。`BindingIssue`
  四元组 `{entity, component, field, kind}`（UnknownField/UnknownType），`line()`
  行形态对照 audit `finding.line()`。
- **unknown field 补实体上下文**：`apply_ast_to_ecs` 前置 Name patch 预插入（文档
  #Name 写在组件后也能报出实体名）；warn 升格为「unknown field 'x' on 'T' on entity
  #RedField」+结构化行；**同现场恰一条**（单测钉死：重复 apply 一行一嘴）。
- **面板**：`src/inspector/missing_list.rs` 扩容「Scene Problems」双节——标题改
  「Scene Problems」，引用节现状全保留（Rebind/Show/Copy/Locate 四钮不动）+
  **绑定节新行**（Locate=选实体复用 `select_only`，Copy=复制 `component.field`；
  **Rebind 不可用故不渲染**——决策 4(a) 裁定原文）；空态三分（引用/绑定/加载失败
  全空才答「no broken references」，guards 双测钉死：仅绑定行即开板、双空保持安静）。

### 3. A8 吸收（决策 5）— ✅ 落地（红腿 B5 翻绿路径在库）

- **未知路径丢弃补指引 warn**：三处 note_unapplied warn 位（Type/Struct/TupleStruct）
  收敛到 `report_unknown_type`——`registered_tail_matches` 在注册表找**同尾段定义**
  （re-export 拼写的定义模块路径，≤3 条），warn 形态：「that spelling is not
  registered — the project registers 'game::graph::Gizmo'. A crate-root re-export
  is not a registered spelling; write the definition module path」（对照 AN1 运行态
  warn 形态：说清成因+可用面）；无匹配时保留 not-in-registry+指向工程注册组件。
  **无 `::` 的裸名也补报**（原双臂 silent fall-through 顺手闭合）。
- **unresolved_remedy 文案改写**（apply.rs 原「rebuild the project so the editor
  picks up its types」单因误导——DF-R2 红腿在档）：双因诚实版「Rebuild the project
  if the type is new to it; if the scene spells a re-exported or renamed path,
  rewrite it to the definition module path the editor registers — the
  scene-problems list carries one row per occurrence.」单测钉双句在+旧句亡。
- **组件处置语义**：re-export 拼写的组件**维持不落**（修复是「说清楚」不是「归一化
  装载」——决策 5(A8) 裁定=warn+文案，非 QA 治本向 a);归一化留作后续票面），
  warn+面板行+「stays unapplied」语义在单测与红绿对中明确。

### 4. W3 加载失败面板化（决策 5(W3)=做）— ✅ 落地

- **落点**：`src/asset_failures.rs` `WarnedFailures` 扩容——(path,mtime) 一次锁底座
  **原样复用**（is_reported/去重/换 mtime 再说一次全不动），新增 `rows():
  Vec<LoadFailureRow{file,named,error}>` 失败清单资源化。
- **面板**：Scene Problems 第三节「Asset load failures」（三节形态顺贴）——行=
  「{file} failed to load ({error})」警告色+**Show**（reveal 文件夹）/**Copy**（复制
  路径）双钮（对照 missing_list 行钮族）；每节渲染上限 12 行+会话全量在资源。
  汇总行三段式（「…; N binding problems, M load failures」）。

### 5. Game 日志展开面（W4，决策 6(a)）— ✅ 落地，2 单测

- **落点**：`src/game_panel.rs` 日志条点击展开/再点折叠（`GameLogExpanded` 标记+
  点击观察器，纯消费侧——T12 通道两端零触碰）。展开态：条体 `max_height 45%`+
  `ScrollPosition` 滚动+**100 条缓冲全量可达**（每条一行、三级着色不变、重建后钉
  最底）；折叠态：原 4 行形态逐字保留（既有测试零适配过）。条带 tooltip 注明
  「Click to expand…」。单测：点击翻转标记、展开后 100 条全渲染（旧最前新最后）+
  滚动帽/滚位在、折叠面既有测试不动。

### 6. A5 顺手（决策 7(a)）— ✅ 落地，1 单测（+1 既有测试翻新）

- **落点**：`crates/jackdaw_runtime/src/pie_log.rs`——窗口溢出补自身计数 warn：
  `admit` 统计窗口上限丢弃数，首个丢弃触发一条汇总行（对照帧排空明报形态：
  「jackdaw_runtime::pie_log: the one-second window overflowed; N line(s) were
  dropped until it rolls」，附在通过行末尾），`overflow_reported` 旗标**每窗口恰一次**
  （同窗后续 admit 不重复）。单测：饱和窗口只出汇总、计数准确、同窗不重报、新窗
  无陈报；既有 cap 测试翻新（上限面含汇总行）。**注**：pie_log 在 workspace 门内
  有跑（workspace 特性统一开启 `pie`——本轮 libtests 日志名字集 diff 亲证，A5 新测
  计入 3073）；另以 T12 的单包 ad-hoc 形态亲跑
  `-p jackdaw_runtime --features pie,bevy/bevy_winit,bevy/bevy_gizmos,bevy/custom_cursor`
  pie_log 5/5 绿（单包裸 `--features pie` 编不过，T12 记档的 pre-existing）。

## 三、门禁（quick 全门，日志全文复核归档）

| 门 | 命令 | 结果 | 归档日志 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | EXIT=0 零 Diff | `t24t1_gates_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | EXIT=0，零 error/warning 行 | `t24t1_gates_clippy_ws.log` |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | EXIT=0，零行 | `t24t1_gates_clippy_phys.log` |
| libtests | `cargo test --workspace --lib` | **3073/3073**（记录基线 3055，净 +18，逐名见 §五） | `t24t1_gates_libtests.log` |
| guards | `cargo test -p jackdaw --test guards` | **248/248**（基线 246，+2，164s） | `t24t1_guards.log` |
| stage | `cargo test -p jackdaw --test stage` | **562+10 红**（同簇基线亲红，判「无新增红」口径；详见偏差 D6） | `t24t1_stage.log`+`t24t1_stage_baseline_prefix.log` |

> pie_log 单测已计入 workspace 门（3073 含之）；单包 ad-hoc 复跑见 §二-6。

## 四、偏差清单（分级如实）

- **D1（口径校准，非缺陷）**：buglist A8/方案 W1 的「re-export 静默丢=零 warn」与
  修前活体不符——warn 有（DF-R2 红证亲档 1 条+remedy 1 条），静默真身=**无指引、
  单因误导 remedy、零结构化行**。建设按校准面落地（warn 补可用类型面+文案改写+
  行入板），buglist 票面修文留主控职权（本轮零范围外改动纪律）。
- **D2（脚本迭代，非产品）**：`loop/qa/t24-red.sh` 首跑两腿判定受 grep 形态影响
  （`-->` 前缀误作选项；DF-R3 面板腿命名了绿面而非红面）——证据文件离线复核后
  红档 verdict 以实文件为准，脚本已修（`-e`+腿改名 `…_ABSENT_FROM_PANEL`）。
- **D3（测试设计修正）**：Build panel 行带测试首版按查询序断言行序（世界查询非
  生成序）+位置行文本在子实体不在标记实体——修测试（按内容断言+全 Text 收集）
  非修系统；`BuildPanelRow` 顺带瘦身为纯标记（clippy dead_code）。
- **D4（落点偏差）**：绑定行的「文档」面未入行——`load_bsn_scene` 无文档路径参数、
  `SceneBsnAst` 不携带来源（方案 §0 事实七只承诺实体+组件+字段四元组中的三件），
  行身份按实体+组件+字段+kind 锁（rows 恒描述当前载入文档，与 UnresolvedTypes
  生命周期同款）；文档名面若 T2 真机发现必要，走资源补路径的独立小改。
- **D6（门禁环境红，非本轮引入）**：stage 全量在本机今日两跑（修前/修后）同簇红——
  extension_app_plugin ×2、gltf_authoring ×4、launcher ×1、new_project ×3/4
  （扩展构建/GLTF 装载/jd new/launcher 集群，资源竞争家族，A6「门禁磁盘高压」/
  A15「并行撞共享态」同形）。**基线亲证**：修前（stash 后 a63fcb84 原树）全量
  561+11 红，同簇含本轮全部 10 红+1（`new_project::a_typed_name…`）——红属基线环境，
  非本轮引入；本轮 10 红腿**隔离/单线程逐簇复跑全绿**
  （extension_app_plugin 4/4、gltf_authoring 14/14、new_project 7/7、launcher
  单线程 1/1）。按 A4 先例「处置前该门按『无新增红』口径」放行：本轮 diff 域
  （build/bindings/panel/game log/pie_log）在 stage 面零失败。归档：
  `t24t1_stage.log`（修后两跑之二）+`t24t1_stage_baseline_prefix.log`（修前基线红）。
  建议主控把该簇并账 A6 家族（watcher/满载/资源竞争），或本机资源余裕时复跑全量。
- **D5（既有测试翻新）**：`the_remedy_names_what_is_missing_and_the_rebuild` 钉死
  旧 remedy 单因文案（正是 A8 红腿本身）——按新双因诚实文案翻新并改名
  `the_remedy_names_both_honest_moves`（T23 MO4 探针翻转先例形态）。

## 五、新增单测逐名（3073 = 记录基线 3055 + 净 18）

本轮净增 18 名（17 新 + 1 既有翻新改名；其旧名
`apply::document_only_tests::the_remedy_names_what_is_missing_and_the_rebuild` 移除）：

| 域 | 名 | 钉什么 |
|---|---|---|
| build_diagnostics | an_arrow_line_is_parsed_into_a_row_with_its_block_severity | `-->` 提取格式钉死（W2） |
| build_diagnostics | non_matching_lines_pass_quietly_and_severity_follows_the_block | 非匹配行安静跳过+severity 跟随 |
| build_diagnostics | an_arrowless_failure_yields_no_rows_and_an_honest_count | 无箭头失败零行+诚实计数 |
| build_diagnostics | error_shaped_prose_is_not_a_level_line | 行级判定不吞散文 |
| build_diagnostics | a_colonful_path_survives_the_split | 冒号路径右切分 |
| build_diagnostics | editor_args_match_the_protocol_forms | 决策 3 两协议参数形态 |
| build_diagnostics | the_probe_takes_the_first_editor_the_path_holds | 探针表首中+空 PATH 落空 |
| build_diagnostics | a_rendered_path_finds_the_package_file | 渲染路径落盘解析 |
| build_panel::diagnostic_rows_tests | the_failed_log_renders_summary_rows_and_clears_with_the_latch | 汇总+行带上限+闩清带行走 |
| build_panel::diagnostic_rows_tests | an_arrowless_failure_shows_a_summary_without_rows | 无箭头失败只出汇总 |
| build_panel::diagnostic_rows_tests | rows_keep_their_severity_through_the_panel | 行着色按 severity |
| jackdaw_bsn::binding_issue_tests | an_unknown_field_is_recorded_once_with_its_entity | W1 一次锁「同现场恰一条」+实体上下文 |
| jackdaw_bsn::binding_issue_tests | a_re_export_spelling_is_reported_with_the_registered_face | A8 指引 warn+rebuild 不在场 |
| jackdaw_bsn::binding_issue_tests | a_reload_relists_rows_but_speaks_only_for_a_change | 重载重列行+变更才再言 |
| jackdaw_bsn::binding_issue_tests | a_bare_unknown_name_is_reported | 无 `::` 裸名闭合静默 |
| jackdaw_bsn（翻新） | the_remedy_names_both_honest_moves（旧名移除） | A8 remedy 双因诚实文案 |
| game_panel | the_strip_click_toggles_the_expansion | W4 条点击翻转展开 |
| game_panel | the_expanded_strip_reaches_every_buffered_line | 展开后 100 条全可达 |
| guards::reference_audit | a_binding_problem_opens_the_list_references_alone_left_closed | 绑定节开板面（DF-R3 红面翻绿） |
| guards::reference_audit | with_nothing_to_show_the_list_answers_quietly | 三面全空保持安静 |
| pie_log（pie 特性形态） | a_window_overflow_counts_its_drops_once_per_window | A5 窗口溢出明报每窗一次 |

> 名字集对 diff 附注：本轮日志比 t23t3qa 归档多 3 名非本轮名字
> （`live_edits::*` ×2、`scene_nodes::a_despawned_entity_resolves…`，来自
> 6a1e701f/#499 的 lineage 漂移，先于本轮已在 HEAD）；两代归档日志的 sum 口径
> 与 ok 行口径各有 ±3/±4 的格式噪声（t23t3qa 自身 3055 sum vs 3051 ok 行），
> 故以各自 result-sum 为门禁口径：3055 → 3073，差恰为本轮净 18。

## 六、给 T2/QA 的注意事项

1. **面板锚变名**：Missing References 对话框标题改「Scene Problems」，双节头
   「Broken references」/「Binding problems」+第三节「Asset load failures」；空态
   状态栏答「no broken references」仅在**三面全空**时出现（A4/B2/B3 腿的 ui_tree
   锚按节头取）。
2. **warn 形态面扩容**：unknown field 行形「unknown field 'x' on 'T' on entity
   #Name; the scene-problems list carries the row」；unknown type 行形含「the
   project registers '…'」或「check the spelling against the project's registered
   components」；M12 扫描正则的 `unknown field|cannot apply` 前缀天然覆盖。
3. **A8 腿（B5）绿判定**：re-export 场景修后=warn 含注册拼写指引+面板绑定节行
   （Locate/Copy 钮）+**组件仍不落**（语义明确非归一化装载）；红证在
   `t24t1_dfr2_red.log`。
4. **Build panel 锚**：行带文本锚「N errors · first: file:line:col」+每行
   `--> file:line:col`+「Open」钮；点击动作落点=探针表首个在册编辑器（本机
   cursor `--goto`），T2 断言落点可读状态栏回报（「opened cursor at …」/无编辑器时
   「revealed …」）。
5. **Game 条交互**：条体点击展开（45% 高滚动列表 100 条全渲染）/再点折叠；PIE 腿免
   时 direct run+游戏 BRP 读日志面替代（B4 口径不变）。
6. **加载失败面板**（W3）：破文件重载失败→第三节行恰 1（一次锁语义原样），节行
   Show/Copy 双钮；(path,mtime) 换新再坏再说一次的既有语义不变。
7. **无 open 项**：D1-D5 均收敛；红→绿全链可复跑（命令见红档与 §三表）。

## 七、产物清单

- 分支 `loop/t24-debug`：10 文件改动+1 新模块（`src/build_diagnostics.rs`；
  `src/{build_panel,game_panel,asset_failures,lib}.rs`、
  `src/inspector/missing_list.rs`、`crates/jackdaw_bsn/src/{apply,catalog,lib}.rs`、
  `crates/jackdaw_runtime/src/pie_log.rs`、`tests/guards/reference_audit.rs`）
- 红证+探针+门禁归档：`t24t1_probe_editor_cli.log`、`t24t1_dfr{1,2,3}_red.log`、
  `t24t1_gates_{fmt,clippy_ws,clippy_phys,libtests,guards,stage}.log`
- 红窗证据目录 `loop/t24-red/`（walk JSON×5+editor log×2+console+脚本 fixture 残片）
- 红窗脚本 `loop/qa/t24-red.sh`（T2 可复用：prep/dfr1/dfr23 三相）
- 未动：buglist.md / 台账 / roadmap / fork / 场景格式 / 协议 / T12 通道两端 / A7/A9/A10/A14/A16
