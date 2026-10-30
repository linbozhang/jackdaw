# T17 游戏存档与玩家设置 — 实施方案

> 需求来源：`loop/plans/roadmap-game-dev.md` T17（P1 第十二项，T01-T16 已闭环）。
> **验收原文**（roadmap 第 31 行，逐字核实）：「**运行时存档接口+示例（进度/解锁/音量/输入设
> 置），与场景文件分开。验收=重启恢复；缺文件/旧版/损坏安全回退不崩。**」
> 基线：本地 main **d34606e0**（T16 收官合入）。本方案基于该基线全量只读调研：
> `crates/jackdaw_runtime/`（Cargo.toml feature 图+lib.rs 插件面+config.rs/game_input.rs/
> flow.rs 三模块全文+tests/ 26 文件清单）；`crates/jackdaw_scaffold/templates/game/`（src/
> lib.rs.template 1,281 行+assets 全件）；`crates/jackdaw_api_internal/src/document.rs`（write_
> atomic）；`src/project.rs`/`src/project_settings.rs`/`src/scene_io/session_journal.rs`（T04 链）；
> `crates/jackdaw_env/src/paths.rs`；`crates/jackdaw_project_build/src/{export.rs,bevy_source.rs}`；
> `crates/jackdaw_scaffold/src/lib.rs`（lock 快照）；fork `/Users/zhanglinbo/workspace/bevy-fork-
> pinned/crates/bevy_remote/src/builtin_methods.rs`；`tests/util/mod.rs`+`tests/fixtures/bsn_game/`；
> `xtask/src/main.rs`；`loop/qa/t16-live.sh`；`buglist.md` 全量 save/存档/设置域扫描。**零临时探
> 针**——全部结论为静态可复核事实（存档域在 fork 与 runtime 侧的「零成晶」判定靠 grep 零命中
> 实证，不需要跑任何东西）。
> **任务定性：纯建设型（约 75/25 偏建设）——T12/T15/T16 的「成晶 vs 缺口反转读法」第四次适用，
> 结论第一次是「机制层零成晶」**：fork 无存档系统（bevy_save 非官方、不在依赖树，fork crates/
> 与 Cargo.lock grep 零命中）、`jackdaw_runtime` 与模板**零存档面**（「玩家数据在进程重启后存
> 活」的通路今天不存在）；成晶的是**纪律与原语**——三态安全回退纪律三处先例（T08 config 缺文
> 件回退/T13 flow 容错解析/编辑器 project_settings 三态默认）、原子写先例两处（编辑器
> write_atomic+runtime 自有 texture_import tmp+rename）、T09 输入面 serde+union merge、T16 音量
> config 资产+BRP 读面。建设面=runtime 存档薄层（~200-250 行）+模板示例段（~100-120 行）+验
> 收矩阵。缺陷候选按 **SV 系**编号（Save，避开 buglist R/Y/W/A/N 系与 T01-T16 各任务编号系
> U/I/F/C/PF/AN/AU），只记不修→主控裁定吸收面。
> 真机口径：**macOS（本机）**，bash+curl+jq 驱动游戏 BRP 15702（fixture 注入 `jackdaw_remote`，
> t16-live.sh:458-461 同款两行 sed）；direct run 为主、PIE 单腿（N13 记数+A10 绕行）；**勿设
> RUST_BACKTRACE**（T11-T3 口径，buglist N13 更新：Mac debug 构建 RUST_BACKTRACE=1 → wgpu
> LockTrace→libunwind SIGSEGV）；warn 形态扫描（`save|corrupt|UnresolvedTypes|cannot-apply`）
> 以 `$PHASE` 日志名入常备腿（A7 教训原文）；**存档验证的断言大头走文件系统与 headless 双 App，
> BRP 依赖低**（撞 A9 面小于 T16，如实评估见 §三）。
> 工具债前置评估：**A7/A9/A10 均不前置，脚本自守**（§五决策 7）；A3（fork patch standalone 红）
> 与 A8（BSN 全路径）确认与本任务**无直接撞面**（全量 grep 见 §一重叠表）。

---

## 0. 架构事实（核实结论，方案的地基）

**总判断：T17 是在一张白纸上画最薄的一层——「玩家数据持久化」在游戏侧不是缺一块板，是整面
墙没砌；但每一块需要的砖（原子写、容错解析、版本守卫的三态纪律、union 合并、BRP 资源面、
config 资产桥）在仓库里都有烧好的先例，照抄纪律即可。** 十四条事实：

- **事实一：游戏侧零存档面（grep 全量实证）。** `jackdaw_runtime/src/` 19 个文件（10,466 行）
  中写盘的产品代码只有一处：`texture_import.rs:159-163` 把压缩纹理缓存写为
  `<file>.basis.partial` 再 `std::fs::rename`——**tmp+rename 原子写先例就在 runtime 自己家里**；
  读盘面有 `flow.rs`（game.flow.json 直读）与 catalog 走（assets 内）。`save|savegame|profile|
  SaveStore` 在 runtime/模板/`tests/fixtures/bsn_game` 全部零命中——「运行时存档接口」的
  「运行时」侧今天什么都不存在。模板（`lib.rs.template` 1,281 行）同理：GameFlow/GameState/
  PlayerHealth 全是易失态，进程一退 Menu/血量/重开计数归零。
- **事实二：fork 无存档能力，T17 不从引擎侧借力。** fork（`bevy-fork-pinned`）`crates/` 无
  bevy_save 族（`bevy_save` 是非官方 crate，不在本仓依赖树——Cargo.lock 零命中）；bevy 本体
  的持久化原语只有 `bevy_scene`/`bevy_world_serialization`（场景/世界序列化，正是「与场景文
  件分开」要分开的那个东西）与 DynamicScene。⇒ 存档薄层必须自建，且**不该**搭场景序列化
  （DynamicScene 挂实体/组件形态，与玩家档案的「一张小表」语义不符，还会把类型注册面拖进来）。
- **事实三：runtime 的模块家族形态=现成模板，save.rs 是第四个成员。** runtime 的「游戏侧
  系统面」三模块全部同构：`config.rs`（T08，ConfigPlugin\<T\> 资产→Resource 初值）/
  `game_input.rs`（T09，InputActionsPlugin 求值引擎）/`flow.rs`（T13，flow 文件读取）——
  都是「小模块+泛型插件+tests 同文件/同目录」的形态（lib.rs:103-121 模块声明；prelude 导出
  :185-198）。save.rs 照这个家族形态落位，游戏侧一行接线
  （`.add_plugins(SavePlugin::<GameSave>::new(env!("CARGO_PKG_NAME")))`）与 ConfigPlugin 同款
  心智。
- **事实四：T08 config 的三态回退纪律=「缺文件」验收词的直接先例。** `config.rs`：
  缺文件不是错误——`apply_config_defaults`（:147-208）对 catalog 无答的路径
  `warn!("no config asset at '{}'…")`+回落 `T::default()`（:196-205），loader 自灭（一次警告
  不逐帧刷）；插件 build 先把默认插进去（:130）保证任何读方不空转。**T17 的「缺文件→首跑
  默认」与这条纪律逐字同构**，差异只有一处：存档文件在用户目录不在 assets，不走 catalog/walk。
- **事实五：T13 flow 的容错解析哲学=「损坏安全回退」验收词的直接先例，且解析器形态可抄。**
  `flow.rs:16-21` 原文：「Every problem warns and falls back, never refuses: a broken, missing
  or mis-pointed flow file must describe itself in the log and still hand the game a scene to
  start from.」实现面（:90-142）用 `serde_json::Value` 容错解析+逐分支 warn（坏 JSON/非对象/
  未知字段点名忽略/错类型逐 JSON kind 报告）——**这张 warn 分支表就是存档文件解析面的模板**；
  `serde_json` 已是 runtime 依赖（`Cargo.toml:67`），零新增解析栈。
- **事实六：编辑器侧持久化链（T04）是纪律来源但不是同一件事——边界必须钉死。** 编辑器侧
  四件：①`write_atomic`（`jackdaw_api_internal/src/document.rs:105`，tmp+sync_all+rename+旧文
  件 `.bak` 单槽轮换 :96-99/:149-165）；②损坏配置先备份再重建：`project.rs:322-338`
  `back_up_corrupt_project_config` → `project.json.corrupt-<millis>`（T04-T1 修复，buglist Y9
  :134-138 在案）；③`project_settings.rs:31-39` `load_section` 缺文件/缺段/坏段一律
  `T::default()`；④崩溃 journal `session_journal.rs:1-21` → `<config>/state/sessions/<hash>/
  <pid>-<started>/`（2s 防抖，:35；KEPT_SESSIONS=5，:39）。**边界**：这些全是**编辑器进程**
  对「工程/编辑器自身状态」的持久化，活在 `jackdaw_api_internal`/`src/scene_io` 编辑器层——
  运行时游戏既不链接这些 crate（runtime Cargo.toml:10-68 依赖图无它们），也不该背「恢复编辑
  会话」语义。T17 只取其**纪律形态**：原子写+坏文件备份+默认回退；实现是 runtime 内自带的
  ~30 行小助手（texture_import 先例形态），**不**为它拉编辑器层依赖。
- **事实七：用户目录解析已有仓库约定，但 runtime 不能直接复用编辑器品牌层。**
  `jackdaw_env::paths.rs`（:6-10 `data_dir`=`dirs::data_dir()/jackdaw`，:33-40 `config_dir`，
  :71-78 `state_dir`，:31 `JACKDAW_CONFIG_DIR` 测试缝，:94-96 `home_dir()/.jackdaw` 兜底）——
  这是**编辑器**的品牌路径（常量名 `DATA_DIR_NAME="jackdaw"` :3）。一个发货游戏把玩家档案写
  进「编辑器目录」语义错位；`jackdaw_env` 还拖 libc/windows-sys（其 Cargo.toml 依赖段）。
  ⇒ runtime 直加 `dirs.workspace = true` 一行（workspace 已有 `dirs = "6"`，根 `Cargo.toml:
  297`），存档基目录=`dirs::data_dir()` 下**游戏自己的目录**（决策 1）。测试缝
  `JACKDAW_SAVE_DIR`（整体替换存档目录）与 `JACKDAW_CONFIG_DIR` 先例同构。
- **事实八：「与场景文件分开」的字面与三条硬理由。** ①字面：场景文件=assets 树内 `.bsn`，
  存档落用户目录即字面分开；②导出包是**只读分发形态**：`export.rs:1-26` doc 明言 dist=
  `<root>/.jackdaw/dist/<profile>/`（exe+assets 整树+`.jackdaw-export` 标记），T07 铁证链含
  「挪盘异目录启动」——装进 /Applications 或 Program Files 的包在程序目录写档不可行；③
  assets 树是编辑器资产走（`load_asset_files`，lib.rs:315 Startup）与 PIE temp 副本
  （`config.rs:444-467` 测试钉死「PIE temp 不影子化 config」）的地盘，玩家档案混进去既污染
  工程树又会被导出打包带走别人的进度。
- **事实九：四类数据三类已有载体，T17 是给它们各接一条「持久半边」。**
  - **音量**（T16）：`GameAudioConfig {master,music,sfx: f32}`（`lib.rs.template:439-458`，
    Default 全 1.0）经 `ConfigPlugin::<GameAudioConfig>::new("audio-config.bsn")`（:294-296）
    注入——**authored 默认值每次进程都注入，玩家改动无地方落**（T16 决策 3-A 明记「运行时
    UI 留 T17」+t16 方案 §七-7「T17 设置屏消费 GameAudioConfig」的移交原文）；`SoundLive`
    镜像（:479-493）=BRP 读面已在。
  - **输入设置**（T09）：`GameInputConfig`/`GameActionDef`/`GameInputBinding` 全部带
    `Serialize+Deserialize` derive（`game_input.rs:97-98/:83/:49`）——**存档 profile 可以直接
    嵌入该类型，序列化零新代码**；`merge_actions`（:233-246）union 合并（同名替换/缺省保留
    默认，防「文件里没有的动作被吃掉」）=「保存的改绑+游戏新增动作」合并语义的现成原语。
  - **进度/解锁**（T12）：挂点=`GameFlow`（Menu/Level/GameOver，`lib.rs.template:914-921`）+
    `on_screen_pressed` 观察者+`reset_run`（:1207-1217，每关重置 PlayerHealth 的现成「一局」
    边界）；`enter_menu/enter_game_over`（:339-341）=写档/读档展示的天然时刻。
- **事实十：BRP 资源面=真机断言通道，无需任何新方法。** fork `bevy_remote/src/builtin_methods.rs:
  79-92`：`world.get_resources`（:80）/`world.insert_resources`（:83）/`world.mutate_resources`
  （:89）全在；T16 真机腿已日用（`t16-live.sh:327` mutate GameAudioConfig 三字段先例）。
  `SaveStore<T>` 做成 Reflect Resource（决策 8）→「改值→触发写→读回」全链 BRP 直达。
  **T16-T1 教训直接适用：泛型类型不在 reflect inventory 自动注册——`SaveStore<T>` 与模板
  profile 类型须在注册点显式 `register_type`，否则 BRP 面静默缺席。**
- **事实十一：headless 双层测试锚都有现成位。** ①runtime 集成测试层：
  `crates/jackdaw_runtime/tests/` 26 文件（`game_flow.rs` 的 ENV_LOCK :23-26+tempdir 工程
  :46-52+`start_scene_in` 显式根缝绕开环境的读法=存档「显式目录缝」同款；`config.rs` 内联
  测试的 `run_until` 泵帧 :279-287）；该层走 `cargo xtask integration`（`xtask/src/main.rs:
  118-128` nextest --workspace --tests，全 crate 集成测试在档）——**runtime 的 bevy 依赖
  `default-features=false` 精简集（`Cargo.toml:11-28`）不含 bevy_audio/render，但存档模块只
  需要 prelude+serde_json，精简集全够**（T16 教训「锚不放 runtime dev 环境」在此不适用：
  音频那次是 feature 缺类型没法命名，存档零 feature 诉求）。②引擎级 e2e 锚：
  `tests/fixtures/bsn_game`（自带 Cargo.lock）+`tests/util/mod.rs:338/:352`
  `run_windowless_game(_until)`（stderr 标记等待，T16 音频 sink 标记行先例 :346-349 doc 原文）
  ——**双跑腿**（同一 fixture 二进制连跑两次、JACKDAW_SAVE_DIR 指同一 tempdir：第一次写、
  第二次断言恢复标记）=「重启恢复」的引擎级 headless 证明。
- **事实十二：fixture/真机腿形态全可复用，且新增一个依赖会触发两处 lock 连带。** fixture
  工程=`jd new`（t16-live.sh 同款），注入 `jackdaw_remote` 两行 sed（`t16-live.sh:458-461`），
  direct run 15702+`gbrp world.trigger_event`（:794-802 ScreenPressed 先例，绕开 A10 指针腿）。
  连带面：runtime 加 `dirs` 依赖 → ①scaffold 内嵌 workspace lock 快照必须刷新
  （`crates/jackdaw_scaffold/src/lib.rs:1255/:1265-1271` `include_str!("../../../Cargo.lock")`，
  T08-T1 前置 lockfix 机制：快照使 metadata 变好锁修剪器）；②`tests/fixtures/bsn_game` 自带
  Cargo.lock 同刷（T16 事实十五③同款告诫）。两处都是机械件，但漏掉任何一个=新工程/fixture
  `--locked` 冷编拒绝（A3 家族形态）。
- **事实十三：版本化格式没有现成件，「旧版安全回退」是唯一要全新设计的验收词。** 全仓文件
  格式无版本字段先例（flow.json 无版本、config bsn 无版本、journal.json 无版本——journal 靠
  目录名 pid-started 区分会话）。T17 的 envelope（`{"save_version":…,"profile":…}`）+版本守卫
  是**最小新建件**；迁移链做成可选注册项（不做强制——验收词只要求「回退不崩」，迁移是给
  游戏的加分 API）。**守卫的不变式有一条必须钉死：未来版本/未注册迁移的旧版本，自动落盘
  必须抑制——绝不把玩家的「读不懂的存档」用默认值覆盖回去**（写坏无法挽回；损坏态不同，
  它已有 `.corrupt` 备份兜底）。
- **事实十四：buglist 与 roadmap 邻域边界清楚，零重叠票。** save/存档/设置域全量 grep：
  Y9（:134-138，project.json/settings.json 原子写——T04-T1 已闭，编辑器侧）、R3（:30-35，T14
  已闭）、N14（:502，T11-T3 已闭，编辑器文档域）、Y27 族键位（编辑器键位非游戏侧）——
  **零条运行时游戏存档条目**（该域从未被任何用户通路触达，AU1 挡音频时的同构局面）。
  roadmap 邻域：T25（:42「运行态调参与选择性回写」）是**编辑器域**的白名单组件 Live 编辑回
  写到**资产**，与 T17 玩家数据写**用户目录**方向相反、互不侵犯——book 注记一句即可。T18
  （资产导入）、T20（示例游戏拼装）在 §七 衔接表说明。

### 验收句逐词定性（矩阵化的前提）

| 验收词 | 定性 | 依据 |
|---|---|---|
| 运行时存档接口 | **缺口（SV1 🔴，建设主体）** | runtime 零存档面、fork 零存档系统（事实一/二）；纪律先例全在（事实四/五/六） |
| +示例 | **缺口** | 模板 1,281 行零持久化段（事实一） |
| 进度 | **缺口（SV4）** | GameFlow/GameState 全易失态，重启必回 Menu（事实一/九） |
| 解锁 | **缺口（SV4）** | 全仓游戏侧零解锁概念（grep 零命中） |
| 音量 | **半缺口（SV2）** | GameAudioConfig 载体+BRP 面成晶（T16），但玩家改动每进程重置=持久半边缺（事实九） |
| 输入设置 | **半缺口（SV3）** | GameInputConfig serde 面+union merge 成晶（T09），改绑每进程重置（事实九） |
| 与场景文件分开 | **决策成晶** | 用户目录落位即字面满足；T07 dist 只读分发+PIE temp 先例三重硬理由（事实八） |
| 验收=重启恢复 | **缺口（建设主体）** | 三通道（headless 双 App/fixture 双跑/真机杀进程重启）全要新建；锚位现成（事实十一） |
| 缺文件→回退 | **纪律成晶** | config.rs 缺文件→default+一次 warn 先例逐字同构（事实四） |
| 旧版→回退 | **缺口（唯一全新设计件）** | 全仓无版本字段先例；envelope+守卫+可选迁移链自建（事实十三） |
| 损坏→安全回退 | **纪律成晶** | Y9 `.corrupt-<millis>` 备份先例+flow 容错解析 warn 表先例（事实五/六）；运行时自实现 |
| 不崩 | **断言新建** | 三态×headless+真机矩阵化（§二） |

---

## 一、缺陷候选（SV 系，只记不修→主控裁定吸收面）

| 编号 | 严重度 | 描述 | 证据 | 处置建议 |
|---|---|---|---|---|
| **SV1** | 🔴 | **游戏侧零存档面**：runtime/模板/fixture 无任何玩家数据持久化通路；fork 亦无存档系统可借——「运行时存档接口」的正主 | 事实一/二全链 | **吸收（本任务建设主体）**：runtime `save.rs` 薄层+模板示例（决策 3-A） |
| **SV2** | 🟡 | **音量设置易失**：玩家（或 BRP）改 `GameAudioConfig` 后重启即回 authored 默认，改动无处落 | 事实九（T16 决策 3 移交原文） | **吸收**：profile 音量段+加载桥（M13）；T16 移交的滑条素材按决策 7 落 |
| **SV3** | 🟡 | **输入改绑易失**：改绑/死区调整每进程重置；`GameInputConfig` serde+union merge 原语齐但无持久半边 | 事实九 | **吸收**：profile 输入段+union merge 恢复桥（M14） |
| **SV4** | 🟡 | **进度/解锁无概念**：GameFlow 重启必回 Menu，无 runs/解锁/检查点任何形态 | 事实一/九 | **吸收（示例段）**：`runs_played`+解锁示例（M2/M3 断言对象）；真实游戏的进度语义归游戏自己 |
| **SV5** | ⚪ | **runtime 无用户目录帮手**：`dirs` 不在 runtime 依赖图，`jackdaw_env` 是编辑器品牌层不可复用 | 事实七 | **吸收（SV1 附带一格）**：runtime 一行 `dirs.workspace = true`+存档目录解析函数 |
| **SV6** | ⚪ | **PIE 与 direct 共享用户存档槽的语义未定**：编辑器 Play 与真跑是同一二进制同一份存档——QA 迭代会反复写真档 | 事实八/十；`JACKDAW_PIE` 检测（pie.rs:31-46） | **决策 6 裁定**（建议 A：同槽=诚实语义+`JACKDAW_SAVE_DIR` 测试缝供隔离） |
| **SV7** | ⚪ | **损坏档 `.corrupt` 备份无清理**：每次损坏留一份，永不自动清 | Y9 先例同款行为（project.rs:338 不清理） | **记档不修**（量级=每次损坏一文件，无害；编辑器侧先例同语义） |
| **SV8** | ⚪ | **多存档槽/多档案（save slot 1/2/3、多 profile）无形态**：v1 单文件单槽 | 事实十三 | **记档（范围外）**：envelope+目录设计预留扩展位（saves/ 子目录），本轮不做 UI/槽管理 |

统计：🔴 1（SV1，验收缺口的建设面）｜🟡 3（SV2-SV4，持久半边三件）｜⚪ 4（SV5-SV8）。
SV5-SV7 全部随建设面自然吸收或如实记档，无独立修复任务。

### buglist 重叠表（save/存档/设置/profile 域全量扫描）

| 条目 | 一句话 | T17 处置 |
|---|---|---|
| （无） | **运行时游戏存档域 buglist 零条目**（全量 grep save/存档/存盘/进度/解锁/profile 零命中——游戏侧从未被触达） | 缺陷主体是本方案新发现的 SV1-SV8 |
| Y9 | project.json/settings.json 非原子写+损坏被默认静默覆盖（**T04-T1 已闭**） | **纪律来源**：`.corrupt` 备份先例照抄形态（事实六），无残留工作 |
| A3 | standalone 发货测试红：脚手架 [patch] 无条件注入本机 fork path（T11-T3 立账，**未闭**） | **无关确认**：T17 不改 fork/patch 面；但 runtime 加 dirs 会触发 lock 快照刷新（事实十二）——刷新不到位会以 A3 家族形态（--locked 拒绝）现形，列入 T1 连带清单规避 |
| A7 | 真机驱动脚本工具债（对话框+字段行定位 6 腿+陈旧 grep+截图 flake） | **前置评估=不前置（决策 7）**：T17 真机腿**零对话框零字段行定位**——驱动面=进程启停+gbrp 资源读写+文件系统断言，A7 家族咬不到；`$PHASE` 日志名写法直接吸收 |
| A8 | BSN crate 根 re-export 路径静默丢弃 | **知悉+低撞面**：T17 不新增 bsn 授权组件（profile/存档系统全 Rust 侧），仅 T16 已注册的 GameAudioConfig/既有组件被引用；模板 bsn 种子零新增 |
| A9 | 游戏 BRP 间歇空响应（构建/重试窗口高发，大响应体假说） | **自守不前置（决策 7）**：T17 的 gbrp 用量**中等偏低**（单资源读写，响应体天然小）；存档断言大头在文件系统与 stderr 标记（不依赖 BRP 活性）——撞面小于 T16；settle 重试+idle 探针照旧 |
| A10 | PIE 面板指针转发缩放布局未达 | **绕行**：真机腿以 direct run 为主（N13 同款口径）；若决策 7-A 落滑条，操作腿走 `world.trigger_event` ScreenPressed 链（t16-live.sh:794-802 先例）或 PIE 单腿记数 |
| N12 | bevy 原生与 jackdaw BRP 实体域互不相通 | **知悉+绕行**：游戏侧断言全 bevy 原生 `world.*`（资源读写不受实体域影响） |
| N13 | PIE connected 后 swap_remove panic 100% 复发 | **绕行+记数**：PIE 单腿；**勿设 RUST_BACKTRACE**（Mac debug 构建必 SIGSEGV） |
| 其余 | R/Y/W 系均为 prefab/brush/chrome 域 | 无动作 |

---

## 二、验收矩阵设计

**两铁证×通道=14 格主矩阵**。断言通道缩写：**H**=headless（`crates/jackdaw_runtime/tests/
save_store.rs`：文件系统三态+双 App 生命周期模拟，纯文件断言零设备依赖）；**H2**=引擎级
e2e（`tests/fixtures/bsn_game` 双跑腿，`run_windowless_game_until` stderr 标记）；**G**=真机
游戏 BRP 15702（fixture 注入 jackdaw_remote，bevy 原生 `world.get_resources`/`mutate_resources`
）；**盘**=文件系统断言（save.json 逐字段 jq/盘上 `.corrupt` 备份在案）；**PX**=截图。
「重启恢复」的诚实口径=**三个通道各自独立成立**（headless 证明逻辑、fixture 双跑证明引擎管
线、真机杀进程证明真实进程边界），缺一不勾。

### 铁证①：重启恢复（四类数据）

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| 生命周期模拟 | M1 | headless 双 App：App1 写档（四类值）→drop→App2 同目录重建→四类值逐字段相等+status=Loaded | 🔴SV1 前置；H |
| 引擎 e2e | M2 | bsn_game fixture 双跑：run1（JACKDAW_SAVE_DIR=tmp）走到 GameOver 写档打 `SAVE_WRITTEN` 标记→run2 同 dir 启动打 `SAVE_LOADED runs=1` 标记 | 🔴前置；H2 |
| 真机重启 | M3 | direct run→gbrp mutate 四类（进度/解锁/音量/输入）→自动落盘→`kill`→重启→`world.get_resources` 四类原样 | 🔴前置；G+盘（M2 盘侧逐字段） |
| 导出一致 | M4 | `game.export`→staged 异目录启动→同槽恢复 M3 所写值（用户目录不随包走，dev run 与导出 run 共享进度=「涉及数据的功能全链一致」的存档版） | 🔴前置；G+盘（T07 形态复用） |
| 分开铁证 | M5 | 存档路径在用户目录（盘断言路径形态）；assets/ 树零新增文件；导出包内无存档文件；PIE temp（`.jackdaw-pie/`）与存档目录互不相涉 | 🔴前置；盘（「与场景文件分开」的逐字落点） |
| 音量桥 | M6 | 未有存档时 GameAudioConfig=config 资产原值；有存档时=保存值；改 config 资产后存档仍在（两层叠加语义活证：authored default < player saved） | 🔴SV2 前置；H+G |
| 输入桥 | M7 | 保存的改绑经 union merge 恢复：同名列生效、游戏新增动作不丢（`merge_actions` 语义）；未存时=默认五动作 | 🔴SV3 前置；H |
| 进度/解锁示例 | M8 | GameOver 计数 `runs_played+=1` 写档；重启后 menu 可读；≥3 局解锁位翻转（示例数据面） | 🔴SV4 前置；H2+G |

### 铁证②：三态安全回退不崩

| 通道 | 格 | 内容 | 现状 |
|---|---|---|---|
| 缺文件 | M9 | 无文件首跑：quiet 默认（**零 warn**——flow.rs「无文件是安静默认」先例）+status=Fresh+游戏照跑；第二次写档建目录 | 纪律成晶（事实四）；H |
| 旧版 | M10 | envelope `save_version` 低于当前：未注册迁移→warn+回落默认+**自动落盘抑制**（不覆盖旧档）；注册迁移→升级读入（可选 API 单测）；高于当前（降级守卫）：warn+默认+抑制 | 全新建（事实十三）；H |
| 损坏 | M11 | 烂 JSON/空文件/二进制垃圾/半截文件四形态：均 warn+回落默认+**原文件 rename 为 `save.json.corrupt-<millis>` 备份在案**+不崩 | 纪律成晶（事实五/六）；H |
| 目录异常 | M12 | 目标目录只读/不可建：写失败 warn 不崩+内存态照常跑；`dirs::data_dir()` 为 None 的兜底路径单测 | H |
| 真机抽腿 | M13 | 真机损坏腿：手写烂 save.json→direct run 启动不崩+日志 warn+`.corrupt` 备份落盘+BRP 读到默认值 | 🔴前置；G+盘 |
| 横切·warn 形态 | M14 | 扫描 `save|corrupt|UnresolvedTypes|cannot-apply` 全程零意外命中（预期 warn 逐条点名） | 脚本常备腿（`$PHASE` 日志名） |

**矩阵统计**：🔴 修复前置 13 格（全部压在 SV1-SV4 建设面上）｜H 兜底 8 格（M1/M6/M7/M9-M12）｜
H2 引擎级 2 格（M2/M8）｜真机 4 格（M3/M4/M13/PIE 腿）。T1 清源（runtime 侧 H 全绿）、
T2 落判（模板+fixture+真机）。

---

## 三、真机腿清单（Mac，bash+curl+jq；T2 集中跑）

fixture 工程=`jd new` 出 `/Users/zhanglinbo/workspace/loop-mac/t17-save`（T14-T16 决策同款；
**建后注入 jackdaw_remote 两行 sed**（t16-live.sh:458-461 同款））。流程脚本
`loop/qa/t17-live.sh`（t16-live.sh 形态：prep/editor-free 直跑相+leg/summary/cleanup trap+
`$PHASE` 日志名 warn 扫描+N13 记数+A9 settle 重试助手）。**A7 撞面评估=零**：全部腿无编辑器
UI 驱动、无对话框、无字段行定位——驱动原语只有进程启停、gbrp 资源读写、文件系统断言
（存档域的天然优势，如实记录）。

| # | 腿 | 通道 | 为什么必须真机 |
|---|---|---|---|
| L1 | 首跑缺文件：direct run→BRP 读 SaveStore status=Fresh+四类默认值→盘上无文件（**不预先建目录**）→mutate 一次→盘上 save.json 出现 | G+盘 | 「缺文件→首跑默认」的真机活证+惰性建目录语义 |
| L2 | 四类写入：gbrp mutate（进度 runs、解锁位、audio master/music/sfx、input 一个改绑）→每步后盘上 save.json 逐字段 jq 断言（自动落盘时延=同帧） | G+盘 | 「文件是真相」的铁证（T08 纪律存档版） |
| L3 | **重启恢复正主**：kill -9→重启→BRP 读四类原样+status=Loaded | G+盘 | 验收句「重启恢复」字面；kill -9 排除优雅退出钩子假阳性 |
| L4 | 损坏腿：写烂 save.json（三形态抽一：空文件）→启动不崩→日志 warn 名中路径+`.corrupt-<ts>` 在盘→BRP 读默认值→再 mutate→新 save.json 正常 | G+盘 | 「损坏安全回退不崩」真机活证+备份先例活证 |
| L5 | 导出腿：`game.export`→staged 异目录启动→M3 值仍在（同用户目录槽）→包内无存档文件 | G+盘 | 「导出可跑且进度随人走」+M5 分开铁证 |
| L6 | PIE 单腿：PIE 启动→mutate→写盘→stop→direct run 读回（决策 6-A 同槽语义活证；N13 记数、A10 无涉——本腿零指针操作） | PIE+G+盘 | 编辑器 Play 与真跑同档的语义裁定证据 |
| L7 | 滑条腿（决策 7-A 裁定时）：direct run→`world.trigger_event` ScreenPressed 开暂停屏→滑条值变更（trigger 或 BRP mutate 滑条字段）→音量变→重启→滑条位置与音量同恢复 | G+PX | T16 决策 3 移交的设置屏兑现；trigger 链绕开 A10 |
| L8 | M14 warn 扫描全程+日志逐条点名核对 | 脚本 | 静默失败=存档域最毒形态（AU8 前科），warn 可见性必须常备 |

---

## 四、分任务拆解（T1/T2/T3）

### T1「runtime 存档薄层」（建设主体：SV1/SV5；决策 1/2/3/4/5/6/8）

1. **首步探针（半日，全静态可核）**：①**serde 往返探针**：`GameInputBinding`/`GameActionDef`
   JSON roundtrip 单测（serde derive 已在（game_input.rs:49/:83），bevy 输入类型
   KeyCode/MouseButton 的 serde 实现已编译在案——探针只钉 JSON 形态与往返稳定，防 bsn 反射
   路径与 serde 路径混同的错觉）；②**dirs 实测**：macOS `dirs::data_dir()` 返回路径形态单测
   （`~/Library/Application Support`）+None 兜底分支；③**反射注册探针**：
   `register_type::<SaveStore<T>>()` 后 BRP components 表含它（T16-T1 泛型教训转正为常驻
   断言）。
2. **`save.rs` 模块（~200-250 行，config.rs/flow.rs 家族形态）**：
   - envelope：`{"save_version": u32, "saved_at": String(RFC3339), "profile": T}`；
   - `SavePlugin::<T>::new(game_id)`（+`.with_migrations(Vec<Migration>)` 可选）；
   - `SaveStore<T>` 资源：`profile: T`+`status: SaveStatus`+`dirty: bool`；
     `SaveStatus::{Loaded, Fresh(NoFile), Recovered{backup}, VersionSkipped{found}, …}`——
     **status 是 BRP 可断言面的一部分**（决策 8）；
   - API：`write()`（显式）/`reload()`/`reset_to_default()`/`get_mut()`（置 dirty）；
   - 目录解析：`save_dir(game_id)` = `JACKDAW_SAVE_DIR` env > `dirs::data_dir()/<game_id>` >
     home 兜底（paths.rs:94-96 先例形态）；文件 `<dir>/save.json`；**目录惰性创建**（首写才
     create_dir_all——M9 断言点）；
   - 三态守卫：缺文件 quiet 默认（flow.rs 先例）；版本守卫+迁移链尝试；解析失败→warn 逐
     分支（flow.rs:90-142 warn 表形态）+`.corrupt-<millis>` 备份（project.rs:338 先例）；
   - **不变式（写进模块 doc）**：`VersionSkipped` 态自动落盘抑制——绝不把读不懂的存档用默
     认值覆盖（事实十三）；`Recovered`（损坏）态备份后允许覆盖（原文件已在备份里）；
   - 原子写：tmp+rename+sync（texture_import.rs:159-163 先例形态，runtime 内 ~15 行小助手）；
   - dirty 自动落盘系统（决策 5-A）+显式 API 同在；Cargo.toml 加 `dirs.workspace = true`。
3. **headless 测试 `crates/jackdaw_runtime/tests/save_store.rs`（矩阵 H 侧 8 格全落）**：
   M1 双 App 生命周期/M9 缺文件/M10 版本双向+迁移链单测/M11 损坏四形态+备份在案/M12 目录
   异常+dirs None/M6/M7 桥逻辑（桥系统本体在模板，但 merge 语义单测可下沉 runtime 侧）/env
   缝/原子写（中断写残 temp 不伤主文件）。锚形态照 `game_flow.rs`（ENV_LOCK+tempdir）与
   `config.rs`（run_until）。
4. **lock 连带（事实十二）**：scaffold lock 快照刷新（`lib.rs:1265-1271` include_str 自动随，
   但需 `Cargo.lock` 实际更新+`a_new_game_carries_the_workspace_lock_snapshot`（:3597）过）+
   `tests/fixtures/bsn_game/Cargo.lock` 刷新。
5. **门禁**：quick 四门+`cargo test -p jackdaw_runtime`+integration 档（save_store.rs 在档，
   xtask main.rs:118 形态）。

**验收标准**：探针三项定案在案；H 侧 8 格全绿；quick 四门+integration 绿；lock 两处连带
落地（scaffold 测试+fixture 冷编各一证）。

### T2「模板示例 + fixture e2e + 真机矩阵」（SV2-SV4；决策 6/7 + §五全部落地判定）

1. **模板 save 段（lib.rs.template，对齐教学密度 ~100-120 行）**：
   - `GameSave` profile（`Serialize+Deserialize+Clone+Default+Reflect`）：
     `progress: GameProgress { runs_played: u32, best_runs… }`+`unlocks: Vec<String>`+
     `audio: Option<AudioPrefs { master, music, sfx }>`+`input: Option<Vec<GameActionDef>>`；
   - 接线一行：`.add_plugins(SavePlugin::<GameSave>::new(env!("CARGO_PKG_NAME")))`+
     显式 `register_type::<SaveStore<GameSave>>()`（T16 泛型教训）；
   - **桥系统三件**：`apply_saved_audio`（`.after(jackdaw_runtime::apply_config_defaults::<
     GameAudioConfig>)` 排序——防 authored 注入覆盖恢复值，事实九时序险点）；
     `apply_saved_input`（`merge_actions(config.actions, saved)` union）；
     写侧 watcher：`Changed<GameAudioConfig>/Changed<GameInputConfig>`→写 profile.audio/input
     →置 dirty（设置改动即持久）；`OnEnter(GameFlow::GameOver)`→`runs_played+=1`+解锁判定
     →dirty；
   - menu/gameover 文本绑定 `runs_played`（BindContext 现成接线，T12 机器）+解锁提示一行；
   - doc 头部新增「Saving progress and settings」导览段（两层语义：config 资产=authored 默认，
     存档=玩家覆盖；「文件在用户目录，与场景分开」一句）。
2. **bsn_game fixture e2e（H2）**：fixture lib.rs 加最小 save 接线+stderr 标记
   （`SAVE_WRITTEN`/`SAVE_LOADED runs=N`，`save:` 前缀隔离——T16 `audio:` 前缀先例）；
   `tests/` 新 e2e 或扩展 `bsn_game_run.rs`：同一 fixture 二进制双跑、共用 tempdir、第二跑
   等恢复标记（`run_windowless_game_until` extra_markers 现成参数）。scaffold teaches 断言
   （模板含 GameSave/SavePlugin 接线/桥系统/doc 段）。
3. **真机矩阵**：fixture 工程+`loop/qa/t17-live.sh`+L1-L8 全腿（§三）；M3/M4/M13 真机格+
   L6 PIE 单腿（N13 记数）；缺陷只记不修（SV 系续编 SV9 起），红证归档
   `loop/reports/t17*/`（T16 红态归档纪律沿用：红 e2e 先存 `_red.log`）。
4. **QA 报告**：14 格逐格判定+L 腿全证据+用户 30 秒清单草稿（改音量→重启→听/读回；
   删存档文件→首跑不崩）。

**验收标准**：M1-M8（铁证①）三通道证据在案=重启恢复成立；M9-M13（铁证②）headless 全绿+
真机抽腿=三态回退成立；M14 零意外 warn；四门禁绿。

### T3「终验 + 文档」

1. 14 格终态复跑+重点腿复跑（L3/L4/L5）。
2. book 新章 `book/src/user-guide/game-saves.md`（SUMMARY 排 game-flow.md 之后，
   `SUMMARY.md:28` 后）：存档两层语义（config 资产=authored 默认 < 玩家存档覆盖）、接口导览
   （SavePlugin 一行接线+profile 结构+write/clear API）、三态回退行为表（缺文件 quiet/旧版
   warn+抑制/损坏 warn+备份）、`JACKDAW_SAVE_DIR` 测试缝、版本化与迁移钩子、与场景文件分开
   的路径表（macOS/Windows/Linux 三行）、T16 音量滑条消费指路+T25 边界一句（编辑器域回写
   资产 vs 游戏域写用户目录）；`game-parameters.md`/`game-input.md`/`audio.md` 交叉引用。
3. buglist 处置（预期无打钩；SV7/SV8 记档在案）、roadmap T17 勾选、台账记行。
4. 终验门：全量门（fast/integration/doctests/docs/scaffold_e2e——日志全文复核，门前清磁盘）。

---

## 五、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **存档位置（「与场景文件分开」的落地形态，SV1 前置）** | A=**用户目录**（`dirs::data_dir()/<game-id>/save.json`；macOS `~/Library/Application Support/<id>/`、Windows `%APPDATA%/<id>/`、Linux `~/.local/share/<id>/`）：OS 玩家数据惯例+导出包只读分发免疫（T07 dist 形态）+编辑器工程树零污染；代价=dev 迭代时档案不在项目里（`JACKDAW_SAVE_DIR` 缝补）。B=项目 `.jackdaw/saves/`：工程内可见性好；代价=发货游戏无「项目」概念、导出包落不到、与编辑器私有目录语义混。C=assets 树内：零理由——会被资产走/导出/PIE temp 三面污染（事实八③）——**否决** | **A**；game_id 显式参数（游戏 lib.rs 写 `env!("CARGO_PKG_NAME")` 展开为游戏自己的包名，scaffold teaches 钉形态） |
| 2 | **格式与版本化（「旧版安全回退」指向版本化）** | A=**JSON envelope+save_version 字段**（serde_json 已是 runtime 依赖 :67；flow.rs 容错解析器形态可抄 :90-142；人可读=QA 文件断言容易+玩家可手救）：文本协议无二进制漂移。B=bincode：紧凑+快；代价=新依赖+不可读（三态矩阵的「损坏」与「旧版」形态都难构造断言）+跨版本字段序敏感。C=BSN/reflect 序列化：与编辑器同栈；代价=存档绑定类型注册面+场景栈纠缠（恰是「分开」要避的）+BSN 解析无容错 value 层——**否决** | **A**；envelope 三字段（save_version/saved_at/profile），框架持有版本、游戏只写 profile |
| 3 | **接口落点（「运行时存档接口」的宿主）** | A=**`jackdaw_runtime::save` 模块**（第四个家族成员，事实三）：游戏侧零新依赖（runtime 在每个游戏里）、与 config/game_input/flow 同心智、prelude 一并导出；代价=runtime 多 ~250 行。B=新 crate `jackdaw_save`：独立演进；代价=为 ~250 行立 crate（T15-AN1 反面教材同构）+游戏 Cargo 模板加一行+scaffold features 面连带。C=仅模板段：验收句「运行时存档接口」字面落空——**否决** | **A**；模块+tests 同目录家族形态，`pub use` 入 prelude |
| 4 | **旧版处置深度** | A=**版本守卫+默认回退+可选迁移链 API**：验收词「旧版安全回退」逐字满足；`with_migrations(vec![{from, apply}])` 给要保进度存档的游戏；未注册旧版=warn+默认+抑制覆盖。B=强制迁移链：每加字段必写迁移——对 v1 示例是纯税。C=无版本字段：「旧版」词落空、未来版本读崩——**否决**（新版本降级守卫必须显式存在） | **A**；模板 v1 零迁移演示+runtime 单测两种迁移路径（有链升级/无链回退）都断言 |
| 5 | **写入策略（自动 vs 显式）** | A=**dirty 标志自动落盘+显式 API 同在**：BRP mutate 一发即持久（真机腿 L2/L3 链最短）；T04 journal「脏了就写」先例语义（:1-15）；文件极小（<1KB 量级）同帧写无感；VersionSkipped 抑制不变式兜住自动写的唯一危险面。B=纯显式：游戏全控；代价=真机腿要专门触发腿+忘写=进度丢失（对新手游戏的坑）。C=仅退出时写：kill -9 即丢=验收句「重启恢复」的 kill 腿直接红——**否决** | **A**；`get_mut()` 置 dirty、Update 系统 flush、显式 `write()` 给游戏要原子时刻的场景 |
| 6 | **PIE 与 direct 的槽位关系（SV6）** | A=**同槽**：PIE 就是真游戏进程（真代码真逻辑），真存真读=「所见即所存」；QA/开发隔离走 `JACKDAW_SAVE_DIR` 缝（脚本标配）；无分支无特判。B=PIE 独立槽（`JACKDAW_PIE` 存在→`pie` 子目录）：编辑器迭代不污染真档；代价=「Play 里打到的进度导出后不见了」的认知陷阱+一个隐式分支 | **A**；book 注记一句「Play 会写真实档案」+`JACKDAW_SAVE_DIR` 指路 |
| 7 | **设置屏范围（T16 决策 3 移交的「B 素材」兑现面）** | A=**音量三滑条入暂停屏+输入数据级演示**：hud.bsn PauseScreen（:54-98 现有落点）加三滑条+ValueChanged→observer→写 `GameAudioConfig`（写资源走 observer——bind 写路径拒资源，T16 事实九）→Changed watcher 落盘；输入改绑演示走 BRP mutate（数据级），键位捕获 UI（keydown 捕获循环）明确不做。B=A+键位重绑 UI：示例全；代价=捕获态 UI+编辑器键位不混用边界（T09 验收句）+A10 指针腿——范围超验收句（验收词只要求「输入设置」持久，不要求重绑 UI）。C=零 UI 全 BRP 数据演示：最瘦；代价=T16 移交落空+「示例」教学生泽弱 | **A**；B 记 book 指路（「键位重绑 UI 留后续任务」）；滑条操作腿走 trigger 链绕 A10 |
| 8 | **SaveStore 的 BRP 断言面形态** | A=**Reflect Resource（profile+status 全可读）**：`world.get_resources` 直读、`world.mutate_resources` 直改（fork builtin_methods.rs:79-92 现成）+status 枚举使三态在真机可断言（M13 的 status=Recovered 读法）；代价=泛型注册要在每个游戏显式一行（T16-T1 教训，本来就逃不掉）。B=自定义 BRP 方法（jackdaw_remote handler 直查）：`jackdaw_remote` 不在模板/runtime 依赖——真实用户游戏永不链接（T16 事实十 v2 补充同构）——**正当性弱**。C=无 BRP 面：真机格 M3/M4/M13 全塌——**否决** | **A**；status 字段设计为简单可读形态（小枚举+备份路径字符串），真机断言零新方法 |

小定案（主控可否决）：缺陷编号 SV1-SV8（新发现自 SV9 续）；矩阵格 M1-M14；真机腿 L1-L8；
fixture 工程 `/Users/zhanglinbo/workspace/loop-mac/t17-save`（crate 名 `t17_save`）；流程脚本
`loop/qa/t17-live.sh`；报告目录 `loop/reports/t17*/`；book 章
`book/src/user-guide/game-saves.md`（SUMMARY:28 game-flow 之后）；存档文件
`<save_dir>/save.json`（多槽预留 `saves/` 子目录，SV8 记档）；env 缝 `JACKDAW_SAVE_DIR`
（整体替换存档目录，tests/QA 标配）；envelope 字段 `save_version`/`saved_at`/`profile`；
模板类型名 `GameSave`/`GameProgress`/`AudioPrefs`；runtime 依赖 `dirs.workspace = true`
一行（不走 jackdaw_env——编辑器品牌层+libc/windows-sys 拖挂，事实七）；headless 锚
`crates/jackdaw_runtime/tests/save_store.rs`（H）+`tests/fixtures/bsn_game` 双跑（H2）；
lock 连带两处（scaffold 快照+bsn_game fixture 锁）入 T1 清单。

---

## 六、风险与回滚

| 风险 | 概率 | 缓解 |
|---|---|---|
| **authored 注入覆盖恢复值**：ConfigPlugin 在 walk 后注入 config 资产值，若桥系统先跑，保存的音量/输入被 authored 默认冲掉 | 中-高（时序必然相遇） | 桥系统显式 `.after(apply_config_defaults::<T>)`（`apply_config_defaults` 是 pub API，config.rs:147）；M6/M13 红绿+T1 单测钉时序；loader 自灭后排序仍有效（空查询 no-op） |
| dirty 自动落盘覆盖「读不懂的存档」（未来版本/未迁移旧版被默认值冲掉=不可挽回数据丢失） | 中（设计险点，非实现险点） | **不变式**：VersionSkipped 态抑制自动写（事实十三）；单测专断言（旧版本档+mutate→盘上原档未动）；损坏态例外（已有 `.corrupt` 备份） |
| `dirs` 依赖连带 lock 双处（scaffold 快照 :1265-1271+bsn_game fixture 自带锁）刷新漏一处 → 新工程/fixture `--locked` 拒绝（A3 家族形态现形） | 中 | T1 清单显式两项+scaffold 测试（:3597）+fixture 冷编活证双门；A3 注记（buglist 重叠表） |
| serde 对 bevy 输入类型（KeyCode 等）的 JSON 往返边角（serde derive 在案但 JSON 路径未跑过） | 低-中 | T1 探针①半日定案；炸则 profile 输入段降级为自建轻量绑定表（string+kind）并记 SV9——概率低（T09 已依赖这些 derive 编译过） |
| `dirs::data_dir()` None 环境（极简容器/异形 HOME） | 低 | home 兜底（paths.rs:94-96 先例形态）+None 仍 None 时 status 降级 NoDir+写 warn 不崩（M12）；本机 Mac 恒有该目录 |
| 损坏备份 `.corrupt` 堆积 | 低 | SV7 记档不修（一损坏一文件，Y9 先例同语义无害） |
| A9 撞面（gbrp 间歇空响应） | 低-中（低于 T16） | 断言大头走文件系统/stderr 标记（BRP 活性无关）；单资源小响应体+settle 重试+idle 探针；L3 读回腿超重试预算即按 MCP 优先原则现场立项 |
| N13（PIE 腿 100% 复发） | 确定 | PIE 仅 L6 单腿+记数；勿设 RUST_BACKTRACE（Mac debug 必 SIGSEGV） |
| 模板膨胀（现 1,281 行，+~120 行） | 低 | doc 段精简指路 book；行数增量记 T2 报告（T12/T16 先例口径） |
| bsn_game fixture 加 save 接线波及既有断言（共享 fixture） | 低-中 | 追加不改造（不动既有探针实体/标记）；`save:` stderr 前缀隔离；跑 bsn_game_run 全件确认零回归 |
| 双跑 e2e 时长（fixture 构建已有，双跑仅运行成本） | 低 | run_windowless_game_until 90s 连接预算（mod.rs:397）沿用；两跑共享一次构建 |
| Mac debug 无 RUST_BACKTRACE / 门链同窗互踩 | 确定 | 全程不设（T11-T3 口径）；门链单独跑（T12-T3 §九-7 纪律）；门前清磁盘（A6 家族） |
| 回滚 | — | 四件独立可 revert（save.rs 单模块+runtime Cargo.toml 一行 dirs；模板 save 段两文件段；fixture e2e 追加；live 脚本）。**零 fork 改动、零编辑器产品代码改动、零场景格式变更、零 bsn 新授权组件、零新 BRP 方法**——产品 diff 面=runtime 一 crate+模板一 crate，由定性表保障（四类数据的机制载体全部成晶，只砌持久半边） |

---

## 七、与 T01-T16 已建设施的衔接

1. **T08（ConfigPlugin）=authored 默认层**：存档=玩家覆盖层，两层叠加语义（config 资产 <
   玩家存档）是本任务的核心语义贡献；`apply_config_defaults` 的 pub 可见性直接支撑桥排序。
   M6 是两层语义的活证格。
2. **T09（输入）=union merge 原语与 serde 面**：`merge_actions` 的 union 语义（防旧档吃掉新
   动作）正是存档恢复需要的合并律；profile 嵌 `Vec<GameActionDef>` 零序列化新代码。
3. **T16（音频）=音量持久半边的消费对象与移交方**：`GameAudioConfig` 三字段+Changed watcher
   +SoundLive BRP 读面全现成；T16 决策 3-B 的「滑条→observer→写资源」接线素材在决策 7-A 兑
   现；book audio.md「T17 设置屏将消费同一资源」指路落定。
4. **T12（游戏 UI/模板纪律）**：GameFlow 三态=进度事件挂点（OnEnter(GameFlow::GameOver) 写
   档）；hud.bsn 两屏=设置屏落点；`on_screen_pressed`/`register_function` 机器=runs_played
   展示链。
5. **T13（flow）=容错哲学与路径先例**：warn-and-fallback 哲学原文（flow.rs:16-21）+serde_
   json 容错解析 warn 表+「无文件是安静默认」语义+BEVY_ASSET_ROOT 型 env 缝先例——存档解析
   面逐条照抄形态。
6. **T04（编辑器保存链）=纪律来源（边界见事实六）**：write_atomic 的 tmp+sync+rename 纪律、
   `.corrupt-<millis>` 备份纪律、`.bak` 单槽（本轮不做恢复链，SV 记档）——形态三件照抄，
   实现自含在 runtime。
7. **T07（导出）=位置决策依据**：dist 只读分发形态（export.rs:1-26）+异目录启动铁证链=用户
   目录决策的第二硬理由；M4/L5 复用其 staged 启动形态。
8. **对 T18-T25 的奠基**：T18（资产导入）无关但共享「坏文件不崩」验收哲学；**T20（示例游
   戏）直接拼装 save 段**（进度+设置全套现成）；**T25（运行态调参回写）边界=编辑器域组件白
   名单回写资产，与 T17 玩家数据写用户目录方向相反**——book 注记一句划界；T24（错误定位）
   的「存档 warn 可见」已在本轮 warn 表内。
9. **分支与行号基线**：本方案行号基于 main d34606e0；T17 从 main 拉 `loop/t17-save-settings`；
   loop/ 目录随 git 旅行（2026-10-28 迁移态）。

---

## 八、耗时预估

| 段 | 预估 | 大头 |
|---|---|---|
| T1 | 1-1.5 天 | 探针三件（serde 往返/dirs/反射注册）+save.rs 薄层（envelope/三态守卫/原子写/dirty flush/迁移链 API）+H 侧 8 格测试+lock 双处连带 |
| T2 | 1-1.5 天 | 模板 save 段（profile+三桥+watcher+doc）+bsn_game 双跑 e2e+t17-live.sh L1-L8+红证归档（决策 7-B 若裁 +0.5 天） |
| T3 | 0.5-1 天 | 14 格终态+book game-saves.md 新章+全量门+收尾 |
| 合计 | **3-4 天** | 视决策 5 时序险点与 dirty 抑制不变式的实现顺畅度浮动 |
