# T24 任务 3 报告：终验 + 文档轮（13 格全链复跑全 PASS + book 新章 + A18/QD 落账）

> 分支 `loop/t24-debug` @ T2 closeout 5992b700 之上，本任务**产品树预期改动面=零**——
> 实际改动面：book（新章+挂链+四处交叉链接+A18 两处微修）+ loop 脚本头注释（QD1 口径
> 注记）+ loop 报告勘误（QD2）+ 本轮证据与报告归档。方案 `loop/plans/t24-debug-feedback.md`
> §四-T3+决策 8(a)；T2 报告 §六交接六条注意逐条执行（复跑口径/cursor 面/A4 原子写/
> A1 fresh-open 结构/B4 两半/DF 七件候裁）；T2 QA 放行建议四件移交（QD1-QD4）中 QD1/QD2
> 顺手落、QD3 落书、QD4 已由主控在 A19 票补注（buglist 亲读在档）。平台 macOS arm64；
> RUST_BACKTRACE 全程未设；真机窗与门禁窗分离（终验完成后才起门禁窗）；磁盘门前 47Gi
> （>15Gi 门槛）。终验证据目录 `loop/t24-final/`（T24_OUTDIR 参数化，53 件），归档前缀
> `t24t3_*`（loop/reports/ 七件）。

## 裁决：**13 格全 PASS**（39 腿零 FAIL，全链一次跑绿，无降级格）

`bash loop/qa/t24-live.sh all`（2026-11-03 20:53-21:09 本地，约 17 分钟，warm 缓存在场；
PHASE_DONE all 全量判定行=唯一归因来源，另有 console-all.log 全程在档）。逐格：

| 格 | 链 | 腿（全部 PASS） | 本轮绿面要点（对照 T2 终窗同形） |
|---|---|---|---|
| C1 | 编译 | C1_FOOTER_FAILED / C1_PIE_STATUS_FAILED / C1_ERROR_MOUTH_LOG | footer「Build failed - 」+`jackdaw/status` pie=failed+editor log ERROR「error[E0308] (src/lib.rs:2077:18)」三嘴齐 |
| C2 | 编译 | C2_PANEL_ARROWS / C2_PANEL_FAILED_FACE / C2_PANEL_AUTOFOCUSED | visible_only 走查含「--> src/lib.rs:2077:18」+「Build failed - 」（箭头在可见走查=Build tab 活动=自动聚焦自身面） |
| C3 | 编译 | C3_SUMMARY_PINNED / C3_ROWS_WITH_OPEN / C3_OPEN_CLICK_LANDED / C3_LANDING_STATUS_TEXT / C3_CURSOR_LAUNCHED / C3_CURSOR_CLEANED | 「4 errors · first: src/lib.rs:2077:18」汇总+行级 Open 钮；点击→「opened cursor at src/lib.rs:2077:18」+Cursor 拉起；腿后 pkill 收尾（交接注意 2 执行） |
| C4 | 编译 | C4_STATE_NOT_FAILED / C4_WARNING_IN_PANEL | 「Project built」在、「Build failed」零出现；warning 箭头在面板日志 |
| A1 | 资产 | A1_WARN_ON_LOAD / A1_AUDIT_FOUR_TUPLE / A1_OPERATOR_MOUTH | mv 后首开（fresh-open 结构维持，交接注意 4）：warn_on_load+四元组逐字段+operator 汇总 |
| A2 | 资产 | A2_BOARD_ROWS / A2_ROW_TEXT_MATCHES / A2_ROW_ACTIONS | Scene Problems 板 Broken references 节行文本=finding.line()+四钮；三色经远端 kind |
| A3 | 资产 | A3_LOCATE_SELECTS / A3_TAB_FORWARD | 清选中判增量→Locate→selection=AuditEntity+scene=t24a.bsn |
| A4 | 资产 | A4_FAILURE_ROW_ONE_MOUTH / A4_FAILURE_ROW_ONE / A4_LOCK_QUIET / A4_NEW_KEY_SPEAKS / A4_NEW_KEY_ROW_LANDED | 破写走脚本原子替换（交接注意 3）：恰 1 行/同 key 静音/新 mtime 再说+第二行 |
| B1 | 绑定 | B1_REMEDY_ONCE / B1_RELOAD_QUIET | remedy 一行+同文档重载静音（unchanged-remedy 锁） |
| B2 | 绑定 | B2_STRUCTURED_ROW / B2_PANEL_ROW_GREEN | 结构化 warn（实体#RedField+板指引）+Binding problems 行 |
| B3 | 绑定 | B3_BOTH_SECTIONS | 双节并存互不吞（scoped 审计判据=1） |
| B4 | 绑定 | B4_STRIP_FOUR_FACE / B4_EXPAND_FULL_LIST / B4_DIRECT_LOG_FACE | PIE 半场：折叠 4 行证抑旧+展开全 6 行；direct 半场：游戏二进制 assets/ 旁+15702 自守，游戏自身日志同一 warn 行（交接注意 5 执行） |
| B5 | 绑定 | B5_GUIDED_WARN / B5_REMEDY_HONEST / B5_PANEL_ROW / B5_COMPONENT_UNAPPLIED | 指引 warn 报注册定义拼写+双因诚实 remedy（误导行 0 次）+板行+组件不落（明说） |

39 腿逐名列档 `t24t3_leg_verdicts.txt`；腿数口径：39 唯一腿名（C14+A13+B12），
console 判定条目 41（B2_PANEL_ROW_GREEN 与 B5_REMEDY_HONEST 各重判 1 次，T2 QA 先例
同形，非偏差）。

## 一、warn census 对照（T2 终窗 → T3 终窗，同形+逐条归因）

全文 `t24t3_warn_census.txt`（QD1 口径已应用：游戏日志**全词表**入表）。逐窗：

| 窗 | T2 | T3 | 判 |
|---|---|---|---|
| build | 3 | 3 | 同形：C1 设计 ERROR ×1+C4 设计 WARN ×2 |
| assets | 9 | 9 | 同形：A1 warn_on_load ×1+MO1 固有 ×1+引擎 ERROR ×5（**3 open+2 watcher 逐行重证**，各距 OPERATOR/索引走查 <1s）+asset_failures ×2（恰两 key） |
| bindings | 8 | 8 | 同形同序：B1 ×2/B2 ×1/B3 ×3（含 t24b3 固有破引用+MO1 固有）/B5 ×2，误导行 0 |
| runtime | 2 | 1 | **唯一编辑器窗增量=DF-W5 缺席**：T2 终窗的 drain_game_events panic ×1 本轮 0 次——该件本就间歇（T2 弃置碰撞窗 4 条，见 QD2 勘误），非回归非修复，buglist A19⑤ 维持记档；DF-W6 ChildOf 悬空 WARN ×1 同形复现（T2 ×1→T3 ×1） |
| 游戏日志 | 8（1 设计+7 固有） | 6（1 设计+5 固有） | 设计嘴逐字节同一行（B4Entity unknown field）；固有面组成漂移：T2 的 bind no-context ×3 本轮缺席，本轮新见 terrain no-Camera3d ×1——两侧皆模板游戏启动面（GhostComponent skip ×1+config 缺省 ×3 恒在），随启动时序波动，无 T24 格骑其上 |

**总计：21 编辑器窗命中+6 游戏日志命中（1 设计+5 启动固有），全部归因，零未归因**；
keymap preset 噪声每窗 1 条按 T2 口径排除（四窗各 1 亲数）。编辑器侧唯一 delta（DF-W5
缺席）与游戏日志侧固有面组成漂移均已逐条落因。

## 二、book 新章 debugging-errors.md（决策 8(a)）

`book/src/user-guide/debugging-errors.md`（SUMMARY 挂在 Play-in-editor 之后）。结构：

- **The five mouths**：五嘴地图表（加载失败 T18/引用审计 T23 族/覆盖失效 MO1/构建失败/
  游戏运行时 T12——各自嘴形态+面板落点：Scene Problems 三节/Build panel 条/Game 条）。
- **The Scene Problems board**：入口（文件卡 Missing References…/asset.audit/远程 audit
  工具）+三节行形态与动作（Broken references 四钮/Binding problems Locate+Copy 无
  Rebind 及其理由/Asset load failures Show+Copy+一次锁语义）。
- **The thirty-second checklists**：三链 30 秒定位清单（编译坏一行→Build panel 汇总钉
  首错+行级 Open→探针表 code/code-insiders/vscodium/cursor/windsurf/zed 逐序+回落
  reveal；资产改名→板 Locate/Rebind；绑定坏字段→板行三件套+改写指引）。
- **The game's log**：条 4 行折叠/点击展开 100 条+节流三层诚实书（1s 去重窗+32/窗+
  512/帧排空）+**A5 修复后语义**（两溢出都明报：窗口溢出一窗一句计数行+排空溢出尾行
  替换，源码锚 pie_log.rs overflow_reported/两条 message 在档）。
- **What an unknown type or field spelling means**：**A8 修复后语义如实书**（定义模块
  全路径为准；re-export 拼写有指引 warn 报注册拼写；remedy 双因——真新类型才 rebuild/
  否则改写定义路径；**组件不装载，明说不归一**）。
- **Transient warnings at open time**：**MO8 同型注记**（打开瞬间告警=生成时序自清，
  material-overrides 章已注，此处升为跨嘴读者法则：每嘴按失败身份一次——文件版本/一次
  破坏/未变重载各说一次；重复=新失败，逗留=真告警）。
- **Known edges, stated as they are**：**A19 七件现状边界**逐件一行（DF-W1 reread 无
  摘要嘴/DF-W3 写窗中间态双行/DF-W4 ui_tree 计数膨胀/DF-W5 PIE 通道 drain panic/DF-W6
  PIE 收尾悬空关系/DF-W7 PIE 后直启失 remote 面；**DF-W2 游戏侧 flow 载入丢字段静默
  一句按 QD3 裁定落书**——编辑器有 warn 游戏侧暂无）。
- **Where this sits**：收口互链四章。

**交叉引用逐章核对可达**（链接完整性脚本亲跑：0 断链；mdbook 本机未装，文件级校验为
可达性证明）：SUMMARY.md 挂链+入链四章（assets.md 破文件节/assets chapter、
asset-references.md 引用定义节与 Missing References 节、material-overrides.md 瞬态段、
play-in-editor.md Build Game 段）各一句互链，出链（新章→四章+本章锚）全解析。

## 三、A18+QD 落账清单

- **A18①（已落待主控结票）**：`book/src/user-guide/asset-references.md` 引用定义段
  （原 :12 句）补 MO2 后例外一句——MaterialOverrides/InstanceMaterialOverrides 映射
  路径亦是引用且 audit 覆盖，破因以 `Missing` 行落在 `materials` 字段名下（互链
  material-overrides.md）。
- **A18②（已落待主控结票）**：`book/src/user-guide/material-overrides.md` rebind 段
  括注「(or at once, on the tab the scene is open in)」改文档赢语义——「rewritten
  document wins on the next save and reopen — until then a live world keeps wearing
  the old path」（A11 两面第一手证据口径）。
- **QD1（已落）**：`loop/qa/t24-live.sh` 头注释 census 段补口径注记——直跑游戏自身
  日志的启动固有面（T2 窗 8 条中 7 条）是模板游戏启动而非设计嘴：不入格归因，但游戏
  日志全词表入 census（本轮 `t24t3_warn_census.txt` 即按此口径执行）。
- **QD2（已落）**：`loop/reports/t24-t2-report.md` DF-W5 行「弃置的碰撞窗 2 次」一行
  勘误——实为 4 条（6515 ×1+11469 ×2+14561 ×1，QA 亲数），勘误痕保留，现象判定与
  N13 归票不变。
- **QD3（已落书）**：DF-W2 按「旁证级采信」落新章 Known edges 一句（编辑器 warn、
  游戏侧暂无），未补显式 flow 腿（QA 两可选路径中落前者）。
- **QD4**：A19 七件严重度已由主控补注（buglist 亲读在档：W1🟡/W2🟡/W3⚪/W4⚪/W5🟡/
  W6⚪/W7🟡），本轮无事。
- **A5/A8 修复后语义**：随新章落书（见 §二），票面修文留主控职权（本轮零 buglist
  触碰）。

## 四、门禁（全亲跑，日志归档 `t24t3_gates_*.log`+`t24t3_guards.log`）

| 门 | 命令 | 结果 | 归档 |
|---|---|---|---|
| 格式 | `cargo fmt --all -- --check` | EXIT=0 零 Diff | `t24t3_gates_fmt.log` |
| Lint 全仓 | `cargo clippy --workspace --all-targets --features dylib -- -D warnings` | EXIT=0，零 error/warning 行 | `t24t3_gates_clippy_ws.log` |
| 物理双包 | `cargo clippy -p jackdaw_physics -p jackdaw_avian_integration --all-targets -- --deny warnings` | EXIT=0，零行 | `t24t3_gates_clippy_phys.log` |
| libtests | `cargo test --workspace --lib` | **3073/3073**（基线 3073 不变——T3 零产品改动由数字亲证；逐包 ok 行在档） | `t24t3_gates_libtests.log` |
| guards | `cargo test -p jackdaw --test guards` | **248/248**（基线 248 不变，163.5s） | `t24t3_guards.log` |
| stage | 不复跑——A6 家族口径（基线亲证在档：`t24t1_stage.log` 562+10 环境红⊆修前基线，10 腿隔离全绿；本任务零产品改动，无新增红面） | — | 引 T1 在档 |

（日志中仅有的两处 "panicked" 字样=测试名 `…_not_panicked`，ok 行亲读，非失败。）

## 五、偏差清单（如实）

- **D-a（census 两处 delta，全归因非意外）**：①runtime 窗 DF-W5 缺席（间歇件，T2 终
  窗 1 次→T3 0 次，A19⑤ 记档维持）；②游戏日志固有面组成漂移（bind no-context ×3
  缺席/terrain no-Camera3d ×1 新见）——两侧皆启动固有面，随启动时序波动，设计嘴逐字
  节同形。零未归因。
- **D-b（本轮 DF 活体新样）**：无——DF-W1..W7 无一新增样，DF-W6 同形复现一次。
- **D-c（QD3 落法）**：QA 给出「旁证级采信**或**补显式 flow 腿」两可选，本轮落前者
  （book 一句）；理由：flow 腿的显式记录需动 runtime 相段触发结构，与 T3 零产品改动
  面纪律冲突，旁证三件（脚本注释记档+终窗游戏日志 skip-warn 对比+t24bad.bsn 留档）
  已在档。

## 六、产物清单

- 终验证据 `loop/t24-final/` 53 件（console-all.log/editor-all-w1..4-28925-.log 四终窗/
  walk-* 全格/b4-game-direct.log/offset 与 warn-line 件/warn-scan-all.txt/boot-pid）
- 归档 `loop/reports/` 前缀 `t24t3_*` 七件：`t24t3_warn_census.txt`（QD1 口径全文）、
  `t24t3_leg_verdicts.txt`（39 腿判定制表）、`t24t3_gates_{fmt,clippy_ws,clippy_phys,
  libtests}.log`、`t24t3_guards.log`
- book：新章 `book/src/user-guide/debugging-errors.md`+SUMMARY 挂链+四章互链
- 修文：`loop/qa/t24-live.sh`（QD1 口径注记）、`loop/reports/t24-t2-report.md`（QD2 勘误）
- 未动：产品源码零改动（`git status` 产品树差集=0 亲证）；buglist/roadmap/台账零触碰
  （A18「已落待主控结票」标注在本报告 §三，不动票面）；RUST_BACKTRACE 全程未设；
  A7/A9/A10/A14/A16 未前置（面板判据全文本锚+结构化远端锚；budget/jackdaw/wait 重试
  窗；PIE 指针转发未触碰；三色经远端 kind；模板零改动）

## 七、给 QA 的注意

1. **复跑口径**：本轮 13 格全链一次跑绿（warm 缓存约 17 分钟）；`all` 含 prep 重置
   fixture（jd new 重生成+材料重 mv），与 T2 报告注意 1 的「重 prep 重 mv」描述一致
   ——复跑无需手工清场，脚本自愈在位。
2. **census 对照基线换成 t24t3**：下一轮对照请以 `t24t3_warn_census.txt` 为基线
   （QD1 口径已在表内：游戏日志全词表+固有面单列）；DF-W5 间歇性预期为「有则记档、
   无则非偏差」，勿按 T2 终窗的「必有 1 条」口径判。
3. **game-log 固有面**：terrain no-Camera3d 与 bind no-context 的此消彼长是启动时序
   面（D-a②），判「同形」时以「设计嘴逐字节同+固有面可归因」为准，不逐条数目相等。
4. **A18 结票素材**：两处改写全文见本报告 §三（与 buglist A18 修复方向逐字对应）；
   票面勾选留主控。
5. **book 校验**：本机无 mdbook 二进制，可达性以文件级链接校验（0 断链）+SUMMARY 挂
   链亲读为证；若 QA 侧有 mdbook，跑一遍 `mdbook build` 可作二次证明。

## 八、遗留项

- A19 七件候裁吸收面（主控职权）；DF-W1/W3 产品侧修复未启动（T2 交接注意 6 维持）。
- A18 结票（两处已落，票面勾选待主控）；A5/A8 票面修文待主控（修复本体 T1 已落，
  book 语义本轮已书）。
- stage 门不复跑口径随 A6 家族维持（D6 在档）；若主控要求抽腿，`--exact` 隔离即可
  （T1 QA 先例三簇亲跑绿）。
