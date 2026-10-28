# T12-T2 实施报告：绑定错误可见 + 真机交互链

> 任务：`loop/plans/t12-game-ui.md` §二-T2（241-280 行）；§0 架构事实作地基。分支
> `loop/t12-game-ui`（自 main 7ab807ca 续做，已并 main）。真机证据 `loop/t12t2-live/`
> （24 件），脚本 `loop/qa/t12t2-*.sh`（6 件），门禁归档 `loop/reports/t12t2_*.log`。
> 暖工程 `/Users/zhanglinbo/workspace/loop-mac/t12t1-game/t12t1-game` 复用（T1 遗产）。
> （勘误 2026-10-28 主控，QA t12-t2-qa.md 回流①：证据/脚本计数以 QA 亲数为准 24/6；
> 日志条行数两处 8→4，见 :14/:76。）

## 〇、执行摘要

**PIE 日志通道（决策 4-A）成立并落地**——`LogPlugin::custom_layer` 探针一次通过（fork
`bevy_log/src/lib.rs:236` 钩子、:323 与既有 subscriber 组合，零双订阅；EnvFilter 在
custom layer 之后叠加，转发只见到过了滤的事件），未回落 4-B。runtime 侧转发层
（`crates/jackdaw_runtime/src/pie_log.rs`，tracing Layer→mpsc→`StateEvent::Log` Reliable，
去重+每秒上限节流）+ 编辑器侧 `PieGameLog`（上限 100）+ Game 面板日志条（4 行，W13 三档
色）。**真机十腿 + 分辨率两档 + direct/导出 parity + Stop 铁证 + 编辑器往返全 PASS**
（归档齐全）。**真机腿抓出三处 T1 潜伏模板缺陷并已修**（spawn 序竞态/暂停双注册/开局
game_over 竞态——guards 与 teaches 都看不见它们，只有真机能踩出来）。

## 一、主控移交两项

### 1. hud.bsn 编辑器往返零 diff 实测（QA 升权项）——判：序列化器规范化（可接受），种子已回写

`loop/qa/t12t2-roundtrip.sh`：编辑器打开暖工程 hud.bsn（2D 画布）→不动任何东西→
`scene.save`→SHA 对比。**首轮实测确有 diff**（`t12t2-roundtrip-after.bsn` 归档），逐行
判定：

| diff | 判定 |
|---|---|
| 8 行教学头注释 → 编辑器标准头 `// jackdaw 0.21.0-dev \| bevy main` | 规范化（保存重生成头注释；任何用户保存都会发生） |
| `Bindings([...])` 多行数组 → 单行（9 处） | 规范化（纯格式） |
| `Progress { value: 1.0 }` → 字段逐行 | 规范化（纯格式） |
| `#HealthFill` 的 `width: Percent(100.0)` 被剥掉 | **规范化的故意行为**：`src/scene_io/save.rs:973` `normalize_runtime_derived_values` 明文把「widget 自己推导的值」（progress fill 的宽度、separator 长轴、nine-patch 模式）从文档里拿掉——`progress_fill_follows_value` 每帧从 `Progress.value` 重写该宽度（runtime/widgets `lib.rs:992`），authored 值本就是死重 |
| 语义面：绑定/数值/遮罩色（`bevy_color::srgba::Srgba` 两处）/结构 | **零漂移**（T1 QA 修的规范 Srgba 路径在编辑器保存后原样幸存） |

按主控预授权口径（规范化 → 记档+把规范化形态写回种子消除漂移）：**模板
`hud.bsn.template` 与暖工程 `assets/hud.bsn` 均回写为编辑器保存形态**（模板保住
`{{crate_name}}`/`{{project-name}}` 占位；教学头注释的内容本就住在 lib.rs.template 的
Game UI 导览段，不受损）。回写后 scaffold teaches **87/87**、guards game_ui **7/7** 复跑
全绿；复验往返 **PASS（字节级零 diff，`hud document confirmed open` 后保存）**
（`t12t2-roundtrip-console.log`）。

脚本加固记档：首轮曾在「打开未完成」时保存，得到半载世界的畸形文件——已改为
`jackdaw/scene_bsn` 确认 HudRoot 在前才保存（该轮归档留作反例）。

### 2. PIE 日志通道落地后的 warn 面真机化

真机④红腿即此验证：暖工程 hud.bsn 施 typo（`PlayerHealth.currrent`）→ Play → **Game
面板日志条出现一条 warn**，原文归档：

```
jackdaw_bind::evaluate: binding 0 on 722v0: path 'currrent' on 't12t1_game::PlayerHealth': Error accessing element with `.currrent` access(offset 8): The struct accessed doesn't have a `currrent` field
```

修正 hud.bsn → 重开 PIE → 该 warn 消失（C4_GREEN）。T1 QA §十-2 的诉求（「同类第四处
bug 不再依赖 QA 探针才能发现」）已闭环。

## 二、PIE 日志通道（决策 4-A）

**探针结论：4-A 成立**（源码实读 + 产品测试 + 真机三重证）。改动面：

1. **runtime `crates/jackdaw_runtime/src/pie_log.rs`（新，pie feature 内）**：
   - `pie_log_relayer`＝`LogPlugin::custom_layer` 钩子（fn 指针形态）：建 mpsc
     channel、Receiver 以 `PieLogRelay` 资源入 world、返回 `RelayLayer`；
   - `RelayLayer: Layer<Registry>`：DEBUG/TRACE 留本地（`Level` 按 verbosity 排序，
     大于 INFO 才拦），info/warn/error 全收；消息=target+message+结构化字段尾随
     （`FieldReader` visitor）；level 归一为小写；
   - `forward_pie_logs`（attach_pie 装，Update）：排空 relay（每帧至多 512，溢出丢弃并
     以一条 warn 明报）→ `PieLogForwarder::admit` 节流（同 (level,message) 1s 去重 +
     每秒 32 条上限，窗口滚动复位）→ `StateEvent::Log` 走 **Reliable** lane；
   - 钩子挂载点：`maybe_windowless` 在 `JACKDAW_PIE` 在场时
     `.set(LogPlugin { custom_layer, ..default() })`——非 PIE 启动的游戏 plugin group
     分毫未动。
2. **编辑器**：`src/pie_game_log.rs`（新）＝`PieGameLog` 资源（VecDeque 上限 100，旧行
   滚出；`GameLogEntry::color()` 走 W13 三档：error→`TEXT_ERROR`、warn→`TEXT_WARNING`、
   info→`TEXT_SECONDARY`）；`src/pie.rs drain_game_events` 增 `StateEvent::Log` 分支
   （聚焦实例才入账）；`src/game_panel.rs` 面板底部日志条（4 行，新条目沉底，warn 警告
   色/error 错误色/info 次要色，无日志时整条隐藏）。
3. **测试（产品侧代码全带测试）**：runtime pie_log 4 件（layer 层级过滤/结构化字段/
   节流去重+上限+窗口滚动/溢出保新+明报）——注意 pie 模块单包运行需
   `--features pie,bevy/bevy_winit,bevy/bevy_gizmos,bevy/custom_cursor`（与游戏构建的
   特性统一同形态；**pre-existing**：干净 main 上 `-p jackdaw_runtime --features pie`
   本就编不过——workspace 门不编译 pie 模块）；编辑器 pie_game_log 2 件 + game_panel
   日志条同步系统 1 件（行序/滚出/三档色）。
4. **不改 BindFailures 读取面**（YAGNI，主控已裁）：绑定失败以日志行为准。

## 三、坏绑定红绿（真机③ + headless guard）

- **真机红**：typo → 日志条 warn 可见（§一-2 引文，`t12t2-pie-console.log` C4_RED）；
- **真机绿**：修正 → 重开 PIE → 面板无该 warn（C4_GREEN）；
- **headless guard**（`tests/guards/game_ui.rs`
  `a_typoed_field_fails_loudly_and_a_fix_lands_quietly`，field_bindings.rs 先例形态）：
  typo 绑定 → `BindFailures` 非空 + Progress 保持 authored 1.0；同 binding 修正字段名 →
  下一帧 ratio 0.87 落位 + 台账清零。guards 全量 **229/229**（228+1）。

## 四、真机四链（PIE，bash+curl+jq，`t12t2-pie-chains.sh`，7 轮迭代后十腿全 PASS）

最终轮（`t12t2-pie-summary.txt` / `t12t2-pie-console.log`）：

| 腿 | 结果 | 关键证据 |
|---|---|---|
| C1_START_BUTTON | PASS | capture on→`input.pointer` 真 click（窗逻辑 px (700,787)）→转发 CursorMoved+MouseButton→游戏 picking→Start 按钮→`GameState.menu` false（游戏 BRP 15702 读回）；Hud 屏 shown（`Inherited`＝Visible 绑定的「显示」写形）、StartScreen=Hidden。**真 picking 点击链，非 log 占位** |
| C2_BAR_DAMAGE | PASS | 位置反馈转向（真 KeyboardInput 键）把玩家走到 hazard 列（steered to 1.76,0.40）→穿越即扣血 **100→70**（两次 15 触发）→`Progress.value`=0.699999988079071（=70/100 精确）+`HealthText`="70 / 100" 双通道同步 |
| C2_BLOODOUT_GAMEOVER | PASS | 血尽（组件 bottom-out，标注降级通道）→`game_over`=true→GameOverScreen shown |
| C3_RESTART_RESET | PASS | 结束屏 shown→Restart 按钮 sweep 点击→`game_over` 清、**血回满 100**、结束屏 Hidden |
| C3_PAUSE_RESUME | PASS | Escape（游戏 BRP KeyboardInput 事件，T09 通道）→`paused`=true+暂停屏 shown；Resume 按钮点击→`paused`=false——**双路一致** |
| C4_RED / C4_GREEN | PASS / PASS | §一-2 |
| C5_U5_UI_ONLY | PASS | hud.bsn 前置→Play→UI-only 世界：Brush 实体=0、HudRoot≥1（=2：覆盖根+spawn_hud 第二根——预览语义的双 hud 记档） |

辅助证据：编辑器窗口截图（`t12t2-probe-window.png`，日志条三档色肉眼可见——两条橙黄
warn+白 info）。

**真机腿抓出并修复三处 T1 潜伏模板缺陷**（全部只有真机能踩出来；guards 移植单注册/
headless 时序与真机不同，headless 全绿）：

1. 🔴→已修 **spawn 序竞态**：`(spawn_scene, spawn_hud)` 元组**不链序**（T1 报告 §六-7
   自己记录过元组语义），`apply_pie_scene_override` 换「最低实体索引的根」——hud 根抢到
   低位时被整体换成 scene.bsn：**PIE 无 UI 且主场景双载**（真机截图为证：流帧里只有 3D
   世界；日志行「playing 'scene.bsn' in place of 'hud.bsn'」）。修：`(spawn_scene,
   spawn_hud).chain()` + 注释钉死原因 + teaches 针（`(spawn_scene, spawn_hud).chain()`）。
2. 🔴→已修 **暂停双注册**：T1 rework 给 `handle_pause_action` 加 `.before(move_player)`
   边时**没从原 Update 元组摘除**——同系统注册两次，Escape 每按一次翻转两次=净零，**发布
   形态的 Escape 暂停完全失效**（direct 真机实测：Escape 后 `paused` 恒 false；同键
   Interact 的 `just_pressed` 正常触发，证明注入链无辜）。修：元组摘除，仅保留带边注册；
   teaches 针钉 `add_systems(Update, handle_pause_action.before(move_player))`；修后
   direct 实测 Escape false→true→false。
3. 🟡→已修 **开局 game_over 竞态**：玩家组件以 0/0 出生，`update_game_over`（≤0 即
   true，只置不清）若先于 `apply_health_from_config` 跑，**开局直接 game_over**
   （direct/PIE 各实锤一次， boot state=`true,false,true`）。修：
   `(apply_health_from_config, update_game_over).chain()` + teaches 针；修后 direct boot
   state=`{game_over:false,menu:true,paused:false}`。

三处均带 teaches 永久针，scaffold 87/87 每次改后复跑绿。

## 五、真机⑤b：分辨率两档 + 四通道一致 + Stop 铁证

| 腿 | 结果 | 证据 |
|---|---|---|
| 分辨率两档 | PASS | `t12t2-resolution-console.log`：两档流尺寸 **1920x151 与 1920x170**（Game 面板停靠为底部条带→流=面板像素尺寸；**通道记档：条带形而非 16:9 档**，16:9 四档数学断言归 T1 guards）。两档同断言全中：游戏虚拟 Window 报告的流尺寸=StartScreen(overlay) 计算盒（1920x151/1920x170 精确充满）、**HealthBar 180x10 两档恒定**、StartButton 84x24 两档在场。窗口截图归档 `t12t2-res-{A,B}.png` |
| direct parity | PASS | `t12t2-parity-DIRECT-console.log`：boot state 干净（chain 修后）；menu=false→Hud shown+Start 隐；health 组件写 60→`Progress.value` 0.6+文本 "60 / 100"；paused/game_over→对应屏 shown——**与 PIE 同行为**。通道差异记档：Mac 无 OS 级点击注入等价物（T11 口径），direct 腿走数据面+键事件，picking 点击链由 PIE 腿独证 |
| 导出 parity | PASS | `game.export`→staged `.jackdaw/dist/release/`（release，exe 210MB+assets+export manifest）→**staged exe 独立启动**→同 parity 集 PASS（`t12t2-parity-EXPORT-console.log`）——四通道（编辑器/PIE/direct/导出）一致 |
| Stop 铁证 | PASS | `t12t2-stop-console.log`：PIE 求值中→Stop→`scene.bsn`+`hud.bsn` SHA256 双不变 |

四通道一致（t11t3 格 10 形态）成立：编辑器（画布/往返）=PIE（点击/血条/四屏）=direct
15702（parity 集）=导出 staged（parity 集）。

## 六、U5 记档（UI tab 聚焦 Play）

实测（C5 腿）：UI 场景 tab 聚焦时 Play，`JACKDAW_PIE_SCENE` 覆盖**第一个根**→世界=
「UI-only 预览」：scene.bsn 的 Brush 实体 0、Hud 文档在场；玩家/相机链（代码侧）仍在但
教学语义是「预览这张画布」。附带记档：覆盖根+`spawn_hud` 第二根并存时 HudRoot=2（同一
文档两实例）——预览形态的边界，无功能腿受损。doc/教学注记已在 T1 落于模板 Game UI
导览段（U5 边角），本轮补真机证据。

## 七、门禁（日志全文复核；归档 `loop/reports/t12t2_gates_final.log` 等）

| 门 | 结果 | 归档 |
|---|---|---|
| `cargo fmt --all -- --check` | CLEAN | `t12t2_gates_final.log` |
| `cargo clippy --workspace --all-targets -- -D warnings` | CLEAN | 同上（首轮 `t12t2_clippy_ws_tail` 记录亦 CLEAN） |
| `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | CLEAN（例行） | 同上 |
| `cargo clippy -p jackdaw_runtime --features pie,bevy/…（pie 形态）--all-targets` | CLEAN | 同左 |
| `cargo test --workspace --lib` | 全绿（scaffold **87/87**） | `t12t2_gate_libtests.log`+final |
| `cargo test -p jackdaw --test guards` | **229/229**（228+1） | final |
| `cargo test -p jackdaw_runtime --tests` | 全绿 | final |
| pie_log 单测（ad-hoc 特性统一形态） | 4/4 | final |
| warn 形态扫描（cannot apply/cannot read/does not read as/UnresolvedTypes） | **全部 t12t2 归档 0 条**（红腿 `currrent` warn 为「path … on …」形，系测试对象本身） | 本节 |

## 八、偏差与记档分级

| 级 | 项 | 处置 |
|---|---|---|
| 🔴→已修 | 三处 T1 潜伏模板缺陷（spawn 序竞态/暂停双注册/开局 game_over 竞态），§四 | 修复+真机复验+teaches 针；**建议 QA 把「模板注册唯一性/链序」列为真机常备检查** |
| ⚪ | `maybe_windowless` 的 LogPlugin `.set` 会覆盖游戏自带 LogPlugin 定制（filter/custom_layer）——仅 PIE 启动受影响，模板游戏用默认值；doc 注释已写明 | 接受（记档） |
| ⚪ | pie 模块单包 check/test 需 ad-hoc bevy 特性（pre-existing：干净 main 同令牌即红，5 错） | 接受（记档+归档命令行） |
| ⚪ | Game 面板停靠为底部条带→PIE 流尺寸为条带形（非 16:9 档）；分辨率真机腿以「两档流尺寸下布局不破」替代，16:9 档位归 T1 headless guards | 接受（通道差异如实标注） |
| ⚪ | 血尽腿在部分轮次以组件 bottom-out 达成（hazard 往返穿越受 rig 跟随下的方向漂移干扰，穿越伤害本身 100→70 为真键真 hazard）；日志全程标注通道 | 接受（诚实标注） |
| ⚪ | 脚本迭代 7 轮（中间轮 console 全留档同文件覆盖，终轮 summary 归档）；首轮往返踩「打开未完成即保存」已加固 | 脚本轮次，非产品 |
| ⚪ | `T02/T03 回归`（绑定卡提交链/undo）：本轮零改 Inspector/undo 面；`Bindings` 组件经编辑器保存往返（=T02 提交链的落盘面）在往返腿覆盖；Stop 铁证（T06）PASS | 记档 |

## 九、测试账本

| 套件 | 数量 | 结果 |
|---|---|---|
| guards game_ui | +1（typo 红绿）→ guards 全量 228→**229** | ok |
| runtime pie_log 单测 | +4 | ok |
| 编辑器 pie_game_log/game_panel 单测 | +3 | ok |
| teaches | +3 针（chain/pause 边/health 链），85→**87** 维持（针增不变数） | ok |

## 十、给 QA 的注意事项

1. **真机手段沉淀**：`loop/qa/t12t2-pie-chains.sh` 的四个可复用件——①`frame_click`
   底部条带流坐标点击（`input.pointer` 窗逻辑 px，(700,787)/(787,772) 一带）；②位置反馈
   转向走 hazard（键盘事件注入+BRP 读位闭环）；③`screen_vis`（**Name 不可 BRP 序列化**
   ——任何带 `bevy_core::name::Name` 的 `world.query` 静默返空；用组件语义选择）；④
   `world.insert_components` 形状为 `{"entity":"..v0","components":{"路径":{…}}}`。
2. **Visible 绑定的「显示」写形是 `Visibility::Inherited`**（不是 `Visible`）——断言
   shown 要收两形。
3. PIE 游戏进程改动后需重启 PIE 才生效；编辑器启动时会后台 pre-build，首跑冷编数分钟。
4. 暖工程 `target/debug/assets/` 需 scene.bsn+hud.bsn 副本（direct run 资产目录惯例，
   脚本已 cp）。
5. 导出腿：`game.export` 后 staged exe 启动需 ~15s 才开 BRP，脚本若以进程名等待注意
   `./t12t1-game` 的 cmdline 形态（`pgrep -f 'dist/release/…'` 不匹配）。

**提交**：见 git log（显式 pathspec：runtime 三文件+新 pie_log.rs、编辑器四文件+新
pie_game_log.rs、scaffold 三文件、guards 一文件、模板两文件；既存噪音 .gitignore/
buglist.md 未触碰）。
