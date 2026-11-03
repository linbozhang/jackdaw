# T24 任务 3 QA 复核报告（独立复核——终验+文档轮）

> 复核对象：分支 `loop/t24-debug` @ **5e21c238**（T3 终验+文档轮）。基线 5992b700=T2
> closeout（T1 a5f9eb6f/T2 291e3a4d 及两轮 QA PASS 在档）。程序报告
> `loop/reports/t24-t3-report.md`；方案 `loop/plans/t24-debug-feedback.md` §四-T3+
> 决策 8(a)；T2 QA `t24-t2-qa.md`（QD1-QD4 定义源）；buglist A18/A19 票亲读。
> 复核日期 2026-11-03，平台 macOS arm64。**RUST_BACKTRACE 全程未设**（QA 会话回显
> [unset]；console-all.log 零 backtrace 字样）；QA 门禁窗在程序终验窗与程序门禁窗
> 全部关闭之后亲跑；全部数字**亲跑/亲数非转录**（门禁日志归档 `t24t3qa_*` 五件，
> census 由原始窗日志去 ANSI 后逐行复数）。

## 裁决：**PASS**（放行 T24 整体闭环）

- 程序偏差 D-a/D-c 复核**成立并接受**（两处 census delta 全归因；QD3 落法与零产品
  改动纪律一致）；D-b「无 DF 活体新样」属实。
- QA 新立偏差：**无**（零阻断、零新立；一处口径注记防误读，见 §九）。
- 「零产品改动轮」声明**属实**：`git diff --name-only 5992b700..5e21c238` 亲跑 69
  文件，`^(src/|crates/)` 差集=0 程序化亲证；buglist/roadmap/台账（loop/progress.md）
  零触碰亲证（A18「已落待主控结票」标注在程序报告 §三，票面未动）。

---

## 一、diff 面亲核 — ✅ 干净，零越面

69 文件构成亲数：**book 6**（debugging-errors.md 新章+SUMMARY.md 挂链+asset-references/
assets/material-overrides/play-in-editor 四处入链改）+ **loop/qa 1**（t24-live.sh QD1
头注）+ **loop/reports 9**（t24-t2-report.md QD2 勘误+t24-t3-report.md+`t24t3_*` 归档
7 件）+ **loop/t24-final 53**（终验证据）。产品树 `^(src/|crates/)` 0 文件（grep 亲证）。

> 口径注记（防误读）：任务面常写「book 五文件」，实际 6——material-overrides.md 是
> A18② 的落点，方案 §四-T3 明列「A18 两处 book 微修随触碰落」，与程序报告口径一致，
> **属预期面非越面**。

## 二、门禁亲跑 — ✅ 五门全绿（日志归档 `loop/reports/t24t3qa_*.log`）

| 门 | 结果（QA 亲跑） | 归档 |
|---|---|---|
| `cargo fmt --all -- --check` | EXIT=0，零 Diff（日志 0 字节） | `t24t3qa_gates_fmt.log` |
| `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | EXIT=0，0 warning/error 行（28 行 Checking/Finished 进度亲读） | `t24t3qa_gates_clippy_ws.log` |
| `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | EXIT=0，零行 | `t24t3qa_gates_clippy_phys.log` |
| `cargo test --workspace --lib` | **3073/3073**（59 条 `test result: ok` 行 awk 求和亲算；FAILED=0）——基线不变，零产品改动由数字亲证 | `t24t3qa_gates_libtests.log` |
| `cargo test -p jackdaw --test guards` | **248/248**（165.57s，亲跑） | `t24t3qa_guards.log` |

stage 不复跑——A6 家族口径接受（T1 基线 `t24t1_stage.log` 在档，562+10 环境红⊆修前
基线、10 腿隔离绿；本任务产品树 0 改动，无新增红面可入）。程序归档门禁日志的
"panicked" 字样亲核：libtests 恰 2 处均为测试名 `…_not_panicked … ok`，guards 0 处，
与报告注一致。

## 三、终验证据链抽核 — ✅ 13 格全 PASS，C3/A4/B5 全链闭合

- **39 腿判定表**（`t24t3_leg_verdicts.txt`）逐行亲读：C14+A13+B12=39 全 `_PASS`；
  console `PHASE_DONE all`（console-all.log:105）判定条目 41=B2_PANEL_ROW_GREEN 与
  B5_REMEDY_HONEST 各重判 1 次——与报告口径一致（T2 QA 先例同形）。
- **C3 六腿全链**：walk-c1「4 errors · first: src/lib.rs:2077:18」+6 个 Open 行钮；
  `c3-click-response.json` clicked:true target text="Open" kind=node（经行文本父节点，
  T1 附注执行）；walk-c3-landing「opened cursor at src/lib.rs:2077:18」；console:23
  「cursor processes before=0 after=2」；脚本 :688 `pkill -x Cursor` 收尾；
  C3_CURSOR_CLEANED PASS。与 T2 终窗四件（loop/t24-live/ 同名件）并排亲读**同格同形**
  （同汇总文本/同 click 形/同落地文本/同 before=0 after=2 console 行）。
- **A4 五腿全链**（console:51-60 判据行逐行亲读）：破写后 warn 线 1（want ≥1）→板
  汇总 1（want 1）→同 key 重载 0 新行→再破 1 新行→板汇总 2（want 2）。判据走**板
  汇总计数**（免疫 DF-W4 walk 膨胀——walk-a4/walk-a4-again 原始串 3/6 为膨胀值，去重
  文本 1 份系同 path 同文本所致，判据设计正确）。原子替换工艺脚本 :391-402 亲读
  （「broke {path} (atomic replace)」），T2 交接注意 3 执行属实。
- **B5 五要件**：console:80 guided warns=1 / misleading-remedy lines=0+warn 全文报
  注册定义拼写 `jackdaw_animation_runtime::graph::AnimationGraphRef`；w3 窗 remedy
  双因诚实文案亲读（「Rebuild the project if the type is new to it; … rewrite it to
  the definition module path」）；walk-b5 板行「RedEntity · …AnimationGraphRef
  (unknown type)」；console:85 GraphRef(def path)=0 vs Transform=17（组件不落）。
- 旁证快读：A1 四元组（a1-finding.json 六字段亲读：document/entity/component/field/
  kind/reference——恰为 MO2 覆盖路径破因的 Missing 行，同时旁证 A18① 语义）；
  B4 直跑半场 b4-direct-line.txt=游戏自身日志同一 warn 行。

## 四、census 对照复数 — ✅ 全窗对上，两处 delta 归因亲证

原始窗日志去 ANSI 后逐行复数（QA 亲跑，非转录）：

| 窗 | 原始 WARN+ERROR | keymap 噪声 | 归因表 | 判 |
|---|---|---|---|---|
| build w1 | 3+1=4 | 1 | 3 | ✓ 同形（C1 ERROR×1+C4 WARN×2，逐行亲读） |
| assets w2 | 5+5=10 | 1 | 9 | ✓ 同形（warn_on_load+MO1 固有+引擎 ERROR×5+asset_failures×2） |
| bindings w3 | 9+0=9 | 1 | 8 | ✓ 同形同序（B1×2/B2×1/B3×3/B5×2，误导行 0 亲 grep） |
| runtime w4 | 2+0=2 | 1 | 1 | ✓ DF-W6×1 同形复现；**DF-W5 panic 0 次**（间歇件，非回归非修复） |
| 游戏日志 | 6+0=6 | —（无） | 6 | ✓ QD1 口径：1 设计+5 启动固有 |

- **assets 3 open+2 watcher 拆分逐条重证**（带时刻亲读）：13:00:08.996→索引走查
  13:00:09.009（watcher，距 0.013s）/ 13:00:13.999→scene.open 13:00:13.029（0.97s）/
  13:01:48.065→open 13:01:47.078（0.99s）/ 13:01:56.048→走查 13:01:56.056
  （watcher，0.008s）/ 13:02:01.063→open 13:02:00.070（0.99s）——恰 3 open+2
  watcher，各 <1s，census 拆分**逐条成立**；asset_failures 恰 2 key（13:00:10.003+
  13:01:57.056）。
- **设计嘴逐字节**：T3 游戏日志 B4 行与 T2 原始 `loop/t24-live/b4-game-direct.log`
  亲 diff——同一行逐字节相同 ✓。
- **D-a② 游戏日志固有面漂移**：bind no-context 0 条亲 grep（T2 ×3 缺席）、terrain
  no-Camera3d ×1 新见、GhostComponent skip ×1+config 缺省 ×3 恒在——两侧皆启动面，
  无格骑其上，归因接受。
- **QD2 数字亲手复数**：弃置碰撞窗 6515×1+11469×2+14561×1=**4 条** ✓——勘误后的
  修文数字准确（原「2 次」确不准），勘误痕保留亲读（t24-t2-report.md:77-80）。
- **总计**：21 编辑器窗+6 游戏日志，全部归因零未归因——QA 复数与 census 表逐窗逐行
  对上。keymap 噪声四窗各恰 1 条亲验。

## 五、book 新章技术准确性 — ✅ 八节逐节对源码，零技术错误

`book/src/user-guide/debugging-errors.md` 八节逐节核（源码锚全亲读）：

| 节 | 书面主张 | 源码/证据锚（QA 亲读） | 判 |
|---|---|---|---|
| 五嘴地图·加载失败 | log「asset load failed: … -- showing the previous content」+状态条横幅+一次/版本+板节 | asset_failures.rs:121（log）、:126-128（notify_warn）、(path,mtime) 锁+新版本再说话（测试文档 :167-169 亲读） | ✓ |
| 五嘴地图·引用审计 | 载入汇总+asset.audit+文件卡 Missing References… | reference_audit.rs:505 文本逐字、:657 label、operators.rs:585 唯一调用点 | ✓ |
| 五嘴地图·覆盖失效 | 「material override:」warn+audit Missing 行四元组 | material_overrides.rs:102；reference_audit.rs:294 takes_string_path 入判据；a1-finding.json 活体四元组 | ✓ |
| 五嘴地图·构建失败 | 「Build failed - click for log」+自动聚焦+strip「N errors · first:」 | status_bar.rs:452、build_panel.rs:44 auto_focus、:329 汇总文本 | ✓ |
| 五嘴地图·游戏运行时 | 折叠四行/点击展开全 100 缓冲/三色经 kind | game_panel.rs:284、:886-888（W4 注记）、:1002 TEXT_ERROR/:1013 TEXT_WARNING | ✓ |
| Scene Problems 板 | 三节标题+破引用四钮+绑定行 Locate/Copy 无 Rebind+载入失败 Show/Copy+无 tab 拒改写 | missing_list.rs:191/197/203、:502-505、:274（Locate 仅实体在场）/:292、:396-397、:615「…is not open; open it first…」 | ✓ |
| 30 秒清单 | 探针六味序+回落 reveal+Build 面自聚焦+warning 不翻红 | build_diagnostics.rs:207-212（code→code-insiders→vscodium→cursor→windsurf→zed）、:289-295 open_with_desktop 回落；C4 腿活体 | ✓ |
| 游戏日志 | 1s 去重窗/32/窗/512/帧+两溢出明报（A5 后语义） | pie_log.rs:30/:34/:39；窗口溢出行文本逐字（:199-200）+once per window（overflow_reported :149/162/193）；排空溢出尾替换（:256-261 truncate+push） | ✓ |
| 未知类型/字段 | 未知字段 warn 三件套+板行+字段丢弃组件照落；未知类型指引报注册拼写+双因 remedy+**组件不落明说不归一**+汇总行一次/未变重载静音 | apply.rs:767-768、:330（tail-match）、:352-353、:167-168 remedy、:342-343 A8 注记「rebuild line does not belong here」；活体：B4 直跑 Transform 落 minus field（console:101）、B5 GraphRef=0 vs Transform 17（console:85）；B1_RELOAD_QUIET PASS | ✓ |
| 瞬态告警 | MO8 升读者法则（每嘴按失败身份一次） | 与 material-overrides.md MO8 注记一致；B4/B5 一次锁活体在档 | ✓ |
| Known edges | A19 七件逐件一行（DF-W2 按 QD3 旁证级一句） | DF-W1 源码复证（warn_on_load 唯一调用点 operators.rs:585）；七件与 buglist A19 逐条对上 | ✓ |
| Where this sits | 收口互链四章 | 四链全解析（见下） | ✓ |

**链接完整性亲跑（0 断链）**：SUMMARY.md:38 挂在 Play-in-editor(:37) 之后亲读；入链
四处亲点（asset-references.md:69/assets.md:163/material-overrides.md:104/
play-in-editor.md:166）；新章出链 4 文件链全可达+2 纯锚链
（#what-an-unknown-type-or-field-spelling-means ↔ 本章 :104 标题 slug 吻合）；
assets.md:131「## When a file is broken」被引节名存在。mdbook 本机亦未装——文件级
校验为可达性证明（与程序同口径；`mdbook build` 二次证明不适用）。

## 六、A18+QD 落账核 — ✅ 全部落账，改写与票面方向逐字对应

- **A18①**（asset-references.md:17-21 亲读）：「The paths inside a MaterialOverrides
  or InstanceMaterialOverrides map are references too, and the audit walks them with
  everything else: a broken override shows up as a Missing row naming the component's
  materials field」——**引用域+可发现性双覆盖** ✓，与源码语义一致（takes_string_path
  入审计判据+field=materials 四元组活体 a1-finding.json），互链 material-overrides.md
  在句。**建议结票**。
- **A18②**（material-overrides.md:109-117 亲读）：「the rewritten document wins on
  the next save and reopen — until then a live world keeps wearing the old path」；
  旧过诺括注「(or at once, on the tab the scene is open in)」已除（亲 grep 无残留）
  ——与 A11 增补两面第一手证据（rename 粘性 t23t2_rename_sticky.log+save wet2 面）
  一致，**既不过诺也不欠诺** ✓。**建议结票**。
- **QD1**：t24-live.sh:82-89 census 口径注记全文亲读（启动固有面不入格归因+游戏日志
  全词表入 census）——本轮 census 即按此口径执行（§四 已证）。已落 ✓。
- **QD2**：t24-t2-report.md:77-80 勘误痕保留+修文数字 4 条=QA 亲数 ✓。已落 ✓。
- **QD3**：落书形态=QA 两可选项中的前者（Known edges 一句，无显式 flow 腿）——与
  零产品改动纪律一致，旁证三件在档（脚本注释+终窗游戏日志 skip-warn 对比+t24bad.bsn
  留档）。接受 ✓。
- **QD4**：buglist A19 票（:556-558）亲读——七件严重度 W1🟡/W2🟡/W3⚪/W4⚪/W5🟡/
  W6⚪/W7🟡 已注，括注「严重度为主控 2026-11-03 依 QA QD4 补注」在档 ✓。已落 ✓。

## 七、纪律核 — ✅ 全过

- **RUST_BACKTRACE**：QA 会话 `env | grep -i rust` 空、门禁脚本内回显 [unset]；
  console-all.log 零 backtrace 字样。
- **窗分离时间线亲证**（文件 mtime）：终验窗末 w4 21:06:37 → census 21:14:53 →
  程序门禁 21:15:16-21:26:32 → 提交 21:30:06 → **QA 门禁在其后**（本轮五门）——A6
  分离两代维持。
- **df 门前**：QA 开工 47Gi（>15Gi）；程序报告 47Gi 在档。
- 产品树/buglist/roadmap/台账零触碰亲证（git status 干净+diff 面 grep）。

## 八、裁决与放行建议（素材判定给主控）

**PASS → 建议 T24 整体闭环**：①合入 main；②roadmap T24 勾选（第 26 个）；③分支
`loop/t24-debug` 删除。均主控职权。

- **A18 结票**：两处改写亲读与票面修复方向逐字对应（§六），建议结票。
- **A5/A8 票面修文素材**（票面仍 `- [ ]` 未勾，buglist :451/:500 亲读；修复本体
  T1 已落+book 后语义本轮已书）：A5 修复锚 `crates/jackdaw_runtime/src/pie_log.rs`
  :193-203（窗口溢出计数行+overflow_reported once-per-window）+:245-264（排空溢出
  尾替换）+单测 :352-369 亲读在档；A8 修复锚 `crates/jackdaw_bsn/src/apply.rs`
  :344-361（unknown_type_message 三态）+:367-384（report_unknown_type 板行+warn）
  +A8 注记 :342-343；终验 B5 五腿+book 节为活体。**判定：两票具备勾选条件**，勾选
  与票面修文留主控。
- **A19 七件吸收面建议**：④并入 A7 批次随手（工具域，票面已有）；⑤并 N13（同病灶，
  票面已有）；⑦与 A10 同域（票面已有）——维持。**DF-W1/W3 产品修复未启动的归属
  建议**：W1（reread 无摘要嘴）——独立小票或「下轮触碰 scenes/operators/
  external_watch 时顺手」口径（warn_on_load 唯一调用点已在档，修复面窄：reread 路径
  补同一摘要嘴）；W3（写窗中间态双 key）——harness 原子写已绕、⚪ 低危，建议维持
  A19 记档不单独开票（或与 W1 同域并票，两者同属载入摘要/一次锁域）。两者均不阻断
  T24 闭环。

## 九、QA 偏差清单

**零阻断、零新立。** 一处口径注记（非偏差）：任务面「book 五文件」实际 6（§一），
A18② material-overrides.md 为预期落点。程序 D-a 两处 delta 亲证归因成立（§四）、
D-b「无新样」属实（DF-W6 同形复现一次亲读）、D-c 落法接受（§六 QD3）。

## 十、产物清单（QA 侧）

- 门禁归档：`loop/reports/t24t3qa_gates_{fmt,clippy_ws,clippy_phys,libtests}.log` +
  `t24t3qa_guards.log`（五门亲跑）
- 本报告：`loop/reports/t24-t3-qa.md`
- 零产品改动、零 buglist/roadmap/台账触碰；RUST_BACKTRACE 全程未设；QA 门禁窗在
  程序终验窗/程序门禁窗全部关闭之后发起；QA 开工磁盘 47Gi。
