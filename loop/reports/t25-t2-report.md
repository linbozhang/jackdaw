# T25 任务 2 报告：真机矩阵轮（13 格全跑 + LT-R1 绿侧对照 + LT9/LT10 两个新候选 + census 归因闭合）

> 分支 `loop/t25-live-tuning`（基线 = T1 收官 `bd65fef9`）；平台 macOS arm64（Apple M1 Pro，
> 工具链锁定 1.99.0）。驱动面：编辑器 BRP 15703（`jackdaw/pie`/`scene_bsn`/`history`/
> `status`/`scene_tree`/`selection.set`/`ui_tree`/`ui_click`）+ 游戏 BRP 15702（`world.query`
> /`get_components`/`mutate_components`/`write_message`——T20 形态的键盘行走与 assist）。
> 脚本 `loop/qa/t25-live.sh`（prep|live|gates 三相；live 内部按 **A–E 五个自足编辑器窗口**
> 分格组运行——见 §三 的窗口化裁决）；证据目录 `loop/t25-live/`（T1 沿用，本轮新增 70+
> 件；>500KB 的 walk 证据以 gzip 归档，zcat 可读）；归档前缀 `t25t2_*`；
> `loop/reports/t25t2_live_legs.log`（终轮逐腿判定 + census + 窗口记录）。
> RUST_BACKTRACE 全程未设；磁盘 26–27Gi（>15Gi 线）；门禁窗与真机窗分离（A6，
> gates 相独立调用）；`component.set` 修后语义 = LT2 注入面（T1 三窗亲证），本轮
> 全程绿侧，红档 `t25t1_ltr1_red.log` 的绿侧对照在本轮 A1 腿闭环（§二）。

## 〇、结论速览

**13 格全数在档：12 格判据全绿；D2 的 Path B 机制五腿全绿、其「save→重开实体在」收链
三腿被本轮新立的 LT10 阻断（只记不修，证据在档）——按方案「live finds 归 LT 系只记不
修」与 census 归因纪律承载，矩阵不空格。** 门禁全绿（fmt 零 diff、clippy 全仓/物理双包
零 warning、libtests 3087/3087 = T1 基线持平、guards 248/248——本轮**零产品改动**，
基线数字即铁证）。两个新 LT 候选（LT9 长会话投影陈旧绑定、LT10 Path B 提携落盘 avian
关系内件→下次加载崩溃）只记不修，候主控裁定。

## 一、注入面与判据自守（T1 交接逐条执行）

1. **注入面**：`selection.set`（scene_tree bits）+ `component.set` 即产生腿——本轮
   A1/A2/A3/B2/B3/C3/C4/D1/D2 的全部 field 腿一次命中（live_edits 即刻 +1，文档/盘/
   undo 三不动）；`component.add`/`component.remove`（LT1 结构类）同形命中。
2. **祖先爬升版 button_bits_in_row**（托盘行 label 外 holder 层）逐腿使用；另加
   **exact 形参**区分「Root / DirectionalLight」与「Root / DirectionalLight.illuminance」
   两行（前缀包含关系的反例）。
3. **click_label kind=button 回落**照用；本轮新增 **click_label_rect**（候选按 rect y
   择 top/bottom）——C2 的 Apply All 在「托盘 footer 与弹窗键同屏」时按 bottom 命中弹窗
   键（y=983 居中模态），一次命中无歧义。
4. **boot 先清 Recovered Work 模态**：五窗 boot 全带清场环；A→B 窗切换的带账 kill 被
   下一窗 boot 的 Discard All 正确消化（恢复会话判读 = v2 先例：每窗自建基线，不继承）。
5. **Revert 流送断言在 play 窗内**（B2：游戏侧 x 3.5→0.0 实测）；**停窗后的行 Revert =
   设计的 keep+warn 语义**——本轮 C4 实测并反立为腿（§二 C4）。
6. **勿复制 t25-red.sh:355 构造**：全脚本 `$(scene_bsn_text)` 形态，`grep -c 'sha_of "$'`
   = 0。
7. **v2 恢复会话判读**：每窗 boot 后重开 scene.bsn 并 settle_save，基线全部窗内自建。

## 二、13 格逐格判定（判据全结构化；窗口归属注明）

| 格 | 判定 | 关键实测（证据文件在 `loop/t25-live/`） |
|---|---|---|
| **A1** | **PASS** | 窗 A：component.set Root translation.x=2.0 → 游戏 BRP x 0.0→**2.0**（A1_GAME_STREAMED）+ live_edits=**1**（A1_LEDGER_ONE）+ 字段行点在档：**label 兄弟无文本节点 6→7**（A1_DOT_ON_FIELD_ROW；walk 的 rect 数据在本构建对纯 UI 节点退化为 0 尺寸，rect 形不可用，兄弟计数差分可用——A14 族自守）。**LT-R1 绿侧对照三腿全 PASS**：文档 SHA/盘 SHA/undo 深度全部不动（对照红档：文档动+undo+1+计 0+游戏静默——三重静默翻转为三重绿色）。**负向半 PASS**：真实 hazard 行走（T20 行走形，move_speed 0.5 测量步+满速俯冲，route=walk 在档）health **100.0→85.0**，live_edits 恒 1（A1_NEG_LEDGER_UNCHANGED）——游戏驱动变化不入账。 |
| **A2** | **PASS** | 同字段再编辑 2.0→3.5：计恒 **1**（A2_REEDIT_COUNT_STILL_ONE）+ 托盘 diff cell **`(not authored) -> 3.5`**（A2_TRAY_LIVE_SIDE_UPDATED；Root 的文档行是裸 Transform，无字段级 authored 值，基线诚实显 `(not authored)`——Sun 行的显式 Vec3 patch 则显数值形 `0.0 -> 5.0`，两形各自正确）；换实体（Sun x=5.0）→ 计 **2**（A2_SECOND_ENTITY_COUNT_TWO）+ 第二行 `0.0 -> 5.0` 在档。 |
| **A3** | **PASS** | 运行态 add 后的未 authored 组件字段编辑（Root/DirectionalLight.illuminance=8000）：托盘行 **`(not authored) -> 8000`**（A3_BASELINE_NOT_AUTHORED）+ 游戏 BRP illuminance 8000 实读（A3_GAME_VALUE）；**play 窗内托盘行 Save**（托盘经 Review 交接跨 replay 常开，A2_TRAY_SURVIVES_REPLAY）→ scene_bsn 出现**整组件 patch（20 个字段，A3_WHOLE_COMPONENT_PATCH）**携带 live 值 8000（A3_PATCH_CARRIES_LIVE）+ undo 恰 +1（A3_SAVE_ONE_UNDO）+ 计 5→4——N14 口径（稀疏 patch 会丢兄弟字段，整组件落天然保全）真机闭合。 |
| **A4** | **PASS** | add DirectionalLight on Root：游戏 BRP Root 实获组件（A4_ADD_STREAMED，default JSON 在档）+ 计 3（A4_ADD_LEDGERED）；remove DirectionalLight on Sun：游戏侧 Sun 组件消失（A4_REMOVE_STREAMED）+ 计 5（A4_REMOVE_LEDGERED，authored baseline 的结构条目）；托盘结构行 walk：**Revert disabled:true / Save enabled** 双腿（A4_STRUCTURAL_REVERT_DISABLED/SAVE_ENABLED——ui_tree 的 disabled 字段直读）；移除行 Save → Sun 的 authored patch **删除**（A4_PATCH_DROPPED）+ undo +1（A4_REMOVE_SAVE_ONE_UNDO）+ 计结算。 |
| **B1** | **PASS**（tooltip 腿=工具面注记） | badge 文本 **"5 edits"** 在 walk（B1_BADGE_TEXT，LT7/A14 口径：文本+计数面联判）+ `jackdaw/pie` live_edits=5 联判（B1_BADGE_COUNT_FACE）+ 托盘行 label/diff cell 全在 walk（B1_TRAY_ROWS/B1_DIFF_CELLS）。**tooltip 全值腿不可达**（B1_TOOLTIP_WALKED=FAIL 如实在档）：全值 tooltip 是 hover 300ms 后 spawn 的浮层，合成面无 hover（A14 族）；行内 diff cell 已携带两侧值（短标量截断上限 24 字符不触及，cell 即全值）。点击后 visible/invisible 双 walk 均无 "scene:" 文本，双档在案。 |
| **B2** | **PASS** | **play 窗内**行 Revert（T1 D3 教训执行）：游戏 BRP Root x **3.5→0.0**（B2_GAME_BASELINE_STREAMED——baseline 流送回运行中的游戏）+ 计 3→**2**（B2_COUNT_DECREMENTED）+ 字段行点消失（dot 节点 7→6，B2_DOT_GONE）。 |
| **B3** | **PASS** | 新编辑（Sun z=3.0）行 Save：scene_bsn 出现 **z: 3.0**（B3_DOCUMENT_AUTHORED）+ 计 3→2（B3_COUNT_DECREMENTED）+ undo 恰 **+1**（B3_ONE_UNDO_ENTRY）。 |
| **C1** | **PASS** ×2 | 1 条账停（cycle 1）与 2 条账停（窗 B）：标题 **"N live edits not saved to scene"** 精确匹配（C1_PROMPT_TITLE/C1_PROMPT_TITLE_TWO）+ 弹窗期间账计数与文档 SHA 双不动（C1_LEDGER_UNMOVED/C1_LEDGER_UNMOVED_TWO）；三键文本（Review/Discard/Apply All）在 walk。 |
| **C2** | **PASS**（五点链） | 窗 B 新建两条账（Root.x=4.5 + Sun.z=6.0）→ stop → 弹窗键 **Apply All**（rect 择键，一次命中）→ ①文档变（C2_DOCUMENT_CHANGED）+ 字段落盘 `x: 4.5`/`z: 6.0`（C2_FIELDS_AUTHORED）+ **undo 恰 +1 = 一条组**（C2_ONE_UNDO_GROUP，3→4）+ 计归 0（C2_APPLY_SETTLED）；②scene.save → 盘变（C2_SAVE_WROTE_DISK）；③reload → 文档仍持两值（C2_RELOAD_KEEPS）；④⑤replay → **游戏 BRP Root x=4.5（C2_GAME_ROOT_X）+ Sun z=6.0（C2_GAME_SUN_Z）= 保存值**。五点全链铁证闭合。 |
| **C3** | **PASS** | settle_save 后基线（doc/disk/undo）→ play → 1 条账 → stop → 弹窗（C3_PROMPT_UP）→ **Discard** → 文档 SHA 恒等（C3_DOCUMENT_IDENTICAL）+ 盘 SHA 恒等（C3_DISK_IDENTICAL）+ undo 深度不变（C3_UNTOUCHED_UNDO）+ 计归 0（C3_COUNT_ZERO）+ 弹窗关（C3_PROMPT_CLOSED）。放弃半边铁证四腿全绿。 |
| **C4** | **PASS** | 2 条账 → stop → 弹窗（C4_PROMPT_UP）→ **Review** → 弹窗关+托盘开且行在（C4_HANDOFF_TRAY：行在+弹窗文本不在）；**停窗行 Revert = 设计的 keep+warn**：revert_entry 需活投影承载 baseline 流送，停窗无活体 → WARN `has no live counterpart right now, keeping the entry`（editor-live 日志行在档）+ 计恒 2（**C4_REVERT_KEEPS_ENTRY**——本格的产品语义发现，反立为腿）；**两行 Save 逐条清账**：计 2→1→**0**（C4_TRIAGE_SAVE/SAVES_EMPTY）+ undo **+2**（一 Save 一条，C4_SAVE_TWO_UNDOS）+ **弹窗不重现**（walk 无弹窗文本）+ **托盘随计 0 收**、badge 文本消失（C4_SELF_HEALED）。 |
| **D1** | **PASS** | settle_save 基线 → play → 1 条账 → stop（弹窗在档 D1_PROMPT_UP）→ **文档 SHA 恒等**（D1_DOCUMENT_IDENTICAL）+ **盘 SHA 恒等**（D1_DISK_IDENTICAL）+ **ephemeral 归 0**（D1_EPHEMERAL_ZERO；30s budget 内排水——停态转换的 despawn 滞后数帧，首次读 28 为中间态）；**带弹窗 scene.save 落盘不含 live 值**（盘文本无 `y: 9.0`，D1_SAVE_NO_LIVE_VALUE）+ 文档仍恒等（D1_SAVE_DOC_UNCHANGED）——`live_mode_save_uses_authored_values_not_live_overlays` 的真机形闭合。 |
| **D2** | **PASS（Path A 全绿 + Path B 机制五腿全绿；收链三腿被 LT10 阻断，见 §四）** | **Path A**（authored Sun 选中 + y=6.5 编辑后点 Inspector 头部 Save to Scene）：scene_bsn 的 Sun Transform patch **全组件落地**（translation/rotation/scale 三关键字齐，D2_PATHA_WHOLE_COMPONENT）+ undo **恰 +1**（D2_PATHA_ONE_UNDO，一条 CommandGroup）+ live 值 6.5 在档（D2_PATHA_LIVE_VALUE）。**Path B**（ephemeral player 选中）：**player 定位 = BSN 位置探针**（scene_tree 的组件列表只含引擎类型——编辑器注册表无项目组件，PlayerHealth 不可名；改为遍历无名行逐个 `jackdaw/entity` 读 BSN，按 spawn 位移 `x: -2.0` 唯一命中，D2_PLAYER_SELECTED_FACE）→ Save to Scene → **新 node 入文档**（promoted patch 携带 `ColliderConstructor::Capsule`（player 独有形状）= D2_PATHB_NODE_IN_DOC）+ **ephemeral 31→30**（D2_PATHB_EPHEMERAL_DROPPED）+ **undo 深度不变**（D2_PATHB_NOT_UNDOABLE——**LT5 不可撤销注记真机在档**）+ scene.save 落盘同名标记（D2_DISK_HAS_PLAYER）+ **avian 关系内件随提携落盘**（ColliderOf { body: "4635v2" } 在档 = **D2_PROMOTE_INTERNALS_LAND**，LT10 证据腿）。**收链三腿（save→reload→replay→游戏侧实读）= FAIL，归因 LT10**：promoted node 的 avian 关系 patch 使下一次加载非确定崩溃（三次窗 E 复跑：一次 exit-101 崩溃 + 一次成功加载（游戏侧 players=1 实读）+ 一次 exit-101——泛化形态见 §四）。 |

**红绿对照（铁证②）**：红档 `t25t1_ltr1_red.log`（修前 component.set = 文档动+游戏静默+计 0
+undo+1+盘不动）↔ 本轮绿侧（同现场 `component.set`：游戏动+计 1+文档/盘/undo 三不动，
LTR1_GREEN_DOCUMENT_UNCHANGED/DISK_UNCHANGED/NO_UNDO 三腿 PASS）——**同一命令、两侧
档案，LT2 修复的行为闭环在真机完整在档**。LT-R2（N11 注入缺口）维持纯归档（方案原文：
零修复预期），本轮未复跑（T1 活体复认已足）。

## 三、窗口化裁决（本轮最重要的运行形态决定）

方案原设「13 格一窗全跑」。试跑五轮的证据链（attempt 1–5 的 console 存档：
`console-live-attempt{1,2,3,4,5}.log`）钉死了一个 **长会话退化**：同一编辑器会话自第
4 个 play 会话起，`component.set` 稳定落入 authored 路径（文档动+undo 动+计 0——红档
签名复现！），且 `jackdaw/pie` 的投影计数膨胀（authored 3→13、ephemeral 31→21）——
**投影的 `entity_for_stable_id` 反查开始应答已 despawn 的陈旧实体**，场景树的活动实体
不再出现在 `by_bits` 值集里。四轮隔离探针（/tmp 诊断，未入库）证明：单独复刻
「reload / apply-all / reload→play→stop→save→play」任一序列均不退化（路由全绿）——
诱因是多会话累积 + N13 崩溃窗的时序叠加，非单步可复现。

**处置（只记不修 + 运行形态自守）**：live 相改为 **A–E 五窗**（A=A1/A2/A3/A4/B1/B2/B3
+C1 首证；B=C2 五点链；C=C3+C4；D=D1；E=D2）——每窗一次全新 boot（恢复模态清场 +
scene.bsn 重开 + settle_save），窗内 ≤3 个 play 会话，陈旧绑定无从累积；窗口切换的带
账 kill 由下一窗 boot 的 Discard All 消化，账的形态每窗自建自清。**每窗即自足证据**
（`T25_WINDOWS="E"` 选择器支持单窗复跑——D2 的 Path B 三窗复验即用此形）。另加
**routed_edit/routed_add/routed_remove 护栏**（`ROUTE_FALL_THROUGH` 签名：计不动+
undo 动 = authored 路径漏过 → **先 history.undo 撤掉污染写** → 会话重启 → bits 重读 →
一次重试），attempt 5 的窗 C/D/E 全部由护栏兜住（日志在档），末两轮零触发。

## 四、LT 新候选（只记不修，候主控裁定）

- **LT9 🟡 长会话投影陈旧绑定（entity_for_stable_id 应答死亡实体）。** 症状：同一编辑器
  会话 ≥4 个 play 会话后，投影计数膨胀（authored 3→13 = by_bits 里的死亡实体被计为
  authored），场景树活动实体脱离 `by_bits` 值集，operator 面（`component.set`/add/
  remove）的 live 路由反查 miss → **静默落入 authored 路径**（文档动+undo 动+计 0——
  LT-R1 的红签名在修后构建上经投影陈旧态重新可达）。会话重启即愈（护栏验证）；窗口化
  运行完全规避。证据：`console-live-attempt{3,4,5}.log` 的退化段 + attempt 5 的
  ROUTE_FALL_THROUGH 段。修复面嫌疑：revert_preview/重生成路径对 stable-id 链接的
  重注册（T13 的 N13 专项或可一并照看）。**判据纪律**：护栏存在后不阻塞任何格。
- **LT10 🔴 Path B 提携把 avian 关系内件与逐帧字段落进文档，下一次加载非确定崩溃。**
  `promote_ephemeral_to_authored`/`register_entity_in_ast` 按注册表全量捕获（含
  `ColliderOf { body: "<bits>" }` 关系（指向本次会话的位串，重开后不可解析）与
  SleepTimer/VelocityIntegrationData/PreSolveDeltaRotation/ComputedAngularInertia 等
  逐帧内件；下一 play 的文档 apply 对 ColliderOf 反射实例化失败 → `thread 'main'
  panicked ... Couldn't create an instance of ColliderOf` → 游戏 exit 101。三次窗 E：
  两次崩溃（`editor-live-w2.log` 三条 panic 行 + exit-101 在档）、一次带 warn 静默加载
  （`does not fit bevy_ecs::entity::Entity; dropping it`）——**非确定**。修复面嫌疑：
  提携捕获过滤（跳过关系组件与 avian/逐帧内件，同 `should_skip_component` 的精神）。
  阻断面：D2 的「save→重开实体在」收链（本格三腿 FAIL 归此）；Path B 机制半边不受影
  响。**与 LT5（Path B 不可撤销）同域相邻，主控可并案裁定。**
- **⚪ 工具面注记（不入 LT 编号，A14 族）**：①ui_tree walk 的 rect 对纯 UI 节点退化
  为 0 尺寸（本构建形态）——live-edit 点的 rect 形判据不可用，兄弟计数差分可用；②
  hover tooltip（300ms 浮层）合成不可达——B1 的 tooltip 腿如实 FAIL 在档。

### buglist/LT 重叠核对

- **LT8（badge 合成点击不 spawn 托盘）**：维持，不重报——本轮托盘全程走 Review 交接路
  线（C4 的 handoff 腿即其本体）。
- **N13（drain panic）**：census 承载（§五）；本轮全部格判据不含 panic 清零。
- **N11**：不前置；本轮注入面 = LT2 修复面（决策 2(a) 兑现），全程零触碰 ui_input。
- **A10/A14/A9/A7**：自守承载（selection.set、文本+计数面联判、budget 重试窗、无手放
  点击）。

## 五、census 归因（N13 族逐窗在档）

终轮（attempt 10，A–E 五窗）：**error-handler panics=10、swap_remove 签名=13**
（`census-live.txt`；每窗明细在档）——约 16 次 play/stop 转换摊 **0.6–0.7 次/转换**，
远低于 ~5–6 次/周期基线，全数归 N13 族，无格判据依赖。窗 E 复验轮的 1 次 exit-101 +
3 条 ColliderOf panic 行归 **LT10**（非 N13；`editor-live-w2.log` 在档）。

**warn 形态扫描**（`SetComponent|AddComponent|unknown field|field write skipped`）：
**全部为 0，每一轮都是 0**——游戏侧五态失败嘴整轮未开（流送全数命中），`component.set`
修后的 Live 命中零 warn 形态保持。本轮观察到的 warn 全数归因：
`jackdaw_bsn::document::from_reflect` + `bevy_ecs::relationship`（LT10 落盘文档的
apply 面 + 投影 ephemeral 层级翻挪的悬空 ChildOf 警告——转换窗固有形态，charged to
no cell）；`jackdaw::scene_io::save` "keeping the asset reference 'sounds/ambient.wav'"
（fixture 音频资产不解析的 keep-with-warn 既有嘴，charged to no cell）；
`jackdaw_api_internal::keymap`（preset 和弦重复声明，启动固有，T24 已知）；
`jackdaw::live_edits` "keeping the entry" ×1 = **C4 的设计嘴**（keep+warn 语义本体，
本轮反立为腿）。

## 六、门禁（全绿，日志归档；与真机窗不同窗）

| 门 | 结果 | 归档 |
|---|---|---|
| `cargo fmt --all -- --check` | EXIT=0，零输出（历轮通过口径） | `t25t2-gates-fmt.log` |
| `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | EXIT=0，零 warning | `t25t2-gates-clippy-ws.log` |
| `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | EXIT=0，零行 | `t25t2-gates-clippy-phys.log` |
| `cargo test --workspace --lib` | **3087/3087**（= T1 基线持平——本轮零产品改动） | `t25t2-gates-libtests.log` |
| `cargo test -p jackdaw --test guards` | **248/248** | `t25t2-guards.log` |

## 七、偏差清单（分级如实）

- **D1（运行形态改窗）**：方案原设一窗全跑，实跑改五窗——诱因与证据见 §三；窗化后
  13 格全部在档，判据零降级。方案原文「同窗纪律」的格间可比性由「每窗自建基线 +
  settle_save」保持。
- **D2（fixture 需带 SceneNodeId）**：模板 scene.bsn 原生无 stable-id 行——投影把文档
  实体全部按 ephemeral 派生（authored=0），LT2 路由永不命中（attempt 1/2 的失败根因，
  诊断在档）。prep 现写入 T1/T06 的 fixture 形（`SceneNodeId(7001/7002/7003)`）。**给
  T3：任何依赖 authored 映射的投影腿，fixture 必须带 stable-id 行。**
- **D3（C4 语义反转立为腿）**：停窗行 Revert 的「保留 entry 只 warn」是方案事实五的
  明文分支，非缺陷——B2（play 窗流送+计减）与 C4（停窗 keep+warn）各自断言其设计半边。
- **D4（A3 的 Save 在 play 窗内做）**：停窗后 revert_preview 从 AST 重生成 authored
  预览，运行态新增组件不在其上，整组件 Save 将无物可序列化（代码路径亲读 + T1 交接
  注记 4 同源）——A3 的托盘行 Save 安排在 play 窗内（托盘经 Review 交接跨 replay 常开，
  该形态本身 = C4 的 handoff 语义，已单独立腿）。
- **D5（B1 tooltip 腿）**：hover 浮层合成不可达，腿如实 FAIL 在档（§二 B1）——A14 族
  判据自守的又一实证，不阻塞。
- **D6（census 的窗口 glob 跨轮残留）**：窗化后 census 的 `editor-live-w*.log` glob 会
  扫到前轮残留日志（attempt 11/12 的"across 2 windows"计数偏大）；终轮以 attempt 10 的
  五窗整轮数字（10/13）为准，残留偏差如实注记。

## 八、产物清单

- 分支新增：`loop/qa/t25-live.sh`（prep|live|gates 三相；五窗结构 + 注入护栏 +
  `T25_WINDOWS` 选择器）；`loop/reports/t25-t2-report.md`（本件）；
  `loop/reports/t25t2_live_legs.log`（终轮逐腿判定 + census + 窗口记录）。
- `loop/t25-live/`：新增 70+ 件（五窗 walk/click/face 证据、c2/c3/c4/d1/d2 文档快照、
  census-live.txt/warns-live.txt、`t25t2_gates_*.log` 五门、attempt 1–5 的 console 与
  编辑器日志存档；>500KB walk 以 gzip 归档）。`console-live.log` 为 attempt 9–12 的
  追加全程记录。
- 未动：产品源码（零 diff——libtests/guards 基线数字即证）、save/停止语义（红线）、
  buglist/roadmap/台账（主控职权）、N11/N13/A7/A9/A10/A14（纪律不前置）、fork/协议/
  场景格式；RUST_BACKTRACE 全程未设。

## 九、给 T3 的交接注意

1. **复跑形态**：`bash loop/qa/t25-live.sh prep && bash loop/qa/t25-live.sh live`——
   五窗结构保持（每窗自足证据即「同窗纪律」的窗化等价物）；单窗复验用
   `T25_WINDOWS="E"` 形。
2. **fixture**：prep 会重写 pristine scene.bsn（带 SceneNodeId 7001/7002/7003）——
   勿改回无 id 形（投影 authored 映射依赖它）。
3. **护栏**：`ROUTE_FALL_THROUGH` 若再现，护栏已自动 undo+重启+重试；T3 报告只需转录
   触发次数（LT9 的活体计数）。
4. **dot 判据**：label 兄弟无文本节点计数（2→3→2），非 rect；停窗 Revert=keep+warn
   （C4 形），流送 Revert 断言只在 play 窗（B2 形）。
5. **D2 收链**：LT10 未修前，重链三腿按「LT10 阻断」转录（崩溃 panic 行在
   `editor-live-w2.log`）；若主控裁定修 LT10，D2 重链应翻绿并在报告勘误痕记录。
6. **book 扩节素材**（决策 7）：预览差异面/diff cell 两形（`(not authored) ->` 与数值
   形）/三层白名单边界（投影 authored=0 的 fixture 反例即白名单第一层的活证）/组件增
   删的账面行态（Revert 置灰）/LT5+LT10 注记/30 秒清单——本轮各腿的 walk 文本可直接
   引用。
