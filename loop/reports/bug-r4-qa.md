# R4 QA 报告：远程实体树父子解析与协议格式失配（buglist 🔴）

> 任务：T2 QA 腿（门禁亲跑 + 红绿独立复核 + 真机腿）。
> 待验对象：分支 `loop/bug-r4-remote-hierarchy` @ `efdf0430`（自 main `9c80f5a8` 拉）。
> 方案书：`loop/plans/bug-r4-remote-hierarchy.md`；程序报告：`loop/reports/bug-r4-report.md`。
> **总判定：PASS（放行合入）。本报告不执行合入、不打 buglist 勾，收尾归主控。**

## 1. 逐项判定表

| # | 验收项 | 判定 | 关键证据 |
|---|---|---|---|
| 1 | diff 面复核 | **PASS** | `git diff main..loop/bug-r4-remote-hierarchy --stat`：仅 `src/remote/entity_browser.rs`（+59/-1，1 行修复 + 58 行测试模块）+ 程序证据 5 份（`loop/bug-r4/{red,green,fmt,clippy,libtests}.log`）+ 程序报告 1 份；merge-base = main HEAD `9c80f5a8`，无越界提交。修复行亲读：`.and_then(jackdaw_pie_protocol::snapshot::entity_bits)`，与方案书 D1 形态一致，类型签名未变，未触协议 crate/producer/UI 树组件 |
| 2 | 门禁三连 QA 亲跑 | **PASS** | `loop/bug-r4-qa/qa-fmt.log`（exit 0，全文无 Diff 输出）；`qa-clippy.log`（exit 0，`Finished dev profile`，全文无真实 error/warning 行——grep 命中均为 crate 名含 error 子串：quick-error/proc-macro-error/thiserror）；`qa-libtests.log`（exit 0，全文复核：**59 个测试二进制（=基线 59）、3095 passed / 0 failed（=基线 3091+新增 4）**，jackdaw 主库 1277（=1273+4），无 FAILED/panicked 行，全部 `0 failed`） |
| 3 | 红绿独立复核（方法 a：独立复红） | **PASS** | 在分支工作树上用 Edit 把修复行临时还原为 `serde_json::Value::as_u64` → `cargo test -p jackdaw entity_browser`（`qa-red.log`）：文本/数组两形态 FAILED，`left: None, right: Some(4294967290)`，与程序 red.log 断言值逐字一致（行号 854/863 同）；还原修复行（`git diff` 空）→ 复跑 4 条全绿（`qa-green.log`，exit 0）。**红→绿与修复行一一对应，非采信程序归档** |
| 4 | 真机腿（交互验收，MCP 优先） | **PASS** | 编辑器（bsn_game fixture）+ 独立游戏进程（T25 先例形态）+ 远程连接建立 + Remote Entities 面板父子嵌套断言 + 截图，详见 §4 |
| 5 | 报告落盘 | **PASS** | 本报告 |
| 6 | QA 证据归档并 commit 到分支 | **PASS** | `loop/bug-r4-qa/`（详见 §5），随本报告 commit 到该分支；不合入 main、不动 buglist/roadmap/progress |

## 2. 红绿方法声明

**选方法 a（独立复红）**：程序 red.log 未被直接采信，QA 在本机工作树独立复现了红证再复绿。
断言值交叉验证一致：`Some(4294967290)`（= `Entity::from_raw_u32(5).unwrap().to_bits()`）在修前
被 `as_u64` 丢成 `None`——正是票面「恒 None → 全判根 → 平铺」的机制。

## 3. 门禁证据标准执行说明

按契约「日志全文复核制」执行：三份 QA 日志均逐行复核（grep error/FAILED/Diff + 人工看尾行），
exit code 仅辅助。QA fmt 一轮通过（无程序侧「首轮返工」复现——程序偏差 1 属其新增代码排版，
修复后末轮已覆盖归档，QA 不再复现此问题）。

## 4. 真机腿证据链（MCP 优先原则）

### 4.1 驱动形态

按 T25 先例（bash+curl+jq，`loop/qa/r4-live.sh` 精简为 `loop/bug-r4-qa/r4-live.sh`）：

1. **boot 编辑器**（fixture 工程 `tests/fixtures/bsn_game`，`JACKDAW_OPEN_PROJECT` 直开，
   `JACKDAW_WINDOW_SIZE=1920x1080`，端口 15703）；
2. **游戏进程独立启动**（T25 的 GAMEBIN 形态）：shell 侧 `cargo build`（`qa-game-build2.log`）
   后 `BEVY_ASSET_ROOT=<fixture>` 直接跑 `bsn_scene_game`，游戏 BRP 15702 应答
   `{"app_name":"Bevy Game","bevy_version":"0.21"}`（PIE 路因本机环境问题改走独立进程，见 §6 偏差 2）；
3. **编辑器通过工程布局持久化**（`project.json` 的 left Leaf 增补 `jackdaw.remote.entities`）
   使 Remote Entities 面板默认打开（窗口菜单/命令面板均无打开入口，见 §6 偏差 5）；
4. **远程连接**：状态栏指示器 → 连接 popover → Connect（默认 endpoint `http://127.0.0.1:15702`）；
5. **断言全部走结构化通道**：`jackdaw/scene_snapshot`（游戏侧线上形态）+ `jackdaw/ui_tree`
   JSON walk（面板树嵌套）+ `jackdaw/screenshot`（视觉留档），零坐标注入、零像素赌。

### 4.2 生产端线上形态（票面机制亲证）

`jackdaw/scene_snapshot`（游戏 BRP）拉回 7 实体，`ChildOf` 全部为**实体文本形式**
（`live-game-childof-forms.txt`）：

```
entity=4294966725 name=Root           ChildOf="566v0"
entity=4294966722 name=Marker Probe   ChildOf="570v0"
entity=4294966720 name=Scatter Group  ChildOf="570v0"
entity=4294966729 name=scene          ChildOf=null
entity=4294966723 name=Sun            ChildOf="570v0"
entity=4294966724 name=Main Camera    ChildOf="570v0"
entity=4294966721 name=Bgm Probe      ChildOf="570v0"
```

`as_u64()` 对 `"NvM"` 文本一律 None——票面机制在真机数据上成立；修复路由到
`entity_bits` 后文本形态可解析。

### 4.3 连接建立

编辑器日志（`live-editor.log`）：

```
[06:46:40] INFO jackdaw::remote::connection: Connected to remote game: Bevy Game
```

状态栏 label 翻转为 `Connected: Bevy Game`（`live-walk-connected.json`）。
连接后编辑器自动按 `RemoteSnapshotPollTimer` 周期拉 `jackdaw/scene_snapshot`，
面板状态文本由 `Not connected` → `7 entities`（与游戏侧 7 实体一致）。

### 4.4 核心断言：远程层级树非平铺（父子行嵌套）

展开操作（懒展开链）：点 `scene` 行展开箭头 → 填充子行 `Root`；点 `Root` 行展开箭头 →
填充五个子行。最终面板树行（`live-walk-expand3.json`，摘要见
`live-hierarchy-assertion.txt`，缩进 x 即嵌套深度）：

```
y=  93  x= 49  scene              ← 唯一顶层根行
y= 121  x= 70  Root               ← scene 的子行（缩进 70 > 49）
y= 149  x=  91  Bgm Probe         ← Root 的子行（缩进 91 > 70）
y=  177  x=  91  Main Camera
y=  205  x=  91  Marker Probe
y=  233  x=  91  Scatter Group
y=  261  x=  91  Sun
```

判定（三项全部满足）：
1. **顶层只有真根 `scene` 一个行**——修前平铺形态会把全部 7 实体判根平铺在顶层
   （`has_children` 恒 false，懒展开永不触发）；
2. **子行出现在父行下**（ui_tree JSON 的行缩进层级 = 父子嵌套关系）；
3. **`has_children` 行可展开且展开后填充子行**（懒展开两跳全部工作）。

### 4.5 视觉留档

`live-screenshot-window.png`（1920x1080）：左栏 Remote Entities 面板嵌套树
（scene → Root → 五子行，逐级缩进）+ 右下角状态栏绿点 `Connected: Bevy Game` 同框。

### 4.6 修前对照说明

方案书 QA 验收 3 的「与修前对照（平铺列表）」以**单测红证 + 独立复红**替代真机修前对照：
修前形态已由 4 条单测的红侧（文本/数组形态 `None`）与机制链（`extract_parent`→根判定/
`children_of`/`has_children` 全部经由该单点）钉死，真机修前对照需重建修前编辑器+连接
（连接 popover 交互本身受 §6 偏差 3 影响，成本不成比例），如实记档。

## 5. QA 证据归档（loop/bug-r4-qa/，随本报告 commit 到任务分支）

| 文件 | 内容 |
|---|---|
| `qa-fmt.log` / `qa-clippy.log` / `qa-libtests.log` | 门禁三连 QA 亲跑全文日志 |
| `qa-red.log` / `qa-green.log` | 独立复红（还原修复行）与复绿 |
| `r4-live.sh` | 真机腿驱动脚本（bash+curl+jq，T25 先例形态） |
| `live-console.log` / `live-editor.log` / `live-game.log` | 编辑器/游戏控制台与日志（含 `Connected to remote game` 行） |
| `qa-game-build2.log` | fixture 游戏构建日志 |
| `live-game-scene_snapshot.json` / `live-game-childof-forms.txt` | 游戏侧线上快照与 ChildOf 文本形态 |
| `live-walk-*.json` | ui_tree JSON walk 序列（chrome/popover/面板/展开三跳） |
| `live-walk-expand3.json` + `live-hierarchy-assertion.txt` | 最终嵌套树证据与断言摘录 |
| `live-screenshot-window.png` | 编辑器整窗截图（树+状态栏同框） |
| `live-project.json.bak` | fixture 布局文件改动前备份（改后已还原） |

## 6. 偏差 / known-issue 单列（全部不阻断 R4 判定）

1. **fmt 程序轮返工未复现**：QA fmt 门一轮通过。程序报告偏差 1（首轮两处长行 Diff）属
   其新增测试排版，末轮已覆盖归档，QA 侧无对应问题。
2. **PIE 路改走独立游戏进程（T25 先例形态）**：编辑器内工程打开流程在本机存在环境性
   停滞（见偏差 2b），且 PIE 需要 `jackdaw.toml`+cargo 构建链；任务书允许「boot 游戏
   （或按 T25 先例启动含父子层级场景的游戏进程）」，故游戏侧走独立进程，编辑器仅提供
   chrome（面板+连接）——远程面板数据源为游戏 BRP，两种形态的 producer（游戏 BRP
   `scene_snapshot`）完全一致，断言效力不变。如实记档。
3. **【立票素材·产品缺陷候选】连接 popover 越出窗口右缘，中心点击必然落空**：
   popover（宽 252，TopStart 放置）锚定状态栏指示器（右缘 x≈1908），整体右缘 x≈2067
   越出窗口逻辑宽 1920；`ui_click` 以 `placement.centre`（x=1941）为中心注入点击，
   该点在窗口外 → `clicked:true` 但手势永远无效。可用绕过：对按钮可见区内坐标
   （如 x≤1875）用 `input.pointer` 的 move→press→release 三步（跨帧）可靠触发。
   建议：A 系立票「popover 放置做窗口边界 clamp（或 ui_click 对越界中心点回退到
   可见区交点）」；本任务不修（范围纪律 D3）。
4. **【立票素材·工具层缺陷候选】`ui_tree` 的 text 过滤对 popover 子树失效**：
   popover 打开时 `ui_tree {"text":"Remote Connection"}` 返回空，而同参数无过滤全量
   walk 能看到 popover 全部节点（含标题文本）——`locate_for_tree` 的起点集合不含
   popover 子树。QA 曾因此多次误判 popover 未开。建议并入偏差 3 的 A 系立票或单独
   工具票；本任务不修。
5. **窗口打开入口缺失**：Remote Entities 窗口（`jackdaw.remote.entities`）无 operator、
   无命令面板命令、无菜单项（Window 菜单属 y<40 禁触区，手册 7.5），QA 最终通过
   `project.json` 布局持久化让面板默认打开（改前备份 `live-project.json.bak`，收尾已
   还原）。属「交互驱动麻烦步骤」，按 MCP 优先原则可立工具票（窗口开关 operator）。
6. **本机环境异常（未复现于收尾会话，记录备查）**：
   a) 一次 boot 后工程打开流程静默停滞（`jackdaw.toml` 存在时复现 2 次：扩展加载后
   无日志无对话框，`project:null` 15 分钟+）——绕过：删除临时 `jackdaw.toml` 走
   「Open without setup」路径（该对话框点击正常）；`jackdaw.toml` 为 QA 临时补齐、
   已删除，fixture 未留痕；
   b) 一次 boot 后编辑器窗口被外部销毁（日志 `Skipped event Destroyed for unknown
   winit Window` 后进程退出，当时无任何 pkill 操作）；
   c) 首个编辑器会话期间出现来源不明的 operator 调用（`hierarchy.open_context_menu`
   /`grid.increase`/`viewport.focus_selected` 若干次）；
   d) 编辑器日志两次出现 `Monitor removed 1526v0`（显示器拓扑变化，本机单屏 2560x1440）。
   以上均不涉及 R4 修复面（解析单行与树构建），不影响判定。
7. **QA 脚本自身缺陷（已修复）**：`r4-live.sh` 首版 `wait_idle` 用 `bash -c` 包裹
   shell 函数（子进程不可见函数）导致 boot 判定假阴性三次；已改为同 shell 管道实现，
   并随证据归档（脚本最终版无此问题）。
8. **N13 census**：收尾编辑器/游戏日志全文扫描无 `panic`/`swap_remove` 行——**N13 未
   复现**（本次连接生命周期未触发 PIE drain 路径；census 口径记 0）。
9. **fixture 临时改动已全部还原**：`Cargo.toml`（临时 `jackdaw_remote` 依赖）、
   `src/main.rs`（临时 `JackdawRemotePlugin`）、`jackdaw.toml`（临时补齐后删除）、
   `project.json`（布局改后还原备份）；`git status` 干净（仅 `.zcode/config.json` 为
   本会话工具自身写入，与任务无关，不纳入 commit）。副产物 `bsn_game-main/`（编辑器
   setup 流程复制的 896MB 工程副本）已删除。

## 7. 结论

**PASS——放行合入。** 修复行、测试、门禁、红绿、真机五面全部亲验通过；真机腿在真实
游戏进程 + 真实连接 + 真实面板上确认远程层级树按父子嵌套渲染（非平铺），懒展开正常。
发现的 popover 越界与 ui_tree 过滤两个缺陷均不属 R4 修复面，建议 A 系立票由主控裁定。

**不合入、不打勾，收尾归主控。**
