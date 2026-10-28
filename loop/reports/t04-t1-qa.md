# T04-T1「写盘原子化与损坏防御」QA 验收 — 提交 `160893e6`（分支 `loop/t04-save-recovery`，13 文件 +776/−29，HEAD/diff 亲核一致）

口径：`loop/plans/t04-save-backup-recovery.md` §二 T1 验收 6 项 + 程序报告 `loop/reports/t04-t1-report.md`（§偏差与取舍 10 条）。QA 只验不修。工作区仅历轮遗留（`.gitignore` 本地改动、未跟踪 `buglist.md`）。

## VERDICT: PASS — 方案 T1 验收 6 项全绿（红→绿有数字、故障注入真实、真机链独立复现、tmp 残留 0）；review 无新 🔴；扩散扫描发现 1 个 🟡 方案外漏项（`file.convert_to_binary/text` 裸写，源文档不丢、不违反 T1 契约，建议 T2 顺手吸收）+ 一组 ⚪ 低危残留，均不阻塞。

## 1. 门禁（程序日志 `gate-*-t04t1.log` 独立行 exit code 齐全，无需补跑）

| 门 | 独立行 exit | 数字 |
|---|---|---|
| fmt | `FMT_EXIT=0` | — |
| clippy（workspace+all-targets+dylib+`-D warnings`） | `CLIPPY_EXIT=0` | — |
| xtask fast | `XTASK_FAST_EXIT=0` | **2869 passed, 2 skipped**（32.674s） |
| xtask integration | `XTASK_INTEGRATION_EXIT=0` | **5086 passed, 2 skipped**（332.466s） |

增量自洽：fast +3 = document.rs 新单测 ×3（lib 面）；integration +12 = guards atomic_writes ×9 + document ×3。与 T03-r2 基线（2866/5074）精确衔接。

## 2. 红→绿真实性（QA 亲跑 + 逐条核实）

- **绿侧亲跑**：`cargo test --test guards atomic_writes` → **9 passed, 0 failed, exit 0**；`cargo test -p jackdaw_api_internal document` → **4 passed, 0 failed, exit 0**。
- **红侧**：`t04t1-red-run.log` `0 passed; 7 failed`（:189），7 条 FAIL 与程序红表一一对应（prefab/project.json/conversion×2/damaged/sweep/untitled Save）。红轮测试文件为中间版本（7 条；N8 后半 resolved/dismissed 两条当时未写——红日志编译警告 `unused import: SceneTab` @atomic_writes.rs:18 佐证），N8 缺陷红证由前半承载（旧行为 Save=Discard 直接关 tab → `tabs.len()==2` 断言 FAIL）——可接受。
- **红证结构自洽**：红跑编译通过且行为断言 FAIL，证明 src 处于「垫片在、行为旧」状态。
- **垫片 3 处 pub 化零行为变化 — 属实**（diff 逐行核实）：`apply_confirm_dialog_action` fn→pub、`SceneDialogTask` pub(super)→pub（+scene_io re-export）、`transition_to_editor` pub(crate)→pub，均纯可见性（偏差#6 成立）。
- **temp 槽占用法测试设计审查（偏差#1）— 成立**：
  - `occupy_temp_slot` 用**目录**占位 `.{name}.tmp-{本进程pid}`——`File::create` 对已存在目录在 Windows/Unix 均必败，跨平台、零依赖；
  - 区分力（源码级核实）：裸 `fs::write` 不经 temp 直接写穿目标（保存 Ok + 旧字节丢失 → 红断言必挂）；`write_atomic` 的 staged `File::create(temp)` 失败 → 返回 Err + 目标零触碰（绿断言通过）——**两种实现产生可观测差异**；
  - blocked parent 论证成立（父目录不可达时两种实现的 open 都先失败、旧文件均不可达，无区分力）；
  - 断言严格性：`fs::read(path) == OLD`（`Vec<u8>` 逐字节）✅；conversion 用例附加「源 .jsn 不被 rename .bak、无 .bak 出现」双向断言 ✅。

## 3. 真机链独立复跑（`loop/qa/t04t1-save-sha.ps1` 三阶段 + QA 驱动脚本 `t04t1-qa-before.ps1`，证据 `loop/reports/t04t1-live/`、`t04t1-qa-launch.log`）

新构建亲跑（`cargo build -p jackdaw` EXIT:0）→ launch → save → wrap：

```
[save] {"id":"scene.save","result":"finished"}
[saved file] assets\scene.bsn (116352 bytes, 1 changed)
[stamp line] '// jackdaw 0.21.0-dev | bevy main' ok=True
[sha disk body]  B35F49482162D87AFD2549D9ED864748CE2F2B646B04D8C69F4D1429C6568CB0 (116318 bytes)
[sha editor emit] B35F49482162D87AFD2549D9ED864748CE2F2B646B04D8C69F4D1429C6568CB0 (116318 bytes)
SAVE VERDICT: PASS (stamp=True sha_match=True)
```

- **与程序数字完全一致**（B35F...C8CB0）；QA 附加验证：**保存幂等**（保存前后盘上全文 SHA256 均 `4F55D81E...17DB`，同一文档状态二次落盘逐字节幂等）；**保存后工程 `*.tmp-*` 残留 = 0**；wrap 后无残留进程。
- **偏差#9 在 QA 侧复现**：launch 阶段 `ShellExecute`（ComObject）冷启动失败一次（bat 生成但编辑器未起、15812 未监听）——按程序先例手动 `cmd /c` 执行同 bat 兜底成功；脚本三阶段重构（before 快照落盘）正是分阶段复跑得以成功的关键。工具层问题，非产品缺陷，建议后续把 launch 阶段的 ShellExecute 直接改为 `cmd /c` 执行。
- **去 stamp 口径源码核实（偏差#3）— 成立**：`scene_io/stamp.rs` 注释+实现证明 stamp 只在落盘边界加（`with_stamp` = stamp 行 + body，内存快照不带）；`jackdaw/scene_bsn` 返回内存 emit body。**附加观察（⚪）**：保存链用 `emit_bsn_scene_for_file`（RelativeToFile spelling）而 scene_bsn 用 `emit_bsn_scene_with_inline_assets`（AsHeld）——两 emitter spelling 不同，SHA 相等依赖该场景两种 spelling 输出一致；对含内联差异的场景/prefab tab 此对比口径需换 emitter。my-game 实测一致，锚点意图达成，不阻塞。

## 4. 代码 review（重点扩散面，`git show 160893e6` 逐文件 + QA 独立全仓扫描）

### 4.1 原子改造逐项核实 — 全部落实
prefab `save_prefab_to_disk`、`save_project_config`/`create_default_project`、`project_settings::write_document`、`jsn_to_bsn`（commit_conversion + with_stamp / catalog 只 atomic 不加 stamp）均改 `write_atomic`；`write_levels`（model_lod.rs）现状已走 `write_atomic`（偏差#7 属实）；`scene_save_all_system` 对 dirty untitled 返回 false 阻止退出（偏差#8 属实）。

### 4.2 QA 独立裸写扫描（全仓 `fs::write|File::create|write_all|OpenOptions`，~200 命中，产品/测试逐一分类）

- **新发现 🟡 [方案外漏项]：`file.convert_to_binary` / `file.convert_to_text`**（`src/file_ops.rs:515/534` operator；project_window 右键菜单 "Convert to Binary/Text" + F3 面板真实可达）→ `crates/jackdaw_bsn/src/file.rs:235` 裸 `fs::write` 重写用户文档（写二进制孪生后删源）。**写序安全**（写成功才删源：中断时源文档完好、TwinExists 拒绝在先），故不违反 T1「保存中断不损坏权威旧文件」的操作化定义（旧文件=源，未损）——**非 🔴**；但中断留半截孪生 + 重试撞 TwinExists 卡死需手动清理。落在 commit 标题「every authoritative write」伞面而方案改动面 1-5 未列。**建议 T2 顺手吸收**（改 `write_atomic` 一行；T2 的 `.bak` 轮转同场）。
- ⚪ 低危残留（方案外、低频、损坏=丢偏好或可重生成，均记录不阻塞）：keymap 持久化裸写（`api_internal/keymap/persist.rs`、`src/keybinds.rs`；读取侧损坏容错已有测试）；texture `.meta` sidecar（`src/texture_import.rs:80`）；launcher 对用户工程 `Cargo.toml` 的 repin/扩展开关裸写（`project_actions.rs:330`、`extensions.rs:881`，toml_edit 保形）；`migrate.rs` 用户源码改写（`.bak` 先行）；viewport 设置 / PIE 脚手架（派生）。
- 正面排除：`asset_index.rs:1042` 为测试 harness；export/dist/bootstrap/构建系统产物=派生物；`undo_snapshot.rs` 为内存 deflate；`document_ops.rs` 生成 operators.md 可再生。

### 4.3 专项五点（任务书 ①-⑤）
- ② **孤儿 tmp pattern**：`is_temp_file_name` 收窄到编辑器自身命名（前导点 + `.tmp-` + 纯数字 pid + `at>1` 文档名非空），60 秒新鲜窗保护并发实例，跳过 `.git`/`target`；lookalike 保护测试在位（document.rs 单测：fresh 留/无点前缀留/非 pid 留/.git 内留；guards：backdate 孤儿删）。**误删用户文件风险极低** ✅。
- ③ **损坏 rename**：`back_up_corrupt_project_config`（读不了也算损坏）→ `project.json.corrupt-<毫秒ts>` → 状态栏 `notify_info`（guards 断言含 "damaged"）→ 默认重建走原子 ✅。
- ④ **untitled 状态机全分支**：排队（untitled Save → swap + `save_scene_with_outcome`==DialogOpened → `PendingSaveAsClose`）；poll Save 分支三向（保存成功→finish 关 tab；失败→cancel；dismissed→cancel）+ **「scene 未加载→cancel」防悬挂修补**（旧行为此处直接 return 会让 deferred close 悬挂——本轮顺手修掉）；cancel 后资源清空可二次触发（测试断言）。观察（⚪）：Save As 模态期间 `tab_index` 理论上可因外部变化失效（模态下难触发）。
- ⑤ **sync_all 位置**：`File::create(temp)` → `write_all` → **`sync_all()`** → rename（`document.rs` staged 闭包）✅ 裁决 4-A；失败路径清 temp 返回 Err。
- 模块 doc 同步改写（删「Save falls back to Discard」自认偏差）✅。

## 5. buglist 核对 — 合格

Y9、W9 均 `- [x]` + `> 已修复 160893e6` 备注，含覆盖用例名；W9 备注注明 catalog 不加 stamp 口径。与实测一致。

## 6. 偏差 10 条逐条裁定

| # | 偏差 | QA 裁定 |
|---|---|---|
| 1 | 故障注入改 temp 槽占用法 | **合理**（区分力源码级核实，见 §2；断言逐字节严格） |
| 2 | sync_all 无 headless 断言点 | 合理（掉电语义不可单测；实现顺序已核实） |
| 3 | SHA 去 stamp 口径 | **成立**（stamp 边界源码核实）+ ⚪ 观察：两 emitter spelling 差异使该口径内容依赖 |
| 4 | catalog 不加 stamp | 合理（维持资产文档语义） |
| 5 | N8 poll 接线 fn 级覆盖 | 合理（rfd task 不可伪造属实；poll 三向+防悬挂已逐行核实） |
| 6 | 垫片 3 处 pub 化零行为 | **属实**（diff 逐行核实） |
| 7 | write_unsaved_model_settings 免改 | 属实（write_levels 已 atomic） |
| 8 | save_all 链未动 | 属实（dirty untitled → false 阻止退出） |
| 9 | ShellExecute 冷启动失败 | **QA 复现一次**；cmd /c 兜底 + 三阶段重构有效；建议工具层固化 |
| 10 | 并发 60s 窗防护 | 合理（撞窗后果=可重试失败，权威文件不受损） |

## 7. 问题统计

| 级别 | 条目 |
|---|---|
| 🔴 严重 | 0 |
| 🟡 中等 | 1（`file.convert_to_binary/text` 裸写孪生转换——方案外漏项，源文档不丢、不违 T1 契约，建议 T2 吸收） |
| ⚪ 轻微 | keymap/.meta/repin 等低危裸写残留；SHA 口径 emitter spelling 差异；Save As 模态期 tab_index 边界；launch 工具层 ShellExecute；document.rs 测试变量名 `dot_keeping` 语义误导（实为应删项） |

**正向**：temp 槽目录占用法设计聪明且论证诚实（主动承认 blocked parent 不可区分）；「scene 未加载 → cancel」防悬挂是超方案的顺手修补；sweep 的 lookalike 测试矩阵完整；真机链三阶段可独立复跑的重构在 QA 复跑中直接兑现价值；红→绿/门禁/真机数字与 QA 独立复跑零偏差（SHA 十六进制逐位一致）。

## 8. 方案 T1 验收 6 项对照

| 验收项 | 状态 |
|---|---|
| 1. headless 故障注入 ×3 旧文件字节不变 | ✅（红 7 failed → 绿 9 passed 亲跑，逐字节断言） |
| 2. 损坏注入 `.corrupt-<ts>` + 状态栏 | ✅ |
| 3. untitled Save As 链（成功关/取消留） | ✅（三分支 + 二次触发） |
| 4. 孤儿 tmp 预置清除 | ✅（guards + 单测；真机保存后残留 0） |
| 5. 「保存中断不损坏旧文件」操作化（headless 注入为准） | ✅ |
| 6. 真机 scene.save ↔ scene_bsn SHA 一致 | ✅（独立复跑，含幂等验证） |

**VERDICT: PASS**
