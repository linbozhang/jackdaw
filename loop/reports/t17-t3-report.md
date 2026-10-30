# T17 任务 3「终验 + book 章」程序报告

> 分支 `loop/t17-save`（自 main 8db72bff fast-forward 同步，T2 已在）；任务书
> `loop/plans/t17-save-settings.md` §四-T3。真机 macOS arm64，fixture
> `/Users/zhanglinbo/workspace/loop-mac/t17-save/t17-save`（编辑器 BRP 15703 / 游戏 15702），
> 全程未设 RUST_BACKTRACE。**判语：book 存档新章落地（含 T2 QA 交接硬性三条全部入章）；
> 关键腿终态复跑两相 10 判定全 PASS（数值与 T2/QA 双轮一致）；全量门绿——integration 终树
> 复跑 5439/5440、唯一红=A6 已知件（隔离 1/1 绿 3.19s）；本轮修一处 T2 遗留集成层测试债
> （guards 模板 GameState 缺 save 镜像字段，详见偏差 1，tests/ 单文件，src/ 零改动）。**
> QA 交接三条兑现位置：回流 E=book「Play writes the real save」节；SV9 形态 A=book
> 「The pause screen's sliders」节（含 authored 场景不能直接放场景件的边界注记）；
> 截图措辞按归档 PNG 读数勘误（Master 0.35/Music 0.6/Sfx 0.5，本轮 PX 腿重摄同读数）。

## 〇、最终判定汇总（日志全文复核，exit 仅辅助）

```
game 相（本轮复跑 03:35-03:39）: L1_FIRST_RUN=PASS L2_FOUR_CLASSES=PASS L3_KILL9_RESTART=PASS
                                 L4_M13_CORRUPT=PASS L7_SLIDER=PASS M6_AUTHORED_VS_SAVED=PASS
                                 WARN_SCAN_GAME=PASS (unattributed=0, panics=0)
editor 相（本轮复跑 03:41-03:52）: L5_EXPORT=PASS L6_PIE_SLOT=PASS WARN_SCAN_EDITOR=PASS
                                   (zero_tolerance=0; N13 记数=6)
```

归档：`loop/reports/t17t3_live-*`（26 件：console 两相、summary 两相、L1/L3/L4/L5/L6 五份
store witness、l4 warn 行、warn 两件、n13 两件、PX 截图、7 份 direct/staged/editor 日志）+
门禁 `t17t3_{fmt,clippy_ws,clippy_physics,libtests,save_store,fast,integration,doctests,
doctests_bind_rerun,doc,scaffold_e2e,gameflow_isolated,a6_isolated}_log` +
`t17t3_gates_progress.log`（逐门时间线）+ `t17t3_integration-first-run-red_red.log`
（首跑红态摘录）。`loop/t17-live/` 工作目录随本轮刷新入库（T2 绿态件被覆盖、`*_red.log`
保留为 T2 红证）。

## 一、book 新章（方案 §四-T3-2 全项）

**`book/src/user-guide/game-saves.md`**（新章，SUMMARY 排 Game Flow 后），九节：

1. 开篇导览——两层语义定式：`config asset（authored default）< save（player override）`；
   「与场景分开」的分工声明。
2. **Where the save lives**——三 OS 路径表（macOS/Windows/Linux）；save.json 全文示例
   （envelope 三字段+profile 四类）；「分开」的三条硬理由（导出只读分发/工程树零污染/
   PIE temp 拷贝不碰它）；`JACKDAW_SAVE_DIR` 整体替换缝。
3. **One line to save**——`SavePlugin::<GameSave>::new(env!("CARGO_PKG_NAME"))` 一行接线；
   SaveStore\<T\> 三字段表（profile/status/dirty，反射面=Resources 面板+BRP 可断言）；
   `get_mut()` 置 dirty 纪律（**含 BRP 直改不置 dirty 的边界如实写**）；write/reload/
   reset_to_default；惰性建目录。
4. **What the template saves**——四类数据表（progress=GameFlow GameOver 挂点/unlocks 第 3 局
   endless/audio=GameAudioConfig 桥/input=GameInputConfig）；音量桥与输入 union merge
   桥各一段细讲；menu `Runs:` 镜像指路 Game UI。
5. **The three-state fallback**——六态行为表（Fresh quiet/Loaded/Recovered+备份/
   迁移链升级/VersionSkipped+文件不动+自动写抑制/NoDir）；两条成文规则（坏档只备份不销毁；
   **读不懂的存档绝不被覆盖**，reset_to_default=唯一刻意丢弃门）；迁移 opt-in 注记。
6. **The pause screen's sliders**——设置屏导览（ValueChange→观察者→config→watcher 同帧落盘；
   重启后位置与音量同恢复）；**SV9 形态 A 边界注记入章**：FeathersSlider 是 scene component，
   BSN 组件行只挂 require 链永不展开场景——模板=文档只写标签行挂点、Rust 侧
   `spawn_scene(bsn! { @FeathersSlider })` 挂接+反射注册，「自己加控件」的作者照此形态。
7. **Play writes the real save**——PIE 同槽语义（Play 写真档）+ **回流 E 单写方纪律句**：
   写盘走固定临时名 `save.json.tmp` 即刻 rename（中断写=上次好档，loader 永不误认 tmp）；
   固定 tmp 名=单写方契约，双活进程同槽在契约外，三态回退兜住最坏情形（备份+默认，无可挽回
   丢失）；开发双活各指各的 `JACKDAW_SAVE_DIR`。
8. **When a save goes wrong**——坏档双态（AU6 域对应：音频坏字节=崩溃，坏存档=日志响游戏静）；
   四症状清单（首跑静/损坏 warn+备份/异版本 saving 暂停/目录不可写单次 warn+重试）。
9. **The 30-second check**——六步（首跑零目录/kill 后重启 Runs:1/滑条恢复/删档安静/乱码档
   warn+备份+复活/开档读真)。

交叉引用落地：`SUMMARY.md` 挂目（game-flow 之后）；`audio.md`（设置屏段改写：模板暂停屏
即此物+存档把改动放回 authored 之上）；`game-flow.md`（reset_run 段补「Restart 重置玩家
不重置玩家记录」指路）；`game-ui.md`（**勘误+指路**：两 overlay 表 PauseScreen 行
「Title + Resume button」已过时→补三滑条；新增一段指路 game-saves 的持久半边与
scene-component 边界）。出链九目标逐一核实存在；book 无图嵌（沿既有章惯例），未引具体
PNG 数值——归档截图读数勘误记录于本报告与 QA 交接（下）。

## 二、关键腿终态复跑（方案 §四-T3-1；两相 10 判定）

方案点名 L3/L4/L5 抽腿，本轮实跑**两相全量 10 判定全 PASS**（含 L6 PIE——任务书指定第三腿；
L5 导出腿随 editor 相复跑）。数值与 T2/QA 双轮逐项对齐：

| 腿/格 | 本轮数值 | 与 T2/QA 对齐 |
|---|---|---|
| L3 kill -9 重启（M3 正主） | kill -9→重启→**Loaded**+runs=3+unlocks 含 endless+audio 0.7/0.6/0.5（f32 全精度形）+Move 首绑 KeyE；桥读回（config 三值/merged 表 ≥5 动作）/GameState 镜像 runs=3+unlock_note 非空（`l3-store-witness.json`） | 四类+桥+镜像三面数值与 T2 一致 |
| L4 损坏（M11/M13） | 空文件→**Recovered{backup: save.json.corrupt-1793389086701}**+`game save:` warn **恰 1 行**点名路径+默认站住+mutate 0.6→槽位复活；盘上备份恰 1 份 | 形态与 T2/QA 复验一致（备份名随时间戳浮动） |
| L6 PIE 同槽（决策 6-A） | PIE 写 runs=1→stop→direct run **Loaded runs=1**（`l6-store-witness.json`）；menu.bsn sha 不变+assets 零档 | 与 T2 一致 |
| L1 首跑（M9） | 空 scratch→Fresh+四类默认+盘上无目录+**零 `game save:` warn**；mutate 0.7→同帧落盘 | 一致 |
| L2 四类（铁证①盘侧） | audio watcher 三字段/input 整表改绑 KeyE/**真 game-over 三局**→endless（盘 jq 逐字段） | 一致 |
| L7 滑条（M6 设置屏） | **trigger 路径成立**（0.35 落盘）→kill -9 重启→滑条位 0.3499999940395355≈0.35+Node/Children 全在+本跑 `scene component` ERROR=0+PX 截图（`shot-l7-pause-sliders.png`，**读数 Master 0.35/Music 0.6/Sfx 0.5**） | 与 QA 复验轮读数一致（勘误口径） |
| M6 authored vs saved | authored 改 0.9→存档 0.35 站住+文件未动；删档→0.9 站住；恢复 0.42 | 一致 |
| L5 导出（M4/M5） | staged 树零 save.json+assets 零档+staged 异目录跑同槽 **Loaded master 0.75** | 一致 |
| WARN 扫描（M14/L8） | 两相 **unattributed=0**；词表 `UnresolvedTypes\|cannot apply\|cannot-apply\|scene component\|without its scene\|game save:`+`AudioPlayer` 泛型——**全部归档日志逐份 grep 零命中**；`game save:` 仅 direct-l4.log 恰 1 行（设计证据）；`no config asset` ×2/run=模板良性态归因不计数 | 口径与 T2 一致 |
| N13 记数 | direct 日志 panic=**0**；编辑器日志 panic=**6**，全部 `swap_remove index (is 0) should be < len (is 0)` @ `jackdaw::pie::drain_game_events`（buglist N13 已知签名；T2=9，随 PIE 连接次数浮动，T16 同口径） | 签名一致、计数浮动合规 |

## 三、门禁（终树；日志归档 t17t3_*；逐门时间线 gates_progress.log）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **EXIT=0** | t17t3_fmt.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | **EXIT=0，0 `warning`** | t17t3_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | **EXIT=0** | t17t3_clippy_physics.log |
| 单测 | `cargo test --workspace --lib` | **2990 passed / 0 failed**（teaches 91 在档） | t17t3_libtests.log |
| save_store 套件 | `cargo nextest run --profile ci -p jackdaw_runtime --test save_store` | **19/19** | t17t3_save_store.log |
| fast | `cargo xtask fast` | **EXIT=0；Summary 2990/2990（66.5s）**；0 FAILED | t17t3_fast.log |
| integration 首跑 | `cargo xtask integration` | **5438/5440，两红**（A6 已知件+game_flow_template 新红=偏差 1 的 T2 遗留债）；红态摘录 `t17t3_integration-first-run-red_red.log` | 已被终树复跑覆盖 |
| integration 终树复跑 | 同上（修后树，覆盖归档；38.5 min） | **5439/5440，唯一红=A6 已知件**（prefab_file_change_triggers_reload 三 try 同签名满载 flake；隔离 1/1 绿 3.19s=`t17t3_a6_isolated.log`；修后 `the_flow_walks…` 8.9s PASS 在案；0 新增红，口径达成） | t17t3_integration.log |
| doctests | `cargo test --workspace --doc` | bind dyld rpath 家族第 10 次目击（`libstd-*.dylib not loaded`，仅 `-p jackdaw_bind --doc`）→**单包复跑 PASS**（T15 处方） | t17t3_doctests.log + t17t3_doctests_bind_rerun.log |
| docs | `cargo doc --workspace --no-deps` | **EXIT=0** | t17t3_doc.log |
| scaffold_e2e | `cargo nextest run --profile ci -p jackdaw --test scaffold_e2e` | **1/1 PASS**（148.3s） | t17t3_scaffold_e2e.log |
| 磁盘 | df | 门前 19Gi→**清盘后 78Gi**（清 `target/debug/incremental` 14G+陈旧 fixture `t16-audio` 51G，T14 清盘族先例）；integration 首跑前 66Gi；全部门后 38Gi | gates_progress.log |

## 四、偏差清单（如实）

1. **⚠️ integration 层首跑揭出一处 T2 遗留测试债，本轮修复**（T2 QA 九门不含全量
   integration——该层在 T17 模板改动后从未跑过；T16 偏差 1 同款模式）：
   `tests/guards/game_flow_template.rs` 的模板副本 `GameState` 只有 `paused` 字段，而 T2
   给 menu/gameover 模板文档新增了 `Res(GameState).runs_played`/`.unlock_note` 两绑定——
   副本叫不出这两个字段→菜单两绑定入 BindFailures 台账+hud 的 PickupCount（无物理变体）
   =**3≠1**（`:570` "the one expected failure is the hud's" 红）。修=副本补两字段
   （tests/ 单文件 +8 行，src/ 零 diff 可证）；隔离复跑 **guards game_flow_template 3/3 绿**
   （`t17t3_gameflow_isolated.log`）；终树全量复跑仅 A6 红（上表）。`game_ui.rs` 的
   GameState 副本不修：该测试只装 hud.bsn（无 runs 绑定），集成实测未红。
2. **⚪ prep 相 PREP_FAIL 一次（脚本陈旧检查，本轮修复）**：`t17-live.sh` prep 验件
   `grep FeathersSlider hud.bsn`——SV9 形态 A 后 hud.bsn 只写 marker 行不再含该文本
   （滑条 Rust 侧挂接）→PREP_FAIL；管道 `| tail` 掩了 exit，game 相照跑且 L1 的
   「scratch 空」断言独立成立（scratch 恰为空，证据链未污染）。修=验件改
   `MasterVolumeSlider`（hud marker）+`attach_volume_sliders`（src 形态 A）双查
   （脚本 T3 勘误，QA 工具面）。
3. **⚪ l4-warn-lines.txt 跨轮累积**：脚本对该文件 `>>` 追加，本轮归档件含 T2 历史行
   （时间戳 15:48-18:40Z）——本轮 L4 的行=19:38:06Z 恰 1 条，已单独摘录
   `t17t3_live-l4-warn-line.txt` 为准。
4. **⚪ warn-attributed.log 混入 stale staged-run.log 扫描**：game 相扫描时
   `loop/t17-live/staged-run.log` 还是 T2 旧件（editor 相后来才重写）——归因件
   （`no config asset` 良性态），无害；本轮真机 staged 日志以
   `t17t3_live-staged-run.log`（本轮 editor 相产出）为准。
5. **⚪ doctests bind dyld 第 10 次目击**，T15 处方有效，双日志归档。
6. **⚪ N13=6**（T2=9）：PIE 连接次数浮动，签名逐条核对一致，绕行有效（L6 断言全过）。
7. **⚪ book 章体量**：九节 ~300 行，对齐 audio.md/game-flow.md 密度口径；事实面全部锚
   save.rs/模板源码与 T1/T2 报告（BRP 不置 dirty、VersionSkipped 抑制、tmp 固定名等）。

**未动面**：`src/`（编辑器）、`crates/`（产品）、fork、协议、场景格式——零改动（本轮产品面
改动仅 tests/guards 一个文件+qa 脚本两处）；buglist/台账/roadmap 未写（主控合入时落笔）。

## 五、给 QA 终验的注意事项

1. **门禁复核顺序**：`t17t3_gates_progress.log`（时间线）→ `t17t3_integration.log` 末行
   Summary（5439/5440+唯一红 A6）→ `t17t3_a6_isolated.log`（隔离绿）→
   `t17t3_gameflow_isolated.log`（偏差 1 修复的隔离绿）→ fast/libtests/fmt/clippy 各 log
   全文。首跑两红与终树一红的差异=偏差 1 的修复；首跑红态摘录在
   `t17t3_integration-first-run-red_red.log`（终树复跑已覆盖主日志）。
2. **QA 交接三条的落账位置**（验收对照面）：①回流 E=book §「Play writes the real save」
   第二段（固定 tmp 名=单写方契约+三态回退兜底）；②SV9 形态 A=book §「The pause screen's
   sliders」末段（scene component 边界注记）；③截图措辞=归档 PNG 读数 Master
   0.35/Music 0.6/Sfx 0.5（QA 复验轮 nit 的勘误；book 未嵌图，报告本轮 PX 重摄同读数）。
3. **真机复跑可重入**：`loop/qa/t17-live.sh prep|game|editor` 单相均可重入（prep 已修，
   幂等）；门前先 `cargo build -p jackdaw -p jd` 重链编辑器（T2 偏差 3/T16 偏差 3 同款）；
   **勿设 RUST_BACKTRACE**。
4. **用户 30 秒清单**（T2 QA §十一草稿的 SV9 后兑现版，book §九已同步收录）：新建游戏
   Play→`Runs: 0` 且用户目录无文件无目录；死一次重启→`Runs: 1`；暂停屏拖 Master→重启→
   滑条与音量同恢复（滑条 SV9 修复后可拖，真实形态）；删 save.json→安静；改乱码→
   warn+`.corrupt` 备份+默认；开档可读。
5. **词表口径**（M14）：`game save:` 仅允许出现在损坏腿日志；`no config asset` ×2/run=
   模板良性态归因；`UnresolvedTypes|cannot apply|cannot-apply|scene component|
   without its scene|AudioPlayer` 零容忍（本轮全零）；N13 记数即可（编辑器相日志）。
6. **book 校对锚**：章内断言对照 `crates/jackdaw_runtime/src/save.rs`（envelope/status/
   守卫不变式/目录解析）、`crates/jackdaw_scaffold/templates/game/src/lib.rs.template`
   （GameSave/桥/watcher/attach_volume_sliders）、T1/T2 报告；BRP mutate 不置 dirty 的
   边界表述与 T1 QA 回流 D 一致。
7. **heavy 档提示**：`bsn_game_run`/`editor_journey` 与本轮零共享改动（本轮仅 guards 一
   文件）；`game_ui.rs` 未动且集成实测绿——终验照旧跑 heavy 档即可。

## 六、产物清单

- `book/src/user-guide/game-saves.md`（新章）+ `book/src/SUMMARY.md`（挂目）
- `book/src/user-guide/{audio,game-flow,game-ui}.md`（交叉引用三处；game-ui 含 overlay
  表勘误）
- `tests/guards/game_flow_template.rs`（GameState 副本补 runs_played/unlock_note，
  +8 行——偏差 1）
- `loop/qa/t17-live.sh`（prep 验件 SV9 形态 A 双查——偏差 2）
- `loop/qa/t17t3-gates.sh`（本轮门链脚本）
- 归档：`loop/reports/t17t3_live-*`（26 件）+ `t17t3_{13 门禁/隔离件}.log` +
  `t17t3_gates_progress.log` + `t17t3_integration-first-run-red_red.log`；
  `loop/t17-live/` 原始目录刷新入库
