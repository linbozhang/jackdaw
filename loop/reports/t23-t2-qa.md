# T23 任务 2 QA 报告：真机五链矩阵轮验收

> QA 独立复核（2026-11-02）。对象：分支 `loop/t23-material` @ **7e225c02**（fast-forward
> 至 main a058ce58，含 T1 全部建设）；程序报告 `loop/reports/t23-t2-report.md`；运行证据
> `loop/t23-live/`；红证基线 `t23t1_red.log`（T1 归档）+ T1 QA
> `t23-t1-qa.md`。方法=diff 面亲核 + 门禁亲跑（后台+轮询）+ 归档证据逐文件亲读 +
> **M1/M5 两链真机亲跑复现**（QA 重定向证据目录 `loop/t23-live-qa/`，程序证据未动），
> RUST_BACKTRACE 全程未设。QA 归档前缀 `t23t2_qa_*`。
> **裁决：PASS（附 2 条回流，见 §六/§七）——放行 T23-T3 终验+文档轮。**

## 〇、diff 面与纪律核

- `git diff --name-only a058ce58..7e225c02`：28 文件**全部在 `loop/` 下**（2 脚本+1 报告+
  25 归档），产品树/fork/buglist/台账/roadmap **零改动**——「产品零改动轮」声明属实。
- 两脚本均无 `RUST_BACKTRACE` 设置；prep 相日志 `disk: 79Gi free`（门前）；时间线核：
  七相 11:56-12:55 全部结束后门链才开跑（单窗纪律）；本 QA 复核结束已 pkill 编辑器/游戏
  进程（亲证零残留）。

## 一、门禁亲跑（QA 全链复跑，非转录程序日志）

| 门 | 命令 | 结果 | QA 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | EXIT=0，零输出 | `t23t2_qa_gates_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | EXIT=0，全文零 error/warning 行 | `t23t2_qa_gates_clippy_ws.log` |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | EXIT=0，零行 | `t23t2_qa_gates_clippy_phys.log` |
| libtests | `cargo test --workspace --lib`（独立口径） | **3052/3052**（59 个测试二进制求和；与 T1 基线同数） | `t23t2_qa_gates_libtests.log` |
| guards | `cargo nextest run --profile ci -p jackdaw --test guards` | **246/246**（255.8s） | `t23t2_qa_guards.log` |
| stage | `cargo nextest run --profile ci -p jackdaw --test stage` | **572/572**（590.9s） | `t23t2_qa_stage.log` |
| AN2 腿 | `cargo nextest run --profile ci -p jackdaw_runtime --features animation --test animation_scene_load` | **1/1** | `t23t2_qa_an2_scene_load.log` |
| operators 档（QA 增补，见 QD2） | `cargo nextest run --profile ci -p jackdaw --test operators scatter_ops` | **18/18**（含覆盖-散布三件） | `t23t2_qa_scatter.log` |

- 程序侧归档日志（`t23t2_gates_*`/`t23t2_guards.log`/`t23t2_stage.log`/`t23t2_an2_scene_load.log`）
  **全文逐行复核**通过：3052/246/572/1 与报告一致，fmt/clippy 零 error/warning/Diff 行。
- QA 用 `cargo test --workspace --lib` 独立于程序的 nextest 口径复跑得同一总数 3052。
- 八门归档日志全文 grep（`^error|FAILED|Diff after reformat|^warning:`）**全部 0 行**。

## 二、铁证①五链×属性逐格核（抽四格全读+全格证据链对照）

**25/25 腿属实**：六相终轮 PASS 数逐相点验 9（chains）+2（export）+6（broken）+2（rename）
+5（reimport）+1（gamebroken）=25；prep 相无腿（PREP_OK）。

### M1 五链主干（L1）——四格全读，亲跑复现 ✅

| 腿 | 程序证据（亲读） | QA 复跑（`loop/t23-live-qa/`） |
|---|---|---|
| 放置 | console-chains 终轮 `placed mesh parts 6 (want 6)`+props 根带 GltfSource | 同 PASS（parts=6） |
| 换装+PX | map=`{"Rock":"materials/mossy.bsn"}`；健康换装零 warn；PX **2.469%** | 同 PASS；PX **2.467%**；**QA 亲看 before/after 截图**：props 列 Rock×2 变鲜绿（mossy）、TrimC 变青（deep Water 面）、PlainD 无名材质原色不动（MO4 语义活证） |
| 落盘 | L1_DOC_ON_DISK：t23.bsn 含 MaterialOverrides≥2+三路径 | 同 PASS |
| 重开 | 双 map 原样+layered=2/water=1+PX **0.067%** | 同 PASS；PX **0.054%** |
| 导出 | `export_wait` **SHA256 相等**才返回（脚本 :503-522 亲读）；staged 文档含 patch+三材质在树 | （未复跑 export 相；盘面断言链亲读核） |
| staged G 断柄 | `g-holders.json` 亲读：两 holder map 精确回读（props `{Rock:mossy,Trim:deep}`+kit `{Rock:wet}`）；`g-layered.json`=2×`Mesh.Rock`（kit）；`g-water.json`=1×`Mesh.Trim`（props）——「staged 游戏确实穿对」闭合方案事实六缺口 | （未复跑；归档 JSON 与断言逐项吻合） |

### M2 四穿面（L2）——组件换装活证 ✅

console 终轮+脚本断言（:705-741）亲读：props Rock Standard→**Layered（layered=2 且 layered
面在 Water 时清零）**→**Water（water=2）**→回 Standard（water=0）→Trim→Water（water=1）；
kit Rock→Layered（layered=2）。Layered/Water 是 glTF 模型永不自带的组件——在场性即换装
铁证；四穿面柄一致性由 export/gamebroken 两态对照补齐（报告 D1 口径自洽）。

### M3 同名多部件+MO4 拒绝 ✅

- `name=Rock` 一键换装 props **两块** Rock mesh（layered=2/water=2 成对出现）；kit 列不动。
- MO4 真机形态=`cancelled`+警告含可命名清单（归档 `t23t2_mo4_refusal_response.json` 亲读；
  QA 复跑同文）；与 T1 裁定 4-B 及 `t23t1_red.log` 扩大化红证构成红绿对。

### M4 预制体链 ✅

console 终轮+脚本（:816-864）亲读：pack 后 `prefabs/props.bsn` 盘上含
`MaterialOverrides`+mossy+deep（携带）→packed 实例 TrimC 经模型层穿 Water（water=1）→
实例层赢（实例根 `InstanceMaterialOverrides {"Trim":wet.bsn}`、layered=1/water=0）→
双胞胎实例 layered=1/water=1（跟随预制体、不吃第一实例的实例层）。QA 复跑三段全同。

### M7 重导入保留+M13 缩略图 ✅

console-reimport 终轮+脚本（:1169-1199）亲读：props.glb 追加 BoxE→`Reloaded models/props.glb`
重实例化→named=7（8→7 是脚本口径修正=D3④，无名 mesh 本不挂 GltfMaterialName）→**BoxE
经幸存覆盖穿上 Water 面（water=2）**→覆盖 map 原样→缩略图新 FNV-mtime PNG。QA 复跑
broken 相衔接的文档状态与之一致。

### 横切格

- **M11 undo**：kit Trim→mossy→undo→map 单键→全程零 warn→redo 复原（console+脚本
  :743-760）；QA 复跑同 PASS（undo 假报=0）。
- **M10 游戏侧边界**：`gb-*.json`+`staged-broken-run.log` 亲读：破包 named=6/layered=2/
  water=0、零 panicked、游戏 app_info 应答、游戏日志零 `material override:`——
  「报告仅编辑器进程」（决策 1-A）真机成立。

### A11/A5 关联刻画核

- **A11**（buglist:469，rebind 活世界粘性）：覆盖域两面如实刻画——①rename 面：活世界
  粘旧路径已真机归档（`t23t2_rename_sticky.log` 亲读：活 map 拼 deep.bsn+水面 0（give-back）
  +1 条 unresolved warn，重开后文档赢）；②rebind 面：被 MO9 **遮蔽**（rebind 根本改不了
  Map 引用，粘性无从谈起；脚本注释 :1063-1067 与报告 §三口径一致），`t23t2_a11_sticky.log`
  确已删除（ls 亲证），避免与 MO9 证据混淆——处置诚实。buglist 维持原状 ✓。
- **A5**（pie_log 域）：本轮零 PIE 腿（决策 5），A5 不暴露不涉及——无动作正确。

## 三、铁证②结构变化红绿核

### 绿侧（真机，本轮回）——QA 亲跑复现 broken 相 6/6 PASS

| 格 | 程序证据（亲读） | QA 复跑 |
|---|---|---|
| M5 失效路径 | rm wet.bsn→**恰 1 条** `kit overrides 'Rock' with 'materials/wet.bsn', which names no material…`（偏移差分 :953-977）+状态栏嘴同文（walk_has）+audit **四元组**（`t23t2_m5_audit_finding.json` 亲读：component/document/entity/field/kind/reference 六字段精确）+layered 2→0+water 不动+锁不重报 | **同 PASS**：恰 1 条+状态栏+同四元组+give-back |
| M5 恢复自愈/再说一次 | 恢复零新 warn+layered 回 2；再 rm +1 warn | 同 PASS |
| M13 破文件 | 索引拒绝行 ×1+覆盖 unresolved ×1+水面摘除回穿 | 同 PASS（1/1） |
| M8 失效键四态 | `Rock`→`Stone`→恰 1 条 stale 键 warn（**stale 优先口径**活证：值 mossy 可解析仍报键）；kit 不动；同写再写不重报；恢复→water 回 2+零 warn；再改→+1（console+脚本 ：1201-1256） | （未复跑 reimport 相；四态断言链+warn 行原文亲读核） |
| M6 编辑器改名 | 盘上 1 处 `deep2.bsn`+audit 零+重开穿新路径；活世界粘性如实归档（§二 A11①） | （未复跑；证据链亲读核） |
| M9 audit→修复环 | audit 归零+重开穿 wet2+**MO9 红腿**（rebind 后 live map 原地+audit 仍报+状态栏「no longer holds that reference」在场——`t23t2_mo9_rebind_map_red.log`+`qa_mo9_status_walk.json` 亲读，ui_tree 含该文本 ×3） | **同 PASS**：MO9 红证独立复现（`loop/t23-live-qa/qa_mo9_rebind_map_red.log`）+外部改写+重开 audit 归零 |

### 红侧（修前）——逐格对账，发现一处偏差（QD1，§六）

| 格 | 程序报告口径 | QA 对账 |
|---|---|---|
| M5/MO2 | 红=T1 `t23t1_red.log`（audit 零 findings FAILED，main=12c0f9f1 标注） | ✅ 红证在案且为执行型（headless） |
| M6/MO3 | 红=同 log（rewrite 不跟随 FAILED） | ✅ 在案 |
| M3/MO4 | 红=同 log（扩大化探针绿段=陷阱活体） | ✅ 在案 |
| **M8/MO1** | 报告 §二称「修前红证=T1 归档 t23t1_red.log」 | ⚠️ **不成立**：该 log 只有 MO2/MO3/MO4 三红，**无 stale 键零报告的执行型红证**（headless/真机皆无）。T1 报告 §一明言「stale 键的真机红证（M8 修前零报告）留 T2 按『红态先归档』纪律跑」、T1 QA 放行条件 #2 同——**T2 未补跑且偏差清单（§四 D1-D5）未记**。缓解：MO1 报告系统为净新增代码（方案事实八①修前 grep 零报告面=静态红证），真机绿侧四态链是验收词正证。**不阻 PASS**，回流主控裁定（建议 T3 补一腿，§七） |

**「不静默丢」总格**：键失效与路径失效两形态各自「日志+状态栏双嘴各一次、进 audit 四元组、
恢复自动重穿、修复后再说一次」全部真机绿证在案（QA broken 相独立复现），验收句后半句
实质闭环。

## 四、MO9/MO8 新发现复核

### MO9 🟡 rebind 对 Map 引用失效——成立，维持「并 T05 域或 T23-T3 收口」建议

- **源码级亲核**：`src/inspector/missing_list.rs:527` `rewrite_ast_reference` 的 Struct 臂
  只匹配 `BsnValue::String`（:581）与 `BsnValue::List`（:585-594），`BsnValue::Map` 落
  `_ => {}`（:595）——覆盖 materials Map **既不在臂内也无关 MO3 的 force 通路**（后者在
  reference_rewrite 的扫描-重写层，missing_list 按字段直改是第三条独立路径，报告 §三
  机制表述准确）；rebind 拒答语「the document no longer holds that reference」在
  :395。TupleStruct 臂（AR11 先例）只救 newtype 不救 Map。
- **真机活体**：程序红证+QA 独立复现双在案（live map 原地+audit 仍报同一条）。
- **QA 评估**：MO2 落地后覆盖路径「可发现但 rebind 不可修」成半环，与验收句「失效路径
  处理」完整性相悖——**必须收口**，建议 T23-T3 开场小补（`rewrite_ast_reference` 加
  Map 臂 ~15 行+单测，红腿 `M9_REBIND_MAP_BLIND` 应翻绿）或并入 T05 域小任务；两选项
  均零阻塞本裁决。

### MO8 ⚪ 瞬态 stale 告警——成立，口径核可

- **现象复现**：QA 复跑 chains/broken 相同样见到 open/pack/重实例化窗口的 stale 三连后
  自净（如 QA chains 05:57:11 三连、broken 06:00:35+06:00:40 两组三连）；export 相程序
  证据 04:06:04.799+04:06:09.667 两组三连与报告引证一致。
- **偏移差分口径核**：脚本全部 warn 计数走 `mark_log`/`log_lines_since`（:337-353），
  M5/M6/M8/M11 的偏移均在 open 瞬态窗口之后落标——M6 的「+1 unresolved」在归档
  `rename_sticky.log` 中与 2 条前置瞬态可区分（时间戳 04:38:03 vs 04:38:18），M8 的
  「恰 1 条」在 reimport 相 11 条总量中由偏移差分裁出（QA 逐条归因：2 条 M8+9 条 MO8
  瞬态）。「判 warn 次数必须用偏移差分」的报告注意事项（§八-2）经亲核成立。
- **处置**：记档维持；可选收口（延迟一帧再判/book 注记）归 T3 book 章（「打开瞬间的
  stale 告警属生成时序，自清」一句的位置已在方案 T3 书单内）。

## 五、M12 warn 扫描归因复核（逐相亲数）

| 相 | 总数 | QA 逐条归因 | 程序口径 |
|---|---|---|---|
| chains | 19 | 8 RUN_OP INFO（词表点匹配）+1 MO4 拒绝+10 MO8 瞬态（3+2+2+3） | 一致 ✓ |
| export | 6 | 6 MO8 瞬态（两组三连） | 一致 ✓ |
| broken | 16 | 3 unresolved（rm/re-break/M13 各 1）+12 MO8 瞬态+1 索引拒绝 | 一致 ✓ |
| rename | 13 | 12 MO8 瞬态+1 unresolved（M6 预期形态） | 一致 ✓ |
| reimport | 11 | 2 M8 stale（两轮）+9 MO8 瞬态 | 一致 ✓ |
| gamebroken | 0 | 游戏日志零报告（editor-only 设计） | 一致 ✓ |

`UnresolvedTypes|holds no material|cannot-apply|references name files|asset load failed|
panicked` 在全部 editor/game 日志 **0 命中**（QA 亲 grep）。**零意外 warn 成立**。

## 六、偏差裁定

| 偏差 | 事实核 | 裁定/建议 |
|---|---|---|
| 程序 **D1** 可读面收窄（ModelMaterial 无 Reflect、Standard 柄值不可序列化） | 源码亲核：`crates/jackdaw_runtime/src/material_overrides.rs:24` `#[derive(Component, Clone, Debug)]` 无 Reflect；BRP 值反序列化失败与探针口径一致 | **接受**。Layered/Water 组件换装+map 回读+PX+M10 对照四链闭环，验收力不降 |
| 程序 **D2** M9 修复写入走文档外改+重开 | 脚本 :1068-1090 亲读：python 外部改写+reopen+audit 归零+穿 wet2 | **接受**。链路结论成立；修复路真身随 MO9 收口补轮（并 T3） |
| 程序 **D3** 脚本内迭代（chains 5 轮/broken 2 轮/reimport 2 轮等） | 各相首轮 FAIL 均为脚本口径（BRP 实体参/PX 取景/wear_paths 回落/部件计数 8→7/M8 首轮 kit 判定时序），终轮全 PASS 且失败分支有消息；broken 首轮 M5_MISSING_FAIL 无消息输出属早版静默 grep，终轮已全部带消息 | **接受**。无产品行为改动，迭代归档完整（console 全轮在案） |
| 程序 **D4** 散布腿以 headless 兑现 | 方案 L3 确含「散布抽查」；但 **「门禁 stage 全绿含之」引用不实**——scatter_ops 在 `tests/operators/` 档（目标名 operators），T2 门链（guards+stage）不含之 | **QD2（QA 增补）**：D4 实质成立——QA 亲跑 `--test operators scatter_ops`=**18/18**（含 `a_models_material_overrides_follow_it_into_stored_scatter_and_back_out` 等三件，归档 `t23t2_qa_scatter.log`）；程序报告该括注建议 T3 更正一句话 |
| 程序 **D5** Foliage 记档不跑 | 方案 §二 M2 原文「四穿面取三」 | **接受** |
| **QD1（QA 新立）** M8 修前缺执行型红证（§三红侧对账表） | T1 报告/T1 QA 两处明言真机红证归 T2 补；T2 未跑、偏差清单未记 | **不阻 PASS**；回流主控二选一：(a) T3 开场补一腿（checkout main@12c0f9f1 构建，跑 M8 段红证归档后回分支，成本≈一次构建+一腿）；(b) 主控明示裁定「MO1 红证=静态 grep 事实（报告系统净新增代码）」记入台账。QA 建议 (a)，红态纪律闭环 |
| **QD3（QA 增补）** 用户 30 秒清单草稿未随程序报告落档（方案 T2 步骤 4 项） | 程序报告 §八为 QA 注意事项，无清单草稿 | 由本报告 §七补齐，不回流 |

## 七、裁决与放行建议

### 裁决：**PASS**

依据：①门禁 QA 亲跑 7+1 门全绿且与程序归档一致（3052/246/572/1/18，日志全文零行）；
②diff 面亲核产品零改动、纪律（RUST_BACKTRACE/单窗/df/进程清理）全数成立；③铁证①
25/25 逐格证据链亲读核（四格全读：M1 含 staged G 通道归档 JSON+PX 截图亲看、M2/M4/M7
脚本断言+console 双核）；④铁证②真机绿侧全链在案且 **M5 broken 相 QA 亲跑 6/6 独立
复现**（含 MO9 红证复现）；⑤M12 逐相逐条归因吻合、零意外 warn；⑥MO9 源码级+真机
双坐实、MO8 现象与口径双复现；⑦偏差 D1-D5 全部实证成立，QD1/QD2 两条回流均不触
验收标准实质（铁证②红侧的 M8 缺口有静态红证+净新增代码事实兜底，且 T3 本就要复跑
L1/L4/L6）。

### 放行 T23-T3 建议（终验+book 书单交接）：**放行**，带六点注意

1. **QD1 先裁**：M8 修前真机红证按 §六建议 (a) 补跑（并入 T3 开场，与 L1/L4/L6 复跑
   同窗排程），或主控裁定 (b) 记台账——二选一落档后铁证②红侧才算全格闭环；
2. **MO9 收口**：建议 T3 开场小补（`rewrite_ast_reference` 加 `BsnValue::Map` 臂 ~15 行
   +单测；红腿 `M9_REBIND_MAP_BLIND` 应翻绿、M9 修复路真身补一轮）；或按主控裁定并
   T05 域——**不得无声携带进终验**（audit 可发现而 rebind 不可修的半环须有归属）；
3. **终验照方案**：13 格终态复跑+L1/L4/L6 重点腿；warn 判数继续用偏移差分（MO8 口径，
   脚手架已备）；
4. **book 书单**（`material-overrides.md`）按方案 §四-T3 落笔，另加两句：MO8 瞬态自清
   注记、MO9 修复后的 rebind 语义（若 (2) 落在 T3 后则 book 注记「Map 引用 rebind 暂
   走 missing_list 手修」的现状边界）；
5. **程序报告一句话更正**（QD2）：D4 括注「门禁 stage 全绿含之」改为「operators 档
   （QA 亲跑 18/18，`t23t2_qa_scatter.log`）」；
6. **用户 30 秒清单草稿**（补 D3 落档）：①选中模型部件→材质行 Pick 换装→存盘→重开→
   视口仍穿；②`game.export`→staged 游戏里穿同款；③删一个被覆盖引用的材质文件→状态
   栏+日志各一条「material override:」、audit 面出现 Missing 四元组；④文件放回去→
   自动穿回、告警自清；⑤改名 GLB 里的材质名→恰一条「no part of it wears any more」。

## 八、QA 产物清单

- 门禁归档：`t23t2_qa_gates_{fmt,clippy_ws,clippy_phys,libtests}.log`、`t23t2_qa_guards.log`、
  `t23t2_qa_stage.log`、`t23t2_qa_an2_scene_load.log`、`t23t2_qa_scatter.log`（增补档）
- 真机亲跑证据：`loop/t23-live-qa/`（prep/chains/broken 三相 console+editor log+warn
  scan+截图+offset+`qa_mo9_rebind_map_red.log`/`qa_mo9_status_walk.json`——程序证据
  `loop/t23-live/` 未动）
- 变更：仅本报告；产品代码/buglist/台账/roadmap/fork/loop 既有归档零改动
