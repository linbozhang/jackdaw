# T17 任务 2「模板示例 + fixture e2e + 真机矩阵」QA 验收报告

> 裁决：**FAIL（单点）** —— 核心验收句（运行时存档接口+四类示例数据持久+重启恢复+三态回退
> 不崩）**全数成立**，程序 10 条偏差全 ACCEPT；但**决策 7-A 设置屏滑条交付面实质未达**（新缺陷
> **SV9**，实锤在案）：hud.bsn 把 `FeathersSlider` 按普通组件写，bevy_scene 拒绝 spawn 其场景
> 件内部（每跑 3 条 ERROR 未披露），滑条实体实测**无 Node、无 Children**——不可见不可拖，
> T16 移交的「音量三滑条入暂停屏」只有数据半边；teaches 针与模板注释把该错误形态钉成了教学
> 样板。修复轮范围严格限滑条一件+披露修正，**已验面零回滚**。
> 验收对象：分支 `loop/t17-save` @ **ef95c9bc**；程序报告 `loop/reports/t17-t2-report.md`。
> 门禁与腿全部 **QA 亲跑**（2026-10-30/31，本机 macOS；全程未设 RUST_BACKTRACE；门前 df=28Gi
> 可用，门后 23Gi——T3 全量门前必须清盘，程序偏差 2 的教训在本轮又吃掉 5Gi）。
> QA 归档 11 件 `loop/reports/t17t2_qa_*`（gates.sh+9 日志+df+exitcodes）。

---

## 一、门禁（QA 亲跑，后台顺序执行，日志全文复核制）

| 门 | 命令 | QA 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **EXIT=0**，0 字节零 Diff | t17t2_qa_fmt.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- --deny warnings` | **EXIT=0**，`warning:` 计数=0，`error` 串 0 | t17t2_qa_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | **EXIT=0**，0 warning | t17t2_qa_clippy_phy.log |
| 单测 | `cargo test --workspace --lib` | **EXIT=0；2990 passed / 0 failed**（逐 `test result` 求和亲算）；**scaffold 91/91**（预期 90→91 达成，第 91=`new_game_project_teaches_the_save_pattern`） | t17t2_qa_libtests.log |
| save_store 套件 | `cargo nextest run --profile ci -p jackdaw_runtime --test save_store` | **19/19 PASS**（=T1 的 17+回流 F 边界+reload/slot 两新针，亲数吻合） | t17t2_qa_save_store.log |
| audio_gate | `cargo nextest run --profile ci --test audio_gate` | **7/7 PASS** | t17t2_qa_audio_gate.log |
| AN2 腿 | `cargo nextest run --profile ci -p jackdaw_runtime --features animation --test animation_scene_load` | **1/1 PASS** | t17t2_qa_an2.log |
| bsn_game e2e | `cargo nextest run --profile ci --test bsn_game_run` | **3/3 PASS**（双跑腿 `a_save_survives_the_fixture_restart` 18.2s 过 + 旧件两件）。**注**：程序报告 §〇 写「2/2」——该套件实际 3 测试（`a_run_target` 重烟也是件），计数笔误，绿态不受损 | t17t2_qa_bsngame.log |
| fast | `cargo xtask fast` | **EXIT=0；Summary 2990/2990（65.0s）**；全文 0 FAILED/0 error/0 diff/0 `warning:` | t17t2_qa_fast.log |
| 磁盘 | `df`（门前/门后） | 28Gi→23Gi | t17t2_qa_df.txt |

门禁结论：**九门全绿**，与程序报告门禁表逐项相符（唯一出入=bsn_game 计数 2/2 vs 实际 3/3，
见偏差 12）。

## 二、T1 回流三硬约束兑现复核

### ① 回流 D（BRP mutate 不置 dirty → watcher→get_mut→dirty 链）—— **成立，源码亲读**

- **watcher 形态**（`lib.rs.template:853-873` `save_audio_changes` / `:897-913`
  `save_input_changes`）：armed 门=`ConfigLoader<T>` 查询空的那一帧**置 armed 并 return**——
  该帧正是 `apply_config_defaults` 注入 authored 值的帧（两 watcher 均
  `.after(apply_config_defaults::<T>)`，:369-370/:374-375），跳过它=「authored 注入不被当
  成玩家改动+首跑零落盘」；之后任何 `config.is_changed()`（滑条观察者/BRP mutate）→
  `save.get_mut()`（runtime save.rs:269-270 置 dirty）→ `flush_saves`（:457-461）同帧落盘。
- **脚本侧纪律**（t17-live.sh:410-413 注释原文「BRP never writes the store's dirty bit, QA
  reflow D」）：L1/L2/L4/L7 的全部玩家侧写档走 `gmut` config 资源（path/value 形），progress/
  unlock 走真 game-over 路径（PlayerHealth=0 → `count_run_over` → `get_mut`）——L2 三局计数
+endless 解锁是活证（盘上 jq 逐字段）。
- **L1 的「首跑零落盘」断言真在跑**：脚本 ：396 `[ ! -e "$SCRATCH" ]`（无目录）+
  :408-409 零 `game save:` warn 计数——armed 帧跳过的两个设计目的各有独立断言。

### ② 回流 E（固定 .tmp 名交错面→book/SV 记档）—— **未落，隐式延 T3（QA 红旗）**

T2 报告零处提及 tmp 名竞态（grep 仅命中满盘行）；方案 §四-T3 书单也未点名。T1 QA 原文是
「移交 T2/T3」，T2 未动且**没有任何显式记录**——现状态只靠「book 章=T3 口径」的隐式链。
**回流主控**：T3 书单必须显式加一句（固定 `.tmp` 名=单写方纪律/双活进程交错后果被损坏路径
兜住），否则该观察在闭环时丢失。不阻本轮裁决（T2 交付面不含 book）。

### ③ 回流 F（迁移边界三探针常驻化）—— **成立，源码亲读+亲跑**

`save_store.rs:501-576` `migration_chain_boundaries_stay_on_the_safe_side` 三段全在：退化步
0→0 → `VersionSkipped{0}`+"walks backwards" warn+文件字节不动（:505-522）；越顶 0→5 →
`Loaded`（serde 终检=真闸门）+写后 save_version=1（:524-549）；版本 5e9 → `Recovered`+备份
字节逐字节原样（:551-575）。另有 `the_store_reports_its_slot_and_reloads_it`（:582-600，
reload 丢内存改动+dirty 清零）。套件 **19/19 QA 亲跑绿**。T1 探针三语义全部转为常驻断言，
兑现口径与 T1 QA §四-④ 的要求逐字相符。

## 三、模板接入面审查（方案 §四-T2 清单逐项源码亲读）

| 项 | 落点 | QA 亲核 |
|---|---|---|
| `GameSave` 四类结构 | template:767-818（progress/unlocks/audio Option/input Option<Vec\<GameActionDef\>）| ✓ 四类齐；GameActionDef 直嵌 runtime serde 面 |
| SavePlugin 一行接线 | :357 | ✓；SavePlugin::build 已注册 T/SaveStatus/SaveStore\<T\>（save.rs:447-449 亲读）——偏差 5 的「方案显式注册行被插件吸收」属实 |
| 桥系统四件 | apply_saved_audio :832 / save_audio_changes :853 / apply_saved_input :879 / save_input_changes :897 | ✓ 就绪门（loader 空）+一次 armed+`.after(apply_config_defaults)`（:369-375）；tuple `.chain().after` 不编译改 tuple `.after`（偏差 6）——语义等价成立（正确性由 loader 空门保证） |
| 设置屏三滑条 | hud.bsn.template:99-148 三行「标签+滑条」+marker 三件 :958-970+观察者 :977-991+sync :1002-1024 | **✗ SV9（下节）**——组件面/观察者/sync 的代码本身正确，hud.bsn 的 FeathersSlider 落地形态错 |
| `ValueChange<f32>`/`FeathersSlider` 注册两行 | :339/:345 | ✓（注册行存在且正确；问题不在注册在场景语义） |
| `OnEnter(GameOver)` 进度 | :412 `(enter_game_over, count_run_over)`+:918-929 | ✓ 第 3 局 push `"endless"`；`get_mut` 同帧落盘 |
| `GameState` 镜像 | :1408-1417+mirror :935-953 | ✓ menu/gameover 绑 `Res(crate::GameState).runs_played`（teaches 针 hud/menu/gameover 四件） |
| doc 段 | :253-281「Saving progress and settings」 | ✓ 两层语义+用户目录与场景分开 |
| teaches 91 | scaffold lib.rs:3763-3824 | ✓ 18 lib 针+hud 4+menu/gameover 各 1+Cargo serde 行，QA 亲跑 91/91 |
| fixture（H2） | bsn_game lib.rs:326-378 seam 门+SAVE_FRESH/LOADED/WRITTEN/CONFIG 标记 | ✓ seam 未设零写入零标记（:340），老 e2e 真档不可触 |
| 双跑 e2e | tests/bsn_game_run.rs:210-301 | ✓ run1 Fresh/0.50/runs=1 → run2 LOADED runs=1/**0.90 压过 authored**/runs=2+盘上 envelope 三断言；老测试 seam（偏差 8）亲读属实，volume=0.160 断言原样 |

**M3/L2 腿路径核**：BRP mutate `SaveStore` 本体不置 dirty（T1 结论），本轮所有真机写档均绕
开该面（config watcher/game-over 路径）——回流 D 的全状态口径在脚本设计层执行到位。

## 四、SV9（QA 新立，🔴）：设置屏滑条未以场景件形态落地

**证据链（全部亲取）**：

1. **每跑 3 条 ERROR，未披露**：`bevy_scene::scene_component: Entity … was spawned with the
   "scene component" bevy_feathers::controls::slider::FeathersSlider, but without its scene…
   should be included using `@…` syntax in BSN`——绿态 direct-l1.log ×9（3 腿×3 滑条）、
   direct-l3/l7 ×3。程序报告零处点名；M14 扫描词表（`UnresolvedTypes|cannot apply|
   cannot-apply|game save:`）不含此形态，WARN_SCAN PASS 是**词表内真、词表外漏**。
2. **机制（fork 源码亲读）**：`FeathersSlider` 是 `#[derive(SceneComponent)]#[scene(
   FeathersSliderProps)]`（slider.rs:52-53）——控件本体=一个 BSN 场景（Node/轨道/把手子实
   体）。按普通组件 spawn 时 bevy 只挂 `#[require(Slider)]` 链，**场景不 spawn**（scene_
   component.rs:44-59 debug 钩子报错；无任何自愈系统，feathers slider.rs 零 spawn_scene 补
   拍路径）。
3. **活体实锤（QA 真机探针）**：fixture direct run→ScreenPressed 进 level→查询
   MasterVolumeSlider 实体（767v0）→`world.get_components`：**`bevy_ui::ui_node::Node` 不在
   实体上、`bevy_ecs::hierarchy::Children` 不在实体上**——滑条无布局无子件，不可见不可交互。
   数据半边（BRP trigger ValueChange→观察者→watcher→落盘→重启 sync 回指）不受扰，即 L7 能
   PASS 的原因——**L7 恰好全程绕开拖拽/视觉**。
4. **方案口径被静默收窄**：方案 §三 L7 通道=「G+**PX**」（截图）；归档零截图，报告未提 PX
   落选。若 PX 腿在案，本缺陷在红轮 2 即暴露。
5. **错误形态被钉成教学样板**：teaches 针（lib.rs:3804）+模板注释（:340-345）钉的是普通组
   件形——每个 `jd new` 新游戏首跑即得 3 条 ERROR+三行空滑条。
6. **报告披露失实**：报告 §一-6「滑条=…带主题的 feathers 场景件」与 §四红轮 1「已修复」的
   叙事，在 UI 半边不成立。

**修复路径核**（QA 已探）：jackdaw_bsn 的 `@` 语法=**文件包含**（`@"base.bsn"`，syntax/
parse.rs:412），非 bevy 场景件包含——hud.bsn 内改 `@FeathersSlider` 大概率不可走；给 BSN 加
场景件包含=动 loader，**违反 T17 自 declared 边界（零编辑器产品代码改动）**。守边界的修复
形态=**模板 Rust 侧 spawn**（feathers 场景件 API/`spawn_scene` 挂进 PauseScreen 行，保住
hud.bsn 的 marker/绑定面）或退回 bevy_ui_widgets::slider::Slider 手拼。属设计裁定，**回流
主控**。

**严重度定性**：不触验收句正主（存档接口/重启恢复/三态回退全绿），但决策 7-A 是主控裁定的
T16 移交兑现面、teaches 是模板产品质量、M14 是「静默失败=存档域最毒形态」的常备防线——
**单点 FAIL 的正主**。

## 五、M 矩阵 14 格逐格判定（QA 核实口径）

| 格 | 判定 | QA 依据 |
|---|---|---|
| M1 双 App 重启恢复 | ✅ | save_store 19/19 亲跑（T1 测试复跑） |
| M2 fixture 双跑 | ✅ | bsn_game 3/3 亲跑，`a_save_survives_the_fixture_restart` 过（断言面亲读） |
| M3 真机重启恢复 | ✅ | L3 脚本逐断言亲读（pkill -9+pgrep 防残留 ：466-467；store/桥/镜像三面）；`l3-store-witness.json` 亲读：Loaded+runs=3+endless+audio 0.7/0.6/0.5+Move 首绑 KeyE+5 动作全 |
| M4 导出一致 | ✅ | `l5-store-witness.json`：Loaded+master=0.75；脚本 staged/assets 双 find 断言 |
| M5 分开铁证 | ✅ | staged 树+assets 树零 save.json（脚本 find 断言）+用户目录形态由 runtime macOS 常驻针钉住+QA 残留检查实证真档树零 t17_save |
| M6 音量桥 | ✅ | fixture e2e 0.90 压 0.50（亲跑）+真机腿（authored 0.9 不洗 0.35、删档→0.9 站住、档在→文件不被 authored 改动碰）逐断言亲读 |
| M7 输入桥 | ✅ | runtime union merge 针+L3（Move=KeyE 生效+缺省 5 动作全留） |
| M8 进度/解锁 | ✅ | L2 三局全走真 game-over 路径（health=0 三轮）+L3 GameState 镜像 runs=3+unlock_note 断言 |
| M9 缺文件 | ✅ | L1（Fresh+无目录+零 `game save:` warn）+H 针 |
| M10 旧版 | ✅ | H：M10a/b/c+回流 F 三边界（H-only=方案口径） |
| M11 损坏 | ✅ | H 五形态+L4 |
| M12 目录异常 | ✅ | H 只读目录+NoDir |
| M13 真机损坏腿 | ✅ | L4+**QA 亲跑复验 PASS**（下节） |
| M14 warn 形态 | ⚠️ 词表内 ✅ / 词表外 ✗ | 零未归因（warn-unattributed.log 空，亲读）+`game save:` 仅 L4+`no config asset` 全归因；**但 3 条/跑 scene-component ERROR 在词表外未披露（SV9）** |

## 六、L 腿逐腿判定 + QA 亲跑

L1-L8 全 PASS（逐腿断言面亲读：L1 无目录/零 warn、L2 四类含 input 整表改绑+三局真路径、
L3 kill -9 三面读回、L4 备份=1+warn=1、L5 staged 无档+同槽 0.75、L6 PIE 写→direct 读回
runs=1+menu.bsn sha 不变、L7 trigger 路径 witness+重启滑条位 0.3499999940395355≈0.35、
L8 双相零未归因）。**QA 亲跑两件**：

1. **M13/L4 复跑（独立 scratch /tmp，全程未触归档件）**：空文件→`status=Recovered{backup:
   save.json.corrupt-1793381914033}`（BRP 读）+备份在盘+warn 点名路径+默认站住（runs=0/
   audio=null）→config mutate 0.44→save.json 复活（envelope 全形）→状态仍 Recovered+
   dirty=false→进程全程未崩。**PASS**（首跑 step5 假红=QA 自己 mutate 参数形错，非产品）。
2. **滑条实体探针**（§四-3）：Node/Children 双缺实锤。

N13 记数=9 复核属实（editor-editor.log 9 处 `swap_remove index`，全部
`jackdaw::pie::drain_game_events` 已知 buglist 特征，L6 断言面不受扰）。

## 七、两铁证独立性判定 —— **成立**

- **铁证①重启恢复三通道**，断言面互不相同：**H**（save_store 双 App，进程内 drop/重建，
  断 store 字段相等）≠**H2**（bsn_game 双进程，断 stderr 标记+盘上 envelope，fixture 二进制
  与模板 binary 不同构）≠**G**（模板 fixture 真窗口进程 kill -9，断 BRP 资源 JSON+盘 witness
  +桥/镜像读回）。三通道三 harness 三断言面，无共享绿灯路径，「缺一不勾」口径守住。
- **铁证②三态回退**：H 侧 M9-M12 全针+真机抽腿 L1（缺文件）/L4（损坏，QA 亲跑复验）+
  M10 边界深度由回流 F 常驻针钉住。headless 全绿+真机抽腿=方案验收口径的字面兑现；「不崩」
  在 L4 腿由进程存活+继续可玩实证。

## 八、红→绿实录纪律核（4 件亲读+mtime 时间线）

| 件 | QA 亲读结论 |
|---|---|
| `console-game_red.log`（23:50） | **真红**：f32 无容差（0.41999998…四连红）+jq 漏 `.actions`（input null）+FeathersSlider/ValueChange 未注册（WARN_SCAN ×15）+L7 sync 门（position 空）**同件全现**。报告的「两轮」叙事与归档有出入：单份红件已含全部四类症状（含 L7），mtime 只此一份、绿件 00:13——**第二轮独立红证未在档**（大概率同一红件两波修复的叙事重构；报告「滑条位置 0.0」与在档「空串」亦不一致）。红证本体为真，叙事口径见偏差 11 |
| `editor-editor_red.log`（00:20） | 真红：dyld Symbol not found（陈旧 dylib，t16 同款）原文在档 |
| `console-editor_export_red.log`（00:46） | **薄**：仅 135 字节 EDITOR_READY 一行，`linking with cc failed`/磁盘余量原文**零归档**（全仓 grep 零命中）——T1 QA 回流 B 同家族（归档口径），记档不阻 |
| 绿态 | 00:11-00:13 game 相 / 00:55-00:57 editor 相，summary 双件全 PASS，warn 零未归因 |

## 九、偏差裁定（程序 10 条+QA 新增 4 条）

**程序 10 条：1-10 全 ACCEPT**（🟡1 三红教训内容成立且已铸进模板注释/teaches/报告 QA 注记，
仅归档叙事口径见偏差 11；🟡2 满盘=环境事故，教训成立但**脚本未加 df 门=QA 注意事项而非机
制**，本轮门禁 df 28Gi→23Gi 复现了紧张度——T3 全量门前清盘必须执行；⚪3 行数 354、⚪4
GameProgress 收敛、⚪5 注册两行、⚪6 `.after` 无链、⚪7 serde 入 manifest、⚪8 老 e2e seam、
⚪9 input 整表改绑（恢复半边语义等价，L3 亲证）、⚪10 scaffold_e2e 重档延 T3（暖编+check
+teaches 三证在案）——逐条与源码/归档对得上，无注水）。

**QA 新增**：

- **12（报告计数笔误）**：bsn_game 门「2/2」实为 3/3（`a_run_target` 重烟也是套件件）。
- **11（红→绿叙事 vs 归档口径）**：见 §八；不阻，建议报告补一句「第二轮红证与首轮同件，
  归档为最终红态」。
- **13（E 回流未显式落账）**：见 §二-②；T3 书单硬性项。
- **14（SV9，阻断级）**：见 §四；唯一 FAIL 依据。

## 十、裁决

**FAIL（单点）**。依据浓缩：九门禁亲跑全绿（fast/libtests 双通道 2990、teaches 91、
save_store 19/19、AN2 1/1、bsn_game 3/3、物理双包/fmt/全仓 clippy deny-warnings 零红）；
T1 回流 D/F 兑现亲核成立（E 未落账=偏差 13）；重启恢复三通道+三态回退两铁证独立性成立；
M13 亲跑复验 PASS；矩阵 14 格中 13.5 格绿。**唯一阻断=SV9**：设置屏滑条交付面实质未达
（bevy_scene 拒绝场景件、实体无 Node/无 Children 实锤、每跑 3 条未披露 ERROR、teaches 钉死
错误形态、方案 PX 通道静默落选、报告 §一-6 UI 半边失实）。

**修复轮范围（不回滚已验面）**：①模板侧修复滑条落地形态（守「零编辑器产品代码改动」边界，
方案内属设计裁定点→主控裁形：模板 Rust spawn 场景件 or Slider 手拼 or 立 SV9 记票+决策 7-A
降级）；②修复后 **L7 补 PX 截图腿**（方案原口径）+game 相受扰腿复跑；③M14 词表加
`scene component`（或零 ERROR 容差）；④teaches 针与模板注释随修复更新；⑤报告披露修正
（§一-6/§四红轮叙事/bsn_game 计数）。

**主控替代路径**（若裁定滑条面降级为 SV9 记票+决策 7-A 数据级兑现）：则本报告条件改判
**PASS**——须同时满足：SV9 入账（SV9 编号现成）、模板 ERROR 形态至少消音或 doc 注明、
30 秒清单的滑条步改为数据级路径、T16 移交面在 roadmap 台账记「UI 半边未达」。二选一，均
为合法闭环；QA 建议前者（模板是本任务的产品，错误教学形态代价最高）。

**放行 T17-T3 的建议**：T3 可以**并行启动文档面**（book 章结构/三态回退行为表/JACKDAW_SAVE_DIR
缝/路径表均不依赖滑条修复），但 **T17 闭环（合入 main）必须在 SV9 修复轮落判之后**；T3 全量
门前清磁盘（本轮门禁吃 5Gi 实证）；T3 书单硬性加两条=回流 E（.tmp 单写方纪律一句）+SV9
处置结果。

## 十一、用户 30 秒清单草稿（QA 拟，T3 final-qa 口径；标注 SV9 影响）

1. 打开 jackdaw→新建游戏（Game 模板）→Play/直跑，开局菜单应显示 `Runs: 0`（存档 Fresh，
   无文件无目录——首跑安静）。
2. 进一局→故意死一次→Game Over 计数 +1→**重启游戏**→菜单 `Runs: 1`（重启恢复正主）。
3. 暂停屏拖 Master 滑条→音量即变→**重启**→滑条位置与音量同恢复。【**SV9 修复前此步不可
   达**：滑条不可见不可拖；临时替代=BRP/配置路径改音量，持久半边已证】
4. 手动删 `~/Library/Application Support/<game-id>/save.json`→重启→游戏照跑零报错
   （缺文件→安静默认）。
5. 把 save.json 改成任意乱码→重启→游戏照跑+日志一行 `game save:` warn+旁边多出
   `save.json.corrupt-<时间戳>` 备份（损坏→安全回退）。

## 十二、QA 收尾自查

门禁后 df=23Gi（记录在案）；无残留进程（pgrep 双查零命中）；真档树
`~/Library/Application Support/` 无 `t17_save`/`bsn_scene_game`（零污染）；QA 临时 scratch
与探针脚本已清；归档只写 `loop/reports/t17t2_qa_*`（11 件），未动产品代码/buglist/台账/
程序归档件。

—— QA（loop 自动化验收）2026-10-31
