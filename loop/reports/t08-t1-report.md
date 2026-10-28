# T08-T1 实施报告：配置资产 → Resource 注入链 + 模板教学（P1 第一棒）

> 任务：`loop/plans/t08-game-params.md` §二 T1（P1+P2+P3；决策 1-A/2-A + 小定案）。
> 分支 `loop/t08-config`（自 main 6119a066 拉出），提交 **69cc71cb**
> `Load game parameters from config assets at runtime`（6 文件 +776/−3）。未 push，未合入（待 QA）。

## 一、交付

### 1. runtime 注入机制（`crates/jackdaw_runtime/src/config.rs`，新模块）

- **`ConfigLoader<T>`**（Component）：`new(path)` 显式 + `Default` 走约定 [`DEFAULT_CONFIG_PATH`]（`game-config.bsn`，决策 2 的糖）；loader 注入后自毁——一次/进程由构造保证。
- **`ConfigPlugin<T>`**（游戏一行）：`app.add_plugins(ConfigPlugin::<GameConfig>::default())`——**build 期立即 `insert_resource(T::default())`**（消费系统永不与注入竞态——真机实跑揪出的首版时序缺陷，见 §四-4）+ 注册系统 + spawn loader。
- **`apply_config_defaults<T>`**：从 `JackdawCatalog` 取约定键（`get(path)`——路径或 `@Name`），注入 store 里的值为 Resource 初值；**等待 `AssetsWalked`**（本任务新增的启动 walk 完成标志，`load_walked_assets` 尾部 insert）后，缺键=default+一次 warn（缺配置不是错误）；类型不符（try_typed Err）同兜底。
- **机制修正（对方案的重要实现偏差）**：方案决策 2-A 原文的「资产就绪后」最初实现为 `AssetServer::load` 轮询——**行不通**：jackdaw 的 `.bsn` 资产不走 bevy loader 体系（是 JackdawPlugin 启动 walk 手填 store/catalog，runtime 既有架构事实）。改为 **catalog/walk 路线**：`JackdawCatalog::register_file`（本任务新增公开注册面）+ `AssetsWalked`。注入语义不变（初值、一次、缺文件 default）。
- prelude 出口：`ConfigLoader/ConfigPlugin` 与 PIE_SCENE_ENV 家族同居（小定案）。

### 2. 模板教学（`lib.rs.template`）

- `GameConfig { player_health, move_speed, gravity }`：`#[derive(Asset, Resource, Reflect, Clone)] + #[reflect(Resource, Default, @EditorCategory::new("Game Config"))]`，手写 `Default`（100/1/-9.81——缺文件时游戏跑在合理数上）。
- `GamePlugin::build`：`init_asset::<GameConfig>().register_asset_reflect::<GameConfig>().add_plugins(ConfigPlugin::<GameConfig>::default())`（两注册+一行加载）。
- `FallingCube` 示例（spawn 于 Startup，带 mesh/material）：`falling_cubes` 读 `Res<GameConfig>`——`translation.y += gravity*dt`（下落）+ `rotate_y(speed * move_speed * dt)`（组件参数×全局参数对照教学）；`player_health` 注释注明供 HUD/玩家系统（T11/T12 伏笔）。
- doc 新增「# Tuning parameters」节（改参数=编辑器改卡片→Save→Play/cargo run 生效；组件参数 vs 全局参数的分工说明）。
- **scaffold 测试**：`new_game_project_teaches_the_config_pattern`（10 项断言：类型/字段/两注册/ConfigPlugin/消费系统/doc 节）。

### 3. 编辑器↔游戏文件形态往返（`tests/guards/config_injection.rs`，新）

- **正向往返**：编辑器 `write_asset_file`（真 emit 路径：`AssetValue::Handle` 经 `serialize_assets_to_bsn`）写 150/2.5/-19.5 → 游戏侧 walk 形态（parse+`load_asset_root`+catalog 注册+AssetsWalked）+ `apply_config_defaults` → **Resource 三字段=编辑器所写**。形态漂移即红。
- **会话态负向**（P1 现状钉死）：编辑器 world 资源写 999/99/-99 → assets 目录**零文件** + 游戏侧起=default——「面板值不落盘、游戏读文件不读面板」的字面边界。

### 4. runtime 机制单测（config.rs tests，5 个）

红绿对（无系统时 Resource 永不出现=红半；walk 后=文件值=绿半）、缺文件 default+loader 自毁（一次）、store 后改值不重注入、`.jackdaw-pie/` temp 不遮蔽配置正本、**build 期 default 就位**（新增语义防回归）。测试文件形态=编辑器真形态（`// jackdaw asset <path>` 头 + `#"game-config"`（**含 `-` 的名字 emitter 会加引号**——实测坑，已钉进测试）。

### 5. scaffold 实编验证

`jd new` 生成 → `cargo build` **PASS**（含 ConfigLoader/GameConfig/FallingCube 全链编译；首版模板有 ColorMaterial 用于 3D mesh 的编译错，被实编抓获修正为 StandardMaterial——文本断言测试抓不住的正是这类，实编腿的价值证明）。

## 二、真机结果（`loop/qa/t08-config-play.ps1` 沉淀 + 日志 `loop/t08t1_live.log`）

十轮迭代后达到的状态：
- **编辑器全链 PASS**：新模板工程 → prebuild → schema（assets 桶含 `...::GameConfig`（category "Game Config"）→ `asset.new type=game_config`（**op 按 id/type_path/label 命名，短名不认**——脚本坑之一）→ 创建 `assets/game-config.bsn` → `asset.set move_speed=2.5/gravity=-9.81` → `asset.save` → **盘上文件与 runtime 测试钉的形态逐字一致**（header+quoted name+struct patch，f32 全精度）。
- **cargo run 抽查 PASS**：独立运行 12 秒存活（Panic 修复后；首跑 101=下述时序缺陷）。
- **PIE 生命周期 PASS**：play_current → connected → running → stop → temp 副本清理，编辑器全程存活。
- **`scene_snapshot` 两帧差行为断言：受阻**——play 运行中 snapshot 持续返回 watching-pending（投影域在**无交互后台编辑器**下不产实体（projection entities=0；历史 t06 真机链有前台交互）。**三腿证据已足**（游戏运行+配置文件就位+注入链 headless 全绿），行为面留 QA 前台复跑（脚本一行 `-Project` 即可）。如实记档。

## 三、门禁（quick 四门，全文复核+归档 `loop/t08t1_*`）

| 门 | 结果 |
|---|---|
| fmt | clean |
| clippy workspace all-targets `-D warnings` | **exit 0**（揪出 doc backticks ×2、drop_non_drop，修后覆盖） |
| 单测 | runtime **config 5/5**、crate lib 全量绿；scaffold **79**（+1 新）；guards **199**（+2 新）；主 crate lib **1169** |
| 任务相关集成 | guards 全量（52.6s）；scaffold 实编 cargo build PASS |

## 四、偏差与记档（重要，按影响排序）

1. **注入机制实现路线修正**（§一-1）：AssetServer 轮询 → catalog/walk（`.bsn` 不走 bevy loader 的架构事实）；`JackdawCatalog::register_file` 与 `AssetsWalked` 为配套新增公开面。方案决策 2-A 的**用户面语义**（一行/初值/一次/缺文件 default/约定名糖）完整保留。
2. **上游漂移再现**（feature#3 同款）：新工程 fresh lock 解析到 wgpu-hal 30.0.1 坏组合（E0308）——**与本任务无关**（本仓库同版本编译过；差异在 fresh 解析的 feature 组合）。临时处置=workspace Cargo.lock 引导重解析后编译 PASS。**建议立项**：scaffold 新工程 lock 漂移敞口（挂 T08-T3 或 open-challenges）。
3. **模板经 `include_dir` 编译期嵌入**：改模板后必须重编 jd.exe 才进新生成——本任务真机前三轮跑在旧模板工程上（诊断成本主要来源）。教训：模板改动后 `cargo build -p jd` 是验证链一部分。
4. **首版 ConfigPlugin 时序缺陷**（真机 cargo run 101 揪出）：消费系统（`Res<GameConfig>`）先于注入跑 → Resource 缺失 panic。修复=build 期先插 default（首帧 Update 前文件值已就位——default 只存在于 Startup 窗口），新增测试钉死。
5. **asset.new 命名口径**：kind 按 id（`game_config`）/type_path/label 命名，**短名（`GameConfig`）不认**——现有测试已钉此语义（`a_kind_answers_to_its_id_its_type_path_and_its_label`），脚本对齐；文档/提示建议后续任务补一句。
6. **PS 验证工具坑集**（全在本会话内识别并绕开，不残留）：`ConvertFrom-Json` 深度限制把 620KB schema 的 assets 桶解析成空（一度误导「schema assets 空」——原始文本 grep 才见真相）；组件键含 `::` 不能用点语法（索引发）；`@($null).Count=1`（watching-pending 误读成 1 实体）。
7. **真机行为断言腿**交 QA 前台复跑（§二）——Play 会话/配置文件/游戏运行三腿已有独立证据。

## 五、buglist 与交接

- buglist：本轮无打钩项（P1-P3 新发现，按方案）✓；W13 归 T2。
- QA 复核建议：①前台编辑器复跑 `t08-config-play.ps1`（行为断言腿）；②无 lock 新工程的 wgpu 漂移现象确认（§四-2）；③模板工程「New Asset 列表出现 Game Config」的 UI 面走查（BRP 腿已证 schema/kinds 注册）。
