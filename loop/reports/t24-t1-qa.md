# T24 任务 1 QA 复核报告（独立复核）

> 复核对象：分支 `loop/t24-debug` @ **a5f9eb6f**（T1 建设轮），基线 a63fcb84=T24 方案。
> 程序报告 `loop/reports/t24-t1-report.md`；方案 `loop/plans/t24-debug-feedback.md`
> （9 决策点已裁 1(a)/2(a)/3(c)/4(a)/5(A8 吸收+W3 面板化)/6(a)/7(a)/8(a)/9(a)）。
> 复核日期 2026-11-03，平台 macOS arm64。RUST_BACKTRACE 全程未设；磁盘 45Gi（>15Gi
> 门槛）；门禁为测试进程窗口，与真机/红窗不同窗（A6 纪律）；全部数字**亲跑非转录**。

## 裁决：**PASS**（放行 T2 真机矩阵轮）

- 程序偏差 D1-D6 复核**全部成立**；QA 新立观察/文档级偏差 **QD1-QD4**（全部非阻断）。
- D6 建议主控并入 A6/A4 家族票据记档（主控职权，QA 只建议）。

---

## 一、门禁亲跑数字对照

| 门 | 程序口径 | QA 亲跑 | 判 |
|---|---|---|---|
| fmt | EXIT=0 零 Diff | **EXIT=0 零输出**（`t24t1qa_gates_fmt.log`） | ✅ |
| clippy ws dylib | EXIT=0 零行 | **EXIT=0，error/warning 行 0**（`t24t1qa_gates_clippy_ws.log`） | ✅ |
| clippy 物理双包 | EXIT=0 零行 | **EXIT=0，error/warning 行 0**（`t24t1qa_gates_clippy_phys.log`） | ✅ |
| libtests | 3073/3073 | **3073 passed / 0 failed**（result-sum 口径；`t24t1qa_gates_libtests.log`） | ✅ |
| guards | 248/248 | **248 passed / 0 failed**，161.9s（`t24t1qa_guards.log`） | ✅ |
| stage | 562+10 红 | 归档亲读+隔离腿亲跑（见 §二），全量未重跑（D6 口径下不要求） | ✅（D6 成立） |

### libtests 拆账复核（名字集 diff，t23t3qa 归档 vs 本轮 QA 亲跑日志）

- 名字集差（unique names）：**+22 进 / −3 出**，净 +19；
  result-sum 差 3073−3055=**+18**（两代日志 dupe 噪声 −1，与程序报告附注的格式噪声
  说明一致）。
- **本轮名（+18 净）= 18 新 + 1 翻新改名 − 1 旧名移除**，与 §五表逐名对上：
  build_diagnostics ×8、build_panel diagnostic_rows ×3、binding_issue_tests ×4、
  `the_remedy_names_both_honest_moves`（翻新，旧名
  `the_remedy_names_what_is_missing_and_the_rebuild` 移除）、game_panel ×2、
  pie_log `a_window_overflow_counts_its_drops_once_per_window` ×1。**21 组名在 QA
  亲跑日志中逐名 grep 全绿**；guards 2 新名亦逐名亲绿。
- **lineage 漂移（非本轮）**：+3 进（`live_edits::*` ×2、
  `scene_nodes::a_despawned_entity_resolves…`——与程序附注所列三名一致）**−2 出**
  （`live_edits::revert_without_a_live_counterpart_keeps_the_entry`——系 #499 改名
  的另一端；`scene_io::save::terrain_sidecar_tests::only_terrains_present_in_the_scene_
  are_written`）。程序附注只提了 3 进未提 2 出（见 QD1）。
- pie_log 在 workspace 门内 5/5 亲绿（pie 特性统一开启），程序报告「5/5」对上。

## 二、D6 复核（stage 562+10 红）——**成立，按「无新增红」放行**

1. **两份归档日志亲读**（`t24t1_stage.log` / `t24t1_stage_baseline_prefix.log`）：
   - 修后：562 passed / **10 failed**；修前基线：561 passed / **11 failed**。
   - 红腿集合比对（comm 亲跑）：**本轮 10 红 ⊆ 基线 11 红**，差集恰为
     `new_project::a_typed_name_names_the_project_the_dialog_creates`（基线独红，
     修后转绿）；**修后零新增红**。红腿全落在 extension_app_plugin ×2 /
     gltf_authoring ×4 / launcher ×1 / new_project ×3——本轮 diff 域
     （build/bindings/panel/game log/pie_log）在 stage 面**零失败**。
   - 基线跑真身：`t24t1_stage_baseline_prefix.log` 以全仓 **Compiling** 行开头
     （修后跑 0.33s Finished 缓存命中）——基线确为 stash 后 a63fcb84 原树的重新
     编译执行，非同二进制复跑。时间线：修后跑 08:24:59Z 先行，基线跑 08:33:37Z
     （stash 回原树）——与 D6「先见红、stash 亲证基线」叙事一致。
   - stage 测试总数两跑一致（572=562+10=561+11），本轮未增删 stage 腿。
2. **隔离亲跑三条**（`--exact --test-threads=1`，跨三簇，门前 `pkill` 清盘）：
   - `extension_app_plugin::an_extension_enabled_at_launch_adds_its_plugin_before_
     the_app_runs` → **1 passed**（`t24t1qa_stage_leg_ext.log`）
   - `gltf_authoring::undo_redo_restores_a_loadable_gltf` → **1 passed**
     （`t24t1qa_stage_leg_gltf.log`）
   - `new_project::create_in_the_new_game_dialog_makes_the_offered_project_and_
     opens_it` → **1 passed**（`t24t1qa_stage_leg_newproj.log`）
   - 3/3 隔离绿，与程序报告「10 腿隔离/单线程全绿」抽验一致。
3. **裁定**：D6 复核**成立**——红属基线环境簇（扩展构建/GLTF 装载/jd new/launcher
   资源竞争家族；基线日志的 ext 腿 panic 形态=`Ticks` 资源缺失，与 watcher/满载
   同形）。**建议主控并入 A6/A4 家族票据记档**（或本机余裕时复跑全量）——主控职权，
   QA 仅建议。QA 抽验 3 腿全绿，无阻断事实。

## 三、七项复核逐项结论

### 1. diff 面 — ✅ 干净，零越面

`git diff --name-only a63fcb84..a5f9eb6f` 亲跑：38 文件 = 产品面 11
（`src/build_diagnostics.rs` 新模块 + `src/{build_panel,game_panel,asset_failures,lib}.rs`
+ `src/inspector/missing_list.rs` + `crates/jackdaw_bsn/src/{apply,catalog,lib}.rs`
+ `crates/jackdaw_runtime/src/pie_log.rs` + `tests/guards/reference_audit.rs`）+ 报告
1 + 门禁/红证归档 10 + 红窗证据 16。**与预期面逐一对照无越界**：buglist / roadmap /
台账 / book / 场景格式 / 协议 / T12 通道两端 / `crates/jackdaw_project_build`（管线
红线）/ fork 全部零触碰。`src/lib.rs` 差=2 行（模块注册+plugin 挂载）。

### 2. 门禁 — ✅ 全绿（见 §一表，全部亲跑）

### 3. D6 — ✅ 成立（见 §二）

### 4. 六件建设源码级亲读 — ✅ 六件全部落地与报告一致

1. **build_diagnostics.rs**（485 行含测试）：`parse_arrow` 用 `rsplitn(3,':')`
   **右切分**——冒号路径（绝对 mac/windows 拼写）保整，`a_colonful_path_survives_
   the_split` 钉死；severity 块跟随（`error…`/`warning…` 级行设色，note/help 继承，
   `is_level_line` 拒散文/`error_code`）；非匹配行安静跳过；解析空/零行→面板行带
   `Display::None`、全文日志照旧=**回落现状**（方案 §六风险一缓解落地）；
   `count_errors` 独立计 `^error` 行（无箭头失败诚实计数）；`EDITOR_PROBES` 探测表
   6 行（code/code-insiders/vscodium/cursor/windsurf=GotoFlag，zed=Positional），
   首个 PATH 命中即用，表空/拒启回落 `open_with_desktop` reveal 文件夹；
   `resolve_source_file` 工程根→含 Cargo.toml 一级目录候选（纯 stat 零 cargo
   spawn）；管线侧 `jackdaw_project_build` 零改动（决策 2(a) 红线遵守）。
2. **BindingIssues**（apply.rs）：行身份=**实体+组件+字段+kind 四元组一次锁**
   （`identity()` 管道串，`record()` 返回首见即言；rows 每场景 `start_scene()` 清、
   `reported` 跨载持久=面板恒述当前文档，与 UnresolvedTypes 生命周期同款）；
   `an_unknown_field_is_recorded_once_with_its_entity` 钉「同现场恰一条」（重复
   apply 一行一嘴）✓；unknown field warn 补实体名——`apply_ast_to_ecs` **前置
   Name patch 预插入**（文档 #Name 写在组件后也能报出）✓；missing_list 双节：
   标题「Scene Problems」+「Binding problems」节（**Locate=select_only 选实体 /
   Copy=复制 `component.field`；Rebind 不渲染**——决策 4(a) 裁定原文逐字落实）✓。
3. **A8**：三处 note_unapplied warn 位（apply_type_patch / apply_struct_patch /
   apply_tuple_struct_patch 的 enum 臂）**收敛到 `report_unknown_type`** ✓；
   `registered_tail_matches` 注册表同尾段定义 ≤3 条；warn 形态「that spelling is
   not registered — the project registers '…'」（对照 AN1 形态：成因+可用面）✓；
   `unresolved_remedy` **双因诚实版**（rebuild 仅真新类型+改写定义路径，指向
   scene-problems 行）✓；**裸名（无 `::`）双臂 silent fall-through 闭合**
   （apply_type_patch:628 else / apply_struct_patch:878 else，`a_bare_unknown_name_
   is_reported` 钉死）✓；组件不落语义在 warn 文案「A crate-root re-export is not a
   registered spelling; write the definition module path」+doc 中言明（归一化留
   后续票面——决策 5 裁定=warn+文案非装载）✓。
4. **W3**：`WarnedFailures` 扩容——(path,mtime) HashSet 底座**原样复用**
   （is_reported/去重/换 mtime 再说一次全不动），`rows(): &[LoadFailureRow]`
   一次锁复用 ✓；面板第三节「Asset load failures」=「{file} failed to load
   ({error})」警告色+**Show**（reveal 文件夹）/**Copy**（复制路径）双钮 ✓；
   每节 12 行帽（`MAX_ROWS_PER_SECTION`）✓；汇总三段式 ✓。
5. **Game 展开面**：`GameLogExpanded` 标记+点击观察器（纯消费侧，T12 通道两端
   零触碰——diff 亲证 `pie_game_log.rs`/`pie.rs` 未动）✓；展开 `max_height 45%`+
   `ScrollPosition`+100 条全量（`the_expanded_strip_reaches_every_buffered_line`）；
   **折叠面 4 行形态逐字保留**——`game_log_strip()` 仍 `children![log_row(0..3)]`、
   折叠路径 `desired_rows=LOG_ROWS(4)`，既有测试 `the_log_strip_carries_the_newest_
   lines_in_tier_colors` **零适配**（diff 中原样为上下文行）亲核 ✓。
6. **A5**：`admit` 统计窗口丢弃数、首个丢弃触发一条汇总行（帧排空明报形态：
   「the one-second window overflowed; N line(s) were dropped until it rolls」），
   `overflow_reported` **每窗恰一次**、滚窗复位 ✓（`a_window_overflow_counts_its_
   drops_once_per_window` 钉：饱和只出汇总、计数准确、同窗不重报、新窗无陈报）；
   既有 cap 测试翻新（上限面含汇总行）✓。

### 5. 红证真身 — ✅ 三件全是修前活体，原始证据逐项对上

- **DF-R1**（W2）：`walk-dfr1.json` 亲数 **20 条 `--> src/lib.rs:2077:18` 形箭头**、
  「Build failed」在档、**action 标签（Rebind/Locate/Copy/Show in Finder/Reveal/
  Open）walk 全无**；`editor-dfr1-final.log` PIE 失败闩 1 条
  「PIE: game build of t24-red failed…(src/lib.rs:2077:18)」✓。
- **DF-R2**（A8）：`editor-dfr23-final.log` 亲数——裸「cannot apply
  '…AnimationGraphRef': type not in the registry」×1 +「rebuild the project so the
  editor picks up its types」×1；`walk-dfr2.json`「no broken references」在档 ✓。
- **DF-R3**（W1）：unknown field warn ×1 在档；`walk-dfr3.json`
  「no broken references」×1 且 **`nonexistent_field` 在 walk 中 0 出现** ✓。
- **D1 校准口径与原始证据一致**：warn **确有**（1 条裸 warn+1 条误导 remedy），
  静默真身=无指引/单因误导/零结构化行——红证如实、报告如实。
- 证据目录 `loop/t24-red/` 齐全（walk JSON×5、editor log×4——`cmp` 亲证
  `editor-all-1/2` 与 `editor-dfr1/dfr23-final` 逐字节同、console、jd-new、lockfix、
  boot-pid、`lib.rs.pristine` 模板残影）；归档 verdict 标注「离线复核为准」与 D2
  脚本误判记载一致。
- **探针 log**（`t24t1_probe_editor_cli.log`）亲读：code 系全 NOT FOUND、cursor
  `/usr/local/bin/cursor` 3.18.9（`-g --goto <file:line[:character]>` help 亲引）、
  zed `/opt/homebrew/bin/zed` 1.26.2（位置参数）——与代码 `EDITOR_PROBES` 表序
  一致，决策 3(c) 定案可复核。

### 6. 偏差 D1-D5 — 全部成立

| 偏差 | 判 | 依据 |
|---|---|---|
| D1 口径校准 | **成立** | 红档原始 log 亲证 warn 有（§五-5）；buglist 修文留主控=零范围外改动纪律遵守 |
| D2 脚本迭代 | **成立** | `loop/qa/t24-red.sh` `has_in` 现用 `grep -qFe`（`-e` 吃下 `-->` 前缀 needle）；DF-R3 腿改名 `DFR3_FIELD_NAME_ABSENT_FROM_PANEL`+反向判定；归档 verdict 以证据文件离线复核为准——修在脚本侧非产品侧 |
| D3 测试设计修正 | **成立（终态可证）** | 行带测试按内容断言（`rows.iter().any`）+全 Text 收集、`BuildPanelRow` 纯标记——修在测试侧；squash 单提交故迭代中间态不可考古，以终态为准记档 |
| D4 落点偏差 | **成立** | `load_bsn_scene(world, &mut World, text: &str)` **确无文档路径参数**（catalog.rs:209 亲读）；`SceneBsnAst { world, roots, ecs_to_ast, ast_to_ecs }` **不携带来源**（document/mod.rs:99 亲读）；行身份四元组与方案 §0 事实七的三件承诺一致 |
| D5 旧测试翻新 | **成立** | 名字集 diff 亲证旧名亡新名立；旧测试原断言 `remedy.contains("rebuild the project")` 正是 A8 红腿文案本身——翻新合理（T23 MO4 先例形态） |

### 7. T2 交接面 — ✅ 七条注意全部可执行，C3 落点可驱动

1. 面板锚变名：代码亲证「Scene Problems」标题+三节头+空态三分（`open_missing_list`
   三空才答 quiet）——ui_tree 锚按节头取可行。
2. warn 形态面：实际行形与注意 2 逐字对上（apply.rs warn 串亲读）；
   `unknown field|cannot apply` 前缀天然覆盖新行形 ✓。
3. B5 绿判定=warn 含注册拼写指引+面板绑定节行+**组件仍不落**——代码语义一致；
   红证 `t24t1_dfr2_red.log` 在档。
4. Build panel 锚：「N errors · first: file:line:col」汇总串、`--> file:line:col`
   行、「Open」钮、状态栏回报串（`opened {editor} at {pos}` /
   `no external editor on PATH; revealed {folder} (l:c)`）全部在码——可作 ui_tree
   文本锚。
5. Game 条交互（45% 滚动 100 条/折叠 4 行/PIE 免腿 direct run 替代）与码一致。
6. 加载失败面板三节行 Show/Copy+一次锁不变——码一致。
7. 无 open 项成立（D1-D5 收敛+D6 家族记档建议移交主控）。

**C3 真机可驱动性**：本机 cursor+zed 双在册（探针档）——点击 Open→`std::process::
Command::spawn` cursor `--goto file:line:col`→状态栏 `opened cursor at …` 可被
ui_tree walk 断言；无编辑器机器回落 `revealed …` 文本锚。驱动链（`jackdaw/ui_click`
「Open」→walk 状态栏文本）无需 A7 前置。**附注两点给 T2**：(a) 点击副作用=本机会
真启动 cursor 窗口，腿后需收尾清理；(b) Open 行文本子节点 `Pickable::IGNORE`，
ui_click 需命中按钮节点（按行文本定位其父节点）。

## 四、QA 偏差清单（QA 新立，全部非阻断）

- **QD1（文档算术口误，程序报告侧）**：报告 §五标题「净 +18=17 新+1 翻新改名」
  与其自身表格不符——表列 21 行=19 libtest 名+2 guards 名；正确拆账=**18 新 + 1
  翻新改名 − 1 旧名移除 = libtest 净 +18**（guards +2 另计）。headline 3073/净 18
  本身正确。且附注只列 lineage 3 进、漏 2 出（`revert_without_a_live_counterpart…
  →revert_keeps_the_entry…` 改名另一端、`only_terrains_present_in_the_scene_are_
  written` 移除），名集全差为 +22/−3。**修文留主控**，数字面无需重跑。
- **QD2（面板汇总面小拗口，观察）**：findings 空而绑定非空时汇总读「no broken
  references; N binding problems…」（`summarize(0)` 恒返该串）；仅引用问题时追加
  「; 0 binding problems, 0 load failures」。信息准确、语义不误，T2 按 §六-1 以
  节头取锚即可，不修。
- **QD3（B5 修后「组件不落」无库级单测，观察）**：A8 测试钉 warn+行+文案面，
  组件缺席断言由红证（DF-R2 BRP 0 持有）+T2 B5 真机腿承担——与方案矩阵分工
  一致，不缺环。
- **QD4（guards 首测断言强度弱，观察）**：
  `a_binding_problem_opens_the_list_references_alone_left_closed` 在无字体 headless
  世界会因早退（notice 不设）而平凡通过；但其「findings 空+notice ≠ quiet 答」
  组合仍排除红面（DF-R3「零行+quiet 答」），守卫价值在。不阻断。

## 五、产物清单（QA 侧）

- 归档（前缀 `t24t1qa_*`，全部亲跑）：`loop/reports/t24t1qa_gates_{fmt,clippy_ws,
  clippy_phys,libtests}.log`、`t24t1qa_guards.log`、`t24t1qa_stage_leg_{ext,gltf,
  newproj}.log`（隔离腿三件）
- 本报告：`loop/reports/t24-t1-qa.md`
- 零产品改动、零 buglist/roadmap/台账触碰；RUST_BACKTRACE 全程未设（stage 归档中
  该字样均为 std panic 建议行，非设置记录）。

## 六、放行建议

**PASS → 放行 T2 真机矩阵轮**（13 格+L 系腿，按 §六注意与决策 8(a) 口径）。
随行移交主控三件：①D6 红簇并入 A6/A4 家族记档（QA 建议）；②QD1 报告修文；
③T2 附注两点（cursor 副作用收尾、ui_click 命中按钮节点）。
