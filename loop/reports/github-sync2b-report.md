# GitHub 主干第二轮同步（#791-#799）守卫修复与收尾验证报告（sync2b）

- 日期：2026-11-07
- 执行：程序 agent（jackdaw Loop 工作流）
- 基线：`cdc839bc`（9 上游提交合并，工作树含前序会话未提交融合修复）
- 收尾：main = `bd16c5fb`（本报告随提交入库，不推任何远端）

## 一、核心结论（主控预判修正）

**19 个 guards 失败全部不是本轮 9 提交合并（cdc839bc）引入的。** 决定性证据：在合并前基线 `b1351c9d` 的独立 worktree 跑同一 guards 套件，19 个失败**逐一同样复现**（356 通过 + 19 失败 = 375，与当时「guards 375/375」的门禁声称数字吻合但内容相反——该声称不成立，失败集在合并前就已存在）。合并本身对 guards 的净贡献为零失败：上游新增 8 个测试全部直接绿（383 = 364 + 19）。

**唯一根因（19/19 同源）**：第一轮同步（04d8fe44）时 guards 是独立测试目标 `[[test]] name = "guards"`，其 crate 名就是 `guards`，`std::any::type_name::<T>()` 产生 `guards::…` 前缀，测试 fixture 文档按此拼写类型路径。第二轮 review2（b1351c9d）把测试树折入上游单一 `tests/editor` 二进制（crate 名 `editor`）后，所有注册路径前缀变成 `editor::guards::…`，但五份测试文件的 fixture 拼写**没有跟着改**（同批只有 `scaffolded_component_flow.rs` 改对了）。后果分三族：

| 族 | 失败机制 |
|---|---|
| reference_rewrite ×6 | 文档拼写 `guards::…::Signpost` 在注册表查不到 → `rewrite_struct` 的 `get_with_type_path` 返回 None → 资产字段的字段类型解析不出 → `rewrite_ast` 替换 0 处 → 改名/移动后盘上引用文件不重写（referrers 表来自无类型字符串扫描所以正常，恰好把断点精确逼到注册表查找） |
| reference_audit ×3 | 同理 `Signboard` 不应用 → 审计按类型化资产字段找坏引用，找到 0 条（预期 1-2） |
| game_ui ×5 / game_flow ×3 / game_flow_template ×2 | HUD/Menu/Level/GameOver 文档的组件与 BindPath 拼写 `guards::…` 全部不解析 → 实体不带标记组件、绑定无 context、屏幕不翻转、玩家不生成 |

**处置分类：19 项全部 = 「测试锚需更新」（裁定政策第 1 条）**。fixture 是按「项目 crate 名 = 测试目标名」的仿真写的，单二进制化后注册前缀变了，拼写跟进即可；不涉及任何 Loop 正确性能力（R1/Y31/Y9/T05 的能力本体都在产品代码里，未被动过——`reference_rewrite.rs` 产品文件在 b1351c9d↔HEAD 之间零改动）。修复 = 五份文件把 `guards::` 前缀改为 `editor::guards::`（与 `scaffolded_component_flow.rs` 既有惯例一致），commit `8d60d715`。

## 二、19 项逐个处置表

| # | 测试 | 失败现场（合并树） | 根因 | 处置 |
|---|---|---|---|---|
| 1 | reference_rewrite::renaming_a_referenced_file_rewrites_its_referrers_and_nothing_else | 盘上引用仍是旧路径（rewrite_ast 替换 0） | fixture 拼写 `guards::` vs 注册 `editor::guards::` | 测试锚更新 ✅ |
| 2 | reference_rewrite::renaming_a_material_rewrites_the_overrides_holding_it_and_nothing_else | 同上（#Sign 引用未随走） | 同上 | 同上 ✅ |
| 3 | reference_rewrite::renaming_a_folder_rewrites_prefixed_references_on_component_boundaries | 组件边界引用重写 0 处 | 同上 | 同上 ✅ |
| 4 | reference_rewrite::moving_a_file_rewrites_references_and_retargets_the_card | 移动后盘上引用未跟走 | 同上 | 同上 ✅ |
| 5 | reference_rewrite::renaming_a_referenced_material_under_a_dirty_tab_keeps_it_dirty_and_in_step | save 写回的仍是旧引用 | 同上 | 同上 ✅ |
| 6 | reference_rewrite::a_rewritten_document_is_not_read_back_and_a_reimport_reloads_in_place | 场景里查无 Signpost（组件未应用） | 同上 | 同上 ✅ |
| 7 | reference_audit::a_loaded_scene_leaves_one_summary_warning | 加载摘要 0 条坏引用 | 同上（Signboard 不应用→审计无发现） | 同上 ✅ |
| 8 | reference_audit::asset_missing_list_gathers_the_findings_headless | 清单 0/2 | 同上 | 同上 ✅ |
| 9 | reference_audit::asset_audit_reports_and_fills_the_findings | 「no broken references」 | 同上 | 同上 ✅ |
| 10 | game_flow::a_switch_leaves_zero_residue_in_both_directions | menu 绑定解析 0/3 | 同上（Menu 文档组件+BindPath 全不解析） | 同上 ✅ |
| 11 | game_flow::bindings_rewire_onto_the_freshly_spawned_scene | wire_menu context None | 同上 | 同上 ✅ |
| 12 | game_flow::one_click_is_one_event_across_scene_reloads | 点击不产生 start 事件（Action 绑定不解析） | 同上 | 同上 ✅ |
| 13 | game_ui::the_hud_is_the_only_ui_and_it_loads_with_its_bindings_resolved | 「the authored marker loaded」失败 | 同上（hud 模板 `{{crate_name}}` 替换串过期） | 同上 ✅ |
| 14 | game_ui::flipping_game_state_moves_the_screens | 屏幕可见性不变（Hidden≠Inherited） | 同上 | 同上 ✅ |
| 15 | game_ui::the_bar_follows_player_health_and_misses_it_loudly | 血条宽度 1.0≠0.87（Field 绑定不解析） | 同上 | 同上 ✅ |
| 16 | game_ui::buttons_flip_state_only_through_the_observer | 「Resume drops the veil」 | 同上 | 同上 ✅ |
| 17 | game_ui::a_typoed_field_fails_loudly_and_a_fix_lands_quietly | 修正后 ratio 不落（typo 腿 BindPath 前缀过期） | 同上 | 同上 ✅ |
| 18 | game_flow_template::a_restart_lands_the_run_back_where_it_began | NoEntities(PlayerMarker)（模板玩家组件未应用） | 同上（模板 crate_name 替换串过期） | 同上 ✅ |
| 19 | game_flow_template::the_flow_walks_the_three_documents_and_back_with_zero_residue | Start 后 flow 停在 Menu | 同上 | 同上 ✅ |

修复后族级复跑：`guards::reference` 21/21、`guards::game` 28/28、全量 `guards::` **383/383**。

## 三、前序会话 WIP 的收编（commit 04411579）

任务开始时工作树并不干净（任务简报称干净，实际有前序会话 21 文件未提交改动）：那是一次进行到 25→19 失败后被中断的融合修复。逐文件审阅后确认其为有效工作（#799 异步存盘管线的共存修复），收编为独立 commit：

- **快照基线**：`settle_tab_after_save` 改为接收 `PreparedSave` 快照时刻的 `snapshot_depth/snapshot_pushes/snapshot_hash`（随 `WaitingSave` 穿越写盘线程），do/undo/redo 与写盘竞争时按「文件实际拿到的内容」落基线，而非写盘落定时刻的栈位。
- **forgotten 状态**：`CommandHistory::forgotten()` + dirty watcher 尊重之（sidecar 落地后保存失败/外部文件自持 → 保存前一直脏）。
- file.delete 单文件兜底（关闭会收走最后一个 tab 时照样删，目录仍按 N3 拒绝）；pre-launch 存盘改走 `save_tabs(modified_tabs)`；bsn Name patch 改从 AST patch entities 读；`load_bsn_assets_onto` 传 assets 上下文；launch 渲染器并诊断设置走 `render_backend`；测试树跟随新管线（上游单 temp slot、去 .bak 轮换断言、macOS /var 规范化、physics 扩展 spawn 行过滤、LiveEditKind 字段、`scene.save` 后 `wait_for_saves`）。

## 四、六模块门与本轮新修（commit bd16c5fb）

六模块单跑暴露三类问题，其中两类是**本轮（含 WIP 收编树）新发**、一类预存：

1. **operators::authoring_ops::every_entity_taking_operator_is_classified（新发，已修）**：census 表（b1351c9d 手工并表遗留）缺 `brush.selection.set_faces` 行（Loop 既有算子，entity 参数、非 selection fallback）且 `terrain.scatter.adopt` 重复两行、physics 两行错序。补行+去重+按 sort 序排表。
2. **stage::save_before_play::play_saves_the_edited_scene_before_the_game_starts（#799 异步管线竞态，已修）**：play 的 save-before 派发写盘在工作线程；探针证明 settle 逻辑正确但测试给的两帧 `app.update()` 在本机跑不赢写盘。按裁定政策第 3 条与 04411579 既有先例，测试加 `wait_for_saves` 等待原语（不 sleep 硬等）。
3. **prefabs::prefab_lifecycle::prefab_file_change_triggers_reload（并行争抢环境缺口，已修）**：单跑恒绿、串行 `--test-threads=1` 79/79 全绿，仅 12 线程并行时 macOS watcher 事件送达超过 3s 预算（A28 同类）。测试注释本就写明「generous deadline to avoid flakes」——预算 3s→15s，不弱化断言（reload 本体仍必须发生）。

## 五、A30 消化结论

**A30（scenes::scenes_swap::a_map_pasted_from_another_scene_takes_a_copy_of_its_cells）在 #794 之后仍未绿。** 基线 b1351c9d 与当前树同样失败，#794 的 swap-without-reread 没有消化它。维持原票据裁定（T16 域，跨页重读丢弃未保存细胞，待裁），本轮不动。

## 六、门禁表（终值，全部亲跑）

| 门 | 命令 | 结果 |
|---|---|---|
| fmt | `cargo fmt --check` | ✅ 干净（exit 0） |
| clippy | `cargo clippy --workspace -- -D warnings` | ✅ 干净（exit 0） |
| libtests | `cargo test --workspace --lib` | ✅ **70 二进制 3876 通过 0 失败**（上轮 3851 → 上游新增） |
| guards | `cargo test -p jackdaw --test editor guards::` | ✅ **383/383**（任务书 375/375 + 上游本轮新增 8） |
| operators | `--test editor operators::` | ✅ 417/417 |
| inspector | 同上 | ✅ 235/235 |
| prefabs | 同上 | ✅ 110/110 |
| scenes | 同上 | ⚠️ 331/332（唯一红 = A30，票据待裁） |
| viewport | 同上 | ⚠️ 182/183（唯一红 = `a_preset_picked_in_the_quality_menu…`，**基线同败**，预存） |
| stage | 同上 | ⚠️ 577/581：1 稳定红 = `the_footer_names_the_scene…`（**基线同败**，A28 单）；3 间歇红 = `gltf_authoring` 三件（**单跑 14/14 绿**、上一轮模块跑亦全绿，12 线程并行下资产管线加载超时类争抢，A28 同类环境缺口） |

A28 注记：A28 原始清单为「stage 套件 7 用例本机预存失败」；本轮 stage 稳定红只剩 footer 一件（其余历史上间歇），gltf 三件为并行负载敏感型间歇红。

## 七、拆账（本 commits，均未推任何远端）

| commit | 内容 |
|---|---|
| `04411579` | 收编前序会话 WIP：#799 异步存盘快照基线/forgotten/file.delete 兜底/save_tabs 迁移/bsn Name patch/测试树跟随新管线 |
| `8d60d715` | 19 个 guards 失败的唯一根因修复：五份测试 fixture 拼写 `guards::` → `editor::guards::` |
| `bd16c5fb` | 六模块门收尾：authoring census 表补行去重排序、save_before_play 加 wait_for_saves、prefab watcher 测试预算 3s→15s |

## 八、遗留 / 待裁

1. **A30**（跨页粘贴 map 细胞丢失）维持票据，#794 未消化，T16 域待裁。
2. **A28 扩充**：stage footer（稳定红，基线同败）+ stage gltf_authoring 三件（并行间歇红，单跑绿）+ 本次 prefab watcher 争抢（已用预算放宽消化）——同属「本机并行/环境敏感」族，建议下轮统一裁（候选方向：模块跑降到低并行度 `--test-threads=4` 或逐件加等待预算）。
3. **`clippy --all-targets` 超集观察**（非本轮门禁形态）：`editor/jackdaw_editor_core/src/remote_ops.rs` 有 items-after-test-module 与 assertions-on-constants 各若干，均为 b1351c9d 之前既有结构（本轮零改动）；若未来收紧门禁形态需一并清理。
4. **b1351c9d 门禁声称纠偏**：该 commit 的「guards 375/375」「六模块全绿除 scenes」与实测不符（19 个 guards 失败在彼时已存在，operators/prefabs 亦有各自问题）；本轮报告即为该账的更正记录，后续轮次的门禁数字以本报告口径为准。
5. 真机 PIE 端到端抽验仍留（上轮遗留原样）。

## 九、证据归档（loop/github-sync/）

- `sync2b-fmt.log`（fmt 终查，exit 0）
- `sync2b-clippy.log`（workspace -D warnings，exit 0；文件尾部另含一次 `--all-targets` 超集探查的 remote_ops 记录）
- `sync2b-libtests.log`（70 二进制汇总：3876/0）
- `sync2b-guards.log`（383/383）
- `sync2b-modules.log`（首轮六模块：暴露 operators/stage/prefabs/viewport 问题）
- `sync2b-module-fails.log`（失败名单抓取）
- `sync2b-probe.log`（save_before_play 双跑复现 + census 修复前现场）
- `sync2b-modules-final.log`（终值六模块）
- 基线对照：`/tmp/jd-base` worktree 跑批（b1351c9d：guards 19 败复现、operators/prefabs/viewport/stage/scenes 对照），原始输出在 /tmp/jd-base-guards-full.log、/tmp/jd-base-modules.log（临时区，要点已录入本报告）
