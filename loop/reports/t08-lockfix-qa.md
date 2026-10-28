# T08-T3 前置小任务 QA 报告：scaffold fresh lock 漂移修复（聚焦·轻量·只验不修）

> 验收对象：分支 `loop/t08-lock-fix`（自 main e70348d5），提交 **c0f9929e** `Pin fresh scaffold locks to the workspace bevy tree`（单文件 `crates/jackdaw_scaffold/src/lib.rs` +75，与程序报告一致）。
> 证据：`loop/t08lf_qa.log`（QA 必炸路径独立复跑）、`loop/t08lf_qa_jdbuild.log`（jd 重编）、`loop/t08lf_*`（程序归档五件套）、scaffold 亲跑输出。工作区核对：与提交态一致。
> 前置说明：QA 复跑前发现 `target/debug/jd.exe`（06:08）早于提交（06:31）——**快照嵌入在 jd 里，必须先重编**（06:33 重编后复跑）；这与偏差②的新鲜度规则是同一规则的实例，doc 已写明。

## 一、必炸路径独立复跑（核心）——PASS

QA 上轮（t08-t2-qa.md §六-3/behavior 轮）记录的必炸路径：fresh `jd new` 工程编辑器首 prebuild 必炸（E0308 wgpu-hal 失配×2 轮+schema 空白+asset.new 拒绝）。本轮独立复现修复后状态（`loop/t08lf_qa.log`，全新工程 `loop/qa-fixture/t08lf-qa`）：

1. **fresh `jd new`**（重编后的 jd）→ 8 文件 scaffolded；
2. **lock 三查（修剪不漂移独立实证）**：`jd new` 自带 resolve 后的 lock——本工程条目已补入（own-entry=True）、**bevy 保持 workspace rev c9c397ba**（True）、漂移 rev fe544043 **不在**（False）——seed 快照被 cargo 最小变动修剪（加本工程条目），未触发全量重解析；
3. **编辑器 prebuild 一次过**：`JACKDAW_OPEN_PROJECT` 打开 → BRP up → **IDLE reached** → `.jackdaw/schema.json` 产出且**含 GameConfig** → 编辑器存活 → **stderr ERROR 行数 0**（含 `--locked` 全程）。

与程序归档 `t08lf_prebuild.log`（IDLE/SCHEMA/ALIVE 三 True）互相印证。**上轮必炸路径修复闭环**。

（附注：QA 探针 `jackdaw/assets` face 字符串匹配 GameConfig 为 False，系 QA 脚本对 result 对象的字符串化形态问题，非产品证据——schema.json 含 GameConfig 为 prebuild 成功的主证据，不影响判定。）

## 二、机制 review——无新 🔴/🟡，一项 ⚪ 观察

1. **快照嵌入与新鲜度**：`include_str!("../../../Cargo.lock")` 编译期嵌入，doc 写明「checkout 构建每次重编即更新，与模板 include_dir 同款规则」——与 T1 教训（模板 include_dir 须重编 jd）一致；且 `include_str` 是 cargo 的文件依赖追踪项，改 workspace lock 会自动触发 `jackdaw_scaffold` 重编——机制上「忘了重编」的暴露面比模板 include_dir 更小。路径解析（`src → ../../..` = 仓库根）正确。
2. **写入时机**：`scaffold_new_project_with` 在 dev-checkout 依赖改写后、`check_new_project`（cargo metadata）前写入 `<dest>/Cargo.lock`（仅 `TemplateKind::Game`）——时序正确（metadata 见到 lock 才走最小变动）。
3. **修剪不漂移论证**：cargo 对已有 lock 的 metadata 语义=保留已锁版本、只加本工程条目、prune 未引用——文档化行为；程序真机实证+QA 本轮 lock 三查双重印证。`pin_project`/`ensure_lockfile` 见 lock 已在目标 rev → no-op，`--locked` 构建一次过——三环（fresh 解析坏锁、pin 单包不重排、--locked 锁死坏锁）逐环拆解，论证成立。
4. **活样本记档核实**（偏差①口径）：`H:\workspace_AI\t08-qa-game` 现状=manifest 已对齐模板写法（`bevy = { git = ..., branch = "main" }`）+lock 含 c9c397ba——与程序「复活路径=拷 lock+manifest 对齐」记档一致；QA 手改状态（rev 固定写法）确属样本侧差异，修复本身不受影响。样本保留供 T3 复用或删除，接受。
5. **路径名拒绝**（⚪ 顺带项）：`validated_project_name` 前置拒绝路径形态+--path 指引；用例覆盖 `E:\games\my-game`、`/home/me/my-game`、`games/my-game` 三形态。**QA 真机抽验**：`jd new E:\games\my-game ...` → 拒绝并输出「pass the directory with --path and only the name here」——上轮 QA 亲历的静默错名目录事故根因关闭。
6. **⚪ QA 侧观察（不阻塞）**：workspace lock 中本地 crate 条目（如 `jackdaw_runtime`）为 path 形态（无 source 字段）；**发布形态 jd**（新工程 manifest 用 registry 版本号）拿到含 path 条目的快照时可能触发单包级重解析。发布打包链路届时需验证（程序报告称「发布 jd 打包发布时验证过的组合」）；本 Loop 全程 checkout 构建（工程依赖本地 path，形态匹配），不受影响。建议随发布流程记档。

## 三、新用例亲跑——绿

`cargo test -p jackdaw_scaffold`：**81 passed / 0 failed**（2.07s），含两条新用例均在列：
- `a_new_game_carries_the_workspace_lock_snapshot`（生成的 lock 逐字等于快照；doc 注明 live 行为由真机腿钉住）；
- `a_project_name_that_is_really_a_path_is_refused_with_guidance`（三形态拒绝+--path 指引）。

## 四、门禁抽验——过

- 归档全文复核（`loop/t08lf_*`）：fmt 空=clean；clippy 0 error 行；`t08lf_game_build.log`/`t08lf_qagame_build.log` 各 0 error+Finished；`t08lf_prebuild.log` IDLE/SCHEMA/ALIVE 三 True（§一互证）。
- 程序未重跑主 crate/guards（只动 scaffold、clippy all-targets 覆盖编译面）——**接受**：改动面单 crate，lib/guards 无涉；QA 侧 scaffold 亲跑 81/0 补全。

## 五、偏差 4 条裁定

| # | 偏差 | 裁定 |
|---|---|---|
| ① | 活样本需 manifest 对齐（rev 固定→branch 写法）才活 | **接受**（QA 样本手改状态差异，记档口径核实成立；样本已对齐保留供 T3） |
| ② | 快照新鲜度=重编 jd（沿 T1 include_dir 惯例，doc 写明） | **接受**（include_str 参与增量追踪，暴露面更小；本轮 jd.exe 陈旧即此规则实例，重编后验证） |
| ③ | extension 模板不写快照 | **接受**（依赖树窄+任务范围 Game；漂移窗口出现再扩，记档） |
| ④ | pin 机制不修，由 lock 快照使其 no-op | **接受**（`--precise` 单包移动不重排传递树是 cargo 语义、无可靠原语；快照路线在新工程上让 pin/ensure/--locked 三步全 no-op 命中好锁，比修 pin 更稳——论证与实证均成立） |

## 六、结论

必炸路径独立复跑绿（lock 三查+IDLE+schema+零 error 一次过）；机制审无新 🔴/🟡（一项发布形态 ⚪ 观察记档）；新用例+scaffold 亲跑 81/81 绿；归档四门复核过；偏差 4 条全部接受。上轮 QA 记录的 T3 硬性前置（t08-t1-qa.md §六-②）就此解除。

VERDICT: PASS（建议主控 --no-ff 合入；T3 记事：发布形态快照的 path 条目观察随发布流程验证；活样本 t08-qa-game 可复用或删除；qa-fixture 下三个测试工程建议 T3 前清理或按需保留）
