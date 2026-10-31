# T19 终验 QA 报告：任务 3（收官段）+ T19 整体终验（只验不修）

> 验收对象：分支 `loop/t19-graphics` @ **77f7122d**（基线 main=b63ab28d=T2 合入点；程序提交
> =T19-T3 收官，T1/T2 已分别于 72a7ba10/b63ab28d 合入；T1 QA PASS（t19-t1-qa.md）、T2 QA
> PASS（t19-t2-qa.md，附 6 条 errata+F1——本轮逐条核落账兑现，见 §三-3）。程序报告：
> `loop/reports/t19-t3-report.md`。T3 diff 亲核（numstat 全件）：**产品面=book 三文件
> （graphics-panel.md +55 行两节+game-flow/assets 各一句交叉引用）+loop/reports/t19-t2-
> report.md（errata 落账 40 行）+T3 报告与归档+loop/t19-live/ 证据刷新（含 config-scratch/
> 补档）**——`src/`、`crates/`、`templates/`、fork、协议、场景格式零改动（commit 全件
> grep 该域路径零命中）；T1/T2 QA 报告本体与 plans/ 零触碰（git diff b63ab28d..77f7122d
> 为空亲证）；工作树除 QA 归档外零触碰。
> QA 手段：**Mac 全量门亲跑**（两段后台链+轮询，全程未设 RUST_BACKTRACE，门链独窗不与
> 真机同窗，门前 df 124Gi）+**关键格 console 原文全读**（editor/game/export/prep/seed 五
> 相 console 全文+原始 editor-game.log N13 两条亲读+t19-live.sh M9/M8 脚本逻辑对源）+
> **盘面亲验**（fixture scene.bsn SHA 现场重算+config-scratch/viewport.json 同值对读+
> seed-backup SHA+PNG 计数）+book 两节逐句对锚源码+交叉引用双向亲读+UI 名现场核对+
> clippy 双包/doctests 采信归档抽核（0 warning 行+bind dyld 第 12 次目击签名+单包复跑绿
> BIND_EXIT=0+双 log mtime 顺序可追）。
> QA 归档 `loop/reports/t19t3_qa_*` 八件（fmt/libtests/fast/audio_gate/save_store/doc/
> scaffold_e2e/integration——八门亲跑全覆盖）。

## 〇、结论

**PASS（T19-T3 收官 + T19 整体，含 roadmap T19 可勾选建议）**——全量门 QA 独立复现与程
序轮逐位吻合：integration **5458 跑 5458 过全绿**（QA 亲跑 606.7s EXIT=0；程序轮 551.3s
同数全绿——**A6 两轮均未复发**，flaky 本轮未触发，按既有口径如实记「全绿」，非口径变更）；
fast/libtests 双通道 **3001/3001**（QA 对 libtests 全文 58 条 result 行逐行求和恰合
3001/0）、**teaches 91**（scaffold 包 `running 91 tests` QA 亲点）、audio_gate **7/7**、
save_store **19/19**、fmt 零 Diff、docs **EXIT=0 且 17 行 warning 面与 T18 归档逐行同面**
（13 条实体警告同族同位+4 条包汇总行——T3 报告记「13 条」与 T18 QA 记「17 条」是计数法
差异非树态差异，详见 §六-2）、scaffold_e2e **1/1**。T3 真机复跑 **38 判定全 PASS**
（editor 17/game 14/export 7，QA 五相 console 全文亲读零虚报）：M1 像素 **100.00%/mean
73.359** 与 T2 逐字同值；M5 PX **42.92%/5.137**（T2 42.94%/5.129 同量级同向）；M9 三点
SHA 恒等（脚本逻辑亲读+活体 fixture SHA 今日重算=种子锚逐字）；M13 拒绝活体
`-32602 the control is disabled (checkbox )` 逐字同文；GR8 流送帧 **15.13%/2.731**（T2
13.78%/2.156，像素基准两轮同 5,939,136=3024×1964——忠实案维持，浮动=帧时差如实记档）；
N13=2 条全部 `pie::drain_game_events` 归属（原始日志两条全文亲读）；warn 扫描**零未解释
命中**（仅 N13 两条，逐条归属在案）。book 扩两节事实面对得上锚源码（EnvironmentPlugin
两侧同链/AA opt-out 恒真/viewport.json 用户级/模板无 Environment 四锚亲读）+三交叉引用
双向落位+「Game panel」UI 名对照 play-in-editor.md 防杜撰+**GI 节 diff 亲证零触碰**
（「保持」字面兑现）。**Errata E1-E6+F1 全部落账亲核**（E2 以 config-scratch/ 三件真档
闭合，QA 同值对读过）。验收句「场景级曝光/Bloom/AA 在 Play+导出生效；editor 偏好不污染
游戏；GI 保持禁用说明」逐词证据在案（§五）。**GR1/GR2 双缺口吸收闭合、GR3 边界记档**。
**偏差 0 🔴 + 0 🟡 + 6 ⚪（§六）**——全部为记档精度/计数法/台账残留级，不动摇裁决。

## 一、Mac 全量门亲跑（权威口径，最终树 77f7122d；门链独窗，未设 RUST_BACKTRACE）

门前 df 124Gi；链一后 122Gi；integration 后 121Gi（无清盘动作，T2 QA 预清的余量足够）。

| # | 门 | 命令 | QA 亲跑结果 | 归档 |
|---|---|---|---|---|
| 1 | 格式 | `cargo fmt --all -- --check` | **EXIT=0**（0 字节=零 Diff） | t19t3_qa_fmt.log |
| 2 | 单测 | `cargo test --workspace --lib` | **EXIT=0；3001 passed / 0 failed**（58 条 test result 行逐行求和亲算）；**scaffold 包 `running 91 tests` 亲点**（:2686）——teaches 91 计数与 T17-T2/T18-T3 一致零扰动 | t19t3_qa_libtests.log |
| 3 | fast | `cargo xtask fast` | **EXIT=0；Summary 3001 tests run: 3001 passed, 0 skipped（24.1s）** | t19t3_qa_fast.log |
| 4 | audio_gate | `cargo nextest run --profile ci --test audio_gate` | **7/7 PASS**（2.3s） | t19t3_qa_audio_gate.log |
| 5 | save_store | `cargo nextest run --profile ci -p jackdaw_runtime --test save_store` | **19/19 PASS**（0.1s） | t19t3_qa_save_store.log |
| 6 | docs | `cargo doc --workspace --no-deps` | **EXIT=0**；warning 面 **17 行与 t18t3_qa_doc.log 逐行同面**（12 条 private-doc-link+1 条 `StateEvent::Log` 未解析链接=13 条实体，同族同位；另 4 行为包级汇总行——T18 QA 的「17 条」与 T3 报告的「13 条」是同一树态的两种计数法，§六-2） | t19t3_qa_doc.log |
| 7 | scaffold_e2e | `cargo nextest run --profile ci -p jackdaw --test scaffold_e2e` | **1/1 PASS**（149.5s）EXIT=0 | t19t3_qa_scaffold_e2e.log |
| 8 | **integration** | `cargo xtask integration` | **EXIT=0；Summary [606.7s] 5458 tests run: 5458 passed (1 slow), 0 skipped——全绿**；FAIL 计数 0；尾段附 AN2 腿 1/1（`a_loaded_scene_plays_its_default_state`）。**A6（`prefab_file_change_triggers_reload`）本轮未复发**——与程序轮（551.3s 同数 5458 全绿）两轮独立互证「flaky 本轮未触发」；按任务口径如实记全绿，**不构成口径变更**（A6 定案口径维持，红时仍按隔离复跑对照） | t19t3_qa_integration.log |

**clippy 双包/doctests（采信归档抽核，T18 先例口径）**：`t19t3_gates_fmt_clippy.log`
抽核通过——`warning`/`error` 行计数 **0**（grep 亲算），物理双包两行 `Checking
jackdaw_avian_integration`+`Checking jackdaw_physics` 在档+`Finished`；fast 内含同参数
clippy 覆盖。`t19t3_gates_doctests_docs_scaffold.log` 主跑仅 `-p jackdaw_bind --doc` 处
dyld 家族失败（`Library not loaded: @rpath/libstd-614bb9b33bbc23af.dylib`——**第 12 次
目击**，T17 第 10/T18 第 11 同族同签名，T15 定案环境票）+`t19t3_gates_doctests_bind_
rerun.log` 单包复跑 **1 passed（EXIT=0，BIND_EXIT=0 在文）**——双日志 mtime 顺序可追
（01:16→01:18），采信。

**程序归档交叉复核**：`t19t3_gates_fast.log` Summary 3001/3001、`t19t3_gates_integration
.log` Summary 5458/5458 且 FAIL 计 0、`t19t3_gates_tests.log` SURFACE 段全量捕获（`test
result: ok. 52 passed` 两处在文=E5 教训已执行）、五相 console RESULTS 行判定数
17/14/7+prep/seed 与报告 §〇/§三/§四门禁表逐项一致，无隐瞒。

## 二、关键格复核（38 判定的四格证据原文全读+浮动口径+warn/N13 全归属）

**抽读四格=任务书建议格，全部 console 原文亲读+脚本逻辑对源+盘面亲验：**

1. **M1（曝光 100.00%）**：console-editor.log:7-13 原文——两拼写探针双 -23402 全文在档
   （`did not register the ReflectSerialize…`/`Unknown component type`，=T2 偏差 1 已裁
   ACCEPT 的工具链边界，非回归）；`M1 numeric via document:13.0`；像素对原文
   `pixels: 2806708; changed(>tol 12): 2806708 (100.00%); mean channel diff: 73.359`
   ——**与 T2 归档逐字同值**（判据=全帧重绘，exposure 9.7→13 的红绿）。
2. **M5（direct parity 42.92%）**：console-game.log:17 原文 seed face
   `{"bloom": 0.800000011920929, "exposure": null, "msaa": "Sample4", "smaa_present":
   true, "tonemapping": "TonyMcMapface"}`——与 M4（PIE 755v0）/M6（staged）三站逐字段
   同值、与 T2 归档逐字段同值；:26 像素对 `5939136 pixels; changed: 2548972 (42.92%);
   mean 5.137`（T2 42.94%/5.129 同量级同向）；bloom-0 态 `bloom: null` 组件退场同形
   （`dress_post` 的 `bloom_intensity > 0.0` 闸，T2 QA 已对源）；restore 种子 SHA 回位
   原文在档。
3. **M9（三点 SHA）**：脚本逻辑亲读（t19-live.sh:1230-1241——`sha_a1` 套件前/`sha_a2`
   套件后/`sha_a3` save 后三点相等+`jackdaw/status` dialog 恒空四条件同断）+console
   PASS 判语 `scene.bsn byte-identical through the whole A-region suite + save; no
   dirty dialog`+**QA 盘面亲验**：fixture `assets/scene.bsn` 今日现场重算 SHA=
   `655892c6c28327866acaa52c71a1ff510f9d963144b28864d257e1422e9a99a9`（种子锚逐字）、
   `scene.bsn.seed-backup` 同值；M8 RESTORE DRIFT 断言锚=同 SHA 硬编码在脚本 :1221。
   T2 QA 的当日活体复跑（t19t2_qa_m9_live.log）为第二重活证。
4. **M13（拒绝活体）**：console-editor.log:39 原文
   `{"jsonrpc":"2.0","id":2141,"error":{"code":-32602,"message":"the control is disabled
   (checkbox )"}}`——与 T2 逐字同文；等价性闭环（`ui_probe.rs:96-107` 只在祖先链带
   `InteractionDisabled` 时拒绝=拒绝即活体，T2 QA §五-2 源码亲读结论沿用）+置灰截图
   `shot-m13-gi-panel.png` 在档（本轮无 E6 的恢复对话框浮层）+H 锚（graphics_panel 三
   件）在本轮 `t19t3_gates_tests.log` 再绿。

**GR8/M5 浮动口径核（任务指定）**：GR8 流送帧对 13.78%→**15.13%**（mean 2.156→2.731）
——像素基准两轮恒等（5939136=3024×1964，窗口尺寸面同）、方向同向（bloom 0.8→0 两态流
送面移动）、量级同带（14±1%），与组件读回（bloom 退场）一致——**忠实案维持**，浮动=
帧时差/合成时序，判据是「过阈（≥1%）+同向」非逐字复现（决策 1-A：像素轨是「画面随值
变」判据）。T3 报告偏差 2 如实，QA 采信。

**M3 AA 边界格（附带全读）**：console-editor.log:21-22——文档 antialiasing=Taa 在+视口
相机 `TemporalAntiAliasing not present`（-23403 on Entity 3910v0）=「opt-out 恒真」边界
本身的负向断言，与 M7 三站 Smaa 正向断言合围「AA 唯游戏通道生效」。

**N13 记数与归属**：editor 相 0/export 相 0/game 相 2——QA 对原始
`loop/t19-live/editor-game.log` 两条亲读：`thread 'main' panicked at …/vec/mod.rs:2258:
swap_remove index (is 0) should be < len (is 0)`+`ERROR bevy_ecs::error::handler:
Encountered an error in system jackdaw::pie::drain_game_events: Exclusive system
panicked`（紧跟 `PIE: Play #1 connected`，其后 `OPERATOR: pie.stop` 编辑器存活续跑）
——即一次 N13 panic 的两条日志行，全部归属 `pie::drain_game_events`，与 T2「每 PIE 相
2 条」同形（N13 绕行+读回重试绿）。

**warn 扫描零未解释命中复核**：五相 console 的扫描判定行逐一亲数——editor 相 1 份
（clean）+game 相 7 份（direct-m5a/m5b/m7keep/m11a/m11b/m15 全 clean+editor 2 命中=N13
两条）+export 相 2 份（staged-run+editor 全 clean）=**QA 实数 10 份扫描、命中共 2 条、
全部归属、零未解释**。T3 报告写「十一份」（direct×5）与 console 实数差一（direct 实为
6 份）——**计数法级 prose 偏差，命中分析不受影响**（⚪ §六-3）。

## 三、book 扩节核对（方案 §四-T3-2+决策 8-A；GI 节「保持」字面）

`git diff b63ab28d..77f7122d -- book/src/user-guide/graphics-panel.md` 亲读：**恰好两节
插入于 Scene section 与 Realtime GI 之间（+55 行），GI 节零 hunk 触碰**；SUMMARY 未动
（不另立新章）；game-flow.md +5 行（Cameras 节尾一句）、assets.md +4 行（JPG 边界条目
尾一句）。

### 1. 「Scene quality in Play and export」节——事实面逐句对锚（QA 亲验）

| 书内断言 | 锚源码/证据 | 判 |
|---|---|---|
| "one piece of code reads the scene's `Environment` and dresses each game camera…no second implementation" | `src/lib.rs:452`（编辑器 `.add_plugins(jackdaw_surface::EnvironmentPlugin)`）与 `crates/jackdaw_runtime/src/lib.rs:347`（游戏同插件，`render` feature 下）**同一插件亲读** | ✅ |
| "same scene values read back field-for-field identical…all three places" | M4/M5/M6 三站 seed face 逐字段同值（§二-2，QA 亲读） | ✅ |
| "Flipping the scene's anti-aliasing switches the matching component on all three stations…Keep switches it off" | M7_PIE_SMAA/M7_DIRECT_SMAA/M7_STAGED_SMAA/M7_KEEP_EXIT 四 PASS（console 原文） | ✅ |
| "Screenshots confirm the pictures genuinely change…streamed frames follow the same dressing" | M1 100.00%/M2 28.95%/M5 42.92%+GR8 15.13% 忠实案（§二） | ✅ |
| "scene anti-aliasing applies to the game's cameras only. The editor viewport always keeps its own AA" | `src/viewport_quality.rs:100` `antialiasing: true` **恒真亲读**+M3 边界格 | ✅ |
| "exported build carries the whole `assets/` tree…adds nothing editor-private, holds no quality settings of its own" | M10 manifest 全清单 diff 空+`crates/jackdaw_project_build/src/export.rs` copy_tree 名单（T2 QA 亲读链） | ✅ |
| 出链 `[Assets](assets.md)` ×2（格式表+压缩纹理首载角） | assets.md 存在+该两处内容在档（T18 交付面） | ✅ |

### 2. 「Editor preferences and the game」节——事实面逐句对锚（QA 亲验）

| 书内断言 | 锚源码/证据 | 判 |
|---|---|---|
| "stored per user, in `viewport.json` under your config directory — never in the scene file, never in the project" | `crates/jackdaw_env/src/paths.rs:59-62`（`config_dir().join("viewport.json")`）+`src/viewport_settings.rs:3-6` 文件头 doc（"Kept per user…never in a scene…Play and the saved file are unaffected"）**逐字亲读** | ✅ |
| "Dialing the entire Viewport section leaves the scene file byte-for-byte unchanged, with no dirty flag and no undo entries" | M9 三点 SHA+dialog 恒空+T1 headless 守卫（undo 零增量；QA 三场破坏演练证两闸能红，t19-t1-qa.md §二） | ✅ |
| "leaves the exported package unchanged: every file the export manifest lists comes out identical" | M10_PACKAGE_PASS（console:12-13 原文"manifest full-list diff empty…staged scene bytes equal"） | ✅ |
| "the game's cameras read back the same numbers under two opposite viewport settings" | M11 两态 face 逐字段恒等（console:31-36 原文） | ✅ |
| "Scene anti-aliasing has no row in this panel on purpose…authored where the rest of its `Environment` lives — the inspector's component fields"（GR3 注记） | `build_scene_section`（graphics_panel.rs:414-521）亲读**零 antialiasing/msaa 控件** | ✅ |
| "a brand-new project has no `Environment` at all…editor preview, Play and export all agree on the plain default look"（GR7） | `templates/game/assets/scene.bsn` grep Environment **EXIT=1 亲验**+M15（无环境=smaa 退场）+空态提示文案 ftl 在档 | ✅ |
| 出链 `[Game Flow](game-flow.md)` | game-flow.md 存在 | ✅ |

### 3. 交叉引用双向+UI 名防杜撰+Errata 落账

- **双向亲读**：`game-flow.md:128-131`（Cameras 节尾："the look the Graphics panel's
  Scene section authors reaches that camera the same way it reaches Play and the
  exported build ([Graphics Panel](graphics-panel.md))"→指向 graphics-panel）；
  `assets.md:36-40`（JPG 边界条目尾："The exported build carries whatever `assets/`
  holds either way — [Graphics Panel](graphics-panel.md) covers the scene-quality side"）；
  graphics-panel 侧出链 assets.md×2+game-flow.md×1 全部目标存在。三处引用位置与 T3 报
  告声称一致。
- **UI 名**："Game panel"＝play-in-editor.md 既定名（:10/:305/:307/:311/:317 五处亲读）
  ——graphics-panel.md:89 用词同源，**零杜撰**；"Graphics Panel"章名与 Window 菜单既有
  表述一致。
- **Errata E1-E6+F1 落账逐条亲核**（t19-t2-report.md）：E1→:135「**14 张**通道 PNG…E1
  勘误」+QA `ls` 亲数 **14**（原位修正+标注，原数字不灭失）；E3→:8「735→**1,708** 行
  （E3 勘误）」；E4→:36「**15 次** operator 活体套件（E4 勘误）」；E5→:89 注记+T3 归
  档已按全量捕获执行（SURFACE 52 passed 在 t19t3_gates_tests.log 两处亲读）；E6→:111
  注记（Recovered Work 对话框不影响 GI 行可见与 M9 dialog 断言）；F1→§十落账（判据承
  载面=H 锚三态断言，A14 候选工具票已立 buglist:481）。**T2 QA 报告本体零触碰**（git
  diff 为空亲证）。
- **E2 补档闭合核（任务指定同值对读）**：`loop/t19-live/config-scratch/viewport.json`
  文件脸 `render_scale:50/anti_aliasing:"off"/ssao_quality:"high"/post_processing:false/
  sharpen:false` ↔ console-editor.log:45 M12_SCRATCH_PASS 判据行
  `{"render_scale":50,"aa":"off","ssao":"high","post":false,"sharpen":false}` ——**逐字
  段同值**，T2 时的归档缺口闭合；同目录 extensions.json/recent.json 随档；M12_PER_USER
  行（:47-48 无 override 读回 render_scale:100+fxaa+post true）与 scratch 面构成 per-user
  双腿。

## 四、QA 放行清单对照（任务书终验口径）

| 条目 | 终态 |
|---|---|
| **T1 验收（GR2 守卫红绿+GR8 探针+fixture prep+门禁）** | ✅ QA PASS（t19-t1-qa.md：七门亲跑+守卫三场人为破坏演练实证 undo 闸/字节闸独立开火+GR8 两模式静态链全对+S3 磁盘独立复历） |
| **T2 验收（M1-M16/L1-L10 真机矩阵+四门禁）** | ✅ QA PASS（t19-t2-qa.md：四条验收标准全核+四格重算逐字复现+M9 活体腿+6 errata+F1）——errata 本轮终验全部落账兑现（§三-3） |
| **T3 验收（16 格终态复跑+book 扩节+全量门+errata 落账）** | ✅ 本轮（§一/§二/§三：38 判定全 PASS 亲读+八门亲跑+book 两节对锚+E 落账核） |
| **GR1 🔴 场景级画质 Play+导出零端到端证据** | **吸收闭合（验收主任务兑现）**：M4（PIE 755v0）/M5（direct 761v0）/M6（staged）三站数值脸逐字段一致+bloom-0 三站组件同步退场+M7 AA 三站+M8 编辑→保存→重开往返+像素红绿四组——铁证①立住 |
| **GR2 🟡 editor 偏好不污染负向证据零** | **吸收闭合（建设小头兑现）**：M9 文档 SHA 三点恒等+无脏弹窗/M10 导出包 manifest 全清单 diff 空+staged 字节相等/M11 两态游戏相机矩阵恒等/M12 CONFIG_DIR 隔离+per-user 活证+T1 headless 守卫（演练证能红）——铁证②立住 |
| **GR3 ⚪ 场景级 AA 无面板行** | **不吸收（范围边界）兑现**：矩阵以 `environment.set` 为授权面跑通（M7 三站）；book GR3 注记落节（§三-2）；面板补行留 open-challenges 口径 |
| **铁证③ GI 保持禁用说明** | **维持成立**：M13 拒绝活体（-32602 同文）+置灰截图+M14 全链零 solari/ray 命中+fork `bevy_solari` optional 未启用（T2 QA 静态亲扫沿用）+ftl/book/H 锚三层文案一致（本轮 book GI 节 diff 零触碰=「保持」字面兑现） |
| **M16 存活腿** | ✅ 三相终态 BRP 活+pid（console M16_*_PASS 三处）；N13 绕行读回绿 |
| **关联票纪律** | A6（维持「已定案环境票」放行口径——本轮两轮全绿未触发，如实记）/A7（不前置，脚本五招在档，未真踩不可绕形态）/A14/A15（T2 收官提交 edeee59a 已立账、票面注「主控批准」，本轮零触碰、未勾选=正确）✅ |
| **buglist/roadmap/台账纪律** | T3 提交触碰零 buglist/台账/roadmap（numstat 亲核）；roadmap 第 33 行未勾（留主控）；台账最后一行=T19-T2 DONE（288 行，T3 行留主控）✅ |

## 五、验收句逐词证据指认

roadmap 第 33 行验收原文（逐字在案）：「**画质设置与游戏输出一致性：Graphics 面板边界
验证+游戏运行/导出应用链路。验收=场景级曝光/Bloom/AA 在 Play+导出生效；editor 偏好不
污染游戏；GI 保持禁用说明。**」

### 「场景级曝光/Bloom/AA 在 Play+导出生效」——成立（曝光组件读回为已裁定的分层合围）

| 验收词 | 证据（QA 亲读/亲验） |
|---|---|
| 场景级（作者面） | 种子值经 `environment.set` operator 写入→`scene.save` 落盘（决策 3-A，seed 相幂等跳写+组件读回 exposure 13.0/bloom 0.800000011920929/Smaa 原文 console-seed.log:4）——B 区写入链即验收通路 |
| 曝光…生效 | document face 13.0（world.query，M1/M8 两处原文）+dress 同 insert 块相邻字段（Bloom 0.800000011920929 精确读回代言，`environment.rs:689-695` T2 亲读）+编辑器视口像素 **100.00%** 重绘+H 锚 `post_settings_reach_the_camera_components`（本轮 surface 52 再绿）。**限定注记**：Exposure 组件级读回被 BRP 结构性拒绝（-23402，`#[reflect(opaque)]` 无 ReflectSerialize，fork 面）=T2 偏差 1 QA ACCEPT 的工具链边界，两轮红证在档非回归 |
| Bloom…Play 生效 | PIE 相机 seed face bloom 0.800000011920929+bloom-0 退场（M4）+流送帧红绿 15.13%（GR8 忠实） |
| Bloom…导出生效 | staged 进程同 face（M6）+direct 42.92% 像素（M5，同二进制不同启动路径互证） |
| AA…Play 生效 | M7 三站 Smaa 在+Keep 退场（`smaa_present:false` 原文）+M15 无环境对照（dress 消失=组件确随场景走） |
| AA…导出生效 | M7_STAGED_SMAA_PASS+staged face smaa_present:true |
| 一致性 | 三站四字段恒等（bloom/tonemapping/smaa/msaa——exposure 走上述合围）+M8 保存-重开往返 12.5 |

### 「editor 偏好不污染游戏」——成立（四腿全绿，§四 GR2 行）

文档层 M9（SHA 三点+无脏弹窗+无 undo）→导出层 M10（manifest 全清单 diff 空+staged 字
节相等+新写证明 `ready -> …` 前进）→游戏层 M11（两态反向设定下相机矩阵逐字段恒等）
→配置层 M12（scratch 隔离+per-user 读回，E2 补档同值对读）——三层架构边界的四条盘面
/真机证据链闭环，feature-08 终验 ⚪ 遗留就此收口。

### 「GI 保持禁用说明」——成立（回归格不破+文案三层不动）

M13 拒绝活体（InteractionDisabled 在场的运行时直接证明）+置灰截图+M14 零 solari/ray
warn+静态面（workspace features 无 solari/fork optional）+ftl tooltip 四替代项与 book
GI 节逐字同源（本轮亲读）+H 锚再绿——「保持」=复验不破，「说明」=三层文案原样。

## 六、偏差与记档分级（QA 视角，全部 ⚪ 不阻塞）

| # | 项 | 事实 | 处置 |
|---|---|---|---|
| 1 | **Exposure 组件读回结构性必红**（M1/M8 两拼写 -23402 原文在档） | fork `bevy_camera` `#[reflect(opaque)]` 无 ReflectSerialize——工具链边界，T2 偏差 1 已裁 ACCEPT；数值脸=document+相邻字段+H 锚+像素四层合围 | 维持；若要组件级读回需 fork 注册（超 T19 授权），记档即可 |
| 2 | **docs 警告计数法差异**：T3 报告记「13 条与 T17/T18 基线同数同族」，T18 QA 记「17 条」 | QA 双 log 逐行对比：**两轮树态逐行同面**（12 条 private-doc-link+1 条 StateEvent::Log=13 条实体+4 行包级汇总=17 行 grep）；T19 的合并 log 另含 1 行 dylib doctest 注记（来自 doctests 段非 cargo doc）——「13」与「17」是同一树态两种计数法，**零新增零消失** | 两读法并记本条，后续归档建议注明计数口径（行/条） |
| 3 | **warn 扫描份数 prose 差一**：T3 报告「十一份（direct×5）」，console 实数 **10 份扫描（direct 实为 6）** | 五相 console 扫描判定行逐一亲数：1+7+2=10；命中 2 条全归属——「零未解释命中」的实质判定不受影响 | 措辞级勘误随本报告入档；主控合入时可顺手改「direct×6，共十份」 |
| 4 | **台账 288 行残留勘误前数字**：`loop/progress.md` T19-T2 行仍写「证据 17 张通道 PNG」（E1 已勘为 14） | 该行系 T2 收官期主控落笔，早于 E1 勘误落账；T3 报告面已改、台账行未随 | 主控合入写 T19 行时顺手改一处 token（「17」→「14」） |
| 5 | **GR6 同轮 Inconclusive-by-fixture**（sun_shadows 文件脸动+两帧互证 flat） | fixture 无承影几何（sky only），非 R12 形态；T2 同形 | 维持「R12 本体不吸收，T20 有承影体场景顺手补腿」口径 |
| 6 | **seed 相 -23501 resource face+mdbook 渲染未验+A14/A15 立账时点** | ①seed resource face 为 L1 预期形态（文件脸在 editor 相承载，L1_PRESET_FACE 翻转 PASS 闭合）；②book 无 mdbook 本地渲染（工具不在 PATH）——链接全相对+目标存在亲验，UI 名对照既定用词；③A14/A15 系 T2 收官提交（edeee59a）落账、票面注「主控批准立账」，非 T3 触碰 | 照实记档 |

**未动面**：`src/`、`crates/`、templates、fork、协议、场景格式——T3 零改动（T19 全弧
产品面=T1 的 tests 两件+T2/T3 的 loop 脚本与归档）；buglist/台账/roadmap 本轮未写（主
控合入时落笔）；工作树仅 QA 归档 8 件+本报告（`git status` 全量亲录）；RUST_BACKTRACE
全程未设；门链与真机不同窗；fork 零触碰。

## 七、最终裁决与 roadmap 建议

- **T19-T3 验收标准（方案 §四-T3）**：16 格终态复跑+重点腿=三相 38 判定全 PASS（五相
  console 全文亲读，四关键格原文全读+盘面亲验，零虚报）✅；book 扩两节+三交叉引用+GI
  节原文不动 ✅（§三）；errata E1-E6+F1 落账 ✅（§三-3）；全量门 QA 亲跑复现（八门
  EXIT=0+clippy/doctests 归档抽核）✅（§一）。
- **T19 整体（T1/T2/T3）**：验收句逐词全数在案（§五）；三铁证终态立住（GR1/GR2 吸收闭
  合+GR3 边界兑现+铁证③维持，§四）；门禁 QA 独立复现与程序轮逐位吻合（fast/libtests
  3001+teaches 91、integration **两轮 5458/5458 全绿**（A6 两轮未复发=flaky 未触发，
  定案口径不变）、audio 7/save_store 19/scaffold_e2e 1、docs 同面 17 行、clippy 归档零
  warning、bind dyld 第 12 次目击按 T15 处方单包复跑绿）；三轮 QA 裁决链闭环（T1
  PASS→T2 PASS（含 6 errata）→T3 终验）。
- **VERDICT: PASS——T19 整体闭环。roadmap T19（第 33 行）建议可勾选**，闭环注记建议含：
  验收句逐词证据（三站数值脸逐字段+bloom/AA 组件与像素双轨+负向四腿+GI 拒绝活体）；
  GR 终态（GR1/GR2 吸收闭合、GR3-GR8 记档/边界，其中 GR6=Inconclusive-by-fixture 待
  T20 承影体场景补腿、GR8=流送帧忠实案两轮同向）；integration 两轮全绿（A6 定案口径维
  持）+teaches 91；book 扩两节+三交叉引用+GI 不动；T19 产品面=零改动（回滚=删 tests 两
  件+脚本）；⚪ 偏差六项不阻塞（§六-3/§六-4 两处一处 token 级勘误建议随合入落笔）。
- **主控合入路径**：照旧 `--no-ff`（T3 单提交 77f7122d 随 T2 之后）；主控落笔面=roadmap
  第 33 行勾选+收官行、台账 T19 行（顺手把 288 行「17 张」改「14 张」）、buglist 零新
  票（A6/A7/A14/A15 维持未勾选）+本报告 §六-3 的「direct×6，共十份」可选勘误。

## 八、用户 30 秒清单（T2 QA 修正式维持，真机腿一一对映）

1. **拖 Exposure 滑条**：Scene 区把 Exposure 从 9.7 拖到 13——Play 画面整帧变亮（回拖变
   暗）——M1 像素 100.00% 重绘背书。
2. **拨视口 Quality Preset**：Viewport 区 Low↔High 来回拨——Play/导出画面**不变**（游
   戏相机读数恒等）——M11 恒等+M10 包面背书。
3. **悬停 GI 行**：Realtime GI 行置灰，悬停看说明（Solari 实验/未接入+四替代项）——
   合成驱动做不到 hover，人工点验；置灰有拒绝活体背书。

## QA 会话产物索引

- 门禁八门：`loop/reports/t19t3_qa_{fmt,libtests,fast,audio_gate,save_store,doc,
  scaffold_e2e,integration}.log`（QA 亲跑全覆盖；两段后台链+轮询，df 124Gi 开跑）。
- 核验对象：`loop/reports/t19-t3-report.md`+归档 t19t3_* 十三件（console 五相+门禁八
  log）；T1/T2 报告与 QA（t19-t1-qa/t19-t2-qa 含 errata 交接）+t19-t2-report.md 落账
  面；`loop/qa/t19-live.sh`（M9/M8/锚点段亲读）；`loop/t19-live/`（console 五相+原始
  editor-game.log N13 两条+config-scratch 三件+seed-backup+14 PNG+walk JSON）；book 三
  文件 diff 与源码对照点（src/lib.rs:452、crates/jackdaw_runtime/src/lib.rs:347、
  src/viewport_quality.rs:100、crates/jackdaw_env/src/paths.rs:59-62、
  src/viewport_settings.rs:3-6、src/graphics_panel.rs:414-521、模板 scene.bsn、
  main.ftl:36-37）；buglist A6/A7/A14/A15+roadmap 第 33 行+台账 285-288 行。
- 进程收尾：QA 复查零 jackdaw/nextest/cargo 残留进程；fork 零触碰；RUST_BACKTRACE 全
  程未设；门链独窗；df 出口 121Gi；工作树除 QA 归档 8 件+本报告外零触碰。

—— QA agent（loop 自动化终验），2026-11-01
