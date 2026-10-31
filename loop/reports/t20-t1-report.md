# T20-T1 报告：编排 glue 清源轮（决策 1/2 落地 + prep 入库 + 三探针）

> 分支 `loop/t20-example`（自 main 46fdaeb5）；方案 `loop/plans/t20-example-game.md` §四-T1；
> 主控裁定：8 决策点全按建议（决策 1=A 模板扩胜局流转、决策 2=配套音效三行、决策 3=双导出、
> 决策 7=scratch save dir、其余按方案）。日期 2026-11-01（会话日 2026-10-28 方案基线）。

## 一、结论速览

| 项 | 状态 |
|---|---|
| 决策 1-A 落地（EG1 胜局流转） | ✅ collect_pickups 扩 `flow.set(GameFlow::GameOver)`，红绿双证归档 |
| 决策 2-A 落地（胜局音效三行） | ✅ 胜局臂内联 blip 三行（press_sound 同款组件），teaches/头文档同步 |
| 同步面清单核验（T12-T3 纪律） | ✅ 六面逐项过（见 §二），外加漏网面 book 一处（§二.7） |
| teaches 计数 | ✅ 91→92（新测试 `new_game_project_teaches_the_win_transition`） |
| 门禁 fmt/clippy(全仓)/clippy(物理双包)/libtests | ✅ 四门 EXIT=0，日志全文复核零 error/FAILED/Diff（t20t1_gates_fmt_clippy_libtests.log） |
| 门禁 integration + scaffold_e2e 冷编 | （见 §四，跑毕回填） |
| prep 腿 | ✅ 脚本入库+跑通（含两次真实缺陷自咬与修复，见 §五 偏差 1/2） |
| 探针 1（双导出顺序与判据落脚本） | ✅ 落 t20-live.sh 头注释+export_wait（§三.1） |
| 探针 2（M2 七元组定稿） | ✅ 落 t20-live.sh 头注释+seven_tuple 助手（§三.2） |
| 探针 3（PIE 真指针 1600x1000 一拍） | ✅ 真指针可用（(800,911) 命中），M6 主通道定真指针（§三.3） |

## 二、决策 1/2 落地与同步面清单（逐项自查）

改动面（git diff）：`crates/jackdaw_scaffold/src/lib.rs` +61/-2、
`crates/jackdaw_scaffold/templates/game/src/lib.rs.template` +7/-2、
`book/src/user-guide/physics.md` 1 条目、新增 `loop/qa/t20-live.sh`。

新胜局臂（物化形态，见 t20t1_eg1_green_collect_pickups.txt）：`count.0 >= 3` →
`info!("Level clear! …")`（保留）→ blip 三行（`AudioPlayer::<AudioSource>(server.load(BLIP_SOUND))`
+ `PlaybackSettings::DESPAWN` + `SfxBus`）→ `flow.set(GameFlow::GameOver)`。
collect_pickups 新增系统参数 `mut flow: ResMut<NextState<GameFlow>>`、`server: Res<AssetServer>`。

同步面清单（每面独立核验，防 T12-T3 式「三处遗漏」）：

1. **模板函数真身**（`scaffold/src/lib.rs` `module_physics_demo` raw string 内的
   collect_pickups）：✅ 胜局流转+音效三行；doc comment 从「the third one clears the level」
   改为教胜局=与血尽同款流转、Restart 同门。
2. **lib.rs.template 对应函数**：✅ 核验为**无需改函数体**——模板文件无 collect_pickups 副本
   （经 `{{module_physics_demo}}` 占位符在物化时拼接，占位符 :1688 位于 BLIP_SOUND/SfxBus
   定义之后，引用合法）；改的是头文档两句（胜利教学 :80-83、音效教学 :197-199）。
3. **嵌入断言族**（scaffold/src/lib.rs tests）：✅ 两处——
   a. `new_game_project_teaches_the_physics_and_trigger_pattern` 加锚
   `flow.set(GameFlow::GameOver)`（该拼写物化文件中唯一，update_game_over 走 `next.set`、
   on_screen_pressed 只落 Level/Menu，锚定无歧义）；
   b. 新增第 92 测 `new_game_project_teaches_the_win_transition`：钉 `Level clear!` 保留、
   `flow.set(GameFlow::GameOver)`、头文档 `the run is won`、`server.load(BLIP_SOUND)` 恰 2 次
   （press+win，防漂移防增殖）、回流走既有 `"start" | "restart"` 臂。
4. **guards 模板副本**（`tests/guards/`）：✅ 核验为**零副本需同步**——全 27 个 guard 文件无
   collect_pickups/`Level clear` 复制（physics_triggers.rs 自持本地 marker 只测 TriggerEvents
   桥；game_ui.rs 的 PickupCount 为 HUD 绑定本地件）；胜局改动不触及任何 guard。
5. **teaches 计数**：✅ 91→92（`grep -c '#\[test\]' crates/jackdaw_scaffold/src/*.rs` 91 基线；
   libtests 实跑 92 passed 0 failed，归档日志含定向复核行）。
6. **模板头文档两句**：✅ 胜利句（Triggers 条目）+音效句（Game audio 节）。
7. **漏网面（book）**：`book/src/user-guide/physics.md` 拾取条目原文「the third one logs
   "Level clear!"」已因本改动失真——按 T12-T3 同步面纪律做最小修订（一行，非 T3 的扩节）。

## 三、三探针

### 探针 1：决策 3 双导出顺序与判据（落脚本）

- **顺序**：`prep`（净 fixture，无注入）→ **纯包导出先行**（T2 pure 腿 M12/M13）→ `inject`
  （两行 sed 测试缝）→ box/config/pie → **注入包导出**（M11/M14）。纯包必须在 inject 之前
  导出——注入改 Cargo.toml+main.rs，导出 exe 会携带 BRP listener，发货面/测试缝分离即此。
  L1 的「remote 注入」据此拆为 `prep`/`inject` 两个独立相位（方案 L1 元素不减，顺序约束
  来自决策 3-A，脚本头注释落档）。
- **判据**（export_wait 助手）：started_at 必须越过 pre-call 面（防上一次导出的树把 SHA 判据
  预满足——t19 M10 教训）且 state 回 "ready"；其后 staged scene.bsn SHA==工程（调用方判）；
  纯包额外**搬出工程树**（cp 到 loop/t20-live/t20-game-pure）再跑 env -i（隔离断言读
  cargo/编辑器不可达的树）。
- 注入幂等（已注入则跳过 sed）；prep 尾部断言 fixture **无** jackdaw_remote 依赖
  （发货面无缝纪律，防顺序倒置）。

### 探针 2：M2 七元组定稿

七字段×通道×期望值（脚本头注释+`seven_tuple <tag>` 助手，M2 三循环每环 before/after 对读；
M5 的 kill -9 复验第七字段）：

| # | 字段 | 通道 | 期望（Restart 后） |
|---|---|---|---|
| 1 | 血量 | gcomp PlayerHealth | current==max==config 100.0（默认） |
| 2 | 拾取计数 | gcomp PickupCount | 0 |
| 3 | 玩家位置 | gcomp Transform | PLAYER_SPAWN (-2,1,0) |
| 4 | 拾取物数 | world.query With<Pickup> 计数 | 3（重生） |
| 5 | MenuBgm | gsound（SoundLive 镜像） | Menu 态在场；Level 态消失（「停」=DespawnOnExit） |
| 6 | Ambient | gsound_wait | Level 态在场 spatial（「起」） |
| 7 | Runs | GameState.runs_played 镜像 | 累加；kill -9 重启保持（save.json） |

### 探针 3：PIE 真指针 1600x1000 可用性一拍 ✅

**判定：真指针主通道可用**（PROBE_PIE_POINTER=PASS，2026-11-01 02:2x，console-probe.log 在案）。

- 方法：`t20-live.sh probe` 相位（t16 L4 形态）——编辑器带 `JACKDAW_WINDOW_SIZE=1600x1000`
  boot→open menu.bsn→`pie.play_current`→`pie.play_input_toggle` 开捕获→800±120 ×
  831-911 波段扫→15702 读流转。
- 结果：**(800,911) 单点命中**——Start 按钮响应真指针，MenuBgm 消失/Ambient 出现
  （SoundLive 镜像经 15702 读到=流转确认）。与 t16 L4 的工作几何一致（底挂 Game 面板
  中线带）；frame_rect 的 ui_tree 探针给空（<none>），波段扫兜住了——**M6 主通道=真指针，
  判据点建议直接用 t16 L4 的 (800, 831-911) 波段，ui_tree rect 读数不可依赖**。
- N13 记数：8 条 panic 全落已知 `jackdaw::pie::drain_game_events`/
  `cleanup_session_on_stop` 家族（N13，Mac 100% 复发，pie.stop 时段；错误处理器捕获、
  编辑器存活）——归因入账，非新缺陷。
- A10 暴露面预判结论：固定窗下未复现「指针缩放布局不达」；trigger_event 降级链保留为
  记录在案的回落（决策 4-A），M6 以真指针为主判。

## 四、门禁

| 门 | 命令 | 结果 |
|---|---|---|
| fmt | `cargo fmt --all -- --check` | EXIT=0，零 Diff（归档 :2） |
| clippy 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | EXIT=0（归档 :67） |
| clippy 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | EXIT=0（归档 :116） |
| libtests | `cargo test --workspace --lib` | EXIT=0 全 0 failed；scaffold 定向复核 **92 passed**（91+1 达标，归档尾部） |
| integration | `cargo nextest run --profile ci --workspace --features dylib --tests -E 'not (…10 excluded…)'` | ✅ EXIT=0，**5459 run: 5459 passed, 0 skipped**（t19 基线 5458+本任务新测试；1 flaky=`prefab_lifecycle::prefab_file_change_triggers_reload` 重试 2/3 过——A6 家族 watcher flaky 已知形态，与本改动无涉） |
| scaffold_e2e 冷编 | `cargo nextest run --profile ci -E 'binary(scaffold_e2e)'` | ✅ EXIT=0，1 passed（145.9s）——**模板改动物化+冷编成 exe+schema 断言全过** |

日志全文复核按 README 证据标准执行（error/FAILED/Diff-after-reformat 零命中）。

## 五、偏差与如实记录

1. **脚本自咬（已修，prep 腿证据）**：prep 收尾 log 字符串误用反引号（`` run `inject` ``
   ）——bash 命令替换把 inject 函数真执行了，fixture 被提前注入，破坏决策 3 的
   「纯包先行」前提。修复：去反引号（连带修复 379 行同类隐患：预检失败消息会把 needle
   当命令执行）；重跑 prep 恢复净 fixture。教训入脚本注释头（无）——如实记于此。
2. **门禁换味二进制（环境交互，已加守卫）**：integration 门带 `--features dylib`，把
   `target/debug/jd` 重链为动态 libstd 形态（编辑器同款，需 DYLD 前缀），prep 的 jd new
   随即 dyld 崩（Abort trap 6，日志在案）。处置：prep 头加 jd 执行性守卫（失败即提示
   `cargo build -p jd` 重建静态味）；门禁跑毕重建静态 jd 后重跑 prep。**给 QA 的纪律**：
   dylib 门之后跑任何 live 腿前，先确认 jd/编辑器二进制风味，或先 `cargo build -p jd`。
3. **决策 2「三行」的实现形态**：胜局 blip 落为**内联三行 spawn**（press_sound 同款
   AudioPlayer/PlaybackSettings/SfxBus 三组件），未调用现成 `press_sound()` 函数（一行）。
   取字面合规（裁决原文「三行」）+ demo 段自足教学（「Everything a game needs to copy」）；
   代价 = 与 press_sound 五行重复，teaches 测试以 `server.load(BLIP_SOUND)`==2 锚定这对
   孪生，增殖/漂移即红。
4. **EG1 红证形态**：静态物化红证（预改模板 jd new 出的工程中，胜局臂无任何 flow 写点、
   全文件 GameOver 写点唯一在血尽臂）——**真机红证（集齐三枚停留 Level 的实况）不在 T1**，
   按方案由 T2 L3 真机腿落地（M3 判定本尊）；1-A 已裁，红证为修复对照存档非 1-B 预备。
5. **未做**：M16 画面对照（决策 6-B 裁不做）；EG2-EG6 零产品改动；buglist/台账/roadmap
   未动（T3 处置面）。

## 六、给 QA（T2）的注意事项

1. **相位顺序铁律**：`prep`（净）→ pure 腿 → `inject` → box/config/pie/export。inject 之后的
   任何导出都是注入包；pure 腿漏跑就只能重 `prep`（脚本 destructive：rm -rf + jd new）。
2. **门禁与 live 不同窗**（T12-T3 纪律）：dylib 门会换 jd/编辑器二进制味——live 前跑
   `cargo build -p jd`；prep 已带自诊断守卫，报 PREP_FAIL 时按提示重建即可。
3. 胜局真机判定（M3）：集齐三枚→`flow.set(GameFlow::GameOver)`→GameOverRoot 出现+Runs+1；
   Restart→七元组复位（探针 2 表）。stdout 日志断言走 direct run（A5 绕 pie_log），
   `Level clear!` 行保留可作辅证。
4. blip 三行在胜局臂：sfx 计数采样窗按 t16 M3-direct 形态（0.12s sink，40×0.08s 采样）。
5. N13/warn 扫描/截图五招/RUST_BACKTRACE 禁令/df 门前清盘照方案 §0 事实十五执行。
