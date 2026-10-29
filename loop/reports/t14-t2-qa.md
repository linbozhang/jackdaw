# T14-T2 终验 QA：修复吸收轮（PF1/PF2/PF3/PF4/PF5/PF9）

> 验收对象：分支 `loop/t14-prefab` @ **8f8581f6**；程序报告 `loop/reports/t14-t2-report.md`。
> 依据：任务书 `loop/plans/t14-prefab-acceptance.md` §五-T2+§六（主控裁定：6 决策点全按建议
> ＋PF9 新增吸收，台账 T14 方案行）；T1 报告/红证；`loop/README.md` 契约；T03 纪律先例。
> QA 手段：五门亲跑＋源码级亲读六修复＋全部关键格亲跑＋真机证据逐位核。全程未设
> RUST_BACKTRACE；门前 df=167GB 可用（>20GB 阈值）；门链与编辑器/游戏不同窗；结束无残留进程。

## 一、裁决

**PASS——放行 T14-T3（终验+文档）。** 六修复全部源码亲读＋亲跑绿；放行条件 L6 五点链
真机 PASS 亲核成立；L4 失败定案（腿前提被 PF2 修复打破）论证成立且 T3 修腿义务在档；
A6/thumbnail/脚本腿三处回归面全部归因成立。报告 4 处勘误+脚本腿 2 个新发现见 §六（均非
产品缺陷、不阻放行，随 T3 修腿清单带走）。

## 二、门禁（QA 亲跑，日志全文复核）

| 门 | 命令 | 结果 | 日志（QA 亲跑覆盖归档） |
|---|---|---|---|
| 1 | `cargo fmt --all -- --check` | ✅ EXIT=0，全文 0 error/FAILED/Diff | `t14t2_qa_fmt.log` |
| 2 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | ✅ EXIT=0，全文 0 命中 | `t14t2_qa_clippy_ws.log` |
| 3 | 物理双包 `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings`（T13 终验同款，强于程序单包口径） | ✅ EXIT=0，全文 0 命中 | `t14t2_qa_clippy_physics.log` |
| 4 | `cargo test --workspace --lib` | ✅ EXIT=0；58 套件 **2975 passed / 0 failed**；scaffold 套件 **88**=teaches 88 在册（fast 日志逐行点数） | `t14t2_qa_libtests.log` |
| 5 | `cargo xtask fast` | ✅ EXIT=0；**2975 run: 2975 passed, 0 skipped** | `t14t2_qa_fast.log` |

注：任务书预期「fast 2975+新增」——实际 2975 与 T13 持平，**正确**：T2 全部新增面是
integration 级（tests/prefabs/operators/guards），lib 层零新增，程序报告口径一致。

| 集成面（亲跑） | 结果 | 日志 |
|---|---|---|
| `--test prefabs` 全套件 | **100 passed / 1 failed**＝唯一红恰为 A6 件 `prefab_lifecycle::prefab_file_change_triggers_reload`（签名 `Got ["v1"]`:714，与已定案环境票同签名）；**0 ignored**（T1 两格红证已入常规套件） | `t14t2_qa_prefabs_full.log` |
| A6 件隔离跑 ×3 | ✅ ×3 EXIT=0 | `t14t2_qa_a6_isolated_{1,2,3}.log` |
| `--test operators` | ✅ **156 passed / 0 failed** | `t14t2_qa_operators.log` |
| `--test guards` | ✅ **244 passed / 0 failed**（含 undo_history **29/29**、record_counts 双名单 2/2） | `t14t2_qa_guards.log` |
| 九格定向亲跑 | ✅ **9 passed / 0 failed**（§三全部格子） | `t14t2_qa_cells.log` |

warn 形态扫描（prefabs 套件日志）：`cannot apply|cannot read|does not read as|UnresolvedTypes`
**零命中**；prefab 词表 warn 5 条逐条归因为负路径测试的预期产物（watcher 保旧副本 ×2、
revert_component 拒删、revert_all 部分还原、.jsn 遗留重定向拒读）。

## 三、六修复逐条复核（源码亲读＋亲跑）

**PF1（apply/propagate 传播冻结兄弟实例）——✅ 修复成立。**
- 三语义亲读（`src/prefab/watcher.rs:531-559`）：`StagedSparseCapture` ＋ `stage_sparse_capture`
  **stage-if-empty**（同帧第二次 mutate 不得按自己的新基线重捕，注释与实现一致）；
  `take_reload_basis` **take-or-capture**（无 staged 时回落现捕＝watcher 原语义）；
  `drop_staged_capture` **丢弃**。`reload_all_instances` 全部经 `take_reload_basis`（:563）。
- callers 全量清点（grep 全仓）逐一对齐：①`sync.rs` 驱动器——epoch 无变化**先丢弃**（:32，
  防未落地 mutate 的陈旧捕获泄漏），有变化 reload 消费后**再丢弃**（:45，「必消费或丢弃」成
  立）；②`apply_to_prefab_source_inner`——**cached 预检(:1905)→清 delta→stage(:1946)→
  mutate(:1953)**，mutate 前置 stage 成立，失败路径（`!cached`）在 stage 之前返回（无陈旧
  staged 遗留）；③`propagate_instance_to_prefab`——stage(:849) 在 cache 写/fingerprint 之前；
  ④无缓存突变的 reload callers（revert_field/component/all、unbundle、respawn_with_instance、
  bulk_apply_in_scene、placement_migration）＝take 回落现捕即正确，与程序偏差清单 §四-6 一致；
  ⑤`pack_matching`(:835)/`save_scene_as_prefab` 的 cache insert 无 staging——程序已披露
  （overwrite 撞既有实例为既有边缘行为、无红证格），QA 认可不入 T2 面，**建议 T3 book 记
  一笔**（边缘场景语义）。
- 亲跑：T1 格 `an_applied_baseline_reaches_every_sibling_instance` 绿（九格跑）；深化格
  `an_external_edit_after_an_apply_still_reaches_every_instance` 绿（apply 后外部再改、含 y=2
  placement 兄弟双跟随）；真 watcher 交互格
  `an_external_edit_after_an_apply_lands_through_the_real_watcher` 绿（真 notify+debounce 链，
  指纹不吞外部写）。红证在档（`t14t1-pf1-red.log`＋`t14t2-t1-cells-red.log`＋
  `t14t2-new-cells-red.log` 件 4）。

**PF2（apply 不落盘重开/导出即丢）——✅ 修复成立（决策 1=A 如裁落地）。**
- 源码：`apply_to_prefab_source` 尾部 `persist=true`→`save_prefab_to_disk`（:1971）；
  `save_prefab_to_disk`＝write_atomic(:2163)＋`compute_file_fingerprint`＋
  `record_saved_fingerprint`(:2165-2168)（回声抑制，drain_changes :278-289 指纹跳过消费）。
  **Apply All 一次落盘**：`apply_all_overrides_to_source` 逐叶 `inner(persist=false)`
  (:2108-2116)＋循环后单次 save(:2122)，裁定原文兑现。
- lifecycle:1230 反向重钉亲读：测试改名 `apply_to_source_lands_the_new_baseline_on_disk`
  （:1230），盘上读回断言＋指纹登记断言（:1306-1316 起）——「apply 后盘上=新基线」按裁定
  重钉，绿（九格跑）。
- 亲跑：`an_applied_baseline_survives_a_scene_save_and_reopen` 绿（存场景→全新 app 重开→
  盘上基线 5.0＋重开世界 x=5）。真机：`pf2-live-witness-t2.txt`（apply 后盘上 rock.bsn 即带
  基线 [2,1,1] 多行形，经 L7 重启存活——T1 见证链反转）亲核在档。
- **Inspector 逐字段=N 次小盘写（偏差 4）QA 裁定建议：可接受，T3 记账不修码。** 亲读
  `prefab_menu.rs:205-242` 确认逐叶派发 `prefab.apply_to_source`（每叶 persist=true）。理由：
  裁定「一次落盘」文本针对 `apply_all_overrides_to_source`（已兑现）；Inspector 路径每叶均
  原子写＋各自登记指纹（回声安全）；同帧 N 连发由 stage-if-empty 只捕第一次（正确基线）、
  驱动器下一帧一次 reload；中间态各自是合法基线（崩溃窗口无损坏）。副作用仅 IO 放大与
  「半组件落盘」中间态（合法），记 book 即可。

**PF3（=buglist R3 变体拍平深层级）——✅ 修复成立（决策 3 吸收兑现）。**
- 源码亲读（`operators.rs:1706-1826`）：Descendant 结构携**同 id**（变体经 IsA 继承原件 id
  空间）、**`ast_parent_of` 映射**挂回各自父节点的对应体（:1785-1792，fallback 变体根）＝
  buglist 修复方向原文逐字落地；内嵌 IsA＋deleted 保留（:1743-1748→:1778-1779）；变体根
  `IsA(原件,deleted)`+PEID(0) 不变。
- 亲跑：`a_variant_keeps_the_nested_levels_of_the_instance_it_was_cut_from` 绿——nested(5) 挂
  root(0)、knob(7) 挂 nested(5)、nested 仍指 inner.bsn、**隔离新 app** 实例化变体经保留的内
  嵌 IsA 物化 knob=1。红证在档（`t14t2-new-cells-red.log` 件 2）。

**PF4（apply 的 undo 是 no-op 条目）——✅ 修复成立（决策 2=A 兑现）。**
- 源码：`prefab.apply_to_source` 声明 `allows_undo = false`（operators.rs:2475）；record_counts
  双名单亲读：`SELF_PUSHING` 收入（:563，名单注释扩写「file-level write no snapshot can roll
  back (PF2/PF4)」）、`SNAPSHOT_BACKED` 已无此条。**键位设置面核查**：`src/keybind_settings.rs`
  全文零 `prefab.*`/undo 声明耦合——无需同步（唯二名单即 record_counts 双清单）。
- 亲跑：guards 244 绿含 `self_pushing_operators_declare_undo_transparent`＋
  `snapshot_backed_operators_keep_allows_undo`＋undo_history 29/29；红证在档
  （`t14t2-pf4-red.log`：修前名单测试红）。
- **语义变更披露核对**：报告 §五-3 明示「apply 现在不可撤销（Unity 同语义）；对 apply 的撤销
  预期需按新语义提票」——口径成立。名单 assert 文案对 apply 略不贴切（说 pushes its own
  entry）以名单内注释澄清＝偏差 5，认可。

**PF5（点路径清不掉 delta）——✅ 修复成立；实施细化裁定：接受（优于裁定原文）。**
- 裁定原文「先按 `.` 取首段再 retain」；实施为**叶移除＋空剪枝**（`remove_delta_leaf`
  operators.rs:1979-2002：逐段下钻删叶、空父结构剪枝、叶级空则除组件 patch）。QA 复核裁定
  意图＝「点路径清得掉且不伤兄弟覆盖」：首段 retain 在复合 delta 上会把未 apply 的兄弟叶整
  体丢掉（程序偏差 1 之例成立），**比现状更差**；叶移除达成意图且无回归——等同或强于裁定，
  接受。
- 时序安全性亲读：顺序＝cached 预检(:1905)→清 delta(:1922-1940)→stage(:1946)→mutate——
  **清除先于捕获**（否则驱动器 reload 从捕获复活已清的叶）；`!cached` 失败路径挡在清除之前
  （无「清了 delta 基线未动」丢失窗口）；`!applied` 分支实际不可达（预检已保证缓存存在）。
  认可偏差 2。
- 亲跑：`an_applied_leaf_clears_its_own_delta_and_keeps_the_sibling_one` 绿——reload 前 delta
  仅余 {y:3}、兄弟覆盖存活；reload 后 doc+ECS 双面 x=5（新基线）/y=3（authored）。红证在档
  （`t14t2-new-cells-red.log` 件 3）。

**PF9（改名不重定向引用场景，保存写回旧拼写）——✅ 修复成立（主控新增吸收兑现）。**
- 源码亲读（`src/reference_rewrite.rs`）：`follow_a_move` 在 sweep moves **追加绝对→绝对
  `Spelled` 对**（:506-513，第二因＝live doc IsA 装载时绝对化，索引相对对零命中）；`replacement`
  的 `Spelled` 臂＝全等匹配（:210-214）。覆盖面亲读：`rewrite_referencing_documents`（:697）
  扫 active 场景 tab 的 live `SceneBsnAst`＋非 active tab 的 stash 快照（prefab tab 的 live doc
  归 cache、已由 retarget_tabs 重写——范围切分正确）；touched tabs 干净基线随重写重算
  （:527-529→`recompute_clean_baselines`，与 stand-on tab 同待遇）；folder move 的绝对拼写由
  `Names{folder:true}` 的 folder_tail 臂覆盖。残余观察（不阻）：`Spelled` 臂不处理 folder tail，
  依赖 Names 臂前缀对齐；canonical 拼写分歧（macOS /var symlink 族）理论上有缝隙——现测
  未踩，T3 book 可提一句。
- 亲跑：T1 ⑥' `a_scene_save_after_a_prefab_rename_keeps_the_new_spelling` 绿（红证
  `t14t1-pf9-red.log`＋`t14t2-t1-cells-red.log` 在档）；T1 ⑥
  `renaming_a_prefab_retargets_its_tab_cache_and_references` 回归绿。

## 四、L6 放行条件亲证＋L4 定案复核

- **L6_EXPORT_FIVE_POINT=PASS 亲核成立**：`loop/t14-live/summary-game.txt`（终轮 20:15）四门
  全 PASS；`console-game.log:8-10` 亲读——staged RockTip y=5.5（sed 改盘→game.export→staged
  独立启动）✓、还原+重导后 1.0 ✓（双向）；脚本门为数值窗（`awk -v a="$staged_tip2"` ≥0.99
  ≤1.01）＋staged sha==本地＋manifest 点名三重，修复形态亲读在案。**放行条件满足。**
- **L4 失败定案复核：成立，产品无辜。** 证据链：①腿内 `grep -q "y: 4.0"` 自证 sed 未落盘
  （l4=false 在 grep 处即置）；②`console-editor.log:29` RockTip y=1.0（外部编辑根本没发生）；
  ③`pf2-live-witness-t2.txt` 亲证 PF2 后 rock.bsn 盘上为多行展开形（单行 sed 模式失配），
  T1 单行夹具时代同腿实质绿；④产品面反证亲跑绿＝真 watcher 交互格（真实 notify 链）。
  「腿前提被 PF2 打破」论证接受。**T3 修腿义务在档两处**（t14-t2-report.md §三＋
  pf2-live-witness-t2.txt：sed 改多行容忍）。
- 附带亲证（程序未主张，QA 补记）：editor 第二轮 `L2b` 实测 rock_a=[2.0,1.0,1.0] 随 apply
  基线——**PF1 真机传播活证**（该行括号内「frozen」为 T1 时代脚本残留文案，值本身已反转；
  见 §六勘误）。

## 五、回归面

1. **A6 口径执行亲证**：全套件并发跑唯一红＝A6 件（`Got ["v1"]`），隔离跑 ×3 绿（亲跑）；
  与 T13 终验定案（环境票、🔴 已立项、磁盘高压家族）处置一致。放行不受阻，T3 终验沿用
  「全套件红+隔离绿」口径注记。
2. **thumbnail flake ×2 定性**：本轮 QA 亲跑 libtests **零 thumbnail 失败**（含涉事件
  `a_subject_whose_models_have_all_failed_is_written_off ... ok`）；程序 ×2 发生在其满载并行
  libtests。归因环境负载成立：T2 产品 diff 恰 5 文件（src/prefab/{mod,operators,sync,watcher}.rs
  ＋reference_rewrite.rs，亲核 `git diff e20517ed..8f8581f6 --stat`＝+293/−40 与报告一致），
  与 thumbnail/asset 域零交集。
3. **脚本腿三处修复效力评估（亲证）**：实测 BSD awk 对坏形态 `awk -v a "$x"` 输出
  `awk: invalid -v option argument: a`、命令替换为空 → `[ "" = "y" ]` 恒假——**坏数字门只会
  强制 FAIL，从不制造假 PASS**。据此：修复前**不存在**依赖坏门的历史 PASS；L3c（REVERT_ALL，
  字符串等值门 `[ "$rb" = "$base_scale" ]`）与 L3e（SAVE_AS_PREFAB，对话框布尔门）**不经
  awk 数字门**，其历史 PASS/FAIL 判定效力不受脚本修复影响——**无需 T3 复跑**（L3e 本身的
  FAIL 是另一独立的 UI 行定位问题，T1 已归因）。修复受益者＝L4/L5/L6 三腿的门（T2 终轮已
  在修复后脚本下重跑：L5/L6 PASS、L4 因上述腿前提 FAIL）。
4. **T13 防线回归指认**：undo 面（record_counts 双名单/undo_history 29）✅亲跑绿；T05 引用
  面（rename retarget ⑥＋PF9 ⑥'）✅亲跑绿；T07 导出面（L6 五点链）✅真机 PASS；T13 flow 面
  （WARN_SCAN_GAME=PASS、flow/warn 词表零命中）✅真机 PASS。

## 六、报告勘误与脚本腿新发现（QA 提出，随 T3 带走；均非产品缺陷）

1. **prefabs 件数**：报告 §二「99 passed（100 件）」→实际套件 **101 件**（100 绿＋A6 件全套
  并发红；commit message「prefabs 101 (99+A6 isolated)」为准）。
2. **editor 第二轮 L2_REVERT_COMPONENT FAIL 归因修正**：非「UI 行定位/竞态」——菜单确已
  点击并执行（`L2a: Revert Component ran`），读回 [2,1,1] 恰为**上一轮 apply 后的盘上基线**
  （该轮未重跑 prep、夹具带基线 [2,1,1] 进场，腿门硬编码 [1,1,1] 恒失配）＝**腿前提类**（与
  L4 同族）。产品面：同二进制第一轮同腿 PASS（[1,1,1]，fresh prep）＋lifecycle 锚亲跑绿。
  T3 修腿：分段前强制 prep 或门改基线相对。
3. **L2_REVERT_FIELD FAIL 归因修正**：菜单已执行、revert 实际生效（`rock_b y=0.0 (baseline
  0)`）——门为裸字符串 `[ "$py" = "0" ]` 而 BRP 返回 "0.0"→恒假。与已修的 L6 裸字符串门同
  族、**漏修一处**。T3 修腿：数值窗。
4. **脚本残留文案**：L2b 日志行括号内「PF1 witness: frozen at [1.0,1.0,1.0] instead of
  following…」为 T1 硬编码叙述，T2 实测值已随修复反转（第二轮 [2.0,1.0,1.0]=跟随）。T3 清
  理该文案，防误读。报告 §三「与 T1 终轮同集合」措辞据此两处修正（REVERT_COMPONENT 不在
  T1 FAIL 集内）。
5. T3 book 建议记账（非义务）：pack_matching/save_scene_as_prefab overwrite 边缘的 staging
  缺席（§三 PF1⑤）；Inspector 批量 apply 合并落盘（偏差 4）；PF9 Spelled 臂 folder/canonical
  残余缝隙（§三 PF9）。

## 七、归档清单（QA 亲跑产物）

`t14t2_qa_fmt.log`｜`t14t2_qa_clippy_ws.log`｜`t14t2_qa_clippy_physics.log`｜
`t14t2_qa_libtests.log`｜`t14t2_qa_fast.log`｜`t14t2_qa_prefabs_full.log`｜
`t14t2_qa_a6_isolated_{1,2,3}.log`｜`t14t2_qa_operators.log`｜`t14t2_qa_guards.log`｜
`t14t2_qa_cells.log`（均在 `loop/reports/`；程序原同名门禁日志保留为 `*-prog.log` 后缀）。

## 八、给主控的回流清单

1. **裁决 PASS**，建议 `--no-ff` 合入并派 **T14-T3**（终验+文档）。
2. T3 必办（程序/QA 已对齐）：①L4 sed 多行容忍；②L2d 门数值窗＋L2a 分段前 prep（§六-2/3）；
  ③35 格终态复跑＋L1-L8 全腿（editor 腿修复后重跑拿全 PASS 集）；④book/buglist（R3/W23
  打钩）/台账/roadmap；⑤A6 口径注记沿用。
3. T3 建议记账：§六-5 三项＋报告勘误 §六-1/4。
4. 报告勘误四项（§六）建议主控落（同 T13 先例：QA 提出、主控落）。
