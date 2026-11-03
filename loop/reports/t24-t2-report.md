# T24 任务 2 报告：真机矩阵轮（13 格全通 + 红绿对照闭合）

> 分支 `loop/t24-debug` @ b9935bbd（T1 建设轮 a5f9eb6f + QA PASS closeout 之上，本任务
> 零产品代码改动——纯真机验收轮，改动面=脚本+证据+报告）。方案
> `loop/plans/t24-debug-feedback.md` §二矩阵+§三腿清单+§四-T2；T1 报告七条注意与
> QA 交接附注两条（cursor 窗口收尾、ui_click 命中按钮节点）全部执行。
> 平台 macOS arm64（26.6.2，M1 Pro）；编辑器 BRP 15703、游戏 BRP 15702；direct run
> 为主、B4 的 PIE 编辑器面为辅助（A10 指针转发全程未触碰）。RUST_BACKTRACE 全程
> 未设；磁盘门前检查 44Gi（>15Gi 门槛）；真机窗与 cargo 构建窗分离（direct-run 的
> cargo 后备构建在编辑器清盘后的自有窗执行）。
> 脚本 `loop/qa/t24-live.sh`（相段化：prep|build|assets|bindings|runtime|all，可复
> 跑，结构照 t23-live.sh 先例）；证据目录 `loop/t24-live/`（归档前缀 t24t2_*，报告
> 目录四件）；fixture `/Users/zhanglinbo/workspace/loop-mac/t24-debug/t24-live`。

## 裁决：**13 格全 PASS**（39 条腿逐格全通，无降级格、无空格）

| 格 | 链 | 内容 | 腿（全 PASS） | 绿侧证据 |
|---|---|---|---|---|
| C1 | 编译 | 改坏模板一行→Play→失败态三嘴 | C1_FOOTER_FAILED / C1_PIE_STATUS_FAILED / C1_ERROR_MOUTH_LOG | walk-c1.json「Build failed - 」；`jackdaw/status` pie=`failed`；editor log ERROR「PIE: game build of t24-live failed … error[E0308] (src/lib.rs:2077:18)」 |
| C2 | 编译 | Build panel 自动聚焦+全文日志 | C2_PANEL_ARROWS / C2_PANEL_FAILED_FACE / C2_PANEL_AUTOFOCUSED | visible_only 走查含「--> src/lib.rs:2077:18」×N+「Build failed - 」；箭头行在可见走查=Build tab 即活动 tab（自动聚焦的自身面） |
| C3 | 编译 | 首错行结构化+行级定位 | C3_SUMMARY_PINNED / C3_ROWS_WITH_OPEN / C3_OPEN_CLICK_LANDED / C3_LANDING_STATUS_TEXT / C3_CURSOR_LAUNCHED / C3_CURSOR_CLEANED | 走查含「4 errors · first: src/lib.rs:2077:18」汇总+行「--> …」+「Open」钮；`ui_click`(按行文本定位父按钮实体)→clicked:true；落点=状态栏「opened cursor at src/lib.rs:2077:18」+Cursor 进程拉起（探针表 cursor `--goto` 命中）；腿后 `pkill Cursor` 收尾（防窗口堆积，QA 附注执行） |
| C4 | 编译 | 纯 warning 不翻 Failed 但可见 | C4_STATE_NOT_FAILED / C4_WARNING_IN_PANEL | walk-c4.json「Project built」在、「Build failed」零出现；「warning: unused variable」+警告箭头「--> src/lib.rs:2077:9」在面板日志 |
| A1 | 资产 | 外部 mv 引用文件→载入→audit 嘴 | A1_WARN_ON_LOAD / A1_AUDIT_FOUR_TUPLE / A1_OPERATOR_MOUTH | warn_on_load「scene 't24a.bsn': 1 references name files…」；`jackdaw/audit` finding 四元组逐字段（document/entity/component=MaterialOverrides/field=materials，kind=Missing，reference=materials/t24mat.bsn）；asset.audit operator 嘴「1 broken references in 1 documents (1 Missing)」 |
| A2 | 资产 | Missing References 面板行呈现 | A2_BOARD_ROWS / A2_ROW_TEXT_MATCHES / A2_ROW_ACTIONS | 「Scene Problems」板+「Broken references」节+行文本=finding.line()（动态取自远端 findings）+Rebind/Locate/Show/Copy 四钮；三色分级经远端 kind=Missing 断言（A14 口径：ui_tree 不读色） |
| A3 | 资产 | Locate 跳转落点 | A3_LOCATE_SELECTS / A3_TAB_FORWARD | 点击前 `jackdaw/selection.set clear`（去陈旧选中，判增量）→ui_click Locate 按钮实体→`jackdaw/status` selection[0].name=`AuditEntity`+scene=t24a.bsn |
| A4 | 资产 | 加载失败域第三节行恰 1+再坏再说 | A4_FAILURE_ROW_ONE_MOUTH / A4_FAILURE_ROW_ONE / A4_LOCK_QUIET / A4_NEW_KEY_SPEAKS / A4_NEW_KEY_ROW_LANDED | 破 GLB→重载→「Asset load failures」节恰 1（board 汇总行「1 load failure」）；同 key 重载 warn 增量 0（一次锁）；再坏（新 mtime）增量 1+汇总「2 load failures」 |
| B1 | 绑定 | 未知组件载入 remedy 一行 | B1_REMEDY_ONCE / B1_RELOAD_QUIET | 「1 type in this scene is in neither … (some_game::GhostComponent). Rebuild the project if the type is new to it…」；同文档重载增量 0（unchanged-remedy 去重） |
| B2 | 绑定 | unknown field 结构化行 | B2_STRUCTURED_ROW / B2_PANEL_ROW_GREEN | warn 形「unknown field 'nonexistent_field' on '…Transform' on entity #RedField; the scene-problems list carries the row」；板「Binding problems」节+行「RedField · …Transform.nonexistent_field (unknown field)」 |
| B3 | 绑定 | 双节呈现 | B3_BOTH_SECTIONS | 同板「Broken references」+「Binding problems」并存：t24b3 行（引用，audit scoped=1）与 DualEntity 绑定行互不吞 |
| B4 | 绑定 | 运行时绑定错进面板 | B4_STRIP_FOUR_FACE / B4_EXPAND_FULL_LIST / B4_DIRECT_LOG_FACE | PIE：游戏 BRP `jackdaw/apply_bsn` 注 6 条坏绑定→Game 条折叠面=最新 4 行（旧 2 行证被折叠）→点击条体→展开面全 6 行可达；direct run：独立游戏（二进制置于 assets/ 旁）BRP apply_bsn→游戏自身日志「unknown field 'nonexistent_field_direct' … on entity #B4Entity」 |
| B5 | 绑定 | A8 红腿翻转 | B5_GUIDED_WARN / B5_REMEDY_HONEST / B5_PANEL_ROW / B5_COMPONENT_UNAPPLIED | warn「that spelling is not registered — the project registers 'jackdaw_animation_runtime::graph::AnimationGraphRef'. A crate-root re-export is not a registered spelling; write the definition module path」；误导单因 rebuild 行 0 次、双因诚实 remedy 在；板行「RedEntity · jackdaw_animation_runtime::AnimationGraphRef (unknown type)」；BRP 组件缺席（定义路径 0 持有 vs Transform 17 持有）——处置语义=不归一化装载，明说 |

格与判据的对应：每格四步「触发→面板呈现→定位动作→落点断言」全走，断言锚全部结构化
（`jackdaw/audit`/`jackdaw/status` selection+pie/`ui_tree` 文本/游戏 BRP），零像素依赖；
A7 未前置（面板判据全走文本锚+结构化远端锚，ui_click 全部经 walk 解析的按钮实体）；
A9 高发窗腿带 budget/jackdaw/wait 重试窗；A14 未前置（三色经远端 kind）。

## 一、红绿对照（三红证全部翻绿，t24t2_* 归档）

| 红证（T1 修前归档） | 绿侧（本轮） | 归档 |
|---|---|---|
| `t24t1_dfr1_red.log`（W2：20 条箭头在板、零动作标签、日志独骑） | 结构化行带（汇总钉首错+每位置一行+Open 钮）、点击→cursor `--goto` 带行打开、状态栏回报落点 | `t24t2_dfr1_green.log` |
| `t24t1_dfr2_red.log`（A8：裸 warn+误导 rebuild remedy+零行+组件缺席） | 指引 warn（报注册定义拼写）+双因诚实 remedy（误导行 0 次）+板行+组件仍不落（明说） | `t24t2_dfr2_green.log` |
| `t24t1_dfr3_red.log`（W1：unknown field 日志独嘴、面板盲） | 结构化 warn（带实体名+板指引）+Binding problems 行含实体/组件/字段 | `t24t2_dfr3_green.log` |

## 二、warn census（四终窗全词表，逐条归因——全文 `t24t2_warn_census.txt`）

- **build 窗 3 命中**：C1 设计错误嘴 ×1；C4 设计 warning 面 ×2（PIE 日志通道转发）。零意外。
- **assets 窗 9 命中**：A1 warn_on_load ×1（设计）；material_overrides stale-key ×1
  （fixture 固有：A1 场景的 MaterialOverrides 落在无网格实体上——T23 MO1 语义正确
  触发）；bevy_asset ERROR ×5（破 GLB 每次载入尝试的引擎自有面：3 次 scene.open+
  2 次 watcher 重载）+ asset_failures WARN ×2（A4 设计：破+再坏，一次锁每 key 一句）。
  零意外。
- **bindings 窗 8 命中**：B1 裸 warn+remedy ×2（设计）；B2 结构化 warn ×1（设计）；
  B3 unknown field+warn_on_load（b3 fixture 有意携带破引用）+material_overrides
  ×1（fixture 固有）；B5 指引 warn+诚实 remedy ×2（设计，误导行 0 次）。零意外。
- **runtime 窗 2 命中**：B4 direct-run 设计 warn ×1（游戏自身日志）；**意外 2 条记档**
  （见 DF-W5/DF-W6）。PIE 半场六条游戏侧 warn 走 StateEvent::Log 进 Game 面板
  （面=walk-b4-folded/expanded.json，不落编辑器日志）。
- **总计 22 编辑器窗命中+1 游戏日志命中，全部归因；零未归因 warn。**

## 三、DF 候选（live finds，只记不修，候主控裁定）

- **DF-W1（加载域嘴面）**：`scene.open reload:true` 对**已开 tab** 走
  `reopen_open_tab→reread_tab_from_disk`，该路**不调 warn_on_load**——tab 开着时引
  用坏了、重载三次都不出载入摘要 warn（assets 轮三次亲证；fresh-open 路径才走）。修
  向：reread 路径补同一句摘要嘴。
- **DF-W2（游戏侧嘴面）**：独立游戏经 flow 载入含 unknown field 的场景文档**零
  warn、静默丢字段**（同一文档编辑器侧有结构化 warn）——游戏侧运行时装载缺 W1 的
  结构化落点（B4 的 t24bad flow 腿两次亲证；world 内组件落地、字段丢弃无声）。
- **DF-W3（一次锁 key 粒度）**：(path,mtime) 锁的 mtime 取自报告时刻——外部破写被
  watcher 在写窗中间读到时，同一次逻辑破坏产生两个 key、两行板行（assets 轮 1-3 亲
  证；harness 改原子替换后消失）。另：同文件两次失败（两种引擎错误串）落两行同文件
  行——行身份不含错误串去重。
- **DF-W4（工具面）**：`jackdaw/ui_tree` 走查对同一子树**重复发射**（同实体 id 在多个
  walk root 下重现 x2-x6）——原始文本计数膨胀，脚本侧被迫按唯一文本/汇总行计数。
- **DF-W5（N13 家族，buglist 在档）**：`drain_game_events` "Exclusive system
  panicked"——游戏连接推日志事件时触发（终窗 1 次；弃置的碰撞窗 2 次）。N13 现状
  观察，T1 红窗（Play 失败未连游戏）不可能出现故无基线对照。
- **DF-W6（PIE 收尾面）**：bevy_ecs relationship WARN「ChildOf(...) relates to an
  entity that does not exist」——PIE 会话实体churn后遗留悬空关系（终窗 1 次）。
- **DF-W7（remote 服务面）**：PIE 游戏刚退出、同端口立即绑定的独立游戏失去 remote
  面（15702 绑定失败，无 SO_REUSEADDR），游戏照跑无 BRP——runtime 轮两次亲证，
  harness 以「端口真正拒绝连接后再启动+90s 未应答即重启一次」自守。修向：绑定重试
  或启动期可观测 warn。

## 四、偏差清单（如实）

- **D-a（运行碰撞，harness）**：build 轮 run1-run2 两脚本窗共用 WINDOW 编号文件名
  （互截断编辑器日志），且 run2 的 warm 等待被残留 schema 提前放行、play 骑上 run1
  窗的在途构建（陈旧二进制连上、N13 panic 面世）。**加固**：端口占位守卫（杀死至
  端口真拒绝连接）+`jackdaw/status` pid 与本窗 boot pid 逐一对账+warm 等待改
  `jackdaw/wait idle`（pgrep cargo 被 zcode 助手进程的 argv 误配，弃用）+窗口文件名
  带 `$$`。run3 另发现上轮早退留下的破模板被带进 warm 构建——harness 加 phase 首
  自愈（pristine 回填）。
- **D-b（assets 轮六跑收敛，全 harness 侧）**：①glb_write 漏 POSITION accessor
  min/max（t23 工艺丢失）→GLB 自始无效，"破"是二次死上破——按 t23 补齐；②audit
  document 以索引拼写（基名 `t24a.bsn`）≠脚本假设 `assets/t24a.bsn`；③BSD grep
  `[0-9]*` 空匹配吞数字；④索引滞后——mv 后 4s 载入时 load-time audit 仍见旧索引，
  加 budget 等 audit 嘴先报再开场景；⑤warn_on_load 仅 fresh-open（DF-W1）；⑥破写
  中间态双 key（DF-W3）；⑦board 行计数按唯一文本/汇总行（DF-W4）。**产品侧真发现
  只有 DF-W1/W3，其余皆 harness 工艺。**
- **D-c（B4 形态）**：PIE 编辑器面（条 4 行+展开 100 条）必须 PIE 才存在——PIE 腿
  保留（指针转发未触碰，A10 绕行实质保持；N13 panic 记 DF-W5），direct run 面按方案
  口径以「游戏 BRP apply_bsn+游戏自身日志」交付；runtime 的 flow-scene 直载路径发现
  DF-W2（游戏侧静默）后，触发器改走游戏 BRP。
- **D-d（非阻塞）**：bindings 轮 B3 首跑审计计数含 assets 轮遗留 finding（audit 走
  全项目所有文档）——判据改 scoped（endswith t24b3.bsn）；A3 判据加「点击前清空选中、
  判增量」以排除会话残留选中。

## 五、产物清单

- 脚本 `loop/qa/t24-live.sh`（prep/build/assets/bindings/runtime/all 六相段，可复跑；
  端口占位守卫+pid 对账+`$$` 窗口文件名+phase 自愈+原子破写/原子治愈+warn 相段词表）
- 证据 `loop/t24-live/`：console-*.log（逐相段累积）、editor-*-wN-<pid>.log（终窗四
  件+历轮）、walk-*.json（每格走查）、a1-finding.json/a2/a3-click-response.json/
  b4-click-response.json/b4-apply-response.json、b2/b5-warn-line.txt、a4-warn-line.txt、
  b4-game-direct.log、c3-click-response.json、warn-scan-*.txt、c1/b1/b2/b5 offset 文件
- 报告目录 `loop/reports/`：`t24t2_dfr1_green.log`、`t24t2_dfr2_green.log`、
  `t24t2_dfr3_green.log`、`t24t2_warn_census.txt`、本报告 `t24-t2-report.md`
- 未动：产品源码零改动（`git diff b9935bbd` 仅脚本+证据+报告）；buglist/台账/roadmap/
  book/协议/fork 零触碰；RUST_BACKTRACE 全程未设；A7/A9/A10/A14/A16 未前置

## 六、T3 交接注意

1. **复跑口径**：13 格脚本相段化可复跑；`bash loop/qa/t24-live.sh all` 全链约 25-35
   分钟（warm 构建缓存在时更短）；fixture 复用即可，prep 仅首次需要（重 prep 会重
   mv 材料——A1 的 mv 已由终窗执行，fixture 当前态=材料已 mv、GLB 已治愈、flow 已
   恢复模板）。
2. **C3 的 cursor 面**：点击会真启动 Cursor 窗口（本机探针表首中）——腿后脚本已
   `pkill Cursor` 收尾；T3 复跑若机器无 cursor/zed，自动回落 `open_with_desktop`
   reveal，落点文本锚变「no external editor on PATH; revealed …」。
3. **A4 的判据面**：板行计数走 board 汇总行「N load failures」（行文本同串会合并）；
   破写/治愈务必走脚本内的原子替换——非原子写会复现 DF-W3 的双 key。
4. **A1/A2/A3 顺序依赖**：warn_on_load 只有 fresh-open 走（DF-W1）——T3 复跑保持
   脚本现在的「基线不开 t24a、mv 后首开」结构；audit 计数判据 scoped 到本格文档。
5. **B4 的两半**：PIE 半场依赖编辑器内 Game 面板（条 4 行+展开）；direct 半场依赖
   游戏二进制**位于 assets/ 旁**（runtime 以二进制邻域定位项目）且 15702 真空闲
   （DF-W7 的自守已在脚本）。游戏侧 flow-scene 直载的静默（DF-W2）已记档——复跑
   时 t24bad.bsn 在 assets 仅作留档，不作为断言面。
6. **DF 候选七件**（DF-W1..W7）候主控裁定吸收面；DF-W5/W6 为观察记录非本轮引入。
7. warn 词表按相段配置在脚本 warn_scan 调用行；T3 复跑后直接对照
   `t24t2_warn_census.txt` 的归因结构复核增量。
