# T13-T2 实施报告：流配置面 + 导出从指定场景启动

> 任务：`loop/plans/t13-scene-flow.md` §三-T2（S1+S3+S8；决策 1-A/6-A/7-A，主控 8 点全按建议）。
> 分支 `loop/t13-scene-flow`（自 8e5675ab = T1 合入后续做，`git merge main --ff-only` 确认同基）。
> 改动面（`git diff --stat`：11 文件 +208/−9 + 6 新文件）：共享校验器
> `crates/jackdaw_project_build/src/flow.rs`（新）；runtime 读取链
> `crates/jackdaw_runtime/src/flow.rs`（新）+ `lib.rs` 挂载与 pie_scene_or doc 优先级；
> 模板 `lib.rs.template` 一行换字面量 + 种子 `templates/game/assets/game.flow.json`（新）+
> teaches 87→88；编辑器 `src/game_flow.rs`（新：poll 校验 warn + operator `game.set_start_scene`）+
> `src/lib.rs`/`src/core_extension.rs` 注册 + `src/remote/server.rs` BRP `jackdaw/game_flow` +
> `src/project_window.rs` 右键两项 + `src/game_export.rs` 导出核对；CLI
> `crates/jackdaw_cli/src/lib.rs` 同段校验。测试：runtime `tests/game_flow.rs`（新 10 件）+
> guards `tests/guards/game_flow_config.rs`（新 7 件）+ `main.rs` 注册。真机腿
> `loop/qa/t13t2-live.sh`（t12t3 形态）+ fixture `/Users/zhanglinbo/workspace/loop-mac/t13t2/`。
> 全程未设 RUST_BACKTRACE。门禁归档 `loop/reports/t13t2_*.log`（9 件），真机归档
> `loop/t13t2-live/`。

## 〇、执行摘要

「启动场景+构建场景清单」落在单一来源 **`assets/game.flow.json`**（游戏可读、编辑器可写、
导出自然入包）：runtime 侧 `flow::start_scene_or(fallback)` 读 `start_scene`，任何问题
warn+回落、绝不阻塞启动，优先级由模板一行组合钉死
`pie_scene_or(&flow::start_scene_or("scene.bsn"))`（JACKDAW_PIE_SCENE > flow > 代码字面量）；
编辑器侧共享校验器（project_build::flow）逐帧指纹轮询、变更即 `game flow:` warn（状态栏+结构化
face，不弹窗不阻塞），operator `game.set_start_scene` 原子写（read-modify-write，真实场景加入
清单，坏路径照写由校验点名），BRP `jackdaw/game_flow` 结构化读面；`jd export`/`game.export`
两入口同一校验函数、零 staging 改动，坏 flow 导出继续+warn。真机五点链闭合：**改 flow
start_scene→重导→staged 独立启动从新场景开**（EXP1 从 scene.bsn 起→operator 改 level2.bsn→
编辑器重导→staged 从 LevelTwo 起、Root 归零）。红→绿三面亲证（2 编译红+1 行为红）；
guards 241/241（234+7）、teaches 88/88、quick 五门 EXIT=0。

## 一、验收标准逐条（方案 §三-T2）

| # | 验收标准 | 判 | 证据 |
|---|---|---|---|
| 1 | **headless 红→绿①**：无 game.flow.json 时 direct run 从模板 fallback 启动（现状）；有且指向 menu.bsn 时从 menu 启动 | **PASS** | 红：`t13t2_runtime_red.log`（`jackdaw_runtime::flow` E0432 编译红=API 缺位，即「启动场景唯一来源是模板字面量」的现状）+`t13t2_teach_red.log`（行为红：模板无 flow 接线，teach FAIL，S1 红证）。绿：runtime `tests/game_flow.rs` 10/10（`t13t2_runtime_tests.log`：`a_standalone_run_starts_from_the_flow_file` 全链 app 装载 menu.bsn、`no_flow_file_falls_back_quietly` 零 warn 回落）；guards `the_runtime_reader_reaches_the_same_verdicts` 双解析器同判 |
| 2 | **优先级红绿②**：flow 与 JACKDAW_PIE_SCENE 并存时 PIE 覆盖赢（pie_scene_override 同族新针） | **PASS** | `the_pie_override_wins_over_the_flow_file`（runtime tests，ENV_LOCK 形态同族）：flow 指 menu.bsn + env=override.bsn → 全链 app 装载 Overridee、MenuRoot 不在场；组合式结构保证（PIE 在外层），pie_scene_override 既有 5/5 零回归（`t13t2_runtime_tests.log`） |
| 3 | **编辑器链**：`game.set_start_scene`/右键→json 落盘（原子写）→`jackdaw/game_flow` 读回一致；拼错路径→warn 可见（原文归档） | **PASS（operator+BRP 面）/🟡（右键 GUI 腿降级）** | 真机 chain-run4：LEG_SET_PASS（operator→盘上 json `{"scenes":["scene.bsn","level2.bsn"],"start_scene":"level2.bsn"}`（write_atomic）→BRP 读回一致零 warn）+LEG_WARN_PASS（typo.bsn 照写，warn 两条原文归档 `leg-warn-text.txt`：not in the scene list / not on disk；修正后 warn 清零）。右键菜单项+标识已实现（project_window.rs，两项=提供+✓标识），GUI 合成腿未成（见 §五-3 降级），留 QA 终审 30 秒手验 |
| 4 | **导出链**：flow 指向存在场景→导出零 warn；指向缺失场景→导出成功+warn 原文；staged 树含 game.flow.json 且在 manifest files 里（盘上核） | **PASS** | 零 warn：`t13t2-live/jd-export-1.log`（flow=scene.bsn 在盘，EXP1_EXIT=0 全文无 game flow 行）；缺失场景 warn：`jd export` 对 typo 形态的 warn 由共享校验函数单测+guards 矩阵钉死（`the_matrix_of_broken_shapes_all_warn`），CLI/编辑器两入口同一 `validate_flow`（真机 typo 腿走编辑器入口，`leg-warn.json` flow_warnings 两条原文）；staged：`exp1-tree/`（staged game.flow.json=scene.bsn + manifest files 含 `assets/game.flow.json`）与 EXP2 后 staged=level2.bsn（jq 盘核） |
| 5 | **teaches 88/88；quick 四门** | **PASS** | `t13t2_libtests_scaffold.log` 88/88（新针 `new_game_project_teaches_the_scene_flow_pattern`：模板 doc 命名 flow 文件+`flow::start_scene_or`+`pie_scene_or(`+`"scene.bsn"`+种子含 start_scene 键）；五门（fmt/clippy 全仓/clippy 物理双包/libtests/guards 全量 241/241）全 EXIT=0，见 §四 |

**验收格 8 前置腿（简报明授，真机五点链）**：EXP1（staged 从 scene.bsn 起：Root 在场/
LevelTwo 不在场，`exp1-tree/staged-run1-names.json`）→ `game.set_start_scene level2.bsn`
（LEG_SET）→ 编辑器 `game.export` 重导（EXP2_STAGED_TREE：staged flow=level2.bsn+manifest
收编）→ staged 独立启动从 level2.bsn 起（LevelTwo 在场/Root 归零，EXP2_PASS）。T12 格 9
五点链的直系迁移成立——**改配置→重导→独立启动变**，T3 格 8 的机制半边已实证。

## 二、实现

### 1. flow schema（定稿形状）

`assets/game.flow.json`（assets 树内，项目级游戏流的单一来源）：

```json
{
  "start_scene": "menu.bsn",
  "scenes": ["menu.bsn", "scene.bsn", "gameover.bsn"]
}
```

- `start_scene`：string，assets 相对、`/` 分隔——独立运行的游戏从哪张场景起步。
- `scenes`：string 数组，同路径形态——构成游戏的场景清单；**可省略，缺省读作「仅
  start_scene」**；runtime 只读不强制（清单的消费主体=编辑器校验+导出核对+文档）。
- 校验规则（warn 不拒，文案前缀 `game flow:`，逐条点名路径/字段）：坏 JSON；start_scene
  缺失/空/非 string/路径形态不合法（绝对路径、反斜杠、`..`）；start_scene 不在非空清单内；
  清单重复项；清单项缺失/非 string/不在盘上（`.bsn`/`.bsb` 孪生互认）；未知字段点名忽略；
  `.jackdaw-pie/` 前缀路径列而不查（PIE 会话临时副本随生随灭）。**无 flow 文件=默认态，
  零 warn**（全部既有项目的现状）。
- 两套解析器：`project_build::flow`（编辑器+导出共享，完整 schema 面）与
  `runtime::flow`（游戏侧最小面：只消费 start_scene，只 warn 影响启动的事+未知字段）；
  guards `the_runtime_reader_reaches_the_same_verdicts` 用同一 fixture 钉死两.parser 同判，
  防漂移。

### 2. runtime 读取链（`crates/jackdaw_runtime/src/flow.rs`）

- `pub fn start_scene_or(fallback: &str) -> String`：资产根按 BEVY_ASSET_ROOT →
  CARGO_MANIFEST_DIR → exe 目录 + `assets` 解析（镜像 bevy FileAssetReader 与 catalog 直读
  同族）；文件缺失=静默回落（默认态）；任何损坏/缺字段/不在盘=warn（`game flow:` 前缀，
  点名路径与回落目标）+回落。**永不 panic、永不无场景**。
- `pub fn start_scene_in(assets: Option<&Path>, fallback: &str) -> (String, Vec<String>)`：
  显式根接缝（测试与自解析根的调用方；警告返回供断言）。
- 优先级钉死在 doc 与组合式：`pie_scene_or(&flow::start_scene_or("scene.bsn"))`——
  JACKDAW_PIE_SCENE（play_current，T06 语义）> flow start_scene > 代码 fallback；
  `pie_scene_or` doc 同步注记。`pub mod flow` 挂载 lib.rs，prelude 未动（模板走全路径）。

### 3. 编辑器面（`src/game_flow.rs` + 注册三处 + BRP + 右键）

- **校验 warn**：`GameFlowState` 资源（stat 指纹=mtime+len）+ 每帧 `poll_game_flow`
  （Editor 态）：指纹变更才重读（`inspect_flow`），每条 warn 一次 `warn!`（`game flow:`
  前缀）+ 状态栏 `notify_warn`，不弹窗不阻塞；项目关闭复位。结构化 face 即 BRP 面。
- **operator `game.set_start_scene path=<assets 相对或绝对>`**：relativize（接受 assets
  相对/项目内绝对/反斜杠容忍）→ read-modify-write（保留既有 scenes）→
  `scene_io::save::write_atomic` 原子落盘 → `notify_info` → 同帧刷新校验 face。**清单
  维护策略（真机腿逼出的定案）**：路径在盘上才加入 scenes 清单（永不重排/删减）——坏路径
  只写 start_scene、由校验点名，清单永不收垃圾（第一版无条件加入导致 typo 永久驻留清单、
  warn 不可清除，真机腿当场抓获后改为盘上判定）。
- **BRP `jackdaw/game_flow`**：`{present, path, start_scene, scenes:[{path,on_disk}],
  warnings}`——QA 结构化口（MCP 优先原则：改配置→读回一致真机走此面）。
- **Project 窗口右键**：场景文档（is_document_path 且非资产 kind，双击开场景的同一判定）
  右键项「Set as Startup Scene」；当前启动场景的文件显示「Startup Scene ✓」标识（标签二态
  静态串，零 feathers API 改动）。`operator_for_action` 映射 `project.set_start_scene`。
- **`game.export` 导出核对**：`start_game_export` 在付钱构建前读 flow（manifest assets_dir
  解析，与 staging 同源），warn 逐条状态栏+存入 `GameExports.flow_warnings`；成功通知追加
  「exported, but ...」汇总；`ExportFace`/`jackdaw/export` 增 `flow_warnings` 字段（additive，
  staging/manifest 结构零改动）。
- **`jd export`（CLI）**：扩展工程检查后、构建付钱前，同一 `validate_flow` 逐条
  `jd export: warning: game flow: ...`（stderr），导出继续。

### 4. 模板与种子

- `lib.rs.template` `spawn_scene` 一行换字面量：
  `asset_server.load(jackdaw_runtime::pie_scene_or(&jackdaw_runtime::flow::start_scene_or("scene.bsn")))`
  + doc（flow 文件语义、Play 覆盖、坏文件回落）。hud 链序、States 形态等其余模板面零改动
  （三文档演进归 T3）。
- 种子 `templates/game/assets/game.flow.json`：
  `{"start_scene": "scene.bsn", "scenes": ["scene.bsn"]}`——**T2 时点自洽形态**（偏差 🟡-1，
  见 §五）；include_dir 整树嵌入，`jd new` 自动落盘（真机 fixture 亲证 SEED_FLOW 行）。
- teaches +1：`new_game_project_teaches_the_scene_flow_pattern`（87→88）。

## 三、测试账本

- `crates/jackdaw_runtime/tests/game_flow.rs`（10 件）：解析矩阵经显式根接缝（合法/缺失
  文件/坏 JSON/缺键/非 string/`..`逃逸/不在盘点名回落/未知字段/清单不强制）+ 公共面
  BEVY_ASSET_ROOT（ENV_LOCK 形态同 pie_scene_override.rs）+ 两条全链 app 针（独立运行从
  flow 启动；PIE 覆盖赢过 flow）。
- `tests/guards/game_flow_config.rs`（7 件，guards 234→241）：健康零 warn/`.bsb` 孪生算
  在盘/无文件安静默认/坏形态矩阵（缺 start_scene、不在清单、不在盘、重复、坏 JSON、未知
  字段、路径形态）/PIE 临时目录列而不查/双解析器同判/写序列化回读（空清单序列化省略）。
- 红证时间线（如实）：三面测试**先于实现**提交运行——runtime/guards 编译红（API 缺位，
  `t13t2_runtime_red.log`/`t13t2_guards_red.log`）+ teach 行为红（模板字面量现状，
  `t13t2_teach_red.log`，即 QA 清单 S1 红证「无 flow.json 时启动场景唯一来源是模板字面量」
  的可运行形态）；实现后同面全绿（`t13t2_runtime_tests.log`/`t13t2_guards.log`/
  `t13t2_libtests_scaffold.log`）。
- 项目内单测：project_build flow 模块 3 件（缺省态/相对形态两拼写/非对象 warn）。

## 四、门禁（日志全文复核；归档 `loop/reports/t13t2_*.log`）

| 门 | 结果 | 归档 |
|---|---|---|
| `cargo fmt --all -- --check` | EXIT=0（重跑覆盖：首轮 fmt diff+clippy 4 件即修即覆） | `t13t2_fmt.log` |
| `cargo clippy --workspace --all-targets -- -D warnings` | EXIT=0，0 error/warning 行 | `t13t2_clippy_ws.log` |
| `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | EXIT=0 | `t13t2_clippy_physics.log` |
| `cargo test --workspace --lib` | EXIT=0（含 scaffold 88/88=teaches +1 佐证） | `t13t2_libtests.log` |
| `cargo test -p jackdaw --test guards` | **241/241 passed, 0 failed**（234+7，74.6s） | `t13t2_guards.log` |
| `cargo test -p jackdaw_runtime` | 全部二进制 0 failed（新 game_flow 10/10；pie_scene_override 5/5、ui_scene_ownership 2/2、scene_root_change 4/4=T1 零回归） | `t13t2_runtime_tests.log` |
| `cargo test -p jackdaw_scaffold --lib` | 88/88 | `t13t2_libtests_scaffold.log` |
| `cargo test -p jackdaw_project_build --lib flow` | 3/3 | （会话内亲跑，随 clippy 覆盖） |
| 受影响 crate 编译 | `cargo check -p jackdaw_project_build -p jackdaw_runtime -p jackdaw_scaffold -p jackdaw_cli_internal -p jackdaw --all-targets` 全 EXIT=0 | 会话内亲跑 |

**warn 形态扫描**（`cannot apply|cannot read|does not read as|UnresolvedTypes`）：唯一命中
`t13t2_guards.log:4758` `cannot apply 'mygame::world::NotBuiltYet'`——
`scaffolded_component_flow.rs` 既有故意红料，T12/T13-T1 基线同款恰 1 条，与本任务零关联。
新 warn 形态 `game flow:`（校验面）不在常备词表——建议 T3 真机词表增补（同 T1 的
`Cannot spawn scene '<path>'` 建议）。RUST_BACKTRACE 全程未设；本轮 N13 记数 0 次
（PIE 未使用——真机腿走 pie.play 语义之外的操作面与独立进程，无 PIE session）。

## 五、偏差与记档分级

1. **🟡 种子内容为 T2 自洽形态，非方案 §三-T2-5 的三文档形状**：方案建议种子即写
   `{"start_scene":"menu.bsn","scenes":[menu,scene,gameover]}` 与 T3 对齐；但 menu.bsn/
   gameover.bsn 至 T3 才存在，T2 合入后每个新工程开箱即触发校验 warn+启动场景拒载 warn 回落（fallback），
   且与 T2 自身验收「flow 指向存在的场景→导出零 warn」矛盾。故 T2 种子=
   `{"start_scene":"scene.bsn","scenes":["scene.bsn"]}`，teach 针钉 T2 形状（flow 文件在
   场+start_scene 键+flow::start_scene_or 调用+fallback 名），**T3 落三文档时改种子+重钉
   teach 针**（T3 改动面已有种子往返钉与 teaches 更新项）。
2. **🟡 `game.set_start_scene` 的清单维护超出 operator 字面（真机验收必需）**：方案只说
   「写 start_scene（read-modify-write，缺文件创建）」。真机腿证明两件事：①清单不含
   start_scene 时校验 warn（简报明授的 schema 规则）会立刻点燃；②无条件把路径加入清单会
   让 typo 永久驻留、warn 不可清除（chain-run3 实录）。定案=路径在盘才入清单（真实场景
   加入，坏路径照写 start_scene 由校验点名）。方案字面与定案的差已由 guards/真机双面钉死。
3. **🟡 右键 GUI 合成腿降级（LEG_MENU）**：菜单项+标识已实现且与既有七个右键项同一机制；
   合成腿三次未成——两次坐标域错位（ui_tree rect=物理像素，input.pointer=逻辑像素）修正
   后，ui_tree 对 Project 窗口 tile 文本的可见性随面板状态漂移（首轮 dump 在场、fresh 编辑
   器缺席），合成 secondary click 未在 picking 层产生菜单。按 MCP 优先原则不以土法硬耗：
   结构化作者面（operator+BRP）已全链真机通过；**右键两项留 QA 终审 30 秒手验**（右键
   scene.bsn 见「Set as Startup Scene」；右键 level2.bsn 见「Startup Scene ✓」）。
4. **⚪ 编辑器 log 的 warn! 行未在 stdout 捕获中出现**（status_bar+BRP face 双面在案）：
   editor.log 仅 36 行（编辑器 stdout 本就少量输出），warn 面以状态栏通知+结构化 face 为
   准；QA 如需 log 面可查编辑器自己的日志通道。
5. **⚪ 真机腿过程性偏差（均已修复重跑）**：fixture 手插 dep 后 Cargo.lock 未刷新导致
   `--locked` 导出拒跑（prep 补 `cargo metadata` 刷新）；一次 staging 与残留进程竞态
   （清场后 `jd export` 复跑即成）；phase 脚本 EXIT trap 误杀编辑器（phases 合并单调用）。
   最终证据链全部来自干净重跑（chain-run4 + 复跑 exp1）。
6. **⚪ `jackdaw/game_flow`、`game.set_start_scene` 的 MCP 工具封装未做**：BRP 面已可用
   （`jd mcp` 的 call 通道可透传）；MCP 第 N 工具挂账，QA 如需可由主控裁定小任务补。

## 六、给 QA 的注意事项

1. **优先级组合式**：模板/游戏侧一行
   `pie_scene_or(&flow::start_scene_or(fallback))`——play_current 语义不动（runtime 10/10
   内 `the_pie_override_wins_over_the_flow_file` 在案）；T3 格 10（PIE 双语义）不受 flow
   影响。
2. **warn 文案**：编辑器/导出/游戏三面统一 `game flow:` 前缀+点名路径；runtime 回落文案
   含「starting from '<fallback>'」；导出 CLI 前缀 `jd export: warning: game flow:`。
   真机词表建议增补 `game flow:`。
3. **清单的写路径**：operator 只在路径在盘时入清单——手编 json 仍是清单编辑的正道
   （决策 6-A 挂账不变），校验 warn 是清单与 start_scene 不一致时的唯一反馈面。
4. **无 flow 文件=零 warn 默认态**（既有项目/测试工程不受扰）；有文件才校验。
5. **右键 GUI 腿**：🟡 降级（§五-3），QA 终审 30 秒：右键非启动场景 .bsn→「Set as Startup
   Scene」；右键当前启动场景→「Startup Scene ✓」。
6. **导出面**：staging/manifest 零改动，flow 文件随 assets 整树自然入包（真机盘核）；
   `ExportFace`/`jackdaw/export` 新增 `flow_warnings` 字段（additive）。
7. **fixture**：`/Users/zhanglinbo/workspace/loop-mac/t13t2/t13t2-game`（暖工程，Cargo.lock
   已含 jackdaw_remote；源码依赖本地 workspace path=T2 代码）；真机脚本
   `loop/qa/t13t2-live.sh`（分相 prep/editor/exp1/exp1v/chain/menu/all；编辑器腿必须单调用
   内跑——phase EXIT trap 会清场）。归档 `loop/t13t2-live/`（console.log=全部 leg 判词，
   `exp1-tree/`=导出 1 证据，`leg-*.json/txt`=各腿结构化证据，`staged-*.log`=staged 进程
   日志）。
8. 门链与真机勿同窗（T12-T3 §九-7 口径）；本轮结束时进程清场（pkill jackdaw/t13t2-game，
   已核）。

**提交**：显式 pathspec（§首段 17 文件：11 改+6 新）；loop/ 产物不入库；buglist/台账/
roadmap 未触碰（主控合入时写）。
