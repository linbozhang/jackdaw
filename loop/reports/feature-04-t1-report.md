# 功能 #4 任务 1 报告：BRP 访问表数据链 + 降级守卫

> 多 Agent 开发循环 · 程序（Rust/Bevy 工程师）· 2026-10-22
> 分支 `loop/system-graph`，基于 main `130f01cc`，提交 `d914073e`
> （Report per-system component access in the schedules BRP method，2 files，+369/-18）

## 实现内容（对照方案任务 1 清单）

1. **server 侧纯函数**（`crates/jackdaw_remote/src/ecs_methods.rs`）：
   - `pub enum AccessKind { Read, Write, Archetypal, Unbounded }`，serde 小写字符串（`rename_all = "lowercase"` → "read"/"write"/"archetypal"/"unbounded"），两侧自定义枚举、不依赖 bevy 类型序列化（方案实现期核对项已落实）；
   - `pub struct AccessEntry { component: String, kind: AccessKind }`；
   - `pub fn system_access_entries(&SystemAccess, &World) -> Vec<AccessEntry>`：`Shared` 经 `combined_access().try_iter_access()` 逐组件导出 read/write/archetypal；unbounded（如 `Query<EntityMut>`，`try_iter_access` 返回 `Err`）收敛为**单条** `{component: "", kind: "unbounded"}` 标记；`Exclusive`（`&mut World`）与 `None` 产空表（exclusive 由回复的独立字段表达）；
   - 组件名经 `Components::get_info().name()`，未注册回退数字 id——与歧义命名共用新抽的 `component_name()` 辅助函数（`ambiguities_for` 原地逻辑收敛为调用它，行为不变）。
2. **handler 扩展**（同文件 `jackdaw_schedules_handler`）：
   - `schedule.systems()` → `schedule.systems_with_access()`（bevy main 持久挂在 Schedule 上的访问数据；两迭代器同为 `executable.system_ids × executable.systems` 的 zip，**index 空间不变**，edges/ambiguities 对齐不受影响——D1-2 结论核实成立）；
   - 每系统对象新增 `"accesses": [...]` 与 `"exclusive": bool`；
   - 顶层新增 `"access_reported": true`（含无 Schedules 资源的早退路径）。方法清单零改动（D5：无新 BRP 方法，老编辑器+新游戏无 404）。
3. **编辑器 serde 扩展**（`src/remote/debug/schedules.rs`）：
   - `SystemAccessEntry { component: String, kind: String }`（kind 保持字符串，未知 kind 容错——D6-2）；
   - `SystemInfo` 增 `#[serde(default)] accesses: Vec<SystemAccessEntry>`、`#[serde(default)] exclusive: bool`；
   - `SchedulesReply` 增 `#[serde(default)] access_reported: bool`；老回复解析为全空/false——降级守卫。depgraph/mod 只经 `Res<SchedulesReply>` 读取，无字面量构造点，零接线改动（消费方 UI 属任务 2/3，未做）。

## 测试（新增 9 个，全过）

- **server 六态**（`ecs_methods.rs`，模板：`World + Schedule::new + add_systems + initialize`，按方案 D6-1）：
  1. 资源读+写：`Res<Counter>` → read、`ResMut<Counter>` → write，组件名 `ends_with("Counter")`；
  2. 组件读：`Query<&Transform>` → read（`bevy_transform::…::Transform`）；
  3. archetypal：`Query<Has<Marker>>` → archetypal（bevy `Has<T>` 的 QueryData 确走 `add_archetypal`，fetch.rs:4002）；
  4. exclusive：`&mut World` 系统 → 空表 + `is_exclusive()`；另断言 `SystemAccess::None` → 空表；
  5. unbounded：`Query<EntityMut>` → 恰一条 `{component:"", kind:"unbounded"}`；
  6. 未注册回退：手工构造 `SystemAccess::Shared` + `ComponentId::new(999_999)` → `"999999"`（数字 id 字符串）。
- **server handler 级** 1 个：真实 handler 产出 JSON 断言 `access_reported == true`、每系统 `accesses` 含 "read"/"write" 小写 kind、`exclusive == false`（钉住线格式）。
- **编辑器 serde 两态** 2 个：完整新回复（含 unbounded 空组件名 + 未知 kind "whatever" 容错 + exclusive 系统）解析；老回复字面量解析 → `accesses` 空、`exclusive == false`、`access_reported == false`（降级守卫）。

## 各门退出码

| 门 | 结果 | 证据 |
|---|---|---|
| `cargo check -p jackdaw_remote -p jackdaw` | 0（PASS） | `Finished dev profile … in 30.78s` |
| `cargo fmt --all -- --check` | 0（PASS） | 应用 fmt 后复跑无 diff；xtask fast 链内该项亦过 |
| `cargo clippy --workspace -- -D warnings` | 0（PASS） | 经 `cargo xtask fast` 链内更严的 `--all-targets --features dylib -- -D warnings` 以 0 通过 |
| `cargo xtask fast` | 0（PASS） | Summary: 2785 tests run, 2785 passed, 2 skipped |
| `cargo xtask integration` | 0（PASS） | Summary: 4916 tests run, 4916 passed, 3 skipped |

零回归：两门合计 7701 通过；新增 9 个测试均在 fast 门中逐条可见 PASS。

## 帧开销实测（方案 D2，门槛 <5ms/秒帧尖刺）

方法：临时测量测试（跑完即删，未入库）搭模板世界——5 个 schedule（First/PreUpdate/Update/PostUpdate/Last = 20/30/120/80/30 系统，共 285 系统 + 每 schedule 1 个 exclusive），系统混合按 30% 单组件 / 40% 三组件+ResMut / 25% 五组件+Has+Res / 5% EntityMut，真实 `Schedule::initialize` 后调真 handler 30 轮取均值/峰值，另以「旧 handler 逻辑复刻」同轮对照隔离增量。

数字（dev 非优化构建，30 轮）：

| 指标 | 数值 |
|---|---|
| 访问条目总数 | 941 条（285 系统，均值 ~3.3） |
| 新回复体积 | 698,953 B（旧 603,420 B，**增量 95,533 B ≈ +16%**，量级与 D2 估算一致） |
| 旧 handler（复刻，含旧序列化） | avg 11.23ms / max 13.64ms |
| 新 handler | avg 11.98ms / max 15.24ms |
| 新序列化 | avg 1.55ms / max 2.31ms |
| **增量（handler 差 + 序列化差）** | **≈ avg 2.3ms / max ~3.9ms 每轮询** |

结论：**门槛通过，方案 A 成立，无需转方案 B**。理由：(a) 增量 ~2.3ms 是 **dev 非优化构建**数字，release 构建对这类分配密集代码通常快一个数量级，真机只会更低；(b) 绝对值 ~13.5ms 中约 11ms 为改动前即存在的 names/edges/ambiguities 构建成本（旧 handler 复刻同轮证实），非本功能引入；(c) 体积增量 ~96KB/秒 本机回环无压力。真机 release 环境的帧时间对拍留任务 3 人工 QA（清单原项）。

## 与方案偏差点

1. **unbounded 条目的 `component` 取空字符串 `""`**：方案草图只约定 kind，未定 component 值；取空串表意「无具体组件」，任务 2 的 `access_badge`（"ALL"）与恒命中过滤按 kind 判定即可。
2. **`ambiguities_for` 的命名兜底抽成共享 `component_name()`**：方案未列此重构；同文件同兜底逻辑去重（ambiguity 与 accesses 共用一处），行为零变化，属顺手收敛，降低两处漂移风险。
3. 测试数 9 > 方案字面「六态」：多出的 3 个为 handler 级线格式钉子 + 编辑器侧未知 kind 容错并入完整态断言（D6-2 第三小项「未知 kind 容错」并入完整回复测试而非独立测试）。

## 遗留 / Concerns（给任务 2/3 与 QA）

- 编辑器侧 UI（过滤/着色/徽标/From selection/降级提示行）全部未做——任务 2/3 范围，本任务只铺数据链与 serde 守卫，`access_reported`/`accesses` 当前无任何 UI 消费方。
- 测量为模板世界规模（285 系统/941 条目）；目标游戏若 schedule 显著更大（>1000 系统），增量按比例放大，任务 3 人工 QA 建议在真实游戏上复测一次帧尖刺（<5ms 门槛，超标触发方案 B 裁决——搬家路径已备好：`system_access_entries` 已是独立纯函数）。
- （未验证）真机 release 构建的绝对帧尖刺数字——本报告数字为 dev 构建实测 + 保守推理；任务 3 验收清单已含此项。
- 老游戏+新编辑器降级路径仅有 serde 单测级证据（老字面量解析为全默认）；端到端「老版本模拟驱动 UI」验证属任务 3 人工 QA。
