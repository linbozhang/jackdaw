# T19 任务 2「真机矩阵轮」QA 验收报告

> QA 回流（2026-10-28 轮，真机证据产生于 2026-10-31 深夜程序轮）；对象=程序提交
> `125e6545`（分支 `loop/t19-graphics`，自 main `72a7ba10`）+程序报告
> `loop/reports/t19-t2-report.md`；方案 `loop/plans/t19-graphics-parity.md` §二矩阵/
> §三 L 腿/§四-T2+决策表（主控 8 点全按建议）；T1 交接口径八条硬条件逐条执行核实。
> QA 纪律：只读+亲跑+写报告（亲跑证据归档 `loop/reports/t19t2_qa_*` 7 件，见 §八）；
> 产品代码、buglist、台账零改动；全程未设 RUST_BACKTRACE；结束时零残留编辑器/游戏
> 进程（pgrep 亲验 0/0）；loop markdown 只用 Read/Edit/Write。

## 裁决：**PASS**（附 6 条 errata 勘误+1 条 QA 发现+放行 T19-T3 条件，见 §六/§七）

任务书 T2 四条验收标准逐一核过：①M4-M7（Play/导出生效）全绿=铁证①——**成立**
（三站数值脸逐字段一致 QA 亲读日志原文+像素红绿四组 QA 亲自重算逐字复现，§三）；
②M9-M12（不污染）全绿=铁证②——**成立且 QA 亲跑 M9 活体腿复现**（今日树上三点
SHA 恒等+无脏弹窗，§四）；③M13/M14（GI 保持）全绿=铁证③——**成立**
（`ui_click` 拒绝经源码核实即 InteractionDisabled 活体证明，等价性成立，§五-2）；
④M16 存活腿全过——**成立**（三相终态 BRP 活+pid；N13 四条命中全部归属
`pie::drain_game_events`）。四门禁+受影响域全绿（QA 全部亲跑，§一）。
**产品零改动亲验**：`git diff 72a7ba10..125e6545 -- src/ crates/ book/ templates/`
为空；改动面=`loop/qa/t19-live.sh`（735→1,708 行，+1002/−29）+证据归档 52 文件——
回滚声明「删脚本与归档」属实。GR8 独立性判定：**L3 首拍忠实案成立不触发回落**
（QA 亲自重算 13.78%/mean 2.156 与归档逐字一致，且与组件读回 bloom 0.8→退场同向，
§三-GR8）——T1 遗留硬条件兑现。

## 一、门禁亲跑（全部 QA 手跑，后台+轮询；日志归档 t19t2_qa_*）

df 门**先清后跑**：门前出口 9.5Gi（与任务书口径一致）→QA 清 fixture
`.jackdaw/t19-graphics/.jackdaw/target`（20G）→出口 29Gi→门禁开跑；fixture 场景
SHA 亲验无损（仍=种子 `655892c6…`）。

| 门 | 命令 | QA 亲跑结果 | QA 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **EXIT=0，零 Diff** | t19t2_qa_fmt.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **EXIT=0**（52s 增量；全文零 error/warning） | t19t2_qa_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | **EXIT=0** | t19t2_qa_physics.log |
| 单测 | `cargo test --workspace --lib` | **passed=3001 failed=0**（QA 对全文逐行求和恰合 3001，与 T1 基线同值） | t19t2_qa_libtests.log |
| graphics_panel 回归 | `cargo test -p jackdaw --test viewport graphics_panel` | **8 passed，0 failed** | t19t2_qa_targeted.log |
| GR2 负向守卫 | 同上 `graphics_prefs_clean` | **2 passed，0 failed** | t19t2_qa_targeted.log |
| flake 隔离 | 同上 `viewport_settings_menu` 隔离 | **12 passed，0 failed**（隔离口径不复发，与程序归档 12/12 交叉一致） | t19t2_qa_targeted.log |
| surface 族 | `cargo test -p jackdaw_surface` | **52 passed，0 failed**（QA 补全量捕获重跑，见 errata E5） | t19t2_qa_targeted.log（尾部附全量捕获） |
| AN2 腿 | `cargo nextest run -p jackdaw_runtime --features animation --test animation_scene_load` | **1 passed**（T15 转活先例维持） | t19t2_qa_targeted.log |

与程序归档（t19t2_gates_clippy.log/t19t2_gates_tests.log）交叉一致。README 门禁证据
标准「日志全文复核」双端满足（程序侧 SURFACE 段截断缺陷见 errata E5，以 QA 全量重跑
补证）。

## 二、矩阵逐格核实（抽 4 格证据原文全读+全格交叉）

**抽读四格=任务书建议格，全部证据原文亲读+可重算量值亲自重算：**

- **M1（曝光，document 脸+像素红绿）**：console 原文——probe 两拼写双双 -23402
  （全文在档：`did not register the ReflectSerialize…`/`Unknown component type`）→
  `M1 numeric via document:13.0`；像素对 QA 以独立 python 解码器（PNG 全滤波行还原+
  通道和>12 判据，与脚本 pixdiff 语义逐步对源）重算：**100.00% changed / mean 73.359
  ——与归档逐字一致**。
- **M5（direct parity）**：seed_face 原文 `{"bloom": 0.800000011920929, …, "smaa_
  present": true, "tonemapping": "TonyMcMapface"}`；QA 重算游戏窗口对 **42.94% /
  mean 5.129 逐字复现**；M5 restore 种子 SHA 回位原文在档。
- **M9-M12（负向四腿）**：①SHA 三点=M9 段脚本逻辑亲读（前/套件后/save 后三点恒等
  +`jackdaw/status` dialog 恒空判据）+QA 今日活体复跑（§四）；②manifest 全清单
  diff=QA 以脚本同语义独立重算：before/after 各 9 条目、only-before/only-after/
  value-diff 全零、scene.bsn 行 SHA 相等、`generated_unix` 1793458783→1793458834
  前进（重跑感知守卫真开火过）；③相机矩阵恒等=M11 两态 face 原文逐字段相同+
  `faces_equal` 语义亲读（数值 epsilon 0.001）；④CONFIG_DIR 隔离=M12 双 PASS 原文
  （scratch 面 `render_scale:50`+工程树零 viewport.json+无 override 读回用户级
  100）——QA 另亲验今日用户级 `~/Library/Application Support/jackdaw/viewport.json`
  在盘且 `render_scale:100`（per-user 语义的持续活证）。
- **L7/M13（GI 行 InteractionDisabled 活体）**：拒绝原文
  `{"code":-32602,"message":"the control is disabled (checkbox )"}` 在档；源码亲读
  `ui_probe.rs:96-107`——`disabled_by_ancestor` 只在祖先链带 `InteractionDisabled`
  组件时拒绝——**拒绝即活体**（详见 §五-2）；置灰截图 QA 亲目验：Realtime GI 行
  灰显（与上方明亮行对比明显）、面板值 13.00/0.80 在场。

**其余各格交叉核实（日志原文+脚本对源）**：M2 组件读回精确
（`Bloom{intensity:0.800000011920929}`，类型路径证据在档）+像素对 QA 重算 28.95%/3.890
逐字一致；M3 `-23403 not present` 边界原文在档；M4 bloom-0 组件退场判据与产品语义
闭环（`dress_post` 的 `bloom_intensity > 0.0` 闸，`crates/jackdaw_surface/src/
environment.rs:696-703` 亲读——0 值走 `restore_bloom` 退场，判据非脚本臆造）+GR8
见 §三；M6 staged SHA==工程 SHA（manifest-scene-line.txt=种子 SHA）+staged face
+截图在档；M7 三站 Smaa PASS+Keep 退场 `smaa_present:false` 原文在档；M8 12.5
往返+复原种子 SHA 原文在档；M14 QA 静态亲扫（workspace/全 crate Cargo.toml 零
solari 命中、fork `bevy_internal/Cargo.toml:291` `bevy_solari` 仍 optional、
src/crates rs 零引用）；M15 游戏通道 `smaa_present:false`（dress 消失）+复原种子
SHA——编辑器空态提示半格为弱证据（QA 发现 F1，§六）；M16 三相 alive+warn 全归因。

**L1-L10 腿**：L1（PREP_OK+seed 幂等跳写+L1_PRESET_FACE 文件脸翻转+L1_SEED_VERIFY
epsilon 读回）原文在档；L2/L3/L4/L5/L6/L7/L8 如上；L9 像素归档在盘（QA 重算四组
即其证明）；L10 隔离 12/12 双端一致+真机三相期间 flake 未同窗出现（门链单独跑纪律
在案）。

## 三、三铁证+GR8 独立性判定

- **铁证①（Play+导出生效）成立**：三站数值脸逐字段一致（PIE 755v0/direct 761v0/
  staged 三份 face 原文同值：bloom 0.800000011920929+TonyMcMapface+Smaa 在+Msaa
  Sample4 恒定）；bloom-0 态三站组件同步退场（PIE/Direct 断言+staged 由 M7 Keep
  退场同法背书）；像素红绿四组 QA 亲算复现（M1 100.00%/M2 28.95%/GR8 13.78%/M5
  42.94%，与 feature-08 先例 77.11%/3.89% 同量级）；AA 三站=M7 PIE/DIRECT/STAGED
  SMAA 三 PASS+Keep 退场；M8 保存-重开往返=「编辑→保存→重开→Play→导出」编辑器
  半边闭合。
- **铁证②（不污染）成立**：M9 文档 SHA 三点恒等（QA 今日活体复跑 PASS，§四）+
  无脏弹窗；M10 全清单 diff 空+新写证明+staged 字节相等；M11 两态恒等；M12 隔离
  +per-user 活证（QA 亲验盘面持续态）。四腿全绿。
- **铁证③（GI 保持禁用说明）成立**：M13 拒绝活体（源码闭环 §五-2）+置灰截图亲目
  验+tooltip 文案脸=H 锚（T1 复跑绿，本轮 8 件再绿）；M14 warn 扫描六份日志零
  solari/ray 命中+静态面 QA 亲扫全零。
- **GR8 独立性判定：忠实案成立，不触发决策 4 回落**。L3 首拍为真机 PX（T1 硬条件
  兑现）：bloom 0.8→0 两态流送帧对 QA 重算 **13.78% changed / mean 2.156 逐字复现**
  ，与组件读回（bloom 0.8→组件退场）同向一致；判红纪律在位（flat 时先走
  confirm_red 式新帧互证再落红，脚本 :1417-1429 亲读）；N13 绕行记数在档（2 次
  PIE play × 每相 2 条命中，全部 `pie::drain_game_events` 归属）。M4 保留 PX 红绿
  （决策 4 忠实分支）执行正确。

## 四、M8 种子 SHA 精确复原+flake 隔离（候选 W 票素材）

- **种子 SHA 锚亲验**：`655892c6c28327866acaa52c71a1ff510f9d963144b28864d257e1422e9
  a99a9`——QA 今日在盘重算与报告/方案逐字一致；M4/M5/M8/M15 四处 restore 日志行
  全部「seed SHA back/RESTORE DRIFT 双向断言」在档；QA M9 活体腿终态再证复原。
- **flake 隔离 12/12 不复发**：程序归档（t19t2_gates_tests.log）与 QA 亲跑（
  t19t2_qa_targeted.log）双端隔离跑全绿；真机三相期间未同窗出现。与 T1 定证链
  （全量并行 2/2 红）合并看，候选 W 票素材完整（全量并行红/隔离绿/零产品改动时
  同样红=预存），维持「不修、立候选 W 票」口径。

## 五、主要偏差 4 条裁定（QA 逐条复核）

1. **偏差 1（Exposure 组件读回结构性不可用）——ACCEPT**。源码闭环：fork
   `bevy_camera/src/camera.rs:230-233` `#[derive(Reflect)] #[reflect(opaque)]` 且
   无 ReflectSerialize 注册——-23402 拒绝是结构必然而非脚本/产品缺陷（红证 run2
   与终版日志各存一份错误全文）。降级口径核实：数值脸=document face（world.query
   读 Environment.post.exposure，M1/M8 两处原文）+同一 insert 块相邻字段
   （`dress_post` 的 `camera.insert((tonemapping, Exposure, color_grading))`
   environment.rs:689-694 亲读——Bloom/Tonemapping 与 Exposure 同块插入，组件脸由
   M2 的 Bloom 精确读回代言）+H 锚（`post_settings_reach_the_camera_components`
   把 doc→组件映射钉进 CI，本轮 surface 52 件含之再绿）+像素轨。分层合围成立，
   「组件级读回需 fork 注册 ReflectSerialize」的后续定位如实。
2. **偏差 2（tooltip 不可驱动=click 拒绝即活体禁用证据）——ACCEPT，等价性成立且
   实为更强**。`ui_probe.rs:96-107` 亲读：拒绝只在祖先链存在 `InteractionDisabled`
   组件时发生——「拒绝」是该组件在场的运行时直接证明，强于截图的目验灰显；置灰
   截图同时在场（双证）。ui_drag 两次探针（hover 无 popover）在 run2 归档
   （`t19t2_editor_run2_wrong-cam.log:38` 原文「the Solari tooltip never surfaced
   in the tree」）；文案脸维持 H 锚（graphics_panel.rs:373-394 本轮隔离跑 8 件
   再绿）。真机 tooltip 需 sustained hover=合成输入面边界，MCP 优先原则的
   「ui_hover 类方法」记为候选工具票（超 T19 授权，不阻裁决）。
3. **偏差 3（M7 期望修正：Msaa::Off→Keep 语义）——ACCEPT**。fork
   `bevy_render/src/view/mod.rs:248-254` `#[default] Sample4` 亲读；dress 侧
   `Multisampling::Keep => None`→`restore(camera, undressed.msaa)`（
   environment.rs:733-739+枚举文档「The cameras keep what they have」）亲读；且
   M15 无环境对照亦 Sample4=实证非 dress 面。方案 M7 原文「Smaa 在+Msaa::Off」为
   基线期推断，修正判据「Smaa 在/退场+Msaa 恒定（M11 恒等腿覆盖）」与真机事实及
   源码一致，如实记档处置正确。
4. **偏差 4（六轮脚本面红→绿纪律）——ACCEPT**。六份红证 QA 逐份亲读，与叙事逐条
   对上：①run1 editor=`ECOMP_ERRORS: unbound variable`（line 1032，$() 子shell
   全局丢失）；②run2 editor=裸查询错相机（3778v0，M1/M2/M3/M8/M13 连红——错相机
   读的是别的 Camera3d）+**-23402 错误全文首次入档**；③run1 game=menu-scene
   （M5 face `{}` 空世界）；④run2 game=M5a bloom null 竞态；⑤run3 game=save-
   before-play 假红（N13 计数 4 与两轮 PIE 窗口吻合）；⑥run1 export=M10
   `manifest_ts=1793458428->1793458428` 不前进（SHA 被旧树预满足）。六处修正全部
   脚本面（ecam 换 camera_state/game_face 双拼写/direct_run 等相机/M4 显式
   save/restore/export_wait started_at 判据——脚本相应段落亲读在位），产品面零
   改动由 git diff 为证。红态先归档再修正纪律（T16 首例）延续属实。

## 六、Errata（程序报告勘误，不改裁决）与 QA 发现

- **E1**：「17 张通道 PNG」（报告 §八/任务口径）实为 **14 张**——报告自己的枚举
  （m1×2+m2×2+m4×2+m5×2+m6×1+gr6×4+m13×1）与 `ls` 均为 14。
- **E2**：`config-scratch/`（M12 scratch 面文件脸）**未归档**——报告 §八声称在
  `loop/t19-live/` 下，实际不存在（`SCRATCH_CONFIG="$OUTDIR/config-scratch"` 亲
  读）。M12 判据的文本证据（scratch face JSON+per-user face）在 console 原文中
  完整，QA 另验用户级文件在盘，格不翻；归档缺口照实记。
- **E3**：脚本行数「735→约 1,100 行」实为 **1,708 行**（+1002/−29，任务书口径
  +1002 行与此吻合）。
- **E4**：M9「A 区 16 次 operator」实为活体套件 **15 次**（a_region_suite：1
  preset+1 quality.set+8 show.toggle+ssao+sharpen+realtime+stats+graph；T1 headless
  守卫的 16 次含双 preset，两者勿混）。
- **E5**：程序门禁归档 `t19t2_gates_tests.log` 的 SURFACE 段被 `tail -5` 截到
  doc-tests 尾（「running 0 tests」）——52 passed 行未入档。QA 全量捕获重跑补证
  **52 passed 属实**；后续归档应全文或 grep "test result" 捕获（QA 归档已附全量
  段）。
- **E6**：`shot-m13-gi-panel.png` 入镜一枚「Recovered Work」恢复对话框（seed→
  editor 相转场 pkill 的恢复日志；时间戳与转场吻合）——GI 行置灰与面板值不被遮挡
  （QA 亲目验），报告 §六-8 未提及，照实补记。M9 判据的 dialog 断言未受影响
  （套件后 dialog 恒空在档）。
- **F1（QA 发现，非 errata）**：**M15 的编辑器空态提示半格判据无区分力**——
  `walk_has "This scene has no environment"` 是存在性检查：`ui_tree` 的
  `visible` 字段只跟踪 bevy `Visibility`（`ui_probe.rs:107-125` 亲读），不跟踪
  UI `Display::None`；空态提示节点在**两态** walk 中均 `visible:true`（QA 对
  walk-editor.json[种子态]与 walk-game.json[剥离态]双亲读实证）。即该 PASS 不证
  明提示可见。格维持绿：M15 判据由游戏通道（smaa 退场=dress 消失，强证据）+
  复原 SHA 承载，提示可见性由 H 锚 `the_scene_empty_hint_follows_the_scenes_
  environment`（graphics_panel.rs:433-465 三态断言，本轮隔离跑绿）钉住。候选改进
  （T19 范围外）：ui_tree 暴露 Display 或新 ui_hover 类工具一并立项。

## 七、放行 T19-T3 建议

1. **prep 预算重置**：QA 已为 df 门再次清 fixture `.jackdaw/target`（20G，门前
   9.5Gi→清后 29Gi）——T3 prep 相 **~7-10 分钟冷编预算单列**（种子文档在盘，
   SHA 亲验，seed 相幂等跳写只验证）。
2. **book 扩节书单交接（决策 8-A，只扩 `book/src/user-guide/graphics-panel.md`，
   不另立新章）**：「Play 与导出」节素材=同一 EnvironmentPlugin 两侧同链/四通道
   一致性结论（M4-M6 三站逐字段+M7 三站）/场景 AA 只在游戏通道生效（M3 边界+
   M7）/PIE 流送帧忠实（GR8 案）；「编辑器偏好与游戏」节素材=viewport.json 用户级
   （M12 双腿+per-user 语义）/三不变边界（M9 SHA/M10 包/M11 数值）/GR3 注记
   「场景 AA 走 Inspector」/GR7 开箱空态（空态提示文案在场）；GI 节原文不动
   （「保持」字面兑现=回归通过）。
3. **磁盘清盘口径**：export/staged 腿前清 workspace `target/debug/deps` 陈旧工件
   （target 全目录现 194G）；腿间 df；A6 单触发源纪律照旧；fixture target 是后续
   吃盘大户，T3 结束时可顺手清（下一任务 prep 重温）。
4. **errata E1-E6 请程序随 T3 报告修订一并落**（纯报告/归档面，不触代码）；
   F1/W 票候选（flake、ui_tree display、ui_hover）归主控裁定吸收面，T19 内不修。
5. **复跑注意（程序 §七九条仍全部有效，QA 亲验补三条）**：Exposure 组件读回必红
   （-23402，别当回归）；save-before-play 显式 save/restore 校 SHA；export_wait
   必须用重跑感知版（ts 前进+ready）；sur face 门禁归档用全量捕获（E5 教训）；
   walk 判据避开「仅存在性」的可见性断言（F1 教训）。
6. **30 秒用户清单**（程序草稿可用，QA 按证据修一句）：拖 Exposure 滑条看 Play
   画面变亮变暗（M1 像素 100.00% 背书）；拨视口 Quality Preset 看 Play/导出画面
   不变（M11 恒等+M10 包面背书）；悬停 GI 行看置灰与说明（真机合成驱动做不到
   hover，人工点验）。

## 八、QA 亲跑证据清单（loop/reports/，新增 7 件）

t19t2_qa_fmt.log / t19t2_qa_clippy_ws.log / t19t2_qa_physics.log /
t19t2_qa_libtests.log（全文，3001/0）/ t19t2_qa_targeted.log（graphics_panel 8+
守卫 2+flake 隔离 12+AN2 1+surface 52 全量捕获段）/ t19t2_qa_m9_live.log（QA
活体 M9 腿：三点 SHA 恒等+无脏弹窗+种子复原+存活）/ t19t2_qa_m9_boot.log（该腿
编辑器启动日志）。共 7 件。QA 无临时探针入树；`git status` 仅余本清单新件；
结束时零残留进程；df 出口 26Gi。
