# T15 任务 1「缺口补齐轮」QA 验收报告

> 分支 `loop/t15-animation` @ **13e8d952**（验收对象=程序报告 `t15-t1-report.md` + 归档
> `t15t1_*` 13 件）；QA 亲跑日志归档 `t15t1_qa_*` 10 件。裁决：**PASS（附三项放行条件）**，
> 建议放行 T15-T2，前置吸收一个 QA 新发现 **AN7 🟡**（§四）。全程未设 RUST_BACKTRACE，
> 零产品代码/buglist/台账改动。

## 〇、裁决摘要

| 项 | 结论 |
|---|---|
| **裁决** | **PASS**——AN1/AN2/AN3/AN4 四件建设全部核实为真、红绿证据成立、六门全绿（integration 唯一红按 A6 已定案环境票口径放行，隔离绿在案） |
| **放行条件** | ① **AN7**（QA 新发现 🟡，§四）须在 T2 真机腿开跑前吸收（一行修+一测，主控裁定时点：T2 开场小修轮或回流 T1 补轮）；② T2 各腿 warn 扫描协议把 AN7 的项目开启 warn 行列入已知归因；③ **AN2 勘误**（§五）随本报告入档，T3 book/终验措辞照改 |
| **T2 fixture 交接状态** | 见 §七（绿态就绪，红态复现步骤在案） |

## 一、门禁（QA 全部亲跑，最终树 13e8d952）

| 门 | 命令 | 结果 | QA 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **CLEAN**（0 字节日志） | t15t1_qa_fmt.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | **CLEAN**（exit 0，0 warning/error 行） | t15t1_qa_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | **CLEAN**（exit 0，0 warning/error 行） | t15t1_qa_clippy_physics.log |
| 单测 | `cargo test --workspace --lib --features dylib` | **exit 0**；全 result 行 0 failed；scaffold teaches **89/89**（log :2714）亲点 | t15t1_qa_libtests.log |
| fast | `cargo xtask fast` | **2980/2980 passed, 0 skipped**；全文扫描唯一 "error" 命中=test 名（`error::tests::display_text_is_pinned` PASS）；5 个新测试逐条点名在案 | t15t1_qa_fast.log |
| integration | `cargo xtask integration` | **5401/5402 passed**，唯一红=`jackdaw::prefabs prefab_lifecycle::prefab_file_change_triggers_reload`（3 try 全败 @ tests/prefabs/prefab_lifecycle.rs:714:5，「watcher reloaded prefab; v2 should be in world. Got ["v1"]」）——**A6 同签名**（buglist :455-457 原文点名同文件同行号），按已定案口径「处置前 integration 该件放行」处理；**隔离亲跑 1/1 绿（2.47s，满载时 16-18s）**=典型满载挤压 FSEvents 预算形态 | t15t1_qa_integration.log / t15t1_qa_a6_isolated.log |
| AN2 新腿（隔离） | `cargo nextest run --profile ci -p jackdaw_runtime --features animation --test animation_scene_load` | **1/1 PASS**（QA 亲跑；本轮 integration 链内该腿因 A6 红 `ran && …` 短路未追加执行，但 integration 主跑内该测试本体已过，见 :3156 (3068/5402)） | t15t1_qa_an2_scene_load.log |
| badge 集成测试（隔离） | `cargo nextest run --profile ci -p jackdaw --features dylib --test inspector animation_cards` | **3/3 PASS** | t15t1_qa_an3_badge.log |
| jd 模块面（亲验） | `cargo run -p jd -- new … --modules animation` | **双向亲验**：开模块⇒Cargo.toml `features = ["animation","terrain","pie"]`+jackdaw.toml `animation = true`；`--no-modules`⇒Cargo.toml 零 animation+toml `animation = false` | t15t1_qa_jd_modules_smoke.log |

**门禁日志复核**（契约证据标准）：fmt 0 字节；双 clippy 0 warning；libtests 无 FAILED（唯一
"panicked" 命中=test 名 `…_not_panicked` ×2）、动画域 warn 形态 0 条（3 条 "could not read"
均为 PIE prebuild 负路径测试/viewport 坏档测试既有归因）；fast 全文复核无 error/FAILED。
**warn 归因**：lib 门零动画域 warn 与程序报告一致。**磁盘**：门前 121Gi/门后 120Gi，未触警戒。
**计数核对**：fast 2975→**2980**（+5：catalog 1+teaches 1+badge 单测 3）✓；integration
5394→**5402**（+5 lib+3 inspector 集成）✓——两基线计数与 T14 收官数严丝合缝，改动面清点吻合。

## 二、AN 逐条复核

### AN1 🔴 游戏侧授权路径 → **核实成立（1/3 消费面有缺陷，见 AN7）**

| 复核项 | 结论 |
|---|---|
| modules.json 条目形态 | **过**。`runtime_features:["animation"]`+`provides:["jackdaw_animation_runtime"]`+`component_prefixes`+requires 缺省（=空，与 navmesh/multiplayer 同形）；default 缺省=false，`physics` 仍唯一 default——「no rigs links neither」注释保持成立 |
| catalog 单测 +1 | **过**。`the_animation_module_carries_the_feature_that_plays_its_sets`（modules.rs:492）：feature 恰一/零 crate/零 requires/providing_crate 归属/detect 经 feature 识别，fast 内亲见 PASS |
| scaffold teaches +1 | **过**。`new_game_project_enables_animation_only_through_its_module`（scaffold lib.rs:3757）双向断言亲读；`template_runtime_features`（:2673）链亲读=模块 features+terrain/pie 兜底，animation 唯一来自模块 |
| 三面出项亲验 | **jd 面亲验双向过**（上表）；scaffold 面由 teaches 双向断言亲读过；**模块 UI 面有缺陷→AN7**（§四）：`editor_has_module("animation")` 恒 false，四面 UI 误报「编辑器不含此模块」 |
| 红绿证据 | **红证过**：两条通用 warn 均点名全路径 `jackdaw_animation_runtime::AnimationSet`（runtime「embedded asset type …not registered」+bsn::apply「cannot apply …type not in the registry」，源码 `crates/jackdaw_runtime/src/lib.rs:1461`、`crates/jackdaw_bsn/src/apply.rs:401` 亲读核实插值）。**绿证过**：同 fixture 开模块重建后双 warn 消失、绑定+default 态静默（坏 clip 必 warn 的反证形态成立）；fixture 盘面（jackdaw.toml `animation=true`+Cargo.toml features）亲读吻合 |
| 「remedy 不改文案」裁定复核 | **维持**。判据「是否点名类型路径」对两条实走 warn 均达标；catalog.rs UnresolvedTypes remedy（编辑器语境）确不走游戏侧（程序偏差④属实）。缺口=不指路模块开关，T3 book 一句覆盖即可；注意该指引与 AN7 修复联动（§四） |

### AN2 🔴 门禁层 → **核实成立（腿真实在档+亲跑绿），但前态表述需勘误（§五）**

- `xtask/src/main.rs` 亲读：`integration()` 末尾 `ran && animation_scene_load()`（:165），
  腿命令与报告一致（:172-188）；`fast()`（:35-65）fmt+core-deps+git-deps+clippy+`--lib`
  nextest，**不含该腿** ✓；`release-gate = fast+integration+heavy` 每次必过此腿 ✓。
- 腿隔离亲跑 **1/1 PASS**；测试本体亲读=真端到端（JackdawPlugin+BSN 场景文档+stand-in
  Gltf→断 `AnimationSetBound.player==Armature`+`AnimationTransitions::get_main_animation`
  =default 态在播）。
- **但**：「此前在一切常跑档位编译为空」**不成立**——见 §五勘误。

### AN3 🟡 作者态 badge → **核实成立**

- `set_reference_problems` 纯函数亲读：三态齐全（source 越界含 0 源特判文案/source 文件不在
  盘/clip 名不在该 source 且列全量可用 clip）；**「在盘未索引不报」边界亲读成立**
  （`clips_of` None 且 `on_disk` true→不报，:167-175）。
- badge 形态对照 bindings_card 先例（`src/inspector/bindings_card.rs:1345-1370`）亲读：同一
  组件族 `Text+TEXT_SIZE_SM+TextColor(TEXT_ERROR)+Hovered::default()+Tooltip::title`，连
  「A badge, never a gate」注释语义同源——**形态复刻属实**。
- 单测三件（纯逻辑，fast 内亲见 PASS）+集成三件（QA 亲跑 3/3）：集成测试走真实 inspector
  dispatch，badge 按 tooltip 渲染器同款 `(Tooltip,Hovered)` 查询读回——**可读性断言不是自说自话**。
- 红证复核：修前树跑的是缺席断言版测试（`…_says_nothing` ×2 通过=结构性双零），同日志内
  runtime warn `animation graph 'rigs/nope.bsn' could not be read` 在场——「运行态有 warn、
  作者态零提示」同屏成立。绿证 3/3 在案。
- 全 good 卡零噪音（第三件测试锚定）；badge 非 gate 与先例一致。

### AN4 🟡 hero.glb → **核实成立**

- 结构亲验（python 解析 GLB）：魔数/版本/总长、双 chunk 类型与长度、buffer 字节数全对；
  三动画名恰为 `Idle_Loop/Walk_Loop/Jump`；input accessor 均带 min/max（spec 必需+Library
  时长读法依赖）；节点 `Armature>Hips`、channel 全部 target node 1 translation——与
  fixture anim.bsn 的 `skeleton_root:"Armature"` 对齐。
- 生成器亲跑**字节级一致**（sha256 对比）→可重跑性成立；脚本带 OUT_PATH 参数，T18/T20 可复用。
- fixture anim.bsn 亲读：三态逐字对齐验收句（idle/walk 循环、jump one-shot `then: Some("idle")`
  演示回落）；jan 仍在 `assets/models/jan`（A 回落路径随时可用）。
- 绿腿静默证据复核：AN1 绿日志零 `wants clip` warn=三 clip 按名全部解析（反证形态成立）。

### AN5/AN6 ⚪ → 记档核

AN5（PIE 期间编辑视口照播）T2 M12/L9 记档点，本轮零改动正确；AN6 门禁表已按「任务相关门」
显式行落（本报告 §一），stage 动画实数 35（见偏差①）。

## 三、偏差 6 条裁定（逐条）

| # | 偏差 | QA 复核 | 裁定 |
|---|---|---|---|
| ① | 方案「stage 动画 69 件」实为 35 | QA 亲点四文件 `#[test]` 数：library 10+graph 8+markers 10+timeline 7=**35** ✓（程序 10+8+10+7 同数异序）；过滤腿 35/35 过 | **接受**。方案调研口径勘误，随台账勘误记；门禁表按实数记正确 |
| ② | badge 三形态截图未做，PX 归 T2 L8 | headless 断言强度亲验：精确文本+TEXT_ERROR+渲染器同款查询读回 | **接受，附硬条件**：T2 **L8 必须实际截到三形态 badge 行**（M8 红绿），未截到=T1 该项验收悬空 |
| ③ | AN1 绿活证提前落袋（机制半边） | 绿日志+fixture 盘面亲核成立；BRP 数值采样确未做 | **接受**：T2 **L5 必须补 `world.query` 数值断言**（default 态+写态跟随），此为 AN1 验收句的正主格 |
| ④ | UnresolvedTypes remedy 路径与方案描述有出入 | 亲读 apply.rs:401/runtime lib.rs:1461：两条 warn 均插值全路径，判据达标 | **维持程序裁定（不改文案）**；T3 book 写明两条 warn 原文+「开 animation 模块即修」指引，并与 AN7 修复联动措辞 |
| ⑤ | AN3 红证断言域锚在包装层 | 红档日志亲读：缺席断言测试通过（双零）+runtime warn 同屏，结构性成立；锚域差异如实披露 | **接受，红证有效**。不要求重锚（修前树已不存在，重建重跑纯属浪费）；两要素（双零+同屏）齐即可作 before 证据 |
| ⑥ | jd 二进制 dylib 失配（Abort trap 6） | T14 先例同款；QA 亲跑一律 `cargo run -p jd`（本轮 QA 自己首次误用参数被 jd 拒绝属用法错误非产品问题，已纠正归档） | **接受（工具面注记）** |

## 四、QA 新发现 AN7 🟡（回流主控，放行条件①）

**`editor_has_module("animation")` 恒为 false——模块 UI 三面+项目开启 warn 共四面误报
「编辑器不含动画工具」，与事实相反（动画作者面无条件编入编辑器）。**

- 根因（`src/module_picker.rs:39-50` 亲读）：`catalog_has_module` 只认两条路——catalog
  `extension` 字段（animation 条目没有）或 `id=="multiplayer"` 特判（feature 门）。physics/
  navmesh 走 extension（`src/lib.rs:716` 注册），multiplayer 走特判，**animation 两者皆无**
  →false。而动画工具面（`src/animation/`+`AnimationGraphExtension`，src/lib.rs:693）无条件
  编入，编辑器无 `animation` cargo feature（根 Cargo.toml `[features]` 亲读）。
- 四面后果（全部亲读核实，零功能性破坏——checkbox/开关/operator 路径均不 gating）：
  1. **New Project 对话框**（`src/launcher/pages/new_project.rs:320-331`）：Animation 行
     chip=「not in this editor」（Caution），而 multiplayer 是「tools built in」；
  2. **Extensions 页**（`src/launcher/pages/extensions.rs:146,178-185`）：无工程时 detail=
     「not in this editor」；开着带 animation 的工程时 attention=「this editor does not
     include its tools」；
  3. **File>Modules/导入审查 picker**（`src/module_picker.rs:181-198`）：行下常驻
     「This editor does not include this module.」warning 行；
  4. **每次打开 animation 工程状态栏+日志 warn**（`src/project_modules.rs:227-254`）：
     「This project uses the Animation module, which this editor does not include. Scenes
     keep those components, but they cannot be edited here.」——三句全错（动画组件本编辑器
     全可编辑）。T2 的 fixture 即 animation 工程，**每条 L 腿的编辑器日志都会出现该行**。
- 修向（供主控裁）：`catalog_has_module` 补一条 animation 臂（builtin，返回 true）——一行
  改动；建议带一测（`catalog_has_module(None, "animation")==true` 形态）。T2 L1 的 PX 腿
  顺手把修后 File>Modules 截图入档作 AN7 关闭证据。
- 立项编号按方案约定自 **AN7** 续编。

## 五、勘误：AN2「死件」前态表述（随本报告入档，放行条件③）

程序报告称 `animation_scene_load.rs`「此前在一切常跑档位编译为空」——**对 integration 档不
成立**：`crates/jackdaw_sdk/Cargo.toml` 的 `jackdaw_runtime` 依赖自 c091eebb（动画首落 PR，
先于 T15）就带 `"animation"` feature，`--workspace` 构建下 feature 统一使其在 integration
档（`--workspace --tests`）一直是活体。**实证**：T14 两份归档 integration 日志均有
`PASS jackdaw_runtime::animation_scene_load`（t14t3_integration.log :3157 (3068/5394)、
t14t3_qa_gate_integration.log :3148 (3060/5394)）；本轮 integration 主跑亦过（:3156）。

- 影响面：AN2 原始缺陷定性「CI 视角持续零覆盖」**过重**——fast/quick（`--lib`）档确为死件、
  parity 端到端证据链缺口仍真，但 integration 一直有编译+执行覆盖。方案事实十同句勘误。
- 不改变本轮建设价值：显式腿把该覆盖从「碰巧靠 sdk feature 统一」变成「一等公民」——若日后
  sdk 摘除 animation，integration 隐式覆盖静默消失，显式腿仍强制编译+执行。T3 book/终验
  措辞按本节口径写。

## 六、给 T2 的交接清单

1. **fixture 工程** `/Users/zhanglinbo/workspace/loop-mac/t15-anim/t15-anim`：现为**绿态**
   （jackdaw.toml `animation=true`+Cargo.toml features 含 animation，亲读核实）；flow
   start_scene=anim.bsn；jan+hero.glb 双资产在位。红态复现=程序报告 §五-2 步骤（模块改回
   false+features 摘除+冷编），红档日志可对照。
2. **基线**：scaffold teaches **89**、fast 族 **2980**、integration 族 **5402**（本轮计数，
   后续任务以此为准）。
3. **必做前置**：AN7 修复合入后再开 L 腿（至少先于 L1/L7-L9 的编辑器实机段）；warn 扫描
   协议把「This project uses the Animation module …」列为 AN7 已知行（修复前）/确认消失
   （修复后）。
4. **A6 口径照旧**：integration 若再红 `prefab_file_change_triggers_reload` @ :714 → 隔离
   单测绿即归因放行，计入 A6 账下 flake 计数。
5. **模块 UI 首次实机核一眼**（程序报告 §五-3 请求的 QA 动作，以静态核实代实机）：确认存在
   AN7 所述误报文案，修复后复看消失。
6. hero.glb 改动一律走 `python3 loop/t15-live/make_hero_glb.py OUT_PATH` 重生成（字节级
   确定性已验），勿手编二进制。

—— QA agent，2026-10-30
