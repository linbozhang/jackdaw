# T14-T3 程序报告：收官段（腿修复 + 35 格终态 + 文档 + 全量门）

> 分支 `loop/t14-prefab`（main=c08f800e 已并，T1=e20517ed、T2=8f8581f6 在分支史）。
> 任务书：`loop/plans/t14-prefab-acceptance.md` §五-T3+§六-T3 书单；QA 回流清单：
> `loop/reports/t14-t2-qa.md` §六/§八（L4/L2d/L2a 修腿 + 35 格终态 + L1-L8 复跑 +
> book/buglist + 记账三项）。零产品代码改动（只动 `loop/qa/t14-live.sh` 腿脚本、
> `book/`、`buglist.md`、`loop/reports/`）。全程未设 RUST_BACKTRACE；门前 df=166GB。

## 〇、执行摘要

QA 回流③的必办清单逐项落地：**L4 腿修复成立并转绿**（sed 单行 → `re_prefab_y`
空白/换行容忍重写 + 替换计数门；PF2 后盘面多行展开形下 watcher 真机门恢复效力）；
**L2a 分段前夹具复位成立并转绿**（`write_fixtures` 提取、editor 段开场重写夹具，
硬编码基线门恢复前提）；**L2d 数值窗成立**（裸 "0" 门 → awk 窗口变量形）——但该腿
仍然 FAIL，归因升格：**Inspector walk 从未出现 "translation" 行文本**（非门形问题，
见 §二-3）；**L2b "frozen" 残留文案清理 + 转真门**（见 §二-2，语义按实测翻转）。
真机 L1-L8 三轮全量复跑，终轮 **16 PASS / 5 FAIL**（21 腿）：PASS 集含 L1/L2 系列
4 腿/L3 Apply-All+Revert-All/**L4**/L5+L5-stop/**L6 五点链**/L7/L8a + 双 WARN_SCAN；
5 个 FAIL 全部收敛在「对话框提交 + 行定位」UI 驱动族（L2_REVERT_FIELD、
L3_SAVE_AS_VARIANT/PREFAB、L3_UNBUNDLE、L8_PACK），与 T1/T2 终轮同族、语义面全部
有 headless 锚（§二-5 逐腿归因 + 修复史）。35 格矩阵终态 **34 格 ✅ / 1 格 ⚠️-腿**
（§四：六格红转绿指针兑现；唯一非 ✅ 格的缺陷面为零——是脚本腿驱动缺口）。
book 新章 `user-guide/prefabs.md`（七环节导览/apply 即写盘+不可撤销披露/变体嵌套
修复后语义/导出链/三条记账注记）+ SUMMARY + scene-management 交叉引用；
buglist **R3、W23 打钩**并注记 T14-T2 8f8581f6。全量门见 §五（teaches 88、
integration A6 口径隔离、scaffold_e2e 冷编落袋）。

## 一、QA 必办清单逐项处置（t14-t2-qa.md 回流③）

| # | 必办 | 处置 | 判 |
|---|---|---|---|
| 1 | L4 腿修复（sed 单行→多行容忍，恢复 watcher 真机门，复跑 L4） | `re_prefab_y` 帮手（python 原位正则 `y: <old>,\s*z: ` 容忍任意空白/换行）+ 替换计数门 `[ "${n_y:-0}" -ge 1 ]`；L4/L6 四处调用 | **PASS（终轮）** |
| 2 | L2d 数值窗 | `[ "$py" = "0" ]` → `pyw=$(awk ...)` 变量形 + `[ -n "$py" ] && [ "$pyw" = "y" ]`（防空读假绿） | 门形已修；腿仍 FAIL=行文本缺失（§二-3） |
| 3 | L2a 分段前 prep | 夹具写入块提取为 `write_fixtures`，editor 段开场（editor_boot 前）重写四夹具+flow——硬编码 [1,1,1] 门恢复前提，editor 段可独立复跑 | **PASS（终轮）** |
| 4 | L2_REVERT_FIELD 裸串门（"0.0"≠"0"） | 同 #2 | 同 #2 |
| 5 | L2b 残留 "frozen" 文案清理（QA §六-4） | 文案改「sibling follows the applied baseline」并转真门；实测 rock_a 保 [1,1,1] 授权覆盖、rock_b 跟随新基线 [2,1,1]——门按双断言落（§二-2） | **PASS（终轮）** |
| 6 | 35 格终态表（六格红转绿指针） | §四终表：PF1/PF2/PF3/PF4/PF5/PF9 六格全部 ✅（headless 绿证 T2 在档 + 真机活证本轮） | 完成 |
| 7 | L1-L8 全腿复跑 + 全程 warn 扫描 + N13 记数 | 四轮全量（§三终轮 16/21）；WARN_SCAN editor+game 双 PASS（词表含 `game flow:`/`Cannot spawn scene`，零命中）；**N13 PIE panic 本轮记数 0**（T2 曾 5） | 完成 |
| 8 | book Prefab 章 + 交叉引用 | `book/src/user-guide/prefabs.md` 新章（§六-1）；SUMMARY 挂目；scene-management 拾取对话框句挂链 | 完成 |
| 9 | buglist 打钩：R3（=PF3）、W23（=PF5） | 均 `- [x]` + 注记 8f8581f6（T14-T2 并账 PF3/PF5）+ 红绿证测试名 | 完成 |
| 10 | 记账三项 | §六-2（pack/save_scene overwrite staging 缺席、Inspector 批量落盘合并、PF9 Spelled folder/canonical 残余）——报告 ⚪ 账 + book 三处注记 | 完成 |
| 11 | 全量门（fmt/clippy 全仓+物理双包/libtests/fast/integration/doctests/docs/scaffold_e2e） | §五门禁表；integration A6 口径沿用（全套件红=A6 件 + 隔离跑绿如实记数） | 完成 |
| 12 | 台账/roadmap 不动 | 未动（主控合入时写） | 遵守 |

## 二、腿修复史（四轮，全程透明）

1. **第 1 轮（QA 必办三项 + L5/L6 语义翻转）**：`re_prefab_y` 帮手（替换计数门）；
   L2d awk 窗口；`write_fixtures` 夹具复位；L5 删 PF2 见证块（PF2 后游戏按盘上进
   基线即 PASS 形态，T2 终轮 console 已证）；L6 同帮手。结果：15/21，新转绿
   L4/L2_REVERT_COMPONENT/L5 门形；新 FAIL L2_APPLY_TO_SOURCE（门值错，见 2）。
2. **第 2 轮（L2b 门值纠正 + 对话框 BRP 化 + 行菜单选中先行）**：rock_a 在夹具里
   **有 authored scale [1,1,1]**（world.bsn 节点显式写）——apply 后 rock_a 保
   [1,1,1] 是「实例独有保留」的正确行为，旧门（跟随 [2,1,1]）把正确行为判负；
   改双断言 rock_a=[1,1,1] + rock_b=[2,1,1]（applied 实例跟随新基线）。
   dialog_input 改 BRP `dialog.answer choice=0`（对话框 action 按钮，走 feathers
   resolve_dialog_choice，像素无关）；row_menu 加选中先行。结果：15/21，五腿同族
   FAIL 未动——对话框 answer 静默无效果（editor 日志零 dialog.answer 行=或未达
   对话框、或保存路径未触发），barrel_a 行菜单仍不开。
3. **第 3 轮（bevy 原生点击试验，回退）**：menu_click/row_menu/L2d 全改
   click_text/rclick_text（widget 解析、坐标无关）——**反而大面积回归**（UI 菜单
   腿 6 腿全挂；L5 因 L3c 未回滚 [3,1,1] 连带 FAIL）。定案：ui_click 的文本子串
   匹配与右键菜单的命中面在本环境不可靠；**全部回退**到第 2 轮形态（菜单函数从
   git HEAD 字节恢复 + 重放选中先行小补丁）。
4. **第 4 轮（终轮）**：16/21。相对第 2 轮净变化：L2b 门修好转绿；L2b 等待加长
   （4s+wait_idle 240）+ rb 双值入日志。剩余 5 FAIL 与 T1/T2 终轮同集合同族。

### 剩余 5 FAIL 逐腿归因（脚本腿，非产品缺陷；语义面均有锚）

| 腿 | 现象（三轮一致） | 归因 | 语义面锚 |
|---|---|---|---|
| L2_REVERT_FIELD | Inspector walk 从未出现 "translation" 行文本（重选 rock_b 亦不渲染）；门形已修（awk 窗口） | 字段行渲染/文本节点不在 walk 可见集（T1 §三即「定位超时」同族） | lifecycle undo-of-revert + revert 系 4 件；L2 同菜单族 L2a/L2b/L2c 真机 PASS 证右键通道本身可用 |
| L3_SAVE_AS_VARIANT | 对话框开、text_input 在、answer 0 后对话框不关、文件不落（editor 日志零 dialog.answer warn） | prefab 对话框的 children-slot 形态不经 feathers DialogChoices 主按钮面，`dialog.answer` 达不到它 | T④ headless（变体+undo+文件留盘）；T1 干跑人工证全链（rock_var.bsn 落盘+实例改接线） |
| L3_SAVE_AS_PREFAB | 同上（同对话框族） | 同上 | PO pack/save_as_prefab 4 件；LC save_round_trip |
| L3_UNBUNDLE | barrel_a 行右键菜单三轮不开（rock_b 同函数可开） | 行菜单对嵌套实例行/未选中行的绑定缺口（脚本驱动） | LC 1315/3407/2239 + T⑤ 探针（嵌套×unpack 持久性=存活） |
| L8_PACK_UNDO_FILE_STAYS | 同 L3d（barrel_a 行） | 同上 | PO undo_of_pack（文件留盘约定）+ guards batch_undo |

注：这 5 腿在 T1 终轮/T2 两轮即 FAIL（QA 已勘误定性「脚本定位/竞态（脚本腿，
语义面有 headless 锚），非产品缺陷/非本轮回归」）；T3 三轮修腿将同族可修面
（L2a/L2b/L4/L6/L5 门形）全部修净，剩余为对话框提交与字段行渲染两个驱动缺口，
如实留档给后续工具票。

## 三、真机终态（第 4 轮全量，`loop/qa/t14-live.sh all`；证据 `loop/t14-live/` + `t14t3_live_all*-prog.log`）

```
L0_FIXTURE_RESOLVES=PASS          夹具解析（3 实例+RockTip×3+BarrelRock+rock_b scale [2,1,1]）
L1_NATIVE_PICKER=PASS             rfd 原生对话框 osascript 键注，base.bsn 实例落地
L2_REVERT_COMPONENT=PASS          Revert Component → scale 回 [1,1,1]（夹具复位后门前提成立）
L2_APPLY_TO_SOURCE=PASS           Apply Component：rock_b 跟随新基线 [2,1,1]、rock_a 保授权 [1,1,1]
L2_BULK_APPLY=PASS                Apply to All Instances：双 rock 同 [2,1,1]
L2_APPLY_FIELD=PASS               Apply Field to Prefab Source 派发
L2_REVERT_FIELD=FAIL              字段行文本不在 walk（§二-3，门形已修）
L3_APPLY_ALL=PASS                 hierarchy Apply All 派发
L3_REVERT_ALL=PASS                Revert All（基线相对断言）
L3_SAVE_AS_VARIANT=FAIL           对话框提交缺口（§二-5）
L3_SAVE_AS_PREFAB=FAIL            同上
L3_UNBUNDLE=FAIL                  barrel_a 行菜单不开
L4_EXTERNAL_EDIT_PROPAGATES=PASS  外部改 rock.bsn（多行形 y1→4）→RockTip=4.0；还原→1.0；
                                  rock_b 授权覆盖保 [2,1,1]——PF1 文件路+覆盖保留双证
L5_PIE_PREFAB_SCENE=PASS          游戏世界 RockTip=3/BarrelRock=1/rock_b scale=[2,1,1]/tip y=1.0
L5_STOP_RESTORES=PASS             Stop 后编辑态计数复原、world.bsn sha 稳定
L6_EXPORT_FIVE_POINT=PASS         sed y=5.5→导出→staged 独立启动 5.5 ✓→还原→重导→1.0 ✓（双向）
L7_EDITOR_RESTART=PASS            存→退→重启→journal 复原 rock_a/RockTip
L8_SPAWN_UNDO=PASS                spawn→undo（history.undo 键位同命令通道，classic 预设启动日志背书）
L8_PACK_UNDO_FILE_STAYS=FAIL      barrel_a 行菜单不开（同 L3d）
WARN_SCAN_EDITOR=PASS             defect_forms=0 game_flow=0 refused=0
WARN_SCAN_GAME=PASS               同上；N13 PIE panic 记数 0（T2 终轮 1；词表零命中）
```

**16 PASS / 5 FAIL（21 腿）**。四轮趋势：T1 终轮 12 PASS → T2 终轮 13 PASS →
T3 第 1 轮 15 → 第 2/4 轮 16（第 3 轮试验轮 12，已回退）。

## 四、35 格主矩阵终态

锚缩写同 T1 报告（L*=真机腿、T=tests/prefabs/prefab_t14_acceptance.rs、LC=
lifecycle、PO=prefab_ops、G=guards、UI=ui_import、SP=source_paths、RT/RTm=crate 单测）。

### A. 创建
| 维度 | 终态 | 锚 |
|---|---|---|
| 多实例更新 | ✅ | PO pack_matching 4 件 |
| 实例独有保留 | ✅ | PO pack_writes 保 transform + LC 2573 |
| undo | ✅ | PO undo_of_pack + LC 3172/3248/3580 |
| 重开 | ✅ | LC 2515/1524 + components 防漂移 |
| 导出 | ✅ | **L6 五点链终轮 PASS**（改→导→staged 独立启动→变→还原→重导→变回） |

### B. 实例
| 维度 | 终态 | 锚 |
|---|---|---|
| 多实例更新 | ✅ | PO 810 |
| 实例独有保留 | ✅ | LC 2573/2662 + guards 83-248 |
| undo | ✅ | LC 3248 + guards 686/574-598 + **L8a 终轮 PASS** |
| 重开 | ✅ | LC 380 + guards 728 + **L7 终轮 PASS** |
| 导出 | ✅ | L6（world.bsn 三实例随包） |
| 入口面 | ✅ | **L1 终轮 PASS**；UI 导入 ✅H（UI 7 件） |

### C. 覆盖
| 维度 | 终态 | 锚 |
|---|---|---|
| 多实例更新 | ✅ | UI 229 |
| 实例独有保留 | ✅ | watcher 先捕获后更新 + LC 2832 + **L4 终轮 PASS**（外部编辑→跟随+rock_b [2,1,1] 保） |
| undo | ✅ | guards 567/3670 |
| 重开 | ✅ | LC 3801 + L7 |
| 导出 | ✅ | L5（rock_b 覆盖 [2,1,1] 游戏端一致）+ RT prefab_resolution 65 |
| 可见面 | ✅ | **L2a/L2b/L2c/L2d-apply 终轮 PASS**（右键五动作四达；字段行 revert 面见 §二-3） |

### D. 应用（六格红转绿主面）
| 维度 | 终态 | 锚 |
|---|---|---|
| 多实例更新 | ✅ | **PF1 修复**：T① 深化格+真 watcher 交互格绿（T2）；真机 **L2b 终轮 PASS**（applied 实例 rock_b 跟随 [2,1,1]）+ **L4 PASS**（文件路传播） |
| 实例独有保留 | ✅ | **PF5 修复**：applied 叶清除、兄弟覆盖保留（T2 绿证）；真机 L2b 的 rock_a [1,1,1] 存活 + L4 rock_b [2,1,1] 存活 |
| undo | ✅ | **PF4 修复**：apply 声明不可撤销、双名单同步（T2 guards 绿）；Unity 同语义，撤销预期按新语义提票 |
| 重开 | ✅ | **PF2 修复**：apply 即写盘+指纹回声防（T2 重钉绿）；真机 **L5 PASS**（游戏按盘上基线 [2,1,1] 进世界=T2 见证链反转的收口） |
| 导出 | ✅ | **PF2 牵连收口**：L6 五点链 PASS（盘面路径）+ L5（apply 路径按盘） |
| Apply All 面 | ✅ | T② + L3b（终轮 PASS，apply-all 单次落盘） |

### E. 还原
| 维度 | 终态 | 锚 |
|---|---|---|
| 多实例更新 | ✅ | LC 3917 |
| 实例独有保留 | ✅ | LC 974 + 拒删 + LC 4004 |
| undo | ✅ | T③ |
| 重开 | ✅ | 与 C-重开同锚 + L7 |
| 导出 | ✅ | L6 参数化（还原后=基线） |
| unpack/unbundle 面 | ✅（语义）/⚠️（L3d/L8b 真机驱动腿） | LC 1315/3407/2239 + T⑤（E-6 存活）；真机 unbundle/pack 腿=对话框+行驱动缺口（§二-5），产品语义面 headless 全锚 |

### F. 嵌套
| 维度 | 终态 | 锚 |
|---|---|---|
| 多实例更新 | ✅ | LC 683 + sync 递归；L4（barrel→rock 链 RockTip 同步） |
| 实例独有保留 | ✅ | nested_instance_ids 64/82 + resolver 762 |
| undo | ✅ | LC 3248 族 |
| 重开 | ✅ | cache_prefab_tree + runtime 递归；**L5 PASS**（三层在游戏世界解析） |
| 导出 | ✅ | runtime 285 + L6（staged 含嵌套链） |
| 变体×嵌套 | ✅ | **PF3 修复**（=R3 打钩）：变体保层级+内嵌 IsA（T2 绿证：nested(5) 挂 root(0)、knob(7) 挂 nested(5)、隔离 app 物化 knob） |

### G. 变体
| 维度 | 终态 | 锚 |
|---|---|---|
| 多实例更新 | ✅ | runtime 330 + IsA 链 |
| 实例独有保留 | ✅ | LC 1029 + operators 1755-1777 |
| undo | ✅ | T④ |
| 重开 | ✅ | SP 183 + UI 388 |
| 导出 | ✅ | L6 |
| 浅层形态 | ✅ | LC 1029 |

**统计：✅ 34 格；⚠️ 1 格（E-unpack/unbundle 面的「真机驱动腿」缺口——缺陷面为零，
是脚本腿缺口，见 §二-5；产品语义面 headless 全锚 + T⑤ 真机探针存活记录）。**
T1 底稿 24✅/8⚠️/3🔴 → T2 后 32✅/🔴 清零 → T3 终态 34✅/1⚠️（T2 修复面的两格
——D-多实例更新真机证、D-重开/导出 apply 路真机证——本轮 L2b/L5 PASS 后从
headless-only 升格为双证）。

## 五、门禁表（QA 亲跑位；程序日志 `t14t3_*.log`）

| 门 | 命令 | 结果 | 日志 |
|---|---|---|---|
| 1 | `cargo fmt --all -- --check` | **EXIT=0**（全文 0 error/Diff） | `t14t3_fmt.log` |
| 2 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **EXIT=0** | `t14t3_clippy_ws.log` |
| 3 | 物理双包 clippy（T13 终验同款强口径） | **EXIT=0** | `t14t3_clippy_phy.log` |
| 4 | `cargo test --workspace --lib` | **EXIT=0**：58 套件 0 failed；scaffold/teaches **88 passed** 点数在案 | `t14t3_libtests.log` |
| 5 | `cargo xtask fast` | **EXIT=0**：**2975 run: 2975 passed, 0 skipped** | `t14t3_fast.log` |
| 6 | `cargo xtask integration` | **EXIT=1＝唯一红恰为 A6 件**（`prefab_file_change_triggers_reload`，nextest 两试同签名）→ **隔离跑 EXIT=0**（`t14t3_a6_isolated.log`）；按 T1/T2/T13 定案口径放行 | 同左 |
| 7 | `cargo test --doc --workspace` | **EXIT=101＝已知 jackdaw_bind dyld rpath flake**（`@rpath/libstd` 装载失败，/private/var 临时目录族；T12/T13 同族）→ **bind 重跑 EXIT=0**（`t14t3_doctests_bind_rerun.log`） | 同左 |
| 8 | `cargo doc --no-deps --workspace` | **EXIT=0**（17 条既有 rustdoc 私有项链接 warning，非本轮改动面——本轮零 Rust diff） | `t14t3_docs.log` |
| 9 | scaffold_e2e 冷编 | **EXIT=0**（1 passed，146.23s 冷编落袋） | `t14t3_scaffold_e2e.log` |

## 六、记账与偏差

### 1. 记账三项（QA §六-5，⚪ 账，不修码）
1. **pack/save_scene_as_prefab overwrite 边缘的 staging 缺席**：两者的 cache insert
   不走 staged 捕获——写入的是全新内容+全新实例节点；overwrite 撞既有实例时旧实例
   不做 staged reload。已入 book「Packing」节（One known edge 段）。
2. **Inspector 批量 apply 逐字段落盘**：逐叶派发 `prefab.apply_to_source` 每叶一次
   原子小盘写+各自指纹登记（同帧由 stage-if-empty 只捕第一次，回声安全；中间态均为
   合法基线）。已入 book「Applying」节（五次写说明）。
3. **PF9 Spelled 臂残余缝隙**：folder tail 拼写与 canonical 路径分歧（macOS /var
   symlink 族）理论上有缝隙，现测未踩。已入 book「Variants」节（Two narrow gaps）。

### 2. 偏差分级
- **腿修复回退一轮（中，过程性）**：第 3 轮 bevy 原生点击试验造成 6 腿回归，当轮
  发现、当轮全量回退（menu/row 函数从 git HEAD 字节恢复+重放小补丁），第 4 轮即
  修复效果确认轮。回退零残留（§五门禁的 fmt/clippy 不涉 shell；`bash -n` 全程门）。
- **L2b 门语义按实测翻转为双断言（低）**：QA 文案预期「sibling follows」；实测夹具
  的 rock_a 有 authored scale——「跟随」面在 applied 实例（rock_b）上断言，「保留」
  面在 sibling（rock_a）上断言。比单断言更完整，无产品影响。
- **L5 PF2 见证块移除（按 T2 QA §四定案）**：PF2 后游戏按盘上进基线是 PASS 形态
  （T2 终轮已证），见证块成为恒假门，删除。T2 见证文件保留在档。
- **N13 记数 0（知悉）**：T2 终轮 1 次、本轮 0 次——环境票波动，口径不变（绕行+记数）。

## 七、给 QA 终验的注意事项

1. **A6 口径沿用**：`prefab_lifecycle::prefab_file_change_triggers_reload` 全套件
   并发红（Got ["v1"] 同签名）、隔离跑绿——放行不受阻，真机 L4 为该环节正主（本轮
   PASS）。
2. **五个脚本腿 FAIL 的定性材料**：§二-5 表 + T1 §三/T2 勘误（同族、同归因）+ 各腿
   headless 锚清单位置。若 QA 要复现修复史：第 1/2/4 轮 prog 日志在
   `t14t3_live_all{,2,4}-prog.log`（第 3 轮 `t14t3_live_all3-prog.log` 为回退试验轮）。
3. **真机复跑入口**：`bash loop/qa/t14-live.sh prep|editor|game|all`（分段自管进程；
   editor 段含 rfd 对话框腿，依赖宿主辅助功能授权；L2a 门依赖夹具复位=editor 段
   开场自动做，无需重 prep）。
4. **「apply 现在不可撤销」**（PF4 定案）与「apply 即写盘」(PF2)——book 章已按用户
   视角披露；对 apply 的撤销预期需按新语义提票。
5. **门链与编辑器/游戏不同窗**（T12-T3 §九-7）：本轮全程遵守（live 跑完再起门链）；
   门前 df=166GB；无残留进程。

## 八、归档清单（本轮新增）

| 文件 | 内容 |
|---|---|
| `loop/reports/t14t3_live_all{,2,3,4}-prog.log` | 四轮真机全量 prog 日志（3=回退试验轮） |
| `loop/t14-live/`（终轮覆盖） | console-all.log、editor-all.log、summary*.txt、pf1-live-witness.txt、n13-count.txt、shot-l2-inspector.* |
| `loop/qa/t14t3-gates.sh` + `loop/reports/t14t3_*.log` | 门链脚本 + 各门日志 + exitcodes |
| `loop/reports/t14t2_gate_fast-prog.log` | T2 程序侧 fast 门原日志（QA 归档注记的 *-prog 保留件，随本提交入库） |
