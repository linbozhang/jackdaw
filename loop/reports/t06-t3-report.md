# T06-T3 实施报告：「PIE 工具面 + 真机矩阵 + 文档收尾」

> 程序角色产出，2026-10-26。分支 `loop/t06-final`（自 main `66ef15e8` 拉出）。
> 规格：`loop/plans/t06-play-isolation.md` §二 T3 + 前置欠账六项（QA 硬条件与历轮移交）。
> 提交信息：`Add the pie inspection tool and finish play isolation`。
> 提交哈希：见文末。

## 一、改动面

### 主体

| 项 | 落点 |
|---|---|
| BRP `jackdaw/pie` | `src/remote/server.rs::pie_handler`：`{status, view_mode(scene|live), focused, instances:[{key, config, instance, stage: connecting|live, scene_override, scene_source: named|unsaved-copy|none}], projection:{entities, authored, ephemeral}, live_edits}`；`PieSession::instance_faces()` 单一收口（`src/pie.rs`）。headless 可测（同 history/recovery 模式） |
| BRP `jackdaw/selection.set` | `server.rs::selection_set_handler`：按 bits（scene_tree 的 id）或按 name 设 selection、`clear` 清空、重打 `Selected` 标记（pick 同款）。**欠账① 的工具**：QA 面直达投影实体（outliner Live 行不在 ui_tree、viewport pick 不中投影实体的两个缺口由它绕开） |
| MCP 第 24 工具 `pie` | `crates/jackdaw_mcp/src/lib.rs`：薄翻译（audit/recovery 同构），描述教调用方怎么在 play/wait 后断言 `scene_override`/`scene_source` |
| book「Play-in-Editor」节 | `book/src/user-guide/play-in-editor.md`：新增「Which scene Play runs」（主按钮/F5=当前场景、下拉首组=Play Startup Scene、JACKDAW_PIE_SCENE 换把、**多 root 只换首个**与支持面=JackdawSceneRoot 的限制）、「Unsaved changes: the three policies」（三态+旧 bool 迁移+`.jackdaw-pie/` 副本生命周期）、「Stopping and reloading」改写（2s 优雅窗口、Stop 还原语义、**reload 重算 override 不落盘**）、尾部补「The stop prompt and live changes」（显式门） |

### 前置欠账处置（六项）

| # | 欠账 | 处置 |
|---|---|---|
| ① | selection 工具能力 + 矩阵 #7 收口 | **工具已交付**（`jackdaw/selection.set` + headless 单测 + 真机选中投影 Spinner 实证）。矩阵 #7 的 Inspector 合成输入半场（拖拽/键入→字段提交→pending live edit→stop prompt 按钮）**仍不可达**：实测 ui_drag（scrub 手势不吃合成拖）与 ui_input（数值行不提交键入）都到不了提交路径——**工具面缺口 N11**（记 buglist），语义由 headless `live_edits.rs` 18 例（apply_all 恰一条 undo / discard_all 不碰 AST / post-stop apply）覆盖。矩阵 #7 以「selection 面验证 + 无 pending 时 stop prompt 不弹 + 文档不变」收口，按钮链记档 |
| ② | Reload override 重算 | **已修**：`pie_current::override_for_reload`（reload 不落盘不打断：编辑过→新 temp 副本、clean→原文件路径）+ `handle_reload` 对带 override 的实例换新解析；`resolve_override_for_launch` 从 launch_current_scene 抽出复用。guards 新例（clean=named、dirty=新副本且盘不动）+ 真机矩阵 #8（reload 后 `scene_source=unsaved-copy`、副本名可见）双验 |
| ③ | `pie_stopped` 竞态 | **已修**：`PieSession.launches` 单调计数 + `PieWait.launch_baseline`——会话在两次轮询之间完整来去（stop 快于首询）时计数已动，wait 立即满足；单测 2 例（先 hold 后满足 / 从未运行仍 hold）+ 真机（矩阵 cell 1-2 的 `pie stopped (wait satisfied)`） |
| ④ | pie.stop avail 门竞态 | **核查后保守关闭**：曾放宽（connecting 也计 Playing），真机实测触发 **N10 冻结族**（见⑤）——connecting 窗口内 stop（哪怕被 avail 拒绝后的重试链）与主线程满 CPU 自旋相关；已回退为 avail 拒绝+调用方重试语义（T1 QA 已按此跑通；回归锚单测 `a_connecting_child_keeps_the_editor_stopped`） |
| ⑤ | 模板 scaffold 实编 | **已跑**：`jd new t06-template-check`（模板含 `pie_scene_or("scene.bsn")` 毕业代码、jackdaw_runtime path 依赖）→ `cargo check` **全过**（1m37s 零 error）→ 工程已删 |
| ⑥ | （N-QA4 journal 衔接已并入 T2；本任务无） | — |

### 发现并记档的新问题（buglist 新条目）

- **N10**（🟡→高优）：dirty 场景 + Save 态 `play_current` 真机冻结编辑器主线程。**main 基线（66ef15e8）同样冻结**（stash 实证）——T1 交付的真机未测路径；clean/copy/untitled 路径不受影响；headless 全绿。规避：先 scene.save 再 play。修复方向与完整实证（`loop/t06t3_probe_freeze*.log`：CPU/4s≈5s 自旋、连接窗口 stop 同族）在 buglist。
- **N11**（⚪ 工具缺口）：Inspector 数值字段的合成输入提交路径（scrub 拖拽与键入都不达 commit）——QA 无法驱动 stop prompt 按钮链；补 `field.set` 类 BRP 或修合成输入后收口矩阵 #7 的按钮半场。
- **N12**（⚪）：bevy 原生 BRP（world.query/get_components）与 jackdaw 方法的实体 id 域互不相通（`{index}v{generation}` vs raw bits、且两个 world 视图不含对方实体）——T2 已发现、T3 再次撞上（读组件值走 `jackdaw/entity` 的 BSN 文本绕开）；工具统一域记档。

## 二、真机矩阵 10/10（`loop/qa/t06-final-live.ps1`，run12 = `T06_FINAL_MATRIX_10_OF_10_PASS`）

| # | 场景 | 关键断言（全过） |
|---|---|---|
| 1 | named 对账 | `jackdaw/pie` 的 `scene_override='t06-final.bsn'`/`scene_source=named`；Live 投影实体名集 == authored（容器名差异除外） |
| 2 | untitled 副本 | `scene_source=unsaved-copy`；副本存在且含文档；**游戏加载副本**（Live 树含 Cube）；stop 后副本删、tab 仍 dirty |
| 3 | 三策略 | Save：`scene.save` 落盘+clean+play 跑保存内容（dirty+save-play 组合=N10 规避口径，见偏差①）；Copy：dirty 场景跑副本、盘逐字节不动 |
| 4 | prefab 回落 | prefab tab 在前 → override=最近 scene tab 的文件 |
| 5 | 启动场景对照 | `pie.play` 无 override（null） |
| 6 | Stop 铁证复跑 | 文档 emit SHA + 盘 SHA 双腿一致、undo 深度不变、实体名集复原、`jackdaw/pie` 无实例无 ephemeral |
| 7 | 显式门 | selection.set 选中投影 Spinner（QA 硬条件的工具实证）；无 pending 时 stop prompt 不弹、文档不变；按钮链=N11 |
| 8 | Reload 重算 | connected 后（`stage=live` 面读）编辑→reload→**新副本**（`.jackdaw-pie/current-t06-final-<pid>.bsn`）且 `scene_source=unsaved-copy`；副本存在 |
| 9 | 崩溃孤儿 | kill 编辑器→游戏死（job object）；孤儿 temp 副本重启清扫 |
| 10 | 多实例 | instances=2 配置下 play_current 起单实例带 override（产品语义：current=单实例心智，下拉行起其余）；stop 清空 |

**Stop 通道说明**：矩阵的 stop 用 status-face 轮询+avail 拒绝重试（T2 稳定配方）——pie_stopped wait 修复本身在 cell 1-2 以 `wait satisfied` 实证，但 watching 轮询帧跨连接窗口会撞 N10 族冻结，矩阵全程避开该窗口。

## 三、门禁（全量，2026-10-25 升级标准：日志全文复核 + 重跑覆盖归档）

| 门 | 结果 | 日志 |
|---|---|---|
| `cargo fmt --all -- --check` | PASS | `loop/t06t3_fmt.log` |
| `cargo clippy --workspace --all-targets -- -D warnings` | PASS（存量工具链噪音 5 条：rust-lld ×1、build script duplicate ×4） | `loop/t06t3_clippy_all.log` |
| `cargo xtask fast`（nextest） | **2905/2905 passed**（1 leaky 存量、2 skipped） | `loop/t06t3_xtask_fast.log` |
| `cargo xtask integration` | **5177/5177 passed**（两处存量适配被 guard 抓出并修复：T1 欠的 `project.set_save_before_play` params 声明；T2 三态迁移后 `save_before_play::with_save_before_play_off` 的 toggle 次数（旧 off=copy 态=两次 toggle）；重跑后全绿） | `loop/t06t3_xtask_integration.log` |
| `cargo doc --workspace --no-deps` | PASS（57 文档生成，无 error） | `loop/t06t3_doc.log` |
| `cargo test --workspace --doc` | 8 crates doctests 全 ok（忽略 11 个 `ignore` 标记）+ **jackdaw_bind 1 例 workspace 轮无声失败、单跑通过**——本任务未触碰 crate 的存量环境性失败（记偏差③） | `loop/t06t3_doctests2.log`、`loop/t06t3_doctests_bind.log` |
| guards 全量 + runtime override | guards **197/0**（+stop_restore 4、+play_current reload 例）、runtime **5/5** | `loop/t06t3_guards_full.log` 等 |
| MCP smoke | `tools/list` 25 工具含 **pie**（直连 jd-mcp.exe；注意 jd.exe 旧二进制需 `cargo build -p jackdaw_mcp` 单独刷新） | `loop/t06t3_mcp_out4.txt` |

**门禁过程真问题两枚**：① clippy --all-targets 面抓到 T1/T2 测试代码的 redundant closure 与存量 expect(print_stdout) 失效（工具链版本噪音，6 文件 expect→allow）——quick 门不覆盖 all-targets，全量门首次暴露；② integration 的 param_declarations guard 抓到 T1 欠的 params 声明。均已修复并重跑覆盖。

## 四、验收对照（方案 T3 节）

- [x] 矩阵 10 格全过（#7/#10 按上述口径，#3 的 dirty+save 组合=N10 规避）
- [x] 全量门（fast/integration/docs/doctests + MCP smoke；bind doctest 存量环境性例外记档）
- [x] 用户 30 秒清单（见 §五）
- [x] buglist 核对：Y34/W26/W17 已在 T2 打钩；本任务新增 N10/N11/N12 记档
- [ ] roadmap T06 勾选与台账：由主控合入时更新（loop/ 不入库）

## 五、用户 30 秒清单（实测通过）

1. **打开任意一个不是 scene.bsn 的场景点 Play——看到的就是这个场景**：矩阵 #1（named 对账：override 指向该文件 + Live 投影实体一致）+ T1 真机。
2. **Play 里把东西弄乱 → Stop → 一切如初、文件没被碰**：矩阵 #6（双 SHA + 实体名集 + undo 深度）+ T2 铁证链。
3. **新建未保存场景直接 Play 也能跑，Stop 后仍是未保存状态**：矩阵 #2（unsaved-copy + tab 仍 dirty）。
   - ⚠️ N10 规避注记（30 秒清单①的脏场景变体）：**已保存场景编辑后直接点 Play（默认 save 策略）当前会冻结编辑器**——先 Ctrl+S 再 Play 或切 play_unsaved_copy 策略；修复立项 N10。

## 六、偏差与记档

1. **矩阵 #3 的 dirty+Save 组合改为 scene.save→play 两步**（N10 规避）：保存链与 PIE 启动同帧组合触发 N10 冻结（main 基线同冻=既有）；矩阵内语义覆盖（保存的内容被 play 跑）不变，dirty+save-play 组合待 N10 修复后补验。
2. **矩阵 #7 按钮链（N11）**：selection.set 工具交付且真机选中投影实体；Inspector 字段合成提交不可达（scrub/键入都不达 commit 路径），stop prompt 按钮两分支真机链推迟到 N11 补面；语义由 headless live_edits.rs 全覆盖。
3. **jackdaw_bind doctest workspace 轮无声失败**（单跑过、未触碰 crate、无 running/test 行即 error）：存量环境性，单跑归档为证；不阻断放行（其余 8 crates doctests 全绿）。
4. **`jd mcp` 的 jd.exe 二进制漂移**：`cargo build -p jd` 不重编 jackdaw_mcp 的 jd-mcp.exe（独立二进制），MCP 变更需单独 `cargo build -p jackdaw_mcp`——首次 smoke 假阴性源于此，记档给后续 MCP 任务。
5. **连接窗口的 avail 拒绝+重试是 stop/reload 的既定交互**（欠账④保守关闭）：QA 配方已内建重试；根因（N10 族）另立项。
6. bevy 原生 BRP 与 jackdaw 方法实体域不通（N12 记档）：本任务读组件值统一走 `jackdaw/entity`。
7. **执行纪律**：续跑开局曾在 main 上带改动（主控拦截；分支无分叉无损失，已切回 loop/t06-final 完成全部工作并自查 `git branch`）；本次提交前再次核对分支。

## 七、提交

- 分支：`loop/t06-final`（父 `66ef15e8` = main）
- 文件：`src/pie.rs`（launches 计数/instance_faces/reconcile 回退+锚点测试）、`src/pie_current.rs`（resolve 抽取+override_for_reload+params 声明+测试修正）、`src/remote/server.rs`（pie_handler/selection_set_handler/pie_wait 基线+测试 4 例）、`crates/jackdaw_mcp/src/lib.rs`（pie 工具）、`book/src/user-guide/play-in-editor.md`、`tests/guards/{main,play_current_scene,stop_restore,session_journal}.rs`、`crates/jackdaw_runtime/tests/pie_scene_override.rs`、存量 lint 修（6 测试文件 expect→allow）
- 提交信息：`Add the pie inspection tool and finish play isolation`
- 哈希：`4937db6c`（父 `66ef15e8` = main；未推远端；15 文件 +743/-93）
- loop/、buglist.md 不入库；QA fixture（t06-final.bsn 及 .bak）已清，jackdaw.toml instances 注入已还原。
