# T25 任务 1 报告：窄口建设+红证归档轮（LT2 live 路由补齐 + LT1 结构类入账 + LT-R1/R2 红证 + 6(a) 可达性探）

> 分支 `loop/t25-live-tuning`（自 main 050b4813，含 T25 方案）；方案
> `loop/plans/t25-live-tuning.md` §四-T1；七决策点主控已全部按建议裁定
> （1(a)/2(a)/3(a)/4(a)/5(a)/6(a)/7(a)）——本轮落地 2(a)+4(a)，探针验证 6(a)。
> 红态先行纪律遵守：`t25t1_ltr1_red.log` / `t25t1_ltr2_red.log` 修前归档
> （2026-11-03，预 T1 构建 = main 050b4813 的 target/debug/jackdaw——其唯一
> 前置 commit 为 docs-only 方案文件，二进制亲证与 HEAD 树一致；红窗独立，
> 红窗内零 cargo 命令）。RUST_BACKTRACE 全程未设；构建前磁盘 46Gi/30Gi 均 >15Gi 线。

## 〇、红证两件（修前归档，纪律遵守）

| 腿 | 归档 | 现场与断言（全文见档） |
|---|---|---|
| **LT-R1（LT2 三重静默）** | `t25t1_ltr1_red.log` + `loop/t25-live/{editor-red.log,ltr1-component-set-response.json,ltr1-game-transform.json,t25-red.bsn.before,t25-red.bsn.after-document,console-red.log}` | fixture `t25-live`（jd new + jackdaw_remote 注入，游戏 BRP 15702），场景 `assets/t25-red.bsn`（#Spinner + SceneNodeId(7001) + Transform{y:1.0}）；PIE Play #1 connected → Live 视图 → `scene_tree` 取投影 Spinner（bits 4294962901）→ **一次 `component.set translation.y=2.5`** → 文档 SHA `134099b4…→aebf28f3…`（diff 即 `y: 1.0→2.5` 一处）而**游戏侧 Transform.translation=[0.0,1.0,0.0] 纹丝不动**、**`jackdaw/pie` live_edits=0**、盘文件 SHA 恒等、undo 深度 0→1（静默 authored 的 undo 项在案）；operator 自答 "finished" 无 warning——三重静默 + 一个自信的哑巴，全链在档。 |
| **LT-R2（LT3/N11 活体复认）** | `t25t1_ltr2_red.log` + `loop/t25-live/{ltr2-inputs.json,ltr2-candidates.txt,ltr2-input-response-*.json}` | 同窗：Inspector 卡片在屏（投影 Spinner 选中），`ui_input` 打 '2.5'+Enter-commit **六行数值行**（x>1050/y>150 依序）→ 每行后 `live_edits=0` 恒值、游戏 y 恒 1.0、文档与 R1 后恒等——**零提交**，N11 票面证据在本构建刷新（纯归档腿，零修复预期，与方案一致）。 |

> 红窗 census：error-handler panics=0、swap_remove=0（本窗 N13 未发作，记档不进判据）。
> 红窗脚本 `loop/qa/t25-red.sh`（prep/red 两相，A6 五纪律+A9 重试窗+勿设 RUST_BACKTRACE 全随）。

## 一、两窄口逐项状态

### 1. LT2 修复（决策 2(a)）— ✅ 落地，remote_ops 6 单测

- **落点**：`src/remote_ops.rs` 抽出两个 apply 函数，各在 authored 路径**前置**一次
  `try_route_pie_live_field_edit`（src/inspector/reflect_fields.rs:2081，与 Inspector 七入口
  同一双条件：资源实体排除→Live 态→投影反查 bits）：
  - `apply_component_set`（component.set 主体）：路由命中即 return，跳过
    `field_edit_commit_on`——流送+记账，文档零触碰；未命中（Scene 态/非投影/资源实体）
    行为与修前逐字节一致（同 warn 文案形态）。
  - `apply_computed_transform`（entity.set_transform 主体）：算得 `new_transform` 后
    `TypedReflectSerializer` 全组件 JSON + `field_path=""` 路由（`set_field_in_component_json`
    空路径=整组件替换，亲证 component_json.rs:251-254）；命中即 return（不推 SetTransform
    命令、不进 history——下一帧投影增量把预览实体带齐）；未命中走既有 SetTransform+sync_component_to_ast。
- **语义对齐**：与 Inspector 面完全同条件同形态——Scene 态零变化（单测钉死），Scene 态
  ephemeral 的「field write skipped」warn 分支原样（warn 在既有 SetBsnField execute，
  本轮零触碰；单测钉 ledger/文档/行为三面）。
- **单测**（`src/remote_ops.rs` tests，6 名）：Live component.set→记账+文档恒等+无 undo 项 /
  Scene component.set→AST 写入+恰一条 undo+无记账 / Scene ephemeral→skipped warn 形态
  （无记账、无文档、pushed no-op 命令如前）/ **Live ephemeral→记账 node_id=None**
  （注入面对运行时实体同样成立）/ Live set_transform→整组件 entry（field_path=""、
  live JSON 带新 x、文档恒等）/ Scene set_transform→authored 命令原样（ECS+AST+undo 一条）。

### 2. LT1 最小入账（决策 4(a)）— ✅ 落地，live_edits 6 单测+tray 2 单测

- **落点**：
  - `src/live_edits.rs`：新 `LiveEditKind { Field, ComponentAdded, ComponentRemoved }`
    （entry 增 `kind` 位）；新 `record_live_structural_edit`（`field_path=""` 结构类 entry：
    baseline=authored 整组件 JSON（文档有 patch 时），remove 且文档无 patch 时回落
    pre-removal 预览序列化值（显示用，托盘行诚实显「刚没了什么」）；label 既有
    `{name} / {short_type}` 形）；同键更新/zone 热重载 re-key 与 record_live_edit 同款
    （re-key 收窄到 field_path 为空的结构类条目，不劫持字段条目）。
  - **Save 半边**：`build_save_command` 顶部分支——ComponentRemoved→
    `RemoveProjectComponent::from_world`（撤 AST patch，undo 自带快照恢复）；added 沿既有
    整组件分支（组件未 authored→全组件一次性落，N14 口径天然满足）。运行态-only remove
    （文档从未持有）在 `save_entry_to_scene`/`apply_all_to_scene` 两调用点**静默结账**
    （无需 authoring，不计 stale）。
  - **Tray 行态**：`src/live_edits_ui.rs` `tray_row_state(resolves, kind)`——结构类行
    **Save 照常可用、Revert 禁用置灰**（stale 仍全禁）；tray/StopPrompt 两条 rebuild 调用点
    传入 `entry.kind`。
  - **ops.rs**：`component.add`/`component.remove` Live 分支流送前各记一笔结构类 entry
    （added 带 default JSON、removed 带 Null——托盘行形 `{baseline} -> null`）。
  - **Revert 对结构类禁用**后，`revert_entry` 的「永远 warn」行不再可能出现（结构性 Revert
    无 UI 入口）；既有 revert 语义零触碰。
- **单测**（live_edits.rs 6 名）：结构 add→entry 形+整组件 Save 落 patch+undo 一条 /
  结构 remove→baseline=authored JSON+Save=patch drop+undo 一条 / 运行态-only remove→
  静默结账零 authoring / apply_all 混合账（字段+add+运行态-only remove）→一条 undo 组全落 /
  同键 re-edit 不重复 / 字段条目与结构条目同 type 邻存不互斥。tray 2 名：结构行 Save 可用
  +Revert 禁用 / stale 结构行全禁。

### 3. 红绿对锚（修后同现场，供 T2 复用）

`component.set` 修后即注入面（决策 2(a) 原文兑现）：**探针三窗全部亲证
INJECTION=PASS**——`selection.set`（scene_tree bits）+`component.set` 一发即入账
（live_edits=1），文档只在显式 Save/Apply 后变化，游戏 BRP 值随流送变化
（`t25t1_probe_tray_click.log` 逐条在档）。T2 矩阵 A 系触发腿零新增工具面。

## 二、tray/弹窗 ui_click 可达性探（决策 6(a) 前提，三窗）— ✅ 可达成立（badge 单点例外）

归档 `t25t1_probe_tray_click.log`；脚本 `loop/qa/t25-probe.sh`（v1+v2）+`loop/qa/t25-probe3.sh`。

| 按钮 | 判定 | 证据 |
|---|---|---|
| StopPrompt 三键 | **三键全通（end to end）** | Apply All：click→文档 authored（134099…→6c31e7…）→计 0→弹窗关；Discard：click→计 0→文档字节恒等→undo 深度不变；Review：click→弹窗关→托盘开带行（handoff） |
| tray footer Apply All | **通（end to end）** | click→文档 authored（6c31e7…→fa0be35…）→计 0 |
| tray 行 Save | **通（end to end）** | click→文档 authored（6c31e7…→2750fda…）→undo +1→计 0 |
| tray 行 Revert | **通（end to end）** | click→计 0→编辑器实体回 baseline（本窗游戏已停，流送半边空读——腿设计注记，ControlEvent 无游戏时安静丢弃为既有语义） |
| tray 行/diff cell 走查 | **通** | 行 label `Spinner / Transform.translation.y`、`3.0 -> 4.0` cell、Save/Revert（kind=button）、tooltip 文本均在 ui_tree walk |
| **badge chip** | ** locating 通，开托盘不通（LT 候选）** | '1 edit' walk 在案、click clicked:true（target=badge button）但**托盘不 spawn**——合成点击的 picking 未达 badge（嫌疑：badge 点位上方覆盖节点或 `hidden()` prop 的 picking 排除）。**非 6(a) 阻塞**：托盘开行路线=stop→Review（即 C4 链本体，零产品改动） |

- **给 T2 的路线**：B 系托盘腿=play→注入→stop→`ui_click Review`→托盘在屏逐条 triage；
  行钮解析用 `t25-probe{,3}.sh` 的**祖先爬升版 button_bits_in_row**（tray 行 label 外包一层
  flex-grown holder，C3 单层 parent 解析不够——v3 踩过、已修）；click_text 歧义（弹窗行
  'Discard' vs 按键 'Discard'）用 click_label 的 kind=button 候选回落。
- **v1 教训在档**：开窗先清「Recovered Work」模态（v1 带着上一窗红证 kill 留下的恢复弹窗
  跑完全程——其 scrim 吞掉全部 badge/tray 点击而 GlobalZ-210 的 prompt 按键照常落地；
  该现象本身反证 prompt 键在模态之上可达）。两脚本 boot 均已带清场步。
- census：v1 panics=4/swap_remove=5；v2 3/3；v3 5/7（N13 族归因，判据不含）。

## 三、门禁（全绿，日志归档）

| 门 | 命令 | 结果 | 归档日志 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | EXIT=0 零 Diff | （行内过） |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | EXIT=0，零 warning/error（首跑 1 处 needless_borrow 修后过） | `t25t1_gates_clippy_ws.log` |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | EXIT=0，零行 | `t25t1_gates_clippy_phys.log` |
| libtests | `cargo test --workspace --lib` | **3087/3087**（记录基线 3073，净 +14=本轮新测逐名，见 §四） | `t25t1_gates_libtests.log` |
| guards | `cargo test -p jackdaw --test guards` | **248/248**（基线 248，持平，166s） | `t25t1_guards.log` |

> 名字集对附注（对 `t24t1_gates_libtests.log` comm diff=17 名）：其中 3 名非本轮
> （`live_edits::revert_without_a_live_counterpart_keeps_the_entry`、
> `live_edits_ui::badge_label_pluralizes`、`terrain/scene_io` 各 1——HEAD 已在、
> t24t1 归档未含的 lineage 漂移，t24 报告 §五同款噪声），且总数对账 3073+14=3087
> 恰为本轮 14 名（漂移名与既有改名/移出互抵）。

## 四、偏差清单（分级如实）

- **D1（探针次序）**：任务书开场序为「R1→R2→可达性探→建设」，可达性探实际落在
  **修后窗**（探针三窗之一为 v1 修后构建）：修前构建无合成注入面（N11 活体复认即
  LT-R2 本身），托盘/弹窗的行与键**需要真实 entry 才会存在**——badge/托盘在计 0 时
  根本不渲染，预探无从谈起。探针改骑 LT2 修复的注入面（决策 2(a) 的直接兑现），
  时序偏差零成本、结论等价。另 v1 窗带「Recovered Work」模态跑完（红窗 kill 恢复弹窗
  未清）——其发现（scrim 吞点击而 prompt 不吞）反成数据点，v2 起清场纪律入脚本。
- **D2（脚本迭代，非产品）**：v1 探针托盘行 label 针写错（authored 编辑器名 vs 投影
  实体名——**投影实体 Name 游戏侧为 'Spinner'**，先例 t06 的 Find-EntityBits 同名即可）
  +恢复模态干扰；v3 首跑 row 解析失败=托盘行结构比 C3 先例深一层（label 外包 holder），
  解析器改祖先爬升后全通。均为脚本面修正，红档 verdict 以实文件离线复核为准。
- **D3（测试设计修正）**：`scene_mode_ephemeral_writes_stay_skipped_with_no_ledger`
  首版钉「无 undo 项」——与活体不符：`field_edit_commit_on` 对 skipped 写**照推 no-op
  命令**（warn+push 为既有形态）。修测试钉实貌（无记账+无文档+一条 pushed 命令），
  非修系统。另 `P3_ROW_REVERT_STREAMED_BASELINE` 腿在**停窗后**读游戏 BRP——游戏已死
  空读，腿设计误；Revert 的对账半边（计 0+编辑器实体回 baseline）已证，流送半边属
  停后无游戏语义（ControlEvent 安静丢弃），T2 若需真机流送断言应在 play 窗内做 Revert。
- **D4（红窗读空窗）**：`LTR2_DOCUMENT_STABLE` 在窗判 FAIL——R2 腿前的 scene_bsn 读
  撞忙窗返回空（A9 类）；离线复核：R2 后文档 SHA `aebf28f3…` 与 R1 后**完全一致**
  （打字腿零改动），红档 verdict 以离线复核为准（t24 D2 口径）。红档已如实双记。

## 五、新增单测逐名（3087 = 记录基线 3073 + 净 14）

| 域 | 名 | 钉什么 |
|---|---|---|
| remote_ops | live_component_set_tracks_the_edit_and_leaves_the_document | LT2：Live component.set→记账（键/live/baseline/label）+文档恒等+零 undo 项 |
| remote_ops | scene_mode_component_set_authors_the_document_and_skips_the_ledger | LT2：Scene 态零变化（AST 写入+一条 undo+无记账） |
| remote_ops | scene_mode_ephemeral_writes_stay_skipped_with_no_ledger | LT2：ephemeral warn 形态保持（D3 实貌版） |
| remote_ops | live_ephemeral_component_set_tracks_without_a_document | LT2：注入面对运行时实体成立（node_id=None） |
| remote_ops | live_set_transform_routes_the_whole_component_into_the_ledger | LT2：set_transform 整组件路由（field_path=""、文档恒等） |
| remote_ops | scene_mode_set_transform_keeps_the_authored_command | LT2：set_transform Scene 态零变化 |
| live_edits | a_structural_add_records_a_whole_component_entry_and_saves_the_patch | LT1：add entry 形+整组件 Save 落 patch |
| live_edits | a_structural_remove_records_the_baseline_and_saves_as_a_patch_drop | LT1：remove baseline=authored+Save=patch drop+undo |
| live_edits | a_runtime_only_removal_settles_without_authoring_anything | LT1：运行态-only remove 静默结账 |
| live_edits | apply_all_lands_structural_and_field_entries_in_one_group | LT1：混合账一条 undo 组 |
| live_edits | a_structural_re_edit_updates_one_entry_without_duplicating | LT1：同键 re-edit 不重复 |
| live_edits | a_field_edit_and_a_structural_edit_on_one_type_stay_separate | LT1：字段/结构条目同 type 邻存 |
| live_edits_ui | structural_rows_keep_save_and_disable_revert | LT1：结构行 Save 可用+Revert 禁用（决策 4(a) 行态） |
| live_edits_ui | stale_structural_rows_disable_everything | LT1：stale 结构行全禁 |

## 六、给 T2/QA 的注意事项

1. **注入面**：`selection.set`（scene_tree bits）+`component.set`（entity/type_path/field/value）
   即 live edit 产生腿——探针三窗 INJECTION 全 PASS；entry 同键再编辑=单条更新（A2 半边
   headless 已钉）。
2. **托盘开行路线**：stop→`ui_click Review`（badge click 为 LT 候选勿依赖）；托盘行钮/
   footer/diff cell/tooltip 全 walk 可达；行钮解析用 `t25-probe{,3}.sh` 的祖先爬升版
   `button_bits_in_row`（行 label 外包 holder 层）。
3. **结构类行（A4 腿）**：add 入账行形 `Player / Health`+`(not authored) -> {default}`、
   remove 行形 `{json} -> null`；**行上 Revert 置灰**（按钮 variant=Disabled，walk 仍带
   文本）；运行态-only remove 的 Save/Apply 静默结账不 warn。
4. **Revert 流送断言须在 play 窗内做**（停后无游戏，ControlEvent 安静丢弃——B2 格注意）。
5. **warn 形态**：`component.set` 修后 Live 命中**零 warn**（流送+记账）；Scene 未命中
   命中 `field_edit_commit_on` 既有 warn 形态不变。M12 扫描面无新增形态。
6. **投影实体 Name**=游戏侧名（'Spinner'），scene_tree/ui_tree/托盘 label 三处同名，
   腿内按名取 bits 与 t06 先例一致。
7. **红→绿对照**：红档 `t25t1_ltr1_red.log`；绿半边=探针窗口的 INJECTION+Save/Apply
   authored+计增链（`t25t1_probe_tray_click.log`），同现场可复跑（命令在两脚本头注）。

## 七、产物清单

- 分支 `loop/t25-live-tuning`：6 文件改动（`src/{remote_ops,live_edits,live_edits_ui}.rs`、
  `src/inspector/ops.rs`、`src/pie_projection.rs`、`src/remote/server.rs`——后两者仅
  测试构造补 `kind` 位）
- 新脚本：`loop/qa/t25-red.sh`（红窗，prep/red 两相）、`loop/qa/t25-probe.sh`（可达性
  v1/v2）、`loop/qa/t25-probe3.sh`（行钮窗）
- 归档：`loop/reports/t25t1_{ltr1_red,ltr2_red,probe_tray_click}.log` +
  `t25t1_gates_{clippy_ws,clippy_phys,libtests,guards}.log`
- 证据目录 `loop/t25-live/`（红窗+三探针窗的 walk/响应/census 全档，24M）
- 未动：save/停止语义（红线——`revert_preview`/`open_stop_prompt_if_dirty`/save 隔离
  零触碰，仅既有 explicit gates 上验证）；buglist/roadmap/台账（主控职权）；N11/N13/
  A7/A9/A10/A14（纪律不前置）；fork；协议；场景格式
