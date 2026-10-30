# T15 终验 QA 报告：任务 3（收官段，接管形态）+ T15 整体终验（只验不修）

> 验收对象：分支 `loop/t15-animation` @ **be4aed9c**（基线 main=47a9f39c+T1/T2 合入；程序提交
> =T15-T3 接管完成）。程序报告：`loop/reports/t15-t3-report.md`（首节有接管如实注记）。
> 前置：T15-T1 QA PASS（t15-t1-qa.md，附放行条件三项全部在 T2/T3 兑现）、T15-T2 QA PASS
> （t15-t2-qa.md，AN10 回流已在 T3 开场吸收）。
> T3 diff 亲核：**产品面恰 2 文件**（`src/lib.rs` +69/−10 AN10 双件、`tests/stage/
> animation_graph.rs` +115 两件新测）；T15 全弧（6f170325~1..be4aed9c）产品面 12 文件
> +733/−40（modules.json+modules.rs/scaffold lib/animation_graph_card/module_picker/
> project_modules/xtask/src lib.rs/animation_cards.rs/animation_graph.rs），零场景格式变更、
> 零协议变更、零新 plugin。
> QA 手段：**Mac 六门亲跑**（串行后台脚本 `loop/qa/t15t3-qa-gates.sh`，全程未设
> RUST_BACKTRACE，门前 df=67Gi、`ps` 复核零遗留进程、门链独窗——中途亲查 9 个匹配进程全为
> integration 自身测试件）＋**门后定向三腿**（A6 隔离/bind doctest/stage 动画 37）＋AN10
> 源码亲读＋fixture 盘上亲验＋T3 真机证据链全文核对＋book 四文件亲读。QA 归档
> `t15t3qa_*.log` 10 件。

## 〇、结论

**PASS（T15-T3 接管形态 + T15 整体，含 roadmap T15 可勾选建议）**——六门亲跑 5 绿＋
integration 唯一红=A6 件（**QA 独立复现：5405 跑 5404+同件同签名 prefab_lifecycle.rs:714
三试全败＋隔离绿 2.917s**，定案口径放行；本轮与程序轮逐位吻合）；AN10 修复源码/红绿/盘上/
双捕获四层终核成立（§二）；book 四文件逐项过（§三）；验收句三铁证各有独立证据且 T3 在
AN10 修复后的盘上净态上补了 direct/staged 两通道 parity 复跑（§四）；AN1-AN7 结案清单全绿、
零破坏回归面绿（§五）；**接管形态裁定=前任产出全量保留+主控代笔门禁可复现**（§六）。
**偏差 0 🔴 + 0 🟡 + 6 ⚪（§七）**——最重的一条是归档完整性瑕疵（前任 AN10 红证文件 0 字节+
两条补跑声明无归档日志，QA 均已亲跑补齐），不动摇裁决。

## 一、Mac 全量门亲跑（权威口径，最终树 be4aed9c）

| # | 门 | 命令 | QA 亲跑结果 | 归档 |
|---|---|---|---|---|
| 1 | 格式 | `cargo fmt --all -- --check` | **CLEAN**（exit=0，日志 0 字节） | `t15t3qa_fmt.log` |
| 2 | 单测 | `cargo test --workspace --lib --features dylib` | **exit=0**；58 套件全 ok；**scaffold teaches `89 passed` 行亲点**；`test result:` 行逐条无缺 0 failed | `t15t3qa_libtests.log` |
| 3 | fast | `cargo xtask fast` | **2981 run: 2981 passed, 0 skipped**（exit=0；T15 专属三测亲见 PASS：AN7 `the_animation_tools_are_built_into_every_editor` @(486/2981)、catalog `the_animation_module_carries…` @(1933/2981)、teaches 新测在案） | `t15t3qa_fast.log` |
| 4 | **integration** | `cargo xtask integration` | **5405 run：5404 passed，1 failed**（exit=1，Summary 1699.997s）——唯一红=`jackdaw::prefabs prefab_lifecycle::prefab_file_change_triggers_reload`，3 试全败（17.6/15.7/20.1s），panic 同签名 `watcher reloaded prefab; v2 should be in world. Got ["v1"]` @ **prefab_lifecycle.rs:714 = A6 存量票原签名**；**零 nextest 重试自愈 flake、非 A6 失败为零**；**AN2 腿链内亲见 PASS**（`animation_scene_load a_loaded_scene_plays_its_default_state` @(3063/5405)）；badge 集成三件链内 3/3（:4230-4232） | `t15t3qa_integration.log` |
| 5 | docs | `cargo doc --no-deps --workspace` | **exit=0**；warning 面 **17 条与 T14 基线归档逐字同**（diff 为空）——见 §七-5 对程序轮 20 条的裁定 | `t15t3qa_docs.log` |
| 6 | scaffold_e2e | `cargo nextest run --profile ci -p jackdaw --test scaffold_e2e` | **PASS 146.675s**（exit=0；与程序轮 148.98s 同档） | `t15t3qa_scaffold_e2e.log` |

**门后定向三腿**（QA 独立）：

| 腿 | 结果 | 归档 |
|---|---|---|
| A6 件隔离跑 | ✅ **1/1 PASS（2.917s）**——与全套件红构成「红跟随二进制内并行负载」定案形态 | `t15t3qa_a6_isolated.log` |
| bind doctest 单包 | ✅ **exit=0**（`cargo test -p jackdaw_bind --doc`，1 passed）——同时补上程序报告声称但未归档的复跑日志（§七-3） | `t15t3qa_doctests_bind_rerun.log` |
| stage 动画回归腿 | ✅ **37/37**（`--test stage -E 'test(/animation/)'`；35 既有+AN10 新 2 件——「零破坏回归面」+AN10 锚一次收口） | `t15t3qa_stage_animation.log` |

**程序归档交叉复核**（接管五门抽核）：fmt 0 字节、clippy 双包日志 0 warning 行（仅
Checking/Compiling+Finished）、libtests teaches 89、fast Summary `2981 passed, 0 skipped`、
integration Summary `[1646.042s] 5405 run: 5404 passed, 1 failed`（唯一红 A6 同签名）、
scaffold_e2e `SCAFFOLD_EXIT=0`（148.979s）、docs `DOC_EXIT=0`——与 t15-t3-report §四门禁表
逐项一致，无隐瞒。**warn 形态扫描（QA 独立）**：我的 libtests/fast 全文扫描——libtests 仅
2 条 thumbnail 负路径测试件（broken.gltf/marker.bsn「could not be photographed」，既有归因），
fast 的 15 处 WARN 命中全为测试名含 warn+clippy 命令回显，**零动画域缺陷形态**；T3 真机
console（editor/game 双份）扫 `cannot apply|UnresolvedTypes|holds no|could not be read|
does not include this module` 全 0。**计数核对**：fast **2981**=T2 基线 2981（T3 零 fast 侧新增——stage 新件归 integration 档，
与 AN2 落位决策一致）；integration 5402（T1 收官）→**5405**（+3 分解=AN7 单测 1 件随 lib
目标计入+stage 新 2 件；inspector 三件 T1 已在 5402 内）——逐位吻合无隐藏件。**磁盘**：
门前 67Gi/门后 65Gi；**RUST_BACKTRACE 全程未设**；结束零残留进程（亲查 0）。

## 二、AN10 修复终核（T3 唯一产品改动）→ **核实成立，建议关闭**

| 层 | QA 终核 | 判 |
|---|---|---|
| **源码·登记排除** | `src/lib.rs` `register_animation_entities_in_ast` 亲读：查询族加 `Without<crate::animation::graph_doc::GraphCanvasPart>`，doc 注释把语义定界写明（画布持久形态=.animgraph.bsn 文件；混合图 clip 子节点照旧注册） | ✅ |
| **源码·存量清洗** | 新系统 `drop_leaked_graph_canvas_entities`（`.after(drop_imported_clip_entities)`，注册序亲读）亲读：查询=GraphNode∥Connection **且带 `AstNodeRef`**（只判文档链接实体——开着的画布节点从不带此件，不受扰）；父链过滤=parent 有 `AnimationBlendGraph`→保留、无父/父非 clip→despawn（走 `despawn_scene_entity`）；**排除面定界正确**（混合图 clip 子节点保留/画布工作实体清除/用户动画组件零触碰——过滤器只匹配 GraphNode/Connection 两型） | ✅ |
| **GraphCanvasPart 定义域** | `graph_doc.rs:147-149`「Marker on everything the Graph window spawns」+三处插入点亲读（graph_root/wires/nodes 全为画布自产件；画布 node 挂 ChildOf(graph 根) 而非 clip 下）——`Without` 排除不会误伤用户实体 | ✅ |
| **stage 新 115 行** | 两件新测亲读+亲跑（我的 stage 腿 37/37 含之）：①`the_open_graph_canvas_keeps_its_nodes_out_of_the_scene_document`（存档断言无 GraphNode/Connection+画布仍画满 2 态=「排除的是文档不是画布」）；②`a_document_holding_leaked_canvas_nodes_loads_clean_and_saves_without_them`（**前置断言泄漏节点确在 AST=测试内建 mini-red**；泄漏件被清/混合图 clip 子节点存活/重存不回写/blend 节点留档四断言） | ✅ |
| **盘上 fixture（QA 亲验今态）** | 项目+dist 双份 × scene.bsn/anim.bsn/graph.bsn 共 6 件 **GraphNode 全 0**；`assets/graph.bsn` 现文=#Rig+全路径 AnimationGraphRef+Armature，画布节点零残留 | ✅ |
| **purge 真机腿** | `t15t3_an10_purge_console.log`：`PURGE_BEFORE leaked_nodes=6 graphref=1` → 编辑器打开（修复版）→save→`PURGE_AFTER leaked_nodes=0 graphref=1`+`AN10_PURGE_PASS`；**编辑器日志行 `Scene saved to …/assets/graph.bsn`（22:58:28Z）与时戳互证**；归档 `t15t3_an10_purge_graph.bsn` 亲读=0 画布节点+ref 完整 | ✅ |
| **游戏通道 cannot-apply=0 双捕获** | `t15t3-channels.sh` 亲读：把 **staged 与 direct 两通道 flow 都指到曾泄漏的 graph.bsn** → `STAGED_UP leak_warns=0`+`DIRECT_UP leak_warns=0`，终行 `STAGED_LEAK_WARNS=0 DIRECT_LEAK_WARNS=0`；两通道归档日志亲读零 GraphNode/cannot-apply 行；红相对照=同窗 `staged-run.log`（07:04:40，6+6 条泄漏 warn 原文在档） | ✅（红相捕获的源文档归属有一处归档含糊，§七-2） |

## 三、book 核对（方案 §四-T3-2 书单+T2 QA 回流条款）

`book/src/user-guide/animation.md`（190 行新章）逐项亲读：

| 书单项 | 落点 | 判 |
|---|---|---|
| 七能力词导览 | Library 片段选择/Timeline/Graph 三面板节+预览三通道节+Loop/transition/`then` 节+Parameters 节 | ✅ |
| 双模型教学（set vs animgraph+何时用哪个） | 「Two ways to author states」+选择指引（small cast→set；conditions/blends→graph） | ✅ |
| 模块开关教学（AN1 附带面 T3 义务） | 「First, the module」：off by default 理由/`jd new --modules animation`/无模块时「names the unregistered types in its log」→开模块即修——与 AN7 修复后语义（editor 面内置）一致 | ✅ |
| 坏引用双面（badge+运行态 warn 原文） | 「When a reference is wrong」两形态，badge 文案与 Game 面板条均引原文（含可用 clip 全列表） | ✅ |
| AN8 全路径写法 | 「Hand-editing scene text」：`jackdaw_animation_runtime::graph::…` vs crate root，re-export 短式装载失败的机制一句 | ✅ |
| hero.glb 指引 | 「deliberately the smallest legal glTF, handy as a template」（生成器在 loop/ 不入库，章内表述为正确的仓内形态） | ✅ |
| AN5 边角注记 | 「Play-in-editor keeps the editor viewport alive…Stop hands the stage back」 | ✅ |
| M7 循环口径（T2 QA §六-5） | 「sampling the state name across a longer window than the clip — it holds」 | ✅ |
| SUMMARY 位置/交叉引用 | SUMMARY.md:29 恰在 Player Controller 后；animation.md 内链 player-controller/game-ui/scene-management/remote-debugging/configuration；player-controller.md 回链+configuration.md 模块表 +animation 行 | ✅ |
| open-challenges 改写 | diff 亲读：「Started in, not finished」→「authoring-and-game loop is closed…open depth = retargeting between rigs and richer blend shapes beyond the 1D blend」+挂链 | ✅ |

## 四、验收句三铁证终态——独立性判定

| 铁证 | 终态 | 独立性判定 |
|---|---|---|
| ①待机↔行走↔跳跃可配 | **独立成立** | 编辑器可配半边=M1/M2 全 operator 链+组件读回（T2，QA 邻证）；游戏运行半边=M3/M4 数值断言（T2 `l5_set_witness`+staged 采样，QA 曾 fresh-boot 独立复现）；授权路径盘上终态亲验（modules.json animation 条目+fixture jackdaw.toml `animation=true`+hero.glb 三 clip 在位 sha=00825bdb…）。两面证据互不依赖 |
| ②编辑器预览=游戏运行 | **独立成立（AN2 正主）** | T2 四通道 parity（editor/pie/direct/staged 折叠序列 `[idle,walk,idle,jump,idle]` 三三一致，QA 独立复现过 direct 全序列）+**T3 在 AN10 修复后的净盘上补跑 direct/staged 两通道**（`t15t3_parity_{direct,staged}_manual.json` QA 全文亲读：8 样本序列两通道一致，walk 循环持有 since 2.03-2.05s>1.0s clip、三处交叉淡出 `transition` 字段在窗、jump one-shot `then` 回落全在档）+门禁层 AN2 显式腿在程序轮与 QA 轮 integration 双双链内 PASS。AN10 修复只减游戏侧噪音、不动播放语义——T3 复跑与 T2 证据不冲突互证 |
| ③坏引用有提示 | **独立成立（AN10 修后 warn 面纯净）** | 作者态=M8 badge 三形态（T2 QA 亲机 ui_tree 逐一读回原文）；预览态=M9 双形态带时戳 warn；运行态=M10 Game 面板条目（截图亲览+log 行）——三提示面各自独立成证；**AN10 修复后**T3 真机 console 双份+双捕获文件扫描 cannot-apply/UnresolvedTypes=0，warn 面不再被画布噪音淹没（AN10 修复的正外部性） |

## 五、QA 放行清单对照（方案任务验收标准逐条）

| 条目 | 裁定 |
|---|---|
| T1/T2/T3 验收全绿 | T1 QA PASS（四建设红转绿+六门绿，放行条件三项：AN7 已修/AN7 行入 warn 协议/AN2 勘误入档+book 措辞照改——逐条兑现在案）；T2 QA PASS（M1-M14 14/14，M3/M6 独立复现+M8 亲机）；T3=本轮（§一/§二/§三） |
| AN1 结案 | catalog animation 条目盘上亲读（runtime_features `[animation]`+provides+prefixes，default 关=「no rigs links neither」保持）；catalog 测试+teaches 双测我的 fast 日志亲见 PASS；fixture 绿态在盘 |
| AN2 结案 | `xtask/src/main.rs:165` `ran && animation_scene_load()` 亲读；腿在程序轮+QA 轮两次 integration 链内 PASS；T1 QA 勘误（integration 一直有隐式覆盖）已按口径入 book/报告措辞 |
| AN3 结案 | `set_reference_problems`+badge 形态（T1 QA 源码级亲读在案）；集成三件我的 integration 链内 3/3（:4230-4232）；M8 三形态+全 good 零噪音双验收口 |
| AN4 结案 | hero.glb fixture 在位（1,676B，T1 时戳未变=字节未动）；三 clip 名与 anim.bsn 三态逐字对齐（T1 QA 已做 GLB 结构+生成器字节级复核） |
| AN5/AN6 记档 | AN5=book 注记+M12 mid-PIE 写读在档；AN6=各报告门禁表按实数记（stage 35→37 演进如实） |
| AN7 关闭 | 修复臂+一测（T2 QA 四面实机复证）；我的 fast 日志 AN7 测试 PASS @(486/2981)；T3 真机 console 扫「does not include」=0 |
| 「既有动画系统零破坏」回归面 | stage 动画 4 文件 **37/37**（我的腿亲跑，含 R1 修复面邻域）；runtime 两 crate 测试族在 fast lib 全绿；guards/keyframe_undo 在我的 integration 全绿（唯一红=非动画域 A6 件）；fast 2981 与 T2 基线严丝合缝（T3 零 fast 侧新增——stage 新件归 integration 档，与 AN2 落位决策一致） |
| buglist/roadmap/台账纪律 | buglist 在 T15 弧内仅被 T2 收官提交触碰（9313b7a4 主控立账 A8/A9+A7 并账=合规动作）；A6/A7/A8/A9 四票均未打钩=正确（T15 未修其中任何一票）；roadmap T15 未勾（留主控合入）；台账 progress.md 含接管形态如实行（diff 亲读） |

## 六、接管形态裁定（双签核）

1. **前任产出全量保留——亲核成立**：T3 产品 diff 恰 2 文件且与前任声明的工作面逐一对应
   （src/lib.rs AN10 双件+stage 两测）；book 四文件、五门日志（fmt/双 clippy/libtests/fast+
   被打断前 A6 红的 integration 前段）、purge/channels 真机件全部在提交内，无被覆盖/改写
   痕迹（对照报告 §一-§三描述逐件指认）；接管补跑件（integration 后段/doctests/docs/
   scaffold_e2e/报告）与前任件在归档命名上可区分。
2. **主控代笔门禁抽核复现——超额达成**：任务要求抽 1 门亲跑；QA 实际**全量六门亲跑**，
   fast（2981/2981）/integration（5405 跑 5404+唯一红 A6 同件同签名三试全败）/scaffold_e2e
   （146.7s PASS）/docs（warning 面=T14 基线）/fmt/libtests 全部复现归档结论——代笔日志
   无一虚报。
3. **两条代笔声明原缺归档，QA 亲跑补齐且均属实**：bind doctest 单包复跑（报告称 exit=0 无
   日志）→QA 亲跑 exit=0；A6 隔离复跑（报告称 2.578s 绿无日志）→QA 亲跑 1/1 绿 2.917s。
   归档缺口补上（§七-3），声明本身可信。
4. **接管叙事如实**：报告首节/提交信息/台账三处一致注记「前任被看门狗终止、未提交未写
   报告、接管全量保留」；与 T11-T3 先例同形。**裁定：接管形态合格，双签通过。**

## 七、偏差与记档分级（QA 视角，全部 ⚪ 不阻塞）

| # | 项 | 处置 |
|---|---|---|
| 1 | **前任 AN10 红证文件 0 字节**：报告 §一引 `t15t3_an10_red_stage.log` 为红证，实测 0 字节（疑被看门狗截断或命令输出未落盘）。红绿链不塌：T2 QA 独立红（盘上 6 节点 mtime 链+游戏通道 warn）在档+新测②内建 mini-red 前置断言+channels 红相 staged-run.log 12 条 warn 原文在档 | 归档完整性瑕疵记档；本报告 §二以三层替代红证为准 |
| 2 | **红相 staged 捕获的源文档归属含糊**：`loop/t15-live/staged-run.log`（07:04:40，12 条泄漏 warn）与 dist graph.bsn mtime（06:58:28=purge save 同秒）无法从归档唯一互证（purge 后盘面已全净，无第二现场）；绿相链（purge before/after+编辑器 save 日志行+双通道 leak_warns=0+QA 亲验 6 份场景副本全净）不受扰 | 记档；不影响 AN10 判定 |
| 3 | **两条补跑声明无归档日志**（bind 复跑/A6 隔离）——QA 均已亲跑补档（`t15t3qa_doctests_bind_rerun.log`/`t15t3qa_a6_isolated.log`），声明属实 | 已闭合 |
| 4 | 措辞两处：①「stage 新 115 行 **5 锚**」实为 2 个新测试函数（37=35+2，锚=测试内断言）；②`m7-transition-witness.txt` 内容为 `M7_TRANSITION_WITNESS none`（脚本腿 AN9 抖动红相），报告偏差-2称「补强件」——T3 过渡语义的实证在两份 manual parity JSON 的 `transition` 字段 | 措辞勘误随本报告入档 |
| 5 | **docs「CLEAN」措辞与 warning 面**：程序轮归档 20 条 warning（vs T14 基线 17）；**QA 同树复跑=17 条与 T14 基线逐字同**，+3（triggers.rs 冗余链接/game_export.rs 未闭合 HTML 标签/jackdaw 计数 10→11）为该轮 rustdoc 增量伪影——两文件 T15 弧零触碰（git log 亲核），**零新 warning 面成立**，「CLEAN」按 T14 既有口径（exit=0+无新面）可读，但字面不严谨 | 措辞勘误；两条 warning 载体（triggers.rs:22/game_export.rs:325）为存量瑕疵，随缘修 |
| 6 | 工具面注记：`t15t3-gates.sh:16` 的 scaffold_e2e 带 `--features dylib` 而报告 §四写不带 features（归档日志头有 bevy_dylib 编译=疑带参跑）；QA 复跑用不带 features 形态同样 PASS 146.7s——两形态皆绿，无实质 | 记档（A7 邻域工具票可顺手统一） |

## 八、最终裁决与 roadmap 建议

- **T15-T3 验收标准（方案 §四-T3）**：12 格终态——T2 矩阵 14/14 为基，T3 在 AN10 修复后
  复跑 direct/staged parity+purge/channels 真机腿+stage 37 ✅；book 新章+SUMMARY+交叉引用+
  open-challenges 改写 ✅（§三）；模板教学评估=book 参数模板段已带（章内 Rust 代码块）✅；
  buglist 预期无打钩 ✅；台账已记、roadmap 未动（主控合入时写）✅；终验门全量+AN2 档位腿 ✅
  （§一）。
- **AN10 结案**：源码定界正确+红绿钉死+盘上净态亲验+游戏通道双零——**建议关闭**（连同
  T2 QA 的修向 a 预期完全兑现：序列化排除+存量清洗，无 book 阻断注记需要——修复已落地，
  book 教的是修后正确语义）。
- **T15 整体（T1/T2/T3）**：验收句三词（可配/预览=游戏/坏引用有提示）铁证全数独立在案
  （§四）；缺陷收口——🔴 AN1/AN2 全修、🟡 AN3/AN4/AN7/AN10 全修、⚪ AN5/AN6 记档、
  AN8→A8 票、AN9→A9 票（复现先行，未修不打钩）；六个能力词「验成晶」定性全程成立，
  建设面最小化（全弧产品 12 文件 +733/−40，零新系统）。
- **VERDICT: PASS——T15 整体闭环。roadmap T15（第 29 行）建议可勾选**，闭环注记建议含：
  三铁证独立在案（M1-M14 真机矩阵+四通道 parity `[idle,walk,idle,jump,idle]`+badge 三形态/
  PIE 日志双面）；AN1/AN2/AN3/AN4/AN7/AN10 修（buglist 无打钩项=全部为 T15 新 AN 系）；
  integration 5404/5405 唯一红=A6（QA 独立复现同签名+隔离绿，定案口径）；接管形态双签
  合格；A8/A9 立账待修；⚪ 偏差六项不阻塞。
- 主控合入路径照旧 `--no-ff`（be4aed9c 单提交）；台账 T15 行、roadmap 勾选由主控合入时写
  （本轮 QA 零产品/台账/buglist/roadmap 触碰，工作树仅新增 QA 归档 10 件+门链脚本+本报告）。

## 九、用户 30 秒清单（book 章自带 30 秒检查的实机版）

1. **开模块**：File > Modules 勾 Animation→让它重写游戏的 Cargo.toml（游戏侧能播的前置）。
2. **配动画**：放一个带骨架的 glTF→选中→Animation 面板 Library：选一个 clip→**Add as
   state**——视口立刻播 default 态。
3. **切状态**：`animation.set_state` 切另一态：视口带过渡切换；**Play**：游戏播同样的状态、
   同样的切换（编辑器所见=游戏所得）。
4. **坏引用有提示**：把某状态要的 clip 名改错——还没按 Play，Inspector 动画卡该行已经
   挂出写明修法的 badge；改回即消失。

## QA 会话产物索引

- 门禁六门+定向三腿：`loop/reports/t15t3qa_{fmt,libtests,fast,integration,docs,
  scaffold_e2e,a6_isolated,doctests_bind_rerun,stage_animation}.log`+`t15t3qa_gates_progress.log`；
  脚本 `loop/qa/t15t3-qa-gates.sh`（串行，unset RUST_BACKTRACE）。
- 核验对象：`loop/reports/t15-t3-report.md`+归档 t15t3_* 30 件（五门日志/purge 三件/channels
  件/manual parity JSON/warn 捕获）；`loop/qa/t15t3-{an10-purge,channels,gates}.sh` 亲读；
  T1/T2 报告与 QA+buglist A6-A9+roadmap 第 29 行+progress 台账接管行；AN10 源码两件
  （src/lib.rs register 排除+drop 系统；graph_doc.rs GraphCanvasPart 定义域）；stage 新测
  全文；book 四文件+SUMMARY；fixture 盘上 6 份场景副本+hero.glb+flow 双份。
- 进程收尾：QA 复查零 jackdaw/t15-anim/nextest 残留进程；数据卷 65Gi；门链独窗
  （运行中亲查匹配进程全为 integration 自身测试件）；RUST_BACKTRACE 全程未设；
  工作树除 QA 归档新增外零触碰。

—— QA agent，2026-10-30
