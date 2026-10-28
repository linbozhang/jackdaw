# T03 返工第 2 轮终验复验（QA）— 提交 `4a2cf332`（分支 `loop/t03-undo`，3 文件 +86/−1，HEAD/diff 亲核一致）

口径：`loop/reports/t03-r1-qa.md` §7 回流清单 + §8 闭口条件（registry 两项应答 + 新测试）。轮次：R1 复验（t03-r1-qa.md，FAIL）之后的第 2 轮复验。QA 只验不修。工作区干净（仅历轮遗留 `.gitignore` 本地改动 + 未跟踪 `buglist.md`）。

## VERDICT: PASS — R1 回流清单 4 项全部按最小集落实且证据真实；QA 四项复验（registry / 新测试 / diff+扫描 / quick 门）全绿；无新 🔴。T03 可合入 main 并勾 roadmap。

## 1. registry 重验（QA 独立复跑，真机 BRP，`loop/reports/t03r2qa-probe.ps1` → `t03r2qa-probe.log`，RESULT failures=0）

- 新构建亲跑：`cargo build -p jackdaw` EXIT:0 → 真机启动（临时工程 + `JACKDAW_OPEN_PROJECT`，端口 15820）→ `jackdaw/operators` 应答：
  - **`brush.extend_face_to_brush` allows_undo=false** ✅、**`pie.live_edit_save` allows_undo=false** ✅（R1 两项回流目标）；
  - 轮 1 九项复答 false：clip.delete_keyframes / clip.paste_keyframes / brush.join / pie.live_edits_apply_all / terrain.generate / terrain.erode / resource.insert / resource.remove / resource.set_field ✅；
  - 锚点 `entity.duplicate` / `entity.toggle_visibility` 仍 true（未误伤）✅。
- **11/11 + 2 锚点全 PASS**，与程序 `t03r2-probe.log`（failures=0）独立一致。

## 2. 新测试重验（QA 亲跑）

- **亲跑**：`cargo test --test guards the_extend_face_keybind_is_one_user_entry` → **1 passed, 0 failed, exit 0**（0.95s）。
- **红→绿对照**：`t03r2-red-run.log` 中该测试 stash 红 `left: 2, right: 1` @record_counts.rs:257 + 清单测试红 @:499（首个失败项 `brush.extend_face_to_brush`）——两个红证与修复一一对应，数字与任务书预告一致。
- **非恒真/非空跑排查**（任务书要求项）：
  - 断言组为纯行为断言：`depth == before+1`（恰一条；红日志 left:2 证明该断言在未修复时会失败）+ `assert_ne!(extended, before_text)`（文档真实变化）+ undo 后 `#ExtendBrush==1 && #TargetBrush==1`（双笔刷复原、target 不被吃）。若 impl 早退（无 push、无几何变化），前两个断言必挂——**不可能是空跑**。
  - 斜面前置（target cuboid 绕 Y 转 45° + x=3 平移）正确性：注释给出几何依据（轴对齐 cuboid 对的面法线 dot 全为 0/±1 → extend 的 angled 约束滤空、半空间交非盒 → 失败无 push；斜置后约束有界 → push 成立），程序报告披露经一次失败尝试后解出——绿跑中 depth+1 与 assert_ne 同时成立即「走到了 push 分支」的实证。前置搭建走 **Face 模式入口路径**（`EditMode::BrushEdit(Face)` + `active_brush` + `sub_mut().faces=[0]` + 双选），非 QA 预授权的「静态 Invoke 组合」替代——比授权口径更强。
  - 测试用 `user()`（`run_op_clause_as_user`，键位同路 history:true）派发，与 join 测试同款。

## 3. diff review（`git show 4a2cf332`，3 文件 +86/−1）

- `src/draw_brush/extend_face.rs`：+1 `allows_undo = false`（R1 🔴 项）。
- `src/live_edits.rs`：+1 `allows_undo = false`（R1 🟡 项，与 apply_all 处置对齐）。
- `tests/guards/record_counts.rs`：新测试 +79（断言质量见 §2）；`SELF_PUSHING` 50→**52**（brush.extend_face_to_brush、pie.live_edit_save 各带一行成因注释），清单测试同步钉死。
- **buglist R1 追笔**：核实两段备注在位（765b4599 键位路径尾巴 + 4a2cf332 返工 2 补齐，描述与 QA 实测事实一致——"QA 复验揪出的同型漏网，二层间接盲区"）。
- 本轮 diff 无任何逻辑改动（两 attr + 测试 + 注释），无新风险面。

## 4. 扫描复跑（QA 亲跑）

- **并入核实**：`loop/qa/scan-selfpush.ps1` 注释明示合并三方（r1 双脚本 + QA 间接扫描），代码体与 QA 的 `t03r1qa-scan-indirect.ps1`（fn 体一层 called-local-fn 归纳）逐行一致。
- **当前树复跑**：`powershell loop/qa/scan-selfpush.ps1` → **0 命中**（exit 0）——与 r1 树同逻辑扫描命中 2 项形成对照，0 命中恰由两行声明生效解释；程序另做过 sanity 反证（临时删 `resource.insert` 声明 → 扫描命中 → 还原 → 0 命中）。全仓无剩余未声明自推 op。

## 5. quick 门抽验

| 门 | 证据 | QA 处置 |
|---|---|---|
| fmt | 程序日志 `gate-fmt-t03r2.log` 为空文件、无独立行 exit code | **存疑 → 亲跑**：`gate-fmt-t03r2qa.log` **EXIT:0** ✅ |
| clippy | `gate-clippy-t03r2.log` 尾 "Finished in 15.12s"、无 exit 行 | **存疑 → 亲跑**：`gate-clippy-t03r2qa.log`（workspace+all-targets+dylib+`-D warnings`）**EXIT:0** ✅ |
| xtask fast | `gate-xtask-fast-t03r2.log` Summary：**2866 passed, 2 skipped**（33.562s） | 与 QA 上轮亲跑基线 2866 精确一致，不存疑 ✅ |
| xtask integration | `gate-xtask-integration-t03r2.log` Summary：**5074 passed, 2 skipped**（317.005s） | = 上轮亲跑 5073 + 1 新测试，精确吻合 ✅ |
| guards（附加） | `t03r2-guards-green.log`：**138 passed, 0 failed**（137+1） | 数字自洽 ✅ |

## 6. 结论

R1 判 FAIL 的两项回流目标（🔴 extend_face、🟡 live_edit_save）均已按最小集修复并有真实红→绿证据；QA 复跑 registry 11/11、亲跑新测试绿、合并扫描 0 命中、门禁四门全绿（两门存疑项已亲跑补证）、guards 138/138；本轮 diff 无新风险面，**无新 🔴**。

T03 整体（T1 + T2 + 返工 1 + 返工 2）至此满足终验 §7 放行面：roadmap T03 **建议勾选**。遗留（均已记录、不阻塞）：brush.join 的异步 recenter 位移不入撤销（程序建议另开 buglist 条目，QA 同意）。

**VERDICT: PASS**
