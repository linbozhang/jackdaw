# T17 任务 1「runtime 存档薄层」QA 验收报告

> 裁决：**PASS**（附 6 条回流/移交注记，无一阻断 T17-T2）。
> 验收对象：分支 `loop/t17-save` @ **e589257f**（工作树与程序提交零漂移，`git status` 干净）；
> 程序报告 `loop/reports/t17-t1-report.md`；门禁与探针全部 **QA 亲跑**（2026-10-30，
> 本机 macOS；全程未设 RUST_BACKTRACE；门前 df=69Gi 可用）。QA 归档 10 件
> `loop/reports/t17t1_qa_*`（gates.sh 脚本+9 日志，exitcodes.log 汇总）。

---

## 一、门禁（QA 亲跑，日志全文复核制）

| 门 | 命令 | QA 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **EXIT=0**，零 Diff | t17t1_qa_fmt.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | **EXIT=0**，`warning:` 计数=0；`error` 串 1 命中=PASS 行测试名（`jackdaw_bind error::tests::display_text_is_pinned`），逐条归因 | t17t1_qa_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | **EXIT=0** | t17t1_qa_clippy_phy.log |
| 单测（README 门） | `cargo test --workspace --lib` | **EXIT=0，2989 passed / 0 failed**（逐 `test result` 求和亲算；=T16 基线 2987+save.rs 内联 2）；**scaffold=90**（teaches 预期，T16 口径延续） | t17t1_qa_libtests.log |
| fast | `cargo xtask fast` | **EXIT=0**；三步形态亲验（fmt→clippy→nextest）在档；**Summary 2989/2989（63.4s）**；全文 0 FAILED/0 diff/0 真错误（唯一 error 串=测试名，同上） | t17t1_qa_fast.log |
| AN2 腿 | `cargo nextest run --profile ci -p jackdaw_runtime --features animation --test animation_scene_load` | **1/1 PASS（exit 0）** | t17t1_qa_an2.log |
| save_store 套件 | `cargo nextest run --profile ci -p jackdaw_runtime --test save_store` | **17/17 PASS** | t17t1_qa_save_store.log |
| runtime 全件 | `cargo test -p jackdaw_runtime` | 全绿：lib **42**（含 save 内联 2）+save_store **17**+其余件全过，0 failed | t17t1_qa_rt_suite.log |
| fixture --locked | `cargo build --locked`（tests/fixtures/bsn_game） | **EXIT=0**（QA 复跑 0.57s 增量；冷编口径见 §五-B） | （QA 复跑未单独立档，结论在案） |

门禁结论：**八门全绿，与程序报告的门禁表逐项相符**（计数 2989/42/17/90/1 全部亲算复核）。

## 二、save.rs 源码级审查（本任务全部产品改动面）

产品 diff 实测（`git show --stat e589257f`）：Cargo.lock +1、runtime Cargo.toml +5（注释 4 行+
`dirs.workspace = true` 1 行）、lib.rs +14（mod+根 pub use+prelude）、save.rs 761（新）、
tests/save_store.rs 828（新）。**零 fork 改动、零编辑器产品代码改动、零模板改动**——与报告
§〇-四的改动面声明逐字相符。

### ① 三态守卫与三先例的形态一致性 —— 成立

| 先例 | save.rs 落点 | QA 亲核 |
|---|---|---|
| config.rs:127-137（默认先插+loader 自灭一次 warn） | `SavePlugin::build` 同步 `open_in`→`insert_resource`（store 第一帧前就位，M1 断言）；写失败 warn 走 `warned_write_failure` 单次（:305-312），恢复后重试成功（M12 测试） | ✓ |
| flow.rs:16-21 + 90-142（warn-and-fall 哲学+逐分支 warn 表） | `load()`（:470-539）逐分支镜像 parse 形状：NotFound→安静 Fresh；坏读/非 UTF-8/坏 JSON/非对象/未知字段点名忽略/缺版本/缺 profile/schema 不符→各自 warn；自带 `json_kind` 副本与 flow 同款 | ✓ |
| project.rs:322-338（`.corrupt-<millis>` rename 备份） | `back_up_corrupt`（:566-584）同款：rename 非复制、一次一档、不清理（SV7 同语义，测试 `every_corrupt_load_leaves_its_own_backup` 钉两备份各含各字节） | ✓ |

M11 五形态（烂 JSON/空文件/二进制垃圾/半截文件/错 schema profile）测试全 Recovered+备份字节
逐字节原样+槽位腾空至下次写——「损坏安全回退不崩」的 H 侧证据成立。

### ② VersionSkipped 不变式 —— 成立，双钉亲核

- **模块 doc**：`save.rs:48-59`「The invariant: an unreadable save is never overwritten」整节
  在案，含 Recovered 为何豁免（备份已兜住原文）。
- **实现路径两点独立钉死**：`flush_saves` 显式 skip（save.rs:461，且 skip 静默——load 时已 warn
  过原委）+ `write()` 显式拒绝（save.rs:283-291，`SaveError::VersionGuard{found}`+warn）。
- **测试真能捕获违规**（QA 逐断言推演）：M10a `a_newer_save_is_never_overwritten_automatically`
  写入 v99 原文→记 before 字节→mutate 置 dirty→**3 帧 flush 后字节级相等**（若 flush 漏判
  status，默认档即落盘、字节必变→红）；显式 `write()`→`Err{VersionGuard 99}`+字节再验（若
  write 漏守卫→红）；`reset_to_default`→write 成功且盘上 save_version=1（守卫可出、语义闭环）。
  两个执法点各有一条独立红路径。M10b 补旧版无迁移同抑制。
- **边界注记**：`SaveStore` 字段 pub（决策 8 的 BRP 断言面所必然），游戏手改 `status` 可绕守卫
  ——与 `reset_to_default` 同信任级，自动路径不变式不受影响，不算缺陷。

### ③ 原子写 —— 成立（texture_import 形态，非 T04 重型形态=方案指定）

`atomic_write`（save.rs:657-673）：`create_dir_all`（惰性建目录，M9 断言 load 永不建）+
tmp(`save.json.tmp`)+`write_all`+`sync_all`+`rename`。与 texture_import.rs:157-163 同构且多
`sync_all` 一道；T04 `write_atomic`（document.rs:105）的重型三件（staging 重试/`.bak` 单槽/
双 rename 回滚）方案明确不拉入（「实现自含 runtime ~15 行」）——形态选择合规。残 tmp 被下次
写整吞+loader 只读 `save.json`（常驻断言 `a_stray_temp_file_is_never_taken_for_a_save`）亲核。
**观察 E（移交 T2/T3）**：tmp 名无 pid/唯一后缀——T04 doc 明言跨写方共用 staging 文件的竞态
教训；决策 6-A（PIE 与 direct 同槽）下双活进程理论上可交错（后果被损坏路径兜住：备份+默认，
无不可挽回丢失）。建议 book 一句或 SV 记档，主控裁定。

### ④ 迁移链（with_migrations）语义 —— 成立，QA 补 3 探针亲跑

实现（save.rs:589-652）：`from==version` 找步→无步 warn+VersionSkipped（盘不动）→**单调检查**
`step.to <= step.from` 拒绝（warn「walks backwards」）→apply 失败降级 VersionSkipped→
`hops > len` 环界（QA 推演：单调成立后每步 version 严格递增、每步至多选中一次，该界不可达=
纵深防御，无害）→链毕 serde 终检。**SAVE_VERSION=1 时链至多一跳**（M10c 覆盖该唯一跳；
多跳路径当前构造不出，属 v2+ 预置机制）。

QA 临时探针 3/3 PASS（`tests/t17t1_qa_probe.rs`，跑后已删、树归零）：
1. **退化步 0→0** → `VersionSkipped{0}`+warn 含 "walks backwards"+文件字节不动——单调检查实弹验证；
2. **越顶步 0→5（vs SAVE_VERSION=1）** → `Loaded`（profile 类型 serde 终检是真正闸门）——越顶语义
   成立但 doc 未记，建议 book/迁移 API doc 一句（回流 C）；
3. **版本超 u32（5e9）** → **Recovered+备份**（非 VersionSkipped；u32 装不下即按损坏走，字节已备份
   无丢失）——语义成立，建议 doc 一句（随 C）。

常驻测试未覆盖单调/环边界（M10c 只覆盖正常迁移+apply 失败）——**建议 T2/T3 把探针 1 吸收进
save_store.rs**（回流 F）；`reload()`/`dir()`/`save_file()` 无专项测试（实现平凡，不阻）。

### ⑤ JACKDAW_SAVE_DIR 整体替换口径 —— 成立（脚本标配口径无误）

`save_dir`（save.rs:365-370）：`var_os`+**非空过滤**（空串回落 data dir，未测、实现清楚）→
`PathBuf::from(overridden)` **原样返回、不拼 game-id**；测试
`the_environment_seam_moves_the_whole_save_directory` 断言 `dir == scratch.path()` 逐字。
与 jackdaw_env `JACKDAW_CONFIG_DIR`（**拼** `launcher` 子目录，paths.rs:88-91）的差异是**有意
设计**（SAVE_DIR_VAR doc+模块 doc+报告 QA 注记 3 三处写明「整体替换」）——t17-live.sh 按此口径
指向 scratch 即可。三层兜底（data>home `~/.local/share/<id>`>None→NoDir）与 paths.rs:94-96
先例同形（`std::env::home_dir()` 同源），内联测试+`open_in(None)` 双钉。

## 三、三探针复核（与源码互证）

| # | 断言 | QA 互证结果 |
|---|---|---|
| ① | serde JSON 往返+精确形态 | **成立**。derive 源头亲核：`GameInputBinding`/`GameActionDef` 带 `Serialize+Deserialize`（game_input.rs:47/:81），runtime bevy features 含 `"serialize"`（KeyCode serde 编译在案）。测试钉死的精确串（`"KeyW"` 裸串/外层 externally-tagged 变体/`MouseMotion` 单元变体裸串）与 serde 默认形为逐字相符；envelope 全链往返+同构 build 零 warn 同测试在案 |
| ② | dirs macOS 形态+两层兜底 | **成立**。macOS 断言（`ends_with("Library/Application Support/<id>")`+`starts_with(data_dir)`）；两层兜底=纯层级函数 `resolve_save_dir`（None 底边可构造，内联测试）+`open_in(None)`→NoDir 零 warn+写拒（M12 底边测试） |
| ③ | 反射注册→BRP 全类型路径 | **成立，T16-T1 教训转常驻确认**。对照半亲核：未注册 `SaveStore<TestProfile>` 时 registry `contains(TypeId)` =false（泛型不入 auto-inventory 实证）；绿半注册三件（store/status/profile T）后 `ReflectSerializer` 产出以全路径 `jackdaw_runtime::save::SaveStore<save_store::TestProfile>` 为键、profile/status/dirty 三字段全可读、status 单元变体读作 `"NoDir"` 字符串——机制本体与 fork `builtin_methods.rs:761-763`（BRP `world.get_resources` 走 ReflectSerializer）亲核同源。**T2 真机腿按此键名查询** |

探针以常驻断言落位（非一次性脚本）+红证先归档（`t17t1_save_store_red.log` 18 个 E0432/E0433
实录，QA 抽验属实）——T16-T1 教训的吸收形态合格。

## 四、lock 连带面核查

1. **工作区 Cargo.lock diff 恰一行：属实**（`git show e589257f -- Cargo.lock` = jackdaw_runtime
   依赖列表加 `"dirs"` 一行）；scaffold 快照 `a_new_game_carries_the_workspace_lock_snapshot`
   在 fast（:2192）与 libtests 双通道 PASS 亲核（include_str 编译期自动重嵌）。
2. **fixture 锁刷新：属实**。`tests/fixtures/bsn_game/Cargo.lock` 的 jackdaw_runtime 依赖行含
   `"dirs"`（亲读）；`.gitignore:7` 确证该件为 gitignored 本地件——**偏差 3 的口径澄清正确**；
   QA 复跑 `cargo build --locked` EXIT=0。
3. **⚠ 报告「bevy git rev 两锁同为 ae61521 逐字核对」不成立（QA 实锤，回流 A）**：
   工作区 Cargo.lock **不含任何 bevy git rev**——根 Cargo.toml:439 `[patch."https://github.com/
   bevyengine/bevy"]` 把 bevy 指到本地 fork 路径（`/Users/zhanglinbo/workspace/bevy-fork-pinned`，
   path 依赖在 lock 中无 source 行，亲读 :622-625）；fork HEAD=`9cb82e77`（=上游 `c9c397ba`+
   2 本地提交，`jackdaw-pinned-rev` 文件记录的是 **c9c397ba**，非 ae61521）。**只有** fixture 锁
   持 git rev `ae61521`（71 处引用，fixture 无 [patch]、直连上游 git）。即：两锁的 bevy 解析
   形态根本不同（fork 路径 vs 上游 rev），「同为 ae61521」无从核对也非事实。**实质性影响=零**：
   单行 diff/快照测试/`--locked` 三项真不变式全绿，且 bevy 解析分叉是本任务之前既存的仓库架构
   （fixture 独立解析上游=模拟用户工程），T17 diff 只碰 dirs 一行。处置建议：主控责令程序修订
   报告 §四该句（或 QA 本报告为准），无需代码动作。
4. **teaches 口径亲核**：fast 日志中 `jackdaw_scaffold` lib 测试恰 **90**（=T16 基线，报告
   「teaches 90 不动」属实）；2989=2987+2 分解成立。

## 五、偏差裁定（程序 7 条+QA 新增 3 条）

**程序自报 7 条，QA 全部裁定 ACCEPT（0 条需返工）**：

| # | 偏差 | 裁定 | 依据 |
|---|---|---|---|
| 1 | save.rs 761 行 vs 方案 200-250 | **ACCEPT** | 超出部分=方案自指机制的实尺寸（迁移走+warn 表+手写 RFC3339+doc）；家族区间正常（game_input.rs 766）；「薄」在依赖面（零新解析栈/零时间库/一行 dirs）成立；RFC3339 手写器有 3 针测试+`date -u` 对表兜底 |
| 2 | `Recovered{backup: Option<String>}` | **ACCEPT** | rename 失败时状态不说谎+单行 warn 随行（damaged 路径亲读）；BRP 面多数字路径有值 |
| 3 | fixture lock=gitignored 本地件 | **ACCEPT** | `.gitignore:7` 亲核；`--locked` 冷编实证+QA 增量复跑双证；新工程侧由快照测试兜住 |
| 4 | `save_dir` 入 prelude | **ACCEPT** | ConfigPlugin/InputActionsPlugin 同款心智 |
| 5 | `flush_saves` pub | **ACCEPT** | `apply_config_defaults` pub 先例；默认已由 plugin 挂 Update |
| 6 | 中途三轮 clippy 红+覆盖归档 | **ACCEPT** | 最终树清零+最终重跑覆盖归档=纪律正确执行；save_store 红证独立保留（18 错实录抽验属实） |
| 7 | 测试 828 行 | **ACCEPT** | 17 测试=矩阵 H 侧 8 格+三探针+红绿对，断言密度对得起行数，无注水 |

**QA 新增（回流清单 A-C，均非代码缺陷）**：

- **A（须修订报告）**：§四-3 bevy rev 句失实（详见前节）。
- **B（归档口径注记）**：程序报告称 fixture 冷编 1m49s，但归档 `t17t1_fixture_locked.log` 只剩
  最终增量过（0.47s，覆盖归档所致）；fixture `target/` mtime（21:35 建→21:49 成品）佐证冷编
  确曾发生，QA 复跑绿——结论不受损，建议报告补一句「冷编时长以 mtime 佐证、归档为最终增量」。
- **C（doc 注记建议）**：迁移越顶（0→5→Loaded）与超 u32 版本（→Recovered）两个边界语义实现
  正确（QA 探针实弹）但 doc 未记；warn 计数括注松散（实际=9 处 `warnings.push`+2 处直呼
  `warn!` =「11 处」总数对，分支拆法对不上；`game save:` 前缀全覆盖亲核成立——load 侧 9 支
  全经两处 `warn!("game save: {warning}")` 泵出，写侧 2 处直呼自带前缀）。

## 六、移交 T2 的交接面（QA 视角补充）

1. **BRP mutate 不置 dirty**（全状态通用，不止 VersionSkipped）：direct BRP 改 `SaveStore<T>`
   本体不触发自动落盘；T2 的 M3/L2 腿必须改 config 资源（GameAudioConfig 等）走模板 watcher→
   `get_mut`→dirty 链，或显式调 `write()`。程序报告 QA 注记 2 只对 VersionSkipped 说了半句，
   T2 脚本设计按全状态口径执行。
2. BRP 资源键=全类型路径（探针③实读形态）；status 读变体名字符串，data 变体带 `backup`/`found`。
3. `JACKDAW_SAVE_DIR` 整体替换=脚本标配（L1-L8 全腿设它指 scratch，防写真档——本轮 QA 已实测
   测试面零真档残留，同纪律延续）；warn 扫描词表新增 `game save:` 前缀，健康首跑应零命中。
4. 桥系统时序险点（authored 注入覆盖恢复值）的 runtime 侧支撑已就位：`apply_config_defaults`
   pub 可见+`.after` 排序方案在案，T2 落地时以 M6 红绿验证。

## 七、裁决

**PASS**。依据浓缩：八门禁亲跑全绿（fast/libtests 双通道 2989、scaffold teaches 90、
save_store 17/17、AN2 1/1、物理双包/fmt/全仓 clippy deny-warnings 零红）；761 行源码级审查
四专项（三态守卫三先例同构/VersionSkipped 双钉真能捕违规/原子写合规/迁移链单调+环界实弹验证）
全成立；三探针与源码互证无虚；lock 连带实质三项全绿、唯一失实是报告一句 bevy rev 口径
（回流 A，零代码影响）；偏差 7 条全 ACCEPT，QA 新增 3 条均非阻断。**放行 T17-T2**（模板
save 段+bsn_game 双跑 e2e+t17-live.sh 真机矩阵 L1-L8），交接面按 §六。

—— QA（loop 自动化验收）2026-10-30
