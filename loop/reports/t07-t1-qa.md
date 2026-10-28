# T07-T1 QA 验收报告：「staging 原子替换与目录防护」（只验不修）

> QA 角色产出，2026-10-24。分支 `loop/t07-export`，提交 `ef353c57`（父 `54cd5ce6` = main），
> 3 文件 +810/−65（export.rs 主体 / jackdaw_cli --force+skipped / game_export.rs 测试构造）。
> 程序报告：`loop/reports/t07-t1-report.md`（偏差 3 项已逐条裁定，见 §六）。
> 验收方法：红证日志逐条核对 + 绿侧亲跑 + 原子交换逐步 review + 双探针独立重跑 + 门禁归档复核。

## 一、红→绿真实性

红证 `loop/t07t1_red_run1.log`（未改动基线，**4 红 / 13 绿**）逐条核对，失败形态全部为
**旧缺陷的行为级铁证**（非存在性红证）：

| 用例 | 红形态（QA 日志核对） | 判定 |
|---|---|---|
| Y7 大小写变体 | `JACKDAW_EXPORT_CASE-GUARD... was accepted: could not read ...case-guard...\assets: os error 3`——变体被字节比较放行后**真删了 assets 源** | 铁证 ✅ |
| N1 exe 拷贝失败 | digest 对比：left（实际旧 dist）仅剩 2 个 assets 文件、**my-game.exe 没了** vs right（期望完整清单）——旧「先清空后拷」不保旧 | 铁证 ✅ |
| N1 交换锁 | `could not clear the existing staging directory ... os error 32`——旧 clear 语义（新代码文案改为 "move the previous export" 以保证红性确定） | 铁证 ✅ |
| N1 staging blocker | `unwrap_err() on an Ok value: ExportReport {... files: 4}`——旧无 staging 机制，注入无效导出直接成功 | 铁证 ✅ |

绿侧 **QA 亲跑**：`cargo test -p jackdaw_project_build --lib export` → **33 passed / 0 failed**
（含报告所述 export::tests 25 条+同过滤面其余 8 条，全绿）；归档 crate 全量 219/0 复核一致。

## 二、原子交换 review（重点）：无新 🔴

主链逐失败点（`stage_export`/`stage_into`/`swap_into_place`）：

| 步骤 | 失败语义 | 判定 |
|---|---|---|
| 打包（stage_into：assets 拷贝→exe 拷贝→写标记，先 assets 后 exe 次序保留） | 任一失败 → 删 staging、**旧 dist 原样**、错误上报（staging 在 parent 同级同卷，全程不碰 dist） | ✅ |
| 交换第一步（旧 dist rename → `.{profile}.trash-{unix_secs}-{n}`） | rename 原子性：失败=dist 未动，Err（锁测试注入点） | ✅ |
| 交换第二步（staging rename → dist） | 失败 → trash rename 回 dist（尽力恢复）+删 staging+Err（防御分支，无注入点——偏差②） | ✅ |
| 删 trash | 失败仅 `tracing::warn`（新导出已在位）+留给下次孤儿清理——**兜底测试钉住**（`staging_and_trash_leftovers_are_cleaned_on_the_next_export`：预置 `.release.staging-999`/`.release.trash-old` 被清） | ✅ |

- **staging 命名 `.{profile}.staging-{pid}-{n}`：pid 防多实例互踩** ✅；同进程残留由 unique_dir
  计数避让；trash 用时间戳+unique_dir（多实例并发导出同一 dist 本身为病态场景，非防护对象，可接受）；
- **unique_dir 文件占名语义**：目录占名→计数避让，**文件占名→直接返回该名让 create 响亮失败**
  （不静默后缀绕过）——正是红证 4 的注入点，设计意图与测试一致 ✅；
- **孤儿清理与 T04 族衔接**：`cleanup_orphan_exports` 每次导出先清本 profile 的 staging/trash
  **目录**（非目录异物不删、其它 profile 不误删——测试钉 `.dev.staging-1` 保留）✅；
- `normalize_staging_dir`：相对路径拒绝（防 `--out .`）、verbatim 简化、dot 组件拒绝——防 cwd 事故 ✅。

## 三、path_contains / 名单过滤 / 标记门 / assets_dir

1. **path_contains**（export.rs:512）：Windows **逐组件** `eq_ignore_ascii_case`（`C:\assets2`
   vs `C:\assets` 组件不等→不误伤；含盘符前缀），非 Windows 保持 `starts_with` 字节比较
   （`#[cfg]` 分开实现）；纯函数矩阵测试（同径异拼/相等/不同/反向/跨盘）在绿侧。✅
2. **名单过滤**：目录 `SKIPPED_ASSET_DIRS=[".jackdaw-pie"]` **精确等值**（Unix 变体不同目录不
   模糊伤）；文件 `is_editor_private_file`（`.bak` 后缀 / 含 `.tmp-` / 含 `.corrupt-`）；
   **用户合法 dot 文件不在名单=照常拷贝**（注释明示，决策 5-A 名单制本意达成）；skipped 每命中
   条目计 1、CLI 成功输出 skipped>0 打印可审计说明。✅
3. **标记门三态**（`output_dir_is_foreign`）：dist 不存在→放行；空目录→放行（首导出）；非空无
   标记→`ForeignOutputDir` 拒（文案点名 --force 与换 --out）；**文件形态视为非空拒**（read_dir
   Err→true）。force：`ExportPlan.force`+CLI `--force` **精确等值匹配**（`arg == "--force"`，
   不当路径读，parse 断言在 cli crate 绿侧）；**编辑器入口不暴露 force**（`plan_export` 签名
   不变、force 默认 false，game_export.rs 仅测试构造补 skipped——零行为改动核实）。✅
4. **assets_dir（R10）**：`plan_export` **内部读** `ProjectManifest::read(root).assets_dir()`
   （损坏 toml 回落 "assets"），`assets_staged_subdir` 跟随 manifest 相对路径（`dist/content`）；
   签名不变两调用方零改动（小定案执行核对 ✅）；测试 `an_assets_dir_override_is_staged_under_
   its_own_name`（dist/content 与源一致+无幻影 assets）。✅

## 四、门禁复核

| 门 | 归档 | 复核 |
|---|---|---|
| fmt | `t07t1_fmt.log` 0 字节 | ✅ |
| clippy | `t07t1_clippy.log` | 仅 5 条既有 build-script/linker 警告（历轮同款），无 error ✅ |
| project_build lib | `t07t1_green_final.log` | **219/0**（含 export 模块 25 新口径）✅ |
| cli lib | `t07t1_cli.log` | **18/0**（--force parse 断言含）✅ |
| jackdaw lib | `t07t1_lib.log` | **1167/0**（E0560 行系 game_export 失败路径测试注入样本）✅ |
| guards | `t07t1_guards.log` | **197/0** ✅ |
| QA 亲跑 | export 模块 | **33/0** ✅ |

## 五、偏差 3 项裁定

1. **「删 trash 中断」注入不可达（核心）——双探针论证实质成立**。QA 独立重跑
   `H:\workspace_AI\t07t1_probe{,2}.ps1` 实证：(a) 无 Delete share 句柄 **实际 DENIED 父目录
   rename**（访问被拒绝，IOException）；(b) RWD share 句柄同样 **RENAME-DENIED**；(c) readonly
   子文件不阻止父 rename 且现代删除完整清掉 trash；(d) share=Delete 句柄下树删除成功（POSIX 式）。
   结论链成立：**任何打开句柄都先挡住交换第一步 rename**（该步有测试），不存在「活着穿过第一步
   却令第三步删除失败」的 OS 级注入态 → warn+留置分支为防御代码、用户可见语义由孤儿清理测试钉住
   ——口径可接受。⚪ 附记：**探针 A 输出文本有缺陷**——`Rename-Item` 非终止错误在
   `$ErrorActionPreference='Continue'` 下未被 catch 接住，误打印 "RENAME-OK"（真实结论以错误流
   DENIED 为准；建议后续探针对被测 cmdlet 统一 `-ErrorAction Stop`，与 probe2 P1 写法对齐）。
2. **swap 第二步失败恢复分支无注入点**：目标位置刚被第一步腾空、同卷 rename 无现实失败面——
   防御代码+代码审查覆盖（QA 已 review 恢复分支 `rename(&trash, dist)` 尽力恢复语义）。同口径
   可接受 ✅。
3. **skipped == 4 vs 方案 ==3**：同一用例多覆盖 `.corrupt-`（名单第 4 成员），验收三件套
   （.bak/.jackdaw-pie/.tmp-）逐条断言均在内、计数语义与方案一致——覆盖更宽，接受 ✅。

## 六、buglist 台账核对

- **R10**：`[x]` + `> 已修复 ef353c57（T07-T1）`（manifest 内部读/staged 目录名跟随/签名不变+测试名）✅
- **Y7**：`[x]` + `> 已修复 ef353c57（T07-T1）`（path_contains 实现口径+红证形态+测试名）✅
- **W9**：历史勾（T04-T1 `> 已修复 160893e6`）未动，本任务无动作 ✅

## 七、QA 汇总

- 新发现 ⚪ ×1（探针 A 输出文本缺陷，不影响论证结论）；无 🔴 无 🟡。
- 改动面核实：确仅 3 文件（export.rs 833 行主体+cli 40 行接线+game_export.rs 2 行测试构造），
  无越界；工作区仅常规项（`.gitignore` 本地 `.mimosa/`+buglist.md 不入库），无插桩/残留。

## 八、PASS 条件核对

| 条件 | 判定 |
|---|---|
| 红绿真实（4 铁证核对+绿侧亲跑 33/0） | ✅ |
| 原子交换各步失败语义审清（打包/交换两步/删 trash/孤儿清理/pid/unique_dir 全核） | ✅ |
| review 无新 🔴（path_contains/名单/标记门/assets_dir 全过） | ✅ |
| 偏差 3 项有结论（双探针 QA 重跑实质成立/防御代码口径/skipped==4 接受） | ✅ |
| 门禁干净（六件归档+亲跑） | ✅ |

VERDICT: PASS
