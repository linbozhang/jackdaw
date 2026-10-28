# A3+A4 报告：standalone fork 注入修复 + Mac integration 基线清理

> 插队小任务 A3+A4（主控指令，T11-T3 QA 回流两项）。分支 `loop/a3a4-mac-baseline`
> （基于 main **7d27cf47**）。产品代码 8 文件 + 测试 1 文件（见 §五清单）。
> 开局自检：工作区干净、分支自 main 新拉。
> 验收口径：Mac `cargo xtask integration` 全绿 + quick 四门全绿；受影响测试断言语义
> 不变或强化（本轮 **零预算放宽、零等待加时、零断言弱化**，§六逐条论证）。

## 〇、结论

- **A3（产品缺陷，T10 血统）已修**：fork patch 注入 gate 在 dev checkout，standalone
  发货测试红→绿，dev-checkout 形态（teaches/fork-patch/scaffold flow）全绿；build.rs
  补 workspace Cargo.toml 监视。
- **A4 Mac 基线 8 红全部处置**：7 项修复（6 产品侧 + 1 测试侧比较形态）+ 1 项即 A3。
  其中 **#7 journal 5ms 预算测试未做任何平台校准**——根因是 macOS autofs 停顿
  （数据见 §三-7），产品侧修复后 Mac 实测 **0.62-1.0ms**（优于 Windows T11-T1 基线
  2.6ms），5ms 预算两平台通吃。
- `cargo xtask integration`（Mac）：**5331 run, 5331 passed, 0 failed**（§四，终跑全绿、
  零 retry；首轮 5 红系 #7 修复初版的误拒，当场根因定位+返工，详见 §三-7 返工记录）；
  flaky 项（maximize_toggle/switching_workspaces）两轮均未复发（§三-8）。
- quick 四门全绿（§四表）。
- **语义缺口上报（不擅自发明）**：shipped binary + physics 模块的「两个 bevy 解析」
  问题维持既有降级路径（§二-4），详见 §七-1。

## 一、A3：standalone 发货 fork patch 注入（产品缺陷）

### 1. 红证（修复前，main 7d27cf47 亲跑）

`cargo test -p jd --test standalone_scaffold the_shipped_binary_scaffolds_without_a_checkout`
→ **EXIT=101 确定性红**（归档 `a3a4_red_standalone_scaffold.log`）：产物 Cargo.toml 两段
`[patch]` 指向 `/Users/zhanglinbo/workspace/bevy-fork-pinned`，断言
「a shipped binary must scaffold registry dependencies, not local paths」（standalone_scaffold.rs:132）
被破——与 QA t11-final-qa.md §一 #1 形态逐字一致。

### 2. 设计意图（以测试为准）

- `the_shipped_binary_scaffolds_without_a_checkout`（crates/jd/tests/standalone_scaffold.rs:91）：
  把 jd 二进制**复制到 checkout 外**（/var/tmp，dev-checkout 检测按「运行中的可执行文件
  所在树」判），并 `env_remove("JACKDAW_DEV_CHECKOUT")` → 断言产物**全 manifest 无
  `path =`**（「A path dependency here would point at a directory that does not exist
  on the user's machine」）——shipped 发货=可移植 manifest，registry/git 依赖。
- `a_physics_game_patches_every_fork_crate_on_both_sources`（jackdaw_scaffold lib 内联
  单测 :3732）：测试二进制**在 checkout 内运行** → 物理工程两段 `[patch]`（crates-io +
  bevy git 源）×5 crate 全在场——dev checkout 形态=注入（T10-T3 引入的语义：git 源子
  crate 不 patch 会漂到远端分支头）。

两测试的设计分界正是「**本构建是否 dev checkout**」，与 QA 建议的 gate 一致。

### 3. 根因与修法

根因：`module_patch_lines`（scaffold 新工程）与 `add_module_crates`（模块变更/import）
只 gate 在编译期 `BEVY_FORK`（build.rs `fork_pin` 从构建机 workspace Cargo.toml 烘入的
绝对路径），不看运行形态。构建机带 fork 时烘入的路径对任何别的机器都是死路径。

修法（`crates/jackdaw_scaffold/src/lib.rs`）：

- 两处注入均加 gate `crate::dev_checkout::jackdaw_dev_checkout().is_some()`（既有 helper：
  可执行文件在源码树内，或 `JACKDAW_DEV_CHECKOUT` 显式覆盖——与 standalone 测试的
  复制出树手法互为印证）；
- 非 dev checkout 走**既有降级路径**（原 `BEVY_FORK=None` 分支的 note），措辞按事实
  校准：「this build cannot share its bevy fork patch with the game; …remake the fork
  with this jackdaw's scripts/make-bevy-fork.ps1 and add the [patch] sections it writes」；
- `crates/jackdaw_project_build/build.rs` `emit_bevy_source` 补
  `cargo:rerun-if-changed=<workspace>/Cargo.toml`——`fork_pin` 从该 manifest 读 fork 路径，
  原先只有 embed-recipe 分支监视它，非 embed 构建里 fork 重指/移动后 `JACKDAW_BEVY_FORK`
  停留旧值直到清洁重建（QA §八-1 诊断的第二半）。

### 4. 验证

- 红→绿：standalone 三件套全绿（`a3a4_scaffold_jd_green.log`，133/133，
  `the_shipped_binary_scaffolds_without_a_checkout` PASS 34.7s、
  `a_physics_game_patches_every_fork_crate_on_both_sources` PASS 0.06s——dev-checkout
  形态不受 gate 影响）；
- 全量 integration 内 scaffold_e2e/teaches/stage launcher/physics flow 族全绿（§四）。

## 二至三、A4：Mac integration 8 红逐项

| # | 测试 | 失败形态（QA 日志原文） | 根因（本轮查实） | 修法（层） | 红绿证据 |
|---|---|---|---|---|---|
| 1 | `jd::standalone_scaffold::the_shipped_binary_scaffolds_without_a_checkout` | 产物含 fork `[patch] path=` | =A3（§一） | 产品（scaffold gate） | 红 `a3a4_red_standalone_scaffold.log` → 绿 `a3a4_scaffold_jd_green.log` |
| 2 | `guards reference_rewrite::renaming_an_open_clean_scene_retargets_its_tab` | tab 路径停在旧名 `/private/var/…/hedgerow.bsn` | **产品 bug**：tab 持 canonical 拼写（`resolve_scene_path` 打开时 canonicalize → `/private/var/…`），rename 后 `retarget_tabs` 对已被移走的 old 路径 `dunce::canonicalize` **失败**（文件已不在）→ 回落原始拼写 `/var/…` ≠ tab 的 `/private/var/…` → `stands_on` 不匹配 → **retarget 整体未发生**（Y8「旧文件复活」缺陷在 macOS 复现的真实形态，非仅断言形式差） | 产品（`src/reference_rewrite.rs` 新 `canonical_of_moved`：canonicalize 失败时取**最深仍存在祖先**的 canonical 形式拼回尾部，双侧同形比较；`retarget_tabs`/`stands_on` 两处换用） | guards 26/26（`a3a4_guards_green.log`）+ integration 全绿 |
| 3 | `guards reference_rewrite::renaming_a_folder_retargets_a_tab_under_it_onto_the_same_tail` | tab 路径停在旧文件夹名 `…/assets/props/sub/scene.bsn` | 同 #2（folder 变体，同一 `stands_on` 匹配失败） | 同 #2 | 同上 |
| 4 | `guards reference_rewrite::a_dirty_tab_journals_under_the_renamed_path` | journal 记旧名 `…/hedgerow.bsn` | #2 的下游（journal 重写挂在 tab retarget 上，retarget 未发生→journal 记旧路径） | 同 #2（上游修好即愈） | 同上 |
| 5 | `guards reference_audit::a_loaded_scene_leaves_one_summary_warning` | broken-ref 告警 0≠1 | **产品 bug**：`warn_on_load(world, canonical_tab_path, …)` 收 `/private/var/…` 形态，`indexed_path` 只按原始 `/var/…` 形态的 assets 目录 `strip_prefix` → 失败 → 绝对路径直接返回 None → **Mac 用户加载带断链引用的场景得不到任何警告**（N5 静默回归） | 产品（`src/asset_index.rs::indexed_path` 补第二跳：两侧 canonicalize 后再 strip，任一命中即相对化；原语义分支全保留） | 同上（断言仍=恰 1 行+计数行） |
| 6 | `guards session_journal::a_dirty_tab_journals_the_save_emitters_own_text` | `entry_path.starts_with(tmp.path())` 假（`/private/var` vs `/var`） | **测试侧比较形态**：产品按设计 journal 记 tab 的 canonical 路径（正确），测试拿原始 TMPDIR 拼写比前缀 | 测试（两侧 `std::fs::canonicalize` 后比较——产品行为零改动；本任务唯一测试侧修复） | 同上 |
| 7 | `guards session_journal::the_journal_write_costs_no_more_than_five_milliseconds` | 301-568ms ≫ 5ms | **产品 bug（macOS autofs 停顿）**，深挖见下节——**非 APFS/fsync、非平台预算问题** | 产品（`src/scene_io/save.rs` emit 的 prefab 查找拒绝项目外绝对路径） | Mac 实测 0.62-1.0ms，**预算不动** |
| 8 | `panels reconcile::a_maximized_leaf_draining_ends_the_maximize`（+负载 flaky：`maximize_toggle`、`switching_workspaces` 同签名） | `observe<PointerOver,…highlight_on_hover>: Entity despawned (4199v1 → generation 2)` | **产品侧生命周期缺护航**：project_window 对树行/瓦片按**既有实体**排队 `.observe(...)`（延迟命令），同帧 panels 重建可在队列 flush 前把树整体 despawn——正是该文件 tiles 处已记档并护航过的竞态（「a panel rebuild can despawn that grid before these flush」→ `attach_or_despawn`/`set_marker_if_alive` 家族）；observe 命令本身无护航，bevy 错误处理器把死实体错误升为 panic。Windows 时序不同未踩中，Mac 确定性踩中 | 产品（`crates/jackdaw_feathers/src/utils.rs` 新 `observe_if_alive`——同家族语义「实体已死则随实体丢弃观察者」；project_window 全部 11 处对既有实体的 observe 换用：行 content×3 + 瓦片×8（QA 复核更正：初稿计 8 处系漏数瓦片 3 处）；spawn-builder 链上的 `.observe`（fresh 实体同队列无窗口）不动） | panels+controls 55/55（`a3a4_panels_controls_green.log`）；integration 满载全绿，flaky 项未复发 |
| 9 | `controls ui_probe_click::a_ui_input_types_and_commits_in_one_gesture` | 多出字符 `"0entity: 42"`（默认值 "0" 未被替换） | **注入 helper 平台缺口**：fork 的文本输入把 select-all 绑在**平台 command 键**（`command = if mac { SUPER } else { CTRL }`，bevy_ui_widgets/text_input.rs:160），合成 `select_all_gesture` 固定发 Ctrl+A——Windows 命中、macOS 是无操作 → 全选未发生 → 打字追加在默认值后 | 测试工具层（`src/test_input.rs::select_all_gesture` 按平台发 SuperLeft+A / ControlLeft+A——Mac 上的人按的就是 Cmd+A；断言不动） | 同上 |

### #7 深挖：为什么 Mac 上 9KB 双实体场景的 emit 要 80-570ms

1. **隔离探针**（单跑，150 轮循环）：terrain fixture 每 emit **77-101ms 确定性慢**
   （400 实体生成场景同路径仅 0.55ms）→ 非负载、非 fsync（`a3a4_probe_emit_distribution.log`）。
2. **采样画像**（macOS `sample`，两次）：~99% 样本在 `sparsify_inherited_descendants →
   PrefabAstCache::get → canonical_prefab_path → resolve_existing → realpath →
   __getattrlist`（`a3a4_sample_profile_before_fix*.txt`）。
3. **调用计数**（临时原子计数器，已撤）：每 emit 恰 **2 次** canonicalize，各 ~40-80ms——
   单次 realpath 不可能这么慢（`a3a4_probe_canon_callcount.log`）。
4. **点名慢路径**（计时打印，已撤）：`SLOW CANON (fallback) 98ms on
   /home/joe/Workspace/jackdaw/assets/prefabs/box.jsn`——fixture `real_scene.bsn:278`
   的 Brush 实体带遗留 `IsA { source: "/home/joe/…" }`（**他机的绝对路径**），
   `a3a4_probe_slow_canon_home_joe.log`（169 次命中）。
5. **OS 级实锤**（python 微基准，本机）：`realpath("/home/joe/…")` = **70.5ms/次**、
   `/home/nobody-here/…` = 22.3ms、`/tmp/…` ≈ 0——macOS `/home` 是 **autofs auto_home
   触发挂载**（`mount` 实证：`map auto_home on /System/Volumes/Data/home`），每次 stat
   都找 automountd/目录服务。Windows 无此概念（canonicalize 秒败），同码同 fixture
   T11-T1 Windows 实测 emit 2.64ms / write 2.29ms。
6. **修法层**：emit 的 `sparsify` 对 `IsA` source 查 prefab cache；cache 只装本项目文件
   （watcher/tabs/spawn_instance 全是项目路径），项目外的绝对 source **永远 miss**——
   却为这个 miss 付出整条文件系统行走。`author`（save.rs）的 `get_prefab` 闭包对
   「绝对 && 不在项目根下」直接 None（load 路径本就把这种拼写 warn 成 stray
   「names a place on this machine」）；miss 语义与修前一致，只省掉停顿。
7. **修后实测**：terrain fixture emit **843µs** / write **915µs**；400 实体 1.0ms/0.62ms
   ——5ms 预算在 Mac 上从超 60-113 倍变为余量 5 倍以上，**无需任何平台校准**
   （比 Windows T11-T1 基线 2.6ms 还快）。
8. **真实用户面**：任何 Mac 用户打开带 `/home/...` 遗留引用的旧场景，每次保存、每次
   journal 防抖写、每次 undo 快照都要付这笔停顿——产品侧修复正当性成立。
9. **返工一轮（全量门拦下，红绿在案）**：初版 gate 只按 `ProjectRoot.root` 原始拼写
   （`/var/…`）判「项目内」，而 emit 时文档里的 `IsA` source 已是 cache 键的 canonical
   形态（`/private/var/…`）——项目内 prefab 被误拒，sparsify 失效，首跑 integration
   **新增 5 红**：`guards record_counts::dragging_an_inherited_child_out_is_one_clean_entry`、
   `stage material_overrides::an_instance_keeps_following_the_prefab_entries_it_did_not_override`
   （断言 `left index 0 right index 1`：实例不再跟随 prefab 编辑）、
   `stage remote_placement::an_instance_that_inherited_nothing_is_selected_by_the_label_its_row_shows`、
   `stage remote_placement::the_scene_tree_names_an_instance_that_inherited_nothing_after_its_file`、
   `stage remote_placement::an_instance_whose_prefab_is_missing_keeps_its_row_and_its_reference`
   （5331 跑 5326 过；首跑日志被复跑覆盖，失败清单与形态以此处引文为准，逐条复跑
   验证）。修法：gate 同时接受项目根的**两种拼写**（原始 + `dunce::canonicalize` 后），
   项目内 prefab 两种形态均放行、`/home/joe/…` 两种形态下仍拒——5 红复跑 5/5 绿
   （含 journal 预算回归），再全量 integration 定案（§四）。

## 四、门禁归档（日志全文复核为准，`loop/reports/a3a4_*`）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **CLEAN**（首跑 1 处 diff=本任务测试编辑→`cargo fmt --all` 重排→复跑零 diff 覆盖归档） | `a3a4_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets -- -D warnings` | **CLEAN**（EXIT=0，零 error/warning） | `a3a4_clippy_ws.log` |
| Lint 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **CLEAN**（EXIT=0） | `a3a4_clippy_physics.log` |
| 单测 | `cargo test --workspace --lib` | **绿**（58 套件全 ok，EXIT=0） | `a3a4_libtests.log` |
| fast | `cargo xtask fast` | **2961/2961 passed, 0 skipped**（EXIT=0，与 T11-T3 Mac 基线同总数） | `a3a4_fast.log` |
| **integration（主门）** | `cargo xtask integration` | **5331/5331 passed (1 slow), 0 failed, 0 skipped**（EXIT=0，终跑全绿、零 retry 消耗；对照 T11-T3 基线 5331 跑 5323 过+8 红——净清 8 红。首轮曾因 #7 初版 gate 误拒项目内 canonical 形态 prefab 新增 5 红（§三-7 返工记录），修后终跑定案） | `a3a4_integration.log` |
| 过程证据 | A3 红 / 探针×3 / 画像×2 / guards·panels·controls·scaffold 定向绿 | 见 §一/§三 引用 | `a3a4_red_standalone_scaffold.log`、`a3a4_probe_*.log`、`a3a4_sample_*.txt`、`a3a4_*_green.log` |

（门禁全程未设 RUST_BACKTRACE——Mac debug wgpu SIGSEGV 禁令遵守；跑后清理：无
jackdaw/jd 残留进程；红证轮在断言处 panic 未走到自清的 5 个 scratch 目录
`/var/tmp/jackdaw_standalone_new_*` 已手工清除，共享二进制目录
`/var/tmp/jackdaw_standalone_jd` 为测试设计保留态。）

## 五、改动清单

产品（8 文件）：

| 文件 | 改动 |
|---|---|
| `crates/jackdaw_scaffold/src/lib.rs` | A3：`module_patch_lines` + `add_module_crates` fork patch 注入 gate 在 `jackdaw_dev_checkout()`；降级 note 措辞校准 |
| `crates/jackdaw_project_build/build.rs` | A3：`emit_bevy_source` 监视 workspace Cargo.toml（BEVY_FORK 停旧值问题） |
| `src/reference_rewrite.rs` | A4 #2-4：`canonical_of_moved` helper，`retarget_tabs`/`stands_on` 双侧 canonical 比较 |
| `src/asset_index.rs` | A4 #5：`indexed_path` canonical strip 第二跳 |
| `src/scene_io/save.rs` | A4 #7：emit 的 prefab 查找拒绝项目外绝对路径（按项目根原始+canonical 两种拼写判内；autofs 停顿） |
| `src/test_input.rs` | A4 #9：`select_all_gesture` 平台 command 键（Mac=Super，余=Control） |
| `src/project_window.rs` | A4 #8：11 处既有实体 observe 换 `observe_if_alive`（QA 复核计数） |
| `crates/jackdaw_feathers/src/utils.rs` | A4 #8：新 `observe_if_alive` helper（attach_or_despawn 同家族） |

测试（1 文件）：

| 文件 | 改动 |
|---|---|
| `tests/guards/session_journal.rs` | A4 #6：journal 路径断言双侧 canonicalize（仅比较形态；诊断用临时探针全部已撤，终版无 instrumentation） |

## 六、断言/预算纪律逐条

- **#7 5ms 预算：未放宽、未分平台**。修复后 Mac P95 级实测 0.62-1.0ms（数据 §三-7），
  预算 5ms 原样通过——「平台校准预算」分支未启用（根因是产品停顿而非 fsync 语义差）。
- **#9：断言未动**（仍 `typed == "entity: 42"`），修在注入 helper 的平台修饰键。
- **#5：断言语义不变且仍精确**（恰 1 行 + 计数行），修在审计器上游的路径相对化。
- **#6：唯一测试侧改动**=比较形态双侧 canonicalize；产品行为（journal 记 canonical
  路径）零改动。
- **#2-4/#8：纯产品修复**，测试断言一字未动。
- 无任何等待加时、无 retry 上限调整、无 skip/allowlist。

## 七、上报与遗留 ⚪

1. **语义缺口（A3 附带，上报主控裁定，未擅自发明）**：shipped binary + physics 模块
   的 resolve 面——注入 gate 后，非 dev checkout 的新工程拿到的 physics manifest 无
   fork patch，avian3d（registry bevy）与 bevy（git main）是两个 bevy，首次构建可能
   resolve 失败。这是**既有设计降级**（原 `BEVY_FORK=None` 构建一直如此，note 指引
   用户自建 fork），fork 分发模型本身是「构建机本地目录」（buglist T10 偏差②机约）。
   若产品要走「shipped 也开箱即用物理」，需要可分发的 fork 形态（git 仓库/registry），
   超出本任务范围。本轮选择：可移植 manifest（standalone 测试钉死的承诺）优先。
2. ⚪ `canonical_prefab_path` 的文件系统行走仍是通用性能地雷（W15 族）：本任务只拆了
   emit 热路径上最恶性的项目外场景；cache 层的负查找 memo/键归一属后续优化面。
3. ⚪ macOS autofs 停顿不限于 `/home/joe`：任何指向 autofs 触发挂载点（/home、/net）
   下的死路径 stat 都慢（20-70ms）。#7 修复按「项目外绝对路径不探测」规避了整个族。
4. ⚪ doctests jackdaw_bind dyld 环境性失败（T09 起第 4+ 次家族）非本任务 8 红之一，
   未动；本机本轮 `--test` 域不受影响。
5. ⚪ QA 复验建议重点：#2 的真机语义（rename 打开中的场景→保存落新路径旧文件不复活）
   与 #7 的用户面（带遗留 `/home/...` 引用的旧工程在 Mac 上保存/undo 不再百毫秒级卡顿）。

## 八、buglist 勾选建议（留 QA）

- **A3**：修复+红绿证据+dev-checkout 族回归齐备（§一），建议 QA 复核后勾选。
- **A4**：8 红全部处置+主门全绿（§四），建议 QA 复核后勾选；台账 Mac 基线状态由
  「带已知环境红」升为「全绿基线」。
