# R5 QA 验收报告：空地形上点 Erode 直接 panic

> 2026-11-06，QA agent。待验对象：分支 `loop/bug-r5-erode-empty-terrain` @ `740c48b4`
> （自 main `958dfa28` 拉）。方案书：`loop/plans/bug-r5-erode-empty-terrain.md`。
> 程序报告：`loop/reports/bug-r5-report.md`。
> **总判定：PASS。不合入、不打勾、不动 buglist/roadmap/progress——收尾归主控。**

## 一、逐项判定总表

| # | 验收项 | 判定 | 关键证据 |
|---|---|---|---|
| 1 | diff 面复核 | **PASS** | `git diff main..loop/bug-r5-erode-empty-terrain --stat` 亲跑：改动恰为 `src/terrain/ops.rs`（+65）+ `crates/jackdaw_terrain/src/erosion.rs`（+59）+ `loop/bug-r5/` 五份日志 + 程序报告，与程序自报完全一致；未触碰 panel/generate/quantize/brush/UI 机制/buglist/roadmap/progress |
| 2 | 门禁三连亲跑 | **PASS** | QA 亲跑日志归档 `loop/bug-r5-qa/`：fmt 干净（`qa-gates-fmt.log`，exit 0 无 diff）；clippy 全 workspace `-D warnings` 干净（`qa-gates-clippy.log`，Finished 无诊断，exit 0）；test **3098 passed / 0 failed，59 个测试二进制**（`qa-gates-test.log` 逐行复核：59 条 `test result: ok`、0 条 FAILED、无 error 行，`TEST-EXIT=0`），3098 = 基线 3095 + 3，拆账 kernel 2 + op 1，三条新测试名在册（行 1236/3164/3165） |
| 3 | 红绿独立复核 | **PASS** | 方法 a)（临时还原守卫复红）：QA 亲手摘除两处守卫行 → 双腿定向测试 panic 复现（`qa-red.log`，panic 原文与票面逐字一致）→ 从备份还原 → 复绿（`qa-green.log`，kernel 4/4、op 4/4，exit 0）。还原后 `git diff` 确认工作区只剩与任务无关的 `.zcode/config.json` |
| 4 | 真机腿 | **PASS** | 详见第三节。断言①②③全部取证；Form A（真点面板 Erode 按钮）+ Form B（operator）双形态；截图含 toast 实拍 |
| 5 | QA 报告 | **PASS** | 本文件 |
| 6 | QA 证据提交 | **PASS** | `loop/bug-r5-qa/` 全量归档 + 本报告在该分支 commit；fixture 临时改动全部还原（截图已移出、PNG 残留清零、`git status tests/fixtures/` 干净）；杀编辑器进程、清 /tmp 备份 |

辅助门禁：真机腿前重建编辑器二进制（旧二进制 13:20 早于修复 commit，stale）`cargo build --bin jackdaw` exit 0（`qa-build-binary.log`）。

## 二、红绿方法声明

**选方法 a)（亲跑复红），不采信程序 red.log 替代**；程序 red.log/green.log 另行全文复核，与本跑结论一致。

- 红态：手工摘除 `erosion.rs` kernel 早退（`if resolution < 4 { return; }` 及注释）与
  `ops.rs` op 拒绝分支，双腿定向测试均 **panic 于 `crates/jackdaw_terrain/src/erosion.rs:75:29:
  cannot sample empty range`**（与票面、程序红证逐字一致），exit code 101（`qa-red.log`）。
- 绿态：备份还原两文件后同两条定向测试全绿（kernel `erosion::` 4/4、op `terrain::ops::tests` 4/4，
  exit 0，`qa-green.log`）。
- 修前真机 panic 未在真机上直接复现（真机跑的是修复后二进制），红侧以「QA 亲跑测试级红证 +
  程序 red.log」构成；方案书明示 operator 形态与按钮形态效力等同，红腿以测试级复现为准，如实记档。

## 三、真机腿证据链

形态：macOS 本机，`JACKDAW_WINDOW_SIZE=1920x1080`，端口 15703，fixture
`tests/fixtures/bsn_game`（无 jackdaw.toml → setup 卡片 → 点 **"Open without setup"** 打开工程，
即 R4 QA 验证过的已知正常路径）。驱动脚本 `loop/bug-r5-qa/r5-live.sh`（bash+curl+jq，可复跑）。

流程：boot → 打开工程 → `call_operator entity.add.terrain`（Add 菜单同款 operator：spawn
未雕刻 Terrain（grid_resolution 0）并自动选中；undo 产生 "Add Terrain" 记录，作基线）→
等 `terrain.erode` 注册表 `available:true`（has_selected_terrain 通过的硬证据）→ **不生成、直接触发
Erode** → 断言。

### 断言①：编辑器不 panic 不退出 —— PASS

- 进程判定：`ASSERT1_ALIVE pid=91183`（触发后 `kill -0` 通过，三轮触发后依旧存活）。
- 日志判定：`live-editor.log` 全文 **0 处 `panicked`**（`grep -c panicked` = 0）。
- 对照票面：修前此处直接 panic（红证 panic 原文见第二节）；修后 `OPERATOR: terrain.erode`
  正常执行并走拒绝分支（日志行 48）。

### 断言②：toast 出现 —— PASS（结构 + 截图双证据；Form A/B 双形态均取到）

- 文案（ops.rs 拒绝分支原文）：
  `this terrain's grid is 0 vertices a side and erosion needs at least 4; nothing was eroded and no ground was changed`
- 结构证据（Form A，真点按钮）：`live-click-erode-formA.json` 显示
  `clicked:true, target:{entity:12884896804, kind:"button", operator:"terrain.erode"}`（点击点
  [1794.5,848] 在窗内）；紧随的全量 walk `live-walk-toast-formA.json` 命中文本节点：
  `{"entity":12884896169,"kind":"text","text":"this terrain's grid is 0 vertices a side and erosion
  needs at least 4; nothing was eroded and no ground was changed","rect":[618.0,1042.0,673.0,16]}`
  （窗口底部居中，toast 位置语义一致）。
- 视觉证据：`live-erode-toast-async.png` **实拍 toast 渲染在窗口底部居中**（红色错误 toast + 图标 +
  关闭钮，文案完整可读）；`live-erode-window.png` / `live-erode-toast-race.png` 存档编辑器面貌
  （Terrain 面板 Generation 页：Hydraulic Erosion 参数区 + 底部 Erode 按钮；Outliner 中 Terrain
  选中；状态栏 `Entity: Terrain`；视口空网格 = resolution 0 的未雕刻态）。
- Form B（operator `call_operator terrain.erode`）同样取到 toast（`ASSERT2_TOAST_FOUND (form B
  operator)`，walk `live-walk-after-erode2.json`）。
- 程序偏差 2（headless 无字体 toast 可能 no-op）在真机不成立：toast 真实出现（编辑器字体已载）。

### 断言③：无副作用 —— PASS

- undo 栈：Form A 前后 `jackdaw/history` 均为 `{"undo_len":1,"redo_len":0,"top":"Add Terrain"}`
  （`live-history-pre-erode-formA.json` / `live-history-post-erode-formA.json`）——拒绝面
  **零新 undo 记录**、top 不变；Form B 轮同值（`live-history-after-erode.json`）。
- 拒绝路径实证：编辑器日志三轮触发各留一条
  `WARN jackdaw::terrain::ops: this terrain's grid is 0 vertices a side and erosion needs at least 4; nothing was eroded and no ground was changed`（共 3 条）。
- heights/dirty 面：op 层单测 `eroding_an_empty_terrain_is_refused_without_undo_or_dirty`
  已断言（分辨率仍 0 / rebuild_all 不置位 / undo 栈空），headless 绿证在册；真机栈上以
  undo 栈 + warn 行为等效证据，如实记档。

## 四、偏差清单（如实记档，均不阻断）

1. **首轮 boot 踩环境情报 (a)**：脚本初版未点 setup 卡片的 "Open without setup"（工程未开、
   无 dock/无文档 face），首轮 `terrain.erode` 因 selection/文档未就绪被 dispatcher 以
   `cancelled` 拒绝（`live-erode-op.json`），该轮无断言价值、作废不采信；补驱对话框打开工程后
   干净重跑全部通过。脚本已固化该处理（`r5-live.sh` 的 `open_setup`），属环境流程问题、非修复缺陷。
2. **Generation tab 首次点击被 A20 阻断**：tab 按钮 rect [1882,69,89,22] 中心 x=1926.5 越过
   1920 窗缘（tab strip 溢出），ui_click 落空（点击回报 clicked:true 但 operator 未派发、UI 树
   逐字节不变）——即 R4 QA 已立票的 A20。按 MCP 优先原则改走结构化入口
   `call_operator terrain.panel.tab {tab:"generation"}` 切页（panel.rs doc 注释明示脚本与点击同
   路径），切页后 Erode 按钮完整在窗内（[1677,837,235,22]），Form A 点击成功。A20 归其票面处理。
3. **toast 抢拍前两次未中**：`jackdaw/screenshot` 为 watching 型且异步落盘慢于 toast 3s 存活期；
   第三帧（异步残页改名 `live-erode-toast-async.png`）实际抓到 toast，视觉证据成立。
4. **截图路径规则**：`jackdaw/screenshot` 的 path 只接受相对工程目录的路径（绝对路径报
   INVALID_PARAMS）；截图先落 fixture 再移出还原。
5. **`jackdaw/entity {"name":"Terrain"}` 瞬时误报**：add 后立即查询返回 "names no entity in this
   scene, or two"（`live-entity-terrain.json`），同轮稍后的 `status.selection` 与 operators
   `available:true` 均证实实体在且选中——以该两项为选中证据。
6. **程序遗留（归主控）**：方案书 `loop/plans/bug-r5-erode-empty-terrain.md` 未随分支 commit
   （untracked）。R4 惯例为收尾时主控 check in（9c80f5a8），QA 不代提交，提请主控合并时处理。
7. 工作区有一处与任务无关的既有改动 `.zcode/config.json`（QA 开工前已存在），未纳入提交。

## 五、状态

- 分支 `loop/bug-r5-erode-empty-terrain`：QA 证据（`loop/bug-r5-qa/` + 本报告）已 commit；
  **不合入 main**；buglist 打勾、roadmap/progress 未动——收尾归主控。
- 门禁/红绿/真机全部独立亲跑，日志全文复核，无静默降级。
