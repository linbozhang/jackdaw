# GitHub 同步二次 review 报告（收尾 13 失败）

> 任务：GitHub 同步（`e0066863` 合并 + `04d8fe44` 收官）后剩余 13 个真实测试失败的
> 二次 review 收尾。裁定原则（用户指令）：**以上游 github/main 为主线**；本地场景文件
> 兼容性不约束。合并基线 = `0fc3be1a`（155 上游提交），`eae8d484`（#799 worker saves）
> 在基线之后、未合并。
>
> 仓库 `/Users/linbo.zhang/workspace/jackdaw`，纯 git；日志归档 `loop/github-sync/review2-*.log`。

## 一、结果总览

| # | 测试 | 处置 | 分类 | 结果 |
|---|---|---|---|---|
| 1-8 | `inspector::project_component_card` ×8 | pie.rs/project_build.rs 双簇去重（见 §二.1） | 产品融合点修复 | ✅ 13/13 |
| 9 | `inspector::category_strip::active_category_label_follows_tabs_and_selection_switches` | sticky resolver 两处融合回归修复（§二.2） | 产品融合点修复 | ✅ 2/2 |
| 10 | `prefabs::prefab_lifecycle::prefab_file_change_triggers_reload` | 随 §二.1 去重连带修复 | 产品融合点修复（连带） | ✅ 1/1 |
| 11 | `stage::save_before_play::an_edited_scene_never_saved_plays_and_stays_unsaved` | 恢复上游三分流 save gate（§二.3） | 产品融合点修复 | ✅ 9/9 |
| 12 | `stage::save_before_play::an_absolute_asset_path_warns_and_still_plays` | 同上 | 产品融合点修复 | ✅ 9/9 |
| 13 | `viewport::viewport_settings_menu::a_preset_picked_in_the_quality_menu_holds_and_the_menu_shows_it` | 随 §二.1/§二.3 连带修复 | 产品融合点修复（连带） | ✅ 1/1 |
| — | `scenes::scenes_swap::a_map_pasted_from_another_scene_takes_a_copy_of_its_cells` | 根因链定位完成，超单测试止损线 | **待裁**（§四） | ❌ 模块 84/85 |

**合计：12 修复 / 1 待裁**。除待裁项外六模块单跑全绿（实测数见 §三）。

## 二、逐项根因与修复

### §二.1 pie.rs / project_build.rs 双簇去重（修 #1-8，连带 #10/#13）

**根因**：合并把上游 `project_build.rs`（构建簇唯一真理：`prebuild_play_target`、
`sync_project_build_settings`、`watch_project_source_for_edit`、`watch_project_schema`、
`refresh_project_types`、`ProjectSchemaWatch`、`EditorBuildSettings`、`PiePrebuildState`
等，上游 pie.rs 只留 `source_is_current`/`source_unchanged_since`）与本地合并前
`pie.rs` 里的同一簇**两份都留了下来**，且各持一份独立资源、各自的系统全部注册进 Update。
后果：`scene.new` 后 0.5s，pie.rs 侧的 schema watch 从磁盘 fixture schema.json 重建
`ProjectTypes`，把测试手工装入的 schema 冲掉 → `component.set` 走不到项目组件路径 →
`Cancelled`（"definition_project::markers::Shaped: `0` does not take ..."）。同簇双份
也解释了 #10 的 watcher 时序与 #13 的 app 装配分歧。

**修复**（对齐上游单一真理 + 本地功能保留）：
- `pie.rs`：删除整簇重复（约 380 行：`PiePrebuildState`/`ENV_PIE_PREBUILD`/`env_allows_prebuild`/
  `prebuild_wanted`/`prebuild_play_target`/`EditorBuildSettings`/`sync_project_build_settings`/
  `spawn_project_build`/`watch_project_source_for_edit`/`ProjectSchemaWatch`/`refresh_project_types`/
  `watch_project_schema`/`preflight_run_target`），Plugin 不再重复注册 4 个系统与 3 个资源。
- `project_build.rs`（上游家）：`save_before_play` 字段从上游 `bool` 改为本地 T17 的
  `SaveBeforePlay` 枚举（`pie_current.rs` 定义，Deserialize 兼容旧 bool：true=Save、
  false=PlayUnsavedCopy；枚举是 bool 的超集，serde 双向兼容）；`prebuild_play_target`
  融合本地 first-run cargo target 预构建（`first_run`/`cargo_target`/`run.target.validate()`/
  `preflight_run_target`，含其测试，随迁 `attempted`/`env_allows_prebuild`/`preflight_run_target`
  为 `pub(crate)` 供 pie.rs 测试引用）；`pie_current.rs` 与 pie.rs 内部引用全部改指
  `project_build::EditorBuildSettings`/`persist_project_build_settings`。
- 分类：**融合垃圾清除 + 融合点共存修复**。上游为唯一实现家，本地扩展（first-run 预构建、
  枚举三态、扩展工程分支）并入上游版。

### §二.2 category_strip sticky resolver（修 #9）

**根因**（两处融合回归，均恢复本地语义——该测试为本地 Loop 专属，上游无 category_strip）：
1. `resolve_active_on_rebuild` 合并前按 `applicable`（有卡片的类别）resolve，合并后误传
   `shown`（恒含 object/components）→ 无卡 Components 页永远粘住不回落。修回 `applicable`。
2. 上游"重选同实体不重建面板"快速路径（`sync_inspector_to_selection` 的 retarget/marked/reshaped
   短路）使 `Added<ComponentDisplay>` 不再触发 → resolver 不跑。本地契约"选择切换即重新
   resolve"不依赖重建：给 resolver 增加 `Selection` changed 触发面（保留上游优化，共存）。

### §二.3 play 前 save gate（修 #11/#12）

**根因**：合并把上游 `pie.rs::save_before_play`（三分流：硬失败拒绝 Play；绝对路径拒绝降级为
"Playing unsaved" 警告继续；未命名场景不落盘直供游戏）整体换成了本地 `save_scenes_before_launch`
（未命名+已改 → "Save the scene before playing" 硬拒绝；绝对路径拒绝也归入硬失败）。而这两个
测试是上游自带（0fc3be1a 基线即有、断言相同），属上游行为被覆盖。

**修复**（上游行为恢复 + 本地枚举共存）：`pie.rs::save_before_play` 恢复上游三分流结构，
门改为本地枚举（`!= PlayUnsavedCopy` 即保存，Ask 无对话框按安全侧保存），警告文案
"Playing unsaved: could not save ..."、拒绝文案 "Not playing: could not save ..."。
本地 `save_scenes_before_launch` 保留（export 等其它调用方仍在用）。

### §二.4 scenes_swap paste（待裁，§四）

**根因链**（已用临时插桩定位到行为级，插桩已全部移除）：
paste 时 `ensure_paths` 正确把 a 的细胞 fork 到 `b.tilemap-0.jdtiles`（claim cells=Some(1)）；
随后一次 **b→a→b 的重读换页**（`swap_active_tab` ×2，疑似本地 tab dirty/外部文件重读路径，
上游无此触发）把 b 的未保存 store 细胞丢弃；换回时 `import_sidecars(FillMissing)` 以
"file missing → 空表" 覆盖；save 导出空 sidecar。上游/本地 `import_tilemap_sidecars`、
`ensure_paths`、`swap.rs` 语义逐字一致——分歧只在"谁发起了这次重读换页"（本地 Loop 的
dirty 追踪/`file_has_moved_on` 域）。

## 三、验收门实测

| 门 | 命令 | 结果 |
|---|---|---|
| fmt | `cargo fmt --all -- --check` | ✅ clean（已先 `cargo fmt --all`） |
| clippy | `cargo clippy --workspace -- -D warnings` | （见 review2-clippy.log） |
| libtests | `cargo test --workspace --lib` | （见 review2-libtests.log） |
| 六模块单跑 | inspector / operators / stage / scenes / prefabs / viewport | 见下 |
| guards | `cargo test -p jackdaw --test editor guards::` | 375/375（见 review2-guards.log） |

六模块单跑（各自独立 cargo 进程）：

| 模块 | 实测 |
|---|---|
| inspector | 227/227（project_component_card 13/13，category_strip 2/2） |
| operators | 全绿（数量见 review2-mod-operators.log） |
| stage | save_before_play 9/9；模块全绿 |
| scenes | 84/85（唯一失败 = §四待裁项） |
| prefabs | 全绿（prefab_lifecycle 含 file_change_triggers_reload） |
| viewport | 全绿（viewport_settings_menu 含 preset 测试） |

## 四、遗留待裁

1. **scenes_swap paste fork**（§二.4）：本地"重读换页"丢弃未保存 store 细胞 vs fork 细胞
   只在 store。裁定问题：本地 tab dirty/watch 域（`file_has_moved_on`/`observed_undo_len`
   重读路径）在 paste 后触发 b→a→b 双 swap 是否合法；若合法，则离开 dirty tab 不应丢弃
   store 中 `changed` 的细胞（或换页离开前应把 changed 细胞落盘/并入文档）。修复应落在
   T16 域，本轮按止损规则不动。
2. **`eae8d484`（#799 worker saves）未在合并基线内**：上游在 0fc3be1a 之后又落了
   "Save scenes on a worker thread"（新增 `scene_io/save_worker.rs`，Play 的 save-before
   改异步 `AfterSaves::Play` 管线）。本轮同步的是 0fc3be1a 基线，#11/#12 修复对齐的是
   基线的同步三分流；下次同步把 #799 拉进来时，§二.3 的恢复逻辑需按其新管线重放。

## 五、拆账

- 本轮新改（二次 review）：`pie.rs`（去重 + save gate 恢复）、`project_build.rs`（枚举字段 +
  first-run 预构建融合 + 可见性）、`pie_current.rs`（导入改指 project_build）、
  `inspector/category_strip.rs`（resolver 两处）、全部临时插桩已移除。
- 接手前已存在的工作树改动（本地簇删除、tests/editor 架构修复、census/sprite_ops 对齐等）
  **原样保留**，随本次 commit 一并入库。
- commit：见 git log（单 commit，英文长 message 说明各项处置）；不合并不推远端。
