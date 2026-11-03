# T25 运行态调参与选择性回写 — 实施方案

> 策划产物（2026-11-03，基于本地 main **b9bc6e4e**（T24 收官合入）全量只读调研：编辑器
> `src/pie.rs`/`src/pie_projection.rs`/`src/pie_mirror.rs`/`src/live_frame.rs`/
> `src/live_edits.rs`/`src/live_edits_ui.rs`/`src/live_highlight.rs`/`src/layout.rs`/
> `src/inspector/reflect_fields.rs`/`src/inspector/live_edit_dots.rs`/`src/inspector/ops.rs`/
> `src/inspector/mod.rs`/`src/hierarchy.rs`/`src/commands.rs`/`src/remote_ops.rs`/
> `src/remote/server.rs`/`src/remote/ui_probe.rs`/`src/scene_io/{mod,save}.rs`；
> `crates/jackdaw_runtime/src/pie.rs`；`crates/jackdaw_pie_protocol/src/event.rs`；
> `book/src/user-guide/play-in-editor.md`；`buglist.md` 全量 PIE/运行时/追踪域扫描；
> `loop/plans/t24-debug-feedback.md`（格式与纪律先例）；`loop/qa/t06-final-live.ps1` +
> `loop/reports/t06-t3-qa.md`（T06 停止态验收先例与 N11 记录）。**零临时探针**——本方案
> 全部关键结论是静态可复核事实（源码锚在档）+既有测试与既有矩阵证据在档。需求来源：
> `loop/plans/roadmap-game-dev.md` 第 42 行（T01-T24 已闭环）。
> **验收原文**（roadmap 第 42 行，逐字核实）：「**T25 运行态调参与选择性回写：有限白名单
> 组件 Live 编辑+停止后选择性保留。验收=预览差异→应用/放弃；不自动保存运行时对象。**」
> **任务定性：第十次定性反转，判定约 90/10（验收型）**——本任务描述的整座楼**早已建成**
> （主体系 pre-loop 的 #297「Initial play-in-editor support」2026-06-12 一并入库，T06
> 2026-10-26 又把停止态语义钉过一轮 SHA 铁证）：Live 编辑路由（Inspector 七个入口）/
> 追踪账（LiveEditLog 带 baseline）/预览差异面（Live Changes tray 的 `baseline -> live`
> 行+tooltip）/应用与放弃双半边（per-entry Save/Revert + Apply All/Discard All 四
> operator）/停止对账弹窗（StopPrompt 三键）/「不自动保存」的 save 隔离（AST 权威+
> ephemeral 永不序列化+停止 revert_preview）各有成品与单测（live_edits 23+
> live_edits_ui 8+pie_projection 22）。T25 的真工作=**验收**：把 T06 矩阵因 N11（注入
> 面）搁置的「live edit→追踪→预览差异→应用/放弃→停止对账」全链在真机走完 13 格，外加
> **两个窄口建设件**（①operator 面与 Inspector 面的 live 路由不对称=LT2，component.set
> 在 Live 模式直写文档绕过流送；②运行态组件增删不入追踪账=LT1）与一个定性裁定
> （「有限白名单」词=现状三层过滤判据化 or 新面，决策 3）。缺陷候选按 **LT 系**编号
> （Live Tuning，避开 R/Y/W/A/N/DF/SP/TM/MO 系），只记不修→主控裁定吸收面。真机口径沿
> T23/T24：**macOS（本机）**，bash+curl+jq 驱动编辑器 BRP 15703（`jackdaw/pie`/`jackdaw/
> scene_bsn`/`jackdaw/status`/`ui_tree`/`ui_click` 结构化锚）与游戏 BRP 15702（游戏侧
> 数值断言）；**live 编辑必经 PIE 会话**（`send_control_to_focused` 只达聚焦 PIE 实例，
> 直启游戏无此通道）——PIE 腿不能全免，N13（Mac 100% 复发、被错误处理器捕获编辑器存活）
> 按 census 归因纪律承载；**勿设 RUST_BACKTRACE**（T11-T3 口径：Mac debug 构建下触发
> wgpu SIGSEGV）；**A7/A9/A10/A14 家族不前置**（tray/弹窗按钮走 `ui_click`+行文本父节点
> 解析的 T24-T2 C3 先例；投影实体选中走 `selection.set` 的 T06 格 7 先例）。

---

## 0. 架构事实（核实结论，方案的地基）

**总判断：T25 不是「建运行态调参系统」——五件套（编辑路由/追踪账/差异面/应用放弃/
停止对账）全部在库且各有单测。T25 的工作=验收句全链真机化+两个不对称窄口（operator
面绕过追踪、组件增删不入账）+「白名单」词的定性裁定。**

- **事实一：Live 投影层已建成（pre-loop #297）。** `src/pie_projection.rs`：游戏侧 bits
  →编辑器预览实体的映射 `PieProjection.by_bits`（:27-34）；游戏 spawn 的运行时实体带
  `PieEphemeral` 标记（:19-20「never serialized」），authored 实体经 `SceneNodeId` 解析
  映射（:262-271）；`ChildOf` 重映射+环 guard（:82-134）；投影 skip 清单=相机前缀
  （:51）+`should_skip_component`+`Children`，allow 例外 `ActiveCameraRig`/
  `AnimationGraphPlayback`（:59-62）。停止/换焦统一走 `revert_preview`（:145-148：
  清投影+despawn ephemeral+从 AST 重生成 authored 预览）。
- **事实二：Inspector 的 Live 编辑路由已建成，七个入口全走同一函数。**
  `src/inspector/reflect_fields.rs:2081-2159` `try_route_pie_live_field_edit`：
  资源实体排除（:2093-2095）→Live 模式+投影实体反查 bits（:2102-2109）→读预览实体
  全组件 JSON 合并编辑字段→`ControlEvent::SetComponent` 流送到聚焦游戏（:2142-2149）
  →`record_live_edit` 记账（:2150-2157）。调用点七个：reflect_fields ×4
  （:1889/:2194/:2693/:3516）+`node_card.rs:1117`+`bindings_card.rs:1824`+
  `val_field.rs:395`——Inspector 可编辑的字段行**无组件白名单**，凡走提交路径的编辑
  一律路由 Live。
- **事实三：追踪账（选择性回写的半边）已建成，baseline 语义精细。**
  `src/live_edits.rs`：`LiveEditKey{bits,type_path,field_path}`+`LiveEditEntry{node_id,
  baseline,live_value,label}`（:17-41）；baseline 仅首次编辑捕获（:126-184）、node_id
  只补不降（:140-144）、同 node 换 bits 重键不重复（:145-157，zone 热重载场景）；
  **只记用户发起的编辑**——模块 doc :1-5「Game-driven component changes are never
  tracked」。账本清空时机：换焦清（`set_focused_instance`→`revert_preview`+log clear，
  pie_projection.rs:227-255，StopPrompt 开着时让位 ：241-249）、停止**不清**
  （`open_stop_prompt_if_dirty` 只弹窗不动账，live_edits_ui.rs:388-392）——停止后
  entry 经 node_id 仍可落盘（单测 `post_stop_apply_writes_via_node_id`）。
- **事实四：预览差异面已建成=Inspector 点+Live Changes tray。**
  字段行 live-edit 点（`src/inspector/live_edit_dots.rs:55-94`）：被追踪字段行出现
  点标记，悬停显 authored 值（:96-99），点击弹 Save/Revert 菜单（:28-29 动作常量）；
  tray（`src/live_edits_ui.rs`）：hierarchy 头部 badge 计数（:94-164，Live 或停止态
  显示 ：141-142），面板逐行「label + `baseline -> live`（两侧各 24 字符截断）
  +Save/Revert 按钮」（:229-306），tooltip 全值（:256-257），footer Apply All /
  Discard All（:309-324）；stale 行（实体不再解析）双按钮禁用置灰（:72-88）。
- **事实五：应用/放弃双半边已建成，四个 operator+两套粒度。**
  per-entry：`save_entry_to_scene`（live_edits.rs:395-441——authored node 走
  `SetBsnField` 单条可撤销；**组件未 authored 时整组件一次性落**（:325-388 分支，
  防稀疏 patch clobber 兄弟字段）；无 node 的 ephemeral 走整实体 promote 并清其全部
  entry）；`revert_entry`（:446-539——baseline 合并进全组件 JSON 回送游戏
  （:503-516），无 baseline 时 authored 组件取类型默认值（:459-474），无活体对应/
  组件已失时**保留 entry 只 warn**（:495-527））。批量：`apply_all_to_scene`
  （:545-609——authored 批量合一 CommandGroup 一条 undo，ephemeral 逐实体 promote，
  stale 保留并计数 warn）；`discard_all`（:612-616——只清账，文档与游戏零触碰）。
  operator 注册：`pie.live_edit_save`/`pie.live_edit_revert`/`pie.live_edits_apply_all`/
  `pie.live_edits_discard_all`（:627-706；per-entry 动作经 `LiveEditLog.pending_action`
  资源传递——**只有 tray/点菜单 UI 会置它**，:57-63 注记）。
- **事实六：整实体保留路径（Path A/B）已建成=Inspector 头部「Save to Scene」按钮。**
  `src/layout.rs:1076-1128`+`src/pie.rs:1401-1429`（`can_save_live_to_scene`：Live 态
  +选中在投影内+ephemeral 或 AST 有 node）；`promote_authored_overlay`
  （pie.rs:1531-1580——全组件捕获按 SetBsnField 组一条 undoable CommandGroup，
  :1431-1472 `preview_entity_components_as_bsn` 用与 `register_entity_in_ast` 同一
  skip 过滤）；`promote_ephemeral_to_authored`（pie.rs:1586-1598——mint 新 node id+
  去标记+`register_entity_in_ast`，**v1 不可撤销**（:1489 注记））。
- **事实七：停止对账弹窗已建成，三条路径全覆盖。**
  `StopPrompt`（live_edits_ui.rs:50-51）在 `OnEnter(PlayState::Stopped)` 挂
  `open_stop_prompt_if_dirty`（pie.rs:344-352）——**显式 Stop、崩溃/自退 reap 同一
  转换全触发**（cleanup_session_on_stop 同批 ：419-430）；弹窗标题「N live edits not
  saved to scene」（:416-422），三键=**Apply All**（关窗+operator）/ **Discard**（关窗
  +operator）/ **Review**（关窗+开 tray 逐条 triage，:533-547+:578-603）；跨 tab stale
  行计数提示「apply when it is active」（:512-531）；逐条 triage 清空后弹窗自愈关闭
  （:436-438）；重开 Play 时弹窗开着则转交 tray（`review_handoff_on_replay`
  :404-408）。
- **事实八：「不自动保存运行时对象」语义已建成且有三层实证。**
  ①save 面隔离：保存发射 live document（AST，只含 authored 值），单测
  `live_mode_save_uses_authored_values_not_live_overlays`（`src/scene_io/save.rs:1668`
  起）钉「Live 覆盖只存在于 ECS 实体，不落文档」；②ephemeral 永不序列化（事实一
  标记 doc）+停止 `revert_preview` 重生成；③T06 停止态 SHA 双腿铁证（T06-T2 链：
  Stop 后文档/盘文件字节恒等+undo 深度不变）+book 明文：「What the game did while
  running never reaches the document; the only way runtime changes come back is the
  explicit gates（Save to Scene / Live Changes tray / stop prompt's Apply）」
  （`book/src/user-guide/play-in-editor.md:60-63`）。
- **事实九：白名单=三层既有过滤，去中心化，无用户可见单面。**
  ①游戏侧流送过滤器：`With<Transform>`+排除 `DerivedFaceMesh`/`FrameCaptureCamera`
  （`crates/jackdaw_runtime/src/pie.rs:162-167`）——无 Transform 的实体根本不流送、
  不可选、不可 Live 编辑；②编辑器投影 skip（事实一 ：51-74）——相机组件永不投影；
  ③保存 skip（`src/scene_io/mod.rs:169-187` `should_skip_component`+`ALWAYS_SAVE_PATHS`
  :137-167）+整实体捕获同过滤（事实六）；另资源实体显式排除 live 路由（事实二
  :2093-2095）。三层之外**无逐组件用户可配白名单**——「有限白名单」词的落法=决策 3。
- **事实十：游戏侧执行端已建成且失败有嘴。** `crates/jackdaw_runtime/src/pie.rs`
  `SetComponent`（:326）/`AddComponent`（:333）/`RemoveComponent`（:340）落活实体；
  失败 warn 五态：unknown type path（:694）/无 ReflectComponent（:698）/反序列化失败
  （:706）/实体不存在（:713）/实体无该组件（:717），AddComponent 同形（:736+）——
  游戏日志（T12 PIE 日志通道）可断言。
- **事实十一：运行态组件增删已可流送，但**不入追踪账。`src/inspector/ops.rs`：
  `pie_live_target_bits`（:101-112）+`component.add`（:199-228 流送
  `AddComponent`，默认值兜底 schema default）+`component.remove`（:302-313 流送
  `RemoveComponent`）——**两条路径均无 `record_live_edit` 调用**：停止对账弹窗对运行时
  增删无感知，增删的保留只走整实体 Save to Scene（事实六全组件捕获会带上）。（LT1）
- **事实十二：operator 面与 Inspector 面的 live 路由不对称。**
  `component.set`（`src/remote_ops.rs:256-303`）走
  `field_edit_commit_on`（`src/commands.rs:294-325`）——直写 AST（SetBsnField），
  **无 live 路由**：Live 模式下对投影实体执行=文档被静默 authored（游戏不知情、
  无追踪、游戏下一帧流送值还会盖回预览显示）；对 ephemeral 执行=仅 warn
  「field write skipped: not in the scene document」（SetBsnField execute 的无 node
  分支）。`entity.set_transform`（remote_ops.rs:151）同走 authored 面
  （SetTransform→`sync_component_to_ast`，commands.rs:358-376）。（LT2）
- **事实十三：远端/工具面现状。** `jackdaw/pie` face 返回 `view_mode/focused/instances/
  projection{entities,authored,ephemeral}/live_edits`（计数，`src/remote/server.rs:
  689-705`）；`jackdaw/call_operator`（:1006-1016）可远端驱动**批量**双 operator
  （apply_all/discard_all 读账自足），**per-entry save/revert 无远端驱动面**
  （pending_action 仅 UI 置位，事实五）；LiveEditLog 逐条内容（baseline/live 值）无
  结构化远端读（计数之外只有 tray UI 文本可走查）。创建 live edit 的合成注入面=**
  N11**（buglist:515：ui_drag/ui_input 均不达数值行提交，T06 三探针实证，
  t06-final-live.ps1:299-305 在档）——live edit 的**产生**目前只能靠真人 UI。
- **事实十四：headless 语义面测试充足，真机链只有半截。**
  live_edits.rs 23 测+live_edits_ui.rs 8 测+pie_projection.rs 22 测（编辑/追踪/revert/
  apply/discard/promote/停止后 apply/reproject 全覆盖）；真机侧 T06 矩阵只走了
  selection 面+「无 pending 时停止文档不变」（格 7，t06-final-live.ps1:296-327），
  「产生 pending→tray→prompt 三键」因 N11 整链搁置——T25 的矩阵正是把这段走完。
- **事实十五：PIE 通道稳定性活票在本轮触发路径上。** N13（buglist:525：Mac 100% 复发、
  四受害系统、bevy 错误处理器捕获后编辑器存活）——live 编辑每腿都是 PIE 会话，日志
  必带 panic 噪音，按 T24 census 归因纪律承载；A10（:466 指针转发缩放布局）影响
  Select 模式点选——绕行=`selection.set`（T06 格 7 先例）；Y37（:280 每帧全量反射
  序列化）影响大场景流送延迟——模板规模不阻塞；DF-W6/W7（A19 票内 PIE 收尾两边缘）
  同域记档。

---

## 验收句逐词定性（矩阵化的前提）

验收句拆五词，每词标 **已建成 / 半成晶 / 缺口**（锚见 §0）：

| 词 | 判定 | 依据 |
|---|---|---|
| 「运行态调参…Live 编辑」 | **已建成** | Inspector 七入口 live 路由（事实二）+游戏侧执行端带 warn 嘴（事实十）；组件增删也流送（事实十一） |
| 「有限白名单组件」 | **半成晶（定性词）** | 三层既有过滤（游戏流送/投影/保存+资源实体排除，事实九）已是「有限」的实体；无用户可见白名单面——落法=决策 3 |
| 「停止后选择性保留」 | **已建成** | 停止弹窗三键+tray 逐条+账本停止不清/经 node_id 落盘（事实三/七）；组件增删不入账=窄缺口（事实十一，LT1） |
| 「预览差异→应用/放弃」 | **已建成** | tray `baseline -> live` 行+tooltip（事实四）+Save/Revert/Apply All/Discard 四 operator 双粒度（事实五） |
| 「不自动保存运行时对象」 | **已建成** | save 隔离单测+ephemeral 永不序列化+停止 revert+T06 SHA 铁证+book 明文（事实八）；operator 面绕过=例外（事实十二，LT2） |

**反转判定**：五词中 4 全成、1 半成（且是定性词不是功能词）——**约 90/10，验收型**
（对照：T24=45/55、T23=30/70、T20=90/10）。建设面只有两个窄口（LT1 组件增删入账、
LT2 operator 面补路由——都是「补一处调用/一个分支」量级）+注入面的工具裁定（决策 2），
主体是真机矩阵。

---

## 一、缺陷候选（LT 系，只记不修→主控裁定吸收面）

- **LT1 🟡 运行态组件增删不入追踪账，停止对账不覆盖。**
  `component.add`/`component.remove` 在 Live 模式流送游戏（ops.rs:199-228/:302-313）
  但无 `record_live_edit`：运行时加的组件停止后随 revert_preview 消失、弹窗计 0、
  用户无「刚才加过东西」提示；保留唯一通道=整实体 Save to Scene（会带上，但按钮门
  `can_save_live_to_scene` 不区分「有未对账增删」）。机械上入账顺滑：add 以
  `field_path=""`+全组件 JSON 记 entry 的既有形完全兼容（save 走事实五的整组件分支）；
  revert 无 baseline 会被既有「保留 entry 只 warn」语义接住——但 tray 行会出现一个
  Revert 永远 warn 的行，故入账需带结构类 entry 形（Save 可用/Revert 禁用）=决策 4。
- **LT2 🟡 operator 面绕过 live 路由，Live 模式下静默 authored。**
  `component.set`→`field_edit_commit_on` 直写 AST（事实十二）：Live 模式对投影实体
  执行=文档被改而游戏不流送、无追踪、预览显示随后被游戏流送值盖回——「文档与所见
  分叉」三重静默；对 ephemeral 执行=warn 不可达。`entity.set_transform` 同。
  修法窄：两入口补 `try_route_pie_live_field_edit` 前置路由（一处调用级）。此件同时
  是矩阵注入面的候选（决策 2a）。
- **LT3 🟡 live edit 的产生无合成注入面（N11 的 T25 面）。**
  真机矩阵的触发半边受阻：ui_drag/ui_input 不达数值行提交（N11 在档）；七个 live
  路由调用点全在 Inspector UI 代码路径内，无 operator 可达。不解决则 13 格的 A 系
  只能降级 headless。落法=决策 2（LT2 修复顺带解决 vs 修 N11 vs 降级矩阵）。
- **LT4 ⚪ per-entry 动作与逐条内容无结构化远端面。**
  pending_action 仅 UI 置位（事实五/十三）；`jackdaw/pie` 只有计数。矩阵可走
  ui_click tray/弹窗按钮（T24-T2 C3 的行文本父节点解析先例），零产品改动；若面板
  不可达再议远端面（决策 6）。
- **LT5 ⚪ Path B（ephemeral promote）不可撤销。**
  代码自注「Not undoable in v1 (no remove-node command exists that mirrors the
  insert)」（pie.rs:1489）：整实体 Save to Scene 一个运行时实体后 Ctrl+Z 无路可退
  （AST 有 node 但无 remove-node 命令）。与 T03 的 undo 全覆盖口径相抵，量级=新命令
  （DespawnSceneEntity 已有先例可对照），记档候裁。
- **LT6 ⚪ revert 的默认值基线依赖 `ReflectDefault`。**
  `default_field_json`（live_edits.rs:218-234）对无 `ReflectDefault` 的类型返回
  None→「authored 组件但字段无默认值」的 revert 落 warn 保留 entry——稀疏，实发生率
  低（authored 场景文档通常有全值 patch，baseline 走文档不走默认），记档。
- **LT7 ⚪ 弹窗/tray 的可达性判据受 A14 限制。**
  badge 显隐是 `Display::None` 翻转（live_edits_ui.rs:147-151），ui_tree 不暴露
  Display（A14 在档）——「badge 可见」格判据只能用计数面（`jackdaw/pie`
  live_edits>0）+文本在档联合判定，不能单靠 walk 有无。腿设计按此自守。

### buglist 重叠表（PIE/运行时/追踪域全量扫描）

| 票 | 关系 | 本轮处置建议 |
|---|---|---|
| N11（:515 Inspector 合成提交驱动缺口） | **LT3 的票面本体**（T06 搁置格 7 按钮链的因） | 决策 2 裁定：建议不前置修 N11 本体（A7 族纪律），以 LT2 修复顺带给注入面；N11 维持独立票 |
| N13（:525 drain panic 100% 复发） | live 编辑每腿是 PIE 会话，日志必带 panic 噪音（Mac 被捕获编辑器存活） | **不前置**；census 归因纪律（对照 T24 runtime 窗） |
| A10（:466 PIE 指针转发） | Select 模式点选腿 | **不前置**；绕行=selection.set（T06 格 7 先例） |
| Y37（:280 每帧全量序列化） | 流送延迟（大场景） | 不前置；模板规模不阻塞，记档 |
| A19 内 DF-W6/W7（PIE 收尾悬空 ChildOf/直启失 remote 面） | 同 PIE 域边缘 | census 承载；维持并法处置 |
| A14（:483 ui_tree 不暴露 Display/hover） | LT7 判据限制 | **不前置**；腿判据自守（计数面+文本联合） |
| A16（:491 GameFlow State<T> BRP 死） | 游戏侧流状态读通道 | 不触碰（模板零改动裁定先例） |
| A11（:470 rebind 世界侧粘性） | 语义近亲（文档↔活世界两半边的反向） | 不前置；T25 的 SetBsnField 落 AST 后预览即更新（live 链路天然同步），与 A11 的 rebind 场景不同域 |
| A7/A9 | 驱动工具债/BRP 空响应 | **不前置**；腿带 jackdaw/wait 重试窗（A9 高发窗口=开工程构建） |
| A12/A13/A15/A17 | 弱相关（渲染/缓存/flake/图集） | 不触碰 |

---

## 二、验收矩阵设计

### 铁证①：功能主干（「预览差异→应用/放弃」全链+通用交付）

live edit 产生→追踪（计数+点）→**预览差异**（tray 行 `baseline -> live`）→
**应用**（Apply All 一条 undo 组）→保存→重开→Play 生效（roadmap 通用交付全链）；
**放弃**半边（Discard/逐条 Revert）→文档字节恒等+undo 深度不变。断言锚全部结构化
（`jackdaw/pie` 计数与投影/`jackdaw/scene_bsn` 文档字段/`jackdaw/status` selection/
`ui_tree` 文本/游戏 BRP 数值），不依赖像素。

### 铁证②：红态先归档（红绿对）

- **红腿 LT-R1（LT2，若决策 2(a) 采纳）**：修前在 Live 模式对投影实体跑
  `component.set`→归档：文档 SHA 变化+游戏侧值不变+`live_edits` 计 0（三重静默
  铁证）——修后同现场：流送达游戏+计 1+文档只在显式 Save 后变化。
- **红腿 LT-R2（LT3/N11）**：修前 `ui_input` 打数值行+Enter→归档：无提交发生
  （值不变+计 0）——T06 三探针结论的活体复认（T1 纯探针腿，零修复预期），
  N11 票面证据刷新。

### 十三格矩阵（4 链：编辑产生 4 + 差异与逐条 3 + 停止对账 4 + 边界与保留 2）

| 格 | 链 | 内容 | 判据（全结构化） |
|---|---|---|---|
| A1 | 产生 | authored 实体字段 Live 编辑→流送+追踪+点 | 游戏 BRP 值变+`jackdaw/pie` live_edits=1+字段行点在档（ui_tree）；**负向半**：游戏驱动变化（hazard 扣血）不增计（live_edits 恒值=只记用户发起） |
| A2 | 产生 | 同字段再编辑→单 entry 更新 | 计数恒 1+tray 行 live 侧更新；换实体再编辑→计 2 |
| A3 | 产生 | 未 authored 组件字段编辑→整组件落 | entry baseline 显示 `(not authored)`（tray 文本）；逐条 Save→`scene_bsn` 整组件 patch 在档+兄弟字段不丢（N14 口径） |
| A4 | 产生 | 运行态组件 add/remove 流送+处置 | 游戏 BRP 组件出现/消失；账面按决策 4 裁定（入账=计增、不入账=计 0+book 记边界） |
| B1 | 差异 | tray 预览差异面 | badge 计数（jackdaw/pie 联判，LT7 自守）+ui_click 开 tray+行文本 `label`+`baseline -> live` 两侧值（截断形）+tooltip 全值 |
| B2 | 差异 | 逐条 Revert | 游戏侧值回 authored（游戏 BRP）+计减 1+点消失 |
| B3 | 差异 | 逐条 Save | `scene_bsn` 字段=live 值+计减 1+undo 恰一条（`jackdaw/history`） |
| C1 | 停止对账 | 带账停止弹弹窗 | Stop→弹窗标题「N live edits not saved to scene」（ui_tree）+背景账本不动（计不变） |
| C2 | 停止对账 | Apply All→通用交付全链 | Apply→文档字段变+undo 一条组（`jackdaw/history` 深度 +1）→save→重开→**Play 后游戏侧值=保存值**（五点链） |
| C3 | 停止对账 | Discard→放弃半边铁证 | Discard→文档 SHA 恒等+undo 深度不变+计归 0+弹窗关 |
| C4 | 停止对账 | Review 交接+triage 自愈 | Review→tray 开（弹窗关）；逐条 Save/Revert 清空→弹窗不重现+tray 随计 0 收 |
| D1 | 边界 | 不自动保存双腿 | 带运行时改动+未 Apply 停止→`scene_bsn` 文档 SHA 恒等+盘文件 SHA 恒等+ephemeral=0（`jackdaw/pie` projection）+此态下 save 落盘内容不含 live 值（`live_mode_save_uses_authored_values_not_live_overlays` 的真机形） |
| D2 | 边界 | Save to Scene 双路径 | Path A（authored 投影实体）：全组件覆盖落 node+一条 undo 组；Path B（ephemeral）：新 node 入文档（`scene_bsn` 树增根/节点）+save→重开实体在（LT5 不可撤销注记在档） |

格间依赖：A4 依赖决策 4；B/C 系的触发腿依赖决策 2（注入面）；D2 Path B 依赖决策 2
注入或 selection.set+ui_click Save to Scene 按钮（面板面可达时免）。未采纳格降级为
「现状记档格」（判据改现状语义断言在档），矩阵不空格。

---

## 三、真机腿清单（Mac，bash+curl+jq；T2 集中跑）

- **驱动面**：编辑器 BRP 15703（`pie.play_current`/`jackdaw/pie`/`jackdaw/scene_bsn`/
  `jackdaw/status`+`selection.set`/`jackdaw/history`/`jackdaw/call_operator`（批量双
  operator）+`ui_tree`/`ui_click`（tray/弹窗按钮，行文本父节点解析=T24-T2 C3 先例））+
  游戏 BRP 15702（fixture 注入 `jackdaw_remote`，游戏侧数值断言）。
- **live edit 注入**（按决策 2 落法）：(a) 采纳时 `component.set` 路由后即注入面
  （`selection.set` 选投影实体→`component.set`）；(b) 未采纳时 ui_input 尽力腿
  （A2/A3 降级记档风险在案）。
- **fixture**：模板工程（T20 形态——player/hazard/pickup 链现成，游戏驱动变化=
  hazard 扣血现成负向腿）；authored 实体选场景文档根节点（bsn 在盘可 `scene_bsn`
  对读），运行时实体选 player（游戏 spawn）。
- **自守**：**PIE 腿不能全免**（live 通道只达聚焦 PIE 实例，事实十五）——N13 按错
  误处理器捕获口径承载，panic 逐条 census 归因不进格判据；`selection.set` 替代
  Select 点选（A10）；badge 判据用计数面+文本联合（A14/LT7）；构建腿前后带
  `jackdaw/wait` 重试窗（A9）；**勿设 RUST_BACKTRACE**（T11-T3 口径）；warn 形态扫描
  （`SetComponent|AddComponent|swap_remove|unknown field`）入常备腿。
- **红态归档纪律**：LT-R1 修前证据（预 T1 构建）T1 内先归档再动手（T23 QD1/T24 DF-R
  先例；红证构建 commit 与日志同档）；LT-R2 探针腿零修复预期、纯归档。

---

## 四、分任务拆解（T1/T2/T3）

### T1「窄口建设+红证归档轮」（决策 2/3/4 落地；LT-R1/R2 先归档）

1. **LT2 修复（若决策 2(a) 采纳）**：`component.set`/`entity.set_transform` 补
   live 路由前置（`try_route_pie_live_field_edit` 一处调用级）+单测（Live 模式
   component.set→流送+记账、Scene 模式行为零变化、ephemeral warn 形态保持）；
   LT-R1 红证先归档。
2. **LT1 入账（若决策 4 采纳）**：`component.add`/`component.remove` 记结构类
   entry（`field_path=""`+kind 位；tray 行 Save 可用/Revert 禁用）+单测；不采纳则
   只归档现状边界注记。
3. **LT-R2 探针腿**：ui_input 数值行提交归档（零修复，N11 证据刷新）。
4. **门禁**：fmt/clippy ws/libtests（新单测钉两窄口）；红证归档在案。

### T2「真机矩阵轮」（验收主任务：13 格+warn census；决策 5/6 收尾）

13 格真机全跑+panic/warn census（N13 族逐条归因）+live finds 归 LT 系记档（只记不
修）；铁证①五点链与铁证②红绿对逐格断言。

### T3「终验 + 文档」

13 格复跑（同窗纪律，对照 T23/T24 终窗形态）；book 扩节（决策 7）：
`play-in-editor.md` 「The stop prompt and live changes」节扩预览差异/白名单三层/
组件增删边界/LT5 注记+30 秒清单；活票处置按裁定落账；QA 全门；终验报告。

---

## 五、设计决策点（需主控裁定——本方案不拍板）

**决策 1：任务定性确认。**
(a) 验收型（90/10）：不重建系统，矩阵为主体+两个窄口小件；(b) 建设型重裁（如主控对
「白名单」另有构想则升建设）。
**建议 (a)**，理由：五件套成品+93 个 headless 单测在档，T06 已钉停止态 SHA 铁证；
重建/新面无需求信号。

**决策 2：live edit 注入面（LT3/N11 处置）。**
(a) `component.set`/`entity.set_transform` 补 live 路由（LT2 修复与注入面一体，小
产品件+单测；operator 面语义与 Inspector 面对齐）；(b) 修 N11 本体（ui_input 数值行
提交——工具面大改，A7 族纪律风险）；(c) 都不做（A2/A3 触发腿降级 headless，
矩阵两格记档）。
**建议 (a)**，理由：LT2 本身是缺陷（Live 模式静默 authored+文档所见分叉），修复
顺带产出确定性注入面；N11 维持独立票不前置（纪律）。(b) 的收益面（所有 Inspector
驱动任务）超出 T25 需求，留给 A7 族批量。

**决策 3：「有限白名单组件」的落法。**
(a) 判据化现状三层过滤（游戏流送 `With<Transform>`/投影 skip/保存 skip+资源实体
排除），book 写清边界，矩阵 D1/A1 负向腿承载，零产品改动；(b) 建用户可配白名单
（新配置面+编辑器 UI+两侧执行——T08 级子项目）；(c) 只对保存侧收紧（live 落盘的
组件须在名单内）。
**建议 (a)**，理由：roadmap 词读作约束（「有限」）而非功能；三层过滤已是事实上
的白名单且各层有单测；(b) 无需求信号且 T25 验收句不含「可配置」。

**决策 4：运行态组件增删入账（LT1）。**
(a) 最小入账：add/remove 记结构类 entry（kind 位；Save 走既有整组件路径可用，
Revert 对结构类禁用——tray 行态已有 per-action enable 面 ：72-88 可扩）；
(b) 不入账：现状记档（保留通道=整实体 Save to Scene），book 边界句；
(c) 完整对账（add 的 revert=游戏侧 RemoveComponent、remove 的 revert=重加
baseline——需新 ControlEvent 组合与 baseline 快照，面扩）。
**建议 (a)**，理由：「停止后选择性保留」的完整读法应覆盖增删；最小入账复用
`field_path=""` 既有形与 row-state 面；不可 revert 的行禁用按钮比永远 warn 诚实。
(c) 的复杂度与验收句不匹配。

**决策 5：N13 在 live 腿窗口的承载口径。**
(a) 维持票+错误处理器捕获口径+census 归因（Mac 形态编辑器存活，格判据不含 panic
清零）；(b) 本轮顺手修（数据结构级 panic，修复面在投影重入/陈旧 location 嫌疑链，
T13 已建议立项专项）。
**建议 (a)**，理由：N13 是 T13 已上调优先级的独立专项，修复风险高（ECS 内核嫌疑链）；
T25 每腿必经 PIE，混入会把验收轮变专项轮。census 纪律（T24 runtime 窗先例）够用。

**决策 6：per-entry 动作驱动面（LT4）。**
(a) ui_click 走 tray/弹窗按钮（零产品改动；T24-T2 C3 行文本父节点解析先例；
badge 显隐判据用计数面联防 A14）；(b) 加结构化远端面（pending_action 置位参数或
`jackdaw/pie` 扩 entries 列表——小工具面）。
**建议 (a) 先行**，理由：面板按钮是标准 feathers button，ui_click 可达性先例充分；
(b) 作为 T2 现场兜底（面板不可达时 T2 报告提请，不当前置建设）。

**决策 7：book 形态。**
(a) 扩既有节（`play-in-editor.md` 「The stop prompt and live changes」扩四块：
预览差异面/三层白名单边界/组件增删处置（按决策 4）/LT5 注记+30 秒清单）；
(b) 新章 `live-tuning.md`。
**建议 (a)**，理由：该节已存在且 PI 面其它节已覆盖 Scene/Live 树与三策略；扩节
不破既有交叉引用（T20-T3 Errata 先例的反面教训：新页会新增断链面）。

---

## 六、风险与回滚

- **风险 1：注入面若落决策 2(a)，component.set 语义变化波及既有调用方。**
  既有脚本/文档对 `component.set` 的 authored 语义依赖（T 系矩阵用例）。缓解：
  路由只在「Live 态+投影实体」双条件触发（与 Inspector 面同条件），Scene 态行为
  零变化；单测钉两态+ephemeral warn 三形；既有矩阵腿不受影响（均非 Live 态）。
- **风险 2：tray/弹窗 ui_click 可达性未证。** Editor UI 面先例充分但 tray 是浮动
  面板（绝对定位 ：195-215）。缓解：决策 6(b) 兜底；T1 探针腿先验可达性（零成本）。
- **风险 3：N13 panic 噪音淹没 census。** 每腿必经 PIE（Mac 100% 复发）。缓解：
  census 按签名归因 N13 族（T24 runtime 窗先例），格判据不依赖 panic 清零；
  panic 计数异常升高（远超 ~5-6 次/周期基线）记 LT 新候选。
- **风险 4：模板游戏实体生命周期与 A2 重键路径。** zone 热重载/respawn 的 re-key
  已有单测（:995-1028），真机触发需要模板场景恰好重生 authored 实体——A2 不强求
  重键真机腿（headless 面已覆盖），真机只钉单 entry 更新半。
- **回滚**：两窄口件各自独立可退（路由一处调用/入账一处调用+kind 位）；矩阵腿零
  产品依赖（决策 6(a) 前提下）；save/停止语义零触碰（本任务红线——只在既有
  explicit gates 上验证，不改门）。

## 七、与 T01-T24 已建设施的衔接

| 设施 | 衔接 |
|---|---|
| #297 PIE 五件套（投影/追踪/差异/应用放弃/停止对账） | 验收对象本体；零重建 |
| T06 停止态 SHA 铁证+三策略+临时副本 | D1 格判据的直接先例；格 7 搁置链=本轮正主 |
| T12 PIE 日志通道（StateEvent::Log→Game 条） | 游戏侧 warn 嘴的断言面（事实十） |
| T20 模板游戏（hazard/pickup/GameFlow） | A1 负向腿（游戏驱动变化）与 C2 Play 腿的 fixture |
| `jackdaw/pie`/`scene_bsn`/`history`/`call_operator` 远端面 | 矩阵主断言锚 |
| ui_tree/ui_click+行文本父节点解析 | tray/弹窗驱动（T24-T2 C3 先例） |
| T23 QD1/T24 DF-R 红证纪律 | LT-R1/R2 修前归档先例 |
| A 系活票 | 重叠表见 §一；N11 关联不前置、N13/A10/A14/Y37 自守承载 |

## 八、耗时预估

- T1 建设轮：0.5-1.5 天（决策 2(a)+4(a) 双采纳≈1 天含单测与红证归档；单采纳或全
  不采纳≈0.5 天；决策 2(b) 采纳 +1-2 天）
- T2 真机矩阵轮：1 天（13 格+census+注入腿重试窗）
- T3 终验+文档：1 天（13 格复跑+book 扩节+QA 全门）
- **合计约 2.5-3.5 天**（对照 T24 三轮 3 天节奏；本任务建设面极窄、矩阵面中等）
