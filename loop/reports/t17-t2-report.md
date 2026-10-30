# T17 任务 2「模板示例 + fixture e2e + 真机矩阵」程序报告

> 分支 `loop/t17-save`（自 main 585b3b84 fast-forward 同步）；任务书
> `loop/plans/t17-save-settings.md` §四-T2；T1 交接面按 QA `t17-t1-qa.md` §五/§六
> 执行（回流 D：BRP mutate 不置 dirty→真机腿全走 config 资源 watcher→`get_mut`→dirty
> 链；回流 F：迁移边界三探针吸收进 save_store.rs 常驻；`JACKDAW_SAVE_DIR` 整体替换
> =脚本标配）。改动 10 文件 +832/−3 + 新增 `loop/qa/t17-live.sh` + 归档 25+7 件。
> 零 fork 改动、零编辑器产品代码改动、零场景格式变更、零新 BRP 方法、runtime 产品代码
> 零改动（T1 之后 runtime 侧只动测试文件）。

## 〇、门禁（最终树重跑，覆盖归档 `loop/reports/t17t2_*`）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **CLEAN** | t17t2_fast.log（fast 首步） |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | **EXIT=0，0 `warning:`** | t17t2_clippy_ws.log |
| 单测 | `cargo test --workspace --lib` | **2990 passed / 0 failed**（=T1 的 2989+1 teaches）；**scaffold=91**（预期 90→91 达成） | t17t2_libtests.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | **EXIT=0** | t17t2_clippy_physics.log |
| audio_gate | `cargo nextest run --profile ci --test audio_gate` | **7/7 PASS** | t17t2_audio_gate.log |
| AN2 腿 | `cargo nextest run --profile ci -p jackdaw_runtime --features animation --test animation_scene_load` | **1/1 PASS** | t17t2_an2.log |
| save_store 套件 | `cargo nextest run --profile ci -p jackdaw_runtime --test save_store` | **19/19 PASS**（17+2 新测试） | t17t2_save_store.log |
| fast | `cargo xtask fast` | **EXIT=0；Summary 2990/2990（73.7s）；全文 0 FAILED/0 `warning:`** | t17t2_fast.log |
| bsn_game e2e | `cargo nextest run --profile ci --test bsn_game_run` | **3/3 PASS**（双跑腿+旧件+run-target 重烟；程序报告「2/2」系计数笔误，QA 偏差 12 指正，此处更正） | 本文 §二 |
| 磁盘 | `df`（门前） | 36Gi 可用（终跑）；**本轮实际撞过一次满盘**，见偏差 4 | — |

## 一、模板接入面（方案 §六 T2 清单逐项）

**lib.rs.template（+354 行，含 doc 段）**：

1. **`GameSave` profile**（`Reflect+Clone+Default+Serialize+Deserialize`）：
   `progress: GameProgress { runs_played: u32 }`+`unlocks: Vec<String>`+`audio:
   Option<AudioPrefs { master, music, sfx }>`+`input: Option<Vec<GameActionDef>>`
   ——四类数据齐（进度/解锁/音量/输入）；`GameActionDef` 直嵌 runtime 既有 serde 面，
   零序列化新代码（T1 探针①的兑现）。
2. **接线**：`.add_plugins(SavePlugin::<GameSave>::new(env!("CARGO_PKG_NAME")))` 一行。
   方案写的「显式 `register_type::<SaveStore<GameSave>>()`」**不需要**：T1 的
   `SavePlugin::build` 已注册 SaveStore\<T\>+SaveStatus+T 三件（save.rs:447-449）——
   偏差 7 记档。
3. **桥系统**（方案指定的三件，落成四系统）：
   - `apply_saved_audio`：读 `save.profile.audio` → 写 `GameAudioConfig`；就绪门=
     `Query<(), With<ConfigLoader<GameAudioConfig>>>` 为空（authored 注入已完成——
     loader 在即 `apply_config_defaults` 还会注入，会把存档洗掉）；一次 armed。
   - `apply_saved_input`：`merge_actions(&config.actions, saved)` union 合并，同门同时序。
   - `save_audio_changes` / `save_input_changes`（写侧 watcher）：armed 门=**loader 空
     的那一帧 armed 但跳过持久化**——这一帧跳过正是「authored 注入不被当成玩家改动、
     首跑不落盘」的机制（L1 的「盘上无文件」断言靠它）；之后任何 `Changed`（滑条/
     BRP）→`get_mut()`→dirty→同帧 flush（方案决策 5-A）。
   - 两个桥+两个 watcher 均排 `.after(jackdaw_runtime::apply_config_defaults::<T>)`
     （方案指定的时序防覆盖；tuple `.chain().after` 组合在本 bevy 不编译，改 tuple
     `.after`——链不必要，loader 空门已保证正确性，偏差 6）。
4. **进度/解锁**：`count_run_over` 挂 `OnEnter(GameFlow::GameOver)`（与 `enter_game_over`
   同 tuple）：`runs_played+=1`，第 3 局 push `unlocks: "endless"`；`get_mut`→同帧落盘。
5. **显示镜像**：`GameState` 增 `runs_played: u32`+`unlock_note: String`；
   `mirror_save_display`（Update）把存档值抄给绑定面——绑定解析资源路径，menu/gameover
   文本绑 `Res({{crate_name}}::GameState).runs_played`（泛型 SaveStore 路径不进文档，
   T12 机器现成接线）。重启后镜像由存档值驱动=「menu 可读」的活证。
6. **设置屏最小面**（决策 7-A）：hud.bsn PauseScreen 增三行「标签+挂点 marker」
   （行节点+`Node{width:62%,height:24px}` 布局槽）；滑条本体由 **Rust 侧
   `attach_volume_sliders` 挂接**——`FeathersSlider` 是场景件（scene component），
   文档里按普通组件行写只挂 require 链、场景永不展开（QA SV9 实锤），唯一合法
   落地=`commands.spawn_scene(bsn! { @FeathersSlider })`（编辑器 slider_row 同款
   形态）挂到 authored 行下、marker 随件（查询带 `Without<SliderValue>` 防挂件
   自触发连环）；滑条条=根节点 `BackgroundGradient`，其类型与载荷三件须显式注册
   （场景件组件走注册表应用，未注册类型静默剥落）；`FeathersPlugins` 负责着色/
   内嵌字体/样式系统；`on_volume_changed` 观察者认 marker→写对应 `GameAudioConfig`
   （bind 写路径拒资源，观察者=桥）；`sync_volume_sliders` 把 mix 指回滑条位置
   （无 changed 门——滑条在恢复后才 spawn，等值护栏防反馈环）；`register_type::<
   ValueChange<f32>>()`+`register_type::<FeathersSlider>()` 两行（泛型与 feathers
   类型都不在 reflect auto-inventory——T16 泛型教训的两次适用）。输入改绑演示=BRP
   mutate（数据级），键位捕获 UI 不做（决策 7-B 记 book 指路，归 T3）。
7. **doc 段**：「Saving progress and settings」导览（两层语义、文件在用户目录与场景
   分开、三态守卫指路 runtime SaveStore doc）。
8. **Cargo.toml.template**：+`serde = { version = "1", features = ["derive"] }`（profile
   derive 所需，游戏自己的依赖，不走 runtime 转供）。

**teaches**：新增 `new_game_project_teaches_the_save_pattern`（lib 针 18+hud 滑条 4+
menu/gameover runs 绑定+Cargo.toml serde 行），**scaffold lib 测试 90→91**。

**bsn_game fixture（H2）**：`GameSave { runs_played, audio: Option<AudioPrefs> }`+
SavePlugin 接线+`apply_saved_audio` 桥（一次 armed，硬编码 config=authored 层）+
`run_save_demo`（**JACKDAW_SAVE_DIR seam 门**——seam 未设零写入零标记，普通 e2e
跑永远是 fresh 世界且不写真档）：`SAVE_FRESH`/`SAVE_LOADED runs=N`→计数+写
audio 0.9→`SAVE_WRITTEN runs=N`→`SAVE_CONFIG master=…`（桥后 config 读数）。

## 二、headless 证据（H/H2）

- **新 e2e `a_save_survives_the_fixture_restart`**（tests/bsn_game_run.rs）：同一构建
  二进制双跑共用 tempdir：run1 `SAVE_FRESH`+`SAVE_CONFIG master=0.50`（authored 站住）+
  `SAVE_WRITTEN runs=1`；run2 同槽 `SAVE_LOADED runs=1`+**`SAVE_CONFIG master=0.90`
  （存档压过 authored=M6 的引擎级活证）**+`SAVE_WRITTEN runs=2`；盘上 envelope 断言
  （save_version=1/profile.runs_played=2/profile.audio.master=0.9）。**PASS**。
- 既有 `built_game_loads_and_spawns_a_bsn_scene` 不受扰（volume=0.160 断言原样绿）——
  该测试现也设 seam（隔离保险，偏差 8）。
- **save_store.rs +2 测试（17→19）**：`migration_chain_boundaries_stay_on_the_safe_side`
  （**回流 F 三探针常驻化**：退化步 0→0→VersionSkipped+"walks backwards" warn+文件
  字节不动；越顶步 0→5→Loaded（serde 终检=真闸门，越顶语义进常驻断言）；版本超
  u32（5e9）→Recovered+备份字节逐字节原样）+`the_store_reports_its_slot_and_reloads_it`
  （`dir()`/`save_file()`/`reload()` 面：reload 丢弃内存改动、dirty 清零）。
  M9-M12 的 runtime 侧测试 T1 已在档，本轮 19/19 全绿复跑。

## 三、真机矩阵（`loop/qa/t17-live.sh`，三相；证据归档 `loop/reports/t17t2_live-*`）

fixture=`/Users/zhanglinbo/workspace/loop-mac/t17-save/t17-save`（jd new+两行 remote
sed）；**`JACKDAW_SAVE_DIR=$FIXROOT/scratch` 在脚本顶端 export**——direct run、编辑器
（PIE 继承）、staged run 全走同一 scratch，零写真档（QA 交接面 3 的落实）。
authored `audio-config.bsn`（master **0.42**，与所有腿用值 0.7/0.35/0.6/0.75/0.9 可辨）
按编辑器 New Asset 的产出形手写（预验：`config 'audio-config.bsn' loaded` INFO 在案）。

### 铁证①重启恢复——三通道独立成立

| 通道 | 证据 | 结论 |
|---|---|---|
| H（生命周期模拟） | T1 `a_save_survives_the_process_boundary_between_two_apps`（本轮 19/19 复跑绿） | 成立 |
| H2（引擎管线） | fixture 双跑 e2e（§二）`SAVE_LOADED runs=1`+saved-over-authored 0.90 | 成立 |
| G（真机进程边界） | **L3：`kill -9`→重启→status=Loaded+四类原样**（runs=3、unlocks 含 endless、audio 0.7/0.6/0.5、Move 改绑 KeyE）+桥读回（config=0.7/0.6/0.5、merged 表 5 动作全、GameState 镜像 runs=3+unlock_note）+盘 jq 逐字段 | 成立 |

### 铁证②三态安全回退不崩——H 全绿+真机抽腿成立

| 格 | 通道 | 证据 |
|---|---|---|
| M9 缺文件 | H+G | L1：空 scratch 首跑 status=Fresh+四类默认+**盘上无目录**（惰性建目录）+**零 `game save:` warn**；一次 mutate→save.json 出现 |
| M10 旧版 | H | VersionSkipped 双向+迁移链+三边界探针（§二）真机无腿（方案口径 H-only） |
| M11 损坏 | H+G | runtime 五形态+备份；**L4/M13：空文件→Recovered+`save.json.corrupt-*` 备份在盘+warn 名中路径（`l4-warn-lines.txt`）+默认站住+再 mutate→槽位复活** |
| M12 目录异常 | H | runtime 只读目录+NoDir 两测试 |
| M14 warn 形态 | 脚本 | game+editor 两相 **WARN_SCAN PASS**：`UnresolvedTypes|cannot apply|cannot-apply` 零命中；`game save:` 仅出现在 L4 腿日志（=该腿设计产物，逐条点名归档）；`no config asset` 三行=模板良性态（归因不计数） |

### M 矩阵 14 格逐格判定（全绿）

| 格 | 判定 | 证据 |
|---|---|---|
| M1 双 App 重启恢复 | ✅H | save_store 19/19（T1 测试复跑） |
| M2 fixture 双跑 | ✅H2 | `a_save_survives_the_fixture_restart` PASS |
| M3 真机重启恢复 | ✅G+盘 | L2+L3（kill -9 口径） |
| M4 导出一致 | ✅G+盘 | L5：export→staged 异目录跑→**同槽读回 Loaded+master 0.75**（`l5-store-witness.json`） |
| M5 分开铁证 | ✅盘 | staged 树与 assets 树 **零 save.json**（find+manifest 双断言）；用户目录路径形态由 runtime 常驻断言钉住（T1） |
| M6 音量桥 | ✅H+H2+G | fixture `SAVE_CONFIG 0.90`+真机 M6 腿（authored 改 0.9→资源仍 0.35=存档赢；删档→0.9 站住；恢复 authored 0.42）+L3 桥读回 |
| M7 输入桥 | ✅H+G | runtime union merge 测试+L3（Move 改绑生效+缺省 5 动作全保留） |
| M8 进度/解锁 | ✅H2+G | fixture runs 计数+真机三局→endless 解锁+GameState 镜像（menu 绑定面）读回 3+解锁行 |
| M9 缺文件 | ✅H+G | L1（上表） |
| M10 旧版 | ✅H | M10a/b/c+三边界探针 |
| M11 损坏 | ✅H+G | 五形态测试+L4 |
| M12 目录异常 | ✅H | 只读目录+NoDir |
| M13 真机损坏腿 | ✅G+盘 | L4 |
| M14 warn 形态 | ✅脚本 | 两相 WARN_SCAN PASS（上表） |

### L 腿 8 条逐腿判定（全 PASS）

| 腿 | 结论 | 关键证据 |
|---|---|---|
| L1 首跑缺文件 | PASS | Fresh+默认+无目录+零 warn；mutate→文件出现 |
| L2 四类写入 | PASS | audio 三字段（watcher 同帧）、input 改绑（BRP mutate actions 数组→watcher）、progress/unlock **走真 game-over 路径**（BRP 置 PlayerHealth=0→`count_run_over`→3 局→endless）——每步盘 jq 断言（`direct-l1.log` 尾部文件全文在案） |
| L3 重启恢复 | PASS | kill -9→重启→四类+桥+镜像逐项（`l3-store-witness.json`） |
| L4 损坏腿 | PASS | Recovered+备份 1 份+warn 1 行+默认+槽位复活 |
| L5 导出腿 | PASS | staged 无档+assets 无档+staged 跑同槽读回（Loaded/0.75） |
| L6 PIE 单腿 | PASS | PIE 写 runs=1→direct run 读回同槽（决策 6-A 同槽语义活证）；menu.bsn sha 不变+assets 无档（stop 不变量）；**N13 记数=9，全部为已知 buglist N13 特征**（`jackdaw::pie::drain_game_events` swap_remove，本腿断言全不受扰） |
| L7 滑条腿 | PASS | **trigger 路径成立**：BRP `world.trigger_event` 打 `bevy_ui_widgets::ValueChange<f32>`（source=实体串形）→观察者写 config→watcher 落盘 0.35；kill -9 重启→滑条 `SliderValue=0.3499999940395355`（=0.35，f32 形）与 mix 同恢复（`l7-path-witness.txt`=trigger，fallback 未动用） |
| L8 warn 扫描 | PASS | 两相零意外（M14 上表） |

## 四、SV9 修复节（QA 裁定 FAIL 的单点；修复形态 A=模板 Rust 侧 spawn 场景件）

**QA 实锤（红，已验在案）**：hud.bsn 把 `FeathersSlider` 按普通组件行写→bevy_scene 只挂
require 链、场景永不 spawn；每跑 3 条 ERROR（`bevy_scene::scene_component: Entity … was
spawned with the "scene component" … but without its scene`，M14 词表外未披露）；滑条实体
无 Node/无 Children（QA 活体探针）——不可见不可拖，只有数据半边活着（L7 全程绕开
拖拽/视觉所以曾 PASS）。红证归档：`t17t2_live-direct-l1.log` 等日志中的 ERROR 行（修复后
归零）+QA 报告 §四原文。

**修复（形态 A 五件套，守「零编辑器产品代码改动」边界）**：
1. **hud.bsn 摘三行 `FeathersSlider` 组件行**；三行「标签+marker」authored 行保留为
   挂点，marker 行补 `Node{width:62%,height:24px}`（=滑条的布局槽——marker 实体
   原本无 Node，挂上去的场景件不参与 UI 布局，宽度为零不可见）。
2. **`attach_volume_sliders`（Update，`Added<marker>` 三查询）**：
   `commands.spawn_scene(bsn! { @FeathersSlider }).insert((marker, ChildOf(row)))`
   ——场景件唯一合法落地路径（bevy_scene 文档明言 spawn_scene/`@` 语法；编辑器
   `slider_row` 同款形态）；marker 随件（观察者/sync 照旧认得）；**查询带
   `Without<SliderValue>`**——否则挂件自身带 marker 下帧重新命中本查询，每个滑条
   每帧再生一个滑条（实爆过一次：186 实体连环，轮内红态如实记）。
3. **渐变三件注册**：`BackgroundGradient/Gradient/ColorStop/InterpolationColorSpace`
   ——场景件的组件走类型注册表应用，注册表叫不出名的类型**静默从场景件上剥落**
   （滑条的进度条=根节点上的 BackgroundGradient，剥落后永不上色）；BRP 查询它们的
   正名=`bevy_ui::gradients::BackgroundGradient`（定义模块路径，非 `ui_node::`）。
4. **`FeathersPlugins` 进游戏模板**：场景件给出骨骼（轨道/把手/数字），feathers 运行时
   （主题观察者+内嵌字体+控件样式系统）负责着色与随值移动——没有它控件能用但
   什么都不画；与 widgets_runtime 的主题共存（其 finish 设计上最后跑）。
5. **teaches 针更新**：摘 hud 场景件针，钉 Rust 形态（`fn attach_volume_sliders`+
   `spawn_scene(bsn! { @FeathersSlider })`+`register_type::<FeathersSlider>()`）。

**绿（真机归零核+PX，最终轮 game 相全绿）**：
- 滑条实体=`bevy_feathers::controls::slider::FeathersSlider` 查询实锤，**Node（feathers
  轨道布局）+Children（场景子件）+SliderValue** 三件全在；marker 实体恰 2 个
  （authored 行+挂接件）=连环已断；
- 全部 direct 日志 **`scene component` ERROR 行=0**（修复前 3/跑）；
- L7 全链在真滑条上复验：trigger→观察者→watcher→落盘→kill -9 重启→sync 回指
  （`SliderValue=0.3499999940395355`≈0.35）；
- **PX 截图腿补齐**（方案 L7 通道 G+PX 的 PX 半边）：BRP 置 `GameState.paused=true`→
  暂停屏可见→截图归档 `shot-l7-pause-sliders.png`——**三条带主题的滑条肉眼可见**
  （Master 填充至 0.42 带数字读数、Music/Sfx 满值），与存档/authored 值一致。

## 五、红→绿实录（先归档纪律）

| 轮 | 红（已归档） | 根因 | 绿 |
|---|---|---|---|
| 1 | `console-game_red.log`：L1/L2/L3/M6 数值断言全红+WARN_SCAN 红（FeathersSlider cannot apply ×15） | ①脚本数值比较无 f32 容差（BRP 读数=0.41999998…全精度形）；②**FeathersSlider 不在 reflect auto-inventory**，且文档路径须用**定义模块路径** `bevy_feathers::controls::slider::FeathersSlider`（re-export 路径 `controls::` 在注册表查不到）；③L2 的 jq 过滤器漏 `| .actions`（mutate 拿到整资源对象，报 "expected reflected list value"） | 模板 +`register_type::<FeathersSlider>`+hud 路径改定义模块形；脚本 feq 容差+路径修正 → game 相 7 腿全绿 |
| 2 | `console-game_red.log`（第二轮）：L7 红（滑条位置 0.0） | `sync_volume_sliders` 挂 `config.is_changed()` 门——存档恢复发生在启动（menu、滑条未 spawn），滑条 spawn 时 change 已消耗，永远拿不到恢复值 | 去门（等值护栏已防反馈环）→ L7 PASS |
| 3 | `editor-editor_red.log`：EDITOR_BOOT_FAIL（dyld symbol not found） | 编辑器二进制对 dylib 陈旧（t16 同款已知形态） | `cargo build -p jackdaw` 后重跑 → boot 绿 |
| 4 | `console-editor_export_red.log`：L5 export `linking with cc failed` | **满盘**（251Mi 剩余——release 导出+本轮多份 target 把盘吃满；A6 家族教训实弹） | 清 /tmp 渲染检查工程 19G+workspace incremental 23G→36Gi；重跑 → L5 PASS |
| 5（SV9 返工轮） | QA 报告 §四+`t17t2_live-direct-l1.log` 等（3 条/跑 scene-component ERROR+实体无 Node/Children）——程序首轮绿态日志中的未披露红 | FeathersSlider 是场景件，文档组件行不展开场景（§四 SV9 节） | 形态 A 挂接（`attach_volume_sliders`）→ Node/Children 实锤+ERROR 归零+PX 截图腿；L7 首复跑红一次（marker 双实体致位置查询抓到行实体——脚本查询加 SliderValue 过滤）→ 复跑全绿 |

另：L7 腿内 ValueChange 触发带文档化 fallback（config mutate=同一资源同一路径），
最终轮 **trigger 路径成立，fallback 未动用**（`l7-path-witness.txt`=trigger）。

## 六、偏差清单（如实）

1. **🟡 模板接入三次红→绿**（§五表 1/2 行）：FeathersSlider 注册+TypePath 定义模块
   拼写、sync 的 changed 门。均为新学形态（feathers 类型不入 auto-inventory=widgets_runtime
   手工注册 ThemedText 的同因；泛型 ValueChange 同理），已铸进模板注释与 teaches 针。
2. **🟡 满盘一次**（§五表 4 行）：环境事故非产品缺陷；教训=**editor/export 相前必须
   df**（A6 家族），本轮门禁表记录在案，脚本未加 df 门（记 QA 注意事项）。
3. **⚪ 模板行数超方案估计**：lib.rs.template +354 行（方案 ~100-120）：三桥+watcher
   armed 机制+三滑条面+doc 段的真实尺寸；对齐 T12/T16 模板段的密度口径，无注水。
4. **⚪ GameProgress 只保留 runs_played**：方案写 `best_runs…`（省略号）；score 类字段
   会与 physics 模块条件模板（PickupCount 只在 physics 变体存在）耦合，两变体安全起见
   收敛为一字段+doc 注明「真实游戏自行扩展」。M8 断言面（runs+解锁位）不受损。
5. **⚪ 模板显式注册行=两件而非 SaveStore**：SavePlugin 已注册 SaveStore/SaveStatus/
   profile（T1）；模板补的是 ValueChange\<f32\>（BRP 触发面）与 FeathersSlider（文档
   应用面）——方案清单的字面行被插件吸收，两件新注册行是模板自身面所需。
6. **⚪ tuple `.chain().after(...)` 组合不编译**：本 bevy 的 tuple 组合子该形被
   Curve/Iterator 候选拒绝；改 tuple `.after(set)`（无链）。语义等价：桥/watcher 的
   正确性由 loader 空门保证，`.after` 只收紧同帧序。
7. **⚪ serde 进游戏模板 manifest**（+1 行）：profile 的 serde derive 所需；方案未点名。
8. **⚪ 既有 bsn_game e2e 设 seam**：fixture 新增 save 接线后，老测试加
   `JACKDAW_SAVE_DIR=tempdir` 保证 Fresh 世界（volume=0.160 断言永不读 Saved mix）+
   永不触真档。断言零改动，只加环境。
9. **⚪ 真机 input 改绑=整表替换后 union 恢复**：BRP mutate 的 actions 数组为整表
   （单绑定路径 mutate 未走通，"expected reflected list" 的变体），L3 验证的是
   **恢复半边**（合并律：改绑生效+缺省动作保留）——「改绑写入」的粒度与方案
   「一个改绑」的语义在盘面等价（盘上即为改绑后的表）。
10. **⚪ scaffold_e2e 重档未跑**：渲染工程编译证据=live fixture 暖编（`game-warmbuild-prep.log`）
    +渲染工程 cargo check 零错（早期探针）+teaches 91；重档归 T3 终验门（方案 §四-T3 口径）。
11. **🟡 SV9 返工轮（QA 裁定后）**：修复形态=A（模板 Rust 侧 spawn 场景件，§四 SV9 节
    五件套）。轮内真实红态两次、均已如实归因并修复：①挂接件自身带 marker 下帧重新命中
    attach 查询→滑条连环自spawn（186 实体，暂停屏三条叠 bars）——`Without<SliderValue>`
    断链；②滑条条=BackgroundGradient 被注册表静默剥落+缺 feathers 运行时不着色——
    渐变四件注册+`FeathersPlugins`。另有脚本侧一次红：marker 双实体（authored 行+挂件）
    致位置查询抓到行实体→查询加 SliderValue 过滤。全部修复点已铸进模板注释与 teaches。
12. **⚪ 报告披露修正（QA 偏差 11/12 记账）**：①§〇 bsn_game 门「2/2」实为 **3/3**
    （run-target 重烟也是套件件），已更正；②红→绿叙事口径按 QA §八更正：**第二轮红证
    与首轮同件归档**（`console-game_red.log` 单份已含全部四类症状，含 L7 位置空串——
    原报告写「0.0」与在档「空串」不一致，以归档为准），mtime 只此一份、绿件随后，
    「两轮」系同一红件两波修复的叙事重构，红证本体为真。

## 七、给 QA 的注意事项

1. **BRP 读数的 f32 形态**：资源数值返回全精度（0.42→`0.41999998688697815`）；盘上
   save.json（serde 路径）为最短形（`0.42`）。任何 BRP 数值断言必须容差比较
   （feq/abs<0.001），文件断言可精确。
2. **BRP 键名=定义模块路径**：资源 `jackdaw_runtime::save::SaveStore<t17_save::GameSave>`
   （status 单元变体读作 `"Fresh"/"Loaded"` 字符串，数据变体读作对象
   `{"Recovered":{"backup":"…"}}`——L4 的判定按存在性不走 startswith）；组件如
   `bevy_ui_widgets::slider::SliderValue`、`bevy_feathers::controls::slider::FeathersSlider`
   ——**re-export 拼写（`bevy_ui_widgets::SliderValue`）查不到**，报 Unknown/not in registry。
3. **ValueChange 触发形**：`world.trigger_event {"event":"bevy_ui_widgets::ValueChange<f32>",
   "value":{"source":"<实体串形 767v0>","value":…,"is_final":true}}`——实体必须 JSON
   字符串形；触发即写资源走观察者，与滑条拖动同链。
4. **M14 归因表**：`game save:` 仅允许出现在损坏腿日志（每行自带路径+回退说明）；
   `no config asset` ×3=模板良性态（归因）；`UnresolvedTypes|cannot apply` 零容忍；
   N13=PIE 腿已知 swap_remove 特征，记数即可（本轮 9）。
5. **seam 纪律照旧**：`JACKDAW_SAVE_DIR` 整体替换；PIE 从编辑器环境继承——编辑器
   启动时务必带 seam，否则 PIE 写真档（决策 6-A）。
6. **editor/export 相前 df**（偏差 2 的教训）；编辑器二进制对 dylib 的陈旧错=
   dyld symbol not found，重编 `-p jackdaw` 即愈（t16 同款）。
7. **T3 书单硬性交接两条（QA 偏差 13 落账）**：①**回流 E 显式记档**——save.json.tmp
   是固定名（无 pid/唯一后缀），单写方纪律（决策 6-A 下 PIE 与 direct 双活进程理论
   交错面），后果被损坏路径兜住（备份+默认，无不可挽回丢失）；book game-saves 章
   须写一句、或 SV 记档留案（T1 QA 回流 E 原文移交义务，T2 未动、此处显式交接）。
   ②**SV9 处置结果**写入 T17 闭环材料（修复形态 A=模板 Rust 挂接，teaches 已改钉
   正确形态）。
8. **未动面**：buglist/台账/roadmap 未改（T3 口径）；book 章、键位捕获 UI 指路、
   30 秒用户清单=方案 §四-T3；SV9 已随形态 A 修复（QA 复验口见下）。
9. **SV9 复验口（给 QA）**：①绿态 direct 日志 `grep -c "scene component"`=0（修复前
   3/跑，本轮全腿实测零）；②真机进 level 后 BRP 查 `bevy_feathers::controls::slider::
   FeathersSlider` 实体→`get_components` 含 `bevy_ui::ui_node::Node`+
   `bevy_ecs::hierarchy::Children`（场景子件）+`bevy_ui_widgets::slider::SliderValue`；
   ③暂停屏滑条**肉眼可见**（`GameState.paused=true` 绑定面）：三条带主题滑条、
   Master 按存档值填充至 0.42 且带数字读数、Music/Sfx 满值——`shot-l7-pause-sliders.png`
   在案（本轮 PX 腿实摄）；④滑条可拖（QA 手测口——自动化腿 L7 的 ValueChange
   trigger 链已证：事件→观察者→config→watcher→落盘→重启 sync 回指位置与音量同恢复）；
   ⑤BRP 查询渐变用定义模块路径 `bevy_ui::gradients::BackgroundGradient`（非
   `ui_node::`——该类型定义在 gradients.rs）。
10. **marker 双实体注意**：修复后 marker 同时在 authored 行与其滑条子件上（挂接时
    随件插入）——按 marker 单独查询会得两实体；脚本/QA 查滑条须加
    `bevy_ui_widgets::slider::SliderValue` 联合过滤（t17-live.sh L7 现行写法）；
    marker 实体总数恰 2（authored 行+挂接件）也是连环已断的断言口
    （返工轮内曾实爆 186 实体，见偏差 11）。

## 八、产物清单

- `crates/jackdaw_scaffold/templates/game/src/lib.rs.template`（+354：doc 段+GameSave
  家族+四桥系统+滑条三 marker+观察者+sync+镜像+注册两行+接线）
- `crates/jackdaw_scaffold/templates/game/assets/{hud,menu,gameover}.bsn.template`
  （+66：三滑条+两文档 runs/unlock 绑定）
- `crates/jackdaw_scaffold/templates/game/Cargo.toml.template`（+serde）
- `crates/jackdaw_scaffold/src/lib.rs`（+72：save teaches 测试）
- `crates/jackdaw_runtime/tests/save_store.rs`（+113：回流 F 边界+reload/slot，19 测试）
- `tests/fixtures/bsn_game/src/lib.rs`（+112：save 接线+桥+双跑 demo）、`Cargo.toml`（+serde）
- `tests/bsn_game_run.rs`（+116：双跑 e2e+老测试 seam）
- `loop/qa/t17-live.sh`（新，~700 行，prep/game/editor 三相）
- 归档：`loop/reports/t17t2_{clippy_ws,libtests,clippy_physics,audio_gate,an2,save_store,fast}.log`
  （7 门禁件）+`loop/reports/t17t2_live-*`（25 真机证据件）+`loop/t17-live/`
  （原始运行目录，含 4 份 *_red.log）
