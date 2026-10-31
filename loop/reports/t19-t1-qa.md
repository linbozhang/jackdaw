# T19 任务 1「负向守卫+探针清源轮」QA 验收报告

> QA 回流（2026-10-31 深夜轮）；对象=程序提交 `0c681afd`（分支 `loop/t19-graphics`，自
> main `e86f040b`）+程序报告 `loop/reports/t19-t1-report.md`；方案
> `loop/plans/t19-graphics-parity.md` §四-T1+§五决策表（主控 8 点全按建议）。QA 纪律：
> 只读+亲跑+写报告（亲跑证据归档 `loop/reports/t19t1_qa_*` 9 件，见 §一）；产品代码、
> buglist、台账零改动；全程未设 RUST_BACKTRACE；结束时无残留编辑器/游戏进程。

## 裁决：**PASS**（附 5 条 errata 勘误+2 条放行条件，见 §六/§七）

任务书 T1 三条验收标准逐一核过：①负向守卫红绿在案且断言消息自证覆盖面——**成立，
且经 QA 三场人为破坏演练实证两道闸都能红**（程序侧「现状直绿+消息自证」的逻辑自证
之外，QA 补了行为学证明，§三）；②GR8 探针有结论、忠实/不忠实两案均进决策 4 回落
路径——**成立**（两模式静态组件链亲读复核全对，偏差 S1 裁定 ACCEPT，§四）；③
fixture prep 全绿——**成立**（PREP_OK+seed PASS 归档链完整，QA 亲验 fixture 场景
SHA 与报告逐字一致，§五）。门禁七项全绿（QA 全部亲跑，§一）。产品零改动核实：
`git diff e86f040b..0c681afd -- src/ crates/` 为空，改动面=tests 一件
（graphics_prefs_clean.rs 307 行）+tests/viewport/main.rs 一行（`mod` 注册）+
loop/qa/t19-live.sh 一件（735 行）+报告与证据归档——回滚声明「删测试文件与脚本」
属实。

## 一、门禁亲跑（全部 QA 手跑，后台+轮询；日志归档 t19t1_qa_*）

| 门 | 命令 | QA 亲跑结果 | QA 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **EXIT=0，零 Diff** | t19t1_qa_fmt.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **EXIT=0，全文 0 error/0 warning** | t19t1_qa_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | **EXIT=0** | t19t1_qa_gates.log |
| 单测 | `cargo test --workspace --lib`（全文日志） | **passed=3001 failed=0**（QA 对全文逐行求和，恰合任务书预期 3001） | t19t1_qa_libtests.log |
| 集成·viewport 全量 | `cargo test -p jackdaw --test viewport` | **166/1：唯一红=既有 flake `a_preset_picked`（同签名复现，见 §六-5）；新守卫 2 件与 graphics_panel 8 件在全量跑中绿** | t19t1_qa_gates.log |
| 新守卫隔离 | `cargo test ... --test viewport graphics_prefs_clean` | **2 passed**（守卫 1+守卫 2 都绿，含决策 3 盘面测试亲跑） | t19t1_qa_targeted.log |
| graphics_panel 回归隔离 | 同上 `graphics_panel` | **8 passed**（功能 #8 锚零回归） | t19t1_qa_targeted.log |
| surface 族 | `cargo test -p jackdaw_surface` | **52 passed，0 failed**（dress 测试族全绿） | t19t1_qa_gates.log |
| AN2 腿 | `cargo nextest run -p jackdaw_runtime --features animation --test animation_scene_load` | **1 passed**（T15 转活先例维持） | t19t1_qa_gates.log |
| 像素助手自证 | `bash loop/qa/t19-live.sh selftest` | **SELFTEST_HELPERS_PASS，exit 0**；md5/pixdiff 数值与程序归档逐字一致（pixdiff 同图 0.00%、红绿互补 100.00%/mean 113.333） | t19t1_qa_selftest.log |

与程序归档（t19t1_gates.log/t19t1_libtests.log）交叉一致；程序归档的 libtests 全文
QA 亦独立求和=3001/0。门禁标准（README「日志全文复核」）双端满足。

## 二、GR2 守卫源码审查（tests/viewport/graphics_prefs_clean.rs 亲读）

**结构**：守卫 1 `the_viewport_preferences_leave_the_scene_document_untouched`
（tempdir 工程+盘上开场景（带 Environment+Camera3d）→首次 save 取基准字节→全套
viewport.* operator 走用户路径→settings-moved 逐字段自证→undo 零增量→clobber 重写
证明→scene.save 字节相等）；守卫 2 `the_prep_chain_authors_an_environment_through_
the_operators`（select→component.add→environment.set 五种子→save→重开逐字段读回）。

**「现状直绿」覆盖面自证的核实**（报告三重自证逐条对源）：
- **settings-moved 自证**：`assert_the_settings_moved` 实为 **19 条逐字段 assert**
  （preset None+quality.set 五参+8 show flag+ssao 两项+sharpen 两项+realtime/stats/
  frame_graph），每条消息点名产生它的 operator——operators 没跑则守卫没前提。⚠️报告
  写「17 项」为误计（errata E2，§六）。
- **clobber 重写证明**：`fs::write(&scene, "// clobbered\n")` 后才 `scene.save`——
  save 静默不发生则盘上残留垃圾字节、字节断言必红。该技巧 QA 在演练 1 中反向实证
  （见下）：save 确实重写了盘面。真实有效。
- **undo 计数消息**：assert_eq 消息自带 "went from 0 entries to 1" 形态前后计数
  （演练 1b 的红文里逐字可见）。真实有效。
- **用户路径语义**：`run_op_clause_as_user`（boot_ops.rs:606）亲读——`creates_
  history_entry: true`+`ExecutionContext::Invoke`；快照门
  `(creates_history_entry && allows_undo)`（operator.rs:661 区域）亲读属实；
  `CallOperatorSettings::default()=false`（:377-381 注释明言 user dispatcher 才显式
  置真）——「最强路径下检验 allows_undo=false」的声明成立。既有
  viewport_settings.rs 的 `run` 助手走静默默认，声明③的增量属实。
- **resolve_entity_params**（boot_ops.rs:470-510 亲读）：String→按名、Int→按 id、
  Entity 直通——报告探针②沉淀的两条纪律（按名传/f32 epsilon）与源相符。

**与既有 viewport_settings.rs:166 重叠声明的核实**：该测试存在且如报告所述覆盖
「preset low+8 show flags+realtime/stats+4 view.mode→save→字节相等」，走静默路径、
无 undo 断言、无 clobber、无 settings-moved。报告声明的六项增量逐条核实**全部成立**
（quality.set 五参/ssao.set/sharpen.set/stats.graph.toggle 既有测试确未跑；undo 零
增量断言既有测试确无；用户路径差异如上；clobber/settings-moved 确无；文档形态差异
属实）。二者互补、既有测试未动的处置正确。

**人为破坏演练（QA 侧临时改、跑后即还原，树已验净）**——三场，全部归档：

| 演练 | 注入形态 | 结果 | 归档 |
|---|---|---|---|
| 演练 1 | 守卫 1 套件后直接 `world.get_mut::<Environment>` 改 exposure（不进文档 AST） | **绿**——正确行为：`scene.save` 序列化的是场景文档（AST）而非活世界组件，纯世界突变不构成文档污染；该演练反向证明了 clobber 后 save 确实重写盘面（垃圾被 AST 字节覆盖） | t19t1_qa_drill1_byte_guard_red.log |
| 演练 1b | 静默路径跑**真会写文档的 operator**（`run_op_clause "environment.set post.exposure=13"`，creates_history_entry=false——「A 区写文档而不进 undo」的bug 真形态），守卫原样 | **红**——undo 闸先红："the stack went from 0 entries to 1"；证明 as-shipped 守卫对文档写入 operator 必红 | t19t1_qa_drill1b_byte_guard_red.log |
| 演练 1c | 同 1b 注入+暂挂 undo 断言（隔离 byte 闸） | **红**——字节闸独立开火，红文自带完整消息且污染字节肉眼可读（盘面出现 `exposure: 13.0` 的 PostProcess 块 vs 基准的裸 `Environment`）；「偏好泄进文档而 undo 被绕过」的失败形态被字节闸精确捕获 | t19t1_qa_drill1c_byte_tripwire_red.log |

结论：守卫的两道闸（undo 计数、存盘字节）**都经行为学证明能红**，且各自咬住一种
绕过方式（1b 咬「写文档的 operator」，1c 咬「绕过 undo 计数的文档污染」）；「现状
直绿」不是无牙守卫。守卫 1 的保护面如实界定：**文档 AST 层+operator 面**（这正是
save 的序列化源），不覆盖纯世界态——与 GR2「文档层不污染」的验收语义恰好对齐。
演练文件已 `git checkout` 还原并复跑绿（2/2），`git status` 只余 QA 归档新件。

## 三、决策 3 定案复核（探针②）

- **盘面半边亲跑**：`the_prep_chain_authors_an_environment_through_the_operators`
  QA 隔离亲跑 **绿**（select→component.add（Entity 参数）→environment.set 五种子→
  scene.save→重开逐字段读回 exposure 13.0/bloom 0.8/Smaa/sky+post enabled）。
- **真机半边归档链核实**：t19t1_editor_seed.log（首写，文档全文含正确种子）→
  t19t1_seed_attempt1_false-red.log（假红：链首拍已写对文档，红在验证器 jq `==0.8`
  撞 f32 `0.800000011920929`——偏差 S2 证据链自洽）→t19t1_seed_pass.log（幂等二跑：
  "already carries the seeded environment; skipping the write"+SHA 前后相等+组件
  读回带 f32 精确值）。脚本 seed 相源码亲读：grep 幂等守卫+epsilon 判据+读回断言
  与归档逐条对上。
- **QA 亲验盘面事实**：fixture `assets/scene.bsn` 现场重算 SHA=
  `655892c6c28327866acaa52c71a1ff510f9d963144b28864d257e1422e9a99a9`，与报告声称
  **逐字一致**，文档含 1 处 Environment 块——种子 fixture 的在案事实亲证。
- 定案 A 案（operator 写后存盘）成立；B 案留作回落未动，符合方案决策 3。

## 四、GR8 探针复核与偏差裁定

**静态链源码亲读（两模式全对）**：
- 窗口回退：捕获相机 spawn 于 `Camera3d::default()`+`Camera{is_active:false}`+
  `RenderTarget::Image`+`ChildOf(rig)`，**无 RenderLayers、无 EnvironmentOptOut**
  （pie_frames.rs:187-199）；dress 查询面 `Query<CameraParts, With<Camera3d>>`+
  `layers.is_none_or(|l| l.intersects(&default))`（缺席=被 dress）+`opt_out.unwrap_
  or_default()`（无 opt-out=全量 dress）+新相机无 `UndressedCamera` 不走早退
  （surface/environment.rs:473,503-525,538-560）——「流送帧=与游戏窗口同组件面」
  按构造成立。
- 无窗模式：`retarget_cameras` 每帧把游戏自己的窗口相机改指共享 WindowlessTarget
  （pie_windowless.rs:138-152）；`start_windowless_stream` 的 `Readback::texture(
  同一 image)`+`camera: None`（pie_frames.rs:227-267）——「流送帧=游戏本体相机渲染
  输出原样」按恒等成立。
- 两条边界如实：`dresses_cameras()` 任一组开才 dress（scene_types:333-338，种子
  sky+post 双开恒真）；一帧延迟由 M4 settle 吸收。

**S1 裁定：ACCEPT（放行，附 T2 硬条件）**。方案 T1-1 原文「headless **或**真机单腿
定案……（读 pie_frames.rs 捕获相机的组件链+真机流送帧红绿对照）」——「读组件链」
即方案列举的定案手段之一，headless 分支被满足；验收标准「两案均进决策 4 回落路径」
已兑现（忠实案→M4 保 PX；不忠实案触发条件=L3 红绿与组件读回矛盾→降级数值轨+GR8
记档）。**硬条件**：T2 L3 首拍必须真机跑 PX 确认（程序已承诺），届时 N13 绕行+A7
五招全量武装；若矛盾按回落路径执行并在 GR 台账记档。

**S2 裁定：ACCEPT**——假红在验证器不在链（attempt1 归档文档全文即决策 3 真机证据），
epsilon 修正后 PASS；红证归档在案，纪律已沉淀进脚本注释与报告 §六-4。

**S3 裁定：ACCEPT（QA 独立复历）**——QA 本轮门禁亦两次撞 99-100% 磁盘：清 workspace
incremental（2.4G）后又清 t19 fixture `.jackdaw/target`（18G，门禁前 5.2Gi→清后
20Gi）。fixture 场景/资产无损（SHA 亲验）。**给 T2 的实际后果：QA 又清了一次
fixture 构建缓存，prep 相冷编预算（~10 分钟）为必答题而非可选项**；另注意 workspace
`target/debug/deps` 已累积 212G，export 腿（需产出 staged 包）前建议做一次陈旧工件
清理（A6 单触发源纪律）。

## 五、像素助手与 A7 五招核

- `selftest` 亲跑全绿（§一）；`png_pixels_md5`/`png_decode_rgb`/`crop_md5`（参数化
  矩形）/`pixdiff`（%+mean，尺寸不匹配自红）四助手源码亲读+t18 形态一致；selftest
  覆盖「同内容稳定/异色相异/矩形内稳定跨界相异/同图 0.00%/互补 100.00%」与归档数值
  逐字一致。
- A7 五招在 `shot` 助手逐招对源：①唯一 request 键（`t19-$name-$RANDOM-$SECONDS-$i`）
  ②`rm -f` 先行 ③落盘 size>0 才算 ④判红必过 `confirm_red`（两张同态新帧互等且等于
  after 才认真红，否则判 flake/stale 返回 1 让腿重读——脚本注释明写「flake 探针
  (move 3), not a criterion」，与决策 6-A 语义精确一致）⑤20 次重试后 `screencapture
  -x` 降级。`settle_pixels`（GR4 纪律）与 `manifest_diff`（决策 5-C，files/entries+
  path/name/sha256/sha/hash 拼写兼容）在库；`gr6_spot_check` 占位+断言草图注释在案
  （T2 落腿）。脚本 735 行与报告一致。

## 六、预存 flake 定证链与 errata

**flake**：`viewport_settings_menu::a_preset_picked_in_the_quality_menu_holds_and_
the_menu_shows_it`（viewport_settings_menu.rs:192 "the defaults are the High preset"）。
程序 A/B 定证链核实+QA 独立补证：

| 跑 | 形态 | 结果 | 归档 |
|---|---|---|---|
| 程序 A | 全量（含新模块，167） | 166/1 红，同签名 | t19t1_viewport_flake.log |
| **QA A'** | 全量（含新模块，167） | **166/1 红，同签名** | t19t1_qa_gates.log |
| 程序 B（声称） | 摘除新模块全量（165） | 声称 164/1——**归档缺失**（errata E4） | — |
| **QA B'** | 摘除新模块全量（165，QA 手摘手还原） | **164/1 红，同签名**——程序声称被 QA 独立复现补证 | t19t1_qa_flake_b_run.log |
| QA 隔离 | 单测隔离 | **绿（1/1）** | t19t1_qa_targeted.log |

结构性证据：提交 `src/`/`crates/` 零改动（亲验 git diff 为空）——B' 跑的二进制与
main 产品面全同。**「flake 预存、非 T19 引入」定证成立**。且注意频率：今日全量并行
跑 **2/2 红**（QA A'+B'），非偶发——机理候选（并行共享 `JACKDAW_CONFIG_DIR`
viewport.json 并发写撞启动读档窗/菜单 settle 时序）归档质量可接受，但建议主控尽快
按候选 W 票立账（测试基建域），T2 L10 视口菜单回归腿需预留隔离跑兜底。
**「只记不修」裁定建议：维持**（T19 范围外，产品零改动的前提下无修的授权面）。

**Errata（程序报告勘误，不改裁决）**：
- E1：归档件数——报告/任务口径「t19t1_* 11 件」，实际 **10 件**。
- E2：「×17 调用」实为 **16 次** operator 调用（2 preset+quality.set+8 show.toggle+
  ssao.set+sharpen.set+realtime+stats+stats.graph）；「17 项逐字段断言」实为 **19 条**
  assert。口径变化不改覆盖面实质（覆盖只多不少的声明仍保守成立——19 字段≥17）。
- E3：「新文件 242 行（fmt 后）」实为 **307 行**。
- E4：B 跑（摘模块 164/165）**未归档日志**——QA 已独立复现补证（上表 B'），建议
  后续 A/B 定证一律双跑双归档。
- E5（备注）：t19t1_gates.log 中 `PHY_EXIT=`/`LIBTESTS_EXIT=` 回显为空（脚本 `$?`
  捕获笔误），证据以 Finished/无告警行与 QA 亲跑为准。

## 七、放行 T19-T2 建议（真机矩阵轮交接）

1. **prep 冷编预算**：fixture `.jackdaw/target`（18G）已再次被 QA 清除（磁盘门禁
   需要）——T2 **必须**先跑 `prep` 相（~10 分钟冷编预算单列）；种子文档在盘
   （SHA `655892c6…` 亲验），seed 相走幂等跳写只验证。
2. **entity 按名**：`component.add {"entity":"Root",...}`；`resolve_entity_params`
   String→按名、Int→按 id，裸 id 字符串不解析（boot_ops.rs:470-510 亲读确认）。
3. **f32 epsilon**：种子断言一律 `abs(diff)<0.001`（jq 与 Rust 同口径）；别写 `==0.8`。
4. **判红 confirm_red 纪律**：任何「无变化」判红必过两张同态新帧互证；AA/画质切换后
   `settle_pixels 3`+首拍丢弃；编辑器视口用 shot+pixdiff %，游戏窗口用
   screencapture+crop_md5 变/不变（决策 1 分工）。
5. **M10 强度**：`manifest_diff` 全清单 diff（决策 5-C），结构意外回落 scene.bsn SHA
   单点（A 案）。
6. **L3 PIE 腿**：GR8 按构造忠实案保 PX 红绿；与组件读回矛盾即触发回落（数值轨+GR8
   记档）；N13 绕行纪律照旧。
7. **flake 兜底**：`a_preset_picked` 今日全量 2/2 红——L10 若再红按「隔离跑定证」
   口径处理并记入候选 W 票证据；勿在 T19 内修。
8. **磁盘**：export/staged 腿前清 workspace `target/debug/deps` 陈旧工件（当前 212G）；
   腿间 df，A6 单触发源纪律。
9. **GR6 抽查**：A 区腿顺带落 `gr6_spot_check` 断言（Sun/Point Shadows 像素红绿+
   shadow resource 数值半）；像素 flat+数值动=R12 形态，记 GR 红证不修。

## 八、QA 亲跑证据清单（loop/reports/）

t19t1_qa_fmt.log / t19t1_qa_clippy_ws.log / t19t1_qa_gates.log（物理双包+libtests 摘要+
viewport 全量+surface+AN2）/ t19t1_qa_libtests.log（全文，3001/0）/ t19t1_qa_targeted.log
（新守卫 2+graphics_panel 8+flake 隔离绿）/ t19t1_qa_selftest.log / t19t1_qa_drill1_
byte_guard_red.log / t19t1_qa_drill1b_byte_guard_red.log / t19t1_qa_drill1c_byte_tripwire_
red.log / t19t1_qa_flake_b_run.log。共 10 件。演练/摘模编辑已全部还原，`git status`
仅余本清单新件。
