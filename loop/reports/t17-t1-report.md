# T17 任务 1「runtime 存档薄层」程序报告

> 分支 `loop/t17-save`（自 main 96bbc159）；任务书 `loop/plans/t17-save-settings.md` §四-T1；
> 主控裁定 8 决策点全按建议执行（1=用户目录 `dirs::data_dir()/<game-id>`+`JACKDAW_SAVE_DIR`
> 缝 / 2=JSON envelope+save_version / 3=`jackdaw_runtime::save` 第四家族模块 / 4=版本守卫+
> 默认回退+可选迁移链 / 5=dirty 自动落盘+显式 API 同在+VersionSkipped 抑制不变式 / 6=PIE 同槽
> （运行时侧零特判，语义注记归 T2/book）/ 7=T2 范围 / 8=SaveStore\<T\> Reflect Resource+status
> 枚举）。改动 3 文件 +19/−1 + 2 新文件（save.rs 761 行、tests/save_store.rs 828 行）+7 归档
> 日志。零 fork 改动、零编辑器产品代码改动、零场景格式变更、零新 BRP 方法、零模板改动
> （模板段=T2）。

## 〇、首步三探针结论（必记项）：三项全定案，零回落

探针全部以**常驻断言**落位 `crates/jackdaw_runtime/tests/save_store.rs`（17 测试全绿），
红态实录先归档（§三）。

| # | 探针 | 结论 |
|---|---|---|
| ① | **serde 往返**（GameInputBinding/GameActionDef JSON 形态钉死） | **成立**：T09 的 serde derive（game_input.rs:49/:83）+runtime bevy `serialize` feature 下 JSON 路径无损往返；**精确形态已钉进测试**：`{"name":"Move","kind":"Axis2D","bindings":[{"Key":"KeyW"},{"MouseButton":"Left"},"MouseMotion",{"GamepadButton":"South"},{"GamepadAxis":{"axis":"LeftStickX","deadzone":0.15}}]}`——KeyCode 序列化为裸字符串（`"KeyW"`），外层枚举是 tagged 变体。存档文件=人可读 JSON，QA 可直接 jq。经 envelope 全链往返（写→读→逐字段相等+Loaded）也在同一测试钉住 |
| ② | **dirs::data_dir() macOS 形态 + None 兜底** | **成立**：macOS `dirs::data_dir()`=`~/Library/Application Support`（常驻断言 `the_save_directory_lives_in_application_support_on_macos`，存档目录=其下 `<game-id>`）；None 兜底分两层测：纯层级函数 `resolve_save_dir(data_dir, home, id)`（save.rs 内联测试——env 已在其上层；data>home(`~/.local/share/<id>`,即 Linux data_dir 形态)>None）+ `open_in(None)` → `NoDir` 安静默认+写拒绝（M12 底边）。本机 macOS 恒有该目录，None 分支为异形环境保险 |
| ③ | **反射注册 → BRP components/资源表含 SaveStore\<T\>** | **成立（T16-T1 教训转正常备断言）**：泛型资源**不在 reflect auto-inventory**——对照半：`insert_resource(SaveStore<TestProfile>)` 后注册表 `contains(TypeId::of::<SaveStore<TestProfile>>())` 为 **false**（save_store.rs 常驻断言）；`SavePlugin::build` 显式 `register_type::<SaveStore<T>>()`+`SaveStatus`+**profile 类型 T 本身**三件后，`ReflectSerializer`（BRP `world.get_resources` 的机制本体，fork builtin_methods.rs:761 同款）产出 `{"jackdaw_runtime::save::SaveStore<save_store::TestProfile>":{"dirty":…,"profile":{…},"status":"NoDir"}}`——**资源以全类型路径为键**（QA 的 BRP 查询按此键名走），profile/status/dirty 全可读；status 枚举单元变体序列化为变体名字符串 |

## 一、模块形态（save.rs，第四家族成员）

`crates/jackdaw_runtime/src/save.rs`（761 行：代码 469+模块 doc 140+空行~85+内联测试 2 件）；
lib.rs `mod save;` + 根 `pub use`（SaveError/SaveMigration/SavePlugin/SaveStatus/SaveStore/
SAVE_DIR_VAR/SAVE_FILE/SAVE_VERSION/flush_saves/save_dir）+ prelude 加
SaveMigration/SavePlugin/SaveStatus/SaveStore/save_dir。Cargo.toml 加 `dirs.workspace = true`
一行（工作区已有 dirs="6"，不入 jackdaw_env——编辑器品牌层+libc/windows-sys 拖挂，事实七）。

- **envelope**：`SaveEnvelope<T> { save_version: u32, saved_at: String(RFC3339 UTC 秒精度),
  profile: T }`——格式契约类型公开+doc 钉死；serde_json pretty 写出，字段序
  save_version→saved_at→profile（原始文本前缀断言钉住）。
- **SavePlugin\<T\>::new(game_id)**+`.with_migrations(Vec<SaveMigration>)`：build 内同步加载
  （文件小且本地，无 async——flow.rs 启动线先例），**store 在第一帧前就位**（config.rs 先例，
  M1 断言）；Update 挂 `flush_saves`；注册反射三件（探针③）。
- **SaveStore\<T\>**（Resource+Reflect，`#[reflect(Resource)]`）：公开面恰为
  `profile: T`+`status: SaveStatus`+`dirty: bool`（BRP 断言面，决策 8）；私有
  dir/migrations/warned_write_failure 均 `#[reflect(ignore)]`。
- **SaveStatus**：`Fresh`（无文件，安静）/`Loaded`/`Recovered { backup: Option<String> }`/
  `VersionSkipped { found: u32 }`/`NoDir`——**status 是 BRP 可断言面的一部分**（探针③实读）。
- **API**：`get_mut()`（置 dirty）/`write()`（显式）/`reload()`（重读，弃内存改动）/
  `reset_to_default()`（刻意丢弃，唯一解除 VersionSkipped 守卫的门）/`dir()`/`save_file()`。
- **目录解析**：`save_dir(game_id)` = `JACKDAW_SAVE_DIR`（**整体替换**，非子目录拼接）>
  `dirs::data_dir()/<game_id>` > `~/.local/share/<game_id>` > None→NoDir；文件
  `<dir>/save.json`；**目录惰性创建**（load 永不建目录——M9 断言「首跑零目录」）。
- **三态守卫**：缺文件安静默认（flow.rs 先例）；坏读/非 UTF-8/坏 JSON/非对象/未知字段点名
  忽略/缺 save_version/缺 profile/profile 不符 schema → **warn 逐分支（flow.rs:90-142 warn
  表形态）+`.corrupt-<millis>` 备份（project.rs:338 先例形态，rename 非复制，一次一档，
  SV7 不清理）**；版本守卫：高于 SAVE_VERSION（降级守卫）与低于且未注册迁移 →
  `VersionSkipped{found}`+warn+**自动落盘抑制**；注册迁移 → 链式上爬（单调性检查+环检查+
  apply 失败降级 VersionSkipped，永不动盘）→ `Loaded`。
- **不变式（写进模块 doc 首节+两处实现点）**：`VersionSkipped` 态 `flush_saves` 静默跳过+
  `write()` 拒绝返回 `SaveError::VersionGuard{found}`——绝不把读不懂的存档用默认值覆盖；
  `Recovered` 例外（原文件已在备份里），允许覆盖。测试双钉：mutate+flush×3 帧后盘上字节
  逐字节相等（M10）+显式 write Err 后仍相等。
- **原子写**：tmp(`save.json.tmp`)+`sync_all`+rename（texture_import.rs:159-163 先例形态）；
  残 tmp 被下一次写整吞、loader 永不把 tmp 当存档（常驻断言）。
- **写入双轨**（决策 5-A）：dirty 自动落盘（`flush_saves`，Update 一帧内落）+显式 `write()`
  同在；写失败 dirty 保留（不静默丢改动）+**失败态迁移沿单次 warn**（`warned_write_failure`
  防 warn 刷屏——config.rs loader 自灭纪律的写侧形态），恢复可写后重试成功。

## 二、H 侧矩阵落位（tests/save_store.rs，17 测试全绿）

| 格 | 测试 | 断言要点 |
|---|---|---|
| M1 双 App 重启恢复 | `a_save_survives_the_process_boundary_between_two_apps` | app1 get_mut 四字段+一帧 flush→drop→app2：Loaded+逐字段相等+dirty=false |
| M9 缺文件 | `a_missing_save_file_starts_fresh_quietly` | Fresh+零 warn+默认+**目录未被创建**（惰性建目录活证） |
| M10a 新版本 | `a_newer_save_is_never_overwritten_automatically` | v99→VersionSkipped{99}+flush×3 字节不变+write Err{VersionGuard 99}+reset_to_default 后 v1 落盘 |
| M10b 旧版无迁移 | `an_older_save_without_a_migration_is_suppressed_too` | v0→VersionSkipped{0}+warn 非空+write Err+文件不动 |
| M10c 迁移链 | `a_registered_migration_upgrades_an_older_save` | v0→(0→1 迁移注入字段)→Loaded+旧值保留+下次写戳 v1；apply 失败→VersionSkipped+文件不动 |
| M11 损坏四形态+schema 漂移 | `a_corrupt_save_is_backed_up_and_the_game_runs_on` | 五形态（烂 JSON/空文件/二进制垃圾/半截文件/错类型 profile）全 Recovered+备份字节逐字节原样+默认+warn+下一写复活 |
| M11 备份不互踩 | `every_corrupt_load_leaves_its_own_backup` | 两次损坏→两个备份、各含各的原始字节（SV7 记档口径） |
| M12 目录异常 | `an_unwritable_directory_warns_and_the_game_keeps_running`（unix） | 只读目录 write→Err{Io}+dirty 保留+内存照跑；恢复权限后重试落盘 |
| M12 NoDir | `a_missing_directory_is_a_quiet_nodir` | open_in(None)→NoDir 零 warn+write Err{NoSaveDir} |
| M7 输入合并 | `the_saved_input_table_merges_with_the_defaults_as_a_union` | 存档改绑经 `merge_actions`：同名生效、缺省动作保留全表 |
| env 缝 | `the_environment_seam_moves_the_whole_save_directory` | JACKDAW_SAVE_DIR 整体替换（非子目录） |
| 原子写 | `a_stray_temp_file_is_never_taken_for_a_save` | 残 tmp≠存档（Fresh）+写吞 tmp+落正主 |
| envelope 形态 | `the_on_disk_envelope_shape_is_pinned` | 三字段+字段序+RFC3339 形态+profile 逐字段 |
| flush 红绿对 | `the_flush_system_is_what_carries_a_mutation_to_disk` | **红半**：无 flush 系统 5 帧不落盘（本模块之前的每个游戏的形态）；**绿半**：plugin 一帧落盘 |
| 探针①②③ | 3 件（§〇） | 常驻 |

外加 save.rs 内联 2 件（目录层级 None 底边+RFC3339 三针：epoch/闰日 2000-02-29/2026 当代秒，
与 `date -u -r` 对表）。

## 三、红→绿证据

| 腿 | 红证 | 绿证 |
|---|---|---|
| 测试先行 | `t17t1_save_store_red.log`（**先写测试后建模块**：18 个 E0432/E0433 未解析错误——SaveStore/SavePlugin/save_dir 不存在，EXIT=101 实录） | `t17t1_save_store.log` 17/17（EXIT=0） |
| flush 系统 | 同文件内红半（无系统 5 帧不落盘，config.rs `app_with_assets(with_system)` 先例形态） | plugin 一帧落盘 |
| 反射注册 | 探针③对照半（未注册泛型资源=注册表不可见） | 三件注册后全路径键序列化 |
| VersionSkipped 抑制 | —（新不变式，红=代码形态） | M10a 字节级断言（flush×3+显式拒绝后盘上原档未动） |
| lock 连带 | — | §四 lock 两行 |

门禁中途红→绿的迭代如实记录：fast 第 1/2/3 轮各抓到 clippy 红两处（save.rs `manual_let_else`
两处、测试 `bool_assert_comparison` 一处）——已修并在**最终树重跑覆盖归档**（归档纪律：
旧红日志被最终绿覆盖，仅 save_store 红证以 `_red.log` 独立保留）。

## 四、门禁（最终树重跑，日志归档 `loop/reports/t17t1_*`）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check`（fast 首步） | **CLEAN** | t17t1_fast.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings`（fast 步） | **CLEAN**（0 `warning:` 行；19 个 "error" 命中全为 PASS 行中的测试名，逐条归因） | t17t1_fast.log |
| 单测 | `cargo nextest run --profile ci --workspace --lib --features dylib`（fast 步） | **2989/2989（基线 2987+2 save.rs 内联）** | t17t1_fast.log |
| fast | `cargo xtask fast` | **exit 0，全文复核 0 真错误/0 FAILED/0 Diff** | t17t1_fast.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | **CLEAN（exit 0）** | t17t1_clippy_physics.log |
| AN2 腿 | `cargo nextest run --profile ci -p jackdaw_runtime --features animation --test animation_scene_load` | **1/1（exit 0）** | t17t1_an2.log |
| runtime 套件 | `cargo test -p jackdaw_runtime`（全部测试二进制） | **全绿**（lib 42 含 save 内联 2；save_store 17；其余件全过） | t17t1_runtime_suite.log |
| scaffold lock 快照 | `a_new_game_carries_the_workspace_lock_snapshot`（fast libtests 内） | **PASS**（:2238——快照 include_str 自动随 Cargo.lock，两侧同源） | t17t1_fast.log |
| fixture --locked 冷编 | `cargo build --locked`（tests/fixtures/bsn_game） | **过（1m49s，exit 0）**——`cargo update -p jackdaw_runtime` 后 `dirs` 入其 jackdaw_runtime 依赖行 | t17t1_fixture_locked.log |
| 磁盘 | `df`（门前） | 90Gi 可用（12% 用量），无需清盘 | — |

**lock 两处连带验证**：①工作区 `Cargo.lock` diff=**恰一行**（jackdaw_runtime 依赖列表加
`"dirs"`；`git diff Cargo.lock` 实录）——scaffold 快照 include_str 编译期自动重嵌，快照测试
PASS 即证；②`tests/fixtures/bsn_game/Cargo.lock` 为 **gitignored 本地件**（.gitignore:7
`tests/fixtures/**/Cargo.lock`——本轮澄清：T16 报告口径的「fixture Cargo.lock 刷新」指本地
文件而非入库件），已 `cargo update -p jackdaw_runtime` 刷新，`--locked` 冷编过=验收实证，
bevy git rev 两锁同为 `ae61521` 逐字核对。

**warn 形态扫描**：fast 日志 0 `warning:` 编译行；runtime 套件日志仅测试名含 "warn" 的 PASS
行。存档域新增 warn 共 11 处全为「game save: 」前缀的可归因形态（load 守卫 7 分支+写拒绝+
写失败+迁移 3 分支），QA 的 M14 扫描口径：**`game save:` 行出现即存档域有事**，每行自带
路径与回退说明；损坏态伴随 `save.json.corrupt-<millis>` 落盘可盘断。

## 五、偏差清单（如实）

1. **⚪ save.rs 体量超方案估计**：方案「~200-250 行」，实际 761 行（纯代码 469+doc 140）。
   超出部分是方案自身指定的机制面的真实尺寸：版本守卫+迁移链走（单调/环检查）~110、
   load warn 分支表 ~90、RFC3339 手写器（无 chrono/time 依赖，civil-from-days ~50）+
   契约 doc ~140。对比家族成员（config.rs 469 行、game_input.rs 766 行）属正常家族区间，
   「薄层」定性不破（薄在**依赖面**：零新解析栈、零时间库、一行 dirs）。
2. **⚪ `Recovered { backup: Option<String> }` 的 Option**：方案写 `Recovered{backup}`（裸
   字符串）；rename 失败时（目录只读等）状态不得说谎，`None`+单行 warn 才诚实。BRP 断言面
   不受损（多数路径有值）。
3. **⚪ fixture Cargo.lock 系 gitignored 本地件**（.gitignore:7）：方案事实十二与 T16 口径
   均按「入库文件同刷」叙述；实际它不入库，刷新=本地 `cargo update`+`--locked` 冷编实证
   （已做）。对新工程冷编的 `--locked` 验收由 scaffold 快照测试+快照 include_str 自动性
   共同兜住。无残留工作，仅口径澄清。
4. **⚪ `save_dir` 入 prelude**：方案未点名；config/game_input 家族的 plugin/路径函数均在
   prelude（`ConfigPlugin`/`InputActionsPlugin` 同款），save 一并保持心智一致。
5. **⚪ flush_saves 公开导出**（方案列为系统未言可见性）：沿 `apply_config_defaults` pub
   先例——游戏要自定义调度时有得用；默认由 plugin 挂 Update，无需游戏动手。
6. **⚪ 门禁三轮 clippy 红**（manual_let_else×2+bool_assert_comparison×1）：仓库
   `-D warnings` 全仓 clippy 比单测更早抓风格；最终树已清零，fast 覆盖归档。
7. **⚪ 测试文件 828 行**（方案未预估）：M 矩阵+三探针+红绿对的断言密度所致，与
   game_flow.rs（~370）+config.rs 内联测试的家族密度一致偏上，无注水。

## 六、给 QA 的注意事项

1. **BRP 键名**：资源以全类型路径回答——`jackdaw_runtime::save::SaveStore<jackdaw::…GameSave>`
   形态（探针③实测模板外壳为 `SaveStore<save_store::TestProfile>`，泛型参数是**消费侧
   crate 内类型路径**）；T2 真机腿查 `world.get_resources` 时按此键找，status 读变体名
   字符串（`"Fresh"/"Loaded"/"Recovered"/"VersionSkipped"/"NoDir"`；data 变体带
   `backup`/`found` 字段）。
2. **VersionSkipped 是行为态不是错误态**：该状态下 BRP mutate 会成功改内存但**盘不落**——
   真机腿若见「mutate 了但 save.json 没动」，先读 status 再查 warn（`game save:` 行说原委）；
   `reset_to_default` 是唯一出 guard 的门（示例游戏不该走到，读到即记 SV 票）。
3. **env 缝是脚本标配**：`JACKDAW_SAVE_DIR` **整体替换**存档目录（不拼 game-id 子目录）——
   t17-live.sh 的 fixture 工程腿务必设它指向 scratch，否则 PIE/direct 会写真档（决策 6-A
   同槽语义）；「存档与场景分开」的盘断言路径形态=`~/Library/Application Support/<game-id>/
   save.json`（seam 未设时）。
4. **warn 扫描口径**（M14 预期归因表）：`game save:` 前缀=存档域warn（健康启动零命中；
   L1 首跑 Fresh 应零 warn）；`cannot apply`/`UnresolvedTypes` 照旧零容忍；`save.json.tmp`
   在盘出现且持久不消=原子写中断疑点（正常只在写的一瞬间存在）。
5. **无 RUST_BACKTRACE 口径照旧**；本任务测试全部 headless 无设备依赖，`#[cfg(unix)]` 两腿
   （只读目录+无）在 Windows 开发机上自动缩编（存档域无 Windows 专属断言缺口，QA Mac 本机
   全量跑）。
6. **T2 衔接面**：桥系统三件（apply_saved_audio/.after(apply_config_defaults) 排序、
   apply_saved_input union、写侧 watcher）+GameSave profile+`register_type` 一行+模板段
   归 T2；runtime 侧契约=§〇/§二 全部常驻断言，QA 可直接引用其测试名做回归清单。
7. **未动面**：buglist/台账/roadmap 未改（T3 口径）；scaffold teaches 90 不动（模板段=T2
   才新增 teaches）；SV2-SV4/SV6-SV8 处置与真机矩阵归 T2/T3。

## 七、产物清单

- `crates/jackdaw_runtime/src/save.rs`（新，761 行）
- `crates/jackdaw_runtime/tests/save_store.rs`（新，828 行，17 测试）
- `crates/jackdaw_runtime/Cargo.toml`（+dirs.workspace = true，5 行）
- `crates/jackdaw_runtime/src/lib.rs`（mod/pub use/prelude，+14 行）
- `Cargo.lock`（+1 行）
- 归档：`loop/reports/t17t1_{save_store_red,save_store,runtime_suite,fast,clippy_physics,
  an2,fixture_locked}.log`（7 件）
