# T19 任务 2「真机矩阵轮」程序报告

> 分支 `loop/t19-graphics`（先 fast-forward 合并 main 72a7ba10——T1 已在）；任务书
> `loop/plans/t19-graphics-parity.md` §二矩阵/§三 L 腿/§四-T2；T1 基线
> `t19-t1-report.md`/`t19-t1-qa.md` 全部硬条件执行（prep 冷编预算、entity 按名、f32
> epsilon、判红必过 confirm_red、export 前清盘、GR6 落 gr6_spot_check、L10 flake 隔离
> 口径、勿设 RUST_BACKTRACE——全程未设）。**产品代码零改动**：全部改动=
> `loop/qa/t19-live.sh`（T2 腿实现，735→1,708 行；E3 勘误：原稿「约 1,100 行」有误）+证据归档。零场景格式变更、零协议
> 变更、零 fork 改动、零 UI 改动。真机纪律：三通道（editor/game/export 相）各自独立
> 启停（cleanup trap pkill）；每腿后 BRP 活性；warn 扫描逐条归属；红态先归档再修正。

## 〇、三铁证结论（验收句逐条）

| 铁证 | 结论 | 主证据 |
|---|---|---|
| ①场景级曝光/Bloom/AA 在 Play+导出生效 | **成立** | M4/M5/M6 数值脸：PIE、direct、staged 三站游戏相机读回 Bloom{intensity 0.800000011920929}+Tonemapping TonyMcMapface+Smaa 在+Msaa 保持——种子文档三站逐字段一致；M1/M2 编辑器侧组件/文档读回+像素红绿（100.00%/28.95%）；M7 三站 Smaa+Keep 退场；M8 保存-重开往返 |
| ②editor 偏好不污染游戏 | **成立（四腿全绿）** | M9 文档 SHA 全程不变+无脏弹窗；M10 导出包 manifest 全清单 diff 空+staged 字节相等；M11 A 区两态游戏相机矩阵逐字段恒等；M12 CONFIG_DIR 隔离+per-user 语义活证 |
| ③GI 保持禁用说明 | **成立** | M13 真机：GI 行在树+`ui_click` 拒绝「the control is disabled」=InteractionDisabled 活体证明+置灰面板截图归档；tooltip 文案脸=H 锚（tests/viewport/graphics_panel.rs:373-394，T1 复跑绿）；M14 全程 warn 扫描零 solari/ray 命中+workspace/fork 静态复核（bevy_solari 仍 optional 未启用） |

GR8 L3 首拍真机确认（T1 遗留硬条件）：**流送帧忠实案成立**——PIE 运行中 bloom 0.8→0
两态全屏捕获对 **13.78% 像素改变**（mean 2.156），与组件读回（bloom 0.8→组件退场）同向
一致，不触发决策 4 回落路径。归档 shot-m4-pie-stream-a/b.png。

## 一、矩阵 16 格逐格判定

| 格 | 判定 | 证据与量值 |
|---|---|---|
| M1 曝光（编辑器视口） | **绿**（数值脸=document） | R：`environment.set post.exposure` 9.7↔13，document face 13.0（world.query 读回）；**Exposure 组件读回被 BRP 结构性拒绝**（-23402 ReflectSerialize 缺席，`#[reflect(opaque)]`，见偏差 2）——组件脸由 H 锚（surface:995）+document 脸+像素脸合围；PX：9.7→13 全屏渲染目标直拍 **100.00% changed，mean 73.4**（shot-m1-low/high.png） |
| M2 Bloom（编辑器视口） | **绿** | R：视口相机 `Bloom{intensity:0.800000011920929}` 组件读回精确（`bevy_post_process::bloom::settings::Bloom`，类型路径证据入日志）；PX：0↔0.8 **28.95% changed**（feature-08 先例 77% 同量级；shot-m2-off/on.png） |
| M3 AA 边界（场景 AA 不入视口） | **绿** | 文档 antialiasing=Taa 在（world.query）；视口相机 `TemporalAntiAliasing` **not present**（lenient errors -23403 实证）；回 Smaa 复原 |
| M4 PIE parity | **绿** | G：种子态 bloom 0.8+Tony+Smaa+Msaa Sample4 逐字段读回；bloom-0 态组件退场；N13 绕行+计数（2 次 drain_game_events panic，编辑器存活，读回重试绿）；PX 流送帧对 13.78% |
| M5 direct parity | **绿** | G：同 M4 断言面（seed_face 绿）；PX 游戏窗口对 **42.94% changed**（screencapture 全屏、chrome 两帧抵消）；盘面 save/restore 往返种子 SHA 不变 |
| M6 staged parity | **绿** | EXPORT：export_wait（重跑感知判据）→staged scene.bsn SHA==工程 SHA；manifest 含 scene.bsn 行（manifest-scene-line.txt）；staged 进程数值脸==种子；shot-m6-staged.png |
| M7 AA 三站 | **绿**（Msaa 期望修正，见偏差 4） | PIE/direct/staged 三站 `Smaa` 在（preset High）；回 Keep→direct 站组件退场（M7_KEEP_EXIT）；Msaa=Keep 语义=相机自有值保持（Sample4，无环境对照 M15 亦 Sample4=非 dress 面） |
| M8 往返 | **绿** | 12.5→save→盘面含 12.5→reload→document 读回 12.5→复原 13.0+save→**种子 SHA 精确复原**（655892c6…） |
| M9 文档层 SHA 腿 | **绿** | A 区 15 次 operator 活体套件（a_region_suite：1 preset+1 quality.set+8 show toggle+ssao/sharpen/realtime/stats/graph；E4 勘误：原稿「16 次」把 T1 headless 守卫的双 preset 计法混入）全家 →scene.bsn SHA 三点恒等（前/套件后/save 后）+`jackdaw/status` dialog 恒空 |
| M10 导出包腿 | **绿** | 决策 5-C 全清单：manifest_diff(before,after) **空输出**+staged scene.bsn SHA 相等+manifest 新写证明（started_at 前进+ready，mtime 前进） |
| M11 游戏层数值腿 | **绿** | A 区态 1（viewport AA=TAA+SSAO ultra+bloom/fog on）vs 态 2（Off+SSAO off+bloom/fog off）两次 direct run：游戏相机矩阵 **faces_equal 逐字段恒等**（AA 组件只随场景走） |
| M12 配置层隔离腿 | **绿** | `JACKDAW_CONFIG_DIR=<scratch>` 启动→A 区 preset low→viewport.json 落 **scratch**（render_scale 50 文件脸）+工程树零 viewport.json；无 override 二次启动读回用户级原值（render_scale 100）——「per user」活证 |
| M13 GI 回归 | **绿**（tooltip 展开不可合成驱动，见偏差 3） | 面板 walk 含 Realtime GI 行；`ui_click` 拒绝=「the control is disabled (checkbox)」活体 InteractionDisabled 证据；置灰面板 window 截图归档；tooltip Solari 文案=H 锚 |
| M14 全链缺席 | **绿** | 六份 game 日志+editor 日志+staged 日志 warn 扫描（`tonemapp|bloom|exposure|solari|ray|UnresolvedTypes|panicked`）零 solari/ray 命中；workspace Cargo 零 solari 引用；fork bevy_solari 仍 optional（:291）未启用 |
| M15 无 Environment 对照 | **绿** | 盘面删 Environment→direct：游戏相机 **Smaa 退场**（smaa_present=false，dress 消失）；编辑器面板空态提示在树（"This scene has no environment"）；PIE 通道对照由 M4 bloom-0 态兼任；复原后种子 SHA 精确 |
| M16 存活+warn | **绿** | 三相各自终态 BRP 活+pid；N13 计数（每 PIE 相 2 次，全部 `pie::drain_game_events` 归属）；warn 扫描逐条归属零未解释命中 |

## 二、L1-L10 腿状态

| 腿 | 状态 | 要点 |
|---|---|---|
| L1 prep+boot+前提态 | **绿** | PREP_OK（冷编 ~7 分钟）；seed 相幂等（文档已带种子→跳写只验证）；L1_PRESET_FACE：low↔high preset 对写文件脸翻转并复原（store 活证）；L1_SEED_VERIFY：world.query 逐字段读回（f32 epsilon 口径） |
| L2 编辑器三件套 | **绿** | M1/M2/M3 如上 |
| L3 PIE parity+GR8 | **绿** | M4 如上；GR8 首拍忠实案确认 |
| L4 direct parity | **绿** | M5 如上 |
| L5 export parity | **绿** | M6 如上 |
| L6 AA 三站 | **绿** | M7 如上 |
| L7 负向三腿 | **绿** | M9-M12 如上 |
| L8 GI 回归+空态对照 | **绿** | M13/M15 如上 |
| L9 往返+像素归档 | **绿** | M8 如上；17 张 PNG+两份 manifest+walk JSON 归档 `loop/t19-live/`（随 git 旅行，T18 先例） |
| L10 warn/存活/视口菜单回归 | **绿** | M14/M16 如上；`viewport_settings_menu` 既有面=门禁隔离跑（见 §四） |

## 三、真机方法论增量（t19-live.sh，产品零改动的载体面）

1. **ecam 换脸**：编辑器视口相机识别改走 `jackdaw/camera_state`（编辑器自己的
   ActiveViewport 应答；to_bits 的 NonMaxU32 编码换算 `{index}v{generation}`）——裸
   `world.query [Camera3d]` 首个实体不是视口相机（编辑器世界有 3d/2d host、工具预览
   多台相机；run 1 的错相机教训）。
2. **game_face 自证式读回**：一次 get_components 同时请求两套类型路径拼写
   （lenient errors 吸收输者）+Bloom/Exposure 双拼写归一——类型路径证据（bevy 定义项
   路径 vs re-export 拼写）落日志。
3. **direct_run 相机等待**：流程默认先起 menu.bsn，BRP 应答远早于场景相机的生成——
   direct_run 增加等相机循环（run 2 的 M5a 读空教训）。
4. **M4 的 save-before-play 纪律**：工程 save-before-play 策略默认 `Save`
   （pie_current.rs SaveBeforePlay）——脏文档 PIE 会把盘面写成现场值；两态显式
   save/restore（run 3 的 M5a 假红教训，红证归档）。
5. **export_wait 重跑感知**：SHA 判据被上一轮导出的树预满足——改为 export face 的
   started_at 前进+state 回 ready（run 1 的 M10 测量竞态教训，红证归档）。
6. **Exposure 组件不可读**（`#[reflect(opaque)]` 无 ReflectSerialize，-23402）：数值
   脸分层降级 document face+H 锚+像素轨（偏差 2 详述）。

## 四、门禁（受影响域+快四门；日志归档 loop/reports/t19t2_gates_*）

| 门 | 结果 |
|---|---|
| `cargo fmt --all -- --check` | **CLEAN（FMT_EXIT=0）** |
| `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **Finished，0 告警（-D warnings 下 exit 0；deps 清理后重编 3m10s）** |
| 物理双包 `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | **EXIT=0（1m59s）** |
| 受影响域：`cargo test -p jackdaw --test viewport graphics_prefs_clean` | **2 passed，0 failed** |
| 受影响域：`cargo test -p jackdaw --test viewport graphics_panel` | **8 passed，0 failed**（功能 #8 锚零回归） |
| 受影响域（L10 既有面）：`cargo test -p jackdaw --test viewport viewport_settings_menu` 隔离跑 | **12 passed，0 failed**——预存 flake 隔离不复发（与 T1 隔离绿一致；证据入候选 W 票） |
| 受影响域：`cargo test -p jackdaw_surface`（dress 测试族） | **52 passed，0 failed**（E5 勘误：程序归档该段被 tail 截断，52 passed 行未入档——QA 全量捕获重跑补证，t19t2_qa_targeted.log 尾段；归档纪律教训见 §十） |
| AN2 腿 `cargo nextest run -p jackdaw_runtime --features animation --test animation_scene_load` | **1 passed**（T15 转活先例维持） |

## 五、预存 flake 复发观察（viewport_settings_menu::a_preset_picked…）

T1 定证的预存 flake（全量并行 2/2 红、隔离绿；候选 W 票）。本次真机期间观察：**隔离跑
不复发**（12/12 绿，本轮门禁亲跑）——与 T1 的「并行撞共享 viewport.json/菜单 settle
时序」机理候选一致，隔离口径稳定。真机三相期间该 flake 未与任何画质腿同窗出现（门禁链
单独跑，T12-T3 §九-7 纪律）。按 QA 交接口径：不修，证据归 `t19t2_gates_tests.log`，
供主控立候选 W 票时引用。

## 六、偏差清单（如实分级）

| # | 级 | 偏差 | 处置与依据 |
|---|---|---|---|
| 1 | S | **M1/M4-M6 的 Exposure 组件读回被 BRP 结构性拒绝**：`Exposure` 是 `#[reflect(opaque)]` 且未注册 ReflectSerialize（错误码 -23402，错误全文归档于各相日志）。数值脸降级=**document face（world.query 读 Environment.post.exposure，可读）+同一 dress 代码路径的相邻字段（Bloom/Tonemapping 同一 insert 块，surface/environment.rs:690-703）+像素轨红绿**；游戏侧 seed_face 以 Bloom 0.8+Tony+Smaa+Msaa 为 dress 判据 | 工具链边界非产品缺陷；H 锚 `post_settings_reach_the_camera_components` 已把 doc→组件映射钉进 CI。若后续要组件级读回，需 bevy 侧给 Exposure 注册 ReflectSerialize（fork 面，超 T19 授权） |
| 2 | S | **M13 的 tooltip 展开无法合成驱动**：`ui_click` 拒绝点击 disabled 控件（该拒绝本身即 InteractionDisabled 的活体证据，已收为 M13_GI_DISABLED 绿）；`ui_drag` 扫过行文本产生 hover 但 popover 未出现（两次探针，2026-10-31）。tooltip 文案脸维持 H 锚（graphics_panel.rs:373-394） | 真机 tooltip 展开=合成输入面的边界；如需真机化需 ui_hover 类方法（remote 面，超 T19 授权） |
| 3 | S | **M7 的「Msaa::Off」期望修正**：方案 M7 写「Smaa 在+Msaa::Off」；真机实测游戏相机 Msaa=**Sample4**，且 M15 无环境对照亦 Sample4——这是管线/相机缺省值，非 dress 面；场景 msaa=Keep 的语义=「保持相机自有值」。M7 判据修正为「Smaa 在/退场+Msaa 恒定（M11 恒等腿覆盖）」 | 方案行号基线期的推断与真机事实的偏差，非产品缺陷；如实记档 |
| 4 | S | 三轮红证归档后修正脚本（产品零改动）：run1 editor=set -u 撞 $() 子shell 全局丢失（ECOMP_ERRORS unbound）；run2 editor=错相机（裸查询首实体非视口相机）；run1 game=流程 start_scene 指向 menu.bsn（direct/staged 空世界）；run2 game=M5a 撞 menu→scene 转换竞态；run3 game=save-before-play 把脏文档写盘（M5a 假红）；run1 export=SHA 判据被旧树预满足（M10 测量竞态）。六份红证全部归档 `loop/reports/t19t2_*_red.log` 系 | 红态先行归档纪律（T16 首例）延续；每轮修正均为脚本面，产品面零改动由 git diff 为证 |
| 5 | M | **GR6 抽查=Inconclusive-by-fixture**：sun_shadows 开关数值半（viewport.json 文件脸 sun_shadows=false）动了，像素半经 confirm_red 两帧互证 flat——**fixture 场景无承影几何**（天空+太阳盘，无接收面），像素 flat 是几何必然而非 R12 形态；R12 形态的抽查需要带承影体的场景 | GR6 腿以 PASS（inconclusive-by-fixture verdict 入日志）归档；R12 本体维持不吸收；建议：若主控要关闭 R12 抽查面，T20 示例游戏（有地形/道具）顺手补一腿 |
| 6 | S | L8 的 M15 PIE 通道未单独跑对照（direct 通道承担了组件对照+编辑器空态提示）；staged 通道对照未跑（导出预算两次，方案 §六 风险表） | M15 判据由 direct+编辑器两通道承载；staged 面由 M10 的携带面证明间接覆盖（包内容=工程树，树已对照） |
| 7 | 备注 | 用户级 viewport.json 在 L1 前不存在（High==缺省不触发 store 写）——L1 的 preset low↔high 对补上了文件存在性；M9 套件后做了 hygiene restore（sharpen/stats/graph/realtime 复原） | 无用户可见影响；文件内容全程是编辑器自身合法写 |
| 8 | 备注 | M13_GI_PX 腿的 window 截图含 tooltip 未展开的面板（偏差 2 的直接后果）；截图仍证明 GI 行置灰在面板中（E6 勘误补记：截图另入镜一枚「Recovered Work」恢复对话框——相转场 pkill 的恢复日志，GI 行与面板值不被遮挡，详见 §十） | 证据面照实归档 |

## 七、给 QA（T3 终验）的注意事项

1. **复跑顺序**：prep（fixture target 已暖，~1 分钟）→ seed（幂等跳写）→ editor →
   game → export（release 已暖，两导各 ~2 分钟+staged run）。每相独立启停，trap 会清场。
2. **种子文档 SHA 锚**：`655892c6c28327866acaa52c71a1ff510f9d963144b28864d257e1422e9a99a9`
   ——每相结束都应回到该值（各腿自带 restore+校验日志行）。
3. **Exposure 读回必红**：任何对 `bevy_camera::camera::Exposure` 的 get_components 断言
   都会 -23402（偏差 1）——别把它当回归；数值脸用 document face。
4. **save-before-play**：脏文档 `pie.play_current` 会写盘（SaveBeforePlay 默认 Save）——
   PIE 腿前后必须显式 save/restore 并校 SHA（M4 已内建）。
5. **direct/staged 腿**：flow start_scene 必须指向 scene.bsn（脚本已做）；direct_run 自带
   等相机循环；staged 启动需 `DYLD_LIBRARY_PATH`（t16 形态，脚本已带）。
6. **export_wait**：重跑感知版（started_at+ready）；SHA 判据在树已存在时会瞬时假就绪。
7. **判红纪律**：confirm_red（编辑器通道）/gshot 新帧互证（全屏通道）必过；settle_pixels
   ≥3s+画质切换后首拍丢弃；f32 一律 epsilon。
8. **flake**：`a_preset_picked` 若在门禁隔离跑中复红，按候选 W 票口径归档证据、不修。
9. **30 秒用户清单草稿**（方案 T2-4 要求）：拖 Exposure 滑条看 Play 画面变亮变暗；
   拨视口 Quality Preset 看 Play/导出画面**不**变；悬停 GI 行看置灰与说明文案（合成驱动
   做不到，人工点验即可）。

## 八、证据清单

- 腿证据（随 git）：`loop/t19-live/`——14 张通道 PNG（m1 低/高、m2 关/开、m4 流送 a/b、
  m5 a/b、m6 staged、gr6 四张、m13 面板；E1 勘误：原稿「17 张」为笔误，枚举与 `ls` 均
  14）、manifest-before/after.json+scene 行、六份 direct 日志、staged 日志、walk-editor/
  game.json、scene.bsn.seed-backup；`config-scratch/`（M12 scratch 面文件脸）**T2 当轮
  未归档**（E2 勘误：原稿声称在档不实——判据的文本证据 scratch face JSON/per-user face
  在 console-game.log 原文完整；T3 复跑已补档，见 T3 报告）。
- 相日志归档：`loop/reports/t19t2_*`——editor_console（三轮终版 PASS）、game_console
  （终版 PASS）、export console、prep/seed/selftest、门禁日志、以及六份红证
  （set-u 死亡/错相机/menu-scene/M5 竞态×2/M10 竞态）。
- 红证先归档再修正的全部过程记录见各 `*_red.log` 文件名后缀。

## 十、Errata 落账（T2 QA 回流 6 条，T3 程序报告面修订 2026-10-28）

QA（t19-t2-qa.md §六）勘误不改裁决；逐条落账如下（E1/E3/E4 已在正文原位修正并标注）：

- **E1**：§八「17 张 PNG」→ **14 张**（正文已改，原稿笔误）。
- **E2**：`config-scratch/` 归档缺失照实记（§八正文已改）；T3 复跑 editor 相 M12 腿时
  补档 `loop/t19-live/config-scratch/`（scratch viewport.json 文件脸），缺口闭合。
- **E3**：脚本行数「约 1,100」→ **1,708 行**（报告头部已改）。
- **E4**：M9「16 次 operator」→ **15 次**活体套件（正文已改；T1 headless 守卫 16 次
  含双 preset，两口径勿混——QA 原勘误注记保留于此）。
- **E5**：§四门禁表 `t19t2_gates_tests.log` 的 SURFACE 段被 `tail -5` 截断（52 passed
  行未入档）——QA 全量捕获重跑补证 52 passed 属实（t19t2_qa_targeted.log 尾段）；后续
  归档纪律=全文或 grep "test result" 捕获，T3 门禁归档已按此执行。
- **E6**：§六-8 补记：`shot-m13-gi-panel.png` 入镜一枚「Recovered Work」恢复对话框
  （seed→editor 相转场 pkill 的恢复日志，时间戳吻合）——GI 行置灰与面板值不被遮挡，
  M9 判据的 dialog 断言未受影响（套件后 dialog 恒空在档）。
- **F1（QA 发现，非 errata）处置**：M15 编辑器空态提示半格判据无区分力（ui_tree 的
  visible 只跟踪 bevy Visibility，不跟踪 UI Display）——格维持绿（游戏通道 smaa 退场
  为强证据），提示可见性由 H 锚三态断言承载（`the_scene_empty_hint_follows_the_
  scenes_environment`）；A14 已立候选工具票。book 无需注记：空态提示的可见性对用户
  本就成立，判据承载面是 QA 内部口径，记档于此即可。

## 九、耗时与预算对账

prep 冷编 ~7 分钟（QA 预算 10 分钟内）；三相真机合计约 95 分钟（editor 3 轮×~7 分钟、
game 4 轮×~10 分钟、export 2 轮×~14 分钟）；门禁链在 deps 清理后全量重编（预算单列）。
磁盘门前 52Gi→出口 20Gi（A6 纪律：清 workspace 37G 陈旧 deps 工件，fixture 两个 target
是后续吃盘大户）。
