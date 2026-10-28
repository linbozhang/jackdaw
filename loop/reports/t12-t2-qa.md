# T12-T2 QA 报告：绑定错误可见 + 真机交互链

> 验收对象：`loop/reports/t12-t2-report.md`，提交 62a85731（分支 `loop/t12-game-ui`，自 main
> 7ab807ca 续做；QA 时点工作树仅 loop 归档与 `.zcode/` 噪音，产品面干净）。
> 方案：`loop/plans/t12-game-ui.md` §二-T2（241-280 行）+ §0 架构事实；T1 移交两项出处
> `loop/reports/t12-t1-qa.md` §十/§十一；通道/降级口径先例 `loop/reports/t11-t3-report.md`。
> 门禁归档 `loop/reports/t12t2_qa_*`（7 件）+ QA 脚本 `loop/qa/t12t2-qa-gates.sh`。
> 全部亲跑（Mac，未设 RUST_BACKTRACE），真机证据全文复核三腿（picking 点击/坏绑定红绿/
> 导出 staged parity），其余腿证据文件逐一开卷。

## 裁决：**PASS —— 放行 T12-T3**

§二-T2 验收清单（方案 273-282 行）逐项全绿（亲验复核见 §二）；真机腿抓出的三处 T1 潜伏
模板缺陷**修复前形态逐一溯源确证、修复后形态+永久针逐一落实**（§三）；主控移交两项**程序
裁定成立**（§五）。偏差全部 ⚪ 级（含两项报告勘误，不阻塞，见 §六）。

---

## 一、门禁（QA 亲跑，日志全文复核零 error/FAILED）

| 门 | 命令 | QA 亲跑结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **CLEAN**（EXIT=0） | `t12t2_qa_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **CLEAN**（EXIT=0） | `t12t2_qa_clippy_ws.log` |
| Lint 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **CLEAN**（EXIT=0） | `t12t2_qa_clippy_physics.log` |
| 单测 | `cargo test --workspace --lib` | **全绿 2970**（scaffold **87/87** :2748 亲数） | `t12t2_qa_libtests.log` |
| fast | `cargo xtask fast` | **2970/2970 passed**，EXIT=0 | `t12t2_qa_gate_fast.log` |
| guards（附加） | `cargo test -p jackdaw --test guards` | **229/229**（56.6s；=228+新 typo 红绿 1） | `t12t2_qa_guards.log` |
| runtime 全测（附加） | `cargo test -p jackdaw_runtime --tests` | 全绿 EXIT=0 | `t12t2_qa_runtime_tests.log` |

**测试账本对账（数字级闭合）**：T1 收官 fast 基线 **2963**（`t12t1_qa_gate_fast.log`
亲读）+ 本轮新增产品测试 **7**（runtime pie_log 4 + 编辑器 pie_game_log 2 + game_panel 1，
fast 日志 :2075-2078/:222/:556/:558 逐条可见）= **2970**，分毫不差。guards 228→229（+1
typo 红绿）同为程序声称数。teaches 87/87 在 libtests 内实跑（针增不变数成立）。

**pie 模块编译形态勘正（对程序 ⚪ 记档的反向修正）**：报告称「workspace 门不编译 pie
模块」——实测**不是**：feature unification（编辑器依赖拉满 bevy 特性）使 `pie_log` 模块
在 workspace libtests/clippy --all-targets 下实编实跑（4 测试全在 fast 账本内）。实际覆盖
**强于**报告声称；ad-hoc 单包形态（`-p jackdaw_runtime --features pie,bevy/…`）只是单包
场景的需要（单包无统一特性时 pie.rs 的 winit 面编不过，pre-existing 属实）。

**warn 形态扫描（纪律执行）**：`cannot apply|cannot read|does not read as|UnresolvedTypes`
扫 `loop/t12t2-live/` 全部归档 **0 条**；`currrent` 形仅红腿 console 一处（测试对象本身，
`path … on …` 形，在案归因）。

## 二、方案 §二-T2 验收清单逐项核实

| 验收项 | 核实方式与结果 | 判 |
|---|---|---|
| 真机① 三按钮真 picking 点击链 | `t12t2-pie-console.log` 全文 75 行亲读：C1 sweep 13 次 `input.pointer` 真 click 命中 (700,787)，`GameState.menu` true→false（游戏 BRP 15702 读回），Hud=Inherited/StartScreen=Hidden；Restart 点击→血 100/game_over 清/屏 Hidden；Escape 键事件→paused=true+PauseScreen shown，Resume 点击→false——**双路一致**。状态断言全走 BRP 数字读回，非 log 占位 | ✅ |
| 真机② 血条绑数据 | 真 KeyboardInput 位置反馈转向走到 hazard 列（steered to 1.758,0.399）→穿越真伤 100→70（=2×15）→`Progress.value`=0.699999988079071（=70/100 精确）+`HealthText`="70 / 100" 双通道同帧；血尽→game_over=true+GameOverScreen shown | ✅ |
| 真机③ 绑定错误可见 | C4_RED：typo（`PlayerHealth.currrent`）→ Game 面板日志条 warn **原文归档**（`jackdaw_bind::evaluate: binding 0 on 722v0: path 'currrent' on 't12t1_game::PlayerHealth': Error accessing element with \`.currrent\` …`，两实体 722v0/720v0 各一条=双 hud 实例，与 C5 HudRoot=2 互证）；`t12t2-probe-window.png` 亲视：两条橙黄 warn+白 info 肉眼可辨。C4_GREEN：修正→重开→warn 消失。headless 半边=guards `a_typoed_field_fails_loudly_and_a_fix_lands_quietly`（game_ui.rs:897-977 亲读：台账非空+Progress 保持 authored 1.0→修正 0.87 落位+台账清零） | ✅ |
| 真机④ 分辨率两档 | `t12t2-resolution-console.log`：1920x151 与 1920x170 两档，游戏虚拟 Window 流尺寸=StartScreen(overlay) 计算盒精确充满（±2px）、HealthBar 180x10 恒定（±1）、StartButton 在场；两档窗口截图归档。与 T1 guards 四档数学断言（`one_layout_holds_across_the_four_common_resolutions` game_ui.rs:689-690，800x600/1280x720/1920x1080/2560x1440 亲核在案）互证 | ✅（条带形偏差定性 ⚪，§六） |
| 真机⑤ 四通道 | PIE（十腿）=direct（parity 五断言 PASS，boot state 干净）=导出 staged（同五断言 PASS，数字逐字同：0.6000000238418579/"60 / 100"）。staged 实证：`.jackdaw/dist/release/` 210,790,912 字节 exe+export-manifest.json+assets，`game.export` operator 调用在 channels editor log :36。通道差异按 T11 口径记档（Mac direct 无 OS 级点击注入等价物，picking 由 PIE 腿独证） | ✅ |
| T02/T03 回归 | ⚪ 记档成立：提交仅触 4 个编辑器文件（game_panel/lib 一行模块声明/pie 11 行/pie_game_log 新），`src/inspector/`、undo 面**零改动**（git show --stat 亲核）；Bindings 落盘面经往返腿（=T02 提交链的 disk face）；undo 面由 fast 2970（含 editor undo 测试）机护。**T3 矩阵须补 T02/T03 显式腿**（§七） | ⚪ |
| T06 Stop 铁证预演 | `t12t2-stop-console.log`：PIE 绑定求值中→Stop→scene.bsn+hud.bsn SHA256 双恒等；脚本形态正确（SHA 前后夹真 PIE 会话） | ✅ |
| quick 四门 | §一 | ✅ |

**真机十腿 summary 亲核**：`t12t2-pie-summary.txt` 十腿全 PASS，与 console 逐腿对得上。

## 三、三处 T1 潜伏缺陷修复复核（程序自捕自修——全部溯源确证）

| # | 缺陷 | 修复前形态（溯源） | 修复后（源码现状） | 永久针 | 判 |
|---|---|---|---|---|---|
| 1 | spawn 序竞态（PIE 覆盖可能换掉 hud 根） | 7515fa11/e984ee1f 模板：`(spawn_scene, spawn_hud)` 无链序元组；`apply_pie_scene_override` 换最低实体索引根（runtime lib.rs 先例）——hud 根抢低位即被整体换成 scene.bsn | lib.rs.template:200 `(spawn_scene, spawn_hud).chain()`+注释钉死原因；真机反例归档 `t12t2-probe-window.png`（流帧只有 3D 世界+日志「playing 'scene.bsn' in place of 'hud.bsn'」亲视确证） | teaches :3863 | ✅ |
| 2 | 暂停双注册（**发布形态 Escape 暂停完全失效**） | **e984ee1f 模板亲读实锤**：`handle_pause_action` 同在 :240 Update 元组**与** :247 `.before(move_player)` 边注册——Bevy 同系统两实例每帧各跑一次，Escape 翻两次净零；7515fa11 已并 main（b5e5ee90），故发布形态确带此 bug | 62a85731 模板 :250 仅一处带边注册，元组已摘除；真机 Escape false→true→false（pie console :55-70）+parity 双腿 paused 屏断言 | teaches :3875 | ✅ |
| 3 | 开局 game_over 竞态（0/0 出生血时序） | `update_game_over` ≤0 即 true 且只置不清（模板 :672-699 亲读）先于 `apply_health_from_config` 跑→开局即 game_over；修复前实锤=**`t12t2-channels-console.log`「DIRECT boot state=true,false,true」归档在案**（channels 腿首轮 PARITY_DIRECT_FAIL 的真实根因） | 模板 :243 `(apply_health_from_config, update_game_over).chain()`+注释；修后 direct/PIE/导出 boot state 三处归档全 `false,true,false` 干净 | teaches :3876 | ✅ |

三处均为「guards 移植单注册/headless 时序看不见、只有真机能踩」类——程序建议把「模板注册
唯一性/链序」列为真机常备检查，**QA 赞同并建议写入 T3 矩阵**（§七）。

## 四、产品新代码审查（本任务核心面）

**runtime `crates/jackdaw_runtime/src/pie_log.rs`（新，346 行）**：
- Layer→mpsc→StateEvent::Log 形态属实：`RelayLayer: Layer<Registry>` 拦 info/warn/error
  （`Level` 按冗余度排序，`>INFO` 即 DEBUG/TRACE 留本地——方向亲核正确）；消息=target+
  message+结构化字段尾随（`FieldReader` 双路 record_debug/record_str）。
- **节流语义不会丢唯一性错误（重点核）**：去重键=(level, **精确文案**)——文案含 target+
  实体号+路径，两个不同绑定失败必然不同文案，互不压制；同文案 1s 去重=每秒至多重现一次，
  可见性不丢（warn-per-frame 退化为 1 行/秒是设计本意，doc 明言）；且绑定失败本身是
  warn-once 台账语义，天然单发。**判：合理**。
- **Reliable lane 选择依据成立**：日志即验收面本身（丢一条=错误不可见），不可靠 lane 可能
  恰丢最关键一条；32 条/秒窗口上限使可靠通道负载有界。**判：正确**。
- ⚪ **记档 1（不对称的静默丢弃）**：窗口上限（32 条/秒）溢出的行被静默 `continue`
  （pie_log.rs:175-177），而帧排空溢出（512 条/帧）有明报 warn——>32 条/秒的**独特**错误
  爆发会静默丢部分。绑定 warn-once 语义下实际风险低；建议后续开小票（窗口溢出也补一条
  一次性「throttle engaged」提示）。非阻塞。
- ⚪ **记档 2（transport 未就绪的早行丢弃）**：`forward_pie_logs` 在 `PieTransportRes`
  不在场时已 drain 的行不回队（:199-201）——attach 极早期数行可能丢；`install` 与
  transport 注册同在 `attach_pie`（pie.rs:93），实际窗口极小。记档。
- 产品测试 4 件全真实（层级过滤/结构化字段/去重+上限+窗口滚动/溢出保新+明报），且全在
  workspace fast 账本内实跑（§一勘正）。

**编辑器 `src/pie_game_log.rs`（新）**：VecDeque 上限 100 pop_front 滚出属实；三档色走
W13 tokens（error→TEXT_ERROR/warn→TEXT_WARNING/其余→TEXT_SECONDARY）属实；测试 2 件真实
（滚出+序/三档色）。

**`src/game_panel.rs` 日志条 + `src/pie.rs` Log 分支**：`drain_game_events` 增
`StateEvent::Log` 分支仅聚焦实例入账（设计即「focused game 的最近日志」，模块 doc 明言；
非聚焦实例行不缓存——切焦点丢历史行，记档不动）；`sync_game_panel_log` 差量写行+终端序
沉底+整条隐藏，测试 1 件真实。
- 🔴→**报告失实（非代码缺陷）**：报告 §〇/§二与提交信息两处称日志条「8 行」，代码实为
  **`LOG_ROWS = 4`**（game_panel.rs:76，children 4 行、测试按 4 行、截图 4 行三方自洽）。
  方案验收只要求「最近 N 条」，无功能缺口——**判 ⚪ 报告勘误项**（随 T3 收尾顺手修，或
  按需把行数改回 8，二选一由主控定）。

**BindFailures 读取面未动（YAGNI 裁定遵守）**：编辑器 src 对 `BindFailures` 零消费
（`src/lib.rs:385` 的 init_resource 系 T2 之前既有，git 亲核）；坏绑定以日志行为准成立。

## 五、主控移交两项复核

### 1. hud.bsn 编辑器往返零 diff —— **程序裁定成立**

- **复验腿亲核**：`t12t2-roundtrip-console.log`＝回写种子后 QA 升权重跑：「hud document
  confirmed open」（加固生效）→SHA256 before==after **字节级零 diff**→VERDICT PASS。
- **规范化判定逐项亲核**（`git diff 7515fa11..62a85731` 模板全文 diff 亲读）：8 行教学头
  →编辑器标准头 1 行；`Bindings([...])` 多行→单行（9 处）；`Progress { value: 1.0 }`→
  字段逐行——纯格式；`#HealthFill` 的 `width: Percent(100.0)` 剥离=**故意行为实证**：
  `src/scene_io/save.rs` `normalize_runtime_derived_values`（:973 起）doc 明文「a progress
  fill's width … back out of the document, so they are not recorded as authored」+代码
  `remove_bsn_field(…, "width")`，且 `progress_fill_follows_value` 每帧从 `Progress.value`
  重写该宽度（authored 值本为死重）；**语义面零漂移**：`bevy_color::srgba::Srgba` 两处
  （α=0.6/0.92）在编辑器保存形态下原样幸存（模板 :116/:162 亲读）。
- **种子回写亲核**：暖工程 `assets/hud.bsn` 与模板占位替换后**字节等同**（diff 亲跑）；
  首轮 diff 反例归档（`t12t2-roundtrip-after.bsn`，标准头形态）在案；首轮「打开未完成即
  保存」踩坑已加固（`jackdaw/scene_bsn` 确认 HudRoot 在前才保存）并如实记档。

### 2. typo warn 真机可见 —— **成立**

红腿 console 原文+截图肉眼双证（§二真机③）；绿腿修正消失；headless guard 永久化；
T1 QA §十-2「同类第四处 bug 不再依赖 QA 探针才能发现」的诉求闭环——本轮真机腿反手抓出
三处新缺陷并当场可见（正是该通道的价值证明）。

## 六、偏差与记档分级（QA 视角）

| 级 | 项 | 处置 |
|---|---|---|
| ⚪ | 报告「日志条 8 行」实为 4 行（§四）；报告头「脚本 7 件/证据 22 件」实际提交 6 脚本/24 证据件（QA 补 gates 脚本后 7/25） | 报告勘误项，不阻塞 |
| ⚪ | `t12t2-channels-console.log` 为中间轮（FAIL 轮：双 bug 实锤+探针表坏）与终轮 parity PASS 混档，`t12t2-channels-summary.txt` 停留在中间轮全 FAIL verdict——单独读会误判；终轮证据在 pie/parity/resolution/stop 各自归档 | 中间轮如实留档有价值（boot state=true,false,true 即缺陷③实锤）；建议 T3 把该 summary 重归档或改名防误读 |
| ⚪ | pie_log 窗口上限溢出静默丢弃（§四记档 1）；transport 未就绪早行丢弃（记档 2）；非聚焦实例日志不缓存 | 记档；前者可开小票 |
| ⚪ | `maybe_windowless` 的 LogPlugin `.set` 覆盖游戏自带 filter/custom_layer 定制（仅 PIE 形态；doc 注释在案 pie_windowless.rs:62-67 亲读） | 接受（程序记档属实） |
| ⚪ | 分辨率条带形（1920x151/170，非 16:9 档）：Game 面板底部停靠→流=面板像素尺寸，方案 266-268 行明文允许「Game 面板尺寸由编辑器布局驱动」；脚本头注记通道；16:9 四档归 T1 guards 实核在案 | 接受（通道差异如实标注，口径正确） |
| ⚪ | 血尽腿 final 轮=hazard 真伤 100→70+组件 bottom-out 补完；脚本有 DAMAGE_CHANNEL 标注但 console 未显式打印 bottom-out 行（可由 6 轮循环 health 恒 70+state 翻转严格推出）；报告 §八已如实声明降级 | 接受（诚实标注成立；标注颗粒度记档） |
| ⚪ | 方案「重开=血/拾取/位置复位数字级」：live 腿断言血+屏；位置复位数字级在 guards :681（PLAYER_SPAWN 精确断言亲核）；**拾取复位模板未实现**（restart 不重置 PickupCount——教学语义选择，非缺陷） | 记档；T3 矩阵钉「restart 复位语义」教学口径 |
| ⚪ | `t12t2-export-game.log` 0 字节空归档 | 归档卫生，不阻塞 |

## 七、给主控的建议

1. **放行 T12-T3**（验收矩阵+文档收尾），T3 带以下入矩阵：
   - T02/T03 显式回归腿（绑定卡提交链/undo——本轮仅记档豁免）；
   - 「模板注册唯一性/链序」入真机常备检查（本轮三连缺陷的方法论沉淀）；
   - warn 形态扫描（四形态+归因）为standing 腿；
   - restart 复位语义（拾取是否随重开清零）教学口径定案；
   - `t12t2-channels-summary.txt` 陈旧 verdict 重归档；报告勘误两项（4 行/计数）顺手修。
2. 用户 30 秒清单（本任务层面）：
   - 拉分支跑模板新工程：四屏在、**Escape 真暂停**（T1 发布形态的双注册失效已修）、
     死后 Restart 血/位置归位；
   - 编辑器 Play 看 Game 面板底部日志条：把 hud.bsn 的 `PlayerHealth.current` 手改为
     `currrent` 再 Play，橙黄 warn 即现形；改回重开即消失——「绑定错误可见」亲测 30 秒；
   - 形态须知：PIE 流=Game 面板条带尺寸（非 16:9）；PIE 形态下游戏自带 LogPlugin 定制被
     默认值+转发层覆盖（仅 Play 影态）。

## 八、QA 足迹

亲跑门禁 7 门（`loop/qa/t12t2-qa-gates.sh`，归档 `t12t2_qa_*.log` 7 件）；亲读源码
pie_log.rs/pie_game_log.rs/game_panel.rs/pie.rs/pie_windowless.rs/模板 lib.rs.template/
guards game_ui.rs/save.rs；亲 diff 模板 T1→T2 全文与暖工程种子；真机证据开卷 13 件
（console/summary/截图/parity/staged 目录/roundtrip/stop）；进程零残留。
