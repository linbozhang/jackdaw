# T14-T2 程序报告：修复吸收轮（PF1/PF2/PF3/PF4/PF5/PF9 六修复合入）

> 分支 `loop/t14-prefab`（main=38b95c00 已并，T1=e20517ed 在分支上）。任务书：
> `loop/plans/t14-prefab-acceptance.md` §五-T2+§六决策 1/2/3 裁定（全按建议+新增 PF9）。
> 本轮为「红→绿」轮：六个缺陷各自红证在档（T1 预置 PF1/PF9 格+本轮新增四格红证）→
> 修→绿；T1 两格 `#[ignore]` 删除即进常规套件。产品改动 5 文件 +293/-40，测试 3 文件。

## 一、六修复逐个红绿证据

| 修复 | 红证（修前） | 绿证（修后） | 改动落点 |
|---|---|---|---|
| **PF1** apply/propagate 传播冻结兄弟实例 | T1 格 `an_applied_baseline_reaches_every_sibling_instance`（`--ignored` 复红，`loop/reports/t14t1-pf1-red.log`）；深化格红 `t14t2-new-cells-red.log`（第 4 件） | 两格常规跑绿（`t14t2-six-green.log` 件 1/件 6）；全套件 99 passed | `src/prefab/watcher.rs`：新 `StagedSparseCapture` 资源+`stage_sparse_capture`（stage-if-empty）/`take_reload_basis`/`drop_staged_capture`；`reload_all_instances` 改取 basis；`drain_changes` 逐文件 stage/take（保留 in-frame 已 stage 的 apply 捕获）。`src/prefab/sync.rs`：驱动器 reload 消费 staged，未 reload 或无变化时**一律丢弃** staged（防陈旧捕获泄漏进无关 reload）。`src/prefab/operators.rs`：`apply_to_prefab_source` 与 `propagate_instance_to_prefab` mutate 前置 stage |
| **PF2** apply 不落盘重开/导出即丢 | 新格红 `an_applied_baseline_survives_a_scene_save_and_reopen`（`t14t2-new-cells-red.log` 件 1）；探针 P3+真机见证 `loop/t14-live/pf2-live-witness.txt` | 同格绿；lifecycle:1230 反向重钉为 `apply_to_source_lands_the_new_baseline_on_disk`（盘上=新基线+指纹登记防回声），绿 | `apply_to_prefab_source` 尾部 `save_prefab_to_disk`（write_atomic+`record_saved_fingerprint`，回声抑制机制现成）；**Apply All 一次落盘**：`apply_all_overrides_to_source` 逐叶 inner(persist=false)+循环后单次 save |
| **PF3**（=buglist R3）save_as_variant 拍平深层级 | 新格红 `a_variant_keeps_the_nested_levels_of_the_instance_it_was_cut_from`（`t14t2-new-cells-red.log` 件 2：nested 挂根、内嵌 IsA 丢失） | 同格绿：变体文档 nested(5) 挂 root(0)、knob(7) 挂 nested(5)、内嵌 IsA 保留（诊断所见变体文件形状逐字吻合）；隔离新 app 实例化变体物化 knob（经保留的内嵌 IsA 解析） | `save_as_variant` 按 buglist 修复方向重建：子孙以**同 id**（变体经 IsA 继承原件 id 空间）建节点，`ast_parent_of` 映射挂回各自父节点的对应体；内嵌实例节点保留自身 `IsA{source,deleted}` |
| **PF4** apply 的 undo 是 no-op 条目 | `t14t2-pf4-red.log`：guards `self_pushing_operators_declare_undo_transparent` 红（声明仍 true） | guards 全量 244 绿（两名单测试均绿） | `prefab.apply_to_source` 声明 `allows_undo = false`；`record_counts.rs` 从 `SNAPSHOT_BACKED` 移除、入 `SELF_PUSHING`（名单 doc 扩注文件级不可撤销语义） |
| **PF5** 点路径清不掉 delta | 新格红 `an_applied_leaf_clears_its_own_delta_and_keeps_the_sibling_one`（`t14t2-new-cells-red.log` 件 3） | 同格绿：apply 后（reload 前）translation delta 仅余 {y:3}（x 已除）；reload 后 x=基线 5、y=3 保留（ECS+doc 双面） | delta 清除改为**叶移除**（`remove_delta_leaf`：按 `.` 逐段下钻删叶、空父结构剪枝、叶级空则除组件 patch）；且**清除先于捕获**（capture 在 mutate 前、clear 在 capture 前——否则 reload 从捕获复活已清的叶；失败路径有 cached 预检挡在清除之前，无数据丢失窗口） |
| **PF9** 改名不重定向引用场景，保存写回旧拼写 | T1 格 `a_scene_save_after_a_prefab_rename_keeps_the_new_spelling`（`--ignored` 复红，`t14t1-pf9-red.log`） | 同格常规跑绿；T1 ⑥（tab/cache/磁盘面）保持绿 | `src/reference_rewrite.rs` `follow_a_move` 新增 `rewrite_referencing_documents`：**引用**（非 stand-on）改名文件的场景 tab 内存文档同步重写——active tab 的 live `SceneBsnAst` + 非 active tab 的 stash 快照；其干净基线随重写重算（与 stand-on tab 同待遇）。**实施中发现第二因**：live doc 的 IsA 拼写是装载时绝对化的绝对路径，`rewrite_ast` 按索引相对形式匹配落空——sweep 的 move 列表追加绝对→绝对 `Spelled` 对（相对 Names 对照旧服务磁盘文件） |

深化格（方案 T2-1 要求）：`an_external_edit_after_an_apply_still_reaches_every_instance`
——apply+驱动器 respawn 后外部再改 prefab，按 watcher 逐文件纪律手工驱动
（stage→cache 换血→take→`reload_instances_of`），两实例（含 y=2 placement 兄弟）都跟随
新外部基线且 placement 保留。红在档、绿在档。

## 二、回归面与门禁（全绿，日志全文复核）

| 面 | 结果 | 日志 |
|---|---|---|
| tests/prefabs | **99 passed / 0 failed / 0 ignored**（100 件，1 件 A6 票全套并发挂、隔离跑绿 ×3——见 §五-1） | `t14t2-six-green.log`+全套件运行 |
| tests/operators | **156 passed / 0 failed**（含 operator_undo 11 件） | 同上批运行 |
| tests/guards | **244 passed / 0 failed**（含 record_counts 双名单、undo_history 29 件、recovery 7 件） | 同上 |
| libtests 全仓 | **2975+1183 等，终态 EXIT=0** | `t14t2_qa_libtests.log` |
| `cargo xtask fast` | **2975 run: 2975 passed, 0 skipped**，exit 0 | `t14t2_gate_fast.log` |
| clippy 全仓 `--all-targets --features dylib -D warnings` | exit 0 / `^error`=0 | `t14t2_qa_clippy_ws.log` |
| 物理双包 clippy `-p jackdaw_physics --all-targets` | exit 0 | `t14t2_qa_clippy_physics.log` |
| fmt `cargo fmt --all -- --check` | exit 0 | `t14t2_qa_fmt.log` |
| scenes 域（watcher 邻域）`external_reload` | 18 passed | 同上批运行 |
| warn 形态扫描 | 见 §三 game 段 | `loop/t14-live/` |

磁盘检查：门前 df 202GB 可用（>20GB 阈值）；全程未设 RUST_BACKTRACE；门链与真机编辑器/游戏不同窗。

## 三、真机复跑（`loop/qa/t14-live.sh`，fixture=`loop-mac/t14-prefab`）

三段单调用复跑（prep→editor→game）。**放行条件 L6 五点链=PASS**，game 段全绿：

```
game 段（终态 summary-game.txt）：L5_PIE_PREFAB_SCENE=PASS  L5_STOP_RESTORES=PASS
L6_EXPORT_FIVE_POINT=PASS  WARN_SCAN_GAME=PASS（N13 PIE panic 记数 1，绕行口径）
  L5：编辑器会话（fresh prep）→PIE 游戏 RockTip=3 BarrelRock=1 rock_b scale=[2.0,1.0,1.0]（盘上授权覆盖）tip y=1.0；Stop 后计数复原、world.bsn sha 稳定
  L6：sed 改 rock.bsn y=5.5→导出→staged 独立启动读 5.5 ✓→还原→重导→staged 读 1.0 ✓（双向）
```

editor 段（两轮）：L0 夹具解析/L1 原生对话框/L2 四动作（apply field/component、bulk apply、
revert component）/L3 apply-all+revert-all/L7 重启复原/L8 spawn-undo/WARN_SCAN 全 PASS；
L2_REVERT_COMPONENT 第二轮 FAIL、L2_REVERT_FIELD/L3_SAVE_AS_VARIANT/L3_SAVE_AS_PREFAB/
L3_UNBUNDLE/L8_PACK_UNDO_FILE_STAYS FAIL——与 T1 终轮同集合的 UI 行定位/竞态（脚本腿，
语义面有 headless 锚），非本轮回归。

**L4 外部编辑传播 FAIL（两轮同签名）＝腿前提被 PF2 修复打破，非产品回归**。根因链：
L2/L3 的 apply 现在即写盘（PF2），rock.bsn 被重写为多行展开形——L4 腿的单行 sed
（`s|y: 1.0, z: 0.0|...`）从此不命中，盘上根本没改成 4.0（腿内 `grep -q "y: 4.0"` 亦
失败）。产品面反证：无头新增件 `an_external_edit_after_an_apply_lands_through_the_real_
watcher`（apply 落盘+指纹后走真实 notify+debounce 的外部编辑）绿；T1 的 L4（PF2 落盘前
单行夹具）绿；PF2 真机绿色见证 `loop/t14-live/pf2-live-witness-t2.txt`（apply 后盘上
rock.bsn 即带基线 scale [2.0,1.0,1.0] 且经 L7 重启存活——T1 见证链反转）。T3 修腿：
sed 改多行容忍。

**脚本腿修复（本轮工具，全透明）**：`loop/qa/t14-live.sh` 三处——(1) 数字门 `awk -v a "$x"`
为坏 shell 形态（BSD awk 拒参，数字门从未真正评过）→ `awk -v a="$x"`（3 处）；(2) L5 的
awk 门因此从假 FAIL 转真 PASS；(3) `export_prefab_wait` 就绪谓词补 T1 记录的载荷轮询
（staged rock.bsn sha==本地+manifest 点名，state=ready 竞态绕过）与 L6 第二点的裸字符串
门（"1.0"≠"1" 恒假）改数值窗。修复前 game 段日志存 `t14t2-live-game*.log`（L6 数值双向
绿而门 FAIL 的三次记录在档）。

## 四、偏差清单（按影响分级）

1. **PF5 修向细化（低）**：裁定原文「先按 `.` 取首段再 retain」。实施为**叶移除+空剪枝**。
   首段 retain 在复合 delta 上会把未 apply 的兄弟覆盖一并丢掉（例：delta 持
   translation{x:5,y:9}，apply x → 整个 translation 字段被 retain 掉 → y=9 丢失），
   比现状（整名不命中、永不清理）更差；叶移除达到裁定意图（点路径清得掉）且无此回归。
   新增测试把「兄弟覆盖保留」钉进绿证。
2. **PF5 时序前移（低，实施发现）**：清除必须**先于捕获**——否则驱动器 reload 从捕获文本
   复活已清的叶。以 cached 预检（`PrefabAstCache::get`）挡住「未缓存」失败路径，清除
   之前不可能走到，无「清了 delta 但基线未动」的丢失窗口。
3. **PF9 追加绝对拼写对（低，实施发现）**：live doc 的 IsA 在装载时被绝对化，仅靠索引
   相对形式匹配时 sweep 零命中（DIAG 实证 source=绝对路径）。sweep moves 追加
   `Spelled{from: old 绝对, to: new 绝对}`；磁盘文件仍走原相对 Names 对。绝对形式即缓存
   惯例（`save_prefab_to_disk` 注释明言 cache 保绝对路径），emit 时照旧 relativize。
4. **Inspector 逐字段 apply 逐字段落盘（低，PF2 语义的自然结果）**：Inspector 的
   `apply_component_to_source` 逐叶派发 `prefab.apply_to_source` operator，每叶各落一次
   盘（小文件、原子写）。裁定「一次落盘」针对 `apply_all_overrides_to_source`
   （hierarchy Apply All），已按裁定一次落盘。若需 Inspector 批量面合并落盘，T3 记账。
5. **PF4 名单语义注记（无偏差）**：`prefab.apply_to_source` 移入 `SELF_PUSHING` 名单，
   名单 doc 扩注「文件级写盘不可撤销」一类；assert 的报错文案对 apply 略不贴切（说
   pushes its own entry），以名单内注释澄清。
6. **未动面（知悉）**：`pack_matching_groups`/`save_scene_as_prefab` 的 cache insert 未加
   staging（写入的是全新内容+全新实例节点；overwrite 撞既有实例为既有边缘行为，无红证
   格，不入 T2 面）；`placement_migration` 的 reload 为纯场景文档路，无需 staging；
   `bulk_apply_in_scene` 不 mutate 缓存，对当前基线捕获即正确，同帧 apply→bulk_apply
   组合由 staging 自动正确（实测深化格路径覆盖）。
7. **buglist/台账/roadmap 未改**（R3/W23 打钩留 T3，按任务纪律）。

## 五、给 QA 的注意事项

1. **A6 票口径**：`prefab_lifecycle::prefab_file_change_triggers_reload` 在全套件并发跑
   下挂（Got v1）、隔离跑绿（本轮 ×3，含门后终跑）。按 T1 定案口径隔离跑/放行，真机
   L4（外部编辑传播）为该环节正主——本轮真机重跑照跑。
2. **thumbnail 面并行 flake（与 prefab 无关）**：
   `thumbnail::tests::a_subject_whose_models_have_all_failed_is_written_off` 在满载并行
   libtests 下挂 ×2（src/thumbnail.rs:1477 "the model it names cannot load"），模块单跑
   23 件全绿、静机全量跑 EXIT=0。归因环境负载，非本轮改动面（thumbnail/asset 与 prefab
   零交集）。
3. **apply 现在不可撤销**（PF4 裁定=Unity 同语义）：undo 栈不再产生 no-op 条目；对 apply
   的撤销预期需按新语义提票。
4. **真机三段复跑**：`bash loop/qa/t14-live.sh prep|editor|game` 各自单调用（阶段自管
   进程启停）；editor 段含 rfd 原生对话框腿（依赖宿主辅助功能授权，T1 §九-1 口径）；
   game 段两次导出+staged 独立启动，约 10-15 分钟。
5. **PF2 后的 L5/L6 语义**：editor 段的 apply 现在落盘——game 段新编辑器自盘重建即得
   新基线，T1 的 L5 PF2 见证链（会话内 2 → 盘上 1 → 游戏按 1）应翻转为按盘上 2 进游戏；
   L6 五点链（磁盘 sed 面）与 apply 面（headless 格）双证。
6. 产物归档：红证 `t14t1-pf1-red.log`/`t14t1-pf9-red.log`（T1）+
   `t14t2-pf4-red.log`/`t14t2-t1-cells-red.log`/`t14t2-new-cells-red.log`（本轮）；
   绿证 `t14t2-six-green.log`；门禁 `t14t2_qa_*.log`/`t14t2_gate_fast.log`；
   真机 `loop/t14-live/`。
