# T15-T3 实施报告：AN10 修复 + book 动画新章 + 终验准备（接管完成）

> 任务：`loop/plans/t15-animation.md` §六 T3 节；分支 `loop/t15-animation`（基线 main=47a9f39c）。
> **执行形态说明（如实）**：前任程序 agent 完成了 AN10 修复+红绿证据+book 四文件+五门日志后被
> 看门狗（600s 不活跃）终止——**未提交、未写报告**。主控接管：核验在盘工作（本报告 §一-§三）、
> 补跑被中断的 integration 与未跑的 doctests/docs/scaffold_e2e（§四）、写本报告、提交。
> 接管对前任改动**全量保留**（T11-T3 先例），未改动任何前任产出。

## 一、AN10 修复（主控裁定：T3 开场吸收）

**缺陷**（T15-T2 QA 发现）：Graph 画布节点（`GraphNode(anim.state)`+`Connection`+`SceneNodeId`）
被 `scene.save` 泄漏进场景文档——fixture graph.bsn 盘上 6 个画布节点实证；游戏每载 6+
"cannot apply / not registered" warn 并 fail-soft 丢弃。

**修复**（`src/lib.rs` +59/−10，两件）：
1. **登记排除**：`register_animation_entities_in_ast` 不再把画布工作实体（GraphNode/Connection）
   注册进 JSN AST——画布的持久形态是 `.animgraph.bsn` 文件本身，场景副本是双重一次性状态。
2. **存量清洗**：新系统 `drop_leaked_graph_canvas_entities`（after drop_imported_clip_entities）
   ——装载带泄漏的旧文档时 despawn 文档链接的画布实体（`AstNodeRef`+GraphNode/Connection 且
   父非 AnimationBlendGraph clip；**混合图 clip 下的节点是场景内容，保留**——语义定界写在 doc 注释）。

**红→绿证据**：
- 红证：`loop/reports/t15t3_an10_red_stage.log`（stage 测试红：画布节点进文档）+
  T2 归档 graph.bsn 盘上 6 节点+游戏通道 cannot-apply warn。
- 绿证：`loop/reports/t15t3_an10_green_stage_animation.log`（stage 套件绿，含新 115 行
  `tests/stage/animation_graph.rs`——`the_open_graph_canvas_keeps_its_nodes_out_of_the_scene_document`
  等 5 件画布语义锚）+`loop/reports/t15t3_an10_purge_{editor,console}.log`+
  `t15t3_an10_purge_graph.bsn`（清洗后文档 0 画布节点）+`loop/reports/t15t3_animation-warn-lines-game.txt`
  （游戏通道 cannot-apply=**0**）。
- Graph 功能回归：画布重建/undo 跟随/定义恢复锚全绿（`a_node_taken_off_the_canvas_takes_its_state_and_wires_with_it` 等）。

## 二、book 文档

- 新章 `book/src/user-guide/animation.md`（SUMMARY 排 Player Controller 后）：七能力词导览
  （片段选择/Library/Timeline/Graph/预览三通道/循环/状态切换+then/过渡/参数驱动）、
  **模块开关指引**（jd modules 开 animation=AN1 附带面 T3 义务）、坏引用双面（badge+运行态 warn）、
  hero.glb 生成器指引、「预览=游戏」设计意图。
- `open-challenges.md` 动画行改写：「Started in, not finished」→「authoring-and-game loop is
  closed…open depth = retargeting between rigs and richer blend shapes beyond the 1D blend」。
- 交叉引用：player-controller.md、configuration.md。

## 三、记账项（T2 QA 回流③，⚪ 落报告不修码）

pack/save_scene overwrite 边缘 staging 缺席；Inspector 批量落盘合并；PF9 Spelled 臂 folder/canonical
残余缝隙——均已在线（A7/A8/A9 票+book 注记覆盖），此处不重复展开。

## 四、门禁（接管补跑进行时/结果）

| 门 | 结果 | 归档 |
|---|---|---|
| fmt | CLEAN（0 字节，exit=0） | `t15t3_fmt.log` |
| clippy 全仓 `--all-targets --features dylib` | exit=0 | `t15t3_clippy_ws.log` |
| clippy 物理双包 | exit=0 | `t15t3_clippy_physics.log` |
| `cargo test --workspace --lib` | exit=0（58 套件全 ok；teaches 89） | `t15t3_libtests.log` |
| `cargo xtask fast` | **2981/2981 passed** | `t15t3_fast.log` |
| `cargo xtask integration` | 前任被看门狗打断（无 Summary）；**主控续跑**：**5405 跑 5404 过+1 失败=唯一红 A6 件（同签名 prefab_lifecycle.rs:714，隔离复跑 1/1 绿 2.578s=定案口径达成；非 A6 失败为零）**，Summary 1646s | `t15t3_integration.log` |
| doctests | bind dyld rpath 家族第 8 次目击（EXIT=101）→**单包复跑 PASS**（`cargo test -p jackdaw_bind --doc` exit=0） | `t15t3_doctests.log` |
| docs | **CLEAN**（EXIT=0） | `t15t3_doc.log` |
| scaffold_e2e | **PASS 148.98s**（nextest 单测试形态 `cargo nextest run --profile ci -p jackdaw --test scaffold_e2e`——xtask 无顶层 scaffold_e2e 命令，SDK_BINARIES 成员经 heavy 档执行的等价直跑） | `t15t3_scaffold_e2e.log` |

warn 形态扫描：AN10 修复后游戏通道 cannot-apply=0（双捕获文件）；N13 记数文件
`loop/reports/t15t3_n13-count.txt`；门链与真机不同窗、全程未设 RUST_BACKTRACE、df 门前检查。

## 五、偏差

1. 接管形态本身（报告由主控代笔，门禁证据链为亲跑+前任日志复核混合——QA 终验对全部日志做
   全文复核即为双签）。
2. 前任 M7 过渡见证（`t15t3_m7-transition-witness.txt`）与 parity 手动复跑 JSON
   （`t15t3_parity_{direct,staged}_manual.json`）为真机补强件，AN9 间歇面下的双轨口径与 T2 相同。
3. 其余待 QA 终验对照（A6 口径/AN9 现象如实记数）。
