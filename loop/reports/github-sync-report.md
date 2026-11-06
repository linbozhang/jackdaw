# GitHub 同步报告（github/main → 本地 main）

> 用户指令（2026-11-06）：不推 GitHub；把 `github.com/jbuehler23/jackdaw` 其他人的最新提交
> 同步进本地 main；巡检自动化不建。远端以 `github` 名挂载（origin 保持指 Mac 1 本地 bare
> 路径不动；本机该路径不存在，fetch/push 均不经过它）。

## 一、规模与弧线

- 分叉：merge-base `5c3ba8ea`；GitHub 领先 **155 提交**，本地领先 **323 提交**（Loop 全部）。
- 上游主体：编辑器拆 crate（`editor/jackdaw_editor_core`+remote/modelling/terrain/tile/
  animation/launcher 七件套 #761-#769，含存盘类型路径改名机制 `jackdaw_bsn::migrate`）、
  Play 模块重做（#772-#788，含供载未存盘 sidecar/场景 #787/#785、组件编辑同步到运行游戏
  #776）、紧凑写场景（#789）、CI sccache（#786）。
- **合并提交 `e0066863`**：89 个冲突全部解决后由程序 agent 提交（改名检测把本地语义重放到
  新 crate 路径；fork patch/avian 集成原样保留）。该 agent 死于编译修复循环中途。
- **编译修复+门禁收官（主控亲自接手）**：完成 editor_core 的 Loop 模块注册收尾、修复 guards
  32 个失败至全绿（弧线见第三节），四门全绿后随本次 commit 入库。

## 二、门禁终值（日志全文复核制，归档 `loop/github-sync/`）

| 门 | 结果 | 对账 |
|---|---|---|
| fmt | EXIT=0（`cargo fmt --all` 修 1 处空行后复检） | gate4-fmt 复检绿 |
| clippy -D warnings | EXIT=0 全文无诊断 | gate4-clippy.log |
| libtests | EXIT=0，**3860 passed / 70 二进制 / 0 FAILED** | 本地基线 3122+上游 +738；二进制 59→70（crate 拆分新增 lib 测试目标） |
| guards | EXIT=0，**375 passed / 0 failed** | 原 248 本地锚全存活 + 上游并入主题测试；快门重校准为 `--test guards`（见四.3） |
| build --workspace | EXIT=0（2m09s 增量） | build-final.log |

fork 锚点：bevy 仍取自本地 fork（lock 无 registry/git bevy 来源）；fork HEAD `f83d83b41`、
pinned-rev `c9c397ba` 未动。

## 三、guards 32→0 修复清单（逐族）

1. **A 族 physics_triggers×4（根因=合并丢注册）**：上游拆 crate 时
   `register_extension::<jackdaw_physics::PhysicsExtension>()`（旧 src/lib.rs:734）丢失，
   avian 不再入编辑器世界（`Time<Physics>` 缺失）。修复=editor_core 补依赖+原样恢复注册块。
2. **D 族 recovery×3（误合并）**：`recovery_dialog.rs:571` 的 registry 读取被改成
   `doc.world`（文档世界无 AppTypeRegistry），本地惯用法=主 world。改回。
3. **C/G 族普查×4（声明缺失）**：上游 `clip.delete_keyframes`/`clip.paste_keyframes`
   自推历史但漏 `allows_undo=false`（同文件 timeline.* 都有）→补声明+注释；
   `game.export`（本地 op）漏 `writes_disk`、上游 `project.set_save_before_play` 漏
   `writes_disk` →补。
4. **F 族 keyframe×5（R1 语义被回退）**：合并把 `DespawnKeyframeCmd` 退化为 bare
   despawn/裸 respawn——本地 R1 语义（关键帧操作必须走文档 AST：`despawn_scene_entity`+
   `register_entity_in_ast`）整段丢失，残留 AST 节点会被快照 undo 复活。两处原样恢复；
   `SpawnKeyframeCmd`（粘贴创建）同病灶同修。
5. **E 族 scaffold×4（目标架构失配）**：上游类型路径拼写 `editor::guards::…` 来自其
   单测试二进制架构；接手 agent 的 `[[test]] guards` 使 crate 名=guards。拼写全部改
   `guards::…`。
6. **B 族 play_overlay×9（⚠️ 最深，见四.2）**：接手 agent 为消解本地/上游两个同名
   `TilemapLayer` 把上游版改名 `TilemapGridLayer`——**改掉了存盘类型路径**，所有已存
   tilemap 场景 layers 无法 apply（烟枪 warn：`the document's value is not a
   TilemapGridLayer; dropping it`→`the map names 0`）。修复=撤销改名恢复
   `tilemap::TilemapLayer` 存盘路径，撞名改用「不重导出」消解（本地版留根名、上游版走
   模块路径，lib.rs 注记）。
7. **editor_remote×2（契约碰撞）**：chrome 拒绝——上游改为直接拒绝（比本地空树成功更
   严格，意图同为不泄漏），测试适配；compact warnings——见四.1。

## 四、主控裁定记录（语义分歧处置）

1. **compact 应答的 warnings 键（采纳上游）**：上游 compact 模式省略空 `warnings`
   数组；本地旧契约恒含 `[]`。两者在同一测试文件内直接对撞。**裁定=采纳上游**（贴近
   演进方，字段省略对忽略方无害）；本地 `warnings_do_not_carry_over` 断言改为
   「键缺席或为空」。**影响记档：既有 Loop QA 脚本若读 `.warnings` 需容忍 null**
   （历史 QA 证据不受影响；未来 QA 知悉）。
2. **Tilemap 双类型共存（撤销误改名）**：本地 per-layer `TilemapLayer`（根路径）与上游
   consolidated `tilemap::TilemapLayer`（模块路径）并存，后者保住上游存盘路径。
3. **测试目标架构（保留 Loop 单目标）**：上游 `tests/editor/main.rs` 单二进制含全部主题
   （crate=editor）；在合并树会引爆 12 处跨主题编译冲突（重复定义/TilemapLayer 改名 E0308
   等）。裁定=保留 `[[test]] guards`（crate=guards）+改拼写，`tests/editor/main.rs` 留树
   未启用。快门口径从 `--test guards`（248）重校准为 `--test guards`（375，含上游主题）。
4. **chrome 拒绝语义（采纳上游）**：见三.7。

## 五、遗留 / 待办

- **A28（stage 套件 7 用例本机失败）需重验**：合并前失败形态基于旧目标布局；上游把
  stage 并入 editor 目标后需在本机重跑（`--test editor stage::`）确认是环境缺口还是已消失。
- `tests/editor/main.rs` 留树未启用：未来若想回归上游单二进制架构，需先解决 12 处跨主题
  冲突（清单见 gate 日志 editor-target 编译轮）。
- 上游 155 提交中的行为变更（#776 组件同步、#789 紧凑写盘、#787 供载）与本地 Loop 语义
  在合并中**并存**；T25 live 路由等锚全部存活（guards 375 全绿背书）。深度行为级回归
  （真机 PIE 端到端）留下一轮 Loop 任务抽验。
- 不推任何远端（用户指令）；本地 main 领先 origin 57+ 提交。
- 巡检自动化：按用户指令不建。

## 六、弧线账

| 步骤 | 谁 | 结果 |
|---|---|---|
| fetch+评估+试合并 | 主控 | 89 冲突定型，保险分支 `main-pre-github-sync` |
| 89 冲突解决+合并提交 | 程序 agent A（死于编译修复循环中途） | `e0066863` |
| 编译修复循环 | 程序 agent B（死于门禁中途，留 13 模块注册+多轮 check 日志） | build 绿 |
| guards 32→0+四门收官+报告 | 主控亲自 | 本次 commit |
