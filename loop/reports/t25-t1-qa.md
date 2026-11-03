# T25 任务 1 QA 独立复核报告：窄口建设+红证归档轮

> QA 角色产出，2026-11-03。分支 `loop/t25-live-tuning` @ `6bf62357`（基线 `050b4813` = T25
> 方案 commit，唯一父，提交链亲核无误）。平台 macOS arm64（Apple M1 Pro，工具链锁定
> 1.99.0 / rustfmt 1.10.0，无 rustfmt.toml 覆盖）。复核方法：diff 面亲核 + 五门亲跑
> （归档前缀 `t25t1qa_*`，非转录）+ 两窄口源码级亲读 + 红证三件真身核（SHA 离线复算 +
> 构建归属机制核 + 原始 console 日志逐行对账）+ D1-D4 逐项裁 + T2 交接面评估。
> 只验不修（未改产品代码/buglist/roadmap/台账）；RUST_BACKTRACE 全程未设（跑门前显式
> unset 并确认）；门禁时磁盘 27Gi（>15Gi 线）；门禁纯本窗，与任何真机窗不同窗。

## 〇、裁决：**FAIL（单点阻塞，修复路径机械且即时）**

- **QA-1 🔴（唯一阻塞）fmt 门在提交树上红，程序报告门禁表与提交信息的不实绿记。**
  `cargo fmt --all -- --check` 亲跑 **EXIT=1**（归档 `t25t1qa_gates_fmt.log`）：
  恰一处 diff——`src/remote_ops.rs:264`（本轮新增的 `apply_computed_transform` 内
  `let serializer = TypedReflectSerializer::new(new_transform.as_partial_reflect(), &registry);`
  超长需折行；已核该行不在 050b4813 基线，系本轮引入）。工具链锁定 1.99.0、无
  rustfmt 覆盖配置，失败确定性可复现、非环境漂移。报告 §三 门禁表第一行「EXIT=0
  零 Diff（行内过）」与提交信息「fmt clean」**与事实不符**；且 fmt 门无归档日志
  （报告自注「行内过」）——与历轮 fmt 归档口径（t06t3_fmt.log 0 字节在档）不符，
  此处本应引起警觉。
- **其余五项复核全部独立通过**（详见下），无其他阻塞。修复路径：程序在本轮提交上
  补一行 rustfmt 机械折行（零语义）→ 亲跑 fmt EXIT=0 归档 → 修订报告 §三 该行 →
  QA 抽验 fmt 一门即可，**无需重审实质**。修复后即放行 T2 真机矩阵轮 13 格。

## 一、diff 面亲核：**PASS（红线全保持）**

`git diff --name-only 050b4813..6bf62357` = **59 文件**，与预期面逐一吻合：

| 面 | 件数 | 判定 |
|---|---|---|
| src/ 产品码 | 6（`remote_ops.rs` 320 行±、`live_edits.rs` 369±、`live_edits_ui.rs` 55±、`inspector/ops.rs` 22±、`pie_projection.rs` +1、`remote/server.rs` +1） | ✓ 恰如报告 §七所列 |
| loop/qa/ 新脚本 | 3（t25-red.sh / t25-probe.sh / t25-probe3.sh） | ✓ |
| loop/reports/ | 8（报告+7 归档日志） | ✓ |
| loop/t25-live/ 证据 | 42（红窗+三探针窗 walk/响应/census） | ✓ |

红线逐条：

- **`scene_io/{mod,save}.rs` 零 diff** ✓（硬判据满足）。旁证：新测试名
  `scene_io::save::failed_authoritative_write_keeps_the_scene_dirty` 在 `git show
  050b4813:src/scene_io/save.rs` **:1694 已在**（T24 收官 64b26f37 添入）——与本轮无关，
  不构成暗改。
- **停止语义零触碰** ✓：`src/pie.rs`（`revert_preview`/`open_stop_prompt_if_dirty` 所在）
  零 diff；`revert_preview` 所在 `pie_projection.rs` 仅 +1 行测试构造 `kind` 位
  （mod tests 内）；`live_edits_ui.rs` 的改动面= `tray_row_state` 增 kind 参 + 两条
  rebuild 调用点传 `entry.kind` + 测试——StopPrompt 三键/弹窗结构/revert_entry 语义
  零触碰。LT1 的 Save 半边（`build_save_command` 顶部 ComponentRemoved 分支 +
  两调用点静默结账）属决策 4(a) 明文授权的 explicit-gates 面内扩展，非「门」的改动：
  文档仍只在显式 Save/Apply 时变化（`scene_io/save.rs` 零 diff 即铁证）。
- **buglist / roadmap / progress 台账零触碰** ✓（diff 清单无其一）。
- `pie_projection.rs` 与 `remote/server.rs` 各恰 1 行、均在 `mod tests` 测试构造补
  `kind: LiveEditKind::Field`——「仅测试构造补位」的报告声明逐字属实。

## 二、门禁亲跑（t25t1qa_* 归档在案）

| 门 | 我的命令与结果 | 程序报告口径 | 判定 |
|---|---|---|---|
| fmt | `cargo fmt --all -- --check` **EXIT=1**，1 处 diff（remote_ops.rs:264） | 「EXIT=0 零 Diff（行内过）」 | **不符（QA-1，阻塞）** |
| clippy ws | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` EXIT=0，0 warning 0 error | EXIT=0 | ✓ 一致 |
| clippy 物理 | `-p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` EXIT=0，零行 | EXIT=0 零行 | ✓ 一致 |
| libtests | `cargo test --workspace --lib` EXIT=0，**3087 passed / 0 failed**（59 条 result 行求和；FAILed 零） | 3087/3087 | ✓ 一致 |
| guards | `cargo test -p jackdaw --test guards` EXIT=0，**248 passed / 0 failed**（168.8s） | 248/248（166s） | ✓ 一致 |

**3087 拆账独立复核**（对 T24 终态基线 `t24t3_gates_libtests.log` 3073 做名字集
comm 对账，比程序报告对 t24t1 的口径更贴近基线）：

- **+15 / −1**：+14 = 本轮新测逐名全数在案（remote_ops 6 + live_edits 6 +
  live_edits_ui 2，与报告 §五 表逐名一致，且全在我亲跑日志中 ok）；+1 =
  `scene_io::save::failed_authoritative_write_keeps_the_scene_dirty`（**T24 收官
  64b26f37 添入的 lineage 漂移，050b4813 树上已在**）；−1 =
  `sprite_stage::a_sprite_that_does_not_draw_does_not_pick`（T24 T3 弧内已删，
  050b4813 源码已无——`git grep` 仅命中旧 t21t1 归档日志）。净 +14 恰为本轮。
- 程序报告「3073+14=3087 恰为本轮 14 名（漂移名与既有改名/移出互抵）」的**算术
  结论为真**；其对 t24t1 的 17 名/3 漂移口径与我的 t24t3 口径（+15/−1、漂移互抵）
  相互印证。⚪ 细节注记：程序口径未点名 sprite 移出与 scene_io 添入的具体 commit
  归属（64b26f37），本报告补全。
- ⚪ 归档注记：程序归档 `t25t1_gates_clippy_ws.log` 仅含最终干净轮（4 行），
  「首跑 1 处 needless_borrow 修后过」的首跑未归档、无从复核；最终态我已独立确证
  零 warning，不构成阻塞，但该句属不可复核声明（对照 QA-1 的教训：不可复核的门禁
  声明=归档纪律漏洞）。

## 三、两窄口源码级亲读：**双双 PASS**

### LT2（operator 面补 live 路由）— PASS

- **前置路由与双条件同源** ✓：`apply_component_set`（remote_ops.rs:333 起）与
  `apply_computed_transform`（:251 起）各在 authored 路径前调用
  `crate::inspector::reflect_fields::try_route_pie_live_field_edit`——与 Inspector
  七入口（reflect_fields ×4 + node_card + bindings_card + val_field）**同一个函数**
  （reflect_fields.rs:2081），条件逐行亲读一致：资源实体排除（`is_resource_entity`
  先判）→ `PieViewMode::Live` → `live_bits_for_preview` 投影反查。三重未命中
  （Scene 态/非投影/资源实体）原样落 authored 路径。
- **命中即 return，零文档零 history** ✓：路由函数内流送 `SetComponent` +
  `record_live_edit` 后返 true，两 apply 函数直接返回——不推 SetBsnField/
  SetTransform 命令、不进 CommandHistory；单测双侧钉死（Live 双测均断言
  `undo_len == 0` + 文档 debug 串恒等）。
- **set_transform 全组件 JSON + 空路径语义** ✓：`TypedReflectSerializer` 序列化
  new_transform → `field_path=""`；`component_json.rs` 双函数亲读：
  `typed_json_path_set` 首行 `if path.is_empty() { *root = value; return; }`
  （空路径=整组件替换），`get_field_in_component_json` 文档明注「An empty
  field_path returns the whole component value」→ 记账 live 值=整组件、label 走
  `record_live_edit` 既有空路径分支 `{name} / {short_type}`（该分支 050b4813 已在，
  非本轮新增）。
- **Scene 态零变化** ✓：miss 路径与修前**逐字节一致**（diff 亲读：`field_edit_commit_on`
  + 同文案 `warn_caller`，无任何其它改动）；`apply_computed_transform` miss 时
  SetTransform 命令 + push 与修前一致；`scene_mode_*` 两单测钉 AST 写入/恰一条 undo/
  无记账。
- **ephemeral warn 分支保持** ✓：warn 在既有 `SetBsnField` execute（commands.rs，
  本轮零 diff）；`field_edit_commit_on` 成功构造路径后无条件 execute+push（:322-324），
  ephemeral 的 no-node 分支 warn 后命令仍入栈=既有形态——单测按 D3 修正后的实貌钉。
- **新面安全注记（QA 亲核非报告所载）**：LT2 使 `field_path=""` 且 `kind=Field` 的
  entry **首次机器可达**（Inspector 七入口从不传空路径）。该形 entry 的 Revert 在
  tray 上**可用**（kind==Field），其语义已核健全：`revert_entry` 的
  `merged.is_null() && !key.field_path.is_empty()` 守卫带明注「An empty field path
  carries a whole-component baseline and may legitimately re-add it」——整组件
  baseline 回送+预览侧 `apply_component_value` 同步，T2 真机若遇该行可放心走。
- **6 单测亲跑全 ok**（亲跑日志逐名在案），断言面与报告 §一.1 所述一致。

### LT1（运行态组件增删入账）— PASS

- **三态 kind 位** ✓：`LiveEditKind { Field, ComponentAdded, ComponentRemoved }`
  （Default=Field），entry 增 `kind` 位；既有 `record_live_edit` 尾部补
  `kind: Field`——字段路由语义零变。
- **`record_live_structural_edit`** ✓：`field_path=""` 结构键；baseline=authored
  整组件 JSON（`authored_field_json(..., "", ...)`，文档无 patch 时 None→tray 显
  「(not authored)」）；**remove 且无 authored 的回落分支亲读确认**：
  `.or_else(|| (kind == ComponentRemoved).then(|| serialize_component_json(world,
  preview, type_path)).filter(|v| !v.is_null()))` ——回落 pre-removal 预览序列化值
  （显示用），非 Null；label 复用既有 `{name} / {short_type}` 形。
- **同键更新 + re-key 收窄** ✓：精确键更新在前；re-key 查找条件带
  `k.field_path.is_empty()`（只认结构条目，**不劫持字段条目**——与
  `a_field_edit_and_a_structural_edit_on_one_type_stay_separate` 单测互证）。
- **Save 半边** ✓：`build_save_command` 顶部 ComponentRemoved→
  `RemoveProjectComponent::from_world`（撤 AST patch，undo 快照自恢复）；
  ComponentAdded 无 authored → 既有整组件分支（N14 口径天然满足）；
  **运行态-only remove 两调用点**（`save_entry_to_scene` / `apply_all_to_scene`）
  静默结账（`patch_authored` 判 + log remove/handled push，零 warn 零 authoring）
  ——单测 `a_runtime_only_removal_settles_without_authoring_anything` 钉死。
- **Tray 行态** ✓：`tray_row_state(resolves, kind)`——`structural = kind != Field`，
  `save_enabled: resolves`、`revert_enabled: resolves && !structural`（结构行 Save
  可用/Revert 禁用；stale 仍全禁）；`rebuild_tray` 与 `rebuild_stop_prompt` 两调用点
  均传 `entry.kind`。
- **ops.rs 记账点** ✓：`component.add` Live 分支流送前记 ComponentAdded（带 default
  JSON）、`component.remove` Live 分支记 ComponentRemoved（Null）——均在
  `pie_live_target_bits` 命中分支内，Scene 态增删零触碰。
- **8 单测亲跑全 ok**（live_edits 6 + live_edits_ui 2），行态矩阵与决策 4(a) 一致。

## 四、红证真身核：**ltr1 全真；ltr2 三腿真、一腿结构破（QA-2）；probe 三窗全对**

### LT-R1（三重静默）——真身成立

- **构建归属机制核** ✓：`t25-red.sh:46` 把 `build=$(git rev-parse --short HEAD)` 印进
  console-red.log；归档原件三次印戳全为 **`build=050b4813`**（22:28:21 prep /
  22:28:32 一次 **EDITOR_BOOT_FAIL 后诚实留痕重试** / 22:30:45 成功窗）。脚本自
  仓库 `./target/debug/jackdaw` 启动+pid 对账（`EDITOR_READY ... pid=74364` 与
  boot_pid 校验在脚本 ：157-158）；050b4813 相对 T24 终码确为 docs-only
  （b9bc6e4e..050b4813 = 方案 + progress.md 两文件，均非产品码——红档头注称
  「唯一前置 commit 为 docs-only 方案文件」措辞欠准，⚪ 见 QA-3a，实质成立）。
  另有行为指纹兜底：文档动而游戏/账本不动的形态在修后构建上不可能出现
  （修后路由即入账）。
- **文档 SHA 对离线复算精确复现** ✓：`t25-red.bsn.before`（盘文件，带头注释）去头
  注释+去尾换行 → SHA256 = `134099b4cd80…`；`t25-red.bsn.after-document` 去尾换行 →
  `aebf28f351c5…`——红档 SHA 对逐字符吻合；两文件 diff 恰两处：头注释行 + `y: 1.0→2.5`
  一字段，与「恰 y:1.0→2.5」声明一致。
- **七断言全对** ✓：GAME_UP / PROJECTION_SELECTED（scene_tree bits 4294962567，
  Live 视图）/ LEDGER_CLEAN_BEFORE（0）/ DOCUMENT_SILENTLY_AUTHORED（SHA 对）/
  GAME_VALUE_UNCHANGED（归档 `ltr1-game-transform.json` translation [0.0,1.0,0.0]，
  y 恒 1.0）/ LEDGER_COUNT_ZERO / DISK_UNTOUCHED（f7fa8f24 恒等，即归档 before 件
  本尊）/ HISTORY_ENTRY_PUSHED（undo 0→1）。operator 响应原件
  `{"result":"finished","warnings":[]}` 在档——「自信的哑巴」铁证。census-red.txt
  0 行 = 0 panic 0 swap_remove，与「本窗 N13 未发作」一致。

### LT-R2（N11 活体复认）——三腿真，一腿结构破

- **真腿** ✓：六行数值行（候选筛选 x>1050/y>150 依序，归档 candidates+六响应件，
  响应 1 原文 `"commit":"enter","typed":true`）逐行后 live_edits=0、game_y=1.0；
  NO_COMMIT / GAME_VALUE_UNCHANGED / ROWS_REACHED 三判定与原始日志逐行一致。
- **QA-2 🟡（D4 根因归因错误）**：`LTR2_DOCUMENT_STABLE` 在窗 FAIL 的真实根因
  **不是**报告所称「R2 腿前的 scene_bsn 读撞忙窗返回空（A9 类）」。committed 脚本
  `t25-red.sh:355` `local bsn_r2_before=$(sha_of "$scene_bsn_text")` 把**函数名当变量
  用**：bash 3.2.57 + `set -u` 下该构造打印 unbound error 但**不中止**、变量置空
  （我在本机 /bin/bash 3.2.57 实证复现：error 打印、`before=[]`、脚本继续）——
  **文档读从未发生**，before 恒空串，after 读回 aebf28f3，该腿**结构上不可能 PASS**
  （与忙窗无关、确定性）。console-red.log :46 `document:  -> aebf28f3…`（before 空）
  与此精确吻合。** mitigations 仍真**：R2-after=aebf28f3 与 R1-after 逐字符一致
  （console :26 与 :46 对读），打字腿零改动的离线复核成立，双记诚实
  （PHASE_DONE 行保留 FAIL）。但 A9 归因是错的，且该 bug 随脚本入库——报告 §六.7
  让 T2 复用这两脚本的命令，**T2 腿复制该构造将产出假 FAIL（或更糟的假恒真）**。
  处置：脚本修一行（`$(scene_bsn_text)`）；T2 腿禁用「变量形态的函数名」构造。

### probe_tray_click（6(a) 可达性三窗）——结论矩阵与原始日志全对

- INJECTION=PASS ×3（component.set 一发入账，LT2 注入面真机成立）。
- StopPrompt 三键 end-to-end 全真：Apply All authored **134099→6c31e7**（v1 :29，
  prompt 关）、Discard（v2 :88-92：计 0、文档恒等、undo 不变）、Review→tray
  handoff（v2 :96）。footer Apply All **6c31e7→fa0be35**（v2 :97-100）。行 Save
  **6c31e7→2750fda** undo+1（v3 第二跑 :43）。行 Revert 结账（v3 第二跑 :34-36，
  流送半边空读如实 FAIL=D3）。
- **badge 例外真身** ✓：click 响应原文 `"clicked":true,"target":{...,"kind":"button",
  "text":"1 edit"}`（v1 :9）而托盘不 spawn（v2 `PROBE_BADGE_OPENS_TRAY_FAIL`）——
  「badge 点位落点但不 spawn 托盘」的 LT 候选证据成立，非 6(a) 阻塞（Review handoff
  即 C4 链本体）。
- v1 恢复模态叙事与原始日志吻合（v1 托盘行 FAIL 链+Discard「2 candidates」歧义
  error 原文 ：34）；census v1 4/5、v2 3/3、v3 5/7 与归档一致（⚪ QA-3b：probe3
  首跑 census 1/1 未入报告 §二 census 行，琐碎）。

## 五、偏差 D1-D4 逐项裁定

| 偏差 | 裁定 | 依据 |
|---|---|---|
| **D1** 探改修后窗（骑 LT2 注入面） | **接受** | 修前确无注入面三重锚：N11 票面（buglist:515，T06 三探针）+ LT-R2 本构建活体复认 + **badge 渲染条件源码锚**（`live_edits_ui.rs:146` `count > 0 && (Live \|\| stopped)`，计 0 即 `Display::None`；托盘空即 despawn）——托盘/弹窗的行与键需真实 entry 才存在，预探无从谈起。骑决策 2(a) 的注入面零成本、结论等价；v1 模态发现反成数据点。如实披露 ✓ |
| **D2** 探针脚本两轮迭代 | **接受** | 均脚本面：v1 点名错（投影实体 Name=游戏侧 'Spinner'）+ 恢复模态干扰；v3 行结构深一层（label 外包 flex holder）→ 祖先爬升解析器（`t25-probe.sh:216` 亲读实现）。红档 verdict 以实文件离线复核为准——我已照办（§四），成立 |
| **D3** 两处测试设计修正 | **接受** | ①修测试不修系统核为真：miss 路径逐字=修前（diff 亲读），`field_edit_commit_on` 构造成功即无条件 execute+push（commands.rs:314-325）——「pushed no-op 命令」为既有形态，测试改钉实貌正确；②`P3_ROW_REVERT_STREAMED_BASELINE` 停窗后读游戏 BRP=腿设计误，probe3 原始日志两次如实 FAIL（game_y 空），Revert 对账半边（计 0+回 baseline）已证，流送半边归「停后无游戏」语义——处置正确 |
| **D4** 红窗读空窗双记 | **修正后接受（QA-2）** | 双记诚实、离线复核为真（R2-after=R1-after 逐字符核）——但根因归因错误：非 A9 忙窗空读，系 `t25-red.sh:355` 函数名当变量的**确定性脚本缺陷**（bash 3.2 set -u 不中止实证），该腿结构上不可能 PASS。结论不受损，归因须更正，脚本须修 |

## 六、T2 交接面评估：**四条注意全部可执行、源码/日志双锚在案**

1. **祖先爬升版 `button_bits_in_row`** ✓：`t25-probe.sh:216-240` 亲读——行文本祖先
   逐层爬升找含按钮兄弟的持有者（tray 行 label 外包 flex-grown holder，C3 单层
   parent 不够），v3 第二跑实证全通。可执行。
2. **click_label kind=button 歧义回落** ✓：`t25-probe.sh:197-199` 实现在案，v1 原始
   「2 candidates; pass \"index\" to pick one」（弹窗行 'Discard' kind=node vs 按键
   kind=button，rect 双列在案）为实证。可执行。
3. **boot 先清 Recovered Work 模态 scrim** ✓：`t25-probe.sh:154-156` 清场步+
   :18-20 头注教训；v1（模态在屏托盘全 FAIL）vs v2（清后全通）的对照即证据。
   另注：v2 起点文档 6c31e7 系 v1 会话 authored 后经恢复机制带过——T2 若遇「文档
   已是 authored 值」的起点（Apply All authored 断言落空），按 v2 先例判 settled
   即可，勿误报。可执行。
4. **Revert 流送断言须在 play 窗内** ✓：D3 后半的腿设计教训（停窗后 ControlEvent
   安静丢弃为既有语义）；B2 格若需流送半边断言须在 stop 之前。可执行。

补充给 T2（QA 增补）：注入面（`selection.set`+`component.set`）三窗 INJECTION 全
PASS 可直接作 A 系触发腿；结构类行（A4 腿）行形与置灰见报告 §六.3 与本报告 §三
LT1（单测钉 add 行 `(not authored) -> {default}`、remove 行 `{json} -> null`）；
⚠️ **勿复制 `t25-red.sh:355` 的 `"$scene_bsn_text"` 变量形态函数调用构造**（QA-2）。

**badge 不 spawn 托盘候选的 LT 编号建议（主控职权，QA 建议）：LT8** ——「badge chip
合成点击可达性缺口：`ui_click` 返回 clicked:true 且 target=badge button，但托盘不
spawn（嫌疑：badge 点位上方覆盖节点或 `hidden()` prop 的 picking 排除）。与 LT7
（ui_tree 不暴露 Display，A14 族判据限制）不同面；非验收阻塞——托盘开行路线=
stop→Review（C4 链本体），零产品改动。建议只记不修，候 T25 收尾或 A7 族批量。」
（LT1-LT7 已按方案 §一 占用，LT8 为下一个空号。）

## 七、QA 发现清单（汇总）

| # | 级 | 发现 | 处置 |
|---|---|---|---|
| QA-1 | 🔴 | fmt 门提交树红（remote_ops.rs:264 本轮新线超长）；报告门禁表与提交信息「fmt clean」不实；fmt 无归档 | **阻塞**。程序补一行折行+fmt 重跑归档+报告一行修订；QA 抽验 fmt 后放行 |
| QA-2 | 🟡 | D4 根因归因错误：LTR2_DOCUMENT_STABLE 结构破（脚本 ：355 函数名当变量，bash 3.2 实证确定性），非 A9 忙窗；双记与离线复核本身为真 | 归因更正入报告/脚本修一行；T2 腿勿复制该构造 |
| QA-3 | ⚪ | (a) 红档头注「唯一前置 commit docs-only」欠准（实为 plan+progress.md 两文件，均非产品码）；(b) probe3 首跑 census 1/1 未入 §二 census 行；(c) clippy「首跑 needless_borrow」无首跑归档、不可复核 | 记档；不阻塞 |
| QA-4 | ⚪ | 拆账口径补全：对 t24t3 基线 = +15/−1（scene_io::save 一名 64b26f37 添、sprite_stage 一名 T24 T3 弧删，互抵后净 +14）；报告算术结论为真 | 已在本报告 §二补全，不阻塞 |

## 八、纪律与产物

- RUST_BACKTRACE 全程未设（跑门前后均显式确认）；磁盘门禁时 27Gi（>15Gi 线）；
  门禁亲跑非转录（fmt/clippy×2/libtests/guards 五门全部本机执行，日志归档）；
  QA 窗纯门禁，与真机窗不同窗；未改产品代码/buglist/roadmap/台账；红证复核全部
  离线（无编辑器进程启动）。
- QA 归档：`loop/reports/t25t1qa_{gates_fmt,gates_clippy_ws,gates_clippy_phys,
  gates_libtests,guards}.log`（5 件）。
- 引用的程序侧归档（未改动）：`t25t1_{ltr1_red,ltr2_red,probe_tray_click}.log`、
  `t25t1_gates_*.log`、`loop/t25-live/*`（42 件）、`loop/qa/t25-{red,probe,probe3}.sh`。

## 九、PASS/FAIL 条件核对

| 条件 | 判定 |
|---|---|
| diff 面=预期 59 文件、save/停止语义红线、buglist/roadmap/台账零触碰 | ✅ |
| 两窄口源码级亲读 + 14 单测亲跑逐名 | ✅ |
| 红证真身（构建归属+SHA 离线复算+原始日志对账） | ✅（ltr2 一腿结构破=QA-2，结论不受损） |
| D1-D4 逐项裁 | ✅（D4 归因修正后接受） |
| T2 交接四条可执行性 | ✅（+QA 增补两条） |
| 全量门干净 | ❌ **fmt 红（QA-1）** |

**VERDICT: FAIL（单点阻塞=QA-1；修复路径机械——一行 rustfmt 折行+fmt 重跑归档+
报告门禁表一行修订；实质复核五项全过，修复后 QA 抽验 fmt 一门即放行 T2 真机矩阵轮 13 格）**
