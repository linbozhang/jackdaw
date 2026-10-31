# T19 任务 3「终验 + book 扩节」程序报告

> 分支 `loop/t19-graphics`（`git merge main` 快进到 **b63ab28d**——T2 已在；T3 零 src/、
> 零 crates/、零 templates/ 产品改动，改动面=book 三文件+T2 报告勘误落账+本轮证据归
> 档）；方案 `loop/plans/t19-graphics-parity.md` §四-T3+§六-T3 书单；T2 交接
> `t19-t2-report.md`/`t19-t2-qa.md`（errata 6 条+F1 随本轮落账）。真机 macOS arm64，
> fixture `/Users/zhanglinbo/workspace/loop-mac/t19-graphics/t19-graphics`（BRP 15703，
> game 15702），`cargo build --bin jackdaw` 先行（T18 教训），全程未设 RUST_BACKTRACE。
> **判语：book 扩两节落地（graphics-panel.md 内，不另立新章，GI 节三层文案核对一致原
> 文不动）+三文件交叉引用；T2 QA errata 6 条全部落账（含 E2 config-scratch 补档闭
> 合）；16 格矩阵终态复跑=三相真机 38 判定全 PASS（editor 17/game 14/export 7），量值
> 与 T2 归档同量级同向（M1 100.00%/M2 28.95%/M5 42.92%/GR8 15.13%），种子 SHA 精确回
> 位，N13=2 全归属，warn 扫描干净；全量九门绿——integration **5458/5458 全绿**（A6
> 件本轮未复发，0 红；隔离件无需触发）。** buglist/台账/roadmap 未动（主控合入时落
> 笔）。日期 2026-10-28。

## 〇、最终判定汇总

```
真机复跑（prep+seed+editor+game+export 五相）:
  editor 相 17 判定全 PASS（M1/M2/M3/M8/M9/M12×2/M13×3/L1×2/GR6/M16 + warn/N13）
  game   相 14 判定全 PASS（M4×3 含 GR8/M5×3/M7×3/M11/M15×2/M16 + N13）
  export 相  7 判定全 PASS（M6×3/M7 staged/M10/M16 + warn）
  种子 SHA 三相回位精确 = 655892c6…；N13 计数 game 相=2（全部 pie::drain_game_events）
  warn 扫描（tonemapp|bloom|exposure|solari|ray|UnresolvedTypes|panicked）逐条归属零未解释
门禁（终树; 全文捕获+全文复核）: fmt ✅ / clippy 全仓(--all-targets --features dylib) ✅
  / 物理双包 ✅ / libtests 3001/0（scaffold lib=91=teaches 计数）✅ / fast 3001/3001 ✅
  / integration 5458/5458 全绿（A6 未复发）✅ / doctests 全 workspace 跑完——bind dyld
  第 12 次目击→单包复跑 1/1 绿 ✅ / docs EXIT=0（13 条=同数同族预存树态）✅
  / scaffold_e2e 1/1 ✅
```

归档：`loop/reports/t19t3_*`（console 五相+门禁 log）+`loop/t19-live/` 刷新（含 E2
补档 `config-scratch/`）。

## 一、book 扩节（方案 §四-T3-2+决策 8-A+T2 QA §七-2 书单）

**`book/src/user-guide/graphics-panel.md`** 扩两节（插在 Scene section 与 Realtime GI
之间），**不另立新章**（SUMMARY 不动）：

1. **「Scene quality in Play and export」**（场景级画质在游戏与导出中的呈现）：
   - 同一 `EnvironmentPlugin` 两侧同链——「one piece of code reads the scene's
     `Environment` and dresses each game camera」，Play/direct/导出三通道跑同一份代
     码、无第二实现可漂移（方案事实三的 user 面表述）；
   - T19 一致性矩阵结论如实入文：同值三站（PIE/direct/staged）组件逐字段读回一致；
     场景 AA 拨转三站组件同步开关（M7）；截图红绿证画面真随值变（exposure 重绘帧/
     bloom 重绘画面，M1 100%/M2 28.95%/M5 42.92% 背书）；**GR8 流送帧忠实案**入文
     （Game panel 流送帧与游戏窗口同 dress）；
   - 场景 AA 边界复述：只落游戏相机、编辑器视口恒自有 AA（M3 边界+opt-out 语义回
     指 Scene section 的 previews 注记）；「verify scene AA means running the game」；
   - 导出携带面：staged=整棵 assets 树+scene，无编辑器私件、无自有画质设置（M10 背
     书）；**JPG 等格式边界指路 assets.md**（游戏模板 Bevy features 的诚实表）+
     **AR9 带 meta 注记指路**（compressed 纹理可见面滞留首载的已知角，assets.md 承
     载）——两处均一句指路不重述。
2. **「Editor preferences and the game」**（编辑器偏好与游戏）：
   - viewport.json 用户级语义（config 目录、never in scene/project）+**三不变边界**
     如实入文（M9 场景字节恒等+无脏标记+无 undo 条目/M10 导出包 manifest 全清单+
     scene 字节恒等/M11 视口两态反向设定下游戏相机矩阵恒等）+per-user 语义的迁移面
     （换机/换用户带走的是 authored look 而非 preview dial——M12 双腿背书）；
   - **GR3 注记**：场景 AA 无面板行是设计态——viewport 行自有编辑器 AA，场景 AA 与
     `Environment` 其余字段同处（inspector component fields）；
   - **GR7 开箱空态**：新工程无 `Environment`，四通道同为默认观感，Scene 区空态提示
     在场；**game-flow 指路**（run 的场景来源与导出启动面）。
3. **GI 节核对（原文不动）**：三层文案逐字核对一致——ftl
   `graphics-realtime-gi-tooltip`（main.ftl:36-37）↔ book Realtime GI 节 ↔ H 锚
   （tests/viewport/graphics_panel.rs GI 行三件，本轮 `t19t3_gates_tests.log` 隔离跑
   再绿+editor 相 M13 真机拒绝活体再绿）。「保持」的字面兑现=回归通过即不动（决策
   8-B）。

**交叉引用（graphics-panel↔assets/game-flow 双向）**：`game-flow.md` Cameras 节尾+
一句（level 相机所画=Scene section 所 authored 的场景观感，指路 graphics-panel）；
`assets.md` JPG 边界条目尾+一句（导出携带整棵 assets 树，画质叙事面指路
graphics-panel）。出链目标（assets.md/game-flow.md/graphics-panel.md 相对链接）逐一
核实存在；「Game panel」用词对照 play-in-editor.md 既定名防杜撰（T18 偏差 7 教训）。

## 二、Errata 落账（T2 QA §六 6 条+F1，程序报告面修订，不触代码）

| # | 落账 |
|---|---|
| E1 | `t19-t2-report.md` §八「17 张通道 PNG」→**14 张**（原位修正+标注；枚举与 `ls` 均 14） |
| E2 | **补档闭合**：本轮 editor 相 M12 腿复跑后，`loop/t19-live/config-scratch/` 已在档（scratch viewport.json 文件脸 render_scale:50，与 console 判据行同值）；T2 报告 §八改为如实记（「T2 当轮未归档」+T3 补档指引） |
| E3 | T2 报告头部「735→约 1,100 行」→**735→1,708 行**（原位修正+标注） |
| E4 | T2 报告 M9 行「16 次 operator」→**15 次活体套件**（原位修正+标注；T1 headless 守卫 16 次含双 preset 的口径区分注记保留） |
| E5 | T2 报告 §四 surface 行+§十落账注记：程序归档段被 tail 截断、QA 全量捕获补证 52 passed；本轮门禁归档已按教训全量捕获（`t19t3_gates_tests.log` SURFACE 段完整，52/0 在文） |
| E6 | T2 报告 §六-8+E6 注记：`shot-m13-gi-panel.png` 入镜「Recovered Work」恢复对话框（相转场 pkill 恢复日志），GI 行置灰与面板值不被遮挡，M9 dialog 断言未受影响 |
| F1 | **不涉 book**（空态提示对用户可见性本就成立，判据承载面是 QA 内部口径）：处置=T2 报告 §十记档「空态提示判据以 H 锚三态断言承载（A14 候选工具票）」；M15 格维持绿（游戏通道 smaa 退场=强证据） |

E1/E3/E4 原位修正处均带「E* 勘误」标注，原文数字不灭失（报告面可审计）；T2 QA 报告
本体零触碰。

## 三、关键格终态复跑（方案 §四-T3-1 的抽格口径之上做全矩阵三相复跑）

协调者抽 3 格建议（M1 曝光三站/M9-M12 负向/M8 往返）全部被三相覆盖——本轮直接复跑
editor/game/export 全三相（prep/seed 先行），38 判定全 PASS，证据=`t19t3_console-*.log`：

| 相 | 判定 | 与 T2 归档对齐 |
|---|---|---|
| **editor**（17） | L1_PRESET_FACE/L1_SEED_VERIFY/M1_EXPOSURE_R+PX/M2_BLOOM_R+PX/M3_AA_BOUNDARY/M8_ROUNDTRIP/M9_SHA/M13_GI_ROW+GI_DISABLED+GI_PX/M12_SCRATCH+PER_USER/GR6_SPOT/M16_EDITOR_ALIVE 全 PASS | M1 数值=document 13.0+PX **100.00%/mean 73.359**（与 T2 逐字同值）；M2 组件读回 0.800000011920929+PX **28.95%/3.890**（逐字同值）；M3 -23403 边界原文同形；M8 12.5 往返+种子 SHA 回位；M9 三点 SHA 恒等+dialog 恒空；M12 scratch 50 文件脸+无 override 读回 100；M13 拒绝活体 `-32602 the control is disabled` 同文；GR6 同轮 Inconclusive-by-fixture（sun_shadows 文件脸动了+两帧互证 flat=无承影几何，非 R12 形态） |
| **game**（14） | M4_NUMERIC+PX_STATE+GR8_LIVE/M5_NUMERIC+STATE2+PX/M7_PIE_SMAA+DIRECT_SMAA+KEEP_EXIT/M11_IDENTITY/M15_GAME+EDITOR_HINT/M16 全 PASS | M4/M5 seed face 与 T2 **逐字段同值**（bloom 0.800000011920929+TonyMcMapface+smaa_present true+Msaa Sample4）；bloom-0 组件退场同形；M5 PX **42.92%/5.137**（T2 42.94%/5.129 同量级）；**GR8 流送帧对 15.13%/2.731**（T2 13.78%/2.156 同量级同向——忠实案维持，帧时差浮动如实）；M11 两态恒等 faces_equal；M15 无环境=smaa 退场+空态提示在树 |
| **export**（7） | M6_STAGED_CARRIES+MANIFEST_LINE+NUMERIC/M7_STAGED_SMAA/M10_PACKAGE/M16 全 PASS | staged scene.bsn SHA==工程 SHA（export_wait 重跑感知判据「run advanced (idle -> …) and is ready」）；staged face 同 M4 逐字段；M10 manifest 全清单 diff 空+新写证明（ready -> … 前进）+staged 字节相等 |

- **N13 记数**：editor 相=0；game 相=2（两条 `jackdaw::pie::drain_game_events` panic
  命中，绕行+读回重试绿——与 T2「每 PIE 相 2 次」同形）；export 相=0。
- **warn 扫描**：editor/direct×6/staged 十份日志逐条归属（勘误 2026-10-31 主控落，t19-final-qa 回流②：direct 实为 6 份、总数实为十份）——direct/staged/editor
  （除 N13 两条外）零命中；词表 `tonemapp|bloom|exposure|solari|ray|UnresolvedTypes|
  panicked`。**M14 全链缺席维持**：全程零 solari/ray 命中。
- **种子 SHA 终态**：三相跑毕 `655892c6c28327866acaa52c71a1ff510f9d963144b28864d257
  e1422e9a99a9` 精确回位（盘面亲验）；pgrep 零残留进程。
- 磁盘：门前 21Gi→清 workspace deps 陈旧工件 **126Gi**（21→147Gi，T2 QA 口径：
  保留 10-31 午后暖工件、清除 146,639 件陈旧件）→export 相前 132Gi 复核。

## 四、门禁（终树；日志全文捕获+全文复核，exit 仅辅助；E5 教训执行）

| 门 | 命令 | 结果 | 证据 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | ✅ EXIT=0，零 Diff | t19t3_gates_fmt_clippy.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | ✅ EXIT=0，全文零 error/warning 行 | 同上 |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | ✅ EXIT=0 | 同上 |
| 单测 | `cargo test --workspace --lib` | ✅ **3001 passed / 0 failed**（**scaffold lib=91**=teaches 计数与 T17-T2/T18-T3 一致） | t19t3_gates_tests.log（LIBTESTS 段全量捕获） |
| 受影响域 | graphics_panel 8+graphics_prefs_clean 2+surface 全量 52+AN2 1+viewport_settings_menu 隔离 12 | ✅ 全绿（六段全量捕获；flake 隔离口径不复发——候选 W 票口径维持） | 同上 |
| fast | `cargo xtask fast` | ✅ **Summary: 3001 tests run: 3001 passed, 0 skipped**（23.6s） | t19t3_gates_fast.log |
| integration | `cargo xtask integration` | ✅ **5458 run: 5458 passed, 0 skipped**（551.3s；A6 `prefab_file_change_triggers_reload` 本轮 **PASS 未复发**——0 红口径达成，隔离件无需触发；总数 5458=T18 时代 5456+T19 期自然增长） | t19t3_gates_integration.log |
| doctests | `cargo test --workspace --doc` | ✅ 全 workspace 跑完；`jackdaw_bind` dyld `libstd-*.dylib not loaded` **第 12 次目击**（T17 第 10/T18 第 11 同族）→**T15 处方单包复跑 `-p jackdaw_bind --doc` 全绿（EXIT=0）** | t19t3_gates_doctests_docs_scaffold.log + t19t3_gates_doctests_bind_rerun.log |
| docs | `cargo doc --workspace --no-deps` | ✅ EXIT=0；**13 条警告与 T17/T18 基线同数同族**（jackdaw 10+api_internal 1+project_build 1+remote 1，private-doc-link 家族+StateEvent::Log+dylib doctest 注记——本轮零 src/ 改动，预存树态） | 同上（对照 t18t3_qa_doc.log） |
| scaffold_e2e | `cargo nextest run --profile ci -p jackdaw --test scaffold_e2e` | ✅ **1/1 PASS** EXIT=0 | 同上 |

## 五、偏差清单（如实分级）

| # | 级 | 偏差 | 处置 |
|---|---|---|---|
| 1 | S | **M1/M8 的 Exposure 组件读回必红重现**（-23402 ReflectSerialize 缺席，两拼写探针原文在档） | 已知工具链边界（T2 偏差 1 QA ACCEPT），非回归；数值脸=document face+相邻字段+像素轨合围，判据不变 |
| 2 | S | **GR8/M5 像素量值浮动**：GR8 13.78%→15.13%、M5 42.94%→42.92%、M4 流送对 5939136 像素基准（窗口尺寸面同） | 同量级同向——像素轨是「画面随值变」的判据不是恒等判据（决策 1-A），浮动=帧时差/窗口 chrome；判据过阈（≥1%）远超浮动带 |
| 3 | M | **GR6 同轮 Inconclusive-by-fixture**（sun_shadows 文件脸动+像素两帧互证 flat） | 与 T2 同形（fixture 无承影几何）；维持「R12 本体不吸收，T20 有承影体场景顺手补腿」口径 |
| 4 | M | **seed 相 -23501 resource face**（`Unknown resource type ViewportSettings`） | L1 预期形态（脚本注释明言 file face 在 editor 相承载）；本轮 L1_PRESET_FACE 文件脸翻转 PASS 闭合 |
| 5 | M | **book 无 mdbook 本地渲染验证**（工具不在 PATH） | 链接全部相对路径+目标文件逐一核实存在；「Game panel」等 UI 名对照 play-in-editor.md 既有用词；mdbook 渲染面留 QA/主控环境复核 |
| 6 | 备注 | M13 置灰截图本轮无「Recovered Work」浮层（E6 教训的转场恢复窗未再触发）；N13 game 相 2 条与 T2 同数；doctests bind dyld 第 12 次目击（T17 第 10/T18 第 11 同族，单包复跑绿双 log 归档）；docs 13 条警告=T17/T18 基线同数同族（零 src/ 改动，预存树态不修不扩）；门禁链与真机不同窗（T12-T3 §九-7 纪律）；integration 本轮全绿（A6 未复发，与 t16/t17「唯一红=A6」时代口径的差异=flaky 家族本轮未触发，非口径变更）；buglist/台账/roadmap 零触碰；fork 零改动；RUST_BACKTRACE 全程未设 | 照实记档 |

## 六、给 QA（终验）的注意事项

1. **复核顺序**：先 `t19t3_console-editor.log`（M1/M2 像素对+M12 双 PASS+M13 拒绝活
   体）→`t19t3_console-game.log`（seed face 逐字段+GR8+M11 恒等+N13 归属）→
   `t19t3_console-export.log`（SHA 判据+M10 diff 空）→门禁 log 全文（integration 唯
   一红应=A6，隔离件对照）。
2. **预期红/形态清单**：①Exposure 组件 get_components 必红 -23402（偏差 1，勿当回
   归）；②seed 相 -23501 resource face（偏差 4）；③GR6 Inconclusive-by-fixture
   （PASS 判定内的 verdict 行，非红）；④doctests `jackdaw_bind` dyld 家族（本轮第 12
   次目击，单包复跑已绿归档——全 workspace 重跑再遇同形照 T15 处方复跑即可，勿当回
   归）；⑤integration 本轮全绿（A6 未复发）——若 QA 复跑遇 A6 红，按既有口径隔离复
   跑对照（t16/t17/t18 归档同族）。**①-④之外出现任何红=新缺陷。**
3. **E2 补档验证**：`loop/t19-live/config-scratch/viewport.json` 应 render_scale:50
   文件脸（与 console-editor.log 的 M12_SCRATCH_PASS 行同值对读）。
4. **量值锚**（与 T2 归档对照）：M1 100.00%/73.359；M2 28.95%/3.890；M5 42.92%/5.137；
   GR8 15.13%/2.731（13.78%→15.13% 为帧时差浮动，判据=过阈+同向，勿要求逐字复现）；
   seed face 四字段与 M4/M5/M6 三站同值；种子 SHA `655892c6…`。
5. **book 校对锚**：两节断言对照源码面——同一插件两侧（`src/lib.rs:452` 与
   `crates/jackdaw_runtime/src/lib.rs:347` 装 `EnvironmentPlugin`）、AA 边界
   （`src/viewport_quality.rs:93-102` opt-out 恒真）、导出携带（`crates/
   jackdaw_project_build/src/export.rs` copy_tree 名单）、per-user（`crates/
   jackdaw_env/src/paths.rs:59-62`+`src/viewport_settings.rs:3-6` 文件头 doc）、GR3
   （B 区 4 行无 AA）、GR7（`crates/jackdaw_scaffold/templates/game/assets/scene.bsn`
   无 Environment）；GI 节=ftl:36-37 逐字同源。
6. **30 秒用户清单**（T2 QA 修正式维持）：拖 Exposure 滑条看 Play 画面变亮变暗（M1
   100.00% 背书）；拨视口 Quality Preset 看 Play/导出画面不变（M11 恒等+M10 包面背
   书）；悬停 GI 行看置灰与说明（合成驱动做不到 hover，人工点验）。
7. **复跑口径**（如需）：`cargo build --bin jackdaw` 先行→`bash loop/qa/t19-live.sh
   prep && … seed && … editor/game/export`（各相独立启停，trap 清场）；export 相前
   df 复核；勿设 RUST_BACKTRACE；门禁与真机不同窗；结束 pkill+pgrep 复核。

## 七、产物清单

- `book/src/user-guide/graphics-panel.md`（+两节）、`book/src/user-guide/game-flow.md`
  （+一句交叉引用）、`book/src/user-guide/assets.md`（+一句交叉引用）
- `loop/reports/t19-t2-report.md`（errata 落账：E1/E3/E4 原位修正+E5/E6 注记+§十落
  账节+F1 处置）
- `loop/t19-live/` 刷新：五相 console+walk/shot 刷新+**config-scratch/ 补档（E2）**
  +manifest 刷新
- 归档 `loop/reports/t19t3_*`：console-prep/seed/editor/game/export 五件+gates_fmt_
  clippy/gates_tests/gates_fast/gates_integration/gates_doctests_docs_scaffold/
  gates_doctests_bind_rerun 八件门禁 log（integration 全绿无隔离件）
