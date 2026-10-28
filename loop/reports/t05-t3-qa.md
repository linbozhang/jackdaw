# T05-T3 QA 终验报告：真机矩阵 + 工具 + 文档收尾（兼 T05 整体闭环判定）

- 角色：QA（只验不修）｜日期 2026-10-26｜分支 `loop/t05-final`，提交 **396073fa**（10 文件 +189/−10，`git show --stat` 亲核一致）
- 输入：`loop/reports/t05-t3-report.md`、`loop/plans/t05-reference-stability.md` §二 T3 + QA 清单、README 2026-10-25 门禁标准
- QA 归档：`gate-docbind2-t05t3qa.log`（bind solo 亲跑 1/1 EXIT 0）、真机复跑全程输出（launch/grid123/grid8/grid6/grid4579/grid10）与程序留档 `t05t3_grid*.log`、截图 `loop/reports/t05t3-live/`

---

## 一、三个即修缺口重点审：**无新 🔴**

### 缺口① IsA.source 重写特判（reference_rewrite.rs）
- **匹配面正确**：`is_source = data.type_path == ISA_TYPE`（**组件级**判定）+ 字段级 `is_source && field.name == "source"`——仅 IsA 组件的 source 字段被放行为引用，其它组件的同名 source 字段不受影响（`rewrite_value` 的放行条件 `takes_path || is_source || @`，is_source 布尔单独传参，与类型通道正交）。
- **红出机理闭环（代码考古）**：盘上 referrers 表的扫描源是 `asset_files.rs::spelled_references(text)`——**文本级宽进**（提取全部引号串经 `could_name_a_file` 过滤，不按类型），IsA.source 天然入 holders 集合；旧 rewrite 侧类型级严出不认 String source → `Some(0)` 不写盘 → grid 1 红出。修复使严出对齐宽进，且方向安全（宽进多算文档、严出少改字段——note 误伤防线不变）。**报告口径修正**：程序称「T1 的 scan 侧已有 ISA 特判」不实——`reference_rewrite::spelled_references`（:74-）并无该特判，真正兜住盘上侧的是 asset_files 的文本级扫描；不影响修复正确性。

### 缺口② prefab watcher 释放（prefab/watcher.rs :84-135）
- **同一机制、独立实现**：与 T1 的 `external_watch::release_watch_under` 语义同款（释放树内 watch、保留剩余、后续按 tab/cache 变化重建），但实现独立——external 版在旧 watcher 上 unwatch 树内条目，prefab 版**整体重建** watcher（kept 重挂 parent folders、`watched_canonical` 清空）——prefab 侧重建更彻底。rename_file/move_file 目录分支两处对称调用两个释放 ✓。⚪ 备案：两份同名函数分叉维护（两个 watcher 本是独立系统、State 结构不同，可接受；语义漂移风险记档）。窗口期漏检分析同 T1-R1 已审结论（重建有既定触发）。

### 缺口③ audit 只代入 dirty tab（reference_audit.rs :134-145）
- **语义合理**：干净 tab 的文档=盘上文件（T1 rename 联动对 tab 内存重写+基线重算保持等价；外部改盘由 external_watch reload prompt 守护差异呈现）——prefab tab 的 cache 快照在重开前滞后盘上，代入会报已修复引用为 Missing（grid 8 红出的真因）。dirty tab（有未保存编辑）仍代入内存文档 ✓。
- **防线缺口（⚪）**：guards 本轮只改了注释（backticks/emoji lint），dirty-only 无专门 headless 回归用例——证据为真机 grid8 红绿链；建议补「干净 prefab tab 不代入」guards 用例。

## 二、真机矩阵独立复跑：**10/10 全 PASS**

QA 独立复跑（重 build 后，六段全跑）：launch（PROJECT OPEN + Indexed 行）→ grid123 **5/5**（格1 盘上引用改名+旧路径消失、格2 move 重写、格3 文件夹前缀重写+盘上目录移动）→ grid8 **3/3**（audit Missing→rebind 落盘→audit 清空）→ grid6 **2/2**（非 force 文件原样+确认框列引用）→ grid4579 **7/7**（格4 tab retarget+save 只落新路径、格5 恰一文件、格7 非 force 拒/force 删+无残留 tab、格9 无 -1 副本）→ grid10 **1/1**（重导入后 audit 清）。与程序留档 t05t3_grid*.log 逐格 PASS 行一致。
- 备注 1：grid6 两轮断言路径不同——程序轮主断言（"Delete it anyway" 按钮）、QA 轮 fallback（"references" 文本行）均证实确认框在场且列引用；精确文案（前 3 名+余数）以程序轮主断言+截图 grid6-confirm.png 为准。
- 备注 2：QA launch 首跑失败为 **QA 自身环境**（此前 bind doctests 增量编译致 dylib-host deps 错配、exe 启动即死，零字节日志为证；重 build 25s 后全链通过）——非产品问题，如实记录。

## 三、全量门复核

| 门 | 归档 | QA 复核/亲跑 |
|---|---|---|
| fmt | t05t3_fmt.log 0 行 | ✓ |
| clippy | t05t3_clippy.log 25 行无 error（初跑 backticks lint 已修覆盖归档） | ✓ |
| lib | t05t3_lib.log 3523 行精确过滤零真失败 | ✓ |
| guards | g_refw 12/12 + g_audit 5/5 + g_rest 162/162 + g_perf 1/1（分治 180） | 归档零真失败 ✓ |
| xtask fast/integration | fast2 2986 行 / integration 5348 行，精确过滤零真失败（"error/failed"命中均为含此词的 PASS 测试名） | ✓ |
| xtask docs | 5 行，book 新节构建过 | ✓ |
| doctests | doctests4：**3 段** merged-harness error（jackdaw_bind / jackdaw_feathers / jackdaw_node_graph），0 段 failed>0、52 段显式 ok | bind solo **QA 亲跑 1 passed EXIT 0** ✓；docbind_main stash 实证 bind 在 main（a034595b）同败 ✓；**feathers/node_graph 两段未逐段 stash 实证**（程序报告只点名 bind，"52/55"数字涵盖 3 段；本轮 diff 未触碰这两 crate，同族既有推断成立）——⚪ 口径备注；程序"bind 3/3"实为 solo 1/1（数字小误，绿为事实） |

## 四、MCP 工具与 book 文档

- **MCP 第 23 工具 audit**：`brp_text("jackdaw/audit")` 与 recovery 同款薄翻译 ✓；description 内嵌 missing_list/rebind 调用指引（五参）✓；mcp_smoke tools/list 锁定表补 `recovery`（顺手补此前漏锁）与 `audit` 两行 ✓。
- **book「Asset References」节**（77 行）：路径即身份/无 GUID、Handle/@AssetRef/IsA.source 判据、@ 裸名歧义、rename/move 联动四点（结构级替换+普通串不动/tab 卡片跟随+干净脏两态/index 同 handle+大小写）、状态栏报告、删除确认/force/未保存编辑计入、audit（**"an open tab with unsaved edits stands in for its file"——与缺口③ dirty-only 口径同步**）、Missing 清单四按钮+未打开文档边界、外部改名「不猜 rename、改完 audit、编辑器内做最安全」——与实现逐点一致 ✓。⚪：文档判据未提 newtype/TupleStruct（MeshMaterial3d 形态，T2-R1 的 tuple_held_type）——口径少一类（用户视角影响小）。

## 五、buglist 与用户清单

- 七条全 `[x]`（:121 Y8、:241 Y31、:312 W7、:317 W8、:328 W10、:333 W11、:338 W12）+ 7 条 `> 已修复 6ba0ce4b/abf00a31` 备注（四条 T1、三条 T2），与历轮核对一致，无漏。
- 用户 30 秒清单三条在报告文末在位（改名照旧/删除看影响面/缺失重绑）。

## 六、T05 放行清单（方案 §二 T3 QA 清单四项）

1. **T1/T2/T3 各自验收全绿** ✓：T1 PASS（t05-t1-qa.md + 修复轮 1 重验 PASS）、T2 PASS（t05-t2-qa.md 修复轮 1 重验 PASS）、T3 本报告 PASS。
2. **N1/N3/Y8 红→绿** ✓：T1 `t05t1_red_run.log` 0 passed/10 failed 全断言失败（三者的用例在列、失败信息直指旧行为）→ 绿 10/10；Y8 另有 `renaming_an_open_clean_scene_retargets_its_tab` 及 R1 文件夹组合补强。
3. **「不丢引用」三腿铁证** ✓：旧路径不存在（guards 用例 1 `!old.exists` + 真机格 1/4）、引用串逐串比对（guards 用例 1/2 含新串+无旧串+note 不动 + 真机格 1/2/3）、重载 handle 指向新路径（guards 用例 1 `indexed_path==新路径`+metallic 不变 + 格 10 重导入同 handle 换值 audit 清）——三腿在 headless 与真机两侧均有落点。
4. **门禁按升级标准** ✓：全文复核为主（本轮 lib/fast/integration 精确过滤零真失败）、重跑覆盖归档（clippy backticks/doctests 初跑均已覆盖）、exit code 辅助。

## 七、T05 整体闭环判定

验收三句全落地：**改名移动不丢引用**（矩阵格 1-5 + guards rename/move/case/folder 全链 + 联动语义入 book）；**删除示影响面**（格 6/7 + 确认框列引用文档名 + open-tab 拒绝/force 关 tab）；**缺失可定位重绑**（asset.audit/missing_list/asset.rebind + MCP audit + 格 8 真机闭环）。裁决 8 项全部按方案落实（A 主体、operator 侧重写、状态栏+清单 UX、file.move、干净 tab 基线重算、N6 最小警示、Y31 吸收、删除守卫 A）。buglist 七条吸收闭环。残留备案（不阻塞）：⚪ dirty-only 无 headless 用例、prefab/external 两份 release_watch_under 分叉、book 未提 newtype 判据、doctests feathers/node_graph 两段未逐段 stash 实证、ui_click scale 工具层缺陷仍在 backlog（已由 asset.rebind operator 通道绕开）。

**VERDICT: PASS**（T05-T3 放行）

**T05 勾选建议：roadmap T05 可勾选完成**（T1/T2/T3 三任务 QA 全 PASS、放行清单四项齐、验收三句真机+headless 双侧闭环）。
