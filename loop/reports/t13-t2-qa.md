# T13-T2 QA 验收报告：流配置面 + 导出从指定场景启动

> 验收对象：`loop/reports/t13-t2-report.md`；分支 `loop/t13-scene-flow`，程序提交
> `2a012ad7`（HEAD 即该提交，tracked 树洁净）。改动面核实：`git diff 8e5675ab..2a012ad7
> --stat` = **恰好 17 文件**（11 改 + 6 新，+1662/−9），与报告自述逐文件一致，零越界
> （book/buglist/roadmap/hud.bsn/PIE 协议/staging 结构零触碰）。QA 手段：五门亲跑（后台+
> 轮询，全程未设 RUST_BACKTRACE）+ 全部产品改动源码亲读（两解析器/编辑器面/导出两入口/
> BRP/右键/模板/种子）+ 红绿证据亲读 + **关键测试亲跑**（runtime game_flow 10、guards
> game_flow_config 7、project_build flow 3、pie_scene_override 5、T1 面 spot 3 件）+
> 真机归档逐位核。QA 归档 `loop/reports/t13t2_qa_*.log` 8 件。裁判：**PASS，放行
> T13-T3**；回流清单见 §七。

## 一、门禁（QA 亲跑，日志全文复核；归档 t13t2_qa_*）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | EXIT=0，零 diff 行 | `t13t2_qa_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | EXIT=0，全文 0 error/0 warning 行 | `t13t2_qa_clippy_dylib.log` |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | EXIT=0，0/0 | `t13t2_qa_clippy_physics.log` |
| 单测 | `cargo test --workspace --lib` | **2974 passed / 0 failed**（=T1 基线 2970 + teaches 1 + project_build flow 3，账目吻合） | `t13t2_qa_libtests.log` |
| CI 快门 | `cargo xtask fast` | **2974/2974 passed, 0 skipped**，EXIT=0 | `t13t2_qa_xtask_fast.log` |

- 日志全文按行复核：clippy 两件 0 命中；libtests 全文唯一 error 形态行 =
  `pie: game build of my-game failed: error[E0560]`（libtests :653）——亲核由
  `pie::prebuild_tests::a_failed_build_stays_on_screen...`（ok）故意红料发出，T12/T13-T1
  基线同款，零关联；xtask fast 全文无 FAIL/失败行。
- **xtask 口径注记**：`xtask fast` = fmt + 双 deps + clippy + `nextest --workspace --lib
  --features dylib`（xtask/src/main.rs:35-68 亲读）——**只数 lib 测试**，guards +7 与
  runtime 集成 +10 不在 fast 层（T1 同口径：T1 xtask 2970 == T1 libtests 2970）。简报
  「预期 ≥2970+7」的 +7 按 fast 层口径不应计入；2974 即满额，非缺口。
- warn 形态扫描（常备词表）：程序归档唯一命中 `t13t2_guards.log:4758`
  `cannot apply 'mygame::world::NotBuiltYet'`——scaffolded_component_flow.rs 故意红料，
  恰 1 条与基线同款（报告引 ：4748 系终态重跑覆写前行号，⚪ 记档）；QA 八件归档全文
  0 命中。`game flow:` 形态行在 guards/runtime 绿日志中 0 条（矩阵断言走返回值不走
  subscriber，机制亲核）。RUST_BACKTRACE 全程未设；本轮 N13 记数 0（PIE 未使用）。

## 二、flow schema 审查（本任务产品核心）

### 1. 双解析器结构（源码亲读）

`project_build::flow`（编辑器+导出完整面）与 `runtime::flow`（游戏最小面）分工清晰：
前者 `inspect_flow` 读全 schema（scenes 清单逐项盘检+不在清单 warn+重复 warn），后者
`start_scene_in` 只消费 start_scene（清单明确不巡警，`a_scene_list_is_read_but_not_enforced`
钉死）。优先级=组合式（模板一行 `pie_scene_or(&flow::start_scene_or("scene.bsn"))`），
PIE 在外层、flow 居中、代码字面量兜底——**T06 play_current 语义结构性不可破**
（`the_pie_override_wins_over_the_flow_file` 亲跑绿背书）。无文件双面同判：editor
`inspect_flow` `!is_file` → default（present=false，零 warn）；runtime 读失败 → 静默
回落——「无 flow 文件=零 warn 默认态」源码级成立，且三测钉死（guards
`no_flow_file_is_the_quiet_default` / runtime `no_flow_file_falls_back_quietly` /
project_build `an_absent_file_is_the_quiet_default`），QA 亲跑全绿：**存量工程不受扰亲验通过**。

### 2. 校验矩阵七类逐一核对（每类双侧落点）

| # | 坏形态 | editor 侧 | runtime 侧 | 同判 fixture |
|---|---|---|---|---|
| 1 | 坏 JSON | guards 矩阵 ✓ | runtime `a_broken_flow_file_falls_back_loudly` ✓ | ✓ |
| 2 | 缺 start_scene | guards 矩阵 ✓ | runtime `an_unusable_start_scene` ✓ | — |
| 3 | 非 string | **editor 侧无直接测**（`parse_flow` 分支在，未测）⚪ | runtime `an_unusable_start_scene`（42）✓ | — |
| 4 | 路径形态（`..`/绝对/反斜杠） | guards 矩阵 ✓ | runtime ✓（`..`） | — |
| 5 | 不在清单 | guards 矩阵 ✓ | 有意不查（最小面，测钉） | — |
| 6 | 重复 | guards 矩阵 ✓ | 有意不查（同上） | — |
| 7 | 不在盘 | guards 矩阵+`a_start_scene_off_disk` 双证 ✓ | runtime `a_start_scene_off_disk_falls_back_naming_it` ✓（点名回落目标） | ✓ |

七类全部有测试覆盖（editor 侧「非 string」靠 runtime 侧镜像+源码同构兜底，⚪-2 记档）；
`flow_json` 写序列化回读+空清单序列化省略有专测。**全部亲跑绿。**

### 3. 双解析器同判面（QA 重点核查项）

- **共享三 helper（`scene_on_disk`/`path_form_problem`/`json_kind`）经 QA diff 亲证两文件
  字节级 identical**（仅可见性异）——当前漂移风险=0。
- `the_runtime_reader_reaches_the_same_verdicts` 同判 fixture 覆盖 **3 形**（健康/
  start_scene 不在盘/坏 JSON），报告「同一 fixture 钉死两 parser 同判防漂移」的表述
  **偏强**：三处分歧面不在同判 fixture 内——
  ①bsn⇄bsb 孪生互认：editor 侧有测（`a_bsb_twin_counts_as_on_disk`），**runtime 侧无测**
  （实现 identical 兜底）；②`.jackdaw-pie/` 列而不查：editor 侧有测（`pie_temp_copy_paths_
  are_not_held_to_disk`），**runtime 不豁免**（start_scene 照查盘）——同 fixture 异判的
  真实分歧行，属域语义差异（独立运行时 pie 临时副本必不在盘，warn 是对的）但未成文未钉；
  ③「文件在但读不出」（IO 权限）：editor warn「could not be read」vs runtime 静默回落，
  未钉。**均 ⚪ 记档 + T3 建议增补**（同判 fixture 加孪生+pie-temp 两形+分歧注释），不阻塞。

## 三、三处 🟡 偏差裁定复核

### 🟡-1 种子自洽形态 —— **裁定成立（程序论证方向正确，措辞一处不精确）**

方案 §三-T2-5 建议种子即三文档形（menu/scene/gameover）；程序改用
`{"start_scene":"scene.bsn","scenes":["scene.bsn"]}`。核裁定依据：menu.bsn/gameover.bsn
T3 才存在，若 T2 种子按方案写——编辑器开箱校验 warn「not on disk」+导出 warn+runtime
warn 回落，**新工程开箱即三面带警**，与 T2 自身验收「flow 指向存在场景→导出零 warn」
直接矛盾。**成立**。一处措辞修正：报告称后果含「启动场景拒载黑屏」——runtime 对不在盘
的 start_scene 是 **warn+回落模板字面量**（scene.bsn 在盘，游戏照常起），不是黑屏；
真实代价=开箱 warn 面，论证结论不变。**T3 重钉义务在案**：报告 §五-1 明写「T3 落三文档
时改种子+重钉 teach 针」，且 T3 改动面本含种子往返钉与 teaches 更新项（方案 §三-T3-1/3）；
现 teach 针（start_scene 键+`scene.bsn`）在 T3 种子改为 menu 形后仍会字面命中（scenes
清单含 scene.bsn），不会静默破，但须按方案主动重钉为三文档断言——义务链完整。

### 🟡-2 operator 清单维护策略 —— **裁定成立（真机抓获→源码修复→真机复证，闭环最完整的一件）**

方案字面只授「写 start_scene（read-modify-write，缺文件创建）」。真机实录：
chain-run3 `LEG_SET_PASS` + `LEG_WARN_FAIL warnings did not clear`——第一版无条件把路径
加入清单，typo.bsn **永久驻留清单**、operator 无法清除 warn（只有手编 json 能救），缺陷
当场抓获。修复形态源码亲核（`src/game_flow.rs:179`）：
`if !next.scenes.contains(&relative) && flow::scene_on_disk(&assets, &relative)` ——
**在盘才入清单、永不重排/删减**；坏路径照写 start_scene 由校验点名（leg-warn.json 原文
两条：not in the scene list / not on disk），修正后 warn 清零（chain-run4 `LEG_WARN_PASS`
亲核）。typo 不再进清单（leg-warn.json 的 scenes 不含 typo.bsn 亲核）。策略权衡正确：
清单语义=「构成游戏的场景」，垃圾不入册；校验是唯一反馈面。方案字面超出已记档，
guards+真机双面钉死。

### 🟡-3 右键 GUI 合成腿降级 —— **裁定：降级合理（MCP 优先原则的正确应用），GUI 形态本体记档为合入知悉项**

按三要素核：
- **已修的坐标域错位证据**：`loop/qa/t13t2-live.sh` menu_leg 注释+实现亲读——ui_tree
  rect=物理像素、input.pointer=逻辑像素，`x=rect[0]/2+10` 已除 retina 因子（修复在案）；
- **ui_tree tile 漂移证据**：menu-run3 `LEG_MENU_SKIP tile not found`、leg-menu.json =
  `{"nodes":[]}`（菜单项在 picking 层从未物化）、console.log 三轮 LEG_MENU_FAIL 实录；
- **降级后剩余风险封顶**：右键两项与既有七个右键项走同一 `open_context_menu`/
  `ContextMenuState`/`operator_for_action` 机制（project_window.rs diff 亲读）；新判式
  `is_document_path && !holds_an_asset` 与双击开场景同族谓词（is_document_path 基底共用，
  右键更严：排除注册资产 kind）——新面只剩两个标签串+判式收紧，**承载机制是用户已验证
  的既有面**。结构化作者面（operator+BRP）已全链真机过（LEG_SET/LEG_WARN）。
  按 MCP 优先原则（README：麻烦步骤补工具而非土法硬耗），继续合成点击属土法硬耗，降级
  正确。**30 秒手验项已写清**（报告 §五-3+§六-5，本报告 §六整理成清单）。
  遗留如实记档：两项 GUI 形态（菜单项出现+标识显示+点击生效）至本报告时点**零机器证据、
  零人眼证据**——按 README 交互验收规则「留用户手测」不是放行条件而是终审抽查项，故
  本 QA 不以它阻塞，但主控合入时须知悉该残余风险敞口，清单必须累积进 final-qa。

## 四、导出五点链复核（`loop/t13t2-live/` 逐位核）

| # | 环节 | 证据 | 判 |
|---|---|---|---|
| 1 | EXP1：staged 从 scene.bsn 起 | `exp1-tree/staged-run1-names.json`：`Root`/`scene`/`Sun` 在场、`LevelTwo`/`LevelTwoSun` **不在场**；`staged-game.flow.json`=scene.bsn；`jd-export-1.log` EXP1_EXIT=0 且全文无 `game flow` 行 | ✓ |
| 2 | operator 改配置 | `leg-set.json`：BRP 读回 start_scene=level2.bsn、scenes=[scene.bsn, level2.bsn]（在盘新场景入清单）、warnings=[]；盘上 json 同值（脚本 jq 判） | ✓ |
| 3 | 编辑器重导 | `leg-exp2.json`：game.export face state=ready、`flow_warnings:[]`、files=5、skipped=1；EXP2_STAGED_TREE_PASS=脚本对 staged flow `jq` 盘核 start_scene=level2.bsn+manifest 含 flow | ✓ |
| 4 | manifest 收编 | `exp1-tree/export-manifest.json` files[0] = `assets/game.flow.json`（sha256+size）——flow 随 assets 整树入包零 staging 改动 | ✓ |
| 5 | 独立启动从新场景起 | `names-raw.json`（EXP2 staged 运行 dump）：`LevelTwo`/`LevelTwoSun`/`level2` 在场、`Root` **归零**；EXP2_PASS | ✓ |

**改配置→重导→独立启动变**五点链闭合，T12 格 9 直系迁移成立。脚本断言形态亲读
（双向实体在场性+盘上 jq 双核），非只读 PASS 字符串。

**两入口同一校验源码级核对**：`jd export`（`crates/jackdaw_cli/src/lib.rs:811-818`，构建
付钱前 `flow::validate_flow`，stderr `jd export: warning: game flow:`）与 `game.export`
（`src/game_export.rs:171-178`，`game_flow::inspect_project_flow` → 同一 `project_build::
flow::inspect_flow`，状态栏 warn + `GameExports.flow_warnings`）——**两入口汇聚同一
校验函数，源码级证实**。`ExportFace` 增 `flow_warnings` 字段、`jackdaw/export` 应答增同名
键——纯 additive（既有字段逐一不动，export_handler 旧面补空数组），clippy 全绿佐证无
破坏面。

## 五、PIE 优先级 + 零回归（亲跑）

- `the_pie_override_wins_over_the_flow_file`：**亲跑 ok**——flow 指 menu.bsn +
  `JACKDAW_PIE_SCENE=override.bsn` → 全链 app 装载 Overridee、MenuRoot 不在场（ENV_LOCK
  形态同族，无环境泄漏）；runtime game_flow **10/10** 全绿（`t13t2_qa_runtime_gameflow.log`）。
- `pie_scene_override` **5/5**、`scene_root_change` 4/4、`ui_scene_ownership` 2/2 亲跑
  （`t13t2_qa_runtime_src.log`）——T1/T06 面零回归。
- guards `game_flow_config` **7/7** 亲跑（`t13t2_qa_guards_flowconfig.log`）；
  project_build flow 单测 3/3 亲跑（`t13t2_qa_pb_flow.log`）；guards 全量 241/241
  （程序归档 `t13t2_guards.log` 复核 +7 账目吻合）。

## 六、偏差分级与 30 秒手验清单

| 级 | 项 | 裁定/处置 |
|---|---|---|
| 🟡 | 三处程序偏差（种子自洽/operator 清单/右键降级） | **三件全部裁定成立**（§三）；不阻塞；T3 义务与知悉项见 §七 |
| ⚪-1 | 同判 fixture 仅 3 形；bsb 孪生 runtime 侧无测、pie-temp 为真实异判分歧行（runtime 不豁免）、IO 读失败静默 vs warn 未钉 | 共享 helper 字节级 identical 兜底（QA diff 亲证）；**T3 建议同判 fixture 增孪生+pie-temp 两形+分歧注释**（廉价，防未来漂移） |
| ⚪-2 | editor 侧「非 string start_scene」无直接测（runtime 侧有） | 同构兜底；T3 顺手补一断言即可 |
| ⚪-3 | fixture `assets/game.flow.json.bak` 来源 | **QA 亲核归因：设计行为**——write_atomic 单代备份轮转（save.rs 测试钉），导出 staging 排除 .bak（export.rs:743+专测；leg-exp2 skipped:1 即它）——无产品问题，非垃圾 |
| ⚪-4 | 报告 warn 命中行号 ：4748 vs 实际 ：4758 | 终态重跑覆写日志所致，内容同款恰 1 条，trivial |
| ⚪-5 | 报告「黑屏」措辞（§五-1） | runtime 是 warn+回落（回落目标在盘），非黑屏；结论不变，措辞修正 |
| ⚪-6 | editor stdout 无 `game flow:` warn! 行（报告 ⚪-4） | 亲核 editor.log 0 命中属实；warn 面以状态栏+BRP face 为准（leg-warn.json/txt 原文在案）——成立 |
| ⚪-7 | 新 warn 词表 `game flow:`（+T1 的 `Cannot spawn scene`）不在常备扫描词表 | 程序建议复核有效；**T3 真机词表增补**（两条一起） |

**30 秒手验清单（右键 GUI 两项终审抽查；累积进 final-qa）**：
1. `jd open` 打开含 game.flow.json 的工程 → Project 窗口右键**非启动场景** .bsn（如
   level2.bsn）→ 菜单出现「**Set as Startup Scene**」→ 点击 → 状态栏
   「start scene set to 'level2.bsn'」、该文件获「**Startup Scene ✓**」标识、
   `jackdaw/game_flow` 读回 start_scene=level2.bsn。
2. 右键**当前启动场景**文件（scene.bsn）→ 菜单项文案为「**Startup Scene ✓**」。
3. 健康 flow 下状态栏无任何 `game flow:` warn。

## 七、裁决

**PASS** —— 放行 T13-T3（模板三文档演进 + 真机矩阵 + book）。

依据：五门亲跑全绿（xtask fast 2974/2974，口径注记在案）；flow schema 双解析器结构
源码级核立（共享 helper 字节级 identical、最小面/完整面分工 doc 化、无文件零 warn 默认态
三测亲验、七类校验矩阵逐一有测试）；红绿三面闭合（E0432 编译红 ×2 + teach 行为红，先于
实现提交；终态绿=程序归档+QA 亲跑双源）；真机五点链逐位核立（改配置→重导→独立启动变，
双向实体在场性断言）；两导出入口同 `validate_flow` 源码级证实、ExportFace/BRP 纯 additive；
PIE 优先级针亲跑绿+pie_scene_override 5/5 零回归；三处 🟡 程序偏差全部裁定成立且
🟡-2 是「真机抓获→源码修复→真机复证」的完整闭环。

**回流清单（🔴 主控）**：
1. 合入知悉：右键两项 GUI 形态零证据敞口（🟡-3）——30 秒手验清单（§六）移交 final-qa
   累积；用户抽查踩出问题按 buglist 流程另立。
2. 带★给 T3 的义务链（程序报告在案、QA 复核有效）：种子改三文档形+重钉 teach 针；
   真机 warn 词表增补 `game flow:` 与 `Cannot spawn scene '<path>'`（两条一起）。
3. 带★给 T3 的非阻塞建议（本报告新提）：guards 同判 fixture 增 bsb 孪生+pie-temp 两形
   与分歧注释（⚪-1）；editor 侧补「非 string」断言（⚪-2）。
4. 报告顺手修正（⚪-4/⚪-5）：warn 命中行号 ：4748→:4758；§五-1「拒载黑屏」→「warn 回落」。
5. QA 归档清单（8 件，`loop/reports/`）：`t13t2_qa_fmt.log`、`t13t2_qa_clippy_dylib.log`、
   `t13t2_qa_clippy_physics.log`、`t13t2_qa_libtests.log`、`t13t2_qa_xtask_fast.log`、
   `t13t2_qa_runtime_gameflow.log`、`t13t2_qa_runtime_src.log`（含 pie 5/5+T1 spot）、
   `t13t2_qa_guards_flowconfig.log`（+`t13t2_qa_pb_flow.log`，共 9 件）。
6. 本轮 QA 结束进程清场已核（pgrep 无 jackdaw/t13t2-game 遗留；QA 侧仅跑 headless，
   未启编辑器/游戏进程）。
