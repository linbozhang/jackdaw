# T04 场景保存、自动备份与崩溃恢复 — 实施方案

> 策划产物（2026-10-25，基于 `loop/t03-undo` HEAD 765b4599 全量代码核实；T03-T2 修复正在该分支复验，
> 若 T03 终验返工，本文行号按符号名重定位，结论不受影响）。需求来源：`loop/plans/roadmap-game-dev.md` T04。
> 验收原文：未保存恢复、多标签关闭提示、自动备份、场景+附属文件一致性。**验收=异常退出可恢复（预览+选择，
> 不覆盖）；保存中断不损坏旧文件**。
> buglist 吸收 Y9/W9；buglist 之外新发现编号 **N1–N8**（沿用 T03 命名风格）。

---

## 0. 架构事实（核实结论，方案的地基）

- **场景主链写盘已是原子的**：`write_atomic`（temp + 同目录 rename，
  `crates/jackdaw_api_internal/src/document.rs:92-111`，save.rs:13 re-export）。场景文本
  （`src/scene_io/save.rs:394`）、terrain sidecar（`save.rs:531`）都走它；refused tab 禁写
  （`save.rs:148-158,260-268`）；legacy `.jsn` 保存时先 rename 成 `.jsn.bak`（`save.rs:384-391`）。
- **保存顺序有明确设计**：terrain sidecar → 场景文本 → `write_alongside`（模型 LOD meta + 升级 prefab，
  `save.rs:17-40,406`）→ 布局持久化 `project.json`（`save.rs:436`）→ 缩略图缓存（`save.rs:438`）。
  写完全部后才清脏并记录基线（`save.rs:413-433`）。
- **T03 已交付 per-tab 指纹脏标记**（本任务直接复用，见 §五）：`SceneTab.saved_doc_hash /
  saved_undo_len / observed_pushes`（`src/scenes/mod.rs:128-166`），加载也建基线
  （`src/scene_io/load.rs:441-454`）；同源 emit 器 `document_fingerprint`（`save.rs:90-129`）。
- **多标签关闭提示三套确认对话框已存在**：单 tab 关闭（`scene.close` op，`scenes/operators.rs:574,584-613`
  → `confirm_dialog.rs:53` Save/Discard/Cancel）、关窗/退出（`scenes/mod.rs:46-78` 拦 `WindowCloseRequested`
  → `confirm_dialog.rs:220` SaveAll/DiscardAll/Cancel）、离开项目（`confirm_dialog.rs:474-489`）。
  存在的 ≠ 验收过的：真机从未系统走查（见 §一 C 组）。
- **崩溃恢复为零**：全仓无 autosave/backup/journal/recovery 系统；panic hook 只写日志
  （`src/editor_log.rs:40-47`），日志保留上一份 `editor.previous.log`（`:32-34`）。其余 "recovery" 命中
  （loader 缓存、project_select 装修引导）与场景无关。
- **路径设施**：`crates/jackdaw_env/src/paths.rs` — `config_dir()`/`state_dir()` 受
  `JACKDAW_CONFIG_DIR` 整体覆盖（`:31-40,71-78`，测试隔离即用它）；`local_data_dir()`（logs、SDK 缓存）
  **不**受覆盖（`:17-21`）。这决定 journal 存放位置（裁决项 1）。
- **保存触发点**：`scene.save`（Ctrl+S）/`scene.save_as`（Ctrl+Shift+S）键位在 `src/scene_ops.rs:21-27`；
  `scene.save_all`（`scenes/operators.rs:684`）；PIE 启动前 `save_scenes_before_launch`（`src/pie.rs:748,756`
  — 属 T06 边界，本任务不动）。

---

## 一、现状与缺陷矩阵

### A. 崩溃恢复（T04 主体缺口）

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **N1** | 🔴 | **无任何崩溃恢复机制**。编辑器崩溃/被 kill/掉电后，未保存编辑全部丢失，无 journal、无自动备份、无恢复入口；连"上次异常退出"的检测信号都没有 | 全仓搜 autosave/backup/recovery/panic 仅命中日志与无关模块；panic hook 只 `error!` 日志（`src/editor_log.rs:42-46`） |
| **N2** | 🟡 | 正常退出链完备但无快照步骤：quit 链 = 拦截关窗 → confirm → AppExit（`src/scenes/mod.rs:46-78`），无"退出时快照"挂点；`taskkill /F` 类硬杀更是完全无覆盖——journal 必须平时就新鲜（裁决项 2），不能只挂退出钩子 | 同上 |
| **N3** | ⚪ | 既有好底子两处：日志保留 previous（`editor_log.rs:32-34`）可作辅助信号；布局已有 `auto_save_layout_on_change`（`src/lib.rs:3419-3425`）证明"编辑中周期性落盘"在本工程已有先例可循 | 同上 |

### B. 保存原子性与「保存中断不损坏旧文件」

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **N4** | 🔴 | **prefab 保存裸 `fs::write`，不在原子保护内**。`save_prefab_to_disk` 直写（`src/prefab/operators.rs:1993,2022`）；场景保存链的 prefab tab 分支（`src/scene_io/save.rs:301`）与 `write_alongside` 的升级 prefab 写（经 `lod_upgrade::write_upgraded_prefabs`，`save.rs:20-21`）都经它——写盘中途进程断，prefab 旧文件被半截覆盖。场景文本有 `write_atomic` 而 prefab 链漏网 | `prefab/operators.rs:2022` |
| **Y9**（buglist） | 🟡 | `project.json`/`settings.json` 裸写 + 损坏后静默覆盖：保存路径 `src/project.rs:311`、`src/project_settings.rs:95`；**每次保存场景必触发 project.json 写**（`save.rs:436` → `save_layout_to_project`）；损坏后 `load_project_config` 返 None → `create_default_project` 直接覆盖（`src/project_select.rs:524-525`），布局与 last_open_tabs 无提示全丢 | buglist Y9，触发点已按当前代码重定位核实 |
| **W9**（buglist） | 🟡 | JSN→BSN 转换是场景文本里唯一裸写路径：`src/jsn_to_bsn.rs:300,375` 裸 `fs::write`，中途崩溃留截断 .bsn，且写入不带版本 stamp | buglist W9 |
| **N5** | 🟡 | `write_atomic` 无 fsync：temp 写完即 rename（`document.rs:102-109`）。进程级中断安全（同目录 rename 原子）；**掉电窗口**：rename 落盘顺序可能先于数据 → 半截/空文件。验收语义若含掉电需补 `sync_all`（裁决项 4） | `document.rs:92-111` |
| **N6** | ⚪ | 孤儿 tmp 无人回收：进程死在 `fs::write(temp)` 与 rename 之间，`.scene.bsn.tmp-<pid>` 永久残留（`document.rs:97-101`）；失败分支有清理（`:102-109`），被杀分支没有。无害但脏，启动时应扫除 | `document.rs:98-101` |
| **N7** | ⚪ | 跨文件无回滚（sidecar 已落、场景文本失败）：现状以顺序设计缓解——各文件各自原子、失败 tab 留脏可重试，注释自认无跨文件回滚（`save.rs:371-379`）。**不改结构**，验收补"scene text 失败后重试成功且不脏数据"用例钉死该承诺 | `save.rs:371-395` |
| — | ⚪ | 缩略图为可再生缓存（按内容哈希命名，`src/thumbnail.rs:362-380`），失败/损坏无一致性风险，不列缺陷 | |

### C. 多标签关闭提示

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **N8** | 🔴 | **untitled 脏 tab 的关闭对话框 Save 按钮实际执行 Discard**：无路径时 Save 分支直接 `scene_close_system_unprompted`（丢弃关闭），仅 warn 一条，代码注释自认 "Deviation … deferred"。用户点 Save 期望保存却丢数据——按钮语义与行为相反的数据丢失路径 | `src/scenes/confirm_dialog.rs:570-580` |
| **N9** | ❓ | 三套确认对话框（单 tab Save/Discard/Cancel、退出 SaveAll/DiscardAll/Cancel、离开项目）headless 已有针对性测试（`confirm_dialog.rs:593-702`；T03 dirty_matrix 用例 5 验过"保存后 undo 关 tab 必提示"），但**真机 UI 从未系统走查**：三按钮点击路径、Esc/Enter 语义、对话框与拖拽/输入焦点的互斥。T04 验收原文点名"多标签关闭提示"，此组验收为 T3 必做项 | `scenes/operators.rs:584-613`、`confirm_dialog.rs:220,474` |

### D. 场景+附属文件一致性

| 编号 | 严重度 | 现状描述 | 证据 |
|---|---|---|---|
| **N10** | 🟡 | 一致性现状总评：**单文件原子性基本具备（缺 N4/Y9/W9 三处）、多文件只保顺序不保事务**。场景+sidecar+prefab+project.json 的成组一致靠"全部写完才清脏 + 失败留脏重试"维护；崩溃发生在组内中间时的盘面状态=部分新部分旧，恢复侧（journal）是唯一能对齐到"崩溃瞬间编辑态"的机制——journal 与保存链的一致性约定是 T2 设计点 | `save.rs:257-441` 全序 |
| **N11** | 🟡 | 引入 journal 后的两个新一致性点（前瞻，进 T2 验收）：① 恢复 tab 的后续保存必须 `note_known_content`（`src/scenes/external_watch.rs:169`），否则自己的写被读回当"外部修改"误弹 reload；② journal 内文档是内存 emit（无 stamp，stamp 只在落盘边界 `save.rs:367`），恢复预览/保存路径要经同一 `with_stamp` 边界，不得绕过 | `external_watch.rs:169`、`save.rs:367` |

**统计：🔴 3（N1、N4、N8）｜🟡 5（N2、Y9、W9、N5、N10/N11 合并计 2）｜⚪ 3（N3、N6、N7）｜❓ 1（N9 真机走查）**

### buglist 重叠表（保存/崩溃/恢复/备份/关闭提示相关全量扫描）

| 条目 | 一句话 | T04 处置 |
|---|---|---|
| Y9 | project/settings 非原子写+损坏静默覆盖 | **吸收（T1）** |
| W9 | jsn_to_bsn 裸写无 stamp | **吸收（T1）** |
| Y8 | `file.rename` 不联动打开中 tab，Ctrl+S 写旧路径致两份分叉 | 不吸收，归 **T05**（引用稳定性主责）；§四 备案 |
| Y10 | 布局 DockTree 无环校验，坏 project 文件栈溢出崩溃 | 不吸收本体；T1 落地"损坏先备份再重建"后覆盖路径留档、触发面收窄，布局校验留 backlog |
| Y28 | BSN 解析无深度上限，不受信 .bsn 可 panic | 不吸收；但 **T2 验收强制**：journal 文件 parse 失败走安全路径（保留文件+告警+跳过），不得因恢复入口引入新崩溃面 |
| W26 | PIE Job Object assert 把启动失败变编辑器崩溃 | 不吸收（崩溃源治理，PIE 域）；备注：崩溃源越多 journal 价值越大，治理归各自主任务 |
| W7 | 每次保存资产索引 gone 检测 O(n·m) 主线程 | 不吸收（性能专项）；备注：T2 journal 若同帧叠加写盘需避让（debounce 已缓解） |
| W11/W12 | 仅大小写重命名失败 / 盘符相对路径漏判 | 不吸收，归 T05 |

---

## 二、分任务拆解（T1/T2/T3）

### T1「写盘原子化与损坏防御」（N4+N6+Y9+W9+N8；N5 按裁决项 4）

**目标**：把保存链上所有权威写盘点纳入原子保护；损坏配置先备份再重建；修掉 untitled Save=Discard 反语义。

**改动面预估**：
1. `save_prefab_to_disk`（`prefab/operators.rs:1993`）及 `write_upgraded_prefabs`/`write_unsaved_model_settings` 的落盘点改 `write_atomic`（含 stamp 与否维持现状）；
2. `save_project_config`（`project.rs:311`）、`project_settings.rs:95`、`jsn_to_bsn.rs:300,375` 改 `write_atomic`（jsn_to_bsn 补 `stamp::with_stamp`，`scene_io/stamp.rs:11`）；
3. `load_project_config` 损坏分支：先把坏文件 rename `<name>.corrupt-<ts>` 再走默认重建（替换 `project_select.rs:524-525` 的直接覆盖），状态栏告知路径；
4. `write_atomic` 补 `sync_all`（若裁决 4 选 A）：temp 写后 `file.sync_all()` 再 rename；启动时清理本编辑器目录下孤儿 `.*.tmp-*`；
5. N8：untitled tab 关闭确认的 Save 分支改为打开 Save As 对话框（复用 `spawn_save_dialog`，`save.rs:57-67`），`poll_scene_dialog` Save 分支成功后再执行 `scene_close_system_unprompted`（沿用 `SaveOutcome::DialogOpened` 注释 `save.rs:69-84` 的 deferred-action 模式；对话框期间 tab 保持打开，Cancel/对话框关闭 = 回到未关闭状态）。

**验收标准（可执行可复现）**：
- [ ] headless 故障注入：对 prefab 保存、project.json、jsn_to_bsn 各写一个"写盘失败（blocked parent 目录法，先例 `save.rs:1642,1756,1950`）→ 目标旧文件字节不变"用例（保存前写旧内容 → 触发保存 → 断言读回逐字节相等）；
- [ ] 损坏注入：预置半截 JSON 的 project.json → 初始化 → `.corrupt-<ts>` 存在且内容=坏文件、新 project.json 可解析、状态栏有提示（Y9 红→绿）；
- [ ] untitled 脏 tab：关闭 → Save → Save As 对话框出现 → 选路径 → 保存成功且 tab 关闭；Cancel → tab 保留仍脏（N8 红→绿）；
- [ ] 孤儿 tmp：预置 `.scene.bsn.tmp-999999` 假文件 → 启动后被清除；
- [ ] 「保存中断不损坏旧文件」操作化定义（写入任务的验收措辞）：**进程级中断**（写失败/panic/kill 落在保存窗口内）→ 权威旧文件（场景/prefab/project.json）字节不变；**掉电语义**按裁决项 4 的裁定范围执行。
- [ ] 真机（BRP 驱动）：my-game 打开场景 → `jackdaw/call_operator` scene.save → `jackdaw/scene_bsn` 与盘上文件 SHA256 一致（回归锚点，T02 沉淀脚本 `loop/qa/t02t2-light-color.ps1` 的 scene.save 调用模式可复用）。

**测试设计**：guards 单测（`tests/guards/` 新 `atomic_writes.rs`：故障注入 ×3 + 损坏备份重建 + untitled Save As 链 headless 化——Save As 对话框 headless 下无 font 即跳 UI 直接断言 `SceneDialogTask` 已排队（`confirm_dialog.rs:215-219` 的无字体模式先例））；真机 1 链如上。
**buglist 吸收**：Y9、W9 打钩。

### T2「crash journal 与自动备份」（N1+N2+N3+裁决项 1/2/5/6）

**目标**：编辑中周期性把脏 tab 的文档快照落盘（journal），保存时对旧文件做 `.bak` 轮转；崩溃/被杀后 journal 残留即"可恢复"信号。

**改动面预估**：
1. 新模块 `src/scene_io/session_journal.rs`：journal 写入（`write_atomic` 落盘）、会话目录生命周期（启动建、正常退出删、崩溃残留）、轮转（保留最近 N=5 个会话）、损坏 journal 安全读取（parse 失败 → 告警跳过该会话，文件保留）；
2. 触发系统：Update 系统监视 per-tab 脏状态（复用 `tab.dirty` + `observed_pushes` 变化），debounce 窗口（默认 2s，见裁决 2）后对**所有脏 tab**同源 emit（`document_fingerprint` 同一 emitter 家族，`save.rs:98-129`）写入 journal；prefab tab 走 `emit_bsn_scene_with_inline_assets`；
3. journal 条目：`{tab 路径|null, kind, display_name, captured_at, saved_at, entity_count, doc 文本}`；**terrain sidecar 不进 journal**（裁决 6 默认 A），journal 元数据标注该限制；
4. `.bak` 轮转（裁决 5）：`write_atomic` 覆盖前若目标存在，先 rename 为 `<name>.bak`（场景与 prefab 同规则；`.bak` 单份）；
5. 多实例隔离：journal 按会话 pid+时间戳分目录，互不覆盖。

**验收标准**：
- [ ] headless：编辑置脏 → 推进时间过 debounce → journal 文件存在、条目 emit 文本与 `emit_bsn_scene_for_file` 同源；干净 tab 不产生条目；
- [ ] headless：模拟崩溃残留（不删会话目录）+ 正常退出（删）两分支；轮转超 N 清最旧；损坏 journal（手写坏 JSON）读取不 panic、告警且文件保留；
- [ ] headless：`JACKDAW_CONFIG_DIR` 指向 tempdir 时 journal 落在覆盖目录下（若裁决 1 选 A/B 含 config 的方案）——测试隔离的硬前提；
- [ ] headless：保存成功后 journal 中该 tab 条目移除（已持久化，无需恢复）+ `<scene>.bsn.bak` 存在且内容=保存前旧文件；
- [ ] 真机（kill 链，T04 验收核心）：fixture 工程启动（`JACKDAW_OPEN_PROJECT` 直开 + `JACKDAW_CONFIG_DIR` 隔离）→ 编辑置脏（`jackdaw/call_operator` entity.add）→ `jackdaw/recovery`（新 BRP，见 T3；T2 先以文件系统断言代替）确认 journal 新鲜 → `taskkill /F /PID` → 重启 → journal 会话目录残留（断言）。
- [ ] 大场景性能闸：含 terrain 的场景上 journal 写入不造成 >5ms 的帧尖刺（emit 在主线程、写盘经 `IoTaskPool`；实测记录进报告，超标则调 debounce 或改裁决）。

**测试设计**：guards 单测（新 `tests/guards/session_journal.rs`，harness 复用 T03 `dirty_matrix.rs:28-113` 的 `editor()/place_rock()/save()` 模式）；真机 kill 链如上（脚本沉淀 `loop/qa/t04-kill-recover.ps1`）。
**buglist 吸收**：无（本任务主体为新功能）。

### T3「恢复入口（预览+选择，不覆盖）+ 多标签关闭提示验收 + 工具与收尾」

**目标**：启动时检测残留会话 → 恢复对话框（预览+逐 tab 选择，恢复动作本身不写任何权威文件）；三套关闭确认对话框真机走查收口；BRP/MCP 工具补齐；文档与台账。

**改动面预估**：
1. 启动检测：编辑器入场（工程打开后、场景 tab 恢复前）扫描 journal 会话目录 → 有残留 → 弹恢复对话框（UI 沿 `confirm_dialog.rs` 的 scrim+card 模式）；
2. 对话框内容（裁决 3）：每脏 tab 一行——路径/未命名、上次保存时间、journal 捕获时间、实体数、与盘上文件的 diff 摘要（行数差；预览按钮展开文本 diff 视图或复制路径）；动作 =「恢复」（打开为内存 tab 并置脏，**不写盘**）/「丢弃」（删该条目）/ 全部丢弃；
3. 恢复执行：journal 文本 parse（安全路径：失败告警跳过）→ 走既有打开链建 tab → 置 `dirty=true`（无 `saved_doc_hash` 基线不适用——有路径时按盘上文件建基线更合理：恢复 tab 的 saved 基线=盘上文件、当前=journal 内容 → 恒脏，用户显式保存才覆盖）；恢复后的保存经标准 save 边界（自动补 stamp、`note_known_content`）；
4. BRP 新方法 `jackdaw/recovery`（挂 `src/remote/server.rs:147-161` 既有 with_method_main 表）：`{available, sessions:[{started, updated, tabs:[摘要]}]}`；动作走新 operator `recovery.restore {session, tab}` / `recovery.dismiss {session|all}`（`jackdaw/call_operator` 可驱），`jackdaw_mcp` 补 1 个镜像工具（MCP 优先原则——QA 驱动对话框按钮可用 ui_click，但状态断言与批量编排走结构化工具）；
5. N9 真机走查矩阵（三对话框 × 三按钮 × named/untitled tab，共 11 格，见下）；
6. book 文档（保存/恢复节）+ buglist Y9/W9 备注（T1 已打钩则核）+ roadmap T04 勾选 + 台账。

**N9 走查矩阵（真机，ui_tree 定位 + ui_click 驱动，结果可重放）**：
| # | 场景 | 期望 |
|---|---|---|
| 1-3 | named 脏 tab 关闭 → Save / Discard / Cancel | 保存后关 / 直接关不保存 / 保持打开 |
| 4-5 | untitled 脏 tab 关闭 → Save（T1 后）/ Cancel | Save As 对话框→保存即关 / 保持 |
| 6-8 | 退出（多 tab 有脏）→ SaveAll / DiscardAll / Cancel | 全存后退出 / 全弃退出 / 不退出 |
| 9-10 | 离开项目（confirm_dialog.rs:474）→ 确认/取消 | 同上语义 |
| 11 | 脏 tab 存在时 Alt+F4/点 X | 拦截并弹 quit 对话框（`scenes/mod.rs:64-78`） |

**验收标准**：
- [ ] **T04 验收原文两句话的终验链（真机，全 BRP/MCP 驱动）**：
  ① 异常退出可恢复（预览+选择，不覆盖）：kill 链（T2）→ 重启 → `jackdaw/recovery` 断言 available + 摘要字段 → `ui_tree` 断言恢复对话框节点 → `ui_click`「恢复」→ `jackdaw/scene_tree` 断言实体数=journal 记录 → **原 scene.bsn SHA256 与 kill 前逐字节相同**（不覆盖铁证）→ 用户显式保存后文件才变；
  ② 保存中断不损坏旧文件：T1 故障注入用例 + 真机 kill 落在 debounce 窗口内（kill 于保存动作毫秒级窗口难以稳定命中，以 T1 headless 注入为准，真机补一次"kill 于 journal 写盘后、保存前"的常态路径回归）；
- [ ] 多 tab 恢复：两个脏 tab（一个 named 一个 untitled）→ kill → 重启 → 对话框两行各自可独立恢复/丢弃；untitled 恢复为 untitled 脏 tab；
- [ ] 损坏 journal（预删一半字节）→ 启动不崩、该会话跳过并告警、文件保留；
- [ ] N9 矩阵 11 格全过（截图+BRP 日志留档 `loop/reports/`）；
- [ ] 全量门（`xtask fast`/`integration`/docs/doctests）+ 用户 30 秒清单（见 QA 清单）。

**测试设计**：guards 单测（恢复 parse 安全路径、恢复 tab 的 dirty 基线语义、dismiss 清理）；真机脚本 `loop/qa/t04-final-live.ps1`（沉淀 kill-重启-恢复循环，参照 `t03-final-qa-live.ps1` 模式）。
**buglist 吸收**：Y9/W9 备注核验；roadmap T04 勾选。

**QA 清单（放行标准，全任务）**：
- [ ] T1/T2/T3 各自验收标准全绿；每个 🔴 缺陷（N1/N4/N8）有红→绿测试；
- [ ] 「不覆盖」铁证用例（SHA256 比对）真机复现两轮；
- [ ] quick 门（T1/T2）/ 全量门（T3）；
- [ ] 用户 30 秒清单：①改场景不保存 → 任务管理器杀编辑器 → 重开 → 弹恢复 → 恢复 → 内容在且原文件未动；②untitled 场景关闭时点 Save → 弹 Save As；③保存后工程目录出现 scene.bsn.bak 且内容是上一版。

---

## 三、设计决策点（需主控裁定）

| # | 决策 | 选项与利弊 | 建议 |
|---|---|---|---|
| 1 | **journal 存放位置** | A=`config_dir()/state/sessions/<project-hash>/<pid>-<ts>/`：受 `JACKDAW_CONFIG_DIR` 覆盖=**测试隔离免费**；不污染项目目录；换机不跟随（跨机恢复不做，可接受）。B=项目内 `.jackdaw/session/`：随项目走、随仓库备份带走；但污染用户项目目录、需 gitignore 教育、VCS 冲突、多机编辑互相踩。C=`local_data_dir()`（logs 同级）：语义最正统但**不受 CONFIG_DIR 覆盖**，测试隔离要额外机制 | **A**（测试隔离+洁癖双赢；`state_dir()` 基础设施现成 `paths.rs:71-78`） |
| 2 | **journal 写盘时机** | A=脏状态变化后 debounce 2s 写全部脏 tab（emit 主线程+写盘 IoTaskPool）：kill 丢失≤2s；每次≈一次保存 emit 的成本。B=固定间隔（如 2 分钟）：I/O 最省但丢窗口大，验收"异常退出可恢复"成色弱。C=仅退出钩子+panic hook：不覆盖 kill -9（最常见崩溃形态），等于没做 | **A**，debounce 默认 2s 常量化；大场景性能闸不过则调大并如实记录丢失窗口 |
| 3 | **恢复提示 UX 形态** | A=启动时对话框（列表+摘要+预览展开+逐条恢复/丢弃）：满足"预览+选择"验收原文最直接。B=不弹窗、tab 栏放恢复标记：不打扰启动但可发现性差、验收"预览"无处安放。C=独立恢复中心面板：功能全但过重，首版不值 | **A**（scrim+card 沿 confirm_dialog 模式，成本最低） |
| 4 | **write_atomic 补 fsync** | A=补（temp 写后 `sync_all()` 再 rename，可选 rename 后再 sync 父目录——Windows 无目录 fsync 等价物，接受）：一行级改动，掉电语义完整，"保存中断不损坏旧文件"全覆盖。B=不补：进程级中断已满足，掉电记 open-challenges 挂账 | **A**（成本极低，验收措辞可以写死） |
| 5 | **自动备份（.bak）策略** | A=保存时旧文件 rename `<name>.bak` 单份：防"保存了坏内容/保存后悔"，零额外 I/O（本来就要覆盖）。B=N 份轮转：更强但配置面+清理逻辑+收益递减。C=不做：journal 已覆盖崩溃前内容，但"保存后才发现存坏"场景无解 | **A**（场景+prefab 同规则；与既有 `.jsn.bak` 约定 `save.rs:384-391` 呼应） |
| 6 | **terrain sidecar 进不进 journal** | A=不进：sidecar 可达数十 MB，2s debounce 写不动；恢复=场景文本+盘上旧 sidecar，编辑过 terrain 高度的场景恢复后高度回退到上次保存——对话框如实标注。B=进：完整但 I/O 重、debounce 被迫拉长 | **A**（首版如实标注限制；完整版待用户反馈再立项） |

另有小定案（主控可否决）：untitled Save 按钮修法取「Save As 子流程」（T1-5），不取「按钮改名 Discard」（诚实但功能没长）。

---

## 四、风险与回滚

| 风险 | 缓解 |
|---|---|
| journal 高频 emit 在超大场景造成帧尖刺（emit 在主线程，同源 emitter 要求 world 访问） | debounce+只写脏 tab+性能闸（T2 验收 5ms 红线）；不过则调大间隔并如实记录丢失窗口，不砍功能 |
| journal 与 external_watch 误联动（恢复 tab 的保存被当外部修改弹 reload） | N11 验收项钉死 `note_known_content`；恢复链与保存链共用同一写边界 |
| kill-重启真机链 flaky（进程退出时序、端口复用 15703） | 沉淀专用脚本轮询等待（manual §6 时序规约）；journal 文件断言为主、UI 断言为辅 |
| `.bak`/`.corrupt-*` 文件被用户工程工具链误捡（打包器把 .bak 打进包） | `.bak` 与编辑器产物（`.jackdaw/`）语义区分；book 文档注明；导出管线只拷 `assets_dir`（T07 域）天然不涉 |
| 恢复对话框挡住 `JACKDAW_OPEN_PROJECT` 自动开门的启动流（fixture 直开工程 + 恢复提示叠加） | 对话框排在工程打开后、tab 恢复前，单实例互斥（同 confirm_dialog 的 Pending 模式）；真机链即用此开门路径，天然覆盖 |
| 多编辑器实例同项目并发：journal 按 pid 分目录不互踩，但两实例同时崩溃会出两个恢复会话 | 对话框支持多会话列出、逐会话处理；首版逐会话顺序弹（简单） |
| N8 改动引入"Save As 对话框未决时 tab 状态悬挂"（对话框取消后 tab 应保留且仍脏） | deferred-action 状态机进 PendingTabClose 扩展，headless 全分支测试（T1 验收 3） |
| 回滚 | 三任务各自独立成 changelist/分支段：T1 纯写盘路径收紧（revert 无状态残留）；T2 journal 系统整体可摘（唯一落盘面在 state/sessions）；T3 UI+工具层依赖 T2 但 revert 不伤保存链 |

---

## 五、与 T03 已建设施的衔接

1. **per-tab 指纹脏标记 = journal 的触发信号**：`SceneTab.dirty` 与 `observed_pushes`（`scenes/mod.rs:131,146-151`）正是 T03 建立的"该 tab 有未保存编辑"权威判定——journal 触发系统只看它，不另造脏判定（避免第三轨）。T03 复验若对 watcher 语义有返工，journal 触发面随之同步，不另行仲裁。
2. **同源 emit 器 = journal 内容生成器**：`document_fingerprint`/`emit_bsn_scene_for_file`/`emit_bsn_scene_with_inline_assets`（`save.rs:90-129`）保证 journal 文本与"下次保存会写什么"逐字节同源（除 stamp）；恢复预览的 diff 基线也用它生成盘上文件侧文本。
3. **`jackdaw/history` BRP = `jackdaw/recovery` 的模板**：T03 落的 history_handler（`src/remote/server.rs:152,514-562`）示范了"读 per-tab 状态返回 JSON"的 BRP 挂法与 headless 测法，recovery 照此办理；两者并列构成 T04 真机断言的基础设施。
4. **测试基建直接复用**：`tests/guards/dirty_matrix.rs:28-113` 的 `editor()/place_rock()/save()/tab_dirty()` harness 就是 session_journal 与恢复单测的脚手架；T03 的"红→绿+矩阵"报告格式沿用。
5. **保存边界的基线写入 = journal 清条目的时机**：`save_scene_inner` 写完权威文件后更新 `saved_*` 基线（`save.rs:413-433`）——journal 在同一时机移除该 tab 条目（已持久化即无需恢复），语义闭环由保存边界单点维护。
6. **分支与行号基线**：本方案行号基于 `loop/t03-undo` 765b4599（T03-T2 返工 1 后）；T03 终验 PASS 合入 main 后，T04 从 main 拉新分支 `loop/t04-save-recovery`，行号按符号重定位（矩阵证据均已给符号名）。
