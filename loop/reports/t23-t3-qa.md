# T23 任务 3 QA 报告：终验 + 文档轮独立复核

> 复核对象：分支 `loop/t23-material` @ **41f8c24f**（T3 程序轮），基线 **8bf20864**（T2
> closeout）。QA @ 同 commit 41f8c24f 独立复核（非转录）；平台 macOS arm64。
> 程序报告 `loop/reports/t23-t3-report.md`；方案 `loop/plans/t23-material-override.md`
> §四-T3；任务来源 `loop/reports/t23-t2-qa.md` §七放行六点。
> **裁决：PASS（零阻塞偏差，1 条 QA 微修建议）——放行合入 main + roadmap T23 勾选。**
> RUST_BACKTRACE 全程未设；门前 df 79Gi；QA 门链（13:28-13:49）与 QA 真机复跑
> （13:49-13:59，pkill 后另窗）不同窗；归档前缀 `t23t3qa_*`，真机复跑证据自建
> `loop/t23-final-qa/`（`loop/t23-live{,-qa}/`、`loop/t23-final{,-attempt1}/` 未动）。

## 一、门禁数字对照（程序归档 vs QA 亲跑）

| 门 | 命令 | 程序归档（t23t3_*） | QA 亲跑（t23t3qa_*） |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | EXIT=0 | **EXIT=0**，零 Diff（`t23t3qa_gates_fmt.log`） |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | EXIT=0 | **EXIT=0**，零 error/warning 行（`t23t3qa_gates_clippy_ws.log`） |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | EXIT=0 零行 | **EXIT=0** 零行（`t23t3qa_gates_clippy_phys.log`） |
| libtests | `cargo test --workspace --lib` | 3055/3055（59 二进制） | **3055/3055**（59 二进制，逐名点验见下） |
| guards | `cargo nextest run --profile ci -p jackdaw --test guards` | 246/246（258.4s） | **246/246**（265.3s） |
| stage | `cargo nextest run --profile ci -p jackdaw --test stage` | 572/572（556.1s） | **572/572**（564.3s） |
| operators 散布 | `cargo nextest run --profile ci -p jackdaw --test operators scatter_ops` | 18/18（13.9s） | **18/18**（14.0s） |

**3055 拆账独立复核**：QA log 59 个 `test result` 行求和 = 3055、0 failed；其中
`inspector::missing_list` 模块单独亲跑 = **5/5**（3 件 MO9 新单测逐名 ok：
`an_override_map_reference_rebinds` / `an_override_map_rebind_moves_values_only` /
`an_override_map_rebind_stays_on_its_own_component_and_field`，+AR11 旧 2 件）——
3052 基线 +3 吻合，且 QA log 与程序 log 各自独立产出同名 3 件 ok 行。
AN2 腿免跑理由核：`git diff --name-only 8bf20864..41f8c24f` 中
`jackdaw_runtime/`、`crates/` 命中 **0** 文件——改动确不触 runtime 侧，免跑成立
（T2 的 AN2 1/1 在案即可，QA 未补跑，与本任务指令门清单一致）。

## 二、复核八项逐项结论

### 1. diff 面亲核 —— ✓ 与程序报告改动清单逐项吻合，无越面
`git diff --name-only 8bf20864..41f8c24f` 共 97 文件：
- **产品源 1 文件**：`src/inspector/missing_list.rs`（+203/-1，恰 3 hunk：Map 臂
  17 行含注释、`use jackdaw_bsn::{BsnPatch, BsnValue}` 导入 1 行、测试 ~187 行）；
- book 2 文件：`material-overrides.md` 新章 + `SUMMARY.md` 恰 1 行挂链；
- `loop/qa/t23-live.sh`（+57/-34，QA 亲读全文：OUTDIR/REPORT_TAG 参数化、M9 判据
  移文档面、修复路 `scene.save` 为主 python 外改降 fallback、sticky 档名参数化、
  头注释——**纯 harness，零产品行为改动**；默认值仍完整复现 T2 口径
  `OUTDIR=loop/t23-live`、`REPORT_TAG=t23t2`）；
- `loop/reports/t23-t2-report.md` D4 一句话更正（QD2，见 §三-8）；
- 程序报告本体 + `t23t3_*` 归档 10 件 + `loop/t23-final/` 38 文件 +
  `loop/t23-final-attempt1/` 40 文件。
未动：buglist/台账/roadmap/fork/Cargo.toml/Cargo.lock/`loop/t23-live{,-qa}/`（mtime
仍在 T2 时点）——全部与报告 §七清单一致。

### 2. 门禁亲跑 —— ✓ 七门全绿，数字逐门吻合（§一表）

### 3. MO9 修复面源码级亲读 —— ✓ 语义自洽 + 3 单测亲读亲跑 + 红绿翻转成立
- **源码**（missing_list.rs:603-612 亲读）：Map 臂在 `matches_component`
  （type_path 尾段比对，:551-570）与 `field.name == finding.field`（:577）双重门内
  才到达；只改写「值为 `BsnValue::String` 且拼写全等 `finding.reference`」的**值**；
  `for (_, value)` **键不触**；嵌套值**不下潜**。
- **与 audit 接线自洽**：audit 侧 `reference_audit.rs:294` 经
  `material_overrides::takes_string_path`（:27-33：`MaterialOverrides`/
  `InstanceMaterialOverrides` + field `materials`，及 `GltfSource.path`）收录；
  `strings_under`（:367-370）对 Map **只收值串、键从不收**——与 Map 臂「值改键不动」
  精确对称。两层组件 `materials` 均为 `BTreeMap<String,String>`
  （crates/jackdaw_scene_types/src/types.rs:990/998），值恒为 String，故「不下潜」
  与 audit 的「任意深度下潜」在覆盖域**可达集恒等**，无漏改面。四元组接线
  （component/document/entity/field）与 rebind 触发链（AuditFinding →
  rewrite_ast_reference）一致，M5 归档 finding JSON 即实证。
- **3 单测亲读亲跑**：parse 真身（`parse_bsn_text` 构 AST，非纸面锚）；测试 2 以
  「键拼成路径样字符串」验证键不误伤、测试 3 验证换层 finding 与无匹配不改写——
  语义覆盖与臂规则一一对应。模块跑 5/5（§一）。
- **红绿对账**：红=T2 `t23t2_mo9_rebind_map_red.log`（rebind 后 audit
  **count=1**——8bf20864 树无 Map 臂，红真）；attempt1 首窗（修复后 build，audit
  **count=0** 但被活世界判据误冠 `_red` 名，见 §二-6）；绿=`t23t3_mo9_rebind_map_green.log`
  （**audit 即归零**+live map 旧拼如实录为 A11 面）+终窗 console-all.log
  `M9_REBIND_MAP_GREEN_PASS` 与 `M9_REBIND_PASS`（save 写 wet2→重开穿 wet2→audit
  **total=0**，修复路真身走编辑器自己的门）。脚本新判据只在 `audit_count != 0` 时
  才落 `_red` 档——`M9_REBIND_MAP_BLIND→GREEN` 翻转以文档面判据成立，且判据面
  本身已按 T2 QA §七-2 要求落码。

### 4. QD1 红证复核 —— ✓ 修前静默十腿全证 + build 断言机制属实 + 截图亲看
- `t23t3_m8_red.log`：build=`12c0f9f143e8…`，10/10 腿 PASS；静默量化（`material
  override:` 新增 0 / `no part of it wears` 0 / audit `{"count":0}` / ui_tree 无
  material override / 水穿 2→0 / 条目永存 `{"Rock":"materials/deep.bsn"}` /
  PX 1.018%→1.018% 视觉同幅回穿）与程序报告 §一表逐腿吻合。
- **断言机制亲读**（loop-mac/t23t3-red/m8-red.sh:324-331）：`git rev-parse HEAD`
  非 `12c0f9f1*` 即 `RED_ABORT` exit 2——站错 commit 跑不出红证；另 12c0f9f1 经
  `git merge-base --is-ancestor` 核为 8bf20864 之祖（=T23 方案提交、T1 前的 main）。
  且日志内容本身即修前指纹（报告面/文案在该 build **不存在**、audit 对 override
  全盲）——修复后 binary 不可能产出此形，红证产自 12c0f9f1 修前代码双保险成立。
- 两张 PNG 亲看：dressed 照两部件清晰水蓝（water=2），after-rename 照同两部件
  明显回穿本色（白/灰）——静默回穿的视觉见证成立。
- 红态纪律：log 尾注「red leg archived before leaving the detached build」；脚本
  三轮迭代的 console 留档在 loop-mac/t23t3-red/（v1/v2），产品行为零改动。
- **铁证②红侧 M8 格闭环**：MO1 自此红（执行型 10/10）绿（T2 reimport 相四态+终验
  M8 格 4 腿）双证齐全——T2 QA §三对账表唯一缺口补上。

### 5. 13 格终态抽核 —— ✓ 全链亲读 + warn 归因亲数 + M1 格真机复跑独立 PASS
- `console-all.log` 亲读全文（89 行）：六 `done:` 行 + `ALL done`；**25 腿并集全
  PASS、全文 0 个 FAIL**；M1（PX 2.468%/0.058%、staged holders=2 精确回读
  g-holders.json、layered=2 全在 Mesh.Rock/water=1 在 Mesh.Trim 与 gb-*.json 一致）、
  M5（恰 1 warn 原文 `m5-warn-line.txt` + audit 四元组 JSON 逐字段=报告）、M6
  （doc 恰 1 处 deep2 + sticky 档 `t23t3_rename_sticky.log` 亲读：live map 粘旧+
  water 1→0+1 条 unresolved）、M8（恰 1 条点名 warn 原文在档）、M9（§二-3）、
  M10（破包 6/2/0 零 panic 游戏日志零报告）、M13（索引拒 1+缩略图新名）逐格
  与报告 §三表吻合。脚本断言亲读（M6 须盘上 deep2、M7 须 named=7/water=2/新缩略图）
  与 PASS 行对应。
- **M12 warn 归因亲数**（偏移差分口径的独立复核）：QA 以全 pattern
  （9 词表）直接数 editor-all-1..5 全文 = **19/6/16/13/11/0，合计 65**——与
  console 六相行、程序报告、**T2 逐相同形**三者全吻合。分类亲数：`material
  override:` 52 条（7+6+15+13+11）+ `material.override:` 12 条（11 RUN_OP INFO
  回显 + 1 MO4 拒绝）+ 1 条 M13 索引拒（`materials/deep.bsn no longer holds a
  type this project knows`，editor-all-3:62）= 65，与报告 52/12/1 拆账一致。
  `UnresolvedTypes`/`holds no material`/`cannot-apply`/`panicked` 全部 0；staged
  两日志 `material override:` 0。`walk-all.json` 为末窗 UI 树（156 节点，全文无
  material override 文本=收窗状态栏安静）。
- **QA 真机复跑（chains 格，另窗）**：`T23_OUTDIR=loop/t23-final-qa
  T23_REPORT_TAG=t23t3qa` 跑 prep+chains，T3 build（`cargo build -p jackdaw -p jd`
  亲构建）——**9/9 腿 PASS**（L1 五链+L2 四穿+M11+MO4+M4），PX 2.464%/0.054%，
  warn 19 条同形（RUN_OP 回显+MO4 拒+打包瞬态 stale 轮，归因同族），归档
  `loop/t23-final-qa/`（console-chains.log/warn-scan-chains.json/walk/截图/offset）。
  M1 重点腿终态复证独立成立。

### 6. attempt1 披露核 —— ✓ 归档与 §三-附注口径一致
- attempt1 console 行 57-58：判据写在活世界面（`M9_REBIND_MAP_BLIND_PASS`），其
  `t23t3_mo9_rebind_map_red.log` 内容=audit **count:0** + live map 旧拼——正是
  披露所说「误名档案，内容本身如实录得 audit=0+live map 旧拼，是 A11 面第一手
  记录」；首窗 0 FAIL、六 done、warn 19/6/16/13/11/0（25/25 亦全 PASS）与披露
  「首跑亦全 PASS」一致；文件内容未被改写（40 文件原样，含误名 2 件）。
- 脚本考古：t23-live.sh 本轮 diff 纯 harness（§二-1），无产品行为改动混入；
  attempt1 与终窗共用 `loop/t23-final` OUTDIR（warn-scan 路径同名），故首窗证据
  需另目录保存——归档处置与披露逻辑自洽。

### 7. book 章复核 —— ✓ 逐句对源码无技术错误，1 处括注过诺（QA 微修建议）
`book/src/user-guide/material-overrides.md` 亲读，逐项对源码：
- 三层：`MaterialOverrides`/`InstanceMaterialOverrides`（types.rs:988/996）；实例
  层赢+未覆盖键跟预制体（runtime `find_models_to_dress` instances 外层最后覆盖+
  测试 `an_instances_overrides_lay_over_its_models_and_leave_the_rest_to_it`）；
  「所见即所穿」（编辑器视口与游戏同一插件，报告面 editor-only——M10 证）。
- by-name：键=GltfMaterialName；无名不可寻址（MO4 拒绝原文与 mo4-response.json、
  operator 源码 :497-505 逐字吻合）。
- 换装三口同落一个 undo 命令：`SetMaterialOverrides`（EditorCommand，apply/undo，
  :327-411）——材质行 Pick/operator/浏览器 Apply 三口皆汇此；空 name=换全模型
  （`model_material_names`）、`material=""` 清条目（`materials.remove`）与
  `#[operator(id="material.override")]` 参数文档一致；预制体携带+散布带回
  （M4 格+scatter_ops 18/18）。
- 持久化/undo/导出/游戏静默注记：书句「the reporting, though, stays in the
  editor…no `material override:` lines」在场，与 MO1 设计（report_broken_overrides
  run_if Editor）及 M10 证据一致；undo 零假 warn（M11）；重导入幸存覆盖穿新件
  （M7）。
- 失效双态：路径断（warn 一次/heal 静默/再断再说+audit Missing 四元组）与键断
  （条目永存+恰一条点名 warn）——M5/M8 腿与 warn 原文（src/material_overrides.rs
  :102/:108）逐字对上；`material=""` 手清门在场。
- **MO8 自清注记**原文在场（:98-102「the warnings you see in the first moments
  after opening a scene are spawn-timing, and clear themselves」）。
- rebind 语义：「Rebind covers the override maps on both layers」与
  takes_string_path+Map 臂一致；tab 转 dirty、保存/重开落世界与终窗 M9_REBIND
  一致。**但**括注「(or at once, on the tab the scene is open in)」（:113）过诺：
  活世界并不随 rebind 即时更衣——第一手证据
  `t23t3_mo9_rebind_map_green.log`（rebind 后未重开 live map 仍 wet.bsn、layered
  **0**）与 `t23t3_rename_sticky.log`（M6 同族粘性）均反证「at once」面。语义
  应为「文档面即改、活世界待 save/reopen」（A11 面）。→ **QD-book（⚪ 微修）**：
  建议一句改写（如删括注或改为「the tab's document shows the new path at once;
  the parts wear it from the next save/reopen」），并入本轮已议的
  asset-references.md 微修票同批执行即可，不阻塞。
- 30 秒清单五条（:116-125）与 T2 QA §七-6 五条同源逐条对应；SUMMARY.md:18 挂链
  紧排 Materials & Textures 之后；交叉引用五章（materials-textures/prefabs/
  sprites-2d/assets/asset-references）文件均在 book/src/user-guide/ 实存。

### 8. QD2 更正核 —— ✓ 如实
`git diff` 亲读 `t23-t2-report.md` D4：原括注「门禁 stage 全绿含之」已改，新文
明言 **operators 档**（T2 门链 guards+stage 不含该档）+ QA 亲跑 18/18 + 归档
`t23t2_qa_scatter.log`，并留更正痕一句（「T23-T3 更正：本条原括注…不实」）。
`loop/reports/t23t2_qa_scatter.log` 在档（T2 轮 QA 产出）；本轮 QA 亲跑复证
18/18（§一）。

## 三、偏差清单

**程序偏差 Dx：无阻塞项。** 记录 2 条观察（不阻 PASS）：
- **D6（门径范围，预裁定）**：方案 §四-T3-4 字面「终验门：全量门（fast/integration/
  doctests/docs/scaffold_e2e）」未按字面全跑；本轮按任务指令门清单执行 7 门
  （fmt/clippy×2/libtests/guards/stage/operators 散布）——与 T2 QA 门径（§八）+散布
  增补档同源。属 T3 派单时的门清单预裁定，台账记一句即可，无需返工。
- **O1（harness 观察）**：PHASE=all 模式下 `warn-scan-all.txt` 被逐相覆盖，只留
  末窗（0 命中）；分窗数字由 console-all.log 六行保全，QA 已独立重数无歧义。
  后续 all 轮可将 `warn-scan-$PHASE` 命名一并参数化（harness 改进票素材，非必须）。

**QA 新立 QDx：1 条（微，不阻塞）**
- **QD-book（⚪）**：`material-overrides.md` rebind 段括注「(or at once, on the tab
  the scene is open in)」（:113）对活世界面过诺——rebind 后活世界粘旧拼法（A11
  面，第一手证据两件）反证即时不更衣。建议一句改写，与 asset-references.md
  一句话微修票同批落笔（均主控职权，QA 只供素材）。

## 四、裁决与放行建议

### 裁决：**PASS**

依据：①七门 QA 亲跑全绿且与程序归档逐门一致（3055=3052+3 逐名点验/246/572/18，
日志全文零行）；②diff 面亲核无越面、AN2 免跑理由实证（runtime/crates 零触）、
纪律（RUST_BACKTRACE 未设/df 79Gi/门与真机不同窗/进程清盘）全数成立；③MO9 修复
面源码级亲读语义自洽（audit 收集集与改写集恒等）、3 单测亲跑 5/5、红绿对账
BLIND→GREEN 在文档面判据上成立且判据已落码；④QD1 修前红证十腿+build 断言机制+
截图亲看全证，铁证②红侧闭环；⑤13 格 25/25 腿零 FAIL、warn 65 命中亲数
19/6/16/13/11/0 与 T2 同形、52/12/1 拆账复核一致、零意外 warn；⑥QA 真机另窗
复跑 chains 格 9/9 独立 PASS（M1 重点腿）；⑦attempt1 披露与归档一致、脚本纯
harness；⑧book 逐句对源码成立、QD2 更正如实。

### 放行建议：**放行**——合入 main + roadmap 勾选 T23（第 25 个任务）

遗留项归属素材评估（均主控职权，QA 只判素材是否够）：
1. **A11 票（buglist:469）增补素材：够**——两面真机刻画在档：①rebind 后活世界
   粘旧拼法（`t23t3_mo9_rebind_map_green.log`：live map wet.bsn+layered 0）；
   ②本域 `scene.save` 发射重写后文档（盘上 wet2），A11 原票「save 回写旧路径」
   形态在 MaterialOverrides 域未复现（组件域差异）；另有 M6 rename 粘性面
   `t23t3_rename_sticky.log` 与 attempt1 档案可引。
2. **MO8 维持记档：成立**——book 自清注记原文在场（:98-102）；「延迟一帧再判」
   可选收口继续挂 open-challenges，无新增证据需要。
3. **asset-references.md 一句话微修票：素材够**——目标句精确在位
   （`book/src/user-guide/asset-references.md:12`「A field holds a reference when
   its type is a `Handle<T>` (or a list of them)…」），MO2 后例外（两覆盖层
   materials 值+`GltfSource.path` 亦是审计引用）事实清楚；建议与 QD-book 同批。

## 五、QA 产物清单

- 门禁归档（亲跑）：`loop/reports/t23t3qa_gates_{fmt,clippy_ws,clippy_phys,
  libtests}.log`、`t23t3qa_guards.log`、`t23t3qa_stage.log`、`t23t3qa_scatter.log`
- 真机复跑证据（自建）：`loop/t23-final-qa/`（prep+chains 两相 console、editor
  log、warn-scan-chains.txt、walk-chains.json、mo4-response.json、截图×4、offset）
- 变更：仅本报告；产品代码/buglist/台账/roadmap/fork/既有归档零改动
