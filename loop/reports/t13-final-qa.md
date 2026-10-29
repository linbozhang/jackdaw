# T13 终验 QA 报告：任务 3（收官段）+ T13 整体终验（只验不修）

> 验收对象：分支 `loop/t13-scene-flow` @ **c82550c7**（基线 main=3fe6aa7d；T3 提交=18 文件
> +1927/−520：模板 lib.rs.template 流段重写+hud.bsn 收缩两屏+新种子 menu.bsn/gameover.bsn
> .template+game.flow.json 三文档形+scaffold lib.rs 重钉+guards game_ui.rs 迁移/
> game_flow_template.rs 新 3 件/game_flow_config.rs 增两形+project_build flow.rs +1+
> book 7 文件；`git diff main...HEAD` 亲核零 prefab/watcher/scene_io 域交集）。
> 程序报告：`loop/reports/t13-t3-report.md`。前置：T1 QA（7e1e3c3e PASS，负向复演在案）、
> T2 QA（2a012ad7 PASS）。
> QA 证据：**Mac 全量门 10 门亲跑**（后台串行，全程未设 RUST_BACKTRACE，门链与编辑器/游戏
> 不同窗——开跑前 `ps` 复核零遗留进程；归档 `t13t3_qa_*` 12 件，脚本
> `loop/qa/t13t3-qa-gates.sh`）；`loop/t13t3-live/` 16 件逐位核对+抽格 2/5/8 原始日志全文
> 亲读；T1/T2 旧证据指针开卷；guards/模板/种子/teaches 针/book 盘上亲核；**A6 独立复跑四腿**
> （隔离单测双树+全 prefab 二进制双树=git worktree 干净 main 亲跑）与 **N13 逐条原文记数**
> 亲做。

## 〇、结论

**PASS（T13-T3 + T13 整体，含 roadmap T13 可勾选建议）**——矩阵 12 格逐一核实 12 PASS
成立（逐格数字与 `loop/t13t3-live/` 原始日志逐位一致；格 2 真指针 sweep/格 5 三循环七元组
恒等/格 8 导出五点链三格全文亲读属实）；验收句铁证各有独立证据；T12 重钉对照表逐条源码
亲核，**裁定：重钉≠回归**（⑤四档分辨率数字逐字未放松亲证）；guards 244/244（241+3 亲数）、
teaches 88（scaffold 套件 88 passed 亲读）、lib 2975、fast 2975 全绿亲跑。
**integration 亲跑复现同件单红**（5381/5382，唯一红=`prefab_file_change_triggers_reload`
3 试全败）——QA 独立四腿复核将程序二分定案**升级为闭合证据链**（双树全二进制红/隔离绿
亲证+零 diff 交集+磁盘高压加重因子实测），**A6 升级 🔴 立项建议成立**；N13 本轮实测
**22 条** panic（程序报告 11 条漏计 flow 相一半+归因与日志不符，见 §五-1），stop 形态
新样本 4 条在案，**N13 升级处置优先级建议成立**。偏差 **0 🔴（产品）+2 🟡（两升级案）+
8 ⚪**（§七）。

## 一、Mac 全量门亲跑（权威口径）

| # | 门 | 命令 | QA 亲跑结果 | 归档 |
|---|---|---|---|---|
| 1 | 格式 | `cargo fmt --all -- --check` | **CLEAN**（EXIT=0，日志 0 字节） | `t13t3_qa_fmt.log` |
| 2 | Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **CLEAN**（EXIT=0） | `t13t3_qa_clippy_ws.log` |
| 3 | Lint 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **CLEAN**（EXIT=0） | `t13t3_qa_clippy_physics.log` |
| 4 | 单测 | `cargo test --workspace --lib` | **2975 passed / 0 failed**（EXIT=0；scaffold 套件 88 passed=teaches 88 在册亲读） | `t13t3_qa_libtests.log` |
| 5 | guards | `cargo test -p jackdaw --test guards` | **244 passed / 0 failed**（101.04s） | `t13t3_qa_guards.log` |
| 6 | fast | `cargo xtask fast` | **2975/2975 passed, 0 skipped**（EXIT=0，与预期 2975 一致） | `t13t3_qa_gate_fast.log` |
| 7 | **integration** | `cargo xtask integration` | **5382 run：5381 passed，1 failed**（EXIT=1，1235.9s）——唯一红=`jackdaw::prefabs prefab_lifecycle::prefab_file_change_triggers_reload`，3 试全败（13.36s/11.45s/8.43s），panic 同签名（`watcher reloaded prefab; v2 should be in world. Got ["v1"]`，prefab_lifecycle.rs:714）=**程序的 5381/5382 独立复现**（§四-1 四腿复核） | `t13t3_qa_gate_integration.log` |
| 8 | doctests | `cargo test --workspace --doc --features dylib` | exit=101=jackdaw_bind **DYLD 环境族**（`libstd-614bb9b33bbc23af.dylib` 找不到——**第 7 次目击**，T08-T12 同族）→带 toolchain DYLD 单包复跑 **PASS**（0.02s） | `t13t3_qa_doctests.log` + `t13t3_qa_doctests_bind_rerun.log` |
| 9 | docs | `cargo doc --workspace --no-deps` | **EXIT=0** | `t13t3_qa_docs.log` |
| 10 | scaffold_e2e 冷编 | `cargo test -p jackdaw --test scaffold_e2e` | 首跑 **FAILED=ENOSPC**（数据卷 100% 满、余 1.9GB；失败运行自身遗留 46GB 临时工程——QA 清理后释放）→**腾出 46GB 后复跑 PASS 1/1（169.61s）**——纯环境失败，冷编验收腿以复跑绿为准（程序本论 182.09s PASS 亦在案） | `t13t3_qa_scaffold_e2e.log`（首跑红）+ `t13t3_qa_scaffold_e2e_retry.log`（复跑绿） |

**程序归档交叉复核**（`t13t3_*` 14 件）：fast 2975/2975、guards 244/244（88.85s）、
scaffold_e2e 182.09s、doctests bind 复跑 PASS、docs EXIT=0、plain_new 零 error——与报告
§四表逐项一致，无隐瞒。**integration 权威口径**：程序两轮（每轮 3 试）+QA 一轮（3 试）=
**今日同件 6×3 连红**，全绿在本机当前机器态不可达；单红的定案与门禁处置见 §四-1
（A6 升级票，非 T13 域缺陷，按 T12 先例「单红=已定案环境票+闭合证据链」放行）。

**warn 形态扫描**：四缺陷形态 `cannot apply|cannot read|does not read as|UnresolvedTypes`
扫 `loop/t13t3-live/` 16 件 **0 条**；`game flow:` 行 7 条全部逐条归因（cell 9 设计产物
4 条原文在案被断言 + `game flow: start scene set to` INFO 3 条=操作回执，非 warn）；
`Cannot spawn scene` **0 条**。QA 自己的 guards 亲跑日志 1 条 warn=`NotBuiltYet` 故意
fixture（T12 QA 同款归因）。libtests 亲跑日志 error 形态行仅 `not_panicked` 系测试名。

## 二、矩阵 12 格逐位核实（报告 §三表 vs `loop/t13t3-live/` 原始日志）

**抽 3 格全文亲读**（格 2 真指针 sweep、格 5 三循环恒等、格 8 导出五点链），其余逐格
数字与 console-game.log/console-flow.log 逐位对照：

| # | 场景 | 判 | QA 核实（证据原文位） |
|---|---|---|---|
| 1 | 新工程开箱=启动场景 | **PASS** | console-game.log:4-5 亲读：MenuRoot=1/StartButton=1/MenuUiCamera=1/Sun=0/HudRoot=0+face start_scene=menu.bsn+warnings=0+scenes=3（脚本 jq 三断言）；player=0 由脚本 PlayerMarker 计数断言承载 |
| 2 | 菜单→关卡（真指针点击） | **PASS** | **全文亲读**：`sweep_click: hit at (787,787)`（真编辑器指针，sweep 网格第 2 点命中）→sig_menu=[n=9 p=0 h=0 c=0 pl=0 r=0 cam=1]→sig_level=[n=17 p=3 h=1 c=1 pl=1 r=0 cam=0]；MenuRoot/MenuTitle/MenuUiCamera 全 0=零残留；pickups=3/FallingCube=1/player=1 |
| 3 | 关卡→结束 | **PASS** | console:21：died=true（hazard 真实触发通道 die_on_hazard 往返踏）+GameOverRoot/RestartButton/MenuButton/GameOverUiCamera=1+Sun/HudRoot/HealthBar/pickups/hazards 全 0+player_still=1（sig=[n=11 … pl=1 cam=1]） |
| 4 | 结束→重开 | **PASS** | console:25：health=100.0/PickupCount=0/pickups=3/pos=(-2.0, 0.86, 0.0)=PLAYER_SPAWN；sig=[n=17 p=3 h=1 c=1 pl=1 r=0 cam=0] 与格 2 首载 sig_level **逐字同串**（无重复加载） |
| 5 | 往返稳定性 | **PASS** | **全文亲读**：三循环 A/B/C 每停靠点七元组 stop-signature 逐字恒等——level=[n=17 p=3 h=1 c=1 pl=1 r=0 cam=0]×3、over=[n=11 p=0 h=0 c=0 pl=1 r=0 cam=1]×3、menu=[n=9 p=0 h=0 c=0 pl=1 r=0 cam=1]×3；一次按压恰一次翻转由 STAND_FLOW_PAUSE_SINGLE（tap1=true/tap2=false）+T1 guards 观察者单次件承载 |
| 6 | 跨场景对象规则 | **PASS** | console:28：player `738v0`==`738v0`==`738v0`（level₁/gameover/level₂ 三站恒等）；pickups `733v0,734v0,735v0`→`764v0,765v0,766v0` 每轮更换；book 规则表在位（§六） |
| 7 | 启动场景三形态同源 | **PASS** | console-flow:7-8：face 读回 gameover.bsn+盘上 json 同值+Play（GameOverRoot=1/MenuRoot=0）+direct（BEVY_ASSET_ROOT 二进制独立启动同判） |
| 8 | 导出从指定场景（五点链） | **PASS** | **全文亲读**：leg1 `face_zero_warn=y manifest=y staged_flow=y staged_boot_go=y`（export face 零 warn+manifest 含 assets/game.flow.json+staged flow=gameover.bsn+staged 独立启动 GameOverRoot=1/MenuRoot=0）→改 menu.bsn→重导→staged flow=menu.bsn→staged 独立启动 MenuRoot=1/GameOverRoot=0（console:10-12）。「改→重导→变」闭合 |
| 9 | 清单校验与坏数据 | **PASS** | editor face 两条 warn 原文归档（leg-warn-text.txt：not in the scene list / not on disk）+游戏回落原文亲读（`game flow: the start scene 'ghost.bsn' is not on disk; starting from 'menu.bsn'`，direct-ghost.log:4）+导出 face flow_warnings 含 ghost.bsn（console:15-17）。⚪「修正后三面清零」实为编辑器 face 一面复验（§七-3） |
| 10 | PIE 双语义 | **PASS** | play=菜单起步（MenuRoot=1/Sun=0，断言在游戏在场时）；play_current（scene.bsn tab）=Sun=1/HudRoot=1/MenuRoot=0/MenuUiCamera=0/player=1——boot 映射使流状态=Level 与屏上世界一致，S6 错位不存在（console-flow:4-5；行内 menu_up=0 为 stop 后采样，非断言值） |
| 11 | 编辑器再编辑闭环 | **PASS** | console:20-22：menu.bsn 打开（scene_bsn 确认 MenuRoot）→MenuTitle 改 "T13t3 Flow Title"→Save 盘上 1 hit→Play 标题命中=1→staged menu.bsn 含编辑+staged 独立启动命中=1（T12 格 9 五点链直系迁移） |
| 12 | 回归根 | **PASS** | T10 拾取 0→3（->3/3/3）+level-clear line true；T09 STAND_FLOW_PAUSE tap1=true/tap2=false+frozen=true（暂停中 held W 坐标逐位恒等）+resumed=true；T11 walked=true（位移 3.50m）+jumped=true（y +0.50）；CELL12d player id 全程恒等；Stop 铁证=四种子 SHA 归档（seed-shas-game-phase.txt） |

**矩阵结论：12/12 PASS 成立，零环境降级格。** 断言窗口与 T12/T11 形态一致性：boot 精确
计数、零残留精确 =0、health ±0.01、sig 全串相等——同形；一处如实记档：cell 4 Restart
位置窗 x/z ±0.05（T12 为 ±0.02，实测落点误差 0.000，且 headless
`a_restart_lands_the_run_back_where_it_began` 以 `assert_eq!` **精确相等**钉 PLAYER_SPAWN——
数字级保证由零容差 guards 承载，见 §七-5）。

## 三、T12 重钉对照表复核（game_ui.rs 7 件迁移 + game_flow_template.rs 3 新件）

> 任务书提及「program_ui.rs」——实际重钉面为 `tests/guards/game_ui.rs`（952 行）+
> 新 `tests/guards/game_flow_template.rs`（844 行）；`git diff` 无 program_ui.rs。

| T12 件 | T13 源码现状（亲读） | 断言语义裁定 |
|---|---|---|
| ①load（U1 红绿） | 保留：红腿 Node=0+BindFailures 空原样（:348-373）；parts 收缩为 [HealthBar,HealthFill,HealthText,PickupsText,ResumeButton]；veil=PauseScreen srgba(0,0,0,0.6) 精确断言原样（:431-436） | **忠实迁移**（Start/Restart 按钮随四屏出 hud，veil 绑定退役见②） |
| ②screens follow state | 改「veil follows its bool」：Hud 恒 Inherited（注释明言旧 `not(menu)` 绑定随 menu 屏退役——「the menu is a world now, not a bool」）+paused 翻转双向（:457-491）；menu/gameover 屏断言整体移出 | **②veil 绑定退役=如实重钉非残留**：T12 的「bool 驱动四屏」语义由「States 驱动三世界+bool 驱动两屏」承接，且世界级断言（MenuRoot/GameOverRoot 在场+零残留+相机随态）比 T12 的 Visibility 断言**更强** |
| ③bar binds data（U3 红绿） | 保留：0.87→0.3→钳 0 双档+BindFailures 红腿原样；终态断言 `game_over` bool → `flow_of()==GameFlow::GameOver`（+一帧时序注释「a NextState set lands the frame after」）（:496-590） | **③bool→State\<GameFlow\>=忠实重钉**：断言对象升级为互斥状态机真值，强度不减 |
| ④buttons red-green | 改 Resume 单按钮（红腿：无 observer 点击不改态；绿腿：literal→observer→veil 落）；Start/Restart 按钮→状态断言移交 game_flow_template ①②（click()/flow_of 断言） | **忠实迁移**，无断言净损失 |
| ⑤四分辨率布局 | 800×600/1280×720/1920×1080/2560×1440 四档原样；与 `git show main:tests/guards/game_ui.rs` 逐断言对照：veil 全充满（角 0,0+尺寸=窗口，原 StartScreen 位换 PauseScreen）、HudRoot 全窗口、HealthBar `12.0 / [11,40) / 180×10` **逐字同数**、按钮 inside-window+centered ±2 **逐字同式**（原 StartButton 位换 ResumeButton）；overlay 腿翻 paused 后测量 | **⑤数字未放松：亲证成立**（逐断言 diff 同判，仅测量对象随四屏→两屏演进切换） |
| ⑥pause gate | 门控 `actions.just_pressed("Pause") && flow.get()==&GameFlow::Level`（:862-870 port 与模板同形）；六腿：menu 态 W 死/Level 行走 0.4/paused 静止/Escape 双向/Interact 扣血 85/GameOver 态再死（:759-859） | **⑥门控判式=bool 合取→States 判式，忠实重钉**（三态世界上语义等价、菜单/结束两态全覆盖） |
| ⑦typo 红绿 | 原样零改（currrent→current 同件修复落值+台账清零，:881-952） | 原样 |
| （新①）三文档全链 | boot→Start→血尽→Menu 三循环：每停靠点 Counts{entities,members,roots,cameras} 恒等+逐点零残留+**live_failure 精确 1 条**（hud 计数通道无物理预期形，多即双注册缺陷签名）（:515-707） | T12 四屏断言的世界级升级版；**plan 格 5 的 JackdawSceneMember 恒等由 headless Counts.members 承载**（真机脚本七元组数的是 Root——见 §七-6） |
| （新②）Restart 数字级 | 玩家实体 id 恒等+health=100（直读 config）+PLAYER_SPAWN `assert_eq!` 精确+level Counts 恒等+血条 1.0（:712-789） | T12 五断言全数迁移、零放松（含暂停态血尽清 paused 边） |
| （新③）boot 映射 | 纯腿 menu/gameover/scene/嵌套路径四判+gameover boot app 级+level boot（=play_current 形态）app 级「OnEnter 先于 Startup 必须无双重生成不崩」（:794-844） | S6/格 10 的 headless 半边 |

**guards 计数亲核**：main=241、HEAD=244（`#[test]` 逐文件计数），+3=game_flow_template
新件，**零删除**。teaches：ui/health/scene_flow/contract_files 四针重钉在源码亲读
（scene_flow 针断言三文档名+两新种子标记与 Action literal；ui 针 two-overlays+三 gone 项
`#StartScreen`/`#GameOverScreen`/`GameState).menu`；`register_function(not)` 注册行保留——
与报告「保留注册、文档示例退役」一致）；scaffold 套件 88 passed=teaches 88 亲读。

### 重钉裁定（任务书问句：重钉是否等于回归？）

**裁定：重钉≠回归，判「语义保持的等强/增强迁移」。** 依据三点：①逐断言对照下
⑤ 的数字与断言式**逐字未放松**（唯一窗口变化在真机 cell 4 ±0.02→±0.05，headless 零
容差兜底，§七-5）；②被移除的 T12 断言（四屏 Visibility、game_over bool 终态、Start/
Restart 按钮翻转）在 T13 全部有**更强**的对应物（世界级零残留+Counts 恒等+States 真值，
实体计数维度比 Visibility 维度细）；③guards 总数 241→244 净增零删除，T12 面的 7 件
在 guards 亲跑中全绿。T12 语义**零残留**的不是旧形态的代码，而是旧形态的**保证**——
这正是方案 §二决策 3-A「拆分而非废弃」的验收含义。

## 四、两件升级案评估（回流主控证据包）

### 1. A6 prefab watcher（`prefab_file_change_triggers_reload`）——**升级 🔴 立项建议：成立**

QA 独立四腿复核（全部亲跑，buglist A6 原文处置口径「连续两轮全量零复发即可降级 ⚪ 销案」
今日被反向满足）：

1. **全量形态**：QA 亲跑 `cargo xtask integration` 5381/5382，唯一红同件同签名
   （prefab_lifecycle.rs:714，`Got ["v1"]`），**3 试全败**（8.4-13.4s）——与程序两轮
   （各 3 试全败，t13t3_gate_integration.log/-rerun2.log 亲读核实）合计**今日 3 轮 ×3 试
   连红**。
2. **二分定案复核（程序声称「干净 main 同红」但无归档日志——QA 补齐）**：`git worktree`
   签出基线 main（3fe6aa7d，不动分支），共享 target 冷编后跑全 prefab 二进制：
   **干净 main 同红 88 passed/1 failed（19.59s），同件同签名**（panicked at
   prefab_lifecycle.rs:714）——程序的 stash 二分定案**独立复现成立**；同 worktree 隔离
   单跑 1.89s 绿。
3. **本任务树形态**：全 prefab 二进制（89 件 in-process 并行）**两次亲跑同红**（88/1，
   18.59s 等）；**隔离单测 3/3 绿**（1.86-2.09s）——红跟随「二进制内并行负载」形态，
   绿跟随隔离形态，两树完全一致。
4. **零交集+环境因子**：`git diff --name-only main...HEAD` 亲核 18 文件与 prefab/watcher/
   scene_io 域**零交集**；上游 45e15e7b 血统（A6 在案）。本轮新增实测：integration 期间
   数据卷 **100% 满（余 1.9GB）**，腾至 46GB 后全二进制形态**仍红**——触发器是测试自身
   二进制内 89 件并行对 FSEvents 3 秒预算的挤压，磁盘高压为加重因子（scaffold_e2e 即因
   ENOSPC 首跑失败，§一-10）。T12 轮同机两轮全绿=跨日机器态敏感。

**裁定**：非产品缺陷、非 T13 引入（双树同红+隔离绿+零交集三重）；但 A6 的「观察账」
定性今日失效——满载/满盘下该件**确定性红**，`cargo xtask integration` 在本机当前机器态
**不可全绿**。**建议：按 🔴 立项**（门禁基建票，非产品 🔴），修复方向维持 A6 原案并加一条：
事件驱动等待或预算随负载自适应（测试侧 3s `generous` 注释已失义）；**并账小项**：
scaffold_e2e 临时工程清理泄漏（失败遗留 46GB、成功遗留 17GB 实测，§七-7）是同一「磁盘
高压伤门禁」家族，建议同票治理。T13 门禁口径：按 T12 先例以「单红=已定案环境票+闭合
证据链」放行，integration 的 5381/5382 如实入账。

### 2. N13（PIE drain swap_remove panic）——**升级处置优先级：建议成立**

QA 对 `loop/t13t3-live/editor-game.log`/`editor-flow.log` **逐条原文记数**：

| 相 | swap_remove panic | drain_game_events（system） | cleanup_session_on_stop（system） | despawn（Command） |
|---|---|---|---|---|
| game（01:20-01:26） | 11 | 5 | **1**（01:26:08.505，紧随 pie.stop 01:26:08.357=stop 形态新样本） | 5 |
| flow（01:46-01:49） | **11（程序未计）** | 4 | **3**（三处 stop 时刻） | 4 |
| **合计** | **22** | 9 | **4** | 9 |

- **程序报告勘误**：「game 相 11 条（drain 9 + cleanup 2）」——总数 11 ✓，但归档日志的
  实际归因是 **5+1+5**（9/2 与日志不符）；flow 相另有 **11 条未入账**；cleanup 形态合计
  **4 条非 2 条**。方向不变、刻画更强（§七-1）。
- **stop 形态新样本确认且加厚**：`cleanup_session_on_stop` 4 条（T11-T3 发现的第二受害
  系统），全部 swap_remove 同族签名（`is 0 < len 0` 空 vec 退化形 3 条+`is 1 < len 0` 1 条
  ——第三种变体 `is 1 should be < len (is 0)` 在案，buglist 刻画可再补一笔）。
- **复发率**：本轮 2/2 个 PIE connected 相全中（22 条），与 T11-T3 测定的 **100%**
  （10/10 轮、57 条）连续一致；全部被 bevy 错误处理器捕获、编辑器存活、15 腿 PASS 不受扰
  （两相日志尾部的 pie.stop/game.export 均成功执行=operator 管道在归档轮 functioning）。
- **受害面扩充至四类**：drain 系统+stop 清理系统+**despawn Command**（9 条，T12 起已知）
  +（T11 原刻画 bevy_ecs 三处无护航点）——「exclusive system 排空 vs 陈旧 EntityLocation」
  的结构性竞态刻画维持。
- **升级依据**：①主路径（每次 Play/Stop）100% 触发，仅靠 Mac 错误处理器兜底，旧机形态
  直接杀死编辑器（T11-T3 在案）；②**「operator 管道挂起」形态**：程序报告称「本轮实录
  00:43:40 后 input.pointer 全部悬空」——**归档无存活证据**（全 archive 无 00:4x 时间戳；
  归档轮指针 sweep 正常命中、pie.stop 正常返回；中间轮已被脚本 `: >` 覆盖，报告所述
  run3/run4 同样不在档）。该形态在 T11-T2 有「PIE 全形态崩」在案先例，故**绕行决策
  （cell 4/5 用 `world.trigger_event`）维持合理**，但「本轮实录」一词超出具证范围（§七-2）。
  若挂起形态坐实，则 PIE panic → operator 管道不可用 → **用户 Play 主路径冻结**，与前述
  合并即双受害系统。**建议：N13 处置优先级上调**（挂账→排期立案），修复抓手沿用 buglist
  刻画（①投影重入→②bevy_ecs 陈旧 location→③树索引上游竞态），并加「PIE connected ×N
  连跑+满盘/负载态」作为复发率与挂起形态的标准测法；真栈仍需 Windows 侧 RUST_BACKTRACE
  （Mac debug 不可用，T11-T3 口径）。

## 五、QA 放行清单对照（方案 §三-T3 QA 清单，全任务）

| 条目 | 裁定 |
|---|---|
| T1/T2/T3 各自验收全绿 | T1 QA PASS（五门亲跑+S2 负向复演：回退 lib.rs→红→还原→绿，`t13-t1-qa.md` §三）；T2 QA PASS（五门亲跑+chain-run3→run4 warn 红绿+PIE 优先级针，`t13-t2-qa.md`）；T3=本轮（§一/§二） |
| S1 红→绿（启动场景） | 红=无 flow.json 时启动场景唯一来源是模板字面量（T2 红）；绿=三形态从配置启动（格 7 Play/direct+格 8 staged 独立启动+格 1 开箱） |
| S2 红→绿（切换原语） | 红=换绑 no-op 实测（T1 归档红证+QA 负向复演）；绿=`respawn_on_scene_root_change`（`Changed<JackdawSceneRoot>,With<SceneSpawned>`，runtime lib.rs:640-648 亲读）+去抖按 AssetId（T1 QA ②③审查） |
| S3 红→绿（清单零面孔） | 红=拼错清单零反馈（T2 chain-run3 LEG_WARN_FAIL 原判）；绿=warn 三面（编辑器 status bar/导出 face/游戏回落，格 9 三面原文在案） |
| 铁证一：往返无残留/无重复加载 | 格 2/3/4/5 四腿（零残留精确 0+sig 回首载同串+三循环七元组恒等）+headless game_flow_template ①（Counts 含 members 恒等）✓ |
| 铁证二：导出从指定场景启动 | 格 8 五点链独立证据（改→重导→staged 独立启动变）✓ |
| 铁证三：跨场景对象规则 | 格 6（玩家 id 三站恒等/拾取 id 每轮更换）+book 规则表（§六）✓ |
| 铁证四：启动场景可配 | 格 1/7（开箱 menu+set→三形态 gameover→复原）✓ |
| T01-T12 防线逐条指认 | **T02**=game_ui ⑦ typo 红绿（亲跑绿）；**T03/T04/T05**=guards 244 内 batch_undo/atomic_writes/asset_lifecycle 等既有件全绿+fast 2975；**T06**=格 10 双语义+格 12 Stop 铁证（四种子 SHA）；**T07**=格 8（manifest 收编+staged 独立启动）；**T08**=guards ② reset_run 直读 config（health=100）+格 4；**T09**=guards ⑥ States 判式+格 12b Escape 双向/frozen；**T10**=格 12a 拾取 0→3+level-clear+格 3 hazard 血尽；**T11**=格 12c walk/jump+格 6 id 恒等+guards ⑥ 菜单/结束门控；**T12**=game_ui 7 件亲跑全绿+⑤数字未放松亲证+格 2/3/4；**T13-T1/T2**=game_flow.rs（T1）+game_flow_config.rs 7 件+runtime game_flow 10 件（libtests 在册）+格 1/7/9。**T12 重钉面=重点豁免对象，裁定见 §三（不构成回归）** |
| quick 门（T1/T2）/全量门（T3） | T1/T2 QA 各五门亲跑 PASS 在案；T3 全量门=§一（10 门亲跑） |
| 三纪律 | 无 RUST_BACKTRACE（QA 脚本 unset+全程无 backtrace 输出）；warn 扫描 0 缺陷形态（§一）；N13 记数在案（§四-2，以 QA 计数为准） |

## 六、book 新章核对（方案 §三-T3-5 书单）

`book/src/user-guide/game-flow.md`（164 行，c82550c7 新增）逐项亲读：

| 书单项 | 落点 | 判 |
|---|---|---|
| 启动场景与 game.flow.json | §Where a run begins（字段语义/路径口径/三形态同读+优先级序 play_current>flow>代码默认+缺文件安静/坏文件 warn 回落） | ✅ |
| 构建场景清单与校验 | §The scene list and its validation（scenes 可选不强制/校验时机两处+导出两入口/逐项检查/never a refusal） | ✅ |
| 运行时切换 | §Runtime switching（States 枚举+一行换绑代码块+卸旧/保根/异步就绪/SceneRefused+`Cannot spawn scene` warn+按路径去重=往返计数归位+boot 映射=PIE 对齐） | ✅ |
| 跨场景对象规则表 | §Cross-scene objects（三行表：成员随亡/代码 spawn 存续/Resource 存续+reset_run「switching is the reset」restart 语义段） | ✅ |
| UI 场景相机纪律 | §Cameras（Camera2d+IsDefaultUiCamera+DespawnOnExit 代码块+黑屏首嫌疑提示） | ✅ |
| PIE 双语义 | §Where a run begins 优先级段+§Runtime switching boots 段（play_current=预览在前场景，boot 对齐） | ✅ |
| restart 语义 | §Cross-scene objects 第三行段（「Restart is not special」） | ✅ |
| 决策 8 特别项 | 「Prefab instances and nested scenes follow their host scene」显式行+DontDestroyOnLoad 级机制「no current user and is not built」一句话挂起（:146-149） | ✅ |
| SUMMARY | SUMMARY.md:26「Game Flow」排 :25 Game UI 后 | ✅ |
| 交叉引用 | game-ui.md×7（两屏改写亲核：屏表仅 #PauseScreen，StartScreen/GameOverScreen 全章无）、game-input.md:50、game-parameters.md:49、player-controller.md:43、physics.md:138——全亲读指向正确 | ✅ |
| 断行链接扫描 | 7 个本轮触碰 book 文件全扫：**0 处**行内链接目的地跨行（T12 🟡 缺陷类未复发） | ✅ |

**右键 GUI 30 秒手验清单在位**：程序报告 §六-4 五项（①右键非启动场景→Set as Startup
Scene→状态栏+marker+face 读回一致；②右键当前启动场景→「Startup Scene ✓」；③健康 flow
无 `game flow:` warn；④新工程 Play→菜单→Start→关卡→血尽→Restart→Menu 两圈无残留；
⑤双击 menu.bsn 改标题 Save→Play 生效）——与本轮 book §The 30-second check 三条+格 11
自动化证据互补，留作用户终手验（本轮真机腿沿用 operator+BRP 结构化面，GUI 合成腿按 T2
QA 降级裁度不重试）。

## 七、偏差与记档分级（QA 视角）

| 级 | 项 | 处置 |
|---|---|---|
| 🟡 | **A6 升级立项**（§四-1）：今日 3 轮×3 试连红+双树全二进制红/隔离绿亲证+零交集+磁盘高压加重；A6 原降级销案口径反向满足；本机 integration 全绿当前不可达 | **建议主控按 🔴 立项**（门禁基建票）；T13 放行按「单红=已定案环境票」先例 |
| 🟡 | **N13 升级处置优先级**（§四-2）：本轮 22 条（非 11）、受害面四类、stop 形态 4 条、2/2 相全中延续 100% 复发率；operator 挂起形态有 T11-T2 先例但本轮声明无存活证据 | **建议上调排期**；报告 N13 记数以本表为准（勘误） |
| ⚪ | 程序报告 N13 归因不精确：11 条的子归因（drain 9+cleanup 2）与归档日志（5+1+5）不符；flow 相 11 条漏计；cleanup 合计 4 非 2 | 报告勘误项；「编辑器存活、各腿不受扰」实质结论不变 |
| ⚪ | 「00:43:40 后 operator 管道挂起」与「run3/run4 留档 console-game.log」均无存活证据（脚本清空重写，归档仅为终轮；归档轮内 operator 管道健康） | 报告措辞降格为「中间轮观察（未归档）」；trigger_event 绕行决策维持 |
| ⚪ | 格 9「修正后三面清零」：实际仅复验编辑器 face（游戏回落/导出 face 修后清零未单独复跑；修正后面由代码路径同一性推定） | 报告勘误项；如需可补一条修后重导腿 |
| ⚪ | 格 12 数字：行走位移实测 3.50m（报告「>2.6m」成立但非实测值）；跳跃 +0.50（报告 +0.48） | 报告勘误项；阈值断言不受影响 |
| ⚪ | cell 4 Restart 真机位置窗 ±0.05 较 T12 ±0.02 略宽（实测误差 0.000；headless 新② `assert_eq!` 精确相等兜底） | 记档；「数字级断言原样迁移」以 headless 零容差件为准 |
| ⚪ | 真机 stop-signature 数 `JackdawSceneRoot`（恒 0，BRP 非反射类型）而 plan 格 5 用词是 `JackdawSceneMember`；Member 恒等由 headless Counts.members 断言承载（程序 ⚪-8 披露了现象未点明 plan 用词差） | 记档；无残留语义由 named/pickup/hazard/cube 计数+headless 双面兜住 |
| ⚪ | **scaffold_e2e 临时工程清理泄漏**：QA 首跑（ENOSPC 失败）遗留 46GB、复跑（PASS）仍遗留 17GB 于 TMPDIR（确定性目录名亲核）；数据卷今日一度 100% 满是该家族的直接后果，也是 A6 watcher 件的加重因子 | 建议**并 A6 票治理**（失败/成功两态都补清理，或固定位置+预清理）；QA 已清场（现余 45GB、零残留、零进程） |
| ⚪ | doctests bind DYLD 环境族第 7 次目击（程序记第 6 次）；带 DYLD 复跑 PASS（T12 口径） | 已知环境账，延续 |

## 八、最终裁决与 roadmap 建议

- **T13-T3 验收标准（方案 §三-T3）**：矩阵 12 格全过（12/12，零降级）✅；验收句铁证独立
  证据（往返=格 2/3/4/5+headless、导出=格 8、规则=格 6+book、启动=格 1/7）✅；T08-T12
  防线回归+guards 244/teaches 88 ✅；全量门 10 门亲跑（8 绿+integration 已定案单红
  A6+doctests 环境族复跑绿）✅；物理双包单跑绿 ✅；scaffold_e2e 冷编落袋（复跑 169.61s
  PASS）✅。
- **T13 整体（T1/T2/T3）**：T1 QA PASS（S2 红绿+负向复演）、T2 QA PASS（S1/S3 红绿+PIE
  优先级针）、T3=本轮；QA 放行清单全项成立（§五）；S1-S8 全部结案有据。
- **VERDICT: PASS——T13 整体闭环。roadmap T13（第 27 行）建议可勾选**，闭环注记建议含：
  验收句铁证独立在案（格 2/5/6/8+headless game_flow_template 三件）；矩阵 12 格含
  「改→重导→变」导出链（格 8）与编辑器再编辑链（格 11）；T12 重钉经逐断言对照判
  「语义保持、数字未放松」；integration 5381/5382 唯一红=A6（本轮 QA 双树四腿闭合证据，
  升级 🔴 立项）；N13 22 条绕行记数（建议上调优先级）；两项 🟡 回流+勘误五项不阻塞。
- 主控合入路径照旧 `--no-ff`（c82550c7 单提交）；台账 T13 行补记；buglist（A6 升级、N13
  增注）/roadmap 由主控合入时写（本轮 QA diff 零产品触碰，亲核成立）。

## 九、用户 30 秒清单（book §The 30-second check+报告 §六-4 落地为可执行手测）

1. **三世界流转**：`jd new my-game`→编辑器打开→**Play**：菜单（项目名标题+Start 按钮）
   →点 **Start**：3D 关卡+HUD（"100 / 100"+"Pickups: 0"）→走进红色 hazard 放血至尽：
   **结束屏**（近黑遮罩+Restart/Menu）→**Restart**：满血回出生点、拾取重生×3→**Menu**：
   回菜单。循环两圈——实体不累积、菜单/关卡/结束互不留残。
2. **启动场景改配置**：Project 窗口右键 `scene.bsn`→**Set as Startup Scene**（原
   menu.bsn 带 **Startup Scene ✓**）→Play 或 `cargo run`：游戏直接进关卡；改回 menu.bsn
   复原。手编 `game.flow.json` 写个不存在的名字→状态栏 `game flow: … not on disk`
   黄字、游戏照跑（回落并点名）。
3. **菜单再编辑**：Project 窗口双击 `assets/menu.bsn`（2D 画布）→改标题→**Save**→
   **Play**：新标题上屏；`game.export` 导出双击：新标题仍在。
4. **GUI 抽查（程序 §六-4 移交）**：右键任意 .bsn 应见「Set as Startup Scene」项；健康
   工程状态栏应无任何 `game flow:` warn。

## QA 会话产物索引

- 门禁：`loop/reports/t13t3_qa_{fmt,clippy_ws,clippy_physics,libtests,guards,gate_fast,
  gate_integration,doctests,doctests_bind_rerun,docs,scaffold_e2e,scaffold_e2e_retry}.log`
  （12 件）；脚本 `loop/qa/t13t3-qa-gates.sh`（串行 10 门，unset RUST_BACKTRACE）。
- A6 四腿：integration 亲跑（t13t3_qa_gate_integration.log）+本树隔离 3×绿与本树全二进制
  2×红（会话实录，未归档文件，数字在 §四-1）+**干净 main worktree 全二进制红/隔离绿**
  （同上；worktree 已拆除，分支未动）；程序两轮归档交叉亲读（t13t3_gate_integration.log/
  -rerun2.log：各 3 试全败同签名）。
- 核验对象：`loop/t13t3-live/` 16 件（console 两相全文+editor 两相逐条记数+direct/staged
  启动日志+leg-warn-text+seed SHA）；T1/T2 证据指针开卷；`tests/guards/game_ui.rs`/
  `game_flow_template.rs`/`game_flow_config.rs`、`git show main:tests/guards/game_ui.rs`
  对照、模板四件+flow.json 种子、teaches 针、book 7 文件+SUMMARY+断行扫描、
  `crates/jackdaw_runtime/src/lib.rs`（原语）、`src/game_flow.rs`/`src/game_export.rs`
  （face）盘上亲核。
- 进程收尾：QA 复查零 jackdaw/t13t3-game 残留进程、零 TMPDIR 残留（QA 清出 46GB+17GB
  两笔）；门链与编辑器未同窗；数据卷余 45GB。
