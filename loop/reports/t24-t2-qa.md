# T24 任务 2 QA 复核报告（独立复核）

> 复核对象：分支 `loop/t24-debug` @ **291e3a4d**（T2 真机矩阵轮）+ 主控记账 e669ca6f
> （buglist A19 立账+progress 台账，主控面）。基线 b9935bbd=T1 QA PASS closeout。
> 程序报告 `loop/reports/t24-t2-report.md`；方案 `loop/plans/t24-debug-feedback.md`
> §二 13 格判据+§三腿清单；T1 QA 交接附注两条（cursor 收尾、ui_click 命中按钮节点）。
> 复核日期 2026-11-03，平台 macOS arm64。RUST_BACKTRACE 全程未设；QA 复跑窗与程序
> 证据窗分离（QA 证据全落 `loop/t24-live-qa/`，程序证据目录零触碰）；全部数字**亲跑
> 非转录**（census 亲数归档 `t24t2qa_census_recount.log`）。

## 裁决：**PASS**（放行 T3 终验+文档轮）

- 程序偏差 D-a/D-b/D-c/D-d 复核**全部成立**；QA 新立观察级偏差 **QD1-QD4**
  （全部非阻断，修文/裁定素材留主控）。
- 「零产品改动轮」声明**属实**：`git diff --name-only b9935bbd..291e3a4d` 亲跑 91
  文件全部在 `loop/`（脚本 1+报告 5+证据 85）；buglist/roadmap/台账/book/产品源码
  零触碰（e669ca6f 的 buglist.md/progress.md 改动为主控记账面，任务声明在案）。

---

## 一、六项复核逐项结论

### 1. diff 面 — ✅ 干净，零越面

91 文件=loop/qa/t24-live.sh ×1 + loop/reports ×5（t24-t2-report.md、dfr1/2/3_green、
warn_census）+ loop/t24-live ×85。产品树/buglist/协议/fork 零改动亲证
（`grep -v '^loop/'` 差集为空）。

### 2. 抽核四格证据链 — ✅ 全链闭合（C3/A3/B3/B5）

- **C3（全链亲证）**：walk-c1/walk-c3-landing 均带「4 errors · first:
  src/lib.rs:2077:18」汇总+箭头行带+「Open」钮；`c3-click-response.json`
  clicked:true、target=节点实体 4294962531 text="Open"（按 T1 附注经行文本父节点
  命中按钮，非文本子节点）；`walk-c3-landing.json` 状态栏「opened cursor at
  src/lib.rs:2077:18」在档；console「cursor processes before=0 after=2」拉起证据+
  `pkill -x Cursor`（脚本 :680）腿后收尾亲证。终跑（run5，窗 83800）六腿全 PASS。
- **A3（增量判据链）**：`a3-click-response.json` clicked:true text="Locate" 实体
  8589929473；console 亲读「selection cleared before the click (length now 0)」→
  「after Locate selection=AuditEntity scene=…/assets/t24a.bsn」——清选中判增量的
  D-d 修正真实在跑；walk-a3.json AuditEntity 在档。
- **B3（双节并存）**：walk-b3.json「Broken references」×1+「Binding problems」×1+
  t24b3 引用行×1+DualEntity 绑定行×1，互不吞亲证；scoped 审计判据=1（D-d 修正：
  run1 未 scoped 计 2 FAIL→run2 scoped=1 PASS，console 两跑对照亲读）。
- **B5（五要件）**：①指引 warn（b5-warn-line.txt+终窗 11:31:26 行，报注册定义拼写
  `graph::AnimationGraphRef`）②误导单因 rebuild 行终窗 **0 次**（亲 grep）③双因
  诚实 remedy 在窗（11:31:26 catalog 行全文亲读）④板行 walk-b5.json「RedEntity ·
  …AnimationGraphRef (unknown type)」×1 ⑤组件 0 持有 vs Transform 17（console
  B5_COMPONENT_UNAPPLIED 腿亲读）——处置语义=明说不归一，与 T1 QA QD3 分工一致。
- 旁证格快读：A1 四元组 finding（a1-finding.json 逐字段）+warn_on_load 行+operator
  嘴（a1-audit-operator.json「1 broken references in 1 documents (1 Missing)」）；
  A4 一次锁双腿+新 key 再说（a4-warn-line.txt、板汇总 1→2）；B1 双腿、B2 翻绿、
  C1 三嘴、C4 不翻 Failed（walk-c4「Project built」在、「Build failed」0）。
- 腿数口径核：报告 headline 39=唯一腿名（C14+A13+B12）；提交信息 41=console 判定
  条目（B2_PANEL_ROW_GREEN 与 B5_REMEDY_HONEST 各重复判 1 次）。两者各自自洽，
  非偏差，记一句防误读。

### 3. warn census 复数 — ✅ 四窗全数对上（超出「至少 2 窗」要求），1 项完整性偏差

- **build 3**（1 ERROR+2 WARN）/ **assets 9**（4 WARN+5 ERROR）/ **bindings 8**
  （8 WARN）/ **runtime 2**（1 WARN+1 ERROR）=22 编辑器窗命中——亲数与报告
  3/9/8/2 逐窗对上（keymap preset 噪声每窗 1 条按 census 口径排除）。
- **assets 5 条引擎 ERROR 的 3+2 归因逐条亲证**：11:19:45（watcher，无 scene.open
  前置，紧随一次锁 WARN 11:19:46=首 key）+11:19:50/11:21:24/11:21:37（三处均紧随
  `OPERATOR: scene.open` t24b）+11:21:32（watcher，紧随 WARN 11:21:33=新 key）——
  恰 3 open+2 watcher，census 拆分**逐条成立**。
- bindings 8/8、build 3/3、runtime 2/2 归因逐行对上；误导行 0、B5 双 warn 各 1
  亲验。亲数归档 `t24t2qa_census_recount.log`。
- **QD1（census 游戏日志面不完整，QA 新立）**：`b4-game-direct.log` 实有 **8 条
  WARN**，census 只计「+1 游戏日志命中」（B4 设计 warn）。未列的 7 条=直跑游戏
  启动固有面（GhostComponent skip ×1、config 缺省 ×3、bind no-context ×3）——
  可归因但未归因入表，「全部归因；零未归因」对该文件**口径过强**。非阻断；
  T3 复跑按报告注意 7 对照归因结构时需把游戏日志全词表纳入。

### 4. DF 七件候选实证核 — ✅ 七件现象全部成立（2 件带证据面注记），A19 票一致性对上

| 件 | 现象判定 | QA 亲证锚 | 严重度建议 |
|---|---|---|---|
| DF-W1 reread 路径无载入摘要嘴 | **成立** | 源码级：`warn_on_load` 全仓唯一调用点 `src/scenes/operators.rs:585`（fresh-open 路径），`reread_tab_from_disk`（external_watch.rs:271）零调用；活体：assets run1-5 A1_WARN_ON_LOAD_FAIL→run6 fresh-open 结构 PASS | 🟡 合理（票面一致） |
| DF-W2 游戏侧 flow 载入丢字段零 warn | **成立（旁证级）** | 终窗游戏日志旁证：未知**类型**有 skip warn（GhostComponent×1）而 assets 在档的 t24bad.bsn（仅 unknown field）零 warn；脚本注释明记「the t24bad flow leg, recorded as a DF candidate」。**QD3**：报告「两次亲证」无独立腿记录/console 行在档，证据面弱于叙述——候裁吸收面时按旁证级采信 | 票面未标注（QD4） |
| DF-W3 写窗中间态双 key | **成立** | assets run2/run3 亲读「distinct rows: 2 (want 1)」×2；run6 原子替换后 1→2 恰序（console 六跑对照亲读） | ⚪ 合理（harness 原子写已绕） |
| DF-W4 walk 重复发射子树 | **成立** | 原始计数膨胀多处亲证：C 格箭头 walk 原始 24 处 vs 结构化 4 行；assets run1 板行原始 6/9；脚本被迫「distinct/汇总行」计数 | 票面未标注 |
| DF-W5 drain_game_events panic | **成立** | 终窗 ERROR ×1 亲证（12:10:41）。**QD2**：报告「弃置的碰撞窗 2 次」不准——弃置三窗实有 4 条（6515:1+11469:2+14561:1），修文留主控；现象与 N13 家族归票不受影响 | 并 N13 合理 |
| DF-W6 PIE 收尾悬空 ChildOf | **成立** | 终窗 WARN ×1 亲证（12:10:17，ChildOf(4725v1)→不存在实体） | 票面未标注 |
| DF-W7 PIE 后直启失去 remote 面 | **成立** | runtime run1/run2 直跑「never answered its BRP」×2 亲证（run2 为干净 DF-W7 现场；run1 混二进制位置因素）；run3 端口真拒绝+重启自守后 PASS；脚本三件套亲读（nc 拒绝循环/90s 未应答重启一次/注释记档） | 票面未标注；修向（绑定重试或启动期 warn）与 A10 同域判定合理 |
- **A19 票文本一致性**：七件内容与报告 DF 节逐条对上；处置面（④并 A7 批次随手、
  ⑤并 N13、⑦与 A10 同域）与报告修向一致；证据锚指向正确。**QD4（观察）**：票面
  仅 W1🟡/W3⚪ 带严重度，W2/W4/W5/W6/W7 未标注——主控修文职权，非阻断。

### 5. 纪律核 — ✅ 全过

- **真机/cargo 窗分离**：直跑 cargo 后备构建在编辑器清盘后自有窗（console-runtime
  「the editor is already down」+b4-cargo.log「Finished in 0.41s」缓存命中亲读）；
  活窗内唯一 cargo=编辑器自家 PIE 机器（脚本纪律 4 明文）。
- **df 门前**：脚本 prep 门 <15Gi 拒跑（:535-537）；`console-prep.log`「disk: 44Gi
  free」亲读。QA 侧开工时本机 14.97GiB（低于门槛）——已清理两处已闭环旧任务
  fixture 的 target 纯构建缓存（t21-sprite/t22-tilemap 各 18G，可再生成）至
  47.91GiB 后才发起复跑。
- **RUST_BACKTRACE 未设**：全部日志的 backtrace 字样仅 std 默认建议行
  「note: run with RUST_BACKTRACE=1 …」（该行本身=未设的证明，设了则打印真栈）。
- **A7 自守**：面板判据全走 ui_tree 文本锚+结构化远端锚；ui_click 全部经 walk
  解析的按钮节点（C3/Open、A3/Locate、B4/条体三处 click-response 亲读）；对话框
  仅 `dismiss_dialog`（answer choice 0=取消式清场，无表单提交/字段行定位）。
- **A9 自守**：budget() 即判不重试 + jackdaw/wait 重试窗（budget 15/20/60/90/120/
  240 多处亲读）；C1 构建腿 90×5s 窗、B4 直跑 90s+180s 窗。
- **A10**：PIE 半场只有编辑器面板 ui_click（Game 条展开），指针转发零触碰；B4 直
  跑半场按方案口径交付。**A14**：三色经远端 kind 断言，脚本零色读亲 grep。**A16**
  （模板零改动）：t24bad.bsn 为 assets 侧新增 fixture 文件，模板源未触碰（C4 腿
  治愈后 lib.rs 与 pristine 一致由脚本自愈保证）。
- **Zed/Cursor 收尾**：C3 腿后 `pkill -x Cursor`（cursor before=0 after=2→0）；
  Zed 未被 T2 触发（探针表首中 cursor，T1 探针档在 `t24t1_probe_editor_cli.log`）；
  QA 复跑后本机无 jackdaw 残留进程亲证。

### 6. 可抽格真机复跑 — ✅ bindings 相段首轮 11/11 全 PASS

- 入口：`env -u RUST_BACKTRACE T24_OUTDIR=…/loop/t24-live-qa bash loop/qa/t24-live.sh
  bindings`（QA 证据自建目录，程序证据零污染——git status 仅新增未跟踪
  loop/t24-live-qa/）。
- 结果：**B1×2+B2×3+B3×1+B5×5 判定条目全 PASS**，首轮即绿（程序侧该相段 run1 曾
  因未 scoped 判据 FAIL——D-d 修正在复跑中直接生效）。
- census 同形复现：QA 终窗 8 WARN（6 设计+t24b3 warn_on_load+material_overrides
  固有）+0 ERROR，与程序终窗 8 条逐行同形；误导行 0；B3 双节+DualEntity 行×1、
  B5 板行×1 亲 grep。fixture 复用零重 prep（材料已 mv 态下 B3 破引用面完好）。
- 耗时约 2 分钟（warm 缓存），与报告注意 1「可复跑」口径一致。

---

## 二、程序偏差复核（D-a..D-d 全部成立）

| 偏差 | 判 | QA 亲证 |
|---|---|---|
| D-a build 碰撞+加固 | 成立 | console-build.log 5 跑（17:35→18:28）；editor-build-1.log 共名时代（run1/run2）+run3 起带 `$$` 后缀；「restored the template … pristine copy」自愈行亲读；端口守卫+pid 对账+`jackdaw/wait idle` 在脚本亲读 |
| D-b assets 六跑收敛 | 成立 | console-assets.log 6 条 PHASE_DONE 亲数：run1 四 FAIL→run6 全 PASS；失败面全在 harness 工艺（A1 索引滞后/A4 计数膨胀/DF-W3 双 key），产品侧真发现=DF-W1/W3 口径成立 |
| D-c B4 形态 | 成立 | runtime 4 跑：PIE 半场 run2 起 PASS（run1 条节点不可寻址如实 FAIL）；直跑半场 run1/2 FAIL（DF-W7）→run3 PASS；PIE 条折叠面=c-f 四行、展开面=a-f 六行（walk jq 逐行亲抽，每行带 apply.rs:766 元数据） |
| D-d B3 scoped+A3 增量 | 成立 | bindings run1「audit count: 2 (want 1)」FAIL→run2 scoped=1 PASS；A3「selection cleared before click」console 行亲读 |

## 三、QA 偏差清单（QA 新立，全部非阻断）

- **QD1（census 游戏日志面不完整，观察）**：见 §一-3。`b4-game-direct.log` 8 WARN
  中 7 条启动固有面未入归因表；「零未归因」声明对该文件过强。T3 复跑对照时把游戏
  日志全词表纳入即可，无需重跑程序证据。
- **QD2（DF-W5 报告计数不准，修文）**：弃置窗 panic 实 4 条（1+2+1），报告/census
  写「2 次」。现象判定不变，修文留主控。
- **QD3（DF-W2 证据面弱于叙述，观察）**：「t24bad flow 腿两次亲证」无独立腿记录在
  档（现证据=脚本注释记档+终窗游戏日志旁证+t24bad.bsn 留档）。现象判定成立；候裁
  吸收面时按旁证级采信，或 T3 顺手补一条显式 flow 腿记录。
- **QD4（A19 票严重度标注不齐，观察）**：票面仅 W1🟡/W3⚪ 带严重度，五件未标注。
  主控修文职权；QA 对未标注五件的严重度旁注：W4=工具面小（A7 域）、W5=并入 N13 随
  N13 定级、W6/W7=PIE/remote 域观察级。

## 四、产物清单（QA 侧）

- 归档：`loop/reports/t24t2qa_census_recount.log`（四终窗+游戏日志全词表亲数）
- 复跑证据：`loop/t24-live-qa/`（17 件：console/editor 日志、walk-b2/b3/b5、
  offset/warn-line/warn-scan、boot-pid）
- 本报告：`loop/reports/t24-t2-qa.md`
- 零产品改动、零 buglist/roadmap/台账触碰；RUST_BACKTRACE 全程未设；QA 复跑窗与
  程序证据窗分离；QA 开工磁盘 14.97GiB→清理旧 fixture 构建缓存至 47.91GiB 后复跑。

## 五、放行建议

**PASS → 放行 T3 终验+文档轮**（13 格复跑 `t24-live.sh all` 全链+book
debugging-errors.md+A18 两处微修顺手+A19 处置面裁定素材）。随行移交主控四件：
①QD1——T3 census 对照纳入游戏日志全词表（7 条启动固有面）；②QD2——DF-W5「2 次」
修文为 4 条；③QD3——DF-W2 按旁证级采信或 T3 补显式 flow 腿记录；④QD4——A19 票
补齐五件严重度标注。T3 交接六条注意（程序报告 §六）QA 复核**全部可执行**：复跑口
径（注意 1）经 QA bindings 相段复跑实证；C3 cursor 面（注意 2）收尾亲证；A4 原子
替换判据（注意 3）、A1 fresh-open 结构（注意 4）、B4 两半（注意 5）均在终窗亲读。
