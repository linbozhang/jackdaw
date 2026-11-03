# T23 任务 3 报告：终验 + 文档轮（13 格终态、MO9 收口、QD1 红证、book 新章）

> 分支 `loop/t23-material` @ **8bf20864**（含 T1 建设、T2 真机矩阵、两轮 QA PASS、main
> 59536d18 合入）；方案 `loop/plans/t23-material-override.md` §四-T3；T2 QA §七放行
> 六点注意=本任务清单来源。**六件全部落地：QD1 修前红证 10/10、MO9 Map 臂+3 单测
> 红腿翻绿、终验 13 格 PASS（25/25 腿零 FAIL）、book 新章挂链、QD2 一句话更正、本
> 报告。** 终态证据 `loop/t23-final/`（首窗已被取代的 attempt1 在
> `loop/t23-final-attempt1/`，见 §三-附注）；T2 证据 `loop/t23-live/` 与 QA 证据
> `loop/t23-live-qa/` 未动。RUST_BACKTRACE 全程未设；门前 df 79Gi。

## 一、QD1：M8 修前执行型红证（开场第一件）

- 做法：`git checkout 12c0f9f1`（T23-T1 之前的 main，含 T23 方案提交；脚本自带
  build 断言，站错 commit 即 RED_ABORT）→ `cargo build -p jackdaw -p jd` → 专用红证
  脚本（`loop-mac/t23t3-red/m8-red.sh`，仓外自守，helpers 抄自 t23-live.sh）→ 新
  fixture（props.glb 材质 Rock/Trim+一无名；手写 mossy.bsn+deep.bsn 水面材质）→
  place → `material.override Rock→deep`（**水面判据**：give-back 是 BRP 可读的组件
  在场性事实）→ GLB 改名 `Rock→Stone` → 观测。
- **修前静默全证（10/10 腿 PASS，`loop/reports/t23t3_m8_red.log`，build 12c0f9f1，
  run 2026-11-03 11:58）**：

  | 腿 | 事实 |
  |---|---|
  | RED_PLACE / RED_DRESS / RED_DRESS_VISIBLE | 3 named parts；Rock→deep 后水穿面 **2**、map=`{"Rock":"materials/deep.bsn"}`、PX **1.018%**（换装可见） |
  | RED_RELOAD | 改名写盘后部件实体更名 **Mesh.Stone**（结构确实动了） |
  | RED_SILENT_LOG | `material override:` 新增 **0** 行；`no part of it wears` **0** 行（报告面/文案在该 build 不存在） |
  | RED_SILENT_GIVEBACK | 水穿面 **2→0**——被覆盖部件**悄悄穿回原材质，无任何宣布** |
  | RED_SILENT_AUDIT | `jackdaw/audit` findings **0**（覆盖路径对审计不可见=MO2 修前活体） |
  | RED_SILENT_STATUS | ui_tree 全文无 `material override`（状态栏嘴不存在） |
  | RED_ENTRY_STAYS | 覆盖条目原地永存（无人清、无人报） |
  | RED_SILENT_REVERT | PX **1.018%**（与换装同幅视觉差=静默回穿的视觉见证） |

- 全程日志 warn-scan 仅 1 命中=RUN_OP INFO 点匹配（material.override 调用行本身）；
  两张 PX 见证 PNG 同归档（`t23t3_m8_red_dressed.png`/`t23t3_m8_red_after_rename.png`）。
- 红态纪律：红证先归档（loop/reports/ 三件）再回分支。脚本三轮迭代（v1 取景缺
  frame_all、v2 部件名查询组件面窄），前两轮 console 留档
  `loop-mac/t23t3-red/console-red*.log`+`t23t3_m8_red-v2.log`，产品行为零改动。
- **铁证②红侧 M8 格就此闭环**（T2 QA §三对账表唯一缺口）：MO1 红绿双证齐全——
  红=本 log（执行型，10/10），绿=T2 reimport 相四态+本轮终验 M8 格（§三）。

## 二、MO9 收口：rebind 的 Map 臂（红腿翻绿）

- **改动（唯一产品源文件）**：`src/inspector/missing_list.rs`
  `rewrite_ast_reference` Struct 臂加 `BsnValue::Map` 分支（~15 行）——与 List 臂
  同深度的同规则：只改写「值为 String 且拼法等于失效路径」的条目；**键不动**（材质
  名不是路径）；嵌套值不深入。
- **单测 3 件**（in-src，AR11 TupleStruct 先例同族，parse 真身 AST）：
  1. `an_override_map_reference_rebinds`——Trim 条目改写、Rock 条目不动、同实体
     `GltfSource.path` 不动；
  2. `an_override_map_rebind_moves_values_only`——同值两键全改写、**键拼成路径样
     字符串不误伤**、他值不动；
  3. `an_override_map_rebind_stays_on_its_own_component_and_field`——换层
     （InstanceMaterialOverrides）finding 不改写、无匹配 reference 不改写。
  `cargo test --lib -p jackdaw inspector::missing_list` = **5/5**（3 新+AR11 旧 2）。
- **修复路真身一轮**（终验 broken 相 M9 段，`t23t3_mo9_rebind_map_green.log`）：
  - `asset.rebind` 后 **audit 即归零**（`count:0`）——Map 引用改写真身，MO9 盲区闭合；
  - **A11 活世界粘性如实录档**（判据在文档面，粘性面只录不判）：rebind 后未重开窗口
    live kit map 仍 `{"Rock":"materials/wet.bsn"}`、layered 穿装 **0**——活世界不随
    AST 重绑定即时更新（A11 本体真踩，红证归 A11 票不修，与方案 buglist 表裁定
    口径一致）；**且 `scene.save` 发射的是重写后文档**（盘上 t23.bsn 写出 wet2，
    A11 原票「save 从活世界发射旧路径」的形态在本域未复现——按组件域差异如实
    记档，不推翻 A11 本体）；
  - 重开后：kit map=`{"Rock":"materials/wet2.bsn"}`+layered=2+**audit total=0**
    （`M9_REBIND` PASS）；
  - `M9_REBIND_MAP_GREEN` **PASS**——T2 QA §七-2 要求的「红腿 `M9_REBIND_MAP_BLIND`
    翻绿」落地（绿腿以文档面为准裁名，见 §三-附注的判据更正）。
- 脚本 M9 段改造：修复路保存链走编辑器自己的门（`scene.save`；T2 的文档外 python
  改写降为 fallback）；红/绿档案按 build 实况裁名，REPORT_TAG 参数化保证 T2 归档
  （`t23t2_mo9_rebind_map_red.log` 等）不被复跑覆盖。

## 三、终验矩阵 13 格（终态复跑，`loop/t23-final/`，2026-11-03 12:29-12:52）

七相 `all` 一窗跑毕：**25/25 腿全 PASS，零 FAIL**（console-all.log 六个 done: 行）。

| 格 | 腿/结果 | 终态证据（console-all.log 归档） |
|---|---|---|
| M1 五链主干 | ✅ 6 腿 | place 6 parts；L1_DRESS PX **2.468%**；L1_DOC_ON_DISK（patch+三路径盘上）；L1_REOPEN PX **0.058%**；L1_EXPORT（SHA 相等+staged 树携带）；L1_STAGED_DRESS（G：holders=2 map 精确回读，staged layered=2 全在 Mesh.Rock、water=1 在 Mesh.Trim） |
| M2 四穿面 | ✅ | L2_WEAR_FACES：Standard→**Layered(2)**→**Water(2)**→Standard（清零）→Trim Water(1)；kit Rock Layered(2)——组件换装活证 |
| M3 重名/无名 | ✅ | `name=Rock` 一键换装双部件（layered/water 成对出现）；**MO4_REFUSAL**：无名部件+name 空→`cancelled`+警告含可命名清单 |
| M4 多层预制体 | ✅ | M4_PREFAB_INSTANCE：pack 盘上携带、packed 实例水穿 1、实例层赢（roots=1 `{"Trim":wet}`，layered=1/water=0）、twin 跟随预制体（1/1） |
| M5 失效路径 | ✅ 3 腿 | rm wet→**恰 1 条** warn（原文归档 m5-warn-line.txt）+audit 精确四元组（component/document/entity/field=MaterialOverrides/t23.bsn/kit/materials）+layered 2→0；一次锁不重报；M5_HEAL 零新 warn 回 2；M5_SPEAKS_AGAIN |
| M6 编辑器改名 | ✅ 2 腿 | M6_RENAME：doc 唯一处 deep2+audit 0+重开穿新路径；M6_LIVE_FACE_CHARACTERIZED：`t23t3_rename_sticky.log`（活 map 粘旧+水面 1→0+1 条 unresolved——A11 族活世界粘性第二面，重开后文档赢） |
| M7 重导入保留 | ✅ | M7_REIMPORT：props.glb 加 BoxE→named=7、**BoxE 经幸存覆盖穿 Water**（water=2）、覆盖 map 原样、缩略图 FNV-mtime 新 PNG（M13 面） |
| M8 失效键 | ✅ 4 腿 | Rock→Stone→**恰 1 条**「overrides a material named 'Rock', which no part of it wears any more…」；同写再写不重报；M8_RECOVER 名字回归 water 回 2+零 warn；M8_SPEAKS_AGAIN；M8_FINAL_STATE |
| M9 审计/rebind | ✅ 2 腿 | **M9_REBIND_MAP_GREEN**（audit 即归零=盲区闭合+A11 活世界粘性如实录档）+**M9_REBIND**（save 写 wet2→重开穿 wet2→audit total=0）——修复路真身，见 §二 |
| M10 游戏侧边界 | ✅ | M10_GAME_MISSING：破包 named=6/layered=2/water=0、**零 panic**、游戏存活应答、游戏日志零 `material override:`（报告仅编辑器进程=设计） |
| M11 undo | ✅ | M11_UNDO：换装→undo→map 摘除→redo 复原，全程零假 warn |
| M12 warn 形态 | ✅ | 65 命中逐类归因：52 `material override:`（M5/M6/M8 预期说+MO8 瞬态自清轮）+12 `material.override:`（RUN_OP INFO 回显+MO4 拒绝 1）+1 索引拒（M13）；`UnresolvedTypes`/`holds no material`/`cannot-apply`/`panicked` **0**；staged 游戏/破包游戏日志 **0**。分窗总数 19/6/16/13/11/0——与 T2 逐相完全同形 |
| M13 T18 回归 | ✅ | M13_BROKEN_FILE（索引拒 1+覆盖 unresolved 1+水面摘除→恢复回穿 1）+M7 缩略图重渲染 |

**13/13 格 PASS，铁证①②终态复跑全绿；L1/L4/L6 重点腿（M1/M5+M9/M7+M8）全部在
上述格中终态复证。**

- **附注（attempt1 窗口，如实）**：终验首跑（12:05-12:40）25/25 腿亦全 PASS，但 M9
  辅腿判据误写在活世界面（rebind 后 live map 未随动即裁「blind」），把已闭合的
  MO9 误冠 `*_red` 名。判据更正为文档面（audit 计数）后整窗重跑；首窗证据原样保留
  于 `loop/t23-final-attempt1/`（含误名档案 `t23t3_mo9_rebind_map_red.log`——其内容
  本身如实录得 audit=0+live map 旧拼，正是 A11 面的第一手记录，被终窗 green 档案的
  A11 栏取代），报告如本条披露，不改写其内容。

## 四、门禁（产品改动后全量亲跑，单窗，编辑器/游戏 pkill 后）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | EXIT=0，零 Diff（collapsible_if 修复后复检再录 EXIT=0） | `t23t3_gates_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | EXIT=0（首轮揪出**测试内** 1 处 collapsible_if，修复后复跑绿；两轮均在档） | `t23t3_gates_clippy_ws.log` |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | EXIT=0，零行 | `t23t3_gates_clippy_phys.log` |
| libtests | `cargo test --workspace --lib`（59 二进制求和） | **3055/3055**（基线 3052+MO9 单测 3，吻合） | `t23t3_gates_libtests.log` |
| guards | `cargo nextest run --profile ci -p jackdaw --test guards` | **246/246**（258.4s，与基线同数） | `t23t3_guards.log` |
| stage | `cargo nextest run --profile ci -p jackdaw --test stage` | **572/572**（556.1s，与基线同数） | `t23t3_stage.log` |
| operators 档散布 | `cargo nextest run --profile ci -p jackdaw --test operators scatter_ops` | **18/18**（13.9s，与基线同数） | `t23t3_qa_scatter.log` |

全部归档日志 grep（`^error|FAILED|Diff after reformat|^warning:`）**零行**。AN2 腿
（T2 1/1）本轮未跑：改动不触 `jackdaw_runtime`（Map 臂在编辑器 crate+测试），按
本任务指令门清单执行；如 QA 需要可补一轮 `animation_scene_load`。
RUST_BACKTRACE 全程未设；门链与终验七相不同窗（终验 12:29-12:52 结束、进程 pkill
后 12:54 起跑门）。

**门禁数字变化汇总**：libtests 3052→**3055**（+3 MO9 单测）；guards 246→246（平）；
stage 572→572（平）；operators 18→18（平）；fmt/clippy 双门绿（首轮 clippy 测试内
1 处 collapsible_if 属新增单测自身，修复归档在案）。

## 五、book 新章 `book/src/user-guide/material-overrides.md`（SUMMARY 挂链）

- SUMMARY 排 Materials & Textures 之后。书单全覆盖：
  - **三层机制**用户视角：模型层 `MaterialOverrides`/实例层 `InstanceMaterialOverrides`
    （实例赢+未覆盖键跟随预制体）/运行时 dressing（编辑器视口与游戏同一插件，
    「所见即所穿」）；
  - **by-material-name 语义**：同名多部件一网打尽+无名材质不可寻址边界（DCC 命名建议）；
  - **换装三口**：材质行 Pick（自动选层）/operator（空 name=换全模型、`material=""`
    清条目）/浏览器 Apply——同落一个 undo 命令；预制体携带+散布带回；
  - **持久化/undo/导出**：patch 随场景存、重开再穿、undo 无警告、导出 catalog 解析；
    **游戏侧静默属设计**注记（「The reporting, though, stays in the editor…so the
    game log carries no `material override:` lines」）；
  - **失效双态**：路径断（warn 一次→恢复自愈静默→再断再说；audit Missing 四元组；
    `material=""` 手清门）与键断（条目永存+恰一条点名 warn）；
  - **MO8 注记一句（必含，原文在场）**：「the warnings you see in the first moments
    after opening a scene are spawn-timing, and clear themselves」；
  - **rebind 语义（MO9 收口后如实在书）**：「Rebind covers the override maps on both
    layers」——两层覆盖 map 均可 rebind，tab 转 dirty、保存/重开落世界；
  - **30 秒清单**（T2 QA §七-6 五条）落章尾「The 30-second tour」；
  - 交叉引用：materials-textures / prefabs / sprites-2d / assets / asset-references。
- mdbook 本机未装，链接手工核对（五个目标章均在 book/src/user-guide/）。

## 六、QD2：程序报告一句话更正

`loop/reports/t23-t2-report.md` §四 D4：原括注「门禁 stage 全绿含之」不实（scatter_ops
在 `tests/operators/` 档，T2 门链 guards+stage 不含该档）——改为如实表述「在
**operators 档**——T2 门链（guards+stage）不含该档，QA 亲跑 …=**18/18**（归档
`t23t2_qa_scatter.log`）」并留更正痕一句。

## 七、改动文件清单（与指令预期改动面一致：1 产品源文件+book+一句话更正+loop 工具/归档）

| 文件 | 改动 |
|---|---|
| `src/inspector/missing_list.rs` | **唯一产品源文件**：Map 臂 ~15 行+单测 3 件（测试内 collapsible_if 一处随 clippy 修复） |
| `book/src/user-guide/material-overrides.md` | 新章 |
| `book/src/SUMMARY.md` | 挂链一行 |
| `loop/reports/t23-t2-report.md` | D4 一句话更正（QD2） |
| `loop/qa/t23-live.sh` | T3 终验扩展：`T23_OUTDIR`/`T23_REPORT_TAG` 参数化；M9 段按文档面裁名（绿=audit 归零+归 A11 面；红=真 map-blind），修复路保存链走 `scene.save`（外改降 fallback）；M6 sticky 档名参数化 |
| `loop/reports/t23t3_*` | 归档：红证 3 件（log+2 PNG）、MO9 绿证 2 件、门禁 7 log、M6 sticky 1 件 |
| `loop/t23-final/`（38 文件） | 终态运行证据：console-all/editor-all-1..5/warn-scan/g-*.json/gb-*.json/截图/offsets |
| `loop/t23-final-attempt1/` | 被取代的首窗证据（25/25 PASS；含误名 MO9 档案 2 件，内容未改写，披露见 §三-附注） |

未动：buglist.md / 台账 / roadmap / fork / 场景格式 / 协议 / `loop/t23-live{,-qa}/`。

## 八、遗留项清单（台账/buglist/roadmap 主控记账素材，均不改本尊）

1. **台账行素材**：T23-T3 终验+文档轮闭环（8bf20864）：QD1 修前红证 10/10 归档
   （`t23t3_m8_red.log`，铁证②红侧全格闭环）；MO9 收口（missing_list Map 臂+3 单测，
   红腿翻绿 `M9_REBIND_MAP_GREEN`，修复路真身 audit 归零+重开穿新路径）；终验 13 格
   25/25 腿 PASS（`loop/t23-final/`）；门禁 libtests 3055（+3）/guards 246/stage 572/
   operators 18 全绿；book 新章挂链；QD2 D4 更正。
2. **buglist 素材（无新立票）**：
   - **A11（buglist:469）增补证据建议**：覆盖域 rebind 粘性两面已真机刻画——①活世界
     在 rebind→reopen 窗口内粘旧拼法（`t23t3_mo9_rebind_map_green.log`：live map
     wet.bsn+layered 0）；②本域 `scene.save` 发射重写后文档（wet2 落盘），A11 原票
     「save 回写旧路径」的形态未在 MaterialOverrides 域复现——按组件域差异增补进
     A11 票正文，修复时对照；
   - **MO8**：维持记档（book 已注记自清）；「延迟一帧再判」可选收口无人认领，继续
     挂 open-challenges 一句话；
   - **MO9**：本任务收口，buglist 无条目（T2 报告记档缺陷已修，台账在案即可）；
   - **book 微修票素材（新，⚪）**：`book/src/user-guide/asset-references.md` 的
     「A field holds a reference when its type is a `Handle<T>`（or a list of them）…」
     在 MO2 后有了例外（两覆盖层的 materials 值与 `GltfSource.path` 也是审计引用）——
     本轮改动面纪律未动既有章，留一句话微修票。
3. **roadmap**：T23 三任务（T1 建设/T2 真机矩阵/T3 终验+文档）全闭环，可勾选。
4. **30 秒清单素材**：正式落位=book「The 30-second tour」五条（与 T2 QA §七-6 草稿
   同源定稿）。

## 九、给 QA 的注意事项

1. 终态证据 `loop/t23-final/` 为 PHASE=all 单日志形态（console-all.log 含各相 done:
   行；editor 窗日志 editor-all-1..5 按相递增）。warn 判数照旧偏移差分（MO8 口径）。
2. M9 绿腿判据=文档面（audit 计数）；`t23t3_mo9_rebind_map_green.log` 内 live map/
   wears 即 A11 粘性面读数，**不要**把它当 MO9 未修的证据（文档已改写、重开已穿新）。
3. `loop/t23-final-attempt1/` 是被判据更正取代的首窗（§三-附注）；其
   `t23t3_mo9_rebind_map_red.log` 文件名与内容语义不符，以终窗 green 档案为准。
4. 红证复跑：`loop-mac/t23t3-red/m8-red.sh`（仓外），需先 checkout 12c0f9f1（脚本
   自带断言）；迭代 console（v1/v2）同目录在案。
5. `t23-live.sh` 默认参数仍完整复现 T2 口径（OUTDIR=loop/t23-live、REPORT_TAG=t23t2）；
   终验用环境变量切档，两代证据互不覆盖。
