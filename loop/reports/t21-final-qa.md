# T21 终验 QA 报告：任务 3（收官段）+ T21 整体终验（只验不修）

> 验收对象：分支 `loop/t21-sprite` @ **765c363d**（基线 main=bb4b75b9=T2 合入点；程序提交
> =T21-T3 收官，T1/T2 已分别合入；T1 QA PASS（t21-t1-qa.md）、T2 QA PASS（t21-t2-qa.md，
> 附 6 条 errata+F4——本轮逐条核落账兑现，见 §三-4）。程序报告：
> `loop/reports/t21-t3-report.md`。T3 diff 亲核（`git show --stat` 全件）：**产品面=book
> 五文件（sprites-2d.md 新章 217 行+SUMMARY 一行+四文件出链）+loop/qa/t21-live.sh 脚本
> 修复（199 行差）+t21-t2-report.md errata 落账（28 行差）+T3 报告与归档**——`src/`、
> `crates/`、`templates/` 零改动（`git diff bb4b75b9..765c363d -- src/ crates/ templates/`
> 为空亲证）；T1/T2 QA 报告本体零触碰（bb4b75b9..765c363d 触及两文件 0 commit 亲证）；
> 工作树除 QA 归档外零触碰（`git status` 全量亲录）。
> QA 手段：**Mac 全量门亲跑**（后台链+轮询，全程未设 RUST_BACKTRACE，门链独窗不与真机
> 同窗，门前 df 95Gi——QA 预清已闭环 T19/T20 fixture 构建缓存 48Gi，T19-T1 偏差 3 先例）
> +**关键格 console 原文全读**（editor r2/r3+atlas+game+prep+direct-m13 六相 console 全文
> +判定文件三件亲读）+**像素亲验**（归档截图以 sips+BMP 解码自行比对：atlas index 三拍
> 全图 diff 只差 Inspector 文本区、sprite 区域裁剪 md5 复现 `0c15a625…×3`、M13 游戏窗口
> 与 M2/M7 编辑器窗口**亲读目视**确认六 tile 全图渲染+A17 现状）+book 新章十节逐节对锚
> 源码+SUMMARY 挂目+出链四处双向亲读+UI 名现场核对+clippy 双包/doctests 采信归档抽核
> （0 warning 行+bind dyld 第 14 次目击签名+单包复跑 1/1）。
> QA 归档 `loop/reports/t21t3_qa_*` 十一件（fmt/libtests/fast/audio_gate/save_store/
> integration/docs/scaffold_e2e 八门+A6 隔离复跑+animation 分包+gates 脚本/台账+atlas
> 裁剪三件）。

## 〇、结论

**PASS（T21-T3 收官 + T21 整体，含 roadmap T21 可勾选建议）**——全量门 QA 独立复现：
libtests **3029/3029**（58 条 result 行逐行求和亲算）、**teaches 92**（`running 92 tests`
在 :2709 亲点）、fast **3029/3029**、audio_gate **7/7**、save_store **19/19**、fmt 零 Diff、
docs **EXIT=0**（13 条实体警告=12「public documentation for」+1「unresolved link to」，与
T17/T19/T20 基线同数同族；grep 行计 17=实体 13+包级汇总 4，T19 终验已记的两种计数法）、
scaffold_e2e **1/1**（153.0s）。integration QA 轮 **5574/5575**：唯一红=**A6 票本体**
`prefab_lifecycle::prefab_file_change_triggers_reload`（TRY 1-3 全红，panic 签名
`prefab_lifecycle.rs:714 watcher reloaded prefab; v2 should be in world. Got ["v1"]` 与
buglist A6 刻画逐字同文；QA 隔离复跑 **1/1 绿**（1.9s，t21t3_qa_a6_isolated.log））——
**0 新增红口径维持**（程序轮同树 5575/5575 TRY3 过+animation 1/1 在档；QA 轮 animation
分包补跑 **1/1 绿**）。关键格复核：拾取+描边窗口级三轮（r2/r3 归档，1.27% 像素差两轮
在文，QA 亲读目视描边+gizmo 形态）、SP3 三态（可编辑 NEW/GRID/REDO/REOPEN 绿+UNDO 本
会话红如实+可保存 M9 三件三轮绿+可运行 game 相 4/4）、set_verified 跨实体写落证据
（r3 console :43-49 原文在档）、ATLAS_INDEX_PX 严格判据离线判定=裁剪逐字节同（QA 以
脚本同参裁剪独立复现）——零虚报。book 新章十节事实面**九节半对得上锚源码与归档证据**
（唯一残句见偏差 1）；SUMMARY 挂目、出链四处、UI 名全部现场核对通过。**Errata E1-E6+F4
全部落账亲核**。验收句「图片或 Sheet→可编辑可保存可运行的 2D 对象」三态逐词证据在案
（§五）。**A17 机制精化采纳**（§六）：「loader 缺面」单因读法被新证据闭合，「双柄空间」
成立为机制注记（最佳解释），票面更新归主控。**偏差 0 🔴 + 1 🟡 + 7 ⚪（§七）**——🟡 为
book 一处书面残句（§九旧表述与 §七 A17 现状注记自相矛盾），一行勘误随合入落笔，不动摇
任何验收词。

## 一、Mac 全量门亲跑（权威口径，最终树 765c363d；门链独窗，未设 RUST_BACKTRACE）

门前 df 95Gi（QA 预清 T19/T20 fixture 构建缓存——两任务已闭环 main，构建缓存按 T19-T1
偏差 3 先例清理；活跃 fixture t21-sprite 未触碰）；integration 后 94Gi；门后 93Gi。

| # | 门 | 命令 | QA 亲跑结果 | 归档 |
|---|---|---|---|---|
| 1 | 格式 | `cargo fmt --all -- --check` | **EXIT=0**（0 字节=零 Diff） | t21t3_qa_fmt.log |
| 2 | 单测 | `cargo test --workspace --lib` | **EXIT=0；3029 passed / 0 failed**（result 行逐行求和亲算）；**scaffold 包 `running 92 tests` 亲点**（:2709）——teaches 92 与 T3 报告一致 | t21t3_qa_libtests.log |
| 3 | fast | `cargo xtask fast` | **EXIT=0；Summary 3029 tests run: 3029 passed, 0 skipped（39.6s）** | t21t3_qa_fast.log |
| 4 | audio_gate | `cargo nextest run --profile ci --test audio_gate` | **7/7 PASS**（4.7s） | t21t3_qa_audio_gate.log |
| 5 | save_store | `cargo nextest run --profile ci -p jackdaw_runtime --test save_store` | **19/19 PASS**（0.1s） | t21t3_qa_save_store.log |
| 6 | **integration** | `cargo xtask integration` | **EXIT=1；Summary 5575 tests run: 5574 passed (1 slow), 1 failed**——唯一红=**A6 票本体** `prefab_lifecycle::prefab_file_change_triggers_reload`（TRY 1-3 全红，:714 签名与 buglist 逐字同文）；**QA 隔离复跑 1/1 绿**（1.9s）；全文零 dyld 行。程序轮同树 5575/5575（TRY3 过）在档两相对照——**A6「满载红/隔离绿」模式第四次同族目击，0 新增红维持**。animation 分包 QA 补跑 **1/1**（0.09s，EXIT=0——QA 轮主段红后 xtask 中止未达分包段，按程序轮命令行补跑） | t21t3_qa_integration.log + t21t3_qa_a6_isolated.log + t21t3_qa_animation_split.log |
| 7 | docs | `cargo doc --workspace --no-deps` | **EXIT=0**；13 条实体警告（12 private-doc-link+1 unresolved link）与程序归档逐行同面=T17/T19/T20 基线同数同族（预存树态，本轮零 src/ 改动） | t21t3_qa_docs.log |
| 8 | scaffold_e2e | `cargo nextest run --profile ci -E 'binary(scaffold_e2e)'` | **1/1 PASS**（153.0s 含冷编）EXIT=0 | t21t3_qa_scaffold_e2e.log |

**clippy 全仓/物理双包/doctests（采信归档抽核，T18/T19 先例口径）**：
`t21t3_gates_clippy_ws.log` warning/error 行计数 **0**（grep 亲算）+`Finished` 在文；
`t21t3_gates_clippy_phys.log` 两包 `Checking jackdaw_physics`+`Checking
jackdaw_avian_integration` 在文+零 warning 行；`t21t3_gates_doctests_full-run_red.log`
bind-dyld 家族第 14 次目击（`Library not loaded: @rpath/libstd-614bb9b33bbc23af.dylib`
同签名）+`t21t3_gates_doctests_bind_retry.log` 单包复跑 **1 passed（EXIT=0）**——采信。
程序 exit 台账（t21t3_gates_exit.txt）亲读：九门 rc 与报告 §四表逐项一致（doctests
EXIT=101 如实记红态）；df 台账 51Gi→47Gi。

**QA 归档交叉复核**：程序轮 fast Summary 3029/3029、integration Summary 5575/5575
`(1 slow, 1 flaky)`、判定文件三件（editor_r3/atlas/game_final）与报告 §三表逐行一致、
selftest 4/4（console-selftest.log）——无隐瞒。

## 二、关键格复核（派单抽 4 判定原文全读+像素亲验；三轮判定逐行核对）

**抽读四格=任务书建议格，全部 console 原文亲读+归档像素亲验：**

1. **六 PR 拾取+描边（M2）三轮+window 级像素差 1.27%**：r2/r3 console 原文在档——
   `M2_PICK_PASS`（world click→selection=[Hero]）+`M2 outline window half: pixels:
   5739552; changed: 72962 (1.27%)`（r2）/`72916 (1.27%)`（r3，canvas 半 702218px 通道
   0.00%=viewport2d 陈旧帧通道，恰证 A2 口径「window 级才新鲜」）+`M2_CLEAR_PASS`。
   **QA 亲读 `shot-m2-selected-window.png`**：Hero 在 Outliner 高亮+画布红 sprite 蓝描边
   +移动 gizmo（蓝 stem+顶部旋钮+白色中心枢轴——与 E3 勘误后的 ACCENT_BLUE 形态描述
   逐字吻合，无「红绿双轴」）+状态栏「Entity: Hero」；选中/未选对 md5 相异亲算。
   **边界如实记**：r1 console 为 0 字节（§七-1），「三轮全绿」的归档载体=r2/r3 两轮。
2. **SP3 图集三态**：可编辑=atlas console 原文 `ATLAS_NEW/GRID/REDO/REOPEN_PASS`+
   `ATLAS_UNDO_FAIL`（"6 rows after undo+save"——本会话红如实记；T2 绿在档
   `console-atlas_t2.log` 的 `ATLAS_UNDO_PASS` 亲读对照，升降如实）+`ATLAS_WEAR_FAIL`
   （-23402 结构限制尾文全文在档=Sprite 组件 BRP 拒读/拒写门现场，D9 口径）；
   可保存=editor r3 `M9_BSN_TYPES/M9_REOPEN/M9_KIND_REOPENED_PASS`×2 轮（r2/r3）+
   盘面亲验（fixture scene.bsn:24-26 `texture_atlas: Some(…TextureAtlas { layout:
   "content/sheet.bsn", index: 2 })` 亲读+卡 6 URect 亲数）；可运行=game console
   `GAME done: 4/4`（M13_NUMERIC Transform 读回==授权值+SheetSpr presence+M13_CAM2D+
   WINDOW_PX hero-red 0.033%+M13_ATLAS 文档 wear+walk「Loaded 1 asset files」亲读
   direct-m13.log:9）。
3. **M12+AU6 拒写门（派单格名系 T16/T20 词表迁移，T21 对应面核）**：T21 的写门证据=
   ①-23402 结构拒读门（atlas console :10-13 `register_type_data` 尾文全文）；②
   **set_verified 跨实体写落直接证据**（r3 console :43-49 原文：TopSpr 面
   `translation:[-150,-40,3.0]` 收到了写给 Hero 的 z=3，Hero 本面 `[0,0,0]` 不动——
   D13 实体重生/柄漂移家族的机制性新证据，工具票弹药在档）。T16-AU6（坏音频解码
   panic）与 T21 零耦合；lane retry/NOT-SAMPLED best-effort 为 t20-live.sh 音频腿词表，
   **t21-live.sh 全文零命中**（grep 亲证）——T21 的同族「设计内口径」=read_ready/
   camera_ready/set_verified 三门+WARN_PATTERN 增补（fail-set 与捕获集分离）+TCC 弹窗
   前置，全部按设计行使且判定如实（非设计内红为零）。
4. **game 相 4/4**：console-game.log 全文亲读（判定行与 §〇 引用一致）+**QA 亲读
   `shot-M13_ATLAS-window.png` 目视**：游戏窗口内 wear 的 SheetSpr 渲染**完整 2×3 六
   tile（red/green、blue/yellow、magenta/cyan 逐色可辨）**，模板 HUD「100 / 100
   Pickups: 0」+3D 家具噪音同帧在画（决策 6-A 如实注记的实况）——**A17 run 侧全图渲染
   由 QA 目视独立定案**（文档 index:2 只应画蓝 tile）；6.363% 蓝普查=tol 50 宽存在性
   判据（壁纸+UI 同族色平凡满足），报告降级「参考值」处理正确。hero-red 0.033% 与
   QA 自算（tol 30 步进 2）同量级。

**A17 编辑器侧同形亲验**：`shot-m7-blue-top.png` 目视=SheetSpr 在 2D 画布同样渲染全
2×3 sheet；TopSpr（蓝）叠 Dropped（红）左侧露红条=z 几何旁证与 T2 QA 同形；FPS 1.01
（软渲染会话实况）；M2 对内 SheetSpr 亦全图（第二独立帧）。**两侧全图=可复现现状，
T3 报告 §三-4 的新发现成立。**

**warn/N13 归属**：五份 T3 console 的 WARN_SCAN 判定行逐一亲读=editor r2/r3+atlas+
game 全零命中（词表含 A6 增补 loader 行）；全部 console `panicked` 零行=N13=0 如实
（本轮未跑 PIE 相，probe 腿属 T2 已定案范围）。

## 三、book sprites-2d.md 十节核对（逐节对锚源码+SUMMARY+出链+UI 名+Errata）

新章 217 行、十节。逐节事实面核（判✅=QA 亲读锚点吻合）：

| 节 | 书内断言（抽样） | 锚源码/证据 | 判 |
|---|---|---|---|
| 导语 | 1 world unit = 1 texture pixel；UI 场景另kind指路 game-ui | 方案事实九（`sprite_size` 取像素尺寸）+game-ui.md 存在 | ✅ |
| A 2D scene | `scene.new kind=2d`；launcher「2D game」=Camera2d+一 sprite；模板 3D 家具诚实注记 | `src/scenes/operators.rs` kind 臂+`src/launcher/mod.rs:232,241`（"2D game"/"Camera2d and a sprite" 亲读）+决策 6-A | ✅ |
| Making a sprite | 三入口同归 sprite.add；占位 32×32；新 sprite z=最高+1；结果组件 Name/Sprite/Anchor/Transform/Visibility；SP10 3D 组注记 | `src/sprite_ops.rs:31`（PLACEHOLDER_SIZE=32.0）+:41-43（z 文档）+params path/x/y(+parent/name)+`src/creation_taxonomy.rs:247-249`（two_d 按 OpenScene2dRoot 出现） | ✅ |
| Select/move/rotate/scale | 蓝描边+gizmo；move 全选/rotate-scale 主 sprite/绕 Anchor；吸附次序=邻 sprite 边/心或参考线→网格→整像素；Ctrl 反转；`space=world` y up | `src/sprite_snap.rs:6-7`（"another sprite's edge, centre or a guide … then the grid, then the pixel" 逐字）+`src/canvas_snap.rs:114-115`（"Use Snap"/"Use Pixel Snap"）+:149（Ctrl 反转）+`src/test_input.rs:632`；gizmo 形态 QA 亲读目视 | ✅ |
| Inspector | 字段表 image/color/flip/custom_size/rect/texture_atlas/image_mode 四态/alpha_mode 三态；Pivot 3×3 九格+裸 offset 同字段同 undo | fork `sprite.rs`（image_mode Auto/Scale/Sliced/Tiled :205-212+alpha_mode Opaque/Mask/Blend :180-182 亲读）+`src/inspector/anchor_presets.rs`（ANCHOR_PRESETS[8]=Bottom Right；T2 QA §六-1 同 undo 通道亲读链） | ✅ |
| Sizes and pixels | 无 PPU；PPU100 的 64px↔custom_size 0.64 或 **scale 0.01**；过滤 per-asset 不持久=SP4 注记 | 方案事实九/十；**书内 scale 0.01 正确**（方案 §五-决策 2 与 T2 报告 §四 的「scale 0.64」系笔误，书修正是对的方向——64×0.64=40.96≠0.64） | ✅ |
| Sprite atlases | New Asset→Sprite Atlas 卡；`sprite.atlas.grid tile_size columns rows [padding] [offset]`；帧序左→右上→下、整刀一条 undo；卡内 URect 手编=非网格；layout picker 列工程图集；**A17 现状注记（两侧均全图+loader ERROR 条件句）** | `src/sprite_atlas.rs`（T1 QA §四-3 亲读）+fork `from_grid` 帧序单测（T1 钉死）+`definition_assets.rs` kind 注册+asset_row 经 kinds.by_type_path（T1 QA §四-2）；A17 句与 T3 新证据一致（QA 双侧目视独立复证） | ✅ |
| Draw order | 小 z 先画；新 sprite=top+1；排序面板/Y-sort 记 open work | 方案事实八（fork `bevy_sprite_render` sort key）+`book/src/developer-guide/open-challenges.md:300-308` 亲读 | ✅ |
| Playing and shipping | embedded 忠实/windowed 流=3D 相机无 2D pass→游戏窗口 truth；导出携带整树；**A16 一句话**（State\<GameFlow\> 不可 BRP 读、修复=模板一行）；**A11 一句话**（活世界持旧柄至重开） | T2 probe 7/7（embedded 0.187%/windowed 0.000%，QA 亲测复现）+buglist A16/A11 票面逐句对照；**但 §九尾句「a staged build draws indexed tiles like a direct run」与本节前半及 §七 A17 注记自相矛盾——见偏差 1 🟡** | ⚠️ 一处 |
| The 30-second check | 五条，第 4 条带 A17 现状句（「两侧都画全图——记录缺陷；切分/指认/index 的保存与重载逐字无损」） | 与 T3 报告 §七一致；与归档证据同形 | ✅ |

- **SUMMARY 挂目**：`book/src/SUMMARY.md:28` `- [Sprites in 2D](user-guide/sprites-2d.md)`
  恰在 Game UI(:27) 与 Audio(:29) 之间 ✅（方案口径「game-ui 附近」兑现）。
- **出链四处双向亲读**：assets.md:32-33（2D 拖放例外句→新章）、game-ui.md:43-48
  （两画布对照段→新章）、remote-control.md:223-226（`space: "world"` 段→新章——
  BRP JSON 拼写，与新章 operator 拼写 `space=world` 各安其位）、keyboard-shortcuts.md:36
  （Arrows 行「in a 2D scene, moves the selected sprite」）✅；新章入链八目标
  （game-ui/scene-management/viewport-navigation/assets/play-in-editor/game-flow/
  asset-references/remote-control）文件全部存在 ✅；T1 §五校对点清单五项全兑现。
- **UI 名现场核对**：「File > New Scene」=`src/lib.rs:4338` 菜单项原文；「New Asset
  (Project window)」=assets.md:23 既有命名；「Use Snap」「Use Pixel Snap」=
  canvas_snap.rs:114-115 原文；「Embedded/Windowed」=play-in-editor.md:301-307 既有名
  （防杜撰 ✅）；「Missing References」「Rebind」=asset-references.md:50-59 原词；
  「2D game」=launcher/mod.rs:232 原文。**零杜撰。**
- **Errata 落账确认（任务指定）**：t21-t2-report.md 六条全在位亲读——E1（§二导语+M3 行
  「会话在证、归档缺失」降级+死因 `$drop_sprite` unbound）、E2（§二 z 行：归档对字节
  相同+viewport2d 陈旧帧，z 语义维持+补跑口径）、E3（§二 #650 行按所见措辞降级）、
  E4（§三 wear 行：全图+loader ERROR，SP11/A17）、E5（§三 direct/export 行：普查壁纸
  主导、像素半无效）、E6（§三 index 行：三拍字节同=假阳性记无效）；F4（§六 D2 行措辞
  降级）；§八 Errata 落账注记节在位、原文数字不灭失。T2 QA 报告本体零触碰（git 亲证）。
  **落账注记与正文标注逐条对得上，兑现 T2 QA §八-6 回流。**

## 四、QA 放行清单对照（任务书终验口径）

| 条目 | 终态 |
|---|---|
| **T1 验收（六 PR 移植全绿+两探针定案+quick 门绿）** | ✅ QA PASS（t21-t1-qa.md：六对 patch-id EQUAL=「零文本冲突」最强形态+上游测试族亲跑 31/31+13/13+七门亲跑；SP7 探针按 D2 裁定移交 T2 首步兑现） |
| **T2 验收（图集链 headless 绿+SP9 单测+fork 变更在案+记档文本）** | ✅ QA PASS（t21-t2-qa.md：M10 10/10+SP9 3/3+fork f83d83b41=HEAD 亲验（本轮复核 fork 仍在该提交）+SP4/SP5/SP8/SP10 记档文本本轮 book/open-challenges 全部落位）——6 errata+F4 本轮终验全部落账兑现（§三） |
| **T3 验收（关键格终态复跑+book 新章+全量门+errata 落账）** | ✅ 本轮（§一/§二/§三：关键格原文全读+像素亲验+十节核对+E 落账核+八门亲跑+A6 口径闭合）——16 格正式判定按能力维度分布于 T2 报告 §二/§三+T3 报告 §三，本轮三态汇总见 §五 |
| **SP1 🔴 2D 授权通路零** | **吸收闭合（建设主体兑现）**：三入口同归 `sprite.add`（#657 落地）；M1_OPERATOR 绿归档+M1_IMAGE presence 绿×2+拖放=同 operator 代码面；M1_MENU=D6 驱动缝记档（常驻口径，不升级产品缺陷） |
| **SP2 🔴 画布交互零** | **吸收闭合**：拾取/描边/gizmo（#650/#653/#654）M2 三轮绿（归档 r2/r3+窗口对）+M3B_ROTATE 绿+方向键/undo 链=T2 交互钉死+H 侧 sprite_gizmo 31/31（563 全量内）承载；移动链真机面本会话通道受限（D1/D2 如实记，读窗死+截图证 Hero 未动）——按 T2 QA §四-2 常驻口径维持 |
| **SP3 🟡 图集切分零授权面** | **吸收闭合（T1+T2）**：fork 一行（f83d83b41）+kind 注册+`sprite.atlas.grid`+walk 装载（M10 10/10）；本轮三态复跑 §二-2 |
| **SP4 ⚪ 过滤** | **记档兑现**：book §六过滤注记（per-asset 不持久+正道=全局默认/代码侧）逐句对锚（事实十） |
| **SP5 🟡 PPU 概念不存在** | **定性闭合**：book §六 PPU 对照表（零代码，决策 2-A；书内 scale 0.01 修正了方案/报告的 0.64 笔误） |
| **SP6 🟡 2D 画布逻辑像素 bug** | **随 #650 闭合**：`world_to_target_pixel`（viewport_2d.rs:188）+`target_pixels_per_stage_pixel`（:245）亲读在位+world_mapping_tests 在 libtests 绿内 |
| **SP7 ⚪ PIE 2D 存疑** | **T2 判别闭合**：embedded 忠实/windowed 不忠实（7/7+QA 亲测复现）；book §九如实分流；M14 形态维持 |
| **SP8 ⚪ 裸 z** | **记档兑现**：book §八注记+open-challenges:300-308（排序面板/Y-sort 两行亲读） |
| **SP9 ⚪ Anchor 九宫格** | **产品落地闭合**：anchor_presets.rs 九常量+3 单测（T2 QA 亲跑绿）+DOM 九格点（T2 QA 亲证）；现场点击腿三轮 D10 家族红（本轮 r3 walk 零 preset 格亲读）——常驻口径「非 Retina/GPU 会话或工具票后」维持，零回退 |
| **SP10 ⚪ 3D 组在 2D 场景** | **记档兑现**：book §三括注+open-challenges:312-316 亲读 |
| **SP11 → buglist A17** | **立票+机制精化**（§六）：票已立（buglist:493-495），T3 新证据与精化注记本轮评估采纳 |
| **M16 开箱腿** | ⚪ 部分承载：fixture=默认模板+prep 直书 Template::TwoD 形态场景（jd-new.log 亲读 modules: Physics；脚本 :53 注记自认直书）——「launcher 选 2D 模板冷启」独立腿未跑；实质面（2D starter 场景在编辑器/PIE/direct 三侧可见可跑+launcher 标签+scaffold 冷启门）在案。见 §七-5 |
| **关联票纪律** | A7（五招自守在脚本：md5 帧差+window/canvas 双通道+flakecheck 对拍+settle_pixels；未真踩不可绕形态）/A14/A15（无依赖知悉）/A16（book 一句话注记兑现，票面未动）/A17（票面更新归主控，本轮零触碰 buglist）✅ |
| **buglist/roadmap/台账纪律** | T3 提交零触碰 buglist/台账/roadmap（`git show --stat` 亲核）；roadmap T21 行未勾（留主控）✅ |

## 五、验收句逐词证据指认

roadmap T21 验收原文（方案 §0 逐字核实）：「**完整 Sprite 作者流程：导入/PPU/Pivot/
过滤/图集切分/绘制顺序/预览。验收=图片或 Sheet→可编辑可保存可运行的 2D 对象。**」

### 「图片或 Sheet→可编辑」——成立

| 验收词 | 证据（QA 亲读/亲验） |
|---|---|
| 导入 | T18 面复用+拖放成 sprite（#657 路由）：M1_IMAGE presence 绿×2+多轮会话红/蓝/SheetSpr 均上画布（T2 在档）；`sprite.add path` 产图形态（book 三入口+M1_OPERATOR） |
| 可编辑（图片） | 拾取（M2_PICK 三轮）+描边/gizmo（window 对 1.27%+QA 目视）+Inspector 字段表（fork Sprite 结构逐字段在+机器在）+Pivot 九宫格（代码+单测+DOM）+吸附/参考线（GUIDES_ADD 三轮绿+H 侧） |
| 可编辑（Sheet） | 图集卡 New Asset→grid→redo→重开全绿归档+卡 6 URect 盘面亲数+`sprite.atlas.grid` 整刀一条 undo（T2 绿在档，本会话 UNDO 红如实） |
| PPU | 定性落地（book 对照表，零代码=决策 2-A 字面） |
| Pivot | Anchor 面=预设格+裸 Vec2 同字段同 undo（T2 QA 亲读链+单测 3/3） |
| 过滤 | 诚实边界格：无授权面（book 注记=设计内「无面」如实入表） |
| 图集切分 | 上行+wear 盘面正门（scene.bsn texture_atlas 直书亲读） |
| 绘制顺序 | z 裸字段+top+1 语义（sprite_ops.rs:41 文档）+叠序几何旁证（本轮 m7 帧目视：TopSpr 蓝盖 Dropped 红露红条）+引擎 sort key+stage 族；翻转两拍 PX 本会话通道红（set_verified 证写未落，r3 :43-49）——按 T2 QA §四-3 口径 z 语义维持绿 |

### 「→可保存」——成立

M9 三件（REOPEN 逐字段+BSN_TYPES 全路径类型+KIND_REOPENED kind 再识别）r2/r3 两轮
归档绿（r1 声明归档缺失 §七-1）；bsn 文本全路径类型 QA 盘面亲读（`bevy_sprite::…Sprite`
拼写+`bevy_image::texture_atlas::TextureAtlas` 卡头两拼写均引擎可解析=脚本双拼写 grep
的根据）；图集引用与 index:2 落盘亲读；2D kind 重开识别=T2 probe L1 行为级证明在档。

### 「→可运行」——成立

direct run 4/4 归档（数值 face==授权值+Camera2d+窗口 hero-red 0.033%+图集文档+walk
「Loaded 1 asset files」亲读）；PIE embedded 忠实（T2 probe 7/7+QA 条带普查逐位复现）；
导出=T2 M15 六件绿在档（T3 抽格口径未含 export，D9 如实——staged 半边以 T2 归档承载，
预期与 §二 A17 发现同形：包内 wear 在、渲染全图）；开箱=2D starter 场景三侧可见可跑
（编辑器画布/PIE embedded 流/direct 窗口三处 QA 目视）+scaffold_e2e 冷启门绿。

**诚实边界（不反达标）**：A17——wear 的 sprite 两侧均渲染全图而非 index 帧（QA 目视
定案）；「可运行」的字面由数据链（切分/指认/index 保存-重载-walk 装载逐字无损）+进程
行为承载，index 的**画布可见面**是记录缺陷 A17 的修复门，book §七/§九-30 秒清单已如实
注记（§九残句除外，偏差 1）。

## 六、A17 机制精化评估（任务指定：只评估证据，票面更新归主控）

**T2 QA 原裁**：「loader 缺面」（编辑器 scene→定义资产 handle 的 AssetServer 面无
.bsn loader→ERROR+全图渲染）。**T3 精化**：「双柄空间——场景文档的
`Handle<TextureAtlasLayout>`（AssetServer 路径柄）不解析到 walk/catalog 装载进 Assets
store 的卡；路径柄永不就绪→sprite 提取回落全图」。

**QA 评估：采纳精化，定为「机制注记（最佳解释）」而非定案。**

1. **负证据充分且 QA 独立复证**：T3 两份编辑器进程日志（editor-editor/editor-atlas）
   `Could not find an asset loader` **零命中**（grep 亲算）——prep 先建卡后 loader
   ERROR 消失，而全图渲染依旧（QA 目视 m2/m7 两帧独立确认编辑器画布全图）——**「全图
   渲染」不以 loader ERROR 为必要条件，「loader 缺面」作为单因读法被闭合**。
2. **run 侧同形且 QA 目视定案**：direct 游戏窗口六 tile 全图（§二-4）；walk 装载链绿
   （M10 10/10+「Loaded 1 asset files」）——卡确已进 Assets store 而渲染仍全图=「卡
   已装载」与「sprite 未用到卡」并存，正是**柄空间不统一**的形态学证据。
3. **盘面形态与精化自洽**：场景文档 `layout: "content/sheet.bsn"` 是**路径串**（apply
   时成 AssetServer 路径柄，QA 亲读 scene.bsn:24-26）；卡经 walk/catalog 柄装载
   （M10 测试的 catalog 句柄链）——两侧柄不同源，「路径柄永不就绪」解释全部观测
   （含游戏侧 WARN 零命中=回落静默）。
4. **正面直接观测仍缺**：无柄 pending/resolve 失败的运行时直接读数（如 AssetServer
   debug 面）；精化文本自身亦以「机制注记」措辞（T3 报告 §三-4「A17 票的修复方向两臂
   以票面原文为准，本证据供主控裁修复面时参考」）——**措辞纪律正确**。
5. **给主控的裁定参考**：buglist A17 票面更新时建议——①现象面改为「两侧进程同形：
   编辑器画布与游戏/导出窗口均渲全图；loader ERROR 与卡是否先在盘相关，非机制判据」；
   ②修复面两臂（scene 内 loader vs 改持图片路径+运行时构建）评估时注意**编辑器与游戏
   两侧的装载面不同**（catalog 面 vs walk 面），单臂修复需验证两侧同愈；③T3 报告
   §三-4+全分辨率帧（shot-M13_ATLAS-window.png）+QA 本节为证据组。

## 七、偏差与记档分级（QA 视角，0 🔴 + 1 🟡 + 7 ⚪）

| # | 项 | 事实 | 级别 | 处置 |
|---|---|---|---|---|
| 1 | **book §九尾句与 A17 现状注记自相矛盾**：`sprites-2d.md:187-188`「…and a staged build draws indexed tiles like a direct run」——与本章 §七（:154-162「两侧均渲染全图…A17」）、30 秒清单第 4 条、T3 新证据（QA 目视全图）三面相抵，系 E5 被否旧表述的残留 | 🟡 | **一行勘误随合入落笔**（建议改「a staged build renders exactly like a direct run — the whole sheet today (A17)」）；不动摇任何验收词（读者沿 §七/30 秒清单得到正确现状），但属交付面事实错误，随合入必改 |
| 2 | **r1 editor console 0 字节**（loop/t21-live/console-editor_r1.log）：T3 报告 §三-2 的 r1 判定列（含 M1_IMAGE 旧判据红、M2 viewport2d 对）无归档载体——A1/D14 家族复发 | ⚪ | 「拾取+描边三轮全绿」按归档实数 **r2/r3 两轮**读；报告列如实但载体缺失照 A1 口径记档；下轮先 `cp` 红态再重跑的纪律再申 |
| 3 | **game 遮挡轮 console 0 字节**（console-game_r1-occluded.log）：D7「M13_WINDOW_PX 首轮红=TCC 弹窗遮挡」的红证无归档载体（弹窗帧亦不在档） | ⚪ | 终轮 4/4 全归档承载判定；遮挡轮红证记「会话在证、归档缺失」；与 #2 同族同处置 |
| 4 | **ATLAS_INDEX_PX 归档链**：归档 console 的名义 PASS 系旧全窗 cmp 判据（chrome 噪音平凡满足）；严格判据（sprite 区域裁剪）的离线判定=逐字节同→无效；报告声称「裁剪三件归档 loop/t21-live/」但**该三件不在档**（find 亲证） | ⚪ | **QA 以脚本同参独立复现**（sips `-c 110 130 --cropOffset 450 1300`：三裁剪 md5=`0c15a625…` ×3 与报告逐字同；另以全图 BMP 比对证三拍只差 Inspector 文本区 x:2563-2673/y:219-237）——判定实质成立；QA 已把复现裁剪三件归档 `t21t3_qa_atlas_index_crop{0,1,2}.png` 补链 |
| 5 | **M16 开箱腿未独立跑**：fixture 经默认模板 `jd new`+prep 直书 2D starter 场景（非 launcher Template::TwoD 选择路径）；「开箱冷启 2D」无独立归档腿 | ⚪ | 实质面三侧可见可跑+标签/脚手架在案；T22 若触碰 2D 关卡模板，开箱腿顺手补 |
| 6 | **派单抽格名 T16/T20 词表迁移**：「M12+AU6 拒写门」「lane retry」「NOT-SAMPLED best-effort」为 T16 音频域/T20 live 脚本词表，t21-live.sh 零命中 | ⚪ | 按 T21 对应面核（§二-3：-23402 结构门+set_verified+read_ready 三件=设计内口径全数行使）；派单模板域串词记档，不构成漏验 |
| 7 | **T3 报告 df 门前数**：报告头「53Gi free」vs 双归档（console-prep.log+gates_exit.txt）均 51Gi | ⚪ | prose 级；主控合入时可顺手改「51Gi」 |
| 8 | **QA integration 轮 A6 三试全红**（程序轮 TRY3 过）：满载下 flake 更深一次 | ⚪ | A6 定案口径内（隔离绿+签名同文+0 新增红）；A6 票已有三连红先例（T13-T3），本轮为其「满载红/隔离绿」模式的再目击，票面刻画无需变更 |

**未动面**：`src/`、`crates/`、templates、fork（HEAD=f83d83b41 本轮复核未变）、协议、
场景格式——T3 零产品改动；buglist/台账/roadmap 本轮未写；工作树仅 QA 归档（git status
全量亲录）；RUST_BACKTRACE 全程未设；门链独窗；QA 预清已闭环 T19/T20 fixture 构建缓存
（48Gi，T19-T1 偏差 3 先例），活跃 t21-sprite fixture 未触碰；结束进程清盘（pgrep 零
jackdaw/t21-sprite 残留亲验）。

## 八、最终裁决与 roadmap 建议

- **T21-T3 验收标准（方案 §四-T3）**：真机矩阵关键格终态复跑 ✅（§二：四格原文全读+
  像素亲验，判定与归档逐行吻合，红项全部有根因归档）；book 新章+交叉引用 ✅（§三：
  十节九节半对锚、SUMMARY/出链/UI 名全过、一处残句🟡随合入勘误）；errata 落账 ✅
  （§三：六条+F4 逐条兑现）；全量门 ✅（§一：八门 QA 亲跑+clippy/doctests 归档抽核；
  integration 唯一红=A6 本体，隔离绿，0 新增红口径维持）。
- **T21 整体（T1/T2/T3）**：验收句逐词全数在案（§五）；「图片或 Sheet→可编辑可保存
  可运行的 2D 对象」三态成立（编辑面全链真机+盘面双证；保存面三轮归档+盘面亲读；
  运行面 direct 4/4+PIE embedded 忠实+导出 T2 在档——A17 的 index 画布可见面为记录
  缺陷、数据链无损且 book 如实注记）；SP1-SP11 结案清单逐条终态（§四：建设面 5 吸收
  闭合+定性 1+判别 1+产品落地 2+随行修 1+记档 3+立票 1）；门禁三轮 QA 链闭环
  （T1 PASS→T2 PASS（含 6 errata）→T3 终验，本轮全量门独立复现）；A17 机制精化采纳
  （§六）。
- **VERDICT: PASS——T21 整体闭环。roadmap T21（P2 段第 38 行）建议可勾选**，闭环注记
  建议含：验收句三态证据（三入口 sprite.add+窗口级拾取描边 gizmo+图集卡全链+M9 三件
  三轮+direct 4/4+PIE embedded 忠实）；SP 终态（SP1/SP2/SP3/SP5/SP6/SP7/SP9/M10 闭合、
  SP4/SP8/SP10 记档、SP11=A17 立票并精化为双柄空间注记）；A17 现状如实（两侧全图渲染
  =记录缺陷，数据往返无损，修复即画布预览升级）；门禁（libtests 3029/teaches 92、
  integration 程序轮 5575/5575+QA 轮 5574/5575 唯一红=A6 本体隔离绿）；book 新章
  （十节+四处出链，一处残句随合入勘误）；T21 产品面=六 PR 移植+SP3/SP9 授权面+fork
  一行（回滚=逐 commit revert+fork 一行独立 revert）。
- **主控合入路径**：照旧 `--no-ff`；主控落笔面=roadmap T21 勾选+收官行、台账 T21 行、
  buglist A17 票面精化更新（§六-5 三点参考）+**book :187-188 一行勘误**（偏差 1，随合
  入必改）+T3 报告头 df 数可选勘误（51Gi）。

## 九、用户 30 秒清单（book 章节尾定稿；终验对照通过，现状句如实）

1. 新工程选 **2D game** 模板，开 starter 场景：2D 画布上一个 sprite；**Play**：
   Game 面板看得见它（embedded 忠实）。
2. 拖任意 PNG 进画布：落点生成以文件命名的 sprite；点选→描边+移动 gizmo；拖动、
   方向键微调、`Ctrl+Z` 逐步回退。
3. Inspector 里点 **Pivot** 预设（如 Top Center）：sprite 绕自身位移；改 `color`：
   画布立刻跟随。
4. **New Asset → Sprite Atlas** 切网格、把 sprite 的 `texture_atlas` 指到卡上设
   index：**Save**、**Play**——游戏带着 wear 跑（今日画布与窗口都画全图——A17
   记录缺陷；切分/指认/index 的保存与重载逐字无损）。
5. 重开场景：transform、pivot、图集引用与 index 逐字段回来。

（QA 备注：第 2/3 步的画布交互在 1 FPS 软渲染+Retina 会话由三轮归档窗口证据背书；
SP9 预设**点击**腿与 M1_MENU picker 行为已知驱动缝——人工手点无碍，合成驱动待工具票。）

## QA 会话产物索引

- 门禁八门+A6 隔离+animation 分包：`loop/reports/t21t3_qa_{fmt,libtests,fast,
  audio_gate,save_store,integration,docs,scaffold_e2e,a6_isolated,animation_split}.log`
  +`t21t3_qa_gates{.sh,_exit.txt}`（后台链+轮询，df 95Gi 开跑）。
- 像素亲验复现件：`loop/reports/t21t3_qa_atlas_index_crop{0,1,2}.png`（md5 0c15a625…×3，
  裁剪参数=脚本同参）+目视帧（归档原件 loop/t21-live/shot-m2-selected-window.png、
  shot-m7-blue-top.png、shot-M13_ATLAS-window.png）。
- 核验对象：`loop/reports/t21-t3-report.md`+归档 t21t3_* 十三件；T1/T2 报告与 QA
  （t21-t1-qa/t21-t2-qa 含 F1-F4 口径）+t21-t2-report.md 落账面；`loop/qa/t21-live.sh`
  （atlas_face/atlas index/color_census/set_verified 段亲读）；`loop/t21-live/`（console
  六相+判定三件+direct-m13+selftest+jd-new+prep 双轮）；book 五文件 diff 与源码对照点
  （src/sprite_ops.rs、src/sprite_snap.rs、src/canvas_snap.rs、src/creation_taxonomy.rs、
  src/inspector/anchor_presets.rs、src/test_input.rs、src/launcher/mod.rs、src/lib.rs:4338、
  fork sprite.rs、bevy-fork-pinned HEAD）；buglist A6/A7/A14/A15/A16/A17+roadmap 第 38 行。
- 进程收尾：QA 复查零 jackdaw/t21-sprite 残留进程；fork 零触碰；RUST_BACKTRACE 全程
  未设；门链独窗；df 出口 93Gi；工作树除 QA 归档 15 件外零触碰。

—— QA agent（loop 自动化终验），2026-11-01
