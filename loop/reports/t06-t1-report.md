# T06-T1 实施报告：「运行当前场景」通道（N1+N2+N3+N4）

> 程序角色产出，2026-10-26。分支 `loop/t06-play`（自 main `213e3370` 拉出）。
> 规格：`loop/plans/t06-play-isolation.md` §二 T1 + §0 + §三（决策 1/2/3/6 已按裁定实施）+ §五。
> 提交信息：`Run the current scene through the PIE scene channel`。
> 提交哈希：见文末「提交」一节。

## 一、改动面（按方案 T1 五项对照）

| # | 方案项 | 落点 |
|---|---|---|
| 1 | runtime 换把系统 | `crates/jackdaw_runtime/src/lib.rs`：`PIE_SCENE_ENV` 常量 + `pie_scene_override()` + `pie_scene_or(default)` helper（`pub`，对齐 `JACKDAW_PIE` 家族）；`apply_pie_scene_override` 系统挂入 Update 链 `clear_modified_scene_roots → **apply_pie_scene_override** → spawn_loaded_scenes → cleanup_orphaned_scene_members`；只换 `Added<JackdawSceneRoot>` 中 entity index 最小者（=spawn 序首个，确定性），info 日志记录原/新场景路径（真机证据通道之一）。无 env 时零查询零命令，行为逐字节同现状 |
| 2 | 模板毕业 | `crates/jackdaw_scaffold/templates/game/src/lib.rs.template`：`asset_server.load("scene.bsn")` → `asset_server.load(jackdaw_runtime::pie_scene_or("scene.bsn"))`（A+B 叠加：机制层换把 + 教学面显式可读） |
| 3 | `pie.play_current` op + 三态 + temp 副本 | 新模块 `src/pie_current.rs`（~870 行含测试）：`SaveBeforePlay` 三态枚举（serde 兼容读 bool）、`handle_play_current`、场景解析（active=Scene 即它 / Prefab 回落最近 Scene tab（索引距离最近、tie 取先））、`write_pie_temp_copy`（emit_bsn_scene_for_file 同源 + write_atomic、刻意不进 journal）、Ask 对话框（confirm_dialog 同款 scrim+card+三按钮）、`report_background_unsaved`（N3：后台脏 untitled 逐个点名 + 状态栏 warn，不再静默）、`sweep_orphan_pie_copies`（项目打开时清孤儿）、`LastPlayCurrent` 资源（本次解析结果的状态/断言面） |
| 4 | 会话侧 | `src/pie.rs`：`PieSession` 增 `scene_overrides`/`temp_copies`；`PendingSpawn` 增 `scene_override`（build 完成路径 `poll_builds` 同步穿引）；`spawn_instance` 增参并设 `JACKDAW_PIE_SCENE` env（用 runtime crate 的常量，单一真理源）；`launch_instance_with_override`（override 存在 ⇒ 调用方已应用保存策略，跳过 `save_before_play` 门）；`record_scene_override` 单一收口（去重共享副本）；`cleanup_session_on_stop` 删 temp 副本 + 清 overrides；`PieSession::drop` 同删；`wire_pie_button` 主按钮 → `PiePlayCurrentOp`；`add_to_extension` 注册新 op + `bind_operator_host F5`；`project.toggle_save_before_play` 升级三态循环（保留旧 id）+ 新 op `project.set_save_before_play mode=save|ask|play_unsaved_copy` |
| 5 | UI | `src/pie_menu.rs`：下拉首组「Play Startup Scene」行（Play 图标 + 分隔线，点击走原 `pie.play` 链）+ 既有 run 实例列表；`src/project_select.rs`：项目打开时调 `sweep_orphan_pie_copies`（紧邻 T04 孤儿 tmp 清扫） |

`pie.play` 语义零改动（小定案：启动场景运行，向后兼容）。

## 二、🔴 红 → 绿

### N1（Play 跑的总是 scene.bsn 不是当前场景）

- 红证（旧码，`git stash` 复演）：`cargo test -p jackdaw_runtime --test pie_scene_override`
  → **0 passed / 3 failed**。核心 panic：`the first root plays the override: ["Anchor", "Second", "scene", "second"]`
  —— 旧 runtime 无视 `JACKDAW_PIE_SCENE`，spawn 的是游戏自决场景（Anchor）的实体。
  日志：`loop/t06t1_red_runtime.log`。
- 绿（新码）：同命令 → **4 passed / 0 failed**（3 个行为用例 + `pie_scene_or` 单测）。
  日志：`loop/t06t1_green_runtime_final.log`。

### N2（untitled 两向都错：脏=硬拒绝 / 干净=静默错场景）

- 红证（旧码，探针 `tests/play_current_red.rs`，stash 复演）：旧码上
  `run_op_clause "pie.play_current"` → `UnknownId("pie.play_current")`，
  **0 passed / 1 failed**——「运行当前场景」这个概念在旧编辑器侧不存在。
  日志：`loop/t06t1_red_probe_old_code.log`。
- 绿（新码）：探针 → **1 passed / 0 failed**（脏 untitled 经 play_current 解析成功、
  `.jackdaw-pie/current-untitled-1-<pid>.bsn` 副本落盘、含未保存编辑、tab 仍脏）。
  日志：`loop/t06t1_red_probe_final.log`。探针按设计是一次性红证载体，红绿数字归档后已删除，常驻版本为 `tests/guards/play_current_scene.rs`。

## 三、门禁（quick 四门亲跑 + 日志全文复核）

| 门 | 命令 | 结果 | 日志 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | PASS（0 diff；改动期间多轮 apply 后终检覆盖归档） | `loop/t06t1_fmt.log` |
| Lint | `cargo clippy --workspace -- -D warnings` | PASS；全文复核仅既有工具链噪音（rust-lld `-fuse-ld` ×1、build script duplicate ×4），无 error、无新增 warning | `loop/t06t1_clippy.log` |
| 单测 | `cargo test --workspace --lib` | 全绿：**56 crates / 2893 passed / 0 failed**（主编译器 crate 1155，含 pie_current 8、stop_cleanup 5） | `loop/t06t1_lib.log` |
| 任务相关集成 | `cargo test -p jackdaw --test guards`（全量）+ `--test pie_scene_override` + `--test play_current_red`（终跑后按设计删除） | guards 全量 **192 passed / 0 failed**（play_current_scene 12 用例含内：Save 保存链 / Copy 副本+盘上不变 / clean-named / untitled×两策略 / Ask 三答案+cancel+untitled 不弹 / prefab 回落 / 全 prefab 拒绝 / 后台 tab 状态）；runtime **4/4**；探针 **1/1** | `loop/t06t1_guards_full.log`、`loop/t06t1_green_runtime_final.log`、`loop/t06t1_red_probe_final.log` |

**门禁过程中的一个真实问题与修复**：新增 12 个 guards 用例并行时，既有计时测试 `session_journal::the_journal_write_costs_no_more_than_five_milliseconds` 连续三次全量失败（单跑恒过、main 旧码基线全量 180/0 过——`loop/t06t1_guards_main_baseline.log`），定性为本模块 12 路重型集成测试（编辑器全启 + 场景加载 + emit/写盘）并行饱和 IO、把 5ms 计时预算挤爆。修复：模块内共享锁串行化（`PLAY_CURRENT_LOCK`，guard 文件头注明原因），串行后全量 192/0 稳定通过。这属于新测试对既有脆弱计时测试的礼貌让路，非功能问题。

## 四、决策 6 真机验证结论（点前缀路径可加载性）

**结论：A 方案验证通过，无需回落 B（保留目录 + walk 显式跳过）。**

真机用例 A（untitled 场景，其唯一可能加载路径就是点前缀副本）：

```
scene.new + entity.add.cube → pie.play_current → pie running
temp copy: <my-game>/assets/.jackdaw-pie/current-untitled-1-<pid>.bsn
切 Live 视图后 scene_tree 投影: count=3 names=[current-untitled-1-31884, Cube, Directional Light]
```

—— 游戏（bevy AssetServer）成功从 `.jackdaw-pie/` 点前缀目录加载了副本并以它为场景根（root 名即副本 stem）。且 my-game 是**未做任何源码改动的存量工程**（其 `spawn_scene` 仍硬编码 `scene.bsn`），同时实证了决策 1-A「存量工程零改动受益」。

## 五、真机验证（loop/qa/t06-play-current.ps1，最终 run6 = `T06T1_PLAY_CURRENT_LIVE_PASS`）

证据口径（T1 级，完整对账工具 `jackdaw/pie` 归 T3）：
**编辑器启动日志**（override 行：哪个场景、named 还是 unsaved-copy）+ **Live 投影流 scene_tree**
（游戏世界实体的结构化对账，不依赖相机/渲染）+ 截图留档。四用例：

| 用例 | 断言要点 | 结果 |
|---|---|---|
| A untitled → temp 副本 | play_current 解析不拒绝；副本存在且含编辑；**Live 树 = [current-untitled-1-\<pid\>, Cube, Directional Light]（游戏加载的就是副本）**；stop 后副本删除 | 全过 |
| B named（pie-probe.bsn，非 scene.bsn）→ 路径 override | 编辑器日志 `launched with scene override 'pie-probe.bsn'`；无副本；**Live 树 = [pie-probe, Cube, Directional Light]**；对照 scene.bsn 实体集（用例 D count=24）完全不同 | 全过 |
| C 三态 Ask | 对话框出现且三按钮齐（Save / Play Unsaved Copy / Cancel）；点 Play Unsaved Copy → 副本生成、**盘上文件 hash 不变**、override 计数 +1 | 全过 |
| D 启动场景对照（pie.play） | **无新 override 行**；Live 树 count=24（= scene.bsn 大场景）——证明旧语义零回归 | 全过 |

截图留档：`loop/t06t1-live/{A-playing-untitled,B-playing-named,C-ask-copy,D-startup-control}.png`。

多实例口径：文件名含编辑器 pid 防互踩（`current-<display>-<pid>.bsn`），同会话多实例共享一份副本只读（`record_scene_override` 去重登记，单测钉住）；完整多实例矩阵 #10 归 T3。

## 六、规格验收清单对照（T1 节）

- [x] headless（runtime）：env override → 换把 → spawn 的实体来自 b 文档（内容断言）；无 env 回归锚点；多 root 只换首个 —— `pie_scene_override.rs`
- [x] headless（editor）：dirty named + Save → 保存走完（tab clean、盘上新内容）且 override=相对路径；PlayUnsavedCopy → tab 仍脏、盘上不变、副本与 emit 同源；untitled 两策略均可运行（N2 红→绿先落红证）—— `play_current_scene.rs`
- [x] headless：active=prefab → 回落最近 scene tab；全 prefab → 拒绝（无解析结果、零写入）—— 同上
- [x] headless：stop 清理（构造副本 → cleanup → 文件不存在；容忍已消失副本）—— `pie.rs stop_cleanup_tests` 新增 3 例
- [x] headless：孤儿清理（预置 `current-*-*.bsn` → sweep 清除、非 current-* 不动、二次 sweep 空操作）—— `pie_current.rs` 单测；启动接入点 = 项目打开链（project_select）
- [x] headless：旧布尔迁移（true→Save / false→PlayUnsavedCopy；整段 settings.json 经 `load_section` 读；snake_case 枚举 round-trip；未知值拒绝）—— `pie_current.rs` 单测 4 例
- [x] 真机（BRP 链）：非 scene.bsn 场景 → play_current → running → **投影流实体对账**（Live 树 name 集 = 该场景实体集，非 scene.bsn）→ stop → 副本清理 —— run6 四用例
- 备注：方案里「断言 scene_override 指向该场景」的真机断言面，T1 阶段由编辑器启动日志行（`record_scene_override` 的 info!）承担，结构化 `jackdaw/pie` BRP 归 T3。

## 七、偏差与记档

1. **`jackdaw/wait until=pie_stopped` 的 `seen_active` 竞态（既有边界，非本改动引入）**：stop 若在 wait 首次轮询前完成（我们的 stop 链同帧内结束），`seen_active` 永为 false，wait 永不满足且表现为 HTTP 层超时。QA 脚本改轮询 `jackdaw/status` 的 `pie` 字段（诊断证明 `"pie":"stopped"` 一切正常）。→ 建议 T3 的 `jackdaw/pie` 工具设计时消除该竞态。
2. **`pie.stop` 的 avail 门竞态（既有）**：children 已有但子进程未 connected（PlayState 仍 Stopped）时 stop 返回 cancelled；QA 重试规避。与 Y34/N6（T2 优雅停止）近邻，T2 一并收口。
3. **temp 副本不含 terrain sidecar**：副本仅 emit 文档文本（规格处方）；带地形的未保存场景在 play 会话里地形回落到盘上旧 sidecar（如有）。已知限制，book 注记归 T3。
4. **孤儿清扫为全清**：第二个编辑器打开同一项目会清掉第一个编辑器正在使用的副本（运行中游戏已将副本载入内存，仅 reload 场景受影响）。代码注释 + 本报告记档；与 QA 矩阵 #9 的完整核对归 T3。
5. **Reload（current 模式）不重算 override**：`handle_reload` 维持启动语义（override 随 stop 丢弃）。矩阵 #8 明确归 T3。
6. **启动场景路径的三态语义**（规格未细说）：Save/Ask → 照旧保存（Ask 无对话框、保守取 Save）；PlayUnsavedCopy → 不保存（忠实旧 `false`）。current 模式不受此影响（untitled 恒走副本）。`save_before_play` 门函数 doc 已写明。
7. **`project.toggle_save_before_play` 保留旧 id**，实现为三态循环（Save→Ask→PlayUnsavedCopy→Save）；显式设置走新 op `project.set_save_before_play mode=`（规格 e) 的「保留旧 id 兼容 + 并列新 op」组合）。
8. **F5 键位**：经 `bind_operator_host` 进 DefaultKeymap（与 viewport_2d 的 Home/Shift+R 同构）；未做真机键盘注入验证（口径：注册机制代码路径同构 + guards 层 op 可达）。
9. **模板毕业的验证口径**：`pie_scene_or` 单测 + 模板用法与 helper 签名核对（`String → AssetServer::load`）；仓库无模板编译级测试，未 scaffold 新工程实编（成本权衡）。
10. 真机运行后清理：`my-game/assets/pie-probe.bsn`（QA 造的探针场景）已删除，`.jackdaw-pie/` 目录为空（点前缀目录留存无害，walk 跳过）。
11. **Stop 时 ChildOf 悬空 WARN**（revert_preview despawn 时序，一帧内自愈）——方案 B 节「❓selection 还原」的邻居现象，归 T2 实测定性。

## 八、buglist

无打钩项（Y34/W26/W17 归 T2，方案原定）。

## 九、提交

- 分支：`loop/t06-play`（自 `213e3370`）
- 文件：`crates/jackdaw_runtime/src/lib.rs`、`crates/jackdaw_runtime/tests/pie_scene_override.rs`（新）、`crates/jackdaw_scaffold/templates/game/src/lib.rs.template`、`src/lib.rs`、`src/pie.rs`、`src/pie_current.rs`（新）、`src/pie_menu.rs`、`src/project_select.rs`、`tests/guards/main.rs`、`tests/guards/play_current_scene.rs`（新）
- 提交信息：`Run the current scene through the PIE scene channel`
- 哈希：`1bf371c1`（父提交 `213e3370` = main 闭环点；未推远端）
- loop/ 与 buglist.md 不入库；探针 `tests/play_current_red.rs` 红证归档后删除。
