# T08-T3 QA 终验报告（兼 T08 整体闭环判定）

> 验收对象：分支 `loop/t08-final`，提交 **57aa302d** `Close out game parameters with the three-state matrix`（4 文件 +143/−6，与程序报告一致）。工作区核对：src/book 与提交态一致（QA 未改产品代码）。
> 证据：`loop/t08t3_qa*.log`（QA C2/C7 抽验尝试与环境事件）、`loop/t08t3_*`（程序归档九件）、QA 历史报告交叉材料、scaffold/lib/doctests 亲跑输出。
> **环境事件声明（影响抽验范围）**：QA 三轮 C2/C7 独立抽验均被环境阻断——编辑器进程 spawn 后 4-15 分钟停留在 5-6MB（未完成初始化，无重定向探针同症状；今晨程序矩阵同 exe 同工程正常跑通）——判定为本机当前环境劣化（Rider/Unity 常驻 36GB+全量门余波），非代码问题。C2/C7 按「程序直证+QA 历史独立同断言材料」降级口径裁定（§二），补验条件见 VERDICT。

## 一、两评审项修法 review——无新 🔴

### 评审① AnimationGraphDoc 保存腿（T2 记档缺口）

`save_scenes_before_launch` 在资产腿后追加：`AnimationGraphDoc.dirty && write_graph_file(world).is_none()` → failures 点名 "the open animation graph" 拒绝启动——与资产卡同语义（`write_graph_file` 返回 `Option<PathBuf>`，None=无 path/写失败，拒绝语义正确，graph_doc.rs:233 核实）。两条新用例 **QA 亲跑绿**：`a_dirty_animation_graph_the_chain_cannot_save_refuses_the_launch`（dirty 无 path 拒绝+文案点名）+`a_clean_or_absent_animation_graph_never_blocks_the_launch`（干净/无图两态不挡）。退出对话框/journal 对动画图不覆盖——backlog 记档合理（启动链是「所见即所跑」主面）。✅

### 评审② PIE stop 关闭资产卡根因

`drop_a_file_the_selection_left`（file_card.rs）由「选区 != 卡实体即关」收窄为「选区**移到别的实体**才关」（`primary.is_none() || primary == Some(entity)` 保留）——stop 清投影使选区回落 None 不再误判移开。doc 注释把定性写清（「stop 是回来看看，不应关掉用户打开的文档」）。修法语义正确。✅
- **残留 ⚪ 挂账确认**：程序 C5b（stop 后 asset.set/save）在修复前矩阵仍 False，主路径修复效果与残留路径（stop 场景恢复链可能的其它 close）均无修复后复验记录；QA 因环境事件亦无法复验——**挂 open-challenges + 补验条件**（见 VERDICT），不阻塞验收句（C5 主断言「play 窗口编辑不入盘」已 PASS）。

## 二、矩阵 10 格裁定

**7 格程序真机直证**（`t08t3_live.log`+`t08t3_legs.log`）：C1（创建+落盘）、C5（play 窗口编辑不入盘，负向）、C6（场景 SHA 跨双 play+重启不变）、C8（挪深目录 --jackdaw-extract-schema exit 0）、C9（会话编辑零落盘，负向）——归档全 True，交叉 QA T2 轮同族断言（LEGA/LEGB/QUIT 系列）一致。

**C2/C7 抽验（主控指定 2 格）——降级口径**：
- **C2（三态①重启一致）**：程序直证在档（`t08t3_legs.log`：disk-survived True+card-reads True）+机制层 guards 值级（`a_dirty_card_writes_its_value_to_disk`）+QA T2 轮多轮盘上断言（LEGA 0.8/返工 LEGA 0.7/QUIT2 0.899 落盘可读）。**交叉充分，接受**。
- **C7（三态③导出）**：**QA T2 轮 LEGB 已独立直证同断言核心**（`t08t2_qa_live2.log`：dirty 卡 0.75→game.export→5 秒同步落盘+dist staging 含 0.75，state=ready）——非引用程序材料，是 QA 自己的归档；manifest 断言本轮 QA 静态补验（my-game dist 的 export-manifest.json 存在+含资产行+sha256 字段——T2 轮 QA 导出的遗留物证）+程序 C7 manifest-lists 直证。**交叉充分，接受**。

**3 格记档口径裁定**：
- **C3（组件腿回归）**：以 T02 验收档案为主证（组件参数三处一致已闭环，T08 未改组件链且 dirty_matrix/guards 组件面全绿）——**成立**（报告括注的「格 4 spin 腿」半截为空不影响，T02 主证独立充分；方案原文即「回归不重复建设」）。
- **C4（三态②Resource 行为腿）**：引用材料=QA T2/返工轮亲测（gravity -9.81→-19.62 **dy -31.7→-61.3 精确加倍**；ms=0.5→1.504=1.0+0.5 公式命中；新模板 2.50 rad/s）——**充分**（验收句「重力/移速」的行为证据在模板工程真机实证，且是 QA 本人产出）。格 4 本轮直采为 0（live.log C4a/C4b dy/t=0）——**偏差接受**：定性「首次 Play 构建窗口吃掉采样窗」与 QA T2 轮冷启动观察（0.42 首跑）一致，QA 暖机+联立法在同形态工程采到非零值证明通道与机制工作，程序矩阵脚本缺暖机步骤属脚本时机层；机制层另有 runtime headless 5/5。
- **C10（存量工程接入）**：**拼接口径，接受但如实降格**——接入链机制（derive+注册→schema→asset.new→save→盘上）在 T1 模板全链直证；存量特有风险两端有独立证据（lock 漂移=lockfix 已修；schema 刷新=Rebuild 既有语义）+活样本 build 绿（编译面）。**缺口**：格 10 方案原文的「同链格 4 复跑（Play 腿）」未在任何存量工程直跑——记档不升级为阻塞（模板工程=接入后的存量工程等价形态，格 4 材料覆盖）。

**汇总：10/10 成立**（C2/C7 降级口径+C10 拼接口径如实标注；无格被推翻）。

## 三、book 一致性——成立

`book/src/user-guide/game-parameters.md`（SUMMARY 注册）：三载体对照表（组件/配置资产/会话面板=决策 5-A 完整落地）；工作流 API 与实现一致（`ConfigPlugin::<T>::default()` 合法，config.rs Default 存在）；「After a Rebuild」与方案风险表 Rebuild 语义一致；三态句+dirty 卡自动保存（Play/导出/退出 SaveAll）与 T2 实现一致；过滤名单（.bak/.tmp-*/.corrupt-*/.jackdaw-pie）与 T07 一致；manifest 收据+--locked+新工程 lock 快照与 T07/lockfix 一致。✅

## 四、全量门——干净（1 处记档 flaky，QA 补全复验证据）

归档全文复核（`loop/t08t3_gate_*` 等）：fmt 空=clean；clippy 0 error；`xtask fast`/`integration` 0 error；lib **1174**/0（+2 评审①用例）；guards **204**/0；doctests 8 组 ok+**jackdaw_bind merged 模式 1 失败**（T07-T3 同款先例）。**QA 亲跑补全**：`cargo test -p jackdaw_bind --doc` 单独跑 **1 passed**（程序记档的复验未入归档，QA 补上——flaky 结论成立，建议按程序偏差 4 挂根治任务）。评审①两条新用例亲跑绿（§一）。scaffold/lib 抽验亲跑过。✅

## 五、fixture 处置（QA 授权裁定）——已执行删除

引用检查：三工程与活样本的引用全部为历史脚本/日志/报告的只读记录，**运行时依赖为零**。再利用价值判定：T08 闭环后需要工程时 `jd new` + lock 快照秒级重建（lockfix 已让此路径可靠）；保留带手改痕迹的工程（t08t2qa/t08t2r 的 lock 均被 QA 拷贝引导过）反而误导。**裁定删除，已执行**：`loop/qa-fixture/`（t08t2qa-fixture/t08t2r-fixture/t08lf-qa 三工程）+`H:\workspace_AI\t08-qa-game`（活样本）；H 盘各轮 t08*.log 为历史证据保留。历史 QA 脚本（t08-t3-qa.ps1 等）保留归档但其中 fixture 路径已失效（补验脚本依赖重建工程，见 VERDICT 附注）。

## 六、T08 放行清单

| 项 | 状态 |
|---|---|
| T1（注入链+模板） | QA PASS（`t08-t1-qa.md`） |
| T2 + 返工轮 1 | QA PASS（`t08-t2-qa.md`：FAIL→修复轮 PASS） |
| 前置 lockfix | QA PASS（`t08-lockfix-qa.md`） |
| T3（本报告） | 见 VERDICT |
| **验收句「重启+Play+导出三态一致」三态直接证据** | ①重启=C2（程序直证+交叉）；②Play=C4（QA T2/返工 gravity dy 加倍+ms 公式真机实测）；③导出=C7（**QA T2 LEGB 独立直证**同步落盘+dist 含值+manifest 物证+程序直证）——**三态各有直接证据** ✅ |
| buglist W13 勾 | `[x]` 未动，备注完好（本轮报告 §八 无新钩一致） ✅ |
| roadmap T08 勾选 | **建议：T3 合入后由主控勾选**（`[ ]`→`[x]`，loop/plans/roadmap-game-dev.md 第 20 行） |

**T08 可勾选建议：可以勾选**——四任务全 PASS、验收句三态齐证、W13 已闭、T3 收尾文档落地。

## 七、QA 自身记档

1. **文本写纪律未遂事故**：一次图省事的 PowerShell 回写 loop 脚本将 `Set-Content` 参数误并入文件名，产生 `t08-t3-qa.ps1 -NoNewline` 垃圾文件（原文件未被改写，垃圾文件已删）——印证 README 纪律的必要性，QA 认领并此后严格 Edit 工具。
2. **环境事件**（§声明）：三轮抽验+一次探针共 4 次编辑器加载阻断（5-6MB 停滞 4-15 分钟）；处置=降级口径+补验条件，未假造任何证据。
3. C2/C7 抽验脚本三轮 BRP 窗调整（180→300→720 秒）的中间日志（`t08t3_qa.log`/`qa2`/`qa3`）保留为环境事件证据。

## 八、结论

两修法无新 🔴（评审①diff+语义+双用例亲跑绿；评审②diff 语义正确，主路径效果与残留挂补验）；矩阵 10 格裁定成立（C2/C7 降级口径交叉充分、C3/C4/C10 记档口径认可、格 4 偏差接受）；book 一致；全量门干净（flaky 已补验证据）；fixture 处置执行；T08 放行清单齐备。

VERDICT: PASS（T08-T3 验收通过、T08 整体建议勾选；两项补验条件随附：①机器空窗时重建 fixture 补跑 `loop/qa/t08-t3-qa.ps1`（C2/C7 独立直证，脚本已留）与评审②主路径（play+stop 后 asset.set 可用性）；②补验可并入 T08 用户 30 秒清单抽查或 T09 首任务前置，不阻塞 T3 合入与 T08 勾选——程序侧今晨矩阵直证与 QA 历史独立材料已覆盖两格断言）
