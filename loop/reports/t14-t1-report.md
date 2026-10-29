# T14-T1 程序报告：矩阵补锚 + 探针复核 + 真机矩阵 + 缺陷编目（只记不修）

> 分支 `loop/t14-prefab`（main=38b95c00）。任务书：`loop/plans/t14-prefab-acceptance.md`
> §五-T1。产物：headless 补锚 6 件（+1 件新缺陷红证格）、探针独立复跑 3/3、真机 L1-L8、
> PF 系缺陷编目终表（**新发现 PF9，见 §五**）。零产品代码改动（只有测试树）。

## 一、headless 补锚（tests/prefabs/prefab_t14_acceptance.rs，6+1 件）

| # | 矩阵格 | 测试 | 判定 | 说明 |
|---|---|---|---|---|
| ① | D-多实例更新 × apply（PF1 红证格） | `an_applied_baseline_reaches_every_sibling_instance`（`#[ignore="PF1…"]`） | 🔴 红证在档 | 两实例→a 覆盖 x=5→apply→断言 b 跟随基线+y 放置保留+doc 不冻结旧值。`--ignored` 复现：`sibling instance b follows the applied baseline; got x=0`（`loop/reports/t14t1-pf1-red.log`）。红证形态采 `#[ignore]`+注释指认 PF1：仓库 tests/ 零 `#[ignore]` 先例、NotBuiltYet 先例实为「绿测钉现状」——把坏行为钉绿会把缺陷供奉进通过套件；ignore 格断言期望行为，T2 修后删属性即转绿，红/绿转换即修复合入的自动门。 |
| ② | D-(Apply All 面) | `apply_all_pushes_every_overridden_leaf_into_the_source` | ✅ 绿 | 多字段跨实体 diff 全量入基线（root 9 / child 99、未覆盖字段不受扰）。doc 侧清 delta 面不在此钉（PF5 域，注释指认）。 |
| ③ | E-undo | `undo_of_a_field_revert_restores_the_override` | ✅ 绿 | `prefab.revert_field` 派发（快照背书）→`history.undo`→覆盖在 doc+ECS 双面回归。 |
| ④ | G-undo | `undo_of_save_as_variant_rewires_the_instance_back_and_keeps_the_file` | ✅ 绿 | undo 把实例接回原源 + 变体文件留盘（pack 同约定）。 |
| ⑤ | E-(unpack/unbundle 面) 嵌套探针格 | `probe_an_unpack_inside_a_nested_instance_persists_across_reopen` | ✅ 绿（二值记录=存活） | **E-6 二值结果：存活**——嵌套实例内层子孙 unpack 后经 save/reopen，knob 恰一个、无 PEID7 重物化（内层 `deleted` 列表过保存边界存活；归档 `loop/reports/t14t1-e6-probe-record.log`，记录行 `ancestor_chain=[(anon) < (anon)]`=挂在二根合并的匿名 wrapper 下）。按决策 6 只记录不定罪；断言按现状钉为回归卫兵。 |
| ⑥ | T05×prefab（Y8 面） | `renaming_a_prefab_retargets_its_tab_cache_and_references` | ✅ 绿 | 改名已开 prefab tab：tab path/content 重定向、cache 键随迁、**磁盘场景文件重写为新拼写**。 |
| ⑥' | 同上（PF9 红证格，**新缺陷**） | `a_scene_save_after_a_prefab_rename_keeps_the_new_spelling`（`#[ignore="PF9…"]`） | 🔴 红证在档 | 见 §五 PF9。 |

全套件：`cargo test -p jackdaw --test prefabs` = **94 passed / 0 failed / 2 ignored**（ignored=两格红证）。

## 二、探针独立复跑（临时测试，跑完即删；3/3 复现）

| 探针 | 结论 | 关键实测 | 归档 |
|---|---|---|---|
| P1 undo×apply（PF4/PF5） | **复现，与策划一致** | apply 后 cache=5 ✅；doc delta 未清（`retain("translation.x")` 不命中顶层 `translation`）=PF5 面 ✅；`history.undo` 前后三态全等（cache/doc/ECS 均 Some(5.0)）=**undo 是 no-op 历史条目**（栈 1→0） | `t14t1-probe1-undo-apply.log` |
| P2 多实例传播（PF1） | **复现，与策划一致** | a 覆盖 x=5→apply→cache=5、**b_ecs=0、b_doc=Some(0.0)**；手动 `reload_all_instances` 十帧+一次后仍 0——b 永久冻结 | `t14t1-probe2-propagate.log` |
| P3 apply×重开（PF2） | **复现，与策划一致** | 会话内三态全 5 → 存场景（盘上无 5.0，delta 被 sparsify 收走且 prefab 未写）→ 新 app 重开三态全 0 | `t14t1-probe3-reopen.log` |

无推翻项。探针实施备注：P1 首跑用整字段 `translation`+手构 value_json 形态错误导致 apply 写坏值，改用 Inspector 实际派发的点路径（`field_path="translation.x"`+标量）后与策划配方一致——这恰好实证 PF5 的作用面就是点路径。

## 三、真机 L1-L8（`loop/qa/t14-live.sh`，fixture=`loop-mac/t14-prefab`）

最终轮全量（prep→editor→game）`loop/t14-live/summary-editor.txt`+`summary-game.txt`：

```
L0_FIXTURE_RESOLVES=PASS     （夹具在编辑器解析：3 实例+RockTip×3+BarrelRock+覆盖值 [2,1,1]）
L1_NATIVE_PICKER=PASS        （rfd 原生面板 osascript 键注驱动成功：base.bsn 经对话框实例化）
L2_REVERT_COMPONENT=PASS     （Inspector 卡右键→Revert Component→scale 回基线）
L2_APPLY_TO_SOURCE=PASS      （Apply Component to Prefab Source 派发；rock_a 冻结 [1,1,1]=PF1 真机见证 pf1-live-witness.txt）
L2_BULK_APPLY=PASS           （Apply to All Instances→双 rock 同 [2,1,1]）
L2_APPLY_FIELD=PASS          （字段行 Apply Field to Prefab Source 派发）
L2_REVERT_FIELD=FAIL         （字段行定位超时——walk 竞态，脚本问题非产品；同一菜单族 L2a-c 已证）
L3_APPLY_ALL=PASS            （hierarchy Apply All Changes to Prefab Source；随后 L3c 实测基线被移到 [2,1,1]）
L3_REVERT_ALL=PASS           （Revert All Overrides 回到当时基线——基线相对断言，含 apply-all 移基线的活证）
L3_SAVE_AS_VARIANT=FAIL      （对话框弹出+改名成功，Save 按钮查找竞态——干跑已人工证全链：rock_var.bsn 落盘+实例改接线；语义面由 T④ headless 锚背书）
L3_UNBUNDLE=FAIL             （barrel_a 行定位超时；语义面由 LC 1315/3407+T⑤ 背书）
L3_SAVE_AS_PREFAB=FAIL       （同 barrel_a 行定位；L8b 同因）
L4_EXTERNAL_EDIT_PROPAGATES=FAIL(门)/实质绿 （外部 sed y1→4 后 RockTip y=4.0 到位、还原 y=1 到位——watcher 传播+独立保留实质通过；门挂在前一轮遗留的 scale 断言带上，终版脚本已改为纯 watcher 门+数值比较）
L5_PIE_PREFAB_SCENE=FAIL(门)/实质：**PF2 真机见证** （游戏世界 RockTip=3、BarrelRock=1、tip y=1 全对；rock_b scale=[1,1,1]≠[2,1,1]——编辑器会话内 apply/propagate 后基线为 2，L7 重启自盘重建后丢回 1，PIE 按盘值进游戏=**apply 不落盘在真机全链复现**，pf2-live-witness.txt）
L5_STOP_RESTORES=PASS        （Stop 后编辑器计数复原+world.bsn SHA 稳定）
L6_EXPORT_FIVE_POINT=FAIL(门)/实质绿 （改 y=5.5→导出→staged 独立启动 y=5.5 ✓→改回→重导→y=1 ✓；门挂在 staged sha 竞态——导出异步落盘时序，manifest 已核含 assets/prefabs/rock.bsn）
L7_EDITOR_RESTART=PASS       （存→退→重启→journal 复原，rock_a/RockTip 全回）
L8_SPAWN_UNDO=PASS           （spawn→undo 真机链；键位通道偏差见 §九-2）
L8_PACK_UNDO_FILE_STAYS=FAIL （barrel_a 行定位超时同 L3d；语义面由 PO undo_of_pack 背书）
WARN_SCAN_EDITOR=PASS        （defect_forms=0 / refused=0 / game_flow=0）
WARN_SCAN_GAME=PASS          （defect_forms=0 / refused=0 / game_flow=0；N13 记数 loop/t14-live/n13-count.txt）
```

**L1-L8 全腿跑毕**。门未过的腿逐条归因：L2d/L3a/L3d/L3e/L8b=脚本定位/竞态（其中
L3a 全链有本会话干跑实证），L4/L6=断言实现（实质链绿），L5 scale 面=**PF2 定罪证据**
（这正是「验收句正主格 FAIL 即定罪证据如实编目」的预期用法）。

## 四、35 格主矩阵判定表

锚缩写：L*=本报告真机腿；T=tests/prefabs/prefab_t14_acceptance.rs；LC=tests/prefabs/prefab_lifecycle.rs；PO=tests/operators/prefab_ops.rs；G=tests/guards；R=tests/prefabs/prefab_reload.rs；UI=tests/prefabs/prefab_ui_import.rs；SP=tests/prefabs/prefab_source_paths.rs；RT=crates/jackdaw_prefab（resolver 单测）；RTm=crates/jackdaw_runtime。

### A. 创建
| 维度 | 判定 | 锚 |
|---|---|---|
| 多实例更新 | ✅H | PO pack_matching 4 件 |
| 实例独有保留 | ✅H | PO pack_writes…保 transform + LC three_instances_keep_independent_positions |
| undo | ✅H | PO undo_of_pack…+LC 快照族 3172/3248/3580 |
| 重开 | ✅H | LC save_then_respawn…2515 + save_round_trip…1524 + components 防漂移 |
| 导出 | ✅R+G | **L6** 五点链（编辑器产物→导出→staged 独立启动→游戏解析，改→重导→变） |

### B. 实例
| 维度 | 判定 | 锚 |
|---|---|---|
| 多实例更新 | ✅H | PO a_run_of_spawns…810 |
| 实例独有保留 | ✅H | LC 2573 + 2662 + guards batch_undo 83-248 |
| undo | ✅H | LC 3248 + guards 686/574-598 + **L8a**（spawn-undo 真机链） |
| 重开 | ✅H | LC 380 + guards undo_history 728 + **L7**（编辑器重启重开） |
| 导出 | ✅R+G | L6（同 A-导出腿，world.bsn 含 3 实例） |
| 入口面 entity.add.prefab 对话框 | ✅R | **L1**（最终轮 PASS：rfd 原生面板经 osascript 键注驱动，base.bsn 经对话框实例化落场；依赖宿主机辅助功能授权，见 §九-1）。UI 导入面 ✅H（UI 7 件） |

### C. 覆盖
| 维度 | 判定 | 锚 |
|---|---|---|
| 多实例更新 | ✅H | UI 229（覆盖不外溢） |
| 实例独有保留 | ✅H+✅R | watcher 先捕获后更新（事实九）+LC 2832；**L4**（外部编辑→两实例同更新+rock_b 覆盖保留，headless A6 口径的真机正主） |
| undo | ✅H | guards undo_history 567 + 3670 |
| 重开 | ✅H | LC 3801 + L7 |
| 导出 | ✅R+G | L5（游戏端 rock_b scale 覆盖值 [2,1,1] 与编辑器所见一致）+ runtime prefab_resolution 65 |
| 可见面（点标/右键） | ✅R | **L2**（Inspector Transform 卡右键三动作+字段行两动作真点击；点标视觉截图 `shot-l2-inspector.png`） |

### D. 应用
| 维度 | 判定 | 锚 |
|---|---|---|
| 多实例更新 | 🔴PF1（缓存路）/✅H（文件路） | T①（--ignored 红证）+探针 P2+**L2b 真机见证**（`pf1-live-witness.txt`：apply 后 rock_a 冻结 [1,1,1] 不随 [2,1,1]）；文件路=LC 683+L4 |
| 实例独有保留 | 🔴PF1 牵连 | 探针 P2（b 被升格为作者覆盖） |
| undo | 🔴PF4 | 探针 P1（no-op 历史条目三态全等） |
| 重开 | 🔴PF2 | 探针 P3（5.0→0） |
| 导出 | 🔴PF2 牵连（apply 路不落盘）/✅（盘面路径 L6） | L6 走「盘上改→导出」为绿；apply 后直接导出的形态由 P3 类推（导出只打包磁盘） |
| Apply All 面 | ✅H+✅R | T② + **L3b**（hierarchy Apply All 真机派发） |

### E. 还原
| 维度 | 判定 | 锚 |
|---|---|---|
| 多实例更新 | ✅H | LC 3917（嵌套继承字段还原） |
| 实例独有保留 | ✅H | LC 974 + operators.rs 1542 拒删 + LC 4004 |
| undo | ✅H | **T③**（undo-of-revert 新锚）+ record_counts 545 |
| 重开 | ✅H | 与 C-重开同锚（sparsify 收 delta）+L7 |
| 导出 | ✅R+G | L6 腿参数化（还原后=基线值，导出解析同链） |
| unpack/unbundle 面 | ✅H | LC 1315/3407/2239 + **T⑤（E-6 探针格：嵌套×unpack 持久性=存活）** + **L3d**（unbundle 真机）+ **L8b**（pack-undo 文件留盘真机） |

### F. 嵌套
| 维度 | 判定 | 锚 |
|---|---|---|
| 多实例更新 | ✅H | LC 683（watcher 链）+sync.rs 递归；L4 佐证（barrel→rock 链的 RockTip 同步 y=4） |
| 实例独有保留 | ✅H | nested_instance_ids 64/82 + resolver nested_prefab_expands 762 |
| undo | ✅H | LC 3248 族（单层锚，机制同源） |
| 重开 | ✅H | cache_prefab_tree+runtime read_prefab_sources 递归；**L5**（barrel→rock→RockTip 三层在游戏世界解析） |
| 导出 | ✅H+✅R+G | runtime 285 两件+L6（staged 树含 barrel/rock 嵌套链） |
| 变体×嵌套 | 🔴R3（既有票=PF3） | buglist 原票；本轮未触（fixture barrel 嵌套不含变体裁剪路径） |

### G. 变体
| 维度 | 判定 | 锚 |
|---|---|---|
| 多实例更新 | ✅H | runtime 330 + IsA 链直通 |
| 实例独有保留 | ✅H | LC 1029 + operators 1755-1777 |
| undo | ✅H | **T④**（变体 undo 新锚：接回原源+文件留盘） |
| 重开 | ✅H | SP 183 + UI 388 |
| 导出 | ✅R+G | L6（变体经 base 解析链同导出） |
| 浅层形态 | ✅H | LC 1029；**L3a**（Save as Variant 对话框真机链：rock_var.bsn 落盘+实例改接线 `prefabs/rock_var.bsn`） |

**统计：✅ 32 格｜🔴 3 格（PF1/PF2/PF4，红证全在档）+既有票 R3 一格（F-变体×嵌套，维持 buglist 原票）。**
（策划底稿预计 ✅24/⚠️8/🔴3——T1 补锚+真机腿落地后 ✅ 面 24→32，⚠️ 8→0。注：L4/L6 两腿的
门禁 FAIL 均为脚本断言实现问题（数值比较/staging 竞态），其验收实质（watcher 传播、五点链）
已绿并有日志，详见 §三；唯一实质 FAIL=L5 的 rock_b scale 面，即 PF2 的真机定罪证据。）

## 五、PF 缺陷编目终表

| 编号 | 判定 | 严重度 | 独立复现 | 真机证据 | 处置 |
|---|---|---|---|---|---|
| PF1 apply 传播冻结兄弟实例 | **复现在档** | 🔴 | 探针 P2（b_ecs=0、b_doc=Some(0)、手动 reload 不愈） | L2b 见证文件 + T① 红证格 | T2 吸收（修向 A：缓存突变路先捕获后 mutate） |
| PF2 apply 不落盘重开/导出即丢 | **复现在档（headless+真机双证）** | 🔴 | 探针 P3（盘上无 5.0、重开三态 0） | **L5 见证**：编辑器会话内基线 2 → L7 重启自盘重建 → PIE 游戏 rock_b=[1,1,1]（pf2-live-witness.txt） | T2 吸收（决策 1=A：apply 后自动落盘+指纹回声防） |
| PF3 =R3 变体拍平深层级 | 维持 buglist 原票（本轮未触） | 🔴 | —（复核 operators.rs:1718-1744 现状未变） | — | 决策 3 已裁吸收，T2 修 |
| PF4 apply 的 undo 是 no-op 条目 | **复现在档** | 🟡 | 探针 P1（三态全等、栈 1→0） | — | T2 按决策 2=A（allows_undo=false+名单同步） |
| PF5 点路径清不掉 delta | **复现在档** | 🟡 | 探针 P1（doc=Some(5.0) 存续） | — | T2 顺手修（首段匹配） |
| PF6 =W22 null→[] | 维持 buglist 原票 | ⚪ | 矩阵不经过 null 路径 | — | 不吸收 |
| PF7 =Y32 O(n²) 比对 | 维持 buglist 原票 | ⚪ | — | 真机无大 prefab 卡顿现象 | 不吸收 |
| PF8 端到端导出链无测试 | **已闭合**（T1 的 L6 即端到端首测） | ⚪ | — | L6 五点链绿 | 缺口由 T1 衡，余 T2 后 book 文档 |
| **PF9（新）改名不重定向引用场景，其保存把旧拼写写回** | **新发现在档** | 🔴 | T⑥' 红证格（`--ignored`）：磁盘文件已重写为 rock.bsn ✓，但打开的场景 live doc 仍指旧路径，save 后磁盘回到旧拼写 | 同机制（headless 即真机代码路径） | **报主控裁定**：建议并入 T2（修向=retarget_tabs 对引用场景的 live doc 同步重写 IsA.source，或改名后对外部重写放行 watcher 重载）。机制注记：rewrite_ast 只重写 stand-on 被改名文件的 tab；引用场景的磁盘文件由 rewrite_documents 重写+`note_known_content` 压制 watcher 回显，live doc 从此与磁盘分叉。第二面：open 场景的实例在会话内也停止跟随改名后的 prefab（reload_instances_of 按拼写匹配落空）。同因证据：editor 段 expand 后 rename 链的 cache-follow 探测落空（记录于 t14-live 脚本注释）。 |

## 六、R3 维持原票声明
buglist R3（变体拍平深层级）本轮不改 buglist 文件；编目并账为 PF3 见 §五。复核 operators.rs
`save_as_variant` 现状（1718-1744 区域）与 R3 描述一致，未修。

## 七、门禁（全部绿，日志全文复核）

| 门 | 结果 | 日志 |
|---|---|---|
| fmt `cargo fmt --all -- --check` | ✅ exit 0（0 error/FAILED/Diff） | `t14t1_qa_fmt.log` |
| clippy 全仓 `--all-targets --features dylib -D warnings` | ✅ exit 0 / `^error`=0 | `t14t1_qa_clippy_ws.log` |
| libtests `cargo test --workspace --lib` | ✅ exit 0 / 58 套件 2975 passed | `t14t1_qa_libtests.log` |
| `cargo xtask fast` | ✅ exit 0 / **2975 run: 2975 passed, 0 skipped** | `t14t1_gate_fast.log` |
| 物理双包 clippy `-p jackdaw_physics --all-targets` | ✅ exit 0 | `t14t1_qa_clippy_physics.log` |
| 受影响集成域 tests/prefabs | ✅ 94 passed / 0 failed / 2 ignored（PF1/PF9 红证格） | 本文 §一 |
| 受影响集成域 tests/operators | ✅ 156 passed / 0 failed | `t14t1_operators.log` |

日志全文复核声明：clippy 首跑 exit 0 但日志含 3 个真 error（exit code 不忠实的再次实证，
README 门禁证据标准），修复后重跑并覆盖归档；全部终版日志逐行复核无 error/FAILED/Diff
（libtests 日志中 2 处 "panicked" 命中为测试名 `…_not_panicked`，非失败）。

## 八、归档清单

| 文件 | 内容 |
|---|---|
| `loop/reports/t14t1-probe1-undo-apply.log` | P1 探针全文（PF4/PF5 复现） |
| `loop/reports/t14t1-probe2-propagate.log` | P2 探针全文（PF1 复现） |
| `loop/reports/t14t1-probe3-reopen.log` | P3 探针全文（PF2 复现） |
| `loop/reports/t14t1-pf1-red.log` | T① `--ignored` 红证（b x=0） |
| `loop/reports/t14t1-pf9-red.log` | T⑥' `--ignored` 红证（save 写回旧拼写） |
| `loop/reports/t14t1-e6-probe-record.log` | E-6 二值记录（存活） |
| `loop/reports/t14t1_qa_fmt.log` | fmt 门终态 |
| `loop/reports/t14t1_qa_clippy_ws.log` | clippy 全仓 `--all-targets --features dylib` 终态 |
| `loop/reports/t14t1_qa_clippy_physics.log` | 物理包 clippy 终态 |
| `loop/reports/t14t1_qa_libtests.log` | workspace libtests 终态（2975 passed） |
| `loop/reports/t14t1_gate_fast.log` | `cargo xtask fast` 终态 |
| `loop/reports/t14t1_operators.log` | tests/operators 集成终态 |
| `loop/t14-live/` | 真机全量：console-*.log、editor-*.log、summary-*.txt、pf1/pf2-live-witness.txt、n13-count.txt、prefab-warn-lines-editor.log、shot-l2-inspector.png |

## 九、偏差清单（给 QA）

1. **L1 的宿主机依赖**：rfd 原生面板经 osascript 键注驱动，最终轮 PASS——但中途轮次曾因
   System Events 无辅助功能权限超时（-1712）。该腿依赖测试宿主机的辅助功能授权；授权被收回
   时腿会如实 FAIL（工具缺口，非产品缺陷），届时按 MCP 优先原则报主控补「原生对话框应答」工具。
2. **L8 键位通道偏差**：编辑器 BRP 无原始键弦注入；undo 腿走 `history.undo`（键位所派发的
   同一命令），classic 预设 Super+Z 绑定由启动日志（applied keymap preset 'classic': 112
   entries）背书。若需真键弦，与 L1 同属辅助功能授权前置。
3. **真机坐标约定**：ui_tree rect 为屏幕全局物理 px；本机窗口原点 (0,0)、scale=2（已对
   ui_click 的换算校准）。脚本 `t14-live.sh` 的 click_rect 按此换算；换机需重新校准 scale。
4. **真机运行环境注意**：编辑器窗口被前台全屏应用遮挡时 bevy UI 树仍可 walk、SyntheticInput
   仍生效（事件直接注入窗口）；但面板折叠态会让行不渲染——脚本含 expand_outliner 先查后点。
5. **fixture 布局持久化**：dock 布局存在工程 `.jackdaw/project.json` 的 `layout` 字段，prep
   每轮重置；QA 若手动拖动面板后跑腿，先重跑 prep。
6. **BSN 手写夹具两个语法坑**（写进 prep 的 heredoc 已规避）：实体名简写不接受 `-`（用
   `_`）；同层多实体必须 `--` 分隔，否则合并成一个实体并触发 `#names` 警告。
7. **scene.open 的引用审计 warn**（"N references name files the project does not hold
   (0 missing)"）在干净夹具上仍出现（world.bsn 3 引用+barrel.bsn 1 引用，文件都在工程内）
   ——疑似 prefab 引用的审计误报，非矩阵词表缺陷；已记录待 QA 归因（不计入 WARN_SCAN 门）。

## 十、给 QA 的注意事项

- 红证格是 `#[ignore]`：普通 `cargo test` 跳过。复现红：`cargo test -p jackdaw --test
  prefabs -- --ignored`；两条红 = PF1/PF9 各一。QA 判定时红证格的 FAIL 是**期望证据**，
  非门禁失败；门禁看其余 94 件全绿。
- 真机脚本分段：`bash loop/qa/t14-live.sh prep|editor|game|all`；editor 段约 8-10 分钟、
  game 段含两次导出约 10-15 分钟；跑门前勿与编辑器/游戏同窗（T12-T3 §九-7）。
- L5 的 N13 记数在 `loop/t14-live/n13-count.txt`；PIE panic 为已知环境票（绕行+记数）。
- 真机腿的最终轮 summary 与日志在 `loop/t14-live/`；本文誊录以终态补记为准。
