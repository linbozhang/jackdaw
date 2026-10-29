# T14 终验 QA 报告：任务 3（收官段）+ T14 整体终验（只验不修）

> 验收对象：分支 `loop/t14-prefab` @ **e6aae40d**（基线 main=c08f800e；T1=e20517ed、
> T2=8f8581f6 在分支史；main 侧合入点=e7fafe4d）。程序报告：`loop/reports/t14-t3-report.md`。
> 前置：T14-T2 QA PASS（`t14-t2-qa.md`，六修复源码级亲读+L6 放行条件亲证+回流③清单）。
> T3 diff 亲核：**34 文件零产品代码**（book 3 + buglist 1 + `loop/qa/` 2 + `loop/reports/`
> 26 + `loop/t14-live/` 终轮证据 9；`git diff --name-status c08f800e..e6aae40d -- src/ crates/
> tests/` = 空）——「零产品代码改动」声明成立。
> QA 手段：**Mac 全量门 9 门亲跑**（串行后台，全程未设 RUST_BACKTRACE，门前 df=143Gi 可用
> >20GB 阈值，门链与编辑器/游戏不同窗——开跑前 `ps` 复核零遗留进程；归档
> `t14t3_qa_*.log` 15 件，脚本 `loop/qa/t14t3-qa-gates.sh`）＋门后定向 6 腿亲跑（bind
> 重跑/A6 隔离/t14 acceptance 12 格/prefabs 全套/operators/guards）；`loop/t14-live/` 终轮
> 证据逐位核对＋**抽 3 格原文全读**（L4 watcher 真机门、L5 PIE=PF2 见证链收口、L6 导出五
> 点链）；六修复源码锚逐一亲读（PF1 watcher.rs:532-558/sync.rs:32,45；PF2 operators.rs:1946-1971；
> PF3 operators.rs:1706-1752；PF4 operators.rs:2475+record_counts.rs:560-563；PF5
> operators.rs:1932/1979；PF9 reference_rewrite.rs:210/510/697）；bevy 原生点击试验轮
> 回退 diff 亲核；book/buglist/SUMMARY 盘上亲读。

## 〇、结论

**PASS（T14-T3 + T14 整体，含 roadmap T14 可勾选建议）**——终轮真机 16/21 PASS 逐位核实
成立（5 个 FAIL 全部复核确认为对话框提交/字段行渲染两个**脚本驱动缺口**，语义面 headless
全锚+真机同族先例，与 T1/T2 终轮定性一致）；35 格终态 34✅+1⚠️（⚠️=真机驱动腿缺口，
缺陷面为零）成立；六修复红转绿指针全部兑现（源码锚+12 格定向亲跑绿+真机活证）；验收句
五条铁证各有独立证据（§五）；「不另起系统」硬约束亲核成立（T2 恰 5 文件+293/−40、零新
文件/零新 plugin，唯一新增=既有 PrefabPlugin 内一个 Resource+次序纪律）。全量门 9 门亲跑
8 绿＋integration 唯一红=A6 件（**QA 独立复现同件同签名 3 试全败＋隔离绿**，定案口径放行）。
**偏差 0 🔴（产品）+0 🟡（阻塞性）+7 ⚪（§七）**——其中需要主控知悉的两条：①终轮 N13
实为 **1 条 panic**（报告记 0——`t14-live.sh` all 模式 warn/N13 扫描 grep 的是陈旧的分相
文件名，**QA 已对真实终轮日志独立复扫：缺陷形态 0 条、panic 1 条被错误处理器捕获、编辑器
存活**，N13 绕行口径实质不变）；②程序 integration 轮含 1 件 nextest 重试自愈的 flaky
（`stage add_component`，TRY1 红→TRY2 绿；QA 轮零 flake）——均不阻塞。

## 一、Mac 全量门亲跑（权威口径）

| # | 门 | 命令 | QA 亲跑结果 | 归档 |
|---|---|---|---|---|
| 1 | 格式 | `cargo fmt --all -- --check` | **CLEAN**（EXIT=0，日志 0 字节） | `t14t3_qa_fmt.log` |
| 2 | Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **CLEAN**（EXIT=0，日志 0 条 error） | `t14t3_qa_clippy_ws.log` |
| 3 | Lint 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **CLEAN**（EXIT=0） | `t14t3_qa_clippy_physics.log` |
| 4 | 单测 | `cargo test --workspace --lib` | **2975 passed / 0 failed**（EXIT=0；**58 套件逐行点数=58**，jackdaw_scaffold 套件 **88 passed**=teaches 88 在册亲读） | `t14t3_qa_libtests.log` |
| 5 | fast | `cargo xtask fast` | **2975 run: 2975 passed, 0 skipped**（EXIT=0，与预期 2975 一致） | `t14t3_qa_gate_fast.log` |
| 6 | **integration** | `cargo xtask integration` | **5394 run：5393 passed，1 failed**（EXIT=1，1425s）——唯一红=`jackdaw::prefabs prefab_lifecycle::prefab_file_change_triggers_reload`，**3 试全败**（14.8/13.9/12.4s），panic 同签名（`watcher reloaded prefab; v2 should be in world. Got ["v1"]`，prefab_lifecycle.rs:714）＝**程序 5393/5394 独立复现且比程序轮更干净（程序轮另有 1 件 flaky 自愈，QA 轮零 flake）** | `t14t3_qa_gate_integration.log` |
| 7 | doctests | `cargo test --workspace --doc --features dylib` | exit=101=jackdaw_bind **DYLD 环境族**（`@rpath/libstd-614bb9b33bbc23af.dylib` 装载失败；T11/T12/T13 同族续目击）→ **bind 单包复跑 EXIT=0** | `t14t3_qa_doctests.log` + `t14t3_qa_doctests_bind_rerun.log` |
| 8 | docs | `cargo doc --workspace --no-deps` | **EXIT=0**（T3 零 Rust diff，无新 warning 面） | `t14t3_qa_docs.log` |
| 9 | scaffold_e2e | `cargo test -p jackdaw --test scaffold_e2e` | **EXIT=0**（1 passed；门含冷编总时长 241s） | `t14t3_qa_scaffold_e2e.log` |

**门后定向亲跑 6 腿**（QA 独立）：

| 腿 | 结果 | 归档 |
|---|---|---|
| A6 件隔离跑 | ✅ **1 passed / 0 failed**（2.36s）——与全套件红构成 T13 定案的「红跟随二进制内并行负载」形态 | `t14t3_qa_a6_isolated.log` |
| t14 acceptance 12 格定向 | ✅ **12 passed / 0 failed**（10.8s）——PF1×2+ApplyAll+undo-of-revert+variant-undo+E-6 探针+rename⑥+PF9⑥‘+PF2+PF3+PF5+深化格全绿 | `t14t3_qa_acceptance_cells.log` |
| `--test prefabs` 全套件 | **100 passed / 1 failed / 0 ignored**——唯一红恰为 A6 件（:714 同签名）；**101 件总数与 T2 勘误口径一致** | `t14t3_qa_prefabs_full.log` |
| `--test operators` | ✅ **156 passed / 0 failed** | `t14t3_qa_operators.log` |
| `--test guards` | ✅ **244 passed / 0 failed**（119.6s；含 record_counts 双名单、undo_history 29） | `t14t3_qa_guards.log` |

**程序归档交叉复核**（`t14t3_*.log` 14 件）：exitcodes 逐门一致（integration EXIT=1 唯一红
A6→`A6_ISO_EXIT=0`、doctests EXIT=101→`DOCTESTS_BIND_RERUN_EXIT=0`、fast 2975/2975、
scaffold 146.23s PASS、docs EXIT=0）——与报告 §五门禁表逐项一致，无隐瞒。

**warn 形态扫描（QA 独立，对真实终轮日志）**：`cannot apply|cannot read|does not read as|
UnresolvedTypes` 扫 `editor-all.log`＝**0**；`game flow:`＝0；`Cannot spawn scene`＝0；
prefab 词 warn 行＝0；staged 两日志＝0。acceptance/prefabs/operators 三份 QA 测试日志同扫
0 条。editor-all.log 实存 WARN 仅两条已知非缺陷形态：keymap classic 预设 10 组和弦冲突
（T1 在档）与 `scene 'world.bsn': 4 references name files the project does not hold
(0 missing)`（T1 §九-7 已记录的 asset.audit 对 prefab 引用误报，不属缺陷词表）。

## 二、终轮真机 16/21 逐位核实＋抽 3 格原文全读

终轮=第 4 轮（`t14t3_live_all4-prog.log`＋`loop/t14-live/{console-all,editor-all,
summary*}.txt`，10-29 22:48-23:10，**开场 PREP_OK=全新 jd new+write_fixtures，第 3 轮
试验数据被 re-prep 隔离**）。`summary.txt` 与报告 §三逐腿一致：**16 PASS（L0、L1、L2 四
动作、L2_APPLY_FIELD、L3b/c、L4、L5×2、L6、L7、L8a、双 WARN_SCAN）/ 5 FAIL（
L2_REVERT_FIELD、L3a/e、L3d、L8b）**。

**抽格一：L4_EXTERNAL_EDIT_PROPAGATES（watcher 真机门——修腿后恢复效力）全文亲读。**
门形亲读（`t14-live.sh` L680-706）：`re_prefab_y` python 原位正则 `y: 1.0 → 4.0`（**替换
计数门 `[ ${n_y:-0} -ge 1 ]`**——PF2 多行展开形下 sed 失配的根因修掉）→ RockTip y=4.0
数值窗门（±0.01）→ 还原 4.0→1.0（第二次数值窗门）。console:30 实测 `RockTip y=4.0`、
`L4_EXTERNAL_EDIT_PROPAGATES_PASS`——双向门全过。机制面：外部编辑 rock.bsn 经 watcher
传播到直接实例与 barrel→rock 嵌套链（RockTip 计数 3=直系 2+嵌套 1，夹具亲读核实）。**裁定：
PASS 成立，PF1 文件路+watcher 修复后真机门恢复。** ⚪ 措辞勘误见 §七-2（「rock_b 授权
覆盖保 [2,1,1]」不准确——实测 rock_b=[2.0,**4.0**,1.0]，此时 rock_b 无存活的 scale 覆盖，
x=2 来自 apply 后的盘上基线、y=4 恰证明**未冻结**；「覆盖保留」面由 L2b 的 rock_a 承载）。

**抽格二：L5_PIE_PREFAB_SCENE（PF2 见证链收口）全文亲读。** 终轮链：editor 段 L2b apply
→PF2 落盘（基线 [2,1,1] 上盘）→game 段**新编辑器进程自盘重建**→PIE 游戏世界
`RockTip=3 BarrelRock=1 rock_b scale=[2.0,1.0,1.0] tip y=1.0`（console:50，门
`[ "$sb" = "[2.0,1.0,1.0]" ]`）。T1 时代同腿游戏读 [1,1,1]（apply 不落盘的红见证，
`pf2-live-witness-t2.txt` 亲读在档：T1 见证链被反转）；归因干净——editor 段 L3c Revert All
已清 rock_b 覆盖，游戏 [2,1,1] 只能来自盘上基线。L5_STOP_RESTORES（Stop 后计数复原+
world.bsn sha 稳定）同 PASS。**裁定：PF2「重开一致」apply 路收口成立。**

**抽格三：L6_EXPORT_FIVE_POINT（导出一致正主格）全文亲读。** 五点：①盘改
`re_prefab_y 1.0→5.5`（计数门）→②`game.export`（`export_prefab_wait` 就绪谓词含
staged rock.bsn sha==本地+manifest 点名）→③staged 独立启动 `RockTip y=5.5`（
`staged-tall.log` 亲读：15:10:19 独立进程 boot 实录）→④还原+重导→⑤staged 复读 1.0
（`staged-restored.log` 15:10:39 第二次独立 boot）。console:55-56 双向数值在案。staged
日志 WARN 全为 scaffold 已知回落形（no config asset/no context binding），零缺陷形态。
**裁定：「改→重导→变」双向闭合，验收句「导出一致」铁证成立。**

其余腿逐位对照（console-all.log 行号）：L0:5（3 实例+RockTip×3+rock_b [2,1,1]）、
L1:43（osascript rc=0，base refs 0→1）、L2a:8-9（Revert Component→[1,1,1]）、
L2b:10-11（**双门：rock_a=[1,1,1] 授权覆盖存活＋rock_b=[2,1,1] 跟随新基线**——PF1 真机
传播+PF5 applied 叶清除双活证）、L2c:12（双 rock 同 [2,1,1]）、L2d/L2_APPLY_FIELD:14-16、
L3b:22/L3c:23（基线相对断言 [2,1,1]）、L7:40（重启后 rock_a=1/RockTip=3=journal 复原）、
L8a:33（spawn-undo refs 0→1→0；classic 预设 112 entries 背书 editor-all.log:22）。

## 三、5 个 FAIL 腿定性复核（裁定：脚本腿，语义面零缺口成立）

| 腿 | 现象（终轮实录） | 归因复核 | headless 锚清单位置（QA 逐一亲验在档） |
|---|---|---|---|
| L2_REVERT_FIELD | 「no translation field row in the Inspector walk」；awk 数值窗门形已修（diff 亲读） | 字段行文本不在 ui walk 可见集（重选 rock_b 后仍不渲染）——T1 §三「定位超时」同族 | `prefab_lifecycle::revert_field_snaps_value_back_to_prefab`:919 + `undo_of_a_field_revert_restores_the_override`（acceptance 12 格亲跑绿）+ guards undo_history:567 |
| L3_SAVE_AS_VARIANT | 「the dialog never closed after the Save answer」——dialog_input 已改 BRP `dialog.answer choice=0` 三试仍不关（diff 亲读） | prefab 保存对话框的 children-slot 形态不经 feathers DialogChoices 主按钮面——对话框提交工具缺口 | acceptance `undo_of_save_as_variant_rewires_the_instance_back_and_keeps_the_file` + lifecycle:1029 族 + SP:183；T1 干跑人工证全链（rock_var.bsn 落盘+实例改接线） |
| L3_SAVE_AS_PREFAB | 同上（同对话框族） | 同上 | PO pack/save_as_prefab 4 件（:120/:170/:247…）+ LC `save_round_trip_preserves_prefab_markers`:1547 |
| L3_UNBUNDLE | 「no row 'barrel_a' or its menu never came up」（rock_b 同函数可开；row_menu 选中先行补丁在 diff 亲读在案） | 行菜单对 barrel_a 行（未选中/嵌套行）的绑定缺口——脚本驱动 | LC `unpack_child_adds_to_deleted_and_creates_standalone_node`:1338 + `unbundle_instance_promotes_inherited_children_to_authored`:2262 + acceptance `probe_an_unpack_inside_a_nested_instance_persists_across_reopen`（E-6 存活，12 格亲跑绿） |
| L8_PACK_UNDO_FILE_STAYS | 同 L3d（barrel_a 行） | 同上 | PO `undo_of_pack_puts_the_group_back_and_leaves_the_file`:170 + guards batch_undo |

**裁定：五腿定性成立。** 依据：①同族先例——T1 终轮/T2 两轮同集合 FAIL（T2 QA §六已勘误
定性「脚本定位/竞态，语义面有 headless 锚，非产品缺陷/非本轮回归」）；②T3 三轮修腿把
**同族可修面全部修净**（L2a 夹具复位、L2b 双门、L2d 数值窗、L4/L6 计数门——四轮趋势
15→15→[试验轮回退]→16，每处修复都有对应腿转绿）；③剩余两个缺口（对话框提交、字段行
渲染）在 T2 QA 回流时已如实留档给工具票，本轮未新发现第三类缺口；④零产品代码 diff，
产品面无回归载体。

## 四、过程性偏差复核：bevy 原生点击试验轮（第 3 轮）

1. **回退彻底性——亲核成立。** `git diff 8f8581f6..e6aae40d -- loop/qa/t14-live.sh` 亲读：
   menu_click/click_text/rclick_text/row_menu 函数体**零 diff**（click_text/rclick_text
   仅作为 T2 既有死帮手定义存留，无调用点）；T3 对腿的全部改动=re_prefab_y 帮手+计数门
   ×4、write_fixtures 提取+editor 段开场复位、L2b 双门+等待加长、L2d awk 窗、L2d 前重选、
   dialog_input→dialog.answer、row_menu 选中先行、L5 见证块删除——与报告 §二/§八清单逐项
   吻合，无第 3 轮 click_text/rclick_text 调用残留。
2. **当轮数据隔离——亲核成立。** 第 3 轮 prog 日志（all3）确认大面积回归（UI 菜单腿 6 腿
   全挂+L5 连带 FAIL=基线被上轮残留 [3,1,1] 污染）；终轮 console 首行 `PREP_OK`+`jd-new.log`
   （22:48 全新 `jd new`）+`game-warmbuild.log`（2m11s 冷编）=终轮从零重建夹具，试验轮
   [3,1,1] 残留被清场，终轮数据不受染。
3. ⚪ 记档：第 3 轮 prog 日志在 L6 头部截断（无 VERDICT 行），试验轮全量判定不可从归档
   复数——轮已被回退+终轮覆盖，实质影响零（见 §七-3 趋势线勘误）。

## 五、QA 放行清单对照（全任务）

| 条目 | 裁定 |
|---|---|
| T1/T2/T3 验收全绿 | T1=矩阵 35 格全判定+探针 3/3+L1-L8 全跑+四门绿（`t14-t1-report.md`；T1 无独立 QA 报告，其验收由 T2 QA 一并承担＝合并验收先例）；T2 QA PASS（五门亲跑+六修复源码级亲读+L6 放行亲证，`t14-t2-qa.md`）；T3=本轮（§一/§二） |
| **铁证①改 Prefab 多实例更新** | PF1 格 headless 双证（acceptance `an_applied_baseline_reaches_every_sibling_instance`+真 watcher 交互件，12 格亲跑绿）＋真机 **L2b**（applied 实例 rock_b 跟随 [2,1,1]）＋**L4**（外部编辑双向传播 4.0→1.0）✅ |
| **铁证②实例独有保留** | **L2b 的 rock_a 面**（授权覆盖 [1,1,1] 穿越 apply+传播存活）＋PF5 格（兄弟叶保留，亲跑绿）＋L4 的 x=2 存续 ✅ |
| **铁证③undo 一致** | T03 面=record_counts 双名单+undo_history 29（guards 244 亲跑绿）＋**PF4 语义定案披露**（apply `allows_undo=false`，Unity 同语义；book+T2/T3 报告三处披露在案；对 apply 的撤销预期按新语义提票）＋undo-of-revert/variant-undo/spawn-undo 锚全绿+L8a 真机 ✅ |
| **铁证④重开一致** | **L5**（apply→盘→新编辑器→PIE=[2,1,1]）＋**L7**（编辑器重启 journal 复原）＋headless PF2 格（存→全新 app 重开）＋LC 重开族 ✅ |
| **铁证⑤导出一致** | **L6 五点链双向**（§二抽格三）＋runtime 解析同源件 ✅ |
| 「不另起系统」硬约束 | **亲核成立**：全分支产品面=T2 恰 5 文件（src/prefab/{mod,operators,sync,watcher}.rs+reference_rewrite.rs，+293/−40 亲数）；零新文件/零新 crate/零新 plugin/零新 SystemSet——唯一新增注册=既有 PrefabPlugin 内 `init_resource::<StagedSparseCapture>`（即裁定修向 A 预定的「watcher 次序纪律提为共用前置」）；T3 零产品 diff |
| buglist R3/W23 打钩核对 | 均 `- [x]`＋注记「已修 8f8581f6（T14-T2，并账 PF3/PF5）」＋红绿证测试名逐字在案（buglist.md:30-33/:402-405 亲读）；T2 对 buglist 零改动（打钩留 T3 的纪律声明与 diff 一致） |
| 三纪律 | 无 RUST_BACKTRACE（QA 脚本 unset＋全程零 backtrace 输出——editor-all.log:45 的 note 行为 bevy panic 模板原文，非设置）；warn 扫描 0 缺陷形态（§一，QA 对真实日志独立复扫）；N13 记数在案（**勘误：终轮实为 1 条**，§七-1）；门前 df=143Gi；门链独窗；结束零残留进程 |

## 六、book 新章核对（方案 §五-T3-2 书单）

`book/src/user-guide/prefabs.md`（205 行，e6aae40d 新增）逐项亲读：

| 书单项 | 落点 | 判 |
|---|---|---|
| 七环节工作流速览 | 「seven moves: pack, instantiate, override, apply, revert, nest, and variant」+Packing/Instantiating/Overriding/Applying/Reverting/Nesting/Variants 七节 | ✅ |
| apply 新语义披露 | 「**Apply writes the prefab file immediately**」+「Apply is **not undoable**…file-level write」+.bak 退路+Apply All 一次落盘 vs Inspector 逐字段 | ✅ |
| 变体嵌套修复后语义 | 「nested levels stay nested at their own depth…nested instances inside the cut keep their own references」（PF3 后语义） | ✅ |
| 导出链 | 「The baseline on disk is what a fresh export ships — apply before exporting」+staged assets 树+越界拒绝+坏文档 warn 点名 | ✅ |
| 记账三注记 | ①Packing「One known edge」段=overwrite staging 缺席；②Applying「five-field component writes five times」=Inspector 逐叶落盘；③Variants「Two narrow gaps remain by design」=folder tail+canonical 拼写（PF9 残余） | ✅ |
| watcher 防冻结语义（PF1 面） | §External edits「compares against the *old* baseline…not mistaken for an authored override and frozen」 | ✅ |
| SUMMARY/交叉引用 | SUMMARY.md:21「[Prefabs](user-guide/prefabs.md)」；scene-management.md:19-20 拾取对话框句挂链「(see [Prefabs](prefabs.md))」亲读；prefabs.md 内链 bsn-format/scene-management 两处 | ✅ |
| Common gotchas | 五条（含「Applied and then regretted it. No undo for apply」）——用户视角陷阱面 | ✅ |

## 七、偏差与记档分级（QA 视角，全部 ⚪ 不阻塞）

| # | 项 | 处置 |
|---|---|---|
| 1 | **终轮 N13 实为 1 条（报告记 0）＋t14-live.sh all 模式扫描路径缺陷**：脚本 :799-803/:898-903 硬编码 grep `editor-editor.log`/`editor-game.log`，而 all 模式实写 `editor-all.log`——终轮官方 WARN_SCAN/N13 数字出自 20:50 陈旧分相文件（n13-count.txt 5 条命中亦是更早轮的 `>>` 残留）。**QA 对真实终轮日志独立复扫：缺陷形态 0/`game flow:` 0/`Cannot spawn scene` 0/prefab warn 0——WARN_SCAN 实质 PASS 成立**；唯一 panic=editor-all.log:43-46（`drain_game_events` swap_remove，被 bevy 错误处理器捕获，随后 pie.stop/game.export 正常执行=编辑器存活），N13 绕行+记数口径实质不变 | 报告勘误（N13 终轮=1）；**建议工具票补一条**：all 模式扫描改 `editor-$PHASE.log`（与五 FAIL 腿工具票同批）；账面 N13 累计数以 T11-T3 的 57 条+各轮实录为准 |
| 2 | L4 报告措辞「rock_b 授权覆盖保 [2,1,1]」不准确：实测 [2.0,**4.0**,1.0]（x=2=盘上基线、y=4=跟随，恰证未冻结）；终轮该点 rock_b 无存活 scale 覆盖（L3c 已清），「覆盖保留」面由 L2b rock_a 承载——腿门本身诚实（「only the watcher face gates here」） | 报告勘误项；矩阵 C-保持格的 headless 锚不受扰 |
| 3 | 报告 §三趋势线「第 2/4 轮 16」有误：归档亲数**第 2 轮=15 PASS/6 FAIL**（L2b 当时未修）；「第 3 轮 12」不可复数（all3 prog 日志截断无 VERDICT 行）；第 1 轮 15、终轮 16 与归档一致 | 报告勘误项；趋势实质（修腿单调转绿）不变 |
| 4 | 程序 integration 轮含 1 件 nextest 重试自愈 flaky（`stage add_component::add_component_is_offered_on_the_view_the_inspector_opens_on` TRY1 FAIL→TRY2 PASS，报告未提）；QA 轮同门**零 flake**——stage 域与 T14 零交集（T3 零产品 diff） | 记 flake 台账；不阻塞 |
| 5 | `pf1-live-witness.txt` 标签残留 T1 冻结时代语义（`L2b_PF1_WITNESS rock_a=[1.0,1.0,1.0]`——现值含义=授权覆盖存活，非冻结见证）；日志行文案已按 T2 QA §六-4 清理，唯独见证文件名/标签未随改 | 记档（与 #1 同批工具票顺手改）；log 行双值已如实入 console |
| 6 | doctests bind DYLD 环境族又一次目击（T11/T12/T13 续族；bind 单包复跑 PASS） | 已知环境账延续 |
| 7 | 35 格表引用的 lifecycle 行号漂移 ~20-30 行（T2 在该文件加测所致；锚名全部亲验在档，如 LC 1315→1338、2239→2262、2515→2538） | 记档；锚可寻址性不受影响 |

## 八、最终裁决与 roadmap 建议

- **T14-T3 验收标准（方案 §五-T3）**：35 格终态复跑+六格红转绿确认 ✅（§二/§五）；L1-L8
  全腿复跑 ✅（终轮 16/21，5 FAIL 定性成立）；book 章节书单 ✅（§六）；buglist R3/W23 打钩
  ✅（§五）；台账/roadmap 未动（diff 亲核=主控合入时写）✅；全量门+A6 口径注记 ✅（§一）。
- **T14 整体（T1/T2/T3）**：T1 交付矩阵+探针+红证编目（PF 系 9 条）、T2 六修复红→绿
  （QA 源码级亲读+放行条件 L6 亲证）、T3=本轮；验收句五维铁证全数独立在案（§五）；
  「不另起系统」约束全程成立；缺陷面收口——🔴 3（PF1/PF2/PF3）全修、🟡 2（PF4 语义定案/
  PF5）全修、PF9 新增 🔴 修、W22/Y32 维持不吸收、PF8 导出缺口由 L6 闭合。
- **VERDICT: PASS——T14 整体闭环。roadmap T14（第 28 行）建议可勾选**，闭环注记建议含：
  验收句铁证独立在案（L2b/L4/L5/L6/L7 五链+12 格 headless）；六修复红转绿（PF1-PF5+PF9，
  buglist R3/W23 打钩）；integration 5393/5394 唯一红=A6（QA 独立复现同签名+隔离绿，定案
  口径）；真机 16/21（5 FAIL=对话框/字段行两工具缺口，headless 全锚）；N13 终轮 1 条绕行
  记数（QA 勘误）；⚪ 偏差七项+两条工具票建议（t14-live.sh all 模式扫描路径、对话框/行
  定位驱动）不阻塞。
- 主控合入路径照旧 `--no-ff`（e6aae40d 单提交）；台账 T14 行、roadmap 勾选由主控合入时写
  （本轮 QA diff 零产品/台账触碰，亲核成立）。

## 九、用户 30 秒清单（book 章落地为可执行手测）

1. **打包与实例**：`jd new my-game`→编辑器打开→选中几个实体→右键 **Save Selection as
   Prefab...**→命名→选区变实例；再右键空处 **entity.add.prefab** 拾取同一文件→第二个实例。
   拖动各自位置互不影响。
2. **覆盖与应用**：改其中一台 rock 的 scale（字段点变实心）→右键 **Apply Component to
   Prefab Source**：另一台**立刻跟随**新基线，本台自己的覆盖保留；打开
   `assets/prefabs/rock.bsn`——**新基线已写盘**（Apply 即保存，无撤销；.bak 存旧内容）。
3. **还原**：右键被改字段→**Revert Field**→回落基线；hierarchy 右键 **Revert All
   Overrides** 一键清空本实例覆盖。
4. **外部编辑**：用任意编辑器改 rock.bsn 的 y 值保存→编辑器 ~0.15s 后所有实例跟随；
   实例上的覆盖不被误冻。
5. **重开与导出**：Ctrl+S→关 tab→重开：一切如初；**Play**：游戏世界与编辑器所见同源；
   `game.export` 后双击导出产物：改过的基线在独立游戏里生效。

## QA 会话产物索引

- 门禁 9 门：`loop/reports/t14t3_qa_{fmt,clippy_ws,clippy_physics,libtests,gate_fast,
  gate_integration,doctests,doctests_bind_rerun,docs,scaffold_e2e}.log`；脚本
  `loop/qa/t14t3-qa-gates.sh`（串行 9 门，unset RUST_BACKTRACE）。
- 定向 6 腿：`t14t3_qa_{a6_isolated,acceptance_cells,prefabs_full,operators,guards}.log`
  ＋bind 重跑（同上）。
- 核验对象：`loop/t14-live/` 终轮 23 件（console/editor-all 全文+summary 三件+staged 双
  日志+pf1/pf2 见证+n13-count）；四轮 prog 日志（t14t3_live_all{,2,3,4}-prog.log）；
  `loop/qa/t14-live.sh` 终版全文+`git diff 8f8581f6..e6aae40d` 逐行；T1/T2 报告与 QA +
  红证五件；六修复源码锚（watcher.rs/sync.rs/operators.rs/record_counts.rs/
  reference_rewrite.rs）；tests/prefabs 三文件+tests/operators/prefab_ops.rs+guards 锚名
  清单；book 3 文件+buglist R3/W23；roadmap/progress 未动核。
- 进程收尾：QA 复查零 jackdaw/t14-prefab/nextest 残留进程；数据卷余 143Gi；门链与编辑器
  未同窗；工作树除 QA 归档新增（t14t3_qa_*.log 15 件+本报告+门链脚本）外零触碰。
