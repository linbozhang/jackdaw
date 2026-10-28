# 功能 #4 任务 1 QA 验收报告：BRP 访问表数据链

> 多 Agent 开发循环 · QA（独立第三方验收）· 2026-10-22
> 验收对象：`loop/system-graph` @ `d914073e`（基于 main `130f01cc`），diff = 2 files，+369/-18
> 验收方式：独立复跑四门 + diff/bevy 源码逐条核实（未采信程序报告的自述数字，全部自证）

## VERDICT: **PASS**

---

## 1. 确定性门（全部自跑，退出码与计数）

| 门 | 结果 | 计数 / 证据 |
|---|---|---|
| `cargo fmt --all -- --check` | exit 0 | 无 diff |
| `cargo clippy --workspace -- -D warnings` | exit 0 | Finished in 36.27s；仅有 toolchain 级 `linker_messages` warning（rust-lld 忽略 `-fuse-ld=lld`），lint 自述 ignores `-D warnings`，与本 diff 无关 |
| `cargo xtask fast` | exit 0 | Summary: 2785 tests run, 2785 passed, 2 skipped；链内 fmt + clippy `--all-targets --features dylib -D warnings` 均过 |
| `cargo xtask integration` | exit 0 | Summary: 4916 tests run, 4916 passed, 3 skipped |

**环境备注（非代码问题）**：xtask fast 首跑失败，原因为 Windows 环境性文件锁——链接 `jackdaw_dylib` 测试 exe 时 `rust-lld: failed to write output ... permission denied`（杀毒/索引服务占用典型症状），立即重跑即过。CI 或后续 Agent 复现时先重跑再判定。

**新增 9 测试在 fast 门逐条可见 PASS**（nextest 输出 grep 核实）：`system_access_entries_reports_{resource_reads_and_writes, component_reads, archetypal_access, exclusive_and_none_as_empty, unbounded_access_as_marker, falls_back_to_numeric_id_for_unregistered_components}`、`schedules_handler_reports_accesses_and_capability_flag`、`reply_deserializes_accesses_and_capability_flag`、`reply_defaults_access_fields_when_absent`。

## 2. 规格符合性（逐条）

### 2.1 数据链正确性（核心）— ✅

- **`systems_with_access()`**（bevy@`c9c397ba` `schedule/schedule.rs:754`）：与旧 `systems()`（`:732`）完全同构——都是 `executable.system_ids × executable.systems` 的 zip，仅多携带 access。**index 空间不变、edges/ambiguities 对齐不受影响**的声明经 bevy 源码核实成立。
- **`try_iter_access()`**（`query/access.rs:532`）：`Shared(id)`=读、`Exclusive(id)`=写、`Archetypal(id)`=存在性；unbounded（read_all/write_all）返回 `Err(UnboundedAccessError)`。实现的映射（Shared→Read / Exclusive→Write / Archetypal→Archetypal / Err→单条 unbounded 标记）与 bevy 语义一致；archetypal 与 reads 重叠时 bevy 自身已做 `difference(reads)` 去重，无重复条目。
- **ComponentId→名字**：`world.components().get_info(id).name()`；未注册回退 `id.index().to_string()`（`ComponentId::new(999_999).index()==999_999`，`component/info.rs:188-196` 核实）。`Has<T>` 走 `add_archetypal`（`query/fetch.rs:4002-4003` 核实，报告引用准确）。
- **六态测试逐个读过，断言语义真实**（非"只断不空"）：每条断言具体组件名后缀（`ends_with("Counter"/"Transform"/"Marker")`）+ kind 枚举值；unbounded 断言恰一条 `{component:"", kind:Unbounded}`；未注册断言 `"999999"` 字符串。
- **exclusive/&mut World 呈现合理**：`SystemAccess::Exclusive` → `accesses=[]` + `exclusive=true`（`is_exclusive()` 仅 Exclusive 变体为 true，`system/access.rs:41` 核实）；`None`（不访问世界）→ `[]` + `false`。两种空表靠 `exclusive` 字段区分，数据自洽。
- **handler 级线格式钉子**：`schedules_handler_reports_accesses_and_capability_flag` 断言 `access_reported==true`、kind 为小写字符串 `"read"/"write"`、`exclusive==false`——序列化形态被测试钉住。
- **Err 分支（schedule 未初始化）**：保持原 `initialized:false` 空数组形态不变；顶层 `access_reported:true` 含无 Schedules 资源的早退路径，合理（能力与资源存在性无关）。

### 2.2 降级守卫 — ✅

- 编辑器 `reply_defaults_access_fields_when_absent`：老回复字面量（无 `accesses`/`exclusive`/`access_reported`）解析成功且断言 `!access_reported`、`accesses` 空、`!exclusive`——serde 两态测试核实。
- 未知 kind 容错：`kind` 保持 `String`，测试含 `"whatever"` 保留断言；未知嵌套字段被 serde 丢弃（现状 `initialized` 同款）。
- 编辑器侧不炸：`SystemInfo`/`SchedulesReply` 全部新字段带 `#[serde(default)]`；depgraph.rs:133 与 debug/mod.rs:66 仅经 `Res<SchedulesReply>` 读取，**无字面量构造点**，零接线改动核实成立。

### 2.3 帧开销实测方法论 — ✅（带一条 ⚪ 保留）

- **增量归因干净（方向保守）**：30 轮 + 旧 handler 逻辑复刻同轮对照。数字自洽：handler 差 0.75/1.60ms + 序列化 1.55/2.31ms ≈ avg 2.3 / max 3.9ms，< 5ms 门槛（主控方案 A 裁定成立）。绝对值 ~13.5ms 中 ~11ms 为改动前既有成本（旧 handler 复刻证实），归因逻辑成立。
- **基准世界规模与 D2 设定一致**：285 系统（5 schedule，Update 120 落在 D2 引用的 50-150 区间）、941 条目（均值 3.3，在 D2 "每系统 1-6 条"内、略低于均值 4 的假设即偏保守）、增量 95KB 与 D2 估算 150-400KB 同量级偏小。dev 非优化构建 + release 只快不慢的推理方向正确。
- **⚪ 保留**：测量测试"跑完即删，未入库"，QA 无法独立复现基准世界构造（只能核报告自述与 D2 口径的一致性）；且"新 handler avg 11.98"是否含 serde 序列化口径未写明——两种口径下 2.3/3.9 均为保守上界，不影响门槛判定，但任务 3 真机复测时应补齐口径说明。

### 2.4 游戏侧零改动 — ✅

`git diff main..loop/system-graph` 全量 = `crates/jackdaw_remote/src/ecs_methods.rs` + `src/remote/debug/schedules.rs` 两文件；对 `jackdaw_runtime`/`jackdaw_pie_protocol`/`book`/`loop/plans` 路径过滤 diff 为空。`jackdaw_remote` 是方案 D5 明定的唯一 server 改动点（BRP server crate，游戏升级依赖重编即得，无游戏代码改动），方法注册表（lib.rs）零改动。

### 2.5 无任务 2/3 越界 — ✅

无 depgraph.rs/graph.rs/debug/mod.rs/UI/过滤/着色/徽标/From selection/降级提示行/文档/roadmap 改动；schedules.rs 的改动仅 serde 结构 + 两态测试 + 模块文档注释，无 `system_box` 徽标（任务 3 项）。

## 3. 偏差抽验

1. **unbounded 条目 `component=""` 下游消费（任务 2 前瞻）**：当前无任何 UI 消费方，任务 1 内自洽（kind 有独立标记）。两个任务 2 实现隐患：(a) picker 候选若按方案 D3-5 取"accesses 组件名并集"，**必须排除空串**，否则出现空白 chip；(b) From selection 的 OR 匹配**必须按 `kind=="unbounded"`（及 `exclusive` 字段）恒命中**而非纯组件名匹配，否则 `Query<EntityMut>` 系统被漏报。方案 D6-3 已把"unbounded/exclusive 恒命中"规格化，属实现注意事项而非本任务缺陷——建议主控把这两点显式写进任务 2 交底。
2. **`component_name()` 抽取零行为变化** — ✅：diff 逐行比对，`ambiguities_for` 原 `match get_info { Some→name().to_string(), None→index().to_string() }` 与新函数体逐字符一致，仅收敛为共享调用，行为零变化（报告声明属实）。

## 4. 代码质量

- **`system_access_entries` 纯函数隔离** ✅：签名 `(&SystemAccess, &World) -> Vec<AccessEntry>`，无副作用、无全局状态；唯一内部依赖 `component_name`（同文件纯函数）与自包含类型 `AccessKind`/`AccessEntry`（derive Serialize）。方案 B 搬家"零逻辑改动"声明成立（需连同这三个定义一起搬，均无外部耦合）。
- **无 unwrap 滥用** ✅：生产代码零 `unwrap`/`expect`（`try_iter_access` 用 match、`get_info` 用 match、未初始化走既有 Err 分支）；unwrap 仅出现在测试（惯例档位）。**无新增 allow**。
- **序列化风格一致** ✅：新增字段 `accesses`/`exclusive`/`access_reported`/`component`/`kind` 全 snake_case，与既有 `name`/`sets`/`schedule`/`systems`/`edges`/`ambiguities` 一致；`AccessEntry` derive Serialize 后经 `json!` 引用，与既有 `Ambiguity` 同款模式；嵌套层次（系统对象内一层数组）与既有结构平齐。`AccessKind` 用 `rename_all="lowercase"` 小写字符串，符合方案"两侧自定义枚举、不依赖 bevy 序列化"的核对项。

## 5. 问题统计与结论

| 级别 | 数量 |
|---|---|
| 🔴 严重 | 0 |
| 🟡 中等 | 0 |
| ⚪ 轻微 | 1 |

- ⚪ [程序] 帧开销测量代码未入库且序列化归因口径未写明（见 §2.3）——不阻塞，建议任务 3 真机复测时补齐。

**concerns（移交主控/任务 2/3）**：
1. 任务 2 交底应显式包含：picker 候选排除空串 `component`；unbounded/exclusive 按标记恒命中（勿纯组件名匹配）。
2. 任务 3 真机 release 帧尖刺复测 + 大规模 schedule（>1000 系统）游戏上的复测（程序报告已自列，QA 同意保留）。
3. Windows 环境下 `jackdaw_dylib` 测试 exe 偶发文件锁（本次 fast 门首跑 permission denied，重跑即过）——建议 CI/后续 Agent 将 target 目录加入杀毒排除，遇此错先重跑再判定。

**VERDICT: PASS**（四门全 0 + 规格五项全 ✅ + 无 🔴/🟡；⚪ 不阻塞）。
