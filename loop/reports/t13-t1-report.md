# T13-T1 实施报告：运行时切换原语 + 无残留机制面

> 任务：`loop/plans/t13-scene-flow.md` §三-T1（S2；决策 2-A，主控裁定 8 点全按建议）。
> 分支 `loop/t13-scene-flow`（自 main e9666d65 拉出）。改动面：`crates/jackdaw_runtime/
> src/lib.rs`（+89/−18：新系统 `respawn_on_scene_root_change` + 机械提取
> `clear_scene_instance` + 去重组件 `SpawnedSceneId` + 拒载 warn 带路径）、新测试
> `crates/jackdaw_runtime/tests/scene_root_change.rs`（4 件）、新 guards
> `tests/guards/game_flow.rs`（5 件）+ `tests/guards/main.rs` 注册一行。
> 模板/scaffold/teaches/book/编辑器零改动（模板演进归 T3）。全程未设 RUST_BACKTRACE。
> 门禁归档 `loop/reports/t13t1_*.log`（11 件，红绿证据在案）。

## 〇、执行摘要

S2 的红→绿闭环完成：**现状对「已加载目标」的 handle 换绑是 no-op**（红证 3+4 件），
新增 `respawn_on_scene_root_change`（Update 链 `clear_modified_scene_roots →
apply_pie_scene_override → respawn_on_scene_root_change → spawn_loaded_scenes →
cleanup_orphaned_scene_members`）消费 `Changed<JackdawSceneRoot>` 且带 `SceneSpawned`
的根，执行与热重载链完全相同的三步（机械提取为私有函数 `clear_scene_instance`，两触发器
并存）；`SpawnedSceneId`（私有组件，随 `SceneSpawned` 同点写入）实现「同 handle 重写不
重启」去抖。绿态：runtime 4/4 + guards 5/5 全绿，runtime 全套 26 个测试二进制（含
pie_scene_override 5/5、ui_scene_ownership 2/2）零 failed，guards 全量 234/234（229+5），
quick 四门 + 物理双包 clippy + bind 测试全 EXIT=0。

**调研期新发现（方案 §0 事实三的补充，已入测试注释与报告）**：现状的换绑并非在所有形态
下都 no-op——「换绑到**尚未加载**的目标」会经 `AssetEvent::LoadedWithDependencies` 意外
重载（`clear_modified_scene_roots` 按根的**当前** handle 匹配事件）。该意外路径恰好解释
S2 的真实危害面：目标已加载（游戏持有句柄/往返回程）时静默 no-op；拒载零反馈；同 handle
重写经 GC 重载会误重载；同帧竞态无单点把关。guards 因此刻意持有句柄（原语的核心场景），
避免骑在意外路径上假绿。

## 一、验收标准逐条（方案 §三-T1）

| # | 验收标准 | 判 | 证据 |
|---|---|---|---|
| 1 | **headless 红→绿①（原语）**：无 runtime 增量时换绑 no-op（红）；有增量后换绑即重载（绿） | **PASS** | 红：`t13t1_runtime_red.log`——`rebinding_a_spawned_root_swaps_the_scene_under_it` FAILED（"the rebound scene spawns: ["Anchor", "scene"]"，预加载目标后换绑，旧场景原封不动，S2 钉死）+`switching_twice_in_one_frame...` FAILED 同签名；绿：**`t13t1_runtime_tests.log:259`（权威终态绿跑 4/4；`t13t1_runtime_green.log` 系 04:16 中间态残留「3 passed; 1 failed」，QA t13-t1-qa.md 回流①勘正，勿引）**。guards 侧红证 `t13t1_guards_red.log` 4/5 FAILED（②"MenuRoot must not outlive its scene at LevelRoot: left 1, right 0"=换绑后旧场景仍在；④"the first menu (and its context with it) is gone"失败=同；件①为早版自伤红，真红见 QA `t13t1_qa_neg_repro_guards.log`） |
| 2 | **headless 红→绿②（无残留/恒定）**：五轮循环计数恒等+零残留断言全绿 | **PASS（绿）** | `t13t1_guards_green.log` 5/5：①双向零残留（menu 文档实体含无父 UI 根全归零、level=单载基线 entities/members/roots 逐项相等、根存活、BindFailures 空；反向同）+②五轮 menu↔level↔gameover 每停靠点计数与首访逐项恒等（entities/members/roots/scenes/catalog 五元组 `PartialEq` 一行断言）+每停靠点内容断言（当前场景在场一次、其余两场景零残留——该断言在红跑给出 S2 红签名） |
| 3 | ③观察者单次 / ④绑定重接 / ⑤拒载可见 全绿 | **PASS** | ③`one_click_is_one_event_across_scene_reloads`：Activate 一次→`ScreenPressed` 恰一次，跨两次菜单重载共三次点击恰三次（STAND_PAUSE_SINGLE 净零签名跨场景形态）；④`bindings_rewire_onto_the_freshly_spawned_scene`：wire_menu 重挂新 MenuRoot、BindContext==跨场景玩家、血 70→40 期间换绑后 Progress 0.4/文本 "40 / 100"（新实例新鲜求值非旧值残留）、旧根与旧 context 随亡、BindFailures 空；⑤`a_broken_target_refuses_loudly_and_recovers`：missing.bsn/broken.bsn 换绑→`SceneRefused` 在根上+旧场景仍卸载+**warn 含目标名**（`Cannot spawn scene 'missing.bsn': …`，tracing 线程层捕获断言原文）+再换绑好场景恢复（refused 摘除）+加载中目标不崩溃就绪后 spawn（late.bsn） |
| 4 | 既有 `ui_scene_ownership`/`pie_scene_override`/热重载相关测试零回归 | **PASS** | `t13t1_runtime_tests.log`：runtime 全部 26 个测试二进制 0 failed——pie_scene_override 5/5、ui_scene_ownership 2/2、scene_root_name/retired_ui_components/document_twins/catalog_loading 等全绿（机械提取为等价重构+新触发器的放行条件成立） |
| 5 | quick 四门 | **PASS** | `t13t1_fmt.log` EXIT=0（空 diff）；`t13t1_clippy_ws.log` `--workspace --all-targets -D warnings` EXIT=0 零 error/warning 行；`t13t1_libtests.log` `--workspace --lib` EXIT=0（teaches 87 件在册全绿=未触动佐证）；受影响 crate 集成=runtime 全套（上栏）+`t13t1_bind_tests.log` EXIT=0 |

## 二、实现（crates/jackdaw_runtime/src/lib.rs）

1. **`clear_scene_instance(commands, root, members)`（私有，机械提取）**：despawn 成员 +
   移除 `SceneSpawned` + 复位 `SceneInstanceMembers`——`clear_modified_scene_roots` 改为
   调用它（diff 逐字等价），`respawn_on_scene_root_change` 调用它（新触发器）。
2. **`respawn_on_scene_root_change`（新，~20 行核心）**：查询
   `(Changed<JackdawSceneRoot>, With<SceneSpawned>)`+`Option<&SpawnedSceneId>`；若
   `SpawnedSceneId == 根当前 handle.id()` 则跳过（同 handle 重写≠切换），否则执行
   `clear_scene_instance`。链位在 `apply_pie_scene_override` 之后、`spawn_loaded_scenes`
   之前——PIE 的 Startup 换柄发生在根尚无 `SceneSpawned` 时，被 `With<SceneSpawned>`
   天然豁免（pie_scene_override 5/5 零回归即证）。
3. **`SpawnedSceneId(AssetId<JackdawScene>)`（私有组件）**：在 `spawn_loaded_scenes` 的
   全部四个 `SceneSpawned` 写点（成功+三类拒载）同点写入，不变量「SceneSpawned 的判定
   属于哪个场景 id」单一来源；拒载态也记录，使「换绑离场再换回」不卡死、重复换绑同一坏
   目标不反复重试。
4. **拒载 warn 带目标名（S8 的 runtime 半边）**：`Cannot spawn scene: {err}` →
   `Cannot spawn scene '{path}': {err}`（`AssetServer::get_path`；全仓无旧文案消费者，
   已核）。guards ⑤ 以 tracing 线程层捕获断言原文含 `missing.bsn`。
5. **doc 钉死语义**（`respawn_on_scene_root_change` 文档）：换绑保留根实体（Name/标记/
   根上组件）；异步未就绪期根空转，`spawn_loaded_scenes` 就绪门闸与 `SceneRefused` 拒载
   原样生效；同 handle 重写=no-op；同帧双切换合并、最后一柄获胜；**已知边界**：换绑落在
   「上一目标仍在加载」窗口时 Changed tick 被消耗（再换绑一次即恢复）。

## 三、测试账本

- `crates/jackdaw_runtime/tests/scene_root_change.rs`（4 件，方案预估 3-4 断言）：
  换绑即重载（根存活+根上组件保留+成员数恒等）/同 handle 重写不重启（**成员实体 id 不变**
  ——该件同时钉死去抖：无去抖的朴素实现会拆掉重造、id 必变）/同帧双换绑最后一柄获胜
  （中间柄永不实例化）/换绑坏文档 SceneRefused+再换绑恢复。测试刻意**预加载目标**
  （`wait_loaded`），doc 注明原因：未加载目标在任何 runtime 上都会经装载事件路径意外
  重载，no-op 缺陷只在已加载目标上现形。
- `tests/guards/game_flow.rs`（5 件，guards 229→234）：三文档种子（menu.bsn=UI 根+标记+
  绑定血条+Start 按钮；level.bsn=普通世界+标记；gameover.bsn=UI 根+Restart 按钮）经
  `AssetServer` 从 tempdir 真装载；①②④持有三柄（原语核心场景），⑤按路径换绑（missing/
  broken/late=in-flight 形态）。warn 捕获用 `tests/inspector/field_targeting.rs` 同款
  thread-local tracing 层（先例复用，非新机制）。
- 红证时间线（如实）：runtime 红跑与 guards 红跑均在**未修改 runtime** 上执行后才实现
  （`t13t1_runtime_red.log`/`t13t1_guards_red.log`）；guards 首版按路径换绑在现状
  runtime 上 4/5 假绿（意外装载路径），重构为持柄形态后红证 4/5 成立，再做实现。

## 四、门禁（日志全文复核；归档 `loop/reports/t13t1_*.log`）

| 门 | 结果 | 归档 |
|---|---|---|
| `cargo fmt --all -- --check` | EXIT=0（0 行） | `t13t1_fmt.log` |
| `cargo clippy --workspace --all-targets -- -D warnings` | **EXIT=0，0 error/warning 行**（首轮 2 件 doc_markdown/ok_expect 已修，重跑覆盖归档） | `t13t1_clippy_ws.log` |
| `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | EXIT=0 | `t13t1_clippy_physics.log` |
| `cargo test --workspace --lib` | EXIT=0 | `t13t1_libtests.log` |
| `cargo test -p jackdaw --test guards` | **234/234 passed, 0 failed**（69.1s；229 既有含 game_ui 7 件+新增 5） | `t13t1_guards.log` |
| `cargo test -p jackdaw_runtime` | 全部二进制 0 failed（含新 4 件） | `t13t1_runtime_tests.log`（绿跑 `t13t1_runtime_green.log`） |
| `cargo test -p jackdaw_bind` | EXIT=0 | `t13t1_bind_tests.log` |

**warn 形态扫描**（`cannot apply|cannot read|does not read as|UnresolvedTypes`，全归档）：
唯一命中 `t13t1_guards.log:4807` `cannot apply 'mygame::world::NotBuiltYet'`——归因
`tests/guards/scaffolded_component_flow.rs:558` 的既有测试对象（陈旧工程腿的红料），
**T12 基线 `t12t3_guards.log` 同款 1 条在案**，与本任务零关联。新测试面（runtime/bind/
guards game_flow）0 条。RUST_BACKTRACE 全程未设（红跑 panic 尾注 "note: run with
RUST_BACKTRACE=1" 即未设之证）；本轮无 PIE/真机腿，N13 记数不适用（0 次）。

## 五、偏差与记档分级

1. **🟡 实现超出方案决策 2-A 字面的两小块（均简报明授或验收必需）**：
   a. `SpawnedSceneId` 去抖——决策 2-A 只说「Changed+SceneSpawned→热重载机械」，简报
   执行要点补「同 handle 重写不重启（Changed 触发但值相同/去抖）」；runtime 测试
   `rewriting_the_live_handle_is_not_a_switch` 钉死（无去抖实现必红）。
   b. 拒载 warn 带路径——方案 T1-⑤「warn 文案含目标名」的现状文案不含路径，属验收必需
   的最小增强（一次 diff 行，无消费者破坏，已核全仓）。
2. **⚪ 方案事实三的修正性补充**：「对已 spawn 的根换绑新 handle 是 no-op」精确成立域=
   **目标已加载**（或其装载事件已消费）；未加载目标经 `AssetEvent::LoadedWithDependencies`
   意外重载。不推翻 S2 定级（无语义化原语、无拒载、竞态无把关的本质不变），但 T3 真机
   归因时注意：现状工程「能用」的换绑多为意外路径。已写进 guards/runtime 测试 doc。
3. **⚪ guards ③（观察者单次）在现状 runtime 上即绿**：no-op 世界=原按钮从未重载，单
   注册平凡成立。该件守的是**重载路径**的双注册回归（T3 真机 STAND_FLOW 的机制半边），
   非 S2 红证；S2 红证由 runtime 3 件+guards ②④⑤承载。
4. **⚪ BROKEN 文档形态**：`"this file is not a scene document"` 实测**可被 BSN 解析器
   接受**（宽容解析，不拒），换为未闭合 brace 形态保证拒载——解析器宽容行为记档
   （buglist Y28-Y30 域的旁证，不吸收不展开）。
5. **⚪ 测试计数**：guards 229→234（+5）、runtime 集成 +1 文件 4 件（方案预估 3-4 ✓）；
   teaches 87 不动（零模板改动）。方案 T1 改动面预估「runtime 新系统 ~20-30 行」实测
   核心 ~25 行+doc（合计 +89/−18，doc 占比高，符合「doc 钉死边界」的交付要求）。
6. **⚪ clippy 首轮 2 件**（guards doc 缺反引号、`ok().expect()`）即修即覆（重跑归档
   覆盖，符合 README 门禁纪律）。

## 六、给 QA 的注意事项

1. **T3 真机侧的切换动作**就是一行换绑（模板 States 的 OnEnter 里
   `commands.entity(root).insert(JackdawSceneRoot(server.load("xxx.bsn")))`）；无需
   despawn——旧成员由 runtime 清（含无父 UI 根，guards ①已断言）。
2. **日志形态变更**：拒载 warn 现为 `Cannot spawn scene '<path>': …`（带引号路径）；
   若既有脚本 grep 旧文案 `Cannot spawn scene: ` 需同步（全仓无代码消费者，已核）。
3. **PIE 换柄与切换原语互不越界**：`apply_pie_scene_override` 的 Startup 单次换柄不会
   触发重载系统（`With<SceneSpawned>` 豁免+去抖双保险）；pie_scene_override 5/5 回归
   在案。运行中 spawn 的新根不受影响。
4. **同帧双切换语义**（guards/runtime 双钉）：最后一柄获胜、中间柄永不实例化——T3 格 5
   （往返稳定性）若遇「连点两次 Start」腿，期望即此。
5. **已知边界**（doc 在案）：换绑落在「上一目标仍在加载」窗口会被 Changed 消耗（超 rare：
   需在新目标加载完成前再次换绑且换向第三场景）——再换绑一次恢复；T3 模板 States 单点
   翻转天然规避（决策 5-A）。
6. **guards 单跑过滤词**：`cargo test -p jackdaw --test guards game_flow`（5 件，~1.2s）；
   全量 234 件 ~70s。红绿日志中 guards 红跑行号对应红跑时点文件，与终态文件行号有漂移，
   以断言消息文本定位为准。
7. 门链与后续真机勿同窗（T12-T3 §九-7 口径）；本轮进程零遗留（未启动任何编辑器/游戏
   进程，headless only，无需 pkill——已核 `pgrep -f jackdaw` 空）。

**提交**：显式 pathspec（`crates/jackdaw_runtime/src/lib.rs`、
`crates/jackdaw_runtime/tests/scene_root_change.rs`、`tests/guards/game_flow.rs`、
`tests/guards/main.rs`）；loop/ 产物不入库；buglist/台账/roadmap 未触碰（主控合入时写）。
