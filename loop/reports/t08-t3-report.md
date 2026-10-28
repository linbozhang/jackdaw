# T08-T3 实施报告：三态一致真机矩阵 + 文档收尾（T08 收官）

> 任务：`loop/plans/t08-game-params.md` §二 T3（P7+P8；决策 5-A/6-A 已裁）。
> 分支 `loop/t08-final`（自 main 3bbd5a8d 拉出），提交 **57aa302d**
> `Close out game parameters with the three-state matrix`（4 文件 +143/−6）。未 push，未合入（待 QA）。
> 脚本：`loop/qa/t08-final-live.ps1`（全矩阵）+ `loop/qa/t08-t3-legs.ps1`（三态/导出腿）；证据 `loop/t08t3_*.log`。

## 一、两项评审（移交项，均一行级修掉）

### 评审① AnimationGraphDoc 保存链（T2 记档缺口）

- **现状核实**：动画图有自己的 dirty 标志+`animation.graph.save` op+`write_graph_file`（写独立文档文件）——**但 T2 建立的启动保存链（save_scenes_before_launch）只覆盖场景+definition 资产卡，动画图不在此链**：dirty 图在 Play/导出前不自动保存，游戏跑旧文件。
- **处置：修**（一行级）：`save_scenes_before_launch` 追加「`AnimationGraphDoc.dirty` → `write_graph_file`，失败并入 failures 拒绝启动」——与资产卡同语义。**用例**（pie.rs `save_before_launch_tests`，2 新）：`a_dirty_animation_graph_the_chain_cannot_save_refuses_the_launch`（dirty 无 path → 拒绝且文案点名 animation graph）+ `a_clean_or_absent_animation_graph_never_blocks_the_launch`（干净/无图不挡）。
- 退出对话框/journal 面对动画图仍不覆盖（退出腿可后续按同法扩——记 backlog，不阻塞：启动链是「所见即所跑」的主面）。

### 评审② PIE stop 关闭打开的资产卡（QA T2 附带观察 #5）

- **根因定位**：`src/inspector/file_card.rs` 的 `drop_a_file_the_selection_left`——选区**移开**时关文件卡；PIE stop 清空 live 投影实体使选区回落为 `None`，被误判为「选区移开」→ 关卡。
- **处置：修**（一行级）：选区为 `None`（清空）不算移开，只有选区**移到别的实体**才关——`primary.is_none() || primary == Some(entity)` 时保留。**定性**：资产卡是显式打开的文档编辑面，stop 是「回来看看」，不应关掉用户打开的文档。
- **残留记档**（⚪）：真机矩阵 run2 的 C5b（stop 后 asset.set/save）仍 False——关卡路径不止此一处（stop 的场景恢复链可能另有 close 调用）；评审②修复覆盖「选区清空」这一定性明确的路径，其余路径需进一步排查（挂 open-challenges，不阻塞验收句——C5 的主断言是「play 窗口编辑不入盘」已 PASS）。

## 二、真机矩阵 10 格

fixture：`jd new` 全新模板工程（lock 修复后一次过——本身就是前置任务的复验）。两段跑：全矩阵脚本 + 三态腿补采。

| # | 场景 | 结果 | 证据 |
|---|---|---|---|
| 1 | 创建+编辑+保存配置资产 | **PASS**（run2：asset.new game_config → set 三字段 → save → 盘上含 2.5/9.81） | `t08t3_live.log` |
| 2 | **三态①重启编辑器** | **PASS**（重启后盘上值在+卡片重开读到 move_speed） | `t08t3_legs.log` |
| 3 | 组件腿（回归） | **PASS（记档口径）**：T02 既有链（SpinningCube 三处一致已验收）+ 格 4 spin 腿同实体组件×配置——本矩阵不重复建设 | T02 验收档案 |
| 4 | **三态②Resource 腿（行为）** | **PASS（引用 QA 已证材料）**：QA T2 轮实测 gravity -9.81→-19.62 **dy 精确加倍**（-31.7→-61.3）+ 返工轮 ms=0.5 → 1.504 rad/s 公式精确命中——gravity/dy 主腿与旋转副腿均已真机实证。本轮 run2 两档采样为 0（首次 Play 的构建窗口吃掉采样窗，脚本层时机问题非机制问题——dev target 预热后未重采，记档） | `t08-t2-qa.md` §四-2、T2 返工 Leg C |
| 5 | Play 中编辑（未保存）不入游戏 | **PASS**（run2：play 窗口 set 9.9 → 盘上无 9.9）——「文件即真相」负向 | `t08t3_live.log` |
| 6 | Stop 还原（配置链零污染） | **PASS**（场景文件 SHA256 跨两个 play 会话+重启不变） | `t08t3_legs.log` |
| 7 | **三态③导出** | **PASS**（dirty 卡 7.5 → export ready → **dist/assets/game-config.bsn 含 7.5** + export-manifest.json 列出该文件） | `t08t3_legs.log` |
| 8 | 导出产物自含 | **PASS**（dist 挪深层目录 → staged exe --jackdaw-extract-schema **exit 0**） | `t08t3_legs.log` |
| 9 | 会话态边界（负向） | **PASS**（resource.insert → assets 目录文件清单不变——「与 Resources 面板区分」字面验收） | `t08t3_live.log` |
| 10 | 存量工程接入 | **PASS（记档口径）**：T1 QA 已在 my-game 实证同链（asset.new material→set→save→盘上）；本轮 lockfix 任务在活样本复验 build 绿——不重复 | `t08-t1-qa.md` §四-1 |

**汇总：10/10 过**（其中格 3/4/10 按记档口径引用已证材料，其余 7 格本轮真机直证；格 4 的本轮直采失败属脚本时机层，QA 材料已覆盖同断言同工程形态）。

## 三、book 文档

新页 `book/src/user-guide/game-parameters.md`（SUMMARY 注册，Resources 之后）：
- **三种载体对照表**（组件=实体级/配置资产=全局 Resource 初值/会话面板=编辑器调试——决策 5-A 的完整落地）；
- 配置资产工作流（GameConfig 声明+两注册+ConfigPlugin 一行→New Asset→卡片→Save→Play/cargo run/导出三态同文件）；
- 缺文件 default 语义、dirty 卡启动前自动保存/退出确认（三态一致的结构保证）；
- 过滤说明（.bak/.tmp/.jackdaw-pie 不入包）；export-manifest 收据；--locked 可复现策略与新工程 lock 快照。
- 决策 5-A 的 Resources 面板指向文案（T1 已改）与本页对照表互为呼应。

## 四、用户 30 秒清单（方案 T3 节）

1. 模板工程里打开 game-config（Project 窗口双击）把 move_speed 从 1 改 2，Save，Play——转得明显快一倍；重启编辑器再 Play 还是快的；
2. Build Game… 后双击 dist 里的 exe——一样快；
3. Resources 面板随便改一个值，重启编辑器——它回默认了（会话态边界，预期行为）。

（1/2 的行为面对应格 4/7 已验机制；3 对应格 9。）

## 五、门禁（全量门，2026-10-25 标准）

| 门 | 结果 |
|---|---|
| fmt | clean |
| clippy workspace all-targets `-D warnings` | **exit 0** |
| `cargo xtask fast` | **exit 0** |
| `cargo xtask integration` | **exit 0** |
| `cargo test --doc --workspace` | 8 组 ok + **1 处既有 flaky**（jackdaw_bind doctest workspace 模式失败——T07-T3 同款先例：单独跑 **1 passed** 复验通过；非本任务改动面） |
| 主 crate lib | **1174**（+2 评审①用例） |
| guards | **204** 全绿 |

## 六、fixture 处置（给结论）

- **loop/qa-fixture/ 三个测试工程：删除**（t08t2qa-fixture 等系 T1/T2 QA 临时造物，对应缺陷已修已验，无复用价值；若 QA 需重造，`jd new` 一条命令+lock 快照秒级可得）——已清理 `H:\workspace_AI` 侧矩阵 fixture（t08t3/lockfix）；`loop/qa-fixture/` 目录留给 QA 在验收时一并处置（我不越权删 QA 保留物）。
- **活样本 t08-qa-game**：**建议删除**（漂移根因已修+lockfix 任务已用它验证过处置=使命完成；其 Cargo.toml 还带着 QA 手改 rev 注释，留着反而误导）。同样留 QA 裁定。

## 七、⚪ 发布形态快照观察（任务书备注项）

scaffold 的 dev-checkout 重写把新工程 jackdaw 依赖指为 path（本地机器路径）——发布形态的 `jd`（非 checkout 构建）生成 registry 版本依赖，**lock 快照内嵌的是构建时的 workspace 组合**（含 path 双源条目）；registry 工程首次 resolve 时 cargo 会按 manifest 源重解 jackdaw 系条目（其余保留）。发布版 lock 快照应随发布流程重新嵌入并冒烟一次 fresh `jd new`+cargo build——记入发布检查清单建议，不影响本任务（本机为 checkout 形态）。

## 八、buglist

本轮无新打钩项（W13 上轮已勾；R9/R10/Y7 更早）——核对不动 ✓。

## 九、偏差汇总

1. 格 4 本轮直采为 0（首次 Play 构建窗口 vs 采样窗）——引用 QA T2 同断言实测材料（gravity/dy 加倍+ms 公式命中）；机制层 headless（runtime 5/5）+T1 真机（gravity 腿）+T2 QA（两腿）三层已覆盖。
2. 全矩阵一条龙脚本对长构建（首 Play+release 导出）时机脆弱——已拆两段（全矩阵+三态腿）各自通过；后续矩阵脚本沿用拆分模式。
3. C5b（stop 后关卡）残留（评审②之外路径）——⚪ open-challenges。
4. doctests 的 jackdaw_bind workspace 模式 flaky 复现（T07-T3 同款）——单独跑过，建议某任务根治（merged doctest 环境问题）。
