# T24 调试反馈与错误定位 — 实施方案

> 策划产物（2026-11-03，基于本地 main **02b680c0**（T23 收官合入）全量只读调研：编辑器
> `src/asset_failures.rs`/`src/reference_audit.rs`/`src/inspector/missing_list.rs`/
> `src/inspector/file_card.rs`/`src/build_panel.rs`/`src/build_status.rs`/`src/ext_build.rs`/
> `src/extension_build.rs`/`src/scrolling_log.rs`/`src/status_bar.rs`/`src/pie.rs`/
> `src/pie_game_log.rs`/`src/game_panel.rs`/`src/game_export.rs`/`src/project_build.rs`/
> `src/project_window.rs`/`src/editor_log.rs`/`src/remote/server.rs`；
> `crates/jackdaw_project_build/src/{build,binary}.rs`；`crates/jackdaw_bsn/src/{apply,catalog}.rs`；
> `crates/jackdaw_runtime/src/pie_log.rs`；`crates/jackdaw_rustc_wrapper/src/lib.rs`；
> `buglist.md` 全量调试/日志/错误域扫描；`loop/plans/t23-material-override.md`（格式与
> 纪律先例）。**零临时探针**——本方案全部关键结论是静态可复核事实（源码锚在档）；
> 唯一静态不可裁点（外部编辑器跳转协议在本机的可用性）以 T1 首步纯探针定案（决策 3）。
> 需求来源：`loop/plans/roadmap-game-dev.md` 第 41 行（T01-T23 已闭环）。
> **验收原文**（roadmap 第 41 行，逐字核实）：「**调试反馈与错误定位：错误关联资产/实体/
> 组件/代码位置跳转。验收=编译失败/资产缺失/绑定错误可从面板定位。**」
> **任务定性：第九次定性反转，判定约 45/55（建设型略偏重）**——T12-T23 八次反转的
> 读法在此**第九次适用**：调试反馈不是空白域，三条验收链各有半座楼已立——
> **编译失败**：Build panel 底部坞板（自动聚焦+全文日志+状态栏可点击）+三条构建
> 味道（扩展/Play/导出）全部汇入同一 `BuildStatus` 失败闩，`--> file:line:col` 信息
> **已在日志文本里**（rustc rendered 诊断原样过管）——「可从面板定位」的**呈现半边逐词
> 成晶**；**资产缺失**：T18 加载失败双嘴（一次锁）+T23 audit 五元组四元组+Missing
> References 列表（Rebind/Show/Copy/**Locate=开 tab+选实体**）——**资产域的「面板
> 定位」连跳转动作都已建成**；**绑定错误**：嘴有三处（apply unknown field warn /
> UnresolvedTypes remedy / T23 MO1 双嘴+游戏日志条）但**面板与定位双层整体缺席**。
> 真正的建设面收窄为三窄口：**①诊断行结构化**（rendered 文本→`file:line:col` 可操作
> 行，管线零改动——JSON 流已在，只差解析）；**②绑定错误结构化落点+面板行**（对照
> missing_list 行形态）；**③跳转动作到代码位置的最后一米**（唯一真空白，对照 locate
> 先例做文件/行落点）。缺陷候选按 **DF 系**编号（Debug Feedback，避开 buglist
> R/Y/W/A/N/TM 系与 T01-T23 各任务编号系 U/I/F/C/PF/AN/AU/AR/SP/TM/EG/GR/MO），
> 只记不修→主控裁定吸收面。真机口径沿 T23：**macOS（本机）**，bash+curl+jq 驱动
> 编辑器 BRP 15703（`jackdaw/audit`/`jackdaw/status`/`ui_tree` 结构化锚）与游戏 BRP
> 15702；direct run 为主、PIE 腿免（A10/N13 绕行口径）；**勿设 RUST_BACKTRACE**
> （T11-T3 口径）；**A7 家族不前置**（全 operator/BRP 直达，避开对话框提交+字段行
> 定位族；面板断言走 `ui_tree` 文本锚+结构化远端锚双轨）；**A9 不前置**（高发窗口
> 腿带重试窗，服务侧指纹落盘留在 A9 票内）。

---

## 0. 架构事实（核实结论，方案的地基）

**总判断：T24 不是「建错误报告系统」——错误已经被五个嘴说出口，其中两个域有面板、
一个域有跳转。T24 的工作=把三链各自的「面板呈现→定位动作→落点」最后一米补齐：
编译链差「行结构化+行级跳转」（信息在文本里，不可操作）；资产链差「加载失败域的
面板化」（引用域已全通）；绑定链差「结构化落点+面板行」（嘴已响，无人定位）。**
十五条事实：

- **事实一：编译失败的呈现半边已建成，且三条构建味道汇入同一失败闩。**
  共享状态=`BuildStatus { state, outcome, failed_log }`（`src/build_status.rs:22-31`，
  `failed_log`「The whole output of the last build that failed, kept for the Build
  panel」）；`BuildState` 五态 Idle/Building/Ready/Failed/Blocked，Failed 语义
  「the status bar makes it clickable to surface the build log」（:44-46），Blocked
  独立承载「连构建都起不来」的 setup 问题（:48-52）。三条写入路径：①扩展/工程
  构建（`src/extension_build.rs:412`）；②Play 构建（`src/pie.rs:2105-2120`，
  `poll_builds` 失败分支：闩 `BuildState::Failed`+`failed_log`=全量日志+
  `status_bar::notify_error`）；③导出构建（`src/game_export.rs:337-349`，
  `report_export_failure` 同构）。PIE 本地另有 `BuildState::Failed{launch}` 驱动
  `play_status`（enum `src/pie.rs:138-153`、`launch_failed` :241-246、`play_status`
  :289；远端嘴 `jackdaw/status` 的 `"pie"`
  字段，`src/remote/server.rs:518`）。
- **事实二：Build panel 是已建成的底部坞板，失败自动聚焦。**
  `src/build_panel.rs`：`BUILD_WINDOW_ID="jackdaw.build"`（:26），面板文档「It
  focuses itself on the first build after opening a project and **whenever a build
  fails**」（:3-5）；`auto_focus_build_panel`（:288-297）对 `Failed|Blocked` 强制
  聚焦；`sync_build_panel`（:150-200）把 `failed_log` 全文灌进 `ScrollingLog`
  （:181-197「show the whole output it kept」）+状态行着色；状态栏 Failed 态文案
  「Build failed - click for log」可点击（`src/status_bar.rs:449-456`+点击观察器
  :190-193）。Blocked 态 footer **fall through**（:462-465 注释「Sticky, so it must
  not take the footer over permanently」）——setup 问题只靠面板自动聚焦一次承担
  （W7）。
- **事实三：诊断信息以 rendered 文本形态过管，`file:line:col` 已在文本里但不可操作。**
  cargo 以 `--message-format=json` 跑（`crates/jackdaw_project_build/src/binary.rs:
  220-221` 注释：plain json 而非 json-render-diagnostics，为的是 compiler-message
  记录可达）；`parse_build_line`（`crates/jackdaw_project_build/src/build.rs:412-455`）
  对 `compiler-artifact` 数进度、对 `compiler-message` **只取 `message.rendered`**
  （:440-451）拆行进日志——rustc rendered 块天然含 `--> src/lib.rs:12:5` 箭头行，
  **路径/行/列信息原样在日志文本里**；结构化的 `message.spans`（file_path/
  line_start/col_start）**零消费**。失败日志装配=`compile_failure_log`（rustc 诊断
  +cargo stderr，`binary.rs:482-496`）。呈现侧 `BuildProgress`（`src/ext_build.rs:
  20-56`）：`full_log` 无界（Build panel 用）+`recent_log_lines` 20 条尾窗（紧凑面）。
- **事实四：ScrollingLog 是纯文本积，无行级交互。**
  `src/scrolling_log.rs` 全文无 click/jump/observer（仅 content 同步+吸底
  `ScrollPosition`）——Build panel 的「IDE-style scrollback」（ext_build.rs:46 注记）
  目前只有「滚到底」一个交互。这是 W2 的呈现侧落点：行结构化后行级动作才有挂载点。
- **事实五：资产缺失域=两套机制、四个嘴，其中引用域连跳转都已建成（T18+审计族）。**
  ①**加载失败域**（T18）：`src/asset_failures.rs` 监听 `UntypedAssetLoadFailedEvent`，
  按 **(path, mtime) 一次锁**每失效路径恰一 warn+`status_bar::notify_warn` 双嘴
  （:79-89），引擎语义「失败重载不摘旧值」故嘴要说「showing the previous content」
  （模块 doc :1-14）。**无面板形态**：状态栏 Notice 单行即焚，无清单可回看（W3）。
  ②**引用域**（audit 族）：`src/reference_audit.rs` `AuditFinding { document,
  entity_name, component, field, reference, kind }` 五元组（:48-56），kind 三态
  Missing/Ambiguous/MachinePath（:25-33）；四嘴：`asset.audit` operator（:445）、
  `jackdaw/audit` 远端方法（`src/remote/server.rs:154`）、载入一行 summary
  （`warn_on_load` :486-509→`warn_caller`）、Missing References 列表（:662 operator
  `asset.missing_list` 驱动，`src/inspector/missing_list.rs`）。
- **事实六：Missing References 列表=本仓库已有的「错误面板+定位跳转」完整先例。**
  `src/inspector/missing_list.rs`：每行渲染 `finding.line()`（:170，人读一行含
  document/entity/component/field/reference）+按 kind 三色（`color_of` :206-212）；
  行按钮四动作（:184-190+分派 :263-265）：**Rebind**（过 picker 改写 open tab 文档、
  作为一次编辑、脏旗照走 :366-384；无 tab 拒答提示先开 :304-313）、**Show**（开
  文件管理器到文档所在目录 :641-654）、**Copy**（引用进剪贴板 :657-662）、
  **Locate**（**开 tab+按 Name 查询选中实体** `select_only` :667-697+）——这就是
  「错误关联实体→面板→跳转落点」的全链既有实现。入口：资产文件卡按钮
  「Missing References…」（`src/inspector/file_card.rs:378`）+operator；命令面板无项
  （`src/command_palette.rs` 零命中）。汇总空态走状态栏「no broken references」
  （:66-71）。**命名反直觉**：Show=开文件夹、Locate=选实体（W8）。
- **事实七：绑定错误的嘴有三处，全部不是面板行。**
  ①**unknown field**：`crates/jackdaw_bsn/src/apply.rs:542`
  `log::warn!("unknown field '{}' on '{}'", field.name, data.type_path)`——只有
  字段名+类型路径，**无实体名、无文档位置**，只进 log 不进任何面板（W1 主体）。
  ②**未知类型**：`UnresolvedTypes` 收集+每载入恰一 remedy 行
  （`apply.rs:141-166` `take_remedy` 去重「an unchanged remedy stays quiet across
  reloads」+`catalog.rs:221-229` `report_unresolved_types` 载入后一句 warn，含类型
  清单与 rebuild 指引）——**load 级汇总，非逐实体行**。③**运行时嘴**（T12）：
  游戏侧 tracing 层全量捕获→节流（1s 去重窗+32 条/秒+512 条/帧排空，
  `crates/jackdaw_runtime/src/pie_log.rs:27-41`）→`StateEvent::Log` 可靠通道→编辑器
  侧 `pie.rs:2646-2654` 进 `PieGameLog`（100 条环形，`src/pie_game_log.rs:15`）→
  Game 面板条**只渲染最新 4 行**（`LOG_ROWS=4`，`src/game_panel.rs:76`）三级着色
  （W13 三层方案，`pie_game_log.rs:31-40`）——**4 行不可交互、96 条不可见**（W4）。
  文档自证覆盖面：「a binding that names a missing field is the classic」（pie_log.rs
  模块 doc :3-5）——绑定错误正是这条通道的经典负载。
- **事实八：T23 MO1 已给「失效引用」域加了第四个嘴（双嘴+一次锁先例）。**
  `src/material_overrides.rs:233-234`：失效材质覆盖按失败身份一次锁，`warn!` +
  `status_bar::notify_warn` 双嘴，仅编辑器进程（:45 注记）。与 asset_failures 同构
  ——**「嘴+一次锁」已是仓库惯用形**，面板化是缺口不是机制（W3/W5 的落点参照）。
- **事实九：实体跳转的既有先例=locate；组件跳转是隐含的；代码位置跳转是真零。**
  locate（事实六）=「开 tab+选实体」全链；组件级=audit 行文本里有 component/field
  字样+选中实体后 Inspector 自动呈现（隐含，无直接「展开该组件」动作）；**代码
  位置**：无类型→源文件映射（`.jackdaw/schema.json` 只载类型路径不载文件）、无
  open-at-line 动作；唯一桌面出口=`open_with_desktop`（`src/project_window.rs:
  2156-2166`，open/explorer/xdg-open 开文件或目录）——能开文件、不能带行。「代码
  位置跳转」的全部基础设施=事实三的 rendered 文本里的 `--> file:line:col`。
- **事实十：编辑器自己的错误面=log 文件+状态栏，无统一 Problems 面。**
  `src/editor_log.rs`（无控制台构建写 `editor.log`，前轮改名 `editor.previous.log`
  保崩溃现场）；状态栏 Notice 单行即焚（`src/status_bar.rs:69-89`）；Build panel
  （构建域）/Missing References（引用域）/Game 面板条（运行时域）三面板各管一段，
  **互不聚合**（W5）。五嘴清单：加载失败（T18）/引用审计（T23）/覆盖失效（MO1）/
  构建失败（事实一）/游戏运行时（T12）。
- **事实十一：audit/绑定两域的「可发现性」已有 BRP/远端结构化嘴，真机断言有锚。**
  `jackdaw/audit` 返回 findings 结构化清单（事实五）；`asset.missing_list` operator
  可远端驱动列表；`jackdaw/status` 载 `pie` 构建态。T24 真机腿的断言锚=这三者+
  `ui_tree` 文本锚（面板行文本 `finding.line()` 可 walk）——**A14（ui_tree 不暴露
  Display/hover）不前置**：面板行判据用文本锚即可，无需 hover。
- **事实十二：绑定错误静默半边已在 buglist（A8），T24 是它的天然吸收轮。**
  A8（`buglist.md:499`）：BSN apply 对 crate 根 re-export 路径**静默丢弃**（无
  warn、组件不落）+`unresolved_remedy` 文案（apply.rs:168-175「rebuild the
  project」）对真实成因误导。修复方向「未知路径丢弃补 warn（对照 AN1 运行态 warn
  形态）+remedy 文案改写」——与本轮 W1 结构化落点同域同因，**顺手票候选**（决策 5）。
- **事实十三：PIE 日志通道的既有边界本轮不动。**
  节流三层（事实七）的溢出语义不对称（窗口满静默丢 vs 帧排空明报）=**A5**
  （`buglist.md:451`，票注「下轮触碰 pie_log 时顺手」）——T24 正是触碰 pie_log 域的
  轮（W4 若采纳展开面则触碰消费侧；A5 在生产侧），**A5 顺手与否=决策 7 附带项**。
  PIE 面板指针转发（A10）与 drain panic（N13）维持绕行口径不触碰。
- **事实十四：扩展构建管线的另一出口 `jd`/CLI 与 schema 提取不在验收面。**
  `jd build`/`jackdaw build` 走同一 `parse_build_line`（build.rs:457-475 shim 共用），
  但 CLI 无面板语义；schema 提取失败「not fatal, keeps prior schema」
  （binary.rs:446-456 warn 进日志）——T24 不动 CLI 面。
- **事实十五：绑定错误还有一个域=游戏参数绑定（T08），现状走既有嘴。**
  参数声明/绑定错误沿 operator 拒+warn_caller 形态（`material_overrides.rs:459-498`
  同款 `warn_caller` 先例），真机腿经 BRP 可断言；T24 不为参数域单开面板，矩阵不设
  专格（若 T2 live 发现形态缺口归 DF 系记档）。

---

## 验收句逐词定性（矩阵化的前提）

验收句拆五词，每词标 **已建成 / 半成晶 / 缺口**（锚见 §0）：

| 词 | 判定 | 依据 |
|---|---|---|
| 「错误关联资产/实体/组件」（句首描述） | **已建成** | audit 五元组 document/entity/component/field/reference（事实五）+行渲染 `finding.line()`（事实六） |
| 「代码位置跳转」（句首描述） | **缺口** | rendered 文本里有 `--> file:line:col` 但零解析零动作；无类型→源文件映射；open_with_desktop 不能带行（事实九） |
| 「编译失败可从面板定位」 | **已建成（呈现半边）+缺口（行级定位半边）** | Build panel 自动聚焦+全文日志+状态栏可点击+三味同闩（事实一/二）；但行不可操作、无首错定位、无「N errors」汇总（事实三/四）→判**半成晶**偏成 |
| 「资产缺失可从面板定位」 | **半成晶** | 引用域全通（面板+Locate 跳转，事实五/六）；加载失败域只有嘴（T18 双嘴即焚，事实五①）→两域合判**半成晶** |
| 「绑定错误可从面板定位」 | **缺口为主** | 嘴三处已响（事实七）但面板行/实体定位/展开面全缺（事实十）→**缺口**，唯嘴层成晶 |

**反转判定**：五词中 1 全成、2 半成、2 缺口——**约 45/55，建设型略偏重**（对照：
T23=30/70、T22=70/30、T18≈35/65）。建设面集中在三窄口（诊断行结构化 / 绑定错误
结构化落点+面板行 / 代码位置最后一米），全部有同仓库先例可对照（missing_list 行
形态、MO1 嘴+一次锁形、parse_build_line 挂点），无一处需要新管线。

---

## 一、缺陷候选（DF 系，只记不修→主控裁定吸收面）

- **W1 🔴 绑定错误零结构化落点。** unknown field 只 `log::warn!`（apply.rs:542，
  仅字段名+类型路径，无实体名/文档位置）；未知类型是 load 级一行汇总
  （apply.rs:141-166+catalog.rs:221-229）非逐实体行；静默半边=A8（re-export 路径
  零 warn）。三处嘴无一进面板、无一可定位——「绑定错误可从面板定位」的主建设面。
- **W2 🔴 编译诊断只以渲染文本流过，行不可操作。** `parse_build_line` 只取
  `message.rendered`（build.rs:440-451），`message.spans` 零消费；ScrollingLog 无
  行级交互（事实四）；失败定位=「滚到底自己找」，无首错行、无错误计数、无点击。
  `--> file:line:col` 已在文本里——结构化是解析问题不是管线问题。
- **W3 🟡 加载失败域无面板形态。** asset_failures 双嘴即焚（asset_failures.rs:79-89），
  无清单回看、无 locate/show 动作（对照 missing_list 先例齐全）；(path,mtime) 一次锁
  （:17-40）本身就是面板化去重的现成底座。
- **W4 🟡 PIE 游戏日志 100 条缓冲只露 4 行且不可交互。** `LOG_ROWS=4`
  （game_panel.rs:76）vs `PIE_GAME_LOG_CAP=100`（pie_game_log.rs:15）；行无
  click/复制/过滤/展开；GameLogEntry 载荷只有 level+message（无实体/组件结构）。
- **W5 🟡 五嘴不聚合，跨域错误无统一入口。** 加载失败/引用审计/覆盖失效/构建失败/
  运行时日志各自为嘴或为面板（事实十），状态栏 Notice 单行即焚；用户没有
  「现在项目有什么错」的一站式答案。
- **W6 🟡 代码位置跳转零设施。** 事实九：无映射、无动作、open_with_desktop 不带行
  ——句首「代码位置跳转」的唯一真空白（建设量=决策 3 的落点选择）。
- **W7 ⚪ Blocked（setup 问题）态 footer 无承载。** `BuildState::Blocked` 渲染
  fall through（status_bar.rs:462-465），只靠 Build panel 自动聚焦一次；错过聚焦后
  用户无处看到「为什么连构建都起不来」（sticky 语义在面板不在 footer）。
- **W8 ⚪ missing list 按钮命名与动作反直觉。** Show=开文件管理器、Locate=开 tab
  选实体（missing_list.rs:263-265）——对人易误点，对驱动脚本（A7 族）易错配；
  文件头 doc 顺序（"open the document's folder, copy, or bring the document
  forward"）与按钮名不一一对应。
- **W9 ⚪ Play 构建失败态只在远端嘴。** pie 本地 `Failed{launch}` 只被
  `jackdaw/status` `"pie"` 字段消费（remote/server.rs:518），Play 按钮本体无失败态
  区分；用户面靠 footer Failed+notify_error 兜底（事实一）——影响小，记档防漏。

### buglist 重叠表（调试/日志/错误域全量扫描）

| 票 | 关系 | 本轮处置建议 |
|---|---|---|
| A8（:499 BSN re-export 静默丢+remedy 误导） | **W1 的静默半边**，同域同因 | 决策 5：候选本轮顺手吸收（T23 MO9 先例） |
| A5（:451 pie_log 窗口溢出静默丢） | T24 触碰 pie_log 域（W4 若采纳） | 决策 7 附带：顺手候选，小票一行级 |
| A9（:503 BRP 空响应+方法瞬失） | 真机腿高发窗口会撞；票内首步「服务侧指纹落盘」属调试反馈域但修复面在 remote 服务侧 | **不前置**（纪律）；腿带重试窗；指纹落盘留票内（决策 9） |
| A14（:482 ui_tree 不暴露 Display/hover） | 调试可见性工具面洞，但本轮面板判据用文本锚即可 | **不前置**；维持票 |
| A16（:490 GameFlow State<T> BRP 死） | flow 通道调试可见性，模板一行 | 不触碰（守模板零改动裁定先例） |
| A7（:459 驱动脚本工具债） | 真机驱动同族债 | **不前置**；腿设计全 operator/BRP 直达自守 |
| A10/N13 | PIE 通道稳定性 | 绕行口径（direct run 为主）维持 |
| A13（:478 imported 孤儿） | 弱相关（texture_import 域） | 不触碰 |
| A12（渲染面 Basis 冻结） | 弱相关 | 不触碰 |
| A18（:551 book 微修两处） | ②rebind 括注与本轮 rebind/audit 域相接 | T3 book 触碰时顺手落（T20-T3 Errata 先例） |

---

## 二、验收矩阵设计

### 铁证①：三链「触发错误→面板呈现→定位动作→落点断言」功能主干

每链四步全通即验收句成立；断言锚全部结构化（`jackdaw/audit`/`jackdaw/status`/
`ui_tree` 文本/`selection` 远端读），不依赖像素。

### 铁证②：红态先归档（红绿对）

- **红腿 DF-R1（W2）**：T1 修前构建跑「改坏模板一行→Play 失败」，归档：Build panel
  日志全文在档但**行级动作为零**（ui_tree walk 面板行无按钮成分/`jackdaw/audit`
  型结构化行无编译类 finding）——对照 T23 QD1 修前构建纪律。
- **红腿 DF-R2（W1/A8）**：修前手写 crate 根 re-export 组件路径的场景→载入→
  **零 warn、组件不落**（console 全读+组件缺席断言）——A8 静默红证；修后同现场
  warn+面板行绿。
- **红腿 DF-R3（W1）**：修前 unknown field 现场归档 log 唯一嘴（面板/结构化清单
  零行）→修后同现场面板行在档。

### 十三格矩阵（3 链：编译 4 + 资产 4 + 绑定 5）

| 格 | 链 | 内容 | 判据（全结构化） |
|---|---|---|---|
| C1 | 编译 | 改坏模板一行→Play→失败态三嘴 | footer `Failed`+`jackdaw/status` 构建 outcome+`notify_error`（log 在档） |
| C2 | 编译 | Build panel 自动聚焦+全文日志 | 面板文本含 `--> <file>:<line>:<col>` 行+「Build failed - 」状态行 |
| C3 | 编译 | 首错行结构化+行级定位动作 | 解析后首错行（file/line/col 字段）呈现；点击→落点动作断言（按决策 3：文件夹 reveal / 文件打开 / 编辑器协议探针结果） |
| C4 | 编译 | warning 不翻 Failed 但可见 | 纯 warning 现场：状态不 Failed、warning 行在面板日志（warn census 形态） |
| A1 | 资产 | 外部改名引用文件→载入→audit 四嘴 | 载入 summary warn（warn_on_load）+`jackdaw/audit` findings（Missing，四元组逐字段断言） |
| A2 | 资产 | Missing References 面板行呈现 | `asset.missing_list`→ui_tree walk 行文本=`finding.line()`+三色分级（kind 断言经远端 findings） |
| A3 | 资产 | Locate 跳转落点 | Locate→tab 打开（`jackdaw/status` 场景路径）+Name 实体 `select_only`（selection 远端断言） |
| A4 | 资产 | 加载失败域面板行（W3 采纳后） | 破文件→重载失败→面板清单行恰 1（(path,mtime) 一次锁维持）+再坏一次新 key 再说一次 |
| B1 | 绑定 | 未知组件载入→remedy 一行 | UnresolvedTypes remedy warn 在档（含类型清单）；重载同型不重复（去重语义） |
| B2 | 绑定 | unknown field 结构化行 | 修前红（log only）→修后：面板行含实体名/组件/字段（DF-R3 红绿对） |
| B3 | 绑定 | 面板双节呈现（决策 4 落地后） | 绑定节行四元组 ui_tree walk+与引用节并存互不吞 |
| B4 | 绑定 | 运行时绑定错进面板 | 游戏侧坏绑定→`StateEvent::Log`→Game 条 4 行+展开面（W4 采纳后）100 条可达；PIE 腿免者用 direct run+游戏 BRP 读日志面替代 |
| B5 | 绑定 | A8 红腿翻转 | re-export 路径场景：修前零 warn 组件不落（DF-R2）→修后 warn+面板行+组件处置语义明确（决策 5 采纳为前提；未采纳则此格记「票维持」红态在档） |

格间依赖：C3/C4 依赖决策 2/3；A4 依赖决策 5（W3 采纳）；B2/B3 依赖决策 4；
B4 依赖决策 6；B5 依赖决策 5。未采纳格降级为「现状记档格」（判据改为现状语义
断言在档），矩阵不空格。

---

## 三、真机腿清单（Mac，bash+curl+jq；T2 集中跑）

- **驱动面**：编辑器 BRP 15703（`jackdaw/audit`/`jackdaw/status`/`scene.open`/
  `asset.missing_list`/编辑类 operator 改坏引用）+游戏 BRP 15702（fixture 注入
  `jackdaw_remote`，t15-live.sh 先例）；direct run 为主，PIE 腿免（A10/N13）。
- **写坏现场三件**：①模板源文件注入编译错误（sed 一行改坏→Play）；②assets 下
  引用文件外部 `mv`（audit/加载双域）；③手写场景文档注入未知组件/未知字段/
  re-export 路径（python3 写盘，T15 手拼先例）。
- **自守**：面板断言双轨=结构化远端锚优先+`ui_tree` 文本锚兜底；**避开**对话框
  提交与 Inspector 字段行定位族（A7）；构建腿前后带 `jackdaw/wait` 重试窗（A9
  高发窗口=开工程构建）；**勿设 RUST_BACKTRACE**；warn 形态扫描
  （`unknown field|asset load failed|failed to load|references name files|type[s]? .* in neither|build failed`）入常备腿。
- **红态归档纪律**：DF-R1/R2/R3 修前证据（预 T1 构建）T1 内先归档再动手
  （T23 QD1 先例；红证构建 commit 与日志同档）。

---

## 四、分任务拆解（T1/T2/T3）

### T1「结构化+面板化建设轮」（建设主体：决策 1/2/3/4/5/6 落地；DF-R1/R2/R3 红证先归档）

1. **诊断行结构化（W2）**：`parse_build_line` 侧或编辑器侧新解析（按决策 2，
   建议 rendered 正则提 `--> file:line:col`）→结构化失败行清单（挂 `BuildStatus`
   或伴生资源）；Build panel 行级渲染+首错定位+点击动作（按决策 3 落点）。
   管线（cargo argv/JSON 流）零改动。
2. **绑定错误结构化落点+面板行（W1）**：apply unknown field 补实体/文档上下文的
   结构化记录+warn（行形态对照 MO1）；missing_list 扩容双节（按决策 4）——引用节
   现状保留+绑定节新行；A8 吸收与否按决策 5。
3. **加载失败面板行（W3，按决策 5 附带）**：asset_failures 失败清单资源化+并入
   聚合节或状态栏历史（按决策 1 形态）。
4. **Game 日志展开面（W4，按决策 6）**：Game 面板条点击展开滚动列表（100 条
   缓冲已在，纯消费侧）。
5. **门禁**：fmt/clippy ws/libtests（+新单测：解析器钉 `-->` 提取、一次锁与面板
   去重、rebind 拒答路径不回归）；红证 DF-R1/R2/R3 预修构建归档。

### T2「真机矩阵轮」（验收主任务：13 格+L 系腿；决策 7/8/9 收尾）

13 格真机全跑+warn census+live finds 归 DF 系记档（只记不修）；三链落点动作逐格
断言；发现即记 DF 系新候选。

### T3「终验 + 文档」

13 格复跑（同窗纪律，对照 T23 七相窗）；book 新章 `debugging-errors.md`（五嘴
地图+三链 30 秒定位清单+A8/A5 现状注记）或并入既有章（决策 8 附带）；A18 两处
book 微修随触碰落；A5 顺手与否按决策 7 执行；QA 全门（fmt/clippy/libtests/
guards/integration 视面）；终验报告。

---

## 五、设计决策点（需主控裁定——本方案不拍板）

**决策 1：面板架构。**
(a) 就地强化三面（Build panel 行级+missing_list 扩容+Game 条展开），不建新坞板；
(b) 新建统一 Problems 坞板聚合五嘴；(c) 混合：就地强化+轻聚合资源（一份结构化
错误清单资源，三面板各自渲染自己的节）。
**建议 (a)**，理由：三面板形态全在、聚合面的跨域去重/刷新是 T22 级子项目、验收句
只要求「可从面板定位」不要求「从一个面板」；(c) 的资源层可作 (b) 的将来地基。

**决策 2：编译诊断结构化深度。**
(a) rendered 文本正则提 `--> file:line:col`（零管线改动，host 侧解析）；
(b) 消费 `message.spans` 全结构化（改 `parse_build_line` 事件载荷，主结构化但
管线上下游 `BuildEvent` 面扩）；
(c) 不解析，只加「滚到首个 `-->` 行」的定位交互。
**建议 (a)**，理由：rendered 块是 rustc 保证格式（`--> path:line:col` 首行），
正则一行级；错误主行+次注（note/help）都在同一文本块，(a) 足以支撑 C3 格；
(b) 的增益（多 span 精确列）对验收句无增量。(c) 不满足「行可操作」的最低形。

**决策 3：代码位置跳转落点（句首「代码位置跳转」的落地面）。**
(a) reveal 所在文件夹（`open_with_desktop` 现成，零新依赖，不带行）；
(b) 系统默认应用打开文件（open 带 file，不带行）；
(c) 探测外部编辑器协议（`code --goto file:line:col` 族，探测可用则带行跳转，
不可用回落 (a)）；协议可用性=T1 首步纯探针（`which code`/可执行探测）。
**建议 (c) 带 (a) 回落**，理由：验收句明写「代码位置**跳转**」，(a) 只是「定位到
文件附近」；探测失败回落保证全机可用；不改编辑器内嵌代码面（无此 Scope）。

**决策 4：绑定错误面板化形态。**
(a) missing_list 扩容为「场景问题」双节（引用节+绑定节），行按钮族复用
（绑定节 Locate=选实体、Rebind 不可用则不渲染）；
(b) 独立 Binding Errors 面板/对话框；
(c) 只扩 audit 域（绑定错误入 findings 加 kind）。
**建议 (a)**，理由：行形态/一次锁/picker 全复用，missing list 已是「错误面板」
的既成心智；绑定错误（unknown field/未知类型）与引用错误同属「场景文档问题」，
分域数据源、同板呈现。(c) 会把「类型解析失败」混进「文件引用」语义（kind 三态
已定型，加第四态破坏 `as_str` 契约面）。

**决策 5：A8 吸收裁定 + W3 加载失败面板化。**
(A8) (a) 本轮顺手吸收（未知路径丢弃补 warn+remedy 文案改写，T23 MO9 先例——
修红腿 B5 翻绿）；(b) 维持票不动，B5 记红态在档。
(W3) (i) 面板化本轮做；(ii) 不做（T18「嘴即验收」定性维持，状态栏+log 足够）。
**建议 A8=(a)、W3=(i)**，理由：A8 是绑定链验收的直接对立物且修复窄（warn 一处+
文案一处）；W3 与决策 1 联动成本一格；两者不做则 13 格有两格长期「现状记档」，
验收句的「绑定错误」词只剩半边。

**决策 6：Game 日志展开面。**
(a) Game 面板条点击展开滚动列表（100 条缓冲全量可达，纯消费侧改动）；
(b) 并入决策 1 的聚合面运行时节；
(c) 不动（T12 验收已收口，4 行即嘴）。
**建议 (a)**，理由：缓冲已 100 条只露 4 条是纯浪费面；B4 格需要运行时错误可回看；
(a) 不动 T12 通道两端（A5 生产侧顺手与否互不依赖）。

**决策 7：A5 顺手裁定。**
(a) 本轮顺手（pie_log 窗口溢出补自身计数 warn，对照帧排空明报形态）；
(b) 维持票。
**建议 (a)（若决策 6 落地）**，理由：票注原文「下轮触碰 pie_log 时顺手」，W4 展开
面正是触碰；一行级改动+一枚单测。

**决策 8：真机口径与 book 形态。**
(a) 沿 T23 口径（Mac bash+curl+jq，BRP 15703/15702，direct run 为主，A10/N13
绕行，勿设 RUST_BACKTRACE）+book 新章；
(b) PIE 腿全免另加窗口纪律；
(c) book 并入既有章不新开。
**建议 (a)**（book 新章 `debugging-errors.md`），理由：三链跨五嘴，合页比散注
可查；既有章（assets/material-overrides）各注一句互链即可。

**决策 9：A9 服务侧指纹落盘（BRP handler 入口/出口计时+body 存在性）是否随本轮
真机基建先落。**
(a) 严格票内不前置，腿带重试窗自守；(b) 随 T2 真机基建先落（调试反馈域近亲）。
**建议 (a)**，理由：纪律不前置（历次口径）；指纹落盘动 remote 服务侧热路径，
属 A9 票本体第一步，混入会把「验收矩阵轮」变成「A9 修复轮」。

---

## 六、风险与回滚

- **风险 1：rendered 正则的格式漂移。** rustc rendered 输出无稳定性契约（JSON
  模式下 `-->` 行格式跨版本基本稳定但非承诺）。缓解：解析失败**回落现状**（全文
  日志照旧渲染，行级动作缺席不报错）；解析器单测钉格式+一条「非匹配行安静跳过」。
- **风险 2：绑定错误行的一次锁语义与重载去重互扰。** unknown field 每帧 apply
  可能重复（对照 UnresolvedTypes 的「unchanged remedy stays quiet」）。缓解：行身份
  （文档+实体+组件+字段）一次锁，对照 MO1 失败身份形；T1 单测钉「同现场恰一条」。
- **风险 3：missing_list 扩容后 ui_tree 行数膨胀伤 walk 断言。** 缓解：节标题锚
  +行数上限（对照 picker 分页先例）+双节行分域命名。
- **风险 4：外部编辑器协议探测的 Windows 形态。** `code` 在 PATH 的形态 Windows
  与 mac 不同。缓解：探测失败回落决策 3(a)，协议面做成「探测表」可扩展。
- **回滚**：全部改动可按资源/系统/按钮三粒度独立回退；管线侧零改动（决策 2(a)
  前提下）保证 `jd build`/export/CI 构建面不受影响。

## 七、与 T01-T23 已建设施的衔接

| 设施 | 衔接 |
|---|---|
| T18 asset_failures 一次锁 | W3 面板化的去重底座原样复用 |
| T23 audit 五元组+MO1 双嘴 | 绑定行四元组的形态模板；一次锁先例 |
| missing_list 行/按钮/picker | 决策 4 扩容的全套复用件；Locate=实体跳转先例 |
| T12 pie_log 通道+PieGameLog | W4 展开面的数据源；A5 顺手位 |
| T10/T23 构建管线（BuildStatus 三味同闩） | W2 解析的挂点（编辑器侧或 parse 侧）；零管线改动红线 |
| jackdaw/audit、jackdaw/status 远端嘴 | 真机断言主锚 |
| open_with_desktop | 决策 3(a) 回落现成件 |
| A 系活票 | 重叠表见 §一；A8/A5 候选顺手、A7/A9/A10/A14/A16 不前置 |

## 八、耗时预估

- T1 建设轮：1.5-2 天（解析器+三面板行级+红证归档；决策 1(a)+2(a)+3(c)+4(a)
  前提下；若决策 1(c)/2(b) 采纳 +0.5-1 天）
- T2 真机矩阵轮：1 天（13 格+warn census+重试窗）
- T3 终验+文档：1 天（13 格复跑+book 新章+A18/A5 顺手+QA 全门）
- **合计约 3.5-4 天**（对照 T23 三轮 3 天节奏；本任务面板面广但单格窄）
