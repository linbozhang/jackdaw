# T20-T1 QA 报告：编排 glue 清源轮验收

> QA 独立验收（2026-11-01）。对象：分支 `loop/t20-example` @ **0edf9536**、报告
> `loop/reports/t20-t1-report.md`、归档 `loop/reports/t20t1_*`。验收方式=只读源码复核 +
> 门禁/prep/inject/probe 全部**亲跑**（integration+scaffold_e2e 按指示采信归档抽核）。
> QA 归档 `loop/reports/t20t1_qa/`（门禁日志 7 件 + 亲跑 console 6 件）。全程未设
> RUST_BACKTRACE；loop markdown 只用 Read/Edit/Write；产品代码/buglist/台账未动。

## 一、裁决

## **PASS —— 放行 T20-T2**

T1 三条验收标准（方案 §四-T1）全部达成且证据可复溯：①门禁全绿（五门亲跑 EXIT=0 +
integration 归档抽核吻合）；②prep 腿绿（亲跑 PREP_OK，净 fixture 三证齐）；③探针三定案
在案（两条落脚本+一条**QA 独立复现同点命中**）。EG1 修复源码级复核属实、同步面 7/7 落实、
红绿证据与源码逐字一致、5 条偏差全部可接受（其中偏差 2 处方需按 QA-E4 扩展）。

## 二、门禁表（QA 亲跑，2026-11-01 03:36-03:43）

| 门 | 命令 | 亲跑结果 | 证据 |
|---|---|---|---|
| fmt | `cargo fmt --all -- --check` | **EXIT=0**，零输出零 Diff | t20t1_qa/fmt.log |
| clippy 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **EXIT=0**，零 warning（全文扫） | t20t1_qa/clippy_ws.log |
| clippy 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **EXIT=0**，零 warning | t20t1_qa/clippy_phys.log |
| libtests | `cargo test --workspace --lib` | **EXIT=0** 全 0 failed；scaffold **92 passed**（69→70 lib.rs，恰一新测） | t20t1_qa/libtests.log |
| xtask fast | `cargo xtask fast` | **EXIT=0**，**3002 passed 0 skipped = 3001+1 达标** | t20t1_qa/xtask.log |
| integration | `nextest --profile ci --workspace --features dylib --tests` | **采信归档抽核**：5459 run / 5459 passed / 0 skipped；1 flaky=`prefab_file_change_triggers_reload` 重试 2/3 过（A6 watcher 家族已知形态）；摘要/EXIT/FLAKY/scaffold_e2e 四点核，尾段扫零 error | t20t1_gates_integration_scaffold_e2e.log |
| scaffold_e2e 冷编 | `nextest -E 'binary(scaffold_e2e)'` | **采信归档**：1 passed（145.9s）——模板改动轮物化+冷编+schema 断言过 | 同上 |

计数三源互证：恰一个新测试（`git diff` 69→70 唯一 `fn new_game_project_teaches_the_win_transition`）
同时出现在 libtests 92（91+1）、xtask fast 3002（3001+1）、integration 5459（5458+1）——与
报告口径逐位吻合。注：integration 归档为 46 行尾段摘录，按本轮 QA 指示走采信抽核口径
（QA 自己的五门为全文亲跑）。

## 三、EG1 修复源码级复核（全部属实）

**胜局臂亲读**（`crates/jackdaw_scaffold/src/lib.rs:3172-3206`，模板域唯一真身）：
`count.0 >= 3` → `info!("Level clear! …")` **保留** → blip 三行（`AudioPlayer::<AudioSource>(
server.load(BLIP_SOUND))` + `PlaybackSettings::DESPAWN` + `SfxBus`，:3199-3203，press_sound
同款三组件=T16 音频基线形态）→ `flow.set(GameFlow::GameOver)`（:3204）；新系统参数
`mut flow: ResMut<NextState<GameFlow>>` + `server: Res<AssetServer>`（:3176,:3178）。

**写点唯一性（锚定无歧义判定）属实**：物化文件中 `flow.set(GameFlow::GameOver)` 唯一——
血尽臂 `update_game_over` 走 `next.set`（lib.rs.template:1687）、`on_screen_pressed` 只落
Level/Menu（:1578,:1582）。嵌入断言锚 :3858 及其注释对此的说明与源码一致。

**同步面 7 项逐项核**：

| # | 面 | 判定 | QA 核验方式 |
|---|---|---|---|
| 1 | 模板函数真身 | ✅ | scaffold:3172-3206 亲读（上） |
| 2 | lib.rs.template 无需改函数体 | ✅ **判定属实** | 模板内 `collect_pickups`/`Level clear` 仅 3 处头文档 `//!` 提及（:76,:97,:197），**无函数副本**；物化经 `{{module_physics_demo}}` 占位符（:1693）在物化时由 `module_physics_demo()` 输出拼接（scaffold:2607-2611 `replace_line`）——真身只此一份；占位符位于 BLIP_SOUND（:1593）/SfxBus（:563）定义之后，引用合法 |
| 3 | 嵌入断言族 | ✅ | 既有测加锚 `flow.set(GameFlow::GameOver)`（:3858）+ **第 92 测** :3915-3947 亲读：钉 `Level clear!` 保留、`flow.set` 拼写、头文档 `the run is won`、`server.load(BLIP_SOUND)==2`（press+win 孪生防漂移防增殖）、回流走既有 `"start" | "restart"` 臂 |
| 4 | guards 零副本 | ✅ **判定属实** | 真路径=仓库根 `tests/guards/`（29 个 .rs）；`collect_pickups`/`Level clear` **零命中**；GameOver 命中 3 文件全为 guard 本地 fixture（game_ui.rs 本地枚举+血尽 HUD 局、game_flow*.rs 的 GameOverRoot/gameover.bsn 映射守卫），与胜局臂无涉——无同步面 |
| 5 | teaches 计数 | ✅ | 91 基线（46fdaeb5）→ 92（git show 逐 commit 计数）+ 亲跑 92 passed |
| 6 | 模板头文档两句 | ✅ | 模板 diff：胜利句（:80-83，「the run is won…Restart starts the next one」）+音效句（:197-199，「blip pulls double duty as the win's fanfare…sfx bus…before the flow moves」） |
| 7 | physics.md:225 旧行为修订 | ✅ | book diff 单条目：「the third one logs "Level clear!"」→「wins the run: the flow moves to the game-over screen (with a blip), where Restart starts the next one」——最小修订非扩节，符合 T12-T3 纪律 |

## 四、红绿复核

- **红证**（t20t1_eg1_red*.txt）：预改模板物化，collect_pickups 胜局臂只有 info!（0 flow
  写点），全文件 GameOver 写点唯一在血尽臂（`next.set`），`flow.set` 只落 Level/Menu，
  附静态语义注（拾取物 DespawnOnExit(Level)，GameOver 态不可再触发）——**与 46fdaeb5
  基线源码逐字吻合，红证成立**。
- **绿证**（t20t1_eg1_green*.txt）：物化胜局臂 = info!+blip 三行+`flow.set`，四锚命中数
  （1/1/2/2）——**与 0edf9536 源码及 QA 的 prep 物化 fixture 亲读三方一致**（QA 亲跑 prep
  后 fixture src/lib.rs :1971 info! / :1980 flow.set / :80 头文档，独立再证）。
- **真机红绿归 T2 L3 口径**：属实且与方案一致——方案 T1.4 的红证预备是 1-B 案条件项，
  主控裁了 1-A，静态物化红证转为修复对照存档；真机胜局实况归 T2 L3/M3 判定本尊。

## 五、prep/inject 腿 QA 亲跑 + 脚本自咬修复核

| 腿 | 结果 | QA 证据 |
|---|---|---|
| prep | **PREP_OK**（暖编 2m06s，451 行冷编全文过） | t20t1_qa/my_console_prep.log、my_warmbuild_prep.log |
| inject | **INJECT_OK**；**幂等性亲证**（二跑打印 `already present, skipping the sed`） | t20t1_qa/my_console_inject.log、my_warmbuild_inject.log |

prep 三证亲验：净 fixture（Cargo.toml `jackdaw_remote` **0 命中**=发货面无缝）；胜局臂物化
在位（:1971/:1980/:80）；flow start_scene=menu.bsn+3 场景+三 wav+模板完整性预检 needle 族
（含 `flow.set(GameFlow::GameOver)` 与 hud.bsn 滑条行回退）。inject 两行落位亲验：
Cargo.toml :26 dep + main.rs :37 plugin，lockfix+cargo metadata 刷新+暖编过。

**自咬修复核（属实）**：全文反引号扫描——可执行代码**零反引号**，余 5 处全在 `#` 注释行
（:22,:30,:31,:33,:383）；原 prep 收尾 log 的 `` run `inject` `` 命令替换已去反引号（现
:410 纯文本），379 行同类隐患（预检失败消息把 needle 当命令执行）同修（现 :388 纯文本）。
修复完整，无残留同类。

**QA 亲跑新增发现（QA-E4，见 §七）**：probe 相位首跑 **EDITOR_BOOT_FAIL**——
`target/debug/jackdaw` 处于 integration 门（`--features dylib`）后的动态味且与盘上
`libjackdaw_dylib.dylib` 陈旧失配（dyld Symbol not found，t20t1_qa/my_console_probe.log
前身）。`cargo build -p jackdaw` 重建静态味后同相位 PASS。**报告偏差 2 的处方只写了
`cargo build -p jd`，漏了编辑器二进制**——环境交互面比报告记的多一个，处置见 §七。

## 六、三探针结论核

1. **双导出顺序与判据**：落脚本属实——头注释 :28-42 编码「纯包先行（prep 净 fixture 上、
   inject 之前）→inject→注入包」；`export_wait`（:310-331）=t19-live.sh:280-293 逐字先例
   （T19 三站已验）：started_at 越过 pre-call 面+state 回 ready（防上一次导出树预满足 SHA
   判据），staged SHA 调用方判；纯包 `cp -R` 搬出工程树（PURE_DIST）；prep 尾部无 remote
   断言防顺序倒置。**判据成立**。
2. **M2 七元组**：脚本 :44-56 头注释+`seven_tuple` 助手（:332-347），七字段=血量/计数/位置/
   拾取物数/MenuBgm/Ambient/Runs，通道（gcomp/gcomp/gcomp/world.query/gsound/gsound_wait/
   get_resources）与期望值（100.0/0/(-2,1,0)/3/Menu 在 Level 消失/Level 在 spatial/累加+
   kill -9 保持）与报告表逐字段一致。**定稿成立**。
3. **PIE 真指针 1600x1000**：归档（console-probe.log：PROBE_PIE_POINTER=PASS @ (800,911)，
   frame_rect <none>，N13 8 hits 全 pie drain/cleanup 家族）+ **QA 独立复现**：重建编辑器后
   亲跑 probe 相位，**同点 (800,911) 命中**、frame_rect 同样 <none>、N13 2 hits=1 事件
   （drain_game_events，pie.stop 时段，编辑器存活）。命中判据=15702 读到 Ambient SoundLive
   出现（gsound_wait→gbrp）——**「15702 对 PIE world 可读」由此亲证**。两轮同点=结论稳固。
   附注：波段扫全程 ~8 分钟（A9 gbrp 重试+命中点在扫序末位 dy=911），T2 M6 应先打已知好点。

## 七、偏差 5 条裁定建议 + 勘误

| # | 偏差（报告 §五） | QA 裁定建议 |
|---|---|---|
| 1 | 脚本自咬（backtick 命令替换提前执行 inject） | **接受**。修复亲核完整（§五）；可再补一行 log() 助手注释「禁反引号」防复发（T2 顺手，非阻塞） |
| 2 | dylib 门换味二进制 | **接受+处方扩展**：波及面含编辑器二进制（QA-E4 实证），T2 live 前跑 `cargo build -p jackdaw -p jd`，或给 editor_boot 加 prep 同款执行性守卫（小改，建议 T2 首日带） |
| 3 | 决策 2「三行」落为内联 spawn（未调 press_sound） | **接受现状**。裁决原文即「三行」，内联形态教组件三件套（demo 自足）；重复代价已被 teaches `server.load(BLIP_SOUND)==2` 锚钉住。改一行调用属无验收价值的 churn，不建议 |
| 4 | EG1 红证为静态物化（真机红绿归 T2 L3） | **接受**。与方案 T1.4 条件项+M3 设计一致（§四） |
| 5 | 未做面（M16/EG2-EG6/buglist 台账 roadmap） | **接受**。全部与方案决策 6-B 及 T3 处置面吻合 |

**勘误（⚪，不改判）**：
- E1：报告 §二.2 占位符行号 :1688 → 实为 **:1693**（同 commit 头文档 +5 行所致漂移；判定本身属实）。
- E2：报告 §二.4「全 27 个 guard 文件」→ `tests/guards/` 实有 **29 个 .rs**（28 守卫+main.rs
  汇总口）；零副本判定经真路径复扫属实。QA 首扫曾误打不存在的 `crates/jackdaw_scaffold/
  tests/guards/` 空路径得假零命中——已在本报告 §三.4 以真路径重核更正（QA 自查记录）。
- E3：报告 §三.3「N13 记数 8 条」=8 个 grep 命中=**4 个事件**（drain ×2+cleanup ×1+despawn
  Command ×1），与 T13 grep 口径同约定；建议 T2 归因时按事件注明（QA 复现轮 2 hits=1 事件）。

## 八、给 T20-T2 的放行建议

1. **双导出预算 ~50min 单列**（export_wait 上限 1500s×2）；门前 df 清盘、导出后查 `.jackdaw`
   与 scaffold_e2e 临时残留（A6 纪律）。
2. **相位铁律交接**：`prep`（净）→ pure 腿（M12/M13）→ `inject` → box/config/pie → export。
   inject 之后的任何导出都是注入包；pure 漏跑只能重 prep（脚本 destructive：rm -rf+jd new）。
   **当前 fixture 为 QA inject 亲跑后的注入态，T2 开工直接以 prep 相位重置即可。**
3. **live 前二进制味守卫**（QA-E4 扩展处方）：dylib 门之后先 `cargo build -p jackdaw -p jd`
   再跑任何 live 腿；prep 已带 jd 守卫，编辑器味守卫建议 T2 首日补（偏差 2 处置）。
4. **M6 主通道=真指针**：两轮独立同点 (800,911)；判据用 t16 L4 几何 (800, 831-911) 波段，
   **ui_tree rect 读数不可依赖**（两轮均 <none>）；建议先打已知好点再扫（全扫 ~8min）。
   trigger_event 降级链保留为记录在案回落；固定 1600x1000 窗不得省。
5. **M3 胜局判定**：集齐三枚→GameOverRoot 出现+Runs+1（`flow.set` 已物化）；stdout 日志断言
   走 direct run（A5 绕 pie_log），`Level clear!` 行辅证；blip 三行在胜局臂，sfx 采样窗按
   t16 M3-direct 形态（0.12s sink，40×0.08s 采样）。
6. N13/warn 扫描/截图五招/RUST_BACKTRACE 禁令照方案 §0 事实十五；N13 建议按事件归因（E3）。

## 九、QA 归档清单（loop/reports/t20t1_qa/）

门禁：fmt.log、clippy_ws.log、clippy_phys.log、libtests.log、xtask.log、gates_exit.log
（五门退出码）、gates_main.log（首跑全文）。亲跑：my_console_prep.log、my_console_inject.log、
my_console_probe.log、my_editor_probe.log、my_jd_new.log、my_lockfix.log、
my_warmbuild_prep.log、my_warmbuild_inject.log、qa_prep_console.log。
（loop/t20-live/ 的程序已提交证据经 git restore 保持原状；QA 亲跑副本全在本目录。）
