# T17 终验 QA 报告：任务 3（收官段）+ T17 整体终验（只验不修）

> 验收对象：分支 `loop/t17-save` @ **eb16fdf8**（基线 main=8db72bff；程序提交=T17-T3 收官，
> T2 已于 01263554 合入）。程序报告：`loop/reports/t17-t3-report.md`。前置：T17-T1 QA PASS
> （t17-t1-qa.md，回流 A-C 在案）、T17-T2 QA FAIL（SV9）→返工 3c4ffa8b→复验节转 PASS
> （t17-t2-qa.md §十三-十六，交接硬性三条在案）。
> T3 diff 亲核（numstat 全件）：**产品面=book 五文件（新章 258 行+SUMMARY+三交叉引用）
> +tests/ 一文件（guards game_flow_template +6/−1）+loop 工具与归档**——`src/`、`crates/`、
> 模板、fork、协议、场景格式零改动（commit 全件无该域路径）。buglist/台账/roadmap 零触碰。
> QA 手段：**Mac 全量门亲跑**（串行后台链 `loop/qa/t17t3-qa-gates.sh`+`-gates2.sh`，全程未设
> RUST_BACKTRACE，门前清盘 `target/debug/incremental` 13G→df 47Gi，门链独窗）+**heavy 档
> 定向腿亲跑**（integration 门结构性排除 `bsn_game_run` 等重二进制——QA 亲跑 bsn_game 3/3
> 补 M2 终树绿证+A6 隔离 1/1 绿）+T3 真机 26 件证据**原文全读**（三格 witness 逐字节 diff
> T2 对应件+summary 两相+warn 三件+N13 双件+PX 截图亲览）+book 新章九节逐节对锚
> save.rs/模板源码+门禁归档 13 件抽核（clippy 双包/doctests 采信归档）。
> QA 归档 `loop/reports/t17t3_qa_*` 15 件（8 门日志+5 定向腿日志+gates_progress+signal 红
> 旁证件）+门链脚本 2 件。

## 〇、结论

**PASS（T17-T3 收官 + T17 整体，含 roadmap T17 可勾选建议）**——全量门 QA 独立复现与程序轮
逐位吻合：integration **5440 跑 5439 过+唯一红=A6 已知件**（QA 独立复现同签名三试+
隔离 1/1 绿 3.810s；另一被信号打断的旁证轮 5422 跑 5421 过同样唯一红=A6，两轮互证「红跟随
二进制内并行负载」定案形态）；fast/libtests 双通道 **2990**、**teaches 91**、save_store **19/19**、
audio_gate **7/7**、fmt/clippy 归档零红、docs 17 条 warning=存量私项链接族零新增、scaffold_e2e
**1/1**；heavy 档 bsn_game **3/3**（`a_save_survives_the_fixture_restart` 27.6s 过=M2 H2 通道
终树绿证补齐）。T3 两相 10 判定复跑与 T2/QA 轮数值**逐字节一致**（五份 witness diff 实证，
唯一差异=L4 备份时间戳按设计浮动）；book 新章九节+SUMMARY+三交叉引用全落且事实面对得上
runtime/模板源码；**T2 QA 交接硬性三条全部落账**（§三）；验收句「重启恢复；缺文件/旧版/
损坏安全回退不崩」逐词证据在案（§四）；「与场景文件分开」三铁证成立（§四）；SV1-SV9 结案
清单全绿（§五）。game_flow_template 红的修复定性复核成立：**T2 遗留测试债、tests/ 单文件
+6/−1、非放宽容差**（§二）。**偏差 0 🔴 + 0 🟡 + 7 ⚪（§六）**——全部为归档精度/措辞/QA 侧
基建级，不动摇裁决。

## 一、Mac 全量门亲跑（权威口径，最终树 eb16fdf8；门链独窗，未设 RUST_BACKTRACE）

门前清盘：`target/debug/incremental`（13G，T3 收盘同款）→df 38Gi→47Gi；integration 前 40Gi、
全部门后 39Gi（A6 家族压力区全程宽裕）。

| # | 门 | 命令 | QA 亲跑结果 | 归档 |
|---|---|---|---|---|
| 1 | 格式 | `cargo fmt --all -- --check` | **EXIT=0**（3s） | `t17t3_qa_fmt.log` |
| 2 | 单测 | `cargo test --workspace --lib` | **EXIT=0；2990 passed / 0 failed**（58 个 test result 行求和亲算）；**scaffold teaches `91 passed` 行亲点**（含 `new_game_project_teaches_the_save_pattern ... ok`） | `t17t3_qa_libtests.log` |
| 3 | save_store 套件 | `cargo nextest run --profile ci -p jackdaw_runtime --test save_store` | **19/19 PASS**（0.121s） | `t17t3_qa_save_store.log` |
| 4 | audio_gate | `cargo nextest run --profile ci --test audio_gate` | **7/7 PASS**（9.7s） | `t17t3_qa_audio_gate.log` |
| 5 | fast | `cargo xtask fast` | **EXIT=0；Summary 2990/2990（88.5s）**；全文 0 FAILED/0 diff/`warning:`=0（唯一 `error` 串=PASS 行测试名 `jackdaw_bind error::tests::display_text_is_pinned`，T1 QA 同款归因） | `t17t3_qa_fast.log` |
| 6 | **integration** | `cargo xtask integration` | **Summary [2397.5s] 5440 run：5439 passed (19 slow)，1 failed，0 skipped**——唯一红=`jackdaw::prefabs prefab_lifecycle::prefab_file_change_triggers_reload` 三试全败，panic 同签名 `watcher reloaded prefab; v2 should be in world. Got ["v1"]` @ **prefab_lifecycle.rs:714 = buglist A6 原签名**；修复件 `game_flow_template::the_flow_walks…` **PASS 10.4s QA 亲见**；零其他红 | `t17t3_qa_integration.log` |
| 7 | docs | `cargo doc --workspace --no-deps` | **EXIT=0**；warning 面 **17 条=存量私项链接族**（与 T16 基线同数同族，save 域零命中） | `t17t3_qa_docs.log` |
| 8 | scaffold_e2e | `cargo nextest run --profile ci -p jackdaw --test scaffold_e2e` | **PASS 1/1**（154.9s） | `t17t3_qa_scaffold_e2e.log` |

**门后定向腿（QA 独立，均为 integration 门结构性排除/ known-flake 件）**：

- **A6 件隔离跑 ✅ 1/1 PASS（3.810s，100 skipped）**——「红跟随二进制内并行负载」定案口径
  在 T17 终树复现，与程序轮 `t17t3_a6_isolated.log`（3.192s）互证。归档 `t17t3_qa_a6_isolated.log`。
- **bsn_game heavy 档 ✅ 3/3 PASS（27.6s）**——含 **`a_save_survives_the_fixture_restart`
  PASS 27.6s**：M2 引擎级双跑腿（H2 通道）在终树的绿证由 QA 补齐（§六-4）。归档
  `t17t3_qa_bsn_game.log`。

**旁证轮**：QA 第一条门链在 integration 中段被外部 SIGKILL（harness 1h wall cap，§六-5）——
被杀时已跑 5422/5440：**5421 passed，1 failed=同一 A6 同签名三试**（18 件 not run due to
signal）。该轮与终轮两轮独立互证：integration 的唯一红恒为 A6、终树零其他红。全文保全于
`t17t3_qa_integration-signal18_red.log`。

**clippy 双包/doctests（采信归档抽核）**：`t17t3_clippy_ws.log`（deny-warnings 全仓，Finished
39.5s，`warning` 计 0）/`t17t3_clippy_physics.log`（Finished 30.2s 零红）抽核通过；
`t17t3_doctests.log` 主跑仅 `-p jackdaw_bind --doc` 处 dyld rpath 家族失败（`libstd-*.dylib
not loaded`，**第 10 次目击**，T15 定案环境票）+`t17t3_doctests_bind_rerun.log` 单包复跑
**1 passed（EXIT_BIND=0）**——T15 处方有效，双日志 mtime 顺序可追（04:38→04:46），采信。

**程序归档交叉复核**：`t17t3_fast.log` Summary 2990/2990（66.5s）、libtests 求和 2990/0、
save_store 19/19、fmt 0 字节、clippy 双包零 warning、scaffold_e2e 148.3s、
`t17t3_gates_progress.log` 逐门时间线（integration 首跑 EXIT=1+doctests EXIT=101 如实留痕）、
首跑两红摘录件在案——与 t17-t3-report §三门禁表逐项一致，无隐瞒。

## 二、game_flow_template 红的修复定性复核 → **成立：T2 遗留测试债，处置合格**

integration 层在 T17 模板改动后首跑（T2 QA 九门不含全量 integration——该层确属首次运行，
T16 偏差 1 同款模式）揭出两红=A6+本件；T3 自捕自修。

- **首跑红证**（`t17t3_integration-first-run-red_red.log` 亲读）：`the_flow_walks_the_three_
  documents_and_back_with_zero_residue` 三试同签名，`tests/guards/game_flow_template.rs:570`
  断言 `left == right failed: the one expected failure is the hud's; left: 3, right: 1`——
  模板副本 `GameState` 只有 `paused`，而 T2 给 menu/gameover 模板文档新增的
  `Res(GameState).runs_played`/`.unlock_note` 两绑定在副本上解析失败→BindFailures 3≠1。
  Summary `5440 run: 5438 passed, 2 failed`。
- **修复 diff 亲读**（`git show eb16fdf8 -- tests/guards/game_flow_template.rs`；numstat
  **+6/−1**）：副本 `GameState` 补 `runs_played: u32`+`unlock_note: String` 两字段+四行 doc
  说明（「the copy keeps them so those bindings resolve the way the real game's do」）。
  **断言门本身一字未动**——`:570` 仍钉「恰 1 个预期失败（hud 的）」，修复是让副本镜像真实
  模板使绑定可解析，**非放宽容差**。
- **定性三点**：①根因=T2 模板文档改动未同步 guards 副本，**债在 T2、暴露在 T3 首跑、
  非 T3 引入**；②改动面合规——numstat 全件 `tests/` 单文件，`src/`/`crates/` 零 diff；
  ③绿证闭环——隔离 3/3（`t17t3_gameflow_isolated.log`，3.997s）+终树全量 PASS 10.4s（程序
  轮 8.9s+QA 轮 10.4s 两轮亲见）。
- **`game_ui.rs` 副本不修的口径核实成立**：QA 亲读其 `GameState` 副本仍只有 `paused`（:63-65）
  ——该测试只装 hud.bsn（无 runs 绑定），终树 integration 其 6 件全 PASS 亲见
  （含 `the_hud_is_the_only_ui_and_it_loads_with_its_bindings_resolved`）。
- **计数勘误**：程序报告偏差 1 写「+8 行」、任务书写「+7 行」，git numstat 实为 **+6/−1**——
  措辞级偏差记 §六-1，实质（tests/ 单文件、非放宽、src/ 零 diff）不受损。

## 三、book 核对（方案 §四-T3-2 九节书单+SUMMARY+三交叉引用+T2 QA 交接三条）

`book/src/user-guide/game-saves.md`（258 行新章）逐节亲读，事实面逐条对锚
`crates/jackdaw_runtime/src/save.rs` 与模板源码：

| 书单项 | 落点 | 源码/证据对照（QA 亲验） | 判 |
|---|---|---|---|
| 1 开篇两层语义（`config asset (authored default) < save (player override)`+「分开」分工） | 首两段 | M6 真机活证（authored 0.9 不洗 0.35+文件未动；删档→0.9 站住——脚本 m6 断言亲读） | ✅ |
| 2 Where the save lives（三 OS 路径表/save.json 全文示例/分开三硬理由（导出只读分发、工程树零污染、PIE temp 拷贝不碰它）/`JACKDAW_SAVE_DIR` 整体替换缝） | §2 | 路径表与 `save_dir` 三层兜底（save.rs:365-370 `var_os`+原样返回不拼 id，T1 QA §二-⑤ 亲核）一致；「整体替换」与 `the_environment_seam_moves_the_whole_save_directory` 常驻针一致 | ✅ |
| 3 One line to save（一行接线/SaveStore 三字段表/get_mut 置 dirty+**BRP 直改不置 dirty 边界如实写**/write·reload·reset_to_default/惰性建目录） | §3 | `SavePlugin::build` 同步 load+insert+注册（T1 QA 源码级）；`get_mut`（save.rs:269）置 dirty；BRP 边界=T1 QA 回流 D 全状态口径，book 措辞与之相符 | ✅ |
| 4 What the template saves（四类数据表/audio 桥=loader 自灭就绪门后覆盖/input 桥=union merge「旧档不吃完新动作」/menu `Runs:` 镜像） | §4 | 桥四件 `.after(apply_config_defaults)`+armed 帧（T2 QA §三亲读）；`merge_actions` union 语义（game_input.rs:233-246）；`UNLOCK_ENDLESS`/`count_run_over`（template:843/:933-966） | ✅ |
| 5 The three-state fallback（**六态行为表** Fresh quiet/Loaded/Recovered+备份/迁移升级/VersionSkipped+文件不动+自动写抑制/NoDir；两成文规则：坏档只备份不销毁、**读不懂的存档绝不被覆盖**（reset_to_default=唯一刻意丢弃门）；迁移 opt-in） | §5 | 六态与 `SaveStatus` 枚举（save.rs:106-134）逐变体对上；抑制双钉（`flush_saves` skip :461+`write()` 拒 :283-291）；doc 原文「an unreadable save is never overwritten」（:48-59） | ✅ |
| 6 The pause screen's sliders（ValueChange→观察者→config→watcher 同帧落盘；重启位与音量同恢复；**SV9 形态 A 边界注记**：FeathersSlider=scene component，BSN 组件行只挂 require 链永不展开场景→模板 hud.bsn 只写标签行挂点+Rust `spawn_scene(bsn!{@FeathersSlider})`+反射注册，「自己加控件」照此形态） | §6 | 修复形态 A 逐字（T2 QA 复验 §十三）；L7 机械断言（Node 全形+Children 825v0）+QA 亲览截图三滑条肉眼可见=活证 | ✅ |
| 7 Play writes the real save（PIE 同槽语义+「Play 覆写 standalone 进度」后果明示；**回流 E 单写方纪律**：固定 `save.json.tmp` 即刻 rename、中断写=上次好档、loader 永不误认 tmp；固定 tmp 名=单写方契约、双活进程同槽在契约外、三态回退兜住最坏情形、双活各指各的 `JACKDAW_SAVE_DIR`） | §7 | `atomic_write`（save.rs:654-673 tmp+sync_all+rename）+`a_stray_temp_file_is_never_taken_for_a_save` 常驻针；L6 PIE 同槽活证 | ✅ |
| 8 When a save goes wrong（四症状清单：首跑静/损坏 warn+备份+复活/异版本 saving 暂停+status 指路/目录不可写单次 warn+重试；「loud in the log, quiet in the game」与音频坏字节崩溃态对照=AU6 域呼应） | §8 | 与 `load()` warn 分支表+`warned_write_failure` 单次+重试（M12 测试）一致 | ✅ |
| 9 The 30-second check（六步：首跑零目录/kill 后重启 Runs:1/滑条恢复/删档安静/乱码档 warn+备份+复活/开档读真） | §9 | 与 T2 QA §十一草稿的 SV9 后兑现版+T3 报告 §五-4 一致 | ✅ |

**SUMMARY+交叉引用**：`SUMMARY.md:29` 挂目于 Game Flow（:28）之后=方案指定位 ✅；
`audio.md`（设置屏段改写「模板暂停屏即此物+存档把改动放回 authored 之上」+回链）✅；
`game-flow.md`（「Restart resets the *player*, not the *player's record*」+回链）✅；
`game-ui.md`（**overlay 表 PauseScreen 行勘误**「Title + Resume button」→「+ three volume
sliders」+新增段指路持久半边与 scene-component 边界）✅。章内出链 8 目标
（game-parameters/play-in-editor/resources/remote-debugging/game-flow/audio/game-input/
game-ui）**逐一存在亲验** ✅；book 无图嵌（章惯例），未引具体 PNG 数值 ✅。

**T2 QA 交接硬性三条落账位置指认**：①**回流 E**=book §「Play writes the real save」第二段
（固定 tmp 名=单写方契约+双活各指各缝）——T2 QA 偏差 13 的红旗解除；②**SV9 形态 A**=book
§「The pause screen's sliders」末段（scene component 边界注记+`spawn_scene` 形态教学）；
③**截图措辞以归档 PNG 为准**=T3 报告与本轮均按 Master 0.35/Music 0.6/Sfx 0.5 口径（QA 本轮
亲览归档 PNG 实证同读数），book 未嵌图故无引用面。**三条全兑现。**

## 四、验收句三铁证终态+两相 10 判定一致性

roadmap 第 31 行验收原文（逐字在案）：「运行时存档接口+示例（进度/解锁/音量/输入设置），
与场景文件分开。验收=重启恢复；缺文件/旧版/损坏安全回退不崩。」

### 铁证①重启恢复——三通道独立成立

| 通道 | 证据 | 独立性 |
|---|---|---|
| H（headless 双 App） | save_store **19/19 QA 亲跑**（M1 双 App+M9-M12 三态+回流 F 三边界+reload/slot） | 进程内 drop/重建，纯文件断言 |
| H2（引擎级双进程） | bsn_game **3/3 QA 亲跑**，`a_save_survives_the_fixture_restart` 27.6s（run1 Fresh 写档打标记→run2 同 scratch 断恢复标记+盘上 envelope） | fixture 二进制×两次真实进程边界 |
| G（真机杀进程） | L3：`pkill -9 -x t17-save`+pgrep 防残留（脚本 ：473-474 亲读，**排除优雅退出钩子假阳性**）→重启→`l3-store-witness.json`：**Loaded+runs_played=3+unlocks=["endless"]+audio 0.7/0.6/0.5（f32 全精度形）+Move 首绑 KeyE**+桥读回（config 三值/merged 5 动作）+GameState 镜像 runs=3 | 模板 fixture 真窗口进程 kill -9 |

三通道三 harness 三断言面，无共享绿灯路径。**与 T2/QA 数值一致性：五份 witness 逐字节 diff
——L1/L3/L5/L6/l7-path 全等，L4 仅备份时间戳按设计浮动**（`corrupt-1793376814109`→
`corrupt-1793389086701`）；两相 summary 文件与 T2 逐字节相同（7+3 判定全 PASS）。

### 铁证②三态安全回退不崩——headless 全针+真机抽腿成立

- **缺文件**：L1（scratch 空→Fresh+四类默认+**盘上无目录**+零 `game save:` warn+mutate 0.7
  同帧落盘——脚本 ：396/:408-416 双断言亲读）+H 侧 M9。
- **旧版**：H 侧 M10a/b/c+回流 F 三边界常驻针（退化步 walks-backwards→VersionSkipped 文件
  字节不动/越顶→Loaded serde 终检/超 u32→Recovered 备份）——19/19 内 QA 亲跑；**VersionSkipped
  抑制不变式双钉**（flush skip+write 拒绝）T1 QA 实弹验证在案。
- **损坏**：L4 空文件→**Recovered{backup: save.json.corrupt-1793389086701}**（witness 原文）+
  `game save:` warn **恰 1 行**（19:38:06Z，点名路径+「starting from the default (the original
  is kept as …)」原文亲读）+默认站住（runs=0/audio=null）+config mutate 0.6→槽位复活+进程
  全程未崩；H 侧五形态全 Recovered+备份字节逐字节原样。
- **不崩**：两相 WARN_SCAN panics=0（direct 侧）/N13=6 全部 PIE 已知签名（编辑器侧）；全部
  腿进程存活至判定完。

### 铁证③「与场景文件分开」——三面盘证成立

①**路径面**：存档落用户目录（macOS `~/Library/Application Support/<game-id>/`，witness 链+
macOS 常驻针 `ends_with("Library/Application Support/<id>")`）；②**包面**：L5 导出腿
`find "$STAGED" -name save.json`+`find "$PROJECT/assets" -name save.json` **双零命中断言**
（脚本 ：771-677 亲读，console「L5: staged tree clean of player data」在案）+staged 异目录
跑同槽 Loaded master 0.75（`l5-store-witness.json`，与 T2 逐字节一致）；③**无泄漏面**：L6
PIE 前后 `menu.bsn` sha256 相等+assets 树零 save.json（脚本 ：830-833）+PIE temp 拷贝不碰
存档目录（book 三硬理由）+**QA 残留检查实证真档树零 t17_save/bsn_scene 污染**。

**M14 warn 扫描归零核**：两相 `warn-unattributed.log` **0 字节亲验**；词表亲读=
`UnresolvedTypes|cannot.apply|cannot-apply|scene component|without its scene`+`game save:`
计门（SV9 复验轮补的两词在位；AudioPlayer 泛型注册形由 `cannot.apply` 家族覆盖）；`game
save:` 全部日志仅 direct-l4.log 恰 1 行（设计证据）；`no config asset` ×2/run=模板良性态
归因 12 行逐条亲读。**N13=6 记数核**：编辑器日志 QA 直查——`panicked at` 头**恰 6**+
`swap_remove index (is 0) should be < len (is 0)` 消息**恰 6**，与 console「panics counted:
6」/报告一致；direct 侧 0；T2=9→T3=6 浮动合规。归因上下文实读=3×`drain_game_events`
system+2×despawn command+1×`cleanup_session_on_stop`——同签名同 PIE 会话生命周期域
（buglist N13 域），报告「全部 @ drain_game_events」措辞偏宽记 §六-3。

## 五、QA 放行清单对照（方案 §六+各任务验收标准）

| 条目 | 裁定 |
|---|---|
| **T1/T2/T3 验收全绿** | T1 QA PASS（八门亲跑+源码级四专项+三探针互证）；T2 QA FAIL（SV9 单点）→返工 3c4ffa8b→复验节 **PASS**（修复六项全兑现+QA 独立真机复验+九门终树亲跑）；T3=本轮（§一/§二/§三：两相 10 判定复跑+book 章+全量门+heavy 档补腿） |
| **SV1 🔴 游戏侧零存档面（建设主体）** | **已修结案（吸收）**。`save.rs` 761 行薄层+`SavePlugin::<T>` 一行接线+SaveStore 反射面+prelude 导出（T1 QA 源码级）；零 fork/编辑器/模板外依赖（dirs 一行） |
| **SV2 🟡 音量易失** | **已修结案（吸收）**。audio 桥+watcher 同帧落盘；活证=M6 两层语义（authored 0.9 vs saved 0.35 站住+文件未动+删档回落 0.9）+L7 滑条恢复 0.3499999940395355≈0.35+PX |
| **SV3 🟡 输入改绑易失** | **已修结案（吸收）**。input 桥 union merge；活证=L3 Move 首绑 KeyE 生效+缺省 5 动作全留+`the_saved_input_table_merges_with_the_defaults_as_a_union`（19/19 内） |
| **SV4 🟡 进度/解锁无概念** | **已修结案（吸收）**。GameOver 挂点计数+第 3 局 endless；活证=L2 三局真 game-over 路径（health=0 三轮）+L3 重启镜像 runs=3+unlock_note 非空 |
| **SV5 ⚪ 无用户目录帮手** | **已修结案（吸收）**。`dirs.workspace = true` 一行+`save_dir` 三层兜底（data>home>NoDir） |
| **SV6 ⚪ PIE/direct 槽位语义** | **决策 6-A 结案**。同槽活证=L6（PIE 写 runs=1→stop→direct Loaded runs=1，witness 与 T2 逐字节一致）；book §7 明示后果+双活各指缝 |
| **SV7 ⚪ `.corrupt` 备份无清理** | **记档不修（方案口径）**。book §5 成文规则如实写「the backups are not cleaned up——each one is a player's data」 |
| **SV8 ⚪ 多存档槽** | **记档（范围外）**。envelope+目录设计预留（saves/ 子目录）；本轮零 UI/槽管理 |
| **SV9 🔴 设置屏滑条（T2 QA 立票）** | **已修结案（形态 A）**。T2 QA 复验节转 PASS（六项全兑现+QA 独立复验：恰 2 marker/Node+Children/零 rejection/亲截图/ValueChange 路由）；T3 交接落 book §6 边界注记；T3 轮 L7 机械断言（Node 全形+Children）+PX 全过+本跑 `scene component` ERROR=0 |
| **验收句逐词** | **运行时存档接口**=save.rs+BRP 反射面（T1 探针③转常驻）✅；**+示例**=模板四类+三桥+teaches 91（save_pattern 亲点）✅；**进度**=runs_played witness ✅；**解锁**=endless witness ✅；**音量**=0.7/0.6/0.5+滑条同恢复 ✅；**输入设置**=KeyE+union merge ✅；**与场景文件分开**=铁证③三面 ✅；**重启恢复**=铁证①三通道 ✅；**缺文件→回退**=L1+M9 ✅；**旧版→回退**=M10+抑制不变式 ✅；**损坏→安全回退**=L4+M11 ✅；**不崩**=全腿进程存活+panics=0 ✅ |
| **buglist/roadmap/台账纪律** | 关联票 **A6/A8/A9/A10 均未打钩=正确**（A6 定案口径放行未修——本轮 QA 两轮独立复现同签名+隔离绿再证；A8 知悉低撞面——T17 零新 bsn 授权组件；A9 自守不前置——断言大头走文件系统；A10 绕行——direct 为主+PIE 单腿）；N13 未打钩（记数绕行）✅；T3 提交触碰零 buglist/台账/roadmap（numstat 亲核）；roadmap 第 31 行未勾（留主控合入）✅ |

## 六、偏差与记档分级（QA 视角，全部 ⚪ 不阻塞）

| # | 项 | 处置 |
|---|---|---|
| 1 | **修复行数三说**：程序报告偏差 1 写「+8 行」、终验任务书写「+7 行」，git numstat 实为 **+6/−1**（4 行新 doc+2 字段行，替换 1 行旧注释） | 措辞级勘误随本报告入档；实质（tests/ 单文件、断言门未放宽、src/ 零 diff）三说一致且成立 |
| 2 | **`t17t3_live-n13-editor-count.txt` 只有 5 行**（T2 同款件同形）：脚本 `grep -an … \| head -5` 硬上限的摘录件，真计数来自同函数 `grep -ac`（=6，console 在案）——QA 直查日志 6 头+6 消息实锤 | 归档精度记档（head -5 cap）；N13=6 定案 |
| 3 | **N13 归因措辞偏宽**：报告称「全部 @ `jackdaw::pie::drain_game_events`」——实读 3/6 为 drain_game_events system、2/6 为 despawn command、1/6 为 `cleanup_session_on_stop`；签名同为 `swap_remove index (is 0) should be < len (is 0)`、全部在 PIE 会话生命周期内（buglist N13 域） | 措辞级勘误；计数浮动（T2=9→T3=6）合规、绕行有效（L6 断言全过） |
| 4 | **integration 门结构性排除 heavy 档**（`-E not(binary(bsn_game_run)|…)` 亲读于门命令行）：M2 的 H2 通道不在 5440 内，T3 门链未在终树单跑 bsn_game（报告 §五-7 以零共享改动论argued） | **QA 本轮亲跑 bsn_game 3/3 补齐终树绿证**（`a_save_survives_the_fixture_restart` 27.6s）——已闭合；后续任务若触碰 fixture/模板宜将 heavy 档列入收官门 |
| 5 | **QA 第一条门链被 harness 1h wall cap SIGKILL**（integration 中段，18/5440 not run due to signal）：被杀轮已跑部分 5422 run 5421 passed **1 failed=同一 A6 同签名**，与终轮互证 | QA 侧基建注记（非产品、非程序轮）；被杀轮全文保全 `t17t3_qa_integration-signal18_red.log` 作旁证；p2 链跑完全程 |
| 6 | **game 相 warn 归因件混入 2 行 stale staged-run.log**（T2 旧件被 game 相扫描，`no config asset` 良性态）——T3 报告偏差 4 自报 | 采信自报；本轮真机 staged 日志以 `t17t3_live-staged-run.log`（editor 相产出）为准 |
| 7 | **doctests bind dyld 第 10 次目击**：主跑仅 `-p jackdaw_bind --doc` 失败、单包复跑 1 passed（EXIT_BIND=0），双日志归档+mtime 顺序可追 | T15 定案环境票口径沿用，非 T17 引入，采信 |

**未动面**：`src/`（编辑器）、`crates/`（产品）、fork、协议、场景格式——T3 零改动（T17 全弧
产品面=T1 的 runtime 一 crate+T2 的模板/fixture+T3 的 book/tests 一文件）；buglist/台账/
roadmap 本轮未写（主控合入时落笔）。

## 七、最终裁决与 roadmap 建议

- **T17-T3 验收标准（方案 §四-T3）**：14 格终态+重点腿复跑（两相 10 判定全 PASS，含方案点名
  L3/L4/L5+L6/L7/M6 超出下限）✅；book 新章九节+SUMMARY+三交叉引用 ✅（§三）；buglist 预期
  无打钩 ✅；台账/roadmap 留主控 ✅；终验门全量日志全文复核+QA 亲跑 ✅（§一）。
- **SV 系收口**：🔴 SV1/SV9 全修、🟡 SV2/SV3/SV4 全修、⚪ SV5/SV6 吸收/裁定结案、⚪ SV7/SV8
  记档（book 作者面如实披露）；无未结票遗留 T17 域。
- **T17 整体（T1/T2/T3）**：验收句逐词全数在案（§四）；两铁证独立性成立（重启恢复三通道
  三 harness；三态回退 headless 全针+真机抽腿）；「与场景文件分开」三面盘证；T1 回流 D/F
  兑现亲核成立（T2 QA §二）、回流 E 于 T3 落账（§三）；T2 交接硬性三条全兑现（§三）；
  fast/libtests 2990、teaches 91、save_store 19/19、integration 5439/5440（唯一红=A6 定案
  口径，QA 两轮独立复现同签名+隔离绿）双轮吻合；integration 层 T2 遗留测试债自捕自修且仅
  触 tests/ 一文件（§二）。
- **VERDICT: PASS——T17 整体闭环。roadmap T17（第 31 行）建议可勾选**，闭环注记建议含：
  验收句逐词证据（重启恢复三通道 witness+三态回退六态表+分开三面盘证）；SV1-SV9 终态
  （SV1-SV6 修/裁定、SV7/SV8 记档、SV9 形态 A 复验 PASS）；integration 5439/5440 唯一红=A6
  （QA 两轮复现同签名+隔离绿，定案口径；首跑第二红=T2 遗留测试债已修，仅 tests/ +6/−1）；
  book 九节新章+T2 交接三条落账；⚪ 偏差七项不阻塞（N13 归因措辞/count 件 head-5 cap/行数
  三说/heavy 档结构性排除已补腿等）。
- 主控合入路径照旧 `--no-ff`（eb16fdf8 单提交随 T2 之后）；台账 T17 行、roadmap 勾选由主控
  合入时写（本轮 QA 零产品/台账/buglist/roadmap 触碰，工作树仅新增 QA 归档 15 件+门链脚本
  2 件+本报告）。

## 八、用户 30 秒清单（book §9 的实机版，T3 报告 §五-4 采信版沿用）

1. **首跑**：新建游戏（Game 模板）→Play/直跑：菜单 `Runs: 0`，且
   `~/Library/Application Support/<game-id>/` **不存在**（首跑零痕迹）。
2. **重启恢复**：进一局故意死一次→Game Over 计数+1→**强杀进程重启**→菜单 `Runs: 1`
   （kill -9 也不丢，无优雅退出钩子）。
3. **滑条**：Escape 暂停→拖 Master→音量即变→重启→**滑条位置与音量同恢复**（SV9 修复后
   真实可拖形态）。
4. **缺文件**：删 `save.json`→重启→游戏照跑零报错（安静默认）。
5. **损坏**：把 save.json 改成任意乱码→重启→一行 `game save:` warn 点名路径+旁边多出
   `save.json.corrupt-<时间戳>` 备份+默认站住；再改一次音量→槽位复活。
6. **文件是真相**：文本编辑器打开 save.json——`save_version`/`saved_at`/`profile` 人可读。

## QA 会话产物索引

- 门禁八门+定向两腿+旁证一轮：`loop/reports/t17t3_qa_{fmt,libtests,save_store,audio_gate,
  fast,integration,docs,scaffold_e2e,bsn_game,a6_isolated}.log`+
  `t17t3_qa_integration-signal18_red.log`+`t17t3_qa_gates_progress.log`；脚本
  `loop/qa/t17t3-qa-gates.sh`+`t17t3-qa-gates2.sh`（串行，unset RUST_BACKTRACE）。
- 核验对象：`loop/reports/t17-t3-report.md`+归档 t17t3_* 26 件（三格 witness/warn 三件/
  n13 两件/summary 两件/console 两件/首跑红摘录/隔离两件/clippy 双包/doctests 双件/PNG
  亲览）+`loop/t17-live/` 工作目录；T1/T2 报告与 QA（含 T2 复验节）+buglist A6/A8/A9/A10/
  N13+roadmap 第 31 行；修复 diff 全文（`git show eb16fdf8 -- tests/guards/
  game_flow_template.rs`+numstat 全件）；book 五文件+save.rs/模板源码对照点；t17-live.sh
  关键腿断言亲读（L1/L3/L4/L5/L6/M6/m6fresh/warn 词表）。
- 进程收尾：QA 复查零 jackdaw/nextest/t17-save 残留进程；真档树 `~/Library/Application
  Support/` 零 t17_save/bsn_scene 污染；`JACKDAW_SAVE_DIR` 零 env 残留；df=39Gi；门链独窗；
  RUST_BACKTRACE 全程未设；工作树除 QA 归档新增外零触碰。

—— QA agent（loop 自动化终验），2026-10-31
