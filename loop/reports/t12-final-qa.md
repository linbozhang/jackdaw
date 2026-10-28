# T12 终验 QA 报告：任务 3（收官段）+ T12 整体终验（只验不修）

> 验收对象：分支 `loop/t12-game-ui` @ **912c681d**（基线 main=6d158469；T3 提交=book 5 文件
> [SUMMARY+1 / game-input+6 / game-ui 新章 194 行 / physics+5 / player-controller+4] +
> `t12t2-channels-summary.txt` 重归档，**零产品代码**）。程序报告：`loop/reports/t12-t3-report.md`。
> 前置：T1 QA（rework e984ee1f 后 PASS，§十一）、T2 QA（62a85731 PASS；勘误+移交由主控
> fb0156bc 落账，A5 已立 buglist:449）。
> QA 证据：**Mac 全量门 10 门亲跑**（归档 `t12t3_qa_*` 12 件，脚本
> `loop/qa/t12t3-qa-final-gates.sh`，全程未设 RUST_BACKTRACE）；`loop/t12t3-live/` 21 件
> 逐位核对 + 抽格 1/9/12 原始日志全文；T2/T1 旧证据指针逐一开卷；scaffold 占位源码、
> 模板/书籍/暖工程/两个 t12t3 fixture 工程盘上亲核。门链与编辑器未同窗（T3 报告 §九-7）。

## 〇、结论

**PASS（T12 整体，含 roadmap T12 可勾选建议）**——矩阵 12 格逐一核实 12 PASS 成立（格
1/4/9/12 本轮新证据亲核，格 2/3/5/6 引用+新腿加厚，格 7/8/10/11 引用指针开卷属实+零产品
改动豁免合理）；验收句四铁证各有独立证据；QA 移交五项全部落账，**restart 拾取复位之争
判程序对**（T2 QA 原判证伪，三重证据在案）；book 新章六节+三交叉引用+SUMMARY 在位（一处
🟡 断行链接）；Mac 权威全量门 **integration 两次独立全绿 5348/5348（0 failed）**、其余门
全绿/doctests bind 环境族复跑 PASS。偏差 **2 🟡 + 8 ⚪，零 🔴**（§六），🟡 均不阻塞合入
（一行 book 链接修复 + 一个 flaky 小票建议）。

## 一、Mac 全量门亲跑（权威口径）

| # | 门 | 命令 | QA 亲跑结果 | 归档 |
|---|---|---|---|---|
| 1 | 格式 | `cargo fmt --all -- --check` | **CLEAN**（EXIT=0，日志 0 字节） | `t12t3_qa_fmt.log` |
| 2 | Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **CLEAN**（EXIT=0，零 warning/error 行） | `t12t3_qa_clippy_ws.log` |
| 3 | Lint 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **CLEAN**（EXIT=0） | `t12t3_qa_clippy_physics.log` |
| 4 | 单测 | `cargo test --workspace --lib` | **2970 passed / 0 failed**（EXIT=0） | `t12t3_qa_libtests.log` |
| 5 | fast | `cargo xtask fast` | **2970/2970 passed, 0 skipped**（EXIT=0，≥2970 达标） | `t12t3_qa_gate_fast.log` |
| 6 | guards | `cargo test -p jackdaw --test guards` | **229/229 passed**（61.04s；含四档分辨率+typo 红绿） | `t12t3_qa_guards.log` |
| 7 | scaffold_e2e 冷编 | `cargo test -p jackdaw --test scaffold_e2e` | **1/1 passed**（嵌套冷编 148.48s 落袋） | `t12t3_qa_scaffold_e2e.log` |
| 8 | doctests | `cargo test --workspace --doc --features dylib` | jackdaw_bind 1 失败=**环境性**（rustdoctest 子进程丢 DYLD，`libstd-614bb9b33bbc23af.dylib` 找不到——**第 5 次目击**，T08/T09/T10/T11/T12 同族）→带 toolchain DYLD 单包复跑 **PASS** | `t12t3_qa_doctests.log` + `t12t3_qa_doctests_bind_rerun.log` |
| 9 | docs | `cargo doc --workspace --no-deps` | **EXIT=0**；17 条 warning（§六-5 归因） | `t12t3_qa_docs.log` |
| 10 | integration | `cargo xtask integration` | 首跑 5347/5348+**1 flaky 红**（§一-1）→**复跑 5348/5348 passed, 0 skipped, EXIT=0（780.7s）**——0 failed 合同成立 | `t12t3_qa_gate_integration.log` + `t12t3_qa_gate_integration_rerun.log` |

**程序归档交叉复核**（`t12t3_*` 12 件）：fast 2970（27.77s Summary 亲读）/integration
5348（700.46s）/guards 229（59.94s）/scaffold_e2e 143.60s/doctests bind 复跑 EXIT=0/docs
EXIT=0——与报告 §六表逐项一致，无隐瞒。**integration 权威口径 = 两次独立全绿**（程序
00:50 全绿 + QA 复跑 03:0x 全绿），任务书「5348 全绿，须 0 failed」成立。

**§一-1 首跑单红诊断（如实记录）**：`jackdaw::prefabs
prefab_lifecycle::prefab_file_change_triggers_reload` 3 试全败（panic
`watcher reloaded prefab; v2 should be in world. Got ["v1"]`，prefab_lifecycle.rs:714——
文件监视器在 7s 窗口内未完成重载）+`add_component::add_component_is_offered…` flaky
2/3（TRY1 败 TRY2 过）。**定性：负载敏感 flaky，非产品缺陷**——①隔离复跑两项均 PASS
（prefab 件 1.33s vs 满载 7s 窗口；add_component 2.10s）；②该测试系上游 PR #379
（45e15e7b）引入，T12 全 diff 与 prefab/watcher/stage 域**零文件交集**（git 亲核）；
③同一工作树两次全量一红一绿+程序先前全绿。⚪ 建议开小票（满载下 watcher 重载窗口预算），
不入 T11 §八-2 已知环境红清单（该清单无此件）。程序侧同轮交叉编译负载（QA 的 bind
doctest 复跑与首跑 integration 短暂同窗）不排除为诱因之一，如实披露；失败时间点在复跑
结束之后，且复跑全量绿已证非确定性。

**warn 形态扫描（standing 腿执行）**：四缺陷形态 `cannot apply|cannot read|does not
read as|UnresolvedTypes` 扫 `loop/t12t3-live/` 21 件 **0 条**（程序声称亲核成立）；QA
guards 亲跑日志 1 条=`scaffolded_component_flow.rs` 故意 `NotBuiltYet` fixture（测试
对象本身，与 T1/T2 QA 归因一致）。在案 warn 逐条精确归因见 §六-4（程序报告的归因句有
两处不精确，实质结论不变）。

## 二、矩阵 12 格逐位核实（报告 §一表 vs 原始日志）

**抽 3 格原始日志全文亲读**（格 9 本轮核心新证据、格 1 开箱真跑、格 12 无物理 Interact
全链），其余各格证据指针逐一开卷：

| # | 场景 | 判 | QA 核实（证据原文位） |
|---|---|---|---|
| 1 | 新工程开箱四屏 | **PASS** | `t12t3-cell1-console.log` 全文亲读：EDITOR_READY（**fresh project** `loop-mac/t12t3/t12t3-ui`）→boot `state=true,false,false`+StartScreen=Inherited/Hud=Hidden→sweep_click 真命中 (700,787)→`false,false,false`+Hud=Inherited/Start=Hidden/**pickups=3 FallingCube=1 player=1 rig=1**+health_text='100 / 100'——T11 玩家链在新工程活体在场 |
| 2 | 按钮触发真行为 | **PASS** | 旧指针开卷：`t12t2-pie-summary.txt` 十腿含 C1_START_BUTTON/C3_RESTART_RESET（真 picking）；新：`t12t3-live-console.log` L18-21 CELL2_RESTART_RESET **数字级五断言**（before: game_over=true+GameOverScreen=Inherited+pickups_alive=0；after Restart: health=100.0/PickupCount=0/pickups_alive=3/pos=(-2.0,0.86,0.0)=PLAYER_SPAWN/GameOverScreen=Hidden）+CELL5 Resume 点击路。脚本窗口亲核：health ±0.01、pos x ±0.02/z ±0.02——**未放宽** |
| 3 | 血条绑数据 | **PASS** | 旧指针开卷：`t12t2-pie-console.log:27` 亲读「health 100.0 -> 70.0, Progress.value=0.699999988079071, HealthText=70 / 100」（=70/100 精确）；T1 guards 两档（0.87/0.3/钳 0）在 fast+guards 双账本；新：格 12 Interact 路 100→85/0.8500000238418579/'85 / 100'（cell12 console :21）+live 行走 hazard 真触 100→85（live console :10-11）——**hazard/Interact 双伤害源双通道** |
| 4 | HUD 第二数据 | **PASS（新）** | `t12t3-live-console.log` L9-13：真键走位拾取计数序 0→0/3/3→3+`text='Pickups: 3'`+**「level-clear line in the Game panel log strip: true」**（T10 既有 level clear 行为不破坏+PIE 日志通道活证）；行走途中 hazard 真触扣血如实标注为 damage 通道活证 |
| 5 | 暂停双路 | **PASS** | 旧：T2 C3_PAUSE_RESUME（Escape 与 Resume 等价）开卷属实；新：live console L14-16 CELL5_PAUSE_DOORS——Escape 开（屏 Inherited）+**held W 位移为零（frozen=true，坐标逐位恒等）**+Resume 点击关（state 复原+PauseScreen=Hidden） |
| 6 | 绑定错误可见 | **PASS** | 运行态：T2 C4_RED/C4_GREEN（warn 原文含 `path 'currrent' on 't12t1_game::PlayerHealth'` 亲读在案+修正消失）+T1 headless 红证（`t12t1_qa_probe_red_health.log`：BindFailures=2+Progress 恒 1.0）；**作者态新腿**：T02_BIND_CARD 三处一致（§四-1）；格 12 no-modules 形态 warn 原文归档（unknown type/no context）——**两面在两种模块形态可见** |
| 7 | 布局·headless | **PASS** | `one_layout_holds_across_the_four_common_resolutions` 在 guards 229 件内（程序 59.94s+**QA 亲跑 61.04s 双归档**，grep 亲数命中）；四档 800×600/1280×720/1920×1080/2560×1440 每档同断言 |
| 8 | 布局·真机 | **PASS** | `t12t2-resolution-console.log` 开卷：RES_TIER_A window=1920x151/RES_TIER_B=1920x170，两档 StartScreen(overlay) 精确充满+**HealthBar 180x10 恒定**+StartButton 84x24；条带形通道差异按方案 266-268 行允许记档，16:9 四档归格 7 |
| 9 | 编辑器再编辑闭环 | **PASS（新，核心）** | `t12t3-editor-chains-console.log` 全文亲读五点链：①文档两编辑可见（doc region 原文：`Text("T12t3 Edited Title")`+HealthFill `Srgba{0.85,0.15,0.15}`）②Save SHA `1007b0d3…→2d8c5968…`（盘上变更）③PIE Play 生效（`title_hits=1`+`fill_color Srgba 红主导`）④`game.export` staged hud.bsn **含两编辑**（QA 盘上 grep=1/1 实物亲核，staged 目录 export-manifest.json+210MB exe 在）⑤**staged exe 独立启动 title_hits=1**（cell9-staged-boot.log）。「编辑→保存→重开→Play→导出」全环活证。⚪ 注：第二编辑=改标题（非矩阵字面「加按钮」），链路本质不受影响（§六-6） |
| 10 | 四通道一致 | **PASS** | T2：parity-DIRECT/EXPORT 双 VERDICT PASS 开卷（boot state 干净）；本轮格 9 导出腿+cell1/12 PIE 腿再证；格 9 补上「导出保留」行为级一环 |
| 11 | Stop 铁证回归 | **PASS** | T2 `t12t2-stop-console.log:7` 「VERDICT_STOP_PROOF: PASS (both documents untouched)」开卷；本轮未复跑=零产品改动豁免（程序如实声明）；**QA 旁证亲核**：暖工程盘上 hud.bsn SHA=1007b0d3（=cell9 编辑会话起讫恒等+已复原种子） |
| 12 | 无物理形态回归 | **PASS（新）** | `t12t3-cell12-console.log` 全文亲读三腿：CELL12_UI_PRESENT（**no-modules project** `t12t3-nophys` boot 干净+StartScreen=Inherited+'Pickups: 0' 静态+'100 / 100'+预期 warn 上 strip）→CELL12_INTERACT_DAMAGE（E 键 100→85+Progress 0.85+文本同步=Interact fallback 真行为）→CELL12_NO_AVIAN（RigidBody 双查询 0/0+schema avian 0，QA 亲读 Cargo.toml 零 avian 引用）；teaches 退场断言=fast 2970 内 scaffold 套件（ui/health 两 teaches 名亲读在 fast 账本） |

**矩阵结论：12/12 PASS 成立，零环境降级格。** 断言窗口与 T11/T2 移植形态一致性：live-chains
boot 精确串/`shown()`=Inherited|Visible（T2 §十-2 同形）/restart 位置 ±0.02——**未放宽**；
cell1/cell12/editor-chains 断言逐条亲读同判。

## 三、QA 放行清单对照（方案 330-338 行，全任务）

| 条目 | 裁定 |
|---|---|
| T1/T2/T3 各自验收全绿 | T1 QA rework 后 PASS（§十一四项落实亲核在案）；T2 QA PASS（勘误+A5 由 fb0156bc 落账亲核）；T3=本轮（§一/§二/§五） |
| U1 红证（无 spawn_hud 无 UI） | T1 guards ①红腿（Node 实体数=0+BindFailures 无=T12 前形态钉死）——`t12t1_qa_guards.log`，`game_ui.rs` 双 app 对照在案 |
| U2 红证（typo Play 静默改前/可见改后） | 机制层=T1 guards `a_typoed_field_fails_loudly…`（台账非空+Progress 恒 authored）+QA 红证复演探针；架构面=方案事实七（`StateEvent::Log` 两端零接线 grep）；绿=Game 面板日志条（T2 C4+本轮格 12 strip 活证） |
| U3 红证（无 Health 时 BindFailures） | T1 guards ②红腿+`t12t1_qa_probe_red_health.log`（BindFailures=2 原文）；绿=两档 ratio 精确+钳 0+game_over |
| 铁证一：按钮真行为（格 2） | 格 2 独立证据（真 picking 状态断言+数字级五断言）✓ |
| 铁证二：血条绑数据（格 3） | 格 3 独立证据（双伤害源+精确 ratio+文本同步+血尽→结束屏）✓ |
| 铁证三：分辨率布局（格 7+8 双通道） | 格 7 headless 四档+格 8 真机两档像素抽验 ✓ |
| 铁证四：绑定错误可见（格 6 双面） | 格 6 作者态 badge 面（T02 三处一致）+运行态日志面（C4+格 12）双面 ✓ |
| T09（Pause 消费面+改绑） | T1：guards game_input 全绿+handle_pause_action 真翻转重钉（guards ⑥ Escape 双态）；T2：C3 真机双路；**T3：STAND_PAUSE_SINGLE**（一次翻转/两次回原——双注册缺陷机械捕获）+CELL5。改绑面=game-input.md「Rebinding is editing one file」未触碰+teaches input_action_pattern 在 fast 复跑 |
| T10（拾取/hazard） | T1：collect_pickups/PickupCount 零改动 diff+guards physics_triggers；T2：C2 真伤 100→70；**T3：CELL4**（0→3+level clear 不破坏+hazard 途中真触） |
| T11（玩家链+paused gate） | T1：guards player_controller 5 件+WASD 位移双态断言；**T3：格 1**（玩家/rig/FallingCube 在新工程活体在场）+CELL5 frozen 零位移 |
| T02（绑定卡提交链/三处一致） | T2：Bindings 组件保存往返字节零 diff（=落盘面）；**T3：T02_BIND_CARD 显式腿**（component.set 提交链+ECS/文档/卡片面三处一致，§四-1） |
| T03（undo） | T2：fast 2970 机护（记档）；**T3：T03_UNDO 显式腿**（undo 后 ECS+文档双面清零） |
| T06（Stop 铁证=格 11） | T2 VERDICT_STOP_PROOF+T3 旁证（seed SHA 起讫恒等盘上亲核）——格 11 PASS |
| T07（导出 manifest/异目录） | T2：staged 独立启动 parity+export-manifest.json；**T3：格 9 导出腿**（staged 实物 manifest 607B+两编辑 grep+独立启动） |
| T08（GameConfig.player_health 注入语义） | 分布覆盖：T1 注入链（config.is_changed() 门、与 gravity 同构）+doc 改口；T2 缺陷③（开局 game_over 竞态=注入时序）修复合+chain 针+三通道 boot 干净；T3：STAND_CHAIN/cell12 boot state 干净。无单列显式腿，语义面 guards+teaches+真机三面在——接受（如实指认） |
| quick 门（T1/T2）/全量门（T3） | T1/T2 QA 各 7 门亲跑 PASS 在案；T3 全量门=§一（10 门亲跑，integration 两次全绿） |

## 四、QA 移交五项复核（t12-t2-qa.md §七 → T3 落账）

1. **T02 绑定卡三处一致显式腿——成立**。`t12t3-editor-chains-console.log:7` 亲读「T02
   three faces after the edit: ecs=currrent doc_hits=1 card=currrent」；脚本断言亲读=
   editor ECS（world.query 按实体过滤）/文档（scene_bsn grep）/**卡片面**（`selection.set`
   选中→`ui_tree` visible_only:false 取行文本）三独立面。badge 颜色通道非 BRP 可达如实记档
   （文本面已含错误原文，足够）。probe 探针两轮在案（`t12t3-probe*-console.log`，含
   probe2 的 EDITOR_BOOT_FAIL 中间轮——程序 §八-1 如实声明）。
2. **T03 undo 显式腿——成立**。console:9-10「T03 after undo: ecs_typo=0 doc_hits=0」；
   同一 typo 编辑→history.undo→双面清零。
3. **STAND_CHAIN/STAND_PAUSE_SINGLE 常备腿——成立**。live console:3-8：boot state 精确串
   +HudRoot=1+拾取×3+FallingCube+**`hud_swap_defect_line=false`**（脚本 :235 只匹配缺陷形态
   `in place of '[^']*hud\.bsn'`，良性 override info 行不误报——与 T2 QA「三连缺陷方法论」
   口径一致）；STAND_PAUSE_SINGLE（false,true,false→false,false,false，每按一次翻一次）。
   两腿为命名腿入 summary，机械捕获 spawn 链序/双注册两类缺陷。
4. **restart 拾取复位之争——判：程序对，T2 QA 原判证伪**。三重证据：①**源码**：
   `respawn_pickups_on_restart`（`crates/jackdaw_scaffold/src/lib.rs:3256`：despawn 幸存
   拾取+`spawn_pickup_line`+`count.0 = 0`+速度清零，gate=`button != "restart"` return）
   注册于 physics 占位段 :2787（`.add_observer`）——`git log -S` 亲证**自 T1 7515fa11 即在**，
   即 T2 QA 写「拾取复位模板未实现」时该实现已存在（误因：只查了模板 lib.rs.template 本体，
   未查 scaffold 占位族）；②**活证**：CELL2_RESTART_RESET pickups_alive 0→3+PickupCount→0
   数字级；③**teaches 针** :3983（`fn respawn_pickups_on_restart` 在 hazard 形态针集）+
   book `game-ui.md:80-86`「the level comes back with you」教学口径定案。无物理形态无拾取
   系统（文本保持 authored）口径同段钉死。**T2 QA 该记档作废，以本条为准。**
5. **channels-summary 重归档——完成**。文件头 9 行 STALE-INTERMEDIATE-ROUND 标注亲读
   （中间轮四 FAIL=缺陷①-③实锤证据价值说明+终轮 verdict 指向 parity/resolution 各自
   归档），原 verdict 行原样保留——防误读与防篡改两目的均达成。

## 五、book 新章核对（方案 307-312 书单）

`book/src/user-guide/game-ui.md`（194 行，912c681d 新增）逐项：

| 书单项 | 落点 | 判 |
|---|---|---|
| UI 画布 | §The 2D canvas（UI Scene kind/2D 画布+标尺参考线/Add 菜单 UI 控件族/布局预设/对齐吸附/reference_size=画布基准） | ✅ |
| 四屏范本导览 | §The template's four screens（四屏表+GameState 事件流+按钮 literal+Pause 双门一处 bool+restart 语义段 :80-86） | ✅ |
| 绑定教学 | §Wiring a binding（五种 Binding 表+via 注册教学 ratio/not/is_zero+BindContext/wire_hud/HudRoot 接线） | ✅ |
| 分辨率纪律 | §Resolution discipline（percent/flex 优先/px 仅尺寸内边距/reference_size 非缩放因子——决策 5-A 定案） | ✅ |
| 错误两面 | §When a binding is wrong（作者态 badge 行内+tooltip/运行态 Game 面板日志条+30 秒 typo 演示） | ✅ |
| U5 边角 | §One editor edge（UI tab 聚焦 Play=画布预览语义+双 hud 根边界） | ✅ |
| 三处交叉引用 | game-input.md:47-49（`handle_pause_action` 翻 `GameState.paused`+双门同 bool——Pause 消费面真行为化）；player-controller.md:37-39（HUD 观察对象=该玩家实体）；physics.md:134-137（hazard 0b100/0b001 行做真活+HUD 同源 PlayerHealth）——全部亲读在位且指向正确 | ✅ |
| SUMMARY 位置 | SUMMARY.md:25「Game UI」排 :24 Game Input 后 :26 Player Controller 前 | ✅ |
| （超额）旧工程补装/30 秒清单 | §Adding UI to an older project（两行+一文件）+§The 30-second check 三条=方案 325-328 口径 | ✅ |

🟡 一处（§六-1）：:31-32 链接目的地跨行断开。book 无构建门（xtask fast/integration 均不含
mdbook，本机无 mdbook——程序 §五如实记档，QA 同核），仓库 doc 门=`cargo doc` 已绿；
相对链接面 QA 亲扫全书 44 文件**仅此一处**断行目的地，其余全部单行合法。

## 六、偏差与记档分级（QA 视角）

| 级 | 项 | 处置 |
|---|---|---|
| 🟡 | **book `game-ui.md:31-32` 断行链接**：`[When a binding is wrong](#when-a-binding-is-` + 换行 + `wrong)`——CommonMark 链接目的地不得含换行，渲染为裸 markdown 文本（非超链接）；目标锚 `## When a binding is wrong` 本身在位。book 无构建门故漏过「手核」 | **一行修复**（目的地并回单行）；不阻塞合入，建议主控合入前顺手修+全书可加一条「行内链接目的地禁跨行」检查 |
| 🟡 | **integration 首跑单红**（prefab watcher 满载 flaky）：两次独立全量绿+隔离 PASS+零 diff 交集已定性非产品缺陷（§一-1），但系本机首次目击且不在 T11 已知环境红清单——满载下 watcher 7s 窗口预算偏紧 | 建议开小票（窗口预算/重试容忍），不入已知清单；门禁口径维持「0 failed」以两次全绿为准 |
| ⚪ | **N13 本轮 10 次**（cell1 3+live 3+editor-chains 4，victim=jackdaw::pie 族+despawn command，全被错误处理器捕获、编辑器存活、各腿 PASS 不受扰）——**T3 报告零 N13 记数**（方案 §四风险表「绕行+记数」口径未执行）；buglist N13 挂账延续 | 报告勘误项；计数以本条为准 |
| ⚪ | **程序 warn 归因清单不精确**：报告称「no context ×4=格 12 无物理形态预期失败」——实为 4 条中 2 条属格 12（t12t3_nophys 预期形）、**另 2 条+`PickupCount.0`×1（报告漏计）属格 9 staged 独立启动的物理形态早期帧良性 warn**（wire_hud 落位前 warn-once，T1 QA §三已钉的 clear_failure 自清族）；`unknown type`×1=格 12 属实 | 报告勘误项；「零真漏网」实质结论不变（四缺陷形态 0 条亲核成立） |
| ⚪ | docs 17 条 warning 中 1 条=`unresolved link to StateEvent::Log`（`src/pie_game_log.rs:4`，**T2 新建文件**）——报告「全为未触碰 crate 存量形态」措辞不精确（其余 16 条确为存量私有链接噪音） | 报告勘误项；EXIT=0 非阻塞 |
| ⚪ | 格 9 第二编辑=改 StartTitle 文本（矩阵字面「加按钮」的结构级新增未单独抽验）——编辑器通道的结构编辑由画布/控件既有面承载，链路五点本质（编辑→保存→重开→Play→导出）不受影响 | 记档；后续如需可补一条结构级编辑腿 |
| ⚪ | 报告提交注记「book 四文件」实为 **5 文件**（SUMMARY+4 user-guide） | 报告勘误项 |
| ⚪ | QA 首跑 integration 与 QA 自己的 bind doctest 复跑短暂同窗（可能的负载诱因之一，如实披露）；失败点晚于该复跑结束+复跑全量绿证明非确定性 | 本报告 §一-1 |
| ⚪ | 格 7/8/10/11 未复跑——按移交口径豁免（本轮零产品改动，其证据面无新输入）；格 11 有 seed SHA 起讫恒等盘上旁证；格 2/5/6 已有新证据加厚 | 接受（程序 §一注如实） |
| ⚪ | probe2 中间轮 EDITOR_BOOT_FAIL 归档留档；cell9/格 1/12 的 fixture 工程按 T11-T3 §九-3 惯例注入 JackdawRemotePlugin（QA 亲核两工程 Cargo.toml/main.rs，模板本体零改动） | 接受（程序 §八-2 如实） |

## 七、最终裁决与 roadmap 建议

- **T12-T3 验收标准（方案 321-328）**：矩阵 12 格全过（12/12，零降级）✅；全量门（10 门
  亲跑，integration 两次 5348/0 failed，doctests 环境族复跑 PASS）✅；scaffold_e2e 冷编
  落袋 ✅；用户 30 秒清单三条在 book 且可执行（§八）✅。
- **QA 放行清单（方案 330-338）**：全项成立（§三），含 U1/U2/U3 红绿、四铁证独立证据、
  T01-T11 防线逐条指认。
- **VERDICT: PASS——T12 整体闭环。roadmap T12（第 26 行）建议可勾选**，闭环注记建议含：
  验收句四铁证独立证据在案（格 2/3/7+8/6）；矩阵 12 格含编辑器再编辑五点链（格 9）与
  无物理全功能（格 12）；restart 拾取复位口径以活证定案（T2 QA 记档证伪）；integration
  两次 5348 全绿；两项 🟡 回流（book 断行链接一行修+prefab watcher 小票）与报告勘误三项
  （N13 计数/warn 归因/docs 措辞）不阻塞。
- 主控合入路径照旧 `--no-ff`（912c681d 单父）；台账 T12 行补记；buglist/roadmap 由主控
  合入时写（本轮 diff 零触碰亲核成立）。

## 八、用户 30 秒清单（方案 325-328 三条落地为可执行手测）

1. **四屏与真行为**：`jd new my-game`（physics 默认开）→编辑器打开→**Play**：开始屏先见
   （项目名标题+Start 按钮，深色不透明底）→点 **Start**：进入 3D 世界+左上 HUD
   （"100 / 100"+"Pickups: 0"）→走到 (2, 0.5, 0) 红色 hazard（可离开再进重复触发）：
   血条掉、文本同步→血尽出**结束屏**（近黑遮罩）→点 **Restart**：满血 100 回出生点、
   拾取重生 ×3→**Escape**：暂停屏（半透明变暗）+玩家冻结→点 **Resume** 回来。
2. **编辑器再编辑**：Project 窗口双击 `assets/hud.bsn`（2D 画布打开）→选中血条填充改个
   颜色、把开始屏标题改字→**Save**→再 **Play**：两处编辑都上屏（导出构建同样带走）。
3. **绑定错误可见**：选中 #HealthBar→Inspector 绑定卡把 read 里的 `PlayerHealth.current`
   改成 `currrent`→Save→**Play**：Game 面板底部日志条出现橙黄 warn（原文点名
   `path 'currrent' on '…PlayerHealth'`）→改回→重开 Play→告警消失。

## QA 会话产物索引

- 门禁：`loop/reports/t12t3_qa_{fmt,clippy_ws,clippy_physics,libtests,gate_fast,guards,
  scaffold_e2e,doctests,doctests_bind_rerun,docs,gate_integration,gate_integration_rerun}.log`
  （12 件）；脚本 `loop/qa/t12t3-qa-final-gates.sh`（串行 10 门，无 RUST_BACKTRACE）。
- 核验对象：`loop/t12t3-live/` 21 件（格 1/9/12 console 全文+live-chains 全文）；T1/T2
  证据指针 12 件开卷；`crates/jackdaw_scaffold/src/lib.rs`（占位族三处）/模板/teaches 针/
  book 44 文件链接扫描/暖工程与两 fixture 工程盘上/staged 导出实物；git diff/`-S` 时间线。
- 进程收尾：QA 复查无 jackdaw/t12t1-game/t12t3 残留进程（仅门链自身 rustc，已随门链退出）；
  门链与编辑器未同窗；暖工程 hud.bsn 保持种子 SHA 1007b0d3。
