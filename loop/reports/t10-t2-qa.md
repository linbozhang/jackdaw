# T10-T2 QA 验收报告：触发器/碰撞层/模板教学+真机不穿地首证（只验不修）

> 验收对象：分支 `loop/t10-triggers`，提交 **bd83b3da**（基于 main fcaba7c7，12 文件 +1189/−10）。
> 开局自检：分支/提交态核对一致；工作区仅剩既存噪音（.gitignore M、buglist.md 未跟踪），无其他未提交改动。
> QA 证据：亲跑四门禁+真机 direct run 独立复跑（`loop/reports/t10t2_qa_directrun.log`+本报告 §一采样抄录）、
> 程序六件归档全文复核、avian 0.8.0 源码核对（registry checkout 实读）、core_deps/git_deps 守卫实读。
> QA 真机脚本归档：`loop/qa/t10-t2-qa-directrun.ps1`。

## 一、真机不穿地首证独立复跑——成功（T1 挂账清偿核心证据）

**启动环境事件（如实记档）**：QA 环境下 direct run 游戏进程首三次启动失败——
bash 管道宿主调 `Start-Process`（直接 exe 与 `cargo run` 两式）均死于
`exit code: 0xc0000005, STATUS_ACCESS_VIOLATION`（stderr 止于 Vulkan AdapterInfo、
窗口创建之前，两次形态一致；`cargo build` 确认 exe 新鲜零漂移后仍复现，非构建竞态）。
改用 `cmd start /B` 完全分离启动后**一次成功**——崩溃与**进程宿主环境**（管道继承的
控制台/句柄态）相关，环境间歇性，非游戏代码确定性缺陷（同二进制程序 10-27 跑通、
QA 分离启动亦跑通）。该现象与程序记档 §六-3 的 0xc0000005 同码，裁定详见 §四②。

**独立复现的数值证据**（游戏侧 BRP `http://127.0.0.1:15702` scene_snapshot，
三次采样间隔 2s，脚本分离启动后采样；失败尝试日志归档 `t10t2_qa_directrun.log`）：

| 断言 | QA 采样（三次一致） | 程序报告值 | 判定 |
|---|---|---|---|
| 模板 FallingCube 落定 y | **0.3000**（x=-0.0097，落地轻横移属物理噪声） | 0.2999731/30/31 | 半边长 0.3 停在 stage 顶面（顶 y=0），**零穿透**；三次采样 4 位小数完全一致=两帧差在显示精度内为 0（程序 ±6e-8 互证） |
| stage 地面 | (0.0, -0.5) 在场 | 同 | 模板 spawn_stage ✓ |
| 拾取物 | x=-1 与 x=1 在场（y=0.5）；**x=0 缺席** | 同 | x=0 拾取物被落下的 cube 触发 despawn ✓ |
| 玩家 | (-2.0, 0.5) 在场，**PickupCount=1** | 同 | 拾取链端到端真机闭环：cube 落下→进 sensor→CollisionStart→TriggerEvents Enter→collect_pickups despawn+计数 0→1，全链 ✓ |

**结论**：T1 挂账「真机不穿地首证」以 QA 独立复跑清偿（direct run 数值+headless
guards ④ 双通道；PIE 窗口流程序已证）。跑毕孤儿进程清理 phys-game/jackdaw 计 0。

## 二、红绿真实性与门禁（全绿，亲跑+归档复核双通道）

| 门 | QA 亲跑 | 程序归档复核 |
|---|---|---|
| `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **CLEAN**（Finished 23.60s，EXIT=0；warning 全为 bevy 宏 crate 既有噪音） | `t10t2_clippy_physics.log` 零 error/warning 匹配 ✓ |
| `cargo xtask fast` | **2959 tests run: 2959 passed**（1 leaky+2 skipped 既有；fmt/core_deps「no third-party Bevy crate」/git_deps（66 manifests bevy main c9c397ba）/clippy 段全过，EXIT=0） | `t10t2_gate_fast.log` Summary 同绿；全文 error 匹配均为**测试名含 error 字样的 PASS 行**（21 行逐条目检）✓ |
| `cargo test -p jackdaw_avian_integration -p jackdaw_physics` | **51/51**（套件 5+4+6+5+5+6+0+20+0+0，与归档逐套件一致） | `t10t2_physics_tests.log` 同 ✓ |
| `cargo test --test guards physics_triggers` | **4/4**（0.86s） | `t10t2_guards.log` 同 ✓ |
| fmt / clippy_ws | （fast 段亲跑过） | `t10t2_fmt.log`/`t10t2_clippy_ws.log` 零 error/FAILED/Diff 匹配 ✓ |

- **红证形态核查（无需 stash 复演）**：三组关键红绿均为**同场景对照式**——①guards 前提红绿
  （silent sensor 无组件 vs armed 对带组件，`Starts==1` 而非 2：若 avian 无前提也发事件即红）；
  ②integration `without_the_plugin_there_is_no_list_and_no_prerequisite`（结构性红：断言
  Resource 不存在+prerequisite 不补齐，对照插件在的绿半）；③层过滤红绿（互滤对零接触 vs
  全通对恰一接触）。行为面偏离即红，由对照结构保证；main 上（本提交前）触发链零消费是
  策划事实四的既有红。**成立**。
- `t10t2_physics_tests.log` 第 709 行一条 bevy B0004 despawn WARN：位于 **editor 存量套件**
  （20 tests，上下文为 `OPERATOR: component.remove` 链），非 error、测试全过、本提交未触碰
  editor 测试——定性为存量测试运行时警告。⚪

## 三、代码 review（重点面全部核实）

1. **TriggerEvents「零 avian 依赖」**：`crates/jackdaw_runtime/src/triggers.rs` 仅
   `use bevy::prelude::*`，三类型（TriggerPhase/TriggerContact/TriggerEvents）纯数据面；
   三类型入 `jackdaw_runtime::prelude`（方案字面达成）；模块 doc 明确双 crate 分工与
   CollidingEntities「持续态」替代查询。✅
2. **`On<Add<Sensor>>` observer 时序语义（对照 avian 0.8.0 源码，registry checkout 实读）**：
   - `collider_tree/update.rs`：CONTACT_EVENTS flag **仅在 proxy 构建/重建时**从
     `Has<CollisionEventsEnabled>` 快照（:182/:271/:467 三处均为 `ColliderTreeProxyFlags::new`）；
     对照 SENSOR（:307/:327 Insert/Remove observer 响应式改写）与 CUSTOM_FILTER
     （CollisionLayers insert observer）**均无 CollisionEventsEnabled 的对应响应路径**；
   - `collision/broad_phase/bvh_broad_phase.rs:186`：`flags_union.contains(CONTACT_EVENTS)`
     闸住事件候选进入 narrow phase；`trigger_collision_events`（narrow_phase/mod.rs:286+）
     的世界直查只是候选之后的二次过滤——**「后加组件对已进树 collider 无效」断言在源码
     三重印证下成立**，observer（prerequisite 与 Sensor 同 flush 落实体、恒先于任何
     bridge 构建的 Collider 进树）是正确形态而非过度设计。✅
   - despawn 侧 `Query::get().unwrap_or(false)`：despawn 一侧读作非 sensor，幸存 sensor
     仍获 Exit——integration/guards 测试钉死。✅
3. **层隔离语义测试质量**：互滤判定（双方 memberships×对方 filters 双向不过→零接触）
   与 avian 语义精确一致；红绿对（0b0010/0b0100 vs 0b0001 双向零交 vs 0b0001/0b0001
   全通恰一接触）+桥面 Enter 可见性，且 doc 注释如实记档「静止体后改层不重配对」引擎
   边界（broad phase 增量配对，与源码观察一致）。✅
4. **重力双源归一（F8）**：`apply_gravity_from_config`（Update，`Res<GameConfig>`
   is_changed 驱动）单向注入 avian `Gravity`——单源=GameConfig 作者真相，无漂移回流；
   doc 两源边界（文件=下次启动/Resources 面板=会话内）与 T08 语义兼容。✅
5. **T09 Move 语义零漂移**：diff 核实 `move_player_by_actions` 与 InputActionsPlugin 链
   **零改动**；玩家物理身=Kinematic capsule（Transform 直写保留、collider 跟随——决策 6
   明文允许的保守备选）；fast 2959 全绿含 T09 测试族。✅
6. **`build_mesh_primitive_colliders` 补路**：三查询互斥核实（brush=With<Brush>、
   model=ModelFilter `Without<Brush>, Without<Mesh3d>`（model_colliders.rs:35 实读）、
   新路=With<Mesh3d> 且仅图元构造器）——覆盖补全不重叠。✅
7. ⚪ 观察（不阻塞）：`collect_pickups` 不检查 `contact.other` 是玩家——任何 collider
   （QA 真机亲见落下的 FallingCube 收走 x=0 拾取物）都计数。TriggerEvents 语义本身正确，
   但模板教学意图「walk into」与行为有偏差；T3 矩阵格 5（合成输入驱玩家拾取）是真正
   区分点，建议 T3 顺带补 `players.contains(contact.other)` 判定或 doc 注明。
   另 ⚪：Mesh3d 实体+`requires_mesh` 构造器静默 continue（无 collider 无警告，doc 有说明）。

## 四、四记档项逐条裁定（程序报告 §六）

| # | 记档 | QA 裁定 |
|---|---|---|
| ① | TriggerPlugin 选址（数据类型入 runtime、消费插件入 integration） | **成立**。core_deps 守卫实读（xtask/src/core_deps.rs:141-154）：violations 以「使用者含非 integration crate」计——`jackdaw_runtime` 直依赖 avian3d 即违规（T1 QA ✅ 的豁免最小化铁律）。方案哲学（游戏读可读状态零碰 avian）完整达成；integration→runtime 新依赖边无循环。**选址偏差是守卫铁律下的必然，非裁量偷懒。** |
| ② | windowless PIE×JackdawRemotePlugin 崩 0xc0000005（根因未修） | **记档成立，定性需扩界**。复现证据核实：`loop/t10t2-live/` dump/gdump/live 三份编辑器日志均有 `PIE: Play #1 exited before connecting with exit code: 0xc0000005`（15:05/15:16/15:19 三时段），probe 对照日志零崩溃——二分证据在档。**QA 补充证据**：QA 环境**窗口模式 direct run（带 remote）**亦两次复现 0xc0000005（AdapterInfo 后、窗口创建前），`start /B` 分离启动即通——崩溃与进程宿主环境相关且环境间歇（程序当时同二进制 direct run 跑通）。「稳定复现于 remote 组合」的定性不完整。**T3 处置建议：立项调查**（至少钉死启动环境敏感性矩阵），仅回避不够——真机矩阵的启动稳定性依赖于此。 |
| ③ | PIE 内数值采样通道受限（scene_snapshot 语义） | **成立**。编辑器端口快照=编辑器世界（文档实体+视口；`snapshot-pie.json` 97KB 在档），PIE 投影镜像实体在物理工程未出现——通道限制属实且如实记档。替代通道（direct run 游戏侧 BRP）**已被 QA 独立复跑验证有效**（§一）。game-config 改 gravity 两帧差留 T3 格 4 属计划内范围。 |
| ④ | scaffold_e2e 冷编腿未重跑（暖工程实编替代） | **替代充分，QA 不补跑**。组合证据：scaffold teaches 测试（fast 内亲跑绿）钉「scaffold 产物文本正确+占位零残留」；暖工程 lib.rs=新模板渲染产物，其 `cargo build` 程序跑过+QA 复跑通过（增量零漂移）；e2e 的自动化链（add_module_crates/lock 快照）本任务未触碰（T1 已验）。残留风险仅「模板改动使 e2e 缓存键失效后的首次贯通」——建议 T3 开工前跑一次落袋（20-40 分钟冷编）。 |

## 五、模板教学面抽查

- 模板 diff：doc 头「Physics & triggers」导览（collider/trigger/layer 三节+两重力说明）
  +5 行级占位（statements/falling_body/manual_gravity/player_body/demo），与 scaffold
  注入函数一一对应；占位反转（physics 时空行、非物理时注回手动重力行）使**模板双形态
  均编译**。✅
- doc 层表首版：互滤一句话（"a contact only exists when each side's memberships meet a
  layer the other side filters in"）与 avian 双向测试语义一致；hazard 0b100/player 0b001
  示例 bit 自洽。✅
- teaches 测试断言面（12 physics 断言+占位零残留+5 退场断言+手动重力回归）与「doc 教学段
  无条件在场」自洽——退场断言列表精确避开 doc 中无条件出现的字面（记档 §六-6 口径）。✅
- scaffold 84/84（83+新 1，fast 内含）。✅

## 六、问题统计与偏差分级

- 🔴 严重：0
- 🟡 中等：0
- ⚪ 轻微：4——①collect_pickups 无 other 侧判定（教学意图偏差，T3 格 5 区分+建议补判定/doc）；
  ②Mesh3d+mesh 型构造器静默无 collider；③editor 存量套件 B0004 despawn WARN；④scaffold_e2e
  冷编未贯通（§四④，T3 前置建议）。
- 环境事件 1 起（如实记档，非代码缺陷）：bash 管道宿主 Start-Process 启动游戏窗口模式
  两次 0xc0000005，分离启动成功——并入 §四②裁定。

## 七、结论

达标：真机不穿地首证**独立复跑成功**（数值+拾取链端到端，T1 挂账清偿）；红绿真实
（对照式红证+51/51+4/4 亲跑）；门禁全绿（QA 亲跑+六件归档全文复核双通道）；四记档
逐条裁定成立（②附 QA 扩界证据）；代码 review 六重点全核实（observer 时序获 avian
源码三重印证）；模板教学面达标。零 🔴 零 🟡。

**VERDICT: PASS**（建议主控 `--no-ff` 合入 bd83b3da。随行建议：①T3 将 0xc0000005
立项调查（§四② QA 补充证据：非 windowless 特有、与宿主环境相关）；②T3 开工前跑一次
scaffold_e2e 冷编落袋；③T3 矩阵格 5 用合成输入驱玩家拾取，顺带裁定 collect_pickups
的 other 侧判定；④记档 ⑤（静止体改层不重配对）与 ⑥（doc 无条件在场）维持程序口径。）
