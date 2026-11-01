# T21-T1 QA 报告：六 PR cherry-pick 试合探针轮+SP3 图集 —— 裁决 PASS（放行 T21-T2）

> 验收对象=`loop/reports/t21-t1-report.md`（分支 `loop/t21-sprite`，终树 56eefb50：
> 6 cherry-pick 5f55c9ee/6f6b9f97/4a4d7778/3a30d5ef/211d6061/00df93ba + SP3 收尾）。
> 上游对照基线=本地标签 `nightly-2026-10-27`。QA 亲跑日期 2026-11-01。
> 归档=`loop/reports/t21t1_qa_*`（七门日志+master 时间线）。RUST_BACKTRACE 全程未设。

## 一、结论

**PASS。** 决策 1 定案门（A 路全量落地）成立，「零文本冲突」声明经 patch-id 逐对全等
证实为最强形态（见 §二-3），SP3 全链在案且红绿亲跑复现，七门亲跑全绿（日志全文复核）。
4 条记档级发现（§六 F1-F4），无阻断项，不动摇放行。

## 二、cherry-pick 完整性核（本任务核心，全过）

### 1. 六 PR+SP3 逐提交核

| 本地 | 上游 | patch-id（--stable） | 作者/信息 | upstream shortstat |
|---|---|---|---|---|
| 5f55c9ee | 91fa6afe #650 | **EQUAL** | 保留 | 8 files, +1312/−9 |
| 6f6b9f97 | 8b043358 #653 | **EQUAL** | 保留 | 15 files, +1651/−38 |
| 4a4d7778 | e7cb8638 #654 | **EQUAL** | 保留 | 4 files, +623/−38 |
| 3a30d5ef | 5e865fad #655 | **EQUAL** | 保留 | 12 files, +1270/−103 |
| 211d6061 | edf167e5 #656 | **EQUAL** | 保留 | 12 files, +1028/−186 |
| 00df93ba | 10a53456 #657 | **EQUAL** | 保留 | 16 files, +1189/−14 |
| 56eefb50 | —（SP3 本地件） | — | linbo.zhang | 13 files, +9588/−11（含报告与归档日志） |

- 六 PR 插入合计 7,073 行 ✓（报告 §一）；上游测试文件族 546+1068+387+564+302+429≈3,300 行 ✓。
- 链序/基点：5f55c9ee 父=5a11deff（main），六连后 SP3 在顶 ✓。

### 2. 抽 2 PR 全 diff 对读（#653/#657）

上游切口与合并后落点逐处对读，**全部与报告 §三/§二 行号吻合**：

- **#653**：scene_io 三钩子（load.rs :830-831 两个 `forget_drag_resource` 插在
  UiManipulation 之后 topo 之前；save.rs :698 sprite 渲染件跳过 + :992-996 normalize
  的 patch 清除；mod.rs `sprite_render_component_paths()` 落 SKIP_COMPONENT_PATHS 邻位）
  + transform_ops.rs :283 `nudge_sprites` 先行/3D 网格步进回落分支序 + gizmos.rs
  TRANSFORM_GIZMO_LAYER=3 与 `run_if(three_d_world_is_current)` + viewport.rs :134/:353。
- **#657**：boot_ops.rs :283 白名单行、creation_taxonomy.rs :52/:247 `two_d()`+`collect()`
  钩子、entity_ops.rs :864-867/:873/:2367 `scene_2d_parent`/`spawn_template_under`/
  `SpriteAddOp` 注册、tests/operators 三处白名单行（:576/:26/:337）、ui_asset_drop 路由注释。
- 唯一引注漂移：mod.rs 实际 :102-109（报告写 :91-100）——nit 级（F2）。

### 3. 「零文本冲突」真实性

**成立，且为最强形态。** 六对 patch-id 全等意味着每个本地提交的净 diff 与上游逐字节同
（patch-id 只哈希 +/- 内容行，忽略行号与上下文）——若曾发生冲突人工消解并改动内容，
patch-id 必然不等。即：不仅「git 未报冲突」，合并结果里也没有任何一行是解冲突时引入的。
另以 `git diff --name-only` 自算重叠集（六 PR 文件 ∩ 本地 5c3ba8ea..5a11deff 改动）=
**恰 15 文件**，与 D1 口径一致（方案预判 12 + tests/operators 3 个白名单行文件）。

### 4. 重叠文件抽 6 个语义落点复核（两侧改动物理不相交声明）

| 文件 | 本地改动 | 上游切口 | 复核 |
|---|---|---|---|
| src/lib.rs | +129/−19（T 系模块/插件注册） | 六 PR 各 1-2 行 | 5 个 sprite 模块声明（:164-168 含 SP3 sprite_atlas）+插件注册（:455-456,:496）落位，两侧在字母序/注册序不同槽位，机械级 ✓ |
| src/entity_ops.rs | +190/−23 | #657 +20 | 上游切口（spawn_template 族+注册行）与本地改动不同函数，落点 :864-867/:873/:936/:2367 ✓ |
| src/test_input.rs | +392/−9 | #650 +22 | `space @ ("canvas" \| "world")` 臂+world 映射+三值错误文案在 :643-668 逐字在位 ✓ |
| src/scene_io/load.rs | +41/−6 | #653 +2 | 钩子落 `forget_dragged_entities` 函数体内 ✓ |
| src/scene_io/save.rs | +137/−26 | #653 +10 | 两钩子各落本地函数体（collect_bsn_inline_assets/normalize_runtime_derived_values）✓ |
| src/transform_ops.rs | +15 | #653 +6 | sprite 先行、3D 回落，与本地 SnapSettings 步进共存 ✓ |

另抽查 gizmos.rs/viewport.rs/commands.rs（CanvasGuides 文档行 :2466）落位均正确。
物理双包零触碰实证：六 PR 文件集与 `crates/jackdaw_scaffold|jackdaw_runtime|
integrations/physics` 交集为空 ✓（teaches/guards 零波及的预判成立）。

### 5. SP6 随行修在位

`world_to_target_pixel`（viewport_2d.rs :188）与 `target_pixels_per_stage_pixel`（:245）
在位，`world_mapping_tests` 3 测随 libtests 绿（含 y 向上/逆映射/缩放三腿）✓。

## 三、上游测试随行核

- **libtests 拆账（D5 修正）**：基线 t20t2 日志（cargo test 格式）求和=3002，本轮
  nextest=3025，**+23 = jackdaw crate +19 + jackdaw_snap crate +4**：
  - jackdaw +19：sprite_atlas::tests 3（SP3）+ sprite_snap::tests 10（#655）+
    sprite_stage::tests 3（#650）+ viewport_2d::world_mapping_tests 3（#650/SP6）；
  - jackdaw_snap +4：#655 随行 4 测（landing/resize/axis/degenerate）。
  逐名对账（T20 测试名集 vs T21 测试名集 comm 双向），无删失、无改名。T20 日志里另
  11 个 crate（physics/api/dylib 等）在基线即 0 测（cargo test 空转），无遗漏。
  **D5 的细账（atlas 3+snap 7+随行 13）数字不准，总账 3002+23 对**（F4）。
- **integration 增量**：主段 5571（T19 基线 5458 → +113，主体=stage 五族 73+
  operators sprite_ops 13+inspector sprite_atlas 2+既有文件内扩展）。
- **抽 2 个上游测试文件亲跑（非空转实证）**：
  - `--test stage` sprite_gizmo 族 31/31（16.2s，逐测真实启动编辑器 App，1.4s/测）；
  - `--test operators` sprite_ops 13/13（6.7s）。
  加上 integration 全量轮内 PASS：stage 五族 73/73、sprite_atlas 单测 3+集成 2。
  **stage 测试族在 Mac 全绿，方案 §六「环境差归因」预案未触发。**

## 四、SP3 图集复核（fork+编辑器+红绿）

1. **fork 一行**：`/Users/zhanglinbo/workspace/bevy-fork-pinned` HEAD=f83d83b41 ✓，
   diff 亲读=恰 2 行（derive 加 `Default`、`reflect(Debug, Default, PartialEq, Clone)`），
   提交信息含动机（New Asset 门 ReflectAsset+ReflectDefault 双在）+T21 出处+pinned rev
   c9c397ba1。fork 本地提交恰 3 个（20c04162a 钉版/9cb82e77e 记 rev/f83d83b41）。
   **F1：报告 §四-1 的「重制纪律注记」（重制须依次 cherry-pick 3 本地提交）只写在
   loop 报告里，fork 提交信息与 fork 侧任何文件均无此注记**——记档级（重制是罕见
   操作、报告在案、fork 历史自带 "jackdaw loop" 作者可辨识），建议主控裁定补录位置
   （fork 侧再提交纯注记会多一个本地提交；更轻的是记入台账或 T21 计划行）。
2. **compiled kind**：`SPRITE_ATLAS_KIND="sprite_atlas"`（"Sprite Atlas"，Icon::Grid2x2，
   `TextureAtlasLayout` type_path）注册进 `compiled_kinds()`（6→7）✓；asset_row 候选面
   经 `kinds.by_type_path`（asset_row.rs :603/:817）白得 ✓（「无需另写 asset_row 臂」成立）。
3. **`sprite.atlas.grid` operator**：`src/sprite_atlas.rs`（刻意独立于上游文件族），
   tile_size/columns/rows 必填+缺参 warn_cancelled，`from_grid` 整值写入走
   `commit_whole_definition`→`SetDefinitionField{field_path:""}`→undo 一条 ✓；
   core_extension.rs 注册 ✓。
4. **write_asset_field 整资产写修复（D4）**：field_path="" 分支由 `apply_json_to_reflect`
   （就位补丁，列表按位合并→短列表不清尾部）改为 TypedReflectDeserializer 反序列化+
   `ReflectAsset::insert` 整体替换，修复与「undo 应用 0 帧旧值 textures 仍 6」探针缺陷
   对得上；undo 走 `SetDefinitionField::apply(old_json)` 同路径，语义一致 ✓。
   **调用方核（F3）**：全仓调用方恰 2 处（definition_assets.rs :487 write_field、
   :1018 commit_handle_field←asset_row.rs :556 传真实行 field_path）。报告括注
   「asset.set 强制非空 field」**不严格**——asset.set 只要求 field 参数存在，不拒绝空串，
   degenerate 调用 `asset.set field=""` 理论可达该分支；但无任何产品流程/行对象以空
   field_path 到达，「修复零波及存量路径」的实质成立。D4 同意吸收，措辞修正记档。
5. **红绿亲跑**：单测 3（尺寸拼写/网格帧序/undo_json 契约）+集成 2
   （`a_sprite_atlas_is_creatable_and_the_grid_cuts_it_into_frames` 全链、
   `the_grid_refuses_to_run_without_a_tile_size` 缺参 Cancelled）本轮亲跑全 PASS ✓；
   New Asset 门放行=集成首测即「门开实证」✓。

## 五、上游相邻修复「另立不混入」裁定核——两件均成立

| 提交 | 实读内容 | 裁定核 |
|---|---|---|
| 2198c1c2（元组形态保存） | commands.rs +186（AddProjectComponent/SetBsnField/authored_project_field_json/set_project_field 深改）+schema_values +95+bsn parse +25 | 本地 commands.rs 自 merge-base 改 +180/−6，切口函数与本地改动深度重叠——「冲突风险高、另立」理由实证成立；sprite 链零依赖（Sprite/Anchor/TextureAtlasLayout 均 struct 组件）✓ |
| 1655f425（Visibility::Inherited 不落盘） | save.rs +21 切在 `normalize_runtime_derived_values`——**恰是 #653 钩入的同一函数** | 现在 cherry-pick 必与 sprite 链纠缠；不混入正确。行为现状=显式值落盘冗余但往返无损（报告判定准确）。同意见独立小票（全部场景文件瘦身的普适收益）✓ |

## 六、QA 发现清单（记档级，无阻断）

| # | 发现 | 建议 |
|---|---|---|
| F1 | fork 重制纪律注记只入 loop 报告，fork 侧（提交信息/文件）无 | 主控裁补录位置（台账/T21 计划行/fork 注记提交） |
| F2 | 报告 §三 mod.rs 落点引注 :91-100，实际 :102-109 | nit；下轮报告行号引注以 grep 实测为准 |
| F3 | D4 括注「asset.set 强制非空 field」不严格（operator 不拒空串，degenerate 可达；产品流程确无调用方） | D4 维持「零波及」结论，措辞按本报告 §四-4 修正 |
| F4 | D5 细账 3+7+13 不准；实测 +23=jackdaw+19（atlas 3/snap 10/stage 3/viewport_2d 3）+jackdaw_snap+4 | 台账引用拆账时以本报告 §三数字为准 |

## 七、偏差 6 条裁定建议（QA 意见）

| # | 偏差 | QA 裁定建议 |
|---|---|---|
| D1 | 重叠 15≠预判 12 | **同意记档**。15=自算实证（§二-3），方向性结论（全机械级）不变 |
| D2 | PIE 2D 探针（方案 T1 第 2 条）未跑 | **同意移交**，但须定死归属：**移交 T2 首步真机小轮**（与 SP3 真机面 L5 同轮，省 fixture 成本）；不得滑到 T3 之后。矩阵 M14 判定不受影响；静态预期（快照态不忠实→降级数值轨）不变 |
| D3 | SP3 提前至 T1 | **同意**（主控 dispatch 明示）；落地质量经 §四 全项复核支持 |
| D4 | write_asset_field 整资产分支改替换 | **同意吸收**，附 F3 措辞修正；修复与 undo/redo 语义闭环（单测+集成亲跑绿） |
| D5 | libtests 拆账 | **总账认可、细账修正**（F4）；不阻断 |
| D6 | clippy 首轮红 2 处 lint | **同意结案**。按门禁证据标准「修完重跑覆盖归档日志」执行（归档=复跑后日志，EXIT=0 全文零行）；首轮红细节因覆盖不可回溯属契约预期行为，非违规 |

## 八、门禁表（QA 亲跑终树 56eefb50；日志全文复核为准，exit 辅助）

| 门 | 命令 | 结果 | 证据 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | ✅ EXIT=0 | t21t1_qa_fmt.log |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | ✅ EXIT=0，全文零 error/warning 行 | t21t1_qa_clippy_ws.log |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | ✅ EXIT=0，全文零行 | t21t1_qa_clippy_phys.log |
| libtests | `cargo nextest run --profile ci --workspace --lib` | ✅ **3025/3025**（=3002+23，拆账 §三） | t21t1_qa_libtests.log |
| fast | `cargo xtask fast` | ✅ EXIT=0，lib 段 **3025/3025**（dylib features），fmt/clippy 段零行 | t21t1_qa_fast.log |
| integration | `cargo xtask integration` | ✅ EXIT=0，主段 **5571/5571**+animation 分包 1/1；唯一 flaky=`prefab_file_change_triggers_reload` TRY3 过（文件监视时序族，两轮同形，非 sprite 域）；**A6 未复发**（全文零 dyld 行） | t21t1_qa_integration.log |
| scaffold_e2e | `cargo nextest run --profile ci -p jackdaw --test scaffold_e2e` | ✅ **1/1**（150.9s） | t21t1_qa_scaffold_e2e.log |
| 定向亲跑 | `--test stage` sprite_gizmo 族 / `--test operators` sprite_ops | ✅ 31/31+13/13（非空转：逐测 1.4s 真实 App） | 本报告 §三 |

程序归档日志（t21t1_gates_*，终轮）与 QA 复跑逐门同形，报告 §六 门禁表与证据一致。
warn 扫描：clippy_ws/integration 归档零意外 error/warning/dyld 行。

## 九、放行 T21-T2 建议

1. **放行**：T1 裁决 PASS，分支 `loop/t21-sprite`（56eefb50）可交主控 `--no-ff` 合入
   main 或按惯例由 T2 续用（主控定）。
2. **SP7 PIE 2D 探针移交口径（D2）**：移交 **T2 首步真机小轮**（半天内：2D 场景
   `pie.play_current` 文件路径态+快照态各一拍），与 SP3 真机验证（New Asset 出现
   "Sprite Atlas"、`sprite.atlas.grid tile_size=32,16 columns=2 rows=3`、undo 一条撤整刀）
   合并跑；结论按决策 7 预案分流（忠实→M14 保 PX；不忠实→数值轨+SP7 记档）。
3. **T2 剩余记档件清单**：SP9 Anchor 九宫格 segmented（决策 3-B）；SP5 book 量纲教学
   （决策 2-A，零代码）；SP4/SP8/SP10 记档+open-challenges 两行（排序面/3D 组隐藏）；
   决策 6 模板裁定落地（建议 A=零模板改动）；M10 `TextureAtlasLayout` bsn 游戏侧 walk
   装载探针转正；**F1 fork 重制注记补录**（本轮新增，主控裁位置）。
4. **给 T2 的顺手事实**（对报告 §八-4 的确认）：`sprite.atlas.grid` 的
   `commit_whole_definition` 整资产写+一条 undo 通路已验证；SP9 的 Anchor 面板件与
   SP3 卡内编辑共用卡面；book 校对点五条（报告 §五）在案，T3 落实。
