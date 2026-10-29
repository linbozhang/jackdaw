# T15 任务 2「真机矩阵轮」QA 验收报告

> 分支 `loop/t15-animation` @ **894f4074**（验收对象=程序报告 `t15-t2-report.md` + 归档
> `t15t2_*` 31 件 + 脚本 `loop/qa/t15-live.sh`）；QA 亲跑日志/亲机证据归档 `t15t2_qa_*`
> 16 件（§〇）。裁决：**PASS**，建议放行 T15-T3；QA 新发现 **AN10 🟡**（§四，回流主控），
> AN8/AN9 给出立账定性建议（§五），脚本工具债两条随 T3 处理（§六）。全程未设
> RUST_BACKTRACE；零产品代码/buglist/台账改动；结束已清理编辑器/游戏进程并还原 fixture
> （flow start_scene=anim.bsn、anim.bsn 的 Walk_Loop 在位）。

## 〇、QA 亲验清单（本报告的证据基座）

| # | 动作 | 结果 | 归档 |
|---|---|---|---|
| 1 | 七门亲跑（fmt/双 clippy/物理双包/libtests/fast/AN2 腿/stage 过滤腿） | 全 exit 0（§一） | t15t2_qa_fmt/clippy_ws/clippy_physics/libtests/fast/an2_scene_load/stage_animation.log + qa_gates_progress.log |
| 2 | AN7 消费面静态核（module_picker.rs 亲读+四个消费者 grep） | 修在唯一汇聚点，四面全被覆盖（§二） | — |
| 3 | AN7 消费面亲机核：launcher Extensions 页 ui_tree walk | Animation 行=「built into this editor」；唯一 "not in this editor" 属 Navmesh（合法） | t15t2_qa_walk_extensions.txt |
| 4 | AN7 消费面亲机核：New project 页 ui_tree walk | Animation chip=「tools built in」；同上 Navmesh 合法 | t15t2_qa_walk_newproject.txt |
| 5 | AN7 消费面亲机核：打开 fixture 工程的编辑器日志扫描 | 「which this editor does not include」= **0 行**（QA 自己的 boot 日志） | t15t2_qa_editor_project_open.log |
| 6 | M8 三形态 badge 亲机复核（bad.bsn→BadSet/BadGraph） | 三形态原文逐一在 live ui_tree 读回（§三 M8 行） | t15t2_qa_walk_badge_forms12.txt / _form3.txt + t15t2_qa_shot_badge_context.png |
| 7 | M3 set 路数值断言独立复现（fresh direct boot） | bind 读回 `idle`→写 `walk` 读回→2.5s 后仍 `walk`，与 l5_set_witness 逐字吻合 | t15t2_qa_parity_direct.json 同批记录（会话内） |
| 8 | M6/L6 direct 通道 parity 独立复现（fresh boot+parity_driver.py） | 折叠序列 `[idle,walk,idle,jump,idle]` 复现；walk 循环 2.04s、三处交叉淡出在档、one-shot 回落在档 | t15t2_qa_parity_direct.json |

> 备注：QA 亲机段用 wrapper 脚本带 `DYLD_LIBRARY_PATH` 启动编辑器（直接 export 被
> 沙箱剥离，dyld 报 libstd 缺载——工具面注记，与产品无关）；亲验后进程全清。

## 一、门禁（QA 全部亲跑，最终树 894f4074，warm cache 下全程约 7 分钟）

| 门 | 命令 | 结果 | 日志全文复核 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | exit 0 | 0 字节 ✓ |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | exit 0 | 0 warning/error 行 ✓ |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | exit 0 | 0 warning/error 行 ✓ |
| 单测 | `cargo test --workspace --lib --features dylib` | exit 0 | 全 result 行 0 failed；**teaches 套件 `89 passed; 0 failed` 行亲点** ✓；唯一 2 处 "panicked" 命中=test 名 `…_not_panicked`（T1 同款归因） |
| fast | `cargo xtask fast` | exit 0 | **2981/2981 passed, 0 skipped**（基线 2980+AN7 一测 ✓）；全文 0 FAIL/error 命中；**AN7 新测亲见 PASS**（`jackdaw module_picker::tests::the_animation_tools_are_built_into_every_editor` @ (485/2981)） |
| AN2 腿 | `cargo nextest run --profile ci -p jackdaw_runtime --features animation --test animation_scene_load` | exit 0 | **1/1 PASS**（0.105s） |
| 受影响域 | `cargo nextest run --profile ci -p jackdaw --features dylib --test stage animation` | exit 0 | **35/35**（452 skipped） |

与程序报告 §三逐项吻合；基线计数（fast 2980→**2981**、teaches 89）与 T1 收官数严丝合缝。
磁盘门前 74Gi/门后 72Gi，未触警戒。

## 二、AN7（本任务唯一产品改动）→ **核实成立，建议关闭**

- **修复语义亲读成立**：`catalog_has_module` 的 animation 臂（module_picker.rs:43-48）在
  extension/multiplayer 两条旧路之前短路返回 true，注释把理由写明（工具面无 extension 无
  cargo feature，游戏侧 runtime 才挂模块）。全仓 grep 证实四个消费面**全部**经由这两个
  函数：①项目开启 warn（project_modules.rs:227-248→editor_has_module）②New Project
  chip（new_project.rs:320→catalog_has_module）③Extensions 页（extensions.rs:146→
  editor_has_module）④File>Modules picker 行注（module_picker.rs 内部）——修在唯一汇聚点，
  无漏网面。对照 catalog：animation 条目确无 extension 字段（T1 已核），arm 语义正确。
- **一测亲跑**：本 QA 的 fast 日志亲见 PASS（见 §一）。
- **四面证据核**：
  | 面 | 红证 | 绿证 |
  |---|---|---|
  | 状态栏/日志 | t15t2_an7_red_editor.log 的三句全错 warn 亲读在档 | QA 自己开工程的 boot 日志 **0 行**（亲机）+ 程序双相 WARN_SCAN an7_lines=0 |
  | File>Modules picker | 红 ui_tree 亲读（2 处 "This editor does not include this module"） | 绿截图亲览：Animation 勾选、行下仅正常描述、Navmesh 的 warn 合法保留 |
  | Extensions 页 | T1 QA 原报告四面亲读 | **QA 亲机**：Animation=「built into this editor」 |
  | New Project chip | 同上 | **QA 亲机**：Animation=「tools built in」 |
- 判定：四面全绿且两面由 QA 实机重证，**AN7 关闭**。

## 三、M1-M14 逐格复核（抽 4 格原文全读，其余证据指认）

| 格 | 程序判定 | QA 复核 | 备注 |
|---|---|---|---|
| M1 | ✅ | **过**（组件面） | console 现场行亲读：三态恰 Idle_Loop,Walk_Loop,Jump；set_state×4 写后组件读回逐次吻合。注意语义=**wanted-state 组件读回**（程序原文如此，非播放态读回）；编辑器相 log 有 3 条 `animation set has no state named` warn（20:45:17-19，写早于 set 重编译的腿内时序，读回不受扰）——腿自身红相，归因在档。视口姿态截图 4 张 **md5 全同**（a0ccb63e…，偏差⑧属实，视觉面不依赖此） |
| M2 | ✅ | **过** | ref 组件读回+graph 文件 grep 现场行在 console；hero_graph.animgraph.bsn 落盘亲读（Speed/Jump 参数、entry idle） |
| M3 | ✅ | **过+独立复现** | `t15t2_l5_set_witness.json`（bind idle→写 walk→hold 2s）亲读；**QA 在 fresh direct boot 上独立复现同三元组**（bind `idle`→写 `walk` 读回→2.5s 仍 `walk`）——T1 硬条件③（world.query 数值断言）达成且经 QA 独立证实 |
| M4 | ✅ | **过** | L10 console 行亲读（staged 树/manifest/sha=y）+staged 通道采样在档 |
| M5 | ✅ | **过**（断言面） | L4 console：preview(walk)→pause→stop→set_state(Jump) 读回 `"Jump"`（借还后 set 应答）。视口截图同帧（同 M1 注） |
| M6 | ✅ | **过+独立复现**（AN2 正主） | 四通道捕获件全文亲读：editor 5 样本（jq 指纹=shell 采样器）、pie/direct/staged 各 8 样本（python json.dumps 指纹=parity_driver.py）；折叠序列三三一致；**QA 亲跑 parity_driver.py（fresh boot）direct 通道复现 `[idle,walk,idle,jump,idle]`**——parity 判定不再单靠程序自捕获 |
| M7 | ✅ | **过**（语义注一条） | 三处交叉淡出 `transition={from:…,remaining_secs}` 在 pie/direct/staged 全部在档（0.04-0.14s 窗口内逮住）；循环活证=walk 态持续采样 since 2.02-2.12s>Walk_Loop 1.0s 恒 `walk`+one-shot jump 回落对照。**注**：方案原文的「since_secs 回绕」（clip 游标回绕）未采——since 为图级状态时长本就不回绕；循环机制由 H 侧 runtime 测试（RepeatAnimation::Forever）+此处状态持续证据合成，接受但记注 |
| M8 | ✅ | **过+亲机复证**（AN3） | 三形态原文在程序 walk 断言+**QA 亲机 ui_tree 逐一读回**：`animation state \`ghost_clip\` wants clip \`No_Such_Clip\`, and \`models/hero.glb\` holds \`Idle_Loop\`, \`Walk_Loop\`, \`Jump\`` / `animation state \`off_range\` names source 2, and the set lists 2 sources` / `no graph file named \`animation/nope.bsn\` in this project`；全 good 卡零行（L8_GOOD_CARD_CLEAN）。**视觉面缺口保持如实**：程序截图被 Recovered Work 模态遮挡（亲览属实）；QA 复拍亦未取得 badge 渲染帧（Inspector 卡折叠+`jackdaw/screenshot` **同帧 flake 被 QA 复现**——60s 间隔两张 md5 全同）→ 视觉面待截图通道修复（§六-4），语义面以 live ui_tree 双验收口 |
| M9 | ✅ | **过** | 双形态 warn 带时间戳在档（missing.glb could not be read / holds no clip named …only [Jump,Idle_Loop,Walk_Loop]） |
| M10 | ✅ | **过**（AN3 运行半） | 截图亲览：PIE LIVE 态 Game 面板 warn 条原文带可用 clip 全列表；editor-game.log 两处 warn 行在档（红相），绿相面板 0 行+盘上 clip 已复原（QA 亲验 anim.bsn 现态） |
| M11 | ✅ | **过** | QA 亲跑 stage 过滤腿 35/35；R1 修复面在 guards 族经 fast lib 覆盖 |
| M12 | ✅ | **过** | console：sha stable=y；mid-PIE 写 idle 读回 `"idle"`（AN5 记档点落实）；Stop 后写 walk 读回 `"walk"`。注：L9 首个 set_state（PIE 前）warn「Rig names no entity」未落地（log 20:46:35）——腿判定不受扰（中段/Stop 后两次写读成对），脚本打磨项（§六） |
| M13 | ✅ | **过** | console：scene.bsn set 与 graph.bsn ref 各 save→reload 后逐字同；但见 §四 AN10——该 save 同时把图节点实体写进了文档 |
| M14 | ✅ | **过**（T1 证据引用） | T1 红档日志亲读：真机游戏实跑的两条**点名全路径**的 unresolved warn（embedded asset type …not registered + cannot apply …type not in the registry）在档；不重跑红态接受（2 分钟冷编成本，红档可对照） |

**矩阵结论**：14/14 判定成立；其中 M3/M6 经 QA 独立复现，M8 经 QA 亲机复证。

## 四、QA 新发现 AN10 🟡（回流主控，只记不修）

**动画图画布节点实体泄漏进场景文档：Graph 窗口里授权的 `anim.state` 画布节点以
`jackdaw_node_graph::graph::GraphNode`+`SceneNodeId` 实体形态被 scene.save 写进 .bsn 场景；
一切游戏通道装载该场景时逐条 warn 并 fail-soft 丢弃（每载 6+ 条），编辑器↔游戏文档契约
在动画授权流上破口。**

- **盘上实证（QA 亲读 fixture）**：`/Users/zhanglinbo/workspace/loop-mac/t15-anim/t15-anim/
  assets/graph.bsn`（含 .bak）在 `#Rig`（AnimationGraphRef+Armature）之外序列化了 **6 个**
  `GraphNode{node_type:"anim.state"}`+SceneNodeId 根级实体；mtime 链（.bak 04:46:30→
  final 04:47:01）落在编辑器相 M13 save 窗口——泄漏源=图画布的工作节点驻留场景 world，
  场景保存时一并落文档。
- **三通道游戏侧实证**：direct-run.log:14-31 与 staged-run.log:13-22 各 6 条
  `embedded asset type 'jackdaw_node_graph::graph::GraphNode' is not registered …fall back
  to a default handle` + 6 条 `cannot apply …: type not in the registry`。Rig 本体的
  AnimationGraphRef 全路径在册不受扰——**parity/M2-M14 判定不受影响**，但这是靠被测对象
  恰好干净才成立：任何用户照 T3 book 教学走一遍「开 Graph 窗口→存场景→Play」即复现。
- **warn 扫描盲区（工具面一并记）**：常备 warn 扫描只 grep 编辑器日志（editor-$PHASE.log），
  direct/staged 游戏进程自己的 stdout 日志不在扫描面——本轮泄漏因此漏检。T3 终验门建议
  把游戏通道日志纳入扫描。
- **编号**：按方案约定自 AN7 续编，AN8/AN9 已被程序占用，故记 **AN10**。
- **修向（供主控裁）**：a) 场景序列化排除图画布工作集（SceneNodeId/graph 工作实体不入
  文档，画布态只活在 .animgraph.bsn 资产）——治本；b) 游戏侧 catalog 对 editor-only 类型
  降噪（已知编辑器件静默跳过）——治标。倾向 a；T3 book 动画章在修复落地前须加注记。

## 五、AN8/AN9 立账材料复核（QA 定性建议，供主控裁定）

### AN8（图族类型路径必须全路径）→ **建议立票，独立成票**

- 机制代码级核实：apply.rs:394-404 按 `get_with_type_path` **精确串**查注册表；图族三件
  定义在 `graph.rs`（GraphRef :243 / Params :276 / Playback :332）+crate 根 re-export
  （lib.rs:40）——re-export 路径不在册，亲验成立。
- 活体红证在档且 QA 亲读：debug-editor.log / debug-editor2.log 各 3 条
  `cannot apply 'jackdaw_animation_runtime::AnimationGraphRef': type not in the registry`。
- **QA 补强一条**：`jackdaw_bsn::catalog` 同时发 remedy 行「…rebuild the project so the
  editor picks up its types」——该指引**误导**（重建救不了文档里的错路径），AN8 的用户
  可见面比程序报告写的更糟一档，票内应一并修（remedy 文案或路径归一化）。
- pie_projection:61 允许名单是全路径——程序报告对本条的勘误**采纳**。
- 定性：与 AN9（服务面稳定性）、N13（PIE drain panic）、A7（驱动工具债）互不重叠，
  **独立票**；修复向建议 a) apply/catalog 按 re-export 归一化（治本）为主，doc 注记为辅
  （T3 book 必写全路径写法）。

### AN9（编辑器/游戏 BRP 面间歇失效）→ **建议立票（复现先行），独立成票**

- **在档证据充分的部分**：脚本上下文游戏侧 world.* 成批读空的完整现场（console-game.log
  全文：首个 world.query 成功 `id=724v0 states=idle,walk,jump`→其后 get_components 全空；
  pie/direct/staged 三通道一致；同窗编辑器口与 L7 ui_tree、L10 盘检全正常）+ 同批调用
  数分钟后人工静默全绿（parity/l5 捕获件，QA 指纹/时序核通过，§三）。m7 witness 脚本版
  `none` vs 人工版三通道 transition 在档，同一断言两代结果——现象真实性成立。
- **在档证据缺口（如实）**：服务侧指纹（空 body 200 的 `expected value at line 1 column 1`、
  瞬时 method-not-found、rpc.discover 仍列全方法）均为程序在会话内所见，**未落盘**；
  立票材料以「复现路径」为主张：连跑 `bash loop/qa/t15-live.sh game` 对比人工静默逐腿。
- **QA 补强的相关性数据**：QA 的独立复现（direct 通道两轮、含 parity_driver 全序列）全程
  **零编辑器进程在跑**，所有读写成顺——而程序失败窗的截图底栏在档可见「building the
  game / game ready (642 types)」（编辑器开工程即后台构建）。支持「编辑器后台构建核挤 +
  大响应体优先被吃」的工作假说，可作为票内第一个定向实验。
- 定性：**独立票**（不是 N13 的 drain panic、不是 A7 的对话框/行定位，也不是 N12 的域界
  ——域界是查不到，AN9 是查得到但服务面间歇哑），与 A7 记邻居关系（同属真机驱动工具
  稳定性域）。MCP 优先原则：立票后先补**可观测性**（BRP 服务端请求日志/耗时打点）再修，
  避免继续盲测。

### 双轨记账（脚本腿红/人工绿）→ **记账口径站得住**

- CAPTURE 完整性：四通道捕获件格式指纹与各自生产者吻合（editor=shell jq 采样、三个游戏
  通道=parity_driver.py 的 json.dumps）；标签序列与驱动器代码逐一对应；mtime 时序自洽
  （editor 04:46 → pie 05:42:41 → direct 05:43:30 → staged 05:46:45 → verdict 05:48:24）。
- 时序可信：walk-loop-b since≈2.02-2.12s 与 sleep 2 吻合；jump-early since 0.36-0.40 与 0.4s
  窗吻合；jump-held 落在回落 crossfade 窗内——手写无法自然造出这组互相咬合的非整浮点。
- 编辑器通道另有**同期 console 行**（console-editor.log 的 L3_PARAM_DRIVES_PREVIEW 行）与
  归档 JSON 逐字吻合——不是事后补写的孤立文件。
- 脚本红档如实保留（summary-game.txt 三 FAIL 原样），判定以行为结论为准——**接受程序
  口径**，且 QA 已用独立复现把最大的一环（M6 parity）补成双源。

## 六、QA 新增偏差/工具面注记（分级）

| # | 事项 | 级别 | 处置建议 |
|---|---|---|---|
| 1 | AN10 图节点泄漏（§四） | 🟡 产品邻域 | 回流主控裁修复面；T3 book 注记兜底 |
| 2 | `t15-live.sh` 编辑器通道采样器误用：l3_param_drives_preview（:721/726/731/747）调 `sample_graph_game`（15702 游戏口）于无游戏的编辑器相——**按提交版重跑会写入 MISSING 行、L6 编辑器序列比对永不匹配**；在档 editor 通道数据来自采样编辑器 world 的运行版（同期 console 行为证） | ⚪ 脚本债（A7 邻） | T3 复跑前修：该腿改 editor-world 采样（graph_state/comp_of 族） |
| 3 | L9 首 set_state 未等场景绑定落地（「Rig names no entity」warn） | ⚪ 脚本债 | 写前加绑定等待/读回 |
| 4 | `jackdaw/screenshot` 同帧 flake（程序偏差⑧ + QA 复拍复现：60s 两帧 md5 同）；launcher 相截图 capture never landed | ⚠️ 工具面（MCP 优先：修截图通道） | 归 A7/AN9 工具家族；badge 视觉面与视口姿态的「像素级」证据待通道修复后补拍 |
| 5 | M7 循环活证的「since 回绕」原案未采（§三 M7 注） | ⚪ 口径注记 | T3 book 写循环语义时按「状态持续>clip 长+one-shot 对照」口径 |
| 6 | Bash 工具沙箱剥离 DYLD_LIBRARY_PATH，wrapper 脚本内 env 可绕 | ⚪ 环境注记 | 本报告 §〇 备忘 |

## 七、验收句三铁证——独立性判定

| 铁证 | 判定 | 依据 |
|---|---|---|
| ①待机↔行走↔跳跃可配 | **独立成立** | 编辑器可配（M1/M2 组件+图链）与游戏运行（M3/M4 数值断言）两面各有独立证据；QA 在 fresh boot 上独立复现了游戏侧 set+graph 两路。不依赖编辑器单面自证 |
| ②编辑器预览=游戏运行 | **独立成立**（编辑器半边为程序同期 console 行+QA 指纹/时序核，游戏半边 QA 独立复现） | 四通道折叠序列一致；QA 复现 direct 通道全序列含 M7 三面；编辑器通道的同期 console 行使「事后补写」假设不成立。注：QA 未重跑编辑器参数驱动链本身（成本考量，证据双源已足） |
| ③坏引用有提示 | **独立成立** | 三个提示面各自独立成证：作者态 badge（三形态 QA 亲机 ui_tree 读回）、预览态 warn（双形态带时戳在档）、运行态 Game 面板条目（截图亲览+log 行）。视觉渲染帧受截图通道所限，以 live ui_tree 双验收口 |

## 八、裁决与放行建议

**裁决：PASS。** 依据：七门亲跑全绿且与程序报告逐项吻合；M1-M14 全 14 格核实成立，
其中 M3/M6 由 QA 独立复现、M8 亲机复证；L1-L10 十腿状态与程序口径一致（L5×2/L6 脚本红
=AN9，人工绿经指纹/时序/复现三重核）；AN7 关闭（四面中两面 QA 实机重证）；AN8/AN9
立账材料充分（各附 QA 补强）；三铁证独立性成立。程序报告如实披露的 9 条偏差经逐条复核
全部属实、定级恰当。

**放行 T15-T3，附建议**：
1. **AN10 先裁**（修 or 立票+book 注记）——它咬的是 T3 book 动画章的主教学路径（「开图
   窗口→存场景→Play」），裁决应在 T3 开场前落。
2. T3 book 动画章必写：图族类型**全路径**写法（AN8）、坏引用双面（badge 文案原文+Game
   面板条原文）、模块开关教学（联动 AN7 已修面）。
3. T3 终验门把 **direct/staged 游戏通道 stdout 纳入 warn 扫描**（本轮 AN10 漏检面）。
4. `t15-live.sh` 两处脚本债（§六-2/3）随 T3 复跑前顺手修或并入 A7 账。
5. 截图通道（同帧 flake+launcher 相 capture never landed）按 MCP 优先立项，补齐 badge
   渲染帧与视口姿态的像素级证据后，M8/L8 的「视觉面」才算全闭合（现以 live ui_tree 验收
   口放行）。
6. N13 记数 11（editor 6+game 5，归档样本 5+5 亲点）；磁盘全程未触警戒；RUST_BACKTRACE
   全程未设；QA 结束已清理全部编辑器/游戏进程并还原 fixture（flow start_scene=anim.bsn、
   anim.bsn 无 No_Such_Clip 残留）。

—— QA agent，2026-10-30
