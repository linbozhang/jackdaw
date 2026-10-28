# T12-T3 实施报告：验收矩阵 + book 文档 + 全量门

> 任务：`loop/plans/t12-game-ui.md` §二-T3（284-338 行：12 格矩阵 + book 游戏 UI 章 +
> 工具面两预判评估 + 全量门）+ QA t12-t2-qa.md 回流五项（T02/T03 显式腿、常备检查、
> restart 复位口径、channels-summary 重归档、报告勘误——勘误两项主控已在 fb0156bc 修讫）。
> 分支 `loop/t12-game-ui`（自 main 6d158469 fast-forward 续做，T2 已并入）。
> 本轮**产品代码零改动**（改动面=book 四文件 + loop 产物）；矩阵新证据 14 腿全 PASS。
> 真机证据 `loop/t12t3-live/`（4 个 summary + console/editor/build 归档）；脚本
> `loop/qa/t12t3-{gates,editor-chains,live-chains,cell1,cell12,probe-editor,probe2}.sh`；
> 门禁归档 `loop/reports/t12t3_*.log`（12 件）。暖工程 `loop-mac/t12t1-game/t12t1-game`
> 复用；新工程 `loop-mac/t12t3/{t12t3-ui,t12t3-nophys}`（本轮 scaffold，模板产物零手改，
> 仅按 T11-T3 §九-3 惯例加 JackdawRemotePlugin 仪表，见 §五-3）。全程未设 RUST_BACKTRACE。

## 〇、执行摘要

**矩阵 12 格收口为 12 PASS**（无降级格）：格 1/4/9/12 本轮真机新跑，格 2/3/5/6/7/8/10/11
引用 T1/T2 有效证据指针并抽四腿真机复证（§二标注双通道）。**格 9（编辑器再编辑闭环）是
本轮核心新证据**：改标题+改血条填充色→编辑器文档/盘上 SHA/Play 生效/导出 staged/独立启动
五点全链活证——roadmap「通用交付要求」的铁证落地。QA 回流五项全部落账：T02 绑定卡三处
一致（编辑器 ECS+文档+卡片面）与 T03 undo 显式格 PASS；「spawn 链序/单注册」以
STAND_CHAIN/STAND_PAUSE_SINGLE 命名腿入常备检查；restart 拾取复位口径以数字级活证定案
（并证伪 T2 QA「拾取复位未实现」记档，见 §四）；t12t2-channels-summary.txt 已加陈旧轮
标注重归档。全量门全绿（integration **5348/5348 零 failed**、fast 2970/2970、guards
229/229、scaffold_e2e 冷编 143.6s 落袋、doctests 复跑 PASS、docs EXIT=0）；warn 形态扫描
四格式 0 条，在案告警逐条归因为测试对象（§六）。

## 一、验收矩阵 12 格（双通道证据表）

> 本轮新证据：`loop/t12t3-live/t12t3-{editor-chains,live-chains,cell1,cell12}-*`；
> 旧轮指针：`loop/t12t2-live/*`（T2）、`loop/reports/t12t1_*`（T1）。

| # | 场景 | 判 | 证据指针（本轮新跑 = 新；其余 = 引用指针，抽腿复证见注） |
|---|---|---|---|
| 1 | 新工程开箱四屏 | **PASS（新）** | `t12t3-cell1-summary.txt` 双腿：开箱 PIE boot state=`true,false,false`+StartScreen=Inherited/Hud=Hidden；Start 真 picking 点击（700,787）→`false,false,false`+Hud=Inherited+拾取×3+FallingCube+玩家+rig+「100 / 100」——T11 玩家链在场（`t12t3-cell1-console.log`） |
| 2 | **按钮触发真行为** | **PASS** | 旧：`t12t2-pie-summary.txt` C1_START_BUTTON/C3_RESTART_RESET（真 picking 状态断言）。新：`t12t3-live-summary.txt` CELL2_RESTART_RESET（血 100+位 (-2,·,0)=PLAYER_SPAWN+PickupCount 0+拾取重生×3+屏 Hidden，数字级五断言全中）+CELL5（Resume 点击路）。本轮 Start/Resume/Restart 三按钮再次全部真点击走通 |
| 3 | **血条绑数据** | **PASS** | 旧：`t12t2-pie-summary.txt` C2_BAR_*（hazard 真伤 100→70，`Progress.value`=0.699999988079071=70/100 精确+文本同步）；T1 guards 两档数值断言（`t12t1_guards.log`）。新：`t12t3-cell12-console.log` Interact 路 100→85/0.85/「85 / 100」+`t12t3-live-console.log` 拾取途中 hazard 真触 100→85——两伤害源双通道 |
| 4 | HUD 第二数据 | **PASS（新）** | `t12t3-live-summary.txt` CELL4_PICKUPS：真键走位拾取 0→3（过程采样 0/3/3→3），`PickupsText` 随之「Pickups: 3」，**「Level clear!」info 上 Game 面板日志条**（PIE 日志通道的额外活证）；T10 既有拾取链行为不破坏（同 walk 内 level clear 触发）。T1 guards 「Pickups: 3」静态断言（`game_ui.rs:568`）互证 |
| 5 | 暂停双路 | **PASS** | 旧：`t12t2-pie-summary.txt` C3_PAUSE_RESUME（Escape 与 Resume 等价）。新：CELL5_PAUSE_DOORS——Escape 开→暂停屏 Inherited+**按 W 位移为零（frozen=true 数字断言）**→Resume 点击关+屏 Hidden |
| 6 | **绑定错误可见** | **PASS** | 旧：`t12t2-pie-summary.txt` C4_RED/C4_GREEN（运行态 warn 原文+修正消失）+T1 headless 红证（`t12t1_qa_probe_red_health.log`）。新：**作者态卡片面补齐**——T02_BIND_CARD 三处一致（§三）；格 12 日志条 no-modules 形态 warn（unknown type/no context 原文归档）——两面在两种模块形态都可见 |
| 7 | **布局·headless** | **PASS** | T1 guards `one_layout_holds_across_the_four_common_resolutions`（800×600/1280×720/1920×1080/2560×1440 每档同断言）——本轮 `t12t3_guards.log` 229/229 复跑含此件（59.94s） |
| 8 | **布局·真机** | **PASS** | T2 两档流尺寸像素抽验：`t12t2-resolution-summary.txt` RES_TIER_A/RES_TIER_B PASS（1920x151/170 条带形两档，HealthBar 180x10 恒定±1）+窗口截图两件；16:9 四档归格 7（方案 266-268 行口径，通道差异已记档） |
| 9 | 编辑器再编辑闭环 | **PASS（新，核心）** | `t12t3-editor-chains-summary.txt` CELL9_REEDIT+CELL9_EXPORT：改 StartTitle 文本+HealthFill 填充色（摘 ThemeBackgroundColor 令牌+落裸 Srgba 0.85,0.15,0.15）→编辑器文档两处可见→Save SHA 变更（1007b0d3…→2d8c5968…）→盘上 bsn 含两编辑→PIE Play 生效（live title_hits=1+fill Srgba 红主导）→`game.export` staged `assets/hud.bsn` 含两编辑→**staged exe 独立启动 title_hits=1**（`t12t3-cell9-staged-boot.log`）。编辑→保存→重开→Play→导出全环 |
| 10 | 四通道一致 | **PASS** | T2：编辑器（画布/往返零 diff）=PIE（十腿）=direct（`t12t2-parity-DIRECT-console.log` 五断言）=导出 staged（`t12t2-parity-EXPORT-console.log` 数字逐字同）。本轮格 9 导出腿+cell1/12 的 PIE 腿再证；格 9 补上「导出保留」行为级一环 |
| 11 | Stop 铁证回归 | **PASS** | T2：`t12t2-stop-console.log` VERDICT_STOP_PROOF PASS——PIE 绑定求值中→Stop→scene.bsn+hud.bsn SHA256 双恒等。本轮脚本未复跑（零产品改动，SHA 面无新输入）；`t12t3-editor-chains` 的 seed SHA 前后核（编辑会话起讫 1007b0d3 恒等）为旁证 |
| 12 | 无物理形态回归 | **PASS（新）** | `t12t3-cell12-summary.txt` 三腿：CELL12_UI_PRESENT（boot 干净+StartScreen=Inherited+「Pickups: 0」静态+「100 / 100」）；CELL12_INTERACT_DAMAGE（E 键 100→85+Progress 0.85+文本同步——Interact fallback 真行为）；CELL12_NO_AVIAN（RigidBody 查询 0/schema avian 命中 0）。teaches 退场断言=fast 2970/2970 内 scaffold 套件（`t12t3_gate_fast.log`） |

**矩阵结论：12/12 PASS，零环境降级。** 抽腿复证说明：格 2/5（暂停/重开）、格 3（Interact
伤害路）、格 6（作者态面）本轮均以新证据加厚；格 7/8/10/11 为纯引用指针（本轮零产品改动，
其证据面无新输入，豁免复跑符合 QA 移交口径；格 1/9/12 按移交建议本轮真跑）。

## 二、QA t12-t2-qa.md 回流五项落账

1. **T02 绑定卡作者态链（显式腿）——T02_BIND_CARD PASS**。驱动形态：`component.set`（与
   绑定卡同一条 `field_edit_commit` 提交链）对 HealthBar 的 `Bindings` 整组件写入 typo
   （`.current`→`.currrent`）→**三处一致**：①编辑器 ECS（BRP `world.query` 读回
   currrent）②文档（`jackdaw/scene_bsn` currrent）③**绑定卡面**（`selection.set` 选中后
   Inspector 行标签文本含 currrent——badge 的错误文本挂同一行标签 Tooltip，颜色通道非
   BRP 可达，如实记档）。`t12t3-editor-chains-console.log` 全文在档。
2. **T03 undo（显式腿）——T03_UNDO PASS**。同一 typo 编辑→`history.undo`→编辑器 ECS 与
   文档双面 currrent 清零（console「T03 after undo: ecs_typo=0 doc_hits=0」）。
3. **「模板注册唯一性/链序」常备检查——立为命名腿并 PASS**：`STAND_CHAIN`（boot state
   干净=health 链序 ✓；HudRoot=1+FallingCube+拾取×3=主场景在场=spawn 链序 ✓；日志条无
   「in place of '<…>hud.bsn'」缺陷签名行 ✓——注意 runtime 的 override info 行
   「playing X in place of Y」每次 PIE 必打，良性形态（scene.bsn 换 scene.bsn/temp copy）
   须与缺陷形态（original=hud.bsn）区分，检查按后者断言）；`STAND_PAUSE_SINGLE`（一次
   Escape 翻一次 paused，两次回原——双注册缺陷的净零签名被此断言机械捕获）。
4. **restart 拾取复位教学口径——数字级活证定案，并修正 T2 QA 记档**：物理形态 restart =
   血回满+回 PLAYER_SPAWN+**拾取重生×3+PickupCount 清零**（`respawn_pickups_on_restart`
   观察者，模板 physics 占位段既有——T2 QA §六「拾取复位模板未实现」的记档**不准确**，
   本轮 CELL2_RESTART_RESET 以 alive 0→3+count→0 活证其存在）；无物理形态无拾取系统
   （文本保持 authored「Pickups: 0」，其绑定 warn 可见=格 12 副产物）。口径已写入 book
   `game-ui.md`（「One restart semantic worth knowing exactly」段）。
5. **`t12t2-channels-summary.txt` 重归档——完成**：文件头加 STALE-INTERMEDIATE-ROUND
   标注（中间轮 FAIL verdict 的证据价值=缺陷③实锤 boot state 实锤在案，终轮 verdict 指向
   parity/resolution 各自归档），原 verdict 行原样保留防篡改嫌疑。

## 三、格 9 的驱动沉淀（编辑器文档编辑通道，供 QA 复用）

`component.set/component.add/component.remove` operator 的 Entity 参数在 BRP JSON 上**只
接受名字或 Entity bits 整数两种形态**；文档实体以名字解析最稳（`"entity":"HealthBar"`），
且 sole-target 时顺带选中实体（满足 `is_available = has_primary_selection` 门）。要点：

- Int 形态（`entity_with_id`=try_from_bits+get_entity+非 EditorEntity 过滤）在文档实体上
  实测被拒（「no entity in this scene has id N」），两轮探针在案（`t12t3-probe*-console.log`）
  ——**名字形态是文档编辑的可用通道**（静态分析未定案其拒绝根因，实测结论为准，记档）。
- 改色：widget 填充的 ThemeBackgroundColor（令牌）与裸 BackgroundColor 并存时主题每帧覆盖
  后者（feathers theme.rs 的 update_theme 双组件查询）——**先 remove 令牌再 add+set 裸色**
  即确定性 authored 色；Color 值走 reflect JSON 形态
  `{"Srgba":{"red":…,"green":…,"blue":…,"alpha":…}}`（'r,g,b' 串解析未验证）。
- badge/卡片面：`jackdaw/selection.set {"names":[…]}` 选中后 `jackdaw/ui_tree`（建议
  `visible_only:false`）读卡片行标签文本。
- PIE 流点击：Game 面板停靠为底部条带时流=1920x151 条带，模板按钮居中=帧矩心；固定网格
  (787,787) 一带实测命中（frame_center 启发式在本布局量到编辑器 dock 节点，误报记档，
  网格回退为准）。

## 四、工具面两预判评估项（方案 317-318 行，如实评估）

1. **Game 面板流尺寸的程序化驱动——不可达，记档降级通道**。dock_ops 无面板尺寸 operator；
   流尺寸每帧跟随 `game_panel_pixel_size`（live_frame_view.rs:138,172），无 BRP/Operator
   面。本轮按方案 266-268 行的允许降级：固定 `JACKDAW_WINDOW_SIZE`+面板停靠形态
   （`JACKDAW_WINDOW_SIZE=1600x900`→流 1920x151 条带）+ui_tree 量测；16:9 四档精确像素
   断言仍归 headless guards（格 7）。若后续需要 16:9 真机像素档，按 MCP 优先流程立最小票
   （面板尺寸 op），本轮不立项不硬耗。
2. **PIE 转发点击的坐标换算——现成工具组合足够，未立项**。帧矩形可从 `jackdaw/ui_tree`
   node 树量得（t12t2 frame_rect 先例），模板四屏按钮居中=帧矩心，本轮 cell12 以
   「量测中心+小网格回退」命中；无 letterbox 内比例坐标的一步式工具，但组合通道零新代码
   完成验收。若未来需点击偏离中心的控件，最小补面=ui_tree 暴露流内坐标换算或
   `input.pointer` 加 frame-relative 模式（一句话挂账，不阻塞）。

## 五、book 文档与交叉引用

- 新章 `book/src/user-guide/game-ui.md`（SUMMARY 排 Game Input 后）：2D 画布
  （scene.new kind=UI/控件族/预设/参考线/reference_size=画布基准）、四屏范本导览表
  （hud.bsn 结构+GameState 事件流）、五种 Binding 表+via 注册教学（ratio/not/is_zero）
  +BindContext 接线（wire_hud/HudRoot）、分辨率纪律（percent/flex 优先、px 边界、
  reference_size 非缩放因子）、绑定错误两面（badge/Play 日志条，含 30 秒 typo 演示）、
  U5 边角（UI tab 聚焦 Play=画布预览）、旧工程补装两行、30 秒清单。restart 拾取复位口径
  写入「The template's four screens」节（§二-4）。
- 三处交叉引用落地：`game-input.md`（Pause 消费面真行为化：`handle_pause_action` 翻
  `GameState.paused`+暂停屏绑定同一 bool）；`player-controller.md`（HUD 观察对象=该玩家
  实体）；`physics.md`（hazard 行做真活：hazard_damage→PlayerHealth→HUD 同源）。
- **book 构建门自查**：xtask 无 book 构建门（fast/integration 均不含 mdbook；本机无
  mdbook 可执行）——book 面以 mdbook 兼容的纯 markdown+相对链接手核，仓库 doc 门=
  `cargo doc`（已跑，§六）。如实记档：book 构建验证留 QA 侧视环境而定。

## 六、全量门（日志全文复核；归档 `loop/reports/t12t3_*.log`）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **CLEAN**（EXIT=0） | `t12t3_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **CLEAN**（EXIT=0，零 warning/error 行） | `t12t3_clippy_ws.log` |
| Lint 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **CLEAN**（EXIT=0） | `t12t3_clippy_physics.log` |
| 单测 | `cargo test --workspace --lib` | **EXIT=0**（scaffold 87/87 在内） | `t12t3_libtests.log` |
| fast | `cargo xtask fast` | **2970/2970 passed, 0 failed**（=T2 QA 基线，本轮零测试增删） | `t12t3_gate_fast.log` |
| integration | `cargo xtask integration` | **5348/5348 passed, 0 skipped, EXIT=0**（700s；任务书基线「5331 全绿」的 0-failed 要求维持） | `t12t3_gate_integration.log` |
| doctests | `cargo test --workspace --doc --features dylib` | 首轮 jackdaw_bind 1 失败=**环境性**（rustdoctest 子进程丢 DYLD_LIBRARY_PATH，libstd-*.dylib 找不到，T11-T3 同类历史口径）→`cargo test -p jackdaw_bind --doc` 带 toolchain DYLD 复跑 **PASS** | `t12t3_doctests.log` + `t12t3_doctests_bind_rerun.log` |
| docs | `cargo doc --workspace --no-deps` | **EXIT=0**；17 条 warning 全为私有项链接噪音（game_export/pie/preview_context 等，本轮未触碰的 crate，存量形态） | `t12t3_docs.log` |
| guards 回归 | `cargo test -p jackdaw --test guards` | **229/229 passed, EXIT=0**（59.94s，含四档分辨率+typo 红绿等 229 件） | `t12t3_guards.log` |
| scaffold_e2e 冷编 | `cargo test -p jackdaw --test scaffold_e2e` | **1/1 passed**（嵌套冷编 143.60s，模板 revision 键更新后全冷，落袋） | `t12t3_scaffold_e2e.log` |

**warn 形态扫描（纪律执行）**：`cannot apply|cannot read|does not read as|UnresolvedTypes`
扫 `loop/t12t3-live/` 全部归档 **0 条**。在案告警逐条归因（全为测试对象本身）：
`currrent`×2=T02 红腿编辑对象；`unknown type 't12t3_nophys::PickupCount'`×1+`no
context for '…PlayerHealth.current'`×4=格 12 无物理形态的预期绑定失败（拾取文本保持
authored 静态的机制面，与 T1 报告 §六-2 预期一致）；均归档原文可见。

## 七、U 系结案清单（终态）

| 编号 | 一句话 | 终态 | 闭环处 |
|---|---|---|---|
| U1 | 模板零 UI、四屏无载体 | **已闭环** | T1（模板四屏+hud.bsn+教学段）；本轮格 1/9 真机复证 |
| U2 | 绑定错误 Play 形态不可见 | **已闭环** | T2（PIE 日志通道+面板日志条）；本轮补作者态卡片面（T02 腿）与 no-modules 形态 strip 活证 |
| U3 | 血条无活数据源 | **已闭环** | T1（PlayerHealth 组件+hazard/Interact 双伤害源）；本轮双源再证（格 3/12） |
| U4 | 分辨率缩放语义未定 | **已闭环（决策 5-A 纪律）** | T1 guards 四档+T2 两档+本轮 book「Resolution discipline」节定案文档 |
| U5 | UI tab 聚焦 Play 语义边界 | **已闭环（文档化）** | T2 C5 真机+模板导览注记+本轮 book「One editor edge」节 |
| U6 | via 函数零库存 | **已闭环** | T1（模板注册 ratio/is_zero/not+教学）；本轮 book「via」节 |
| U7 | 无字段事件未验证 | **已闭环（探针定案）** | T1 探针可用、定稿单事件+literal（`t12t1_u7_probe.log`） |
| U8 | 多 UI 根画布测量（W2） | **不吸收，维持** | buglist W2 维持（本轮未触碰 buglist，按移交由主控/QA 后续处理）；模板单 UI 根不踩 |

## 八、偏差与记档分级

1. **⚪ 脚本返工轮次（不改产品结论；终轮 console 全 PASS 归档）**：
   - editor-chains 4 轮：Entity 参数 Int 形态被拒→名字形态（§三）；卡片面需
     selection.set+visible_only:false；颜色走 reflect JSON；一处 python argv/stdin 笔误。
     中间轮 console 被终轮覆盖（脚本按轮清档），过程要点已在 §二/§三记档。
   - live-chains 4 轮：boot 断言串字段序写反（state 输出 menu,paused,game_over）；暂停腿
     挪到 Start 后——**Escape 的 menu 门控是模板教学语义（菜单上不响应暂停），非缺陷，
     首轮 FAIL 即此**；restart 腿把函数名当变量取（`${state##*,}`）；goto_x 加 z 修正
     （相机相对行走漂移）；行走健康 guard 过严→hazard 途中接触重标为 damage 通道活证；
     c2r 授 pass 笔误。
   - cell1 3 轮 / cell12 4 轮（§八-3/§八-4）。
2. **⚪ 新工程仪表（格 1/12 前置）**：scaffold 产物不含 JackdawRemotePlugin（模板本体
   如此，非缺陷——直跑/导出不需要 BRP；PIE 的流/控制走 IPC）→按 T11-T3 §九-3 暖工程
   惯例给两个 fixture 工程加 `jackdaw_remote` 依赖+plugin 行（`jd new` 产物仅此一处手改，
   模板/仓库零改动）。同系：jd 二进制先于 T2 提交（含陈旧 scaffold）→脚手架前重建；
   门链编译后 jd 的 libstd rpath 失效一次→重建（Mac dylib 环境，T11 §八-6 同族）。
3. **⚪ cell12 的 capture 静默拒绝**：`pie.play_input_toggle` 带
   `focused_with_fresh_stream` 可用性门，流未就绪时拒绝且不记 OPERATOR 行（设计如此；
   首轮 25 次点击全部未转发即此因）→脚本改为「探测面板头文字→toggle→复验」重试环。
   建议后续小票：toggle 拒绝时给 OperatorWarnings 一条（可并入 §四-1 的票）。
4. **⚪ PIE 条带流点击几何**：流=1920x151 条带，按钮=帧矩心；frame_center 启发式量到
   编辑器 dock 节点误报一次（fallback 固定网格命中）——启发式过滤条件记档待改，不影响
   结论（§三）。
5. **⚪ doctests/docs 存量形态**：§六表内（bind DYLD 环境性复跑 PASS；docs 17 条存量
   私有链接 warning）。
6. **⚪ Brush 断言不适配 T12 模板**：T12 舞台为网格实体（无 brush），T11 时代的 Brush
   计数断言在 cell1 首轮误用→换 Pickup/FallingCube 面（`t12t3-cell1-console.log`）。
7. **测试账本**：本轮**零新增产品测试**（fast 2970、guards 229 与 T2 收官持平）；
   沉淀 bash 脚本 7 件（gates/editor-chains/live-chains/cell1/cell12/probe×2）。

## 九、给 QA 的注意事项

1. **文档编辑通道**：`component.set` 的 Entity 参数用**名字**（"HealthBar"）；Int bits
   形态对文档实体实测被拒（§三，探针在案）。整组件 Bindings 值直接回填 world.query 的
   JSON 形态即可。
2. **capture 门**：PIE 输入转发 toggle 在流未就绪时**静默拒绝**——验证「Shift+Esc to
   release」面板头文字再点击（cell12 脚本 `capture_on` 可直接复用）。
3. **条带流点击**：Game 面板底停靠时按钮=帧矩心，固定网格 (787,787) 一带可靠；
   `frame_center` 启发式（node 面积最大者）会量到 dock 节点，用前先核对 rect 数值。
4. **状态串字段序**：游戏 BRP `GameState` 的文本序为 `menu,paused,game_over`（parity
   脚本 JSON 键序是 game_over,menu,paused——两脚本族口径不同，断言勿混）。
5. **Escape 的 menu 门控**：菜单未关时 Escape 不暂停是模板语义；暂停类断言须在 Start 之后。
6. **no-modules 绑定告警形态**：`unknown type`（PickupCount 未注册）而非物理形态的
   `context entity lacks`——两形态都是 U2 通道的合法样本，归因时按模块形态区分。
7. **dylib 环境**：门链编译与编辑器/二进制运行勿同窗（本轮 jd 一次 rpath 失效+编辑器一次
   Abort trap 6，均为 target 目录被并行编译扰动；T11 §八-6 同族）。复跑门禁顺序建议：
   门链→（结束后）真机腿。
8. 勿设 RUST_BACKTRACE（全程未设）；进程已清零（jackdaw/两 fixture 工程 pkill，暖工程
   hud.bsn 已复原种子 SHA 1007b0d3…）。

**提交**：显式 pathspec（book 四文件：SUMMARY.md/game-input.md/player-controller.md/
physics.md/game-ui.md 新章）；loop/ 产物按惯例不入库（.gitignore 噪音未触碰；
buglist/台账/roadmap 未触碰，按移交由主控合入时写）。
