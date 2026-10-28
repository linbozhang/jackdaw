# T13-T1 QA 验收报告：运行时切换原语 + 无残留机制面

> 验收对象：`loop/reports/t13-t1-report.md`；分支 `loop/t13-scene-flow`，程序提交
> `7e1e3c3e`（HEAD 即该提交，tracked 树洁净）。改动面核实：`git diff main...HEAD --stat`
> = **恰好 4 个文件**（`crates/jackdaw_runtime/src/lib.rs` +106 行差/−18、新
> `tests/scene_root_change.rs` 305 行、新 `tests/guards/game_flow.rs` 808 行、
> `tests/guards/main.rs` +1 行注册）——与报告自述一致，零越界改动。
> QA 手段：五门亲跑（后台+轮询、全程未设 RUST_BACKTRACE）+ 全部产品改动源码亲读 +
> 红绿证据亲读 + **负向复演亲跑**（临时回退 `lib.rs` 至 e9666d65 → 复跑终态测试 →
> 恢复 → 复绿确认，`git diff HEAD` 空=字节级还原）。QA 归档 `loop/reports/t13t1_qa_*.log`
> 9 件。裁判：**PASS，放行 T13-T2**；回流清单见 §六。

## 一、门禁（QA 亲跑，日志全文复核；归档 t13t1_qa_*）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | EXIT=0，零 diff 行 | `t13t1_qa_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | EXIT=0，全文 0 error/0 warning 行 | `t13t1_qa_clippy_dylib.log` |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | EXIT=0，0/0 | `t13t1_qa_clippy_physics.log` |
| 单测 | `cargo test --workspace --lib` | 2970 passed / 0 failed（teaches 87 在册=未触动佐证） | `t13t1_qa_libtests.log` |
| CI 快门 | `cargo xtask fast` | **2970/2970 passed, 0 skipped**（≥2970 达标），EXIT=0 | `t13t1_qa_xtask_fast.log` |

- 日志全文按行复核：clippy 两件 0 命中；libtests 全文唯一 `error[` 形态行 =
  `pie::prebuild_tests::a_failed_build_stays_on_screen...` 的**故意红料**（失败构建上屏
  测试，本件 ok）——零关联。xtask fast 全文无 FAIL/失败行。
- RUST_BACKTRACE 全程未设（QA 侧 unset + 无 backtrace 输出）；N13 不适用（本轮
  headless only，0 次）；进程零遗留（结束时 `pgrep target/debug` 空，已核）。

## 二、核心机制审查（源码亲读：`crates/jackdaw_runtime/src/lib.rs`）

| # | 审查点 | 结论 |
|---|---|---|
| ① | **链位** | `Update` 链 `clear_modified_scene_roots → apply_pie_scene_override → respawn_on_scene_root_change → spawn_loaded_scenes → cleanup_orphaned_scene_members`（`.chain()`，lib.rs:312-321）。依据成立：PIE 换柄只发生在 `Added<JackdawSceneRoot>` 当帧（`Local<bool>` 单次），此刻根尚无 `SceneSpawned`（spawn 需异步装载≥1 帧；即便缓存直载，spawn 在链上更后）——`With<SceneSpawned>` 过滤天然豁免 PIE，`pie_scene_override` 5/5 回归即证。位于 `spawn_loaded_scenes` 之前 + bevy 链式自动 deferred 应用点，清 verdict 的 commands 在 spawn 轮询读 `Without<SceneSpawned>` 前落定——与既有热重载链同一机制，无新时序假设 |
| ② | **职责边界/竞态** | 无重复无竞态：`respawn_on_scene_root_change` 过滤 `(Changed<JackdawSceneRoot>, With<SceneSpawned>)`，与 `clear_modified_scene_roots`（资产事件触发）和 `spawn_loaded_scenes`（`Without<SceneSpawned>` 门闸）三者作用域两两不相交。同帧双触发（换绑+资产事件）：clear_modified 先清（移除 `SceneSpawned`），respawn 被过滤豁免→单次清理。机械提取 `clear_scene_instance` 经 diff 逐字等价核验（原三步：despawn 成员/移 `SceneSpawned`/复位 members） |
| ③ | **去抖语义** | 判定键=**`AssetId<JackdawScene>`（柄身份），非路径**（`SpawnedSceneId` 在全部四个 `SceneSpawned` 写点同点写入，含三类拒载态——拒载也记账使「换走再换回」不卡死）。**热重载不会被误去抖**：①资产内容变更不产生 `Changed<JackdawSceneRoot>`（组件值未动、无人 insert），respawn 根本不被调用；②热重载走 `AssetEvent::Modified` 触发的 clear_modified，该路径完全不读 `SpawnedSceneId`。去抖只命中「游戏代码重写同柄」——insert 同值也置 Changed（bevy 语义），故去抖是必需品而非装饰；`rewriting_the_live_handle_is_not_a_switch` 以**成员实体 id 不变**钉死（无去抖的朴素实现必拆重建、id 必变——断言设计真能捕获） |
| ④ | **已知边界 doc** | 在案（respawn doc：「a rebind that lands while the previous target is still loading is superseded (the change tick is consumed…) — rebind once more to recover」）。QA 独立推演：该消耗只发生在根**无** `SceneSpawned` 时（无活场景可清，无实害）；且 `spawn_loaded_scenes` 是**逐帧轮询**而非事件驱动——空根+已就绪柄下一帧即 spawn，连「装载窗口内换向第三场景」也自恢复。**doc 偏保守（把自恢复写成需再换绑），方向安全，可接受不阻塞**（⚪ 记档） |

## 三、红绿复核（亲读+亲跑+负向复演）

**红证时序核实**：两份红日志（04:07/04:14）早于实现提交（04:34:46），日志含
`Compiling jackdaw_runtime`（改动前构建）+ `note: run with RUST_BACKTRACE=1`（未设之证）；
runtime 红 3/4 FAILED、guards 红 4/5 FAILED，签名均为 S2 本相（`["Anchor", "scene"]`
换绑后旧场景原封不动；guards ②「MenuRoot must not outlive its scene: left 1, right 0」）。

**QA 负向复演（本报告最强证据）**：`git checkout e9666d65 -- crates/jackdaw_runtime/src/lib.rs`
回退产品码至 T13 前，用**终态测试**复跑——
- runtime `scene_root_change`：**3/4 FAILED**（`t13t1_qa_neg_repro_runtime.log`），签名同上；
- guards `game_flow`：**4/5 FAILED**（`t13t1_qa_neg_repro_guards.log`），其中件①红在
  **真签名**「MenuRoot must leave zero residue behind the switch: left 1, right 0」
  （tests/guards/game_flow.rs:472）——补齐了归档红证的一个缺口（见 ⚪-2）；
- 件③（观察者单次）红态即绿，与报告 ⚪-3 自述一致（no-op 世界按钮永不重载、单注册平凡
  成立；该件守的是**重载路径**的双注册回归，非 S2 红证）——判断成立。
- 恢复 `7e1e3c3e` 后复跑：runtime 4/4 + guards 5/5 全绿（同日志尾），`git diff HEAD` 空
  =字节级还原，tracked 树洁净。

**绿态亲跑**：`t13t1_qa_guards_gameflow.log` 5/5、`t13t1_qa_runtime_src.log` 4/4、
`t13t1_qa_guards_gameui.log` 7/7、`t13t1_qa_t12_runtime_spot.log`（pie_scene_override
5/5 + ui_scene_ownership 2/2）。

**warn 扫描归因**：程序归档唯一命中 `t13t1_guards.log:4807`
`cannot apply 'mygame::world::NotBuiltYet'`——亲核来源
`tests/guards/scaffolded_component_flow.rs:553-558` 故意红料（陈旧工程未知类型必须被报
告），T12 基线 `t12t3_guards.log` 同款恰 1 条，零关联成立；QA 九件归档全文 0 命中。
另核：新拒载 warn `Cannot spawn scene '{path}'` 全仓**零消费者**（程序「已核」声明成立），
guards 件⑤以 tracing 线程层在测内断言原文含 `missing.bsn`（拦截先于全局 subscriber，
故不落日志文件——机制已核，非证据缺口）。⚪ 记档：该新 warn 形态不在常备扫描词表
（`cannot apply|cannot read|does not read as|UnresolvedTypes`）内，T3 真机扫描词表可增补。

## 四、🟡 事实修正核实（方案 §0 事实三的修正性补充）

亲核 `clear_modified_scene_roots` 匹配逻辑（现 lib.rs:568-598）：收集
`AssetEvent::Modified{id} | LoadedWithDependencies{id}`，按**根的当前** `root.0.id()`
匹配。据此推演并经负向复演印证：

- **修正成立**：no-op 精确域=目标已加载（`server.load` 命中缓存不发事件→无触发器）；
  未加载目标在装载完成时发 `LoadedWithDependencies`，恰好命中根的当前柄→旧场景成员被
  清、新场景 spawn——「意外重载」路径属实。guards/runtime 测试刻意持柄（`wait_loaded`/
  `flow_handles`，doc 注明原因）正是为不骑在这条意外路径上——测试设计判断正确。
- **不影响 S2 定级**：S2 本质（无语义化原语、拒载零反馈、同帧竞态无单点把关）不因意外
  路径存在而变；恰恰是意外路径解释了「现状工程为何能碰巧工作」，归 T3 真机归因注意事项。
- **不影响 T2/T3 计划面**：T3 模板三文档在 Startup 全量预载、切换永远指向已加载柄=
  真 no-op 域，且 T1 原语已落地；T2 flow 读取链与触发器无关。计划面零改动需求。

## 五、T12 零回归抽验 + 记档

- guards `game_ui` 全套 **7/7**（四屏翻转/血条 ratio/四分辨率布局/观察者单发/输入门控/
  拼错字段响报）；runtime 抽 2：`pie_scene_override` **5/5**、`ui_scene_ownership` **2/2**。
- **diff 面核对**：`git diff main...HEAD` 恰 4 文件，`crates/jackdaw_scaffold/`、
  `tests/guards/game_ui.rs`、`book/` 全部空 diff——hud.bsn 种子（二根形态/四屏语义）与
  全部 T12 面字节级未动；teaches 87 不动（libtests 全绿佐证）。物理双包 clippy 独立绿。
- 程序偏差记档复核：🟡-1a（SpawnedSceneId 去抖，简报明授）/1b（warn 带路径，验收必需
  且零消费者破坏）——均成立且已核；⚪-4（BROKEN 宽容解析旁证）、⚪-5/6（计数与 clippy
  首轮即修即覆）——核无异议。

## 六、偏差分级与裁决

| 级 | 项 | 说明 | 处置 |
|---|---|---|---|
| 🟡 | **报告与归档矛盾一处**：`t13t1_runtime_green.log`（04:16）是**陈旧中间态**（"3 passed; 1 failed"，件④ 拒载恢复未过），报告 §一却引为「绿 4/4」；真终态绿在 `t13t1_runtime_tests.log:259`（4/4，04:21） | 违反「重跑覆盖归档」纪律的字面；但 QA 亲跑已补权威绿证（`t13t1_qa_runtime_src.log` 4/4 + 恢复复绿），不阻塞 | **回流程序**：修正报告该处引用或覆写该日志；主控合入时知悉 |
| ⚪ | 归档 guards 红证件①的红是测试自伤（早版文件用全量 `Counts` 比较，持柄致 `scenes:3 vs 1`），非 S2 签名；终态文件已改 `scene_counts` 规避。S2 真红由件②④⑤+runtime 3 件承载，QA 负向复演已补终态形态的件①真红 | 红证整体成立，报告「红证 4/5 成立」对件①不精确 | 已由本报告 §三 补证，无需动作 |
| ⚪ | 报告「runtime 全套 25 个测试二进制」与归档 26 个集成二进制（+1 unittests）计数不符 | 计数口径差，0 failed 的实质不受影响 | 报告顺手修正 |
| ⚪ | respawn doc 已知边界偏保守（实际自恢复，见 §二-④） | 方向安全 | 无动作 |
| ⚪ | 新 warn 形态 `Cannot spawn scene '<path>'` 不在常备扫描词表 | 本轮无遗漏（测内断言在案） | T3 真机词表增补建议 |

## 七、裁决

**PASS** —— 放行 T13-T2（配置面 + 导出面）。

依据：五门亲跑全绿（xtask fast 2970/2970）；S2 红→绿经「归档红证 + 终态负向复演 + 亲跑
绿」三重闭合；核心机制四审查点全部源码级核立（去抖键=柄身份、热重载不可误去抖、链位
豁免 PIE 有 5/5 回归背书、无重复清理竞态）；🟡 事实修正核实成立且不动 S2 定级与 T2/T3
计划面；T12 零回归（game_ui 7/7 + 抽 2 全绿 + T12 面 diff 空）。

**回流清单（🔴 主控）**：
1. 🟡 程序修正 `t13-t1-report.md` §一#1 的绿证引用（指向 `t13t1_runtime_tests.log`）或以
   终态绿跑覆写 `t13t1_runtime_green.log`；顺手改 ⚪ 计数（25→26）。
2. 主控合入时知悉：guards 归档红证件①为测试自伤红（真红以 QA 负向复演
   `t13t1_qa_neg_repro_guards.log` 为准）。
3. 带★给 T3 的两条已经程序报告在案、QA 复核有效：真机切换一律持柄换绑（勿按路径新
   load）；拒载日志新文案 `Cannot spawn scene '<path>': …`。
4. QA 归档清单（9 件，`loop/reports/`）：`t13t1_qa_fmt.log`、`t13t1_qa_clippy_dylib.log`、
   `t13t1_qa_clippy_physics.log`、`t13t1_qa_libtests.log`、`t13t1_qa_xtask_fast.log`、
   `t13t1_qa_guards_gameflow.log`、`t13t1_qa_runtime_src.log`、
   `t13t1_qa_neg_repro_runtime.log`、`t13t1_qa_neg_repro_guards.log`（含恢复复绿尾注）、
   `t13t1_qa_guards_gameui.log`、`t13t1_qa_t12_runtime_spot.log`。
