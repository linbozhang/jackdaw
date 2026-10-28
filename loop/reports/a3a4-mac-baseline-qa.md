# A3+A4 终验 QA 报告：standalone fork 注入修复 + Mac integration 基线清理（只验不修）

> 验收对象：分支 `loop/a3a4-mac-baseline` @ **b15ac34c**（产品提交 f7f57ab7：产品 8 文件 +
> 测试 1 文件；b15ac34c 仅证据归档）。开局自检：分支/提交态与任务指令一致，工作区干净，
> 基点=main 7d27cf47。程序报告：`loop/reports/a3a4-mac-baseline-report.md`。
> QA 证据：六门**全部亲跑**（2026-10-28 16:59-17:11，串行，**全程未设 RUST_BACKTRACE**，
> 归档 `a3a4_qa_*`）；代码逐 hunk 亲读；fork 源码/bevy_ui_widgets 亲读；autofs 微基准独立复现；
> t11 基线红账逐条对账。

## 〇、结论

**VERDICT: PASS**（A3+A4 均达标）。六门亲跑全绿，主门 integration **5331/5331 passed,
0 failed**（QA 独立复跑）；8 红全部处置且修复层逐项核实成立；断言纪律零违例（唯一测试侧
改动=#6 比较形态，#9 修在注入 helper、断言未动）；#7 的 5ms 预算两平台未动。QA 新发现
**🟡 一项报告计数不准**（#8 实际 11 处换用，非 8 处——修复比报告宣称的更全，无功能缺口）
与 ⚪ 若干（含 QA 复跑新观察 1 例无关 flaky）。buglist **A3/A4 均建议可勾选**（§六）。

## 一、门禁亲跑（日志全文复核，归档 `loop/reports/a3a4_qa_*`）

| 门 | 命令 | 结果（QA 亲跑） | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | **CLEAN**（EXIT=0，日志零字节） | `a3a4_qa_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | **CLEAN**（EXIT=0，全文零 error/warning/FAILED 匹配，Finished 22.56s） | `a3a4_qa_clippy_ws.log` |
| Lint 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- -D warnings` | **CLEAN**（EXIT=0，零匹配，Finished 11.90s） | `a3a4_qa_clippy_phy.log` |
| 单测 | `cargo test --workspace --lib` | **绿**（EXIT=0，58 套件全 ok；全文唯一 ERROR 匹配=pie prebuild 负路径夹具在通过测试内的日志行，T11 既有口径） | `a3a4_qa_libtests.log` |
| fast | `cargo xtask fast` | **2961/2961 passed, 0 skipped**（EXIT=0，Summary 在档） | `a3a4_qa_fast.log` |
| **integration（主门）** | `cargo xtask integration` | **5331/5331 passed (1 slow, 1 flaky), 0 failed, 0 skipped**（EXIT=0，Summary 478.371s）——**核心判据 0 failed 达成**。1 flaky=`jackdaw_runtime::lod_group::wobbling_the_camera_around_a_switch_places_nothing_new`（TRY1 FAIL→TRY2 PASS，与任务改动面零交集，详 ⚪-3） | `a3a4_qa_integration.log` |

与程序归档对照：程序 `a3a4_integration.log` Summary 5331/5331 passed (1 slow), 0 failed，
全文零 FAIL 行——QA 复跑同总数同结局，主门证据双向成立。

## 二、8 红逐条核实（对照 t11-final-qa §一 8 红诊断表 + 程序报告 §二至三）

先对红账：QA 在 `t11t3_qa_mac_gate_integration.log` 逐条复核 t11 基线终局——**8 failed**
（standalone_scaffold×1、reference_rewrite×3、reference_audit×1、session_journal×2、
panels reconcile::a_maximized_leaf_draining×1、controls ui_probe_click×1）**+3 flaky-passed**
（maximize_toggle、switching_workspaces、+a_maximized_leaf_draining 本身 2 fail 1 pass 计入
failed）——与 t11 表及 A4 建账口径逐条一致。程序表格 9 行=8 红（#1=A3）+负载 flaky 注记，无遗漏。

| # | 修复层核实（QA 亲读代码） | 判定 |
|---|---|---|
| 1 (=A3) | `module_patch_lines`（lib.rs:2734）与 `add_module_crates`（lib.rs:2103）两处注入均 gate `dev_checkout::jackdaw_dev_checkout().is_some()`；helper 语义亲读（env 覆盖优先，否则运行中 exe canonical 后须落在编译期源码树内）——与 standalone 测试「复制二进制到 /var/tmp + env_remove」手法互为印证，dev-checkout 形态（teaches/fork-patch/物理工程双源 patch）不受影响。非 dev checkout 走既有降级 note（措辞校准为指引用户自建 fork）。`jackdaw_project_build/build.rs` 补 `rerun-if-changed=<ws>/Cargo.toml`（fork_pin 读该 manifest，原先仅 embed 分支监视）——修法与 buglist A3 修复方向逐字吻合。红证 `a3a4_red_standalone_scaffold.log` 亲核（panic 于 :132，产物两段 `[patch]` 各 5 行 `path = ".../bevy-fork-pinned"`）；绿证：QA 复跑 `the_shipped_binary_scaffolds_without_a_checkout` PASS 33.19s + `a_physics_game_patches_every_fork_crate_on_both_sources`（lib.rs:3732 引用核实）PASS + 程序 scaffold 归档 133/133 | **成立** |
| 2-4 | `canonical_of_moved`（reference_rewrite.rs:688）语义亲读：先常规 canonicalize；失败（文件已被移走）则自最深**仍存在**祖先 canonical 化拼回尾部，双侧（`retarget_tabs` 的 old_canonical 与 tab held、`stands_on` 的 held）走同一 resolver → 同形比较；folder 变体 strip_prefix 得非空 tail 拼到 new_canonical——三条 guards 断言（tab 新名/folder 同尾/journal 新路径）在 QA 复跑全 PASS。**这是 Y8「旧文件复活」缺陷在 macOS 的真实复现修复**（T05-T1 的 retarget 修复在 macOS 因拼写不匹配从未生效过），建议 buglist Y8 加注（⚪-4） | **成立** |
| 5 | `indexed_path`（asset_index.rs:321）第二跳：两侧 canonicalize 后再 strip，任一命中即相对化；**原语义分支全保留**（原始拼写 strip 在前、相对路径逻辑在后）。边界核实：项目内 canonical 拼写（/private/var/…）第一跳 miss 第二跳命中→仍可查（不重蹈 #7 返工覆辙）。断言未动（恰 1 行+计数行），QA 复跑 PASS | **成立** |
| 6 | 唯一测试侧改动：双侧 `std::fs::canonicalize` 后比较，`starts_with`/`ends_with` 谓词与失败信息原样，产品行为零改动（journal 记 tab canonical 路径是既有正确行为）。§三断言纪律逐 hunk 核对 | **成立** |
| 7 | `save.rs::author` 的 `get_prefab` 闭包：绝对路径且既不以 `ProjectRoot.root` 原始拼写、也不以其 `dunce::canonicalize` 形态为前缀→直接 None（miss 语义同修前，只省掉文件系统行走）——**返工教训已内嵌**（两种拼写均放行，项目内 canonical 形态 prefab 不误拒）；`ProjectRoot` 缺失时保持原行为。**autofs 论证 QA 独立复现**：本机 python 微基准 `realpath("/home/joe/...box.jsn")`=69-92ms/次（5 次采样），`/tmp` 死路径≈0ms，`mount` 实证 `map auto_home on /System/Volumes/Data/home (autofs)`——与程序 70.5ms 数据同量级。归档探针/画像亲核（emit 77-101ms、SLOW CANON /home/joe ×169、sample 栈 canonicalize→realpath→__getattrlist）。**5ms 预算未动**（session_journal.rs 该测试零 diff），QA 复跑预算测试 PASS；修复后 0.62-1.0ms 实测归档在案 | **成立** |
| 8 | `observe_if_alive`（feathers/utils.rs:101）家族语义亲读：queued command 内 `world.get_entity_mut(entity)` 成功才 `observe`——与 `attach_or_despawn` 同族（实体已死则随实体丢弃）。project_window 既有实体 observe **全部**换用；剩 2 处 raw `.observe` 亲核均为同队列 fresh spawn（1287 行 caption=同函数刚 spawn、1543 行 spawn-builder 链），同队列 FIFO 无窗口，不换正确。⚠️ 计数纠偏见 🟡-1：实际 **11 处**（行×3+瓦片×8），报告写 8 处（行×3+瓦片×5）——修复比宣称更全，无功能缺口。panels reconcile 确定性红 + maximize_toggle/switching_workspaces 两 flaky 在程序终跑与 QA 复跑均一次过 | **成立**（报告计数 🟡） |
| 9 | `select_all_gesture` 平台分支（test_input.rs:578）：macos=SuperLeft/Key::Super，余=ControlLeft/Key::Control——**fork 源码亲证**：`bevy-fork-pinned/crates/bevy_ui_widgets/src/text_input.rs` `let command = if mac { SUPER } else { CTRL };`（~:160），Ctrl+A 在 Mac 是无操作的论证闭合。断言未动（ui_probe_click 测试文件零 diff，仍 `typed == "entity: 42"`） | **成立** |

## 三、断言纪律（逐 hunk）

- `git diff 7d27cf47..HEAD` 全量文件面：loop/ 外改动=**产品 8 文件 + 测试 1 文件**，与报告
  §五清单完全一致，无夹带；
- 测试侧唯一文件 `tests/guards/session_journal.rs` 单 hunk=#6 比较形态（双侧 canonicalize），
  谓词/失败信息原样；**5ms 预算测试零 diff**（未放宽、未分平台、未加时）；
- #9 修在 `src/test_input.rs`（合成输入注入 helper，任务预授权面），消费它的断言测试文件
  零改动；
- 无 skip/allowlist/retry 上限调整（xtask 与 nextest 配置零改动）；产品文件 diff 均为修复本体
  +注释，无内联测试改动混入。
- **结论：断言纪律零违例**——「零预算放宽、零等待加时、零断言弱化」的宣称成立。

## 四、证据链与已知瑕疵评估

- 红证：t11 归档 8 failed+3 flaky 逐条对账（§二）；A3 独立红证归档亲核（EXIT=101、断言
  :132、两段 fork [patch] 全文在档）。
- 绿证：程序归档（scaffold 133/133、guards 26/26 覆盖 #2-7 全部目标测试+邻域、
  panels+controls 55/55、integration 5331/5331 零 FAIL 行）与 QA 六门独立复跑双向互证；
  返工 5 红（record_counts×1、material_overrides×1、remote_placement×3）在程序终跑与
  QA 复跑均 PASS。
- **#7 返工首跑日志被复跑覆盖（程序自曝）——QA 裁定：可接受（⚪-2）**。理由：①loop README
  门禁证据标准（2026-10-25）明文要求「修完问题重跑必须覆盖归档日志」——终跑覆盖归档是
  契约行为而非销证；②首跑失败清单以逐字引文存世（报告 §三-9 含断言形态
  `left index 0 right index 1`），5 项恰为 misgate 必然受害域（sparsify/prefab 跟随），
  与「gate 只认原始拼写」的机制在源码级闭合；③5 项在程序终跑与 QA 独立复跑双绿。
  残余风险仅「首跑恰为此 5 项」的原始日志缺位，不足以动摇任何一项修复的成立。
  实践建议（不改判）：今后返工轮的首跑红日志以独立文件名归档（如
  `*_integration_rework_red.log`），避免依赖报告引文。

## 五、偏差分级汇总（QA 本轮新增）

1. **🟡 报告 #8 计数不准**：`a3a4-mac-baseline-report.md` §二/§五称 project_window
   「8 处」observe 换用（行×3+瓦片×5），实际 **11 处**（行×3+瓦片×8；QA 逐行清点，
   旧文件 13 处 raw `.observe` → 新文件 11 处 observe_if_alive + 2 处同队列 fresh 保留）。
   修复比宣称更完整，无功能缺口、不影响任何测试结局；建议主控在台账/报告收尾时以
   11 处口径更正一行（无需返工）。
2. **⚪ #7 返工首跑日志覆盖**：可接受，评估见 §四。
3. **⚪ QA 复跑新观察 1 例无关 flaky**：`jackdaw_runtime::lod_group::
   wobbling_the_camera_around_a_switch_places_nothing_new` TRY1 FAIL（多出一个可见层级，
   left/right 实体清单在档）→TRY2 PASS。该域（jackdaw_runtime/lod）与 A3+A4 改动面零交集；
   t11 基线/程序终跑/t10a 该测试均一次过——本机首见，属环境 flaky 族偶发，不影响
   0 failed 终局。建议挂「Mac integration flaky 族」观察账（与 maximize_toggle/
   switching_workspaces 同类；后两者本轮两跑均未复发，#8 修复有效性不受影响）。
4. **⚪ buglist Y8 加注建议（勾选归主控）**：Y8 已勾选项的 T05-T1 修复（6ba0ce4b
   follow_a_move retarget）在 macOS 上因 `/var`→`/private/var` 拼写不匹配**从未生效**，
   f7f57ab7 `canonical_of_moved` 才使其真落地——建议 Y8 条目补一行注记
   （"2026-10-28 A3+A4：T05-T1 修复在 macOS 静默未生效（canonical 拼写不匹配），
   f7f57ab7 canonical_of_moved 补齐，guards×3 复绿"），保持 [x] 不变。
5. **⚪ 语义缺口维持上报**：shipped binary + physics 模块的两个 bevy 解析风险（程序 §七-1，
   既有设计降级，note 已指引自建 fork）——维持主控裁定，未擅自发明。
6. **⚪ 遗留不动项与程序一致**：canonical_prefab_path 通用行走（W15 族）、autofs 死路径
   stat 慢不限于 /home/joe（#7 修复按「项目外绝对路径不探测」规避整族）、doctests
   jackdaw_bind dyld 家族（本轮 --test 域不受影响）。

## 六、裁决与 buglist 建议

- **VERDICT: PASS**（A3+A4）。核心判据：①六门 QA 亲跑全绿，integration 0 failed；
  ②8 红修复层逐项源码级核实成立（含边界与返工教训内嵌）；③断言纪律零违例、5ms 预算
  两平台未动；④红绿证据链双向闭合；⑤唯一 🟡 为报告计数笔误（修复更全方向），无功能影响。
- **buglist A3：建议可勾选 [x]**——gate 修复+独立红绿+dev-checkout 族回归+build.rs 监视
  补齐+QA 复跑全绿；闭环注记建议含本报告路径。
- **buglist A4：建议可勾选 [x]**——8 红全部处置、主门 QA 独立复跑 5331/5331 全绿；
  台账口径由「带已知环境红」升为「全绿基线（5331/5331；QA 复跑含 1 例无关 flaky retry，
  观察账见 ⚪-3）」。
- 主控回流清单：🟡-1（计数更正）、⚪-3（flaky 观察）、⚪-4（Y8 注记）、⚪-5（语义缺口裁定）。

## QA 会话产物索引

- 六门日志：`loop/reports/a3a4_qa_{fmt,clippy_ws,clippy_phy,libtests,fast,integration}.log` +
  `a3a4_qa_exitcodes.log` + 脚本 `a3a4_qa_gates.sh`（串行，无 RUST_BACKTRACE）。
- 亲读对象：7d27cf47..b15ac34c 全量 diff、`dev_checkout.rs`、`reference_rewrite.rs`（retarget/
  stands_on/folder_tail 全文）、`asset_index.rs::indexed_path`、`scene_io/save.rs::author`、
  `project_window.rs` observe 全点位、feathers `utils.rs`、`test_input.rs`、
  bevy-fork-pinned `text_input.rs`、buglist A2/A3/A4/Y8。
- 独立复现：autofs realpath 微基准（69-92ms）+ mount 实证。
- 收尾：无 jackdaw/jd/nextest/cargo 残留进程；本轮 scratch（/var/tmp/jackdaw_recipe_*×2）
  已清；更早会话遗留的 recipe_*×6 与按测试设计保留的 `jackdaw_standalone_jd` 未动
  （非本轮产物）。
