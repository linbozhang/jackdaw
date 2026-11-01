# T21-T1 程序报告：上游六 PR cherry-pick 试合探针轮（决策 1-A 定案门）

> 分支 `loop/t21-sprite`（自 main 5a11deff）。任务书=`loop/plans/t21-sprite.md` §四-T1
> +§五-决策 1；主控裁定 8 决策点全按建议。上游对照基线=本地标签
> `nightly-2026-10-27`（merge-base 5c3ba8ea）。归档=`loop/reports/t21t1_*`。
> 报告日期 2026-11-01。

## 一、结论（定案门）

**决策 1 = A 路全量落地。六个 PR 全部零文本冲突自动合并，编译与测试全绿，
回落 B 不触发，估时表的 +3 天浮动不进风险表。**

- 六 PR 合计 7,073 行插入（含约 3,300 行测试族）原样入库，保持上游作者
  （Joe Buehler）与提交信息，链序 #650→#653→#654→#655→#656→#657。
- 方案 §0 预判的 12 文件重叠面，实测为 **15 文件**（多出的 3 个是
  tests/operators/{authoring_ops,main,remote_coverage}.rs——#657 的 operator
  参数白名单行），全部 git 自动合并成功，无一需要人工消解。
- 方案担心的「nightly 与 main 的中间 34 commit 隐性依赖」未兑现：六 PR 在
  无中间提交的情况下独立编译、独立通过。

## 二、六 PR 逐个落判表

| PR | 上游 commit | 本分支 commit | 内容 | 插入/删除 | 冲突文件 | 冲突账 | 落判 |
|---|---|---|---|---|---|---|---|
| #650 | 91fa6afe | 5f55c9ee | 2D 世界场景拾取+描边（sprite_stage 639 行+viewport_2d 坐标映射+input.pointer `space=world`） | +1312/−9 | 0 | lib.rs/test_input.rs/stage-main 自动合并；SP6 逻辑像素修随之入库（viewport_2d `world_to_target_pixel`/`target_pixels_per_stage_pixel` 在位） | **落地** |
| #653 | 8b043358 | 6f6b9f97 | 移动 gizmo+方向键微调+undo（sprite_gizmo 724 行） | +1651/−38 | 0 | scene_io 三文件的钩子行精确落入本地函数体（`forget_dragged_entities`/`collect_bsn_inline_assets`/`normalize_runtime_derived_values`）；transform_ops 方向键路由（sprite 先行、3D 回落）与本地 SnapSettings 网格步进共存 | **落地** |
| #654 | e7cb8638 | 4a4d7778 | 旋转+缩放 gizmo（sprite_gizmo +318） | +623/−38 | 0 | gizmos.rs 渲染层行自动合并 | **落地** |
| #655 | 5e865fad | 3a30d5ef | 拖拽吸附（网格/像素/邻 sprite 边；sprite_snap 301 行+jackdaw_snap +124） | +1270/−103 | 0 | jackdaw_snap 本地既有 crate 直接扩展，其 #[cfg(test)] 单测族随行（libtests +7 增量主体） | **落地** |
| #656 | edf167e5 | 211d6061 | 2D 世界参考线+吸附（CanvasGuides 扩到世界场景；canvas_snap +187） | +1028/−186 | 0 | commands.rs 文档行、scene_types 的 CanvasGuides 字段扩展自动合并 | **落地** |
| #657 | 10a53456 | 00df93ba | Add 菜单 2D 组+`sprite.add` operator+图片拖放改路由（sprite_ops 307 行） | +1189/−14 | 0 | creation_taxonomy `two_d()` 组（按 OpenScene2dRoot 出现）+`collect()` 钩子、entity_ops `spawn_template_under`/`scene_2d_parent`、boot_ops/authoring_ops/remote_coverage 三处参数白名单行全部落位 | **落地** |

**回落清单：空。** 无一 PR 触发语义级回落判据（本地 T08-T20 与上游无同函数设计
分歧——重叠面两侧改动物理上不相交，见 §三）。

## 三、冲突账细节（15 重叠文件的合并质量复核）

git 静默合并≠语义正确，逐文件复核了合并后落点（合并正确性的 H 侧证据）：

| 文件 | 本地改动面 | 上游切口 | 复核结论 |
|---|---|---|---|
| src/lib.rs | +124/−19（T 系模块与插件注册） | #650/#653/#655/#657 各 1-2 行 | 4 个 sprite 模块声明+3 处插件注册落位（lib.rs:164-167,454-455,496） |
| src/test_input.rs | +375/−9 | #650 +22 | `space @ ("canvas" \| "world")` 臂+`world_to_target_pixel` 映射+错误文案三值，全落位（:643-659） |
| src/gizmos.rs | +1 | #653 +11 | TRANSFORM_GIZMO_LAYER=3+`run_if(three_d_world_is_current)` 落位 |
| src/scene_io/load.rs | +41/−6 | #653 +2 | 两个 forget_drag_resource 行插在 UiManipulation 之后 topo 之前（:830-831） |
| src/scene_io/mod.rs | +39/−16 | #653 +10 | `sprite_render_component_paths()` 新函数落在 SKIP_COMPONENT_PATHS 邻位（:91-100） |
| src/scene_io/save.rs | +137/−26 | #653 +10 | 两处钩子（inline assets 的 sprite 渲染件跳过 + normalize 的 patch 清除）各落本地函数体内（:698,992-996） |
| src/transform_ops.rs | +15 | #653 +6 | `nudge_sprites` 先行、未中则 3D 网格步进回落的分支序正确（:283-289） |
| src/viewport.rs | +172/−17 | #653 +15 | ViewportLayerCounter.last=TRANSFORM_GIZMO_LAYER+camera_layers 三层数组落位（:134,353） |
| src/commands.rs | +173/−6 | #656 1 行 | CanvasGuides 文档行（UI or 2D world）落位 |
| src/boot_ops.rs | +2 | #657 +1 | `("sprite.add", "parent")` 白名单行落位（:283） |
| src/creation_taxonomy.rs | +34/−2 | #657 +26 | `two_d()` 函数+`TWO_D_GROUP`/排序常量+`collect()` 调用全落位（:247,387） |
| src/entity_ops.rs | +181/−22 | #657 +20 | `spawn_template_under`+`scene_2d_parent` 接线+SpriteAddOp 注册落位（:864-867,2367） |
| tests/operators/{authoring_ops,main,remote_coverage}.rs | 各 +1~+6 | #657 各 +1 | `mod sprite_ops;`+`sprite.add` 参数行三处落位 |
| tests/stage/main.rs | 本地多族 | 六 PR 各 +1 | sprite_drop/sprite_gizmo/sprite_picking/sprite_snap/world_guides 五模块全挂接 |

物理双包/scaffold/teaches 面：六 PR 零触碰 `crates/jackdaw_scaffold`、
`crates/jackdaw_runtime`、`integrations/physics/`（git diff 实证=空）——
teaches 计数与 guards 语义零波及。

## 四、SP3 图集切分（决策 4-A，提前自 T2 落地）

按主控裁定「SP3 若属六 PR 外的 fork 新建件，本轮一并做」，本轮全部落地并红绿：

1. **fork 一行**（`/Users/zhanglinbo/workspace/bevy-fork-pinned` commit
   **f83d83b41**）：`bevy_image/src/texture_atlas.rs` 的 `TextureAtlasLayout`
   derive 加 `Default`+`reflect(Default)`（2 行 diff）。这是 fork 第 3 个本地
   提交（前两个=钉版提交）；**重制纪律注记**：`scripts/make-bevy-fork.ps1`
   只做初始重制，fork 的 git 历史即补丁记录——若将来重制 fork，须依次
   cherry-pick 三个本地提交。
   - **红绿证据**：New Asset 门 `has_default_value`（ReflectAsset+ReflectDefault
     双在）在测试里放行 sprite_atlas kind 并成功写出文件
     （tests/inspector/sprite_atlas.rs 首 test）——门开实证。
2. **compiled kind**：`src/definition_assets.rs` 加 `SPRITE_ATLAS_KIND =
   "sprite_atlas"`（label "Sprite Atlas"，图标 Grid2x2），compiled_kinds 6→7。
   kind 注册同时点亮 asset_row 候选面（`assets_for_row` 走
   `kinds.by_type_path`，方案预判的「asset_row 臂」无需另写）。
3. **`sprite.atlas.grid` operator**（新模块 `src/sprite_atlas.rs`，刻意不碰
   上游文件族以便将来同步）：params
   `tile_size/columns/padding/offset`（u32 尺寸拼写 "64" 或 "64,64"）+
   `columns/rows`（i64，从 1 起）→ `TextureAtlasLayout::from_grid` 整值写入
   打开的图集卡；帧序=左到右、上到下（单测钉死）；一条 undo 撤整刀。
   注册走 `add_to_extension`（core_extension.rs 紧随 definition_assets）。
4. **顺带修复（T1 挖出的编辑器潜伏缺陷）**：`write_asset_field` 的
   field_path="" 整资产写分支原走 `apply_json_to_reflect` 就地补丁——
   bevy reflect 的 apply 对列表是按位合并，**短列表不清尾部**（探针实证：
   undo 应用 0 帧旧值后 textures 仍 6）。修法=整资产分支改走
   TypedReflectDeserializer 反序列化新值+`ReflectAsset::insert` 整体替换。
   此前该分支无调用方（asset.set 强制非空 field），修复零波及存量路径。

**SP3 测试**：单测 3（尺寸拼写/网格帧序/JSON 双侧可反序列化契约）+
集成 2（`a_sprite_atlas_is_creatable_and_the_grid_cuts_it_into_frames`：
New Asset→开卡→grid 2×3→帧矩形与 undo 全链断言；`the_grid_refuses_to_run_
without_a_tile_size`：缺参 Cancelled 不动值）。全绿。

## 五、本地同步面清单（teaches/guards/book）

- **teaches**：零波及（scaffold 不在六 PR 触碰面，方案预判成立）。
- **guards**：零波及。`record_counts.rs` 的 transform.nudge 白名单不受
  #653 影响的方向键接管只发生在「主选中是 sprite」时（`nudge_sprites`
  返回 false 即回落 3D 原路），guards 的 3D 场景语境不变。
- **book 校对点清单**（T3 落实，本轮不改 book）：
  1. `assets.md`：图片拖放行为已变——2D 世界场景内拖图产 Sprite（#657），
     非再是 UI ImageNode；
  2. `game-ui.md`：Add 菜单新增 2D 组（仅 2D 世界场景打开时出现，
     Sprite/Empty 2D 两行）；画布参考线/标尺章节需注记世界场景支持（#656）；
  3. `remote-control.md`：`input.pointer` 新增 `space=world`（y 向上，
     随面板 pan/zoom，#650）；
  4. 方向键微调在 2D 场景移动 sprite（#653）——若 keyboard-shortcuts 有
     相应描述需补一句；
  5. T3 计划中的新章 `sprites-2d.md` 照方案 §四-T3-4 落。
- **上游测试挂接**：五族 stage 测试+operators 族随 PR 自动挂
  （tests/stage/main.rs、tests/operators/main.rs），零手工挂接需求。

## 六、门禁结果（终树；日志全文捕获于 loop/reports/t21t1_*，exit 仅辅助）

| 门 | 命令 | 结果 | 证据 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | ✅ EXIT=0 | t21t1_gates_fmt.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | ✅ EXIT=0（全文零 error/warning 行） | t21t1_gates_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | ✅ EXIT=0（全文零行） | t21t1_gates_clippy_phys.log |
| libtests | `cargo nextest run --profile ci --workspace --lib` | ✅ **3025/3025**（基线 3002+23：sprite_atlas 单测 3+jackdaw_snap 上游单测族+其余上游随行） | t21t1_gates_libtests.log |
| integration | `cargo xtask integration` | ✅ EXIT=0——主段 **5571/5571**（T19 基线 5458+上游六 PR 随行测试增量）+runtime animation 分包段 1/1；A6 未复发；唯一 flaky=`prefab_lifecycle::prefab_file_change_triggers_reload` 第 3 试过（文件监视时序族，非 sprite 域，nextest 判 PASS） | t21t1_gates_integration.log |
| scaffold_e2e | `cargo nextest run --profile ci -p jackdaw --test scaffold_e2e` | ✅ **1/1**（148.5s 含 check 新产品冷编；模板零改动仍过） | t21t1_gates_scaffold_e2e.log |

> 门禁纪律注记：首轮 clippy_ws 抓到测试文件 2 处 lint（unused mut/未用
> OperatorResult），已修；修复后按「覆盖归档日志」规则重跑覆盖（见补记）。
> 物理双包/libtests 首轮即绿。RUST_BACKTRACE 全程未设。

## 七、上游相邻修复评估（方案 §四-T1-5）

| 提交 | 内容 | 与 sprite 链耦合度 | 裁定 |
|---|---|---|---|
| 2198c1c2 | 元组形态项目组件保存（commands.rs +186/schema_values +95） | 无——Sprite/Anchor/TextureAtlasLayout 全是 struct 组件非元组；commands.rs 本地改动大（+173/−6），cherry-pick 冲突风险高 | **另立不混入**（独立小票，价值面=项目组件 UX） |
| 1655f425 | Visibility::Inherited 不落盘（save +21/bsn apply +60） | 邻接——sprite 实体带 Visibility，落盘为冗余噪音但不破坏往返（bsn 显式值仍正确重开） | **另立不混入**；建议记为独立小任务（收益=全部场景文件瘦身） |

## 八、T2 交接

1. **决策 1 定案：A 路全落地，B 回落未触发，+3 天浮动从估时表除名。**
   T1 估时 2-3 天口径下，试合零冲突使移植收尾实际提前。
2. **T2 剩余面**（方案 §四-T2）：SP9 Anchor 九宫格预设 segmented；SP5 量纲
   教学 book 件；SP4/SP8/SP10 记档件+open-challenges 两行；决策 6 模板裁定
   落地（建议 A=零模板改动）；`TextureAtlasLayout` 的 bsn 游戏侧 walk 装载
   探针转正（M10，方案 §0-事实十三遗留的唯一探针——布局资产经
   TextureAtlasPlugin 已 init_asset+register，预期装载，待 headless 钉死）。
3. **SP7/PIE 2D 探针（决策 7）本轮未跑**（真机腿，dispatch 口径未含；
   方案 T1 第 2 条）——**移交 T2 首步或 T3 fixture 轮**，静态预期仍是
   「快照态不忠实→M14 降级数值轨」。
4. **给 T2 的顺手事实**：`sprite.atlas.grid` 已带整资产写+undo 通路
   （`commit_whole_definition`）；SP9 的 Anchor 面板件与 SP3 的卡内编辑
   （Inspector Vec<URect> 手编）共用此卡面。

## 九、偏差清单

| # | 偏差 | 处置 |
|---|---|---|
| D1 | 重叠面实测 15 文件≠方案预判 12（+3 个 tests/operators 白名单行文件） | 如实记档；方向性结论不变（仍全机械级） |
| D2 | 方案 T1 第 2 条 PIE 2D 探针未跑（dispatch 执行要点未含真机项） | 移交 T2/T3（§八-3），矩阵 M14 判定不受本轮影响 |
| D3 | SP3 由 T2 提前至 T1 落地 | 主控裁定指示（dispatch 执行要点 3） |
| D4 | `write_asset_field` 整资产分支由 apply-补丁改替换（新修编辑器缺陷） | 缺陷此前无调用方（asset.set 强制非空 field），零波及；单测+集成红绿在案 |
| D5 | libtests 计数 3025≠预期「3002+上游增量」的精确拆账 | 增量主体=sprite_atlas 3+jackdaw_snap 7+其余上游随行 13；总账对上（3002+23），逐件拆账如上口径 |
| D6 | clippy_ws 首轮红（本测试文件 2 处 lint：unused mut/未用 OperatorResult） | 已修+按「覆盖归档日志」纪律重跑覆盖，复跑 EXIT=0 全文零行（§六） |

## 十、给 QA 的注意事项

1. **fork 变更在案**：`/Users/zhanglinbo/workspace/bevy-fork-pinned`
   f83d83b41（TextureAtlasLayout Default+ReflectDefault）。QA 复核门禁时若
   在干净环境跑，须确认 fork 处于该提交（`git -C …/bevy-fork-pinned log
   --oneline -1`）。
2. **SP3 真机面留给 L5**：New Asset 清单应出现 "Sprite Atlas"；
   `sprite.atlas.grid` 需先 `asset.new`（或经 New Asset 清单）开卡再跑；
   operator 直调口径：`sprite.atlas.grid tile_size=32,16 columns=2 rows=3`。
3. **undo 语义**：图集切刀=一条 undo（整值替换）；QA 可裁 undo 后
   textures 回空、redo 复原 6 帧。
4. **#650 的 SP6 修**随迁：拾取/吸附坐标在非 100% 缩放下应已正确，但真机
   腿仍按 A10 口径全在 100% 跑（双保险不撤）。
5. **integration 实况**：A6 本轮未复发（预期口径仍挂，若复发按 A6 归因隔离
   复跑）；上游 stage 五族（sprite_picking/sprite_gizmo/sprite_snap/
   world_guides/sprite_drop）为新增，全绿；`prefab_file_change_triggers_reload`
   第 3 试过的 flaky 是文件监视时序族（prefab reload watcher），与 sprite 域
   无关，若 QA 复跑再遇可按既有 flaky 家族归因。
6. **book 零改动**（T3 落）；buglist/台账/roadmap 零触碰（纪律）。
